/**
 * **Records and templates, the rules** (stage 5 step 6, group "records") —
 * the Mac's Python ported rule for rule, pure (no bucket, no network), so
 * `node hub/step6records.mjs` checks every function here against what the
 * Python says on his real data (`hub/step6records-real.py`).
 *
 * Which Python each is:
 *   templates.py     check_name, validate, add, rename, remove, edit (the
 *                    folder template's edits); the filing rules' tree
 *                    (_parse_line, parse_tree, find_block, render_tree,
 *                    filing_state, update_filing_rules)
 *   recordlayout.py  the record standards (_type_key, _tidy_template,
 *                    template_for, templates, modes_standard)
 *   backend.py       record_templates, crew_choices, spec_options,
 *                    icon_svg's check, notion_link_status
 *   crewrows.py      companies, _clean, _norm
 *   record.py        links_plan's rename
 * Change one, change both, the same day.
 */

import { pyStrip, squash, casefold, truthy } from "./notionlink.js";
import { ROLES } from "./credits.js";

// ── Python's strings ─────────────────────────────────────────────────────────

/** `str.isspace()`'s characters, as a class body. */
const WS = "\\t\\n\\x0b\\x0c\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const IS_SPACE = new RegExp(`^[${WS}]$`, "u");
const RSTRIP = new RegExp(`[${WS}]+$`, "u");
const pyRstrip = (s) => String(s).replace(RSTRIP, "");
/** `s.strip(chars)` for a set of plain characters. */
const stripChars = (s, chars) => {
  const a = Array.from(String(s));
  let i = 0, j = a.length;
  while (i < j && chars.includes(a[i])) i++;
  while (j > i && chars.includes(a[j - 1])) j--;
  return a.slice(i, j).join("");
};
const cpLen = (s) => Array.from(String(s)).length;
const ljust = (s, n) => s + " ".repeat(Math.max(0, n - cpLen(s)));
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

/** repr() of a str, as Python writes it (for `Unknown edit 'x'.`). */
export function strRepr(s) {
  const t = String(s);
  const q = t.includes("'") && !t.includes('"') ? '"' : "'";
  let out = "";
  for (const c of t) {
    const n = c.codePointAt(0);
    if (c === "\\") out += "\\\\";
    else if (c === q) out += `\\${q}`;
    else if (c === "\n") out += "\\n";
    else if (c === "\r") out += "\\r";
    else if (c === "\t") out += "\\t";
    else if (n < 0x20 || n === 0x7f) out += `\\x${n.toString(16).padStart(2, "0")}`;
    else out += c;
  }
  return q + out + q;
}

/** Python's `sorted()` on strings: by code point. */
export function byCodePoint(a, b) {
  const x = Array.from(a), y = Array.from(b);
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    const d = x[i].codePointAt(0) - y[i].codePointAt(0);
    if (d) return d;
  }
  return x.length - y.length;
}

// ── the folder template's edits (templates.py) ───────────────────────────────

/** An edit the template can't take — said in his words (`templates.Bad`). */
export class Bad extends Error {}

/** templates.check_name — why a folder name can't be used, or "". */
export function checkName(name) {
  const n = name === null || name === undefined ? "" : String(name);
  if (!pyStrip(n)) return "Name can't be empty.";
  if (n !== pyStrip(n)) return "Name can't start or end with a space.";
  if (n.includes("/")) return "Name can't contain “/”.";
  if (n.includes(":")) return "Name can't contain “:”.";
  if (n.startsWith(".")) return "Name can't start with a dot.";
  if (Array.from(n).some((c) => c.codePointAt(0) < 32)) return "Name can't contain line breaks.";
  return "";
}

const parentOf = (path) => (path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : "");
const leafOf = (path) => path.slice(path.lastIndexOf("/") + 1);
const sameName = (a, b) => casefold(a) === casefold(b);
const under = (path, top) => path === top || path.startsWith(`${top}/`);
const childrenOf = (structure, path) => structure.filter((p) => p !== path && under(p, path));

