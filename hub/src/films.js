/**
 * Who anybody is, and what they may do with a film.
 *
 * **Moved out of `worker.js` on 2026-09-01**, when the MCP arrived. Two doors
 * now ask the same question — a person on the web page, and an AI on
 * `mcp.your-domain.example` — and there must be exactly one answer to it.
 * Two copies of `roleFor` would drift, and the day they drifted would be the
 * day somebody saw a film they had been taken off.
 *
 * Nothing here is new. It is the same code, in a file both halves import.
 */

import { closedMark } from "./step6shelf.js";
import { viewByKey } from "./views.js";
import { LAYOUT, keys } from "../../relay/layout.js";
import { filmless } from "../../relay/portal.js";

export const PROJECT = /^[0-9a-f]{8,64}$/;
export const EMAIL = /^[^\s@]{1,190}@[^\s@]{1,60}$/;

/** The shape of a film's list of people when it has none yet. */
export function emptyPeople() {
  return { version: 1, people: [], links: [], invites: [] };
}

export async function listAll(env, prefix) {
  const out = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000 });
    out.push(...page.objects);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out;
}

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function peopleOf(env, project) {
  return (await peopleWithTag(env, project)).list;
}

/**
 * The list of people **and the tag the bucket gave that copy of it** — what a
 * change made for the Projects Console compares against when it writes back
 * (`savePeople` with `from`). `etag` is null when the film has no list yet.
 */
export async function peopleWithTag(env, project) {
  const got = await env.BUCKET.get(keys.people(project));
  if (!got) return { list: emptyPeople(), etag: null };
  try {
    const parsed = await got.json();
    return {
      list: {
        version: 1,
        people: Array.isArray(parsed.people) ? parsed.people : [],
        links: Array.isArray(parsed.links) ? parsed.links : [],
        invites: Array.isArray(parsed.invites) ? parsed.invites : [],
      },
      etag: got.etag,
    };
  } catch {
    return { list: emptyPeople(), etag: got.etag };
  }
}

/**
 * Write the list back, refusing to clobber somebody else's write.
 *
 * Two people opening the same invite in the same second would otherwise each
 * read the list, add themselves, and write — and the second would erase the
 * first. R2 will compare the tag it gave us; one retry is plenty for a race
 * this narrow, and the caller says "try again" rather than pretending.
 *
 * **`from`, a true compare-and-set** (the Projects Console's door,
 * 2026-10-05): `{ etag }` as `peopleWithTag` read it, null for "there was no
 * list". Then the write lands only over exactly the copy the change was made
 * to — no second look — so a change made from a stale read is refused rather
 * than written over whatever arrived in between. Without it, as ever.
 *
 * Answers the stored object (truthy) or false.
 */
export async function savePeople(env, project, list, from = undefined) {
  const key = keys.people(project);
  const body = JSON.stringify(list, null, 2);
  const httpMetadata = { contentType: "application/json" };
  if (from) {
    const put = await env.BUCKET.put(key, body, {
      httpMetadata,
      onlyIf: from.etag ? { etagMatches: from.etag } : { etagDoesNotMatch: "*" },
    });
    return put || false;
  }
  for (let attempt = 0; attempt < 2; attempt++) {
    const current = await env.BUCKET.get(key);
    const put = await env.BUCKET.put(key, body, {
      httpMetadata,
      onlyIf: current ? { etagMatches: current.etag } : { etagDoesNotMatch: "*" },
    });
    if (put) return put;
  }
  return false;
}

