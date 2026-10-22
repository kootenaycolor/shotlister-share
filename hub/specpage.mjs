#!/usr/bin/env node
/**
 * **The camera page's LUTs and Notes, drawn as Projects Console draws them**
 * (2026-10-14, his ask: "get the portal looking more like the project console
 * in the way it handles luts and notes").
 *
 * - LUTs are a row of the sheet's table, each file a chip by its name that
 *   opens it; drawn once across when every camera has the same, else a
 *   column per camera, under the cameras the Camera row names;
 * - a file Notion keeps itself says "File in Notion", a link while the hub
 *   holds a copy and plain words when it holds none;
 * - Notes are the table's last row: the record's words as typed, or the
 *   Notion sheet's page drawn in the row;
 * - a sheet's other files (camera reports) stay under Files, not in LUTs;
 * - both sources: the record's sheet laid on a card (specsheet.js) and a card
 *   Notion wrote; one camera and two.
 *
 *     node hub/specpage.mjs              the checks
 *     node hub/specpage.mjs --html DIR   also writes each case as a page asking
 *                                        for the portal's stylesheets at /hub.css
 *                                        and so on, to serve and photograph
 *
 * No server, no bucket: the page is drawn the way the worker draws it.
 */
import { register } from "node:module";
import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// as portalshare.mjs: the engine's .wasm stood in for, a JSON import read as JSON
register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

const { emptyFront, tidy } = await import("./src/front.js");
const { recordBody, phoneFrontOf } = await import("./src/pages.js");
const { checkSheet, laySheets } = await import("./src/specsheet.js");

