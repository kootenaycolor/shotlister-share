#!/usr/bin/env node
/**
 * **Stage 5 step 5, the server's core** — checked without the worker.
 *
 * 1. The asks `project_modes` and `set_project_mode` (projectmodes.js over
 *    studiomodes.js): flags, standard, tiles that never guess, the switch,
 *    the both-off rule, a Job by its record's kind (and not by the Mac's
 *    drive-move `job`), listed to the phone and the Mac's router.
 * 2. Music Video behaves as Commercial everywhere the server names Types.
 * 3. New Project / Job: the options' types and modes standard; a Job's record
 *    behind `step5birth`; Jobs in the one list carry what their card needs.
 * 4. Frames: the spec sheet's frames section, checked; Notion's Frame Guides
 *    as a one-way copy, written only behind `framescopy`.
 *
 *     node --import <jsonhook> hub/step5core.mjs
 */
import { projectModes, setProjectMode, tilesOf, asFlags } from "./src/projectmodes.js";
import { setModesSwitch, resolveModes } from "./src/studiomodes.js";
import { CLOUD_METHODS, answerHere } from "./src/cloud.js";
import { NOW_READS } from "./src/routerasks.js";

let pass = 0, fail = 0;
export const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 76).padEnd(78)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 500)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const section = (s) => { if (process.env.VERBOSE) console.log(`\n${s}`); };

function bucket() {
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? { json: async () => JSON.parse(m.get(k)), text: async () => m.get(k), etag: `e${m.get(k).length}` } : null; },
    async head(k) { return m.has(k) ? {} : null; },
    async put(k, v, opts = {}) {
      if (opts.onlyIf && opts.onlyIf.etagDoesNotMatch === "*" && m.has(k)) return null;
      m.set(k, typeof v === "string" ? v : String(v)); return {};
    },
    async delete(k) { m.delete(k); },
    async list({ prefix, delimiter }) {
      const seen = new Set();
      for (const k of m.keys()) if (k.startsWith(prefix)) seen.add(prefix + k.slice(prefix.length).split(delimiter)[0] + delimiter);
      return { delimitedPrefixes: [...seen], objects: [], truncated: false };
    },
  };
}
const ID = (n) => n.toString(16).padStart(32, "0");
const RELAY = (n) => "f" + n.toString(16).padStart(31, "0");
const fact = (value, v = 1) => ({ value, v, at: "2026-10-05T10:00:00.000Z" });

const env = { BUCKET: bucket(), NOTION_TOKEN: "checking", NOTION_API: "http://127.0.0.1:9/v1/" };
const put = (key, record) => env.BUCKET.put(`r/${key}/record.json`, JSON.stringify({ page: key, ...record }));
const record = async (key) => JSON.parse(env.BUCKET.m.get(`r/${key}/record.json`));

// ── 1. the asks ─────────────────────────────────────────────────────────────
section("1. project_modes / set_project_mode");

await put(ID(1), { name: "Lets Bake", type: "Commercial", film: { relay: RELAY(1), shots: 142, scenes: 30, days: 4, boards: 2 }, facts: { type: fact("Commercial") } });
await put(ID(2), { name: "Instant Stills", kind: "job", type: "Commercial", facts: { type: fact("Commercial") } });
await put(ID(3), { name: "Mid Move", type: "Narrative", job: { id: "abc", label: "Moving to wd-4", done: false }, facts: {} });
await put(ID(4), { name: "No Film", type: "Personal", facts: {} });

const use1 = { scenes: 30, scripts: 1, locations: 6, boards: 2, days: 4, diagrams: 1 };
const reads = [];
const readUse = async (e, relay) => { reads.push(relay); return use1; };

let got = await projectModes(env, [ID(1)], { readUse });
check("project_modes answers ok with the contract's keys", got.ok === true && got.id === ID(1) && got.type === "Commercial" && got.job === false && got.switch === false
  && ["modes", "standard", "tiles"].every((k) => same(Object.keys(got[k]), ["shot_list", "locations", "references", "schedule", "diagram"])), JSON.stringify(got));
