/**
 * The portal's own right-click menu, and the Library's selection toolbar.
 *
 * **One menu, drawn by us.** His ask, 2026-10-02: *"across the portal I would
 * love an in-app right click menu"*, and in the Library *"a list or card
 * function with the ability to multiselect and apply settings with either that
 * right click menu bar or some sort of tool bar."* So there is one small menu
 * component, and the right click and the toolbar both open it — the toolbar's
 * Sidebar, Links, Me and Move To buttons are the same entries as the menu's.
 *
 * **It never takes away the browser's own.** Shift or Alt with the right click
 * gives the browser's menu; so does a right click in a field, on selected text,
 * or anywhere in the program's own screens (`#film`, which have menus of their
 * own). A menu that cannot be got out of is worse than none.
 *
 * **Nothing here decides who may do what.** The entries an editor or an
 * administrator sees are drawn from what the page says about them
 * (`data-editor`, `data-admin`, `data-arrange` on the rail), and the server
 * refuses the rest — `/library` is an editor's and the Visibility actions are
 * an administrator's, whatever this file draws.
 *
 * Delegated from `document`, so a page swapped in place by `deep.js` needs
 * nothing re-wired; `swapped` only resets what a new page starts with.
 */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const inApp = () => Boolean(document.getElementById("film"));

/* ===========================================================================
   The menu                                                                   */

let menu = null;
let shownAt = 0;

function closeMenu() {
  if (menu) { menu.remove(); menu = null; }
}

/** Items are `{ label, run }`, `{ label, items }` for a submenu, `{ label, on }` for a ticked one, or `"-"`. */
function build(items) {
  const el = document.createElement("div");
  el.className = "ctxmenu";
  el.setAttribute("role", "menu");
  for (const item of items) {
    // **A small label** (Seen On) or **a node of our own** (the Seen On row).
    if (item && item.section) {
      const label = document.createElement("div");
      label.className = "ctxsec";
      label.textContent = item.section;
      el.append(label);
      continue;
    }
    if (item && item.node) {
      const holder = document.createElement("div");
      holder.className = "ctxnode";
      holder.append(item.node);
      el.append(holder);
      continue;
    }
    if (item === "-") {
      const rule = document.createElement("div");
      rule.className = "ctxsep";
      rule.setAttribute("role", "separator");
      el.append(rule);
      continue;
    }
    const button = document.createElement("button");
    button.type = "button";
    button.className = "ctxitem";
    button.setAttribute("role", "menuitem");
    button.textContent = item.label;
    if (item.on) button.classList.add("ticked");
    if (item.warn) button.classList.add("ctxwarn");
    if (item.disabled) button.disabled = true;
    if (item.items) {
      const wrap = document.createElement("div");
      wrap.className = "ctxwrap";
      button.classList.add("hassub");
      button.setAttribute("aria-haspopup", "menu");
      const sub = build(item.items);
      sub.classList.add("ctxsub");
      wrap.append(button, sub);
      const open = () => {
        for (const other of $$(".ctxsub.open", el)) if (other !== sub) other.classList.remove("open");
        sub.classList.add("open");
        // Out to the right, or back to the left when there is no room.
        sub.style.left = "";
        sub.style.right = "";
        const box = sub.getBoundingClientRect();
        if (box.right > window.innerWidth - 8) { sub.style.left = "auto"; sub.style.right = "calc(100% - 4px)"; }
        const low = sub.getBoundingClientRect().bottom - (window.innerHeight - 8);
        if (low > 0) sub.style.top = `${-6 - low}px`;
      };
      wrap.addEventListener("pointerenter", open);
      wrap.addEventListener("pointerleave", () => sub.classList.remove("open"));
      button.addEventListener("click", (event) => { event.stopPropagation(); open(); });
      el.append(wrap);
    } else {
      button.addEventListener("click", () => { closeMenu(); item.run && item.run(); });
      el.append(button);
    }
  }
  return el;
}

/** Open the menu at a point, or above one (`up`) for a toolbar button. */
function showMenu(x, y, items, up = false) {
  closeMenu();
  shownAt = Date.now();
  menu = build(items);
  (document.querySelector(".fh2") || document.body).append(menu);
  menu.style.left = `${x}px`;
  menu.style.top = `${y}px`;
  const box = menu.getBoundingClientRect();
  let left = x;
  let top = up ? y - box.height - 6 : y;
  if (left + box.width > window.innerWidth - 8) left = Math.max(8, window.innerWidth - box.width - 8);
  if (top + box.height > window.innerHeight - 8) top = Math.max(8, window.innerHeight - box.height - 8);
  if (top < 8) top = 8;
  menu.style.left = `${left}px`;
  menu.style.top = `${top}px`;
  const first = $(".ctxitem:not(:disabled), .seenon .sn", menu);
  if (first) first.focus({ preventScroll: true });
}

document.addEventListener("pointerdown", (event) => {
  if (menu && !menu.contains(event.target)) closeMenu();
}, true);
window.addEventListener("resize", closeMenu);
window.addEventListener("blur", closeMenu);
// A shelf settling on a snap point just after a press and hold is not the reader scrolling away.
document.addEventListener("scroll", () => { if (Date.now() - shownAt > 700) closeMenu(); }, true);

