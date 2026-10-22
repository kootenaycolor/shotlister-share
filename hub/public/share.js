/**
 * Share — who may open this film, and what anybody with the link may do.
 *
 * **A popover beside the button, not a page you go to** (move 3 of
 * `design/29-portal-details`, 2026-10-03; it was a centred box over a blurred
 * page from 2026-09-01). It opens from whichever Share button was pressed,
 * through `feel.pop`, and closes on Escape or a press outside. Two tabs, for
 * him: **People** (the link line, who is on the list, views) and **On the
 * Link** (a checklist of the sidebar's pages under its own headings, then
 * People's Shown and Contact). The address `/f/<id>/share` still works: it
 * sends an editor to the film with `?share=1`, and the popover opens there.
 * Its look is `share.css`, built out of `feel.css`; its words follow the
 * app's law — a label names the thing.
 *
 * The model underneath is unchanged, and is not Google's. Three things grant
 * access and they are genuinely different:
 *
 * - **A person on the list.** They sign in and the film knows their address.
 * - **An invite.** Send it; whoever opens it signs in with any address they
 *   like and *that address joins the list*. It is spent once used.
 * - **An unlisted link.** Grants no name at all — whoever holds it reads the
 *   film. Served from `share.` because the apex has a sign-in in front of it,
 *   and a link that asked somebody to sign in would not be an unlisted link.
 *
 * ## The key is kept
 *
 * It used to be hashed here and thrown away, so an address existed only while
 * it was on screen. His call, 2026-09-01: keep it, so **Copy link works
 * whenever this opens**, from any device. What that gave up is small — the
 * thing it guarded against was somebody reading the bucket, and anybody who can
 * read the bucket can already read every film in it whole. A presented key is
 * still checked by its hash, so how access is *decided* has not moved.
 */

const HUB = window.HUB;

/**
 * The key this browser came in on, if it came in on one.
 *
 * **This is the whole of the difference.** An editor's window is about who may
 * open the film. Somebody reading it on an unlisted link cannot change that and
 * is not offered the chance — what they get is the one thing they cannot get
 * for themselves: the address they are standing on with the key on it. Every
 * link inside the film is a plain address, so the address bar is no use to
 * them. His report, 2026-09-08: *"just copying the url doesn't lead you to the
 * right place."*
 */
const LINK = (HUB && HUB.linkKey) || null;

/**
 * **Declared up here, above the code that runs on load.** A link holder's
 * page draws synchronously the moment the script starts, and `herePath` reads
 * this; as a `const` further down the file it was in its dead zone at that
 * moment and the Share page a link holder opened was blank — every time,
 * since 2026-09-08. The argument for the list is beside `aPlace` below.
 */
const NOT_A_PLACE = new Set([
  "share", "photo", "visibility", "add", "join", "print", "api", "media", "pic",
  // the film's own page is `base`, never `base/home`
  "home",
]);


let list = { version: 1, people: [], links: [], invites: [] };
/**
 * **His view links** (`src/views.js`): a filtered Shot List each, shared on
 * its own. Null until read; read with the list of people, never by a link
 * holder, who is refused it.
 */
let views = null;
/** Opened from the Shot List's Share View, so the Views section is the point. */
let wantView = false;
let saying = "";
let bad = false;
let busy = false;
let root = null;
let overlay = null;
let forMe = false; // For Me is retired; kept so nothing below breaks
/** A tick was saved: the rail is brought up to date when the popover closes. */
let settingsDirty = false;

/**
 * **Share and Visibility are one panel now, as two tabs.** Ref 1153, his pick
 * of 2026-09-23: they answer the same question — what does somebody with the
 * link see — and Visibility used to be a page of its own reachable only from
 * behind his initials. The tab is his alone (`HUB.admin`); the server refuses
 * `/visibility` to anybody else whatever a page draws.
 *
 * The table itself is the server's (`visibilityForm` in `src/pages.js`),
 * fetched once per opening, so the tab and the plain `/visibility` page are
 * one layout rather than two that drift.
 */
const MAY_SEE_TAB = Boolean(HUB && HUB.admin) && !LINK;
/**
 * **Share is Access alone now** (2026-10-11, his approved layout): who may
 * open the film, General Access, the link. What a viewer sees moved to the
 * Library (each page's one switch, and Crew), so the second tab is gone and
 * nothing is said in two places. The plain `/visibility` page still answers
 * its address; the tab's code below stays asleep behind this.
 */
const VIS_TAB = false;
let tab = "share";
let visMarkup = null;

/**
 * **Read before it is asked for.** His ask, 2026-10-02: *"I want things to
 * feel 'instant' even if stuff is loading in the background, especially
 * settings pages and controls."* The panel used to read the list of people
 * when it opened and the Visibility table when its tab was pressed — a second
 * or more of *Loading* each time. Both are read once the page has settled,
 * kept here, and drawn the moment the panel opens; a fresh read then runs
 * behind it and redraws only if something changed and he has not started
 * changing it himself.
 */
let held = null;
let visHeld = null;
let reading = null;
let visSaves = 0;
// Declared up here for the reason `NOT_A_PLACE` gives: the Share page draws
// as this file starts, and a `let` further down is not there yet.
let visFresh = false;

function readAhead() {
  if (LINK || !HUB || !HUB.project || reading) return reading;
  reading = Promise.allSettled([
    api("GET").then((got) => { held = got; }),
    VIS_TAB && MAY_SEE_TAB ? visApi("GET").then((got) => { visHeld = got; }) : null,
  ]).finally(() => { reading = null; });
  return reading;
}
if (!LINK && HUB && HUB.project) {
  const soon = () => setTimeout(readAhead, 400);
  if (document.readyState === "complete") soon();
  else addEventListener("load", soon);
  // **A save anywhere else makes what is held yesterday's** — a page's own
  // Shown on Links, a rename — so it is read again.
  document.addEventListener("saved", () => {
    held = null;
    visHeld = null;
    setTimeout(readAhead, 300);
  });
}

// ------------------------------------------------------------------- marks
//
// Stroked, 16-unit, `currentColor`. A padlock and a globe are the two states of
// general access, and they are the same two anybody recognises from a document.

