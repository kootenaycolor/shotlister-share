/**
 * The relay.
 *
 * **It stores files and understands none of them.** It never parses a change,
 * never merges, never runs the engine — so it cannot lose an edit or settle a
 * disagreement wrongly, because it does not know what either of those is. Every
 * rule about what a change means stays in `engine/`, where it is already
 * written and already tested.
 *
 * That is the whole design, and it is the reason this file can be short.
 *
 * ## What it holds
 *
 * Per project, exactly what a `.shotlist` folder holds and nothing more:
 *
 * ```text
 *   p/<project>/logs/<device>-<session>.log      the change logs
 *   p/<project>/logs/<device>-<installation>.device  the identity marks (empty)
 *   p/<project>/media/<sha256>                   pictures and clips
 *   p/<project>/manifest.json                    the project's birth certificate
 * ```
 *
 * ## The two rules it does enforce
 *
 * Both are about damage, not about meaning, which is why they belong here:
 *
 * - **A log may only ever grow.** A `PUT` whose body does not begin with the
 *   bytes already stored is refused. One writer per log is the invariant the
 *   whole sync design rests on, and the failure it protects against is real: a
 *   half-written or truncated local file uploading over a good remote one, with
 *   nothing to notice. Folding old logs together (Ref 192) is the one case that
 *   legitimately rewrites, and it says so with `?rewrite=1`.
 * - **A picture is written once and never again.** Media is named after the
 *   hash of its contents, so a name means one set of bytes for ever. A `PUT`
 *   to a name already here is answered and ignored, which makes an interrupted
 *   upload safe to simply repeat.
 *
 * Neither rule needs to know what a shot is.
 *
 * ## The hash check is offered, not assumed
 *
 * Most media does hash to its own name, and for those the sender says so with
 * an `x-sha256` header and the relay checks it — that is what stops a
 * corrupted local file being cached for ever under a name everything trusts.
 *
 * It is not *required*, and finding out why is the reason this is written down:
 * **a clip is stored twice under one name** — the movie itself, and the still
 * that stands for it wherever a picture is drawn (`storage/src/lib.rs:1019`).
 * The still is a different set of bytes under the same stem, so it hashes to
 * something else entirely. A relay that insisted would have refused the poster
 * of every video in the project, which is exactly the sort of rule that looks
 * principled and quietly breaks a real film.
 */

// **Where everything sits, and what a name may look like, from `layout.json`.**
// The bucket's layout is named once, there, and the hub reads the same file;
// this worker used to spell every path itself. The name shapes are exactly
// what `engine/src/package.rs` writes — anything else is refused, which is
// what keeps a made-up path out of the bucket — and the battery checks the
// two still agree.
import { LAYOUT, keys, names } from "../layout.js";
import { filmless } from "../portal.js";

const LOG_NAME = names.log;
const MARK_NAME = names.mark;
/** A fold record, `<device>.folded` — what that device retired and rewrote. */
const FOLD_NAME = names.fold;
/** How media sits on disk: the hash's first 32 characters, then its extension. */
const MEDIA_NAME = names.medium;
/**
 * The pictures alone — what `/i/` is willing to serve without a token.
 *
 * Deliberately narrower than `MEDIA_NAME`: the clips and the scans stay behind
 * the password, because nothing needs them fetchable and a route is easier to
 * keep small than to make small again later.
 */
const PICTURE_NAME = names.picture;
const SHA256 = /^[0-9a-f]{64}$/;
const PROJECT = names.project;

/**
 * What to serve a file as.
 *
 * Not decoration: the share page plays clips in a browser, and a browser will
 * not play a video it has been handed as `application/octet-stream`.
 */
const MIME = {
  jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", gif: "image/gif",
  webp: "image/webp", heic: "image/heic", tiff: "image/tiff", bmp: "image/bmp",
  mp4: "video/mp4", mov: "video/quicktime", m4v: "video/x-m4v", webm: "video/webm",
  pdf: "application/pdf", usdz: "model/vnd.usdz+zip", json: "application/json",
};

