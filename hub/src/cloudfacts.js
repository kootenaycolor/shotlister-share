/**
 * **A project's facts, answered by the server** (2026-10-13, Projects Console
 * without the Mac, group 2). Seven asks that waited for the Mac:
 * `project_facts`, `set_project_facts`, `settle_facts`, `project_history`,
 * `set_project_credits`, `add_custom_link`, `remove_custom_link` — the
 * console's `backend.py` methods of those names, with the parts of
 * `record.py` they call (`facts`, `set_facts`, `settle`, `history`,
 * `change_credits`, `change_links`, `links_plan`, `link_title`) and
 * `backend.page_title`, ported rule for rule. Change a rule there and change
 * it here in the same breath; `hub/factsedit.mjs` holds the two together.
 *
 * **What was the hub's already, and is called, not copied.** The facts
 * themselves live on the record and have one writer, `writeFacts` (facts.js,
 * the door the Mac's `record.set_facts` PUTs to: one version per fact,
 * compare-and-set, every change kept in the history). The Notion link's
 * questions and his pick on one are `conflictsList` / `settleConflict`
 * (notionsync.js, the door `record.settle` POSTs to). What a project shows is
 * `resolveLayout` (notionlink.js) and its Type from `projectType`
 * (cloudlayout.js). The credits' reading and planning are notionlink.js's
 * port of `credits.py`. What is here is what the Mac adds on top: the
 * refusals in his words, the three tries against a record that moves, the
 * links list, a pasted page's title, and what happens after a save.
 *
 * **After a save**, as the Mac does it, each only when the save touched it:
 * - the readout's `hidden` line said again (Type, layout, story) — `_readout_later`
 * - the Notion link looks at this project now — `notionsync.kick`; only when
 *   the server keeps Notion in step (`/console/studio/owner`), as the Mac's
 *   own kick stands down when it does not
 * - the film is told now — `filmfacts.kick`; only when the server writes the
 *   films (`/console/studio/owner/films`)
 * - a Client or Agency typed in is made a company in Crew if Crew has
 *   nothing like it — `_crew_company_later`
 * - the icon and colour handed back for the header tile — `_patch_look`
 * None of these can undo the save or hand the ask to the Mac: they are tried
 * after the record is written and a failure is only logged, as the Mac's
 * threads only log.
 *
 * **Where it differs from the Mac, on purpose** (and held to in the checks):
 * - the history says the server made the change (`by: "server"`), not the
 *   Mac's name, as cloudlayout.js and cloudrecord.js do;
 * - nothing is queued offline: the record is here, so `offline` is false and
 *   `waiting` is 0. `conflicts` counts the Notion link's questions the server
 *   holds. While the Mac keeps Notion in step those questions are the Mac's,
 *   so `project_facts` and `settle_facts` are handed to it (`Handoff`);
 * - the Type a project is read by is the record's as it is now, never a list
 *   a few minutes old (only differs when the Type is set to nothing);
 * - the side effects run before the answer, not on a thread after it —
 *   except the two that go to Notion (the link's look, a company made in
 *   Crew): his rule (2026-10-15) is that no save waits on Notion, so those
 *   run beside the reply (`ctx.waitUntil`) and the link's own minute is the
 *   backstop.
 */

import { resolveLayout, truthy, pyStrip, squash, casefold, FACTS as LINK_FACTS, sorted, pyEqual,
  creditTidy, creditPeople, withPeople, creditsOf, creditsPlan } from "./notionlink.js";
import { projectRow, bareId, Handoff, allCrew, duplicates, companyProps, crewOptions, readsBack, iconFor } from "./cloud.js";
import { projectType, savedTemplates, patchHidden } from "./cloudlayout.js";
import { HTML5, INVALID_CHARREFS, INVALID_CODEPOINTS } from "./htmlnames.js";

/** Who the history says made a change written here. */
export const BY = "server";
const CREW = "feedface-0000-4000-8000-000000000004";
const NO_ROW = "This project has no Notion row.";

/** backend.FILM_FACTS — a save of any asks the film to take the record's words. */
export const FILM_FACTS = new Set(["title", "director", "producer", "client", "agency", "credits", "layout", "story", "type"]);
/** backend.notionsync_fields() — notionlink.FACTS. */
export const LINK_FIELDS = new Set(Object.keys(LINK_FACTS));
/** The facts whose change says the readout's `hidden` again. */
const READOUT_FACTS = ["type", "layout", "story"];

// ── Python's rules, where JavaScript's differ ────────────────────────────────

/** `str.isspace()` — Python's `\s` and `split()`. */
const WS = "\\t\\n\\x0b\\x0c\\r\\x1c-\\x1f \\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const isObj = (x) => x !== null && typeof x === "object" && !Array.isArray(x);
const has = (o, k) => isObj(o) && Object.prototype.hasOwnProperty.call(o, k);
/** `x or default` */
const or = (x, d) => (truthy(x) ? x : d);

/** An exception the Mac's code would raise, its words as `str(e)` says them. */
export class PyError extends Error {}

