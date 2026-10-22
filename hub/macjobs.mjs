#!/usr/bin/env node
/**
 * **The Mac jobs list** (src/macjobs.js, stage 5 step 7 piece A), in memory:
 * a bucket that compares-and-sets like R2's, two made-up Macs, a clock.
 *
 * - claims: only from waiting, once, even with two Macs at it at once;
 * - the Studio's 30-second head start, and "pressed here" going first;
 * - a lease that runs out: retry-safe back to waiting, not-safe to needs-you;
 *   three times and it is needs-you; Try Again and Let It Go;
 * - a failed part stays failed; media folders with no template stays open;
 * - one reminder after three days, never two;
 * - the owed list carried across once, and the old door answered from it;
 * - the hard rule: a job that waits for a drive is template folders or a scan;
 * - the words under each job;
 * - an index job: the Mac's scan, then the server's Notion write (a fake).
 *
 *     node hub/macjobs.mjs
 */
import { register } from "node:module";
register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

const M = await import("./src/macjobs.js");
const door = await import("./src/newprojectdoor.js");
const { readFileSync, readdirSync } = await import("node:fs");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(84)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 400)}`}`);
};
const refused = async (fn, re) => { try { await fn(); return false; } catch (e) { return e instanceof M.Refused && (!re || re.test(e.message)); } };

function bucket() {
  const m = new Map(); let n = 0;
  return {
    m,
    async get(k) { return m.has(k) ? { etag: String(m.get(k).etag), json: async () => JSON.parse(m.get(k).body) } : null; },
    async head(k) { return m.has(k) ? {} : null; },
    async delete(k) { m.delete(k); },
    async put(k, v, opts) {
      const held = m.get(k);
      const only = opts && opts.onlyIf;
      if (only && only.etagMatches && (!held || String(held.etag) !== only.etagMatches)) return null;
      if (only && only.etagDoesNotMatch === "*" && held) return null;
      m.set(k, { body: String(v), etag: ++n }); return {};
    },
  };
}
const T0 = Date.parse("2026-10-13T18:00:00Z"); // a Tuesday, 11 am in Vancouver
const MIN = 60_000, DAY = 86_400_000;
const env0 = () => ({ BUCKET: bucket() });
const STUDIO = { machine_id: "STUDIO-1", name: "Studio Mac", runs_agents: true, drives: [{ name: "wd-1", short: "wd-1", uuid: "U-WD1" }], tools: ["cwebp", "mysides"] };
const LAPTOP = { machine_id: "LAPTOP-1", name: "Laptop", runs_agents: false, drives: [{ name: "zz-scratch-media", short: "zz-scratch-media", uuid: "U-ZZ" }], tools: ["cwebp"] };

// ── the hard rule ────────────────────────────────────────────────────────────
console.log("the hard rule");
{
  const env = env0();
  check("MEDIA_KINDS is exactly template folders and the read-only scan", JSON.stringify([...M.MEDIA_KINDS].sort()) === '["index","media-folders"]');
  check("a sidebar job that names a drive is refused", await refused(() => M.addJob(env, { kind: "sidebar", needs: { drive: "wd-4" }, project_name: "X" }, T0), /create-only/));
  M.KINDS["zz-planted"] = { retry_safe: true, needs_default: {}, parts: ["x"] };
  check("a planted kind that waits for a drive is refused (the guard is the set, not the list)", await refused(() => M.addJob(env, { kind: "zz-planted", needs: { drive: "wd-1" } }, T0), /create-only/));
  check("…and a planted kind with no drive is taken", Boolean(await M.addJob(env, { kind: "zz-planted", needs: {} }, T0)));
  delete M.KINDS["zz-planted"];
  check("an unknown kind is refused", await refused(() => M.addJob(env, { kind: "media-move", needs: { drive: "wd-1" } }, T0)));
  check("media folders without a drive are refused", await refused(() => M.addJob(env, { kind: "media-folders", args: { slug: "a" } }, T0), /drive/));
  check("media folders without a folder name are refused", await refused(() => M.addJob(env, { kind: "media-folders", needs: { drive: "wd-1" } }, T0), /folder name/));
  // No line in macjobs.js names /Volumes or a file-moving call.
  const src = readFileSync(new URL("./src/macjobs.js", import.meta.url), "utf8") + readFileSync(new URL("./src/driveindex.js", import.meta.url), "utf8");
  check("the server's list never names /Volumes", !/\/Volumes/.test(src));
  const bigMoveSection = /big-move kinds \(moves builder\)/.test(src);
  check("KINDS has the marked section for the moves builder", bigMoveSection);
}

