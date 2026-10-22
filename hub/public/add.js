/**
 * **The Add screen's two live answers.** Ref 872.
 *
 * The form works with nothing running — it is a plain POST, and the worker
 * decides everything. These two are what a script can add and a server cannot:
 *
 * - **The address, as he types the name.** His question, 2026-09-08, was why
 *   `Visual Bible`, `Bible` and `Visual Language Bible` all silently land on
 *   the film's existing bible, and why `People` is refused outright — none of
 *   which is written anywhere he would ever see. Showing the address he is
 *   about to make turns a collision into something he *sees* before pressing
 *   Add, rather than something the next screen tells him about.
 * - **Only the questions this type asks.** A deck asks nothing after the type;
 *   a file asks for the file; only a written page has a real choice about where
 *   its words come from. Everything else is put away rather than greyed out.
 *
 * With no script both simply do not happen: every question is shown and the
 * address is not. Nothing is lost that the next screen will not say.
 */

/**
 * A name a URL can carry, out of a name a person reads.
 *
 * **`slugFrom` in `src/paper.js` is the same six lines**, and the worker makes
 * the real address with that one. If these two ever disagree, this screen
 * promises an address the film does not get — so change both together.
 */
function slugFrom(name) {
  const said = String(name || "")
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
    .replace(/-+$/g, "");
  return /^[a-z0-9][a-z0-9-]*$/.test(said) ? said : "";
}

/**
 * **Dressed wherever the form turns up.** Add is landed in place now
 * (`deep.js`, 2026-10-02) rather than loaded, so this file is already running
 * when its form arrives — it looks again on every swap, and marks the form so
 * it is never wired twice.
 */
function dress() {
  const form = document.querySelector(".addform");
  if (!form || form.dataset.dressed) return;
  form.dataset.dressed = "1";
  const field = form.querySelector(".namefield");
  const line = form.querySelector(".fh-addr");
  const slug = line && line.querySelector("b");

  const address = () => {
    if (!field || !line || !slug) return;
    const said = slugFrom(field.value);
    slug.textContent = said;
    line.classList.toggle("off", !said);
  };

  const asked = () => {
    const picked = form.querySelector('input[name="type"]:checked');
    const type = picked ? picked.value : "page";
    for (const el of form.querySelectorAll("[data-only]")) {
      // **A list of types, not one.** The address belongs to a page and to a
      // deck alike; a file is not an address on this film at all.
      el.classList.toggle("off", !el.dataset.only.split(" ").includes(type));
    }
  };

  if (field) field.addEventListener("input", address);
  form.addEventListener("change", (event) => {
    if (event.target && event.target.name === "type") asked();
  });

  asked();
  address();
}

dress();
document.addEventListener("swapped", dress);

/* ===========================================================================
   Add is a menu, not a form (move 2 of design/29-portal-details)

   The + at the foot of the sidebar, and the + on a heading, open this where
   they stand: a name field that is already focused, then the five things a
   film can be given. Enter picks the one that is lit; the arrow keys move it;
   a pasted web address lights Link by itself. From a heading it says `Add to
   <Heading>` and the new page lands under it. The Built In pages sit under a
   rule, each with a neutral switch for whether it is on the sidebar.

   It posts to the same `/add` the old page posts to, asking for JSON, so the
   menu can say why not and stay where it is. The old page at `/add` is still
   there for anyone who lands on it, and for a browser with no script.

   Dropping a file on the sidebar adds it as a File by the same post.
   =========================================================================== */

const KINDS = [
  { kind: "page", name: "Written Page", hint: "" },
  { kind: "deck", name: "Deck", hint: "" },
  { kind: "board", name: "Board", hint: "" },
  { kind: "file", name: "File", hint: "or drop one", phoneHint: "Photos or Files" },
  { kind: "link", name: "Link", hint: "or paste one" },
];

/** Whether a line is a web address: one that starts https://, or a bare www. one. */
const addressOf = (value) => {
  const said = String(value || "").trim();
  if (/^https?:\/\/\S+$/i.test(said)) return said;
  if (/^www\.\S+\.\S+$/i.test(said)) return `https://${said}`;
  return "";
};
const hostName = (address) => {
  try { return new URL(address).hostname.replace(/^www\./, ""); } catch { return "Link"; }
};
const stemOf = (name) => String(name || "File").replace(/\.[^.]+$/, "").replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 60) || "File";