function pyType(x) {
  if (x === null || x === undefined) return "NoneType";
  if (typeof x === "boolean") return "bool";
  if (typeof x === "number") return Number.isInteger(x) ? "int" : "float";
  if (typeof x === "string") return "str";
  return Array.isArray(x) ? "list" : "dict";
}

/** `repr(float)` — shortest digits, Python's switch to an exponent. A JSON
 * number with no fraction is taken as Python's int (JSON cannot tell). */
function numRepr(x) {
  if (Number.isNaN(x)) return "nan";
  if (!Number.isFinite(x)) return x > 0 ? "inf" : "-inf";
  if (Number.isInteger(x) && Math.abs(x) < 1e21) return BigInt(x).toString();
  const [m, e] = x.toExponential().split("e");
  const exp = Number(e);
  const digits = m.replace("-", "").replace(".", "");
  const sign = x < 0 ? "-" : "";
  if (exp < -4 || exp >= 16) {
    return `${sign}${digits[0]}${digits.length > 1 ? `.${digits.slice(1)}` : ""}e${exp < 0 ? "-" : "+"}${String(Math.abs(exp)).padStart(2, "0")}`;
  }
  if (exp >= 0) {
    const whole = digits.slice(0, exp + 1).padEnd(exp + 1, "0");
    return `${sign}${whole}.${digits.slice(exp + 1) || "0"}`;
  }
  return `${sign}0.${"0".repeat(-exp - 1)}${digits}`;
}

const NOT_PRINTABLE = /[\p{Cc}\p{Cf}\p{Cs}\p{Co}\p{Cn}\p{Zl}\p{Zp}\p{Zs}]/u;

function strRepr(s) {
  const q = s.includes("'") && !s.includes("\"") ? "\"" : "'";
  let out = q;
  for (const ch of s) {
    const c = ch.codePointAt(0);
    if (ch === q || ch === "\\") out += `\\${ch}`;
    else if (ch === "\t") out += "\\t";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch !== " " && NOT_PRINTABLE.test(ch)) {
      if (c <= 0xff) out += `\\x${c.toString(16).padStart(2, "0")}`;
      else if (c <= 0xffff) out += `\\u${c.toString(16).padStart(4, "0")}`;
      else out += `\\U${c.toString(16).padStart(8, "0")}`;
    } else out += ch;
  }
  return out + q;
}

/** `repr(v)` for a JSON value. */
export function pyRepr(v) {
  if (v === null || v === undefined) return "None";
  if (v === true) return "True";
  if (v === false) return "False";
  if (typeof v === "number") return numRepr(v);
  if (typeof v === "string") return strRepr(v);
  if (Array.isArray(v)) return `[${v.map(pyRepr).join(", ")}]`;
  return `{${Object.entries(v).map(([k, x]) => `${strRepr(k)}: ${pyRepr(x)}`).join(", ")}}`;
}

/** `str(v)` for a JSON value. */
export const pyStr = (v) => (typeof v === "string" ? v : pyRepr(v));

/** A decimal digit's value, any script (Python's int() takes them all). */
function digitValue(ch) {
  const cp = ch.codePointAt(0);
  let start = cp;
  while (start > 0 && /\p{Nd}/u.test(String.fromCodePoint(start - 1))) start -= 1;
  return (cp - start) % 10;
}

/** `int(x)`, raising as Python raises. */
export function pyInt(x) {
  if (typeof x === "boolean") return x ? 1 : 0;
  if (typeof x === "number") {
    if (Number.isNaN(x)) throw new PyError("cannot convert float NaN to integer");
    if (!Number.isFinite(x)) throw new PyError("cannot convert float infinity to integer");
    return Math.trunc(x);
  }
  if (typeof x === "string") {
    const m = /^([+-]?)(\p{Nd}(?:_?\p{Nd})*)$/u.exec(pyStrip(x));
    if (!m) throw new PyError(`invalid literal for int() with base 10: ${strRepr(x)}`);
    let n = 0;
    for (const ch of m[2]) if (ch !== "_") n = n * 10 + digitValue(ch);
    return m[1] === "-" ? -n : n;
  }
  throw new PyError(`int() argument must be a string, a bytes-like object or a real number, not '${pyType(x)}'`);
}

/** `for x in v` — a list's items, a string's letters, a dict's keys. */
export function pyIter(v) {
  if (Array.isArray(v)) return v;
  if (typeof v === "string") return Array.from(v);
  if (isObj(v)) return Object.keys(v);
  throw new PyError(`'${pyType(v)}' object is not iterable`);
}

/** `v[i]` for i = 0, 1. Any refusal is one the Mac catches. */
function pyIndex(v, i) {
  if (Array.isArray(v)) {
    if (i >= v.length) throw new PyError("list index out of range");
    return v[i];
  }
  if (typeof v === "string") {
    const all = Array.from(v);
    if (i >= all.length) throw new PyError("string index out of range");
    return all[i];
  }
  if (isObj(v)) throw new PyError(String(i));          // a JSON object's keys are never the number
  throw new PyError(`'${pyType(v)}' object is not subscriptable`);
}

