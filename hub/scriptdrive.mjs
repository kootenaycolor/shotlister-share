#!/usr/bin/env node
/**
 * **One script, from Drive** — `src/scriptdrive.js` (stage 5 step 4, piece C).
 *
 *  1. The label every app shows (`scriptlabel-cases.json`, also held by Swift and Python).
 *  2. Which files are drafts; which is the one in use; same / new / older.
 *  3. The template gains `1-creative/script/`, `archive/` and `current-draft/` (and the kept copy, once).
 *  4. The switch: off by default; off, every door but the look refuses and cards carry no script.
 *  5. One project looked at: every status, outputs never taken for a draft, Shot List off.
 *  6. A check keeps what it saw; the card says "new draft" from it.
 *  7. Confirming a draft from Drive: the rest of current-draft/ moves to archive/, nothing else
 *     moves; more than one draft there and he picks; loose files in script/ are never read or moved.
 *  8. Studio's Import filed into Drive: sent once, folders made where missing.
 *  9. A draft's PDF handed out only from the project's own script folder.
 * 10. The dry look writes nothing; `wide` lists every script-looking file.
 * 11. The clock: every ten minutes, while on.
 * 12. The doors.
 *
 *     node hub/scriptdrive.mjs
 */
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import {
  isOutput, isDraftFile, sortDrafts, compare, fileLabel, draftsOf, cardScript,
  scriptDriveOn, setScriptDrive, lookAt, checkOne, settle, fileIn, fileOut, scriptLook, onScriptTimer,
  addScriptFolders, scriptDoor, readState, scriptFilesIn, STATE_KEY,
} from "./src/scriptdrive.js";
import { draftLabel } from "./src/scriptlabel.js";
import { PROJECT_TEMPLATE, withScriptFolders, SCRIPT_FOLDERS } from "./src/drivefolders.js";
import { templateOf } from "./src/foldertemplate.js";
import { allCards } from "./src/studiocards.js";
import { setModesSwitch } from "./src/studiomodes.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 70).padEnd(72)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const md5 = (bytes) => createHash("md5").update(bytes).digest("hex");

function bucket() {
  const m = new Map();
  let n = 0;
  const tags = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? { json: async () => JSON.parse(m.get(k)), text: async () => m.get(k), etag: tags.get(k) } : null; },
    async head(k) { return m.has(k) ? { etag: tags.get(k), checksums: k.endsWith(".pdf") ? { md5: md5(m.get(k)) } : {} } : null; },
    async put(k, v, o = {}) {
      const want = o.onlyIf || {};
      if (want.etagMatches && tags.get(k) !== want.etagMatches) return null;
      if (want.etagDoesNotMatch === "*" && m.has(k)) return null;
      m.set(k, typeof v === "string" ? v : String(v));
      tags.set(k, `t${++n}`);
      return {};
    },
    async delete(k) { m.delete(k); },
    async list({ prefix, delimiter }) {
      const seen = new Set();
      for (const k of m.keys()) if (k.startsWith(prefix)) seen.add(prefix + k.slice(prefix.length).split(delimiter)[0] + delimiter);
      return { delimitedPrefixes: [...seen], truncated: false };
    },
  };
}

/** A Drive held in memory: folders and files with md5s, times and bytes; every write counted. */
function drive() {
  const items = new Map();
  let n = 0;
  const writes = [];
  const add = (parent, name, { folder = false, bytes = "", modified = "2026-10-01T00:00:00Z", mime } = {}) => {
    const id = `drv${String(++n).padStart(10, "0")}`;
    items.set(id, { id, name, folder, mime: mime || (folder ? "application/vnd.google-apps.folder" : name.endsWith(".pdf") ? "application/pdf" : "text/plain"),
      parents: parent ? [parent] : [], md5: folder ? "" : md5(bytes), modified, created: modified, size: bytes.length, bytes });
    return id;
  };
  const shape = (f) => ({ id: f.id, name: f.name, folder: f.folder, mime: f.mime, parents: [...f.parents], md5: f.md5, modified: f.modified, created: f.created, size: f.size });
  const api = {
    secret: "GDRIVE_WRITE", writes, items,
    async list(parent) { return [...items.values()].filter((f) => f.parents.includes(parent)).map(shape); },
    async get(id) { const f = items.get(id); return f ? shape(f) : null; },
    async download(id) { return new Response(items.get(id).bytes, { headers: { "content-type": "application/pdf" } }); },
    async mkdir(parent, name) { writes.push(["mkdir", name]); return shape(items.get(add(parent, name, { folder: true }))); },
    async upload(parent, name, bytes) {
      writes.push(["upload", name]);
      return shape(items.get(add(parent, name, { bytes: Buffer.from(bytes).toString("latin1"), modified: "2026-10-14T20:00:00Z" })));
    },
    async archive(file, from, to) {
      const f = items.get(file);
      if (!f.parents.includes(from) || items.get(from).name !== "current-draft") throw new Error("not in current-draft/");
      if (items.get(to).name !== "z-archive" || items.get(to).parents[0] !== items.get(from).parents[0]) throw new Error("archive is not current-draft's sibling");
      writes.push(["archive", f.name]);
      f.parents = [to];
      return shape(f);
    },
  };
  return { api, add, items, writes };
}
const readOnly = (d) => ({ secret: "GDRIVE", list: d.api.list, get: d.api.get, download: d.api.download });