// ── claims ───────────────────────────────────────────────────────────────────
console.log("claims");
{
  const env = env0();
  await M.setPresence(env, STUDIO, T0);
  await M.setPresence(env, LAPTOP, T0);
  const j = await M.addJob(env, { kind: "media-folders", project_name: "Northern Lights", needs: { drive: "wd-1" }, args: { slug: "northern-lights" } }, T0);
  check("a new job waits, with a 12-hex id and the mockup's title", j.state === "waiting" && /^[0-9a-f]{12}$/.test(j.id) && j.title === "Make media folders · Northern Lights", j.title);
  check("the laptop (no wd-1) cannot claim it", await refused(() => M.changeJob(env, j.id, { claim: true, by: LAPTOP.machine_id }, T0 + 1000), /not plugged/));
  const [a, b] = await Promise.all([
    M.changeJob(env, j.id, { claim: true, by: STUDIO.machine_id }, T0 + 1000),
    M.changeJob(env, j.id, { claim: true, by: STUDIO.machine_id + "-twin" }, T0 + 1000).catch((e) => ({ err: e.message })),
  ]);
  check("one claim wins", a.state === "running" && a.claim.by === STUDIO.machine_id, JSON.stringify(a));
  check("the lease is five minutes", Date.parse(a.claim.lease_until) - (T0 + 1000) === M.LEASE_MS);
  const again = await M.changeJob(env, j.id, { claim: true, by: STUDIO.machine_id }, T0 + 2000);
  check("a second claim is handed the job as it stands", again.claim.by === STUDIO.machine_id && again.claim.at === a.claim.at);
  // two Macs at a job both can do
  const any = await M.addJob(env, { kind: "zz-any", needs: {} }, T0).catch(() => null);
  check("kinds outside the registry are refused", any === null);
  M.KINDS["zz-any"] = { retry_safe: true, needs_default: { mac: "any" }, parts: ["x"] };
  const k = await M.addJob(env, { kind: "zz-any", project_name: "P" }, T0);
  check("the laptop waits out the Studio's head start", await refused(() => M.changeJob(env, k.id, { claim: true, by: LAPTOP.machine_id }, T0 + 10_000), /Studio Mac goes first/));
  const both = await Promise.allSettled([
    M.changeJob(env, k.id, { claim: true, by: LAPTOP.machine_id }, T0 + 31_000),
    M.changeJob(env, k.id, { claim: true, by: STUDIO.machine_id }, T0 + 31_000),
  ]);
  const k2 = (await M.jobsFor(env, {}, T0 + 31_000)).find((x) => x.id === k.id);
  check("two Macs racing after it: exactly one holds it", k2.state === "running" && [LAPTOP.machine_id, STUDIO.machine_id].includes(k2.claim.by)
    && both.filter((x) => x.status === "fulfilled" && x.value.claim && x.value.claim.by === (x.value.claim.by)).length >= 1, JSON.stringify(k2.claim));
  const k3 = await M.addJob(env, { kind: "zz-any", project_name: "P", by_machine: LAPTOP.machine_id }, T0);
  const got = await M.changeJob(env, k3.id, { claim: true, by: LAPTOP.machine_id, local: true }, T0 + 1000);
  check("pressed on the laptop: the laptop takes it at once (local first)", got.claim && got.claim.by === LAPTOP.machine_id);
  // the Studio asleep: no head start
  const env2 = env0();
  await M.setPresence(env2, STUDIO, T0 - 10 * MIN);
  await M.setPresence(env2, LAPTOP, T0);
  const k4 = await M.addJob(env2, { kind: "zz-any", project_name: "P" }, T0);
  check("the Studio asleep: the laptop takes it straight away", (await M.changeJob(env2, k4.id, { claim: true, by: LAPTOP.machine_id }, T0 + 1000)).claim.by === LAPTOP.machine_id);
  delete M.KINDS["zz-any"];
  // studio only
  const s = await M.addJob(env, { kind: "sidebar", project_name: "Northern Lights" }, T0);
  check("a sidebar job is the Studio's", await refused(() => M.changeJob(env, s.id, { claim: true, by: LAPTOP.machine_id }, T0 + 40_000), /Studio/));
  check("…which takes it", (await M.changeJob(env, s.id, { claim: true, by: STUDIO.machine_id }, T0 + 40_000)).state === "running");
  const fresh = await M.addJob(env, { kind: "sidebar", project_name: "Q" }, T0);
  check("an unknown Mac must say who it is first", await refused(() => M.changeJob(env, fresh.id, { claim: true, by: "NOBODY" }, T0), /Say which Mac/));
  // drive by uuid
  const u = await M.addJob(env, { kind: "media-folders", project_name: "U", needs: { drive: "wd-1", drive_uuid: "OTHER-UUID" }, args: { slug: "u" } }, T0);
  check("a drive named wd-1 with another uuid is not that drive", await refused(() => M.changeJob(env, u.id, { claim: true, by: STUDIO.machine_id }, T0 + 1000), /not plugged/));
  const u2 = await M.addJob(env, { kind: "media-folders", project_name: "U", needs: { drive: "wd-1", drive_uuid: "u-wd1" }, args: { slug: "u" } }, T0);
  check("…and the same uuid is", (await M.changeJob(env, u2.id, { claim: true, by: STUDIO.machine_id }, T0 + 1000)).state === "running");
  // parts
  const done = await M.changeJob(env, j.id, { part: "media", state: "done", said: "Media folders made on wd-1", by: STUDIO.machine_id }, T0 + 5000);
  check("its part done: the job is done, on the Studio Mac", done.state === "done" && done.ran_on === "Studio Mac" && !done.claim, JSON.stringify(done));
  check("a part from a Mac not holding the job is refused", await refused(() => M.changeJob(env, s.id, { part: "sidebar", state: "done", by: LAPTOP.machine_id }, T0 + 41_000), /not yours/));
}