/** templates.validate — the structure as kept, or `Bad`. */
export function validate(structure) {
  if (!Array.isArray(structure)) throw new Bad("The template must be a list of folders.");
  const seen = new Set();
  const out = [];
  for (const raw of structure) {
    if (typeof raw !== "string") throw new Bad("Each folder must be a name.");
    const path = stripChars(raw, "/");
    if (!path) throw new Bad("Name can't be empty.");
    for (const part of path.split("/")) {
      const why = checkName(part);
      if (why) throw new Bad(`${why} (${path})`);
    }
    const key = casefold(path);
    if (seen.has(key)) throw new Bad(`“${leafOf(path)}” is already there.`);
    const parent = parentOf(path);
    if (parent && !seen.has(casefold(parent))) throw new Bad(`“${leafOf(path)}” is missing its parent folder.`);
    seen.add(key);
    out.push(path);
  }
  return out;
}

const orEmpty = (v) => (truthy(v) ? String(v) : "");

/** templates.add */
export function addFolder(structure, parent, name) {
  const tree = validate(structure);
  const why = checkName(name);
  if (why) throw new Bad(why);
  const p = stripChars(orEmpty(parent), "/");
  if (p && !tree.includes(p)) throw new Bad("That folder isn't in the template.");
  const n = String(name);
  if (tree.some((x) => sameName(leafOf(x), n) && parentOf(x) === p)) throw new Bad(`“${n}” is already there.`);
  const made = p ? `${p}/${n}` : n;
  if (!p) return [...tree, made];
  const at = tree.indexOf(p) + 1 + childrenOf(tree, p).length;
  return [...tree.slice(0, at), made, ...tree.slice(at)];
}

/** templates.rename */
export function renameFolder(structure, path, name) {
  const tree = validate(structure);
  const why = checkName(name);
  if (why) throw new Bad(why);
  const p = stripChars(orEmpty(path), "/");
  if (!tree.includes(p)) throw new Bad("That folder isn't in the template.");
  const n = String(name);
  if (leafOf(p) === n) return tree;
  const parent = parentOf(p);
  if (tree.some((x) => x !== p && sameName(leafOf(x), n) && parentOf(x) === parent)) throw new Bad(`“${n}” is already there.`);
  const made = parent ? `${parent}/${n}` : n;
  return tree.map((x) => (under(x, p) ? made + x.slice(p.length) : x));
}

/** templates.remove */
export function removeFolder(structure, path) {
  const tree = validate(structure);
  const p = stripChars(orEmpty(path), "/");
  if (!tree.includes(p)) throw new Bad("That folder isn't in the template.");
  return tree.filter((x) => !under(x, p));
}

/** templates.edit */
export function editTree(structure, op, path = "", name = "") {
  if (op === "add") return addFolder(structure, path, name);
  if (op === "rename") return renameFolder(structure, path, name);
  if (op === "remove") return removeFolder(structure, path);
  throw new Bad(`Unknown edit ${typeof op === "string" ? strRepr(op) : op === null || op === undefined ? "None" : JSON.stringify(op)}.`);
}

/** backend.template_edit — one edit, not saved. */
export function templateEdit(args) {
  const [structure, op, path = "", name = ""] = args;
  try {
    return { ok: true, structure: editTree(structure, op, path, name) };
  } catch (e) {
    if (e instanceof Bad) return { ok: false, why: e.message };
    throw e;
  }
}

// ── the filing rules' project-template tree (templates.py) ───────────────────

/** Settings' name for each tree, in the Mac's order (templates.DESTINATIONS). */
export const DESTINATIONS = ["drive", "media"];

const FENCE = new RegExp(`^[${WS}]*(\`\`\`|~~~)`, "u");
const DRAW = "│├└─┬┌┐┘┤┴┼|`+";
const NOTE = new RegExp(`[${WS}]{2,}|[${WS}]+#[${WS}]|[${WS}]+←|[${WS}]+—[${WS}]|[${WS}]+–[${WS}]`, "u");
const NAMED = new RegExp(`^([^/]*?[^/${WS}])/([${WS}][^\\n]*)?$`, "u");
const TWO_SPACES = new RegExp(`[${WS}]{2,}`, "u");
const PLACEHOLDER = /[<>…]|\.\.\./u;

