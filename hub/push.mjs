#!/usr/bin/env node
/**
 * **Alerts on the phone, from the server** — `src/push.js`, the Mac's
 * `studio/push.py` ported (2026-10-11, stage 3 step 4). No network: Apple is
 * a stand-in that says what Apple says.
 *
 * - the provider token is a real ES256 JWT that checks out against the key's
 *   public half, is reused for 45 minutes, and a new one is not made more
 *   than once in 20;
 * - phones register once, tidy tokens only, and the Mac's list merges in;
 * - a send goes to every phone with the Mac's headers and payload; a token
 *   from the other service is tried there and remembered; a dead token is
 *   dropped; a rejection that is Apple's or ours leaves the token alone;
 * - with no key, or no phones, nothing is sent and nothing breaks;
 * - the Notion link's questions become alerts that open the questions.
 *
 *     node hub/push.mjs
 */
import { webcrypto } from "node:crypto";
import * as P from "./src/push.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 72).padEnd(74)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 400)}`}`);
};

function bucket() {
  const m = new Map(); let n = 0;
  return {
    m,
    async get(k) { return m.has(k) ? { etag: String(m.get(k).etag), json: async () => JSON.parse(m.get(k).body) } : null; },
    async put(k, v, opts) {
      const held = m.get(k);
      const only = opts && opts.onlyIf;
      if (only && only.etagMatches && (!held || String(held.etag) !== only.etagMatches)) return null;
      if (only && only.etagDoesNotMatch === "*" && held) return null;
      m.set(k, { body: String(v), etag: ++n }); return {};
    },
  };
}
const toPem = (der) => `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString("base64").match(/.{1,64}/g).join("\n")}\n-----END PRIVATE KEY-----\n`;
const pair = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const PEM = toPem(await webcrypto.subtle.exportKey("pkcs8", pair.privateKey));
const mkEnv = (extra = {}) => ({ BUCKET: bucket(), APNS_KEY: PEM, APNS_KEY_ID: "ABC123DEFG", ...extra });
const T1 = "a".repeat(64), T2 = "b".repeat(64), T3 = "c".repeat(64);
const MIN = 60_000;
const t0 = Date.UTC(2026, 9, 11, 12, 0, 0);

// ── the key ──────────────────────────────────────────────────────────────────
let env = mkEnv();
check("a key and its id make it configured; either missing does not", P.configured(env) && !P.configured({ ...env, APNS_KEY: "" }) && !P.configured({ ...env, APNS_KEY_ID: "short" }));
const jwt = await P.makeJwt(env, t0);
const [h, c, sig] = jwt.split(".");
const dec = (s) => JSON.parse(Buffer.from(s, "base64url").toString());
check("the provider token carries ES256, the key id, the team and the time", dec(h).alg === "ES256" && dec(h).kid === "ABC123DEFG" && dec(c).iss === "YOURTEAMID" && dec(c).iat === Math.floor(t0 / 1000), JSON.stringify([dec(h), dec(c)]));
const ok = await webcrypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, pair.publicKey, Buffer.from(sig, "base64url"), new TextEncoder().encode(`${h}.${c}`));
check("…and its signature checks out against the key's public half", ok && Buffer.from(sig, "base64url").length === 64);

const a = await P.providerJwt(env, { now: t0 });
const b = await P.providerJwt(env, { now: t0 + 44 * MIN });
check("the held token is reused for 45 minutes", a === b);
const cc = await P.providerJwt(env, { now: t0 + 46 * MIN });
check("…then a new one is made", cc !== a);
const d = await P.providerJwt(env, { force: true, now: t0 + 46 * MIN + 10 * MIN });
check("a forced one is refused inside 20 minutes (the held one comes back)", d === cc);
const e = await P.providerJwt(env, { force: true, now: t0 + 46 * MIN + 21 * MIN });
check("…and allowed after", e !== cc);

// ── the phones ───────────────────────────────────────────────────────────────
check("a token that is not a device token is refused", (await P.register(env, "nope")).ok === false && (await P.register(env, "ZZ".repeat(40))).ok === false);
let r = await P.register(env, T1.toUpperCase(), "dev", "Nathaniel's iPhone", t0);
check("a phone registers (token lower-cased, count answered)", r.ok && r.tokens === 1);
await P.register(env, T1, "prod", "renamed", t0 + 1000);
let held = await P.devices(env);
check("registering again keeps the first environment guess, refreshes the name", held[T1].env === "dev" && held[T1].device === "renamed", JSON.stringify(held));
r = await P.mergeDevices(env, { [T2]: { env: "prod", device: "iPad", added: 5, seen: 6 }, [T1]: { env: "prod" }, nope: {} });
check("the Mac's list merges in: new tokens only, tidy ones only", r.added === 1 && r.tokens === 2 && (await P.devices(env))[T1].env === "dev", JSON.stringify(r));
check("a phone can be taken off", (await P.unregister(env, T2)).removed === true && Object.keys(await P.devices(env)).length === 1);

