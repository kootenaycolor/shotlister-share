/**
 * **The Studio's mailbox** (2026-10-05) — how the phone reaches the Mac with
 * no Tailscale in between.
 *
 * Until now the phone's Agents tab, its drive lights and a project's extra
 * doors came from the Mac's own transport (`:49213/rpc`), which only answers
 * on the tailnet. Everything else the phone does already goes through this
 * worker. This door moves the rest here too, in two halves:
 *
 * - **The snapshot.** The Mac writes what the phone's screens show — the
 *   agents and their inbox, the drives, each project's doors — about once a
 *   minute, and the phone reads it. So the phone has an answer with the Mac
 *   asleep, and says how old it is.
 * - **The asks.** A call the phone would have made on the transport is put
 *   here instead, `{method, args}`. The Mac checks every few seconds, claims
 *   it, runs it through the same backend method under the same allow-list the
 *   transport held the phone to, and writes the answer back. The phone polls
 *   for it. A few seconds slower than the tailnet; works from anywhere.
 *
 *   GET  /console/studio                 the snapshot, `{}` before the first one, with
 *                                        `cloud`: the calls answered here (cloud.js)
 *   PUT  /console/studio                 the snapshot, replaced; `at` stamped here
 *   GET  /console/studio/asks            every ask still kept, oldest first
 *   POST /console/studio/asks            { method, args, by } → the ask, pending (or working, by the
 *                                        server, for the few answered after the reply: later.js)
 *   GET  /console/studio/later           { held } — those asks, with when each was started and finished
 *   POST /console/studio/later/tick      the minute's turn at them, now
 *   GET  /console/studio/asks/<id>       one ask, with its answer once it has one
 *   POST /console/studio/now             { method, args } → a read answered on the spot, never kept:
 *                                        { state: done|failed|declined } (routerasks.js, the Mac's router)
 *   POST /console/studio/asks also takes `key` (the same ask again is answered with the one kept)
 *                                        and `here_only` (declined, not left for the Mac's mailbox)
 *   GET  /console/studio/template        the folder template, the server's master copy (foldertemplate.js)
 *   PUT  /console/studio/template        { drive?, media?, base, by } — written from version `base`, or 409
 *   PUT  /console/studio/asks/<id>       { state: working|done|failed, result, error, by }
 *   GET  /console/studio/owner           who keeps Notion and the records in step:
 *                                        { owner: "mac" | "hub", at, by } — "mac" until set
 *   PUT  /console/studio/owner           { owner, by } — the one switch (2026-10-11, stage 2)
 *   GET  /console/studio/specsheet       where the Camera Spec Sheet is read from: { on, source:
 *                                        "notion" | "record", at, by } — Notion until set (specsheet.js)
 *   PUT  /console/studio/specsheet       { on, by } — the switch, after his tick on the look
 *   POST /console/studio/specsheet/look  every Notion sheet as the move would write it, and each
 *                                        line it could not place; writes nothing
 *   POST /console/studio/specsheet/move  { confirm: "move the spec sheets", by } — the move: record
 *                                        facts only, never Notion, never over a sheet already there
 *   GET  /console/studio/lenslibrary     the lens library: sets with their lenses, lenses on their own,
 *                                        `v` (lenslibrary.js); the seed until first written
 *   POST /console/studio/lenslibrary/look    { ops } — what they would make; writes nothing
 *   PUT  /console/studio/lenslibrary     { ops, base, by } — written from version `base`, or 409
 *   GET  /console/studio/lenslibrary/uses    { uses: {id: [sheets]} } — which sheets use each entry
 *   POST /console/studio/lenslibrary/entries { pick } — what picking it puts on a sheet; writes nothing
 *   GET  /console/studio/kitextras       modifiers and filters (kitlibrary.js); /look, PUT, /uses, /entries as the lens library's
 *   GET  /console/studio/sensormodes     the sensor modes, and which still need a size (sensormodes.js)
 *   POST /console/studio/sensormodes/look    { ops } — writes nothing
 *   PUT  /console/studio/sensormodes     { ops, base, by }
 *   GET  /console/studio/sensormodes/uses    { uses: {id: [sheets]} }
 *   POST /console/studio/export/<project>  Studio's Export made and filed in Drive by the server (exporting.js)
 *   GET  /console/studio/exportpresets   the Studio's export presets: { v, presets } (exportpresets.js)
 *   PUT  /console/studio/exportpresets   { presets, base, by } — written from version `base`, or 409
 *   GET  /console/studio/templates       his Settings › Record standards, as the console keeps them
 *   PUT  /console/studio/templates       the same, replaced — sent by the console on every save
 *   GET  /console/studio/conflicts       { conflicts } — Notion and the record both changed,
 *                                        each with its `id`, as the Mac's sync sheet shows them
 *   POST /console/studio/conflicts/settle { id, keep: mine|theirs } — his pick (notionsync.js)
 *   GET  /console/studio/sync            { owner, last, dry } — the worker's last live look
 *                                        and its last look-without-writing (timer.js)
 *   GET  /console/studio/owner/portal    who refreshes the portal's cards and link covers:
 *   PUT  /console/studio/owner/portal    { owner: "mac" | "hub" } (refreshhub.js, stage 3 step 2)
 *   POST /console/studio/portal/run      { dry, only, all, force, redraw, detail } — a refresh now
 *   GET  /console/studio/portal          the switch, the pass under way, the last tick and look
 *   POST /console/studio/portal/trial    { only, slug } — one cover drawn now, as a PNG, nothing kept
 *   GET  /console/studio/layout          Customize Record from the server: { on, last look }
 *   PUT  /console/studio/layout          { on, by } — its switch, off until thrown (cloudlayout.js)
 *   POST /console/studio/layout/run      { dry, name, want, reset } — what it would write, now
 *   GET  /console/studio/folders         the Mac's folder lists held here, counts and ages
 *   PUT  /console/studio/folders         { drives?, projects? } — from the Mac (drivelists.js)
 *   GET  /console/studio/newfilm         New Film made by the server: { on } — off until set
 *   PUT  /console/studio/newfilm         { on, by } (newfilm.js)
 *   POST /console/studio/newfilm/look    { name, title } — what it would make, or why not; writes nothing
 *   GET  /console/studio/linkfilm        a spare film linked by the server: { on } — off until set
 *   PUT  /console/studio/linkfilm        { on, by } (linkfilm.js)
 *   POST /console/studio/linkfilm/look   { name } — the relay's films it would offer; writes nothing
 *   GET  /console/studio/drivefolders    Google Drive folders made by the server: { on, roots, scratch, ready }
 *   PUT  /console/studio/drivefolders    { on, by, roots?, scratch?, template? } (drivefolders.js)
 *   POST /console/studio/drivefolders/look { kind: project|shoot|showcase, name, … } — the plan; writes nothing
 *   POST /console/studio/drivefolders/run  the same, made — switch on and GDRIVE_WRITE only
 *   GET  /console/studio/drivecopies     Drive copies of pictures: { mode, drivecopies_root, only, cap, ready, last }
 *   PUT  /console/studio/drivecopies     { mode: off|scratch|live, drivecopies_root?, only?, cap?, by } (drivecopiesdoor.js)
 *   GET  /console/studio/drivecopies/look?id=…  the plan for one project; writes nothing
 *   POST /console/studio/drivecopies/run|tick   one project now, or the clock's sweep now
 *   GET  /console/studio/specsheetsheet  the Camera Spec Sheet as a Google Sheet in Drive: { mode, root, only, ready, last }
 *   PUT  /console/studio/specsheetsheet  { mode: off|scratch|live, root?, only?, by } (specsheetsheetdoor.js)
 *   GET  /console/studio/specsheetsheet/look|xlsx|manifest?id=…  what a run would do; the workbook; what Drive holds
 *   POST /console/studio/specsheetsheet/run|tick  one project now, or the clock's sweep now
 *   GET  /console/studio/filmbackup      film backups made by the server: { on, folder, bucket, signin, day }
 *   PUT  /console/studio/filmbackup      { on, by, folder? } (filmbackuprun.js) — off until set
 *   POST /console/studio/filmbackup/look { name? } — which films a run would copy, sizes, what would go; writes nothing
 *   POST /console/studio/filmbackup/run  { name? } — copies now; switch on only
 *   POST /console/studio/filmbackup/tick the daily minute, now (what the clock does)
 *   GET  /console/studio/filmbackup/copies/<relay>        a film's copies in the bucket
 *   GET  /console/studio/filmbackup/zip/<relay>/<stamp>   one copy, as the zip (the restore door)
 *   GET  /console/studio/newproject      a full New Project made by the server: { on, ready, why }
 *   PUT  /console/studio/newproject      { on, by } (newproject.js, newprojectdoor.js)
 *   POST /console/studio/newproject/look { form } — every request it would make; writes nothing
 *   GET  /console/studio/newproject/owed { items } — the media folders and sidebar entries the
 *                                        Mac still owes (`?all=1` the finished ones too)
 *   PUT  /console/studio/newproject/owed/<id> { part, state, said, by } — from the Mac
 *   GET  /console/studio/macjobs         the Mac jobs list, presence, switch, look (macjobs.js)
 *   GET  /console/studio/newshoot        New Shoot answered by the server: { on, ready, why } — off until set
 *   PUT  /console/studio/newshoot        { on, by } (newshoot.js, newshootdoor.js)
 *   POST /console/studio/newshoot/look   { name, form? } — the form and the plan; writes nothing
 *
 * Kept at `s/studio.json` and `s/asks.json`, apart from records (`r/`) and
 * films (`p/`). Asks are written compare-and-set, so a phone asking at the
 * moment the Mac answers loses neither. An answered ask is kept ten minutes —
 * long enough for a phone to come back for it — and an unclaimed one a day,
 * so a request made with the Mac off is still done when it wakes.
 */

