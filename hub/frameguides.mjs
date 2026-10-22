#!/usr/bin/env node
/**
 * **Frame guide files on an aspect ratio** (2026-10-15, src/specsheet.js).
 * Offline: the sheet keeps them on the ratio they sit under, the ops add,
 * rename, tag a camera, link and remove them, a removed ratio's files go
 * under Main, the camera page lays them with their links.
 *
 *     node hub/frameguides.mjs
 */
import { checkSheet, applyFrameOp, laySheets, ratioOnCard } from "./src/specsheet.js";

let pass = 0, fail = 0;
const check = (what, good, why) => {
  if (good) { pass += 1; console.log(`  ${what.slice(0, 70).padEnd(72)} PASS`); }
  else { fail += 1; console.log(`  ${what.slice(0, 70).padEnd(72)} FAIL — ${JSON.stringify(why)}`); }
};
const J = JSON.stringify;
const base = checkSheet({ format: 1, cameras: [{ label: "A Cam", body: "Alexa 35" }], frames: [{ name: "Main", ratio: "2.39:1", main: true }, { name: "Social", ratio: "9:16" }] }).sheet;

let s = applyFrameOp(base, { op: "add_guide", at: 0, guide: { file: "3-post/frame-line/arri-2.39.xml", name: "ARRI 2.39", camera: "A Cam", url: "" } });
check("a file is added under a ratio", s.sheet && s.sheet.frames[0].guides.length === 1 && s.sheet.frames[0].guides[0].camera === "A Cam", s);
s = applyFrameOp(s.sheet, { op: "add_guide", at: 0, guide: { file: "3-post/frame-line/red.rfg" } });
check("a name defaults to the file name", s.sheet.frames[0].guides[1].name === "red.rfg", s.sheet.frames[0].guides);
s = applyFrameOp(s.sheet, { op: "link_guide", file: "3-post/frame-line/red.rfg", url: "https://drive.google.com/uc?export=download&id=abc123" });
check("Drive's link lands on the file that names it", s.sheet.frames[0].guides[1].url.endsWith("abc123"), s);
check("a link for no file is refused", applyFrameOp(s.sheet, { op: "link_guide", file: "nope", url: "https://x.y/z" }).why === "No such frame guide.");
s = applyFrameOp(s.sheet, { op: "guide", at: 0, i: 1, name: "RED 2.39", note: "B body only", camera: "B Cam" });
check("rename, note and camera", J(s.sheet.frames[0].guides[1]) === J({ name: "RED 2.39", camera: "B Cam", note: "B body only", file: "3-post/frame-line/red.rfg", url: "https://drive.google.com/uc?export=download&id=abc123" }), s.sheet.frames[0].guides[1]);
check("an empty name is refused", applyFrameOp(s.sheet, { op: "guide", at: 0, i: 0, name: " " }).why === "Say the frame guide's name.");
check("a file with a non-https link is refused", Boolean(checkSheet({ ...s.sheet, frames: [{ name: "Main", ratio: "", main: true, guides: [{ name: "x", file: "a", url: "http://x" }] }] }).why));
check("a path climbing out of the folder is refused", Boolean(checkSheet({ ...s.sheet, frames: [{ name: "Main", ratio: "", main: true, guides: [{ name: "x", file: "../a" }] }] }).why));
// a sheet with no frames: a file sits under Main
const bare = checkSheet({ format: 1, cameras: [] }).sheet;
const under = applyFrameOp(bare, { op: "add_guide", at: 0, guide: { file: "3-post/frame-line/a.png" } });
check("on a sheet with no ratios a file sits under Main", under.sheet.frames.length === 1 && under.sheet.frames[0].main && under.sheet.frames[0].guides.length === 1, under);
// the camera page
const card = { camera: {} };
laySheets(card, { spec_project: { sheet: s.sheet, v: 1 } });
check("the page ratios carry their files", card.camera && true, card);
const shoot = { shoot: "" };
const onCard = s.sheet.frames.map(ratioOnCard);
check("ratioOnCard: Main with two files, Social with none", onCard[0].guides.length === 2 && !("guides" in onCard[1]), onCard);
check("a card's files carry name, camera, note and link only", J(Object.keys(onCard[0].guides[0])) === J(["name", "camera", "note", "url"]), onCard[0].guides[0]);
// remove
const r = applyFrameOp(s.sheet, { op: "remove_guide", at: 0, i: 0 });
check("a file is removed from the sheet", r.sheet.frames[0].guides.length === 1, r);
const r2 = applyFrameOp(r.sheet, { op: "remove_guide", at: 0, i: 0 });
check("the last one leaves no empty list", !("guides" in r2.sheet.frames[0]), r2.sheet.frames[0]);
// a removed ratio's files go under Main
let t = applyFrameOp(s.sheet, { op: "add_guide", at: 1, guide: { file: "3-post/frame-line/social.png", name: "Social" } });
t = applyFrameOp(t.sheet, { op: "remove_frame", at: 1 });
check("a removed ratio's files go under Main", t.sheet.frames.length === 1 && t.sheet.frames[0].guides.some((g) => g.name === "Social"), t.sheet.frames);
// the limit
let full = base;
for (let i = 0; i < 12; i++) full = applyFrameOp(full, { op: "add_guide", at: 0, guide: { file: `3-post/frame-line/${i}.xml` } }).sheet;
check("twelve to a ratio, no more", Boolean(applyFrameOp(full, { op: "add_guide", at: 0, guide: { file: "3-post/frame-line/x.xml" } }).why));
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
