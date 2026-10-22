#!/usr/bin/env node
/**
 * **The Camera Spec Sheet as a Google Sheet** — the workbook itself
 * (`src/specsheetsheet.js`), no hub, no Google. 2026-10-15.
 *
 * What is checked: the tabs (the project's, then each shoot's own), the
 * sections in the app's order, every box a camera, lens, filter, aspect ratio
 * and finishing resolution has, the header line and the "Updated" line, that
 * every LUT and frame guide file is a real hyperlink to its Drive file (and
 * that one Notion still holds is not), that the words are what is compared
 * (a time never makes a change), that the .xlsx is a valid zip and opens in
 * another program (openpyxl) with the same words and links, and the same on
 * every real project's sheets from the portal backup's mirror (read only).
 *
 *     node hub/specsheetsheet.mjs
 */
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { recordSheets as recordSheetsPlain, checkSheet } from "./src/specsheet.js";
import * as S from "./src/specsheetsheet.js";
import { entryOfSheetLens } from "./src/lenslibrary.js";

const HERE = dirname(fileURLToPath(import.meta.url));
let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(96)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 700)}`}`);
};
const say = (x) => JSON.stringify(x);

/**
 * `recordSheets`, plus the frame guide files on the aspect ratios. Those ride
 * on each frame as `guides: [{name, camera, note, file, url}]` (the frame guide
 * files work, specsheet.js); where the sheet's checks already keep them they
 * come through `recordSheets` as they are, and where they do not yet, they are
 * laid on from the raw fact so this file checks the workbook either way.
 */
function recordSheets(facts) {
  const out = recordSheetsPlain(facts);
  for (const [name, one] of Object.entries(out)) {
    const raw = facts[name] && facts[name].value && facts[name].value.frames;
    if (!Array.isArray(raw) || !one.sheet.frames) continue;
    one.sheet.frames.forEach((f, i) => { if (raw[i] && raw[i].guides && !f.guides) f.guides = raw[i].guides; });
  }
  return out;
}

/** The workbook as another program reads it: [{name, cells: {A1: {v, link}}}]. */
function readBack(bytes) {
  const dir = mkdtempSync(join(tmpdir(), "specsheetsheet-"));
  const file = join(dir, "out.xlsx");
  writeFileSync(file, bytes);
  const py = `
import json, sys, openpyxl
wb = openpyxl.load_workbook(sys.argv[1])
out = []
for ws in wb:
    cells = {}
    merged = [str(m) for m in ws.merged_cells.ranges]
    for row in ws.iter_rows():
        for c in row:
            if c.value not in (None, ""):
                cells[c.coordinate] = {"v": c.value, "link": c.hyperlink.target if c.hyperlink else None, "bold": bool(c.font and c.font.b)}
    out.append({"name": ws.title, "cells": cells, "merged": merged, "widthA": ws.column_dimensions["A"].width})
print(json.dumps(out))`;
  const r = spawnSync("python3", ["-I", "-c", py, file], { encoding: "utf8" });
  const zip = spawnSync("unzip", ["-tq", file], { encoding: "utf8" });
  return { tabs: r.status === 0 ? JSON.parse(r.stdout) : null, err: r.stderr, zipOk: zip.status === 0, file };
}
const texts = (tab) => Object.values(tab.cells).map((c) => String(c.v));
const rowOf = (tab, word, col = "A") => Object.keys(tab.cells).find((k) => k.startsWith(col) && String(tab.cells[k].v) === word);
const rowNo = (ref) => Number(ref.replace(/^[A-Z]+/, ""));

