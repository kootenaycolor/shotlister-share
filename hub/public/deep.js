// Moving about the record without leaving the page.
//
// **Why this exists at all.** The mockup he approved was one file: clicking a
// name in the rail called `document.startViewTransition` and swapped a `<div>`,
// which is instant and is why it felt the way it did. The real thing is four
// separate addresses, so the same click became a full page load — the browser
// still starts a transition, but then sits on a blank frame waiting for the
// network before it can draw the second half. His words: *"the animations are
// not working. between clicks."* He was right; a transition that fired is not a
// transition anybody saw.
//
// So the addresses stay real — they can be linked to, bookmarked, opened in a
// new tab, and they still work with this file missing — and the click stops
// being a page load. We fetch the same address, take its `.fh2` out, and swap
// it in under a view transition. The browser never leaves the document.
//
// **The rules are the mockup's rules**, and the mockup wrote down why:
//
//   > Motion means you have gone somewhere. Moving between two names in the
//   > rail is not going somewhere — it is the same place showing something
//   > else, and animating it made every click look like a jump. So a sibling
//   > move just swaps. Only arriving and leaving are travelled.
//
// Only `a[data-deep]` is caught. The door into Shotlister is not marked and is
// meant not to be: that address starts the engine, and pretending it is a swap
// would be a lie told in an animation.

const HOLD = 120000; // how long a fetched page may be reused

const warm = new Map();
/** Addresses already asked for once, so a hover does not ask again. */
const asked = new Set();

/**
 * **When the rail was last changed on this page, and the save carrying it.**
 *
 * A page fetched before a drag carries the rail as it was before the drag —
 * every kept page did, and so did the four fetched ahead of the click — so a
 * click along the rail after arranging it put the row straight back. His ask,
 * 2026-09-10, for saving that is *"faster and more fluid"*. `arrange.js` says
 * `arranging` at the moment of the change, with the save as its detail, and
 * `arranged` once it has landed. Anything fetched before the change is stale;
 * anything fetched after it waits for the save, or the worker would answer
 * with the film as it was a moment ago.
 */
let arrangedAt = 0;
let settling = null;
document.addEventListener("arranging", (event) => {
  arrangedAt = Date.now();
  settling = event.detail instanceof Promise ? event.detail : null;
  asked.clear();
});
document.addEventListener("arranged", () => {
  settling = null;
  settle();
});

/** Whether a kept page may still be used. */
function fresh(have) {
  return Boolean(have) && have.at >= arrangedAt && Date.now() - have.at < HOLD;
}

/** The page at an address, fetched once and briefly kept. */
function pageAt(href) {
  const have = warm.get(href);
  if (fresh(have)) return have.said;
  const waited = settling ? settling.catch(() => {}) : Promise.resolve();
  const said = waited.then(() => fetch(href, { credentials: "same-origin" })).then((answer) => {
    if (!answer.ok) throw new Error(String(answer.status));
    return answer.text();
  });
  // **A refusal must not be remembered.** A failed fetch left in the map would
  // make every later click fail the same way for twenty seconds, long after
  // whatever caused it had passed.
  said.catch(() => warm.delete(href));
  warm.set(href, { at: Date.now(), said });
  return said;
}

/**
 * Home, or a page under the film.
 *
 * **Not a list of the four built-in pages.** It was, and his own Notion
 * sections — Lens Character, a lighting plan — came back as "home", so Back
 * or Forward onto one of them ran the going-home choreography (the title
 * growing, the rail re-arriving) onto a page that is a sibling of the one
 * before it. Found in the 2026-09-16 sweep. Home is the film's own address
 * and nothing else: `/<slug>` or `/f/<id>`; anything with a segment after
 * that is a page of the record — Add, Headings and Share included.
 */
function kindOf(path) {
  const parts = String(path || "").replace(/\/+$/, "").split("/").filter(Boolean);
  const under = parts[0] === "f" ? parts.slice(2) : parts.slice(1);
  return under.length ? "record" : "home";
}

// **The last click wins.** Two `go`s can be in the air at once — a slow one
// started first and a fast one started second — and without this the slow one
// lands last and puts you somewhere you have already left. Clicking twice down
// the rail did exactly that, every time.
let latest = 0;

/**
 * Put the page at `href` on screen.
 *
 * Anything unexpected hands the click back to the browser, which is the whole
 * safety net here: the addresses are real, so the worst case is the behaviour
 * we had before this file existed.
 */
async function go(href, kind, push) {
  const mine = ++latest;
  // **A skeleton, only when the wait is long enough to see.** His note on Ref
  // 1161: *"loading skeleton would still be cool where we can add it."* The
  // pages arrive whole, so there is nothing to fill in piece by piece — but
  // between the click and the page there can be a wait, on a phone on a set,
  // and a pane that sits unchanged through it reads as a click that missed. A
  // kept page lands at once and never shows one; anything slower than a
  // blink shows the page's shape until the page arrives (`.fh-waiting`).
  const slow = fresh(warm.get(href)) ? null : setTimeout(() => { if (mine === latest) waiting(true); }, 150);
  let said;
  try {
    said = await pageAt(href);
  } catch {
    leaveFor(href);
    return;
  } finally {
    clearTimeout(slow);
  }
  if (mine !== latest) return;
  waiting(false);
  place(said, href, kind, push, mine);
}

