/**
 * **His OK, in between** (2026-10-19, his ask: "make sure the mcp can do all
 * actions in project console and shotlister that i can").
 *
 * Projects Console never moves, deletes, hides, publishes or changes who can
 * see something on one click: it shows a plan, a pop-up or Delete's list of
 * every effect, and waits for his button. The connector's console tools keep
 * the same two steps, with the chat as the button:
 *
 * 1. **The look.** Called without `confirm`, a tool writes nothing. It answers
 *    the same preview the app shows and a **confirm token**, kept here.
 * 2. **The run.** Called again with that token, it runs — only when the token
 *    is one this server gave, to this person, for this tool, this project and
 *    these arguments, under ten minutes old, never used, and the preview it
 *    was given for is still what the app would show now. Anything else is
 *    refused and nothing is written; a preview that moved is answered with
 *    the new one and a new token, so he sees what changed before saying yes.
 *
 * The descriptions tell the AI to show him the preview and get his yes in the
 * chat before step 2. The token cannot know whether he said yes — it makes
 * sure a run is only ever of exactly what was shown, and soon after.
 *
 * His alone: every console tool asks `isAdmin` first, step 1 included.
 */

/** How long a token lasts. Long enough to read a plan and answer; no longer. */
export const TOKEN_LIFE_MS = 10 * 60 * 1000;
export const PREFIX = "mcp/confirm/";
const TOKEN = /^ok-[0-9a-f]{20}$/;

/** Arguments as a stable string: keys sorted, the gate's own fields left out. */
export function canon(value) {
  const walk = (v) => {
    if (Array.isArray(v)) return v.map(walk);
    if (v && typeof v === "object") {
      const out = {};
      for (const k of Object.keys(v).sort()) {
        if (k === "confirm" || k === "typed_name") continue;
        if (v[k] === undefined) continue;
        out[k] = walk(v[k]);
      }
      return out;
    }
    return v;
  };
  return JSON.stringify(walk(value === undefined ? null : value));
}

async function sha(text) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function fresh() {
  const a = new Uint8Array(10);
  crypto.getRandomValues(a);
  return `ok-${[...a].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

const keyOf = (token) => `${PREFIX}${token}.json`;

/**
 * Keep a token for one ask. `preview` is what was shown (only its digest is
 * kept); `ask` is {tool, project, args}. Answers the token.
 */
export async function issue(env, who, ask, preview, { now = Date.now() } = {}) {
  const token = fresh();
  await env.BUCKET.put(keyOf(token), JSON.stringify({
    email: String((who && who.email) || "").toLowerCase(),
    tool: ask.tool, project: String(ask.project || ""), args: canon(ask.args || {}),
    digest: await sha(canon(preview)),
    at: new Date(now).toISOString(), until: now + TOKEN_LIFE_MS, used: false,
  }), { httpMetadata: { contentType: "application/json" } });
  return token;
}

/**
 * Whether `token` lets this ask run now. Answers `{ok: true}` — the token is
 * spent in the same breath, so it never runs twice — or `{ok: false, why,
 * stale?}` in words for the chat. `preview` is the look made again just now:
 * when it is not what the token was given for, the answer is `stale`.
 */
export async function redeem(env, who, token, ask, preview, { now = Date.now() } = {}) {
  const again = `Call ${ask.tool} again without \`confirm\` to see the preview, show it to him, and use the new token once he says yes.`;
  if (!token) return { ok: false, why: `Nothing was done. This needs his OK: call ${ask.tool} without \`confirm\` first, show him the preview it answers, and only after his yes call it again with the \`confirm\` token it gave.` };
  if (!TOKEN.test(String(token))) return { ok: false, why: `Nothing was done. That is not a confirm token this server gave. ${again}` };
  const got = await env.BUCKET.get(keyOf(token));
  if (!got) return { ok: false, why: `Nothing was done. That confirm token is not one this server gave. ${again}` };
  let kept;
  try { kept = await got.json(); } catch { return { ok: false, why: `Nothing was done. That confirm token could not be read. ${again}` }; }
  if (kept.email !== String((who && who.email) || "").toLowerCase()) return { ok: false, why: `Nothing was done. That confirm token was given to somebody else. ${again}` };
  if (kept.used) return { ok: false, why: `Nothing was done. That confirm token was already used; each one runs once. ${again}` };
  if (now > Number(kept.until || 0)) return { ok: false, stale: true, why: `Nothing was done. That confirm token ran out (each lasts ${TOKEN_LIFE_MS / 60000} minutes). ${again}` };
  if (kept.tool !== ask.tool || kept.project !== String(ask.project || "") || kept.args !== canon(ask.args || {})) {
    return { ok: false, why: `Nothing was done. That confirm token was for a different ask (another tool, project or arguments). ${again}` };
  }
  if (kept.digest !== await sha(canon(preview))) {
    return { ok: false, stale: true, why: "Nothing was done. Something changed since he saw the preview, so it is not what he said yes to. Here is the preview as it stands now, with a new token: show him this one." };
  }
  // **Spent before it runs**, and only by the one who read it as it was: a
  // second call racing this one finds the etag moved and is refused.
  const spent = await env.BUCKET.put(keyOf(token), JSON.stringify({ ...kept, used: true, used_at: new Date(now).toISOString() }), {
    httpMetadata: { contentType: "application/json" }, onlyIf: { etagMatches: got.etag },
  });
  if (!spent) return { ok: false, why: `Nothing was done. That confirm token was used a moment ago. ${again}` };
  return { ok: true };
}