/** templates._parse_line — one line of a drawn tree, or null. */
export function parseLine(raw) {
  const text = Array.from(pyRstrip(raw));
  let i = 0;
  while (i < text.length && (IS_SPACE.test(text[i]) || DRAW.includes(text[i])
    || (text[i] === "-" && i + 1 < text.length && "- ".includes(text[i + 1])))) i++;
  const rest = text.slice(i).join("");
  if (!rest) return null;
  let name, note, slash;
  const m = NAMED.exec(rest);
  if (m && !TWO_SPACES.test(m[1])) {
    name = m[1];
    note = pyStrip(m[2] || "");
    slash = true;
  } else {
    const at = NOTE.exec(rest);
    const first = at ? rest.slice(0, at.index) : rest;
    name = first.replace(/\/+$/u, "");
    note = at ? pyStrip(rest.slice(first.length)) : "";
    slash = first.endsWith("/");
  }
  name = pyStrip(stripChars(pyStrip(name), "`"));
  if (!name) return null;
  return { col: i, name, note, slash, placeholder: PLACEHOLDER.test(name), raw: String(raw), path: "" };
}

/** templates.parse_tree — a code block's lines → {paths, notes, extras, root, …}. */
export function parseTree(lines) {
  let parsed = lines.map(parseLine).filter(Boolean);
  let root = null;
  if (parsed.length && parsed[0].placeholder && parsed.slice(1).every((p) => p.col > parsed[0].col)) {
    root = parsed[0];
    parsed = parsed.slice(1);
  }
  const stack = [];
  const paths = [], notes = {}, extras = [];
  for (const p of parsed) {
    while (stack.length && stack[stack.length - 1].col >= p.col) stack.pop();
    if (p.placeholder) {
      if (!stack.length) extras.push(p);
      continue;
    }
    if (stack.length && stack[stack.length - 1].placeholder) continue;
    p.path = stack.length ? `${stack[stack.length - 1].path}/${p.name}` : p.name;
    paths.push(p.path);
    if (p.note) notes[p.path] = p.note;
    stack.push(p);
  }
  const drawn = lines.some((l) => l.includes("├") || l.includes("└"));
  const cols = [...new Set(parsed.filter((p) => !p.placeholder).map((p) => p.col))].sort((a, b) => a - b);
  const steps = [];
  for (let k = 1; k < cols.length; k++) if (cols[k] > cols[k - 1]) steps.push(cols[k] - cols[k - 1]);
  const slashes = parsed.map((p) => p.slash);
  return {
    paths, notes, extras, root, drawn,
    indent: steps.length ? Math.min(...steps) : (drawn ? 4 : 2),
    slash: slashes.length > 0 && slashes.filter(Boolean).length * 2 >= slashes.length,
    base_col: cols.length ? Math.min(...cols) : 0,
  };
}

/** Python's tuple compare for (int, bool). */
const scoreAbove = (a, b) => (a[0] !== b[0] ? a[0] > b[0] : Number(a[1]) > Number(b[1]));

/** templates.find_block — the fenced block that draws a template, or null. */
export function findBlock(text, want) {
  const lines = text.split("\n");
  const tops = new Set(want.map((p) => casefold(p.split("/")[0])));
  let best = null, heading = "", i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.startsWith("#")) heading = line;
    const m = FENCE.exec(line);
    if (m) {
      const fence = m[1];
      let j = i + 1;
      while (j < lines.length && !pyStrip(lines[j]).startsWith(fence)) j++;
      if (j >= lines.length) break;
      const tree = parseTree(lines.slice(i + 1, j));
      const mine = new Set(tree.paths.map((p) => casefold(p.split("/")[0])));
      let both = 0;
      for (const t of mine) if (tops.has(t)) both++;
      const score = [both, heading.toLowerCase().includes("template")];
      if (mine.size && score[0] >= Math.min(2, tops.size) && score[0] * 2 >= mine.size && (best === null || scoreAbove(score, best.score))) {
        best = { start: i + 1, end: j, tree, score };
      }
      i = j + 1;
      continue;
    }
    i++;
  }
  return best;
}

