#!/usr/bin/env node
/**
 * **Released and Close Project** (`src/step6shelf.js`, 2026-10-15) on the big
 * moves' world held in memory (`bigmovesworld.mjs`):
 *
 * - Close writes the project file into the Drive folder, keeps the snapshot
 *   and the portal's own files hidden on the server, marks every portal id,
 *   sets the record Closed, and deletes nothing (no Drive trash, no bucket
 *   object gone, the film's logs untouched);
 * - the closed project leaves the one list; the portal's mark answers;
 * - Reopen takes the marks away and puts the status back; a project file
 *   brings back a record the server lost;
 * - the Released stills come from stills/ (stills/hq/ when there is one, else stills/lq/), read only;
 * - Released is a plain pick; Closed never is.
 *
 *     node hub/step6shelf.mjs
 */
import { register } from "node:module";
import { readFileSync } from "node:fs";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);

const S = await import("./src/step6shelf.js");
const six = await import("./src/step6.js");
const W = await import("./bigmovesworld.mjs");
const OL = await import("./src/onelist.js");
const NL = await import("./src/notionlink.js");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(88)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 700)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const recordOf = (s, id) => JSON.parse(s.BUCKET.objects.get(`r/${id}/record.json`).body);

console.log("the shape");
check("five asks: three on the spot, Close and Reopen held", same([...S.NOW], ["close_look", "closed_projects", "released_stills"])
  && same([...S.LATER_WRITES], ["close_project", "reopen_project"]) && S.METHODS.size === 5);
