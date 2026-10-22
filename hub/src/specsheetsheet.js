/**
 * **The Camera Spec Sheet as a Google Sheet in the project's Drive folder**
 * (2026-10-15, his ask: "the camera spreadsheet as an auto-updating Google
 * Sheet, like we do for the shot list ... so there's always a backwards-
 * compatible way to get this information. Ideally it links to the files inside
 * the cells"). The rules; the Drive side (the switch, the clock, Google) is
 * `specsheetsheetdoor.js`.
 *
 * **A mirror, not a master.** The record's spec sheets (specsheet.js) are
 * where the sheet is edited. This turns them into a workbook — one tab for the
 * project's sheet, then one for each shoot that keeps its own — and the server
 * rewrites the Drive file whenever the words in it change. An edit made in the
 * Google Sheet is overwritten at the next change, the same as the shot list's
 * live sheet. The header says so.
 *
 * **Native Google Sheet, made without the Sheets API.** The Drive API turns an
 * uploaded .xlsx into a real Google Sheet when the upload names the Sheet type
 * (the same call, with the file's id, replaces the contents in place and keeps
 * the id and the link). So the workbook is written here as a plain .xlsx
 * (`xlsxOf`, no library: a few XML files in a zip) and Drive converts it. This
 * matters because the Google project behind the server's sign-in has the
 * Sheets API switched off; the Drive API, which the sign-in already has, is
 * enough. Hyperlinks, bold, fills, column widths and several tabs all survive
 * the conversion (checked on the real Drive, 2026-10-15).
 *
 * **Layout** (the app's order): Camera, Color, Deliverables, Notes. A tab is
 * eight columns wide, so every table sits under the same widths:
 *
 *   CAMERA        cameras (body, sensor mode, capture resolution, frame rate,
 *                 codec, desqueeze, sensor size); lenses (focal length,
 *                 T-stop, close focus, set); filters; modifiers
 *   COLOR         per camera: color space; one row per LUT, hyperlinked
 *   DELIVERABLES  aspect ratios with their frame guide files (hyperlinked);
 *                 finishing resolutions
 *   NOTES         the sheet's notes; its other files (hyperlinked)
 *
 * A link goes to the file in Drive (`driveLink`: any Drive address with a file
 * id becomes `drive.google.com/file/d/<id>/view`). A LUT Notion still holds
 * (no address yet) shows its name with "In Notion, not in Drive yet" beside it.
 */

import { framesOf, finishingOf, PROJECT_KEY } from "./specsheet.js";

export const HEADER_NOTE = "Updated automatically from Projects Console.";
export const COLUMNS = 8;
const WIDTHS = [34, 26, 24, 22, 16, 18, 16, 24];
const SHEET_TYPE = "application/vnd.google-apps.spreadsheet";
export { SHEET_TYPE };
export const XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
const bare = (id) => String(id || "").replace(/-/g, "").toLowerCase();

// ── links ───────────────────────────────────────────────────────────────────

/**
 * The address a cell links to: a Drive file's own address from any form of
 * link to it (`open?id=…`, `file/d/…/view?usp=sharing`), a folder or Docs
 * address as it is, anything else https as it is; "" when there is none.
 */
