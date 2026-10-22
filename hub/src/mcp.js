/**
 * The MCP, on an address any AI can reach.
 *
 * His ask, 2026-09-01: *"can you work on getting the mcp up and running
 * anywhere an ai could use it? i now have a domain for this project."*
 *
 * ## What this is
 *
 * The same tools the Mac has had since the MCP was written —
 * `mcp/src/server.rs`, compiled to WebAssembly without its `disk` feature and
 * driven from here (`mcpweb/`). Not a second implementation. A second
 * implementation would have drifted inside a week, and the one nobody was
 * sitting in front of would have been the one that drifted.
 *
 * ## Why it has a host of its own
 *
 * Cloudflare Access stands in front of `your-domain.example` and answers a
 * request it does not recognise with a sign-in page. Right for a person,
 * useless for a program: an AI would be handed HTML asking it to check its
 * email. So this lives on `mcp.your-domain.example`, where there is no
 * Access application, and does its own asking — and when it needs to know who
 * somebody is, it sends their **browser** to the apex, where Access does know.
 *
 * The alternative was a handful of bypass rules in his Cloudflare dashboard,
 * every one of them a click he would have to get exactly right and none of them
 * visible from in here.
 *
 * ## Signing in, in order
 *
 * 1. The AI registers itself (`/register`) and sends the person to `/authorize`.
 * 2. `/authorize` has no idea who they are, so it sends their browser to the
 *    apex carrying a signed note saying what was asked for.
 * 3. The apex is behind Access, so by the time the worker sees that request it
 *    knows the address. It signs *that* onto the note and sends the browser back.
 * 4. Back here, the person is shown what is asking and presses one button.
 * 5. The AI swaps its code for a token and uses it on every call afterwards.
 *
 * **Nothing here trusts a header.** The note between the two hosts is signed
 * with `HUB_SECRET`, and the address inside it is only ever one Access itself
 * put there.
 *
 * ## What a call actually costs
 *
 * Every request starts the film again: list the logs, fetch them, replay them,
 * answer, and — if the tool changed something — put a new log in the bucket. A
 * worker holds nothing between requests, so this is not a shortcut, it is the
 * only honest thing available. It is also cheap: his largest film is 6,497
 * changes across 118 logs and replays in a few milliseconds. The logs are held
 * in Cloudflare's cache under a key made of their own names and sizes, so the
 * fetching happens once per change rather than once per question.
 */

import { setFollow, followStateOf, driveReady } from "./docfollow.js";
import { viewsOf, viewPath, makeView, changeView, removeView } from "./views.js";
import { keeps, named } from "../public/narrow.js";
import { keys } from "../../relay/layout.js";
import mcpWasm from "./mcp.wasm";
import puppeteer from "@cloudflare/puppeteer";
import { begin, feed, put, take } from "./live.js";

import {
  EMAIL,
  PROJECT,
  filmlessPortal,
  filmsFor,
  listAll,
  maySee,
  pageOf,
  roleFor,
  sha256Hex,
  titleOf,
  visibleOf,
  saveVisible,
  isAdmin,
  owners,
  peopleOf,
  savePeople,
  boardOpen,
  pageHtmlOf,
  shortOf,
  movePage,
  renameDocument,
  forgetMoves,
} from "./films.js";
import { Refusal, changeAccess } from "./access.js";
import { ATTACH_TOOL, attachTool, REFRESH_TOOL, refreshTool } from "./mcpattach.js";
import { BOARD_TOOLS, base64Of, boardTool, pictureInto, driveIdOf } from "./boards.js";
import { ICON_CHOICES } from "./icons.js";
import { everyone, FILE_NAME, frontOf, PAGE_SOURCES, saveFront, setIcon, setArchived, setOnSidebar, offSidebar, isArchived, setShelf, shelfOf, shelfIdFor, shelfList, shelfNames, editShelves, arrangeRail, applyOrder, shotView, tidy } from "./front.js";
import { MAX_PAGE, markdownFrom, pageFrom, slugFrom } from "./paper.js";
import { unfilled } from "./pages.js";
import { writeFacts } from "./facts.js";
import { carriedTo } from "./carry.js";
import { withLensSets } from "./lenses.js";
import { BY, LABEL, RECORD_TOOLS, RECORD_TOOL_NAMES, conflictSaid, datesFrom, filmNamesToRecord, namesFromRecord,
  planFacts, recordOfOpen, recordTool } from "./recordtools.js";
import { KIT_TOOLS, KIT_TOOL_NAMES, kitTool, kitArguments, LIBRARY_TOOLS, LIBRARY_TOOL_NAMES, libraryTool } from "./kittools.js";
import { projectRows, findProject, followOpen, noSideSaid, openedNoSide, MODES_TOOL, modesTool, shownRow, projectFacts } from "./mcpprojects.js";
import { MODS_TOOL, modsTool } from "./mcpmods.js";
import { SHOOT_TOOLS, SHOOT_TOOL_NAMES, shootToolRun } from "./mcpshoots.js";
import { resolveProject, studioOf } from "./projectid.js";
import { EXPORT_TOOL, exportTool } from "./exporting.js";
import { CONSOLE_TOOLS, CONSOLE_TOOL_NAMES, CONSOLE_GLOBAL, consoleTool } from "./consoletools.js";
import { HUB_GATED, needsGate, hubGate, gatedListing } from "./mcpgate.js";

/** The host this answers on. `mcp.your-domain.example`. */
export const MCP_HOST_PREFIX = "mcp.";

const PROTOCOL_VERSION = "2024-11-05";

/** How long a token is good for. Long, because signing in again is a chore. */
const TOKEN_LIFE = 90 * 24 * 3600 * 1000;
/** A code is swapped within seconds or it is stale. */
const CODE_LIFE = 5 * 60 * 1000;
/** The note passed between the two hosts. Long enough to sign in, no longer. */
const NOTE_LIFE = 15 * 60 * 1000;

/**
 * **The largest message a signed-in caller may send.** It was 1 MB, which
 * quietly refused every file sent as itself — a board's picture or clip
 * (`set_board`), and `add_document` above about 750 KB despite its own 6 MB
 * promise. Only a caller with a token gets this far (`rpc`), and base64 is a
 * third larger than the file, so this carries a 28 MB file with room over.
 */
const MAX_BODY = 40 * 1024 * 1024;

/**
 * What separates one change log from the next inside the cached blob.
 *
 * A log is text, and every byte of it is a printable line — so a NUL cannot
 * appear in one, which is what makes it safe to split on. Joining them with a
 * newline would be a bug: each log begins with its own header line, and the
 * engine reads a log whole.
 */
/**
 * Tools this host cannot honestly offer.
 *
 * Both want a filesystem — one reads a file off the Mac to pin to a shot, the
 * other writes the list out to a path. The engine refuses them with a plain
 * sentence if they are called anyway; taking them off the list is so that an AI
 * does not spend a turn discovering it.
 */
// `export` is the Mac's (it writes to a path on his disk); the portal's own
// `export` (`exporting.js`) stands in its place and files in Drive.
const NOT_HERE = new Set(["attach", "export"]);
/** Asked of the engine by `exporting.js` only, never by name from outside. */
const INSIDE_ONLY = new Set(["export_pages", "export_sheet"]);

// ------------------------------------------------------------------- routing

export async function serveMcp(request, env, asked, ctx, host) {
  // **The name it was asked for, not the one it arrived as.** Every address
  // this hands out — the token endpoint, the redirect to the apex, the note it
  // signs — has to be one an AI can come back to. `worker.js` works the name
  // out; see `hostAsked` there for why it is not simply `url.host`.
  const url = new URL(asked);
  if (host) url.host = host;

  const path = url.pathname.replace(/\/+$/, "") || "/";

  if (path === "/health") {
    return json({
      mcp: "shotlister",
      version: 1,
      access: Boolean(env.ACCESS_TEAM && env.ACCESS_AUD),
      signing: Boolean(env.HUB_SECRET),
      // Every address this hands an AI is built from this. When a client says
      // it cannot sign in, look here first.
      here: origin(url),
      apex: apexOrigin(url),
    });
  }

  // ---- what an MCP client reads before it knows how to sign in ------------
  if (path === "/.well-known/oauth-protected-resource" || path === "/.well-known/oauth-protected-resource/mcp") {
    return json({
      resource: origin(url),
      authorization_servers: [origin(url)],
      scopes_supported: ["shotlister"],
      bearer_methods_supported: ["header"],
    });
  }
  if (
    path === "/.well-known/oauth-authorization-server" ||
    path === "/.well-known/oauth-authorization-server/mcp" ||
    path === "/.well-known/openid-configuration"
  ) {
    return json({
      issuer: origin(url),
      authorization_endpoint: `${origin(url)}/authorize`,
      token_endpoint: `${origin(url)}/token`,
      registration_endpoint: `${origin(url)}/register`,
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      scopes_supported: ["shotlister"],
    });
  }

  if (path === "/register") return await register(request, env);
  if (path === "/authorize") return await authorize(request, env, url);
  if (path === "/token") return await token(request, env);

  // ---- the endpoint itself -----------------------------------------------
  //
  // Both addresses, so what he pastes into an AI can be the bare host. Some
  // clients append `/mcp` on their own and some do not.
  if (path === "/" || path === "/mcp") {
    if (request.method === "POST") return await rpc(request, env, url, ctx);
    // **A client asking to open a stream is told no, not handed a web page.**
    // Some of them try `GET` with `Accept: text/event-stream` before they will
    // use plain request-and-answer; a 200 full of HTML reads to them as a
    // stream that never says anything.
    const wants = request.headers.get("accept") || "";
    if (request.method === "GET" && wants.includes("text/event-stream")) {
      return problem(405, "There is no stream here. Post a JSON-RPC message instead.");
    }
    if (request.method === "GET" && path === "/") return frontDoor(url);
    // A GET on `/mcp` is a client asking to open a stream it will be told
    // about over. Nothing here pushes, so saying so plainly beats a hang.
    return problem(405, "Post a JSON-RPC message here.");
  }

  return problem(404, "No such address.");
}

function origin(url) {
  return `${url.protocol}//${url.host}`;
}

/** The apex, where Access knows people. `mcp.x.studio` becomes `x.studio`. */
function apexOrigin(url) {
  const host = url.host.startsWith(MCP_HOST_PREFIX) ? url.host.slice(MCP_HOST_PREFIX.length) : url.host;
  return `${url.protocol}//${host}`;
}

// ---------------------------------------------------------- signing the notes

/**
 * Sign a small object so the other host can trust it.
 *
 * The two hosts are the same worker, which is exactly why this is needed rather
 * than exactly why it is not: what travels between them is a redirect through
 * somebody's browser, and a browser is a place anybody can type.
 */
async function seal(env, kind, body) {
  const secret = String(env.HUB_SECRET || "");
  if (!secret) throw refuse("This hub has no signing key yet.");
  const payload = base64url(JSON.stringify({ kind, until: Date.now() + NOTE_LIFE, ...body }));
  const key = await signingKey(secret);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return `${payload}.${base64urlBytes(new Uint8Array(mac))}`;
}

async function unseal(env, kind, sealed) {
  const secret = String(env.HUB_SECRET || "");
  if (!secret || typeof sealed !== "string") return null;
  const [payload, mac] = sealed.split(".");
  if (!payload || !mac) return null;
  const key = await signingKey(secret);
  const want = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  if (base64urlBytes(new Uint8Array(want)) !== mac) return null;
  let body;
  try {
    body = JSON.parse(unbase64url(payload));
  } catch {
    return null;
  }
  if (body.kind !== kind) return null;
  if (!body.until || Date.now() > body.until) return null;
  return body;
}

function signingKey(secret) {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

// ------------------------------------------------------------ who is asking

/**
 * Register a client. Anybody may — that is what dynamic registration is, and it
 * is what lets him paste one address into any AI rather than making a client id
 * by hand for each one.
 *
 * A registration on its own gets nobody anything: the next step is a person
 * signing in with Cloudflare, and after that a film they have a part in.
 */
async function register(request, env) {
  if (request.method !== "POST") return problem(405, "Wrong method.");
  let said;
  try {
    said = await request.json();
  } catch {
    return problem(400, "That is not a registration.");
  }
  const redirects = (Array.isArray(said.redirect_uris) ? said.redirect_uris : [])
    .filter((u) => typeof u === "string" && u.length < 2000)
    .slice(0, 8);
  if (!redirects.length) return problem(400, "A client needs somewhere to be sent back to.");

  const id = random(24);
  const client = {
    client_id: id,
    client_name: String(said.client_name || "An AI").slice(0, 80),
    redirect_uris: redirects,
    made: new Date().toISOString(),
  };
  await env.BUCKET.put(`mcp/clients/${id}.json`, JSON.stringify(client), {
    httpMetadata: { contentType: "application/json" },
  });
  return json(
    {
      ...client,
      token_endpoint_auth_method: "none",
      grant_types: ["authorization_code", "refresh_token"],
      response_types: ["code"],
    },
    201
  );
}

async function clientOf(env, id) {
  if (!/^[A-Za-z0-9_-]{10,80}$/.test(String(id || ""))) return null;
  const got = await env.BUCKET.get(`mcp/clients/${id}.json`);
  if (!got) return null;
  try {
    return await got.json();
  } catch {
    return null;
  }
}

/**
 * The sign-in, in three visits: asked, sent to the apex to be recognised, and
 * back here to be shown what is happening and press one button.
 */
async function authorize(request, env, url) {
  if (!env.HUB_SECRET) {
    return page(500, "Not finished setting up", "Double-click Set Up the Hub and run it again.");
  }

  // ---- third visit: the person pressed Allow ------------------------------
  if (request.method === "POST") {
    const form = await request.formData();
    const granted = await unseal(env, "granted", form.get("grant"));
    if (!granted) return page(403, "That took too long", "Go back to the app and connect again.");
    if (form.get("answer") !== "yes") {
      return sendBack(granted.ask, { error: "access_denied", state: granted.ask.state });
    }
    const code = random(32);
    await env.BUCKET.put(
      `mcp/codes/${code}.json`,
      JSON.stringify({
        email: granted.email,
        client_id: granted.ask.client_id,
        redirect_uri: granted.ask.redirect_uri,
        code_challenge: granted.ask.code_challenge,
        until: Date.now() + CODE_LIFE,
      }),
      { httpMetadata: { contentType: "application/json" } }
    );
    return sendBack(granted.ask, { code, state: granted.ask.state });
  }

  // ---- second visit: back from the apex, carrying an address --------------
  const grant = url.searchParams.get("grant");
  if (grant) {
    const granted = await unseal(env, "granted", grant);
    if (!granted) return page(403, "That took too long", "Go back to the app and connect again.");
    const client = await clientOf(env, granted.ask.client_id);
    return consent(granted, client, grant, url);
  }

  // ---- first visit: work out what is being asked for ---------------------
  const ask = {
    client_id: url.searchParams.get("client_id") || "",
    redirect_uri: url.searchParams.get("redirect_uri") || "",
    state: url.searchParams.get("state") || "",
    code_challenge: url.searchParams.get("code_challenge") || "",
    method: url.searchParams.get("code_challenge_method") || "",
  };
  const client = await clientOf(env, ask.client_id);
  if (!client) return page(400, "Unknown app", "This app is not registered here. Remove the connector in the app and add it again.");
  if (!client.redirect_uris.includes(ask.redirect_uri)) {
    // Refused rather than redirected: an address the client never registered is
    // exactly the shape of somebody arranging for the code to be sent to them.
    return page(400, "Wrong address", "This app asked to return somewhere it did not register. Remove the connector in the app and add it again.");
  }
  if (ask.method !== "S256" || !/^[A-Za-z0-9_-]{20,200}$/.test(ask.code_challenge)) {
    return sendBack(ask, { error: "invalid_request", state: ask.state });
  }

  const note = await seal(env, "asking", { ask });
  const back = `${origin(url)}/authorize`;
  return new Response(null, {
    status: 302,
    headers: {
      location: `${apexOrigin(url)}/mcp-signin?ask=${encodeURIComponent(note)}&back=${encodeURIComponent(back)}`,
    },
  });
}

/**
 * The apex's half of the sign-in. **Runs on `your-domain.example`**, which
 * is behind Access — so by the time this is reached the address is known and
 * verified, and all this does is sign it onto the note and send the browser
 * back.
 *
 * Called from `worker.js`, which owns the apex's routing. Returns null for
 * anything it will not do, and the caller shows its own page.
 */
export async function mcpSignIn(request, env, url, who, host) {
  if (!who || !who.email || !EMAIL.test(who.email)) return null;
  const asked = await unseal(env, "asking", url.searchParams.get("ask"));
  if (!asked) return null;
  const back = url.searchParams.get("back") || "";
  // Only ever back to our own MCP host. A `back` typed into the address bar is
  // a stranger's, and the one thing this hands out is somebody's address.
  const wanted = `${url.protocol}//${MCP_HOST_PREFIX}${host || url.host}/authorize`;
  if (back !== wanted) return null;

  const granted = await seal(env, "granted", { email: who.email.toLowerCase(), ask: asked.ask });
  return new Response(null, {
    status: 302,
    headers: { location: `${back}?grant=${encodeURIComponent(granted)}` },
  });
}

function sendBack(ask, fields) {
  const to = new URL(ask.redirect_uri);
  for (const [key, value] of Object.entries(fields)) {
    if (value) to.searchParams.set(key, value);
  }
  return new Response(null, { status: 302, headers: { location: to.toString() } });
}

/** Swap a code for a token, or a refresh token for a fresh one. */
async function token(request, env) {
  if (request.method !== "POST") return problem(405, "Wrong method.");
  let form;
  try {
    form = await request.formData();
  } catch {
    return json({ error: "invalid_request" }, 400);
  }
  const kind = form.get("grant_type");

  if (kind === "refresh_token") {
    const held = await tokenRecord(env, String(form.get("refresh_token") || ""), "refresh");
    if (!held) return json({ error: "invalid_grant" }, 400);
    return await mint(env, held.email, held.client_id);
  }

  if (kind !== "authorization_code") return json({ error: "unsupported_grant_type" }, 400);

  const code = String(form.get("code") || "");
  if (!/^[A-Za-z0-9_-]{20,80}$/.test(code)) return json({ error: "invalid_grant" }, 400);
  const got = await env.BUCKET.get(`mcp/codes/${code}.json`);
  if (!got) return json({ error: "invalid_grant" }, 400);
  // **Taken away before it is checked.** A code is good exactly once, and the
  // way that rule gets broken is checking first and deleting later.
  await env.BUCKET.delete(`mcp/codes/${code}.json`);
  let held;
  try {
    held = await got.json();
  } catch {
    return json({ error: "invalid_grant" }, 400);
  }
  if (Date.now() > held.until) return json({ error: "invalid_grant" }, 400);
  if (held.client_id !== String(form.get("client_id") || "")) return json({ error: "invalid_grant" }, 400);

  const verifier = String(form.get("code_verifier") || "");
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  if (base64urlBytes(new Uint8Array(digest)) !== held.code_challenge) {
    return json({ error: "invalid_grant" }, 400);
  }

  return await mint(env, held.email, held.client_id);
}

async function mint(env, email, client_id) {
  const access = random(40);
  const refresh = random(40);
  const body = JSON.stringify({ email, client_id, until: Date.now() + TOKEN_LIFE });
  await env.BUCKET.put(`mcp/tokens/${await sha256Hex(access)}.json`, body, {
    httpMetadata: { contentType: "application/json" },
  });
  await env.BUCKET.put(`mcp/refresh/${await sha256Hex(refresh)}.json`, body, {
    httpMetadata: { contentType: "application/json" },
  });
  return json({
    access_token: access,
    refresh_token: refresh,
    token_type: "Bearer",
    expires_in: Math.floor(TOKEN_LIFE / 1000),
    scope: "shotlister",
  });
}

async function tokenRecord(env, secret, kind) {
  if (!/^[A-Za-z0-9_-]{20,120}$/.test(secret)) return null;
  const where = kind === "refresh" ? "refresh" : "tokens";
  const got = await env.BUCKET.get(`mcp/${where}/${await sha256Hex(secret)}.json`);
  if (!got) return null;
  let held;
  try {
    held = await got.json();
  } catch {
    return null;
  }
  if (!held.until || Date.now() > held.until) return null;
  if (!EMAIL.test(String(held.email || ""))) return null;
  return held;
}

// -------------------------------------------------------------- the protocol

async function rpc(request, env, url, ctx) {
  const offered = request.headers.get("authorization") || "";
  const bearer = offered.toLowerCase().startsWith("bearer ") ? offered.slice(7).trim() : "";
  const held = bearer ? await tokenRecord(env, bearer, "access") : null;
  if (!held) {
    // The header is how a client learns *where* to sign in. Without it a client
    // sees a 401 and has nothing it can do about it.
    return new Response(JSON.stringify({ error: "invalid_token" }), {
      status: 401,
      headers: {
        "content-type": "application/json; charset=utf-8",
        "www-authenticate": `Bearer realm="shotlister", resource_metadata="${origin(url)}/.well-known/oauth-protected-resource"`,
      },
    });
  }

  const text = await request.text();
  if (text.length > MAX_BODY) return problem(413, "That message is too long.");
  let asked;
  try {
    asked = JSON.parse(text);
  } catch {
    return json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "That is not JSON." } });
  }

  const many = Array.isArray(asked);
  const messages = many ? asked : [asked];
  const replies = [];
  for (const message of messages) {
    const reply = await one(env, url, held, message, ctx);
    if (reply) replies.push(reply);
  }
  if (!replies.length) return new Response(null, { status: 202 });
  const reply = json(many ? replies : replies[0]);
  // How the film was brought up for this message — `restored`,
  // `restored+tail` or `replayed` — so a check can see the snapshot working.
  if (held.road) reply.headers.set("x-shotlister-film", held.road);
  return reply;
}

