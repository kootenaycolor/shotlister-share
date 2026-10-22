#!/usr/bin/env node
/**
 * **The big moves** (stage 5 step 7, `src/bigmoves.js`) on a world held in
 * memory (`bigmovesworld.mjs`): a scratch test project "zz step7 test" with
 * two shoots, selects, a showcase, a film and a portal, beside a real one.
 *
 * - the look writes nothing; the run does what the look said;
 * - the switch: off hands back to the Mac, scratch acts only in the scratch
 *   folder, live everywhere;
 * - one move at a time (the `moving` lock), New Shoot's words for it;
 * - every move undone, round trip, and undo's 30 days, once only, and its
 *   Mac jobs cancelled first (a running one blocks it);
 * - Rename all or nothing: a planted failure puts everything back;
 * - Delete backs up before its first write, tombstones the record, and the
 *   old id still answers "deleted"; undo brings every piece back;
 * - his rules: Archive removes nothing (portal, Studio, footage untouched),
 *   Turn Off is showcase and website only, nothing names /Volumes.
 *
 *     node hub/bigmoves.mjs          (PLANT=1 plants a wrong answer, to see it fail)
 */
import { register } from "node:module";
import { readFileSync } from "node:fs";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);

const B = await import("./src/bigmoves.js");
const { Handoff } = await import("./src/cloud.js");
const W = await import("./bigmovesworld.mjs");
const PLANT = process.env.PLANT === "1";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(88)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 700)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const snap = (s) => ({ tree: s.drive.tree(s.ids.cine), bucket: [...s.BUCKET.objects.entries()].filter(([k]) => !k.startsWith("activity/") && !k.startsWith("s/bigmoves/moves/")).map(([k, v]) => [k, v.body]).sort(), notion: JSON.stringify([...s.n.pages.entries()]) });
const recordOf = (s, id) => JSON.parse(s.BUCKET.objects.get(`r/${id}/record.json`).body);
const setMode = (s, kind, mode) => {
  const cur = JSON.parse(s.BUCKET.objects.get("s/bigmoves.json").body);
  cur[kind] = mode;
  s.BUCKET.objects.set("s/bigmoves.json", { body: JSON.stringify(cur), etag: 99 });
};
async function throws(fn) { try { await fn(); return null; } catch (e) { return e; } }

console.log("the shape");
check("three asks: a look on the spot, a run and an undo held", same([...B.METHODS], ["bigmove_look", "bigmove_run", "bigmove_undo"])
  && same([...B.NOW], ["bigmove_look"]) && same([...B.LATER_WRITES], ["bigmove_run", "bigmove_undo"]));
check("seven moves, each off, scratch or live", same(B.KINDS, ["wrap", "archive", "movedrive", "rename", "turnoff", "delete", "showcase"]));
check("Mac job kinds for the registry, none of them on a media drive", same(Object.keys(B.BIGMOVE_KINDS), ["showcase-stills", "film-drivefolder", "bridge-list"])
  && Object.values(B.BIGMOVE_KINDS).every((k) => k.retry_safe && !k.needs_default.drive));
{
  const MJ = await import("./src/macjobs.js");
  check("the kinds are registered on the Mac jobs list, the same as here, none a media kind",
    Object.entries(B.BIGMOVE_KINDS).every(([k, v]) => MJ.KINDS[k] && JSON.stringify(MJ.KINDS[k].needs_default) === JSON.stringify(v.needs_default)
      && JSON.stringify(MJ.KINDS[k].parts) === JSON.stringify(v.parts) && !MJ.MEDIA_KINDS.has(k)));
}
check("no server file of step 7 names a media drive", !/\/Volumes/.test(readFileSync(new URL("./src/bigmoves.js", import.meta.url), "utf8"))
  && !/\/Volumes/.test(readFileSync(new URL("./src/drivemoves.js", import.meta.url), "utf8")));
{
  const env = { BUCKET: W.bucketOf() };
  const s = await B.settingsOf(env);
  check("the switch is off everywhere until set", B.KINDS.every((k) => s[k] === "off") && !(await B.anyOn(env)));
  check("a bad mode is refused", Boolean(B.changedSettings(s, { wrap: "on" }).problem));
  const set = await B.setSettings(env, { wrap: "scratch", by: "check" });
  check("scratch on one move lists the asks", set.wrap === "scratch" && (await B.anyOn(env)) && (await B.bigmovesNow(env)).length === 3);
}

console.log("wrap");
{
  const s = W.standing();
  const w = s.world();
  const before = snap(s);
  const lk = await B.look(w, s.ids.P, "wrap");
  check("the look writes nothing", same(snap(s), before));
  check("the look: Shoot 1 wrapped, status stays Active (Shoot 2 still to come), dates move on",
    lk.ok && lk.can_run && lk.lines.some((l) => /Status stays Active · Shoot 2 \(Nov 4\) is still to come/.test(l.text))
    && lk.lines.some((l) => l.text === "Shoot 1 marked Wrapped") && lk.lines.some((l) => /Shoot Dates move on to Shoot 2/.test(l.text)), JSON.stringify(lk.lines));
  check("the look: mockup 09's words, no showcase or stills line", lk.title === "Wrap zz step7 test" && lk.button === "Wrap Project"
    && lk.footer === "Nothing is deleted. Undo is in the history." && !lk.lines.some((l) => /stills|showcase/i.test(l.text))
    && lk.lines.some((l) => l.text === "Drive folder stays where it is") && lk.lines.some((l) => l.text === "Portal stays up for the grade"));
  {
    const rec0 = recordOf(s, s.ids.P);
    rec0.facts.shoot_dates = { value: "2026-10-01", v: 1 };
    s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec0), etag: 98 });
  }
  const r = await B.run(w, s.ids.P, "wrap");
  check("the Wrap moves the record's Shoot Dates too, so the record does not hold the old ones", recordOf(s, s.ids.P).facts.shoot_dates.value === "2026-11-04/2026-11-05", JSON.stringify(recordOf(s, s.ids.P).facts.shoot_dates));
  check("the run: Shoot 1 Wrapped, dates on Shoot 2, status still Active", r.ok && s.n.status("dddddddddddddddddddddddddddddd11") === "Wrapped"
    && s.n.pages.get(s.ids.P).properties["Shoot Dates"].date.start === "2026-11-04" && s.n.status(s.ids.P) === "Active", JSON.stringify(r));
  check("nothing on the Drive changed", same(s.drive.tree(s.ids.cine), before.tree));
  check("the lock is gone after", !recordOf(s, s.ids.P).moving);
  check("one history line with a big-move undo", [...s.BUCKET.objects.keys()].filter((k) => k.startsWith("activity/")).length === 1
    && JSON.parse([...s.BUCKET.objects.entries()].find(([k]) => k.startsWith("activity/"))[1].body).undo.type === "bigmove");
  const r2 = await B.run(w, s.ids.P, "wrap");
  // second wrap: now Shoot 1 is the last begun; it's wrapped; Shoot 2 still upcoming → no change but note
  check("a second run with nothing new to do is refused, not repeated", !r2.ok && /Nothing to change/.test(r2.why), JSON.stringify(r2));
  const u = await B.undo(w, r.move_id);
  check("undo puts Notion back exactly (shoot row, dates, status)", u.ok && s.n.status("dddddddddddddddddddddddddddddd11") === "Upcoming"
    && same(s.n.pages.get(s.ids.P).properties["Shoot Dates"].date, { start: "2026-10-01" }) && s.n.status(s.ids.P) === "Active", JSON.stringify(u));
  check("undo puts the record's Shoot Dates back too", recordOf(s, s.ids.P).facts.shoot_dates.value === "2026-10-01", JSON.stringify(recordOf(s, s.ids.P).facts.shoot_dates));
  check("undo twice is refused", !(await B.undo(w, r.move_id)).ok);
  // the last shoot: Post, and the record's status
  s.n.pages.get("dddddddddddddddddddddddddddddd12").properties.Dates.date = { start: "2026-10-05" };
  const r3 = await B.run(w, s.ids.P, "wrap");
  check("with no shoot still to come: Post in Notion and on the record", r3.ok && s.n.status(s.ids.P) === "Post"
    && recordOf(s, s.ids.P).facts.status.value === "Post" && s.n.status("dddddddddddddddddddddddddddddd12") === "Wrapped", JSON.stringify(r3));
  const u3 = await B.undo(w, r3.move_id);
  check("undo: Active again, on the record too", u3.ok && s.n.status(s.ids.P) === "Active" && recordOf(s, s.ids.P).facts.status.value === "Active"
    && s.n.status("dddddddddddddddddddddddddddddd12") === "Upcoming");
  // a failure half-way puts the done writes back
  s.n.failNext((path, body) => body.properties && body.properties.Status && body.properties.Status.select && body.properties.Status.select.name === "Post");
  const r4 = await B.run(w, s.ids.P, "wrap");
  check("a Notion failure half-way: nothing changed, the shoot row put back", !r4.ok && /Nothing was changed/.test(r4.why)
    && s.n.status("dddddddddddddddddddddddddddddd12") === "Upcoming" && s.n.status(s.ids.P) === "Active", JSON.stringify(r4));
}