document.addEventListener("keydown", (event) => {
  if (menu) {
    const here = document.activeElement;
    const list = $$(".ctxitem:not(:disabled), .seenon .sn", here && here.closest(".ctxmenu") ? here.closest(".ctxmenu") : menu)
      .filter((el) => el.offsetParent !== null);
    const at = list.indexOf(here);
    if (event.key === "Escape") { closeMenu(); event.preventDefault(); return; }
    if (event.key === "ArrowDown") { (list[(at + 1) % list.length] || list[0]).focus(); event.preventDefault(); return; }
    if (event.key === "ArrowUp") { (list[(at - 1 + list.length) % list.length] || list[0]).focus(); event.preventDefault(); return; }
    if (event.key === "ArrowRight" && here && here.classList.contains("hassub")) {
      here.click();
      const inner = $(".ctxitem", here.parentElement.querySelector(".ctxsub"));
      if (inner) inner.focus();
      event.preventDefault();
      return;
    }
    if (event.key === "ArrowLeft" && here && here.closest(".ctxsub")) {
      const sub = here.closest(".ctxsub");
      sub.classList.remove("open");
      const parent = $(".ctxitem", sub.parentElement);
      if (parent) parent.focus();
      event.preventDefault();
      return;
    }
    return;
  }
  if (event.key === "Escape" && active()) clearPicks();
});

/* ===========================================================================
   Small things the entries do                                                 */

const absolute = (href) => new URL(href, location.href).href;

async function copy(text) {
  await feel.copy(text, "Link Copied");
}

/** A word in the shared pill (`feel.js`), at the bottom, leaving by itself. */
const say = (words) => feel.toast(words);

const going = (href, fresh) => { if (fresh) window.open(href, "_blank", "noopener"); else location.href = href; };

/** The three that every link has. */
const linkItems = (href, outside = false) => [
  { label: "Open", run: () => going(href, outside) },
  { label: "Open in New Tab", run: () => going(href, true) },
  { label: "Copy Link", run: () => copy(absolute(href)) },
];

/* ===========================================================================
   Changing things, many at a time

   One post, one save, on the server (`bulk` in `worker.js`). Every action says
   where things end up rather than flipping them, so a selection of mixed
   things comes out the same however it started.                              */

/** What each action says when it is done. */
const SAID = {
  pin: "Pinned", unpin: "Unpinned", archive: "Archived", unarchive: "Unarchived", icon: "Icon Changed",
  private: "Made Private", public: "Made Public",
};

/**
 * **How to put it back**, worked out from the card as it stood before the
 * change, so a selection of mixed things comes back as it was, not all one way.
 */
function undoSteps(action, keys) {
  const card = (k) => (pane() ? cardOf(k) : null);
  const split = (was, yes, no) => {
    const a = keys.filter((k) => was(k));
    const b = keys.filter((k) => !was(k));
    return [a.length && { action: yes, keys: a }, b.length && { action: no, keys: b }].filter(Boolean);
  };
  const flag = (k, name, otherwise) => { const c = card(k); return c ? c.dataset[name] === "1" : otherwise; };
  if (action === "icon") {
    // Put each one back to the icon it wore, which only a Library card remembers.
    const by = {};
    for (const k of keys) { const c = card(k); if (c) (by[c.dataset.icon || ""] = by[c.dataset.icon || ""] || []).push(k); }
    return Object.entries(by).map(([to, ks]) => ({ action: "icon", keys: ks, to }));
  }
  if (action === "pin" || action === "unpin") return split((k) => flag(k, "side", action === "unpin"), "pin", "unpin");
  if (action === "archive" || action === "unarchive") return split((k) => flag(k, "archived", action === "unarchive"), "archive", "unarchive");
  if (action === "private" || action === "public") {
    const priv = (k) => { const c = card(k); return c ? c.dataset.links === "0" : action === "public"; };
    return split((k) => priv(k), "private", "public");
  }
  if (action === "shelf") {
    const prior = (k) => { const c = card(k); return c ? c.dataset.shelf || "" : ""; };
    if (!keys.every((k) => prior(k))) return null;
    const by = new Map();
    for (const k of keys) by.set(prior(k), [...(by.get(prior(k)) || []), k]);
    return [...by].map(([to, list]) => ({ action: "shelf", keys: list, to }));
  }
  return null;
}

/**
 * Change things, say so in the pill with an Undo, and show the result. The
 * page reloads to draw it, so the pill is said by the page that comes back
 * (`feel.later`).
 */
async function apply(action, keys, to = "", lib = null) {
  lib = lib || ($(".fh-libpane") ? $(".fh-libpane").dataset.lib : `${location.pathname.split("/").slice(0, 3).join("/")}/library`);
  const steps = undoSteps(action, keys);
  const body = new FormData();
  body.set("bulk", JSON.stringify({ keys, action, to }));
  let got = null;
  try { got = await fetch(lib, { method: "POST", body, credentials: "same-origin" }); } catch { /* said below */ }
  if (!got || !got.ok) { say(got && got.status === 403 ? "That is not yours to change" : "That did not go through"); return; }
  const undoPost = steps && steps.length
    ? steps.map((one) => ({ url: lib, fields: { bulk: JSON.stringify({ keys: one.keys, action: one.action, to: one.to || "" }) } }))
    : null;
  feel.later(action === "shelf" ? `Moved to ${to}` : SAID[action] || "Saved", undoPost ? { undoPost } : {});
  location.reload();
}