async function one(env, url, held, message, ctx) {
  const id = message && message.id;
  // A notification carries no id and expects no reply.
  if (id === undefined || id === null) return null;
  const method = String((message && message.method) || "");

  try {
    if (method === "initialize") {
      return {
        jsonrpc: "2.0",
        id,
        result: {
          protocolVersion: PROTOCOL_VERSION,
          capabilities: { tools: {} },
          serverInfo: { name: "shotlister", version: "1" },
        },
      };
    }
    if (method === "ping") return { jsonrpc: "2.0", id, result: {} };
    if (method === "tools/list") {
      return { jsonrpc: "2.0", id, result: { tools: await toolList() } };
    }
    if (method === "tools/call") {
      const params = message.params || {};
      const said = await callTool(env, held, String(params.name || ""), params.arguments || {}, ctx);
      // A tool may answer with pictures as well as words (`board` `look`).
      if (said && typeof said === "object" && Array.isArray(said.content)) return { jsonrpc: "2.0", id, result: { content: said.content } };
      return { jsonrpc: "2.0", id, result: { content: [{ type: "text", text: said }] } };
    }
    return { jsonrpc: "2.0", id, error: { code: -32601, message: `Unknown method: ${method}` } };
  } catch (error) {
    if (error && error.said) {
      return { jsonrpc: "2.0", id, error: { code: -32000, message: error.said } };
    }
    // **The reason goes back, not just "something went wrong".** This is his
    // own server and he is its only audience; a fault an AI cannot describe is
    // one he cannot report, and the first morning this was live was spent
    // working out by hand what one line of text would have said.
    console.error(error && error.stack ? error.stack : String(error));
    const why = String((error && error.message) || error || "unknown").slice(0, 200);
    return { jsonrpc: "2.0", id, error: { code: -32000, message: `Shotlister could not finish that: ${why}` } };
  }
}

/** An error worth showing whoever asked, as opposed to one worth logging. */
function refuse(said) {
  const error = new Error(said);
  error.said = said;
  return error;
}

/**
 * The tools that belong to the portal rather than to the film.
 *
 * **Everything here writes `front.json`, which is a projection and not a
 * source** — see `front.js`. The words come from Notion, where he writes them;
 * the counts and the ratio come from the film itself, asked for here rather
 * than typed in, because a number a person retypes is a number that goes wrong.
 *
 * This is `design/notion-bridge.md`'s standing arrangement, one layer up: the
 * clever part — reading his project page, deciding what belongs on it — happens
 * in an agent, and arrives as an ordinary write. Nothing calls Notion from
 * inside this worker, so a page a director opens does not depend on Notion
 * being awake.
 */
const HUB_TOOLS = [
  {
    name: "front",
    description:
      "What the collaborators' portal currently says about the open project — its logline, vitals, pinned documents and crew contacts. Read this before changing any of it.\n\nSHOOTS — a project that shoots more than once has `shoots` (from his Notion Shoots database, oldest first) and the portal leads with the next Upcoming one: `crew` and `camera` at the top are that shoot's. Pass `shoot` (a slug from `shoots`, e.g. `shoot-1`) to read the page as that shoot's tab shows it: its crew, spec sheet, documents and days, with `was` holding the shoot before for comparison. A shoot he named has `name` (\"Malibu Pickup\") and `base` (\"Shoot 2\", which the slug follows). A shoot's dates, name and notes are changed with `set_shoot`, who is on it with `set_shoot_crew`, a new shoot is `add_shoot`, and `shoots` lists every shoot with its crew. Shoots and their crew live in the project record: editing Notion's Shoots rows or a Notion project page directly does NOT reliably reach Studio, so always use those tools.\n\nLENSES — `camera.lenses` is the sheet's text, one set per line; `camera.lens_sets` the same sets as {label, series, focals, stop, notes}.",
    inputSchema: { type: "object", properties: {
      shoot: { type: "string", description: "A shoot's slug, to read that shoot's tab. Leave out for the next shoot." },
    }, required: [] },
  },
  {
    name: "set_front",
    description:
      "Write the open project's page on the portal at your-domain.example. Everything is optional and only what you pass is changed; `documents`, `crew` and `camera` replace what is there when given. The project's own facts — title, director, producer, aspect ratio, and the scene, shot, location, board and day counts — are read from the project itself on every call, so never pass those.\n\nSource the words from his Notion project page (the project's `console_page`): its Logline, Synopsis, Director's Note and Visual Language boxes, Status, Type, Length and Shoot Dates properties.\n\nRECORD — on a project with a record, the logline, synopsis, note, look, status, type, length and shoot dates are written to it (as set_record does) and Notion follows. A fact the project hides, or one the record will not take, is not kept; the reply says which. The rest of the call still goes through. For client, agency, colour, icon, website, Drive folder, credits and links use set_record, set_credit and add_record_link.\n\nDOCUMENTS — the rule, his (2026-10-17): **Drive files reach the Documents page only by his Show on Portal switch in Projects Console** (the record's `portal_docs`); never pin a Drive file here yourself, and the old Notion `Hub` checkbox no longer means anything. Pass a `url` for anything that should stay where it lives (Drive, Notion). Use `add_document` instead for anything a collaborator must open without an account anywhere — a look book, mainly.\n\nCAMERA — from the project's row in his Camera Spec Sheets database, verbatim. Leave out anything he has not filled in rather than guessing it.\n\nCREW — from the Crew database, the rows related to this project. Crew and camera are the portal's copies of Notion's Crew and Camera Spec Sheets: on a project linked to Notion the next refresh replaces them from there, so change them in Notion.",
    inputSchema: {
      type: "object",
      properties: {
        logline: { type: "string", description: "One or two sentences. His Notion page has one written. Saved to the project record, which writes it into the Notion page's Logline box." },
        synopsis: { type: "string", description: "The story in a paragraph or a few. Saved to the project record and his Notion page's Synopsis box; the portal does not show it yet." },
        note: { type: "string", description: "The director's note, if there is one. Saved to the project record and his Notion page's Director's Note box." },
        look: { type: "string", description: "The visual language, in a sentence or two. Saved to the project record and his Notion page's Visual Language box." },
        status: { type: "string", description: "Development or Active, saved to the project record. Complete, Post and Archived ask him first: set_stage. One already on the record may be passed and changes nothing." },
        type: { type: "string", description: "Narrative, Commercial, Personal, … — a choice already in use. Saved to the project record." },
        length: { type: "string", description: "Short, Feature, … — a choice already in use. Saved to the project record." },
        shoot_start: { type: "string", description: "YYYY-MM-DD. Saved to the project record's Shoot Dates. Anything else is not kept." },
        shoot_end: { type: "string", description: "YYYY-MM-DD." },
        key_image: {
          type: "string",
          description:
            "The picture that stands for the project, as a stored file name like `a1b2….jpg`. Use `add_document` to put a new one there, or a hash already in the project.",
        },
        source: { type: "string", description: "Where this came from, e.g. `notion:<page id>`, so the next run knows." },
        documents: {
          type: "array",
          description:
            "The handful worth one click. Each is either a link (`url`) or a file already stored here (`file`). `kind` is `lookbook` or `document`.",
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              kind: { type: "string" },
              url: { type: "string" },
              file: { type: "string" },
              note: { type: "string" },
            },
            required: ["name"],
          },
        },
        camera: {
          type: "object",
          description:
            "The camera spec sheet, from his Notion Camera Spec Sheets row for this project. Copy the values as written; omit what is blank.",
          properties: {
            body: { type: "string", description: "Notion's `Camera`, e.g. `Alexa 35`." },
            lenses: { type: "string", description: "Notion's `Lenses`, whole." },
            format: { type: "string", description: "Notion's `Shooting Format`, e.g. `4.6K 16:9`." },
            capture: { type: "string", description: "Notion's `Capture Resolution`." },
            colour: { type: "string", description: "Notion's `Color Space`." },
            codec: { type: "string", description: "Notion's `Codec`." },
            fps: { type: "string", description: "Notion's `Frame Rate`, e.g. `23.976`, or a line per camera (`A Cam: 23.976`)." },
            desqueeze: { type: "string", description: "Notion's `Desqueeze`." },
          },
        },
        crew: {
          type: "array",
          description: "Contacts, grouped on the page by `department`. From his Notion Crew database, the rows related to this project.",
          items: {
            type: "object",
            properties: {
              name: { type: "string" },
              role: { type: "string" },
              department: { type: "string" },
              company: { type: "string" },
              email: { type: "string" },
              phone: { type: "string" },
              note: { type: "string" },
            },
            required: ["name"],
          },
        },
      },
      required: [],
    },
  },
  {
    name: "add_document",
    description:
      "Pin one thing under the project's Documents — a look book PDF, a key image, a Drive folder, a video, anything a collaborator should be able to reach.\n\nTWO WAYS, AND THE CHOICE MATTERS. Send `base64` and `filename` to **hold the file here**: it is stored by its own contents, so sending the same file twice costs nothing and makes one copy, and it opens for somebody with no account anywhere. Send `url` instead to **point at where it already lives** — Drive, Notion, YouTube — which makes no second copy and cannot go stale.\n\nFULL-QUALITY PICTURES: send `url` with `kind: picture` and the hub fetches the original — a Drive share link or any public image address. Never hand-copy a photo into `base64`; that is what made pictures soft. For a private file on his Mac, run `tools/upload-picture.sh <film id> <file>` and write the name it prints.\n\nPrefer a link for anything that already has a home. Hold the bytes only for what a collaborator must be able to open without signing in to anything, which in practice means the look book.\n\nEither way it is *his*, and a Notion refresh leaves it alone. Adding one does not disturb the rest of the list — unlike `set_front`, which replaces it.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "What to call it on the page." },
        filename: { type: "string", description: "Used only for its extension, e.g. `lookbook.pdf`. With `base64`." },
        base64: { type: "string", description: "The file itself. Up to about 6 MB. Send this or `url`, not both." },
        url: {
          type: "string",
          description:
            "Where it already lives — a Drive folder, a Notion page, a video. `http` or `https`. Send this or `base64`, not both.",
        },
        kind: {
          type: "string",
          description:
            "`lookbook`, `document`, `key_image` to make it the project's picture, or `picture` to store it for a page without listing it under Documents. A `picture` is what `set_page` draws: store it, then write the name it gives back as `![caption](name)`. With a `url`, `picture` and `key_image` are fetched by the hub at full size, so never write a photo out as `base64`; a Drive link must be shared as anyone with the link.",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "deck",
    description:
      "Read a deck of this project — its sections in order, the words in each, and which pictures are grouped together with how much each group matters. A deck is a page of the project that carries its own design: a pitch deck, a look book, a visual bible.\n\nRead this before changing one, so a revision is a revision. The design itself is not here and is not yours to change — it is written for the deck and tuned in Deck Editor. What you may change is the words and the order.",
    inputSchema: {
      type: "object",
      properties: { slug: { type: "string", description: "The deck's address, as `pages` lists it. `bible`." } },
      required: ["slug"],
    },
  },
  {
    name: "set_deck",
    description:
      "Change a deck's words, or the order of its sections. Send only what changes — anything left out is kept.\n\nWORDS — `words` is a map of key to text, using the keys `deck` hands back (`overall_approach.b1`). A key the deck does not already have is refused rather than invented, because a word with no place in the design is a word nobody will ever see.\n\nORDER — `sections` is the full list of section ids in the order you want them. Every id must be one the deck already has.\n\nWHAT YOU MAY NOT DO HERE — you cannot add or remove pictures, regroup them, or change what is emphasised. That is arrangement, it is his, and it is done by hand in Deck Editor where he can see the result. Nor can you touch the design.\n\nAfter this the deck must be published from Deck Editor for the change to reach the page and the PDF.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The deck's address. `bible`." },
        words: { type: "object", description: "Key to text, for keys the deck already has." },
        sections: { type: "array", items: { type: "string" }, description: "Every section id, in the order you want them." },
      },
      required: ["slug"],
    },
  },
  {
    name: "pages",
    description:
      "Every page on the project's portal: the Script (the project's newest draft, when it has one — `page` with `script` gives every draft and its PDF link), the four the record always has, and every one beside them. Says which came from Notion and which an agent wrote — only the second kind can be changed from here. Read this before writing a page, so a new one does not land on top of an existing one.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_page",
    description:
      "Make a page on the project's portal, or rewrite one — a Visual Bible, a lighting plan, an overheads list, a safety briefing, anything a crew member should be able to open. It becomes a real address of its own and a row in the project's rail, beside Visual Bible, Camera Spec Sheet, People and Documents.\n\nWrite the page as Markdown. Headings, paragraphs, lists, quotations, tables, rules and links are drawn. Bold and italic are not — the markers are removed rather than printed, so write plainly.\n\nPICTURES — a picture must be a file this hub holds. Put the bytes here with `add_document` and `kind` set to `picture`, then write the name it hands back: `![The alley](a1b2….jpg)`. A picture pointing anywhere else is dropped, and the reply says so.\n\nCARRYING PICTURES OVER FROM NOTION — this is the case that catches people. A picture on one of his Notion pages is served from a signed address that **expires within the hour**, so linking it produces a page that works while you are looking at it and is broken by the afternoon. Download the bytes and send them through `add_document` with `kind: picture`, one per picture, then write the names it gives back. The same picture sent twice costs nothing and makes one copy, so there is no reason to be careful about repeats. Never put a `notion.so`, `amazonaws.com` or `prod-files-secure` address in a page.\n\nPICTURE ROWS — several pictures on one line are drawn side by side, which is how a visual bible compares references: `![](a1b2….jpg) ![](c3d4….jpg) ![](e5f6….jpg)`. Three or four across reads well; they stack on a phone. Every picture on a project's page is cropped to that project's aspect ratio, so a row lines up whatever shape the stills arrived in.\n\nVIDEO — a clip on its own line: `!video[The reel](https://livid.com/embed/AbC123)`. A Livid, YouTube or Vimeo address plays in its own player; a clip this hub holds is its name (`add_document` hands it back), with its still after it if it has one: `!video[Trailer](a1b2....mp4 c3d4....jpg)`. The words in the brackets go under it.\n\nNAMING — pass `name` as a person reads it and the address is made from it. `Visual Bible`, `Camera Spec Sheet`, `People` and `Documents` are the record's own four: writing one of those puts your words on that page under what is already there rather than making a second one.\n\nALREADY DESIGNED — pass `html` instead of `markdown` when the page arrives with a design of its own, which is what Deck Editor publishes. It is drawn as it is, and the page is stamped as a deck: a Notion refresh will not overwrite it, and Markdown sent here will be refused rather than replacing his design.\n\nA page written here survives a Notion refresh: writing it sets its Source to *Written here*, and a refresh no longer copies Notion on top of it. That is not a one-way door — the page itself carries a Source control, so it can be handed back to Notion whenever he wants.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "What the page is called, in Title Case, as a person reads it. `Lighting Plan`." },
        markdown: { type: "string", description: "The page itself, as Markdown, for the portal to style." },
        html: {
          type: "string",
          description:
            "The page as a **finished document**, when it already has a design of its own — what Deck Editor publishes. The portal draws this instead of styling Markdown, and stamps the page as a deck so a Notion refresh and an agent's Markdown both leave it alone. Scripts are stripped on the way out. Send one of `markdown` or `html`, not both.",
        },
        subtitle: { type: "string", description: "One line under the title, if it needs one. Left off is normal." },
        slug: {
          type: "string",
          description: "The address, if it should not be made from the name. Lower case, hyphens, no spaces.",
        },
        category: {
          type: "string",
          description:
            "The category to file a **new** page in (the sidebar's headings are the Library's categories), as `library` lists them. The same as adding from a heading's + on the portal. Left off, a new page is filed by what it is called. Ignored for a page that already exists.",
        },
        type: {
          type: "string",
          description:
            "`page` or `deck`. Only needed to make **an address with nothing at it yet** — send `type` and no `markdown` or `html`, and the row and the address are made and nothing is written. `deck` is the useful one: it is the slot Deck Editor publishes a design into, and without it a publish has nowhere to land. Sending neither a body nor a `type` is refused, because an agent with nothing to say has no reason to make a page.",
        },
      },
      required: ["name"],
    },
  },
  {
    name: "page",
    description:
      "Read a page of the project's record back — its words, its pictures and their order, as the Markdown that would make it. Read this before rewriting a page, so a revision is a revision rather than a replacement. Works on a page an agent wrote and on one that came from Notion; only the first can be written back.",
    inputSchema: {
      type: "object",
      properties: { slug: { type: "string", description: "The page's address, as `pages` lists it. `bible`." } },
      required: ["slug"],
    },
  },
  {
    name: "set_source",
    description:
      "Say where a page's words come from — and therefore who may write it. The same control he has at the foot of the page on the portal.\n\n  `notion`       Notion feeds it, every refresh. Anything written here is replaced.\n  `notion-once`  a snapshot: Notion stops copying over it, and what is here stays.\n  `here`         written on the portal or by an agent. Notion leaves it alone.\n\nCHANGEABLE BOTH WAYS, always. Handing a page back to `notion` starts it being fed again at the next refresh; taking a snapshot stops it without destroying either copy. Nothing here is a one-way door.\n\nTHE THING TO KNOW: `set_page` already sets a page to `here`, because writing it *is* writing it here. Use this to hand one back, or to take a snapshot of a Notion page you want to stop changing under you.\n\nONLY WHERE NOTION NAMES THE PAGE. A page made on the portal or by an agent has no Hub-ticked Project Docs row behind it, so the two Notion sources are refused for it — `pages` says which is which under `notion_names_it`. Connecting one is done in Notion, by ticking `Hub` and setting `Section` to the page's name; nothing on this side can do it.\n\nA deck's words come from Deck Editor and cannot be reassigned.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The page's address, as `pages` lists it. `lighting-plan`." },
        source: { type: "string", description: "`notion`, `notion-once` or `here`." },
      },
      required: ["slug", "source"],
    },
  },
  {
    name: "arrange",
    description:
      "Put the project's sidebar in an order. The same thing he does by dragging it on the portal. The sidebar's headings ARE the Library's categories: a page stands under the category it is filed in, so putting a row under a heading files it in that category, and the headings come in the order of the categories.\n\nROW ADDRESSES are `shotlist`, `locations`, `schedule`, `boards`, `bible`, `camera`, `people`, `documents`, and the address of any page beside them — `pages` lists them all.\n\nSend `groups` as a list of `{name, rows}`: `[{\"name\": \"Look\", \"rows\": [\"bible\", \"boards\"]}, {\"name\": \"Schedule and Locations\", \"rows\": [\"schedule\", \"locations\"]}]`. A name no category carries yet makes one. Send `order` instead for one plain order with no filing. To add, rename, remove or reorder the categories themselves use `edit_shelves`.\n\nA PARTIAL LIST IS FINE and is usually what you want: anything not named keeps its place at the end of its category, and a page added tomorrow appears there rather than having to be placed first.\n\nAsk `library` for each page's category to see what it is now.",
    inputSchema: {
      type: "object",
      properties: {
        groups: {
          type: "array",
          description: "The categories and what is under each, in the order they should be drawn.",
          items: {
            type: "object",
            properties: {
              name: { type: "string", description: "The category. Empty files nothing and only gives an order." },
              rows: { type: "array", items: { type: "string" }, description: "Row addresses, in order." },
            },
            required: ["rows"],
          },
        },
        order: {
          type: "array",
          items: { type: "string" },
          description: "The simple case: one list. Sets the order and files nothing.",
        },
      },
      required: [],
    },
  },
  {
    name: "rename_page",
    description:
      "Rename a page he made (or an agent did): the name on the sidebar, the page's heading and its address change (`Night Exteriors` moves it to `night-exteriors`), and the old address forwards, so a link already sent keeps working. A deck keeps its address. A page Notion names is renamed on the portal only: its address and its Notion title stay. Refused onto a name another page already has. The same as Rename on a page's menu on the portal.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The page's address, as `pages` lists it. `lighting-plan`." },
        name: { type: "string", description: "The new name, in Title Case." },
      },
      required: ["slug", "name"],
    },
  },
  {
    name: "rename_document",
    description:
      "Rename a pinned document, a file or a link (a Drive folder shown as `drive.google.com`, say). Its category, icon, archive and private settings stay with it. A document Notion names keeps Notion's name behind the scenes, so the next refresh does not add it twice. Refused onto a name another document already has. The same as Rename on a document's card in the portal's Library.",
    inputSchema: {
      type: "object",
      properties: {
        document: { type: "string", description: "The document's current name, as `library` lists it." },
        name: { type: "string", description: "The new name, in Title Case." },
      },
      required: ["document", "name"],
    },
  },
  {
    name: "follow_doc",
    description:
      "A page drawn from a Google Doc (Halcyon's Outline, from Ivy's outline doc): whether it is following the doc, which doc, and when it last redrew. With `on`, turn following on or off; with `refresh`, redraw it from the doc now. While on, the portal looks at the doc every two minutes and redraws the page once an edit has sat still for a minute and a half. `doc` (a Google Docs address or id) points a page at a doc. The same as Follow Google Doc and Refresh from Doc on a page's menu on the portal. Administrators only; the doc itself is never written to.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The page's address, as `pages` lists it. `outline`." },
        on: { type: "boolean", description: "Follow the doc (true) or stop (false). Leave out to only read." },
        refresh: { type: "boolean", description: "Redraw the page from the doc now." },
        doc: { type: "string", description: "The Google Doc to follow, as an address or id. Only to point a page at a doc." },
        credit: { type: "string", description: "Whose draft it is, said on the page: `Ivy`." },
      },
      required: ["slug"],
    },
  },
  {
    name: "library",
    description:
      "The project's Library: every page and document it holds, shelved like a real library (to start: Creative, Technical, Logistical, Other). A page has two settings: pinned (it has a row in the sidebar) and private (only editors can see it; a viewer or a link holder never learns it exists). Lists each page with its shelf and, for an editor, whether it is pinned, private and archived, and the project's documents with their shelf and whether they are private. An archived page is unpinned, private and filed in the Archive. An editor sees all of it; anyone else sees what they may open. Change it with `set_on_sidebar` (pinned) and `archive_page`; private is `set_visibility`. Nothing in the Library is ever deleted.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_on_sidebar",
    description:
      "Pin a page to the project's sidebar, or unpin it. Pinned: has a row in the sidebar. Unpinning leaves it in the Library and still opening at its address; pinning it again puts it back exactly where it was, in its category. Works on any page `library` lists, including the built-in ones (`locations`, `people`, `documents`, `boards`, `schedule`, `shotlist`). The same as the Pinned switch on the portal. A document (a file or a link, such as a Drive folder) can be pinned too: send `document` instead of `slug`, and it becomes a row that opens it.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The page's address, as `library` lists it. `lighting-plan`." },
        document: { type: "string", description: "Instead of `slug`: a document's name, as `library` lists it under `documents`." },
        pinned: { type: "boolean", description: "true to pin it to the sidebar, false to unpin it." },
        on: { type: "boolean", description: "Older name for `pinned`." },
      },
      required: [],
    },
  },
  {
    name: "move_to_shelf",
    description:
      "Move a page or document to another shelf (category) of the project's Library. Each project has its own shelves, listed by `library` under `shelves`: to start, Creative, Technical, Logistical and Other, which he may rename and add to (`edit_shelves`). Everything is filed by what it is and what it is called, so this is only for the one that was filed wrong; moving something back to where it would be filed anyway forgets the move. Nothing else about it changes.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "A page's address, as `library` lists it." },
        document: { type: "string", description: "Instead of `slug`: a document's name, exactly as `library` lists it." },
        shelf: { type: "string", description: "The shelf, by its name or id, as `library` lists them." },
      },
      required: ["shelf"],
    },
  },
  {
    name: "edit_shelves",
    description:
      "Change the project's Library categories, which are also the sidebar's headings (one list). `add` a new one (`name`; it goes last), `rename` one (`shelf`, `name`; everything on it stays on it), `remove` one he added (`shelf`; the four starting ones can be renamed but not removed, and what stood on it goes back to the shelf it would be filed on anyway), `move` one (`shelf`, `to`: up, down or a place counting from 0), or `order` them all (`ids`). Only when he asks for it. Answers the shelves as they now stand.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["add", "rename", "remove", "move", "order"] },
        shelf: { type: "string", description: "The shelf, by its name or id, as `library` lists them." },
        name: { type: "string", description: "For add and rename: the shelf's name, at most 40 characters." },
        to: { type: "string", description: "For move: up, down, or a place counting from 0." },
        ids: { type: "array", items: { type: "string" }, description: "For order: shelf ids (or names), in the new order." },
      },
      required: ["action"],
    },
  },
  {
    name: "set_icon",
    description:
      "Give a page or a document its own icon, the small picture beside its name in the sidebar and the Library. Say the page's `slug` or the `document`'s name, and the `icon`; an empty icon goes back to the default for what it is. The same as Icon in the right-click menu on the portal. Icons: " + ICON_CHOICES.join(", ") + ".",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The page's address, as `library` lists it." },
        document: { type: "string", description: "A document's name instead of a page address." },
        icon: { type: "string", description: "One of the icon names, or empty to go back to the default." },
      },
      required: ["icon"],
    },
  },
  {
    name: "archive_page",
    description:
      "Archive a page or a document (a file or link), or unarchive it. Archiving unpins the page, makes it private (only editors can see it) and files it in the Library's Archive, a folded section at the foot of the Library; it still opens for an editor at its address. Unarchiving puts back exactly what it was: pinned or not, private or not, in its old place. Nothing is deleted. The same as Archive on the portal.",
    inputSchema: {
      type: "object",
      properties: {
        slug: { type: "string", description: "The page's address, as `library` lists it." },
        document: { type: "string", description: "A document's name instead of a page address, as `library` lists it." },
        archived: { type: "boolean", description: "true to archive it, false to take it out of the Archive." },
      },
      required: ["archived"],
    },
  },
  {
    name: "remove_page",
    description:
      "Take a page off the project's portal. Only a page an agent wrote can be taken off here; one that came from Notion is Notion's to remove, by unticking its `Hub` box.",
    inputSchema: {
      type: "object",
      properties: { slug: { type: "string", description: "The page's address, as `pages` lists it." } },
      required: ["slug"],
    },
  },
  {
    name: "visibility",
    description:
      "What the project's What Viewers See panel says. `private` lists what only editors can see (pages, people, documents), and whose contact details a link holder is shown. Private: only editors can see it. Also lists every section's slug and name. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_visibility",
    description:
      "Make things private, or public again, as the What Viewers See panel does. Private: only editors can see it. `private` lists what to make private and `public` what to show again (older names: `hide` and `show`). Send only what changes. Sections are named by slug (`visibility` lists them), people and documents by name. A board's link sharing is `set_board` `share`, not this. Whether a page has a row in the sidebar is `set_on_sidebar` (pinned), not this. His alone.",
    inputSchema: {
      type: "object",
      properties: {
        for: { type: "string", description: "Retired: `links` is all there is now. `me` is refused." },
        private: {
          type: "object",
          description: "What to make private: `{ sections: [slug], people: [name], documents: [name] }`.",
          properties: {
            sections: { type: "array", items: { type: "string" } },
            people: { type: "array", items: { type: "string" } },
            documents: { type: "array", items: { type: "string" } },
          },
        },
        public: {
          type: "object",
          description: "What to show again, the same shape as `private`.",
          properties: {
            sections: { type: "array", items: { type: "string" } },
            people: { type: "array", items: { type: "string" } },
            documents: { type: "array", items: { type: "string" } },
          },
        },
        hide: {
          type: "object",
          description: "Older name for `private`.",
          properties: {
            sections: { type: "array", items: { type: "string" } },
            people: { type: "array", items: { type: "string" } },
            documents: { type: "array", items: { type: "string" } },
          },
        },
        show: {
          type: "object",
          description: "Older name for `public`.",
          properties: {
            sections: { type: "array", items: { type: "string" } },
            people: { type: "array", items: { type: "string" } },
            documents: { type: "array", items: { type: "string" } },
          },
        },
        contact: {
          type: "object",
          description: "`{ on: [name], off: [name] }` — whose email and phone a link holder sees (the People tab's On the portal: Off = private, Name, Contact = contact on).",
          properties: {
            on: { type: "array", items: { type: "string" } },
            off: { type: "array", items: { type: "string" } },
          },
        },
      },
      required: [],
    },
  },
  {
    name: "access",
    description:
      "Who can open the project, as the Share popover's People tab says: the people on the list with their roles, the general link (on, off or never made, its address, whether it has a password) and any invites not yet used, the link's short name, and whether people with the link may draw on the Diagrams page (`diagram_link_edit`; on unless switched off). His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_access",
    description:
      "Change who can open the project, as the Share popover does. `link` is `anyone` (anyone with the link can read it; makes the link the first time and turns the same link back on after that) or `restricted` (only the people on the list; the link is kept and works again if turned back on). `add` is a list of `{ email, role }` with role `viewer` (default) or `editor`; `role` changes people already on the list; `remove` is a list of emails. `password` sets a password on the general link, or `null` to clear it. `short` renames the link's short name (share.your-domain.example/<short>; 2–24 letters or digits) and the old one keeps working, so nothing already sent breaks. `diagram_link_edit` true lets people with the link draw on the Diagrams page (the default), false lets them only look (the Diagrams page's Editable by Link). He is always an editor and cannot be removed. Send only what changes. His alone.",
    inputSchema: {
      type: "object",
      properties: {
        link: { type: "string", description: "`anyone` or `restricted`." },
        add: {
          type: "array",
          items: { type: "object", properties: { email: { type: "string" }, role: { type: "string" } }, required: ["email"] },
        },
        role: {
          type: "array",
          description: "People already on the list whose role changes: `[{ email, role }]`.",
          items: { type: "object", properties: { email: { type: "string" }, role: { type: "string" } }, required: ["email", "role"] },
        },
        remove: { type: "array", items: { type: "string" } },
        password: { type: ["string", "null"], description: "A password for the general link, or null to clear it." },
        short: { type: "string", description: "The link's short name. The old one keeps working." },
        diagram_link_edit: { type: "boolean", description: "Whether people with the link may draw on the Diagrams page." },
      },
      required: [],
    },
  },
  {
    name: "views",
    description:
      "The open project's view links: each is a filtered Shot List shared on its own address (share.your-domain.example/<film>/v/<name>-<code>), so whoever opens it sees only those shots and nothing else of the project. Lists each view's name, filter, whether it is on, and its link, and the fields and values a new view can filter on. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "share_view",
    description:
      "Make a view link: the Shot List narrowed to a filter, on an address of its own that shows nothing else of the project. For example only the stunt team's shots, or one camera's. `filters` is a list of `{ field, value }`, the field by its column name or label (Tags, Equipment, Shot Size, Lens, a custom column) and the value as the Shot List shows it; values of one field are any-of, different fields all-of. It stays live: a shot that matches later joins the link. Answers the link to send. His alone.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", description: "What the view is called, e.g. `Stunt Team`. Defaults to the values." },
        filters: {
          type: "array",
          items: { type: "object", properties: { field: { type: "string" }, value: { type: "string" } }, required: ["field", "value"] },
        },
        shooting_order: { type: "boolean", description: "Open in shooting order (by day) rather than script order." },
      },
      required: ["filters"],
    },
  },
  {
    name: "set_view",
    description:
      "Change one view link, named by its name or its code (`views` lists both): `name` renames it (the link keeps working), `on: false` switches it off and `on: true` back on, `filters` replaces its filter, `remove: true` deletes it for good, only when he has said to. His alone.",
    inputSchema: {
      type: "object",
      properties: {
        view: { type: "string", description: "The view's name or code." },
        name: { type: "string" },
        on: { type: "boolean" },
        filters: { type: "array", items: { type: "object", properties: { field: { type: "string" }, value: { type: "string" } } } },
        shooting_order: { type: "boolean" },
        remove: { type: "boolean" },
      },
      required: ["view"],
    },
  },
  ATTACH_TOOL,
  REFRESH_TOOL,
];