console.log("wrap while Notion is out of reach (Daybreak, 2026-10-19: \"error 401\")");
{
  const NW = await import("./src/notionwaits.js");
  const s = W.standing();
  const w = s.world();
  setMode(s, "wrap", "live");
  const SH1 = "dddddddddddddddddddddddddddddd11", SH2 = "dddddddddddddddddddddddddddddd12";
  // the record keeps its own copy of the Shoots rows (notionsync writes it); Shoot 1 is the last, Shoot 2 is wrapped away
  const rec0 = recordOf(s, s.ids.P);
  rec0.facts.status = { value: "Active", v: 1 };
  rec0.facts.shoot_dates = { value: "2026-10-01", v: 1 };
  rec0.facts.shoots = { v: 1, value: [
    { id: SH1, title: "zz step7 test — Shoot 1", label: "Shoot 1", n: 1, start: "2026-10-01", end: "", status: "Upcoming" } ] };
  s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec0), etag: 7 });
  s.n.outage = () => new Handoff("unauthorized");
  const before = JSON.stringify([...s.n.pages.entries()]);
  const lk = await B.look(w, s.ids.P, "wrap");
  check("Notion down: the look still reads the shoots (from the record) and can run", lk.ok && lk.can_run && lk.plan.status === "Post" && lk.plan.shoot === SH1, JSON.stringify(lk));
  check("Notion down: the look says one quiet line, never an error", lk.lines.filter((l) => /waits/.test(l.text)).length === 1
    && lk.lines.some((l) => l.text === "Notion waits: not connected") && !JSON.stringify(lk).match(/401|error|unauthorized/i), JSON.stringify(lk.lines));
  const r = await B.run(w, s.ids.P, "wrap");
  check("Notion down: the Post is done — the record's stage is Post", r.ok && recordOf(s, s.ids.P).facts.status.value === "Post", JSON.stringify(r));
  check("Notion down: what he is told is the quiet line, not an error", /Notion waits: not connected/.test(r.report) && !JSON.stringify(r).match(/401|error|unauthorized/i), JSON.stringify(r));
  check("Notion down: nothing was written to Notion, nothing lost", JSON.stringify([...s.n.pages.entries()]) === before);
  check("Notion down: the shoot row's Wrapped waits on the list", (await NW.waitsList(s.env)).length === 1 && (await NW.waitsList(s.env))[0].kind === "shoot-status"
    && (await NW.waitsList(s.env))[0].shoot === SH1 && (await NW.waitsList(s.env))[0].status === "Wrapped");
  check("Notion down: the lock is gone and the history has a line", !recordOf(s, s.ids.P).moving && [...s.BUCKET.objects.keys()].some((k) => k.startsWith("activity/")));
  const again = await B.run(w, s.ids.P, "wrap");
  check("Notion down: a second Post is turned down as nothing to do (the list does not double)", !again.ok && (await NW.waitsList(s.env)).length === 1, JSON.stringify(again));
  // Notion comes back: the minute's look does the waiting part
  s.n.outage = null;
  const calls = [];
  const said = await NW.flushWaits(s.env, async (path, method = "GET", body) => { calls.push([method, path]); return method === "GET" ? s.n.get(path) : s.n.patch(path, body); });
  check("Notion back: the shoot row is marked Wrapped, once", s.n.status(SH1) === "Wrapped" && said.length === 1 && (await NW.waitsList(s.env)).length === 0, JSON.stringify(said));
  const said2 = await NW.flushWaits(s.env, async (path, method = "GET", body) => (method === "GET" ? s.n.get(path) : s.n.patch(path, body)));
  check("Notion back: nothing left to do the next minute", said2.length === 0);
  // undo while it still waits: taken off the list, Notion never touched
  const s2 = W.standing(); const w2 = s2.world(); setMode(s2, "wrap", "live");
  const r2c = recordOf(s2, s2.ids.P);
  r2c.facts.shoot_dates = { value: "2026-10-01", v: 1 };
  r2c.facts.shoots = { v: 1, value: [{ id: SH1, title: "zz step7 test — Shoot 1", label: "Shoot 1", n: 1, start: "2026-10-01", end: "", status: "Upcoming" }] };
  s2.BUCKET.objects.set(`r/${s2.ids.P}/record.json`, { body: JSON.stringify(r2c), etag: 7 });
  s2.n.outage = () => new Handoff("unauthorized");
  const ra = await B.run(w2, s2.ids.P, "wrap");
  const ua = await B.undo(w2, ra.move_id);
  check("Notion down: Undo takes the waiting part off and puts the record's stage back", ua.ok && (await NW.waitsList(s2.env)).length === 0
    && recordOf(s2, s2.ids.P).facts.status.value === "Active" && /Notion waits/.test(ua.report || ua.said || JSON.stringify(ua)), JSON.stringify(ua));
  // the same with a Notion that is up but refuses this one request: still all or nothing, as before
  const s3 = W.standing(); const w3 = s3.world(); setMode(s3, "wrap", "live");
  s3.n.pages.get("dddddddddddddddddddddddddddddd12").properties.Dates.date = { start: "2026-10-05" };
  s3.n.failNext((path, body) => body.properties && body.properties.Status && body.properties.Status.select && body.properties.Status.select.name === "Post");
  const rr = await B.run(w3, s3.ids.P, "wrap");
  check("Notion up but refusing one request: still all-or-nothing, nothing queued", !rr.ok && (await NW.waitsList(s3.env)).length === 0, JSON.stringify(rr));
  check("words: a refused key, a lost connection and a 5xx are \"Notion waits\"; a plain refusal is not",
    NW.notionWords(new Handoff("unauthorized")) === NW.QUIET && NW.notionWords(new TypeError("fetch failed")) === NW.QUIET
    && NW.notionWords(new Error("Notion answered 401: unauthorized")) === NW.QUIET && NW.notionWords(new Error("Notion: validation_error — bad")) === "");
}

console.log("the waiting list while Notion stays out (bug audit N2, 2026-10-19)");
{
  const NW = await import("./src/notionwaits.js");
  const s = W.standing();
  await NW.addWait(s.env, { kind: "shoot-status", project: s.ids.P, page: s.ids.P, shoot: "dddddddddddddddddddddddddddddd11", status: "Wrapped", label: "Shoot 1" });
  const down = async () => { throw new Handoff("unauthorized"); };
  for (let i = 0; i < 40; i++) await NW.flushWaits(s.env, down);
  const kept = await NW.waitsList(s.env);
  check("forty minutes of Notion down: the wait is kept and costs no try", kept.length === 1 && Number(kept[0].tries || 0) === 0, JSON.stringify(kept));
  const off = async () => { throw new TypeError("fetch failed"); };
  for (let i = 0; i < 25; i++) await NW.flushWaits(s.env, off);
  check("…and no connection costs none either", (await NW.waitsList(s.env))[0].tries === 0);
  const refuse = async () => { throw new Error("Notion: validation_error — bad"); };
  let said = [];
  for (let i = 0; i < 20; i++) said = await NW.flushWaits(s.env, refuse);
  check("twenty real refusals let it go, and say so in words", (await NW.waitsList(s.env)).length === 0
    && same(said, ["Shoot 1 · Wrapped not in Notion: Notion refused it"]), JSON.stringify(said));
}