const MARK = {
  lock: `<path d="M4.4 7.2h7.2a1.4 1.4 0 0 1 1.4 1.4v4.2a1.4 1.4 0 0 1-1.4 1.4H4.4A1.4 1.4 0 0 1 3 12.8V8.6a1.4 1.4 0 0 1 1.4-1.4Z"/><path d="M5.6 7.2V5.4a2.4 2.4 0 0 1 4.8 0v1.8"/>`,
  globe: `<circle cx="8" cy="8" r="5.4"/><path d="M2.6 8h10.8"/><path d="M8 2.6c1.5 1.6 2.3 3.4 2.3 5.4S9.5 11.8 8 13.4C6.5 11.8 5.7 10 5.7 8S6.5 4.2 8 2.6Z"/>`,
  link: `<path d="M6.7 9.3a2.5 2.5 0 0 0 3.6 0l2-2a2.55 2.55 0 0 0-3.6-3.6l-.8.8"/><path d="M9.3 6.7a2.5 2.5 0 0 0-3.6 0l-2 2a2.55 2.55 0 0 0 3.6 3.6l.8-.8"/>`,
  invite: `<rect x="2.6" y="4" width="10.8" height="8" rx="1.4"/><path d="m3 4.8 5 3.6 5-3.6"/>`,
  close: `<path d="m4.6 4.6 6.8 6.8M11.4 4.6l-6.8 6.8"/>`,
};

function mark(which, size = 14) {
  return `<svg class="mk" viewBox="0 0 16 16" width="${size}" height="${size}" fill="none"
    stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round"
    aria-hidden="true">${MARK[which]}</svg>`;
}

// ------------------------------------------------------------------ opening

/**
 * **A popover beside the button, not a box over a blurred page** (move 3 of
 * `design/29-portal-details`, 2026-10-03). It opens from whichever Share
 * button was pressed — the sidebar's, the phone's top bar, a page's own — as
 * `feel.pop`, so it shares the look, the Escape and the press-outside of every
 * other floating thing. Nothing behind it is dimmed on a desk; on a phone it
 * is a sheet from the bottom, with a light scrim so the film still reads as
 * the thing underneath.
 *
 * The button is a real link, so it works with nothing running. The click is
 * caught at the document rather than on the button because the viewer redraws
 * its whole chrome on every paint, and a handler bound to a button would be
 * thrown away with it.
 *
 * `/f/<id>/share` is still an address: for somebody who may edit, it sends the
 * browser to the film (the page it was pressed on, if it says) with
 * `?share=1`, and the popover opens there. A link holder keeps the small card
 * at that address, because a link holder's film may not have a page to land on.
 */
let handle = null;
/**
 * **On a phone it is the shared bottom sheet** (`feel.sheet`, move 3 of
 * `design/30-portal-phone`). Its head leads with the film, one line says who
 * can open it and opens General Access, and Copy Link is a row of its own.
 * `onPhone` is decided once, when it opens.
 */
let onPhone = false;
/** On a phone: is the General Access block (the line under the film's name) open? */
let accessOpen = false;

/** The first Share button that is actually on screen. */
function visibleShareButton() {
  for (const one of document.querySelectorAll("a[data-share]:not([data-tab])")) {
    const box = one.getBoundingClientRect();
    if (box.width > 0 && box.height > 0 && !one.closest("details")) return one;
  }
  return null;
}

/** `?share=1` on the film's own page: open once the button has been drawn. */
function openWhenAsked() {
  const params = new URLSearchParams(location.search);
  if (!params.get("share")) return;
  const tabAsked = params.get("share") === "visibility" ? "visibility" : "";
  params.delete("share");
  const rest = params.toString();
  try { history.replaceState(history.state, "", location.pathname + (rest ? `?${rest}` : "") + location.hash); } catch { /* the address stays */ }
  let tries = 0;
  const look = () => {
    const button = visibleShareButton();
    if (button) return open(tabAsked, button);
    if (++tries < 40) setTimeout(look, 100);
  };
  look();
}

