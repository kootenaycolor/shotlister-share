/**
 * **New Film, made by the server** (2026-10-11, Projects Console without the
 * Mac, stage 3 step 5). The phone's New Film on a project's Film row
 * (`new_film(name, title)`) used to need the Mac: Projects Console asked
 * Shotlister Studio to make a film in Documents/Shotlister and link it
 * (`--newfilm <title> --link <project>`). With the switch on, it is made here
 * instead, straight onto the relay, where every film lives between devices:
 *
 * - **The film**: one change log and the manifest under a new name in the
 *   bucket (`p/<relay id>/`), written by the engine's own `new_film` door
 *   (`mcpweb/src/newfilm.rs`): the project record, the lists every new film
 *   starts with, the title, the project's icon and colour (on the film and its
 *   manifest, as `--link` puts them), and the four link fields it writes — `console_page` (the Notion row's id, as the Mac writes it),
 *   `console_name`, `drive_url` (Notion's Drive Folder), and `drive_folder`,
 *   the Mac's own path to the project's Drive folder as it last sent it
 *   (`drivelists.js`; left out when it never has, as `--link` leaves it out
 *   when it finds no folder).
 * - **The record** names the film (`film.relay`) at once, marked `made: "hub"`,
 *   and a portal the project already had on its own is carried into it
 *   (`carry.js`), as the record door does when the Mac names a film.
 *
 * The Mac and the iPhone then find it under the relay's films in Shotlister
 * (*Open from relay*), like a film made on another device; opening it once
 * fetches it. Until the Mac has it, the Mac's console cannot see it on its
 * disk, so two things hold the link in the meantime: the record door keeps a
 * film the server made when the Mac's readout says "no film"
 * (`keepServerFilm`, while the film is still on the relay), and the Mac's own
 * New Film refuses for a project whose record names one (Projects Console,
 * `backend.new_film`) — so neither a lost link nor a second film.
 *
 * **Refused, with nothing written**: no title; a project with no Notion row;
 * a project whose record already names a film; a film already made for it
 * from here; a film of that name already on the relay (the Mac's own rule,
 * `--newfilm` refuses a taken name). Two presses at once make one film: the
 * project is claimed first (`s/newfilm/<page>.json`, written only if absent).
 *
 * **Off until thrown** (`s/newfilm.json`): with it off the ask is handed to
 * the Mac exactly as before. `POST /console/studio/newfilm/look {name, title}`
 * says what would be made, or why not, and writes nothing.
 */

/** The bucket's layout (relay/layout.js), loaded when first needed so the
 * rules here can be read by a plain node check. */
let LAYOUT = null;
const layout = async () => (LAYOUT ||= await import("../../relay/layout.js"));

export const SWITCH_KEY = "s/newfilm.json";
const claimKey = (page) => `s/newfilm/${page}.json`;
const PAGE = /^[0-9a-f]{32}$/;
/** A claim this old that never finished is taken to have died half-way. */
const STALE_MS = 10 * 60 * 1000;

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return { value: await got.json(), etag: got.etag }; } catch { return { value: null, etag: got.etag }; }
}

/** The switch: `{on, at, by}`, off when never set. */
export async function newFilmOn(env) {
  const got = await readJson(env, SWITCH_KEY);
  const v = got && isObject(got.value) ? got.value : {};
  return { on: v.on === true, at: v.at || null, by: v.by || null };
}

/** The device the server's new films are written as — mcp.js `deviceFor`'s hash. */
export function deviceFor(name) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(`hub/mcp/${String(name).toLowerCase()}`)) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return hash.toString(16).padStart(16, "0");
}