/** templates.render_tree — `structure` drawn in the block's own style, its notes kept. */
export function renderTree(tree, structure) {
  const slash = tree.slash ? "/" : "";
  const rows = [];
  const items = structure.map((p) => [p, Object.prototype.hasOwnProperty.call(tree.notes, p) ? tree.notes[p] : ""]);
  const extras = tree.extras.map((x) => [null, x]);
  const root = tree.root;
  if (tree.drawn) {
    const base = " ".repeat(root ? root.col : Math.max(0, tree.base_col - 4));
    const topKids = [...items, ...extras];
    const kidsOf = (parent) => {
      const out = items.filter(([p]) => parentOf(p) === parent);
      return parent === "" ? [...out, ...extras] : out;
    };
    const walkTree = (parent, lead) => {
      const kids = kidsOf(parent);
      kids.forEach(([p, x], n) => {
        const last = n === kids.length - 1;
        const branch = last ? "└── " : "├── ";
        if (p === null) {
          rows.push([base + lead + branch, x.name + (x.slash ? slash : ""), x.note]);
          return;
        }
        rows.push([base + lead + branch, leafOf(p) + slash, x]);
        walkTree(p, lead + (last ? "    " : "│   "));
      });
    };
    if (root === null && !topKids.length) return [];
    walkTree("", "");
  } else {
    const step = tree.indent || 2;
    const base = " ".repeat(tree.base_col);
    for (const [p, note] of items) rows.push([base + " ".repeat(step * (p.split("/").length - 1)), leafOf(p) + slash, note]);
    for (const [, x] of extras) rows.push([base, x.name + (x.slash ? slash : ""), x.note]);
  }
  let width = 0;
  for (const [a, b, c] of rows) if (c) width = Math.max(width, cpLen(a) + cpLen(b));
  const out = root ? [pyRstrip(root.raw)] : [];
  for (const [a, b, c] of rows) out.push(c ? ljust(a + b, width + 2) + c : a + b);
  return out.map(pyRstrip);
}

/** templates._trees_now, given the trees: {which: [...]} for each one there is. */
export function treesNow(trees) {
  const out = {};
  for (const w of DESTINATIONS) if (trees[w] !== null && trees[w] !== undefined) out[w] = Array.isArray(trees[w]) ? [...trees[w]] : [];
  return out;
}

function blocksOf(text, trees) {
  const found = {};
  for (const [w, structure] of Object.entries(trees)) {
    const block = structure.length ? findBlock(text, structure) : null;
    if (block !== null) found[w] = block;
  }
  return found;
}

const drawnSame = (block, structure) => {
  const a = new Set(block.tree.paths.map(casefold)), b = new Set(structure.map(casefold));
  return a.size === b.size && [...a].every((x) => b.has(x));
};

/** Python's read_text(): universal newlines. */
export const universal = (raw) => String(raw).replace(/\r\n?/g, "\n");

/**
 * templates.filing_state, given the doc's words: `text` is the file's words,
 * `null` when it is missing, `false` when it could not be read; `trees` the
 * trees, or `{trouble}` when they could not be had. `path` is said back.
 */
export function filingState(trees, text, path) {
  const out = { path, differ: [] };
  if (!trees || trees.trouble) return { ...out, state: "unreadable" };
  const t = treesNow(trees);
  if (text === null) return { ...out, state: "missing" };
  if (text === false) return { ...out, state: "unreadable" };
  const blocks = blocksOf(text, t);
  if (!Object.keys(blocks).length) return { ...out, state: "unreadable" };
  const differ = Object.entries(blocks).filter(([w, b]) => !drawnSame(b, t[w])).map(([w]) => w);
  return { ...out, state: differ.length ? "out_of_date" : "in_step", differ };
}

/**
 * templates.update_filing_rules, given the doc's words: `{text, redone}` —
 * the doc rewritten (only the blocks that differ, bottom first; everything
 * else byte for byte) and which trees were redrawn. Raises `Bad` as Python does.
 */
