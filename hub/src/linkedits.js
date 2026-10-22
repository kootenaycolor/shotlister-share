/**
 * **What people on the share link drew on the plans** (his ask, 2026-10-17:
 * *"editing should be available publicly"*), kept so he can see it and take
 * it back.
 *
 * When the project's Editable by Link is on, a visitor with the link and no
 * sign-in gets the whole Diagrams editor. Every batch of their edits is kept
 * by the film as a change log in a device of their own (`diagramEdit`), the
 * way any edit is; this is the record beside it that says who and when in
 * his words — "Link visitor", the time, what they did, on which plan — and
 * holds the edits that take it back, worked out by the server's engine at
 * the moment it was made (`diagram::portal::undo_ops`), so an Undo from his
 * list never trusts what a visitor's page said.
 *
 * One object per batch, named newest-first, so two visitors writing at once
 * never overwrite each other's entry.
 *
 * And a brake: a link may make at most `PER_MINUTE` batches a minute from one
 * address (Cloudflare's rate limiter where the hub has one, `LINK_EDITS`, and
 * this isolate's own count always), so a link pasted somewhere public cannot
 * be used to hammer a film.
 */

export const PER_MINUTE = 120;
/** The most entries his list shows. */
const MOST = 150;
const FAR = 1e13;

/** Where a project's link edits are kept: beside `diagram.settings.json`. */
export function linkEditsPrefix(base) {
  return `${base}diagram.linkedits/`;
}

/** A visitor's short name: their browser's own random name, four letters of it. */
export function visitorName(me) {
  const tag = String(me || "").replace(/[^a-z0-9]/gi, "").slice(-4).toUpperCase();
  return tag ? `Link visitor ${tag}` : "Link visitor";
}

/**
 * Keep one batch. `said` is the engine's answer (its `undo`); `labels` are
 * the page's names for the edits (shown only, never acted on).
 */
export async function keepLinkEdit(bucket, base, { me, scene, ops, labels, said }) {
  const undo = Array.isArray(said && said.undo) ? said.undo : [];
  if (!undo.length) return null;
  const at = Date.now();
  const tidy = (Array.isArray(labels) ? labels : [])
    .map((l) => String(l || "").replace(/\s+/g, " ").trim().slice(0, 60))
    .filter(Boolean);
  // Several of the same in a row read as one: "Move ×3".
  const named = [];
  for (const l of tidy) {
    const last = named[named.length - 1];
    if (last && last.label === l) last.n += 1; else named.push({ label: l, n: 1 });
  }
  const entry = {
    at: new Date(at).toISOString(),
    who: visitorName(me),
    device: String(me || "anon").slice(0, 20),
    scene: String(scene || ""),
    did: named.slice(0, 8).map((x) => (x.n > 1 ? `${x.label} ×${x.n}` : x.label)),
    ops: Array.isArray(ops) ? ops.length : 0,
    undo,
    undone: false,
  };
  const name = `${String(FAR - at).padStart(13, "0")}-${entry.device}-${Math.random().toString(36).slice(2, 8)}.json`;
  await bucket.put(`${linkEditsPrefix(base)}${name}`, JSON.stringify(entry), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  return name;
}

/** His list: newest first. */
export async function listLinkEdits(bucket, base) {
  const prefix = linkEditsPrefix(base);
  const listed = await bucket.list({ prefix, limit: MOST });
  const out = [];
  for (const o of listed.objects || []) {
    const got = await bucket.get(o.key);
    if (!got) continue;
    try {
      const e = await got.json();
      out.push({ key: o.key.slice(prefix.length), ...e });
    } catch { /* a broken entry is left out, not shown wrong */ }
  }
  return out;
}

/** Mark one taken back (or not), by its name. */
export async function markLinkEdit(bucket, base, key, undone) {
  if (!/^[0-9]{13}-[a-z0-9]{1,20}-[a-z0-9]{1,8}\.json$/i.test(String(key || ""))) return false;
  const at = `${linkEditsPrefix(base)}${key}`;
  const got = await bucket.get(at);
  if (!got) return false;
  let e;
  try { e = await got.json(); } catch { return false; }
  e.undone = Boolean(undone);
  await bucket.put(at, JSON.stringify(e), { httpMetadata: { contentType: "application/json; charset=utf-8" } });
  return true;
}

// ---- the brake --------------------------------------------------------------

const counts = new Map();

/**
 * Whether one more batch may come from `who` on `project` this minute.
 * Cloudflare's limiter first, when bound; this isolate's count always, so a
 * hub without the binding (a local run) still has a brake.
 */
export async function linkMayWrite(env, project, who) {
  const key = `${project}:${who}`;
  if (env && env.LINK_EDITS && typeof env.LINK_EDITS.limit === "function") {
    try {
      const { success } = await env.LINK_EDITS.limit({ key });
      if (!success) return false;
    } catch { /* the limiter is a brake, not a gate: fall through */ }
  }
  const now = Date.now();
  const minute = Math.floor(now / 60000);
  const c = counts.get(key);
  if (!c || c.minute !== minute) {
    if (counts.size > 5000) counts.clear();
    counts.set(key, { minute, n: 1 });
    return true;
  }
  c.n += 1;
  return c.n <= PER_MINUTE;
}
