/**
 * **Dragging the rail into the order he wants.** Ref 870.
 *
 * His answer, 2026-09-08, to the question of whether the sidebar should be his
 * to arrange: *"I like your recommendation here as well. Dragging is good."*
 * Until this existed his own pages sat on the end of the list in the order they
 * happened to arrive, and a crew member opening the film read his thinking
 * sorted by accident.
 *
 * ## Why this is delegated from the document, and not wired to the rows
 *
 * There are two rails and only one of them stands still. The record's pages are
 * drawn by the worker and never change under you; **the program's rail is
 * redrawn by `paint()` every time anything about the film changes** — a scene
 * added, a log arriving from the relay, a mode switched. Anything wired to a
 * row would be wired to a row that no longer exists a second later, and
 * re-attaching after every paint means `public/film.js` has to remember to call
 * something. That file has crashed the whole app three times from exactly this
 * class of coupling (see the notes above `railGroups` there).
 *
 * So nothing is attached to a row, ever. One listener on the document finds the
 * row under the pointer at the moment of the press, and a repaint in between
 * costs nothing because there was nothing to lose.
 *
 * ## Why a press is not a drag until it has travelled
 *
 * Every row here is a link or a button that somebody means to press far more
 * often than they mean to move it. So a press is a press until the pointer has
 * gone `SLOP` pixels, and only then does it become a drag — and the click that
 * a real drag ends with is swallowed, or letting go over Locations would open
 * Locations.
 *
 * On a touch screen the rail is a sheet that scrolls, and a finger going down
 * the list means *scroll* almost every time. So there a drag has to be asked
 * for: hold still for `HOLD` milliseconds first. Moving before that is a
 * scroll and this gets out of the way.
 */

/** How far a press travels before it is a drag rather than a press. */
const SLOP = 6;

/** How long a finger holds still before it is asking to move a row. */
const HOLD = 400;

/** The rail's groups, in the order they are drawn. Each is `.group[data-head]`. */
function groupsIn(rail) {
  return [...rail.querySelectorAll(".sections > .group[data-head]")];
}

/** A group's rows, by the key the order is stored under. */
function keysIn(group) {
  return [...group.querySelectorAll(":scope > .to[data-key]")].map((el) => el.dataset.key);
}

/** The rail as it stands — headings and their rows — read straight off the DOM. */
function shapeOf(rail) {
  return groupsIn(rail).map((g) => ({ name: g.dataset.head || "", rows: keysIn(g) }));
}

/**
 * **A browser drags a link before this file gets a look in.**
 *
 * Every row on the rail is an `<a href>`, and pressing one and moving is the
 * browser's own gesture for dragging a link somewhere — it takes the pointer,
 * paints a ghost, and the pointermove events this file is waiting for never
 * arrive. **No headless check can see it**: synthetic mouse events through
 * Chrome's debugging port do not start a native drag, so the harness reported a
 * working feature he could not use.
 *
 * `draggable="false"` on the rows says it in the markup; this says it again for
 * anything drawn before that landed, and for the text inside a row.
 */
document.addEventListener("dragstart", (event) => {
  if (event.target.closest && event.target.closest(".rail[data-arrange] .sections")) event.preventDefault();
});

/**
 * **Once a row has been held, the finger is the drag's and not the page's.**
 * A browser decides a touch is a scroll at its first move unless that move is
 * cancelled, and cancelling it is the only way the pointer events keep coming.
 * `holding` is on the body from the moment the hold is up until the finger
 * lifts; before it, a moving finger is a scroll and nothing here interferes.
 */
document.addEventListener("touchmove", (event) => {
  if (document.body.classList.contains("holding") && event.cancelable) event.preventDefault();
}, { passive: false });