/**
 * Names a page may not have, because something else already answers there.
 *
 * **The router reads these before it looks for a section**, so a page called
 * any of them would be written, listed in the rail, and open as something else
 * entirely — the worst kind of failure, because everything reports success.
 * `crew`, `share`, `join`, `visibility`, `media`, `pic` and `api` are the
 * hub's own addresses; the rest are the four modes of the program.
 */
const TAKEN = new Set([
  "crew", "api", "media", "pic", "share", "join", "visibility", "library", "icon", "cover",
  "shotlist", "shots", "locations", "boards", "schedule", "camera-sheet", "script", "script.pdf",
]);

/** The four the record always has. A page may join one; none may be removed. */
const BUILT_IN = new Map([
  ["bible", "Visual Bible"],
  ["camera", "Camera Spec Sheet"],
  ["people", "People"],
  ["documents", "Documents"],
]);

/**
 * The two of those four that can carry written words, under the names an agent
 * will actually write.
 *
 * **`Visual Bible` makes the address `visual-bible`, and the page is at
 * `bible`.** Without this the two are different pages: a section called Visual
 * Bible sits at its own address, the rail carries the words *Visual Bible*
 * twice in two different groups, and the page the film already has stays empty
 * — which is exactly what happened the first time this was checked. An agent
 * asked for the Visual Bible and got a second one.
 *
 * **People and Documents are not here on purpose.** `recordPage` draws a tree
 * on the bible and on the spec sheet and on nothing else: those two pages are a
 * crew list and a pinned list, drawn from `front.crew` and `front.documents`.
 * A page folded onto either would be written, listed, and never drawn — which
 * is the failure that reports success, so it is refused with the name of the
 * tool that does work instead.
 */
const FOLDS = new Map([
  ["visual-bible", "bible"],
  ["bible", "bible"],
  ["camera-spec-sheet", "camera"],
  ["camera-spec", "camera"],
  ["camera", "camera"],
]);

/** Where a page that belongs to one of the record's lists should go instead. */
const INSTEAD = new Map([
  ["people", "People is the project's crew list. Put contacts on it with `set_front` and `crew`."],
  ["contacts", "People is the project's crew list. Put contacts on it with `set_front` and `crew`."],
  ["crew", "People is the project's crew list. Put contacts on it with `set_front` and `crew`."],
  ["documents", "Documents is the project's pinned list. Put things on it with `set_front` and `documents`, or `add_document`."],
]);

/** As many as the card will hold — `MAX_SECTIONS` in `front.js`. */
const MOST_PAGES = 24;

// **What a finished document may weigh.** `pageHtmlOf` refuses to draw more
// than this, so accepting more here would store a page that silently never
// appears. The pictures are served from the film, not carried in the markup,
// so a real deck is tens of kilobytes.
const MAX_DOC = 2 * 1024 * 1024;

/**
 * A deck's own record — its words and its order, on the film.
 *
 * **The half of a deck that is not the design.** His ruling, 2026-09-05: the
 * design is written for each deck and tuned by hand, and the arrangement —
 * which pictures, grouped how, emphasised how much — is his and is done where
 * he can see the result. What is left is the words and the order of the
 * sections, and those are exactly what he would ask Notion AI to work on.
 *
 * It lives at `p/<film>/decks/<slug>.json` so anything that can reach the hub
 * can read and change it. A deck folder on his Mac pushes it up when it
 * publishes and reads it back before it builds, which is what stops the two
 * from drifting — the fault that put his Drive bible out of step with his
 * website in the first place.
 */
async function deckTool(name, args, env, found) {
  const slug = String(args.slug || "").trim();
  if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) throw refuse("Say which deck, by its address — `bible`.");
  const key = keys.deck(found.project, slug);
  const got = await env.BUCKET.get(key);
  if (!got) {
    throw refuse(
      `There is no deck at \`${slug}\` on this project. \`pages\` lists what it has; a deck is put here when it is published from Deck Editor.`
    );
  }
  let record;
  try {
    record = JSON.parse(await got.text());
  } catch {
    throw refuse("That deck's record is not readable. Publish it again from Deck Editor.");
  }
  const sections = Array.isArray(record.sections) ? record.sections : [];

  if (name === "deck") {
    return JSON.stringify({
      deck: record.name || slug,
      address: `https://your-domain.example/f/${found.project}/${slug}`,
      sections: sections.map((s) => ({
        id: s.id,
        title: s.title || "",
        shown: s.on !== false,
        pictures: (s.groups || []).reduce((n, g) => n + (g.pictures || []).length, 0),
        groups: (s.groups || []).map((g) => ({ emphasis: g.emphasis, pictures: (g.pictures || []).length })),
      })),
      words: record.words || {},
      design: "written for this deck — not readable or writable here",
    }, null, 1);
  }

  // ---- set_deck ----------------------------------------------------------
  const changed = [];
  if (args.words && typeof args.words === "object") {
    const words = { ...(record.words || {}) };
    const unknown = Object.keys(args.words).filter((k) => !(k in words));
    if (unknown.length) {
      throw refuse(
        `This deck has no place for ${unknown.slice(0, 4).map((k) => `\`${k}\``).join(", ")}. Its keys come from its design; \`deck\` lists the ones it has.`
      );
    }
    for (const [k, v] of Object.entries(args.words)) words[k] = String(v ?? "");
    record.words = words;
    changed.push(`${Object.keys(args.words).length} piece${Object.keys(args.words).length === 1 ? "" : "s"} of writing`);
  }
  if (Array.isArray(args.sections)) {
    const has = sections.map((s) => s.id);
    const asked = args.sections.map(String);
    const strange = asked.filter((id) => !has.includes(id));
    const missing = has.filter((id) => !asked.includes(id));
    if (strange.length) throw refuse(`This deck has no section called \`${strange[0]}\`.`);
    if (missing.length) {
      throw refuse(
        `Send every section, in the order you want them — \`${missing[0]}\` is missing, and leaving one out would drop it.`
      );
    }
    record.sections = asked.map((id) => sections.find((s) => s.id === id));
    changed.push("the order of its sections");
  }
  if (!changed.length) throw refuse("Nothing was sent to change. Pass `words`, or `sections`, or both.");

  record.updated = new Date().toISOString();
  await env.BUCKET.put(key, JSON.stringify(record), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  return `${record.name || slug} — changed ${changed.join(" and ")}. Publish it from Deck Editor for the page and the PDF to follow.`;
}

/** What a file put on the portal may be. A card is written by an agent reading
 *  somebody else's page, so the list is short on purpose. */
export const DOC_EXTENSION = new Set([
  "pdf", "png", "jpg", "jpeg", "webp", "heic", "gif", "txt", "csv", "md", "rtf", "key", "pages", "numbers",
  "doc", "docx", "xls", "xlsx", "ppt", "pptx", "mp4", "mov",
]);

/** About 6 MB of file. Beyond that a link is the right answer, not an upload. */
const MAX_UPLOAD = 8 * 1024 * 1024;

/**
 * The list of tools: the engine's own, with two taken off and one put on.
 *
 * **Asked of the WebAssembly rather than written out here**, so a tool added to
 * the Mac's MCP appears on this one without anybody remembering to.
 */
