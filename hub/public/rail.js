/**
 * The rail's own two behaviours: the sheet on a phone, and scroll bars that
 * know when to leave.
 *
 * **Deliberately apart from `deep.js`.** That file owns *navigation* — which
 * click becomes a page load, what travels between two screens, and the whole
 * choreography of the move. These two are furniture: they are true of a page
 * standing still, they need no knowledge of where you came from, and they must
 * work on a screen that never navigates at all. Keeping them here means the
 * navigation file stays about navigation, and it means the program half of the
 * portal can pick this up later without importing the front of house's ideas
 * about routing.
 *
 * Both are small on purpose. Neither should ever grow a second job.
 */

/* ===========================================================================
   Scroll bars, drawn

   `hub.css` already made the native bar quiet on 2026-09-02 — no track, a
   translucent capsule in the ink already in use. What it could not do is make
   it **leave**: macOS draws its classic bars permanently whenever a mouse is
   attached, and `::-webkit-scrollbar` parts cannot be animated, so there is no
   fading them out.

   His instruction, 2026-09-04: *"they should be integrated into the design, not
   always there, only appearing when scrolling or hovering over."* So the native
   one is switched off wherever we take over, and the thumb is drawn: sized and
   placed from `scrollTop`, shown while you scroll or while the pointer is over
   the area, faded out about a second after you stop.

   **The host is the element that does not scroll.** A thumb parented to the
   scroller would scroll away with the content, which is the one mistake this
   whole idea can make.                                                       */

const IDLE = 900;

export function slimScroll(el, axis = "y") {
  const host = el.closest(".host") || el.parentElement;
  if (!host || el.dataset.slim === axis) return;      // never wire one twice
  el.dataset.slim = axis;

  const bar = document.createElement("i");
  bar.className = `sbar ${axis}`;
  host.appendChild(bar);

  let idle;
  let over = false;

  const draw = () => {
    const room = axis === "y" ? el.clientHeight : el.clientWidth;
    const whole = axis === "y" ? el.scrollHeight : el.scrollWidth;
    if (whole <= room + 1) {                          // nothing to scroll
      bar.classList.remove("seen");
      return false;
    }
    const size = Math.max(26, room * (room / whole));
    const at = ((axis === "y" ? el.scrollTop : el.scrollLeft) / (whole - room)) * (room - size);
    if (axis === "y") {
      bar.style.height = `${size}px`;
      bar.style.transform = `translateY(${at}px)`;
    } else {
      bar.style.width = `${size}px`;
      bar.style.transform = `translateX(${at}px)`;
    }
    return true;
  };
  const show = () => { if (draw()) bar.classList.add("seen"); };
  const later = () => {
    clearTimeout(idle);
    idle = setTimeout(() => { if (!over) bar.classList.remove("seen"); }, IDLE);
  };

  el.addEventListener("scroll", () => { show(); later(); }, { passive: true });
  host.addEventListener("pointerenter", () => { over = true; show(); });
  host.addEventListener("pointerleave", () => { over = false; later(); });
  // A list that grows or shrinks — a search narrowing it — changes the thumb's
  // size, and nothing else would tell us.
  new ResizeObserver(() => draw()).observe(el);
  el.refreshBar = draw;
  draw();
}

/** Every scroller on the page that has asked for ours. */
export function slimAll(root = document) {
  for (const el of root.querySelectorAll(".scrolls")) {
    slimScroll(el, el.dataset.axis === "x" ? "x" : "y");
  }
}

/* ===========================================================================
   The sheet, on a phone

   The rail is a column beside the work on a desk. Laid *above* the work on a
   phone it costs the top of the screen permanently, and a rail that can hold a
   hundred and eighty scenes cannot afford that — measured before this was
   rewritten, 675 of 862 pixels were chrome and the first shot began 758 down.

   So on a phone it is a sheet, raised from a bar at the bottom, and the work
   gets the screen.                                                           */

