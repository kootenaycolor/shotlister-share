/**
 * **A spare film linked to its project by the server** (2026-10-13, Projects
 * Console without the Mac, stage 4 step D). On the Mac, Link on a film
 * suggestion runs Shotlister's own `--link` on the film on its disk
 * (`backend.link_film`), which writes the four link fields through the
 * engine. With the Mac asleep and the switch on, it is done here instead, on
 * the film's relay copy — where every film lives between devices — through
 * the engine's own `link_film` door (`mcpweb/src/linkfilm.rs`):
 *
 * - **Which films are spare** — `backend.unlinked_films`: a film whose
 *   `console_page` is empty, or names a page no Projects row has any more. A
 *   film linked to ANOTHER project is never offered: moving one is a
 *   different act from adopting a spare. The server can only see films that
 *   have reached the relay; one that never synced is the Mac's to offer, and
 *   with the Mac awake the whole ask stays the Mac's, as before.
 * - **When the project already has a film** — `engine.find_shotlister_film`:
 *   one carrying the project's page, or one called exactly what the project is
 *   called — nothing is offered.
 * - **The link** — `Linking.link`: `console_page` (the Notion row's id, as
 *   the Mac writes it), `console_name`, `drive_url` (Notion's Drive Folder),
 *   then `drive_folder`, the Mac's own path to the project's Drive folder as
 *   it last sent it (`drivelists.js`; left out when it never has).
 * - **Afterwards** the record names the film at once (`film.relay`, marked
 *   `linked: "hub"`, so the record door keeps it while the Mac, which has not
 *   fetched the change, still says "no film"), a portal the project had on its
 *   own is carried into the film (`carry.js`), and the project's facts, icon
 *   and colour go into the film (`mirrorOne`), as Shotlister does the moment a
 *   film carries a page. The record follows within a minute either way
 *   (`liveAfterEdit`).
 *
 * The Halcyon trap (2026-10-13) is why the record is named here and not left
 * to a later look: a portal carried into a film whose record still says
 * `relay: ""` answers 403 on its keyed link until the record names the relay.
 *
 * **Off until thrown** (`s/linkfilm.json`): with it off a film suggestion is
 * the Mac's exactly as before.
 */

let LAYOUT = null;
const layout = async () => (LAYOUT ||= await import("../../relay/layout.js"));

export const SWITCH_KEY = "s/linkfilm.json";
/** What the server last learnt of a film's link, by the logs it read it from. */
const seenKey = (relay) => `s/filmlinks/${relay}.json`;
const PROJECTS = "feedface-0000-4000-8000-000000000001";

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();
const urlOf = (props) => ((props || {})["Drive Folder"] || {}).url || "";

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

/** The switch: `{on, at, by}`, off when never set. */
export async function linkFilmOn(env) {
  const v = (await readJson(env, SWITCH_KEY)) || {};
  return { on: v.on === true, at: v.at || null, by: v.by || null };
}

/** Every film on the relay, by its manifest's title. */
export async function relayFilms(env) {
  const { keys, names, LAYOUT: L } = await layout();
  const out = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: L.prefix, delimiter: "/", cursor, limit: 1000 });
    for (const prefix of page.delimitedPrefixes || []) {
      const relay = prefix.slice(L.prefix.length, -1);
      if (!names.project.test(relay)) continue;
      const m = await readJson(env, keys.manifest(relay));
      if (isObject(m)) out.push({ relay, title: String(m.title || "") });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return out;
}

/**
 * The page a film carries, read from its logs — kept by the logs it was read
 * from, so a film is opened again only when it has changed. `readout` is
 * `filmReadout` (filmdoor.js), passed in so a plain node check need not load
 * the engine.
 */
export async function filmPage(env, relay, readout, ctx, { keep = true } = {}) {
  const { keys } = await layout();
  const listed = await env.BUCKET.list({ prefix: keys.logs(relay), limit: 1000 });
  const objects = (listed.objects || []).filter((o) => o.key.endsWith(".log"));
  const stamp = `${objects.length}:${objects.map((o) => o.key).sort().pop() || ""}:${listed.truncated ? "more" : ""}`;
  const kept = await readJson(env, seenKey(relay));
  if (isObject(kept) && kept.stamp === stamp && !listed.truncated) return String(kept.page || "");
  const film = await readout(env, relay, ctx);
  const page = String((film && film.consolePage) || "");
  if (keep) await env.BUCKET.put(seenKey(relay), JSON.stringify({ stamp, page, at: new Date().toISOString() }), {
    httpMetadata: { contentType: "application/json" },
  });
  return page;
}