// ── leases, tries, failures ─────────────────────────────────────────────────
console.log("leases and retries");
{
  const env = env0();
  await M.setPresence(env, STUDIO, T0);
  const j = await M.addJob(env, { kind: "media-folders", project_name: "N", needs: { drive: "wd-1" }, args: { slug: "n" } }, T0);
  let t = T0;
  for (let i = 1; i <= 2; i++) {
    await M.changeJob(env, j.id, { claim: true, by: STUDIO.machine_id }, t);
    t += M.LEASE_MS + 1000;
    const after = (await M.jobsFor(env, {}, t)).find((x) => x.id === j.id);
    check(`a retry-safe job whose lease ran out goes back to waiting (try ${i})`, after.state === "waiting" && after.tries === i && after.parts.media.state === "open", JSON.stringify(after));
  }
  await M.changeJob(env, j.id, { claim: true, by: STUDIO.machine_id }, t);
  // renewing keeps it
  await M.changeJob(env, j.id, { lease: true, by: STUDIO.machine_id }, t + 4 * MIN);
  check("a renewed lease keeps it running", (await M.jobsFor(env, {}, t + 6 * MIN)).find((x) => x.id === j.id).state === "running");
  t += 4 * MIN + M.LEASE_MS + 1000;
  const third = (await M.jobsFor(env, {}, t)).find((x) => x.id === j.id);
  check("the third lease that runs out makes it needs-you", third.state === "needs-you" && third.tries === 3 && /3 times/.test(third.said), JSON.stringify(third));
  check("…shown with the Needs You pill", M.shown(third).pill === "Needs You");
  const back = await M.retryJob(env, j.id, "Nathaniel", t);
  check("Try Again: waiting, tries afresh", back.state === "waiting" && back.tries === 0);
  // not retry-safe
  M.KINDS["zz-unsafe"] = { retry_safe: false, needs_default: { mac: "studio" }, parts: ["x"] };
  const u = await M.addJob(env, { kind: "zz-unsafe", project_name: "P" }, t);
  await M.changeJob(env, u.id, { claim: true, by: STUDIO.machine_id }, t);
  await M.changeJob(env, u.id, { progress: { pct: 40, text: "copying 4 of 10" }, by: STUDIO.machine_id }, t + MIN);
  const u2 = (await M.jobsFor(env, {}, t + MIN + M.LEASE_MS + 1000)).find((x) => x.id === u.id);
  check("a not-safe job whose lease ran out is needs-you, with its last words", u2.state === "needs-you" && /Studio Mac · copying 4 of 10/.test(u2.said), JSON.stringify(u2));
  check("…never started again on its own", u2.tries === 1 && !u2.claim);
  const gone = await M.cancelJob(env, u.id, "Nathaniel", t + 10 * MIN);
  check("Let It Go: cancelled, with who", gone.state === "cancelled" && gone.cancelled_by === "Nathaniel");
  delete M.KINDS["zz-unsafe"];
  // failed part
  const f = await M.addJob(env, { kind: "media-folders", project_name: "F", needs: { drive: "wd-1" }, args: { slug: "f" } }, t);
  await M.changeJob(env, f.id, { claim: true, by: STUDIO.machine_id }, t);
  const ff = await M.changeJob(env, f.id, { part: "media", state: "failed", said: "Permission denied", by: STUDIO.machine_id }, t + 1000);
  check("a failed part: failed, in its words", ff.state === "failed" && ff.said === "Permission denied");
  check("…and stays failed (no automatic retry)", (await M.jobsFor(env, {}, t + 10 * DAY)).find((x) => x.id === f.id).state === "failed");
  // media folders with no template: stays open
  const o = await M.addJob(env, { kind: "media-folders", project_name: "O", needs: { drive: "wd-1" }, args: { slug: "o" } }, t);
  await M.changeJob(env, o.id, { claim: true, by: STUDIO.machine_id }, t);
  const oo = await M.changeJob(env, o.id, { part: "media", state: "open", said: "No folder template on this Mac yet", by: STUDIO.machine_id }, t + 1000);
  check("media folders with no template saved stays open (waiting, no try)", oo.state === "waiting" && oo.tries === 0 && !oo.claim);
  check("a running job cannot be let go", await (async () => {
    await M.changeJob(env, o.id, { claim: true, by: STUDIO.machine_id }, t + 2000);
    return refused(() => M.cancelJob(env, o.id, "N", t + 3000), /Wait for it/);
  })());
  // keeping
  const kept = await M.jobsFor(env, {}, t + 31 * DAY);
  check("finished jobs go after 30 days; open ones never", !kept.some((x) => x.id === gone.id) && kept.some((x) => x.id === f.id));
}

