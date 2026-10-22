/**
 * The engine half of `studiocards.js`: a film read on the server, with or
 * without its card laid over it. Its own file so the plain node checks of
 * `studiocards.js` need not load the engine.
 */
import mcpWasm from "./mcp.wasm";
import { begin, feed, put, logObjects } from "./live.js";
import { take } from "./live.js";
import { titleOf } from "./films.js";
import { engineCard } from "./studiocards.js";

/** Lay a card into a begun, fed engine (`set_card`). Quiet when the engine is older. */
export function layCard(x, card) {
  if (!card || typeof x.set_card !== "function") return false;
  const [ptr, len] = put(x, engineCard(card));
  const said = x.set_card(ptr, len);
  x.dealloc(ptr, len);
  return said === 0;
}

/** The engine's view `project` block for a film, read only; with `card` laid on when given. */
export async function filmProject(env, project, ctx, card = null) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(1);
  begin(x, project, await titleOf(env, project), true, "0000000000000001");
  await feed(env, project, ctx, x, await logObjects(env, project));
  if (card) layCard(x, card);
  const text = take(x, x.view());
  const view = text ? JSON.parse(text) : {};
  return view.project || {};
}

/**
 * What a film holds, counted (studiomodes.js's look): scenes and script
 * drafts for Shot List, locations, reference boards, schedule days, and
 * diagrams (loose plans and scenes with anything drawn). Read only.
 */
export async function filmUse(env, project, ctx) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(1);
  begin(x, project, await titleOf(env, project), true, "0000000000000001");
  await feed(env, project, ctx, x, await logObjects(env, project));
  const text = take(x, x.view());
  const v = text ? JSON.parse(text) : {};
  const n = (a) => (Array.isArray(a) ? a.length : 0);
  const scenes = Array.isArray(v.scenes) ? v.scenes : [];
  return {
    scenes: scenes.length,
    scripts: n(v.scripts),
    locations: n(v.locations),
    boards: n(v.boards),
    days: n(v.days),
    diagrams: (Array.isArray(v.plans) ? v.plans.filter((p) => (p.diagram || 0) > 0).length : 0) + scenes.filter((s) => (s.diagram || 0) > 0).length,
  };
}
