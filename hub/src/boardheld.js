/**
 * **What the portal's boards and pages lean on** (2026-10-15).
 *
 * Studio's tidy-up deletes, from the sync server and after a week, any picture
 * the film itself does not name. A picture put on a Dump Board or a look board
 * is named only by the board, so it would go. Before it deletes anything,
 * Studio (Mac and iPhone) asks here which pictures the portal holds on to:
 *
 *   GET /console/studio/held/<film id>
 *     -> { ok: true, scanned: <files read>, stems: ["<32 hex>", …] }
 *
 * A **stem** is a picture's 32-character name without its extension. A clip's
 * poster shares its clip's stem, so keeping a stem keeps both.
 *
 * What is read: the film's boards (not their history or settings), pages,
 * decks, press pages and the portal's front. Raw text is searched for
 * `<32 hex>.<ext>`, so a card, a thread, a figure inside a page or a
 * published copy are all caught without knowing each one's shape. Wider than
 * strictly needed, on purpose: a stem kept by mistake costs a picture a
 * little room on the server; one lost costs a broken board.
 *
 * **Never a guess.** Any file that cannot be read makes the whole answer an
 * error, and Studio treats an error as "delete nothing today".
 */

import { keys } from "../../relay/layout.js";
import { listAll } from "./films.js";

const NAMED = /(?:^|[^0-9a-f])([0-9a-f]{32})\.[A-Za-z0-9]{1,8}(?![A-Za-z0-9])/g;
const ID = /^[0-9a-f]{8,64}$/;

/** The stems a piece of text names. */
export function stemsIn(text) {
  const out = new Set();
  for (const m of String(text || "").matchAll(NAMED)) out.add(m[1]);
  return out;
}

/** Whether a key under the film's prefix is one of the portal's own files. */
export function portalFile(rel) {
  if (rel === "front.json") return true;
  if (rel.includes(".history/")) return false;
  if (rel.endsWith(".settings.json") || rel.endsWith(".posters-owed.json")) return false;
  return /^(boards|pages|decks|press)\/[^/]+\.(json|html)$/.test(rel);
}

export async function heldBy(env, film) {
  const base = keys.film(film);
  const stems = new Set();
  let scanned = 0;
  for (const o of await listAll(env, base)) {
    const rel = o.key.slice(base.length);
    if (!portalFile(rel)) continue;
    const got = await env.BUCKET.get(o.key);
    if (!got) throw new Error(`${rel} could not be read`);
    for (const s of stemsIn(await got.text())) stems.add(s);
    scanned += 1;
  }
  return { ok: true, scanned, stems: [...stems].sort() };
}

export async function heldDoor(env, rest, method) {
  if (rest[0] !== "held") return null;
  const reply = (body, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
  if (rest.length !== 2 || !ID.test(rest[1])) return reply({ ok: false, problem: "Say which film." }, 400);
  if (method !== "GET") return reply({ ok: false, problem: "Wrong method." }, 405);
  try {
    return reply(await heldBy(env, rest[1]));
  } catch (e) {
    return reply({ ok: false, problem: String((e && e.message) || e).slice(0, 200) }, 500);
  }
}