let TOOLS = null;
async function toolList() {
  if (TOOLS) return TOOLS;
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(1);
  begin(x, "0", "listing", true, "0000000000000001");
  const said = JSON.parse(ask(x, { jsonrpc: "2.0", id: 1, method: "tools/list" }));

  const tools = (said.result.tools || [])
    .filter((tool) => !NOT_HERE.has(tool.name))
    .map((tool) => (HERE_SAID[tool.name] ? { ...tool, description: HERE_SAID[tool.name] } : tool))
    // The engine's `new_shoot` only sets up the film's side; to add a shoot to a project use add_shoot.
    .map((tool) => (tool.name === "new_shoot"
      ? { ...tool, description: `ONLY THE STUDIO SIDE: this does not add a shoot to the project (no shoot on the project record, no Notion row, Drive folders, crew or portal page). To add a shoot, use \`add_shoot\`. What this does: ${tool.description}` }
      : tool))
    .map((tool) =>
      tool.name === "open_project"
        ? {
            name: "open_project",
            description: "Open one of his projects: by its ID (as `projects` lists it; its Notion page or its film's older id work too) or its name. A portal with no Studio side yet opens as a portal. Everything else works on whatever is open.",
            inputSchema: {
              type: "object",
              properties: { project: { type: "string", description: "The project's ID or name." } },
              required: ["project"],
            },
          }
        : tool
    );
  tools.push(EXPORT_TOOL);
  tools.unshift(MODES_TOOL, MODS_TOOL, ...HUB_TOOLS, ...RECORD_TOOLS, ...SHOOT_TOOLS, ...CONSOLE_TOOLS, ...KIT_TOOLS, ...LIBRARY_TOOLS, ...BOARD_TOOLS, {
    name: "projects",
    description: "Every project you may open: its name, its ID (what open_project takes), whether it is a Project or a Job, its Type (Narrative, Commercial, Music Video, Personal), whether it has a Studio side, and whether you may change it. A project whose Studio side is \"none yet, only its portal\" has portal pages: they can be written, its scenes, shots, locations and days cannot. One with no Studio side (often a Job) has only its record and its modes; `modes` turns one on, which makes its Studio side.",
    inputSchema: { type: "object", properties: {}, required: [] },
  });
  TOOLS = tools.map(gatedListing).map(tidySchema);
  return TOOLS;
}

/**
 * **A schema every client reads** (2026-10-19): Notion AI could not see two
 * tools a fresh Claude saw. A list whose `items` is missing or empty, or a
 * `type` given as a list, is refused by some clients' schema checks, which may
 * drop the whole tool. Every list says what it holds (a word, unless the tool
 * said otherwise), and a value that may be empty says so in words.
 */
const LIST_OF = {
  "set_script.rows": { type: "object" }, "take_kit.kit": { type: "object" },
  "set_print_frame.frames": { type: "object" }, "set_print_frame.arrows": { type: "object" },
  "picture_arrows.arrows": { type: "object" }, "update_edit_reference.starts": { type: "number" },
  "set_shoot_crew.add": { type: "object", properties: { person: { type: "string" }, role: { type: "string" } }, required: ["person"] },
};

function tidySchema(tool) {
  const walk = (s, at = "") => {
    if (!s || typeof s !== "object" || Array.isArray(s)) return s;
    const out = { ...s };
    if (Array.isArray(out.type)) {
      const real = out.type.filter((t) => t !== "null");
      out.type = real[0] || "string";
      if (out.type !== "object" && out.type !== "array") out.description = `${out.description || ""}${out.description ? " " : ""}null clears it.`.trim();
    }
    if (out.type === "array") out.items = out.items && Object.keys(out.items).length ? walk(out.items) : (LIST_OF[`${tool.name}.${at}`] || { type: "string" });
    if (out.properties) out.properties = Object.fromEntries(Object.entries(out.properties).map(([k, v]) => [k, walk(v, at ? `${at}.${k}` : k)]));
    return out;
  };
  return { ...tool, inputSchema: walk(tool.inputSchema) };
}

/**
 * **What two of the engine's tools mean here** (2026-10-05). On the portal a
 * film with a project record takes its names from the record, so
 * `update_film`'s names are written there (`filmNamesToRecord`) and
 * `summary` reads them from there.
 */
const HERE_SAID = {
  update_project: "Change the project's details: `title` (its name in Studio — the project's own name is changed with Rename, `big_move` kind rename), `director`, `producer`, `client`, `agency`, and the frame. With the project's aspect ratios on its spec sheet (each a name and a ratio, no resolution), `frame` picks the one Studio draws at by name (Delivery, Social), independently of the portal's Main, and `frame_guides`=true shows the others as guide lines; `aspect_ratio` then picks the one at that ratio. A project with none takes `aspect_ratio` as any ratio: 2.39, 1.85:1, 2.76, 16:9, 9:16 (vertical), 4096x1716. The aspect ratios themselves are edited in the spec sheet (set_spec_sheet's `aspect_ratio`). Only what is given changes; \"\" clears a name. On a project with a record, the four names are written to the record (as set_credit and set_record would) and Studio follows; a name the project hides is refused. summary reads them back.",
  summary: "What the open project is: its ID, whether it is a Project or a Job, its Type (Narrative, Commercial, Music Video, Personal; kind follows it: Commercial and Music Video are commercials), title, names, frame, and counts of scenes, shots, locations, boards and days. On a project with a record, director, producer, client and agency are the record's, and `hidden` lists what the project does not show. The whole record: `record`. Its modes: `modes`.",
};

/** Where this client's open film is remembered. One per app, per person. */
async function openKey(held) {
  return `mcp/open/${await sha256Hex(`${held.client_id}|${held.email}`)}.json`;
}

/**
 * add_shoot, set_shoot_crew and shoots. Owner first, before any project is
 * looked up. `env.SHOOT_TOOL_DEPS` stands in for the world in checks, and is
 * heard only on a machine whose Notion is a stand-in on localhost.
 */
async function shootToolsHere(env, held, who, name, args, ctx) {
  if (!owners(env).includes(String(who.email || "").toLowerCase())) throw refuse("Only Nathaniel can add shoots or change who is on them.");
  const rows = await projectRows(env, await filmsFor(env, who), isAdmin(env, who));
  const wanted = String(args.project || "").trim();
  let row = null;
  if (wanted) {
    row = await findProject(env, rows, wanted);
    if (!row) throw refuse(`No project called ${wanted}. Yours: ${rows.map((r) => r.project).join(", ") || "none"}.`);
  } else {
    const open = await env.BUCKET.get(await openKey(held));
    let note = null;
    try { note = open ? await open.json() : null; } catch { note = null; }
    if (!note || !note.project) throw refuse("Say which project (`project`), or open one first with `open_project`.");
    row = rows.find((r) => (note.id && r.id === note.id) || r.open === note.project) || null;
    if (!row) throw refuse("That project is no longer yours to open. Ask for `projects`.");
  }
  const local = /^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/v1\/$/.test(String(env.NOTION_API || ""));
  const deps = { ctx, ...(local && env.SHOOT_TOOL_DEPS ? env.SHOOT_TOOL_DEPS : {}) };
  return await shootToolRun(env, { id: row.id, title: row.project }, name, args, refuse, who, deps);
}

/** Arguments a gated tool was confirmed with (`mcpgate.js`): run, not asked again. */
const GATE_PASSED = new WeakSet();

/** The two steps in front of a tool that hides, publishes, deletes for real
 * or changes who can see something: its preview (an answer) or null to run. */
async function gateHere(env, held, who, name, args, ctx, found) {
  if (!HUB_GATED.has(name) || GATE_PASSED.has(args) || !needsGate(name, args || {})) return null;
  const g = await hubGate(env, found, who, name, args || {}, refuse, isAdmin(env, who), {
    read: (n, x) => callTool(env, held, n, x, ctx),
    run: (x) => { GATE_PASSED.add(x); return callTool(env, held, name, x, ctx); },
  });
  return g.answer;
}

async function callTool(env, held, name, args, ctx) {
  const who = { email: held.email, via: "mcp" };

  if (name === "projects") {
    // **Project or Job, its Type, and whether it has a Studio side** (stage 5
    // step 5). A portal says it is one (SL-1376): listed as a film with "0
    // changes", Halcyon read as an empty film waiting to be filled, and a
    // chat filled it. Projects with no Studio side are his alone.
    const rows = await projectRows(env, await filmsFor(env, who), isAdmin(env, who));
    if (!rows.length) return "You have no projects here yet.";
    return JSON.stringify(rows.map(shownRow), null, 1);
  }

  if (name === "open_project") {
    // **The project's one ID** (stage 5 step 5): its own ID, its Notion
    // page, its film's relay id (an alias) or its name. `film` and `path`
    // are the older names for the argument, still read.
    const wanted = String(args.project || args.film || args.path || args.id || "").trim();
    if (!wanted) throw refuse("Say which project. `projects` lists them.");
    const rows = await projectRows(env, await filmsFor(env, who), isAdmin(env, who));
    const row = await findProject(env, rows, wanted);
    if (!row) throw refuse(`No project called ${wanted}. Yours: ${rows.map((r) => r.project).join(", ") || "none"}.`);
    await env.BUCKET.put(await openKey(held), JSON.stringify({ project: row.open, id: row.id, side: row.side }), {
      httpMetadata: { contentType: "application/json" },
    });
    if (!row.side && row.studio !== "none yet, only its portal") {
      const { record } = await resolveProject(env, row.id);
      return openedNoSide(row.project, record, row.id);
    }
    const found = { project: row.open, id: row.id, title: await titleOf(env, row.open), role: isAdmin(env, who) ? "editor" : await roleFor(env, row.open, who) };
    // **A portal is opened as a portal.** Its summary from the engine would
    // be an empty film's — no scenes, no shots — which reads as an invitation.
    const portal = await filmlessPortal(env, row.open);
    if (portal) return portalOpened(found.title);
    return await summaryHere(env, found, held, ctx);
  }

  // **The studio's lens library and sensor modes** (`kittools.js`, phase 2 of
  // the spec sheet): one for every project, so no film need be open. Read by
  // anyone signed in, changed by him alone.
  if (LIBRARY_TOOL_NAMES.has(name)) return await libraryTool(env, name, args || {}, refuse, isAdmin(env, who));

  // **Shoots and their crew** (`mcpshoots.js`) — his alone; the project named
  // in the call, else the open one. No film need be open: the record is what
  // they work on.
  if (SHOOT_TOOL_NAMES.has(name)) return await shootToolsHere(env, held, who, name, args || {}, ctx);

  // **Projects Console's own actions that need no open project** (New
  // Project, Reopen, his standards, Activity, the On a Mac list, the agents —
  // `consoletools.js`): his alone; the open project, when there is one, only
  // narrows what they list.
  if (CONSOLE_GLOBAL.has(name)) {
    let note = null;
    try { const got = await env.BUCKET.get(await openKey(held)); note = got ? await got.json() : null; } catch { note = null; }
    const there = note && note.project ? { project: note.project, id: note.id || "", title: "" } : null;
    return await consoleTool(env, there, name, args || {}, refuse, who, isAdmin(env, who));
  }

  const open = await env.BUCKET.get(await openKey(held));
  if (!open) throw refuse("No project is open. Ask for `projects`, then `open_project`.");
  let kept;
  try {
    kept = await open.json();
  } catch {
    throw refuse("No project is open. Ask for `projects`, then `open_project`.");
  }
  if (!kept || !kept.project) throw refuse("No project is open. Ask for `projects`, then `open_project`.");
  // **Asked again on every call, never remembered.** Somebody taken off a film
  // this morning must not still be inside it this afternoon because an app kept
  // a note saying they were.
  // **The open project follows its ID** (stage 5 step 5): an older note is
  // given its ID through the alias, and when the project's Studio side is
  // made or moves (a mode turned on), the next call goes there.
  const now = await followOpen(env, kept);
  let project = now.project;
  // **A film remembered by its portal's id** goes where the portal went.
  const moved = now.side ? await carriedTo(env, project) : project;
  if (moved !== project || now.moved) {
    project = moved;
    await env.BUCKET.put(await openKey(held), JSON.stringify({ project, id: now.id, side: now.side, looked: now.looked }), { httpMetadata: { contentType: "application/json" } });
  }
  // **A project with no Studio side** (a Job, or every mode off): his alone,
  // since nobody else is on it; its record and modes answer, nothing else.
  if (!now.side && !(await filmlessPortal(env, project))) {
    if (!isAdmin(env, who)) throw refuse("You no longer have a part in that project.");
    const { record } = await resolveProject(env, now.id || project);
    const found = { project, id: now.id, title: (record && record.name) || project, role: "editor" };
    const asked = await gateHere(env, held, who, name, args, ctx, found);
    if (asked !== null) return asked;
    if (RECORD_TOOL_NAMES.has(name)) return await recordTool(env, found, name, args, refuse);
    if (name === "modes") return (await modesTool(env, found, args, refuse, who)).said;
    if (name === "mods") return await modsTool(env, found, args, refuse, who);
    // Projects Console's actions (`consoletools.js`): a project with no
    // Studio side has every one of them but the plans' Link Edits.
    if (CONSOLE_TOOL_NAMES.has(name)) {
      if (name === "link_edits" || name === "undo_link_edit") throw refuse(noSideSaid(found.title, record));
      return await consoleTool(env, found, name, args || {}, refuse, who, true);
    }
    if (name === "summary") return JSON.stringify({ title: found.title, ...projectFacts(record, now.id), studio_side: "none" }, null, 1);
    throw refuse(noSideSaid(found.title, record));
  }
  const role = await roleFor(env, project, who);
  if (!role) throw refuse("You no longer have a part in that project.");
  const found = { project, id: now.id, title: await titleOf(env, project), role };
  // **Asked on every call, like the role**: a portal can get its film later,
  // and a film is never a portal. One small read for a film (`filmlessPortal`).
  const portal = await filmlessPortal(env, project);
  const asked = await gateHere(env, held, who, name, args, ctx, found);
  if (asked !== null) return asked;

  // **The portal's own three go nowhere near the film's document.** They write
  // a card beside it; the engine neither knows nor should know that a web page
  // about the film exists.
  if (name === "front" || name === "set_front" || name === "add_document") {
    return await frontTool(env, found, held, name, args, ctx);
  }
  // **The project record** (`recordtools.js`) — beside the film, like the card.
  if (RECORD_TOOL_NAMES.has(name)) return await recordTool(env, found, name, args, refuse);
  // **Its Studio modes** (`studiomodes.js`'s own door, stage 5 step 5): the
  // switch, the both-off rule and the Studio side made lazily are all there.
  if (name === "modes") return (await modesTool(env, found, args, refuse, who)).said;
    if (name === "mods") return await modsTool(env, found, args, refuse, who);
  // **The Camera Spec Sheets** (`kittools.js`, Ref 1627) — Notion's, beside
  // the film like the record; a portal with no film has them too.
  if (KIT_TOOL_NAMES.has(name)) return await kitTool(env, found, name, args, refuse, ctx);

  // **The record's pages, which are beside the film rather than in it.** Same
  // bargain as the card: the engine neither knows nor should know that a web
  // page about the film exists.
  if (name === "deck" || name === "set_deck") return await deckTool(name, args, env, found);
  // **Boards** — `boards.js`. Asked who this is on every call, like the rest:
  // a board he keeps to himself is nobody else's to read, here as on the page.
  if (name === "boards" || name === "board" || name === "add_board" || name === "set_board" || name === "arrange_board") {
    return await boardTool(env, found, who, isAdmin(env, who), name, args, {
      frontOf, saveFront, pageHtml: pageHtmlOf, boardOpen, refuse, attachToShot, ctx,
      // A portal has no film to show a board, whatever stray logs say.
      filmView: () => (portal ? {} : filmView(env, found, ctx)),
    });
  }
  if (name === "pages" || name === "page" || name === "set_page" || name === "remove_page"
      || name === "set_source" || name === "arrange" || name === "rename_page" || name === "rename_document"
      || name === "library" || name === "set_on_sidebar" || name === "archive_page" || name === "move_to_shelf" || name === "edit_shelves" || name === "set_icon") {
    return await pageTool(env, found, name, args, who);
  }
  if (name === "follow_doc") return await followTool(env, found, who, args);
  if (name === "visibility" || name === "set_visibility") return await visibilityTool(env, found, who, name, args);
  if (name === "access" || name === "set_access") return await accessTool(env, found, who, name, args);
  if (name === "views" || name === "share_view" || name === "set_view") return await viewsTool(env, found, who, name, args, ctx);
  // **A picture or clip onto the film from the web** (`mcpattach.js`): the
  // Mac's `attach` reads his disk; here it comes by address or as bytes.
  if (name === "refresh_from_notion") return await refreshTool(env, found, isAdmin(env, who), refuse);
  // **Projects Console's actions** (`consoletools.js`): the same server code
  // the console and the iPhone call, his alone, and whatever moves, deletes,
  // hides, publishes or changes who can see something in two steps with his
  // OK in between (`consolegate.js`).
  if (CONSOLE_TOOL_NAMES.has(name)) {
    if (portal && (name === "link_edits" || name === "undo_link_edit")) throw refuse(notAFilm(found.title));
    return await consoleTool(env, found, name, args || {}, refuse, who, isAdmin(env, who), {
      diagramEdit: (asked) => diagramEdit(env, found.project, who, ctx, asked),
    });
  }
  if (name === "add_picture") {
    if (portal) throw refuse(notAFilm(found.title));
    return await attachTool(env, found, args, refuse, { attach: (asked) => attachToShot(env, found.project, who, ctx, asked) });
  }

  // **Everything past here is the film's own** — the engine's tools, read or
  // write. A portal has no film, so none of them has anything true to say:
  // a read would answer from an empty film, or from stray logs, and a write
  // would put a film's changes where nothing reads them (SL-1376, Halcyon).
  if (portal) throw refuse(notAFilm(found.title));

  // **Diagram mode** (`mcp/src/server/diagram.rs`). Two of its tools need what
  // the engine in here cannot reach: a picture wants a browser to draw it,
  // and a scanned room wants its measurements out of the bucket.
  if (name === "diagram_picture") return await diagramPicture(env, found, held, args, ctx);
  if (name === "lay_room" && !args.measurements) return await layRoom(env, found, held, args, ctx);

  if (name === "summary") return await summaryHere(env, found, held, ctx);
  // **Studio's Export, filed in Drive** (`exporting.js`).
  if (name === "export") return await exportTool(env, found, held, args, ctx, { run, refuse });
  if (INSIDE_ONLY.has(name)) throw refuse(`Unknown tool: ${name}`);
  if (name === "update_project") return await updateFilmHere(env, found, held, args, ctx);
  // The kit taken from the film's own spec sheets when none is given.
  if (name === "take_kit") return await run(env, found, held, { name, arguments: await kitArguments(env, found, args, ctx) }, ctx);

  return await run(env, found, held, { name, arguments: args }, ctx);
}

/**
 * **The same export for the Mac and the phone** (`POST
 * /console/studio/export/<project>`, `studio.js`): his token, so he is the
 * editor, and the project named by its ID. Answers what `export` answers.
 */
export async function consoleExport(env, id, args, ctx) {
  const { key, record } = await resolveProject(env, id);
  if (!key) throw refuse("No project has that ID.");
  const film = studioOf(record);
  if (!film) throw refuse("This project has no Studio side to export.");
  const owner = String(env.OWNER || "").split(",")[0].trim();
  const found = { project: film, id: key, title: await titleOf(env, film), role: "editor" };
  return await exportTool(env, found, { email: owner }, args || {}, ctx, { run, refuse });
}

/** The engine's summary, with the names the record gives the film laid over
 * it — what the film shows once its mirror has run. */
async function summaryHere(env, found, held, ctx) {
  const said = await run(env, found, held, { name: "summary", arguments: {} }, ctx);
  let summary;
  try { summary = JSON.parse(said); } catch { return said; }
  // **Project or Job, and its Type** (stage 5 step 5): from the project's own
  // record, found by its ID. Kind follows Type: Commercial and Music Video
  // are commercials.
  let mine = null;
  try { mine = found.id ? (await resolveProject(env, found.id)).record : null; } catch { mine = null; }
  const who = projectFacts(mine, found.id || found.project);
  let view = null;
  try { view = await recordOfOpen(env, found.project); } catch { view = null; }
  const out = { ...summary, project_id: who.id, is: who.is, type: who.type, ...(view ? { ...namesFromRecord(view), hidden: view.hidden } : {}) };
  return view ? JSON.stringify(out, null, 1) : JSON.stringify(out);
}

