/**
 * **A film's scenes, sections and days, read on the server** for New Shoot
 * (`newshootdoor.js`) — `dossier.film_facts`' `scene_list`, `sections` and
 * `day_list` on the Mac, from the relay copy's logs instead of a copy of the
 * film on disk. The engine's own `view`, read only: nothing is kept. Kept
 * apart, like `newfilmdoor.js`, so the rules can be checked without the engine.
 */

import mcpWasm from "./mcp.wasm";
import { begin, feed, take } from "./live.js";
import { titleOf } from "./films.js";

export async function filmShape(env, relay, ctx) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  const seed = new Uint8Array(6);
  crypto.getRandomValues(seed);
  x.set_seed(seed.reduce((v, b) => v * 256 + b, 0));
  begin(x, relay, await titleOf(env, relay), true, "0000000000000001");
  await feed(env, relay, ctx, x);
  const text = take(x, x.view());
  const view = text ? JSON.parse(text) : {};
  return {
    scenes: (view.scenes || []).map((s) => ({ number: s.number || "", title: s.title || "", archived: Boolean(s.archived) })),
    sections: (view.sequences || []).map((q) => q.title || ""),
    days: (view.days || []).map((d) => ({ label: d.label || "", date: d.date || "" })),
  };
}
