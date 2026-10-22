/**
 * **A portal page that follows a Google Doc** — Halcyon's Outline, from
 * Ivy's outline doc.
 *
 * His ask, 2026-10-10: *"I want to put the toggle for the updating agent on the
 * page and not Projects Console."* Until then a Mac agent (Doc Mirror, in
 * `~/Developer/agents/doc-mirror`) asked Drive every two minutes and put the
 * page up with wrangler. Now the portal asks, on its own clock (`scheduled` in
 * `worker.js`, every two minutes), so it works with the Mac asleep, and the
 * switch is on the page's own menu: **Follow Google Doc**, for an
 * administrator.
 *
 * The rule is the agent's, unchanged:
 *
 *  - **Ask Drive one small question** — "what version are you on?" — and do
 *    nothing more unless the answer changed.
 *  - **Let an edit settle.** The doc must sit still for a minute and a half
 *    before the page is redrawn, so it is never published halfway through
 *    somebody's sentence — unless the page is already ten minutes behind a doc
 *    that is still being typed in.
 *  - **Draw it the same way** (`docrender.js`, a copy of the agent's own
 *    drawing, held to it byte for byte by `hub/docfollow.mjs`).
 *  - **Never write to the doc.** Read only, by a Google sign-in that can only
 *    read (`GDRIVE`, below).
 *
 * Where things are kept:
 *
 *  - **The switch and the doc are on the page's own row** on the film's card
 *    (`follow: { doc, on, credit }`, `followOf` in `front.js`), so the sidebar
 *    can show it and a Notion refresh keeps it.
 *  - **What it last saw** — Drive's version, when it last drew the page, any
 *    trouble — is one small file beside the films, `follow/index.json`, which
 *    is also the list the clock walks. One read a tick when nothing moved.
 *
 * **`GDRIVE` is a secret, and without it nothing happens**: the menu shows the
 * switch greyed with "Not connected to Google", the clock does nothing. It is
 * `{ client_id, client_secret, refresh_token }` for a sign-in to
 * owner@your-domain.example with the read-only Drive scope, made once by
 * `hub/drive-signin.py` and put with `wrangler secret put GDRIVE`.
 */

import { keys } from "../../relay/layout.js";
import { frontOf, storedFront, saveFront, followOf } from "./front.js";
import { titleOf } from "./films.js";
import { render, picturesOf, updatedLabel, RENDER_VERSION } from "./docrender.js";

const INDEX = "follow/index.json";
/**
 * Google, or the fake one `hub/docfollow.mjs` starts on this machine. The fake
 * is only believed when it names localhost, so a stray setting on the live hub
 * can never send its Google sign-in anywhere else.
 */
const fake = (env) => (/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(env.GOOGLE_FAKE || "") ? env.GOOGLE_FAKE : "");
const tokenUrl = (env) => (fake(env) ? `${fake(env)}/token` : "https://oauth2.googleapis.com/token");
const driveUrl = (env) => (fake(env) ? `${fake(env)}/drive/v3/files` : "https://www.googleapis.com/drive/v3/files");
const SETTLE = 90 * 1000;          // the doc must sit still this long before it is drawn
const STALE = 10 * 60 * 1000;      // ...unless the page is this far behind a doc still being edited
const EXT = { "image/png": ".png", "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/gif": ".gif", "image/webp": ".webp" };

export const driveReady = (env) => Boolean(env.GDRIVE);

class Unavailable extends Error {}

/* ------------------------------------------------------------------ Drive */

let TOKEN = null;     // { access, until } — kept for the life of the isolate

async function accessToken(env) {
  if (TOKEN && Date.now() < TOKEN.until) return TOKEN.access;
  let c;
  try { c = JSON.parse(env.GDRIVE); } catch { throw new Unavailable("the Google sign-in will not read"); }
  const got = await fetch(tokenUrl(env), {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: c.client_id, client_secret: c.client_secret,
      refresh_token: c.refresh_token, grant_type: "refresh_token",
    }),
  });
  if (!got.ok) throw new Unavailable(`Google refused the sign-in (${(await got.text()).slice(0, 160)})`);
  const tok = await got.json();
  TOKEN = { access: tok.access_token, until: Date.now() + (Number(tok.expires_in || 3600) - 60) * 1000 };
  return TOKEN.access;
}

async function drive(env, url) {
  let got;
  try {
    got = await fetch(url, { headers: { authorization: `Bearer ${await accessToken(env)}` } });
  } catch (error) {
    if (error instanceof Unavailable) throw error;
    throw new Unavailable(`couldn't reach Drive (${error && error.message})`);
  }
  if (got.status === 403 || got.status === 404) throw new Unavailable(`Drive says the doc can't be opened (${got.status}) — was it unshared?`);
  if (!got.ok) throw new Unavailable(`Drive answered ${got.status}: ${(await got.text()).slice(0, 200)}`);
  return got;
}

async function docMeta(env, doc) {
  const fields = "id,name,version,modifiedTime,webViewLink,lastModifyingUser(displayName)";
  return (await drive(env, `${driveUrl(env)}/${doc}?fields=${encodeURIComponent(fields)}&supportsAllDrives=true`)).json();
}