function waiting(on) {
  const pane = frontHalf() && frontHalf().querySelector(".fh-pane");
  if (!pane) return;
  pane.classList.toggle("fh-waiting", on);
  // The shape is drawn at the top, where the page will land.
  if (on) pane.scrollTop = 0;
}

/**
 * Put a page that has already arrived on screen.
 *
 * **Split out of `go` so a form can land the same way a link does.** His
 * report, 2026-09-08: *"it takes a long time to save stuff ... every click is a
 * completely new save and reload situation."* Moving about the record has never
 * been a reload — this file has swapped `.fh2` in place since 2026-09-03 — but
 * every *save* was a plain form post, which is the browser's own full page
 * load: the stylesheet, the scripts and the wasm all fetched and parsed again
 * to draw a page that differs by one word. The saving was never the slow part.
 */
/**
 * **The half of the document he is looking at — never the app's frame.**
 *
 * `document.querySelector(".fh2")` was the page for as long as the page was
 * the only `.fh2` in the document. Once the app has been woken it is a second
 * one, inside `#film` — and when the document *began* in the app (a share
 * link, a reload on the shot list) the film's page is fetched later and lands
 * after it, so "the first `.fh2`" is the app, put away and invisible. Every
 * record row pressed from there swapped the new page into the hidden app,
 * replacing the app itself: the screen did not change, the address did, and
 * the next press of Shot List showed the Visual Bible where the program used
 * to be. His report, 2026-09-16: *"on People or Camera Spec Sheet, sometimes
 * the clicks to other tabs don't work, but they work for certain tabs"* — the
 * app's rows still went through `enterApp`, which is why those worked.
 *
 * The stage knows which half is the page once both exist; before that, the
 * page is whichever `.fh2` is not inside the app's box.
 */
function frontHalf() {
  if (stage.front && stage.front.isConnected) return stage.front;
  return [...document.querySelectorAll(".fh2")].find((el) => !el.closest("#film")) || null;
}

function place(said, href, kind, push, mine = latest) {
  const came = new DOMParser().parseFromString(said, "text/html");
  const next = came.querySelector(".fh2");
  const here = frontHalf();
  // A page that is not front of house — a sign-in wall, an error — is not ours
  // to paint into this one.
  if (!next || !here) {
    leaveFor(href);
    return;
  }

  const named = came.title;
  const arrived = document.adoptNode(next);

  const swap = () => {
    here.replaceWith(arrived);
    // **The stage has to keep pointing at what is on screen.** Once the app has
    // been woken, `stage.front` is the half this just replaced — and a stale
    // pointer is an element no longer in the document, so the next press of the
    // shot list would put the app back beside a page nobody can see.
    if (stage.front === here) {
      stage.front = arrived;
      stage.at = new URL(href, location.href).pathname;
    }
    document.title = named;
    if (document.scrollingElement) document.scrollingElement.scrollTop = 0;
    // `copy.js` dresses what it finds at load; what just arrived it has never
    // seen. Wrapped because a listener that throws must not be able to take the
    // swap down with it — the page is already replaced by this point.
    try {
      document.dispatchEvent(new Event("swapped"));
    } catch {
      /* whatever was listening is its own problem */
    }
  };

  if (mine !== latest) return;
  if (push) history.pushState({ deep: kind }, "", href);

  // **Every move animates, but not every move is the same move.** Going from
  // one name in the rail to another is not arriving anywhere: the rail is the
  // same rail, in the same place, and sliding it in from the left again on
  // every click is the jitter he saw. Only the pane changed, so only the pane
  // moves. Arriving and leaving still travel whole.
  if (!document.startViewTransition) return plainly(swap, arrived);
  const root = document.documentElement;
  // **`athome` is why this is not simply "is there a rail".** The film's page
  // now wears `.deep` too, because the rail is on every page — so the old test
  // classed *home to a section* as a sibling and the title would have stopped
  // travelling without anything failing. It is the one move he asked to keep:
  // *"I love that animation - dont want ot give it up"*, 2026-09-04.
  //
  // Three kinds, and the middle one is the common one:
  //   home -> a section   the name leaves its big form      `entering`
  //   a section -> home   the name goes back to it          `leaving`
  //   section -> section  the rail is already right         `sibling`
  const athome = here.classList.contains("athome");
  const sibling = here.classList.contains("deep") && !athome && kind === "record";
  const how = athome && kind === "record" ? "entering" : kind === "home" ? "leaving" : "";
  if (sibling) root.classList.add("sibling");
  else if (how) root.classList.add(how);
  const moving = document.startViewTransition(swap);
  // **A transition that is abandoned still has to tidy up after itself.** One
  // started while another is running — an impatient second press — is aborted,
  // and `finished` *rejects*: `finally` alone leaves that rejection with nobody
  // to catch it, which is a red line in the console on a move that otherwise
  // worked perfectly.
  moving.finished.finally(() => root.classList.remove("sibling", "entering", "leaving")).catch(() => {});
}