/** `update_film`: the four names to the record when the film has one; the
 * title and the frame to the film. A film that does not yet take its names
 * from the record gets them as well, so it shows them before its mirror runs. */
async function updateFilmHere(env, found, held, args, ctx) {
  const routed = await filmNamesToRecord(env, found, args || {}, refuse);
  if (!routed) return await run(env, found, held, { name: "update_project", arguments: args }, ctx);
  let toFilm = routed.rest;
  let own = false;
  try { own = JSON.parse(await run(env, found, held, { name: "summary", arguments: {} }, ctx)).facts !== "record"; } catch { own = false; }
  if (own) toFilm = args;
  const lines = [];
  if (routed.said.length) lines.push(`Written to the project record: ${routed.said.join(", ")}. Studio follows within minutes.`);
  else lines.push(`The record already says ${routed.names.join(", ")}.`);
  if (Object.keys(toFilm).some((k) => toFilm[k] !== undefined)) lines.push(await run(env, found, held, { name: "update_project", arguments: toFilm }, ctx));
  return lines.join(" ");
}

// ---------------------------------------------------------------- diagram mode

/**
 * **A plan Claude can look at.** The engine draws the SVG exactly as the Mac
 * and the portal do; what it cannot do here is hold the pictures in it — the
 * Film Set Objects pack is left out of this build, and the film's own files
 * are in the bucket, not in the engine — or turn it into a PNG. So each
 * `fso/<id>.png` and `media/<file>` the plan names is read from the bucket and
 * put inside it, and Cloudflare's own Chrome (the press's, `press.js`)
 * photographs it. A picture that is not there is left out rather than
 * failing the whole plan.
 */
async function diagramPicture(env, found, held, args, ctx) {
  let svg = await run(env, found, held, { name: "diagram_picture", arguments: args }, ctx);
  if (!svg.startsWith("<svg")) return svg;
  const names = [...new Set([...svg.matchAll(/href="((?:fso|media)\/[^"]+)"/g)].map((m) => m[1]))];
  const inside = await Promise.all(names.map(async (at) => {
    const [folder, file] = [at.slice(0, at.indexOf("/")), at.slice(at.indexOf("/") + 1)];
    const tries = folder === "fso" ? [`fso/${file}`]
      : [keys.inFolder(found.project, "media", file), keys.inFolder(found.project, "media", file.replace(/\.jpg$/, ".png"))];
    for (const key of tries) {
      const got = await env.BUCKET.get(key);
      if (!got) continue;
      const bytes = new Uint8Array(await got.arrayBuffer());
      const ext = key.split(".").pop().toLowerCase();
      const type = ext === "jpg" || ext === "jpeg" ? "image/jpeg" : ext === "webp" ? "image/webp" : "image/png";
      return [at, `data:${type};base64,${base64Of(bytes)}`];
    }
    return [at, ""];
  }));
  for (const [at, data] of inside) {
    if (data) svg = svg.split(`href="${at}"`).join(`href="${data}"`);
  }
  const size = /width="([\d.]+)" height="([\d.]+)"/.exec(svg.slice(0, svg.indexOf(">")));
  const width = Math.round(Number(size && size[1]) || 1200);
  const height = Math.round(Number(size && size[2]) || 800);

  let png;
  const browser = await puppeteer.launch(env.BROWSER, { keep_alive: 60_000 });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width, height, deviceScaleFactor: 1 });
    await page.setContent(`<!DOCTYPE html><html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0}svg{display:block}</style></head><body>${svg}</body></html>`, { waitUntil: "load", timeout: 30_000 });
    png = await page.screenshot({ type: "png", clip: { x: 0, y: 0, width, height } });
  } finally {
    await browser.close();
  }
  const bytes = png instanceof Uint8Array ? png : new Uint8Array(png);
  const missing = inside.filter(([, data]) => !data).length;
  return {
    content: [
      { type: "image", data: base64Of(bytes), mimeType: "image/png" },
      ...(missing ? [{ type: "text", text: `${missing} picture${missing === 1 ? "" : "s"} on the plan had not reached the portal and are left out.` }] : []),
    ],
  };
}

/**
 * **A scanned room, from the bucket.** `room_scans` names the file each
 * scan's measurements are kept under; this fetches the one asked for and
 * hands its words to `lay_room`, which on a Mac reads the file itself.
 */
async function layRoom(env, found, held, args, ctx) {
  const scans = JSON.parse(await run(env, found, held, { name: "room_scans", arguments: { scene: args.scene } }, ctx));
  const wanted = String(args.scan || "").trim().toLowerCase();
  const place = String(args.location || "").trim().toLowerCase();
  const scan = scans.find((s) => (!wanted || s.scan.toLowerCase() === wanted) && (!place || s.location.toLowerCase().includes(place)));
  // Nothing to fetch: the engine says why, in its own words.
  if (!scan || !scan.file) return await run(env, found, held, { name: "lay_room", arguments: args }, ctx);
  const got = await env.BUCKET.get(keys.inFolder(found.project, "media", scan.file));
  if (!got) throw refuse(`The ${scan.scan} scan's measurements have not reached the portal yet — open the project on the phone that scanned it, or lay it from the Mac.`);
  return await run(env, found, held, {
    name: "lay_room",
    arguments: { ...args, scan: scan.scan, location: scan.location, measurements: await got.text() },
  }, ctx);
}

// ------------------------------------------------------ the portal's own card

/**
 * Read or write what the portal says about a film.
 *
 * The one rule worth stating: **the film's own facts are asked of the film,
 * every time, and cannot be passed in.** A count or a ratio that arrived as an
 * argument is a number somebody transcribed, and it would go quietly wrong the
 * first time a scene was added. The words — which nothing here can know — are
 * the only thing this takes on trust.
 */
async function frontTool(env, found, held, name, args, ctx) {
  const front = await frontOf(env, found.project, ctx);

  if (name === "front") {
    const page = `https://your-domain.example/f/${found.project}`;
    const asked = String(args.shoot || "");
    if (asked && (front.shoots || []).length < 2) throw refuse("This project shoots once; it has no shoot tabs.");
    if (asked && !front.shoots.some((one) => one.slug === asked)) {
      throw refuse(`No shoot called ${asked}. This project's are ${front.shoots.map((one) => one.slug).join(", ")}.`);
    }
    const shown = shotView(front, asked);
    const { shootPages, ...said } = shown;
    if (said.shootOn) said.shootOn.page = `${page}/shoots/${said.shootOn.slug}`;
    // Lens sets beside each Lenses text, read as the portal draws them.
    said.camera = withLensSets(said.camera);
    if (said.was && said.was.camera) said.was = { ...said.was, camera: withLensSets(said.was.camera) };
    if (Array.isArray(said.shoots)) said.shoots = said.shoots.map((one) => (one && one.camera ? { ...one, camera: withLensSets(one.camera) } : one));
    return JSON.stringify({ film: found.title, page, ...said }, null, 1);
  }

  if (found.role !== "editor") throw refuse("Only an editor may change a project's page.");

  if (name === "add_document") {
    /**
     * **A link is not second best, and until now an agent could not make one.**
     * His instruction, 2026-09-08: *"any AI using the MCP should be able to do
     * any of the things that I can do here."* He can pin a Drive folder or a
     * video from the Add screen; the only door here was `set_front`, which
     * **replaces the whole list** — so adding one link meant sending every
     * other document back exactly right or losing them.
     *
     * `source: "here"` is what keeps it. `both_kinds` in `refresh.py` used to
     * tell his uploads from Notion's links by asking which carried a `file`, so
     * a link put here without it would be swept away by the next refresh.
     */
    const said = String(args.url || "").trim();
    if (said) {
      if (args.base64) throw refuse("Send the bytes or a link, not both.");
      let where = "";
      try {
        const url = new URL(said);
        if (url.protocol === "https:" || url.protocol === "http:") where = url.toString();
      } catch { /* not an address at all */ }
      if (!where) throw refuse("A link is an `http` or `https` address.");
      const called = String(args.name || "").replace(/\s+/g, " ").trim();
      if (!called) throw refuse("Say what to call it on the page.");
      if (args.kind === "key_image" || args.kind === "picture") {
        // **The hub fetches it, so an agent never writes the bytes out.** Hand-copying a
        // photograph into a tool call is why pictures went up at 300px (Ref 1442). A Drive
        // link shared as *anyone with the link* gives the original; a private one answers
        // with a sign-in page, which is refused plainly rather than stored as a picture.
        const file = await fetchPictureFile(env, found.project, where);
        if (!file) {
          throw refuse(
            driveIdOf(new URL(where))
              ? "Drive would not hand that picture over. It must be shared as anyone with the link; a private file cannot be fetched from here. From the Mac, `tools/upload-picture.sh` puts it up from a file path."
              : "Could not fetch a picture from that address. It must be a public JPG, PNG, WebP or GIF under 25 MB."
          );
        }
        if (args.kind === "key_image") {
          front.key_image = file;
          front.updated = new Date().toISOString();
          await saveFront(env, found.project, front);
          return `${found.title}'s picture is now ${file}, fetched at full size.`;
        }
        return `Fetched and stored at full size. Write it into a page as ![caption](${file}).`;
      }
      const existed = (front.documents || []).some((d) => d.name.trim().toLowerCase() === called.toLowerCase());
      front.documents = (front.documents || [])
        .filter((d) => d.name.trim().toLowerCase() !== called.toLowerCase())
        .concat({
          name: called,
          kind: args.kind === "lookbook" ? "lookbook" : "document",
          url: where,
          source: "here",
        });
      // **A new link is on the sidebar like a new page**; one being replaced keeps
      // whatever place he gave it.
      if (!existed && args.kind !== "lookbook") setOnSidebar(front, `doc:${called}`, true);
      front.updated = new Date().toISOString();
      await saveFront(env, found.project, front);
      return `${called} is on ${found.title}'s sidebar and in its Library, pointing at ${where}.`;
    }
    const stored = await storeFile(env, found.project, args);
    // **A picture for a page is stored and not listed.** Twenty frames written
    // into a bible would otherwise appear twenty times under Documents, which
    // is the pinned-things list and not a media folder. The name goes back in
    // the reply; that is what `set_page` draws it from.
    if (args.kind === "picture") {
      return `Stored ${stored.bytes} bytes. Write it into a page as ![caption](${stored.file}).`;
    }
    if (args.kind === "key_image") {
      front.key_image = stored.file;
    } else {
      front.documents = front.documents
        .filter((d) => d.file !== stored.file)
        .concat({
          name: String(args.name),
          kind: args.kind === "lookbook" ? "lookbook" : "document",
          file: stored.file,
          bytes: stored.bytes,
        });
    }
    front.updated = new Date().toISOString();
    await saveFront(env, found.project, front);
    return `Put ${stored.bytes} bytes on the page as ${stored.file}.`;
  }

  // ---- set_front ---------------------------------------------------------
  // **The logline and synopsis go through the project record** (2026-10-05,
  // the Notion link). Written onto the card alone, a logline was put back
  // from Notion by the Mac's next refresh; through the record it keeps a
  // version, shows in his History, and the Studio's link writes it into the
  // Notion page's Logline / Synopsis boxes within a minute. A film with no
  // record yet keeps the old behaviour: the card only.
  let recorded = "";
  const notKept = [];
  const offCard = new Set();
  // Everything set_front says that the record holds goes through it since
  // 2026-10-05 — status, type, length and the shoot dates too, which written
  // onto the card alone were put back by the next refresh. A fact the
  // project hides, or one the record will not take (a Post status, a type
  // Notion has no choice for), is left off the card as well and said in the
  // reply; the rest of the call still goes through.
  const AS_FACT = { logline: "logline", synopsis: "synopsis", note: "directors_note", look: "visual_language",
    status: "status", type: "type", length: "length" };
  const asked = {};
  for (const [arg, field] of Object.entries(AS_FACT)) {
    if (args[arg] !== undefined) asked[field] = String(args[arg]);
  }
  if (args.shoot_start !== undefined || args.shoot_end !== undefined) {
    asked.shoot_dates = datesFrom(args.shoot_start !== undefined ? args.shoot_start : front.shoot.start,
      args.shoot_end !== undefined ? args.shoot_end : front.shoot.end);
  }
  if (Object.keys(asked).length) {
    const view = await recordOfOpen(env, found.project);
    if (view) {
      const { changes, refused } = await planFacts(env, view, asked);
      for (const [field, why] of Object.entries(refused)) {
        notKept.push(`${LABEL[field]}: ${why}.`);
        offCard.add(field);
      }
      if (Object.keys(changes).length) {
        const got = await writeFacts(env, view.page, changes, BY);
        if (got.status !== 200) {
          throw refuse(got.conflicts ? `Nothing written. ${conflictSaid(got.conflicts)}. Read the page again and retry.`
            : `The project record would not take it: ${got.problem}`);
        }
        recorded = Object.keys(changes).map((f) => LABEL[f].toLowerCase()).join(", ");
      }
    } else if (asked.synopsis !== undefined) {
      throw refuse("This project has no record yet, so there is nowhere to keep a synopsis.");
    }
  }
  for (const field of ["logline", "note", "look", "status", "type", "length", "source"]) {
    if (args[field] !== undefined && !offCard.has(AS_FACT[field])) front[field] = String(args[field]);
  }
  if (!offCard.has("shoot_dates")) {
    if (args.shoot_start !== undefined) front.shoot.start = String(args.shoot_start);
    if (args.shoot_end !== undefined) front.shoot.end = String(args.shoot_end);
  }
  if (args.key_image !== undefined) {
    const said = String(args.key_image);
    if (said && !FILE_NAME.test(said)) throw refuse("A key image is a stored file name like `a1b2….jpg`.");
    front.key_image = said;
  }
  if (Array.isArray(args.documents)) front.documents = args.documents;
  if (Array.isArray(args.crew)) front.crew = args.crew;
  if (args.camera && typeof args.camera === "object") front.camera = args.camera;

  // **Asked of the film, never taken from the caller.**
  let vitals = null;
  try {
    vitals = JSON.parse(await run(env, found, held, { name: "summary", arguments: {} }, ctx));
  } catch {
    // A film whose summary will not parse still deserves its words saved; the
    // counts simply stay as they were rather than being invented.
  }
  if (vitals) {
    front.director = String(vitals.director || "");
    front.producer = String(vitals.producer || "");
    front.ratio = Number(vitals.ratio) || 0;
    front.counts = {
      ...front.counts,
      scenes: Number(vitals.scenes) || 0,
      shots: Number(vitals.shots) || 0,
      locations: Number(vitals.locations) || 0,
      boards: Number(vitals.boards) || 0,
      days: Number(vitals.days) || 0,
    };
  }
  front.counts.pictures = await countPictures(env, found.project);
  front.updated = new Date().toISOString();

  const saved = tidy(front);
  await saveFront(env, found.project, saved);
  const lost = (Array.isArray(args.documents) ? args.documents.length : saved.documents.length) - saved.documents.length;
  return `${found.title} is up at your-domain.example/f/${found.project} — ${saved.counts.scenes} scenes, ${saved.counts.shots} shots, ${saved.documents.length} documents, ${saved.crew.length} contacts${
    Object.values(saved.camera).some(Boolean) ? ", and a camera spec sheet" : ""
  }.${
    lost > 0 ? ` ${lost} document${lost === 1 ? "" : "s"} dropped for having neither a link nor a file.` : ""
  }${
    recorded ? ` The ${recorded} went into the project record; his Notion page follows within a minute or two.` : ""
  }${notKept.length ? ` Not kept: ${notKept.join(" ")}` : ""}`;
}

// ------------------------------------------------------ the record's pages

/**
 * Read, write and remove the pages of the record.
 *
 * ## Why this is here at all
 *
 * The store was already general. A page has always lived at
 * `p/<film>/pages/<slug>.json`, `front.sections` has always been a list of
 * whatever he named rather than a fixed four, and the router has matched the
 * *shape* of a name since 2026-09-02. Everything was in place except a way to
 * write one that was not `refresh.py` reading Notion — so an agent that had
 * just worked out a film's visual language had to ask him to make a Notion page
 * for it first, and then wait for a refresh.
 *
 * ## The two roads, and why they do not run into each other
 *
 * A refresh rewrites `sections` with exactly what Notion names, which would
 * take an agent's page off the rail an hour after it was made. So a section
 * written here is stamped `by: "mcp"`, `front.js` keeps that stamp, and
 * `refresh.py` carries those across untouched. The rule that falls out of it is
 * the one stated in the tool: **whoever made a page owns it.** An agent may not
 * rewrite his Notion bible from here, and a refresh may not delete an agent's
 * lighting plan.
 */
/**
 * What each source is called, in the words the portal uses.
 *
 * **`SOURCE_SAID` in `src/pages.js` and `sourceSaid` in `public/film.js` are
 * the same four.** Three copies of one list is two too many; they exist because
 * the worker, the browser and this cannot import each other's halves. Change
 * one and change all three.
 */
const SOURCE_SAID = {
  notion: "Live from Notion",
  "notion-once": "Copied from Notion once",
  here: "Written here",
  program: "From the Deck Editor",
};

/** Where a section's words come from, when the card does not say. Mirrors
 *  `sourceFrom` in `front.js` and `source_of` in `refresh.py`. */
function sourceOf(one) {
  if (PAGE_SOURCES.includes(one.source) || one.source === "program") return one.source;
  return one.by === "deck" ? "program" : one.by === "mcp" ? "here" : "notion";
}

/**
 * What an agent may do to a page, asked of the source rather than of `by`.
 *
 * **The old answer was wrong in one direction that mattered.** It said "change
 * it in Notion" of anything Notion made — including a page he has taken a
 * snapshot of, where Notion no longer reaches the site at all, so an agent
 * following that advice would edit a page nobody would ever read again.
 */
function mayDo(one) {
  const source = sourceOf(one);
  if (source === "program") return "read it — change it in Deck Editor and publish";
  if (source === "notion") {
    return "rewrite it with set_page, which takes it over — or change it in Notion, which is where it comes from now";
  }
  return one.by === "mcp" ? "rewrite or remove it" : "rewrite it — Notion has let go of this one";
}

/**
 * The Script page, as the connector says it: where it is, the address that is
 * always the newest PDF, and every draft with its own. Read off the film — a
 * new draft comes in by Import Script on the Mac, never from here.
 */
function scriptSaid(found, front) {
  const base = `https://your-domain.example/f/${found.project}`;
  return {
    page: "Script",
    address: `${base}/script`,
    slug: "script",
    made_by: "the project — the drafts taken in with Import Script on the Mac",
    you_may: "read it; the newest draft is always the one shown",
    newest_pdf: `${base}/script.pdf`,
    drafts: (front.scripts || []).map((d, i) => ({
      name: d.name,
      file: d.came_from,
      dated: d.dated,
      latest: i === 0,
      pdf: `${base}/script.pdf?draft=${d.stem}`,
    })),
  };
}

/**
 * **What Viewers See, from here too.** The connector rule, his, 2026-09-30:
 * anything he can do in the program, the MCP can do. The same gate as the
 * panel: his alone. Private is what a page's own menu calls it. For Me is
 * retired (2026-10-03): its data is kept and applied nowhere.
 */
const VIS_BUILT_IN = ["shotlist", "script", "diagrams", "locations", "schedule", "bible", "boards", "camera", "people", "documents"];