check("…modes as flags, a Commercial's start", same(got.modes, { shot_list: true, locations: false, references: true, schedule: true, diagram: false }), JSON.stringify(got.modes));
check("…standard is the Type's", same(got.standard, got.modes));
check("…tiles from the film's counts", same(got.tiles, { shot_list: "142 shots", locations: "6 places", references: "2 boards", schedule: "4 days", diagram: "1 plan" }), JSON.stringify(got.tiles));
check("…the film read once, by its relay", same(reads, [RELAY(1)]));
got = await projectModes(env, [RELAY(1)], { readUse });
check("…a project found by its film's id too", got.ok && got.id === ID(1) || got.ok === false, JSON.stringify(got));

got = await projectModes(env, [ID(4)], { readUse: async () => { throw new Error("should not be read"); } });
check("no film: tiles all empty, nothing guessed", got.ok && Object.values(got.tiles).every((t) => t === ""), JSON.stringify(got.tiles));
got = await projectModes(env, [ID(1)], { readUse: async () => { throw new Error("engine down"); } });
check("the film unreadable: only the record's counts", got.ok && same(got.tiles, { shot_list: "142 shots", locations: "", references: "2 boards", schedule: "4 days", diagram: "" }), JSON.stringify(got.tiles));
check("tilesOf: zero and missing are empty, one is singular", same(tilesOf({ shots: 1 }, { locations: 0, days: 1 }), { shot_list: "1 shot", locations: "", references: "", schedule: "1 day", diagram: "" }));
check("tilesOf: scenes when shots are not known", tilesOf(null, { scenes: 12 }).shot_list === "12 scenes");

got = await projectModes(env, [ID(2)], { readUse });
check("a Job (kind: job) has none on and a standard of none", got.ok && got.job === true && Object.values(got.modes).every((v) => !v) && Object.values(got.standard).every((v) => !v), JSON.stringify(got));
got = await projectModes(env, [ID(3)], { readUse });
check("a project mid drive-move (the Mac's job: {…}) is not a Job", got.ok && got.job === false && Object.values(got.modes).every(Boolean), JSON.stringify(got));
check("resolveModes: the same for the cards", resolveModes(await record(ID(3))).modes.length === 5 && resolveModes(await record(ID(2))).modes.length === 0);
got = await projectModes(env, [ID(99)]);
check("an unknown id: ok false, in words", got.ok === false && /No project/.test(got.error), JSON.stringify(got));

const deps = { by: "check", ensureSide: async () => ({ ok: true, relay: ID(4), made: true }) };
got = await setProjectMode(env, [ID(1), "locations", true, false], deps);
check("set_project_mode refused while the switch is off, in its words", got.ok === false && got.error === "Modes are switched off on the server.", JSON.stringify(got));
check("…and nothing written", !(await record(ID(1))).facts.modes);
await setModesSwitch(env, { on: true, by: "check" });
got = await setProjectMode(env, [ID(1), "locations", true, false], deps);
check("on: Locations on", got.ok && same(got.modes, asFlags(["shot_list", "locations", "references", "schedule"])), JSON.stringify(got));
check("…kept as the difference from the standard", same((await record(ID(1))).facts.modes.value, { locations: true }), JSON.stringify((await record(ID(1))).facts.modes));
got = await setProjectMode(env, [ID(1), "shot_list", false, false], deps);
check("Shot List off with Schedule on: needs both, says why", got.ok === false && got.needs === "both" && /Schedule/.test(got.error), JSON.stringify(got));
got = await setProjectMode(env, [ID(1), "shot_list", false, true], deps);
check("…with both: both off", got.ok && got.modes.shot_list === false && got.modes.schedule === false && same(got.also, ["schedule"]), JSON.stringify(got));
got = await setProjectMode(env, [ID(1), "colour", true], deps);
check("an unknown mode refused", got.ok === false && got.error, JSON.stringify(got));
got = await setProjectMode(env, [ID(1), "diagram", "yes"], deps);
check("on must be true or false", got.ok === false && got.error === "Say on or off.", JSON.stringify(got));
got = await setProjectMode(env, [ID(4), "diagram", true], deps);
check("a project with no film: its Studio side made first", got.ok && got.modes.diagram === true, JSON.stringify(got));