export function driveLink(url) {
  const u = squash(url);
  if (!/^https:\/\/\S+$/.test(u)) return "";
  if (!/^https:\/\/drive\.google\.com\//.test(u)) return u;
  if (/\/folders\//.test(u)) return u;
  const id = /\/file\/d\/([A-Za-z0-9_-]{10,})/.exec(u) || /[?&]id=([A-Za-z0-9_-]{10,})/.exec(u);
  return id ? `https://drive.google.com/file/d/${id[1]}/view` : u;
}

/** A name a person reads for a file: its own name, or "Drive link" for an address that was used as the name. */
function fileWords(file, fallback) {
  const name = squash(file && file.name);
  if (name && !/^https?:\/\//.test(name)) return name;
  const url = squash(file && file.url);
  if (/drive\.google|docs\.google/.test(url)) return fallback;
  return name || url || fallback;
}

// ── cells ───────────────────────────────────────────────────────────────────

const cell = (text, style = "body", link = "") => ({ text: String(text == null ? "" : text), style, ...(link ? { link } : {}) });
const blank = () => cell("", "blank");

/** A table row, padded to the sheet's width. */
function row(cells) {
  const out = cells.map((c) => (typeof c === "string" ? cell(c) : c));
  while (out.length < COLUMNS) out.push(blank());
  return out;
}
function band(text, style) {
  return row([cell(text, style), ...Array.from({ length: COLUMNS - 1 }, () => cell("", style))]);
}
const gap = () => row([]);

/** A table's header cells, then the row's remaining cells shaded as header too, so the band spans the tab. */
function headRow(...names) {
  const cells = names.map((n) => cell(n, "head"));
  while (cells.length < COLUMNS) cells.push(cell("", "head"));
  return cells;
}
const none = (text) => row([cell(text, "quiet")]);

// ── one sheet as rows ───────────────────────────────────────────────────────

const mm = (n) => (Number.isFinite(Number(n)) ? String(Math.round(Number(n) * 100) / 100) : "");
const sensorSize = (c) => (c.sensor && c.sensor.width && c.sensor.height ? `${mm(c.sensor.width)} × ${mm(c.sensor.height)} mm` : "");
const joined = (list) => (Array.isArray(list) ? list.join(" · ") : "");

/** A focal length as the sheet shows it: the library's ("25", "8-64") with mm, else the last "NNmm" in the lens's name. */
function focalText(lens, entry) {
  const said = squash(entry && entry.focal);
  if (said) return /mm$/i.test(said) ? said : `${said} mm`;
  const words = squash(lens.name).split(" ").filter((w) => /^\d+(?:\.\d+)?(?:-\d+(?:\.\d+)?)?mm$/i.test(w));
  return words.length ? words[words.length - 1].replace(/mm$/i, " mm") : "";
}

function lensRows(sheet, lib, lensEntry) {
  const out = [];
  for (const lens of sheet.lenses || []) {
    const entry = lib && lensEntry ? lensEntry(lib, lens) : null;
    const set = squash(lens.set) || (entry && entry.set && lib ? ((lib.sets || []).find((s) => s.id === entry.set) || {}).name : "") || "";
    const stop = squash(lens.stop) || squash(entry && entry.stop);
    const cf = squash(entry && entry.close_focus).replace(/^cf\s*/i, "");
    out.push(row([lens.name, focalText(lens, entry), stop, cf, set, lens.note || ""]));
  }
  return out;
}

/** The rows of one sheet: its sections, in the app's order. */
export function sheetRows({ sheet, fact, sheets, lib = null, lensEntry = null }) {
  const rows = [];
  // ── CAMERA
  rows.push(band("CAMERA", "section"));
  const cams = sheet.cameras || [];
  if (cams.length) {
    rows.push(headRow("Camera", "Body", "Sensor mode", "Capture resolution", "Frame rate", "Codec", "Desqueeze", "Sensor size"));
    for (const c of cams) rows.push(row([c.label, c.body, joined(c.format), joined(c.capture), joined(c.fps), joined(c.codec), joined(c.desqueeze), sensorSize(c)]));
  } else rows.push(none("No cameras listed."));
  rows.push(gap());
  if ((sheet.lenses || []).length) {
    rows.push(headRow("Lens", "Focal length", "T-stop", "Close focus", "Set", "Note"));
    rows.push(...lensRows(sheet, lib, lensEntry));
  } else rows.push(none("No lenses listed."));
  if ((sheet.filters || []).length) {
    rows.push(gap());
    rows.push(headRow("Filter", "Set", "Note"));
    for (const f of sheet.filters) rows.push(row([f.name, f.set || "", f.note || ""]));
  }
  if ((sheet.modifiers || []).length) {
    rows.push(gap());
    rows.push(headRow("Modifier", "Note"));
    for (const m of sheet.modifiers) rows.push(row([m.name, m.note || ""]));
  }
  rows.push(gap());

  // ── COLOR
  rows.push(band("COLOR", "section"));
  const colourRows = [];
  for (const c of cams) {
    const luts = c.luts || [];
    const space = joined(c.colour);
    if (!luts.length) {
      if (space) colourRows.push(row([c.label, space, cell("", "blank"), blank()]));
      continue;
    }
    luts.forEach((l, i) => {
      const link = driveLink(l.url);
      const words = fileWords(l, "LUT");
      const where = link ? "" : l.held || !l.url ? "In Notion, not in Drive yet" : "";
      colourRows.push(row([c.label, i === 0 ? space : "", link ? cell(words, "link", link) : cell(words), cell(where, "quiet")]));
    });
  }
  if (colourRows.length) {
    rows.push(headRow("Camera", "Color space", "LUT", ""));
    rows.push(...colourRows);
  } else rows.push(none("No color space or LUTs listed."));
  rows.push(gap());

  // ── DELIVERABLES
  rows.push(band("DELIVERABLES", "section"));
  const frames = framesOf(sheet).filter((f) => f.ratio || (f.guides || []).length);
  if (frames.length) {
    const ordered = [...frames.filter((f) => f.main), ...frames.filter((f) => !f.main)];
    rows.push(headRow("Aspect ratio", "Ratio", "Main", "Frame guide file", "Camera", "Note"));
    for (const f of ordered) {
      const guides = f.guides || [];
      const first = (g) => {
        const link = g ? driveLink(g.url) : "";
        const words = g ? (squash(g.name) || (g.file ? g.file.split("/").pop() : "Frame guide")) : "";
        return [g ? (link ? cell(words, "link", link) : cell(words)) : blank(), g ? g.camera || "" : "", g ? g.note || "" : ""];
      };
      const [d, e, n] = first(guides[0]);
      rows.push(row([f.name, f.ratio, f.main ? cell("Main", "main") : "", d, e, n]));
      for (const g of guides.slice(1)) {
        const [d2, e2, n2] = first(g);
        rows.push(row([blank(), blank(), blank(), d2, e2, n2]));
      }
    }
  } else rows.push(none("No aspect ratios listed."));
  rows.push(gap());
  const finishing = finishingOf(sheets, fact);
  if (finishing.length) {
    rows.push(headRow("Finishing resolution", "Resolution", "Note"));
    for (const f of finishing) rows.push(row([f.title, f.resolution, f.note || ""]));
  } else rows.push(none("No finishing resolutions listed."));
  rows.push(gap());

  // ── NOTES
  rows.push(band("NOTES", "section"));
  const notes = String(sheet.notes || "").split("\n").map((l) => l.trim()).filter(Boolean);
  if (notes.length) for (const l of notes) rows.push(row([cell(l, "notes")]));
  else rows.push(none("No notes."));
  const files = (sheet.files || []).filter((f) => f && (f.url || f.name));
  if (files.length) {
    rows.push(gap());
    rows.push(headRow("File", "Where"));
    for (const f of files) {
      const link = driveLink(f.url);
      rows.push(row([link ? cell(fileWords(f, "File"), "link", link) : cell(fileWords(f, "File")), link ? "" : cell("In Notion, not in Drive yet", "quiet")]));
    }
  }
  return rows;
}

// ── the workbook as tabs ────────────────────────────────────────────────────

const BAD_TAB = /[\[\]:*?/\\]/g;
function tabName(want, taken) {
  const base = squash(String(want || "").replace(BAD_TAB, " ")).slice(0, 28) || "Sheet";
  let name = base;
  for (let n = 2; taken.has(name.toLowerCase()); n++) name = `${base} ${n}`;
  taken.add(name.toLowerCase());
  return name;
}

const dateWords = (iso) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""));
  if (!m) return "";
  return new Intl.DateTimeFormat("en-US", { timeZone: "UTC", year: "numeric", month: "short", day: "numeric" }).format(new Date(Date.UTC(+m[1], +m[2] - 1, +m[3])));
};