/**
 * Two steps (consolegate.js). `look()` answers `{shown, can_run}` — `shown`
 * the preview as the app words it — and writes nothing; `go(shown)` runs.
 * `typed`: the name he has to type (Rename, Move, Delete), checked before the
 * token is spent so a slip costs nothing.
 */
export async function twoSteps(env, who, a, refuse, { tool, project, args, look, go, typed = "" }) {
  const seen = await look();
  if (!a.confirm) {
    if (!seen.can_run) return JSON.stringify({ ...seen.shown, can_run: false, said: "Nothing can run as it stands; nothing was changed." }, null, 1);
    const token = await issue(env, who, { tool, project, args }, seen.shown);
    return JSON.stringify({
      ...seen.shown,
      can_run: true,
      confirm: token,
      next: `Nothing has changed yet. Show him this preview and wait for his yes. Then call ${tool} again with the same arguments and confirm "${token}"${typed ? `, and typed_name: the project's name as he types it in the chat ("${typed}")` : ""}.`,
    }, null, 1);
  }
  if (typed && String(a.typed_name || "").trim() !== typed) {
    throw refuse(`Nothing was done. ${tool} needs the project's name typed exactly, as the app asks: ask him to type "${typed}" in the chat and pass it as typed_name.`);
  }
  const red = await redeem(env, who, a.confirm, { tool, project, args }, seen.shown);
  if (!red.ok) {
    if (red.stale && seen.can_run) {
      const token = await issue(env, who, { tool, project, args }, seen.shown);
      throw refuse(`${red.why}\n${JSON.stringify({ ...seen.shown, confirm: token }, null, 1)}`);
    }
    throw refuse(red.why);
  }
  if (!seen.can_run) throw refuse(`Nothing was done: ${(seen.shown.problems || []).join(" ") || "it can't run now."}`);
  const out = await go(seen.shown);
  return typeof out === "string" ? out : JSON.stringify(out, null, 1);
}

/** The standard sentences every two-step description carries. */
export const TWO_STEPS =
  "**Two steps, with his OK in between.** Without `confirm` nothing changes: you get the preview the app shows and a `confirm` token (10 minutes, runs once). Show him that preview and wait for his yes in the chat; only then call again with the same arguments and `confirm`. His alone.";
