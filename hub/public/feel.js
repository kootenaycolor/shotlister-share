/**
 * **The feel of the portal, in one small file every page loads.**
 *
 * Moves 7 and 8 of `design/29-portal-details.src.html`: the pieces that are the
 * same on every page, so the pages that come after inherit them instead of
 * each making their own. The look is in `feel.css`; its head lists the class
 * names. This file is the behaviour:
 *
 *   feel.toast("Saved")                       a pill at the bottom that leaves by itself
 *   feel.toast("Archived", { undo: fn })      …with an Undo button (fn may be async)
 *   feel.toast("Archived", { undoPost })      …whose Undo posts a form: { url, fields }
 *   feel.later("Archived", { undoPost })      …said by the NEXT page (for an action that reloads)
 *   feel.copy(text, "Link Copied")            copy, then say so (and say so only if it worked)
 *   feel.pop(anchor, content, options)        a popover opening from the thing clicked
 *   feel.tint(element)                        the film's colour as that element sees it
 *   feel.phone()                              is this a phone? (the one breakpoint every phone rule uses)
 *   feel.sheet(content, options)              a bottom sheet: the phone's popover (see below)
 *
 * **The phone's popover is `feel.sheet`, not a second copy of each panel.**
 * Callers pick: `feel.phone() ? feel.sheet(box, opts) : feel.pop(anchor, box, opts)`.
 * `content` is a node or an HTML string. Options: `title` (a heading bar with
 * a close button; leave it out to draw your own head), `label` (aria-label),
 * `className`, `focus` (a selector or node to focus first; default the first
 * field; `false` focuses the sheet itself so no keyboard opens), `onClose`. It returns `{ el, body, title, place, close }`, where
 * `place` does nothing (kept so a caller can treat it like a popover's handle)
 * and `close(returnFocus)` shuts it. A grab handle at the top, a scrim, Escape,
 * a press on the scrim or a drag down on the handle or head all close it; the
 * sheet rides above the keyboard; Tab stays inside it; focus goes back to
 * where it was. Its look is `.fx-sheet*` in `feel.css`; put `data-sheet-drag`
 * on any element of your own that should drag the sheet down too.
 *
 * and, with nothing to call:
 *
 *   • every <img> keeps its box, wears a neutral placeholder, and fades up from
 *     a slight blur a beat after the one before (opt out: data-fx="off");
 *   • every title="…" becomes the shared tooltip (data-tip), carrying the key
 *     where one exists (data-key="⌘K"); no browser bubble.
 *
 * **Plain script, no imports**, loaded `defer` in the head beside `wait.js`, so
 * it is there before any module on the page runs.
 */
