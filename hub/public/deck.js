/**
 * The deck editor — where the preview is the interface.
 *
 * His instruction, 2026-09-05: *"rethink the whole thing instead of
 * retrofitting it."* The real rendered deck is the interface: click a picture
 * in the actual design and drag it, make it bigger and watch it get bigger,
 * click words and type.
 *
 * **What this knows, and deliberately no more.** It draws the deck from the
 * record — sections, groups, pictures, emphasis, words — and each design's own
 * stylesheet is loaded beside it untouched. Nothing here knows what a design
 * looks like, which is what lets a design be written fresh for every deck
 * without this file changing.
 *
 * ---
 *
 * **The pass of 2026-09-06, second half.** His words: *"the ux/ui of the deck
 * editor frankly sucks. The PDF has no editing controls, and the html is hard
 * to use."* Both halves were true and both were structural.
 *
 * 1. **Paper was a picture of the last PDF.** An iframe of whatever his Mac
 *    printed, with no handles on it at all — and blank in his own Deck Editor
 *    app, which is a WKWebView. So paper could be looked at and never touched,
 *    and the third of his three layers (*how many across, crop, page breaks are
 *    per side*) could only ever be set for the web. **Paper is now drawn here,
 *    from the record and the deck's own print design**, sheet by sheet, with
 *    the same handles the web has. What is published is what prints: the press
 *    prints the body this file made rather than packing pages a second time,
 *    which is the end of Ref 789.
 * 2. **The controls were a strip of pills that appeared when something was
 *    picked.** Fifteen of them, named in the program's words — Split Off, Join
 *    Above, Recentre — and nothing on screen when nothing was picked. They are
 *    an inspector down the right now: the deck when nothing is picked (what is
 *    published, what Notion has that this does not, the two designs), the
 *    picture when one is.
 * 3. **There was no outline.** A `Go to…` dropdown. There is a rail of
 *    sections down the left now, each with a strip of its own frames, dragged
 *    to reorder and dotted to hide.
 * 4. **Rows could not be made by hand.** A picture could join a row or be split
 *    onto its own, and that was all. Dropping between two rows makes a new one,
 *    and Join Row Below is beside Join Row Above.
 *
 * **The fidelity law survives all of it**, and is the reason any of this can be
 * trusted: *this file writes every layout decision as an inline style on the
 * element it draws.* Inline styles are part of the body, and the body is what
 * publishes and what prints, so the editor and the two outputs cannot drift.
 * See the head of `src/editor.js` for what that replaced.
 */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

const esc = (s) => String(s == null ? "" : s)
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** The deck's own documents, sealed off.
 *
 * **Two of them, one per side.** The portal's stylesheet styles a `.frames` and
 * so does his deck design; outside a shadow root the portal wins and a
 * section's rows come out side by side in one squashed line. A design may use
 * any class name it likes, so nothing outside may reach in — and the web design
 * and the paper design may not reach each other either, which is the whole
 * point of their being two. */
let webRoot = null;
let paperRoot = null;
const deckEl = () => webRoot && webRoot.getElementById("deck");
const sheetsEl = () => paperRoot && paperRoot.getElementById("sheets");
/** Whichever side is being handled. */
const liveEl = () => (state.view === "paper" ? sheetsEl() : deckEl());

/** How many pictures a group of each loudness may put on one line, per medium.
 *  The same table as `arrangement.py`. */
const CAPS = {
  web: { hero: 1, large: 2, normal: 3, quiet: 4 },
  paper: { hero: 1, large: 2, normal: 3, quiet: 4 },
};

const LOUD = ["hero", "large", "normal", "quiet"];

/** **His two laws, in the one place that decides web layout.** Nothing full
 *  bleed, and nothing skinnier than 2.40:1. */
const WIDEST = 2.4;
const HELD = "66%";

/** **Said on the documents, not on the body.** The drop gaps live inside a
 *  shadow root, and `:host-context` is not in Safari — so the class goes on
 *  each host, where `:host(.dragging)` can see it. */
function dragging(on) {
  document.body.classList.toggle("dragging", on);
  for (const id of ["stage", "papered"]) {
    const el = document.getElementById(id);
    if (el) el.classList.toggle("dragging", on);
  }
}

const state = {
  record: null,
  view: "web",
  picked: [],          // ids, in document order
  anchor: null,        // where a Shift run counts from
  cropping: null,      // the one frame being cropped by hand, if any
  past: [],
  future: [],
  dirty: false,
  saving: false,
  unpublished: false,   // changed since the page and the PDF were last made
  edits: 0,             // how many changes have been made, ever
  sent: -1,             // which of them the server has
  said: "",
  active: "",          // the section the rail is lit on
  drawer: false,
  source: "deck",      // which stills the drawer is showing
  find: "",
  zoom: 1,
  fresh: new Set(),    // pictures pulled from Notion this session
  shelfPicked: [],     // stills picked on the shelf, to drag in together
  shelfAnchor: null,   // where a Shift run on the shelf counts from
  tall: false,         // the drawer as a wrapped grid rather than one strip
  look: "",            // the still being looked at whole, if any
  linking: false,      // the Notion field is open
};

// ---------------------------------------------------------------------------
// Where a frame is
// ---------------------------------------------------------------------------

const idOf = (section, group, at) => `${section}|${group}|${at}`;
const refOf = (id) => {
  const bits = String(id).split("|");
  return { section: bits[0], group: Number(bits[1]), at: Number(bits[2]) };
};
const idFor = (fig) => idOf(fig.dataset.section, Number(fig.dataset.group), Number(fig.dataset.at));

const sections = () => state.record.sections || [];
const liveSections = () => sections().filter((s) => s.on !== false);

function sectionOf(id) {
  return sections().find((s) => s.id === refOf(id).section);
}

function groupAt(id) {
  const s = sectionOf(id);
  return s && (s.groups || [])[refOf(id).group];
}

function keyAt(id) {
  const g = groupAt(id);
  return g && g.pictures[refOf(id).at];
}

/** Every frame in the deck, in the order it is read. */
function order() {
  const out = [];
  for (const s of sections()) {
    for (const [gi, g] of (s.groups || []).entries()) {
      for (let i = 0; i < (g.pictures || []).length; i += 1) out.push(idOf(s.id, gi, i));
    }
  }
  return out;
}

const inOrder = (ids) => {
  const all = order();
  return [...new Set(ids)].filter((id) => all.includes(id)).sort((a, b) => all.indexOf(a) - all.indexOf(b));
};

const one = () => (state.picked.length === 1 ? state.picked[0] : null);

/** The groups the selection touches, without repeats. */
function groupsPicked() {
  const seen = [];
  for (const id of state.picked) {
    const g = groupAt(id);
    if (g && !seen.includes(g)) seen.push(g);
  }
  return seen;
}

