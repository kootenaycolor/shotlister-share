/**
 * **What a Library cover says**: one real thing each, nothing invented.
 *
 * - a **deck** says its own first heading and how many slides it has
 * - a **written page** says its first heading
 * - a **board** says how many pins it holds
 *
 * **Not read on every load.** A Worker request holds six open answers at once
 * and a Library of twenty pages must not open twenty bodies to draw its
 * covers. So the answers are kept in one small object,
 * `p/<film>/covers.json`, each stamped with the write time of the object it
 * was read from. A load lists the film's pages, decks and boards (names and
 * write times only, no bodies, the same listing `since.js` makes), compares
 * stamps, and reads a body only where the stamp has moved: once ever for a
 * page that has never been read, once more each time somebody writes it.
 * No write path has to know this exists. At most `READS` bodies are read per
 * load, one after another, so a first look at a big film fills the rest in
 * over the next few loads rather than in one long request.
 *
 * **A slide** is a section of a deck that is switched on (`record.sections`
 * in `decks/<slug>.json`), which is what the deck editor's rail lists; a deck
 * with no record falls back to the `sec` blocks of its published page.
 */
import { keys } from "../../relay/layout.js";

const READS = 8;
const HEAD_BYTES = 262144;

const key = (project) => `${keys.pages(project).replace(/pages\/$/, "")}covers.json`;

const clean = (text) => String(text || "")
  .replace(/<[^>]*>/g, " ")
  .replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
  .replace(/&quot;/g, '"').replace(/&#0?39;|&apos;/g, "'").replace(/&#8217;/g, "’")
  .replace(/\s+/g, " ").trim().slice(0, 90);

/** The first heading in a page's tree, looking one level into columns and toggles. */
export function headingOf(tree) {
  const walk = (nodes, depth) => {
    for (const node of Array.isArray(nodes) ? nodes : []) {
      if (node && /^h[123]$/.test(node.t)) {
        const said = clean((node.r || []).map((bit) => bit.s).join(""));
        if (said) return said;
      }
      if (node && depth < 3 && node.k) {
        const inner = walk(node.k, depth + 1);
        if (inner) return inner;
      }
    }
    return "";
  };
  return walk(tree, 0);
}

/** The first heading in a published page's markup. */
export function headingOfHtml(html) {
  const found = /<h[123][^>]*>([\s\S]*?)<\/h[123]>/i.exec(String(html || ""));
  return found ? clean(found[1]) : "";
}

async function bodyOf(env, k, ranged = false) {
  try {
    const got = await env.BUCKET.get(k, ranged ? { range: { offset: 0, length: HEAD_BYTES } } : undefined);
    return got ? await got.text() : null;
  } catch {
    return null;
  }
}

/** Read one cover's facts. Never throws; nothing found is `{}`. */
async function readOne(env, project, want, stamps) {
  if (want.type === "deck") {
    const record = await bodyOf(env, keys.deck(project, want.slug));
    let n = 0;
    if (record) {
      try {
        const parsed = JSON.parse(record);
        n = (Array.isArray(parsed.sections) ? parsed.sections : []).filter((s) => s && s.on !== false).length;
      } catch { /* the page below is the fallback */ }
    }
    const html = stamps.html ? await bodyOf(env, keys.pageHtml(project, want.slug), true) : null;
    if (!n && html) n = (html.match(/class="[^"]*\bsec\b[^"]*"/g) || []).length;
    return { title: headingOfHtml(html) || "", n };
  }
  if (want.type === "board") {
    const body = await bodyOf(env, `${keys.pages(project).replace(/pages\/$/, "boards/")}${want.board || want.slug}.json`);
    let n = 0;
    if (body) { try { n = (JSON.parse(body).added || []).length; } catch { /* none */ } }
    return { n };
  }
  // A written page: its tree, or its finished document.
  let title = "";
  const tree = await bodyOf(env, keys.page(project, want.slug));
  if (tree) { try { title = headingOf(JSON.parse(tree)); } catch { /* none */ } }
  if (!title && stamps.html) title = headingOfHtml(await bodyOf(env, keys.pageHtml(project, want.slug), true));
  return { title };
}

/**
 * The covers for these pages: `wanted` is `[{ slug, type, board? }]` for the
 * decks, written pages and boards the Library will draw. Returns
 * `{ [slug]: { title?, n? } }`. `listing` is the film's `changeListing`, passed
 * in when the caller already has one.
 */
export async function coversOf(env, project, wanted, listing = null) {
  if (!wanted.length) return {};
  let held = { v: 1, items: {} };
  try {
    const got = await env.BUCKET.get(key(project));
    if (got) {
      const parsed = await got.json();
      if (parsed && typeof parsed.items === "object" && parsed.items) held = { v: 1, items: parsed.items };
    }
  } catch { /* start again */ }

  // Write times by object name, from the listing.
  const times = new Map();
  const mark = (list) => { for (const o of list || []) times.set(o.key, new Date(o.uploaded).getTime()); };
  if (listing) { mark(listing.pages); mark(listing.boards); mark(listing.decks); }
  else {
    const top = async (prefix) => {
      try { return (await env.BUCKET.list({ prefix, delimiter: "/", limit: 500 })).objects || []; } catch { return []; }
    };
    const base = keys.pages(project).replace(/pages\/$/, "");
    const [pages, boards, decks] = await Promise.all([top(keys.pages(project)), top(`${base}boards/`), top(keys.decks(project))]);
    mark(pages); mark(boards); mark(decks);
  }

  const out = {};
  const next = { ...held.items };
  let reads = 0;
  let moved = false;
  for (const want of wanted) {
    const stamps = { html: times.has(keys.pageHtml(project, want.slug)) };
    const at = want.type === "deck" ? Math.max(times.get(keys.deck(project, want.slug)) || 0, times.get(keys.pageHtml(project, want.slug)) || 0)
      : want.type === "board" ? times.get(`${keys.pages(project).replace(/pages\/$/, "boards/")}${want.board || want.slug}.json`) || 0
      : Math.max(times.get(keys.page(project, want.slug)) || 0, times.get(keys.pageHtml(project, want.slug)) || 0);
    const have = held.items[want.slug];
    if (have && have.at === at) { out[want.slug] = have; continue; }
    if (!at) { out[want.slug] = {}; continue; }      // nothing written yet: nothing to say
    if (reads >= READS) { out[want.slug] = have || {}; continue; }
    reads += 1;
    const got = await readOne(env, project, want, stamps);
    const item = { at, ...got };
    next[want.slug] = item;
    out[want.slug] = item;
    moved = true;
  }
  if (moved) {
    try {
      await env.BUCKET.put(key(project), JSON.stringify({ v: 1, items: next }), { httpMetadata: { contentType: "application/json" } });
    } catch { /* a cache; the next look reads again */ }
  }
  return out;
}
