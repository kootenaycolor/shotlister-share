/**
 * A film, in somebody else's browser.
 *
 * The engine is compiled to WebAssembly and runs here: the change logs are
 * fetched, replayed, and asked to describe the film — the same description the
 * Mac app's own screens are drawn from (`engine::view`). **Nothing about the
 * film is worked out in JavaScript.** This file positions and paints.
 *
 * ## It is the app's screens, not a website about them
 *
 * His ruling, 2026-09-01. So: the four modes across the top, the scene sidebar
 * down the left, the side panel on the right that *pushes the table aside*
 * rather than floating over it, and the script inside that panel locked to the
 * scene you are on — because the question a shot list asks of a script is
 * always *what happens in this scene*. Where a Swift file already decides
 * something, it decides it here too.
 *
 * ## Always live, and what that costs today
 *
 * No snapshots: a link points at the film rather than a copy of it. So this
 * re-reads by **asking**, every twenty seconds, whether the change logs have
 * moved. The relay has a push channel the Mac and the phone use, but a browser
 * cannot sign a websocket handshake — the trap written down against Ref 403.
 * Asking is the honest version until that is solved, and nothing on this page
 * changes when it is.
 */

const HUB = window.HUB;
const root = document.getElementById("film");
/**
 * **A view link** (`src/views.js`): the Shot List of one filter, handed over
 * by the server already cut down. No change logs and no engine here — the
 * shots come from `api/view`, and so does every re-sort, search and switch to
 * shooting order. Also set when he opens one of his own views to look at it.
 */
const LENS = HUB.lens || null;
// The same narrowing the server cuts a view link with — one function, so the
// filter on his screen and the link he makes from it cannot disagree.
const { keeps } = await import(new URL(`./narrow.js${new URL(import.meta.url).search}`, import.meta.url).href);

let wasm = null;
let memory = null;
let model = null;

// **Which mode the address asked for.** A tile on the film's page points at
// `/f/<id>/locations`, so the first paint is already the mode somebody was
// sent to rather than the shot list followed by a jump.
let mode = ["shots", "locations", "boards", "schedule", "diagrams"].includes(HUB.mode) ? HUB.mode : "shots";
let view = "table";
let scene = null;
/** The scene picked on the schedule, lit until another is. */
let strip_ = null;
let panel = null;
/**
 * The scene being *read*, as opposed to the scene picked.
 *
 * His instruction, 2026-09-01: the script should follow the page down rather
 * than wait to be told. Picking a scene in the sidebar still narrows the whole
 * table to it — that is the app's behaviour and it is not this. This is the
 * scene whose band has most recently passed the top of the well, and it only
 * matters when nothing is picked.
 */
let inView = null;
/** The observer watching for the scene at the top. Disconnected on every redraw. */
let bandWatch = null;
let seen = "";
let live = false;
let missing = 0;
// **Read from the copy in this browser, with no server behind it.** Not the
// same as `live` being false, which is a page that expects to reconnect.
let offline = false;
let openShot = null;   // the placement whose media is popped out
let openRoom = null;   // the scanned room whose measurements are popped out
let openIndex = 0;
let place = null;        // the location being looked at
/* The Diagrams page: which scene's plan, which camera is tapped, which beat. */
let plan = null;
let planCam = null;
/** A shot to look at on its scene's plan, once the Diagram draws it (the pop-out's Diagram). */
let planShot = null;
let planBeat = 1;
let board = null;        // the board being looked at
let listFind = "";       // filtering the locations or boards list, by name
/**
 * Which scenes are showing the whole of their synopsis, by scene id.
 *
 * **One line at rest, the whole of it when you press it** — which is not a
 * shape invented here. It is `SynopsisField` in `studio/Sources/Controls.swift`,
 * and its comment says whose idea it was: *"Grows when you click it rather than
 * opening anything: one line at rest, the whole of it while you are in it — his
 * call."* The portal drew every synopsis open, which on a phone was six lines of
 * paragraph at the head of every scene.
 *
 * The Mac's page also offers *Edit on the scene page* when it is open. Nothing
 * here does, because nobody reading this can edit anything.
 */
const openSynopsis = new Set();
/**
 * **A phone, and the shape the app takes on one.**
 *
 * The iPhone app is Shotlister on a small screen and it is not the Mac's
 * window shrunk: the four modes are a tab bar along the bottom, a list is a
 * screen you open rather than a column beside the work, and a shot is a row
 * with its frame at the left rather than a line across eleven columns. This
 * flag is the whole of how that is decided, and it is **watched** rather than
 * read once: a window dragged narrow, or a phone turned in a hand, changes the
 * answer and the page is redrawn to match.
 *
 * 700px because the sidebar is 258 and the panel 300: below that the three
 * cannot stand side by side without the middle one being a gutter.
 *
 * **And a phone on its side is still a phone.** Turned landscape an iPhone is
 * 852 across — wider than anything here cares about — and 393 tall, so a test
 * on width alone put the Mac's chrome, its 258px list and its eleven columns
 * on a screen four hundred points high. A short window *that is being touched*
 * is the honest test; `pointer: coarse` keeps a short desktop window out of it.
 *
 * It must match the media query in `hub.css`, which decides the same thing in
 * style. Change one and change the other.
 */
const PHONE = window.matchMedia(
  "(max-width: 700px), (max-height: 480px) and (pointer: coarse)"
);
let narrow = PHONE.matches;

/**
 * Whether the list down the side is showing.
 *
 * **Open on a Mac, shut on a phone.** On a wide window it is a column beside
 * the work and costs nothing; on a phone it covers the work, and somebody sent
 * a link should land on the film rather than on its index.
 */
let sidebar = !narrow;
/**
 * How many clips may be alive at once.
 *
 * Small on purpose. A page holding twenty-two video elements asks a browser for
 * twenty-two decoders and it will not give them: one clip plays and the rest sit
 * still, which is what he reported. Three is plenty for a list.
 */
const LIVE_CLIPS = 3;
/**
 * What a clip's poster ends in. **`relay/layout.json` says `jpg`, and
 * `hub/checks.sh` checks this agrees** — a page cannot import that file, so it
 * repeats the word and is measured against it. The worker answers a `.jpg`
 * address with an older film's PNG when that is what it holds.
 */
const POSTER = "jpg";

const COLUMN_MIN = 56;
const COLUMN_MAX = 640;
const WIDTHS_KEY = `shotlister.widths.${HUB.project}`;
const FRAME_WIDTH_KEY = `shotlister.framew.${HUB.project}`;
/**
 * **How big the table's type is** — the Mac's four steps, `Brand.comfortable`
 * in `studio/Sources/Theme.swift`, kept as the same numbers so the slider here
 * and ⌘+ there walk the same sizes. One setting for every film, in this
 * browser only: it is how one person likes to read, not a fact about a film.
 */
const TEXT_SIZES = [0.85, 1, 1.18, 1.4];
const TEXT_SIZE_KEY = "shotlister.textsize";
let textSize = 1;
try { textSize = Number(localStorage.getItem(TEXT_SIZE_KEY)) || 1; } catch {}
if (!TEXT_SIZES.includes(textSize)) textSize = 1;
/**
 * What is being asked for — the browser's half of `engine::view::Asked`.
 *
 * **Handed to the engine, never applied here.** Filtering in the page would be
 * quicker to write and would mean a search in a browser and a search on the Mac
 * quietly came to mean different things.
 */
// **No `hideStruck`.** His call, 2026-09-01: hiding cut shots is a thing for
// a phone on a set, not for somebody being shown a film. Absent from what is
// asked, the engine's own default shows everything — and a cut shot is still
// drawn struck through, which is the honest way to say it was cut rather than
// pretending it never existed.
let asking = { search: "", sortColumn: "", sortDescending: false, facets: [], groupBy: "scene" };
/**
 * **Shooting order, remembered per film in this browser.** `groupBy: "day"`
 * asks the engine for the Mac's own day groups — each day's shots in the
 * order the Schedule arranged them — and the Shot List draws a day's band
 * over the runs of scenes inside it. His ask, 2026-09-20 (Ref 1136): *"The
 * web portal should be able to show the shot list in shooting order."*
 */
const GROUP_KEY = `shotlister:groupby:${HUB.project || ""}`;
/** **The Schedule's Shooting Order**, remembered per film in this browser —
 *  each day as its shots in the order they are shot, as the Mac's switch. */
const RUN_KEY = `shotlister:shootorder:${HUB.project || ""}`;
let shootOrder = false;
try { shootOrder = localStorage.getItem(RUN_KEY) === "1"; } catch {}
try { if (localStorage.getItem(GROUP_KEY) === "day") asking.groupBy = "day"; } catch {}
if (LENS) asking.groupBy = LENS.groupBy === "day" ? "day" : "scene";
function byDay() { return asking.groupBy === "day"; }
/** What the Shot List is filtered to, for the Share panel's Share View. */
window.shotlisterFilter = () => (mode === "shots" && !LENS ? { facets: asking.facets.slice(), groupBy: asking.groupBy } : null);

/*
 * **The shoot this page is on** — SL-1396. A film that shoots more than
 * once carries its shoots on `HUB.shoot`; the Shot List and the Schedule
 * narrow to the one the address names, and "All Shoots" lifts it. A scene
 * belongs to a shoot through its section (the Shoots row's Shot List
 * Section), or else through its day's date; one no shoot claims is on every
 * tab, his rule for anything with an empty Shoot. Functions, not consts, so
 * `paint` can ask before the rest of the file has run.
 */
let allShoots = false;
function shootOn() {
  const shoot = HUB.shoot;
  if (!shoot || allShoots) return null;
  return (shoot.tabs || []).find((one) => one.slug === shoot.on) || null;
}
function looseName(words) {
  return String(words || "").toLowerCase().replace(/[—–-]/g, " ").replace(/\s+/g, " ").trim();
}
function onShootDay(one, date) {
  return Boolean(date && one.start && date >= one.start && date <= (one.end || one.start));
}
/* **Shoot fields** (stage 5 step 4 piece D): once the film's scenes or days
   name their shoot (`shootSaid`), that is the rule, Studio's own
   (`Doc::scene_shoot`), and each scene is exactly one shoot's. A film with
   none keeps the section/date rule below. `byFields`, `dayShootOf` and
   `sceneShootOf` in `src/front.js` are the server's same three. */
function byFields() {
  const tabs = (HUB.shoot && HUB.shoot.tabs) || [];
  const ids = new Set(tabs.map((one) => one.id).filter(Boolean));
  if (tabs.length < 2 || !ids.size) return false;
  const named = (list) => (list || []).some((one) => one && ids.has(one.shootSaid));
  return named(model && model.scenes) || named(model && model.days);
}
function dayShootOf(day) {
  const tabs = HUB.shoot.tabs;
  const own = day && day.shootSaid && tabs.find((one) => one.id === day.shootSaid);
  if (own) return own.slug;
  const date = day && day.date;
  const covering = date && tabs.find((one) => onShootDay(one, date));
  if (covering) return covering.slug;
  const before = date ? tabs.filter((one) => one.start && one.start <= date).sort((a, b) => (a.start < b.start ? -1 : 1)).pop() : null;
  return (before || tabs[0]).slug;
}
function sceneShootOf(scene) {
  const tabs = HUB.shoot.tabs;
  const own = scene && scene.shootSaid && tabs.find((one) => one.id === scene.shootSaid);
  if (own) return own.slug;
  const day = scene && scene.day && ((model && model.days) || []).find((d) => d.label === scene.day);
  return day ? dayShootOf(day) : tabs[0].slug;
}
function shootsOfScene(sceneId) {
  const tabs = (HUB.shoot && HUB.shoot.tabs) || [];
  const scene = ((model && model.scenes) || []).find((x) => x.id === sceneId) || {};
  if (byFields()) return [sceneShootOf(scene)];
  const section = scene.sequence && ((model && model.sequences) || []).find((q) => q.id === scene.sequence);
  if (section) {
    const named = looseName(section.title);
    const claimed = tabs.filter((one) => (one.sections || []).some((n) => looseName(n) === named));
    if (claimed.length) return claimed.map((one) => one.slug);
  }
  const day = scene.day && ((model && model.days) || []).find((d) => d.label === scene.day);
  const claimed = day ? tabs.filter((one) => onShootDay(one, day.date)) : [];
  return claimed.length ? claimed.map((one) => one.slug) : null;
}
function inShoot(sceneId) {
  const on = shootOn();
  if (!on) return true;
  const of = shootsOfScene(sceneId);
  return !of || of.includes(on.slug);
}
/* **A wrapped shoot's tab is its record** — his Shoot 1 scenes are archived
   once shot, and an archived scene is set aside everywhere else. On the tab
   of a wrapped shoot that names it, it is drawn. */
function setAside(scene) {
  if (!scene || !scene.archived) return false;
  const on = shootOn();
  if (!on || on.status !== "Wrapped") return true;
  const of = shootsOfScene(scene.id);
  return !(of && of.includes(on.slug));
}
function dayInShoot(day) {
  const on = shootOn();
  if (!on || !day) return true;
  if (byFields()) return dayShootOf(day) === on.slug;
  return onShootDay(on, day.date) || !(HUB.shoot.tabs || []).some((one) => onShootDay(one, day.date));
}
/* `Shoot 2 | All Shoots`, at the head of the Shot List and the Schedule. */
function shootSeg() {
  const shoot = HUB.shoot;
  const on = shoot && (shoot.tabs || []).find((one) => one.slug === shoot.on);
  // **The one shoot picker has All Shoots in it** (stage 5 step 5): no second toggle.
  if (!on || shoot.picker) return "";
  return `<div class="seg shootseg"><button data-allshoots="0" class="${allShoots ? "" : "on"}">${esc(on.name)}</button><button data-allshoots="1" class="${allShoots ? "on" : ""}">All Shoots</button></div>`;
}
/* The switcher at the top of the rail — `shootTabs` in `src/pages.js`, the
   same line drawn the same way, so the two rails are one rail: the shoot
   you are on, ‹ › to the one before and after, and the line opening a list
   of every shoot (Ref 1413, built for many). `shootMenuOpen` keeps the list
   open across a redraw, which a log arriving would otherwise shut. */
let shootMenuOpen = false;
function shootTabsHere() {
  const shoot = HUB.shoot;
  const tabs = (shoot && shoot.tabs) || [];
  if (tabs.length < 2) return "";
  if (shoot.picker) return shootPickerHere();
  // Not `MODE_AT`: a `const` further down is not there yet when `paint` first runs.
  const at = { shots: "shotlist", diagrams: "diagrams", locations: "locations", boards: "boards", schedule: "schedule" }[mode] || "shotlist";
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const said = (ymd) => { const [, m, d] = String(ymd).split("-").map(Number); return `${months[m - 1]} ${d}`; };
  const when = (one) => {
    if (!one.start) return "";
    if (!one.end || one.end === one.start) return said(one.start);
    const [a, b] = [said(one.start), said(one.end)];
    return a.split(" ")[0] === b.split(" ")[0] ? `${a}–${b.split(" ")[1]}` : `${a} – ${b}`;
  };
  const svg = (d) => `<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const BACK = '<path d="M9.8 3.8 5.6 8l4.2 4.2"/>';
  const ON = '<path d="M6.2 3.8 10.4 8l-4.2 4.2"/>';
  const href = (one) => `${shoot.base}/shoots/${one.slug}/${at}`;
  const here = tabs.findIndex((one) => one.slug === shoot.on);
  const now = tabs[here];
  const step = (one, back) => one
    ? `<a class="shootstep" href="${esc(href(one))}" title="${esc(one.name)}" aria-label="${esc(one.name)}">${svg(back ? BACK : ON)}</a>`
    : `<span class="shootstep shootend" aria-hidden="true">${svg(back ? BACK : ON)}</span>`;
  const row = (one) => `<a class="shootrow${one === now ? " on" : ""}"${one === now ? ' aria-current="true"' : ""} href="${esc(href(one))}"><b>${esc(one.name)}</b><span>${esc(when(one))}</span><i>${esc(one.status)}</i></a>`;
  return `<div class="shootpick">
    ${step(tabs[here - 1], true)}
    <details class="shootmenu"${shootMenuOpen ? " open" : ""}><summary aria-label="Shoots"><b>${esc(now.name)}</b><span>${esc([when(now), now.status].filter(Boolean).join(" · "))}</span>${svg('<path d="M4.2 6.2 8 10l3.8-3.8"/>').replace('width="14" height="14"', 'width="13" height="13"')}</summary>
      <div class="shootlist">${tabs.map(row).join("")}</div></details>
    ${step(tabs[here + 1], false)}
  </div>`;
}

/* **The one shoot picker** (stage 5 step 5) — `shootPicker` in
   `src/pages.js`, drawn the same: All Shoots first, then each shoot with its
   dates and a Wrapped / Next / Upcoming tag; ‹ › step through that order.
   Each shoot keeps its own address; All Shoots is `/shoots/all-shoots`. */
function shootPickerHere() {
  const shoot = HUB.shoot;
  const tabs = shoot.tabs || [];
  const at = { shots: "shotlist", diagrams: "diagrams", locations: "locations", boards: "boards", schedule: "schedule" }[mode] || "shotlist";
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const said = (ymd) => { const [, m, d] = String(ymd).split("-").map(Number); return `${months[m - 1]} ${d}`; };
  const when = (one) => {
    if (!one.start) return "";
    if (!one.end || one.end === one.start) return said(one.start);
    const [a, b] = [said(one.start), said(one.end)];
    return a.split(" ")[0] === b.split(" ")[0] ? `${a}–${b.split(" ")[1]}` : `${a} – ${b}`;
  };
  const svg = (d, n = 14) => `<svg viewBox="0 0 16 16" width="${n}" height="${n}" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const BACK = '<path d="M9.8 3.8 5.6 8l4.2 4.2"/>';
  const ON = '<path d="M6.2 3.8 10.4 8l-4.2 4.2"/>';
  const ALL = { slug: "all-shoots", name: "All Shoots", all: true };
  const order = [ALL, ...tabs];
  const here = Math.max(0, order.findIndex((one) => one.slug === shoot.on));
  const now = order[here];
  const named = (one) => (one.base && one.base !== one.name ? one.base : "");
  const sub = (one) => (one.all ? `${tabs.length} shoots` : [named(one), when(one)].filter(Boolean).join(" · "));
  const tag = (one) => (one.status ? `<i class="tag${one.status === "Next" ? " next" : ""}">${esc(one.status)}</i>` : "");
  const href = (one) => `${shoot.base}/shoots/${one.slug}/${at}`;
  const step = (one, back) => one
    ? `<a class="shootstep" href="${esc(href(one))}" title="${esc(one.name)}" aria-label="${back ? "Previous shoot" : "Next shoot"}">${svg(back ? BACK : ON)}</a>`
    : `<span class="shootstep shootend" aria-hidden="true">${svg(back ? BACK : ON)}</span>`;
  const row = (one) => `<a class="shootrow${one === now ? " on" : ""}"${one === now ? ' aria-current="true"' : ""} href="${esc(href(one))}"><b>${esc(one.name)}</b><span>${esc(sub(one))}</span>${tag(one)}</a>`;
  return `<div class="shootpick pick5">
    ${step(order[here - 1], true)}
    <details class="shootmenu"${shootMenuOpen ? " open" : ""}><summary aria-label="Shoots"><b>${esc(now.name)}</b><span>${esc(sub(now))}</span>${tag(now)}${svg('<path d="M4.2 6.2 8 10l3.8-3.8"/>', 13)}</summary>
      <div class="shootlist">${order.map(row).join("")}</div></details>
    ${step(order[here + 1], false)}
  </div>`;
}

applyWidths();
boot();

// Turning the phone on its side, or dragging a desktop window narrow, changes
// which shape is right — so it is answered when it changes rather than at boot.
PHONE.addEventListener("change", (event) => {
  narrow = event.matches;
  sidebar = !narrow;
  // A panel that covered the whole screen has nothing to be beside any more.
  if (narrow) panel = null;
  draw();
});

// Arrow keys walk a shot's frames and escape shuts the pop-out — the same keys
// the app answers to. Bound once rather than on every redraw.
document.addEventListener("keydown", (event) => {
  if (openRoom) {
    if (event.key !== "Escape") return;
    openRoom = null;
    draw();
    event.preventDefault();
    return;
  }
  if (!openShot) return;
  const row = rowOf(openShot);
  const count = row && row.stills ? row.stills.length : 0;
  if (event.key === "Escape") { openShot = null; draw(); }
  else if (event.key === "ArrowRight" && count) { openIndex = (openIndex + 1) % count; draw(); }
  else if (event.key === "ArrowLeft" && count) { openIndex = (openIndex - 1 + count) % count; draw(); }
  else if (event.key === " " && root.querySelector(".plate video")) toggleClip(root.querySelector(".plate video"));
  else return;
  event.preventDefault();
});

/**
 * **Keep the page itself, so a film opens where there is no signal.**
 *
 * `sw.js` says what it does and why it is network-first. Registered from here
 * rather than from the page's head because it belongs to the program, and
 * because `?nosw=1` on any address takes it straight back off again — a worker
 * that cannot be removed without a developer is not one to put on his portal.
 */
function keepTheShell() {
  if (!("serviceWorker" in navigator)) return;
  if (new URLSearchParams(location.search).has("nosw")) {
    navigator.serviceWorker.getRegistrations()
      .then((all) => all.forEach((one) => one.unregister()))
      .catch(() => {});
    return;
  }
  navigator.serviceWorker.register("/sw.js").catch(() => {
    /* a browser that refuses is a browser that behaves as it did before */
  });
}

async function boot() {
  // **The outline is already on screen** — `ghost()` in `src/worker.js` writes
  // it into the page itself, so it is drawn before this script exists. Nothing
  // to paint here; the first paint is the film.
  keepTheShell();
  if (LENS) {
    try {
      await readLens();
      draw();
      setInterval(checkLens, 20000);
    } catch (error) {
      paint(waiting("That view would not open. " + error));
    }
    return;
  }
  try {
    const source = await WebAssembly.instantiateStreaming(fetch("/shotlister_web.wasm"), {});
    wasm = source.instance.exports;
    memory = wasm.memory;
    // The engine has no clock and no randomness of its own in a browser — see
    // `engine/src/id.rs`. Both are the host's to give, and it panics without them.
    wasm.set_now(Date.now());
    wasm.set_seed(Math.floor(Math.random() * 2 ** 53));
    await Promise.all([read(), loadDiagram()]);
    draw();
    setInterval(check, 20000);
    listen();
  } catch (error) {
    paint(waiting("That film would not open. " + error));
  }
}

/**
 * **The browser's own copy of this film.**
 *
 * A film is its change logs, and opening one used to fetch every single one:
 * measured on his real *Call Her Back*, 166 requests, 120 of them logs. On a
 * local server that is a tenth of a second; on a phone on a location every one
 * of the hundred and twenty is a round trip, and it is the whole of the wait.
 *
 * **A log is worth keeping because a log barely changes.** The relay's one
 * rule is that a log may only ever grow, so the only one that can differ from
 * the copy here is the one the writing device is still appending to — and the
 * server says every log's size before a single byte is fetched. So the size
 * goes in the key: a log that has grown is simply a different key, which makes
 * a stale copy impossible rather than unlikely.
 *
 * One cache per film, so two films never share a name, and a browser that will
 * not give us one (a private window, an old browser) gets exactly what it got
 * before this existed.
 */
async function filmCache() {
  if (typeof caches === "undefined") return null;
  try {
    return await caches.open(`film-${HUB.project}`);
  } catch {
    return null;
  }
}

/** Where one log is kept. The size is in the key on purpose — see `filmCache`. */
function logKey(name, size) {
  return `/kept/log/${encodeURIComponent(name)}/${size}`;
}

/**
 * Throw away what this film is no longer made of.
 *
 * Logs are retired — `storage`'s fold gathers old ones up (Ref 192) — and a
 * grown log leaves its shorter self behind under the old key. Neither is ever
 * asked for again, and a cache nobody prunes is a cache that grows for ever.
 */
async function pruneCache(kept, wanted) {
  try {
    for (const request of await kept.keys()) {
      const path = new URL(request.url).pathname;
      if (path.startsWith("/kept/log/") && !wanted.has(path)) await kept.delete(request);
    }
  } catch {
    /* a cache that will not be tidied is not a film that will not open */
  }
}

async function read() {
  const kept = await filmCache();

  // **What the film is made of, and the one thing worth asking the server for
  // every time.** It is a single small request; everything after it can come
  // from here. When it cannot be had at all — no signal on a location, which
  // is exactly where he is standing — the last answer stands in for it, and
  // the film opens anyway.
  let state = null;
  try {
    state = await api("state");
    offline = false;
    if (kept) await kept.put("/kept/state", new Response(JSON.stringify(state)));
  } catch (trouble) {
    const held = kept ? await kept.match("/kept/state") : null;
    if (!held) throw trouble;
    state = await held.json();
    offline = true;
  }

  const names = state.logs.map((l) => l.name).sort();
  const sizes = new Map(state.logs.map((l) => [l.name, l.size]));
  seen = state.logs.map((l) => `${l.name}:${l.size}`).sort().join("|");

  // Fetched together rather than one after another: a hundred and eighteen
  // round trips in series is most of the time this page takes.
  //
  // **One log that will not come is not a film that will not open.** The first
  // run against his real film died whole because a single name came back 400.
  // A missing log means some changes are missing, which is worth saying — it is
  // not worth refusing to draw the other ten thousand.
  const texts = await Promise.all(names.map((n) => oneLog(kept, n, sizes.get(n))));
  missing = texts.filter((t) => t === null).length;
  if (kept) await pruneCache(kept, new Set(names.map((n) => logKey(n, sizes.get(n)))));
  // **Emptied only once everything is in hand**: the engine is never empty
  // across an await, so a Diagram edit made while the film is being read
  // lands on the film, not on nothing.
  wasm.reset();
  for (const text of texts) {
    if (text === null) continue;
    const [pointer, length] = put(text);
    wasm.add_log(pointer, length);
    wasm.dealloc(pointer, length);
  }
  wasm.settle();
  model = JSON.parse(describe());
  live = !offline;
  if (scene && !model.scenes.some((s) => s.id === scene)) scene = null;
}

/**
 * One log — from here if we already have it, from the server if not.
 *
 * Null means it could not be had at either end, which is what `missing` counts
 * and what the bar says out loud. **Being unable to keep a copy is not being
 * unable to read one**: every cache call is allowed to fail on its own, and the
 * fetch behind it still stands.
 */
async function oneLog(kept, name, size) {
  const key = logKey(name, size);
  if (kept) {
    try {
      const held = await kept.match(key);
      if (held) return await held.text();
    } catch {
      /* fall through to the server */
    }
  }
  try {
    const got = await fetch(`/f/${HUB.project}/api/log/${name}`, { headers: { accept: "*/*" } });
    if (!got.ok) return null;
    if (kept) {
      try {
        await kept.put(key, got.clone());
      } catch {
        /* out of room, or a browser that refuses — read it anyway */
      }
    }
    return await got.text();
  } catch {
    return null;
  }
}

/** Ask the engine to describe the film the way it is currently being looked at. */
function describe(asked = asking) {
  const [pointer, length] = put(JSON.stringify(asked));
  const out = take(wasm.view(HUB.role === "editor" ? 0 : 1, pointer, length));
  wasm.dealloc(pointer, length);
  return out;
}

/**
 * Look again without reading the film again.
 *
 * A search changes what is *shown*, not what is *known*, so the change logs are
 * not fetched a second time — the engine is simply asked the question again.
 */
function relook() {
  if (LENS) {
    // A search is asked of the server as he types, so wait for him to pause.
    clearTimeout(lensWait);
    lensWait = setTimeout(() => readLens().then(draw).catch(() => { live = false; draw(); }), asking.search ? 250 : 0);
    return;
  }
  if (!wasm) return;
  model = JSON.parse(describe());
  draw();
}

// ------------------------------------------------------------ a view link

let lensWait = 0;
let lensStamp = "";

/** The view's shots, as the server cuts them, asked the way he is looking. */
async function readLens() {
  const q = new URLSearchParams({ groupBy: asking.groupBy });
  if (asking.sortColumn) q.set("sort", asking.sortColumn);
  if (asking.sortDescending) q.set("desc", "1");
  if (asking.search) q.set("q", asking.search);
  if (!HUB.linkKey) q.set("code", LENS.code);
  const got = await fetch(`/f/${HUB.project}/api/view?${q}`, { headers: { accept: "application/json" } });
  if (!got.ok) throw new Error(String(got.status));
  model = await got.json();
  lensStamp = model.stamp || "";
  live = true;
  offline = false;
  if (scene && !model.scenes.some((x) => x.id === scene)) scene = null;
}

/** Every twenty seconds: has the film changed? Drawn again only if so. */
async function checkLens() {
  const was = lensStamp;
  try {
    const keep = model;
    await readLens();
    if (lensStamp === was) { model = keep; return; }
    draw();
  } catch {
    live = false;
    draw();
  }
}

/** The view's own filter, drawn as chips that cannot be taken off. */
function lensChips() {
  return `<div class="fchips lens"><span class="lensname">${esc(LENS.name)}</span>${
    (LENS.facets || []).map(([, v]) => `<span class="fchip fixed">${esc(v)}</span>`).join("")}</div>`;
}

/**
 * **The film's live line** — the relay's room, the one his Mac and phone
 * listen on (`api/live`). It carries one word when anybody keeps a change,
 * and the page looks at once rather than on its next twenty-second look. A
 * line that will not open (no relay here, a proxy that eats websockets) is
 * simply the old way: the look every twenty seconds.
 */