function randomHex(chars) {
  const bytes = new Uint8Array(chars / 2);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** `Projects.safeName` — the name a film's folder takes on the Mac, and so the
 * name two films may not share (`--newfilm` compares them case blind). */
export function safeName(title) {
  return String(title || "").replace(/\//g, "-").replace(/:/g, "-").trim();
}

/** Every film on the relay, by its manifest's title (a film with no manifest is not one). */
async function relayFilms(env) {
  const { keys, names, LAYOUT: L } = await layout();
  const out = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: L.prefix, delimiter: "/", cursor, limit: 1000 });
    for (const prefix of page.delimitedPrefixes || []) {
      const project = prefix.slice(L.prefix.length, -1);
      if (!names.project.test(project)) continue;
      const m = await readJson(env, keys.manifest(project));
      if (m && isObject(m.value)) out.push({ relay: project, title: String(m.value.title || "") });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out;
}

const urlOf = (props) => ((props || {})["Drive Folder"] || {}).url || "";

/**
 * What New Film would do for this project and title, or why it would not —
 * everything checked, nothing written. `row` is the project's Notion row.
 */
export async function planNewFilm(env, row, name, title, { fetchText = null } = {}) {
  const { keys } = await layout();
  const want = String(title || name || "").trim();
  // The Mac's own words (backend.new_film, StudioApp.newFilm).
  if (!want) return { ok: false, why: "a film needs a title" };
  if (!row) return { ok: false, why: "no Notion row for this project" };
  const page = bare(row.id);
  if (!PAGE.test(page)) return { ok: false, why: "no Notion row for this project" };
  const record = await readJson(env, `r/${page}/record.json`);
  const film = record && isObject(record.value) && isObject(record.value.film) ? record.value.film : null;
  if (film) return { ok: false, why: `This project already has a film: ${film.title || "untitled"}.` };
  const claim = await readJson(env, claimKey(page));
  if (claim && isObject(claim.value) && claim.value.relay && await env.BUCKET.head(keys.manifest(claim.value.relay))) {
    return { ok: false, why: `A film was already made for this project: ${claim.value.title || "untitled"}.` };
  }
  const taken = (await relayFilms(env)).find((f) => safeName(f.title).toLowerCase() === safeName(want).toLowerCase());
  if (taken) return { ok: false, why: `a film called "${want}" already exists on the relay` };
  const folders = await readJson(env, `r/${page}/folders.json`);
  const folder = folders && isObject(folders.value) ? String(folders.value.path || "") : "";
  // The project's icon and colour, which the Mac's `--link` puts on the film
  // at once — the same lookup the server's film marks use (filmfacts.js).
  // The record's icon fact first (the project's home); a project with no
  // record yet — an archived one the server never kept — has the Notion
  // row's own icon, which is where the Mac's console cache reads it.
  const { markLookup, fetchIcon, markAddress } = await import("./filmfacts.js");
  let facts = record && isObject(record.value) && isObject(record.value.facts) ? record.value.facts : {};
  if (!markAddress(facts)) {
    const { iconText } = await import("./notionlink.js");
    const address = iconText(row) || "";
    if (address) facts = { icon: { value: address } };
  }
  const marks = markLookup(env, fetchText || fetchIcon);
  // Not kept (`marks.save`): a look writes nothing, and the film marks'
  // own minute keeps the drawings it fetches.
  const pair = await marks.of(facts);
  return {
    ok: true, title: want, page,
    link: {
      title: want, page: String(row.id), name: String(name || ""), drive_url: urlOf(row.properties), drive_folder: folder,
      ...(pair.path ? { mark: { path: pair.path, colour: pair.colour } } : {}),
    },
    claim: claim ? claim.etag : null,
  };
}

/** The record's film block for a film made here — record.build's shape. */
export function filmBlock(title, relay, now = Date.now(), mark = null) {
  return {
    title, relay, archived: false, how: "link",
    shots: 0, scenes: 0, days: 0, boards: 0, last_edit: Math.floor(now / 1000), backup: null,
    director: "", mark: mark && mark.path ? { path: mark.path, colour: mark.colour } : {},
    made: "hub", made_at: new Date(now).toISOString(),
  };
}

/**
 * Name the film on the project's record, compare-and-set; a record is begun if
 * there is none. `also` goes on the film block: a film the server linked
 * rather than made (linkfilm.js) says `linked: "hub"` instead of `made`.
 */
export async function nameOnRecord(env, page, name, title, relay, mark = null, also = null) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const got = await env.BUCKET.get(`r/${page}/record.json`);
    let record = null;
    if (got) { try { record = await got.json(); } catch { record = null; } }
    const next = isObject(record) ? { ...record } : { version: 1, page, name, facts: {}, lights: {} };
    if (isObject(next.film) && next.film.relay && next.film.relay !== relay) {
      throw new Error(`the record named another film while this one was made (${next.film.title || next.film.relay})`);
    }
    next.film = filmBlock(title, relay, Date.now(), mark);
    if (isObject(also)) {
      delete next.film.made;
      delete next.film.made_at;
      Object.assign(next.film, also, { linked_at: new Date().toISOString() });
    }
    next.lights = { ...(isObject(next.lights) ? next.lights : {}), film: "on", portal: "on" };
    next.updated = new Date().toISOString();
    const saved = await env.BUCKET.put(`r/${page}/record.json`, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: got ? { etagMatches: got.etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return;
  }
  throw new Error("the record kept changing while the film was named on it");
}

/**
 * Make the film. Answers the Mac's shape — `{ok, path, linked, said}` — plus
 * `relay` and `title`, or `{ok: false, why}` with nothing written.
 */
export async function makeNewFilm(env, row, name, title, engineMakes = null) {
  const { keys } = await layout();
  const plan = await planNewFilm(env, row, name, title);
  if (!plan.ok) return plan;
  const { page, link } = plan;
  const relay = randomHex(32);
  // Claimed first: a second press, or a second phone, finds it taken.
  const claim = { page, relay, title: plan.title, state: "making", at: new Date().toISOString() };
  const held = await readJson(env, claimKey(page));
  if (held && isObject(held.value) && held.value.state === "making" && Date.now() - Date.parse(held.value.at || 0) < STALE_MS) {
    return { ok: false, why: "A film for this project is being made right now." };
  }
  const claimed = await env.BUCKET.put(claimKey(page), JSON.stringify(claim), {
    httpMetadata: { contentType: "application/json" },
    onlyIf: held ? { etagMatches: held.etag } : { etagDoesNotMatch: "*" },
  });
  if (!claimed) return { ok: false, why: "A film for this project is being made right now." };

  const device = deviceFor("new-film");
  const make = engineMakes || (await import("./newfilmdoor.js")).engineMakes;
  let said, log;
  try {
    ({ said, log } = await make(link, device));
  } catch (e) {
    await env.BUCKET.delete(claimKey(page));
    throw e;
  }
  const logKey = keys.log(relay, `${device}-${randomHex(16)}.log`);
  await env.BUCKET.put(logKey, log, { httpMetadata: { contentType: "text/plain; charset=utf-8" } });
  try {
    await env.BUCKET.put(keys.manifest(relay), said.manifest, { httpMetadata: { contentType: "application/json" } });
  } catch (e) {
    // No half a film left for a device to find.
    await env.BUCKET.delete(logKey);
    await env.BUCKET.delete(claimKey(page));
    throw e;
  }
  await nameOnRecord(env, page, String(name || ""), plan.title, relay, link.mark);
  let carried = null;
  try {
    const { carryPortal } = await import("./carry.js");
    carried = await carryPortal(env, page, relay);
  } catch (e) {
    console.error("new film: carry:", String((e && e.stack) || e));
  }
  await env.BUCKET.put(claimKey(page), JSON.stringify({ ...claim, state: "made", made: new Date().toISOString(), engine_project: said.project }), {
    httpMetadata: { contentType: "application/json" },
  });
  return {
    ok: true, path: "", linked: true, relay, title: plan.title,
    said: `newfilm: "${plan.title}"  on the relay`,
    ...(link.drive_folder ? {} : { folder: "not linked yet: the Mac has not sent this project's Drive folder" }),
    ...(carried ? { carried } : {}),
  };
}

/**
 * **The record door's guard** (worker.js, `PUT /console/record/<page>`): the
 * Mac's readout says "no film" for a project whose film the server made (or
 * linked, linkfilm.js) and the Mac has not fetched yet — it looks only at its own disk. While that
 * film is still on the relay, the server's film and its two lights stay.
 * Anything else the Mac says, including a film of its own, goes as it is.
 */
export async function keepServerFilm(env, stored, incoming) {
  if (!isObject(stored) || !isObject(stored.film)) return incoming;
  if (stored.film.made !== "hub" && stored.film.linked !== "hub") return incoming;
  if (isObject(incoming.film)) return incoming;
  const { keys, names } = await layout();
  const relay = String(stored.film.relay || "");
  if (!names.project.test(relay) || !(await env.BUCKET.head(keys.manifest(relay)))) return incoming;
  const lights = { ...(isObject(incoming.lights) ? incoming.lights : {}) };
  for (const k of ["film", "portal"]) if (stored.lights && stored.lights[k]) lights[k] = stored.lights[k];
  return { ...incoming, film: stored.film, lights };
}