// ── sending ──────────────────────────────────────────────────────────────────
const calls = [];
const apple = (script) => async (url, init) => {
  const token = url.split("/").pop(); const host = new URL(url).host;
  calls.push({ token, host, headers: { ...init.headers }, body: JSON.parse(init.body) });
  const [status, body] = script(token, host, calls.length);
  return { status, json: async () => body };
};
let got = await P.send(env, { title: "Changed in two places", body: "x ".repeat(200), category: "RECEIPT", data: { route: "conflicts" }, level: "time-sensitive", thread: "t" }, { fetchImpl: apple(() => [200, {}]), now: t0 });
check("one phone, one push, to the environment it was registered on", got.ok && got.sent === 1 && calls[0].host === "api.sandbox.push.apple.com", JSON.stringify([got, calls[0] && calls[0].host]));
const sentBody = calls[0].body;
check("the payload is the Mac's: alert, level, category, thread, sound, our data", sentBody.aps.alert.title === "Changed in two places" && sentBody.aps["interruption-level"] === "time-sensitive" && sentBody.aps.category === "RECEIPT" && sentBody.aps["thread-id"] === "t" && sentBody.aps.sound === "default" && sentBody.route === "conflicts", JSON.stringify(sentBody));
check("…the body is trimmed to a sentence that ends in an ellipsis", sentBody.aps.alert.body.length <= 181 && sentBody.aps.alert.body.endsWith("…"));
const hd = calls[0].headers;
check("…and the headers are the Mac's", hd["apns-topic"] === "com.example.projectsconsole" && hd["apns-push-type"] === "alert" && hd["apns-priority"] === "10" && /^bearer [\w-]+\.[\w-]+\.[\w-]+$/.test(hd.authorization) && Number(hd["apns-expiration"]) === Math.floor(t0 / 1000) + 3600, JSON.stringify(hd));

calls.length = 0;
await P.register(env, T3, "prod", "other", t0);
got = await P.send(env, { title: "t", body: "b" }, { fetchImpl: apple((tk, host) => (tk === T3 && host === "api.push.apple.com" ? [400, { reason: "BadDeviceToken" }] : [200, {}])), now: t0 });
held = await P.devices(env);
check("a token from the other service is tried there and remembered", got.sent === 2 && held[T3].env === "dev" && calls.filter((x) => x.token === T3).length === 2, JSON.stringify([got, held[T3]]));

calls.length = 0;
got = await P.send(env, { title: "t", body: "b" }, { fetchImpl: apple((tk) => (tk === T3 ? [410, { reason: "Unregistered" }] : [200, {}])), now: t0 });
check("a dead token is dropped", got.sent === 1 && !(T3 in (await P.devices(env))), JSON.stringify(got));

calls.length = 0;
got = await P.send(env, { title: "t", body: "b" }, { fetchImpl: apple(() => [500, { reason: "InternalServerError" }]), now: t0 });
check("Apple's trouble leaves the token alone and is said", got.sent === 0 && got.failures.length === 1 && T1 in (await P.devices(env)), JSON.stringify(got));

calls.length = 0;
let first = true;
got = await P.send(env, { title: "t", body: "b" }, { fetchImpl: apple(() => { if (first) { first = false; return [403, { reason: "ExpiredProviderToken" }]; } return [200, {}]; }), now: t0 + 97 * MIN });
check("an expired provider token is renewed once, when allowed, and the push goes", got.sent === 1 && calls.length === 2 && calls[0].headers.authorization !== calls[1].headers.authorization, JSON.stringify(got));

check("no key: nothing sent, nothing thrown", (await P.send({ ...env, APNS_KEY: "" }, { title: "t", body: "b" })).error === "no key");
check("no phones: nothing sent, nothing thrown", (await P.send({ ...mkEnv() }, { title: "t", body: "b" })).error === "no phones registered");
const thrown = await P.send(env, { title: "t", body: "b" }, { fetchImpl: async () => { throw new Error("offline"); }, now: t0 });
check("a network failure is a line in the answer", thrown.sent === 0 && /fetch failed/.test(thrown.failures[0] || ""), JSON.stringify(thrown));

// ── the questions ────────────────────────────────────────────────────────────
calls.length = 0;
const told = await P.tellConflicts(env, [{ title: "Changed in two places", body: "ZED: the logline — changed in Notion and in the record. Open Projects Console to pick which to keep.", page: "p1", field: "logline", project: "ZED" }], { fetchImpl: apple(() => [200, {}]), now: t0 });
check("a question for him becomes an alert that opens the questions", told.length === 1 && told[0].sent >= 1 && calls[0].body.route === "conflicts" && calls[0].body.page === "p1" && calls[0].body.aps["thread-id"] === "conflict-p1", JSON.stringify(calls[0] && calls[0].body));
check("no questions, no alerts", (await P.tellConflicts(env, [])).length === 0);

console.log(`push: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
