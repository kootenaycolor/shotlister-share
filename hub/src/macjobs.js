/**
 * **The Mac jobs list** (stage 5 step 7, piece A, 2026-10-15).
 *
 * The few things only a Mac can do — a project's template folders on a media
 * drive, its Finder sidebar entry, a drive's index scan — are kept here as
 * jobs, seen by every device, and done by whichever Mac can do them first.
 *
 *   GET  /console/studio/macjobs                { on, jobs, macs } (`?all=1` the finished too)
 *   POST /console/studio/macjobs                { kind, project_id, project_name, title?, sub?,
 *                                                needs, args, move_id?, by, by_machine? } → job
 *   PUT  /console/studio/macjobs/<id>           CAS: { claim: true, by, name, local? }
 *                                                     { lease: true, by }
 *                                                     { progress: {pct, text}, by }
 *                                                     { part, state: done|failed|open, said, by }
 *                                                     { state: "waiting", by }   (given back)
 *   PUT  /console/studio/macjobs/<id>/scan      an index job's scan (the Mac's read of a drive)
 *   POST /console/studio/macjobs/<id>/retry     needs-you or failed → waiting (his Try Again)
 *   POST /console/studio/macjobs/<id>/cancel    his Let It Go
 *   PUT  /console/studio/macjobs/mac            a Mac's presence
 *   GET  /console/studio/macjobs/switch         { on, at, by }   PUT { on, by }
 *   GET  /console/studio/macjobs/look           what the switch would do now; writes nothing
 *
 * Kept at `s/macjobs.json` (`{jobs, migrated_owed}`), written compare-and-set
 * like the asks mailbox; presence at `s/macjobs-macs.json`.
 *
 * **HARD RULE (his, 2026-10-15): media drives are create-only.** A job that
 * names a drive (`needs.drive`) must be one of `MEDIA_KINDS` — template
 * folders, or a read-only scan. `addJob` refuses anything else, and so does
 * the Mac's runner.
 */

import { Handoff, cloudReady, notionOf } from "./cloud.js";
import { refuseOff } from "./fixedon.js";

export const JOBS_KEY = "s/macjobs.json";
export const MACS_KEY = "s/macjobs-macs.json";
export const SWITCH_KEY = "s/macjobs-switch.json";
export const SCAN_PREFIX = "s/macjobs-scan/";

export const LEASE_MS = 5 * 60 * 1000;
export const HEAD_START_MS = 30 * 1000;
export const PRESENT_MS = 3 * 60 * 1000;
export const REMIND_MS = 3 * 24 * 3600 * 1000;
export const KEEP_MS = 30 * 24 * 3600 * 1000;
export const ASK_EXPIRES_MS = 10 * 60 * 1000;
export const LEASE_TRIES = 3;
const MACS_KEEP_MS = 30 * 24 * 3600 * 1000;

const ID = /^[0-9a-f]{12}$/;
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const str = (v, n = 200) => String(v == null ? "" : v).slice(0, n);
const newId = () => crypto.randomUUID().replace(/-/g, "").slice(0, 12);

/** The only kinds that may touch a media drive: make template folders, read. */
export const MEDIA_KINDS = new Set(["media-folders", "index"]);

/**
 * The kinds. `parts`: the Mac's parts, in order; `server`: parts the server
 * does after the Mac's (`SERVER_PARTS`). `retry_safe`: a lease that runs out
 * puts it back to waiting (else needs-you). `needs_default`: merged under the
 * job's own `needs`.
 */
export const KINDS = {
  "media-folders": { retry_safe: true, needs_default: {}, parts: ["media"], label: "Make media folders" },
  sidebar: { retry_safe: true, needs_default: { mac: "studio" }, parts: ["sidebar"], label: "Add to Finder sidebar" },
  index: { retry_safe: true, needs_default: {}, parts: ["scan"], server: ["notion"], label: "Index" },
  ask: { retry_safe: false, needs_default: { mac: "studio" }, parts: ["answer"], label: "Ask the Studio Mac" },
  // ── big-move kinds (moves builder) ─────────────────────────────────────────
  // Added here by the moves builder: { retry_safe, needs_default, parts, label }.
  // bigmoves.js BIGMOVE_KINDS says the same; never a drive (media is create-only).
  "showcase-stills": { retry_safe: true, needs_default: { mac: "any", tools: ["cwebp"] }, parts: ["stills"], label: "Showcase pictures" },
  "film-drivefolder": { retry_safe: true, needs_default: { mac: "studio" }, parts: ["studio"], label: "Tell Studio where the folder went" },
  "bridge-list": { retry_safe: true, needs_default: { mac: "studio" }, parts: ["bridge"], label: "Drive bridge list" },
  // ── end of big-move kinds ──────────────────────────────────────────────────
};

/** Words a job is listed under, per kind. */
function titleOf(kind, name, needs) {
  const k = KINDS[kind] || {};
  if (kind === "index") return `Index ${needs.drive || "a drive"}`;
  return name ? `${k.label || kind} · ${name}` : (k.label || kind);
}

// ── storage ──────────────────────────────────────────────────────────────────

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

async function listOf(env) {
  const got = await env.BUCKET.get(JOBS_KEY);
  if (!got) return { doc: { jobs: [] }, etag: null };
  try {
    const v = await got.json();
    const doc = isObject(v) ? v : {};
    return { doc: { ...doc, jobs: Array.isArray(doc.jobs) ? doc.jobs.filter(isObject) : [] }, etag: got.etag };
  } catch {
    return { doc: { jobs: [] }, etag: got.etag };
  }
}

export class Refused extends Error {
  constructor(status, said) { super(said); this.status = status; }
}