async function visibilityTool(env, found, who, name, args) {
  if (!isAdmin(env, who)) throw refuse("Only he may say what is shown.");
  const [front, visible] = await Promise.all([frontOf(env, found.project), visibleOf(env, found.project)]);
  const boards = (front.sections || []).filter((one) => one.type === "board" && one.slug);
  const sections = [...new Set([...VIS_BUILT_IN, ...(front.sections || []).map((one) => one.slug).filter(Boolean)])];
  const named = { sections: (front.sections || []).filter((one) => one.slug).map((one) => ({ slug: one.slug, name: one.name })) };
  if (name === "visibility") {
    return JSON.stringify({
      film: found.title,
      private: { sections: visible.sections, people: visible.crew, documents: visible.documents, contact_shown: visible.contact,
        boards: boards.map((one) => ({ slug: one.slug, shared_with: one.share })) },
      sections: [...VIS_BUILT_IN.filter((at) => !named.sections.some((one) => one.slug === at)).map((at) => ({ slug: at })), ...named.sections],
    }, null, 1);
  }
  if (args.for === "me") throw refuse("For Me is retired. Whether a page has a row in the sidebar is `set_on_sidebar` (pinned); who may see it is `private`.");
  if (args.for !== undefined && args.for !== "links") throw refuse("`for` is retired; leave it out.");
  const known = {
    sections: new Set(sections.filter((at) => !boards.some((one) => one.slug === at))),
    crew: new Set(everyone(front).map((one) => one.name).filter(Boolean)),
    documents: new Set((front.documents || []).map((doc) => doc.name).filter(Boolean)),
  };
  const lists = visible;
  const said = [];
  const touch = (group, hide) => {
    if (!group) return;
    if (typeof group !== "object" || Array.isArray(group)) throw refuse("`hide` and `show` are `{ sections, people, documents }`.");
    for (const [field, kind] of [["sections", "sections"], ["people", "crew"], ["documents", "documents"]]) {
      if (group[field] === undefined) continue;
      if (!Array.isArray(group[field])) throw refuse(`\`${field}\` is a list.`);
      for (const raw of group[field]) {
        const key = String(raw);
        if (!known[kind].has(key)) {
          if (kind === "sections" && boards.some((one) => one.slug === key)) throw refuse(`${key} is a board; who sees it on a link is \`set_board\` \`share\`.`);
          throw refuse(`No ${field === "people" ? "person" : field.slice(0, -1)} called ${key}. Ask for \`visibility\`.`);
        }
        const now = new Set(lists[kind]);
        if (hide) now.add(key); else now.delete(key);
        lists[kind] = [...now];
        said.push(`${hide ? "made private" : "made public"} ${key}`);
      }
    }
  };
  touch(args.private || args.hide, true);
  touch(args.public || args.show, false);
  if (args.contact !== undefined) {
    const now = new Set(visible.contact);
    for (const [field, on] of [["on", true], ["off", false]]) {
      for (const raw of (args.contact && Array.isArray(args.contact[field]) ? args.contact[field] : [])) {
        const key = String(raw);
        if (!known.crew.has(key)) throw refuse(`No person called ${key}. Ask for \`visibility\`.`);
        if (on) now.add(key); else now.delete(key);
        said.push(`contact ${on ? "on" : "off"} for ${key}`);
      }
    }
    visible.contact = [...now];
  }
  if (!said.length) throw refuse("Nothing to change. Send `private`, `public` or `contact`.");
  await saveVisible(env, found.project, visible);
  return `${found.title}: ${said.join(", ")}.`;
}

/**
 * **Who may open the film** — the Share popover's People tab, from a chat. The
 * list is the one `/api/people` writes (same shape, same file), so the two can
 * never disagree. A key is made here the way the browser makes it: random,
 * kept, and matched by its hash.
 */
async function accessTool(env, found, who, name, args) {
  if (!isAdmin(env, who)) throw refuse("Only he may say who can open the project.");
  const project = found.project;
  const list = await peopleOf(env, project);
  const short = await shortOf(env, project);
  const address = (link) => (link && link.key
    ? `https://share.your-domain.example/${short || `f/${project}`}${short ? "" : `?k=${link.key}`}`
    : "");
  const told = () => {
    const link = list.links.find((l) => l && l.key) || null;
    return {
      film: found.title,
      general_access: !link ? "restricted (no link made)" : link.off ? "restricted (link kept, off)" : "anyone with the link",
      link: link && !link.off ? address(link) : undefined,
      password: link && link.pass ? "set" : "none",
      people: list.people.map((p) => ({ email: p.email, role: p.role, owner: owners(env).includes(p.email) || undefined, joined_by: p.via })),
      invites: list.invites.length,
    };
  };
  if (name === "access") {
    const kept = await env.BUCKET.get(`${keys.pages(project).replace(/pages\/$/, "")}diagram.settings.json`);
    let set = {};
    try { set = kept ? await kept.json() : {}; } catch { set = {}; }
    return JSON.stringify({ ...told(), short: short || undefined, diagram_link_edit: set.publicEdit !== false }, null, 1);
  }

  // **The rules are `changeAccess`'s** (`access.js`), shared with the
  // Projects Console's door, so the two cannot drift; only the hints that
  // name this tool's own fields are added here.
  const HINTS = { already: " Use `role` to change them.", absent: " Ask for `access`.", nolink: " Send `link: \"anyone\"` first." };
  const ask = { add: args.add, role: args.role, remove: args.remove, link: args.link, password: args.password };
  const extra = [];
  // **The short name and the Diagrams page's link switch** (2026-10-17): the
  // Share panel's own field and the Diagrams page's Editable by Link.
  if (args.short !== undefined) {
    const { SHORT, RESERVED, claimShort } = await import("./films.js");
    const wanted = String(args.short || "").trim().toLowerCase();
    if (!SHORT.test(wanted)) throw refuse("A short name is 2–24 letters or digits.");
    if (RESERVED.has(wanted)) throw refuse("That name is the hub's own.");
    if (wanted !== short) {
      const got = await claimShort(env, project, wanted);
      if (!got) throw refuse(`${wanted} is taken by another project.`);
      extra.push(`the link is now share.your-domain.example/${got}${short ? ` (${short} still works)` : ""}`);
    }
  }
  if (typeof args.diagram_link_edit === "boolean") {
    const at = `${keys.pages(project).replace(/pages\/$/, "")}diagram.settings.json`;
    const kept = await env.BUCKET.get(at);
    let set = {};
    try { set = kept ? await kept.json() : {}; } catch { set = {}; }
    if ((set.publicEdit !== false) !== args.diagram_link_edit || set.publicEdit === undefined) {
      await env.BUCKET.put(at, JSON.stringify({ ...set, publicEdit: args.diagram_link_edit }), { httpMetadata: { contentType: "application/json; charset=utf-8" } });
    }
    extra.push(args.diagram_link_edit ? "people with the link may draw on the Diagrams page" : "people with the link only look at the Diagrams page");
  }
  const touchesPeople = ["add", "role", "remove", "link", "password"].some((k) => args[k] !== undefined);
  let said = [];
  if (touchesPeople) {
    try {
      said = await changeAccess(env, list, ask, { mint: () => random(24) });
    } catch (error) {
      if (error instanceof Refusal) throw refuse(error.said + (HINTS[error.code] || ""));
      throw error;
    }
  }
  if (!said.length && !extra.length) throw refuse("Nothing to change. Send `link`, `add`, `role`, `remove`, `password`, `short` or `diagram_link_edit`.");
  if (said.length && !(await savePeople(env, project, { version: 1, ...list }))) throw refuse("Somebody changed the list at the same moment. Try again.");
  return `${found.title}: ${[...said, ...extra].join(", ")}.`;
}

/**
 * **View links** (`views.js`): the Share panel's Views, from a chat. The
 * filter is checked against the film itself, so a view that would keep no
 * shots is refused with the values there are, not made empty.
 */
const NOT_A_FACET = new Set(["image", "struck", "title", "description", "notes", "number", "synopsis", "script"]);
async function viewsTool(env, found, who, name, args, ctx) {
  if (!isAdmin(env, who)) throw refuse("Only he may share views.");
  const short = await shortOf(env, found.project);
  const link = (v) => `https://share.your-domain.example${viewPath(v, short, found.project)}`;
  const model = await filmView(env, found, ctx);
  const rows = (model.groups || []).flatMap((g) => g.rows || []);
  const fields = (model.columns || []).filter((c) => !NOT_A_FACET.has(c.name) && c.kind !== "check").map((c) => {
    const values = new Set();
    for (const r of rows) {
      let v = r[c.name];
      if (v === undefined && r.custom) v = r.custom[c.name];
      for (const one of Array.isArray(v) ? v : [v]) { const said = named(one).trim(); if (said) values.add(said); }
    }
    return { field: c.name, label: c.label || c.name, values: [...values].sort() };
  }).filter((f) => f.values.length);
  const told = (v) => ({
    name: v.name, code: v.code, on: !v.off, shooting_order: v.groupBy === "day", link: link(v),
    filters: (v.facets || []).map(([f, value]) => ({ field: (fields.find((x) => x.field === f) || {}).label || f, value })),
    shots: rows.filter((r) => keeps(r, v.facets)).length,
  });
  const facetsFrom = (filters) => {
    if (!Array.isArray(filters) || !filters.length) throw refuse("`filters` is a list of `{ field, value }`.");
    return filters.map((one) => {
      const want = String((one && one.field) || "").trim().toLowerCase();
      const field = fields.find((f) => f.field.toLowerCase() === want || f.label.toLowerCase() === want);
      if (!field) throw refuse(`No field called ${one && one.field}. There are: ${fields.map((f) => f.label).join(", ")}.`);
      const value = field.values.find((v) => v.toLowerCase() === String(one.value || "").trim().toLowerCase());
      if (!value) throw refuse(`No shot has ${field.label} ${one.value}. Its values: ${field.values.slice(0, 40).join(", ")}.`);
      return [field.field, value];
    });
  };
  const all = (await viewsOf(env, found.project)).views;
  if (name === "views") {
    return JSON.stringify({ film: found.title, views: all.map(told), fields: fields.map((f) => ({ field: f.label, values: f.values.slice(0, 60) })) }, null, 1);
  }
  if (name === "share_view") {
    const facets = facetsFrom(args.filters);
    if (!rows.some((r) => keeps(r, facets))) throw refuse("That filter keeps no shots.");
    const made = await makeView(env, found.project, { name: args.name, facets, groupBy: args.shooting_order ? "day" : "scene" }, who.email);
    const said = told(made);
    return `${said.name}: ${said.shots} shot${said.shots === 1 ? "" : "s"} of ${found.title}, at ${said.link}`;
  }
  const want = String(args.view || "").trim().toLowerCase();
  const view = all.find((v) => v.code === want) || all.find((v) => String(v.name).toLowerCase() === want);
  if (!view) throw refuse(`No view called ${args.view}. Ask for \`views\`.`);
  if (args.remove === true) {
    await removeView(env, found.project, view.code);
    return `Removed ${view.name}. Its link opens nothing now.`;
  }
  const change = {};
  if (typeof args.name === "string" && args.name.trim()) change.name = args.name;
  if (typeof args.on === "boolean") change.off = !args.on;
  if (args.filters !== undefined) change.facets = facetsFrom(args.filters);
  if (typeof args.shooting_order === "boolean") change.groupBy = args.shooting_order ? "day" : "scene";
  if (!Object.keys(change).length) throw refuse("Nothing to change. Send `name`, `on`, `filters`, `shooting_order` or `remove`.");
  const after = await changeView(env, found.project, view.code, change);
  const said = told(after);
  return `${said.name} is ${said.on ? "on" : "off"}: ${said.shots} shot${said.shots === 1 ? "" : "s"}, at ${said.link}`;
}

/** The film's own pages, which the Library lists beside the ones he has made. */
const LIBRARY_BUILT = [
  { slug: "shotlist", name: "Shot List" }, { slug: "script", name: "Script" }, { slug: "diagrams", name: "Diagrams" },
  { slug: "locations", name: "Locations" }, { slug: "schedule", name: "Schedule" }, { slug: "boards", name: "Reference Images" },
  { slug: "bible", name: "Visual Bible" }, { slug: "camera", name: "Camera Spec Sheet" },
  { slug: "people", name: "People" }, { slug: "documents", name: "Documents" },
];
const libraryKnown = (slug, mine) => LIBRARY_BUILT.some((b) => b.slug === slug) || mine.some((s) => s.slug === slug);
const libraryName = (slug, mine) => (mine.find((s) => s.slug === slug) || LIBRARY_BUILT.find((b) => b.slug === slug) || { name: slug }).name;

/** `follow_doc` — the page menu's Follow Google Doc (`docfollow.js`). */
async function followTool(env, found, who, args) {
  if (!isAdmin(env, who)) throw refuse("Only an administrator may change what a page follows.");
  const slug = slugFrom(args.slug || args.page || "");
  const writes = args.on !== undefined || args.refresh || args.doc !== undefined || args.credit !== undefined;
  if (!writes) {
    const state = await followStateOf(env, found.project, slug);
    if (!state) throw refuse(`${slug || "That page"} does not follow a Google Doc. Point it at one with \`doc\`.`);
    return JSON.stringify({ slug, connected: driveReady(env), ...state }, null, 2);
  }
  const got = await setFollow(env, found.project, slug, {
    on: args.on === undefined ? undefined : Boolean(args.on), refresh: Boolean(args.refresh),
    doc: args.doc, credit: args.credit,
  });
  if (!got.ok && got.status !== 502) throw refuse(got.said);
  return JSON.stringify({ slug, connected: driveReady(env), ...got }, null, 2);
}