/** Ask the worker to add something. Resolves `{ ok, href }` or `{ ok: false, error }`. */
async function sendAdd(base, fields) {
  const body = new FormData();
  for (const [key, value] of Object.entries(fields)) if (value != null && value !== "") body.set(key, value);
  try {
    const got = await fetch(`${base}/add`, { method: "POST", body, credentials: "same-origin", headers: { accept: "application/json" } });
    const data = await got.json().catch(() => null);
    if (got.ok && data && data.ok) { if (window.seenOn) window.seenOn.changed(); return data; }
    return { ok: false, error: (data && data.error) || (got.status === 403 ? "That is not yours to add" : "Could not add that") };
  } catch {
    return { ok: false, error: "Could not add that" };
  }
}

/** Go to a page of the film the way a press on a link would. */
function goTo(href) {
  const link = document.createElement("a");
  link.href = href;
  link.dataset.deep = "record";
  link.style.display = "none";
  document.body.append(link);
  link.click();
  link.remove();
}

let addOpen = null;

function openAdd(anchor, options = {}) {
  if (addOpen) {
    const same = addOpen.anchor === anchor;
    addOpen.handle.close();
    if (same) return;
  }
  // **From the phone's sheets the rail is not an ancestor** (the dock, a page's
  // own button), so the film's rail is found where it stands.
  const rail = anchor.closest("nav.rail") || document.querySelector("nav.rail");
  if (!rail || !window.feel) return;
  // **On a phone Add is a bottom sheet** (move 3 of design/30-portal-phone):
  // the same fields and rows, drawn in `feel.sheet`, with a head and a close
  // button, 44px rows, and the picker offering Photos, Camera and Files.
  const onPhone = feel.phone();
  const base = rail.dataset.base || "";
  const head = options.head || "";
  let built = [];
  try { built = JSON.parse(rail.dataset.built || "[]"); } catch { built = []; }

  const el = (tag, cls, text) => { const n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; };
  const box = el("div", "addbox");
  const field = el("input", "fx-pop-field");
  field.type = "text";
  field.placeholder = "Name or paste a link";
  field.autocomplete = "off";
  field.spellcheck = false;
  field.maxLength = 1200;
  field.setAttribute("aria-label", "Name or paste a link");
  const err = el("div", "addbox-err");
  err.hidden = true;
  const title = head ? `Add to ${head}` : "Add";
  const label = el("div", "fx-pop-sec", title);
  const picker = el("input");
  picker.type = "file";
  picker.hidden = true;
  picker.setAttribute("aria-label", "Photos or Files");
  if (onPhone) box.append(field, err); else box.append(field, err, label);

  let at = 0;
  let step = "name";       // "link" once a Link has been asked for without an address
  let named = "";
  let changed = false;
  let busy = false;
  const items = KINDS.map((k, i) => {
    const row = el("button", "fx-pop-item addkind");
    row.type = "button";
    row.dataset.kind = k.kind;
    row.setAttribute("role", "menuitem");
    row.append(el("span", `kindmark ${k.kind}`), el("span", "", k.name));
    const hint = onPhone && k.phoneHint ? k.phoneHint : k.hint;
    if (hint) row.append(el("small", "", hint));
    row.append(el("span", "fx-pop-key", "↵"));
    row.addEventListener("pointerenter", () => lit(i));
    row.addEventListener("click", () => pick(k.kind));
    box.append(row);
    return row;
  });
  function lit(i) {
    at = (i + KINDS.length) % KINDS.length;
    items.forEach((row, n) => row.classList.toggle("on", n === at));
  }
  lit(0);

  // The Built In pages, each with a neutral switch.
  if (built.length) {
    if (!onPhone) box.append(el("div", "fx-pop-sep"));
    box.append(el("div", "fx-pop-sec", "Built In"));
    for (const page of built) {
      const row = el("button", "fx-pop-item addbuilt");
      row.type = "button";
      row.dataset.at = page.at;
      const sw = el("span", `fx-sw${page.on ? " on" : ""}`);
      row.append(el("span", "", page.name), el("small", "", page.state || ""), sw);
      row.setAttribute("role", "menuitemcheckbox");
      row.setAttribute("aria-checked", String(page.on));
      row.addEventListener("click", async () => {
        const want = !page.on;
        page.on = want;
        sw.classList.toggle("on", want);
        row.setAttribute("aria-checked", String(want));
        const good = await window.seenOn.post(base, want ? "sidebar-on" : "sidebar-off", [page.at]);
        if (!good) {
          page.on = !want;
          sw.classList.toggle("on", !want);
          row.setAttribute("aria-checked", String(!want));
          feel.toast("Could Not Save");
          return;
        }
        changed = true;
        feel.toast("Saved");
      });
      box.append(row);
    }
  }
  box.append(picker);

  // The sheet's head names it; a popover has the small section line instead.
  const setTitle = (words) => { label.textContent = words; if (onPhone && handle.title) handle.title.textContent = words; };
  const problem = (words) => { err.textContent = words; err.hidden = !words; handle.place(); };

  async function send(fields) {
    if (busy) return;
    busy = true;
    problem("");
    const got = await sendAdd(base, { ...fields, head });
    busy = false;
    if (!got.ok) { problem(got.error); return; }
    handle.close();
    feel.toast("Added");
    goTo(got.href);
  }

  function pick(kind) {
    const raw = field.value.trim();
    if (kind === "file") {
      picker.value = "";
      picker.click();
      return;
    }
    if (kind === "link") {
      const address = addressOf(raw);
      if (step === "name" && !address) {
        // A name first, then the address it points to.
        named = raw;
        step = "link";
        field.value = "";
        field.placeholder = "Paste a link";
        setTitle(named ? `Link · ${named}` : "Link");
        field.focus();
        return;
      }
      if (!address) { problem("That is not a web address"); return; }
      send({ type: "link", name: step === "link" && named ? named : hostName(address), url: address });
      return;
    }
    if (!raw) { shake(field); field.focus(); return; }
    send({ type: kind, name: raw });
  }

  picker.addEventListener("change", () => {
    const file = picker.files && picker.files[0];
    if (file) send({ type: "file", name: field.value.trim() || stemOf(file.name), file });
  });

  field.addEventListener("input", () => {
    problem("");
    // A pasted address lights Link by itself.
    if (step === "name" && addressOf(field.value)) lit(KINDS.findIndex((k) => k.kind === "link"));
  });
  field.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown") { event.preventDefault(); lit(at + 1); }
    else if (event.key === "ArrowUp") { event.preventDefault(); lit(at - 1); }
    else if (event.key === "Enter" && !event.isComposing) { event.preventDefault(); pick(step === "link" ? "link" : KINDS[at].kind); }
  });

  const closed = () => {
    addOpen = null;
    if (changed && window.sidebar) window.sidebar.refresh();
  };
  const handle = onPhone
    ? feel.sheet(box, { title, className: "addsheet", focus: field, onClose: closed })
    : feel.pop(anchor, box, {
        side: options.side || "top",
        align: "start",
        className: "addpop",
        role: "dialog",
        onClose: closed,
      });
  addOpen = { anchor, handle };
  field.focus();
}