/** Read, settle, change, write back only if nobody wrote in between. */
export async function changeJobs(env, change, now = Date.now()) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const { doc, etag } = await listOf(env);
    const macs = await macsOf(env);
    const settled = settle(doc.jobs, macs, now);
    const out = change({ ...doc, jobs: settled.jobs }, macs) || {};
    if (out.refused) throw out.refused;
    const next = out.doc || { ...doc, jobs: settled.jobs };
    if (!out.doc && !settled.changed) return out;
    next.jobs = prune(next.jobs, now);
    const saved = await env.BUCKET.put(JOBS_KEY, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: etag ? { etagMatches: etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return out;
  }
  throw new Refused(409, "The list kept changing while this was being written. Try again.");
}

export async function macsOf(env) {
  const v = await readJson(env, MACS_KEY);
  return isObject(v) && isObject(v.macs) ? v.macs : {};
}

// ── the switch ───────────────────────────────────────────────────────────────

export async function macJobsOn(env) {
  const v = await readJson(env, SWITCH_KEY);
  return { on: Boolean(v && v.on === true), at: (v && v.at) || null, by: (v && v.by) || null };
}

export async function setSwitch(env, said) {
  const fixed = refuseOff(said);
  if (fixed) return fixed;
  const out = { on: Boolean(said && said.on === true), at: new Date().toISOString(), by: str(said && said.by, 80) };
  await env.BUCKET.put(SWITCH_KEY, JSON.stringify(out), { httpMetadata: { contentType: "application/json" } });
  if (out.on) await migrateOwed(env);
  return out;
}

// ── the rules ────────────────────────────────────────────────────────────────

/** Kept: every open job; finished or let go for thirty days. */
export function prune(jobs, now = Date.now()) {
  return (jobs || []).filter((j) => !["done", "cancelled"].includes(j.state)
    || !j.done_at || now - Date.parse(j.done_at) < KEEP_MS);
}

const present = (mac, now) => Boolean(mac && mac.seen && now - Date.parse(mac.seen) < PRESENT_MS);
const isStudio = (mac) => Boolean(mac && (mac.runs_agents === true || mac.name === "Studio Mac"));

/**
 * Leases that ran out, asks that expired: what the clock alone changes.
 * Answers `{jobs, changed}`.
 */
export function settle(jobs, macs = {}, now = Date.now()) {
  let changed = false;
  const at = new Date(now).toISOString();
  const out = (jobs || []).map((j) => {
    if (j.kind === "ask" && j.state === "waiting" && now - Date.parse(j.asked) > ASK_EXPIRES_MS) {
      changed = true;
      return { ...j, state: "failed", said: "No Mac answered in time.", done_at: at };
    }
    if (j.state !== "running" || !j.claim || !j.claim.lease_until) return j;
    if (Date.parse(j.claim.lease_until) >= now) return j;
    changed = true;
    if (j.claim.by === "server") {
      // The server's own part was cut off: it is tried again by the minute.
      return { ...j, claim: { ...j.claim, lease_until: null, expired: at } };
    }
    const kind = KINDS[j.kind] || {};
    const who = j.claim.name || "a Mac";
    const tries = (j.tries || 0) + 1;
    const parts = reopen(j.parts);
    const lastWords = j.progress && j.progress.text ? ` · ${j.progress.text}` : "";
    if (!kind.retry_safe) {
      return { ...j, state: "needs-you", tries, parts, last_claim: j.claim, claim: undefined,
        said: `Stopped on ${who}${lastWords}` };
    }
    if (tries >= LEASE_TRIES) {
      return { ...j, state: "needs-you", tries, parts, last_claim: j.claim, claim: undefined,
        said: `Stopped ${tries} times on ${who}` };
    }
    return { ...j, state: "waiting", tries, parts, last_claim: j.claim, claim: undefined };
  });
  return { jobs: out.map(dropUndefined), changed };
}

function dropUndefined(j) {
  const o = {};
  for (const [k, v] of Object.entries(j)) if (v !== undefined) o[k] = v;
  return o;
}

/** Every Mac part not done goes back to open. */
function reopen(parts) {
  const out = {};
  for (const [k, p] of Object.entries(parts || {})) {
    out[k] = p.state === "done" || p.who === "server" ? p : { ...p, state: "open" };
  }
  return out;
}

/** Whether `mac` (presence) can take this job now, and if not, why. */
export function canTake(job, mac, macs = {}, now = Date.now(), { local = false } = {}) {
  if (!mac) return { ok: false, why: "Say which Mac this is first." };
  const needs = job.needs || {};
  if (needs.mac === "studio" && !isStudio(mac)) return { ok: false, why: "This one is the Studio Mac's." };
  if (needs.mac && needs.mac !== "any" && needs.mac !== "studio" && needs.mac !== mac.machine_id) {
    return { ok: false, why: "This one is another Mac's." };
  }
  if (needs.drive && !hasDrive(mac, needs)) return { ok: false, why: `${needs.drive} is not plugged into this Mac.` };
  for (const t of needs.tools || []) {
    if (!(mac.tools || []).includes(t)) return { ok: false, why: `This Mac has no ${t}.` };
  }
  // The Studio's head start on a job any Mac can do: the laptop only takes it
  // when the Studio is asleep — or when he pressed the button on the laptop.
  const anyMac = !needs.mac || needs.mac === "any";
  const pressedHere = local && job.by_machine && job.by_machine === mac.machine_id;
  if (anyMac && !isStudio(mac) && !pressedHere && now - Date.parse(job.asked) < HEAD_START_MS) {
    const studioUp = Object.values(macs).some((m) => isStudio(m) && present(m, now) && m.machine_id !== mac.machine_id);
    if (studioUp) return { ok: false, why: "The Studio Mac goes first.", wait: true };
  }
  return { ok: true };
}