/** The addresses that are him. One line in `wrangler.toml`, comma-separated. */
export function owners(env) {
  return String(env.OWNER || "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter((e) => EMAIL.test(e));
}

/**
 * What this person may do with this film: `editor`, `viewer`, or nothing.
 *
 * **He is an editor on everything, always.** Not a convenience — without it the
 * hub cannot be started: only an editor may write the list of people, so an
 * empty film would have nobody able to add the first one.
 */
export async function roleFor(env, project, who) {
  if (who.email && owners(env).includes(who.email.toLowerCase())) return "editor";
  const list = await peopleOf(env, project);

  if (who.via === "link") {
    const hash = await sha256Hex(who.key);
    const found = list.links.find((l) => l && l.hash === hash);
    // **A view link is a viewer of one filtered shot list** (`views.js`), and
    // nothing else of the film — the worker narrows it to that at the door.
    if (!found) return (await viewByKey(env, project, who.key)) ? "viewer" : null;
    // **Switched off, not thrown away.** Turning general access off used to
    // delete the link, so turning it back on minted a new address and every
    // link he had already sent stopped working. His instruction, 2026-09-02:
    // *"that ruins links ive sent out before."* The address is kept and simply
    // stops answering, exactly as a document does.
    if (found.off) return null;
    // An expiry is a date, so it runs to the end of that day rather than to
    // midnight at its start — a link that dies at breakfast on the day he said
    // is a link that died a day early as far as anybody using it is concerned.
    if (found.expires && Date.now() > Date.parse(`${found.expires}T23:59:59Z`)) return null;
    return found.role === "editor" ? "editor" : "viewer";
  }

  if (!who.email) return null;
  const found = list.people.find(
    (p) => p && String(p.email || "").toLowerCase() === who.email.toLowerCase()
  );
  if (!found) return null;
  return found.role === "editor" ? "editor" : "viewer";
}

/** What a film is called, or its id if nothing in the bucket says. */
export async function titleOf(env, project) {
  return (await namedOf(env, project)).title;
}

/**
 * What a project is called, and whether it is a portal with no film — in the
 * reads `titleOf` was making anyway, so the shelf learns both for nothing.
 *
 * **The manifest first.** A film has one, and with a manifest the answer is
 * *film* whatever else is there (`filmless`), so the mark is never read for
 * one. Without a manifest the mark names it, and says it is a portal.
 */
async function namedOf(env, project) {
  const manifest = await env.BUCKET.get(keys.manifest(project));
  if (!manifest) {
    // **A portal with no film is named by its mark.** Nothing else under the
    // prefix carries a title: the manifest is the film's, and there is none.
    const portal = await portalOf(env, project);
    return {
      title: (portal && portal.title) || project,
      portal: filmless({ mark: Boolean(portal), manifest: false }),
      film: false,
    };
  }
  try {
    return { title: (await manifest.json()).title || project, portal: false, film: true };
  } catch {
    // A film whose manifest we cannot read is still a film. Its id is a poor
    // name and a better one than refusing to name it at all.
    return { title: project, portal: false, film: true };
  }
}

// ------------------------------------------------------ a portal, no film

/**
 * The mark that says this project is a portal with no film behind it.
 *
 * His ask, 2026-09-16: *"a web portal for a film that doesn't have a
 * shotlister project ... created by the project console."* The address is the
 * project's own — `/f/<its Notion page id>`, which has stood for a project
 * from birth since the record arrived — and this small object under that
 * prefix is what turns the record's bare page into the front of house: the
 * words from Notion, the documents, the people, the spec sheet, his own
 * pages. The film's four screens stay off the rail, because there is no film.
 *
 * **A mark, not a manifest.** Writing `manifest.json` here would make the
 * relay list it as a film, and every Mac and iPhone would offer to fetch a
 * film with nothing in it. The relay leaves a prefix carrying this mark out
 * of its listing instead (`listProjects` in `relay/src/worker.js`).
 *
 * Absent is simply "not a portal-only project", which is what every film is.
 * **Unreadable is still a mark, with no name** (SL-1376): the relay sees the
 * key go past in its listing and cannot read it, so if the hub took an
 * unreadable mark for no mark the two would disagree about what it is.
 */
export async function portalOf(env, project) {
  const got = await env.BUCKET.get(keys.portal(project));
  if (!got) return null;
  let parsed = null;
  try {
    parsed = await got.json();
  } catch {
    parsed = null;
  }
  if (!parsed || typeof parsed !== "object") parsed = {};
  return {
    version: 1,
    title: String(parsed.title || "").slice(0, 200),
    page: /^[0-9a-f]{32}$/.test(String(parsed.page || "")) ? String(parsed.page) : "",
    made: typeof parsed.made === "string" ? parsed.made.slice(0, 40) : "",
    by: typeof parsed.by === "string" ? parsed.by.slice(0, 80) : "",
  };
}

/**
 * **The portal's mark, when this project is a portal with no film — or
 * `null` when it is a film.** The question every door asks before it treats
 * a project as one or the other: the rail and its four screens, the shelf,
 * the connector, the console's readout. The rule itself is `filmless`, in
 * `relay/portal.js`, which the relay's listing asks too.
 *
 * Change logs under a mark with no manifest do not make it a film. They are
 * strays — SL-1376, the two a chat wrote into Halcyon — and everything that
 * asks here ignores them; `strayLogs` counts them for the console.
 *
 * **The mark first**, so a film costs one small read: it has no mark, and
 * the manifest is never asked about.
 */
export async function filmlessPortal(env, project) {
  const portal = await portalOf(env, project);
  if (!portal) return null;
  const manifest = await env.BUCKET.head(keys.manifest(project));
  return filmless({ mark: true, manifest: Boolean(manifest) }) ? portal : null;
}

/** How many change logs sit under a project — under a filmless portal, the strays. */
export async function strayLogs(env, project) {
  return (await listAll(env, keys.logs(project))).filter((o) => o.key.endsWith(".log")).length;
}

/**
 * Whether a film lives under this prefix: its manifest, or any change log.
 * The door asks before it marks a project as a portal, so a mark can never
 * be written over a film that has synced.
 */
export async function hasFilm(env, project) {
  if (await env.BUCKET.head(keys.manifest(project))) return true;
  const logs = await env.BUCKET.list({ prefix: keys.logs(project), limit: 1 });
  return logs.objects.length > 0;
}

export async function savePortal(env, project, asked) {
  const was = await portalOf(env, project);
  const record = {
    version: 1,
    title: String(asked.title || (was && was.title) || "").slice(0, 200),
    // The Notion page its words come from: the project's own address for a
    // portal keyed on its page, the page named for one keyed on a minted ID.
    page: /^[0-9a-f]{32}$/.test(String(asked.page || "")) ? String(asked.page) : ((was && was.page) || project),
    made: (was && was.made) || new Date().toISOString(),
    by: String(asked.by || (was && was.by) || "").slice(0, 80),
  };
  await env.BUCKET.put(keys.portal(project), JSON.stringify(record), {
    httpMetadata: { contentType: "application/json" },
  });
  return record;
}

/** Every portal-only project in the bucket, for the refresh to walk. */
export async function everyPortal(env) {
  const found = [];
  for (const object of await listAll(env, LAYOUT.prefix)) {
    if (!object.key.endsWith(`/${LAYOUT.hub.portal}`)) continue;
    const id = object.key.split("/")[1];
    if (!id || !PROJECT.test(id)) continue;
    const portal = await filmlessPortal(env, id);
    if (portal) found.push({ project: id, ...portal });
  }
  found.sort((a, b) => a.title.localeCompare(b.title));
  return found;
}

/**
 * A film's name as it appears in an address: `Call Her Back` → `callherback`.
 *
 * **Letters and digits only.** A slug that can contain a hyphen or a dot has to
 * be told apart from every other path segment the hub serves, and the films are
 * few enough that squeezing the name is unambiguous in practice. Anything that
 * squeezes to nothing keeps its id, which is what an untitled film gets.
 */
export function slugOf(title) {
  return String(title || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
}

/** Never a slug: these are the hub's own addresses. */
export const RESERVED = new Set(["f", "health", "whoami", "robots.txt", "mcp-signin", "favicon.ico", "decks", "manifest.webmanifest", "app-icon.png", "hub-icon.png"]);

/**
 * The film somebody meant by name, among the ones they may open.
 *
 * **Resolved against what this person may see**, which is not only tidy: a
 * stranger guessing names learns nothing, because a slug they may not open does
 * not resolve for them at all. Three films means three small reads; if that ever
 * becomes three hundred this wants an index, and the place to put one is here.
 */
export async function filmBySlug(env, who, slug) {
  const wanted = slugOf(slug);
  if (!wanted || RESERVED.has(slug)) return null;
  for (const film of await filmsFor(env, who)) {
    if (slugOf(film.title) === wanted) return film;
  }
  return null;
}

/**
 * Every film id in the bucket.
 *
 * **The folders, not their contents.** This used to list every object under
 * `p/` — every picture, every log, every held file of every film, a thousand
 * a call — and then keep only the second path segment. `filmsFor` runs it on
 * every request that names a film by its slug, which on a share link is every
 * page and every picture on it; that was the three to four seconds each load
 * took, and on 2026-09-18 it tipped a request over Cloudflare's resource
 * limit (error 1102, seen several times in a row on the LUT off Harbour Light
 * Affair's spec sheet). A delimited list answers with the folder names alone,
 * in one call, however many pictures the films hold.
 */
export async function everyFilm(env) {
  const seen = new Set();
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: LAYOUT.prefix, delimiter: "/", cursor, limit: 1000 });
    for (const folder of page.delimitedPrefixes || []) {
      const id = folder.slice(LAYOUT.prefix.length).replace(/\/$/, "");
      if (id && PROJECT.test(id)) seen.add(id);
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return [...seen];
}

/**
 * Which films this person has a part in, with what they may do and what each is
 * called.
 *
 * Reads every film's list of people, which is one small object each. Three
 * films today; if that ever becomes three hundred this wants an index, and the
 * place to put one is here rather than in the film.
 */
export async function filmsFor(env, who) {
  // **Every film at once, not one after another** (2026-10-02): eight films
  // read in turn was most of a second on every page that drew the shelf.
  const found = await Promise.all((await everyFilm(env)).map(async (project) => {
    const role = await roleFor(env, project, who);
    if (!role) return null;
    // Closed (step6shelf.js): off the shelf until reopened.
    if (await closedMark(env, project)) return null;
    // **A portal with no film says so**, so the shelf does not call it "0
    // changes" — and says so even with logs under it (SL-1376): those are
    // strays, not a film, by the one rule (`filmless`). Learned in the reads
    // the title takes anyway, so a film costs nothing.
    const { title, portal, film } = await namedOf(env, project);
    const logs = portal ? 0 : (await listAll(env, keys.logs(project))).filter((o) => o.key.endsWith(".log")).length;
    // **Leftovers are not a project** (2026-10-17, the relay's rule too): no
    // manifest, no portal mark and no change logs is what a deleted project
    // left behind (a front page, some covers) — never a film or a portal.
    if (!portal && !film && logs === 0) return null;
    return { project, title, role, logs, portal };
  }));
  const films = found.filter(Boolean);
  films.sort((a, b) => a.title.localeCompare(b.title));
  return films;
}

/**
 * **Whether this person has more than one film** — all a page needs to know
 * to draw the Projects arrow. `filmsFor` answers it by reading every film's
 * title and logs; this asks only who may open what, all at once, and for him
 * not even that: he may open every film there is.
 */
export async function manyFilms(env, who) {
  // **A link opens one film.** Its key is made for that film's list and no
  // other, so asking every film whether it knows the key is a second of
  // reads for an answer that is always no.
  if (!who || who.via === "link") return false;
  const all = await everyFilm(env);
  if (all.length < 2) return false;
  if (who && who.email && owners(env).includes(who.email.toLowerCase())) return true;
  const roles = await Promise.all(all.map((project) => roleFor(env, project, who).catch(() => null)));
  return roles.filter(Boolean).length > 1;
}

// ------------------------------------------------------------- what is seen

/**
 * **Administrator.** His instruction, 2026-09-04: his own addresses get a rank
 * above editor, and only that rank decides what everybody else may see.
 *
 * **Deliberately a separate question from `roleFor`, not a third value it
 * returns.** Every gate in the hub asks `role === "editor"`, and quietly
 * changing what he is would have had to be right in a dozen places at once to
 * avoid taking a permission away from him by accident. This only ever *adds*
 * a power, so nothing that works today can stop working.
 */
export function isAdmin(env, who) {
  return Boolean(who && who.email && owners(env).includes(who.email.toLowerCase()));
}

/** Nothing hidden — what a film that has never been told otherwise looks like. */
export function emptyVisible() {
  return { version: 1, sections: [], crew: [], documents: [], contact: [], me: emptyMine() };
}

/** Nothing hidden from him. */
export function emptyMine() {
  return { sections: [], crew: [], documents: [] };
}

/**
 * What this film hides, as three lists of names — plus one list of names it
 * shows more of.
 *
 * **Hidden things are listed, rather than visible things ticked.** A film
 * nobody has set anything on shows everything, and a section he adds later —
 * or a crew member Notion gains overnight — is visible without him being asked
 * again. The other way round, every new thing would arrive invisible and the
 * failure would be silent.
 *
 * **`contact` runs the other way, on purpose.** A phone number is not a
 * section — the safe default is hidden, not shown, so this is the one list
 * that says who a link holder *may* reach rather than who they may not see.
 *
 * **`me` is the same three lists again, for his own view** — Visibility's For
 * Me tab (`meSees`). It hides nothing from anybody else, and a link holder's
 * lists say nothing about what he sees.
 */
export async function visibleOf(env, project) {
  const got = await env.BUCKET.get(keys.visible(project));
  if (!got) return emptyVisible();
  try {
    const parsed = await got.json();
    const list = (x) => (Array.isArray(x) ? x.filter((v) => typeof v === "string").slice(0, 500) : []);
    const out = {
      version: 1,
      sections: list(parsed.sections),
      crew: list(parsed.crew),
      documents: list(parsed.documents),
      contact: list(parsed.contact),
      me: mineOf(parsed.me, list),
    };
    // **"Me" is retired** (his ruling, 2026-10-03): a page hidden For Me is
    // now simply not Pinned. Done once, here, on the first read that finds
    // any, and idempotent: the list it empties is the list it reads.
    if (out.me.sections.length) await retireMe(env, project, out);
    return out;
  } catch {
    // **Unreadable means hide nothing, and that is the safe way round here.**
    // The alternative — hiding everything — locks a crew out of a film because
    // one object went bad, which is a worse failure than a spec sheet being
    // visible for an hour.
    return emptyVisible();
  }
}

/**
 * **Each page hidden For Me becomes unpinned** (a row in `front.library`, under
 * the heading it sat in), then leaves `visible.me.sections`. People and
 * documents hidden For Me are kept in the store and no longer applied
 * (`meSees`), since the control that set them is gone. The front card is
 * edited as plain JSON, so this file needs nothing from `front.js`.
 */
async function retireMe(env, project, visible) {
  const got = await env.BUCKET.get(keys.front(project));
  if (got) {
    try {
      const front = await got.json();
      const library = Array.isArray(front.library) ? front.library : [];
      const archive = Array.isArray(front.archive) ? front.archive : [];
      const off = new Set([...library, ...archive].map((one) => one && one.at));
      for (const at of visible.me.sections) {
        if (off.has(at)) continue;
        library.push({ at, head: "" });
      }
      front.library = library;
      await env.BUCKET.put(keys.front(project), JSON.stringify(front), {
        httpMetadata: { contentType: "application/json; charset=utf-8" },
      });
    } catch { return; }
  }
  visible.me.sections = [];
  await saveVisible(env, project, visible);
}

function mineOf(raw, list) {
  const me = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  return { sections: list(me.sections), crew: list(me.crew), documents: list(me.documents) };
}

/** Addresses no page may move to: the record's, the program's, the hub's own. */
const NOT_AN_ADDRESS = new Set([
  "script", "bible", "camera", "people", "documents", "crew", "api", "media", "fso", "pic", "share", "join",
  "visibility", "add", "order", "groups", "library", "archive", "refresh", "shoots", "shotlist", "shots",
  "locations", "boards", "schedule", "diagrams", "cover", "icon", "edit", "print", "file", "drive", "camera-sheet", "v",
]);

/**
 * **A renamed page takes the address its new name makes**, and answers it
 * whole: its words and finished document move with it, and everything that
 * remembers a page by its address — its group, icon, shelf, Library and
 * Archive rows, who may see it — is told the new one. A board's cards are
 * kept under their storage name (`board`), so a board that had none keeps
 * its old address as that name and its cards stay where they are.
 *
 * `front.moved` remembers where an address went, so a link sent before the
 * rename forwards (see the page route). An earlier address of the same page
 * is pointed at the newest, never at a page in between; an address taken
 * again by a page of its own is that page's and stops forwarding.
 *
 * Returns the address the page is at now: the old one when the new name's
 * is the hub's own or another page's. The caller saves `front`.
 */
export async function movePage(env, project, front, visible, from, to) {
  const his = (front.sections || []).find((one) => one.slug === from);
  if (!his || !to || to === from || NOT_AN_ADDRESS.has(to) || (front.sections || []).some((one) => one.slug === to)) return from;
  for (const k of [keys.page, keys.pageHtml]) {
    const got = await env.BUCKET.get(k(project, from));
    if (!got) continue;
    await env.BUCKET.put(k(project, to), await got.arrayBuffer(), { httpMetadata: got.httpMetadata });
    await env.BUCKET.delete(k(project, from));
  }
  if (his.type === "board" && !his.board) his.board = from;
  his.slug = to;
  const swap = (at) => (at === from ? to : at);
  front.rail = (front.rail || []).map(swap);
  for (const list of ["library", "archive"]) {
    if (Array.isArray(front[list])) front[list] = front[list].map((one) => (one && one.at === from ? { ...one, at: to } : one));
  }
  for (const map of ["icons", "shelf"]) {
    const m = front[map];
    if (m && Object.prototype.hasOwnProperty.call(m, from)) {
      front[map] = { ...m, [to]: m[from] };
      delete front[map][from];
    }
  }
  const moved = Object.fromEntries(Object.entries(front.moved || {}).map(([was, now]) => [was, now === from ? to : now]));
  moved[from] = to;
  delete moved[to];
  front.moved = moved;
  if (visible && (visible.sections.includes(from) || visible.me.sections.includes(from))) {
    visible.sections = visible.sections.map(swap);
    visible.me.sections = visible.me.sections.map(swap);
    await saveVisible(env, project, visible);
  }
  return to;
}

/**
 * **Renaming a pinned document** (a file or a link). A document is known by its
 * name everywhere (`doc:<name>` in the Library's category, icon, archive and
 * sidebar lists, and the private lists in Visibility), so a rename carries
 * each of those over. A Notion document keeps Notion's name in `was`, so the
 * next refresh finds it again and does not add a second card.
 *
 * Returns `{ ok: true, name }` or `{ why }`. The caller saves `front`, and
 * `visible` with `saveVisible` when `touched` says it changed.
 */
export function renameDocument(front, visible, from, to) {
  const called = String(to || "").replace(/\s+/g, " ").trim().slice(0, 140);
  if (!called) return { why: "Give it a name." };
  const docs = front.documents || [];
  const same = (a, b) => String(a || "").trim().toLowerCase() === String(b || "").trim().toLowerCase();
  const one = docs.find((d) => same(d.name, from));
  if (!one) return { why: `No document called ${from}.` };
  if (docs.some((d) => d !== one && same(d.name, called))) return { why: `${called} is already pinned to this film.` };
  const was = one.name;
  if (was === called) return { ok: true, name: called, touched: false };
  if (!one.file && (one.source || "notion") === "notion" && !one.was) one.was = was;
  one.name = called;
  const old = `doc:${was}`, now = `doc:${called}`;
  front.rail = (front.rail || []).map((at) => (at === old ? now : at));
  for (const list of ["library", "archive", "docPins"]) {
    if (Array.isArray(front[list])) front[list] = front[list].map((e) => (e && e.at === old ? { ...e, at: now } : e));
  }
  for (const map of ["icons", "shelf"]) {
    const m = front[map];
    if (m && Object.prototype.hasOwnProperty.call(m, old)) {
      front[map] = { ...m, [now]: m[old] };
      delete front[map][old];
    }
  }
  let touched = false;
  if (visible) {
    const swap = (list) => (list || []).map((n) => (n === was ? called : n));
    if ((visible.documents || []).includes(was)) { visible.documents = swap(visible.documents); touched = true; }
    if (visible.me && (visible.me.documents || []).includes(was)) { visible.me.documents = swap(visible.me.documents); touched = true; }
  }
  front.updated = new Date().toISOString();
  return { ok: true, name: called, touched };
}

/**
 * **A removed page takes its old addresses with it.** His rule, 2026-10-09:
 * every old link keeps working *unless the page is deleted or private*. Left
 * behind, an old address would forward to whatever page took the removed
 * one's address next, which is a different page wearing an old link.
 */
export function forgetMoves(front, slug) {
  front.moved = Object.fromEntries(Object.entries(front.moved || {}).filter(([was, now]) => now !== slug && was !== slug));
}

export async function saveVisible(env, project, visible) {
  await env.BUCKET.put(keys.visible(project), JSON.stringify(visible), {
    httpMetadata: { contentType: "application/json" },
  });
}

/**
 * Whether the film's page is down — taken off for everyone but an editor.
 *
 * **A switch, not a deletion.** The Projects Console's ask, 2026-09-15: take
 * a portal page down and put it back up *without* removing the synced film.
 * `p/<project>/down.json` is the switch; present and `down: true` means every
 * route a viewer or a link holder could reach answers "This page is down"
 * (see `route` in `worker.js`). An editor sees the film as ever, which is how
 * he checks it before putting it back. Absent, or unreadable, means up — one
 * object going bad must not take a page down.
 */
export function emptyDown() {
  return { version: 1, down: false, since: "", by: "" };
}

export async function downOf(env, project) {
  const got = await env.BUCKET.get(keys.down(project));
  if (!got) return emptyDown();
  try {
    const parsed = await got.json();
    return {
      version: 1,
      down: parsed.down === true,
      since: typeof parsed.since === "string" ? parsed.since.slice(0, 40) : "",
      by: typeof parsed.by === "string" ? parsed.by.slice(0, 80) : "",
    };
  } catch {
    return emptyDown();
  }
}

/** Down writes the switch; up takes it away, so a page put back leaves nothing behind. */
export async function saveDown(env, project, down, by = "") {
  const key = keys.down(project);
  if (!down) {
    await env.BUCKET.delete(key);
    return emptyDown();
  }
  const record = { version: 1, down: true, since: new Date().toISOString(), by: String(by || "").slice(0, 80) };
  await env.BUCKET.put(key, JSON.stringify(record), { httpMetadata: { contentType: "application/json" } });
  return record;
}

/**
 * May this person see this thing?
 *
 * **An editor and an administrator see everything.** Visibility is what a film
 * shows the people it is shared *with* — his ruling, 2026-09-04, that it
 * follows the link rather than the person, so there is one setting per film
 * rather than a matrix nobody would maintain.
 */
export function maySee(visible, kind, key, role) {
  if (role === "editor") return true;
  return !(visible[kind] || []).includes(String(key));
}

/**
 * **May this person open this board?** `share` on the section — see `SHARES`
 * in `front.js`. Anything that is not a board is not this function's business
 * and answers yes; `maySee` still rules it.
 *
 * `admin` is `isAdmin` for a person who is signed in, and false on the share
 * host whatever it says — a link holder is nobody in particular. `crew` means
 * signed in: somebody the film knows by an address, not a key.
 */
export function boardOpen(one, who, admin) {
  if (!one || one.type !== "board") return true;
  if (admin) return true;
  if (one.share === "link") return true;
  if (one.share === "crew") return Boolean(who && who.email && who.via !== "link");
  return false;
}

/**
 * The film's pages this person may know exist — its boards filtered by
 * `boardOpen`. For drawing and for reading out, **never for saving**: a card
 * written back after this has run would take his private boards off it.
 */
export function sectionsFor(front, who, admin) {
  return (front.sections || []).filter((one) => boardOpen(one, who, admin));
}

/**
 * May this person see this crew member's email and phone?
 *
 * **The opposite direction from `maySee`.** Contact details default hidden
 * from anyone who is not an editor; `visible.contact` is the list of names he
 * has chosen to hand out anyway, set per person in Visibility.
 */
export function mayContact(visible, key, role) {
  if (role === "editor") return true;
  return (visible.contact || []).includes(String(key));
}

/**
 * **Does he want to see this, signed in?** Visibility's For Me tab — his ask,
 * 2026-10-02: *"what do I do if I want to not see certain things on the
 * logged-in portal … and hide stuff like I do for the visible shared page?"*
 *
 * **Out of his way, never shut.** A section hidden for him leaves his rail and
 * his front page; its address still opens, the rail keeps the row while he is
 * standing on it, and Visibility and Add's Built In list still name it — the
 * way back. A person or a document leaves the People or Documents page.
 *
 * `admin` is `isAdmin` for a person who is signed in, as `boardOpen` takes it.
 * Anybody else is shown what `maySee` shows them, untouched by this.
 */
export function meSees() {
  // **Retired, 2026-10-03.** A page is Pinned or not; nothing is hidden For
  // Me any more. The lists stay in `visible.me` (people and documents he had
  // hidden are kept, not applied), and this stays so every caller still reads.
  return true;
}

/**
 * One section's page, as the tree in the bucket.
 *
 * **Here rather than in `worker.js`, where its twin still lives.** Both the
 * page router and the MCP need to read a page now — the MCP since 2026-09-04,
 * when the film's page became the source of truth for a bible's words and the
 * deck editor started rendering a PDF from it. `worker.js` imports `mcp.js`,
 * so the MCP cannot import back out of it without a cycle; this file is where
 * the other bucket helpers already live.
 *
 * Never throws and never refuses. An absent or unreadable page draws as empty
 * rather than as an error — the section is still listed, and "nothing on this
 * page yet" is the honest thing to say while the next refresh runs.
 */
export async function pageOf(env, project, slug) {
  if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug || "")) return null;
  const got = await env.BUCKET.get(keys.page(project, slug));
  if (!got) return null;
  try {
    const tree = await got.json();
    return Array.isArray(tree) ? tree : null;
  } catch {
    return null;
  }
}