/**
 * **Follow Google Doc** on, off, or a redraw now (`POST <film>/follow`). The
 * switch is drawn again where the page is shown; a redraw reloads the page he
 * is reading, if it is this one, so he sees what came in.
 */
async function follow(one, ask) {
  let got = null;
  let data = null;
  try {
    got = await fetch(`${one.base}/follow`, {
      method: "POST", credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ slug: one.key, ...ask }),
    });
    data = await got.json();
  } catch { /* said below */ }
  if (!got || !data) { say("That did not go through"); return; }
  if (typeof data.on === "boolean") {
    for (const el of $$(`[data-key="${CSS.escape(one.key)}"][data-follow]`)) el.dataset.follow = data.on ? "1" : "0";
  }
  const here = location.pathname.replace(/\/$/, "") === `${one.base}/${one.key}`;
  if (got.ok && here && data.drawn && (ask.refresh || ask.on)) { feel.later(data.said || "Updated from the Doc"); location.reload(); return; }
  say(data.said || (got.ok ? "Saved" : "That did not go through"));
}

const shelvesOf = () => {
  const from = $(".fh-libpane") || $("nav.rail[data-shelves]");
  try { return JSON.parse((from && from.dataset.shelves) || "[]"); } catch { return []; }
};
const onOff = (on, off) => [{ label: "On", run: on }, { label: "Off", run: off }];

/**
 * **One menu for a page, wherever it is asked for** (move 4): the sidebar's
 * ⋯, the Library card's ⋯ and the right click all come here, so they cannot
 * drift. Order is fixed:
 *
 *     Pinned    [switch]
 *     Private   [switch]
 *     ───────
 *     Open · Rename (a page he made) · Move To ›
 *     ───────
 *     Archive  (warm)
 *
 * It is about **one page or card, or about several picked ones**; a switch is
 * on only for a setting every one of them has, and a press sets all.
 */
function infoOf(el) {
  const card = el.classList.contains("fh-card");
  const rail = el.closest("nav.rail");
  const root = card ? pane() : rail;
  const lib = card && root ? root.dataset.lib : "";
  const key = el.dataset.key || "";
  const name = card ? el.dataset.name || key : ((el.querySelector(".nm") || el).textContent || "").trim();
  return {
    el, card, key, name,
    base: card ? lib.replace(/\/library$/, "") : (rail && rail.dataset.base) || "",
    doc: key.startsWith("doc:"),
    href: card ? el.dataset.href : el.getAttribute("href") || "",
    outside: card ? el.dataset.outside === "1" : el.dataset.outside === "1" || key.startsWith("doc:"),
    side: card ? el.dataset.side === "1" : true,
    priv: el.dataset.links === "0",
    rename: el.dataset.rename === "1",
    follow: el.dataset.follow === undefined ? null : el.dataset.follow === "1",
    archived: card && el.dataset.archived === "1",
    icon: el.dataset.icon || "",
    admin: Boolean(root && root.hasAttribute("data-admin")),
  };
}

/** The little neutral tags on a card, drawn again after a setting changes. */
function cardTags(card) {
  let line = $(".fh-cardstate", card);
  const home = $(".fh-meta", card) || $(".fh-cardlink", card);
  // **Only the lock**: a Private page, for an editor. What is pinned is what
  // the sidebar shows, so the card says nothing about it.
  if (card.dataset.links !== "0" || !pane() || !pane().hasAttribute("data-editor")) { if (line) line.remove(); return; }
  if (!line) { line = document.createElement("span"); line.className = "fh-cardstate"; home.append(line); }
  line.innerHTML = `<span class="fh-tag fh-lock" title="Private"><svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.4 7.2h7.2a1.4 1.4 0 0 1 1.4 1.4v4.2a1.4 1.4 0 0 1-1.4 1.4H4.4A1.4 1.4 0 0 1 3 12.8V8.6a1.4 1.4 0 0 1 1.4-1.4Z"/><path d="M5.6 7.2V5.4a2.4 2.4 0 0 1 4.8 0v1.8"/></svg></span>`;
}

/** Show a changed setting where it is drawn, without reloading. */
function paint(el, kind, on) {
  if (el.classList.contains("fh-card")) {
    for (const one of sameKey(el.dataset.key)) {
      if (kind === "pin") one.dataset.side = on ? "1" : "0";
      else one.dataset.links = on ? "0" : "1";
      cardTags(one);
    }
    // The sidebar row, if it has one, shows the lock at once.
    if (kind === "priv") {
      for (const row of $$(`nav.rail .to[data-key="${CSS.escape(el.dataset.key)}"]`)) {
        row.dataset.links = on ? "0" : "1";
        row.classList.toggle("offl", on);
      }
    }
    if (kind === "pin" && window.sidebar) window.sidebar.refresh();
    return;
  }
  if (kind === "priv") {
    el.dataset.links = on ? "0" : "1";
    el.classList.toggle("offl", on);
  } else if (kind === "pin" && !on) {
    // Off the sidebar: the row leaves it, still in the Library and at its address.
    closeMenu();
    el.classList.add("leaving");
    setTimeout(() => el.remove(), 180);
  }
}

