/**
 * **Telling Projects Console on the phone, from the server** (2026-10-11,
 * Projects Console without the Mac, stage 3, step 4). The Mac's
 * `studio/push.py` rule for rule: one notification to every registered phone,
 * signed with the Apple push key.
 *
 * - **The key** is two Worker secrets, `APNS_KEY` (the `.p8`, PEM text) and
 *   `APNS_KEY_ID` (its ten characters). Without them nothing is sent and
 *   nothing breaks: `configured` says so.
 * - **The provider token** (a signed ES256 JWT) is reused hard. Apple
 *   invalidates it at 60 minutes and refuses more than one new one per 20, so
 *   it is made at 45 minutes, kept in the bucket (`s/apns-jwt.json`), and a
 *   rejection for expiry gets a new one only if the held one is over 20 old.
 * - **The endpoint is discovered, not declared.** A build put straight on the
 *   phone is signed for Apple's sandbox, the same app from TestFlight for
 *   production, and a token from one is refused by the other. The held
 *   `env` is tried first, the other on `BadDeviceToken`, and whichever
 *   answered is written back.
 * - **The phones** are kept in the bucket (`s/push-devices.json`), put there
 *   when the phone registers (`push_register`, answered in `cloud.js`) and
 *   when the Mac hands over the list it already had.
 */

const TEAM_ID = "YOURTEAMID";
const TOPIC = "com.example.projectsconsole";
const HOSTS = { prod: "api.push.apple.com", dev: "api.sandbox.push.apple.com" };
const OTHER = { prod: "dev", dev: "prod" };
const JWT_MAX_AGE = 45 * 60;
const JWT_MIN_AGE = 20 * 60 + 5;
const BODY_CHARS = 180;
const DEVICES_KEY = "s/push-devices.json";
const JWT_KEY = "s/apns-jwt.json";

export const configured = (env) => Boolean(env && String(env.APNS_KEY || "").includes("PRIVATE KEY") && String(env.APNS_KEY_ID || "").length === 10);

const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlText = (text) => b64url(new TextEncoder().encode(text));

async function readJson(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}
const keepJson = (env, key, body) => env.BUCKET.put(key, JSON.stringify(body), { httpMetadata: { contentType: "application/json" } });

// ── the key ─────────────────────────────────────────────────────────────────

async function signingKey(pem) {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

/** A signed provider token: header, claims, and the 64-byte signature
 * WebCrypto gives (r then s), which is what a JWT carries. */
export async function makeJwt(env, now = Date.now()) {
  const header = b64urlText(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = b64urlText(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(now / 1000) }));
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, await signingKey(env.APNS_KEY), new TextEncoder().encode(`${header}.${claims}`));
  return `${header}.${claims}.${b64url(signature)}`;
}

/** The held provider token, or a new one when it is 45 minutes old
 * (`force` only if the held one is over 20). */
export async function providerJwt(env, { force = false, now = Date.now() } = {}) {
  const held = await readJson(env, JWT_KEY);
  const age = held ? (now - held.iat * 1000) / 1000 : Infinity;
  if (held && held.jwt && held.kid === env.APNS_KEY_ID && !(force ? age > JWT_MIN_AGE : age >= JWT_MAX_AGE)) return held.jwt;
  const jwt = await makeJwt(env, now);
  await keepJson(env, JWT_KEY, { jwt, iat: Math.floor(now / 1000), kid: env.APNS_KEY_ID });
  return jwt;
}

// ── the phones ──────────────────────────────────────────────────────────────

export async function devices(env) {
  const got = await readJson(env, DEVICES_KEY);
  return got && typeof got === "object" && !Array.isArray(got) ? got : {};
}

async function changeDevices(env, edit) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const current = await env.BUCKET.get(DEVICES_KEY);
    let held = {};
    if (current) { try { held = await current.json(); } catch { held = {}; } }
    const next = edit({ ...held });
    const put = await env.BUCKET.put(DEVICES_KEY, JSON.stringify(next), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: current ? { etagMatches: current.etag } : { etagDoesNotMatch: "*" },
    });
    if (put) return next;
  }
  throw new Error("the phone list kept changing");
}

const isToken = (t) => typeof t === "string" && t.length >= 32 && /^[0-9a-f]+$/.test(t);

/** push.register — idempotent; the phone's guess at the endpoint is used only the first time. */
export async function register(env, token, apnsEnv = "", device = "", now = Date.now()) {
  const t = String(token || "").trim().toLowerCase();
  if (!isToken(t)) return { ok: false, error: "not a device token" };
  const next = await changeDevices(env, (held) => {
    const row = held[t] || {};
    if (!row.added) row.added = now / 1000;
    if (!row.env) row.env = apnsEnv in HOSTS ? apnsEnv : "prod";
    row.device = device || row.device || "";
    row.seen = now / 1000;
    held[t] = row;
    return held;
  });
  return { ok: true, tokens: Object.keys(next).length };
}

export async function unregister(env, token) {
  const t = String(token || "").trim().toLowerCase();
  let removed = false;
  await changeDevices(env, (held) => { removed = t in held; delete held[t]; return held; });
  return { ok: true, removed };
}