function listen(wait = 1000) {
  if (!("WebSocket" in window)) return;
  let line;
  try {
    line = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/f/${HUB.project}/api/live`);
  } catch {
    return;
  }
  let opened = false;
  let beat = 0;
  line.addEventListener("open", () => {
    opened = true;
    beat = setInterval(() => { try { line.send("ping"); } catch { /* closing */ } }, 30000);
  });
  line.addEventListener("message", (event) => {
    let said = null;
    try { said = JSON.parse(event.data); } catch { return; }
    if (said && said.changed) check();
  });
  line.addEventListener("close", () => {
    clearInterval(beat);
    // Back again, slower each time it fails; a line that never opened once
    // is not worth knocking on for ever.
    if (!opened && wait > 60000) return;
    setTimeout(() => listen(opened ? 1000 : wait * 2), opened ? 1000 : wait);
  });
}

async function check() {
  const wasLive = live;
  // **Never read the film under an edit in flight.** The Diagram makes its
  // edits on this page's copy first; reading now would throw them away
  // before the server has kept them. It asks for the read itself once they
  // are kept.
  if (diagram && diagram.busy()) return;
  try {
    const state = await api("state");
    const now = state.logs.map((l) => `${l.name}:${l.size}`).sort().join("|");
    live = true;
    // **Coming back is worth saying as loudly as going away.** A page that
    // opened from the copy in this browser sits there saying Offline until it
    // is told otherwise, and this is the only thing that ever asks.
    offline = false;
    // **The Diagrams page is not repainted for nothing.** Every other page
    // redraws to refresh the Live mark; this one would lose a drag, a pinch
    // or Play halfway through. It is repainted only when the film changed —
    // and then the plan redraws in place, keeping the view.
    //
    // **Nor is any other page, once it already says Live.** Redrawing an
    // unchanged film every twenty seconds threw away every playing clip and
    // started it again from its poster, which is the clip he saw "cut off
    // before the video is done" (2026-10-09). Nothing on screen changes when
    // the film has not, so there is nothing to redraw.
    if (now === seen) return wasLive ? undefined : draw();
    await read();
    draw();
  } catch {
    // A film that cannot be reached is not a film that has changed. Say so in
    // the one place that claims to know, and keep what is on screen.
    live = false;
    draw();
  }
}

// ------------------------------------------------------------------ the shell

/**
 * The two handlers that can sit inside the side panel.
 *
 * Named because the panel is redrawn on its own as the page scrolls, and
 * anything bound to the old node goes with it.
 */
function opensAPicture(b) {
  b.addEventListener("click", () => {
    openShot = b.dataset.open || null;
    // **The panel you clicked is the one that opens.** A strip of four with
    // every panel opening the first would be a list that lies about itself.
    openIndex = Number(b.dataset.at || 0);
    draw();
  });
}

function switchesThePanel(b) {
  b.addEventListener("click", () => {
    const want = b.dataset.panel;
    // The toggle in the top bar is the only way to shut it — the panel has
    // no close button of its own, deliberately, the same as the Mac's.
    panel = want === "toggle" ? (panel ? null : "script") : want;
    travelled(() => draw(), "panes");
  });
}

/**
 * Keep the panel on the scene the page is showing.
 *
 * **Only the panel is redrawn, never the page.** Repainting the film on every
 * scroll event would fight the scroll itself; this replaces one node when the
 * answer actually changes, which on a long film is a few times a minute.
 */
function followTheScroll() {
  if (bandWatch) {
    bandWatch.disconnect();
    bandWatch = null;
  }
  readWell = null;
  const well = root.querySelector(".well");
  if (!well) return;
  const bands = [...well.querySelectorAll("[data-band]")];
  if (!bands.length) return;

  // The last band that has passed the top of the well is the scene being read;
  // before any has, it is the first one. **The scene lists follow it** — the
  // Mac's rule that the chrome follows what is being read, not what the
  // sidebar last said — except while the page is on its way to a picked
  // scene, when the list already says where it is going and would otherwise
  // flick through every scene passed on the way.
  const look = () => {
    const box = scrollerOf(well);
    const edge = box === document.scrollingElement || box === document.documentElement ? 0 : box.getBoundingClientRect().top;
    const top = edge + headroom(well, box);
    let now = bands[0].dataset.band;
    for (const band of bands) {
      if (band.getBoundingClientRect().top - top > 8) break;
      now = band.dataset.band;
    }
    if (now === inView) return;
    inView = now;
    if (!goingTo) markScene(now);
    redrawPanel();
  };
  readWell = look;

  // **Watched, not polled.** An observer fires exactly when a band crosses in
  // or out of the well, which is exactly when the answer can change — and it
  // does not care which ancestor happens to be the thing that scrolls, which a
  // scroll listener does. The measurement is still the rects: an observer says
  // *when* to look, not *what* is on top.
  const box = scrollerOf(well);
  bandWatch = new IntersectionObserver(look, {
    root: box === document.scrollingElement || box === document.documentElement ? null : box,
    threshold: 0,
  });
  for (const band of bands) bandWatch.observe(band);

  // **And the scroll itself, throttled to a frame.** The observer and a scroll
  // listener are two independent paths to the same question; neither costs
  // anything, and a browser that is quiet on one is not necessarily quiet on
  // the other. `look` does nothing at all when its answer has not changed.
  let waiting = false;
  (box === document.scrollingElement || box === document.documentElement ? window : box).addEventListener(
    "scroll",
    () => {
      if (waiting) return;
      waiting = true;
      requestAnimationFrame(() => {
        waiting = false;
        look();
      });
    },
    { passive: true }
  );

  look();
}

/**
 * The box that actually scrolls the well's contents.
 *
 * **On a desk it is the well; on a phone it is the page.** The well has
 * `overflow:auto` everywhere, but on a phone the portal's frame lets the pane
 * grow to its content and the document does the scrolling — so scrolling the
 * well there moves nothing at all. The first ancestor with room to scroll is
 * the one to move, and failing that the document.
 */
function scrollerOf(el) {
  for (let box = el; box && box !== document.body; box = box.parentElement) {
    const overflow = getComputedStyle(box).overflowY;
    if ((overflow === "auto" || overflow === "scroll") && box.scrollHeight > box.clientHeight + 1) return box;
  }
  return document.scrollingElement || document.documentElement;
}

/**
 * How far down the scroller's top edge the content really starts — the
 * table's sticky column headings, and on a phone the portal's fixed top bar —
 * so a scene brought to the top is not brought under them.
 */
function headroom(well, box = well) {
  let room = 0;
  const stuck = well.querySelector(":scope > .thead");
  if (stuck) room += stuck.getBoundingClientRect().height;
  if (box === document.scrollingElement || box === document.documentElement) {
    for (const bar of root.querySelectorAll(".fh-topbar")) {
      const rect = bar.getBoundingClientRect();
      if (getComputedStyle(bar).position === "fixed" && rect.height > 0) room = Math.max(room, rect.bottom);
    }
  }
  return room;
}

/** Where `el` sits within `box`'s scroll range. */
function offsetIn(el, box) {
  const top = el.getBoundingClientRect().top;
  if (box === document.scrollingElement || box === document.documentElement) return top + box.scrollTop;
  return top - box.getBoundingClientRect().top + box.scrollTop;
}

/** Light one scene in the rail's list and the phone's, without a redraw. */
function markScene(id) {
  root.querySelectorAll(".kid[data-scene], .scene-row[data-scene]")
    .forEach((b) => b.classList.toggle("on", Boolean(id) && b.dataset.scene === id));
}

/** Stops the glide to a picked scene, while there is one; null otherwise. */
let goingTo = null;

/** Reads which scene is at the top of the well now — `look` in `followTheScroll`. */
let readWell = null;

/**
 * Carry the page to a scene — **smoothly, the way the Mac's table does**
 * (`withAnimation(.easeInOut(duration: 0.3)) { reader.scrollTo(..., anchor: .top) }`
 * in `Table.swift`), and to the top of the well, under the column headings.
 *
 * **No redraw.** The page is already drawn and the scene is on it; a redraw
 * would put the well back at the top and the animation would start from
 * there. Only the highlight moves, and then the scroll. `how` is `"auto"`
 * when the page has only just been drawn — arriving from the schedule — since
 * a scroll from the top of a long film would be a journey nobody asked for.
 */
function goToScene(id, how = "smooth") {
  const well = root.querySelector(".well");
  const band = well && [...well.querySelectorAll("[data-band]")].find((b) => b.dataset.band === id);
  if (!band) return false;
  if (goingTo) goingTo();
  markScene(id);
  const box = scrollerOf(well);
  const top = Math.max(0, offsetIn(band, box) - headroom(well, box));
  // Landed: the page is read again, as it is after any scroll, and the pick
  // has been honoured.
  goingTo = glide(box, top, how === "smooth" ? 300 : 0, () => {
    goingTo = null;
    scene = null;
    // Read the page where it has landed rather than wait for the next scroll
    // event to say so — which a tab drawn no frames may never send.
    if (readWell) readWell();
    markScene(inView);
  });
  return true;
}

/**
 * Scroll a box to `to` over `ms`, eased in and out — the Mac's
 * `.easeInOut(duration: 0.3)`, drawn by hand.
 *
 * **Not `scrollTo({ behavior: "smooth" })`.** The browser's own glide has no
 * end event, takes however long it likes, and is skipped entirely by a page
 * that is not being drawn — so nothing could say when the scroll had landed,
 * and `look` would light every scene passed on the way. This one knows when
 * it is done, and a tab that gets no frames lands by the clock instead of
 * hanging half way. *Reduce motion* is honoured: the page simply arrives.
 * Returns a function that stops it where it is.
 */
function glide(box, to, ms, then) {
  const from = box.scrollTop;
  const gap = to - from;
  if (!gap || !ms || matchMedia("(prefers-reduced-motion: reduce)").matches) {
    box.scrollTop = to;
    setTimeout(then, 0);
    return () => {};
  }
  const ease = (k) => (k < 0.5 ? 2 * k * k : 1 - ((-2 * k + 2) ** 2) / 2);
  const began = performance.now();
  let frame = 0;
  let over = false;
  const finish = (landed) => {
    if (over) return;
    over = true;
    cancelAnimationFrame(frame);
    clearTimeout(clock);
    if (landed) box.scrollTop = to;
    then();
  };
  const step = (now) => {
    if (over) return;
    const k = Math.min(1, (now - began) / ms);
    box.scrollTop = from + gap * ease(k);
    if (k < 1) frame = requestAnimationFrame(step);
    else finish(true);
  };
  frame = requestAnimationFrame(step);
  const clock = setTimeout(() => finish(true), ms + 250);
  return () => finish(false);
}

function redrawPanel() {
  const side = root.querySelector(".panelside");
  if (!side) return;
  const fresh = document.createElement("div");
  fresh.innerHTML = sidePanel();
  const drawn = fresh.firstElementChild;
  side.replaceWith(drawn);
  drawn.querySelectorAll("[data-panel]").forEach(switchesThePanel);
  drawn.querySelectorAll("[data-open]").forEach(opensAPicture);
  drawMarks();
}

/** Which screen and view the page was last drawn for, so a redraw of the same one keeps its place. */
let drawnAs = "";

function draw() {
  if (!model) return;
  document.body.classList.toggle("edmod", editOn());
  const body =
    mode === "shots" ? shotsMode()
    : mode === "locations" ? locationsMode()
    : mode === "boards" ? boardsMode()
    : mode === "diagrams" ? diagramsMode()
    : scheduleMode();
  // **A redraw of the same page keeps its place.** `paint` replaces the whole
  // document, so every redraw — a log arriving, a synopsis opened, a filter
  // changed — used to put the well back at the top. With a scene now something
  // scrolled to rather than filtered to, that would throw away the scroll the
  // moment anything changed. A different screen or view starts at the top.
  const as = `${mode}/${view}`;
  const was = root.querySelector(".well");
  const keep = was && drawnAs === as ? scrollerOf(was).scrollTop : 0;
  // **The sheet stays what it was.** On a phone the Scenes button raises the
  // rail with only its list in it (`side.js` adds `scopeopen only` to the
  // rail), and `paint` draws a fresh rail without them — so pressing Filter
  // in that sheet threw him onto the whole menu, and picking a filter
  // happened out of sight. His report, 2026-10-06: "I don't think I can
  // really filter stuff right now. It seems to just bounce around."
  const railWas = root.querySelector("nav.rail");
  const sheetWas = railWas
    ? { cls: ["scopeopen", "only"].filter((c) => railWas.classList.contains(c)),
        only: (railWas.querySelector(".railtop") || {}).dataset?.only || "" }
    : null;
  // Every clip on the page is about to be replaced; note where each one was.
  root.querySelectorAll("video.clip, .plate video").forEach(rememberClip);
  paint(`${mode === "shots" ? viewbar() : ""}${body}${viewer()}${roomBox()}`);
  const railNow = root.querySelector("nav.rail");
  if (railNow && sheetWas && sheetWas.cls.length) {
    railNow.classList.add(...sheetWas.cls);
    const top = railNow.querySelector(".railtop");
    if (top && sheetWas.only) top.dataset.only = sheetWas.only;
  }
  wire();
  const well = root.querySelector(".well");
  if (well && keep) scrollerOf(well).scrollTop = keep;
  drawnAs = as;
  // A scene is only "being read" where there is a page to read; anywhere else
  // the panel would keep whichever scene it last saw, which would be a lie.
  if (mode !== "shots") inView = null;
  followTheScroll();
}

const MODES = [
  ["shots", "Shot List"], ["diagrams", "Diagrams"], ["locations", "Locations"],
  ["boards", "Boards"], ["schedule", "Schedule"],
];

/**
 * The bar across the top.
 *
 * **On a phone the modes are not in it** — they are the tab bar along the
 * bottom, where the iPhone app keeps them and where a thumb can reach them.
 * What is left is what a navigation bar carries: where you came from, what you
 * are looking at, and the two or three controls that act on it.
 */
/**
 * **What the film is called — the manifest first, the engine only as a
 * fallback.**
 *
 * These three pages — Shot List, Locations, Schedule — used to read
 * `model.project.title`, and every other page in the portal reads the manifest
 * the server already holds. That is fine right up until a document carries no
 * title of its own, because the engine does not hand back an empty string for
 * that: `engine/src/view.rs:332` hands back the word *Untitled*. So the `||`
 * fallback that was here never fired — it was never given a falsy value to
 * fall back from — and the film appeared to rename itself the moment you
 * pressed Shot List while the browser tab went on saying its real name.
 *
 * Measured 2026-09-07: home, People and Documents said *Call Her Back*; Shot
 * List, Locations and Schedule said *Untitled*.
 *
 * The manifest is the film's name. The engine's title is what the document
 * calls itself, which is a different question and only worth asking when the
 * server has nothing.
 */
function filmTitle() {
  return HUB.title || (model && model.project && model.project.title) || "";
}

/**
 * The film's own mark, drawn in its own colour, as `refresh.py` read it off the
 * Notion row. Nothing when the film has none — a film without an icon gets its
 * name and no gap where a picture should be.
 */
function filmMark() {
  const outline = HUB.mark && HUB.mark.path;
  if (!outline) return "";
  return `<span class="filmicon" aria-hidden="true"><svg viewBox="0 0 20 20" fill="currentColor">` +
    `<path d="${esc(outline)}"></path></svg></span>`;
}

/**
 * The bar across the top.
 *
 * **The film's name is the way back, and there is no back button.** His
 * instruction, 2026-09-02. An arrow beside a name that is itself a link was two
 * controls doing one job, and the name is the one that says where it goes.
 *
 * **It carries `view-transition-name`s that match the film's page**, which is
 * what makes the title and its mark travel from the middle of that page into
 * this corner rather than one disappearing and another appearing. The names are
 * the same two `pages.js` puts on the big title; the browser matches them by
 * name across the swap.
 */
/**
 * Who you are, behind the initial in the corner.
 *
 * **It used to do nothing at all** — his instruction, 2026-09-02: *"nothing
 * happen when you click it — whats the point?"* It is the one thing in this bar
 * that is about *you*, so it holds the address you came in as and what you may
 * do. The role pill that stood beside it has gone inside: a fact about you,
 * drawn as a control, in a bar that is otherwise all controls.
 *
 * A `<details>`, so it opens with no script of its own and closes on its own
 * when the app redraws.
 */
function meCard() {
  const named = HUB.email ? esc(HUB.email) : "Opened with a link";
  // The same line as the record's pages carry — see `meCard` in `pages.js`.
  const may = [HUB.role === "editor" ? "Editor" : "Viewer",
               HUB.admin ? "Administrator" : ""].filter(Boolean).join(" · ");
  return `<details class="me">
    <summary class="fh-avatar" title="You" aria-label="You">${
      // The same as the record's pages — his instruction, 2026-09-08: somebody
      // who has not signed in is drawn as a person, not as a full stop.
      HUB.email ? esc(initials()) : person_mark()
    }</summary>
    <div class="mecard">
      <div class="mewho">${named}</div>
      <div class="memay">${may}</div>
      ${may === "Viewer" ? `<p class="mesaid">You can read this film. You cannot change it.</p>` : ""}
      ${
        /* The same way in as the record's pages have, because it is the same
           button — his report, 2026-09-04: he looked for it behind his own
           initials. It leaves the program, which is why it is a plain link. */
        /* Retired 2026-10-11: what a viewer sees is set in the Library. */
        ""
      }
    </div>
  </details>`;
}


function topbar() {
  return `<div class="topbar">
    <a class="filmid" data-deep="home" href="${esc(HUB.base || `/f/${HUB.project}`)}" title="Home"><span class="home">${mark("home", 13)}Home</span>${filmMark()}<span class="film">${esc(filmTitle())}</span></a>
    <div class="spacer"></div>
    ${
      // **The modes are pinned to the middle of the bar, not floated there.**
      // They used to be centred by the space either side of them, so anything
      // that grew on the left pushed them along — hovering the film's name slid
      // the whole tab bar across with it. His instruction, 2026-09-02: just the
      // title. Being taken out of the row is what stops them being moved by it.
      // **The modes were here and are in the rail now.** Two copies of one
      // list is what the door used to hide; there is one, on every page of the
      // portal, and this bar keeps only what is about *this* screen.
      ""
    }
    ${
      // **A green dot says Live and nothing else on a phone.** The word is
      // three of the forty characters that fit across a bar that narrow, and
      // it says what the dot already says. Anything *wrong* still gets its
      // words, because a dot alone cannot say "three logs missing".
      narrow && live && !missing
        ? `<span class="livedot" title="Live"><i></i></span>`
        : `<span class="livedot${live && !missing ? "" : " off"}"><i></i>${
            offline ? "Offline" : !live ? "Reconnecting" : missing ? `${missing} ${missing === 1 ? "log" : "logs"} missing` : "Live"
          }</span>`
    }
    ${mayShare() ? `<a class="sharebtn${HUB.linkKey ? " open" : ""}" data-share href="/f/${HUB.project}/share" title="Share">${share_mark()}${narrow ? "" : "Share"}</a>` : ""}
    ${meCard()}
  </div>`;
}

/**
 * **Every mark the page draws, in one place, and not one of them a character.**
 *
 * His instruction, 2026-09-02: get rid of all the emoji. There were two real
 * ones — a clapperboard on a location's scene count and an anchor on a scene's
 * place, both of which arrive from the system in full colour and match nothing
 * around them — and a drawer of stray Unicode shapes standing in for icons
 * beside them: `\u25a4`, `\u25a6`, `\u25a3`, `\u2261`, `\u2039`, `\u2715`,
 * arrows. A row carrying a colour emoji, a maths symbol and a stroked SVG at
 * once is most of what reads as unconsidered.
 *
 * So: stroked, 16-unit, `currentColor`, 1.35 — the hand `share.js` already drew
 * in, and the same one the app's own chrome uses. `hub.css` has no idea any of
 * these exist, which is the point: they take the ink of whatever they sit in.
 */

const MARK = {
  // **What is left is what a word cannot say.** Everything else that used to be
  // here drew a picture in front of text that already said it — the four modes,
  // a scene's synopsis, a location, a sequence, a count of scenes, a count of
  // areas — and all of them are gone with the marks themselves. His
  // instruction, 2026-09-03: fewer glyphs, wherever they can go.
  //
  // These four survive because each is the whole control or the whole fact.
  // Which way a column sorts is not a word anybody wants to read.
  // A clip's own two states (2026-10-09).
  play: '<path d="M5 3.4v9.2L12.6 8z" fill="currentColor" stroke="none"/>',
  pause: '<path d="M4.6 3.4h2.4v9.2H4.6zM9 3.4h2.4v9.2H9z" fill="currentColor" stroke="none"/>',
  up: '<path d="M4.4 9.6 8 6l3.6 3.6"/>',
  down: '<path d="M4.4 6.4 8 10l3.6-3.6"/>',
  // **A shafted arrow, not a chevron.** His instruction, 2026-09-02: a
  // different arrow for going home; a bare angle bracket is what a sidebar
  // collapse wears, and this one has somewhere to go.
  home: '<path d="M13 8H3.4"/><path d="M7 4 3.4 8 7 12"/>',
  close: '<path d="m4.6 4.6 6.8 6.8M11.4 4.6l-6.8 6.8"/>',
  // The Diagrams page: a beat before and after, and zoom out and in — each
  // the whole of its button, as the sort arrows are.
  before: '<path d="M9.6 4.4 6 8l3.6 3.6"/>',
  after: '<path d="M6.4 4.4 10 8l-3.6 3.6"/>',
  less: '<path d="M4 8h8"/>',
  more: '<path d="M4 8h8M8 4v8"/>',
};

/** One mark, at a size, in the ink of whatever it sits in. */
function mark(which, size = 13) {
  return `<svg class="mk" viewBox="0 0 16 16" width="${size}" height="${size}" fill="none"
    stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"
    aria-hidden="true">${MARK[which]}</svg>`;
}

/**
 * **The iPhone app's own words, not the Mac's pills.** Its tabs read "Shot
 * list" and "Mood boards" — sentence case, and "mood boards" rather than
 * "boards", which is what he calls them everywhere but the Mac's mode pill.
 * The pills above keep their own labels; this is a different bar.
 */
const TAB_LABELS = {
  shots: "Shot list", diagrams: "Diagrams", locations: "Locations",
  boards: "Reference Images", schedule: "Schedule",
};

/**
 * The four modes, across the foot of a phone.
 *
 * **Words, no pictures** — his instruction, 2026-09-03: remove glyphs wherever
 * they can go. This file already argues the case for the Mac's capsules ("three
 * words in a row read faster than three little pictures") and then made an
 * exception here. The exception was never earned: *Shot list*, *Locations*,
 * *Mood boards* and *Schedule* are four plain words, and a twenty-pixel drawing
 * over each of them said nothing extra while costing a third of the bar's
 * height — which on a phone is the scarcest thing there is.
 */
function tabbar() {
  return `<div class="tabbar">${MODES.map(([id]) => `
    <button data-mode="${id}" class="tab${mode === id ? " on" : ""}">${TAB_LABELS[id]}</button>`).join("")}</div>`;
}

/**
 * The toggle for the list down the side, and a count.
 *
 * **Never beside the film's name** — his instruction, 2026-09-01: a mark
 * sitting next to a title reads as that film's icon rather than as a control,
 * whatever it is drawn as. So every mode with a list gets this row, and the
 * toggle is in the same place in all of them: far left of the second bar, with
 * the count of the thing the list holds at the other end.
 */
function listbar(said) {
  // **No list toggle here either.** Locations and Boards had their own copy of
  // the control that hid the column beside them; that column is the rail now,
  // and the rail folds itself.
  // **No bar that only carries a count** (his pick, 2026-10-03,
  // `design/31-portal-quiet.html` 3): the count is on the sidebar row.
  void said;
  // **On a phone, the way to the list is on the page** (his pick, 2026-10-03):
  // the sheet keeps it folded, so the page says where it is.
  const label = { locations: "All Locations", boards: "All Boards" }[mode];
  return narrow && label ? `<div class="viewbar listonly"><div class="spacer"></div>${onlyButton(label)}</div>` : "";
}

/** The page's own door to its list in the sheet, drawn alone (`side.js` `data-only`). */
function onlyButton(label) {
  return `<button type="button" class="btn onlybtn" data-sheet="open" data-only="${esc(label)}">${esc(label)}</button>`;
}

/**
 * The dim behind a sheet.
 *
 * On a phone the list and the panel lie *over* the film rather than beside it,
 * and a sheet with nothing behind it reads as a new page — which it is not.
 * Tapping it puts the sheet away, the way tapping outside anything on iOS does.
 */
function scrim(what) {
  return narrow ? `<div class="scrim" data-${what}="1"></div>` : "";
}

function many(n, word) {
  return `${n} ${word}${n === 1 ? "" : "s"}`;
}

function viewbar() {
  const views = [["table", "Table"], ["storyboard", "Storyboard"], ["document", "Document"]];
  // **The Script view, on a film that holds a script** — the words down one
  // side, the shots that cover them down the other. His finding from set,
  // 2026-09-22: that page is the one everyone reaches for.
  if ((model.scripts || []).length) views.push(["script", "Script"]);
  // **The list toggle is gone with the list it hid.** The scenes are in the
  // rail now, and the rail has its own fold — a second control for the same
  // thing, in a different bar, saying it differently, is the fault he named on
  // 2026-09-02 about an arrow beside a name that was already a link.
  const list = "";
  const seg = `<div class="seg">${views.map(([id, label]) => `<button data-view="${id}" class="${view === id ? "on" : ""}">${label}</button>`).join("")}</div>`;
  // **Sort, in one place** (his ask, 2026-10-06: "there should just be a
  // Sort by option to view shots in shooting order"): the script's own
  // order, the order they are shot in, or any column. Shooting Order is the
  // engine's day grouping; dragging a shot there moves it in the shooting
  // order and never renumbers it. A plain select, so a phone gets its own
  // picker.
  const sortNow = byDay() ? "shootingorder" : asking.sortColumn;
  const sorted = LENS ? "" : `<label class="sortpick${sortNow ? " on" : ""}"><span>Sort</span><select data-sortpick aria-label="Sort">
      <option value=""${!sortNow ? " selected" : ""}>Script Order</option>
      <option value="shootingorder"${byDay() ? " selected" : ""}>Shooting Order</option>
      <optgroup label="Column">${shownColumns().filter((c) => c.name !== "image").map((c) =>
        `<option value="${esc(c.name)}"${!byDay() && asking.sortColumn === c.name ? " selected" : ""}>${esc(c.label || labelOf(c.name))}</option>`).join("")}</optgroup>
    </select></label>`;
  // On a phone the filter is in the Scenes sheet, out of sight: while one is
  // on, the bar says so and takes it off in one tap.
  const unfilter = narrow && !LENS && anyFacet() ? `<button class="btn on" data-unfacet="*">Clear Filter</button>` : "";
  // **Beside the count, and no word on it** — his instruction, 2026-09-01. It
  // belongs at the end of the row it acts on rather than up among the modes,
  // and `icon.lit` is the chrome's own way of saying a thing is on.
  const script = LENS ? "" : `<button class="icon${panel ? " lit" : ""}" data-panel="toggle" title="Script, references and notes">${PANEL_MARK}</button>`;

  // **Two rows on a phone, and deliberately.** Five things across 375px push
  // the count and the script toggle off the right edge; the word "Views" goes
  // with them, because the three buttons under it say what they are.
  // **One row on a phone now, where it used to take two.** The count used to be
  // pushed to a second line because five things would not fit across 375px.
  // Four do: the views stopped being squeezed to nothing, which was costing
  // them more width than the count needs.
  //
  // The list button stays. It was briefly taken out on the grounds that a phone
  // has no scene list beside the film — it has one *over* it, as a sheet, which
  // is exactly what this opens.
  if (narrow) {
    return `<div class="viewbar">
      ${list}${seg}${shootSeg()}<div class="spacer"></div>${onlyButton("Scenes")}<span class="lab">${shownCount()}</span>${script}
      ${sorted || unfilter ? `<div class="varow">${sorted}${unfilter}</div>` : ""}
    </div>`;
  }
  // **No "Views" label.** `23-softer.html`: with a choice drawn as a choice
  // and a button as a button, the strip explains itself.
  // **Text size, on the table only** — his ask, 2026-09-15. The Mac's own
  // control: a small A, a slider of four stops, a large A, at the right of the
  // bar. `data-tscale` is the stop's index, so the slider and the stored size
  // cannot disagree about where they are.
  const sizer = view === "table"
    ? `<label class="tscale" title="Text size"><span class="a1">A</span><input type="range" min="0" max="${TEXT_SIZES.length - 1}" step="1" value="${TEXT_SIZES.indexOf(textSize)}" data-tscale="1"><span class="a2">A</span></label>`
    : "";
  return `<div class="viewbar">
    ${list}
    ${seg}
    ${shootSeg()}
    ${sorted}
    <div class="spacer"></div>
    ${sizer}
    <span class="lab">${shownCount()}</span>
    ${script}
  </div>`;
}

/**
 * How much of the film is on screen, in the engine's own count.
 *
 * `filter.shown` and `filter.hiddenScenes` come from the same narrowing the
 * list was built with, so this cannot disagree with what is drawn — which a
 * number counted here could.
 */
/** In shooting order, land on today's day when the film has one. */
function goToToday() {
  const today = (model.days || []).find(isToday);
  if (!today) return;
  const well = root.querySelector(".well");
  const band = well && [...well.querySelectorAll(".dayband")].find((b) => b.dataset.day === today.id);
  if (!band) return;
  const box = scrollerOf(well);
  glide(box, Math.max(0, offsetIn(band, box) - headroom(well, box)), 300, () => {});
}

function shownCount() {
  // Narrowed to a shoot, the count is what is drawn.
  if (shootOn()) {
    const n = shownGroups().reduce((sum, g) => sum + (g.rows || []).length, 0);
    return `${n} ${n === 1 ? "shot" : "shots"}`;
  }
  const filter = model.filter || {};
  // **A count only when something is narrowing the list** (his pick,
  // 2026-10-03, `design/31-portal-quiet.html` 3): the whole film's count is
  // on its sidebar row; what is worth saying here is how much a filter left.
  if (!filter.narrowed && !filter.text && !filter.hideStruck && !filter.hiddenScenes) return "";
  const shown = typeof filter.shown === "number" ? filter.shown : 0;
  const hidden = filter.hiddenScenes || 0;
  const said = `${shown} ${shown === 1 ? "shot" : "shots"}`;
  return hidden ? `${said} · ${hidden} ${hidden === 1 ? "scene" : "scenes"} hidden` : said;
}

function labelOf(name) {
  const column = (model.columns || []).find((c) => c.name === name);
  return column ? column.label || column.name : name;
}

// -------------------------------------------------------------- the shot list

/**
 * Does this shot carry every value he has picked?
 *
 * **The narrowing is done here rather than by the engine, and that is not the
 * first choice.** `view.rs` has `shot_is` and would do it properly — but it
 * compares against the value a shot *stores*, and what the app offers as a
 * filter is the value it *draws*, which `named()` has already turned from a
 * record into its label. A facet sent as `["size","COWBOY/OTS"]` therefore
 * matched nothing and narrowed nothing, silently. Reconciling those two is a
 * change in `engine/`, which another thread is inside; this narrows on exactly
 * the strings the panel offered, so the control is honest today and the engine
 * can take the job back without the screen changing.
 */
function keepsFacets(row) {
  return keeps(row, asking.facets);
}

/**
 * The scenes on the page, in every view.
 *
 * **A picked scene is a place to go, not a filter.** His ask, 2026-09-10:
 * *"When I click into an individual scene on the Shot List, I don't want it to
 * just isolate that scene's shots. I'd rather scroll down with a smooth
 * animation, the same way the actual shotlister app does, to that scene's
 * shots within the table. Same goes for storyboard view and document view."*
 * Until then a pick narrowed the page to one scene, and the storyboard was one
 * scene whatever was picked. Now every view draws the whole film under its
 * scene bands and `goToScene` carries the page to the one he picked. Only the
 * filters narrow.
 */
function shownGroups() {
  // **An archived scene is set aside, in every view** — his report,
  // 2026-09-19. The engine's rows still carry it, and the Mac sets it aside
  // in the shell (`Table.swift`); the sidebar here already did the same, so
  // the scene was gone from the list and still on the page beside it.
  const shelved = archivedScenes();
  let all = byDay()
    // A day's group is cut by its rows' scenes, not by its own key.
    ? (model.groups || [])
        .map((g) => ({ ...g, rows: (g.rows || []).filter((r) => !shelved.has(r.sceneId)) }))
        .filter((g) => g.rows.length)
    : (model.groups || []).filter((g) => !shelved.has(g.key));
  if (asking.facets.length) {
    // A band's count is what the filter leaves, not the scene's whole.
    all = all
      .map((g) => { const rows = (g.rows || []).filter(keepsFacets); return { ...g, rows, count: rows.length }; })
      .filter((g) => g.rows.length);
  }
  // **This shoot's scenes and days** (SL-1396), unless All Shoots is on.
  if (shootOn()) {
    all = byDay()
      ? all
          .filter((g) => dayInShoot((model.days || []).find((d) => d.id === g.key)))
          .map((g) => ({ ...g, rows: (g.rows || []).filter((r) => inShoot(r.sceneId)) }))
          .filter((g) => g.rows.length)
      : all.filter((g) => inShoot(g.key));
  }
  return all;
}

/**
 * **A day's group as the runs of scenes inside it** — each run a scene group
 * of its own, so the three views draw it with the band they already draw,
 * under the day's own head. The Mac's Table does exactly this on a day
 * (`runs` in `engine/src/export/html.rs`); a mixed day reads scene by scene
 * in the board's order, a scene split across days shows its part.
 */
function sceneRunsOf(day) {
  const runs = [];
  for (const row of day.rows || []) {
    const last = runs[runs.length - 1];
    if (last && last.key === row.sceneId) { last.rows.push(row); last.count += 1; continue; }
    const scene = (model.scenes || []).find((x) => x.id === row.sceneId) || {};
    runs.push({
      key: row.sceneId, label: `Scene ${scene.number || ""}`, count: 1, rows: [row],
      heading: scene.heading || "", slug: scene.slug || "", video: "", audio: "",
      colour: "", sequenceTitle: "", day: day.label, intExt: scene.intExt || "",
      location: scene.location || "", timeOfDay: scene.timeOfDay || "",
    });
  }
  return runs;
}

/** `2026-09-20` as `Sun 20 Sep` — a date read on set, not a sort key. */
function niceDate(ymd) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(ymd || "");
  if (!m) return ymd || "";
  const d = new Date(+m[1], +m[2] - 1, +m[3]);
  return d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" });
}

/** Whether this day's date is today, by the calendar this browser keeps. */
function isToday(day) {
  if (!day || !day.date) return false;
  const now = new Date();
  const ymd = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
  return day.date === ymd;
}

/** A day's head over its runs: the label, the date, Today when it is, the count. */
function dayBand(g) {
  const day = (model.days || []).find((d) => d.id === g.key) || { label: g.label, date: "" };
  const today = isToday(day);
  // The day's whole running order, by number — what a drop is placed in,
  // shots a filter or another shoot hides included (`shotDrag`).
  const whole = ((model.groups || []).find((x) => x.key === g.key) || g).rows || [];
  return `<div class="dayband${today ? " today" : ""}" data-day="${esc(g.key || "")}" data-label="${esc(g.label)}" data-whole="${esc(whole.map((r) => r.number).join(","))}">
    <span class="daylabel">${esc(g.label)}</span>
    ${day.date ? `<span class="daydate">${esc(niceDate(day.date))}</span>` : ""}
    ${today ? `<span class="chip today">Today</span>` : ""}
    <span class="count">${many(g.rows.length, "shot")}</span>
  </div>`;
}

/** The scenes he has archived — off the page, off the list, out of the counts. */
function archivedScenes() {
  return new Set((model.scenes || []).filter(setAside).map((s) => s.id));
}

/** The scenes still standing once his filters are applied. */
function scenesLeft() {
  if (!asking.facets.length) return null;
  // In shooting order a group is a day, so its scenes are its rows' scenes.
  return new Set(shownGroups().flatMap((g) => (byDay() ? (g.rows || []).map((r) => r.sceneId) : [g.key])));
}

function shotsMode() {
  const groups = shownGroups();
  measureChipColumns();
  // In shooting order every group is a day; its scene runs are drawn with
  // the same bands and cards, under the day's head. The Script view keeps
  // the script's own order whatever the list is grouped by.
  const drawAll = (draw) => byDay()
    ? groups.map((g) => {
        const runs = sceneRunsOf(g);
        return dayBand(g) + runs.map((r, i) => sectionHeadBefore(runs, i) + draw(r)).join("");
      }).join("")
    : groups.map((g, i) => sectionHeadBefore(groups, i) + draw(g)).join("");
  const body = groups.length
    ? view === "document"
      ? `<div class="desk"><div class="paper">${drawAll(groupDocument)}</div></div>`
      : view === "script"
      ? `<div class="desk"><div class="paper${(model.scripts || []).some((q) => (q.text || "").includes(AV_CELL)) ? " wide" : ""}">${scriptPaper(byDay() ? groups.flatMap(sceneRunsOf) : groups)}</div></div>`
      : drawAll(view === "table" ? groupTable : groupBoardCards)
    : `<div class="sheetwrap"><p class="empty">Nothing here</p></div>`;
  return `<div class="body">
    <div class="well ${view}" style="--tscale:${textSize}">${view === "table" && !narrow ? header() : ""}${body}</div>
    ${panel ? scrim("panelshut") + sidePanel() : ""}
  </div>`;
}

/** Whether this film is a commercial — which changes what a scene is. */
function isCommercial() {
  return !!(model && model.project && model.project.kind === "commercial");
}

/**
 * **The colours a section is born with**, in turn — `Doc::SEQUENCE_COLOURS`
 * in `engine/src/doc.rs`, written out because the browser has no engine to
 * ask. The Mac colours a bare section the first time it opens the film and
 * writes that down, so the portal normally reads the colour off the film;
 * this list stands in for a film the Mac has not opened since 2026-09-19,
 * by the same rule (position among the sections), so the two never disagree.
 */
const SECTION_COLOURS = ["#2B6CB0", "#B4531B", "#2F7A44", "#7B4BC4", "#A33574", "#2C7A7B", "#9A6B10", "#4C51BF"];

/**
 * The section a scene sits in — `{id, title, ink, rgb}` — or null on a
 * film, a scene in no section, or a section the film no longer has. `ink` is
 * the section's own colour; `rgb` is the same as `r,g,b`, so `hub.css` can
 * lay it down at whatever strength the light or the dark page wants.
 */
function sectionOf(sceneId) {
  if (!isCommercial()) return null;
  const scene = (model.scenes || []).find((x) => x.id === sceneId) || {};
  if (!scene.sequence) return null;
  const all = model.sequences || [];
  const at = all.findIndex((q) => q.id === scene.sequence);
  if (at < 0) return null;
  const section = all[at];
  const ink = (section.colour || "").trim() || SECTION_COLOURS[at % SECTION_COLOURS.length];
  return { id: section.id, title: section.title || "", ink, rgb: rgbOf(ink) };
}

/** `#RRGGBB` as `r,g,b`, for an `rgba()` the stylesheet finishes. */
function rgbOf(hex) {
  const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex.trim());
  return m ? `${parseInt(m[1], 16)},${parseInt(m[2], 16)},${parseInt(m[3], 16)}` : "128,128,128";
}

/** The two variables a section's run wears, for `style=""`. */
function sectionVars(section) {
  return `--sec:${section.ink};--sec-rgb:${section.rgb}`;
}

/**
 * **The section's colour is the whole run's.** His finding on Harbour Light
 * Affair, 2026-09-19: three scripts were not telling apart while scrolling,
 * a head with a small square was not enough. The Mac's answer (`sectionSpine`
 * in `Table.swift`) is here too: the section's ink runs as a 4px spine down
 * the left of every band, row and card of its run, so a fast scroll says
 * which script this is before a word is read. Put on the element as a class
 * and a variable; `hub.css` draws the spine. Nothing on a film or a scene in
 * no section.
 */
function runStyle(sceneId) {
  const section = sectionOf(sceneId);
  return section ? { cls: " insec", style: sectionVars(section) } : { cls: "", style: "" };
}

/**
 * **A section's head over the first scene of its run** — the Mac's band, here:
 * tinted with the section's ink, the title set in it, a light wash over its run.
 * Three spots on one job, pasted into three sections, read as three headed runs
 * (his ask, 2026-09-19). Only when the scene's section differs from the one
 * before it; a scene in none gets none. On the Document page it is a chapter
 * head instead — a bar in the section's colour, the title at the sheet
 * title's size, and air above — the Mac's `sectionHead` in `Document.swift`.
 */
function sectionHeadBefore(groups, i) {
  const section = sectionOf(groups[i].key);
  if (!section) return "";
  const before = i > 0 ? sectionOf(groups[i - 1].key) : null;
  if (before && before.id === section.id) return "";
  const vars = sectionVars(section);
  if (view === "document") {
    return `<div class="docsection${i === 0 ? " first" : ""}" style="${vars}">${esc(section.title)}</div>`;
  }
  return `<div class="sectionhead insec" style="${vars}">${esc(section.title)}</div>`;
}

function sceneBand(g) {
  const first = g.rows[0] || {};
  const scene = (model.scenes || []).find((x) => x.id === g.key) || {};
  // The row of chips the app draws under a scene heading, in its order: where,
  // which sequence, which day. A chip that has nothing to say is not drawn —
  // the app offers "Add synopsis" because it can add one, and nobody reading
  // this can. The synopsis itself used to lead this row and is a button now;
  // see below.
  const chips = [];
  const where = scene.shootingLocation || scene.location || g.location;
  if (where) chips.push(["place", where]);
  // The sequence keeps its dot — that colour means something (`23-softer.html`).
  if (first.sequence) chips.push(["sequence", first.sequence, first.sequenceColour]);
  if (first.day) chips.push(["schedule", first.day]);

  // **The synopsis is a button that grows, not a chip that is always open.**
  // It is the only thing in this row that is a paragraph rather than a fact,
  // and it carries the whole of its text either way — pressed, it stops being
  // one line and becomes all of them, which is the Mac's `SynopsisField`.
  const shown = openSynopsis.has(g.key);
  const synopsis = scene.description
    ? `<button class="bandchip toggle${shown ? " on" : ""}" data-synopsis="${esc(g.key)}" title="${shown ? "Shorten" : "Read the synopsis"}">${esc(scene.description)}</button>`
    : "";

  const run = runStyle(g.key);
  return `<div class="sceneband${run.cls}" data-band="${esc(g.key)}"${run.style ? ` style="${run.style}"` : ""}>${editThrough(g)}
    <div class="top">
      <span class="num">${esc(g.label.replace(/^Scene\s*/, ""))}</span>
      <span class="slug">${esc(g.heading || g.location)}</span>
      <span class="count">${g.count} ${g.count === 1 ? "shot" : "shots"}</span>
    </div>
    ${synopsis || chips.length ? `<div class="strip">${synopsis}${chips.map(([, said, colour]) =>
      `<span class="bandchip">${colour ? `<i class="dot" style="background:${esc(colour)}"></i>` : ""}${esc(said)}</span>`).join("")}</div>` : ""}
  </div>`;
}

/** In shooting order, on an editor's page, a shot can be carried: its number rides on it. */
function shotTag(row) {
  return byDay() && !LENS && HUB.role === "editor" ? ` data-shotno="${esc(row.number)}"` : "";
}

function groupTable(g) {
  const run = runStyle(g.key);
  const pieces = editPieces(g);
  return sceneBand(g) + g.rows.map((row, at) => shotRow(row, run, pieces[at])).join("");
}

// ── Edit Reference, the first mod (2026-10-17) ─────────────────────────────
//
// A gold bracket in the margin joins the shots an edit reference cuts
// together, with a play button at its top; the player shows the clip with the
// shot on now. Drawn only when the project has the mod on (`HUB.mods`); the
// runs of rows are the engine's (`editSpans` on each group), the same ones
// Studio and the phone draw.
const MOD_EDIT = "edit_reference";
function editOn() {
  return Array.isArray(HUB.mods) && HUB.mods.includes(MOD_EDIT) && !!model && Array.isArray(model.editRefs) && model.editRefs.length > 0;
}
function editRef(id) { return ((model && model.editRefs) || []).find((e) => e.id === id) || null; }
function editClock(s) { const t = Math.max(0, Math.floor(s || 0)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`; }
function editRange(e) {
  const a = e.shots[0], b = e.shots[e.shots.length - 1];
  return !a ? "" : a.number === b.number ? a.number : `${a.number}–${b.number}`;
}
/** Each row's pieces, by its index in the group. */
function editPieces(g) {
  const out = {};
  if (!editOn() || !Array.isArray(g.editSpans)) return out;
  for (const span of g.editSpans) {
    const ref = editRef(span.ref);
    if (!ref) continue;
    let lane = 0;
    for (let i = span.from; i <= span.to; i++) lane = Math.max(lane, (out[i] || []).length);
    // A run that carries on across a scene heading (the engine's `before` /
    // `after`) has no button or hook at that end: it is one bracket.
    for (let i = span.from; i <= span.to; i++) {
      const row = g.rows[i];
      (out[i] = out[i] || []).push({ ref, first: i === span.from && !span.before, last: i === span.to && !span.after, lane, shot: row && row.shot });
    }
  }
  return out;
}
/** The brackets passing a scene's heading: runs that carry on from above. */
function editThrough(g) {
  if (!editOn()) return "";
  const lines = [];
  for (const span of g.editSpans || []) if (span.before && span.from === 0 && editRef(span.ref)) lines.push(span.ref);
  for (const id of g.editThrough || []) if (editRef(id) && !lines.includes(id)) lines.push(id);
  return lines.map((id, lane) => `<span class="eref thru" style="--lane:${lane}" data-erefline="${esc(id)}"></span>`).join("");
}
function editMarks(pieces) {
  if (!pieces || !pieces.length) return "";
  return pieces.map((p) => {
    const tip = `${p.ref.name} · ${editRange(p.ref)}${p.ref.length > 0 ? ` · ${editClock(p.ref.length)}` : ""}`;
    return `<span class="eref${p.first ? " first" : ""}${p.last ? " last" : ""}" style="--lane:${p.lane}" data-erefline="${esc(p.ref.id)}">${
      p.first ? `<button class="eref-play" data-editref="${esc(p.ref.id)}" data-erefshot="${esc(p.shot || "")}" title="${esc(tip)}" aria-label="Play ${esc(p.ref.name)}">${EDIT_PLAY}</button>` : `<i class="eref-dot" data-erefshot="${esc(p.ref.id + ":" + (p.shot || ""))}"></i>`}</span>`;
  }).join("");
}
const EDIT_PLAY = '<svg viewBox="0 0 10 10" width="9" height="9" aria-hidden="true"><path d="M2.5 1.5v7l6-3.5z" fill="currentColor"/></svg>';

/** **The player**, over the page (2026-10-17, take two: "just play the video"):
 *  the clip, play and pause, a scrubber with the time, close. It blooms out of
 *  the bracket's gold button on a spring and folds back into it; Reduce Motion
 *  makes both a fade. Space plays and pauses, ← → step five seconds, Escape
 *  closes. While it plays, the dot of the shot on now glows on the bracket. */
const EDIT_SPRING = "linear(0, 0.009, 0.035 2.1%, 0.141 4.4%, 0.723 12.9%, 0.938 16.7%, 1.017 19.4%, 1.067, 1.089 24.7%, 1.085 27.1%, 1.05 32.1%, 1.012 37.2%, 0.993 42.6%, 0.991 49.5%, 1.001 63.6%, 1)";
const EDIT_PAUSE = '<svg viewBox="0 0 10 10" width="12" height="12" aria-hidden="true"><path d="M2.5 1.5h1.8v7H2.5zM5.7 1.5h1.8v7H5.7z" fill="currentColor"/></svg>';
function editCalm() { return matchMedia("(prefers-reduced-motion: reduce)").matches; }
function openEditRef(id, from) {
  const ref = editRef(id);
  if (!ref) return;
  closeEditRef(true);
  const clip = ref.media.find((m) => m.kind === "video");
  const stills = ref.media.filter((m) => m.kind === "image" || m.kind === "gif");
  const first = clip || stills[0];
  const shape = first && first.width > 0 && first.height > 0 ? `${first.width} / ${first.height}` : "16 / 9";
  const wrap = document.createElement("div");
  wrap.className = "eref-wrap";
  wrap.innerHTML = `<div class="eref-panel" role="dialog" aria-modal="true" aria-label="${esc(ref.name)}">
    <div class="eref-head"><b>${esc(ref.name)}</b>
      <span class="eref-count">${esc(editRange(ref))}${ref.length > 0 ? ` · ${editClock(ref.length)}` : ""}</span>
      ${ref.link ? `<a class="eref-open" href="${esc(ref.link)}" target="_blank" rel="noopener">Open Link</a>` : ""}
      <button class="eref-x" title="Close" aria-label="Close"><svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><path d="M2 2l8 8M10 2l-8 8" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg></button></div>
    <div class="eref-pic" style="aspect-ratio:${shape}">
      ${clip ? `<video playsinline preload="auto" poster="${mediaSrc(clip, POSTER)}" src="${mediaSrc(clip, extensionOf(clip))}"></video>`
        : stills.length ? `<img class="eref-still" alt="" src="${mediaSrc(stills[0], extensionOf(stills[0]))}">`
        : ref.link ? `<a class="eref-link" href="${esc(ref.link)}" target="_blank" rel="noopener">Open Link</a>` : ""}
      <span class="eref-gold" aria-hidden="true">${EDIT_PLAY}</span>
    </div>
    <div class="eref-ctl"><button class="eref-pp" aria-label="Play">${EDIT_PLAY}</button>
      <span class="eref-time eref-now-t">0:00</span>
      <div class="eref-scrub" role="slider" tabindex="0" aria-label="Position" aria-valuemin="0" aria-valuemax="${Math.round(ref.length)}" aria-valuenow="0"><i class="track"></i><i class="fill"></i><i class="knob"></i></div>
      <span class="eref-time">${editClock(ref.length)}</span></div>
  </div>`;
  (document.querySelector(".app") || document.body).appendChild(wrap);
  const panel = wrap.querySelector(".eref-panel");
  const video = wrap.querySelector("video");
  const scrub = wrap.querySelector(".eref-scrub");
  let t = 0, playing = false, tick = 0;
  const now = () => (video ? video.currentTime : t);
  const at = () => { let k = 0; ref.shots.forEach((s, i) => { if (s.start <= now() + 0.001) k = i; }); return k; };
  const paint = () => {
    const p = ref.length > 0 ? Math.min(1, now() / ref.length) : 0;
    scrub.style.setProperty("--p", p);
    scrub.setAttribute("aria-valuenow", String(Math.round(now())));
    wrap.querySelector(".eref-now-t").textContent = editClock(now());
    const pp = wrap.querySelector(".eref-pp");
    pp.innerHTML = playing ? EDIT_PAUSE : EDIT_PLAY;
    pp.setAttribute("aria-label", playing ? "Pause" : "Play");
    panel.classList.toggle("playing", playing);
    const still = wrap.querySelector(".eref-still");
    if (still && stills.length && ref.length > 0) {
      const pic = stills[Math.min(stills.length - 1, Math.floor(p * stills.length))];
      const src = mediaSrc(pic, extensionOf(pic));
      if (still.getAttribute("src") !== src) still.setAttribute("src", src);
    }
    // the shot on now glows on the bracket behind
    const shot = ref.shots[at()];
    document.querySelectorAll("[data-erefshot]").forEach((d) => d.classList.remove("now"));
    if (shot) {
      document.querySelectorAll(`.eref-dot[data-erefshot="${CSS.escape(ref.id + ":" + shot.shot)}"]`).forEach((d) => d.classList.add("now"));
      if (at() === 0) document.querySelectorAll(`.eref-play[data-editref="${CSS.escape(ref.id)}"]`).forEach((d) => d.classList.add("now"));
    }
  };
  const seek = (s) => { const to = Math.max(0, ref.length > 0 ? Math.min(ref.length, s) : s); if (video) video.currentTime = to; else t = to; paint(); };
  const pause = () => { playing = false; if (video) video.pause(); clearInterval(tick); paint(); };
  const play = () => {
    if (ref.length > 0 && now() >= ref.length - 0.1) seek(0);
    playing = true;
    if (video) video.play().catch(() => {});
    else { clearInterval(tick); tick = setInterval(() => { t = Math.min(ref.length, t + 0.1); if (t >= ref.length) pause(); paint(); }, 100); }
    paint();
  };
  if (video) {
    video.addEventListener("timeupdate", paint);
    video.addEventListener("ended", pause);
    video.addEventListener("click", () => (playing ? pause() : play()));
  }
  wrap.querySelector(".eref-pp").addEventListener("click", () => (playing ? pause() : play()));
  const seekAt = (e) => { const r = scrub.getBoundingClientRect(); seek(((e.clientX - r.left) / r.width) * ref.length); };
  scrub.addEventListener("pointerdown", (e) => {
    scrub.setPointerCapture(e.pointerId); scrub.classList.add("held"); seekAt(e);
    const mv = (ev) => seekAt(ev);
    scrub.addEventListener("pointermove", mv);
    scrub.addEventListener("pointerup", () => { scrub.removeEventListener("pointermove", mv); scrub.classList.remove("held"); }, { once: true });
  });
  scrub.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") { seek(now() + 5); e.preventDefault(); }
    if (e.key === "ArrowLeft") { seek(now() - 5); e.preventDefault(); }
  });
  wrap.addEventListener("keydown", (e) => {
    if (e.key === " " && !e.target.closest("button, a")) { e.preventDefault(); playing ? pause() : play(); }
    if ((e.key === "ArrowRight" || e.key === "ArrowLeft") && e.target === wrap) { seek(now() + (e.key === "ArrowRight" ? 5 : -5)); }
  });
  wrap.querySelector(".eref-x").addEventListener("click", () => closeEditRef());
  wrap.addEventListener("click", (e) => { if (e.target === wrap) closeEditRef(); });
  // From the button to the panel: where it starts and how small.
  const fromButton = () => {
    const p = panel.getBoundingClientRect();
    if (!from) return { dx: 0, dy: 0, s: 0.05 };
    const b = from.getBoundingClientRect();
    return { dx: b.left + b.width / 2 - (p.left + p.width / 2), dy: b.top + b.height / 2 - (p.top + p.height / 2), s: Math.max(0.02, b.width / p.width) };
  };
  wrap.closeIt = (now) => {
    pause();
    document.querySelectorAll("[data-erefshot]").forEach((d) => d.classList.remove("now"));
    if (now) { wrap.remove(); return; }
    wrap.classList.remove("on");
    const done = () => { wrap.remove(); if (from && from.isConnected) { from.focus({ preventScroll: true }); if (!editCalm()) from.animate([{ transform: "scale(1.3)" }, { transform: "scale(1)" }], { duration: 320, easing: EDIT_SPRING }); } };
    if (editCalm()) { panel.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 160, fill: "both" }).onfinish = done; return; }
    const { dx, dy, s } = fromButton();
    wrap.querySelector(".eref-gold").animate([{ opacity: 0 }, { opacity: 1 }], { duration: 130, fill: "both" });
    panel.animate([{ transform: "translate(0,0) scale(1)", borderRadius: "12px" }, { transform: `translate(${dx}px, ${dy}px) scale(${s})`, borderRadius: "50%" }],
      { duration: 260, easing: "cubic-bezier(.5,0,.75,0)", fill: "both" }).onfinish = done;
  };
  paint();
  const held = new URLSearchParams(location.search).get("editrefat");
  const stop = new URLSearchParams(location.search).get("editrefbloom");
  wrap.classList.add("on");
  if (stop !== null) {
    const { dx, dy, s } = fromButton(), k = Number(stop) || 0;
    panel.style.transform = `translate(${dx * (1 - k)}px, ${dy * (1 - k)}px) scale(${s + (1 - s) * k})`;
    wrap.querySelector(".eref-gold").style.opacity = k < 0.6 ? 1 : Math.max(0, 1 - (k - 0.6) / 0.4);
    return;
  }
  if (editCalm()) {
    wrap.querySelector(".eref-gold").style.opacity = 0;
    panel.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 200, easing: "ease-out" });
  } else {
    const { dx, dy, s } = fromButton();
    panel.animate([{ transform: `translate(${dx}px, ${dy}px) scale(${s})`, borderRadius: "50%" }, { transform: "translate(0,0) scale(1)", borderRadius: "12px" }],
      { duration: 520, easing: EDIT_SPRING });
    wrap.querySelector(".eref-gold").animate([{ opacity: 1 }, { opacity: 1, offset: 0.55 }, { opacity: 0 }], { duration: 680, easing: "ease-out", fill: "both" });
  }
  wrap.querySelector(".eref-x").focus({ preventScroll: true });
  if (held !== null) seek(Number(held) || 0);
  else setTimeout(play, editCalm() ? 50 : 300);
}
function closeEditRef(now) {
  document.querySelectorAll(".eref-wrap").forEach((w) => { if (w.closeIt) w.closeIt(now); else w.remove(); });
}
document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeEditRef(); });

/** A row, cell by cell, in the project's own column order. */
function shotRow(row, run = { cls: "", style: "" }, pieces = null) {
  if (narrow) return listRow(row, run, pieces);
  return `<div class="trow${row.struck ? " struck" : ""}${run.cls}"${shotTag(row)} style="grid-template-columns:${gridTemplate()}${run.style ? `;${run.style}` : ""}">
    ${editMarks(pieces)}<span class="no">${markBtn(row)}${esc(row.number)}</span>
    ${shownColumns().map((c) => `<span class="td td-${slug(c.name)}">${cellFor(row, c)}</span>`).join("")}
  </div>`;
}

/**
 * A shot on a phone — **the iPhone app's row, not the table squeezed.**
 *
 * `ShotRow` in `phone/Sources/ShotList.swift`: the frame at the left, the
 * number and the name loud on one line, what the shot says under them, and the
 * craft small beneath that. Eleven columns across a 375px screen is two
 * scrollbars fighting each other, and the app has never drawn it that way on a
 * phone.
 *
 * **Nothing is dropped, and that is the one place this parts company with the
 * app.** The phone can afford three of the craft columns because tapping a
 * shot opens the whole of it; the portal has no page to tap into, so every
 * visible column is still here — the prose as prose, everything else as the
 * same chips, in the same ink, that the table draws.
 */
/**
 * **One frame, and how many there are** — `FrameThumbnail` on the iPhone.
 *
 * The table puts a shot's frames side by side, up to four, because a hundred
 * and thirty points can carry four panels. A hundred cannot: four of them come
 * out twenty-five points wide, which is a smudge rather than a picture. So a
 * phone shows the frame that stands for the shot and lets `stillMarks` say in
 * the corner how many others there are — which is the mark the app already
 * draws for exactly this.
 */
function oneFrame(row) {
  const key = keyFrame(row);
  if (!key || !key.hash) return `<span class="frame empty" style="aspect-ratio:${ratio()}">${NO_PICTURE}</span>`;
  return `<button class="frame" style="aspect-ratio:${ratio()}" data-open="${esc(row.placement || "")}" title="Open">${mediaTag(key)}${stillMarks(row)}</button>`;
}

/**
 * **The Shot mark, as a control.** An editor's one write from the page: a
 * ring beside the number, a filled tick once the shot is got. Struck means
 * got, labelled Shot everywhere (his ruling, 2026-09-16). A viewer sees
 * nothing here — the SHOT chip in the row says it for them. The press goes
 * to `PUT api/mark`, the row flips at once, and the film is read again when
 * the log lands, which is how every other device's mark arrives too.
 */
function markBtn(row) {
  if (HUB.role !== "editor" || !row.number) return "";
  return `<button class="markbtn${row.struck ? " on" : ""}" data-mark="${esc(row.number)}" data-done="${row.struck ? "0" : "1"}" title="${row.struck ? "Shot" : "Mark shot"}" aria-pressed="${row.struck ? "true" : "false"}">${tick_mark()}</button>`;
}

function listRow(row, run = { cls: "", style: "" }, pieces = null) {
  const columns = shownColumns();
  const has = (name) => columns.some((c) => c.name === name);
  const chips = columns
    .filter((c) => c.name !== "image" && !isProse(c) && !isCheck(c))
    .map((c) => cellFor(row, c))
    .filter(Boolean)
    .join(" ");
  return `<div class="lrow${row.struck ? " struck" : ""}${run.cls}"${shotTag(row)}${run.style ? ` style="${run.style}"` : ""}>
    ${editMarks(pieces)}${has("image") ? `<div class="lframe">${oneFrame(row)}</div>` : ""}
    <div class="lsaid">
      <div class="ltop">
        ${markBtn(row)}<span class="no">${esc(row.number)}</span>
        ${has("title") && row.title ? `<span class="ltitle">${esc(row.title)}</span>` : ""}
      </div>
      ${has("description") && row.description ? `<p class="prose">${esc(row.description)}</p>` : ""}
      ${has("notes") && row.notes ? `<p class="prose note">${esc(row.notes)}</p>` : ""}
      ${columns.filter((c) => kindOf(c) === "text").map((c) => cellFor(row, c)).filter(Boolean)
          .map((said) => `<p class="prose note">${said}</p>`).join("")}
      ${chips ? `<div class="lchips">${chips}</div>` : ""}
    </div>
  </div>`;
}

/**
 * The storyboard — every scene, each under its own band, the cards below.
 *
 * It was one scene at a time until 2026-09-10, the way the Mac draws it; his
 * ask that day was that a scene picked from the list be scrolled to here as
 * it is in the table, which means the others have to be on the page to scroll
 * past. The band is the same band the table draws, so the two read alike.
 */
function groupBoardCards(g) {
  const run = runStyle(g.key);
  return sceneBand(g) + `<div class="cards${run.cls}" style="--film:${ratio()}${run.style ? `;${run.style}` : ""}">${g.rows.map((row) => {
    // **The picture area takes the shape of the shot's own Print Frame**, whole,
    // never cropped to a fixed box; a shot without one keeps the film's frame.
    // If the baked board is not on this page's copy of the film, the card goes
    // back to the key picture and the film's shape (`boardMissing`).
    const own = boardShape(row);
    const r = own ? own.r : ratio();
    const key = keyFrame(row);
    const plain = key ? mediaTag(key) + stillMarks(row) : NO_PICTURE;
    return `
    <div class="card"${shotTag(row)} style="--r:${r}">
      <button class="cardframe${own ? " board" : ""}" style="aspect-ratio:${r}" data-open="${esc(row.placement || "")}"${own ? ` data-fallback="${esc(plain)}"` : ""}>${
        own ? `<img class="boardpic" alt="" loading="lazy" src="${own.src}">` : plain
      }</button>
      <div class="cardsaid">
        <div class="no">${markBtn(row)}${esc(row.number)}</div>
        <div class="said">${esc(row.title || row.description)}</div>
        ${cardChips(row)}
      </div>
    </div>`;
  }).join("")}</div>`;
}

/** A shot's baked Print Frame as the storyboard draws it: its shape and where its picture is. */
function boardShape(row) {
  // Only a current bake — what prints; a stale one is the key picture again.
  const b = row.printFrame && !row.printFrame.stale && row.printFrame.baked;
  if (!b || !b.hash || !(b.width > 0) || !(b.height > 0)) return null;
  return { r: b.width / b.height, src: mediaSrc(b, String(b.ext || "jpg").replace(/[^a-z0-9]/gi, "").toLowerCase() || "jpg") };
}

// A board that is not here: put the key picture back, at the film's shape.
document.addEventListener("error", (e) => {
  const img = e.target;
  if (!img || img.tagName !== "IMG" || !img.classList.contains("boardpic")) return;
  const box = img.closest(".cardframe");
  if (!box || box.dataset.fallback === undefined) return;
  const card = box.closest(".card");
  box.classList.remove("board");
  box.style.aspectRatio = String(ratio());
  if (card) card.style.setProperty("--r", String(ratio()));
  box.innerHTML = box.dataset.fallback;
  delete box.dataset.fallback;
}, true);

/**
 * **A category wears the same clothes in every view.** The card shows the
 * table's chips, small, in the table's own column order — the typewriter line
 * is kept only for the Document view, because that is paper.
 */
function cardChips(row) {
  const chips = shownColumns()
    .filter((c) => c.name !== "image" && c.name !== "struck" && !isProse(c) && !isCheck(c))
    .map((c) => cellFor(row, c))
    .filter(Boolean)
    .join(" ");
  return chips ? `<div class="cardchips">${chips}</div>` : "";
}

/**
 * The document — **a sheet of paper on a desk**, which is most of what makes it
 * feel like the app's own.
 *
 * The number sits out in the margin, the title is set in serif, the technical
 * line is mono under it, and the picture comes *below* the words rather than
 * beside them. A note is italic. The desk behind the page is markedly darker
 * than the app's other surfaces on purpose: it is what makes the page read as
 * paper rather than as a narrower window.
 */
function groupDocument(g) {
  return `<div class="docscene" data-band="${esc(g.key)}">
    <div class="dochead">
      <span class="no">${esc(g.label.replace(/^Scene\s*/, ""))}</span>
      <span class="slug">${esc(g.heading || g.location)}</span>
      <span class="shots">${g.count} ${g.count === 1 ? "SHOT" : "SHOTS"}</span>
    </div>
    ${g.rows.map((row) => `
      <div class="docshot">
        <span class="no">${esc(row.number)}</span>
        <div class="docbody">
          <div class="title">${esc(row.title || row.description)}</div>
          ${row.technical ? `<div class="tech">${esc(row.technical)}</div>` : ""}
          ${row.title && row.description ? `<p class="said">${esc(row.description)}</p>` : ""}
          ${row.script ? `<div class="quote">${row.script.split(/\n\s*\n/).map((q) => `<p>${esc(q.trim()).replace(/\n/g, "<br>")}</p>`).join("")}</div>` : ""}
          ${row.notes ? `<p class="note">${esc(row.notes)}</p>` : ""}
          ${documentFrames(row)}
        </div>
      </div>`).join("")}
  </div>`;
}

// ------------------------------------------------------------ the Script view

/**
 * **The script is the spine; the shots hang off it.** The same page the Mac
 * prints (`html::script` in `engine/src/export/html.rs`), drawn on the
 * paper: each script the film holds is a chapter; the script is cut wherever
 * a shot's quoted stretch begins or ends; beside each stretch stand the shots
 * that cover the whole of it, cued by the scene they belong to; a stretch
 * nobody covers says so; shots tied to no words come last, under their scene.
 * A script with no live shot on the page has no chapter — a dropped version's
 * script lives on an archived scene, and a chapter of red lines would be the
 * page disagreeing with the film.
 *
 * Ranges are UTF-16 offsets — the engine's and JavaScript's — so `slice`
 * reads them as they are, as `quotedScript` already does.
 */
function scriptPaper(groups) {
  const all = [];
  for (const g of groups) for (const row of g.rows || []) all.push({ row, scene: g.key });
  const chapters = (model.scripts || []).map((script) => scriptChapter(script, all)).filter(Boolean);
  return chapters.length ? chapters.join("") : `<p class="empty">No script</p>`;
}

/**
 * **A shot's stretches**, `[[from, to], …]` — a shot can quote several
 * lines far apart (2026-10-05) — else the one it always had.
 */
function spansOf(row) {
  if (Array.isArray(row.scriptSpans) && row.scriptSpans.length)
    return row.scriptSpans.filter((s) => Array.isArray(s) && s[1] > s[0]);
  if (typeof row.scriptFrom === "number" && typeof row.scriptTo === "number" && row.scriptTo > row.scriptFrom)
    return [[row.scriptFrom, row.scriptTo]];
  return [];
}

function scriptChapter(script, all) {
  const key = script.section || "";
  const inSection = (sceneId) => {
    const scene = (model.scenes || []).find((x) => x.id === sceneId) || {};
    return (scene.sequence || "") === key;
  };
  // One quote for each of a shot's stretches; `at` is the shot.
  const quotes = all.flatMap((x, at) =>
    (x.row.scriptOf || "") === key ? spansOf(x.row).map(([from, to]) => ({ at, from, to })) : []);
  const untied = all
    .map((x, at) => at)
    .filter((at) => !spansOf(all[at].row).length && inSection(all[at].scene));
  if (!quotes.length && !untied.length) return "";

  const section = key ? sectionById(key) : null;
  const title = section ? section.title : (model.project && model.project.title) || "Script";
  const vars = section ? ` style="${sectionVars(section)}"` : "";
  const count = new Set(quotes.map((q) => q.at)).size + untied.length;
  const text = script.text || "";
  // **An AV script keeps its two columns** (his report, 2026-10-02: Video
  // and Audio ran together into one block, a row's last line of picture
  // glued to the next line of dialogue). Video, Audio, Shots — the heads
  // the side panel's grid wears, a row of the script to a row of the page.
  const av = text.includes(AV_CELL);
  // **Tall frames sit beside the words, small** — a 9:16 frame drawn the
  // column's width was a screen tall, and a page of them was pictures with
  // words lost between. The film's frame is the one shape every shot has.
  const kind = `${av ? " av" : ""}${ratio() < 1 ? " tall" : ""}`;
  // An AV chapter carries both sets of heads; a paper too narrow for three
  // columns stacks Audio under Video and wears Script / Shots (`scpaper`).
  const heads = av
    ? [["h-v", "Video"], ["h-a", "Audio"], ["h-s", "Script"], ["", "Shots"]]
    : [["", "Script"], ["", "Shots"]];
  let out = `<div class="scchapter"${vars}>
    <div class="docsection first"><span class="sctitle">${esc(title)}</span><span class="sccount">${many(count, "shot")}</span></div>
    <div class="scgrid${kind}"><div class="sccols">${heads.map(([k, h]) => `<span${k ? ` class="${k}"` : ""}>${h}</span>`).join("")}</div>`;
  // The scene is said where it changes, through the whole chapter — said
  // over every stretch, it was the same two lines a dozen times down a page.
  const cued = { last: null };
  for (const stretch of scriptStretches(text, quotes)) {
    const rows = stretch.shots.map((at) => all[at]);
    const right = rows.length
      ? scriptCell(rows, cued)
      : `<div class="scnone">No shot covers these lines</div>`;
    const left = av ? avStretch(text, stretch.from, stretch.to) : paragraphsOf(stretch.text);
    out += `<div class="scrow"><div class="scscript">${left}</div><div class="scshots">${right}</div></div>`;
  }
  let at = 0;
  while (at < untied.length) {
    const scene = all[untied[at]].scene;
    const run = [];
    while (at < untied.length && all[untied[at]].scene === scene) run.push(all[untied[at++]]);
    // The scene is this row's left-hand cue; the one over its first shot is
    // for a phone, where the left-hand side is not drawn.
    cued.last = null;
    out += `<div class="scrow untied"><div class="scscript"><div class="scwhere">${sceneCue(scene)}</div></div><div class="scshots">${scriptCell(run, cued)}</div></div>`;
  }
  return `${out}</div></div>`;
}

/**
 * **One stretch of an AV script, a row of Video beside Audio for every row
 * it touches.** A stretch is cut where quotes begin and end, so it may start
 * partway into a row's Audio or run on across rows; the side it starts on is
 * known by reading the marks before it. A third cell, which the Mac folds
 * into Audio (`av_rows`), is folded the same way here.
 */
function avStretch(text, from, to) {
  let audio = false;
  for (let i = 0; i < from; i++) {
    if (text[i] === AV_ROW) audio = false;
    else if (text[i] === AV_CELL) audio = true;
  }
  const rows = [{ video: "", audio: "" }];
  for (let i = from; i < to; i++) {
    const c = text[i];
    const row = rows[rows.length - 1];
    if (c === AV_ROW) { rows.push({ video: "", audio: "" }); audio = false; }
    else if (c === AV_CELL) { if (audio) row.audio += "\n"; audio = true; }
    else if (audio) row.audio += c;
    else row.video += c;
  }
  return rows
    .filter((r) => r.video.trim() || r.audio.trim())
    .map((r) => `<div class="scv">${paragraphsOf(r.video)}</div><div class="sca">${paragraphsOf(r.audio)}</div>`)
    .join("");
}

/** A section by its id — `{id, title, ink, rgb}` — or null. */
function sectionById(id) {
  const all = model.sequences || [];
  const at = all.findIndex((q) => q.id === id);
  if (at < 0) return null;
  const section = all[at];
  const ink = (section.colour || "").trim() || SECTION_COLOURS[at % SECTION_COLOURS.length];
  return { id: section.id, title: section.title || "", ink, rgb: rgbOf(ink) };
}

/**
 * Cut a script wherever a quote begins or ends, and say for each piece which
 * shots cover the whole of it. White-space pieces go; neighbours covered by
 * the same shots are one piece.
 */
function scriptStretches(text, quotes) {
  const len = text.length;
  const cuts = [...new Set([0, len, ...quotes.flatMap((q) => [Math.min(q.from, len), Math.min(q.to, len)])])].sort((a, b) => a - b);
  const out = [];
  for (let i = 0; i + 1 < cuts.length; i++) {
    const [a, b] = [cuts[i], cuts[i + 1]];
    if (b <= a) continue;
    const shots = quotes.filter((q) => q.from <= a && q.to >= b).map((q) => q.at);
    const piece = text.slice(a, b);
    const last = out[out.length - 1];
    if (last && last.shots.length === shots.length && last.shots.every((x, k) => x === shots[k])) {
      last.text += piece;
      last.to = b;
    } else out.push({ text: piece, shots, from: a, to: b });
  }
  // An AV script's marks are not words: a piece of nothing but a mark (or
  // a mark and a line break) drew an empty row with shots beside it.
  return out.filter((s) => s.text.replace(/[\u001d\u001e]/g, "").trim());
}

function paragraphsOf(text) {
  return text.split(/\n\s*\n/).map((q) => q.trim()).filter(Boolean)
    .map((q) => `<p>${esc(q).replace(/\n/g, "<br>")}</p>`).join("");
}

/** The scene as a cue over a shot — its title, its slug under it. */
function sceneCue(sceneId) {
  const scene = (model.scenes || []).find((x) => x.id === sceneId) || {};
  const heading = scene.heading || scene.title || scene.location || "";
  const slug = scene.slug && scene.slug !== heading ? `<span class="slug">${esc(scene.slug)}</span>` : "";
  return `${esc(heading)}${slug}`;
}

/**
 * The shots in a cell, cued by scene where the scene changes — `cued.last`
 * carries the scene from one cell to the next down the chapter. The words
 * and the frames are kept apart so a film with tall frames can stand them
 * beside the words (`.scgrid.tall`) and a wide one under them.
 */
function scriptCell(rows, cued = { last: null }) {
  return rows.map(({ row, scene }) => {
    const cue = scene !== cued.last ? `<div class="sccue">${sceneCue(scene)}</div>` : "";
    cued.last = scene;
    return `<div class="scshot${row.struck ? " struck" : ""}">
      ${cue}
      <div class="scbody">
        <div class="scwords">
          <div class="schead">${markBtn(row)}<span class="no">${esc(row.number)}</span><span class="title">${esc(row.title || row.description)}</span></div>
          ${row.technical ? `<div class="tech">${esc(row.technical)}</div>` : ""}
          ${row.title && row.description ? `<p class="said">${esc(row.description)}</p>` : ""}
          ${row.notes ? `<p class="note">${esc(row.notes)}</p>` : ""}
        </div>
        ${documentFrames(row)}
      </div>
    </div>`;
  }).join("");
}

/**
 * **Every frame the shot has, in a row** — which is what the app's document
 * page draws, without a limit and without a mark on any of them. A page of
 * paper carries prose and pictures and no furniture.
 */
function documentFrames(row) {
  const shown = panels(row);
  if (!shown.length) return "";
  return `<div class="docframes">${shown.map((m, i) => framePanel(row, m, i, "docframe")).join("")}</div>`;
}

/**
 * A pane with one side filled — the panel beside the list — and its mirror.
 *
 * **One icon mirrored, on one plane** — his ruling, 2026-09-01, and unchanged.
 * What changed on 2026-09-02 is the drawing: it was a frame with a hairline
 * ruled down it, which at thirteen pixels is a rectangle with a scratch in it
 * and reads as unfinished. The pane it stands for is *filled* now, so the icon
 * says which side is the panel rather than merely where a line falls.
 */
function paneMark(side) {
  const filled = side === "left" ? "3.3" : "9.5";
  return (
    '<svg viewBox="0 0 16 16" width="13" height="13" aria-hidden="true">' +
    '<rect x="2.4" y="2.6" width="11.2" height="10.8" rx="2.2" fill="none" ' +
    'stroke="currentColor" stroke-width="1.35"/>' +
    `<rect x="${filled}" y="3.5" width="3.2" height="9" rx="1.1" fill="currentColor" opacity=".42"/></svg>`
  );
}

const SIDE_MARK = paneMark("left");
const PANEL_MARK = paneMark("right");

// ------------------------------------------------------------- the side panel

function sidePanel() {
  // Picked beats read: somebody who has chosen a scene has said what they want.
  const chosen = model.scenes.find((s) => s.id === (scene || inView));
  const sections = [["script", "Script"], ["references", "References"], ["notes", "Notes"]];
  return `<div class="panelside" data-showing="${esc(chosen ? chosen.id : "")}">
    <div class="paneltabs">
      ${sections.map(([id, label]) => `<button data-panel="${id}" class="${panel === id ? "on" : ""}">${label}</button>`).join("")}
    </div>
    ${
      // **Which scene this is.** With the panel following the page rather than
      // waiting to be told, a pane with no name on it leaves somebody reading a
      // scene and unable to say which one.
      chosen
        ? `<div class="panelhead"><span>${esc(chosen.number ? `${chosen.number}  ` : "")}${esc(chosen.heading || chosen.location || "")}</span></div>`
        : ""
    }
    ${!chosen
      ? `<div class="panelbody"><p class="empty">No scene</p></div>`
      : panel === "script" ? scriptPane(chosen)
      : panel === "notes" ? notesPane(chosen)
      : referencesPane(chosen)}
  </div>`;
}

function scriptPane(s) {
  if (isCommercial()) return avPane(s);
  if (!s.script) return `<div class="panelbody"><p class="empty">Not in the script</p></div>`;
  return `<div class="panelhead"><span>Scene ${esc(s.number)}</span></div>
    <div class="sheet">${esc(s.script)}</div>`;
}

/**
 * **A commercial's script is an AV script** — the Mac's `avPane` in
 * `ScriptPanel.swift`, read-only. One script at a time: the scene in view's
 * section's, else the film's own, and a dropdown when the job has several
 * (Ref 1090, one per section). Every shot's quoted stretch is tinted the way
 * `ScriptText` tints it; where stretches overlap the tint is darker, which is
 * honest. Tying a shot to its words stays on the Mac — this is the page, not
 * the desk. His report, 2026-09-19 night: the script column was here and the
 * script itself was not.
 */
let scriptSection = null;   // the script he picked in the panel, when several

function avPane(s) {
  const scripts = model.scripts || [];
  if (!scripts.length) return `<div class="panelbody"><p class="empty">No script</p></div>`;
  const has = (id) => scripts.some((q) => q.section === id);
  const inView = s.sequence && has(s.sequence) ? s.sequence : scripts[0].section;
  const section = scriptSection !== null && has(scriptSection) ? scriptSection : inView;
  const script = scripts.find((q) => q.section === section) || scripts[0];
  const title = (id) => {
    if (!id) return scripts.length > 1 ? "Film" : "Script";
    const seq = (model.sequences || []).find((q) => q.id === id);
    return seq ? seq.title : "Script";
  };
  const head = scripts.length > 1
    ? `<select data-script>${scripts.map((q) =>
        `<option value="${esc(q.section)}"${q.section === script.section ? " selected" : ""}>${esc(title(q.section))}</option>`).join("")}</select>`
    : `<span>${esc(title(script.section))}</span>`;
  if (!script.text) return `<div class="panelhead">${head}</div><div class="panelbody"><p class="empty">No script</p></div>`;
  return `<div class="panelhead">${head}</div>
    <div class="sheet av">${quotedScript(script)}</div>`;
}

/**
 * The script's text with every quoted stretch marked. Ranges are UTF-16
 * offsets — the engine's, and JavaScript's — so they index the string as is.
 * Cut at every boundary, count how many stretches cover each piece, and mark
 * the covered ones; the shot numbers ride the piece as its title.
 */
function quotedScript(script) {
  const text = script.text;
  const quotes = [];
  for (const g of model.groups || []) {
    for (const row of g.rows || []) {
      if ((row.scriptOf || "") !== (script.section || "")) continue;
      for (const [a, b] of spansOf(row)) {
        const from = Math.max(0, Math.min(a, text.length));
        const to = Math.max(from, Math.min(b, text.length));
        if (to > from) quotes.push({ from, to, number: row.number, scene: g.key });
      }
    }
  }
  // **An AV script is a table** (2026-09-30): Video beside Audio, a row to
  // a row. The engine keeps it as one text with a mark between a row's two
  // cells and another between rows, so each cell is a range of that text
  // and quotes mark it exactly as they mark a plain script.
  if (!text.includes(AV_CELL)) return quotedRange(text, quotes, 0, text.length);
  let html = `<table class="avgrid"><thead><tr><th>Video</th><th>Audio</th></tr></thead><tbody><tr>`;
  let start = 0;
  for (let i = 0; i <= text.length; i++) {
    const c = text[i];
    if (i < text.length && c !== AV_CELL && c !== AV_ROW) continue;
    html += `<td>${quotedRange(text, quotes, start, i)}</td>`;
    if (c === AV_ROW) html += `</tr><tr>`;
    start = i + 1;
  }
  return html + `</tr></tbody></table>`;
}

const AV_CELL = "\u001d";
const AV_ROW = "\u001e";

/** The stretch `lo`–`hi` of a script, its quoted pieces marked. */
function quotedRange(text, quotes, lo, hi) {
  const inside = quotes.filter((q) => q.to > lo && q.from < hi);
  if (!inside.length) return esc(text.slice(lo, hi));
  const clip = (n) => Math.max(lo, Math.min(n, hi));
  const cuts = [...new Set([lo, hi, ...inside.flatMap((q) => [clip(q.from), clip(q.to)])])].sort((a, b) => a - b);
  let out = "";
  for (let i = 0; i + 1 < cuts.length; i++) {
    const [a, b] = [cuts[i], cuts[i + 1]];
    const over = inside.filter((q) => q.from <= a && q.to >= b);
    const piece = esc(text.slice(a, b));
    if (!over.length) { out += piece; continue; }
    const said = over.map((q) => q.number).join(", ");
    // The number at the head of each stretch, once — the Mac lights the
    // followed shot's stretch instead, and the page has no followed shot.
    // A stretch carried on from the cell before is headed again.
    const starting = over.filter((q) => q.from === a || (a === lo && q.from < lo))
      .map((q) => `<span class="qn">${esc(q.number)}</span>`).join("");
    out += `<mark class="q${over.length > 1 ? " q2" : ""}" data-quote="${esc(over[0].scene)}" title="${esc(said)}">${starting}${piece}</mark>`;
  }
  return out;
}

function notesPane(s) {
  if (!s.notes) return `<div class="panelbody"><p class="empty">No notes</p></div>`;
  return `<div class="panelhead"><span>Scene ${esc(s.number)}</span></div>
    <div class="panelbody"><p class="said">${esc(s.notes)}</p></div>`;
}

/**
 * References: what is pinned to this scene, and then every board it is linked
 * to, each under its own heading.
 *
 * **Headings only when there is more than one source** — the same rule the Mac
 * uses, and for the same reason: a single heading over a single wall is a word
 * that tells you nothing.
 */
function referencesPane(s) {
  const boards = (model.boards || []).filter((b) =>
    String(s.boardIds || "").split(/[\s,]+/).filter(Boolean).includes(b.id) ||
    (b.scenes || []).includes(s.id)
  );
  const mine = s.attachments || [];
  const sources = (mine.length ? 1 : 0) + boards.length;
  if (!sources) return `<div class="panelbody"><p class="empty">Nothing attached</p></div>`;

  let out = "";
  if (mine.length) {
    out += sources > 1 ? `<div class="panelhead"><span>This scene</span></div>` : "";
    out += `<div class="wall">${mine.map((m) => `<span class="tile" data-look="scene:${esc(s.id)}">${picture(m)}</span>`).join("")}</div>`;
  }
  for (const board of boards) {
    out += sources > 1
      ? `<div class="panelhead"><span>${esc(board.name)}</span><div class="spacer"></div><span>${(board.media || []).length}</span></div>`
      : "";
    out += `<div class="wall">${(board.media || []).map((m) => `<span class="tile" data-look="board:${esc(board.id)}">${picture(m)}</span>`).join("")}</div>`;
  }
  return out;
}

// ----------------------------------------------------------------- locations

/**
 * How many scenes are at a place, counting the ones in its rooms.
 *
 * `scenesInside` is **a number**, and `scenes` is a list of ids. Reading the
 * first as a list put "undefined scenes" on his Mansion the first time this
 * screen drew.
 */
function sceneCount(p) {
  if (typeof p.scenesInside === "number") return p.scenesInside;
  return (p.scenes || []).length;
}

/**
 * Locations and boards are **master and detail in the app**, not a stack of
 * cards: a list down the side with its own search at the foot, the thing you
 * picked in the middle, and — for a location — its address, notes and scans in
 * a panel on the right. Drawn from photographs of the app rather than guessed.
 */
/**
 * The places, tops with their areas indented under them.
 *
 * **Pulled out of `locationsMode` so the rail and the page cannot disagree.**
 * The list is drawn twice now — once in the well and once as the master column
 * this mode has always had — and two copies of the same loop is how they would
 * come to differ over what counts as a scene at a place.
 */
function placeRows() {
  const all = model.locations || [];
  const byId = new Map(all.map((l) => [l.id, l]));
  const rows = [];
  for (const top of all.filter((l) => !l.parent)) {
    rows.push({ id: top.id, name: top.name, count: sceneCount(top), deep: false });
    for (const id of top.areas || []) {
      const area = byId.get(id);
      if (area) rows.push({ id: area.id, name: area.name, count: sceneCount(area), deep: true });
    }
  }
  return rows;
}

/** The boards, and which one is being looked at. */
function boardRows() {
  return (model.boards || []).map((b) => ({ id: b.id, name: b.name, count: (b.media || []).length, deep: false }));
}
function boardChosen() {
  const boards = model.boards || [];
  const one = boards.find((b) => b.id === board) || boards[0] || null;
  return one ? one.id : null;
}

/* ---------------------------------------------------------------- diagrams */

/**
 * **The Diagram lives in its own file** — `diagram.js`, the Mac's Diagram mode
 * in a browser (his goal, 2026-09-29). This page hands it what it needs to
 * know about the film and draws it where the mode says; everything it does
 * with a plan is its own.
 */
let diagram = null;

async function loadDiagram() {
  try {
    // The same build as this file, so a new portal never runs an old half.
    const at = new URL("./diagram.js", import.meta.url);
    at.search = new URL(import.meta.url).search;
    const { startDiagram } = await import(at.href);
    diagram = startDiagram({
      root, HUB, esc, many, listbar, mediaTag, named, mark, put, take,
      wasm: () => wasm,
      model: () => model || {},
      seen: () => seen,
      narrow: () => narrow,
      mode: () => mode,
      plan: () => plan,
      // A loose plan just made on this page: the film asked again, so the
      // list carries it, and the plan picked (`diagram.js` `newPlan`).
      pickPlan: (id) => { if (diagram) diagram.chose(); plan = id; planCam = null; planBeat = 1; relook(); },
      relook: () => relook(),
      beat: () => planBeat,
      setBeat: (n) => { planBeat = n; },
      draw: () => draw(),
      // `held`: whether the page is mid-gesture by the time the film is in
      // hand — a drag begun while it was being read. Then the page is not
      // drawn again under the hand (that lost the drag), and says so.
      reread: async (held) => { await read(); if (held && held()) return false; draw(); return true; },
      showShot: (shotId) => showShot(shotId),
      takeShot: () => { const s = planShot; planShot = null; return s; },
      // A frame as a still: a clip by its poster, a picture by itself.
      stillOf: (m) => (m && m.hash ? mediaSrc(m, m.kind === "video" || /\.(mp4|mov|m4v|gif)$/i.test(m.filename || "") ? POSTER : extensionOf(m)) : ""),
      roomText: (hash) => roomText(hash),
    });
  } catch (error) {
    diagram = null;
    console.error("the Diagram would not load", error);
  }
}

function diagramRows() {
  return diagram ? diagram.rows() : [];
}

function planChosen() {
  return diagram ? diagram.chosen() : null;
}

function diagramsMode() {
  if (!diagram) return `${listbar("")}<div class="body"><div class="well"><div class="sheetwrap"><p class="empty">Opening the diagram</p></div></div></div>`;
  return diagram.mode();
}

function wirePlan() {
  if (diagram) diagram.wire();
}

/** From a camera on the plan to its shot in the Shot List. */
function showShot(shotId) {
  let sceneId = null;
  for (const g of model.groups || []) for (const r of g.rows || []) if (r.shot === shotId) sceneId = r.sceneId;
  mode = "shots";
  keepAddress();
  draw();
  if (sceneId) requestAnimationFrame(() => goToScene(sceneId));
}

function locationsMode() {
  const all = (model.locations || []);
  const tops = all.filter((l) => !l.parent);
  const byId = new Map(all.map((l) => [l.id, l]));
  const chosen = byId.get(place) || tops[0] || null;
  const rows = placeRows();

  // **On a phone the panel is not a panel.** A 290px column beside a 375px
  // screen is a second page nobody can see, so it comes apart and lands in the
  // page in **his own order for a place, set 2026-08-22 and kept by the iPhone
  // app**: name, address, pictures, scans, notes. The address is what somebody
  // standing on a pavement opened this for; it does not belong under eighteen
  // photographs.
  const detail = chosen
    ? placeDetail(chosen, byId, narrow ? placeFacts(chosen, "address") : "")
    : `<div class="sheetwrap"><p class="empty">No locations yet</p></div>`;
  return `${listbar(many(all.length, "location"))}
  <div class="body">
    <div class="well">${detail}${narrow && chosen ? placeFacts(chosen, "rest") : ""}</div>
    ${!narrow && sidebar && chosen ? placeFacts(chosen) : ""}
  </div>`;
}

/**
 * **A room is inside a house, and the page has to say so.**
 *
 * His report, 2026-09-10: *"the web app doesnt distinguish that areas are
 * inside of locations. right now it displays them as equal things."* It did
 * not: every place drew the same way and the rail listed them in one flat
 * column. Three things say it now, and they are the same three the Mac says —
 * the list indents a room under its house, a room names the house above its
 * own name, and a house lists the rooms in it by name rather than counting
 * them.
 *
 * **The house above the name is a way back up**, not a caption. It is the only
 * route from a room to its house on a phone, where the list is a sheet.
 */
function placeDetail(p, byId, under) {
  const areas = (p.areas || []).map((id) => byId.get(id)).filter(Boolean);
  const media = p.media || [];
  const house = p.parent ? byId.get(p.parent) : null;
  return `<div class="detail">
    <div class="detailhead">
      ${house ? `<button class="upto" data-goto="${esc(house.id)}">${esc(house.name)}</button>` : ""}
      <h1>${esc(p.name)}</h1>
      <div class="detailchips">
        <span class="bandchip">${sceneCount(p)} ${sceneCount(p) === 1 ? "scene" : "scenes"}</span>
      </div>
      ${areas.length ? `<div class="rooms">${areas.map((a) => `<button class="room" data-goto="${esc(a.id)}">
          <span class="hd">${esc(a.name)}</span>
        </button>`).join("")}</div>` : ""}
      ${under || ""}
    </div>
    ${media.length
      ? `<div class="wall big">${media.map((m) => `<span class="tile" data-look="place:${esc(p.id)}" style="aspect-ratio:${ratio()}">${mediaTag(m)}</span>`).join("")}</div>`
      : `<p class="empty" style="padding:0 18px">No photographs</p>`}
  </div>`;
}

/**
 * The panel the app keeps on the right of a location.
 *
 * `part` is how a phone takes it apart: `"address"` goes under the name and
 * `"rest"` under the photographs, which is the order the iPhone app draws a
 * place in. With no `part` it is the whole panel, which is the Mac's.
 */
function placeFacts(p, part) {
  const map = p.effectiveLatitude && p.effectiveLongitude
    ? `https://maps.apple.com/?ll=${encodeURIComponent(p.effectiveLatitude)},${encodeURIComponent(p.effectiveLongitude)}`
    : null;
  // **A room has no address of its own — it is at its house's**, which is the
  // whole of Ref 269 and why the Mac shuts the door that would write one. The
  // web drew the borrowed address as though the room owned it, which is the
  // same flattening he reported in the list.
  const borrowed = p.parent && !p.address && p.effectiveAddress;
  const house = borrowed ? (model.locations || []).find((l) => l.id === p.parent) : null;
  const address = `<div class="fact">
      <div class="factname">Address</div>
      ${!p.effectiveAddress ? `<p class="empty">No address</p>`
        : map ? `<a class="said maplink" href="${map}" target="_blank" rel="noreferrer" title="Open in Maps">${esc(p.effectiveAddress)}${open_ext()}</a>`
        : `<p class="said">${esc(p.effectiveAddress)}</p>`}
      ${house ? `<p class="whose">${esc(house.name)}</p>` : ""}
    </div>`;
  const notes = `<div class="fact">
      <div class="factname">Notes</div>
      ${p.effectiveNotes ? `<p class="said">${esc(p.effectiveNotes)}</p>` : `<p class="empty">No notes</p>`}
    </div>`;
  const scans = `<div class="fact">
      <div class="factname">3D Scans</div>
      ${scanRows(p)}
    </div>`;
  // **Scans before notes when it is a phone, notes before scans when it is a
  // Mac.** Not an inconsistency: the phone's order is his, set for the iPhone
  // app on 2026-08-22, and the panel on the right is the Mac's own and is left
  // exactly as it was.
  return `<div class="facts${part ? ` ${part}` : ""}">${
    part === "address" ? address : part === "rest" ? scans + notes : address + notes + scans
  }</div>`;
}

/**
 * **The rooms he scanned, on the location that was scanned.**
 *
 * This said "Nothing scanned" and always would have: a scan was two files in
 * the project folder and nothing outside a Mac holding that folder knew they
 * were there. They are files the document knows about now, so they arrive here
 * the same way a photograph does.
 *
 * **The plan is not drawn from this markup.** A room is measurements, and the
 * measurements are a file — so the row is laid out with the room's own name and
 * an empty frame, and `layPlan` fetches the file and asks the engine what shape
 * it is. `drawPlans` is the pass, beside `drawMarks`.
 */
function scanRows(p) {
  const scans = p.scans || [];
  if (!scans.length) return `<p class="empty">Nothing scanned</p>`;
  // The pop-out is over the whole screen, so the place the room is in has to
  // travel with it — `RoomScan_2026-08-27T130801` alone says which minute the
  // scan was taken and nothing about which house it is in.
  const here = p.name;
  return scans.map((scan) => {
    // **Either half may be missing and it is still a room.** Without
    // measurements there is no plan and nothing can be read off; without the
    // shape there is nothing to turn over. Saying which is missing is the
    // difference between a plan that failed and one that was never possible,
    // and the Mac has said so since the day scans existed.
    const frame = scan.plan
      ? `<div class="planbox"></div><div class="scansaid"></div><div class="scanparts"></div>`
      : `<p class="empty">Measurements missing</p>`;
    // **The file, and the numbers.** His ask, 2026-09-09: the main thing is
    // that the room can be taken away, and beside it a way to read the
    // measurements off and copy one down. Both are here rather than in the
    // pop-out alone, because the panel is what somebody sees first.
    // The button carries the whole room with it — the measurements to draw, the
    // name to head it with, and the file to hand over. Nothing has to be looked
    // up again from whichever place happens to be chosen when it is pressed.
    const buttons = [
      scan.shape ? scanTake(scan) : "",
      scan.plan
        ? `<button class="btn" data-sizes="${esc(scan.plan.hash.slice(0, 32))}"
            data-name="${esc(scan.name)}"
            data-place="${esc(here)}"
            data-file="${scan.shape ? esc(scanFile(scan)) : ""}"
            data-shape="${scan.shape ? esc(mediaSrc(scan.shape, extensionOf(scan.shape))) : ""}">Dimensions</button>`
        : "",
      scan.plan ? `<button class="btn" data-measure="1" title="Press two points on the plan to read the distance between them">Measure</button>` : "",
    ].filter(Boolean).join("");
    return `<div class="scan"${scan.plan ? ` data-plan="${esc(scan.plan.hash.slice(0, 32))}"` : ""}>
      <div class="scanname">${esc(scan.name)}</div>
      ${scan.taken ? `<div class="scantaken">${esc(scan.taken)}</div>` : ""}
      ${frame}
      ${buttons ? `<div class="scanacts">${buttons}</div>` : ""}
    </div>`;
  }).join("");
}

/**
 * **Take the room away.** A `.usdz` is what every Mac and every iPhone opens
 * without being given anything, so the file itself is the useful thing to hand
 * somebody — and it goes out under the name the phone gave it rather than the
 * fingerprint it is stored under, which is a name nobody can read.
 */
function scanTake(scan) {
  return `<a class="btn" href="${mediaSrc(scan.shape, extensionOf(scan.shape))}" download="${esc(scanFile(scan))}">Download</a>`;
}

/** What the room is called once it is off the portal and on somebody's desk. */
function scanFile(scan) {
  return String(scan.shape.filename || `${scan.name}.usdz`).replace(/[\/\\]/g, "-");
}

/**
 * Every scan on the page that has not been drawn yet.
 *
 * Called from `wire`, beside `drawMarks`, for the same reason: what is drawn
 * depends on a file, and a file is not here when the markup is written.
 */
function drawPlans() {
  for (const box of root.querySelectorAll(".scan[data-plan]")) {
    if (box.dataset.drawn) continue;
    box.dataset.drawn = "1";
    wireMeasure(box, box.querySelector("[data-measure]"));
    layPlan(box, box.dataset.plan);
  }
}

/**
 * One room: fetched once, then drawn by the engine.
 *
 * **Kept by hash**, because the same room is drawn again every time he clicks
 * between two locations, and the answer cannot change — the file is named after
 * its own contents.
 *
 * A room that comes back `{}` is a scan with nothing in it. Those are real: an
 * aborted scan writes a file the same way a finished one does, and three of the
 * seven on his own film are that. It says so rather than drawing an empty box.
 */
const ROOMS = new Map();
const PLANS = new Map();

/** The measurements as the phone wrote them. Fetched once per room, ever. */
async function roomText(hash) {
  if (!ROOMS.has(hash)) {
    let text = null;
    try {
      const got = await fetch(`/f/${HUB.project}/media/${hash}.json`, { headers: { accept: "*/*" } });
      if (got.ok) text = await got.text();
    } catch {
      text = null;
    }
    ROOMS.set(hash, text);
  }
  return ROOMS.get(hash);
}

/**
 * The same room, drawn at whatever size is asked for.
 *
 * **A plan is drawn to fit its frame**, so the panel's 520×360 and the
 * pop-out's square are two different drawings of one room — and the room
 * itself is fetched only the once. The measurements beside them are identical
 * either way; only the SVG differs.
 */
async function roomAt(hash, w, h) {
  const key = `${hash}|${w}x${h}`;
  if (!PLANS.has(key)) {
    const text = await roomText(hash);
    PLANS.set(key, text ? roomFrom(text, w, h) : null);
  }
  return PLANS.get(key);
}

async function layPlan(box, hash) {
  const room = await roomAt(hash, 520, 360);
  if (!box.isConnected) return;
  const frame = box.querySelector(".planbox");
  if (!frame) return;
  if (!room) {
    frame.outerHTML = `<p class="empty">Nothing measured</p>`;
    box.querySelector(".scansaid")?.remove();
    box.querySelector(".scanparts")?.remove();
    return;
  }
  frame.innerHTML = room.svg;
  const said = box.querySelector(".scansaid");
  if (said) {
    said.textContent = `${room.across} × ${room.deep}`
      + (room.ceiling ? ` · ${room.ceiling} ceiling${room.ceilingVaries ? ", varies" : ""}` : "");
  }
  const parts = box.querySelector(".scanparts");
  if (parts) {
    parts.textContent = [
      many(room.walls, "wall"),
      room.doors ? many(room.doors, "door") : "",
      room.windows ? many(room.windows, "window") : "",
    ].filter(Boolean).join(" · ");
  }
}

/**
 * **The room, opened up.** His ask, 2026-09-09: *"they can also open up and see
 * the dimensions of the room in a little pop-up window and copy any dimension
 * they would need down."*
 *
 * The plan big enough to read, every measurement beside it, and each one a
 * button that copies itself. **Pointing at a row lights that wall up on the
 * plan** — a list of twenty-eight numbered walls with no way to tell which is
 * which is a list of numbers, not measurements.
 *
 * The measurements are not written here: the shell goes out with the room's
 * name and its two file buttons, and `fillRoom` asks the engine for the rest,
 * the same way `layPlan` fills the panel. A drawing depends on a file, and the
 * file is not here when the markup is written.
 */
function roomBox() {
  if (!openRoom) return "";
  // **There is no "Open in 3D" here any more.** It pointed at the same file as
  // Download and, in a browser, did the same thing — his report, 2026-09-10:
  // *"downlowad and view in 3d both download the same thing"*. A second button
  // that is the first button is worse than one button. It comes back only if
  // something actually opens the room in the page.
  const files = openRoom.shape
    ? `<div class="popfiles">
        <a class="btn light" href="${esc(openRoom.shape)}" download="${esc(openRoom.file)}">Download</a>
      </div>`
    : "";
  return `<div class="popout roomout" data-shut="1">
    <div class="popbar" data-stop="1">
      <span class="poptitle">${esc(openRoom.place || openRoom.name)}</span>
      ${openRoom.place ? `<span class="lab">${esc(openRoom.name)}</span>` : ""}
      <div class="spacer"></div>
      <button class="btn light" data-measure="1" title="Press two points on the plan to read the distance between them">Measure</button>
      ${files}
      <button class="icon" data-shut="1" title="Close">${mark("close")}</button>
    </div>
    <div class="roomstage" data-stop="1" data-fill="${esc(openRoom.hash)}">
      <div class="roomplan"></div>
      <div class="roomsizes"><p class="empty">Reading the room…</p></div>
    </div>
  </div>`;
}

/** The room in the pop-out, once the engine has answered about it. */
async function fillRoom() {
  const stage = root.querySelector(".roomstage[data-fill]");
  if (!stage || stage.dataset.drawn) return;
  stage.dataset.drawn = "1";
  wireMeasure(stage, root.querySelector(".roomout [data-measure]"));
  const room = await roomAt(stage.dataset.fill, 760, 760);
  if (!stage.isConnected) return;
  if (!room) {
    stage.innerHTML = `<p class="empty">Nothing measured</p>`;
    return;
  }
  stage.querySelector(".roomplan").innerHTML = room.svg;
  stage.querySelector(".roomsizes").innerHTML = roomSizes(room);
  stage.querySelectorAll("[data-copy]").forEach(copiesIt);
  stage.querySelectorAll(".sizerow[data-part]").forEach(litsUpThePlan);
}

/** Every measurement of a room, grouped, each one its own button. */
function roomSizes(room) {
  const parts = room.parts || [];
  const groups = [
    ["wall", "Walls"], ["door", "Doors"], ["window", "Windows"], ["opening", "Openings"],
  ];
  // **The ceiling is one number only when the walls agree.** They did not on
  // his own kitchen — 7 ft 11 in at one end and 16 ft 8 in at the other — and a
  // single number there is a lie the panel already refuses to tell.
  const ceiling = [
    room.ceiling ? size("Ceiling", room.ceiling) : "",
    room.ceilingVaries ? size("Lowest", room.ceilingLow) : "",
    room.ceilingVaries ? size("Highest", room.ceilingHigh) : "",
  ].filter(Boolean).join("");
  let out = `<div class="sizehead"><span>Room</span></div>
    ${size("Width", room.across)}${size("Depth", room.deep)}${ceiling}`;
  for (const [kind, name] of groups) {
    const mine = parts.filter((one) => one.kind === kind);
    if (!mine.length) continue;
    out += `<div class="sizehead"><span>${name}</span><span class="count">${mine.length}</span></div>
      <div class="sizerow cols"><span class="sizename"></span><span class="sizecol">Length</span><span class="sizecol">Height</span></div>`;
    out += mine.map((one) => `<div class="sizerow" data-part="${esc(one.id)}">
      <span class="sizename">${esc(one.label)}</span>
      <button class="sizeval" data-copy="${esc(one.long)}">${esc(one.long)}</button>
      <button class="sizeval" data-copy="${esc(one.tall)}">${esc(one.tall)}</button>
    </div>`).join("");
  }
  out += `<div class="sizefoot"><button class="btn" data-copy="${esc(roomAsText(room))}">Copy All</button></div>`;
  return out;
}

/** One measurement on its own line: what it is, and the number, copyable. */
function size(name, value) {
  return `<div class="sizerow">
    <span class="sizename">${esc(name)}</span>
    <button class="sizeval wide" data-copy="${esc(value)}">${esc(value)}</button>
  </div>`;
}

/** The whole room as lines of text, for pasting somewhere that is not this. */
function roomAsText(room) {
  const lines = [`Width\t${room.across}`, `Depth\t${room.deep}`];
  if (room.ceiling) lines.push(`Ceiling\t${room.ceiling}`);
  if (room.ceilingVaries) lines.push(`Lowest\t${room.ceilingLow}`, `Highest\t${room.ceilingHigh}`);
  for (const one of room.parts || []) lines.push(`${one.label}\t${one.long}\t${one.tall}`);
  return lines.join("\n");
}

/**
 * **A number you press is a number you have.** `navigator.clipboard` is the
 * whole of it on a page served over https, which the portal always is; the
 * older way is kept for a browser that refuses, because a copy button that
 * silently does nothing is worse than no button.
 */
function copiesIt(button) {
  button.addEventListener("click", async (event) => {
    event.stopPropagation();
    const text = button.dataset.copy || "";
    let done = false;
    try {
      await navigator.clipboard.writeText(text);
      done = true;
    } catch {
      done = oldWayToCopy(text);
    }
    const was = button.textContent;
    button.textContent = done ? "Copied" : "Press ⌘C";
    if (done && window.feel) window.feel.toast("Copied");
    button.classList.add("said");
    setTimeout(() => {
      if (!button.isConnected) return;
      button.textContent = was;
      button.classList.remove("said");
    }, 1100);
  });
}

function oldWayToCopy(text) {
  try {
    const box = document.createElement("textarea");
    box.value = text;
    box.setAttribute("readonly", "");
    box.style.cssText = "position:fixed;top:-1000px;opacity:0";
    document.body.appendChild(box);
    box.select();
    const done = document.execCommand("copy");
    box.remove();
    return done;
  } catch {
    return false;
  }
}

/** Point at a row and the wall it measures lights up on the plan. */
function litsUpThePlan(row) {
  const lit = (on) => {
    const shape = root.querySelector(`.roomplan [data-part="${row.dataset.part}"]`);
    if (shape) shape.classList.toggle("lit", on);
    row.classList.toggle("on", on);
  };
  row.addEventListener("mouseenter", () => lit(true));
  row.addEventListener("mouseleave", () => lit(false));
  // A finger has no hover. Touching a row picks it out and leaves it picked
  // until another one is — which is also how it works with a mouse held still.
  row.addEventListener("click", () => {
    root.querySelectorAll(".roomplan .lit").forEach((one) => one.classList.remove("lit"));
    root.querySelectorAll(".sizerow.on").forEach((one) => one.classList.remove("on"));
    lit(true);
  });
}

/**
 * **A measure tool on a scanned room, for anybody who can see it.** His ask,
 * 2026-10-11: a measure tool should always be there, in the Diagrams and on a
 * location's scan. It changes nothing in the film, so a viewer and a link
 * holder have it the same as an editor: Measure, press one point and then
 * another on the plan, and the distance is written on the line — in feet and
 * inches and in metres. A third press starts a new one; Esc, or Measure
 * again, puts it away.
 *
 * **The scale comes from the engine's own drawing** (`data-scale` on the plan:
 * drawing units to a metre), so this holds no second opinion about how big the
 * room is. A press near a wall's or an opening's corner is held to it, because
 * that is almost always what is being measured.
 *
 * `host` is whatever holds the plan (the panel's scan, or the pop-out's stage);
 * `button` is its Measure button, which may sit outside it.
 */
function wireMeasure(host, button) {
  if (!host || !button || host.dataset.measure) return;
  host.dataset.measure = "1";
  const NS = "http://www.w3.org/2000/svg";
  let on = false, pts = [], hover = null;
  const plan = () => host.querySelector("svg.plan");
  const unitsPer = () => { const p = plan(); return p ? Number(p.dataset.scale) || 0 : 0; };
  /** Pixels on the screen per drawing unit, so a mark is the same size at any zoom. */
  const ratio = () => { const p = plan(); const vb = p && p.viewBox && p.viewBox.baseVal; return p && vb && vb.width ? p.getBoundingClientRect().width / vb.width : 1; };
  const where = (ev) => {
    const p = plan(); const m = p && p.getScreenCTM();
    if (!m) return null;
    const q = new DOMPoint(ev.clientX, ev.clientY).matrixTransform(m.inverse());
    const at = [q.x, q.y];
    if (ev.altKey) return at;
    let best = null, near = 9 / ratio();
    for (const poly of p.querySelectorAll("polygon.pl-wall, polygon.pl-hole")) {
      for (const pair of String(poly.getAttribute("points") || "").trim().split(/\s+/)) {
        const c = pair.split(",").map(Number);
        const d = Math.hypot(c[0] - at[0], c[1] - at[1]);
        if (d < near) { near = d; best = c; }
      }
    }
    return best || at;
  };
  const feet = (m) => {
    const inches = Math.round(m * 39.3701);
    const ft = Math.floor(inches / 12), inch = inches % 12;
    return ft ? (inch ? `${ft} ft ${inch} in` : `${ft} ft`) : `${inch} in`;
  };
  const say = (a, b) => {
    const m = Math.hypot(a[0] - b[0], a[1] - b[1]) / unitsPer();
    return `${feet(m)} · ${(Math.round(m * 100) / 100).toFixed(2)} m`;
  };
  function draw() {
    const p = plan();
    if (!p) return;
    p.querySelector(".pl-measure")?.remove();
    const a = pts[0], b = pts[1] || hover;
    if (!a) return;
    const k = ratio();
    const g = document.createElementNS(NS, "g");
    g.setAttribute("class", "pl-measure");
    g.setAttribute("pointer-events", "none");
    const add = (tag, attrs) => { const n = document.createElementNS(NS, tag); for (const [x, v] of Object.entries(attrs)) n.setAttribute(x, v); g.append(n); return n; };
    if (b && unitsPer()) {
      add("line", { class: "pl-mline", x1: a[0], y1: a[1], x2: b[0], y2: b[1], "stroke-width": 2 / k });
      const label = add("text", { class: "pl-mtext", x: (a[0] + b[0]) / 2, y: (a[1] + b[1]) / 2 - 9 / k, "text-anchor": "middle", "font-size": 12.5 / k, "stroke-width": 4 / k });
      label.textContent = say(a, b);
    }
    for (const c of [a, pts[1]].filter(Boolean)) add("circle", { class: "pl-mdot", cx: c[0], cy: c[1], r: 4.5 / k, "stroke-width": 1.5 / k });
    p.append(g);
  }
  function set(next) {
    on = next;
    pts = []; hover = null;
    host.classList.toggle("measuring", on);
    button.classList.toggle("on", on);
    button.textContent = on ? "Done measuring" : "Measure";
    draw();
    if (on && window.feel) window.feel.toast("Press two points to measure · Esc to finish");
  }
  button.addEventListener("click", (event) => { event.stopPropagation(); set(!on); });
  host.addEventListener("click", (event) => {
    if (!on || !event.target.closest || !event.target.closest("svg.plan")) return;
    const at = where(event);
    if (!at) return;
    if (pts.length !== 1) pts = [at]; else pts = [pts[0], at];
    hover = null;
    draw();
  });
  host.addEventListener("pointermove", (event) => {
    if (!on || pts.length !== 1 || !event.target.closest || !event.target.closest("svg.plan")) return;
    hover = where(event);
    draw();
  });
  document.addEventListener("keydown", (event) => {
    if (!on || event.key !== "Escape" || !host.isConnected) return;
    event.stopPropagation();
    if (pts.length) { pts = []; hover = null; draw(); } else set(false);
  }, true);
}

/** Ask the engine what shape a room is. Null for anything it cannot read. */
function roomFrom(text, w, h) {
  if (!wasm) return null;
  const [pointer, length] = put(text);
  const out = take(wasm.scan_plan(pointer, length, w, h));
  wasm.dealloc(pointer, length);
  try {
    const room = JSON.parse(out);
    return room && room.svg ? room : null;
  } catch {
    return null;
  }
}

// -------------------------------------------------------------------- boards

function boardsMode() {
  const boards = model.boards || [];
  const chosen = boards.find((b) => b.id === board) || boards[0] || null;
  const rows = boardRows();
  return `${listbar(many(boards.length, "board"))}
  <div class="body">
    <div class="well">${chosen ? boardDetail(chosen) : `<div class="sheetwrap"><p class="empty">No boards yet</p></div>`}</div>
  </div>`;
}

function boardDetail(b) {
  const media = b.media || [];
  const scenes = (b.scenes || []).length;
  return `<div class="detail">
    <div class="detailhead">
      <h1>${esc(b.name)} <span class="pictures">${media.length} ${media.length === 1 ? "picture" : "pictures"}</span></h1>
      ${scenes ? `<div class="detailchips"><span class="bandchip">${scenes} ${scenes === 1 ? "scene" : "scenes"}</span></div>` : ""}
    </div>
    ${media.length
      ? `<div class="wall big">${media.map((m) => `<span class="tile" data-look="board:${esc(b.id)}" style="aspect-ratio:${ratio()}">${mediaTag(m)}</span>`).join("")}</div>`
      : `<p class="empty" style="padding:0 18px">Nothing on it</p>`}
  </div>`;
}

/**
 * The list down the side, in the app's shape: a title, the rows with their
 * counts, and a search pinned at the foot.
 *
 * **This search filters names here rather than asking the engine.** The
 * engine's search is about shots and scenes; "which of my locations is called
 * something like this" is a different question and a list filter answers it.
 */
function listSide(title, placeholder, rows, chosenId, what) {
  const want = listFind.trim().toLowerCase();
  const shown = want ? rows.filter((r) => r.name.toLowerCase().includes(want)) : rows;
  return `<div class="sidebar">
    <div class="side-h"><span class="sidetitle">${esc(title)}</span><div class="spacer"></div><span class="count">${rows.length}</span></div>
    <div class="scenelist">
      ${shown.length ? shown.map((r) => `<button class="scene-row ${r.deep ? "deep" : ""} ${chosenId === r.id ? "on" : ""}" data-pick="${esc(what)}" data-id="${esc(r.id)}">
          <span class="slug">${esc(r.name)}</span><span class="count">${r.count}</span>
        </button>`).join("") : `<p class="empty" style="padding:8px 14px">Nothing matches</p>`}
    </div>
    <div class="sidefoot">
      <input class="find" id="listfind" type="search" placeholder="${esc(placeholder)}" value="${esc(listFind)}">
    </div>
  </div>`;
}

// ------------------------------------------------------------------ schedule

/**
 * Days as lanes, and what is not on one underneath.
 *
 * A scene knows its day by *label* in the description, which is how the Mac
 * draws it too — the day's own record carries a count of nought here, so
 * matching on the label is the honest read rather than the lazy one.
 */
function scheduleMode() {
  const days = model.days || [];
  const scenes = (model.scenes || []).filter((s) => !setAside(s));
  // **A day's scenes in the order the board arranged them**, not script
  // order — his finding, 2026-09-20 (Ref 1137). The engine's day groups
  // carry each day's placements in that order; the scenes are read off them
  // in order of first appearance, and a scene the groups do not name (no
  // shots yet) keeps its script-order place at the end.
  const arranged = wasm ? JSON.parse(describe({ ...asking, groupBy: "day", facets: [], search: "" })) : null;
  const orderOn = new Map();
  for (const g of (arranged && arranged.groups) || []) {
    const seen = [];
    for (const row of g.rows || []) if (row.sceneId && !seen.includes(row.sceneId)) seen.push(row.sceneId);
    orderOn.set(g.key, seen);
  }
  const inBoardOrder = (day, on) => {
    const order = orderOn.get(day.id) || [];
    const at = (id) => { const i = order.indexOf(id); return i < 0 ? order.length : i; };
    return on.slice().sort((a, b) => at(a.id) - at(b.id));
  };
  // **This shoot's days** (SL-1396), and only its own unscheduled scenes.
  const lanes = days.filter(dayInShoot).map((day) => ({ day, on: inBoardOrder(day, scenes.filter((s) => s.day === day.label && inShoot(s.id))) }));
  const loose = scenes.filter((s) => !s.day && inShoot(s.id));
  // **Each day's shots in the order they are shot** — the same day groups,
  // row by row. `whole` is every shot on the day, shown or not, so a drop
  // can be said as a place in the day itself.
  const runOn = new Map();
  for (const g of (arranged && arranged.groups) || []) {
    const rows = (g.rows || []).filter((r) => r.number);
    runOn.set(g.key, {
      whole: rows.map((r) => r.number),
      shown: rows.filter((r) => inShoot(r.sceneId) && !setAside((model.scenes || []).find((x) => x.id === r.sceneId) || {})),
    });
  }
  const moves = shootOrder && HUB.role === "editor" && !!wasm;
  const head = (day, said) => `<div class="lanehead">
        <span class="placename">${esc(day.label)}</span>
        ${day.date ? `<span class="count">${esc(niceDate(day.date))}</span>` : ""}
        ${isToday(day) ? `<span class="chip today">Today</span>` : ""}
        <div class="spacer"></div>
        <span class="count">${said}</span>
      </div>`;

  return `<div class="viewbar">${shootSeg()}<div class="seg runseg"><button data-shootorder="0" class="${shootOrder ? "" : "on"}">Scenes</button><button data-shootorder="1" class="${shootOrder ? "on" : ""}">Shooting Order</button></div><div class="spacer"></div><span class="lab">${many(lanes.length, "day")}</span></div><div class="body"><div class="well"><div class="sheetwrap"${moves ? " data-runs" : ""}>
    ${lanes.map(({ day, on }) => {
      if (!shootOrder) {
        return `<div class="lane${on.length ? "" : " bare"}">
      ${head(day, on.length ? `${on.length} ${on.length === 1 ? "scene" : "scenes"}` : "No scenes")}
      ${on.map(strip).join("")}
    </div>`;
      }
      const run = runOn.get(day.id) || { whole: [], shown: [] };
      return `<div class="lane${run.shown.length ? "" : " bare"}" data-day="${esc(day.id)}" data-label="${esc(day.label)}" data-whole="${esc(run.whole.join(","))}">
      ${head(day, run.shown.length ? many(run.shown.length, "shot") : "No shots")}
      <div class="runs">${run.shown.map((row, i) => runRow(row, i)).join("")}</div>
    </div>`;
    }).join("")}
    <div class="lane">
      <div class="lanehead"><span class="placename">Not Scheduled</span>
        <div class="spacer"></div><span class="count">${loose.length}</span></div>
      ${loose.length ? loose.map(strip).join("") : `<p class="empty">Everything has a day</p>`}
    </div>
  </div></div></div>`;
}

/**
 * **One shot in a day's running order** — Shooting Order. Its place, the
 * scene's time-of-day dot, its number, where, and what it is; crossed out
 * once it is Shot. A press does nothing; a double press opens it in the Shot
 * List; an editor drags it (`data-runs` on the sheet, see `shootDrag`).
 */
function runRow(row, i) {
  const scene = (model.scenes || []).find((x) => x.id === row.sceneId) || {};
  return `<div class="runrow${row.struck ? " struck" : ""}" data-run="${esc(row.number)}" data-runscene="${esc(row.sceneId || "")}">
    <span class="at">${i + 1}</span>
    <span class="dot" style="background:${timeInk(scene.timeOfDay)}"></span>
    <span class="no">${esc(row.number)}</span>
    <span class="where">${esc(scene.location || scene.heading || "")}</span>
    <span class="what">${esc(row.description || row.title || "")}</span>
  </div>`;
}

/**
 * One scene on a day.
 *
 * **A press picks it; a double press opens it in the Shot List** — the Mac's
 * own gestures (`onTapGesture(count: 2, perform: onInspect)` in
 * `Schedule.swift`). A single press used to leave for the Shot List, which
 * made the schedule a screen you fell out of by touching it. His report,
 * 2026-09-10: *"going into schedule is clunky because if I click on a day it
 * takes me to shot list, and I have to go back to schedule."*
 */
function strip(s) {
  return `<button class="stripe${strip_ === s.id ? " on" : ""}" data-strip="${esc(s.id)}">
    <span class="dot" style="background:${timeInk(s.timeOfDay)}"></span>
    <span class="no">${esc(s.number)}</span>
    <span class="addr">${esc(s.heading || s.location)}</span>
    <span class="count">${s.count || 0}</span>
  </button>`;
}

// ------------------------------------------------------------- scene sidebar

/**
 * The scene list, and the search that belongs to it.
 *
 * **The search sits at the foot of the sidebar**, which is where the app keeps
 * it — "Search scenes, shots, gear". It was in the views bar here, which left
 * the sidebar with nothing to do but list, and he said it felt hidden away.
 * Giving it the search gives it a job.
 */
function sceneSidebar() {
  const filter = model.filter || {};
  // **The list narrows with the search, as the app's does.** The engine already
  // says which scenes fell out of the narrowing; counting them here, or worse
  // deciding here which ones they are, is how the sidebar and the table would
  // come to disagree about the same search.
  const gone = new Set(filter.hiddenSceneIds || []);
  const scenes = (model.scenes || []).filter((s) => !setAside(s) && !gone.has(s.id) && inShoot(s.id));
  const hidden = filter.hiddenScenes || 0;
  return `<div class="sidebar">
    <div class="side-h">
      <span class="sidetitle">Scenes</span>
      <div class="spacer"></div>
      <span class="count">${scenes.length}</span>
    </div>
    <div class="scenelist">
      ${sceneRuns(scenes).map(({ section, run }) => {
        const rows = run.map((s) => `<button class="scene-row ${inView === s.id ? "on" : ""}" data-scene="${esc(s.id)}">
          <span class="dot" style="background:${timeInk(s.timeOfDay)}"></span>
          <span class="no">${esc(s.number)}</span>
          <span class="slug">${esc(s.heading || s.location)}</span>
        </button>`).join("");
        return section
          ? `<div class="secpanel" style="${sectionVars(section)}"><div class="sechead">${esc(section.title)}</div>${rows}</div>`
          : rows;
      }).join("")}
      ${hidden ? `<p class="empty" style="padding:8px 14px">${hidden} ${hidden === 1 ? "scene" : "scenes"} hidden</p>` : ""}
    </div>
    <div class="sidefoot">
      <input class="find" id="find" type="search" placeholder="Search scenes, shots, gear" value="${esc(asking.search)}">
    </div>
  </div>`;
}



/**
 * **A section's scenes sit on a panel of their own** — the Mac's sidebar,
 * here. His report, 2026-09-20: *"the colors of the sections/script are too
 * much in the side bar next to the other colors of each scene — they should
 * more be grouped in sub panels."* So the list is cut into runs: consecutive
 * scenes in the same section make one run, drawn on a lifted panel with the
 * title at its head in the section's colour (no bar — "very GEN AI", his
 * ruling 2026-09-19);
 * scenes in no section stay plain rows between the panels. A section is a
 * label on a run, not a bin, so the order of the list is never changed.
 */
function sceneRuns(scenes) {
  const runs = [];
  for (const s of scenes) {
    const section = sectionOf(s.id);
    const last = runs[runs.length - 1];
    if (last && ((!last.section && !section) || (last.section && section && last.section.id === section.id))) {
      last.run.push(s);
    } else {
      runs.push({ section, run: [s] });
    }
  }
  return runs;
}

// ------------------------------------------------------------------ filters

/**
 * **A chip is a choice, not an option.** His question, 2026-09-04: *"what if
 * there are 100+ filters? THere could be 20 shooting days alone on a feature"*.
 * A flat row of every value is five things on a short and several hundred on a
 * feature, so the row only ever holds what he has picked, and picking happens
 * in a panel that takes the well's own room — **fields first, values second**.
 * Thirty-one shoot days is then a short searchable list rather than a wall.
 *
 * The narrowing itself is the engine's: `asking.facets` is a list of
 * `[field, value]` pairs that `view.rs` turns into `scene_is` / `shot_is`, so
 * the table and the scene list cannot disagree about the same filter.
 */
let filterOpen = null;   // null | "fields" | a field name
let filterFind = "";     // searching within one field's values

/** Columns that are prose or pictures are not facets; the rest are. */
const NOT_A_FACET = new Set(["image", "struck", "title", "description", "notes", "number", "synopsis"]);

function allRows() {
  const shelved = archivedScenes();
  return (model.groups || []).filter((g) => !shelved.has(g.key)).flatMap((g) => g.rows || []);
}

/** **A scene that is both reads I/E on screen** (his ruling, 2026-10-13); the
 *  filter still asks the engine for INT/EXT. Only this label changes. */
const facetShown = (field, v) => (field === "int_ext" && String(v).toUpperCase() === "INT/EXT" ? "I/E" : v);

function facetValues(name, rows) {
  const tally = new Map();
  for (const row of rows || allRows()) {
    let v = row[name];
    if (v === undefined && row.custom) v = row.custom[name];
    for (const one of Array.isArray(v) ? v : [v]) {
      const said = named(one).trim();
      if (said) tally.set(said, (tally.get(said) || 0) + 1);
    }
  }
  // **In the order a person expects.** A plain string sort puts Day 10 before
  // Day 2; a leading number wins where there is one.
  const num = (x) => { const m = /(\d+)/.exec(x); return m ? +m[1] : NaN; };
  return [...tally].map(([v, n]) => ({ v, n })).sort((a, b) => {
    const x = num(a.v), y = num(b.v);
    if (!isNaN(x) && !isNaN(y)) return x - y;
    return a.v.localeCompare(b.v);
  });
}

/** The fields worth offering: a column with more than one value behind it. */
function facetFields() {
  const rows = allRows();
  const fields = shownColumns()
    .filter((c) => !NOT_A_FACET.has(c.name) && !isProse(c) && !isCheck(c))
    .map((c) => ({ name: c.name, label: c.label || c.name, values: facetValues(c.name, rows) }))
    .filter((c) => c.values.length > 1);
  /* **Interior/Exterior is a fact about the scene, not a column**, so it is
     offered beside the columns rather than from them. Each row carries the
     answers its scene gives (`int_ext`, from the engine): an INT/EXT scene is
     under INT, under EXT and under INT/EXT, so picking Exterior finds it. */
  const inOut = { name: "int_ext", label: "Interior/Exterior", values: facetValues("int_ext", rows) };
  return inOut.values.length > 1 ? [...fields, inOut] : fields;
}

const chosenFor = (field) => asking.facets.filter(([f]) => f === field).map(([, v]) => v);
const anyFacet = () => asking.facets.length > 0;

function facetChips() {
  if (!anyFacet()) return "";
  return `<div class="fchips">${asking.facets.map(([f, v]) =>
      `<button class="fchip" data-unfacet="${esc(f)}|${esc(v)}">${esc(facetShown(f, v))}<span class="x">${ex_mark()}</span></button>`).join("")
    }<button class="fchip clear" data-unfacet="*">Clear</button>${
      // **Share these shots on their own** (`src/views.js`) — the Share
      // panel, opened on its Views section with this filter in it.
      HUB.role === "editor" ? `<a class="fchip shareview" data-share data-tab="view" href="${esc(HUB.base || `/f/${HUB.project}`)}/share">${link_mark()}Share View</a>` : ""
    }</div>`;
}

function filterPanel() {
  if (filterOpen === "fields") {
    const fields = facetFields();
    return `<div class="panelbar"><span class="now">Filter</span>
        <button class="done" data-facet="">Done</button></div>
      <div class="panellist scrolls">
        ${fields.length ? fields.map((f) => `<button class="frow" data-facet="${esc(f.name)}">${esc(f.label)}
            <span class="fn">${f.values.length}</span><span class="chv">${chev_mark()}</span></button>`).join("")
          : `<div class="scount">Nothing to filter by yet</div>`}
      </div>`;
  }
  const field = facetFields().find((f) => f.name === filterOpen);
  if (!field) return "";
  const on = new Set(chosenFor(field.name));
  const said = filterFind.trim().toLowerCase();
  const vals = said ? field.values.filter((x) => x.v.toLowerCase().includes(said)) : field.values;
  return `<div class="panelbar">
      <button class="back" data-facet="fields"><span class="chv">${chev_mark()}</span>Filter</button>
      <span class="now">${esc(field.label)}</span>
      <button class="done" data-facet="">Done</button></div>
    <div class="scopedhead"><input class="sfield" id="facetfind" type="search"
      placeholder="Search ${esc(field.label.toLowerCase())}" value="${esc(filterFind)}"></div>
    <div class="panellist scrolls">
      ${vals.length ? vals.map((x) => `<button class="frow${on.has(x.v) ? " picked" : ""}" data-facetval="${esc(field.name)}|${esc(x.v)}">
          <span class="tick">${tick_mark()}</span>${esc(facetShown(field.name, x.v))}<span class="fn">${x.n}</span></button>`).join("")
        : `<div class="scount">Nothing matches</div>`}
    </div>`;
}

// --------------------------------------------------------------------- rail

/**
 * **The same rail the front of house draws, with this half's sections live.**
 *
 * His approval, 2026-09-04. The four mode pills and the phone tab bar are gone
 * — they were the app's own copy of a list that now exists once, on every page
 * of the portal, and two copies of one nav is what the door used to hide.
 *
 * **A section of the program is a button; a section of the record is a link.**
 * That is the only difference left between them, and it is a fact about what a
 * click costs rather than about what the thing is: the engine is already read,
 * so switching to Locations must not be a page load. The address still changes
 * underneath, so the row stays a real place somebody can bookmark or send.
 */
/* **A function, not a `const` array — and that is not style.** `paint()` runs
   at boot, long before this line does, and a `const` read before its own
   declaration is a ReferenceError rather than `undefined`: the whole app drew
   nothing and the console said *"Cannot access 'RAIL' before initialization"*.
   A function declaration hoists; the array it returns is built when asked. */
function railGroups() {
  /* **`paint` runs before the film is read**, to draw the booting screen — so
     every count here has to survive a null model rather than assume one. */
  const m = model || {};
  /* **The card's numbers until the film has been read.** The record's rail
     draws `front.counts`; this one used to draw nothing until the engine had
     the scenes, so the four rows arrived blank and filled in a beat later —
     one more way the two rails read as two. The card's count stands in, and
     the live one takes over the moment it exists. */
  const card = (HUB.rail && HUB.rail.counts) || {};
  const live = (own, key) => (model ? own() : card[key] || "");
  /* **One list, no headings** — his answer of 2026-09-08. `GROUPS` in
     `src/pages.js` is the same eight rows in the same order, because the
     record's rail and this one are meant to be one rail; change both or they
     drift apart on the way through a door. Kept as a list of groups so that
     `railRows`, the well and the mode lookup all still walk the same shape. */
  // **The names he gave pages on the portal** (`front.labels`), laid over the built-in ones.
  const L = (HUB.rail && HUB.rail.labels) || {};
  const named = (r) => (L[orderKey(r.at)] ? { ...r, name: L[orderKey(r.at)] } : r);
  return [
  { head: "", rows: [
    { at: "shots", name: "Shot List", n: () => live(() => (m.scenes || []).filter((x) => !setAside(x) && inShoot(x.id)).length, "scenes") },
    /* The script's newest draft (SL-1338) — a page of the record, read off
       the film. `unfilled` keeps it off until a draft is taken in. */
    { at: "script", name: "Script", page: true, source: "film" },
    { at: "diagrams", name: "Diagrams", n: () => live(() => (m.scenes || []).filter((x) => !x.archived && x.diagram > 0).length + (m.plans || []).filter((p) => p.diagram > 0).length, "diagrams") },
    { at: "locations", name: "Locations", n: () => live(() => (m.locations || []).length, "locations") },
    { at: "schedule", name: "Schedule", n: () => live(() => (m.days || []).filter(dayInShoot).length, "days") },
    { at: "boards", name: "Reference Images", n: () => live(() => (m.boards || []).length, "boards") },
    { at: "bible", name: "Visual Bible", page: true },
    { at: "camera", name: "Camera Spec Sheet", page: true },
    { at: "people", name: "People", page: true, n: () => (HUB.rail && HUB.rail.crew) || "" },
    { at: "documents", name: "Documents", page: true, n: () => (HUB.rail && HUB.rail.documents) || "" },
  ] },
  ].map((g) => ({ ...g, rows: g.rows.map(named) }));
}

/**
 * Every row the rail draws, under his headings.
 *
 * **His own pages join the built-in eight before the headings are laid over
 * them**, because a heading may hold any of them — that is the whole of what he
 * asked for. A section already in the rail is not added twice: a Notion section
 * named `Visual Bible` is folded onto the built-in page, the same way the
 * server folds it.
 */
/**
 * Whether this reader may not see a section — one of the four screens or a
 * page of the record.
 *
 * **The worker decides; this only repeats it.** `HUB.rail.hidden` is what the
 * film's Visibility panel hides, handed over with the page for anybody who is
 * not an editor. A row for a hidden thing says the thing exists, which is
 * exactly what he set Visibility to stop — his ruling, 2026-09-04 — and the
 * app's rail was drawing all eight rows and every page for a link holder
 * regardless. His report, 2026-09-10. Keyed the way the order is keyed, so
 * the Shot List answers to `shotlist` here as it does everywhere else.
 */
function hidden(at) {
  if (LENS && HUB.linkKey) return orderKey(at) !== orderKey("shots");
  const list = (HUB.rail && HUB.rail.hidden) || [];
  return list.includes(orderKey(at));
}

/* **An empty row is left off his rail too** (2026-09-23), except the screen
   he is on. Add's Built In table is the way to an empty one. **So is a row he
   hid For Me** (`meSees` in `films.js`) — off the rail, never refused. */
function gone(at) {
  /* **A page in the Library is off the rail too** (2026-10-02) — for
     everybody, and still open from its address. `offSidebar` in `src/front.js`
     is the same rule one door along. */
  const off = [...((HUB.rail && HUB.rail.empty) || []), ...((HUB.rail && HUB.rail.mine) || []),
    ...((HUB.rail && HUB.rail.library) || [])];
  return off.includes(orderKey(at)) && orderKey(at) !== orderKey(mode);
}

/* **The Library sits first on every rail, for everybody** (his ruling,
   2026-10-02): it holds every page and document, and the rows below are only
   the ones pinned to the sidebar. Not a row and not in a `.group`, so
   dragging the rail never files it. `libraryRow` in `src/pages.js` is the same
   row, one door along. A view link has no rail to speak of, so none there. */
function libraryRow(base) {
  if (LENS && HUB.linkKey) return "";
  const n = (HUB.rail && HUB.rail.libraryN) || "";
  return `<div class="libgroup"><a class="to librow" data-deep="record" href="${esc(base)}/library"${railName("row", "library")}>${rowIcon({ at: "library" }, 17, false)}<span class="nm">Library</span>${
    n ? `<span class="n">${esc(String(n))}</span>` : ""}</a></div>`;
}

/* **A row's icon**, by what the page is or the one he picked (`HUB.rail.icons`).
   The table is `public/icons.js`, loaded before this file; it is the same set
   as `src/icons.js`. Read at call time, never at load. */
function rowIconName(r) {
  const paths = window.ROW_ICONS || {};
  const pick = ((HUB.rail && HUB.rail.icons) || {})[orderKey(r.at)];
  if (r.doc) return (pick && paths[pick] && pick) || (r.file ? "file" : "link");
  return (pick && paths[pick] && pick) || (paths[r.at] ? r.at : paths[r.type] ? r.type : "page");
}

function rowIcon(r, size = 15, wrap = true) {
  const paths = window.ROW_ICONS || {};
  const one = `<svg viewBox="0 0 16 16" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[rowIconName(r)] || ""}</svg>`;
  return wrap ? `<span class="ico">${one}</span>` : one;
}

function railParts() {
  const built = railGroups().flatMap((g) => g.rows).filter((r) => !hidden(r.at) && !gone(r.at));
  const known = new Set(built.map((r) => r.at));
  const his = ((HUB.rail && HUB.rail.sections) || [])
    .filter((one) => !known.has(one.at) && !hidden(one.at) && !gone(one.at))
    .map((one) => ({ at: one.at, name: one.name, page: true, source: one.source, type: one.type }));
  /* **The documents he pinned** (`HUB.rail.docs`, `railDocs` in `src/pages.js`):
     each a row that opens its file or link in a new tab. */
  const docs = ((HUB.rail && HUB.rail.docs) || []).map((one) => ({ at: one.at, name: one.name, doc: true, href: one.href, file: one.file }));
  return inGroups([...built, ...his, ...docs]);
}

/** Where a record page lives, from here. */
function recordHref(at) {
  return `${HUB.base || `/f/${HUB.project}`}/${at}`;
}

/**
 * What each of the four sources is called, in words.
 *
 * **`sectionPage` in `pages.js` says the same four**, because the same four
 * rows are drawn on the record's pages by the worker and here by the app. Two
 * lists that must agree is the shape of the identity drift in `STATUS.md`, so
 * if one of these changes, change the other in the same breath.
 */
/* **A function, not a `const`, and that is the third time this file has said
   so.** `paint()` runs at boot, before any `const` further down the file has
   been initialised — reading one there is a ReferenceError, not `undefined`,
   and the whole app draws nothing but a black screen. `RAIL` did it, the two
   marks below did it, and this did it on 2026-09-08: every sidebar link went
   black the moment it shipped. A function declaration hoists. */
/**
 * **The mark on a row whose page syncs from an outside document** — a page
 * Live from Notion, or one following a Google Doc. Editors only, from
 * `HUB.rail.edit.sync` (`railEdit` in `src/pages.js`); `syncDot` there is the
 * same mark on the record's rail. A function declaration, so it hoists.
 */
function syncDot(kind) {
  if (!kind) return "";
  const said = kind === "gdoc" ? "Synced from Google Doc" : "Synced from Notion";
  return `<span class="syncico" title="${said}" aria-label="${said}"><svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.6 6.4A4.8 4.8 0 0 0 4 4.6L3 5.6"/><path d="M3 2.8v2.8h2.8"/><path d="M3.4 9.6A4.8 4.8 0 0 0 12 11.4l1-1"/><path d="M13 13.2v-2.8h-2.8"/></svg></span>`;
}

/**
 * **The key an order is stored under**, which is not always the key this half
 * calls the row.
 *
 * The program's Shot List is `shots` and the record's is `shotlist` — one row,
 * two names, because one is a mode of the app and the other is an address. The
 * order is written by the record's rail, so the record's word wins and this is
 * where the two are reconciled. Getting it wrong would put the Shot List on the
 * end for him and at the top for a director reading the same film.
 *
 * **A function, not a `const` map, for the fourth time in this file.** See the
 * note above `railGroups`.
 */
function orderKey(at) {
  return at === "shots" ? "shotlist" : at;
}

/**
 * A rail's rows, under their categories, in his own order.
 *
 * **`railGroups` in `src/front.js` is the same rule**, because the record's rail
 * is drawn by the worker and this one by the browser and neither can import the
 * other. Change one and change the other in the same breath, or the same film
 * reads two ways depending on which door you came in.
 */
function inGroups(rows) {
  const rail = HUB.rail || {};
  const place = new Map((rail.order || []).map((at, i) => [at, i]));
  const rank = (row) => (place.has(row.at) ? place.get(row.at) : place.has(orderKey(row.at)) ? place.get(orderKey(row.at)) : Infinity);
  const sorted = rows.map((row, i) => ({ row, i })).sort((a, b) => (rank(a.row) - rank(b.row)) || (a.i - b.i)).map((x) => x.row);
  const by = new Map((rail.shelves || []).map((one) => [one.id, { head: one.name, shelf: one.id, builtIn: Boolean(one.builtIn), had: 0, rows: [] }]));
  // Before the portal sent categories, a rail had no headings at all.
  if (!by.size) return [{ head: "", rows: sorted }];
  const filed = rail.filed || {};
  for (const row of sorted) {
    const id = filed[row.at] || filed[orderKey(row.at)];
    (by.get(id) || by.get("other") || [...by.values()][0]).rows.push(row);
  }
  // **A category with nothing in it is his to drop a page on and nobody
  // else's to read.** The record's rail (`railFor`) holds the same rule.
  const said = [...by.values()].filter((g) => g.rows.length || (HUB.role === "editor" && !g.builtIn));
  return said.length ? said : [{ head: "", rows: [] }];
}

/** One heading's worth of rows, drawn. `railParts` decides which they are. */
/**
 * **Every row is named for the browser, so a row that moves slides.** A mode
 * change redraws the whole rail, and the well opening under the new row used
 * to push everything beneath it down in one frame — his report, 2026-09-16.
 * Named, each row is its own thing to the view transition and travels from
 * where it was to where it is now; the well itself fades in under it. The
 * record's rail (`railFor` in `src/pages.js`) names its rows the same way, so
 * crossing the door between the two moves rows rather than replacing them.
 * A name must be one word the browser accepts, so the key is cleaned first.
 */
function railName(kind, key) {
  return ` style="view-transition-name:${kind}-${String(key).replace(/[^A-Za-z0-9_-]/g, "_")}"`;
}

function railRows(g) {
  const edit = (HUB.rail && HUB.rail.edit) || null;
  return g.rows.map((r) => {
    const n = typeof r.n === "function" ? r.n() || "" : "";
    const key0 = orderKey(r.at);
    /* **A lock beside the count, for an editor**: the page is Private. `railEdit` in `src/pages.js` decides which. */
    const off = edit && edit.off.includes(key0);
    const count = (edit ? `<span class="off-tag" title="Private"><svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.4 7.2h7.2a1.4 1.4 0 0 1 1.4 1.4v4.2a1.4 1.4 0 0 1-1.4 1.4H4.4A1.4 1.4 0 0 1 3 12.8V8.6a1.4 1.4 0 0 1 1.4-1.4Z"/><path d="M5.6 7.2V5.4a2.4 2.4 0 0 1 4.8 0v1.8"/></svg></span>` : "") + (n === "" ? "" : `<span class="n">${esc(String(n))}</span>`);
    const flags = edit
      ? ` data-links="${off ? 0 : 1}"${edit.rename.includes(key0) ? ' data-rename="1"' : ""}${
        /* A page following a Google Doc (`docfollow.js`): the menu's switch. */
        edit.follow && key0 in edit.follow ? ` data-follow="${edit.follow[key0] ? 1 : 0}"` : ""}`
      : "";
    const key = ` data-key="${esc(key0)}"${flags}${railName("row", key0)}`;
    /* **Quiet when there is nothing behind it** — for him only; a reader is
       not sent the row at all. `unfilled` in `src/pages.js` decides. */
    const quiet = (((HUB.rail && HUB.rail.empty) || []).includes(key0) ? " empty" : "") + (off ? " offl" : "");
    if (r.doc) {
      return `<a class="to${quiet}"${key} data-icon="${rowIconName(r)}" draggable="false" data-outside="1" target="_blank" rel="noopener" href="${esc(r.href)}"><span class="dot"></span>${rowIcon(r)}<span class="nm">${esc(r.name)}</span>${count}</a>`;
    }
    if (r.page) {
      return `<a class="to${quiet}"${key} data-icon="${rowIconName(r)}" draggable="false" data-deep="record" href="${esc(recordHref(r.at))}"><span class="dot"></span>${rowIcon(r)}<span class="nm">${esc(r.name)}</span>${syncDot(edit && edit.sync && edit.sync[key0])}${count}</a>`;
    }
    const here = mode === r.at;
    return `<button class="to${here ? " on" : ""}${quiet}"${key} data-icon="${rowIconName(r)}" data-mode="${r.at}"><span class="dot"></span>${rowIcon(r)}<span class="nm">${esc(r.name)}</span>${count}</button>`
      + (here ? well() : "");
  }).join("");
}

/**
 * The current section's own list, under the row it belongs to.
 *
 * The scenes, the places and the boards each already had a sidebar of their
 * own; this is that list, in the rail, which is why the app gives up its
 * 258px column and the screen goes back to three parts instead of four.
 */
function well() {
  if (!model) return "";          // nothing to list until the film is read
  if (mode === "shots") return sceneWell();
  if (mode === "locations") return listWell("Search locations", placeRows(), place || null, "place");
  if (mode === "boards") return listWell("Search boards", boardRows(), boardChosen(), "board");
  if (mode === "diagrams") return listWell("Search scenes", diagramRows(), planChosen(), "plan");
  return "";
}

function sceneWell() {
  const filter = model.filter || {};
  const gone = new Set(filter.hiddenSceneIds || []);
  const left = scenesLeft();
  const scenes = (model.scenes || [])
    .filter((s) => !setAside(s) && !gone.has(s.id) && inShoot(s.id))
    .filter((s) => !left || left.has(s.id));
  const all = (model.scenes || []).filter((s) => !setAside(s) && inShoot(s.id)).length;
  const body = filterOpen ? filterPanel() : `
    <div class="scopedlist scrolls">
      ${sceneRuns(scenes).map(({ section, run }) => {
        // A section's run sits on a panel of its own — `sceneRuns` says why.
        const kids = run.map((s) => `<button class="kid${inView === s.id ? " on" : ""}" data-scene="${esc(s.id)}">
        <span class="tod" style="background:${timeInk(s.timeOfDay)}"></span>
        <span class="num">${esc(s.number)}</span>
        <span class="hd">${esc(s.heading || s.location)}</span></button>`).join("");
        return section
          ? `<div class="secpanel" style="${sectionVars(section)}"><div class="sechead">${esc(section.title)}</div>${kids}</div>`
          : kids;
      }).join("")}
    </div>
    <div class="scount">${scenes.length === all ? many(all, "scene")
      : `<b>${scenes.length}</b> of ${all} scenes`}</div>`;

  return `<div class="wellwrap open" style="view-transition-name:well-${mode};view-transition-class:well"><div class="scoped"><div class="scopedin host">
    <div class="scopedhead">
      <input class="sfield" id="find" type="search" placeholder="Search scenes, shots, gear" value="${esc(asking.search)}">
      ${LENS ? `<button class="filterbtn${byDay() ? " lit" : ""}" data-groupby="${byDay() ? "scene" : "day"}" title="Shooting order">Days</button>`
        : `<button class="filterbtn${anyFacet() || filterOpen ? " lit" : ""}" data-facet="${filterOpen ? "" : "fields"}">Filter</button>`}
    </div>
    ${LENS ? lensChips() : facetChips()}
    ${body}
  </div></div></div>`;
}

/** What a list's count is counting, one or many. */
/** Rows that are things, not the heads over them. */
function counted(rows) { return rows.filter((r) => !r.head).length; }

function listWord(what, n) {
  const word = { place: "location", plan: "diagram" }[what] || "board";
  return n === 1 ? word : `${word}s`;
}

function listWell(placeholder, rows, chosenId, what) {
  const said = listFind.trim().toLowerCase();
  const shown = said ? rows.filter((r) => !r.head && r.name.toLowerCase().includes(said)) : rows;
  return `<div class="wellwrap open" style="view-transition-name:well-${mode};view-transition-class:well"><div class="scoped"><div class="scopedin host">
    <div class="scopedhead">
      <input class="sfield" id="listfind" type="search" placeholder="${esc(placeholder)}" value="${esc(listFind)}">
    </div>
    <div class="scopedlist scrolls">
      ${shown.length ? shown.map((r) => r.head
          // A head over a run — the Diagrams page's Plans and Scenes — with
          // its own + where it makes things (`r.add`).
          ? (r.reveal ? `<button type="button" class="kidhead kidreveal" data-pshowempty="1">${esc(r.reveal)}</button>`
            : `<div class="kidhead"><span>${esc(r.head)}</span>${r.eye ? `<button type="button" class="kidadd kideye${r.eye === "on" ? " on" : ""}" data-phideempty="${esc(r.eye)}" title="Hide Empty" aria-label="Hide Empty" aria-pressed="${r.eye === "on"}">${eye_mark(r.eye === "on")}</button>` : ""}${r.add ? `<button type="button" class="kidadd" data-${esc(r.add)}="1" title="New Plan" aria-label="New Plan">+</button>` : ""}</div>`)
          : `<button class="kid${r.deep ? " deep" : ""}${chosenId === r.id ? " on" : ""}${r.out ? " out" : ""}${r.mark ? " mark" : ""}" data-pick="${esc(what)}" data-id="${esc(r.id)}"${r.menu ? ` data-pdscene="${esc(r.id)}"` : ""}>
          <span class="hd">${esc(r.name)}</span><span class="kn">${esc(String(r.count))}</span>${r.menu ? `<span class="kmore" role="button" tabindex="-1" data-pdscenemenu="${esc(r.id)}" title="More" aria-label="Scene Menu">⋯</span>` : ""}</button>`).join("")
        : `<div class="scount">Nothing matches</div>`}
    </div>
    <div class="scount">${counted(shown) === counted(rows) ? `${counted(rows)} ${listWord(what, counted(rows))}`
      : `<b>${counted(shown)}</b> of ${counted(rows)} ${listWord(what, counted(rows))}`}</div>
  </div></div></div>`;
}

/**
 * **The phone's own furniture, which the program was missing entirely.**
 *
 * The rail is a sheet on a phone, parked off the bottom of the screen until
 * something raises it — and the program had no bar to raise it with, no top bar
 * and no scrim. So the dock vanished the moment you went into a section and the
 * rail could not be opened at all: *"dock disappeared after you click into a
 * tab... Side bar in shot list doesn't do anything"*, his report 2026-09-04.
 * The record's pages had all three from the start; this is the same three.
 */
/* **Hoisted functions, not consts, and that is the second time.** `paint()`
   runs at boot, before any `const` further down the file has been initialised
   — reading one there is a ReferenceError, not `undefined`, and the whole app
   draws nothing. `RAIL` did exactly this earlier the same day. A function
   declaration hoists; these return a string when asked. */
function eye_mark(off) { return `<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M1.6 8S4 3.6 8 3.6 14.4 8 14.4 8 12 12.4 8 12.4 1.6 8 1.6 8Z"/><circle cx="8" cy="8" r="2"/>${off ? '<path d="M2.6 13.4 13.4 2.6"/>' : ""}</svg>`; }
function lock_mark() { return '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.4 7.2h7.2a1.4 1.4 0 0 1 1.4 1.4v4.2a1.4 1.4 0 0 1-1.4 1.4H4.4A1.4 1.4 0 0 1 3 12.8V8.6a1.4 1.4 0 0 1 1.4-1.4Z"/><path d="M5.6 7.2V5.4a2.4 2.4 0 0 1 4.8 0v1.8"/></svg>'; }
function link_mark() { return '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6.7 9.3a2.5 2.5 0 0 0 3.6 0l2-2a2.55 2.55 0 0 0-3.6-3.6l-.8.8"/><path d="M9.3 6.7a2.5 2.5 0 0 0-3.6 0l-2 2a2.55 2.55 0 0 0 3.6 3.6l.8-.8"/></svg>'; }
function globe_mark() { return '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="8" r="5.4"/><path d="M2.6 8h10.8"/><path d="M8 2.6c1.5 1.6 2.3 3.4 2.3 5.4S9.5 11.8 8 13.4C6.5 11.8 5.7 10 5.7 8S6.5 4.2 8 2.6Z"/></svg>'; }
/**
 * Who is offered Share, and which mark it wears.
 *
 * **A link holder is offered it too.** His ask, 2026-09-08: somebody reading
 * the film on an unlisted link should get the same button, and be able to copy
 * that link — the address bar cannot give it to them, because every address
 * inside the film is a plain one with no key on it. They are offered nothing
 * else; the window decides what to draw once it opens.
 *
 * The mark is the truth about the film: a globe for one being read on a link,
 * a padlock otherwise.
 */
function mayShare() { return HUB.role === "editor" || Boolean(HUB.linkKey); }
function share_mark() { return HUB.linkKey ? globe_mark() : lock_mark(); }
function person_mark() { return '<svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="8" cy="6" r="2.6"/><path d="M3.4 13.4a4.6 4.6 0 0 1 9.2 0"/></svg>'; }
function back_mark() { return '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.8 8H3.2"/><path d="M6.8 4.4 3.2 8l3.6 3.6"/></svg>'; }
function plus_mark() { return '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 3.4v9.2"/><path d="M3.4 8h9.2"/></svg>'; }
function rows_mark() { return '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.8 4.2h10.4"/><path d="M2.8 8h10.4"/><path d="M2.8 11.8h6.4"/></svg>'; }
function find_mark() { return '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="7.2" cy="7.2" r="4.2"/><path d="M10.4 10.4 13.4 13.4"/></svg>'; }
function open_mark() { return '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.2 6.2 8 10l3.8-3.8"/></svg>'; }
function arrow_mark() { return '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.2 8h9.6"/><path d="M9.2 4.4 12.8 8l-3.6 3.6"/></svg>'; }
function chev_mark() { return '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 3.5L10.5 8L6 12.5"/></svg>'; }
function tick_mark() { return '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 8.5L6.5 12L13 4.5"/></svg>'; }
function open_ext() { return '<svg class="ext" viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 3.5h6.5V10"/><path d="M12.5 3.5 4 12"/></svg>'; }
function ex_mark() { return '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg>'; }
function appPhoneParts() {
  const base = HUB.base || `/f/${HUB.project}`;
  const here = railParts().flatMap((g) => g.rows).find((r) => r.at === mode);
  const back = (HUB.rail && HUB.rail.back) || "";
  // **One dock** (phone move 1): the top line is the film's mark and name and
  // opens the sidebar sheet; Share lives in that sheet's header now. The same
  // markup as `phoneParts` in `src/pages.js`, which `public/dock.js` listens to.
  return `<header class="fh-topbar">
      ${back ? `<a class="tback" href="${esc(back)}" aria-label="Projects" title="Projects">${back_mark()}</a>` : ""}
      <button type="button" class="tname" data-sheet="open" aria-label="Pages">${filmMark()}<span>${esc(filmTitle())}</span></button>
    </header>
    <div class="fh-scrim" data-sheet="shut"></div>
    <div class="dock" data-dock>
      <button class="nowbar" data-sheet="open" type="button" aria-label="Pages">
        <span class="nn">${esc(here ? here.name : "Shot List")}</span>
      </button>
      <button class="dockbtn dockfind" data-dockfind type="button" aria-label="Find">${find_mark()}</button>
      ${HUB.role === "editor" ? `<a class="dockbtn dockadd" data-dockadd href="${esc(base)}/add" aria-label="Add">${plus_mark()}</a>` : ""}
    </div>`;
}

function appRail() {
  const base = HUB.base || `/f/${HUB.project}`;
  /* **The same mark the record's rail carries**, so one script arranges both.
     `public/arrange.js` looks for exactly this and works by delegation, which
     is why it survives this rail being drawn again on every paint. */
  /* **The same rail as the record's pages, part for part.** `railFor` in
     `src/pages.js` draws the Projects arrow, the film's name, the rows under
     his headings, the editor's Add and Headings, and the foot — and this one
     drew the name, the rows and the foot. So the arrow came and went and the
     tools came and went as he crossed the door, and every row moved with them.
     His report, 2026-09-16. What is drawn here is now the same list; the one
     thing the app adds is the Live dot, which is a fact only the app knows. */
  const back = (HUB.rail && HUB.rail.back) || "";
  const edit = (HUB.rail && HUB.rail.edit) || null;
  const fresh = (HUB.rail && HUB.rail.fresh) || "";
  return `<nav class="rail"${HUB.role === "editor" ? ` data-arrange="${esc(base)}/order" data-base="${esc(base)}"${edit ? ` data-shelves="${esc(JSON.stringify(edit.shelves))}" data-built="${esc(JSON.stringify(edit.built))}"` : ""}${HUB.admin ? " data-admin" : ""}` : ""}>
    <div class="grabber" aria-hidden="true"></div>
    <div class="railtop">
      ${back ? `<a class="back" href="${esc(back)}">${back_mark()}<span class="bw">Projects</span></a>` : ""}
      <div class="filmline"><a class="fh-who" data-deep="home" href="${esc(base)}">${filmMark()}<span class="filmname">${esc(
        filmTitle())}</span></a>${
        /* The worker draws the line (`freshLine` in pages.js) and it is his
           alone; it lives behind the film's name, as on the record's pages. */
        fresh ? `<details class="filmmenu"><summary aria-label="Film Menu" title="Film Menu">${open_mark()}</summary><div class="pmcard">${fresh}</div></details>` : ""}</div>
      ${shootTabsHere()}
      <button type="button" class="railfind" data-find aria-label="Find">${find_mark()}<span>Find</span><kbd>⌘K</kbd></button>
    </div>
    <div class="sectionhost"><div class="sections scrolls">
      ${libraryRow(base)}
      ${railParts().map((g, i) => `${g.head ? `<div class="grouphead"${railName("head", i)}>${esc(g.head)}</div>` : ""}
        <div class="group" data-head="${esc(g.head)}"${HUB.role === "editor" && g.shelf ? ` data-shelf="${esc(g.shelf)}"${g.builtIn ? " data-builtin" : ""}` : ""}>${railRows(g)}</div>`).join("")}
    </div></div>
    <div class="railfoot">
      ${meCard()}
      <span class="livedot${live && !missing ? "" : " off"}"><i></i>${
        offline ? "Offline" : !live ? "Reconnecting" : missing ? `${missing} ${missing === 1 ? "log" : "logs"} missing` : "Live"
      }</span>
      ${HUB.role === "editor" ? `<a class="railadd" data-add href="${esc(base)}/add" title="Add" aria-label="Add">${plus_mark()}</a>` : ""}
      ${mayShare() ? `<a class="sharebtn${HUB.linkKey ? " open" : ""}" data-share href="${esc(base)}/share" title="Share">${share_mark()}Share</a>` : ""}
    </div>
  </nav>`;
}

// ------------------------------------------------------------------- wiring

/**
 * The address, kept in step with which of the four is on screen.
 *
 * Each of them is a real address — the film's page links to all four, and
 * arriving at one opens the app in it. Moving between them *inside* the app
 * never touched the address, so anything that reads the address was told the
 * shot list whatever was showing. Share is where that showed: a link copied
 * from Locations opened the shot list. His report, 2026-09-08.
 *
 * **`replaceState`, not `pushState`.** Back leaves the app, and it did before
 * this — stepping back through four tabs first would be a new behaviour nobody
 * asked for. The query is carried through untouched: on the share host it holds
 * the key that opened the film at all.
 */
const MODE_AT = { shots: "shotlist", diagrams: "diagrams", locations: "locations", boards: "boards", schedule: "schedule" };

/**
 * The screen an address names, or nothing. The reverse of `MODE_AT`.
 */
function modeAt(pathname) {
  const last = String(pathname || "").replace(/\/+$/, "").split("/").pop();
  return Object.keys(MODE_AT).find((m) => MODE_AT[m] === last) || null;
}

/**
 * **Brought back by a door, the app goes to the screen the door named.**
 *
 * `deep.js` keeps the app standing when he leaves it and swaps it back in
 * when he presses one of its rows on a record page — and it came back as it
 * was, on whatever screen it was left on. Pressing Locations opened the Shot
 * List whenever the Shot List was where he had been. His report, 2026-09-10.
 * The address is already the door's by the time `entering` fires, so the
 * screen is read off it — the reverse of `keepAddress`. Drawn while still put
 * away; the `resize` that `unstow` sends draws it again at its real size.
 */
document.addEventListener("entering", () => {
  const want = modeAt(location.pathname);
  if (!want || want === mode || hidden(want)) return;
  mode = want;
  draw();
});

function keepAddress() {
  const base = HUB.base || `/f/${HUB.project}`;
  const want = `${base}/${MODE_AT[mode] || "shotlist"}${location.search}${location.hash}`;
  if (location.pathname + location.search + location.hash === want) return;
  try {
    history.replaceState(history.state, "", want);
  } catch {
    /* a browser that refuses is a browser that keeps the old address — no worse
       than before this existed, and not worth taking the click down for */
  }
}

/**
 * **What ⌘K can jump to inside the film** — Ref 1161, item 2. `public/jump.js`
 * draws the box and finds the film's pages off the rail; only the program
 * knows the scenes, the places and the boards, so it says them here. Each
 * one goes the way pressing it in the rail's list goes. A screen this reader
 * may not see offers nothing, as its rail row offers nothing.
 */
window.shotlisterJump = () => {
  if (!model) return [];
  const to = (want, then) => () => {
    if (hidden(want)) return;
    mode = want;
    if (narrow) sidebar = false;
    then();
    keepAddress();
    travelled(() => draw());
  };
  const out = [];
  if (!hidden("shots")) {
    for (const s of (model.scenes || []).filter((one) => !one.archived)) {
      out.push({
        kind: "Scene", name: [s.number, s.heading || s.location].filter(Boolean).join(" "),
        go: () => {
          to("shots", () => { scene = s.id; })();
          setTimeout(() => goToScene(s.id, "smooth"), 450);
        },
      });
    }
  }
  if (!hidden("locations")) {
    for (const r of placeRows()) out.push({ kind: "Location", name: r.name, go: to("locations", () => { place = r.id; }) });
  }
  if (!hidden("boards")) {
    for (const r of boardRows()) out.push({ kind: "Reference Images", name: r.name, go: to("boards", () => { board = r.id; }) });
  }
  return out;
};

/**
 * **The days, and Not Scheduled, under a shot's Day cell** — the Mac's `pickDay`
 * (Ref 1570). A press on the chip opens a small menu: every day of the film as
 * `Day 2 · Sat 10 Jul`, the shot's own day ticked, then Not Scheduled. A pick
 * goes to the same door the Shooting Order drag does (`PUT api/shootorder`, the
 * connector's `schedule_shot`), with no place named, which is the end of that
 * day's order, as the Mac and the phone put it; its scene, number and letter
 * stay. The film is read again once the server has kept it; a refusal leaves
 * the cell as it was. One menu at a time, put away by a press anywhere else or
 * Escape.
 */
function pickDay(button) {
  const open = document.querySelector(".daymenu");
  const same = open && open.dataset.shot === button.dataset.dayof;
  if (open) open.remove();
  if (same) return;
  const held = button.dataset.day || "";
  const menu = document.createElement("div");
  menu.className = "daymenu";
  menu.dataset.shot = button.dataset.dayof;
  menu.setAttribute("role", "menu");
  const item = (label, day, on, quiet) => `<button class="dayitem${on ? " on" : ""}${quiet ? " quiet" : ""}" role="menuitem" data-pickday="${esc(day)}">${on ? tick_mark() : "<i></i>"}<span>${esc(label)}</span></button>`;
  menu.innerHTML = ((model && model.days) || []).map((d) =>
    item(d.date ? `${d.label} · ${niceDate(d.date)}` : d.label, d.label, d.label === held)).join("")
    + `<div class="daysep"></div>` + item("Not Scheduled", "", !held, true);
  const at = button.getBoundingClientRect();
  document.body.appendChild(menu);
  const room = menu.getBoundingClientRect();
  const left = Math.max(8, Math.min(at.left, window.innerWidth - room.width - 8));
  const below = at.bottom + 4;
  const top = below + room.height > window.innerHeight - 8 ? Math.max(8, at.top - room.height - 4) : below;
  menu.style.left = `${Math.round(left)}px`;
  menu.style.top = `${Math.round(top)}px`;
  menu.querySelectorAll("[data-pickday]").forEach((b) =>
    b.addEventListener("click", async (event) => {
      event.stopPropagation();
      const day = b.dataset.pickday;
      menu.remove();
      if (day === held) return;
      button.classList.add("saving");
      try {
        const got = await fetch(`/f/${HUB.project}/api/shootorder`, {
          method: "PUT", headers: { "content-type": "application/json" },
          body: JSON.stringify({ shot: button.dataset.dayof, day }),
        });
        if (!got.ok) throw new Error(`${got.status} ${await got.text()}`);
        await check();
      } catch (error) {
        button.classList.remove("saving");
        button.title = "Could not change the day";
        console.warn("could not change the day", button.dataset.dayof, String(error));
      }
    })
  );
  const first = menu.querySelector(".dayitem.on") || menu.querySelector(".dayitem");
  if (first) first.focus();
}
document.addEventListener("click", (event) => {
  const open = document.querySelector(".daymenu");
  if (open && !open.contains(event.target)) open.remove();
});
document.addEventListener("keydown", (event) => {
  const open = document.querySelector(".daymenu");
  if (!open) return;
  if (event.key === "Escape") { open.remove(); return; }
  if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
  event.preventDefault();
  const all = [...open.querySelectorAll(".dayitem")];
  const at = all.indexOf(document.activeElement);
  all[(at + (event.key === "ArrowDown" ? 1 : -1) + all.length) % all.length].focus();
});

function wire() {
  wirePlan();
  root.querySelectorAll("[data-mode]").forEach((b) =>
    b.addEventListener("click", () => {
      // **A hidden screen is refused here as its address is refused by the
      // worker.** The rail does not offer it, but a button is a button.
      if (hidden(b.dataset.mode)) return;
      mode = b.dataset.mode;
      keepAddress();
      travelled(() => draw());
    })
  );
  root.querySelectorAll("[data-view]").forEach((b) =>
    b.addEventListener("click", () => {
      view = b.dataset.view;
      travelled(() => draw());
    })
  );
  root.querySelectorAll("details.shootmenu").forEach((d) =>
    d.addEventListener("toggle", () => { shootMenuOpen = d.open; })
  );
  root.querySelectorAll("[data-allshoots]").forEach((b) =>
    b.addEventListener("click", () => {
      allShoots = b.dataset.allshoots === "1";
      draw();
    })
  );
  // The Shot mark: the row flips at once, the server writes the change, and
  // the film is read again once the log is there. A refusal puts it back.
  root.querySelectorAll("[data-editref]").forEach((b) =>
    b.addEventListener("click", (event) => { event.stopPropagation(); openEditRef(b.dataset.editref, b); })
  );
  // A light runs down the bracket while the pointer is on its button.
  root.querySelectorAll(".eref-play").forEach((b) =>
    b.addEventListener("pointerenter", () => {
      if (editCalm()) return;
      document.querySelectorAll(`[data-erefline="${CSS.escape(b.dataset.editref)}"]`).forEach((line, i) =>
        line.animate([{ "--sheen": 0 }, { "--sheen": 1 }, { "--sheen": 0 }], { duration: 300, delay: i * 55, easing: "ease-in-out" }));
    })
  );
  root.querySelectorAll("[data-mark]").forEach((b) =>
    b.addEventListener("click", async (event) => {
      event.stopPropagation();
      const number = b.dataset.mark;
      const done = b.dataset.done === "1";
      const row = b.closest(".trow, .lrow, .card, .scshot");
      if (row) row.classList.toggle("struck", done);
      b.classList.toggle("on", done);
      b.dataset.done = done ? "0" : "1";
      b.disabled = true;
      try {
        const got = await fetch(`/f/${HUB.project}/api/mark`, {
          method: "PUT", headers: { "content-type": "application/json" },
          body: JSON.stringify({ shot: number, done }),
        });
        if (!got.ok) throw new Error(String(got.status));
        await check();
      } catch (error) {
        if (row) row.classList.toggle("struck", !done);
        b.classList.toggle("on", !done);
        b.dataset.done = done ? "1" : "0";
        b.title = "Could not mark";
        console.warn("could not mark", number, String(error));
      } finally {
        b.disabled = false;
      }
    })
  );
  // The Day cell: the days, and Not Scheduled, under the chip.
  root.querySelectorAll("[data-dayof]").forEach((b) =>
    b.addEventListener("click", (event) => {
      event.stopPropagation();
      pickDay(b);
    })
  );
  // Scenes or Days: the engine is asked again, the film is not read again.
  root.querySelectorAll("[data-groupby]").forEach((b) =>
    b.addEventListener("click", () => {
      asking.groupBy = b.dataset.groupby === "day" ? "day" : "scene";
      try { localStorage.setItem(GROUP_KEY, asking.groupBy); } catch {}
      relook();
      if (byDay()) goToToday();
    })
  );
  root.querySelectorAll("[data-scene]").forEach((b) =>
    b.addEventListener("click", () => {
      scene = b.dataset.scene || null;
      // **A pick is a scroll, not a redraw** — see `goToScene`. The page is
      // drawn again only when it has to be: on a phone the list lies over the
      // film and has to be put away, the way opening a scene on the iPhone
      // leaves the index behind. The well keeps its place through that
      // redraw, and the scroll starts from there.
      if (narrow) {
        sidebar = false;
        draw();
      }
      if (scene) goToScene(scene, "smooth");
    })
  );
  // Scenes or Shooting Order on the Schedule: the page is drawn again, the
  // film is not read again.
  root.querySelectorAll("[data-shootorder]").forEach((b) =>
    b.addEventListener("click", () => {
      shootOrder = b.dataset.shootorder === "1";
      try { localStorage.setItem(RUN_KEY, shootOrder ? "1" : "0"); } catch {}
      draw();
    })
  );
  // A shot in the shooting order, pressed twice: opened in the Shot List at
  // its scene, as a stripe is.
  root.querySelectorAll("[data-runscene]").forEach((b) =>
    b.addEventListener("dblclick", () => {
      if (hidden("shots") || !b.dataset.runscene) return;
      scene = b.dataset.runscene;
      mode = "shots";
      keepAddress();
      travelled(() => {
        draw();
        goToScene(scene, "auto");
      });
    })
  );
  // The schedule's stripes: pressed, lit; pressed twice, opened in the Shot
  // List at that scene — see `strip`.
  root.querySelectorAll("[data-strip]").forEach((b) => {
    b.addEventListener("click", () => {
      strip_ = b.dataset.strip;
      root.querySelectorAll("[data-strip]").forEach((x) => x.classList.toggle("on", x === b));
    });
    b.addEventListener("dblclick", () => {
      if (hidden("shots")) return;
      scene = b.dataset.strip;
      mode = "shots";
      keepAddress();
      travelled(() => {
        draw();
        goToScene(scene, "auto");
      });
    });
  });
  // ---- the filter ---------------------------------------------------------
  root.querySelectorAll("[data-facet]").forEach((b) =>
    b.addEventListener("click", () => {
      filterOpen = b.dataset.facet || null;
      filterFind = "";
      draw();
    })
  );
  root.querySelectorAll("[data-facetval]").forEach((b) =>
    b.addEventListener("click", () => {
      const cut = b.dataset.facetval.indexOf("|");
      const field = b.dataset.facetval.slice(0, cut), value = b.dataset.facetval.slice(cut + 1);
      const at = asking.facets.findIndex(([f, v]) => f === field && v === value);
      if (at >= 0) asking.facets.splice(at, 1); else asking.facets.push([field, value]);
      draw();
    })
  );
  root.querySelectorAll("[data-unfacet]").forEach((b) =>
    b.addEventListener("click", () => {
      const said = b.dataset.unfacet;
      if (said === "*") asking.facets = [];
      else {
        const cut = said.indexOf("|");
        const field = said.slice(0, cut), value = said.slice(cut + 1);
        asking.facets = asking.facets.filter(([f, v]) => !(f === field && v === value));
      }
      draw();
    })
  );
  const facetFind = root.querySelector("#facetfind");
  if (facetFind) {
    facetFind.addEventListener("input", () => {
      filterFind = facetFind.value;
      draw();
      const again = root.querySelector("#facetfind");
      if (again) { again.focus(); again.setSelectionRange(again.value.length, again.value.length); }
    });
  }

  const find = root.querySelector("#find");
  if (find) {
    // Debounced, because every keystroke re-describes the whole film — fast,
    // but not fast enough to do six times a word.
    let waiting = null;
    find.addEventListener("input", () => {
      clearTimeout(waiting);
      waiting = setTimeout(() => {
        asking.search = find.value;
        relook();
        const again = root.querySelector("#find");
        if (again) { again.focus(); again.setSelectionRange(again.value.length, again.value.length); }
      }, 220);
    });
  }
  root.querySelectorAll("[data-sortby]").forEach((b) =>
    b.addEventListener("click", () => {
      const name = b.dataset.sortby;
      // Click once to sort, again to turn it round, a third time for the
      // list's own order — which is what the numbering means.
      // A column's order is not the shooting order: picking one leaves it.
      if (byDay()) { asking.groupBy = "scene"; try { localStorage.setItem(GROUP_KEY, "scene"); } catch {} }
      if (asking.sortColumn !== name) { asking.sortColumn = name; asking.sortDescending = false; }
      else if (!asking.sortDescending) { asking.sortDescending = true; }
      else { asking.sortColumn = ""; asking.sortDescending = false; }
      relook();
    })
  );
  root.querySelectorAll("[data-sort]").forEach((b) =>
    b.addEventListener("click", () => {
      asking.sortColumn = "";
      asking.sortDescending = false;
      relook();
    })
  );
  root.querySelectorAll("[data-sortpick]").forEach((pick) =>
    pick.addEventListener("change", () => {
      const said = pick.value;
      const day = said === "shootingorder";
      asking.groupBy = day ? "day" : "scene";
      asking.sortColumn = day ? "" : said;
      asking.sortDescending = false;
      try { localStorage.setItem(GROUP_KEY, asking.groupBy); } catch {}
      relook();
      if (day) goToToday();
    })
  );

  // **Grown in place, never by redrawing.** `paint` replaces the whole page,
  // which puts the well back at the top — so reading the synopsis on scene 15
  // would throw you to scene 2. The words are already in the button; all that
  // changes is whether it is allowed more than one line. `sceneBand` reads the
  // same set, so a real redraw — a search, a sort, a change of view — leaves
  // open whatever was open.
  root.querySelectorAll("[data-synopsis]").forEach((b) =>
    b.addEventListener("click", () => {
      const key = b.dataset.synopsis;
      const open = !openSynopsis.has(key);
      if (open) openSynopsis.add(key);
      else openSynopsis.delete(key);
      b.classList.toggle("on", open);
      b.title = open ? "Shorten" : "Read the synopsis";
    })
  );

  root.querySelectorAll("[data-sidebar]").forEach((b) =>
    b.addEventListener("click", () => { sidebar = !sidebar; travelled(() => draw(), "panes"); })
  );
  // The dim behind the script panel. The panel's own toggle is up in the views
  // bar, which a sheet covering the screen has hidden.
  const pick = root.querySelector("[data-script]");
  if (pick) pick.addEventListener("change", () => { scriptSection = pick.value; draw(); });
  // A quoted stretch takes the page to its shot's scene.
  root.querySelectorAll("[data-quote]").forEach((m) =>
    m.addEventListener("click", () => goToScene(m.dataset.quote)));
  root.querySelectorAll("[data-panelshut]").forEach((b) =>
    b.addEventListener("click", () => { panel = null; travelled(() => draw(), "panes"); })
  );
  // **The house above a room's name, and the rooms listed on a house.** Kept
  // apart from `[data-pick]`, which means *a row in the list* and is what the
  // driven checks reach for.
  root.querySelectorAll("[data-goto]").forEach((b) =>
    b.addEventListener("click", () => {
      place = b.dataset.goto;
      if (narrow) sidebar = false;
      draw();
    })
  );
  root.querySelectorAll("[data-pick]").forEach((b) =>
    b.addEventListener("click", () => {
      if (b.dataset.pick === "place") place = b.dataset.id;
      else if (b.dataset.pick === "plan") { if (diagram) diagram.chose(); plan = b.dataset.id; planCam = null; planBeat = 1; }
      else board = b.dataset.id;
      if (narrow) sidebar = false;
      draw();
    })
  );
  const listfind = root.querySelector("#listfind");
  if (listfind) {
    listfind.addEventListener("input", () => {
      listFind = listfind.value;
      draw();
      const again = root.querySelector("#listfind");
      if (again) { again.focus(); again.setSelectionRange(again.value.length, again.value.length); }
    });
  }

  root.querySelectorAll("[data-open]").forEach(opensAPicture);
  root.querySelectorAll("[data-shut]").forEach((b) =>
    b.addEventListener("click", (event) => {
      /* **The close mark shuts however it is hit.** `event.target === b` was
         false every single time it was pressed: a tap lands on the `<svg>`
         inside the button, never on the button. On a desk Escape covered for
         it; a phone has no Escape, so the pop-out was a room with no door —
         his report, 2026-09-04: *"i can't get it to go away, tapping off of it
         doesnt do anything. its just stuck there"*. */
      if (b.tagName === "BUTTON") {
        event.stopPropagation();
        openShot = null; openRoom = null; draw();
        return;
      }
      /* **And the backdrop is anywhere that is not the picture itself.** It
         used to be the element exactly, which on a phone is a 12px border
         around a stage that fills the screen — a target nobody can hit. The
         original intent stands: clicking the *picture* must not shut it, or
         looking closely at something closes it. That is now what `data-stop`
         marks, rather than the whole middle of the screen. */
      if (!event.target.closest("[data-stop]")) { openShot = null; openRoom = null; draw(); }
    })
  );
  root.querySelectorAll("[data-stop]").forEach((b) =>
    b.addEventListener("click", (event) => event.stopPropagation())
  );
  root.querySelectorAll("[data-frame]").forEach((b) =>
    b.addEventListener("click", () => {
      openIndex = Number(b.dataset.frame);
      draw();
    })
  );
  root.querySelectorAll("[data-planshot]").forEach((b) =>
    b.addEventListener("click", (event) => {
      event.stopPropagation();
      openShot = null;
      if (diagram) diagram.chose();
      plan = b.dataset.planscene; planCam = null; planBeat = 1;
      planShot = b.dataset.planshot;
      mode = "diagrams";
      keepAddress();
      travelled(() => draw());
    })
  );
  root.querySelectorAll("[data-grip]").forEach(dragColumn);
  root.querySelectorAll("[data-tscale]").forEach((slider) => {
    const sizeAt = () => TEXT_SIZES[Number(slider.value)] || 1;
    // While the thumb moves the type follows it; the columns are re-measured
    // when it is let go, because a redraw under a drag would take the slider
    // out from under the pointer.
    slider.addEventListener("input", () => {
      const well = root.querySelector(".well.table");
      if (well) well.style.setProperty("--tscale", String(sizeAt()));
    });
    slider.addEventListener("change", () => {
      textSize = sizeAt();
      try { localStorage.setItem(TEXT_SIZE_KEY, String(textSize)); } catch {}
      draw();
    });
  });
  holdTrim(root);
  // The pop-out's clip: its controls, and a click on the picture plays or
  // stops it, as a player does.
  root.querySelectorAll(".plate video").forEach((video) => {
    clipControls(video, true);
    video.addEventListener("click", () => toggleClip(video));
  });
  root.querySelectorAll("[data-sizes]").forEach((b) =>
    b.addEventListener("click", () => {
      openRoom = {
        hash: b.dataset.sizes,
        name: b.dataset.name || "",
        place: b.dataset.place || "",
        shape: b.dataset.shape || "",
        file: b.dataset.file || "",
      };
      draw();
    })
  );
  drawMarks();
  drawPlans();
  fillRoom();
  playWhatIsSeen();
  // **Again once the page has actually been laid out.** The first pass runs in
  // the same tick as the drawing, when a row may still measure nought — and a
  // pass that finds nothing would never run again on a page nobody scrolls.
  requestAnimationFrame(() => playWhatIsSeen());
  setTimeout(playWhatIsSeen, 400);
  retryWhenReady(root);
  watchScrolling();

  root.querySelectorAll("[data-panel]").forEach(switchesThePanel);
}



/**
 * The pop-out — his ask, and the app has had one since August.
 *
 * A frame in the list is small on purpose; the moment you want to *look* at one
 * you want it big, and you want the shot's other frames to hand. So: the
 * picture or clip full size, the shot's filmstrip under it, arrow keys, and
 * escape.
 *
 * **It floats over the list rather than replacing it**, which is the difference
 * between looking at a frame and losing your place.
 */
function viewer() {
  if (!openShot) return "";
  const row = rowOf(openShot);
  if (!row) return "";
  const stills = row.stills && row.stills.length ? row.stills : row.frame ? [row.frame] : [];
  if (!stills.length) return "";
  const at = Math.max(0, Math.min(openIndex, stills.length - 1));
  const showing = stills[at];
  // **Where this shot's camera stands** — the scene's plan, the camera
  // picked and saying its shot (the Diagram's `takeShot`); the other way
  // round from the plan card's Shot List.
  const scene = (model.scenes || []).find((x) => x.id === row.sceneId);
  const onPlan = Boolean(row.shot && scene && scene.diagram > 0 && diagram && !hidden("diagrams"));
  // The film's shape, said once for the whole pop-out: the plate takes it and
  // so does every thumbnail under it.
  return `<div class="popout" data-shut="1" style="--r:${ratio()}">
    <div class="popbar" data-stop="1">
      <span class="no">${esc(row.number)}</span>
      <span class="poptitle">${esc(row.title || row.description || "")}</span>
      <div class="spacer"></div>
      <span class="lab">${at + 1} of ${stills.length}</span>
      ${onPlan ? `<button class="popgo" data-planshot="${esc(row.shot)}" data-planscene="${esc(row.sceneId)}">Diagram</button>` : ""}
      <button class="icon" data-shut="1" title="Close">${mark("close")}</button>
    </div>
    <div class="popstage">
      <span class="plate" data-stop="1">${mediaTag(showing, true)}</span>
    </div>
    ${stills.length > 1 ? `<div class="popstrip" data-stop="1">
      ${stills.map((m, i) => `<button class="popthumb ${i === at ? "on" : ""}" data-frame="${i}">${mediaTag({ ...m, kind: m.kind === "video" ? "image" : m.kind }, false)}</button>`).join("")}
    </div>` : ""}
  </div>`;
}

function rowOf(placement) {
  for (const group of model.groups || []) {
    const found = (group.rows || []).find((r) => r.placement === placement);
    if (found) return found;
  }
  return null;
}

// ------------------------------------------------------- drawing like the app

/**
 * **A chip's colour comes from its column, not from its word** — his ruling,
 * 2026-09-14, built on the Mac as `Brand.columnInk` and carried here
 * 2026-09-15. Shot sizes are one family, angles another, movement another; a
 * row stops being five random hues and a column reads as a set. Lens is a
 * list in Settings like the others, so it is a chip like the others.
 *
 * The named lists have a hue each — the same eight inks, the same assignment
 * as `Theme.swift`. A column the project made for itself takes one by hashing
 * its *name* (djb2, as the Mac does), so it is the same every time it is
 * drawn and the same on his Mac.
 *
 * The one thing this cannot see is a term he has coloured *by hand* — those
 * live behind the engine's `colours` command rather than in the description of
 * a film. His films have none today; when one does, this quietly draws the
 * column's colour where the Mac draws his. Filed rather than guessed at.
 */
const COLUMN_INKS = {
  size: "k2", angle: "k4", movement: "k6", lens: "k1", modifiers: "k1", lens_filters: "k1",
  support: "k8", tags: "k5", priority: "k3", pov: "k7",
};
function chipInk(column) {
  const known = COLUMN_INKS[column];
  if (known) return known;
  const trimmed = String(column == null ? "" : column).trim().toLowerCase();
  if (!trimmed) return "";
  let hash = 5381n;
  const mask = (1n << 64n) - 1n;
  for (const byte of new TextEncoder().encode(trimmed)) {
    hash = ((hash * 33n) + BigInt(byte)) & mask;
  }
  return `k${Number(hash % 8n) + 1}`;
}

/** Columns whose value is prose. Everything else with a value wears a chip. */
const PROSE = new Set(["title", "description", "notes", "script"]);

/**
 * **A column the project made for itself draws by its kind**, the same four
 * ways the Mac's table draws it (`Table.swift`): a *text* column is prose, a
 * *check* column is a tick, *single* and *multi* are chips. The engine says the
 * kind beside the column's name (Ref 249); a built-in column has none.
 */
function kindOf(column) {
  return (column && column.kind) || "";
}
function isProse(column) {
  return PROSE.has(column.name) || kindOf(column) === "text";
}
function isCheck(column) {
  return kindOf(column) === "check";
}

/** What the table is: the project's own columns, in its own order, visible only. */
function shownColumns() {
  return (model.columns || []).filter((c) => c.visible);
}

/**
 * The grid every row and the header share.
 *
 * One template, set once on the well, is what makes a column line up down the
 * page — the thing that separates a table from a stack of wrapped pills, and
 * most of why the first cut did not feel like the app.
 */
/**
 * **What a column is worth before anybody has an opinion about it.**
 *
 * A rule rather than a number wherever the column is prose: description, title
 * and notes stretch so the table fills the window instead of ending in a band
 * of grey. The rest are as wide as their chips need.
 */
function columnDefault(c) {
  return c.name === "image" ? `calc(132px * var(--tscale, 1))`
    : c.name === "description" ? "minmax(200px, 2.2fr)"
    : c.name === "title" ? "minmax(130px, 1.1fr)"
    : c.name === "notes" ? "minmax(140px, 1fr)"
    // The quoted script is prose, like a description.
    : c.name === "script" ? "minmax(200px, 1.8fr)"
    // A project's own text column is prose too — Wardrobe, Sound, Setup.
    : kindOf(c) === "text" ? "minmax(140px, 1fr)"
    : `${natural[c.name] || CHIP_COLUMN_MIN}px`;
}

/**
 * **A chip column is as wide as its widest chip, measured, and no wider than
 * a cap.** It used to be `minmax(88px, max-content)`, which reads as "grow to
 * fit" and never did: a chip clamps itself to a percentage of its cell, and a
 * percentage of a cell whose width depends on the chip is a cycle every
 * browser resolves differently — Chromium counted it as nothing, so Equipment
 * sat at 88px on a 2300px window with "Hood Mo…" in it while Description took
 * 619, and Safari made its own decision. His words, 2026-09-15: the pills
 * *"really struggle to keep inside of their column"*.
 *
 * So the width is a number, found the same way everywhere: every value the
 * column holds is drawn once, off screen, in the table's own type at the
 * table's own size, and the widest wins — floored at 88 so a heading fits,
 * capped at 176 so one long lens name cannot take the table. A longer value
 * still truncates with its ellipsis and carries itself in its tooltip. His
 * dragged width, when there is one, wins over all of this in `gridTemplate`.
 */
const CHIP_COLUMN_MIN = 88;
const CHIP_COLUMN_MAX = 176;
let natural = {};
const measured = new Map();
let measurer = null;

function measureChipColumns() {
  natural = {};
  if (narrow || view !== "table") return;
  const columns = shownColumns().filter((c) => c.name !== "image" && !isProse(c));
  if (!columns.length) return;
  if (!measurer) {
    measurer = document.createElement("div");
    measurer.className = "well table measure";
    measurer.setAttribute("aria-hidden", "true");
    measurer.innerHTML = `<span class="chip"></span>`;
    document.body.appendChild(measurer);
  }
  measurer.style.setProperty("--tscale", String(textSize));
  const chip = measurer.firstElementChild;
  const widthOf = (text) => {
    const key = `${textSize}|${text}`;
    if (!measured.has(key)) {
      chip.textContent = text;
      measured.set(key, chip.getBoundingClientRect().width);
    }
    return measured.get(key);
  };
  for (const c of columns) {
    let widest = 0;
    for (const g of model.groups || []) {
      for (const row of g.rows || []) {
        let value = row[c.name];
        if (value === undefined && row.custom) value = row.custom[c.name];
        const values = Array.isArray(value) ? value : value ? [value] : [];
        for (const v of values) {
          const text = named(v);
          if (text) widest = Math.max(widest, widthOf(text));
        }
      }
    }
    if (c.name === "struck") widest = Math.max(widest, widthOf("SHOT"));
    // Lens Stack draws a second line of names in the same cell: room for it.
    if (c.name === "lens") widest = Math.max(widest, 150);
    // The chip clamps itself to its cell less 6px, so the cell is the chip
    // plus that — rounded *up*, because a chip measured at 87.3 in a track
    // rounded to 93 is clamped to 87 and loses its last letter to the ellipsis
    // for a third of a pixel. Seen at the largest text size: "FULL-…".
    natural[c.name] = Math.min(CHIP_COLUMN_MAX, Math.max(CHIP_COLUMN_MIN, Math.ceil(widest) + 7));
  }
}

/**
 * **Every column's width is his, and none of them has to be.**
 *
 * A track is a custom property with the table's own rule as its fallback, so a
 * column nobody has dragged is drawn exactly as it always was, and one he has
 * dragged is the number he left it at. `var()` takes everything after the first
 * comma as the fallback, which is what lets `minmax(200px, 2.2fr)` sit there.
 */
function gridTemplate() {
  const width = (c) => `var(--w-${slug(c.name)}, ${columnDefault(c)})`;
  return ["44px", ...shownColumns().map(width)].join(" ");
}

function header() {
  return `<div class="thead" style="grid-template-columns:${gridTemplate()}">
    <span class="th">Shot</span>
    ${shownColumns().map((c) => {
      const on = asking.sortColumn === c.name;
      const button = `<button class="th${on ? " on" : ""}" data-sortby="${esc(c.name)}" title="Sort by ${esc(c.label || c.name)}">${esc(c.label || c.name)}${on ? mark(asking.sortDescending ? "down" : "up", 11) : ""}</button>`;
      // The grip is a grid item's *child*, never a grid item of its own — one
      // extra child of `.thead` and every column below it lines up one place
      // to the left of its own heading.
      return `<span class="thgrip">${button}<span class="grip" data-grip="${esc(c.name)}" title="Drag to resize"></span></span>`;
    }).join("")}
  </div>`;
}

/** One cell, decided by which column it is — the same decision the app makes. */
function cellFor(row, column) {
  const name = column.name;
  if (name === "image") return frameCell(row);
  if (name === "struck") return row.struck ? `<span class="chip k6">SHOT</span>` : "";

  // **The camera is the row's `unit`** — the engine's word for the record
  // a shot names, with its label, body and colour. Asking the row for
  // `camera` found nothing, and the column stood empty on every portal
  // (his report, 2026-09-19). Drawn in the camera's own colour, as the app.
  if (name === "camera") {
    const unit = row.unit;
    if (!unit || !unit.label) return "";
    // The label is the chip, as the app draws it; the body rides the title.
    // A colour is stored with or without its `#` depending on who wrote it.
    const said = unit.body ? `${unit.label} ${unit.body}` : unit.label;
    const hex = (unit.colour || "").replace(/^#?/, "#");
    const ink = unit.colour ? ` style="color:${esc(hex)}"` : "";
    return `<span class="chip"${ink} title="${esc(said)}">${esc(unit.label)}</span>`;
  }
  // **A shot's Shoot Day is picked, not sealed** (Ref 1570) — the Mac's Day
  // cell, here: an editor's chip is a button that opens the days. A shot on no
  // day shows Not Scheduled, quiet until the row is under the pointer. A
  // viewer, or a film with no days to pick from, sees the plain chip.
  if (name === "day" && HUB.role === "editor" && row.number && ((model && model.days) || []).length) {
    const said = named(row.day);
    return `<button class="chip ${chipInk(name)} daybtn${said ? "" : " unset"}" data-dayof="${esc(row.number)}" data-day="${esc(said)}" aria-haspopup="menu" title="Shoot Day">${esc(said || "Not Scheduled")}</button>`;
  }
  // **Lens Stack**: the lens chip, and the shot's filters and modifiers on a
  // quiet line under it, in the same cell. The two columns are not drawn.
  if (name === "lens") return lensStackCell(row);
  let value = row[name];
  if (value === undefined && row.custom) value = row.custom[name];
  value = named(value);
  // The quoted script keeps its paragraphs.
  if (name === "script" && value) {
    return `<span class="prose">${value.split(/\n\s*\n/).map((q) => esc(q.trim()).replace(/\n/g, "<br>")).join("<br><br>")}</span>`;
  }

  // A project's own column comes as a list whatever its kind — a text value
  // is a list of one, a check is present or absent — so the kind decides
  // before the shape does, or a sentence wears a chip and a tick reads "1".
  if (isCheck(column) || kindOf(column) === "text") {
    const own = row.custom && row.custom[name];
    const said = named(Array.isArray(own) ? own[0] : own);
    if (!said) return "";
    return isCheck(column) ? `<span class="check">${tick_mark()}</span>` : `<span class="prose">${esc(said)}</span>`;
  }

  if (Array.isArray(row[name]) || Array.isArray(row.custom && row.custom[name])) {
    const list = row[name] || row.custom[name];
    // The title carries the whole value, because a narrow column truncates the
    // chip and a tooltip is a label too.
    return list.map((v) => `<span class="chip ${chipInk(name)}" title="${esc(named(v))}">${esc(named(v))}</span>`).join(" ");
  }
  if (!value) return "";
  if (PROSE.has(name)) return `<span class="prose">${esc(value)}</span>`;
  return `<span class="chip ${chipInk(name)}" title="${esc(value)}">${esc(value)}</span>`;
}

/**
 * **Lens Stack, one cell** (his pick, 2026-10-15, variant B): the lens as the
 * chip it always was, then its filters and modifiers on a quiet second line —
 * a ring for a filter, a diamond for a modifier, in the lens colour turned
 * down. No box, no outline. A shot with neither draws exactly the lens chip.
 */
function lensStackCell(row) {
  const lens = named(row.lens);
  const filters = (row.lens_filters || []).map(named).filter(Boolean);
  const modifiers = (row.modifiers || []).map(named).filter(Boolean);
  const chip = lens ? `<span class="chip ${chipInk("lens")}" title="${esc(lens)}">${esc(lens)}</span>` : "";
  if (!filters.length && !modifiers.length) return chip;
  const item = (v, kind) =>
    `<span class="lu" title="${kind === "f" ? "Filter" : "Modifier"}"><i class="lg lg-${kind}"></i>${esc(v)}</span>`;
  return `<span class="lenscell">${chip}<span class="lensunder">${
    filters.map((v) => item(v, "f")).join("")}${modifiers.map((v) => item(v, "m")).join("")}</span></span>`;
}

/**
 * A shot's frame, and it plays.
 *
 * **His ask: clips autoplay.** The app plays them; a still poster where a clip
 * should be is the most obvious way this stopped feeling like the app. Muted
 * and looping, because a shot list full of clips that each demand attention is
 * worse than one that does not move at all.
 *
 * **The trim is honoured**, the same non-destructive in/out the app draws: the
 * file is never touched, so the range is applied while playing rather than cut.
 */
/** The frame that stands for a shot: the chosen one, else the first. */
function keyFrame(row) {
  const stills = row.stills || [];
  return stills.find((s) => s.key) || stills[0] || row.frame || null;
}

/**
 * **Is this file a clip?** The engine's word first, the filename only when it
 * did not say — `Ingest.isMovie(ext, kind:)`, which is where a GIF handed to a
 * video player came from. A GIF is not a movie: it goes round on its own and
 * wears no play mark, in the app and here.
 */
function isMovie(m) {
  if (!m) return false;
  if (m.kind) return m.kind === "video";
  return /\.(mp4|mov|m4v|webm|avi)$/i.test(m.filename || "");
}

/** A picture the shot claims but the portal has nothing to draw — the app's `photo`. */
const NO_PICTURE =
  `<svg class="nopic" viewBox="0 0 22 18" fill="none" stroke="currentColor" stroke-width="1.3"
     stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
     <rect x="1.4" y="2.2" width="19.2" height="13.6" rx="2.6"></rect>
     <path d="M2 13.6 7.5 8.4l3.9 3.5 3.1-2.5 5.5 4.4"></path>
     <circle cx="7.1" cy="6.4" r="1.35"></circle>
   </svg>`;

/**
 * **The two marks the app draws on a still, and only those two.**
 *
 * A play triangle at the top left when the frame is a clip, and how many frames
 * the shot has at the bottom right when it has more than one — `Thumbnail` in
 * `studio/Sources/Table.swift` and the storyboard card in `Storyboard.swift`
 * put them in exactly those corners, at exactly those moments.
 *
 * **The document page gets neither**, because the app's does not: a page of
 * paper carries prose and pictures and no furniture. That is a rule, not an
 * omission — don't add them there later.
 */
function stillMarks(row) {
  const stills = row.stills || [];
  const count = typeof row.frames === "number" ? row.frames : stills.length;
  const play = isMovie(keyFrame(row))
    ? `<span class="playmark"><svg viewBox="0 0 10 10" aria-hidden="true"><path d="M3.1 2.1 7.7 5 3.1 7.9Z"></path></svg></span>`
    : "";
  const more = count > 1 ? `<span class="more">${count}</span>` : "";
  return play + more;
}

/**
 * **The frames a shot draws side by side**, and how many of them.
 *
 * His answer, Ref 78: *"side by side if it shows a series of storyboards that
 * represent one shot."* Which is what several frames on one shot usually are —
 * a move drawn in three panels, not three candidate frames — and one thumbnail
 * with a number beside it could not tell him which he was looking at.
 *
 * `limit` is the table's four, the point past which a panel stops being a
 * picture and becomes a stamp; the rest are counted. The document passes none,
 * because the app's document draws every frame in a row.
 */
function panels(row, limit) {
  const shown = (row.stills || []).filter((m) => m && m.hash);
  return limit ? shown.slice(0, limit) : shown;
}

function framePanel(row, m, i, klass) {
  return `<button class="${klass}" style="aspect-ratio:${ratio()}" data-open="${esc(row.placement || "")}" data-at="${i}" title="Open">${mediaTag(m)}</button>`;
}

function frameCell(row) {
  const shown = panels(row, 4);
  if (shown.length > 1) {
    // **The box is as tall as the panels and no taller.** Each one keeps the
    // film's shape and they share the width, so two frames do not draw a band
    // of air above and below them — his note, and the reason the app's own
    // strip sets its height from a panel rather than from the cell.
    const over = (typeof row.frames === "number" ? row.frames : shown.length) - shown.length;
    return `<span class="frames">${shown.map((m, i) => framePanel(row, m, i, "pane")).join("")}${
      over > 0 ? `<span class="more">+${over}</span>` : ""
    }</span>`;
  }
  const key = keyFrame(row);
  if (!key || !key.hash) return `<span class="frame empty" style="aspect-ratio:${ratio()}">${NO_PICTURE}</span>`;
  return `<button class="frame" style="aspect-ratio:${ratio()}" data-open="${esc(row.placement || "")}" title="Open">${mediaTag(key)}${stillMarks(row)}</button>`;
}

/** Where a file lives, and what tag can show it. */
function mediaSrc(m, extension) {
  return `/f/${HUB.project}/media/${m.hash.slice(0, 32)}.${extension}`;
}

function extensionOf(m) {
  return (m.filename || "").split(".").pop().toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) || "png";
}

/**
 * How a picture is framed inside its box — the app's `Framed`, in CSS.
 *
 * The app scales the picture to cover the box, multiplies by `cropScale`, and
 * offsets it by `(0.5 - cropX)` of the overflow. `object-fit: cover` with
 * `object-position` is exactly that: an anchor of 1 shows the right-hand edge,
 * 0 the left, 0.5 the middle. **He noticed some pictures ignoring their crop**,
 * and they were: this was not being read at all, so every frame sat centred.
 */
function framing(m) {
  const x = typeof m.cropX === "number" ? m.cropX : 0.5;
  const y = typeof m.cropY === "number" ? m.cropY : 0.5;
  const scale = typeof m.cropScale === "number" && m.cropScale > 0 ? m.cropScale : 1;
  const bits = [`object-position:${(x * 100).toFixed(2)}% ${(y * 100).toFixed(2)}%`];
  if (scale !== 1) bits.push(`transform:scale(${scale});transform-origin:${(x * 100).toFixed(2)}% ${(y * 100).toFixed(2)}%`);
  return bits.join(";");
}

function mediaTag(m, big) {
  if (!m || !m.hash) return "";
  // **The arrows travel with the picture, and are laid on it after it loads.**
  // Where they go depends on the photograph's own shape, which only the browser
  // knows once it has the file — so the tag carries the engine's line and
  // `layMarks` does the rest. `.marked` is the wrapper the pop-out needs: there
  // the picture is shown whole and sized by its own pixels, so the overlay has
  // to lie on the picture's rectangle rather than on the box around it. In a
  // list the frame *is* that rectangle and no wrapper is wanted.
  const marks = m.arrows ? ` data-marks="${esc(m.arrows)}"` : "";
  const wrap = (tag) => (big ? `<span class="marked">${tag}</span>` : tag);
  // A filmstrip of playing clips is a wall of movement nobody can read, so a
  // thumbnail of a clip is its poster. The app does the same.
  if (m.kind === "image" && m.filename && /\.(mp4|mov|m4v|gif)$/i.test(m.filename)) {
    return wrap(`<img alt="" loading="lazy" style="${framing(m)}"${marks} src="${mediaSrc(m, POSTER)}">`);
  }
  if (m.kind === "video") {
    const trim = ` data-in="${m.trimStart || 0}" data-out="${m.trimEnd || 0}"`;
    const src = mediaSrc(m, extensionOf(m));
    // A poster is a JPEG since 2026-09-15 — `POSTER`, above.
    const poster = mediaSrc(m, POSTER);
    if (big) {
      return wrap(`<video style="${framing(m)}"${marks} src="${src}" poster="${poster}" muted loop playsinline autoplay preload="auto"${trim}></video>`);
    }
    // **In a list it begins as its poster.** A page holding twenty-two video
    // elements asks a browser for twenty-two decoders and it will not give
    // them — one clip plays and the rest sit still, which is exactly what he
    // reported. So a clip in the list is a picture until it is looked at, and
    // `playWhatIsSeen` turns the few nearest the middle into real players.
    return wrap(`<img class="clip" alt="" loading="lazy" style="${framing(m)}"${marks} src="${poster}"
      data-clip="${esc(src)}" data-poster="${esc(poster)}"${trim}>`);
  }
  if (m.kind === "gif") return wrap(`<img alt="" loading="lazy" style="${framing(m)}"${marks} src="${mediaSrc(m, extensionOf(m))}">`);
  return wrap(`<img alt="" loading="${big ? "eager" : "lazy"}" style="${framing(m)}"${marks} src="${mediaSrc(m, extensionOf(m))}">`);
}

/**
 * Keep a clip inside its trim.
 *
 * The range lives on the *use* of the file, never on the file, so there is
 * nothing to cut — the player is simply held between the two marks.
 */
/**
 * Play what is on screen, and only that.
 *
 * His ask was that clips autoplay. The naive reading — `autoplay` on every clip
 * — asks the browser to fetch a couple of hundred megabytes for a page somebody
 * scrolls past, so it refuses, one clip plays and the rest sit still. That
 * looks like a bug and is really a page asking for something silly.
 *
 * **Measured rather than observed.** `IntersectionObserver` was the obvious
 * tool and it never fired once in the browser this was checked in — a fresh
 * one, on a visible element, no callback. Rather than ship a thing I could not
 * watch work, this is arithmetic on rectangles: it runs after every redraw and
 * on scroll, and it can be verified by asking which clips are playing.
 */
function playWhatIsSeen() {
  const height = viewportHeight();
  const middle = height / 2;
  // **Measure the box it sits in, never the media itself.** A freshly made
  // `<video>` measures nought until it has loaded something, so measuring it
  // judged it off screen the instant after it was created — and it was swapped
  // straight back to a picture, for ever, with no error anywhere to say so.
  // The frame around it always has a size.
  let swapped = false;
  const boxOf = (el) => frameOf(el).getBoundingClientRect();
  const near = (el) => {
    const box = boxOf(el);
    if (box.bottom <= 0 || box.top >= height || box.width === 0) return Infinity;
    return Math.abs((box.top + box.bottom) / 2 - middle);
  };

  // The few nearest the middle of the window become players; everything else
  // goes back to being a picture, which hands its decoder back.
  const clips = [...root.querySelectorAll("img.clip, video.clip")]
    .map((el) => ({ el, distance: near(el) }))
    .filter((c) => c.distance !== Infinity)
    .sort((a, b) => a.distance - b.distance);

  // **Kept by frame, not by element.** Swapping a picture for a player replaces
  // the element, so a set of elements gathered before the swap does not contain
  // what the swap produced — and the same pass that swapped it in swapped it
  // straight back out. Nothing errored; the clip simply never played.
  const keep = new Set(clips.slice(0, LIVE_CLIPS).map((c) => frameOf(c.el)));

  for (const { el } of clips) {
    if (el.tagName === "IMG" && keep.has(frameOf(el))) { swapIn(el); swapped = true; }
  }
  for (const el of root.querySelectorAll("video.clip")) {
    if (!keep.has(frameOf(el))) swapOut(el);
    // A clip he stopped stays stopped; one he is dragging through is his.
    else if (el.paused && !el.dataset.held && !el.dataset.scrubbing) el.play().catch(() => {});
  }
  // A clip that has just become a player has not been marked yet. Only when one
  // actually has: this runs on every frame of a scroll.
  if (swapped) drawMarks();
}

/**
 * **How wide the storyboard column is**, which is his to decide.
 *
 * 132 is the app's own default — `Columns.width("image")` in
 * `studio/Sources/Table.swift` — so a film opened here for the first time looks
 * like the film on his Mac. Kept per film, in this browser only: it is how one
 * person likes to look at one film, not a fact about the film, and writing it
 * into the change logs would push it onto everybody else who opens it.
 *
 * The bounds are the app's own sense of it: narrower than 66 and a frame is a
 * smudge, wider than 520 and the table is a contact sheet with captions.
 */
/**
 * A column's name as a custom property can carry — a project may call a column
 * of its own anything at all, and `--w-shot size` is not a property.
 */
function slug(name) {
  return String(name).replace(/[^A-Za-z0-9_-]/g, "_");
}

/** Every width he has set, for this film, in this browser. */
function keptWidths() {
  let kept = {};
  // Storage can be off entirely — a private window, or a browser told to keep
  // nothing. That is not a reason for the table to fail to draw.
  try {
    kept = JSON.parse(localStorage.getItem(WIDTHS_KEY) || "{}") || {};
    // The storyboard column could be dragged a day before the others could.
    // Fold that one key in rather than losing the width he had set.
    const first = Number(localStorage.getItem(FRAME_WIDTH_KEY));
    if (first && kept.image === undefined) {
      kept.image = first;
      localStorage.setItem(WIDTHS_KEY, JSON.stringify(kept));
    }
    localStorage.removeItem(FRAME_WIDTH_KEY);
  } catch {}
  return kept && typeof kept === "object" ? kept : {};
}

function rememberWidths(kept) {
  try { localStorage.setItem(WIDTHS_KEY, JSON.stringify(kept)); } catch {}
}

/** Put every width he has set on the page, where `gridTemplate` reads them. */
function applyWidths() {
  const kept = keptWidths();
  for (const [name, px] of Object.entries(kept)) {
    const width = Number(px);
    if (width >= COLUMN_MIN && width <= COLUMN_MAX) {
      root.style.setProperty(`--w-${slug(name)}`, `${width}px`);
    }
  }
}

function setColumnWidth(name, px, remember) {
  const width = Math.round(Math.min(COLUMN_MAX, Math.max(COLUMN_MIN, px)));
  root.style.setProperty(`--w-${slug(name)}`, `${width}px`);
  if (remember) {
    const kept = keptWidths();
    kept[name] = width;
    rememberWidths(kept);
  }
  return width;
}

/** Back to the width the column is drawn with when nobody has touched it. */
function forgetColumnWidth(name) {
  root.style.removeProperty(`--w-${slug(name)}`);
  const kept = keptWidths();
  delete kept[name];
  rememberWidths(kept);
}

/**
 * **Dragging a column's edge.**
 *
 * Each width lives in one custom property on the page, so a drag sets one value
 * and every row follows it in the same frame — redrawing the table on each
 * mouse move would be a table of sixty shots rebuilt a hundred times a second.
 *
 * **The width a drag starts from is measured, not remembered**, because most
 * columns have never been dragged and are drawn from a rule rather than a
 * number: `minmax(200px, 2.2fr)` is a real width on screen and nowhere else.
 * The heading cell is the track, so its own rectangle is the answer.
 *
 * A pointer capture rather than window listeners: the pointer keeps reporting
 * to the grip even when it leaves it, which is most of a drag, and it ends
 * cleanly if the browser takes the pointer away.
 */
function dragColumn(grip) {
  const name = grip.dataset.grip;
  grip.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    const from = event.clientX;
    const was = grip.parentElement.getBoundingClientRect().width;
    grip.setPointerCapture(event.pointerId);
    grip.classList.add("on");
    let width = was;
    const move = (moved) => { width = setColumnWidth(name, was + (moved.clientX - from), false); };
    const done = () => {
      grip.releasePointerCapture(event.pointerId);
      grip.classList.remove("on");
      grip.removeEventListener("pointermove", move);
      setColumnWidth(name, width, true);
    };
    grip.addEventListener("pointermove", move);
    grip.addEventListener("pointerup", done, { once: true });
    grip.addEventListener("pointercancel", done, { once: true });
  });
  // Back to the width the table chose for it. A column dragged to the stop and
  // left there is otherwise a thing he cannot undo without knowing the number.
  grip.addEventListener("dblclick", () => forgetColumnWidth(name));
}

