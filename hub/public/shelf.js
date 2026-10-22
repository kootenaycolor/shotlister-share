/**
 * The shelf's own controls — search, Status, sort, Grid or List.
 *
 * His walkthrough, 2026-09-23: the shelf will get big, so it needs finding as
 * well as looking. **Everything is already on the page**: each card carries
 * its name, Notion's Status, its first shoot date and the words a search
 * matches (`shelfBody` in `src/pages.js`), so nothing here asks the server
 * anything. With no script the controls stay hidden and the grid stands.
 *
 * **Remembered per browser**, the way the shot list's Days switch is: the
 * phone and the desk can each keep their own. Storage may be refused (a
 * private window), and then the shelf simply starts from Active, Name, Grid.
 *
 * **His own home page has two more things** (his ask, 2026-10-05), drawn only
 * where the server says `data-owner` on the tools — a viewer's shelf is
 * exactly what it was. The stages (his Status words) become headings that fold,
 * the count staying; Sort becomes a menu — Next Date, Name, Recently Changed,
 * Status — with No Groups to flatten the list. What he chose is kept in this
 * browser alone, under the same key, in three fields no other sign-in reads
 * (`order`, `flat`, `folded`). Nothing is sent anywhere.
 *
 * **It starts on Active** — his answer, 2026-09-23 (Ref 1158): the films he is
 * working on, not every film he has ever made. A shelf with no Active film
 * starts on All rather than on nothing. `shelf.v2` because v1 kept All as the
 * starting point, and a browser that stored it would never meet the new one.
 */
const tools = document.querySelector("[data-shelftools]");
const shelf = document.querySelector("[data-shelf]");

