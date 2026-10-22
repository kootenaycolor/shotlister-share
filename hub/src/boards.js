/**
 * Boards — the pin board as a page any film can have, as many times as it likes.
 *
 * **Where this came from.** The Halcyon look board (2026-09-23/24) was one
 * page, built by hand from a prompt. His idea of 2026-09-24: the same board as
 * a page he can add to any project, private until he shares it, shaped by
 * chatting with Claude, with *everything in the film* ready to drag onto it —
 * reference images, shots, scenes, locations, days, people, documents (his
 * reminder, 2026-09-25: "that's just default, what it ships with").
 *
 * **What is standard and what is not.** The canvas, the kinds of card and the
 * saving are the same for every board. The *sorts* — Halcyon's Observe ↔
 * Move and A-cam / B-cam — are the board's own, kept on the board: two kinds
 * only, a line between two words and a row of columns, which between them
 * cover everything Halcyon did. Claude makes them up to fit the film when it
 * builds one; he adds one by asking, or from the board's own menu.
 *
 * Three doors write a board, and all three come through here: the page
 * (`public/board.js`, via `/f/<id>/api/board/<name>`), the MCP (`boardTool`),
 * and the Add screen, which makes the page itself (`newBoard`).
 *
 *   p/<film>/boards/<name>.json            the board — cards, threads, sorts
 *   p/<film>/boards/<name>.settings.json   who may edit it from a link
 *   p/<film>/boards/<name>.history/…       earlier copies, ≤300
 */

import { keys, names } from "../../relay/layout.js";
import { listAll } from "./films.js";
import { ORDER, KIND_NAMES, FOLDABLE, sizeOf, ratioOf, coverOf, keyOfSrc, arrange, clearSpot, describeLayout } from "./arrange.js";
import { SHARES } from "./front.js";
import { slugFrom } from "./paper.js";
import { diffBoard } from "../public/boardpatch.js";

export const BOARD_NAME = /^[a-z0-9][a-z0-9-]{0,80}$/;

/**
 * Halcyon's two sorts, for a board whose page says nothing about sorts.
 *
 * **The same list lives in `public/board.js`** — the browser and the worker
 * cannot share a file. It is only ever the answer for a page published before
 * sorts were the board's own (Halcyon), and is recognised there by its cards
 * carrying `data-obs` / `data-cam`. `obs` is kept the way Halcyon always kept
 * it — 1 is Observe, the left end — and `cam` as the column's id.
 */
export const LEGACY_SORTS = [
  {
    id: "obs", type: "line", name: "Observe ↔ Move", short: "Obs ↔ Move",
    ends: ["Observe", "Move"], under: ["still · long lens · from outside", "handheld · following · inside it"],
  },
  {
    id: "cam", type: "columns", name: "A-cam / B-cam", short: "A / B cam", none: "Undecided",
    cols: [
      { id: "mini", name: "A-cam", sub: "Alexa Mini + S16 zoom", chip: "A-CAM", pick: "A · Mini", tone: "gold" },
      { id: "both", name: "Both", sub: "either camera", chip: "A + B", pick: "Both", tone: "ink" },
      { id: "fx6", name: "B-cam", sub: "Sony FX6", chip: "B-CAM", pick: "B · FX6", tone: "steel" },
    ],
  },
];

/** Where one board's files live. The same shape the route has always used. */
export function boardKeys(project, name) {
  const base = `${keys.pages(project).replace(/pages\/$/, "boards/")}${name}`;
  return { board: `${base}.json`, settings: `${base}.settings.json`, history: `${base}.history/` };
}

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

export async function readBoard(env, project, name) {
  return (await readJson(env, boardKeys(project, name).board)) || {};
}

export async function readBoardSettings(env, project, name) {
  return (await readJson(env, boardKeys(project, name).settings)) || {};
}

const JSON_TYPE = { httpMetadata: { contentType: "application/json; charset=utf-8" } };

/**
 * Keep a board, and the one it replaces when that is worth keeping.
 *
 * **Lifted out of the route unchanged** so the MCP writes through exactly the
 * same history the page does: a copy when the last is ten minutes old, when a
 * save takes away more than a few pieces, and before every restore. The
 * oldest go past 300. `by` is whose save it was.
 */
export async function saveBoard(env, project, name, board, by, restoring = false) {
  const k = boardKeys(project, name);
  const now = new Date();
  const cur = await readJson(env, k.board);
  const pieces = (b) => ((b && b.added) || []).length + ((b && b.ties) || []).length + Object.keys((b && b.text) || {}).length;
  const due = cur && cur.at && (restoring || !cur.snap || now - Date.parse(cur.snap) > 10 * 60 * 1000 || pieces(board) < pieces(cur) - 3);
  if (due) {
    const id = String(cur.at).replace(/[:.]/g, "-");
    await env.BUCKET.put(`${k.history}${id}.json`, JSON.stringify(cur), {
      ...JSON_TYPE,
      customMetadata: { at: String(cur.at), by: String(cur.by || ""), cards: String((cur.added || []).length), threads: String((cur.ties || []).length) },
    });
    board.snap = now.toISOString();
    const all = await listAll(env, k.history);
    if (all.length > 300) {
      const oldest = all.map((o) => o.key).sort().slice(0, all.length - 300);
      await Promise.all(oldest.map((key) => env.BUCKET.delete(key)));
    }
  } else {
    board.snap = (cur && cur.snap) || now.toISOString();
  }
  board.at = now.toISOString();
  board.by = String(by || "");
  await env.BUCKET.put(k.board, JSON.stringify(board), JSON_TYPE);
  return board.at;
}

/** A board's live room (`boardroom.js`), or null on a portal without them. */
export function roomOf(env, project, name) {
  if (!env.BOARDS) return null;
  return env.BOARDS.get(env.BOARDS.idFromName(`${project}/${name}`));
}

/**
 * **The MCP's changes go through the board's room too**, as what it changed
 * rather than the whole board — so a chat arranging a board while somebody is
 * dragging cards on it leaves both, and everybody looking sees it land.
 * `before` is the board as it was read, untouched; `copy` keeps it in History
 * first (an arrange, a restore).
 */
export async function writeBoard(env, project, name, before, after, by, copy = false) {
  const room = roomOf(env, project, name);
  if (!room) return saveBoard(env, project, name, after, by, copy);
  const r = await room.fetch(new Request("https://room/patch", {
    method: "POST", body: JSON.stringify({ ops: diffBoard(before || {}, after), by, copy }),
    headers: { "content-type": "application/json", "x-board-project": project, "x-board-name": name },
  }));
  if (!r.ok) throw new Error(`The board would not take that (${r.status}).`);
  return (await r.json()).at;
}

/** The page a board belongs to, if it was made as a Board page. Halcyon's was not. */
export function boardSection(front, name) {
  return (front.sections || []).find((one) => one.type === "board" && one.board === name) || null;
}

/** A Board page by its address. */
export function boardAt(front, slug) {
  return (front.sections || []).find((one) => one.type === "board" && one.slug === slug) || null;
}

// ------------------------------------------------------------- a new board

/** Addresses a page may not take — the hub's own, and the four the record has. */
const TAKEN = new Set([
  "bible", "camera", "people", "documents", "crew", "api", "media", "pic", "share", "join",
  "visibility", "add", "order", "groups", "library", "refresh", "shotlist", "shots", "locations", "boards",
  "schedule", "icon", "cover", "camera-sheet", "file", "print", "edit",
]);
const NAMED = ["Visual Bible", "Camera Spec Sheet", "People", "Documents", "Shot List", "Locations",
  "Schedule", "Mood Boards", "Reference Images", "Add"];

/**
 * What is wrong with this name for a new page, or "" when nothing is. The
 * same refusals the Add screen makes, for the MCP's `add_board`.
 */
export function nameProblem(front, called) {
  const slug = slugFrom(called);
  if (!called) return "Give the board a name.";
  if (!slug) return `${called} does not make an address. Try plain words.`;
  const slugs = new Set([...TAKEN, ...(front.sections || []).map((one) => one.slug)]);
  const names = new Set([...NAMED, ...(front.sections || []).map((one) => one.name)].map((n) => String(n).toLowerCase()));
  if (slugs.has(slug) || names.has(called.toLowerCase())) return `${called} is already a page on this film.`;
  if ((front.sections || []).length >= 24) return "This film already carries as many pages as it holds. Remove one first.";
  return "";
}

/**
 * The row a new Board page is. **Its storage name is not its address**: a
 * page removed and made again under the same name must start empty, not find
 * the old board still sitting in the bucket. **It starts as his alone** —
 * his ruling, 2026-09-25.
 */
export function newBoard(called, share = "me") {
  const slug = slugFrom(called);
  const tail = [...crypto.getRandomValues(new Uint8Array(3))].map((b) => b.toString(16).padStart(2, "0")).join("");
  return {
    slug,
    name: called,
    title: "",
    by: "mcp",
    type: "board",
    source: "here",
    notion: false,
    board: `${slug}-${tail}`.slice(0, 80),
    share: SHARES.includes(share) ? share : "me",
  };
}

// ----------------------------------------------------------- the page itself

