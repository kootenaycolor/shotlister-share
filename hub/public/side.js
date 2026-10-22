/**
 * **The sidebar, edited where it stands** (move 1 of
 * `design/29-portal-details.src.html`).
 *
 * Before this, changing the sidebar meant leaving it: Headings was a page, Add
 * was a page, and what showed where was buried in Share. All of it is on the
 * sidebar now, for an editor:
 *
 * - **A heading** shows a fold arrow, a + (Add, aimed at that heading) and a ⋯
 *   (Rename, Remove) when the pointer is on it. Double-click renames it in
 *   place. Fold state is remembered per film in this browser.
 * - **`+ New Heading`** sits quietly at the bottom of the list.
 * - **A heading is a category** (2026-10-11): Rename renames the category,
 *   New Heading adds one, Remove removes one he added (the seven stay).
 * - **A row** shows a ⋯ when the pointer is on it: the sidebar's own menu
 *   (`rowMenu` in `ctx.js`): On Sidebar, Rename, Icon. Right click opens it
 *   too. Dragging is `arrange.js`, which this does not touch.
 * - **Add Pages…** puts pages that are not on the sidebar back on, picked
 *   from a short list.
 * - **Find** opens the ⌘K box (`jump.js`) for everybody, viewers included.
 *
 * **Nothing here is attached to a row.** The program draws its sidebar again
 * on every change (see the long note at the top of `arrange.js`), so the
 * controls are put on by `dress`, which looks again whenever the document
 * changes and does nothing to what is already dressed. Every press is heard
 * once, on the document.
 *
 * **Viewers get none of it**: only a rail carrying `data-arrange` (an editor's)
 * is ever dressed, and the server refuses every one of these writes to anybody
 * else whatever a page draws.
 *
 * Headings are saved through `arrange.js`'s own saver (`arrange-save`), the one
 * the Headings page and a drag already use, so the order, the program's copy
 * and the `unsaved` mark all stay true.
 */

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const say = (words, options) => (window.feel ? feel.toast(words, options) : null);

