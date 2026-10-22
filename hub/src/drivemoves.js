/**
 * **Google Drive folders moved, renamed, trashed and untrashed by the server**
 * (stage 5 step 7, the big moves). `drivewrite.js` stays create-only; this is
 * the one file through which the server can take a folder away from where it
 * is — and it can only do that inside his cinematography folder or the
 * scratch folder used for tests.
 *
 * Four changes and nothing else:
 * - `rename(id, name)`        the folder keeps its id (Notion's link keeps working)
 * - `move(id, from, to)`      `addParents` / `removeParents`, the id kept
 * - `trash(id)`               to the Drive's own trash (kept there 30 days)
 * - `untrash(id)`             back out of it
 * There is no delete. A trashed folder is the Drive's to empty, never ours.
 *
 * **The fence** (`guarded`): every change names a folder that must sit
 * *inside* one of the allowed roots (the cinematography folder, the scratch
 * folder) — found by walking its parents, at most `MAX_DEPTH` levels up — and
 * never be one of those roots itself, nor one of the section roots (projects,
 * gigs, project-showcases). A move's destination must be inside a root or be
 * one. Anything else is refused before Google is asked.
 *
 * The sign-in is `GDRIVE_WRITE` (full drive scope, `hub/drive-signin.py`).
 * `GOOGLE_FAKE` (localhost only) points it at the checks' fake Google.
 */

import { accessToken, filesUrl, uploadUrl, DriveRefused } from "./drivewrite.js";

const FOLDER = "application/vnd.google-apps.folder";
const ID = /^[A-Za-z0-9_-]{5,160}$/;
export const MAX_DEPTH = 14;

/** Refused by the fence: nothing was asked of Google. */
export class OutsideRoots extends Error {}

function item(f) {
  return { id: f.id, name: String(f.name || ""), folder: f.mimeType === FOLDER, mime: f.mimeType || "",
    trashed: Boolean(f.trashed), parents: f.parents || [] };
}

/**
 * The Drive as `{get, list, rename, move, trash, untrash, mkdir, mkfile}`, or
 * null without the write sign-in. `write: false` reads only (a look).
 */
export function driveMovesApi(env, { write = false } = {}) {
  const secret = env.GDRIVE_WRITE ? "GDRIVE_WRITE" : (!write && env.GDRIVE ? "GDRIVE" : "");
  if (!secret) return null;
  const fields = `fields=${encodeURIComponent("id,name,mimeType,trashed,parents")}&supportsAllDrives=true`;
  async function call(url, init = {}) {
    const access = await accessToken(env, secret);
    let got;
    try {
      got = await fetch(url, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${access}` } });
    } catch (e) {
      throw new Error(`couldn't reach Google Drive (${e && e.message})`);
    }
    if (got.status === 404) return null;
    if (got.status === 401 || got.status === 403) throw new DriveRefused(`Google Drive refused (${got.status}): ${(await got.text()).slice(0, 200)}`);
    if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
    return got.json();
  }
  const checked = (id) => {
    if (!ID.test(String(id || ""))) throw new Error(`not a Drive id: ${String(id).slice(0, 40)}`);
    return id;
  };
  const patch = async (id, body, query = "") => {
    const got = await call(`${filesUrl(env)}/${encodeURIComponent(checked(id))}?${fields}${query}`, {
      method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
    });
    if (!got) throw new Error("Google Drive can't find that folder");
    return item(got);
  };
  const api = {
    secret,
    async get(id) {
      if (!ID.test(String(id || ""))) return null;
      const got = await call(`${filesUrl(env)}/${id}?${fields}`);
      return got ? item(got) : null;
    },
    async list(parent, { trashed = false } = {}) {
      checked(parent);
      const out = [];
      let page = "";
      do {
        const q = `'${parent}' in parents${trashed ? "" : " and trashed = false"}`;
        const url = `${filesUrl(env)}?q=${encodeURIComponent(q)}&fields=${encodeURIComponent("nextPageToken,files(id,name,mimeType,trashed,parents)")}`
          + `&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`;
        const got = await call(url);
        if (!got) return out;
        out.push(...(got.files || []).map(item));
        page = got.nextPageToken || "";
      } while (page);
      return out;
    },
  };
  if (write && secret === "GDRIVE_WRITE") {
    api.rename = (id, name) => patch(id, { name: String(name) });
    api.move = (id, from, to) => patch(id, {}, `&addParents=${encodeURIComponent(checked(to))}&removeParents=${encodeURIComponent(checked(from))}`);
    api.trash = (id) => patch(id, { trashed: true });
    api.untrash = (id) => patch(id, { trashed: false });
    api.mkdir = async (parent, name) => {
      // never a second folder of the same name: read the parent again, now
      const there = (await api.list(checked(parent))).find((k) => k.folder && !k.shortcut && k.name === name);
      if (there) return there;
      const got = await call(`${filesUrl(env)}?${fields}`, {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, mimeType: FOLDER, parents: [checked(parent)] }),
      });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      return item(got);
    };
    api.mkfile = async (parent, name, text) => {
      const boundary = `drivemoves${crypto.randomUUID().replace(/-/g, "")}`;
      const body = `--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n`
        + `${JSON.stringify({ name, parents: [checked(parent)], mimeType: "text/plain" })}\r\n`
        + `--${boundary}\r\ncontent-type: text/plain; charset=UTF-8\r\n\r\n${text}\r\n--${boundary}--`;
      const got = await call(`${uploadUrl(env)}?uploadType=multipart&${fields}`, {
        method: "POST", headers: { "content-type": `multipart/related; boundary=${boundary}` }, body,
      });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      return item(got);
    };
  }
  return api;
}

