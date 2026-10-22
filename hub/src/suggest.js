/**
 * **Suggestions, answered by the server** (2026-10-11, Projects Console
 * without the Mac, stage 3 step 5). The Mac's `backend.project_suggestions`
 * with `linked.py`, ported rule for rule: for each empty place on a
 * project's page — a shoot's spec sheet, the deck, a document, the Drive
 * folder, the Shotlister film — the best guess at what belongs there. Read
 * only: nothing is ever linked until he taps Link, and Link
 * (`link_suggestion`) is still the Mac's.
 *
 * **A suggestion is only for an empty place.** Two places are guessed from
 * what only the Mac can see, and the server never guesses them:
 *
 * - **the Drive folder**, looked for on the Mac's own disk by its name. The
 *   server answers only when the place is filled already — Notion's Drive
 *   Folder box or the record's `drive_folder` (or a pasted link) — which is
 *   when the Mac does not look either;
 * - **a spare film**, from the films on the Mac's disk, and linked by its
 *   folder there. The server answers when the record names the project's
 *   film (the Mac found it at its last look) or a film link was pasted —
 *   which is when the Mac offers none either — and, since stage 4 step D,
 *   with the Mac asleep and the `linkfilm` switch on, from the films on the
 *   relay instead (linkfilm.js; a film that never synced is not seen).
 *
 * Otherwise the whole ask goes to the Mac (`Handoff`), as it did before this
 * file: a partial answer would leave out a suggestion the Mac would make.
 *
 * Where it differs from the Mac: Notion and the record are read fresh every
 * time (the Mac keeps an answer two minutes, and its project page two
 * minutes); the shoots are read on their own rather than through the whole
 * project page (the same rows, the same spec sheets).
 */

import { projectRow, bareId, Handoff } from "./cloud.js";
import { shootOf, orderShoots, shootRows, specOf, projectOf } from "./projectpage.js";
import { urlRefusal, truthy, cmp, pyStrip } from "./notionlink.js";

const SHOOTS = "feedface-0000-4000-8000-000000000002";
const SPECS = "feedface-0000-4000-8000-000000000003";
const DOCS = "feedface-0000-4000-8000-000000000005";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
/** `str(x or "")` */
const str = (v) => (truthy(v) ? String(v) : "");

// ── words ────────────────────────────────────────────────────────────────────

/** Lower case, apostrophes dropped ("Let's" = "Lets"), everything else that
 * is not a letter or digit a space — linked.words. */