/* **`railopen`, not `sheet`, and the name is the whole point.** `hub.css` has
   owned `.sheet` since long before this — the script panel's paper, at 11px
   monospace with `white-space: pre-wrap` and `margin: 0 10px 12px`. Putting
   that word on `<body>` handed the entire document all of it: every newline in
   every template became a real line box (the "ton of spacing"), the paper came
   out white behind the page, and the margin drew the two white bars down the
   sides he photographed. One class name, all three faults. */
const PHONE = "(max-width:700px), (max-height:480px) and (pointer:coarse)";
const onPhone = () => window.matchMedia(PHONE).matches;

/* **The page has to be parked, not just hidden behind something.** Fixing the
   body is the only thing iOS Safari reliably honours, and fixing it throws the
   document back to the top — so the offset is held here and handed back on the
   way out. Without the second half the sheet closes onto a page that has jumped
   to its first line. */
let parked = 0;

function sheet(on) {
  const b = document.body;
  if (b.classList.contains("railopen") === on) return;   // nothing to do
  if (on) {
    parked = window.scrollY || window.pageYOffset || 0;
    if (onPhone()) b.style.top = `${-parked}px`;
    b.classList.add("railopen");
  } else {
    b.classList.remove("railopen");
    b.style.top = "";
    if (onPhone()) window.scrollTo(0, parked);
  }
  loose();                       // a half-finished drag must not outlive it
}

/* ===========================================================================
   Dragged shut

   His report, 2026-09-04: *"i can't drag and click the tab bar to slide it back
   down to it's drawer…i can only tap outside of it to make it go away"*. Tapping
   the scrim is the way out you find by accident; pulling the sheet down is the
   one a thumb reaches for, and on a phone held in one hand it is the only one
   within reach at all.

   **Listened for on the document, not on the rail.** The program repaints its
   rail on every mode change, so a listener bound to the element is thrown away
   the first time you switch section — and the gesture would work once. */

const SHUT_BY = 96;    // far enough down that he meant it
const FLICK = 0.5;     // …or fast enough that he meant it, px per ms

let y0 = 0, t0 = 0, dy = 0, live = false, list = null, rail = null, veil = null;

const at = (e) => (e.touches && e.touches[0]) || e;
/* **The scrim beside the rail being dragged, not the first one in the
   document.** Once the app has been woken there are two pages in the
   document, one put away — and `document.querySelector(".fh2 .fh-scrim")`
   found the hidden one, so the dimming behind the sheet did not follow the
   finger. Found in the 2026-09-16 sweep. */
const scrim = () => (rail && rail.closest(".fh2") ? rail.closest(".fh2").querySelector(".fh-scrim") : null);

/** Put everything back the way the stylesheet left it. */
function loose() {
  if (rail) { rail.style.transform = ""; rail.classList.remove("dragging"); }
  if (veil) veil.style.opacity = "";
  live = false; rail = null; list = null; veil = null;
}

function grab(e) {
  if (live || !document.body.classList.contains("railopen")) return;
  const el = e.target;
  rail = el && el.closest ? el.closest(".rail") : null;
  if (!rail) return;
  /* **A list with somewhere left to go owns the drag.** Only when it is already
     at its top does pulling down mean the sheet rather than the list — which is
     the rule every iOS sheet follows, and the reason a drag inside the scene
     list still scrolls the scene list. */
  list = el.closest(".sections, .scopedlist, .panellist");
  if (list && list.scrollTop > 0) { rail = null; return; }
  y0 = at(e).clientY;
  t0 = e.timeStamp || Date.now();
  dy = 0; live = true;
  veil = scrim();
  rail.classList.add("dragging");
}