// ── moves builder's three ────────────────────────────────────────────────────
console.log("for the moves builder");
{
  const env = env0();
  await M.setPresence(env, STUDIO, T0);
  M.KINDS["zz-move"] = { retry_safe: true, needs_default: { mac: "studio" }, parts: ["x"] };
  const a = await M.addJob(env, { kind: "zz-move", project_id: "P1", project_name: "P", move_id: "MOVE1" }, T0);
  const b = await M.addJob(env, { kind: "zz-move", project_id: "P1", project_name: "P", move_id: "MOVE1" }, T0);
  await M.addJob(env, { kind: "zz-move", project_id: "P2", project_name: "Q", move_id: "MOVE2" }, T0);
  await M.changeJob(env, b.id, { claim: true, by: STUDIO.machine_id }, T0 + 1000);
  check("jobsFor by project", (await M.jobsFor(env, { project_id: "P1" }, T0)).length === 2);
  check("jobsFor by move", (await M.jobsFor(env, { move_id: "MOVE2" }, T0)).length === 1);
  const c = await M.cancelJobs(env, { move_id: "MOVE1", by: "undo" }, T0 + 2000);
  check("cancelJobs lets go the waiting one and names the running one", c.cancelled.join() === a.id && c.running.join() === b.id, JSON.stringify(c));
  delete M.KINDS["zz-move"];
}