export function words(text) {
  let t = str(text).normalize("NFKD").replace(/[^\x00-\x7f]/g, "").toLowerCase();
  t = t.replace(/['’`]/g, "");
  return t.replace(/[^a-z0-9]+/g, " ").split(" ").filter(Boolean).join(" ");
}

/** engine.slugify — every character not a letter or digit a dash, ends trimmed. */
export function slugify(name) {
  const s = Array.from(String(name).toLowerCase()).map((c) => (/^[\p{L}\p{N}]$/u.test(c) ? c : "-")).join("");
  return s.replace(/^-+|-+$/g, "");
}

/** Does a title name this project — its name or its folder name, as whole
 * words? — linked.names_project */
export function namesProject(title, name, slug = "") {
  const t = ` ${words(title)} `;
  for (const key of new Set([words(name), words(str(slug).replace(/-/g, " "))])) {
    if (key && key.length >= 3 && t.includes(` ${key} `)) return true;
  }
  return false;
}

/** linked.shoot_numbers */
export function shootNumbers(title) {
  return new Set([...words(title).matchAll(/\bshoot\s*(\d+)\b/g)].map((m) => Number.parseInt(m[1], 10)));
}

const DECK = /\b(deck|look\s*book|lookbook|treatment|visual\s*bible|bible|pitch)\b/;
const DECK_SECTIONS = ["Visual Bible", "Look Book"];

/** linked.is_deck */
export function isDeck(title, section = "") {
  return DECK_SECTIONS.includes(section) || DECK.test(words(title));
}

/** `date.fromisoformat(str(iso or "")[:10])` as days since 0001-01-01 (Python's
 * ordinal), or null. Only the plain YYYY-MM-DD the console ever hands it. */
function ordinal(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(str(iso).slice(0, 10));
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (y < 1 || mo < 1 || mo > 12 || d < 1) return null;
  const at = new Date(0);
  at.setUTCFullYear(y, mo - 1, d);
  // a day that is not in its month (30 February) rolls over: not a day
  if (at.getUTCFullYear() !== y || at.getUTCMonth() !== mo - 1 || at.getUTCDate() !== d) return null;
  return Math.round(at.getTime() / 86400000) + 719163;
}

/** linked.days_apart */
export function daysApart(a, b) {
  const da = ordinal(a), db = ordinal(b);
  if (da === null || db === null) return null;
  return Math.abs(da - db);
}

// ── how good a guess is ──────────────────────────────────────────────────────

/**
 * [points, reasons] for one candidate — 0 points means "don't offer it" —
 * linked.score.
 * - names the project (or already sits on it): needed at all;
 * - names this shoot's number: +3; names *another* shoot's: never;
 * - made within a week of the shoot: +2, within three: +1.
 */
export function score(title, { name, slug = "", shootN = null, shootDay = "", made = "", onProject = false } = {}) {
  const why = [];
  let pts = 0;
  if (onProject) {
    pts += 2;
    why.push("on this project");
  } else if (namesProject(title, name, slug)) {
    pts += 3;
    why.push("names the project");
  } else {
    return [0, []];
  }
  if (truthy(shootN)) {
    const nums = shootNumbers(title);
    if (nums.size && !nums.has(shootN)) return [0, []];
    if (nums.has(shootN)) {
      pts += 3;
      why.push(`says Shoot ${shootN}`);
    }
  }
  if (truthy(shootDay) && truthy(made)) {
    const gap = daysApart(shootDay, made);
    if (gap !== null && gap <= 7) {
      pts += 2;
      why.push("made the week of the shoot");
    } else if (gap !== null && gap <= 21) {
      pts += 1;
      why.push("made near the shoot");
    }
  }
  return [pts, why];
}

/** Highest first; ties by newest; at most two, so a slot shows one line and
 * a second only when it is just as likely — linked._best. */
function best(cands) {
  const kept = cands.filter((c) => c.points > 0)
    .map((c, i) => [[-c.points, -(ordinal(c.made || "") || 0)], c.title.toLowerCase(), i, c])
    .sort((p, q) => (p[0][0] - q[0][0]) || (p[0][1] - q[0][1]) || cmp(p[1], q[1]) || (p[2] - q[2]))
    .map((t) => t[3]);
  if (!kept.length) return [];
  const top = [kept[0]];
  if (kept.length > 1 && kept[1].points === kept[0].points) top.push(kept[1]);
  return top;
}

// ── the suggestions ──────────────────────────────────────────────────────────

/** Is the project's Drive Folder place already filled — by Notion's Drive
 * Folder box (the row) or by the record's `drive_folder` fact? —
 * linked.drive_linked. */
export function driveLinked(row, facts) {
  if (pyStrip(str((row || {}).drive_url))) return true;
  const one = (facts || {}).drive_folder;
  return isObject(one) && Boolean(pyStrip(str(one.value)));
}

const candidate = (row, pts, why) => ({ target: row.id, title: row.title, url: row.url || "", made: row.made || "", why, points: pts });

/**
 * Every suggestion for a project's empty places — linked.suggest. Each:
 * {slot, target, kind, title, url, why, points}.
 */
export function suggest({ page, name, slug, shoots = [], sheets = [], spare_sheets = [], docs = [], spare_docs = [],
  drive = null, films = [], have = {} }) {
  const out = [];
  const used = new Set();
  const sheetFree = (sh) => !truthy(sh.shoots);
  for (const s of shoots || []) {
    const sid = s.id;
    const slot = `shoot:${sid}:spec`;
    const linked = new Set([...(s.spec || []), ...sheets.filter((sh) => (sh.shoots || []).includes(sid)).map((sh) => sh.id)]);
    if (!linked.size && !truthy(have[slot])) {
      const cands = [];
      for (const sh of sheets) {
        if (sheetFree(sh)) {
          const [pts, why] = score(sh.title, { name, slug, shootN: s.n, shootDay: s.start || "", made: sh.made || "", onProject: true });
          cands.push({ ...candidate(sh, pts, why), kind: "sheet" });
        }
      }
      for (const sh of spare_sheets) {
        if (sheetFree(sh)) {
          const [pts, why] = score(sh.title, { name, slug, shootN: s.n, shootDay: s.start || "", made: sh.made || "" });
          cands.push({ ...candidate(sh, pts, why), kind: "sheet" });
        }
      }
      for (const c of best(cands)) out.push({ ...c, slot });
    }
  }
  // the project's decks: a Project Docs row that is a deck, on no project
  if (!docs.some((d) => isDeck(d.title, d.section || "")) && !truthy(have.deck)) {
    const cands = [];
    for (const d of spare_docs) {
      if (isDeck(d.title, d.section || "") && !used.has(d.id)) {
        const [pts, why] = score(d.title, { name, slug });
        cands.push({ ...candidate(d, pts, why), kind: "doc" });
      }
    }
    for (const c of best(cands)) {
      out.push({ ...c, slot: "deck" });
      used.add(c.target);
    }
  }
  // any other document that names the project but sits on none
  for (const d of spare_docs) {
    if (used.has(d.id)) continue;
    const [pts, why] = score(d.title, { name, slug });
    if (pts) out.push({ ...candidate(d, pts, why), kind: "doc", slot: "doc" });
  }
  // the Drive folder Notion doesn't know, found on disk by its name
  if (drive && truthy(drive.url) && !truthy(have.drive)) {
    out.push({ slot: "drive", target: drive.url, kind: "drive", title: drive.label || drive.path || "",
      url: drive.url, why: ["the project's folder on the Drive"], points: 5 });
  }
  // a film nobody has claimed, called what the project is called
  for (const f of films || []) {
    if (!truthy(have.film) && namesProject(f.title || "", name, slug)) {
      out.push({ slot: "film", target: f.path, kind: "film", title: f.title, url: "", why: ["names the project"], points: 3 });
      break;
    }
  }
  return out;
}

// ── rows, as the pure functions want them ────────────────────────────────────

const ids = (props, name) => (((props || {})[name] || {}).relation || []).map((r) => String(r.id || "").replace(/-/g, ""));

function titleOf(props) {
  for (const f of Object.values(props || {})) {
    if (f && f.type === "title") return (f.title || []).map((t) => t.plain_text || "").join("").trim();
  }
  return "";
}

/** linked.sheet_row */
export function sheetRow(page) {
  const props = page.properties || {};
  return { id: String(page.id || "").replace(/-/g, ""), title: titleOf(props), url: page.url || "",
    made: String(page.created_time || "").slice(0, 10), shoots: ids(props, "Shoot"), projects: ids(props, "Projects") };
}

/** linked.doc_row */
export function docRow(page) {
  const props = page.properties || {};
  return { id: String(page.id || "").replace(/-/g, ""), title: titleOf(props), url: page.url || "",
    made: String(page.created_time || "").slice(0, 10), section: ((props.Section || {}).select || {}).name || "",
    shoots: ids(props, "Shoot"), projects: ids(props, "Projects") };
}

/** record.custom_links */
function customLinks(facts) {
  const one = (facts || {}).links;
  const value = isObject(one) ? one.value : null;
  const items = isObject(value) ? value.custom : null;
  return (Array.isArray(items) ? items : []).filter((i) => isObject(i) && truthy(i.url));
}

/** The Drive Folder as the Mac's list has it: Notion's box, with the record's
 * `drive_folder` laid over when it is a well-formed address (or "") —
 * `record._overlay_owned`. */
function driveUrlOf(row, facts) {
  const one = (facts || {}).drive_folder;
  if (isObject(one) && typeof one.value === "string" && !urlRefusal(one.value)) return one.value;
  return ((((row || {}).properties || {})["Drive Folder"] || {}).url) || "";
}

// ── the reading ──────────────────────────────────────────────────────────────

async function queryAll(n, source, body = {}) {
  const out = [];
  let cursor;
  do {
    const got = await n.post(`data_sources/${source}/query`, { ...body, page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    out.push(...(got.results || []));
    cursor = got.has_more ? got.next_cursor : undefined;
  } while (cursor);
  return out;
}

async function recordOf(env, page) {
  if (!env || !env.BUCKET) return null;
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

export const FILMS_NEED = "spare films are on the Mac's disk";

/**
 * What the Mac would need its own disk for, or "" when the server can answer
 * the whole ask. `record` is the project's record (its readout and facts).
 */
export function needsTheMac(row, record) {
  const facts = (record && isObject(record.facts) && record.facts) || {};
  const have = {};
  for (const i of customLinks(facts)) have[i.slot] = true;
  const driveIn = driveLinked({ drive_url: driveUrlOf(row, facts) }, facts);
  if (!driveIn && !have.drive) return "the Drive folder is looked for on the Mac's disk";
  if (!(record && record.film) && !have.film) return FILMS_NEED;
  return "";
}

/**
 * backend.project_suggestions(name, force=False). Answers {ok, trouble,
 * suggestions} · {ok: false, why, suggestions: []}, as the Mac does; throws
 * `Handoff` when the answer needs the Mac's disk, or Notion refuses a read.
 * `force` asks nothing: nothing is kept here.
 */
export async function projectSuggestions(env, n, args) {
  const [name] = Array.isArray(args) ? args : [];
  const row = await projectRow(n, name);
  if (!row) return { ok: false, why: "no Notion row for this project", suggestions: [] };
  const page = bareId(row.id);
  const record = await recordOf(env, page);
  const facts = (record && isObject(record.facts) && record.facts) || {};
  const needs = needsTheMac(row, record);
  // **Spare films with the Mac asleep** (stage 4 step D, linkfilm.js): the
  // films on the relay stand in for the ones on its disk, once that switch
  // is on. Awake, the Mac still offers its own, as before.
  let films = [];
  if (needs === FILMS_NEED) {
    const { linkFilmOn, spareFilms } = await import("./linkfilm.js");
    const { macAwake } = await import("./cloudlink.js");
    if (!(await linkFilmOn(env)).on || (await macAwake(env))) throw new Handoff(needs);
    const { filmReadout } = await import("./filmdoor.js");
    try {
      films = (await spareFilms(env, n, page, String(name), slugify(String(name)), filmReadout)).spare;
    } catch (e) {
      throw new Handoff(`${needs} (the relay's could not be read: ${String((e && e.message) || e).slice(0, 120)})`);
    }
  } else if (needs) throw new Handoff(needs);

  const trouble = [];
  const failed = (e) => { if (e instanceof Handoff) throw e; return e; };
  // The project page's shoots: its Shoots rows with the spec sheet each
  // links or names (projectpage.shoot_rows), not the shoot made from the
  // project's own dates. A shoot that cannot be read is no shoot here, and
  // not trouble: the Mac's page keeps that to itself.
  const [rawShoots, mine, spare, docsOn, docsSpare] = await Promise.all([
    queryAll(n, SHOOTS, { filter: { property: "Project", relation: { contains: row.id } } })
      .then((pages) => Promise.all(pages.map((p) => shootOf(n, p)))).then(orderShoots).catch((e) => { failed(e); return null; }),
    queryAll(n, SPECS, { filter: { property: "Projects", relation: { contains: page } },
      sorts: [{ timestamp: "created_time", direction: "descending" }] }).catch(failed),
    queryAll(n, SPECS, { filter: { property: "Projects", relation: { is_empty: true } } }).catch(failed),
    queryAll(n, DOCS, { filter: { property: "Projects", relation: { contains: page } } }).catch(failed),
    queryAll(n, DOCS, { filter: { property: "Projects", relation: { is_empty: true } } }).catch(failed),
  ]);
  const said = (what, got) => {
    if (Array.isArray(got)) return got;
    trouble.push(`${what}: ${(got && got.message) || got}`);
    return [];
  };
  const sheetPages = said("spec sheets", mine);
  const sheets = sheetPages.map(sheetRow);
  const spare_sheets = said("spare spec sheets", spare).map(sheetRow);
  const docs = said("documents", docsOn).map(docRow);
  const spare_docs = said("spare documents", docsSpare).map(docRow);
  const rows = shootRows(rawShoots || [], sheetPages.map((p) => specOf(p)), [], projectOf(row, facts));
  const shoots = rows.filter((s) => !s.from_project)
    .map((s) => ({ id: s.id, n: s.n, label: s.label || "", start: s.start || "", spec: s.spec ? [s.spec.id] : [] }));

  const have = {};
  for (const i of customLinks(facts)) have[i.slot] = true;
  if (driveLinked({ drive_url: driveUrlOf(row, facts) }, facts)) have.drive = true;
  return {
    ok: true,
    trouble,
    suggestions: suggest({ page, name: String(name), slug: slugify(String(name)), shoots, sheets, spare_sheets, docs,
      spare_docs, drive: null, films, have }),
  };
}