document.addEventListener("click", (event) => {
  // Everything a browser does with a link that is not a plain left click — open
  // in a tab, in a window, download — stays the browser's.
  if (event.defaultPrevented || event.button !== 0) return;
  if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  const link = event.target.closest("a[data-deep]");
  if (!link || link.target || link.hasAttribute("download")) return;
  const to = new URL(link.href, location.href);
  if (to.origin !== location.origin) return;
  // The name you are already on is not a journey.
  if (to.pathname === location.pathname) {
    event.preventDefault();
    return;
  }
  event.preventDefault();
  if (link.dataset.deep === "app") waitOn(enterApp(to.href, link));
  // **Every link pressed inside the app is a way out of it, not just Home.**
  //
  // The app draws the record's own sections in its rail — Visual Bible, Camera
  // Spec Sheet, People — and those were handed to `go`, which replaces *the
  // first `.fh2` in the document*. Inside the app that is the film's page,
  // stowed out of sight behind the app: the fetched page took its place already
  // visible, nothing ever put the app away, and both halves stood in the
  // document at once — a whole Visual Bible page with a whole Mood Boards app
  // underneath it, each with its own rail. His report and his screenshot,
  // 2026-09-05: *"these two instances stack on top of each other"*.
  //
  // Leaving is a swap, so it is `leaveApp` that knows how to do it: put the app
  // away, put the film's page up. Which section is being asked for changes only
  // what that page holds.
  else if (link.closest("#film")) waitOn(leaveApp(to.href, link.dataset.deep, true));
  else waitOn(go(to.href, link.dataset.deep, true));
});

/**
 * **The bar across the top (`wait.js`) for a move made in place.** The
 * browser never loads a page here, so it would never say it was busy; this
 * says so. A move that falls back to a real page load leaves the bar running
 * for the new page to end — `wait.js` hears the page going.
 */
/** The fallback to a real page load, with the bar left running for it. */
function leaveFor(href) {
  if (window.portalWait) window.portalWait.away();
  location.href = href;
}

function waitOn(moving) {
  const bar = window.portalWait;
  if (!bar) return moving;
  bar.start();
  return Promise.resolve(moving).finally(() => bar.done());
}

/**
 * **A save says so, in the shared pill (`feel.js`).** Archive, Unarchive, Put
 * on Sidebar, Take Off Sidebar and Move To carry an Undo, because each can be
 * put back with the same form; a switch just says Saved. The Undo is the form
 * submitted again with the one value turned round, so it goes through this
 * very handler (and says Undone, not another Undo).
 */
function undoForm(form, changes) {
  const again = form.cloneNode(true);
  for (const [name, value] of Object.entries(changes)) {
    const field = again.elements[name];
    if (field) field.value = value;
  }
  again.dataset.said = "Undone";
  again.hidden = true;
  (form.closest(".fh2") || document.body).append(again);
  setTimeout(() => again.remove(), 4000);
  return () => { again.requestSubmit(); return false; };
}

function confirmed(form) {
  const feel = window.feel;
  if (!feel) return;
  if (form.dataset.said) return feel.toast(form.dataset.said);
  const field = (name) => (form.elements[name] ? form.elements[name].value : null);
  const to = new URL(form.action || location.href, location.href).pathname;
  if (/\/visibility$/.test(to)) return feel.toast("Saved");
  if (!/\/library$/.test(to)) return undefined;
  if (field("archive") !== null) {
    const on = field("on") === "1";
    return feel.toast(on ? "Archived" : "Unarchived", { undo: undoForm(form, { on: on ? "0" : "1" }) });
  }
  if (field("sidebar") !== null) {
    const on = field("on") === "1";
    return feel.toast(on ? "Put on Sidebar" : "Taken Off Sidebar", { undo: undoForm(form, { on: on ? "0" : "1" }) });
  }
  if (field("shelf") !== null) {
    const was = form.dataset.was;
    return feel.toast(`Moved to ${field("to")}`, was ? { undo: undoForm(form, { to: was }) } : {});
  }
  return undefined;
}

/**
 * **A save is a swap, not a reload.** His report, 2026-09-08: *"The UI for
 * adding pages and headings and stuff is very clunky and slow ... every click
 * is a completely new save and reload situation."*
 *
 * Every control on the portal is a plain `<form method="post">` on purpose —
 * these decide who sees a crew member's number and whether his writing survives
 * a refresh, and a control that only works once a script has arrived does
 * nothing on a bad connection on a shoot. **That reasoning is about whether the
 * form works, and it never asked for the fast path to be slow.**
 *
 * So the form is untouched and the *submitting* is caught: the same POST goes
 * out by `fetch`, which follows the redirect the worker already sends, and the
 * page that comes back is landed the way a link is landed — in place, under a
 * transition, with nothing re-fetched and nothing re-parsed. With this file
 * missing the browser does exactly what it did before.
 *
 * **The button says it is working.** A save that takes a moment and shows
 * nothing is the same experience as a save that has frozen.
 */