import { answerHere, cloudMethodsNow, cloudReady } from "./cloud.js";
import { hubOwner, refuseOff } from "./fixedon.js";

const ASK_ID = /^[0-9a-f]{12}$/;
const METHOD = /^[a-z_]{1,40}$/;
const STATES = new Set(["working", "done", "failed"]);
const MAX_SNAPSHOT = 4 * 1024 * 1024;
const MAX_ASK = 256 * 1024;
const MAX_ANSWER = 2 * 1024 * 1024;
const ANSWERED_KEEP_MS = 10 * 60 * 1000;
const UNCLAIMED_KEEP_MS = 24 * 3600 * 1000;
const SNAPSHOT_KEY = "s/studio.json";
const ASKS_KEY = "s/asks.json";
const OWNER_KEY = "s/sync-owner.json";

/**
 * **Who keeps Notion and the records in step**: this worker (notionsync.js,
 * on its timer), since 2026-10-11. It was a switch between the Mac's Notion
 * link and this one until stage 5 step 9 (2026-10-18) removed the Mac's copy;
 * it always says "hub" now, with when it moved here.
 */
export async function syncOwner(env) {
  const got = await env.BUCKET.get(OWNER_KEY);
  let said = null;
  try { said = got ? await got.json() : null; } catch { said = null; }
  return hubOwner(said);
}