function shake(node) {
  node.classList.remove("shake");
  void node.offsetWidth;
  node.classList.add("shake");
}

window.addMenu = { open: openAdd };

/* ---- dropping a file on the sidebar ------------------------------------ */

const hasFiles = (event) => event.dataTransfer && [...(event.dataTransfer.types || [])].includes("Files");
const railUnder = (event) => (event.target instanceof Element ? event.target.closest("nav.rail[data-arrange]") : null);

document.addEventListener("dragover", (event) => {
  const rail = railUnder(event);
  if (!rail || !hasFiles(event)) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = "copy";
  rail.classList.add("dropping");
});
document.addEventListener("dragleave", (event) => {
  const rail = railUnder(event);
  if (rail && !rail.contains(event.relatedTarget)) rail.classList.remove("dropping");
});
document.addEventListener("drop", async (event) => {
  const rail = railUnder(event);
  if (!rail || !hasFiles(event)) return;
  event.preventDefault();
  rail.classList.remove("dropping");
  const files = [...event.dataTransfer.files].slice(0, 8);
  const base = rail.dataset.base || "";
  let good = 0;
  let why = "";
  for (const file of files) {
    const got = await sendAdd(base, { type: "file", name: stemOf(file.name), file });
    if (got.ok) good += 1; else why = got.error;
  }
  if (!good) { feel.toast(why || "Could Not Add"); return; }
  if (why) feel.toast(why);
  else feel.toast("Added");
  if (document.getElementById("film")) { feel.later("Added"); location.reload(); }
  else if (window.sidebar) window.sidebar.refresh();
});