/** A picture bigger than this is refused rather than silently truncated. */
const MAX_MEDIA = 512 * 1024 * 1024;
/** A log this big means something has gone wrong; the largest real one is 46 KB. */
const MAX_LOG = 64 * 1024 * 1024;

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return preflight();
    try {
      const response = await route(request, env);
      return cors(response);
    } catch (error) {
      // Never leak a stack trace to a caller; the log keeps the detail.
      console.error(error && error.stack ? error.stack : String(error));
      return cors(problem(500, "The relay could not finish that."));
    }
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const parts = url.pathname.split("/").filter(Boolean);

  // `/v1/health` answers without a token, so "is it up?" can be asked by
  // anything. It says nothing about what is stored.
  if (parts.length === 2 && parts[0] === "v1" && parts[1] === "health") {
    return json({ relay: "shotlister", version: 1 });
  }

  // `/v1/version` says which commit this relay was deployed from, and when.
  // No token: it reveals a hash and a date and nothing about what is stored.
  //
  // **Stamped at deploy time, never read from git here** — a Worker has no
  // git. `relay/deploy.sh` passes `COMMIT` and `DEPLOYED` as vars on the
  // deploy; a relay put up any other way answers `unknown`, which is itself
  // the honest answer. `hub/drift.sh` reads this and says how far behind
  // `main` the live relay is.
  if (parts.length === 2 && parts[0] === "v1" && parts[1] === "version") {
    return json(versionOf(env));
  }

  // `/i/<project>/<name>` — one picture, and no token asked for.
  //
  // **Because Google has to be the one fetching it.** A frame in the exported
  // spreadsheet is an `IMAGE()` formula rather than a picture pasted over the
  // grid — that is what makes it belong to a cell and travel with its row when
  // he sorts — and Sheets draws it by having Google's own servers ask for the
  // address. They cannot be handed his password, and Sheets refuses a picture
  // carried inside the formula ("is not a valid url"), measured 2026-09-04. So
  // the address has to be the permission.
  //
  // **A name nobody can guess, not a door left open.** The name is the first 32
  // characters of the picture's own hash — 128 bits that only exist if you
  // already hold the bytes. Nothing here lists: it answers for one exact name
  // and gives 404 to everything else, so there is no way in from the outside
  // except already knowing the answer.
  if (parts.length === 3 && parts[0] === "i") {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return problem(405, "Wrong method.");
    }
    if (!PROJECT.test(parts[1])) return problem(400, "That is not a project name.");
    if (!PICTURE_NAME.test(parts[2])) return problem(404, "No such address.");
    return await media(request, env, parts[1], parts[2]);
  }

  if (parts[0] !== "v1") return problem(404, "No such address.");
  const who = await authorised(request, env);
  if (!who) return problem(401, "Not signed in.");

  // /v1/projects
  if (parts.length === 2 && parts[1] === "projects") {
    if (request.method !== "GET") return problem(405, "Wrong method.");
    return await listProjects(env);
  }

  // `/v1/devices` — a token per device, minted and revoked with the master
  // password. See `authorised` for why.
  if (parts[1] === "devices") {
    if (!who.master) return problem(403, "Only the master password may manage devices.");
    if (parts.length === 2 && request.method === "GET") return await listDevices(env);
    if (parts.length === 2 && request.method === "POST") return await mintDevice(request, env);
    if (parts.length === 3 && request.method === "DELETE") return await revokeDevice(env, parts[2]);
    return problem(parts.length <= 3 ? 405 : 404, parts.length <= 3 ? "Wrong method." : "No such address.");
  }

  // Everything else is /v1/p/<project>/...
  if (parts[1] !== "p" || parts.length < 3) return problem(404, "No such address.");
  const project = parts[2];
  if (!PROJECT.test(project)) return problem(400, "That is not a project name.");

  const rest = parts.slice(3);

  // `/v1/p/<project>/watch` — the open line. A device holds one while it has
  // the film on screen, and is told the moment anything about it changes, so a
  // change lands in about a second instead of on the next five-minute check.
  //
  // **It tells; it never sends the change itself.** The message is one word.
  // What actually moved is worked out by the same `syncplan` that has always
  // worked it out, so push adds a *reason to sync* and no second idea of what
  // syncing means.
  if (rest.length === 1 && rest[0] === "watch") {
    return await watch(request, env, project);
  }

  // `/v1/p/<project>` — the whole film, gone.
  //
  // **Because the pieces were not enough.** Every route here removes one thing
  // it knows the name of: a log, a picture, the manifest. Nothing owns the
  // files somebody else wrote beside them — the portal keeps a `front.json`
  // next to the logs — so a film taken off by deleting its pieces left that
  // behind, and 268 bytes is enough to keep a film in `/v1/projects` and draw
  // it on his Projects screen as though it were still there. 2026-09-04, doing
  // exactly that by hand.
  //
  // So this one is by prefix and deliberately has no opinion about what it
  // finds: whatever is under the film's name goes with the film. That is what
  // archiving and deleting both need, and neither can be built out of the
  // pieces.
  //
  // **And since 2026-09-16 it remembers why.** `?fate=archived` or
  // `?fate=deleted` leaves a note beside the films, so every other device
  // does the same to its own copy at its next sync instead of asking — his
  // ruling: one Projects list, the same on every device, nothing done twice.
  if (rest.length === 0) {
    if (request.method !== "DELETE") return problem(405, "Wrong method.");
    return await removeProject(env, project, url.searchParams.get("fate"), who);
  }

  // `/v1/p/<project>/back` — the film is coming back from a bin somewhere.
  // The note that it was taken off goes *before* the device syncs, because a
  // sync reads the note first and would otherwise put the film straight back
  // in the bin it just left.
  if (rest.length === 1 && rest[0] === "back") {
    if (request.method !== "PUT" && request.method !== "POST") return problem(405, "Wrong method.");
    await forgetFate(env, project);
    return json({ project, back: true });
  }

  if (rest.length === 1 && rest[0] === "state") {
    if (request.method !== "GET") return problem(405, "Wrong method.");
    return await state(env, project);
  }

  if (rest.length === 1 && rest[0] === "manifest") {
    return await manifest(request, env, project);
  }

  if (rest.length === 2 && rest[0] === "log") {
    return await log(request, env, project, rest[1], url, who);
  }

  if (rest.length === 2 && rest[0] === "media" && rest[1] === "missing") {
    if (request.method !== "POST") return problem(405, "Wrong method.");
    return await missing(request, env, project);
  }

  if (rest.length === 1 && rest[0] === "media") {
    if (request.method !== "GET") return problem(405, "Wrong method.");
    return await mediaList(env, project);
  }

  if (rest.length === 2 && rest[0] === "media") {
    return await media(request, env, project, rest[1], who);
  }

  return problem(404, "No such address.");
}

