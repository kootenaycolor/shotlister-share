/**
 * **Prepare Showcase from the picked selects** (2026-10-17, his Released →
 * Showcase flow, mockup claude.ai/artifact/6kL31SvcSyiDh5ePFuNXzi).
 *
 * The selects he picks in the Released sheet (the record's `selects`, Drive
 * file ids in his order) are the one source. Each becomes, in the showcase,
 * exactly what the Drive's `portfolio/showcase-structure.md` and the Prepare
 * Showcase ritual (the console's rituals.py) have always made:
 *
 * - `stills/{slug}-{shot-id}-showcase-stills.webp` — the gallery copy, .webp,
 *   fitted inside 2560×1440, under 1MB. A pick that already sits in the
 *   showcase's own `stills/` is that copy already and is kept as it is. In a
 *   showcase split by quality (`stills/lq/`) a new one goes to `stills/lq/`
 *   tagged `-lq`.
 * - `select-stills/{slug}-{NN}-{shot-id}-showcase-stills.webp` — a numbered
 *   copy of each pick, in his order (NN = the pick's place), flat. A re-run
 *   adds the new ones and moves a no-longer-picked one into
 *   `select-stills/z-archive/` — nothing is deleted.
 * - `credits.txt` at the showcase's root — every credit the console holds
 *   for the project, his own as My Credit. When a different credits.txt is
 *   already there it is kept and the new one is `credits-YYYYMMDD.txt`
 *   beside it.
 * - `.portfolio-project`, `stills/`, `select-stills/` when missing.
 * - **Never `website/`** (his call, 2026-10-17): that folder is for web
 *   thumbnails he makes by hand; this flow neither makes nor writes into it.
 *
 * Only adds (and the archive move): a file already there is kept, nothing
 * is renamed or replaced. The pictures themselves are made on a Mac (cwebp, sips); this
 * file only decides what is made and from what. No Thumbnail Maker, no grid
 * image (his call: that is the website picker's, not this flow's).
 *
 * Pure: the checks load it on its own (`hub/showcaseplan.mjs`).
 */

import { creditsOf } from "./credits.js";

export const STILLS_TAG = "-showcase-stills";
const DOTTED = /\d+\.\d+\.\d+/;
const LONG = /\d{4,}/g;
const MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"];
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const pad2 = (n) => String(n).padStart(2, "0");

/** The shot-id half of a showcase name — rituals.shot_id: the dotted
 * scene.shot.take, else the longest run of 4+ digits, else the position. */
export function shotId(name, position) {
  const stem = String(name || "").replace(/\.[^.]+$/, "");
  const dotted = DOTTED.exec(stem);
  if (dotted) return dotted[0];
  const runs = stem.match(LONG) || [];
  if (runs.length) return runs.reduce((best, r) => (r.length > best.length ? r : best), runs[0]);
  return pad2(position);
}

/** One id per name, deduped with the spec's `-N` — rituals.shot_ids_for. */
export function shotIds(names) {
  const seen = {};
  return names.map((n, i) => {
    const sid = shotId(n, i + 1);
    seen[sid] = (seen[sid] || 0) + 1;
    return seen[sid] === 1 ? sid : `${sid}-${seen[sid] - 1}`;
  });
}

const factOf = (record, k) => {
  const f = record && isObject(record.facts) ? record.facts[k] : null;
  return isObject(f) ? f.value : undefined;
};

function longDate(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso || ""));
  return m ? `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}` : "";
}