/** Which section a group belongs to, and where in it. */
function whereIs(group) {
  for (const s of sections()) {
    const gi = (s.groups || []).indexOf(group);
    if (gi !== -1) return { section: s, gi };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Reading the record
// ---------------------------------------------------------------------------

/**
 * **A frame the deck cannot name is not drawn.** Two keys in his live bible
 * are in the arrangement and in no picture record — added from one side and
 * never given a file — so `srcOf` handed back an empty address and both
 * printed as black holes on the sheet (2026-09-07). Left out of the layout
 * rather than drawn empty; the key stays in his arrangement, and the deck
 * panel says how many there are, because a silent drop is its own fault.
 */
const drawable = (key) => Boolean(nameOf(key));

function bands(group, view) {
  // **His own number first, the emphasis only as a default.** How many sit
  // across is per side — the third of his three layers — so it is stored under
  // the view it was set for and never reaches the other one.
  const said = group.across && group.across[view];
  const most = Math.max(1, said || CAPS[view][group.emphasis] || 3);
  const keys = (group.pictures || []).filter(drawable);
  if (keys.length <= most) return [keys];
  let lines = Math.ceil(keys.length / most);
  // **Never a line of one**, his rule of 2026-09-06: three across a cap of two
  // balances to two and one, stranding the third.
  while (lines > 1 && keys.length - most * (lines - 1) === 1) lines -= 1;
  const out = [];
  let at = 0;
  for (let i = 0; i < lines; i += 1) {
    const take = Math.ceil((keys.length - at) / (lines - i));
    out.push(keys.slice(at, at + take));
    at += take;
  }
  return out;
}

/** How many this group really puts on a line, on the side being looked at. */
function acrossOf(group, view = state.view) {
  return (group.across && group.across[view]) || CAPS[view][group.emphasis] || 3;
}

function shapeOf(key) {
  const held = (state.record.pictures || {})[key];
  return (held && held.ar) || 16 / 9;
}

/** Where a frame is cropped to, for the side being looked at. */
function cropOf(key, view) {
  const all = state.record.crop || {};
  return (all[key] && all[key][view]) || "";
}

function nameOf(key) {
  const held = (state.record.pictures || {})[key];
  return held ? held.name : "";
}

function srcOf(key) {
  const name = nameOf(key);
  return name ? `../pic/${name}` : "";
}

/**
 * What he has typed, out of the design's own elements and into the record.
 *
 * **Before anything redraws, never after.** A redraw writes the record's words
 * back into the page, so a word typed and then followed by *any* other change
 * was overwritten before it was ever saved.
 */
function harvest() {
  for (const host of [deckEl(), sheetsEl()]) {
    if (!host) continue;
    for (const el of host.querySelectorAll("[data-t]")) {
      state.record.words[el.dataset.t] = el.innerHTML.trim();
    }
  }
}

// ---------------------------------------------------------------------------
// Paper — the same arithmetic the press used to do on its own
// ---------------------------------------------------------------------------

/**
 * **The print maths, ported from `deckcore.py` and `render.py` on purpose.**
 *
 * These four are `row_height`, `band_height`, `flow_pages` and `fit_page`,
 * line for line. They were the press's, and while they were the press's the
 * editor could not show a page turn — so the first sheet the press made was
 * arranged differently from what he was looking at until he published once,
 * which is Ref 789. One packer, and it is this one, because this is the one he
 * judges by.
 */
const paperKit = () => state.record.paper || null;

/** Page geometry, from the deck's own theme. Letter at 0.11in gaps if silent. */
function paperTheme() {
  const kit = paperKit() || {};
  const t = kit.theme || {};
  return {
    w: Number(t.w) || 8.5,
    h: Number(t.h) || 11,
    gap: Number(t.gap) || 0.11,
    first: Number(t.first) || 10.5,
    cont: Number(t.cont) || 10.5,
  };
}

const rowHeightIn = (ars, contentW, gap) =>
  (contentW - gap * (ars.length - 1)) / ars.reduce((n, a) => n + a, 0);

const bandHeightIn = (contentW, gap, per, ar) => ((contentW - gap * (per - 1)) / per) / ar;

/** Break a flat row list into pages using the print budgets. */
function flowPages(rows, contentW, gap, first, cont, breaks, shape = shapeOf, glued = null) {
  const pages = [];
  let page = [];
  let used = 0;
  let budget = first;
  for (const [i, r] of rows.entries()) {
    const h = Math.max(...r.map((k) => bandHeightIn(contentW, gap, r.length, shape(k)))) + gap;
    // **A page break he asked for beats the arithmetic.** Set on the row in the
    // paper view; the arithmetic decides every other break. A row the search
    // glued to the one above stays with it, and `fitPage` narrows the block.
    const forced = breaks && breaks.has(i) && page.length;
    const stuck = glued && glued.has(i) && page.length && !forced;
    if ((forced || (used + h > budget && !stuck)) && page.length) {
      pages.push(page);
      page = [];
      used = 0;
      budget = cont;
    }
    page.push(r);
    used += h;
  }
  if (page.length) pages.push(page);
  return pages.length ? pages : [[]];
}

/** What it takes for these rows to fill `height` exactly. */
function fitPage(rows, contentW, gap, height, maxCrop = 1.05, shape = shapeOf) {
  const live = rows.filter((r) => r.length);
  if (!live.length) return { heights: [], width: 1 };
  const hs = live.map((r) => rowHeightIn(r.map(shape), contentW, gap));
  const avail = height - gap * (live.length - 1);
  const total = hs.reduce((n, h) => n + h, 0);
  if (total <= 0 || avail <= 0) return { heights: hs, width: 1 };
  const ratio = avail / total;
  if (ratio < 1) return { heights: hs.map((h) => h * ratio), width: ratio };
  if (ratio <= maxCrop) return { heights: hs.map((h) => h * ratio), width: 1 };
  return { heights: hs, width: 1 };
}

// ---------------------------------------------------------------------------
// Paper — laying a section's frames into rows
// ---------------------------------------------------------------------------

/** A group's declared shape, if it is an even grid — `4/3`, `16/9`, `2.39`. */
function ratioOf(group) {
  const said = String((group && group.ratio) || "").trim();
  if (!said) return 0;
  const m = /^(\d+(?:\.\d+)?)\s*[/:]\s*(\d+(?:\.\d+)?)$/.exec(said);
  if (m) return Number(m[1]) / Number(m[2]) || 0;
  return Number(said) || 0;
}

/** The shape a frame is laid out at on paper: the grid's, or its own. */
function shapeOn(key, group) {
  return ratioOf(group) || shapeOf(key);
}

/** How many a group may put across on paper, with a hero alone by right. */
function paperCap(group) {
  return Math.max(1, (group.across && group.across.paper) || CAPS.paper[group.emphasis] || 3);
}

/** Every way to cut `n` frames into rows of the allowed sizes, in order. */
function splits(n, sizes) {
  const out = [];
  const walk = (left, parts) => {
    if (left === 0) { out.push(parts.slice()); return; }
    for (const size of sizes) {
      if (size > left) continue;
      parts.push(size);
      walk(left - size, parts);
      parts.pop();
      if (out.length > 20000) return;
    }
  };
  walk(n, []);
  return out;
}

/**
 * **The Mac's row search, in the editor — so what the portal prints is what
 * the Mac would have printed.** His report on the first server print of the
 * rebuilt bible, 2026-09-07: *"it renders horribly."* Compared page by page
 * with the Mac's print of the same design, the design was identical and the
 * layout was not. This used to split each group evenly by its cap — which
 * half-filled the opening sheet, stranded a single frame in three sections,
 * and spilled frames onto the next sheet — while the Mac searched every legal
 * split of the section and scored it. Ref 811 called this the real fix.
 *
 * A pool is the run of frames a section lays out together: its groups in his
 * order, joined, until a group he gave a page break or an *Across* of its own
 * — those are his decisions and stand as rows exactly as he set them. Within
 * a pool every split into rows of two to four is tried (a hero may stand alone;
 * a lone frame is a row of one), never leaving a remainder of one, and each is
 * scored the way the Mac scores: the spread of row heights above all — rows
 * within half an inch read as a grid, a tall row over a short one reads as an
 * accident — then how well the block fills the box the band leaves it, how
 * badly shapes mix on a row (a 2.40:1 still beside a 1.33:1 one shrinks the
 * boxy frame to a stamp), how many rows cut through his groups, and how even
 * the parts are. No row may come out under 1.55in; when nothing clears that,
 * the floor drops a step at a time rather than falling back to a bad split.
 */
const WEIGHTS = { spread: 2.6, fill: 1.6, mix: 1.1, cuts: 0.55, even: 0.25, cap: 0.15 };
/** How narrow a block of frames may be drawn before it is better to break it
 *  over two sheets. The printed book already narrows to 79% and 87%. */
const NARROWEST = 0.7;
/** Two splits scoring within this of each other are the same page — see the
 *  tie-break in `packPool`. */
const CLOSE = 0.005;

/** Rows for one pool, and whether they were chosen to share a single sheet. */
function packPool(pool, contentW, gap, budget) {
  const keys = pool.map((p) => p.key);
  const n = keys.length;
  if (!n) return { rows: [], onePage: true };
  if (n === 1) return { rows: [pool], onePage: true };
  const shape = pool.map((p) => p.shape);
  const gi = pool.map((p) => p.gi);
  const heroAt = pool.map((p) => p.cap === 1);
  const sizes = [2, 3, 4];
  if (heroAt.some(Boolean)) sizes.unshift(1);
  const all = splits(n, sizes).filter((parts) => {
    // A row of one only for a hero, and only the hero's own frame.
    let at = 0;
    for (const size of parts) {
      if (size === 1 && !heroAt[at]) return false;
      at += size;
    }
    return true;
  });
  if (!all.length) return { rows: [pool], onePage: true };

  const measured = all.map((parts) => {
    const rows = [];
    let at = 0;
    for (const size of parts) { rows.push({ from: at, to: at + size }); at += size; }
    const heights = rows.map((r) => rowHeightIn(shape.slice(r.from, r.to), contentW, gap));
    const total = heights.reduce((a, b) => a + b, 0) + gap * (rows.length - 1);
    return { parts, rows, heights, total };
  });
  // How many sheets this pool wants, judged at three across — a pool of
  // twenty frames is not asked to fill one page.
  const natural = rowHeightIn(shape.slice(0, Math.min(3, n)), contentW, gap) * Math.ceil(n / 3);
  const pages = Math.max(1, Math.round(natural / budget));
  const box = budget * pages + gap * (pages - 1);

  const score = (m) => {
    const hs = m.heights;
    const spread = Math.max(...hs) - Math.min(...hs);
    // Short of the box costs by the shortfall; over it costs by how far the
    // block must be narrowed to fit, and that cost keeps growing — a block
    // twice the box is far worse than one a tenth over, not merely worse.
    const fill = m.total <= box ? (box - m.total) / box : (m.total / box - 1) * 6;
    let mix = 0; let cuts = 0; let over = 0;
    for (const r of m.rows) {
      const ars = shape.slice(r.from, r.to);
      mix += Math.max(...ars) / Math.min(...ars) - 1;
      if (new Set(gi.slice(r.from, r.to)).size > 1) cuts += 1;
      // **Emphasis is a preference on paper, not a rule.** A "large" group
      // would rather sit two across; a row of three costs a little, a row
      // that spills the sheet costs a lot more. The Mac put three of a large
      // group on a row, and so may this.
      const size = r.to - r.from;
      for (let i = r.from; i < r.to; i += 1) over += Math.max(0, size - Math.max(2, pool[i].cap));
    }
    const even = Math.max(...m.parts) - Math.min(...m.parts);
    return spread * WEIGHTS.spread + fill * WEIGHTS.fill + mix * WEIGHTS.mix
      + cuts * WEIGHTS.cuts + even * WEIGHTS.even + over * WEIGHTS.cap;
  };

  let floor = 1.55;
  let allowed = [];
  while (floor > 0.55) {
    allowed = measured.filter((m) => Math.min(...m.heights) >= floor);
    if (allowed.length) break;
    floor -= 0.15;
  }
  if (!allowed.length) allowed = measured;
  // **Scores this close are the same page.** `composition_a` chose 2·3·2 over
  // 2·2·3 by 0.0067 in 5.94 — one part in nine hundred — and the whole of that
  // margin came from two stills whose aspect ratios differ by 0.0007. A page
  // that reflows because a photograph was measured a hair differently is not
  // laid out, it is jittering. So everything within half a percent of the best
  // is treated as equally good, and the choice among them is made on something
  // a person would recognise: fewer rows, then the split that grows denser
  // down the sheet rather than jostling — which is the order they are walked
  // in. The Mac's book chose 2·2·3 here, and so does this now.
  const scored = allowed.map((m, i) => ({ m, i, s: score(m) }));
  const lowest = Math.min(...scored.map((x) => x.s));
  const close = scored.filter((x) => x.s <= lowest + Math.abs(lowest) * CLOSE);
  close.sort((a, b) => a.m.rows.length - b.m.rows.length || a.i - b.i);
  const best = close[0].m;
  // **A split chosen for one sheet stays on one sheet.** `fitPage` narrows a
  // block that runs over rather than breaking it — the Mac's book does this on
  // two sheets, at 87% and 79% of the measure — and 2·2·3·3 on the opening
  // comes to 10.46in against a 10.45in page, the honest maximum rather than a
  // spill. The limit is how narrow is still a page: below `NARROWEST` of the
  // measure the block is better carried onto the next sheet. Only a pool that
  // wanted one sheet in the first place is held to one.
  const onePage = pages === 1 && best.total <= box / NARROWEST;
  return { rows: best.rows.map((r) => pool.slice(r.from, r.to)), onePage };
}

/**
 * A section's frames as rows on paper, with the page breaks he asked for.
 *
 * Returns `{ rows, breaks }`: each row is a list of `{key, gi, at, shape}`,
 * and `breaks` holds the row indexes that start a new sheet.
 */
function paperRows(section, contentW, gap, first, cont) {
  const rows = [];
  const breaks = new Set();
  const glued = new Set();
  let pool = [];
  const flush = () => {
    if (!pool.length) return;
    const budget = rows.length ? cont : first;
    const packed = packPool(pool, contentW, gap, budget);
    for (const [i, line] of packed.rows.entries()) {
      if (packed.onePage && i > 0) glued.add(rows.length);
      rows.push(line);
    }
    pool = [];
  };
  for (const [gi, group] of (section.groups || []).entries()) {
    const frames = (group.pictures || []).map((key, at) => ({
      key, gi, at, group, shape: shapeOn(key, group), cap: paperCap(group),
    })).filter((f) => drawable(f.key));
    if (!frames.length) continue;
    if (group.break) { flush(); if (rows.length) breaks.add(rows.length); }
    if (group.across && group.across.paper) {
      // **An Across he set by hand is a row he drew.** Split as he said,
      // never merged with a neighbour, never re-cut by the search.
      flush();
      for (const line of bands(group, "paper")) {
        rows.push(line.map((key) => frames.find((f) => f.key === key)).filter(Boolean));
      }
      continue;
    }
    pool.push(...frames);
  }
  flush();
  return { rows, breaks, glued };
}

// ---------------------------------------------------------------------------
// Drawing — the web side
// ---------------------------------------------------------------------------

/** One frame, wherever it is drawn. Every measurement inline, because inline
 *  is what publishes and what prints. */
function frameEl(key, sectionId, gi, at, box) {
  const fig = document.createElement("figure");
  Object.assign(fig.dataset, { key, section: sectionId, group: String(gi), at: String(at) });
  if (box.width) fig.style.width = box.width;
  if (box.aspect) fig.style.aspectRatio = box.aspect;
  if (box.grid) {
    fig.style.minWidth = "0";
    fig.style.overflow = "hidden";
  }
  const img = document.createElement("img");
  img.src = srcOf(key);
  img.alt = "";
  img.loading = "lazy";
  if (box.fill) {
    img.style.width = "100%";
    img.style.height = "100%";
    img.style.objectFit = "cover";
    img.style.display = "block";
  }
  const spot = cropOf(key, state.view);
  if (spot) img.style.objectPosition = spot;
  fig.append(img);
  return fig;
}

/** The bar a picture would land on, drawn between two rows. */
function gapEl(sectionId, gi) {
  const bar = document.createElement("div");
  bar.className = "dgap";
  bar.dataset.gap = `${sectionId}|${gi}`;
  return bar;
}

/**
 * Put his own rows back into his own design.
 *
 * **The design's markup is the canvas, not something this rebuilds.** The
 * published page arrives whole — its cover, its headings, its furniture — and
 * only the blocks tagged `data-section` are replaced.
 */
function drawWeb() {
  const host = deckEl();
  if (!host) return;
  host.className = "web";
  for (const block of host.querySelectorAll("[data-section]")) {
    const id = block.dataset.section;
    const section = sections().find((s) => s.id === id);
    if (!section) continue;
    block.innerHTML = "";
    block.append(gapEl(id, 0));
    for (const [gi, group] of (section.groups || []).entries()) {
      let at = 0;
      for (const line of bands(group, "web")) {
        const total = line.reduce((n, k) => n + shapeOf(k), 0) || 1;
        const even = group.ratio || "";
        const alone = line.length === 1;
        const row = document.createElement("div");
        row.className = even ? "frow even" : `frow loud-${group.emphasis}${alone ? " solo" : ""}`;
        if (even) {
          row.style.setProperty("--cells", String(line.length));
          row.style.setProperty("--cell", even);
          // The generator's stylesheet has no rule for an even row at all, so
          // its structure is said here or it is not said anywhere.
          row.style.display = "grid";
          row.style.gridTemplateColumns = `repeat(${line.length},minmax(0,1fr))`;
          row.style.aspectRatio = "auto";
          row.style.width = "100%";
        } else {
          row.style.setProperty("--ar", total.toFixed(4));
          row.style.aspectRatio = `min(${total.toFixed(4)}, ${WIDEST})`;
          if (alone) {
            row.style.width = HELD;
            row.style.marginLeft = "auto";
            row.style.marginRight = "auto";
          } else {
            row.style.width = "100%";
          }
        }
        for (const key of line) {
          row.append(frameEl(key, id, gi, at, even
            ? { width: "auto", aspect: `min(${even}, ${WIDEST})`, fill: true }
            : { width: `${((shapeOf(key) / total) * 100).toFixed(3)}%`, fill: true }));
          at += 1;
        }
        block.append(row);
      }
      block.append(gapEl(id, gi + 1));
    }
  }
}

// ---------------------------------------------------------------------------
// Drawing — the paper side
// ---------------------------------------------------------------------------

/** A block of the kit, whichever shape it came in.
 *
 *  A kit pushed before 2026-09-07 hands a block over as a bare string of
 *  markup; one pushed since says `{html, cls, style}` — the contents and the
 *  dress of the sheet that held them in the template. Both are read, so a
 *  deck that has not been republished still draws. */
function dressed(block) {
  if (!block) return { html: "", cls: "", style: "" };
  if (typeof block === "string") return { html: block, cls: "", style: "" };
  return { ...block, html: block.html || "", cls: block.cls || "", style: block.style || "" };
}

/**
 * The deck as it prints: real sheets, real page turns, his own cream.
 *
 * **Drawn from the print design, not from the web one.** The kit is pushed to
 * the portal by `publish.py` and holds the print stylesheet, the page geometry
 * and each section's own block of words — the design's, untouched. What this
 * decides is only where the rows land, which is paper's half of the third
 * layer.
 */
function drawPaper() {
  const host = sheetsEl();
  if (!host) return;
  const kit = paperKit();
  host.innerHTML = "";
  if (!kit) return;
  const t = paperTheme();
  const contentW = t.w - 2 * t.gap;
  const blocks = kit.blocks || {};
  const heads = kit.heads || {};
  const sheets = [];

  for (const [n, section] of liveSections().entries()) {
    const own = heads[section.id] ? dressed(heads[section.id]) : null;
    const opening = dressed(blocks[section.id]);
    const headIn = own ? Number(own.inches) || 0 : 0;
    const first = Math.max(1, t.first - headIn);
    // **Rows by search, not by cap** — see `paperRows`. Each row knows its
    // frames' groups and layout shapes, so an even grid lays out even.
    const laid = paperRows(section, contentW, t.gap, first, t.cont);
    const shapeOfKey = new Map();
    for (const line of laid.rows) for (const f of line) shapeOfKey.set(f.key, f.shape);
    const shape = (k) => shapeOfKey.get(k) || shapeOf(k);
    const rows = laid.rows.map((line) => ({ keys: line.map((f) => f.key), frames: line, gi: line[0].gi, group: line[0].group }));
    const breaks = laid.breaks;
    // A section of words alone is a sheet of its own, exactly as it prints.
    if (!rows.length) {
      if (opening.html) sheets.push({ id: section.id, head: opening.html, dress: opening, rows: [], budget: 0, alt: n % 2 === 1 });
      continue;
    }
    const dress = own || opening;
    const headHtml = dress.html;
    const pages = flowPages(rows.map((r) => r.keys), contentW, t.gap, first, t.cont, breaks, shape, laid.glued);
    let taken = 0;
    for (const [i, page] of pages.entries()) {
      const slice = rows.slice(taken, taken + page.length);
      taken += page.length;
      sheets.push({
        id: section.id,
        head: i === 0 ? headHtml : `<div class="phead cont"><div class="pcont">${esc(section.title || section.id)} <span>continued</span></div></div>`,
        // **The first sheet wears what its design wrote; a continued sheet is
        // the plain one.** A band paints itself from behind, so its class is
        // not lifted onto the sheet — that would paint it twice.
        dress: i === 0 ? dress : null,
        rows: slice,
        shape,
        budget: i === 0 ? first : t.cont,
        alt: n % 2 === 1,
      });
    }
  }

  for (const [i, sheet] of sheets.entries()) {
    const page = document.createElement("div");
    // **The sheet wears the class its design gave it.** `red`, `spec`, `end` —
    // the red ground, the spectrum band, the mirrored last page all hang on
    // the wrapper's class in the template, and the kit carries it as `cls`.
    // Dropped, every sheet came out the plain black one — on screen and, since
    // the press prints what is drawn here, on paper too.
    const dress = sheet.dress || {};
    page.className = ["page", dress.cls || ""].join(" ").trim();
    if (dress.style) page.setAttribute("style", dress.style);
    page.dataset.sheet = String(i + 1);
    page.dataset.section = sheet.id;
    page.style.setProperty("--prog", `${((i + 1) / sheets.length * 100).toFixed(1)}%`);
    if (sheet.alt && kit.alt) page.style.backgroundColor = kit.alt;
    if (sheet.head) {
      // **Put in as the design wrote it, wrapped in nothing.** A print design
      // may style `.page > .claim`, and a box of the editor's own between the
      // two would break the selector and leave the sheet unstyled.
      const held = document.createElement("template");
      held.innerHTML = sheet.head;
      page.append(held.content);
    }
    if (sheet.rows.length) {
      const shots = document.createElement("div");
      shots.className = "shots";
      shots.style.height = `${sheet.budget.toFixed(4)}in`;
      const shape = sheet.shape || shapeOf;
      const { heights, width } = fitPage(sheet.rows.map((r) => r.keys), contentW, t.gap, sheet.budget, 1.05, shape);
      for (const [n, row] of sheet.rows.entries()) {
        if (n === 0) shots.append(gapEl(sheet.id, row.gi));
        const rw = document.createElement("div");
        rw.className = "rw";
        rw.dataset.group = String(row.gi);
        rw.style.display = "grid";
        rw.style.gridTemplateColumns = row.keys.map((k) => `${shape(k).toFixed(4)}fr`).join(" ");
        rw.style.height = `${heights[n].toFixed(4)}in`;
        if (width < 0.999) rw.style.width = `${(width * 100).toFixed(2)}%`;
        rw.style.marginLeft = "auto";
        rw.style.marginRight = "auto";
        // **Each frame carries its own group and its place in it.** A row may
        // now run across two of his groups, so the row's index is not every
        // frame's — and dragging, picking and cropping all go by the frame's.
        for (const f of row.frames || row.keys.map((key, j) => ({ key, gi: row.gi, at: j }))) {
          rw.append(frameEl(f.key, sheet.id, f.gi, f.at, { grid: true, fill: true }));
        }
        shots.append(rw);
        shots.append(gapEl(sheet.id, row.gi + 1));
      }
      page.append(shots);
    }
    if (kit.foot) {
      const foot = document.createElement("div");
      foot.className = "foot";
      foot.innerHTML = `<span>${esc(kit.foot)}</span><span class="r">${String(i + 1).padStart(2, "0")}</span>`;
      page.append(foot);
    }
    host.append(page);
  }
}

// ---------------------------------------------------------------------------
// Drawing — everything
// ---------------------------------------------------------------------------

function draw() {
  // **Take what he has typed before drawing over it.** Not every redraw comes
  // through `change` — picking a picture and switching view both redraw.
  harvest();
  const canvas = $("#canvas");
  if (canvas) canvas.classList.toggle("onpaper", state.view === "paper");
  $("#stage").hidden = state.view === "paper";
  $("#papered").hidden = state.view !== "paper";
  $("#nopaper").hidden = !(state.view === "paper" && !paperKit());
  if (state.view === "paper") drawPaper(); else drawWeb();
  words();
  mark();
  rail();
  inspector();
  drawer();
  for (const b of $$("[data-view]")) b.classList.toggle("on", b.dataset.view === state.view);
  $("#zoomsaid").textContent = `${Math.round(state.zoom * 100)}%`;
  const box = sheetsEl();
  if (box) box.style.setProperty("--sheet", `${state.zoom}`);
  // **The web side zooms as well.** The dial changed its own number and
  // nothing else on this side — found by driving it, 2026-09-07. Set on the
  // host, which is outside what `cleaned()` publishes, so it cannot travel.
  // A fluid page zoomed by `zoom` alone only reflows into the same width,
  // so the deck is held at the column's own width first and then scaled.
  const web = deckEl();
  const stage = $("#stage");
  if (web && stage) {
    if (state.zoom === 1) { web.style.zoom = ""; web.style.width = ""; }
    else { web.style.width = `${stage.clientWidth}px`; web.style.zoom = String(state.zoom); }
  }
  look();
  // **What the bar says is part of the drawing.** Left out, a change redrew the
  // deck and the bar went on saying "Saved" over a deck that had just moved.
  status();
}

/** Words, in each design's own elements. They carry the same keys on both
 *  sides, so what he types once is what both outputs say. */
function words() {
  const host = liveEl();
  if (!host) return;
  for (const el of host.querySelectorAll("[data-t]")) {
    const key = el.dataset.t;
    const said = (state.record.words || {})[key];
    // **Only when it differs.** Rewriting an element that already says the
    // right thing puts the caret back to the start mid-sentence.
    if (said !== undefined && el.innerHTML.trim() !== said) el.innerHTML = said;
    el.contentEditable = "true";
    el.spellcheck = false;
  }
}

/** Which frames are picked, and which sit in the same group as one that is. */
function mark() {
  const host = liveEl();
  if (!host) return;
  const picked = new Set(state.picked);
  const kin = new Set();
  for (const g of groupsPicked()) {
    const at = whereIs(g);
    if (!at) continue;
    for (let i = 0; i < g.pictures.length; i += 1) kin.add(idOf(at.section.id, at.gi, i));
  }
  for (const fig of host.querySelectorAll("figure[data-key]")) {
    const id = idFor(fig);
    fig.classList.toggle("picked", picked.has(id));
    fig.classList.toggle("kin", !picked.has(id) && kin.has(id));
    fig.classList.toggle("cropping", state.cropping === id);
  }
}

// ---------------------------------------------------------------------------
// The rail of sections
// ---------------------------------------------------------------------------

function rail() {
  const box = $("#sections");
  if (!box) return;
  const all = sections();
  $("#seccount").textContent = `${all.filter((s) => s.on !== false).length} of ${all.length}`;
  box.innerHTML = all.map((s) => {
    const keys = (s.groups || []).flatMap((g) => g.pictures || []).slice(0, 5);
    const strip = keys.length
      ? `<div class="dkstrip">${keys.map((k) => `<i style="background-image:url(${esc(srcOf(k))})"></i>`).join("")}</div>`
      : `<div class="dkstrip dkwords"><i></i><i></i><i></i></div>`;
    const n = (s.groups || []).reduce((c, g) => c + (g.pictures || []).length, 0);
    return `<div class="dksec${s.id === state.active ? " on" : ""}${s.on === false ? " off" : ""}"
      data-sec="${esc(s.id)}" draggable="true">
      <span class="dkgrip" aria-hidden="true">⠿</span>
      <div class="dkname"><div class="dkt">${esc(s.title || s.id)}</div>${strip}</div>
      <button type="button" class="dkeye" data-eye="${esc(s.id)}"
        title="${s.on === false ? "Show" : "Hide"}" aria-label="${s.on === false ? "Show" : "Hide"} ${esc(s.title || s.id)}">${s.on === false ? "○" : "●"}</button>
      <span class="dkn">${n || ""}</span>
    </div>`;
  }).join("");
}

// ---------------------------------------------------------------------------
// The inspector
// ---------------------------------------------------------------------------

const when = (stamp) => {
  if (!stamp) return "";
  const t = new Date(stamp);
  if (Number.isNaN(t.getTime())) return "";
  const today = new Date().toDateString() === t.toDateString();
  return today
    ? t.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    : t.toLocaleDateString([], { day: "numeric", month: "short" });
};

/** A little picture of what a group of this loudness draws. */
function loudIcon(name) {
  const n = CAPS.web[name] || 3;
  return `<i style="grid-template-columns:repeat(${n},1fr)">${"<b></b>".repeat(n)}</i>`;
}

function inspector() {
  const box = $("#insp");
  if (!box) return;
  const picked = state.picked.length;
  box.innerHTML = picked ? inspectPicture() : inspectDeck();
  // **Every control says what it does, and a switched-off one says why.** The
  // reason is written where a hand looking for it will find it.
  for (const b of box.querySelectorAll("button[data-does]")) b.title = b.dataset.does;
}

function inspectDeck() {
  const r = state.record;
  const behind = state.unpublished || (r.printed && r.updated && r.printed < r.updated);
  const active = sections().find((s) => s.id === state.active) || sections()[0];
  const n = active ? (active.groups || []).reduce((c, g) => c + (g.pictures || []).length, 0) : 0;
  const notion = r.notion || null;
  return `
    <div class="dkhead"><b>${esc(r.name || "Deck")}</b><span>${esc(r.film || "")}</span></div>

    <div class="dkgrp"><span class="dklab">Published</span>
      <div class="dklines">
        <div class="dkline${state.unpublished ? " dkwarn" : ""}"><b>Page</b><span>${
          state.unpublished ? "Not published" : r.published ? `Live · ${esc(when(r.published))}` : "Never"}</span></div>
        <div class="dkline${behind ? " dkwarn" : ""}"><b>PDF</b><span>${
          !r.printed ? "Never printed" : behind ? "Behind the page" : `Filed · ${esc(when(r.printed))}`}</span></div>
      </div>
      <div class="dkrow">
        ${r.pdf ? `<a class="dkbtn" href="${esc(r.pdf)}" target="_blank" rel="noopener">Open PDF</a>` : ""}
        <button type="button" id="copylink" data-does="The address a director opens">Copy Link</button>
      </div>
    </div>

    <div class="dkgrp"><span class="dklab">Notion</span>
      ${notion && notion.url ? `
        <div class="dksrc"><div class="dksrcname"><b>${esc(notion.page || "Linked page")}</b>
          <small>${esc(String(notion.url).replace(/^https?:\/\//, "").slice(0, 40))}</small></div>
          <a class="dkbtn" href="${esc(notion.url)}" target="_blank" rel="noopener">Open</a></div>
        <div class="dkrow">
          <button type="button" id="pullpics" data-does="Bring that page's pictures onto the shelf">Pull Pictures</button>
          <button type="button" id="linknotion" data-does="A different Notion page">Change…</button>
        </div>
        <p class="dkhint">Pictures land in Stills under Notion, marked new. Your Mac fetches them
          on its next pass. The words are this deck's and are edited here.</p>
      ` : `
        <div class="dksrc"><div class="dksrcname"><b>Not linked</b><small>No Notion page for this deck</small></div>
          <button type="button" id="linknotion" data-does="The page this deck is drafted on">Link…</button></div>
        <p class="dkhint">The page a deck is drafted on. Set once, then Pull brings its pictures down.</p>
      `}
      ${state.linking ? `<div class="dkrow">
        <input type="url" id="notionurl" placeholder="Notion page address" autocomplete="off" spellcheck="false">
        <button type="button" id="linkgo">Link</button>
        <button type="button" id="linkno">Cancel</button>
      </div>` : ""}
    </div>

    ${active ? `<div class="dkgrp"><span class="dklab">Section</span>
      <div class="dkhead"><b>${esc(active.title || active.id)}</b><span>${n} picture${n === 1 ? "" : "s"}</span></div>
      <div class="dkrow">
        <button type="button" data-toggle="${esc(active.id)}">${active.on === false ? "Show" : "Hide"}</button>
        <button type="button" id="addrow" data-does="Drag stills in from below">Add Picture Row</button>
      </div>
    </div>` : ""}

    <div class="dkgrp"><span class="dklab">Design</span>
      <div class="dklines">
        <div class="dkline"><b>Web</b><span>${r.webDesign ? "Written" : "From the page"}</span></div>
        <div class="dkline${paperKit() ? "" : " dkwarn"}"><b>Paper</b><span>${paperKit() ? "Written" : "Not on the portal"}</span></div>
        ${(() => {
          // Frames in the arrangement that name no picture — see `drawable`.
          const lost = sections().flatMap((sec) => (sec.groups || [])
            .flatMap((g) => (g.pictures || []).filter((k) => !drawable(k)))).length;
          return lost ? `<div class="dkline dkwarn"><b>Missing</b><span>${lost} frame${lost === 1 ? "" : "s"}</span></div>` : "";
        })()}
      </div>
      <p class="dkhint">Ask Claude for a design change. Words, pictures and arrangement stay.</p>
    </div>

    <div class="dkgrp"><span class="dklab">Keys</span>
      <p class="dkhint"><kbd>1</kbd>–<kbd>6</kbd> across · <kbd>H</kbd> hero · <kbd>⌫</kbd> remove ·
        <kbd>⌘Z</kbd> undo · <kbd>⌘A</kbd> the section · <kbd>⌥←</kbd> <kbd>⌥→</kbd> swap along the row ·
        double-click a frame to crop · drag to move · drop between rows for a new row ·
        right-click for the menu · double-click a still for a closer look</p>
    </div>`;
}

function inspectPicture() {
  const many = state.picked.length;
  const groups = groupsPicked();
  const g0 = groups[0];
  const at = whereIs(g0);
  const alike = groups.every((g) => g.emphasis === g0.emphasis) ? g0.emphasis : "";
  // **A number bigger than the row's own pictures draws the same row.** Worked
  // out from the group rather than guessed, so the stepper stops where the
  // drawing stops changing.
  const widest = Math.max(...groups.map((g) => (g.pictures || []).length));
  const aw = acrossOf(g0, "web");
  const ap = acrossOf(g0, "paper");
  const linked = groups.every((g) => !g.across || g.across.web === g.across.paper);
  const only = one();
  const key = only ? keyAt(only) : "";
  const spot = only ? cropOf(key, state.view) : "";
  const whole = groups.length === 1 && many === (g0.pictures || []).length;
  const last = at ? at.gi >= (at.section.groups || []).length - 1 : true;
  const ratio = g0.ratio || "";
  const [cx, cy] = (spot || "50% 50%").split(" ");
  return `
    <div class="dkhead"><b>${many === 1 ? "Picture" : `${many} Pictures`}</b>
      <span>${at ? esc(at.section.title || at.section.id) : ""}</span></div>

    ${only ? `<div class="dkshot" style="--x:${esc(cx)};--y:${esc(cy)}">
      <img src="${esc(srcOf(key))}" alt="" style="object-position:${esc(spot || "50% 50%")}">
      <span class="dkspot"></span>
    </div>` : ""}

    <div class="dkgrp"><span class="dklab">Emphasis</span>
      <div class="dkloud">${LOUD.map((name) => `
        <button type="button" data-loud="${name}" class="${alike === name ? "on" : ""}"
          ${alike === name ? "disabled" : ""}
          data-does="${alike === name ? "Already this" : `${CAPS.web[name]} on a line`}"
          >${loudIcon(name)}${name[0].toUpperCase()}${name.slice(1)}</button>`).join("")}
      </div>
    </div>

    <div class="dkgrp"><span class="dklab">Across</span>
      ${[["web", aw], ["paper", ap]].map(([sideName, n]) => `
      <div class="dkside"><span class="dklab">${sideName[0].toUpperCase()}${sideName.slice(1)}</span>
        <div class="dkstep">
          <button type="button" data-step="${sideName}:-1" ${n <= 1 ? "disabled" : ""}
            data-does="${n <= 1 ? "One across is as few as it goes" : `${n - 1} on a line`}">−</button>
          <span>${n}</span>
          <button type="button" data-step="${sideName}:1" ${n >= 6 || n >= widest ? "disabled" : ""}
            data-does="${n >= 6 ? "Six across is as many as it goes"
              : n >= widest ? "The row has no more pictures to spread" : `${n + 1} on a line`}">+</button>
        </div></div>`).join("")}
      <label class="dktick"><input type="checkbox" id="bothsides" ${linked ? "checked" : ""}> Same on both</label>
    </div>

    <div class="dkgrp"><span class="dklab">Row</span>
      <div class="dkrow">
        <button type="button" data-act="split" ${whole ? "disabled" : ""}
          data-does="${whole ? "These are already a row of their own" : "Onto a row of its own"}">Own Row</button>
        <button type="button" data-act="join" ${!at || at.gi === 0 ? "disabled" : ""}
          data-does="${!at || at.gi === 0 ? "Nothing above it" : "Into the row above"}">Join Row Above</button>
        <button type="button" data-act="joinbelow" ${last ? "disabled" : ""}
          data-does="${last ? "Nothing below it" : "Into the row below"}">Join Row Below</button>
      </div>
      <div class="dkside"><span class="dklab">Grid</span>
        <div class="dkrow tight">
          ${["", "16/9", "4/3", "2.39"].map((r) => `<button type="button" data-ratio="${r}"
            class="${ratio === r ? "on" : ""}" ${ratio === r ? "disabled" : ""}
            data-does="${ratio === r ? "Already this"
              : r ? `Even cells cropped to ${r}` : "Each frame its own shape"}">${r || "True"}</button>`).join("")}
        </div></div>
      ${state.view === "paper" && at && at.gi > 0
        ? `<label class="dktick"><input type="checkbox" id="pagebreak" ${g0.break ? "checked" : ""}> Starts a new page</label>`
        : ""}
    </div>

    <div class="dkgrp"><span class="dklab">Frame</span>
      <div class="dkrow">
        <button type="button" data-act="crop" class="${state.cropping ? "on" : ""}" ${only ? "" : "disabled"}
          data-does="${only ? "Move the picture inside its frame" : "Pick one frame"}">Crop</button>
        <button type="button" data-act="uncrop" ${spot ? "" : "disabled"}
          data-does="${spot ? "Back to the middle" : "This frame has not been moved"}">Recentre</button>
        <button type="button" data-act="replace" ${only ? "" : "disabled"}
          data-does="${only ? "Another picture in its place" : "Pick one frame"}">Replace…</button>
        <button type="button" data-act="remove" data-does="Take out of the deck">Remove</button>
      </div>
      ${only ? `<p class="dkhint">Crop is kept for each side on its own. Showing ${state.view}.</p>` : ""}
    </div>`;
}

// ---------------------------------------------------------------------------
// The stills drawer
// ---------------------------------------------------------------------------

function drawer() {
  const box = $("#stills");
  const rail = $("#drawer");
  if (!box || !rail) return;
  rail.classList.toggle("open", state.drawer);
  for (const b of $$("[data-source]")) b.classList.toggle("on", b.dataset.source === state.source);
  if (!state.drawer) { box.innerHTML = ""; return; }
  const pics = state.record.pictures || {};
  const used = new Set(order().map((id) => nameOf(keyAt(id))).filter(Boolean));
  const mine = new Set(Object.values(pics).map((p) => p.name));
  let names = state.record.shelf && state.record.shelf.length
    ? [...state.record.shelf] : [...mine];
  if (state.source === "deck") names = names.filter((n) => used.has(n));
  // **What is on the film and not yet in this deck** — the tab a deck is
  // built from.
  if (state.source === "unused") names = names.filter((n) => !used.has(n));
  // **What the press pulled down, kept on the record.** So the tab still has
  // them the next time he opens the deck, rather than only in this session.
  const pulled = new Set([...(state.record.fresh || []), ...state.fresh]);
  if (state.source === "notion") names = names.filter((n) => pulled.has(n));
  if (state.find) names = names.filter((n) => n.toLowerCase().includes(state.find.toLowerCase()));
  $("#stillcount").textContent = String(names.length);
  state.shelfPicked = state.shelfPicked.filter((n) => names.includes(n));
  const held = new Set(state.shelfPicked);
  const said = $("#shelfsaid");
  if (said) said.textContent = held.size > 1 ? `${held.size} picked` : "";
  const grid = $("#drawergrid");
  if (grid) grid.classList.toggle("on", state.tall);
  rail.classList.toggle("tall", state.tall);
  box.innerHTML = names.map((name) => `
    <button type="button" class="dkpic${used.has(name) ? " dkused" : ""}${pulled.has(name) ? " dkfresh" : ""}${held.has(name) ? " dkon" : ""}"
      data-name="${esc(name)}" draggable="true"
      title="${used.has(name) ? "In this deck" : "On the film"}">
      <img src="../pic/${esc(name)}" alt="" loading="lazy"></button>`).join("")
    + `<div class="dkdrop">Drop stills here</div>`;
}

/** One still, whole, over everything. Double-click a tile to open it. */
function look() {
  const box = $("#look");
  if (!box) return;
  box.hidden = !state.look;
  if (!state.look) return;
  const img = box.querySelector("img");
  const said = $("#looksaid");
  if (img.dataset.name !== state.look) {
    img.dataset.name = state.look;
    img.src = `../pic/${state.look}`;
    said.textContent = "";
    img.onload = () => {
      if (img.dataset.name !== state.look || !img.naturalWidth) return;
      const ar = img.naturalWidth / img.naturalHeight;
      said.textContent = `${img.naturalWidth} × ${img.naturalHeight} · ${ar.toFixed(2)}:1`;
    };
  }
}

// ---------------------------------------------------------------------------
// Changing it
// ---------------------------------------------------------------------------

const snap = () => JSON.stringify({
  sections: state.record.sections, crop: state.record.crop || {},
});

/**
 * Every change goes through here, so undo is one stack and never partial.
 *
 * **A change that changed nothing leaves no trace** — no undo step, no unsaved
 * mark. A catch-all, so a key or a stale click cannot leave one either.
 */
function change(what) {
  harvest();
  const before = snap();
  what();
  const after = snap();
  if (before === after) { draw(); return; }
  state.past.push({ record: before, picked: [...state.picked] });
  if (state.past.length > 60) state.past.shift();
  state.future.length = 0;
  state.dirty = true;
  state.unpublished = true;
  state.edits += 1;
  state.said = "";
  later();
  draw();
}

function step(from, to) {
  if (!from.length) return;
  harvest();
  to.push({ record: snap(), picked: [...state.picked] });
  const was = from.pop();
  const held = JSON.parse(was.record);
  state.record.sections = held.sections;
  state.record.crop = held.crop;
  state.picked = was.picked.filter((id) => keyAt(id));
  state.cropping = null;
  state.dirty = true;
  state.unpublished = true;
  state.edits += 1;
  later();
  draw();
}

const undo = () => step(state.past, state.future);
const redo = () => step(state.future, state.past);

/** Drop any group that has been emptied. */
function tidy() {
  for (const s of sections()) s.groups = (s.groups || []).filter((g) => (g.pictures || []).length);
}

function setEmphasis(name) {
  change(() => {
    for (const g of groupsPicked()) {
      g.emphasis = name;
      // The named size and the number are one control: setting one clears the
      // other, so the two can never disagree.
      delete g.across;
    }
  });
}

function setAcross(n, side) {
  const both = !side || ($("#bothsides") && $("#bothsides").checked);
  change(() => {
    for (const g of groupsPicked()) {
      g.across = g.across || {};
      if (both) { g.across.web = n; g.across.paper = n; } else { g.across[side] = n; }
    }
  });
}

function setRatio(r) {
  change(() => {
    for (const g of groupsPicked()) {
      if (r) g.ratio = r; else delete g.ratio;
    }
  });
}

/** Pull the picked frames out of wherever they are, and hand back their keys. */
function lift(keys) {
  for (const s of sections()) {
    for (const g of s.groups || []) g.pictures = (g.pictures || []).filter((k) => !keys.includes(k));
  }
}

/**
 * A new group in the likeness of one he already arranged.
 *
 * **Carry what is there; never re-list what you remember.** A group is whatever
 * the record says it is — emphasis, an even grid's `ratio`, `across` per side,
 * and whatever the editor grows next — so rebuilding one from a hand-written
 * literal silently deletes every key the literal forgot. That has happened
 * twice already: *Own Row* dropped `ratio` from an even grid, and then dropped
 * `across`, which since the portal began printing the PDF decides the printed
 * sheet rather than a preview. Copying the source and replacing only its
 * pictures cannot go stale as the record grows.
 *
 * **Copied, not shared.** `across` is an object; handing the new group the same
 * one would make a change to either row change both.
 *
 * **`break` is not carried.** It means *this row starts a new sheet*, and that
 * belongs to the row he set it on, not to one split out below it.
 */
function likeGroup(from, keys) {
  let made = {};
  try { made = from ? JSON.parse(JSON.stringify(from)) : {}; } catch { made = {}; }
  made.pictures = [...keys];
  if (!made.emphasis) made.emphasis = "normal";
  delete made.break;
  return made;
}

function splitOff() {
  const ids = inOrder(state.picked);
  const g0 = groupAt(ids[0]);
  const at = whereIs(g0);
  if (!at) return;
  const keys = ids.map(keyAt).filter(Boolean);
  change(() => {
    lift(keys);
    // A row split off an even grid is still an even grid, still as many
    // across, still everything else the group was — see `likeGroup`.
    at.section.groups.splice(at.gi + 1, 0, likeGroup(g0, keys));
    tidy();
    const now = at.section.groups.findIndex((g) => g.pictures.includes(keys[0]));
    state.picked = keys.map((k, i) => idOf(at.section.id, now, i));
  });
}

function joinAbove() {
  const at = whereIs(groupAt(state.picked[0]));
  if (!at || at.gi === 0) return;
  change(() => {
    const up = at.section.groups[at.gi - 1];
    const mine = at.section.groups[at.gi];
    const keys = [...mine.pictures];
    up.pictures.push(...keys);
    at.section.groups.splice(at.gi, 1);
    state.picked = keys.map((k) => idOf(at.section.id, at.gi - 1, up.pictures.indexOf(k)));
  });
}

/**
 * **The other direction, and it is not the same button.** His ask, 2026-09-06:
 * a frame on a top row could only ever reach upwards, so the first row of a
 * section could be joined to nothing at all.
 */
function joinBelow() {
  const at = whereIs(groupAt(state.picked[0]));
  if (!at || at.gi >= at.section.groups.length - 1) return;
  change(() => {
    const mine = at.section.groups[at.gi];
    const down = at.section.groups[at.gi + 1];
    const keys = [...mine.pictures];
    mine.pictures.push(...down.pictures);
    at.section.groups.splice(at.gi + 1, 1);
    state.picked = keys.map((k) => idOf(at.section.id, at.gi, mine.pictures.indexOf(k)));
  });
}

function remove() {
  const keys = inOrder(state.picked).map(keyAt).filter(Boolean);
  if (!keys.length) return;
  change(() => {
    lift(keys);
    tidy();
    state.picked = [];
    state.cropping = null;
  });
}

/** Move frames so they land beside a frame that is already placed. */
function moveTo(ids, targetId, after) {
  const keys = inOrder(ids).map(keyAt).filter(Boolean);
  if (!keys.length || keys.includes(keyAt(targetId))) return;
  const at = whereIs(groupAt(targetId));
  if (!at) return;
  const target = keyAt(targetId);
  change(() => {
    lift(keys);
    const g = at.section.groups[at.gi];
    if (!g) return;
    const spot = g.pictures.indexOf(target) + (after ? 1 : 0);
    g.pictures.splice(Math.max(0, spot), 0, ...keys);
    tidy();
    const now = at.section.groups.indexOf(g);
    state.picked = keys.map((k) => idOf(at.section.id, now, g.pictures.indexOf(k)));
  });
}

/**
 * A row of their own, where he dropped them.
 *
 * **The gap between two rows is a place.** His ask, 2026-09-06: *"add ability
 * to drag photos to different rows and make new ones."* Dropping on a frame
 * joins its row; dropping between two makes a row there.
 */
function newRowAt(keys, sectionId, gi, from) {
  const section = sections().find((s) => s.id === sectionId);
  if (!section || !keys.length) return;
  change(() => {
    // How many groups before this one will empty when these are lifted out.
    const before = (section.groups || []).slice(0, gi)
      .filter((g) => (g.pictures || []).every((k) => keys.includes(k))).length;
    lift(keys);
    tidy();
    const spot = Math.max(0, Math.min(gi - before, section.groups.length));
    section.groups.splice(spot, 0, likeGroup(from, keys));
    state.picked = keys.map((k, i) => idOf(section.id, spot, i));
  });
}

/** The deck's own name for a picture, made if the film has one and it does not. */
function keyFor(name) {
  const pics = (state.record.pictures = state.record.pictures || {});
  for (const [key, held] of Object.entries(pics)) if (held.name === name) return key;
  // A picture off the film this deck has never used needs a name of its own.
  // Its shape is guessed at 16:9 until it is drawn and measured.
  const key = `f${name.slice(0, 12)}`;
  pics[key] = { name, ar: 16 / 9 };
  measure(key, name);
  return key;
}

/** Ask the browser how tall a picture really is, then redraw with the truth. */
function measure(key, name) {
  const img = new Image();
  img.onload = () => {
    if (!img.naturalWidth || !img.naturalHeight) return;
    const ar = img.naturalWidth / img.naturalHeight;
    const held = (state.record.pictures || {})[key];
    if (!held || Math.abs(held.ar - ar) < 0.001) return;
    held.ar = Number(ar.toFixed(4));
    draw();
    later();
  };
  img.src = `../pic/${name}`;
}

function swapFor(name) {
  const id = one();
  if (!id) return;
  const at = whereIs(groupAt(id));
  const key = keyFor(name);
  if (!at) return;
  change(() => {
    const g = at.section.groups[at.gi];
    const spot = refOf(id).at;
    if (!g || spot >= g.pictures.length) return;
    g.pictures[spot] = key;
    state.picked = [idOf(at.section.id, at.gi, spot)];
  });
}

function uncrop() {
  change(() => {
    for (const id of state.picked) {
      const key = keyAt(id);
      if (state.record.crop && state.record.crop[key]) delete state.record.crop[key][state.view];
    }
  });
}

/** Move a picture inside its frame, by hand. */
function croppingBy(fig, dx, dy, from) {
  const key = fig.dataset.key;
  const box = fig.getBoundingClientRect();
  const x = Math.max(0, Math.min(100, from.x - (dx / Math.max(1, box.width)) * 100));
  const y = Math.max(0, Math.min(100, from.y - (dy / Math.max(1, box.height)) * 100));
  const all = (state.record.crop = state.record.crop || {});
  all[key] = all[key] || {};
  all[key][state.view] = `${x.toFixed(1)}% ${y.toFixed(1)}%`;
  const img = fig.querySelector("img");
  if (img) img.style.objectPosition = all[key][state.view];
}

/** The shelf's own selection: click, Shift for a run, ⌘ to add one. */
function pickShelf(name, how) {
  const all = $$("#stills [data-name]").map((b) => b.dataset.name);
  if (how === "toggle") {
    state.shelfPicked = state.shelfPicked.includes(name)
      ? state.shelfPicked.filter((n) => n !== name) : [...state.shelfPicked, name];
    state.shelfAnchor = name;
  } else if (how === "run" && state.shelfAnchor && all.includes(state.shelfAnchor)) {
    const a = all.indexOf(state.shelfAnchor);
    const b = all.indexOf(name);
    state.shelfPicked = all.slice(Math.min(a, b), Math.max(a, b) + 1);
  } else {
    state.shelfPicked = [name];
    state.shelfAnchor = name;
  }
  markShelf();
}

/** Outline what is picked on the shelf, without redrawing it under the hand. */
function markShelf() {
  const held = new Set(state.shelfPicked);
  for (const b of $$("#stills [data-name]")) b.classList.toggle("dkon", held.has(b.dataset.name));
  const said = $("#shelfsaid");
  if (said) said.textContent = held.size > 1 ? `${held.size} picked` : "";
}

/** Swap the picked frame one place along its row, without a drag. */
function nudge(by) {
  const id = one();
  if (!id) return;
  const at = whereIs(groupAt(id));
  if (!at) return;
  const g = at.section.groups[at.gi];
  const i = refOf(id).at;
  const j = i + by;
  if (!g || j < 0 || j >= g.pictures.length) return;
  change(() => {
    [g.pictures[i], g.pictures[j]] = [g.pictures[j], g.pictures[i]];
    state.picked = [idOf(at.section.id, at.gi, j)];
  });
}

/** Every frame of the section he is in — or, if he has them all, the deck. */
function pickAll() {
  const all = order();
  const mine = all.filter((id) => refOf(id).section === state.active);
  const have = mine.length && mine.every((id) => state.picked.includes(id));
  state.picked = have || !mine.length ? all : mine;
  state.anchor = state.picked[0] || null;
  state.cropping = null;
  mark();
  inspector();
  rail();
}

/**
 * Stills of his own, onto the film and then onto the shelf.
 *
 * **One road for the button and the drop.** They used to be one road with no
 * button on it: files could only arrive by being dragged onto the window,
 * which nothing on the screen said. Each goes up by its own contents, so the
 * same still twice makes one copy.
 */
async function addFiles(files) {
  const list = [...(files || [])].slice(0, 40);
  if (!list.length) return;
  toast(list.length === 1 ? "Adding 1 still…" : `Adding ${list.length} stills…`);
  let added = 0;
  for (const file of list) {
    const kind = (file.name.split(".").pop() || "jpg").toLowerCase();
    const base64 = await new Promise((ok, no) => {
      const r = new FileReader();
      r.onload = () => ok(String(r.result).split(",")[1]);
      r.onerror = no;
      r.readAsDataURL(file);
    }).catch(() => null);
    if (!base64) continue;
    const said = await fetch(location.pathname, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ add: { base64, kind } }),
    }).then((r) => r.json()).catch(() => null);
    if (said && said.added) {
      if (!(state.record.shelf || []).includes(said.added)) {
        state.record.shelf = [...(state.record.shelf || []), said.added];
      }
      state.fresh.add(said.added);
      added += 1;
    }
  }
  state.drawer = true;
  state.source = "film";
  draw();
  toast(added === list.length
    ? (added === 1 ? "Added 1 still" : `Added ${added} stills`)
    : `Added ${added} of ${list.length}`);
}

// ---------------------------------------------------------------------------
// Saving and publishing
// ---------------------------------------------------------------------------

let soon = null;
function later() {
  clearTimeout(soon);
  soon = setTimeout(() => { save(); }, 1200);
}

function status() {
  const said = $("#state");
  if (!said) return;
  said.textContent = state.said || (state.dirty ? "Unpublished" : "Saved");
  said.classList.toggle("dkwarn", /Unpublished|Would/.test(said.textContent));
  $("#undo").disabled = !state.past.length;
  $("#redo").disabled = !state.future.length;
}

async function save() {
  if (state.saving) { later(); return; }
  harvest();
  // **What is being sent, so a change made while it flies is not lost.** The
  // mark used to be cleared on any answer, so an edit made mid-flight looked
  // saved and sat in the browser until the next one pushed it.
  const sending = state.edits;
  state.saving = true;
  state.said = "Saving…";
  status();
  let ok = false;
  try {
    const answer = await fetch(location.pathname, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ sections: state.record.sections, words: state.record.words,
                             crop: state.record.crop || {}, pictures: state.record.pictures || {} }),
    });
    ok = answer.ok;
  } catch { ok = false; }
  state.saving = false;
  state.said = ok ? "" : "Would not save";
  if (ok) {
    state.sent = Math.max(state.sent, sending);
    if (state.edits === sending) state.dirty = false; else later();
  }
  status();
}

/** A body, with everything the editor added taken back off. */
function cleaned(host) {
  const clean = host.cloneNode(true);
  for (const el of clean.querySelectorAll("[contenteditable]")) {
    el.removeAttribute("contenteditable");
    el.removeAttribute("spellcheck");
  }
  for (const el of clean.querySelectorAll(".dgap")) el.remove();
  for (const el of clean.querySelectorAll("figure")) {
    el.removeAttribute("draggable");
    el.removeAttribute("data-group");
    el.removeAttribute("data-at");
    el.classList.remove("picked", "kin", "cropping", "lifted");
    if (!el.className) el.removeAttribute("class");
  }
  for (const el of clean.querySelectorAll("[data-sheet]")) el.removeAttribute("data-sheet");
  // **Put the picture addresses back the way the page keeps them.** The editor
  // rewrites `pic/` to `../pic/` because it sits one level deeper; published,
  // that same string resolves above the film and every frame breaks for real.
  for (const img of clean.querySelectorAll('img[src^="../pic/"]')) {
    img.setAttribute("src", img.getAttribute("src").slice(3));
  }
  for (const a of clean.querySelectorAll('a[href^="../pic/"]')) {
    a.setAttribute("href", a.getAttribute("href").slice(3));
  }
  return clean.innerHTML;
}

/**
 * Put what he is looking at on the film's page, and hand the press the sheets.
 *
 * **What publishes is the thing on the screen**, not a second render that might
 * differ from it — and now that is true of the PDF as well: the paper body goes
 * up beside the web one, and the press prints it rather than packing pages of
 * its own. That is what makes the paper view worth arranging on.
 */
async function publish() {
  harvest();
  // Both sides are published, so the one he is not looking at has to be drawn
  // first. Drawn, taken, and then the view put back exactly as it was.
  const was = state.view;
  const web = deckEl();
  let paper = "";
  if (paperKit()) {
    state.view = "paper";
    drawPaper();
    words();
    paper = cleaned(sheetsEl());
    state.view = was;
    if (was !== "paper") { drawWeb(); words(); }
  }
  const btn = $("#publish");
  btn.disabled = true;
  btn.textContent = "Publishing…";
  let ok = false;
  let said = null;
  try {
    const answer = await fetch(location.pathname, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        sections: state.record.sections,
        words: state.record.words,
        crop: state.record.crop || {},
        pictures: state.record.pictures || {},
        publish: cleaned(web),
        paper,
      }),
    });
    ok = answer.ok;
    said = await answer.json().catch(() => null);
  } catch { ok = false; }
  btn.disabled = false;
  if (!ok) { btn.textContent = "Would not publish"; setTimeout(() => { btn.textContent = "Publish"; }, 4000); return; }
  state.dirty = false;
  state.unpublished = false;
  state.said = "";
  state.record.published = new Date().toISOString();
  btn.textContent = paper ? "Published · printing…" : "Published";
  draw();
  if (!paper) { setTimeout(() => { btn.textContent = "Publish"; }, 4000); return; }
  // **The portal prints the sheets it was just given.** His ask, 2026-09-07:
  // the PDF is made on the server, not queued for his Mac. The request stays
  // open while Chrome prints, and the button says how it went.
  btn.disabled = true;
  let made = null;
  try {
    const answer = await fetch(location.pathname.replace(/\/edit$/, "/print"), { method: "POST" });
    made = await answer.json().catch(() => null);
    if (!answer.ok) made = made || { error: "The press did not answer" };
  } catch { made = { error: "The press did not answer" }; }
  btn.disabled = false;
  if (made && !made.error) {
    state.record.printed = new Date().toISOString();
    state.record.pdf = `../pic/${made.file}`;
    btn.textContent = `Published · PDF filed (${(made.bytes / 1e6).toFixed(1)} MB)`;
    draw();
  } else {
    btn.textContent = "Published · PDF failed";
    toast(made && made.error ? made.error : "The press failed");
  }
  setTimeout(() => { btn.textContent = "Publish"; }, 6000);
}

/** Take the address out of the field and put it on the record. */
function linkNotion() {
  const field = $("#notionurl");
  const said = field ? field.value.trim() : "";
  if (!/^https?:\/\/[^/]*notion\.(so|site|com)\//.test(said)) {
    toast("That is not a Notion page address");
    if (field) field.focus();
    return;
  }
  state.record.notion = { url: said, page: "Linked page" };
  state.linking = false;
  fetch(location.pathname, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ notion: state.record.notion }),
  }).catch(() => {});
  draw();
  toast("Linked");
}

/** Ask the Mac to fetch what Notion has. It is the only thing here that can
 *  reach Notion, so this leaves a note and the press acts on it. */
async function pull(what) {
  const btn = $("#pullpics");
  if (btn) { btn.disabled = true; btn.textContent = "Asked"; }
  try {
    await fetch(location.pathname, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ pull: what }),
    });
  } catch { /* said on the button either way */ }
  toast(`Asked for Notion's ${what} — your Mac fetches it on its next pass`);
}

function toast(said) {
  const box = $("#toast");
  if (!box) return;
  box.textContent = said;
  box.classList.add("on");
  clearTimeout(toast.t);
  toast.t = setTimeout(() => box.classList.remove("on"), 2600);
}

// ---------------------------------------------------------------------------
// Picking and handling
// ---------------------------------------------------------------------------

function pick(id, how) {
  const all = order();
  if (how === "toggle") {
    state.picked = state.picked.includes(id)
      ? state.picked.filter((x) => x !== id) : inOrder([...state.picked, id]);
    state.anchor = id;
  } else if (how === "run" && state.anchor) {
    const a = all.indexOf(state.anchor);
    const b = all.indexOf(id);
    if (a !== -1 && b !== -1) state.picked = all.slice(Math.min(a, b), Math.max(a, b) + 1);
  } else {
    state.picked = [id];
    state.anchor = id;
  }
  state.cropping = null;
  state.active = refOf(id).section;
  mark();
  inspector();
  rail();
}

/** Which frame, and which side of it, a pointer at these coordinates means. */
function landing(x, y) {
  const host = liveEl();
  if (!host) return null;
  let best = null;
  for (const fig of host.querySelectorAll("figure[data-key]")) {
    const box = fig.getBoundingClientRect();
    if (!box.width) continue;
    const dx = Math.max(box.left - x, 0, x - box.right);
    const dy = Math.max(box.top - y, 0, y - box.bottom);
    const far = Math.hypot(dx, dy);
    if (!best || far < best.far) best = { fig, far, box, id: idFor(fig) };
  }
  if (!best || best.far > 220) return null;
  return { ...best, after: x > best.box.left + best.box.width / 2 };
}

const MENU = [
  ["loud:hero", "Hero"],
  ["loud:large", "Large"],
  ["loud:normal", "Normal"],
  ["loud:quiet", "Quiet"],
  ["-", ""],
  ["across:1", "One Across"],
  ["across:2", "Two Across"],
  ["across:3", "Three Across"],
  ["across:4", "Four Across"],
  ["-", ""],
  ["split", "Own Row"],
  ["join", "Join Row Above"],
  ["joinbelow", "Join Row Below"],
  ["-", ""],
  ["crop", "Crop"],
  ["uncrop", "Recentre"],
  ["-", ""],
  ["replace", "Replace…"],
  ["remove", "Remove"],
];

function menuAt(x, y) {
  const box = $("#menu");
  box.innerHTML = MENU.map(([act, name]) => (act === "-"
    ? `<div class="msep"></div>`
    : `<button type="button" data-act="${act}">${esc(name)}</button>`)).join("");
  box.hidden = false;
  const w = box.offsetWidth || 170;
  const h = box.offsetHeight || 260;
  box.style.left = `${Math.min(x, window.innerWidth - w - 8)}px`;
  box.style.top = `${Math.min(y, window.innerHeight - h - 8)}px`;
}

const shutMenu = () => { $("#menu").hidden = true; };

function act(what) {
  if (what.startsWith("across:")) return setAcross(Number(what.split(":")[1]));
  if (what.startsWith("loud:")) return setEmphasis(what.split(":")[1]);
  if (what === "split") return splitOff();
  if (what === "join") return joinAbove();
  if (what === "joinbelow") return joinBelow();
  if (what === "remove") return remove();
  if (what === "uncrop") return uncrop();
  if (what === "crop") {
    state.cropping = state.cropping ? null : one();
    draw();
    return undefined;
  }
  if (what === "replace") {
    state.drawer = true;
    state.source = "film";
    draw();
    toast("Click a still to put it in place of the picked frame");
    return undefined;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Starting
// ---------------------------------------------------------------------------

function start(record) {
  state.record = record;
  state.record.words = record.words || {};
  state.active = (liveSections()[0] || {}).id || "";

  // ---- the two documents ------------------------------------------------
  const stage = $("#stage");
  webRoot = stage.shadowRoot || stage.attachShadow({ mode: "open" });
  webRoot.append(document.getElementById("deckdoc").content.cloneNode(true));
  const papered = $("#papered");
  paperRoot = papered.shadowRoot || papered.attachShadow({ mode: "open" });
  paperRoot.append(document.getElementById("paperdoc").content.cloneNode(true));

  const bar = document.createElement("div");
  bar.className = "dropbar";
  bar.hidden = true;
  const band = document.createElement("div");
  band.className = "marquee";
  band.hidden = true;
  // **Beside the deck, never inside it.** Anything inside the deck is swept
  // into what publishes; this is furniture and must not travel.
  document.body.append(bar, band);

  const showBar = (where) => {
    bar.hidden = false;
    bar.style.left = `${(where.after ? where.box.right : where.box.left) - 1}px`;
    bar.style.top = `${where.box.top}px`;
    bar.style.height = `${where.box.height}px`;
  };

  // ---- one gesture, decided as it goes ----------------------------------
  let hold = null;
  let ghost = null;
  let roll = 0;
  let twin = null;

  const wheelOn = () => {
    cancelAnimationFrame(roll);
    const turn = () => {
      if (hold && hold.edge) $("#canvas").scrollBy(0, hold.edge);
      roll = requestAnimationFrame(turn);
    };
    roll = requestAnimationFrame(turn);
  };
  const wheelOff = () => cancelAnimationFrame(roll);

  const makeGhost = (ids, byName) => {
    const el = document.createElement("div");
    el.className = "dghost";
    const where = byName ? `../pic/${ids[0]}` : srcOf(keyAt(ids[0]) || ids[0]);
    el.dataset.many = String(ids.length);
    el.innerHTML = `<img src="${esc(where)}" alt="">`;
    if (ids.length > 1) {
      const many = document.createElement("span");
      many.className = "dmany";
      many.textContent = String(ids.length);
      el.append(many);
    }
    document.body.append(el);
    return el;
  };

  const gapUnder = (x, y) => {
    const host = liveEl();
    if (!host) return null;
    let best = null;
    for (const g of host.querySelectorAll(".dgap")) {
      const box = g.getBoundingClientRect();
      if (!box.width) continue;
      const far = Math.abs(y - (box.top + box.height / 2))
        + (x < box.left - 40 || x > box.right + 40 ? 400 : 0);
      if (!best || far < best.far) best = { el: g, far };
    }
    return best && best.far < 34 ? best.el : null;
  };

  const letGo = () => {
    wheelOff();
    dragging(false);
    bar.hidden = true;
    band.hidden = true;
    for (const g of $$(".dgap.dkover", liveEl() || document)) g.classList.remove("dkover");
    if (ghost) { ghost.remove(); ghost = null; }
    for (const fig of (liveEl() || document).querySelectorAll("figure.lifted")) fig.classList.remove("lifted");
    const was = hold;
    hold = null;
    if (!was) return;
    if (was.what === "crop" && was.moved) { state.dirty = true; state.unpublished = true; state.edits += 1; state.said = ""; later(); draw(); }
    // Two presses and no movement: he means to crop that frame.
    if (was.what === "drag" && !was.moved && was.from === "shelf") {
      // **Said here, not in a click handler.** A press that never moved is the
      // same gesture as a click, and reading it here keeps one path.
      if (one()) swapFor(was.name);
      return;
    }
    if (was.what === "drag" && !was.moved && was.mayCrop) {
      state.picked = [was.id];
      state.cropping = was.id;
      draw();
      return;
    }
    if (was.what === "sweep") { if (was.moved) { inspector(); rail(); } else { state.picked = []; state.cropping = null; draw(); } return; }
    if (was.what === "drag" && was.moved) {
      const keys = was.from === "shelf" ? was.names.map(keyFor) : inOrder(was.ids).map(keyAt).filter(Boolean);
      if (was.from === "shelf") state.shelfPicked = [];
      if (was.gap) {
        const [sid, gi] = was.gap.dataset.gap.split("|");
        // **The whole group it came from, not just how loud it was.** A frame
        // dragged out of an even grid keeps the grid; one off the shelf starts
        // plain. See `likeGroup`.
        const from = was.from === "shelf" ? null : groupAt(was.ids[0]);
        newRowAt(keys, sid, Number(gi), from);
      } else if (was.where) {
        if (was.from === "shelf") {
          const at = whereIs(groupAt(was.where.target));
          const target = keyAt(was.where.target);
          if (at) {
            change(() => {
              const g = at.section.groups[at.gi];
              const spot = g.pictures.indexOf(target) + (was.where.after ? 1 : 0);
              g.pictures.splice(Math.max(0, spot), 0, ...keys);
              state.picked = keys.map((k) => idOf(at.section.id, at.gi, g.pictures.indexOf(k)));
            });
          }
        } else {
          moveTo(was.ids, was.where.target, was.where.after);
        }
      }
    }
  };

  const canvas = $("#canvas");

  canvas.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    shutMenu();
    const path = e.composedPath ? e.composedPath() : [e.target];
    if (path.some((n) => n.matches && n.matches("[data-t]"))) return;   // he is typing
    const fig = path.find((n) => n.matches && n.matches("figure[data-key]"));
    if (!fig) {
      // **A sweep across empty space picks up everything it touches.** Kept
      // from the pass of 2026-09-06: picking one frame at a time is most of
      // what "clunky" meant, and a rubber band is what a hand expects.
      hold = { what: "sweep", x: e.clientX, y: e.clientY, moved: false,
               add: e.metaKey || e.ctrlKey || e.shiftKey, was: [...state.picked] };
      return;
    }
    const id = idFor(fig);
    // **The second press on the same frame may be a double-click — but only
    // the release decides.** Chrome hands `dblclick` a target above the figure,
    // so the frame it happened on is simply not in its path. Waiting for the
    // release keeps the two gestures apart: press and move is always a drag.
    const twice = twin && twin.id === id && e.timeStamp - twin.when < 420;
    twin = { id, when: e.timeStamp };

    const cropping = e.altKey || state.cropping === id;
    if (cropping) {
      const said = cropOf(fig.dataset.key, state.view) || "50% 50%";
      const [fx, fy] = said.split(" ").map(parseFloat);
      harvest();
      state.past.push({ record: snap(), picked: [...state.picked] });
      state.future.length = 0;
      hold = { what: "crop", fig, x: e.clientX, y: e.clientY, from: { x: fx, y: fy }, moved: false };
      e.preventDefault();
      fig.setPointerCapture(e.pointerId);
      return;
    }
    if (!state.picked.includes(id)) {
      pick(id, e.metaKey || e.ctrlKey ? "toggle" : e.shiftKey ? "run" : "only");
    } else if (e.metaKey || e.ctrlKey) {
      pick(id, "toggle");
    }
    hold = { what: "drag", fig, id, x: e.clientX, y: e.clientY, moved: false,
             mayCrop: twice && state.cropping !== id,
             ids: state.picked.includes(id) ? [...state.picked] : [id] };
  });

  document.addEventListener("pointermove", (e) => {
    if (!hold) return;
    const far = Math.hypot(e.clientX - hold.x, e.clientY - hold.y);
    if (!hold.moved && far < 5) return;
    if (!hold.moved) {
      hold.moved = true;
      if (hold.what === "drag") {
        dragging(true);
        ghost = hold.from === "shelf" ? makeGhost(hold.names, true) : makeGhost(hold.ids);
        for (const id of hold.ids) {
          const el = [...liveEl().querySelectorAll("figure[data-key]")].find((f) => idFor(f) === id);
          if (el) el.classList.add("lifted");
        }
        wheelOn();
      }
    }
    if (hold.what === "crop") {
      croppingBy(hold.fig, e.clientX - hold.x, e.clientY - hold.y, hold.from);
      return;
    }
    if (hold.what === "sweep") {
      const left = Math.min(hold.x, e.clientX);
      const top = Math.min(hold.y, e.clientY);
      const wide = Math.abs(e.clientX - hold.x);
      const tall = Math.abs(e.clientY - hold.y);
      band.hidden = false;
      Object.assign(band.style, { left: `${left}px`, top: `${top}px`,
                                  width: `${wide}px`, height: `${tall}px` });
      const caught = [];
      for (const fig of liveEl().querySelectorAll("figure[data-key]")) {
        const box = fig.getBoundingClientRect();
        if (box.right > left && box.left < left + wide
            && box.bottom > top && box.top < top + tall) caught.push(idFor(fig));
      }
      state.picked = inOrder(hold.add ? [...hold.was, ...caught] : caught);
      mark();
      return;
    }
    if (hold.what !== "drag") return;
    if (ghost) {
      ghost.style.left = `${e.clientX + 10}px`;
      ghost.style.top = `${e.clientY + 10}px`;
    }
    // Near the top or bottom of the canvas, keep scrolling while it is held.
    const box = canvas.getBoundingClientRect();
    hold.edge = e.clientY < box.top + 70 ? -14 : e.clientY > box.bottom - 70 ? 14 : 0;

    for (const g of liveEl().querySelectorAll(".dgap.dkover")) g.classList.remove("dkover");
    const gap = gapUnder(e.clientX, e.clientY);
    hold.gap = gap || null;
    if (gap) {
      gap.classList.add("dkover");
      bar.hidden = true;
      hold.where = null;
      return;
    }
    const where = landing(e.clientX, e.clientY);
    hold.where = where ? { target: where.id, after: where.after } : null;
    if (where) showBar(where); else bar.hidden = true;
  });

  for (const kind of ["pointerup", "pointercancel"]) document.addEventListener(kind, letGo);

  canvas.addEventListener("contextmenu", (e) => {
    const path = e.composedPath ? e.composedPath() : [e.target];
    const fig = path.find((n) => n.matches && n.matches("figure[data-key]"));
    if (!fig) return;
    e.preventDefault();
    const id = idFor(fig);
    if (!state.picked.includes(id)) pick(id, "only");
    menuAt(e.clientX, e.clientY);
  });

  $("#menu").addEventListener("click", (e) => {
    const b = e.target.closest("button[data-act]");
    shutMenu();
    if (b) act(b.dataset.act);
  });
  document.addEventListener("click", (e) => { if (!e.target.closest("#menu")) shutMenu(); });

  // ---- the bar ----------------------------------------------------------
  for (const b of $$("[data-view]")) {
    b.addEventListener("click", () => {
      if (state.view === b.dataset.view) return;
      state.view = b.dataset.view;
      state.cropping = null;
      draw();
    });
  }
  $("#undo").addEventListener("click", undo);
  $("#redo").addEventListener("click", redo);
  $("#publish").addEventListener("click", publish);
  $("#zoomin").addEventListener("click", () => { state.zoom = Math.min(1.8, state.zoom + 0.1); draw(); });
  $("#zoomout").addEventListener("click", () => { state.zoom = Math.max(0.4, state.zoom - 0.1); draw(); });

  // ---- the rail ---------------------------------------------------------
  const railBox = $("#sections");
  railBox.addEventListener("click", (e) => {
    const eye = e.target.closest("[data-eye]");
    if (eye) {
      change(() => {
        const s = sections().find((x) => x.id === eye.dataset.eye);
        if (s) s.on = s.on === false;
      });
      return;
    }
    const row = e.target.closest("[data-sec]");
    if (!row) return;
    state.active = row.dataset.sec;
    state.picked = [];
    draw();
    const host = liveEl();
    const to = host && host.querySelector(`[data-section="${CSS.escape(row.dataset.sec)}"]`);
    if (to) to.scrollIntoView({ behavior: "smooth", block: "start" });
  });
  let dragSec = null;
  railBox.addEventListener("dragstart", (e) => {
    const row = e.target.closest("[data-sec]");
    if (!row) return;
    dragSec = row.dataset.sec;
    e.dataTransfer.effectAllowed = "move";
  });
  railBox.addEventListener("dragover", (e) => {
    const row = e.target.closest("[data-sec]");
    if (!row || !dragSec) return;
    e.preventDefault();
    for (const x of $$(".dksec", railBox)) x.classList.toggle("dkover", x === row);
  });
  railBox.addEventListener("drop", (e) => {
    const row = e.target.closest("[data-sec]");
    for (const x of $$(".dksec", railBox)) x.classList.remove("dkover");
    if (!row || !dragSec || row.dataset.sec === dragSec) { dragSec = null; return; }
    e.preventDefault();
    const from = dragSec;
    dragSec = null;
    change(() => {
      const all = sections();
      const at = all.findIndex((s) => s.id === from);
      const [moved] = all.splice(at, 1);
      const to = all.findIndex((s) => s.id === row.dataset.sec);
      all.splice(to, 0, moved);
    });
  });
  railBox.addEventListener("dragend", () => {
    dragSec = null;
    for (const x of $$(".dksec", railBox)) x.classList.remove("dkover");
  });

  // ---- the inspector ----------------------------------------------------
  $("#insp").addEventListener("click", (e) => {
    const b = e.target.closest("button");
    if (!b || b.disabled) return;
    if (b.dataset.loud) return setEmphasis(b.dataset.loud);
    if (b.dataset.step) {
      const [side, by] = b.dataset.step.split(":");
      const g = groupsPicked()[0];
      if (!g) return undefined;
      return setAcross(Math.max(1, Math.min(6, acrossOf(g, side) + Number(by))), side);
    }
    if (b.dataset.ratio !== undefined) return setRatio(b.dataset.ratio);
    if (b.dataset.act) return act(b.dataset.act);
    if (b.dataset.toggle) {
      return change(() => {
        const s = sections().find((x) => x.id === b.dataset.toggle);
        if (s) s.on = s.on === false;
      });
    }
    if (b.id === "addrow") { state.drawer = true; draw(); toast("Drag a still into the section"); return undefined; }
      if (b.id === "pullpics") return pull("pictures");
    if (b.id === "copylink") {
      const link = location.href.replace(/\/edit$/, "");
      navigator.clipboard.writeText(link).then(() => toast("Link copied"), () => toast(link));
      return undefined;
    }
    // **A field in the inspector, never `window.prompt`.** A WKWebView with no
    // UI delegate drops a prompt on the floor, so in his own Deck Editor app
    // the button did nothing at all. Found 2026-09-07.
    if (b.id === "linknotion") {
      state.linking = true;
      inspector();
      const field = $("#notionurl");
      if (field) { if (state.record.notion) field.value = state.record.notion.url || ""; field.focus(); }
      return undefined;
    }
    if (b.id === "linkno") { state.linking = false; inspector(); return undefined; }
    if (b.id === "linkgo") return linkNotion();
    return undefined;
  });
  $("#insp").addEventListener("keydown", (e) => {
    if (e.target.id !== "notionurl") return;
    if (e.key === "Enter") { e.preventDefault(); linkNotion(); }
    if (e.key === "Escape") { state.linking = false; inspector(); }
  });
  $("#insp").addEventListener("change", (e) => {
    if (e.target.id === "pagebreak") {
      change(() => { for (const g of groupsPicked()) g.break = e.target.checked; });
    }
    if (e.target.id === "bothsides" && e.target.checked) {
      const n = acrossOf(groupsPicked()[0] || {}, state.view);
      change(() => {
        for (const g of groupsPicked()) { g.across = g.across || {}; g.across.web = n; g.across.paper = n; }
      });
    }
  });

  // ---- the drawer -------------------------------------------------------
  $("#drawertoggle").addEventListener("click", () => { state.drawer = !state.drawer; draw(); });
  for (const b of $$("[data-source]")) {
    b.addEventListener("click", () => { state.source = b.dataset.source; state.drawer = true; draw(); });
  }
  $("#find").addEventListener("input", (e) => { state.find = e.target.value; drawer(); });
  const stills = $("#stills");
  let shelfTwin = null;
  stills.addEventListener("pointerdown", (e) => {
    const b = e.target.closest("[data-name]");
    if (!b || e.button !== 0) return;
    e.preventDefault();
    const name = b.dataset.name;
    // **A second press on the same tile opens it whole.** Read here rather
    // than from `dblclick`, which never fires once a pointerdown has been
    // prevented — and it has to be, or the browser drags the picture itself.
    if (shelfTwin && shelfTwin.name === name && e.timeStamp - shelfTwin.when < 420) {
      shelfTwin = null;
      hold = null;
      state.look = name;
      look();
      return;
    }
    shelfTwin = { name, when: e.timeStamp };
    // **Several at once.** Shift for a run, ⌘ to add one; then the whole
    // pick is dragged in as one row. A plain press picks that one tile, and
    // if a frame is picked on the deck, the release swaps it in as ever.
    if (e.shiftKey || e.metaKey || e.ctrlKey) {
      pickShelf(name, e.shiftKey ? "run" : "toggle");
      return;
    }
    if (!state.shelfPicked.includes(name)) pickShelf(name, "only");
    const names = [...state.shelfPicked];
    hold = { what: "drag", from: "shelf", name, names, ids: [],
             x: e.clientX, y: e.clientY, moved: false };
  });
  $("#look").addEventListener("click", () => { state.look = ""; look(); });
  $("#drawergrid").addEventListener("click", () => {
    state.tall = !state.tall;
    state.drawer = true;
    draw();
  });
  $("#addstills").addEventListener("click", () => $("#addfiles").click());
  $("#addfiles").addEventListener("change", (e) => {
    addFiles(e.target.files);
    e.target.value = "";
  });

  // A still dropped onto the window goes to the film, then onto the shelf.
  document.addEventListener("dragover", (e) => { if (e.dataTransfer && e.dataTransfer.types.includes("Files")) e.preventDefault(); });
  document.addEventListener("drop", (e) => {
    if (!e.dataTransfer || !e.dataTransfer.files.length) return;
    e.preventDefault();
    addFiles(e.dataTransfer.files);
  });

  // ---- keys -------------------------------------------------------------
  document.addEventListener("keydown", (e) => {
    const typing = e.target.closest("[contenteditable], input, textarea")
      || (e.composedPath && e.composedPath().some((n) => n.matches && n.matches("[data-t]")));
    if (typing) {
      if (e.key === "Escape") e.target.blur();
      return;
    }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") {
      e.preventDefault();
      if (e.shiftKey) redo(); else undo();
      return;
    }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") { e.preventDefault(); save(); return; }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "a") { e.preventDefault(); pickAll(); return; }
    if (e.key === "Escape") {
      if (state.look) { state.look = ""; look(); return; }
      state.picked = []; state.cropping = null; state.shelfPicked = []; shutMenu(); draw(); return;
    }
    if (!state.picked.length) return;
    // **⌥← and ⌥→ swap the picked frame with its neighbour.** ⌘ with an arrow
    // is the browser's own Back in Safari, so Option carries it.
    if (e.altKey && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
      e.preventDefault();
      nudge(e.key === "ArrowRight" ? 1 : -1);
      return;
    }
    // **The arrows walk the deck.** Reading order, so it crosses a row's end
    // and a section's end without anybody having to reach for the mouse.
    if (e.key.startsWith("Arrow")) {
      const all = order();
      const from = all.indexOf(state.picked[state.picked.length - 1]);
      const by = e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : -1;
      const to = Math.max(0, Math.min(all.length - 1, from + by));
      if (to === from) return;
      e.preventDefault();
      pick(all[to], e.shiftKey ? "run" : "only");
      const host = liveEl();
      const fig = host && [...host.querySelectorAll("figure[data-key]")]
        .find((f) => idFor(f) === all[to]);
      if (fig) fig.scrollIntoView({ block: "nearest" });
      return;
    }
    if (/^[1-6]$/.test(e.key)) { setAcross(Number(e.key)); return; }
    if (e.key.toLowerCase() === "h") { setEmphasis("hero"); return; }
    if (e.key === "Backspace" || e.key === "Delete") { e.preventDefault(); remove(); }
  });

  // **A word typed is a word to save.** The design's own elements carry the
  // keys, so this listens on the documents rather than on anything of its own.
  for (const host of [webRoot, paperRoot]) {
    host.addEventListener("input", (e) => {
      const path = e.composedPath ? e.composedPath() : [e.target];
      if (!path.some((n) => n.matches && n.matches("[data-t]"))) return;
      state.dirty = true;
      state.unpublished = true;
      state.edits += 1;
      state.said = "";
      status();
      later();
    });
  }

  window.addEventListener("beforeunload", (e) => {
    if (!state.dirty) return undefined;
    e.preventDefault();
    e.returnValue = "";
    return "";
  });

  draw();
  status();
}

const seed = document.getElementById("record");
if (seed) start(JSON.parse(seed.textContent));