if (tools && shelf) {
  const KEY = "shelf.v2";
  const cards = [...shelf.querySelectorAll(".pcard")];
  const find = tools.querySelector("[data-shelffind]");
  const sort = tools.querySelector("[data-shelfsort]");
  const sortBtn = tools.querySelector("[data-ownersort]");
  const none = document.querySelector("[data-shelfnone]");
  const count = document.querySelector("[data-shelfcount]");
  const ORDER = ["Development", "Active", "Post", "Complete", "Archived"];

  const owner = tools.hasAttribute("data-owner");
  const OWNER_SORTS = [["next", "Next Date"], ["name", "Name"], ["recent", "Recently Changed"], ["status", "Status"]];
  let state = { status: "Active", sort: "name", view: "grid", order: "next", flat: false, folded: {} };
  try {
    const kept = JSON.parse(localStorage.getItem(KEY) || "{}");
    state = { ...state, ...kept };
  } catch { /* a refused store is a fresh shelf */ }
  // What a store from another day, or another hand, may have left in the three new fields.
  if (!OWNER_SORTS.some(([k]) => k === state.order)) state.order = "next";
  state.flat = state.flat === true;
  state.folded = (state.folded && typeof state.folded === "object")
    ? Object.fromEntries(Object.keys(state.folded).filter((k) => state.folded[k] === true).map((k) => [k, true]))
    : {};
  // A status nobody carries any more is no filter at all.
  if (state.status && !tools.querySelector(`.fh-chip[data-status="${CSS.escape(state.status)}"]`)) state.status = "";

  const keep = () => {
    try { localStorage.setItem(KEY, JSON.stringify(state)); } catch { /* nothing to keep it in */ }
  };

  const rank = (s) => { const i = ORDER.indexOf(s); return i === -1 ? (s ? ORDER.length : ORDER.length + 1) : i; };
  const byName = (a, b) => a.dataset.title.localeCompare(b.dataset.title);
  const ways = {
    name: byName,
    status: (a, b) => rank(a.dataset.status) - rank(b.dataset.status) || byName(a, b),
    // **Newest shoot first** (his answer, Ref 1158); a film with no date waits at the end.
    shoot: (a, b) => (b.dataset.shoot || "").localeCompare(a.dataset.shoot || "") || byName(a, b),
  };

  // ---- the owner's own order: next date, name, recently changed, status ----
  // Coming up first, soonest at the top; then the films already shot, latest
  // first; then the ones with no date. Never edited sorts last.
  const ownerWays = {
    next: (a, b) => {
      const key = (c) => c.dataset.next ? [0, c.dataset.next] : c.dataset.last ? [1, c.dataset.last] : [2, ""];
      const [x, y] = [key(a), key(b)];
      if (x[0] !== y[0]) return x[0] - y[0];
      // ahead: earliest first; behind: latest first
      return (x[0] === 1 ? y[1].localeCompare(x[1]) : x[1].localeCompare(y[1])) || byName(a, b);
    },
    name: byName,
    recent: (a, b) => (b.dataset.edited || "").localeCompare(a.dataset.edited || "") || byName(a, b),
    status: (a, b) => rank(a.dataset.status) - rank(b.dataset.status) || byName(a, b),
  };

  /** One stage's heading: a button that folds its films, the count staying. */
  function groupHead(name, n, folded, id) {
    const head = document.createElement("button");
    head.type = "button";
    head.className = "fh-grphead";
    head.dataset.group = name;
    head.setAttribute("aria-expanded", folded ? "false" : "true");
    head.setAttribute("aria-controls", id);
    head.innerHTML = `<span class="chev" aria-hidden="true"></span><span class="gname"></span><span class="gn"></span>`;
    head.querySelector(".gname").textContent = name;
    head.querySelector(".gn").textContent = String(n);
    return head;
  }

  function drawOwner(ok, searching) {
    const sorted = [...cards].sort(ownerWays[state.order] || byName);
    const shown = sorted.filter(ok);
    for (const card of cards) card.hidden = !ok(card);
    const store = document.createElement("div");
    store.hidden = true;
    store.append(...sorted.filter((c) => !ok(c)));
    shelf.replaceChildren();
    shelf.classList.toggle("grouped", !state.flat);
    shelf.classList.toggle("grid3", state.flat);
    shelf.classList.toggle("aslist", state.flat && state.view === "list");
    if (state.flat) {
      shelf.append(...shown);
    } else {
      // The stages in the order he works them — Active first — which is the
      // console's own list; the chips above keep the order they always had.
      const WORKED = ["Active", "Development", "Post", "Complete", "Archived"];
      const place = (n) => { const i = WORKED.indexOf(n); return i === -1 ? (n === "No Status" ? WORKED.length + 1 : WORKED.length) : i; };
      const names = [...new Set(shown.map((c) => c.dataset.status || "No Status"))]
        .sort((a, b) => place(a) - place(b) || a.localeCompare(b));
      names.forEach((name, i) => {
        const mine = shown.filter((c) => (c.dataset.status || "No Status") === name);
        // A search shows every film it finds, folded or not; the fold is only hidden.
        const folded = !searching && state.folded[name] === true;
        const group = document.createElement("section");
        group.className = "fh-grp";
        const body = document.createElement("div");
        body.id = `shelfgrp-${i}`;
        body.className = `grid3${state.view === "list" ? " aslist" : ""}`;
        body.hidden = folded;
        body.append(...mine);
        group.append(groupHead(name, mine.length, folded, body.id), body);
        shelf.append(group);
      });
    }
    shelf.append(store);
    return shown.length;
  }

  function draw() {
    const said = (find.value || "").trim().toLowerCase();
    const words = said.split(/\s+/).filter(Boolean);
    let shown = 0;
    const fits = (card) => (!state.status || card.dataset.status === state.status)
      && words.every((w) => card.dataset.find.includes(w));
    if (owner) {
      shown = drawOwner(fits, words.length > 0);
    } else {
      for (const card of [...cards].sort(ways[state.sort] || byName)) {
        shelf.appendChild(card);
        const ok = fits(card);
        card.hidden = !ok;
        if (ok) shown += 1;
      }
      shelf.classList.toggle("aslist", state.view === "list");
    }
    for (const chip of tools.querySelectorAll(".fh-chip")) chip.classList.toggle("on", chip.dataset.status === state.status);
    for (const b of tools.querySelectorAll("[data-shelfview]")) b.classList.toggle("on", b.dataset.shelfview === state.view);
    if (sort) sort.value = state.sort;
    if (sortBtn) sortBtn.textContent = (OWNER_SORTS.find(([k]) => k === state.order) || OWNER_SORTS[0])[1];
    if (none) none.hidden = shown > 0;
    // **A count is a count**: all of them, or how many of how many.
    if (count) {
      const all = cards.length;
      count.textContent = shown === all ? `${all} ${all === 1 ? "project" : "projects"}` : `${shown} of ${all} projects`;
    }
  }

  tools.addEventListener("click", (event) => {
    const chip = event.target.closest(".fh-chip");
    if (chip) { state.status = chip.dataset.status; keep(); draw(); return; }
    const view = event.target.closest("[data-shelfview]");
    if (view) { state.view = view.dataset.shelfview; keep(); draw(); }
  });
  if (sort) sort.addEventListener("change", () => { state.sort = sort.value; keep(); draw(); });

  // ---- the owner's stages fold; the sort is a menu -------------------------
  if (owner) {
    shelf.addEventListener("click", (event) => {
      const head = event.target.closest(".fh-grphead");
      if (!head || (find.value || "").trim()) return;   // a search has them all open
      const name = head.dataset.group;
      if (state.folded[name]) delete state.folded[name]; else state.folded[name] = true;
      keep(); draw();
      const again = shelf.querySelector(`.fh-grphead[data-group="${CSS.escape(name)}"]`);
      if (again) again.focus();
    });
  }
  let sortMenu = null;
  const closeSort = (back) => {
    if (!sortMenu) return;
    sortMenu.remove(); sortMenu = null;
    sortBtn.setAttribute("aria-expanded", "false");
    if (back) sortBtn.focus();
  };
  if (sortBtn) {
    sortBtn.addEventListener("click", () => {
      if (sortMenu) { closeSort(true); return; }
      const menu = document.createElement("div");
      menu.className = "ctxmenu sortmenu";
      menu.setAttribute("role", "menu");
      menu.setAttribute("aria-label", "Sort");
      const item = (role, on, label, run) => {
        const b = document.createElement("button");
        b.type = "button";
        b.className = `ctxitem${on ? " ticked" : ""}`;
        b.setAttribute("role", role);
        b.setAttribute("aria-checked", on ? "true" : "false");
        b.tabIndex = -1;
        b.textContent = label;
        b.addEventListener("click", () => { closeSort(true); run(); keep(); draw(); });
        return b;
      };
      for (const [key, label] of OWNER_SORTS) menu.append(item("menuitemradio", state.order === key, label, () => { state.order = key; }));
      const rule = document.createElement("div");
      rule.className = "ctxsep";
      rule.setAttribute("role", "separator");
      menu.append(rule, item("menuitemcheckbox", state.flat, "No Groups", () => { state.flat = !state.flat; }));
      (document.querySelector(".fh2") || document.body).append(menu);
      const at = sortBtn.getBoundingClientRect(), box = menu.getBoundingClientRect();
      menu.style.left = `${Math.max(8, Math.min(at.right - box.width, window.innerWidth - box.width - 8))}px`;
      menu.style.top = `${Math.min(at.bottom + 6, window.innerHeight - box.height - 8)}px`;
      sortMenu = menu;
      sortBtn.setAttribute("aria-expanded", "true");
      const items = [...menu.querySelectorAll("[role^=menuitem]")];
      menu.addEventListener("keydown", (event) => {
        const i = items.indexOf(document.activeElement);
        if (event.key === "ArrowDown") items[(i + 1) % items.length].focus();
        else if (event.key === "ArrowUp") items[(i <= 0 ? items.length : i) - 1].focus();
        else if (event.key === "Home") items[0].focus();
        else if (event.key === "End") items[items.length - 1].focus();
        else if (event.key === "Enter" || event.key === " ") { if (i >= 0) items[i].click(); }
        else if (event.key === "Escape" || event.key === "Tab") closeSort(true);
        else return;
        event.preventDefault();
        event.stopPropagation();
      });
      (items.find((x) => x.getAttribute("aria-checked") === "true") || items[0]).focus({ preventScroll: true });
    });
    document.addEventListener("pointerdown", (event) => {
      if (sortMenu && !sortMenu.contains(event.target) && !sortBtn.contains(event.target)) closeSort(false);
    }, true);
    window.addEventListener("resize", () => closeSort(false));
  }
  find.addEventListener("input", draw);
  // **Enter opens the one film left**, which makes the search a way to jump
  // straight to a project as well as a way to narrow the shelf.
  find.addEventListener("keydown", (event) => {
    if (event.key === "Escape") { find.value = ""; draw(); return; }
    if (event.key !== "Enter") return;
    const left = cards.filter((c) => !c.hidden);
    if (left.length >= 1 && find.value.trim()) location.href = left[0].href;
  });
  // `/` finds, from anywhere on the shelf, as on most sites with a search.
  document.addEventListener("keydown", (event) => {
    if (event.key !== "/" || event.metaKey || event.ctrlKey || event.altKey) return;
    const at = document.activeElement;
    if (at && (at.tagName === "INPUT" || at.tagName === "TEXTAREA" || at.tagName === "SELECT" || at.isContentEditable)) return;
    event.preventDefault();
    find.focus();
  });

  tools.hidden = false;
  draw();
}

