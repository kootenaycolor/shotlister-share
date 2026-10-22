/**
 * Arranging a board, and saying what is where on one — for a chat.
 *
 * **Why it exists.** His ask, 2026-09-25: a chat should be able to lay a board
 * out the way he would by hand — "tidy into a grid", "group by scene", "spread
 * the stills along the slider", "put the references in a row above the
 * shots" — and not only card by card. The board itself (`public/board.js`)
 * measures every card it draws; nothing on the server ever draws one, so here
 * a card's size is *estimated* from its kind and, for a picture, from the
 * picture's own shape read off the front of the file. The estimates err
 * large: a gap a little wider than it needed to be is nothing, and two cards
 * on top of each other is the one thing an arrangement must never do.
 *
 * Positions are a card's **centre**, the way the board keeps them.
 */

import { keys } from "../../relay/layout.js";

/** How wide each kind is drawn. **The same widths as `KINDS` in `public/board.js`.** */
export const WIDTH = {
  ref: 300, test: 300, video: 300, still: 230, clip: 270, shot: 260, scene: 250, location: 260,
  day: 230, person: 220, doc: 240, link: 260, idea: 235, gear: 275, note: 215, heading: 0,
};
/** Kinds in the order a board's own lanes put them (`LANES` in `public/board.js`). */
export const ORDER = ["ref", "test", "video", "still", "clip", "shot", "scene", "location", "day", "person", "doc", "idea", "link", "gear", "note", "heading"];
export const KIND_NAMES = {
  ref: "References", test: "Tests", video: "Videos", still: "Stills", clip: "Clips", shot: "Shots", scene: "Scenes",
  location: "Locations", day: "Days", person: "People", doc: "Documents", link: "Links", idea: "Ideas", gear: "Gear",
  note: "Notes", heading: "Headings",
};
const LANES = [
  ["Pictures", ["ref", "test", "video", "still", "clip"]],
  ["From the Film", ["shot", "scene", "location", "day", "person", "doc"]],
  ["Ideas", ["idea"]],
  ["Links", ["link"]],
  ["Gear", ["gear"]],
  ["Notes", ["note"]],
];
/** What may be collapsed to its picture and name (`foldable` in `public/board.js`). */
export const FOLDABLE = (kind) => !["note", "heading", "still", "clip"].includes(kind);
const PICTURED = new Set(["ref", "test", "video", "shot", "scene", "location", "link", "doc"]);
const SPAN = 1900;

// ------------------------------------------------------------ a picture's shape

const be32 = (b, i) => ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;

/**
 * A picture's width and height from the front of its file — PNG, GIF, WebP
 * and JPEG, a phone photograph's turn included (a browser draws it turned).
 * Null for anything else, which is then given a common shape.
 */
export function sizeFromBytes(b) {
  if (!b || b.length < 30) return null;
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e) return { w: be32(b, 16), h: be32(b, 20) };
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46) return { w: b[6] | (b[7] << 8), h: b[8] | (b[9] << 8) };
  if (b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57 && b[9] === 0x45) {
    const t = String.fromCharCode(b[12], b[13], b[14], b[15]);
    if (t === "VP8 ") return { w: (b[26] | (b[27] << 8)) & 0x3fff, h: (b[28] | (b[29] << 8)) & 0x3fff };
    if (t === "VP8L") {
      const n = (b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24)) >>> 0;
      return { w: (n & 0x3fff) + 1, h: ((n >> 14) & 0x3fff) + 1 };
    }
    if (t === "VP8X") return { w: 1 + (b[24] | (b[25] << 8) | (b[26] << 16)), h: 1 + (b[27] | (b[28] << 8) | (b[29] << 16)) };
    return null;
  }
  if (b[0] === 0xff && b[1] === 0xd8) {
    let turned = false;
    let i = 2;
    while (i + 9 < b.length) {
      if (b[i] !== 0xff) { i += 1; continue; }
      const m = b[i + 1];
      if (m === 0xd8 || m === 0x01 || m === 0xff || (m >= 0xd0 && m <= 0xd7)) { i += m === 0xff ? 1 : 2; continue; }
      const len = (b[i + 2] << 8) | b[i + 3];
      if (m === 0xe1 && String.fromCharCode(b[i + 4], b[i + 5], b[i + 6], b[i + 7]) === "Exif") turned = exifTurned(b, i + 10);
      if (m >= 0xc0 && m <= 0xcf && m !== 0xc4 && m !== 0xc8 && m !== 0xcc) {
        const h = (b[i + 5] << 8) | b[i + 6], w = (b[i + 7] << 8) | b[i + 8];
        return turned ? { w: h, h: w } : { w, h };
      }
      i += 2 + len;
    }
  }
  return null;
}