document.addEventListener("submit", async (event) => {
  if (event.defaultPrevented) return;
  const form = event.target;
  if (!(form instanceof HTMLFormElement)) return;
  if ((form.method || "").toLowerCase() !== "post" || !form.closest(".fh2")) return;
  // A form aimed somewhere else, or at another origin, is the browser's.
  const to = new URL(form.action || location.href, location.href);
  if (to.origin !== location.origin || form.target) return;
  // **A form that asks first** (`data-confirm`): Remove Category says what
  // happens to what is on it before anything goes.
  if (form.dataset.confirm && !confirm(form.dataset.confirm)) { event.preventDefault(); return; }

  event.preventDefault();
  const pressed = form.querySelector("button[type=submit], button:not([type])");
  // **A switch is pressed when it is pressed** (2026-10-02, his *"I want
  // things to feel 'instant'"*). Shown on Links, Shown for Me and every
  // switch like them turn over under the finger; the page the save lands
  // confirms it a moment later, or puts it back if the save failed. A form
  // that saves itself as it changes (Visibility) is never held up either.
  const flipping = pressed && pressed.classList.contains("pmswitch");
  const quiet = flipping || form.dataset.autosave !== undefined;
  if (flipping) {
    const on = !pressed.classList.contains("on");
    pressed.classList.toggle("on", on);
    pressed.setAttribute("aria-pressed", String(on));
  }
  if (pressed && !quiet) pressed.disabled = true;
  form.setAttribute("aria-busy", "true");
  // **Only the newest press lands.** Two saves in the air at once — two
  // switches pressed in a row — answer in any order, and landing the older
  // one last would show the page as it was before the second press.
  const mine = ++latest;

  if (window.portalWait && !quiet) window.portalWait.start();
  const done = () => {
    form.removeAttribute("aria-busy");
    if (pressed) pressed.disabled = false;
    if (window.portalWait && !quiet) window.portalWait.done();
  };

  try {
    const data = new FormData(form);
    const said = await fetch(to.href, {
      method: "POST",
      credentials: "same-origin",
      // **`URLSearchParams` unless there is a file.** `FormData` makes fetch
      // send multipart, which the worker reads either way — but a plain form
      // sends urlencoded, and the two paths should differ as little as they can.
      body: form.enctype === "multipart/form-data" ? data : new URLSearchParams(data),
      headers: { accept: "text/html" },
    });
    const text = await said.text();
    // **A switch that did not save goes back, and says so.**
    if (!said.ok && quiet) {
      if (flipping) {
        pressed.classList.toggle("on");
        pressed.setAttribute("aria-pressed", String(pressed.classList.contains("on")));
      }
      if (window.feel) window.feel.toast("Could Not Save");
      done();
      return;
    }
    // `fetch` follows the 303 the worker sends, so this is where we landed.
    const landed = said.url || to.href;
    const kind = kindOf(new URL(landed, location.href).pathname);
    // **The address changes only when it changed.** Saving the source of a page
    // lands on the same page, and pushing that would put a second copy of it in
    // the back history for every press.
    const moved = new URL(landed, location.href).pathname !== location.pathname;
    if (moved && mine === latest) history.pushState({ deep: kind }, "", landed);
    // **Everything held is now yesterday's.** Pages are kept for two minutes so
    // a click along the rail is instant; a save changes the rail and often the
    // page beside it, and serving one of those from the cache would show him
    // the thing he has just changed, unchanged.
    warm.clear();
    asked.clear();
    // Anything else holding a copy of the film's settings — the Share panel's
    // tabs — hears it too.
    document.dispatchEvent(new Event("saved"));
    // **A switch's save changes the rail, not the page he is reading.** The
    // switch already shows what he pressed; landing the whole page again
    // would throw him back to its top. So only the rail is brought up to
    // date — a page hidden For Me goes, a count changes — where he stands.
    if (quiet && !moved && said.ok) {
      if (mine === latest) railFrom(text);
      const line = form.querySelector("[data-vsaid]");
      if (line) line.textContent = "Saved.";
      confirmed(form);
      done();
      return;
    }
    place(text, landed, kind, false, mine);
    if (said.ok) confirmed(form);
    done();
  } catch {
    // **Hand it back to the browser rather than swallowing it.** A save that
    // silently did nothing is the one failure worse than a reload.
    done();
    if (window.portalWait) window.portalWait.away();
    form.submit();
  }
});

/**
 * **Settings changed somewhere that is not a page's own form** — the Share
 * panel's Visibility tab. Every page kept for a click may show the old
 * answer, and the rail beside him may too: both are brought up to date.
 */