(() => {
  if (window.feel) return;

  const mac = /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent || "");
  /** ⌘K on a Mac, Ctrl+K elsewhere. */
  const keyed = (text) => (mac ? text : String(text).replace(/⌘/g, "Ctrl+").replace(/⌥/g, "Alt+"));
  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = text;
    return node;
  };

  /* =========================================================================
     The film's colour
     ========================================================================= */
  function tint(from) {
    const read = (node) => node && getComputedStyle(node).getPropertyValue("--accent").trim();
    const own = from && from.closest ? from.closest("[style*='--accent']") : null;
    return read(own) || read(document.querySelector(".fh2")) || "#7DA4FF";
  }

  /* =========================================================================
     The confirmation pill
     ========================================================================= */
  let pill = null;
  let pillTimer = 0;
  let pillOpen = null;

  function closePill() {
    clearTimeout(pillTimer);
    pillOpen = null;
    if (pill) pill.classList.remove("on");
  }

  /** Undo by posting a form (or several, in order): `{ url, fields }`, then the page reloads to show it. */
  async function postUndo(spec) {
    const list = Array.isArray(spec) ? spec : [spec];
    for (const one of list) {
      const body = new FormData();
      for (const [name, value] of Object.entries(one.fields || {})) body.set(name, value);
      const got = await fetch(one.url, { method: "POST", body, credentials: "same-origin" });
      if (!got.ok) throw new Error(String(got.status));
    }
    if (!list.length || list[list.length - 1].reload !== false) { later("Undone"); location.reload(); return false; }
    return true;
  }

  /**
   * Say something small. `text` is a label, not a sentence: "Link Copied",
   * "Saved", "Archived". With `undo` (a function) or `undoPost` ({ url, fields })
   * it carries an Undo button and stays a little longer.
   */
  function toast(text, options = {}) {
    const o = typeof options === "function" ? { undo: options } : options || {};
    if (!pill || !pill.isConnected) {
      pill = el("div", "fx-toast");
      pill.setAttribute("role", "status");
      pill.setAttribute("aria-live", "polite");
      pill.addEventListener("pointerenter", () => clearTimeout(pillTimer));
      pill.addEventListener("pointerleave", () => { if (pillOpen) pillTimer = setTimeout(closePill, 1600); });
      document.body.append(pill);
    }
    const mine = (pillOpen = {});
    pill.replaceChildren(el("span", "", text));
    const undo = o.undo || (o.undoPost ? () => postUndo(o.undoPost) : null);
    if (undo) {
      const button = el("button", "", "Undo");
      button.type = "button";
      button.addEventListener("click", async () => {
        if (pillOpen !== mine) return;
        closePill();
        try {
          const result = await undo();
          if (result !== false) toast("Undone");
        } catch {
          toast("Could Not Undo");
        }
      });
      pill.append(button);
    }
    // Forced reflow so a pill that is already up animates again for a new word.
    pill.classList.remove("on");
    void pill.offsetWidth;
    pill.classList.add("on");
    clearTimeout(pillTimer);
    pillTimer = setTimeout(closePill, o.ms || (undo ? 6500 : 2200));
    return { close: () => { if (pillOpen === mine) closePill(); } };
  }

  /** Said by the next page: for an action that has to reload to show itself. */
  function later(text, options = {}) {
    try {
      const o = options.undoPost ? { undoPost: options.undoPost } : {};
      sessionStorage.setItem("fx-later", JSON.stringify({ text, ...o, at: Date.now() }));
    } catch { /* private window: it simply is not said */ }
  }
  function sayLater() {
    let held = null;
    try { held = JSON.parse(sessionStorage.getItem("fx-later") || "null"); sessionStorage.removeItem("fx-later"); } catch { held = null; }
    if (held && held.text && Date.now() - held.at < 15000) {
      toast(held.text, held.undoPost ? { undoPost: held.undoPost } : {});
    }
  }

  /** Copy, and say so only when it really went to the clipboard. */
  async function copy(text, said = "Copied") {
    let done = false;
    try { await navigator.clipboard.writeText(text); done = true; } catch { done = false; }
    if (!done) {
      const field = el("textarea");
      field.value = text;
      field.setAttribute("readonly", "");
      field.style.cssText = "position:fixed;opacity:0;pointer-events:none";
      document.body.append(field);
      field.select();
      try { done = document.execCommand("copy"); } catch { done = false; }
      field.remove();
    }
    if (done && said) toast(said);
    return done;
  }

  /* =========================================================================
     Popovers
     ========================================================================= */
  const open = new Set();

  /**
   * A floating panel that opens from `anchor` (the thing that was clicked).
   * `content` is a node or an HTML string. Options: `side` (bottom, top,
   * right, left), `align` (start, center, end), `className`, `role`, `onClose`.
   * Escape closes it and gives focus back; so does a press outside it.
   * Nothing behind it is blurred or dimmed.
   */
  function pop(anchor, content, options = {}) {
    const o = options;
    const box = el("div", "fx-pop" + (o.className ? ` ${o.className}` : ""));
    box.setAttribute("role", o.role || "menu");
    if (typeof content === "string") box.innerHTML = content; else if (content) box.append(content);
    (anchor && anchor.closest && anchor.closest(".fh2") || document.body).append(box);

    const place = () => {
      const a = anchor.getBoundingClientRect();
      const b = box.getBoundingClientRect();
      const gap = 6;
      let side = o.side || "bottom";
      if (side === "bottom" && a.bottom + gap + b.height > innerHeight - 8 && a.top - gap - b.height > 8) side = "top";
      if (side === "top" && a.top - gap - b.height < 8 && a.bottom + gap + b.height < innerHeight - 8) side = "bottom";
      let x;
      let y;
      if (side === "left" || side === "right") {
        x = side === "right" ? a.right + gap : a.left - gap - b.width;
        y = o.align === "end" ? a.bottom - b.height : o.align === "center" ? a.top + (a.height - b.height) / 2 : a.top;
      } else {
        y = side === "bottom" ? a.bottom + gap : a.top - gap - b.height;
        x = o.align === "end" ? a.right - b.width : o.align === "center" ? a.left + (a.width - b.width) / 2 : a.left;
      }
      x = Math.max(8, Math.min(x, innerWidth - b.width - 8));
      y = Math.max(8, Math.min(y, innerHeight - b.height - 8));
      box.style.left = `${x}px`;
      box.style.top = `${y}px`;
      // It grows out of the thing that was clicked.
      box.style.setProperty("--fx-ox", `${Math.round(a.left + a.width / 2 - x)}px`);
      box.style.setProperty("--fx-oy", side === "top" ? "100%" : "0");
    };
    place();

    const handle = { el: box, place, close };
    function close(returnFocus = false) {
      if (!open.has(handle)) return;
      open.delete(handle);
      box.remove();
      removeEventListener("resize", onWindow);
      document.removeEventListener("pointerdown", onDown, true);
      document.removeEventListener("keydown", onKey, true);
      if (o.onClose) o.onClose();
      if (returnFocus && anchor && anchor.focus) anchor.focus({ preventScroll: true });
    }
    const onWindow = () => close();
    const onDown = (event) => { if (!box.contains(event.target) && !(anchor && anchor.contains(event.target))) close(); };
    const onKey = (event) => { if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close(true); } };
    addEventListener("resize", onWindow);
    document.addEventListener("pointerdown", onDown, true);
    document.addEventListener("keydown", onKey, true);
    open.add(handle);
    return handle;
  }
  document.addEventListener("swapped", () => { for (const one of [...open]) one.close(); });

  /* =========================================================================
     Sheets: the phone's popover
     ========================================================================= */
  const PHONE = "(max-width:700px), (max-height:480px) and (pointer:coarse)";
  /** The one phone breakpoint (the same as side.css's). */
  const phone = () => matchMedia(PHONE).matches;
  const sheets = new Set();
  const FOCUSABLE = 'a[href],button:not([disabled]),input:not([disabled]):not([type=hidden]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

  function sheet(content, options = {}) {
    const o = options;
    const back = document.activeElement;
    const scrim = el("div", "fx-sheet-scrim");
    const box = el("div", "fx-sheet" + (o.className ? ` ${o.className}` : ""));
    box.setAttribute("role", "dialog");
    box.setAttribute("aria-modal", "true");
    if (o.label || o.title) box.setAttribute("aria-label", o.label || o.title);
    const grab = el("div", "fx-sheet-grab");
    grab.setAttribute("data-sheet-drag", "");
    grab.append(el("i"));
    box.append(grab);
    let titleEl = null;
    if (o.title) {
      const head = el("div", "fx-sheet-head");
      head.setAttribute("data-sheet-drag", "");
      titleEl = el("b", "", o.title);
      const x = el("button", "fx-sheet-x");
      x.type = "button";
      x.setAttribute("aria-label", "Close");
      x.innerHTML = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><path d="m4 4 8 8M12 4l-8 8"/></svg>';
      x.addEventListener("click", () => close(true));
      head.append(titleEl, x);
      box.append(head);
    }
    const body = el("div", "fx-sheet-body");
    if (typeof content === "string") body.innerHTML = content; else if (content) body.append(content);
    box.append(body);
    const host = document.querySelector(".fh2") || document.body;
    host.append(scrim, box);

    const handle = { el: box, body, scrim, title: titleEl, place() {}, close };
    let closed = false;
    function close(returnFocus = false) {
      if (closed) return;
      closed = true;
      sheets.delete(handle);
      removeEventListener("keydown", onKey, true);
      if (window.visualViewport) { visualViewport.removeEventListener("resize", ride); visualViewport.removeEventListener("scroll", ride); }
      const done = () => { box.remove(); scrim.remove(); };
      box.classList.add("out");
      scrim.classList.add("out");
      if (matchMedia("(prefers-reduced-motion:reduce)").matches) done(); else setTimeout(done, 200);
      if (o.onClose) o.onClose();
      if (returnFocus && back && back.isConnected && back.focus) back.focus({ preventScroll: true });
    }

    // The sheet rides above the keyboard.
    function ride() {
      const v = window.visualViewport;
      if (!v) return;
      const covered = Math.max(0, innerHeight - v.height - v.offsetTop);
      box.style.setProperty("--fx-kb", `${Math.round(covered)}px`);
      box.style.setProperty("--fx-vh", `${Math.round(v.height)}px`);
    }
    if (window.visualViewport) { visualViewport.addEventListener("resize", ride); visualViewport.addEventListener("scroll", ride); ride(); }

    function onKey(event) {
      if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); close(true); return; }
      if (event.key !== "Tab") return;
      const all = [...box.querySelectorAll(FOCUSABLE)].filter((n) => n.offsetParent !== null);
      if (!all.length) return;
      const first = all[0];
      const last = all[all.length - 1];
      if (!box.contains(document.activeElement)) { event.preventDefault(); first.focus(); }
      else if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
    addEventListener("keydown", onKey, true);

    scrim.addEventListener("pointerdown", (event) => { event.preventDefault(); close(true); });

    // Drag down on the handle or the head to close; short of far enough, it springs back.
    let drag = null;
    box.addEventListener("pointerdown", (event) => {
      if (event.button > 0 || !event.target.closest("[data-sheet-drag]") || event.target.closest("button, a, input, select")) return;
      drag = { y: event.clientY, at: performance.now(), dy: 0, id: event.pointerId };
      box.classList.add("dragging");
      try { box.setPointerCapture(event.pointerId); } catch { /* the drag still works on the sheet */ }
    });
    box.addEventListener("pointermove", (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      drag.dy = Math.max(0, event.clientY - drag.y);
      box.style.transform = `translateY(${drag.dy}px)`;
      scrim.style.opacity = String(Math.max(0, 1 - drag.dy / 420));
    });
    const release = (event) => {
      if (!drag || event.pointerId !== drag.id) return;
      const fast = drag.dy / Math.max(1, performance.now() - drag.at) > 0.6;
      const far = drag.dy > Math.min(140, box.offsetHeight * 0.3);
      drag = null;
      box.classList.remove("dragging");
      box.style.transform = "";
      scrim.style.opacity = "";
      if (far || (fast && event.type !== "pointercancel")) close(true);
    };
    box.addEventListener("pointerup", release);
    box.addEventListener("pointercancel", release);

    sheets.add(handle);
    // Focus goes in: the field asked for, else the first field, else the sheet.
    // (`focus: false` keeps the keyboard down: focus goes to the sheet itself.)
    const want = o.focus === false ? null : o.focus ? (typeof o.focus === "string" ? box.querySelector(o.focus) : o.focus) : box.querySelector("input:not([type=hidden]):not([type=file]), textarea, select");
    if (want && want.focus) want.focus({ preventScroll: true });
    else { box.tabIndex = -1; box.focus({ preventScroll: true }); }
    return handle;
  }
  document.addEventListener("swapped", () => { for (const one of [...sheets]) one.close(); });

  // **Escape closes every ⋯ menu too** (the page's, a Library card's, the one
  // behind his initials): they are `<details>`, which a browser leaves open.
  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape" || event.defaultPrevented) return;
    const menus = document.querySelectorAll("details.pagemenu[open], details.fh-cardmenu[open], details.me[open]");
    if (!menus.length) return;
    for (const menu of menus) {
      menu.open = false;
      const summary = menu.querySelector("summary");
      if (summary && menu.contains(document.activeElement)) summary.focus({ preventScroll: true });
    }
  });

  /* =========================================================================
     Tooltips that carry the shortcut
     ========================================================================= */
  // A shortcut is named here only when it really does something. Anything else
  // can say its own with data-key.
  const KEYS = { find: "⌘K", search: "⌘K", close: "Esc" };

  let tip = null;
  let tipFor = null;
  let tipTimer = 0;
  let tipLeft = 0;

  const TIP_SKIP = /^(IFRAME|STYLE|SCRIPT|HTML|BODY|TITLE)$/;
  function convert(node) {
    if (!node || node.nodeType !== 1 || TIP_SKIP.test(node.tagName) || node.namespaceURI !== "http://www.w3.org/1999/xhtml") return;
    const said = node.getAttribute("title");
    if (said == null) return;
    node.removeAttribute("title");
    if (!said.trim()) return;
    if (!node.hasAttribute("data-tip")) node.setAttribute("data-tip", said);
    if (!node.hasAttribute("aria-label") && !(node.textContent || "").trim() && !node.querySelector("img[alt]:not([alt=''])")) {
      node.setAttribute("aria-label", said);
    }
    if (!node.hasAttribute("data-key") && KEYS[said.trim().toLowerCase()]) node.setAttribute("data-key", KEYS[said.trim().toLowerCase()]);
  }

  function showTip(node) {
    if (!node.isConnected) return;
    if (!tip) {
      tip = el("div", "fx-tip");
      tip.setAttribute("role", "tooltip");
      document.body.append(tip);
    }
    const key = node.getAttribute("data-key");
    tip.replaceChildren(document.createTextNode(node.getAttribute("data-tip") || ""));
    if (key) tip.append(el("span", "", keyed(key)));
    tipFor = node;
    const a = node.getBoundingClientRect();
    tip.style.left = "0px";
    tip.style.top = "0px";
    const b = tip.getBoundingClientRect();
    let y = a.top - b.height - 8;
    if (y < 6) y = a.bottom + 8;
    const x = Math.max(6, Math.min(a.left + a.width / 2 - b.width / 2, innerWidth - b.width - 6));
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
    tip.classList.add("on");
  }
  function hideTip() {
    clearTimeout(tipTimer);
    if (tip && tip.classList.contains("on")) { tip.classList.remove("on"); tipLeft = Date.now(); }
    tipFor = null;
  }
  document.addEventListener("pointerover", (event) => {
    if (event.pointerType === "touch") return;
    const node = event.target.closest ? event.target.closest("[data-tip]") : null;
    if (node === tipFor && node) return;
    hideTip();
    if (!node) return;
    tipFor = node;
    // The first waits a moment; the next one, right after, does not.
    tipTimer = setTimeout(() => showTip(node), Date.now() - tipLeft < 500 ? 0 : 420);
  }, true);
  document.addEventListener("pointerdown", hideTip, true);
  document.addEventListener("keydown", (event) => { if (event.key === "Escape") hideTip(); }, true);
  document.addEventListener("scroll", hideTip, true);
  document.addEventListener("focusin", (event) => {
    const node = event.target.closest ? event.target.closest("[data-tip]") : null;
    if (node && node.matches(":focus-visible")) { hideTip(); showTip(node); }
  });
  document.addEventListener("focusout", hideTip);
  addEventListener("blur", hideTip);

  /* =========================================================================
     Pictures
     ========================================================================= */
  const loaded = new Set();
  let lastArrival = 0;

  function dressPicture(img) {
    if (img.__fx || img.dataset.fx === "off") return;
    img.__fx = true;
    if (img.closest(".filmicon, .mark, [data-fx='off']")) return;
    const src = img.currentSrc || img.src;
    // Already in (a kept page, a cached picture): it stays instant.
    if (img.complete && (img.naturalWidth || !img.getAttribute("src"))) {
      if (src) loaded.add(src);
      return;
    }
    if (!img.getAttribute("src") && !img.getAttribute("srcset")) return;
    if (loaded.has(src)) return;
    img.classList.add("fx-wait");
    if (img.dataset.fxColor) img.style.setProperty("--fx-ph", img.dataset.fxColor);
    // A picture with no size of its own would be a line until it lands, and
    // then push everything under it down. Hold a box for it.
    if (!img.hasAttribute("width") && !img.hasAttribute("height") && !img.style.aspectRatio && !img.style.height) {
      const r = img.getBoundingClientRect();
      if (r.width > 40 && r.height < 4) img.classList.add("fx-box");
    }
  }

  function arrive(img) {
    const src = img.currentSrc || img.src;
    img.classList.remove("fx-wait", "fx-box", "fx-bad");
    if (img.dataset.fx === "off" || img.closest(".filmicon, .mark, [data-fx='off']")) return;
    if (!src || loaded.has(src)) return;
    loaded.add(src);
    // One beat after the one before, never more than a short queue.
    const now = performance.now();
    const at = Math.max(now, lastArrival + 70);
    lastArrival = at;
    img.style.setProperty("--fx-d", `${Math.min(at - now, 700) / 1000}s`);
    img.classList.add("fx-in");
    const over = () => { img.classList.remove("fx-in"); img.style.removeProperty("--fx-d"); };
    img.addEventListener("animationend", over, { once: true });
    setTimeout(over, 2200);
  }

  // `load` and `error` do not bubble; capturing at the document hears them all.
  document.addEventListener("load", (event) => { if (event.target instanceof HTMLImageElement) arrive(event.target); }, true);
  document.addEventListener("error", (event) => {
    const img = event.target;
    if (!(img instanceof HTMLImageElement)) return;
    img.classList.remove("fx-wait", "fx-box");
    // No broken-picture icon: the placeholder stands, quietly.
    if (img.dataset.fx !== "off") img.classList.add("fx-bad");
  }, true);

  /* =========================================================================
     Keeping up with the page
     ========================================================================= */
  function scan(root) {
    if (root.nodeType !== 1) return;
    if (root.tagName === "IMG") dressPicture(root);
    if (root.hasAttribute && root.hasAttribute("title")) convert(root);
    for (const node of root.querySelectorAll("img, [title]")) {
      if (node.tagName === "IMG") dressPicture(node);
      if (node.hasAttribute("title")) convert(node);
    }
  }

  const watch = new MutationObserver((list) => {
    for (const change of list) {
      if (change.type === "attributes") { convert(change.target); continue; }
      for (const added of change.addedNodes) scan(added);
    }
  });

  function start() {
    scan(document.documentElement);
    watch.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["title"] });
    sayLater();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true }); else start();

  window.feel = { toast, later, copy, pop, sheet, phone, tint, keyed };
})();