// ── a project with everything on it ─────────────────────────────────────────
const SH1 = "4acab7b3b555897c7c58dce7762aca55", SH2 = "50ad95105a93869dd1c97f9e1a45a05a";
const lutDrive = "https://drive.google.com/open?id=1ExampleLutFileIdAAAAAAAAAAAAAAAAA&usp=drive_fs";
const lutShare = "https://drive.google.com/file/d/1ExampleLutShareIdBBBBBBBBBBBBBBBB/view?usp=sharing";
const guideUrl = "https://drive.google.com/file/d/1GuideFileIdAAAAAAAAAAAAAAAAAAAAAA/view";
const project = {
  format: 1, shoot: "", notion: "", title: "Test Film Camera Spec Sheet",
  cameras: [
    { label: "A Cam", body: "Alexa 35", format: ["4.6K 3:2 Open Gate"], capture: ["4608 x 3164"], fps: ["24.00"], codec: ["ProRes 4444"], colour: ["AWG4 / LogC4"], desqueeze: ["1.0x"],
      luts: [{ label: "", name: "show-logc4.aml", url: lutDrive }, { label: "", name: "held-in-notion.cube", url: "", held: true }],
      sensor: { ref: "m-alexa3546k32opengate", name: "4.6K 3:2 Open Gate", width: 27.99, height: 19.22 } },
    { label: "B Cam", body: "Sony FX6", format: ["S35 HD"], capture: ["1920 x 1080"], fps: ["23.976"], codec: ["XAVC-I"], colour: ["S-Gamut3.Cine / S-Log3"], desqueeze: ["1.0x"],
      luts: [{ label: "", name: lutShare, url: lutShare }] },
  ],
  lenses: [
    { name: "Master Prime 25mm", note: "A Cam only", ref: "l-masterprime25mm", stop: "T1.3", set: "ARRI Master Primes" },
    { name: "Fujinon Premier 75-400mm", note: "", stop: "T2.8-3.8" },
    { name: "Signature Primes", note: "" },
  ],
  modifiers: [{ name: "Atlas LF Extender 1.6x", note: "" }],
  filters: [{ name: "138mm Revar Wormhole Filter", note: "", set: "Revar Cine" }],
  frames: [
    { name: "Web", ratio: "1.33:1", main: false },
    { name: "Theatrical", ratio: "2.39:1", main: true, guides: [
      { name: "alexa35-239.xml", camera: "A Cam", note: "ARRI frame lines", file: "3-post/frame-line/alexa35-239.xml", url: guideUrl },
      { name: "fx6-239.png", camera: "B Cam", note: "", file: "3-post/frame-line/fx6-239.png", url: "https://drive.google.com/open?id=1OtherGuideFileIdBBBBBBBBBBBBB" },
      { name: "pending.xml", camera: "", note: "not in Drive yet", file: "3-post/frame-line/pending.xml", url: "" },
    ] },
    { name: "Social", ratio: "9:16", main: false },
  ],
  finishing_resolutions: [{ title: "Master", resolution: "4096 x 2160", note: "DCI 4K for the grade" }, { title: "Web", resolution: "1920 x 1080", note: "" }],
  notes: "Tribe7 Blackwings: T-Tuned & <ready>\nSecond line\u0001 with a control character",
  files: [{ name: "camera-report.pdf", url: "https://drive.google.com/open?id=1ReportFileIdCCCCCCCCCCCCCCCC" }],
};
const shoot2 = { ...project, shoot: SH2, title: "Test Film - Shoot 2", cameras: [project.cameras[0]], lenses: [{ name: "Angenieux Optimo 45-165mm", note: "", stop: "T2.3" }],
  modifiers: [], filters: [], frames: [{ name: "Main", ratio: "16:9", main: true }], finishing_resolutions: [], notes: "", files: [] };
const facts = {
  spec_project: { value: project, v: 3 },
  [`spec_${SH2}`]: { value: shoot2, v: 1 },
  shoots: { value: [{ id: SH2, label: "Shoot 2", n: 2, start: "2026-10-06" }, { id: SH1, label: "Shoot 1", n: 1, start: "2026-07-09" }] },
};
const sheets = recordSheets(facts);
const lib = {
  sets: [{ id: "s-arrimasterprimes", name: "ARRI Master Primes", whole: false }],
  lenses: [{ id: "l-masterprime25mm", name: "Master Prime 25mm", focal: "25", stop: "T1.3", set: "s-arrimasterprimes", close_focus: "0.35 m", close_focus_m: 0.35 }],
  merged: {},
};
const input = { name: "Test & Film <1>", sheets, shoots: facts.shoots.value, lib, lensEntry: entryOfSheetLens };
const NOW = new Date("2026-10-16T02:41:00Z");
const updated = S.updatedWords(NOW);

