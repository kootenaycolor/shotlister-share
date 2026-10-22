/**
 * View links — a filtered shot list, shared on its own.
 *
 * His ask, 2026-10-02: *"Share only the filter view of a shot list to send to
 * people"* — the techs' shots, the B camera's, one day's.
 *
 * A view is a filter with a name and an address of its own:
 * `share.your-domain.example/chb/v/crane-shots-k7p2x9q4`. The last eight
 * characters are the secret; the words before them only say what it is, so a
 * view renamed keeps every link already sent. Whoever opens it is handed the
 * shots the filter keeps and nothing else (`lensModel`), cut here on the
 * server — no change logs, no other page of the film. It is live: a shot
 * tagged later joins the link without anybody making a new one.
 *
 * Kept in `p/<film>/views.json`, beside `people.json` and never inside it:
 * the Share panel writes that list whole, and a view riding in it would be one
 * forgotten field away from being dropped by every save.
 */
import mcpWasm from "./mcp.wasm";
import { keys } from "../../relay/layout.js";
import { begin, feed, filmStamp, put, take } from "./live.js";
import { lensModel, viewSlug } from "../public/narrow.js";

/** The secret half of a view's address. */
export const VIEW_CODE = /^[a-z0-9]{8}$/;
const MOST_VIEWS = 60;
const MOST_FACETS = 40;

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function viewsOf(env, project) {
  const got = await env.BUCKET.get(keys.views(project));
  if (!got) return { version: 1, views: [] };
  try {
    const parsed = await got.json();
    return { version: 1, views: Array.isArray(parsed.views) ? parsed.views.filter((v) => v && VIEW_CODE.test(v.code)) : [] };
  } catch {
    return { version: 1, views: [] };
  }
}

/** Written against the tag it was read under, as `savePeople` is. */
async function saveViews(env, project, change) {
  const key = keys.views(project);
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await env.BUCKET.get(key);
    let list = { version: 1, views: [] };
    if (current) {
      try {
        const parsed = await current.json();
        if (Array.isArray(parsed.views)) list.views = parsed.views;
      } catch { /* a list that will not read is started again */ }
    }
    const said = change(list);
    const saved = await env.BUCKET.put(key, JSON.stringify(list, null, 2), {
      httpMetadata: { contentType: "application/json" },
      onlyIf: current ? { etagMatches: current.etag } : { etagDoesNotMatch: "*" },
    });
    if (saved) return { list, said };
  }
  throw new Error("Somebody changed the views at the same moment. Try again.");
}

/** The view a link's key opens, switched on — or null. */
export async function viewByKey(env, project, key) {
  if (!key) return null;
  const hash = await sha256Hex(key);
  const found = (await viewsOf(env, project)).views.find((v) => v.hash === hash);
  return found && !found.off ? found : null;
}

/** The view an address names — `crane-shots-k7p2x9q4`, or the code alone. */
export async function viewByCode(env, project, segment) {
  const code = codeIn(segment);
  if (!code) return null;
  return (await viewsOf(env, project)).views.find((v) => v.code === code) || null;
}

export function codeIn(segment) {
  const said = String(segment || "").toLowerCase();
  const code = said.slice(-8);
  if (!VIEW_CODE.test(code)) return "";
  return said.length === 8 || said[said.length - 9] === "-" ? code : "";
}

function randomText(alphabet, n) {
  const raw = crypto.getRandomValues(new Uint8Array(n));
  return [...raw].map((b) => alphabet[b % alphabet.length]).join("");
}

/** `[[field, value], …]`, or `{field, value}` pairs, cleaned and capped. */
export function cleanFacets(facets) {
  const out = [];
  for (const one of Array.isArray(facets) ? facets : []) {
    const field = String(Array.isArray(one) ? one[0] : one && one.field || "").slice(0, 80);
    const value = String(Array.isArray(one) ? one[1] : one && one.value || "").slice(0, 200);
    if (!field || !value) continue;
    if (out.some(([f, v]) => f === field && v === value)) continue;
    out.push([field, value]);
    if (out.length >= MOST_FACETS) break;
  }
  return out;
}

/** The address a view lives at, from the film's short name if it has one. */
export function viewPath(view, short, project) {
  const tail = `v/${viewSlug(view.name)}-${view.code}`;
  return short ? `/${short}/${tail}` : `/f/${project}/${tail}`;
}