/** `key in container`, Python's way. */
function pyIn(key, container) {
  if (isObj(container)) return has(container, key);
  if (Array.isArray(container)) return container.some((x) => pyEqual(x, key));
  if (typeof container === "string") return container.includes(key);
  return false;
}

/** The Mac's signature check: too many or too few arguments, in Python 3.14's words. */
function arity(method, args, required, optional = []) {
  const n = args.length, most = required.length + optional.length;
  if (n > most) {
    throw new PyError(optional.length
      ? `BackendApi.${method}() takes from ${required.length + 1} to ${most + 1} positional arguments but ${n + 1} were given`
      : `BackendApi.${method}() takes ${most + 1} positional arguments but ${n + 1} were given`);
  }
  if (n < required.length) {
    const miss = required.slice(n).map((a) => `'${a}'`);
    const said = miss.length === 1 ? miss[0] : miss.length === 2 ? `${miss[0]} and ${miss[1]}`
      : `${miss.slice(0, -1).join(", ")}, and ${miss[miss.length - 1]}`;
    throw new PyError(`BackendApi.${method}() missing ${miss.length} required positional argument${miss.length > 1 ? "s" : ""}: ${said}`);
  }
}

// ── credits.apply and record.change_credits ──────────────────────────────────

const ROLE = /^[A-Za-z][A-Za-z /&'.-]{0,39}$/;
const MAX_PEOPLE = 24;
/** credits._clean — `str(name or "")`, NFC, Python's spaces, 120 letters. */
const cleanName = (name) => Array.from(squash(pyStr(or(name, "")).normalize("NFC"))).slice(0, 120).join("");
const sameName = (a, b) => casefold(cleanName(a)) === casefold(cleanName(b));

/** [the new list, a refusal in his words or ""] — credits.apply. */
export function applyCredit(list, edit) {
  const credits = creditTidy(list);
  const who = cleanName(edit.person);
  if (has(edit, "add")) {
    const role = cleanName(edit.add);
    if (!ROLE.test(role)) return [credits, "That isn't a credit."];
    if (!who) return [credits, "Pick a person."];
    const now = creditPeople(credits, role);
    if (now.some((p) => sameName(who, p))) return [credits, `${who} is already credited as ${role}.`];
    if (now.length >= MAX_PEOPLE) return [credits, `${role} can't take more people.`];
    return [withPeople(credits, role, [...now, who]), ""];
  }
  if (has(edit, "remove")) {
    const role = edit.remove;
    const now = creditPeople(credits, role);
    if (!now.some((p) => sameName(who, p))) return [credits, `${who} was already taken off.`];
    return [withPeople(credits, role, now.filter((p) => !sameName(who, p))), ""];
  }
  if (has(edit, "move")) {
    const role = edit.move;
    const now = creditPeople(credits, role);
    const at = now.findIndex((p) => sameName(who, p));
    if (at < 0) return [credits, `${who} isn't credited as ${pyStr(role)}.`];
    const by = truthy(edit.by) ? pyInt(edit.by) : 0;
    const to = Math.max(0, Math.min(now.length - 1, at + (by > 0 ? 1 : -1)));
    const [moved] = now.splice(at, 1);
    now.splice(to, 0, moved);
    return [withPeople(credits, role, now), ""];
  }
  if (has(edit, "set")) {
    const role = cleanName(edit.set);
    if (!ROLE.test(role)) return [credits, "That isn't a credit."];
    return [withPeople(credits, role, pyIter(or(edit.people, [])).map(cleanName)), ""];
  }
  return [credits, "Nothing to change."];
}

/** {field: [value, base]} → the door's {field: {value, base}}. */
const asChanges = (plan) => Object.fromEntries(Object.entries(plan).map(([f, [value, base]]) => [f, { value, base: truthy(base) ? pyInt(base) : 0 }]));

/** record.change_credits: read, apply, write; on a clash read again and redo. */
export async function changeCredits(page, edit, deps) {
  for (let i = 0; i < 3; i++) {
    const now = { ...(await deps.readFacts(page)) };
    if (truthy(now.trouble)) return { ok: false, why: now.trouble };
    delete now.offline;
    const before = creditsOf(now);
    const [after, why] = applyCredit(before, edit);
    if (why) return { ok: false, why };
    if (pyEqual(after, before) && pyIn("value", or(now.credits, {}))) return { ok: true, credits: after };
    const plan = creditsPlan(now, after);
    if (!Object.keys(plan).length) return { ok: true, credits: after };
    const got = await deps.writeFacts(page, asChanges(plan), BY);
    if (got.status === 409 && "conflicts" in got) continue;
    if (got.status !== 200) return { ok: false, why: got.problem || `the hub answered ${got.status}` };
    const facts = got.facts || {};
    return { ok: true, credits: creditsOf(facts), facts, changed: sorted(Object.keys(plan)) };
  }
  return { ok: false, why: "The credits kept changing. Try again." };
}

// ── links: record.custom_links, link_title, links_plan, change_links ─────────

const WEB = new RegExp(`^https?://[^${WS}<>"']+$`, "iu");
// "watch" (2026-10-15): a Released project's Vimeo and other links.
const SLOT = /^(drive|website|film|deck|doc|watch|shoot:[0-9a-f]{32}:spec)$/;

/** record.custom_links */
export function customLinks(facts) {
  const one = or((facts || {}).links, {});
  const value = isObj(one) ? one.value : null;
  const items = isObj(value) ? value.custom : null;
  return pyIter(or(items, [])).filter((i) => isObj(i) && truthy(i.url));
}

/** urllib.parse.urlsplit's netloc and path, for an address that already
 * passed the web-address rule (so no spaces, quotes or angle brackets). */
function urlsplit(url) {
  let rest = url;
  const colon = rest.indexOf(":");
  if (colon > 0 && /^[A-Za-z][A-Za-z0-9+.-]*$/.test(rest.slice(0, colon))) rest = rest.slice(colon + 1);
  let netloc = "";
  if (rest.startsWith("//")) {
    const ends = ["/", "?", "#"].map((c) => rest.indexOf(c, 2)).filter((i) => i >= 0);
    const end = ends.length ? Math.min(...ends) : rest.length;
    netloc = rest.slice(2, end);
    rest = rest.slice(end);
    if (netloc.includes("[") !== netloc.includes("]")) throw new PyError("Invalid IPv6 URL");
  }
  rest = rest.split("#")[0].split("?")[0];
  return { netloc, path: rest };
}

/** urllib.parse.unquote — each run of plain ASCII decoded as UTF-8, a bad
 * byte becoming "�". */
function unquote(s) {
  if (!s.includes("%")) return s;
  return s.replace(/[\x00-\x7f]+/g, (run) => {
    if (!run.includes("%")) return run;
    const bytes = [];
    for (let i = 0; i < run.length; i++) {
      const hex = run.slice(i + 1, i + 3);
      if (run[i] === "%" && /^[0-9a-fA-F]{2}$/.test(hex)) { bytes.push(parseInt(hex, 16)); i += 2; } else bytes.push(run.charCodeAt(i));
    }
    return new TextDecoder("utf-8", { ignoreBOM: true }).decode(new Uint8Array(bytes));
  });
}

/** record.link_title — a name for a pasted address when he gave none: the
 * site and the last part of the path ("docs.google.com · Call Sheet"). */
export function linkTitle(url) {
  const u = urlsplit(url);
  const host = u.netloc.startsWith("www.") ? u.netloc.slice(4) : u.netloc;
  const tail = unquote(u.path || "").split("/").filter(Boolean);
  let last = tail.length ? tail[tail.length - 1] : "";
  if (host.endsWith("notion.so") || host.endsWith("notion.site") || host.endsWith("notion.com")) {
    last = pyStrip(last.replace(/-?[0-9a-f]{32}(?=\n?$)/, "").replace(/-/g, " "));
  }
  if (Array.from(last).length > 40 || /^[\p{L}\p{N}_-]{20,}$/u.test(last) || ["edit", "view", "d", "file"].includes(last)) last = "";
  return last ? `${host} · ${last}` : host;
}

/** record.links_plan — [the links fact's new value, its base, a refusal or ""].
 * `stamp` is {id, at} for a link added. */
export function linksPlan(facts, { add = null, remove = "" } = {}, stamp = {}) {
  const one = or((facts || {}).links, {});
  const base = isObj(one) ? (truthy(one.v) ? pyInt(one.v) : 0) : 0;
  const value = isObj(one) && isObj(one.value) ? { ...one.value } : {};
  let items = customLinks(facts);
  if (add !== null) {
    const url = pyStrip(pyStr(or(add.url, ""))), slot = pyStrip(pyStr(or(add.slot, "")));
    if (!WEB.test(url)) return [null, base, "That isn't a web address (https://…)."];
    if (!SLOT.test(slot)) return [null, base, `No place called “${slot}”.`];
    if (items.some((i) => pyEqual(i.url ?? null, url) && pyEqual(i.slot ?? null, slot))) return [null, base, "That link is already there."];
    const title = Array.from(squash(pyStr(or(add.title, "")))).slice(0, 120).join("") || linkTitle(url);
    items = [...items, { id: stamp.id, slot, url, title, at: stamp.at, by: BY }];
  }
  if (truthy(remove)) {
    if (!items.some((i) => i.id === remove)) return [null, base, "That link was already removed."];
    items = items.filter((i) => i.id !== remove);
  }
  value.custom = items;
  return [value, base, ""];
}

/** record.change_links — from the facts as they are now; on a clash read
 * again and redo. */
export async function changeLinks(page, plan, deps) {
  for (let i = 0; i < 3; i++) {
    const now = await deps.readFacts(page);
    if (truthy(now.trouble) || truthy(now.offline)) {
      return { ok: false, why: truthy(now.offline) ? "Offline. Try again when connected." : now.trouble };
    }
    const [value, base, why] = linksPlan(now, plan, deps.stamp());
    if (why) return { ok: false, why };
    const got = await deps.writeFacts(page, { links: { value, base } }, BY);
    if (got.status === 409 && "conflicts" in got) continue;
    if (got.status !== 200) return { ok: false, why: got.problem || `the hub answered ${got.status}` };
    return { ok: true, links: customLinks(got.facts || {}) };
  }
  return { ok: false, why: "The links kept changing. Try again." };
}

// ── backend.page_title: a pasted page's own title ────────────────────────────

const CHARREF = /&(#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\t\n\f <&#;]{1,32};?)/gu;
const invalidCodepoint = (n) => INVALID_CODEPOINTS.some(([a, b]) => n >= a && n <= b);

/** html.unescape */
export function unescape(s) {
  if (!s.includes("&")) return s;
  return s.replace(CHARREF, (_, ref) => {
    if (ref[0] === "#") {
      const hex = ref[1] === "x" || ref[1] === "X";
      const digits = ref.slice(hex ? 2 : 1).replace(/;$/, "");
      const big = BigInt(hex ? `0x${digits}` : digits);
      const num = big > 0x10ffffn ? Infinity : Number(big);
      if (has(INVALID_CHARREFS, String(num))) return INVALID_CHARREFS[String(num)];
      if ((num >= 0xd800 && num <= 0xdfff) || num > 0x10ffff) return "�";
      if (invalidCodepoint(num)) return "";
      return String.fromCodePoint(num);
    }
    if (has(HTML5, ref)) return HTML5[ref];
    const letters = Array.from(ref);
    for (let x = letters.length - 1; x > 1; x--) {
      const name = letters.slice(0, x).join("");
      if (has(HTML5, name)) return HTML5[name] + letters.slice(x).join("");
    }
    return `&${ref}`;
  });
}

const OG = /<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)/iu;
const TITLE = /<title[^>]*>([\s\S]*?)<\/title>/iu;
const TAIL = new RegExp(`[${WS}]+[-–|·][${WS}]+(Google (Docs|Sheets|Slides|Drive)|YouTube|Vimeo|Notion|Dropbox|Frame\\.io|Box)$`, "iu");
const JUNK = /sign[ -]?in|log[ -]?in|access denied|not found|^error|^untitled$|request access|^403|^404/iu;
const HEAD_BYTES = 200_000;

/** The title the Mac reads from a page's first 200 KB, or "". */
export function titleIn(head) {
  const found = OG.exec(head) || TITLE.exec(head);
  if (!found) return "";
  const title = pyStrip(squash(unescape(found[1])).replace(TAIL, ""));
  if (!title || Array.from(title).length > 120 || JUNK.test(title)) return "";
  return title;
}

async function firstBytes(res, limit) {
  if (!res.body) return new Uint8Array(0);
  const reader = res.body.getReader();
  const parts = [];
  let size = 0;
  while (size < limit) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value);
    size += value.length;
  }
  try { await reader.cancel(); } catch { /* already done */ }
  const out = new Uint8Array(Math.min(size, limit));
  let at = 0;
  for (const p of parts) {
    if (at >= out.length) break;
    const take = p.subarray(0, out.length - at);
    out.set(take, at);
    at += take.length;
  }
  return out;
}

