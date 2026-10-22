/**
 * **Stage 5 step 6, group "portal": the portal's sidebar and Library, edited
 * from the console, answered by the server** (2026-10-15).
 *
 * The Mac's methods (`backend.py`, "the portal's sidebar, edited from the
 * Portal tab", "the Library's categories", `portal_remove`, `portal_preview`)
 * were thin already: each found the project's portal (`_relay_of`), then
 * handed the hub's own door its fields — `POST /console/<film>/act/…` as a
 * form, `PUT /console/<film>/library|shelves|access` as JSON — and turned the
 * door's answer into the screen's. Every rule (what a name may be, where a
 * page goes, who may be removed) is the door's. So the port is the same
 * three steps, rule for rule, with the door called in-process:
 *
 *   1. the same pre-checks, in the same order and words ("Nothing to save.");
 *   2. the portal found from the project's record (`relayOfPage`, as the
 *      ported Share asks do), "no Notion row for this project" when Notion
 *      has no row (the Mac's router then does it itself, as for an older
 *      database's project);
 *   3. the same body or form, and the Mac's own mapping of the answer
 *      (`_door` keeps `status`; `_act` keeps the sidebar a refusal carries).
 *
 * Python's `str()`, truthiness and `.strip()` are mirrored (`pyStr`, `truthy`)
 * so an odd argument is sent as the Mac would send it.
 *
 * **What stays the Mac's:** Add on the portal with a FILE (the file is on the
 * Mac's disk; answered null, so the Mac does it), and the preview WINDOW
 * (`open_portal_preview`, a window of that Mac). The preview's two addresses
 * (`portal_preview`) are a read answered here, on the spot.
 *
 * Rule: NO static import of cloud.js / studio.js here (they import step6.js,
 * which imports this file): use `await import("./cloud.js")` inside functions.
 */

/** The switch: `s/step6-portal.json` {on, at, by}; door at /console/studio/step6portal. */
export const SWITCH = "step6portal";
/** Every ask this group answers (listed to the Mac and phone only while the switch is on). */
export const METHODS = new Set([
  "portal_order", "portal_add_page", "portal_rename_page", "portal_rename_document",
  "portal_set_icon", "portal_move_to_shelf", "portal_shelves", "portal_remove", "portal_preview",
]);
/** Of those, reads answered on the spot (`POST /console/studio/now`). */
export const NOW = new Set(["portal_preview"]);
/** Asks too slow for the 20 s reply: kept working by the server (later.js). */
export const LATER_WRITES = new Set([]);
export const LATER_READS = new Set([]);

const PORTAL_HOST = "https://your-domain.example";
const DOOR_HOST = "https://mcp.your-domain.example";
const PAGE = /^[0-9a-f]{32}$/;
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();
const isObj = (v) => Boolean(v) && typeof v === "object" && !Array.isArray(v);

// ── Python, as the Mac's code reads its arguments ───────────────────────────

/** Python's truthiness. */
export function truthy(v) {
  if (v == null || v === false || v === 0 || v === "") return false;
  if (Array.isArray(v)) return v.length > 0;
  if (typeof v === "object") return Object.keys(v).length > 0;
  return true;
}

