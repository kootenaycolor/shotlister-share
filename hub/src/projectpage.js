/**
 * **The project page, answered by the server** (2026-10-10, stage 1 of
 * Projects Console without the Mac). `projectpage.py` in Projects Console,
 * ported rule for rule, with what it needs of `shoots.py` (a shoot's row,
 * its words, its state) and `disagree.py` (the lens check). Change a rule
 * there and change it here in the same breath.
 *
 * One reading per project for the phone's Overview, Shoots, People and
 * Documents: the Shoots, Camera Spec Sheets, Crew and Project Docs data
 * sources in Notion, and the record's crew and credits. Nothing is written
 * to Notion; the only thing kept is which Next-box lines he said are not
 * needed, in R2 at `s/next-hidden.json` (the Mac keeps the same shape in
 * its state folder).
 *
 * **The project's Drive folder** is not the server's to read: the Mac sends
 * the tree its own page reads (`projectpage.folder_tree`, two levels down)
 * whenever it changes (`drivelists.js`), and `gather` takes it as `tree`.
 * Each shoot's `folders` and the Next box's "shoot-N folders" come from it
 * by the Mac's rule (`shoot_folders`). With nothing sent they are empty and
 * `drive_path` is "", as before.
 */

import { bareId, plainTitle, words, relationAll, allCrew } from "./cloud.js";
import { CAMERA_FIELDS as ALL_FIELDS, cameras, sheetLabelled, entries, lutFiles, luts, LUT_FILES, LUT_LABELS, fieldText, labelledCameras } from "./entries.js";
import { lensSets, oneLine } from "./lenses.js";
import { creditFor, rolesOf, sameName } from "./credits.js";

const SHOOTS = "feedface-0000-4000-8000-000000000002";
const SPECS = "feedface-0000-4000-8000-000000000003";
const DOCS = "feedface-0000-4000-8000-000000000005";

// The People tab's groups, in the order a call sheet reads.
const DEPT_ORDER = ["Above the Line", "Production", "AD", "Camera", "G&E", "Sound", "Art", "Costume",
  "Wardrobe", "Makeup", "Post", "Editorial", "Other", "Vendor"];
const DEPT_LABEL = { "Above the Line": "Above the line", Vendor: "Vendors", "": "No department" };

// What the Shoots tab shows from a camera spec sheet, in its words.
// In order of operation (his ask, 2026-10-15), each in its group: Camera,
// Color, Deliverables (`group` on each field; the phone heads each group).
const SPEC_SHOWN = [["Camera", "Camera"], ["Shooting Format", "Format"], ["Lenses", "Lenses"],
  ["Frame Rate", "Frame rate"], ["Codec", "Codec"],
  ["Color Space", "Color"]];
const SPEC_GROUP = { "Color Space": "Color" };
// a camera has no Frame Guides or Finishing Resolution of its own any more (2026-10-15)
const SHEET_FIELDS = ALL_FIELDS.filter(([k]) => k !== "Frame Guides" && k !== "Finishing Resolution");
const groupOf = (k) => SPEC_GROUP[k] || "Camera";
// The camera fields in that order (entries.js keeps its own for the portal's readers).
const CAMERA_ORDER = ["Camera", "Shooting Format", "Capture Resolution", "Desqueeze",
  "Frame Rate", "Codec", "Color Space"];

// The console's words for each camera field (entries.CAMERA_FIELDS there;
// the portal's own words are in entries.js).
const CAMERA_LABEL = { Camera: "Camera", "Shooting Format": "Format", "Capture Resolution": "Resolution",
  "Codec": "Codec", "Color Space": "Color", Desqueeze: "Desqueeze", "Frame Rate": "Frame rate" };

const LENS_WORDS = ["fujinon", "premavista", "angenieux", "angeniuex", "optimo", "zeiss", "supreme", "ultra prime",
  "master prime", "signature", "cooke", "panchro", "leica", "summilux", "canon", "sigma", "atlas",
  "orion", "panavision", "primo", "laowa", "tokina", "ironglass", "helios", "dzofilm", "arri"];

// ── small things Python does for free ────────────────────────────────────────

const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
/** Sort by a list of keys, stable — Python's `sorted(key=lambda: (a, b))`. */
const sortBy = (list, key) => list.map((x, i) => [key(x), i, x])
  .sort((p, q) => { for (let k = 0; k < p[0].length; k++) { const c = cmp(p[0][k], q[0][k]); if (c) return c; } return p[1] - q[1]; })
  .map((p) => p[2]);

/** Any simple Notion property as words — `_prop`. */
export function prop(props, name) {
  const f = (props || {})[name] || {};
  const kind = f.type || "";
  if (kind === "rich_text" || kind === "title") return words(f[kind]);
  if (kind === "number") {
    const n = f.number;
    return n == null ? "" : String(n);
  }
  if (kind === "select") return (f.select || {}).name || "";
  if (kind === "multi_select") return (f.multi_select || []).map((o) => o.name || "").join(", ");
  if (kind === "url") return f.url || "";
  if (kind === "checkbox") return f.checkbox ? "yes" : "";
  return "";
}