/**
 * **The icon picker**: the whole set as a grid, the current one ringed, and a
 * button that goes back to the default. A press sets every page or card in the
 * selection (`apply("icon", …)`, which saves in one go and reloads).
 */
function iconPicker(list, keys, lib) {
  const wrap = document.createElement("div");
  wrap.className = "iconpick";
  const table = window.ROW_ICONS || {};
  const now = list.every((i) => i.icon === list[0].icon) ? list[0].icon : "";
  const grid = document.createElement("div");
  grid.className = "ipgrid";
  for (const name of window.ICON_CHOICES || []) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `ip${name === now ? " on" : ""}`;
    button.title = name.charAt(0).toUpperCase() + name.slice(1);
    button.setAttribute("aria-label", button.title);
    button.innerHTML = `<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${table[name] || ""}</svg>`;
    button.addEventListener("click", () => { closeMenu(); apply("icon", keys, name, lib); });
    grid.append(button);
  }
  const reset = document.createElement("button");
  reset.type = "button";
  reset.className = "ipreset";
  reset.textContent = "Use Default";
  reset.addEventListener("click", () => { closeMenu(); apply("icon", keys, "", lib); });
  wrap.append(grid, reset);
  return wrap;
}

function menuFor(els, { rightClick = false } = {}) {
  const list = els.map(infoOf);
  const one = list.length === 1 ? list[0] : null;
  const first = list[0];
  const keys = list.map((i) => i.key);
  const every = (f) => list.every(f);
  const items = [];
  const can = { pin: true, priv: first.admin };
  if (can.pin || can.priv) {
    items.push({ node: window.seenOn({
      base: first.base, keys, pinned: every((i) => i.side), priv: every((i) => i.priv), can,
      onChange: (kind, on) => { for (const i of list) paint(i.el, kind, on); },
    }) });
    items.push("-");
  }
  if (one) {
    items.push({ label: "Open", run: () => going(one.href, one.outside) });
    if (rightClick) {
      items.push({ label: "Open in New Tab", run: () => going(one.href, true) });
      items.push({ label: "Copy Link", run: () => copy(absolute(one.href)) });
    }
    if (one.rename && window.sidebar) items.push({ label: "Rename", run: () => window.sidebar.rename(one.el) });
    // **A page drawn from a Google Doc** (`docfollow.js`): the switch that
    // keeps it in step with the doc, and a redraw now. An administrator's.
    if (one.follow !== null && one.admin) {
      items.push({ label: "Follow Google Doc", on: one.follow, run: () => follow(one, { on: !one.follow }) });
      if (one.follow) items.push({ label: "Refresh from Doc", run: () => follow(one, { refresh: true }) });
    }
  } else {
    items.unshift({ label: `${list.length} Selected`, disabled: true });
  }
  const now = one && one.card ? one.el.dataset.shelf || "" : "";
  items.push({ label: "Icon", items: [{ node: iconPicker(list, keys, `${first.base}/library`) }] });
  items.push({ label: "Move To", items: shelvesOf().map((name) => ({ label: name, on: name === now, run: () => apply("shelf", keys, name, `${first.base}/library`) })) });
  {
    const archived = every((i) => i.archived);
    items.push("-");
    items.push({ label: archived ? "Unarchive" : "Archive", warn: !archived, run: () => apply(archived ? "unarchive" : "archive", keys, "", `${first.base}/library`) });
  }
  return items;
}

/**
 * **A sidebar row's own menu** (2026-10-11, the approved layout): what the
 * sidebar does to a row, and nothing the Library already does. One switch,
 * On Sidebar (off takes the row away; Add Pages puts it back), then Rename
 * for a page he made and Icon. A page following a Google Doc keeps its
 * Follow Google Doc switch here, an administrator's. A right click adds the
 * three every link has.
 */
function rowMenu(row, { rightClick = false } = {}) {
  const one = infoOf(row);
  const items = [];
  if (rightClick) items.push(...linkItems(one.href), "-");
  items.push({ node: window.seenOn({
    base: one.base, keys: [one.key], pinned: true, can: { pin: true, priv: false }, words: { pin: "On Sidebar" },
    onChange: (kind, on) => { if (kind === "pin" && !on) paint(row, "pin", false); },
  }) });
  items.push("-");
  if (one.rename && window.sidebar) items.push({ label: "Rename", run: () => window.sidebar.rename(row) });
  items.push({ label: "Icon", items: [{ node: iconPicker([one], [one.key], `${one.base}/library`) }] });
  if (one.follow !== null && one.admin) {
    items.push("-");
    items.push({ label: "Follow Google Doc", on: one.follow, run: () => follow(one, { on: !one.follow }) });
    if (one.follow) items.push({ label: "Refresh from Doc", run: () => follow(one, { refresh: true }) });
  }
  return items;
}

/** Offered to the rest of the page: the sidebar draws its ⋯ and its headings' menus through these. */
window.portalMenu = { show: (x, y, items, up) => showMenu(x, y, items, up), forPages: menuFor, forRow: rowMenu, close: closeMenu, say };

