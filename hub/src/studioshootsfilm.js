/**
 * The engine half of `studioshoots.js`: a film's view on the server with its
 * card — shoots and all — laid over it, read only. Its own file so the plain
 * node checks of `studioshoots.js` need not load the engine.
 */
import mcpWasm from "./mcp.wasm";
import { begin, feed, logObjects, take } from "./live.js";
import { titleOf } from "./films.js";
import { layCard } from "./studiocardsfilm.js";

export async function filmView(env, project, ctx, card) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(1);
  begin(x, project, await titleOf(env, project), true, "0000000000000001");
  await feed(env, project, ctx, x, await logObjects(env, project));
  if (card) layCard(x, card);
  const text = take(x, x.view());
  return text ? JSON.parse(text) : {};
}
