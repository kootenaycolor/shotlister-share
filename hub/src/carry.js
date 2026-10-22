/**
 * A portal with no film behind it, carried into the film that arrives later.
 *
 * His ruling, 2026-09-16: *"the pages should move across and merge in."*
 *
 * A portal on its own lives under the project's Notion page id; a film's page
 * lives under the film's relay id. The moment the console's record names a
 * film for a project that still carries a portal mark, `/f/<page id>` starts
 * going to the film — and everything made on the filmless portal (his pages,
 * the documents he pinned, the people and the links he sent, what he hid,
 * the pictures the refresh copied in) would still be in the bucket and
 * nowhere on screen. This moves it across, once, and takes the portal down.
 *
 * **Merge, never overwrite.** The film may already have a card, people, a
 * page under the same slug. Where the film has something, the film's stands
 * and the portal's is left behind with the portal; where the film has
 * nothing, the portal's fills it. Lists are joined by their key — a person by
 * email, a link by its hash, a page by its slug, a document by its file or
 * address — so nothing is doubled and nothing he sent out stops working.
 *
 * **One object at a time.** An R2 body is an open response until it has been
 * read, and about six may be open at once; a bible is forty pictures.
 */
import { LAYOUT, keys } from "../../relay/layout.js";
import { PROJECT, listAll, peopleOf, portalOf, visibleOf, saveVisible, downOf, saveDown, moveShorts } from "./films.js";
import { storedFront, saveFront, emptyFront } from "./front.js";
import { APP_ROWS } from "./pages.js";
import { moveFollows } from "./docfollow.js";

/** The hub's own records at the top of a prefix; everything else is copied by name. */
const OWN = new Set([
  LAYOUT.hub.portal, LAYOUT.hub.front, LAYOUT.hub.people, LAYOUT.hub.visible, LAYOUT.hub.down,
]);

/**
 * Carry the portal under `page` into the film under `relay`. Answers what
 * moved, or `null` when there was no portal to carry. Never throws: a copy
 * that fails leaves the portal standing, to be tried again on the next look.
 */
export async function carryPortal(env, page, relay) {
  if (!page || !relay || page === relay) return null;
  const portal = await portalOf(env, page);
  if (!portal) return null;

  const moved = { people: 0, links: 0, invites: 0, sections: 0, documents: 0, hidden: 0, objects: 0, down: false, shorts: 0, follows: 0 };

  // ---- people: added by email, links and invites by hash
  const from = await peopleOf(env, page);
  const to = await peopleOf(env, relay);
  const emails = new Set(to.people.map((p) => String(p.email || "").toLowerCase()));
  for (const one of from.people) {
    const email = String(one.email || "").toLowerCase();
    if (!email || emails.has(email)) continue;
    to.people.push(one); emails.add(email); moved.people += 1;
  }
  for (const [list, count] of [["links", "links"], ["invites", "invites"]]) {
    const hashes = new Set(to[list].map((l) => l && l.hash));
    for (const one of from[list]) {
      if (!one || !one.hash || hashes.has(one.hash)) continue;
      to[list].push(one); hashes.add(one.hash); moved[count] += 1;
    }
  }
  if (moved.people || moved.links || moved.invites) {
    await env.BUCKET.put(keys.people(relay), JSON.stringify(to, null, 2), {
      httpMetadata: { contentType: "application/json" },
    });
  }

  // ---- the card: the film's stands, the portal's fills the blanks
  const card = mergeFront(await storedFront(env, relay), await storedFront(env, page), moved);
  await saveFront(env, relay, card);

  // ---- what is hidden: the union — bar the program's own screens. A
  // portal with no film never offered the shot list, the locations, the
  // schedule or the reference images, so a hide written against them there
  // said nothing; carried across, it would hide the film's real screens
  // (Harbour Light Affair, 2026-09-18, arrived with all four hidden).
  const hid = await visibleOf(env, page);
  const hides = await visibleOf(env, relay);
  for (const kind of ["sections", "crew", "documents", "contact"]) {
    for (const key of hid[kind]) {
      if (kind === "sections" && APP_ROWS.includes(key)) continue;
      if (hides[kind].includes(key)) continue;
      hides[kind].push(key); moved.hidden += 1;
    }
  }
  // His For Me lists come across the same way.
  for (const kind of ["sections", "crew", "documents"]) {
    for (const key of hid.me[kind]) {
      if (kind === "sections" && APP_ROWS.includes(key)) continue;
      if (hides.me[kind].includes(key)) continue;
      hides.me[kind].push(key); moved.hidden += 1;
    }
  }
  if (moved.hidden) await saveVisible(env, relay, hides);

  // ---- the short name: `/hla` went to the portal, so now it goes to the film
  moved.shorts = await moveShorts(env, page, relay);

  // ---- down: a page he took down stays down
  const wasDown = await downOf(env, page);
  if (wasDown.down && !(await downOf(env, relay)).down) {
    await saveDown(env, relay, true, wasDown.by || "carried");
    moved.down = true;
  }

  // ---- every file: pages, documents, decks, the press, pictures — where the film has none
  const prefix = keys.film(page);
  const objects = await listAll(env, prefix);
  for (const object of objects) {
    const rest = object.key.slice(prefix.length);
    if (!rest || OWN.has(rest)) continue;
    // A film's own things never come from a portal: it had no manifest and no
    // logs, and if somehow it did they are the relay's, not ours to move.
    if (rest === LAYOUT.manifest || rest.startsWith(LAYOUT.logs)) continue;
    const dest = `${keys.film(relay)}${rest}`;
    if (await env.BUCKET.head(dest)) continue;
    const got = await env.BUCKET.get(object.key);
    if (!got) continue;
    await env.BUCKET.put(dest, got.body, {
      httpMetadata: got.httpMetadata,
      customMetadata: got.customMetadata,
    });
    moved.objects += 1;
  }

  // ---- pages that follow a Google Doc: the clock's list is keyed by this id
  moved.follows = await moveFollows(env, page, relay);

  // ---- and the portal goes, mark last, so a failure above leaves it to try again
  for (const object of objects) {
    if (object.key === keys.portal(page)) continue;
    await env.BUCKET.delete(object.key);
  }
  await env.BUCKET.delete(keys.portal(page));
  return moved;
}