document.addEventListener("pointerdown", (event) => {
  if (event.pointerType === "mouse" && event.button !== 0) return;
  const row = event.target.closest(".to[data-key]");
  if (!row) return;
  // **A row's own ⋯ or a name being renamed is not a drag** (move 1).
  if (event.target.closest(".rowmore, input")) return;
  // **The mark is on the rail, not worked out here.** Only an editor's rail
  // carries it, so a viewer's rail is not draggable and this asks nothing about
  // roles — the server has already decided.
  const rail = row.closest(".rail[data-arrange]");
  if (!rail) return;
  const list = row.parentElement;
  if (!list) return;

  const startY = event.clientY;
  const startX = event.clientX;
  let armed = event.pointerType === "mouse";
  let dragging = false;
  let ghost = null;

  // **The well travels with its row.** In the program the open section's own
  // list — the scenes, the places — is a sibling drawn straight after the row
  // it belongs to. Left behind, it would end up under whichever row happened to
  // take that place.
  const well = row.nextElementSibling && row.nextElementSibling.classList.contains("well")
    ? row.nextElementSibling
    : null;

  // **Held long enough on a touch screen: the row lifts** (phone move 2). It
  // is told by a class on the body so the page can stop the browser taking the
  // finger for a scroll (see the touchmove listener below), and by a small
  // buzz where the device has one.
  const hold = armed ? 0 : setTimeout(() => {
    armed = true;
    document.body.classList.add("holding");
    row.classList.add("lifted");
    try { if (navigator.vibrate) navigator.vibrate(12); } catch { /* no buzz */ }
  }, HOLD);
  let slide = 0;

  const groups = () => groupsIn(rail);

  /**
   * **Which heading, then where under it** — in that order, and the order is
   * the whole fix.
   *
   * His report, 2026-09-08: *"I can't drag anything on the left sidebar
   * underneath the headings."* It asked the other question first — *which row
   * do I sit above* — across every row in the rail at once. The last row of a
   * group has no row after it inside that group, so the next row found was the
   * **first row of the next group**, and the drop landed there. Under any
   * heading followed by another heading, the bottom slot did not exist. Filing
   * something at the end of *Look* was impossible, which is most of what
   * filing is.
   *
   * **A group's band starts at its heading**, not at its first row: the gap a
   * heading occupies belongs to the group it names, or the pixels directly
   * under the word *Look* would file into whatever is above it.
   */
  const put = (y) => {
    const bands = groups().map((g) => {
      const head = g.previousElementSibling;
      const box = g.getBoundingClientRect();
      const top = head && head.classList.contains("grouphead")
        ? head.getBoundingClientRect().top
        : box.top;
      return { el: g, top, bottom: box.bottom };
    });
    if (!bands.length) return;
    const into = bands.find((b) => y >= b.top && y <= b.bottom)
      || (y < bands[0].top ? bands[0] : bands[bands.length - 1]);

    const others = [...into.el.querySelectorAll(":scope > .to[data-key]")].filter((el) => el !== row);
    const before = others.find((el) => {
      const box = el.getBoundingClientRect();
      return y < box.top + box.height / 2;
    });
    into.el.insertBefore(row, before || null);
    if (well) row.after(well);
  };

  const move = (e) => {
    const gone = Math.abs(e.clientY - startY) + Math.abs(e.clientX - startX);
    if (!dragging) {
      if (!armed) {
        // Moved before the hold was up: that is a scroll, not a drag.
        if (gone > SLOP) stop(false);
        return;
      }
      if (gone < SLOP) return;
      dragging = true;
      // **The row becomes the drop line, and a copy of it follows the pointer**
      // (move 1): a thin line in the film's colour shows where it will land.
      ghost = document.createElement("div");
      ghost.className = "dragghost";
      ghost.textContent = (row.querySelector(".nm") || row).textContent.trim();
      (row.closest(".fh2") || document.body).append(ghost);
      row.classList.add("moving");
      document.body.classList.add("arranging");
      try { row.setPointerCapture(e.pointerId); } catch { /* a mouse that has already left */ }
    }
    e.preventDefault();
    if (ghost) { ghost.style.left = `${e.clientX + 12}px`; ghost.style.top = `${e.clientY - 14}px`; }
    // **On the Library page the pane beside the rail is a place to drop**: a row
    // let go over it comes off the sidebar (`lib.js` hears `rail-takeoff`).
    const pane = document.querySelector(".fh-lpane");
    leaving = Boolean(pane) && e.clientX > rail.getBoundingClientRect().right;
    if (pane) pane.classList.toggle("dropout", leaving);
    if (!leaving) put(e.clientY);
    // **A finger near the top or foot of a list that scrolls keeps scrolling
    // it**, or a row could never be carried further than the screen shows.
    const box = (row.closest(".sections") || row.parentElement).getBoundingClientRect();
    slide = e.clientY < box.top + 44 ? -10 : e.clientY > box.bottom - 44 ? 10 : 0;
    lastY = e.clientY;
  };
  let lastY = 0;
  let leaving = false;
  const scroller = setInterval(() => {
    if (!dragging || !slide) return;
    const list = row.closest(".sections");
    if (!list) return;
    list.scrollTop += slide;
    put(lastY);
  }, 30);

  const up = () => stop(dragging);

  function stop(moved) {
    clearTimeout(hold);
    clearInterval(scroller);
    document.body.classList.remove("holding");
    row.classList.remove("lifted");
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
    window.removeEventListener("pointercancel", up);
    if (ghost) { ghost.remove(); ghost = null; }
    if (!moved) return;
    row.classList.remove("moving");
    document.body.classList.remove("arranging");
    swallowClick();
    const pane = document.querySelector(".fh-lpane");
    if (pane) pane.classList.remove("dropout");
    if (leaving) { document.dispatchEvent(new CustomEvent("rail-takeoff", { detail: { key: row.dataset.key } })); return; }
    save(rail);
  }

  window.addEventListener("pointermove", move, { passive: false });
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);
});