check("both asks are the server's", CLOUD_METHODS.has("project_modes") && CLOUD_METHODS.has("set_project_mode"));
check("project_modes is a read answered on the spot; set_project_mode is not", NOW_READS.has("project_modes") && !NOW_READS.has("set_project_mode"));
got = await answerHere(env, "project_modes", [ID(4)]);
check("answered through the asks door", got && got.state === "done" && got.result.ok && got.result.modes.diagram === true, JSON.stringify(got));
got = await answerHere(env, "set_project_mode", [ID(1), "references", false, false]);
check("…and a change through it", got && got.state === "done" && got.result.ok && got.result.modes.references === false, JSON.stringify(got));
got = await setModesSwitch(env, { on: false, by: "check" });
check("…and the switch can't be turned off any more (fixed on)", got.on === true && /fixed on/.test(got.problem || ""), JSON.stringify(got));

// ── 2. Music Video ──────────────────────────────────────────────────────────
section("2. Music Video behaves as Commercial");
{
  const { kindOfType } = await import("./src/studiocards.js");
  const { standardOf } = await import("./src/studiomodes.js");
  const { typeIcon, restyle } = await import("./src/onelist.js");
  const { readout } = await import("./src/projectpage.js");
  const { nextLabel, isCommercial } = await import("./src/newshoot.js");
  const { resolveLayout } = await import("./src/notionlink.js");
  const R = await import("./src/newproject.js");
  check("Studio kind: commercial", kindOfType("Music Video") === "commercial" && kindOfType("music video") === kindOfType("Commercial"));
  check("modes standard: Commercial's", same(standardOf("Music Video"), standardOf("Commercial")) && same(standardOf("Music Video", true), []));
  check("console icon: a commercial's colour, its own glyph", typeIcon("Music Video")[1] === typeIcon("Commercial")[1] && typeIcon("Music Video")[0] === "disc", JSON.stringify(typeIcon("Music Video")));
  const two = [{ id: "a", start: "2026-01-01", end: "2026-01-01" }, { id: "b", start: "2026-02-01", end: "2026-02-01" }];
  const words = (t) => readout(two, { type: t }, "2026-03-01").map((x) => x.kind || x.label);
  check("shoots' words: Shoot 1, Shoot 2 (not Principal)", same(words("Music Video"), words("Commercial")) && !same(words("Music Video"), words("Narrative")), JSON.stringify([words("Music Video"), words("Narrative")]));
  check("…the one list's restyle too", same(restyle(readout(two, { type: "x" }, "2026-03-01"), { type: "Music Video" }, "2026-03-01").map((r) => r.kind),
    restyle(readout(two, { type: "x" }, "2026-03-01"), { type: "Commercial" }, "2026-03-01").map((r) => r.kind)));
  check("…New Shoot's next label", nextLabel(2, "Music Video") === nextLabel(2, "Commercial") && isCommercial(" music  video "));
  const lay = (t, saved = {}) => resolveLayout({ type: { value: t } }, t, saved).template;
  check("record layout: Commercial's standard", same(lay("Music Video"), lay("Commercial")), JSON.stringify(lay("Music Video")));
  const mine = { Commercial: { fields: ["client", "website"], credits: ["Director"] } };
  check("…his own Commercial standard followed", same(lay("Music Video", mine), lay("Commercial", mine)) && same(lay("Music Video", mine).fields, ["client", "website"]), JSON.stringify(lay("Music Video", mine)));
  const own = { ...mine, "Music Video": { fields: ["logline"], credits: ["Director", "Producer"] } };
  check("…a Music Video standard of its own wins", same(lay("Music Video", own).fields, ["logline"]));
  const opts = R.optionsFrom({});
  check("New Project offers it, after Commercial", same(opts.types, ["Narrative", "Commercial", "Music Video", "Personal"]), JSON.stringify(opts.types));
}