const HERE = dirname(fileURLToPath(import.meta.url));
const at = process.argv.indexOf("--html");
const OUT = at > 0 ? process.argv[at + 1] : "";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) { pass += 1; console.log(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; console.log(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

const BASE = "/f/halcyon";
const LUT_A = "halcyon-spicy-logc3.aml";
const LUT_B = "halcyon-spicy-slog3.cube";
const HELD = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.cube";

/** Halcyon's sheet on the record: A Cam Alexa Mini, B Cam FX6, a LUT each. */
function halcyonSheet(over = {}) {
  const got = checkSheet({
    title: "Halcyon",
    cameras: [
      { label: "A Cam", body: "Arri Alexa Mini", format: ["Alexa Mini LF Open Gate"], capture: ["1920 x 1080"],
        fps: ["23.976"], codec: ["ProRes 4444"], colour: ["AWG3 / LogC3"], desqueeze: ["1.0x"],
        luts: [{ name: LUT_A, url: "https://drive.google.com/file/d/aaa/view" }] },
      { label: "B Cam", body: "Sony FX6", format: ["FX6 4K 17:9"], capture: ["3840 x 2160"],
        fps: ["23.976"], codec: ["XAVC-I", "ProRes 422 HQ"], colour: ["S-Gamut3.Cine / S-Log3"], desqueeze: ["1.0x"],
        luts: [{ name: LUT_B, url: "https://drive.google.com/file/d/bbb/view" }] },
    ],
    lenses: [{ name: "Master Prime 25mm" }, { name: "Master Prime 35mm" }, { name: "Canon 8-64mm", note: "A Cam only" }],
    notes: "Canon 8-64mm from Keslow, rehoused\nB Cam on the Eye Direct",
    ...over,
  });
  if (!got.sheet) throw new Error(got.why);
  return got.sheet;
}

function oneCameraSheet(over = {}) {
  const got = checkSheet({
    cameras: [{ label: "A Cam", body: "Arri Alexa Mini", format: ["2.8K 4:3"], fps: ["24"], codec: ["ProRes 4444"], colour: ["AWG3 / LogC3"],
      desqueeze: ["1.0x"], luts: [{ label: "Show LUT", name: "chb-show.cube", url: "https://drive.google.com/file/d/ccc/view" }] }],
    lenses: [{ name: "Master Prime 16mm" }],
    notes: "Rehoused, Keslow",
    ...over,
  });
  if (!got.sheet) throw new Error(got.why);
  return got.sheet;
}

/** A card with the record's sheet laid on it, as the portal reads one with the switch on. */
function fromRecord(sheet, title = "Halcyon") {
  const front = tidy({ ...emptyFront(), title });
  laySheets(front, { spec_project: { sheet, v: 1 } });
  return front;
}

/** A card Notion wrote: labelled lines, LUT Labels, the Production LUT files. */
function fromNotion(camera, files, title = "Halcyon") {
  const front = tidy({ ...emptyFront(), title, camera: { ...emptyFront().camera, ...camera }, camera_files: files, camera_notes: 2 });
  return front;
}

const TREE = [{ t: "h2", r: [{ s: "Prep Notes" }] }, { t: "li", r: [{ s: "A-CAM handheld, B-CAM on the Eye Direct" }] }];

const draw = (front, tree = null) => recordBody(BASE, front.title || "Halcyon", "editor", "owner@example.com", front, "camera", false, tree, false);
const rowOf = (html, cls) => {
  const i = html.indexOf(`class="specrow ${cls}`);
  if (i < 0) return "";
  return html.slice(i, html.indexOf("</dd>", i));
};
const pages = {};

// ---- aspect ratio, finishing resolutions, close focus (2026-10-15) -----------
console.log("\nAspect Ratio, Finishing Resolutions, close focus");
{
  const sheet = halcyonSheet({ frames: [{ name: "Main", ratio: "1.85:1", main: true }, { name: "Social", ratio: "9:16" }],
    finishing_resolutions: [{ title: "Master", resolution: "4096 x 2160", note: "DCI 4K for the grade" }, { title: "Social", resolution: "1080 x 1920", note: "" }] });
  const front = tidy({ ...emptyFront(), title: "Halcyon" });
  laySheets(front, { spec_project: { sheet, v: 1 } }, (l) => (l.name === "Master Prime 25mm" ? "CF 0.35 m" : ""));
  const html = draw(front);
  pages["record-ratios-finishing"] = html;
  const order = [...html.matchAll(/<div class="blockhead">([^<]+)<\/div>|<dt>([^<]+)<\/dt>/g)].map((m) => (m[1] ? `# ${m[1]}` : m[2]));
  check("the groups and rows in order of operation", JSON.stringify(order) === JSON.stringify(["# Camera", "Camera", "Shooting Format", "Capture Resolution", "Lenses", "Desqueeze", "Aspect Ratio", "Frame Rate", "Codec", "# Color", "LUTs", "Color Space", "# Deliverables", "Finishing Resolutions", "Notes"]), order.join(" | "));
  const ar = html.slice(html.indexOf("<dt>Aspect Ratio</dt>"), html.indexOf("</dd>", html.indexOf("<dt>Aspect Ratio</dt>")));
  check("Aspect Ratio: each by name and ratio, Main first, no resolution", ar.includes("Main 1.85:1") && ar.includes("Social 9:16") && ar.indexOf("Main") < ar.indexOf("Social") && !/\d{3,4} x \d{3,4}/.test(ar), ar);
  check("…and there is no Frame Guides or Finishing Resolution box of a camera's", !html.includes("<dt>Frame Guides</dt>") && !html.includes("<dt>Finishing Resolution</dt>"));
  const fin = rowOf(html, "finrow");
  check("Finishing Resolutions: title, resolution, note", fin.includes("<b>Master</b><span>4096 x 2160</span><i>DCI 4K for the grade</i>") && fin.includes("<b>Social</b><span>1080 x 1920</span>") && !fin.includes("<i></i>"), fin);
  check("…copies as lines", fin.includes('data-copy="Master · 4096 x 2160 · DCI 4K for the grade\nSocial · 1080 x 1920"'), fin.slice(0, 200));
  const lenses = html.slice(html.indexOf("<dt>Lenses</dt>"), html.indexOf("</dd>", html.indexOf("<dt>Lenses</dt>")));
  check("a lens with a close focus shows it; one without shows nothing", lenses.includes('<i class="npcf">CF 0.35 m</i>') && (lenses.match(/npcf/g) || []).length === 1, lenses);
  const plain = draw(fromRecord(halcyonSheet()));
  check("a sheet with neither list: no Finishing Resolutions row and no Aspect Ratio row", !plain.includes("finrow") && !plain.includes("<dt>Aspect Ratio</dt>") && !plain.includes("npcf"));
}

// ---- the record, two cameras -------------------------------------------------
console.log("\nThe record's sheet, two cameras");
{
  const html = draw(fromRecord(halcyonSheet()));
  pages["record-two-cameras"] = html;
  const luts = rowOf(html, "lutrow");
  check("LUTs are a row of the sheet's table, under Color", html.includes('<dl class="spec">') && /<dt>LUTs<\/dt>/.test(luts) && html.indexOf('<div class="blockhead">Color</div>') < html.indexOf("lutrow") && html.indexOf("lutrow") < html.indexOf("</dl>", html.indexOf("lutrow")), luts.slice(0, 200));
  check("three groups in order of operation: Camera, Color, Deliverables, then Notes", ["Camera", "Color"].every((h) => html.includes(`<div class="blockhead">${h}</div>`)) && html.indexOf('<div class="blockhead">Camera</div>') < html.indexOf('<div class="blockhead">Color</div>') && html.indexOf('<div class="blockhead">Color</div>') < html.indexOf("noterow"));
  const order = [...html.matchAll(/<div class="blockhead">([^<]+)<\/div>|<dt>([^<]+)<\/dt>/g)].map((m) => (m[1] ? `# ${m[1]}` : m[2]));
  check("…every row in its group", order.indexOf("Lenses") < order.indexOf("# Color") && order.indexOf("Codec") < order.indexOf("# Color") && order.indexOf("Color Space") > order.indexOf("# Color") && order.indexOf("Notes") === order.length - 1, order.join(" | "));
  check("…a column per camera, A Cam's under A Cam", /<ul class="camcols lutcols" style="--cams:2"><li><span class="luts"><span class="lut"><a class="lutf" href="https:\/\/drive.google.com\/file\/d\/aaa\/view"[^>]*>halcyon-spicy-logc3.aml<\/a><\/span><\/span><\/li><li><span class="luts"><span class="lut"><a class="lutf" href="https:\/\/drive.google.com\/file\/d\/bbb\/view"[^>]*>halcyon-spicy-slog3.cube<\/a>/.test(luts), luts);
  check("…and the old Files cards are gone for LUTs", !html.includes('<div class="blockhead">Files</div>'), "a Files block");
  check("…the row copies each camera's LUT", luts.includes(`data-copy="A Cam: ${LUT_A} https://drive.google.com/file/d/aaa/view\nB Cam: ${LUT_B}`), luts.slice(0, 220));
  const notes = rowOf(html, "noterow");
  check("Notes is the sheet's last row", /<dt>Notes<\/dt>/.test(notes) && html.indexOf("noterow") > html.indexOf("lutrow") && html.indexOf('<dl class="spec specnotesblock">') < html.indexOf("noterow") && html.lastIndexOf("specrow") <= html.indexOf("noterow"), notes.slice(0, 200));
  check("…his words, line breaks kept", notes.includes('<span class="specnotes">Canon 8-64mm from Keslow, rehoused\nB Cam on the Eye Direct</span>'), notes);
  check("…and the row copies them", notes.includes('data-copy="Canon 8-64mm from Keslow, rehoused\nB Cam on the Eye Direct"'), notes.slice(0, 200));
}

// ---- the record, one LUT on both --------------------------------------------
console.log("\nThe record's sheet, the same LUT on both cameras");
{
  const shared = { label: "", name: "halcyon-show.cube", url: "https://drive.google.com/file/d/sss/view" };
  const sheet = halcyonSheet();
  sheet.cameras.forEach((c) => { c.luts = [shared]; });
  const html = draw(fromRecord(sheet));
  const luts = rowOf(html, "lutrow");
  check("drawn once across the row", !luts.includes("camcols") && (luts.match(/halcyon-show\.cube<\/a>/g) || []).length === 1, luts);
}

// ---- the record, held files --------------------------------------------------
console.log("\nThe record's sheet, a LUT Notion keeps itself");
{
  const sheet = halcyonSheet();
  sheet.cameras[1].luts = [{ label: "", name: LUT_B, url: "", held: true }];
  const front = fromRecord(sheet);
  const html = draw(front);
  pages["record-held"] = html;
  const luts = rowOf(html, "lutrow");
  check("held, no copy: its name and File in Notion, no link", luts.includes(`<span class="lutf" title="${LUT_B}">${LUT_B}</span><small>File in Notion</small>`), luts);
  check("…still under B Cam", /<li>.*logc3.*<\/li><li>.*slog3/.test(luts), luts);
  const phone = phoneFrontOf(front, [front]);
  const files = ((phone.views || phone)[0] || phone).camera ? ((phone.views || [phone])[0].camera.files || []) : [];
  check("the phone's list leaves a file it cannot open out", !JSON.stringify(phone).includes(LUT_B) || files.every((f) => f.url || f.file), JSON.stringify(files));

  // a copy the card already holds: a link to it, still marked held
  const card = tidy({ ...emptyFront(), title: "Halcyon", camera_files: [{ name: LUT_B, file: HELD, bytes: 12 }] });
  laySheets(card, { spec_project: { sheet, v: 1 } });
  const html2 = draw(card);
  const luts2 = rowOf(html2, "lutrow");
  check("held, with the hub's copy: a link to it and File in Notion", luts2.includes(`<a class="lutf" href="${BASE}/file/${LUT_B}"`) && luts2.includes(`>${LUT_B}</a><small>File in Notion</small>`), luts2);
}

// ---- the record, a file that is not a LUT -----------------------------------
console.log("\nThe record's sheet, a camera report beside the LUTs");
{
  const html = draw(fromRecord(halcyonSheet({ files: [{ name: "Camera report.pdf", url: "https://drive.google.com/file/d/rrr/view" }] })));
  const luts = rowOf(html, "lutrow");
  check("not in the LUTs row", !luts.includes("Camera report"), luts);
  check("…but under Files", html.includes('<div class="blockhead">Files</div>') && html.includes(">Camera report.pdf</b>"), "no Files card");
}

// ---- the record, one camera ---------------------------------------------------
console.log("\nThe record's sheet, one camera");
{
  const html = draw(fromRecord(oneCameraSheet(), "Call Her Back"));
  pages["record-one-camera"] = html;
  const luts = rowOf(html, "lutrow");
  check("one cell, no columns", luts && !luts.includes("camcols"), luts);
  check("…the LUT's own label beside its file", luts.includes('<span class="lut"><i>Show LUT</i><a class="lutf"') && luts.includes(">chb-show.cube</a>"), luts);
  check("…Notes as typed", rowOf(html, "noterow").includes('<span class="specnotes">Rehoused, Keslow</span>'), rowOf(html, "noterow"));
  const none = draw(fromRecord(oneCameraSheet({ notes: "" }), "Call Her Back"));
  check("no notes, no Notes row", !none.includes("noterow"), "a Notes row");
}

// ---- a card Notion wrote, two cameras ---------------------------------------
console.log("\nA card Notion wrote, two cameras");
{
  const front = fromNotion({
    body: "A Cam: Arri Alexa Mini\nB Cam: Sony FX6", codec: "A Cam: ProRes 4444\nB Cam: XAVC-I", fps: "23.976",
    luts: `A Cam: ${LUT_A}\nB Cam: ${LUT_B}`,
  }, [{ name: LUT_A, file: HELD, bytes: 900 }, { name: LUT_B, url: "https://drive.google.com/file/d/bbb/view" }]);
  const html = draw(front, TREE);
  pages["notion-two-cameras"] = html;
  const luts = rowOf(html, "lutrow");
  check("by LUT Labels: a column per camera", luts.includes('class="camcols lutcols" style="--cams:2"') && /<li>.*logc3\.aml.*<\/li><li>.*slog3\.cube/.test(luts), luts);
  check("…the file Notion keeps says so", /logc3\.aml<\/a><small>File in Notion<\/small>/.test(luts), luts);
  check("…a Drive link does not", /slog3\.cube<\/a><\/span>/.test(luts), luts);
  const notes = rowOf(html, "noterow tree");
  check("the sheet's Notion page is the Notes row", notes.includes("<dt>Notes</dt>") && notes.includes("Prep Notes") && html.indexOf("noterow") < html.indexOf("</dl>", html.indexOf("noterow")), notes.slice(0, 200));
  check("…and that row does not pretend to copy", !notes.includes("data-copy"), notes.slice(0, 120));
}

// ---- a card Notion wrote, one camera, no labels -----------------------------
console.log("\nA card Notion wrote, one camera, no labels");
{
  const front = fromNotion({ body: "Arri Alexa Mini", codec: "ProRes 4444", luts: "" },
    [{ name: "Production LUT", url: "https://drive.google.com/file/d/abc/view" }], "Call Her Back");
  const html = draw(front, TREE);
  pages["notion-one-camera"] = html;
  const luts = rowOf(html, "lutrow");
  check("one chip, no label, no columns", luts.includes('<span class="lut"><a class="lutf" href="https://drive.google.com/file/d/abc/view"') && !luts.includes("camcols"), luts);
  const label = draw(fromNotion({ body: "A Cam: Alexa 35\nB Cam: FX3", luts: "Night: https://drive.google.com/file/d/abc/view" },
    [{ name: "Production LUT", url: "https://drive.google.com/file/d/abc/view" }]));
  check("a label naming no camera: across, labelled", rowOf(label, "lutrow").includes("<i>Night</i>") && !rowOf(label, "lutrow").includes("camcols"), rowOf(label, "lutrow"));
  const bare = draw(fromNotion({ body: "", luts: "" }, [{ name: "show.cube", url: "https://drive.google.com/file/d/x/view" }]), TREE);
  check("nothing typed but a LUT and notes: still the table", bare.includes('<dl class="spec">') && bare.includes("lutrow") && bare.includes("noterow"), "no table");
}

// ---- frame guide files on an aspect ratio (2026-10-15) -----------------------
console.log("\nFrame guide files under their aspect ratio");
{
  const sheet = halcyonSheet({ frames: [
    { name: "Main", ratio: "2.39:1", main: true, guides: [
      { name: "ARRI 2.39.xml", camera: "A Cam", note: "", file: "3-post/frame-line/arri-2.39.xml", url: "https://drive.google.com/uc?export=download&id=g1" },
      { name: "FX6 2.39.png", camera: "B Cam", note: "overlay", file: "3-post/frame-line/fx6.png", url: "https://drive.google.com/uc?export=download&id=g2" },
      { name: "Waiting.xml", camera: "", note: "", file: "3-post/frame-line/waiting.xml", url: "" }] },
    { name: "Social", ratio: "9:16" }] });
  const html = draw(fromRecord(sheet));
  pages["record-frame-guides"] = html;
  const ar = html.slice(html.indexOf("<dt>Aspect Ratio</dt>"), html.indexOf("</dd>", html.indexOf("<dt>Aspect Ratio</dt>")) + 5);
  check("each ratio is a pill, its files under it as download links", ar.includes("Main 2.39:1") && ar.includes('href="https://drive.google.com/uc?export=download&amp;id=g1"') && ar.includes(" download "), ar);
  check("a file shows its camera before it, its note after", ar.includes("<i>A Cam</i>") && ar.includes("<small>overlay</small>"), ar);
  check("a file Drive has not linked yet says Uploading, with no link", ar.includes("Uploading") && !ar.includes("Waiting.xml</a>"), ar);
  check("Social, with no files, is a pill and nothing more", ar.includes("Social 9:16") && ar.split("ratioguides").length === 3, ar);
  check("the row copies each ratio and its files", html.includes('data-copy="Main 2.39:1\n  A Cam: ARRI 2.39.xml https://drive.google.com/uc?export=download&amp;id=g1'), "");
  const plain = draw(fromRecord(halcyonSheet({ frames: [{ name: "Main", ratio: "1.85:1", main: true }] })));
  check("a sheet with no files draws the Aspect Ratio row as before", !plain.includes("ratioguides") && plain.includes("Main 1.85:1"));
  const bare = draw(fromRecord(halcyonSheet({ frames: [{ name: "Main", ratio: "", main: true, guides: [{ name: "a.xml", file: "x/a.xml", url: "https://drive.google.com/uc?export=download&id=z" }] }] })));
  check("a file with no ratio yet sits under Main", bare.includes("<dt>Aspect Ratio</dt>") && bare.includes("a.xml") && bare.includes("ratioguides"), "");
  // the phone's view carries them flat, for the app to list and download
  const front = fromRecord(sheet);
  const phone = phoneFrontOf(front, [front]);
  const ratioRow = ((phone.views || [phone])[0].camera.rows || []).find((r) => r.label === "Aspect Ratio");
  check("the phone's Aspect Ratio row carries the files, each with ratio, camera and link", ratioRow && ratioRow.guides.length === 3 && ratioRow.guides[0].ratio === "Main" && ratioRow.guides[0].camera === "A Cam" && ratioRow.guides[0].url.endsWith("id=g1") && ratioRow.guides[2].url === "", JSON.stringify(ratioRow));
}

if (OUT) {
  mkdirSync(OUT, { recursive: true });
  // the portal's own stylesheets, by the addresses the worker gives them:
  // serve DIR with hub/public's files beside the pages to photograph them
  const css = ["hub.css", "front.css", "feel.css", "side.css"].map((f) => `<link rel="stylesheet" href="/${f}">`).join("\n");
  for (const [name, body] of Object.entries(pages)) {
    writeFileSync(join(OUT, `${name}.html`), `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>html{background:#0A0A0A}</style>${css}</head><body>${body}</body></html>`);
  }
  console.log(`\n  pages written to ${OUT}`);
}

console.log(`\npassed ${pass}, failed ${fail}`);
process.exit(fail ? 1 : 0);
