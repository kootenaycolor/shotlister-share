/**
 * **The plain half of the server's Export** (`exporting.js`): the cut, the
 * names and reading what was asked — nothing here touches Chrome, Drive or
 * the engine, so `hub/exporting.mjs` checks it in plain Node.
 */
export const ZONE = "America/Vancouver";

/** `Printing.Kind.margin`, in points. */
export const MARGIN = { document: 72, table: 32, storyboard: 36, avscript: 54, diagram: 36 };

/** US Letter, in points, either way round. */
export const paperOf = (orientation) => (orientation === "portrait" ? [612, 792] : [792, 612]);

// ── the cut ──────────────────────────────────────────────────────────────────

/**
 * `Printing.blockBoundsScript`, word for word: every row-shaped thing on the
 * page, `[top, bottom, holdsTheNext, startsASheet, ...cuts]`.
 */
export const BLOCKS_SCRIPT = `(() => {
  const els = Array.from(document.querySelectorAll(
    'tbody tr, .shot, .card, .scene-head, .group-head, .section-head, .run-head, .sc-cols'));
  const heads = ['scene-head', 'group-head', 'section-head', 'run-head', 'sc-cols'];
  const opened = new Set();
  const rows = new Map();
  for (const el of els) {
    const r = el.getBoundingClientRect();
    const key = Math.round(r.top);
    const holds = heads.some((c) => el.classList.contains(c)) ? 1 : 0;
    const fresh = el.closest('.fresh-page');
    const starts = fresh && !opened.has(fresh) ? 1 : 0;
    if (fresh) opened.add(fresh);
    const cuts = [];
    if (el.matches('.sc tbody tr') && !el.classList.contains('sc-cols')) {
      const boxes = [];
      const walk = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      while (walk.nextNode()) {
        if (!walk.currentNode.textContent.trim()) continue;
        const range = document.createRange();
        range.selectNodeContents(walk.currentNode);
        for (const b of range.getClientRects()) boxes.push([b.top, b.bottom]);
      }
      for (const pic of el.querySelectorAll('.card-pic, img')) {
        const b = pic.getBoundingClientRect();
        boxes.push([b.top, b.bottom]);
      }
      const seen = new Set();
      for (const [top] of boxes) {
        const y = Math.round(top) - 1;
        if (seen.has(y) || y <= r.top + 1) continue;
        seen.add(y);
        if (!boxes.some(([a, b]) => a < y && b > y)) cuts.push(y);
      }
    }
    const existing = rows.get(key);
    if (existing) {
      existing[1] = Math.max(existing[1], r.bottom);
      existing[2] = Math.max(existing[2], holds);
      existing[3] = Math.max(existing[3], starts);
      existing.push(...cuts);
    } else { rows.set(key, [r.top, r.bottom, holds, starts, ...cuts]); }
  }
  return Array.from(rows.values()).sort((a, b) => a[0] - b[0]);
})()`;

/** The script's rows as `Printing.Block`s. */
export function parseBlocks(value) {
  return (Array.isArray(value) ? value : []).filter((p) => Array.isArray(p) && p.length >= 2).map((p) => ({
    top: Number(p[0]), bottom: Number(p[1]),
    holdsTheNext: p.length > 2 && Number(p[2]) === 1,
    startsASheet: p.length > 3 && Number(p[3]) === 1,
    cuts: p.length > 4 ? p.slice(4).map(Number).sort((a, b) => a - b) : [],
  }));
}

/** `Printing.pageBreaks`, line for line: where each sheet starts. */
export function pageBreaks(blocks, pageHeight) {
  if (!(pageHeight > 0)) return [0];
  const breaks = [0];
  let pageStart = 0;
  const ordered = [...blocks].sort((a, b) => a.top - b.top);
  for (let at = 0; at < ordered.length; at += 1) {
    const block = ordered[at];
    if (!(block.top >= pageStart)) continue;
    if (block.startsASheet && block.top > pageStart && at > 0) {
      pageStart = block.top;
      breaks.push(pageStart);
    }
    let reaches = block.bottom;
    let held = at;
    while (ordered[held].holdsTheNext && held + 1 < ordered.length) {
      held += 1;
      const next = ordered[held];
      const firstCut = next.cuts.find((c) => c > next.top);
      reaches = Math.max(reaches, firstCut === undefined ? next.bottom : firstCut);
    }
    if (reaches - block.top > pageHeight) reaches = Math.min(reaches, block.bottom + pageHeight * 0.3);
    if (reaches - pageStart > pageHeight && block.top > pageStart && block.bottom - pageStart <= pageHeight) {
      pageStart = block.top;
      breaks.push(pageStart);
      continue;
    }
    if (block.bottom - pageStart > pageHeight && block.cuts.length) {
      while (block.bottom - pageStart > pageHeight) {
        const fits = block.cuts.filter((c) => c > pageStart + 1 && c - pageStart <= pageHeight);
        if (fits.length) pageStart = fits[fits.length - 1];
        else if (block.top > pageStart && block.bottom - block.top <= pageHeight) pageStart = block.top;
        else pageStart += pageHeight;
        breaks.push(pageStart);
      }
      continue;
    }
    if (block.bottom - pageStart > pageHeight) {
      if (block.top > pageStart && block.bottom - block.top <= pageHeight) {
        pageStart = block.top;
        breaks.push(pageStart);
      }
      while (block.bottom - pageStart > pageHeight) {
        pageStart += pageHeight;
        breaks.push(pageStart);
      }
    }
  }
  return breaks;
}