document.addEventListener("settingschanged", async () => {
  warm.clear();
  asked.clear();
  if (!frontHalf() || (stage.app && stage.app.dataset.stowed === undefined)) return;
  try {
    const answer = await fetch(location.href, { credentials: "same-origin" });
    if (answer.ok) railFrom(await answer.text());
  } catch { /* the rail stays as it was; the next move brings it */ }
});

/** The rail out of a page that came back, put where the rail is now. */
function railFrom(said) {
  const came = new DOMParser().parseFromString(said, "text/html").querySelector(".fh2 > .rail");
  const here = frontHalf();
  const now = here && here.querySelector(":scope > .rail");
  if (!came || !now) return;
  // The rail scrolls on its own; keep it where it was.
  const scroller = now.querySelector(".sections");
  const top = scroller ? scroller.scrollTop : 0;
  const arrived = document.adoptNode(came);
  now.replaceWith(arrived);
  const again = arrived.querySelector(".sections");
  if (again) again.scrollTop = top;
  try { document.dispatchEvent(new Event("swapped")); } catch { /* a listener's own problem */ }
}

// **Fetched on the way to the click.** A pointer resting on a name for even a
// tenth of a second is enough to have the page in hand by the time it is
// pressed, which is the difference between this feeling like the mockup and
// feeling like a wait with an animation on top.
function warmUp(event) {
  const link = event.target.closest?.('a[data-deep]:not([data-deep="app"])');
  if (!link) return;
  const to = new URL(link.href, location.href);
  if (to.origin !== location.origin || asked.has(to.href)) return;
  asked.add(to.href);
  pageAt(to.href).catch(() => {});
}
document.addEventListener("mouseover", warmUp, { passive: true });
document.addEventListener("touchstart", warmUp, { passive: true });

// **And fetched before the pointer moves at all.** Hovering is not enough here.
// A record page is two to four kilobytes and takes about a second and a half to
// come back, which is long enough that an animation waiting on it is not an
// animation — it is a pause with a flourish at the end. There are only four of
// them and they never change while you are looking at them, so all four are
// fetched once the page has settled and every click after that is instant,
// which is what the mockup was: everything already in the room.
function fetchTheRest() {
  if (booted) return;
  const door = document.querySelector('a[data-deep="app"]');
  if (door) warmApp(new URL(door.href, location.href).href);
  // **A link that has not been drawn yet cannot be fetched ahead.** Landing
  // straight on the shot list — which is what his share link does — there is
  // nothing marked `data-deep` in the document at all for the first second and
  // a half, because the app's own bar is what carries the way home. This ran at
  // load, found nothing, and never looked again, so pressing the title paid a
  // whole fetch before anything moved. Look a few more times, then stop.
  if (!document.querySelector("a[data-deep]") && lookAgain > 0) {
    lookAgain -= 1;
    setTimeout(fetchTheRest, 700);
  }
  for (const link of document.querySelectorAll('a[data-deep]:not([data-deep="app"])')) {
    const to = new URL(link.href, location.href);
    if (to.origin !== location.origin) continue;
    // Warmth, not "have we ever asked" — otherwise a page fetched once goes
    // cold after `HOLD` and is never fetched again, and the click that finds it
    // stale is slow for no reason.
    if (fresh(warm.get(to.href))) continue;
    pageAt(to.href).catch(() => {});
  }
}
// **`requestIdleCallback` takes options, not a delay.** Passing it a number is
// a TypeError, and because this runs from the `swapped` event it threw on every
// page and on every swap — so nothing was ever fetched ahead and every click
// paid the full second and a half. A plain timer says what is meant.
let lookAgain = 5;
const settle = () => setTimeout(fetchTheRest, 150);
if (document.readyState === "complete") settle();
else addEventListener("load", settle);
// A page swapped in brings its own links, and its own way back.
document.addEventListener("swapped", settle);

// Back and forward are journeys too, and they are the ones most easily left
// broken by a script like this.
// **Leaving the app is a real page load, deliberately.** `film.js` binds itself
// to the document once — it reads `window.HUB` and finds its own box as it is
// imported — so a second visit inside the same document would swap in an empty
// screen. Going back out is rarer than going in, and it is a normal navigation
// today anyway, so it stays one.
addEventListener("popstate", () => {
  if (booted && stage.app && stage.front) {
    // **Any of the four screens is the app**, not only the shot list — the
    // address moves with the screen since `keepAddress`, so a step back can
    // land on `/locations` as easily as `/shotlist`.
    const wantsApp = /\/(shotlist|locations|boards|schedule)\/?$/.test(location.pathname);
    const showingApp = stage.app.dataset.stowed === undefined;
    if (wantsApp) {
      tellApp();
      return showingApp ? undefined : turn(stage.front, stage.app, "entering");
    }
    // **Out of the app is not one address any more.** Sections are reached from
    // inside the app now, so the film's page can be showing any of them — and
    // "the app is already away" was being read as "there is nothing to do",
    // which left Back changing the address and not the page. It is done when
    // the page up is the page asked for.
    if (!showingApp && stage.at === location.pathname) return;
    return waitOn(leaveApp(location.href, kindOf(location.pathname), false));
  }
  waitOn(go(location.href, kindOf(location.pathname), false));
});