/** Every page a project still has — the Mac's `claimed`. */
export async function claimedPages(n) {
  const out = new Set();
  let cursor;
  do {
    const got = await n.post(`data_sources/${PROJECTS}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    for (const p of got.results || []) out.add(bare(p.id));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/**
 * The rules, apart from any reading — `find_shotlister_film` then
 * `unlinked_films`. `films` is `[{relay, title, page}]`; answers
 * `{found, spare}`: the project's own film if it has one (then nothing is
 * spare), else every film no other project holds.
 */
export function spareOf(films, page, name, claimed) {
  const want = bare(page);
  const own = (films || []).find((f) => want && bare(f.page) === want)
    || (films || []).find((f) => String(name || "").trim() && f.title.trim().toLowerCase() === String(name).trim().toLowerCase());
  if (own) return { found: own, spare: [] };
  return {
    found: null,
    spare: (films || []).filter((f) => !(bare(f.page) && claimed.has(bare(f.page)))).map((f) => ({ title: f.title, path: f.relay })),
  };
}

/**
 * The films to offer on a project, read from the relay — the server's
 * `films` for `suggest()`. Only films whose title names the project are
 * opened (the only ones `suggest` would offer), plus the one called exactly
 * the project's name. `readout` as in `filmPage`.
 */
export async function spareFilms(env, n, page, name, slug, readout, ctx, opts = {}) {
  const { namesProject } = await import("./suggest.js");
  const all = await relayFilms(env);
  const exact = (t) => t.trim().toLowerCase() === String(name || "").trim().toLowerCase();
  const near = all.filter((f) => exact(f.title) || namesProject(f.title, name, slug));
  const films = [];
  for (const f of near) films.push({ ...f, page: await filmPage(env, f.relay, readout, ctx, opts) });
  // A film elsewhere on the relay that carries this project's page is its
  // film too; the records name every film the Mac or the server linked, so
  // a record that names one answers that without opening every film.
  const claimed = await claimedPages(n);
  return spareOf(films, page, name, claimed);
}

/** The engine's door, as `mirrorRecord` reaches `mirror_record`. */
async function engineLinks(env, relay, ctx, asked) {
  const door = await import("./filmdoor.js");
  return door.linkFilmEngine(env, relay, ctx, asked);
}

/**
 * Link it. Answers the Mac's `link_suggestion` shape for a film —
 * `{ok, changed: ["film"], title}` — or `{ok: false, why}` with nothing written.
 * `sug` is the suggestion as worked out afresh (target = the film's relay id).
 */
export async function linkFilmHere(env, n, row, name, sug, ctx, hooks = {}) {
  const page = bare(row.id);
  const relay = String(sug.target || "");
  const { names } = await layout();
  if (!names.project.test(relay)) return { ok: false, why: "That suggestion is gone. Look again." };
  // One ID (projectid.js): a project with a portal of its own keeps its pages
  // where they are, so a spare film under another id would hide them. Its
  // Studio side is made in place instead (studioside.js).
  {
    const { oneIdOn } = await import("./projectid.js");
    if ((await oneIdOn(env)).on && await env.BUCKET.head((await layout()).keys.portal(page))) {
      return { ok: false, why: "This project has its own portal. Switch a mode on instead of linking a spare film." };
    }
  }
  const folders = await readJson(env, `r/${page}/folders.json`);
  const folder = isObject(folders) ? String(folders.path || "") : "";
  const claimed = await claimedPages(n);
  const asked = {
    page: String(row.id), name: String(name || ""), drive_url: urlOf(row.properties), drive_folder: folder,
    claimed: [...claimed].filter((p) => p !== page),
  };
  let said;
  try {
    said = await (hooks.engineLinks || engineLinks)(env, relay, ctx, asked);
  } catch (e) {
    return { ok: false, why: String((e && (e.said || e.message)) || e).slice(0, 300) };
  }
  if (!said || !said.ok) return { ok: false, why: "Shotlister did not say it linked it" };
  const { nameOnRecord } = await import("./newfilm.js");
  await nameOnRecord(env, page, String(name || ""), sug.title, relay, null, { linked: "hub" });
  await env.BUCKET.put(seenKey(relay), JSON.stringify({ stamp: "", page: String(row.id), at: new Date().toISOString() }), {
    httpMetadata: { contentType: "application/json" },
  });
  if (!hooks.skipAfter) {
    try {
      const { oneIdOn } = await import("./projectid.js");
      const { carryPortal } = await import("./carry.js");
      if (!(await oneIdOn(env)).on) await carryPortal(env, page, relay);
    } catch (e) {
      console.error("link film: carry:", String((e && e.stack) || e));
    }
    try {
      const { mirrorOne, filmsOwner } = await import("./filmfacts.js");
      const { mirrorRecord } = await import("./filmdoor.js");
      if ((await filmsOwner(env)).owner === "hub") await mirrorOne(env, page, ctx, mirrorRecord);
    } catch (e) {
      console.error("link film: facts:", String((e && e.stack) || e));
    }
    try {
      const { liveAfterEdit } = await import("./recordlive.js");
      await liveAfterEdit(env, page);
    } catch (e) {
      console.error("link film: record:", String((e && e.stack) || e));
    }
  }
  return { ok: true, changed: ["film"], title: sug.title };
}