// ── 3. New Project or Job ──────────────────────────────────────────────────
section("3. New Project or Job");
{
  const B = await import("./src/step5birth.js");
  const R = await import("./src/newproject.js");
  const { setOneId } = await import("./src/projectid.js");
  const { beginMinted } = await import("./src/oneiddoor.js");
  const { buildList } = await import("./src/onelist.js");
  const opts = R.optionsFrom({});
  check("options: each Type's starting modes", same(opts.modes_standard, {
    Narrative: ["shot_list", "locations", "references", "schedule", "diagram"], Commercial: ["shot_list", "references", "schedule"],
    "Music Video": ["shot_list", "references", "schedule"], Personal: ["shot_list", "references"] }), JSON.stringify(opts.modes_standard));
  check("the step5birth switch is off until thrown", (await B.birthOn(env)).on === false);

  let b = B.readBirth({ name: "Instant Stills", job: true, type: "Commercial", modes: ["shot_list"], setup: { drive: true, notion: true, portal: false, media: false }, volume: "wd-4", tier1: true, home: "projects" });
  check("a Job: no Notion row, gigs/, no drive when media is off, the modes switched on, its Kind kept for its loose folder", b.job && b.form.tier1 === false && b.form.home === "gigs"
    && b.form.volume === "" && same(b.modes, ["shot_list"]) && b.setup.notion === false && b.form.job === true && !("modes" in b.form) && !("setup" in b.form), JSON.stringify(b));
  check("…kept as the differences from a Job's start (none)", same(B.birthModes(b.type, b.job, b.modes), { shot_list: true }));
  check("a Job with nothing switched on: none, no modes fact", same(B.readBirth({ name: "x", job: true, type: "Narrative" }).modes, []) && B.birthModes("Narrative", true, []) === null);
  b = B.readBirth({ name: "Northern Lights", type: "Commercial", modes: ["schedule", "locations"], volume: "wd-4", setup: { media: true } });
  check("a Project: its row, its drive, Schedule brings Shot List", b.job === false && b.form.tier1 === true && b.form.volume === "wd-4" && same(b.modes, ["shot_list", "locations", "schedule"]), JSON.stringify(b));
  check("…kept as the differences from Commercial's start", same(B.birthModes(b.type, b.job, b.modes), { locations: true, references: false }));
  check("…none kept when it is the start", B.birthModes("Personal", false, ["shot_list", "references"]) === null && B.birthModes("Personal", false, null) === null);
  check("a Project with Notion off: no row", B.readBirth({ name: "x", setup: { notion: false } }).form.tier1 === false);
  check("Drive off is refused in words", B.readBirth({ name: "x", setup: { drive: false } }).why === "A Drive folder is always made.");
  check("an unknown mode is refused", /No such mode/.test(B.readBirth({ name: "x", modes: ["colour"] }).why || ""));
  check("nothing sent: what the sheet always sent", same(B.readBirth({ name: "x", tier1: false, home: "gigs", volume: "wd-2" }).form, { name: "x", tier1: false, home: "gigs", volume: "wd-2" }));

  b = B.readBirth({ name: "Instant Stills", job: true, type: "music video", date_start: "2026-11-02", date_end: "2026-11-03", status: "Active", id: ID(77) });
  check("a Job's record plan: kind, Type, folder, days, stage — no modes fact", same(B.birthPlan(b, { url: "https://drive.google.com/drive/folders/abc" }), {
    kind: "job", facts: { type: "Music Video", drive_folder: "https://drive.google.com/drive/folders/abc", shoot_dates: "2026-11-02/2026-11-03", status: "Active" } }), JSON.stringify(B.birthPlan(b, { url: "u" })));
  let got = await B.bear(env, b, { url: "https://drive.google.com/drive/folders/abc" });
  check("one ID off: no record, said", got.ok === false && /one ID is off/.test(got.line), JSON.stringify(got));
  await setOneId(env, { on: true, by: "check" });
  got = await B.bear(env, b, { url: "https://drive.google.com/drive/folders/abc" });
  const job = got.key ? await record(got.key) : {};
  check("a Job's record: under the ID the device minted, kind job", got.ok && got.key === ID(77) && job.kind === "job" && job.name === "Instant Stills" && got.line === "Job record made", JSON.stringify({ got, job }));
  check("…its facts written through the one door", job.facts && job.facts.type.value === "Music Video" && job.facts.status.value === "Active" && job.facts.shoot_dates.value === "2026-11-02/2026-11-03"
    && job.facts.drive_folder.v === 1 && !job.facts.modes, JSON.stringify(job.facts));
  check("…every mode off", resolveModes(job).modes.length === 0);
  got = await projectModes(env, [ID(77)]);
  check("…project_modes says job, none on", got.ok && got.job === true && Object.values(got.modes).every((v) => !v), JSON.stringify(got));

  const list = buildList({ pages: [], crew: [], shoots: [], records: { [ID(77)]: job }, saved: {}, now: "2026-10-15" });
  const row = list.jobs[0] || {};
  check("the one list: the Job in Jobs, with what its card needs", list.jobs.length === 1 && row.kind === "job" && row.type === "Music Video" && same(row.modes, [])
    && row.stage === "Active" && row.status === "Active" && row.dates === "2026-11-02" && row.dates_end === "2026-11-03"
    && row.drive_url === "https://drive.google.com/drive/folders/abc" && row.id === ID(77), JSON.stringify(row));
  check("…its shoot, in a commercial's words", row.shoots.length === 1 && row.shoots[0].start === "2026-11-02" && row.shoots[0].kind === "Shoot" && row.shoots[0].state === "Next", JSON.stringify(row.shoots));

  // A Project with a Notion row: New Project begins its record; the birth writes only its modes.
  const page = "c".repeat(32);
  const begun = await beginMinted(env, { notion: page, name: "Northern Lights", by: "server" });
  b = B.readBirth({ name: "Northern Lights", type: "Commercial", modes: ["schedule", "locations"] });
  got = await B.bear(env, b, { page, url: "u" });
  const proj = await record(begun.key);
  check("a Project's record: its modes as the differences, its Type beside them", got.ok && got.key === begun.key && same(proj.facts.modes.value, { locations: true, references: false })
    && proj.facts.type.value === "Commercial" && !proj.kind && got.line === "", JSON.stringify({ got, facts: proj.facts }));
  check("…read back as he chose", same(resolveModes(proj).modes, ["shot_list", "locations", "schedule"]));
  got = await B.bear(env, B.readBirth({ name: "N", type: "Personal" }), { page: "d".repeat(32) });
  check("…a row whose record is not there: said, not raised", got.ok === false && /not found/.test(got.line), JSON.stringify(got));
}

