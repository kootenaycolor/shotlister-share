/**
 * **The project record kept up to date by the server** (2026-10-11, Projects
 * Console without the Mac, stage 3, step 3). The record (`r/<page>/record.json`)
 * is the Console's readout of a project: its lights, its film's counts, its
 * portal. The Mac wrote it — `record.build` / `publish_later` in the console —
 * but only when he opened the project on the Mac, so with the Mac asleep or
 * away it went stale (ZED's was a week old).
 *
 * This looks again, from the server, at what the server can see for itself:
 *
 * - **the film** (`film`): its counts, its icon and colour, how it is tied to
 *   the project, when it was last edited — read from the film's logs;
 * - **the portal** (`portal`): down or up, its links, what viewers see, when
 *   the card was last drawn — read from the portal's own files;
 * - **the project's words from Notion**: stage, type, length, first shoot
 *   day, the website link;
 * - **three lights** — film, portal, website — from those.
 *
 * **What it does not touch** is what only the Mac can see: the Drive folder,
 * the media drives, the showcase, the health lines, the backup. Those lights
 * stay as the Mac last reported them, and `gathered_at` (the Mac's own look)
 * is never moved by this, so the phone can say "as of Tuesday" under them.
 * What this did is stamped on `live_at`.
 *
 * It is a patch: the `facts` are never touched (they are written only through
 * `writeFacts`), nothing is added to a record that has no film or portal, and
 * a record that would not change is not written. Switch: `GET/PUT
 * /console/studio/recordlive` (`on`), off until thrown.
 */

const PAGE = /^[0-9a-f]{32}$/;
const PORTAL_HOST = "https://your-domain.example";
const PROJECTS = "feedface-0000-4000-8000-000000000001";
const SWITCH_KEY = "s/record-live.json";
const LAST_KEY = "s/record-live-last.json";
const SWEEP_EVERY_MINUTES = 10;

/** The pages a film can hide, by the keys the hub's visibility form uses —
 * dossier.HIDEABLE. People is deliberately not here. */
export const HIDEABLE = [["bible", "Visual Bible"], ["camera", "Camera"], ["documents", "Documents"],
  ["shotlist", "Shot List"], ["locations", "Locations"], ["schedule", "Schedule"], ["boards", "Boards"]];

/** Each page the film can show or hide, and which it is — dossier.visible_of. */
export function visibleOf(row, card) {
  if (!row || row.trouble) return [];
  const hidden = new Set(((row.hidden || {}).sections) || []);
  const pages = [...HIDEABLE];
  const known = new Set(pages.map(([k]) => k));
  for (const sec of card && typeof card === "object" && Array.isArray(card.sections) ? card.sections : []) {
    const slug = sec && typeof sec === "object" ? sec.slug : "";
    if (slug && !known.has(slug)) {
      pages.push([slug, sec.name || slug]);
      known.add(slug);
    }
  }
  return pages.map(([slug, label]) => ({ slug, label, on: !hidden.has(slug) }));
}

/** The general-access link as the row reports it — dossier.share_of. */
export function shareOf(row) {
  if (row.trouble) return { trouble: row.trouble };
  const links = (Array.isArray(row.links) ? row.links : []).filter((l) => l && typeof l === "object");
  const live = links.filter((l) => !l.off);
  const first = live[0] || links[0] || null;
  return {
    count: links.length,
    on: live.length > 0,
    hash: (first && first.hash) || "",
    role: (first && first.role) || "viewer",
    expires: (first && first.expires) || "",
    note: (first && first.note) || "",
    password: Boolean(first && first.password),
    address: (first && first.url) || "",
    people: (Array.isArray(row.people) ? row.people : []).length,
  };
}

/** The portal as the record keeps it — record.build's `portal`. */
export function portalBlock(address, card, row) {
  const share = shareOf(row);
  delete share.hash;
  return {
    address: `${PORTAL_HOST}/f/${address}`,
    down: Boolean(row.down),
    since: row.since || "",
    share,
    visible: visibleOf(row, card),
    updated: (card && card.updated) || "",
  };
}

const sameJson = (a, b) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

/**
 * The record with what the server sees laid over it, and which parts moved.
 *
 * `seen` is `{film, portal, notion, relay}` — each part null when it could
 * not be looked at, in which case that part of the record is left exactly as
 * it was (a look that failed never blanks anything).
 */
