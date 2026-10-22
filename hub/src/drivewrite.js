/**
 * **The Google Drive the server makes folders in** (2026-10-13, stage 3
 * step 6) — the small Drive v3 client `drivefolders.js` works through.
 *
 * Four things and no more: list a folder, read one item, make a folder, make
 * a small file (the hidden markers). There is no move, rename, trash or
 * delete here, so nothing that reaches the Drive through this file can take
 * anything away — whatever the sign-in itself would allow.
 *
 * **The sign-ins.** `GDRIVE_WRITE` is the one that makes folders:
 * `{client_id, client_secret, refresh_token}`, made once by
 * `hub/drive-signin.py --write` and kept as a Worker secret. A look (which
 * writes nothing) reads with it when it is there, else with the portal's
 * read-only `GDRIVE` (docfollow.js), so the dry look works before the write
 * sign-in exists. Without either, nothing is read.
 *
 * `GOOGLE_FAKE` (a localhost address only, as in docfollow.js) points both at
 * the fake Google `hub/drivefolders-live.mjs` starts.
 */

const FOLDER = "application/vnd.google-apps.folder";
const SHORTCUT = "application/vnd.google-apps.shortcut";
const ID = /^[A-Za-z0-9_-]{5,160}$/;

export const fake = (env) => (/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(env.GOOGLE_FAKE || "") ? env.GOOGLE_FAKE : "");
export const tokenUrl = (env) => (fake(env) ? `${fake(env)}/token` : "https://oauth2.googleapis.com/token");
export const filesUrl = (env) => (fake(env) ? `${fake(env)}/drive/v3/files` : "https://www.googleapis.com/drive/v3/files");
export const uploadUrl = (env) => (fake(env) ? `${fake(env)}/upload/drive/v3/files` : "https://www.googleapis.com/upload/drive/v3/files");

/** Google said no to the sign-in or the folder (401/403) — nothing was made by this call. */
export class DriveRefused extends Error {}

const TOKENS = new Map();     // secret name -> { access, until, raw }

/** Exported for film backups (`filmbackuprun.js`), which keeps its own few
 * Drive calls — an upload and a trash — out of this file, so nothing that
 * reaches the Drive through *this* file can take anything away. */
export async function accessToken(env, secret) {
  const raw = env[secret];
  const held = TOKENS.get(secret);
  if (held && held.raw === raw && Date.now() < held.until) return held.access;
  let c;
  try { c = JSON.parse(raw); } catch { throw new DriveRefused(`the ${secret} sign-in will not read`); }
  const got = await fetch(tokenUrl(env), {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: c.client_id, client_secret: c.client_secret, refresh_token: c.refresh_token, grant_type: "refresh_token" }),
  });
  if (!got.ok) throw new DriveRefused(`Google refused the sign-in (${(await got.text()).slice(0, 160)})`);
  const tok = await got.json();
  TOKENS.set(secret, { raw, access: tok.access_token, until: Date.now() + (Number(tok.expires_in || 3600) - 60) * 1000 });
  return tok.access_token;
}

/** One item as the rules read it. A shortcut is never taken for a folder. */
function item(f) {
  return { id: f.id, name: String(f.name || ""), folder: f.mimeType === FOLDER, shortcut: f.mimeType === SHORTCUT,
    mime: f.mimeType || "", trashed: Boolean(f.trashed), parents: f.parents || [] };
}

/**
 * The Drive as `{list, get, mkdir, mkfile}`. `write: false` (a look) reads
 * with `GDRIVE_WRITE` or else `GDRIVE`, and has no mkdir or mkfile at all.
 * Answers null when there is no sign-in to use.
 */