/**
 * **Swallow the click this drag is about to become.** Without it, letting go
 * over Locations opens Locations, which is the one thing a person rearranging
 * a list is certain not to want.
 *
 * **And only that click.** A drag that ends off the row it started on may
 * produce no click at all, and a listener left waiting for one would eat the
 * next real press instead — the row he went to open, a moment later, did
 * nothing. So it is armed for as long as a click takes to arrive and no longer.
 */
function swallowClick() {
  const eat = (e) => {
    e.preventDefault();
    e.stopPropagation();
    window.removeEventListener("click", eat, { capture: true });
  };
  window.addEventListener("click", eat, { capture: true });
  setTimeout(() => window.removeEventListener("click", eat, { capture: true }), 350);
}

/**
 * Tell the film what order it is in now.
 *
 * **Nothing is redrawn afterwards.** The rail already shows the answer — it is
 * the thing that was dragged — so a reply that rebuilt it would be a flicker
 * saying nothing. A failure is worth saying, though: the alternative is an
 * order that looks saved until the next page load throws it away.
 *
 * **Two others have to be told, or the order snaps back.** His ask,
 * 2026-09-10, that saving and updating be *"faster and more fluid"*, and both
 * of these were why it was not:
 *
 * - **The app keeps its own copy of the order** — `HUB.rail.groups`, handed
 *   over when the page was served — and `paint()` draws the rail from it on
 *   every change to the film. One paint after a drag and the row was back
 *   where it started, with the save sitting safely on the server. The copy is
 *   brought up to date here, before the save has even gone.
 * - **`deep.js` keeps every page it has fetched for two minutes**, and fetches
 *   the record's pages ahead of the click. Every one of those carries the rail
 *   as it was before the drag. `arranging` says a change is in the air, with
 *   the save to wait on; `arranged` says it has landed. What `deep.js` does
 *   with the two is written there.
 */
/**
 * **Anything that has edited the rail in place asks for it to be saved here**
 * (`public/side.js`: a heading renamed, added or removed). One saver, so the
 * program's copy of the groups and the `arranged` event stay true.
 */
document.addEventListener("arrange-save", (event) => {
  const rail = (event.detail && event.detail.rail) || document.querySelector(".rail[data-arrange]");
  if (rail) save(rail);
});

/**
 * **The order, after a drag that only saw the rows on screen** — `applyOrder`
 * in `src/front.js`, the same rule: the pages the sidebar showed take the new
 * order, and a page that is off the sidebar keeps its place beside the
 * neighbour it had. Change one and change the other in the same breath.
 */