/**
 * The folders from `id` up to (and including) the first allowed root, or
 * null when no allowed root is above it within `MAX_DEPTH` levels. Each step
 * is `{id, name}`, the folder itself first.
 */
export async function chainUp(api, id, roots) {
  const allowed = new Set((roots || []).filter(Boolean));
  const out = [];
  let at = id;
  for (let i = 0; i <= MAX_DEPTH && at; i++) {
    const got = await api.get(at);
    if (!got) return null;
    out.push({ id: got.id, name: got.name, trashed: got.trashed });
    if (allowed.has(got.id)) return out;
    at = (got.parents || [])[0];
  }
  return null;
}

/** The allowed root `id` sits under, and its path from that root ("projects/lets-bake"), or null. */
export async function placeOf(api, id, roots) {
  const chain = await chainUp(api, id, roots);
  if (!chain) return null;
  const root = chain[chain.length - 1];
  return { root: root.id, path: chain.slice(0, -1).reverse().map((c) => c.name).join("/"), chain };
}

/**
 * The fenced api: the same calls, each refused (`OutsideRoots`) unless the
 * folder is inside an allowed root and is not a root itself. `roots` are the
 * allowed tops (cinematography, scratch); `keep` are folders that must never
 * be renamed, moved or trashed (the section roots and their archives).
 */
export function guarded(api, { roots, keep = [] }) {
  if (!api) return null;
  const tops = (roots || []).filter(Boolean);
  const kept = new Set([...tops, ...keep.filter(Boolean)]);
  if (!tops.length) throw new OutsideRoots("No roots are set, so nothing on the Drive can be moved.");
  const inside = async (id, what) => {
    if (kept.has(id)) throw new OutsideRoots(`${what}: that is one of the Drive's own top folders, never moved.`);
    const chain = await chainUp(api, id, tops);
    if (!chain) throw new OutsideRoots(`${what}: that folder is outside the cinematography and scratch folders.`);
    return chain;
  };
  const insideOrRoot = async (id, what) => {
    if (tops.includes(id)) return true;
    const chain = await chainUp(api, id, tops);
    if (!chain) throw new OutsideRoots(`${what}: the destination is outside the cinematography and scratch folders.`);
    return true;
  };
  const out = { ...api, guarded: true, roots: tops };
  if (api.rename) out.rename = async (id, name) => { await inside(id, "Rename"); return api.rename(id, name); };
  if (api.move) {
    out.move = async (id, from, to) => {
      await inside(id, "Move");
      await insideOrRoot(to, "Move");
      if (id === to) throw new OutsideRoots("Move: a folder can't move into itself.");
      const toChain = await chainUp(api, to, tops);
      if (toChain && toChain.some((c) => c.id === id)) throw new OutsideRoots("Move: a folder can't move into itself.");
      return api.move(id, from, to);
    };
  }
  if (api.trash) out.trash = async (id) => { await inside(id, "Trash"); return api.trash(id); };
  if (api.untrash) out.untrash = async (id) => { await inside(id, "Untrash"); return api.untrash(id); };
  if (api.mkdir) out.mkdir = async (parent, name) => { await insideOrRoot(parent, "Make"); return api.mkdir(parent, name); };
  if (api.mkfile) out.mkfile = async (parent, name, text) => { await insideOrRoot(parent, "Make"); return api.mkfile(parent, name, text); };
  return out;
}

/** How many files and folders are under a folder: a bounded walk (`cap` lists). */
export async function weigh(api, id, { cap = 60 } = {}) {
  let files = 0, folders = 0, lists = 0, partial = false;
  const queue = [id];
  while (queue.length) {
    if (lists >= cap) { partial = true; break; }
    const at = queue.shift();
    const kids = await api.list(at);
    lists += 1;
    for (const k of kids) {
      if (k.folder) { folders += 1; queue.push(k.id); } else if (!k.name.startsWith(".")) files += 1;
    }
  }
  return { files, folders, items: files + folders, partial };
}