/** The words of the "Updated" line, on his clock. */
export function updatedWords(now = new Date()) {
  const when = new Intl.DateTimeFormat("en-US", { timeZone: "America/Vancouver", year: "numeric", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(now);
  return `Updated ${when.replace(", ", ", ")} PT`;
}

/**
 * The tabs of a project's workbook. `input`: `{name, sheets, shoots, lib,
 * lensEntry}` — `sheets` is `recordSheets(facts)`, `shoots` the record's shoots
 * list, `lib` the lens library, `lensEntry` the library's lens finder
 * (`entryOfSheetLens`). `updated` is the "Updated …" line ("" while the
 * workbook's content is being compared, so a time never makes a change).
 * Returns `[{name, rows, widths}]`: the project's sheet first, then each
 * shoot's own in order. A project with no sheet has no tabs.
 */
export function tabsOf({ name = "", sheets = {}, shoots = [], lib = null, lensEntry = null } = {}, updated = "") {
  const taken = new Set();
  const out = [];
  const title = `${squash(name) || "Project"} — Camera Spec Sheet`;
  const make = (tab, context, fact) => {
    const sheet = sheets[fact].sheet;
    const top = [
      row([cell(title, "title")]),
      row([cell(context, "subtitle")]),
      row([cell(HEADER_NOTE, "quiet")]),
      row([cell(updated, "stamp")]),
      gap(),
    ];
    out.push({ name: tab, fact, rows: [...top, ...sheetRows({ sheet, fact, sheets, lib, lensEntry })], widths: WIDTHS });
  };
  if (sheets[PROJECT_KEY]) make(tabName("Project", taken), "Project", PROJECT_KEY);
  const list = (Array.isArray(shoots) ? shoots : []).filter((s) => s && typeof s === "object");
  const used = new Set();
  for (const s of [...list].sort((a, b) => (Number(a.n) || 0) - (Number(b.n) || 0))) {
    const fact = `spec_${bare(s.id)}`;
    if (!sheets[fact]) continue;
    used.add(fact);
    const label = squash(s.label) || squash(s.title) || "Shoot";
    const when = dateWords(s.start);
    make(tabName(label, taken), when ? `${label} · ${when}` : label, fact);
  }
  for (const fact of Object.keys(sheets).sort()) {
    if (fact === PROJECT_KEY || used.has(fact)) continue;
    // a sheet tied to a shoot the project's list no longer names
    const label = squash(sheets[fact].sheet.title) || "Shoot sheet";
    make(tabName(label, taken), label, fact);
  }
  return out;
}

/** The tabs' words as a hash, the "Updated" line left out: what "did anything change" compares. */
export async function contentHash(tabs) {
  const text = JSON.stringify(tabs.map((t) => ({ n: t.name, r: t.rows.map((r) => r.map((c) => [c.style === "stamp" ? "" : c.text, c.style, c.link || ""])) })));
  const sum = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(sum)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── the .xlsx ───────────────────────────────────────────────────────────────

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]))
  // XML 1.0 has no room for control characters
  .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "");