// ---- the door into Shotlister ----------------------------------------------
//
// His ask: *"coudl you amke the shotlister open via animation rather than page
// laod?"* — and the reason it was a page load is worth writing down, because it
// is the same reason the rail used to be one and it is not really about
// animation at all.
//
// **Opening the app cost two and a half seconds.** A second and a third of that
// was the worker answering with a one-kilobyte shell; the rest was the app
// waking up — and the app wakes up by fetching **138 separate files** to replay
// the film from. They come to 195 kilobytes between them, so it is not the
// data, it is 138 round trips. An animation laid over that would have been a
// wait with a flourish on it, which is the thing I said I would not build.
//
// So this does two things, and the first matters more:
//
//  1. **Everything the app needs is fetched while he is reading the film's
//     page** — the shell, the engine, the script, and all 138 logs. They sit in
//     the browser's own cache, so the app's own fetches become cache hits.
//  2. **The app is woken up out of sight and only shown once it has drawn.**
//     Not swapped in and left to load: a transition onto a "Reading the film"
//     screen would look worse than the page load it replaced.
//
// The address stays real, and going *back out* of the app is a plain
// navigation on purpose — see `leaving` below.

let booted = false;
/**
 * The two halves once both exist: the film's page, and the app.
 *
 * **`at` is which address the film's half is currently showing**, and it is not
 * decoration. The app can be gone into from any section and come out of into
 * any other, so "the film's page" is no longer one page — knowing which one it
 * is holding is the difference between a swap and a fetch.
 */
const stage = { front: null, app: null, at: null };

/** The film's own id, which the app's shell hands over in `window.HUB`. */
function projectOf(said) {
  const found = /window\.HUB\s*=\s*(\{.*?\});/s.exec(said);
  if (!found) return null;
  try {
    return JSON.parse(found[1].replace(/\\u003c/g, "<"));
  } catch {
    return null;
  }
}

/** Fetch everything the app will ask for, so that by the time it asks, it has it. */
async function warmApp(href) {
  let said;
  try {
    said = await pageAt(href);
  } catch {
    return;
  }
  const hub = projectOf(said);
  if (!hub || !hub.project) return;
  // The engine and the script are stored by the browser and only revalidated,
  // so fetching them now means a 304 later rather than half a megabyte.
  fetch("/film.js").catch(() => {});
  fetch("/shotlister_web.wasm").catch(() => {});
  // **The change logs are deliberately not warmed.** They come back
  // `Cache-Control: no-store`, so the browser is told in as many words not to
  // keep them — fetching all 138 here would be 138 requests thrown away and
  // then made again the moment the app asks. Measured, not assumed.
  //
  // Which is the real reason opening the app costs what it does, and it is not
  // a thing this file can fix: 138 round trips for 195 kilobytes. One request
  // that returns them together is the fix, and it is written down.
}

/**
 * Wait until the app has drawn **the bar the title travels into**.
 *
 * **`.signin` is not the first child.** `film.js` paints everything inside a
 * `.app` wrapper, so the waiting screen sits one level down — looking only at
 * the first child said "drawn" immediately and swapped a *Reading the film*
 * straight onto the screen, which is precisely the thing this exists to avoid.
 *
 * **And "something has been drawn" was still the wrong question.** Measured
 * against his own film on the live host, 2026-09-03: `#film` gets its first
 * child at **80ms** and `.filmid` — the bar carrying `filmmark` and `filmname`
 * — at **1819ms**. So this returned almost at once, the swap ran, and at the
 * moment the browser looked for the new half of the title there was no element
 * wearing its name. A name with an old snapshot and no new one does not
 * travel: it fades. That is the whole of *"the title animations are just still
 * not there"*, and it is why it came right on the second press — by then the
 * app is stowed rather than woken, and `turn` never comes near this.
 *
 * It measured as working locally because the seeded film is one scene and draws
 * inside a frame. Only a real film is slow enough to lose the race, which is
 * the kind of fault a harness on a toy fixture will never show.
 *
 * So the wait is for the named elements themselves, not for evidence of life.
 * A sign-in still ends it — that is a finished answer, and nothing more is
 * coming — and running out of patience still proceeds, because a title that
 * fades is a great deal better than a door that never opens.
 */