/**
 * A section's page as a *finished document*, if one has been published.
 *
 * His decision, 2026-09-05: a deck's design makes two things — a PDF, and a web
 * page in the same world as it. `deck-builder/tools/publish.py` renders the
 * second and puts it here, beside the tree.
 *
 * **A page may therefore arrive in one of two forms**, and the drawn one wins:
 * a tree, which the portal styles itself, or a document, which brings its own.
 * Nothing has to be migrated — a film with no published page draws exactly as
 * it did.
 *
 * **Scripts are cut out.** This is his own file, put here with his own
 * credentials, so nothing hostile is expected — but it is markup written
 * elsewhere and injected into a signed-in page, and the cost of being wrong
 * about that is somebody else's session. A design needs style and markup; it
 * has never needed a script. What a design may need that a script would give
 * it — a comparison slider, a pin board — the portal supplies itself
 * (`public/compare.js`, `public/board.js`), the way `look.js` supplies the
 * lightbox.
 *
 * **A video player from a known host is the one frame allowed through.** His
 * ask, 2026-09-21: the camera tests page opens on the test reel, which is
 * hosted on livid. An `<iframe>` is still cut — except one whose `src` is a
 * player on the short list below, and that one is *re-issued* rather than
 * passed: only its address and title are kept, and the attributes a player
 * needs (`allow`, `allowfullscreen`) are written here. Nothing else typed into
 * the tag reaches the page.
 */
