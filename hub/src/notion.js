/**
 * Refresh from Notion, in the worker — Ref 1155, his pick of 2026-09-23.
 *
 * **What this reverses, said plainly.** Until now the Mac held the only
 * Notion key, on purpose: a leak from Cloudflare could not read his
 * workspace, because Cloudflare had nothing to leak. His answer to Ref 1155
 * was option 2 — give the portal its own key so a Refresh button works from
 * the phone with the Mac asleep. The cost is bounded rather than removed:
 *
 * - **Its own connection, not his.** `NOTION_TOKEN` is a Notion integration he
 *   makes for this alone and connects to exactly four databases — Projects,
 *   Crew, Camera Spec Sheets, Project Docs. A leak reads those four and
 *   nothing else in the workspace. It can be revoked in Notion in one click.
 * - **Read only.** Nothing here writes to Notion; the integration is made
 *   with Read Content and nothing more.
 * - **Inert without it.** No secret, no button, and this module is never
 *   called. `hub/refresh.py` and its launchd job on the Mac are untouched and
 *   remain the other road — the Mac still draws the link covers, which a
 *   worker cannot (no canvas), and still runs every fifteen minutes.
 *
 * **What it reads is what `refresh.py` reads**, for one film at a time:
 * the Projects row's Status, Type, Length, Shoot Dates and icon; the
 * Logline / Director's Note / Visual Language paragraphs off its page; the
 * Project Docs rows ticked `Hub` (a document, or a page when `Page` or
 * `Section` names one); the Camera Spec Sheet row and its notes and files; the
 * Crew rows related to it, and the Director relation. Every rule is the
 * Python one ported, function for function, and each says which:
 * `both_kinds`, `both_roads`, `source_of`, `fed_by_notion`, `section_slug`.
 * Change a rule there and change it here in the same breath — two copies of
 * one rule is the drift `STATUS.md` records.
 *
 * **Not ported here, on purpose:** the film half (`facts`) — the hub reads
 * the film live (`cardOf`) — and the link covers. Both are in the portal's
 * own scheduled refresh (`refreshhub.js`, 2026-10-11), which is `refresh.py`
 * whole and reuses this file's leaves (exported for it); this file stays the
 * Refresh button's.
 */
import { notionIn, notionOut } from "./stageword.js";   // Notion says "Complete"; the record "Released"
import { keys } from "../../relay/layout.js";
import { storedFront, saveFront } from "./front.js";
import { portalOf, titleOf } from "./films.js";
import { recordView, layRecordFacts } from "./facts.js";
import { playerOf } from "./paper.js";
import { markOfRow } from "./notionmark.js";
import { fieldText } from "./entries.js";
import { specPills, colourIndex } from "./specpills.js";
import { boxesOfRow, recordSheets, laySheets, specSwitch } from "./specsheet.js";

const API = "https://api.notion.com/v1/";
const NOTION_VERSION = "2025-09-03";

// The four data sources, and nothing else — the same ids `refresh.py` names.
export const PROJECTS = "feedface-0000-4000-8000-000000000001";
export const PROJECT_DOCS = "feedface-0000-4000-8000-000000000005";
export const CAMERA_SHEETS = "feedface-0000-4000-8000-000000000003";
export const CREW = "feedface-0000-4000-8000-000000000004";
// **A project that shoots more than once** — `SHOOTS` in `refresh.py`. Not
// one of the four the portal's own connection was made for, so it may well be
// refused; then the shoots the Mac last wrote on the card stand in.
export const SHOOTS = "feedface-0000-4000-8000-000000000002";

/** Files this big are left in Notion rather than carried — `HELD_AT_MOST`. */
export const HELD_AT_MOST = 25 * 1024 * 1024;

/**
 * **How many outside calls one refresh may make.** A worker may only make so
 * many per request, and a bible of forty pictures in toggles in columns is a
 * lot of calls. Past this the run stops reading more pages and says so,
 * rather than being cut off half-written.
 */
const BUDGET = 700;

/** Whether this worker may read Notion at all. */
export function notionReady(env) {
  return Boolean(env && typeof env.NOTION_TOKEN === "string" && env.NOTION_TOKEN.trim());
}

export class Refused extends Error {}

/**
 * **A local stand-in may be named for checking, and only a local one.** The
 * battery runs this against a small fake Notion on this machine
 * (`hub/notionfake.mjs`); `NOTION_API` is honoured only when it points at
 * 127.0.0.1 or localhost, so nothing set on the live worker can send his key
 * anywhere but Notion.
 */
function apiOf(env) {
  const said = String(env.NOTION_API || "");
  return /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/v1\/$/.test(said) ? said : API;
}

export function asker(env, log) {
  const key = env.NOTION_TOKEN.trim();
  const base = apiOf(env);
  let spent = 0;
  const count = () => {
    spent += 1;
    if (spent > BUDGET) throw new Refused("stopped early — this film asks more of Notion than one refresh may");
  };
  async function notion(path, body) {
    count();
    const got = await fetch(base + path, {
      method: body === undefined ? "GET" : "POST",
      headers: {
        authorization: `Bearer ${key}`,
        "notion-version": NOTION_VERSION,
        "content-type": "application/json",
      },
      body: body === undefined ? undefined : JSON.stringify(notionOut(body)),
    });
    let answer = null;
    try { answer = notionIn(await got.json()); } catch { throw new Refused("Notion answered with something that is not JSON"); }
    if (!got.ok || (answer && answer.object === "error")) {
      throw new Refused(`${(answer && answer.code) || got.status}: ${String((answer && answer.message) || "").slice(0, 120)}`);
    }
    return answer;
  }
  async function fetchOut(url) {
    count();
    return await fetch(url);
  }
  return { notion, fetchOut, log, spent: () => spent };
}