const ID = (n) => n.toString(16).padStart(32, "0");
const RELAY = (n) => "f" + n.toString(16).padStart(31, "0");
const STEM = (n) => "a" + n.toString(16).padStart(31, "0");
const fact = (value, v = 1) => ({ value, v, at: "2026-10-05T10:00:00.000Z" });
const marks = { of: async () => ({}), save: async () => {} };

// ── 1. the label ──────────────────────────────────────────────────────────────
console.log("the label");
const CASES = JSON.parse(readFileSync(new URL("./scriptlabel-cases.json", import.meta.url), "utf8")).cases;
for (const c of CASES) check(`label: ${c.label}`, draftLabel(c) === c.label, draftLabel(c));
check("a Drive file's label: its name, the day it changed", fileLabel({ name: "Halcyon Pink.pdf", modified: "2026-10-12T18:00:00Z" }) === "Halcyon Pink · Oct 12, 2026");

// ── 2. the rules ──────────────────────────────────────────────────────────────
console.log("the rules");
check("lined and compressed copies are outputs", isOutput("Halcyon Pink LINED.pdf") && isOutput("halcyon_compressed.pdf") && isOutput("lined-script.pdf") && isOutput("Quiet Harbor - Line Script (08.12.25).pdf") && !isOutput("Outlined Draft.pdf") && !isOutput("Halcyon Pink.pdf"));
check("a draft is a PDF that is not an output", isDraftFile({ name: "a.pdf" }) && isDraftFile({ name: "a", mime: "application/pdf" }) && !isDraftFile({ name: "a.docx" }) && !isDraftFile({ name: "a.pdf", folder: true }) && !isDraftFile({ name: "a lined.pdf" }));
const sorted = sortDrafts([{ name: "old.pdf", modified: "2026-09-01T00:00:00Z" }, { name: "new.pdf", modified: "2026-10-01T00:00:00Z" }, { name: "x lined.pdf", modified: "2026-11-01T00:00:00Z" }]);
check("the draft in use is the newest change; outputs left out", same(sorted.map((f) => f.name), ["new.pdf", "old.pdf"]));
const use = { stem: STEM(1), name: "Blue", came_from: "Halcyon Blue.pdf", dated: "2026-09-28T00:00:00Z", md5: "m1" };
check("same bytes: same, whatever the name or time", compare({ name: "renamed.pdf", md5: "m1", modified: "2026-10-20T00:00:00Z" }, use) === "same");
check("different bytes, changed after: new", compare({ name: "Halcyon Pink.pdf", md5: "m2", modified: "2026-10-12T00:00:00Z" }, use) === "new");
check("different bytes, older than the draft in use: older, never offered", compare({ name: "Halcyon White.pdf", md5: "m0", modified: "2026-09-01T00:00:00Z" }, use) === "older");
check("no bytes to compare: the same name is the same draft", compare({ name: "halcyon blue.PDF", md5: "m9", modified: "2026-10-12T00:00:00Z" }, { ...use, md5: "" }) === "same");
check("…another name, newer: new", compare({ name: "Pink.pdf", md5: "m9", modified: "2026-10-12T00:00:00Z" }, { ...use, md5: "" }) === "new");
check("no draft in the film yet: new", compare({ name: "a.pdf", md5: "x" }, null) === "new");
check("nothing in the folder: none", compare(null, use) === "none");
check("the film's drafts: newest first, one per file, only real stems", same(draftsOf([{ stem: STEM(2), name: "b" }, { stem: STEM(2), name: "b again" }, { stem: "nope", name: "c" }, { stem: STEM(1), name: "a" }]).map((d) => d.name), ["b", "a"]));

// ── 3. the template ───────────────────────────────────────────────────────────
console.log("the template");
check("the server's template has the script's folders", SCRIPT_FOLDERS.every((p) => PROJECT_TEMPLATE.includes(p)));
check("…after reference, before shot-list", PROJECT_TEMPLATE.indexOf("1-creative/reference") < PROJECT_TEMPLATE.indexOf("1-creative/script")
  && PROJECT_TEMPLATE.indexOf("1-creative/script/z-archive") === PROJECT_TEMPLATE.indexOf("1-creative/script") + 1
  && PROJECT_TEMPLATE.indexOf("1-creative/script/current-draft") === PROJECT_TEMPLATE.indexOf("1-creative/script") + 2
  && PROJECT_TEMPLATE.indexOf("1-creative/script/current-draft") < PROJECT_TEMPLATE.indexOf("1-creative/shot-list"));