// ---- the open line -----------------------------------------------------

/**
 * Join the room for one film.
 *
 * **A Durable Object per project.** A plain Worker cannot do this: every
 * request may land in a different isolate, so one has no way to reach the
 * sockets another is holding. A Durable Object is the one thing Cloudflare
 * guarantees is a single place — every device watching the same film reaches
 * the same instance, which is exactly what "tell the others" needs.
 */
async function watch(request, env, project) {
  // **Compared without case.** The header's value is written `websocket` by
  // most clients and `WebSocket` by some, and Cloudflare's edge does not
  // normalise it — an exact match worked in `wrangler dev` and answered 426 on
  // the deployed copy, which is the worst kind of difference to find later.
  if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
    return problem(426, "That address wants a websocket.");
  }
  const room = env.ROOMS.get(env.ROOMS.idFromName(project));
  return await room.fetch(request);
}

/**
 * Say that something about this film changed.
 *
 * **Never allowed to fail the write.** A push is a nicety on top of a sync that
 * already worked: if the room cannot be reached, the device that wrote is still
 * written and every other device still finds it on its next check. Letting this
 * throw would turn a working save into a failed one.
 */
async function tell(env, project, what) {
  try {
    const room = env.ROOMS.get(env.ROOMS.idFromName(project));
    await room.fetch("https://rooms/said", {
      method: "POST",
      body: JSON.stringify({ what }),
    });
  } catch (error) {
    console.error("could not tell the room:", String(error));
  }
}

/**
 * **The room for one film.** Holds a socket per device and passes on one word.
 *
 * It stores nothing and knows nothing about films — the same bargain the rest
 * of the relay strikes. It cannot lose an edit because it never carries one.
 *
 * **Hibernating sockets**, so a phone left open on a stand all day costs
 * nothing: Cloudflare evicts the object from memory and wakes it when a message
 * arrives, keeping the connections open across the gap.
 */
export class Room {
  constructor(state) {
    this.state = state;
  }

  async fetch(request) {
    const url = new URL(request.url);

    if (url.pathname === "/said") {
      const { what } = await request.json();
      // **`getWebSockets`, not a list of our own.** The object may have
      // hibernated since these were accepted, and anything we held in memory
      // went with it; the runtime still has the sockets.
      for (const socket of this.state.getWebSockets()) {
        try {
          socket.send(JSON.stringify({ changed: what }));
        } catch (error) {
          // A socket the far end has already dropped. Nothing to do about it
          // and nothing worth failing for.
        }
      }
      return new Response(null, { status: 204 });
    }

    const pair = new WebSocketPair();
    const [near, far] = Object.values(pair);
    this.state.acceptWebSocket(near);
    return new Response(null, { status: 101, webSocket: far });
  }

  /**
   * **Everything a device says is ignored, on purpose.** The line exists to
   * carry one word outwards. A relay that accepted instructions over a socket
   * would be a second way to change a film, and there is deliberately only one.
   */
  async webSocketMessage(socket, message) {
    // A ping, so a device can prove the line is still alive.
    if (message === "ping") socket.send("pong");
  }

  async webSocketClose(socket) {
    try { socket.close(); } catch (error) { /* already gone */ }
  }
}