check("joined to step 6's doors under its own switch", six.GROUPS.some((g) => g.SWITCH === "step6shelf") && S.SWITCH_KEY === "s/step6-shelf.json");
check("one reason, his words", same(S.REASONS, ["Not Produced"]));
check("nothing here names a media drive or trashes", !/\/Volumes|\.trash\(|in_trash/.test(readFileSync(new URL("./src/step6shelf.js", import.meta.url), "utf8")));
check("the link may set Released and Closed, never Post or Archived", NL.STATUS_THE_LINK_MAY_SET.includes("Released")
  && NL.STATUS_THE_LINK_MAY_SET.includes("Closed") && !NL.STATUS_THE_LINK_MAY_SET.includes("Post") && !NL.STATUS_THE_LINK_MAY_SET.includes("Archived"));

console.log("close");
{
  const s = W.standing();
  const w = s.world();
  const keysBefore = new Set(s.BUCKET.objects.keys());
  const treeBefore = s.drive.tree(s.ids.cine);
  const lk = await S.closeLook(s.env, s.ids.P, { world: w });
  check("the look names the file and the folder, writes nothing", lk.ok && lk.can_run && lk.file === "zz-step7-test.project"
    && /zz-step7-test$/.test(lk.folder) && same(new Set(s.BUCKET.objects.keys()), keysBefore), JSON.stringify(lk));
  const r = await S.closeRun(s.env, s.ids.P, { reason: "Not Produced", by: "check" }, { world: w });
  check("the run answers in his words", r.ok && r.report === "zz step7 test closed." && r.file === "zz-step7-test.project", JSON.stringify(r));
  const kids = s.drive.items ? [...s.drive.items.values()].filter((i) => i.parent === s.ids.pdir || (i.parents || []).includes(s.ids.pdir)) : [];
  const file = kids.find((k) => k.name === "zz-step7-test.project");
  check("the project file is in the project's Drive folder", Boolean(file), JSON.stringify(kids.map((k) => k.name)));
  const body = file ? JSON.parse(file.text || file.body || "{}") : {};
  check("the file holds the record, the Notion row, the shoots and the portal's pages", body.kind === S.FILE_KIND && body.id === s.ids.P
    && body.record && body.record.name === "zz step7 test" && body.notion && body.shoots.length === 2
    && Object.keys(body.pages || {}).some((k) => k.endsWith("people.json")) && body.status_before === "Active", JSON.stringify(Object.keys(body)));
  const after = new Set(s.BUCKET.objects.keys());
  check("nothing in the bucket is gone (the film's logs stay)", [...keysBefore].every((k) => after.has(k) || k === `r/${s.ids.P}/record.json`)
    && after.has(`p/${s.ids.RELAY}/logs/0123456789abcdef-0123456789abcdef.log`));
  check("the hidden copy holds the portal's own files, not the film's", [...after].some((k) => /^closed\/a+01\/.+\/p\/c+03\/people\.json$/.test(k))
    && ![...after].some((k) => /^closed\/.+\/logs\//.test(k)) && [...after].some((k) => /^closed\/a+01\/.+\/project\.json$/.test(k)));
  check("every portal id is marked closed", Boolean(await S.closedMark(s.env, s.ids.RELAY)) && Boolean(await S.closedMark(s.env, s.ids.P))
    && (await S.closedMark(s.env, s.ids.RELAY)).name === "zz step7 test" && !(await S.closedMark(s.env, s.ids.R)));
  const rec = recordOf(s, s.ids.P);
  check("the record: Closed, with how to reopen it", rec.closed && rec.closed.reason === "Not Produced" && rec.closed.status_before === "Active"
    && rec.facts.status.value === "Closed" && rec.facts.close_reason.value === "Not Produced" && rec.closed.file.name === "zz-step7-test.project", JSON.stringify(rec.closed));
  check("Notion's Status follows", s.n.status(s.ids.P) === "Closed");
  check("nothing on the Drive was moved or trashed: one file added", (() => {
    const t = s.drive.tree(s.ids.cine);
    const added = t.filter((x) => !treeBefore.includes(x));
    return treeBefore.every((x) => t.includes(x)) && same(added, ["zz-step7-scratch/projects/zz-step7-test/zz-step7-test.project"]);
  })(), JSON.stringify(s.drive.tree(s.ids.cine).filter((x) => !treeBefore.includes(x))));
  const again = await S.closeRun(s.env, s.ids.P, {}, { world: w });
  check("closing twice is refused", !again.ok && again.why === "This project is already closed.");
  const list = await S.closedProjects(s.env);
  check("the closed list has it", list.ok && list.closed.length === 1 && list.closed[0].id === s.ids.P && list.closed[0].reason === "Not Produced");

  // off the one list
  const pages = [...s.n.pages.values()].filter((p) => p.source === OL.SOURCES.projects);
  const records = Object.fromEntries([...s.BUCKET.objects.entries()].filter(([k]) => /^r\/[0-9a-f]{32}\/record\.json$/.test(k)).map(([k, v]) => [k.split("/")[1], JSON.parse(v.body)]));
  const built = OL.buildList({ pages, crew: [], shoots: [], records, saved: {}, now: "2026-10-15" });
  check("a closed project is off the one list; the other stays", !built.projects.some((p) => p.name === "zz step7 test")
    && built.projects.some((p) => p.name === "Real One"), JSON.stringify(built.projects.map((p) => [p.name, p.status])));

  // reopen
  const back = await S.reopenRun(s.env, { id: s.ids.P, by: "check" }, { world: w });
  check("reopen: the status it had, the marks gone", back.ok && back.status === "Active" && !(await S.closedMark(s.env, s.ids.RELAY))
    && !recordOf(s, s.ids.P).closed && recordOf(s, s.ids.P).facts.status.value === "Active" && s.n.status(s.ids.P) === "Active", JSON.stringify(back));
  check("reopening twice is refused", !(await S.reopenRun(s.env, { id: s.ids.P }, { world: w })).ok);
  check("the project file stays in Drive after reopening", Boolean([...s.drive.items.values()].find((k) => k.name === "zz-step7-test.project")));

  // a second close names a new file, never over the first
  const r2 = await S.closeRun(s.env, s.ids.P, {}, { world: w });
  check("closing again saves a dated file beside the first", r2.ok && r2.file === "zz-step7-test-20261015.project", JSON.stringify(r2));

  // the file brings back a record the server lost
  const snapText = [...s.drive.items.values()].find((k) => k.name === "zz-step7-test.project");
  const snap = JSON.parse(snapText.text || snapText.body);
  s.BUCKET.objects.delete(`r/${s.ids.P}/record.json`);
  const fromFile = await S.reopenRun(s.env, { file: snap, by: "check" }, { world: w });
  check("Reopen from a project file restores a lost record", fromFile.ok && fromFile.restored && recordOf(s, s.ids.P).name === "zz step7 test"
    && !recordOf(s, s.ids.P).closed, JSON.stringify(fromFile));
  check("a file that is not a project file is refused", !(await S.reopenRun(s.env, { file: { kind: "something" } }, { world: w })).ok);
}

console.log("fixed on");
{
  const s = W.standing();
  const shelf = six.GROUPS.find((g) => g.SWITCH === "step6shelf");
  const off = await six.setGroup(s.env, shelf, { on: false, by: "check" });
  check("the shelf's switch can't be turned off any more (fixed on)", off.on === true && /fixed on/.test(off.problem || "") && (await six.groupOn(s.env, shelf)) === false, JSON.stringify(off));
  const on = await six.setGroup(s.env, shelf, { on: true, by: "check" });
  check("…and it can still be turned on", on.on === true && (await six.groupOn(s.env, shelf)) === true, JSON.stringify(on));
  const again = await six.setGroup(s.env, shelf, { on: false, by: "check" });
  check("…and stays on after another ask to turn it off", again.on === true && /fixed on/.test(again.problem || "") && (await six.groupOn(s.env, shelf)) === true, JSON.stringify(again));
}

console.log("released stills");
{
  const s = W.standing();
  const w = s.world();
  const stills = [...s.drive.items.values()].find((i) => i.name === "stills");
  for (const n of ["zz-10-showcase-stills.webp", "zz-2-showcase-stills.webp", "notes.txt"]) s.drive.add(stills.id, n, false);
  const matted = s.drive.add(stills.id, "matted", true);
  s.drive.add(matted, "zz-1-matted.webp", false);
  const got = await S.releasedStills(s.env, s.ids.P, { world: w });
  check("stills/ read in name order, numbers as numbers, only pictures, matted/ skipped", got.ok && got.total === 2
    && same(got.stills.map((x) => x.name), ["zz-2-showcase-stills.webp", "zz-10-showcase-stills.webp"]), JSON.stringify(got));
  const lq = s.drive.add(stills.id, "lq", true);
  s.drive.add(lq, "zz-1-showcase-stills.webp", false);
  const got2 = await S.releasedStills(s.env, s.ids.P, { world: w });
  check("a showcase split by quality is read from stills/lq/", got2.total === 1 && /stills\/lq$/.test(got2.folder), JSON.stringify(got2));
  // his call 2026-10-17: stills/hq/ is the default when there is one
  const hq = s.drive.add(stills.id, "hq", true);
  for (const n of ["zz-1-showcase-stills-hq.webp", "zz-3-showcase-stills-hq.webp"]) s.drive.add(hq, n, false);
  const got3 = await S.releasedStills(s.env, s.ids.P, { world: w });
  check("stills/hq/ is read first when there is one (beside lq/)", got3.total === 2 && /stills\/hq$/.test(got3.folder)
    && same(got3.stills.map((x) => x.name), ["zz-1-showcase-stills-hq.webp", "zz-3-showcase-stills-hq.webp"]), JSON.stringify(got3));
  s.drive.items.get(hq).name = "z-hq-set-aside";     // the checks below read the lq/ shape
  const none = await S.releasedStills(s.env, s.ids.R, { world: w });
  check("no showcase: an empty list, not a failure", none.ok && none.total === 0 && none.showcase === null, JSON.stringify(none));
  // a folder he chose himself (selects_folder) wins over the showcase
  const mine = s.drive.add(stills.id, "my-picks", true);
  for (const n of ["b-2.jpg", "b-10.jpg", "readme.md"]) s.drive.add(mine, n, false);
  const key = `r/${s.ids.P}/record.json`, obj = s.BUCKET.objects.get(key), rec = JSON.parse(obj.body);
  rec.facts = { ...(rec.facts || {}), selects_folder: { value: { id: mine, name: "my-picks", path: "/x/my-picks" }, v: 1 } };
  s.BUCKET.objects.set(key, { ...obj, body: JSON.stringify(rec) });
  const own = await S.releasedStills(s.env, s.ids.P, { world: w });
  check("a chosen folder's pictures, in name order, the showcase kept beside", own.ok && own.custom && own.custom.id === mine && own.total === 2
    && same(own.stills.map((x) => x.name), ["b-2.jpg", "b-10.jpg"]) && own.showcase && own.folder === "", JSON.stringify(own));
  const asked = await S.releasedStills(s.env, s.ids.P, { world: w, showcaseOnly: true });
  check("asked for the showcase only: the showcase, even with a folder chosen", asked.ok !== false && asked.custom === null && asked.total === 1, JSON.stringify(asked));
  rec.facts.selects_folder = { value: { id: "gone0000000000000000", name: "gone" }, v: 2 };
  s.BUCKET.objects.set(key, { ...obj, body: JSON.stringify(rec) });
  const gone = await S.releasedStills(s.env, s.ids.P, { world: w });
  check("a chosen folder the server can't read: the showcase, marked unread", gone.ok && gone.custom && gone.custom.unread && gone.total === 1, JSON.stringify(gone));
}

console.log("the released card");
{
  const r = OL.releasedOf({ released_date: { value: "2026-03-14", v: 1 }, selects: { value: ["a1b2c3d4e5f6g7h8i9", "z9"], v: 1 } });
  check("the card's still is the key still, else the first select", r.key_still === "a1b2c3d4e5f6g7h8i9" && r.selects === 2 && r.date === "2026-03-14");
  check("no Released facts: nothing laid on", OL.releasedOf({ title: { value: "x", v: 1 } }) === null);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