const profile = PROJECT_TEMPLATE.filter((p) => !SCRIPT_FOLDERS.includes(p));
check("withScriptFolders: the profile gains them in place", same(withScriptFolders(profile), PROJECT_TEMPLATE));
check("withScriptFolders: already there, unchanged", same(withScriptFolders(PROJECT_TEMPLATE), PROJECT_TEMPLATE));
check("withScriptFolders: script there without archive, archive and current-draft added under it", same(withScriptFolders(["1-creative", "1-creative/script", "1-creative/script/old", "2-logistics"]), ["1-creative", "1-creative/script", "1-creative/script/old", "1-creative/script/z-archive", "1-creative/script/current-draft", "2-logistics"]));
check("withScriptFolders: a kept template from before current-draft gains it alone", same(withScriptFolders(["1-creative", "1-creative/script", "1-creative/script/z-archive", "2-x"]), ["1-creative", "1-creative/script", "1-creative/script/z-archive", "1-creative/script/current-draft", "2-x"]));
check("withScriptFolders: no 1-creative, nothing added", same(withScriptFolders(["a", "b"]), ["a", "b"]));
check("withScriptFolders: an empty 1-creative", same(withScriptFolders(["1-creative", "2-x"]), ["1-creative", ...SCRIPT_FOLDERS, "2-x"]));
{
  const env = { BUCKET: bucket() };
  let got = await addScriptFolders(env, { dry: true });
  check("nothing kept yet: today's template already has them", got.ok && got.already === true && got.v === 0, JSON.stringify(got));
  await env.BUCKET.put("s/folder-template.json", JSON.stringify({ drive: profile, media: ["A"], v: 3, at: "x", by: "him" }));
  got = await addScriptFolders(env, { dry: true });
  check("a kept template without them: the dry ask says what it would add", got.ok && got.dry && same(got.adds, SCRIPT_FOLDERS) && (await templateOf(env)).v === 3, JSON.stringify(got));
  got = await addScriptFolders(env, { dry: false, by: "check" });
  const t = await templateOf(env);
  check("…and run, kept as the next version, media untouched", got.ok && got.v === 4 && same(t.drive, PROJECT_TEMPLATE) && same(t.media, ["A"]), JSON.stringify(t));
  got = await addScriptFolders(env, { dry: false });
  check("…once only", got.already === true && (await templateOf(env)).v === 4);
}

// ── a world: three projects, their films, their Drive ─────────────────────────
function world() {
  const env = { BUCKET: bucket() };
  const d = drive();
  const roots = {};
  const film = new Map();       // relay -> drafts
  const ids = { notion: {}, alias: {} };
  const put = (key, record) => env.BUCKET.put(`r/${key}/record.json`, JSON.stringify({ page: key, ...record }));
  const project = (n, { name, type = "Narrative", folder = true, script = true, archive = true, current = true, files = [], loose = [], drafts = [], facts = {} } = {}) => {
    let root = "";
    if (folder) {
      root = d.add(null, name.toLowerCase().replace(/\W+/g, "-"), { folder: true });
      const creative = d.add(root, "1-creative", { folder: true });
      d.add(creative, "reference", { folder: true });
      d.add(creative, "Directors Deck script notes.pdf", { bytes: "deck" });
      if (script) {
        const s = d.add(creative, "script", { folder: true });
        if (archive) d.add(s, "z-archive", { folder: true });
        const c = current ? d.add(s, "current-draft", { folder: true }) : "";
        for (const f of files) d.add(c, f.name, { bytes: f.bytes, modified: f.modified });
        for (const f of loose) d.add(s, f.name, { bytes: f.bytes, modified: f.modified });
        roots[n] = { root, creative, script: s, current: c };
      } else roots[n] = { root, creative };
    }
    put(ID(n), { name, type, film: { relay: RELAY(n) }, facts: { type: fact(type), ...(root ? { drive_folder: fact(`https://drive.google.com/drive/folders/${root}`) } : {}), ...facts } });
    film.set(RELAY(n), drafts);
    ids.alias[RELAY(n)] = ID(n);
    env.BUCKET.put("s/ids.json", JSON.stringify(ids));
  };
  const deps = {
    api: d.api,
    drafts: async (_env, relay) => draftsOf(film.get(relay) || []),
    md5: async (e, relay, stem) => { const h = await e.BUCKET.head(`p/${relay}/media/${stem}.pdf`); return h ? h.checksums.md5 : ""; },
    md5Of: async (bytes) => md5(Buffer.from(bytes)),
  };
  const pdf = (relay, stem, bytes) => env.BUCKET.put(`p/${relay}/media/${stem}.pdf`, bytes);
  return { env, d, deps, roots, film, project, pdf, put };
}