if (document.getElementById("share")) {
  // **The address itself.** An editor is sent to the film with the popover
  // asked for; a link holder (or a browser that cannot show a popover) gets
  // the plain card.
  const params = new URLSearchParams(location.search);
  if (!LINK && window.feel && HUB && HUB.project) {
    const base = HUB.base || `/f/${HUB.project}`;
    const from = String(params.get("from") || "");
    const to = /^[a-z0-9][a-z0-9-]*$/.test(from) && !NOT_A_PLACE.has(from) ? `${base}/${from}` : base;
    const tabAsked = params.get("tab") === "visibility" ? "visibility" : "1";
    location.replace(`${to}?share=${tabAsked}`);
  } else {
    const page = document.getElementById("share");
    page.classList.add("sharepage");
    wearTheFilm(page);
    page.innerHTML = `<div class="sheetcard"></div>`;
    root = page.querySelector(".sheetcard");
    load();
  }
} else {
  ensureStyles();
  document.addEventListener("click", (event) => {
    const asked = event.target.closest("a[data-share]");
    if (!asked || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
    event.preventDefault();
    // The menu behind his initials and a page's own menu both ask for the
    // On the Link tab by name; the Share button asks for nothing.
    const menu = asked.closest("details");
    if (menu) menu.open = false;
    if (handle) return shut(true);
    // A menu's own item is gone the moment the menu shuts, so the popover
    // opens from the Share button instead — or from the menu's handle.
    open(asked.dataset.tab, menu ? visibleShareButton() || menu.querySelector("summary") || asked : asked);
  });
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", openWhenAsked);
  else openWhenAsked();
}

/** The popover's own stylesheet, once, before anything is drawn in it. */
function ensureStyles() {
  if (document.querySelector('link[href*="share.css"]')) return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  // The same build stamp this script was asked for with.
  link.href = new URL(`/share.css${new URL(import.meta.url).search}`, import.meta.url).href;
  document.head.appendChild(link);
}

function open(which, anchor) {
  if (handle || !window.feel || !anchor) return;
  tab = VIS_TAB && (which === "visibility" || which === "link") && MAY_SEE_TAB ? "visibility" : "share";
  wantView = which === "view";
  visMarkup = visHeld;
  visFresh = false;
  forMe = false;
  saying = "";

  onPhone = feel.phone();
  accessOpen = false;
  const box = document.createElement("div");
  box.className = "sp-root";
  root = box;
  // **A taller phone keyboard is not a reason to close it.** `feel.pop` shuts
  // on any resize; typing an address on a phone resizes the window's height
  // and nothing else, so that kind is stopped before `feel.pop` hears it.
  const widthThen = innerWidth;
  const guard = (event) => { if (innerWidth === widthThen) event.stopImmediatePropagation(); };
  addEventListener("resize", guard);

  const rect = anchor.getBoundingClientRect();
  const low = rect.top > innerHeight / 2;
  const closed = () => {
    removeEventListener("resize", guard);
    handle = null;
    root = null;
    overlay = null;
    if (settingsDirty) {
      settingsDirty = false;
      document.dispatchEvent(new Event("settingschanged"));
    }
  };
  handle = onPhone
    ? feel.sheet(box, { className: "sp spsheet", label: "Share", focus: false, onClose: closed })
    : feel.pop(anchor, box, {
        className: "sp",
        role: "dialog",
        side: low ? "top" : "bottom",
        align: low ? "start" : "end",
        onClose: closed,
      });
  handle.el.setAttribute("aria-label", "Share");
  // **Done is the film's colour, so its words must read on it.** A pale film
  // (yellow, mint) takes dark words, a deep one white.
  const hue = /^#([0-9a-f]{6})$/i.exec(feel.tint(anchor));
  if (hue) {
    const [r, g, b] = [0, 2, 4].map((i) => parseInt(hue[1].slice(i, i + 2), 16) / 255)
      .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
    handle.el.style.setProperty("--sp-on", 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? "#0E0E11" : "#fff");
  }
  overlay = handle.el;
  load();
  // The popover grows and shrinks as its tab changes; keep it on its button.
  // **Placed again once it has finished growing in:** while it scales up, its
  // box measures a little small and would sit a little low.
  new ResizeObserver(() => { if (handle) handle.place(); }).observe(box);
  handle.el.addEventListener("animationend", () => { if (handle) handle.place(); }, { once: true });
}

function shut(returnFocus = false) {
  if (handle) handle.close(returnFocus);
}

async function load() {
  // **Nothing is fetched for a link holder.** The list of people is an editor's
  // and the hub refuses it to anybody else — asking would be a round trip whose
  // only possible answer is a refusal, drawn as *That would not load*.
  if (LINK) return draw();
  readViews();
  if (held) {
    list = held;
    draw();
    // Drawn from what was held; checked behind it. Redrawn only if it changed
    // and he is not in the middle of something — typing an address, a save.
    api("GET").then((got) => {
      held = got;
      if (!root || tab !== "share" || busy || JSON.stringify(got) === JSON.stringify(list)) return;
      if (root.contains(document.activeElement) && document.activeElement.matches("input, select, textarea")) return;
      list = got;
      draw();
    }).catch(() => {});
    return;
  }
  root.innerHTML = `<p class="sp-none">Loading</p>`;
  try {
    list = await api("GET");
    held = list;
  } catch (error) {
    saying = "That would not load.";
    bad = true;
  }
  draw();
}

// ------------------------------------------------------------------ drawing

/**
 * The one unlisted link, if there is one. One at a time, like a document.
 *
 * **Only a link whose address was kept counts.** Links made before that was
 * true still work for whoever holds them, and the hub cannot show one — so
 * treating one as the general link made this panel say "Anyone with the link"
 * over a Copy button that had nothing to copy, and quietly hand over the
 * sign-in address instead. That is the bug he hit.
 */
/**
 * The film's own colour, on whichever box the panel is drawn in.
 *
 * **It has to be told.** The panel is appended to the body as an overlay, or is
 * the whole page — either way it sits outside the app's chrome and inherits
 * none of the film's tokens.
 */
function wearTheFilm(box) {
  const hue = HUB.mark && HUB.mark.colour;
  if (!/^#[0-9A-Fa-f]{6}$/.test(String(hue || ""))) return;
  box.style.setProperty("--accent", hue);
  box.style.setProperty("--accent-tint", `color-mix(in srgb,${hue} 14%,transparent)`);
  box.style.setProperty("--accent-line", `color-mix(in srgb,${hue} 38%,transparent)`);
  box.style.setProperty("--on-accent", "#fff");
}

function general() {
  return list.links.find((l) => l && l.key) || null;
}

/** Is general access actually open? A kept link that is switched off is not. */
function open_() {
  const link = general();
  return link && !link.off ? link : null;
}

/** A link that exists and is switched off — kept, and refused for now. */
function kept() {
  const link = general();
  return link && link.off ? link : null;
}

/** A link from before addresses were kept: real, working, and unshowable. */
function lost() {
  return !general() && list.links.some((l) => l && !l.key);
}

/**
 * Where this panel was opened from.
 *
 * His instruction: *"if I copy a link inside the shot list page I want it to
 * link to that shot list."* So the address carries the page somebody is looking
 * at — and only a page worth being sent to. `share` and `photo` are things you
 * do, not places to send anybody.
 *
 * **Named by what is refused, not by what is allowed.** This was a list of
 * seven addresses, written when a film had seven. A film's pages are whatever
 * he names in Notion now — and every one of them, plus the Visual Bible, the
 * camera sheet and People, fell through the list and copied the film's front
 * door instead. His report, 2026-09-08. So the shape of a page's address is
 * what counts, and the only names kept out are the ones that are not pages.
 */
function aPlace(tail) {
  return /^\/[a-z0-9][a-z0-9-]*$/.test(tail) && !NOT_A_PLACE.has(tail.slice(1));
}

function herePath() {
  const base = HUB.base || `/f/${HUB.project}`;
  // **Standing on the share page itself.** That address is a page somebody was
  // sent to rather than a place to send anybody, so it cannot say where it was
  // opened from — the button that opened it says, on the end of the address.
  const sent = new URLSearchParams(location.search).get("from");
  const tail = sent
    ? `/${String(sent).replace(/^\/+/, "")}`
    : location.pathname.startsWith(base)
      ? location.pathname.slice(base.length).replace(/\/+$/, "")
      : "";
  return aPlace(tail) ? base + tail : base;
}

/**
 * **The friendly address, when there is one.** `share.…/hla` stands for the
 * film's general link (his instruction, 2026-09-19), so whoever may hand out
 * that link is handed the short form of it — and the page they are on rides
 * on the end: `share.…/hla/shotlist`. The server says whether this person's
 * link *is* the general one (`HUB.friendly`); on any other link the key stays
 * on the address, because the short name would open the wrong link.
 */
function linkAddress() {
  // **A view link copies itself**, never the film's general link.
  if (HUB.lens && HUB.lens.address) return HUB.lens.address;
  if (HUB.short && HUB.friendly && (LINK || general())) {
    const base = HUB.base || `/f/${HUB.project}`;
    const here = herePath();
    const tail = here.startsWith(base) ? here.slice(base.length) : "";
    return `${shareOrigin()}/${HUB.short}${tail}`;
  }
  if (LINK) return `${shareOrigin()}${herePath()}?k=${LINK}`;
  const open = general();
  return open ? `${shareOrigin()}${herePath()}?k=${open.key}` : "";
}

/**
 * The card somebody reading on a link is drawn at the share address: the
 * address, and Copy link.
 *
 * Same card, same hand — the head, the globe and the two buttons are the
 * editor's own. What is not here is everything they cannot do: no list of
 * people, no way to add one, no switch between Restricted and Anyone, no
 * password. A control that refuses when pressed is worse than one that was
 * never drawn.
 */
function drawLink() {
  if (handle) return drawLinkPop();
  root.innerHTML = `
    <div class="sheethead">
      <h1>Share &ldquo;${esc(HUB.title)}&rdquo;</h1>
    </div>

    <div class="gen">
      <span class="genmark on">${mark("globe", 15)}</span>
      <div class="genwhat">
        <div class="genname">Anyone with the link</div>
        <div class="sub">${esc(linkAddress())}</div>
      </div>
    </div>

    ${saying ? `<p class="saying${bad ? " bad" : ""}">${esc(saying)}</p>` : ""}

    <div class="sheetfoot">
      <button id="copy" class="btn wide" type="button">${mark("link")}Copy link</button>
      <div class="spacer"></div>
      <a class="primary narrow done" href="${esc(herePath())}">Done</a>
    </div>`;
  root.querySelector("#copy").addEventListener("click", () => toClipboard(linkAddress(), "Link copied."));
}

/** The same, as a popover: the link line, Copy, Done. */
function drawLinkPop() {
  root.innerHTML = `
    ${head()}
    <div class="sp-body">
      <div class="sp-link">
        <span class="sp-ic on">${mark("globe", 14)}</span>
        <div class="sp-t"><b>Anyone with the Link</b><div class="sp-sub">Can View</div></div>
        ${onPhone ? "" : `<button id="copy" class="sp-btn" type="button">Copy</button>`}
      </div>
      ${onPhone ? `<button id="copy" class="sp-copyrow" type="button"><span class="sp-ic">${mark("link", 15)}</span><span class="sp-t"><b>Copy Link</b></span></button>` : ""}
      <div class="sp-note">${esc(linkAddress().replace(/^https?:\/\//, ""))}</div>
      ${saying && bad ? `<p class="sp-say bad">${esc(saying)}</p>` : ""}
    </div>
    <div class="sp-ft"><span class="sp-count"></span><button class="sp-done" id="done" type="button">Done</button></div>`;
  root.querySelector("#copy").addEventListener("click", () => toClipboard(linkAddress(), "Link copied."));
  root.querySelector("#done").addEventListener("click", () => shut(true));
  wireHead();
}

/** The popover's head: its title and — for him — the two tabs. */
function head() {
  if (onPhone) return phoneHead();
  return `<div class="sp-h"><b>Share</b>${VIS_TAB && MAY_SEE_TAB ? `<div class="sp-seg" role="tablist">
      <button type="button" role="tab" data-tab="share" aria-selected="${tab === "share"}"${tab === "share" ? ' class="on"' : ""}>People</button>
      <button type="button" role="tab" data-tab="visibility" aria-selected="${tab === "visibility"}"${tab === "visibility" ? ' class="on"' : ""}>What Viewers See</button>
    </div>` : ""}</div>`;
}

/**
 * **A phone's head leads with the film**: its mark in its colour and its name,
 * and under it one line saying who can open it, which opens General Access.
 * The two tabs are a full-width control under that, outside what scrolls.
 */
function phoneHead() {
  const outline = HUB.mark && HUB.mark.path;
  const hue = HUB.mark && /^#[0-9A-Fa-f]{6}$/.test(String(HUB.mark.colour || "")) ? HUB.mark.colour : "";
  const film = outline
    ? `<span class="sp-film"${hue ? ` style="color:${hue}"` : ""} aria-hidden="true"><svg viewBox="0 0 20 20" fill="currentColor"><path d="${esc(outline)}"></path></svg></span>`
    : "";
  const who = MAY_SEE_TAB && !LINK
    ? `<button type="button" class="sp-who2" id="access" aria-expanded="${accessOpen && tab === "share"}">${open_() || lost() ? "Anyone with the Link" : "Restricted"} · Can View ›</button>`
    : "";
  return `<div class="sp-h sp-hp" data-sheet-drag>${film}<span class="sp-film-t"><b>${esc(HUB.title)}</b>${who}</span>
      <button type="button" class="fx-sheet-x" id="sheetx" aria-label="Close">${mark("close", 14)}</button></div>
    ${VIS_TAB && MAY_SEE_TAB ? `<div class="sp-segrow"><div class="sp-seg" role="tablist">
      <button type="button" role="tab" data-tab="share" aria-selected="${tab === "share"}"${tab === "share" ? ' class="on"' : ""}>People</button>
      <button type="button" role="tab" data-tab="visibility" aria-selected="${tab === "visibility"}"${tab === "visibility" ? ' class="on"' : ""}>What Viewers See</button>
    </div></div>` : ""}`;
}

function wireHead() {
  const x = root.querySelector("#sheetx");
  if (x) x.addEventListener("click", () => shut(true));
  const line = root.querySelector("#access");
  if (line) line.addEventListener("click", () => {
    accessOpen = tab === "share" ? !accessOpen : true;
    tab = "share";
    saying = "";
    draw();
    if (accessOpen) { const at = root.querySelector("#general"); if (at) at.scrollIntoView({ block: "nearest" }); }
  });
  root.querySelectorAll(".sp-h [data-tab], .sp-segrow [data-tab]").forEach((button) =>
    button.addEventListener("click", () => {
      if (tab === button.dataset.tab) return;
      tab = button.dataset.tab;
      saying = "";
      draw();
    })
  );
}

/**
 * **The On the Link tab** — the checklist, fetched from the server once per
 * opening (`?part=2`, `visibilityChecks` in `src/pages.js`) and saved back by
 * the same form to the same address the plain `/visibility` page uses.
 *
 * **A tick saves itself** (2026-10-02, kept): it turns over under the finger,
 * the save goes behind it, and a failed save turns it back. The list is never
 * redrawn from the answer, which would undo a tick pressed while the save was
 * out.
 */
async function drawVis() {
  const link = open_();
  root.innerHTML = `${head()}
    <div class="sp-body sp-vis">${visMarkup || `<p class="sp-none">Loading</p>`}</div>
    <div class="sp-ft"><span class="sp-count" data-count></span>${
      // **A way to see it as a viewer sees it exists only while the link is
      // open:** the link itself is the viewer's view. A film on Restricted has
      // no such view to show.
      link && linkAddress()
        ? `<a class="sp-btn" id="preview" href="${esc(linkAddress())}" target="_blank" rel="noopener">Preview as Viewer</a>` : ""
    }</div>`;
  wireHead();
  if (visMarkup === null) {
    try {
      visMarkup = await visApi("GET");
      visHeld = visMarkup;
      visFresh = true;
    } catch {
      visMarkup = `<p class="sp-say bad">That would not load.</p>`;
    }
    if (root && tab === "visibility") drawVis();
    return;
  }
  const form = root.querySelector(".sp-vform");
  if (!form) return;
  // **Drawn from what was held; checked behind it**, once an opening, and
  // redrawn only if it changed and no tick has been touched since.
  if (!visFresh) {
    visFresh = true;
    const shown = visMarkup;
    visApi("GET").then((got) => {
      visHeld = got;
      if (got === shown || form.dataset.dirty || !root || tab !== "visibility" || visMarkup !== shown) return;
      visMarkup = got;
      drawVis();
    }).catch(() => {});
  }
  const count = root.querySelector("[data-count]");
  const forField = form.querySelector('input[name="for"]');
  forMe = forField && forField.value === "me";
  const tally = () => {
    const part = form.querySelector(".sp-part:not([hidden])");
    const all = part ? part.querySelectorAll("input[data-page]") : [];
    const on = part ? part.querySelectorAll("input[data-page]:checked") : [];
    count.textContent = `${on.length} of ${all.length} pages`;
  };
  tally();

  form.querySelectorAll(".sp-seg [data-part]").forEach((button) =>
    button.addEventListener("click", () => {
      forMe = button.dataset.part === "me";
      if (forField) forField.value = forMe ? "me" : "links";
      form.querySelectorAll(".sp-seg [data-part]").forEach((one) => one.classList.toggle("on", one === button));
      form.querySelectorAll(".sp-part").forEach((part) => { part.hidden = part.dataset.part !== button.dataset.part; });
      tally();
    })
  );

  const dress = (input) => {
    const ck = input.nextElementSibling;
    if (ck && ck.classList.contains("fx-ck")) ck.classList.toggle("on", input.checked);
    // A person who is not shown has no contact to show: dimmed, as before.
    if (input.matches("[data-shown]")) {
      const row = input.closest(".sp-ppl");
      if (row) row.classList.toggle("dim", !input.checked);
    }
  };
  let chain = Promise.resolve();
  const save = (input) => {
    chain = chain.then(async () => {
      try {
        const got = await visApi("POST", new URLSearchParams(new FormData(form)));
        visMarkup = got;
        visHeld = got;
        if (window.feel) feel.toast("Saved");
        // The rail and every page kept for a click may show what just changed,
        // but redrawing the rail swaps the page under the popover and shuts it:
        // so it is told when the popover closes, not on every tick.
        settingsDirty = true;
      } catch {
        input.checked = !input.checked;
        dress(input);
        tally();
        if (window.feel) feel.toast("Not Saved");
      }
    });
  };
  form.addEventListener("change", (event) => {
    const input = event.target;
    if (!input.matches || !input.matches(".vcb")) return;
    form.dataset.dirty = "1";
    dress(input);
    tally();
    save(input);
  });
  form.addEventListener("submit", (event) => event.preventDefault());
}

/**
 * **The plain Visibility page saves itself too.** Its form is the page's, so
 * a save goes the way every save on a page goes — through `deep.js`, which
 * sees `data-autosave` and leaves the page where it is.
 */
function dressPage() {
  for (const form of document.querySelectorAll(".fh2 .fh-visform:not([data-autosave])")) {
    form.dataset.autosave = "";
    let timer = null;
    form.addEventListener("change", (event) => {
      if (!event.target.matches || !event.target.matches(".vcb")) return;
      clearTimeout(timer);
      timer = setTimeout(() => form.requestSubmit(), 250);
    });
  }
}
dressPage();
document.addEventListener("swapped", dressPage);

async function visApi(method, body) {
  const got = await fetch(`${HUB.base || `/f/${HUB.project}`}/visibility?part=2`, {
    method,
    credentials: "same-origin",
    body,
    headers: body ? { "content-type": "application/x-www-form-urlencoded" } : undefined,
  });
  if (!got.ok) throw new Error(String(got.status));
  return await got.text();
}

/** Redraw, keeping the place in a long list. */
function draw() {
  if (!root) return;
  const scroller = root.querySelector(".sp-body");
  const at = scroller ? scroller.scrollTop : 0;
  drawNow();
  const again = root && root.querySelector(".sp-body");
  if (again && at) again.scrollTop = at;
}

function drawNow() {
  if (LINK) return drawLink();
  if (tab === "visibility") return drawVis();
  // **What is open, not what exists.** A kept link that is switched off is
  // still in the list, and the panel must say Restricted rather than claim
  // anybody with the address can read the film.
  const open = open_();
  const live = Boolean(open || lost());
  const note = open
    ? esc(linkAddress().replace(/^https?:\/\//, "")) + (open.pass ? " · Password" : "")
    : kept()
      ? "Link is off · Kept, works again when switched on"
      : lost()
        ? "Made before addresses were kept · Copy makes a new link"
        : "";
  const n = list.people.length;
  // **On a phone** General Access is behind the line under the film's name, and
  // Copy Link is a full-width row of its own; the row's second line says what it
  // does only when it changes access (it makes the link, or replaces an old one).
  const access = !onPhone || accessOpen;
  const copyRow = onPhone
    ? `<button id="copy" class="sp-copyrow" type="button"><span class="sp-ic">${mark("link", 15)}</span><span class="sp-t"><b>Copy Link</b>${
        linkAddress() ? "" : `<small>${lost() ? "Replaces the old link" : "Turns the link on"}</small>`}</span></button>
      ${note ? `<div class="sp-note">${note}</div>` : ""}`
    : "";
  root.innerHTML = `
    ${head()}
    <div class="sp-body">
      ${!access ? "" : `<div class="sp-link">
        <span class="sp-ic${live ? " on" : ""}">${mark(live ? "globe" : "lock", 14)}</span>
        <div class="sp-t">
          <select id="general" class="sp-dd strong" aria-label="General Access">
            <option value="restricted"${live ? "" : " selected"}>Restricted</option>
            <option value="anyone"${live ? " selected" : ""}>Anyone with the Link</option>
          </select>
          <div class="sp-sub">Can <select id="linkrole" class="sp-dd" aria-label="Link Role"${open ? "" : " disabled"}>
            <option value="viewer" selected>View</option>
            <option value="commenter" disabled>Comment</option>
          </select></div>
        </div>
        ${onPhone ? "" : `<button id="copy" class="sp-btn" type="button">Copy</button>`}
      </div>`}
      ${onPhone || !note ? "" : `<div class="sp-note">${note}</div>`}
      ${
        // **No end date, and nothing explaining itself.** His instruction,
        // 2026-09-02: an end date is the one setting here that kills a link
        // somebody already holds, so it is not offered at all.
        open && access
          ? `<div class="sp-set">
               ${HUB.short ? `<label class="sp-f">Short Name
                 <input id="short" class="sp-in slim" type="text" value="${esc(HUB.short)}" maxlength="24"
                   autocomplete="off" spellcheck="false" pattern="[a-z0-9]{2,24}"></label>` : ""}
               <label class="sp-tick"><input type="checkbox" id="haspass" ${open.pass ? "checked" : ""}><i class="fx-ck${open.pass ? " on" : ""}" aria-hidden="true"></i>Password</label>
               ${
                 // **Only when it is wanted** — his instruction. A password field
                 // standing there empty asks a question nobody was asking.
                 open.pass
                   ? `<input id="linkpass" class="sp-in slim" type="password" placeholder="Set · type to change" autocomplete="new-password">`
                   : ""
               }
             </div>`
          : ""
      }
      ${copyRow}

      <div class="sp-add">
        <input id="who" class="sp-in" type="email" placeholder="Add people by email" autocomplete="off" spellcheck="false">
        <select id="asrole" class="sp-dd boxed" aria-label="Role">
          <option value="viewer">Viewer</option>
          <option value="editor">Editor</option>
        </select>
        <button id="add" class="sp-btn" type="button">Invite</button>
      </div>

      <div class="sp-rows">
        ${list.people.map(person).join("")}
        ${list.invites.map(invite).join("")}
        ${!list.people.length && !list.invites.length ? `<p class="sp-none">Nobody yet</p>` : ""}
      </div>

      ${viewsSection()}

      ${saying && (bad || /^https?:/.test(saying)) ? `<p class="sp-say${bad ? " bad" : ""}">${esc(saying)}</p>` : ""}
    </div>
    <div class="sp-ft">
      <span class="sp-count">${n} ${n === 1 ? "person" : "people"} · Link ${open ? "On" : "Off"}</span>
      <button class="sp-done" id="done" type="button">Done</button>
    </div>`;
  wire();
  wireViews();
  if (wantView) {
    wantView = false;
    const at = root.querySelector("#views");
    if (at) at.scrollIntoView({ block: "nearest" });
    const name = root.querySelector("#viewname");
    if (name) name.focus();
  }
}

// ------------------------------------------------------------------- views

/** The filter the Shot List behind this panel is showing, if it is showing one. */
function filterNow() {
  const said = typeof window.shotlisterFilter === "function" ? window.shotlisterFilter() : null;
  return said && said.facets && said.facets.length ? said : null;
}

async function readViews() {
  if (LINK || !HUB || !HUB.project) return;
  try {
    const got = await fetch(`/f/${HUB.project}/api/views`, { headers: { accept: "application/json" } });
    if (!got.ok) return;
    views = (await got.json()).views || [];
    if (root && tab === "share" && !busy && !(root.contains(document.activeElement) && document.activeElement.matches("input"))) draw();
  } catch { /* the rest of the panel stands without them */ }
}

async function viewsApi(method, body) {
  const got = await fetch(`/f/${HUB.project}/api/views`, {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const said = await got.json().catch(() => ({}));
  if (!got.ok) throw new Error(said.problem || String(got.status));
  views = said.views || views;
  return said;
}

function viewAddress(v) {
  return `${shareOrigin()}${v.path}`;
}

/**
 * **Views**: make one from the filter on screen, and the ones already made.
 * Drawn only when there is something to draw — a filter to share, or a view.
 */
function viewsSection() {
  const now = filterNow();
  const have = views || [];
  // **Said even when there is nothing to list**, on the Shot List: the
  // section was missed when it only appeared with a filter on.
  if (!now && !have.length) {
    return typeof window.shotlisterFilter === "function"
      ? `<div class="sp-sec" id="views">Views</div><p class="sp-none">Filter the Shot List to share a view</p>`
      : "";
  }
  const named = now ? now.facets.map(([, v]) => v).join(", ").slice(0, 60) : "";
  return `<div class="sp-sec" id="views">Views</div>
    ${now ? `<div class="sp-make">
        <span class="sp-chips">${now.facets.map(([, v]) => `<span class="sp-chip">${esc(v)}</span>`).join("")}</span>
        <input id="viewname" class="sp-in slim" type="text" maxlength="60" placeholder="Name" value="${esc(named)}" autocomplete="off">
        <button id="makeview" class="sp-btn" type="button">Share View</button>
      </div>` : ""}
    <div class="sp-rows">
      ${have.map((v) => `<div class="sp-row">
        <span class="sp-av quiet">${mark(v.off ? "lock" : "link", 13)}</span>
        <span class="sp-who"><b>${esc(v.name)}</b><small>${v.off ? "Off" : esc(viewAddress(v).replace(/^https?:\/\//, ""))}</small></span>
        ${v.off ? "" : `<button class="sp-btn" type="button" data-vcopy="${esc(v.code)}">Copy</button>`}
        <select class="sp-dd" data-vset="${esc(v.code)}">
          <option value="on"${v.off ? "" : " selected"}>On</option>
          <option value="off"${v.off ? " selected" : ""}>Off</option>
          <option value="remove">Remove</option>
        </select>
      </div>`).join("")}
    </div>`;
}

function wireViews() {
  const make = root.querySelector("#makeview");
  if (make) {
    const name = root.querySelector("#viewname");
    name.addEventListener("keydown", (event) => { if (event.key === "Enter") make.click(); });
    make.addEventListener("click", async () => {
      const now = filterNow();
      if (!now || busy) return;
      busy = true;
      try {
        const said = await viewsApi("POST", { name: name.value.trim(), facets: now.facets, groupBy: now.groupBy });
        busy = false;
        // Drawn first: a browser may sit on the clipboard (a prompt, a window
        // without focus), and the new view should not wait on it.
        say(viewAddress(said.made));
        draw();
        await toClipboard(viewAddress(said.made), "View link copied.");
        return;
      } catch (error) {
        say(`That would not save. ${error.message}`, true);
      }
      busy = false;
      draw();
    });
  }
  root.querySelectorAll("[data-vcopy]").forEach((b) => b.addEventListener("click", () => {
    const v = (views || []).find((one) => one.code === b.dataset.vcopy);
    if (v) toClipboard(viewAddress(v), "View link copied.");
  }));
  root.querySelectorAll("[data-vset]").forEach((pick) => pick.addEventListener("change", async () => {
    const code = pick.dataset.vset;
    const want = pick.value;
    if (want === "remove" && !confirm("Remove this view? Its link stops working for good.")) return draw();
    try {
      if (want === "remove") await viewsApi("DELETE", { code });
      else await viewsApi("PUT", { code, off: want === "off" });
      say(want === "remove" ? "View removed." : want === "off" ? "Nobody can open that view now." : "That view opens again.");
    } catch (error) {
      say(`That would not save. ${error.message}`, true);
    }
    draw();
  }));
}

/** Him, by either address. The server treats both as editors whatever the list
 *  says, so offering to change one would be offering something it refuses. */
function isOwner(email) {
  return (HUB.owners || []).some((o) => String(o).toLowerCase() === String(email).toLowerCase());
}

function person(p, index) {
  const owner = isOwner(p.email);
  return `<div class="sp-row">
    <span class="sp-av">${esc(initials(p.email))}</span>
    <span class="sp-who"><b>${esc(p.email)}</b>${p.via ? `<small>Joined by ${esc(p.via)}</small>` : ""}</span>
    ${
      owner
        ? `<span class="sp-owner">Owner</span>`
        : `<select class="sp-dd" data-role="${index}" aria-label="Role for ${esc(p.email)}">
             <option value="viewer"${p.role === "editor" ? "" : " selected"}>Viewer</option>
             <option value="editor"${p.role === "editor" ? " selected" : ""}>Editor</option>
             <option value="remove">Remove</option>
           </select>`
    }
  </div>`;
}

function invite(i, index) {
  return `<div class="sp-row">
    <span class="sp-av quiet">${mark("invite", 13)}</span>
    <span class="sp-who"><b>Invite</b><small>Joins as ${esc(i.role)}${i.expires ? ` · Until ${esc(i.expires)}` : ""}</small></span>
    <button class="sp-btn" data-copyinvite="${index}" type="button">Copy</button>
    <button class="sp-x" data-dropinvite="${index}" type="button" title="Cancel Invite" aria-label="Cancel Invite">${mark("close", 13)}</button>
  </div>`;
}

// ------------------------------------------------------------------- wiring

function wire() {
  const at = (id) => root.querySelector(`#${id}`);
  const on = (id, event, run) => {
    const it = at(id);
    if (it) it.addEventListener(event, run);
  };

  wireHead();
  on("done", "click", () => shut(true));

  on("add", "click", async () => {
    const email = at("who").value.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+$/.test(email)) return draw(say("That is not an email address.", true));
    if (list.people.some((p) => p.email === email)) return draw(say("They are already on it.", true));
    list.people.push({ email, role: at("asrole").value });
    await save(`${email} can open it now.`);
  });
  on("who", "keydown", (event) => {
    if (event.key === "Enter") at("add").click();
  });

  root.querySelectorAll("[data-role]").forEach((pick) =>
    pick.addEventListener("change", async () => {
      const person = list.people[Number(pick.dataset.role)];
      if (!person) return;
      if (pick.value === "remove") {
        list.people.splice(Number(pick.dataset.role), 1);
        return await save(`${person.email} cannot open it now.`);
      }
      person.role = pick.value;
      await save(`${person.email} is ${pick.value === "editor" ? "an editor" : "a viewer"}.`);
    })
  );

  root.querySelectorAll("[data-dropinvite]").forEach((button) =>
    button.addEventListener("click", async () => {
      list.invites.splice(Number(button.dataset.dropinvite), 1);
      await save("That invite will not work now.");
    })
  );

  root.querySelectorAll("[data-copyinvite]").forEach((button) =>
    button.addEventListener("click", async () => {
      const one = list.invites[Number(button.dataset.copyinvite)];
      if (!one || !one.key) return draw(say("That invite was made before addresses were kept. Make a new one.", true));
      await toClipboard(`${location.origin}${HUB.base || `/f/${HUB.project}`}/join?i=${one.key}`, "Invite copied.");
    })
  );

  // ---- general access ----------------------------------------------------
  on("general", "change", async () => {
    const link = general();
    if (at("general").value === "anyone") {
      if (!link) return await makeLink();
      // **The same address as before.** Switching it back on does not mint a
      // new one, which is the whole point: a link he sent last month starts
      // working again rather than a new one needing to be sent.
      link.off = false;
      return await save("Anyone with the link can read it again. It is the same link as before.");
    }
    // **Done at once, with Undo in the pill** instead of a question: the link
    // itself is kept, so turning it back on is all that undoing needs.
    const wasOn = Boolean(link && !link.off);
    if (link) link.off = true;
    await save("Only the people above can open it. The link is kept and will work again if you turn it back on.");
    if (wasOn && window.feel) {
      feel.toast("Link Turned Off", {
        undo: async () => {
          // **The link in hand is the old list's:** a save replaces `list` with
          // the hub's answer, so Undo finds the link again before it turns it on.
          const again = general() || link;
          again.off = false;
          await save("Anyone with the link can read it again. It is the same link as before.");
        },
      });
    }
  });

  // **Saved as it is changed**, like everything else on this panel. An Apply
  // button is a second thing to remember and a way to lose a change.
  on("haspass", "change", async () => {
    const open = general();
    if (!open) return;
    const ck = at("haspass").nextElementSibling;
    if (ck) ck.classList.toggle("on", at("haspass").checked);
    if (at("haspass").checked) {
      // Drawn only once it is asked for, and given the cursor straight away.
      const field = document.createElement("input");
      field.id = "linkpass";
      field.className = "sp-in slim";
      field.type = "password";
      field.placeholder = "Password";
      field.autocomplete = "new-password";
      const tick = at("haspass").closest(".sp-tick");
      tick.parentNode.insertBefore(field, tick.nextSibling);
      field.addEventListener("change", passwordTyped);
      field.focus();
      return;
    }
    open.salt = null;
    open.pass = null;
    await save("The link asks for no password now.");
  });

  on("linkpass", "change", passwordTyped);

  // **Renaming keeps the old name.** `hla` stays an alias for the film after
  // he changes it to `crown`, so a link already sent under it goes on working.
  on("short", "change", async (event) => {
    const wanted = String(event.target.value || "").trim().toLowerCase();
    if (wanted === HUB.short) return;
    if (!/^[a-z0-9]{2,24}$/.test(wanted)) {
      say("A short name is 2 to 24 letters or digits.", true);
    } else {
      try {
        const got = await fetch(`/f/${HUB.project}/api/short`, {
          method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify({ short: wanted }),
        });
        if (got.status === 409) say("Another film has that name.", true);
        else if (!got.ok) throw new Error(String(got.status));
        else { HUB.short = wanted; say("Short name set."); }
      } catch {
        say("That would not save.", true);
      }
    }
    draw();
  });

  // **Copy link gives an address that works.** His report: it handed over one
  // that asked for a sign-in. It did that whenever there was nothing to copy —
  // access Restricted, or the only link made before addresses were kept. In
  // both cases the thing to do is make one and say so, rather than copy
  // something that turns his director away at the door.
  on("copy", "click", async () => {
    const address = linkAddress();
    // **Copied, and told the truth about.** The address of a link that is
    // switched off is still the address — it is what he already sent people —
    // but handing it over without saying it currently opens nothing would be
    // the same silence that made him distrust these links in the first place.
    if (address && kept()) return await toClipboard(address, "Link copied. It is switched off right now.");
    if (address) return await toClipboard(address, "Link copied.");
    const replacing = lost();
    await makeLink();
    await toClipboard(
      linkAddress(),
      replacing
        ? "Made a new link and copied it. The old address has stopped working."
        : "Made a link anyone can open, and copied it."
    );
  });
}

async function passwordTyped(event) {
  const open = general();
  const word = event.target.value;
  if (!open || !word) return;
  // The salt is random and the hub only ever sees the hash of salt + word, so
  // it can check an answer and could never work the word out.
  open.salt = randomHex(32);
  open.pass = await sha256Hex(open.salt + word);
  await save("The link asks for that password now.");
}

async function makeLink() {
  const key = keyOf(24);
  list.links = [
    { hash: await sha256Hex(key), key, role: "viewer", note: "", off: false, expires: null, salt: null, pass: null },
  ];
  await save("Anyone with the link can read it now.");
}

async function save(said) {
  if (busy) return;
  busy = true;
  try {
    list = await api("PUT", list);
    say(said || "Saved.");
    if (window.feel) feel.toast("Saved");
  } catch (error) {
    say("That would not save.", true);
  }
  busy = false;
  draw();
}

async function toClipboard(text, said) {
  const word = /invite/i.test(said || "") ? "Invite Copied" : /view/i.test(said || "") ? "View Link Copied" : "Link Copied";
  const done = window.feel
    ? await feel.copy(text, word)
    : await navigator.clipboard.writeText(text).then(() => true, () => false);
  // Refused, which a browser does outside a trusted gesture — so show it
  // rather than claim it was copied.
  say(done ? said : text);
  draw();
}

function say(what, wrong) {
  saying = what;
  bad = Boolean(wrong);
}

async function api(method, body) {
  const got = await fetch(`/f/${HUB.project}/api/people`, {
    method,
    headers: body ? { "content-type": "application/json" } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!got.ok) throw new Error(String(got.status));
  const said = await got.json();
  // Whatever the list now is, it is what the next opening draws.
  if (said && Array.isArray(said.people)) held = said;
  return said;
}

/** Where unlisted links are served: the same domain with `share.` in front. */
function shareOrigin() {
  const host = location.host;
  if (host.startsWith("share.")) return location.origin;
  if (host.startsWith("localhost") || host.startsWith("127.")) return location.origin;
  return `${location.protocol}//share.${host}`;
}

function keyOf(bytes) {
  const raw = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...raw)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function randomHex(chars) {
  const raw = crypto.getRandomValues(new Uint8Array(chars / 2));
  return [...raw].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function initials(email) {
  if (!email) return "·";
  const name = email.split("@")[0].replace(/[^A-Za-z]+/g, " ").trim().split(/\s+/).filter(Boolean);
  if (!name.length) return email[0].toUpperCase();
  return (name[0][0] + (name[1] ? name[1][0] : "")).toUpperCase();
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );
}

