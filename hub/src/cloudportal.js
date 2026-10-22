/**
 * **The portal's switches, answered by the server** (2026-10-10, stage 1 of
 * Projects Console without the Mac). `backend.py`'s portal methods were thin
 * already: each found the project's page on the hub (`_relay_of`) and called
 * this worker's own console door. The only reason they needed the Mac was
 * that first step — the film's relay id was read off the film on the Mac's
 * disk. The project's record names it too (`film.relay`, record.py), so the
 * server finds it there, and calls its own door in-process.
 *
 * `refresh_portal` is the hub's own Refresh from Notion (`notion.js`
 * `refreshFilm`), not `hub/refresh.py`: the words, documents, shoots and crew
 * the same; the link covers, which need a browser, still the Mac's for now.
 */

import { portalOf } from "./films.js";
import { refreshFilm } from "./notion.js";
import { keyOfPage } from "./projectid.js";

const PAGE = /^[0-9a-f]{32}$/;
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

/** The portal's id for a project page: its film's relay, or the page itself
 * when it is a portal with no film. "" when it has neither — `_relay_of`. */
export async function relayOfPage(env, page) {
  if (!PAGE.test(bare(page))) return "";
  // A minted project's Notion page stands for its ID (projectid.js): its
  // portal, when it has one with no film, lives under that ID.
  const key = await keyOfPage(env, page);
  const got = await env.BUCKET.get(`r/${key}/record.json`);
  if (got) {
    try {
      const relay = bare(((await got.json()).film || {}).relay);
      if (PAGE.test(relay)) return relay;
    } catch { /* an unreadable record names no film */ }
  }
  return (await portalOf(env, key)) ? key : "";
}

/** One call on this worker's own console door, as the Mac made it. */
export async function door(env, path, method, body) {
  const { default: worker } = await import("./worker.js");
  // **The real host, not a made-up one.** The door builds the addresses it
  // hands back (the friendly share link) from the host it was asked on; asked
  // on `hub.internal` it said `share.hub.internal`, and a record written from
  // that read wrong for a day (2026-10-11). The MCP host is the one nothing
  // stands in front of.
  const request = new Request(`https://mcp.your-domain.example/console/${path}`, {
    method,
    headers: { authorization: `Bearer ${env.CONSOLE_TOKEN}`, "content-type": "application/json" },
    body: body == null || method === "GET" ? undefined : JSON.stringify(body),
  });
  const ctx = { waitUntil() {}, passThroughOnException() {} };
  const res = await worker.fetch(request, env, ctx);
  let json = {};
  try { json = await res.json(); } catch { json = {}; }
  return { status: res.status, json };
}

/** backend._door: {ok: true, …answer} or {ok: false, why[, status]}. */
async function portalDoor(env, page, what, body, method = "PUT") {
  const relay = await relayOfPage(env, page);
  if (!relay) return { ok: false, why: "this film has no portal page" };
  const { status, json } = await door(env, `${relay}/${what}`, method, body);
  if (status >= 400) {
    const out = { ok: false, why: json.problem || json.error || `the hub answered ${status}` };
    out.status = status;
    return out;
  }
  return { ok: true, ...json };
}

/** What Viewers See for one project, by its page — the films shelf's count
 * (onelist.js). The same door `portal_viewers` asks. */
export async function portalViewersOf(env, page) {
  const got = await portalDoor(env, page, "viewers", null, "GET");
  return got.ok ? got : null;
}

/** dossier.mint_link — a new general link: {key, hash}. */
export async function mintLink() {
  const bytes = crypto.getRandomValues(new Uint8Array(24));
  const key = btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(key));
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return { key, hash };
}

/** dossier.password_hashes — a link's password as the hub stores it:
 * {salt, pass}, never the word; the salt 32 hex characters. */
export async function passwordHashes(word, salt = null) {
  const s = salt || [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s + word));
  return { salt: s, pass: [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("") };
}

/** dossier.OWNERS — the hub keeps him on every list as an editor. */
const OWNERS = ["owner@example.com", "owner@your-domain.example"];

/** dossier.mark_owners — each person, with `owner` when the address is his. */
export function markOwners(people) {
  const out = [];
  for (const one of Array.isArray(people) ? people : []) {
    if (one && typeof one === "object" && !Array.isArray(one)) {
      out.push(OWNERS.includes(String(one.email || "").toLowerCase()) ? { ...one, owner: true } : { ...one });
    }
  }
  return out;
}

/** backend.portal_access — one change to who may open it, `if_match` when given. */
async function portalAccess(env, page, change, ifMatch) {
  const body = { ...(change || {}) };
  if (ifMatch != null) body.if_match = ifMatch;
  return await portalDoor(env, page, "access", body);
}

async function refreshPortal(env, page) {
  const relay = await relayOfPage(env, page);
  if (!relay) return { ok: false, why: "no Shotlister film" };
  const got = await refreshFilm(env, relay);
  const said = (got.lines || []).filter((l) => String(l).trim());
  return { ok: Boolean(got.ok), said: said.slice(-6) };
}

/**
 * The methods, each `(n, args, env, row)` where `row` is the project's Notion
 * row as cloud.js found it by name (null when there is none).
 */