function orderAfter(before, shown) {
  const seen = new Set();
  const keep = shown.filter((at) => !seen.has(at) && seen.add(at));
  const after = new Map();
  let prior = "";
  for (const at of before) {
    if (seen.has(at)) { prior = at; continue; }
    if (!after.has(prior)) after.set(prior, []);
    after.get(prior).push(at);
  }
  const out = [...(after.get("") || [])];
  for (const at of keep) out.push(at, ...(after.get(at) || []));
  const placed = new Set(out);
  for (const at of before) if (!placed.has(at)) { out.push(at); placed.add(at); }
  return out;
}

/**
 * **The program's own copy, brought up to date** (`HUB.rail`, which `paint()`
 * draws the rail from). Since 2026-10-11 the headings are the categories, so
 * the copy is three things: `order` (the pages, one list), `filed` (which
 * category each page is in: the heading it now stands under) and `shelves`
 * (the categories, put in the order the headings are in, each in a slot it
 * held, as `arrangeRail` does on the server).
 */
function keepCopy(rail, groups) {
  const hub = window.HUB && window.HUB.rail;
  if (!hub) return;
  const filed = { ...(hub.filed || {}) };
  const present = [];
  for (const group of groupsIn(rail)) {
    const id = group.dataset.shelf;
    if (!id) continue;
    if (!present.includes(id)) present.push(id);
    for (const at of keysIn(group)) filed[at] = id;
  }
  window.HUB.rail.filed = filed;
  if (Array.isArray(hub.shelves)) {
    const all = hub.shelves.map((one) => one.id);
    const slots = all.map((id, i) => (present.includes(id) ? i : -1)).filter((i) => i >= 0);
    const next = [...hub.shelves];
    slots.forEach((slot, n) => { next[slot] = hub.shelves.find((one) => one.id === present[n]); });
    window.HUB.rail.shelves = next;
  }
  window.HUB.rail.order = orderAfter(hub.order || [], groups.flatMap((g) => g.rows));
}

async function save(rail) {
  const where = rail.dataset.arrange;
  const groups = shapeOf(rail);
  if (!where || !groups.length) return;
  keepCopy(rail, groups);
  // The Headings page, if that is where this is, counts its rows off the rail.
  const on = headsOn();
  if (on) recount(on.rail, on.list, on.form);
  const list = document.querySelector(".fh-headform");
  const sending = (async () => {
    try {
      // **One field per heading, `name` then its rows.** The shape the sidebar
      // is actually in, read straight off the DOM — a shape reassembled on the
      // way is a shape that can be reassembled wrong.
      const body = new URLSearchParams();
      for (const group of groups) body.append("group", `${group.name}\n${group.rows.map((k) => k.replace(/,/g, "%2C")).join(",")}`);
      const said = await fetch(where, {
        method: "POST",
        credentials: "same-origin",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body,
      });
      if (!said.ok) throw new Error(String(said.status));
      rail.classList.remove("unsaved");
      if (list) list.classList.remove("unsaved");
    } catch {
      // **Says which way it failed.** "Something went wrong" cost an hour once;
      // this at least says the order on screen is not the order on the film.
      rail.classList.add("unsaved");
      if (list) list.classList.add("unsaved");
    }
  })();
  document.dispatchEvent(new CustomEvent("arranging", { detail: sending }));
  await sending;
  document.dispatchEvent(new CustomEvent("arranged", { detail: groups }));
}

// ---- the Headings page: the same order, from the other side ----------------
//
// **The rail files rows under headings; this list puts the headings themselves
// in order, names them and makes them.** His ask, 2026-09-10: *"I need to be
// able to reorder my headings. The interface for setting up the headings
// should be more like a drag-and-drop list than anything else."*
//
// A drag is made **to the rail first** and then saved off it, exactly as a
// drag on the rail is: the rail beside the list moves as the list does, and
// the save goes in the background. Names, new categories and removals go as
// the page's own form to `/groups` (2026-10-11: the headings are the
// categories, and the server keeps them by id).
//
// Delegated from the document like everything above, because the page arrives
// by `deep.js` swapping it in, and a listener wired to a row would be wired to
// nothing a click later.