async function pageTool(env, found, name, args, who = null) {
  const front = await frontOf(env, found.project);
  const admin = isAdmin(env, who);
  // **A board he keeps to himself is not listed to anybody else** (`boardOpen`).
  const mine = (front.sections || []).filter((one) => one.slug && boardOpen(one, who, admin));
  // **A board is not a page of words.** It is read and changed with `board`
  // and `set_board`; words sent here would be written where nothing draws them.
  const aBoard = (slug) => (front.sections || []).find((one) => one.slug === slug && one.type === "board");
  if ((name === "page" || name === "set_page" || name === "set_source") && aBoard(slugFrom(args.slug || args.page || args.name || ""))) {
    throw refuse("That page is a board. Read it with `board` and change it with `set_board`.");
  }

  if (name === "pages") {
    const stored = new Set(
      (await listAll(env, keys.pages(found.project))).map((o) => o.key.split("/").pop().replace(/\.json$/, ""))
    );
    const said = [...BUILT_IN.entries()].map(([slug, called]) => ({
      page: called,
      address: `https://your-domain.example/f/${found.project}/${slug}`,
      slug,
      made_by: "the record itself",
      you_may: "add to it with set_page",
    }));
    // **The Script page is the film's** (SL-1338): its newest draft, drawn
    // from the drafts taken in on the Mac. Listed when there is one.
    if ((front.scripts || []).length) said.unshift(scriptSaid(found, front));
    for (const one of mine) {
      if (BUILT_IN.has(one.slug)) continue;
      said.push({
        page: one.name,
        address: `https://your-domain.example/f/${found.project}/${one.slug}`,
        slug: one.slug,
        made_by: one.type === "board" ? "a board — read it with `board`, change it with `set_board`" : one.by === "deck" ? "Deck Editor" : one.by === "mcp" ? "an agent or the portal" : "Notion",
        // **The source, not who made it, is what decides who writes.** Ref 871:
        // a page Notion made and he has taken a snapshot of is *his* now, and
        // saying "change it in Notion" of it would send an agent to a page that
        // no longer reaches the site.
        words_from: SOURCE_SAID[sourceOf(one)],
        // **Whether Notion names it at all**, which decides whether the two
        // Notion sources are even offerable. A page made on the portal has no
        // Hub-ticked row behind it and cannot be fed from Notion until one
        // exists.
        notion_names_it: one.notion !== false,
        you_may: mayDo(one),
        written: stored.has(one.slug),
      });
    }
    return JSON.stringify(said, null, 1);
  }

  // **The Library is read by everybody, filtered to what they may open** — the
  // same rules the sidebar and the pages apply. An editor sees the lot, with
  // each page's state.
  if (name === "library") {
    const visible = await visibleOf(env, found.project);
    const editor = found.role === "editor";
    const empties = new Set(unfilled(front, visible));
    const rows = LIBRARY_BUILT.concat(mine.filter((s) => !BUILT_IN.has(s.slug) && !LIBRARY_BUILT.some((b) => b.slug === s.slug)).map((s) => ({ slug: s.slug, name: s.name, type: s.type })));
    const pages = rows
      .filter((r) => maySee(visible, "sections", r.slug, found.role) && !empties.has(r.slug))
      .map((r) => ({
        page: r.name, slug: r.slug,
        address: `https://your-domain.example/f/${found.project}/${r.slug}`,
        ...(r.type ? { kind: r.type } : { kind: "built in" }),
        shelf: shelfOf(front, r.slug, r.name, "page", r.type || ""),
        ...(editor ? {
          pinned: !offSidebar(front, r.slug),
          archived: isArchived(front, r.slug),
          icon: (front.icons || {})[r.slug] || "",
          private: (visible.sections || []).includes(r.slug),
        } : {}),
      }));
    const docs = maySee(visible, "sections", "documents", found.role)
      ? (front.documents || []).filter((d) => maySee(visible, "documents", d.name, found.role))
          .map((d) => ({ document: d.name, shelf: shelfOf(front, `doc:${d.name}`, d.name, "doc"), link: d.file ? `https://your-domain.example/f/${found.project}/file/${d.file}` : d.url,
            ...(editor ? { pinned: !offSidebar(front, `doc:${d.name}`), private: (visible.documents || []).includes(d.name), archived: isArchived(front, `doc:${d.name}`), icon: (front.icons || {})[`doc:${d.name}`] || "" } : {}) }))
      : [];
    return JSON.stringify({ film: found.title, shelves: shelfList(front).map((one) => ({ id: one.id, name: one.name, ...(one.builtIn ? {} : { added: true }) })), pages, documents: docs }, null, 1);
  }

  // **Reading is not changing, so this sits above the gate.** A viewer may open
  // the Visual Bible in a browser; refusing to let them read the same words
  // through the MCP would be a rule that exists nowhere else.
  if (name === "page" && slugFrom(args.slug || args.page || "") === "script") {
    const visible = await visibleOf(env, found.project);
    if (!maySee(visible, "sections", "script", found.role)) throw refuse("That page is not shown to you.");
    if (!(front.scripts || []).length) throw refuse("This project has no script yet. A draft arrives by Import Script on the Mac.");
    return JSON.stringify({ film: found.title, ...scriptSaid(found, front) }, null, 1);
  }

  if (name === "page") {
    const slug = slugFrom(args.slug || args.page || "");
    const one = mine.find((s) => s.slug === slug);
    if (!slug || (!one && !BUILT_IN.has(slug))) throw refuse(`No page at ${slug || "that address"}. Ask for \`pages\`.`);
    const visible = await visibleOf(env, found.project);
    // The same refusal the page itself gives. A section hidden from somebody is
    // hidden here too, or the MCP is a way round the panel.
    if (!maySee(visible, "sections", slug, found.role)) throw refuse("That page is not shown to you.");
    const tree = await pageOf(env, found.project, slug);
    return JSON.stringify({
      film: found.title,
      page: one ? one.name : BUILT_IN.get(slug),
      slug,
      address: `https://your-domain.example/f/${found.project}/${slug}`,
      written_by: one ? (one.by === "deck" ? "Deck Editor" : one.by === "mcp" ? "an agent or the portal" : "Notion") : "the record itself",
      words_from: one ? SOURCE_SAID[sourceOf(one)] : "the record itself",
      you_may: one ? mayDo(one) : "read it",
      markdown: tree && tree.length ? markdownFrom(tree) : "",
    }, null, 1);
  }

  if (found.role !== "editor") throw refuse("Only an editor may change a project's pages.");

  /**
   * **The Library**, the same one he has on the portal: every page and
   * document, with the sidebar a pinned subset of it. The rules live in
   * `setOnSidebar` and `setArchived` in `front.js`, so this and the portal's
   * forms cannot disagree about where a page goes back to.
   */
  if (name === "move_to_shelf") {
    const id = shelfIdFor(front, args.shelf);
    if (!id) throw refuse(`The shelves are ${shelfNames(front).join(", ")}.`);
    const shelf = shelfList(front).find((one) => one.id === id).name;
    const docName = String(args.document || "").trim();
    if (docName) {
      if (!(front.documents || []).some((d) => d.name === docName)) throw refuse(`No document called ${docName}. Ask for \`library\`.`);
      setShelf(front, `doc:${docName}`, shelf, docName, "doc");
      await saveFront(env, found.project, front);
      return `${docName} is on the ${shelf} shelf.`;
    }
    const slug = slugFrom(args.slug || args.page || "");
    if (!slug || !libraryKnown(slug, mine)) throw refuse(`No page at ${slug || "that address"}. Ask for \`library\`.`);
    const sec = mine.find((one) => one.slug === slug);
    setShelf(front, slug, shelf, libraryName(slug, mine), "page", sec ? sec.type : "");
    await saveFront(env, found.project, front);
    return `${libraryName(slug, mine)} is on the ${shelf} shelf.`;
  }
  if (name === "edit_shelves") {
    const said = editShelves(front, { action: args.action, shelf: args.shelf, name: args.name, to: args.to, ids: args.ids });
    if (!said.ok) throw refuse(said.why || "Could not change that shelf.");
    await saveFront(env, found.project, front);
    return JSON.stringify({ film: found.title, done: String(args.action), shelves: shelfList(front).map((one) => ({ id: one.id, name: one.name, ...(one.builtIn ? {} : { added: true }) })) }, null, 1);
  }
  if (name === "set_icon") {
    const icon = String(args.icon || "").trim();
    if (icon && !ICON_CHOICES.includes(icon)) throw refuse(`The icons are ${ICON_CHOICES.join(", ")}.`);
    const docName = String(args.document || "").trim();
    let key = "";
    let label = "";
    if (docName) {
      if (!(front.documents || []).some((d) => d.name === docName)) throw refuse(`No document called ${docName}. Ask for \`library\`.`);
      key = `doc:${docName}`; label = docName;
    } else {
      key = slugFrom(args.slug || args.page || "");
      if (!key || !libraryKnown(key, mine)) throw refuse(`No page at ${key || "that address"}. Ask for \`library\`.`);
      label = libraryName(key, mine);
    }
    setIcon(front, key, icon);
    await saveFront(env, found.project, front);
    return icon ? `${label} now wears the ${icon} icon.` : `${label} is back to its default icon.`;
  }
  if (name === "archive_page" && String(args.document || "").trim()) {
    // **A document (a file or a link) is archived the same way a page is**, by name.
    const docName = String(args.document).trim();
    if (!(front.documents || []).some((d) => d.name === docName)) throw refuse(`No document called ${docName}. Ask for \`library\`.`);
    if (typeof args.archived !== "boolean") throw refuse("Say `archived`: true to archive it, false to unarchive it.");
    const visible = await visibleOf(env, found.project);
    setArchived(front, `doc:${docName}`, args.archived, visible);
    await saveFront(env, found.project, front);
    await saveVisible(env, found.project, { ...visible, version: 1 });
    return args.archived
      ? `${docName} is in the Library's Archive: private, and off the Documents page. It is not deleted.`
      : `${docName} is out of the Archive, back on the Documents page as it was.`;
  }
  if (name === "set_on_sidebar" && String(args.document || "").trim()) {
    const docName = String(args.document).trim();
    if (!(front.documents || []).some((d) => d.name === docName)) throw refuse(`No document called ${docName}. Ask for \`library\`.`);
    const pinned = typeof args.pinned === "boolean" ? args.pinned : args.on;
    if (typeof pinned !== "boolean") throw refuse("Say `pinned`: true to pin it to the sidebar, false to unpin it.");
    setOnSidebar(front, `doc:${docName}`, pinned);
    await saveFront(env, found.project, front);
    return pinned
      ? `${docName} is pinned to ${found.title}'s sidebar${isArchived(front, `doc:${docName}`) ? ", though it is still archived, so it stays off until it is unarchived" : ""}. It opens the document.`
      : `${docName} is unpinned from ${found.title}'s sidebar. It is still on the Documents page and in the Library.`;
  }
  if (name === "set_on_sidebar" || name === "archive_page") {
    const slug = slugFrom(args.slug || args.page || "");
    if (!slug || !libraryKnown(slug, mine)) throw refuse(`No page at ${slug || "that address"}. Ask for \`library\`.`);
    const label = libraryName(slug, mine);
    if (name === "set_on_sidebar") {
      const pinned = typeof args.pinned === "boolean" ? args.pinned : args.on;
      if (typeof pinned !== "boolean") throw refuse("Say `pinned`: true to pin it to the sidebar, false to unpin it.");
      setOnSidebar(front, slug, pinned);
      await saveFront(env, found.project, front);
      return pinned
        ? `${label} is pinned to ${found.title}'s sidebar${isArchived(front, slug) ? ", though it is still archived, so it stays off until it is unarchived" : ""}.`
        : `${label} is unpinned from ${found.title}'s sidebar. It is still in the Library and opens at its address.`;
    }
    if (typeof args.archived !== "boolean") throw refuse("Say `archived`: true to archive it, false to unarchive it.");
    // Archiving also makes the page private, which lives in Visibility.
    const visible = await visibleOf(env, found.project);
    setArchived(front, slug, args.archived, visible);
    await saveFront(env, found.project, front);
    await saveVisible(env, found.project, { ...visible, version: 1 });
    return args.archived
      ? `${label} is in the Library's Archive: unpinned and private. It still opens for an editor at its address.`
      : `${label} is out of the Archive, ${offSidebar(front, slug) ? "still unpinned" : "pinned again"}, in its old place.`;
  }

  if (name === "remove_page") {
    const slug = slugFrom(args.slug || args.page || "");
    const one = mine.find((s) => s.slug === slug);
    if (!one) throw refuse(`No page at ${slug || "that address"}. Ask for \`pages\`.`);
    // **Asked of Notion, not of who wrote it.** A page Notion names comes
    // straight back at the next refresh, so removing it would look like it
    // worked and quietly undo itself within the hour. Anything Notion does not
    // name is his — including a deck, which the portal also lets him remove.
    if (one.notion !== false) {
      throw refuse(`${one.name} is named in Notion, so Notion is where it goes. Untick its \`Hub\` box there.`);
    }
    if (one.by === "deck") {
      throw refuse(`${one.name} is a deck, and its design was tuned by hand. Remove it on the page itself if that is really what he wants.`);
    }
    front.sections = mine.filter((s) => s.slug !== slug);
    front.rail = (front.rail || []).filter((r) => r !== slug);
    forgetMoves(front, slug);
    await env.BUCKET.delete(keys.page(found.project, slug));
    // **A designed page keeps its document beside the tree**, and leaving it
    // behind would make the next page of that name wear the old deck's design.
    await env.BUCKET.delete(keys.pageHtml(found.project, slug));
    front.updated = new Date().toISOString();
    await saveFront(env, found.project, front);
    return `${one.name} is off ${found.title}.`;
  }

  /**
   * **Where a page's words come from, set from here too.** His instruction,
   * 2026-09-08: *"any AI using the MCP should be able to do any of the things
   * that I can do here."* This is the control at the foot of the page.
   *
   * Deliberately its own tool rather than an argument on `set_page`: handing a
   * page back to Notion is a thing you do *without* rewriting it, and an
   * argument would have made the two inseparable.
   */
  if (name === "set_source") {
    const slug = slugFrom(args.slug || args.page || "");
    const one = mine.find((s) => s.slug === slug);
    if (!one) throw refuse(`No page at ${slug || "that address"}. Ask for \`pages\`.`);
    const wanted = String(args.source || "").trim();
    if (!PAGE_SOURCES.includes(wanted)) {
      throw refuse("A source is `notion`, `notion-once` or `here`.");
    }
    if (sourceOf(one) === "program") {
      throw refuse(`${one.name} is a deck — its words come from Deck Editor. Change them there and publish.`);
    }
    // **Notion cannot be pointed at a page it does not name**, and saying it
    // could was the fault he reported on 2026-09-08: the label changed and the
    // words never came. `notion` on the section is written by `refresh.py`, the
    // only thing on this side of the wire that can know.
    if (wanted !== "here" && one.notion === false) {
      throw refuse(
        `Nothing in Notion names ${one.name}. Tick \`Hub\` on a Project Docs row there and set its \`Section\` to “${one.name}”, then it can be fed from Notion.`
      );
    }
    one.source = wanted;
    front.sections = mine;
    front.updated = new Date().toISOString();
    await saveFront(env, found.project, front);
    return `${one.name}: ${SOURCE_SAID[wanted]}.${
      wanted === "notion" ? " Notion writes it again from the next refresh, replacing what is there." : ""
    }`;
  }

  if (name === "rename_document") {
    const visible = await visibleOf(env, found.project);
    const got = renameDocument(front, visible, String(args.document || ""), String(args.name || ""));
    if (!got.ok) throw refuse(got.why);
    if (got.touched) await saveVisible(env, found.project, visible);
    await saveFront(env, found.project, front);
    return `${args.document} is now ${got.name} under Documents on ${found.title}.`;
  }

  if (name === "rename_page") {
    const slug = slugFrom(args.slug || args.page || "");
    const one = mine.find((s) => s.slug === slug);
    if (!one) throw refuse(`No page at ${slug || "that address"}. Ask for \`pages\`.`);
    const called = String(args.name || "").replace(/\s+/g, " ").trim().slice(0, 60);
    if (!called) throw refuse("Say what to call it.");
    const others = new Set([
      ...BUILT_IN.values(), "Shot List", "Locations", "Schedule", "Mood Boards", "Reference Images", "Add",
      ...mine.filter((s) => s.slug !== slug).map((s) => s.name).filter(Boolean),
    ].map((n) => String(n).toLowerCase()));
    if (others.has(called.toLowerCase())) throw refuse(`${called} is already a page on this project.`);
    const was = one.name;
    one.name = called;
    front.sections = mine.map((s) => (s.slug === slug ? one : s));
    // A page Notion names: the portal's name over Notion's, address kept.
    if (one.notion) front.labels = { ...(front.labels || {}), [slug]: called };
    // **The address follows the name**, as on the portal (`movePage`); the
    // old one forwards. A deck keeps its address: Deck Editor publishes by it.
    const at = one.type !== "deck" && !one.notion ? await movePage(env, found.project, front, await visibleOf(env, found.project), slug, slugFrom(called)) : slug;
    front.updated = new Date().toISOString();
    await saveFront(env, found.project, front);
    return at === slug
      ? `${was} is now ${called}. Its address, your-domain.example/f/${found.project}/${slug}, has not changed.`
      : `${was} is now ${called}, at your-domain.example/f/${found.project}/${at}. The old address, /${slug}, forwards there.`;
  }

  /**
   * **The order of the rail**, which he sets by dragging and an agent sets by
   * saying. The headings are the categories (2026-10-11), so a row under a
   * heading is filed in that category (`arrangeRail` in `front.js`).
   */
  if (name === "arrange") {
    const rows = (list) => (Array.isArray(list) ? list : []).map((one) => String(one || "").trim()).filter(Boolean);
    if (!Array.isArray(args.groups) && !Array.isArray(args.order)) {
      throw refuse("Send `groups` — the categories and what is under each — or `order` for one plain list.");
    }
    const asked = Array.isArray(args.groups)
      ? args.groups.map((one) => ({ name: String((one && one.name) || "").trim(), rows: rows(one && one.rows) }))
      : [{ name: "", rows: rows(args.order) }];
    if (Array.isArray(args.groups)) {
      const info = new Map(mine.map((one) => [one.slug, { name: one.name, type: one.type }]));
      const why = arrangeRail(front, asked, (at) => info.get(at) || {});
      if (why) throw refuse(why);
    } else {
      applyOrder(front, asked[0].rows);
    }
    await saveFront(env, found.project, front);
    // **Say back what actually took**, because `tidy` drops anything that is
    // not a row address and a silent drop is how an agent thinks it has
    // arranged a rail it has not touched.
    const took = new Set((await frontOf(env, found.project)).rail);
    const lost = asked.flatMap((g) => g.rows).filter((one) => !took.has(one));
    const said = asked.map((g) => `${g.name ? `${g.name}: ` : ""}${g.rows.filter((one) => took.has(one)).join(", ") || "nothing"}`).join(" · ");
    return `${found.title} — ${said}.${
      lost.length ? ` Not an address on this project, so dropped: ${lost.join(", ")}.` : ""
    } Anything not named stays at the end of its category.`;
  }

  // ---- set_page ----------------------------------------------------------
  const called = String(args.name || "").replace(/\s+/g, " ").trim();
  if (!called) throw refuse("Say what the page is called.");
  const asked = slugFrom(args.slug || called);
  if (!asked) throw refuse(`\`${called}\` does not make an address. Pass a \`slug\` — lower case, hyphens, no spaces.`);
  if (INSTEAD.has(asked)) throw refuse(INSTEAD.get(asked));
  if (TAKEN.has(asked)) throw refuse(`\`${asked}\` is already an address on this project. Give the page another name.`);
  // **The bible or the spec sheet, however it was spelled.** See `FOLDS`.
  const slug = FOLDS.get(asked) || asked;

  // **A page Notion made can be taken over, and taking it over is the point.**
  //
  // His decision, 2026-09-04, made the film's page the *source* for a bible
  // rather than a copy of one — so an agent has to be able to write it. His own
  // Call Her Back bible came from Notion, and under the old rule the very thing
  // he asked for was refused: Notion AI could read that page and never change
  // it.
  //
  // Taking over is not destructive. Notion still holds its page; what stops is
  // the portal copy being overwritten from it (`both_roads`, and `refresh.py`
  // leaves an agent's page alone). To hand it back, untick `Hub` in Notion and
  // tick it again, or `remove_page` and refresh.
  const standing = mine.find((s) => s.slug === slug);
  const cameFromNotion = Boolean(standing) && !standing.by;
  // **A category that is not there is refused before anything is written.**
  const underName = String(args.category || args.heading || "").replace(/\s+/g, " ").trim().slice(0, 40);
  const heading = underName ? shelfIdFor(front, underName) : "";
  if (underName && !heading && !standing) {
    throw refuse(`No category called ${underName}. Ask for \`library\` to see them, or \`edit_shelves\` to add one.`);
  }
  if (!standing && mine.length >= MOST_PAGES) {
    throw refuse(`That project already carries ${mine.length} pages, which is as many as it holds. Remove one first.`);
  }

  // **A page may arrive already designed.** His decision, 2026-09-05: one deck
  // design makes the PDF and the web page, so a deck publishes a finished
  // document rather than words for the portal to style. `pageHtmlOf` already
  // prefers that document over the tree when both are there — what was missing
  // is any way to *make* the row, so a deck could only ever re-skin a page that
  // Notion had already created. Publishing a new one wrote a file nobody could
  // reach and said it had worked.
  const designed = typeof args.html === "string" && args.html.trim().length > 0;

  /**
   * **An address with nothing at it yet**, which is the one thing the portal's
   * Add screen could do and this could not. His instruction, 2026-09-08: *"any
   * AI using the MCP should be able to do any of the things that I can do
   * here."*
   *
   * **`deck` is the case with a reason.** A published deck needs a row and an
   * address to land on — before `/add` existed, publishing a new one wrote a
   * file nobody could reach and reported success. An agent asked to set a film
   * up for a look book should be able to make that slot.
   *
   * **Asked for explicitly, never inferred.** A body and no `type` is a page
   * with words; no body and no `type` stays refused, because that is far more
   * often an agent that forgot its `markdown` than one that meant this.
   */
  const bare = String(args.type || "").trim();
  const empty = !designed && !String(args.markdown || "").trim();
  if (empty && bare !== "page" && bare !== "deck") {
    throw refuse("There is nothing on that page. Send it as Markdown in `markdown`, as a finished document in `html`, or pass `type` to make the address and nothing else.");
  }
  // **Making a bare address over a page that exists would silently reassign
  // it** — a `type: "deck"` on his Notion bible would take it off Notion and
  // stamp it a deck, writing nothing and saying it had worked.
  if (empty && mine.some((one) => one.slug === slug)) {
    throw refuse(`\`${slug}\` is already a page on this project. Send words to rewrite it, or \`set_source\` to change where its words come from.`);
  }

  // **A deck's design is not something plain words may land on top of.** He
  // said it plainly of his Call Her Back bible: he does not want to lose it. An
  // agent rewriting a deck page in Markdown would replace a design he tuned by
  // hand with a styled paragraph, and the deck folder would have no idea.
  if (!designed && !empty && standing && standing.by === "deck") {
    throw refuse(
      `\`${slug}\` is a deck — its design is written in Deck Editor, and Markdown here would replace it. Change it there and publish, or send the finished document in \`html\`.`
    );
  }

  let tree = [];
  let dropped = [];
  if (empty) {
    // Nothing is written; only the row below is made.
  } else if (designed) {
    if (args.html.length > MAX_DOC) {
      throw refuse("That document is too big. Keep it under two megabytes — the pictures live on the project, not in the page.");
    }
    await env.BUCKET.put(keys.pageHtml(found.project, slug), args.html, {
      httpMetadata: { contentType: "text/html; charset=utf-8" },
    });
  } else {
    ({ tree, dropped } = pageFrom(args.markdown));
    if (!tree.length) throw refuse("There is nothing on that page. Send it as Markdown in `markdown`.");
    const body = JSON.stringify(tree);
    if (body.length > MAX_PAGE) throw refuse("That page is too long. Split it in two, or pin the file under Documents.");
    await env.BUCKET.put(keys.page(found.project, slug), body, {
      httpMetadata: { contentType: "application/json; charset=utf-8" },
    });
  }

  // **The name on the rail is the name he reads, and the built-in four keep
  // theirs.** A page folded onto the Visual Bible is drawn under the film's own
  // paragraphs; renaming that row from here would rename a page of the record.
  //
  // **A name may change; an address may not.** The slug is made from the name
  // the first time and kept afterwards, because he sends these links to
  // directors and a rename that moved the address would break one already sent.
  const row = {
    slug,
    name: BUILT_IN.get(slug) || called.slice(0, 60),
    title: String(args.subtitle || "").replace(/\s+/g, " ").trim().slice(0, 140),
    by: designed || (empty && bare === "deck") ? "deck" : "mcp",
    // **Said outright, because it is now the thing that decides who writes.**
    // Ref 871: `refresh.py` used to ask *who wrote last* (`by`), so an agent
    // touching a page locked Notion out of it for good. It asks the source now,
    // and the source is changeable on the page itself — so this records what is
    // true (the words are written here) without it being a one-way door.
    source: designed || (empty && bare === "deck") ? "program" : "here",
    /**
     * **Taking a page over does not take it off Notion's list.** The row keeps
     * whether Notion names it, so a page an agent rewrote can still be handed
     * back — which is the whole of Ref 871. Deriving this from `by` would say
     * *no* the moment an agent touched a Notion page, and the way back would
     * close again silently.
     *
     * A brand new row is one nothing in Notion has ever named. If he ticks
     * `Hub` there later, the next refresh says so and the choice appears.
     */
    notion: standing
      ? (typeof standing.notion === "boolean" ? standing.notion : !standing.by)
      : false,
  };
  front.sections = standing ? mine.map((s) => (s.slug === slug ? row : s)) : [...mine, row];
  // **In a category, as adding from a heading's + does.** Only a page that is
  // new: an existing one keeps the place he gave it.
  let filedUnder = "";
  if (!standing && heading) {
    setShelf(front, slug, heading, called, "page", row.type || "");
    filedUnder = shelfIdFor(front, heading) && (shelfList(front).find((one) => one.id === heading) || {}).name || underName;
  }
  front.updated = new Date().toISOString();
  await saveFront(env, found.project, front);

  const what = empty
    ? (bare === "deck"
        ? "an address for Deck Editor to publish into, with nothing at it yet"
        : "an address with nothing at it yet")
    : designed
      ? "a finished document, with its own design"
      : `${tree.length} block${tree.length === 1 ? "" : "s"}`;
  return `${row.name} is up at your-domain.example/f/${found.project}/${slug} — ${what}${
    standing ? ", rewritten" : ""
  }${filedUnder ? `, under ${filedUnder}` : ""}.${
    cameFromNotion ? " That page came from Notion and is now written here; a refresh will no longer overwrite it." : ""
  }${dropped.length ? ` Dropped: ${dropped.join("; ")}.` : ""}`;
}

/**
 * A picture from an address, stored at the size it has there. A Drive link is
 * turned into its download address first (the page address answers with a
 * sign-in screen), and falls back to Drive's own 2400px preview, which is the
 * best a file shared a little less openly will give. Null when nothing comes.
 */
async function fetchPictureFile(env, project, where) {
  const drive = driveIdOf(new URL(where));
  if (!drive) return pictureInto(env, project, where);
  return (
    (await pictureInto(env, project, `https://drive.google.com/uc?export=download&id=${drive}`)) ||
    (await pictureInto(env, project, `https://drive.google.com/thumbnail?id=${drive}&sz=w2400`))
  );
}

/** How many photographs the film itself holds. Documents are stored apart, so
 *  this stays a count of pictures rather than a count of everything. */
async function countPictures(env, project) {
  const pictures = new Set(["png", "jpg", "jpeg", "heic", "webp", "gif"]);
  return (await listAll(env, keys.media(project))).filter((o) =>
    pictures.has(o.key.split(".").pop().toLowerCase())
  ).length;
}