export function rewriteFiling(trees, text) {
  if (!trees || trees.trouble) throw new Bad((trees && trees.trouble) || "The folder template can't be read.");
  const t = treesNow(trees);
  if (text === null || text === false) throw new Bad("Filing rules not found.");
  const blocks = blocksOf(text, t);
  if (!Object.keys(blocks).length) throw new Bad("Couldn't find the template in the filing rules.");
  let lines = text.split("\n");
  const redo = Object.entries(blocks).filter(([w, b]) => !drawnSame(b, t[w])).map(([w, b]) => [b, w])
    .sort((x, y) => y[0].start - x[0].start);
  for (const [block, w] of redo) lines = [...lines.slice(0, block.start), ...renderTree(block.tree, t[w]), ...lines.slice(block.end)];
  return { text: lines.join("\n"), redone: redo.map(([, w]) => w).reverse() };
}

// ── the record standards (recordlayout.py) ───────────────────────────────────

export const FIELDS = [["logline", "Logline"], ["synopsis", "Synopsis"],
  ["directors_note", "Director's Note"], ["visual_language", "Visual Language"], ["length", "Length"],
  ["client", "Client"], ["agency", "Agency"], ["shoot_dates", "Shoot Dates"], ["website", "Website"]];
export const FIELD_KEYS = FIELDS.map(([k]) => k);
export const TYPES = ["Narrative", "Commercial", "Music Video", "Personal"];
const ALL = [...FIELD_KEYS];
export const DEFAULTS = {
  Narrative: { fields: ["logline", "synopsis", "directors_note", "visual_language", "length", "shoot_dates", "website"],
    credits: ["Director", "Writer", "Producer", "Executive Producer", "Line Producer"] },
  Commercial: { fields: ["length", "client", "agency", "shoot_dates", "website"],
    credits: ["Director", "Producer", "Executive Producer", "Line Producer"] },
  "Music Video": { fields: ["length", "client", "agency", "shoot_dates", "website"],
    credits: ["Director", "Producer", "Executive Producer", "Line Producer"] },
  Personal: { fields: ["logline", "synopsis", "directors_note", "visual_language", "length", "shoot_dates", "website"],
    credits: ["Director", "Producer"] },
};
export const FALLBACK = { fields: ALL, credits: ["Director", "Producer"] };
export const MODES = ["shot_list", "locations", "references", "schedule", "diagram"];
export const MODES_STANDARD = {
  Narrative: [...MODES],
  Commercial: ["shot_list", "references", "schedule"],
  "Music Video": ["shot_list", "references", "schedule"],
  Personal: ["shot_list", "references"],
};

/** Python's `for x in v` for the values a JSON standard can hold. */
function pyIterOf(v) {
  if (Array.isArray(v)) return v;
  if (typeof v === "string") return Array.from(v);
  if (isObject(v)) return Object.keys(v);
  throw new TypeError(`'${typeof v === "number" ? (Number.isInteger(v) ? "int" : "float") : typeof v === "boolean" ? "bool" : "NoneType"}' object is not iterable`);
}

/** Python's `x in tuple` (== on JSON values; a str only equals a str). */
const inList = (list, x) => typeof x === "string" && list.includes(x);

/** recordlayout._type_key */
export function typeKey(ptype) {
  const t = squash(truthy(ptype) ? String(ptype) : "");
  for (const known of Object.keys(DEFAULTS)) if (casefold(known) === casefold(t)) return known;
  return t;
}

/** recordlayout._tidy_template — a saved standard as the Mac reads it, or null. */
export function tidyTemplate(raw) {
  if (!isObject(raw)) return null;
  const fields = pyIterOf(truthy(raw.fields) ? raw.fields : []).filter((f) => inList(FIELD_KEYS, f));
  const roles = pyIterOf(truthy(raw.credits) ? raw.credits : []).filter((r) => inList(ROLES, r));
  const out = { fields: FIELD_KEYS.filter((f) => fields.includes(f)), credits: ROLES.filter((r) => roles.includes(r)) };
  if (Array.isArray(raw.modes)) {
    const have = new Set(raw.modes.filter((m) => inList(MODES, m)));
    if (have.has("schedule")) have.add("shot_list");
    out.modes = MODES.filter((m) => have.has(m));
  }
  return out;
}