/** What the Share panel and the connector are told about a view — never its key. */
export function viewSaid(view, short, project) {
  return {
    code: view.code,
    name: view.name,
    facets: view.facets || [],
    groupBy: view.groupBy === "day" ? "day" : "scene",
    off: Boolean(view.off),
    made: view.made || "",
    path: viewPath(view, short, project),
  };
}

export async function makeView(env, project, asked, by) {
  const facets = cleanFacets(asked.facets);
  if (!facets.length) throw new Error("A view needs a filter.");
  const name = String(asked.name || "").trim().slice(0, 60) || facets.map(([, v]) => v).join(", ").slice(0, 60);
  const key = randomText("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_", 32);
  const view = {
    code: randomText("abcdefghijklmnopqrstuvwxyz0123456789", 8),
    key,
    hash: await sha256Hex(key),
    name,
    facets,
    groupBy: asked.groupBy === "day" ? "day" : "scene",
    made: new Date().toISOString().slice(0, 10),
    by: String(by || "").slice(0, 120),
    off: false,
  };
  await saveViews(env, project, (list) => {
    if (list.views.length >= MOST_VIEWS) throw new Error(`A film holds ${MOST_VIEWS} views at most.`);
    list.views.push(view);
  });
  return view;
}

/** Rename, switch on or off, or change the filter of one view. */
export async function changeView(env, project, code, asked) {
  const { said } = await saveViews(env, project, (list) => {
    const view = list.views.find((v) => v.code === code);
    if (!view) return null;
    if (typeof asked.name === "string" && asked.name.trim()) view.name = asked.name.trim().slice(0, 60);
    if (typeof asked.off === "boolean") view.off = asked.off;
    if (asked.groupBy === "day" || asked.groupBy === "scene") view.groupBy = asked.groupBy;
    if (Array.isArray(asked.facets)) {
      const facets = cleanFacets(asked.facets);
      if (facets.length) view.facets = facets;
    }
    return view;
  });
  return said;
}

/** Gone for good: the link stops answering and cannot be switched back on. */
export async function removeView(env, project, code) {
  const { said } = await saveViews(env, project, (list) => {
    const at = list.views.findIndex((v) => v.code === code);
    if (at < 0) return null;
    return list.views.splice(at, 1)[0];
  });
  return said;
}

/**
 * The shots one view keeps, as the page draws them.
 *
 * `asked` is what the person reading has chosen for themselves — shooting
 * order, a column to sort by, a search — and never the filter, which is the
 * view's. Held in Cloudflare's cache under the film's stamp, so a crew of
 * twenty all looking every twenty seconds replays the film once per change.
 */
export async function lensView(env, project, ctx, view, asked = {}) {
  const question = {
    groupBy: asked.groupBy === "day" ? "day" : asked.groupBy === "scene" ? "scene" : view.groupBy || "scene",
    sortColumn: String(asked.sortColumn || "").slice(0, 80),
    sortDescending: Boolean(asked.sortDescending),
    search: String(asked.search || "").slice(0, 200),
  };
  const { objects, stamp } = await filmStamp(env, project);
  const said = await sha256Hex(JSON.stringify([question, view.facets, view.name]));
  const key = new Request(`https://lenses.invalid/${project}/${view.code}/${stamp || "none"}/${said}`);
  const cache = caches.default;
  const held = await cache.match(key);
  if (held) return await held.text();

  let model = {};
  if (objects.length) {
    const film = await WebAssembly.instantiate(mcpWasm, {});
    const x = film.exports;
    x.set_now(Date.now());
    x.set_seed(1);
    begin(x, project, "", true, "0000000000000001");
    await feed(env, project, ctx, x, objects);
    const [p, l] = put(x, JSON.stringify(question));
    const text = take(x, x.view_as(p, l));
    x.dealloc(p, l);
    model = text ? JSON.parse(text) : {};
  }
  const out = JSON.stringify({ ...lensModel(model, view), lens: { name: view.name, facets: view.facets }, stamp });
  const kept = cache.put(key, new Response(out, {
    headers: { "cache-control": "max-age=86400", "content-type": "application/json" },
  }));
  if (ctx && ctx.waitUntil) ctx.waitUntil(kept);
  else await kept;
  return out;
}
