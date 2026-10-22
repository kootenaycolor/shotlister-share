/**
 * **A project's credits, as the portal says them** (2026-10-05, his ask:
 * "I should be able to add more credits than 1 per title").
 *
 * The record keeps every credit as an ordered list — `credits` in the
 * console's credits.py — and the card lists the ones the project shows
 * beyond the director and the producer, which stay the two lines the film
 * gives. Nothing imported: the checks load this file on its own.
 */

const ROLE = /^[A-Za-z][A-Za-z /&'.-]{0,39}$/;

/** A credit's hidden name on the readout: its line fact where the console
 * keeps one (credits.MIRRORS), else `credit:<Role>`. */
const LINES = { "Executive Producer": "executive_producer", "Line Producer": "line_producer" };

function name(said) {
  return String(said == null ? "" : said).replace(/\s+/g, " ").trim().slice(0, 120);
}

/** A card's credits, made safe to draw: a role is a few plain words, each
 * person a name, nobody blank, a role with nobody dropped. */
export function tidyCredits(raw) {
  return (Array.isArray(raw) ? raw : [])
    .slice(0, 16)
    .map((one) => (one && typeof one === "object" ? {
      role: ROLE.test(String(one.role || "")) ? String(one.role) : "",
      people: (Array.isArray(one.people) ? one.people : []).map(name).filter(Boolean).slice(0, 24),
    } : null))
    .filter((one) => one && one.role && one.people.length);
}

/** The credits a card lists beyond the director and the producer: the
 * record's `credits`, less any the project hides (`hidden`, the console's
 * word on its readout). `card_credits` in refresh.py is the same rule. */
export function cardCredits(facts, hidden = []) {
  const one = (facts || {}).credits;
  const list = one && typeof one === "object" && Array.isArray(one.value) ? one.value : [];
  const off = new Set(hidden);
  return tidyCredits(list).filter((c) => c.role !== "Director" && c.role !== "Producer"
    && !off.has(`credit:${c.role}`) && !off.has(LINES[c.role] || ""));
}

/** Names as a credit reads them: "A", "A & B", "A, B & C" — credits.line in
 * the console, the same rule. */
export function creditLine(names) {
  const all = (names || []).filter(Boolean);
  return all.length < 3 ? all.join(" & ") : `${all.slice(0, -1).join(", ")} & ${all[all.length - 1]}`;
}

/** How a credit is said on the page: "Written by"; the rest by its name. */
export function creditWords(role) {
  return role === "Writer" ? "Written by" : role;
}

// ---- writing credits (2026-10-05, the AI connector reaches the record) ----
//
// The console's credits.py, ported: the record keeps one ordered list (the
// `credits` fact) and, beside it, one line per credit (`LINE_FACTS`, every
// credit since people-unified: each is its own Projects property in Notion,
// a link to Crew — never a Crew role), written together in one
// compare-and-set write so the two never disagree. `of`, `plan`, `tidy`,
// `with_people`, `line` and `split` in credits.py are the same rules; change
// one, change both.

/** The credits a project may carry, in the order they are listed. */
export const ROLES = ["Director", "Writer", "Producer", "Executive Producer", "Line Producer",
  "Co-Producer", "Creative Director", "Production Company"];

/** The credits whose line fact is also their name on the readout's `hidden`
 * — credits.MIRRORS, fixed; a later credit is `credit:<Role>` there. */
export const MIRRORS = { Director: "director", Producer: "producer",
  "Executive Producer": "executive_producer", "Line Producer": "line_producer" };

/** Every credit the Notion link keeps both ways, and its line fact —
 * credits.LINES (people-unified, 2026-10-05). */
export const LINE_FACTS = { ...MIRRORS, Writer: "writer", "Co-Producer": "co_producer",
  "Creative Director": "creative_director", "Production Company": "production_company" };

const clean = (said) => String(said == null ? "" : said).normalize("NFC").replace(/\s+/g, " ").trim().slice(0, 120);
const same = (a, b) => clean(a).toLowerCase() === clean(b).toLowerCase();
const rank = (role) => (ROLES.includes(role) ? ROLES.indexOf(role) : ROLES.length);

/** A credits list made safe to keep — credits.tidy. */
export function tidyList(value) {
  const out = [];
  if (!Array.isArray(value)) return out;
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const role = clean(item.role);
    if (!role || !ROLE.test(role)) continue;
    const people = [];
    for (const n of Array.isArray(item.people) ? item.people : []) {
      const one = clean(n);
      if (one && !people.some((p) => same(p, one))) people.push(one);
    }
    const kept = people.slice(0, 24);
    const have = out.find((x) => x.role.toLowerCase() === role.toLowerCase());
    if (have) have.people.push(...kept.filter((p) => !have.people.some((q) => same(p, q))));
    else if (kept.length) out.push({ role, people: kept });
  }
  return out.filter((x) => x.people.length)
    .map((x, i) => [x, i]).sort((a, b) => rank(a[0].role) - rank(b[0].role) || a[1] - b[1])
    .map(([x]) => x).slice(0, 16);
}