// ── 4. the switch ─────────────────────────────────────────────────────────────
console.log("the switch");
{
  const W = world();
  W.project(1, { name: "Halcyon", files: [{ name: "Halcyon Pink.pdf", bytes: "%PDF-pink", modified: "2026-10-12T18:00:00Z" }] });
  check("off by default", (await scriptDriveOn(W.env)).on === false);
  const c = await checkOne(W.env, ID(1), undefined, W.deps);
  check("off: a check refuses", !c.ok && c.status === 409);
  const s = await settle(W.env, ID(1), {}, undefined, W.deps);
  check("off: settling refuses", !s.ok && s.status === 409);
  const u = await fileIn(W.env, ID(1), new TextEncoder().encode("%PDF-x"), {}, undefined, W.deps);
  check("off: filing an import refuses", !u.ok && u.status === 409);
  const f = await fileOut(W.env, ID(1), "drv0000000009", W.deps);
  check("off: no file is handed out", !f.ok && f.status === 409);
  check("off: nothing written to Drive", W.d.writes.length === 0);
  const cards = await allCards(W.env, { marks });
  check("off: the cards carry no script", cards.length === 1 && !("script" in cards[0]));
  const on = await setScriptDrive(W.env, { on: true, by: "check" });
  check("thrown on", on.on && (await scriptDriveOn(W.env)).on && on.by === "check");
}