export function driveApi(env, { write = false } = {}) {
  const secret = env.GDRIVE_WRITE ? "GDRIVE_WRITE" : (!write && env.GDRIVE ? "GDRIVE" : "");
  if (!secret) return null;
  let wrote = false;
  async function call(url, init = {}) {
    const access = await accessToken(env, secret);
    let got;
    try {
      got = await fetch(url, { ...init, headers: { ...(init.headers || {}), authorization: `Bearer ${access}` } });
    } catch (e) {
      throw new Error(`couldn't reach Google Drive (${e && e.message})`);
    }
    if (got.status === 404) return null;
    if (got.status === 401 || got.status === 403) {
      const why = (await got.text()).slice(0, 200);
      throw (wrote ? new Error(`Google Drive refused (${got.status}): ${why}`) : new DriveRefused(`Google Drive refused (${got.status}): ${why}`));
    }
    if (!got.ok) throw new Error(`Google Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
    return got.json();
  }
  const checked = (id) => {
    if (!ID.test(String(id || ""))) throw new Error(`not a Drive id: ${String(id).slice(0, 40)}`);
    return id;
  };
  const api = {
    secret,
    async list(parent) {
      checked(parent);
      const out = [];
      let page = "";
      do {
        const q = `'${parent}' in parents and trashed = false`;
        const url = `${filesUrl(env)}?q=${encodeURIComponent(q)}&fields=${encodeURIComponent("nextPageToken,files(id,name,mimeType,trashed)")}`
          + `&pageSize=1000&supportsAllDrives=true&includeItemsFromAllDrives=true${page ? `&pageToken=${encodeURIComponent(page)}` : ""}`;
        const got = await call(url);
        if (!got) return out;
        out.push(...(got.files || []).map(item));
        page = got.nextPageToken || "";
      } while (page);
      return out;
    },
    /** A small file's words (a marker): "" when it cannot be read. */
    async text(id) {
      if (!ID.test(String(id || ""))) return "";
      const access = await accessToken(env, secret);
      let got;
      try {
        got = await fetch(`${filesUrl(env)}/${id}?alt=media&supportsAllDrives=true`, { headers: { authorization: `Bearer ${access}` } });
      } catch {
        return "";
      }
      if (!got.ok) return "";
      return (await got.text()).slice(0, 4096);
    },
    async get(id) {
      if (!ID.test(String(id || ""))) return null;
      const got = await call(`${filesUrl(env)}/${id}?fields=${encodeURIComponent("id,name,mimeType,trashed,parents")}&supportsAllDrives=true`);
      return got ? item(got) : null;
    },
  };
  if (write && secret === "GDRIVE_WRITE") {
    api.mkdir = async (parent, name) => {
      // **Never a second folder with the same name** (2026-10-17: a second
      // `select-stills` beside the one the Mac was making). The parent is read
      // again here, at the moment of making, whatever the caller looked at
      // earlier: a folder of exactly this name already in it is the answer, and
      // nothing is made. (A race inside one second between two makers can
      // still double it; nothing here deletes, so that one is a person's call.)
      checked(parent);
      const there = (await api.list(parent)).find((k) => k.folder && !k.shortcut && k.name === name);
      if (there) return there;
      const got = await call(`${filesUrl(env)}?fields=${encodeURIComponent("id,name,mimeType")}&supportsAllDrives=true`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, mimeType: FOLDER, parents: [checked(parent)] }),
      });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      wrote = true;
      return item(got);
    };
    api.mkfile = async (parent, name, text) => {
      const boundary = `drivefolders${crypto.randomUUID().replace(/-/g, "")}`;
      const body = `--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n`
        + `${JSON.stringify({ name, parents: [checked(parent)], mimeType: "text/plain" })}\r\n`
        + `--${boundary}\r\ncontent-type: text/plain; charset=UTF-8\r\n\r\n${text}\r\n--${boundary}--`;
      const got = await call(`${uploadUrl(env)}?uploadType=multipart&fields=${encodeURIComponent("id,name,mimeType")}&supportsAllDrives=true`, {
        method: "POST",
        headers: { "content-type": `multipart/related; boundary=${boundary}` },
        body,
      });
      if (!got || !got.id) throw new Error(`Google Drive did not make ${name}`);
      wrote = true;
      return item(got);
    };
  }
  return api;
}
