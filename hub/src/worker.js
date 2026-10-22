/**
 * The hub — where everybody who is not him opens a film.
 *
 * ## What it is for
 *
 * The relay is a private door: one password, his devices, no idea who is
 * speaking. That is right for sync and useless for people. This is the other
 * door — a director, a producer, an AD, each known by name, each allowed a
 * different amount.
 *
 * ## Three ways to be somebody, and only three
 *
 * 1. **Cloudflare Access.** A person types their email, Access sends a code,
 *    and every request afterwards carries a signed assertion saying who they
 *    are. We verify the signature ourselves rather than trusting the header:
 *    the header is only meaningful because Access put it there, and a worker
 *    that trusts an unverified one trusts anybody who can set a header.
 * 2. **A secret link.** A long unguessable key in the address, for the producer
 *    who needs one page once and should not be on a list. The key is stored
 *    **hashed** in the film, so the list of links leaking does not hand out
 *    access to anything.
 *
 *    An **invite link** is the other half of that idea and the one he actually
 *    wanted: opening it signs you in with whatever address you like, and *that
 *    address is then written onto the film* with the role the invite carried.
 *    His words, 2026-09-01: *"i sent someone a sign up link and they can use
 *    whatever email they want to sign in and add to the policy that way i dont
 *    need to go into cloudflare."*
 *
 *    This is why Cloudflare's own policy is set once and never touched again:
 *    it lets **anybody** ask for a code, and knowing an address is real is all
 *    it is asked to do. Who that address may see is the film's business, and
 *    the film is where it is written.
 * 3. **`HUB_DEV_EMAIL` in `.dev.vars`.** Local checking only, and refused the
 *    moment the worker is not running on localhost.
 *
 * ## Where a person's rights live
 *
 * In the film — `p/<project>/people.json` — not in this worker and not in a
 * Cloudflare dashboard. That is his ruling, 2026-09-01: he sets who may do what
 * from the Mac, the iPhone or the web, none of them the master. A thing that
 * lives inside the film syncs like everything else in the film, so all three
 * can write it and the change merges like any other.
 *
 * ## The rule that is enforced here and nowhere else
 *
 * **A viewer's write is refused by the server.** Not hidden in the page — a
 * page can be edited by whoever is looking at it. Everything that changes a
 * film goes through `mustEdit`, and there is exactly one of those.
 */

import { closedMark } from "./step6shelf.js";
import { specPills, colourIndex } from "./specpills.js";
import { withTiming } from "./timing.js";
import { onceEach, warm } from "./once.js";
import { EMAIL, PROJECT, RESERVED, SHORT, pageHtmlOf, emptyPeople, everyFilm, filmBySlug, filmsFor, manyFilms, listAll, owners, peopleOf, peopleWithTag, savePeople, roleFor, sha256Hex, slugOf, titleOf, isAdmin, visibleOf, saveVisible, emptyVisible, emptyMine, movePage, renameDocument, forgetMoves, maySee, meSees, downOf, saveDown, portalOf, savePortal, hasFilm, everyPortal, filmlessPortal, strayLogs, filmOfShort, shortOf, ensureShort, claimShort, generalKeyOf, fileNameOf, boardOpen, sectionsFor } from "./films.js";
import { boardIn, publishedBoard, boardKeys, boardMarkup, boardSection, newBoard, saveBoard, roomOf, fetchInto, keepBytes, extensionFor, MOST_PICTURE, MOST_CLIP, fileOnShot, boardVersions, postersOwed } from "./boards.js";
import { SHARES } from "./front.js";
import { stayGone } from "./deletedguard.js";
import { serveMcp, mcpSignIn, MCP_HOST_PREFIX, storeBytes, DOC_EXTENSION , markShot, orderShot, attachToShot, diagramEdit, consoleShoot } from "./mcp.js";
import { coversOf } from "./covers.js";
import { ICON_CHOICES } from "./icons.js";
import { frontOf, saveFront, pinnedDocs, setOnSidebar, setArchived, isArchived, setShelf, setIcon, shelfIdFor, shelfList, shelfIdOf, editShelves, arrangeRail, PAGE_SOURCES, shotView, shootIn, filmBase, leadShoot, shotListCount, everyone } from "./front.js";
import { opsProblem } from "../public/boardpatch.js";
export { BoardRoom } from "./boardroom.js";
import { carryPortal } from "./carry.js";
import { keepLinkEdit, listLinkEdits, markLinkEdit, linkMayWrite } from "./linkedits.js";
import { byProjectId, oneIdOn, resolveProject, addIds, notionOf, keyOfPage } from "./projectid.js";
import { writeFacts } from "./facts.js";
import { studioDoor } from "./studio.js";
import { viewsOf, viewByKey, viewByCode, codeIn, viewSaid, viewPath, makeView, changeView, removeView, lensView } from "./views.js";
import { notionReady, refreshFilm } from "./notion.js";
import { pageFrom, MAX_PAGE } from "./paper.js";
import { rebuildPage } from "./rebuild.js";
import { treeFromHtml } from "./unhtml.js";
import { followTick, setFollow, followStateOf, driveReady } from "./docfollow.js";
import { slugFrom } from "./paper.js";
import { printDeck } from "./press.js";
// **Where everything sits in the bucket — `relay/layout.json`, named once.**
// The relay writes it and this reads it; neither spells a path itself.
import { keys, names, poster } from "../../relay/layout.js";

/**
 * One section's Notion page, as the tree `refresh.py` left in the bucket.
 *
 * **Kept out of `front.json` on purpose.** A visual bible is forty pictures and
 * fifteen thousand words, and every page of the portal reads the card; carrying
 * a bible inside it would make the film's own page slower for the sake of a
 * page nobody has opened yet. Read only when that section is asked for, and an
 * absent or unreadable one draws as empty rather than as an error — the section
 * is still listed, and "nothing on this page yet" is the honest thing to say
 * while the next refresh runs.
 */
async function pageOf(env, project, slug) {
  if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) return null;
  const got = await env.BUCKET.get(keys.page(project, slug));
  if (!got) return null;
  try {
    const tree = await got.json();
    return Array.isArray(tree) ? tree : null;
  } catch {
    return null;
  }
}
import { changeListing, changesOf } from "./since.js";
import { APP_ROWS, railDocs, railEdit, sidebarPicks, decksBody, groupsBody, libraryBody, libraryCount, coverWants, homeBody, newPageBody, recordBody, shelfBody, visibilityBody, visibilityChecks, visibilityForm, viewersSeeOf, libraryStateOf, sidebarStateOf, phoneLibraryOf, phoneFrontOf, freshLine, filmIconSvg, unfilled, scriptFileName } from "./pages.js";
import { bodyOf, editorBody, stylesOf } from "./editor.js";
// **What a link's key looks like** (`LINK_KEY`) and the rules for changing who
// may open a film without a browser, kept in one place for the connector and
// the Projects Console's door.
import { LINK_KEY, Refusal, changeAccess, generalLink } from "./access.js";
// **The kit door** (Ref 1627): a film's spec sheets as Shotlister's picks, and its edits.
import { kitDoor } from "./kit.js";

/**
 * The unlisted-link host.
 *
 * **His model, 2026-09-01:** a project is shared by an unlisted link that needs
 * no sign-in at all, optionally behind a password; anybody who wants to *edit*
 * signs up instead. Both are his to hand out.
 *
 * That first half cannot live at the apex, because Cloudflare Access stands in
 * front of it and answers a stranger with a sign-in page — which is precisely
 * what an unlisted link is meant to avoid. So links are served from a host of
 * their own with no Access on it, the same trick the MCP uses and for the same
 * reason.
 *
 * **Do not put an Access application on this hostname.** Doing so turns every
 * link he has sent into a sign-in prompt, which is the one thing he asked this
 * not to be.
 */
const SHARE_HOST_PREFIX = "share.";

/**
 * Which name this request came in under. It decides whether the hub answers or
 * the MCP does, so it is worth being exact about.
 *
 * **The Host header, not `url.hostname`** — behind a custom domain they agree,
 * and in front of one they need not.
 *
 * **And `x-hub-host` in a local run only.** `wrangler dev` serves every
 * route from one port and rewrites Host to the first pattern in
 * `wrangler.toml`, so a local request for the MCP arrives calling itself the
 * hub and the whole of it would be unreachable in checking. The header is
 * honoured only where `HUB_DEV_EMAIL` is set — that lives in `.dev.vars`, which
 * is gitignored and which wrangler never uploads, so a deployed hub has no such
 * var and cannot be told it is somewhere it is not.
 */
function hostAsked(request, url, env) {
  if (env && env.HUB_DEV_EMAIL) {
    const said = request.headers.get("x-hub-host");
    if (said) return said.toLowerCase();
  }
  return String(request.headers.get("host") || url.host).toLowerCase();
}

// The relay's own shapes, from the one layout file both workers read.
const LOG_NAME = names.log;
const MEDIA_NAME = names.medium;

/** What to serve a picture as. A browser will not play a clip handed to it as octet-stream. */
const MIME = {
  png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif",
  heic: "image/heic", webp: "image/webp", mp4: "video/mp4", mov: "video/quicktime",
  m4v: "video/x-m4v", usdz: "model/vnd.usdz+zip", pdf: "application/pdf",
  // A scanned room's other half — the walls and openings `engine::room` reads
  // to draw a floor plan. It is stored as media like everything else, and a
  // browser handed it as octet-stream will still read it; saying what it is
  // costs nothing and stops the next person wondering.
  json: "application/json",
  // A deck's own typefaces, put on the film by `publish.py` so the editor's
  // sheets are set in the same face the print is.
  ttf: "font/ttf", otf: "font/otf", woff: "font/woff", woff2: "font/woff2",
};

/**
 * The app's four modes, as four addresses.
 *
 * All one page — `film.js` draws every mode — but a tile on a film's page
 * has to point somewhere, and `/f/<id>/locations` is a better thing to be
 * sent by somebody than `/f/<id>#locations`. The mode rides in on `window.HUB`
 * with everything else, so the first paint already knows which one it is.
 */
/**
 * The app's four modes, by the names an address uses.
 *
 * `shotlist` rather than `shots` in a link, because `your-domain.example/
 * callherback/shotlist` is a thing somebody can read out loud. `shots` still
 * works — it is what every link written before this said.
 */
/** The pages of the record, and what each is called. */
const RECORD_PAGES = new Map([
  ["script", "Script"],
  ["bible", "Visual Bible"],
  ["camera", "Camera Spec Sheet"],
  ["people", "People"],
  ["documents", "Documents"],
]);

const MODES = {
  shotlist: "shots",
  shots: "shots",
  locations: "locations",
  boards: "boards",
  schedule: "schedule",
  diagrams: "diagrams",
};

/**
 * **The program's tabs by the names the rail gives them**, keyed by the
 * address a link to one carries. A pasted link to Locations unfurls as
 * *Locations — the film*, on a card that names the page, the same as the
 * record's pages do. Mirrored in `refresh.py`, which draws those cards.
 */
const PROGRAM_PAGES = new Map([
  ["shotlist", "Shot List"],
  ["locations", "Locations"],
  ["boards", "Reference Images"],
  ["schedule", "Schedule"],
  ["diagrams", "Diagrams"],
]);

const MAX_PEOPLE = 256 * 1024;

/**
 * The deploy this page came from, on the end of every asset address.
 *
 * **`must-revalidate` is not the same as "the browser will ask".** These files
 * are served `max-age=0, must-revalidate` and browsers still reuse what they
 * hold from memory inside a session — which is why a deploy could land and the
 * page look exactly as it did, twice in one evening, on my machine and on his.
 * A different deploy is a different address, so there is nothing to reuse.
 */
let BUILD = "0";

export default {
  async fetch(request, env, ctx) {
    if (env.BUILD && env.BUILD.id) BUILD = env.BUILD.id.slice(0, 8);
    const stamped = await keptForGood(request, env);
    if (stamped) return stamped;
    try {
      // **Timed** (`timing.js`): where a page's wait goes, said on every answer.
      // **Each small file once, a page's reads together** (`once.js`).
      return await withTiming(request, env, async (watched) => remember(request, await route(request, byProjectId(onceEach(watched)), ctx)));
    } catch (error) {
      console.error(error && error.stack ? error.stack : String(error));
      return page(500, "Something went wrong", "Try again.");
    }
  },
  /**
   * **The portal's own clock** (`[triggers]` in `wrangler.toml`), one handler
   * for two schedules, told apart by `event.cron`:
   *
   * - every two minutes, pages that follow a Google Doc look at their doc
   *   (`docfollow.js`), with the Mac asleep or off, and pictures that changed
 *   are copied to the project's Drive folder (`drivecopiesdoor.js`, its switch);
   * - every minute, the Notion link (`timer.js`, 2026-10-11), once the switch
   *   says the hub keeps Notion in step — until then a look every ten minutes
   *   that writes nothing.
   */
  async scheduled(event, env0, ctx) {
    // A minted project's record read by its Notion page (projectid.js).
    // **A deleted project stays gone** (deletedguard.js): no clock writes
    // under a prefix Delete took away.
    const env = stayGone(byProjectId(env0));
    const said = (error) => console.error(error && error.stack ? error.stack : String(error));
    if (event.cron === "* * * * *") {
      ctx.waitUntil(import("./timer.js").then(({ onTimer }) => onTimer(env, event.scheduledTime)).catch(said));
      return;
    }
    ctx.waitUntil(followTick(env).catch(said));
    // Drive copies of pictures (drivecopiesdoor.js): off until thrown; one read when off.
    ctx.waitUntil(import("./drivecopiesdoor.js").then(({ sweep }) => sweep(env, ctx)).catch(said));
    // Notion's Frame Guides follow the sheets' frames (framescopy.js): off until thrown.
    ctx.waitUntil(import("./framescopy.js").then(({ sweep }) => sweep(env, event.scheduledTime)).catch(said));
    // The Camera Spec Sheet as a Google Sheet in each project's Drive folder (specsheetsheetdoor.js): off until thrown.
    ctx.waitUntil(import("./specsheetsheetdoor.js").then(({ sweep }) => sweep(env, ctx)).catch(said));
  },
};

/** The addresses under a film that are not pages, and so are not warmed (`once.js`). */
const NOT_A_PAGE = new Set(["api", "pic", "media", "fso", "file", "drive", "order", "refresh", "join", "follow", "select"]);

/**
 * **A file stamped with this deploy is the same bytes for ever — say so.**
 *
 * Every page asks for its stylesheets and scripts as `/hub.css?v=<build>`.
 * Cloudflare serves static files `max-age=0, must-revalidate`, so every page
 * load asked the server about each one again and waited on a round trip
 * before it could draw — his *"improve load speeds between pages"*, 2026-09-30.
 * A stamped address changes with every deploy, so the browser may keep it
 * without asking. Only the current stamp: an old one might be answered with
 * new bytes, and those must not be kept under the old name.
 *
 * `run_worker_first` in `wrangler.toml` sends these few files through here;
 * anything unstamped — a font a stylesheet names, the service worker — is
 * served exactly as before.
 */
async function keptForGood(request, env) {
  if ((request.method !== "GET" && request.method !== "HEAD") || !env.ASSETS) return null;
  const url = new URL(request.url);
  if (!/^\/[a-z-]+\.(js|css)$/.test(url.pathname) || url.pathname === "/sw.js") return null;
  const answer = await env.ASSETS.fetch(request);
  if (answer.status === 404) return null;             // not a file: the routes below may know it
  if (!answer.ok) return answer;                      // a 304 is a fine answer as it stands
  if (url.searchParams.get("v") !== BUILD || BUILD === "0") return answer;
  const headers = new Headers(answer.headers);
  headers.set("cache-control", "private, max-age=31536000, immutable");
  return new Response(answer.body, { status: answer.status, headers });
}

/**
 * Keep a link's key, once it has been used.
 *
 * **Without this a secret link opens the page and nothing else.** The key is in
 * the address of the *page*; the page then asks for the film's change logs at
 * addresses of their own, which carry no key, so every one of them arrives
 * anonymous and the film never loads. The page looked fine and was useless —
 * found the first time one was tried against the live hub.
 *
 * So the first request that carries a key hands back a cookie, and everything
 * after it is recognised without the address having to say so. It also means a
 * reload works, and that the key can be taken out of the address bar later
 * without locking the person out.
 */
function remember(request, response) {
  // **A short name is a key the address never shows.** `/hla` let this
  // person in on the film's general link, so the cookie is handed back just
  // as if the key had been on the address — the program inside the portal
  // asks for the film's logs at `/f/<id>/api/…`, which carries neither.
  const key = new URL(request.url).searchParams.get("k") || request.shortKey || "";
  const wants = key && LINK_KEY.test(key) && response.status < 400;
  const out = new Response(response.body, response);
  if (wants) {
    out.headers.append(
      "set-cookie",
      `hubkey=${encodeURIComponent(key)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`
    );
  }
  // Said on every answer, including the MCP's host, which has no sign-in in
  // front of it and so is the one a crawler could actually reach.
  out.headers.set("x-robots-tag", "noindex, nofollow, noarchive, noimageindex");
  return out;
}