/** The slices a page is cut into: `{y, h}` for each sheet, as `Renderer.slice` makes them. */
export function spansOf(breaks, contentHeight, height) {
  const spans = [];
  for (let i = 0; i < breaks.length; i += 1) {
    const start = breaks[i];
    const end = i + 1 < breaks.length ? breaks[i + 1] : contentHeight;
    if (!(end > start)) continue;
    spans.push({ y: start, h: Math.min(height, end - start) });
  }
  return spans;
}

/** `Printing.exportedAtFormatter` — `Oct 17, 2026 at 3:25 PM` — on his clock. */
export function stampOf(date = new Date(), zone = ZONE) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone: zone, month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit", hour12: true,
  }).formatToParts(date).map((p) => [p.type, p.value]));
  return `${parts.month} ${parts.day}, ${parts.year} at ${parts.hour}:${parts.minute} ${String(parts.dayPeriod || "").toUpperCase()}`;
}

/** `YYYY-MM-DD` and `YYYYMMDD` on his clock. */
export function todayOf(date = new Date(), zone = ZONE) {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" })
    .formatToParts(date).map((x) => [x.type, x.value]));
  return { iso: `${p.year}-${p.month}-${p.day}`, compact: `${p.year}${p.month}${p.day}` };
}

// ── names ────────────────────────────────────────────────────────────────────

/** `FileNames.slug`: lowercase letters and numbers, one dash between. */
export function slug(text) {
  let out = "";
  let lastWasDash = true;
  for (const ch of String(text || "").toLowerCase()) {
    if (/[\p{L}\p{N}]/u.test(ch)) { out += ch; lastWasDash = false; }
    else if (!lastWasDash) { out += "-"; lastWasDash = true; }
  }
  return out.replace(/-+$/, "");
}