console.log("the tabs");
check("the sheets are checked and kept (2: the project's and Shoot 2's)", Object.keys(sheets).length === 2, say(Object.keys(sheets)));
const tabs = S.tabsOf(input, updated);
check("one tab for the project's sheet, then the shoot's own", tabs.length === 2 && tabs[0].name === "Project" && tabs[1].name === "Shoot 2", say(tabs.map((t) => t.name)));
check("a shoot with no sheet of its own (Shoot 1) has no tab", !tabs.some((t) => t.name === "Shoot 1"));
check("the project with no sheet has no tabs at all", S.tabsOf({ ...input, sheets: {} }, updated).length === 0);
check("updated line reads on his clock (Pacific)", updated === "Updated Oct 15, 2026, 7:41 PM PT", updated);

const bytes = S.xlsxOf(tabs);
const back = readBack(bytes);
check("the .xlsx is a valid zip", back.zipOk);
check("another program (openpyxl) opens it", Boolean(back.tabs), back.err);
const [P, SHOOT] = back.tabs || [];
check("…with the tab names in order", back.tabs && P.name === "Project" && SHOOT.name === "Shoot 2", say((back.tabs || []).map((t) => t.name)));

console.log("the header");
check("title: the project's name and Camera Spec Sheet (XML characters kept)", P.cells.A1 && P.cells.A1.v === "Test & Film <1> — Camera Spec Sheet", say(P.cells.A1));
check("the tab says which sheet it is (project / shoot and its date)", P.cells.A2.v === "Project" && SHOOT.cells.A2.v === "Shoot 2 · Oct 6, 2026", say([P.cells.A2, SHOOT.cells.A2]));
check("one-line note: Updated automatically from Projects Console.", P.cells.A3.v === "Updated automatically from Projects Console." && SHOOT.cells.A3.v === S.HEADER_NOTE, say(P.cells.A3));
check("an Updated <date time> line", P.cells.A4.v === updated, say(P.cells.A4));

console.log("the sections, in the app's order");
const at = (tab, w) => rowNo(rowOf(tab, w));
check("Camera, Color, Deliverables, Notes — in that order on every tab", [P, SHOOT].every((t) => at(t, "CAMERA") < at(t, "COLOR") && at(t, "COLOR") < at(t, "DELIVERABLES") && at(t, "DELIVERABLES") < at(t, "NOTES")));
check("a section band is bold and spans the tab", P.cells[`A${at(P, "CAMERA")}`].bold === true);

console.log("camera");
const camHead = at(P, "CAMERA") + 1;
check("camera columns: Camera, Body, Sensor mode, Capture resolution, Frame rate, Codec, Desqueeze, Sensor size",
  say(["A", "B", "C", "D", "E", "F", "G", "H"].map((c) => P.cells[`${c}${camHead}`].v)) === say(["Camera", "Body", "Sensor mode", "Capture resolution", "Frame rate", "Codec", "Desqueeze", "Sensor size"]));
check("A Cam: Alexa 35 · 4.6K 3:2 Open Gate · 4608 x 3164 · 24.00 · ProRes 4444 · 1.0x · 27.99 × 19.22 mm",
  say(["A", "B", "C", "D", "E", "F", "G", "H"].map((c) => P.cells[`${c}${camHead + 1}`].v)) === say(["A Cam", "Alexa 35", "4.6K 3:2 Open Gate", "4608 x 3164", "24.00", "ProRes 4444", "1.0x", "27.99 × 19.22 mm"]));
check("B Cam has no sensor size and so none is invented", P.cells[`B${camHead + 2}`].v === "Sony FX6" && !P.cells[`H${camHead + 2}`]);
const lensHead = rowNo(rowOf(P, "Lens"));
check("lens columns: Lens, Focal length, T-stop, Close focus, Set, Note", say(["A", "B", "C", "D", "E", "F"].map((c) => P.cells[`${c}${lensHead}`].v)) === say(["Lens", "Focal length", "T-stop", "Close focus", "Set", "Note"]));
check("Master Prime 25mm: 25 mm · T1.3 · 0.35 m · ARRI Master Primes · A Cam only (focal and close focus from the library)",
  say(["A", "B", "C", "D", "E", "F"].map((c) => P.cells[`${c}${lensHead + 1}`].v)) === say(["Master Prime 25mm", "25 mm", "T1.3", "0.35 m", "ARRI Master Primes", "A Cam only"]));
check("a lens the library does not have: focal length from its name, stop from the sheet, no close focus",
  P.cells[`B${lensHead + 2}`].v === "75-400 mm" && P.cells[`C${lensHead + 2}`].v === "T2.8-3.8" && !P.cells[`D${lensHead + 2}`]);