/** The film's own aspect ratio. Every frame is cut to it, as the app cuts them. */
function ratio() {
  const said = Number(model && model.project && model.project.ratio);
  return said && said > 0.2 ? said : 16 / 9;
}

/**
 * **The storyboard arrows, laid on the photographs that carry them.**
 *
 * The shape is never worked out here. `arrows` in `web/src/lib.rs` hands back
 * the engine's own outline as a finished SVG — the same arithmetic SwiftUI
 * strokes on the Mac and the printed page prints — and this only decides where
 * it lies.
 *
 * **Where is the easy half, because it is not decided here either.** The
 * overlay is an `<img>` wearing the photograph's own inline style, so the crop
 * places both with one set of numbers and there is nothing to keep in step. The
 * SVG carries the photograph's pixels as its size, which is what makes
 * `object-fit: cover` cut the marks exactly where it cuts the picture.
 *
 * **After the file has loaded, because only then is its shape known.** An arrow
 * is stored as a fraction of the picture, so its shape belongs to the picture's
 * shape, and nothing in the change logs says what that is.
 */
function drawMarks() {
  for (const picture of root.querySelectorAll("[data-marks]")) {
    if (picture.dataset.marked) continue;
    if (picture.naturalWidth || picture.videoWidth) layMarks(picture);
    else {
      // A picture says `load`; a clip says `loadedmetadata`, and not before —
      // a `<video>` measures nought until it has read the file's header.
      picture.addEventListener("load", () => layMarks(picture), { once: true });
      picture.addEventListener("loadedmetadata", () => layMarks(picture), { once: true });
    }
  }
}