/** `FileNames.plain`: apostrophes vanish rather than split. */
export const plain = (text) => slug(String(text || "").replace(/['’]/g, ""));

/** `FileNames.exportAuto`: project, document, what it covers, the order, the date. */
export const autoName = ({ project, document, scope = "", order, date }) =>
  [project, document, scope, order, date].filter(Boolean).join("-");

/** A name he gave, as Studio keeps one: exactly, less path separators and its extension. */
export function typedName(said, ext) {
  let base = String(said || "").replace(/[/:]/g, "-").trim();
  if (base.toLowerCase().endsWith(`.${ext}`)) base = base.slice(0, -(ext.length + 1));
  return base;
}

/** `FileNames.unused`: the stem, or `_v2`, `_v3`… when a file of that name (any of `exts`) is there. */
export function unusedStem(stem, taken, exts) {
  const has = (s) => taken.has(s.toLowerCase()) || exts.some((e) => e && taken.has(`${s}.${e}`.toLowerCase()));
  if (!has(stem)) return stem;
  let v = 2;
  while (v < 100 && has(`${stem}_v${v}`)) v += 1;
  return `${stem}_v${v}`;
}

// ── what was asked ───────────────────────────────────────────────────────────

const PAGE_WORDS = { table: "table", "shot list": "table", "shot-list": "table", list: "table", storyboard: "storyboard",
  document: "document", avscript: "avscript", "av script": "avscript", script: "avscript", diagram: "diagram" };

/**
 * The preset he named (by name or id, any case), as the engine's words, with
 * whatever the call says over it. Answers `{ask, preset, notes}` or `{why}`.
 */
export function askFrom(args, presets) {
  const notes = [];
  let preset = null;
  const named = String(args.preset || "").trim();
  if (named) {
    const list = Array.isArray(presets) ? presets : [];
    preset = list.find((p) => p && (String(p.id) === named || String(p.name || "").toLowerCase() === named.toLowerCase()))
      || list.find((p) => p && String(p.name || "").toLowerCase().includes(named.toLowerCase()));
    if (!preset) {
      return { why: list.length ? `No export preset called ${named}. His presets: ${list.map((p) => p.name).join(", ")}.`
        : "No export presets are saved on the server yet. Name the pages, order and days instead." };
    }
  }
  const p = preset || {};
  const said = (k) => args[k] !== undefined && args[k] !== null && args[k] !== "";
  const ask = {};
  let pages = said("pages") ? args.pages : (p.pages || ["table"]);
  if (typeof pages === "string") pages = pages.split(/[,+&]| and /).map((s) => s.trim()).filter(Boolean);
  pages = (Array.isArray(pages) ? pages : []).map((x) => PAGE_WORDS[String(x).toLowerCase().trim()] || String(x).toLowerCase().trim());
  const kept = pages.filter((x) => ["table", "storyboard", "document", "avscript"].includes(x));
  for (const left of pages.filter((x) => !kept.includes(x))) {
    notes.push(left === "diagram" ? "The Diagram page exports from Studio on the Mac; left out." : `${left} is not a page here; left out.`);
  }
  // In the Export window's own order whatever order they were named in
  // (`ExportSection.allCases`): table, storyboard, document, script.
  ask.pages = ["table", "storyboard", "document", "avscript"].filter((x) => kept.includes(x));
  if (!ask.pages.length) return { why: "Say which pages: table (the shot list), storyboard, document or avscript." };
  const arrange = String(said("order") ? args.order : said("arrange") ? args.arrange : (p.arrange || "script")).toLowerCase();
  ask.arrange = /sched|shoot/.test(arrange) ? "schedule" : "script";
  // Days named with no order said: days only mean something in shooting order.
  if (said("days") && !said("order") && !said("arrange") && !preset) ask.arrange = "schedule";
  if (/table/.test(arrange)) notes.push("As in Table reads the Mac's live Table, which the server does not have; exported in script order.");
  if (preset && p.filter === "table" && Array.isArray(p.filterWords) && p.filterWords.length) {
    notes.push(`The preset keeps the Table's filter (${p.filterWords.join(", ")}); the server exports without it.`);
  }
  if (said("days")) ask.days = args.days;
  else if (p.days) ask.days = p.days;
  ask.output = String(said("output") ? args.output : (p.output || "one")).toLowerCase().replace(/[\s_-]/g, "");
  ask.output = /perday|eachday|day/.test(ask.output) ? "perday" : "one";
  if (said("columns")) ask.columns = args.columns;
  else if (Array.isArray(p.columns)) ask.columns = p.columns;
  if (said("columns_except")) ask.columns_except = args.columns_except;
  else if (Array.isArray(p.columnsExcept)) ask.columns_except = p.columnsExcept;
  ask.auto = said("auto") ? Boolean(args.auto) : (p.auto !== undefined ? Boolean(p.auto) : true);
  const size = said("size") ? Number(args.size) : (p.autoSize !== undefined && p.autoSize !== null ? Number(p.autoSize) : 1);
  ask.size = Number.isFinite(size) ? (size > 3 ? size / 100 : size) : 1;
  ask.paper = String(said("paper") ? args.paper : (p.autoPaper || "auto")).toLowerCase();
  if (said("looks")) ask.looks = args.looks;
  else if (p.looks && typeof p.looks === "object") ask.looks = p.looks;
  if (said("widths")) ask.widths = args.widths;
  else if (p.widths && typeof p.widths === "object" && Object.keys(p.widths).length) ask.widths = p.widths;
  if (said("scenes")) ask.scenes = (Array.isArray(args.scenes) ? args.scenes : String(args.scenes).split(/[,\s]+/)).map(String).filter(Boolean);
  ask.workbook = said("workbook") ? Boolean(args.workbook) : Boolean(p.workbook);
  if (preset && Number(p.fileKind) === 1) notes.push("The preset makes a flat PDF; the server makes an ordinary PDF.");
  if (preset && Number(p.fileKind) === 2) notes.push("The preset makes PNG pictures; the server makes a PDF.");
  ask.pattern = said("name") ? null : (p.pattern || null);
  ask.name = said("name") ? String(args.name) : "";
  return { ask, preset, notes };
}