console.log("rename while Notion is out of reach (bug audit N6)");
{
  const NW = await import("./src/notionwaits.js");
  const s = W.standing();
  const w = s.world();
  setMode(s, "rename", "live");
  s.n.outage = () => new Handoff("unauthorized");
  const lk = await B.look(w, s.ids.P, "rename", { new_name: "zz step7 offline name" });
  check("Notion down: the rename's look says Notion waits", lk.ok && lk.can_run && lk.notes.includes("Notion waits: not connected"), JSON.stringify(lk));
  const r = await B.run(w, s.ids.P, "rename", { new_name: "zz step7 offline name" });
  const waits = await NW.waitsList(s.env);
  check("Notion down: the record is renamed and Notion's title waits", r.ok && recordOf(s, s.ids.P).name === "zz step7 offline name"
    && waits.length === 1 && waits[0].kind === "project-title" && waits[0].status === "zz step7 offline name"
    && /Notion waits: not connected/.test(JSON.stringify(r)) && !JSON.stringify(r).match(/401|unauthorized/i), JSON.stringify([r, waits]));
  s.n.outage = null;
  const said = await NW.flushWaits(s.env, async (path, method = "GET", body) => (method === "GET" ? s.n.get(path) : s.n.patch(path, body)));
  check("Notion back: its title is the new name, once", s.n.title(s.ids.P) === "zz step7 offline name" && (await NW.waitsList(s.env)).length === 0
    && same(said, ["zz step7 offline name · name in Notion, kept from earlier"]), JSON.stringify(said));
  // undo while it still waits: the wait is taken off, Notion never asked
  const s2 = W.standing(); const w2 = s2.world(); setMode(s2, "rename", "live");
  s2.n.outage = () => new Handoff("unauthorized");
  const r2 = await B.run(w2, s2.ids.P, "rename", { new_name: "zz step7 offline name" });
  const u2 = await B.undo(w2, r2.move_id);
  check("Notion down: Undo takes the waiting title off and the record's name back", u2.ok && (await NW.waitsList(s2.env)).length === 0
    && recordOf(s2, s2.ids.P).name === "zz step7 test", JSON.stringify(u2));
}

console.log("archive while Notion is out of reach");
{
  const NW = await import("./src/notionwaits.js");
  const s = W.standing();
  const w = s.world();
  setMode(s, "archive", "live");
  const rec0 = recordOf(s, s.ids.P);      // the record keeps the Drive folder's link, Notion or not
  rec0.facts.drive_folder = { value: `https://drive.google.com/drive/folders/${s.ids.pdir}`, v: 1 };
  s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec0), etag: 9 });
  s.n.outage = () => new Handoff("unauthorized");
  const r = await B.run(w, s.ids.P, "archive");
  check("Notion down: the Archive is done on the record and Drive, with the quiet line",
    r.ok && recordOf(s, s.ids.P).facts.status.value === "Archived" && /Notion waits: not connected/.test(r.report || JSON.stringify(r))
    && !JSON.stringify(r).match(/401|unauthorized/i), JSON.stringify(r));
  const u = await B.undo(w, r.move_id);
  check("Notion down: Undo puts the record back", u.ok && recordOf(s, s.ids.P).facts.status.value === "Active", JSON.stringify(u));
}

console.log("the switch");
{
  const s = W.standing();
  const w = s.world();
  setMode(s, "wrap", "off");
  check("off: the look hands the ask to the Mac", (await throws(() => B.look(w, s.ids.P, "wrap"))) instanceof Handoff);
  setMode(s, "wrap", "scratch");
  check("scratch: a project outside the scratch folder goes to the Mac", (await throws(() => B.look(w, s.ids.R, "wrap"))) instanceof Handoff);
  const before = snap(s);
  check("scratch: …and its run writes nothing", (await throws(() => B.run(w, s.ids.R, "wrap"))) instanceof Handoff && same(snap(s), before));
  setMode(s, "wrap", "live");
  const lk = await B.look(w, s.ids.R, "wrap");
  check("live: the real one is the server's", lk.ok && lk.mode === "live" && lk.lines.some((l) => l.text === "Notion status → Post"));
  const dry = await B.look(w, s.ids.R, "archive", {}, { dry: true });
  check("the door's dry look answers whatever the switch says", dry.ok && /projects\/real-one/.test(dry.lines[0].text), JSON.stringify(dry));
  check("a project id that names nothing is refused in words", (await B.look(w, "ffffffffffffffffffffffffffffffff", "wrap")).why === "No project by that ID.");
  check("a name is not an id", (await B.look(w, "Real One", "wrap")).why === "Say which project (its ID).");
}

console.log("one move at a time");
{
  const s = W.standing();
  const w = s.world();
  const rec = recordOf(s, s.ids.P);
  rec.moving = { kind: "archive", since: W.nowFixed.toISOString(), move_id: "mv-0000000000000001" };
  s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec), etag: 50 });
  const lk = await B.look(w, s.ids.P, "rename", { new_name: "zz step7 other" });
  check("while Archive runs, Rename's look says to wait and can't run", !lk.can_run && /Archive is running on this project/.test(lk.problems[0]));
  const r = await B.run(w, s.ids.P, "rename", { new_name: "zz step7 other" });
  check("…and its run is refused, nothing renamed", !r.ok && s.n.title(s.ids.P) === "zz step7 test");
  check("New Shoot's words for it", B.busyWords(rec, W.nowFixed.getTime()) === "Archive is running on this project. Wait for it to finish.");
  check("a lock left 20 minutes by a run that died is let go", B.busyWords(rec, W.nowFixed.getTime() + 21 * 60000) === "");
}