const rel = (props, name) => (((props || {})[name] || {}).relation || []).map((r) => bareId(r.id));
const selectOf = (props, name) => (((props || {})[name] || {}).select || {}).name || "";
const multiOf = (props, name) => (((props || {})[name] || {}).multi_select || []).map((o) => o.name);
const textOf = (props, name) => words(((props || {})[name] || {}).rich_text);

// ── days (shoots.py) ─────────────────────────────────────────────────────────

const SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const LONG = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December"];

function dayOf(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || "").slice(0, 10));
  if (!m) return null;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const t = Date.UTC(y, mo - 1, d);
  const back = new Date(t);
  if (back.getUTCFullYear() !== y || back.getUTCMonth() !== mo - 1 || back.getUTCDate() !== d) return null;
  return { y, m: mo, d, t };
}

/** Today where he is — the Mac's `date.today()`. */
export function today(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Vancouver", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}

/** 'Nov 20', 'Nov 20–22', 'Oct 30 – Nov 2', 'Dec 30, 2026 – Jan 2, 2027' — `pretty_range`. */
export function prettyRange(start, end = "") {
  const a = dayOf(start), b = dayOf(end);
  if (!a) return "";
  if (!b || b.t <= a.t) return `${SHORT[a.m - 1]} ${a.d}`;
  if (a.y !== b.y) return `${SHORT[a.m - 1]} ${a.d}, ${a.y} – ${SHORT[b.m - 1]} ${b.d}, ${b.y}`;
  if (a.m !== b.m) return `${SHORT[a.m - 1]} ${a.d} – ${SHORT[b.m - 1]} ${b.d}`;
  return `${SHORT[a.m - 1]} ${a.d}–${b.d}`;
}

export function dayCount(start, end = "") {
  const a = dayOf(start), b = dayOf(end);
  if (!a) return 0;
  return b && b.t > a.t ? Math.round((b.t - a.t) / 86400000) + 1 : 1;
}

/** '2026-10-06' → 'October 6' — `long_day`. */
export function longDay(iso) {
  const a = dayOf(iso);
  return a ? `${LONG[a.m - 1]} ${a.d}` : (iso || "");
}

// ── a shoot's words (shoots.py) ──────────────────────────────────────────────

const NUMBER = /\bShoot\s+(\d+)\b/i;
const DEFAULT_WORDS = /^(?:principal|additional shoot(?:\s+\d+)?|shoot(?:\s+\d+)?)$/i;
const EDGES = " \t·:—–-|,";
const SHOOT_WORDS = { principal: "Principal", additional: "Additional Shoot", shoot: "Shoot" };
const PAST_STAGES = ["Post", "Released", "Archived", "Closed"];

function strip(s, chars) {
  let a = 0, b = s.length;
  while (a < b && chars.includes(s[a])) a += 1;
  while (b > a && chars.includes(s[b - 1])) b -= 1;
  return s.slice(a, b);
}

function restOf(title) {
  for (const dash of [" — ", " – ", " - "]) {
    const at = (title || "").indexOf(dash);
    if (at >= 0) return [title.slice(0, at), dash, title.slice(at + dash.length)];
  }
  return ["", "", title || ""];
}

export function shootNumber(title) {
  const m = NUMBER.exec(title || "");
  return m ? Number(m[1]) : null;
}

/** 'Lets Bake — Shoot 2' → 'Shoot 2' — `shoot_label`. */
export function shootLabel(title) {
  for (const dash of [" — ", " – ", " - "]) {
    const at = (title || "").indexOf(dash);
    if (at >= 0) return title.slice(at + dash.length).trim();
  }
  return title || "";
}

/** The shoot's own name in a Shoots row title — `name_of`. */
export function nameOf(title) {
  const [, dash, r] = restOf(title);
  let rest = r;
  if (DEFAULT_WORDS.test(strip(squash(rest), EDGES))) return "";
  if (!dash) {
    const m = NUMBER.exec(rest);
    if (m) rest = rest.slice(m.index + m[0].length);
  }
  const m = /\(?\bShoot\s+\d+\b\)?/i.exec(rest);
  if (m) rest = `${rest.slice(0, m.index)} ${rest.slice(m.index + m[0].length)}`;
  const name = strip(squash(rest), EDGES);
  return !name || DEFAULT_WORDS.test(name) ? "" : name;
}

function cleanName(name) {
  const s = strip(squash(name), EDGES);
  return DEFAULT_WORDS.test(s) ? "" : s.slice(0, 80);
}

/** One Shoots row as the console reads it — `shoot_of`, with every crew
 * and spec-sheet id even past the 25 a page carries. */
export async function shootOf(n, page) {
  const props = page.properties || {};
  const title = plainTitle(props);
  const when = (props.Dates || {}).date || {};
  return {
    id: page.id,
    title,
    label: shootLabel(title),
    name: nameOf(title),
    n: shootNumber(title),
    start: String(when.start || "").slice(0, 10),
    end: String(when.end || "").slice(0, 10),
    status: selectOf(props, "Status"),
    crew: await relationAll(n, page, "Crew"),
    spec: await relationAll(n, page, "Camera Spec Sheet"),
    projects: ((props.Project || {}).relation || []).map((r) => r.id),
    section: textOf(props, "Shot List Section"),
    changes: textOf(props, "What Changes"),
    url: page.url || "",
  };
}

/**
 * **The record's copy of the shoots, as the page reads a Shoots row**
 * (2026-10-19, Daybreak). When Notion cannot be read the page still shows the
 * shoots the record holds, and a shoot the record has that Notion did not list
 * is shown beside Notion's rather than left off. `copy` is the record's
 * `shoots` value, `crew` its `crew` snapshot (who is on which shoot).
 */
export function shootsFromRecord(copy, crew, page) {
  const people = Array.isArray(crew) ? crew.filter((p) => p && typeof p === "object") : [];
  return (Array.isArray(copy) ? copy : []).filter((x) => x && typeof x === "object" && x.id).map((x) => {
    const id = bareId(x.id);
    return {
      id,
      title: x.title || "",
      label: x.label || shootLabel(x.title || ""),
      name: x.name || "",
      n: x.n ?? null,
      start: String(x.start || "").slice(0, 10),
      end: String(x.end || "").slice(0, 10),
      status: x.status || "",
      crew: people.filter((p) => p.all_shoots || (p.shoots || []).map(bareId).includes(id)).map((p) => p.person).filter(Boolean),
      spec: Array.isArray(x.spec) ? x.spec : [],
      projects: page ? [page] : [],
      section: x.section || "",
      changes: x.changes || "",
      url: `https://www.notion.so/${id}`,
      from_record: true,
      ...(x.missing_in_notion ? { missing_in_notion: true } : {}),
    };
  });
}

/** Notion's rows and the record's: Notion's words where both have a shoot;
 * a record shoot Notion did not list kept. */
export function withRecordShoots(live, fromRecord) {
  const seen = new Set((live || []).map((s) => bareId(s.id)));
  const extra = (fromRecord || []).filter((s) => !seen.has(bareId(s.id)));
  return extra.length ? orderShoots([...(live || []), ...extra]) : (live || []);
}

export const orderShoots = (shoots) => sortBy(shoots, (s) => [s.start || "9999", s.n || 0]);

const isCommercial = (ptype) => ["commercial", "music video"].includes(String(ptype || "").trim().toLowerCase().replace(/\s+/g, " "));

function displayLabel(index, total, commercial, n = null) {
  const num = n || index + 1;
  if (commercial) return total === 1 ? SHOOT_WORDS.shoot : `${SHOOT_WORDS.shoot} ${num}`;
  if (index === 0) return SHOOT_WORDS.principal;
  return total === 2 ? SHOOT_WORDS.additional : `${SHOOT_WORDS.additional} ${num}`;
}

/** The shoot a project has before any Shoots row: its own Shoot Dates — `principal_shoot`. */
export function principalShoot(project) {
  const p = project || {};
  const start = p.dates || "";
  if (!start) return null;
  return { id: "principal", title: "", label: "", name: cleanName(p.shoot_name || ""), n: null,
    start: start.slice(0, 10), end: String(p.dates_end || "").slice(0, 10),
    status: PAST_STAGES.includes(p.status) ? "Wrapped" : "",
    crew: [], spec: [], projects: [], section: "", changes: "", url: "", from_project: true };
}

/** Each shoot's line: its words, days and state — `readout`. */
export function readout(shoots, project = null, now = today()) {
  const out = [];
  let seenNext = false;
  let ordered = orderShoots(shoots);
  if (!ordered.length) {
    const one = principalShoot(project);
    ordered = one ? [one] : [];
  }
  const commercial = isCommercial((project || {}).type);
  ordered.forEach((s, i) => {
    const lastDay = s.end || s.start || "";
    let state;
    if (s.status === "Wrapped") state = "Wrapped";
    else if (lastDay && lastDay < now) state = "To wrap";
    else if (s.start === now || (s.start && s.start <= now && now <= lastDay)) { state = "Today"; seenNext = true; }
    else if (!seenNext) { state = "Next"; seenNext = true; }
    else state = "Upcoming";
    const kind = displayLabel(i, ordered.length, commercial, s.n);
    out.push({ id: s.id, label: s.name || kind, kind, name: s.name || "",
      notion_label: s.label || s.title || "", n: s.n == null ? null : s.n,
      start: s.start || "", end: s.end || "", when: prettyRange(s.start || "", s.end || ""),
      days: dayCount(s.start || "", s.end || ""), from_project: Boolean(s.from_project), state,
      status: s.status || "", url: s.url || "", changes: s.changes || "" });
  });
  return out;
}

// ── people ───────────────────────────────────────────────────────────────────

/** Everyone on the project, one list: the record's crew and everyone named
 * in a credit, each once — `people`. */
export function people(snapshot, directory, credits = null) {
  const byId = new Map();
  for (const r of directory || []) byId.set(bareId(r.id), r);
  const byName = new Map();
  for (const r of directory || []) {
    const k = squash(r.name).toLowerCase();
    if (!byName.has(k)) byName.set(k, []);
    byName.get(k).push(r);
  }
  const cred = credits || [];
  const out = [];
  const seen = new Set();

  const one = (pid, row, name, snap) => {
    const vendor = row.type === "Vendor" || row.department === "Vendor";
    let dept = vendor ? "Vendor" : (row.department || "");
    const fromSnap = [...((snap || {}).roles || [])];
    const trades = fromSnap.length ? fromSnap : String(row.role || "").split(",").map((r) => r.trim()).filter(Boolean);
    const held = rolesOf(cred, name);
    if (!dept && held.length) dept = "Above the Line";
    const trade = trades.filter((t) => !(held.length && creditFor(t)));
    return {
      person: pid,
      name,
      roles: [...held, ...trade.filter((t) => !held.includes(t))],
      credits: held,
      trade: trade.filter((t) => !held.includes(t)),
      trade_all: trades,
      // their usual role (Crew's Role), and whether this project says otherwise (the record's crew_roles)
      usual: String(row.role || "").split(",").map((r) => r.trim()).filter(Boolean),
      role_here: Boolean((snap || {}).roles_here),
      department: dept,
      company: row.company || "",
      location: row.location || "",
      email: row.email || "",
      phone: row.phone || "",
      vendor,
      shoots: ((snap || {}).shoots || []).map(bareId),
      all_shoots: Boolean((snap || {}).all_shoots),
      on_project: snap != null,
      in_crew: Object.keys(row).length > 0,
      url: row.url || "",
    };
  };

  for (const p of snapshot || []) {
    const pid = bareId(p.person);
    const row = byId.get(pid) || {};
    const name = row.name || p.name || "";
    seen.add(pid);
    out.push(one(pid, row, name, p));
  }
  const named = [];
  for (const credit of cred) {
    for (const nm of credit.people || []) if (!named.some((x) => sameName(nm, x))) named.push(nm);
  }
  for (const nm of named) {
    if (out.some((x) => sameName(nm, x.name))) continue;
    const hits = byName.get(squash(nm).toLowerCase()) || [];
    const row = hits.length === 1 ? hits[0] : {};
    const pid = row.id ? bareId(row.id) : "";
    if (pid && seen.has(pid)) continue;
    const x = one(pid, row, row.name || nm, null);
    x.all_shoots = true; // once on the project with no shoot named: every shoot
    out.push(x);
  }
  return out;
}

/** The record's crew rule, from the Crew rows already read — `snapshot_from`. */
export function snapshotFrom(directory, rawShoots, page) {
  const project = bareId(page);
  const shootIds = new Set((rawShoots || []).map((s) => bareId(s.id)));
  const listed = new Map();
  for (const s of rawShoots || []) {
    for (const person of s.crew || []) {
      const k = bareId(person);
      if (!listed.has(k)) listed.set(k, new Set());
      listed.get(k).add(bareId(s.id));
    }
  }
  const out = [];
  for (const row of directory || []) {
    const pid = bareId(row.id);
    const mine = new Set([...(row.shoots || [])].filter((s) => shootIds.has(s)));
    for (const s of listed.get(pid) || []) mine.add(s);
    if (!(row.projects || []).includes(project) && !mine.size) continue;
    out.push({ person: pid, name: row.name || "",
      roles: String(row.role || "").split(",").map((r) => r.trim()).filter(Boolean).sort(),
      shoots: mine.size ? [...mine].sort() : [...shootIds].sort(), all_shoots: !mine.size });
  }
  return sortBy(out, (p) => [p.name.toLowerCase(), p.person]);
}

function deptRank(dept) {
  if (DEPT_ORDER.includes(dept)) return DEPT_ORDER.indexOf(dept);
  return dept ? DEPT_ORDER.length - 1.5 : DEPT_ORDER.length - 1.25;
}

const ROLE_RANK = ["director", "writer", "producer", "ep", "executive producer", "line producer", "co-producer",
  "creative director", "production company", "dp", "director of photography",
  "1st ac", "2nd ac", "loader", "dit", "gaffer", "key grip"];

function roleRank(person) {
  let best = ROLE_RANK.length;
  for (const role of person.roles || []) {
    const r = String(role).trim().toLowerCase();
    ROLE_RANK.forEach((word, i) => {
      if (r === word || r.startsWith(`${word} `) || r.startsWith(`${word}/`)) best = Math.min(best, i);
    });
  }
  return best;
}

/** People grouped by department, call-sheet order, lead roles first — `groups`. */
export function groups(ppl) {
  const by = new Map();
  for (const p of ppl) {
    const d = p.department || "";
    if (!by.has(d)) by.set(d, []);
    by.get(d).push(p);
  }
  return sortBy([...by.keys()], (d) => [deptRank(d)]).map((dept) => ({
    department: dept, label: dept in DEPT_LABEL ? DEPT_LABEL[dept] : dept,
    people: sortBy(by.get(dept), (x) => [roleRank(x), x.name.toLowerCase()]),
  }));
}

const onShoot = (person, shootId) => Boolean(person.all_shoots) || (person.shoots || []).includes(bareId(shootId));

// ── spec sheets ──────────────────────────────────────────────────────────────

/** A sheet field as text, pills one per line (entries.fieldText). */
const spec = (props, name) => fieldText((props || {})[name]);

/** Which fields are pills, and their pills: {prop: [names]}. */
function pillsOfSheet(props) {
  return Object.fromEntries(Object.entries(props || {}).filter(([, f]) => (f || {}).type === "multi_select")
    .map(([k, f]) => [k, (f.multi_select || []).map((o) => o.name || "")]));
}

/** A camera spec sheet as the Shoots tab shows it — `spec_of`. `cameraLabels`
 * is the record's {body: label}, laid on the Camera pills. */
export function specOf(page, cameraLabels = null) {
  const props = page.properties || {};
  return {
    id: bareId(page.id),
    title: plainTitle(props),
    url: page.url || "",
    shoots: rel(props, "Shoot"),
    fields: SPEC_SHOWN.map(([k, label]) => ({ key: k, label, value: spec(props, k), group: groupOf(k) })),
    lenses: spec(props, "Lenses"),
    lens_sets: lensSets(spec(props, "Lenses")),
    pills: pillsOfSheet(props),
    cameras: camerasOf(props, cameraLabels),
    ...lutsOf(props),
  };
}

function camerasOf(props, cameraLabels = null) {
  const texts = Object.fromEntries(SHEET_FIELDS.map(([k]) => [k, spec(props, k)]));
  texts.Camera = labelledCameras(texts.Camera, cameraLabels);
  const g = { ...cameras(texts, lensSets(spec(props, "Lenses"))), labelled: sheetLabelled(texts) };
  // a Notion number (Frame Rate, before it became text) holds one value
  const single = new Set(SHEET_FIELDS.map(([k]) => k).filter((k) => ((props || {})[k] || {}).type === "number"));
  const pill = new Set(SHEET_FIELDS.map(([k]) => k).filter((k) => ((props || {})[k] || {}).type === "multi_select"));
  const ordered = sortBy(SHEET_FIELDS, ([k]) => [CAMERA_ORDER.indexOf(k) < 0 ? 99 : CAMERA_ORDER.indexOf(k)]);
  g.fields = ordered.map(([k]) => ({ key: k, label: CAMERA_LABEL[k], value: k === "Camera" ? spec(props, k) : texts[k],
    single: single.has(k), pills: pill.has(k), entries: single.has(k) ? [] : entries(texts[k]), there: k in props, group: groupOf(k) }));
  return g;
}

function lutsOf(props) {
  const g = luts(lutFiles(props[LUT_FILES] || {}), prop(props, LUT_LABELS));
  return { luts: g.rows, lut_stray: g.stray, lut_labels: prop(props, LUT_LABELS),
    lut_labels_ok: LUT_LABELS in props, luts_ok: LUT_FILES in props };
}

/** The spec sheet a shoot links, else one that names the shoot — `sheet_for`. */
function sheetFor(shoot, sheets) {
  const linked = new Set((shoot.spec || []).map(bareId));
  return sheets.find((sh) => linked.has(sh.id)) || sheets.find((sh) => (sh.shoots || []).includes(bareId(shoot.id))) || null;
}

/**
 * `shoot-N` inside each of the project's sections, with what is in it —
 * `shoot_folders`. `tree` is the Mac's `folder_tree` of the project's Drive
 * folder, as it sent it.
 */
export function shootFolders(tree, n) {
  if (!n) return [];
  const want = `shoot-${n}`;
  const out = [];
  for (const sec of tree || []) {
    for (const child of (sec && sec.children) || []) {
      if (String((child && child.name) || "").toLowerCase() === want) {
        out.push({ path: `${sec.name}/${child.name}`, where: child.path || "",
          items: (child.children || []).map((c) => (c && c.name) || "") });
      }
    }
  }
  return out;
}

/** Each shoot as the page shows it — `shoot_rows`; its folders from the Mac's tree. */
export function shootRows(raw, sheets, ppl, project = null, now = today(), tree = []) {
  let ordered = orderShoots(raw);
  if (!ordered.length) {
    const one = principalShoot(project);
    ordered = one ? [one] : [];
  }
  const states = new Map(readout(ordered, project, now).map((r) => [bareId(r.id), r]));
  return ordered.map((s) => {
    const sid = bareId(s.id);
    const r = states.get(sid) || {};
    const mine = Boolean(s.from_project);
    let sheet = sheetFor(s, sheets);
    if (mine && !sheet) sheet = sheets.find((sh) => !(sh.shoots || []).length) || null;
    return {
      id: sid,
      label: r.label || s.label || s.title || "",
      kind: r.kind || "",
      name: s.name || "",
      notion_label: s.label || s.title || "",
      from_project: mine,
      n: s.n == null ? null : s.n,
      start: s.start || "",
      end: s.end || "",
      when: r.when || "",
      days: r.days || 0,
      long: s.start ? longDay(s.start) : "",
      state: r.state || "",
      status: s.status || "",
      url: s.url || "",
      changes: s.changes || "",
      section: s.section || "",
      spec: sheet,
      people: ppl.filter((p) => mine || onShoot(p, sid)).map((p) => p.person),
      folders: shootFolders(tree, s.n),
    };
  });
}

function nextShoot(rows) {
  for (const state of ["Today", "Next", "To wrap"]) {
    const hit = rows.find((r) => r.state === state);
    if (hit) return hit;
  }
  return null;
}

function previousShoot(rows, shoot) {
  let before = null;
  for (const r of rows) {
    if (r.id === shoot.id) return before;
    before = r;
  }
  return null;
}

// ── lenses ───────────────────────────────────────────────────────────────────

const STOP = new Set(["zoom", "lens", "lenses", "primes", "prime", "set", "and", "for", "on", "the", "with", "instead"]);

/** The lens a sentence names — `lens_phrase`. */
export function lensPhrase(text) {
  const all = String(text || "").match(/[\p{L}\p{N}_’'./-]+/gu) || [];
  for (let i = 0; i < all.length; i++) {
    const w = all[i];
    if (LENS_WORDS.some((m) => w.toLowerCase().includes(m))) {
      const got = [w];
      for (const nxt of all.slice(i + 1, i + 5)) {
        if (STOP.has(nxt.toLowerCase().replace(/^\.+|\.+$/g, ""))) break;
        got.push(nxt);
      }
      return got.join(" ").replace(/[.,]+$/, "");
    }
  }
  return String(text || "").trim();
}

/** disagree.norm / lenses_in. */
const looseWords = (t) => squash(String(t == null ? "" : t).toLowerCase().replace(/’/g, "'").replace(/[^a-z0-9]+/g, " "));
const lensesIn = (text) => new Set(LENS_WORDS.filter((w) => looseWords(text).includes(w)));

/** The shoot's notes name a lens its sheet does not — `lens_check`. */
function lensCheck(shoot) {
  const sheet = shoot.spec;
  if (!sheet) return null;
  const said = lensesIn(shoot.changes || "");
  const onSheet = lensesIn(sheet.lenses || "");
  if (![...said].some((w) => !onSheet.has(w))) return null;
  return { level: "bad", kind: "lens", shoot: shoot.id, shoot_label: shoot.label,
    notes: lensPhrase(shoot.changes || ""), sheet: oneLine(sheet.lenses || ""),
    sheet_url: sheet.url || "", shoot_url: shoot.url || "" };
}

// ── what's next ──────────────────────────────────────────────────────────────

/** The Overview's "Next" box, from real checks only — `next_checks`. */
export function nextChecks(rows, ppl, { media_on, portal_on }) {
  const nxt = nextShoot(rows);
  let checks = [];
  const ready = [];
  if (nxt) {
    const lens = lensCheck(nxt);
    if (lens) checks.push(lens);
    if (ppl != null) {
      const here = ppl.filter((p) => onShoot(p, nxt.id) && !p.vendor);
      const prev = previousShoot(rows, nxt);
      if (!here.length) {
        checks.push({ level: "warn", kind: "nocrew", shoot: nxt.id, shoot_label: nxt.label });
      } else if (prev) {
        const covered = new Set(here.flatMap((p) => p.roles.map((r) => r.toLowerCase())));
        for (const p of ppl) {
          if (p.vendor || p.all_shoots || !p.shoots.includes(prev.id) || p.shoots.includes(nxt.id)) continue;
          const missing = p.roles.filter((r) => !covered.has(r.toLowerCase()));
          if (missing.length) {
            checks.push({ level: "warn", kind: "role", role: missing.join(" / "), person: p.person, name: p.name,
              shoot: nxt.id, shoot_label: nxt.label, from_label: prev.label });
            for (const r of missing) covered.add(r.toLowerCase());
          }
        }
      }
    }
    if (nxt.spec) ready.push("Spec sheet");
    else checks.push({ level: "todo", kind: "nosheet", shoot: nxt.id, shoot_label: nxt.label });
    if ((nxt.folders || []).length) ready.push(nxt.n ? `shoot-${nxt.n} folders` : "shoot folders");
    if (portal_on) ready.push("the portal");
  }
  if (!media_on) checks.push({ level: "todo", kind: "media" });
  const order = { bad: 0, warn: 1, todo: 2 };
  checks = sortBy(checks, (c) => [c.level in order ? order[c.level] : 3]);
  if (ready.length) checks.push({ level: "ok", kind: "ready", parts: ready });
  return { shoot: nxt ? nxt.id : "", checks };
}

// ── lines he said are not needed ─────────────────────────────────────────────

export const HIDEABLE = ["role", "nocrew", "nosheet", "media"];

export function checkKey(check, shootId = "") {
  const shoot = check.shoot || shootId || "";
  const role = String(check.role || "").trim().toLowerCase();
  return `${shoot}|${check.kind || ""}|${role}`;
}

/** The Next box without the lines hidden for this shoot — `hide_checks`. */
export function hideChecks(nxt, hidden) {
  const off = new Set(hidden || []);
  const keep = [];
  let out = 0;
  for (let c of nxt.checks || []) {
    if (HIDEABLE.includes(c.kind)) {
      const k = checkKey(c, nxt.shoot || "");
      if (off.has(k)) { out += 1; continue; }
      c = { ...c, key: k };
    }
    keep.push(c);
  }
  return { ...nxt, checks: keep, hidden: out };
}

/** Python's repr of a string, for the refusal's words. */
function pyRepr(s) {
  const q = s.includes("'") && !s.includes('"') ? '"' : "'";
  const body = s.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t")
    .split(q).join(`\\${q}`);
  return `${q}${body}${q}`;
}

/** A project's set after hiding (or bringing back) one line — `set_hidden`,
 * on the parsed file `d`, which it changes. Throws the Mac's refusal. */
export function setHiddenIn(d, project, key, hide = true) {
  const k = String(key || "");
  if (k.split("|").length - 1 !== 2 || !HIDEABLE.includes(k.split("|")[1])) {
    throw new RangeError(`not a line that can be hidden: ${pyRepr(k)}`);
  }
  const have = new Set(Array.isArray(d[project]) ? d[project] : []);
  if (hide) have.add(k); else have.delete(k);
  if (have.size) d[project] = [...have].sort(); else delete d[project];
  return have;
}

/** Bring back every line hidden for `shoot` (all, with none named); how
 * many came back — `show_hidden`, on the parsed file `d`. */
export function showHiddenIn(d, project, shoot = "") {
  const have = Array.isArray(d[project]) ? [...new Set(d[project])] : [];
  const back = have.filter((k) => !shoot || k.split("|")[0] === shoot);
  const rest = have.filter((k) => !back.includes(k));
  if (rest.length) d[project] = rest.sort(); else delete d[project];
  return back.length;
}

// ── documents ────────────────────────────────────────────────────────────────

/** The project's Notion documents: Project Docs rows and spec sheets — `documents`. */
export function documents(docPages, sheets, rows) {
  const label = new Map(rows.map((r) => [r.id, r.label]));
  const out = [];
  for (const page of docPages || []) {
    const props = page.properties || {};
    const shoots = rel(props, "Shoot").filter((s) => label.has(s));
    out.push({
      id: bareId(page.id),
      kind: "doc",
      title: plainTitle(props),
      url: page.url || "",
      link: prop(props, "URL"),
      categories: multiOf(props, "Category"),
      page: prop(props, "Page") || prop(props, "Section"),
      shoots: shoots.map((s) => label.get(s)),
      shoot_ids: shoots,
      section: prop(props, "Section"),
      on_portal: Boolean((props.Hub || {}).checkbox),
    });
  }
  for (const sh of sheets || []) {
    const shoots = (sh.shoots || []).filter((s) => label.has(s));
    out.push({ id: sh.id, kind: "sheet", title: sh.title, url: sh.url, link: "", categories: ["Spec sheet"],
      page: "Camera", shoots: shoots.map((s) => label.get(s)), shoot_ids: shoots, section: "", on_portal: null });
  }
  return out;
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

/** The project row as the console's list has it, with the record's facts
 * laid over — `engine.fetch_projects` and `record.overlay_rows`, the parts
 * the page reads (name, page, stage, type, shoot dates, the shoot's name). */
export function projectOf(row, facts = {}) {
  const props = row.properties || {};
  const when = (props["Shoot Dates"] || {}).date || null;
  const out = {
    page_id: row.id,
    name: plainTitle(props),
    status: selectOf(props, "Status") || "?",
    type: selectOf(props, "Type"),
    dates: when ? when.start || "" : "",
    dates_end: (when && when.end) || "",
  };
  const kept = (field) => {
    const one = (facts || {})[field];
    return one && typeof one === "object" && typeof one.value === "string" ? one.value : null;
  };
  for (const field of ["status", "type"]) if (kept(field) !== null) out[field] = kept(field);
  const dates = kept("shoot_dates");
  if (dates !== null && !datesRefusal(dates)) {
    const [s, e] = splitDates(dates);
    out.dates = s;
    out.dates_end = e;
  }
  if (kept("shoot_name") !== null) out.shoot_name = kept("shoot_name");
  return out;
}

function splitDates(value) {
  const s = String(value == null ? "" : value).trim();
  const at = s.indexOf("/");
  return at < 0 ? [s, ""] : [s.slice(0, at).trim(), s.slice(at + 1).trim()];
}

/** notionlink.dates_refusal — "" when the record's dates are well formed. */
function datesRefusal(value) {
  const [start, end] = splitDates(value);
  if (!start && !end) return "";
  for (const d of [start, end]) if (d && !/^\d{4}-\d{2}-\d{2}$/.test(d)) return "bad";
  if (end && !start) return "bad";
  if (end && end < start) return "bad";
  for (const d of [start, end]) if (d && !dayOf(d)) return "bad";
  return "";
}

/**
 * One project's page, read from Notion — `gather`. A part that could not be
 * read is named in `trouble` and the rest still arrives; a refusal from
 * Notion (`Handoff`) is thrown, so the ask goes to the Mac.
 */
export async function gather(n, project, crewSnapshot, { media_on, portal_on, credits = null, cameraLabels = null, isHandoff = () => false, now = today(), tree = [], lay = null, recordShoots = null }) {
  const page = project.page_id || "";
  const trouble = [];
  let raw = [], sheetPages = [], directory = [], docPages = [];
  if (page) {
    const parts = [
      ["shoots", async () => orderShoots(await Promise.all((await queryAll(n, SHOOTS, {
        filter: { property: "Project", relation: { contains: page } } })).map((p) => shootOf(n, p))))],
      ["spec sheets", () => queryAll(n, SPECS, {
        filter: { property: "Projects", relation: { contains: page } },
        sorts: [{ timestamp: "created_time", direction: "descending" }] })],
      ["crew", () => allCrew(n)],
      ["documents", () => queryAll(n, DOCS, {
        filter: { property: "Projects", relation: { contains: page } },
        sorts: [{ timestamp: "created_time", direction: "ascending" }] })],
    ];
    const got = await Promise.all(parts.map(async ([what, fn]) => {
      try { return await fn(); } catch (e) {
        if (isHandoff(e)) throw e;
        trouble.push(`${what}: ${(e && e.message) || e}`);
        return [];
      }
    }));
    [raw, sheetPages, directory, docPages] = got;
    // the record's shoots: the page's when Notion's could not be read, and any
    // the record has that Notion did not list (never a shoot off the page)
    if (Array.isArray(recordShoots) && recordShoots.length) {
      const mine = shootsFromRecord(recordShoots, crewSnapshot, page);
      raw = trouble.some((t) => t.startsWith("shoots:")) ? orderShoots(mine) : withRecordShoots(raw, mine);
    }
    // the record's edits Notion has not got yet are laid over its rows (shootedits.js)
    if (typeof lay === "function") raw = orderShoots(lay(raw));
  }
  const sheets = sheetPages.map((p) => specOf(p, cameraLabels));
  let snapshot = crewSnapshot;
  if ((!snapshot || !snapshot.length) && directory.length) {
    // The record has no crew yet: Notion's own rows say the same thing.
    snapshot = snapshotFrom(directory, raw, page);
  }
  const ppl = snapshot != null ? people(snapshot, directory, credits) : null;
  const rows = shootRows(raw, sheets, ppl || [], project, now, tree || []);
  const nxt = nextChecks(rows, ppl, { media_on, portal_on });
  return {
    ok: true,
    name: project.name || "",
    shoots: rows,
    people: ppl || [],
    people_known: ppl != null,
    groups: groups(ppl || []),
    documents: documents(docPages, sheets, rows),
    next: nxt,
    folders: tree || [],
    trouble,
    // a Notion part not answered: the console keeps its last whole page and
    // says one quiet line (projectpage.py `notion_waits`, 2026-10-19)
    ...(trouble.some((t) => /^(shoots|spec sheets|crew|documents):/.test(t)) ? { notion_waits: true } : {}),
    read_at: Date.now() / 1000,
  };
}