// ── 5. one project looked at ──────────────────────────────────────────────────
console.log("one project");
{
  const W = world();
  await setScriptDrive(W.env, { on: true });
  W.project(1, { name: "Halcyon", files: [
    { name: "Halcyon Blue.pdf", bytes: "%PDF-blue", modified: "2026-09-28T10:00:00Z" },
    { name: "Halcyon Pink.pdf", bytes: "%PDF-pink", modified: "2026-10-12T18:00:00Z" },
    { name: "Halcyon Pink LINED.pdf", bytes: "%PDF-lined", modified: "2026-10-13T18:00:00Z" },
  ], drafts: [{ stem: STEM(1), name: "Revision (9/28/26, 3:00 AM)", came_from: "Halcyon Blue.pdf", dated: "2026-09-28T10:30:00Z" }] });
  await W.pdf(RELAY(1), STEM(1), "%PDF-blue");
  W.project(2, { name: "Daybreak", files: [{ name: "daybreak-white.pdf", bytes: "%PDF-white", modified: "2026-10-01T00:00:00Z" }],
    drafts: [{ stem: STEM(2), name: "White", came_from: "daybreak-white.pdf", dated: "2026-10-02T00:00:00Z" }] });
  await W.pdf(RELAY(2), STEM(2), "%PDF-white");
  W.project(3, { name: "No Folder Yet", script: false });
  W.project(4, { name: "Driveless", folder: false });
  W.project(5, { name: "Empty Script", files: [] });
  W.project(6, { name: "Text Only", files: [{ name: "Draft 2.pdf", bytes: "%PDF-2", modified: "2026-10-01T00:00:00Z" }],
    drafts: [{ stem: STEM(6), name: "Draft 2", came_from: "Draft 2.pdf", dated: "2026-10-03T00:00:00Z" }] });
  W.project(7, { name: "Old Leftover", files: [{ name: "first.pdf", bytes: "%PDF-first", modified: "2026-08-01T00:00:00Z" }],
    drafts: [{ stem: STEM(7), name: "Second", came_from: "second.pdf", dated: "2026-09-01T00:00:00Z" }] });
  await W.pdf(RELAY(7), STEM(7), "%PDF-second");
  W.project(8, { name: "Ad", type: "Commercial", files: [{ name: "ad.pdf", bytes: "%PDF-ad", modified: "2026-10-12T00:00:00Z" }], facts: { modes: fact({ shot_list: false, schedule: false }) } });
  // Mirrorland as it will be: its draft in current-draft/, a diagram and an old draft loose in script/.
  const LOOSE = [{ name: "Scene 7 Diagram.pdf", bytes: "%PDF-diagram", modified: "2026-10-10T00:00:00Z" },
    { name: "MIRRORLAND_HERO SCRIPT_090926.pdf", bytes: "%PDF-hero", modified: "2026-09-09T00:00:00Z" }];
  W.project(10, { name: "Mirrorland", files: [{ name: "MIRRORLAND_092626.pdf", bytes: "%PDF-look", modified: "2026-09-26T00:00:00Z" }], loose: LOOSE,
    drafts: [{ stem: STEM(10), name: "MIRRORLAND_092626", came_from: "MIRRORLAND_092626.pdf", dated: "2026-09-27T00:00:00Z" }] });
  await W.pdf(RELAY(10), STEM(10), "%PDF-look");
  // Mirrorland as it is today: script/ with loose files and no current-draft/.
  W.project(11, { name: "Mirrorland Today", current: false, loose: [...LOOSE, { name: "MIRRORLAND_092626.pdf", bytes: "%PDF-look", modified: "2026-09-26T00:00:00Z" }],
    drafts: [{ stem: STEM(11), name: "MIRRORLAND_092626", came_from: "MIRRORLAND_092626.pdf", dated: "2026-09-27T00:00:00Z" }] });
  const rec = async (n) => JSON.parse(W.env.BUCKET.m.get(`r/${ID(n)}/record.json`));
  const one = (n) => rec(n).then((r) => lookAt(W.env, ID(n), r, undefined, W.deps));
  const r1 = await one(1);
  check("Halcyon: Blue and Pink both in current-draft: he picks, never guessed", r1.status === "pick" && same(r1.choices.map((f) => f.name), ["Halcyon Pink.pdf", "Halcyon Blue.pdf"]), JSON.stringify(r1));
  check("…the choices say which is the draft in use", r1.choices[1].same === true && r1.choices[0].same === false);
  check("…the lined copy is not a draft and is left alone", r1.others.includes("Halcyon Pink LINED.pdf") && !r1.choices.some((f) => /LINED/.test(f.name)));
  check("…the draft in use carries the label every app shows", r1.in_use.label === "Halcyon Blue · Sep 28, 2026", r1.in_use.label);
  const card1 = cardScript(r1);
  check("…the card asks to pick: two choices with labels, no New draft", card1.new === null && card1.pick && card1.pick.length === 2 && card1.pick[0].label === "Halcyon Pink · Oct 12, 2026" && card1.pick[1].same === true && card1.label === "Halcyon Blue · Sep 28, 2026", JSON.stringify(card1));
  const r10 = await one(10);
  check("Mirrorland: only current-draft/ is read; the diagram loose in script/ is never offered", r10.status === "same" && cardScript(r10).new === null && cardScript(r10).pick === null, JSON.stringify(r10));
  check("…the loose files are reported by name", same([...r10.loose].sort(), LOOSE.map((f) => f.name).sort()), JSON.stringify(r10.loose));
  const r11 = await one(11);
  check("Mirrorland today (no current-draft/): no folder, nothing offered", r11.status === "no-folder" && cardScript(r11).new === null, JSON.stringify(r11));
  const W2 = world();
  await setScriptDrive(W2.env, { on: true });
  W2.project(1, { name: "One New", files: [{ name: "Pink.pdf", bytes: "%PDF-pink", modified: "2026-10-12T18:00:00Z" }], loose: [{ name: "Scene 7 Diagram.pdf", bytes: "%PDF-d", modified: "2026-10-13T00:00:00Z" }],
    drafts: [{ stem: STEM(1), name: "Blue", came_from: "Blue.pdf", dated: "2026-09-28T10:30:00Z" }] });
  await W2.pdf(RELAY(1), STEM(1), "%PDF-blue");
  const rn = await lookAt(W2.env, ID(1), JSON.parse(W2.env.BUCKET.m.get(`r/${ID(1)}/record.json`)), undefined, W2.deps);
  const cn = cardScript(rn);
  check("one new draft in current-draft/: New draft, its name and label (a newer loose file ignored)", rn.status === "new" && cn.new && cn.new.name === "Pink.pdf" && cn.new.label === "Pink · Oct 12, 2026" && cn.pick === null, JSON.stringify(cn));
  const r2 = await one(2);
  check("Daybreak: the same bytes, the same draft", r2.status === "same" && cardScript(r2).new === null);
  check("no script folder: said", (await one(3)).status === "no-folder");
  check("no Drive folder on the record: said", (await one(4)).status === "no-drive");
  check("an empty script folder: none", (await one(5)).status === "none");
  check("no PDF in the bucket: the same name is the same draft", (await one(6)).status === "same");
  check("a file older than the draft in use: older, not offered", (await one(7)).status === "older" && cardScript(await one(7)).new === null);
  check("modes off: Ad looked at like any other", (await one(8)).status === "new");
  await setModesSwitch(W.env, { on: true });
  check("modes on and Shot List off: the script is off too", (await one(8)).status === "off");
  check("…a Narrative with Shot List on is still looked at", (await one(1)).status === "pick");
  const noSign = await lookAt(W.env, ID(1), await rec(1), undefined, { ...W.deps, api: null });
  check("no Google sign-in: said, nothing read", noSign.status === "no-signin");
  check("looking wrote nothing to Drive", W.d.writes.length === 0);

  // ── 6. a check keeps what it saw ──
  console.log("a check");
  const c = await checkOne(W.env, ID(1), undefined, W.deps);
  check("a check answers the card's words", c.ok && c.script.pick && c.script.pick.length === 2);
  check("…and keeps the row", (await readState(W.env)).projects[ID(1)].status === "pick");
  const cards = await allCards(W.env, { marks });
  const cc = cards.find((x) => x.id === ID(1));
  check("the card carries the script from what was kept", cc && cc.script && cc.script.pick && cc.script.label === "Halcyon Blue · Sep 28, 2026", JSON.stringify(cc && cc.script));
  check("…a project never checked carries none", !("script" in cards.find((x) => x.id === ID(2))));
  check("a check by another of its ids (the film's relay)", (await checkOne(W.env, RELAY(2), undefined, W.deps)).row.id === ID(2));
  check("no such project", (await checkOne(W.env, ID(99), undefined, W.deps)).status === 404);

  // ── 7. confirming a draft from Drive ──
  console.log("confirming");
  const pink = r1.choices[0].id;
  const blue = r1.choices[1].id;
  const stale = await settle(W.env, ID(1), { file: "drv9999999999", stem: STEM(11) }, undefined, W.deps);
  check("a draft no longer in the folder: refused, nothing moved", !stale.ok && stale.status === 409 && W.d.writes.length === 0);
  const guess = await settle(W.env, ID(1), { stem: STEM(11) }, undefined, W.deps);
  check("two drafts and no pick: refused, nothing moved (never guessed)", !guess.ok && guess.status === 409 && /Pick/.test(guess.why) && W.d.writes.length === 0, JSON.stringify(guess));
  // Studio took Pink in: the film now has it newest (its logs arrive later in the real world).
  const s = await settle(W.env, ID(1), { file: pink, stem: STEM(11), by: "studio" }, undefined, W.deps);
  check("confirmed: Blue moved to archive, Pink stays", s.ok && same(s.archived, ["Halcyon Blue.pdf"]) && s.kept === "Halcyon Pink.pdf", JSON.stringify(s));
  const archiveId = W.roots[1] && [...W.d.items.values()].find((f) => f.name === "z-archive" && f.parents.includes(W.roots[1].script)).id;
  check("…Blue is in script/z-archive/", W.d.items.get(blue).parents[0] === archiveId);
  check("…the lined copy did not move", [...W.d.items.values()].find((f) => /LINED/.test(f.name)).parents[0] === W.roots[1].current);
  check("…the only write was the move", same(W.d.writes, [["archive", "Halcyon Blue.pdf"]]), JSON.stringify(W.d.writes));
  check("…before the film's logs arrive, Pink is already in use: no banner", s.script.new === null && s.script.label === "Halcyon Pink · " + s.script.label.split(" · ")[1], JSON.stringify(s.script));
  let kept = (await readState(W.env)).projects[ID(1)];
  const later = await lookAt(W.env, ID(1), await rec(1), undefined, W.deps, kept);
  check("…and the clock's next look agrees while the logs are still on their way", later.status === "same", JSON.stringify(later.in_use));
  W.film.set(RELAY(1), [{ stem: STEM(11), name: "Pink", came_from: "Halcyon Pink.pdf", dated: "2026-10-14T21:00:00Z" }, ...W.film.get(RELAY(1))]);
  await W.pdf(RELAY(1), STEM(11), "%PDF-pink");
  const arrived = await lookAt(W.env, ID(1), await rec(1), undefined, W.deps, kept);
  check("…and once they arrive: same, labelled from the film", arrived.status === "same" && arrived.in_use.label === "Pink · Oct 14, 2026", JSON.stringify(arrived.in_use));
  const again = await settle(W.env, ID(1), { stem: STEM(11) }, undefined, W.deps);
  check("settling again moves nothing", again.ok && same(again.archived, []) && W.d.writes.length === 1);

  // ── 8. Studio's Import, filed into Drive ──
  console.log("Studio's Import");
  const bad = await fileIn(W.env, ID(2), new TextEncoder().encode("hello there"), { name: "x.pdf" }, undefined, W.deps);
  check("not a PDF: refused", !bad.ok && bad.status === 400);
  const white = await fileIn(W.env, ID(2), new TextEncoder().encode("%PDF-white"), { name: "copy of white.pdf", stem: STEM(2) }, undefined, W.deps);
  check("the same bytes already in script/: not sent again", white.ok && white.sent === false && white.kept === "daybreak-white.pdf" && W.d.writes.length === 1, JSON.stringify(white));
  const yellow = await fileIn(W.env, ID(2), new TextEncoder().encode("%PDF-yellow"), { name: "/Users/n/Downloads/Daybreak Yellow", stem: STEM(22) }, undefined, W.deps);
  check("a new PDF: sent as its own name (.pdf added), the old one archived", yellow.ok && yellow.sent && yellow.kept === "Daybreak Yellow.pdf" && same(yellow.archived, ["daybreak-white.pdf"]), JSON.stringify(yellow));
  check("…the card has no new draft (it is the one in use)", yellow.script.new === null);
  const made = await fileIn(W.env, ID(3), new TextEncoder().encode("%PDF-first"), { name: "First.pdf", stem: STEM(33) }, undefined, W.deps);
  check("no script folder yet: script/, archive/ and current-draft/ made, then the PDF", made.ok && same(made.made, ["1-creative/script", "1-creative/script/z-archive", "1-creative/script/current-draft"]) && made.sent, JSON.stringify(made));
  const today = await fileIn(W.env, ID(11), new TextEncoder().encode("%PDF-new"), { name: "MIRRORLAND_101526.pdf", stem: STEM(111) }, undefined, W.deps);
  const looseNow = [...W.d.items.values()].filter((f) => f.parents.includes(W.roots[11].script) && !f.folder).map((f) => f.name).sort();
  check("Mirrorland today: current-draft/ made, the PDF into it, nothing loose moved", today.ok && same(today.made, ["1-creative/script/current-draft"]) && same(today.archived, [])
    && same(looseNow, ["MIRRORLAND_092626.pdf", "MIRRORLAND_HERO SCRIPT_090926.pdf", "Scene 7 Diagram.pdf"]), JSON.stringify({ today, looseNow }));
  const noDrive = await fileIn(W.env, ID(4), new TextEncoder().encode("%PDF-x"), { name: "x.pdf" }, undefined, W.deps);
  check("no Drive folder: said, nothing made", !noDrive.ok && /no Drive folder/.test(noDrive.why));
  const ro = await fileIn(W.env, ID(2), new TextEncoder().encode("%PDF-z"), { name: "z.pdf" }, undefined, { ...W.deps, api: readOnly(W.d) });
  check("a read-only sign-in: said, nothing made", !ro.ok && /can't write/.test(ro.why));

  // ── 9. a draft's PDF handed out ──
  console.log("handing out");
  const out = await fileOut(W.env, ID(1), pink, W.deps);
  check("a draft in the script folder: its bytes", out.ok && (await out.response.text()) === "%PDF-pink" && out.name === "Halcyon Pink.pdf");
  const outArch = await fileOut(W.env, ID(1), blue, W.deps);
  check("…an archived draft too", outArch.ok);
  const deck = [...W.d.items.values()].find((f) => /Directors Deck/.test(f.name)).id;
  check("a PDF elsewhere in the project: refused", (await fileOut(W.env, ID(1), deck, W.deps)).status === 404);
  check("another project's draft: refused", (await fileOut(W.env, ID(2), pink, W.deps)).status === 404);
  const lined = [...W.d.items.values()].find((f) => /LINED/.test(f.name)).id;
  check("an output in the folder: refused", (await fileOut(W.env, ID(1), lined, W.deps)).status === 404);
  const diagram = [...W.d.items.values()].find((f) => f.name === "Scene 7 Diagram.pdf" && f.parents.includes(W.roots[10].script)).id;
  check("a loose file in script/: refused", (await fileOut(W.env, ID(10), diagram, W.deps)).status === 404);

  // ── 10. the dry look ──
  console.log("the dry look");
  const before = JSON.stringify([...W.env.BUCKET.m.entries()]);
  const writes = W.d.writes.length;
  const look = await scriptLook(W.env, undefined, { wide: true }, W.deps);
  check("every project, counted by what it would say", look.projects === 10 && look.dry === true, JSON.stringify({ ...look, rows: undefined }));
  check("…writes nothing to the bucket or Drive", JSON.stringify([...W.env.BUCKET.m.entries()]) === before && W.d.writes.length === writes);
  const wide = look.rows.find((r) => r.id === ID(1)).files_found;
  check("wide: every script-looking file and where", wide && wide.some((f) => f.path === "1-creative/script/current-draft/Halcyon Pink.pdf" && f.kind === "pdf")
    && wide.some((f) => f.path === "1-creative/script/z-archive/Halcyon Blue.pdf") && wide.some((f) => f.kind === "output")
    && wide.some((f) => f.path === "1-creative/Directors Deck script notes.pdf"), JSON.stringify(wide));
  const only = await scriptLook(W.env, undefined, { only: ID(5) }, W.deps);
  check("only one project", only.projects === 1 && only.rows[0].status === "none");
  const loose = drive();
  const r = loose.add(null, "old-film", { folder: true });
  const z = loose.add(r, "z-script-archive", { folder: true });
  loose.add(z, "old.pdf", { bytes: "1" });
  loose.add(loose.add(r, "3-post", { folder: true }), "script-report.pdf", { bytes: "2" });
  loose.add(r, "notes.pdf", { bytes: "3" });
  check("wide reaches loose and archived scripts, not 3-post", same((await scriptFilesIn(loose.api, r)).map((f) => f.path), ["z-script-archive/old.pdf"]));

  // ── 11. the clock ──
  console.log("the clock");
  const at = (m) => Date.UTC(2026, 9, 14, 20, m);
  check("not at minute 4", (await onScriptTimer(W.env, undefined, at(4), W.deps)).skipped === "not this minute");
  W.env.BUCKET.m.delete(STATE_KEY);
  const tick = await onScriptTimer(W.env, undefined, at(15), W.deps);
  check("at minute 15: every project looked at and kept", tick.looked === 10 && Object.keys((await readState(W.env)).projects).length === 10, JSON.stringify(tick));
  // fixed on since stage 5 step 9: turning it off is refused, and it stays on
  const off = await setScriptDrive(W.env, { on: false });
  check("off is refused: the switch is fixed on", off.on === true && /fixed on/.test(off.problem || "") && (await scriptDriveOn(W.env)).on === true, JSON.stringify(off));
}

// ── 12. the doors ─────────────────────────────────────────────────────────────
console.log("the doors");
{
  const W = world();
  W.project(1, { name: "Halcyon", files: [{ name: "Halcyon Pink.pdf", bytes: "%PDF-pink", modified: "2026-10-12T18:00:00Z" }] });
  const door = async (method, path, body, raw) => {
    const request = new Request(`http://hub.test${path}`, { method, ...(body !== undefined ? { body: raw ? body : JSON.stringify(body) } : {}) });
    const rest = path.split("?")[0].split("/").slice(3);
    const res = await scriptDoor(W.env, request, rest, undefined, W.deps);
    if (!res) return null;
    const type = res.headers.get("content-type") || "";
    return { status: res.status, json: type.includes("json") ? await res.json() : null, text: type.includes("json") ? "" : await res.text(), res };
  };
  check("the switch reads off", (await door("GET", "/console/studio/scriptdrive")).json.on === false);
  check("a look answers with the switch off", (await door("POST", "/console/studio/script/look", {})).json.projects === 1);
  check("one project's kept row, off: no script", (await door("GET", `/console/studio/script/${ID(1)}`)).json.script === null);
  check("a check refuses while off", (await door("POST", `/console/studio/script/${ID(1)}/check`, {})).status === 409);
  check("the template door, dry", (await door("POST", "/console/studio/script/template", {})).json.already === true);
  check("thrown on", (await door("PUT", "/console/studio/scriptdrive", { on: true, by: "check" })).json.on === true);
  const c = await door("POST", `/console/studio/script/${ID(1)}/check`, {});
  check("a check: new draft (the film has none yet)", c.status === 200 && c.json.script.new.name === "Halcyon Pink.pdf", JSON.stringify(c.json));
  const kept = await door("GET", `/console/studio/script/${ID(1)}`);
  check("one project's kept row, on", kept.json.on && kept.json.script.new.file === c.json.script.new.file);
  const file = await door("GET", `/console/studio/script/${ID(1)}/file/${c.json.script.new.file}`);
  check("the file door: the PDF", file.status === 200 && file.res.headers.get("content-type") === "application/pdf" && file.text === "%PDF-pink");
  const up = await door("PUT", `/console/studio/script/${ID(1)}/upload?name=Halcyon%20Yellow.pdf&stem=${STEM(5)}`, new TextEncoder().encode("%PDF-yellow"), true);
  check("the upload door: sent, Pink archived", up.status === 200 && up.json.sent && same(up.json.archived, ["Halcyon Pink.pdf"]), JSON.stringify(up.json));
  const st = await door("POST", `/console/studio/script/${ID(1)}/settle`, { stem: STEM(5) });
  check("the settle door: nothing more to move", st.status === 200 && same(st.json.archived, []));
  check("not JSON: refused", (await door("POST", `/console/studio/script/${ID(1)}/settle`, "{nope", true)).status === 400);
  check("a wrong method", (await door("DELETE", `/console/studio/script/${ID(1)}/check`)).status === 405);
  check("an unknown door under script/", (await door("GET", `/console/studio/script/${ID(1)}/nothing`)).status === 404);
  check("other doors are not this one's", (await door("GET", "/console/studio/cards")) === null);
}

console.log(`\nscriptdrive: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