async function docMarkdown(env, doc) {
  return (await drive(env, `${driveUrl(env)}/${doc}/export?mimeType=${encodeURIComponent("text/markdown")}`)).text();
}

/* ------------------------------------------------------------------ state */

async function readIndex(env) {
  const got = await env.BUCKET.get(INDEX);
  if (!got) return { pages: [] };
  try {
    const raw = await got.json();
    return { pages: Array.isArray(raw.pages) ? raw.pages.filter((p) => p && p.project && p.slug) : [] };
  } catch { return { pages: [] }; }
}

async function writeIndex(env, index) {
  await env.BUCKET.put(INDEX, JSON.stringify({ version: 1, pages: index.pages }), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

function entryOf(index, project, slug) {
  let one = index.pages.find((p) => p.project === project && p.slug === slug);
  if (!one) { one = { project, slug }; index.pages.push(one); }
  return one;
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * **The doc's pictures, put beside the film's other documents** (`docs/`,
 * which the page reaches as `pic/<name>`), named by what they are so a
 * picture that has not changed is never sent twice.
 */
async function picturesFor(env, project, md) {
  const out = {};
  for (const [ref, uri] of Object.entries(picturesOf(md))) {
    const comma = uri.indexOf(",");
    const mime = uri.slice(5, comma).split(";")[0].toLowerCase();
    if (comma < 0 || !EXT[mime]) continue;
    const bytes = Uint8Array.from(atob(uri.slice(comma + 1)), (c) => c.charCodeAt(0));
    const name = (await sha256(bytes)).slice(0, 32) + EXT[mime];
    if (!(await env.BUCKET.head(keys.doc(project, name)))) {
      await env.BUCKET.put(keys.doc(project, name), bytes, { httpMetadata: { contentType: mime } });
    }
    out[ref] = `pic/${name}`;
  }
  return out;
}

/* ------------------------------------------------------------------ one page */

/**
 * Look at one followed page, and redraw it if its doc has moved and settled.
 * `pressed` (the switch just turned on, or Refresh Now) skips both waits.
 * Answers `{ did: "drawn" | "same" | "waiting" | "off", said }`; throws
 * `Unavailable` when Drive cannot be asked.
 */
async function followOne(env, project, slug, mine, pressed) {
  // **The stored card, not the film's whole replay** (`frontOf`): this runs
  // every two minutes and only wants the page's row.
  const front = await storedFront(env, project);
  const sec = (front.sections || []).find((one) => one.slug === slug);
  const follow = sec && followOf(sec.follow);
  if (!follow || (!follow.on && !pressed)) return { did: "off" };

  const meta = await docMeta(env, follow.doc);
  // The doc's own name, for the page's Synced from line (pages.js `syncLine`).
  if (meta.name) mine.title = String(meta.name).slice(0, 140);
  if (!pressed && meta.version === mine.version && mine.render === RENDER_VERSION) return { did: "same" };

  const now = Date.now();
  const modified = Date.parse(meta.modifiedTime || "") || 0;
  if (!pressed && mine.published_at && now - modified < SETTLE && now - mine.published_at < STALE) {
    return { did: "waiting", said: "Waiting for the edit to settle" };
  }

  const md = await docMarkdown(env, follow.doc);
  const cfg = {
    film: (await titleOf(env, project)) || "", name: sec.name, credit: follow.credit || "",
    doc_url: `https://docs.google.com/document/d/${follow.doc}/edit`,
  };
  const hash = await sha256(new TextEncoder().encode(md + RENDER_VERSION + JSON.stringify(cfg)));
  if (hash === mine.hash && !pressed) {
    mine.version = meta.version;            // a comment, not a change of words
    return { did: "same" };
  }

  const pics = await picturesFor(env, project, md);
  const html = render(md, meta, cfg, (ref) => pics[ref] || "");
  await env.BUCKET.put(keys.pageHtml(project, slug), html, {
    httpMetadata: { contentType: "text/html; charset=utf-8" },
  });
  Object.assign(mine, {
    version: meta.version, hash, published_at: now, render: RENDER_VERSION,
    modified: meta.modifiedTime || "",
  });
  const who = (meta.lastModifyingUser || {}).displayName || "someone";
  return { did: "drawn", said: `${who} edited it ${updatedLabel(meta.modifiedTime || "")}` };
}

/**
 * **A portal carried into its film takes its followed pages along.** The list
 * the clock walks is keyed by the film's id, and a portal's id is not the
 * film's: without this, the page keeps its switch and its doc but the clock
 * looks for it under an id that no longer holds anything, and it quietly
 * stops updating (Halcyon's Outline, 2026-10-13). Where the film already
 * follows a page of the same name, the film's stands. Answers how many moved.
 */
export async function moveFollows(env, from, to) {
  const index = await readIndex(env);
  if (!index.pages.some((p) => p.project === from)) return 0;
  const taken = new Set(index.pages.filter((p) => p.project === to).map((p) => p.slug));
  let moved = 0;
  index.pages = index.pages.flatMap((one) => {
    if (one.project !== from) return [one];
    if (taken.has(one.slug)) return [];
    moved += 1;
    return [{ ...one, project: to }];
  });
  await writeIndex(env, index);
  return moved;
}

/** One page, with what it saw written down. Answers what `followOne` did, or `{ did: "trouble", said }`. */
async function lookAt(env, index, project, slug, pressed) {
  const mine = entryOf(index, project, slug);
  const before = JSON.stringify(mine);
  let got;
  try {
    got = await followOne(env, project, slug, mine, pressed);
    delete mine.trouble;
    mine.fails = 0;
  } catch (error) {
    if (!(error instanceof Unavailable)) throw error;
    mine.fails = (mine.fails || 0) + 1;
    mine.trouble = error.message;
    got = { did: "trouble", said: error.message };
  }
  if (got.did === "drawn" || got.did === "trouble") mine.checked_at = Date.now();
  return { ...got, changed: JSON.stringify(mine) !== before };
}

/* ------------------------------------------------------------------ the doors */

/** The clock's turn: every followed page, once. Writes the index only if something moved. */
export async function followTick(env) {
  if (!driveReady(env)) return;
  const index = await readIndex(env);
  let changed = false;
  for (const one of [...index.pages]) {
    const got = await lookAt(env, index, one.project, one.slug, false);
    if (got.changed) changed = true;
    if (got.did === "trouble") console.error(`follow ${one.project}/${one.slug}: ${got.said}`);
  }
  if (changed) await writeIndex(env, index);
}

/**
 * **The switch** — on, off, or Refresh Now — for one page. `doc` (an id or a
 * Google Docs address) and `credit` set which doc and whose draft; a page with
 * no doc yet must be given one. Turning it on, or Refresh Now, draws the page
 * at once rather than waiting for the clock.
 *
 * Answers `{ ok, on, said, ... }`, or `{ ok: false, status, said }`.
 */
export async function setFollow(env, project, slug, ask) {
  const front = await frontOf(env, project);
  const sec = (front.sections || []).find((one) => one.slug === slug);
  if (!sec) return { ok: false, status: 404, said: "No such page." };
  if (sec.type === "board") return { ok: false, status: 400, said: "A board can't follow a doc." };
  const had = followOf(sec.follow);
  const doc = ask.doc !== undefined ? docIdOf(ask.doc) : had ? had.doc : "";
  if (!doc) return { ok: false, status: 400, said: "Name the Google Doc." };
  const on = ask.on === undefined ? Boolean(had && had.on) : Boolean(ask.on);
  const credit = ask.credit !== undefined ? String(ask.credit || "") : had ? had.credit || "" : "";
  const want = followOf({ doc, on, credit });
  if (JSON.stringify(want) !== JSON.stringify(had)) {
    sec.follow = want;
    await saveFront(env, project, front);
  }

  const index = await readIndex(env);
  entryOf(index, project, slug);
  let got = { did: on ? "same" : "off" };
  if ((on && !(had && had.on)) || ask.refresh) {
    if (!driveReady(env)) {
      await writeIndex(env, index);
      return { ok: true, on, said: "Not connected to Google", ...stateOf(want, entryOf(index, project, slug)) };
    }
    got = await lookAt(env, index, project, slug, true);
  }
  await writeIndex(env, index);
  const said = got.did === "drawn" ? "Updated from the Doc" : got.did === "trouble" ? got.said : on ? "Following" : "Stopped Following";
  return { ok: got.did !== "trouble", ...(got.did === "trouble" ? { status: 502 } : {}), on, said, ...stateOf(want, entryOf(index, project, slug)) };
}

/** What a page's follow looks like from outside: for the menu, the console and the MCP. */
export async function followStateOf(env, project, slug) {
  const front = await storedFront(env, project);
  const sec = (front.sections || []).find((one) => one.slug === slug);
  const follow = sec && followOf(sec.follow);
  if (!follow) return null;
  const index = await readIndex(env);
  const mine = index.pages.find((p) => p.project === project && p.slug === slug) || {};
  return stateOf(follow, mine);
}

function stateOf(follow, mine) {
  return {
    doc: follow.doc, following: follow.on, credit: follow.credit || "",
    doc_url: `https://docs.google.com/document/d/${follow.doc}/edit`,
    drawn: mine.published_at ? new Date(mine.published_at).toISOString() : null,
    doc_edited: mine.modified || null,
    title: mine.title || null,
    trouble: mine.trouble || null,
  };
}

/** A Drive file id, from the id itself or any Google Docs or Drive address. */
export function docIdOf(said) {
  const s = String(said || "").trim();
  const m = /\/d\/([A-Za-z0-9_-]{20,100})/.exec(s) || /[?&]id=([A-Za-z0-9_-]{20,100})/.exec(s);
  if (m) return m[1];
  return /^[A-Za-z0-9_-]{20,100}$/.test(s) ? s : "";
}
