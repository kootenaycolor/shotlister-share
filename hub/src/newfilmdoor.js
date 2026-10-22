/**
 * The way into the engine's `new_film` door (`mcpweb/src/newfilm.rs`) for
 * `newfilm.js` — shaped like `mirrorRecord` in `filmdoor.js`: an empty film is
 * begun under a throwaway name (it has no logs to replay), asked to make
 * itself, and hands back its manifest and the one change log to keep. Kept
 * apart so `newfilm.js` can be checked without the engine.
 */

import mcpWasm from "./mcp.wasm";
import { begin, put, take } from "./live.js";

/** `{said: {ok, project, manifest}, log}`; throws with the engine's words. */
export async function engineMakes(link, device) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  const seed = new Uint8Array(6);
  crypto.getRandomValues(seed);
  x.set_seed(seed.reduce((v, b) => v * 256 + b, 0));
  begin(x, "0".repeat(32), link.title, false, device);
  x.settle();
  const [ptr, len] = put(x, JSON.stringify(link));
  const out = x.new_film(ptr, len);
  x.dealloc(ptr, len);
  const said = JSON.parse(take(x, out));
  const log = take(x, x.pending_log());
  if (said.error) throw new Error(said.error);
  if (!log || !said.manifest) throw new Error("the engine made no film");
  return { said, log };
}