/** cellXfs, in order: the style name is the index. */
const STYLES = ["blank", "title", "subtitle", "quiet", "section", "head", "body", "link", "main", "notes", "stamp"];
const styleIndex = (name) => Math.max(0, STYLES.indexOf(name));

const STYLES_XML = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="7">
<font><sz val="10"/><name val="Arial"/></font>
<font><b/><sz val="16"/><name val="Arial"/></font>
<font><b/><sz val="11"/><color rgb="FF444444"/><name val="Arial"/></font>
<font><i/><sz val="9"/><color rgb="FF777777"/><name val="Arial"/></font>
<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>
<font><b/><sz val="10"/><name val="Arial"/></font>
<font><u/><sz val="10"/><color rgb="FF1155CC"/><name val="Arial"/></font>
</fonts>
<fills count="5">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF3A3A3A"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFEEEEEE"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFDCE8FB"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="2">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left/><right/><top/><bottom style="thin"><color rgb="FFDDDDDD"/></bottom><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="${STYLES.length}">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="4" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="5" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="6" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="5" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="top"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="center"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;

const colLetter = (i) => String.fromCharCode(65 + i);

/** Rows whose single cell is long text (a note) are merged across the tab and given the height their lines need. */
const MERGED = new Set(["notes", "title", "subtitle", "quiet", "section", "stamp"]);
function rowHeight(r) {
  const first = r[0];
  if (!first || first.style !== "notes") return 0;
  const chars = WIDTHS.reduce((t, w) => t + w, 0) * 1.05;
  const lines = Math.max(1, Math.ceil(first.text.length / chars) + (first.text.split("\n").length - 1));
  return 14 * lines;
}