function layMarks(picture) {
  if (!picture.isConnected || picture.dataset.marked) return;
  const w = picture.naturalWidth || picture.videoWidth;
  const h = picture.naturalHeight || picture.videoHeight;
  if (!w || !h) return;
  picture.dataset.marked = "1";
  const drawn = arrowsFor(picture.dataset.marks, w, h);
  if (!drawn) return;
  const over = document.createElement("img");
  over.className = "marks";
  over.alt = "";
  over.src = `data:image/svg+xml,${encodeURIComponent(drawn)}`;
  over.style.cssText = picture.style.cssText;
  // Whatever this view does to the photograph, do to the marks. The pop-out
  // shows a picture whole and a list cuts it; neither is decided here.
  over.style.objectFit = getComputedStyle(picture).objectFit;
  picture.after(over);
}

/**
 * Ask the engine for one picture's marks, once.
 *
 * The answer depends on the line and the photograph's shape and nothing else,
 * so it is worth keeping: a table of sixty shots redraws on every keystroke of
 * a search.
 */
const MARKS = new Map();
function arrowsFor(line, w, h) {
  if (!wasm || !line) return "";
  const memo = `${w}x${h}|${line}`;
  if (!MARKS.has(memo)) {
    const [pointer, length] = put(line);
    MARKS.set(memo, take(wasm.arrows(pointer, length, w, h)));
    wasm.dealloc(pointer, length);
  }
  return MARKS.get(memo);
}