// ------------------------------------------------------------ reading rows

export const plain = (rich) => (rich || []).map((bit) => bit.plain_text || "").join("").trim();

/** One property, whatever kind it is, as the words a person would read — `prop`. */
export function prop(row, name) {
  const field = ((row && row.properties) || {})[name];
  if (!field) return "";
  const kind = field.type;
  if (kind === "title" || kind === "rich_text") return plain(field[kind]);
  if (kind === "select") return (field.select || {}).name || "";
  if (kind === "status") return (field.status || {}).name || "";
  if (kind === "multi_select") return (field.multi_select || []).map((o) => o.name || "").join(", ");
  if (kind === "number") {
    const n = field.number;
    return n === null || n === undefined ? "" : String(Number.isInteger(n) ? n : n);
  }
  if (kind === "url" || kind === "email" || kind === "phone_number") return field[kind] || "";
  if (kind === "checkbox") return field.checkbox ? "yes" : "";
  if (kind === "date") return (field.date || {}).start || "";
  return "";
}

export function dates(row, name) {
  const got = ((((row && row.properties) || {})[name] || {}).date) || {};
  return { start: String(got.start || "").slice(0, 10), end: String(got.end || "").slice(0, 10) };
}

export const bare = (id) => String(id || "").replace(/-/g, "");

export function relatesTo(row, name, page) {
  const ids = ((((row && row.properties) || {})[name] || {}).relation || []).map((r) => bare(r.id));
  return ids.includes(bare(page));
}

/** A dashed id, the shape Notion's filters ask for. */
function dashed(id) {
  const b = bare(id);
  return b.length === 32 ? `${b.slice(0, 8)}-${b.slice(8, 12)}-${b.slice(12, 16)}-${b.slice(16, 20)}-${b.slice(20)}` : id;
}

/**
 * Every row of a data source related to one project — `rows_of`, narrowed.
 *
 * **Asked narrowly, checked anyway.** Notion is asked for only the rows whose
 * `Projects` relation holds this page, which is a handful of calls instead of
 * the whole Crew database; if Notion refuses the filter (a column renamed),
 * every row is read instead. Either way `relatesTo` is the rule, as in Python.
 */
async function rowsFor(ask, source, page, relation = "Projects") {
  const all = async (filter) => {
    const out = [];
    let cursor = null;
    do {
      const body = { page_size: 100, ...(filter ? { filter } : {}), ...(cursor ? { start_cursor: cursor } : {}) };
      const answer = await ask.notion(`data_sources/${source}/query`, body);
      out.push(...(answer.results || []));
      cursor = answer.has_more ? answer.next_cursor : null;
    } while (cursor);
    return out;
  };
  let rows;
  try {
    rows = page ? await all({ property: relation, relation: { contains: dashed(page) } }) : await all(null);
  } catch (problem) {
    if (!page || /stopped early/.test(problem.message)) throw problem;
    rows = await all(null);
  }
  return page ? rows.filter((row) => relatesTo(row, relation, page)) : rows;
}

export const HEADINGS = { "logline": "logline", "director's note": "note", "visual language": "look" };

