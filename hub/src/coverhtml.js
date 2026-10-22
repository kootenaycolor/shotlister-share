/**
 * **The link cover, as a page to photograph** — the drawing `hub/cover.mjs`
 * did on the Mac, moved here so the Mac and the portal draw from one copy
 * (2026-10-11, Projects Console without the Mac, stage 3 step 2).
 *
 * `cover.mjs` (the Mac's headless Chrome) and `linkcovers.js` (Cloudflare's
 * browser, beside the worker) both import this, so a change to the card is a
 * change to both. Pure: the typeface comes in as the `@font-face` rules, made
 * by whoever has the files — read off disk on the Mac, out of the worker's
 * own static files on the portal — so the card can never come out in a
 * fallback the rest of the product never shows.
 *
 * What the card says is `covers_wanted` in `refresh.py` (`coversWanted` in
 * `refreshrules.js`): `{title, page, path, colour, logline, status, shoot}`,
 * or `{icon: true, …}` for the 512-square icon.
 */

export const esc = (s) => String(s == null ? "" : s)
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/** The portal's own typeface, Rethink Sans 600 and 500, from two font addresses. */
export function fontFaces(at600, at500) {
  return `@font-face{font-family:R;src:url(${at600}) format("woff2");font-weight:600}
@font-face{font-family:R;src:url(${at500}) format("woff2");font-weight:500}`;
}

/** The 1200x630 card a pasted link unfurls into. */
export function coverPage(film, FONTS) {
  /* **Sized by how much there is to say.** A four-word title at 92px and a
     one-word title at 92px look like different products; this keeps the block
     optically similar whatever the film is called. */
  const title = String(film.title || "Untitled");
  const page = String(film.page || "");
  const big = page || title;
  const size = big.length > 34 ? 62 : big.length > 22 ? 74 : 92;
  const colour = film.colour || "#E8E8EA";
  /* A page's card says the film under the page's name; the film's card says
     its logline under its own. */
  const under = page ? title : film.logline;
  /* **Where the film stands, not just its name.** His report, 2026-09-23: a
     card with only a title and a brand mark read as empty — nothing on it
     told a person anything. Status and shoot dates are already on every
     card's own data (`covers_wanted` in `refresh.py`); saying them here
     costs nothing new and gives the card something to say. */
  const meta = [film.status, film.shoot].filter(Boolean).join(" · ");

  return `<!doctype html><meta charset="utf-8"><style>
${FONTS}
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1200px;height:630px}
body{background:#0A0A0A;color:#F4F4F6;font-family:R,system-ui,sans-serif;
  padding:86px 88px;display:flex;flex-direction:column;justify-content:space-between;
  /* the film's colour, thrown once across the ground so the card reads as
     the film's before a word of it is read */
  background-image:radial-gradient(1100px 620px at 88% -22%, ${esc(colour)}2E, transparent 68%)}
.top{display:flex;justify-content:space-between;align-items:flex-start}
.mark{width:104px;height:104px;color:${esc(colour)}}
.mark svg{width:100%;height:100%;display:block}
/* **A quiet corner, not a footer.** The old dot-and-wordmark sat alone at
   the bottom with nothing beside it — the emptiest-looking thing on an
   already-empty card. Naming the product still matters (a card that could
   be anybody's screenshot is worse), so it moves to a corner label instead
   of anchoring the whole bottom. */
.brand{font-weight:500;font-size:22px;color:#6E6E76}
h1{font-weight:600;font-size:${size}px;line-height:1.04;letter-spacing:-.028em;max-width:16ch}
.said{margin-top:22px;font-weight:500;font-size:26px;line-height:1.4;color:#9A9AA2;
  max-width:34ch;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.film{color:#C8C8CE;font-size:30px}
.meta{margin-top:22px;font-weight:500;font-size:24px;color:#8A8A92}
</style>
<div class="top">
  <div class="mark">${film.path
    ? `<svg viewBox="0 0 20 20" fill="currentColor"><path d="${esc(film.path)}"/></svg>`
    : ""}</div>
  <span class="brand">Shotlister</span>
</div>
<div>
  <h1>${esc(big)}</h1>
  ${under ? `<p class="said${page ? " film" : ""}">${esc(under)}</p>` : ""}
  ${meta ? `<p class="meta">${esc(meta)}</p>` : ""}
</div>
<div></div>`;
}

/**
 * The film's 512-square icon — Safari's tab and the iPhone's home screen,
 * neither of which will draw an SVG: the mark on the night ground, lit by its
 * colour. A film with no mark gets its initial, in its colour, which is still
 * its own. (`{icon: "product"}`, the product's own mark, stays in
 * `cover.mjs`: it reads the app icon's source off disk and is nobody's film.)
 */
export function coverIcon(film, FONTS) {
  const title = String(film.title || "Untitled");
  const colour = film.colour || "#E8E8EA";
  const initial = (title.trim()[0] || "S").toUpperCase();
  return `<!doctype html><meta charset="utf-8"><style>
${FONTS}
*{margin:0;padding:0;box-sizing:border-box}
html,body{width:512px;height:512px}
body{background:#0A0A0A;color:${esc(colour)};font-family:R,system-ui,sans-serif;
  display:flex;align-items:center;justify-content:center;
  background-image:radial-gradient(520px 520px at 82% -10%, ${esc(colour)}3A, transparent 70%)}
.mark{width:288px;height:288px}
.mark svg{width:100%;height:100%;display:block}
.initial{font-weight:600;font-size:300px;line-height:1;letter-spacing:-.04em;margin-top:-16px}
</style>
${film.path
  ? `<div class="mark"><svg viewBox="0 0 20 20" fill="currentColor"><path d="${esc(film.path)}"/></svg></div>`
  : `<div class="initial">${esc(initial)}</div>`}`;
}
