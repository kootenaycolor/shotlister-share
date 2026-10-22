/**
 * **Studio's Export, on the server** (2026-10-17). His ask: *"make sure that
 * the export engine for Studio is available to the server and the MCP, so
 * that an MCP can remotely export a file from anywhere and upload it to Google
 * Drive via the server."*
 *
 * So the connector's `export` makes the file Studio's Export window makes —
 * the same engine pages, the same Auto layout, the same Order and Days rules,
 * the same presets (`s/export-presets.json`, synced Mac ↔ iPhone) and the
 * same file names — and files it in the project's Google Drive folder, in
 * `1-creative/shot-list/exports/` (his answer, 2026-10-17; the folder his other
 * exports already use). Nothing on his
 * Mac takes part.
 *
 * **How a PDF is made, and why this way.** Studio does not print its pages:
 * `studio/Sources/Printing.swift` lays each engine page out in a web view at
 * the sheet's printable width, asks the page where its rows are
 * (`blockBoundsScript`), decides where each sheet starts (`pageBreaks`) so no
 * row is cut in two, cuts the long page into those slices, puts each on
 * Letter with the view's margin, then stamps the footer (when it was made,
 * Page N of M) over the whole file. This file does the same with Cloudflare's
 * Chrome: the same script, the same cut, the same margins and footer. The
 * slices are made by laying a copy of the page in a clipped box per sheet,
 * offset to where that sheet starts — what WebKit's `createPDF(rect)` does on
 * the Mac. **If `Printing.swift`'s cutting changes, this has to.**
 *
 * **Add-only on Drive**: a name already in the folder gets `_v2`, `_v3`, the
 * way Studio's own save does (`FileNames.unused`). Nothing is replaced,
 * moved or deleted.
 *
 * What a server cannot do, said rather than missed: the Mac's live Table (its
 * search, facets and sort) is not here, so "As in Table" is script order and
 * the Table's filter is never applied; clips print as their poster, not the
 * four-moment strip the Mac bakes; the Diagram page and the imported Script's
 * own pages export from Studio on the Mac.
 */
import puppeteer from "@cloudflare/puppeteer";
import { PDFDocument } from "pdf-lib";
import { keys } from "../../relay/layout.js";
import { readPresets } from "./exportpresets.js";
import { findHome } from "./drivecopies.js";
import { copiesDrive, projectOf } from "./drivecopiesdoor.js";
import interFont from "./fonts/inter-latin-wght.bin";
import { ZONE, MARGIN, paperOf, BLOCKS_SCRIPT, parseBlocks, pageBreaks, spansOf, stampOf, todayOf, slug, plain, autoName, typedName, unusedStem, askFrom } from "./exportplan.js";
export { ZONE, MARGIN, paperOf, BLOCKS_SCRIPT, parseBlocks, pageBreaks, spansOf, stampOf, todayOf, slug, plain, autoName, typedName, unusedStem, askFrom };

const LIMIT_MS = 90_000;

// ── Chrome ───────────────────────────────────────────────────────────────────

/**
 * **The Mac's typeface, as near as a server can come.** The pages ask for
 * `-apple-system` (San Francisco), which only a Mac has; Cloudflare's Chrome
 * fell through to a narrower face, so every cell wrapped later and the cut
 * fell elsewhere (ZED: 13 sheets against the Mac's 14). Inter (SIL Open Font
 * License, `fonts/INTER-LICENSE.txt`) is drawn to San Francisco's
 * proportions; it is given the name the pages list third, "Segoe UI", which
 * no Linux Chrome has, so it is picked before anything installed. **Drawn
 * 3% larger** (`size-adjust`): San Francisco at the small sizes these pages
 * use is wider than Inter (ZED's sheet: "Signature" 46.5 against 44.3
 * points), and widths decide where a line wraps and so where a sheet ends.
 * 3% put 13 of ZED's 14 sheet breaks on the same row as the Mac's (5% and
 * 4% gave 15 sheets; 2.5–3.5% all gave 13 of 14).
 */