function reply(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function refuse(status, said) {
  return reply({ problem: said }, status);
}

async function readJson(request, limit) {
  const text = await request.text();
  if (text.length > limit) throw new Error("too long");
  return JSON.parse(text);
}

async function asksOf(env) {
  const got = await env.BUCKET.get(ASKS_KEY);
  if (!got) return { list: [], etag: null };
  try {
    const parsed = await got.json();
    return { list: Array.isArray(parsed) ? parsed.filter((x) => x && typeof x === "object") : [], etag: got.etag };
  } catch {
    return { list: [], etag: got.etag };
  }
}

function pruned(list) {
  const now = Date.now();
  return list.filter((x) => {
    if (x.state === "done" || x.state === "failed" || x.state === "declined") {
      return !x.done_at || now - Date.parse(x.done_at) < ANSWERED_KEEP_MS;
    }
    return !x.asked || now - Date.parse(x.asked) < UNCLAIMED_KEEP_MS;
  });
}

/** Read, change, write back only if nobody else wrote in between. */
async function changeAsks(env, change) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const { list, etag } = await asksOf(env);
    const out = change(list);
    if (out.refusal) return out;
    const saved = await env.BUCKET.put(ASKS_KEY, JSON.stringify(pruned(out.list)), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: etag ? { etagMatches: etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return out;
  }
  return { refusal: refuse(409, "The mailbox kept changing while this was being written. Try again.") };
}

/** The mailbox, for the asks answered later by the server (later.js). */
export const mailbox = { asksOf: (env) => asksOf(env), changeAsks: (env, change) => changeAsks(env, change) };

export async function studioDoor(request, env, parts, ctx) {
  const method = request.method;
  const rest = parts.slice(2);

  // **One ID per project** (oneiddoor.js, stage 5 step 2).
  if (rest[0] === "oneid" || rest[0] === "ids" || rest[0] === "projects") {
    const { oneIdDoor } = await import("./oneiddoor.js");
    const got = await oneIdDoor(env, rest, method, () => readJson(request, 16384));
    if (got) return got;
  }

  // **Studio reads the card** (studiocards.js, stage 5 step 4 piece A).
  // **Modes, one switch everywhere** (studiomodes.js, stage 5 step 4 piece B).
  // Notion's Frame Guides as a copy of the sheet's frames (framescopy.js).
  if (rest[0] === "framescopy") {
    const { copyDoor } = await import("./framescopy.js");
    let notion = null;
    if (cloudReady(env)) {
      const { notionClient } = await import("./newprojectdoor.js");
      notion = notionClient(env);
    }
    const got = await copyDoor(env, rest, method, () => readJson(request, 4096), notion);
    if (got) return got;
  }

  // New Project or Job as step 5 makes them (step5birth.js): the switch.
  if (rest[0] === "step5birth") {
    const { birthDoor } = await import("./step5birth.js");
    const got = await birthDoor(env, rest, method, () => readJson(request, 4096));
    if (got) return got;
  }

  // **Mods, one shelf** (studiomods.js, 2026-10-17).
  if (rest[0] === "mods") {
    const { modsDoor } = await import("./studiomods.js");
    const got = await modsDoor(env, rest, method, () => readJson(request, 4096));
    if (got) return got;
  }

  if (rest[0] === "modes" || rest[0] === "studiomodes") {
    const { modesDoor } = await import("./studiomodes.js");
    const got = await modesDoor(env, rest, method, () => readJson(request, 4096), ctx);
    if (got) return got;
  }

  // **The portal follows the modes; one Shared switch** (portalmodes.js, stage 5 step 5).
  if (rest[0] === "portalmodes") {
    const { portalModesDoor } = await import("./portalmodes.js");
    const got = await portalModesDoor(env, rest, method, () => readJson(request, 4096), ctx);
    if (got) return got;
  }

  // **The Mac jobs list** (macjobs.js, stage 5 step 7).
  if (rest[0] === "macjobs") {
    const { macJobsDoor } = await import("./macjobs.js");
    return await macJobsDoor(env, rest, method, (limit) => readJson(request, limit), ctx, new URL(request.url));
  }

  // Step 6's four switches (step6.js).
  if (typeof rest[0] === "string" && rest[0].startsWith("step6")) {
    const { step6Door } = await import("./step6.js");
    const got = await step6Door(env, rest, method, () => readJson(request, 65536), ctx, new URL(request.url));
    if (got) return got;
  }

  // **The big moves** (bigmoves.js, stage 5 step 7): the switch, a dry look,
  // a project's moves, and a deleted project's old id.
  if (rest[0] === "bigmoves") {
    const { door } = await import("./bigmoves.js");
    const got = await door(env, rest, method, () => readJson(request, 65536), new URL(request.url));
    if (got) return got;
  }

  // **One script, from Drive** (scriptdrive.js, stage 5 step 4 piece C).
  if (rest[0] === "script" || rest[0] === "scriptdrive") {
    const { scriptDoor } = await import("./scriptdrive.js");
    const got = await scriptDoor(env, request, rest, ctx);
    if (got) return got;
  }

  // **Frames and sensors in Studio** (studioframes.js, stage 5 step 4 piece E).
  if (rest[0] === "studioframes") {
    const { framesDoor } = await import("./studioframes.js");
    const got = await framesDoor(env, rest, method, () => readJson(request, 4096), ctx);
    if (got) return got;
  }

  // **Shoots in Studio** (studioshoots.js, stage 5 step 4 piece D).
  if (rest[0] === "studioshoots") {
    const { shootsDoor } = await import("./studioshoots.js");
    const got = await shootsDoor(env, rest, method, () => readJson(request, 4096), ctx);
    if (got) return got;
  }

  // **What the portal's boards and pages lean on** (boardheld.js): Studio asks
  // before its week-old tidy of the sync server deletes a picture.
  if (rest[0] === "held") {
    const { heldDoor } = await import("./boardheld.js");
    const got = await heldDoor(env, rest, method);
    if (got) return got;
  }

  if (rest[0] === "cards" || rest[0] === "studiocards" || rest[0] === "open") {
    const { cardsDoor } = await import("./studiocards.js");
    const got = await cardsDoor(env, rest, method, () => readJson(request, 4096), ctx);
    if (got) return got;
  }

  if (rest.length === 0) {
    if (method === "GET") {
      // `cloud`: the calls this server answers itself (cloud.js), so the
      // phone keeps those buttons live with the Mac asleep. Laid on here, not
      // stored, so it is always this deploy's list.
      const cloud = cloudReady(env) ? await cloudMethodsNow(env) : [];
      const got = await env.BUCKET.get(SNAPSHOT_KEY);
      let snapshot = {};
      if (got) {
        try { snapshot = await got.json(); } catch { snapshot = {}; }
      }
      return reply({ ...snapshot, cloud });
    }
    if (method !== "PUT") return refuse(405, "Wrong method.");
    let snapshot;
    try { snapshot = await readJson(request, MAX_SNAPSHOT); } catch { return refuse(400, "That is not JSON, or it is too long."); }
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) return refuse(400, "A snapshot is an object.");
    const at = new Date().toISOString();
    await env.BUCKET.put(SNAPSHOT_KEY, JSON.stringify({ ...snapshot, at }), {
      httpMetadata: { contentType: "application/json" },
    });
    return reply({ at });
  }

  // **Who writes the films' facts** (filmfacts.js): its own switch, so the
  // Notion link and the films move across on separate days.
  if (rest[0] === "owner" && rest.length === 2 && rest[1] === "films") {
    const { filmsOwner } = await import("./filmfacts.js");
    if (method === "GET") return reply(await filmsOwner(env));
    if (method !== "GET") return refuse(410, "The server keeps this now; there is no Mac copy to switch to.");
  }

  // **Who keeps the portal's cards and link covers** (refreshhub.js, stage 3
  // step 2): the Mac's `refresh.py` every fifteen minutes, or this worker's
  // clock. Its own switch, so it moves across on its own day.
  if (rest[0] === "owner" && rest.length === 2 && rest[1] === "portal") {
    const { portalOwner } = await import("./refreshhub.js");
    if (method === "GET") return reply(await portalOwner(env));
    if (method !== "GET") return refuse(410, "The server keeps this now; there is no Mac copy to switch to.");
  }

  // The portal's refresh, now: `{dry}` (the default) reads everything and
  // writes nothing, whoever owns it; a live one only once the server owns it.
  // `only` one card (an id or a piece of its title), `all` every card left in
  // the pass in this one call, `force` a new pass now, `redraw` every cover,
  // `detail` (dry) every write it would have made.
  if (rest[0] === "portal" && rest.length === 2 && rest[1] === "run") {
    if (method !== "POST") return refuse(405, "Wrong method.");
    let said = {};
    try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
    const { portalOwner, refreshTick } = await import("./refreshhub.js");
    const dry = said.dry !== false;
    if (!dry && (await portalOwner(env)).owner !== "hub") return refuse(409, "The Mac is the one refreshing the portal. Switch the owner first.");
    const only = typeof said.only === "string" ? said.only.slice(0, 80) : "";
    return reply(await refreshTick(env, undefined, Date.now(), {
      dry, only, all: said.all === true, force: said.force === true || dry, redraw: said.redraw === true,
      detail: dry && said.detail === true, batch: Number(said.batch) || undefined,
    }));
  }

  // One cover drawn in the portal's browser and handed back as a PNG,
  // nothing kept — to look at before the switch (`trialCover`).
  if (rest[0] === "portal" && rest.length === 2 && rest[1] === "trial") {
    if (method !== "POST") return refuse(405, "Wrong method.");
    let said = {};
    try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
    const { trialCover } = await import("./refreshhub.js");
    try {
      const png = await trialCover(env, String(said.only || "").slice(0, 80), String(said.slug || "").slice(0, 80));
      return new Response(png, { headers: { "content-type": "image/png", "cache-control": "no-store" } });
    } catch (problem) {
      return refuse(422, String((problem && problem.message) || problem).slice(0, 300));
    }
  }

  if (rest[0] === "portal" && rest.length === 1) {
    if (method !== "GET") return refuse(405, "Wrong method.");
    const { portalStatus } = await import("./refreshhub.js");
    return reply(await portalStatus(env));
  }

  // **The Mac's folder lists** (drivelists.js): each media drive's project
  // folders and each project's Drive folder, sent whenever they change, so
  // `drive_tree` and the project page's folders answer with the Mac off.
  if (rest[0] === "folders" && rest.length === 1) {
    const lists = await import("./drivelists.js");
    if (method === "GET") return reply(await lists.foldersHeld(env));
    if (method !== "PUT") return refuse(405, "Wrong method.");
    let said;
    try { said = await readJson(request, lists.MAX_BODY); } catch { return refuse(400, "That is not JSON, or it is too long."); }
    const got = await lists.putFolders(env, said);
    return reply(got.body, got.status);
  }

  // **New Film made by the server** (newfilm.js): its switch, off until
  // thrown, and a look — what would be made for a project, or why not —
  // which writes nothing, switch or no switch.
  if (rest[0] === "newfilm") {
    const nf = await import("./newfilm.js");
    if (rest.length === 1) {
      if (method === "GET") return reply(await nf.newFilmOn(env));
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (refuseOff(said)) return reply(refuseOff(said));
      const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
      await env.BUCKET.put(nf.SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
      return reply(out);
    }
    if (rest.length === 2 && rest[1] === "look") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (!cloudReady(env)) return refuse(503, "The server has no Notion key.");
      const { notionOf, projectRow } = await import("./cloud.js");
      const name = String((said && said.name) || "");
      let row;
      try { row = await projectRow(notionOf(env), name); } catch (e) { return refuse(502, String((e && e.message) || e).slice(0, 300)); }
      const plan = await nf.planNewFilm(env, row, name, String((said && said.title) || ""));
      delete plan.claim;
      return reply({ ...plan, on: (await nf.newFilmOn(env)).on });
    }
    return refuse(404, "No such door.");
  }

  // **A spare film linked by the server** (linkfilm.js, stage 4 step D): its
  // switch, off until thrown, and a look — the films the server would offer
  // a project with the Mac asleep — which writes nothing.
  if (rest[0] === "linkfilm") {
    const lf = await import("./linkfilm.js");
    if (rest.length === 1) {
      if (method === "GET") return reply(await lf.linkFilmOn(env));
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (refuseOff(said)) return reply(refuseOff(said));
      const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
      await env.BUCKET.put(lf.SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
      return reply(out);
    }
    if (rest.length === 2 && rest[1] === "look") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (!cloudReady(env)) return refuse(503, "The server has no Notion key.");
      const { notionOf, projectRow, bareId } = await import("./cloud.js");
      const { slugify } = await import("./suggest.js");
      const { filmReadout } = await import("./filmdoor.js");
      const name = String((said && said.name) || "");
      try {
        const n = notionOf(env);
        const row = await projectRow(n, name);
        if (!row) return reply({ ok: false, why: "no Notion row for this project" });
        const got = await lf.spareFilms(env, n, bareId(row.id), name, slugify(name), filmReadout, undefined, { keep: false });
        return reply({ ok: true, ...got, on: (await lf.linkFilmOn(env)).on });
      } catch (e) {
        return refuse(502, String((e && e.message) || e).slice(0, 300));
      }
    }
    return refuse(404, "No such door.");
  }

  // **Drive copies of pictures** (drivecopiesdoor.js, stage 5 step 5): the
  // switch, a look that writes nothing, a run, the clock's sweep.
  if (rest[0] === "drivecopies") {
    const { drivecopiesDoor } = await import("./drivecopiesdoor.js");
    const got = await drivecopiesDoor(env, rest, method, () => readJson(request, 4096), ctx, new URL(request.url), request);
    if (got) return got;
  }

  // **The Camera Spec Sheet as a Google Sheet in the project's Drive folder**
  // (specsheetsheetdoor.js): the switch, a look that writes nothing, a run, the sweep.
  if (rest[0] === "specsheetsheet") {
    const { specsheetsheetDoor } = await import("./specsheetsheetdoor.js");
    const got = await specsheetsheetDoor(env, rest, method, () => readJson(request, 4096), ctx, new URL(request.url));
    if (got) return got;
  }

  // **Google Drive folders made by the server** (drivefolders.js, stage 3
  // step 6): the switch and its roots, a look that writes nothing, a run.
  if (rest[0] === "drivefolders") {
    const door = await import("./drivefoldersdoor.js");
    const rules = await import("./drivefolders.js");
    if (rest.length === 1) {
      const show = async () => {
        const s = await door.state(env);
        return { ...s.settings, ready: s.ok, ...(s.ok ? {} : { why: s.why }), signin: env.GDRIVE_WRITE ? "write" : env.GDRIVE ? "read" : "none" };
      };
      if (method === "GET") return reply(await show());
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 16384); } catch { return refuse(400, "That is not JSON."); }
      const next = rules.changedSettings(await rules.settingsOf(env), said);
      if (next.problem) return refuse(400, next.problem);
      await env.BUCKET.put(rules.SWITCH_KEY, JSON.stringify(next), { httpMetadata: { contentType: "application/json" } });
      return reply(await show());
    }
    if (rest.length === 2 && (rest[1] === "look" || rest[1] === "run")) {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 16384); } catch { return refuse(400, "That is not JSON."); }
      if (!said || typeof said !== "object") return refuse(400, "Say kind and name.");
      return reply(rest[1] === "look" ? await door.look(env, said) : await door.run(env, said));
    }
    return refuse(404, "No such door.");
  }

  // **Film backups made by the server** (filmbackuprun.js, stage 4 part C):
  // the switch, a look that writes nothing, a run, a film's copies, and one
  // copy handed back — never written over the live film.
  if (rest[0] === "filmbackup") {
    const fb = await import("./filmbackuprun.js");
    if (rest.length === 1) {
      const show = async () => {
        const day = await env.BUCKET.get(fb.DAY_KEY);
        let last = null;
        if (day) { try { last = await day.json(); } catch { last = null; } }
        if (last) last = { ...last, films: (last.films || []).length };
        return { ...(await fb.settingsOf(env)), ...fb.readiness(env), day: last };
      };
      if (method === "GET") return reply(await show());
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      const next = fb.changedSettings(await fb.settingsOf(env), said);
      if (next.problem) return refuse(400, next.problem);
      await env.BUCKET.put(fb.SWITCH_KEY, JSON.stringify(next), { httpMetadata: { contentType: "application/json" } });
      return reply(await show());
    }
    if (rest.length === 2 && (rest[1] === "look" || rest[1] === "run")) {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said = {};
      try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
      const name = String((said && said.name) || "");
      return reply(rest[1] === "look" ? await fb.look(env, { name }) : await fb.runNow(env, { name }));
    }
    // The minute, now — what the clock does, for a check or a first run.
    // `at` (another time) is honoured only on a hub checking against a fake
    // Google on this machine, so the live hub can never be made to tidy up early.
    if (rest.length === 2 && rest[1] === "tick") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said = {};
      try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
      const { fake } = await import("./drivewrite.js");
      const at = fake(env) && Number.isFinite(said.at) ? said.at : Date.now();
      return reply({ at, day: await fb.onFilmBackupTimer(env, at) });
    }
    if (rest.length === 3 && rest[1] === "copies") {
      if (method !== "GET") return refuse(405, "Wrong method.");
      if (!env.BACKUPS) return refuse(503, "The server has no backups bucket.");
      return reply(await fb.copiesOf(env, rest[2]));
    }
    if (rest.length === 4 && rest[1] === "zip") {
      if (method !== "GET") return refuse(405, "Wrong method.");
      const got = await fb.zipOf(env, rest[2], rest[3]);
      if (!got) return refuse(404, "No such copy.");
      return new Response(got.body, {
        headers: {
          "content-type": "application/zip", "content-length": String(got.size), "cache-control": "no-store",
          "content-disposition": `attachment; filename*=UTF-8''${encodeURIComponent(got.name)}`,
        },
      });
    }
    return refuse(404, "No such door.");
  }

  // **A full New Project made by the server** (newprojectdoor.js, stage 4
  // part B): its switch, a look that writes nothing, and what the Mac owes.
  if (rest[0] === "newproject") {
    const door = await import("./newprojectdoor.js");
    if (rest.length === 1) {
      if (method === "GET") return reply(await door.show(env));
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      return reply(await door.setSwitch(env, said));
    }
    if (rest.length === 2 && rest[1] === "look") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 65536); } catch { return refuse(400, "That is not JSON."); }
      return reply(await door.look(env, said));
    }
    if (rest[1] === "owed" && rest.length === 2) {
      if (method !== "GET") return refuse(405, "Wrong method.");
      return reply(await door.owedList(env, new URL(request.url).searchParams.get("all") === "1"));
    }
    if (rest[1] === "owed" && rest.length === 3) {
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      const got = await door.markOwed(env, rest[2], said);
      return reply(got.body, got.status);
    }
    return refuse(404, "No such door.");
  }

  // **New Shoot answered by the server** (newshoot.js, stage 4 part A): its
  // switch, off until thrown, and a look — the form and, given a form, the
  // plan the phone would see — which writes nothing, switch or no switch.
  if (rest[0] === "newshoot") {
    const ns = await import("./newshootdoor.js");
    if (rest.length === 1) {
      const show = async () => {
        const r = await ns.readiness(env);
        return { on: r.on, at: r.at, by: r.by, ready: r.ok, ...(r.ok ? {} : { why: r.why }) };
      };
      if (method === "GET") return reply(await show());
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (refuseOff(said)) return reply(refuseOff(said));
      const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
      await env.BUCKET.put(ns.SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
      return reply(await show());
    }
    if (rest.length === 2 && rest[1] === "look") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 65536); } catch { return refuse(400, "That is not JSON."); }
      if (!said || typeof said !== "object") return refuse(400, "Say the project's name.");
      return reply(await ns.look(env, said));
    }
    return refuse(404, "No such door.");
  }

  // A look now, without waiting for the minute: `{dry: true}` writes nothing
  // and works whoever owns; a live one only once the server is the owner.
  // **Alerts on the phone, from the server** (push.js): whether the key is
  // here and how many phones are known; the phones' list (the Mac pulls it, and
  // hands over what it already had); and a send, for the Mac and for checks.
  if (rest[0] === "push") {
    const push = await import("./push.js");
    if (rest.length === 1) {
      if (method !== "GET") return refuse(405, "Wrong method.");
      const held = await push.devices(env);
      return reply({
        configured: push.configured(env),
        phones: Object.keys(held).length,
        devices: Object.entries(held).map(([token, row]) => ({ tail: token.slice(-8), env: row.env, device: row.device || "", seen: row.seen || 0 })),
      });
    }
    if (rest.length === 2 && rest[1] === "devices") {
      if (method === "GET") return reply({ devices: await push.devices(env) });
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 256 * 1024); } catch { return refuse(400, "That is not JSON, or it is too long."); }
      return reply(await push.mergeDevices(env, (said && said.devices) || {}));
    }
    if (rest.length === 2 && rest[1] === "send") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 16 * 1024); } catch { return refuse(400, "That is not JSON."); }
      if (!said || !said.title) return refuse(400, "Say a title.");
      return reply(await push.send(env, {
        title: String(said.title), body: String(said.body || ""), category: String(said.category || ""),
        data: said.data && typeof said.data === "object" ? said.data : {}, badge: said.badge ?? null,
        level: String(said.level || "active"), priority: Number(said.priority) || 10, thread: String(said.thread || ""),
      }));
    }
    return refuse(404, "No such door.");
  }

  if (rest[0] === "filmfacts" && rest.length === 2 && rest[1] === "run") {
    if (method !== "POST") return refuse(405, "Wrong method.");
    let said = {};
    try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
    const { filmsOwner, filmFactsTick, marksOn, markLookup, fetchIcon } = await import("./filmfacts.js");
    const dry = said.dry !== false;
    if (!dry && (await filmsOwner(env)).owner !== "hub") return refuse(409, "The Mac is the one writing the films. Switch the owner first.");
    const { mirrorRecord } = await import("./filmdoor.js");
    // The film's icon and colour: a look includes them (so it shows what the
    // switch would do) unless asked not to; a live run only when the switch is on.
    const marks = (dry ? said.marks !== false : await marksOn(env)) ? markLookup(env, fetchIcon) : null;
    // Every film, not only the ones that moved: a sweep.
    const at = new Date(); at.setUTCMinutes(0, 0, 0);
    return reply(await filmFactsTick(env, null, mirrorRecord, at.getTime(), { dry, marks }));
  }

  // **Whether the server writes a film's icon and colour** (filmfacts.js, the
  // Mac's `mirror_mark`): off until `{on:true}`, so a look (`filmfacts/run`
  // with `dry`) can say what it would do first.
  if (rest[0] === "filmmark" && rest.length === 1) {
    const { marksOn } = await import("./filmfacts.js");
    if (method === "GET") return reply({ on: await marksOn(env) });
    if (method !== "PUT") return refuse(405, "Wrong method.");
    let said;
    try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
    const out = { on: Boolean(said && said.on), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
    await env.BUCKET.put("s/film-mark.json", JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
    return reply(out);
  }

  // **The records kept up to date by the server** (recordlive.js): its switch
  // (`on`), the last sweep, and a look now (`{dry}` writes nothing).
  if (rest[0] === "recordlive") {
    const live = await import("./recordlive.js");
    if (rest.length === 1) {
      const read = async (key) => {
        const got = await env.BUCKET.get(key);
        if (!got) return null;
        try { return await got.json(); } catch { return null; }
      };
      if (method === "GET") return reply({ on: await live.recordLiveOn(env), last: await read("s/record-live-last.json") });
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (refuseOff(said)) return reply(refuseOff(said));
      const out = { on: Boolean(said && said.on), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
      await env.BUCKET.put("s/record-live.json", JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
      return reply(out);
    }
    if (rest.length === 2 && rest[1] === "run") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said = {};
      try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
      const dry = said.dry !== false;
      if (!dry && !(await live.recordLiveOn(env))) return refuse(409, "The switch is off. Turn it on first.");
      return reply(await live.recordLiveTick(env, live.workerReads(env, undefined), { dry }));
    }
    return refuse(404, "No such door.");
  }

  // **Customize Record from the server** (cloudlayout.js, stage 3 step 5):
  // its switch (`on`, off until thrown) and a look now — `{dry}` (the
  // default) writes nothing; `name` (+ `want`, `reset`) for one project,
  // none for every record as if each were opened. A real run only with the
  // switch on, and only for one project.
  if (rest[0] === "layout") {
    const lay = await import("./cloudlayout.js");
    if (rest.length === 1) {
      if (method === "GET") {
        const got = await env.BUCKET.get("s/record-layout-last.json");
        let last = null;
        if (got) { try { last = await got.json(); } catch { last = null; } }
        return reply({ on: await lay.layoutOn(env), last });
      }
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (refuseOff(said)) return reply(refuseOff(said));
      const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: String((said && said.by) || "").slice(0, 80) };
      await env.BUCKET.put(lay.SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
      return reply(out);
    }
    if (rest.length === 2 && rest[1] === "run") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said = {};
      try { said = (await readJson(request, 16 * 1024)) || {}; } catch { return refuse(400, "That is not JSON."); }
      if (!cloudReady(env)) return refuse(503, "The server has no Notion key.");
      const dry = said.dry !== false;
      const name = typeof said.name === "string" ? said.name : "";
      if (!dry && !name) return refuse(400, "A real run is for one project: say its name.");
      if (!dry && !(await lay.layoutOn(env))) return refuse(409, "The switch is off. Turn it on first.");
      const { notionOf } = await import("./cloud.js");
      try {
        return reply(await lay.layoutLook(env, notionOf(env), {
          name, dry, reset: said.reset === true,
          want: said.want && typeof said.want === "object" && !Array.isArray(said.want) ? said.want : {},
        }));
      } catch (problem) {
        return refuse(502, String((problem && problem.message) || problem).slice(0, 300));
      }
    }
    return refuse(404, "No such door.");
  }

  if (rest[0] === "filmfacts" && rest.length === 1) {
    if (method !== "GET") return refuse(405, "Wrong method.");
    const { filmsOwner } = await import("./filmfacts.js");
    const read = async (key) => {
      const got = await env.BUCKET.get(key);
      if (!got) return null;
      try { return await got.json(); } catch { return null; }
    };
    return reply({ owner: (await filmsOwner(env)).owner, last: await read("s/filmfacts-last.json"), state: await read("s/filmfacts.json") });
  }

  // **The spec sheet's home** (specsheet.js, 2026-10-14): Notion until he
  // ticks the look, then the project record. The look reads Notion and writes
  // nothing; the move writes record facts only, and only when told in words.
  if (rest[0] === "specsheet") {
    const S = await import("./specsheet.js");
    if (rest.length === 1) {
      if (method === "GET") {
        const sw = await S.specSwitch(env);
        return reply({ ...sw, source: sw.on ? "record" : "notion", confirm: S.CONFIRM });
      }
      if (method !== "PUT") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      if (!said || typeof said.on !== "boolean") return refuse(400, "Say on: true or false.");
      const out = { on: said.on, at: new Date().toISOString(), by: String(said.by || "").slice(0, 80) };
      await env.BUCKET.put(S.SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
      return reply({ ...out, source: out.on ? "record" : "notion" });
    }
    if (rest.length === 2 && (rest[1] === "look" || rest[1] === "move")) {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said = {};
      try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
      if (rest[1] === "move" && said.confirm !== S.CONFIRM) {
        return refuse(400, `Nothing written. The move needs confirm: “${S.CONFIRM}”, after the look.`);
      }
      if (!cloudReady(env)) return refuse(503, "The hub has no Notion key, so it cannot read the spec sheets.");
      try {
        if (rest[1] === "look") return reply(await S.lookOnHub(env));
        const got = await S.moveSheets(env, { confirm: said.confirm, by: said.by });
        return got.status === 200 ? reply(got) : refuse(got.status, got.why);
      } catch (problem) {
        return refuse(502, String((problem && problem.message) || problem).slice(0, 300));
      }
    }
    return refuse(404, "No such door.");
  }

  // **The studio's lens library and sensor modes** (lenslibrary.js,
  // sensormodes.js; phase 2 of the spec sheet): one each for every project.
  // A read answers the seed until the first write. `look` says what changes
  // would make and writes nothing; PUT writes them from the version read.
  if (rest[0] === "lenslibrary" || rest[0] === "sensormodes") {
    const lens = rest[0] === "lenslibrary";
    const L = await import("./lenslibrary.js");
    const M = await import("./sensormodes.js");
    if (rest.length === 1 && method === "GET") {
      if (lens) { const got = await L.readLibrary(env); return reply({ ...L.libraryView(got.library), seeded: got.seeded }); }
      const got = await M.readModes(env);
      return reply({ ...M.modesView(got.modes), seeded: got.seeded });
    }
    if (rest.length === 2 && rest[1] === "uses" && method === "GET") {
      const sheets = await L.everySheet(env);
      if (lens) return reply({ uses: L.lensUsageOf((await L.readLibrary(env)).library, sheets) });
      return reply({ uses: M.modeUsageOf((await M.readModes(env)).modes, sheets) });
    }
    if (lens && rest.length === 2 && rest[1] === "entries" && method === "POST") {
      // what picking a lens, a set or a whole set puts on a sheet; writes nothing
      let said = {};
      try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
      const lib = (await L.readLibrary(env)).library;
      const found = L.itemOf(lib, said.pick);
      if (!found) return refuse(404, `The lens library has no “${String(said.pick || "").slice(0, 80)}”.`);
      return reply({ kind: found.kind, entries: L.entriesFor(lib, found) });
    }
    const write = rest.length === 1 && method === "PUT";
    const look = rest.length === 2 && rest[1] === "look" && method === "POST";
    if (!write && !look) return refuse(rest.length <= 2 ? 405 : 404, rest.length <= 2 ? "Wrong method." : "No such door.");
    let said;
    try { said = await readJson(request, 64 * 1024); } catch { return refuse(400, "That is not JSON."); }
    if (!said || !Array.isArray(said.ops)) return refuse(400, "Say what changes: {ops: [{op, …}]}.");
    if (write && said.base === undefined) return refuse(400, "Say base: the version you read (v).");
    const asked = { ops: said.ops, base: said.base, by: String(said.by || "").slice(0, 80), look };
    const got = lens ? await L.changeLibrary(env, asked) : await M.changeModes(env, asked);
    return got.status === 200 ? reply(got) : refuse(got.status, got.why);
  }

  // **The studio's modifiers and filters** (kitlibrary.js, 2026-10-14): one
  // library for every project, beside the lens library, the same doors.
  if (rest[0] === "kitextras") {
    const X = await import("./kitlibrary.js");
    if (rest.length === 1 && method === "GET") { const got = await X.readExtras(env); return reply({ ...X.extrasView(got.extras), seeded: got.seeded }); }
    if (rest.length === 2 && rest[1] === "uses" && method === "GET") {
      const { everySheet } = await import("./lenslibrary.js");
      return reply({ uses: X.extrasUsageOf((await X.readExtras(env)).extras, await everySheet(env)) });
    }
    if (rest.length === 2 && rest[1] === "entries" && method === "POST") {
      // what picking a modifier, a filter or a filter set puts on a sheet; writes nothing
      let said = {};
      try { said = (await readJson(request, 4096)) || {}; } catch { return refuse(400, "That is not JSON."); }
      const lib = (await X.readExtras(env)).extras;
      const found = X.extraOf(lib, said.pick);
      if (!found) return refuse(404, `The library has no modifier or filter called “${String(said.pick || "").slice(0, 80)}”.`);
      return reply({ kind: found.kind, ...X.entriesForExtra(lib, found) });
    }
    const write = rest.length === 1 && method === "PUT";
    const look = rest.length === 2 && rest[1] === "look" && method === "POST";
    if (!write && !look) return refuse(rest.length <= 2 ? 405 : 404, rest.length <= 2 ? "Wrong method." : "No such door.");
    let said;
    try { said = await readJson(request, 64 * 1024); } catch { return refuse(400, "That is not JSON."); }
    if (!said || !Array.isArray(said.ops)) return refuse(400, "Say what changes: {ops: [{op, …}]}.");
    if (write && said.base === undefined) return refuse(400, "Say base: the version you read (v).");
    const got = await X.changeExtras(env, { ops: said.ops, base: said.base, by: String(said.by || "").slice(0, 80), look });
    return got.status === 200 ? reply(got) : refuse(got.status, got.why);
  }

  if (rest[0] === "owner" && rest.length === 1) {
    if (method === "GET") return reply(await syncOwner(env));
    if (method !== "GET") return refuse(410, "The server keeps this now; there is no Mac copy to switch to.");
  }

  // **Studio's Export, made and filed by the server** (exporting.js): the
  // connector's `export`, for the Mac and the phone. Body: what `export` takes.
  if (rest[0] === "export" && rest.length === 2) {
    if (method !== "POST") return refuse(405, "Wrong method.");
    let said;
    try { said = await readJson(request, 64 * 1024); } catch { return refuse(400, "That is not JSON."); }
    const { consoleExport } = await import("./mcp.js");
    try {
      return reply(JSON.parse(await consoleExport(env, rest[1], said || {}, ctx)));
    } catch (error) {
      if (error && error.said) return refuse(400, error.said);
      throw error;
    }
  }

  // **Export presets** (exportpresets.js): the same Presets menu on every Mac.
  if (rest[0] === "exportpresets" && rest.length === 1) {
    const X = await import("./exportpresets.js");
    if (method === "GET") return reply(await X.readPresets(env));
    if (method !== "PUT") return refuse(405, "Wrong method.");
    let said;
    try { said = await readJson(request, 160 * 1024); } catch { return refuse(400, "That is not JSON."); }
    if (!said || said.base === undefined) return refuse(400, "Say presets and base: the version you read (v).");
    const got = await X.writePresets(env, said);
    if (got.problem) return refuse(400, got.problem);
    if (got.moved) return reply({ problem: "Changed elsewhere. Read it again.", now: got.moved }, 409);
    return reply(got);
  }

  // **His Record standards** (Settings › Record standards on the Mac), which
  // the worker's Notion link reads to know what each Type shows. The console
  // sends them on every save; `{}` means ours throughout.
  if (rest[0] === "templates" && rest.length === 1) {
    if (method === "GET") {
      const got = await env.BUCKET.get("s/record-templates.json");
      if (!got) return reply({});
      try { return reply(await got.json()); } catch { return reply({}); }
    }
    if (method !== "PUT") return refuse(405, "Wrong method.");
    let said;
    try { said = await readJson(request, 256 * 1024); } catch { return refuse(400, "That is not JSON."); }
    if (!said || typeof said !== "object" || Array.isArray(said)) return refuse(400, "Standards are an object, by Type.");
    await env.BUCKET.put("s/record-templates.json", JSON.stringify(said), { httpMetadata: { contentType: "application/json" } });
    return reply({ ok: true });
  }

  if (rest[0] === "conflicts") {
    const { conflictsList, settleConflict } = await import("./notionsync.js");
    if (rest.length === 1) {
      if (method !== "GET") return refuse(405, "Wrong method.");
      // With the project's name beside each, so the phone can say whose it is.
      const list = await conflictsList(env);
      const names = new Map();
      for (const c of list) {
        if (!c.page || names.has(c.page)) continue;
        const got = await env.BUCKET.get(`r/${c.page}/record.json`);
        let name = "";
        if (got) { try { name = String((await got.json()).name || ""); } catch { name = ""; } }
        names.set(c.page, name);
      }
      return reply({ conflicts: list.map((c) => ({ ...c, name: c.name || names.get(c.page) || "" })) });
    }
    if (rest.length === 2 && rest[1] === "settle") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      let said;
      try { said = await readJson(request, 4096); } catch { return refuse(400, "That is not JSON."); }
      const id = String((said && said.id) || "");
      const keep = String((said && said.keep) || "");
      if (!id || !["mine", "theirs"].includes(keep)) return refuse(400, "Say id and keep: mine or theirs.");
      return reply(await settleConflict(env, id, keep));
    }
    return refuse(404, "No such door.");
  }

  if (rest[0] === "sync" && rest.length === 1) {
    if (method !== "GET") return refuse(405, "Wrong method.");
    const read = async (key) => {
      const got = await env.BUCKET.get(key);
      if (!got) return null;
      try { return await got.json(); } catch { return null; }
    };
    return reply({ owner: (await syncOwner(env)).owner, last: await read("s/sync-last.json"), dry: await read("s/sync-dry.json") });
  }

  // **The asks answered after the reply** (later.js): the ones held, and the
  // minute's turn run now — what the clock does, for a check or a stuck ask.
  if (rest[0] === "later" && rest.length <= 2) {
    const later = await import("./later.js");
    if (rest.length === 1 && method === "GET") {
      return reply({ held: (await asksOf(env)).list.filter((x) => x.later) });
    }
    if (rest[1] === "tick" && method === "POST") return reply(await later.onLaterTimer(env, mailbox));
    return refuse(404, "No such door.");
  }

  // **The folder template** (foldertemplate.js): the server's master copy.
  if (rest[0] === "template" && rest.length === 1) {
    const ft = await import("./foldertemplate.js");
    if (method === "GET") return reply(await ft.templateOf(env));
    if (method !== "PUT") return refuse(405, "Wrong method.");
    let said;
    try { said = await readJson(request, 65536); } catch { return refuse(400, "That is not JSON."); }
    const got = await ft.changeTemplate(env, said);
    if (got.problem) return refuse(400, got.problem);
    if (got.moved) return reply({ problem: "Changed elsewhere. Read it again.", now: got.moved }, 409);
    return reply(got);
  }

  // **Reads answered on the spot** for the Mac's router (routerasks.js):
  // never kept in the mailbox; a method the server does not answer here is
  // `declined`, and the Mac does it itself.
  if (rest[0] === "now" && rest.length === 1) {
    if (method !== "POST") return refuse(405, "Wrong method.");
    let asked;
    try { asked = await readJson(request, MAX_ASK); } catch { return refuse(400, "That is not JSON, or it is too long."); }
    const name = String((asked && asked.method) || "").trim();
    if (!METHOD.test(name)) return refuse(400, "Say which method.");
    const ra = await import("./routerasks.js");
    if (!ra.NOW_READS.has(name)) return refuse(400, "Only a read is answered on the spot; send a write to the asks.");
    if (!cloudReady(env) || !(await cloudMethodsNow(env)).includes(name)) return reply(ra.nowAnswer(name, null));
    return reply(ra.nowAnswer(name, await answerHere(env, name, Array.isArray(asked.args) ? asked.args : [])));
  }

  if (rest[0] !== "asks") return refuse(404, "No such door.");

  if (rest.length === 1) {
    if (method === "GET") return reply({ asks: pruned((await asksOf(env)).list) });
    if (method !== "POST") return refuse(405, "Wrong method.");
    let asked;
    try { asked = await readJson(request, MAX_ASK); } catch { return refuse(400, "That is not JSON, or it is too long."); }
    const name = String((asked && asked.method) || "").trim();
    if (!METHOD.test(name)) return refuse(400, "Say which method.");
    const item = {
      id: crypto.randomUUID().replace(/-/g, "").slice(0, 12),
      method: name,
      args: Array.isArray(asked.args) ? asked.args : [],
      by: String(asked.by || "").slice(0, 80),
      asked: new Date().toISOString(),
      state: "pending",
    };
    // **The Mac's router** (routerasks.js, stage 5 step 3): an ask sent again
    // under the same `key` is answered with the one already kept, never done
    // twice; one sent `here_only` is the server's or nobody's — not kept for
    // the Mac's mailbox when the server declines it (the Mac does it itself).
    const ra = await import("./routerasks.js");
    const key = ra.keyOf(asked);
    if (key) {
      item.key = key;
      const seen = ra.sameKey((await asksOf(env)).list, key);
      if (seen) return reply(seen);
    }
    if (ra.hereOnly(asked)) item.here_only = true;
    // **Answered here when it only touches Notion** (cloud.js, 2026-10-10):
    // kept done in the mailbox like any answered ask, so the phone's poll
    // finds it at once and the Mac never sees it. Anything else, or a Notion
    // that refused before writing, waits for the Mac as before.
    // **Answered after the reply** (later.js): the few the server does that
    // can outlast the phone's 20-second wait are kept working, by the
    // server, and done by its own minute — never cut off half-way.
    const later = await import("./later.js");
    if (await later.answeredLater(env, name)) {
      const held = later.heldItem(item);
      const kept = await changeAsks(env, (list) => ({ list: [...list, held] }));
      if (kept.refusal) return kept.refusal;
      if (later.READS.has(name) && ctx && ctx.waitUntil) {
        ctx.waitUntil(later.runOne(env, mailbox, held.id).catch((e) => console.error("later:", String((e && e.stack) || e))));
      }
      return reply(held);
    }
    const here = await answerHere(env, name, item.args, ctx);
    if (!here && item.here_only) return reply(ra.declined(item));
    if (here) {
      item.state = here.state;
      item.by_done = "server";
      item.done_at = new Date().toISOString();
      if (here.state === "done") item.result = here.result === undefined ? null : here.result;
      else item.error = here.error;
    }
    const out = await changeAsks(env, (list) => ({ list: [...list, item] }));
    return out.refusal || reply(item);
  }

  // **Start a held ask now** (askrunner.js): the asker that posted it asks for it
  // to be started at once, not at the server's next minute, and holds the line
  // while it runs.
  if (rest.length === 3 && rest[2] === "start" && ASK_ID.test(rest[1])) {
    if (method !== "POST") return refuse(405, "Wrong method.");
    const got = await (await import("./askrunner.js")).startNow(env, mailbox, ctx, rest[1]);
    return got.refusal ? refuse(404, got.refusal) : reply(got.item);
  }

  if (rest.length !== 2 || !ASK_ID.test(rest[1])) return refuse(404, "No such ask.");
  const id = rest[1];

  if (method === "GET") {
    const item = (await asksOf(env)).list.find((x) => x.id === id);
    return item ? reply(item) : refuse(404, "No such ask — it may have been answered too long ago.");
  }
  if (method !== "PUT") return refuse(405, "Wrong method.");
  let said;
  try { said = await readJson(request, MAX_ANSWER); } catch { return refuse(400, "That is not JSON, or it is too long."); }
  const state = String((said && said.state) || "");
  if (!STATES.has(state)) return refuse(400, "Say state: working, done or failed.");
  let changed = null;
  const out = await changeAsks(env, (list) => {
    const at = list.findIndex((x) => x.id === id);
    if (at < 0) return { refusal: refuse(404, "No such ask.") };
    const item = { ...list[at] };
    // **Claimed once.** Working is only reachable from pending; a second
    // claimant is handed the item as it stands and can see it is not theirs.
    if (state === "working" && item.state !== "pending") {
      changed = item;
      return { list };
    }
    item.state = state;
    if (said.by) item.by_done = String(said.by).slice(0, 80);
    if (state === "working") item.claimed_at = new Date().toISOString();
    else {
      item.done_at = new Date().toISOString();
      if (state === "done") item.result = said.result === undefined ? null : said.result;
      else item.error = String(said.error || "It failed, and did not say why.").slice(0, 2000);
    }
    changed = item;
    const next = list.slice();
    next[at] = item;
    return { list: next };
  });
  return out.refusal || reply(changed);
}