// ── the reminder ─────────────────────────────────────────────────────────────
console.log("the reminder");
{
  const env = env0();
  const j = await M.addJob(env, { kind: "media-folders", project_name: "Northern Lights", needs: { drive: "wd-4" }, args: { slug: "northern-lights" } }, T0);
  const sent = [];
  const send = async (e, note) => { sent.push(note); return { ok: true }; };
  check("not before three days", (await M.remind(env, T0 + 2 * DAY, { send })).length === 0 && sent.length === 0);
  await M.remind(env, T0 + 3 * DAY + 1, { send });
  check("one push after three days, in the mockup's words", sent.length === 1 && sent[0].body === "Northern Lights is still waiting for wd-4", JSON.stringify(sent));
  await M.remind(env, T0 + 4 * DAY, { send });
  await M.remind(env, T0 + 9 * DAY, { send });
  check("never a second", sent.length === 1);
  check("stamped reminded_at", Boolean((await M.jobsFor(env, {}, T0 + 4 * DAY)).find((x) => x.id === j.id).reminded_at));
}

// ── the owed list ────────────────────────────────────────────────────────────
console.log("the owed list carried across");
{
  const env = env0();
  const owed = { items: [
    { id: "aaaaaaaaaaaa", asked: new Date(T0 - DAY).toISOString(), by: "server", state: "open", name: "Old One", page: "p1", slug: "old-one", section: "projects", home: "projects", drive_folder: "https://drive/x", tier1: true,
      parts: { media: { volume: "wd-4", state: "open" }, sidebar: { state: "open" } } },
    { id: "bbbbbbbbbbbb", asked: new Date(T0 - DAY).toISOString(), by: "server", state: "open", name: "Half", page: "p2", slug: "half", section: "gigs", home: "gigs", tier1: false,
      parts: { media: { volume: "wd-1", state: "done", said: "made", by: "mac", at: new Date(T0).toISOString() }, sidebar: { state: "open" } } },
    { id: "cccccccccccc", asked: new Date(T0 - DAY).toISOString(), by: "server", state: "done", done_at: new Date(T0).toISOString(), name: "Done", slug: "done", parts: { sidebar: { state: "done" } } },
  ] };
  await env.BUCKET.put("s/newproject-owed.json", JSON.stringify(owed));
  const look = await M.look(env, T0);
  check("the look says what it would copy, and writes nothing", look.would_copy.length === 3 && !env.BUCKET.m.has(M.JOBS_KEY), JSON.stringify(look.would_copy.map((x) => x.kind)));
  check("switch off: the old door answers from the old list", (await door.owedList(env)).items.length === 2);
  await M.setSwitch(env, { on: true, by: "check" });
  const jobs = await M.jobsFor(env, {}, T0);
  check("switched on: open parts copied across once (3 jobs)", jobs.length === 3 && jobs.every((j) => j.state === "waiting"), JSON.stringify(jobs.map((j) => [j.kind, j.state])));
  await M.migrateOwed(env);
  await M.setSwitch(env, { on: true, by: "again" });
  check("…and only once", (await M.jobsFor(env, {}, T0)).length === 3);
  const media = jobs.find((j) => j.kind === "media-folders");
  check("the media job waits for its drive, with the item's folder name", media.needs.drive === "wd-4" && media.args.slug === "old-one" && media.project_name === "Old One");
  const items = (await door.owedList(env)).items;
  check("the old door answers from the new list", items.length === 2 && items.find((x) => x.id === "aaaaaaaaaaaa").parts.media.volume === "wd-4", JSON.stringify(items));
  const marked = await door.markOwed(env, "aaaaaaaaaaaa", { part: "media", state: "done", said: "Media folders made", by: "mac" });
  check("an old Mac marking a part through the old door marks the job", marked.status === 200 && marked.body.parts.media.state === "done", JSON.stringify(marked));
  check("…the job is done", (await M.jobsFor(env, {}, T0)).find((j) => j.id === media.id).state === "done");
  const made = await door.owe(env, { name: "New One", page: "", slug: "new-one", section: "projects", home: "projects", drive_folder: "u", tier1: true, parts: { media: { volume: "zz-scratch-media", state: "open" }, sidebar: { state: "open" } } });
  const mine = (await M.jobsFor(env, {}, Date.now())).filter((j) => j.group === made.id);
  check("New Project's owe() writes two jobs under one group", mine.length === 2 && mine.some((j) => j.kind === "media-folders" && j.needs.drive === "zz-scratch-media"));
  check("the old owed file is left as it was", JSON.parse(env.BUCKET.m.get("s/newproject-owed.json").body).items.length === 3);
}