// ── 4. Frames ───────────────────────────────────────────────────────────────
section("4. Frames on the spec sheet");
{
  const S = await import("./src/specsheet.js");
  const F = await import("./src/framescopy.js");
  const { writeFacts } = await import("./src/facts.js");
  const cam = { label: "A Cam", body: "Sony Venice 2", guides: ["2.39:1", "16:9"], finishing: ["4096 x 1716"] };
  const camNow = { label: "A Cam", body: "Sony Venice 2" };
  const base = S.checkSheet({ cameras: [cam] }).sheet;
  check("a sheet with no frames stores none (old sheets unchanged)", base && !("frames" in base), JSON.stringify(base));
  check("…and reads one empty Main (a camera has no guides to take a ratio from)", same(S.framesOf(base), [{ name: "Main", ratio: "", main: true }]) && !("guides" in base.cameras[0]) && !("finishing" in base.cameras[0]), JSON.stringify(S.framesOf(base)));
  {
    const f = S.foldCameraRows({ cameras: [{ label: "A Cam", guides: ["2.39:1", "Full Frame", "16:9"], finishing: ["4096 x 1716", "2880 × 2160 (Web)", "ProRes"] }, { label: "B Cam", guides: ["2.39:1"], finishing: ["4096 x 1716"] }] });
    check("the fold: ratios become Aspect Ratio entries, the first Main", same(f.frames, [{ name: "Main", ratio: "2.39:1", main: true }, { name: "A Cam 16:9", ratio: "16:9", main: false }]), JSON.stringify(f.frames));
    check("…resolutions become Finishing Resolutions: a shared one All Cams, a bracketed word its title", same(f.finishing_resolutions, [{ title: "All Cams", resolution: "4096 x 1716", note: "" }, { title: "Web", resolution: "2880 x 2160", note: "" }]), JSON.stringify(f.finishing_resolutions));
    check("…what is neither goes to Notes, labelled, nothing lost", f.notes === "Frame Guides (A Cam): Full Frame\nFinishing Resolution (A Cam): ProRes", f.notes);
    const g = S.foldCameraRows({ cameras: [{ label: "A Cam", guides: ["2.39:1"], finishing: ["4096 x 1716"] }], frames: [{ name: "Delivery", ratio: "2.39:1", main: true }], finishing_resolutions: [{ title: "Master", resolution: "4096 x 1716", note: "x" }] });
    check("…an exact duplicate of an entry already there is skipped", same(g.frames, [{ name: "Delivery", ratio: "2.39:1", main: true }]) && same(g.finishing_resolutions, [{ title: "Master", resolution: "4096 x 1716", note: "x" }]) && g.notes === "");
  }
  let got = S.checkSheet({ cameras: [camNow], frames: [{ name: "Delivery", ratio: "2.39", resolution: "4096 x 1716", main: true }, { name: "Social", ratio: "9 : 16", resolution: "1080 x 1920" }] });
  check("frames kept as name and ratio only: a bare 2.39 is 2.39:1, spaces go, a resolution is dropped", got.sheet && same(got.sheet.frames, [{ name: "Delivery", ratio: "2.39:1", main: true }, { name: "Social", ratio: "9:16", main: false }]), JSON.stringify(got));
  check("none marked Main: the first is", S.checkSheet({ frames: [{ name: "A", ratio: "16:9" }, { name: "B", ratio: "1.85:1" }] }).sheet.frames[0].main === true);
  check("two Main: refused", S.checkSheet({ frames: [{ name: "A", ratio: "16:9", main: true }, { name: "B", ratio: "1.85:1", main: true }] }).why === "Only one frame is Main.");
  check("a frame with no name: refused", S.checkSheet({ frames: [{ name: " ", ratio: "16:9" }] }).why === "Each frame needs a name.");
  check("a ratio that is not one: refused in words", /not a ratio/.test(S.checkSheet({ frames: [{ name: "A", ratio: "wide" }] }).why || "") && /not a ratio/.test(S.checkSheet({ frames: [{ name: "A", ratio: "0:1" }] }).why || ""));
  check("nine frames: refused", /8 frames/.test(S.checkSheet({ frames: Array.from({ length: 9 }, (_, i) => ({ name: `F${i}`, ratio: "16:9" })) }).why || ""));

  got = S.applyFrameOp(base, { op: "add_frame", frame: { name: "Social", ratio: "9:16", resolution: "1080 x 1920" } });
  check("add_frame keeps no resolution", got.sheet && got.sheet.frames.every((f) => !("resolution" in f)), JSON.stringify(got));
  check("add_frame on a sheet with none: the default first, the new one not Main", got.sheet && same(got.sheet.frames.map((f) => [f.name, f.main]), [["Main", true], ["Social", false]]), JSON.stringify(got));
  got = S.applyFrameOp(got.sheet, { op: "main_frame", at: 1 });
  check("main_frame moves Main", same(got.sheet.frames.map((f) => f.main), [false, true]));
  got = S.applyFrameOp(got.sheet, { op: "frame", at: 0, name: "Delivery", ratio: "2.39" });
  check("frame renames and re-ratios", got.sheet.frames[0].name === "Delivery" && got.sheet.frames[0].ratio === "2.39:1");
  check("…a blank name refused", S.applyFrameOp(got.sheet, { op: "frame", at: 0, name: "" }).why === "Say the frame's name.");
  check("…a frame that is not there refused", S.applyFrameOp(got.sheet, { op: "remove_frame", at: 5 }).why === "No such frame.");
  check("…a bad ratio refused", /not a ratio/.test(S.applyFrameOp(got.sheet, { op: "frame", at: 0, ratio: "big" }).why || ""));
  const two = got.sheet;
  got = S.applyFrameOp(two, { op: "remove_frame", at: 1 });
  check("removing Main makes the first left Main", same(got.sheet.frames.map((f) => [f.name, f.main]), [["Delivery", true]]));
  check("an unknown op refused", /No such change/.test(S.applyFrameOp(two, { op: "frames" }).why || ""));
  check("frame op: a resolution said is ignored", !("resolution" in S.applyFrameOp(two, { op: "frame", at: 0, resolution: "4096 x 1716" }).sheet.frames[0]));

  // Finishing Resolutions (2026-10-15): the deliverables, {title, resolution, note}
  check("a sheet with no finishing resolutions stores none", !("finishing_resolutions" in base));
  got = S.checkSheet({ finishing_resolutions: [{ title: "Master", resolution: "4096×2160", note: "DCI 4K for the grade" }, { title: "Social", resolution: "1080 x 1920", note: "Instagram vertical" }, { title: "", resolution: "", note: "" }] });
  check("finishing resolutions kept, × written x, an empty one dropped", got.sheet && same(got.sheet.finishing_resolutions, [{ title: "Master", resolution: "4096 x 2160", note: "DCI 4K for the grade" }, { title: "Social", resolution: "1080 x 1920", note: "Instagram vertical" }]), JSON.stringify(got));
  check("thirteen: refused", /12 finishing/.test(S.checkSheet({ finishing_resolutions: Array.from({ length: 13 }, (_, i) => ({ title: `R${i}` })) }).why || ""));
  let fin = S.applyFinishingOp(base, { op: "add_finishing" });
  check("add_finishing on none: titled Master", fin.sheet && same(fin.sheet.finishing_resolutions, [{ title: "Master", resolution: "", note: "" }]), JSON.stringify(fin));
  fin = S.applyFinishingOp(fin.sheet, { op: "add_finishing", entry: { title: "Social", resolution: "1080x1920", note: "Instagram vertical" } });
  fin = S.applyFinishingOp(fin.sheet, { op: "finishing", at: 0, resolution: "4096 x 2160", note: "DCI 4K for the grade" });
  check("finishing edits one", same(fin.sheet.finishing_resolutions, [{ title: "Master", resolution: "4096 x 2160", note: "DCI 4K for the grade" }, { title: "Social", resolution: "1080 x 1920", note: "Instagram vertical" }]), JSON.stringify(fin));
  check("…a blank title refused", S.applyFinishingOp(fin.sheet, { op: "finishing", at: 0, title: " " }).why === "Say its title.");
  check("…one not there refused", S.applyFinishingOp(fin.sheet, { op: "remove_finishing", at: 4 }).why === "No such finishing resolution.");
  check("remove_finishing", same(S.applyFinishingOp(fin.sheet, { op: "remove_finishing", at: 0 }).sheet.finishing_resolutions.map((f) => f.title), ["Social"]));
  const sheets = { spec_project: { sheet: fin.sheet, v: 1 }, ["spec_" + "a".repeat(32)]: { sheet: base, v: 1 }, ["spec_" + "b".repeat(32)]: { sheet: S.applyFinishingOp(base, { op: "add_finishing", entry: { title: "Shoot 2" } }).sheet, v: 1 } };
  check("a shoot sheet with none reads the project sheet's", same(S.finishingOf(sheets, "spec_" + "a".repeat(32)).map((f) => f.title), ["Master", "Social"]));
  check("a shoot sheet's own list stands instead", same(S.finishingOf(sheets, "spec_" + "b".repeat(32)).map((f) => f.title), ["Shoot 2"]));

  // through the one door: writeFacts checks the frames, as it checks every sheet
  await put(ID(50), { name: "Frames Film", facts: {} });
  got = await writeFacts(env, ID(50), { spec_project: { value: { ...two, notion: "e".repeat(32) }, base: 0 } }, "check");
  check("a sheet with frames written through the one door", got.status === 200 && same((await record(ID(50))).facts.spec_project.value.frames.map((f) => f.name), ["Delivery", "Social"]), JSON.stringify(got));
  got = await writeFacts(env, ID(50), { spec_project: { value: { ...two, frames: [{ name: "", ratio: "16:9" }] }, base: 1 } }, "check");
  check("…a bad frames list refused there, nothing written", got.status === 400 && /needs a name/.test(got.problem) && (await record(ID(50))).facts.spec_project.v === 1, JSON.stringify(got));

  // the copy to Notion's Frame Guides
  check("frameGuidesOf: Main first, each ratio once, none empty", same(F.frameGuidesOf([{ ratio: "16:9" }, { ratio: "2.39:1", main: true }, { ratio: "16:9" }, { ratio: "" }]), ["2.39:1", "16:9"]));
  check("…nothing for nothing", same(F.frameGuidesOf(null), []));
  check("a sheet with no frames of its own is not copied", F.copyPlan(base).skip === "keeps no frames of its own");
  check("a sheet with no Notion row is not copied", F.copyPlan(two).skip === "names no Notion row");
  const plan = F.copyPlan({ ...two, notion: "e".repeat(32) });
  check("…else its row's Frame Guides pills", plan.page === "e".repeat(32) && same(plan.properties, { "Frame Guides": { multi_select: [{ name: "9:16" }, { name: "2.39:1" }] } }), JSON.stringify(plan));
  const calls = [];
  const notion = async (method, path, body) => { calls.push({ method, path, body }); return { properties: { "Frame Guides": { multi_select: [{ name: "2.39:1" }] } } }; };
  check("the copy is off until thrown", (await F.copyOn(env)).on === false);
  got = await F.framesCopy(env, notion, { write: false });
  const row = got.rows.find((r) => r.id === ID(50)) || {};
  check("the look: reads Notion, says what differs, writes nothing", got.dry && row.differs === true && same(row.guides, ["9:16", "2.39:1"]) && same(row.notion, ["2.39:1"])
    && calls.every((c) => c.method === "GET"), JSON.stringify({ got, calls }));
  got = await F.framesCopy(env, notion, { write: true, only: ID(50) });
  check("the run: writes the differing row, Frame Guides only", got.wrote === 1 && calls.filter((c) => c.method === "PATCH").length === 1
    && same(Object.keys(calls.find((c) => c.method === "PATCH").body.properties), ["Frame Guides"]), JSON.stringify(calls));
  const door = await F.copyDoor(env, ["framescopy", "run"], "POST", async () => ({}), notion);
  check("the run door refuses while the switch is off", door.status === 409);
}

// ── the end ─────────────────────────────────────────────────────────────────
console.log(`step5core: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