/* ===========================================================================
   The Library: view, selection, toolbar                                      */

const picked = new Set();
let lastPicked = null;
// **Picking is a mode you go into, not a column of boxes that is always there.**
// A Cmd or Ctrl click, a press and hold on a phone, or the quiet Select button
// starts it; the ticks only show while it is on, and leave with it.
let selecting = false;
const active = () => selecting || picked.size > 0;
let suppress = false;       // the click that follows a press and hold is not a tap
let lastPointer = "";

const pane = () => $(".fh-libpane");
// **A Recently Opened card is an echo** (`data-echo`) of one on a shelf below,
// the same key: picking either picks both, and everything that asks for "the
// card" gets the one that stands on its own shelf.
const visibleCards = () => $$(".fh-card:not([data-echo])", pane() || document).filter((c) => !c.hidden && !c.closest("[data-off]"));
const cardOf = (key) => $$(".fh-card:not([data-echo])", pane() || document).find((c) => c.dataset.key === key);
function sameKey(key) { return $$(".fh-card", pane() || document).filter((c) => c.dataset.key === key); }

function setPick(card, on) {
  const key = card.dataset.key;
  if (on) picked.add(key); else picked.delete(key);
  for (const one of sameKey(key)) {
    one.classList.toggle("picked", on);
    const box = $(".fh-pick input", one);
    if (box) box.checked = on;
  }
}

function clearPicks() {
  for (const key of [...picked]) { const c = cardOf(key); if (c) setPick(c, false); }
  picked.clear();
  lastPicked = null;
  selecting = false;
  drawBar();
}

function drawBar() {
  const bar = $(".fh-bulk");
  const root = pane();
  if (!bar || !root) return;
  root.classList.toggle("picking", active());
  const toggle = $("[data-select]", root);
  if (toggle) toggle.textContent = active() ? "Done" : "Select";
  if (!active()) { bar.hidden = true; bar.replaceChildren(); return; }
  if (!picked.size) {
    // Selecting, nothing chosen yet: say so, and offer the two things to do.
    bar.hidden = false;
    bar.replaceChildren();
    const hint = document.createElement("span");
    hint.className = "fh-bulkn";
    hint.textContent = "Select Items";
    bar.append(hint);
    const all = document.createElement("button");
    all.type = "button";
    all.className = "fh-bulkbtn";
    all.textContent = "Select All";
    all.addEventListener("click", () => { for (const card of visibleCards()) setPick(card, true); drawBar(); });
    const done = document.createElement("button");
    done.type = "button";
    done.className = "fh-bulkbtn quiet";
    done.textContent = "Done";
    done.addEventListener("click", clearPicks);
    bar.append(all, done);
    return;
  }
  const admin = root.hasAttribute("data-admin");
  const keys = [...picked];
  bar.hidden = false;
  bar.replaceChildren();
  const n = document.createElement("span");
  n.className = "fh-bulkn";
  n.textContent = `${keys.length} Selected`;
  bar.append(n);
  const add = (label, items, run) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "fh-bulkbtn";
    button.textContent = label;
    if (items) {
      button.classList.add("hasmenu");
      button.setAttribute("aria-haspopup", "menu");
      button.addEventListener("click", (event) => {
        event.stopPropagation();
        const box = button.getBoundingClientRect();
        showMenu(box.left, box.top, items, true);
      });
    } else button.addEventListener("click", run);
    bar.append(button);
  };
  add("Pinned", onOff(() => apply("pin", keys), () => apply("unpin", keys)));
  if (admin) add("Private", onOff(() => apply("private", keys), () => apply("public", keys)));
  add("Move To", shelvesOf().map((name) => ({ label: name, run: () => apply("shelf", keys, name) })));
  add("Archive", null, () => apply("archive", keys));
  const clear = document.createElement("button");
  clear.type = "button";
  clear.className = "fh-bulkbtn quiet";
  clear.textContent = "Done";
  clear.addEventListener("click", clearPicks);
  const everything = document.createElement("button");
  everything.type = "button";
  everything.className = "fh-bulkbtn quiet";
  everything.textContent = "Select All";
  everything.addEventListener("click", () => { for (const card of visibleCards()) setPick(card, true); drawBar(); });
  bar.append(everything, clear);
}

function pick(card, shift) {
  selecting = true;
  if (shift && lastPicked && lastPicked !== card) {
    const all = visibleCards();
    const a = all.indexOf(lastPicked);
    const b = all.indexOf(card);
    if (a >= 0 && b >= 0) {
      const [from, to] = a < b ? [a, b] : [b, a];
      for (const one of all.slice(from, to + 1)) setPick(one, true);
      lastPicked = card;
      drawBar();
      return;
    }
  }
  setPick(card, !picked.has(card.dataset.key));
  lastPicked = card;
  drawBar();
}

function setView(view) {
  const root = pane();
  if (!root) return;
  root.dataset.view = view;
  for (const button of $$(".fh-seg button", root)) button.setAttribute("aria-pressed", String(button.dataset.view === view));
  try { localStorage.setItem("fh-library-view", view); } catch { /* private window */ }
  fitShelves();
}