/** The box a clip sits in, which always has a size even when the clip does not. */
function frameOf(el) {
  return el.closest(".frame, .pane, .cardframe, .docframe, .tile") || el;
}

function swapIn(picture) {
  const video = document.createElement("video");
  video.className = "clip";
  video.src = picture.dataset.clip;
  video.poster = picture.dataset.poster;
  // **The attributes as well as the properties.** iOS decides whether a play
  // with no tap behind it is allowed by looking at the element's attributes,
  // and a `<video>` built in script carries none — so a clip that was muted
  // and inline by every property Safari could read was still refused, silently,
  // as an unmuted autoplay. Both, so both readings agree.
  video.muted = true;
  video.defaultMuted = true;
  video.setAttribute("muted", "");
  video.setAttribute("playsinline", "");
  video.setAttribute("webkit-playsinline", "");
  video.setAttribute("autoplay", "");
  video.loop = true;
  video.setAttribute("loop", "");
  video.playsInline = true;
  video.preload = "auto";
  video.dataset.clip = picture.dataset.clip;
  video.dataset.poster = picture.dataset.poster;
  video.style.cssText = picture.style.cssText;
  video.dataset.in = picture.dataset.in || "0";
  video.dataset.out = picture.dataset.out || "0";
  // **The marks are the clip's, not the poster's.** Without this a clip near
  // the middle of the page — the ones that become real players — lost every
  // arrow drawn on it the moment it started playing.
  if (picture.dataset.marks) video.dataset.marks = picture.dataset.marks;
  if (picture.dataset.marked) video.dataset.marked = picture.dataset.marked;
  picture.replaceWith(video);
  holdOne(video);
  clipControls(video, false);
  if (!video.dataset.held) {
    video.play().catch(() => {});
    video.addEventListener("canplay", () => { if (!video.dataset.held) video.play().catch(() => {}); }, { once: true });
  }
}

