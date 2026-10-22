/**
 * A page that arrived already designed, sealed off from the portal's own CSS.
 *
 * **The fault this fixes, in one line:** `front.css` has a `.frames` rule for a
 * film's picture strip, and a deck design that happens to use the same word had
 * every row of a section laid side by side in a single squashed line — twelve
 * frames as a sixty-pixel sliver, which reads as the page having no pictures at
 * all. `hub.css` styles a `.frames` too, so keeping one stylesheet out was never
 * going to be enough.
 *
 * A design is written fresh for every deck and may use any class name it likes,
 * so the only answer that stays true is that **nothing outside can reach in**.
 * The document brings its own `<style>`, which moves into the shadow root with
 * it, and the portal's rules stop at the boundary.
 *
 * Same treatment as the editor, for the same reason — see `src/editor.js`.
 *
 * **Sealed again every time the page is swapped, and loaded on every front-of-
 * house page so there is something there to do it.** His report, 2026-09-07:
 * the Visual Bible came up squashed on a shared link and a refresh put it
 * right. Both halves were the same gap. `deep.js` replaces `.fh2` on a click in
 * the rail without reloading anything, so a seal done once at load is a seal
 * for a page that has since been thrown away — and worse, arriving from the
 * film's own page meant this file had never been fetched at all, because it
 * used to be asked for only by a page that was itself a deck. A refresh is a
 * real page load, which is why a refresh looked like a fix. `look.js` says the
 * same thing about the same swap; this is that lesson, applied here.
 */

function seal() {
  const host = document.querySelector(".madepage");
  if (!host || host.shadowRoot) return;
  const root = host.attachShadow({ mode: "open" });
  // **Moved, not copied.** Cloning would run every `<img>` twice — sixty-odd
  // needless fetches on a bible — and leave the originals in the light DOM
  // still wearing the portal's rules.
  while (host.firstChild) root.append(host.firstChild);
  // **One rule goes in with it, and only one.** A picture in a published deck
  // opens whole in `look.js`'s lightbox (his answer, 2026-09-10: yes to decks),
  // and the seal that keeps the portal's stylesheets out keeps the zoom-in
  // cursor out too — so the hand that says *this opens* is put back here.
  const hint = document.createElement("style");
  hint.textContent = "img{cursor:zoom-in}";
  root.append(hint);
  // The document sets its own ground and measure; the host only gives it room.
  host.style.display = "block";
}

seal();
// A page swapped in under `deep.js` has never been sealed, and on most pages
// there is nothing here to seal — `seal` finds no host and does nothing.
document.addEventListener("swapped", seal);