function sheetXml(tab) {
  const links = [];
  const merges = [];
  let body = "";
  tab.rows.forEach((r, ri) => {
    const n = ri + 1;
    const only = r[0] && MERGED.has(r[0].style) && r.slice(1).every((c) => !c.text) ? r[0] : null;
    const h = rowHeight(r);
    const big = r[0] && r[0].style === "title" ? ' ht="26" customHeight="1"' : h ? ` ht="${h}" customHeight="1"` : "";
    let cells = "";
    r.forEach((c, ci) => {
      const ref = `${colLetter(ci)}${n}`;
      const s = styleIndex(c.style);
      if (!c.text) { cells += `<c r="${ref}" s="${s}"/>`; return; }
      cells += `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${esc(c.text)}</t></is></c>`;
      if (c.link) links.push({ ref, url: c.link });
    });
    if (only && (only.style === "notes" || only.style === "title")) merges.push(`A${n}:${colLetter(COLUMNS - 1)}${n}`);
    body += `<row r="${n}"${big}>${cells}</row>`;
  });
  const cols = `<cols>${tab.widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join("")}</cols>`;
  const mergeXml = merges.length ? `<mergeCells count="${merges.length}">${merges.map((m) => `<mergeCell ref="${m}"/>`).join("")}</mergeCells>` : "";
  const linkXml = links.length ? `<hyperlinks>${links.map((l, i) => `<hyperlink ref="${l.ref}" r:id="rId${i + 1}"/>`).join("")}</hyperlinks>` : "";
  const xml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/>${cols}<sheetData>${body}</sheetData>${mergeXml}${linkXml}<pageMargins left="0.5" right="0.5" top="0.5" bottom="0.5" header="0.3" footer="0.3"/></worksheet>`;
  const rels = links.length
    ? `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${links.map((l, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${esc(l.url)}" TargetMode="External"/>`).join("")}</Relationships>`
    : "";
  return { xml, rels };
}

// ── a zip, stored (no compression): a few small XML files ───────────────────

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** `[{name, text}]` as a zip file's bytes. */
export function zipOf(files) {
  const enc = new TextEncoder();
  const parts = [];
  const central = [];
  let offset = 0;
  const u16 = (v) => [v & 0xff, (v >>> 8) & 0xff];
  const u32 = (v) => [v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff];
  for (const f of files) {
    const name = enc.encode(f.name);
    const data = enc.encode(f.text);
    const crc = crc32(data);
    const dosTime = 0, dosDate = (46 << 9) | (1 << 5) | 1; // 2026-01-01, a fixed stamp
    const local = Uint8Array.from([...u32(0x04034b50), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosTime), ...u16(dosDate),
      ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0)]);
    parts.push(local, name, data);
    central.push(Uint8Array.from([...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0x0800), ...u16(0), ...u16(dosTime), ...u16(dosDate),
      ...u32(crc), ...u32(data.length), ...u32(data.length), ...u16(name.length), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0), ...u32(offset)]), name);
    offset += local.length + name.length + data.length;
  }
  const size = central.reduce((t, p) => t + p.length, 0);
  const end = Uint8Array.from([...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length), ...u32(size), ...u32(offset), ...u16(0)]);
  const all = [...parts, ...central, end];
  const out = new Uint8Array(all.reduce((t, p) => t + p.length, 0));
  let at = 0;
  for (const p of all) { out.set(p, at); at += p.length; }
  return out;
}

/** The workbook, as .xlsx bytes. */
export function xlsxOf(tabs) {
  const list = tabs.length ? tabs : [{ name: "Sheet", rows: [], widths: WIDTHS }];
  const files = [];
  files.push({ name: "[Content_Types].xml", text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${list.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("")}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>` });
  files.push({ name: "_rels/.rels", text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>` });
  files.push({ name: "xl/workbook.xml", text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${list.map((t, i) => `<sheet name="${esc(t.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join("")}</sheets></workbook>` });
  files.push({ name: "xl/_rels/workbook.xml.rels", text: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${list.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join("")}<Relationship Id="rId${list.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>` });
  files.push({ name: "xl/styles.xml", text: STYLES_XML });
  list.forEach((t, i) => {
    const { xml, rels } = sheetXml(t);
    files.push({ name: `xl/worksheets/sheet${i + 1}.xml`, text: xml });
    if (rels) files.push({ name: `xl/worksheets/_rels/sheet${i + 1}.xml.rels`, text: rels });
  });
  return zipOf(files);
}

/** The Drive file's name: `<slug>-camera-spec-sheet`, lower case (his naming rule). */
export function fileNameOf(slug, name) {
  const s = String(slug || name || "project").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-+|-+$/g, "");
  return `${s || "project"}-camera-spec-sheet`;
}