/** The logline, the director's note and the visual language, off the page — `prose`. */
function placeholder(words) {
  return /^\*?insert here\*?$/i.test(words) || /^add the director['’]s creative note here\b/i.test(words);
}

export async function prose(ask, page) {
  const said = { logline: "", note: "", look: "" };
  let blocks = [];
  try {
    blocks = (await ask.notion(`blocks/${page}/children?page_size=100`)).results || [];
  } catch (problem) {
    if (/stopped early/.test(problem.message)) throw problem;
    return said;
  }
  let under = null;
  for (const block of blocks) {
    const kind = block.type || "";
    if (kind.startsWith("heading_")) {
      under = HEADINGS[plain((block[kind] || {}).rich_text).toLowerCase().trim()] || null;
    } else if (kind === "paragraph" && under) {
      const words = plain(block.paragraph.rich_text);
      // "*Insert here*" is a placeholder he has not filled in, and so is the
      // template's "Add the director's creative note here: …" (Halcyon,
      // 2026-09-23). `PLACEHOLDER` in `refresh.py` is the same rule.
      if (words && !placeholder(words)) said[under] = `${said[under]} ${words}`.trim();
    } else if (kind === "divider" || kind === "column_list" || kind === "child_database") {
      under = null;
    }
  }
  return said;
}

/**
 * **The logline is a property of the Projects row** (2026-10-05, his pick —
 * option B of the Notion link proposal). The page's "Logline" heading is read
 * only while the property is empty, for a page not moved yet. `typed_words`
 * in refresh.py and `notionlink.notion_words` in Projects Console are the same
 * rule.
 */
export const TYPED = { logline: "Logline", note: "Director's Note", look: "Visual Language" };

/**
 * The director's note and the visual language joined the logline as row
 * properties on 2026-10-05 (his templates decision) — `TYPED` in refresh.py.
 * Paragraph breaks in a box become single spaces, as the headings'
 * paragraphs always were.
 */
export function typedWords(row, said) {
  for (const [field, column] of Object.entries(TYPED)) {
    const words = String(prop(row, column) || "").split(/\s+/).filter(Boolean).join(" ");
    if (words) said[field] = words;
  }
  return said;
}

// ------------------------------------------------ a Notion page, drawn here

export const SECTION_BLOCKS = {
  heading_1: "h1", heading_2: "h2", heading_3: "h3",
  paragraph: "p", quote: "quote", callout: "callout",
  bulleted_list_item: "li", numbered_list_item: "li", to_do: "li",
  toggle: "toggle", image: "img", divider: "hr",
  column_list: "columns", column: "column",
  file: "file", pdf: "file", table: "table", table_row: "trow",
  // **A clip** (Ref 1543): an uploaded one is kept like a file; a link stays
  // a link. An embed is a clip only when it is a player (`playerOf`).
  video: "video", embed: "video",
};

/** A name a URL can carry — `slug_of`. */
export function slugOf(name) {
  const made = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
  return made || "section";
}

export const BIBLE_NAMES = new Set(["bible", "visual-bible", "visual-language-bible"]);
export const FILM_SCREENS = new Set(["shotlist", "shots", "locations", "boards", "schedule"]);

/** Where a section he has named is drawn — `section_slug`. */
export function sectionSlug(name) {
  const made = slugOf(name);
  return BIBLE_NAMES.has(made) ? "bible" : made;
}

/** `Page` first, `Section` for as long as it exists — `page_column`. */
export const pageColumn = (doc) => prop(doc, "Page") || prop(doc, "Section");

/** Rich text as words plus links — `linked`. */
export function linked(rich) {
  const out = [];
  for (const bit of rich || []) {
    const words = bit.plain_text || "";
    if (!words) continue;
    out.push(bit.href ? { s: words, u: bit.href } : { s: words });
  }
  return out;
}

export function hostOf(url) {
  try { return new URL(url).host.replace("www.", "") || "link"; } catch { return "link"; }
}

export function namedBy(url, fallback = "") {
  try {
    const path = new URL(url).pathname;
    return decodeURIComponent(path.split("/").pop() || "") || fallback;
  } catch {
    return fallback;
  }
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * **Notion's own links to its files expire within the hour**, so each is
 * fetched once and kept beside the film's pictures under the hash of its
 * address — `mirror_picture` and `mirror_file`, with the same names, so a
 * picture the Mac already carried is not carried again: a name already in
 * the bucket is not fetched at all.
 */
export async function mirror(env, ask, url, project, picture) {
  if (!url) return null;
  let ext = "";
  if (picture) {
    const got = /\.(jpe?g|png|gif|webp|avif)(?:\?|$)/i.exec(url);
    ext = got ? got[1].toLowerCase() : "jpg";
  } else {
    const tail = namedBy(url).includes(".") ? namedBy(url).split(".").pop() : "";
    ext = /^[A-Za-z0-9]{1,8}$/.test(tail) ? tail.toLowerCase() : "bin";
  }
  const name = `${(await sha256Hex(url.split("?")[0])).slice(0, 32)}.${ext}`;
  const key = keys.medium(project, name);
  const held = await env.BUCKET.head(key);
  if (held) return { file: name, bytes: held.size };
  let got;
  try { got = await ask.fetchOut(url); } catch (problem) {
    if (/stopped early/.test(problem.message)) throw problem;
    return null;
  }
  if (!got.ok) return null;
  const size = Number(got.headers.get("content-length") || 0);
  if (!picture && size > HELD_AT_MOST) return null;
  const bytes = new Uint8Array(await got.arrayBuffer());
  if (!bytes.length || (!picture && bytes.length > HELD_AT_MOST)) return null;
  await env.BUCKET.put(key, bytes);
  return { file: name, bytes: bytes.length };
}

async function childrenOf(ask, block) {
  const out = [];
  let cursor = null;
  do {
    let answer;
    try {
      answer = await ask.notion(`blocks/${block}/children?page_size=100${cursor ? `&start_cursor=${cursor}` : ""}`);
    } catch (problem) {
      if (/stopped early/.test(problem.message)) throw problem;
      return out;
    }
    out.push(...(answer.results || []));
    cursor = answer.has_more ? answer.next_cursor : null;
  } while (cursor);
  return out;
}

/** One Notion page as the small tree the portal draws — `read_blocks`. */
export async function readBlocks(env, ask, block, project, seen, depth = 0) {
  if (depth > 4) return [];
  const made = [];
  for (const raw of await childrenOf(ask, block)) {
    const kind = raw.type || "";
    const as = SECTION_BLOCKS[kind];
    if (!as) continue;
    const body = raw[kind] || {};
    const node = { t: as };
    if (as === "img") {
      const where = (body.file || {}).url || (body.external || {}).url || "";
      if (!seen.has(where)) seen.set(where, await mirror(env, ask, where, project, true));
      const got = seen.get(where);
      if (!got) continue;
      node.src = got.file;
      node.cap = plain(body.caption);
    } else if (as === "file") {
      const outside = body.type === "external";
      const where = ((outside ? body.external : body.file) || {}).url || "";
      if (!where) continue;
      node.name = plain(body.caption) || (outside ? hostOf(where) : namedBy(where, "File"));
      if (outside) {
        node.url = where;
      } else {
        if (!seen.has(where)) seen.set(where, await mirror(env, ask, where, project, false));
        const got = seen.get(where);
        if (!got) continue;
        node.src = got.file;
        node.bytes = got.bytes;
      }
    } else if (as === "video") {
      const outside = kind === "embed" || body.type === "external";
      const where = kind === "embed" ? body.url || "" : ((outside ? body.external : body.file) || {}).url || "";
      if (!where) continue;
      if (outside) {
        if (kind === "embed" && !playerOf(where)) continue;
        if (!/^https?:\/\//i.test(where)) continue;
        node.url = where;
      } else {
        if (!seen.has(where)) seen.set(where, await mirror(env, ask, where, project, false));
        const got = seen.get(where);
        if (!got) continue;
        node.src = got.file;
      }
      const cap = plain(body.caption);
      if (cap) node.cap = cap;
    } else if (as === "table") {
      node.head = Boolean(body.has_column_header);
    } else if (as === "trow") {
      node.c = (body.cells || []).map(linked);
    } else if (as !== "hr") {
      node.r = linked(body.rich_text);
      if (as === "li") node.n = kind === "numbered_list_item";
    }
    if (raw.has_children && !["img", "file", "trow", "video"].includes(as)) {
      node.k = await readBlocks(env, ask, raw.id, project, seen, depth + 1);
    }
    // An empty paragraph is a blank line in Notion and nothing at all here.
    if (as === "p" && !(node.r && node.r.length) && !(node.k && node.k.length)) continue;
    made.push(node);
  }
  return made;
}

export async function putPage(env, project, slug, tree) {
  await env.BUCKET.put(keys.page(project, slug), JSON.stringify(tree), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

// --------------------------------------------------- the rules, as in Python

const SOURCES = new Set(["notion", "notion-once", "here", "program", "drive"]);

/** Where a page's or a document's words come from — `source_of`. */
export function sourceOf(thing) {
  if (SOURCES.has(thing.source)) return thing.source;
  if (thing.by === "deck") return "program";
  if (thing.by === "mcp" || thing.file) return "here";
  return "notion";
}

export const fedByNotion = (section) => sourceOf(section) === "notion";

/** Keep the documents that are his; refresh the ones that are Notion's — `both_kinds`. */
export function bothKinds(already, fromNotionNow) {
  const mine = already.filter((d) => sourceOf(d) !== "notion");
  const named = new Set(mine.map((d) => String(d.name || "").trim().toLowerCase()));
  // **A Notion document renamed on the portal keeps the portal's name**: it
  // remembers Notion's in `was`, and the row Notion sends under that name
  // wears the portal's again instead of arriving as a second card.
  const worn = new Map(already.filter((d) => d.was && sourceOf(d) === "notion").map((d) => [String(d.was).trim().toLowerCase(), d.name]));
  const fresh = fromNotionNow.map((d) => {
    const key = String(d.name || "").trim().toLowerCase();
    return worn.has(key) ? { ...d, name: worn.get(key), was: d.name } : d;
  });
  return [...mine, ...fresh.filter((d) => !named.has(String(d.name || "").trim().toLowerCase()))];
}

/** Keep the pages Notion is not feeding; refresh the ones it is — `both_roads`. */
export function bothRoads(already, fromNotionNow, named) {
  const fresh = new Map(fromNotionNow.map((s) => [s.slug, s]));
  const says = new Set(named || fresh.keys());
  const kept = [];
  for (const section of already) {
    const slug = section.slug;
    if (!fedByNotion(section)) {
      kept.push({ ...section, notion: says.has(slug) });
      fresh.delete(slug);
      continue;
    }
    if (fresh.has(slug)) {
      const took = { ...fresh.get(slug), source: "notion", notion: true };
      if (section.by) took.by = section.by;
      fresh.delete(slug);
      kept.push(took);
      continue;
    }
    if (section.by === "mcp" || section.by === "deck") kept.push({ ...section, notion: says.has(slug) });
    // Otherwise: Notion's row, and Notion has dropped it. Gone, as always.
  }
  for (const one of fresh.values()) kept.push({ ...one, notion: true });
  return kept;
}

/** The film's icon and colour, off its Notion row — `mark_of`. */
export async function markOf(ask, row) {
  // The pair itself is `notionmark.js`, shared with the portal's refresh and
  // the next step's `mirror_mark`; only the fetch is this module's.
  return await markOfRow(row, async (address) => {
    try {
      const got = await ask.fetchOut(address);
      return got.ok ? await got.text() : "";
    } catch (problem) {
      if (/stopped early/.test(problem.message)) throw problem;
      return "";
    }
  });
}

/** Who the row's Director relation names — `director_of`. */
async function directorOf(ask, row, crew) {
  const named = [];
  const known = new Map(crew.map((mate) => [bare(mate.id), mate]));
  for (const who of ((((row.properties || {}).Director) || {}).relation) || []) {
    const page = bare(who.id);
    let mate = known.get(page);
    if (!mate && page) {
      try { mate = await ask.notion(`pages/${page}`); } catch (problem) {
        if (/stopped early/.test(problem.message)) throw problem;
        mate = null;
      }
    }
    const name = mate ? prop(mate, "Name") : "";
    if (name) named.push(name);
  }
  return named.join(" & ");
}

export const CAMERA_FROM = {
  body: "Camera", lenses: "Lenses", format: "Shooting Format",
  capture: "Capture Resolution",
  colour: "Color Space", codec: "Codec", fps: "Frame Rate",
  desqueeze: "Desqueeze",
  // a label per Production LUT (src/entries.js); "" until the property exists
  luts: "LUT Labels",
};

/** A Files property, as things the portal can point at — `files_on`. */
export function filesOn(row, name) {
  const out = [];
  for (const one of ((((row.properties || {})[name]) || {}).files) || []) {
    const outside = one.type === "external";
    const where = ((outside ? one.external : one.file) || {}).url || "";
    if (!where) continue;
    let said = String(one.name || "").trim();
    if (!said || said.startsWith("http")) said = outside ? name : namedBy(where, name);
    out.push({ name: said, url: where, held: !outside });
  }
  return out;
}

/** The same notes with the files it names taken out — `without`. */
export function without(tree, names) {
  const kept = [];
  for (const node of tree) {
    if (node.t === "file" && names.has(String(node.name || "").trim().toLowerCase())) continue;
    if (node.k) node.k = without(node.k, names);
    kept.push(node);
  }
  return kept;
}

// ------------------------------------------------------------- the shoots

/** The page ids a relation holds, undashed — `related`. */
export function related(row, name) {
  return ((((row && row.properties) || {})[name] || {}).relation || []).map((r) => bare(r.id));
}

/** `Shoot 2` out of `Lets Bake — Shoot 2` — `shoot_name`. */
function shootName(title, project) {
  const loose = (words) => String(words || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  const parts = String(title || "").split(/\s+[—–-]\s+/);
  if (parts.length > 1 && loose(parts[0]) === loose(project)) return parts.slice(1).join(" - ").trim();
  return String(title || "").trim();
}

/**
 * **A shoot's own name** (2026-10-05) — `shoot_parts` in refresh.py, and
 * `name_of` in Projects Console's shoots.py. He can name a shoot
 * ("Malibu Pickup"); its Notion title keeps the number in front —
 * `Lets Bake — Shoot 2 · Malibu Pickup` — and **the address stays the
 * number's**: `base` ("Shoot 2") makes the slug and matches `Shoot 2
 * Details`, `name` is what the portal shows. A title with no name of its own
 * is exactly as before: both are the words after the project's name.
 */
const DEFAULT_SHOOT = /^(?:principal|additional shoot(?:\s+\d+)?|shoot(?:\s+\d+)?)$/i;
export function shootParts(words) {
  const said = String(words || "").trim();
  const m = /\(?\bShoot\s+(\d+)\b\)?/i.exec(said);
  if (!m || DEFAULT_SHOOT.test(said)) return { base: said, name: said };
  const own = `${said.slice(0, m.index)} ${said.slice(m.index + m[0].length)}`
    .replace(/\s+/g, " ").replace(/^[\s·:—–|,-]+|[\s·:—–|,-]+$/g, "");
  if (!own || DEFAULT_SHOOT.test(own)) return { base: said, name: said };
  return { base: `Shoot ${m[1]}`, name: own };
}

/**
 * The project's shoots, oldest first — `shoots_of`. **When Notion refuses**
 * (the portal's connection was made for four databases, and Shoots is a
 * fifth) the shoots the Mac last wrote on the card stand in, so a Refresh
 * from the phone never forgets which shoot is next.
 */
async function shootsOf(ask, page, project, card) {
  let rows;
  try {
    rows = await rowsFor(ask, SHOOTS, page, "Project");
  } catch (problem) {
    if (/stopped early/.test(problem.message)) throw problem;
    return (card.shoots || []).map((one) => ({
      id: one.id, name: one.name, base: one.base || one.name, status: one.status,
      dates: { start: one.start || "", end: one.end || "" },
      sheets: one.sheet ? [one.sheet] : [], crew: [], docs: [], sections: one.sections || [],
      changes: one.changes || "", created: "", stored: one,
    }));
  }
  const out = rows.map((row) => ({
    id: bare(row.id),
    ...shootParts(shootName(prop(row, "Shoot"), project) || "Shoot"),
    status: prop(row, "Status"),
    dates: dates(row, "Dates"),
    changes: prop(row, "What Changes"),
    sections: prop(row, "Shot List Section").split(",").map((one) => one.trim()).filter(Boolean),
    crew: related(row, "Crew"),
    sheets: related(row, "Camera Spec Sheet"),
    docs: related(row, "Docs"),
    created: row.created_time || "",
  }));
  out.sort((a, b) => ((a.dates.start || "9999") + a.created).localeCompare((b.dates.start || "9999") + b.created));
  return out;
}

/** The earliest Upcoming shoot, or the latest once all have wrapped — `lead_of`. */
export function leadOf(shoots) {
  if (!shoots.length) return null;
  return shoots.find((one) => String(one.status).toLowerCase() === "upcoming") || shoots[shoots.length - 1];
}

const newest = (rows) => rows.reduce((a, b) => (String(b.created_time || "") > String(a.created_time || "") ? b : a));

/** Which spec sheet a shoot uses — `sheet_for`, the same three steps. */
function sheetFor(shoot, sheets, shoots, say, label = "") {
  if (shoot) {
    const own = sheets.filter((s) => shoot.sheets.includes(bare(s.id)) || related(s, "Shoot").includes(shoot.id));
    if (own.length) return newest(own);
  }
  let mine = sheets.filter((s) => !s.notOurs);
  if (shoots.length) {
    const ours = new Set(shoots.map((one) => one.id));
    const whole = mine.filter((s) => !related(s, "Shoot").some((id) => ours.has(id)));
    if (whole.length) mine = whole;
  }
  if (!mine.length) return null;
  const pick = newest(mine);
  if (mine.length > 1) {
    say(`${mine.length} spec sheets${label ? ` for ${label}` : ""} and none says which shoot — using the newest, “${prop(pick, "Title") || prop(pick, "Lenses")}”`);
  }
  return pick;
}

// ---------------------------------------------------------------- the run

/** Which Notion project this film is, and how it was found — `page_for`. */
async function pageFor(env, ask, project, card) {
  {
    // A portal's mark names its Notion page (a minted project's portal lives
    // under its ID, not its page); an older mark names the project itself.
    const mark = await portalOf(env, project);
    if (mark) return { page: mark.page || project, how: "link" };
  }
  const said = /^notion:([0-9a-f-]{32,36})$/.exec(String(card.source || ""));
  if (said) return { page: bare(said[1]), how: card.linked === "name" ? "name" : "link" };
  const title = String(await titleOf(env, project)).trim().toLowerCase();
  for (const row of await rowsFor(ask, PROJECTS, "")) {
    if (prop(row, "Project").trim().toLowerCase() === title) return { page: bare(row.id), how: "name" };
  }
  return { page: "", how: "" };
}

/**
 * **Pages that follow Notion** (his rule, 2026-10-17): a page follows Notion
 * only when it says so itself: `source: "notion"` (Live from Notion) and
 * `from`, the Notion page it was made from.
 */
export function followingPages(card) {
  return (card.sections || []).filter((s) => s && s.source === "notion" && /^[0-9a-f]{32}$/.test(String(s.from || "").replace(/-/g, "")));
}

/**
 * **The Refresh from Notion button**, and the Console's refresh. Narrowed the
 * same way as the clock (2026-10-17): only pages set up to follow Notion are
 * drawn again, each from its own Notion page. The logline, synopsis, people,
 * documents, spec sheet, shoots and mark are never read from Notion. Returns
 * the lines it would print and whether anything went wrong.
 */
export async function refreshFilm(env, project) {
  const lines = [];
  const say = (line) => lines.push(line);
  // **The card as stored, not `storedFront`**: that one drops a page's `from`
  // (front.js `section`), which is the whole of what says where it follows.
  let card = {};
  try {
    const got = await env.BUCKET.get(keys.front(project));
    card = got ? JSON.parse(await got.text()) : {};
  } catch { card = {}; }
  if (!card || typeof card !== "object" || Array.isArray(card)) card = {};
  const pages = followingPages(card);
  if (!pages.length) return { ok: true, lines: ["No page here follows Notion, so there is nothing to refresh."] };
  if (!notionReady(env)) return { ok: false, lines: ["No Notion connection is set up on the portal."] };
  const ask = asker(env, say);
  let trouble = 0;
  let drawn = 0;
  for (const section of pages) {
    let tree;
    try {
      tree = await readBlocks(env, ask, String(section.from).replace(/-/g, ""), project, new Map());
    } catch (problem) {
      say(`Could not read “${section.name}”: ${problem.message}`);
      trouble += 1;
      if (/stopped early/.test(problem.message)) break;
      continue;
    }
    if (!tree.length) {
      say(`“${section.name}”: its Notion page is empty, left as it was`);
      continue;
    }
    await putPage(env, project, section.slug, tree);
    section.blocks = tree.length;
    section.synced = new Date().toISOString(); // the page's Synced from line (pages.js)
    drawn += 1;
    say(`“${section.name}” drawn from Notion — ${tree.length} blocks`);
  }
  if (!drawn) return { ok: trouble === 0, lines };
  card.updated = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  await env.BUCKET.put(keys.front(project), JSON.stringify(card), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  return { ok: trouble === 0, lines, updated: card.updated };
}

/** The old whole refresh (crew, documents, sheet, shoots). Not called; kept in case he wants any of it back. */
/**
 * **Refresh one film's words from Notion, here.** Returns the lines it would
 * have printed — `refresh.py` says what it did, and so does this — and
 * whether anything went wrong. Never throws for Notion's sake: a refusal is
 * a line, and the card is left as it was.
 */
async function refreshFilmEverything(env, project) {
  const lines = [];
  const say = (line) => lines.push(line);
  if (!notionReady(env)) return { ok: false, lines: ["No Notion connection is set up on the portal."] };
  const ask = asker(env, say);
  let trouble = 0;
  const card = await storedFront(env, project);
  try {
    const { page, how } = await pageFor(env, ask, project, card);
    card.linked = how;
    if (!page) {
      say("No Notion project matches this film — its words are left as they were.");
      return { ok: false, lines };
    }
    const row = await ask.notion(`pages/${page}`);
    const said = typedWords(row, await prose(ask, page));
    Object.assign(said, {
      mark: await markOf(ask, row),
      status: prop(row, "Status"),
      type: prop(row, "Type"),
      length: prop(row, "Length"),
      shoot: dates(row, "Shoot Dates"),
      source: `notion:${page}`,
    });

    // **A project that shoots more than once** (SL-1395, SL-1396) — read
    // first, so a document can say which shoot it is for.
    const shoots = await shootsOf(ask, page, prop(row, "Project"), card);
    const fresh = shoots.length > 0 && !shoots[0].stored;
    const lead = leadOf(shoots);
    const slugFor = new Map(shoots.map((one) => [one.id, slugOf(one.base || one.name)]));
    // With Shoots refused, a row keeps the shoots the Mac last tagged it with.
    const before = new Map([...(card.documents || []), ...(card.sections || [])].map((one) => [one.name, one.shoots || []]));
    const tagged = (doc, name) => {
      if (!fresh) return before.get(name) || [];
      const mine = new Set(related(doc, "Shoot"));
      return shoots.filter((one) => mine.has(one.id) || one.docs.includes(bare(doc.id))).map((one) => slugFor.get(one.id));
    };

    // **Only what he has ticked.** His rule, and the whole of it.
    const documents = [];
    const sections = [];
    for (const doc of await rowsFor(ask, PROJECT_DOCS, page)) {
      if (!prop(doc, "Hub")) continue;
      const name = prop(doc, "Name");
      let section = pageColumn(doc);
      if (section && FILM_SCREENS.has(sectionSlug(section))) {
        say(`“${section}” is one of the film's own screens — “${name}” stays a document`);
        section = "";
      }
      if (section) {
        const slug = sectionSlug(section);
        sections.push({ slug, name: section, from: bare(doc.id), title: name, type: slug === "camera" ? "sheet" : "page", source: "notion", shoots: tagged(doc, section) });
        continue;
      }
      documents.push({
        name,
        kind: name.toLowerCase().includes("look") ? "lookbook" : "document",
        url: prop(doc, "URL") || doc.url || "",
        source: "notion",
        shoots: tagged(doc, name),
      });
    }

    // **A page taken over on the portal is not fetched again** — Ref 871.
    const agents = new Set((card.sections || []).filter((s) => !fedByNotion(s)).map((s) => s.slug));
    const fetched = [];
    for (const section of sections) {
      if (agents.has(section.slug)) {
        say(`“${section.name}” is written on the portal now — left alone`);
        continue;
      }
      let tree;
      try {
        tree = await readBlocks(env, ask, section.from, project, new Map());
      } catch (problem) {
        say(`Could not read “${section.name}”: ${problem.message}`);
        trouble += 1;
        if (/stopped early/.test(problem.message)) break;
        continue;
      }
      if (!tree.length) continue;
      await putPage(env, project, section.slug, tree);
      fetched.push(section);
      say(`“${section.name}” drawn from Notion — ${tree.length} blocks`);
    }

    // The spec sheet: its ten boxes, its files, its notes. **The next
    // shoot's** (SL-1395) — the first one Notion listed, before.
    const sheets = await rowsFor(ask, CAMERA_SHEETS, page);
    for (const id of fresh ? shoots.flatMap((one) => one.sheets) : lead ? lead.sheets : []) {
      if (sheets.some((s) => bare(s.id) === id)) continue;
      try { sheets.push({ ...(await ask.notion(`pages/${id}`)), notOurs: true }); } catch (problem) {
        if (/stopped early/.test(problem.message)) throw problem;
      }
    }
    // pills one per line (entries.fieldText), the way every reader takes a line
    // **The Old columns where they kept the camera labels** (specsheet.js,
    // 2026-10-14): the pills alone flatten a two camera sheet, so a box is
    // read the way the move reads it, as labelled lines.
    const pillNames = Object.fromEntries(Object.entries(await specPills(env)).map(([k, v]) => [k, (v || []).map((o) => o.name)]));
    const boxes = (row) => (row ? boxesOfRow(row, pillNames) : Object.fromEntries(Object.keys(CAMERA_FROM).map((field) => [field, ""])));
    /** A sheet's files carried across and its notes read — the lead's and each shoot's alike. */
    const sheetOf = async (row, notesAt) => {
      const carried = [];
      for (const one of row ? filesOn(row, "Production LUT") : []) {
        if (!one.held) { carried.push({ name: one.name, url: one.url }); continue; }
        const got = await mirror(env, ask, one.url, project, false);
        if (got) carried.push({ name: one.name, file: got.file, bytes: got.bytes });
      }
      let notes = [];
      if (row) {
        try {
          notes = await readBlocks(env, ask, bare(row.id), project, new Map());
        } catch (problem) {
          say(`Could not read the spec sheet's notes: ${problem.message}`);
          trouble += 1;
        }
      }
      notes = without(notes, new Set(carried.map((one) => one.name.trim().toLowerCase())));
      await putPage(env, project, notesAt, notes);
      return { files: carried, notes: notes.length, tree: notes };
    };
    const sheet = sheetFor(lead, sheets, shoots, say);
    const camera = boxes(sheet);
    const theLead = await sheetOf(sheet, "camera-sheet");
    if (sheet && lead) say(`The spec sheet is ${lead.name}'s — ${camera.lenses || "no lenses named"}`);

    const person = (mate) => ({
      name: prop(mate, "Name"), role: prop(mate, "Role"),
      department: prop(mate, "Department"), company: prop(mate, "Company"),
      email: prop(mate, "Email"), phone: prop(mate, "Phone"),
    });
    const crewRows = await rowsFor(ask, CREW, page);
    let crew = crewRows.map(person);

    // **Each shoot on the card** — `refresh.py` writes the same: its own
    // crew, sheet, files and notes. Only when Notion said; a refusal keeps
    // what the Mac last wrote, and the front leads with the stored next
    // shoot's crew.
    let shootsNow = null;
    if (fresh) {
      const ours = new Set(shoots.map((one) => one.id));
      const onSome = new Set(shoots.flatMap((one) => one.crew));
      const known = new Map(crewRows.map((mate) => [bare(mate.id), mate]));
      for (const id of onSome) {
        if (known.has(id)) continue;
        try { known.set(id, await ask.notion(`pages/${id}`)); } catch (problem) {
          if (/stopped early/.test(problem.message)) throw problem;
        }
      }
      const whole = crewRows.filter((mate) => !related(mate, "Shoots").some((id) => ours.has(id)) && !onSome.has(bare(mate.id)));
      shootsNow = [];
      for (const one of shoots) {
        const own = sheetFor(one, sheets, shoots, say, one.name);
        const slug = slugFor.get(one.id);
        const mine = [...known.values()].filter((mate) => related(mate, "Shoots").includes(one.id) || one.crew.includes(bare(mate.id)));
        // **Read again only when it changed** (Ref 1413) — the lead's is the
        // one just read; another's files and notes stand while its sheet has
        // not moved in Notion. Many shoots, most of them wrapped.
        const was = (card.shoots || []).find((x) => x.id === one.id);
        const edited = own ? String(own.last_edited_time || "") : "";
        const lead_ = own && sheet && bare(own.id) === bare(sheet.id);
        // Its own copy too, for when another shoot leads.
        if (lead_) await putPage(env, project, `camera-sheet-${slug}`, theLead.tree);
        const held = lead_ ? theLead
          : own && was && was.sheet === bare(own.id) && was.sheet_edited && was.sheet_edited === edited
            ? { files: was.camera_files || [], notes: was.camera_notes || 0 }
            : await sheetOf(own, `camera-sheet-${slug}`);
        shootsNow.push({
          id: one.id, name: one.name, base: one.base || one.name, slug, status: one.status,
          start: one.dates.start, end: one.dates.end, changes: one.changes, sections: one.sections,
          sheet: own ? bare(own.id) : "", sheet_edited: own ? String(own.last_edited_time || "") : "", camera: boxes(own),
          camera_files: held.files, camera_notes: held.notes,
          crew: [...mine, ...whole].map(person),
        });
        // **One shoot is no shoots** (his ruling): People is the project's.
        if (one === lead && shoots.length > 1) crew = shootsNow[shootsNow.length - 1].crew;
      }
      if (shoots.length > 1) say(`${shoots.length} shoots — the portal leads with ${lead.name}`);
    } else if (lead && lead.stored && shoots.length > 1 && (lead.stored.crew || []).length) {
      crew = lead.stored.crew;
    }
    const director = await directorOf(ask, row, crewRows);

    const was = { documents: (card.documents || []).length, crew: (card.crew || []).length };
    Object.assign(card, said, {
      documents: bothKinds(card.documents || [], documents),
      sections: bothRoads(card.sections || [], fetched, sections.map((s) => s.slug)),
      camera,
      // the lead sheet's page, for the kit door to edit (Ref 1627)
      camera_sheet: sheet ? bare(sheet.id) : "",
      camera_files: theLead.files,
      camera_notes: theLead.notes,
      // each pill's Notion colour, for the camera page (src/specpills.js)
      camera_pills: colourIndex(await specPills(env)),
      crew,
    });
    if (shootsNow) card.shoots = shootsNow;
    else if (!shoots.length) card.shoots = [];
    if (director) card.director = director;
    // **The record's typed facts win** — `from_record` in refresh.py. Without
    // this, Refresh here put Notion's words back over what he typed in the
    // record, and the Mac's run put them back fifteen minutes later.
    const view = await recordView(env, page);
    const typed = layRecordFacts(card, view.facts, view.hidden);
    if (typed.length) say(`The record's ${typed.join(", ")} kept over Notion's`);
    // the spec sheets the record holds, once the switch is on (specsheet.js)
    if ((await specSwitch(env)).on) {
      const laid = laySheets(card, recordSheets(view.facts));
      if (laid.length) say(`The record's spec sheet for ${laid.join(", ")} kept over Notion's`);
    }
    const many = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
    const moved = (word, a, b) => (a === b ? many(b, word) : `${a} → ${many(b, word)}`);
    say(`Notion: ${moved("document", was.documents, card.documents.length)}, ${moved("contact", was.crew, card.crew.length)}${
      Object.values(camera).some(Boolean) ? ", a camera spec sheet" : ""}`);
  } catch (problem) {
    say(`Could not read Notion for it: ${problem.message}`);
    return { ok: false, lines };
  }
  card.updated = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  await saveFront(env, project, card);
  return { ok: trouble === 0, lines, updated: card.updated };
}