let FACES = "";
function faces() {
  if (FACES) return FACES;
  const bytes = new Uint8Array(interFont);
  let raw = "";
  for (let i = 0; i < bytes.length; i += 0x8000) raw += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  FACES = `@font-face { font-family: "Segoe UI"; src: url(data:font/woff2;base64,${btoa(raw)}) format("woff2"); font-weight: 100 900; font-style: normal; size-adjust: 103%; }`;
  return FACES;
}

/** The page as the press lays it: the Mac's face in, pictures fetched with the press key. */
export function forPress(html) {
  const face = `<style>${faces()}</style>`;
  const withFace = /<head>/i.test(html) ? html.replace(/<head>/i, `<head>${face}`) : face + html;
  return withFace.replace(/<img\s/g, '<img crossorigin="anonymous" ');
}

const READY = async () => {
  await (document.fonts ? document.fonts.ready : 0);
  await Promise.all(Array.from(document.images).map((i) => (i.complete ? 0
    : new Promise((r) => { i.onload = r; i.onerror = r; }))));
  void document.body.offsetHeight;
  return document.images.length;
};

/**
 * **Every picture at the size it prints, twice over** — 144 pixels an inch,
 * what WebKit writes on the Mac. Chrome passes the portal's picture through
 * whole (1600 wide for a 2-inch frame), which made ZED's export twice the
 * Mac's size and Call Her Back's 54 MB. Re-drawn whole, at its own shape, so
 * nothing moves; a picture the canvas may not read prints as it was.
 */
function shrinkPictures(scale) {
  for (const img of Array.from(document.images)) {
    const box = img.getBoundingClientRect();
    if (!box.width || !box.height || !img.naturalWidth || !img.naturalHeight) continue;
    const w = Math.max(1, Math.round(box.width * scale));
    const h = Math.max(1, Math.round(box.height * scale));
    if (w >= img.naturalWidth || h >= img.naturalHeight) continue;
    const canvas = document.createElement("canvas");
    canvas.width = w;
    canvas.height = h;
    try {
      const pen = canvas.getContext("2d");
      pen.imageSmoothingQuality = "high";
      pen.drawImage(img, 0, 0, w, h);
      img.src = canvas.toDataURL("image/jpeg", 0.88);
    } catch (_) { /* tainted: left as it was */ }
  }
}

/** The page cut into sheets, in place: each sheet a Letter page with the view's margin and the footer. */
function lay({ spans, width, paper, margin, first, total, stamped }) {
  const body = document.body;
  // Where every picture sits on the long page, before it is cut: a sheet
  // keeps only the pictures it shows, or Chrome writes every picture of the
  // page into every sheet (one came out at twice the Mac's size, a long film
  // at 54 MB).
  const pics = Array.from(document.images).map((img) => {
    const r = img.getBoundingClientRect();
    return [r.top + window.scrollY, r.bottom + window.scrollY];
  });
  const flow = document.createElement("div");
  while (body.firstChild) flow.appendChild(body.firstChild);
  flow.className = "__flow";
  const style = document.createElement("style");
  style.textContent = `@page { size: ${paper[0] / 72}in ${paper[1] / 72}in; margin: 0 }
html, body { margin: 0 !important; padding: 0 !important; background: #fff !important; }
.__sheet * { break-before: auto !important; break-after: auto !important; page-break-before: auto !important; page-break-after: auto !important; }
.__sheet { position: relative; width: ${paper[0]}px; height: ${paper[1]}px; overflow: hidden; background: #fff; break-after: page; page-break-after: always; }
.__sheet:last-child { break-after: auto; page-break-after: auto; }
.__clip { position: absolute; left: ${margin}px; top: ${margin}px; width: ${width}px; overflow: hidden; }
.__flow { position: absolute; left: 0; width: ${width}px; margin: 0; }
.__foot { position: absolute; left: 24px; right: 24px; bottom: 25px; display: flex; justify-content: space-between;
  font: 8px/10px "Segoe UI", Helvetica, Arial, sans-serif; color: #555; white-space: nowrap; }`;
  document.head.appendChild(style);
  spans.forEach((span, i) => {
    const sheet = document.createElement("div");
    sheet.className = "__sheet";
    const clip = document.createElement("div");
    clip.className = "__clip";
    clip.style.height = `${span.h}px`;
    const copy = i === spans.length - 1 ? flow : flow.cloneNode(true);
    copy.style.top = `${-span.y}px`;
    copy.querySelectorAll("img").forEach((img, at) => {
      const [top, bottom] = pics[at] || [0, 0];
      if (bottom <= span.y || top >= span.y + span.h) img.style.visibility = "hidden";
    });
    clip.appendChild(copy);
    sheet.appendChild(clip);
    const foot = document.createElement("div");
    foot.className = "__foot";
    const left = document.createElement("span");
    left.textContent = stamped;
    const right = document.createElement("span");
    right.textContent = `Page ${first + i} of ${total}`;
    foot.append(left, right);
    sheet.appendChild(foot);
    body.appendChild(sheet);
  });
}