function swapOut(video) {
  const picture = document.createElement("img");
  picture.className = "clip";
  picture.alt = "";
  picture.src = video.dataset.poster;
  picture.dataset.clip = video.dataset.clip;
  picture.dataset.poster = video.dataset.poster;
  picture.style.cssText = video.style.cssText;
  picture.dataset.in = video.dataset.in || "0";
  picture.dataset.out = video.dataset.out || "0";
  if (video.dataset.marks) picture.dataset.marks = video.dataset.marks;
  if (video.dataset.marked) picture.dataset.marked = video.dataset.marked;
  rememberClip(video);
  const bar = clipHost(video).querySelector(":scope > .vctl");
  if (bar) bar.remove();
  video.pause();
  // Emptying the source is what actually hands the decoder back; pausing alone
  // does not.
  video.removeAttribute("src");
  video.load();
  video.replaceWith(picture);
}


/**
 * How tall the window is — and never nought.
 *
 * **`window.innerHeight` can be nought.** It was, in the browser this was
 * checked in: `innerHeight`, `documentElement.clientHeight`,
 * `body.clientHeight` and `visualViewport.height` all reported nought while the
 * page was plainly laid out and seven thousand pixels tall. A viewport of
 * nought means nothing is ever on screen, so nothing would ever play — and it
 * would fail *silently*, which is the worst way for this to be wrong.
 *
 * So: ask each in turn, and end at the screen rather than at nought.
 */