console.log("archive");
{
  const s = W.standing();
  const w = s.world();
  const before = snap(s);
  const lk = await B.look(w, s.ids.P, "archive");
  check("the look writes nothing", same(snap(s), before));
  check("the look: folder → projects/z-archived/2026/, showcase → zz-archived/2026/, Archived, portal/Studio/footage stay",
    lk.ok && lk.can_run && /^projects\/zz-step7-test \(\d+ items\) → projects\/z-archived\/2026\/$/.test(lk.lines[0].text)
    && lk.lines.some((l) => l.text === "Showcase → project-showcases/zz-archived/2026/") && lk.lines.some((l) => l.text === "Notion status → Archived")
    && ["Portal stays as it is", "Studio side stays as it is", "Footage stays on its drives"].every((t) => lk.lines.some((l) => l.text === t))
    && lk.arm === "twice" && lk.armed_button === "Click Again to Archive", JSON.stringify(lk.lines));
  const ids = { folder: s.ids.pdir, show: s.ids.show };
  const portal = [...s.BUCKET.objects.keys()].filter((k) => k.startsWith("p/")).sort();
  const r = await B.run(w, s.ids.P, "archive");
  check("the run: folder and showcase moved, their ids kept", r.ok && s.drive.path(ids.folder) === "cinematography/zz-step7-scratch/projects/z-archived/2026/zz-step7-test"
    && s.drive.path(ids.show) === "cinematography/zz-step7-scratch/portfolio/project-showcases/zz-archived/2026/zz-step7-test-showcase", JSON.stringify(r));
  check("Archived in Notion and on the record", s.n.status(s.ids.P) === "Archived" && recordOf(s, s.ids.P).facts.status.value === "Archived");
  check("removes nothing: no trash, every portal and Studio object still there", ![...s.drive.items.values()].some((x) => x.trashed)
    && same([...s.BUCKET.objects.keys()].filter((k) => k.startsWith("p/")).sort(), portal) && !s.BUCKET.objects.has(`gone/${s.ids.RELAY}.json`));
  check("Notion's Drive Folder link still names the same folder", s.n.pages.get(s.ids.P).properties["Drive Folder"].url.endsWith(ids.folder));
  check("a scratch project's move leaves no Studio job", s.jobs.list.length === 0);
  const again = await B.look(w, s.ids.P, "archive");
  check("archiving it again is refused", !again.can_run && /already in the archive/.test(again.problems.join(" ")));
  const u = await B.undo(w, r.move_id);
  check("undo: both folders back, ids kept, status Active", u.ok && s.drive.path(ids.folder) === "cinematography/zz-step7-scratch/projects/zz-step7-test"
    && s.drive.path(ids.show) === "cinematography/zz-step7-scratch/portfolio/project-showcases/zz-step7-test-showcase"
    && s.n.status(s.ids.P) === "Active" && recordOf(s, s.ids.P).facts.status.value === "Active", JSON.stringify(u));
  const r2 = await B.run(w, s.ids.P, "archive");
  check("archive again after undo works (the empty year folders are reused)", r2.ok && s.drive.path(ids.folder).endsWith("z-archived/2026/zz-step7-test"));
  // a gigs project archives into gigs/z-archive/<year>/ (.filing-rules.md)
  const g = W.standing();
  const gp = g.drive.add([...g.drive.items.values()].find((x) => x.name === "gigs" && x.parent === g.ids.scratch).id, "zz-step7-gig", true, "gigFolder00001");
  g.n.addProject("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa05", { name: "zz step7 gig", drive: `https://drive.google.com/drive/folders/${gp}` });
  const gl = await B.look(g.world(), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa05", "archive");
  check("a gig archives to gigs/z-archive/<year>/, as the filing rules say", gl.ok && / → gigs\/z-archive\/2026\/$/.test(gl.lines[0].text), JSON.stringify(gl.lines));
}

console.log("move drive");
{
  const s = W.standing();
  const w = s.world();
  const lk0 = await B.look(w, s.ids.P, "movedrive");
  check("the homes, the one it is in left out", lk0.homes.map((h) => h.key).join(",") === "gigs,archive,custom" && lk0.where === "projects/");
  const br = await B.look(w, s.ids.P, "movedrive", { browse: "" });
  check("the folder picker lists the scratch folder's folders, not the project itself", br.browse && br.browse.folders.some((f) => f.name === "gigs")
    && !br.browse.folders.some((f) => f.id === s.ids.pdir));
  const outside = await B.look(w, s.ids.P, "movedrive", { browse: s.ids.outside });
  check("the picker refuses a folder outside", !outside.can_run && /not inside/.test(outside.problems[0]));
  const before = snap(s);
  const lk = await B.look(w, s.ids.P, "movedrive", { dest: "gigs" });
  check("the look: projects/… → gigs/…, typed name to arm, writes nothing", lk.can_run && lk.arm === "typed" && /→ gigs\/zz-step7-test$/.test(lk.lines[0].text) && same(snap(s), before), JSON.stringify(lk));
  const r = await B.run(w, s.ids.P, "movedrive", { dest: "gigs" });
  check("the run moves it, id kept", r.ok && s.drive.path(s.ids.pdir) === "cinematography/zz-step7-scratch/gigs/zz-step7-test");
  const into = await B.look(w, s.ids.P, "movedrive", { dest: "custom", folder: [...s.drive.items.values()].find((x) => x.name === "1-creative" && x.parent === s.ids.pdir).id });
  check("into itself is refused", !into.can_run && /into itself/.test(into.problems.join(" ")));
  const out = await B.look(w, s.ids.P, "movedrive", { dest: "custom", folder: s.ids.outside });
  check("outside the folders is refused", !out.can_run);
  const u = await B.undo(w, r.move_id);
  check("undo moves it back", u.ok && s.drive.path(s.ids.pdir) === "cinematography/zz-step7-scratch/projects/zz-step7-test");
  const typed = await B.run(w, s.ids.P, "movedrive", { dest: "gigs", confirm: "wrong name" });
  check("a wrong typed name is refused at the run", !typed.ok && /doesn't match/.test(typed.why) && s.drive.path(s.ids.pdir).endsWith("projects/zz-step7-test"));
  const arc = await B.run(w, s.ids.P, "movedrive", { dest: "archive" });
  check("ARCHIVE makes the year folder and moves it there", arc.ok && s.drive.path(s.ids.pdir).endsWith("projects/z-archived/2026/zz-step7-test"));
}

console.log("rename");
{
  const s = W.standing();
  const w = s.world();
  const before = snap(s);
  const lk = await B.look(w, s.ids.P, "rename", { new_name: "zz step7 renamed", new_slug: "zz-step7-renamed" });
  check("the look writes nothing; names, folder, showcase; footage keeps its name; typed arm", same(snap(s), before) && lk.can_run && lk.arm === "typed"
    && lk.lines.some((l) => l.text === "Name: zz step7 test → zz step7 renamed") && lk.lines.some((l) => l.text === "Drive folder → zz-step7-renamed")
    && lk.lines.some((l) => l.text === "Showcase → zz-step7-renamed-showcase") && lk.lines.some((l) => /Media on zz-scratch-media keeps its folder name \(zz-step7-test\)/.test(l.text))
    && lk.lines.some((l) => l.text === "Share links don't change"), JSON.stringify(lk.lines));
  const bad = await B.look(w, s.ids.P, "rename", { new_slug: "Bad Name" });
  check("a folder name with capitals or spaces is refused", !bad.can_run && /lowercase/.test(bad.problems[0]));
  s.drive.add(s.ids.sp, "zz-step7-taken");
  const taken = await B.look(w, s.ids.P, "rename", { new_slug: "zz-step7-taken" });
  check("a name already there is refused", !taken.can_run && /already there: zz-step7-taken/.test(taken.problems[0]));
  // the planted failure: the showcase rename fails after the folder's
  s.drive.failNext((op, id) => op === "rename" && id === s.ids.show);
  const rf = await B.run(w, s.ids.P, "rename", { new_name: "zz step7 renamed", new_slug: "zz-step7-renamed" });
  check("forced failure on the second Drive rename: everything put back", !rf.ok && /Nothing was changed/.test(rf.why)
    && s.drive.items.get(s.ids.pdir).name === "zz-step7-test" && s.drive.items.get(s.ids.show).name === "zz-step7-test-showcase"
    && s.n.title(s.ids.P) === "zz step7 test" && recordOf(s, s.ids.P).name === "zz step7 test" && !recordOf(s, s.ids.P).moving, JSON.stringify(rf));
  // a failure at the very end (the record) puts the Drive and Notion back too
  s.n.failNext(() => false);
  const r = await B.run(w, s.ids.P, "rename", { new_name: "zz step7 renamed", new_slug: "zz-step7-renamed" });
  const rec = recordOf(s, s.ids.P);
  check("the run: Notion title, folder, showcase (ids kept), record name/slug/title", r.ok && s.n.title(s.ids.P) === "zz step7 renamed"
    && s.drive.items.get(s.ids.pdir).name === "zz-step7-renamed" && s.drive.items.get(s.ids.show).name === "zz-step7-renamed-showcase"
    && rec.name === "zz step7 renamed" && rec.slug === "zz-step7-renamed" && rec.facts.title.value === "zz step7 renamed" && rec.drive.name === "zz-step7-renamed", JSON.stringify(r));
  check("the record keeps each drive's footage folder name", same(rec.media_names, { "zz-scratch-media": "zz-step7-test" }));
  check("share links unchanged: the portal's objects are untouched", same(snap(s).bucket.filter(([k]) => k.startsWith("p/")), before.bucket.filter(([k]) => k.startsWith("p/"))));
  const u = await B.undo(w, r.move_id);
  const back = recordOf(s, s.ids.P);
  check("undo renames everything back, media_names gone", u.ok && s.n.title(s.ids.P) === "zz step7 test" && s.drive.items.get(s.ids.pdir).name === "zz-step7-test"
    && s.drive.items.get(s.ids.show).name === "zz-step7-test-showcase" && back.name === "zz step7 test" && back.slug === "zz-step7-test"
    && back.facts.title.value === "zz step7 test" && back.media_names === undefined, JSON.stringify(u));
  const nameOnly = await B.run(w, s.ids.P, "rename", { new_name: "zz step7 only name" });
  check("the formal name alone moves no folder", nameOnly.ok && s.drive.items.get(s.ids.pdir).name === "zz-step7-test" && s.n.title(s.ids.P) === "zz step7 only name");
  // a real (non-scratch) rename queues the bridge list and Studio's folder
  const t = W.standing();
  const tw = t.world();
  setMode(t, "rename", "live");
  const rr = await B.run(tw, t.ids.R, "rename", { new_slug: "real-two" });
  check("live rename of a real project queues the Drive bridge list for the Studio Mac", rr.ok && t.jobs.list.some((j) => j.kind === "bridge-list" && j.args.old === "real-one" && j.args.new === "real-two" && j.move_id === rr.move_id), JSON.stringify(t.jobs.list));
  t.jobs.list[0].state = "running";
  const blocked = await B.undo(tw, rr.move_id);
  check("undo waits while a Mac runs that move's job", !blocked.ok && /Wait for it to finish/.test(blocked.why) && t.drive.items.get(t.ids.real).name === "real-two");
  t.jobs.list[0].state = "waiting";
  const ok = await B.undo(tw, rr.move_id);
  check("undo cancels the move's waiting jobs first, then renames back", ok.ok && t.jobs.list[0].state === "cancelled" && t.drive.items.get(t.ids.real).name === "real-one");
}

console.log("turn off");
{
  const s = W.standing();
  const w = s.world();
  const m = await B.look(w, s.ids.P, "turnoff", { system: "media" });
  check("media is not Turn Off's: footage is never touched", !m.can_run && m.problems[0] === "Footage is never touched.");
  for (const sys of ["film", "filmpage"]) {
    const x = await B.look(w, s.ids.P, "turnoff", { system: sys });
    check(`${sys} is gone from Turn Off`, !x.can_run && /showcase and the website link/.test(x.problems[0]));
  }
  const nl = await B.look(w, s.ids.P, "turnoff", { system: "drive" });
  check("the project itself points at Delete", /Use Delete/.test(nl.problems[0]));
  const lk = await B.look(w, s.ids.P, "turnoff", { system: "showcase" });
  check("showcase: MOVES into project-showcases/zz-archived/<year>/, never a trash, click twice", lk.can_run && lk.heading === "MOVES"
    && /zz-step7-test-showcase · 0 files → project-showcases\/zz-archived\/2026\/$/.test(lk.lines[0].text) && lk.arm === "twice"
    && lk.button === "Move to Archive" && !/trash/i.test(JSON.stringify(lk)), JSON.stringify(lk));
  const r = await B.run(w, s.ids.P, "turnoff", { system: "showcase" });
  check("the run moves the showcase into zz-archived/2026/, id kept, nothing trashed", r.ok
    && s.drive.path(s.ids.show) === "cinematography/zz-step7-scratch/portfolio/project-showcases/zz-archived/2026/zz-step7-test-showcase"
    && ![...s.drive.items.values()].some((x) => x.trashed), JSON.stringify(r));
  const again = await B.look(w, s.ids.P, "turnoff", { system: "showcase" });
  check("turning it off again is refused: already in the archive", !again.can_run && /already in the archive/.test(again.problems.join(" ")));
  const u = await B.undo(w, r.move_id);
  check("undo moves it back, id kept", u.ok && s.drive.path(s.ids.show) === "cinematography/zz-step7-scratch/portfolio/project-showcases/zz-step7-test-showcase");
  const zz = [...s.drive.items.values()].find((x) => x.name === "zz-archived" && x.parent === s.ids.ssc);
  const yr = [...s.drive.items.values()].find((x) => x.name === "2026" && x.parent === zz.id);
  s.drive.add(yr.id, "zz-step7-test-showcase");
  const clash = await B.look(w, s.ids.P, "turnoff", { system: "showcase" });
  check("one already in that year's archive is refused, by hand first", !clash.can_run && /already exists/.test(clash.problems.join(" ")));
  const wl = await B.look(w, s.ids.P, "turnoff", { system: "website" });
  check("website: FORGETS, one click", wl.can_run && wl.heading === "FORGETS" && wl.arm === "click" && wl.lines[0].text === "https://your-website.example/zz");
  const wr = await B.run(w, s.ids.P, "turnoff", { system: "website" });
  check("the run forgets the address", wr.ok && s.n.pages.get(s.ids.P).properties.Website.url === null);
  const wu = await B.undo(w, wr.move_id);
  check("undo puts the address back", wu.ok && s.n.pages.get(s.ids.P).properties.Website.url === "https://your-website.example/zz");
}

console.log("delete");
{
  const s = W.standing();
  const w = s.world();
  const before = snap(s);
  const lk = await B.look(w, s.ids.P, "delete");
  check("the look writes nothing", same(snap(s), before));
  check("the look names every place it removes from", lk.can_run && lk.arm === "typed" && lk.confirm === "zz step7 test"
    && ["Notion · zz step7 test and its 2 shoot rows → Notion's trash", "Drive · projects/zz-step7-test → Drive's trash", "Showcase · zz-step7-test-showcase → Drive's trash",
      "Project record · off every list", "Studio · zz step7 test · removed from Studio on every Mac", "Portal · taken down, its share links stop working"]
      .every((t) => lk.lines.some((l) => l.text === t)), JSON.stringify(lk.lines));
  check("…what it leaves (Job Log, the footage and where), and 30 days", lk.stays.some((l) => l.text === "Job Log row")
    && lk.stays.some((l) => /Footage on zz-scratch-media · 1 GB · stays on that drive, in zz-step7-test/.test(l.text)) && lk.footer === "Everything here can be brought back for 30 days.");
  check("…and flags the real content", lk.flags.some((f) => /14 shots in 3 scenes/.test(f)) && lk.flags.some((f) => /2 files/.test(f))
    && lk.flags.some((f) => /1 person can open the portal/.test(f)) && lk.flags.some((f) => /1 share link will stop working/.test(f)), JSON.stringify(lk.flags));
  // backup before any write: a backup that fails leaves everything as it was
  const real = s.BUCKET.put;
  s.BUCKET.put = async (k, v, o) => (k.endsWith("backup.json") ? (() => { throw new Error("planted: backup refused"); })() : real.call(s.BUCKET, k, v, o));
  const failed = await throws(() => B.run(w, s.ids.P, "delete"));
  s.BUCKET.put = real;
  check("a backup that can't be written stops the delete before any write", failed && /planted/.test(failed.message)
    && !s.n.pages.get(s.ids.P).in_trash && ![...s.drive.items.values()].some((x) => x.trashed) && s.BUCKET.objects.has(`p/${s.ids.RELAY}/manifest.json`)
    && !recordOf(s, s.ids.P).deleted, failed && failed.message);
  // order: the backup is written before the first Notion or Drive write
  const order = [];
  const np = s.n.patch; s.n.patch = async (...a) => { order.push("notion"); return np(...a); };
  const dt = s.drive.trash; s.drive.trash = async (...a) => { order.push("drive"); return dt(...a); };
  const bp = s.BUCKET.put; s.BUCKET.put = async (k, ...a) => { if (k.endsWith("backup.json")) order.push("backup"); return bp.call(s.BUCKET, k, ...a); };
  const r = await B.run(w, s.ids.P, "delete");
  s.n.patch = np; s.drive.trash = dt; s.BUCKET.put = bp;
  check("the backup comes first, then Notion and the Drive", r.ok && order[0] === "backup" && order.includes("notion") && order.includes("drive"), JSON.stringify(order));
  check("Notion page and both Shoots rows in Notion's trash", s.n.pages.get(s.ids.P).in_trash && s.n.pages.get("dddddddddddddddddddddddddddddd11").in_trash && s.n.pages.get("dddddddddddddddddddddddddddddd12").in_trash);
  check("Drive folder and showcase in the Drive's trash, nothing else", s.drive.items.get(s.ids.pdir).trashed && s.drive.items.get(s.ids.show).trashed
    && [...s.drive.items.values()].filter((x) => x.trashed).length === 2);
  check("Studio side and portal gone, the relay's note says deleted", ![...s.BUCKET.objects.keys()].some((k) => k.startsWith(`p/${s.ids.RELAY}/`))
    && JSON.parse(s.BUCKET.objects.get(`gone/${s.ids.RELAY}.json`).body).fate === "deleted");
  check("another project's portal untouched", s.BUCKET.objects.has("p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee99/people.json"));
  const rec = recordOf(s, s.ids.P);
  check("the record is a tombstone, not gone", rec.deleted && rec.deleted.move_id === r.move_id && rec.name === "zz step7 test");
  const old = await B.look(w, s.ids.P, "wrap");
  check("the old id still answers: deleted", !old.ok && old.deleted === true && old.why === "This project was deleted.");
  const door = await B.door(s.env, ["bigmoves", "project", s.ids.P], "GET");
  check("the door answers deleted for the old id (not a bare 404)", door.status === 200 && (await door.json()).deleted === true);
  const { buildList } = await import("./src/onelist.js");
  const listed = buildList({ pages: [], crew: [], shoots: [], records: { [s.ids.P]: { ...rec, kind: "job" } }, saved: {}, now: "2026-10-15" });
  check("the list drops a tombstoned record", listed.jobs.length === 0);
  const backup = JSON.parse(s.BUCKET.objects.get(`bigmoves/backups/${r.move_id}/backup.json`).body);
  check("the backup holds the record, the Notion page, both Shoots rows, the Drive ids, the portal", backup.record.name === "zz step7 test"
    && backup.notion.id === s.ids.P && backup.shoots.length === 2 && backup.drive.folder.id === s.ids.pdir && backup.portal[s.ids.RELAY] === 4);
  const u = await B.undo(w, r.move_id);
  const after = snap(s);
  check("undo brings every piece back (Drive, Notion, portal, record)", u.ok && same(after.tree, before.tree) && same(after.notion, before.notion)
    && same(after.bucket.filter(([k]) => k.startsWith("p/") || k.startsWith("r/") && !k.includes("/history/")), before.bucket.filter(([k]) => k.startsWith("p/") || k.startsWith("r/") && !k.includes("/history/")))
    && !s.BUCKET.objects.has(`gone/${s.ids.RELAY}.json`), JSON.stringify(u));
  const late = W.standing();
  const lw = late.world();
  const lr = await B.run(lw, late.ids.P, "delete");
  const later = { ...lw, now: () => new Date(W.nowFixed.getTime() + 31 * 86400000) };
  const tooLate = await B.undo(later, lr.move_id);
  check("after 30 days undo says it's too late", !tooLate.ok && tooLate.why === "Too late to undo. Undo lasts 30 days.");
}

console.log("a deleted project stays gone (2026-10-17)");
{
  const G = await import("./src/deletedguard.js");
  const { filmsFor } = await import("./src/films.js");
  const s = W.standing();
  const w = s.world();
  const before = snap(s);
  const r = await B.run(w, s.ids.P, "delete");
  const R = s.ids.RELAY;
  const stone = s.BUCKET.objects.get(`bigmoves/deleted/${R}.json`);
  check("Delete leaves a tombstone for the prefix it removed", r.ok && stone && JSON.parse(stone.body).move_id === r.move_id);
  const guarded = G.stayGone(s.env);
  const refused = await throws(() => guarded.BUCKET.put(`p/${R}/front.json`, "{}"));
  check("a clock's write under the deleted id is refused", refused instanceof G.StaysGone && !s.BUCKET.objects.has(`p/${R}/front.json`));
  await guarded.BUCKET.put("p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee99/front.json", "{}");
  check("…and another project's goes through", s.BUCKET.objects.has("p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee99/front.json"));
  const anchored = G.stayGone(s.env, { anchors: { eeeeeeeeeeeeeeeeeeeeeeeeeeeeee77: ["p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee77/portal.json"] } });
  const noAnchor = await throws(() => anchored.BUCKET.put("p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee77/front.json", "{}"));
  check("a card whose project file went mid-card is not written", noAnchor instanceof G.StaysGone);
  // Leftovers written back the old way (before the guard): a front page and a cover.
  s.BUCKET.objects.set(`p/${R}/front.json`, { body: "{}", etag: 90 });
  s.BUCKET.objects.set(`p/${R}/media/cover.png`, { body: "png", etag: 91 });
  const owner = { ...s.env, OWNER: "him@example.com" };
  const shelf = await filmsFor(owner, { email: "him@example.com" });
  check("the shelf skips leftovers (no manifest, no mark, no logs)", !shelf.some((f) => f.project === R), JSON.stringify(shelf));
  const look = await B.sweepLeftovers(s.env, { dry: true });
  check("the leftovers look names them and removes nothing", look.swept.length === 1 && look.swept[0].files.length === 2 && s.BUCKET.objects.has(`p/${R}/front.json`), JSON.stringify(look));
  const swept = await B.sweepLeftovers(s.env, { dry: false, by: "check" });
  const kept = [...s.BUCKET.objects.keys()].filter((k) => k.startsWith(`bigmoves/backups/${r.move_id}/leftovers/`));
  check("the sweep keeps a copy under the move's backup, then takes them away", swept.ok && swept.swept.length === 1
    && ![...s.BUCKET.objects.keys()].some((k) => k.startsWith(`p/${R}/`)) && kept.some((k) => k.endsWith("media/cover.png")) && kept.some((k) => k.endsWith("leftovers.json")), JSON.stringify({ swept, kept }));
  s.BUCKET.objects.set(`p/${R}/manifest.json`, { body: "{}", etag: 92 });
  s.BUCKET.objects.set(`p/${R}/front.json`, { body: "{}", etag: 93 });
  const held = await B.sweepLeftovers(s.env, { dry: false });
  check("a prefix holding a project file is left alone", held.swept.length === 0 && held.left.length === 1 && s.BUCKET.objects.has(`p/${R}/front.json`), JSON.stringify(held));
  s.BUCKET.objects.delete(`p/${R}/manifest.json`); s.BUCKET.objects.delete(`p/${R}/front.json`);
  const other = await B.sweepLeftovers(s.env, { dry: false });
  check("nothing but deleted ids is ever swept", s.BUCKET.objects.has("p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee99/people.json") && other.swept.length === 0);
  const u = await B.undo(G.stayGone(s.env) === s.env ? w : { ...w, env: G.stayGone(s.env) }, r.move_id);
  const after = snap(s);
  const portal = (b) => b.bucket.filter(([k]) => k.startsWith(`p/${R}/`));
  check("undo (on a guarded clock's bucket too) brings it all back and takes the tombstone away", u.ok && same(portal(after), portal(before))
    && !s.BUCKET.objects.has(`bigmoves/deleted/${R}.json`) && !s.BUCKET.objects.has(`gone/${R}.json`), JSON.stringify(u));
  await G.stayGone(s.env).BUCKET.put(`p/${R}/front.json`, JSON.stringify({ title: "zz step7 test" }));
  check("…and the clocks may write to it again", true);
}
{
  // A deleted project's Notion-link questions drop out (the phone's "1 to settle").
  const NS = await import("./src/notionsync.js");
  const s = W.standing();
  const w = s.world();
  const q = (page, met) => ({ page, kind: "notion", changes: { status: ["Development", 1] }, theirs: { status: { value: "Released", v: 1 } }, by: "notion", met_at: met });
  s.BUCKET.objects.set("s/notion-conflicts.json", { body: JSON.stringify({ conflicts: [q(s.ids.P, 1.5), q(s.ids.R, 2.5), q("ffffffffffffffffffffffffffffff09", 3.5)] }), etag: 1 });
  const before = await NS.conflictsList(s.env);
  check("a record-less project's question never shows", before.length === 2 && !before.some((c) => c.page === "ffffffffffffffffffffffffffffff09"), JSON.stringify(before));
  const r = await B.run(w, s.ids.P, "delete");
  const during = await NS.conflictsList(s.env);
  check("after Delete only the standing project's question shows", r.ok && during.length === 1 && during[0].page === s.ids.R, JSON.stringify(during));
  const u = await B.undo(w, r.move_id);
  check("Undo brings the question back", u.ok && (await NS.conflictsList(s.env)).length === 2);
  const r2 = await B.run(w, s.ids.P, "delete");
  const swept = await B.sweepLeftovers(s.env, { dry: false, by: "check" });
  const file = JSON.parse(s.BUCKET.objects.get("s/notion-conflicts.json").body).conflicts;
  check("the leftovers door takes the dead questions off, a copy kept", r2.ok && swept.conflicts.length === 2 && swept.conflicts_kept
    && file.length === 1 && file[0].page === s.ids.R && JSON.parse(s.BUCKET.objects.get(swept.conflicts_kept).body).conflicts.length === 2, JSON.stringify(swept));
}
{
  // The race itself: the refresh made its list, then the project was deleted.
  const RH = await import("./src/refreshhub.js");
  const b = W.bucketOf();
  const env = { BUCKET: b };
  const A = "ffffffffffffffffffffffffffffff01";
  const Z = "ffffffffffffffffffffffffffffff02";
  for (const id of [A, Z]) b.objects.set(`p/${id}/portal.json`, { body: JSON.stringify({ title: `zz race ${id.slice(-1)}`, page: id }), etag: 1 });
  const items = await RH.itemsNow(env);
  b.objects.set("s/portal-refresh.json", { body: JSON.stringify({ pass: { id: "x", started: "2026-10-16T08:29:00Z", items, at: 0, standing: [A, Z], results: {} } }), etag: 1 });
  for (const k of [...b.objects.keys()]) if (k.startsWith(`p/${A}/`)) b.objects.delete(k);                 // A: deleted, prefix gone
  b.objects.set(`bigmoves/deleted/${Z}.json`, { body: JSON.stringify({ move_id: "mv-0000000000000001" }), etag: 1 }); // Z: tombstone, mid-delete
  const t = await RH.refreshTick(env, null, Date.parse("2026-10-16T08:31:00Z"), { all: true });
  check("the refresh passes over a project deleted since its list was made", items.length === 2
    && ![...b.objects.keys()].some((k) => k.startsWith(`p/${A}/`)) && !b.objects.has(`p/${Z}/front.json`)
    && t.lines.some((l) => /gone since this pass began/.test(l)) && t.lines.some((l) => /deleted since this pass began/.test(l)), JSON.stringify(t.lines));
}

console.log("prepare showcase");
{
  const s = W.standing();
  const w = s.world();
  // no selects picked: nothing to make
  const none = await B.look(w, s.ids.P, "showcase");
  check("no selects picked: Pick selects first.", !none.can_run && none.problems.includes("Pick selects first.") && same(none.files, []), JSON.stringify(none.problems));
  // two picks: one already in the showcase's stills/, one from the shoot's selects
  const stillsDir = [...s.drive.items.values()].find((x) => x.parent === s.ids.show && x.name === "stills").id;
  const inShow = s.drive.add(stillsDir, "zz-step7-test-00001517-showcase-stills.webp", false);
  const fromSel = [...s.drive.items.values()].find((x) => x.parent === s.ids.sel && x.name === "A001_1.2.3.png").id;
  const rec = JSON.parse(s.BUCKET.objects.get(`r/${s.ids.P}/record.json`).body);
  rec.facts.selects = { value: [inShow, fromSel], v: 1 };
  rec.facts.my_credit = { value: "Cinematographer", v: 1 };
  rec.facts.released_date = { value: "2026-09-01", v: 1 };
  rec.facts.type = { value: "Narrative", v: 1 };
  rec.facts.length = { value: "Short", v: 1 };
  rec.facts.credits = { value: [{ role: "Director", people: ["Zed Tester"] }], v: 1 };
  rec.facts.crew = { value: [{ name: "Ann Gaffer", roles: ["Gaffer"] }], v: 1 };
  s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec), etag: 7 });
  const before = snap(s);
  const lk = await B.look(w, s.ids.P, "showcase");
  const paths = (lk.files || []).map((f) => `${f.path}:${f.state}`);
  check("the look writes nothing; lists every file, the showcase's own still kept", same(snap(s), before) && lk.can_run
    && same(paths, ["select-stills/:new", "stills/zz-step7-test-00001517-showcase-stills.webp:kept", "select-stills/zz-step7-test-01-00001517-showcase-stills.webp:new",
      "stills/zz-step7-test-1.2.3-showcase-stills.webp:new", "select-stills/zz-step7-test-02-1.2.3-showcase-stills.webp:new", "credits.txt:new"])
    && !paths.some((x) => x.startsWith("website")) && lk.counts.new === 4 && lk.counts.kept === 1 && lk.where.endsWith("zz-step7-test-showcase"), JSON.stringify(paths));
  check("the look's words: pictures need a Mac, no thumbnail or grid image", lk.lines.some((l) => l.text === "1 still into stills/ (.webp, fits 2560×1440, under 1MB)" && l.who === "Needs a Mac")
    && lk.lines.some((l) => l.text === "2 select stills into select-stills/, numbered in your order") && !lk.lines.some((l) => /thumb|grid|website/i.test(l.text)), JSON.stringify(lk.lines));
  const r = await B.run(w, s.ids.P, "showcase");
  const tree = s.drive.tree(s.ids.ssc);
  check("the run: select-stills/ and credits.txt (at the root) made, stills/ kept, no website/", r.ok && tree.includes("zz-step7-test-showcase/select-stills/")
    && tree.includes("zz-step7-test-showcase/credits.txt") && tree.includes("zz-step7-test-showcase/stills/") && !tree.some((x) => /website/.test(x)), JSON.stringify(tree));
  const credits = [...s.drive.items.values()].find((x) => x.parent === s.ids.show && x.name === "credits.txt");
  const showRoot = [...s.drive.items.values()].filter((x) => x.parent === s.ids.show && x.name === ".portfolio-project");
  check("the marker is there once", showRoot.length === 1);
  check("credits.txt: title, what and when, every credit, his own, the crew, the website", credits && /^zz step7 test\nNarrative Short, 2026\nReleased September 1, 2026\n\nDirector +Zed Tester\nCinematographer +Nathaniel Regier\n\nGaffer +Ann Gaffer\n\nhttps:\/\/your-website.example\/zz\n$/.test(credits.text), JSON.stringify(credits && credits.text));
  const job = s.jobs.list.find((j) => j.kind === "showcase-stills");
  check("one Mac job: the 3 pictures to make, each with its source and place", job && job.args.files.length === 3
    && same(job.args.files.map((f) => f.dst), ["select-stills/zz-step7-test-01-00001517-showcase-stills.webp", "stills/zz-step7-test-1.2.3-showcase-stills.webp", "select-stills/zz-step7-test-02-1.2.3-showcase-stills.webp"])
    && job.args.files[0].src.showcase === "stills/zz-step7-test-00001517-showcase-stills.webp"
    && job.args.files[1].src.dir.endsWith("zz-step7-scratch/projects/zz-step7-test/3-post/shoot-1/selects")
    && job.needs.tools.includes("cwebp") && job.needs.tools.includes("showcase-picks") && !job.needs.drive && !JSON.stringify(job.args).includes("/Volumes"), JSON.stringify(job && job.args));
  const r2 = await B.run(w, s.ids.P, "showcase");
  check("a second run makes no new file on the server", r2.ok && same(s.drive.tree(s.ids.ssc), tree));
  check("Prepare Showcase is not undone (it only adds)", r.undo === false && !(await B.undo(w, r.move_id)).ok);
  // a showcase without its marker gets one (the look listed it)
  for (const x of [...s.drive.items.values()]) if (x.parent === s.ids.show && x.name === ".portfolio-project") s.drive.items.delete(x.id);
  const lkm = await B.look(w, s.ids.P, "showcase");
  const rm = await B.run(w, s.ids.P, "showcase");
  check("a missing marker is listed and made", lkm.files.some((f) => f.kind === "marker" && f.state === "new") && rm.ok
    && [...s.drive.items.values()].some((x) => x.parent === s.ids.show && x.name === ".portfolio-project"));
  // a different credits.txt already there is kept; the new one is dated beside it
  credits.text = "old words\n";
  const lk3 = await B.look(w, s.ids.P, "showcase");
  check("an existing, different credits.txt is kept; credits-<day>.txt beside it", lk3.files.some((f) => /^credits-\d{8}\.txt$/.test(f.path) && f.state === "new")
    && !lk3.files.some((f) => f.path === "credits.txt" && f.state === "new"), JSON.stringify(lk3.files));
  // a hand-made website/ is never read or written
  const hand = s.drive.add(s.ids.show, "website", true);
  const handFile = s.drive.add(hand, "thumb.jpg", false);
  const before4 = [...s.drive.items.values()].filter((x) => x.parent === hand).map((x) => x.name).join();
  // select-stills: he re-picks (drops the first, adds nothing) -> the old numbered copies move to z-archive, no delete
  const selDir = [...s.drive.items.values()].find((x) => x.parent === s.ids.show && x.name === "select-stills");
  const f1 = s.drive.add(selDir.id, "zz-step7-test-01-00001517-showcase-stills.webp", false);
  const f2 = s.drive.add(selDir.id, "zz-step7-test-02-1.2.3-showcase-stills.webp", false);
  const byHand = s.drive.add(selDir.id, "my-own-note.webp", false);
  const rec2 = JSON.parse(s.BUCKET.objects.get(`r/${s.ids.P}/record.json`).body);
  rec2.facts.selects = { value: [fromSel], v: 2 };
  s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec2), etag: 9 });
  const lk5 = await B.look(w, s.ids.P, "showcase");
  const arch = lk5.files.filter((f) => f.kind === "archive").map((f) => f.path);
  check("re-pick: the new order numbers 01, the old numbers are listed to move to select-stills/z-archive/, a hand-put file is left", same(arch, ["select-stills/z-archive/zz-step7-test-01-00001517-showcase-stills.webp", "select-stills/z-archive/zz-step7-test-02-1.2.3-showcase-stills.webp"])
    && lk5.files.some((f) => f.path === "select-stills/zz-step7-test-01-1.2.3-showcase-stills.webp" && f.state === "new") && lk5.counts.moved === 2, JSON.stringify(lk5.files.map((f) => `${f.path}:${f.state}`)));
  const a1 = lk5.files.find((f) => f.path.endsWith("-01-00001517-showcase-stills.webp") && f.kind === "archive"), a2 = lk5.files.find((f) => f.path.endsWith("-02-1.2.3-showcase-stills.webp") && f.kind === "archive");
  check("re-pick: a select dropped says so (from 1, to nothing); the same shot renumbered says 2 -> 1; each new select carries its number",
    a1 && a1.from === 1 && a1.to === null && a1.still === null && a1.id === f1 && a2 && a2.from === 2 && a2.to === 1 && a2.still === fromSel
    && lk5.files.find((f) => f.kind === "select" && f.state === "new").n === 1, JSON.stringify([a1, a2]));
  // a second select-stills/ on the Drive (a Mac's and a server-made one): its files count as kept, its files are never moved
  const twin = s.drive.add(s.ids.show, "select-stills", true);
  const tw1 = s.drive.add(twin, "zz-step7-test-01-1.2.3-showcase-stills.webp", false);
  const lkT = await B.look(w, s.ids.P, "showcase");
  check("two select-stills folders: the one's files count as kept, the note says so, nothing of the twin is archived",
    lkT.files.find((f) => f.path === "select-stills/zz-step7-test-01-1.2.3-showcase-stills.webp").state === "kept" && lkT.notes.some((n) => /on the Drive twice/.test(n)) && !lkT.files.some((f) => f.kind === "archive" && /01-1.2.3/.test(f.path)), JSON.stringify(lkT.files.map((f) => `${f.path}:${f.state}`)));
  s.drive.items.delete(tw1); s.drive.items.delete(twin);
  const r5 = await B.run(w, s.ids.P, "showcase");
  const arc = [...s.drive.items.values()].find((x) => x.parent === selDir.id && x.name === "z-archive");
  const inArc = arc ? [...s.drive.items.values()].filter((x) => x.parent === arc.id).map((x) => x.name).sort() : [];
  check("the run moved them (ids kept, nothing trashed), left the hand-put file, never touched website/", r5.ok && same(inArc, ["zz-step7-test-01-00001517-showcase-stills.webp", "zz-step7-test-02-1.2.3-showcase-stills.webp"])
    && s.drive.items.get(f1) && s.drive.items.get(f1).parent === arc.id && s.drive.items.get(byHand).parent === selDir.id
    && [...s.drive.items.values()].filter((x) => x.parent === hand).map((x) => x.name).join() === before4 && !s.drive.items.get(f2).trashed, JSON.stringify({ r5, inArc }));
}