check("a set sold whole has no focal length and none is invented", P.cells[`A${lensHead + 3}`].v === "Signature Primes" && !P.cells[`B${lensHead + 3}`]);
check("filters (with their set) and modifiers are listed", texts(P).includes("138mm Revar Wormhole Filter") && texts(P).includes("Revar Cine") && texts(P).includes("Atlas LF Extender 1.6x"));
check("the shoot's own sheet shows its own lens, not the project's", texts(SHOOT).includes("Angenieux Optimo 45-165mm") && !texts(SHOOT).includes("Master Prime 25mm"));

console.log("color and LUTs");
const colorHead = at(P, "COLOR") + 1;
check("color columns: Camera, Color space, LUT", say(["A", "B", "C"].map((c) => P.cells[`${c}${colorHead}`].v)) === say(["Camera", "Color space", "LUT"]));
const lutRow = (name) => Object.keys(P.cells).find((k) => k.startsWith("C") && String(P.cells[k].v) === name);
check("a LUT with a Drive address is a hyperlink to the file's own address", P.cells[lutRow("show-logc4.aml")].link === "https://drive.google.com/file/d/1ExampleLutFileIdAAAAAAAAAAAAAAAAA/view", say(P.cells[lutRow("show-logc4.aml")]));
check("a LUT whose name is its address shows a word, not the address, and still links", (() => { const k = Object.keys(P.cells).find((x) => P.cells[x].link === "https://drive.google.com/file/d/1ExampleLutShareIdBBBBBBBBBBBBBBBB/view"); return k && P.cells[k].v === "LUT"; })());
const heldRow = lutRow("held-in-notion.cube");
check("a LUT Notion still holds: its name, no link, and it says so", P.cells[heldRow].link === null && P.cells[`D${rowNo(heldRow)}`].v === "In Notion, not in Drive yet", say(P.cells[heldRow]));
check("the color space shows once on a camera's first LUT row", P.cells[`B${rowNo(lutRow("show-logc4.aml"))}`].v === "AWG4 / LogC4" && !P.cells[`B${rowNo(heldRow)}`]);

console.log("deliverables");
const ar = at(P, "DELIVERABLES") + 1;
check("aspect ratio columns: Aspect ratio, Ratio, Main, Frame guide file, Camera, Note", say(["A", "B", "C", "D", "E", "F"].map((c) => P.cells[`${c}${ar}`].v)) === say(["Aspect ratio", "Ratio", "Main", "Frame guide file", "Camera", "Note"]));
check("Main aspect ratio comes first", P.cells[`A${ar + 1}`].v === "Theatrical" && P.cells[`C${ar + 1}`].v === "Main");
check("its frame guide file is a hyperlink to the Drive file", P.cells[`D${ar + 1}`].v === "alexa35-239.xml" && P.cells[`D${ar + 1}`].link === guideUrl, say(P.cells[`D${ar + 1}`]));
check("…with the camera and note beside it", P.cells[`E${ar + 1}`].v === "A Cam" && P.cells[`F${ar + 1}`].v === "ARRI frame lines");
check("a second guide file takes the next row and an old-form Drive address becomes the file's own", P.cells[`D${ar + 2}`].link === "https://drive.google.com/file/d/1OtherGuideFileIdBBBBBBBBBBBBB/view" && !P.cells[`A${ar + 2}`]);
check("a guide file not in Drive yet has its name and no link", P.cells[`D${ar + 3}`].v === "pending.xml" && P.cells[`D${ar + 3}`].link === null);
check("the other aspect ratios follow", P.cells[`A${ar + 4}`].v === "Web" && P.cells[`B${ar + 4}`].v === "1.33:1" && P.cells[`A${ar + 5}`].v === "Social");
const fr = rowNo(rowOf(P, "Finishing resolution"));
check("finishing resolutions: title, resolution, note", P.cells[`A${fr + 1}`].v === "Master" && P.cells[`B${fr + 1}`].v === "4096 x 2160" && P.cells[`C${fr + 1}`].v === "DCI 4K for the grade");
check("a shoot sheet with no list of its own shows the project's (the app's rule)", texts(SHOOT).includes("4096 x 2160"), say(texts(SHOOT)));