/** A credit line back into names: "&" and "," separate, never "and". */
export function splitNames(text) {
  return String(text == null ? "" : text).split(/[&,]/).map(clean).filter(Boolean);
}

export function peopleIn(list, role) {
  const one = (list || []).find((x) => x.role === role);
  return one ? [...one.people] : [];
}

/** The list with one credit's people replaced; nobody left drops it. */
export function withPeople(list, role, names) {
  const rest = (list || []).filter((x) => x.role !== role).map((x) => ({ ...x }));
  return tidyList([...rest, { role, people: [...(names || [])] }]);
}

const factOf = (facts, field) => {
  const one = (facts || {})[field];
  return one && typeof one === "object" ? one : {};
};
const vOf = (one) => Number(one.v) || 0;

/** The project's credits as the record holds them now — credits.of. */
export function creditsOf(facts) {
  const c = factOf(facts, "credits");
  const stored = "value" in c ? tidyList(c.value) : null;
  let out = [...(stored || [])];
  for (const [role, field] of Object.entries(LINE_FACTS)) {
    const m = factOf(facts, field);
    if (typeof m.value !== "string") continue;
    const said = clean(m.value);
    if (stored === null) {
      out = withPeople(out, role, said ? [said] : []);
      continue;
    }
    const newer = Boolean(m.at) && Boolean(c.at) && m.at > c.at && !c.waiting;
    if (newer && !same(creditLine(peopleIn(out, role)), said)) out = withPeople(out, role, said ? [said] : []);
  }
  return out;
}

/** The write that makes the record say `next`: {field: {value, base}} — the
 * list and every line that moves. {} when nothing would change. */
export function creditsPlan(facts, next) {
  const want = tidyList(next);
  const c = factOf(facts, "credits");
  const changes = {};
  if (JSON.stringify(c.value) !== JSON.stringify(want)) changes.credits = { value: want, base: vOf(c) };
  for (const [role, field] of Object.entries(LINE_FACTS)) {
    const line = creditLine(peopleIn(want, role));
    const m = factOf(facts, field);
    const have = typeof m.value === "string" ? m.value : null;
    if (have === null && !line) continue;
    if ((have || "") !== line) changes[field] = { value: line, base: vOf(m) };
  }
  return changes;
}

/** Whether the project hides a credit — its line fact or `credit:<Role>` on
 * the readout's `hidden`. */
export function creditHidden(role, hidden) {
  const off = new Set(hidden || []);
  return off.has(`credit:${role}`) || off.has(MIRRORS[role] || "");
}

// ---- reading credits against people (2026-10-10, the project page on the
// server) — `credit_for`, `roles_of` and `_same` in credits.py.

/** How the trades in Crew's Role say a credit — credits.ALIASES. */
export const CREDIT_ALIASES = { director: "Director", "director/writer": "Director", writer: "Writer",
  producer: "Producer", "executive producer": "Executive Producer", ep: "Executive Producer",
  "line producer": "Line Producer", "co-producer": "Co-Producer", "co producer": "Co-Producer",
  "creative director": "Creative Director", "production company": "Production Company" };

/** Two names one person, case and spacing aside — credits._same. */
export function sameName(a, b) {
  return same(a, b);
}

/** The credit a typed role or Crew trade means ("EP" → Executive Producer),
 * or "" for a trade like Gaffer — credits.credit_for. */
export function creditFor(trade) {
  return CREDIT_ALIASES[clean(trade).toLowerCase()] || "";
}

/** The credits one person holds on this project, in credit order — credits.roles_of. */
export function rolesOf(list, who) {
  return (list || []).filter((x) => (x.people || []).some((p) => same(who, p))).map((x) => x.role);
}