const savedGet = (saved, t) => (isObject(saved) && Object.prototype.hasOwnProperty.call(saved, t) ? saved[t] : undefined);

/** recordlayout.modes_standard(ptype) — no Job, no saved standards. */
export function modesStandard(ptype) {
  const k = typeKey(ptype);
  return [...(Object.prototype.hasOwnProperty.call(MODES_STANDARD, k) ? MODES_STANDARD[k] : MODES)];
}

/** recordlayout.template_for */
export function templateFor(ptype, saved) {
  const t = typeKey(ptype);
  const mine = tidyTemplate(savedGet(saved, t));
  if (mine !== null) return { ...mine, modes: mine.modes !== undefined ? mine.modes : modesStandard(t) };
  // One rule, server and Mac (2026-10-15): a Music Video with no standard of
  // its own is a Commercial, his saved Commercial standard included.
  if (t === "Music Video") return templateFor("Commercial", saved);
  const base = Object.prototype.hasOwnProperty.call(DEFAULTS, t) ? DEFAULTS[t] : FALLBACK;
  return { fields: [...base.fields], credits: [...base.credits], modes: modesStandard(t) };
}

/** recordlayout.templates — every Type's standard and whether it is his. */
export function templatesView(saved, types = []) {
  const names = [...TYPES];
  const keys = isObject(saved) ? Object.keys(saved) : [];
  for (const raw of [...(types || []), ...keys]) {
    const t = typeKey(raw);
    if (t && !names.includes(t)) names.push(t);
  }
  const out = {};
  for (const t of names) out[t] = { ...templateFor(t, saved), changed: tidyTemplate(savedGet(saved, t)) !== null };
  return out;
}

/** backend.record_templates — given his saved standards and Notion's Types. */
export function recordTemplatesAnswer(saved, types) {
  const view = templatesView(saved, types);
  const defaults = {};
  for (const t of Object.keys(view)) {
    const d = Object.prototype.hasOwnProperty.call(DEFAULTS, t) ? DEFAULTS[t] : FALLBACK;
    defaults[t] = { fields: [...d.fields], credits: [...d.credits] };
  }
  return { ok: true, templates: view, fields: FIELDS.map((f) => [...f]), roles: [...ROLES], defaults };
}

/**
 * backend.set_record_template's change to the saved standards: `{saved,
 * ptype}` (the new whole object, the Type as keyed), or `{why}`.
 */
export function standardsAfter(saved, ptype, template) {
  const t = squash(truthy(ptype) ? String(ptype) : "");
  if (!t) return { why: "Which type?" };
  const next = { ...(isObject(saved) ? saved : {}) };
  if (template === null || template === undefined) {
    delete next[t];
  } else {
    const tidy = tidyTemplate(template);
    if (tidy === null) return { why: "Nothing to keep." };
    next[t] = tidy;
  }
  return { saved: next, ptype: t };
}

// ── crew_choices (backend.py, crewrows.py) ──────────────────────────────────

export const COMPANY_KINDS = ["Equipment House", "Production Company", "Post House", "Vendor Contact"];
const MAX = 200;
const bareId = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

/** crewrows._clean */
export const crewClean = (text) => Array.from(squash(String(truthy(text) ? text : "").normalize("NFC"))).slice(0, MAX).join("");

/** crewrows._norm */
export function crewNorm(text) {
  let t = crewClean(text).normalize("NFKD").replace(/[^\x00-\x7f]/g, "").toLowerCase();
  t = t.replace(/\([^\n]*?\)/g, " ");
  return squash(t.replace(/[^a-z0-9& ]/g, " "));
}