/**
 * A fold, carried to the relay — so retired logs stop coming back.
 *
 * **Ref 192, the half that was never built.** When a device folds its old
 * logs into one it writes `<device>.folded` beside them saying what it
 * retired and what it rewrote (`engine::package::FoldRecord`), and every
 * device that reads that record stops fetching the retired ones. The relay
 * never saw the record, so it went on holding every retired log for ever and
 * the hub went on replaying them — harmless, the same change merged twice is
 * nothing, and pointless. This is the relay honouring the record.
 *
 * **Three rules, and they are what make deleting here safe:**
 *
 * 1. A fold may only retire **that device's own logs** — the names begin with
 *    the device in the record's own name. Anything else is refused whole.
 * 2. A retired log goes **only once every log the fold rewrote is here.**
 *    Every change in a retired log is inside a rewritten one; until those
 *    have arrived, taking the retired one away would lose changes. Send the
 *    logs first and the record last, and a record sent early is kept and
 *    honoured the next time it is sent.
 * 3. The record itself is stored under `logs/` like a mark. Devices ignore
 *    it in a listing (`ours` in `remote/src/lib.rs` names only logs and
 *    marks) and the hub reads only `.log`.
 *
 * `GET` hands it back; `PUT` stores and applies it. The reply says what it
 * retired now and what is still waiting on a rewritten log.
 */
async function fold(request, env, project, name, who) {
  const key = keys.log(project, name);
  if (request.method === "GET") {
    const object = await env.BUCKET.get(key);
    if (!object) return problem(404, "No such record.");
    return new Response(object.body, { headers: { "content-type": "text/plain; charset=utf-8" } });
  }
  if (request.method !== "PUT") return problem(405, "Wrong method.");

  const text = await request.text();
  if (text.length > MAX_LOG) return problem(413, "That record is too big.");
  const device = name.slice(0, 16);
  const retired = [];
  const rewritten = [];
  for (const line of text.split("\n")) {
    const at = line.indexOf("\t");
    if (at < 0) continue;
    const mark = line.slice(0, at);
    const named = line.slice(at + 1).trim();
    if (!LOG_NAME.test(named)) continue;
    if (!named.startsWith(`${device}-`)) {
      return problem(400, `A fold may only retire its own device's logs, and ${named} is not one.`);
    }
    if (mark === "R") retired.push(named);
    else if (mark === "W") rewritten.push(named);
  }

  await env.BUCKET.put(key, text, {
    httpMetadata: { contentType: "text/plain; charset=utf-8" },
    customMetadata: wroteBy(who),
  });

  // Rule 2: nothing goes until every rewritten log is here.
  for (const named of rewritten) {
    if (!(await env.BUCKET.head(keys.log(project, named)))) {
      return json({ name, stored: true, retired: 0, waiting: retired.length, missing: named });
    }
  }
  let gone = 0;
  for (const named of retired) {
    if (rewritten.includes(named)) continue;
    const held = await env.BUCKET.head(keys.log(project, named));
    if (!held) continue;
    await env.BUCKET.delete(keys.log(project, named));
    gone += 1;
  }
  if (gone) await tell(env, project, "logs");
  return json({ name, stored: true, retired: gone, waiting: 0 });
}

// ---- what is here ------------------------------------------------------

/**
 * Every log and mark in a project, with its size.
 *
 * Size is the whole comparison, and it is enough because a log only ever grows:
 * same name and same length means the same bytes. That is the same reasoning
 * `storage/` uses on disk, where it compares a size and a date rather than
 * hashing a file it is about to read anyway.
 */
async function state(env, project) {
  const logs = await listAll(env, keys.logs(project), true);
  const note = logs.length === 0 ? await fateOf(env, project) : null;
  return json({
    project,
    ...(note ? { gone: note.fate, when: note.when } : {}),
    logs: logs.map((object) => ({
      name: object.key.slice(keys.logs(project).length),
      size: object.size,
      // Which device put it there, when a device token did. Absent for a log
      // written with the master password — there is nothing to say.
      ...(object.customMetadata && object.customMetadata.by ? { by: object.customMetadata.by } : {}),
    })),
  });
}

/**
 * Everything under one film's name, deleted.
 *
 * **A thousand at a time**, which is R2's own limit on a batched delete and the
 * same page size `listAll` reads in. A film with three hundred photographs is
 * one page and one delete; nothing here assumes that.
 *
 * It answers with the count rather than a bare ok, because the app says
 * *nothing was there* and *forty-one files went* differently, and the second is
 * the one worth being sure of before a folder is moved on this Mac.
 */
async function removeProject(env, project, fate, who) {
  const objects = await listAll(env, keys.film(project));
  const held = objects.map((object) => object.key);
  // **The portal is set aside before anything goes** (2026-10-04, his ask:
  // "without wiping any data — I have teams relying on my current portal").
  // If the copy cannot be finished, nothing is removed at all.
  let kept;
  try {
    kept = await setAside(env, project, fate, who, held);
  } catch (error) {
    return problem(500, "The portal could not be set aside, so nothing was removed. Try again.");
  }
  for (let at = 0; at < held.length; at += 1000) {
    await env.BUCKET.delete(held.slice(at, at + 1000));
  }
  if (fate === "archived" || fate === "deleted") {
    const note = { project, fate, when: new Date().toISOString(), by: (who && who.name) || "" };
    await env.BUCKET.put(keys.gone(project), JSON.stringify(note), {
      httpMetadata: { contentType: "application/json" },
    });
  } else {
    await forgetFate(env, project);
  }
  return json({ project, gone: held.length, fate: fate || null, kept });
}