export const PORTAL_METHODS = {
  async portal_down(n, [, down], env, row) {
    return await portalDoor(env, row.id, "down", { down: Boolean(down), by: "console" });
  },

  async portal_link(n, [, off, hash], env, row) {
    const body = { off: Boolean(off) };
    if (hash) body.hash = hash;
    return await portalDoor(env, row.id, "link", body);
  },

  async portal_visible(n, [, sections], env, row) {
    return await portalDoor(env, row.id, "visible", { sections: (sections || []).map(String) });
  },

  /** General Access; turning it on with no link yet makes one, as Copy Link does. */
  async portal_general_access(n, [, anyone], env, row) {
    const got = await portalDoor(env, row.id, "access", { link: anyone ? "anyone" : "restricted" });
    if (anyone && !got.ok && got.status === 409 && /no link/.test(got.why || "")) {
      const fresh = await mintLink();
      const made = await portalDoor(env, row.id, "access", { replace: { key: fresh.key, hash: fresh.hash, was: null } });
      if (made.ok) made.hash = fresh.hash;
      return made;
    }
    return got;
  },

  // ── Share, What Viewers See and the Library (backend.py 2026-10-05):
  // thin, as on the Mac; every rule is the door's (`/access`, `/viewers`,
  // `/library`), so the phone, the console and the portal never disagree.

  /** Who may open the portal: people, links and the list's `etag`; his own addresses say `owner`. */
  async portal_people(n, args, env, row) {
    const got = await portalDoor(env, row.id, "people", null, "GET");
    if (got.ok) got.people = markOwners(got.people);
    return got;
  },

  /** Add People by Email: on the list at once, as Viewer or Editor. */
  async portal_invite(n, [, email, role = "viewer", ifMatch], env, row) {
    return await portalAccess(env, row.id, { add: [{ email: String(email), role: role ?? "viewer" }] }, ifMatch);
  },

  /** A person's role: viewer, editor — or remove (never him; the door refuses that). */
  async portal_set_role(n, [, email, role, ifMatch], env, row) {
    if (role === "remove") return await portalAccess(env, row.id, { remove: [String(email)] }, ifMatch);
    return await portalAccess(env, row.id, { role: [{ email: String(email), role }] }, ifMatch);
  },

  /** The link's password, made here as salt and hash (never the word), or cleared. */
  async portal_password(n, [, word], env, row) {
    return await portalAccess(env, row.id, { password: word ? await passwordHashes(String(word)) : null });
  },

  /** A new link; every address made from the old one stops working. `was` is the old one's hash. */
  async portal_replace_link(n, [, was], env, row) {
    const fresh = await mintLink();
    const got = await portalAccess(env, row.id, { replace: { key: fresh.key, hash: fresh.hash, was: was ?? null } });
    if (got.ok) got.hash = fresh.hash;
    return got;
  },

  /** What Viewers See: each page, person and document with its switches. */
  async portal_viewers(n, args, env, row) {
    return await portalDoor(env, row.id, "viewers", null, "GET");
  },

  /** What Viewers See, saved as the panel saves it; a list left out (or null) is kept. */
  async portal_viewers_set(n, [, sections, crew, documents, contact], env, row) {
    const body = {};
    for (const [kind, names] of [["sections", sections], ["crew", crew], ["documents", documents], ["contact", contact]]) {
      if (names != null) body[kind] = [...names].map(String);
    }
    return await portalDoor(env, row.id, "viewers", body);
  },

  /** The Library: each page's pinned / private / archived, and each document's. */
  async portal_library(n, args, env, row) {
    return await portalDoor(env, row.id, "library", null, "GET");
  },

  /** pin, unpin, private, public, archive or unarchive, for pages by key (a document is `doc:<name>`). */
  async portal_library_set(n, [, keys, action], env, row) {
    const list = typeof keys === "string" ? [keys] : [...(keys || [])];
    return await portalDoor(env, row.id, "library", { keys: list.map(String), action: String(action) });
  },

  async refresh_portal(n, args, env, row) {
    return await refreshPortal(env, row.id);
  },

  /** A portal for a project with no film, then its words — backend.create_portal. */
  async create_portal(n, [name], env, row) {
    const page = bare(row.id);
    const record = await env.BUCKET.get(`r/${page}/record.json`);
    if (record) {
      try {
        const film = (await record.json()).film || {};
        if (PAGE.test(bare(film.relay))) {
          return { ok: false, why: `${film.title || name} is this project's film — its page arrives with its first sync` };
        }
      } catch { /* no film named */ }
    }
    const { status, json } = await door(env, `${page}/portal`, "PUT", { title: name, by: "console" });
    if (status >= 400) return { ok: false, why: json.problem || `the hub answered ${status}` };
    const url = json.url || `https://your-domain.example/f/${page}`;
    const words = await refreshPortal(env, page);
    // `page` stays the Notion page the console asked about; `portal` is
    // where the portal lives (the project's ID, for a minted one).
    return { ok: true, url, page, portal: await keyOfPage(env, page), refreshed: Boolean(words.ok), said: words.said || [words.why || ""] };
  },

  /** The Project Docs row's Hub box, then the portal — backend.set_document_on_portal. */
  async set_document_on_portal(n, [, docId, on], env, row) {
    if (!docId) return { ok: false, why: "Say which document." };
    await n.patch(`pages/${docId}`, { properties: { Hub: { checkbox: Boolean(on) } } });
    let refreshed;
    try { refreshed = await refreshPortal(env, row.id); } catch (e) { refreshed = { ok: false, why: String(e.message || e) }; }
    return { ok: true, on: Boolean(on), portal: Boolean(refreshed.ok), why: refreshed.ok ? "" : (refreshed.why || "") };
  },
};