async function drawn(holder, patience) {
  const until = Date.now() + patience;
  while (Date.now() < until) {
    // **`.signin` is the waiting screen, not a sign-in.** `film.js` draws
    // `class="signin booting"` while it reads the film, and reading `.signin`
    // as a finished answer ended the wait at 86ms — measured — so the swap ran
    // against a screen that had nothing but a loading bar on it and the title
    // had nowhere to land. That made going in *worse* than the fault it was
    // meant to fix. While `.booting` is up, nothing has arrived yet.
    if (holder.querySelector(".booting")) {
      await new Promise((again) => setTimeout(again, 30));
      continue;
    }
    // The two names the film's big title travels into. Both, because either one
    // alone leaves the other fading beside a moving partner.
    if (holder.querySelector(".filmid .filmicon") && holder.querySelector(".film")) return true;
    // Something else entirely — an error, a screen we do not know. It is not
    // waiting any more, so neither are we.
    if (holder.firstElementChild) return true;
    await new Promise((again) => setTimeout(again, 30));
  }
  return false;
}

/**
 * Put something away without losing it.
 *
 * `display:none` rather than a hidden corner: an element with no box is not
 * captured for a transition and cannot answer to a `view-transition-name`, so
 * the half that is put away can never be mistaken for the half on screen.
 */
function stow(what) {
  what.dataset.stowed = "";
  what.style.display = "none";
}

function unstow(what) {
  delete what.dataset.stowed;
  what.style.removeProperty("display");
  // The app measures itself as it draws; coming back from nothing it should be
  // told the window is there again.
  window.dispatchEvent(new Event("resize"));
}

/** Swap two halves of the document, with the going-in or coming-out motion. */
function turn(from, to, how) {
  const root = document.documentElement;
  const show = () => {
    stow(from);
    unstow(to);
  };
  // **`"#" + (to.id || "") || ".fh2"` was never the fallback it reads as**: the
  // `||` sees a "#" that is always truthy, so a half with no id — which is what
  // the film's page is — asked the browser for the selector `#` and threw.
  if (!document.startViewTransition) return plainly(show, to);
  root.classList.add(how);
  const moving = document.startViewTransition(show);
  moving.finished.finally(() => root.classList.remove(how)).catch(() => {});
}

/**
 * Back to the film's page from inside the app, without leaving the document.
 *
 * **The film's page may never have been here.** Opening the shot list straight
 * from a link, or reloading inside it, gives a document that has only ever held
 * the app — so there was nothing to go home to and the first Home was a page
 * load while every one after it was a swap. His words, 2026-09-02: *"the first
 * time click home doesn't load the animation."* It was not the animation; it
 * was that once, and only once, this was still a navigation.
 *
 * So if the film's page is not here, it is fetched and put in already stowed,
 * and the move is the same swap as every other time.
 *
 * **And it is any address out of the app, not only home.** The app's rail
 * carries the record's sections too; each of them is this same move with a
 * different page in hand. The half already standing is reused only when it is
 * holding the very page being asked for — the app can be entered from Visual
 * Bible and left towards People, and a swap back to whatever it happened to be
 * entered from would be the wrong page under the right address.
 */
async function leaveApp(href, kind = "home", push = true) {
  const at = new URL(href, location.href).pathname;
  const app = stage.app || document.getElementById("film");
  if (!app) {
    leaveFor(href);
    return;
  }
  if (stage.front && stage.at === at) {
    if (push) history.pushState({ deep: kind }, "", href);
    return turn(app, stage.front, "leaving");
  }
  let said;
  try {
    said = await pageAt(href);
  } catch {
    leaveFor(href);
    return;
  }
  const came = new DOMParser().parseFromString(said, "text/html");
  const next = came.querySelector(".fh2");
  if (!next) {
    leaveFor(href);
    return;
  }
  const arrived = document.adoptNode(next);
  // In put away, so it is not on screen and cannot answer to the title's name
  // until the swap itself shows it.
  stow(arrived);
  // **In the film's page's own place, not merely on the end.** Standing one is
  // replaced rather than joined: two of them in the document is the very fault
  // this is here to end. **And before the app, never after it**, when there is
  // no standing one: the page is the first half of the document everywhere
  // else, and a page put on the end was the one `place` could not find.
  if (stage.front && stage.front.isConnected) stage.front.replaceWith(arrived);
  else app.before(arrived);
  stage.front = arrived;
  stage.at = at;
  stage.app = app;
  booted = true;
  if (push) history.pushState({ deep: kind }, "", href);
  document.title = came.title;
  turn(app, arrived, "leaving");
  // `copy.js` dresses what it finds at load; what just arrived it has never
  // seen. Wrapped, because a listener that throws must not take the move down
  // with it — both halves have already changed places by here.
  try {
    document.dispatchEvent(new Event("swapped"));
  } catch {
    /* whatever was listening is its own problem */
  }
}

/**
 * True while the app is being woken for the first time.
 *
 * **The first press takes about a second**, and a second press during it used
 * to start the whole thing again: a second `#film` in the document, two
 * imports, two transitions racing, and `film.js` bound to whichever box it
 * found first. That is the door not opening — his words, *"Shotlister does not
 * consistently open"* — and the same collision is why the title sometimes
 * travelled and sometimes did not. An impatient second click is the normal
 * response to a slow one, so it has to be free.
 */
let waking = false;