/**
 * **Copy the portal's own files to `kept/` before the film is taken off.**
 *
 * Everything under the film's name except the film itself: not the change
 * logs, device marks, manifest or pictures — those are the film, and the film
 * stays whole on the Mac it was archived or binned on (and in the daily
 * backup). What is copied is what lives only here: `people.json` (invites and
 * share links), `visible.json`, `front.json`, `down.json`, `views.json`, the
 * written pages, documents, decks and boards.
 *
 * **One object at a time**, as `hub/src/carry.js` does: an R2 body is an open
 * response until it is read, and only a few may be open at once. A film with
 * a thousand documents is a few thousand calls, well inside the 10,000 a
 * request may make. Throws on any failure, so the caller removes nothing.
 * Answers where the copy is and how many files it holds, or `null` when the
 * film had no portal files to keep.
 */
async function setAside(env, project, fate, who, held) {
  const prefix = keys.film(project);
  const filmFolders = [LAYOUT.logs, LAYOUT.devices, LAYOUT.media];
  const wanted = held.filter((key) => {
    const rest = key.slice(prefix.length);
    return rest && rest !== LAYOUT.manifest && !filmFolders.some((folder) => rest.startsWith(folder));
  });
  if (wanted.length === 0) return null;
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const into = keys.kept(project, stamp);
  for (const key of wanted) {
    const object = await env.BUCKET.get(key);
    if (!object) continue; // gone between the listing and now: nothing to keep
    await env.BUCKET.put(into + key.slice(prefix.length), object.body, {
      httpMetadata: object.httpMetadata,
      customMetadata: object.customMetadata,
    });
  }
  const note = { project, fate: fate || null, when: new Date().toISOString(), by: (who && who.name) || "", files: wanted.length };
  await env.BUCKET.put(`${into}kept.json`, JSON.stringify(note), {
    httpMetadata: { contentType: "application/json" },
  });
  return { at: into, files: wanted.length };
}

/** The note left when a film was taken off, or null. */
async function fateOf(env, project) {
  const object = await env.BUCKET.get(keys.gone(project));
  if (!object) return null;
  try { return await object.json(); } catch (error) { return null; }
}

/** A film written to again is back; its note goes. */
async function forgetFate(env, project) {
  await env.BUCKET.delete(keys.gone(project));
}

async function listProjects(env) {
  const found = new Map();
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: LAYOUT.prefix, cursor, limit: 1000 });
    for (const object of page.objects) {
      const name = object.key.split("/")[1];
      if (!name) continue;
      // **A loose file is not a film.** Everything else here reaches a project
      // through `PROJECT`, so a key that never went through a route — a file
      // written straight into `p/` — arrived under no name at all and this was
      // the one place that took it for one. A stray `p/people.json` drew a film
      // called `people.j` on his Projects screen for a week: it could not be
      // opened, because every other route refuses the name, and it could not be
      // binned, because it was on no Mac. Reported 2026-09-04.
      if (!PROJECT.test(name)) continue;
      const seen = found.get(name) || { project: name, logs: 0, media: 0, bytes: 0 };
      if (object.key.includes(`/${LAYOUT.logs}`)) seen.logs += 1;
      if (object.key.includes(`/${LAYOUT.media}`)) seen.media += 1;
      // **A portal with no film is not a film.** The hub marks a project's
      // own prefix with `portal.json` when the console makes it a web portal
      // with no Shotlister film behind it (2026-09-16). Listed here it would
      // reach every Mac and iPhone as a film with nothing in it, named by
      // its id — the `people.j` fault again, by design this time.
      if (object.key === `${LAYOUT.prefix}${name}/${LAYOUT.hub.portal}`) seen.portal = true;
      if (object.key === `${LAYOUT.prefix}${name}/${LAYOUT.manifest}`) seen.manifest = true;
      seen.bytes += object.size;
      found.set(name, seen);
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  // **Logs do not make it a film** (SL-1376). This used to keep a portal
  // once it had any, and on 2026-10-01 a chat wrote two into Halcyon: every
  // Mac and iPhone was offered a film with no manifest. The one rule, the
  // same function the hub asks (`relay/portal.js`): a mark and no manifest.
  for (const [name, seen] of found) {
    if (filmless({ mark: seen.portal, manifest: seen.manifest })) found.delete(name);
    // **Leftovers are not a film** (2026-10-17). A project deleted from the
    // console can have a few portal files written back under its old id (a
    // front page, cover pictures): no manifest and no change logs. Listed, it
    // drew a nameless project on every Mac and iPhone that could not be
    // opened or deleted. A prefix with neither is nothing to fetch.
    else if (!seen.manifest && seen.logs === 0) found.delete(name);
    delete seen.portal;
    delete seen.manifest;
  }
  // The films that were taken off, with why — a device with a copy of one
  // acts on this row; a device without one draws nothing from it.
  for (const object of await listAll(env, LAYOUT.gone)) {
    const name = object.key.slice(LAYOUT.gone.length).replace(/\.json$/, "");
    if (!PROJECT.test(name) || found.has(name)) continue;
    const note = await fateOf(env, name);
    if (note && note.fate) found.set(name, { project: name, logs: 0, media: 0, bytes: 0, gone: note.fate });
  }
  return json({ projects: [...found.values()] });
}