/** crewrows.companies — every company Crew knows, one per name. */
export function companies(rows, options = []) {
  const out = [], by = new Map();
  for (const r of rows || []) {
    if (r.type === "Vendor") {
      const name = crewClean(r.company) || crewClean(String(r.name || "").replace(/\([^\n]*?\)/g, ""));
      if (!by.has(crewNorm(name))) {
        const one = { name, vendor: bareId(r.id), row_name: r.name || "", people: 0 };
        by.set(crewNorm(name), one);
        out.push(one);
      }
    }
  }
  for (const r of rows || []) {
    const c = crewClean(r.company);
    if (c && r.type !== "Vendor") {
      let one = by.get(crewNorm(c));
      if (one === undefined) {
        one = { name: c, vendor: "", row_name: "", people: 0 };
        by.set(crewNorm(c), one);
        out.push(one);
      }
      one.people += 1;
    }
  }
  for (const c of options || []) {
    if (!by.has(crewNorm(c))) {
      const one = { name: crewClean(c), vendor: "", row_name: "", people: 0 };
      by.set(crewNorm(c), one);
      out.push(one);
    }
  }
  return out.map((x, i) => [x, i]).sort((a, b) => byCodePoint(a[0].name.toLowerCase(), b[0].name.toLowerCase()) || a[1] - b[1]).map(([x]) => x);
}

/** backend.crew_choices — given Crew's choices and rows. */
export function crewChoicesAnswer(opts, rows) {
  const o = opts || {};
  return { ok: true, roles: o.Role || [], departments: o.Department || [], locations: o.Location || [],
    kinds: [...COMPANY_KINDS], companies: companies(rows, o.Company || []) };
}

// ── spec_options (backend.py) ────────────────────────────────────────────────

/** backend.spec_options — given {prop: [{name, color}]}. */
export function specAnswer(got) {
  const options = {}, colors = {};
  for (const [k, v] of Object.entries(got || {})) {
    options[k] = v.map((o) => o.name);
    colors[k] = {};
    for (const o of v) colors[k][String(o.name).toLowerCase()] = o.color;
  }
  return { ok: true, options, colors };
}

// ── icons (backend.icon_svg's check, notionlink.icon_url / icon_parts) ──────

export const ICON_COLORS = ["gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"];
const ICON_URL = /^https:\/\/www\.notion\.so\/icons\/([a-z0-9_-]+)_([a-z]+)\.svg$/i;

/** Whether backend.icon_svg takes this name and colour: the address it
 * would draw from, or "" (refused: "That isn't one of Notion's icons."). */
export function iconAddress(name, color) {
  const n = String(truthy(name) ? name : ""), c = String(truthy(color) ? color : "");
  const url = `https://www.notion.so/icons/${n}_${c}.svg`;
  if (!ICON_URL.test(pyStrip(url)) || typeof color !== "string" || !ICON_COLORS.includes(color)) return "";
  return `https://www.notion.so/icons/${name}_${color}.svg`;
}

// ── a pasted link's name (record.links_plan, rename) ─────────────────────────

/** links_plan(rename=…) — [the links fact's new value, its base, a refusal or ""]. */
export function renamePlan(facts, linkId, title) {
  const one = (facts || {}).links;
  const base = isObject(one) ? (truthy(one.v) ? Math.trunc(Number(one.v)) : 0) : 0;
  const value = isObject(one) && isObject(one.value) ? { ...one.value } : {};
  const custom = isObject(one) && isObject(one.value) ? one.value.custom : null;
  const items = (Array.isArray(custom) ? custom : []).filter((i) => isObject(i) && truthy(i.url));
  const rid = String(truthy(linkId) ? linkId : "");
  const name = Array.from(squash(String(truthy(title) ? title : ""))).slice(0, 120).join("");
  if (!name) return [null, base, "Give the link a name."];
  if (!items.some((i) => i.id === rid)) return [null, base, "That link was removed."];
  value.custom = items.map((i) => (i.id === rid ? { ...i, title: name } : i));
  return [value, base, ""];
}

// ── the Notion link's status ─────────────────────────────────────────────────

/** notion_link_status as the server says it: its last live look. */
export function linkStatusAnswer(last) {
  const l = isObject(last) ? last : {};
  return { ok: true, at: String(l.at || ""), said: Array.isArray(l.said) ? l.said.slice(-20) : [], trouble: String(l.trouble || "") };
}