/** Empty as a card field is empty: nothing, zero, an empty list, or an object of empties. */
function blank(value) {
  if (value === "" || value === 0 || value === null || value === undefined) return true;
  if (Array.isArray(value)) return value.length === 0;
  if (typeof value === "object") return Object.values(value).every(blank);
  return false;
}

/**
 * The film's card with the portal's laid under it.
 *
 * Words, the mark, the key image, the spec sheet: the film's where it has
 * one, the portal's otherwise — and the next refresh from Notion rewrites the
 * words either way. Pages and documents join by their key; the portal's own
 * categories (the sidebar's headings) join the film's, and what he had filed
 * in them stays filed there unless the film already filed it. The order comes
 * across only if the film has arranged nothing yet, because two orders over
 * one rail is not a thing that merges.
 */
export function mergeFront(film, portal, moved = {}) {
  const out = { ...emptyFront(), ...film };
  for (const key of Object.keys(emptyFront())) {
    if (key === "sections" || key === "documents" || key === "camera_files") continue;
    if (key === "camera") {
      for (const field of Object.keys(out.camera)) {
        if (blank(out.camera[field]) && !blank(portal.camera[field])) out.camera[field] = portal.camera[field];
      }
      continue;
    }
    if (blank(out[key]) && !blank(portal[key])) out[key] = portal[key];
  }
  // **Categories join; moves fill the blanks.**
  const ids = new Set(out.shelves.map((one) => one.id));
  const names = new Set(out.shelves.map((one) => one.name.toLowerCase()));
  for (const one of portal.shelves || []) {
    if (ids.has(one.id) || names.has(one.name.toLowerCase())) continue;
    out.shelves = [...out.shelves, one]; ids.add(one.id); names.add(one.name.toLowerCase());
  }
  out.shelf = { ...(portal.shelf || {}), ...(out.shelf || {}) };
  const slugs = new Set(out.sections.map((s) => s.slug));
  for (const one of portal.sections) {
    if (slugs.has(one.slug)) continue;
    out.sections.push(one); slugs.add(one.slug);
    if (moved.sections !== undefined) moved.sections += 1;
  }
  for (const list of ["documents", "camera_files"]) {
    const had = new Set(out[list].map((d) => d.file || d.url));
    for (const one of portal[list]) {
      const id = one.file || one.url;
      if (!id || had.has(id)) continue;
      out[list].push(one); had.add(id);
      if (list === "documents" && moved.documents !== undefined) moved.documents += 1;
    }
  }
  return out;
}

/**
 * **Where an id someone remembered leads now.** A client that had a portal
 * open (the connector's open film, a bookmark held by a script) keeps the
 * portal's id after the portal is carried into its film: the id then holds
 * nothing, and everything asked of it comes back empty (Halcyon, 2026-10-13).
 * A film, or a portal still standing, answers for itself; an id that holds
 * neither is looked up in the project's record, and sent to the film it names.
 */
export async function carriedTo(env, project) {
  if (await env.BUCKET.head(keys.manifest(project))) return project;
  if (await env.BUCKET.head(keys.portal(project))) return project;
  const got = await env.BUCKET.get(`r/${project}/record.json`);
  if (!got) return project;
  let relay = "";
  try { relay = String(((await got.json()).film || {}).relay || ""); } catch { return project; }
  if (!PROJECT.test(relay) || relay === project) return project;
  return (await env.BUCKET.head(keys.manifest(relay))) ? relay : project;
}