/** The watch links the record keeps (`links.custom`, slot "watch"). */
function watchLinks(record) {
  const l = factOf(record, "links");
  const all = isObject(l) && Array.isArray(l.custom) ? l.custom : [];
  return all.filter((x) => isObject(x) && x.slot === "watch" && /^https?:\/\//i.test(String(x.url || ""))).map((x) => String(x.url));
}

/**
 * credits.txt: the title, what it is and when, every credit the console
 * holds (the record's credits, then his own as My Credit, then the crew by
 * role), then the website and the watch links.
 */
export function creditsText({ name, record, website = "", me = "Nathaniel Regier" }) {
  const facts = (record && record.facts) || {};
  const type = String(factOf(record, "type") || "").trim();
  const length = String(factOf(record, "length") || "").trim();
  const released = String(factOf(record, "released_date") || "");
  const dates = String(factOf(record, "shoot_dates") || "");
  const year = /^\d{4}/.test(released) ? released.slice(0, 4) : /^\d{4}/.test(dates) ? dates.slice(0, 4) : "";
  const credit = String(factOf(record, "my_credit") || "").trim() || "Cinematographer";
  const rows = [];
  for (const c of creditsOf(facts)) rows.push([c.role === "Writer" ? "Written by" : c.role, c.people.join(", ")]);
  if (!rows.some(([role, who]) => role === credit && who.includes(me))) rows.push([credit, me]);
  const crew = [];
  const roleOf = new Map();
  for (const p of Array.isArray(factOf(record, "crew")) ? factOf(record, "crew") : []) {
    if (!isObject(p) || !p.name) continue;
    for (const r of Array.isArray(p.roles) && p.roles.length ? p.roles : []) {
      const role = String(r).trim();
      // a credit already said ("Director/Writer" for the credited Director) is not said twice
      if (!role || rows.some(([k, who]) => who.includes(p.name) && role.toLowerCase().includes(k.toLowerCase()))) continue;
      if (!roleOf.has(role)) { roleOf.set(role, []); crew.push(role); }
      const list = roleOf.get(role);
      if (!list.includes(p.name)) list.push(String(p.name));
    }
  }
  const crewRows = crew.map((r) => [r, roleOf.get(r).join(", ")]);
  const width = Math.max(14, ...[...rows, ...crewRows].map(([k]) => k.length)) + 2;
  const fmt = ([k, v]) => `${k.padEnd(width)}${v}`;
  const out = [String(name || "").trim()];
  const what = [[type, length].filter(Boolean).join(" "), year].filter(Boolean).join(", ");
  if (what) out.push(what);
  if (longDate(released)) out.push(`Released ${longDate(released)}`);
  out.push("", ...rows.map(fmt));
  if (crewRows.length) out.push("", ...crewRows.map(fmt));
  const site = String(website || factOf(record, "website") || "").trim();
  const watch = watchLinks(record).filter((u) => u !== site);
  if (site || watch.length) out.push("");
  if (site) out.push(site);
  for (const u of watch) out.push(u);
  return `${out.join("\n")}\n`;
}

export const SELECT_DIR = "select-stills";
export const SELECT_ARCHIVE = "z-archive";

/** {slug}-{NN}-{shot-id}-showcase-stills.webp — the leading number is his
 * pick order, so the folder sorts the way he ordered it. */
export function selectName(slug, n, total, sid) {
  return `${slug}-${String(n).padStart(Math.max(2, String(total).length), "0")}-${sid}${STILLS_TAG}.webp`;
}

/** A file this flow made in select-stills/ — a hand-put file is never moved. */
export function isSelectStill(name, slug) {
  const esc = String(slug).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${esc}-\\d{2,}-.+${STILLS_TAG}\\.webp$`).test(String(name));
}

/**
 * What Prepare Showcase makes from the picks. `picks` [{id, name, inShowcase,
 * at}] in his order (`at` = the still's place in the showcase, e.g.
 * "stills/x.webp", when inShowcase); `have` {stills: Set|null, lq: Set|null,
 * select: [{id, name}]|null, root: Set} — the names already there (null =
 * that folder isn't made yet); `credits` {text, old} (old = an existing
 * credits.txt's text at the showcase's root, or null).
 * Answers {files: [{path, kind, state, still, src}], counts, creditsName}.
 * Never `website/`: that folder is his, for hand-made thumbnails.
 */
export function planFiles({ slug, picks, have, credits, showcaseMade, marker, day }) {
  const files = [];
  const add = (path, kind, state, extra = {}) => files.push({ path, kind, state, still: null, ...extra });
  if (!showcaseMade) add("", "folder", "new");
  if (!marker) add(".portfolio-project", "marker", "new");
  if (!have.stills) add("stills/", "folder", "new");
  if (!have.select) add(`${SELECT_DIR}/`, "folder", "new");
  const ids = shotIds(picks.map((p) => p.name));
  const split = Boolean(have.lq);
  const selectHave = new Set((have.select || []).map((f) => f.name));
  const wanted = new Set();
  picks.forEach((p, i) => {
    const sid = ids[i];
    if (p.inShowcase) add(p.at || `stills/${p.name}`, "still", "kept", { still: p.id });
    else {
      const name = `${slug}-${sid}${STILLS_TAG}${split ? "-lq" : ""}.webp`;
      const there = split ? have.lq.has(name) : Boolean(have.stills && have.stills.has(name));
      add(`stills/${split ? "lq/" : ""}${name}`, "still", there ? "kept" : "new", { still: p.id, src: p.id });
    }
    const sel = selectName(slug, i + 1, picks.length, sid);
    wanted.add(sel);
    add(`${SELECT_DIR}/${sel}`, "select", selectHave.has(sel) ? "kept" : "new", { still: p.id, src: p.id, n: i + 1 });
  });
  // shot-id -> its place in the new order, so a select moved aside can say where
  // the same shot went (its number changed) or that it is no longer picked
  const placeOf = new Map(ids.map((sid, i) => [sid, i + 1]));
  const stemRe = new RegExp(`^${String(slug).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}-(\\d{2,})-(.+)${STILLS_TAG}\\.webp$`);
  // a select no longer picked moves into select-stills/z-archive/ — never deleted
  const archive = [];
  for (const f of have.select || []) {
    if (wanted.has(f.name) || f.twin || !isSelectStill(f.name, slug)) continue;
    archive.push({ id: f.id, name: f.name });
    // from/to: the number it had, and the number the same shot has now (null = no longer picked)
    const m = stemRe.exec(f.name), to = m && placeOf.has(m[2]) ? placeOf.get(m[2]) : null;
    add(`${SELECT_DIR}/${SELECT_ARCHIVE}/${f.name}`, "archive", "moved", { id: f.id, from: m ? Number(m[1]) : null, to,
      still: to ? picks[to - 1].id : null });
  }
  let creditsName = "credits.txt";
  const rootHas = have.root || new Set();
  if (credits.old === null || credits.old === undefined) add("credits.txt", "credits", "new");
  else if (credits.old.trim() === credits.text.trim()) add("credits.txt", "credits", "kept");
  else {
    creditsName = `credits-${day}.txt`;
    add(creditsName, "credits", rootHas.has(creditsName) ? "kept" : "new");
  }
  const counts = { new: files.filter((f) => f.state === "new" && f.kind !== "folder").length,
    kept: files.filter((f) => f.state === "kept").length, moved: archive.length };
  return { files, counts, creditsName, archive };
}