/** Whether a JPEG's EXIF says it stands on its side (orientation 5 to 8). */
function exifTurned(b, t) {
  try {
    const le = b[t] === 0x49;
    const u16 = (i) => (le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
    const u32 = (i) => (le ? (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0 : be32(b, i));
    const ifd = t + u32(t + 4);
    const n = u16(ifd);
    for (let k = 0; k < n; k += 1) {
      const e = ifd + 2 + k * 12;
      if (u16(e) === 0x0112) return u16(e + 8) >= 5 && u16(e + 8) <= 8;
    }
  } catch { /* an unreadable EXIF is an upright picture */ }
  return false;
}

/** Where on the film a card's picture address is kept, or "" for one elsewhere. */
export function keyOfSrc(project, src) {
  const s = String(src || "").split("?")[0];
  const file = s.split("/").pop() || "";
  if (!/^[0-9a-f]{32}\.[a-z0-9]{2,5}$/.test(file)) return "";
  if (/(^|\/)pic\/[^/]+$/.test(s)) return keys.doc(project, file);
  if (/(^|\/)media\/[^/]+$/.test(s)) return keys.medium(project, file);
  return "";
}

/** A picture's height over its width, read off the front of the file. 0 when unknown. */
export async function ratioOf(env, project, src) {
  const key = keyOfSrc(project, src);
  if (!key) return 0;
  try {
    const got = await env.BUCKET.get(key, { range: { offset: 0, length: 98304 } });
    if (!got) return 0;
    const d = sizeFromBytes(new Uint8Array(await got.arrayBuffer()));
    return d && d.w > 0 && d.h > 0 ? Math.min(3, Math.max(0.2, d.h / d.w)) : 0;
  } catch {
    return 0;
  }
}

/** The picture that stands for a card, as `makeCard` in `public/board.js` chooses it. */
export function coverOf(c) {
  if (c.kind === "still") return c.src || "";
  if (c.kind === "clip") return c.poster || "";
  if (c.kind === "doc") return c.src || "";
  if (!PICTURED.has(c.kind)) return "";
  if (c.src && c.kind !== "ref" && c.kind !== "test") return c.src;
  const f = (c.figs || [])[0];
  if (f && f.src) return f.src;
  const k = (c.clips || [])[0];
  if (k && k.poster) return k.poster;
  return c.src || "";
}

// ------------------------------------------------------------- a card's size

const lines = (text, perLine) => Math.max(1, Math.ceil(String(text || "").length / Math.max(8, perLine)));

/**
 * A card's width and height as the board would draw it, a little large.
 * `ratio` is its picture's height over width (0: not known, so a common one).
 *
 * **Measured, not guessed.** Cards of every kind were laid on a board in a
 * browser (2026-09-25) and taken apart: a still or clip is its picture set in
 * 7px, then 18px of padding and a line for its kicker; every other card is its
 * picture edge to edge, then 28px of padding round a stack of lines 9px apart
 * — kicker, title, the line under it, its fields or facts, what is inside, its
 * note, and the foot a board with sorts draws. The widths per character are
 * the fonts' own, rounded toward more lines. Then a little more, on top.
 */
export function sizeOf(c, ratio) {
  // **At its own size** (`size`, dragged by its corner), and **as its picture
  // alone** (`bare`: `.bd-n.bare` in `public/board.js` draws no card body).
  const k = Math.min(5, Math.max(0.3, Number(c.size) || 1));
  const { w, h } = c.bare && (coverOf(c) || c.kind === "clip") ? bareSize(c, ratio) : madeSize(c, ratio);
  return k === 1 ? { w, h } : { w: Math.round(w * k), h: Math.round(h * k) };
}
function bareSize(c, ratio) {
  const w = WIDTH[c.kind] || 240;
  const pad = c.kind === "still" ? 6 : 0;
  return { w, h: Math.round((w - 2 * pad) * (ratio || 0.5625) + pad + 4) };
}
function madeSize(c, ratio) {
  const kind = c.kind;
  if (kind === "heading") {
    const t = String(c.text || c.title || "");
    return { w: Math.max(90, Math.round(t.length * 17 + 44)), h: 60 };
  }
  const w = WIDTH[kind] || 240;
  if (kind === "still" || kind === "clip") {
    const pic = Math.round((w - 14) * (ratio || (kind === "still" ? 0.75 : 0.5625)));
    let h = 8 + pic + 18;
    if (c.kicker) h += 21;
    if (c.cap && c.cap !== c.kicker) h += lines(c.cap, (w - 16) / 7.4) * 18 + 6;
    if (c.text) h += lines(c.text, (w - 16) / 9) * 22 + 6;
    return { w, h: Math.round(h * 1.04 + 12) };
  }
  const tw = w - 28;
  if (c.folded && FOLDABLE(kind)) {
    // **Collapsed: its picture (150 at most), what it is, its name** — the
    // card's other lines are not drawn (`.bd-n.folded` in `public/board.js`).
    const cover = coverOf(c) ? Math.min(150, Math.round(w * (ratio || 0.5625))) : 0;
    const bits = [c.kicker ? lines(c.kicker, tw / 7) * 15 : 0, kind === "note" ? 0 : Math.min(2, lines(c.title, tw / 10.5)) * 20,
      c.text ? lines(c.text, tw / 9.5) * 22 : 0].filter(Boolean);
    const h = 2 + cover + 14 + 12 + bits.reduce((t, n) => t + n, 0) + 9 * Math.max(0, bits.length - 1);
    return { w, h: Math.round(h * 1.04 + 12) };
  }
  const parts = [];
  if (c.kicker) parts.push(lines(c.kicker, tw / 7) * 15);
  if (kind === "idea" || kind === "gear") parts.push(lines(c.title, tw / 12) * 27);
  else if (kind !== "note") parts.push(lines(c.title, tw / 10.5) * 20);
  if (c.sub || c.cap) parts.push(lines(c.sub || c.cap, tw / 8.3) * 19);
  if (kind === "doc" && c.closed && !c.src) parts.push(17);
  if (Array.isArray(c.fields) && c.fields.length) {
    const shown = c.fields.filter(([k]) => ["Size", "Angle", "Lens", "Movement", "Support", "Scene", "Day"].includes(k)).slice(0, 7);
    if (shown.length) parts.push(shown.reduce((t, [, v]) => t + lines(v, 20) * 19, 0));
  } else if (Array.isArray(c.facts) && c.facts.length) {
    parts.push(lines(c.facts.slice(0, 6).join(" · "), tw / 7.5) * 18);
  }
  if (Array.isArray(c.spec) && c.spec.length) parts.push(Math.min(4, c.spec.length) * 19);
  if ((c.players || []).length || (c.clips || []).length || (c.figs || []).length) parts.push(17);
  if (kind === "note") parts.push(lines(c.text, tw / 9.5) * 22);
  else if (c.text) parts.push(lines(c.text, tw / 9.5) * 22);
  if (kind !== "note") parts.push(23);
  const cover = coverOf(c) ? Math.round(w * (ratio || 0.5625)) : 0;
  const h = 2 + cover + 28 + parts.reduce((t, n) => t + n, 0) + 9 * Math.max(0, parts.length - 1);
  return { w, h: Math.round(h * 1.04 + 12) };
}

// --------------------------------------------------------------- arranging

const GAP = 40;
const GROUP_GAP = 220;
const MARGIN = 60;

/** How many to a row in a group: one group wide, several narrow. */
function perRow(n, many, asked) {
  if (asked) return Math.max(1, Math.min(40, Math.round(asked)));
  if (!many) return n <= 4 ? n : Math.min(6, Math.ceil(Math.sqrt(n * 1.5)));
  return n <= 2 ? n : n <= 6 ? 2 : n <= 12 ? 3 : 4;
}

/**
 * One group as a block: its heading on top, then its cards in rows, each row
 * top-aligned, left to right. Places are relative to the block's top left.
 */
function blockOf(group, shape, many, asked) {
  const out = [];
  let y = 0;
  let width = 0;
  if (group.heading) {
    const h = group.heading;
    out.push({ c: h, rx: h.w / 2, ry: h.h / 2 });
    y = h.h + 24;
    width = h.w;
  }
  const items = group.cards;
  const per = shape === "row" ? Math.max(1, items.length) : shape === "column" ? 1 : perRow(items.length, many, asked);
  for (let i = 0; i < items.length; i += per) {
    const row = items.slice(i, i + per);
    let x = 0;
    for (const c of row) {
      out.push({ c, rx: x + c.w / 2, ry: y + c.h / 2 });
      x += c.w + GAP;
    }
    width = Math.max(width, x - GAP);
    y += Math.max(...row.map((c) => c.h)) + GAP;
  }
  return { w: width, h: items.length ? y - GAP : y, out };
}

/**
 * Cards spread along a line sort, the way the board's own line view does it:
 * lane by lane (pictures, then the film, ideas, links, gear, notes), each
 * card as near its place on the line as the others let it be. Relative to a
 * line running from −1900 to +1900.
 */
function alongLine(cards, valueOf) {
  const out = [];
  let top = 0;
  const pack = (row) => {
    const clusters = [];
    const settle = (k) => {
      let off = 0;
      k.offs = k.its.map((n) => { const o = off; off += n.c.w + GAP; return o; });
      k.w = off - GAP;
      k.left = k.its.reduce((t, n, i) => t + (n.want - n.c.w / 2 - k.offs[i]), 0) / k.its.length;
    };
    for (const n of row.slice().sort((p, q) => p.want - q.want)) {
      const k = { its: [n] };
      settle(k);
      clusters.push(k);
      while (clusters.length > 1) {
        const b = clusters[clusters.length - 1], a = clusters[clusters.length - 2];
        if (a.left + a.w + GAP <= b.left) break;
        a.its = a.its.concat(b.its);
        settle(a);
        clusters.pop();
      }
    }
    for (const k of clusters) k.its.forEach((n, i) => { n.rx = k.left + k.offs[i] + n.c.w / 2; });
  };
  for (const [, kinds] of LANES) {
    const members = cards.filter((c) => kinds.includes(c.kind)).map((c) => ({ c, v: valueOf(c) }))
      .sort((a, b) => a.v - b.v);
    if (!members.length) continue;
    for (const n of members) n.want = -SPAN + n.v * 2 * SPAN;
    const rows = Math.ceil(members.length / 10);
    for (let r = 0; r < rows; r += 1) {
      const row = members.filter((_, i) => i % rows === r);
      pack(row);
      const h = Math.max(...row.map((n) => n.c.h));
      for (const n of row) { n.ry = top + n.c.h / 2; out.push(n); }
      top += h + GAP;
    }
    top += 110;
  }
  // Anything of a kind with no lane (a heading) waits under the line.
  const rest = cards.filter((c) => !LANES.some(([, k]) => k.includes(c.kind)));
  let x = -SPAN;
  for (const c of rest) { out.push({ c, rx: x + c.w / 2, ry: top + c.h / 2 }); x += c.w + GAP; }
  return out;
}

const rectOf = (c) => ({ x0: c.x - c.w / 2, y0: c.y - c.h / 2, x1: c.x + c.w / 2, y1: c.y + c.h / 2 });

/**
 * Somewhere a box of `w` by `h` can sit near `want` (its top left) without
 * touching any of `still`. Tried outward from where it was wanted, in the
 * directions `prefer` names first.
 */
export function clearSpot(want, w, h, still, prefer = "down") {
  const hits = (x, y) => still.some((s) => x < s.x1 + MARGIN && x + w > s.x0 - MARGIN && y < s.y1 + MARGIN && y + h > s.y0 - MARGIN);
  if (!hits(want.x, want.y)) return want;
  const dirs = {
    down: [[0, 1], [1, 0], [-1, 0], [0, -1]],
    up: [[0, -1], [1, 0], [-1, 0], [0, 1]],
    right: [[1, 0], [0, 1], [0, -1], [-1, 0]],
    left: [[-1, 0], [0, 1], [0, -1], [1, 0]],
  }[prefer] || [[0, 1], [1, 0], [-1, 0], [0, -1]];
  for (let step = 1; step < 600; step += 1) {
    const d = step * 60;
    for (const [dx, dy] of dirs) {
      if (!hits(want.x + dx * d, want.y + dy * d)) return { x: want.x + dx * d, y: want.y + dy * d };
    }
  }
  const low = Math.max(...still.map((s) => s.y1));
  return { x: want.x, y: low + 200 };
}

/**
 * **Lay out a set of cards.** `cards` is every card on the board, each with
 * `id`, `kind`, `x`, `y`, `w`, `h`; `moving` the ids to arrange; `groups` the
 * order they fall into (`[{name, ids, heading}]`, one nameless group for a
 * plain grid), or `line` for a spread along a sort. Answers `{id: [x, y]}`
 * for every card moved — headings included — and the box it all takes.
 *
 * Nothing that is not moving is touched, and nothing moved lands on it.
 */
export function arrange({ cards, moving, groups, shape = "grid", perRowAsked = 0, line = null, near = null, side = "below", at = null, whole = false }) {
  const byId = new Map(cards.map((c) => [c.id, c]));
  let placed;
  if (line) {
    placed = alongLine(line.cards, line.valueOf);
    for (const h of line.headings || []) placed.push(h);
  } else {
    const many = groups.length > 1;
    const blocks = groups.map((g) => blockOf(g, shape, many, perRowAsked));
    // Groups side by side, wrapping into a new band once one grows too wide.
    const widest = Math.max(0, ...blocks.map((b) => b.w));
    const total = blocks.reduce((t, b) => t + b.w, 0) + GROUP_GAP * Math.max(0, blocks.length - 1);
    const most = Math.max(widest, shape === "row" ? total : Math.min(total, Math.max(3600, Math.sqrt(total * 2600))));
    let x = 0, y = 0, band = 0;
    placed = [];
    for (const b of blocks) {
      if (x > 0 && x + b.w > most + 1) { x = 0; y += band + GROUP_GAP; band = 0; }
      for (const p of b.out) placed.push({ c: p.c, rx: x + p.rx, ry: y + p.ry });
      x += b.w + GROUP_GAP;
      band = Math.max(band, b.h);
    }
  }
  if (!placed.length) return { moved: {}, box: null };

  // The box the arrangement takes, relative.
  const x0 = Math.min(...placed.map((p) => p.rx - p.c.w / 2));
  const y0 = Math.min(...placed.map((p) => p.ry - p.c.h / 2));
  const x1 = Math.max(...placed.map((p) => p.rx + p.c.w / 2));
  const y1 = Math.max(...placed.map((p) => p.ry + p.c.h / 2));
  const W = x1 - x0, H = y1 - y0;

  const still = cards.filter((c) => !moving.has(c.id)).map(rectOf);
  let want, prefer = "down";
  if (near && byId.has(near)) {
    const n = rectOf(byId.get(near));
    const mx = (n.x0 + n.x1) / 2;
    if (side === "above") { want = { x: mx - W / 2, y: n.y0 - 140 - H }; prefer = "up"; }
    else if (side === "right") { want = { x: n.x1 + 140, y: n.y0 }; prefer = "right"; }
    else if (side === "left") { want = { x: n.x0 - 140 - W, y: n.y0 }; prefer = "left"; }
    else { want = { x: mx - W / 2, y: n.y1 + 140 }; prefer = "down"; }
  } else if (at && Number.isFinite(at.x) && Number.isFinite(at.y)) {
    want = { x: at.x, y: at.y };
  } else if (whole) {
    want = { x: -W / 2, y: -H / 2 };
  } else {
    // Tidied where the cards already were.
    const mine = cards.filter((c) => moving.has(c.id)).map(rectOf);
    want = mine.length ? { x: Math.min(...mine.map((r) => r.x0)), y: Math.min(...mine.map((r) => r.y0)) } : { x: -W / 2, y: -H / 2 };
  }
  const spot = clearSpot(want, W, H, still, prefer);
  const dx = spot.x - x0, dy = spot.y - y0;
  const moved = {};
  for (const p of placed) moved[p.c.id] = [Math.round(p.rx + dx), Math.round(p.ry + dy)];
  return { moved, box: { x0: Math.round(spot.x), y0: Math.round(spot.y), x1: Math.round(spot.x + W), y1: Math.round(spot.y + H) } };
}

// ----------------------------------------------------------- what is where

/**
 * **The board in words** — what a chat needs to talk about a layout: the
 * clumps of cards as they sit, each named by the heading over it (or by what
 * it holds), and where on the board it is. Cards closer than a gap are one
 * clump; a heading just above a clump names it.
 */
export function describeLayout(cards, titleOf) {
  const list = cards.filter((c) => c.kind !== "heading");
  const heads = cards.filter((c) => c.kind === "heading");
  if (!list.length && !heads.length) return { said: "The board is empty.", groups: [] };
  const R = new Map(list.map((c) => [c.id, rectOf(c)]));
  const near = (a, b) => a.x0 < b.x1 + 140 && b.x0 < a.x1 + 140 && a.y0 < b.y1 + 140 && b.y0 < a.y1 + 140;
  const parent = new Map(list.map((c) => [c.id, c.id]));
  const find = (i) => { while (parent.get(i) !== i) { parent.set(i, parent.get(parent.get(i))); i = parent.get(i); } return i; };
  for (let i = 0; i < list.length; i += 1) {
    for (let j = i + 1; j < list.length; j += 1) {
      if (near(R.get(list[i].id), R.get(list[j].id))) parent.set(find(list[i].id), find(list[j].id));
    }
  }
  const clumps = new Map();
  for (const c of list) {
    const k = find(c.id);
    if (!clumps.has(k)) clumps.set(k, []);
    clumps.get(k).push(c);
  }
  const all = cards.map(rectOf);
  const B = { x0: Math.min(...all.map((r) => r.x0)), y0: Math.min(...all.map((r) => r.y0)), x1: Math.max(...all.map((r) => r.x1)), y1: Math.max(...all.map((r) => r.y1)) };
  const where = (r) => {
    const cx = (r.x0 + r.x1) / 2, cy = (r.y0 + r.y1) / 2;
    const fx = (cx - B.x0) / Math.max(1, B.x1 - B.x0), fy = (cy - B.y0) / Math.max(1, B.y1 - B.y0);
    const v = fy < 0.34 ? "top" : fy > 0.66 ? "bottom" : "middle";
    const h = fx < 0.34 ? "left" : fx > 0.66 ? "right" : "centre";
    return v === "middle" && h === "centre" ? "centre" : `${v} ${h}`;
  };
  const used = new Set();
  const groups = [...clumps.values()].map((members) => {
    const r = { x0: Math.min(...members.map((c) => R.get(c.id).x0)), y0: Math.min(...members.map((c) => R.get(c.id).y0)),
      x1: Math.max(...members.map((c) => R.get(c.id).x1)), y1: Math.max(...members.map((c) => R.get(c.id).y1)) };
    // A heading over it, or inside it, names it.
    const head = heads.filter((h) => !used.has(h.id) && h.x > r.x0 - 60 && h.x < r.x1 + 60 && h.y < r.y1 && h.y > r.y0 - 260)
      .sort((a, b) => Math.abs(a.y - r.y0) - Math.abs(b.y - r.y0))[0];
    if (head) used.add(head.id);
    const count = {};
    for (const c of members) count[c.kind] = (count[c.kind] || 0) + 1;
    const holds = ORDER.filter((k) => count[k]).map((k) => `${count[k]} ${count[k] === 1 ? k : KIND_NAMES[k].toLowerCase()}`).join(", ");
    return {
      ...(head ? { heading: head.text || head.title || "", heading_id: head.id } : {}),
      where: where(r), holds, box: [Math.round(r.x0), Math.round(r.y0), Math.round(r.x1), Math.round(r.y1)],
      cards: members.sort((a, b) => a.y - b.y || a.x - b.x).map((c) => c.id),
      _r: r,
    };
  }).sort((a, b) => Math.round(a._r.y0 / 300) - Math.round(b._r.y0 / 300) || a._r.x0 - b._r.x0);
  const lone = heads.filter((h) => !used.has(h.id));
  const said = groups.map((g) => {
    const names = g.cards.slice(0, 6).map((id) => titleOf(id)).filter(Boolean);
    return `${g.where}: ${g.heading ? `"${g.heading}" over ` : ""}${g.holds}${names.length ? ` (${names.join("; ")}${g.cards.length > 6 ? "; …" : ""})` : ""}`;
  });
  if (lone.length) said.push(`headings on their own: ${lone.map((h) => `"${h.text || h.title || ""}"`).join(", ")}`);
  for (const g of groups) delete g._r;
  return { said: said.join("\n"), groups, ...(lone.length ? { lone_headings: lone.map((h) => h.id) } : {}) };
}
