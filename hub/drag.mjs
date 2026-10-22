#!/usr/bin/env -S node --experimental-websocket
/**
 * **Whether the rail can actually be dragged**, in a browser that can actually
 * drag.
 *
 * Ref 870. `checks.sh` holds everything underneath the feature — who may save an
 * order, what a key may be, that the rail comes back in that order — and it
 * cannot see the one thing the feature *is*: a pointer picking a row up and
 * putting it somewhere else. Every check in that file asks the worker a
 * question over HTTP; nothing there has a pointer.
 *
 * So this drives real pointer events through Chrome's own input pipeline —
 * `Input.dispatchMouseEvent`, not a synthesised `PointerEvent` from a script,
 * which would prove that `arrange.js` responds to events rather than that a
 * mouse produces them. Then it **reloads the page** and reads the order back,
 * because a rail that shows the new order and forgot to save it looks exactly
 * like one that worked.
 *
 * The same shape as `motion.mjs`, and for the same reason: the Browser pane in
 * an agent session reports the document hidden, and a hidden document is not a
 * browser you can trust about anything that moves.
 *
 *     hub/drag.mjs
 *
 * It starts its own hub on 8789 against a throwaway bucket, drags, and stops
 * everything after. Screenshots land in /tmp.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const PORT = 8789;
const DEBUG = 9345;
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(58)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(58)} FAIL — ${why}`); };

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

/** One film, with two of his own pages on it so there is something to move. */
function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "drag-"));
  const put = (key, body) => {
    const file = join(box, "one.json");
    writeFileSync(file, body);
    spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
      "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  };
  put(`p/${FILM}/manifest.json`,
    JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
  put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
  put(`p/${FILM}/front.json`, JSON.stringify({
    version: 1, status: "Active", type: "Narrative", length: "Short",
    director: "Clara Moreau", ratio: 1.85,
    logline: "A film long enough to give the page something to hold.",
    updated: new Date().toISOString(),
    mark: { path: "", colour: "#D44C47" },
    camera: {}, counts: { scenes: 22, shots: 56, locations: 7, boards: 3, days: 3 },
    crew: [{ name: "Ellis Ward", role: "Gaffer", department: "G&E" }],
    documents: [],
    sections: [
      { slug: "lighting-plan", name: "Lighting Plan", title: "", by: "mcp", source: "here" },
      { slug: "safety-briefing", name: "Safety Briefing", title: "" },
    ],
    // **One heading of his own**, so the drag has somewhere to file a row into
    // rather than only somewhere to put it.
    //
    // **Rows that are there.** Ref 1463: it named `bible` and `boards`, which
    // have nothing on this film, and since 2026-09-23 an empty page is not in
    // the rail ("nothing there, nothing offered") — so the heading had no rows
    // and was not drawn either. A heading is only checked over rows that show.
    groups: [{ name: "Creative", rows: ["shotlist", "people"] }],
  }));
  rmSync(box, { recursive: true, force: true });
}

async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1400,950", "about:blank"], { stdio: "ignore" });
  try {
    let targets = null;
    for (let i = 0; i < 80 && !targets; i++) {
      await wait(150);
      try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch {}
    }
    if (!targets) throw new Error("the browser never answered — is Playwright's Chromium cached?");
    const page = targets.find((t) => t.type === "page");
    const ws = new WS(page.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
    await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
    let id = 0;
    const waiting = new Map();
    ws.on("message", (m) => {
      const said = JSON.parse(m);
      if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
    });
    const ask = (method, params = {}) =>
      new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable");
    return await run(ask).finally(() => ws.close());
  } finally {
    proc.kill();
  }
}

const state = mkdtempSync(join(tmpdir(), "drag-state-"));
say("Putting one film in a local bucket…");
seed(state);
say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state,
   "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  await browser(async (ask) => {
    const js = async (expression) => {
      const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return got.result?.result?.value;
    };
    const open = async (where) => {
      await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}${where}` });
      await wait(2200);
    };
    const shot = async (name) => {
      const got = await ask("Page.captureScreenshot", { format: "png" });
      writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
      say(`  → ${join(shots, name)}`);
    };
    const rail = () => js(
      `JSON.stringify([...document.querySelectorAll('.sections .to[data-key]')].map(e => e.dataset.key))`);
    /** The rail as headings and what is under each — what a drag actually files. */
    const filed = () => js(`JSON.stringify([...document.querySelectorAll('.sections > .group[data-head]')]
      .map(g => [g.dataset.head, [...g.querySelectorAll(':scope > .to[data-key]')].map(e => e.dataset.key)]))`);

    // ---- the rail, dragged ------------------------------------------------
    await open(`/f/${FILM}`);
    const before = JSON.parse(await rail() || "[]");
    say(`\n  rail as it arrives: ${before.join(" · ")}`);
    // **Exactly the four that have something on them.** Not "at least eight":
    // that was the count when empty pages were drawn too (Ref 1463), and it
    // said nothing about *which* rows. Bible and Boards have nothing here and
    // stay out; the written pages, the shot list and People are in.
    const wanted = ["lighting-plan", "people", "safety-briefing", "shotlist"];
    JSON.stringify([...before].sort()) === JSON.stringify(wanted)
      ? ok("the rail draws with every row keyed")
      : no("the rail draws with every row keyed", `got ${before.join(", ")}`);

    // Pick up the last row and carry it to the top of the list.
    const box = (key) => js(`(() => {
      const r = document.querySelector('.sections .to[data-key="${key}"]').getBoundingClientRect();
      return JSON.stringify({ x: Math.round(r.left + r.width / 2), y: Math.round(r.top + r.height / 2) });
    })()`);
    const from = JSON.parse(await box(before[before.length - 1]));
    const to = JSON.parse(await box(before[0]));

    // **`button: "none"` on a move, and `left` only on the press and release.**
    // A move is not a button transition; saying it is makes Chrome deliver the
    // first one and quietly swallow every one after it — measured, not guessed.
    const mouse = (type, x, y) => ask("Input.dispatchMouseEvent", {
      type, x, y,
      button: type === "mouseMoved" ? "none" : "left",
      buttons: type === "mouseReleased" ? 0 : 1,
      clickCount: type === "mouseMoved" ? 0 : 1,
      pointerType: "mouse",
    });
    await mouse("mousePressed", from.x, from.y);
    // **Step by step, not in one jump.** A drag is a sequence; `arrange.js`
    // only becomes a drag after the pointer has travelled, and one leap would
    // exercise a path a hand never takes.
    const steps = 14;
    for (let i = 1; i <= steps; i += 1) {
      await mouse("mouseMoved", from.x, Math.round(from.y + ((to.y - 6) - from.y) * (i / steps)));
      await wait(25);
    }
    (await js("document.querySelectorAll('.moving').length")) === 1
      ? ok("a row picked up says it is being moved")
      : no("a row picked up says it is being moved", "nothing is marked");
    await shot("shotlister-rail-mid-drag.png");
    await mouse("mouseReleased", from.x, to.y - 6);
    await wait(700);

    const after = JSON.parse(await rail() || "[]");
    say(`  rail after the drag: ${after.join(" · ")}`);
    after[0] === before[before.length - 1]
      ? ok("a dragged row lands where it was dropped")
      : no("a dragged row lands where it was dropped", `${after[0]} is on top, not ${before[before.length - 1]}`);

    // **Dropped above `bible`, it is under his own heading now** — which is the
    // whole of "divide things up per project as I want". His instruction,
    // 2026-09-08.
    const under = JSON.parse(await filed() || "[]");
    say(`  filed as: ${JSON.stringify(under)}`);
    (under[0] || [])[0] === "Creative" && (under[0][1] || []).includes(before[before.length - 1])
      ? ok("…and is filed under the heading it was dropped into")
      : no("…and is filed under the heading it was dropped into", JSON.stringify(under));

    // **The one that matters.** A rail showing the new order and having failed
    // to save it is indistinguishable from one that worked, until a reload.
    await open(`/f/${FILM}`);
    const kept = JSON.parse(await rail() || "[]");
    say(`  rail after a reload:  ${kept.join(" · ")}`);
    JSON.stringify(kept) === JSON.stringify(after)
      ? ok("…and the film remembers it after a reload")
      : no("…and the film remembers it after a reload", kept.join(" · "));
    // Headings with rows only: an editor also sees a category with nothing in
    // it, and whether one shows depends on pages hidden as empty, not the drag.
    const full = (list) => JSON.stringify(list.filter((g) => g[1].length));
    full(JSON.parse(await filed() || "[]")) === full(under)
      ? ok("…headings and all")
      : no("…headings and all", await filed());
    (await js(`document.querySelector('.grouphead') ? document.querySelector('.grouphead').textContent : ""`)) === "Creative"
      ? ok("…and the heading is drawn over them")
      : no("…and the heading is drawn over them", "no heading");

    // **A press is still a press.** Every row here is a link somebody means to
    // open far more often than they mean to move it.
    const where = await js(`(async () => {
      document.querySelector('.sections .to[data-key="lighting-plan"]').click();
      await new Promise(r => setTimeout(r, 1200));
      return location.pathname;
    })()`);
    String(where).endsWith("/lighting-plan")
      ? ok("…and a plain click still opens the page")
      : no("…and a plain click still opens the page", String(where));

    // **The program's rail is the same rail**, drawn by `public/film.js` in the
    // browser instead of by the worker — two copies of one order, and the
    // failure if they drift is that the same film reads differently depending
    // on which door you came in. So it is read here rather than reasoned about.
    await open(`/f/${FILM}/shotlist`);
    await wait(2500);
    const inside = JSON.parse(await rail() || "[]");
    say(`  rail inside the app:  ${inside.join(" · ")}`);
    inside[0] === kept[0]
      ? ok("…and the program's rail agrees with the record's")
      : no("…and the program's rail agrees with the record's", inside.join(" · ") || "no rail at all");
    (await js(`Boolean(document.querySelector('.rail[data-arrange]'))`))
      ? ok("…and it can be dragged in there too")
      : no("…and it can be dragged in there too", "no mark on the rail");

    // **A written page is one he can write.** His report, 2026-09-08: *"All of
    // the options under the written page add ... have no function."* The box is
    // the function, and it is a plain form — but whether an editor is shown one
    // on an empty page, and a viewer is not, is a thing only a browser sees.
    await open(`/f/${FILM}/add`);
    await js(`(() => {
      const f = document.querySelector('.namefield');
      f.value = "Rigging Notes";
      f.dispatchEvent(new Event("input", { bubbles: true }));
      document.querySelector('.addform .savebtn').click();
      return 1;
    })()`);
    await wait(2500);
    const born = await js(`JSON.stringify({
      at: location.pathname,
      sub: document.querySelector('.pmnote') && document.querySelector('.pmnote').textContent,
      box: Boolean(document.querySelector('.writebox textarea')),
      notice: document.querySelector('.empty') && document.querySelector('.empty').textContent,
    })`);
    const made = JSON.parse(born);
    made.at.endsWith("/rigging-notes") && made.sub === "Written here" && made.box && !made.notice
      ? ok("a new written page opens with a box to write in")
      : no("a new written page opens with a box to write in", born);
    await shot("shotlister-written-new.png");

    await js(`(() => {
      const t = document.querySelector('.writebox textarea');
      t.value = ["## Day one", "", "Rig the 12K before call.", "",
                 "- Genny at the back gate"].join(String.fromCharCode(10));
      document.querySelector('.writebox .savebtn').click();
      return 1;
    })()`);
    await wait(2600);
    const drawn = await js(`document.querySelector('.inner') ? document.querySelector('.inner').innerText : ""`);
    String(drawn).includes("Day one") && String(drawn).includes("Genny at the back gate")
      ? ok("…and what he types is on the page")
      : no("…and what he types is on the page", String(drawn).slice(0, 120));
    await shot("shotlister-written-saved.png");

    // **Since Ref 1153 the box is a panel of the page menu**, not a fold under
    // the words: a page with words on it shows them, and Write (a menu item
    // pointing at `#pa-write`) opens the box, filled with what is there.
    await open(`/f/${FILM}/rigging-notes`);
    const again = await js(`(() => {
      if (!document.querySelector('.pmitem[href="#pa-write"]')) return "";
      const t = document.querySelector('#pa-write .writebox textarea');
      return t ? t.value : "";
    })()`);
    String(again).startsWith("## Day one") && String(again).includes("- Genny")
      ? ok("…and opening it again shows what is there, not an empty box")
      : no("…and opening it again shows what is there, not an empty box", JSON.stringify(String(again).slice(0, 80)));

    // **Filing at the END of a heading, which is what he could not do.** His
    // report, 2026-09-08: *"I can't drag anything on the left sidebar
    // underneath the headings."* The drop asked *which row do I sit above*
    // across the whole rail, so the last slot of a group followed by another
    // group did not exist — anything aimed there landed in the next group.
    await open(`/f/${FILM}`);
    const startAt = JSON.parse(await filed() || "[]");
    say(`  before: ${JSON.stringify(startAt)}`);
    const lastOfFirst = startAt[0][1][startAt[0][1].length - 1];
    const firstOfNext = (startAt[1] || [])[1][0];
    const from2 = JSON.parse(await box(firstOfNext));
    const to2 = JSON.parse(await box(lastOfFirst));
    await mouse("mousePressed", from2.x, from2.y);
    for (let i = 1; i <= 10; i += 1) {
      await mouse("mouseMoved", from2.x, Math.round(from2.y + ((to2.y + 4) - from2.y) * (i / 10)));
      await wait(25);
    }
    await mouse("mouseReleased", from2.x, to2.y + 4);
    await wait(900);
    const endAt = JSON.parse(await filed() || "[]");
    say(`  after:  ${JSON.stringify(endAt)}`);
    (endAt[0][1] || []).includes(firstOfNext)
      ? ok("a row can be filed at the end of a heading, not only above its rows")
      : no("a row can be filed at the end of a heading, not only above its rows", JSON.stringify(endAt));

    // **And the two tools are not rows of the film.** His instruction: they are
    // utilities, and being in the list said they were pages.
    (await js(`JSON.stringify({
      inlist: Boolean(document.querySelector('.sections .to.add')),
      tools: [...document.querySelectorAll('.railtools .railtool')].map(a => a.textContent.trim()),
      draggable: document.querySelector('.sections .to[data-key]').getAttribute('draggable'),
    })`)) && (() => true)();
    const furniture = JSON.parse(await js(`JSON.stringify({
      inlist: Boolean(document.querySelector('.sections .to.add')),
      tools: [...document.querySelectorAll('.railtools .railtool')].map(a => a.textContent.trim()),
      draggable: document.querySelector('.sections .to[data-key]').getAttribute('draggable'),
    })`));
    !furniture.inlist && furniture.tools.length === 0
      ? ok("…and Add and Headings are not rows in the list, nor phone-only tools")
      : no("…and Add and Headings are not rows in the list, nor phone-only tools", JSON.stringify(furniture));
    furniture.draggable === "false"
      ? ok("…and a row refuses the browser's own link drag")
      : no("…and a row refuses the browser's own link drag", String(furniture.draggable));

    // **Proof it is a swap and not a reload**, which is the whole of his
    // complaint: *"every click is a completely new save and reload situation."*
    // A mark put on the window survives a swap and cannot survive a page load,
    // so this cannot pass by accident.
    await open(`/f/${FILM}/safety-briefing`);
    await js(`(() => { window.__stillHere = "yes"; return 1; })()`);
    const took = await js(`(async () => {
      const at = performance.now();
      document.querySelector('form.srcset input[value="notion-once"]').click();
      document.querySelector('form.srcset .savebtn').click();
      for (let i = 0; i < 120; i++) {
        await new Promise(r => setTimeout(r, 25));
        const sub = document.querySelector('.pmnote');
        if (sub && sub.textContent.indexOf("Copied from Notion once") >= 0) break;
      }
      return JSON.stringify({ ms: Math.round(performance.now() - at), kept: window.__stillHere || "gone" });
    })()`);
    const swapped = JSON.parse(String(took));
    say(`  saving took ${swapped.ms}ms and the document ${swapped.kept === "yes" ? "was never reloaded" : "RELOADED"}`);
    swapped.kept === "yes"
      ? ok("saving swaps the page instead of reloading it")
      : no("saving swaps the page instead of reloading it", String(took));
    (await js(`document.querySelector('.pmnote').textContent`)).includes("Copied from Notion once")
      ? ok("…and what was saved is on screen")
      : no("…and what was saved is on screen", await js(`document.querySelector('.pmnote').textContent`));

    // **And with the script gone it is a plain form again**, which is the
    // bargain: the fast path is script, the working path is not.
    await open(`/f/${FILM}/safety-briefing`);
    (await js(`document.querySelector('form.srcset').getAttribute('method')`)) === "post"
      ? ok("…while the form underneath is still a plain post")
      : no("…while the form underneath is still a plain post", "not a form any more");

    // ---- naming a heading --------------------------------------------------
    await open(`/f/${FILM}/groups`);
    (await js(`Boolean(document.querySelector('input[name="new"]'))`))
      ? ok("headings are named on a screen of their own")
      : no("headings are named on a screen of their own", "no field");
    await js(`(() => {
      document.querySelector('input[name="new"]').value = "Logistics";
      document.querySelector('.seeform .savebtn').click();
      return 1;
    })()`);
    await wait(2200);
    // The headings are the categories (2026-10-11): the seven, then his new one.
    (await js(`[...document.querySelectorAll('input[name="name"]')].map(i => i.value).join("|")`)) === "Creative|Technical|Logistical|Other|Logistics"
      ? ok("…and a new one lands beside the ones he has")
      : no("…and a new one lands beside the ones he has", await js(`[...document.querySelectorAll('input[name="name"]')].map(i => i.value).join("|")`));
    await shot("shotlister-headings.png");

    await open(`/f/${FILM}`);
    await shot("shotlister-rail-headings.png");

    // ---- the source control, on the page it belongs to ---------------------
    // **`safety-briefing` went on the card the way a Hub-ticked Notion row
    // arrives** — no `by` — so it is the page where the choice is real.
    await open(`/f/${FILM}/safety-briefing`);
    (await js(`Boolean(document.querySelector('form.srcset input[value="notion-once"]'))`))
      ? ok("a page Notion names is offered where its words come from")
      : no("a page Notion names is offered where its words come from", "no control");
    await shot("shotlister-source-control.png");

    // **The form navigates, so the answer is read afterwards.** Evaluating in
    // the same call reads a document Chrome is in the middle of replacing, and
    // comes back `undefined` whether it worked or not.
    await js(`(() => {
      document.querySelector('form.srcset input[value="notion-once"]').click();
      document.querySelector('form.srcset .savebtn').click();
      return 1;
    })()`);
    await wait(2200);
    const said = await js(`document.querySelector('.pmnote') ? document.querySelector('.pmnote').textContent : ""`);
    String(said).includes("Copied from Notion once")
      ? ok("…and setting it changes what the page says")
      : no("…and setting it changes what the page says", String(said));

    // **And the page he made himself is offered neither.** His report,
    // 2026-09-08: *"live from notion and copied from notion still dont do
    // anything."* Nothing in Notion names it, so nothing could.
    await open(`/f/${FILM}/rigging-notes`);
    const alone = await js(`JSON.stringify({
      offered: Boolean(document.querySelector('form.srcset input[value="notion"]')),
      why: document.querySelector('.srcset .warn') ? document.querySelector('.srcset .warn').textContent : "",
    })`);
    const one = JSON.parse(String(alone));
    !one.offered && one.why.includes("Nothing in Notion names this page") && one.why.includes("Rigging Notes")
      ? ok("…and a page he made himself is offered neither, and told why")
      : no("…and a page he made himself is offered neither, and told why", String(alone));
    await shot("shotlister-source-unnamed.png");

    // ---- one Add button ----------------------------------------------------
    await open(`/f/${FILM}/add`);
    const asked = await js(`JSON.stringify({
      types: [...document.querySelectorAll('input[name="type"]')].map(i => i.value),
      heads: [...document.querySelectorAll('.addform .blockhead')].map(b => b.textContent),
      fileShown: !document.querySelector('[data-only="file"]').classList.contains('off'),
    })`);
    const seen = JSON.parse(asked);
    seen.types.join(",") === "page,deck,board,file,link"
      ? ok("Add asks the type first, and offers five")
      : no("Add asks the type first, and offers five", seen.types.join(","));
    // **It must not ask the source.** Two of the three answers need a Notion
    // page to be fed by, and this worker has no Notion token — so all three
    // made the same empty page. His report, 2026-09-08.
    !seen.heads.includes("Source") && !seen.fileShown
      ? ok("…and does not ask a question it cannot honour")
      : no("…and does not ask a question it cannot honour", asked);

    const grew = await js(`(async () => {
      const f = document.querySelector('.namefield');
      f.value = "Overheads & Rigging";
      f.dispatchEvent(new Event("input", { bubbles: true }));
      await new Promise(r => setTimeout(r, 60));
      const a = document.querySelector('.fh-addr');
      return a.classList.contains('off') ? "" : a.textContent.trim();
    })()`);
    String(grew).endsWith("/overheads-rigging")
      ? ok("…and the address appears as he types the name")
      : no("…and the address appears as he types the name", String(grew) || "nothing shown");
    await shot("shotlister-add-page.png");

    const swap = await js(`(async () => {
      document.querySelector('input[name="type"][value="link"]').click();
      await new Promise(r => setTimeout(r, 60));
      return JSON.stringify({
        link: !document.querySelector('[data-only="link"]').classList.contains('off'),
        file: !document.querySelector('[data-only="file"]').classList.contains('off'),
        addr: !document.querySelector('.fh-addr').classList.contains('off'),
      });
    })()`);
    const now = JSON.parse(String(swap));
    now.link && !now.file && !now.addr
      ? ok("…and choosing Link asks for an address, not a file or a page's own")
      : no("…and choosing Link asks for an address, not a file or a page's own", String(swap));
    await shot("shotlister-add-link.png");

    // **Taking it off again.** His question, 2026-09-08: *"how do i delete a
    // page?"* Two presses, because a delete is a person's decision. Since
    // Ref 1153 the first is Remove Page in the page's menu, which opens a panel
    // (`#pa-remove`, shown by the menu item's click); the second is the button inside it.
    await open(`/f/${FILM}/rigging-notes`);
    (await js(`(() => {
      if (!document.querySelector('.pmitem[href="#pa-remove"]')) return false;
      const b = document.querySelector('#pa-remove [name="remove"]');
      return Boolean(b) && !b.closest('.pageact').offsetParent;
    })()`))
      ? ok("removing a page takes opening its menu item first")
      : no("removing a page takes opening its menu item first", "the button is just sitting there");
    await js(`(() => { document.querySelector('.pmitem[href="#pa-remove"]').click(); return 1; })()`);
    await wait(300);
    (await js(`Boolean(document.querySelector('#pa-remove').offsetParent)`))
      ? ok("…and the menu item shows the sentence of what goes, and the button")
      : no("…and the menu item shows the sentence of what goes, and the button", "the panel did not open");
    await shot("shotlister-remove.png");
    await js(`(() => { document.querySelector('#pa-remove .savebtn').click(); return 1; })()`);
    await wait(2400);
    const gone = await js(`JSON.stringify({
      at: location.pathname,
      onrail: Boolean(document.querySelector('.to[data-key="rigging-notes"]')),
    })`);
    const left = JSON.parse(String(gone));
    !left.onrail && !left.at.endsWith("/rigging-notes")
      ? ok("…and it goes, off the rail and off the film")
      : no("…and it goes, off the rail and off the film", String(gone));
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\npassed ${pass}, failed ${fail}`);
process.exit(fail ? 1 : 0);