function pyRepr(v) {
  if (typeof v !== "string") return pyStr(v);
  const q = v.includes("'") && !v.includes('"') ? '"' : "'";
  const body = v.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/\r/g, "\\r").replace(/\t/g, "\\t");
  return q + (q === "'" ? body.replace(/'/g, "\\'") : body) + q;
}

/** Python's `str()` of a JSON value. */
export function pyStr(v) {
  if (v === null || v === undefined) return "None";
  if (v === true) return "True";
  if (v === false) return "False";
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : String(v);
  if (Array.isArray(v)) return `[${v.map(pyRepr).join(", ")}]`;
  if (typeof v === "object") return `{${Object.entries(v).map(([k, x]) => `${pyRepr(k)}: ${pyRepr(x)}`).join(", ")}}`;
  return String(v);
}

/** Python's `str.strip()` (whitespace only). */
const PY_SPACE = "\\t\\n\\v\\f\\r\\u001c-\\u001f \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const PY_EDGES = new RegExp(`^[${PY_SPACE}]+|[${PY_SPACE}]+$`, "g");
const strip = (s) => String(s).replace(PY_EDGES, "");

/** `str(x or "").strip()` */
const said = (x) => strip(pyStr(truthy(x) ? x : ""));

/** Python's `for k in x` over a JSON value: a list, a string's letters, a dict's keys. */
function pyIter(v) {
  if (Array.isArray(v)) return v;
  if (typeof v === "string") return [...v];
  if (isObj(v)) return Object.keys(v);
  throw new Error(`'${pyType(v)}' object is not iterable`);
}
const pyType = (v) => (v == null ? "NoneType" : v === true || v === false ? "bool" : typeof v === "number" ? (Number.isInteger(v) ? "int" : "float") : Array.isArray(v) ? "list" : typeof v === "object" ? "dict" : "str");

/** A method called with too few arguments: Python's own TypeError, word for word. */
function needs(method, list, names) {
  const missing = names.filter((_, i) => list.length <= i);
  if (!missing.length) return;
  const quoted = missing.map((m) => `'${m}'`);
  const words = quoted.length === 1 ? quoted[0] : `${quoted.slice(0, -1).join(", ")} and ${quoted[quoted.length - 1]}`;
  throw new Error(`${method}() missing ${missing.length} required positional argument${missing.length === 1 ? "" : "s"}: ${words}`);
}

// ── the door's answer, as the Mac turns it into the screen's ────────────────

/** `backend._door` over `dossier.hub_console_at`: `status` kept, `conflicts` not. */
export function doorAnswer(status, json) {
  if (status >= 400) {
    const problem = isObj(json) ? json.problem : "";
    return { ok: false, why: truthy(problem) ? problem : `the hub answered ${status}`, status };
  }
  return { ok: true, ...(isObj(json) ? json : {}) };
}

/** `backend._act` over `dossier.hub_console_form`: a refusal keeps the sidebar it carries. */
export function actAnswer(status, json) {
  if (status >= 400) {
    const j = isObj(json) ? json : {};
    const why = truthy(j.problem) ? j.problem : truthy(j.why) ? j.why : `the hub answered ${status}`;
    const out = { ok: false, why };
    if ("sidebar" in j) for (const k of ["sidebar", "rows", "icon_choices", "icon_paths"]) if (k in j) out[k] = j[k];
    return out;
  }
  const j = isObj(json) ? json : {};
  return { ...j, ok: "ok" in j ? truthy(j.ok) : true };
}

// ── the actions, each `(list, io)` ───────────────────────────────────────────
// `io.relay(name)` → {relay} | {why} ; `io.door(path, method, body|FormData)`
// → {status, json}; `io.after(name)` after a write the door said yes to.

const NO_PORTAL = "this film has no portal page";

/** `_door`: the portal found, one JSON call, the Mac's answer. */
async function viaDoor(io, name, what, body, method = "PUT") {
  const found = await io.relay(name);
  if (found.why) return { ok: false, why: found.why };
  if (!found.relay) return { ok: false, why: NO_PORTAL };
  const { status, json } = await io.door(`${found.relay}/${what}`, method, body);
  const out = doorAnswer(status, json);
  if (method !== "GET" && status < 400) await io.after(name);
  return out;
}

/** `_act`: the portal found, one form posted on `act/<what>`, the Mac's answer. */
async function viaAct(io, name, what, fields) {
  const found = await io.relay(name);
  if (found.why) return { ok: false, why: found.why };
  if (!found.relay) return { ok: false, why: NO_PORTAL };
  const { status, json } = await io.door(`${found.relay}/act/${what}`, "POST", { form: fields });
  if (status < 400) await io.after(name);
  return actAnswer(status, json);
}

/** `dossier.share_of`, the part the preview reads. */
export function shareOf(row) {
  const links = (Array.isArray(row.links) ? row.links : []).filter(isObj);
  const live = links.filter((l) => !truthy(l.off));
  const first = (live.length ? live : links.length ? links : [null])[0];
  return { count: links.length, on: live.length > 0, address: truthy((first || {}).url) ? first.url : "" };
}

export const ACTIONS = {
  /** The whole sidebar, headings and all: [{name, rows: [page key…]}], in order. */
  async portal_order(list, io) {
    needs("portal_order", list, ["name", "groups"]);
    const [name, groups] = list;
    const fields = [];
    for (const g of pyIter(truthy(groups) ? groups : [])) {
      if (!isObj(g)) throw new Error(`'${pyType(g)}' object has no attribute 'get'`);
      const rows = pyIter(truthy(g.rows) ? g.rows : []).filter(truthy).map((r) => pyStr(r).replace(/,/g, "%2C")).join(",");
      fields.push(["group", `${said(g.name)}\n${rows}`]);
    }
    if (!fields.length) return { ok: false, why: "Nothing to save." };
    return await viaAct(io, name, "order", fields);
  },

  /** Add on the portal: a page, a deck, a board or a link. A file is the Mac's (its disk). */
  async portal_add_page(list, io) {
    needs("portal_add_page", list, ["name", "kind", "title"]);
    const [name, kind, title, url = "", head = ""] = list;
    if (kind === "file") return null;
    const fields = [["type", pyStr(truthy(kind) ? kind : "page")], ["name", said(title)]];
    if (truthy(head)) fields.push(["head", pyStr(head)]);
    if (truthy(url)) fields.push(["url", strip(pyStr(url))]);
    return await viaAct(io, name, "add", fields);
  },

  /** Rename a page of his; its address follows the name, the old one forwards. */
  async portal_rename_page(list, io) {
    needs("portal_rename_page", list, ["name", "at", "title"]);
    const [name, at, title] = list;
    return await viaAct(io, name, pyStr(at), [["rename", said(title)]]);
  },

  /** Rename a pinned file or link (a name, not its address). */
  async portal_rename_document(list, io) {
    needs("portal_rename_document", list, ["name", "doc", "title"]);
    const [name, doc, title] = list;
    return await viaDoor(io, name, "library", { keys: ["doc:" + pyStr(doc)], action: "rename", to: said(title) });
  },

  /** A page's sidebar icon; "" puts the default back. */
  async portal_set_icon(list, io) {
    needs("portal_set_icon", list, ["name", "key", "icon"]);
    const [name, key, icon] = list;
    return await viaDoor(io, name, "library", { keys: [pyStr(key)], action: "icon", to: pyStr(truthy(icon) ? icon : "") });
  },

  /** Move pages (by key) or documents (`doc:<name>`) to a category, by its id. */
  async portal_move_to_shelf(list, io) {
    needs("portal_move_to_shelf", list, ["name", "keys", "shelf"]);
    const [name, keys, shelf] = list;
    const named = typeof keys === "string" ? [keys] : pyIter(keys);
    return await viaDoor(io, name, "library", { keys: named.map(pyStr), action: "shelf", to: pyStr(truthy(shelf) ? shelf : "") });
  },

  /** A Library category: add (title), rename (shelf, title), remove (shelf), move (shelf, to). */
  async portal_shelves(list, io) {
    needs("portal_shelves", list, ["name", "action"]);
    const [name, action, shelf = "", title = "", to = null] = list;
    const body = { action: pyStr(truthy(action) ? action : "") };
    if (truthy(shelf)) body.shelf = pyStr(shelf);
    if (truthy(title)) body.name = strip(pyStr(title));
    if (to !== null && to !== undefined) body.to = to;
    return await viaDoor(io, name, "shelves", body);
  },

  /** Take somebody off the list. Never him; the door refuses that. */
  async portal_remove(list, io) {
    needs("portal_remove", list, ["name", "email"]);
    const [name, email, ifMatch = null] = list;
    const body = { remove: [pyStr(email)] };
    if (ifMatch !== null && ifMatch !== undefined) body.if_match = ifMatch;
    return await viaDoor(io, name, "access", body);
  },

  /** The preview window's two addresses: You (his signed-in view) and Crew (the general link). */
  async portal_preview(list, io) {
    needs("portal_preview", list, ["name"]);
    const [name] = list;
    const found = await io.relay(name);
    if (found.why) return { ok: false, why: found.why };
    if (!found.relay) return { ok: false, why: "No portal" };
    const { status, json } = await io.door(found.relay, "GET", null);
    if (status >= 400) {
      const trouble = truthy(isObj(json) && json.problem) ? json.problem : `the hub answered ${status}`;
      return { ok: false, why: String(trouble).includes("did not answer") ? "Offline" : trouble };
    }
    const row = isObj(json) ? json : {};
    const share = shareOf(row);
    const crew = share.on ? (truthy(share.address) ? share.address : truthy(row.url) ? row.url : "") : "";
    const why = truthy(crew) ? "" : share.count ? "Link off" : "Restricted";
    return { ok: true, name, you: `${PORTAL_HOST}/f/${found.relay}`, crew, crew_why: why };
  },
};

// ── on the server ────────────────────────────────────────────────────────────

/** One call on this worker's own console door, in-process; a form for `act/`. */
export async function workerDoor(env, path, method, body) {
  const { default: worker } = await import("./worker.js");
  const headers = { authorization: `Bearer ${env.CONSOLE_TOKEN}` };
  let payload;
  if (body && Array.isArray(body.form)) {
    payload = new FormData();
    for (const [k, v] of body.form) payload.append(k, v);
  } else if (body != null && method !== "GET") {
    headers["content-type"] = "application/json";
    payload = JSON.stringify(body);
  } else headers["content-type"] = "application/json";
  // The MCP host, as cloudportal.js: the door builds addresses from it.
  const request = new Request(`${DOOR_HOST}/console/${path}`, { method, headers, body: payload });
  const ctx = { waitUntil() {}, passThroughOnException() {} };
  const res = await worker.fetch(request, env, ctx);
  let json = {};
  try { json = await res.json(); } catch { json = {}; }
  return { status: res.status, json };
}

/** The server's io: Notion's row by name, the portal from the record. */
function serverIo(env) {
  const rows = new Map();
  return {
    async relay(name) {
      const { notionOf, projectRow } = await import("./cloud.js");
      const { relayOfPage } = await import("./cloudportal.js");
      const row = await projectRow(notionOf(env), name);
      if (!row) return { why: "no Notion row for this project" };
      rows.set(name, row.id);
      return { relay: await relayOfPage(env, row.id) };
    },
    door: (path, method, body) => workerDoor(env, path, method, body),
    async after(name) {
      const page = rows.get(name);
      if (!page) return;
      try {
        const { liveAfterEdit } = await import("./recordlive.js");
        await liveAfterEdit(env, page);
      } catch (e) {
        console.error("record live:", String((e && e.stack) || e));
      }
    },
  };
}

/** `async (list, env) => result` per method; null hands the ask to the Mac. */
export const ASKS = Object.fromEntries([...METHODS].map((m) => [m, (list, env) => ACTIONS[m](list, serverIo(env))]));

// ── the dry look ─────────────────────────────────────────────────────────────

/**
 * **What the server would do for one project, writing nothing.** The portal
 * it finds, the preview's addresses, the sidebar and Library as they stand,
 * and what each edit would send to keep things exactly as they are (the
 * order re-saved, each page renamed to its own name, each icon and category
 * set to what it is). `door` may only read: anything else throws.
 */
export async function lookOf(env, page, { door = null, relayOf = null } = {}) {
  const key = bare(page);
  if (!PAGE.test(key)) return { ok: false, why: "Say which project: ?id=<page id>." };
  const reads = door || ((path, method, body) => workerDoor(env, path, method, body));
  const sent = [];
  const readOnly = async (path, method, body) => {
    if (method === "GET") return await reads(path, method, body);
    sent.push({ path, method, body: body && body.form ? { form: body.form } : body });
    return { status: 200, json: { ok: true, dry: true } };
  };
  const { relayOfPage } = await import("./cloudportal.js");
  const relay = relayOf ? await relayOf(key) : await relayOfPage(env, key);
  const record = await env.BUCKET.get(`r/${key}/record.json`);
  let title = "";
  if (record) { try { const r = await record.json(); title = String(r.name || r.title || (r.film || {}).title || ""); } catch { /* none */ } }
  const name = title || key;
  const io = { relay: async () => ({ relay }), door: readOnly, after: async () => {} };
  const out = { ok: true, id: key, name, relay, portal: Boolean(relay) };
  out.preview = await ACTIONS.portal_preview([name], io);
  if (!relay) return out;
  const lib = await reads(`${relay}/library`, "GET", null);
  if (lib.status >= 400) return { ...out, library: doorAnswer(lib.status, lib.json) };
  const L = lib.json;
  out.sidebar = (L.sidebar || []).map((g) => ({ name: g.head || "", rows: g.rows || [] }));
  out.shelves = (L.shelves || []).map((s) => ({ id: s.id, name: s.name }));
  out.pages = (L.pages || []).length;
  out.documents = (L.documents || []).length;
  // What each edit would send, as no change at all.
  const would = {};
  const one = async (method, args) => {
    sent.length = 0;
    const answer = await ACTIONS[method](args, io);
    (would[method] = would[method] || []).push({ args: args.slice(1), sends: sent.slice(), answer: answer && answer.dry ? "dry" : answer });
  };
  if (out.sidebar.length) await one("portal_order", [name, out.sidebar]);
  const rows = new Map((L.rows || []).map((r) => [r.at, r]));
  for (const p of (L.pages || []).slice(0, 3)) {
    await one("portal_rename_page", [name, p.at, p.name]);
    await one("portal_set_icon", [name, p.at, (rows.get(p.at) || {}).icon || ""]);
    await one("portal_move_to_shelf", [name, [p.at], p.shelf || ""]);
  }
  for (const d of (L.documents || []).slice(0, 2)) await one("portal_rename_document", [name, d.name, d.name]);
  out.would = would;
  out.writes = 0;
  return out;
}

/** GET /console/studio/step6portal/look?id=<page>: the dry look. */
export async function door(env, rest, method, readBody, ctx, url) {
  if (rest.length === 2 && rest[1] === "look") {
    if (method !== "GET") return Response.json({ problem: "Wrong method." }, { status: 405 });
    const id = (url && url.searchParams.get("id")) || "";
    const got = await lookOf(env, id);
    return Response.json(got, { status: got.ok ? 200 : 400 });
  }
  return null;
}