/**
 * Every file's pages as PDFs: `files` is `[{jobs: [{section, orientation,
 * html}]}]`; answers `[{bytes, pages}]` in the same order. One Chrome for
 * all of them, one tab a page.
 */
export async function renderFiles(env, project, files, { stamped = stampOf(), host = env.PRESS_HOST } = {}) {
  const key = crypto.randomUUID();
  const keyAt = keys.press(project, key);
  await env.BUCKET.put(keyAt, JSON.stringify({ until: Date.now() + 10 * 60_000 }), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  const out = [];
  const browser = await puppeteer.launch(env.BROWSER, { keep_alive: 120_000 });
  try {
    for (const file of files) {
      const laid = [];
      for (const job of file.jobs || []) {
        const margin = MARGIN[job.section] || 32;
        const paper = paperOf(job.orientation);
        const width = paper[0] - margin * 2;
        const height = paper[1] - margin * 2;
        const page = await browser.newPage();
        page.setDefaultTimeout(LIMIT_MS);
        await page.setViewport({ width: Math.round(width), height: Math.round(height), deviceScaleFactor: 1 });
        await page.emulateMediaType("screen");
        await page.setExtraHTTPHeaders({ "x-press": key });
        const html = forPress(String(job.html || ""));
        await page.setContent(html, { waitUntil: "networkidle0", timeout: LIMIT_MS });
        await page.evaluate(READY);
        await page.evaluate(shrinkPictures, 2);
        await page.evaluate(READY);
        const tall = Math.max(1, Number(await page.evaluate(() => document.body.scrollHeight)) || 1);
        const blocks = parseBlocks(await page.evaluate(BLOCKS_SCRIPT));
        const spans = spansOf(pageBreaks(blocks, height), tall, height);
        laid.push({ page, spans, paper, margin, width });
      }
      const total = laid.reduce((n, l) => n + l.spans.length, 0);
      const merged = await PDFDocument.create();
      let first = 1;
      for (const l of laid) {
        if (!l.spans.length) { await l.page.close(); continue; }
        await l.page.evaluate(lay, { spans: l.spans, width: l.width, paper: l.paper, margin: l.margin, first, total, stamped });
        await l.page.evaluate(READY);
        const pdf = await l.page.pdf({
          width: `${l.paper[0] / 72}in`, height: `${l.paper[1] / 72}in`, printBackground: true, preferCSSPageSize: true,
          scale: 96 / 72, margin: { top: 0, right: 0, bottom: 0, left: 0 }, timeout: LIMIT_MS,
        });
        await l.page.close();
        const part = await PDFDocument.load(pdf instanceof Uint8Array ? pdf : new Uint8Array(pdf));
        // A sheet that rounds over its page makes a blank one after it; only the sheets are kept.
        const want = part.getPageIndices().slice(0, l.spans.length);
        for (const sheet of await merged.copyPages(part, want)) merged.addPage(sheet);
        first += l.spans.length;
      }
      if (!merged.getPageCount()) throw new Error("nothing was drawn");
      merged.setProducer("Studio");
      merged.setCreator("Studio");
      out.push({ bytes: await merged.save(), pages: merged.getPageCount() });
    }
  } finally {
    await browser.close().catch(() => {});
    await env.BUCKET.delete(keyAt).catch(() => {});
  }
  return out;
}

// ── the tool ─────────────────────────────────────────────────────────────────

export const EXPORT_TOOL = {
  name: "export",
  description:
    "Export the open project the way Studio's Export window does, and file it in the project's Google Drive folder (1-creative/shot-list/exports/, found if it is there, made only if missing). Works from anywhere; no Mac needed. Answers the Drive link, the Drive folder, and a portal download link.\n\n"
    + "WHAT — `format`: pdf (default), xlsx (his working spreadsheet: Master Shot List, Group by Day, Group by Sequence, Ranges; no pictures) or csv. A PDF holds `pages`: any of table (the shot list), storyboard, document, avscript, always in that order, each on its own paper (table and storyboard landscape, document portrait unless `looks` says otherwise).\n\n"
    + "PRESETS — `preset`: one of his saved export presets by name (the Presets menu in Studio's Export window, the same list on the Mac and iPhone; e.g. \"AC Sheet: Day by Day\", \"Client: Script Order\", \"Tomorrow\"). Anything else given overrides the preset. Without a preset: the shot list, Auto layout, script order, every day, one file.\n\n"
    + "ORDER AND DAYS — `order`: script (story order, scene by scene) or schedule (shooting order, day by day, each day starting a new page, unscheduled last). `days` (schedule only): all, next (the next day not wrapped, on his clock), this week, next week, shoot 2, a range like 12-18, or day numbers like 3,5,9; add \"+ unscheduled\" to include the unscheduled. `output`: one (a single file) or perday (a folder with one PDF per day). `scenes`: scene numbers, to export only those scenes.\n\n"
    + "LAYOUT — `auto` (default true) lays the table out as Studio's Auto does; `size` (0.7–1.3, Auto's Size) and `paper` (auto, landscape, portrait) steer it. `looks` sets each page's dials when not on Auto: {table: {orientation, scale, frames: small|medium|large}, …}. `columns` names the table's columns exactly; `columns_except` drops some from the project's own.\n\n"
    + "NAME — files are named as Studio names them: project-pages-order-YYYYMMDD (e.g. lets-bake-shot-list-schedule-order-20261017.pdf). `name` keeps his own name exactly. A name already in the folder gets _v2. Nothing in Drive is replaced or deleted. `workbook: true` also files the spreadsheet beside a PDF.\n\n"
    + "Not here: the Mac's live Table filter and sort (As in Table exports in script order), flat PDFs and PNGs, the Diagram page, clips' four-moment strips (a clip prints as its poster).",
  inputSchema: {
    type: "object",
    properties: {
      preset: { type: "string", description: "One of his saved export presets, by name." },
      format: { type: "string", description: "pdf (default), xlsx or csv." },
      pages: { type: "array", items: { type: "string" }, description: "table, storyboard, document, avscript. Default: the preset's, else table." },
      order: { type: "string", description: "script or schedule." },
      days: { type: "string", description: "Schedule only: all, next, this week, next week, shoot 2, 12-18, 3,5,9; \"+ unscheduled\" to add the unscheduled." },
      output: { type: "string", description: "one or perday." },
      scenes: { type: "array", items: { type: "string" }, description: "Only these scene numbers." },
      auto: { type: "boolean", description: "Auto layout for the table (default true)." },
      size: { type: "number", description: "Auto's Size, 0.7–1.3 (1 is 100%)." },
      paper: { type: "string", description: "Auto's paper: auto, landscape or portrait." },
      looks: { type: "object", description: "Per page, when not on Auto: {orientation, scale, frames}." },
      columns: { type: "array", items: { type: "string" }, description: "The table's columns, exactly, by field name." },
      columns_except: { type: "array", items: { type: "string" }, description: "The project's columns but these." },
      name: { type: "string", description: "His own file name, kept exactly." },
      workbook: { type: "boolean", description: "Also file the spreadsheet beside a PDF." },
    },
    required: [],
  },
};

const fileUrl = (id) => `https://drive.google.com/file/d/${id}/view`;
const folderUrl = (id) => `https://drive.google.com/drive/folders/${id}`;
const MIME = { pdf: "application/pdf", csv: "text/csv", xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" };

function bytesFromBase64(text) {
  const raw = atob(String(text || ""));
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i);
  return out;
}

/** Kept on the portal by its own contents, as every document there is; answers the download address. */
async function keepOnPortal(env, project, ext, bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const file = `${hash.slice(0, 32)}.${ext}`;
  await env.BUCKET.put(keys.doc(project, file), bytes, { httpMetadata: { contentType: MIME[ext] || "application/octet-stream" } });
  return `https://your-domain.example/f/${project}/pic/${file}`;
}

/**
 * `export`, for `mcp.js`: `run` asks the film's engine (the unlisted
 * `export_pages` / `export_sheet`), `refuse` makes an answer an AI reads.
 */
/** The folder inside `1-creative/shot-list/` that exports go in (the name his other projects already use). */
export const EXPORTS_FOLDER = "exports";

export async function exportTool(env, found, held, args, ctx, { run, refuse, now = new Date() }) {
  if (found.role !== "editor") throw refuse("Exporting into the project's Drive folder is for its editors.");
  const format = String(args.format || "pdf").toLowerCase().replace(/^\./, "");
  if (!["pdf", "xlsx", "csv", "excel", "spreadsheet"].includes(format)) throw refuse("`format` is pdf, xlsx or csv.");
  const ext = format === "pdf" ? "pdf" : format === "csv" ? "csv" : "xlsx";
  const { presets } = await readPresets(env);
  const asked = askFrom(args, presets);
  if (asked.why) throw refuse(asked.why);
  const { ask, notes } = asked;
  const today = todayOf(now);

  // ── what to file ──
  let made = [];            // [{stem?, words, bytes, ext}]
  let document = "shot-list";
  let order = "script-order";
  let scope = "";
  let perday = false;
  let daysSaid = "";
  if (ext === "pdf") {
    const said = JSON.parse(await run(env, found, held, { name: "export_pages", arguments: {
      pages: ask.pages, arrange: ask.arrange, days: ask.days, output: ask.output, scenes: ask.scenes,
      columns: ask.columns, columns_except: ask.columns_except, auto: ask.auto, size: ask.size, paper: ask.paper,
      looks: ask.looks, widths: ask.widths, today: today.iso, base: `${env.PRESS_HOST}/f/${found.project}/pic`,
    } }, ctx));
    ({ document, order, scope, perday } = said);
    daysSaid = said.days || "";
    const rendered = await renderFiles(env, found.project, said.files, { stamped: stampOf(now) });
    made = said.files.map((f, i) => ({ words: f.order, day: f.day || "", bytes: rendered[i].bytes, pages: rendered[i].pages, ext: "pdf" }));
  }
  if (ext !== "pdf" || ask.workbook) {
    const sheet = JSON.parse(await run(env, found, held, { name: "export_sheet", arguments: {
      format: ext === "csv" ? "csv" : "xlsx", arrange: ask.arrange, scenes: ask.scenes, columns: ask.columns, columns_except: ask.columns_except,
    } }, ctx));
    const bytes = bytesFromBase64(sheet.base64);
    if (ext !== "pdf") { order = sheet.order; document = sheet.document; }
    if (!perday) made.push({ words: order, bytes, ext: sheet.ext, sheet: true });
    else notes.push("The spreadsheet is filed with one-file exports only.");
  }

  // ── where it goes ──
  const project = await projectOf(env, found.id || found.project);
  const drive = copiesDrive(env);
  let root = null;
  if (project && project.drive && drive) root = await drive.get(project.drive).catch(() => null);
  const projectWords = plain(root && root.name ? root.name : found.title) || plain(found.title);
  const stemOf = () => {
    if (ask.name) return typedName(ask.name, ext === "pdf" ? "pdf" : ext);
    if (ask.pattern) return ask.pattern.replace(/\{project\}/g, projectWords).replace(/\{date\}/g, today.compact);
    return autoName({ project: projectWords, document, scope, order, date: today.compact });
  };
  const stem = stemOf();

  // Kept on the portal whatever happens to Drive, so the work is never lost.
  for (const m of made) m.portal = await keepOnPortal(env, found.project, m.ext, m.bytes);

  const answer = { project: found.title, format: ext, pages: ask.pages, order: ask.arrange, files: [], notes };
  if (daysSaid && (ask.arrange === "schedule" || perday)) answer.days = daysSaid;
  if (!drive) {
    notes.push("The portal has no Drive sign-in that can write, so nothing was filed in Drive; the portal links hold the files.");
  } else if (!project || !project.drive || !root || root.trashed) {
    notes.push("This project has no Drive Folder link on its record, so nothing was filed in Drive; the portal links hold the files. Set its Drive folder in Projects Console.");
  }
  const canFile = drive && root && !root.trashed;
  let home = null;
  if (canFile) {
    home = await findHome(drive, root.id, "shots", { make: true });
    answer.drive_folder = folderUrl(home.id);
    answer.drive_path = `${root.name}/${home.path}`;
    if (home.made && home.made.length) notes.push(`Made ${home.made.join(", ")} in the project's Drive folder.`);
    // exports/ inside shot-list: found by name (any case) or made once, never a second.
    const kids = await drive.list(home.id);
    const there = kids.find((k) => k.folder && !k.shortcut && k.name.toLowerCase() === EXPORTS_FOLDER);
    const exp = there || await drive.mkdir(home.id, EXPORTS_FOLDER);
    if (!there) notes.push(`Made ${home.path}/${EXPORTS_FOLDER} in the project's Drive folder.`);
    home = { id: exp.id, path: `${home.path}/${exp.name}`, made: [] };
    answer.drive_folder = folderUrl(home.id);
    answer.drive_path = `${root.name}/${home.path}`;
  }

  let parent = home ? home.id : "";
  if (perday) {
    // **File per Day**: a folder of its own, named as the one file would have been.
    const folderStem = stem;
    if (canFile) {
      const taken = new Set((await drive.list(parent)).map((k) => k.name.toLowerCase()));
      const name = unusedStem(folderStem, taken, [""]);
      const made2 = await drive.mkdir(parent, name);
      parent = made2.id;
      answer.drive_folder = folderUrl(made2.id);
      answer.drive_path += `/${name}`;
    }
  }
  const taken = canFile ? new Set((await drive.list(parent)).map((k) => k.name.toLowerCase())) : new Set();
  // One file and its spreadsheet share one stem, `_v2` for both when either is there.
  const shared = unusedStem(stem, taken, [...new Set(made.map((m) => m.ext))]);
  for (const m of made) {
    const name = perday
      ? `${unusedStem(autoName({ project: projectWords, document, scope: "", order: m.words, date: today.compact }), taken, [m.ext])}.${m.ext}`
      : `${shared}.${m.ext}`;
    const row = { name, portal: m.portal };
    if (m.pages) row.pages = m.pages;
    if (m.day) row.day = m.day;
    if (canFile) {
      const got = await drive.upload(parent, name, MIME[m.ext], m.bytes);
      row.drive = fileUrl(got.id);
      taken.add(name.toLowerCase());
    }
    answer.files.push(row);
  }
  if (!notes.length) delete answer.notes;
  return JSON.stringify(answer, null, 1);
}