const svg = (paths, size = 12) => `<svg viewBox="0 0 16 16" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
const CHEVRON = svg('<path d="M4.2 6.2 8 10l3.8-3.8"/>', 10);
const PLUS = svg('<path d="M8 3.4v9.2"/><path d="M3.4 8h9.2"/>', 12);
const DOTS = svg('<circle cx="3.6" cy="8" r="0.9" fill="currentColor" stroke="none"/><circle cx="8" cy="8" r="0.9" fill="currentColor" stroke="none"/><circle cx="12.4" cy="8" r="0.9" fill="currentColor" stroke="none"/>', 14);

const tidy = (value) => String(value || "").replace(/\s+/g, " ").trim().slice(0, 40);
const MOST = 30;   // a film holds at most thirty categories (`MAX_SHELVES` in front.js)

/* ===========================================================================
   Which rail, which groups
   ========================================================================== */

const railOf = (el) => (el && el.closest ? el.closest("nav.rail[data-arrange]") : null);
const sectionsOf = (rail) => $(".sections", rail);
const groupsOf = (rail) => $$(":scope > .group[data-head]", sectionsOf(rail));
const namedGroups = (rail) => groupsOf(rail).filter((g) => g.dataset.head);
const headOf = (group) => {
  const before = group && group.previousElementSibling;
  return before && before.classList.contains("grouphead") ? before : null;
};
const groupOf = (head) => {
  const next = head && head.nextElementSibling;
  return next && next.classList.contains("group") ? next : null;
};

/* ===========================================================================
   Fold, remembered per film
   ========================================================================== */

const foldKey = (rail) => `fh-fold:${rail.dataset.base || location.pathname.split("/").slice(0, 3).join("/")}`;
function folds(rail) {
  try { return new Set(JSON.parse(localStorage.getItem(foldKey(rail)) || "[]")); } catch { return new Set(); }
}
function keepFolds(rail, set) {
  try { localStorage.setItem(foldKey(rail), JSON.stringify([...set])); } catch { /* a private window: it simply is not remembered */ }
}
function fold(head, shut) {
  const rail = railOf(head);
  const group = groupOf(head);
  if (!rail || !group) return;
  const set = folds(rail);
  const name = group.dataset.head;
  if (shut) set.add(name); else set.delete(name);
  keepFolds(rail, set);
  head.classList.toggle("closed", shut);
  group.classList.toggle("folded", shut);
  const button = $(".hfold", head);
  if (button) button.setAttribute("aria-expanded", String(!shut));
}

/* ===========================================================================
   Dressing: the controls, put on whatever the page has drawn
   ========================================================================== */

function control(tag, cls, html, label) {
  const el = document.createElement(tag);
  el.className = cls;
  el.innerHTML = html;
  if (tag === "button") el.type = "button";
  else el.setAttribute("role", "button");
  el.setAttribute("aria-label", label);
  el.setAttribute("data-tip", label);
  el.tabIndex = -1;
  return el;
}

function dressRail(rail) {
  const sections = sectionsOf(rail);
  if (!sections) return;
  const set = folds(rail);
  for (const head of $$(":scope > .grouphead", sections)) {
    const group = groupOf(head);
    if (!group) continue;
    const name = group.dataset.head || head.textContent.trim();
    if (!$(".hname", head)) {
      head.textContent = "";
      const label = document.createElement("span");
      label.className = "hname";
      label.textContent = name;
      head.append(
        control("button", "hfold", CHEVRON, "Fold"),
        label,
        control("button", "hplus", PLUS, `New in ${name}`),
        control("button", "hmore", DOTS, "Heading Menu"),
      );
    }
    const shut = set.has(name);
    head.classList.toggle("closed", shut);
    group.classList.toggle("folded", shut);
    const button = $(".hfold", head);
    if (button) button.setAttribute("aria-expanded", String(!shut));
  }
  for (const row of $$(".to[data-key]", sections)) {
    if (!$(".rowmore", row)) row.append(control("span", "rowmore", DOTS, "Menu"));
  }
  // **`+ New Heading`, last in the list.** The groups are moved with
  // `appendChild` by `arrange.js`, which would leave this above them; so it is
  // put back at the end every time the document changes.
  let add = $(":scope > .newhead", sections);
  if (!add) {
    add = document.createElement("button");
    add.type = "button";
    add.className = "newhead";
    add.innerHTML = `${PLUS}<span>New Heading</span>`;
  }
  // **Add Pages…, under it** (2026-10-11): pages that are not on the sidebar,
  // picked from a short list and put on in one go.
  let pick = $(":scope > .fh-addpages", sections);
  if (!pick) {
    pick = document.createElement("button");
    pick.type = "button";
    pick.className = "fh-addpages";
    pick.innerHTML = `${PLUS}<span>Add Pages…</span>`;
  }
  if (sections.lastElementChild !== pick || pick.previousElementSibling !== add) sections.append(add, pick);
  // **Edit, on a phone's sheet** (his pick, 2026-10-03,
  // `design/31-portal-quiet.html` 2): the + and ⋯ above stay hidden until it is
  // pressed, the way an iPhone list keeps its tools behind Edit. A desk never
  // draws it (`side.css`); there the tools come with the pointer.
  const foot = $(".railfoot", rail);
  if (foot && !$(":scope > .railedit", foot)) {
    const edit = document.createElement("button");
    edit.type = "button";
    edit.className = "railedit";
    edit.textContent = rail.classList.contains("editing") ? "Done" : "Edit";
    foot.prepend(edit);
  }
}

/** Into or out of Edit. Leaving it puts any open name field away too. */
function editing(rail, on) {
  rail.classList.toggle("editing", on);
  const edit = $(".railedit", rail);
  if (edit) { edit.textContent = on ? "Done" : "Edit"; edit.classList.toggle("on", on); }
}

let queued = false;
function dressAll() {
  queued = false;
  for (const rail of $$("nav.rail[data-arrange]")) dressRail(rail);
}
function later() {
  if (queued) return;
  queued = true;
  queueMicrotask(dressAll);
}
new MutationObserver(later).observe(document.body, { childList: true, subtree: true });
dressAll();

/* ===========================================================================
   A name changed where it is
   ========================================================================== */

/**
 * Put a text box where a name is. Enter keeps it, Escape puts the old name
 * back, and leaving the box keeps it too. `commit` may refuse (return false).
 */
function edit(target, { value, max = 40, commit, fresh = false }) {
  const input = document.createElement("input");
  input.type = "text";
  input.className = "inedit";
  input.value = value;
  input.maxLength = max;
  input.setAttribute("aria-label", "Name");
  input.autocomplete = "off";
  input.spellcheck = false;
  let over = false;
  const finish = async (keep) => {
    if (over) return;
    over = true;
    const said = keep ? input.value.replace(/\s+/g, " ").trim().slice(0, max) : "";
    let good = false;
    if (keep && said && (fresh || said !== value)) good = (await commit(said)) !== false;
    input.remove();
    target.hidden = false;
    if (good && target.isConnected && target.textContent !== said && !fresh) target.textContent = said;
  };
  input.addEventListener("keydown", (event) => {
    event.stopPropagation();
    if (event.key === "Enter" && !event.isComposing) { event.preventDefault(); finish(true); }
    else if (event.key === "Escape") { event.preventDefault(); finish(false); }
  });
  input.addEventListener("blur", () => finish(true));
  // A press in the box is the box's, not the row's or the page's.
  for (const type of ["click", "pointerdown", "mousedown", "dblclick"]) {
    input.addEventListener(type, (event) => { event.stopPropagation(); if (type === "click") event.preventDefault(); });
  }
  target.hidden = true;
  target.after(input);
  input.focus();
  input.select();
  return input;
}

/* ---- headings ------------------------------------------------------------ */

const save = (rail) => document.dispatchEvent(new CustomEvent("arrange-save", { detail: { rail } }));

function taken(rail, name, except) {
  const low = name.toLowerCase();
  return namedGroups(rail).some((g) => g !== except && g.dataset.head.toLowerCase() === low);
}

/**
 * **Ask the film to change a category** (`POST <film>/library`, `category`),
 * the same route the Library's own menus use, answered in JSON. The headings
 * are the categories (2026-10-11), so a heading is renamed, added or removed
 * here and never by sending a new name through the order, which would make a
 * second category instead of renaming the first. Answers the reply, or null.
 */
async function category(rail, fields) {
  const body = new FormData();
  for (const [k, v] of Object.entries(fields)) body.set(k, v);
  try {
    const got = await fetch(`${rail.dataset.base}/library`, {
      method: "POST", body, credentials: "same-origin", headers: { accept: "application/json" },
    });
    const said = await got.json().catch(() => null);
    return said || { ok: false, why: "" };
  } catch {
    return { ok: false, why: "" };
  }
}

/** Keep the program's copy of the categories in step (`HUB.rail.shelves`). */
function keepShelves(shelves) {
  if (window.HUB && HUB.rail && Array.isArray(shelves)) {
    HUB.rail.shelves = shelves.map((one) => ({ id: one.id, name: one.name, ...(one.builtIn ? { builtIn: true } : {}) }));
  }
  for (const rail of $$("nav.rail[data-shelves]")) if (Array.isArray(shelves)) rail.dataset.shelves = JSON.stringify(shelves.map((one) => one.name));
  if (window.seenOn) window.seenOn.changed();
}

function renameHead(head) {
  const rail = railOf(head);
  const group = groupOf(head);
  const label = $(".hname", head);
  if (!rail || !group || !label) return;
  edit(label, {
    value: group.dataset.head,
    commit: async (name) => {
      if (taken(rail, name, group)) { say("Already a Heading"); return false; }
      const before = group.dataset.head;
      if (group.dataset.shelf) {
        const said = await category(rail, { category: "rename", shelf: group.dataset.shelf, name });
        if (!said.ok) { say(said.why || "Could Not Rename"); return false; }
        keepShelves(said.shelves);
      }
      const set = folds(rail);
      if (set.delete(before)) { set.add(name); keepFolds(rail, set); }
      group.dataset.head = name;
      head.textContent = "";          // `dressRail` draws it again with the new name
      dressRail(rail);
      // A heading with no category behind it (an old page) still saves the old way.
      if (!group.dataset.shelf) save(rail);
      say("Renamed");
      return true;
    },
  });
}

/**
 * **Remove a heading: remove the category, if he added it.** The seven
 * starting categories stay (the server says so too). What stood under it goes
 * back where each page would be filed anyway, which only the server knows, so
 * the sidebar is drawn again from it. Undo makes the category again with the
 * same name and puts the same pages back under it, through the order.
 */
async function removeHead(head) {
  const rail = railOf(head);
  const group = groupOf(head);
  if (!rail || !group) return;
  const name = group.dataset.head;
  if (group.hasAttribute("data-builtin")) { say("The four starting categories can be renamed but not removed"); return; }
  const keys = $$(":scope > .to[data-key]", group).map((el) => el.dataset.key);
  if (!group.dataset.shelf) return;
  const said = await category(rail, { category: "remove", shelf: group.dataset.shelf });
  if (!said.ok) { say(said.why || "Could Not Remove"); return; }
  keepShelves(said.shelves);
  head.remove();
  group.remove();
  refresh();
  say("Heading Removed", {
    undo: async () => {
      const body = new URLSearchParams();
      body.append("group", `${name}\n${keys.map((k) => k.replace(/,/g, "%2C")).join(",")}`);
      try {
        await fetch(rail.dataset.arrange, { method: "POST", credentials: "same-origin", headers: { "content-type": "application/x-www-form-urlencoded" }, body });
      } catch { /* said by the redraw: the heading is not back */ }
      refresh();
    },
  });
}

/** A heading and its group, in the list at `place` among the named ones. */
function makeGroup(rail, name, place = Infinity) {
  const head = document.createElement("div");
  head.className = "grouphead";
  head.textContent = name;
  const group = document.createElement("div");
  group.className = "group";
  group.dataset.head = name;
  const named = namedGroups(rail);
  const before = place < named.length ? headOf(named[place]) || named[place] : groupsOf(rail).find((g) => !g.dataset.head) || null;
  const where = sectionsOf(rail);
  if (before) where.insertBefore(head, before); else where.append(head);
  head.after(group);
  return group;
}

function newHead(rail) {
  if (namedGroups(rail).length >= MOST) { say("Too Many Categories"); return; }
  const button = $(":scope > .newhead", sectionsOf(rail));
  if (!button) return;
  const label = document.createElement("span");
  label.className = "newname";
  button.hidden = true;
  button.after(label);
  const box = edit(label, {
    value: "",
    fresh: true,
    commit: async (name) => {
      if (taken(rail, name)) { say("Already a Heading"); return false; }
      // **A new heading is a new category** (2026-10-11), made on the film first.
      const said = await category(rail, { category: "add", name });
      if (!said.ok) { say(said.why || "Could Not Add"); return false; }
      keepShelves(said.shelves);
      const group = makeGroup(rail, name);
      if (said.id) group.dataset.shelf = said.id;
      dressRail(rail);
      return true;
    },
  });
  box.placeholder = "Heading";
  box.addEventListener("blur", () => { label.remove(); button.hidden = false; }, { once: true });
}

/** What a heading's ⋯ and a right click on it offer. */
function headItems(head) {
  const rail = railOf(head);
  const group = groupOf(head);
  const name = group ? group.dataset.head : "";
  return [
    { label: "New Page Here", run: () => window.addMenu && window.addMenu.open($(".hplus", head) || head, { head: name, side: "right" }) },
    { label: "Rename", run: () => renameHead(head) },
    "-",
    { label: "Remove", warn: true, run: () => removeHead(head) },
  ].filter((item) => item === "-" || rail);
}

/* ---- a document, renamed on the Documents page ---------------------------- */

document.addEventListener("click", (event) => {
  const button = event.target.closest && event.target.closest(".docrow .renamebtn");
  if (!button) return;
  const row = button.closest(".docrow");
  const name = row && $(".fh-doc b", row);
  const form = button.closest("form");
  if (!name || !form) return;
  event.preventDefault();
  edit(name, {
    value: name.textContent.trim(),
    max: 100,
    commit: async (said) => {
      form.elements.to.value = said;
      form.submit();
      return true;
    },
  });
});

/* ---- a page, renamed in its row or its card ------------------------------- */

function renameItem(el) {
  const card = el.classList.contains("fh-card");
  const target = card ? $("b", el) : $(".nm", el);
  const key = el.dataset.key;
  const rail = el.closest("nav.rail");
  const lib = card ? $(".fh-libpane") : null;
  const base = card ? (lib ? lib.dataset.lib.replace(/\/library$/, "") : "") : (rail && rail.dataset.base) || "";
  if (!target || !key || !base) return;
  const was = target.textContent.trim();
  // **A pinned file or link** (`doc:<name>`) is renamed through the Documents
  // route, and the page is drawn again since every list knows it by name.
  if (key.startsWith("doc:")) {
    edit(target, {
      value: was,
      max: 100,
      commit: async (name) => {
        const body = new FormData();
        body.set("rename_doc", key.slice(4));
        body.set("to", name);
        let got = null;
        try { got = await fetch(`${base}/documents`, { method: "POST", body, credentials: "same-origin" }); } catch { /* said below */ }
        if (!got || !got.ok) { say(got && got.status === 409 ? "That Name Is Taken" : "Could Not Rename"); return false; }
        say("Renamed");
        location.reload();
        return true;
      },
    });
    return;
  }
  edit(target, {
    value: was,
    max: 60,
    commit: async (name) => {
      const body = new FormData();
      body.set("rename", name);
      let got = null;
      try { got = await fetch(`${base}/${key}`, { method: "POST", body, credentials: "same-origin" }); } catch { /* said below */ }
      if (!got || !got.ok) { say("Could Not Rename"); return false; }
      for (const one of $$(`nav.rail .to[data-key="${CSS.escape(key)}"] .nm`)) one.textContent = name;
      for (const one of $$(`.fh-card[data-key="${CSS.escape(key)}"]`)) {
        one.dataset.name = name;
        const b = $("b", one);
        if (b) b.textContent = name;
      }
      const sections = window.HUB && HUB.rail && HUB.rail.sections;
      const mine = sections && sections.find((s) => s.at === key);
      if (mine) mine.name = name;
      if (window.seenOn) window.seenOn.changed();
      say("Renamed");
      // **The address follows the name** (the worker's rename): the answer
      // came from the page's new address, so the rows and, when this is the
      // page open, the address bar go there too, and the old one forwards.
      const at = got.redirected ? new URL(got.url).pathname.split("/").pop() : key;
      if (location.pathname.endsWith(`/${key}`)) {
        if (was && document.title.startsWith(`${was} · `)) document.title = name + document.title.slice(was.length);
        const head = $(".pagehead > h1");
        if (head && head.textContent.trim() === was) head.textContent = name;
        if (at && at !== key) {
          history.replaceState(history.state, "", `${location.pathname.slice(0, -key.length)}${at}${location.search}`);
        }
      }
      if (at && at !== key) refresh();
      return true;
    },
  });
}

/* ===========================================================================
   Keeping the list true after a change
   ========================================================================== */

/**
 * Draw the sidebar's rows again from the server. Used when something changes
 * that the page cannot work out for itself — a page put on the sidebar from
 * its Library card. `deep.js` hears `settingschanged`, throws away the pages
 * it kept and draws the rail again. Inside the program the rail is drawn by
 * `film.js`, so there it is a reload.
 */
function refresh() {
  if (document.getElementById("film")) { location.reload(); return; }
  document.dispatchEvent(new Event("settingschanged"));   // `deep.js` draws the rail again
}

/* ===========================================================================
   Add Pages: what is not on the sidebar, put on in one go
   ========================================================================== */

/**
 * **The panel** (his approved layout, 2026-10-11): a search, the categories
 * folded with how many pages each has that are not on the sidebar, a round
 * tick per page, and one button that says how many it will add. The list is
 * the film's (`GET <film>/library?part=pick`); adding pins them through the
 * Library's own bulk post, then the sidebar is drawn again.
 */
const CHEV = svg('<path d="M6 4.2 9.8 8 6 11.8"/>', 12);
async function addPages(anchor) {
  const rail = railOf(anchor) || $("nav.rail[data-arrange]");
  if (!rail || !window.feel) return;
  const base = rail.dataset.base;
  let data = null;
  try { data = await (await fetch(`${base}/library?part=pick`, { credentials: "same-origin" })).json(); } catch { /* said below */ }
  if (!data || !Array.isArray(data.pages)) { say("Could Not Load"); return; }
  const off = data.pages.filter((p) => !p.on);
  if (!off.length) { say("Every Page Is on the Sidebar"); return; }
  const picked = new Set();
  const opened = new Set();
  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; };
  const box = el("div", "fh-apbox");
  const find = el("input", "fx-pop-field fh-apfind");
  find.type = "search";
  find.placeholder = `Search ${off.length} ${off.length === 1 ? "page" : "pages"}`;
  find.setAttribute("aria-label", "Search Pages to Add");
  find.autocomplete = "off";
  const list = el("div", "fh-aplist");
  const foot = el("div", "fh-apfoot");
  const cancel = el("button", "fh-apbtn", "Cancel");
  cancel.type = "button";
  const go = el("button", "fh-apbtn fh-apgo", "Add 0 Pages");
  go.type = "button";
  go.disabled = true;
  foot.append(cancel, go);
  box.append(find, list, foot);
  const shelves = (data.shelves || []).map((one) => ({ ...one, rows: off.filter((p) => p.shelf === one.id) })).filter((one) => one.rows.length);
  const lone = off.filter((p) => !shelves.some((one) => one.id === p.shelf));
  if (lone.length) shelves.push({ id: "", name: "Other", rows: lone });
  if (shelves[0]) opened.add(shelves[0].id);

  const count = () => {
    const n = picked.size;
    go.textContent = `Add ${n} ${n === 1 ? "Page" : "Pages"}`;
    go.disabled = !n;
  };
  const draw = () => {
    const words = find.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const fits = (p) => words.every((w) => p.name.toLowerCase().includes(w));
    list.replaceChildren();
    let any = false;
    for (const one of shelves) {
      const rows = one.rows.filter(fits);
      if (!rows.length) continue;
      any = true;
      const open = words.length > 0 || opened.has(one.id);
      const head = el("button", "fh-aphead");
      head.type = "button";
      head.setAttribute("aria-expanded", String(open));
      head.append(el("b", "", one.name), el("span", "fh-apn", String(rows.length)));
      const chev = el("span", "fh-apchev");
      chev.innerHTML = CHEV;
      head.append(chev);
      head.addEventListener("click", () => { if (opened.has(one.id)) opened.delete(one.id); else opened.add(one.id); draw(); });
      list.append(head);
      if (!open) continue;
      for (const p of rows) {
        const row = el("button", "fh-aprow");
        row.type = "button";
        row.setAttribute("role", "checkbox");
        row.setAttribute("aria-checked", String(picked.has(p.at)));
        row.append(el("span", "fh-apname", p.name), el("i", "fh-apck"));
        row.addEventListener("click", () => {
          if (picked.has(p.at)) picked.delete(p.at); else picked.add(p.at);
          row.setAttribute("aria-checked", String(picked.has(p.at)));
          count();
        });
        list.append(row);
      }
    }
    if (!any) list.append(el("p", "fh-apnone", "No pages match"));
  };
  find.addEventListener("input", draw);
  draw();
  count();
  const handle = feel.phone()
    ? feel.sheet(box, { title: "Add Pages", className: "fh-apsheet" })
    : feel.pop(anchor, box, { side: "right", align: "end", className: "fh-appop", role: "dialog" });
  cancel.addEventListener("click", () => handle.close(true));
  go.addEventListener("click", async () => {
    const keys = [...picked];
    go.disabled = true;
    const good = window.seenOn ? await window.seenOn.post(base, "pin", keys) : false;
    if (!good) { go.disabled = false; say("Could Not Save"); return; }
    handle.close();
    say(`${keys.length} ${keys.length === 1 ? "Page" : "Pages"} Added`);
    refresh();
  });
  if (!feel.phone()) find.focus({ preventScroll: true });
}

window.sidebar = { rename: renameItem, headItems, refresh, addPages };

/* ===========================================================================
   One listener each, on the document
   ========================================================================== */

const PHONE = "(max-width:700px), (max-height:480px) and (pointer:coarse)";
const hit = (event, sel) => (event.target instanceof Element ? event.target.closest(sel) : null);
const stop = (event) => { event.preventDefault(); event.stopPropagation(); };

document.addEventListener("click", (event) => {
  const foldBtn = hit(event, ".hfold");
  if (foldBtn) { stop(event); const head = foldBtn.closest(".grouphead"); fold(head, !head.classList.contains("closed")); return; }

  // The whole heading name folds it, not only the arrow. A double-click is
  // left alone so it can still rename.
  const nameBtn = hit(event, ".grouphead .hname");
  if (nameBtn && !nameBtn.closest(".inedit") && !nameBtn.querySelector("input,textarea") && event.detail < 2) {
    const head = nameBtn.closest(".grouphead");
    if (railOf(head)) { stop(event); fold(head, !head.classList.contains("closed")); return; }
  }

  const plus = hit(event, ".hplus");
  if (plus) {
    stop(event);
    const head = plus.closest(".grouphead");
    const group = groupOf(head);
    if (window.addMenu) window.addMenu.open(plus, { head: group ? group.dataset.head : "", side: "right" });
    return;
  }

  const more = hit(event, ".hmore");
  if (more && window.portalMenu) {
    stop(event);
    const box = more.getBoundingClientRect();
    window.portalMenu.show(box.right + 6, box.top - 4, headItems(more.closest(".grouphead")));
    return;
  }

  const row = hit(event, ".rowmore");
  if (row && window.portalMenu) {
    stop(event);
    const item = row.closest(".to");
    const box = row.getBoundingClientRect();
    window.portalMenu.show(box.right + 6, box.top - 4, window.portalMenu.forRow(item));
    return;
  }

  if (hit(event, ".newhead")) { stop(event); newHead(railOf(hit(event, ".newhead"))); return; }
  if (hit(event, ".fh-addpages")) { stop(event); addPages(hit(event, ".fh-addpages")); return; }

  const edit = hit(event, ".railedit");
  if (edit) { stop(event); const rail = edit.closest("nav.rail"); editing(rail, !rail.classList.contains("editing")); return; }
  // A sheet opened again starts out of Edit.
  if (hit(event, '[data-sheet="open"]:not([data-only])')) for (const rail of $$("nav.rail")) { editing(rail, false); rail.classList.remove("scopeopen", "only"); }

  const add = hit(event, "[data-add]");
  if (add && window.addMenu) { stop(event); window.addMenu.open(add, { head: "", side: "top" }); return; }

  const find = hit(event, ".railfind");
  if (find) {
    stop(event);
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "k", metaKey: true, ctrlKey: true, bubbles: true, cancelable: true }));
    return;
  }

  // The film's menu (Updated, Refresh) shuts when anything else is pressed.
  for (const menu of $$("details.filmmenu[open]")) if (!menu.contains(event.target)) menu.open = false;
}, true);

document.addEventListener("dblclick", (event) => {
  const name = hit(event, ".grouphead .hname");
  if (!name) return;
  const head = name.closest(".grouphead");
  if (!railOf(head)) return;
  stop(event);
  renameHead(head);
}, true);

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") for (const menu of $$("details.filmmenu[open]")) menu.open = false;
});

// A save that did not take is said, not left as a quiet mark.
document.addEventListener("arranged", () => {
  if ($("nav.rail[data-arrange].unsaved")) say("Could Not Save");
});

// The key shown on Find is the one this machine has. (Only written when it
// differs: writing the same text is still a change, and this watches changes.)
const keyed = () => {
  if (!window.feel) return;
  for (const kbd of $$(".railfind kbd")) {
    const want = feel.keyed("⌘K");
    if (kbd.textContent !== want) kbd.textContent = want;
  }
};
keyed();
new MutationObserver(keyed).observe(document.body, { childList: true, subtree: true });

/* Heard in the capture phase, so the row's own link, `deep.js` and the sheet's
   close-on-go never see the tap. */
document.addEventListener("click", (event) => {
  // **On a phone's sheet the page you are on folds its own list away** (his
  // report, 2026-10-03: the sheet was "a barrage of info"). Tapping the row you
  // are already on opens it, the way a folder opens, instead of reloading it.
  // **A page's own Scenes (or All Locations) button**: the sheet opens with
  // only that list in it, full height. `rail.js` opens the sheet as usual.
  const only = hit(event, "[data-only]");
  if (only) {
    const rail = (only.closest(".fh2") || document).querySelector("nav.rail");
    if (rail) {
      rail.classList.add("scopeopen", "only");
      const top = $(".railtop", rail);
      if (top) top.dataset.only = only.dataset.only;
    }
    return;
  }
  const here = hit(event, "nav.rail .to.on");
  if (here && window.matchMedia(PHONE).matches && here.parentElement.querySelector(":scope > .wellwrap")) {
    stop(event);
    here.closest("nav.rail").classList.toggle("scopeopen");
    return;
  }
}, true);