/**
 * backend.page_title — a pasted link left unnamed takes the page's own title:
 * its og:title, else its <title>, without a site's " - Google Docs" tail; a
 * sign-in wall, an error or nothing at all is "". `fetchFn` is the checks'.
 */
export async function pageTitle(url, fetchFn = fetch) {
  let head;
  try {
    // urllib.request.Request(url): str(url), stripped, unwrapped (<…>, URL:)
    let u = pyStrip(pyStr(url));
    if (u.startsWith("<") && u.endsWith(">")) u = pyStrip(u.slice(1, -1));
    if (u.startsWith("URL:")) u = pyStrip(u.slice(4));
    if (!/^https?:\/\//i.test(u)) return "";
    // http.client sends the address as it is: a space or control character,
    // or a letter that is not ASCII in the path, and it never leaves the Mac.
    const target = u.replace(/#.*$/s, "");
    if (/[\x00-\x20\x7f]/.test(target)) return "";
    if (/[^\x00-\x7f]/.test(target.replace(/^https?:\/\/[^/?]*/i, ""))) return "";
    const res = await fetchFn(target, {
      headers: { "User-Agent": "Mozilla/5.0 (Macintosh) ProjectsConsole/1.0", Accept: "text/html" },
      redirect: "follow",
      signal: AbortSignal.timeout(4000),
    });
    if (res.status < 200 || res.status > 299) return "";
    if (!(res.headers.get("content-type") || "html").includes("html")) return "";
    head = new TextDecoder("utf-8", { ignoreBOM: true }).decode(await firstBytes(res, HEAD_BYTES));
  } catch {
    return "";
  }
  return titleIn(head);
}

// ── backend._patch_look and engine.notion_icon_svg ───────────────────────────

const ICON_URL = /^https:\/\/www\.notion\.so\/icons\/([a-z0-9_-]+)_([a-z]+)\.svg$/iu;

/** notionlink.icon_parts — [name, colour] of a Notion built-in icon, or null. */
export function iconParts(value) {
  const m = ICON_URL.exec(pyStrip(pyStr(or(value, ""))));
  return m ? [m[1].toLowerCase(), m[2].toLowerCase()] : null;
}

/** engine.notion_icon_svg — one built-in icon's drawing, or null. */
export async function iconSvg(name, color, fetchFn = fetch) {
  if (!name || !color) return null;
  try {
    const res = await fetchFn(`https://www.notion.so/icons/${name}_${color}.svg`, { signal: AbortSignal.timeout(10000) });
    if (res.status !== 200) return null;
    return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(await res.arrayBuffer());
  } catch {
    return null;
  }
}

/** What the screen needs to redraw the header tile — `_patch_look`'s answer. */
async function lookOf(parsed, deps) {
  const look = {};
  if (has(parsed, "color")) look.color = pyStr(or(parsed.color[0], ""));
  const icon = has(parsed, "icon") ? iconParts(parsed.icon[0]) : null;
  if (icon) {
    look.icon_name = icon[0];
    look.icon_svg = (await deps.iconSvg(icon[0], icon[1])) || "";
  }
  return look;
}

// ── backend._crew_company_later: a Client or Agency becomes a Crew company ───

/** crewrows._clean — `str(text or "")`, NFC, Python's spaces, 200 letters. */
const crewClean = (text) => Array.from(squash(pyStr(or(text, "")).normalize("NFC"))).slice(0, 200).join("");

/** crewrows.icon_for, kept with the Crew rows it dresses (cloud.js). */
export { iconFor };

/**
 * The credit a new person or company brings — the edit `backend.crew_new` /
 * `company_new` hand `set_project_credits`, or null when there is none:
 * the person's name as `str(name or "").strip()`, the company's as
 * `crewrows._clean(name).replace(",", " ")`, a credit Python calls true.
 */
export function newCredit(method, item) {
  if (!isObj(item) || !truthy(item.credit)) return null;
  return method === "crew_new"
    ? { add: item.credit, person: pyStrip(pyStr(or(item.name, ""))) }
    : { add: "Production Company", person: crewClean(item.name).replace(/,/g, " ") };
}

/**
 * A company typed into the record that Crew may not know yet: its Vendor row
 * (name only — nothing guessed). Anything already there, or close to it, is
 * left alone. Answers what it did, for the log.
 */
export async function crewCompany(n, company) {
  const rows = await allCrew(n);
  const options = (await crewOptions(n)).Company || [];
  const want = { name: crewClean(company).replace(/,/g, " ") };
  if (!want.name || duplicates(want, rows, options).length) return { made: false, name: want.name };
  const [props, why] = companyProps(want, "");
  if (why) return { made: false, name: want.name, why };
  const page = await n.post("pages", { parent: { type: "data_source_id", data_source_id: CREW }, icon: iconFor(props), properties: props });
  const back = await n.get(`pages/${page.id}`);
  const off = readsBack(back, props);
  return off ? { made: false, name: want.name, why: `Notion kept it, but ${off} didn't read back as written.` }
    : { made: true, name: want.name, id: bareId(page.id) };
}

// ── the two looks a save asks for now ────────────────────────────────────────

/** notionsync.kick — the Notion link looks at this project now, when the
 * server is the one keeping Notion in step (never before the Mac's memory is
 * here, as the minute's own rule). What it met for him is sent to the phone,
 * as the minute sends it. */
export async function kickNotion(env, page) {
  const { syncOwner } = await import("./studio.js");
  if ((await syncOwner(env)).owner !== "hub") return { skipped: "the Mac keeps Notion in step" };
  if (!(await env.BUCKET.head("s/notion-link.json"))) return { skipped: "waiting for the Mac's memory" };
  const { syncTick } = await import("./notionsync.js");
  const got = await syncTick(env, { only: page });
  if (Array.isArray(got.notify) && got.notify.length) {
    const { tellConflicts } = await import("./push.js");
    got.pushed = await tellConflicts(env, got.notify);
  }
  return got;
}

/** filmfacts.kick — the film is told now, when the server writes the films. */
export async function kickFilm(env, page) {
  const { filmsOwner, mirrorOne } = await import("./filmfacts.js");
  if ((await filmsOwner(env)).owner !== "hub") return { skipped: "the Mac writes the films" };
  const { mirrorRecord } = await import("./filmdoor.js");
  return await mirrorOne(env, page, undefined, mirrorRecord);
}

/** The history door's list: every accepted change, newest first, ≤ 100. */
async function historyOf(env, page) {
  const keys = [];
  let cursor;
  do {
    const got = await env.BUCKET.list({ prefix: `r/${page}/history/`, cursor, limit: 1000 });
    for (const o of got.objects || []) keys.push(o.key);
    cursor = got.truncated ? got.cursor : undefined;
  } while (cursor);
  const newest = keys.sort().reverse().slice(0, 100);
  return (await Promise.all(newest.map(async (key) => {
    const got = await env.BUCKET.get(key);
    try { return got ? await got.json() : null; } catch { return null; }
  }))).filter(Boolean);
}

/** What the asks reach, as the worker has it. The checks hand in their own. */
export function liveDeps(env, ctx = null) {
  return {
    // beside the reply, never before it (the Notion steps): the minute's look does them if this cannot
    defer: ctx && typeof ctx.waitUntil === "function" ? (work) => ctx.waitUntil(work) : null,
    readFacts: async (page) => (await import("./facts.js")).factsOfRecord(env, page),
    writeFacts: async (page, changes, by) => (await import("./facts.js")).writeFacts(env, page, changes, by),
    history: (page) => historyOf(env, page),
    owner: async () => (await (await import("./studio.js")).syncOwner(env)).owner,
    conflicts: async () => (await (await import("./notionsync.js")).conflictsList(env)).filter(isObj),
    settle: async (id, keep) => (await import("./notionsync.js")).settleConflict(env, id, keep),
    templates: () => savedTemplates(env),
    patchHidden: (page, ptype, saved) => patchHidden(env, page, ptype, saved),
    kickNotion: (page) => kickNotion(env, page),
    kickFilm: (page) => kickFilm(env, page),
    crewCompany: (n, company) => crewCompany(n, company),
    pageTitle: (url) => pageTitle(url),
    iconSvg: (name, color) => iconSvg(name, color),
    stamp: () => ({ id: crypto.randomUUID().replace(/-/g, "").slice(0, 8), at: new Date().toISOString().replace(/\.\d+Z$/, "Z") }),
    log: (said) => console.log(said),
  };
}

/** An after-save step: tried, and only logged when it fails (the Mac's threads).
 * `slow` is a step that goes to Notion: the save never waits on Notion (his
 * rule, 2026-10-15), so where the reply can go first it does, and the step
 * runs beside it. */
async function after(deps, what, fn, slow = false) {
  const run = async () => {
    try {
      const got = await fn();
      if (got && (got.skipped || got.trouble || got.why)) deps.log(`facts: ${what}: ${got.skipped || got.trouble || got.why}`);
    } catch (e) {
      deps.log(`facts: ${what} failed: ${String((e && e.message) || e)}`);
    }
  };
  if (slow && deps.defer) { deps.defer(run()); return; }
  await run();
}

/** backend._layout — what the project shows, or null. */
function layoutOf(row, facts, saved) {
  try {
    return resolveLayout(facts || {}, projectType(row, facts || {}), saved);
  } catch {
    return null;
  }
}

/** backend._credits */
function creditsSafe(facts) {
  try { return creditsOf(facts || {}); } catch { return []; }
}

/** The row for the name the phone shows; `_project_row` matches names exactly. */
async function rowOf(n, name) {
  return typeof name === "string" && name ? await projectRow(n, name) : null;
}

// ── the seven asks, as backend.py has them ───────────────────────────────────

export const FACTS_ASKS = {
  /** backend.project_facts — the facts, what the project shows, its credits. */
  async project_facts(env, n, args, deps) {
    arity("project_facts", args, ["name"]);
    const row = await rowOf(n, args[0]);
    if (!row) return { ok: false, why: NO_ROW, facts: {} };
    if ((await deps.owner()) !== "hub") throw new Handoff("the Mac holds the Notion link's questions");
    const facts = { ...(await deps.readFacts(bareId(row.id))) };
    let offline = false;
    if (has(facts, "offline")) { offline = truthy(facts.offline); delete facts.offline; }
    const saved = await deps.templates();
    const conflicts = (await deps.conflicts()).length;
    return { ok: true, facts, offline, layout: layoutOf(row, facts, saved), credits: creditsSafe(facts), waiting: 0, conflicts };
  },

  /** backend.set_project_facts — {field: [value, the version it was read at]}. */
  async set_project_facts(env, n, args, deps) {
    arity("set_project_facts", args, ["name", "changes"]);
    const [name, changes] = args;
    const row = await rowOf(n, name);
    if (!row) return { ok: false, why: NO_ROW };
    if (!isObj(changes) || !Object.keys(changes).length) return { ok: false, why: "Nothing to save." };
    const parsed = {};
    try {
      for (const [f, vb] of Object.entries(changes)) {
        const value = pyIndex(vb, 0);
        const base = pyIndex(vb, 1);
        parsed[f] = [value, truthy(base) ? pyInt(base) : 0];
      }
    } catch (e) {
      if (e instanceof PyError) return { ok: false, why: "Each change is [value, the version it was read at]." };
      throw e;
    }
    const page = bareId(row.id);
    const body = Object.fromEntries(Object.entries(parsed).map(([f, [value, base]]) => [f, { value, base }]));
    const got = await deps.writeFacts(page, body, BY);
    if (got.status === 409 && "conflicts" in got) return { ok: false, conflicts: got.conflicts };
    if (got.status !== 200) return { ok: false, why: got.problem || `the hub answered ${got.status}` };
    const facts = got.facts || {};
    const saved = await deps.templates();
    const fields = Object.keys(parsed);
    // The readout's hidden line first: the film's look reads it.
    if (fields.some((f) => READOUT_FACTS.includes(f))) {
      await after(deps, "readout", () => deps.patchHidden(page, projectType(row, facts), saved));
    }
    if (fields.some((f) => LINK_FIELDS.has(f))) await after(deps, "notion link", () => deps.kickNotion(page), true);
    if (fields.some((f) => FILM_FACTS.has(f))) await after(deps, "film facts", () => deps.kickFilm(page, name));
    for (const field of ["client", "agency"]) {
      if (has(parsed, field) && pyStrip(pyStr(or(parsed[field][0], "")))) {
        await after(deps, "crew company", () => deps.crewCompany(n, parsed[field][0]), true);
      }
    }
    const out = { ok: true, facts, layout: layoutOf(row, facts, saved) };
    if (has(parsed, "icon") || has(parsed, "color")) out.look = await lookOf(parsed, deps);
    return out;
  },

  /** backend.settle_facts — keep mine or theirs, for one Notion-link question. */
  async settle_facts(env, n, args, deps) {
    arity("settle_facts", args, ["conflict_id", "keep"]);
    const [id, keep] = args;
    if ((await deps.owner()) !== "hub") throw new Handoff("the Mac holds the Notion link's questions");
    if (!(await deps.conflicts()).some((c) => isObj(c) && c.id === id)) return { ok: false, why: "that change was already settled" };
    if (keep !== "mine" && keep !== "theirs") return { ok: false, why: `keep mine or theirs, not ${pyRepr(keep)}` };
    const got = await deps.settle(id, keep);
    if (truthy(got.trouble) && !("conflicts" in got)) return { ok: false, why: got.trouble };
    const kept = Object.fromEntries(Object.entries(got).filter(([k]) => ["settled", "conflicts", "trouble"].includes(k)));
    if (truthy(kept.trouble)) return { ok: false, why: kept.trouble };
    if ("conflicts" in kept) return { ok: false, conflicts: kept.conflicts };
    return { ok: true, ...kept };
  },

  /** backend.project_history — every accepted change, newest first. */
  async project_history(env, n, args, deps) {
    arity("project_history", args, ["name"]);
    const row = await rowOf(n, args[0]);
    if (!row) return { ok: false, why: NO_ROW, history: [] };
    try {
      return { ok: true, history: await deps.history(bareId(row.id)) };
    } catch (e) {
      return { ok: false, why: String((e && e.message) || e), history: [] };
    }
  },

  /** backend.set_project_credits — {add|remove|move: role, person[, by]} or {set, people}. */
  async set_project_credits(env, n, args, deps) {
    arity("set_project_credits", args, ["name", "edit"]);
    const [name, edit] = args;
    const row = await rowOf(n, name);
    if (!row) return { ok: false, why: NO_ROW };
    if (!isObj(edit)) return { ok: false, why: "Nothing to change." };
    const page = bareId(row.id);
    let got;
    try {
      got = await changeCredits(page, edit, deps);
    } catch (e) {
      got = { ok: false, why: String((e && e.message) || e) };
    }
    if (got.ok && truthy(got.changed) && !got.queued) {
      if (got.changed.some((f) => LINK_FIELDS.has(f))) await after(deps, "notion link", () => deps.kickNotion(page), true);
      await after(deps, "film facts", () => deps.kickFilm(page, name));
    }
    if (got.ok && truthy(got.facts)) got.layout = layoutOf(row, got.facts, await deps.templates());
    return got;
  },

  /** backend.add_custom_link — a pasted address kept for one place. */
  async add_custom_link(env, n, args, deps) {
    arity("add_custom_link", args, ["name", "slot", "url"], ["title"]);
    const [name, slot, url] = args;
    let title = args.length > 3 ? args[3] : "";
    const row = await rowOf(n, name);
    if (!row) return { ok: false, why: NO_ROW };
    if (!pyStrip(pyStr(or(title, "")))) title = await deps.pageTitle(url);
    return await changeLinks(bareId(row.id), { add: { slot, url, title } }, deps);
  },

  /** backend.remove_custom_link */
  async remove_custom_link(env, n, args, deps) {
    arity("remove_custom_link", args, ["name", "link_id"]);
    const [name, linkId] = args;
    const row = await rowOf(n, name);
    if (!row) return { ok: false, why: NO_ROW };
    return await changeLinks(bareId(row.id), { remove: pyStr(or(linkId, "")) }, deps);
  },
};

/** One of the seven, answered here. Throws `Handoff` for the Mac's, and a
 * refusal the Mac's Python would raise as that error's words. */
export async function factsAsk(env, n, method, args, deps = null, ctx = null) {
  return await FACTS_ASKS[method](env, n, Array.isArray(args) ? args : [], deps || liveDeps(env, ctx));
}
