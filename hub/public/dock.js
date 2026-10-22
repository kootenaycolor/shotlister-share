/**
 * **The phone's dock, and the touch rules** (moves 1 and 6 of
 * `design/30-portal-phone.src.html`).
 *
 * The markup is drawn by the page (`phoneParts` in `src/pages.js`, and
 * `appPhoneParts` in `film.js` inside the program): a floating dock with the
 * page pill, a Find button and, for an editor, a round +. The pill opens the
 * sidebar sheet through `rail.js`'s own `data-sheet`. What this file does:
 *
 * - **Find** opens the ⌘K box (`jump.js`) by sending it the key it already
 *   listens for, and keeps that box above the on-screen keyboard.
 * - **+** opens Add (`add.js`), aimed at the heading the current page sits
 *   under. It is the same menu a desk's + opens; the phone only draws it as a
 *   sheet.
 * - **The dock leaves while the page scrolls down and returns on scroll up.**
 * - **A swipe from the left edge goes back**, on a phone, never inside a
 *   sheet and never on a canvas that pans.
 * - **A sheet that is not the sidebar drags down to close** (the ⌘K box and the
 *   shared sheets). The sidebar's own drag is `rail.js`.
 *
 * Everything is heard once, on the document: the pages are swapped in place by
 * `deep.js`, so nothing here is attached to a thing that goes away. A desk
 * never matches `onPhone()`, so none of it runs there.
 */

const PHONE = "(max-width:700px), (max-height:480px) and (pointer:coarse)";
const onPhone = () => window.matchMedia(PHONE).matches;
const hit = (event, sel) => (event.target instanceof Element ? event.target.closest(sel) : null);

/* ===========================================================================
   Find and Add
   =========================================================================== */

document.addEventListener("click", (event) => {
  if (hit(event, "[data-dockfind]")) {
    event.preventDefault();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true, ctrlKey: true, bubbles: true, cancelable: true }));
    keepAboveKeyboard();
    return;
  }
  const add = hit(event, "[data-dockadd]");
  if (add) {
    event.preventDefault();
    const frame = add.closest(".fh2") || document;
    const rail = frame.querySelector("nav.rail[data-arrange]");
    const anchor = rail && rail.querySelector(".railadd");
    if (!rail || !anchor || !window.addMenu) { location.href = add.getAttribute("href"); return; }
    // **The heading the page you are on sits under**, or none for a page that
    // is not on the sidebar (the Library, the film's home).
    const here = rail.querySelector(".sections .to.on");
    const group = here && here.closest(".group[data-head]");
    window.addMenu.open(anchor, { head: group ? group.dataset.head || "" : "", side: "top" });
  }
});

/** Lift the ⌘K sheet by however much of the screen the keyboard has taken. */
function keepAboveKeyboard() {
  const vv = window.visualViewport;
  if (!vv || !onPhone()) return;
  const lift = () => {
    const box = document.querySelector(".jumpshroud");
    if (!box) { vv.removeEventListener("resize", lift); vv.removeEventListener("scroll", lift); return; }
    const hidden = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
    box.style.setProperty("--kb", `${Math.round(hidden)}px`);
  };
  vv.addEventListener("resize", lift);
  vv.addEventListener("scroll", lift);
  setTimeout(lift, 60);
}

/* ===========================================================================
   The dock leaves on the way down and returns on the way up
   =========================================================================== */

let lastY = 0;
let acc = 0;
const docks = () => [...document.querySelectorAll(".fh2 .dock")];
const away = (on) => { for (const d of docks()) d.classList.toggle("away", on); };

document.addEventListener("scroll", (event) => {
  if (!onPhone()) return;
  const t = event.target;
  if (t !== document && t !== document.documentElement && t !== document.body && t !== document.scrollingElement) return;
  const y = Math.max(0, window.scrollY || 0);
  const moved = y - lastY;
  lastY = y;
  if (document.body.classList.contains("railopen")) return;
  if (y < 60) { acc = 0; away(false); return; }
  // Direction counts only once it has gone a little way, so a jitter is not a hide.
  acc = Math.sign(moved) === Math.sign(acc) ? acc + moved : moved;
  if (acc > 14) away(true);
  else if (acc < -8) away(false);
}, true);