/**
 * **The card opens into the film** — Ref 1161, item 1. The film's mark and
 * name are the two things that travel between every screen of a film
 * (`filmmark`, `filmname` in front.css); a shelf holds one of each per film,
 * so its cards carry neither name — several elements with one name abort a
 * transition outright. The card being opened is given them at the moment it
 * is pressed, so the mark and the name fly from the card to where they sit on
 * the film's page instead of the page being swapped under them.
 *
 * Coming back by Projects, the card of the film just left takes them for the
 * length of the move, so the mark lands back in its card.
 */
function named(card, on) {
  const mark = card.querySelector(".filmicon");
  const name = card.querySelector(".t");
  if (mark) mark.style.viewTransitionName = on ? "filmmark" : "";
  if (name) name.style.viewTransitionName = on ? "filmname" : "";
}
const allCards = () => [...document.querySelectorAll("[data-shelf] .pcard")];
document.addEventListener("click", (event) => {
  const card = event.target.closest(".pcard");
  if (!card || event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
  for (const other of allCards()) named(other, false);
  named(card, true);
});
// Enter in the search opens the film at the top — the same move.
document.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" || !event.target.matches || !event.target.matches("[data-shelffind]")) return;
  const first = allCards().find((c) => !c.hidden);
  if (first) named(first, true);
}, true);
// Back from a film with the browser's own cache: whatever was named goes.
window.addEventListener("pageshow", () => { for (const card of allCards()) named(card, false); });
window.addEventListener("pagereveal", (event) => {
  if (!event.viewTransition || !window.navigation || !navigation.activation || !navigation.activation.from) return;
  const from = new URL(navigation.activation.from.url);
  const card = allCards().find((c) => !c.hidden && (from.pathname === c.pathname || from.pathname.startsWith(`${c.pathname}/`)));
  if (!card) return;
  named(card, true);
  event.viewTransition.finished.finally(() => named(card, false)).catch(() => {});
});
