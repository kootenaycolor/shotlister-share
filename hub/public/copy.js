// Click a value, take it with you.
//
// **The one thing a published Notion page does that a web page does not.** His
// point, 2026-09-02: on a camera spec sheet he can copy a frame rate, a LUT
// name, a phone number, straight off the page. A page you have to select text
// on with a mouse, on a phone, standing on a street, is a worse page than the
// one he is leaving behind — so this has to come with the move, not after it.
//
// Anything carrying `data-copy` is copyable. The attribute holds the exact text
// to copy when that is not what is drawn; otherwise what is drawn is what is
// taken.
//
// **It brings its own style.** `hub.css` is being edited by another thread, and
// a few rules that only this file uses do not belong in the shared stylesheet
// anyway.
const style = document.createElement("style");
style.textContent = `
  [data-copy] { cursor: pointer; position: relative; }
  [data-copy]:hover { text-decoration: underline; text-underline-offset: 3px; text-decoration-style: dotted; }
  [data-copy]:focus-visible { outline: 2px solid currentColor; outline-offset: 2px; border-radius: 2px; }
  [data-copy].took::after {
    content: "Copied";
    position: absolute; left: 0; top: -1.5em;
    font-size: 11px; letter-spacing: .04em; text-transform: uppercase;
    padding: 2px 6px; border-radius: 3px;
    background: currentColor; color: canvas; opacity: .85;
    pointer-events: none; white-space: nowrap;
  }
`;
document.head.appendChild(style);

async function take(node) {
  const text = (node.getAttribute("data-copy") || node.textContent || "").trim();
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    // **A refusal must not look like a success.** The clipboard is denied
    // outright in some browsers without a gesture it recognises, so fall back
    // to the old way rather than flashing "Copied" over nothing.
    const hidden = document.createElement("textarea");
    hidden.value = text;
    hidden.setAttribute("readonly", "");
    hidden.style.position = "fixed";
    hidden.style.opacity = "0";
    document.body.appendChild(hidden);
    hidden.select();
    let done = false;
    try { done = document.execCommand("copy"); } catch { done = false; }
    hidden.remove();
    if (!done) return;
  }
  // **Said in the shared pill** (`feel.js`); the little badge on the value
  // itself is only the fallback when that is not there.
  if (window.feel) { window.feel.toast("Copied"); return; }
  node.classList.add("took");
  clearTimeout(node.__took);
  node.__took = setTimeout(() => node.classList.remove("took"), 1200);
}

document.addEventListener("click", (event) => {
  const node = event.target.closest("[data-copy]");
  if (!node) return;
  // A crew address is a `mailto:` and a number a `tel:` — for an editor those
  // are the point of the screen, so a plain click still calls or writes. Copying
  // is the modifier, which is what a browser does with a link anyway.
  if (node.closest("a") && !event.altKey) return;
  // **A link inside a copyable row is a link** (2026-10-14): the LUTs row
  // copies as a whole, and the file name in it opens that file in a new tab.
  // The click on the link goes to the link; a click anywhere else on the row
  // still copies it.
  const inside = event.target.closest("a[href]");
  if (inside && inside !== node && node.contains(inside) && !event.altKey) return;
  // **A drag across the words is a selection, not a press.** His ask,
  // 2026-09-10: a whole spec sheet row copies, and the words on it can still
  // be picked out with the mouse. A click that ends a selection inside the
  // row is left alone, so ⌘C takes what was selected rather than the row.
  const picked = window.getSelection();
  if (picked && !picked.isCollapsed && node.contains(picked.anchorNode)) return;
  event.preventDefault();
  take(node);
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" && event.key !== " ") return;
  const node = event.target.closest?.("[data-copy]");
  if (!node || node.closest("a")) return;
  event.preventDefault();
  take(node);
});

function dress() {
  for (const node of document.querySelectorAll("[data-copy]")) {
    if (node.closest("a")) continue;
    // A real button already is one, already reaches the keyboard, and already
    // says what it copies. Dressing it up again overwrites a better label.
    if (node.tagName === "BUTTON") continue;
    node.setAttribute("role", "button");
    node.setAttribute("tabindex", "0");
    // A row that already says what it copies keeps its own words.
    if (!node.hasAttribute("title")) node.setAttribute("title", "Click to copy");
  }
}

dress();
// `deep.js` swaps a whole page in without the document ever reloading, so
// everything below is new and has never been dressed. The taking itself is
// delegated at the document and needs no telling.
document.addEventListener("swapped", dress);