// A page swapped in place starts with the dock showing.
document.addEventListener("swapped", () => { lastY = Math.max(0, window.scrollY || 0); acc = 0; });

/* ===========================================================================
   Swipe from the left edge: back
   ========================================================================== */

const EDGE = 20;       // the first twenty pixels
const FAR = 72;        // how far it has to go
let edge = null;

/** Somewhere a finger is already doing something else (a canvas that pans). */
function busyHere(el) {
  if (el.closest("canvas, svg, input, textarea, select, [contenteditable]")) return true;
  for (let n = el, i = 0; n && n !== document.body && i < 10; n = n.parentElement, i += 1) {
    if (getComputedStyle(n).touchAction === "none") return true;
  }
  return false;
}

document.addEventListener("touchstart", (event) => {
  edge = null;
  if (!onPhone() || event.touches.length !== 1) return;
  const t = event.touches[0];
  if (t.clientX > EDGE) return;
  const el = event.target instanceof Element ? event.target : null;
  if (!el) return;
  if (document.body.classList.contains("railopen")) return;
  if (el.closest(".fx-pop, .jumpshroud, .sp-scrim, .shroud, .popout, .fh-scrim")) return;
  if (busyHere(el)) return;
  edge = { x: t.clientX, y: t.clientY };
}, { passive: true });

document.addEventListener("touchmove", (event) => {
  if (!edge) return;
  const t = event.touches[0];
  const dx = t.clientX - edge.x;
  const dy = Math.abs(t.clientY - edge.y);
  if (dy > 60 && dy > dx) { edge = null; document.body.classList.remove("swiping"); return; }
  if (dx > 8) {
    document.body.classList.add("swiping");
    document.body.style.setProperty("--swipe", String(Math.min(dx, 90)));
  }
}, { passive: true });

const endSwipe = (event, cancelled) => {
  const had = edge;
  edge = null;
  document.body.classList.remove("swiping");
  document.body.style.removeProperty("--swipe");
  if (!had || cancelled) return;
  const t = event.changedTouches[0];
  if (t.clientX - had.x > FAR && Math.abs(t.clientY - had.y) < 60) history.back();
};
document.addEventListener("touchend", (event) => endSwipe(event, false));
document.addEventListener("touchcancel", (event) => endSwipe(event, true));

/* ===========================================================================
   Sheets other than the sidebar drag down to close
   ========================================================================== */

const CARDS = ".jumpcard";
let pull = null;

function closeCard(card) {
  const shroud = card.closest(".jumpshroud");
  if (shroud) { shroud.dispatchEvent(new MouseEvent("mousedown", { bubbles: true })); return; }
  document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
}

document.addEventListener("touchstart", (event) => {
  pull = null;
  if (!onPhone() || event.touches.length !== 1) return;
  const card = hit(event, CARDS);
  if (!card) return;
  // A list with somewhere left to go owns the drag; only from its top is it the sheet's.
  const list = hit(event, ".jumplist, .sp-root, [data-scroll]");
  if (list && list.scrollTop > 0) return;
  pull = { card, y: event.touches[0].clientY, t: performance.now(), dy: 0 };
}, { passive: true });

document.addEventListener("touchmove", (event) => {
  if (!pull) return;
  const dy = event.touches[0].clientY - pull.y;
  if (dy <= 0) { pull.card.style.transform = ""; pull.dy = 0; return; }
  pull.dy = dy;
  pull.card.style.transition = "none";
  pull.card.style.transform = `translateY(${dy}px)`;
}, { passive: true });

const letGo = () => {
  const p = pull;
  pull = null;
  if (!p) return;
  const fast = p.dy / Math.max(1, performance.now() - p.t) > 0.5;
  p.card.style.transition = "";
  p.card.style.transform = "";
  if (p.dy > 96 || (p.dy > 30 && fast)) closeCard(p.card);
};
document.addEventListener("touchend", letGo);
document.addEventListener("touchcancel", letGo);