/* ===========================================================================
   Recently Opened, and a shelf that is longer than a row

   **Per person, per film, in this browser** (localStorage, `fh-opened:<film>`):
   the last things opened from a Library card or the sidebar, newest first.
   Nothing here is sent anywhere; a browser with it blocked just has no top
   shelf.                                                                    */

const filmOf = () => (location.pathname.match(/^\/f\/([^/]+)/) || [])[1] || "";
const openedKey = () => `fh-opened:${filmOf()}`;
function readOpened() {
  try {
    const list = JSON.parse(localStorage.getItem(openedKey()) || "[]");
    return Array.isArray(list) ? list.filter((o) => o && typeof o.k === "string" && Number(o.t) > 0) : [];
  } catch { return []; }
}
function recordOpen(key) {
  if (!key || !filmOf()) return;
  try {
    const list = [{ k: key, t: Date.now() }, ...readOpened().filter((o) => o.k !== key)].slice(0, 30);
    localStorage.setItem(openedKey(), JSON.stringify(list));
  } catch { /* private window */ }
}

/** "today", "yesterday", "3 days ago", "last week", "2 weeks ago", "3 months ago". */
function ago(t) {
  const midnight = new Date(); midnight.setHours(0, 0, 0, 0);
  if (t >= midnight.getTime()) return "today";
  const days = Math.ceil((midnight.getTime() - t) / 86400000);
  if (days <= 1) return "yesterday";
  if (days < 7) return `${days} days ago`;
  if (days < 14) return "last week";
  if (days < 60) return `${Math.floor(days / 7)} weeks ago`;
  return `${Math.floor(days / 30)} months ago`;
}

/** "Opened …" under a cover on the Recently Opened shelf only; said on every
 *  shelf it was the same news twice. */
function stampOpened() {
  const when = new Map(readOpened().map((o) => [o.k, o.t]));
  for (const card of $$(".fh-card[data-echo]", pane())) {
    const line = $(".fh-cardkind", card);
    if (!line) continue;
    if (line.dataset.note === undefined) line.dataset.note = line.textContent;
    const t = when.get(card.dataset.key);
    line.textContent = t ? [line.dataset.note, `Opened ${ago(t)}`].filter(Boolean).join(" · ") : line.dataset.note;
  }
}

/** The top shelf: the last four, as echoes of the cards below. Hidden when empty. */
function drawRecent() {
  const root = pane();
  if (!root) return;
  for (const old of $$(".fh-recent", root)) old.remove();
  const first = $(".fh-shelf", root);
  if (!first) return;
  const real = $$(".fh-card:not([data-echo])", root);
  const echoes = [];
  for (const one of readOpened()) {
    const card = real.find((c) => c.dataset.key === one.k && c.dataset.archived !== "1");
    if (card) echoes.push(card);
    if (echoes.length === 4) break;
  }
  if (!echoes.length) return;
  const shelf = document.createElement("section");
  shelf.className = "fh-shelf fh-recent";
  shelf.id = "shelf-recent";
  shelf.innerHTML = `<h2>${window.ROW_ICONS && window.SHELF_ICONS ? `<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${window.ROW_ICONS[window.SHELF_ICONS["Recently Opened"]] || ""}</svg>` : ""}Recently Opened<span>${echoes.length}</span></h2><div class="fh-cards"></div>`;
  const row = $(".fh-cards", shelf);
  for (const card of echoes) {
    const echo = card.cloneNode(true);
    echo.dataset.echo = "1";
    echo.classList.toggle("picked", picked.has(card.dataset.key));
    const box = $(".fh-pick input", echo);
    if (box) box.checked = picked.has(card.dataset.key);
    row.append(echo);
  }
  first.before(shelf);
}

/**
 * A shelf holds one row. When it has more than a row's worth, See All opens it
 * out; a narrow phone scrolls the row sideways instead (CSS), so there it is
 * not offered.
 */
function fitShelves() {
  const root = pane();
  if (!root) return;
  const phone = matchMedia("(max-width: 760px)").matches;
  for (const shelf of $$(".fh-shelf", root)) {
    const row = $(".fh-cards", shelf);
    const more = $("[data-more]", shelf);
    if (!row || !more) continue;
    const open = shelf.hasAttribute("data-open");
    if (!open) shelf.setAttribute("data-collapsed", "");
    const over = !phone && root.dataset.view !== "list" && (open || row.scrollWidth > row.clientWidth + 2);
    more.hidden = !over;
    more.textContent = open ? "See Less" : "See All";
    more.setAttribute("aria-expanded", String(open));
    if (!over && !open) shelf.removeAttribute("data-collapsed");
  }
}
// A chip or a search changes what is on show, so which shelves overflow.
document.addEventListener("click", (e) => { if (e.target instanceof Element && e.target.closest(".fh-shelves a")) setTimeout(fitShelves, 0); });
document.addEventListener("input", (e) => { if (e.target instanceof Element && e.target.matches("[data-libfind]")) setTimeout(fitShelves, 0); });
let fitTimer = 0;
window.addEventListener("resize", () => { clearTimeout(fitTimer); fitTimer = setTimeout(fitShelves, 120); });

document.addEventListener("click", (event) => {
  const more = event.target instanceof Element ? event.target.closest("[data-more]") : null;
  if (!more) return;
  const shelf = more.closest(".fh-shelf");
  if (shelf.hasAttribute("data-open")) shelf.removeAttribute("data-open"); else shelf.setAttribute("data-open", "");
  fitShelves();
});