function haul(e) {
  if (!live || !rail) return;
  // A row being carried (`arrange.js`) is not the sheet being pulled down.
  if (document.body.classList.contains("arranging") || document.body.classList.contains("holding")) { loose(); return; }
  dy = at(e).clientY - y0;
  if (dy <= 0) {
    /* Pulled upwards. If this began in a list, it was a scroll all along —
       hand it back rather than holding a gesture the list should have had. */
    rail.style.transform = "";
    if (list) loose();
    return;
  }
  if (e.cancelable) e.preventDefault();
  rail.style.transform = `translateY(${dy}px)`;
  if (veil) veil.style.opacity = String(Math.max(0, 1 - dy / (rail.offsetHeight || 400)));
}

function drop(e) {
  if (!live || !rail) return;
  const ms = Math.max(1, (e.timeStamp || Date.now()) - t0);
  const meant = dy > SHUT_BY || dy / ms > FLICK;
  loose();
  if (meant) sheet(false);
}

document.addEventListener("touchstart", grab, { passive: true });
document.addEventListener("touchmove", haul, { passive: false });
document.addEventListener("touchend", drop);
document.addEventListener("touchcancel", drop);
/* A mouse as well — a narrow window on the desk gets the sheet too, and it is
   the only way any of this can be checked without a phone in your hand. */
document.addEventListener("mousedown", grab);
document.addEventListener("mousemove", haul);
document.addEventListener("mouseup", drop);

document.addEventListener("click", (e) => {
  const said = e.target.closest("[data-sheet]");
  if (said) {
    sheet(said.dataset.sheet === "open");
    return;
  }
  // Going somewhere closes it — you asked to look at something. `deep.js` is
  // what actually moves; this only gets out of the way.
  //
  // **A row is a link on the record's pages and a button inside the program**,
  // because switching there must not be a page load. Matching only `a` meant
  // the sheet stayed up over the thing you had just asked to see.
  if (e.target.closest(".rail a, .rail [data-mode], .rail [data-scene], .rail [data-pick]")) sheet(false);
});

/* ===========================================================================
   The page menu (Ref 1153)

   Its items open one of the page's own forms under the title. With no script
   that is `:target` in front.css; with one it is a class, because a page
   landed in place by `deep.js` never gets its `:target` set, and a hash change
   would put a second copy of the page in the back history for every press.
   A click anywhere else puts an open menu away, the way any menu goes.       */

function showAct(id) {
  for (const open of document.querySelectorAll(".pageact.open")) open.classList.remove("open");
  const act = id ? document.getElementById(id) : null;
  if (!act || !act.classList.contains("pageact")) return;
  act.classList.add("open");
  act.scrollIntoView({ block: "nearest" });
  const field = act.querySelector("input[type=text], textarea");
  if (field) field.focus();
}

document.addEventListener("click", (e) => {
  const item = e.target.closest('a[href^="#pa-"], a.pashut');
  if (item) {
    e.preventDefault();
    const menu = item.closest("details");
    if (menu) menu.open = false;
    showAct(item.classList.contains("pashut") ? "" : item.getAttribute("href").slice(1));
    return;
  }
  for (const menu of document.querySelectorAll("details.pagemenu[open]")) {
    if (!menu.contains(e.target)) menu.open = false;
  }
});

// Escape shuts it, because a sheet over the whole screen with no visible way
// out is a trap for anybody who opened it by accident.
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && document.body.classList.contains("railopen")) sheet(false);
});

/* ===========================================================================
   The way back, measured

   The way to the other films is an arrow, and the word *Projects* is held at
   `max-width:0` behind it and slides out on hover. A slide needs a distance,
   and the distance is however wide that word happens to be — which depends on
   the font that actually loaded, so it cannot honestly be written into a
   stylesheet. `front.css` carries a generous fallback, which is what a page
   with no script at all still gets; this replaces it with the truth, so the
   reveal finishes exactly when the animation does instead of stopping short.

   `scrollWidth` reports the content width even while the element is clamped to
   nothing, so nothing has to be shown to be measured.                        */

function measureBack() {
  for (const word of document.querySelectorAll(".railtop .back .bw")) {
    const wide = word.scrollWidth;
    if (wide) word.style.setProperty("--bw", `${wide}px`);
  }
}