// ── the words ────────────────────────────────────────────────────────────────
console.log("the words");
{
  const now = Date.parse("2026-10-16T19:00:00Z"); // Friday
  const tue = Date.parse("2026-10-13T20:00:00Z");
  const macs = { S: { ...STUDIO, seen: new Date(now - MIN).toISOString() }, L: { ...LAPTOP, seen: new Date(now - MIN).toISOString() } };
  const j = M.newJob({ kind: "media-folders", project_name: "Northern Lights", needs: { drive: "wd-4" }, args: { slug: "nl" } }, tue);
  check("Waiting for wd-4 · unplugged · since Tuesday", M.waitingWords(j, macs, now) === "Waiting for wd-4 · unplugged · since Tuesday", M.waitingWords(j, macs, now));
  const z = M.newJob({ kind: "media-folders", project_name: "Z", needs: { drive: "zz-scratch-media" }, args: { slug: "z" } }, now - MIN);
  check("plugged into the laptop: Waiting for the laptop", M.waitingWords(z, macs, now).startsWith("Waiting for the laptop"), M.waitingWords(z, macs, now));
  check("…and unplugged once the laptop says so", M.waitingWords(z, { ...macs, L: { ...macs.L, drives: [] } }, now) === "Waiting for zz-scratch-media · unplugged · since today");
  M.KINDS["zz-any"] = { retry_safe: true, needs_default: { mac: "any" }, parts: ["x"] };
  const a = M.newJob({ kind: "zz-any", project_name: "P", sub: "the server did Notion, Drive and the portal" }, now);
  check("Waiting for a Mac · the server did Notion, Drive and the portal", M.waitingWords(a, {}, now) === "Waiting for a Mac · the server did Notion, Drive and the portal", M.waitingWords(a, {}, now));
  delete M.KINDS["zz-any"];
  const s = M.newJob({ kind: "sidebar", project_name: "P" }, now);
  check("Waiting for the Studio Mac", M.waitingWords(s, macs, now) === "Waiting for the Studio Mac");
  check("Running on Studio Mac", M.waitingWords({ ...j, state: "running", claim: { by: "S", name: "Studio Mac" } }, macs, now) === "Running on Studio Mac");
  check("Done on Studio Mac", M.waitingWords({ ...j, state: "done", ran_on: "Studio Mac", done_at: new Date(now - MIN).toISOString() }, macs, now) === "Done on Studio Mac");
  check("Done yesterday on the laptop", M.waitingWords({ ...j, state: "done", ran_on: "Laptop", done_at: new Date(now - DAY).toISOString() }, macs, now) === "Done yesterday on the laptop");
  check("pills", ["waiting", "running", "done", "needs-you", "failed"].map((state) => M.pillOf({ state })).join() === "Waiting,Running,Done,Needs You,Needs You");
}