/**
 * **Tell the app which screen the door was for.** The app keeps its own mode
 * and, the first time in, reads it off the shell the worker served for that
 * address. Put away and brought back, it came back as it was — on whatever
 * screen it was left on — so Locations opened the Shot List whenever the Shot
 * List was where he had been. His report, 2026-09-10: *"it just takes me to
 * Shotlist first instead of going right to Locations."* The address has
 * already been pushed by the time this fires, and `film.js` reads the screen
 * off it, the reverse of how `keepAddress` writes it.
 */
function tellApp() {
  try {
    document.dispatchEvent(new Event("entering"));
  } catch {
    /* whatever was listening is its own problem */
  }
}

async function enterApp(href, door) {
  // Been here already in this document: the app is still standing, put away
  // rather than torn down, so this is only a swap. `film.js` binds itself once
  // and could not be started twice anyway.
  if (stage.app && stage.front && stage.app.dataset.stowed !== undefined) {
    history.pushState({ deep: "app" }, "", href);
    tellApp();
    return turn(stage.front, stage.app, "entering");
  }
  if (waking) return;
  waking = true;
  const mine = ++latest;
  // The address the film's page is standing on, read before `pushState` moves
  // it — that is what the half kept behind the app is holding.
  const cameFrom = location.pathname;
  // **Something has to happen when it is pressed.** Holding the film's page up
  // until the shot list has drawn is right — a transition onto a *Reading the
  // film* screen would be worse than the page load it replaces — but it does
  // mean about a second in which a press looks like nothing. The door says it
  // heard.
  if (door) door.classList.add("waking");
  const done = () => door && door.classList.remove("waking");
  let said;
  try {
    said = await pageAt(href);
  } catch {
    waking = false;
    leaveFor(href);
    return;
  }
  if (mine !== latest) {
    waking = false;
    return done();
  }

  const came = new DOMParser().parseFromString(said, "text/html");
  const hub = came.querySelector("script:not([src])");
  const front = frontHalf();
  // Not the shell we expected — hand it back to the browser rather than guess.
  if (!hub || !front || !came.querySelector("#film")) {
    waking = false;
    leaveFor(href);
    return;
  }


  // **Woken up out of sight.** `visibility:hidden` rather than `display:none`,
  // because the app measures itself as it draws and a box with no size measures
  // wrong.
  const holder = document.createElement("div");
  holder.id = "film";
  holder.setAttribute("style", "position:fixed;inset:0;visibility:hidden;pointer-events:none");
  // **While it is waking it must not answer to the title's name.** The app's
  // bar carries the same two `view-transition-name`s as the film's big title,
  // which is what lets one travel into the other — but a hidden copy sitting in
  // the page at the same time means two elements wearing one name, and the
  // browser will not move a name it has seen twice. It fades out instead, which
  // is exactly what it did. The names come back in `show`, a moment before the
  // browser looks.
  holder.dataset.waking = "";
  document.body.appendChild(holder);

  const settings = document.createElement("script");
  settings.textContent = hub.textContent;
  document.body.appendChild(settings);

  history.pushState({ deep: "app" }, "", href);
  booted = true;

  try {
    await import("/film.js");
  } catch {
    waking = false;
    leaveFor(href);
    return;
  }
  // **Not here.** Importing the script is the quick half; the wait he can feel
  // is the film being read, below. Clearing the door's pressed look at this
  // point left most of the pause looking like nothing had happened.
  await drawn(holder, 4000);
  done();
  waking = false;

  // **The film's page is kept, not thrown away.** Going home used to be a page
  // load because there was nothing left to go home to. Both halves now live in
  // the document and the move is a swap in either direction, which is the only
  // way home can animate at all.
  stage.front = front;
  stage.at = cameFrom;
  stage.app = holder;
  const show = () => {
    stow(front);
    holder.removeAttribute("style");
    delete holder.dataset.waking;
  };
  // **The class has to outlive the swap.** It was being taken off inside the
  // callback, and the browser only reads the pseudo-element styles *after* the
  // callback returns — so by the time it looked, `html.entering` was gone and
  // the page's own fade fell back to the `animation:none` this file sets on
  // root. The names still travelled, which is why it measured as working and
  // still read as a hard cut.
  if (!document.startViewTransition) return plainly(show, "#film");
  const root = document.documentElement;
  root.classList.add("entering");
  const moving = document.startViewTransition(show);
  moving.finished.finally(() => root.classList.remove("entering")).catch(() => {});
}

/**
 * The same move, for a browser with no view transitions.
 *
 * **Not everything has them, and a page that only animates on Chrome is a page
 * that does not animate.** This asks nothing of the browser but a keyframe: the
 * new thing is swapped in and comes up under its own steam. It is not the morph
 * — nothing can travel without the API — but it is motion, and motion is what
 * says you went somewhere.
 */
function plainly(swap, which) {
  swap();
  const box = typeof which === "string" ? document.querySelector(which) : which;
  if (!box) return;
  box.classList.add("camein");
  setTimeout(() => box.classList.remove("camein"), 500);
}