async function route(request, env, ctx) {
  const url = new URL(request.url);

  // **The MCP has a host of its own, and that is the whole reason it works.**
  //
  // Cloudflare Access sits in front of `your-domain.example` and answers an
  // unsigned-in request with a sign-in page. That is exactly right for a person
  // and useless for a program: an AI asking this worker a question would be
  // handed HTML asking it to check its email. So the MCP lives on
  // `mcp.your-domain.example`, which has no Access application in front of
  // it and does its own asking — and when it needs to know who somebody is, it
  // sends their *browser* to the apex, where Access does know.
  //
  // The alternative was several bypass rules in his Cloudflare dashboard, each
  // one a click he would have to get right and none of them visible from here.
  // **The Host header, not `url.hostname`.** Behind a custom domain the two
  // agree; in front of `wrangler dev` they do not — a local run arrives calling
  // itself localhost whatever was asked for, and the whole of this would be
  // unreachable in checking.
  const host = hostAsked(request, url, env);

  // **The Projects Console's door**, on every host — see `consoleDoor`. Before
  // the MCP split on purpose: the apex has Cloudflare Access in front of it,
  // which hands a program a sign-in page, so the console calls this on the
  // MCP's host, where nothing stands in front of the worker but the token.
  if (url.pathname === "/console" || url.pathname.startsWith("/console/")) {
    return await consoleDoor(request, env, url, ctx);
  }

  // **The portal's own pages, inside the iPhone app** — see `phoneWeb`.
  if (url.pathname.startsWith("/phone/web/")) {
    return await phoneWeb(request, env, url, ctx, host);
  }

  // **The iPhone app's door** — see `phoneDoor`. Every host, for the same
  // reason as the console's: a program cannot pass the apex's sign-in.
  if (url.pathname.startsWith("/phone/")) {
    return await phoneDoor(request, env, url, ctx, host);
  }
  if (url.pathname.startsWith("/kit/")) return await kitDoor(request, env, url, ctx, { carriesToken, hasFilm, portalOf, json, problem });

  // **Which deploy this is**, on every host and with nobody signed in. The
  // apex has Access in front of it, so a program asks on the MCP's host, the
  // way the console does. It reveals a commit hash and a date, nothing else.
  //
  // `COMMIT` and `DEPLOYED` are vars stamped by `hub/deploy.sh` on the
  // deploy — never read from git here, a Worker has none. A hub put up any
  // other way says `unknown`. `hub/drift.sh` compares this to `main`.
  if (url.pathname === "/version") {
    return json({
      hub: "shotlister",
      commit: env.COMMIT || "unknown",
      deployed: env.DEPLOYED || null,
      build: env.BUILD && env.BUILD.id ? env.BUILD.id.slice(0, 8) : null,
    });
  }

  if (host.startsWith(MCP_HOST_PREFIX)) {
    return await serveMcp(request, env, url, ctx, host);
  }

  const parts = url.pathname.split("/").filter(Boolean);
  const sharing = host.startsWith(SHARE_HOST_PREFIX);

  // **Nothing here is for the open web.** His instruction, 2026-09-01: the
  // domain must not be exposed to search or public discovery. Two things,
  // because one is not enough — a crawler that ignores robots.txt still reads
  // the header, and a crawler that never asks for robots.txt still gets it.
  //
  // Worth knowing and not worth hiding: the *name* is already public whatever
  // this says. Every certificate issued for a hostname is written to public
  // Certificate Transparency logs, which are searchable. What this stops is the
  // *contents* being indexed, and the address being found by a search engine
  // following links. It cannot unpublish the name.
  if (parts.length === 1 && parts[0] === "robots.txt") {
    return new Response("User-agent: *\nDisallow: /\n", {
      headers: { "content-type": "text/plain; charset=utf-8" },
    });
  }

  // **A page that says why nothing moved.** Twice now the movement between
  // pages has measured as working here and read as a hard cut on his own
  // machine, and both times the fault was in how it was being *looked at*
  // rather than in the page. Two things stop every animation on this site dead
  // and neither is visible from the code: a browser too old for the API, and
  // "Reduce motion" being on in macOS. This asks the browser both questions and
  // says the answers in words, so nobody has to guess again.
  if (parts.length === 1 && parts[0] === "motion") {
    return html(
      `<div class="fh2 shelf"><div class="shelfwrap">
        <h1>Movement</h1>
        <p class="sub">What this browser can do</p>
        <dl class="spec" id="report"></dl>
        <p class="note" id="verdict"></p>
        <p style="margin-top:22px"><button class="linkish" id="try"
           style="border:1px solid var(--line);padding:9px 16px;border-radius:999px">Try it</button></p>
        <div id="stage" style="margin-top:20px;height:120px;position:relative">
          <div id="block" style="position:absolute;top:0;bottom:0;left:0;right:50%;background:var(--card);
               border-radius:var(--r-card);display:grid;place-items:center;color:var(--quiet)">Press Try it</div>
        </div>
      </div></div>
      <script type="module">
        const can = typeof document.startViewTransition === "function";
        const cross = "CSSViewTransitionRule" in window;
        const quiet = matchMedia("(prefers-reduced-motion: reduce)").matches;
        const row = (label, value) =>
          \`<div class="specrow"><dt>\${label}</dt><dd>\${value}</dd></div>\`;
        document.getElementById("report").innerHTML =
          row("Smooth moves", can ? "Yes" : "No") +
          row("Between whole pages", cross ? "Yes" : "No") +
          row("Reduce motion", quiet ? "On" : "Off") +
          row("Browser", navigator.userAgent.match(/Chrome\\/[0-9]+|Version\\/[0-9.]+ Safari|Firefox\\/[0-9]+/)?.[0] || "unknown");
        document.getElementById("verdict").textContent = quiet
          ? "Reduce motion is on in your Mac's settings, and it switches off every animation on every website. System Settings, Accessibility, Display, Reduce motion."
          : can
          ? "Nothing here is stopping it. Press Try it — if the block below slides, the moves work."
          : "This browser cannot do the smooth version. It will still change pages, just without the movement.";
        document.getElementById("try").addEventListener("click", () => {
          const block = document.getElementById("block");
          // **It has to travel, or the test is worthless.** The first version of
          // this only changed colour, so a working transition looked like a
          // colour change and told him nothing. This crosses the whole box.
          const swap = () => {
            const over = !block.dataset.on;
            block.textContent = over ? "It moved" : "Press Try it";
            block.style.background = over ? "var(--accent, #D44C47)" : "var(--card)";
            block.style.color = over ? "#fff" : "var(--quiet)";
            block.style.left = over ? "50%" : "0";
            block.style.right = over ? "0" : "50%";
            block.dataset.on = over ? "1" : "";
          };
          if (!document.startViewTransition) {
            swap();
            block.classList.add("camein");
            setTimeout(() => block.classList.remove("camein"), 500);
            return;
          }
          block.style.viewTransitionName = "tryblock";
          document.startViewTransition(swap);
        });
      </script>`,
      "Movement",
      200,
      { front: true }
    );
  }

  // Answers without knowing anybody, so "is it up?" can be asked by anything.
  if (parts.length === 1 && parts[0] === "health") {
    // **`host` is here on purpose.** Which name a request arrived under decides
    // whether it is the hub's or the MCP's, and it is the first thing to look
    // at when one of them is answering for the other.
    return json({
      hub: "shotlister",
      version: 1,
      access: Boolean(env.ACCESS_TEAM && env.ACCESS_AUD),
      host: hostAsked(request, url, env),
    });
  }

  // On the share host nobody signs in. A key is the only thing that counts:
  // no Access assertion is read, and the checking identity is refused outright,
  // so this host cannot be talked into believing somebody is an editor.
  // **A short name, first.** `/hla` names a film (`shorts.json`), and on the
  // share host it stands for that film's general link: with no key on the
  // address, the person is let in exactly as if they had presented it. A key
  // on the address always wins — a password link or an expired one sent
  // under the short name is judged as itself, not as the general link.
  let short = null;
  if (parts.length && parts[0] !== "f" && !RESERVED.has(parts[0]) && SHORT.test(parts[0])) {
    const project = await filmOfShort(env, parts[0]);
    if (project) {
      short = { name: parts[0], project };
      if (request.method === "GET" && !NOT_A_PAGE.has(parts[1] || "") && !/\./.test(parts[1] || "")) warm(env, project);
    }
  }
  let who = sharing ? linkOnly(request, url) : await identify(request, env, url);
  // **A view link's address is its own key** (`views.js`): `/chb/v/crane-k7p2x9q4`
  // lets its holder in on that view and on nothing else, and the cookie it
  // hands back is the view's, so the shots' pictures that follow are theirs.
  // Asked before the general link, which `/chb` would otherwise stand for.
  const viewAt = sharing && parts[short ? 1 : 2] === "v"
    ? { project: short ? short.project : parts[1], segment: parts[short ? 2 : 3] }
    : null;
  if (viewAt && PROJECT.test(String(viewAt.project || "")) && codeIn(viewAt.segment)) {
    const found = await viewByCode(env, viewAt.project, viewAt.segment);
    if (found && !found.off) {
      who = { email: null, via: "link", key: found.key };
      request.shortKey = found.key;
    }
  } else if (sharing && short && !url.searchParams.get("k")) {
    const key = await generalKeyOf(env, short.project);
    if (key && LINK_KEY.test(key)) {
      who = { email: null, via: "link", key };
      request.shortKey = key;
    }
  }

  // **Who the hub thinks you are.** The first thing to look at when somebody
  // says they cannot see a film: almost always the answer is that Access knows
  // them by a different address than the one on the list.
  if (parts.length === 1 && parts[0] === "whoami") {
    return json(who ? { email: who.email, via: who.via } : { email: null, via: null });
  }

  // **The MCP's sign-in, and the only reason the apex is in it at all.**
  //
  // The MCP lives on a host with no Access application in front of it, so it
  // cannot know who anybody is. This page can: Access has already asked, and by
  // the time the request gets here the address is verified. All this does is
  // sign it onto the note the MCP host sent and send the browser back.
  if (parts.length === 1 && parts[0] === "mcp-signin") {
    if (!who) return needSignIn(env);
    const sent = await mcpSignIn(request, env, url, who, host);
    if (sent) return sent;
    return page(400, "Sign-in expired", "Sign in again.");
  }

  // **The press, fetching a picture for a print.** The portal's own Chrome has
  // no session, and every picture and typeface on a film needs one — so the
  // first print came out with every frame empty and set in Georgia. A print
  // mints a key, keeps it on the film for a few minutes, and sends it on every
  // request; the key opens pictures and nothing else, and is gone when the
  // print is. See `press.js`.
  const pressKey = request.headers.get("x-press");
  const picPath = parts[0] === "f" && parts.length === 4 && parts[2] === "pic" && PROJECT.test(parts[1]);
  // **A typeface is fetched cross-origin, and the key is a custom header.**
  // That makes Chrome ask first with OPTIONS — and the asking carries no key
  // of its own, only the name of the header it wants to send. So a preflight on
  // a picture path is answered for anybody: it serves nothing, it only says
  // which headers the real request may carry.
  const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "x-press",
                 "access-control-allow-methods": "GET, HEAD, OPTIONS", "access-control-max-age": "600" };
  if (picPath && request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (pressKey && picPath && /^[0-9a-f-]{16,64}$/.test(pressKey)) {
    const held = await env.BUCKET.get(keys.press(parts[1], pressKey));
    let until = 0;
    if (held) { try { until = Number((await held.json()).until) || 0; } catch { until = 0; } }
    if (until <= Date.now()) return page(404, "No such page", "");
    const served = await media(env, parts[1], parts[3], request, ["docs", "media"]);
    const opened = new Response(served.body, served);
    for (const [k, v] of Object.entries(cors)) opened.headers.set(k, v);
    return opened;
  }

  // **Never a sign-in page on the share host.** A link that has gone stale, or
  // an address somebody guessed at, is nothing there — not an invitation to
  // sign in to something, which would undo the point of the host.
  //
  // A short name whose film has no general link on stands for nothing: it
  // says so, as the bare name of a private film (2026-10-13, /zed and /joe).
  if (short) {
    const mark = await closedMark(env, short.project);
    if (mark) return page(410, mark.name || "Project", "This project is closed.");
  }
  if (!who && sharing && short && !viewAt) return page(404, "This film isn't shared", "");
  if (!who) return sharing ? page(404, "No such page", "") : needSignIn(env);

  if (parts.length === 0) return await landing(env, who, url);

  // **The shelf's list, for ⌘K** (`public/jump.js`, Ref 1161): each film this
  // person may open, by name and address, and nothing else. Somebody on a link
  // is not signed in to anything and has no shelf, so they get none.
  if (parts.length === 1 && parts[0] === "films.json") {
    if (who.via === "link") return json({ films: [] });
    const films = await filmsFor(env, who);
    return json({
      films: (films || []).map((f) => ({
        title: f.title,
        base: slugOf(f.title) ? `/${slugOf(f.title)}` : `/f/${f.project}`,
      })),
    });
  }

  // The hub's own manifest, for a page that is nobody's film — the shelf.
  if (parts.length === 1 && parts[0] === "manifest.webmanifest") {
    return new Response(JSON.stringify(manifestOf("Project Studio", "", "")), {
      headers: { "content-type": "application/manifest+json; charset=utf-8", "cache-control": "no-store" },
    });
  }

  // **The deck editor's own front page.** His correction, 2026-09-06: it should
  // be a hub of its own, not a door onto the film shelf. `Deck Editor.app`
  // opens here.
  if (parts.length === 1 && parts[0] === "decks") return await deckShelf(env, who);

  // **A film by its name, first.** `your-domain.example/callherback/shotlist`
  // is the address he asked for; `/f/<id>/…` is what everything written before
  // this says, and both reach the same place. A name resolves only for somebody
  // who may open that film, so guessing names tells a stranger nothing — on the
  // share host that means it resolves only for whoever holds the key.
  let project = null;
  let rest = [];
  let base = "";
  if (short) {
    project = short.project;
    rest = parts.slice(1);
    base = `/${short.name}`;
  } else if (parts[0] !== "f" && !RESERVED.has(parts[0])) {
    const found = await filmBySlug(env, who, parts[0]);
    if (!found) return page(404, "No such film", "");
    project = found.project;
    rest = parts.slice(1);
    base = `/${slugOf(found.title)}`;
  } else {
    if (parts[0] !== "f" || parts.length < 2) return page(404, "No such page", "");
    project = parts[1];
    if (!PROJECT.test(project)) return page(404, "No such film", "");
    // Closed (step6shelf.js): said before anything else about this address.
    {
      const mark = await closedMark(env, project);
      if (mark) return page(410, mark.name || "Project", "This project is closed.");
    }
    rest = parts.slice(2);
    base = `/f/${project}`;
    // **A project's own address.** `/f/<page id>` — the project's Notion id,
    // the one the console keys its record on — stands for the project from
    // birth. With a film attached the address goes straight to the film's
    // page, query and all, so a link keyed on the project keeps working
    // whatever film is attached to it; without one it is the record's own
    // page, for him. A film's relay id and a page id are the same shape, so
    // the record is what decides: a film has none, a project has one.
    //
    // **One ID** (projectid.js, switch `s/oneid.json`): the address serves
    // the project directly. A project whose Studio side lives under its own
    // ID — every new one, and a portal-only one once a mode is switched on —
    // is answered right here; an existing project's film keeps its own relay
    // id (an alias), so `/f/<page>` still goes there, but nothing is carried
    // on the way: there is one place a project's pages live, and one way to
    // find its record. A minted project's Notion page id, if anybody holds
    // one, goes to the project's ID.
    const oneId = PAGE.test(project) && (await oneIdOn(env)).on;
    if (oneId) {
      const found = await resolveProject(env, project);
      if (found.key && found.via === "notion") {
        const to = `${base.replace(project, found.key)}${rest.length ? "/" + rest.join("/") : ""}${url.search}`;
        return new Response(null, { status: 302, headers: { location: to } });
      }
    }
    const record = PAGE.test(project) ? await recordOf(env, project) : null;
    if (record) {
      const relay = record.film && record.film.relay;
      const here = relay === project && await hasFilm(env, project);
      if (oneId && relay && PROJECT.test(relay) && relay !== project) {
        const to = `${base.replace(project, relay)}${rest.length ? "/" + rest.join("/") : ""}${url.search}`;
        return new Response(null, { status: 302, headers: { location: to } });
      }
      if (here) {
        // The film is here, under the project's own ID: answered below.
      } else if (relay && PROJECT.test(relay) && relay !== project) {
        // **A portal made before the film is carried into it** — his ruling,
        // 2026-09-16: the pages move across and merge in. The record's
        // arrival does this (`recordDoor`); this is the same road taken on
        // the way past, for a record that beat the carry.
        await carryPortal(env, project, relay);
        const to = `${base.replace(project, relay)}${rest.length ? "/" + rest.join("/") : ""}${url.search}`;
        return new Response(null, { status: 302, headers: { location: to } });
      }
      // **A portal with no film behind it is the project's page, for
      // everyone it is shared with** — the console's ask, 2026-09-16. The
      // mark under the prefix (`portalOf`) is what turns the record's bare
      // page into the front of house; without it the record page stands,
      // for him alone, as before.
      if (!here && !(await portalOf(env, project))) {
        if (!isAdmin(env, who)) return page(403, "No Access", "");
        return html(projectRecordBody(record), record.name || "Project", 200, { dark: true });
      }
    }
  }

  // **A closed project** (step6shelf.js, Close Project, 2026-10-15): every
  // address it ever had keeps answering, and says so. Its pages are kept
  // behind this, never removed; Reopen Project takes the mark away.
  {
    const mark = await closedMark(env, project);
    if (mark) return page(410, mark.name || "Project", "This project is closed.");
  }

  // **One shoot of a film that shoots more than once** — SL-1396. Its own
  // address, `/shoots/<slug>/…`, carried in `base` so every link the pages
  // draw stays on that shoot; the rest of the address is answered exactly as
  // without it. Drawing reads `shootIn(base)` and lays the shoot over the
  // card (`shotView`); writes never see it.
  if (rest[0] === "shoots" && rest.length >= 2 && /^[a-z0-9][a-z0-9-]{0,40}$/.test(rest[1])) {
    base = `${base}/shoots/${rest[1]}`;
    rest = rest.slice(2);
  }

  // **Everything this film's page is about to ask for, asked at once**
  // (`once.js`): the helpers below each wait on their own read, and now find
  // it already on its way. **Pages only.** The program's own questions
  // (`/api/…`), its pictures and files need two or three of these, and the
  // rest would sit in the six open answers a request is allowed and make the
  // ones it does need wait — `/api/state` went from 0.3 s to 0.55 s.
  if (request.method === "GET" && !NOT_A_PAGE.has(rest[0] || "") && !/\./.test(rest[0] || "")) warm(env, project);

  // **Joining happens before the gate, and has to.** Somebody arriving on an
  // invite has no part in the film yet — that is the entire point of an invite
  // — so asking `roleFor` first would refuse every newcomer at the door.
  if (rest.length === 1 && rest[0] === "join") {
    return await join(request, env, project, who, url);
  }

  let role = await roleFor(env, project, who);
  if (!role) {
    if (sharing && short && !viewAt && request.shortKey) return page(404, "This film isn't shared", "");   // its general link is off
    return sharing
      ? page(404, "No such page", "")   // a wrong key on the share host is simply nothing
      : page(403, "No Access", "");
  }

  // **Read only, whatever the link says.** A link cannot carry the right to
  // change a film — that is what signing up is for — so this is forced here
  // rather than trusted from the list, and `mustEdit` refuses every write.
  if (sharing) role = "viewer";

  // **Down.** The console can take a film's page off without deleting the
  // film (`downOf`, 2026-09-15). Everyone who is not an editor gets one line
  // at every address under the film — the page, its sections, its own
  // requests, a link on the share host — and nothing else. An editor is let
  // through so he can look at what he is about to put back.
  if (role !== "editor" && (await downOf(env, project)).down) {
    return page(503, "This page is down", "");
  }

  // **Not Shared** (portalmodes.js, stage 5 step 5): the console's Shared
  // switch, off. The same one line to everyone but an editor, and no link
  // changed, so turning it back on opens every address already sent.
  if (role !== "editor") {
    const { notSharedOf } = await import("./portalmodes.js");
    if ((await notSharedOf(env, project)).notShared) return page(404, "This page isn't shared", "");
  }

  // **Read Visibility first, on a page**, so a page hidden For Me (retired) has
  // become unpinned (`retireMe` in `films.js`) before anything draws the rail.
  // The read is already on its way (`warm`), so this costs a wait, not a get.
  if (request.method === "GET" && !NOT_A_PAGE.has(rest[0] || "") && !/\./.test(rest[0] || "")) await visibleOf(env, project);

  // **The film's mark, as a file.** Served wherever the film itself is served
  // — the same permission, no separate rule — because a favicon nobody may see
  // is only ever asked for by a browser that is already showing the page.
  if (rest.length === 1 && rest[0] === "icon.svg") {
    const front = await frontOf(env, project, ctx);
    const svg = filmIconSvg(front);
    if (!svg) return new Response("", { status: 404 });
    return new Response(svg, {
      headers: { "content-type": "image/svg+xml; charset=utf-8", "cache-control": "public, max-age=600" },
    });
  }

  // **The same mark as a PNG** — for Safari's tab, and for the iPhone's home
  // screen, which draws PNG and nothing else. Drawn by `hub/cover.mjs` on a
  // refresh, beside the covers, for the same reason they are: a Worker cannot
  // rasterise. A film whose refresh has not run yet gets the product's mark,
  // which is a picture rather than a hole.
  if (rest.length === 1 && rest[0] === "icon.png") {
    const got = await env.BUCKET.get(keys.icon(project));
    if (got) {
      return new Response(got.body, {
        headers: { "content-type": "image/png", "cache-control": "public, max-age=600" },
      });
    }
    return env.ASSETS.fetch(new Request(new URL("/app-icon.png", url).href));
  }

  // **What the home screen is told.** The scope is the whole host, so a tap
  // on any page of any film stays inside the app — a page outside the scope
  // is what iOS opens in the browser-with-an-X he asked to be rid of. The
  // start is the film's own page, key and all, so the app opens where it was
  // added from and a link that needs a key still has it.
  if (rest.length === 1 && rest[0] === "manifest.webmanifest") {
    const title = await titleOf(env, project);
    const k = url.searchParams.get("k");
    const q = k ? `?k=${encodeURIComponent(k)}` : "";
    return new Response(JSON.stringify(manifestOf(title, base, q)), {
      headers: { "content-type": "application/manifest+json; charset=utf-8", "cache-control": "no-store" },
    });
  }

  // **The cover a pasted link unfurls into.** Drawn by `hub/cover.mjs` and kept
  // beside the film's other pictures, because a Worker cannot rasterise: there
  // is no canvas in one, and the alternative was a megabyte of type-setting
  // WebAssembly to draw six words.
  if (rest.length === 1 && rest[0] === "cover.png") {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    // **Fetched straight, not through `media`.** That helper guards against a
    // made-up filename by insisting on 32 hex characters and an extension —
    // right for anything a person can name, and wrong here, where the key is
    // fixed and the guard simply refuses the only file it can ever be.
    // **A page's own card, when one has been drawn.** `?page=bible` asks for
    // the Visual Bible's; a page nobody has drawn yet — added on the portal a
    // minute ago, ahead of the next refresh — falls back to the film's, which
    // is still true, just less specific.
    const slug = String(url.searchParams.get("page") || "");
    const got = (/^[a-z0-9-]{1,64}$/.test(slug)
      ? await env.BUCKET.get(keys.coverFor(project, slug))
      : null) || await env.BUCKET.get(keys.cover(project));
    if (!got) return new Response("", { status: 404 });
    return new Response(got.body, {
      headers: {
        "content-type": "image/png",
        "cache-control": "public, max-age=600",
        // A robot unfurling a link follows redirects but does not run scripts;
        // nothing here needs to be private to the page that named it.
        "access-control-allow-origin": "*",
      },
    });
  }

  // **A view link sees its view and nothing else** (`views.js`). Its holder
  // is let in by a key like any link's; what that key may open is decided
  // here, at the door, so no page, log or list of the film's answers it —
  // only the view's own page, the view's shots, and the pictures on them,
  // which are named by their contents and so cannot be guessed at.
  const lens = linkHeld(who) ? await viewByKey(env, project, who.key) : null;
  if (lens) {
    const short = await shortOf(env, project);
    const home = viewPath(lens, short, project);
    if (rest.length === 0) return new Response(null, { status: 302, headers: { location: home } });
    const mine = rest[0] === "v" && rest.length === 2 && codeIn(rest[1]) === lens.code;
    const asks = rest[0] === "api" && rest[1] === "view" && rest.length === 2;
    const looks = (rest[0] === "media" || rest[0] === "pic") && rest.length === 2;
    if (!mine && !asks && !looks) return page(404, "No such page", "");
  }

  // A link may carry a password. Until it is answered, the film is not served.
  //
  // **Below the mark and the cover, on purpose.** His ruling, 2026-09-19: a
  // locked link still unfurls into the film's card, so whatever fetches the
  // preview has to be given the picture before it has the password.
  if (sharing && who.via === "link") {
    const locked = await passwordWanted(env, project, who, request, url, ctx, base);
    if (locked) return locked;
  }

  // **A Released project's selects, as pictures** (portalselects.js): behind
  // this same door, and only an id the record lists among its selects.
  if (rest.length === 2 && rest[0] === "select" && (request.method === "GET" || request.method === "HEAD")) {
    const { releasedFor } = await import("./portalselects.js");
    const rel = await releasedFor(env, project);
    if (!rel || !rel.selects.includes(rest[1])) return new Response("", { status: 404 });
    const { stillBytes } = await import("./step6shelf.js");
    const got = await stillBytes(env, rest[1]);
    if (!got) return new Response("", { status: 404 });
    return new Response(request.method === "HEAD" ? null : got.body, { headers: { "content-type": got.type, "cache-control": "private, max-age=3600" } });
  }

  // **Front of house.** What used to be here was the shot list; the shot list
  // is one tool now, and this is the room before it.
  if (rest.length === 0) return await filmPage(env, project, role, who, url, base);


  if (rest.length === 1 && MODES[rest[0]]) {
    // **A hidden section of the program is refused at its address too.** The
    // rail not offering Locations is not the same as Locations being shut, and
    // the address is the half a person can type.
    const seen = await visibleOf(env, project);
    if (!maySee(seen, "sections", rest[0], role)) return page(404, "No such page", "");
    // **A portal with no film has no program to open.** The rail does not
    // offer these four, and the address is the half a person can type. The
    // same question the rail's card asks (`frontOf`), so the two can never
    // disagree again — SL-1376, when stray logs made the rail offer Schedule
    // and this refused it.
    if (await filmlessPortal(env, project)) return page(404, "No such page", "");
    return await viewerPage(env, project, role, who, MODES[rest[0]], base, seen, url);
  }

  // **A view link's page** (`views.js`): the Shot List, narrowed to one
  // filter by the server, with no other page of the film beside it. He can
  // open any of his views here to see what its holder sees.
  if (rest[0] === "v" && rest.length === 2) {
    const view = lens || (await viewByCode(env, project, rest[1]));
    if (!view || (view.off && role !== "editor")) return page(404, "No such page", "");
    if (await filmlessPortal(env, project)) return page(404, "No such page", "");
    return await viewerPage(env, project, role, who, "shots", base, emptyVisible(), url, view);
  }

  // **Which photograph stands for the film.** Editors only, and a plain form,
  // so it needs no JavaScript and no engine — every picture the film has ever
  // pushed is a fair answer to "which one is the film", and the bucket already
  // knows all of them.
  // **Share.** Its own address rather than a query on the film's, because it is
  // a thing somebody is sent to and comes back from. `?people=1` still works —
  // the viewer has linked to it since Stage 1 and a live link is worth more
  // than a tidy one.
  if (rest.length === 1 && rest[0] === "share") {
    // **A link holder is let in here too**, and is drawn a card holding one
    // thing: the address they are standing on, with their key on it. They
    // cannot change who may open the film and are not offered the chance — the
    // window decides that from what it was told, and every write is refused on
    // the share host whatever a page draws.
    if (!linkHeld(who)) {
      const stop = mustEdit(role);
      if (stop) return stop;
    }
    const [title, front] = await Promise.all([titleOf(env, project), frontOf(env, project, ctx)]);
    return html(
      // **Both of his addresses.** They are both him, and a window that offered
      // to demote one of them would be offering something the server refuses.
      `<div id="share"></div>${await sharePanel(env, project, title, role, who, base, front)}`,
      `Share · ${title}`,
      200,
      // Dark by ruling, like every page of the portal — this one followed the
      // system until 2026-09-15 and came up white for a link holder. The
      // film's card, so even this address unfurls into something.
      { dark: true, ...sharedAs(url, base, title, front, "share") }
    );
  }

  // **The record's own pages.** Each is a real address rather than a section of
  // one long page — his ruling, 2026-09-02: individual pages, and a rail that
  // cannot be scrolled past.
  // **Names this route must not swallow.** It used to match four fixed words;
  // now that a section can be called anything he types into Notion it matches
  // the *shape* of a name, and the first thing that did was eat `/crew` — which
  // is answered further down, and which six checks caught immediately. A route
  // that widens has to say what it still refuses.
  /**
   * **Who may see what — administrators only.**
   *
   * His instruction, 2026-09-04. The gate is `isAdmin`, not `role === "editor"`:
   * an editor may change the *film*, and only he may change what other people
   * are shown of it. A GET draws the panel; a POST saves it and comes straight
   * back, so the page needs nothing running.
   */
  if (rest.length === 1 && rest[0] === "visibility") {
    if (!isAdmin(env, who)) return page(403, "No Access", "");
    const [title, front, visible, mine] = await Promise.all([
      titleOf(env, project), frontOf(env, project, ctx), visibleOf(env, project), manyFilms(env, who),
    ]);
    // **The table on its own**, for the Visibility tab of the Share panel
    // (`public/share.js`, Ref 1153): the same form the page draws, without the
    // page around it, so the two can never be two layouts.
    const part = url.searchParams.get("part") === "1";
    // **Which tab comes back open** — the one he saved from, so For Me does
    // not jump back to On Links under him.
    const forMe = false; // For Me is retired (2026-10-03)
    // **`part=2` is the Share popover's checklist** (`visibilityChecks`): the
    // same data and the same save, drawn as a list of the sidebar.
    const checks = url.searchParams.get("part") === "2";
    const fragment = (v) => new Response((checks ? visibilityChecks : visibilityForm)(base, front, v, forMe), {
      headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
    });
    if (request.method === "POST") {
      const form = await request.formData();
      /**
       * **One switch, from a page's own menu.** Ref 1153: every page carries
       * Shown on Links for itself, which flips that one name and leaves every
       * other choice alone — a whole-form save from a menu would have had to
       * know the whole table. `back` is a page of this film, never anywhere
       * else.
       */
      const flip = String(form.get("flip") || "");
      if (flip) {
        const [kind, ...named] = flip.split(":");
        const key = named.join(":");
        /**
         * **Set, not flip, when it says which** (2026-10-11): the Library's
         * switches send `shown` (1 or 0) so a second press or a slow answer
         * can never turn a switch the wrong way, and ask for JSON so the page
         * stays put. Without `shown` this is the old flip, for the page menus.
         * `crew` and `contact` are a person by name: Crew in the Library.
         */
        const shownSaid = String(form.get("shown") || "");
        const json = (request.headers.get("accept") || "").includes("application/json");
        const backTo = () => {
          const back = String(form.get("back") || "");
          return /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : base;
        };
        const answer = (shown) => (json
          ? new Response(JSON.stringify({ ok: true, shown }), { headers: { "content-type": "application/json", "cache-control": "no-store" } })
          : new Response(null, { status: 303, headers: { location: backTo() } }));
        if (kind === "crew" || kind === "contact") {
          if (!everyone(front).some((one) => one.name === key)) return page(404, "No such person", `${key || "That"} is not on this film.`);
          // `crew` keeps who is hidden; `contact` keeps whose details are shown.
          const now = new Set(visible[kind] || []);
          const listed = shownSaid ? (kind === "crew" ? shownSaid !== "1" : shownSaid === "1") : !now.has(key);
          if (listed) now.add(key); else now.delete(key);
          await saveVisible(env, project, { ...visible, version: 1, [kind]: [...now] });
          return answer(kind === "crew" ? !listed : listed);
        }
        if (shownSaid && (kind === "sections" || kind === "documents")) {
          const show = shownSaid === "1";
          const onBoard = kind === "sections" && (front.sections || []).find((one) => one.type === "board" && one.slug === key);
          if (onBoard) {
            const want = show ? "link" : onBoard.share === "link" ? "crew" : onBoard.share;
            if (want !== onBoard.share) { onBoard.share = want; await saveFront(env, project, front); }
            return answer(show);
          }
          const known = kind === "documents" ? (front.documents || []).some((d) => d.name === key) : libraryKeys(front).has(key);
          if (!known) return page(404, "No such page", `${key || "That"} is not on this film.`);
          const now = new Set(visible[kind] || []);
          if (show) now.delete(key); else now.add(key);
          await saveVisible(env, project, { ...visible, version: 1, [kind]: [...now] });
          return answer(show);
        }
        // **A document is flipped by its name**, which is what Visibility keeps
        // it under (`documents`), so it must be one the film actually holds.
        if ((kind === "documents" || kind === "me-documents") && (front.documents || []).some((d) => d.name === key)) {
          const back = String(form.get("back") || "");
          const to = /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : base;
          if (kind === "me-documents") {
            const me = { ...emptyMine(), ...(visible.me || {}) };
            const now = new Set(me.documents);
            if (now.has(key)) now.delete(key); else now.add(key);
            await saveVisible(env, project, { ...visible, version: 1, me: { ...me, documents: [...now] } });
          } else {
            const now = new Set(visible.documents || []);
            if (now.has(key)) now.delete(key); else now.add(key);
            await saveVisible(env, project, { ...visible, version: 1, documents: [...now] });
          }
          return new Response(null, { status: 303, headers: { location: to } });
        }
        if ((kind !== "sections" && kind !== "me-sections") || !/^[a-z0-9][a-z0-9-]*$/.test(key)) return page(400, "Not a page", "");
        // **Shown for Me** flips his own list and nothing else (`meSees`).
        if (kind === "me-sections") {
          const me = { ...emptyMine(), ...(visible.me || {}) };
          const now = new Set(me.sections);
          if (now.has(key)) now.delete(key); else now.add(key);
          await saveVisible(env, project, { ...visible, version: 1, me: { ...me, sections: [...now] } });
          const back = String(form.get("back") || "");
          const to = /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : base;
          return new Response(null, { status: 303, headers: { location: to } });
        }
        // **A board's own switch, not the hidden list** (`SHARES` in
        // `front.js`): on Links means Anyone with the Link; off means the crew.
        const onBoard = (front.sections || []).find((one) => one.type === "board" && one.slug === key);
        if (onBoard) {
          onBoard.share = onBoard.share === "link" ? "crew" : "link";
          await saveFront(env, project, front);
          const back = String(form.get("back") || "");
          const to = /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : base;
          return new Response(null, { status: 303, headers: { location: to } });
        }
        const now = new Set(visible.sections || []);
        if (now.has(key)) now.delete(key); else now.add(key);
        await saveVisible(env, project, { ...visible, version: 1, sections: [...now] });
        const back = String(form.get("back") || "");
        const to = /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : base;
        return new Response(null, { status: 303, headers: { location: to } });
      }
      // **The whole form, every list ticked or not** — `saveViewersSee`, which
      // the Projects Console's door shares.
      const ticked = (kind) => new Set(form.getAll(kind).map(String));
      await saveViewersSee(env, project, front, visible, {
        sections: ticked("sections"), crew: ticked("crew"), documents: ticked("documents"), contact: ticked("contact"),
      });
      if (part || checks) return fragment(await visibleOf(env, project));
      return new Response(null, { status: 303, headers: { location: `${base}/visibility` } });
    }
    if (part || checks) return fragment(visible);
    const tools = await toolRail(env, project, title, role, who, base, front);
    return html(visibilityBody(base, title, role, who, front, visible, Boolean(mine), tools, forMe) + tools.panel,
                `Visibility · ${title}`, 200, { front: true });
  }

  /**
   * **The deck editor, on the deck itself.** His rebuild of 2026-09-05: the
   * preview is the interface, so this is not a screen beside the deck — it is
   * the deck, with handles.
   *
   * A GET draws it. A POST saves the arrangement and the words, and nothing
   * else: the design is not writable from here, and neither is which film it
   * belongs to. Editors only, the same gate as adding a page.
   */
  /**
   * **Print this deck, here.** The sheets the editor published, printed by a
   * real Chrome beside this worker and filed under Documents — see `press.js`.
   * The editor asks for it after a publish; an editor may also ask directly.
   * The request stays open while it prints, which is what lets it run past the
   * thirty seconds a background task would get.
   */
  if (rest.length === 2 && rest[1] === "print") {
    if (role !== "editor") return problem(403, "Editors only");
    if (request.method !== "POST") return problem(405, "Wrong method.");
    const slug = rest[0];
    if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) return problem(404, "No such deck.");
    const host = env.PRESS_HOST || new URL(request.url).origin;
    let said;
    try {
      said = await printDeck(env, project, slug, host);
    } catch (error) {
      console.error(error && error.stack ? error.stack : String(error));
      said = { error: `The press failed: ${String(error && error.message || error).slice(0, 200)}` };
    }
    return json(said, said.error ? 500 : 200);
  }

  if (rest.length === 2 && rest[1] === "edit") {
    if (role !== "editor") return page(403, "Editors only", "");
    const slug = rest[0];
    if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) return page(404, "No such page", "");
    const key = keys.deck(project, slug);
    const held = await env.BUCKET.get(key);
    if (!held) {
      return page(404, "Not a deck",
        "");
    }
    let record;
    try {
      record = JSON.parse(await held.text());
    } catch {
      return page(500, "Unreadable", "That deck's record could not be read. Publish it again.");
    }

    if (request.method === "POST") {
      let sent;
      try {
        sent = await request.json();
      } catch {
        return new Response("that is not JSON", { status: 400 });
      }
      // **A picture dropped onto the editor.** Stored by its own contents, the
      // same way `add_document` does it, so dropping the same still twice costs
      // nothing and makes one copy. It goes to the film rather than to the
      // deck: a frame on the film can be reached by every deck of it.
      if (sent.add && typeof sent.add.base64 === "string") {
        const kind = String(sent.add.kind || "jpg").toLowerCase().replace(/[^a-z0-9]/g, "");
        if (!/^(jpe?g|png|webp|heic|gif)$/.test(kind)) {
          return new Response(JSON.stringify({ said: "not a picture" }), { status: 400 });
        }
        let bytes;
        try {
          const binary = atob(sent.add.base64);
          bytes = new Uint8Array(binary.length);
          for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
        } catch {
          return new Response(JSON.stringify({ said: "not base64" }), { status: 400 });
        }
        if (bytes.length > 12 * 1024 * 1024) {
          return new Response(JSON.stringify({ said: "over 12 MB" }), { status: 413 });
        }
        const digest = await crypto.subtle.digest("SHA-256", bytes);
        const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
        const file = `${hash.slice(0, 32)}.${kind === "jpeg" ? "jpg" : kind}`;
        await env.BUCKET.put(keys.doc(project, file), bytes, {
          httpMetadata: { contentType: kind === "png" ? "image/png" : `image/${kind}` },
        });
        return new Response(JSON.stringify({ added: file }), {
          headers: { "content-type": "application/json; charset=utf-8" },
        });
      }

      // **Only the two things this screen may change.** Everything else in the
      // record — the design, the film, the pictures it may draw on — is left
      // exactly as it was, so a save can never be a replacement.
      if (Array.isArray(sent.sections)) record.sections = sent.sections;
      if (sent.words && typeof sent.words === "object") record.words = sent.words;
      if (sent.crop && typeof sent.crop === "object") record.crop = sent.crop;
      // **The shapes of the pictures, because only a browser has measured
      // them.** A still taken off the film has no ratio in the record until it
      // has been drawn; without keeping that, every row it sits in is packed
      // against a guess of 16:9 and the printed sheet comes out wrong.
      if (sent.pictures && typeof sent.pictures === "object") record.pictures = sent.pictures;
      // **Which Notion page this deck is written on.** Set once, in the editor
      // or when the deck is made; the press reads it to know what to fetch.
      if (sent.notion && typeof sent.notion === "object") record.notion = sent.notion;
      // **A note for the Mac, because nothing here can reach Notion.** The
      // portal holds no Notion token by design; the press does, so a pull is
      // asked for here and done there. It is cleared by whoever does it.
      if (sent.pull === "words" || sent.pull === "pictures") {
        record.pull = [...new Set([...(record.pull || []), sent.pull])];
      }
      record.updated = new Date().toISOString();
      await env.BUCKET.put(key, JSON.stringify(record), {
        httpMetadata: { contentType: "application/json; charset=utf-8" },
      });

      // **Publishing keeps the design's own head and swaps only the body.**
      // What the editor sends is the deck exactly as he was looking at it, so
      // what publishes is the thing on the screen rather than a second render
      // that might differ from it. The head — the design's stylesheet and its
      // fonts — is his and is never rewritten from here.
      let published = false;
      if (typeof sent.publish === "string" && sent.publish.trim()) {
        const was = await env.BUCKET.get(keys.pageHtml(project, slug));
        const before = was ? await was.text() : "";
        const at = before.lastIndexOf("</style>");
        const head = at === -1 ? "" : before.slice(0, at + 8);
        // **The editor's own rewrite stops here, whatever sent it.** The editor
        // turns `pic/` into `../pic/` so its frames resolve one level down;
        // published, that same string resolves above the film and every picture
        // breaks — which is what happened to his live bible. The client puts
        // them back too, but a guard that only lives in the browser guards
        // nothing: this route is the boundary.
        const doc = (head + sent.publish)
          .replace(/(\s(?:src|href)=")\.\.\/pic\//g, "$1pic/");
        if (doc.length <= 2 * 1024 * 1024) {
          await env.BUCKET.put(keys.pageHtml(project, slug), doc, {
            httpMetadata: { contentType: "text/html; charset=utf-8" },
          });
          published = true;
        }
      }
      // **The sheets, for the press.** His three layers put page breaks and
      // how many sit across on paper's own side, and until now nothing could
      // set them: the paper view was a picture of the last PDF. The editor
      // draws real sheets now, and what it draws is what prints — so the press
      // stops packing pages a second time and simply prints this. That is the
      // end of the drift Ref 789 records.
      if (typeof sent.paper === "string" && sent.paper.trim() && sent.paper.length <= 4 * 1024 * 1024) {
        const sheets = sent.paper.replace(/(\s(?:src|href)=")\.\.\/pic\//g, "$1pic/");
        await env.BUCKET.put(keys.paperHtml(project, slug), sheets, {
          httpMetadata: { contentType: "text/html; charset=utf-8" },
        });
      }
      return new Response(JSON.stringify({ saved: true, published,
                                           at: record.updated }), {
        headers: { "content-type": "application/json; charset=utf-8" },
      });
    }

    // **The shelf is the film's whole library, not the deck's own frames.**
    // Swapping for a picture already in the deck is the small half of what he
    // wants; reaching for a still that is on the film and not yet in this deck
    // is the useful half. Listed off storage because a picture put there with
    // `add_document` is deliberately not listed under Documents.
    // **The paper design, if his Mac has sent one up.** It carries the print
    // stylesheet, the page geometry and each section's own block of words —
    // enough for the editor to draw the sheets exactly as they print, and not
    // one thing about where the pictures land, which is his to decide.
    // **Named `sheet`, not `page`.** This block already calls a helper called
    // `page()` above, and a `const page` here puts that call in its own
    // temporal dead zone — the "not yours to edit" path would throw instead of
    // answering. Found before it shipped; do not rename it back.
    const [title, sheet, library, front, kit] = await Promise.all([
      titleOf(env, project),
      env.BUCKET.get(keys.pageHtml(project, slug)),
      env.BUCKET.list({ prefix: keys.docs(project), limit: 900 }),
      frontOf(env, project, ctx),
      env.BUCKET.get(keys.paper(project, slug)),
    ]);
    const published = sheet ? await sheet.text() : "";
    record.published = sheet && sheet.uploaded ? new Date(sheet.uploaded).toISOString() : "";
    let paperCss = "";
    if (kit) {
      try {
        const said = JSON.parse(await kit.text());
        paperCss = String(said.css || "");
        // The stylesheet travels in its own `<style>`, never in the record.
        delete said.css;
        record.paper = said;
      } catch {
        record.paper = null;
      }
    }
    record.shelf = (library.objects || [])
      .map((o) => o.key.slice(o.key.lastIndexOf("/") + 1))
      .filter((f) => /\.(jpe?g|png|webp|heic|gif)$/i.test(f))
      .sort();
    // **The portal's own stylesheet is deliberately not loaded here.** A deck
    // brings its own design, and the two use some of the same class names —
    // `front.css` has a `.frames` rule for the film's picture strip, which took
    // over the deck's and laid every row of a section side by side in a single
    // squashed line. The record's scripts are kept out for the same reason:
    // `look.js` binds a click on every picture, and in here a click on a
    // picture means *pick this one*. The editor's own furniture carries a
    // fallback for every colour it uses, so it needs neither.
    // **Paper means the printed thing, not a scroll pretending to be one.** His
    // note, 2026-09-06: *"im not seeing the pdf in its paper form, it's still
    // all one long sheet, not helpful."* Quite right — the paper view only
    // changed how many sat across. So it shows the PDF his Mac printed: real
    // sheets, real page turns, the cream. It lags an edit by however long the
    // press takes, which the view says out loud.
    // **Found by its name, and then by anything else that will do.** Matching
    // only on an exact name meant one word out of step between the deck's own
    // name and the row the press wrote — `Look Book` against `Lookbook` — left
    // the paper view saying "Not printed yet" beside a PDF that had been
    // printed hours ago. That is a lie the screen has no way to explain, and
    // his report of 2026-09-06 that *"the pdf section does not render correctly
    // at all"* is what it looks like from his side.
    const books = (front.documents || []).filter((d) => d.kind === "lookbook" && d.file);
    const plain = (s) => String(s || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    // The press files under the page's rail name, so that is looked for first.
    const onRail = ((front.sections || []).find((one) => one && one.slug === slug) || {}).name;
    const wanted = [plain(onRail), plain(record.name), plain(slug)].filter(Boolean);
    const printed = books.find((d) => d.name === onRail)
      || books.find((d) => d.name === (record.name || slug))
      || books.find((d) => wanted.includes(plain(d.name)))
      || (books.length === 1 ? books[0] : null);
    record.pdf = printed ? `${base}/pic/${printed.file}` : "";
    record.film = title;
    return html(editorBody(base, title, slug, record, stylesOf(published), bodyOf(published),
                           BUILD, paperCss),
                `${record.name || slug} · ${title}`, 200, { paint: true });
  }

  const NOT_A_SECTION = new Set(["crew", "api", "media", "fso", "pic", "share", "join", "visibility", "add", "order", "groups", "library", "refresh", "shoots", "follow"]);

  /**
   * **Refresh from Notion, from the portal.** Ref 1155, his pick of
   * 2026-09-23 (option 2): the portal's own Notion connection, so this works
   * from his phone with the Mac asleep. See `src/notion.js` for what it reads
   * and what it deliberately does not.
   *
   * **His alone, and inert until he connects it.** Administrators only; with no
   * `NOTION_TOKEN` secret the button is never drawn and this says so rather
   * than pretending. A plain form, so `deep.js` shows it working and lands
   * the page he was on, with its "Updated just now", when it is done.
   */
  /**
   * **Follow Google Doc, from the page's menu** — `POST /f/<film>/follow`
   * `{ slug, on }` or `{ slug, refresh: true }` (`docfollow.js`, his ask of
   * 2026-10-10). An administrator's, like Refresh from Notion. JSON in, JSON
   * out: the menu says what came back and changes nothing else on the page.
   */
  if (rest.length === 1 && rest[0] === "follow" && request.method === "POST") {
    if (!isAdmin(env, who)) return json({ ok: false, said: "No Access" }, 403);
    // **From the page's own header menu it arrives as a plain form** (`followItems`
    // in `pages.js`, which has no script to send JSON) and goes back to the page.
    const formed = /form/i.test(request.headers.get("content-type") || "");
    let asked;
    let back = "";
    try {
      if (formed) {
        const form = await request.formData();
        asked = { slug: form.get("slug"), refresh: form.get("refresh") === "1", ...(form.get("on") === null ? {} : { on: form.get("on") === "1" }) };
        back = String(form.get("back") || "");
      } else asked = await request.json();
    } catch { return json({ ok: false, said: formed ? "That did not read." : "That is not JSON." }, 400); }
    const slug = String((asked && asked.slug) || "");
    if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) return json({ ok: false, said: "No such page." }, 404);
    const got = await setFollow(env, project, slug, { on: asked.on === undefined ? undefined : Boolean(asked.on), refresh: Boolean(asked.refresh) });
    if (formed) {
      const to = /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : base;
      return new Response(null, { status: 303, headers: { location: to } });
    }
    return json(got, got.ok ? 200 : got.status || 400);
  }

  if (rest.length === 1 && rest[0] === "refresh" && request.method === "POST") {
    if (!isAdmin(env, who)) return page(403, "No Access", "");
    if (!notionReady(env)) {
      return page(409, "Not connected to Notion",
        "Refresh from Projects Console.");
    }
    const form = await request.formData();
    const got = await refreshFilm(env, project);
    if (!got.ok && !got.updated) return page(502, "Notion did not refresh it", got.lines.join(" · "));
    const back = String(form.get("back") || "");
    const to = back === "home" || !/^[a-z0-9][a-z0-9-]*$/.test(back) ? base : `${base}/${back}`;
    return new Response(null, { status: 303, headers: { location: to } });
  }

  /**
   * **The order he dragged the rail into.** Ref 870, and his answer of
   * 2026-09-08: *"I like your recommendation here as well. Dragging is good."*
   *
   * POST only, and nothing is drawn: the rail already shows the answer, because
   * the rail is the thing that was dragged. A GET falls past here to the 404,
   * which is why `order` is in `NOT_A_SECTION` above — otherwise a film could
   * carry a page called `order` that answered a save.
   *
   * **`saveFront` is the gate on what a key may be.** `tidy` in `front.js`
   * refuses anything that is not a slug, drops repeats and caps the list, so
   * nothing this hands it can put rubbish on a film's card.
   */
  if (rest.length === 1 && rest[0] === "order" && request.method === "POST") {
    if (role !== "editor") return page(403, "Editors only", "");
    const form = await request.formData();
    const front = await frontOf(env, project, ctx);
    /**
     * **The rail as it stands, headings and all.** Each `group` field is one
     * heading's name and its rows, sent as `Name\nrow,row,row` — the shape the
     * sidebar is actually in, because `arrange.js` reads it straight off the
     * DOM and a shape that has to be reassembled here is a shape that can be
     * reassembled wrong.
     */
    const groups = form.getAll("group").map((one) => {
      const [name, rows] = String(one).split("\n");
      return { name: String(name || ""), rows: String(rows || "").split(",").map((r) => r.trim().replace(/%2C/g, ",")).filter(Boolean) };
    });
    // **The headings are the categories** (2026-10-11): a row dragged under a
    // heading is filed in that category, a heading dragged into place puts its
    // category there, and a drag only sends what is on screen, so pages that
    // are off the sidebar keep the place they had.
    const info = new Map((front.sections || []).map((one) => [one.slug, { name: one.name, type: one.type }]));
    const said = arrangeRail(front, groups, (at) => info.get(at) || {});
    // **`updated` is not touched.** It says when Notion last fed this film, and
    // every source line on every page reads it. Stamping it here would have the
    // Visual Bible claim it was refreshed a moment ago because a row moved.
    await saveFront(env, project, front);
    return said ? new Response(said, { status: 409, headers: { "content-type": "text/plain; charset=utf-8" } }) : new Response(null, { status: 204 });
  }
  /**
   * **His own headings for the sidebar** — made, renamed, removed and put in
   * order here; filled by dragging on the rail itself. His instruction,
   * 2026-09-08, and the order on 2026-09-10.
   *
   * **This is the page's plain form.** With `arrange.js` awake the page never
   * posts here: every change is sent to `/order` as the whole rail, the same
   * way a drag on the rail is. This answers a page with no script, and the
   * `303` it ends on is what `deep.js` lands in place.
   *
   * **Removing a heading drops its rows to the bottom of the rail**, never
   * anywhere else. Nothing is deleted: *report, never invent — and never
   * destroy.*
   */
  if (rest.length === 1 && rest[0] === "groups") {
    if (role !== "editor") return page(403, "Editors only", "");
    const [title, front, mine] = await Promise.all([
      titleOf(env, project), frontOf(env, project, ctx), manyFilms(env, who),
    ]);
    const many = Boolean(mine);
    if (request.method === "POST") {
      const form = await request.formData();
      /**
       * **The headings are the categories** (2026-10-11), so this page edits
       * the Library's categories: a name changed, one added, one removed, and
       * the order the fields arrive in is the order they are now in. Each
       * field says which category it was by its `was` (the category's id), so
       * a rename keeps everything filed under it. The seven starting
       * categories may be renamed and reordered, never removed.
       */
      const said = form.getAll("name").map((one) => String(one).replace(/\s+/g, " ").trim().slice(0, 40));
      const was = form.getAll("was").map((one) => String(one).trim());
      const dropped = String(form.get("drop") || "").trim();
      const born = String(form.get("new") || "").replace(/\s+/g, " ").trim().slice(0, 40);
      const before = shelfList(front);
      const order = [];
      const fail = (why) => html(groupsBody(base, title, front, who, role, many, why), `Categories · ${title}`, 200, { front: true });
      for (let i = 0; i < said.length; i += 1) {
        const id = was[i] || "";
        const one = before.find((x) => x.id === id);
        if (!one) { if (said[i]) { const made = editShelves(front, { action: "add", name: said[i] }); if (!made.ok) return fail(made.why); order.push(made.id); } continue; }
        if (id === dropped) {
          const gone = editShelves(front, { action: "remove", shelf: id });
          if (!gone.ok) return fail(gone.why);
          continue;
        }
        if (said[i] && said[i] !== one.name) {
          const renamed = editShelves(front, { action: "rename", shelf: id, name: said[i] });
          if (!renamed.ok) return fail(renamed.why);
        }
        order.push(id);
      }
      if (dropped && !said.length) { const gone = editShelves(front, { action: "remove", shelf: dropped }); if (!gone.ok) return fail(gone.why); }
      if (born) { const made = editShelves(front, { action: "add", name: born }); if (!made.ok) return fail(made.why); order.push(made.id); }
      if (order.length) editShelves(front, { action: "order", ids: order });
      await saveFront(env, project, front);
      return new Response(null, { status: 303, headers: { location: `${base}/groups` } });
    }
    const tools = await toolRail(env, project, title, role, who, base, front);
    return html(groupsBody(base, title, front, who, role, many, "", tools) + tools.panel, `Headings · ${title}`, 200, { front: true });
  }

  /**
   * **The Library** — every page and document the film holds, in one place,
   * and the base the sidebar is drawn from. His words, 2026-10-02: *"the
   * library is just the base where everything is held, and then I can drop
   * things on the sidebar if I want."*
   *
   * **Everybody may read it, public link or not** (his ruling the same day):
   * `libraryBody` shows each reader what they may see, as the sidebar does.
   * Changing it is an editor's: `sidebar` with `on` pins a page to the sidebar
   * or takes it off, `archive` with `on` tucks it into the Archive or takes it
   * out. None of it moves, rewrites or deletes the page (*never destroy*), and
   * its address keeps opening.
   *
   * **A plain form and a `303`**, to `back` when it names a page of the film
   * (a page's own menu), otherwise to the Library. `deep.js` lands it in place.
   */
  if (rest.length === 1 && rest[0] === "library") {
    const [title, front, mine] = await Promise.all([
      titleOf(env, project), frontOf(env, project, ctx), manyFilms(env, who),
    ]);
    if (request.method === "POST") {
      if (role !== "editor") return page(403, "Editors only", "");
      const form = await request.formData();
      const known = libraryKeys(front);
      // **Many at once**, from the Library's toolbar and menu: one JSON field,
      // `{ keys, action, to? }`, applied to every key in a single save. A
      // string of single posts would each read the card, change one thing and
      // write it back, and the last would win over the others. **Set, not
      // flip**: every action says where things end up, so doing it twice is
      // the same as doing it once. The four Visibility ones are an
      // administrator's, as they are everywhere else.
      const bulk = String(form.get("bulk") || "");
      if (bulk) {
        let ask = null;
        try { ask = JSON.parse(bulk); } catch { /* falls through to the refusal */ }
        let done;
        try {
          done = await arrangeLibrary(env, project, front, ask, isAdmin(env, who));
        } catch (error) {
          if (error instanceof Refusal) return page(error.status, error.said, error.more || "");
          throw error;
        }
        return new Response(JSON.stringify({ ok: true, ...done }), {
          headers: { "content-type": "application/json", "cache-control": "no-store" },
        });
      }
      // **A category of the Library** (2026-10-10): add, rename, move up or
      // down, or remove one he added (`editShelves` in `front.js`).
      const category = String(form.get("category") || "");
      if (category) {
        const said = editShelves(front, { action: category, shelf: String(form.get("shelf") || ""),
          name: String(form.get("name") || ""), to: String(form.get("to") || "") });
        // **JSON for the sidebar and the Library's own script** (2026-10-11):
        // a heading renamed, added or removed in place, with the reason when
        // it is refused, and the categories as they now stand.
        const json = (request.headers.get("accept") || "").includes("application/json");
        if (json) {
          if (said.ok) await saveFront(env, project, front);
          return new Response(JSON.stringify(said.ok ? { ok: true, id: said.id || "", shelves: shelfList(front) } : { ok: false, why: said.why || "" }), {
            status: said.ok ? 200 : 422, headers: { "content-type": "application/json", "cache-control": "no-store" },
          });
        }
        if (!said.ok) return page(422, "Could not change that category", said.why || "");
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: `${base}/library` } });
      }
      // **Move To**: a page by its address, a document by `doc:` and its name,
      // onto one of the film's shelves (`front.shelves`), by its name or id.
      const shelfKey = String(form.get("shelf") || "");
      if (shelfKey) {
        const to = String(form.get("to") || "");
        const doc = shelfKey.startsWith("doc:") ? shelfKey.slice(4) : "";
        const sec = (front.sections || []).find((one) => one.slug === shelfKey);
        if (!shelfIdFor(front, to) || !(doc ? (front.documents || []).some((d) => d.name === doc) : known.has(shelfKey))) {
          return page(404, "No such shelf or page", "");
        }
        setShelf(front, shelfKey, to, doc || (sec ? sec.name : shelfKey), doc ? "doc" : "page", sec ? sec.type : "");
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: `${base}/library` } });
      }
      const side = String(form.get("sidebar") || "");
      const tuck = String(form.get("archive") || "");
      const at = side || tuck;
      const docAt = at.startsWith("doc:") && tuck && (front.documents || []).some((d) => d.name === at.slice(4));
      if (!known.has(at) && !docAt) return page(404, "No such page", `${at || "That"} is not a page on this film.`);
      const on = String(form.get("on") || "") === "1";
      // **Always saved**, even when nothing changed: the heading a page sits
      // under may have changed since, and that is what putting it back on the
      // sidebar remembers.
      if (side) setOnSidebar(front, at, on);
      else {
        // Archiving also makes the page private, which lives in Visibility.
        const seen = { ...(await visibleOf(env, project)) };
        setArchived(front, at, on, seen);
        await saveVisible(env, project, { ...seen, version: 1 });
      }
      await saveFront(env, project, front);
      const back = String(form.get("back") || "");
      return new Response(null, { status: 303, headers: { location: /^[a-z0-9][a-z0-9-]*$/.test(back) ? `${base}/${back}` : `${base}/library` } });
    }
    /**
     * **`?part=pick`: what the sidebar's Add Pages panel lists** (2026-10-11).
     * Every live page with its category and whether it is on the sidebar, and
     * the categories in order. An editor's; the panel pins through `bulk`.
     */
    if (url.searchParams.get("part") === "pick") {
      if (role !== "editor") return page(403, "Editors only", "");
      return new Response(JSON.stringify(sidebarPicks(front)), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
    }
    const tools = await toolRail(env, project, title, role, who, base, front);
    // **What the covers say** (`covers.js`): kept, and read again only for what was written since.
    tools.covers = await coversOf(env, project, coverWants(front, tools.visible, role, who, tools.admin));
    return html(libraryBody(base, title, front, who, role, Boolean(mine), "", tools) + tools.panel, `Library · ${title}`, 200, { front: true });
  }

  /**
   * **Adding a page — an editor, on the film itself.**
   *
   * His ruling, 2026-09-05: a deck is always a page of a film, so the project
   * is decided by where you were standing rather than by a field. This is the
   * moment that makes one, and it asks only for a name.
   *
   * The row is what matters. A page's address does not answer until the film
   * lists a section of that slug — so before this existed, a deck could publish
   * a designed document into the bucket, report success, and hand him a link
   * that returned "No such page". The document is written afterwards, by Deck
   * Editor or by `set_page`; this makes the address real.
   */
  if (rest.length === 1 && rest[0] === "add") {
    if (role !== "editor") return page(403, "Editors only", "");
    const [title, front, mine] = await Promise.all([
      titleOf(env, project), frontOf(env, project, ctx), manyFilms(env, who),
    ]);
    const many = Boolean(mine);
    if (request.method === "POST") {
      const form = await request.formData();
      // **The sidebar's Add menu posts here too** (move 2): the same fields, an
      // `accept: application/json` header and, from a heading's +, the `head`
      // the new page should land under. It answers with where to go (or why
      // not) instead of a redirect or a redrawn form, so the menu stays put.
      const json = /application\/json/.test(request.headers.get("accept") || "");
      const under = String(form.get("head") || "").replace(/\s+/g, " ").trim().slice(0, 40);
      const landed = (to) => (json
        ? new Response(JSON.stringify({ ok: true, href: to }), { headers: { "content-type": "application/json", "cache-control": "no-store" } })
        : new Response(null, { status: 303, headers: { location: to } }));
      // **A heading's + is a category's +**: the new page is filed there.
      const filed = (slug) => {
        const id = under ? shelfIdFor(front, under) : "";
        if (id) setShelf(front, slug, id, called || slug, "page", type);
      };
      const called = String(form.get("name") || "").replace(/\s+/g, " ").trim().slice(0, 60);
      /**
       * **The type, and then at most one more question.** Ref 872, his answer:
       * *"Yes, I think Plan B is the way to go."*
       *
       * Three doors used to be five rituals, each deciding both what a thing is
       * and where its words come from, and never saying so. Here the type is
       * asked first and decides what is asked next: a deck asks nothing, a file
       * asks for the file, and only a written page has a real choice about its
       * source.
       */
      const type = ["page", "deck", "file", "link", "board"].includes(String(form.get("type") || "")) ? String(form.get("type")) : "page";
      const chose = { type, name: called, url: String(form.get("url") || "").trim() };
      const refuse = (why) => (json
        ? new Response(JSON.stringify({ ok: false, error: why }), { status: 400, headers: { "content-type": "application/json", "cache-control": "no-store" } })
        : html(newPageBody(base, title, front, who, role, many, why, chose), `Add · ${title}`, 200, { front: true, add: true }));

      /**
       * **A link is not a copy of anything**, which is the point of it. His
       * instruction, 2026-09-08: *"I should just be able to add links to not
       * just Notion, but anything I want — for example, a Google Drive folder
       * or a YouTube video."* Most of what he wants a crew member to reach
       * already lives somewhere with an address, and copying it here would make
       * a second copy that goes stale.
       *
       * It has always been a thing a film can hold — `document` in `front.js`
       * has taken a `url` since the card existed — and the only way to make one
       * was to tick `Hub` on a Project Docs row in Notion. So anything not
       * already written down in Notion could not be pinned at all.
       */
      if (type === "link") {
        if (!called) return refuse("Give the link a name.");
        let where = "";
        try {
          const said = new URL(chose.url);
          // **`http` and `https` only**, the same rule `safeUrl` holds on the
          // card: this ends up in an `href` on a page a director opens.
          if (said.protocol === "https:" || said.protocol === "http:") where = said.toString();
        } catch { /* not an address at all */ }
        if (!where) return refuse("That is not a web address. It starts https://");
        if ((front.documents || []).some((d) => d.name.toLowerCase() === called.toLowerCase())) {
          return refuse(`${called} is already pinned to this film.`);
        }
        front.documents = [...(front.documents || []), {
          name: called,
          kind: "document",
          url: where,
          // **Said outright, and it is what keeps it.** `both_kinds` in
          // `refresh.py` used to tell a link of Notion's from a file of his by
          // asking which one carried a `file` — so a link made here was swept
          // away by the next refresh, silently, and again the one after.
          source: "here",
        }];
        // **A link is a page like any other**: on the sidebar from the start,
        // filed by its name or its address (or under the heading whose + made
        // it), and private or archived from the Library like the rest.
        setOnSidebar(front, `doc:${called}`, true);
        {
          const id = under ? shelfIdFor(front, under) : "";
          if (id) setShelf(front, `doc:${called}`, id, called, "doc");
        }
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return landed(`${base}/library`);
      }

      /**
       * **A file is not an address on this film**, so it takes none of the slug
       * rules below. It is stored by its own contents and pinned under
       * Documents — the same bargain `add_document` strikes, reached from a
       * browser instead of from an agent, because until now the only way to put
       * a look book on a film was to ask Claude to base64 it.
       */
      if (type === "file") {
        const sent = form.get("file");
        if (!called) return refuse("Give the file a name.");
        if (!sent || typeof sent === "string" || !sent.size) return refuse("Choose a file.");
        const extension = String(sent.name || "").split(".").pop().toLowerCase();
        if (!DOC_EXTENSION.has(extension)) return refuse(`A .${extension || "?"} cannot go on the page.`);
        if (sent.size > 8 * 1024 * 1024) return refuse("Over 8 MB. Link it from Drive instead.");
        if ((front.documents || []).some((d) => d.name.toLowerCase() === called.toLowerCase())) {
          return refuse(`${called} is already pinned to this film.`);
        }
        const stored = await storeBytes(env, project, extension, new Uint8Array(await sent.arrayBuffer()));
        front.documents = [...(front.documents || []), {
          name: called,
          kind: "document",
          file: stored.file,
          bytes: stored.bytes,
          // **Uploaded here, so a refresh may not take it away.** `both_kinds`
          // in `refresh.py` tells the two apart by exactly this.
          source: "here",
        }];
        // **A file is the same**: on the sidebar and in its category from the start.
        setOnSidebar(front, `doc:${called}`, true);
        {
          const id = under ? shelfIdFor(front, under) : "";
          if (id) setShelf(front, `doc:${called}`, id, called, "doc");
        }
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return landed(`${base}/library`);
      }

      // **The same address maker the MCP uses.** `slugOf` strips punctuation out
      // rather than turning it into hyphens — it is for a film's own name — so
      // `Lighting Plan` came out `lightingplan`, which is not what `set_page`
      // would have made of it and not what anybody would type.
      const slug = slugFrom(called);
      const taken = new Set([
        ...RECORD_PAGES.keys(), ...NOT_A_SECTION, "add", "shotlist", "shots",
        "locations", "boards", "schedule", "diagrams",
        ...(front.sections || []).map((one) => one.slug).filter(Boolean),
      ]);
      // **The name has to be free as well as the address**, 2026-09-07. Two
      // different things were being checked as one: `Visual Bible` makes the
      // address `visual-bible`, and the built-in bible's address is `bible`, so
      // nothing collided and the rail drew *Visual Bible* twice — two rows,
      // identical, going to different pages, with no group head, count or
      // tooltip to tell them apart. He knows which is which because he built
      // them; a director clicks the wrong one and decides the portal is broken.
      //
      // Refused here rather than patched in the rail, because a suffix rule
      // only ever produces `Visual Bible 2`, which is not a name either.
      const named = new Set([
        ...RECORD_PAGES.values(), "Shot List", "Locations", "Schedule", "Mood Boards", "Reference Images", "Add",
        ...(front.sections || []).map((one) => one.name).filter(Boolean),
      ].map((one) => one.toLowerCase()));
      // **Say why, and keep what he typed in front of him.** A form that clears
      // itself and shows a red line is a form he has to start again.
      const wrong = !called
        ? "Give the page a name."
        : !slug || !/^[a-z0-9][a-z0-9-]*$/.test(slug)
          ? `${called} does not make an address. Try plain words.`
          : taken.has(slug) || named.has(called.toLowerCase())
            ? `${called} is already a page on this film.`
            : (front.sections || []).length >= 24
              ? "Page limit reached"
              : "";
      if (wrong) return refuse(wrong);
      /**
       * **`by` says who made the row; `source` says who writes it.** They used
       * to be one fact, which is the whole of Ref 871: a row an agent touched
       * was a row Notion could never feed again.
       *
       * The portal made this row, so `by` is `mcp` however it is fed — that is
       * what keeps `both_roads` from dropping it if Notion never names it. A
       * **deck** is the exception: `by: "deck"` is what stops Markdown landing
       * on a design (`set_page` refuses it) and what makes the row an address
       * Deck Editor can publish into, which is why `/add` exists at all.
       */
      /**
       * **A board is a page that draws itself** (`boards.js`): nothing is
       * written for it here but the row, and the row says where its cards
       * live and who may open it — him alone, to begin with. His ruling,
       * 2026-09-25: private first, shared when he chooses.
       */
      if (type === "board") {
        front.sections = [...(front.sections || []), newBoard(called, "me")];
        filed(slug);
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return landed(`${base}/${slug}`);
      }
      front.sections = [...(front.sections || []), {
        slug,
        name: called,
        title: "",
        by: type === "deck" ? "deck" : "mcp",
        type: type === "deck" ? "deck" : "page",
        // **Written here, because at birth that is the only true answer.** See
        // the note above `newPageBody`: this worker has no Notion token and
        // cannot bind a page to a Notion page, so *Live from Notion* was a
        // label with nothing behind it. The source is changed on the page
        // afterwards, where there is something to hand over.
        source: type === "deck" ? "program" : "here",
        // **Nothing in Notion names a page born here**, so the two Notion
        // sources are not offered on it until a refresh finds a Hub-ticked row
        // carrying this name. His report, 2026-09-08.
        notion: false,
      }];
      filed(slug);
      front.updated = new Date().toISOString();
      await saveFront(env, project, front);
      return landed(`${base}/${slug}`);
    }
    const tools = await toolRail(env, project, title, role, who, base, front);
    return html(newPageBody(base, title, front, who, role, many, "", {}, tools) + tools.panel, `Add · ${title}`, 200, { front: true, add: true });
  }

  /**
   * **The script's PDF, always the newest draft** (SL-1338). `/script.pdf` is
   * whichever draft the film calls latest at the moment it is asked, so it is
   * an address that can be sent once and stays right; `?draft=<stem>` is one
   * draft for ever. `?save=1` downloads it under its own name. The Script
   * row's Visibility switch holds for the bytes as well as the page.
   */
  if (rest.length === 1 && rest[0] === "script.pdf") {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    const [title, front, visible] = await Promise.all([
      titleOf(env, project), frontOf(env, project, ctx), visibleOf(env, project),
    ]);
    if (!maySee(visible, "sections", "script", role)) return page(404, "No such page", "");
    const drafts = front.scripts || [];
    const asked = url.searchParams.get("draft") || "";
    const one = asked ? drafts.find((d) => d.stem === asked) : drafts[0];
    if (!one) return page(404, "No such page", "");
    const got = await media(env, project, `${one.stem}.pdf`, request, ["media"], scriptFileName(one, title), true);
    if (asked || !got.ok) return got;
    // **The newest is not for ever.** A draft's own address is its bytes and
    // may be kept a year; this one changes the day a new draft comes in.
    const fresh = new Response(got.body, got);
    fresh.headers.set("cache-control", "private, no-cache");
    fresh.headers.delete("etag");
    return fresh;
  }

  /**
   * **A draft's words, for the Script page's Marks view** (Ref 1568). The same
   * draft `script.pdf` serves, as the text the Mac read it from, so the
   * browser's engine can lay it out and say which shots hold which lines.
   * Held to the same door as the PDF: the Script row's Visibility switch.
   */
  if (rest.length === 1 && rest[0] === "script.txt") {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    const [front, visible] = await Promise.all([frontOf(env, project, ctx), visibleOf(env, project)]);
    if (!maySee(visible, "sections", "script", role)) return page(404, "No such page", "");
    const drafts = front.scripts || [];
    const asked = url.searchParams.get("draft") || "";
    const one = asked ? drafts.find((d) => d.stem === asked) : drafts[0];
    if (!one) return page(404, "No such page", "");
    const got = await env.BUCKET.get(keys.inFolder(project, "media", `${one.stem}.txt`));
    if (!got) return problem(404, "No such draft.");
    return new Response(request.method === "HEAD" ? null : got.body, {
      headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "private, max-age=31536000, immutable" },
    });
  }

  if (rest.length === 1 && !NOT_A_SECTION.has(rest[0]) && /^[a-z0-9][a-z0-9-]*$/.test(rest[0])) {
    // **Three reads, at the same time rather than one after another.** They do
    // not depend on each other, and read in turn they were most of the second
    // and a half a two-kilobyte page took to arrive — long enough that the
    // animation waiting on it was a pause with a flourish at the end.
    // **Four now, and the fourth is the way out.** The rail is the same on
    // every page, home included, so `Projects` has to be offered here on the
    // same terms it is offered there — only to somebody who has other films,
    // his ruling of 2026-09-02. Read alongside the rest, so it costs its own
    // latency and no serial time.
    const [title, front, people, mine, visible] = await Promise.all([
      titleOf(env, project),
      frontOf(env, project, ctx),
      role === "editor" ? peopleOf(env, project) : null,
      manyFilms(env, who),
      visibleOf(env, project),
    ]);
    // **One of the four built in, or one he named in Notion.** A `Section` on a
    // Hub-ticked Project Docs row is a section of this film; anything else is
    // not an address here and falls through to the 404 below rather than
    // drawing an empty page for a name somebody guessed.
    const his = (front.sections || []).find((one) => one.slug === rest[0]);
    // **An address a page left on a rename still opens it** (`movePage`): the
    // link sent last week goes on working, and lands on the page's new address.
    // **Unless the page is private to whoever follows it** (his rule,
    // 2026-10-09): then the old address answers as the page would, nothing,
    // rather than forwarding and giving the page's new name away.
    const movedTo = !his && !RECORD_PAGES.has(rest[0]) && (front.moved || {})[rest[0]];
    const there = movedTo && (front.sections || []).find((one) => one.slug === movedTo);
    if (there) {
      if (!maySee(visible, "sections", movedTo, role) || !boardOpen(there, who, isAdmin(env, who) && !sharing)) {
        return page(404, "No such page", "");
      }
      return new Response(null, { status: 301, headers: { location: `${base}/${movedTo}${url.search}` } });
    }
    if (!RECORD_PAGES.has(rest[0]) && !his) return page(404, "No such page", "");
    // **The server refuses, not the page.** A hidden section is not a row that
    // is missing from a rail — it is an address that does not answer, or the
    // whole thing is a stylesheet away from being read.
    if (!maySee(visible, "sections", rest[0], role)) return page(404, "No such page", "");
    // **A board he has not shared is nothing to anybody else** — the same
    // answer as an address that never existed, so its name is not given away.
    if (his && !boardOpen(his, who, isAdmin(env, who) && !sharing)) return page(404, "No such page", "");

    /**
     * **Setting where a page's words come from.** Ref 871.
     *
     * The half of Ref 854 that did not land: every page has carried a source
     * since 2026-09-08 and **nothing could set it** — a value with no control.
     * Worse, the only way to take a snapshot of a Notion page was to have an
     * agent copy it, which stamped the row and locked Notion out for good, with
     * no way back but unticking `Hub` in Notion and ticking it again.
     *
     * His decision, 2026-09-08: *"Your recommendation is correct"* — the source
     * decides who wins, and **it is changeable both ways**. `refresh.py` reads
     * what this writes: `source_of` there is the same derivation, `both_roads`
     * keeps a page Notion is no longer feeding, and the fetch loop leaves one
     * alone unless its source is `notion`.
     *
     * **Only one of his own pages.** People, Documents and the spec sheet are
     * databases rather than pages — there is nothing to hand over — and a deck's
     * words come out of Deck Editor, so handing one to Notion would mean the
     * next publish quietly taking it back.
     */
    if (request.method === "POST") {
      if (role !== "editor") return page(403, "Editors only", "");
      const form = await request.formData();

      /**
       * **Unpinning a document.** His question, 2026-09-08 — asked of a page,
       * true of a link he pins too: Add was built and its other half was not.
       *
       * **Unpinned, never deleted.** A held file is content-addressed and a
       * page may be drawing it, so the row goes and the bytes stay. Only his
       * own: a document Notion names is unticked in Notion, and taking it off
       * here would put it back at the next refresh.
       */
      /**
       * **Renaming a pinned document**, a link or a file (his report,
       * 2026-10-11: a Drive link on the portal could not be renamed). Every
       * list that knows it by name follows (`renameDocument`).
       */
      if (rest[0] === "documents" && form.get("rename_doc") !== null) {
        const visible = await visibleOf(env, project);
        const got = renameDocument(front, visible, String(form.get("rename_doc") || ""), String(form.get("to") || ""));
        if (!got.ok) return page(got.why.includes("already") ? 409 : 400, "Could not rename", got.why);
        if (got.touched) await saveVisible(env, project, visible);
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: `${base}/documents` } });
      }
      if (rest[0] === "documents" && form.get("unpin") !== null) {
        const called = String(form.get("unpin") || "").trim().toLowerCase();
        front.documents = (front.documents || []).filter(
          (d) => !(d.name.trim().toLowerCase() === called && d.source === "here")
        );
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: `${base}/documents` } });
      }
      if (!his) return page(404, "No such page", "");

      /**
       * **Taking a page off the film.** His question, 2026-09-08: *"how do i
       * delete a page?"* He could not, from here.
       *
       * **Refused where Notion names it.** That page comes straight back at the
       * next refresh, so removing it would look like it worked and quietly undo
       * itself within the hour — worse than saying no.
       *
       * The page's own file goes with the row. A deck keeps its published PDF
       * under Documents, which is a document of the film rather than part of
       * this page, and is his to unpin separately.
       */
      if (form.get("remove") !== null) {
        if (his.notion) {
          return page(409, "Notion names this page",
            `Untick Hub on its Project Docs row in Notion, and it goes from here at the next refresh.`);
        }
        front.sections = (front.sections || []).filter((one) => one.slug !== rest[0]);
        front.rail = (front.rail || []).filter((r) => r !== rest[0]);
        forgetMoves(front, rest[0]);
        await env.BUCKET.delete(keys.page(project, rest[0]));
        await env.BUCKET.delete(keys.pageHtml(project, rest[0]));
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: base } });
      }

      /**
       * **Renaming a page, here.** Ref 1153: the page menu's Rename. Refused
       * where Notion names it (the next refresh would put Notion's name back),
       * and refused onto a name another page already wears, for the reason Add
       * refuses one: two rows reading alike are a crew member's wrong click.
       *
       * **The address follows the name** (his ask, 2026-10-09: *"when i rename
       * a page, the link and the smart preview auto updates with the new
       * name"*). It used to stay put, so a page renamed from Lighting Plan to
       * Night Exteriors was still sent as `/lighting-plan`, and iMessage, which
       * keeps a preview per address, went on showing the old name. Now it
       * moves to `/night-exteriors` (`movePage`) and the old address forwards
       * to it, so nothing already sent breaks. **A deck keeps its address**:
       * Deck Editor publishes into it by that name.
       */
      if (form.get("rename") !== null) {
        const called = String(form.get("rename") || "").replace(/\s+/g, " ").trim().slice(0, 60);
        if (!called) return page(400, "Give the page a name", "");
        const others = new Set([
          ...RECORD_PAGES.values(), "Shot List", "Locations", "Schedule", "Mood Boards", "Reference Images", "Add",
          ...(front.sections || []).filter((one) => one.slug !== rest[0]).map((one) => one.name).filter(Boolean),
        ].map((one) => String(one).toLowerCase()));
        if (others.has(called.toLowerCase())) {
          return page(409, "That name is taken", `${called} is already a page on this film.`);
        }
        his.name = called;
        // **A page Notion names keeps its address and its Notion title**: the
        // portal's own name for it is laid over Notion's (`front.labels`), so
        // the next refresh writing Notion's name back changes nothing he sees.
        if (his.notion) front.labels = { ...(front.labels || {}), [rest[0]]: called };
        const at = his.type !== "deck" && !his.notion ? await movePage(env, project, front, visible, rest[0], slugFrom(called)) : rest[0];
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: `${base}/${at}` } });
      }

      /**
       * **Writing the page, here.** His report, 2026-09-08: *"All of the
       * options under the written page add ... have no function."* He was
       * right — the one type called *Written Page* was the one type he could
       * not write. Only `set_page` could put words on a page, and that is an
       * agent's door.
       *
       * **The same Markdown, through the same maker.** `pageFrom` in
       * `paper.js` is what `set_page` calls, writing the same
       * `pages/<slug>.json` — so a page he types and a page Claude writes are
       * one kind of thing, and either can go on editing the other's work.
       */
      if (form.get("markdown") !== null) {
        const said = String(form.get("markdown") || "").trim();
        // **Never wipe a page by accident.** An empty box is refused rather
        // than obeyed: *report, never invent — and never destroy.* A page he
        // truly wants gone is removed as a page.
        // Nothing typed, nothing to lose: back to the page unchanged, rather
        // than a redraw that would have to rebuild the share panel and the
        // deck's own document to say so.
        if (!said) return new Response(null, { status: 303, headers: { location: `${base}/${rest[0]}` } });
        const { tree } = pageFrom(said);
        if (!tree.length) return page(400, "Nothing to save", "");
        const body = JSON.stringify(tree);
        if (body.length > MAX_PAGE) {
          return page(413, "Page too long", "");
        }
        await env.BUCKET.put(keys.page(project, rest[0]), body, {
          httpMetadata: { contentType: "application/json; charset=utf-8" },
        });
        // **Writing it here makes it written here**, which is exactly what
        // `set_page` does and for the same reason: a page fed by Notion would
        // otherwise have his words replaced at the next refresh, silently. The
        // Source control right below says so, and hands it back in one press.
        his.source = "here";
        if (!his.by) his.by = "mcp";
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
        return new Response(null, { status: 303, headers: { location: `${base}/${rest[0]}` } });
      }

      const wanted = String(form.get("source") || "");
      const now = his.source || (his.by === "deck" ? "program" : his.by === "mcp" ? "here" : "notion");
      if (now === "program") {
        return page(409, "Written by Deck Editor",
          "This page's words come from Deck Editor. Change it there and publish.");
      }
      if (!PAGE_SOURCES.includes(wanted)) return page(400, "Not a source", "");
      // **A source Notion cannot honour is refused rather than stored.** His
      // report, 2026-09-08: setting one of the two Notion sources on a page
      // Notion does not name changed a word and waited for a refresh that would
      // never find anything. `notion` on the section is written by
      // `refresh.py`, the only thing that can know.
      if (wanted !== "here" && !his.notion) {
        return page(409, "Notion does not name this page",
          `Tick Hub on a Project Docs row in Notion and set its Section to “${his.name}”, then it can be fed from there.`);
      }
      his.source = wanted;
      await saveFront(env, project, front);
      return new Response(null, { status: 303, headers: { location: `${base}/${rest[0]}` } });
    }

    // Only a drawn section costs a second read, and only when it is opened.
    // **The camera spec sheet's notes are a page of the same kind**, kept under
    // a name of their own so a section he happens to call Camera cannot land on
    // top of them, and read only when the sheet says it has any.
    // **The shoot this address is on** (SL-1396): its crew, sheet and pages.
    const shown = shotView(front, shootIn(base));
    // the camera page's pills in Notion's colours, whichever refresh wrote the
    // card (the Mac's refresh.py carries none): kept in R2, src/specpills.js
    if (rest[0] === "camera") {
      const colours = colourIndex(await specPills(env));
      if (Object.keys(colours).length) shown.camera_pills = colours;
    }
    const tree = his
      ? await pageOf(env, project, rest[0])
      : rest[0] === "camera" && shown.camera_notes
        ? await pageOf(env, project, shown.camera_page || "camera-sheet")
        : null;
    // **A page may have been published as a finished document.** His decision,
    // 2026-09-05: one deck design makes the PDF and the web page, so when
    // `publish.py` has put one here it is drawn instead of the tree — same
    // address, same rail, its own design inside.
    const made = his && his.type === "board" ? boardMarkup(base, his, title) : await pageHtmlOf(env, project, rest[0]);
    const extra = rest[0] === "script" ? await scriptExtra(env, project, front, url.searchParams.get("draft")) : {};
    // **The doc a followed page syncs from, by name, and when** — for the
    // editor's Synced from line (pages.js `syncLine`). One small read.
    if (role === "editor" && his && his.follow && his.follow.on) {
      try { extra.follow = await followStateOf(env, project, rest[0]); } catch { /* the line says Google Doc */ }
    }
    return html(
      recordBody(base, title, role, who, shown, rest[0],
        Boolean(people && people.links.length), tree, Boolean(mine), visible,
        isAdmin(env, who), made, extra) + await sharePanel(env, project, title, role, who, base, front),
      `${his ? his.name : (front.labels || {})[rest[0]] || RECORD_PAGES.get(rest[0])} · ${title}`,
      200,
      (() => {
        const said = sharedAs(url, base, title, front, rest[0]);
        // **A designed page is sealed off from the portal's own CSS.** See
        // `public/made.js`: `front.css` and `hub.css` both style a `.frames`,
        // and so did his deck — twelve frames came out as a sixty-pixel sliver.
        said.made = Boolean(made);
        // The card names the page as well as the film: a link to People and a
        // link to the Visual Bible are different things to be sent.
        said.og.title = `${his ? his.name : (front.labels || {})[rest[0]] || RECORD_PAGES.get(rest[0])} · ${title}`;
        return { front: true, ...said };
      })()
    );
  }

  // `/crew` keeps its old address: the viewer has linked to it since Stage 1,
  // and a working link is worth more than a tidy one. **It draws the People
  // page**, which holds the same names, the same departments and the same
  // editor-only contacts — one crew screen rather than two that can drift.
  if (rest.length === 1 && rest[0] === "crew") {
    const [title, front, people, mine, visible] = await Promise.all([
      titleOf(env, project),
      frontOf(env, project, ctx),
      role === "editor" ? peopleOf(env, project) : null,
      manyFilms(env, who),
      visibleOf(env, project),
    ]);
    // `/crew` is the old address for the People page, so it honours the same
    // rule — an alias that skipped the gate would be a way round it.
    if (!maySee(visible, "sections", "people", role)) return page(404, "No such page", "");
    return html(
      recordBody(base, title, role, who, shotView(front, shootIn(base)), "people",
        Boolean(people && people.links.length), null, Boolean(mine), visible, isAdmin(env, who))
        + await sharePanel(env, project, title, role, who, base, front),
      `People · ${title}`,
      200,
      // The old address is a real page somebody may be sent, so it carries a
      // card like every other one.
      (() => {
        const said = sharedAs(url, base, title, front, "people");
        said.og.title = `People · ${title}`;
        return { front: true, ...said };
      })()
    );
  }

  // ---- the pictures ------------------------------------------------------
  if (rest[0] === "media" && rest.length === 2) {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    return await media(env, project, rest[1], request);
  }

  // **The Film Set Objects pack, for a plan on the Diagrams page** (Ref 1216).
  // The browser's engine is built without the pack's 9.6 MB of pictures, so a
  // plan names them `fso/<id>.png` beside the page, and they are answered
  // here — past the film's own door, like its pictures, because his licence
  // allows plots online and not handing the pictures out. One copy in the
  // bucket for every film (`fso/`), put there by `hub/deploy.sh`.
  if (rest[0] === "fso" && rest.length === 2) {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    if (!/^[a-z0-9-]{1,80}\.png$/.test(rest[1])) return problem(400, "That is not a picture.");
    const art = await env.BUCKET.get(`fso/${rest[1]}`);
    if (!art) return problem(404, "No such picture.");
    return new Response(request.method === "HEAD" ? null : art.body, {
      headers: {
        "content-type": "image/png",
        // The pack does not change under a name; a browser keeps it, a
        // shared cache never does.
        "cache-control": "private, max-age=2592000, immutable",
      },
    });
  }

  // **What the portal draws, from either store.** A look book put here by the
  // MCP lives in `docs/`; a key image may be a frame the film already holds, in
  // `media/`. One address for both rather than two the pages have to choose
  // between — and `docs/` first, so a file put here on purpose wins.
  // **A file by its name** — `/hla/file/visual-bible.pdf` (2026-09-19). The
  // name is looked up among the film's pinned documents and the spec sheet's
  // files, and then it is the content address below, rules and all. A name
  // nothing on the film answers to is nothing.
  if (rest[0] === "file" && rest.length === 2) {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    const front = await frontOf(env, project, ctx);
    let named = "";
    try { named = decodeURIComponent(rest[1]).toLowerCase(); } catch { named = ""; }
    const hit = [...(front.documents || []), ...(front.camera_files || [])]
      .find((d) => d && d.file && fileNameOf(d) === named);
    if (!hit) return page(404, "No such page", "");
    rest = ["pic", hit.file];
  }

  // **A Drive file he put on the portal** (portaldocs.js): streamed from Drive
  // only while it is on the card, not archived, and this reader may see it.
  if (rest[0] === "drive" && rest.length === 2) {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    const [front, seen] = await Promise.all([frontOf(env, project, ctx), visibleOf(env, project)]);
    const doc = (front.documents || []).find((d) => d && d.source === "drive" && d.drive === rest[1]);
    if (!doc || isArchived(front, `doc:${doc.name}`) || !maySee(seen, "sections", "documents", role)
      || !maySee(seen, "documents", doc.name, role)) return page(404, "No such page", "");
    const { driveFileResponse } = await import("./portaldocs.js");
    return await driveFileResponse(env, doc, request);
  }

  if (rest[0] === "pic" && rest.length === 2) {
    if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Wrong method.");
    // **A hidden document's bytes are refused, not merely unlisted.** Taking a
    // row off the Documents page while its file still answers on a guessable
    // address is the shape of hiding that is worth nothing — the address is in
    // the HTML of every page that was ever served before it was hidden.
    const [front, seen] = await Promise.all([frontOf(env, project, ctx), visibleOf(env, project)]);
    const owning = (front.documents || []).find((d) => d.file === rest[1]);
    if (owning && !maySee(seen, "documents", owning.name, role)) {
      return page(404, "No such page", "");
    }
    // **The same rule for a file off the camera spec sheet.** Hiding the sheet
    // has to take its LUT with it, or the section is hidden and its one file
    // still answers on an address that was in the HTML before it was hidden.
    const onSheet = (front.camera_files || []).find((f) => f.file === rest[1]);
    if (onSheet && !maySee(seen, "sections", "camera", role)) {
      return page(404, "No such page", "");
    }
    // **A file off the spec sheet keeps its own name.** His report, 2026-09-18:
    // the LUT came down as `fc234e59….cube` — the content address, not a
    // name — and a LUT is known by its name; a colourist looks for
    // `fb-500t-slog3.cube`, not for a film's title with a date on it. So it
    // goes out exactly as he uploaded it to Notion, undated.
    if (onSheet && onSheet.name) {
      return await media(env, project, rest[1], request, ["docs", "media"], onSheet.name, true);
    }
    // A pinned document is saved under a name a person can read; the film's
    // own title is asked for only here, never on the four hundred tiles of a
    // mood board.
    const named = owning ? saveAsName(await titleOf(env, project), owning.name, rest[1]) : "";
    return await media(env, project, rest[1], request, ["docs", "media"], named);
  }

  if (rest[0] !== "api") return page(404, "No such page", "");
  const api = rest.slice(1);

  // ---- a view link's shots -------------------------------------------------
  // `/f/<id>/api/view` — the one view this link holds, cut on the server
  // (`lensView`). The reader's own choices ride on the query: `groupBy`,
  // `sort`, `desc`, `q`. He may ask for any of his views by `?code=`.
  if (api.length === 1 && api[0] === "view") {
    if (request.method !== "GET") return problem(405, "Wrong method.");
    const view = lens || (role === "editor" ? await viewByCode(env, project, url.searchParams.get("code")) : null);
    if (!view) return problem(404, "No such view.");
    const text = await lensView(env, project, ctx, view, {
      groupBy: url.searchParams.get("groupBy") || "",
      sortColumn: url.searchParams.get("sort") || "",
      sortDescending: url.searchParams.get("desc") === "1",
      search: url.searchParams.get("q") || "",
    });
    return new Response(text, { headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
  }

  // ---- his views of the film -----------------------------------------------
  // `/f/<id>/api/views` — the Share panel's list. GET lists, POST makes one
  // from a filter, PUT renames or switches one, DELETE removes it for good.
  // An editor's, and never on the share host, where nobody is one.
  if (api.length === 1 && api[0] === "views") {
    const stop = mustEdit(role);
    if (stop) return stop;
    const short = await shortOf(env, project);
    const told = async (extra = {}) => json({
      views: (await viewsOf(env, project)).views.map((v) => viewSaid(v, short, project)), ...extra,
    });
    try {
      if (request.method === "GET") return await told();
      const body = await request.json().catch(() => ({}));
      if (request.method === "POST") {
        const made = await makeView(env, project, body, who.email);
        return await told({ made: viewSaid(made, short, project) });
      }
      const code = String(body.code || url.searchParams.get("code") || "");
      if (request.method === "PUT") {
        if (!(await changeView(env, project, code, body))) return problem(404, "No such view.");
        return await told();
      }
      if (request.method === "DELETE") {
        if (!(await removeView(env, project, code))) return problem(404, "No such view.");
        return await told();
      }
    } catch (error) {
      return problem(400, String(error.message || error));
    }
    return problem(405, "Wrong method.");
  }

  // ---- a pin board's arrangement -------------------------------------------
  // `/f/<id>/api/board/<name>` — what `public/board.js` keeps: where the cards
  // are, the threads, the notes and headings, the clips pulled out.
  //
  // **One board for everyone.** His report and instruction, 2026-09-23: the
  // work he did in one browser was missing on his phone, and "it should save
  // globally for everyone." So a board is one file on the film, read by
  // anybody who may see the film and written by anybody signed in to it — the
  // crew builds it together. The last save wins; `at` is stamped here so a
  // browser can tell a newer board from its own, `by` says whose it was.
  //
  // **The public link is his to open.** Same day: "allow me to choose if it's
  // editable via public link." A link on the share host reads the board, and
  // writes it only while `publicEdit` is on — a switch only an editor sees.
  //
  // **And nothing is lost for good.** Same day: "make sure to have a version
  // history to revert to if someone does something stupid." Before a save
  // replaces the board, the board as it stood is copied into its history when
  // the last copy is ten minutes old, when the save takes away more than a
  // few pieces, or when it is a restore — so a restore can itself be undone.
  // An editor lists the copies and puts one back. The oldest go past 300.
  if (api[0] === "board" && api.length >= 2 && api.length <= 4) {
    const name = api[1];
    if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(name)) return problem(400, "Which board?");
    const { board: boardKey, settings: setKey, history: histPrefix } = boardKeys(project, name);
    const readJson = async (k) => {
      const got = await env.BUCKET.get(k);
      if (!got) return null;
      try { return await got.json(); } catch { return null; }
    };
    // **A Board page's cards are as private as its page.** Halcyon's board
    // has no row of its own (it lives inside a published page) and answers as
    // it always has; one made as a Board page answers only whoever may open
    // that page — the same refusal, word for word, as an address that never
    // existed.
    const front = await frontOf(env, project, ctx);
    const owner = boardSection(front, name);
    const admin = isAdmin(env, who) && !sharing;
    if (owner && !boardOpen(owner, who, admin)) return problem(404, "No such address.");
    const settings = (await readJson(setKey)) || {};
    const isEditor = role === "editor" && !sharing;
    const mayEdit = !sharing || Boolean(settings.publicEdit);
    const jsonType = { httpMetadata: { contentType: "application/json; charset=utf-8" } };

    if (api.length === 3 && api[2] === "settings") {
      if (request.method === "GET") return json({ publicEdit: Boolean(settings.publicEdit) });
      if (request.method !== "PUT") return problem(405, "Wrong method.");
      if (!isEditor) return problem(403, "Editors only");
      let asked;
      try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
      settings.publicEdit = Boolean(asked && asked.publicEdit);
      await env.BUCKET.put(setKey, JSON.stringify(settings), jsonType);
      return json({ publicEdit: settings.publicEdit });
    }

    /**
     * **Who may open it — Only Me, Crew, Anyone with the Link.** His alone to
     * set, from the board's own toolbar. The row on the film's card is what
     * changes; everything that decides who sees the page reads it there.
     */
    if (api.length === 3 && api[2] === "share") {
      if (request.method !== "PUT") return problem(405, "Wrong method.");
      if (!owner) return problem(404, "This board is part of a published page; its Visibility decides.");
      if (!admin) return problem(403, "Only the owner can change access");
      let asked;
      try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
      if (!SHARES.includes(asked && asked.share)) return problem(400, "Only Me, Crew, or Anyone with the Link.");
      owner.share = asked.share;
      await saveFront(env, project, front);
      return json({ share: owner.share });
    }

    /**
     * **A picture or a clip, dropped or pasted onto the board.** Kept on the
     * film by its own contents, like everything a person adds, and handed
     * back as the `pic/` address the board draws it from. Whoever may change
     * the board may add to it.
     */
    if (api.length === 3 && api[2] === "upload") {
      if (request.method !== "PUT" && request.method !== "POST") return problem(405, "Wrong method.");
      if (!mayEdit) return problem(403, "View only");
      const ext = extensionFor(request.headers.get("content-type"), url.searchParams.get("name") || "");
      if (!ext) return problem(415, "Pictures and clips only");
      const moving = ext === "mp4" || ext === "mov";
      const most = moving ? MOST_CLIP : MOST_PICTURE;
      if (Number(request.headers.get("content-length") || 0) > most) return problem(413, moving ? "That clip is over 95 MB." : "That picture is over 25 MB.");
      const bytes = new Uint8Array(await request.arrayBuffer());
      if (!bytes.length) return problem(400, "Nothing arrived.");
      if (bytes.length > most) return problem(413, moving ? "That clip is over 95 MB." : "That picture is over 25 MB.");
      const file = await keepBytes(env, project, ext, bytes);
      return json({ kind: moving ? "clip" : "still", file, src: `pic/${file}` });
    }

    /**
     * **An address, pasted or dropped.** Fetched here — a picture onto the
     * film, a page for its title and picture, a YouTube or Vimeo address for
     * its player — because a browser may not read somebody else's page and
     * a picture left on somebody else's server is a board that goes blank.
     */
    if (api.length === 3 && api[2] === "fetch") {
      if (request.method !== "POST") return problem(405, "Wrong method.");
      if (!mayEdit) return problem(403, "View only");
      let asked;
      try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
      const got = await fetchInto(env, project, asked && asked.url);
      if (!got) return problem(400, "That is not a web address.");
      return json(got);
    }

    /**
     * **Add to Shot** — a still or clip on the board, filed on a shot in the
     * film, when he asks and only then (his question, 2026-09-25). The file
     * is put where the film's own pictures live (`media/`, under the relay's
     * name for it) so the Mac and the phone fetch it like any other, a clip's
     * poster beside it; then the engine files it on the shot as a change log
     * in this person's name. `{src, shot, caption?, hash?, poster?}` — `hash`
     * is the film's whole hash, for a picture that came from the film.
     */
    if (api.length === 3 && api[2] === "attach") {
      if (request.method !== "POST") return problem(405, "Wrong method.");
      if (!isEditor) return problem(403, "Editors only");
      let asked;
      try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
      // The same door a chat's `set_board` `to_shot` goes through (`boards.js`).
      try {
        const got = await fileOnShot(env, project, who, ctx, asked, attachToShot);
        return json({ ok: true, shot: got.shot, said: got.said });
      } catch (error) {
        return problem(error.status || 400, String(error.said || error.message || error));
      }
    }

    /**
     * **The live line.** His ask, 2026-09-25: see each other's changes the
     * moment they happen. A browser holds this open while the board is; the
     * board's room (`src/boardroom.js`) sends every kept change down it, and
     * who else is looking. Whoever may read the board may hold one — what it
     * carries back is only where a person's pointer is.
     */
    if (api.length === 3 && api[2] === "live") {
      const room = roomOf(env, project, name);
      if (!room) return problem(404, "This portal has no live rooms.");
      if (request.headers.get("upgrade") !== "websocket") return problem(426, "A live line only.");
      const mail = String((who && who.email) || "");
      const crewName = mail && ((front.crew || []).find((c) => c && c.email && c.email.toLowerCase() === mail.toLowerCase()) || {}).name;
      const named = sharing ? "Guest" : crewName || (admin ? "Nathaniel" : "") || (mail ? mail.split("@")[0].replace(/[._-]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase()) : "Guest");
      const me = /^[a-z0-9]{6,20}$/.test(url.searchParams.get("me") || "") ? url.searchParams.get("me") : "";
      return room.fetch(new Request(`https://room/live${me ? `?me=${me}` : ""}`, {
        headers: { upgrade: "websocket", "x-board-project": project, "x-board-name": name, "x-board-who": named, "x-board-edit": mayEdit ? "1" : "0" },
      }));
    }

    if (api[2] === "history") {
      if (!isEditor) return problem(403, "Editors only");
      if (api.length === 3) return json({ versions: await boardVersions(env, project, name) });
      const id = api[3];
      if (!/^[0-9A-Za-z-]{10,40}$/.test(id)) return problem(400, "Which version?");
      const old = await env.BUCKET.get(`${histPrefix}${id}.json`);
      if (!old) return problem(404, "No such version.");
      return new Response(old.body, { headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
    }
    if (api.length !== 2) return page(404, "No such page", "");

    if (request.method === "GET" || request.method === "HEAD") {
      return new Response(JSON.stringify({
        board: (await readJson(boardKey)) || {}, mayEdit, isEditor, publicEdit: Boolean(settings.publicEdit),
        // Clips filed on a shot from a chat, still waiting for a poster only a
        // browser can make (`postersOwed` in `boards.js`). Editors only.
        ...(isEditor ? { posters: Object.entries(await postersOwed(env, project)).map(([file, o]) => ({ file, ...o })) } : {}),
        // **Said only where it means something**: a Board page, and him.
        ...(owner ? { share: owner.share || "me", isAdmin: admin } : {}),
      }), {
        headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
      });
    }
    const by = sharing ? "public link" : String((who && who.email) || "");
    const from = /^[a-z0-9]{6,20}$/.test(request.headers.get("x-board-me") || "") ? request.headers.get("x-board-me") : "";
    /**
     * **A change, not the whole board.** Since 2026-09-25 a browser sends what
     * it changed (`public/boardpatch.js`) and the board's room lays it on the
     * board as it stands — so two people working at once both keep their
     * work. Answers the board's new stamp and the one it replaced, which is
     * how a browser knows whether anybody else's change came in between.
     */
    if (request.method === "PATCH") {
      if (!mayEdit) return problem(403, "View only");
      const text = await request.text();
      if (text.length > 2 * 1024 * 1024) return problem(413, "That change is too big to keep.");
      let asked;
      try { asked = JSON.parse(text); } catch { return problem(400, "That is not JSON."); }
      const wrong = opsProblem(asked && asked.ops);
      if (wrong) return problem(400, wrong);
      const room = roomOf(env, project, name);
      if (room) {
        const r = await room.fetch(new Request("https://room/patch", {
          method: "POST", body: JSON.stringify({ ops: asked.ops, by, from }),
          headers: { "content-type": "application/json", "x-board-project": project, "x-board-name": name },
        }));
        return new Response(r.body, { status: r.status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
      }
      // No rooms on this portal: laid on here, as near to the same as it gets.
      const { applyOps } = await import("../public/boardpatch.js");
      const cur = (await readJson(boardKey)) || {};
      const at = await saveBoard(env, project, name, applyOps(cur, asked.ops), by);
      return json({ at, prev: cur.at || "" });
    }
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    if (!mayEdit) return problem(403, "View only");
    const restoring = request.headers.get("x-board-restore") === "1";
    if (restoring && !isEditor) return problem(403, "Editors only");
    const text = await request.text();
    if (text.length > 2 * 1024 * 1024) return problem(413, "That board is too big to keep.");
    let board;
    try { board = JSON.parse(text); } catch { return problem(400, "That is not JSON."); }
    if (!board || typeof board !== "object" || Array.isArray(board)) return problem(400, "That is not a board.");
    // Whole, through the room when there is one, so everybody looking is
    // told and it lands between changes rather than on top of one.
    const room = roomOf(env, project, name);
    if (room) {
      const r = await room.fetch(new Request("https://room/put", {
        method: "POST", body: JSON.stringify({ board, by, from, copy: restoring }),
        headers: { "content-type": "application/json", "x-board-project": project, "x-board-name": name },
      }));
      const got = await r.json();
      return json({ ok: true, at: got.at });
    }
    const at = await saveBoard(env, project, name, board, by, restoring);
    return json({ ok: true, at });
  }

  // ---- what the browser needs to draw the film ---------------------------
  // **The card, for anything that would rather have it as data.** The pages
  // here are drawn on the server and do not use it; it exists so the Mac, the
  // phone or a check can ask what the portal is currently saying about a film.
  if (api.length === 1 && api[0] === "front") {
    // **Less the boards this person may not open** — the card read out is a
    // list of names, and the name of a board he has kept to himself is his.
    const front = await frontOf(env, project, ctx);
    return json({ ...front, sections: sectionsFor(front, who, isAdmin(env, who) && !sharing) });
  }

  if (api.length === 1 && api[0] === "manifest") {
    const got = await env.BUCKET.get(keys.manifest(project));
    if (!got) return problem(404, "That film is not on the relay.");
    return json(await got.json());
  }

  if (api.length === 1 && api[0] === "state") {
    // **A portal with no film has no logs to replay**, whatever stray ones
    // sit under it (SL-1376): a board or a plan page that replayed them
    // would draw a film the rail says is not there.
    if (await filmlessPortal(env, project)) return json({ logs: [] });
    const logs = await listAll(env, keys.logs(project));
    // **Only the ones this worker will actually serve.** Listing a name and
    // then refusing it is how the client came to die on his real film: iCloud
    // had made four conflict copies called `… 2.log`, which are not log names,
    // so `state` offered them and `log/<name>` answered 400. The two have to
    // agree about what a log is, and this is where they agree.
    return json({
      logs: logs
        .map((o) => ({ name: o.key.split("/").pop(), size: o.size }))
        .filter((o) => LOG_NAME.test(o.name)),
    });
  }

  if (api.length === 2 && api[0] === "log") {
    const name = api[1];
    if (!LOG_NAME.test(name)) return problem(400, "That is not a change log.");
    if (request.method === "GET") {
      const got = await env.BUCKET.get(keys.log(project, name));
      if (!got) return problem(404, "No such log.");
      return new Response(got.body, {
        headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
      });
    }
    // **Stage 5 is not built. The refusal is, from today.** A viewer must be
    // told no by the server on the first day, not on the day editing lands —
    // otherwise the day editing lands is the day the rule gets invented, and
    // rules invented late get invented wrong.
    const stop = mustEdit(role);
    if (stop) return stop;
    return problem(501, "Editing in a browser is not built yet.");
  }

  // ---- a shot marked Shot, from the page -----------------------------------
  // `PUT /f/<id>/api/mark {shot: "34A", done: true}` — the portal's one write
  // into the film (his ruling, 2026-09-22: the portal reads on set, and a
  // reader has to be able to say "we got this"). The change goes through the
  // MCP's own engine and lands as a change log in this person's name, so
  // every device takes it in the ordinary way. An editor only.
  if (api.length === 1 && api[0] === "mark") {
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    const stop = mustEdit(role);
    if (stop) return stop;
    let asked;
    try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
    const number = String(asked.shot || "").trim();
    if (!number || number.length > 16) return problem(400, "Which shot?");
    try {
      const said = await markShot(env, project, who, ctx, number, Boolean(asked.done));
      return json({ ok: true, shot: number, done: Boolean(asked.done), said });
    } catch (error) {
      return problem(400, String((error && error.message) || error));
    }
  }

  // ---- a shot moved in a day's shooting order, from the Schedule -----------
  // `PUT /f/<id>/api/shootorder {shot: "34A", day: "<dayId>", position: 3}` —
  // the Schedule's Shooting Order drag (`orderShot` in src/mcp.js). An editor
  // only; the change is kept as a log in this person's name.
  if (api.length === 1 && api[0] === "shootorder") {
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    const stop = mustEdit(role);
    if (stop) return stop;
    let asked;
    try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
    const shot = String((asked && asked.shot) || "").trim();
    const day = String((asked && asked.day) || "").trim();
    // **A place is optional** (Ref 1570): a shot picked onto a day from its Day
    // cell goes to the end of that day's order, and `day: ""` takes it off
    // every day — the Mac's Day menu and Not Scheduled. A place that is named
    // still has to be a place.
    const named = asked && asked.position !== undefined && asked.position !== null;
    const position = named ? Number(asked.position) : 0;
    if (!shot || shot.length > 16) return problem(400, "Which shot?");
    if (day.length > 64 || (!day && named)) return problem(400, "Which day?");
    if (named && (!Number.isInteger(position) || position < 1 || position > 100000)) return problem(400, "Which place?");
    try {
      const said = await orderShot(env, project, who, ctx, { shot, day, position });
      return json({ ok: true, said });
    } catch (error) {
      return problem(400, String((error && error.message) || error));
    }
  }

  // ---- the Diagrams page draws ---------------------------------------------
  // `PUT /f/<id>/api/diagram {scene, ops: [{op, made}]}` — a batch of plan
  // edits, kept as one change log in this person's name (`diagramEdit` in
  // src/mcp.js). An editor only; a viewer or a link holder is told no here,
  // whatever the page drew.
  //
  // **The public link is his to open, for plans too.** Same ruling as the pin
  // board's ("allow me to choose if it's editable via public link"), asked
  // again 2026-10-11 for the Diagrams page: a link on the share host reads the
  // plans, and draws on them only while the film's `publicEdit` is on — a
  // switch only an editor sees (`api/diagram/settings`). **On by default**
  // (his answer 2026-10-18): only a stored `publicEdit: false` is off. Off, a
  // link holder is told no. Each browser signs its edits with its own
  // random name (`x-diagram-me`), so two people drawing at once are two
  // devices to the engine, not one edit dropped as the other's duplicate.
  if (api.length === 2 && api[0] === "diagram" && api[1] === "settings") {
    const setKey = diagramSettingsKey(project);
    const read = async () => {
      const got = await env.BUCKET.get(setKey);
      if (!got) return {};
      try { return await got.json(); } catch { return {}; }
    };
    if (request.method === "GET") {
      const publicEdit = (await read()).publicEdit !== false;
      return json({ publicEdit, linkMay: publicEdit && sharing && role === "viewer" });
    }
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    if (role !== "editor" || sharing) return problem(403, "Editors only");
    let asked;
    try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
    const set = { ...(await read()), publicEdit: Boolean(asked && asked.publicEdit) };
    await env.BUCKET.put(setKey, JSON.stringify(set), { httpMetadata: { contentType: "application/json; charset=utf-8" } });
    return json({ publicEdit: set.publicEdit });
  }
  // **His list of what link visitors drew** (2026-10-17): who, when, what,
  // and the server's own edits that take each batch back. An editor's alone.
  if (api.length === 2 && api[0] === "diagram" && api[1] === "linkedits") {
    const stop = mustEdit(role);
    if (stop) return stop;
    if (sharing) return problem(403, "Editors only");
    const base = diagramSettingsKey(project).replace(/diagram\.settings\.json$/, "");
    if (request.method === "GET") return json({ edits: await listLinkEdits(env.BUCKET, base) });
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
    return (await markLinkEdit(env.BUCKET, base, asked && asked.key, asked && asked.undone)) ? json({ ok: true }) : problem(404, "No such entry.");
  }
  if (api.length === 1 && api[0] === "diagram") {
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    // Asked of the bucket on every batch, never remembered: the moment he
    // switches Editable by Link off, the next batch is refused.
    const viaLink = await linkMayDraw(env, project, role, sharing);
    const stop = viaLink ? null : mustEdit(role);
    if (stop) return stop;
    let asked;
    try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || !Array.isArray(asked.ops) || !asked.ops.length) return problem(400, "Say what to change.");
    if (asked.ops.length > (viaLink ? 300 : 400)) return problem(413, "Too many edits at once.");
    const me = /^[a-z0-9]{6,20}$/.test(request.headers.get("x-diagram-me") || "") ? request.headers.get("x-diagram-me") : "anon";
    if (viaLink && !(await linkMayWrite(env, project, `${request.headers.get("cf-connecting-ip") || "here"}/${me}`))) {
      return problem(429, "Too many changes at once. Wait a minute and try again.");
    }
    try {
      const visitor = viaLink ? { email: `public-link/${me}`, via: "link" } : who;
      const said = await diagramEdit(env, project, visitor, ctx, { scene: String(asked.scene || ""), ops: asked.ops, link: viaLink }, viaLink);
      if (viaLink) {
        const base = diagramSettingsKey(project).replace(/diagram\.settings\.json$/, "");
        const keeping = keepLinkEdit(env.BUCKET, base, { me, scene: asked.scene, ops: asked.ops, labels: asked.labels, said })
          .catch((error) => console.error("could not keep a link edit:", String(error)));
        if (ctx && ctx.waitUntil) ctx.waitUntil(keeping); else await keeping;
        delete said.undo;
      }
      return json(said);
    } catch (error) {
      return problem(400, String((error && error.message) || error));
    }
  }

  // `PUT /f/<id>/api/picture?name=plan.jpg` — a picture chosen from the
  // computer for a plan (the Mac's Picture tool, Choose File…). Kept where
  // the film's own pictures live (`media/`, by its hash — the relay's name
  // for it) so the Mac and the phone fetch it like any other; the page then
  // lays it on the plan with the engine's `picture` edit. An editor only.
  if (api.length === 1 && api[0] === "picture") {
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    const stop = (await linkMayDraw(env, project, role, sharing)) ? null : mustEdit(role);
    if (stop) return stop;
    const ext = extensionFor(request.headers.get("content-type"), url.searchParams.get("name") || "");
    if (!ext || !["png", "jpg", "jpeg", "webp", "gif", "heic"].includes(ext)) return problem(415, "Pictures only");
    if (Number(request.headers.get("content-length") || 0) > MOST_PICTURE) return problem(413, "That picture is over 25 MB.");
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (!bytes.length) return problem(400, "Nothing arrived.");
    if (bytes.length > MOST_PICTURE) return problem(413, "That picture is over 25 MB.");
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
    const file = `${hash.slice(0, 32)}.${ext}`;
    await env.BUCKET.put(keys.inFolder(project, "media", file), bytes, { httpMetadata: { contentType: ext === "png" ? "image/png" : "image/jpeg" } });
    return json({ hash, file, ext, bytes: bytes.length });
  }

  // ---- the film changed ----------------------------------------------------
  // `GET /f/<id>/api/live` (a websocket) — the relay's room for this film,
  // the same line his Mac and phone listen on, which carries one word when
  // any of them (or this portal) keeps a change. The page reads again at
  // once instead of on its next look. Anybody who may open the film may
  // listen: it carries nothing but "logs".
  if (api.length === 1 && api[0] === "live") {
    if ((request.headers.get("upgrade") || "").toLowerCase() !== "websocket") return problem(426, "A websocket, please.");
    if (!env.ROOMS) return problem(404, "No live line here.");
    try {
      const room = env.ROOMS.get(env.ROOMS.idFromName(project));
      return await room.fetch(new Request("https://rooms/live", { headers: { upgrade: "websocket" } }));
    } catch {
      return problem(503, "The live line is not answering.");
    }
  }

  // ---- the short name ------------------------------------------------------
  // `PUT /f/<id>/api/short {short}` — the Share panel's own field. An editor
  // only; a new name keeps the old as an alias, so nothing sent out breaks.
  if (api.length === 1 && api[0] === "short") {
    if (request.method !== "PUT") return problem(405, "Wrong method.");
    const stop = mustEdit(role);
    if (stop) return stop;
    let asked;
    try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
    const wanted = String(asked.short || "").trim().toLowerCase();
    if (!SHORT.test(wanted)) return problem(400, "Use 2-24 letters or digits");
    if (RESERVED.has(wanted)) return problem(400, "That name is the hub's own.");
    const got = await claimShort(env, project, wanted);
    if (!got) return problem(409, "Name taken");
    return json({ project, short: got });
  }

  // ---- who may do what ---------------------------------------------------
  if (api.length === 1 && api[0] === "people") {
    if (request.method === "GET") {
      const stop = mustEdit(role);
      if (stop) return stop;
      return json(await peopleOf(env, project));
    }
    if (request.method === "PUT") {
      const stop = mustEdit(role);
      if (stop) return stop;
      return await putPeople(request, env, project, who);
    }
    return problem(405, "Wrong method.");
  }

  return problem(404, "No such address.");
}

// --------------------------------------------------------------- who you are

/**
 * Work out who is asking, by the three ways and in this order.
 *
 * Returns `{ email, via }` or null. `via` is worth carrying: "why does he see
 * a film his director cannot" is nearly always answered by it.
 */
/** Every page the Library holds, by key: the program's screens, the built-in pages, and his. */
function libraryKeys(front) {
  return new Set([...APP_ROWS, "script", "bible", "camera", "people", "documents",
    ...(front.sections || []).map((one) => one.slug)]);
}

/**
 * **The Library, many at once** — `{ keys, action, to? }` applied to every key
 * in one save (the Library's toolbar and menu; lifted out of the route on
 * 2026-10-05 so the Projects Console's door arranges through exactly the same
 * rules). A string of single posts would each read the card, change one thing
 * and write it back, and the last would win over the others. **Set, not
 * flip**: every action says where things end up, so doing it twice is the
 * same as doing it once. The four Visibility ones are an administrator's
 * (`admin`), as they are everywhere else. Keys that are not this film's pages
 * or documents are dropped, not refused, as the page has always done.
 *
 * Throws a `Refusal` (with `status`, and `more` for the page's second line);
 * answers `{ changed, of }`.
 */
async function arrangeLibrary(env, project, front, ask, admin) {
  const known = libraryKeys(front);
  if (!ask || typeof ask !== "object") throw new Refusal("Not a list");
  // **Pinned and Private are the two settings** (his ruling, 2026-10-03):
  // `pin`/`unpin` say whether a page has a row in the sidebar,
  // `private`/`public` whether only an editor may see it. The older
  // words are kept as aliases, so a page that still sends them works.
  const ALIAS = { "sidebar-on": "pin", "sidebar-off": "unpin", "links-hide": "private", "links-show": "public" };
  const sent = String(ask.action || "");
  const action = ALIAS[sent] || sent;
  const to = String(ask.to || "");
  const keys = [...new Set((Array.isArray(ask.keys) ? ask.keys : []).map(String))].slice(0, 300)
    .filter((k) => (k.startsWith("doc:") ? (front.documents || []).some((d) => d.name === k.slice(4)) : known.has(k)));
  const visibility = ["private", "public"].includes(action);
  if (visibility && !admin) throw Object.assign(new Refusal("No Access", "admin", 403));
  if (!visibility && !["pin", "unpin", "archive", "unarchive", "shelf", "icon", "rename"].includes(action)) throw new Refusal("Not an action");
  /**
   * **A pinned document, renamed** (`to` is the new name, `keys` the one
   * `doc:<name>`). The Projects Console and the iPhone ask here; a page has
   * its own rename route. Every list that knows the document by name follows
   * (`renameDocument`).
   */
  if (action === "rename") {
    if (keys.length !== 1 || !keys[0].startsWith("doc:")) throw new Refusal("Rename one document", "keys", 400);
    const visible = await visibleOf(env, project);
    const got = renameDocument(front, visible, keys[0].slice(4), to);
    if (!got.ok) throw new Refusal(got.why, "name", got.why.includes("already") ? 409 : 400);
    if (got.touched) await saveVisible(env, project, visible);
    await saveFront(env, project, front);
    return { changed: 1, of: 1, renamed: got.name };
  }
  if (action === "shelf" && !shelfIdFor(front, to)) throw new Refusal("No such shelf", "shelf", 404);
  // **An icon is one of the set, or nothing** (which goes back to the default).
  if (action === "icon" && to && !ICON_CHOICES.includes(to)) throw new Refusal("No such icon", "icon", 404);
  let changed = 0;
  let seen = null;
  if (visibility || action === "archive" || action === "unarchive") seen = { ...(await visibleOf(env, project)) };
  const flip = (list, key, on) => {
    const now = new Set(list || []);
    const was = now.has(key);
    if (on) now.add(key); else now.delete(key);
    if (was !== now.has(key)) changed += 1;
    return [...now];
  };
  for (const key of keys) {
    const doc = key.startsWith("doc:") ? key.slice(4) : "";
    const sec = (front.sections || []).find((one) => one.slug === key);
    if (action === "icon") { setIcon(front, key, to); changed += 1; }
    else if (action === "shelf") { setShelf(front, key, to, doc || (sec ? sec.name : key), doc ? "doc" : "page", sec ? sec.type : ""); changed += 1; }
    else if (action === "pin") { if (setOnSidebar(front, key, true)) changed += 1; }
    else if (action === "unpin") { setOnSidebar(front, key, false); changed += 1; }
    else if (action === "archive") { if (setArchived(front, key, true, seen)) changed += 1; }
    else if (action === "unarchive") { if (setArchived(front, key, false, seen)) changed += 1; }
    else if (action === "public" || action === "private") {
      const show = action === "public";
      if (sec && sec.type === "board") {
        const want = show ? "link" : sec.share === "link" ? "crew" : sec.share;
        if (want !== sec.share) { sec.share = want; changed += 1; }
      } else if (doc) seen.documents = flip(seen.documents, doc, !show);
      else seen.sections = flip(seen.sections, key, !show);
    }
  }
  await saveFront(env, project, front);
  if (seen) await saveVisible(env, project, { ...seen, version: 1 });
  return { changed, of: keys.length };
}

/**
 * **What Viewers See, saved from what is ticked.** The Visibility form's save
 * (Ref 1154), lifted out of the route on 2026-10-05 so the Projects Console's
 * door saves through exactly the same rules. `ticked` holds a Set per list —
 * `sections`, `crew`, `documents`, `contact` — of what is ticked; a list left
 * out is kept as it stands (the form always sends all four).
 *
 * **The store keeps what is hidden, and a form only sends what is ticked** —
 * so hidden is everything offered that did not come back. Answers what was
 * saved.
 */
async function saveViewersSee(env, project, front, visible, ticked) {
  const hide = (kind, keys) => keys.filter((k) => !ticked[kind].has(k));
  // **`contact` keeps what was ticked, not what was not** — the one list
  // here that runs opt-in rather than opt-out. See `mayContact`.
  const keep = (kind, keys) => keys.filter((k) => ticked[kind].has(k));
  // **Named once.** A section folded onto a built-in page — the Visual
  // Bible is one — carries a slug that is already in this list, and listing
  // it twice would write the same name twice into what a film hides.
  const boardRows = (front.sections || []).filter((one) => one.type === "board");
  const sectionKeys = [...new Set([
    "shotlist", "script", "diagrams", "locations", "schedule", "bible", "boards", "camera", "people", "documents",
    ...(front.sections || []).filter((one) => one.type !== "board").map((one) => one.slug).filter(Boolean),
  ])];
  // **Boards keep their own switch.** Ticked is Anyone with the Link;
  // unticked takes a linked board back to the crew, and leaves one that
  // is his alone, his alone.
  if (ticked.sections && boardRows.length) {
    const on = ticked.sections;
    let moved = false;
    for (const one of boardRows) {
      const want = on.has(one.slug) ? "link" : one.share === "link" ? "crew" : one.share;
      if (want !== one.share) { one.share = want; moved = true; }
    }
    if (moved) await saveFront(env, project, front);
  }
  // Every shoot's people, not only the next shoot's (Ref 1410).
  const crewNames = everyone(front).map((c) => c.name).filter(Boolean);
  const docNames = (front.documents || []).map((d) => d.name).filter(Boolean);
  // **For Me rides in the same form**, under `me-…` names. A form from
  // before it had no such fields, and saving one must not unhide
  // everything he had hidden for himself — so no `for` field, no change.
  // **For Me is retired**: what he had hidden there is kept, never rewritten from here.
  const me = visible.me;
  const out = {
    version: 1,
    sections: ticked.sections ? hide("sections", sectionKeys) : visible.sections,
    crew: ticked.crew ? hide("crew", crewNames) : visible.crew,
    documents: ticked.documents ? hide("documents", docNames) : visible.documents,
    contact: ticked.contact ? keep("contact", crewNames) : visible.contact,
    me,
  };
  await saveVisible(env, project, out);
  return out;
}

/**
 * **The Projects Console's door**, 2026-09-15.
 *
 * The console's rule is that it never writes into a film or the portal
 * itself: every change goes through a door the hub provides. This is that
 * door — one token, no browser session, and the same records the hub's own
 * pages read and write (`people.json`, `visible.json`, `down.json`), in the
 * same shapes, through the same functions. Nothing the console can do here is
 * a thing the Share page or the Visibility panel could not.
 *
 * **A token, the relay's way.** `CONSOLE_TOKEN` is a secret on the hub, set
 * once (`hub/setup.sh`) to the same value as the relay's `TOKEN`, so the
 * console carries one password in its Keychain rather than two. Compared over
 * the whole length, as the relay compares its own, so how long a wrong answer
 * takes says nothing about how much of it was right.
 *
 * **Chosen over a wrangler script beside `refresh.py`** because a script
 * writing straight into the bucket would skip the etag guard `savePeople`
 * keeps — a link switched off from the console at the moment he ticks one on
 * the Share page would lose one of the two — and would need a Cloudflare
 * login on whichever Mac the console runs on. A route needs a token and
 * nothing else.
 *
 *   GET  /console/<film>            the switchboard's readout, in one call
 *   GET  /console/<film>/down       { down, since, by }
 *   PUT  /console/<film>/down       { "down": true|false, "by": "console" }
 *   GET  /console/<film>/people     people.json, as the Share page reads it, and its `etag`
 *   PUT  /console/<film>/access     { add, role, remove, replace, link, password, if_match } — the Share popover's People tab
 *   PUT  /console/<film>/link       { "off": true|false, "hash": "…" }  — every link when no hash is named
 *   GET  /console/<film>/visible    visible.json
 *   PUT  /console/<film>/visible    { "sections": […], "crew": […], "documents": […] } — a list named is replaced, one left out is kept
 *   GET  /console/<film>/viewers    What Viewers See: each page, person and document with its switches
 *   PUT  /console/<film>/viewers    { "sections", "crew", "documents", "contact" } — what is SHOWN, saved as the panel saves
 *   GET  /console/<film>/library    each page's pinned / private / archived, and each document's
 *   PUT  /console/<film>/library    { "keys": […], "action": "pin|unpin|private|public|archive|unarchive|icon|shelf", "to"? } — `to` is the icon ("" for the default) or the shelf
 *   PUT  /console/<film>/shelves    { "action": "add|rename|remove|move|order", "shelf"?, "name"?, "to"?, "ids"? } — the Library's categories (`editShelves`)
 *   POST /console/<film>/act/order  the whole sidebar, `group` fields, as the rail's own drag sends it
 *   POST /console/<film>/act/add    a new page, the Add menu's own fields (name, type, url, head, file)
 *   POST /console/<film>/act/<page> { rename } — the page menu's Rename
 *   POST /console/<film>/shoot      { "date", "name", "section"?, "pickups"?, "version"?, "preview"? } — a new shoot's section and day, through the connector's new_shoot (SL-1402)
 *   GET  /console/<film>/follow/<page>   whether the page follows a Google Doc, which, and when it last redrew
 *   PUT  /console/<film>/follow/<page>   { "on"?, "doc"?, "credit"?, "refresh"? } — the page menu's Follow Google Doc (`docfollow.js`)
 */

/**
 * **Change logs written into a portal with no film**, said to the console
 * (SL-1376). Every page ignores them, so nothing breaks; but a chat or a Mac
 * put them there meaning to change a film, and somebody should know. Empty
 * when there are none, so a readout without the field is a portal with none.
 */
async function strays(env, project) {
  const n = await strayLogs(env, project);
  if (!n) return {};
  const them = n === 1 ? "it" : "them";
  return {
    stray_logs: n,
    warning: `${n} change log${n === 1 ? " was" : "s were"} written into this portal, which has no film. Nothing reads ${them}; move ${them} to parked/ in the bucket.`,
  };
}

/**
 * Whether a request carries the console's token, compared over the whole
 * length. The console's door and the phone's (`phoneDoor`) both ask it.
 */
function carriesToken(request, expected) {
  const given = (request.headers.get("authorization") || "").replace(/^Bearer /, "");
  let difference = given.length === expected.length ? 0 : 1;
  for (let at = 0; at < expected.length && at < given.length; at += 1) {
    difference |= given.charCodeAt(at) ^ expected.charCodeAt(at);
  }
  return difference === 0;
}

async function consoleDoor(request, env, url, ctx) {
  const expected = env.CONSOLE_TOKEN;
  if (!expected) return problem(503, "No console token is set on the hub.");
  if (!carriesToken(request, expected)) return problem(401, "Not the console's token.");

  const parts = url.pathname.split("/").filter(Boolean);
  const method = request.method;
  const sent = async () => {
    const text = await request.text();
    if (text.length > MAX_PEOPLE) throw new Error("too long");
    return JSON.parse(text);
  };

  // **The record**, one per project — see `recordDoor`. Keyed on the
  // project's Notion page id, which is the one id every system agrees on,
  // and a different key from a film's relay id, so the two never collide.
  // **The Studio's mailbox** — the phone's way to the Mac without Tailscale
  // (studio.js): the Mac's snapshot of agents, drives and doors, and the
  // calls the phone would have made on the transport, answered from here.
  if (parts[1] === "studio") return await studioDoor(request, env, parts, ctx);

  if (parts[1] === "records" || parts[1] === "record" || parts[1] === "pending") {
    return await recordDoor(request, env, parts, method, sent);
  }

  // POST /console/rebuild/<film>/<slug> { markdown, from } — a hand-made page made a
  // normal one, its old document kept beside it (`rebuild.js`, Ref 1543).
  // `hub/rebuilt.sh` sends the pages in `hub/rebuilt/` after each deploy.
  if (parts[1] === "rebuild") {
    if (parts.length !== 4) return problem(404, "No such door.");
    if (method !== "POST") return problem(405, "Wrong method.");
    if (!PROJECT.test(parts[2])) return problem(404, "No such film.");
    if (!(await hasFilm(env, parts[2])) && !(await portalOf(env, parts[2]))) return problem(404, "No such film.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "Send { markdown }."); }
    if (!asked || typeof asked.markdown !== "string") return problem(400, "Send { markdown }.");
    const said = await rebuildPage(env, parts[2], parts[3], asked.markdown, asked.from);
    return json(said, said.refused ? 409 : 200);
  }

  // GET /console/portals — every portal with no film behind it, for the
  // refresh to walk (`hub/refresh.py` has no way to list the bucket itself).
  if (parts[1] === "portals") {
    if (parts.length !== 2) return problem(404, "No such door.");
    if (method !== "GET") return problem(405, "Wrong method.");
    return json({ portals: await everyPortal(env) });
  }

  // **A minted project's Notion page names its ID here too** (2026-10-17).
  // One ID keeps a new project's portal, people and links under the
  // project's own ID, and `/f/<notion page>` already sends a visitor there;
  // a console ask that names the project by its Notion page (Create Portal,
  // the Mac's `_relay_of`) is answered at the same place, so the link it
  // hands out opens. Only pages the ID map holds are moved, and nothing has
  // ever lived under one of those, so every existing project is untouched.
  const named = parts[1] || "";
  const project = PAGE.test(named) ? await keyOfPage(env, named) : named;
  if (!PROJECT.test(project)) return problem(404, "No such film.");
  const what = parts[2] || "";

  // **A portal carried into its film, on request** — `POST /console/<page
  // id>/portal/carry {relay}` (2026-09-18). The carry runs on its own when
  // the console's record names the film's relay id, and it never ran for
  // Harbour Light Affair: the console wrote the record three seconds after
  // the film was made, before the film's first sync had given it an id, and
  // did not write again. So the two portals stood side by side for a day.
  // This door lets anything that knows both ids — `hub/refresh.py`, which
  // reads the project page every film names, or the console once it learns
  // the id — ask for the carry itself. Refused unless the mark stands and
  // the relay id holds a film that has synced, so it can never fold a
  // portal into nothing.
  if (what === "portal" && parts[3] === "carry" && parts.length === 4) {
    if (method !== "POST") return problem(405, "Wrong method.");
    if (!PAGE.test(project)) return problem(400, "A portal on its own is keyed on the project's page id.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    const relay = String(asked.relay || "");
    if (!PROJECT.test(relay)) return problem(400, "Say the film's relay id.");
    if (relay === project) return problem(400, "A portal cannot be carried into itself.");
    if ((await oneIdOn(env)).on) return problem(409, "One ID: a portal stays where it is, and its film is made under the project's own ID.");
    if (!(await portalOf(env, project))) return problem(404, "Not a portal on its own.");
    if (!(await hasFilm(env, relay))) return problem(409, "No film has synced under that id.");
    const carried = await carryPortal(env, project, relay);
    return json({ page: project, relay, carried });
  }

  // **The film's short name** — `GET /console/<id>/short` says it, `PUT
  // /console/<id>/short {short}` sets it (2026-09-19). Setting a new name
  // keeps the old one as an alias: a link somebody was sent goes on working.
  if (what === "short" && parts.length === 3) {
    if (method === "GET") {
      const short = await ensureShort(env, project, await titleOf(env, project));
      return json({ project, short, url: short ? `https://${SHARE_HOST_PREFIX}${apexHost(hostAsked(request, url, env))}/${short}` : "" });
    }
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    const wanted = String(asked.short || "").trim().toLowerCase();
    if (!SHORT.test(wanted)) return problem(400, "Use 2-24 letters or digits");
    if (RESERVED.has(wanted)) return problem(400, "That name is the hub's own.");
    const got = await claimShort(env, project, wanted);
    if (!got) return problem(409, "Name taken");
    return json({ project, short: got, url: `https://${SHARE_HOST_PREFIX}${apexHost(hostAsked(request, url, env))}/${got}` });
  }

  // **Follow Google Doc** — the page menu's switch, from the console
  // (`docfollow.js`, 2026-10-10). PUT is also how a page is first pointed at
  // its doc: `{ doc, credit, on }`.
  if (what === "follow" && parts.length === 4) {
    const slug = parts[3];
    if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) return problem(404, "No such page.");
    if (method === "GET") {
      const state = await followStateOf(env, project, slug);
      return state ? json({ project, slug, connected: driveReady(env), ...state }) : problem(404, "That page does not follow a doc.");
    }
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Send { on, doc, credit, refresh }.");
    const got = await setFollow(env, project, slug, {
      on: asked.on === undefined ? undefined : Boolean(asked.on),
      doc: asked.doc, credit: asked.credit, refresh: Boolean(asked.refresh),
    });
    if (!got.ok && got.status !== 502) return problem(got.status || 400, got.said);
    return json({ project, slug, connected: driveReady(env), ...got }, got.ok ? 200 : got.status || 400);
  }

  // **The portal's own editing, from the console** — `POST
  // /console/<film>/act/…` (2026-10-10). His ask: *"adding editing
  // capabilities but not rebuilding them."* So nothing here knows how a page
  // is added, renamed or ordered: the fields are handed to the very route the
  // signed-in page posts to, as him (`CONSOLE_ACT`, read by `identify`), the
  // way `phoneWeb` hands the phone's reads on. Only these three writes, and
  // only their own fields, so the token opens nothing else of the page's.
  if (what === "act") {
    if (method !== "POST") return problem(405, "Wrong method.");
    if (parts.length !== 4) return problem(404, "No such door.");
    if (!owners(env).length) return problem(503, "No owner is set on the hub.");
    if (!(await hasFilm(env, project)) && !(await portalOf(env, project))) return problem(404, "No such film.");
    const verb = parts[3];
    const FIELDS = { order: ["group"], add: ["name", "type", "url", "head", "file", "source", "notion", "markdown"] };
    const allowed = FIELDS[verb] || (/^[a-z0-9][a-z0-9-]{0,63}$/.test(verb) ? ["rename"] : null);
    if (!allowed) return problem(404, "No such door.");
    // **A form, or the same fields as JSON** — the Mac sends a form, the
    // iPhone's Console its usual JSON: `{ name, type, … }`, `groups` as
    // `[{ name, rows }]` for the order, and a file as `{ name, type, base64 }`.
    let form;
    if (/application\/json/.test(request.headers.get("content-type") || "")) {
      let said;
      try { said = await request.json(); } catch { return problem(400, "That is not JSON."); }
      if (!said || typeof said !== "object" || Array.isArray(said)) return problem(400, "Send the fields.");
      form = new FormData();
      for (const one of Array.isArray(said.groups) ? said.groups : []) {
        // A comma in a row's name (a link called "Dailies, day 1") is sent as %2C, as the rail's own drag does.
        const rows = (Array.isArray(one && one.rows) ? one.rows : []).map((r) => String(r).replace(/,/g, "%2C")).join(",");
        form.append("group", `${String((one && one.name) || "")}\n${rows}`);
      }
      for (const [key, value] of Object.entries(said)) {
        if (key === "groups") continue;
        if (key === "file" && value && typeof value === "object") {
          let bytes;
          try { bytes = Uint8Array.from(atob(String(value.base64 || "")), (c) => c.charCodeAt(0)); } catch { return problem(400, "That file did not arrive whole."); }
          if (bytes.length > 50 * 1024 * 1024) return problem(413, "That file is too big to send from here.");
          form.append("file", new File([bytes], String(value.name || "file"), { type: String(value.type || "application/octet-stream") }));
        } else if (typeof value === "string") form.append(key, value);
      }
    } else {
      try { form = await request.formData(); } catch { return problem(400, "Send a form."); }
    }
    const body = new FormData();
    for (const [key, value] of form.entries()) if (allowed.includes(key)) body.append(key, value);
    if (!FIELDS[verb] && body.get("rename") === null) return problem(400, "Send { rename }.");
    /**
     * **A built-in page, renamed** (his ask, 2026-10-10: *"rename any page
     * that's on the portal"*). Shot List, Script, Diagrams and the rest are not
     * his sections, so the page route has nothing to rename: the portal's own
     * name for one goes in `front.labels`, which every rail and heading reads.
     * Its address stays, so nothing already sent breaks. An empty name puts the
     * built-in one back.
     */
    if (!FIELDS[verb] && (RECORD_PAGES.has(verb) || PROGRAM_PAGES.has(verb))) {
      const front = await frontOf(env, project, ctx);
      const called = String(body.get("rename") || "").replace(/\s+/g, " ").trim().slice(0, 60);
      const others = new Set([
        ...[...RECORD_PAGES.entries(), ...PROGRAM_PAGES.entries()].filter(([at]) => at !== verb).map(([at, n]) => (front.labels || {})[at] || n),
        ...(front.sections || []).filter((one) => one.slug !== verb).map((one) => one.name).filter(Boolean),
      ].map((n) => String(n).toLowerCase()));
      let why = "";
      if (called && others.has(called.toLowerCase())) why = `${called} is already a page on this film.`;
      else {
        const labels = { ...(front.labels || {}) };
        if (called && called !== (RECORD_PAGES.get(verb) || PROGRAM_PAGES.get(verb))) labels[verb] = called;
        else delete labels[verb];
        front.labels = labels;
        front.updated = new Date().toISOString();
        await saveFront(env, project, front);
      }
      const now = await frontOf(env, project, ctx);
      return json({ project, ok: !why, ...(why ? { why, problem: why } : { href: `/f/${project}/${verb}` }), ...sidebarStateOf(now) }, why ? 422 : 200);
    }
    const host = hostAsked(request, url, env);
    const apex = host.startsWith(MCP_HOST_PREFIX) ? host.slice(MCP_HOST_PREFIX.length) : host;
    const asked = new Request(new URL(`/f/${project}/${verb}`, `${url.protocol}//${apex}`), {
      method: "POST", body, headers: { accept: "application/json" },
    });
    CONSOLE_ACT.add(asked);
    const answer = await route(asked, env, ctx);
    const kind = answer.headers.get("content-type") || "";
    let said = { ok: answer.status < 400 };
    if (answer.status === 303 || answer.status === 302) said.href = new URL(answer.headers.get("location"), "https://x").pathname;
    else if (kind.includes("json")) {
      const got = await answer.json().catch(() => ({}));
      said = { ok: Boolean(got.ok), ...(got.href ? { href: got.href } : {}), ...(got.error ? { why: got.error } : {}) };
    } else if (answer.status >= 400) {
      // A refusal is a page: its heading and its one line are the reason.
      const text = await answer.text();
      const head = (text.match(/<div class="wordmark">([^<]*)<\/div>/) || [])[1] || "";
      const line = (text.match(/<p class="empty">([^<]*)<\/p>/) || [])[1] || "";
      said.why = [head, line].filter(Boolean).join(". ").replace(/&#39;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&") || `The portal said ${answer.status}.`;
    }
    const front = await frontOf(env, project, ctx);
    return json({ project, ...said, ...(said.why ? { problem: said.why } : {}), ...sidebarStateOf(front) }, said.ok ? 200 : 422);
  }

  if (parts.length > 3) return problem(404, "No such door.");

  // **A new shoot's section and day** — `POST /console/<film>/shoot` (SL-1402,
  // the shot-list step of the console's New Shoot). Body `{date, name,
  // section?, pickups?, version?, preview?}`. The connector's `new_shoot`
  // does the work (`consoleShoot`, mcp.js), so the change is one ordinary
  // change log and the relay tells his devices. 200 with `ok: true` and the
  // steps, made or (with `preview`) only said; 422 with `ok: false` and `why`
  // when it refuses, and then nothing was changed.
  if (what === "shoot") {
    if (method !== "POST") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Send {date, name}.");
    if (!(await hasFilm(env, project))) return problem(404, "No such film.");
    try {
      return json({ ok: true, project, ...(await consoleShoot(env, project, ctx, asked)) });
    } catch (error) {
      if (!error || !error.said) throw error;
      return json({ ok: false, project, why: error.said, problem: error.said }, 422);
    }
  }

  // **A portal with no film behind it** — `PUT /console/<page id>/portal
  // {title}` marks the project's own address as a portal (2026-09-16). The
  // id is the project's Notion page id, which is what `/f/<page id>` already
  // stands for, so nothing has to be minted and nothing has to be remembered
  // anywhere but here. Refused over a film that has synced: the film's own
  // page is that already. Taking one down again is the relay's whole-prefix
  // delete, the same door the console uses for a film's page.
  if (what === "portal") {
    if (method === "GET") {
      const portal = await filmlessPortal(env, project);
      return portal ? json({ ...portal, ...(await strays(env, project)) }) : problem(404, "Not a portal on its own.");
    }
    if (method !== "PUT") return problem(405, "Wrong method.");
    if (!PAGE.test(project)) return problem(400, "A portal on its own is keyed on the project's page id.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    const title = String(asked.title || "").trim();
    if (!title) return problem(400, "Say the project's name.");
    // **A portal already, stray logs and all, is renamed rather than refused**
    // (SL-1376): logs under a mark with no manifest are not a film.
    if (!(await filmlessPortal(env, project)) && (await hasFilm(env, project))) {
      return problem(409, "That id holds a film; its page is the film's.");
    }
    // A minted project's portal lives under its ID; the mark and the first
    // card name its Notion page, which is where its words come from.
    let notionPage = named;
    if (named === project) {
      try {
        const got = await env.BUCKET.get(`r/${project}/record.json`);
        if (got) notionPage = notionOf(await got.json(), project) || project;
      } catch { notionPage = project; }
    }
    const portal = await savePortal(env, project, { title, by: asked.by || "console", page: notionPage });
    // **A first card, so the page says where its words come from** before the
    // first refresh has run. The refresh rewrites it; nothing here is kept
    // that it would not write itself.
    const stored = await frontOf(env, project);
    if (!stored.source) {
      await saveFront(env, project, { ...stored, source: `notion:${notionPage}`, linked: "link" });
    }
    return json({ ...portal, url: `https://${apexHost(hostAsked(request, url, env))}/f/${project}` });
  }

  if (what === "") {
    if (method !== "GET") return problem(405, "Wrong method.");
    const [title, down, tagged, visible, portal] = await Promise.all([
      titleOf(env, project), downOf(env, project), peopleWithTag(env, project), visibleOf(env, project),
      filmlessPortal(env, project),
    ]);
    const people = tagged.list;
    const share = `https://${SHARE_HOST_PREFIX}${apexHost(hostAsked(request, url, env))}/f/${project}`;
    // **The friendly address** — `share.…/hla` — stands for the general link,
    // the first one holding its key, so that link's `url` is the short one
    // and its keyed address is kept beside it for anything that already has it.
    const short = await ensureShort(env, project, title);
    const general = people.links.find((l) => l && l.key);
    return json({
      project,
      title,
      short,
      url: short ? `https://${SHARE_HOST_PREFIX}${apexHost(hostAsked(request, url, env))}/${short}` : "",
      // Whether this is a portal with no film behind it (2026-09-16).
      portal: Boolean(portal),
      // …and, if anything wrote a film's changes into it, how many and what
      // to do — the console's warning in place of a dead link (SL-1376).
      ...(portal ? await strays(env, project) : {}),
      down: down.down,
      since: down.since,
      links: people.links.map((link) => ({
        hash: link.hash, role: link.role, note: link.note || "", off: link.off === true,
        expires: link.expires || null, password: Boolean(link.pass),
        url: link.key
          ? (short && general && link.hash === general.hash
              ? `https://${SHARE_HOST_PREFIX}${apexHost(hostAsked(request, url, env))}/${short}`
              : `${share}?k=${encodeURIComponent(link.key)}`)
          : "",
        keyed: link.key ? `${share}?k=${encodeURIComponent(link.key)}` : "",
      })),
      people: people.people.map((one) => ({ email: one.email, role: one.role })),
      // The tag of the list just read, for `/access`'s `if_match` (2026-10-05).
      people_etag: tagged.etag || "",
      hidden: { sections: visible.sections, crew: visible.crew, documents: visible.documents },
      contact: visible.contact,
    });
  }

  if (what === "down") {
    if (method === "GET") return json(await downOf(env, project));
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (typeof asked.down !== "boolean") return problem(400, "Say down: true or false.");
    return json(await saveDown(env, project, asked.down, asked.by || "console"));
  }

  if (what === "people") {
    if (method !== "GET") return problem(405, "Wrong method.");
    // **With the tag of the copy read** (2026-10-05): sent back as `if_match`
    // on `/access`, it makes the change land only over exactly this list.
    const { list, etag } = await peopleWithTag(env, project);
    return json({ ...list, etag });
  }

  // **Who may open the film, changed** — `PUT /console/<film>/access`
  // (2026-10-05). The Share popover's People tab from the console, in the
  // connector's words and through its rules (`changeAccess`, access.js):
  //   add       [{ email, role }]       Add People by Email; role viewer|editor
  //   role      [{ email, role }]       a person's role changed
  //   remove    [email]                 Remove
  //   replace   { key, hash, was }      a new link replaces the old one; the
  //                                     console makes the key, `was` names
  //                                     the link it replaces (null: none)
  //   link      "anyone"|"restricted"   General Access
  //   password  { salt, pass } | null   set (made on the Mac) or cleared
  //   if_match  the `etag` from GET /people — refused if the list moved since
  // A password is never sent as the word: the hub keeps hashes only.
  if (what === "access") {
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Send what changes.");
    const ask = {};
    for (const field of ["add", "role", "remove", "replace", "link", "password"]) {
      if (field in asked) ask[field] = asked[field];
    }
    if (!Object.keys(ask).length) return problem(400, "Nothing to change. Send add, role, remove, replace, link or password.");
    for (const field of ["add", "role", "remove"]) {
      if (field in ask && !Array.isArray(ask[field])) return problem(400, `${field} must be a list.`);
    }
    if (typeof ask.password === "string" && ask.password !== "") {
      return problem(400, "Send the password's salt and hash, never the word.");
    }
    const ifMatch = asked.if_match === undefined ? undefined : String(asked.if_match || "");
    if (!(await hasFilm(env, project)) && !(await portalOf(env, project))) return problem(404, "No such film.");
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const { list, etag } = await peopleWithTag(env, project);
      if (ifMatch !== undefined && ifMatch !== (etag || "")) {
        return problem(409, "List changed. Reload.");
      }
      let said;
      try {
        said = await changeAccess(env, list, ask);
      } catch (error) {
        if (error instanceof Refusal) return problem(error.status, error.said);
        throw error;
      }
      const put = await savePeople(env, project, list, { etag });
      if (put) {
        const link = generalLink(list);
        const share = `https://${SHARE_HOST_PREFIX}${apexHost(hostAsked(request, url, env))}/f/${project}`;
        return json({
          project,
          said,
          etag: put.etag || null,
          people: list.people.map((one) => ({ email: one.email, role: one.role, ...(owners(env).includes(one.email) ? { owner: true } : {}) })),
          link: link ? {
            hash: link.hash, off: link.off === true, password: Boolean(link.pass),
            keyed: `${share}?k=${encodeURIComponent(link.key)}`,
          } : null,
        });
      }
      // Asked over a list it had read: somebody wrote in between, so say so.
      if (ifMatch !== undefined) break;
    }
    return problem(409, "List changed. Reload.");
  }

  if (what === "link") {
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (typeof asked.off !== "boolean") return problem(400, "Say off: true or false.");
    const hash = asked.hash ? String(asked.hash) : "";
    if (hash && !/^[0-9a-f]{64}$/.test(hash)) return problem(400, "That is not a link's hash.");
    // **Read, change one flag, write back under the etag** — the same guard
    // the Share page's own save goes through, so the two cannot lose each
    // other's change. Everything else on every link is left exactly as it was.
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const list = await peopleOf(env, project);
      const touched = list.links.filter((link) => !hash || link.hash === hash);
      if (hash && touched.length === 0) return problem(404, "No link with that hash.");
      for (const link of touched) link.off = asked.off;
      if (await savePeople(env, project, list)) {
        return json({ changed: touched.length, links: list.links.map((link) => ({ hash: link.hash, off: link.off === true })) });
      }
    }
    return problem(409, "List changed. Reload.");
  }

  if (what === "visible") {
    if (method === "GET") return json(await visibleOf(env, project));
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    const now = await visibleOf(env, project);
    const list = (x) => x.filter((v) => typeof v === "string").slice(0, 500);
    for (const kind of ["sections", "crew", "documents", "contact"]) {
      if (kind in asked) {
        if (!Array.isArray(asked[kind])) return problem(400, `${kind} must be a list of names.`);
        now[kind] = list(asked[kind]);
      }
    }
    // **`me`, his own view** — the same three lists, each sent replacing.
    if ("me" in asked) {
      if (!asked.me || typeof asked.me !== "object" || Array.isArray(asked.me)) return problem(400, "me must be { sections, crew, documents }.");
      for (const kind of ["sections", "crew", "documents"]) {
        if (kind in asked.me) {
          if (!Array.isArray(asked.me[kind])) return problem(400, `me.${kind} must be a list of names.`);
          now.me[kind] = list(asked.me[kind]);
        }
      }
    }
    await saveVisible(env, project, now);
    return json(now);
  }

  // **What Viewers See, whole** — `GET|PUT /console/<film>/viewers`
  // (2026-10-05). The panel's own rows (`viewersSeeOf`) and its own save
  // (`saveViewersSee`), so a page ticked here is ticked there: ticked is seen.
  // PUT sends what is *shown* — `sections` (a board shown is shared with the
  // link), `crew`, `documents` — and `contact`, whose numbers may be reached;
  // a list left out is kept. Everything offered and not sent is Private.
  // (`/visible` is the store itself, hidden lists, and stays as it was.)
  if (what === "viewers") {
    if (method !== "GET" && method !== "PUT") return problem(405, "Wrong method.");
    if (!(await hasFilm(env, project)) && !(await portalOf(env, project))) return problem(404, "No such film.");
    let ticked = null;
    if (method === "PUT") {
      let asked;
      try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
      if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Send the lists that are shown.");
      ticked = {};
      for (const kind of ["sections", "crew", "documents", "contact"]) {
        if (!(kind in asked)) continue;
        if (!Array.isArray(asked[kind]) || asked[kind].some((v) => typeof v !== "string")) {
          return problem(400, `${kind} must be a list of names.`);
        }
        ticked[kind] = new Set(asked[kind].slice(0, 500));
      }
      if (!Object.keys(ticked).length) return problem(400, "Send sections, crew, documents or contact.");
    }
    const [front, visible] = await Promise.all([frontOf(env, project, ctx), visibleOf(env, project)]);
    const now = ticked ? await saveViewersSee(env, project, front, visible, ticked) : visible;
    return json({ project, ...viewersSeeOf(front, now) });
  }

  // **The Library, per page** — `GET|PUT /console/<film>/library`
  // (2026-10-05). GET says each page's and document's settings
  // (`libraryStateOf`); PUT `{ keys, action }` is the Library's own bulk
  // action (`arrangeLibrary`): `pin`/`unpin` (a row in the sidebar),
  // `private`/`public`, `archive`/`unarchive`. A document is `doc:<name>`.
  if (what === "library" || what === "shelves") return await libraryDoor(request, env, project, ctx, what, sent);

  return problem(404, "No such door.");
}

/** What the console may do to a page in the Library — the Library's own words. */
const LIBRARY_ACTIONS = new Set(["pin", "unpin", "private", "public", "archive", "unarchive", "icon", "shelf", "rename"]);

/**
 * **The Library, per page, and its categories** — the console's door and the
 * iPhone apps' (2026-10-05; categories and the phone's way in, 2026-10-10).
 *
 *   GET  …/library   each page's and document's settings and shelf, and the
 *                    film's shelves (`libraryStateOf`), with the sidebar
 *   PUT  …/library   `{ keys, action, to? }`, the Library's own bulk action
 *                    (`arrangeLibrary`): `pin`/`unpin`, `private`/`public`,
 *                    `archive`/`unarchive`, `icon`, `rename` (one document: `to` is its new name), and `shelf` (Move To: `to`
 *                    is a shelf's id or name). A document is `doc:<name>`.
 *   PUT  …/shelves   `{ action, shelf?, name?, to?, ids? }` (`editShelves`)
 *
 * Every answer is the whole Library as it now stands, so the asker redraws
 * from it rather than guessing.
 */
async function libraryDoor(request, env, project, ctx, what, sent) {
  const method = request.method;
  if (method !== "GET" && method !== "PUT") return problem(405, "Wrong method.");
  if (!(await hasFilm(env, project)) && !(await portalOf(env, project))) return problem(404, "No such film.");
  const front = await frontOf(env, project, ctx);
  let done = null;
  // **The categories themselves** — `PUT /…/shelves` `{ action, shelf?, name?, to?, ids? }`
  // (`editShelves`): add, rename, remove (one he added), move, order.
  if (what === "shelves" && method === "PUT") {
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Send { action, shelf, name }.");
    const said = editShelves(front, asked);
    if (!said.ok) return problem(422, said.why || "Could not change that category.");
    await saveFront(env, project, front);
    done = { ok: true, ...(said.id ? { id: said.id } : {}) };
  } else if (method === "PUT") {
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Send { keys, action }.");
    const action = String(asked.action || "");
    if (!LIBRARY_ACTIONS.has(action)) return problem(400, `An action is one of ${[...LIBRARY_ACTIONS].join(", ")}.`);
    const named = Array.isArray(asked.keys) ? asked.keys : asked.key !== undefined ? [asked.key] : null;
    if (!named || !named.length || named.some((k) => typeof k !== "string")) return problem(400, "Name the pages: keys, a list.");
    // **Refused, not dropped.** The page drops a key it does not know; a
    // program asking for one is told which, before anything is written.
    const known = libraryKeys(front);
    const docs = new Set((front.documents || []).map((d) => d.name));
    const stranger = named.find((k) => (k.startsWith("doc:") ? !docs.has(k.slice(4)) : !known.has(k)));
    if (stranger !== undefined) return problem(404, `${stranger} is not a page on this film.`);
    try {
      done = await arrangeLibrary(env, project, front, { keys: named, action, to: String(asked.to || "") }, true);
    } catch (error) {
      if (error instanceof Refusal) return problem(error.status, error.said);
      throw error;
    }
  }
  const visible = await visibleOf(env, project);
  return json({ project, ...(done || {}), ...libraryStateOf(front, visible), ...sidebarStateOf(front) });
}


/**
 * **The iPhone app's line to the portal** — Ref 1541 Stage C, 2026-10-06.
 *
 * The phone shows what the portal shows (the Library's pages, decks, boards
 * and documents) and keeps it for a set with no signal. It cannot sign in the
 * way a browser does: Cloudflare Access on the apex answers a program with a
 * sign-in page. So it calls here, on the MCP's host like the console, with
 * **the token it already holds**: the relay's password in its Keychain is the
 * one `hub/setup.sh` copied into `CONSOLE_TOKEN`. Nothing for him to type.
 *
 * **His view, and almost read only.** The token is his, so the answers are
 * what he sees as owner: Private and the Archive included. The one write is
 * the Library's categories and Move To (`PUT library` / `PUT shelves`, below).
 *
 *   GET /phone/<film>/library        the Library as data (`phoneLibraryOf`)
 *   GET /phone/<film>/page/<slug>    { slug, tree, html, pictures }  a written page, or a
 *                                    published one read back into blocks (`treeFromHtml`)
 *   GET /phone/<film>/deck/<slug>    { slug, deck, pictures }        a deck's content
 *   GET /phone/<film>/board/<slug>   { slug, share, board, pictures } a look board
 *   GET /phone/<film>/front          the film's record: front page, spec sheet,
 *                                    People, Documents, each shoot (`phoneFrontOf`)
 *   GET /phone/<film>/pic/<name>     a picture or file, from docs/ or media/
 *
 * `pictures` is every stored file the answer names, so the phone can fetch
 * them all and open the page with no signal. `html` is true when a published
 * page exists.
 *
 * **Never HTML.** His rulings, 2026-10-06: *"I do not want to combine a web
 * app into an iOS app … ugly"* and *"everything should feel native."* A page
 * the portal draws as a finished document comes down as the same blocks every
 * written page is (`treeFromHtml`, the road the hand-made pages took), so the
 * phone has no web view to show it in and needs none.
 */
/**
 * **The portal's own pages, inside the iPhone app** — his trial, 2026-10-08:
 * *"Let's try this new portal approach and see what it feels like."* A written
 * page, a deck or a board is shown in the app exactly as the portal draws it,
 * so a new kind of page needs no work on the phone. The staple pages (the
 * front page, the spec sheet, People, Documents) stay native.
 *
 *   GET /phone/web/<any path on the apex>   that path, answered as the apex
 *                                           answers him
 *
 * The phone's web view asks through a scheme of its own (`PortalWeb.swift`)
 * that puts the token on every request, so the page's pictures, styles and
 * scripts come through here as well. **Reading only**: anything but GET or
 * HEAD is refused before the portal sees it. His yes to the token standing
 * for him here, 2026-10-08.
 *
 * A page comes back marked `inapp` on `<html>`, which `inapp.css` reads to put
 * the portal's own rail and bar away: the app has its own.
 */
const IN_APP = new WeakSet();
/** Requests the console's `act` door hands to the page routes, as him. */
const CONSOLE_ACT = new WeakSet();

async function phoneWeb(request, env, url, ctx, host) {
  const expected = env.CONSOLE_TOKEN;
  if (!expected) return problem(503, "No token is set on the hub.");
  if (!carriesToken(request, expected)) return problem(401, "Not this hub's token.");
  if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Read only.");
  if (!owners(env).length) return problem(503, "No owner is set on the hub.");

  const rest = url.pathname.slice("/phone/web".length) || "/";
  const apex = host.startsWith(MCP_HOST_PREFIX) ? host.slice(MCP_HOST_PREFIX.length) : host;
  const headers = new Headers();
  for (const name of ["range", "accept", "if-none-match", "if-modified-since"]) {
    const said = request.headers.get(name);
    if (said) headers.set(name, said);
  }
  const asked = new Request(new URL(rest + url.search, `${url.protocol}//${apex}`), { method: request.method, headers });

  // A file the site serves as it stands: a stylesheet, a script, a typeface.
  if ((rest.split("/").filter(Boolean)[0] || "") !== "f" && /\.[A-Za-z0-9]{1,8}$/.test(rest) && env.ASSETS) {
    return (await keptForGood(asked, env)) || (await env.ASSETS.fetch(asked));
  }

  IN_APP.add(asked);
  const answer = await route(asked, env, ctx);

  // **A move stays inside the app**: a redirect to the apex comes back as a
  // path, which the phone's scheme resolves against itself.
  const moved = answer.headers.get("location");
  if (moved && /^https?:\/\//.test(moved)) {
    const there = new URL(moved);
    if (there.host === apex) {
      const kept = new Response(answer.body, answer);
      kept.headers.set("location", there.pathname + there.search);
      return kept;
    }
  }
  if (!(answer.headers.get("content-type") || "").startsWith("text/html")) return answer;
  const page = (await answer.text())
    .replace(/<html(\s[^>]*)?>/, (tag) => tag.replace(/^<html/, '<html class="inapp"'))
    .replace("</head>", `<link rel="stylesheet" href="/inapp.css?v=${BUILD}"></head>`);
  const headers2 = new Headers(answer.headers);
  headers2.delete("content-length");
  return new Response(page, { status: answer.status, headers: headers2 });
}

const STORED_FILE = /\b[0-9a-f]{32}\.[A-Za-z0-9]{1,8}\b/g;
const picturesIn = (thing) => [...new Set(JSON.stringify(thing || null).match(STORED_FILE) || [])];

async function phoneDoor(request, env, url, ctx, host) {
  const expected = env.CONSOLE_TOKEN;
  if (!expected) return problem(503, "No token is set on the hub.");
  if (!carriesToken(request, expected)) return problem(401, "Not this hub's token.");

  const parts = url.pathname.split("/").filter(Boolean);
  const project = parts[1] || "";
  if (!PROJECT.test(project)) return problem(404, "No such film.");
  const what = parts[2] || "";
  /**
   * **The one thing the phone writes: its Library's shelves** (2026-10-10,
   * his ask: *"moving an item to another category must work from the apps"*).
   * `PUT /phone/<film>/library` (Move To, as the console's `{ keys, action:
   * "shelf", to }`) and `PUT /phone/<film>/shelves` (add, rename, remove,
   * move a category) go through the console's own door (`libraryDoor`), with
   * the same token: nothing else here writes.
   */
  if (request.method === "PUT" && parts.length === 3 && (what === "library" || what === "shelves")) {
    const sent = async () => {
      const text = await request.text();
      if (text.length > MAX_PEOPLE) throw new Error("too long");
      return JSON.parse(text);
    };
    if (what === "library") {
      // Only Move To, and Rename for a document: the phone's other switches are the Mac's and the portal's.
      let asked;
      try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
      if (!asked || (asked.action !== "shelf" && asked.action !== "rename")) return problem(400, "The phone moves things between categories, or renames a document: { keys, action: \"shelf\" | \"rename\", to }.");
      return await libraryDoor(request, env, project, ctx, what, async () => asked);
    }
    return await libraryDoor(request, env, project, ctx, what, sent);
  }
  if (request.method !== "GET" && request.method !== "HEAD") return problem(405, "Read only.");
  const slug = parts[3] || "";
  if (parts.length > 4) return problem(404, "No such door.");
  if (!(await hasFilm(env, project)) && !(await portalOf(env, project))) return problem(404, "No such film.");

  if (what === "pic" && parts.length === 4) {
    return await media(env, project, slug, request, ["docs", "media"]);
  }

  const front = await frontOf(env, project, ctx);

  if (what === "library" && parts.length === 3) {
    // **One listing per folder**, not a look per page: a Worker holds six
    // answers open at once, and a film has a few dozen pages.
    const base = keys.film(project);
    const [visible, title, ...listed] = await Promise.all([
      visibleOf(env, project), titleOf(env, project),
      listAll(env, keys.pages(project)), listAll(env, keys.decks(project)),
      listAll(env, `${base}boards/`),
    ]);
    const stored = {};
    for (const one of listed.flat()) {
      if (!one || !one.key.endsWith(".json") && !one.key.endsWith(".html")) continue;
      stored[one.key.slice(base.length)] = one.uploaded ? new Date(one.uploaded).getTime() : 1;
    }
    // **A page published with a board in it** (Halcyon's look board, Ref
    // 1562) is a board to the phone: it is asked for at `board/<slug>`, which
    // hands over its cards. Only a page with a published document is looked
    // at, and only its first few kilobytes, where the board names itself.
    const carried = {};
    await Promise.all((front.sections || []).filter((one) => one.type !== "board" && stored[`pages/${one.slug}.html`])
      .map(async (one) => {
        const head = await env.BUCKET.get(keys.pageHtml(project, one.slug), { range: { offset: 0, length: 16384 } });
        const name = head ? boardIn(await head.text()) : "";
        if (name) carried[one.slug] = { board: name, stamp: stored[`boards/${name}.json`] || 0 };
      }));
    // **The portal's own address**, for anything the phone cannot draw yet:
    // the apex, which a person reaches through his browser's sign-in.
    const apex = host.startsWith(MCP_HOST_PREFIX) ? host.slice(MCP_HOST_PREFIX.length) : host;
    return json({ project, title, portal: `https://${apex}/f/${project}`, updated: front.updated || null,
      ...phoneLibraryOf(front, visible, stored, carried) });
  }

  if (what === "front" && parts.length === 3) {
    // **The film's record, native on the phone** (his ask, 2026-10-06): the
    // front page, the spec sheet, People, Documents and every shoot's tab,
    // worked out by the portal's own code (`phoneFrontOf`). A shoot's notes
    // page is read here, so the phone never asks for it by name.
    const shoots = front.shoots || [];
    const views = shoots.length >= 2 ? shoots.map((one) => shotView(front, one.slug)) : [shotView(front)];
    const [title, ...notes] = await Promise.all([titleOf(env, project),
      ...views.map((v) => (v.camera_notes ? pageOf(env, project, v.camera_page || "camera-sheet") : null))]);
    return json({ project, title, updated: front.updated || null, ...phoneFrontOf(front, views, notes) });
  }

  if (!/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug) || parts.length !== 4) return problem(404, "No such door.");
  const sec = (front.sections || []).find((one) => one.slug === slug);

  if (what === "page") {
    // **What the portal draws is what the phone gets.** A page published as a
    // finished document is drawn on the portal instead of its tree
    // (`recordBody`), and the two can disagree (Call Her Back's Production
    // Design Requests: a tree from Notion, a later document). So a published
    // page comes down as that document, read back into blocks; never as HTML.
    const [stored, html] = await Promise.all([pageOf(env, project, slug), pageHtmlOf(env, project, slug)]);
    if (!stored && !html) return problem(404, "No such page.");
    if (html) {
      const { tree, dropped } = treeFromHtml(html);
      // The page's name is its title on the phone already; a designed page
      // that opens by saying it again (Doc Mirror's "Outline") says it once.
      const name = String(sec ? sec.name : "").trim().toLowerCase();
      const again = name ? tree.findIndex((b) => /^h[1-3]$/.test(b.t) && (b.r || []).map((x) => x.s).join("").trim().toLowerCase() === name) : -1;
      if (again >= 0 && tree.length > 1 && again === tree.findIndex((b) => /^h[1-3]$/.test(b.t))) tree.splice(again, 1);
      return json({ slug, name: sec ? sec.name : slug, tree, html: true, from: "html",
        ...(dropped.length ? { dropped } : {}), pictures: picturesIn(tree) });
    }
    return json({ slug, name: sec ? sec.name : slug, tree: stored, html: false, pictures: picturesIn(stored) });
  }

  if (what === "deck") {
    const got = await env.BUCKET.get(keys.deck(project, slug));
    if (!got) return problem(404, "No such deck.");
    let deck = null;
    try { deck = await got.json(); } catch { return problem(500, "That deck will not read."); }
    return json({ slug, name: sec ? sec.name : slug, deck, pictures: picturesIn(deck && deck.pictures) });
  }

  if (what === "board") {
    // **A page published with a board in it**, its cards handed over in the
    // stored board's own shape (`publishedBoard`). The portal draws that page
    // exactly as before; this only reads it.
    if (sec && sec.type !== "board") {
      const held = await env.BUCKET.get(keys.pageHtml(project, slug));
      const page = held ? await held.text() : "";
      const name = boardIn(page);
      if (!name) return problem(404, "No such board.");
      const kept = await env.BUCKET.get(boardKeys(project, name).board);
      let stored = {};
      if (kept) { try { stored = await kept.json(); } catch { stored = {}; } }
      const board = publishedBoard(stored, page);
      return json({ slug, name: sec.name, published: true, board, pictures: picturesIn(board) });
    }
    if (!sec || sec.type !== "board" || !sec.board) return problem(404, "No such board.");
    const got = await env.BUCKET.get(boardKeys(project, sec.board).board);
    let board = {};
    if (got) { try { board = await got.json(); } catch { board = {}; } }
    return json({ slug, name: sec.name, share: sec.share || "me", board, pictures: picturesIn(board) });
  }

  return problem(404, "No such door.");
}

/**
 * **One record per project, on Cloudflare.**
 *
 * The switchboard spec's next step (Projects Console, 2026-09-11): the card
 * the portal keeps, widened to hold everything the console knows about a
 * project — names, stage, dates, the mirrored facts, every switch's state,
 * the drives, the film, the portal's own switches. The Studio writes it
 * whenever it looks at a project; the console on any device, and the phone,
 * read it back with the same token. Nothing has to be awake for anything
 * else to read it.
 *
 * **Pending.** A switch flipped somewhere the disk is not — the phone, the
 * laptop — is put on the record as pending. The Studio claims it, does it,
 * and marks it done or failed with the words the verb said. Claiming is a
 * state change from `pending` to `working` that only succeeds once, so two
 * copies of the console never do one thing twice.
 *
 *   GET  /console/records                           every record, one line each
 *   GET  /console/records?full=1                    every record, whole
 *   GET  /console/record/<page>                     the record
 *   PUT  /console/record/<page>                     the record, replaced; `updated` stamped here
 *   GET  /console/record/<page>/pending             this record's queue, newest last
 *   POST /console/record/<page>/pending             { verb, args, by } → the item, pending
 *   PUT  /console/record/<page>/pending/<id>        { state: working|done|failed, report, by }
 *   GET  /console/pending                           every item still pending, across records
 *
 * The record lives at `r/<page>/record.json`, the queue at `r/<page>/pending.json`
 * — under `r/`, apart from the films under `p/`, so a listing of one never
 * walks the other. A page id is Notion's, without dashes: 32 hex characters.
 */
const PAGE = /^[0-9a-f]{32}$/;
const PENDING_STATES = new Set(["working", "done", "failed"]);
const PENDING_KEEP_MS = 7 * 24 * 3600 * 1000;

async function recordOf(env, page) {
  const got = await env.BUCKET.get(`r/${page}/record.json`);
  if (!got) return null;
  try { return await got.json(); } catch { return null; }
}

async function pendingOf(env, page) {
  const got = await env.BUCKET.get(`r/${page}/pending.json`);
  if (!got) return [];
  try {
    const parsed = await got.json();
    return Array.isArray(parsed) ? parsed.filter((x) => x && typeof x === "object") : [];
  } catch { return []; }
}

async function savePending(env, page, list) {
  // Done items are kept a week, so the phone can show what happened; older
  // ones go quietly.
  const cutoff = Date.now() - PENDING_KEEP_MS;
  const kept = list.filter((x) => x.state === "pending" || x.state === "working"
    || !x.done_at || Date.parse(x.done_at) > cutoff);
  await env.BUCKET.put(`r/${page}/pending.json`, JSON.stringify(kept), {
    httpMetadata: { contentType: "application/json" },
  });
  return kept;
}

async function recordDoor(request, env, parts, method, sent) {
  // GET /console/records
  if (parts[1] === "records") {
    if (parts.length !== 2) return problem(404, "No such door.");
    if (method !== "GET") return problem(405, "Wrong method.");
    const objects = await listAll(env, "r/");
    const pages = objects.map((o) => o.key).filter((k) => k.endsWith("/record.json"))
      .map((k) => k.split("/")[1]).filter((p) => PAGE.test(p));
    const records = await Promise.all(pages.map((page) => recordOf(env, page)));
    // `?full=1` — every record whole, facts and all, in one call: the phone's
    // project list reads from here (2026-10-05) rather than asking each page.
    if (new URL(request.url).searchParams.get("full") === "1") {
      return json({ records: records.filter(Boolean) });
    }
    return json({
      records: records.filter(Boolean).map((r) => ({
        page: r.page, name: r.name || "", slug: r.slug || "", stage: r.stage || "",
        updated: r.updated || "", film: r.film ? { title: r.film.title, relay: r.film.relay } : null,
        portal: r.portal ? { down: Boolean(r.portal.down) } : null, lights: r.lights || {},
      })),
    });
  }

  // GET /console/pending — every item still waiting, across every record
  if (parts[1] === "pending") {
    if (parts.length !== 2) return problem(404, "No such door.");
    if (method !== "GET") return problem(405, "Wrong method.");
    const objects = await listAll(env, "r/");
    const pages = objects.map((o) => o.key).filter((k) => k.endsWith("/pending.json"))
      .map((k) => k.split("/")[1]).filter((p) => PAGE.test(p));
    const lists = await Promise.all(pages.map(async (page) => {
      const record = await recordOf(env, page);
      return (await pendingOf(env, page)).filter((x) => x.state === "pending")
        .map((x) => ({ ...x, page, name: record ? record.name || "" : "" }));
    }));
    return json({ pending: lists.flat() });
  }

  // /console/record/<page>[/pending[/<id>]]
  const page = parts[2] || "";
  if (!PAGE.test(page)) return problem(404, "That is not a project's page id.");
  const rest = parts.slice(3);

  if (rest.length === 0) {
    if (method === "GET") {
      const record = await recordOf(env, page);
      return record ? json(record) : problem(404, "No record for that project yet.");
    }
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "A record is an object.");
    if (asked.page && asked.page !== page) return problem(400, "The record names a different page.");
    // **The readout never overwrites the facts** (2026-10-05, the one-record
    // plan). This PUT is the console's "what I see" — lights, drive, film
    // counts — sent every time it looks at a project. `facts` are what he
    // typed, one version each, written only through `/facts` below; a PUT
    // keeps whatever facts are already there and ignores any it carries.
    // Compare-and-set against the stored copy so a `/facts` write landing in
    // the same instant is not lost.
    let record;
    let saved = false;
    for (let attempt = 0; attempt < 3 && !saved; attempt++) {
      const current = await env.BUCKET.get(`r/${page}/record.json`);
      let facts = {};
      let stored = null;
      if (current) {
        try { stored = await current.json(); facts = stored.facts || {}; } catch { facts = {}; }
      }
      const { facts: _ignored, ...readout } = asked;
      record = { ...readout, facts, page, updated: new Date().toISOString() };
      // **One ID** (projectid.js): what the server keeps about the project's
      // identity is not the readout's to drop — the Notion page of a minted
      // project, and when it was minted. The page in the address is the
      // project's ID even when it was reached by its Notion page.
      if (stored && typeof stored === "object") {
        for (const k of ["notion_page", "minted"]) if (stored[k] && !(k in readout)) record[k] = stored[k];
        // A big move's own fields (bigmoves.js) are the server's, never the
        // readout's: the lock, the media folders' kept names, the tombstone.
        for (const k of ["moving", "media_names", "deleted"]) if (stored[k] !== undefined) record[k] = stored[k];
        if (stored.page && /^[0-9a-f]{32}$/.test(String(stored.page))) record.page = stored.page;
      }
      // A film New Film made on the server stays named while the Mac, which
      // has not fetched it yet, says "no film" (newfilm.js).
      record = await (await import("./newfilm.js")).keepServerFilm(env, stored, record);
      saved = Boolean(await env.BUCKET.put(`r/${page}/record.json`, JSON.stringify(record), {
        httpMetadata: { contentType: "application/json" },
        onlyIf: current ? { etagMatches: current.etag } : { etagDoesNotMatch: "*" },
      }));
    }
    if (!saved) return problem(409, "The record changed while this was being written. Try again.");
    // **The record naming a film is the moment a portal on its own becomes
    // the film's** — his ruling, 2026-09-16. Carried here, once, and said
    // back so the console can log what moved; `null` when there was nothing
    // to carry, which is every record but one.
    const relay = record.film && record.film.relay;
    // With one ID there is no carry: a project's pages stay where they are
    // (studioside.js), and a film under another id is kept as an alias of the
    // project, for good (projectid.js).
    if ((await oneIdOn(env)).on) {
      if (relay && PROJECT.test(relay) && relay !== record.page && /^[0-9a-f]{32}$/.test(relay)) {
        try { await addIds(env, { alias: { [relay]: record.page } }); } catch (e) { console.error("ids: alias not kept:", String((e && e.message) || e)); }
      }
      return json({ page: record.page, updated: record.updated });
    }
    const carried = relay && PROJECT.test(relay) ? await carryPortal(env, page, relay) : null;
    return json({ page, updated: record.updated, ...(carried ? { carried } : {}) });
  }

  if (rest[0] === "facts" || rest[0] === "history") return await factsDoor(env, page, rest, method, sent);

  // **Drive files on the portal** (portaldocs.js): the folder to pick from, and the switch.
  if (rest[0] === "portaldocs" && rest.length === 1) {
    const { portalDocsDoor } = await import("./portaldocs.js");
    return await portalDocsDoor(env, page, method, sent, { recordOf, writeFacts });
  }

  if (rest[0] !== "pending") return problem(404, "No such door.");

  if (rest.length === 1) {
    if (method === "GET") return json({ pending: await pendingOf(env, page) });
    if (method !== "POST") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    const verb = String(asked.verb || "").trim();
    if (!/^[a-z_]{1,40}$/.test(verb)) return problem(400, "Say which verb.");
    const item = {
      id: crypto.randomUUID().replace(/-/g, "").slice(0, 12),
      verb,
      args: asked.args && typeof asked.args === "object" && !Array.isArray(asked.args) ? asked.args : {},
      by: String(asked.by || "").slice(0, 80),
      asked: new Date().toISOString(),
      state: "pending",
      report: "",
    };
    const list = await pendingOf(env, page);
    list.push(item);
    await savePending(env, page, list);
    return json(item);
  }

  if (rest.length === 2) {
    if (method !== "PUT") return problem(405, "Wrong method.");
    let asked;
    try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
    const state = String(asked.state || "");
    if (!PENDING_STATES.has(state)) return problem(400, "Say state: working, done or failed.");
    const list = await pendingOf(env, page);
    const item = list.find((x) => x.id === rest[1]);
    if (!item) return problem(404, "No such item.");
    // **Claimed once.** Working is only reachable from pending; a second
    // claimant is told the truth rather than handed the item again.
    if (state === "working" && item.state !== "pending") return json(item);
    item.state = state;
    if (asked.by) item.by_done = String(asked.by).slice(0, 80);
    if (state === "working") item.claimed_at = new Date().toISOString();
    else {
      item.report = String(asked.report || "").slice(0, 2000);
      item.done_at = new Date().toISOString();
    }
    await savePending(env, page, list);
    return json(item);
  }

  return problem(404, "No such door.");
}

/**
 * **A project's facts, one version each** (2026-10-05, the one-record plan).
 *
 * The record grows a `facts` map beside the console's readout: what he typed
 * about the project — logline, director, status… — each as
 * `{value, v, at, by}`. A write names the version it started from (`base`);
 * if the stored version has moved on since, the write is refused with what is
 * there now, so an edit on the phone and one on the Mac can never silently
 * erase each other. Every accepted change is also kept, append-only, under
 * `r/<page>/history/`.
 *
 *   GET  /console/record/<page>/facts            → {facts}
 *   PUT  /console/record/<page>/facts            {changes: {field: {value, base}}, by}
 *        → {facts} · 409 {conflicts: {field: stored}} and nothing written
 *   GET  /console/record/<page>/history          → {history: [newest first, ≤ 100]}
 *
 * `base` is the version the writer last saw (0 or absent for a field never set).
 * Nothing reads `facts` yet; this is the ground the record stands on before it
 * becomes the place a project's facts live.
 */
async function factsDoor(env, page, rest, method, sent) {
  if (rest[0] === "history") {
    if (rest.length !== 1) return problem(404, "No such door.");
    if (method !== "GET") return problem(405, "Wrong method.");
    const objects = await listAll(env, `r/${page}/history/`);
    const newest = objects.map((o) => o.key).sort().reverse().slice(0, 100);
    const history = (await Promise.all(newest.map(async (key) => {
      const got = await env.BUCKET.get(key);
      try { return got ? await got.json() : null; } catch { return null; }
    }))).filter(Boolean);
    return json({ history });
  }
  if (rest.length !== 1) return problem(404, "No such door.");
  if (method === "GET") {
    const record = await recordOf(env, page);
    return json({ facts: (record && record.facts) || {} });
  }
  if (method !== "PUT") return problem(405, "Wrong method.");
  let asked;
  try { asked = await sent(); } catch { return problem(400, "That is not JSON."); }
  // **One writer for the facts** — `writeFacts` in facts.js, shared with the
  // AI connector's `set_front` (2026-10-05, the Notion link).
  const got = await writeFacts(env, page, asked && asked.changes, asked && asked.by);
  if (got.status === 200) return json({ facts: got.facts });
  if (got.conflicts) {
    return new Response(JSON.stringify({ conflicts: got.conflicts }), {
      status: 409, headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
  return problem(got.status, got.problem);
}

/** The record's own page: what the console knows, for a project with no film yet. */
function projectRecordBody(r) {
  const esc = (t) => String(t ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const row = (k, v) => (v ? `<div class="row"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>` : "");
  const lights = Object.entries(r.lights || {}).map(([k, v]) => `<span class="light ${esc(v)}">${esc(k)}</span>`).join("");
  return `<style>
    .rec{max-width:640px;margin:48px auto;padding:0 24px;font-family:-apple-system,system-ui,sans-serif}
    .rec h1{font-size:28px;margin:0 0 4px}.rec .stage{opacity:.7;margin-bottom:24px}
    .rec .row{display:flex;gap:16px;padding:8px 0;border-bottom:1px solid rgba(255,255,255,.1)}
    .rec .k{width:120px;flex:none;opacity:.6;font-size:12px;letter-spacing:.08em;text-transform:uppercase;padding-top:2px}
    .rec .lights{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0 24px}
    .rec .light{font-size:11px;letter-spacing:.08em;text-transform:uppercase;padding:4px 8px;border-radius:6px;border:1px solid rgba(255,255,255,.2);opacity:.45}
    .rec .light.on{opacity:1;border-color:#4a9}.rec .light.warn{opacity:1;border-color:#d9a441}
    .rec .foot{opacity:.5;font-size:12px;margin-top:24px}
  </style><div class="rec">
    <h1>${esc(r.name)}</h1><div class="stage">${esc(r.stage)}${r.type ? " · " + esc(r.type) : ""}${r.length ? " · " + esc(r.length) : ""}</div>
    <div class="lights">${lights}</div>
    ${row("Director", r.director)}${row("Shoot", r.dates)}${row("Folder", r.drive ? (r.drive.where || "") + (r.drive.name || "") : "")}
    ${row("Media", (r.media || []).map((m) => m.drive).join(" · "))}${row("Website", r.website)}
    <div class="foot">No film is attached yet. This is the project's record, as the console last wrote it${r.updated ? " (" + esc(r.updated.slice(0, 16).replace("T", " ")) + ")" : ""}.</div>
  </div>`;
}

/** The plain domain, whichever of its hosts a request came in on. */
function apexHost(host) {
  return String(host).replace(/^(mcp|share)\./, "");
}

async function identify(request, env, url) {
  // 0. The iPhone app, through `phoneWeb`, which has already checked its token
  // and lets nothing but reading through. His yes, 2026-10-08.
  if (IN_APP.has(request)) return { email: owners(env)[0], via: "phone" };
  // 0b. The Projects Console's `act` door, which has checked its token and
  // lets only its three writes through (2026-10-10).
  if (CONSOLE_ACT.has(request)) return { email: owners(env)[0], via: "console" };

  // 1. Cloudflare Access.
  const assertion = request.headers.get("cf-access-jwt-assertion");
  if (assertion && env.ACCESS_TEAM && env.ACCESS_AUD) {
    const email = await emailFromAccess(assertion, env);
    if (email) return { email, via: "access" };
  }

  // 2. A secret link. The key is in the address the first time and in a cookie
  // afterwards, so a reload does not lose it and the address can be tidied.
  const key = url.searchParams.get("k") || cookie(request, "hubkey");
  if (key && LINK_KEY.test(key)) return { email: null, via: "link", key };

  // 3. Checking runs only.
  //
  // **Two fences, and the first is the one that matters.** `HUB_DEV_EMAIL`
  // lives in `.dev.vars`, which is gitignored and which wrangler never uploads
  // — the same fence the relay puts round its own checking token. A deployed
  // hub simply has no such var.
  //
  // The second: **it is refused outright once Access is wired up.** Real
  // sign-in existing means this door has no reason to, so it closes rather
  // than sitting there as the weakest way in.
  //
  // A hostname check was tried and does not work: `wrangler dev` serves the
  // custom domain from `routes`, so a local request already arrives calling
  // itself your-domain.example.
  if (env.HUB_DEV_EMAIL && !(env.ACCESS_TEAM && env.ACCESS_AUD)) {
    // `?as=` lets one checking run be several people, which is the only way to
    // check that a viewer is refused what an editor is allowed.
    const as = url.searchParams.get("as");
    if (as && EMAIL.test(as)) return { email: as.toLowerCase(), via: "dev" };
    return { email: String(env.HUB_DEV_EMAIL).toLowerCase(), via: "dev" };
  }

  return null;
}

/**
 * A link may be behind a password. Until it is answered, no film is served.
 *
 * **The hub never learns the word.** The browser that made the link chose a
 * random salt and sent the hash of salt + password; answering means hashing the
 * same way and comparing. So `people.json` leaking hands over neither the key
 * nor the password.
 *
 * It is a gate, not a vault — his words, that this is not a high-security
 * situation. What it stops is a link forwarded to somebody it was not meant for.
 */
async function passwordWanted(env, project, who, request, url, ctx, base = `/f/${project}`) {
  const list = await peopleOf(env, project);
  const hash = await sha256Hex(who.key);
  const link = list.links.find((l) => l && l.hash === hash);
  if (!link || !link.pass || !link.salt) return null;

  if (cookie(request, "hubpass") === link.pass) return null;

  // The film's mark and colour for the door, and — his ruling, 2026-09-19 —
  // its card for the link's preview: the title and the cover unfurl, the
  // page itself stays locked. (Until then the gate named no film, so that a
  // forwarded link gave nothing away; he chose the preview.)
  const [front, title] = await Promise.all([frontOf(env, project, ctx), titleOf(env, project)]);
  const card = sharedAs(url, base, title, front);

  if (request.method === "POST") {
    let said = "";
    try {
      said = String((await request.formData()).get("password") || "");
    } catch {
      said = "";
    }
    if ((await sha256Hex(link.salt + said)) === link.pass) {
      return new Response(null, {
        status: 303,
        headers: {
          location: url.pathname + url.search,
          "set-cookie": `hubpass=${link.pass}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`,
        },
      });
    }
    return passwordPage(true, front, card);
  }
  return passwordPage(false, front, card);
}

/**
 * The door a link with a password opens onto.
 *
 * **Dressed like the boot screen, not like a refusal.** His instruction of
 * 2026-09-02 for the first thing anybody sees on a link — the film's own mark
 * and colour — holds here too, since this page stands where that one would:
 * the mark in the film's colour, his wordmark under it, the field and the
 * button in the shapes every sheet uses, the button in the film's tint.
 * **The film's name stays off it.** The gate exists to stop a forwarded link,
 * and the name is most of what it is protecting; `checks.sh` measures that.
 */
function passwordPage(wrong, front, card = {}) {
  const hue = front && front.mark && front.mark.colour;
  const wear = /^#[0-9A-Fa-f]{6}$/.test(String(hue || ""))
    ? ` style="--accent:${hue};--accent-tint:color-mix(in srgb,${hue} 14%,transparent);--accent-line:color-mix(in srgb,${hue} 38%,transparent)"`
    : "";
  const icon = filmIconSvg(front);
  return html(
    `<div class="signin gatepass"${wear}>
       ${icon ? `<div class="filmicon">${icon.replace(/fill="[^"]*"/, 'fill="currentColor"')}</div>` : ""}
       <div class="mark" role="img" aria-label="Nathaniel Regier"></div>
       <form method="post" class="form">
         <label class="flabel" for="password">Password</label>
         <input class="field" id="password" type="password" name="password" autofocus autocomplete="current-password">
         <button class="primary" type="submit">Open</button>
         ${wrong ? `<p class="saying bad">Wrong password</p>` : ""}
       </form>
     </div>`,
    "Password",
    401,
    // The card is the film's, so a pasted link unfurls; the icon is inline
    // because a browser at a 401 may not go and fetch one.
    { dark: true, ...card, icon: icon ? `data:image/svg+xml,${encodeURIComponent(icon)}` : card.icon }
  );
}

/**
 * Who is asking, on the share host: a key, or nobody.
 *
 * Deliberately not `identify`. That one reads an Access assertion and, in a
 * checking run, an email — neither of which may be honoured here, because this
 * host exists precisely to serve people who have not signed in to anything.
 */
function linkOnly(request, url) {
  const key = url.searchParams.get("k") || cookie(request, "hubkey");
  if (key && LINK_KEY.test(key)) return { email: null, via: "link", key };
  return null;
}

/**
 * Verify an Access assertion and read the email out of it.
 *
 * **Verified, not read.** The header is signed by Access; a worker that merely
 * decodes it is trusting anybody who can set a header, which is everybody the
 * moment a request reaches the worker by any path Access does not cover.
 */
async function emailFromAccess(token, env) {
  const [head, body, signature] = String(token).split(".");
  if (!head || !body || !signature) return null;
  let header, claims;
  try {
    header = JSON.parse(atob(head.replace(/-/g, "+").replace(/_/g, "/")));
    claims = JSON.parse(atob(body.replace(/-/g, "+").replace(/_/g, "/")));
  } catch {
    return null;
  }
  if (claims.aud && !(Array.isArray(claims.aud) ? claims.aud : [claims.aud]).includes(env.ACCESS_AUD)) {
    return null;
  }
  if (claims.exp && Date.now() / 1000 > claims.exp) return null;

  const known = await accessKeys(env);
  const key = known.find((k) => k.kid === header.kid);
  if (!key) return null;

  const data = new TextEncoder().encode(`${head}.${body}`);
  const sig = Uint8Array.from(atob(signature.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));
  const ok = await crypto.subtle.verify({ name: "RSASSA-PKCS1-v1_5" }, key.key, sig, data);
  if (!ok) return null;

  const email = String(claims.email || "").toLowerCase();
  return EMAIL.test(email) ? email : null;
}

let KEYS = null;
let KEYS_AT = 0;

/** Access's signing keys, held for an hour. They rotate; an hour is Cloudflare's own advice. */
async function accessKeys(env) {
  if (KEYS && Date.now() - KEYS_AT < 3600_000) return KEYS;
  const url = `https://${env.ACCESS_TEAM}.cloudflareaccess.com/cdn-cgi/access/certs`;
  // A fresh isolate asked Access afresh: 600 ms on the first page of a visit
  // (2026-10-13). Cloudflare's own cache holds the keys for the same hour.
  const got = await fetch(url, { cf: { cacheTtl: 3600, cacheEverything: true } });
  if (!got.ok) return KEYS || [];
  const { keys } = await got.json();
  KEYS = [];
  for (const jwk of keys || []) {
    try {
      const key = await crypto.subtle.importKey(
        "jwk",
        { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
        { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
        false,
        ["verify"]
      );
      KEYS.push({ kid: jwk.kid, key });
    } catch {
      // A key we cannot import is one we cannot verify with. Skipping it fails
      // a sign-in closed, which is the right way for this to fail.
    }
  }
  KEYS_AT = Date.now();
  return KEYS;
}

// ------------------------------------------------------------- what you may do

/**
 * Take an invite: sign in as anybody, and be written onto the film.
 *
 * **The one write in the hub that is not made by an editor**, and it is narrow
 * on purpose: it can add exactly the address Cloudflare just verified, with
 * exactly the role the invite already carried, and it can do nothing else.
 *
 * A bearer key cannot join. It has no address to write down, and an invite that
 * could be taken by somebody who never proved an address would be a secret link
 * wearing a better name.
 */
async function join(request, env, project, who, url) {
  const key = url.searchParams.get("i") || "";
  if (!LINK_KEY.test(key)) return page(404, "No such invite", "");

  if (!who.email) {
    return page(403, "Sign in to accept", "");
  }

  const hash = await sha256Hex(key);
  const list = await peopleOf(env, project);
  const invite = list.invites.find((i) => i && i.hash === hash);
  if (!invite) return page(403, "Invite expired", "");
  if (invite.expires && Date.now() > Date.parse(`${invite.expires}T23:59:59Z`)) {
    return page(403, "That invite has run out", "Ask him for another.");
  }

  const email = who.email.toLowerCase();
  const already = list.people.find((p) => String(p.email || "").toLowerCase() === email);
  if (!already) {
    list.people.push({
      email,
      role: invite.role === "editor" ? "editor" : "viewer",
      // Kept so he can see *how* somebody got on the film, which is the
      // question he will actually ask when a name he half-recognises appears.
      via: invite.note || "an invite",
      joined: new Date().toISOString().slice(0, 10),
    });
    const saved = await savePeople(env, project, list);
    if (!saved) return page(409, "Try again", "");
  }

  return new Response(null, { status: 302, headers: { location: `/f/${project}` } });
}

/** Where the Diagrams page keeps whether the share link may draw. */
function diagramSettingsKey(project) {
  return `${keys.pages(project).replace(/pages\/$/, "")}diagram.settings.json`;
}

/**
 * Whether this request is a link visitor the owner has let draw on the plans.
 * Only on the share host, only a viewer (a link never carries more), and only
 * unless the film's switch was stored off (on by default).
 */
async function linkMayDraw(env, project, role, sharing) {
  if (!sharing || role !== "viewer") return false;
  const got = await env.BUCKET.get(diagramSettingsKey(project));
  if (!got) return true;
  try { return (await got.json()).publicEdit !== false; } catch { return true; }
}

/** The one gate. Everything that changes a film goes through here. */
function mustEdit(role) {
  if (role === "editor") return null;
  return problem(403, "View only");
}

async function putPeople(request, env, project, who) {
  const text = await request.text();
  if (text.length > MAX_PEOPLE) return problem(413, "That list is too long.");
  let sent;
  try {
    sent = JSON.parse(text);
  } catch {
    return problem(400, "That is not a list of people.");
  }

  const people = [];
  for (const person of Array.isArray(sent.people) ? sent.people : []) {
    const email = String((person && person.email) || "").toLowerCase().trim();
    if (!EMAIL.test(email)) continue;
    people.push({
      email,
      role: person.role === "editor" ? "editor" : "viewer",
      via: String(person.via || "").slice(0, 80) || undefined,
      joined: /^\d{4}-\d{2}-\d{2}$/.test(String(person.joined || "")) ? person.joined : undefined,
    });
  }
  const links = [];
  for (const link of Array.isArray(sent.links) ? sent.links : []) {
    if (!link || !/^[0-9a-f]{64}$/.test(String(link.hash || ""))) continue;
    links.push({
      hash: link.hash,
      // **The key itself, kept — his call, 2026-09-01.** It used to be hashed
      // and thrown away, so the address existed only while it was on screen.
      // That bought less than it cost: the thing it protected against is
      // somebody reading this bucket, and anybody who can read this bucket can
      // already read every film in it whole. Keeping it is what lets Copy link
      // work the way it does in a Google document, which is what he asked for.
      // Verification is unchanged — a presented key is still matched by hash.
      key: LINK_KEY.test(String(link.key || "")) ? link.key : "",
      role: link.role === "editor" ? "editor" : "viewer",
      note: String(link.note || "").slice(0, 80),
      // Off means the address is kept and refused. See `roleFor`.
      off: link.off === true,
      expires: /^\d{4}-\d{2}-\d{2}$/.test(String(link.expires || "")) ? link.expires : null,
      // A password, if he set one. Both are made in the browser: the salt is
      // random and `pass` is the hash of salt + password, so the hub can check
      // an answer and could never work out the word itself.
      salt: /^[0-9a-f]{16,64}$/.test(String(link.salt || "")) ? link.salt : null,
      pass: /^[0-9a-f]{64}$/.test(String(link.pass || "")) ? link.pass : null,
    });
  }

  // **He cannot take himself off.** A film whose only editor removes himself is
  // a film nobody can ever grant anybody a part in again — the list would need
  // a hand into the bucket to repair. He is an editor by the worker's own rule
  // whatever the list says, so this only stops the list from *saying* something
  // untrue. Both of his addresses, since both of them are him.
  for (const owner of owners(env).reverse()) {
    if (!people.some((p) => p.email === owner)) people.unshift({ email: owner, role: "editor" });
  }

  const invites = [];
  for (const invite of Array.isArray(sent.invites) ? sent.invites : []) {
    if (!invite || !/^[0-9a-f]{64}$/.test(String(invite.hash || ""))) continue;
    invites.push({
      hash: invite.hash,
      key: LINK_KEY.test(String(invite.key || "")) ? invite.key : "",
      role: invite.role === "editor" ? "editor" : "viewer",
      note: String(invite.note || "").slice(0, 80),
      expires: /^\d{4}-\d{2}-\d{2}$/.test(String(invite.expires || "")) ? invite.expires : null,
    });
  }

  const list = { version: 1, people, links, invites };
  const saved = await savePeople(env, project, list);
  if (!saved) return problem(409, "List changed. Reload.");
  return json({ ...list, setBy: who.email || "a link" });
}

// ------------------------------------------------------------------ the pages

/**
 * Every deck he can open, across every film.
 *
 * A deck belongs to a film, but he does not think about them a film at a time —
 * he thinks about the one he is working on. So they are gathered here, with the
 * way into each and its printed copy beside it.
 */
async function deckShelf(env, who) {
  const films = await filmsFor(env, who);
  for (const film of films) {
    // One at a time, for the reason `landing` gives.
    film.front = await frontOf(env, film.project);
    film.base = slugOf(film.title) ? `/${slugOf(film.title)}` : `/f/${film.project}`;
    const docs = film.front.documents || [];
    // **A deck is a page that has a deck's record, not one wearing a stamp.**
    // His Call Her Back bible came from Notion and is published to by Deck
    // Editor, so its section says `notion` while it is a deck in every way that
    // matters — and filtering on the stamp showed him an empty hub. Listing
    // what is actually under `decks/` also agrees exactly with what the editor
    // will open, since that route refuses a page with no record.
    const held = await env.BUCKET.list({ prefix: keys.decks(film.project), limit: 200 });
    const named = new Map((film.front.sections || []).map((s) => [s.slug, s.name]));
    film.decks = (held.objects || [])
      .map((o) => o.key.slice(o.key.lastIndexOf("/") + 1))
      .filter((f) => f.endsWith(".json"))
      .map((f) => f.slice(0, -5))
      .map((slug) => {
        const name = named.get(slug) || RECORD_PAGES.get(slug) || slug;
        return {
          slug,
          name,
          // Its printed copy, if the press has filed one under that name.
          pdf: (docs.find((d) => d.kind === "lookbook" && d.name === name) || {}).file || "",
        };
      });
  }
  return html(decksBody(films, who), "Decks", 200, { front: true });
}


async function landing(env, who, url) {
  const films = await filmsFor(env, who);
  // **Three at a time, each read to the end before the next is opened.** An
  // R2 object is an open response until its body has been read, and about six
  // may be open at once — the rule the change logs are fetched under. One at
  // a time was a second and a half for eight films (2026-10-02); three lanes
  // keep a cold film's replay, which reads its logs one by one, well inside
  // the six. Small cards are read whole as they arrive (`once.js`).
  let next = 0;
  const lane = async () => {
    while (next < films.length) {
      const film = films[next++];
      film.front = await frontOf(env, film.project);
      // Its name if it has one, its id if the name squeezes to nothing.
      film.base = slugOf(film.title) ? `/${slugOf(film.title)}` : `/f/${film.project}`;
    }
  };
  await Promise.all([lane(), lane(), lane()]);
  return html(shelfBody(films, who, isAdmin(env, who)), "Films", 200, { front: true, shelf: true });
}


/**
 * A film's own page — the front of house.
 *
 * Drawn here, on the server, out of `front.json` alone, so it arrives at once.
 * The shot list behind it still replays every change log in the browser; a page
 * somebody opens standing up, to find out where they are going on Tuesday, must
 * not have to.
 */
async function filmPage(env, project, role, who, url, base) {
  const title = await titleOf(env, project);

  // **Who may do what, on the web** — his ruling that this is set from the Mac,
  // the iPhone or here, none of them the master. Editors only, and the worker
  // refuses the list to anybody else whatever this page decides to draw.
  //
  // It hangs off the film's own address rather than one of its own because the
  // viewer already links to it that way, and a working link is worth more than
  // a tidy one.
  if (url.searchParams.get("people") !== null) {
    if (role !== "editor") return page(403, "Editors only", "");
    return new Response(null, { status: 302, headers: { location: `${base}/share` } });
  }

  // Whether anybody holds an unlisted link, so the button can say so. One
  // small object, and only for an editor — nobody else is shown the button.
  // Both at once: the card and the list do not depend on each other, and read
  // in turn they are most of what the page costs.
  // **Whether there are other films to go back to.** His instruction,
  // 2026-09-02: the way out is offered only to somebody who has somewhere to
  // go. Read alongside the rest so it costs nothing but its own latency.
  const { releasedFor } = await import("./portalselects.js");
  const [people, front, mine, visible, listing, released] = await Promise.all([
    role === "editor" ? peopleOf(env, project) : null,
    frontOf(env, project),
    manyFilms(env, who),
    visibleOf(env, project),
    changeListing(env, project),
    releasedFor(env, project),
  ]);
  const many = Boolean(mine);
  const shared = Boolean(people && people.links.length);
  // **The panel's script wherever its button is.** Without it the button is
  // still a working link to the page — which is the point of it being one.
  const panel = await sharePanel(env, project, title, role, who, base, front);
  // **Since You Looked** (move 5): the bucket's own write times, narrowed to
  // the pages this person may see — see `since.js`.
  // **A Released project's selects** (portalselects.js, 2026-10-17): on the
  // home page only, read off the record, never stored in the front.
  const seen = { ...shotView(front, shootIn(base)), released };
  const since = changesOf(listing, seen, base, role, who, isAdmin(env, who), visible);
  return html(homeBody(base, title, role, who, seen, shared, many, visible, isAdmin(env, who), since) + panel,
              title, 200, { front: true, ...sharedAs(url, base, title, front) });
}

/**
 * The shot list and its three siblings.
 *
 * The page arrives knowing which film, what this person may do, and which mode
 * to open in; the browser replays the change logs into the engine to draw the
 * rest. Everything the client needs is on `window.HUB` rather than fetched, so
 * the first paint does not wait on a round trip to learn its own name.
 */
/**
 * **The shape of the film, in the HTML itself, carrying its own look.**
 *
 * A bar saying *Reading the film* used to be the first thing on screen, and it
 * lived inside `film.js` — so on a slow connection nothing was drawn at all
 * until the script arrived. Measured at 40 KB/s: two and a half seconds of a
 * black page, then everything at once.
 *
 * **And its own stylesheet, which is the part that is easy to get wrong.**
 * Written into the page but styled from `hub.css`, the outline was in the
 * document and invisible — because at that speed the stylesheet had not
 * arrived either. Anything meant to be seen before the page is loaded cannot
 * depend on the page being loaded, so this carries literal colours rather than
 * the tokens: they are `hub.css`'s own dark values, and they only ever stand in
 * for a fraction of a second.
 *
 * **The table's own metrics, so nothing jumps.** A band and a row are the
 * heights `hub.css` gives them, and it fades in after a beat — a film already
 * kept in the browser draws before the outline is ever visible, which is what
 * stops a fast load flickering.
 *
 * It says nothing out loud. `aria-busy` is for anything reading the page
 * aloud, which cannot see a shape at all.
 */
function ghost() {
  const bone = (w) => `<span class="gb" style="width:${w}px"></span>`;
  const row = `<div class="gr">${bone(22)}<span class="gb gg"></span>${bone(54)}</div>`;
  const band = (wide) =>
    `<div class="gband"><div class="gt">${bone(26)}${bone(wide)}</div>` +
    `<div class="gs">${bone(88)}${bone(64)}</div></div>` + row.repeat(3);
  return `<style>
    .ghost{position:absolute;inset:0;display:flex;background:#0E0E11;
      animation:ghostin .25s ease-out .3s both}
    @keyframes ghostin{from{opacity:0}to{opacity:1}}
    @keyframes gbeat{50%{opacity:.45}}
    .ghost .gnav{width:248px;flex:none;background:#0D0D0D;border-right:1px solid rgba(255,255,255,.10)}
    .ghost .gmain{flex:1;min-width:0}
    .ghost .gbar{display:flex;align-items:center;gap:9px;padding:9px 14px;
      border-bottom:1px solid #232329}
    .ghost .gband{background:#1A1A20;padding:11px 14px 9px;border-bottom:1px solid #232329}
    .ghost .gt{display:flex;align-items:center;gap:9px}
    .ghost .gs{display:flex;gap:14px;margin-top:8px}
    .ghost .gr{display:flex;gap:12px;padding:11px 14px;border-bottom:1px solid #232329}
    .ghost .gb{display:inline-block;height:11px;border-radius:3px;background:#26262E;
      animation:gbeat 1.4s ease-in-out infinite}
    .ghost .gg{flex:1;min-width:0}
    .ghost .gsp{flex:1}
    @media (prefers-reduced-motion:reduce){
      .ghost{animation-name:none;opacity:1}.ghost .gb{animation:none}}
  </style><div class="ghost" aria-busy="true" aria-label="Reading the film">` +
    `<div class="gnav"></div><div class="gmain">` +
    `<div class="gbar">${bone(120)}<span class="gsp"></span>${bone(74)}</div>` +
    `${band(190)}${band(140)}${band(220)}</div></div>`;
}

/**
 * **What the program is told about the shoots** — SL-1396. The tabs, drawn
 * by the program's own rail as `railFor` draws them, and the shoot it is on:
 * its days and the shot list sections it covers, which the Shot List and the
 * Schedule narrow to. A section or a day no shoot claims stays on every tab.
 */
function shootFor(front, base) {
  const lead = leadShoot(front);
  return {
    on: front.shootOn.slug,
    base: filmBase(base),
    // **The one shoot picker** (portalmodes.js): All Shoots first, a tag on each.
    ...(front.portalmodes ? { picker: true } : {}),
    pages: front.shootPages || {},
    tabs: front.shoots.map((one) => ({
      slug: one.slug, name: one.name, start: one.start, end: one.end, ...(front.portalmodes ? { base: one.base || "" } : {}),
      // The Shoots row's id (piece D): a scene or day that names its shoot is matched by it.
      ...(one.id ? { id: one.id } : {}),
      status: one.status === "Wrapped" ? "Wrapped" : one === lead ? "Next" : "Upcoming",
      sections: one.sections,
    })),
  };
}

async function viewerPage(env, project, role, who, mode, base, seen = emptyVisible(), url = null, lens = null) {
  // The key the address carried, so the icon and the manifest can be fetched
  // on the share host — the same rule as `sharedAs`.
  const k = url && url.searchParams.get("k");
  const key = k ? `?k=${encodeURIComponent(k)}` : "";
  // **The film's own mark and colour travel into the app.** His instruction,
  // 2026-09-02: the title should land in the app's bar carrying its icon, and
  // the app's highlight should be the film's colour rather than the program's
  // blue. Both live on the card, so the page hands them over the same way it
  // hands over the title — read together, because neither waits on the other.
  // **`mine` is read for the same reason the record's pages read it**: the
  // way back to the other films is offered only to somebody with somewhere to
  // go, and the app's rail has to offer it on exactly the same terms as the
  // record's — his report of 2026-09-16 was the arrow coming and going as he
  // crossed between the two, and every row under it moving with it.
  const [title, stored, mine] = await Promise.all([
    titleOf(env, project), frontOf(env, project), manyFilms(env, who),
  ]);
  // **The shoot this address is on** (SL-1396) — the rail's counts and pages
  // are that shoot's, and the program narrows the shot list and the
  // schedule to it (`HUB.shoot`).
  const front = shotView(stored, shootIn(base));
  const many = Boolean(mine);
  /**
   * **What Visibility hides is hidden here too.** His report, 2026-09-10:
   * *"when you click into one of the Shotlister Studio based pages … every
   * tab on the sidebar, even the ones that I've hidden from the public link,
   * become exposed."* The record's pages filter their rail through `maySee`;
   * the app draws its own rail in the browser and was never told. So the
   * hidden keys travel with the page, the names of hidden pages do not travel
   * at all, and the app refuses a switch to a hidden mode as the worker
   * refuses its address. An editor is hidden nothing, as everywhere.
   */
  const admin = isAdmin(env, who) && who.via !== "link";
  // **On a view link only the Shot List is a page** — its holder's rail has
  // nothing else in it, and the worker refuses every other address anyway.
  const onLink = lens && linkHeld(who);
  const shown = (key) => !onLink && maySee(seen, "sections", key, role)
    && boardOpen((front.sections || []).find((one) => one.slug === key), who, admin);
  return html(
    `<div id="film">${ghost()}</div>${told(project, title, role, who, mode, {
      base,
      mark: front.mark,
      // **The mods this project has on** (studiomods.js): the app draws a
      // mod's pieces only when it is here. None for most projects.
      mods: await (await import("./studiomods.js")).modsOfFilm(env, project),
      // **The rail is the same rail here, so it needs the same facts.** The
      // engine gives the app its scenes, places and boards; the crew and the
      // documents live in `front.json`, which the app never reads. Counts and
      // the names of his own Notion sections are handed over rather than
      // fetched, so the rail can be drawn on the first frame instead of
      // appearing a beat later with numbers in it.
      rail: {
        // **The same top and the same numbers as the record's rail.** `back`
        // is the Projects arrow, on the same terms `railFor` draws it; `counts`
        // are the card's, so the four rows carry their numbers from the first
        // frame rather than arriving blank and filling in once the film has
        // been read. The engine's live count takes over the moment it exists.
        back: many ? "/" : "",
        counts: onLink ? {} : { ...(front.counts || {}), scenes: shotListCount(front) },
        crew: shown("people") ? (front.crew || []).filter((one) => maySee(seen, "crew", one.name, role) && meSees(seen, "crew", one.name, admin)).length : 0,
        documents: shown("documents") ? (front.documents || []).filter((doc) => !isArchived(front, `doc:${doc.name}`) && maySee(seen, "documents", doc.name, role) && meSees(seen, "documents", doc.name, admin)).length : 0,
        // **`source` travels too, so the rail can say who is feeding a page.**
        // Whether Notion is still writing a page is the one thing about it he
        // could never see, and it is the thing that decides whether editing it
        // in Notion will reach the site at all.
        sections: (front.sections || [])
          .filter((one) => shown(one.slug))
          .map((one) => ({ at: one.slug, name: one.name, type: one.type, source: one.source })),
        // **His categories and his order**, so the program draws the rail the
        // way the record's pages draw it: the headings are the film's
        // categories (`shelves`), each page stands under the one it is filed
        // in (`filed`, by address), in the order of `order`. `railGroups` in
        // `src/front.js` is the same rule as `inGroups` in `public/film.js`;
        // without this the Shot List sits where he put it on one side of the
        // door and at the top on the other.
        shelves: shelfList(front).map((one) => ({ id: one.id, name: one.name, ...(one.builtIn ? { builtIn: true } : {}) })),
        filed: Object.fromEntries([
          ...[...RECORD_PAGES.entries(), ...PROGRAM_PAGES.entries()].map(([at, name]) => [at, shelfIdOf(front, at, (front.labels || {})[at] || name, "page", "")]),
          ...(front.sections || []).map((one) => [one.slug, shelfIdOf(front, one.slug, one.name, "page", one.type || "")]),
          ...pinnedDocs(front).map((d) => [d.at, shelfIdOf(front, d.at, d.name, "doc", "")]),
        ]),
        order: front.rail || [],
        // **What is in the Library**, so the program's rail leaves those rows
        // off exactly as the record's does (`offSidebar` in `front.js`).
        // **…and the pages of a mode that is off** (portalmodes.js), the same way.
        library: [...(front.library || []), ...(front.archive || [])].map((one) => one.at).concat(front.modesOff || []),
        // **The documents pinned to the sidebar** (2026-10-11), each a row that
        // opens its file or link; `railDocs` in `pages.js` is the one list.
        docs: railDocs(base, front, seen, role, admin).map((d) => ({ at: d.at, name: d.name, href: d.href, file: Boolean(d.file) })),
        // **The icons he has picked**, so the program's rail draws what the record's does.
        icons: front.icons || {},
        // **The names he gave pages on the portal**, so the program's rail says them too.
        labels: front.labels || {},
        // How many things the Library holds for this reader — the number on
        // its row, drawn by the program as the record's rail draws it.
        libraryN: libraryCount(front, seen, role, who, admin),
        // The keys of the film's own screens and pages that this reader may
        // not see. `railParts` leaves them out and `wire` refuses them.
        // **An empty page is left off too** (`unfilled`), and an editor is
        // told which rows are empty so the program's rail draws them quiet,
        // as the record's does.
        hidden: role === "editor" ? [] : [...(seen.sections || []), ...unfilled(front, seen)],
        empty: role === "editor" ? unfilled(front, seen) : [],
        // **What he hid For Me** (`meSees`): off his rail like an empty row,
        // never refused — the screen still opens if he goes to it.
        mine: [],
        // **What the sidebar's editor needs** (move 1): which pages a link
        // holder is not shown, which are hidden for him, which can be renamed,
        // and the Built In pages for Add. `railEdit` in `pages.js` is the one
        // place that works it out, for both rails. An editor's only.
        edit: role === "editor" ? railEdit(front, seen, admin) : null,
        // **"Updated N minutes ago", and Refresh once it can** (Refs 1161,
        // 1155) — the record's rail draws it with `freshLine`, and so does
        // this one, from the same function, so the two cannot differ. Posted
        // plainly here: the program is not a page `deep.js` lands in place.
        fresh: isAdmin(env, who)
          ? freshLine(base, front, { shots: "shotlist", locations: "locations", boards: "boards", schedule: "schedule", diagrams: "diagrams" }[mode] || "shotlist", true)
          : "",
      },
      ...(role === "editor" ? { owners: owners(env) } : {}),
      // **The shoots, for the rail's switcher and the program's narrowing.**
      ...(front.shootOn ? { shoot: shootFor(front, base) } : {}),
      // **The app's Share button is the same button.** A link holder reading
      // the shot list has the same nothing to copy out of the address bar as
      // one reading the Visual Bible.
      ...(linkHeld(who) ? { linkKey: linkHeld(who) } : {}),
      ...(await friendlyOf(env, project, title, role, who)),
      // **The view this page is** (`views.js`): its name and filter to draw,
      // its code to ask `api/view` with, its own address for Copy link.
      ...(lens ? { lens: await lensTold(env, project, lens, url) } : {}),
      // **Said by the server, not worked out by the page.** The app could
      // compare his address against `owners`, but a page that decides for
      // itself who is an administrator is a page that can be argued with —
      // and the panel it links to is refused by the worker anyway. This only
      // decides whether the way in is drawn.
      admin: isAdmin(env, who),
    })}` +
      `<script src="/icons.js?v=${BUILD}"></script><script src="/film.js?v=${BUILD}" type="module"></script>` +
      (role === "editor" || linkHeld(who) ? `<script src="/share.js?v=${BUILD}" type="module"></script>` : ""),
    title,
    200,
    // **The app needs the front of house's two files as much as any page does.**
    // Coming here from the film's page they are already loaded, because that is
    // the same document — so Home travelled back beautifully and I measured it
    // doing so. **Arriving here directly, they are not**, and Home was a bare
    // `<a>` doing a page load: no `deep.js` to catch the click, no `front.css`
    // to say how the move looks. That is a link somebody is sent, a bookmark,
    // and every reload — which is most of the times he pressed it. His report,
    // 2026-09-03, and my harness had only ever tested the half that worked.
    //
    // Safe to load here only since `front.css` stopped putting its palette on
    // `:root`: it would otherwise have painted this page's ink near-white.
    //
    // **And a card, like every other page a person may be sent.** Until
    // 2026-10-01 these five tabs unfurled as a bare address.
    (() => {
      const at = url && [...PROGRAM_PAGES.keys()].find((slug) => MODES[slug] === mode && url.pathname.endsWith(`/${slug}`))
        || [...PROGRAM_PAGES.keys()].find((slug) => MODES[slug] === mode) || "";
      const card = url ? sharedAs(url, base, title, front, at) : { icon: `${base}/icon.svg${key}`, film: { base, q: key, title } };
      if (card.og && at) card.og.title = `${PROGRAM_PAGES.get(at)} · ${title}`;
      if (card.og && lens) card.og.title = `${lens.name} · ${title}`;
      return { front: true, ...card };
    })()
  );
}

/** What a view's page is told about the view — never its key. */
async function lensTold(env, project, lens, url) {
  const said = viewSaid(lens, await shortOf(env, project), project);
  const host = url ? url.host.replace(/^(mcp|share)\./, "") : "your-domain.example";
  const local = /^(localhost|127\.)/.test(host);
  return { ...said, address: `${url ? url.protocol : "https:"}//${local ? host : `share.${host}`}${said.path}` };
}

/**
 * The share panel, on a page that has a Share button.
 *
 * **Every such page, not only the film's own.** It was on the film's page and
 * in the app and nowhere else — so pressing Share on the Visual Bible, or
 * People, or one of his own Notion pages was a page load onto `/share`, and
 * that page had no way of knowing where it had been pressed. It copied the
 * film's front door every time. His report, 2026-09-08.
 *
 * Without it the button is still a working link to that page, which is the
 * point of it being one.
 */
/**
 * What the rail's foot needs on Add, Headings and Visibility — whether the
 * film is out on a link, whether he is the administrator, and the share
 * panel's script — so those three wear the same foot as every other page.
 */
async function toolRail(env, project, title, role, who, base, front) {
  const people = role === "editor" ? await peopleOf(env, project) : null;
  return {
    shared: Boolean(people && people.links.length),
    admin: isAdmin(env, who),
    // So Add, Headings and Visibility leave out what he hid For Me, as every
    // other page's rail does.
    visible: await visibleOf(env, project),
    panel: await sharePanel(env, project, title, role, who, base, front),
  };
}

async function sharePanel(env, project, title, role, who, base, front) {
  const key = linkHeld(who);
  if (role !== "editor" && !key) return "";
  return `${told(project, title, role, who, "", {
    base,
    mark: front.mark,
    // **Whether the panel has a Visibility tab** (Ref 1153). The page is told
    // only so it can draw the tab; `/visibility` still refuses anybody else.
    ...(isAdmin(env, who) ? { admin: true } : {}),
    ...(role === "editor" ? { owners: owners(env) } : {}),
    ...(key ? { linkKey: key } : {}),
    ...(await friendlyOf(env, project, title, role, who)),
  })}<script src="/share.js?v=${BUILD}" type="module"></script>`;
}

/**
 * The film's short name, for the page's Copy link — `share.…/hla`.
 *
 * **Made on first sight.** An editor looking at any page of a film gives it
 * a short name if it has none (`ensureShort`), so every film is friendly
 * without anybody asking. A link holder never makes one.
 *
 * **`friendly` says the short name may stand in for this person's link.**
 * True for an editor and for whoever came in on the general link — the one
 * the short name stands for. Somebody on a different link (a password one, a
 * dated one) keeps their key on the address, because `/hla` would open the
 * general link and not theirs.
 */
async function friendlyOf(env, project, title, role, who) {
  const short = role === "editor" ? await ensureShort(env, project, title) : await shortOf(env, project);
  if (!short) return {};
  const key = linkHeld(who);
  const friendly = role === "editor" || (key && key === await generalKeyOf(env, project));
  return { short, friendly: Boolean(friendly) };
}

/**
 * The key somebody came in on, if they came in on one at all.
 *
 * **Why the page has to be told it.** The cookie that remembers a key is
 * `HttpOnly`, so the page cannot read it — and every link inside the film is a
 * plain address with no key on it, so one click and the address bar is showing
 * something that opens nothing for anybody else. His report, 2026-09-08:
 * *"just copying the url doesn't lead you to the right place."* Handing the key
 * back to the page it let in gives away nothing: they are holding it already.
 */
function linkHeld(who) {
  return who && who.via === "link" && LINK_KEY.test(String(who.key || "")) ? who.key : null;
}

/** What the browser is told about itself, before it asks anything. */
function told(project, title, role, who, mode, more) {
  const hub = { project, title, role, email: who.email, via: who.via, mode, ...more };
  return `<script>window.HUB = ${JSON.stringify(hub).replace(/</g, "\\u003c")};</script>`;
}

/**
 * Every picture the film holds, newest-looking first.
 *
 * Both stores: what the film pushed (`media/`) and what the portal was given
 * (`docs/`), because a poster uploaded here is as fair an answer as a frame.
 * Capped — a picker is a page, not an archive.
 */
async function picturesOf(env, project) {
  const IMAGE = new Set(["png", "jpg", "jpeg", "heic", "webp", "gif"]);
  const names = [];
  for (const folder of ["docs", "media"]) {
    for (const object of await listAll(env, keys.folder(project, folder))) {
      const name = object.key.split("/").pop();
      if (MEDIA_NAME.test(name) && IMAGE.has(name.split(".").pop().toLowerCase())) names.push(name);
    }
  }
  return [...new Set(names)].slice(0, 400);
}

/** Set — or clear — the film's photograph, then send the browser back to it. */
async function setPhoto(request, env, project, base) {
  const form = await request.formData();
  const pick = String(form.get("pick") || "");
  if (pick && !MEDIA_NAME.test(pick)) return problem(400, "That is not a picture.");
  const front = await frontOf(env, project);
  front.key_image = pick;
  front.updated = new Date().toISOString();
  await saveFront(env, project, front);
  // **303, not 302.** A form was posted; without it the browser repeats the
  // post on every refresh and on the back button.
  return new Response(null, { status: 303, headers: { location: base || `/f/${project}` } });
}

function needSignIn(env) {
  const wired = Boolean(env.ACCESS_TEAM && env.ACCESS_AUD);
  return html(
    `<div class="signin">
       <div class="wordmark">Nathaniel Regier Studio</div>
       <div class="sub2">Shotlister</div>
       <p class="empty">${wired ? "Sign in to continue" : "Sign-in is not set up yet"}</p>
     </div>`,
    "Sign in",
    401,
    { dark: true }
  );
}

// ---------------------------------------------------------------- the bytes

/**
 * **What a piece of a file was actually asked for.**
 *
 * Parsed here rather than handed to the store, because the store answers a
 * ranged read with the size of the *piece* and not the size of the file — so
 * everything written back to the player about "of how many" was worked out
 * from the wrong number. A two-byte probe, which is the first thing Safari
 * sends a video, came back saying the whole file was two bytes long.
 *
 * `null` means serve the lot: either nothing was asked for, or what was asked
 * for is a shape this does not read (several pieces at once, which no player
 * here sends), and handing back the whole file is always a true answer.
 */
function pieceOf(header, whole) {
  const asked = /^bytes=(\d*)-(\d*)$/.exec(String(header || "").trim());
  if (!asked) return null;
  const [, from, to] = asked;
  if (from === "" && to === "") return null;
  // `bytes=-500` — the last five hundred, which is where an mp4 keeps its index
  // when it was not written for streaming.
  if (from === "") {
    const length = Math.min(Number(to), whole);
    return length > 0 ? { offset: whole - length, length } : "past the end";
  }
  const offset = Number(from);
  if (offset >= whole) return "past the end";
  const end = to === "" ? whole - 1 : Math.min(Number(to), whole - 1);
  if (end < offset) return "past the end";
  return { offset, length: end - offset + 1 };
}

/**
 * What a held file should be called when somebody saves it.
 *
 * **His note, 2026-09-07:** *"the naming of the pdf download needs to be
 * something legible — like name of the project then document kind divided by
 * '-'"*. A document is stored content-addressed, so on disk it is
 * `29cb989a….pdf` and that is what every Download button handed him. The film
 * and the document's own name make the readable one: `Call-Her-Back-Visual-Bible.pdf`.
 *
 * A document whose name already carries the film's — *Script - Call Her Back* —
 * is not said twice.
 *
 * **And since 2026-10-06 (Ref 1570) the apps' own system**, so a file saved from
 * here and one exported from the Mac or phone sort together:
 * `Film_Document_YYYY-MM-DD.ext` — `Lets-Bake_Visual-Bible_2026-10-06.pdf`.
 * Fields joined by underscores, words by hyphens, the date last.
 */
function saveAsName(film, doc, file) {
  const bare = (said) => String(said || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  const fields = bare(doc).includes(bare(film)) ? [exportPart(doc, 48)] : [exportPart(film, 32), exportPart(doc, 48)];
  const stem = fields.filter(Boolean).join("_");
  const extension = String(file || "").split(".").pop().toLowerCase();
  return `${stem || "document"}${/^[a-z0-9]{1,8}$/.test(extension) ? `.${extension}` : ""}`;
}

/**
 * **One field of an exported file's name** — `FileNames.part` in
 * `shared/FileNames.swift`, the Mac's and the phone's, word for word (Ref 1570):
 * words kept with their capitals, apostrophes dropped, every other run of
 * punctuation or space one hyphen, cut at a word when it runs long.
 * `Let's Bake` is `Lets-Bake`.
 */
export function exportPart(text, longest) {
  let out = String(text || "").replace(/['\u2019]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-+|-+$/g, "");
  if (out.length > longest) {
    out = out.slice(0, longest);
    const cut = out.lastIndexOf("-");
    if (cut > longest / 2) out = out.slice(0, cut);
  }
  return out;
}

/**
 * The same name, with the day the file was filed on the end of it.
 *
 * **His report, 2026-09-07:** the PDF he downloaded was not the newest. It was
 * not the portal's fault — the portal was serving the latest print. Every
 * download arrives under the same readable name (see `saveAsName`), and macOS
 * does not overwrite: it keeps the first copy and calls the next one
 * `… (1).pdf`. So after three prints the file called
 * `Call-Her-Back-Visual-Bible.pdf` in his Downloads was the *oldest* of them,
 * and it is the one anybody would double-click. Four copies of the bible were
 * sitting there, and he was reading the first.
 *
 * A version in the name is what tells them apart, and the version people
 * actually use for a document like this is the date — which is how he already
 * names them in Drive: `Call_Her_Back_Visual_Bible_2026-09-07.pdf`. Joined to
 * the rest by an underscore, as the apps' exports are (Ref 1570).
 *
 * **The file's own day, not today's.** Taken from when the bytes were stored,
 * so re-downloading last week's print still names last week — the name follows
 * the document rather than the moment it was fetched.
 *
 * **His day, not UTC.** A print made at ten at night here is already tomorrow
 * in UTC, which would have filed tonight's book under the 8th and disagreed
 * with both his Drive folder and his memory of making it.
 */
function datedName(named, when) {
  let day = "";
  try {
    day = new Intl.DateTimeFormat("en-CA", {
      timeZone: "America/Vancouver", year: "numeric", month: "2-digit", day: "2-digit",
    }).format(when);
  } catch {
    // A runtime without the timezone data still gets a dated name, near enough.
    day = new Date(when).toISOString().slice(0, 10);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return named;
  const dot = named.lastIndexOf(".");
  return dot > 0 ? `${named.slice(0, dot)}_${day}${named.slice(dot)}` : `${named}_${day}`;
}

/**
 * **What the Script page needs beyond the card** (SL-1338): which drafts'
 * PDFs have reached the bucket — a draft's log can arrive before its file —
 * and, for the draft being read when its PDF has not, its words instead.
 * One `head` per draft, all at once; a film has a handful.
 */
async function scriptExtra(env, project, front, asked) {
  const drafts = front.scripts || [];
  const there = await Promise.all(drafts.map((d) =>
    env.BUCKET.head(keys.inFolder(project, "media", `${d.stem}.pdf`)).then(Boolean, () => false)));
  const pdfs = drafts.filter((_, i) => there[i]).map((d) => d.stem);
  const one = drafts.find((d) => d.stem === asked) || drafts[0];
  // **Only for the draft being read, and only when there are marks to draw**
  // (Ref 1568): the Script page's Marks view needs its words in the bucket.
  const marked = Boolean(one) && (front.play_shots || 0) > 0
    ? await env.BUCKET.head(keys.inFolder(project, "media", `${one.stem}.txt`)).then(Boolean, () => false)
    : false;
  let text = "";
  if (one && !pdfs.includes(one.stem)) {
    const got = await env.BUCKET.get(keys.inFolder(project, "media", `${one.stem}.txt`));
    if (got) text = await got.text();
  }
  return { draft: one ? one.stem : "", pdfs, text, marks: marked };
}

async function media(env, project, name, request, folders = ["media"], saveAs = "", exact = false) {
  if (!MEDIA_NAME.test(name)) return problem(400, "That is not a picture.");
  const asked = request.headers.get("range");

  // **A picture costs one call and a clip costs two.** Only a video ever sends
  // a range, and only a range needs the file's own size — so the extra ask is
  // paid on the handful of requests that need it rather than on all four
  // hundred tiles of a mood board.
  let got = null;
  let piece = null;
  let whole = 0;
  for (const folder of folders) {
    const key = keys.inFolder(project, folder, name);
    if (asked) {
      const meta = await env.BUCKET.head(key);
      if (!meta) continue;
      whole = meta.size;
      piece = pieceOf(asked, whole);
      if (piece === "past the end") {
        return new Response(null, {
          status: 416,
          headers: { "content-range": `bytes */${whole}`, "accept-ranges": "bytes" },
        });
      }
      got = await env.BUCKET.get(key, piece ? { range: piece } : undefined);
    } else {
      // **Read or discard inside the loop.** An R2 object is an open response
      // until its body is read, and about six may be open at once; a loop that
      // kept a miss around would be holding one open for nothing.
      got = await env.BUCKET.get(key);
    }
    if (got) break;
  }
  // **A clip's poster asked for as `.jpg` and held as `.png`.** Posters are
  // JPEG since 2026-09-15 and every page asks for `.jpg`; a film pushed
  // before that, or by an older device, still holds the PNG under the same
  // name. One more look before saying no, on that one shape of miss only.
  // Both extensions come from `relay/layout.json`, where the rule is written
  // once — the day the Mac changed and this did not is why it lives there.
  if (!got && !asked && name.endsWith(`.${poster.extension}`)) {
    const before = `${name.slice(0, -(poster.extension.length + 1))}.${poster.before}`;
    return await media(env, project, before, request, folders, saveAs, exact);
  }
  // **A clip asked for as `.mov` and held as `.mp4`.** The Mac keeps every
  // clip on the relay as an MP4 proxy, named by the original's hash; a page
  // that spells the name from the original's filename asks for `.mov` and was
  // told there was nothing — which is why his clips never played on a board
  // (his note, 2026-09-25) nor in the shot list's frames.
  if (!got && /\.(mov|m4v)$/i.test(name)) {
    return await media(env, project, name.replace(/\.(mov|m4v)$/i, ".mp4"), request, folders, saveAs, exact);
  }
  if (!got) return problem(404, "No such picture.");
  if (!asked) whole = got.size;

  const extension = name.split(".").pop().toLowerCase();
  const headers = new Headers();
  got.writeHttpMetadata(headers);
  headers.set("content-type", MIME[extension] || "application/octet-stream");
  // Content-addressed: the name is the bytes, so a picture can be held for
  // ever. This is the whole reason a film of two hundred photographs opens.
  headers.set("cache-control", "private, max-age=31536000, immutable");
  headers.set("etag", got.httpEtag);
  // **Say out loud that pieces can be asked for.** Safari on an iPhone decides
  // whether a video is worth starting from this header, before it fetches a
  // frame of it; ranges were answered here from the beginning and never
  // advertised, which is not the same thing.
  headers.set("accept-ranges", "bytes");
  // **`inline` or `attachment` — the link says which, because only it knows.**
  //
  // This used to be `inline` always, reasoning that a PDF opened from the film
  // should still open and that the Download buttons carry `download`, which
  // saves it either way. **The second half was untrue on a phone.** Safari on
  // iOS ignores `download`; the header is the only thing it listens to. His
  // report, 2026-09-08: *"the download PDF on Safari iOS just links to another
  // page where the PDF opens instead of downloading."* Reproduced in the
  // Simulator on iPhone 17 Pro before this changed, and it is exactly that.
  //
  // The two links already mean different things and the server could not tell
  // them apart. Now it can: the Download buttons ask with `?save=1`, a
  // Documents card does not and still opens in the viewer.
  //
  // The day the bytes were filed goes on the end, so two downloads of a
  // document that has been reprinted are two files and not `… (1).pdf`.
  // `exact` is a name that is the file's own — a LUT off the spec sheet —
  // and is never dated.
  const filed = saveAs && got.uploaded && !exact ? datedName(saveAs, got.uploaded) : saveAs;
  const toSave = new URL(request.url).searchParams.has("save");
  if (filed) {
    headers.set("content-disposition",
      `${toSave ? "attachment" : "inline"}; filename="${filed.replace(/"/g, "")}"`);
  }
  // **And on the way out, a file being saved is not announced as a PDF.**
  //
  // `attachment` alone is not enough on a phone, and this was measured rather
  // than assumed. In the Simulator on iPhone 17 Pro, 2026-09-08, with the
  // request confirmed reaching the worker and the cache defeated: a `.zip`
  // served `attachment` raises Safari's own *"Do you want to download …?"*, so
  // the download manager works and the header is honoured — and the identical
  // response for a `.pdf` is opened in the viewer anyway. Safari on iOS renders
  // a PDF whatever it is told; the content type is the only lever left.
  //
  // So a file the link asked to **save** goes out as bytes, and the name it
  // carries says what it is. Only the Download buttons take this path, so a
  // Documents card still previews in the viewer exactly as before.
  if (toSave && filed) headers.set("content-type", "application/octet-stream");

  if (piece) {
    headers.set("content-range", `bytes ${piece.offset}-${piece.offset + piece.length - 1}/${whole}`);
    headers.set("content-length", String(piece.length));
    return new Response(got.body, { status: 206, headers });
  }
  // **The length, always.** The body is a stream, so without this the answer
  // goes out with no size on it — and a player that cannot know how long a file
  // is cannot seek in it.
  headers.set("content-length", String(whole));
  return new Response(got.body, { headers });
}

// ------------------------------------------------------------------ plumbing

function cookie(request, name) {
  const jar = request.headers.get("cookie") || "";
  const found = jar.split(";").map((c) => c.trim()).find((c) => c.startsWith(`${name}=`));
  return found ? decodeURIComponent(found.slice(name.length + 1)) : null;
}

function initials(who) {
  if (!who.email) return "·";
  const name = who.email.split("@")[0].replace(/[^A-Za-z]+/g, " ").trim();
  const bits = name.split(/\s+/).filter(Boolean);
  if (!bits.length) return who.email[0].toUpperCase();
  return (bits[0][0] + (bits[1] ? bits[1][0] : "")).toUpperCase();
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
 * What a tab shows, and what a pasted link unfurls into.
 *
 * **The mark is the film's, not the product's.** His ask, 2026-09-04: a film's
 * own icon in the tab. Every film has one already — it comes off its Notion row
 * through `refresh.py` as a path and a colour — so this costs no new artwork,
 * and a crew member with four of his films open can tell them apart.
 *
 * **A link he pastes to a crew member should say which film it is.** Without
 * these a share link unfurls as a bare address, which tells the person nothing
 * and looks like something they should not click.
 *
 * **The password page carries one too** — his ruling, 2026-09-19. Until then
 * a locked link unfurled as the product's name and nothing of the film's, so
 * a forwarded link gave the title away to nobody; he chose the preview.
 */
function headMarks(opts) {
  // **A PNG beside the SVG, because Safari draws no SVG favicon.** Chrome
  // takes the SVG, named last; Safari, which skips it, takes the PNG. Both
  // are the film's own mark — see `icon.png` beside `icon.svg` in the route.
  const f = opts.film;
  // **The shelf is not a film.** His ruling, 2026-09-23: the product's own
  // mark (the viewfinder) also stands in for a film that has none of its own
  // yet, so wearing it on the shelf too made the one place that opens every
  // project look like it might just be an unconfigured film. `hub-icon.png`
  // is the shelf's own mark, worn wherever there is no film — never a film's.
  const png = f ? `${f.base}/icon.png${f.q}` : "/hub-icon.png";
  const icon = [
    `<link rel="icon" type="image/png" href="${esc(png)}">`,
    opts.icon ? `<link rel="icon" type="image/svg+xml" href="${esc(opts.icon)}">` : "",
    // **Everything the home screen needs.** His ask, 2026-09-20: the portal
    // added to an iPhone's home screen must be one app — and until this it
    // was not, because with no manifest iOS gave it no scope, and a tap on a
    // tab opened the browser inside the app with an X to come back. The
    // manifest names the film, gives the whole host as the scope, and points
    // at the PNG; the `apple-touch-icon` is what iOS actually draws on the
    // home screen, since it reads no icon out of a manifest. The manifest is
    // fetched with credentials or the apex hands back Access's sign-in page.
    `<link rel="apple-touch-icon" href="${esc(png)}">`,
    `<link rel="manifest" href="${esc(f ? `${f.base}/manifest.webmanifest${f.q}` : "/manifest.webmanifest")}" crossorigin="use-credentials">`,
    `<meta name="apple-mobile-web-app-title" content="${esc(f ? f.title : "Project Studio")}">`,
  ].filter(Boolean).join("\n");
  if (!opts.og) return icon;
  const o = opts.og;
  return [
    icon,
    `<meta property="og:type" content="website">`,
    `<meta property="og:site_name" content="Shotlister">`,
    `<meta property="og:title" content="${esc(o.title)}">`,
    o.said ? `<meta property="og:description" content="${esc(o.said)}">` : "",
    o.url ? `<meta property="og:url" content="${esc(o.url)}">` : "",
    // **A card with a picture, or a small one with none.** Naming a
    // `summary_large_image` and then failing to serve the image is the one
    // combination that unfurls worse than saying nothing at all.
    o.image
      ? `<meta property="og:image" content="${esc(o.image)}">\n` +
        `<meta property="og:image:width" content="1200">\n` +
        `<meta property="og:image:height" content="630">\n` +
        `<meta name="twitter:card" content="summary_large_image">`
      : `<meta name="twitter:card" content="summary">`,
    `<meta name="twitter:title" content="${esc(o.title)}">`,
  ].filter(Boolean).join("\n");
}

/**
 * The web-app manifest, for one film or for the hub itself.
 *
 * `scope` is the host, never the film: the point is that nothing on the
 * portal is "outside" once it is on the home screen. `display` is
 * `standalone` — no browser bars — and the colours are the portal's night.
 */
function manifestOf(title, base, q) {
  return {
    name: title,
    short_name: title,
    id: base || "/",
    start_url: `${base || "/"}${q}`,
    scope: "/",
    display: "standalone",
    background_color: "#16161A",
    theme_color: "#16161A",
    icons: [{ src: base ? `${base}/icon.png${q}` : "/hub-icon.png", sizes: "512x512", type: "image/png" }],
  };
}

/**
 * Everything a preview needs, for one film.
 *
 * **The key travels with it.** An unfurling robot arrives with no cookie, so a
 * cover whose address does not carry the link's own key is a picture it cannot
 * fetch — and the card falls back to a bare address, which is the thing this
 * exists to fix. Carrying it is not a leak: it is the same key the person was
 * already sent.
 */
function sharedAs(url, base, title, front, slug = "") {
  const k = url.searchParams.get("k");
  const q = k ? `?k=${encodeURIComponent(k)}` : "";
  // **A page's link unfurls into the page's card.** His ask, 2026-09-10: one
  // picture for every link to a film said nothing about which page it was.
  // The page's name goes on the picture as well as in the title, and the
  // address stays the page's own rather than the film's.
  const at = slug ? `${base}/${slug}` : base;
  const pic = slug ? `${base}/cover.png?page=${encodeURIComponent(slug)}${k ? `&k=${encodeURIComponent(k)}` : ""}`
                   : `${base}/cover.png${q}`;
  return {
    icon: `${base}/icon.svg${q}`,
    film: { base, q, title },
    og: {
      title,
      said: String(front.logline || "").slice(0, 200),
      url: `${url.origin}${at}${q}`,
      image: `${url.origin}${pic}`,
    },
  };
}

/** A page, in the app's own chrome. `hub.css` is the app's palette, verbatim. */
function html(body, title, status = 200, opts = {}) {
  // **`viewport-fit=cover`, so `env(safe-area-inset-*)` says something.** Every
  // rule in `front.css` that keeps the phone's bar off the home indicator
  // read as zero without it, and in the home-screen app — which has no
  // browser toolbar to stand in the way — the bar sat on the indicator.
  // His report, 2026-09-20.
  // **The ground is painted before the stylesheet arrives.** A dark page
  // stands white until `hub.css` lands, and on the home screen there is no
  // progress bar to say a page is coming — seen in the Simulator, 2026-09-20,
  // as ten white seconds between two black pages. One inline rule, the same
  // colour the theme-color already names, and the wait is dark instead.
  // **The front of house has its own stylesheet.** `hub.css` dresses the tool
  // and reads its palette from `Theme.swift`; `front.css` dresses the record.
  // They are not the same room, and keeping them apart also means one can be
  // worked on while somebody else is in the other.
  //
  // **`paint` takes the colours without the behaviour.** The deck editor needs
  // `front.css` because a deck design reads the front of house's tokens —
  // `--ink`, `--loud`, `--quiet` — and the live page has them while the editor
  // did not, so the identical design drew pale grey type on the site and
  // near-black type in the editor. What it must not take is the three front
  // scripts: `look.js` binds a click on every picture, and in the editor a
  // click on a picture means *pick this one*.
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)} · ${opts.film ? "Shotlister" : "Project Studio"}</title>
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black">
${headMarks(opts)}
<script src="/feel.js?v=${BUILD}" defer></script>
<script src="/seen.js?v=${BUILD}" defer></script>
<script src="/wait.js?v=${BUILD}" defer></script>
<link rel="stylesheet" href="/kit.css?v=${BUILD}">
<link rel="stylesheet" href="/hub.css?v=${BUILD}">${opts.front || opts.paint ? `\n<meta name="theme-color" content="#16161A">\n<style>html{background:#16161A}</style>\n<link rel="stylesheet" href="/front.css?v=${BUILD}">` : opts.dark ? `\n<meta name="theme-color" content="#0E0E11">\n<style>html{background:#0E0E11}</style>` : ""}
<link rel="stylesheet" href="/feel.css?v=${BUILD}">
<link rel="stylesheet" href="/side.css?v=${BUILD}"></head><body${opts.dark ? ` class="fh2 gate"` : ""}>${body}<script src="/copy.js?v=${BUILD}" type="module"></script>${opts.front ? `<script src="/icons.js?v=${BUILD}"></script><script src="/rail.js?v=${BUILD}" type="module"></script><script src="/deep.js?v=${BUILD}" type="module"></script><script src="/look.js?v=${BUILD}" type="module"></script><script src="/arrange.js?v=${BUILD}" type="module"></script><script src="/side.js?v=${BUILD}" type="module"></script><script src="/jump.js?v=${BUILD}" type="module"></script><script src="/dock.js?v=${BUILD}" type="module"></script><script src="/reader.js?v=${BUILD}" type="module"></script><script src="/marks.js?v=${BUILD}" type="module"></script><script src="/ctx.js?v=${BUILD}" type="module"></script><script src="/lib.js?v=${BUILD}" type="module"></script>` : ""}${opts.add || opts.front ? `<script src="/add.js?v=${BUILD}" type="module"></script>` : ""}${opts.shelf ? `<script src="/shelf.js?v=${BUILD}" type="module"></script>` : ""}${opts.made || opts.front ? `<script src="/made.js?v=${BUILD}" type="module"></script><script src="/compare.js?v=${BUILD}" type="module"></script><script src="/board.js?v=${BUILD}" type="module"></script>` : ""}</body></html>`,
    { status, headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } }
  );
}

/**
 * A page that is only words — a refusal, a missing thing, the password gate.
 *
 * **Dark, whatever the system prefers.** The portal is dark by ruling and
 * every page a person reaches is; these were the one kind that followed the
 * system, so a wrong link answered in white on a site that is otherwise
 * black. `dark` puts the app's night palette on `<body>` (`.fh2` in
 * `hub.css`), which is the same block the program inside the portal wears.
 */
function page(status, title, said) {
  return html(`<div class="signin"><div class="wordmark">${esc(title)}</div>${said ? `<p class="empty">${esc(said)}</p>` : ""}</div>`, title, status, { dark: true });
}