function headsOn() {
  const list = document.querySelector(".fh-heads[data-headings]");
  const rail = document.querySelector(".rail[data-arrange]");
  return list && rail ? { list, rail, form: list.closest("form") } : null;
}

function headRows(list) {
  return [...list.querySelectorAll(":scope > .fh-headrow")];
}

function groupNamed(rail, name) {
  return groupsIn(rail).find((g) => (g.dataset.head || "") === name) || null;
}

function headOf(group) {
  const before = group.previousElementSibling;
  return before && before.classList.contains("grouphead") ? before : null;
}

/** The rail's headings, put in the order the list is in. The unfiled pile stays last. */
function railFollows(rail, list) {
  const sections = rail.querySelector(".sections");
  for (const row of headRows(list)) {
    const group = groupNamed(rail, row.dataset.head);
    if (!group) continue;
    const head = headOf(group);
    if (head) sections.appendChild(head);
    sections.appendChild(group);
  }
  for (const group of groupsIn(rail).filter((g) => !g.dataset.head)) sections.appendChild(group);
}

/** Each row's count, read off the rail — the rail is where the rows are. */
function recount(rail, list, form) {
  for (const row of headRows(list)) {
    const group = groupNamed(rail, row.dataset.head);
    const n = group ? keysIn(group).length : 0;
    row.querySelector(".fh-headcount").textContent = n ? `${n} ${n === 1 ? "row" : "rows"}` : "";
  }
  const note = form && form.querySelector(".fh-headnote");
  if (note) note.hidden = !headRows(list).length;
}

/** Every change ends here: counts, then the save. */
function commit({ rail, list, form }) {
  recount(rail, list, form);
  save(rail);
}

/**
 * **A name changed, a category added or removed: the Categories page's own
 * form** (2026-10-11). The headings are the categories now, and only the
 * server knows where a removed category's pages are filed, so these go as the
 * plain form (which sends every row, by its `was` id, in order) and `deep.js`
 * lands the answer in place. Leaving a name field sends it; dragging a row
 * into order still saves in the background, below.
 */
document.addEventListener("change", (event) => {
  const field = event.target;
  if (!(field instanceof HTMLInputElement) || !field.matches(".fh-headrow input[name=name]")) return;
  const form = field.closest("form");
  if (form && headsOn() && form.requestSubmit) form.requestSubmit();
});

/** Dragging a heading into place, the same gesture as a row on the rail. */
/**
 * **Once a row has been held, the finger is the drag's and not the page's.**
 * A browser decides a touch is a scroll at its first move unless that move is
 * cancelled, and cancelling it is the only way the pointer events keep coming.
 * `holding` is on the body from the moment the hold is up until the finger
 * lifts; before it, a moving finger is a scroll and nothing here interferes.
 */
document.addEventListener("touchmove", (event) => {
  if (document.body.classList.contains("holding") && event.cancelable) event.preventDefault();
}, { passive: false });

