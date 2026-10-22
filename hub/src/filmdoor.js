/**
 * **The door that writes the project record's facts into a film** — the
 * server's side of what the Mac's `filmfacts.py` asked Shotlister's
 * `--recordfacts` and `--setmark` for (Projects Console without the Mac,
 * stage 3, 2026-10-11). The engine's door is `mirror_record` in
 * `mcpweb/src/lib.rs`; this is the way into it, shaped like `attachToShot`
 * in `mcp.js`: the film is rebuilt from every log, asked one thing, and
 * whatever it changed is kept as one new log.
 *
 * `asked` is `{link, facts: {title, director, producer, client, agency},
 * mark: {path, colour}}`. It is the server's own work, not a person's, so the
 * log is the device `hub/record-mirror`'s, which the Mac and the phone take in
 * as they take in anything. Answers `{ok, changed, mark}`; throws an error
 * with `said` in plain words. Nothing is kept when nothing changed.
 */

import { keys } from "../../relay/layout.js";
import mcpWasm from "./mcp.wasm";
import { begin, feed, put, take, logObjects } from "./live.js";
import { filmlessPortal, titleOf } from "./films.js";

function refuse(said) {
  const error = new Error(said);
  error.said = said;
  return error;
}

/** The device a name stands for — mcp.js `deviceFor`, the same hash. */
function deviceFor(email) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(`hub/mcp/${String(email).toLowerCase()}`)) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return hash.toString(16).padStart(16, "0");
}

function seed() {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  let value = 0;
  for (const byte of bytes) value = value * 256 + byte;
  return value;
}

function randomHex(chars) {
  const bytes = new Uint8Array(chars / 2);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** mcp.js `keep`: the log into the bucket, then the room told, after. */
async function keep(env, project, device, text, ctx) {
  const portal = await filmlessPortal(env, project);
  if (portal) throw refuse(`${portal.title || "This project"} has no Shotlister film yet, only its portal.`);
  await env.BUCKET.put(keys.log(project, `${device}-${randomHex(16)}.log`), text, {
    httpMetadata: { contentType: "text/plain; charset=utf-8" },
  });
  if (!env.ROOMS) return;
  try {
    const room = env.ROOMS.get(env.ROOMS.idFromName(project));
    const said = room.fetch("https://rooms/said", { method: "POST", body: JSON.stringify({ what: "logs" }) });
    if (ctx && ctx.waitUntil) ctx.waitUntil(said);
    else await said;
  } catch (error) {
    console.error("could not tell the room:", String(error));
  }
}

export async function mirrorRecord(env, project, ctx, asked) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());
  const device = deviceFor("record-mirror");
  begin(x, project, await titleOf(env, project), false, device);
  await feed(env, project, ctx, x);
  const [ptr, len] = put(x, JSON.stringify(asked));
  const out = x.mirror_record(ptr, len);
  x.dealloc(ptr, len);
  const said = JSON.parse(take(x, out));
  const pending = take(x, x.pending_log());
  if (said.error) throw refuse(said.error);
  if (pending && !asked.dry) await keep(env, project, device, pending, ctx);
  return said;
}

/**
 * **A spare film linked to a project** — the engine's `link_film` door
 * (`mcpweb/src/linkfilm.rs`), reached as `mirrorRecord` reaches
 * `mirror_record`. Written as the record mirror's device: linking a film is
 * the server's work, not somebody editing it, so `filmReadout`'s last edit
 * leaves it out as it leaves out the mirror's. Answers `{ok, project, was}`;
 * throws with the engine's words.
 */
export async function linkFilmEngine(env, project, ctx, asked) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());
  const device = deviceFor("record-mirror");
  begin(x, project, await titleOf(env, project), false, device);
  await feed(env, project, ctx, x);
  const [ptr, len] = put(x, JSON.stringify(asked));
  const out = x.link_film(ptr, len);
  x.dealloc(ptr, len);
  const said = JSON.parse(take(x, out));
  const pending = take(x, x.pending_log());
  if (said.error) throw refuse(said.error);
  if (pending) await keep(env, project, device, pending, ctx);
  return said;
}

/**
 * **What a film says about itself, read on the server** — `dossier.film_facts`
 * on the Mac, from the film's logs in the bucket instead of a copy on disk.
 * Read only: nothing is kept. `view` is the engine's own description (the
 * same one the Mac's reader prints); the counts are taken from it the way
 * `film_facts` takes them. `last_edit` is when the newest log reached the
 * bucket (seconds), which is as close as the server can come to the Mac's
 * newest-log time.
 */
export async function filmReadout(env, project, ctx) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());
  begin(x, project, await titleOf(env, project), true, "0000000000000001");
  const listed = await logObjects(env, project);
  await feed(env, project, ctx, x, listed);
  const text = take(x, x.view());
  const view = text ? JSON.parse(text) : {};
  const p = view.project || {};
  const days = view.days || [];
  // Not the server's own mirror logs: writing a film's facts onto it is not
  // somebody editing the film, and the Mac's "edited after its last backup"
  // would say so every time.
  const mine = `${deviceFor("record-mirror")}-`;
  const newest = listed
    .filter((o) => !o.key.split("/").pop().startsWith(mine))
    .reduce((a, o) => Math.max(a, o.uploaded ? new Date(o.uploaded).getTime() : 0), 0);
  return {
    title: p.title || "",
    director: p.director || "",
    consolePage: p.consolePage || "",
    scenes: (view.scenes || []).length,
    shots: (view.groups || []).reduce((n, g) => n + (g.rows || []).length, 0),
    locations: (view.locations || []).length,
    boards: (view.boards || []).length,
    days: days.length,
    daysDated: days.filter((d) => d.date).length,
    lastEdit: newest ? newest / 1000 : 0,
    markPath: p.markPath || "",
    markColour: String(p.markColour || "").toUpperCase(),
  };
}