// **An open is a plain click on a card or a sidebar row** — not a pick, not the
// ⋯, not the tick. Heard before the page moves, so it is in storage by then.
document.addEventListener("click", (event) => {
  const target = event.target instanceof Element ? event.target : null;
  if (!target || target.closest(".fh-cardmenu, .fh-pick")) return;
  const link = target.closest(".fh-card .fh-cardlink, nav.rail .to[data-key]");
  if (!link) return;
  const root = pane();
  const picking = root && root.hasAttribute("data-editor") && (event.metaKey || event.ctrlKey || event.shiftKey || active());
  if (picking || suppress) return;
  const holder = link.closest(".fh-card");
  recordOpen(holder ? holder.dataset.key : link.dataset.key);
}, true);

function initLibrary() {
  picked.clear();
  lastPicked = null;
  if (!pane()) return;
  let view = "cards";
  try { view = localStorage.getItem("fh-library-view") === "list" ? "list" : "cards"; } catch { /* default */ }
  drawRecent();
  stampOpened();
  setView(view);
  drawBar();
  // **The Archive folds shut and stays as he left it, per film.**
  const folder = $(".fh-archive", pane());
  if (folder) {
    const mine = `fh-archive-open:${pane().dataset.lib || ""}`;
    try { folder.open = localStorage.getItem(mine) === "1"; } catch { /* shut */ }
    folder.addEventListener("toggle", () => { try { localStorage.setItem(mine, folder.open ? "1" : "0"); } catch { /* not kept */ } });
  }
}

document.addEventListener("click", (event) => {
  const target = event.target instanceof Element ? event.target : null;
  if (!target || !pane()) return;

  // **The card's ⋯ draws the shared menu** (move 4). The `<details>` under it
  // is what a page with no script gets; with one, it is left shut.
  const more = target.closest(".fh-cardmenu > summary");
  if (more) {
    event.preventDefault();
    const card = more.closest(".fh-card");
    const box = more.getBoundingClientRect();
    const group = card && picked.size > 1 && picked.has(card.dataset.key) ? [...picked].map(cardOf).filter(Boolean) : [card];
    showMenu(box.left, box.bottom + 4, menuFor(group));
    return;
  }

  const seg = target.closest(".fh-seg button[data-view]");
  if (seg) { setView(seg.dataset.view); return; }

  // The quiet Select button: in, and out again.
  if (target.closest("[data-select]")) {
    if (active()) clearPicks(); else { selecting = true; drawBar(); }
    return;
  }

  // The click that ends a press and hold has already done its work.
  if (suppress && target.closest(".fh-card")) {
    suppress = false;
    event.preventDefault();
    event.stopPropagation();
    return;
  }

  const card = target.closest(".fh-card");
  if (!card || !pane().hasAttribute("data-editor")) return;
  // **The checkbox flips itself**; this only records what it now says. A click
  // on its label makes the browser click the box a moment later, so that one
  // is the one heard.
  if (target.closest(".fh-pick")) {
    if (target.matches("input")) {
      if (event.shiftKey && lastPicked && lastPicked !== card) { target.checked = false; pick(card, true); }
      else { setPick(card, target.checked); lastPicked = card; drawBar(); }
    }
    return;
  }
  // **A modified click, or any click once something is picked, selects**
  // rather than opens — the way every file list works.
  if (target.closest(".fh-cardmenu")) return;
  if (event.metaKey || event.ctrlKey || event.shiftKey || active()) {
    if (target.closest(".fh-cardlink") || card === target) {
      event.preventDefault();
      pick(card, event.shiftKey);
    }
  }
}, true);

// A search that hides a card takes it out of the selection too, so the number on
// the toolbar is the number you can see.
document.addEventListener("input", (event) => {
  if (!(event.target instanceof HTMLInputElement) || !event.target.hasAttribute("data-libfind")) return;
  queueMicrotask(() => {
    for (const key of [...picked]) {
      const card = cardOf(key);
      if (card && card.hidden) setPick(card, false);
    }
    drawBar();
  });
});

/* **Press and hold, on a phone or iPad.** (phone move 5) Under half a second on
   a cover or a list row, without moving, opens the same menu the right click
   gives, headed by the item's small cover and name. While it is held the cover
   lifts a little, and a finger that moves (a scroll) lets go of it. A tap still
   opens the item; in Select a tap ticks. The hold itself neither opens the item
   nor selects text (see `front.css`, touch block). */
let press = null;
const cancelPress = () => { if (press) { clearTimeout(press.timer); clearTimeout(press.lift); press.card.classList.remove("holding"); press = null; } };
const HOLD_MS = 450;

/** The item's small cover and its name, the top of a held item's menu. */
function holdHead(card) {
  const head = document.createElement("div");
  head.className = "ctxhead";
  const cv = card.querySelector(".fh-cv");
  if (cv) {
    const box = document.createElement("span");
    box.className = "ctxhcv";
    box.setAttribute("aria-hidden", "true");
    const copy = cv.cloneNode(true);
    copy.style.cssText = "width:128px;height:88px;transform:none;transition:none";
    box.append(copy);
    head.append(box);
  }
  const name = document.createElement("b");
  name.textContent = card.dataset.name || card.dataset.key || "";
  head.append(name);
  return { node: head };
}