const PLAYERS = /^https:\/\/(?:livid\.com\/embed\/|player\.vimeo\.com\/video\/|www\.youtube(?:-nocookie)?\.com\/embed\/)[A-Za-z0-9_\-]+(?:[?#][^"'<>\s]*)?$/;

function playerFrame(tag) {
  const src = (tag.match(/\ssrc\s*=\s*"([^"]*)"/i) || tag.match(/\ssrc\s*=\s*'([^']*)'/i) || [])[1] || "";
  if (!PLAYERS.test(src)) return "";
  // The title arrives already escaped for an attribute; read it back to text
  // before it is escaped again, or an `&` becomes `&amp;amp;`.
  const title = ((tag.match(/\stitle\s*=\s*"([^"]*)"/i) || [])[1] || "Video")
    .replace(/&(amp|lt|gt|quot|#39);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" }[e]));
  const safe = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  return `<iframe src="${safe(src)}" title="${safe(title)}" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe>`;
}

export async function pageHtmlOf(env, project, slug) {
  if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug || "")) return "";
  const got = await env.BUCKET.get(keys.pageHtml(project, slug));
  if (!got) return "";
  const said = await got.text();
  if (said.length > 2 * 1024 * 1024) return "";
  // A player's frame is rewritten whole and held aside as a token, because
  // the general cut below would take the rewritten tag with the rest; every
  // other iframe still goes. The tokens are put back last, after the cut.
  const players = [];
  const stashed = said.replace(/<iframe\b[^>]*>\s*<\/iframe>/gi, (tag) => {
    const made = playerFrame(tag);
    if (!made) return "";
    players.push(made);
    return `\u0000player${players.length - 1}\u0000`;
  });
  return stashed
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<\/?(?:html|head|body|iframe|object|embed)\b[^>]*>/gi, "")
    .replace(/\son[a-z]+\s*=\s*"[^"]*"/gi, "")
    .replace(/\son[a-z]+\s*=\s*'[^']*'/gi, "")
    .replace(/\u0000player(\d+)\u0000/g, (_, i) => players[Number(i)] || "");
}

// ------------------------------------------------------------ short names
//
// **`share.your-domain.example/hla`.** His instruction, 2026-09-19: every
// link on the portal has to be friendly — a film's public link is its
// initials, not its title squeezed flat with a forty-character key on the end.
//
// A short name is a second address for a film, and on the share host it
// *stands for the film's general link*: opening `/hla` is the same as opening
// the film with that link's key, so everything the key decides — off, expired,
// a password — still decides. Nothing is granted that the general link does
// not grant, and switching the link off closes the short name with it.
//
// **Every address that came before still works.** The film's title
// (`/harbourlightaffair?k=…`), its id (`/f/<id>?k=…`) and any name a film has
// ever had here go on answering — a short name is added to the film, never
// swapped in for something crew already hold. Renaming keeps the old name as
// an alias for the same reason.
//
// One small file at the root of the bucket, `shorts.json`, maps every name to
// its film: one read a request, however many films there are.

const SHORTS_KEY = "shorts.json";
export const SHORT = /^[a-z0-9]{2,24}$/;

export async function shortsOf(env) {
  const got = await env.BUCKET.get(SHORTS_KEY);
  if (!got) return {};
  try {
    const parsed = await got.json();
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

async function saveShorts(env, shorts) {
  await env.BUCKET.put(SHORTS_KEY, JSON.stringify(shorts, null, 2), {
    httpMetadata: { contentType: "application/json" },
  });
}

/** The film a short name stands for, or null. */
export async function filmOfShort(env, name) {
  const shorts = await shortsOf(env);
  const hit = shorts[String(name || "").toLowerCase()];
  return hit && PROJECT.test(hit.project) ? hit.project : null;
}

/** A film's current short name — the newest one it holds — or "". */
export async function shortOf(env, project) {
  const shorts = await shortsOf(env);
  let best = "";
  let when = "";
  for (const [name, hit] of Object.entries(shorts)) {
    if (!hit || hit.project !== project) continue;
    if (!best || String(hit.since || "") > when) { best = name; when = String(hit.since || ""); }
  }
  return best;
}

/**
 * The short name a title suggests: its initials, or the one word it is.
 *
 * `Harbour Light Affair` → `hla`; `Call Her Back` → `chb`; `ZED` → `zed`;
 * `Mirrorland` → `mirrorland`. A title of one word has no initials worth
 * having, so it keeps the word. A leading article goes — `The Harbour Light
 * Affair` is `hla`, not `ttca` — and nothing else is second-guessed: he can
 * rename it in the Share panel.
 */
export function defaultShort(title) {
  let words = String(title || "").toLowerCase().replace(/[^a-z0-9\s]+/g, " ").split(/\s+/).filter(Boolean);
  if (words.length > 2 && ["the", "a", "an"].includes(words[0])) words = words.slice(1);
  if (!words.length) return "";
  if (words.length === 1) return words[0].slice(0, 24);
  return words.map((w) => w[0]).join("");
}

/**
 * Give a film a short name.
 *
 * Refused when the name is not a short name, is one of the hub's own
 * addresses, or already stands for a different film. A name the film already
 * holds is simply kept. Returns the name, or null when refused.
 */
export async function claimShort(env, project, name) {
  const wanted = String(name || "").toLowerCase();
  if (!SHORT.test(wanted) || RESERVED.has(wanted) || !PROJECT.test(project)) return null;
  const shorts = await shortsOf(env);
  const held = shorts[wanted];
  if (held && held.project !== project) return null;
  if (!held) {
    // **Never another film's title.** `/harbourlightaffair?k=…` is a link crew
    // already hold, and a short name resolves before a title does — so a
    // short name that spelt another film's title would take that film's
    // links for itself. One read of each film's name, on a claim only.
    for (const id of await everyFilm(env)) {
      if (id !== project && slugOf(await titleOf(env, id)) === wanted) return null;
    }
    shorts[wanted] = { project, since: new Date().toISOString() };
    await saveShorts(env, shorts);
  }
  return wanted;
}

/**
 * A film's short name, made if it has none.
 *
 * The default is the title's initials; when those are taken by another film
 * the title squeezed flat is tried, and after that the film keeps none until
 * he names one. Called wherever a film shows its share link, so every film
 * is friendly the first time anybody looks.
 */
export async function ensureShort(env, project, title) {
  const have = await shortOf(env, project);
  if (have) return have;
  // A film with no name yet is called by its id (`titleOf`), and an id is not
  // a name anybody would type — it waits until the film is called something.
  if (!title || title === project) return "";
  for (const guess of [defaultShort(title), slugOf(title)]) {
    if (!guess) continue;
    const got = await claimShort(env, project, guess);
    if (got) return got;
  }
  return "";
}

/**
 * Every short name pointing at one film now points at another — the carry,
 * when a portal made before its film is folded into it.
 */
export async function moveShorts(env, from, to) {
  const shorts = await shortsOf(env);
  let moved = 0;
  for (const hit of Object.values(shorts)) {
    if (hit && hit.project === from) { hit.project = to; moved += 1; }
  }
  if (moved) await saveShorts(env, shorts);
  return moved;
}

/**
 * The key of a film's general link — the one a short name stands for.
 *
 * The same rule the Share panel uses to say which link is *the* link: the
 * first one that still holds its key. Off and expiry are not judged here;
 * `roleFor` judges them when the key is presented, exactly as it would a key
 * typed into the address.
 */
export async function generalKeyOf(env, project) {
  const list = await peopleOf(env, project);
  const found = list.links.find((l) => l && l.key);
  return found ? found.key : "";
}

/**
 * A held file's friendly address, from its name: `Visual Bible` + a `.pdf`
 * → `visual-bible.pdf`; `fb-500t-slog3.cube` stays itself.
 *
 * `/<film>/file/<this>` serves the same bytes `/pic/<content hash>` does
 * (his instruction, 2026-09-19: file links have to be friendly too). The hash
 * address is kept — it is in every page ever served — this is the one the
 * pages now write.
 */
export function fileNameOf(doc) {
  const extension = String(doc && doc.file || "").split(".").pop().toLowerCase();
  const ext = /^[a-z0-9]{1,8}$/.test(extension) ? extension : "";
  let stem = String(doc && doc.name || "").toLowerCase()
    .replace(/[^a-z0-9.]+/g, "-").replace(/-{2,}/g, "-").replace(/^[-.]+|[-.]+$/g, "");
  if (ext && stem.endsWith(`.${ext}`)) stem = stem.slice(0, -(ext.length + 1));
  if (!stem) return "";
  return ext ? `${stem}.${ext}` : stem;
}