export function patchRecord(record, seen) {
  const next = { ...record };
  const moved = [];
  const set = (field, value) => {
    if (!sameJson(next[field], value)) {
      next[field] = value;
      moved.push(field);
    }
  };

  if (seen.notion) {
    for (const field of ["stage", "type", "length", "dates", "website", "notion"]) {
      if (field in seen.notion) set(field, seen.notion[field]);
    }
  }

  // The film. Only a record that already names one: this never makes a link.
  const hadFilm = record.film && typeof record.film === "object";
  if (seen.film && hadFilm) {
    const f = seen.film;
    const was = record.film;
    const film = { ...was };
    film.shots = f.shots;
    film.scenes = f.scenes;
    film.days = f.days;
    film.boards = f.boards;
    film.director = f.director;
    // "link" when the film itself carries this project's page id; a film the
    // Mac held by title keeps what the Mac said.
    if (f.consolePage && (f.consolePage === record.page || f.consolePage === record.notion_page)) film.how = "link";
    // The newest edit wins: the Mac's is the film on its disk, ours is when
    // the log reached the bucket, so ours only ever moves it forward.
    if (f.lastEdit && f.lastEdit > Number(was.last_edit || 0)) film.last_edit = f.lastEdit;
    if (f.markPath && f.markColour) film.mark = { path: f.markPath, colour: f.markColour };
    if (!sameJson(was, film)) {
      next.film = film;
      moved.push("film");
    }
  }

  if (seen.portal && (hadFilm || record.portal)) {
    set("portal", seen.portal);
  }

  // Three lights the server can see. The rest are the Mac's, and are not
  // touched. A light moves only from what this look saw.
  const lights = { ...(record.lights || {}) };
  if (hadFilm && seen.film) {
    const how = (next.film && next.film.how) || "";
    lights.film = how === "name" ? "warn" : "on";
    lights.portal = (next.film && next.film.relay) ? "on" : "off";
  }
  if (seen.notion && "website" in seen.notion) lights.website = seen.notion.website ? "on" : "off";
  if (!sameJson(record.lights || {}, lights)) {
    next.lights = lights;
    moved.push("lights");
  }
  return { record: next, moved };
}

// ── reading ─────────────────────────────────────────────────────────────────

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

/** Notion's side of one project row — what record.build reads of the Mac's
 * cache of `fetch_projects`. */
export function notionPart(row) {
  const props = row.properties || {};
  const select = (name) => ((props[name] || {}).select || {}).name || "";
  const date = (props["Shoot Dates"] || {}).date;
  return {
    stage: select("Status") || "?",
    type: select("Type"),
    length: select("Length"),
    dates: date && date.start ? date.start : "",
    website: (props.Website || {}).url || "",
    notion: row.url || "",
  };
}

export async function recordLiveOn(env) {
  const said = await readJson(env, SWITCH_KEY);
  return Boolean(said && said.on === true);
}

/**
 * What the server sees of one project: `reads` are the ways in (injected, so
 * a plain node check need not load the engine or the worker):
 * `film(relay)`, `door(relay)` → {status, json}, `notion(page)`.
 */
export async function seeOne(env, record, reads) {
  const relay = record.film && PAGE.test(String(record.film.relay || "")) ? record.film.relay : "";
  const seen = { film: null, portal: null, notion: null, trouble: [] };
  if (relay) {
    try { seen.film = await reads.film(relay); } catch (e) { seen.trouble.push(`film: ${String((e && e.message) || e).slice(0, 160)}`); }
    try {
      const row = await reads.door(relay);
      const card = (await readJson(env, `p/${relay}/front.json`)) || {};
      if (row && !row.trouble) seen.portal = portalBlock(relay, card, row);
      else seen.trouble.push(`portal: ${(row && row.trouble) || "no readout"}`);
    } catch (e) { seen.trouble.push(`portal: ${String((e && e.message) || e).slice(0, 160)}`); }
  }
  if (reads.notion) {
    try { seen.notion = await reads.notion((typeof record.notion_page === "string" && /^[0-9a-f]{32}$/.test(record.notion_page)) ? record.notion_page : record.page); } catch (e) { seen.trouble.push(`notion: ${String((e && e.message) || e).slice(0, 160)}`); }
  }
  return seen;
}

/** Look again at one record and, unless `dry`, write what moved. Compare and
 * set against the stored copy so a `facts` write landing at the same instant
 * is not lost. Answers {moved, wrote, trouble}. */