function holdMenu(card) {
  const box = card.getBoundingClientRect();
  const editor = pane() && pane().hasAttribute("data-editor");
  const group = picked.size > 1 && picked.has(card.dataset.key) ? [...picked].map(cardOf).filter(Boolean) : [card];
  const items = editor
    ? menuFor(group)
    : linkItems(card.dataset.href, card.dataset.outside === "1");
  if (group.length === 1) items.unshift(holdHead(card), "-");
  const x = Math.max(8, Math.min(box.left + 12, window.innerWidth - 244));
  showMenu(x, box.bottom - 8, items);
}

document.addEventListener("pointerdown", (event) => {
  lastPointer = event.pointerType || "";
  suppress = false;
  const root = pane();
  if (!root || event.pointerType === "mouse" || !event.isPrimary) return;
  const target = event.target instanceof Element ? event.target : null;
  const card = target && target.closest(".fh-card");
  if (!card || target.closest(".fh-cardmenu, .fh-pick")) return;
  cancelPress();
  press = {
    x: event.clientX, y: event.clientY, card,
    lift: setTimeout(() => card.classList.add("holding"), 140),
    timer: setTimeout(() => {
      press = null;
      card.classList.remove("holding");
      suppress = true;
      setTimeout(() => { suppress = false; }, 1500);
      if (navigator.vibrate) navigator.vibrate(10);
      holdMenu(card);
    }, HOLD_MS),
  };
}, true);
document.addEventListener("pointermove", (event) => {
  if (press && Math.hypot(event.clientX - press.x, event.clientY - press.y) > 10) cancelPress();
}, true);
document.addEventListener("pointerup", cancelPress, true);
// No scroll listener: a shelf settling on a snap point scrolls under a finger that has not moved,
// and a real scroll already arrives as a move or a cancel.
document.addEventListener("pointercancel", cancelPress, true);

/* ===========================================================================
   The right click                                                            */

document.addEventListener("contextmenu", (event) => {
  if (inApp() || event.shiftKey || event.altKey) return;
  const target = event.target instanceof Element ? event.target : null;
  if (!target) return;
  // **A finger has no right button**: the press and hold on a card selects it
  // (above), and the browser's own pop-up over it would only be in the way.
  if (lastPointer === "touch" || lastPointer === "pen") {
    if (target.closest(".fh-card")) event.preventDefault();
    return;
  }
  if (target.closest("input, textarea, select, [contenteditable], .ctxmenu, .pmcard, summary")) return;
  if (String(window.getSelection && window.getSelection()).trim()) return;

  const root = pane();
  const editorRail = Boolean($("nav.rail[data-arrange]"));

  // ---- a card in the Library ------------------------------------------------
  const card = target.closest(".fh-card");
  if (card && root) {
    event.preventDefault();
    if (root.hasAttribute("data-editor")) {
      // A right click on something not picked picks it alone; on something
      // picked, it is about everything picked.
      if (!picked.has(card.dataset.key)) { clearPicks(); setPick(card, true); lastPicked = card; drawBar(); }
      showMenu(event.clientX, event.clientY, menuFor([...picked].map(cardOf).filter(Boolean), { rightClick: true }));
      return;
    }
    showMenu(event.clientX, event.clientY, linkItems(card.dataset.href, card.dataset.outside === "1"));
    return;
  }

  // ---- a heading on the sidebar ---------------------------------------------
  const head = target.closest("nav.rail .grouphead");
  if (head && editorRail && window.sidebar) {
    event.preventDefault();
    showMenu(event.clientX, event.clientY, window.sidebar.headItems(head));
    return;
  }

  // ---- a row on the sidebar -------------------------------------------------
  const row = target.closest("nav.rail .to");
  if (row && row.getAttribute("href")) {
    event.preventDefault();
    const editable = editorRail && row.dataset.key && row.closest("nav.rail[data-arrange]");
    showMenu(event.clientX, event.clientY, editable ? rowMenu(row, { rightClick: true }) : linkItems(row.getAttribute("href")));
    return;
  }

  // ---- any other link ---------------------------------------------------------
  const link = target.closest("a[href]");
  if (link && !link.getAttribute("href").startsWith("#") && !/^(mailto|tel|javascript):/.test(link.getAttribute("href"))) {
    event.preventDefault();
    showMenu(event.clientX, event.clientY, linkItems(link.getAttribute("href"), link.target === "_blank"));
    return;
  }

  // ---- the page itself ---------------------------------------------------------
  if (target.closest(".fh-pane, .paneshell, main")) {
    event.preventDefault();
    const rail = $("nav.rail a.librow");
    showMenu(event.clientX, event.clientY, [
      { label: "Copy Page Link", run: () => copy(location.href.split("#")[0]) },
      ...(rail ? [{ label: "Open Library", run: () => going(rail.getAttribute("href"), false) }] : []),
      { label: "Reload", run: () => location.reload() },
    ]);
  }
});

document.addEventListener("swapped", () => { closeMenu(); initLibrary(); });
initLibrary();