slimAll();
measureBack();

/* **The web font arrives after the first paint and is wider than the fallback
   it replaces.** Measuring once would leave the word clipped by a few pixels
   on every load, which is the kind of fault that only shows on a cold cache. */
if (document.fonts && document.fonts.ready) document.fonts.ready.then(measureBack);

/* `deep.js` swaps the page under us, so the new one's scrollers need wiring
   and the sheet needs to be shut. It says nothing to us directly — this
   watches the document instead, which means neither file has to know the
   other exists. */
new MutationObserver(() => { slimAll(); measureBack(); })
  .observe(document.body, { childList: true, subtree: true });

/* ---- the shoot switcher (Ref 1413) ---------------------------------------
   Its list opens on the shoot you are on, so with many shoots the one that
   matters is in view; a press anywhere else, or Escape, shuts it. Listened
   for on the document, so the program's rail, drawn again on every change,
   is covered too. */
document.addEventListener("toggle", (event) => {
  const menu = event.target;
  if (!(menu instanceof HTMLDetailsElement) || !menu.classList.contains("shootmenu") || !menu.open) return;
  const on = menu.querySelector(".shootrow.on");
  const list = menu.querySelector(".shootlist");
  if (on && list) list.scrollTop = Math.max(0, on.offsetTop - list.clientHeight / 2 + on.offsetHeight / 2);
}, true);
document.addEventListener("click", (event) => {
  for (const menu of document.querySelectorAll("details.shootmenu[open]")) {
    if (!menu.contains(event.target)) menu.open = false;
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  for (const menu of document.querySelectorAll("details.shootmenu[open]")) menu.open = false;
});


/* ===========================================================================
   The Library's search box

   Narrows the Library's rows as you type, by name. A plain page with no script
   shows them all, which is the right answer for a list this short.             */

document.addEventListener("input", (event) => {
  const box = event.target;
  if (!(box instanceof HTMLInputElement) || !box.hasAttribute("data-libfind")) return;
  const said = box.value.trim().toLowerCase();
  for (const card of document.querySelectorAll(".fh-card")) card.hidden = Boolean(said) && !(card.dataset.find || "").includes(said);
  // A shelf with nothing left on it goes quiet with its cards.
  for (const shelf of document.querySelectorAll(".fh-shelf")) {
    shelf.hidden = Boolean(said) && shelf.querySelectorAll(".fh-card:not([hidden])").length === 0;
  }
  const archive = document.querySelector(".fh-archive");
  if (archive && said) archive.open = archive.querySelectorAll(".fh-card:not([hidden])").length > 0;
});

/* The shelf chips are filters: a shelf shows only itself, All shows everything.
   Plain anchors without this, so they still jump to the shelf with no script. */
document.addEventListener("click", (event) => {
  const chip = event.target instanceof Element ? event.target.closest(".fh-shelves a[data-shelf]") : null;
  if (!chip) return;
  event.preventDefault();
  const want = chip.dataset.shelf;
  for (const one of chip.parentElement.querySelectorAll("a[data-shelf]")) {
    const on = one === chip;
    one.classList.toggle("on", on);
    one.setAttribute("aria-pressed", String(on));
  }
  for (const shelf of document.querySelectorAll(".fh-shelf, .fh-archive")) {
    if (want === "all" || shelf.id === want) shelf.removeAttribute("data-off");
    else shelf.setAttribute("data-off", "");
  }
  const archive = document.querySelector(".fh-archive");
  if (archive && want === "shelf-archive") archive.open = true;
  const pane = document.querySelector(".fh-pane");
  if (pane) pane.scrollTop = 0;
});

/* A card's menu closes when you click anywhere else, and when another opens. */
document.addEventListener("click", (event) => {
  for (const open of document.querySelectorAll(".fh-cardmenu[open], .fh-shelfmenu[open], .fh-addshelf[open]")) {
    if (!open.contains(event.target)) open.removeAttribute("open");
  }
});
