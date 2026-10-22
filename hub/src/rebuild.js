/**
 * **A hand-made page, rebuilt as a normal one** — his decision of 2026-10-06
 * (Ref 1543): the pages an agent once wrote by hand as finished HTML (Camera
 * Tests, References) become ordinary block pages, with Video as a building
 * block, so the phone draws them natively and they can be written like any
 * other page.
 *
 *   POST /console/rebuild/<film>/<slug>   { markdown, from }   with the console's token
 *
 * The Markdown is read by `pageFrom`, the same reader the connector's
 * `set_page` uses. Then, in this order, and only if every step before it held:
 *
 * 1. **The old page is kept.** `pages/<slug>.html` is copied to
 *    `pages/<slug>.handmade.html` (a second copy gets a time in its name
 *    rather than replacing the first), and the copy is read back and its size
 *    compared before anything else happens. Nothing is ever deleted that has
 *    not been kept.
 * 2. **The new page is written** as `pages/<slug>.json`. A tree already there
 *    is kept beside it first, the same way.
 * 3. **The published document is taken off its address**, so the new page is
 *    the one drawn (`pageHtmlOf` would otherwise still win).
 * 4. **The row says what is true now**: a page written here, not a deck. Its
 *    shelf and icon are pinned to what they were, so nothing moves in the
 *    Library.
 *
 * **Once only.** A page already rebuilt (no published document left, its row
 * written here) answers `already` and is not touched again — so a deploy that
 * runs this every time can never write over a change he made since.
 *
 * **Only the page it was written from.** `from` is the SHA-256 of the
 * hand-made page the Markdown was read off; if the page on the portal is not
 * that one any more (somebody published it again since), nothing is written
 * and the answer says so, so the new page never stands in for words it has
 * not seen.
 *
 * **Nothing dropped quietly.** If the reader would leave anything out (a
 * picture that is not a stored file, a refused address), nothing is written
 * and the answer says what.
 */

import { keys } from "../../relay/layout.js";
import { pageFrom, MAX_PAGE } from "./paper.js";
import { storedFront, saveFront, shelfOf, setShelf, setIcon } from "./front.js";
import { defaultIcon } from "./icons.js";

const SLUG = /^[a-z0-9][a-z0-9-]{0,80}$/;

/** Keep `body` at `key`, or beside it with a time if something is already there. */
async function keepAside(env, base, ext, body, type) {
  let key = `${base}.handmade.${ext}`;
  const there = await env.BUCKET.head(key);
  if (there) {
    const held = await (await env.BUCKET.get(key)).text();
    if (held === body) return key;
    key = `${base}.handmade-${new Date().toISOString().replace(/[:.]/g, "-")}.${ext}`;
  }
  await env.BUCKET.put(key, body, { httpMetadata: { contentType: type } });
  const back = await env.BUCKET.get(key);
  if (!back || (await back.text()) !== body) throw new Error(`the copy at ${key} did not read back the same`);
  return key;
}

/**
 * Rebuild one page. Returns `{ done | already | refused, … }`; throws only
 * when the bucket itself fails, and then nothing past the failing step ran.
 */
async function sha256Of(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function rebuildPage(env, project, slug, markdown, from) {
  if (!SLUG.test(slug || "")) return { refused: "That is not a page's address." };
  const front = await storedFront(env, project);
  const row = (front.sections || []).find((one) => one.slug === slug);
  if (!row) return { refused: `No page at ${slug} on this film.` };

  const htmlKey = keys.pageHtml(project, slug);
  const treeKey = keys.page(project, slug);
  const held = await env.BUCKET.get(htmlKey);
  if (!held) {
    if (row.source === "here" && row.by !== "deck") return { already: true, slug };
    return { refused: `${row.name || slug} has no hand-made page to rebuild.` };
  }

  const page = await held.text();
  if (!/^[0-9a-f]{64}$/.test(String(from || ""))) return { refused: "Say which page this was written from (`from`)." };
  if ((await sha256Of(page)) !== from) {
    return { refused: `${row.name || slug} has changed since this was written from it. Nothing was touched.`, changed: true };
  }

  const { tree, dropped } = pageFrom(markdown);
  if (!tree.length) return { refused: "There is nothing on that page." };
  if (dropped.length) return { refused: "Something on the page would be left out.", dropped };
  // A file card says its size, as a pinned document's does.
  for (const node of tree) {
    if (node.t !== "file" || !node.src || node.bytes) continue;
    for (const folder of ["docs", "media"]) {
      const there = await env.BUCKET.head(keys.inFolder(project, folder, node.src));
      if (there) { node.bytes = there.size; break; }
    }
  }
  const body = JSON.stringify(tree);
  if (body.length > MAX_PAGE) return { refused: "That page is too long." };

  const base = htmlKey.replace(/\.html$/, "");
  const kept = await keepAside(env, base, "html", page, "text/html; charset=utf-8");
  const before = await env.BUCKET.get(treeKey);
  const keptTree = before ? await keepAside(env, base, "json", await before.text(), "application/json; charset=utf-8") : "";

  await env.BUCKET.put(treeKey, body, { httpMetadata: { contentType: "application/json; charset=utf-8" } });
  await env.BUCKET.delete(htmlKey);

  // Where it sat in the Library and the icon it wore, kept as they were.
  const name = row.name || slug;
  const wasShelf = shelfOf(front, slug, name, "page", row.type || "");
  const wasIcon = (front.icons || {})[slug] || defaultIcon({ at: slug, type: row.type || "" });
  front.sections = front.sections.map((one) => (one.slug === slug
    ? { ...one, type: "page", source: "here", by: "mcp", handmade: kept.split("/").pop() }
    : one));
  setShelf(front, slug, wasShelf, name, "page", "page");
  if (wasIcon !== defaultIcon({ at: slug, type: "page" })) setIcon(front, slug, wasIcon);
  front.updated = new Date().toISOString();
  await saveFront(env, project, front);
  return { done: true, slug, blocks: tree.length, kept, ...(keptTree ? { keptTree } : {}) };
}