// ---- logs --------------------------------------------------------------

async function log(request, env, project, name, url, who = MASTER) {
  if (FOLD_NAME.test(name)) return await fold(request, env, project, name, who);
  if (!LOG_NAME.test(name) && !MARK_NAME.test(name)) {
    return problem(400, "That is not a log name.");
  }
  const key = keys.log(project, name);

  if (request.method === "GET") {
    const object = await env.BUCKET.get(key);
    if (!object) return problem(404, "No such log.");
    return new Response(object.body, {
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }

  if (request.method === "PUT") {
    const body = new Uint8Array(await request.arrayBuffer());
    if (body.byteLength > MAX_LOG) return problem(413, "That log is too big.");

    // **A log may only ever grow.** An identity mark is empty by design and
    // written once, so it skips the check rather than tripping it.
    if (LOG_NAME.test(name) && !url.searchParams.has("rewrite")) {
      const held = await env.BUCKET.get(key);
      if (held) {
        const before = new Uint8Array(await held.arrayBuffer());
        if (!startsWith(body, before)) {
          return problem(
            409,
            "That would rewrite a log rather than add to it. Send ?rewrite=1 if that is meant."
          );
        }
      }
    }

    await env.BUCKET.put(key, body, { customMetadata: wroteBy(who) });
    // A log under the name again means the film is back — put back from a
    // bin somewhere — so the note that it was taken off goes.
    await forgetFate(env, project);
    // **After the write, never before.** A device told to sync before the bytes
    // are readable would fetch the old state and be told nothing again.
    await tell(env, project, "logs");
    return json({ name, size: body.byteLength });
  }

  if (request.method === "DELETE") {
    await env.BUCKET.delete(key);
    await tell(env, project, "logs");
    return json({ name, gone: true });
  }

  return problem(405, "Wrong method.");
}

// ---- media -------------------------------------------------------------

/**
 * Which of these the relay has not got.
 *
 * Asked as one question rather than one HEAD per picture, because a film has
 * hundreds and a phone on a set has one bar of signal.
 */
async function missing(request, env, project) {
  let asked;
  try {
    asked = await request.json();
  } catch {
    return problem(400, "That was not readable.");
  }
  const names = Array.isArray(asked?.names) ? asked.names : null;
  if (!names) return problem(400, 'Send {"names": [...]}.');
  if (names.length > 10000) return problem(413, "Too many at once.");

  const prefix = keys.media(project);
  const here = new Set(
    (await listAll(env, prefix)).map((object) => object.key.slice(prefix.length))
  );
  return json({
    missing: names.filter((name) => MEDIA_NAME.test(name) && !here.has(name)),
  });
}

/** Everything the relay holds for a project, so a device can see what it lacks. */
async function mediaList(env, project) {
  const prefix = keys.media(project);
  const objects = await listAll(env, prefix);
  return json({
    media: objects.map((object) => ({
      name: object.key.slice(prefix.length),
      size: object.size,
      // When it landed. A device tidying files the film no longer names
      // waits on this before it will take one away — a file can arrive a
      // moment before the log that names it, and a listing read in that
      // moment must not be a reason to delete it.
      uploaded: object.uploaded instanceof Date ? object.uploaded.toISOString() : String(object.uploaded || ""),
    })),
  });
}

async function media(request, env, project, name, who = MASTER) {
  if (!MEDIA_NAME.test(name)) return problem(400, "That is not a picture's name.");
  const key = keys.medium(project, name);
  const extension = name.split(".").pop().toLowerCase();
  const type = MIME[extension] || "application/octet-stream";

  if (request.method === "GET") {
    // A range header is handed straight through, so a browser can seek inside
    // a clip rather than swallowing the whole file to play the middle.
    //
    // **Whether this is a partial answer is decided by the question, not by
    // the reply.** R2 fills in `object.range` for an ordinary whole-file get
    // as well, so trusting it meant *every* picture came back `206 Partial
    // Content` — true enough that browsers and URLSession both shrugged, and
    // wrong in a way that would eventually meet something stricter. Caught by
    // the check that came with `DELETE`, which is the only reason it is not
    // still there.
    const asked = request.headers.get("range");
    const object = await env.BUCKET.get(key, asked ? { range: request } : undefined);
    if (!object) return problem(404, "Not here.");
    const headers = {
      // The name is a hash, so these bytes can never become other bytes.
      "cache-control": "public, max-age=31536000, immutable",
      "content-type": type,
      "accept-ranges": "bytes",
      etag: object.httpEtag,
    };
    if (asked && object.range) {
      const start = object.range.offset ?? 0;
      const length = object.range.length ?? object.size - start;
      headers["content-range"] = `bytes ${start}-${start + length - 1}/${object.size}`;
      return new Response(object.body, { status: 206, headers });
    }
    return new Response(object.body, { headers });
  }

  if (request.method === "HEAD") {
    const object = await env.BUCKET.head(key);
    if (!object) return problem(404, "Not here.");
    return new Response(null, {
      status: 200,
      headers: { "content-type": type, "content-length": String(object.size) },
    });
  }

  if (request.method === "PUT") {
    // **Written once and never again.** The name is a hash, so what is here is
    // already what was going to be sent — and repeating an upload that was cut
    // off halfway is therefore free rather than dangerous.
    if (await env.BUCKET.head(key)) return json({ name, stored: false });

    const body = new Uint8Array(await request.arrayBuffer());
    if (body.byteLength > MAX_MEDIA) return problem(413, "That file is too big.");

    // Checked only when the sender claims it. See the note at the top about
    // the still that stands for a clip, which shares a name and not its bytes.
    const claimed = (request.headers.get("x-sha256") || "").toLowerCase();
    if (claimed) {
      if (!SHA256.test(claimed)) return problem(400, "That is not a hash.");
      const actual = await sha256(body);
      if (actual !== claimed) {
        return problem(400, `Those bytes are ${actual}, not ${claimed}.`);
      }
    }

    await env.BUCKET.put(key, body, { httpMetadata: { contentType: type }, customMetadata: wroteBy(who) });
    // **Pictures are told about too**, even though nothing fetches them
    // automatically. A device deciding *when* to ask for pictures is the app's
    // business; knowing there are new ones to ask for is this one's.
    await tell(env, project, "media");
    return json({ name, stored: true });
  }

  // **Giving the bytes back.** The local store already does this — a picture
  // nothing points at any more, once every device has heard about the
  // deletion, gives its space back (`reclaim_orphans`, Ref 192). Without this
  // the relay was the one place a deleted photograph lived for ever, and there
  // was no way to tidy one off even deliberately.
  //
  // Deliberately dumb, like everything here: it deletes what it is told to and
  // has no opinion about whether anything still points at it. Deciding that is
  // the engine's, which is the only thing that knows.
  if (request.method === "DELETE") {
    await env.BUCKET.delete(key);
    return json({ name, gone: true });
  }

  return problem(405, "Wrong method.");
}

// ---- the manifest ------------------------------------------------------

async function manifest(request, env, project) {
  const key = keys.manifest(project);

  if (request.method === "GET") {
    const object = await env.BUCKET.get(key);
    if (!object) return problem(404, "No manifest.");
    return new Response(object.body, {
      headers: { "content-type": "application/json" },
    });
  }

  if (request.method === "PUT") {
    const body = new Uint8Array(await request.arrayBuffer());
    if (body.byteLength > 64 * 1024) return problem(413, "That is not a manifest.");
    await env.BUCKET.put(key, body, {
      httpMetadata: { contentType: "application/json" },
    });
    await forgetFate(env, project);
    return json({ project, size: body.byteLength });
  }

  // So a project can be taken off the relay completely. Without it the last
  // 106 bytes of a film stayed for ever and kept it in the list of projects,
  // which reads as "this is still here" when nothing of it is.
  if (request.method === "DELETE") {
    await env.BUCKET.delete(key);
    return json({ project, gone: true });
  }

  return problem(405, "Wrong method.");
}

// ---- the plumbing ------------------------------------------------------

async function listAll(env, prefix, withMetadata = false) {
  const objects = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({
      prefix, cursor, limit: 1000,
      ...(withMetadata ? { include: ["customMetadata"] } : {}),
    });
    objects.push(...page.objects);
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return objects;
}

async function sha256(bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function startsWith(body, before) {
  if (body.byteLength < before.byteLength) return false;
  for (let at = 0; at < before.byteLength; at += 1) {
    if (body[at] !== before[at]) return false;
  }
  return true;
}

/** The master password speaking — the one in his Keychain, the console's, the setup door's. */
const MASTER = { master: true, name: "" };

/**
 * Who is asking: the master password, one of his devices, or nobody.
 *
 * **Two kinds of key, since 2026-09-16.** The master password (`TOKEN`, a
 * secret) is what Set Up Sync made and what his Keychain, the console and the
 * hub's door all hold; it mints and revokes the second kind. A *device token*
 * is minted for one Mac or one phone, kept in the bucket as the hash of the
 * token and a name, and can be taken away without touching any other device.
 * Until then the relay could not tell the Mac from the phone from anyone
 * holding the one password, and "a log may only grow" was the only safety —
 * the README said so from the start. Now a write can say who made it.
 *
 * The master is compared over the whole length rather than bailing at the
 * first wrong character, so how long the answer takes says nothing about how
 * much of it was right. A device token is looked up by its hash, which is
 * constant-time by construction.
 */
async function authorised(request, env) {
  const expected = env.TOKEN;
  if (!expected) return null;
  const given = (request.headers.get("authorization") || "").replace(/^Bearer /, "");
  if (given.length === expected.length) {
    let difference = 0;
    for (let at = 0; at < expected.length; at += 1) {
      difference |= given.charCodeAt(at) ^ expected.charCodeAt(at);
    }
    if (difference === 0) return MASTER;
  }
  if (!DEVICE_TOKEN.test(given)) return null;
  const id = await sha256(new TextEncoder().encode(given));
  const held = await env.BUCKET.get(keys.device(id));
  if (!held) return null;
  let device;
  try {
    device = await held.json();
  } catch {
    return null;
  }
  if (!device || typeof device.name !== "string") return null;
  // `seen` moves at most once an hour: enough to say which device is still in
  // use, cheap enough to do on the way past.
  const now = Date.now();
  if (!device.seen || now - Date.parse(device.seen) > 60 * 60 * 1000) {
    device.seen = new Date(now).toISOString();
    await env.BUCKET.put(keys.device(id), JSON.stringify(device), {
      httpMetadata: { contentType: "application/json" },
    });
  }
  return { master: false, name: device.name, id };
}

/** A device token: 64 hex characters, minted here and nowhere else. */
const DEVICE_TOKEN = /^[0-9a-f]{64}$/;

/** What a write is stamped with — nothing, for the master. */
function wroteBy(who) {
  return who && !who.master && who.name ? { by: who.name } : undefined;
}

// ---- devices -----------------------------------------------------------

/** Mint a token for one device. The token is shown once, here, and never stored. */
async function mintDevice(request, env) {
  let asked;
  try {
    asked = await request.json();
  } catch {
    return problem(400, "Send a JSON body with the device's name.");
  }
  const name = String((asked && asked.name) || "").replace(/\s+/g, " ").trim().slice(0, 80);
  if (!name) return problem(400, "A device needs a name.");
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const token = [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
  const id = await sha256(new TextEncoder().encode(token));
  const made = new Date().toISOString();
  await env.BUCKET.put(keys.device(id), JSON.stringify({ name, made, seen: "" }), {
    httpMetadata: { contentType: "application/json" },
  });
  return json({ id, name, made, token }, 201);
}

/** Every device with a token, by name — never a token, which is not kept. */
async function listDevices(env) {
  const objects = await listAll(env, keys.devices());
  const devices = [];
  for (const object of objects) {
    const held = await env.BUCKET.get(object.key);
    if (!held) continue;
    try {
      const device = await held.json();
      devices.push({
        id: object.key.slice(keys.devices().length, -".json".length),
        name: device.name || "",
        made: device.made || "",
        seen: device.seen || "",
      });
    } catch {
      // a record that will not parse is not a device
    }
  }
  devices.sort((a, b) => a.name.localeCompare(b.name));
  return json({ devices });
}

/** Take a device's token away. Its logs stay; only its key stops working. */
async function revokeDevice(env, id) {
  if (!DEVICE_TOKEN.test(id)) return problem(400, "That is not a device id.");
  const held = await env.BUCKET.head(keys.device(id));
  if (!held) return problem(404, "No such device.");
  await env.BUCKET.delete(keys.device(id));
  return json({ id, revoked: true });
}

/**
 * The deploy this relay came from. `BUILD` is Cloudflare's own id for the
 * uploaded version (`[version_metadata]` in wrangler.toml); `COMMIT` is ours.
 */
function versionOf(env) {
  return {
    relay: "shotlister",
    commit: env.COMMIT || "unknown",
    deployed: env.DEPLOYED || null,
    build: env.BUILD && env.BUILD.id ? env.BUILD.id.slice(0, 8) : null,
  };
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function problem(status, said) {
  return json({ problem: said }, status);
}

function cors(response) {
  // **A websocket upgrade goes back untouched.** Rebuilding a response is how
  // this adds its headers, and `new Response(…, { status: 101 })` is illegal —
  // the runtime allows 200 to 599 and nothing else. The only legal way to make
  // a 101 is the `webSocket:` form the room already returned, so passing it
  // through here threw *"Responses may only be constructed with status codes in
  // the range 200 to 599"* and the client saw a 500 with no explanation.
  //
  // Nothing is lost by skipping it: a websocket handshake has no use for CORS
  // headers, and the browser rules it exists for do not apply to one.
  if (response.status === 101) return response;

  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-expose-headers", "etag");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function preflight() {
  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET, PUT, POST, DELETE, HEAD, OPTIONS",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-max-age": "86400",
    },
  });
}