console.log("history undo");
{
  const s = W.standing();
  const w = s.world();
  const r = await B.run(w, s.ids.P, "turnoff", { system: "website" });
  const H = await import("./src/step6history.js");
  const entries = await H.listActivity(s.env);
  check("the history line carries the move's undo", entries[0].undo && entries[0].undo.type === "bigmove" && entries[0].undo.move_id === r.move_id);
  const mv = await B.moveOf(s.env, r.move_id);
  check("the move is kept with what undo needs", mv.kind === "turnoff" && mv.undo.website === "https://your-website.example/zz");
  const moves = await B.movesFor(s.env, s.ids.P);
  check("the project's moves, newest first", moves.length === 1 && moves[0].id === r.move_id);
}

console.log("no trash but Delete (his rule, 2026-10-15 morning)");
{
  // Every move but Delete, run and undone on its own world: nothing may go to
  // the Drive's trash, Notion's trash, or out of the bucket.
  const runs = [
    ["wrap", {}], ["archive", {}], ["movedrive", { dest: "gigs" }], ["rename", { new_name: "zz step7 renamed", new_slug: "zz-step7-renamed" }],
    ["turnoff", { system: "showcase" }], ["turnoff", { system: "website" }], ["showcase", {}],
  ];
  for (const [kind, opts] of runs) {
    const s = W.standing();
    const w = s.world();
    if (kind === "wrap") s.n.pages.get("dddddddddddddddddddddddddddddd12").properties.Dates.date = { start: "2026-10-05" };
    if (kind === "showcase") {
      const rec = JSON.parse(s.BUCKET.objects.get(`r/${s.ids.P}/record.json`).body);
      rec.facts.selects = { value: [[...s.drive.items.values()].find((x) => x.parent === s.ids.sel).id], v: 1 };
      s.BUCKET.objects.set(`r/${s.ids.P}/record.json`, { body: JSON.stringify(rec), etag: 7 });
    }
    const seen = [];
    const np = s.n.patch.bind(s.n);
    s.n.patch = async (path, body) => { if (body && (body.in_trash === true || body.archived === true)) seen.push(`notion ${path}`); return np(path, body); };
    const dt = s.drive.trash; s.drive.trash = async (id) => { seen.push(`drive ${id}`); return dt(id); };
    const bd = s.BUCKET.delete.bind(s.BUCKET); s.BUCKET.delete = async (k) => { seen.push(`r2 ${k}`); return bd(k); };
    const r = await B.run(w, s.ids.P, kind, opts);
    const u = r.ok && r.undo ? await B.undo(w, r.move_id) : { ok: true };
    const label = `${kind}${opts.system ? ` › ${opts.system}` : ""}`;
    check(`${label}: runs and undoes with nothing trashed or deleted anywhere`, r.ok && u.ok && !seen.length
      && ![...s.drive.items.values()].some((x) => x.trashed) && ![...s.n.pages.values()].some((p) => p.in_trash), JSON.stringify({ r, u, seen }));
  }
  {
    const s = W.standing();
    const w = B.noTrash(s.world({ fenced: s.drive }), "archive");
    const e1 = await throws(() => w.fenced.trash(s.ids.pdir));
    const e2 = await throws(() => w.raw.trash(s.ids.pdir));
    const e3 = await throws(() => w.n.patch(`pages/${s.ids.P}`, { in_trash: true }));
    const e4 = await throws(() => w.n.patch(`pages/${s.ids.P}`, { archived: true }));
    const e5 = await throws(() => w.env.BUCKET.delete(`r/${s.ids.P}/record.json`));
    check("the fence: Drive trash, Notion trash/archive and bucket delete all stop a non-Delete move",
      [e1, e2, e3, e4, e5].every((e) => e instanceof B.NoTrash && /only Delete does/.test(e.message))
      && !s.drive.items.get(s.ids.pdir).trashed && !s.n.pages.get(s.ids.P).in_trash && s.BUCKET.objects.has(`r/${s.ids.P}/record.json`));
    const ok = await w.n.patch(`pages/${s.ids.P}`, { properties: { Website: { url: null } } });
    check("…and ordinary writes still pass through", ok !== undefined && s.n.pages.get(s.ids.P).properties.Website.url === null);
    check("Delete alone runs on the plain world", B.noTrash(s.world(), "delete").drive === undefined && B.TRASHES.size === 1 && B.TRASHES.has("delete"));
  }
  {
    // A step inside Archive that tries to trash through its world stops it, and
    // all-or-nothing puts back what it did.
    const s = W.standing();
    const w = s.world();
    const np = s.n.patch.bind(s.n);
    s.n.patch = async (path, body) => np(path, body);
    const nt = B.noTrash;
    const base = s.world();
    const fenced = B.noTrash({ ...base, fenced: s.drive }, "archive").fenced;
    const mv = s.drive.move;
    s.drive.move = async (...a) => { await fenced.trash(a[0]); return mv(...a); };
    const r = await B.run(w, s.ids.P, "archive");
    s.drive.move = mv;
    check("a trash tried inside Archive stops it, nothing trashed, everything back", !r.ok && /only Delete does/.test(r.why)
      && ![...s.drive.items.values()].some((x) => x.trashed) && s.drive.path(s.ids.pdir) === "cinematography/zz-step7-scratch/projects/zz-step7-test"
      && s.n.status(s.ids.P) === "Active" && nt === B.noTrash, JSON.stringify(r));
  }
  {
    // In the code itself: every trash or delete call sits in Delete's own functions.
    const src = readFileSync(new URL("./src/bigmoves.js", import.meta.url), "utf8");
    const tops = [...src.matchAll(/^(?:export )?(?:async )?function (\w+)/gm)].map((m) => ({ name: m[1], at: m.index }));
    const owner = (at) => { let o = ""; for (const t of tops) if (t.at <= at) o = t.name; return o; };
    // `sweepLeftovers` is Delete's own: it takes away what was written back under a deleted project's id.
    const ALLOWED = new Set(["runDelete", "undoDelete", "deletePrefix", "noTrashDrive", "noTrashNotion", "noTrashEnv", "trashingBody", "sweepLeftovers"]);
    const bad = [];
    for (const m of src.matchAll(/\.trash\(|patch\([^\n]*(?:in_trash|archived|trashed): true|BUCKET\.delete\(|deletePrefix\(/g)) {
      const o = owner(m.index);
      if (!ALLOWED.has(o) && !(m[0] === "deletePrefix(" && o === "deletePrefix")) bad.push(`${o}: ${m[0]}`);
    }
    const callers = [...src.matchAll(/deletePrefix\(/g)].map((m) => owner(m.index)).filter((o) => o !== "deletePrefix");
    check("in the code, only Delete's own functions trash or delete", !bad.length && callers.every((o) => o === "runDelete" || o === "undoDelete"), JSON.stringify({ bad, callers }));
  }
}

console.log("a project with no record yet");
{
  const s = W.standing();
  const w = s.world();
  s.BUCKET.objects.delete(`r/${s.ids.P}/record.json`);
  for (const kind of ["wrap", "archive"]) {
    if (kind === "wrap") s.n.pages.get("dddddddddddddddddddddddddddddd12").properties.Dates.date = { start: "2026-10-05" };
    const r = await B.run(w, s.ids.P, kind);
    const u = r.ok ? await B.undo(w, r.move_id) : null;
    check(`${kind} runs and undoes with no record (Notion's status back)`, r.ok && u && u.ok && s.n.status(s.ids.P) === "Active", JSON.stringify({ r, u }));
  }
}

if (PLANT) check("planted: this must fail", false, "planted");
console.log(`\nbigmoves: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