/** Store one file by its own contents, the same bargain every picture strikes. */
async function storeFile(env, project, args) {
  const extension = String(args.filename || "").split(".").pop().toLowerCase();
  if (!DOC_EXTENSION.has(extension)) throw refuse(`Cannot put a .${extension || "?"} on the page.`);

  const base64 = String(args.base64 || "").replace(/\s+/g, "");
  if (!base64) throw refuse("Send the file as base64.");
  if (base64.length > MAX_UPLOAD) throw refuse("That is over about 6 MB. Put it in Drive and pass a link instead.");

  let bytes;
  try {
    const binary = atob(base64);
    bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  } catch {
    throw refuse("That did not decode as base64.");
  }

  return storeBytes(env, project, extension, bytes);
}

/**
 * Store one file by its own contents.
 *
 * **Split out so the portal's own Add screen can use it** (Ref 872). A file
 * chosen in a browser arrives as bytes on a form and never as base64, and a
 * second copy of the hashing would be a second answer to *what is this file
 * called* — which is the one thing every picture and every document on a film
 * agrees on.
 */
export async function storeBytes(env, project, extension, bytes) {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  const file = `${hash.slice(0, 32)}.${extension}`;

  await env.BUCKET.put(keys.doc(project, file), bytes, {
    httpMetadata: { contentType: MIME_OF[extension] || "application/octet-stream" },
  });
  return { file, bytes: bytes.length };
}

/** Enough of a guess to make a browser open it rather than download it. */
const MIME_OF = {
  pdf: "application/pdf", png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg",
  webp: "image/webp", heic: "image/heic", gif: "image/gif", txt: "text/plain; charset=utf-8",
  csv: "text/csv; charset=utf-8", md: "text/markdown; charset=utf-8", mp4: "video/mp4",
  mov: "video/quicktime",
};

// ------------------------------------------------------- driving the engine

/**
 * Bring a film up and ask it one thing.
 *
 * **Everything, every time — or from where the last request left it.** A
 * worker keeps nothing between requests, so the film is rebuilt before every
 * question: from every log, or from the state the last request saved and
 * only the logs that grew since (`feed`, in `live.js`). Either way it has
 * heard everything already in the bucket, which is what makes a change
 * written here sort *after* all of it rather than being dropped as stale
 * (`engine::stamp`, and Ref 339 for the shape of the bug when a device has
 * not heard). The road taken is left on `held` for the reply's header.
 */
/**
 * **The project's card over the film** (studiocards.js, stage 5 step 4 piece
 * A): with its switch on, what the connector reads, exports and draws shows
 * the record's title, credits, mark and kind. Nothing is written. Quiet on
 * any failure: the film's own words then show.
 */
async function cardOver(env, project, x) {
  try {
    const { liveCardFor } = await import("./studiocards.js");
    const card = await liveCardFor(env, project);
    if (!card) return;
    const { layCard } = await import("./studiocardsfilm.js");
    layCard(x, card);
  } catch (error) {
    console.error("could not lay the card on:", String(error));
  }
}

async function run(env, found, held, call, ctx) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());

  const device = deviceFor(held.email);
  begin(x, found.project, found.title, found.role !== "editor", device);
  held.road = await feed(env, found.project, ctx, x);
  await cardOver(env, found.project, x);

  const reply = JSON.parse(
    ask(x, { jsonrpc: "2.0", id: 1, method: "tools/call", params: call })
  );

  const pending = take(x, x.pending_log());
  if (pending) await keep(env, found.project, device, pending, ctx);

  if (reply.error) throw refuse(reply.error.message || "That did not work.");
  const content = (reply.result && reply.result.content) || [];
  const said = content.map((c) => c.text).join("\n");
  return said || "Done.";
}

/**
 * **The film as the board's browser reads it** — the engine's `view`, the
 * same description `public/board.js` asks its own copy of the engine for.
 * Read only: nothing is written, so no change log is kept.
 */
async function filmView(env, found, ctx) {
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());
  begin(x, found.project, found.title, true, "0000000000000001");
  await feed(env, found.project, ctx, x);
  await cardOver(env, found.project, x);
  const text = take(x, x.view());
  return text ? JSON.parse(text) : {};
}

/**
 * **Mark a shot Shot from the portal** — the one thing a browser writes into
 * a film. His ruling, 2026-09-22: the portal is the on-set reader, and a
 * reader that cannot say "we got this" sends him back to the app for one
 * tap. It goes through the same door an AI's `update_shot` does: the film is
 * rebuilt from every log, the strike is one change, and it is kept as a log
 * of this person's own device (`deviceFor`), so the Mac and the phone take
 * it in as they take in anything. An editor only; the worker has said no to
 * everyone else before this is reached.
 */
export async function markShot(env, project, who, ctx, number, done) {
  const role = await roleFor(env, project, who);
  if (role !== "editor") throw refuse("You may look at this project, not change it.");
  const found = { project, title: await titleOf(env, project), role };
  // **Signed as the person, not as "[object Object]".** `who` is the whole
  // sign-in record; until 2026-09-25 it was handed in where an address was
  // wanted, so every strike from the portal came from one and the same device.
  const held = { email: (who && who.email) || String(who || "") };
  return await run(env, found, held, {
    name: "update_shot",
    arguments: { shot: String(number), shot_done: Boolean(done) },
  }, ctx);
}

/** A place no day's run reaches: the engine reads it as the end (Ref 1575). */
const PAST_THE_END = 100000;

/**
 * **Move a shot in a day's shooting order, from the portal's Schedule** —
 * his ask, 2026-10-05, after the Mac's Shooting Order: the same drag here.
 * The connector's own `schedule_shot` with `position`, so the portal, the
 * Mac and an AI make the one change the one way: onto `day` (its id or
 * `Day 3`) at `position` (1 first; none given, the end of the day), or off
 * every day with `day` of "" (Ref 1570), kept as a log of this person's
 * device. An editor only.
 */
export async function orderShot(env, project, who, ctx, { shot, day, position }) {
  const role = await roleFor(env, project, who);
  if (role !== "editor") throw refuse("You may look at this project, not change it.");
  const found = { project, title: await titleOf(env, project), role };
  const held = { email: (who && who.email) || String(who || "") };
  // **No place named is the end of the day**, as the Mac's Day menu and the
  // phone's put a shot (`shootbefore`, end of day); and a day of "" takes the
  // shot off its day. A place past the last is the last (Ref 1575), so "the
  // end" is simply a place no day reaches. The shot joins as it joins, then
  // takes that place.
  const arguments_ = { shots: [String(shot)], day: String(day) };
  if (String(day)) arguments_.position = position ? Number(position) : PAST_THE_END;
  return await run(env, found, held, { name: "schedule_shot", arguments: arguments_ }, ctx);
}

/**
 * **Add a picture or clip to a shot, from a board** — the second thing a
 * browser writes into a film. His question, 2026-09-25: a still laid on a
 * shot on a board, should it go to that shot in Shotlister too? Yes, but only
 * when he asks — a board is for playing around. The file is already in the
 * bucket under the relay's name for it (the worker put it there); the engine
 * adds the file by its hash, reusing one the film already holds, puts a use of
 * it on the shot, and the change is kept as this person's own log, exactly as
 * `markShot`'s is. An editor only.
 *
 * `asked` is `{shot, hash, name, size, caption}`.
 */
export async function attachToShot(env, project, who, ctx, asked) {
  const role = await roleFor(env, project, who);
  if (role !== "editor") throw refuse("You may look at this project, not change it.");
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());
  const device = deviceFor((who && who.email) || String(who || ""));
  begin(x, project, await titleOf(env, project), false, device);
  await feed(env, project, ctx, x);
  const [ptr, len] = put(x, JSON.stringify(asked));
  const out = x.attach(ptr, len);
  x.dealloc(ptr, len);
  const said = JSON.parse(take(x, out));
  const pending = take(x, x.pending_log());
  if (pending) await keep(env, project, device, pending, ctx);
  if (said.error) throw refuse(said.error);
  return said.ok || "Done.";
}

/**
 * **Diagram edits from the Diagrams page** — the portal drawing, not only
 * looking (his goal, 2026-09-29: the portal's diagram does everything the
 * app's does). The page makes each edit on its own copy of the film at once
 * and sends a batch here; the engine makes them again on the film as kept,
 * in order, and they land as one change log in this person's name, exactly
 * as `markShot`'s does — so his Mac and phone take them in the ordinary way.
 * An editor only.
 *
 * `asked` is `{scene, ops: [{op, made}]}`; the answer says which of the
 * page's ids for new pieces became which of the film's (`renamed`).
 */
export async function diagramEdit(env, project, who, ctx, asked, viaLink) {
  // **A link the owner opened for editing** (`diagram.settings.json`, checked
  // by the worker before it gets here) has no person to look up: the worker
  // names the visitor, and each browser gets a device of its own below.
  if (!viaLink) {
    const role = await roleFor(env, project, who);
    if (role !== "editor") throw refuse("You may look at this project, not change it.");
  }
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(seed());
  const device = deviceFor((who && who.email) || String(who || ""));
  begin(x, project, await titleOf(env, project), false, device);
  await feed(env, project, ctx, x);
  const [ptr, len] = put(x, JSON.stringify(asked));
  const out = x.diagram_edits(ptr, len);
  x.dealloc(ptr, len);
  const said = JSON.parse(take(x, out));
  const pending = take(x, x.pending_log());
  if (pending) await keep(env, project, device, pending, ctx);
  if (said.error) throw refuse(said.error);
  return said;
}

/**
 * **A new shoot, for Projects Console** (SL-1402, its New Shoot, R116). The
 * console never writes a film; its shot-list step asks this, through
 * `POST /console/<film>/shoot`, and it is the connector's own `new_shoot`
 * run exactly as a chat's call is (`run`): the film brought up from every
 * log in the bucket, the version, section, day and pickups made as one
 * change log in the console's own name, and his Mac and phone told. A
 * preview, or a shoot already set up, changes nothing and keeps no log.
 * A refusal is thrown with the tool's own sentence.
 *
 * `asked` is `{date, name, section?, pickups?, version?, preview?}`; the
 * answer is the tool's JSON with the film's title in front.
 */
export async function consoleShoot(env, project, ctx, asked) {
  const portal = await filmlessPortal(env, project);
  if (portal) throw refuse(notAFilm(portal.title));
  const found = { project, title: await titleOf(env, project), role: "editor" };
  const said = await run(env, found, { email: "projects-console" }, { name: "new_shoot", arguments: asked }, ctx);
  return { film: found.title, ...JSON.parse(said) };
}

/**
 * What a film's tool says on a portal with no film. His words, near enough,
 * from SL-1376: where to go instead, and nothing about why.
 */
function notAFilm(title) {
  return `${title || "This project"} has no Studio side yet, only its portal. Use set_page for a portal page, or turn a mode on with \`modes\` to make its Studio side.`;
}

/** What opening a portal says, in place of a film's summary. */
function portalOpened(title) {
  return [
    `Opened ${title}. It is a portal with no Studio side yet.`,
    "Its pages work: front, set_front, add_document, pages, page, set_page, rename_page, rename_document, remove_page, set_source, arrange, library, set_on_sidebar, archive_page, move_to_shelf, edit_shelves, set_icon, deck, set_deck, and the board tools.",
    "Scenes, shots, locations, days and plans need its Studio side: `modes` turns a mode on, which makes it.",
  ].join("\n");
}

/** Put a new change log in the bucket, and tell his devices it is there. */
async function keep(env, project, device, text, ctx) {
  // **Never into a portal with no film** (SL-1376). Every road that writes a
  // film's change ends here — the connector, a shot struck on the portal, a
  // still sent to a shot from a board, a plan drawn on the Diagrams page — so
  // this is the one place that has to say no. A log put here would make the
  // relay, the shelf and the rail argue about what the project is.
  const portal = await filmlessPortal(env, project);
  if (portal) throw refuse(notAFilm(portal.title));
  const name = `${device}-${randomHex(16)}.log`;
  await env.BUCKET.put(keys.log(project, name), text, {
    httpMetadata: { contentType: "text/plain; charset=utf-8" },
  });
  // **After the write, never before** — the relay learned this the hard way. A
  // device told to sync before the bytes are readable fetches the old state and
  // is never told again.
  if (!env.ROOMS) return;
  try {
    const room = env.ROOMS.get(env.ROOMS.idFromName(project));
    const said = room.fetch("https://rooms/said", {
      method: "POST",
      body: JSON.stringify({ what: "logs" }),
    });
    if (ctx && ctx.waitUntil) ctx.waitUntil(said);
    else await said;
  } catch (error) {
    // A room that cannot be reached costs a few minutes, not an edit: his Mac
    // and his phone find the log on their next look either way.
    console.error("could not tell the room:", String(error));
  }
}

/**
 * What this person's writes are signed as.
 *
 * **One device per person, not one per worker.** Two collaborators writing
 * through the hub in the same second must not look like one device to the
 * engine — that is exactly the shape of Ref 339, where one edit is dropped as
 * a duplicate of the other. FNV-1a over the address, the same function the Mac,
 * the phone, the bridge and the stdio MCP all use, so nothing here invents a
 * second way of naming a device.
 */
function deviceFor(email) {
  let hash = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(`hub/mcp/${String(email).toLowerCase()}`)) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return hash.toString(16).padStart(16, "0");
}

/** Random, and small enough to survive the trip across as a double. */
function seed() {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);
  let value = 0;
  for (const byte of bytes) value = value * 256 + byte;
  return value;
}

function ask(x, message) {
  const [ptr, len] = put(x, JSON.stringify(message));
  const out = x.handle(ptr, len);
  x.dealloc(ptr, len);
  return take(x, out);
}

// ------------------------------------------------------------------ the pages

function frontDoor(url) {
  return html(
    `<main class="card">
      <p class="brand">Nathaniel Regier Studio</p>
      <h1>Studio for AI</h1>
      <p class="line">Add this address to an AI app as a connector.</p>
      <p class="addr"><code>${esc(origin(url))}</code></p>
    </main>`,
    "Studio for AI"
  );
}

/** The site an app sends you back to, read from the address it registered. */
function siteOf(address) {
  try {
    return new URL(address).host;
  } catch {
    return "";
  }
}

/**
 * Who is asking, what it gets, and who is signed in — then two buttons.
 *
 * **Only the words and the look live here.** The form still posts `grant`
 * (the signed note) and `answer` (`yes` or `no`), and nothing else; what is
 * checked, signed and stored is `authorize` above and is not touched.
 * `hub/checks.sh` asserts the fields.
 */
function consent(granted, client, grant, url) {
  const name = esc((client && client.client_name) || "An AI app");
  const site = siteOf(granted.ask.redirect_uri);
  const ask = granted.ask;
  // Back through this same sign-in, from the top, after Access forgets who he is.
  const again = `${origin(url)}/authorize?${new URLSearchParams({
    response_type: "code",
    client_id: ask.client_id,
    redirect_uri: ask.redirect_uri,
    state: ask.state,
    code_challenge: ask.code_challenge,
    code_challenge_method: ask.method,
  })}`;
  const switchTo = `${apexOrigin(url)}/cdn-cgi/access/logout?returnTo=${encodeURIComponent(again)}`;
  return html(
    `<main class="card" aria-labelledby="t">
      <p class="brand">Nathaniel Regier Studio</p>
      <h1 id="t">${name}</h1>
      <p class="line">wants to connect to Studio</p>
      ${site ? `<p class="line">Returns to <b>${esc(site)}</b></p>` : ""}
      <div class="can">
        <p class="cap">It will be able to</p>
        <ul>
          <li>Read every project you are part of</li>
          <li>Make changes in them, as you</li>
        </ul>
      </div>
      <p class="who">Signed in as <b>${esc(granted.email)}</b> <a href="${esc(switchTo)}">Switch account</a></p>
      <form method="post">
        <input type="hidden" name="grant" value="${esc(grant)}">
        <button class="allow" name="answer" value="yes">Allow</button>
        <button class="cancel" name="answer" value="no">Cancel</button>
      </form>
    </main>`,
    "Allow?"
  );
}

// ------------------------------------------------------------------ plumbing

function random(length) {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return base64urlBytes(bytes);
}

function randomHex(chars) {
  const bytes = new Uint8Array(chars / 2);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function base64url(text) {
  return base64urlBytes(new TextEncoder().encode(text));
}

function base64urlBytes(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unbase64url(text) {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/");
  return new TextDecoder().decode(Uint8Array.from(atob(padded), (c) => c.charCodeAt(0)));
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function problem(status, said) {
  return json({ problem: said }, status);
}

/**
 * The sign-in's pages, drawn with a stylesheet of their own.
 *
 * Same palette as `kit.css` / `hub.css` (the values are copied, light and
 * dark), but inline: this host serves no files, so a link to the apex's
 * stylesheet is a page that depends on a second request answering.
 */
const SIGNIN_CSS = `
:root{--ground:#F2F2F4;--card:#FFFFFF;--ink:#17171A;--ink2:#5A5A61;--ink3:#6E6E75;--rule:#E8E8EB;--chip:#D9D9DE;--accent:#0A6CE8;--on:#FFFFFF;--tint:rgba(10,108,232,.11)}
@media(prefers-color-scheme:dark){:root{--ground:#0E0E11;--card:#1E1E22;--ink:#EDEDF0;--ink2:#A0A0A8;--ink3:#8E8E96;--rule:#2E2E35;--chip:#3A3A40;--accent:#0A84FF;--on:#FFFFFF;--tint:rgba(10,132,255,.22)}}
*{box-sizing:border-box}
html{background:var(--ground);color-scheme:light dark}
body{margin:0;min-height:100vh;min-height:100dvh;display:flex;align-items:center;justify-content:center;padding:24px 16px;
 font:15px/1.45 -apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",sans-serif;color:var(--ink);-webkit-font-smoothing:antialiased}
.card{width:100%;max-width:400px;background:var(--card);border:1px solid var(--rule);border-radius:18px;padding:32px 28px 28px}
.brand{margin:0 0 20px;font-size:11px;font-weight:600;letter-spacing:.04em;text-transform:uppercase;color:var(--ink3)}
h1{margin:0;font-size:22px;line-height:1.25;font-weight:650;letter-spacing:-.01em;overflow-wrap:anywhere}
.line{margin:8px 0 0;color:var(--ink2);font-size:13px;overflow-wrap:anywhere}
.line b{font-weight:500;color:var(--ink)}
.addr{margin:16px 0 0}
code{display:block;padding:10px 12px;border-radius:9px;background:var(--ground);font:12px/1.4 ui-monospace,"SF Mono",Menlo,monospace;overflow-wrap:anywhere}
.can{margin-top:24px;padding-top:20px;border-top:1px solid var(--rule)}
.cap{margin:0 0 8px;font-size:11px;font-weight:600;color:var(--ink3);letter-spacing:.04em;text-transform:uppercase}
ul{margin:0;padding:0;list-style:none}
li{padding:6px 0 6px 22px;position:relative;font-size:15px}
li:before{content:"";position:absolute;left:3px;top:13px;width:5px;height:9px;border:solid var(--accent);border-width:0 2px 2px 0;transform:translateY(-4px) rotate(45deg)}
.who{margin:20px 0 0;padding-top:20px;border-top:1px solid var(--rule);font-size:13px;color:var(--ink2);overflow-wrap:anywhere}
.who b{font-weight:500;color:var(--ink)}
.who a{color:var(--accent);text-decoration:none;display:block;padding:6px 0 2px}
form{margin-top:20px;display:flex;flex-direction:column;gap:8px}
button{font:inherit;font-weight:600;min-height:48px;border-radius:12px;border:0;cursor:pointer;width:100%}
.allow{background:var(--accent);color:var(--on)}
.cancel{background:transparent;color:var(--ink2);font-weight:500}
.allow:hover{filter:brightness(1.08)}
.cancel:hover{background:var(--tint);color:var(--ink)}
a:focus-visible,button:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
.err h1{font-size:19px}
@media(max-width:480px){body{align-items:flex-start;padding-top:max(24px,env(safe-area-inset-top))}.card{padding:28px 22px 22px}}
`;

/** A page of the sign-in. */
function html(body, title, status = 200) {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)} · Studio</title>
<style>${SIGNIN_CSS}</style></head><body>${body}</body></html>`,
    { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } }
  );
}

/** Something went wrong: what, and the one next step. */
function page(status, title, said) {
  return html(
    `<main class="card err" role="alert">
      <p class="brand">Nathaniel Regier Studio</p>
      <h1>${esc(title)}</h1>${said ? `<p class="line">${esc(said)}</p>` : ""}
    </main>`,
    title,
    status
  );
}