function viewportHeight() {
  return (
    window.innerHeight ||
    document.documentElement.clientHeight ||
    (window.visualViewport && window.visualViewport.height) ||
    (window.screen && window.screen.height) ||
    800
  );
}

/**
 * Ask again once a clip is ready to play.
 *
 * **The first ask is usually too early.** `playWhatIsSeen` runs the moment the
 * page is drawn, when a clip has fetched nothing yet; `play()` hands back a
 * promise that quietly rejects, and because that rejection was swallowed the
 * clip stayed paused for ever. One clip on screen, ready, and still — with no
 * error anywhere to say why.
 */
function retryWhenReady(root) {
  root.querySelectorAll("video").forEach((video) => {
    video.addEventListener("canplay", () => playWhatIsSeen(), { once: true });
    video.addEventListener("loadeddata", () => playWhatIsSeen(), { once: true });
  });
  // A clip's poster arriving is the moment its box first has a real size.
  root.querySelectorAll("img.clip").forEach((picture) => {
    picture.addEventListener("load", () => playWhatIsSeen(), { once: true });
  });
}

/** One listener for the life of the page, not one per redraw. */
let watching = false;
function watchScrolling() {
  if (watching) return;
  watching = true;
  let waiting = false;
  const soon = () => {
    if (waiting) return;
    waiting = true;
    requestAnimationFrame(() => {
      waiting = false;
      playWhatIsSeen();
    });
  };
  window.addEventListener("scroll", soon, true);
  window.addEventListener("resize", soon);
}