document.addEventListener("pointerdown", (event) => {
  if (event.pointerType === "mouse" && event.button !== 0) return;
  const row = event.target.closest(".fh-headrow");
  if (!row) return;
  // A press in the field is typing; a press on the cross is the cross.
  if (event.target.closest("input, button")) return;
  const on = headsOn();
  if (!on || row.parentElement !== on.list) return;
  const { list } = on;

  const startY = event.clientY;
  const startX = event.clientX;
  // **The grip is a handle for any finger**; the rest of the row asks a touch
  // to hold still first, as the rail does, because a finger going down a list
  // usually means scroll.
  let armed = event.pointerType === "mouse" || Boolean(event.target.closest(".fh-grip"));
  let dragging = false;
  // **Held long enough on a touch screen: the row lifts** (phone move 2). It
  // is told by a class on the body so the page can stop the browser taking the
  // finger for a scroll (see the touchmove listener below), and by a small
  // buzz where the device has one.
  const hold = armed ? 0 : setTimeout(() => {
    armed = true;
    document.body.classList.add("holding");
    row.classList.add("lifted");
    try { if (navigator.vibrate) navigator.vibrate(12); } catch { /* no buzz */ }
  }, HOLD);
  let slide = 0;

  const put = (y) => {
    const others = headRows(list).filter((el) => el !== row);
    const before = others.find((el) => {
      const box = el.getBoundingClientRect();
      return y < box.top + box.height / 2;
    });
    list.insertBefore(row, before || null);
  };

  const move = (e) => {
    const gone = Math.abs(e.clientY - startY) + Math.abs(e.clientX - startX);
    if (!dragging) {
      if (!armed) {
        if (gone > SLOP) stop(false);
        return;
      }
      if (gone < SLOP) return;
      dragging = true;
      row.classList.add("moving");
      document.body.classList.add("arranging");
      try { row.setPointerCapture(e.pointerId); } catch { /* a mouse that has already left */ }
    }
    e.preventDefault();
    put(e.clientY);
  };

  const up = () => stop(dragging);

  function stop(moved) {
    clearTimeout(hold);
    clearInterval(scroller);
    document.body.classList.remove("holding");
    row.classList.remove("lifted");
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
    window.removeEventListener("pointercancel", up);
    if (!moved) return;
    row.classList.remove("moving");
    document.body.classList.remove("arranging");
    swallowClick();
    railFollows(on.rail, list);
    commit(on);
  }

  window.addEventListener("pointermove", move, { passive: false });
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);
});

/**
 * **A heading drags too, and takes its rows with it** (2026-10-11). The
 * headings are the categories, so dragging one puts that category in its new
 * place: the save sends the rail as it stands, and the server files the
 * categories in the order of the headings (`arrangeRail`). The unfiled pile
 * stays last. Pressing a heading's own buttons, or its name being renamed, is
 * not a drag; on a touch screen it is a hold first, as a row is.
 */
document.addEventListener("pointerdown", (event) => {
  if (event.pointerType === "mouse" && event.button !== 0) return;
  const head = event.target.closest && event.target.closest(".rail[data-arrange] .sections > .grouphead");
  if (!head || event.target.closest("button, input, [role=button]")) return;
  const rail = head.closest(".rail[data-arrange]");
  const group = head.nextElementSibling;
  if (!rail || !group || !group.classList.contains("group")) return;
  const sections = head.parentElement;
  const startY = event.clientY;
  const startX = event.clientX;
  let armed = event.pointerType === "mouse";
  let dragging = false;
  const hold = armed ? 0 : setTimeout(() => {
    armed = true;
    document.body.classList.add("holding");
    head.classList.add("lifted");
    try { if (navigator.vibrate) navigator.vibrate(12); } catch { /* no buzz */ }
  }, HOLD);

  const put = (y) => {
    const heads = [...sections.querySelectorAll(":scope > .grouphead")].filter((h) => h !== head);
    const before = heads.find((h) => y < h.getBoundingClientRect().top + h.getBoundingClientRect().height / 2);
    const tail = groupsIn(rail).find((g) => !g.dataset.head) || sections.querySelector(":scope > .newhead");
    sections.insertBefore(head, before || tail || null);
    head.after(group);
  };
  const move = (e) => {
    const gone = Math.abs(e.clientY - startY) + Math.abs(e.clientX - startX);
    if (!dragging) {
      if (!armed) { if (gone > SLOP) stop(false); return; }
      if (gone < SLOP) return;
      dragging = true;
      head.classList.add("fh-hmoving");
      group.classList.add("fh-hmoving");
      document.body.classList.add("arranging");
      try { head.setPointerCapture(e.pointerId); } catch { /* a mouse that has already left */ }
    }
    e.preventDefault();
    put(e.clientY);
  };
  const up = () => stop(dragging);
  function stop(moved) {
    clearTimeout(hold);
    document.body.classList.remove("holding");
    head.classList.remove("lifted");
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
    window.removeEventListener("pointercancel", up);
    if (!moved) return;
    head.classList.remove("fh-hmoving");
    group.classList.remove("fh-hmoving");
    document.body.classList.remove("arranging");
    swallowClick();
    save(rail);
  }
  window.addEventListener("pointermove", move, { passive: false });
  window.addEventListener("pointerup", up);
  window.addEventListener("pointercancel", up);
});