export async function liveOne(env, page, reads, { dry = false, at = new Date().toISOString() } = {}) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await env.BUCKET.get(`r/${page}/record.json`);
    if (!current) return { moved: [], wrote: false, trouble: ["no record"] };
    let record;
    try { record = await current.json(); } catch { return { moved: [], wrote: false, trouble: ["unreadable record"] }; }
    const seen = await seeOne(env, record, reads);
    const { record: next, moved } = patchRecord(record, seen);
    if (!moved.length || dry) return { moved, wrote: false, trouble: seen.trouble };
    next.live_at = at;
    next.updated = at;
    const put = await env.BUCKET.put(`r/${page}/record.json`, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: { etagMatches: current.etag },
    });
    if (put) return { moved, wrote: true, trouble: seen.trouble };
  }
  return { moved: [], wrote: false, trouble: ["the record kept changing"] };
}

async function recordPages(env) {
  const pages = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: "r/", delimiter: "/", cursor, limit: 1000 });
    for (const p of got.delimitedPrefixes || []) {
      const page = p.split("/")[1];
      if (PAGE.test(page)) pages.push(page);
    }
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  return pages;
}

/** Every project's Notion row, once: {page: row}. */
export async function projectRows(env) {
  const { notionOf, cloudReady, bareId } = await import("./cloud.js");
  if (!cloudReady(env)) return null;
  const n = notionOf(env);
  const out = {};
  let cursor;
  do {
    const got = await n.post(`data_sources/${PROJECTS}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    for (const row of got.results || []) out[bareId(row.id)] = row;
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

/**
 * The sweep: every record, once. `reads.film` and `reads.door` are per
 * relay; Notion is read once for all.
 */
export async function recordLiveTick(env, makeReads, { dry = false, when = Date.now() } = {}) {
  const at = new Date(when).toISOString();
  const rows = await projectRows(env).catch(() => null);
  const reads = {
    ...makeReads(),
    notion: rows ? async (page) => (rows[page] ? notionPart(rows[page]) : null) : null,
  };
  const wrote = [];
  const trouble = [];
  let looked = 0;
  for (const page of await recordPages(env)) {
    looked += 1;
    let got;
    try {
      got = await liveOne(env, page, reads, { dry, at });
    } catch (e) {
      trouble.push(`${page}: ${String((e && e.message) || e).slice(0, 160)}`);
      continue;
    }
    // A page with folder lists and no record yet (an archived project the
    // Mac sends folders for, drivelists.js) is not a record to keep current.
    if (!got.moved.length && got.trouble.length === 1 && got.trouble[0] === "no record") { looked -= 1; continue; }
    if (got.moved.length) wrote.push(`${dry ? "would move " : ""}${page.slice(-6)}: ${got.moved.join(", ")}`);
    for (const t of got.trouble) trouble.push(`${page.slice(-6)}: ${t}`);
  }
  const out = { at, looked, moved: wrote, trouble, ...(dry ? { dry: true } : {}) };
  await env.BUCKET.put(dry ? `${LAST_KEY}.dry` : LAST_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  return out;
}

/** The ways in on the real worker. */
export function workerReads(env, ctx) {
  return () => ({
    film: async (relay) => (await import("./filmdoor.js")).filmReadout(env, relay, ctx),
    door: async (relay) => {
      const { door } = await import("./cloudportal.js");
      const { status, json } = await door(env, relay, "GET");
      return status >= 400 ? { trouble: json.problem || `the hub answered ${status}` } : json;
    },
  });
}

/** The portal's minute: when the switch is on, a sweep every tenth minute. */
export async function onRecordLiveTimer(env, ctx, when = Date.now()) {
  if (!(await recordLiveOn(env))) return;
  if (new Date(when).getUTCMinutes() % SWEEP_EVERY_MINUTES !== SWEEP_EVERY_MINUTES - 5) return;
  try {
    await recordLiveTick(env, workerReads(env, ctx), { when });
  } catch (e) {
    await env.BUCKET.put(LAST_KEY, JSON.stringify({ at: new Date(when).toISOString(), trouble: [String((e && e.stack) || e).slice(0, 1500)] }),
      { httpMetadata: { contentType: "application/json" } });
  }
}

/** After an edit made on the server (a stage, a website, a portal switch):
 * this one project's record, now, without waiting for the sweep. Never
 * throws and never holds the caller up for long. */
export async function liveAfterEdit(env, page, ctx) {
  try {
    if (!(await recordLiveOn(env))) return;
    const key = String(page || "").replace(/-/g, "").toLowerCase();
    if (!PAGE.test(key)) return;
    const { notionOf, cloudReady } = await import("./cloud.js");
    const reads = workerReads(env, ctx)();
    if (cloudReady(env)) {
      const n = notionOf(env);
      reads.notion = async (p) => notionPart(await n.get(`pages/${p}`));
    }
    await liveOne(env, key, reads);
  } catch (e) {
    console.error("record live:", String((e && e.stack) || e));
  }
}
