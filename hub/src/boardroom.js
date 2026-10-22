// One board's live room: everybody who has it open, and the one door its
// changes go through.
//
// **Why it exists.** His ask, 2026-09-25: "live collaboration features to the
// look board, so people can see changes in real time." A board used to be
// asked for every eight seconds and saved whole, the last save winning. Now
// each board has a room — a Cloudflare Durable Object, one per board — that:
//
// 1. **Takes every change, one at a time.** A browser sends what it changed
//    (`public/boardpatch.js`); the room lays it on the board as it stands and
//    keeps it. Two changes arriving together are laid one after the other,
//    never both on the same old copy, so neither is lost. The MCP's changes
//    come through here too (`writeBoard` in `boards.js`).
// 2. **Tells everyone at once.** Every browser with the board open holds a
//    line to the room; a kept change is passed down every line the moment it
//    is kept, and each browser lays it on its own copy.
// 3. **Knows who is here.** A browser says its name and where its pointer is;
//    the room passes that on to the others and keeps none of it.
//
// The board itself stays where it always was, in the bucket, with its
// history (`saveBoard`). The room keeps nothing of its own, so it can sleep
// between changes and wake without losing anything but who is looking.

import { applyOps, opsProblem } from "../public/boardpatch.js";
import { readBoard, saveBoard } from "./boards.js";

const COLOURS = ["#E0B04A", "#6FA8DC", "#8FBF7A", "#D98BA6", "#B59BE0", "#E5896A", "#5FC4B8", "#C9C06A"];

export class BoardRoom {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    // **One change at a time.** A Durable Object runs one request at a time
    // only until it waits on something outside itself — the bucket — so the
    // queue is ours to keep.
    this.line = Promise.resolve();
  }

  one(work) {
    const run = this.line.then(work, work);
    this.line = run.catch(() => {});
    return run;
  }

  /** Everyone on the board, as the others see them. */
  present() {
    const out = [];
    for (const ws of this.state.getWebSockets()) {
      const me = ws.deserializeAttachment() || {};
      if (me.id) out.push({ id: me.id, name: me.name, colour: me.colour, edit: me.edit });
    }
    return out;
  }

  tell(message, except = "") {
    const text = JSON.stringify(message);
    for (const ws of this.state.getWebSockets()) {
      const me = ws.deserializeAttachment() || {};
      if (except && me.id === except) continue;
      try { ws.send(text); } catch { /* a line already dropped */ }
    }
  }

  async fetch(request) {
    const url = new URL(request.url);
    const project = request.headers.get("x-board-project") || "";
    const name = request.headers.get("x-board-name") || "";

    // ---- a browser opening its line ----
    if (url.pathname === "/live") {
      if (request.headers.get("upgrade") !== "websocket") return new Response("A live line only.", { status: 426 });
      const [near, far] = Object.values(new WebSocketPair());
      const taken = new Set(this.present().map((p) => p.colour));
      const me = {
        id: url.searchParams.get("me") || crypto.randomUUID().slice(0, 12),
        name: (request.headers.get("x-board-who") || "Guest").slice(0, 60),
        colour: COLOURS.find((c) => !taken.has(c)) || COLOURS[Math.floor(Math.random() * COLOURS.length)],
        edit: request.headers.get("x-board-edit") === "1",
      };
      this.state.acceptWebSocket(near);
      near.serializeAttachment(me);
      near.send(JSON.stringify({ t: "hello", me, here: this.present().filter((p) => p.id !== me.id) }));
      this.tell({ t: "join", who: me }, me.id);
      return new Response(null, { status: 101, webSocket: far });
    }

    // ---- a change, laid on the board as it stands ----
    if (url.pathname === "/patch") {
      const asked = await request.json();
      const wrong = opsProblem(asked.ops);
      if (wrong) return Response.json({ said: wrong }, { status: 400 });
      return this.one(async () => {
        const cur = await readBoard(this.env, project, name);
        const prev = cur.at || "";
        if (!asked.ops.length && !asked.copy) return Response.json({ at: prev, prev });
        const next = applyOps(cur, asked.ops);
        const at = await saveBoard(this.env, project, name, next, asked.by || "", Boolean(asked.copy));
        this.tell({ t: "ops", ops: asked.ops, prev, at, by: asked.by || "", from: asked.from || "" }, asked.from || "");
        return Response.json({ at, prev });
      });
    }

    // ---- the board replaced whole: a version put back ----
    if (url.pathname === "/put") {
      const asked = await request.json();
      return this.one(async () => {
        const prev = (await readBoard(this.env, project, name)).at || "";
        const at = await saveBoard(this.env, project, name, asked.board, asked.by || "", Boolean(asked.copy));
        this.tell({ t: "reload", at, by: asked.by || "", from: asked.from || "" }, asked.from || "");
        return Response.json({ at, prev });
      });
    }

    return new Response("No such door.", { status: 404 });
  }

  /**
   * **What a browser says down its line is only where it is** — its pointer,
   * the cards it is holding. Passed on to the others, kept by nobody. Changes
   * to the board never come this way: they go through `/patch`, where the
   * portal has already checked who may make them.
   */
  async webSocketMessage(ws, message) {
    if (message === "ping") { ws.send("pong"); return; }
    let said;
    try { said = JSON.parse(message); } catch { return; }
    if (!said || said.t !== "here") return;
    const me = ws.deserializeAttachment() || {};
    const out = { t: "here", id: me.id };
    if (said.at && Number.isFinite(said.at.x) && Number.isFinite(said.at.y)) out.at = { x: Math.round(said.at.x), y: Math.round(said.at.y) };
    else if (said.at === null) out.at = null;
    if (Array.isArray(said.holding)) out.holding = said.holding.filter((x) => typeof x === "string").slice(0, 200);
    // Where the held cards are this moment, so the others watch them move.
    if (said.moving && typeof said.moving === "object") {
      const moving = {};
      for (const [id, xy] of Object.entries(said.moving).slice(0, 60)) {
        if (Array.isArray(xy) && Number.isFinite(xy[0]) && Number.isFinite(xy[1])) moving[id] = [Math.round(xy[0]), Math.round(xy[1])];
      }
      out.moving = moving;
    }
    if (typeof said.open === "string" || said.open === null) out.open = said.open;
    this.tell(out, me.id);
  }

  async webSocketClose(ws) {
    const me = ws.deserializeAttachment() || {};
    try { ws.close(); } catch { /* already gone */ }
    if (me.id) this.tell({ t: "leave", id: me.id }, me.id);
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }
}