/** A drive by its volume uuid when both sides know it, else by name. */
export function hasDrive(mac, needs) {
  const want = String(needs.drive || "").toLowerCase();
  for (const d of (mac && mac.drives) || []) {
    if (needs.drive_uuid && d.uuid) {
      if (String(d.uuid).toUpperCase() === String(needs.drive_uuid).toUpperCase()) return true;
      continue;
    }
    if ([d.name, d.short].some((n) => String(n || "").toLowerCase() === want)) return true;
  }
  return false;
}

// ── the words ────────────────────────────────────────────────────────────────

const TZ = "America/Vancouver";
const dayOf = (ms) => new Intl.DateTimeFormat("en-CA", { timeZone: TZ, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(ms));

/** "today", "yesterday", "Tuesday", "Oct 3" — on his clock. */
export function dayWords(ms, now = Date.now()) {
  const a = Date.parse(dayOf(ms)), b = Date.parse(dayOf(now));
  const days = Math.round((b - a) / 86400000);
  if (days <= 0) return "today";
  if (days === 1) return "yesterday";
  if (days < 7) return new Intl.DateTimeFormat("en-US", { timeZone: TZ, weekday: "long" }).format(new Date(ms));
  return new Intl.DateTimeFormat("en-US", { timeZone: TZ, month: "short", day: "numeric" }).format(new Date(ms));
}

/** "Studio Mac", "the laptop". */
export function macWords(name) {
  const n = String(name || "").trim();
  if (!n) return "a Mac";
  if (n.toLowerCase() === "laptop") return "the laptop";
  return n;
}

/** The pill: Waiting, Running, Done, Needs You (or Let Go). */
export function pillOf(job) {
  if (job.state === "running") return "Running";
  if (job.state === "done") return "Done";
  if (job.state === "needs-you" || job.state === "failed") return "Needs You";
  if (job.state === "cancelled") return "Let Go";
  return "Waiting";
}

/** The sub-line under a job's title: what it waits for, where it ran. */
export function waitingWords(job, macs = {}, now = Date.now()) {
  const needs = job.needs || {};
  const tail = job.sub ? ` · ${job.sub}` : "";
  const live = Object.values(macs).filter((m) => present(m, now));
  if (job.state === "running") {
    const p = job.progress && job.progress.text ? ` · ${job.progress.text}` : "";
    if (job.claim && job.claim.by === "server") return `Running on the server${p}`;
    return `Running on ${macWords(job.claim && job.claim.name)}${p}`;
  }
  if (job.state === "done") {
    const day = dayWords(Date.parse(job.done_at || job.asked), now);
    const where = macWords(job.ran_on);
    return day === "today" ? `Done on ${where}` : `Done ${day} on ${where}`;
  }
  if (job.state === "cancelled") return `Let go${job.cancelled_by ? ` by ${job.cancelled_by}` : ""}`;
  if (job.state === "needs-you" || job.state === "failed") return job.said || "Stopped";
  // waiting
  if (needs.drive) {
    const holder = live.find((m) => hasDrive(m, needs));
    if (holder) return `Waiting for ${macWords(holder.name)} · ${needs.drive} plugged in${tail}`;
    return `Waiting for ${needs.drive} · unplugged · since ${dayWords(Date.parse(job.asked), now)}${tail}`;
  }
  if (needs.mac === "studio") {
    return live.some(isStudio) ? `Waiting for the Studio Mac${tail}` : `Waiting for the Studio Mac · asleep${tail}`;
  }
  if (needs.mac && needs.mac !== "any") {
    const m = macs[needs.mac];
    return `Waiting for ${macWords(m && m.name)}${tail}`;
  }
  return `Waiting for a Mac${tail}`;
}

/** A job as the screens show it: with its pill and sub-line. */
export function shown(job, macs = {}, now = Date.now()) {
  return { ...job, pill: pillOf(job), line: waitingWords(job, macs, now) };
}

// ── making one ───────────────────────────────────────────────────────────────

/** A new job, checked against the hard rule. Throws `Refused`. */
export function newJob(said, now = Date.now()) {
  const s = isObject(said) ? said : {};
  const kind = str(s.kind, 40);
  const k = KINDS[kind];
  if (!k) throw new Refused(400, `There is no ${kind || "such"} job.`);
  const needs = { ...k.needs_default, ...(isObject(s.needs) ? s.needs : {}) };
  for (const key of Object.keys(needs)) if (!["drive", "drive_uuid", "mac", "tools"].includes(key)) delete needs[key];
  if (needs.drive !== undefined) needs.drive = str(needs.drive, 80).trim();
  if (!needs.drive) delete needs.drive;
  if (needs.drive_uuid !== undefined) needs.drive_uuid = str(needs.drive_uuid, 80).trim();
  if (!needs.drive_uuid) delete needs.drive_uuid;
  if (needs.tools !== undefined) needs.tools = (Array.isArray(needs.tools) ? needs.tools : []).map((t) => str(t, 40)).filter(Boolean);
  if (needs.tools && !needs.tools.length) delete needs.tools;
  // HARD RULE: a media drive takes template folders and read-only scans, nothing else.
  if (needs.drive && !MEDIA_KINDS.has(kind)) {
    throw new Refused(400, "Media drives are create-only: only template folders or a read-only scan may wait for a drive.");
  }
  if (MEDIA_KINDS.has(kind) && !needs.drive) throw new Refused(400, "Say which drive.");
  if (kind === "media-folders" && !(isObject(s.args) && s.args.slug)) throw new Refused(400, "Say the folder name.");
  const at = new Date(now).toISOString();
  const parts = {};
  for (const p of k.parts || []) parts[p] = { state: "open", who: "mac" };
  for (const p of k.server || []) parts[p] = { state: "open", who: "server" };
  const name = str(s.project_name, 200);
  const job = {
    id: newId(), kind,
    project_id: str(s.project_id, 64), project_name: name,
    title: str(s.title, 200) || titleOf(kind, name, needs),
    sub: str(s.sub, 200),
    needs, parts, state: "waiting",
    args: isObject(s.args) ? s.args : {},
    asked: at, by: str(s.by, 80) || "server", tries: 0,
  };
  if (s.by_machine) job.by_machine = str(s.by_machine, 80);
  if (s.move_id) job.move_id = str(s.move_id, 64);
  if (s.group) job.group = str(s.group, 64);
  if (!job.sub) delete job.sub;
  return job;
}

/**
 * **For the moves builder** (and New Project): put a job on the list.
 * `{kind, project_id, project_name, title, sub?, needs, args, move_id?, by}`.
 * An index job for a drive that already has one waiting is that one.
 */
export async function addJob(env, said, now = Date.now()) {
  const job = newJob(said, now);
  let out = job;
  await changeJobs(env, (doc) => {
    if (job.kind === "index") {
      const same = doc.jobs.find((j) => j.kind === "index" && ["waiting", "running"].includes(j.state)
        && String((j.needs || {}).drive).toLowerCase() === job.needs.drive.toLowerCase());
      if (same) { out = same; return {}; }
    }
    return { doc: { ...doc, jobs: [...doc.jobs, job] } };
  }, now);
  return out;
}

/** **For the moves builder:** let go of a move's jobs. A running one is left
 * to finish and named, so the undo can say "wait for it". */
export async function cancelJobs(env, { move_id, by = "" } = {}, now = Date.now()) {
  const cancelled = [], running = [];
  if (!move_id) return { cancelled, running };
  await changeJobs(env, (doc) => {
    cancelled.length = 0; running.length = 0;
    const at = new Date(now).toISOString();
    const jobs = doc.jobs.map((j) => {
      if (j.move_id !== move_id) return j;
      if (j.state === "running") { running.push(j.id); return j; }
      if (["waiting", "needs-you", "failed"].includes(j.state)) {
        cancelled.push(j.id);
        return { ...j, state: "cancelled", cancelled_by: str(by, 80), done_at: at };
      }
      return j;
    });
    return cancelled.length ? { doc: { ...doc, jobs } } : {};
  }, now);
  return { cancelled, running };
}

/** **For the moves builder:** a project's or a move's jobs, as kept. */
export async function jobsFor(env, { project_id, move_id } = {}, now = Date.now()) {
  const { doc } = await listOf(env);
  const { jobs } = settle(doc.jobs, await macsOf(env), now);
  return prune(jobs, now).filter((j) => (!project_id || j.project_id === project_id) && (!move_id || j.move_id === move_id));
}

// ── a Mac at it ──────────────────────────────────────────────────────────────

/** One change to one job, by a Mac or by him. Answers the job after. */
export async function changeJob(env, id, said, now = Date.now()) {
  if (!ID.test(String(id))) throw new Refused(404, "No such job.");
  const s = isObject(said) ? said : {};
  const by = str(s.by, 80);
  const at = new Date(now).toISOString();
  let after = null;
  await changeJobs(env, (doc, macs) => {
    const i = doc.jobs.findIndex((j) => j.id === id);
    if (i < 0) return { refused: new Refused(404, "No such job.") };
    const j = doc.jobs[i];
    let next = null;
    const mine = j.state === "running" && j.claim && j.claim.by === by;

    if (s.claim) {
      // **Claimed once.** Only from waiting; a second claimant is handed the
      // job as it stands and can see it is not theirs.
      if (j.state !== "waiting") { after = j; return {}; }
      const mac = macs[by];
      const can = canTake(j, mac, macs, now, { local: Boolean(s.local) });
      if (!can.ok) return { refused: new Refused(409, can.why) };
      next = { ...j, state: "running", claim: { by, name: str(s.name || (mac && mac.name), 80), at, lease_until: new Date(now + LEASE_MS).toISOString() } };
      delete next.progress;
    } else if (s.lease) {
      if (!mine) { after = j; return {}; }
      next = { ...j, claim: { ...j.claim, lease_until: new Date(now + LEASE_MS).toISOString() } };
    } else if (s.progress) {
      if (!mine) { after = j; return {}; }
      const p = isObject(s.progress) ? s.progress : {};
      next = { ...j, progress: { pct: Math.max(0, Math.min(100, Math.floor(Number(p.pct) || 0))), text: str(p.text, 200) },
        claim: { ...j.claim, lease_until: new Date(now + LEASE_MS).toISOString() } };
    } else if (s.part) {
      const part = str(s.part, 40);
      const state = str(s.state, 20);
      if (!isObject(j.parts) || !isObject(j.parts[part])) return { refused: new Refused(400, `This job has no ${part || "such"} part.`) };
      if (!["done", "failed", "open"].includes(state)) return { refused: new Refused(400, "Say state: done, failed or open.") };
      const serverPart = j.parts[part].who === "server";
      if (!mine && !(serverPart && by === "server") && !s.owed) return { refused: new Refused(409, "This job is not yours.") };
      const parts = { ...j.parts, [part]: { ...j.parts[part], state, said: str(s.said, 500), at, by } };
      if (s.result !== undefined) parts[part].result = s.result;
      next = { ...j, parts };
      next = afterPart(next, { part, state, by, at, said: str(s.said, 500), now, owed: Boolean(s.owed) });
    } else if (s.state === "waiting") {
      // The Mac gives it back (the drive was pulled before it started).
      if (!mine) { after = j; return {}; }
      next = { ...j, state: "waiting", parts: reopen(j.parts) };
      delete next.claim;
    } else {
      return { refused: new Refused(400, "Say claim, lease, progress, part or state.") };
    }
    after = dropUndefined(next);
    const jobs = doc.jobs.slice();
    jobs[i] = after;
    return { doc: { ...doc, jobs } };
  }, now);
  return after;
}

/** Where a job stands once a part has moved. */
function afterPart(j, { part, state, by, at, said, now, owed }) {
  const next = { ...j };
  const macParts = Object.entries(next.parts).filter(([, p]) => p.who !== "server");
  const serverParts = Object.entries(next.parts).filter(([, p]) => p.who === "server");
  if (state === "failed") {
    // Failed: with its words, no automatic retry.
    next.state = "failed";
    next.said = said || "It failed, and did not say why.";
    next.done_at = at;
    if (next.claim && next.claim.by !== "server") next.ran_on = next.claim.name;
    delete next.claim;
    return next;
  }
  if (state === "open") {
    // Not now (media folders with no template saved on this Mac yet): back
    // to waiting, no try counted.
    if (next.parts[part].who !== "server") {
      next.state = "waiting";
      delete next.claim;
      delete next.done_at;
      if (said) next.said = said;
    }
    return next;
  }
  if (macParts.every(([, p]) => p.state === "done")) {
    if (next.claim && next.claim.by !== "server") next.ran_on = next.claim.name;
    else if (owed && !next.ran_on) next.ran_on = by === "mac" ? "a Mac" : by;
    const open = serverParts.filter(([, p]) => p.state !== "done");
    if (open.length) {
      next.state = "running";
      next.claim = { by: "server", name: "the server", at, lease_until: null };
      delete next.progress;
    } else {
      next.state = "done";
      next.done_at = at;
      delete next.claim;
      delete next.said;
    }
  }
  return next;
}

/** His Try Again: needs-you or failed back to waiting, tries afresh. */
export async function retryJob(env, id, by = "", now = Date.now()) {
  let after = null;
  await changeJobs(env, (doc) => {
    const i = doc.jobs.findIndex((j) => j.id === id);
    if (i < 0) return { refused: new Refused(404, "No such job.") };
    const j = doc.jobs[i];
    if (!["needs-you", "failed"].includes(j.state)) return { refused: new Refused(409, j.state === "running" ? "It is running." : "It is not stopped.") };
    after = { ...j, state: "waiting", tries: 0, parts: reopen(j.parts), retried_by: str(by, 80), asked: j.asked };
    for (const k of ["said", "done_at", "claim"]) delete after[k];
    // a server part that failed is tried again too
    for (const [k, p] of Object.entries(after.parts)) if (p.who === "server" && p.state !== "done") after.parts[k] = { ...p, state: "open" };
    const jobs = doc.jobs.slice();
    jobs[i] = after;
    return { doc: { ...doc, jobs } };
  }, now);
  return after;
}

/** His Let It Go. A running job is left to finish. */
export async function cancelJob(env, id, by = "", now = Date.now()) {
  let after = null;
  await changeJobs(env, (doc) => {
    const i = doc.jobs.findIndex((j) => j.id === id);
    if (i < 0) return { refused: new Refused(404, "No such job.") };
    const j = doc.jobs[i];
    if (j.state === "running") return { refused: new Refused(409, `Running on ${macWords(j.claim && j.claim.name)}. Wait for it to finish.`) };
    if (["done", "cancelled"].includes(j.state)) { after = j; return {}; }
    after = { ...j, state: "cancelled", cancelled_by: str(by, 80), done_at: new Date(now).toISOString() };
    const jobs = doc.jobs.slice();
    jobs[i] = after;
    return { doc: { ...doc, jobs } };
  }, now);
  return after;
}

// ── presence ─────────────────────────────────────────────────────────────────

/** A Mac says it is here, with its drives and tools. */
export async function setPresence(env, said, now = Date.now()) {
  const s = isObject(said) ? said : {};
  const machine_id = str(s.machine_id, 80).trim();
  if (!machine_id) throw new Refused(400, "Say the machine id.");
  const mac = {
    machine_id,
    name: str(s.name, 80) || "Mac",
    runs_agents: s.runs_agents === true,
    drives: (Array.isArray(s.drives) ? s.drives : []).filter(isObject).slice(0, 40)
      .map((d) => ({ name: str(d.name, 80), short: str(d.short || d.name, 80), uuid: str(d.uuid, 80) })),
    tools: (Array.isArray(s.tools) ? s.tools : []).map((t) => str(t, 40)).filter(Boolean).slice(0, 20),
    seen: new Date(now).toISOString(),
  };
  for (let attempt = 0; attempt < 5; attempt++) {
    const got = await env.BUCKET.get(MACS_KEY);
    let macs = {};
    if (got) { try { const v = await got.json(); macs = isObject(v) && isObject(v.macs) ? v.macs : {}; } catch { macs = {}; } }
    const before = macs[machine_id];
    // When a drive was last seen, and on which Mac.
    const next = {};
    for (const [k, m] of Object.entries(macs)) if (m && m.seen && now - Date.parse(m.seen) < MACS_KEEP_MS) next[k] = m;
    next[machine_id] = { ...mac, ...(before && before.since ? { since: before.since } : { since: mac.seen }) };
    const saved = await env.BUCKET.put(MACS_KEY, JSON.stringify({ macs: next }), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: got ? { etagMatches: got.etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return next[machine_id];
  }
  throw new Refused(409, "The list of Macs kept changing. Try again.");
}

// ── the reading ──────────────────────────────────────────────────────────────

/** `{on, jobs, macs}` as the screens show them. Open jobs, or all kept. */
export async function listed(env, { all = false, project_id = "", drive = "" } = {}, now = Date.now()) {
  const sw = await macJobsOn(env);
  if (sw.on) await migrateOwed(env);
  const { doc } = await listOf(env);
  const macs = await macsOf(env);
  let jobs = prune(settle(doc.jobs, macs, now).jobs, now);
  if (!all) jobs = jobs.filter((j) => !["done", "cancelled"].includes(j.state) || (j.done_at && now - Date.parse(j.done_at) < 24 * 3600 * 1000));
  if (project_id) jobs = jobs.filter((j) => j.project_id === project_id);
  if (drive) jobs = jobs.filter((j) => String((j.needs || {}).drive || "").toLowerCase() === drive.toLowerCase());
  return {
    on: sw.on,
    jobs: jobs.map((j) => shown(j, macs, now)),
    macs: Object.values(macs).map((m) => ({ ...m, present: present(m, now) })),
    waiting: jobs.filter((j) => j.state === "waiting").length,
    needs_you: jobs.filter((j) => j.state === "needs-you" || j.state === "failed").length,
  };
}

// ── the owed list, carried across (newprojectdoor.js) ───────────────────────

const OWED_KEY = "s/newproject-owed.json";

/** Jobs for one owed item's open parts, under one group id. */
export function jobsFromOwed(item, now = Date.now()) {
  const out = [];
  const parts = isObject(item.parts) ? item.parts : {};
  const base = {
    project_id: str(item.id_project || item.page, 64), project_name: str(item.name, 200), by: str(item.by || "server", 80),
    group: item.id,
    args: { slug: item.slug, section: item.section, home: item.home, page: item.page || "", drive_folder: item.drive_folder || "", tier1: item.tier1, name: item.name },
  };
  if (isObject(parts.media) && parts.media.volume) {
    const j = newJob({ ...base, kind: "media-folders", needs: { drive: parts.media.volume } }, now);
    j.asked = item.asked || j.asked;
    j.owed_part = "media";
    if (parts.media.state !== "open") Object.assign(j, closedFrom(parts.media, j));
    out.push(j);
  }
  if (isObject(parts.sidebar)) {
    const j = newJob({ ...base, kind: "sidebar" }, now);
    j.asked = item.asked || j.asked;
    j.owed_part = "sidebar";
    if (parts.sidebar.state !== "open") Object.assign(j, closedFrom(parts.sidebar, j));
    out.push(j);
  }
  return out;
}

function closedFrom(p, j) {
  const part = Object.keys(j.parts)[0];
  const state = p.state === "done" ? "done" : "failed";
  return { state, done_at: p.at || j.asked, said: p.said || "", ran_on: p.by === "mac" ? "a Mac" : (p.by || ""),
    parts: { [part]: { ...j.parts[part], state, said: p.said || "", at: p.at, by: p.by } } };
}

/** The owed list's open items, copied across once (when the switch is on). */
export async function migrateOwed(env, now = Date.now()) {
  const { doc } = await listOf(env);
  if (doc.migrated_owed) return { copied: 0, already: true };
  const owed = await readJson(env, OWED_KEY);
  const items = isObject(owed) && Array.isArray(owed.items) ? owed.items.filter((x) => isObject(x) && x.state === "open") : [];
  let copied = 0;
  await changeJobs(env, (d) => {
    if (d.migrated_owed) return {};
    const have = new Set(d.jobs.map((j) => j.group).filter(Boolean));
    const add = [];
    for (const item of items) if (!have.has(item.id)) add.push(...jobsFromOwed(item, now).filter((j) => j.state === "waiting"));
    copied = add.length;
    return { doc: { ...d, jobs: [...d.jobs, ...add], migrated_owed: new Date(now).toISOString() } };
  }, now);
  return { copied };
}

/** New Project's owe(), as jobs: one per part, under one group (the item's id). */
export async function oweAsJobs(env, item, now = Date.now()) {
  const jobs = jobsFromOwed(item, now);
  await changeJobs(env, (doc) => ({ doc: { ...doc, jobs: [...doc.jobs, ...jobs] } }), now);
  return item;
}

/** A patch to an owed item (New Project sets the page once the row exists). */
export async function owedPatch(env, group, patch, now = Date.now()) {
  await changeJobs(env, (doc) => {
    let hit = false;
    const jobs = doc.jobs.map((j) => {
      if (j.group !== group) return j;
      hit = true;
      const next = { ...j, args: { ...j.args } };
      if (patch.page !== undefined) { next.args.page = patch.page; if (!next.project_id) next.project_id = str(patch.page, 64); }
      return next;
    });
    return hit ? { doc: { ...doc, jobs } } : {};
  }, now);
  return (await owedItems(env, true, now)).find((x) => x.id === group) || null;
}

/** The old owed door's answer, read from the jobs. */
export async function owedItems(env, all = false, now = Date.now()) {
  const { doc } = await listOf(env);
  const jobs = prune(settle(doc.jobs, await macsOf(env), now).jobs, now).filter((j) => j.group && j.owed_part);
  const groups = new Map();
  for (const j of jobs) {
    const a = j.args || {};
    const g = groups.get(j.group) || { id: j.group, asked: j.asked, by: j.by, state: "open", name: a.name || j.project_name,
      page: a.page || "", slug: a.slug, section: a.section, home: a.home, drive_folder: a.drive_folder, tier1: a.tier1, parts: {} };
    const p = j.parts[Object.keys(j.parts)[0]] || {};
    const state = j.state === "done" ? "done" : (j.state === "failed" || j.state === "needs-you" ? "failed" : (j.state === "cancelled" ? "done" : "open"));
    g.parts[j.owed_part] = { ...(j.owed_part === "media" ? { volume: j.needs.drive } : {}), state, ...(p.said ? { said: p.said } : {}), ...(p.at ? { at: p.at } : {}), ...(p.by ? { by: p.by } : {}) };
    groups.set(j.group, g);
  }
  const items = [...groups.values()].map((g) => {
    const open = Object.values(g.parts).some((p) => p.state === "open");
    return { ...g, state: open ? "open" : "done" };
  });
  return all ? items : items.filter((x) => x.state === "open");
}

/** The old door's PUT …/owed/<id> {part, state, said, by}: onto the group's job. */
export async function markOwedJob(env, group, said, now = Date.now()) {
  const part = str(said && said.part, 40);
  const { doc } = await listOf(env);
  const job = doc.jobs.find((j) => j.group === group && j.owed_part === part);
  if (!job) {
    if (!doc.jobs.some((j) => j.group === group)) return { status: 404, body: { problem: "No such item." } };
    return { status: 400, body: { problem: `This item owes no ${part || "part"}.` } };
  }
  const p = Object.keys(job.parts)[0];
  try {
    await changeJob(env, job.id, { part: p, state: said.state, said: said.said, by: str(said.by, 80) || "mac", owed: true }, now);
  } catch (e) {
    if (e instanceof Refused) return { status: e.status, body: { problem: e.message } };
    throw e;
  }
  const item = (await owedItems(env, true, now)).find((x) => x.id === group);
  return { status: 200, body: item };
}

// ── the server's parts ───────────────────────────────────────────────────────

/** Parts the server does once the Mac's are done: `fn(env, job) → said`. */
export const SERVER_PARTS = {
  async notion(env, job) {
    const scan = await readJson(env, `${SCAN_PREFIX}${job.id}.json`);
    if (!scan) throw new Error("The drive's scan never arrived. Index it again.");
    const { upsertVolumeIndex } = await import("./driveindex.js");
    return await upsertVolumeIndex(env, scan, { reporter: job.ran_on || "" });
  },
};

/** Run the server parts that are due: claimed by the server and not leased. */
export async function runServerParts(env, now = () => Date.now()) {
  const { doc } = await listOf(env);
  const due = settle(doc.jobs, {}, now()).jobs.filter((j) => j.state === "running" && j.claim && j.claim.by === "server" && !j.claim.lease_until);
  const out = [];
  for (const j0 of due) {
    let mine = null;
    try {
      await changeJobs(env, (d) => {
        const i = d.jobs.findIndex((j) => j.id === j0.id);
        const j = i >= 0 ? d.jobs[i] : null;
        if (!j || j.state !== "running" || !j.claim || j.claim.by !== "server" || j.claim.lease_until) return {};
        mine = { ...j, claim: { ...j.claim, lease_until: new Date(now() + LEASE_MS).toISOString() } };
        const jobs = d.jobs.slice();
        jobs[i] = mine;
        return { doc: { ...d, jobs } };
      }, now());
    } catch { continue; }
    if (!mine) continue;
    for (const [part, p] of Object.entries(mine.parts)) {
      if (p.who !== "server" || p.state === "done") continue;
      const fn = SERVER_PARTS[part];
      let state = "done", said = "";
      try {
        said = fn ? String((await fn(env, mine)) || "done") : "done";
      } catch (e) {
        state = "failed";
        said = e instanceof Handoff ? `Notion would not let the server write (${e.message}).` : String((e && e.message) || e).slice(0, 500);
      }
      const after = await changeJob(env, mine.id, { part, state, said, by: "server" }, now());
      out.push(after);
      if (state === "done" && part === "notion") {
        try { await env.BUCKET.delete(`${SCAN_PREFIX}${mine.id}.json`); } catch { /* kept, harmless */ }
      }
      if (state === "failed") break;
    }
  }
  return out;
}

/** The minute: the server's parts, then the one reminder for a long wait. */
export async function onMacJobsTimer(env, when = Date.now(), { send } = {}) {
  if (!(await macJobsOn(env)).on) return { off: true };
  const ran = await runServerParts(env, () => Date.now());
  const reminded = await remind(env, when, { send });
  return { ran: ran.length, reminded };
}

/** One push, once, for a job that has waited three days. Stamped first. */
export async function remind(env, now = Date.now(), { send } = {}) {
  const due = [];
  await changeJobs(env, (doc, macs) => {
    due.length = 0;
    const at = new Date(now).toISOString();
    const jobs = doc.jobs.map((j) => {
      if (j.reminded_at || !["waiting", "needs-you"].includes(j.state) || now - Date.parse(j.asked) < REMIND_MS) return j;
      due.push(shown(j, macs, now));
      return { ...j, reminded_at: at };
    });
    return due.length ? { doc: { ...doc, jobs } } : {};
  }, now);
  const push = send || (async (e, note) => (await import("./push.js")).send(e, note));
  for (const j of due) {
    const what = (j.needs || {}).drive || (j.needs.mac === "studio" ? "the Studio Mac" : "a Mac");
    const who = j.project_name || j.title;
    await push(env, { title: who, body: `${who} is still waiting for ${what}`, level: "passive", thread: "macjobs", data: { route: "waiting" } });
  }
  return due.map((j) => j.id);
}

// ── the cloud methods (phone and router) ────────────────────────────────────

export const CLOUD = new Set(["mac_jobs", "mac_job_retry", "mac_job_cancel", "mac_job_index"]);

/** Answer one of the cloud methods. `{state, result}` like answerHere. */
export async function cloudAnswer(env, method, args) {
  const list = Array.isArray(args) ? args : [];
  try {
    if (method === "mac_jobs") {
      const o = isObject(list[0]) ? list[0] : {};
      return { state: "done", result: await listed(env, { all: o.all === true, project_id: str(o.project_id, 64), drive: str(o.drive, 80) }) };
    }
    if (method === "mac_job_retry") return { state: "done", result: { ok: true, job: await retryJob(env, str(list[0], 12), str(list[1] || "phone", 80)) } };
    if (method === "mac_job_cancel") return { state: "done", result: { ok: true, job: await cancelJob(env, str(list[0], 12), str(list[1] || "phone", 80)) } };
    if (method === "mac_job_index") {
      const drive = str(list[0], 80).trim();
      const job = await addJob(env, { kind: "index", needs: { drive }, by: str(list[1] || "phone", 80) });
      return { state: "done", result: { ok: true, job: shown(job, await macsOf(env)) } };
    }
  } catch (e) {
    if (e instanceof Refused) return { state: "done", result: { ok: false, why: e.message } };
    return { state: "failed", error: String((e && e.message) || e).slice(0, 500) };
  }
  return null;
}

// ── the look ─────────────────────────────────────────────────────────────────

/** What turning the switch on would do now. Writes nothing. */
export async function look(env, now = Date.now()) {
  const sw = await macJobsOn(env);
  const { doc } = await listOf(env);
  const macs = await macsOf(env);
  const owed = await readJson(env, OWED_KEY);
  const open = isObject(owed) && Array.isArray(owed.items) ? owed.items.filter((x) => isObject(x) && x.state === "open") : [];
  const would = doc.migrated_owed ? [] : open.flatMap((it) => jobsFromOwed(it, now).filter((j) => j.state === "waiting"));
  return {
    switch: sw,
    migrated_owed: doc.migrated_owed || null,
    owed_open: open.length,
    would_copy: would.map((j) => shown(j, macs, now)),
    jobs: prune(settle(doc.jobs, macs, now).jobs, now).map((j) => shown(j, macs, now)),
    macs: Object.values(macs).map((m) => ({ ...m, present: present(m, now) })),
    kinds: Object.keys(KINDS), media_kinds: [...MEDIA_KINDS],
    notion: cloudReady(env),
  };
}

// ── the doors (studio.js) ────────────────────────────────────────────────────

function reply(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
}

/** `/console/studio/macjobs/…` */
export async function macJobsDoor(env, rest, method, readBody, ctx, url) {
  const body = async (limit) => {
    try { return await readBody(limit); } catch { throw new Refused(400, "That is not JSON, or it is too long."); }
  };
  try {
    if (rest.length === 1) {
      if (method === "GET") {
        const q = url ? url.searchParams : new URLSearchParams();
        return reply(await listed(env, { all: q.get("all") === "1", project_id: q.get("project") || "", drive: q.get("drive") || "" }));
      }
      if (method !== "POST") return reply({ problem: "Wrong method." }, 405);
      return reply(shown(await addJob(env, await body(64 * 1024)), await macsOf(env)));
    }
    const sub = rest[1];
    if (sub === "switch" && rest.length === 2) {
      if (method === "GET") return reply(await macJobsOn(env));
      if (method !== "PUT") return reply({ problem: "Wrong method." }, 405);
      return reply(await setSwitch(env, await body(4096)));
    }
    if (sub === "look" && rest.length === 2) {
      if (method !== "GET") return reply({ problem: "Wrong method." }, 405);
      return reply(await look(env));
    }
    if (sub === "mac" && rest.length === 2) {
      if (method !== "PUT") return reply({ problem: "Wrong method." }, 405);
      return reply(await setPresence(env, await body(16 * 1024)));
    }
    if (sub === "tick" && rest.length === 2) {
      if (method !== "POST") return reply({ problem: "Wrong method." }, 405);
      return reply(await onMacJobsTimer(env));
    }
    if (!ID.test(String(sub))) return reply({ problem: "No such job." }, 404);
    if (rest.length === 2) {
      if (method !== "PUT") return reply({ problem: "Wrong method." }, 405);
      const said = await body(512 * 1024);
      const after = await changeJob(env, sub, said);
      // An index job's Mac part done: the server writes Notion now, beside the reply.
      if (after && after.state === "running" && after.claim && after.claim.by === "server" && ctx && ctx.waitUntil) {
        ctx.waitUntil(runServerParts(env).catch((e) => console.error("macjobs:", String((e && e.stack) || e))));
      }
      return reply(shown(after, await macsOf(env)));
    }
    if (rest.length === 3 && rest[2] === "scan") {
      if (method !== "PUT") return reply({ problem: "Wrong method." }, 405);
      const scan = await body(4 * 1024 * 1024);
      if (!isObject(scan) || !Array.isArray(scan.entries) || !scan.volume) return reply({ problem: "That is not a drive's scan." }, 400);
      await env.BUCKET.put(`${SCAN_PREFIX}${sub}.json`, JSON.stringify(scan), { httpMetadata: { contentType: "application/json" } });
      return reply({ ok: true, entries: scan.entries.length });
    }
    if (rest.length === 3 && rest[2] === "retry") {
      if (method !== "POST") return reply({ problem: "Wrong method." }, 405);
      const said = await body(4096).catch(() => ({}));
      return reply(shown(await retryJob(env, sub, said && said.by), await macsOf(env)));
    }
    if (rest.length === 3 && rest[2] === "cancel") {
      if (method !== "POST") return reply({ problem: "Wrong method." }, 405);
      const said = await body(4096).catch(() => ({}));
      return reply(shown(await cancelJob(env, sub, said && said.by), await macsOf(env)));
    }
    return reply({ problem: "No such door." }, 404);
  } catch (e) {
    if (e instanceof Refused) return reply({ problem: e.message }, e.status);
    throw e;
  }
}