console.log("notes and files");
const nr = at(P, "NOTES");
check("a note line is one row, merged across the tab", P.cells[`A${nr + 1}`].v === "Tribe7 Blackwings: T-Tuned & <ready>" && P.merged.includes(`A${nr + 1}:H${nr + 1}`), say([P.cells[`A${nr + 1}`], P.merged]));
check("a control character is dropped, not written into the XML", P.cells[`A${nr + 2}`].v === "Second line with a control character", say(P.cells[`A${nr + 2}`]));
check("a sheet's file is a hyperlink", Object.values(P.cells).some((c) => c.v === "camera-report.pdf" && c.link === "https://drive.google.com/file/d/1ReportFileIdCCCCCCCCCCCCCCCC/view"));
check("an empty notes section says so", texts(SHOOT).includes("No notes."));

console.log("every link on the tab is a link someone can follow");
const linkCells = [...P.cells ? Object.values(P.cells) : [], ...Object.values(SHOOT.cells)].filter((c) => c.link);
check(`${linkCells.length} links, every one https`, linkCells.length >= 6 && linkCells.every((c) => /^https:\/\//.test(c.link)));
const expected = tabs.flatMap((t) => t.rows.flat().filter((c) => c.link).map((c) => c.link));
check("the links in the workbook are exactly the ones the model made", say(linkCells.map((c) => c.link).sort()) === say([...expected].sort()));

console.log("what is compared");
const h1 = await S.contentHash(S.tabsOf(input, "Updated at one time"));
const h2 = await S.contentHash(S.tabsOf(input, "Updated at another"));
check("the Updated time never makes a change", h1 === h2);
const edited = JSON.parse(JSON.stringify(project)); edited.lenses[1].name = "Fujinon Premier 75-400mm II";
const h3 = await S.contentHash(S.tabsOf({ ...input, sheets: recordSheets({ ...facts, spec_project: { value: edited, v: 4 } }) }, updated));
check("a lens renamed does", h3 !== h1);
const edited2 = JSON.parse(JSON.stringify(project)); edited2.frames[1].guides[0].url = "https://drive.google.com/file/d/1NewGuideAAAAAAAAAAAAAAAAAAAAAAA/view";
check("a frame guide's link changed does", (await S.contentHash(S.tabsOf({ ...input, sheets: recordSheets({ ...facts, spec_project: { value: edited2, v: 4 } }) }, updated))) !== h1);
check("a camera's version number alone does not (only words are compared)", (await S.contentHash(S.tabsOf({ ...input, sheets: recordSheets({ ...facts, spec_project: { value: project, v: 99 } }) }, updated))) === h1);

console.log("links and names");
const L = S.driveLink;
check("driveLink: open?id= → file/d/<id>/view", L("https://drive.google.com/open?id=1abcdefghijKLMN&usp=drive_fs") === "https://drive.google.com/file/d/1abcdefghijKLMN/view");
check("driveLink: file/d/<id>/view?usp=sharing → the same", L("https://drive.google.com/file/d/1abcdefghijKLMN/view?usp=sharing") === "https://drive.google.com/file/d/1abcdefghijKLMN/view");
check("driveLink: a folder, a Doc and a non-Drive address stay as they are", L("https://drive.google.com/drive/folders/1abcdefghijKLMN") === "https://drive.google.com/drive/folders/1abcdefghijKLMN"
  && L("https://docs.google.com/document/d/1abcdefghijKLMN/edit") === "https://docs.google.com/document/d/1abcdefghijKLMN/edit" && L("https://example.com/x.cube") === "https://example.com/x.cube");
check("driveLink: nothing, or something that is not https, is no link", L("") === "" && L("http://drive.google.com/x") === "" && L("javascript:alert(1)") === "" && L("file:///x") === "");
check("file name: <slug>-camera-spec-sheet, lower case", S.fileNameOf("Lets-Bake", "") === "lets-bake-camera-spec-sheet" && S.fileNameOf("", "Call Her Back!") === "call-her-back-camera-spec-sheet" && S.fileNameOf("", "") === "project-camera-spec-sheet");
{
  const odd = S.tabsOf({ ...input, shoots: [{ id: SH2, label: "Shoot: 2 [a]/b?*", n: 1 }] }, "");
  check("a tab name has none of the characters a sheet refuses, and is at most 31 long", odd[1].name === "Shoot 2 a b" && odd.every((t) => t.name.length <= 31), say(odd.map((t) => t.name)));
  const dup = S.tabsOf({ ...input, shoots: [{ id: SH2, label: "Project", n: 1 }] }, "");
  check("two tabs never share a name", new Set(dup.map((t) => t.name.toLowerCase())).size === dup.length, say(dup.map((t) => t.name)));
  const lost = S.tabsOf({ ...input, shoots: [] }, "");
  check("a sheet whose shoot the project no longer lists still has its tab", lost.length === 2 && lost[1].fact === `spec_${SH2}`, say(lost.map((t) => t.name)));
  const none = S.tabsOf({ ...input, sheets: recordSheets({ spec_project: { value: checkSheet({}).sheet, v: 1 } }) }, "");
  const emptyBack = readBack(S.xlsxOf(none));
  check("a sheet with nothing on it still makes a workbook, each section saying so", emptyBack.tabs && texts(emptyBack.tabs[0]).includes("No cameras listed.") && texts(emptyBack.tabs[0]).includes("No lenses listed.") && texts(emptyBack.tabs[0]).includes("No aspect ratios listed."), say(texts((emptyBack.tabs || [{ cells: {} }])[0])));
}

console.log("every real project's sheets (the portal backup's mirror, read only)");
const MIRROR = join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups/mirror/bucket/r");
let real = 0;
if (existsSync(MIRROR)) {
  for (const key of readdirSync(MIRROR)) {
    const f = join(MIRROR, key, "record.json");
    if (!existsSync(f)) continue;
    let rec;
    try { rec = JSON.parse(readFileSync(f, "utf8")); } catch { continue; }
    const ss = recordSheets((rec && rec.facts) || {});
    if (!Object.keys(ss).length) continue;
    real += 1;
    const shoots = rec.facts.shoots && Array.isArray(rec.facts.shoots.value) ? rec.facts.shoots.value : [];
    const tb = S.tabsOf({ name: rec.name, sheets: ss, shoots, lib: null, lensEntry: null }, updated);
    const rb = readBack(S.xlsxOf(tb));
    const sheetWords = (t) => t.cells;
    let good = rb.zipOk && rb.tabs && rb.tabs.length === Object.keys(ss).length;
    const wantLinks = [];
    for (const [fact, one] of Object.entries(ss)) {
      for (const c of one.sheet.cameras) for (const l of c.luts) if (S.driveLink(l.url)) wantLinks.push(S.driveLink(l.url));
      for (const fr of one.sheet.frames || []) for (const g of fr.guides || []) if (S.driveLink(g.url)) wantLinks.push(S.driveLink(g.url));
    }
    const gotLinks = (rb.tabs || []).flatMap((t) => Object.values(sheetWords(t)).filter((c) => c.link).map((c) => c.link));
    good = good && wantLinks.every((u) => gotLinks.includes(u));
    const heldNames = Object.values(ss).flatMap((o) => o.sheet.cameras.flatMap((c) => c.luts.filter((l) => !l.url).map((l) => l.name)));
    good = good && heldNames.every((n) => (rb.tabs || []).some((t) => texts(t).includes(n)));
    const order = (rb.tabs || []).every((t) => { const a = ["CAMERA", "COLOR", "DELIVERABLES", "NOTES"].map((w) => rowNo(rowOf(t, w) || "A0")); return a.every((x, i) => x > 0 && (i === 0 || x > a[i - 1])); });
    check(`${rec.name}: ${tb.length} tab${tb.length === 1 ? "" : "s"}, sections in order, ${wantLinks.length} LUT/guide link${wantLinks.length === 1 ? "" : "s"} all there, held LUTs named`, good && order, say({ zip: rb.zipOk, tabs: (rb.tabs || []).length, wantLinks, gotLinks, heldNames, order }));
    for (const t of tb) check(`${rec.name} / ${t.name}: the cameras' words are on the tab`, (() => { const one = ss[t.fact].sheet; const rbT = (rb.tabs || []).find((x) => x.name === t.name); return rbT && one.cameras.every((c) => texts(rbT).includes(c.body) && c.capture.every((v) => texts(rbT).some((x) => x.includes(v)))); })());
  }
  check(`real projects with a sheet were read (${real})`, real >= 5, real);
} else {
  console.log("  (no mirror on this machine: skipped)");
}

console.log(`\nspecsheetsheet: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
void HERE;