function holdTrim(root) {
  root.querySelectorAll("video[data-in]").forEach(holdOne);
}

/**
 * Keep one clip inside its trim.
 *
 * The range lives on the *use* of the file, never on the file, so there is
 * nothing to cut — the player is simply held between the two marks.
 */
function holdOne(video) {
  const from = Number(video.dataset.in) || 0;
  const to = Number(video.dataset.out) || 0;
  // **Where it was, and whether he had stopped it**, from before the redraw or
  // the scroll that replaced it.
  const kept = CLIP_AT.get(clipKey(video));
  if (kept && kept.held) {
    video.dataset.held = "1";
    video.autoplay = false;
    video.removeAttribute("autoplay");
    video.pause();
  }
  const at = kept && kept.t >= from && (!(to > from) || kept.t < to) ? kept.t : from;
  if (at) video.addEventListener("loadedmetadata", () => { video.currentTime = at; }, { once: true });
  if (!from && !to) return;
  video.addEventListener("timeupdate", () => {
    if (video.dataset.scrubbing) return;
    if (to > from && video.currentTime >= to) video.currentTime = from;
    else if (video.currentTime < from - 0.05) video.currentTime = from;
  });
}

/**
 * **Where each clip was, and whether he stopped it** — his ask, 2026-10-09:
 * *"no control over the loop its in, to stop it or scrub it"*.
 *
 * A clip in the list is a picture until it is near the middle of the page,
 * and every redraw makes every clip again, so the element is never the thing
 * to keep this on. It is kept by file instead: the same clip opened in the
 * pop-out carries on from where the list had it, and one he stopped is still
 * stopped when he scrolls back to it.
 */
const CLIP_AT = new Map();

function clipKey(video) {
  return video.dataset.clip || video.getAttribute("src") || "";
}

function rememberClip(video) {
  const key = clipKey(video);
  if (!key || !video.readyState) return;
  CLIP_AT.set(key, { t: video.currentTime, held: Boolean(video.dataset.held) });
}

/** The box a clip's controls lie in: the pop-out's plate, or the frame. */
function clipHost(video) {
  return video.closest(".plate") || frameOf(video);
}

/** Play or stop, and say which he chose, so nothing starts it again behind him. */
function toggleClip(video) {
  if (video.paused) {
    delete video.dataset.held;
    video.play().catch(() => {});
  } else {
    video.dataset.held = "1";
    video.pause();
  }
  rememberClip(video);
}

/** `0:07`, or `1:02:07` for anything that long. */
function clock(seconds) {
  const s = Math.max(0, Math.floor(seconds || 0));
  const two = (n) => String(n).padStart(2, "0");
  return s >= 3600 ? `${Math.floor(s / 3600)}:${two(Math.floor(s / 60) % 60)}:${two(s % 60)}` : `${Math.floor(s / 60)}:${two(s % 60)}`;
}

/**
 * **Play, stop and scrub, laid along the bottom of a clip.**
 *
 * Spans, not buttons or a range input: in the list a clip sits *inside* the
 * frame's button, and a control inside a button is not allowed and is not
 * reliably clicked. So these swallow their own clicks, and the frame still
 * opens the pop-out when the picture itself is clicked.
 *
 * The bar runs over the clip's trim, not the whole file, because the trim is
 * the clip as far as the shot is concerned. A frame too small to hold a bar
 * gets none; the pop-out is a click away.
 */
function clipControls(video, big) {
  const host = clipHost(video);
  if (!host || host.querySelector(":scope > .vctl")) return;
  if (!big && host.getBoundingClientRect().width < 84) return;
  if (getComputedStyle(host).position === "static") host.style.position = "relative";
  const bar = document.createElement("span");
  bar.className = "vctl";
  bar.dataset.stop = "1";
  bar.innerHTML = `<span class="vplay" role="button" tabindex="0"></span>
    <span class="vtrack" role="slider" aria-label="Scrub" title="Scrub"><span class="vfill"></span><span class="vknob"></span></span>
    ${big ? `<span class="vtime"></span>` : ""}`;
  host.append(bar);
  const play = bar.querySelector(".vplay");
  const track = bar.querySelector(".vtrack");
  const fill = bar.querySelector(".vfill");
  const knob = bar.querySelector(".vknob");
  const time = bar.querySelector(".vtime");

  // The clip's window: its trim when it has one, else the whole file.
  const from = () => Number(video.dataset.in) || 0;
  const to = () => {
    const out = Number(video.dataset.out) || 0;
    return out > from() ? out : video.duration || 0;
  };

  const show = () => {
    const playing = !video.paused;
    play.innerHTML = mark(playing ? "pause" : "play", big ? 18 : 14);
    play.title = playing ? "Pause" : "Play";
    play.setAttribute("aria-label", play.title);
    bar.classList.toggle("held", !playing);
  };
  const place = () => {
    const span = to() - from();
    const part = span > 0 ? Math.min(1, Math.max(0, (video.currentTime - from()) / span)) : 0;
    fill.style.width = `${part * 100}%`;
    knob.style.left = `${part * 100}%`;
    if (time && span > 0) time.textContent = `${clock(video.currentTime - from())} / ${clock(span)}`;
  };
  // Every frame while it is on the page, so the bar glides rather than
  // stepping four times a second the way `timeupdate` would move it.
  const follow = () => {
    if (!bar.isConnected) return;
    place();
    requestAnimationFrame(follow);
  };
  requestAnimationFrame(follow);
  video.addEventListener("play", show);
  video.addEventListener("pause", show);
  show();

  // None of this reaches the frame underneath, which would open the pop-out,
  // nor the shooting order's drag, which listens on the whole page.
  for (const kind of ["click", "pointerdown", "dblclick"]) {
    bar.addEventListener(kind, (event) => event.stopPropagation());
  }
  bar.addEventListener("click", (event) => event.preventDefault());
  play.addEventListener("click", () => toggleClip(video));
  play.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") { event.preventDefault(); event.stopPropagation(); toggleClip(video); }
  });

  // **Scrubbing.** Held to the pointer for the whole drag, stopped while it
  // moves, and playing again afterwards only if it was playing before.
  track.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    const wasPlaying = !video.paused;
    video.dataset.scrubbing = "1";
    video.pause();
    track.setPointerCapture(event.pointerId);
    bar.classList.add("scrub");
    const seek = (e) => {
      const box = track.getBoundingClientRect();
      const part = Math.min(1, Math.max(0, (e.clientX - box.left) / (box.width || 1)));
      const end = to();
      if (end > from()) video.currentTime = from() + part * (end - from()) * 0.999;
      place();
    };
    seek(event);
    const done = () => {
      track.removeEventListener("pointermove", seek);
      bar.classList.remove("scrub");
      delete video.dataset.scrubbing;
      if (wasPlaying && !video.dataset.held) video.play().catch(() => {});
      rememberClip(video);
    };
    track.addEventListener("pointermove", seek);
    track.addEventListener("pointerup", done, { once: true });
    track.addEventListener("pointercancel", done, { once: true });
  });
}

// ----------------------------------------------------------------- plumbing

/**
 * Where a picture lives.
 *
 * **The same rule as `picture_at` in `web/src/lib.rs`**, deliberately: the
 * hash's first thirty-two characters and the file's own extension, except a
 * moving picture, which is drawn by its poster and so always ends `.jpg`. If
 * one of the two changes the other has to.
 */
function picture(frame) {
  // **One way to draw a piece of media, not two.** This was a second copy of
  // `mediaTag`'s rule and they had already begun to differ — this one could not
  // play a clip, so a video on a mood board drew as a still while the same
  // video in the shot list moved.
  return mediaTag(frame);
}

/**
 * A value that may be a word or may be a record.
 *
 * A camera comes through as `{id, label, colour}` where a lens comes through as
 * text, and drawing one the way you draw the other puts `[object Object]` on
 * his shot list — which it did, on the first run of this screen.
 */
function named(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  return String(value.label || value.title || value.name || "");
}

/**
 * The written words, most specific first — **the order is the whole point.**
 * `NIGHTFALL` has to be looked for before `NIGHT` and `DAYBREAK` before `DAY`,
 * or a sky going dark reads as full night and a sunrise reads as noon. The
 * same list `Brand.timeWords` holds in `Theme.swift`.
 */
const TIME_WORDS = [
  ["MAGIC", "sunset"], ["GOLDEN", "sunset"],
  ["SUNSET", "sunset"], ["SUNDOWN", "sunset"], ["EVENING", "sunset"],
  ["NIGHTFALL", "sunset"], ["TWILIGHT", "sunset"], ["DUSK", "sunset"],
  ["SUNRISE", "sunrise"], ["DAYBREAK", "sunrise"], ["SUNUP", "sunrise"],
  ["DAWN", "sunrise"],
  ["MIDNIGHT", "night"], ["NIGHT", "night"],
  ["MORNING", "day"], ["AFTERNOON", "day"],
  ["NOON", "day"], ["MIDDAY", "day"], ["DAY", "day"],
];

/**
 * The colours the app draws a scene's time of day in — `Brand.timeKeyInk`.
 *
 * A temperature scale, not three buckets: night the coolest, sunrise second,
 * day the brightest, sunset the warmest. The four values live in `hub.css` as
 * `--tod-*` so the dark ground gets lifted ones for free.
 */
function timeInk(said) {
  const word = String(said || "").toUpperCase();
  if (!word) return "transparent";
  for (const [needle, key] of TIME_WORDS) if (word.includes(needle)) return `var(--tod-${key})`;
  // CONTINUOUS and LATER get no dot on purpose: they mean "the same as the
  // scene before", and inventing a colour would invent a fact the script did
  // not give.
  return "transparent";
}

/**
 * The screen while the film is being read.
 *
 * **It is the first thing anybody sees on a link he sends**, and it used to be
 * the film's name in grey with a line of text under it. His instruction,
 * 2026-09-02: it should carry the film's own mark and colour and have something
 * moving in it. So it does — the mark in the film's colour, the name, and a
 * thin bar travelling underneath.
 *
 * The mark is the same outline the film's page draws and the bar wears the same
 * colour, so a crew member opening a link meets the film before they meet the
 * program.
 */
function waiting(said) {
  return `<div class="signin booting"${accent()}>
    ${filmMark()}
    <div class="wordmark">${esc(HUB.title)}</div>
    <p class="empty">${esc(said)}</p>
    <div class="bootbar"><i></i></div>
  </div>`;
}

async function api(path, asText) {
  const got = await fetch(`/f/${HUB.project}/api/${path}`, { headers: { accept: "*/*" } });
  if (!got.ok) throw new Error(`${got.status}`);
  return asText ? await got.text() : await got.json();
}

function bytes() {
  return new Uint8Array(memory.buffer);
}

function put(text) {
  const encoded = new TextEncoder().encode(text);
  const pointer = wasm.alloc(encoded.length);
  bytes().set(encoded, pointer);
  return [pointer, encoded.length];
}

function take(pointer) {
  const length = new DataView(memory.buffer).getUint32(pointer, true);
  const text = new TextDecoder().decode(bytes().slice(pointer + 4, pointer + 4 + length));
  wasm.free_result(pointer);
  return text;
}

function initials() {
  if (!HUB.email) return "·";
  const name = HUB.email.split("@")[0].replace(/[^A-Za-z]+/g, " ").trim().split(/\s+/).filter(Boolean);
  if (!name.length) return HUB.email[0].toUpperCase();
  return (name[0][0] + (name[1] ? name[1][0] : "")).toUpperCase();
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );
}

/**
 * **The film's colour is the app's highlight.** His instruction, 2026-09-02:
 * the tabs and Share should wear the colour the film wears everywhere else,
 * rather than the program's own blue. `--accent` is the one token this chrome
 * hangs its highlight on, so setting it here colours the mode capsule, Share
 * and the lit icons together and nothing else has to know.
 *
 * `--on-accent` stays white: these are Notion's own icon colours, all
 * mid-toned and saturated enough to carry white type, and the app already
 * assumes a light mark on a filled capsule.
 */
function accent() {
  const hue = HUB.mark && HUB.mark.colour;
  if (!/^#[0-9A-Fa-f]{6}$/.test(String(hue || ""))) return "";
  return ` style="--accent:${hue};--accent-tint:color-mix(in srgb,${hue} 14%,transparent);` +
    `--accent-line:color-mix(in srgb,${hue} 38%,transparent);--on-accent:#fff"`;
}

/**
 * A redraw you can see happen.
 *
 * **The app redrew instantly and it read as a flicker, not a move.** His
 * instruction, 2026-09-02: more motion between tabs and sidebars, and a less
 * cheap feel. The capsule behind the mode you are in carries a
 * `view-transition-name`, so it *slides* from one word to the next rather than
 * blinking out and in — which is the whole trick, and it costs one line.
 *
 * Anything unexpected, or a browser without transitions, still just redraws.
 */
function travelled(change, how = "views") {
  if (!document.startViewTransition) return change();
  // **A class the whole time it runs.** These pages are reached two ways — a
  // plain load, and swapped in from the film's page, which brings `front.css`
  // and its own transition rules with it. Naming this move means the app's
  // rules apply either way instead of inheriting whichever stylesheet happened
  // to be there. It comes off on `finished`, not inside the callback: the
  // browser reads these styles *after* the callback returns, and taking the
  // class off too early is exactly how the front of house came to hard-cut.
  // **What changed decides what may move.** Switching Table to Storyboard does
   // not touch the scene list, so fading it out and back in is a flash over
   // something that never changed — which is most of what he felt as a pop.
   // Only a pane actually opening or closing gets to animate the panes.
  const root = document.documentElement;
  root.classList.add("appmove", how);
  const moving = document.startViewTransition(change);
  // **A move that is cut short still has to tidy up, quietly.** A second
  // transition starting while this one is pending skips it, and `finished`
  // *rejects* — `finally` alone leaves that rejection with nobody to catch it,
  // which is a red "Transition was skipped" in the console on a move that
  // otherwise worked. `deep.js` catches its three the same way; found on the
  // phone's Back, 2026-09-16.
  moving.finished.finally(() => root.classList.remove("appmove", how)).catch(() => {});
}

/**
 * **The app sits in the same frame as everything else.** `.fh2 .deep` is the
 * portal's one layout — rail, then pane — and `hub.css` still dresses
 * everything inside the pane, so the table, the storyboard and the document
 * page are untouched. What changed is that they are no longer in a different
 * building.
 */
/**
 * **A pop-out has to be over the portal's phone chrome, not under it.**
 *
 * On a phone the portal keeps a fixed bar at the top and its rail along the
 * foot, at z-index 20 and 40 — and the app lives inside `.fh-pane`, which
 * `view-transition-name: pane` makes a stacking context of its own. So a
 * pop-out inside it could not paint over them however high its own z-index
 * went, and the room opened up with the film's name and Download hidden behind
 * that top bar. `popped` lifts the whole pane for as long as something is open,
 * which is the only place the fix can go.
 */
function paint(markup) {
  const over = openShot || openRoom ? " popped" : "";
  root.innerHTML = `<div class="fh2 deep appframe${over}"${accent()}>${appRail()}${appPhoneParts()}<main class="paneshell"><div class="fh-pane"><div class="app">${markup}</div></div></main></div>`;
}

// ------------------------------------------------------- shooting order drag

/**
 * **Shots dragged into a day's shooting order** — his ask, 2026-10-05: the
 * Mac Schedule's Shooting Order, on the portal too. The same bargain as the
 * rail's drag (`public/arrange.js`): one listener on the document, so a
 * repaint costs nothing; a mouse press is a drag once it has travelled
 * `RUN_SLOP` pixels, a finger has to hold still `RUN_HOLD` first or it is a
 * scroll; the row itself becomes the line where it will land and a chip with
 * its number follows the pointer. Let go, the place is said to the server as
 * a place in the whole day (`data-whole`, shots another shoot hides
 * included) and the film is read again.
 *
 * Only an editor's sheet carries `data-runs`; the server says no to anyone
 * else whatever the page drew.
 */
const RUN_SLOP = 6;
const RUN_HOLD = 400;

document.addEventListener("touchmove", (event) => {
  if (document.body.classList.contains("runholding") && event.cancelable) event.preventDefault();
}, { passive: false });

document.addEventListener("pointerdown", (event) => {
  if (event.pointerType === "mouse" && event.button !== 0) return;
  const row = event.target.closest && event.target.closest(".runrow[data-run]");
  if (!row) return;
  const sheet = row.closest("[data-runs]");
  if (!sheet) return;
  const startX = event.clientX, startY = event.clientY;
  const fromLane = row.closest(".lane[data-day]");
  const fromIndex = [...row.parentElement.children].indexOf(row);
  let armed = event.pointerType === "mouse";
  let dragging = false;
  let ghost = null;
  let lastY = startY;
  const hold = armed ? 0 : setTimeout(() => {
    armed = true;
    document.body.classList.add("runholding");
    row.classList.add("lifted");
    try { if (navigator.vibrate) navigator.vibrate(12); } catch { /* no buzz */ }
  }, RUN_HOLD);

  /** Which day the pointer is over — or the nearest — then where among its shots. */
  const put = (y) => {
    const lanes = [...sheet.querySelectorAll(".lane[data-day]")];
    if (!lanes.length) return;
    const boxes = lanes.map((el) => ({ el, box: el.getBoundingClientRect() }));
    const into = (boxes.find((b) => y >= b.box.top && y <= b.box.bottom)
      || boxes.reduce((a, b) => (Math.min(Math.abs(b.box.top - y), Math.abs(b.box.bottom - y))
        < Math.min(Math.abs(a.box.top - y), Math.abs(a.box.bottom - y)) ? b : a))).el;
    const runs = into.querySelector(".runs");
    if (!runs) return;
    const before = [...runs.querySelectorAll(":scope > .runrow")]
      .filter((el) => el !== row)
      .find((el) => { const b = el.getBoundingClientRect(); return y < b.top + b.height / 2; });
    runs.insertBefore(row, before || null);
    for (const lane of lanes) lane.classList.toggle("landing", lane === into);
  };

  const move = (e) => {
    const gone = Math.abs(e.clientY - startY) + Math.abs(e.clientX - startX);
    if (!dragging) {
      if (!armed) {
        if (gone > RUN_SLOP) stop(false);
        return;
      }
      if (gone < RUN_SLOP) return;
      dragging = true;
      ghost = document.createElement("div");
      ghost.className = "runghost";
      ghost.textContent = row.dataset.run;
      document.body.append(ghost);
      row.classList.add("moving");
      document.body.classList.add("runarranging");
      try { row.setPointerCapture(e.pointerId); } catch { /* a mouse already gone */ }
    }
    e.preventDefault();
    ghost.style.left = `${e.clientX + 12}px`;
    ghost.style.top = `${e.clientY - 14}px`;
    lastY = e.clientY;
    put(e.clientY);
  };
  // The well scrolls; held near its top or foot, it keeps scrolling.
  const scroller = setInterval(() => {
    if (!dragging) return;
    const well = sheet.closest(".well");
    if (!well) return;
    const box = well.getBoundingClientRect();
    const slide = lastY < box.top + 44 ? -10 : lastY > box.bottom - 44 ? 10 : 0;
    if (!slide) return;
    well.scrollTop += slide;
    put(lastY);
  }, 30);

  const up = () => stop(dragging);

  function stop(moved) {
    clearTimeout(hold);
    clearInterval(scroller);
    document.body.classList.remove("runholding", "runarranging");
    row.classList.remove("lifted");
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
    window.removeEventListener("pointercancel", up);
    if (ghost) { ghost.remove(); ghost = null; }
    sheet.querySelectorAll(".lane.landing").forEach((l) => l.classList.remove("landing"));
    if (!moved) return;
    row.classList.remove("moving");
    // Eat the click this drag is about to become, and only that one.
    const eat = (c) => { c.preventDefault(); c.stopPropagation(); window.removeEventListener("click", eat, true); };
    window.addEventListener("click", eat, true);
    setTimeout(() => window.removeEventListener("click", eat, true), 350);
    const lane = row.closest(".lane[data-day]");
    if (!lane) return draw();
    if (lane === fromLane && [...row.parentElement.children].indexOf(row) === fromIndex) return;
    seatRun(row, lane);
  }

  window.addEventListener("pointermove", move, { passive: false });
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);
});

/**
 * **Where the dropped row stands, said as a place in the whole day** — after
 * the shown shot that now follows it, or after the one before it — then kept.
 * The numbers on the rows are put right at once; the film is read again
 * once the server has kept the change, and a refusal puts the page back.
 */
async function seatRun(row, lane) {
  const shot = row.dataset.run;
  const whole = (lane.dataset.whole || "").split(",").filter((n) => n && n !== shot);
  const next = row.nextElementSibling && row.nextElementSibling.dataset.run;
  const prev = row.previousElementSibling && row.previousElementSibling.dataset.run;
  let at = whole.length;
  if (next && whole.includes(next)) at = whole.indexOf(next);
  else if (prev && whole.includes(prev)) at = whole.indexOf(prev) + 1;
  for (const runs of lane.closest("[data-runs]").querySelectorAll(".runs")) {
    [...runs.children].forEach((el, i) => { const n = el.querySelector(".at"); if (n) n.textContent = String(i + 1); });
  }
  row.classList.add("saving");
  try {
    const got = await fetch(`/f/${HUB.project}/api/shootorder`, {
      method: "PUT", headers: { "content-type": "application/json" },
      // The day by its label — `Day 2` — which the connector's `find_day`
      // reads; the page's ids are written another way than its own.
      body: JSON.stringify({ shot, day: lane.dataset.label, position: at + 1 }),
    });
    if (!got.ok) throw new Error(`${got.status} ${await got.text()}`);
    await check();
  } catch (error) {
    console.warn("could not move", shot, String(error));
    draw();
  }
}


// ------------------------------------------------- the shot list's shooting order

/**
 * **A shot carried in the shot list, sorted by Shooting Order** — his ask,
 * 2026-10-06: "Once it's in shooting order and I drag things around up and
 * down, that changes the shooting order, not the order of shots storywise."
 * The Schedule's run drag, for the rows and cards of the shot list: a mouse
 * carries after `RUN_SLOP` pixels, a finger after holding `RUN_HOLD`; a line
 * says where it will land; let go and the place is said to the server as a
 * place in that day's whole running order (`data-whole` on the day's band),
 * through the same door the Schedule uses. No number changes.
 */
document.addEventListener("pointerdown", (event) => {
  if (event.pointerType === "mouse" && event.button !== 0) return;
  const item = event.target.closest && event.target.closest("[data-shotno]");
  if (!item || !byDay() || mode !== "shots" || (view !== "table" && view !== "storyboard")) return;
  if (event.target.closest("input, select, textarea, [data-mark], [data-editref], a")) return;
  const startX = event.clientX, startY = event.clientY;
  let armed = event.pointerType === "mouse";
  let dragging = false;
  let ghost = null, line = null, lastY = startY, target = null;
  const hold = armed ? 0 : setTimeout(() => {
    armed = true;
    document.body.classList.add("runholding");
    item.classList.add("lifted");
    try { if (navigator.vibrate) navigator.vibrate(12); } catch { /* no buzz */ }
  }, RUN_HOLD);

  /** The day the pointer is under, and the shot it lands in front of there. */
  const aim = (y) => {
    const marks = [...root.querySelectorAll(".well .dayband, .well [data-shotno]")];
    let band = null, before = null, beforeEl = null, lastInBand = null;
    for (const el of marks) {
      const box = el.getBoundingClientRect();
      if (el.classList.contains("dayband")) {
        if (box.top > y && band) break;
        band = el; before = null; beforeEl = null; lastInBand = null;
        continue;
      }
      if (el === item) continue;
      if (y < box.top + box.height / 2) { if (!before) { before = el.dataset.shotno; beforeEl = el; } }
      else if (!before) lastInBand = el;
    }
    if (!band) return null;
    const edge = beforeEl ? beforeEl.getBoundingClientRect().top
      : lastInBand ? lastInBand.getBoundingClientRect().bottom
      : band.getBoundingClientRect().bottom;
    const well = root.querySelector(".well").getBoundingClientRect();
    if (!line) { line = document.createElement("div"); line.className = "shotline"; document.body.append(line); }
    line.style.top = `${edge - 1}px`;
    line.style.left = `${well.left + 8}px`;
    line.style.width = `${well.width - 16}px`;
    return { band, before };
  };

  const move = (e) => {
    const gone = Math.abs(e.clientY - startY) + Math.abs(e.clientX - startX);
    if (!dragging) {
      if (!armed) { if (gone > RUN_SLOP) stop(false); return; }
      if (gone < RUN_SLOP) return;
      dragging = true;
      ghost = document.createElement("div");
      ghost.className = "runghost";
      ghost.textContent = item.dataset.shotno;
      document.body.append(ghost);
      item.classList.add("moving");
      document.body.classList.add("runarranging");
      try { item.setPointerCapture(e.pointerId); } catch { /* a mouse already gone */ }
    }
    e.preventDefault();
    ghost.style.left = `${e.clientX + 12}px`;
    ghost.style.top = `${e.clientY - 14}px`;
    lastY = e.clientY;
    target = aim(e.clientY);
  };
  const scroller = setInterval(() => {
    if (!dragging) return;
    const well = root.querySelector(".well");
    if (!well) return;
    const box = well.getBoundingClientRect();
    const slide = lastY < box.top + 44 ? -12 : lastY > box.bottom - 44 ? 12 : 0;
    if (!slide) return;
    scrollerOf(well).scrollTop += slide;
    target = aim(lastY);
  }, 30);
  const up = () => stop(dragging);

  function stop(moved) {
    clearTimeout(hold);
    clearInterval(scroller);
    document.body.classList.remove("runholding", "runarranging");
    item.classList.remove("lifted", "moving");
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
    window.removeEventListener("pointercancel", up);
    if (ghost) { ghost.remove(); ghost = null; }
    if (line) { line.remove(); line = null; }
    if (!moved || !target) return;
    const eat = (c) => { c.preventDefault(); c.stopPropagation(); window.removeEventListener("click", eat, true); };
    window.addEventListener("click", eat, true);
    setTimeout(() => window.removeEventListener("click", eat, true), 350);
    shootHere(item.dataset.shotno, target.band, target.before);
  }

  window.addEventListener("pointermove", move, { passive: false });
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);
});

/** The carried shot, kept at its new place in the day's whole order. */
async function shootHere(shot, band, before) {
  const label = band.dataset.label;
  if (!band.dataset.day || !label) return draw(); // Not Scheduled is not a day
  const whole = (band.dataset.whole || "").split(",").filter((n) => n && n !== shot);
  const at = before && whole.includes(before) ? whole.indexOf(before) : whole.length;
  try {
    const got = await fetch(`/f/${HUB.project}/api/shootorder`, {
      method: "PUT", headers: { "content-type": "application/json" },
      body: JSON.stringify({ shot, day: label, position: at + 1 }),
    });
    if (!got.ok) throw new Error(`${got.status} ${await got.text()}`);
    await check();
  } catch (error) {
    console.warn("could not move", shot, String(error));
    draw();
  }
}