function esc(s) {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

/**
 * **A Board page draws itself.** Nothing is published into the bucket for it:
 * the page is this markup, made fresh each time, and everything on the board
 * lives in the board's own file. `board.js` does the rest.
 *
 * `data-api` is where it saves, said outright rather than worked out from the
 * address — a board reached as `/hla/moodboard` and one at `/f/<id>/moodboard`
 * save to the same place. `data-film` is the film's own base, where its
 * pictures and its change logs are read from for *From the Film*.
 */
export function boardMarkup(base, one, filmTitle) {
  return `<div class="lbweb"><div class="lbinner">
<style>
.lbweb{--ink:#F3EFE9;--gold:#D9A867;--rose:#E58FA8;--quiet:#9A9189;--rule:rgba(243,239,233,.14);
  font-family:RS,system-ui,sans-serif;color:var(--ink)}
.lbweb .lbinner{margin:0 auto;padding:0 20px;box-sizing:border-box}
.lbweb .lead{padding:14px 0 12px;display:flex;flex-wrap:wrap;gap:6px 18px;align-items:baseline}
.lbweb .eyebrow{font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:var(--gold);margin:0}
.lbweb .title{font-size:26px;line-height:1.1;font-weight:600;margin:0}
.lbweb .bd:not(.on){min-height:200px}
@media (max-width:700px){.lbweb .lbinner{padding:0 8px}.lbweb .lead{padding:6px 4px 10px}.lbweb .title{font-size:22px}}
</style>
<header class="lead">
  <h2 class="title">${esc(one.name)}</h2>
  <p class="eyebrow">${esc(filmTitle)}</p>
</header>
<section class="bd" data-bd="${esc(one.board)}" data-api="${esc(base)}/api/board/${esc(one.board)}" data-film="${esc(base)}" data-page="${esc(one.slug)}" data-lenses="[]" data-nolook></section>
</div></div>`;
}

// ------------------------------------------------------ fetching from the web

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
const PICTURE = { "image/jpeg": "jpg", "image/jpg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif", "image/heic": "heic" };
const MOVING = { "video/mp4": "mp4", "video/quicktime": "mov", "video/x-m4v": "mp4" };
const TYPE_OF = { jpg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif", heic: "image/heic", mp4: "video/mp4", mov: "video/quicktime" };

/** The largest picture or clip a board will hold. A worker reads a body whole. */
export const MOST_PICTURE = 25 * 1024 * 1024;
export const MOST_CLIP = 95 * 1024 * 1024;

/** Kept by its own contents, on the film, the way every file a person adds is. */
export async function keepBytes(env, project, extension, bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const file = `${hash.slice(0, 32)}.${extension}`;
  await env.BUCKET.put(keys.doc(project, file), bytes, {
    httpMetadata: { contentType: TYPE_OF[extension] || "application/octet-stream" },
  });
  return file;
}

/** What a picture or clip's extension should be, from its type or its name. */
export function extensionFor(type, name = "") {
  const t = String(type || "").split(";")[0].trim().toLowerCase();
  if (PICTURE[t]) return PICTURE[t];
  if (MOVING[t]) return MOVING[t];
  const ext = String(name).split(".").pop().toLowerCase();
  if (ext === "jpeg") return "jpg";
  if (ext === "m4v") return "mp4";
  return TYPE_OF[ext] ? ext : "";
}

/**
 * A YouTube or Vimeo address, as a player and a picture.
 *
 * **`youtube-nocookie`, as Halcyon's trailers are.** The portal lets only
 * YouTube, Vimeo and livid players through, and the board's own player list is
 * built from exactly this.
 */
export function videoOf(raw) {
  let url;
  try { url = new URL(raw); } catch { return null; }
  const host = url.hostname.replace(/^www\.|^m\./, "");
  let id = "";
  if (host === "youtu.be") id = url.pathname.slice(1).split("/")[0];
  else if (/(^|\.)youtube(-nocookie)?\.com$/.test(host)) {
    id = url.searchParams.get("v") || "";
    const m = url.pathname.match(/^\/(?:embed|shorts|live|v)\/([^/?#]+)/);
    if (!id && m) id = m[1];
  }
  if (id && /^[A-Za-z0-9_-]{6,20}$/.test(id)) {
    return { site: "YouTube", embed: `https://www.youtube-nocookie.com/embed/${id}`, thumb: `https://i.ytimg.com/vi/${id}/hqdefault.jpg`, page: `https://www.youtube.com/watch?v=${id}` };
  }
  if (host === "vimeo.com" || host === "player.vimeo.com") {
    const m = url.pathname.match(/(\d{5,})/);
    if (m) return { site: "Vimeo", embed: `https://player.vimeo.com/video/${m[1]}`, thumb: "", page: `https://vimeo.com/${m[1]}` };
  }
  return null;
}

async function grab(url, most) {
  const r = await fetch(url, { headers: { "user-agent": UA, accept: "*/*" }, redirect: "follow" });
  if (!r.ok) throw new Error(`${r.status}`);
  const size = Number(r.headers.get("content-length") || 0);
  if (size && size > most) throw new Error("too big");
  return r;
}

/** Fetch a picture from the web onto the film. Null when it cannot be had. */
export async function pictureInto(env, project, raw) {
  try {
    const own = await ownFile(env, project, raw);
    if (own) return own.kind === "still" ? own.file : null;
    const r = await grab(raw, MOST_PICTURE);
    const ext = extensionFor(r.headers.get("content-type"), new URL(raw).pathname);
    if (!ext || !PICTURE[TYPE_OF[ext]]) return null;
    const bytes = new Uint8Array(await r.arrayBuffer());
    if (bytes.length > MOST_PICTURE || bytes.length < 200) return null;
    return await keepBytes(env, project, ext, bytes);
  } catch {
    return null;
  }
}

function metaOf(html, names) {
  for (const name of names) {
    const re = new RegExp(`<meta[^>]+(?:property|name)=["']${name}["'][^>]*>`, "i");
    const tag = html.match(re);
    if (!tag) continue;
    const content = tag[0].match(/content=["']([^"']*)["']/i);
    if (content && content[1].trim()) return decode(content[1].trim());
  }
  return "";
}

function decode(s) {
  return String(s)
    .replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&apos;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)));
}

/** A Google Drive or Docs file's id, from any of the shapes its links take. */
export function driveIdOf(url) {
  const host = url.hostname.replace(/^www\./, "");
  if (host !== "drive.google.com" && host !== "docs.google.com") return "";
  const m = url.pathname.match(/\/d\/([-\w]{20,})/);
  const id = (m && m[1]) || url.searchParams.get("id") || "";
  return /^[-\w]{20,}$/.test(id) ? id : "";
}

/**
 * **Anything with an address, turned into something the board can hold.**
 *
 *   a YouTube or Vimeo address  → `video`: its player, its title, its picture
 *   a picture                   → `still`, fetched onto the film
 *   a clip                      → `clip`, fetched onto the film
 *   any other page              → `link`: its title, its site, its picture
 *
 * **Fetched here, never hot-linked.** A picture left on somebody else's server
 * is a board that goes blank the day they move it; one kept on the film is
 * the board's for good. What cannot be fetched still becomes a link, because
 * an address he pasted is never nothing.
 */
/**
 * **A file the film already holds is used where it is, never fetched.** A
 * picture off the Visual Bible or the Reference Images answers on the portal
 * only to somebody signed in, so fetching its address gets the sign-in page —
 * and it is the film's already. `pic/<hash>.jpg`, `media/<hash>.jpg`, a bare
 * `<hash>.jpg` or the whole portal address of one: if this film holds that
 * file, the card draws it from `pic/`, which answers from either store.
 * 2026-09-25, building the Call Her Back board from its bible.
 */
export async function ownFile(env, project, raw) {
  const said = String(raw || "").trim().split(/[?#]/)[0];
  const m = said.match(/(?:^|\/)(?:(pic|media)\/)?([0-9a-f]{32}\.([a-z0-9]{2,5}))$/i);
  if (!m || (!m[1] && said.includes("/"))) return null;
  const file = m[2].toLowerCase();
  const ext = m[3].toLowerCase() === "jpeg" ? "jpg" : m[3].toLowerCase();
  if (!TYPE_OF[ext]) return null;
  for (const folder of ["docs", "media"]) {
    if (await env.BUCKET.head(keys.inFolder(project, folder, file))) {
      return { kind: MOVING[TYPE_OF[ext]] ? "clip" : "still", src: `pic/${file}`, file };
    }
  }
  return null;
}

export async function fetchInto(env, project, raw) {
  const own = await ownFile(env, project, raw);
  if (own) return own;
  let url;
  try { url = new URL(String(raw || "").trim()); } catch { return null; }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  const href = url.toString();

  const video = videoOf(href);
  if (video) {
    let title = "", by = "", thumb = video.thumb;
    try {
      const o = video.site === "YouTube"
        ? `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(video.page)}`
        : `https://vimeo.com/api/oembed.json?url=${encodeURIComponent(video.page)}`;
      const r = await fetch(o, { headers: { "user-agent": UA } });
      if (r.ok) {
        const said = await r.json();
        title = String(said.title || "");
        by = String(said.author_name || "");
        if (said.thumbnail_url) thumb = String(said.thumbnail_url);
      }
    } catch { /* a video with no title is still a video */ }
    const kept = thumb ? await pictureInto(env, project, thumb) : null;
    return { kind: "video", href: video.page, embed: video.embed, title: title || `${video.site} video`, site: video.site, by, image: kept ? `pic/${kept}` : thumb };
  }

  // **A Google Drive file: its own preview picture, when Drive will give one.**
  // His question, 2026-09-25: is a script missing its preview because it is a
  // Drive link? Yes — Drive answers a file's page with a sign-in screen to
  // anybody but him. Its thumbnail address answers with the first page for a
  // file shared as *anyone with the link*, and with that same sign-in screen
  // for a private one, which is how the two are told apart: `closed` says so.
  const drive = driveIdOf(url);
  if (drive) {
    const kept = await pictureInto(env, project, `https://drive.google.com/thumbnail?id=${drive}&sz=w1600`);
    let title = "";
    if (kept) {
      try {
        const page = await fetch(href, { headers: { "user-agent": UA }, redirect: "follow" });
        if (page.ok && !/accounts\.google\./.test(page.url)) {
          const html = (await page.text()).slice(0, 600_000);
          title = metaOf(html, ["og:title"]) || decode(((html.match(/<title[^>]*>([^<]*)<\/title>/i) || [])[1] || "").trim());
        }
      } catch { /* the picture is the part that matters */ }
    }
    return {
      kind: "link", href, site: "Google Drive",
      title: title.replace(/\s+-\s+Google (Drive|Docs|Sheets|Slides)$/i, "").slice(0, 140) || "Google Drive",
      image: kept ? `pic/${kept}` : "",
      ...(kept ? {} : { closed: true }),
    };
  }

  let r;
  try { r = await grab(href, MOST_CLIP); } catch { return { kind: "link", href, title: url.hostname.replace(/^www\./, ""), site: url.hostname.replace(/^www\./, "") }; }
  const type = String(r.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
  const ext = extensionFor(type, url.pathname);
  if (ext && (PICTURE[type] || MOVING[type] || (!type.startsWith("text/") && TYPE_OF[ext]))) {
    const bytes = new Uint8Array(await r.arrayBuffer());
    const moving = TYPE_OF[ext].startsWith("video/");
    if (bytes.length > (moving ? MOST_CLIP : MOST_PICTURE)) return { kind: "link", href, title: url.pathname.split("/").pop() || url.hostname, site: url.hostname };
    const file = await keepBytes(env, project, ext, bytes);
    return { kind: moving ? "clip" : "still", file, src: `pic/${file}`, href };
  }
  let html = "";
  try { html = (await r.text()).slice(0, 1_500_000); } catch { html = ""; }
  const title = metaOf(html, ["og:title", "twitter:title"]) || decode(((html.match(/<title[^>]*>([^<]*)<\/title>/i) || [])[1] || "").trim()) || url.hostname;
  const site = metaOf(html, ["og:site_name"]) || url.hostname.replace(/^www\./, "");
  let image = metaOf(html, ["og:image:secure_url", "og:image", "twitter:image", "twitter:image:src"]);
  if (image) {
    try { image = new URL(image, href).toString(); } catch { image = ""; }
  }
  const kept = image ? await pictureInto(env, project, image) : null;
  return { kind: "link", href, title: title.slice(0, 140), site: site.slice(0, 60), image: kept ? `pic/${kept}` : "" };
}

// ------------------------------------------------------------- the MCP's half
//
// **Anything he can do on a board by hand, a chat can do here.** His ask,
// 2026-09-25: "make the MCP fully functional inside the boards." The board's
// own buttons and this door write the same file through the same `saveBoard`,
// make cards from the film the same way (`filmCard` is `cardFor` in
// `public/board.js`), and file a picture on a shot through the same
// `fileOnShot`. What is left out on purpose is only what is one person's view
// of a board and not the board: which sort is on screen, and Show.

const KINDS = ["note", "heading", "still", "clip", "video", "link", "ref", "shot", "scene", "location", "day", "person", "doc", "gear", "idea"];
const LIVE = new Set(["shot", "scene", "location", "day"]);

/**
 * The cards a published page carries (Halcyon's), read the way `readArticle`
 * in `public/board.js` reads them — trailers, stills and clips included, so a
 * copy of one onto another board is the whole card.
 */
function authoredOf(html) {
  const out = [];
  const attr = (tag, name) => decode(((tag.match(new RegExp(`\\s${name}="([^"]*)"`)) || [])[1]) || "");
  const words = (s) => decode(String(s || "").replace(/<[^>]+>/g, "").trim());
  const re = /<article[^>]*class="bd-n"[^>]*>([\s\S]*?)<\/article>/g;
  let m;
  while ((m = re.exec(html))) {
    const tag = m[0].slice(0, m[0].indexOf(">") + 1);
    const inner = m[1];
    const figs = [], clips = [];
    for (const f of inner.match(/<figure[\s\S]*?<\/figure>/g) || []) {
      const v = (f.match(/<video[^>]*>/) || [])[0];
      const im = (f.match(/<img[^>]*>/) || [])[0];
      const cap = words((f.match(/<figcaption[^>]*>([\s\S]*?)<\/figcaption>/) || [])[1]);
      const from = attr(f.slice(0, f.indexOf(">") + 1), "data-from");
      if (v && attr(v, "src")) clips.push({ clip: true, from, src: attr(v, "src"), poster: attr(v, "poster"), cap });
      else if (im && attr(im, "src")) figs.push({ from, src: attr(im, "src"), cap });
    }
    const spec = (((inner.match(/<ul[^>]*class="bd-spec"[^>]*>([\s\S]*?)<\/ul>/) || [])[1] || "").match(/<li[^>]*>[\s\S]*?<\/li>/g) || []).map(words);
    const obs = attr(tag, "data-obs");
    out.push({
      id: attr(tag, "id"), kind: attr(tag, "data-kind") || "idea",
      title: words((inner.match(/<h3[^>]*>([\s\S]*?)<\/h3>/) || [])[1]) || attr(tag, "id"),
      kicker: words((inner.match(/<p[^>]*class="bd-k"[^>]*>([\s\S]*?)<\/p>/) || [])[1]),
      sub: words((inner.match(/<p[^>]*class="bd-s"[^>]*>([\s\S]*?)<\/p>/) || [])[1]),
      players: (inner.match(/<iframe[^>]*>/g) || []).map((t) => ({ src: attr(t, "src"), title: attr(t, "title") || "Video" })),
      figs, clips, spec,
      x: Number(attr(tag, "data-x")) || 0, y: Number(attr(tag, "data-y")) || 0,
      obs: obs === "" ? null : Number(obs), cam: attr(tag, "data-cam"),
    });
  }
  return out;
}

/** Which board a published page carries (`class="bd" data-bd="…"`), or "". */
export function boardIn(html) {
  const m = String(html || "").match(/class="bd"[^>]*data-bd="([^"]+)"/);
  return m && BOARD_NAME.test(m[1]) ? m[1] : "";
}

/**
 * **A published board, whole, in the shape a stored one has** — for the
 * iPhone (Ref 1562). A board published as a page (Halcyon's look board)
 * keeps its cards in the page and only what was changed or added since in
 * `boards/<name>.json`, so that record alone draws an empty board. Here the
 * page's own cards and threads are put into `added` and `ties` beside the
 * stored ones, each card carrying its sort values the way `valsFrom` in
 * `public/board.js` reads them, and the stored changes (`free`, `obs`, `cam`,
 * `vals`, `text`, `cut`, `labels`, `gone`…) stay as they are, to be laid over
 * them by id exactly as the page does. Read only: nothing here is saved.
 */
export function publishedBoard(board, html) {
  const own = board || {};
  const cards = authoredOf(html).map((c) => {
    const vals = {};
    if (typeof c.obs === "number" && Number.isFinite(c.obs)) vals.obs = 1 - Math.min(1, Math.max(0, c.obs));
    if (c.cam) vals.cam = c.cam;
    const card = { id: c.id, kind: c.kind, title: c.title, x: c.x, y: c.y, published: true };
    if (c.kicker) card.kicker = c.kicker;
    if (c.sub) card.sub = c.sub;
    if (c.figs.length) card.figs = c.figs;
    if (c.clips.length) card.clips = c.clips;
    if (c.players.length) card.players = c.players;
    if (c.spec.length) { card.spec = c.spec; card.facts = c.spec; }
    if (Object.keys(vals).length) card.vals = vals;
    return card;
  });
  return {
    ...own,
    added: [...cards, ...(own.added || [])],
    ties: [...authoredTiesOf(html), ...(own.ties || [])],
    lenses: sortsOf(own, html),
  };
}

/** The threads a published page was strung with. */
function authoredTiesOf(html) {
  const list = ((html || "").match(/<ol[^>]*class="bd-ties"[^>]*>([\s\S]*?)<\/ol>/) || [])[1] || "";
  return (list.match(/<li[^>]*>[\s\S]*?<\/li>/g) || []).map((li) => {
    const tag = li.slice(0, li.indexOf(">") + 1);
    const a = (tag.match(/data-a="([^"]*)"/) || [])[1] || "";
    const b = (tag.match(/data-b="([^"]*)"/) || [])[1] || "";
    return { a, b, label: decode(li.replace(/<[^>]+>/g, "").trim()) };
  }).filter((t) => t.a && t.b);
}

function sortsOf(board, html) {
  if (Array.isArray(board.lenses)) return board.lenses;
  const said = (html.match(/data-lenses="([^"]*)"/) || [])[1];
  if (said !== undefined) {
    try { return JSON.parse(decode(said)); } catch { return []; }
  }
  return /data-(obs|cam)=/.test(html) ? LEGACY_SORTS : [];
}

/** A card's place on each sort, in words: `0.3` along a line, a column's name. */
function placesOf(sorts, get) {
  const out = {};
  for (const s of sorts) {
    const v = get(s);
    if (s.type === "line") {
      if (typeof v === "number") out[s.name] = Math.round(v * 100) / 100;
    } else if (v) {
      const col = (s.cols || []).find((c) => c.id === v);
      out[s.name] = col ? col.name : v;
    }
  }
  return out;
}

/** Where a sort keeps one card's value, legacy included. */
function valueOf(board, sort, card, authored) {
  if (authored) {
    if (sort.id === "obs") {
      const o = board.obs && card.id in board.obs ? board.obs[card.id] : card.obs;
      return typeof o === "number" ? 1 - o : null;
    }
    if (sort.id === "cam") return (board.cam && card.id in board.cam ? board.cam[card.id] : card.cam) || "";
    return board.vals && board.vals[sort.id] ? board.vals[sort.id][card.id] : null;
  }
  if (sort.id === "obs") return typeof card.obs === "number" ? 1 - card.obs : null;
  if (sort.id === "cam") return card.cam || "";
  return card.vals ? card.vals[sort.id] : null;
}

function setValue(board, sort, card, authored, value) {
  if (authored) {
    if (sort.id === "obs") { board.obs = { ...(board.obs || {}), [card.id]: 1 - value }; return; }
    if (sort.id === "cam") { board.cam = { ...(board.cam || {}), [card.id]: value }; return; }
    board.vals = board.vals || {};
    board.vals[sort.id] = { ...(board.vals[sort.id] || {}), [card.id]: value };
    return;
  }
  if (sort.id === "obs") { card.obs = 1 - value; return; }
  if (sort.id === "cam") { card.cam = value; return; }
  card.vals = { ...(card.vals || {}), [sort.id]: value };
}

/** One id or a list of them, as a list. */
const idList = (v) => (Array.isArray(v) ? v : v === undefined || v === null || v === "" ? [] : [v]).map(String);

function idFor(prefix) {
  return prefix + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
}

function sortId(name, taken) {
  let base = slugFrom(name).slice(0, 24) || "sort";
  if (base === "obs" || base === "cam") base = `${base}-2`;
  let id = base, i = 2;
  while (taken.has(id)) id = `${base}-${i++}`;
  taken.add(id);
  return id;
}

const TONES = ["gold", "steel", "sage", "rose", "ink"];

/**
 * Sorts as asked for, keeping every id that already exists — a sort or a
 * column renamed in the same breath keeps its cards where they were only if
 * its old name is sent as `was`. **Positions are not ids**: reading them that
 * way would move every card one column over when one in the middle went.
 */
function sortsFrom(asked, had) {
  const taken = new Set();
  const out = [];
  for (const s of asked || []) {
    const name = String(s.name || "").replace(/\s+/g, " ").trim().slice(0, 40);
    if (!name) continue;
    const type = s.type === "columns" ? "columns" : "line";
    const was = had.find((h) => h.name === (s.was || name) && h.type === type && !taken.has(h.id));
    const id = was ? was.id : sortId(name, taken);
    taken.add(id);
    if (type === "line") {
      const ends = Array.isArray(s.ends) && s.ends.length === 2 ? s.ends.map((e) => String(e).slice(0, 24)) : (was && was.ends) || ["Less", "More"];
      const under = Array.isArray(s.under) && s.under.length === 2 ? s.under.map((e) => String(e).slice(0, 60)) : (was && was.under) || undefined;
      out.push({ id, type, name, ...(s.short ? { short: String(s.short).slice(0, 16) } : was && was.short ? { short: was.short } : {}), ends, ...(under ? { under } : {}) });
    } else {
      const colTaken = new Set();
      const cols = [];
      (Array.isArray(s.columns) ? s.columns : []).forEach((raw, i) => {
        // **A column named by a bare word is a word, not an object.** Read as
        // one, `"After".sub` is String's own `sub` method, and every column
        // came out subtitled "function sub() { [native code] }" (2026-09-25).
        const c = typeof raw === "string" ? { name: raw } : raw && typeof raw === "object" ? raw : {};
        const cname = String(c.name || "").replace(/\s+/g, " ").trim().slice(0, 30);
        if (!cname) return;
        const cwas = was && (was.cols || []).find((x) => x.name === (c.was || cname) && !colTaken.has(x.id));
        const cid = cwas ? cwas.id : sortId(cname, colTaken);
        colTaken.add(cid);
        const kept = cwas && typeof cwas.sub === "string" && !cwas.sub.startsWith("function ") ? cwas.sub : "";
        const sub = Object.hasOwn(c, "sub") ? String(c.sub || "").slice(0, 60) : kept;
        cols.push({
          ...(cwas || {}), id: cid, name: cname, sub: sub || undefined,
          tone: (cwas && cwas.tone) || TONES[i % TONES.length],
        });
      });
      out.push({ id, type, name, ...(s.short ? { short: String(s.short).slice(0, 16) } : was && was.short ? { short: was.short } : {}), ...(was && was.none ? { none: was.none } : {}), cols });
    }
  }
  return out;
}

// ------------------------------------------------------ cards from the film
//
// **`cardFor` in `public/board.js`, on the server.** The same view of the film
// the board's *From the Film* panel reads (the engine's `view`, asked in the
// worker by `filmView` in `mcp.js`), turned into the same cards — so a shot an
// AI puts on a board shows its frames and its fields the moment it lands,
// rather than a bare number until a browser opens it. **Picture addresses are
// relative** (`media/…`), as `pic/…` always has been: a board is reached at
// `/f/<id>/…`, at the film's own name, and on the share host, and a relative
// address is right on all three.

const clipM = (m) => Boolean(m && (m.kind === "video" || /\.(mp4|mov|m4v)$/i.test(m.filename || "")));
const pictureM = (m) => Boolean(m && !clipM(m) && (m.kind === "image" || m.kind === "gif" || m.kind === "photo" || /\.(jpe?g|png|webp|gif|heic)$/i.test(m.filename || "")));
const extM = (m) => String(m.filename || "").split(".").pop().toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) || "png";
const srcM = (m) => (m && m.hash ? `media/${m.hash.slice(0, 32)}.${clipM(m) ? "mp4" : extM(m)}` : "");
const posterM = (m) => (m && m.hash ? `media/${m.hash.slice(0, 32)}.jpg` : "");

function figM(m, from) {
  if (clipM(m)) return { clip: true, src: srcM(m), poster: posterM(m), from, hash: m.hash, cap: m.caption || "" };
  if (pictureM(m)) return { src: srcM(m), from, hash: m.hash, cap: m.caption || "" };
  return null;
}
function mediaM(list, from) {
  const all = (list || []).map((m) => figM(m, from)).filter(Boolean);
  const first = all[0];
  return { figs: all.filter((f) => !f.clip).slice(0, 24), clips: all.filter((f) => f.clip).slice(0, 12),
    src: first ? (first.clip ? first.poster : first.src) : "" };
}
function shotRows(model) {
  const out = [];
  for (const g of model.groups || []) for (const row of g.rows || []) out.push(row);
  return out;
}
const dayOf = (it) => (typeof it.day === "string" ? it.day : it.day && it.day.label ? it.day.label : "");

/**
 * **A shoot day's date in words, spelled out — "Mon, Nov 2".** Not asked of
 * `toLocaleDateString`: a worker may carry no locale data, and the MCP
 * (`dayWords` in `src/boards.js`) and this page must write a day card the
 * same, or every day card a chat makes is rewritten the first time a board
 * opens. **The same function lives in both files; change one, change both.**
 */
function dayWords(iso) {
  const m = String(iso || "").match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return String(iso || "");
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return `${["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()]}, ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()]} ${d.getUTCDate()}`;
}

/** A card of the film's, from what the film says now. `cardFor` in `public/board.js`. */
export function filmCard(type, it, model) {
  if (type === "shot") {
    const got = mediaM([...(it.stills || [])].sort((a, b) => (b.key ? 1 : 0) - (a.key ? 1 : 0)), "Frames");
    const scene = (model.scenes || []).find((x) => x.id === it.sceneId);
    const list = (v) => [].concat(v || []).filter(Boolean).join(", ");
    const fields = [
      ["Size", it.size], ["Angle", list(it.angle)], ["Lens", it.lens], ["Movement", it.movement], ["Support", it.support],
      ["Scene", scene ? [scene.number, scene.heading || scene.title].filter(Boolean).join("  ") : ""],
      ["Day", dayOf(it)],
      ["Unit", typeof it.unit === "string" ? it.unit : ""], ["Priority", it.priority], ["Tags", list(it.tags)],
    ].filter(([, v]) => v);
    return { kind: "shot", live: { type, id: it.shot, key: it.number }, title: it.title || it.description || `Shot ${it.number}`,
      kicker: `Shot ${it.number}`, sub: it.title && it.description ? it.description.slice(0, 220) : "",
      fields, facts: [it.size, it.lens, it.movement, it.support].filter(Boolean), said: it.notes || "",
      figs: got.figs, clips: got.clips, src: got.src };
  }
  if (type === "scene") {
    const got = mediaM(it.attachments, "Attachments");
    return { kind: "scene", live: { type, id: it.id, key: it.number }, title: it.heading || it.title || `Scene ${it.number}`,
      kicker: `Scene ${it.number}`, sub: (it.description || "").slice(0, 200),
      facts: [it.count ? `${it.count} shot${it.count === 1 ? "" : "s"}` : "", it.timeOfDay, it.shootingLocation].filter(Boolean),
      said: it.script || "", figs: got.figs, clips: got.clips, src: got.src };
  }
  if (type === "location") {
    const got = mediaM(it.media, "Photos");
    return { kind: "location", live: { type, id: it.id, key: it.name }, title: it.fullName || it.name || "Location",
      kicker: "Location", sub: it.effectiveAddress || it.address || "", said: it.effectiveNotes || it.notes || "",
      facts: [(it.scenes || []).length ? `${it.scenes.length} scene${it.scenes.length === 1 ? "" : "s"}` : ""].filter(Boolean),
      figs: got.figs, clips: got.clips, src: got.src };
  }
  if (type === "day") {
    let when = "";
    when = dayWords(it.date);
    return { kind: "day", live: { type, id: it.id, key: it.label }, title: it.label || "Day", kicker: "Schedule",
      sub: when, facts: [it.count ? `${it.count} shot${it.count === 1 ? "" : "s"}` : ""].filter(Boolean) };
  }
  return null;
}
function personCard(p) {
  return { kind: "person", live: { type: "person", key: p.name }, title: p.name,
    kicker: [p.role, p.department].filter(Boolean).join(" · ") || "Crew", sub: p.company || "" };
}
function docCard(d) {
  return { kind: "doc", live: { type: "doc", key: d.name }, title: d.name, kicker: "Document",
    href: d.url || (d.file ? `pic/${d.file}` : "") };
}

/** The film's thing a person named — a shot or scene by number, a location or day by name — or by id. */
function inFilm(model, type, key, id) {
  const same = (a, b) => String(a || "").trim().toLowerCase() === String(b || "").trim().toLowerCase();
  if (type === "shot") {
    const all = shotRows(model);
    return all.find((r) => id && r.shot === id) || all.find((r) => same(r.number, key)) || null;
  }
  const list = type === "scene" ? (model.scenes || []).filter((x) => !x.archived)
    : type === "location" ? model.locations || [] : type === "day" ? model.days || [] : [];
  const byId = id && list.find((x) => x.id === id);
  if (byId) return byId;
  if (type === "scene") return list.find((x) => same(x.number, key)) || null;
  if (type === "location") return list.find((x) => same(x.name, key) || same(x.fullName, key)) || null;
  return list.find((x) => same(x.label, key)) || null;
}

/** Every picture and clip on Shotlister's own mood boards — the panel's *Reference Images*. */
function moodPictures(model) {
  const out = [];
  for (const b of model.boards || []) {
    for (const m of b.media || []) {
      const f = figM(m, b.name);
      if (!f) continue;
      out.push({ id: m.hash.slice(0, 12), board: b.name, m, f });
    }
  }
  return out;
}

/** A mood board's picture as a card, exactly as the panel lays one on. */
function pictureCard(p) {
  const { m, f, board } = p;
  return f.clip
    ? { kind: "clip", src: f.src, poster: f.poster, hash: m.hash, title: m.caption || board, cap: m.caption || "", kicker: board }
    : { kind: "still", src: f.src, hash: m.hash, title: m.caption || board, cap: m.caption || "", kicker: board };
}

/** Any picture the film holds, by the start of its hash: mood boards first, then shots, scenes, locations. */
function anyPicture(model, id) {
  const want = String(id || "").trim().toLowerCase();
  if (want.length < 8) return null;
  const hit = moodPictures(model).find((p) => p.m.hash.startsWith(want));
  if (hit) return hit;
  const lists = [
    ...shotRows(model).map((r) => [r.stills, `Shot ${r.number}`]),
    ...(model.scenes || []).map((s) => [s.attachments, `Scene ${s.number}`]),
    ...(model.locations || []).map((l) => [l.media, l.name]),
  ];
  for (const [list, from] of lists) {
    for (const m of list || []) {
      if (m && m.hash && m.hash.startsWith(want)) {
        const f = figM(m, from);
        if (f) return { id: want, board: from, m, f };
      }
    }
  }
  return null;
}

// ---------------------------------------------------------- Add to Shot

const MEDIA_MIME = { png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", heic: "image/heic", webp: "image/webp", mp4: "video/mp4", mov: "video/quicktime", m4v: "video/x-m4v" };

/**
 * **Posters still owed.** A clip filed on a shot needs a poster — its first
 * frame — beside it in `media/`, or every list on the Mac and the iPhone draws
 * it blank. The board makes one in the browser (`posterOf` in
 * `public/board.js`) because it can play the clip; a chat cannot, and neither
 * can a worker. So a clip filed without one is written down here, per film,
 * and the next board an editor opens on that film makes the poster and files
 * it through the same `attach` door (`posters` on the board's GET). Filing
 * its poster crosses it off. `{file: {src, shot}}`.
 */
export const postersKey = (project) => `${keys.pages(project).replace(/pages\/$/, "boards/")}.posters-owed.json`;

export async function postersOwed(env, project) {
  return (await readJson(env, postersKey(project))) || {};
}

async function owePoster(env, project, owed, file) {
  const all = await postersOwed(env, project);
  if (owed) {
    if (all[file] && all[file].shot === owed.shot) return;
    all[file] = owed;
  } else {
    if (!(file in all)) return;
    delete all[file];
  }
  await env.BUCKET.put(postersKey(project), JSON.stringify(all), JSON_TYPE);
}

/**
 * **Add to Shot** — a still or clip on a board, filed on a shot in the film,
 * when he asks and only then (his question, 2026-09-25). Lifted out of the
 * worker's `/attach` route so the board's own menu and a chat go one way:
 * the file is put where the film's own pictures live (`media/`, under the
 * relay's name for it) so the Mac and the phone fetch it like any other, a
 * clip's poster beside it; then the engine files it on the shot as a change
 * log in this person's name (`attachToShot` in `mcp.js`).
 *
 * `asked` is `{src, shot, caption?, hash?, poster?, name?}` — `hash` the
 * film's whole hash, for a picture that came from the film. Throws an error
 * carrying `status` and `said` when it cannot.
 */
export async function fileOnShot(env, project, who, ctx, asked, attachToShot) {
  const no = (status, said) => Object.assign(new Error(said), { status, said });
  const shot = String((asked && asked.shot) || "").trim();
  if (!shot || shot.length > 16) throw no(400, "Which shot?");
  const where = String((asked && asked.src) || "");
  const file = where.split("?")[0].split("/").pop() || "";
  if (!new RegExp(names.medium).test(file)) throw no(400, "That is not a picture on this film.");
  const ext = file.split(".").pop().toLowerCase();
  const moving = ext === "mp4" || ext === "mov" || ext === "m4v";
  if (!moving && !/^(jpe?g|png|gif|webp|heic)$/.test(ext)) throw no(415, "Only pictures and clips go on a shot.");
  const fromFilm = /(^|\/)media\/[^/]+$/.test(where.split("?")[0]);
  let hash = String((asked && asked.hash) || "").toLowerCase();
  let size = 0;
  if (fromFilm) {
    // Already one of the film's own files: nothing to move.
    if (!/^[0-9a-f]{64}$/.test(hash) || !hash.startsWith(file.slice(0, 32))) throw no(400, "That picture came without its hash.");
    const head = await env.BUCKET.head(keys.medium(project, file));
    if (!head) throw no(404, "No such picture.");
    size = head.size;
  } else {
    const got = await env.BUCKET.get(keys.doc(project, file));
    if (!got) throw no(404, "No such picture.");
    const bytes = new Uint8Array(await got.arrayBuffer());
    hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) => b.toString(16).padStart(2, "0")).join("");
    if (!hash.startsWith(file.slice(0, 32))) throw no(400, "That file is not what its name says.");
    size = bytes.length;
    if (!(await env.BUCKET.head(keys.medium(project, file)))) {
      await env.BUCKET.put(keys.medium(project, file), bytes, { httpMetadata: { contentType: MEDIA_MIME[ext] || "application/octet-stream" } });
    }
    // A clip is drawn by its poster everywhere a list shows it.
    const poster = String((asked && asked.poster) || "").split("/").pop() || "";
    let posted = false;
    if (moving && /^[0-9a-f]{32}\.jpg$/.test(poster)) {
      const still = await env.BUCKET.get(keys.doc(project, poster));
      if (still) {
        await env.BUCKET.put(keys.medium(project, `${file.slice(0, 32)}.jpg`), await still.arrayBuffer(), { httpMetadata: { contentType: "image/jpeg" } });
        posted = true;
      }
    }
    if (moving) await owePoster(env, project, posted ? null : { src: `pic/${file}`, shot }, file);
  }
  const caption = String((asked && asked.caption) || "").slice(0, 200);
  const title = String((asked && asked.name) || "").replace(/[\\/:*?"<>|\n\r]+/g, " ").trim().slice(0, 60) || (moving ? "Board Clip" : "Board Still");
  try {
    return { shot, said: await attachToShot(env, project, who, ctx, { shot, hash, name: `${title}.${ext}`, size, caption }) };
  } catch (error) {
    throw no(400, String((error && (error.said || error.message)) || error));
  }
}

// ---------------------------------------------------------------- history

/** A board's earlier copies, newest first, as its History panel lists them. */
export async function boardVersions(env, project, name) {
  const prefix = boardKeys(project, name).history;
  const found = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000, include: ["customMetadata"] });
    found.push(...page.objects);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return found.map((o) => ({
    id: o.key.slice(prefix.length).replace(/\.json$/, ""),
    at: (o.customMetadata && o.customMetadata.at) || "",
    by: (o.customMetadata && o.customMetadata.by) || "",
    cards: Number((o.customMetadata && o.customMetadata.cards) || 0),
    threads: Number((o.customMetadata && o.customMetadata.threads) || 0),
  })).sort((p, q) => (p.at < q.at ? 1 : -1));
}

/** The id History will give the board as it stands, once a save copies it. */
const versionId = (board) => (board && board.at ? String(board.at).replace(/[:.]/g, "-") : "");

// ------------------------------------------------------------ pictures, seen

export function base64Of(bytes) {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

const MOST_SEEN = 1_500_000;

/** A card's picture as the chat can see it, or why not. */
async function seen(env, project, card) {
  const src = coverOf(card) || (card.kind === "clip" ? "" : card.src || "");
  if (!src) return { said: `${card.id}: no picture` };
  let bytes, type;
  const key = keyOfSrc(project, src);
  if (key) {
    const got = await env.BUCKET.get(key);
    if (!got) return { said: `${card.id}: its picture is missing` };
    if (got.size > MOST_SEEN) return { said: `${card.id}: its picture is too big to send (${Math.round(got.size / 1e6)} MB)` };
    bytes = new Uint8Array(await got.arrayBuffer());
    type = (got.httpMetadata && got.httpMetadata.contentType) || TYPE_OF[src.split(".").pop().toLowerCase()] || "image/jpeg";
  } else if (/^https:\/\//.test(src)) {
    try {
      const r = await grab(src, MOST_SEEN);
      bytes = new Uint8Array(await r.arrayBuffer());
      type = String(r.headers.get("content-type") || "image/jpeg").split(";")[0];
    } catch { return { said: `${card.id}: its picture could not be fetched` }; }
    if (bytes.length > MOST_SEEN) return { said: `${card.id}: its picture is too big to send` };
  } else {
    return { said: `${card.id}: no picture` };
  }
  if (!/^image\/(jpeg|png|gif|webp)$/.test(type)) return { said: `${card.id}: its picture is a ${type}, which cannot be sent` };
  return { image: { type: "image", data: base64Of(bytes), mimeType: type } };
}

// ------------------------------------------------------------------ the tools

/**
 * `boards`, `board`, `add_board`, `set_board` and `arrange_board` — the
 * board, for an AI.
 *
 * `found` is the open film and the caller's part in it; `who` the caller; and
 * `admin` whether it is him. `deps` carries what lives in `mcp.js`: reading
 * a published page (`pageHtml`, for Halcyon's board), the film's view
 * (`filmView`), and filing a picture on a shot (`attachToShot`).
 */
export async function boardTool(env, found, who, admin, name, args, deps) {
  const { frontOf, saveFront, pageHtml, boardOpen, refuse, filmView, attachToShot, ctx } = deps;
  const front = await frontOf(env, found.project);
  const at = (slug) => `https://your-domain.example/f/${found.project}/${slug}`;
  const open = (one) => boardOpen(one, who, admin);
  let model = null;
  const film = async () => {
    if (!model) {
      try { model = (filmView && (await filmView())) || {}; } catch { model = {}; }
    }
    return model;
  };

  // A published page carrying a board — Halcyon's — is a board too.
  let pubs = null;
  const published = async () => {
    if (pubs) return pubs;
    pubs = [];
    for (const one of front.sections || []) {
      if (one.type === "board") continue;
      const html = await pageHtml(env, found.project, one.slug);
      const m = html && html.match(/class="bd"[^>]*data-bd="([^"]+)"/);
      if (m) pubs.push({ one, board: m[1], html });
    }
    return pubs;
  };

  if (name === "boards") {
    if (args.from_the_film) return await fromTheFilm(String(args.from_the_film));
    const list = [];
    for (const one of (front.sections || []).filter((s) => s.type === "board" && open(s))) {
      const b = await readBoard(env, found.project, one.board);
      list.push({ board: one.name, slug: one.slug, address: at(one.slug), who_can_open: { me: "only him", crew: "anyone signed in to the film", link: "anyone with the link" }[one.share], cards: (b.added || []).length, threads: (b.ties || []).length, sorts: (Array.isArray(b.lenses) ? b.lenses : []).map((s) => s.name) });
    }
    for (const p of await published()) {
      const b = await readBoard(env, found.project, p.board);
      list.push({ board: p.one.name, slug: p.one.slug, address: at(p.one.slug), who_can_open: "whoever can open the page", cards: authoredOf(p.html).length + (b.added || []).length, threads: (b.ties || []).length, sorts: sortsOf(b, p.html).map((s) => s.name), published: true });
    }
    return JSON.stringify(list.length ? list : "No boards on this film yet. `add_board` makes one.", null, 1);
  }

  /** What the board's own *From the Film* panel offers, tab by tab. */
  async function fromTheFilm(tab) {
    const t = tab.toLowerCase();
    if (t === "people") return JSON.stringify((front.crew || []).map((p) => ({ person: p.name, role: [p.role, p.department].filter(Boolean).join(" · ") })), null, 1);
    if (t === "documents" || t === "docs") return JSON.stringify((front.documents || []).map((d) => ({ doc: d.name, ...(d.url ? { url: d.url } : {}) })), null, 1);
    const m = await film();
    if (t === "images" || t === "reference images" || t === "mood boards") {
      const out = [];
      for (const b of m.boards || []) {
        const pics = (b.media || []).map((x) => ({ x, f: figM(x, b.name) })).filter((p) => p.f);
        if (!pics.length) continue;
        out.push({ mood_board: b.name, pictures: pics.map((p) => ({ picture: p.x.hash.slice(0, 12), kind: p.f.clip ? "clip" : "still", ...(p.x.caption ? { caption: p.x.caption } : {}) })) });
      }
      return JSON.stringify(out.length ? out : "No reference images on this film's mood boards.", null, 1);
    }
    if (t === "shots") {
      return JSON.stringify(shotRows(m).map((r) => ({ shot: r.number, title: r.title || r.description || "",
        facts: [r.size, r.lens, r.movement].filter(Boolean).join(" · "), frames: (r.stills || []).map((x) => x.hash && x.hash.slice(0, 12)).filter(Boolean) })), null, 1);
    }
    if (t === "scenes") return JSON.stringify((m.scenes || []).filter((x) => !x.archived).map((x) => ({ scene: x.number, heading: x.heading || x.title || "", shots: x.count || 0 })), null, 1);
    if (t === "locations") return JSON.stringify((m.locations || []).map((x) => ({ location: x.name, ...(x.fullName && x.fullName !== x.name ? { full_name: x.fullName } : {}), photos: (x.media || []).length })), null, 1);
    if (t === "days" || t === "schedule") return JSON.stringify((m.days || []).map((x) => ({ day: x.label, date: x.date || "", shots: x.count || 0 })), null, 1);
    throw refuse("`from_the_film` is one of images, shots, scenes, locations, days, people, documents.");
  }

  if (name === "add_board") {
    if (found.role !== "editor") throw refuse("Only an editor may add a page to this film.");
    const called = String(args.name || "").replace(/\s+/g, " ").trim().slice(0, 60);
    const wrong = nameProblem(front, called);
    if (wrong) throw refuse(wrong);
    const share = SHARES.includes(args.share) ? args.share : "me";
    if (share !== "me" && !admin) throw refuse("Only he may share a board. It starts as his alone.");
    const one = newBoard(called, share);
    front.sections = [...(front.sections || []), one];
    front.updated = new Date().toISOString();
    await saveFront(env, found.project, front);
    if (Array.isArray(args.sorts) && args.sorts.length) {
      await writeBoard(env, found.project, one.board, {}, { v: 1, lenses: sortsFrom(args.sorts, []), added: [], ties: [] }, who.email);
    }
    return `Made the board ${called} at ${at(one.slug)} — ${share === "me" ? "his alone until he shares it" : share === "crew" ? "open to anyone signed in to the film" : "open to anyone with the link"}. Fill it with \`set_board\`, slug \`${one.slug}\`.`;
  }

  // ---- one board ---------------------------------------------------------
  const load = async (slug) => {
    let one = boardAt(front, slug);
    let boardName = one ? one.board : "";
    let html = "";
    if (!one) {
      const p = (await published()).find((x) => x.one.slug === slug);
      if (!p) throw refuse(`There is no board at \`${slug}\`. \`boards\` lists them.`);
      one = p.one;
      boardName = p.board;
      html = p.html;
    }
    if (!open(one)) throw refuse(`There is no board at \`${slug}\`. \`boards\` lists them.`);
    const board = await readBoard(env, found.project, boardName);
    // **Untouched**, for working out what changed: the MCP edits cards in place.
    const pristine = JSON.parse(JSON.stringify(board));
    return { one, boardName, html, board, pristine, every: html ? authoredOf(html) : [], authoredTies: authoredTiesOf(html), sorts: sortsOf(board, html) };
  };
  const slug = String(args.slug || "").trim();
  const here = await load(slug);
  const { one, boardName, html, board } = here;
  const sorts = here.sorts;

  // A card published with the page and deleted on the board is kept out of
  // sight by id (`gone`), never out of the page.
  const shown = (b, every = here.every) => { const off = new Set(b.gone || []); return every.filter((c) => !off.has(c.id)); };

  /** Every card as it sits, published ones at their moved place, with a size. */
  const everyCard = (b, every = here.every) => [
    ...shown(b, every).map((c) => ({
      ...c, authored: true,
      x: b.free && b.free[c.id] ? b.free[c.id][0] : c.x,
      y: b.free && b.free[c.id] ? b.free[c.id][1] : c.y,
      ...(b.text && b.text[c.id] ? { text: b.text[c.id] } : {}),
      ...(b.folded && b.folded[c.id] ? { folded: true } : {}),
      ...(b.bare && b.bare[c.id] ? { bare: true } : {}),
      ...(b.size && b.size[c.id] ? { size: b.size[c.id] } : {}),
    })),
    ...(b.added || []).map((c) => ({ ...c, authored: false, x: Number(c.x) || 0, y: Number(c.y) || 0 })),
  ];
  const sized = async (list) => {
    const ratios = await Promise.all(list.map((c) => { const s = coverOf(c); return s ? ratioOf(env, found.project, s) : 0; }));
    return list.map((c, i) => ({ ...c, ...sizeOf(c, ratios[i]) }));
  };
  /** Every thread on the board: the page's own (less those cut), and those added. */
  const threadsOf = (b) => {
    const cut = new Set(b.cut || []);
    const key = (a, c) => [a, c].sort().join("~");
    return [
      ...here.authoredTies.filter((t) => !cut.has(key(t.a, t.b))).map((t) => ({ ...t, label: b.labels && key(t.a, t.b) in b.labels ? b.labels[key(t.a, t.b)] : t.label, authored: true })),
      ...(b.ties || []).map((t) => ({ ...t, authored: false })),
    ];
  };

  if (name === "board") {
    if (args.history) {
      if (found.role !== "editor") throw refuse("Only an editor may look back through a board.");
      const versions = await boardVersions(env, found.project, boardName);
      return JSON.stringify(versions.length
        ? { board: one.name, versions, put_back: "set_board with `restore` set to a version's id (or \"latest\"). The board as it is now is kept in History first." }
        : "No earlier versions yet. One is kept every ten minutes while people work, and before anything big.", null, 1);
    }
    const cards = await sized(everyCard(board));
    const titleOf = (id) => { const c = cards.find((x) => x.id === id); return c ? (c.kind === "note" ? String(c.text || "").slice(0, 40) : c.title || c.cap || "") : ""; };
    if (Array.isArray(args.look) && args.look.length) {
      const want = args.look.map(String).slice(0, 8);
      const content = [];
      const words = [];
      for (const id of want) {
        const c = cards.find((x) => x.id === id);
        if (!c) { words.push(`${id}: not on this board`); continue; }
        const got = await seen(env, found.project, c);
        if (got.image) { content.push({ type: "text", text: `${id} — ${c.kind}${titleOf(id) ? `: ${titleOf(id)}` : ""}` }, got.image); } else words.push(got.said);
      }
      if (args.look.length > 8) words.push(`Sent the first 8 of ${args.look.length}; ask again for the rest.`);
      if (words.length) content.push({ type: "text", text: words.join("\n") });
      return { content };
    }
    const layout = describeLayout(cards, titleOf);
    return JSON.stringify({
      board: one.name, address: at(one.slug), ...(one.type === "board" ? { who_can_open: one.share } : {}),
      sorts: sorts.map((s) => (s.type === "line" ? { name: s.name, type: "line", ends: s.ends } : { name: s.name, type: "columns", columns: (s.cols || []).map((c) => c.name) })),
      layout: layout.said,
      groups: layout.groups,
      cards: cards.map((c) => ({
        id: c.id, kind: c.kind,
        ...(c.title && c.kind !== "heading" ? { title: c.title } : {}),
        ...(c.text ? { text: c.text } : {}),
        ...(c.kicker ? { kicker: c.kicker } : {}), ...(c.href ? { url: c.href } : {}),
        ...(coverOf(c) ? { picture: coverOf(c) } : {}),
        ...(c.live ? { from_the_film: { type: c.live.type, key: c.live.key } } : {}),
        ...(c.authored ? { published: true } : {}),
        ...(c.folded ? { collapsed: true } : {}),
        ...(c.bare ? { picture_only: true } : {}),
        ...(c.size && c.size !== 1 ? { size: c.size } : {}),
        ...((c.figs || []).length || (c.clips || []).length || (c.players || []).length
          ? { inside: `${(c.clips || []).length} clips, ${(c.figs || []).length} stills, ${(c.players || []).length} videos` } : {}),
        x: Math.round(c.x), y: Math.round(c.y), w: c.w, h: c.h,
        sorted: placesOf(sorts, (s) => valueOf(board, s, c, c.authored)),
      })),
      threads: threadsOf(board).map((t) => ({ a: t.a, b: t.b, ...(t.label ? { label: t.label } : {}) })),
      saved: board.at || null,
      note: "x and y are a card's centre; w and h are its size, estimated. `look` with card ids sends their pictures.",
    }, null, 1);
  }

  if (name !== "set_board" && name !== "arrange_board") throw refuse(`No tool called ${name}.`);
  if (found.role !== "editor") throw refuse("You may look at this board, not change it.");

  // ---- arrange_board -----------------------------------------------------
  if (name === "arrange_board") return await arrangeOne();

  // ---- set_board ---------------------------------------------------------
  const done = [];
  const failed = [];
  const said = [];
  let changed = false;
  let force = false;
  let out = { v: 1, ...board, added: [...(board.added || [])], ties: [...(board.ties || [])] };

  if (args.restore !== undefined && args.restore !== null && args.restore !== "") {
    const versions = await boardVersions(env, found.project, boardName);
    const want = String(args.restore);
    const v = want === "latest" ? versions[0] : versions.find((x) => x.id === want);
    if (!v) throw refuse(versions.length ? `No version ${want}. \`board\` with \`history: true\` lists them.` : "This board has no earlier versions yet.");
    const got = await env.BUCKET.get(`${boardKeys(found.project, boardName).history}${v.id}.json`);
    const old = got ? await got.json() : null;
    if (!old) throw refuse(`Version ${v.id} could not be read.`);
    out = { v: 1, ...old, added: [...(old.added || [])], ties: [...(old.ties || [])] };
    force = true;
    changed = true;
    done.push(`put back as it was at ${v.at}`);
  }

  if (args.share !== undefined) {
    if (one.type !== "board") throw refuse("This board is a published page; who may open it is the page's Visibility.");
    if (!admin) throw refuse("Only he may change who can open a board.");
    if (!SHARES.includes(args.share)) throw refuse("`share` is `me`, `crew` or `link`.");
    one.share = args.share;
    await saveFront(env, found.project, front);
    done.push(`shared with ${{ me: "him alone", crew: "the crew", link: "anyone with the link" }[args.share]}`);
  }

  if (args.rename !== undefined) {
    if (one.type !== "board") throw refuse("This board is part of a published page; the page's name is changed on the page.");
    const called = String(args.rename || "").replace(/\s+/g, " ").trim().slice(0, 60);
    if (called.toLowerCase() !== String(one.name).toLowerCase()) {
      const wrong = nameProblem({ ...front, sections: (front.sections || []).filter((s) => s !== one) }, called);
      if (wrong && !/already a page/.test(wrong)) throw refuse(wrong);
      const clash = (front.sections || []).some((s) => s !== one && String(s.name).toLowerCase() === called.toLowerCase());
      if (clash || NAMED.some((n) => n.toLowerCase() === called.toLowerCase())) throw refuse(`${called} is already a page on this film.`);
    }
    one.name = called;
    front.updated = new Date().toISOString();
    await saveFront(env, found.project, front);
    done.push(`renamed ${called} — its address stays ${at(one.slug)}`);
  }

  if (args.link_edit !== undefined) {
    if (!admin) throw refuse("Only he may let people with the link change a board.");
    const setKey = boardKeys(found.project, boardName).settings;
    const settings = await readBoardSettings(env, found.project, boardName);
    settings.publicEdit = Boolean(args.link_edit);
    await env.BUCKET.put(setKey, JSON.stringify(settings), JSON_TYPE);
    const shared = one.type !== "board" || one.share === "link";
    done.push(settings.publicEdit
      ? `people with the link may change it${shared ? "" : " (once it is shared with the link)"}`
      : "people with the link may only look");
  }

  if (Array.isArray(args.sorts)) {
    out.lenses = sortsFrom(args.sorts, sorts);
    changed = true;
    done.push(`${out.lenses.length} sort${out.lenses.length === 1 ? "" : "s"}`);
  }
  const liveSorts = Array.isArray(out.lenses) ? out.lenses : sorts;
  const findSort = (key) => liveSorts.find((s) => s.id === key || s.name.toLowerCase() === String(key).toLowerCase());
  const place = (card, isAuthored, values) => {
    for (const [key, raw] of Object.entries(values || {})) {
      const s = findSort(key);
      if (!s) throw refuse(`This board has no sort called ${key}. Its sorts: ${liveSorts.map((x) => x.name).join(", ") || "none"}.`);
      if (s.type === "line") {
        let v = typeof raw === "number" ? raw : Number(raw);
        if (Number.isNaN(v)) {
          const said2 = String(raw).toLowerCase();
          v = said2 === String(s.ends[0]).toLowerCase() ? 0.1 : said2 === String(s.ends[1]).toLowerCase() ? 0.9 : 0.5;
        }
        setValue(out, s, card, isAuthored, Math.max(0, Math.min(1, v)));
      } else {
        const col = raw === "" || raw === null ? { id: "" } : (s.cols || []).find((c) => c.id === raw || c.name.toLowerCase() === String(raw).toLowerCase());
        if (!col) throw refuse(`${s.name} has no column called ${raw}. Its columns: ${(s.cols || []).map((c) => c.name).join(", ")}.`);
        setValue(out, s, card, isAuthored, col.id);
      }
    }
  };

  // ---- add ----
  const fresh = [];
  const unplaced = [];
  const lay = (card, c) => {
    if (typeof c.x === "number" && typeof c.y === "number") { card.x = c.x; card.y = c.y; } else { card.x = 0; card.y = 0; unplaced.push(card.id); }
    if (c.values) place(card, false, c.values);
    out.added.push(card);
    fresh.push(card);
  };
  for (const c of Array.isArray(args.add) ? args.add : []) {
    const kind = KINDS.includes(c.kind) ? c.kind : "";
    if (!kind) throw refuse(`A card's kind is one of ${KINDS.join(", ")}.`);
    const title = String(c.title || "").slice(0, 140);
    const card = { id: idFor(`${kind}-`), kind, text: String(c.text || "").slice(0, 4000) };
    if (title) card.title = title;
    if (c.kicker) card.kicker = String(c.kicker).slice(0, 80);

    if ((kind === "still" || kind === "clip") && c.mood_board) {
      // **A whole mood board at once** — what the panel's Reference Images
      // tab holds under one name, each picture its own card.
      const m = await film();
      const wanted = String(c.mood_board).trim().toLowerCase();
      const pics = moodPictures(m).filter((p) => p.board.trim().toLowerCase() === wanted);
      if (!pics.length) throw refuse(`${found.title} has no mood board called ${c.mood_board}${(m.boards || []).length ? `. Its mood boards: ${(m.boards || []).map((b) => b.name).join(", ")}` : ""}.`);
      for (const p of pics) lay({ id: idFor(`${p.f.clip ? "clip" : "still"}-`), text: "", ...pictureCard(p) }, {});
      continue;
    }
    if (kind === "note" || kind === "heading") {
      if (!card.text && title) card.text = title;
    } else if (kind === "still" || kind === "clip") {
      if (c.picture) {
        // One of the film's own pictures, by the start of its hash.
        const p = anyPicture(await film(), c.picture);
        if (!p) throw refuse(`The film has no picture ${c.picture}. \`boards\` with \`from_the_film: "images"\` lists them.`);
        Object.assign(card, pictureCard(p), { id: card.id });
        if (title) card.title = title;
      } else if (c.base64) {
        // **The file itself**, as the board's Upload… takes one.
        const ext = extensionFor(c.type || "", String(c.filename || ""));
        if (!ext) throw refuse("Say what the file is with its `filename` — a .jpg, .png, .webp, .gif, .heic, .mp4 or .mov.");
        const moving = TYPE_OF[ext].startsWith("video/");
        let bytes;
        try {
          const bin = atob(String(c.base64).replace(/^data:[^,]*,/, "").replace(/\s+/g, ""));
          bytes = new Uint8Array(bin.length);
          for (let i = 0; i < bin.length; i += 1) bytes[i] = bin.charCodeAt(i);
        } catch { throw refuse("That did not decode as base64."); }
        if (bytes.length < 40) throw refuse("That file is empty.");
        // A message carries about 28 MB of file (`MAX_BODY` in `mcp.js`); a
        // longer clip goes by its address instead.
        if (bytes.length > (moving ? 28 * 1024 * 1024 : MOST_PICTURE)) throw refuse(moving ? "That clip is over 28 MB, which is as much as a message carries. Put it somewhere with an address and send the `url`." : "That picture is over 25 MB.");
        const file = await keepBytes(env, found.project, ext, bytes);
        card.kind = moving ? "clip" : "still";
        card.src = `pic/${file}`;
        card.cap = title;
        if (!card.title) card.title = moving ? "Clip" : "Still";
      } else {
        if (!c.url) throw refuse(`A ${kind} needs its \`url\`, its file as \`base64\` with a \`filename\`, or a \`picture\` of the film's.`);
        const got = await fetchInto(env, found.project, c.url);
        if (!got || !got.src) { failed.push(c.url); continue; }
        card.kind = got.kind === "clip" ? "clip" : "still";
        card.src = got.src;
        card.cap = title;
        if (!card.title) card.title = card.kind === "clip" ? "Clip" : "Still";
      }
    } else if (kind === "video" || kind === "link") {
      if (!c.url) throw refuse(`A ${kind} needs its \`url\`.`);
      const got = await fetchInto(env, found.project, c.url);
      if (!got) { failed.push(c.url); continue; }
      if (got.kind === "video") {
        card.kind = "video";
        card.href = got.href;
        card.title = title || got.title;
        card.kicker = card.kicker || [got.site, got.by].filter(Boolean).join(" · ");
        card.players = [{ src: got.embed, title: card.title }];
        if (got.image) card.src = got.image;
      } else if (got.src) {
        card.kind = got.kind === "clip" ? "clip" : "still";
        card.src = got.src;
        card.cap = title;
      } else {
        card.kind = "link";
        card.href = got.href;
        card.title = title || got.title;
        card.kicker = card.kicker || got.site;
        if (got.image) card.src = got.image;
        if (got.closed) card.closed = true;
      }
    } else if (kind === "ref") {
      // **A reference, the way Halcyon's are**: a card that opens to its
      // trailers, its stills and its clips, any of which drags out.
      if (!title) throw refuse("A reference needs its `title`.");
      card.players = [];
      card.figs = [];
      card.clips = [];
      for (const v of (Array.isArray(c.videos) ? c.videos : []).slice(0, 8)) {
        const got = videoOf(v);
        if (!got) { failed.push(v); continue; }
        card.players.push({ src: got.embed, title: card.players.length ? `Video ${card.players.length + 1}` : "Trailer" });
        if (!card.figs.length && got.thumb) {
          const kept = await pictureInto(env, found.project, got.thumb);
          if (kept) card.figs.push({ src: `pic/${kept}`, from: "Trailer" });
        }
      }
      for (const s of (Array.isArray(c.stills) ? c.stills : []).slice(0, 40)) {
        const kept = await pictureInto(env, found.project, s);
        if (kept) card.figs.push({ src: `pic/${kept}`, from: "" }); else failed.push(s);
      }
      for (const s of (Array.isArray(c.clips) ? c.clips : []).slice(0, 30)) {
        const got = await fetchInto(env, found.project, s);
        if (got && got.kind === "clip") card.clips.push({ clip: true, src: got.src, poster: "", from: "" }); else failed.push(s);
      }
    } else if (kind === "person" || kind === "doc") {
      const wanted = String(c.name || c[kind] || title || "").trim().toLowerCase();
      const list = kind === "person" ? front.crew || [] : front.documents || [];
      const hit = list.find((p) => String(p.name || "").trim().toLowerCase() === wanted);
      if (!hit) throw refuse(`${found.title} has no ${kind === "person" ? "crew member" : "document"} called ${c.name || c[kind] || title}.`);
      Object.assign(card, kind === "person" ? personCard(hit) : docCard(hit));
    } else if (LIVE.has(kind)) {
      // **Live, and whole from the start.** Named by what a person would say
      // — a shot's number, a scene's number, a location's or a day's name —
      // found in the film now and made into the card the panel would make;
      // the page brings it up to date whenever it is opened.
      const key = String(c[kind] ?? c.number ?? c.name ?? title ?? "").trim();
      if (!key) throw refuse(`Say which ${kind}: \`${kind}\` is its ${kind === "shot" || kind === "scene" ? "number" : "name"}.`);
      const it = inFilm(await film(), kind, key);
      if (!it) throw refuse(`${found.title} has no ${kind} ${key}. \`boards\` with \`from_the_film\` lists what it has.`);
      Object.assign(card, filmCard(kind, it, model));
      if (title) card.title = title;
    } else if (kind === "gear" || kind === "idea") {
      if (!title) throw refuse(`A ${kind} card needs its \`title\`.`);
    }
    lay(card, c);
  }
  if (fresh.length) { done.push(`${fresh.length} card${fresh.length === 1 ? "" : "s"} added`); changed = true; }

  const cardOf = (id) => {
    const a = out.added.find((c) => c.id === id);
    if (a) return { card: a, authored: false };
    const b = shown(out).find((c) => c.id === id);
    if (b) return { card: b, authored: true };
    throw refuse(`This board has no card \`${id}\`. \`board\` lists them.`);
  };

  /** A card as it would be copied: the board's own copy (`cardOut`), less its id. */
  const copyOf = (id) => {
    const { card, authored: isA } = cardOf(id);
    const x = isA && out.free && out.free[card.id] ? out.free[card.id][0] : Number(card.x) || 0;
    const y = isA && out.free && out.free[card.id] ? out.free[card.id][1] : Number(card.y) || 0;
    const { id: _id, x: _x, y: _y, obs: _o, cam: _c, ...rest } = card;
    const copy = JSON.parse(JSON.stringify(rest));
    if (isA && out.text && out.text[card.id]) copy.text = out.text[card.id];
    copy.id = idFor(`${card.kind}-`);
    for (const s of liveSorts) {
      const v = valueOf(out, s, card, isA);
      if (v !== null && v !== undefined && v !== "") setValue(null, s, copy, false, v);
    }
    return { copy, was: card.id, x, y };
  };

  /** Copies laid down together, their shapes kept, where nothing is. */
  const lay2 = async (target, every, copies, ties, nearBox) => {
    const cards = await sized(everyCard(target, every));
    const made = await sized(copies.map((k) => ({ ...k.copy, x: k.x, y: k.y })));
    const x0 = Math.min(...made.map((c) => c.x - c.w / 2)), y0 = Math.min(...made.map((c) => c.y - c.h / 2));
    const x1 = Math.max(...made.map((c) => c.x + c.w / 2)), y1 = Math.max(...made.map((c) => c.y + c.h / 2));
    const still = cards.map((c) => ({ x0: c.x - c.w / 2, y0: c.y - c.h / 2, x1: c.x + c.w / 2, y1: c.y + c.h / 2 }));
    const want = nearBox ? { x: nearBox.x1 + 140, y: nearBox.y0 } : still.length
      ? { x: Math.min(...still.map((r) => r.x0)), y: Math.max(...still.map((r) => r.y1)) + 200 } : { x: -(x1 - x0) / 2, y: -(y1 - y0) / 2 };
    const spot = clearSpot(want, x1 - x0, y1 - y0, still, nearBox ? "right" : "down");
    const ids = new Map();
    copies.forEach((k, i) => {
      k.copy.x = Math.round(made[i].x - x0 + spot.x);
      k.copy.y = Math.round(made[i].y - y0 + spot.y);
      target.added.push(k.copy);
      ids.set(k.was, k.copy.id);
    });
    for (const t of ties) {
      if (ids.has(t.a) && ids.has(t.b)) target.ties.push({ a: ids.get(t.a), b: ids.get(t.b), label: String(t.label || "") });
    }
  };

  if (idList(args.duplicate).length) {
    const list = idList(args.duplicate);
    const copies = list.map((id) => copyOf(id));
    const inside = new Set(list);
    const ties = threadsOf(out).filter((t) => inside.has(t.a) && inside.has(t.b));
    const src = await sized(everyCard(out).filter((c) => inside.has(c.id)));
    const box = { x1: Math.max(...src.map((c) => c.x + c.w / 2)), y0: Math.min(...src.map((c) => c.y - c.h / 2)) };
    await lay2(out, here.every, copies, ties, box);
    changed = true;
    done.push(`${copies.length} duplicated beside ${copies.length === 1 ? "it" : "them"}`);
  }

  if (args.send && typeof args.send === "object") {
    const list = idList(args.send.cards || args.send.ids);
    const to = String(args.send.to || "").trim();
    if (!list.length || !to) throw refuse("`send` is `{cards: [ids], to: \"<another board's slug>\", keep: true}`.");
    if (to === slug) throw refuse("That is this board. `duplicate` copies cards here.");
    const there = await load(to);
    const target = { v: 1, ...there.board, added: [...(there.board.added || [])], ties: [...(there.board.ties || [])] };
    const copies = list.map((id) => copyOf(id));
    const inside = new Set(list);
    const ties = threadsOf(out).filter((t) => inside.has(t.a) && inside.has(t.b));
    await lay2(target, there.every, copies, ties, null);
    await writeBoard(env, found.project, there.boardName, there.pristine, target, who.email);
    const keep = args.send.keep !== false;
    if (!keep) {
      args.remove = [...idList(args.remove), ...list];
    }
    done.push(`${copies.length} ${keep ? "copied" : "moved"} to ${there.one.name} (${at(there.one.slug)})`);
    changed = changed || !keep;
  }

  for (const m of Array.isArray(args.move) ? args.move : []) {
    const { card, authored: isA } = cardOf(String(m.id));
    const x = Number(m.x), y = Number(m.y);
    if (Number.isNaN(x) || Number.isNaN(y)) throw refuse("A move is `{id, x, y}`.");
    if (isA) out.free = { ...(out.free || {}), [card.id]: [Math.round(x), Math.round(y)] };
    else { card.x = x; card.y = y; }
  }
  if (Array.isArray(args.move) && args.move.length) { done.push(`${args.move.length} moved`); changed = true; }

  for (const s of Array.isArray(args.values) ? args.values : []) {
    for (const id of idList(s.id || s.ids || s.cards)) {
      const { card, authored: isA } = cardOf(id);
      place(card, isA, { [s.sort]: s.value });
    }
  }
  if (Array.isArray(args.values) && args.values.length) { done.push(`${args.values.length} placed`); changed = true; }

  for (const t of Array.isArray(args.text) ? args.text : []) {
    const { card, authored: isA } = cardOf(String(t.id));
    if (isA) out.text = { ...(out.text || {}), [card.id]: String(t.text || "") };
    else card.text = String(t.text || "");
    changed = true;
  }

  // **Collapse and expand** — a card folded to its picture and name, as the
  // card's menu does it. Kept where the board keeps it: on the card, or in
  // `folded` by id for one published with the page.
  for (const [ids, on] of [[idList(args.collapse), true], [idList(args.expand), false]]) {
    let n = 0;
    for (const id of ids) {
      const { card, authored: isA } = cardOf(id);
      if (!FOLDABLE(card.kind)) continue;
      n += 1;
      if (isA) {
        out.folded = { ...(out.folded || {}) };
        if (on) out.folded[id] = true; else delete out.folded[id];
      } else if (on) card.folded = true;
      else delete card.folded;
    }
    if (ids.length) { done.push(`${n} ${on ? "collapsed" : "expanded"}${n < ids.length ? ` (${ids.length - n} cannot fold: notes, headings, stills and clips are already small)` : ""}`); changed = changed || n > 0; }
  }

  // **Picture only, and a card's size** — as the card's menu and its corner
  // handle do them. Kept on the card, or in `bare` / `size` by id for one
  // published with the page.
  for (const [ids, on] of [[idList(args.picture_only), true], [idList(args.as_card), false]]) {
    let n = 0;
    for (const id of ids) {
      const { card, authored: isA } = cardOf(id);
      if (!coverOf(card) && card.kind !== "clip") continue;
      n += 1;
      if (isA) {
        out.bare = { ...(out.bare || {}) };
        if (on) out.bare[id] = true; else delete out.bare[id];
      } else if (on) card.bare = true;
      else delete card.bare;
    }
    if (ids.length) { done.push(`${n} ${on ? "shown as picture only" : "shown as cards"}${n < ids.length ? ` (${ids.length - n} have no picture)` : ""}`); changed = changed || n > 0; }
  }
  for (const r of Array.isArray(args.resize) ? args.resize : []) {
    for (const id of idList(r.id || r.ids)) {
      const { card, authored: isA } = cardOf(id);
      const k = Math.min(5, Math.max(0.3, Math.round((Number(r.size) || 1) * 100) / 100));
      if (isA) {
        out.size = { ...(out.size || {}) };
        if (k === 1) delete out.size[id]; else out.size[id] = k;
      } else if (k === 1) delete card.size;
      else card.size = k;
      changed = true;
    }
  }
  if (Array.isArray(args.resize) && args.resize.length) done.push(`${args.resize.length} resized`);

  if (idList(args.remove).length) {
    const gone = new Set(idList(args.remove));
    for (const id of gone) cardOf(id);
    // One published with the page cannot leave the page; it is kept out of
    // sight instead, as the board's own Delete does, and History brings it back.
    const pubd = [...gone].filter((id) => here.every.some((c) => c.id === id));
    if (pubd.length) out.gone = [...new Set([...(out.gone || []), ...pubd])];
    const before = out.added.length;
    out.added = out.added.filter((c) => !gone.has(c.id));
    out.ties = out.ties.filter((t) => !gone.has(t.a) && !gone.has(t.b));
    if (before - out.added.length + pubd.length > 3) force = true;
    done.push(`${before - out.added.length + pubd.length} taken off`);
    changed = true;
  }

  // ---- threads ----
  const key = (a, b) => [a, b].sort().join("~");
  const visible = () => new Set([...shown(out).map((c) => c.id), ...out.added.map((c) => c.id)]);
  const pageTie = (k) => here.authoredTies.some((t) => key(t.a, t.b) === k) && !(out.cut || []).includes(k);
  const labelIt = (a, b, label) => {
    const k = key(a, b);
    const mine = out.ties.find((x) => key(x.a, x.b) === k);
    if (mine) { mine.label = label; return true; }
    if (pageTie(k)) { out.labels = { ...(out.labels || {}), [k]: label }; return true; }
    return false;
  };
  let tied = 0, relabelled = 0;
  for (const t of Array.isArray(args.tie) ? args.tie : []) {
    const ids = visible();
    const b = String(t.b || t.to || "");
    const label = String(t.label || "").slice(0, 80);
    for (const a of idList(t.a || t.from)) {
      if (!ids.has(a) || !ids.has(b)) throw refuse(`A thread ties two cards on this board; \`${ids.has(a) ? b : a}\` is not one.`);
      if (a === b) continue;
      if (out.ties.some((x) => key(x.a, x.b) === key(a, b)) || pageTie(key(a, b))) {
        if (t.label !== undefined) { labelIt(a, b, label); relabelled += 1; }
        continue;
      }
      out.ties.push({ a, b, label });
      tied += 1;
    }
  }
  for (const t of Array.isArray(args.label) ? args.label : []) {
    if (!labelIt(String(t.a), String(t.b), String(t.label || "").slice(0, 80))) throw refuse(`There is no thread between \`${t.a}\` and \`${t.b}\`.`);
    relabelled += 1;
  }
  if (tied) done.push(`${tied} tied`);
  if (relabelled) done.push(`${relabelled} label${relabelled === 1 ? "" : "s"} changed`);
  for (const t of Array.isArray(args.untie) ? args.untie : []) {
    const k = key(String(t.a), String(t.b));
    if (pageTie(k)) out.cut = [...new Set([...(out.cut || []), k])];
    out.ties = out.ties.filter((x) => key(x.a, x.b) !== k);
  }
  if (Array.isArray(args.untie) && args.untie.length) done.push(`${args.untie.length} cut`);
  if (tied || relabelled || (Array.isArray(args.untie) && args.untie.length)) changed = true;

  // New cards with nowhere said go in a tidy block under everything, never on top of anything.
  if (unplaced.length) {
    const cards = await sized(everyCard(out));
    const moving = new Set(unplaced);
    const still = cards.filter((c) => !moving.has(c.id));
    const low = still.length ? Math.max(...still.map((c) => c.y + c.h / 2)) + 200 : 0;
    const left = still.length ? Math.min(...still.map((c) => c.x - c.w / 2)) : 0;
    const got = arrange({ cards, moving, groups: [{ name: "", cards: cards.filter((c) => moving.has(c.id)) }], perRowAsked: 6,
      at: still.length ? { x: left, y: low } : null, whole: !still.length });
    for (const card of out.added) if (got.moved[card.id]) [card.x, card.y] = got.moved[card.id];
  }

  // ---- Add to Shot — only when he asks ----
  for (const s of Array.isArray(args.to_shot) ? args.to_shot : []) {
    const { card } = cardOf(String(s.id));
    if (card.kind !== "still" && card.kind !== "clip") throw refuse("Only a still or a clip goes onto a shot.");
    try {
      const got = await fileOnShot(env, found.project, who, ctx, { src: card.src, hash: card.hash || "", shot: String(s.shot || ""), caption: card.cap || "", poster: card.poster || "", name: card.cap || "" }, attachToShot);
      said.push(String(got.said || "").replace(/\.$/, "") + (card.kind === "clip" && !card.poster && !/(^|\/)media\//.test(card.src || "") ? " (its poster picture is made the next time he opens a board on this film)" : ""));
    } catch (e) {
      throw refuse(e.said || String(e.message || e));
    }
  }

  if (!done.length && !failed.length && !said.length) throw refuse("Nothing was sent to change.");
  let kept = "";
  if (changed) {
    const before = board.at;
    await writeBoard(env, found.project, boardName, here.pristine, out, who.email, force);
    if (force && before) kept = ` The board as it was is in History as \`${versionId(board)}\`.`;
  }
  const madeIds = fresh.length ? ` New: ${fresh.slice(0, 40).map((c) => `${c.id} (${c.kind}${c.title ? ` ${c.title}` : ""})`).join(", ")}${fresh.length > 40 ? ", …" : ""}.` : "";
  return `${one.name}: ${[...done, ...said].join(", ") || "nothing changed"}.${madeIds}${failed.length ? ` Could not fetch ${failed.length}: ${failed.slice(0, 5).join(", ")}.` : ""}${kept} Open it at ${at(one.slug)}.`;

  // ---- arranging -----------------------------------------------------------
  async function arrangeOne() {
    const out2 = { v: 1, ...board, added: [...(board.added || [])], ties: [...(board.ties || [])] };
    const cards = await sized(everyCard(out2));
    const byId = new Map(cards.map((c) => [c.id, c]));
    const by = String(args.by || "grid").toLowerCase();
    const BY = ["grid", "row", "column", "kind", "scene", "day", "sort", "groups", "threads"];
    if (!BY.includes(by)) throw refuse(`\`by\` is one of ${BY.join(", ")}.`);
    let ids = idList(args.cards);
    if (by === "groups") {
      if (!Array.isArray(args.groups) || !args.groups.length) throw refuse("`by: groups` needs `groups: [{name, cards: [ids]}]`.");
      if (!ids.length) ids = [...new Set(args.groups.flatMap((g) => idList(g.cards)))];
    }
    const missing = ids.filter((id) => !byId.has(id));
    if (missing.length) throw refuse(`This board has no card${missing.length === 1 ? "" : "s"} ${missing.slice(0, 5).map((m) => `\`${m}\``).join(", ")}. \`board\` lists them.`);
    const whole = !ids.length;
    const list = whole ? cards.filter((c) => c.kind !== "heading") : ids.map((id) => byId.get(id));
    if (!list.length) throw refuse("There is nothing on this board to arrange.");
    const moving = new Set(list.map((c) => c.id));
    const reading = (a, b) => Math.round(a.y / 220) - Math.round(b.y / 220) || a.x - b.x;

    // ---- into groups ----
    let groups = [];
    let line = null;
    const byKey = (keyOf, order, none) => {
      const m = new Map();
      for (const c of list) {
        const k = keyOf(c) || none;
        if (!m.has(k)) m.set(k, []);
        m.get(k).push(c);
      }
      return [...m.entries()].sort((a, b) => order(a[0]) - order(b[0])).map(([k, cs]) => ({ name: k, cards: cs.sort(reading) }));
    };
    /** Cards with no group of their own join the group of a card they are tied to. */
    const inherit = (own) => {
      const got = new Map(list.map((c) => [c.id, own(c)]));
      const ties = threadsOf(out2);
      for (let pass = 0; pass < 3; pass += 1) {
        for (const c of list) {
          if (got.get(c.id)) continue;
          const t = ties.find((x) => (x.a === c.id && got.get(x.b)) || (x.b === c.id && got.get(x.a)));
          if (t) got.set(c.id, got.get(t.a === c.id ? t.b : t.a));
        }
      }
      return (c) => got.get(c.id) || "";
    };
    if (by === "grid" || by === "row" || by === "column") {
      groups = [{ name: "", cards: list.slice().sort(reading) }];
    } else if (by === "kind") {
      groups = byKey((c) => KIND_NAMES[c.kind] || "Other", (k) => { const i = ORDER.findIndex((o) => KIND_NAMES[o] === k); return i < 0 ? 99 : i; }, "Other");
    } else if (by === "scene" || by === "day") {
      const m = await film();
      const rows = shotRows(m);
      const scenes = (m.scenes || []).filter((x) => !x.archived);
      const sceneName = (s) => (s ? `Scene ${s.number}` : "");
      const byHash = new Map();
      for (const r of rows) for (const x of r.stills || []) if (x.hash) byHash.set(x.hash, r);
      const rowOf = (c) => (c.live && c.live.type === "shot" ? inFilm(m, "shot", c.live.key, c.live.id) : c.hash ? byHash.get(c.hash) : null);
      let own, order;
      if (by === "scene") {
        const sceneOfHash = new Map();
        for (const s of scenes) for (const x of s.attachments || []) if (x.hash) sceneOfHash.set(x.hash, s);
        own = (c) => {
          if (c.live && c.live.type === "scene") return sceneName(inFilm(m, "scene", c.live.key, c.live.id));
          const r = rowOf(c);
          if (r) return sceneName(scenes.find((s) => s.id === r.sceneId));
          if (c.hash && sceneOfHash.has(c.hash)) return sceneName(sceneOfHash.get(c.hash));
          return "";
        };
        const at2 = new Map(scenes.map((s, i) => [sceneName(s), i]));
        order = (k) => (at2.has(k) ? at2.get(k) : 9999);
      } else {
        own = (c) => {
          if (c.live && c.live.type === "day") { const d = inFilm(m, "day", c.live.key, c.live.id); return d ? d.label : ""; }
          const r = rowOf(c);
          return r ? dayOf(r) : "";
        };
        const at2 = new Map((m.days || []).map((d, i) => [d.label, i]));
        order = (k) => (at2.has(k) ? at2.get(k) : 9999);
      }
      const none = by === "scene" ? "No Scene" : "No Day";
      groups = byKey(inherit(own), order, none);
    } else if (by === "sort") {
      const s = liveSortsOf(out2).find((x) => x.id === args.sort || x.name.toLowerCase() === String(args.sort || "").toLowerCase());
      if (!s) throw refuse(`Say which sort: \`sort\` is one of ${liveSortsOf(out2).map((x) => x.name).join(", ") || "— this board has none; `set_board` `sorts` makes one"}.`);
      if (s.type === "columns") {
        const cols = s.cols || [];
        const name2 = (v) => { const col = cols.find((c) => c.id === v); return col ? col.name : ""; };
        const none = s.none || "Unsorted";
        groups = byKey((c) => name2(valueOf(out2, s, c, c.authored)), (k) => { const i = cols.findIndex((c) => c.name === k); return i < 0 ? 999 : i; }, none);
      } else {
        const v = (c) => { const x = valueOf(out2, s, c, c.authored); return typeof x === "number" ? x : 0.5; };
        line = { cards: list, valueOf: v, headings: [], sort: s };
      }
    } else if (by === "groups") {
      const taken = new Set();
      groups = args.groups.map((g) => ({ name: String(g.name || "").replace(/\s+/g, " ").trim().slice(0, 60),
        cards: idList(g.cards).filter((id) => byId.has(id) && !taken.has(id) && taken.add(id)).map((id) => byId.get(id)) })).filter((g) => g.cards.length);
      const rest = list.filter((c) => !taken.has(c.id));
      if (rest.length) groups.push({ name: "Other", cards: rest.sort(reading) });
    } else if (by === "threads") {
      const ties = threadsOf(out2).filter((t) => moving.has(t.a) && moving.has(t.b));
      const parent = new Map(list.map((c) => [c.id, c.id]));
      const find = (i) => { while (parent.get(i) !== i) i = parent.get(i); return i; };
      for (const t of ties) parent.set(find(t.a), find(t.b));
      const clumps = new Map();
      for (const c of list) { const k = find(c.id); if (!clumps.has(k)) clumps.set(k, []); clumps.get(k).push(c); }
      const degree = (id) => ties.filter((t) => t.a === id || t.b === id).length;
      const all = [...clumps.values()];
      groups = all.filter((g) => g.length > 1).sort((a, b) => b.length - a.length).map((g) => {
        const hub = g.slice().sort((a, b) => degree(b.id) - degree(a.id))[0];
        return { name: hub.kind === "note" ? String(hub.text || "").slice(0, 40) : hub.title || hub.cap || "", cards: [hub, ...g.filter((c) => c !== hub).sort(reading)] };
      });
      const lone = all.filter((g) => g.length === 1).flat();
      if (lone.length) groups.push({ name: "Not Tied", cards: lone.sort(reading) });
    }

    // ---- headings ----
    const wantHeads = args.headings === undefined ? !["grid", "row", "column", "threads"].includes(by) : Boolean(args.headings);
    const reused = [];
    const madeHeads = [];
    const headFor = (text, x = 0, y = 0) => {
      const t = String(text || "").trim();
      if (!t) return null;
      const had = cards.find((c) => c.kind === "heading" && !reused.includes(c) && String(c.text || c.title || "").trim().toLowerCase() === t.toLowerCase());
      if (had) { reused.push(had); moving.add(had.id); return had; }
      const h = { id: idFor("heading-"), kind: "heading", text: t, x, y, authored: false, new: true };
      Object.assign(h, sizeOf(h, 0));
      madeHeads.push(h);
      moving.add(h.id);
      return h;
    };
    if (wantHeads) {
      if (line) {
        const [l, r] = line.sort.ends || ["", ""];
        const hl = headFor(l), hr = headFor(r);
        if (hl) line.headings.push({ c: hl, rx: -SPAN_LINE + hl.w / 2, ry: -hl.h / 2 - 90 });
        if (hr) line.headings.push({ c: hr, rx: SPAN_LINE - hr.w / 2, ry: -hr.h / 2 - 90 });
      } else {
        for (const g of groups) if (g.name) g.heading = headFor(g.name);
      }
    }

    // **The last arrangement's own headings go when the whole board is laid
    // out again** — "Stills" over nothing is litter, not his. A heading the
    // arranger made carries `kicker: "Arranged"` (the board never draws a
    // heading's kicker, and keeps it); one he typed himself has none and is
    // left exactly where he put it.
    const stale = whole ? cards.filter((c) => c.kind === "heading" && !c.authored && c.kicker === ARRANGED && !reused.includes(c)) : [];
    const cleared = new Set(stale.map((c) => c.id));
    const all = [...cards.filter((c) => !cleared.has(c.id)), ...madeHeads];
    const nearId = args.near ? String(args.near) : null;
    if (nearId && !byId.has(nearId)) throw refuse(`This board has no card \`${nearId}\`.`);
    if (nearId && moving.has(nearId)) throw refuse("`near` is a card that stays where it is, not one being arranged.");
    const got = arrange({
      cards: all, moving, groups, line,
      shape: by === "row" ? "row" : by === "column" ? "column" : "grid",
      perRowAsked: Number(args.per_row) || 0,
      near: nearId, side: String(args.side || "below"),
      at: args.at && typeof args.at === "object" ? { x: Number(args.at.x), y: Number(args.at.y) } : null,
      whole,
    });

    if (cleared.size) {
      out2.added = out2.added.filter((c) => !cleared.has(c.id));
      out2.ties = out2.ties.filter((t) => !cleared.has(t.a) && !cleared.has(t.b));
    }
    for (const h of madeHeads) {
      const [x, y] = got.moved[h.id] || [0, 0];
      out2.added.push({ id: h.id, kind: "heading", kicker: ARRANGED, x, y, text: h.text });
    }
    let n = 0;
    for (const [id, [x, y]] of Object.entries(got.moved)) {
      const c = byId.get(id);
      if (!c) continue;
      n += 1;
      if (c.authored) out2.free = { ...(out2.free || {}), [id]: [x, y] };
      else { const a = out2.added.find((k) => k.id === id); if (a) { a.x = x; a.y = y; } }
    }
    await writeBoard(env, found.project, boardName, here.pristine, out2, who.email, true);

    const left = whole ? cards.filter((c) => c.kind === "heading" && !reused.includes(c) && !cleared.has(c.id)) : [];
    const placedNow = await sized(everyCard(out2));
    const titleOf = (id) => { const c = placedNow.find((x) => x.id === id); return c ? (c.kind === "note" ? String(c.text || "").slice(0, 40) : c.title || c.cap || "") : ""; };
    const how = line ? `along ${line.sort.name}` : by === "grid" ? "into a grid" : by === "row" ? "into a row" : by === "column" ? "into a column" : `by ${by === "groups" ? "the groups asked for" : by}`;
    const counts = line ? "" : groups.filter((g) => g.name).map((g) => `${g.name} (${g.cards.length})`).join(", ");
    const box = got.box ? ` It takes x ${got.box.x0} to ${got.box.x1}, y ${got.box.y0} to ${got.box.y1}.` : "";
    return `${one.name}: arranged ${n - reused.length} card${n - reused.length === 1 ? "" : "s"} ${how}${counts ? ` — ${counts}` : ""}.${madeHeads.length ? ` Headings made: ${madeHeads.map((h) => h.text).join(", ")}.` : ""}${reused.length ? ` Headings moved: ${reused.map((h) => h.text || h.title).join(", ")}.` : ""}${stale.length ? ` Headings from the last arrangement taken off: ${stale.map((h) => h.text).join(", ")}.` : ""}${left.length ? ` Headings left where they were: ${left.map((h) => h.text || h.title).join(", ")}.` : ""}${box}${board.at ? ` The board as it was is in History as \`${versionId(board)}\` — \`set_board\` \`restore\` puts it back.` : ""}\n\nNow:\n${describeLayout(placedNow, titleOf).said}\n\nOpen it at ${at(one.slug)}. (Anyone looking at it through a sort sees that sort; this is the free board.)`;
  }

  function liveSortsOf(b) { return Array.isArray(b.lenses) ? b.lenses : sorts; }
}

const SPAN_LINE = 1900;
/** What marks a heading `arrange_board` made, so the next full arrangement may clear it. */
const ARRANGED = "Arranged";

/** What the MCP offers, next to the pages' own tools. */
export const BOARD_TOOLS = [
  {
    name: "boards",
    description: "Every board on the open film — the free-form pin boards (like the Halcyon look board) where references, clips, stills and anything from the film are laid out, tied together and sorted. Says who can open each, how many cards it holds and what sorts it has.\n\nWith `from_the_film` it lists instead what the board's own *From the Film* panel offers, to put on a board with `set_board`: `images` (the pictures and clips on Shotlister's own mood boards, each with a `picture` id), `shots`, `scenes`, `locations`, `days`, `people`, `documents`.",
    inputSchema: { type: "object", properties: {
      from_the_film: { type: "string", description: "images, shots, scenes, locations, days, people or documents." },
    }, required: [] },
  },
  {
    name: "board",
    description: "Read one board. Read it before changing it, so a change is a change and not a pile-up.\n\nAnswers its sorts; `layout`, the board in words — each clump of cards, the heading over it, what it holds and where it sits (top left, centre…); `groups`, the same with card ids and boxes; every card (id, kind, title, its centre `x`/`y`, its estimated size `w`/`h`, its place on each sort, what is inside a reference); and the threads between cards.\n\n`look: [ids]` sends the cards' pictures themselves (up to 8 at a time), so you can see what is on the board — to group stills by colour or mood, say, or to describe it to him.\n\n`history: true` lists the board's earlier copies, to put one back with `set_board` `restore`.",
    inputSchema: { type: "object", properties: {
      slug: { type: "string", description: "The board's address, as `boards` lists it." },
      look: { type: "array", items: { type: "string" }, description: "Card ids whose pictures to send." },
      history: { type: "boolean", description: "List earlier copies instead." },
    }, required: ["slug"] },
  },
  {
    name: "add_board",
    description: "Make a new board — a page on the film's portal, beside its other pages. **It starts as his alone** (`share: me`) until he shares it; only he may start one shared. Optionally give it its sorts now.\n\nSORTS are what made the Halcyon board feel made for it: ways to lay the same cards out. Two kinds only — a `line` between two words (Observe ↔ Move, Day ↔ Night, Still ↔ Chaos) and `columns` (A-cam / B-cam, Act 1 / 2 / 3, Kitchen / Car / Roof). Make up the ones that fit what this board is for; none at all is fine too.\n\nA board is renamed with `set_board` `rename`, and taken off the film with `remove_page`.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "What the board is called, in Title Case. `Look Board`, `Night Exteriors`." },
        share: { type: "string", description: "`me` (default), `crew` or `link`. Only he may choose other than `me`." },
        sorts: {
          type: "array",
          description: "`[{name, type: \"line\", ends: [left, right]}, {name, type: \"columns\", columns: [names]}]`.",
          items: { type: "object" },
        },
      },
      required: ["name"],
    },
  },
  {
    name: "set_board",
    description: "Change a board — everything he can do on it by hand. Send only what changes; everything else is kept. A big change (a restore, taking off several cards) keeps the board as it was in History first. To lay many cards out at once, use `arrange_board` instead of `move`.\n\nADD — `add` is a list of cards. Each has a `kind`, and optionally `x`/`y` (its centre; left out, new cards are laid in a tidy block under everything, never on top of anything) and `values` (its place on each sort, by sort name).\n  `note`     `text` — only when he asks for notes; the thinking is his\n  `heading`  `text` — a big word laid on the board\n  `still` `clip`  one of: `url` of a picture or mp4 (fetched and kept on the film, never hot-linked); the file itself as `base64` with its `filename` (up to 25 MB for a picture, 28 MB for a clip — a longer clip goes by `url`); `picture`, a picture of the film's by the id `boards` `from_the_film: images` gives (a shot's frames by the ids `from_the_film: shots` gives); or `mood_board`, a name — every picture on that Shotlister mood board, each its own card\n  `video`    `url` on YouTube or Vimeo — its player, title and picture\n  `link`     `url` of any page — its title, site and picture\n  `ref`      a reference, like Halcyon's: `title`, `kicker` (studio · year), `videos` (YouTube/Vimeo trailers), `stills` (picture urls), `clips` (mp4 urls). It opens to all of them, and any still or clip drags out as its own card.\n  `shot` `scene` `location` `day` — from the film itself, **live**: named by number or name (`shot: \"12A\"`, `scene: \"4\"`, `location: \"The Diner\"`, `day: \"Day 2\"`), made whole at once — frames, fields — and kept up to date whenever the page opens.\n  `person` `doc` — from the film's crew list and pinned documents, by `name`.\n  `gear` `idea` — `title`.\n\nCHANGE — `collapse: [ids]` folds cards to their picture and name, `expand: [ids]` opens them again (not notes, headings, stills or clips); `picture_only: [ids]` shows a card with a picture as the picture alone, no card round it, and `as_card: [ids]` puts it back; `resize: [{id, size}]` draws a card, words and all, at that many times its size (1 as made); `move: [{id, x, y}]`; `values: [{id, sort, value}]` (`id` may be a list; a line takes 0 at its left end to 1 at its right, or an end's name; columns take a column's name, \"\" for none); `text: [{id, text}]` (a card's own note line); `remove: [ids]` (a card published with the page is hidden, not destroyed).\n\nCOPY — `duplicate: [ids]` lays copies beside them, threads between them kept. `send: {cards: [ids], to: \"<slug>\", keep: true}` copies them onto another board of this film; `keep: false` moves them (the board's Cut and Paste).\n\nTHREADS — `tie: [{a, b, label}]` (`a` may be a list, to tie many cards to one under one label; a thread that already exists takes the new label), `label: [{a, b, label}]` to change a thread's label, `untie: [{a, b}]`.\n\nSORTS — `sorts` replaces the board's sorts with this list (see `add_board`). To rename one and keep its cards where they are, send `was` with the old name; the same for a column.\n\nTHE BOARD — `rename` (its name; its address stays), `restore` (a version id from `board` `history: true`, or \"latest\" — undo), and, his alone to change: `share` (`me`, `crew`, `link`) and `link_edit` (true lets people with the link change it, false lets them only look).\n\nADD TO SHOT — `to_shot: [{id, shot}]` files a still or clip on a shot in the film itself, where the Mac and iPhone see it. **Only when he asks for exactly that**; a board is for playing around.\n\nHIS RULES, from the first board: material, not commentary. Don't write captions, descriptions or opinions on cards and don't tie things together unless he asks — \"let me do that\". Lots of real material (trailers, many stills, clips) beats a few. Pictures keep their own shape.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The board's address." },
        add: { type: "array", items: { type: "object" } },
        move: { type: "array", items: { type: "object" } },
        values: { type: "array", items: { type: "object" } },
        text: { type: "array", items: { type: "object" } },
        remove: { type: "array", items: { type: "string" } },
        collapse: { type: "array", items: { type: "string" } },
        expand: { type: "array", items: { type: "string" } },
        picture_only: { type: "array", items: { type: "string" } },
        as_card: { type: "array", items: { type: "string" } },
        resize: { type: "array", items: { type: "object" }, description: "[{id, size}] — 1 as made, 2 twice as big, 0.3 to 5." },
        duplicate: { type: "array", items: { type: "string" } },
        send: { type: "object", description: "{cards: [ids], to: slug, keep: true|false}" },
        tie: { type: "array", items: { type: "object" } },
        label: { type: "array", items: { type: "object" } },
        untie: { type: "array", items: { type: "object" } },
        sorts: { type: "array", items: { type: "object" } },
        rename: { type: "string" },
        restore: { type: "string" },
        share: { type: "string" },
        link_edit: { type: "boolean" },
        to_shot: { type: "array", items: { type: "object" }, description: "[{id, shot}] — only when he asks." },
      },
      required: ["slug"],
    },
  },
  {
    name: "arrange_board",
    description: "Lay a board out in one go — the way he would tidy it by hand — instead of moving cards one at a time. Works out every position, leaves room between groups, and never puts a card on top of one it is not moving. The board as it was goes into History first, so `set_board` `restore` undoes it.\n\n`by`:\n  `grid`     a tidy grid (the default)\n  `row` / `column`   one straight row or column — with `near` and `side`, \"put these in a row under that card\"\n  `kind`     a group per kind — references, stills, clips, shots…\n  `scene` / `day`    a group per scene, or per shoot day, from the film: shots, scenes and days by what they are, the film's own pictures by the shot they belong to, anything else by what it is tied to\n  `sort`     by one of the board's sorts (`sort`: its name): a group per column, or spread along a line between its two ends, the way the board's own line view spreads them\n  `groups`   into named groups you choose: `groups: [{name, cards: [ids]}]`\n  `threads`  what is tied together, together\n\nGrouped layouts put a heading over each group (a heading of that name already on the board is moved there rather than made twice); `headings: false` leaves them off.\n\n`cards` is the ids to arrange; left out, it is every card (headings not reused stay where they are). `near` (a card id that stays put) with `side` (`below`, `above`, `left`, `right`) places the arrangement against that card; `at: {x, y}` puts its top left corner there; left out, a whole board is centred and a few cards are tidied where they were. `per_row` fixes how many to a row.\n\nIt arranges the free board — what anybody sees who is not looking through a sort. Read `board` first; the answer says what went where.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The board's address." },
        by: { type: "string", description: "grid, row, column, kind, scene, day, sort, groups or threads." },
        cards: { type: "array", items: { type: "string" }, description: "Which cards; all of them when left out." },
        sort: { type: "string", description: "For `by: sort` — the sort's name." },
        groups: { type: "array", items: { type: "object" }, description: "For `by: groups` — [{name, cards: [ids]}], in order." },
        headings: { type: "boolean", description: "A heading over each group. On for grouped layouts unless false." },
        near: { type: "string", description: "A card that stays put, to arrange against." },
        side: { type: "string", description: "below (default), above, left or right of `near`." },
        at: { type: "object", description: "{x, y} — where the top left corner goes." },
        per_row: { type: "number", description: "How many to a row." },
      },
      required: ["slug"],
    },
  },
];
