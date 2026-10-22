/**
 * **Pinned and Private: the two settings a page has** (his ruling, 2026-10-03,
 * which retired Seen On's three segments and "Me").
 *
 * - **Pinned**: the page has a row in the sidebar. Unpinned pages still live
 *   in the Library.
 * - **Private**: only he and his editors can see the page. A small lock marks
 *   it wherever an editor meets it.
 *
 * **Plain script, no imports**, loaded `defer` in the head beside `feel.js`, so
 * the sidebar's menu, the Library card's menu, the right click and the phone's
 * press and hold all draw the same two rows:
 *
 *     const rows = seenOn({
 *       base: "/f/<film>",                    // the film's address
 *       keys: ["lighting-plan"],               // a page's address, or "doc:<name>" for a document
 *       pinned: true, priv: false,             // how they stand now (for several keys: lit only if all are)
 *       can: { pin: true, priv: true },        // which rows to offer (documents have no row in the sidebar; only an administrator sets Private)
 *       onChange(kind, on) {},                 // `pin` or `priv`, after each toggle has been saved
 *     });
 *     menu.append(rows);
 *
 * A toggle is **optimistic**: the switch turns at once, the change is posted
 * to the film's Library (the same `bulk` post the Library's toolbar uses), and
 * `feel.toast("Saved")` confirms. If the post fails the switch goes back and
 * the pill says `Could Not Save`.
 *
 * `seenOn.post(base, action, keys, to)` is the post on its own, for anything
 * else that needs to say the same thing (the Add menu's Built In switches).
 */
(() => {
  if (window.seenOn) return;

  // Pin on = "pin"; Private on = "private". The server also still answers to
  // the older `sidebar-on`, `links-hide` and their opposites.
  const ACTIONS = { pin: ["pin", "unpin"], priv: ["private", "public"] };
  const WORDS = { pin: "Pinned", priv: "Private" };
  const ICON = {
    pin: '<path d="M6 2.5h4l-.6 4.2 2.1 2.3H4.5l2.1-2.3L6 2.5Z"/><path d="M8 9v4.5"/>',
    priv: '<path d="M4.4 7.2h7.2a1.4 1.4 0 0 1 1.4 1.4v4.2a1.4 1.4 0 0 1-1.4 1.4H4.4A1.4 1.4 0 0 1 3 12.8V8.6a1.4 1.4 0 0 1 1.4-1.4Z"/><path d="M5.6 7.2V5.4a2.4 2.4 0 0 1 4.8 0v1.8"/>',
  };

  /**
   * **Say the film changed**, so every page `deep.js` fetched ahead of a click
   * is thrown away. A sidebar edit changes the pages beside it (a new link on
   * Documents, a count on a row) and serving one of those from the kept copy
   * would show him the thing he changed, unchanged. `arranging` and `arranged`
   * are the words `arrange.js` already says when the rail changes.
   */
  function changed() {
    document.dispatchEvent(new CustomEvent("arranging"));
    document.dispatchEvent(new CustomEvent("arranged"));
  }

  /** One bulk post. Resolves true when the server took it. */
  async function post(base, action, keys, to = "") {
    const body = new FormData();
    body.set("bulk", JSON.stringify({ keys, action, to }));
    try {
      const got = await fetch(`${base}/library`, { method: "POST", body, credentials: "same-origin" });
      if (got.ok) changed();
      return got.ok;
    } catch {
      return false;
    }
  }

  function seenOn(options) {
    const o = options || {};
    const can = { pin: true, priv: true, ...(o.can || {}) };
    const state = { pin: o.pinned !== false, priv: o.priv === true };
    // A row on the sidebar calls its switch On Sidebar (2026-10-11).
    const words = { ...WORDS, ...(o.words || {}) };
    const root = document.createElement("div");
    root.className = "seenon";
    root.setAttribute("role", "group");
    root.setAttribute("aria-label", "Settings");
    for (const kind of ["pin", "priv"]) {
      if (!can[kind]) continue;
      const button = document.createElement("button");
      button.type = "button";
      button.className = "sn";
      button.setAttribute("role", "switch");
      button.dataset.seen = kind;
      button.innerHTML = `<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICON[kind]}</svg><span class="snw">${words[kind]}</span><i class="fx-sw" aria-hidden="true"></i>`;
      const draw = () => {
        button.classList.toggle("on", state[kind]);
        button.setAttribute("aria-checked", String(state[kind]));
        button.querySelector(".fx-sw").classList.toggle("on", state[kind]);
      };
      draw();
      button.addEventListener("click", async (event) => {
        event.preventDefault();
        event.stopPropagation();
        if (button.disabled) return;
        const want = !state[kind];
        state[kind] = want;
        draw();
        button.disabled = true;
        const good = await post(o.base, ACTIONS[kind][want ? 0 : 1], o.keys || []);
        button.disabled = false;
        if (!good) {
          state[kind] = !want;
          draw();
          if (window.feel) feel.toast("Could Not Save");
          return;
        }
        if (window.feel) feel.toast("Saved");
        if (o.onChange) o.onChange(kind, want);
      });
      root.append(button);
    }
    return root;
  }
  seenOn.post = post;
  seenOn.changed = changed;
  window.seenOn = seenOn;
})();
