/**
 * Jump — ⌘K, or `/`, and a box that goes anywhere.
 *
 * His pick of 2026-09-23 (Ref 1161, item 2): the shelf's search already finds
 * a film; this finds a film from anywhere, and a page inside the film you are
 * on — the Camera Spec Sheet, a scene, a location.
 *
 * **Nothing new to know.** What it offers is what is already on the screen or
 * already his: the film's pages are read off the rail (so a page Visibility
 * hides from a reader is not offered to them either — it was never drawn),
 * the scenes, places and boards come from the program when it is open
 * (`window.shotlisterJump` in `film.js`), and his films come from
 * `/films.json`, which is the shelf's own list and nothing more.
 *
 * **Going somewhere is pressing the thing.** A page row is clicked, so
 * `deep.js` moves the way it always moves; a scene is opened the way the
 * rail's list opens one.
 */
const OPEN_KEY = (e) => (e.metaKey || e.ctrlKey) && !e.altKey && !e.shiftKey && e.key.toLowerCase() === "k";

let box = null;
let films = null;
let shown = [];
let at = 0;

function typing(el) {
  return el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || el.isContentEditable);
}

document.addEventListener("keydown", (e) => {
  if (e.defaultPrevented) return;
  if (OPEN_KEY(e)) {
    e.preventDefault();
    if (box) shut(); else open();
    return;
  }
  // **`/` is the shelf's own search on the shelf**, as it was before this.
  if (e.key === "/" && !e.metaKey && !e.ctrlKey && !e.altKey && !typing(document.activeElement)
      && !document.querySelector("[data-shelffind]") && !document.querySelector(".shroud") && !document.querySelector(".fx-pop.sp")) {
    e.preventDefault();
    open();
  }
});

/** The rail on screen: the program's when it is open, the page's otherwise. */
function rail() {
  const all = [...document.querySelectorAll("nav.rail")].filter((r) => r.getClientRects().length);
  return all.find((r) => r.closest("#film")) || all[0] || null;
}

function pages() {
  const here = rail();
  if (!here) return [];
  const out = [];
  const seen = new Set();
  const add = (el, name, kind = "Page") => {
    const said = String(name || "").trim();
    if (!said || seen.has(said.toLowerCase())) return;
    seen.add(said.toLowerCase());
    out.push({ kind, name: said, go: () => el.click() });
  };
  const home = here.querySelector(".fh-who");
  if (home) add(home, `${home.textContent.trim()}`, "Film");
  for (const row of here.querySelectorAll(".sections .to")) {
    // The row's words without its count, its tag or its ⋯.
    const named = row.querySelector(".nm");
    if (named) { add(row, named.textContent); continue; }
    const count = row.querySelector(".n, .nc");
    add(row, count ? row.textContent.replace(count.textContent, "") : row.textContent);
  }
  for (const tool of here.querySelectorAll(".railtool")) add(tool, tool.textContent, "Tool");
  return out;
}

async function filmsList() {
  if (films) return films;
  try {
    const got = await fetch("/films.json", { credentials: "same-origin" });
    films = got.ok ? (await got.json()).films || [] : [];
  } catch {
    films = [];
  }
  return films;
}

function everything() {
  const inFilm = typeof window.shotlisterJump === "function" && document.querySelector("#film")
    ? window.shotlisterJump() : [];
  const others = (films || []).map((f) => ({ kind: "Project", name: f.title, go: () => { location.href = f.base; } }));
  return [...pages(), ...inFilm, ...others];
}

function open() {
  box = document.createElement("div");
  // **`.shroud` for the portal's dark tokens and its arrival**, the same
  // overlay the Share panel stands on.
  box.className = "shroud jumpshroud";
  box.innerHTML = `<div class="jumpcard" role="dialog" aria-modal="true" aria-label="Jump">
    <input class="jumpfind" type="search" placeholder="Jump to a page, scene or project" autocomplete="off" spellcheck="false" aria-label="Jump to">
    <div class="jumplist" role="listbox"></div>
  </div>`;
  document.body.appendChild(box);
  const find = box.querySelector(".jumpfind");
  box.addEventListener("mousedown", (e) => { if (e.target === box) shut(); });
  find.addEventListener("input", () => { at = 0; draw(); });
  find.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { e.preventDefault(); shut(); return; }
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      at = Math.max(0, Math.min(shown.length - 1, at + (e.key === "ArrowDown" ? 1 : -1)));
      draw(false);
      return;
    }
    if (e.key === "Enter") {
      e.preventDefault();
      go(shown[at]);
    }
  });
  box.querySelector(".jumplist").addEventListener("click", (e) => {
    const row = e.target.closest("[data-i]");
    if (row) go(shown[Number(row.dataset.i)]);
  });
  at = 0;
  draw();
  find.focus();
  filmsList().then(() => { if (box) draw(false); });
}

function shut() {
  if (!box) return;
  box.remove();
  box = null;
}

function go(item) {
  if (!item) return;
  shut();
  item.go();
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function draw(fresh = true) {
  if (!box) return;
  const said = box.querySelector(".jumpfind").value.trim().toLowerCase();
  const words = said.split(/\s+/).filter(Boolean);
  const all = everything();
  // **Pages and projects before scenes when nothing is typed** — forty scenes
  // should not push the film's own pages off the list before he has asked.
  // **A name that is what he typed comes first**, then one that starts with
  // it, then the rest in their natural order — `House` is the location called
  // House before it is scene 3 at Mary & Larry's house.
  const rank = (one) => {
    const name = one.name.toLowerCase();
    return name === said ? 0 : name.startsWith(said) ? 1 : 2;
  };
  shown = (words.length
    ? all.filter((one) => words.every((w) => `${one.name} ${one.kind}`.toLowerCase().includes(w)))
      .map((one, i) => ({ one, i })).sort((a, b) => rank(a.one) - rank(b.one) || a.i - b.i).map((x) => x.one)
    : all.filter((one) => one.kind !== "Scene" && one.kind !== "Location" && one.kind !== "Reference Images"))
    .slice(0, 60);
  if (at >= shown.length) at = Math.max(0, shown.length - 1);
  const list = box.querySelector(".jumplist");
  list.innerHTML = shown.length
    ? shown.map((one, i) => `<button type="button" class="jumprow${i === at ? " on" : ""}" data-i="${i}" role="option" aria-selected="${i === at}">
        <span class="jn">${esc(one.name)}</span><span class="jk">${esc(one.kind)}</span></button>`).join("")
    : `<p class="jumpnone">Nothing matches</p>`;
  const on = list.querySelector(".jumprow.on");
  if (on && !fresh) on.scrollIntoView({ block: "nearest" });
}