// ── presence and the switch's doors ─────────────────────────────────────────
console.log("presence");
{
  const env = env0();
  await M.setPresence(env, LAPTOP, T0);
  await M.setPresence(env, { ...LAPTOP, drives: [] }, T0 + MIN);
  const macs = await M.macsOf(env);
  check("presence replaced, `since` kept", macs[LAPTOP.machine_id].drives.length === 0 && macs[LAPTOP.machine_id].since === new Date(T0).toISOString());
  check("presence without a machine id is refused", await refused(() => M.setPresence(env, { name: "x" }, T0)));
  check("the switch is off until thrown", !(await M.macJobsOn(env)).on);
  check("cloud methods answer only while on (cloudAnswer itself always)", (await M.cloudAnswer(env, "mac_jobs", [{}])).result.on === false);
}

// ── an index job, end to end ────────────────────────────────────────────────
console.log("an index job");
{
  const env = env0();
  await M.setPresence(env, LAPTOP, T0);
  const j = await M.addJob(env, { kind: "index", needs: { drive: "zz-scratch-media" }, by: "phone" }, T0);
  const dup = await M.addJob(env, { kind: "index", needs: { drive: "zz-scratch-media" }, by: "phone" }, T0);
  check("a second Index Now for the same drive is the same job", dup.id === j.id);
  await M.changeJob(env, j.id, { claim: true, by: LAPTOP.machine_id }, Date.now() - 40_000);
  await env.BUCKET.put(`${M.SCAN_PREFIX}${j.id}.json`, JSON.stringify({ volume: "zz-scratch-media", short: "zz-scratch-media", entries: [{ name: "zz-step7-a", parent: "projects", year: "2026", size: "1 MB" }], free_bytes: 40e6, total_bytes: 50e6 }));
  const mid = await M.changeJob(env, j.id, { part: "scan", state: "done", said: "1 folder", by: LAPTOP.machine_id });
  check("the Mac's scan done: running on the server", mid.state === "running" && mid.claim.by === "server" && mid.ran_on === "Laptop");
  // a fake Notion behind driveindex
  const calls = [];
  M.SERVER_PARTS.notion = async (e, job) => {
    const scan = JSON.parse(e.BUCKET.m.get(`${M.SCAN_PREFIX}${job.id}.json`).body);
    const { upsertVolumeIndex } = await import("./src/driveindex.js");
    const notion = {
      post: async (p, b) => { calls.push(["POST", p, b]); return p.endsWith("/query") ? { results: [], has_more: false } : { id: "new" }; },
      patch: async (p, b) => { calls.push(["PATCH", p, b]); return {}; },
    };
    return upsertVolumeIndex(e, scan, { reporter: job.ran_on, notion });
  };
  const ran = await M.runServerParts(env);
  const fin = (await M.jobsFor(env, {})).find((x) => x.id === j.id);
  check("the server writes Notion, and the job is done on the laptop", ran.length === 1 && fin.state === "done" && /zz-scratch-media \(via Laptop\): 1 added/.test(fin.parts.notion.said), JSON.stringify(fin.parts));
  check("…a Drive Contents row made under its data source", calls.some(([m, p, b]) => m === "POST" && p === "pages" && b.parent.data_source_id === "86d77bbd-736b-829e-e17a-12ac039c951f" && b.properties["Folder Name"].title[0].text.content === "zz-step7-a"));
  check("…the scan is dropped after", !env.BUCKET.m.has(`${M.SCAN_PREFIX}${j.id}.json`));
  check("Done on the laptop", M.waitingWords(fin, {}, Date.now()) === "Done on the laptop", M.waitingWords(fin, {}, Date.now()));
  check("a second run does nothing", (await M.runServerParts(env)).length === 0);
}

console.log(`\nmacjobs: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