/** The Mac's list, merged in: a token already here keeps what the hub knows. */
export async function mergeDevices(env, incoming) {
  let added = 0;
  const next = await changeDevices(env, (held) => {
    for (const [token, row] of Object.entries(incoming || {})) {
      if (!isToken(token) || held[token]) continue;
      held[token] = { added: Number(row.added) || Date.now() / 1000, env: row.env in HOSTS ? row.env : "prod", device: String(row.device || ""), seen: Number(row.seen) || 0 };
      added += 1;
    }
    return held;
  });
  return { ok: true, added, tokens: Object.keys(next).length };
}

async function dropDevice(env, token) { await changeDevices(env, (held) => { delete held[token]; return held; }); }
async function rememberEnv(env, token, apnsEnv) { await changeDevices(env, (held) => { if (held[token]) held[token].env = apnsEnv; return held; }); }

// ── sending ─────────────────────────────────────────────────────────────────

const trim = (text) => {
  const t = String(text || "").split(/\s+/).filter(Boolean).join(" ");
  if (t.length <= BODY_CHARS) return t;
  const cut = t.slice(0, BODY_CHARS);
  const space = cut.lastIndexOf(" ");
  return `${space > 0 ? cut.slice(0, space) : cut}…`;
};

async function post(fetchImpl, token, apnsEnv, payload, headers) {
  try {
    const res = await fetchImpl(`https://${HOSTS[apnsEnv]}/3/device/${token}`, { method: "POST", headers, body: payload });
    let body = {};
    try { body = await res.json(); } catch { body = {}; }
    return [res.status, body];
  } catch (e) {
    return [0, { reason: `fetch failed: ${String((e && e.message) || e)}` }];
  }
}

/**
 * One notification to every registered phone — push.send. Never throws: a
 * push that cannot go out is a line in the answer, not a failed run.
 * `fetchImpl` is for the checks.
 */
export async function send(env, { title, body, category = "", data = {}, badge = null, level = "active", priority = 10, thread = "" }, { fetchImpl = fetch, now = Date.now() } = {}) {
  if (!configured(env)) return { ok: false, error: "no key", sent: 0 };
  const held = await devices(env);
  const tokens = Object.keys(held);
  if (!tokens.length) return { ok: false, error: "no phones registered", sent: 0 };
  let jwt;
  try { jwt = await providerJwt(env, { now }); } catch (e) { return { ok: false, error: `could not sign: ${String((e && e.message) || e)}`, sent: 0 }; }

  const aps = { alert: { title: String(title || "").slice(0, 120), body: trim(body) }, "interruption-level": level };
  if (category) aps.category = category;
  if (badge !== null && badge !== undefined) aps.badge = Math.max(0, Math.floor(Number(badge)));
  if (thread) aps["thread-id"] = thread;
  if (level === "time-sensitive") { aps.sound = "default"; aps["relevance-score"] = 1.0; }
  const payload = JSON.stringify({ aps, ...data });
  const headers = {
    authorization: `bearer ${jwt}`,
    "apns-topic": TOPIC,
    "apns-push-type": "alert",
    "apns-priority": String(priority),
    "apns-expiration": String(Math.floor(now / 1000) + 3600),
    "content-type": "application/json",
  };

  let sent = 0;
  const failures = [];
  for (const token of tokens) {
    let apnsEnv = held[token].env in HOSTS ? held[token].env : "prod";
    let [status, answer] = await post(fetchImpl, token, apnsEnv, payload, headers);
    let reason = (answer && answer.reason) || "";
    if (status === 403 && reason === "ExpiredProviderToken") {
      const again = await providerJwt(env, { force: true, now });
      if (again && again !== jwt) {
        jwt = again;
        headers.authorization = `bearer ${jwt}`;
        [status, answer] = await post(fetchImpl, token, apnsEnv, payload, headers);
        reason = (answer && answer.reason) || "";
      }
    }
    if (status === 400 && (reason === "BadDeviceToken" || reason === "BadEnvironmentKeyInToken")) {
      const alt = OTHER[apnsEnv];
      [status, answer] = await post(fetchImpl, token, alt, payload, headers);
      reason = (answer && answer.reason) || "";
      if (status === 200) { apnsEnv = alt; await rememberEnv(env, token, alt); }
    }
    if (status === 200) { sent += 1; continue; }
    if (status === 410 || reason === "Unregistered" || reason === "BadDeviceToken") { await dropDevice(env, token); continue; }
    failures.push(`…${token.slice(-8)}: ${status} ${reason}`.trim());
  }
  return { ok: sent > 0, sent, failures, phones: tokens.length };
}

/**
 * The Notion link's questions for him (`notify` on a look: {title, body,
 * project, field, page}) as alerts on the phone. A tap opens the questions
 * (`route: "conflicts"`). Never throws.
 */
export async function tellConflicts(env, notes, options = {}) {
  const out = [];
  for (const n of notes || []) {
    try {
      out.push(await send(env, {
        title: n.title || "Changed in two places",
        body: n.body || "",
        category: "RECEIPT",
        data: { route: "conflicts", page: n.page || "", field: n.field || "" },
        level: "time-sensitive",
        thread: `conflict-${n.page || "x"}`,
      }, options));
    } catch (e) {
      out.push({ ok: false, error: String((e && e.message) || e), sent: 0 });
    }
  }
  return out;
}
