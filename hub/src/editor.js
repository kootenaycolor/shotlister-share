/**
 * The deck editor, as a page of the portal.
 *
 * His instruction, 2026-09-05: rebuild it rather than retrofit it, because the
 * old one had a print-layout engine at its centre and *"feels bootstrapped
 * rather than purpose made"*. It is here rather than on his Mac, which is what
 * lets a deck have one home instead of a folder in Drive and a copy on the
 * website that drift apart.
 *
 * **What is served is a shell.** Each deck is drawn by `public/deck.js` from
 * the record, and each design's own stylesheet is lifted out of what it
 * published and put beside it untouched — so the editor shows the real thing,
 * and knows nothing about what any particular design looks like. That is what
 * lets a design be written fresh for every deck without this file changing.
 *
 * **Two documents, one per side, each sealed in its own shadow root.** The
 * portal's stylesheet has a `.frames` rule for a film's picture strip, and a
 * deck design that happens to use the same word had every row of a section laid
 * side by side in one squashed line. A design may use any class name it likes,
 * so the only safe answer is that nothing outside can reach in — and that the
 * web design and the print design cannot reach each other either, which is the
 * whole point of their being two. The live page does the same; see
 * `public/made.js`.
 *
 * **THE LAW OF THIS FILE, 2026-09-06.** His complaint: *"the preview panes are
 * not an exact preview of what will be displayed on the html website. images
 * have more gaps."* The cause was here. The editor used to inject four layout
 * rules of its own into the shadow root — a cap on how skinny a row may be, a
 * hero held to two thirds, the shape of an even cell — and the published page
 * never saw any of them, because only the *body* is published and those rules
 * lived in the editor's own stylesheet.
 *
 * The rule that replaces it: **the editor adds no CSS that can move anything.**
 * Every layout decision it makes is written as an inline style on the element
 * it draws, and inline styles are part of the body, so they publish and they
 * print. What is left in here is only what a handle needs — an outline, a
 * cursor, a picture that does not start the browser's own drag — none of which
 * occupies space. Measured after the change: every one of twelve frames the
 * same size on both sides, against five out by up to 392px before it.
 *
 * ---
 *
 * **The pass of 2026-09-06, second half**, on his report that *"the ux/ui of
 * the deck editor frankly sucks. The PDF has no editing controls, and the html
 * is hard to use."* The furniture below is the answer, and it is three things:
 * a rail of sections down the left, the deck in the middle in whichever of its
 * two forms he is working on, and an inspector down the right that changes with
 * what is picked. The strip of fifteen pills is gone.
 *
 * **Paper is drawn, not embedded.** It was an iframe of the last PDF his Mac
 * printed — untouchable, and blank in his own Deck Editor app, which is a
 * WKWebView. `#papered` is a second document with the print design's own
 * stylesheet in it, holding real sheets that can be arranged on. The printed
 * file is still offered, because that is the thing he sends to a director.
 */

const esc = (s) =>
  String(s == null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");

/**
 * The design's own stylesheet, out of the page it published.
 *
 * **Lifted, never rewritten.** The deck's look is his and is tuned by hand; the
 * editor's job is to show it, so the `<style>` block travels across as it is.
 */
export function bodyOf(published) {
  // The published page is a fragment: a head carrying the design's `<style>`,
  // then the design's own markup. Everything after the last stylesheet is the
  // deck as it really looks, and that is what the editor draws on.
  const at = (published || "").lastIndexOf("</style>");
  const body = at === -1 ? String(published || "") : published.slice(at + 8);
  // **A picture's address is relative to the page, and this is not the page.**
  // A published deck says `src="pic/x.jpg"`, which resolves beside the deck at
  // `/f/<film>/<slug>/`. The editor lives one level deeper, so the same string
  // asks for `/f/<film>/<slug>/pic/x.jpg` and every frame comes back 404 — a
  // deck with no pictures in it, which is exactly what he saw.
  return body.replace(/(\s(?:src|href)=")pic\//g, "$1../pic/");
}

export function stylesOf(published) {
  const out = [];
  const re = /<style[^>]*>([\s\S]*?)<\/style>/gi;
  let m;
  while ((m = re.exec(published || ""))) out.push(m[1]);
  return out.join("\n");
}

/**
 * A section's own name, out of the slug the folders gave it.
 *
 * His title-case ruling of 2026-09-04, including its exception: a small word
 * between others stays small, and a small word that leads does not.
 */
const SMALL = new Set(["of", "the", "a", "an", "and", "or", "to", "in", "on", "for"]);

export function readable(said) {
  const words = String(said || "").replace(/[_-]+/g, " ").trim().split(/\s+/);
  if (!words[0]) return "";
  return words
    .map((w, i) => {
      if (w.length === 1) return w.toUpperCase();
      if (i > 0 && SMALL.has(w.toLowerCase())) return w.toLowerCase();
      return w[0].toUpperCase() + w.slice(1);
    })
    .join(" ");
}

/**
 * **Handles, and nothing that occupies space.** Every rule here draws on top of
 * a design or changes a cursor; not one of them can move a frame. That is the
 * law above. Shared by both documents, because a frame is handled the same way
 * whichever side it is drawn on.
 */
const HANDLES = `
    :host{display:block}
    figure{position:relative}
    /* **The frame is what gets dragged, not the picture.** A picture element is
       draggable all by itself, so taking hold of one started the browser's own
       image drag and the frame's drag never began. */
    figure img{-webkit-user-drag:none;user-select:none}
    figure[data-key]{cursor:grab}
    figure[data-key].picked{outline:2px solid var(--accent,#7DA4FF);outline-offset:-2px;z-index:2}
    figure[data-key].lifted{opacity:.35}
    figure[data-key]:hover{filter:brightness(1.08)}
    /* **The group is drawn, because emphasis belongs to it and not to one
       picture.** Making one frame a hero changes every frame beside it. */
    figure[data-key].kin{outline:1px dashed var(--accent,#7DA4FF);outline-offset:-1px}
    figure[data-key].cropping{cursor:move;outline:2px solid #F2C14E;outline-offset:-2px;z-index:3}
    figure[data-key].cropping:after{content:"Drag to move the picture";position:absolute;
      left:50%;bottom:8px;transform:translateX(-50%);background:rgba(10,10,10,.82);
      color:#F2F2F2;font:11px/1 system-ui,sans-serif;padding:5px 9px;border-radius:999px;
      white-space:nowrap;pointer-events:none}
    [data-t]:focus{outline:2px solid var(--accent,#7DA4FF);outline-offset:3px;border-radius:3px}
    [data-t]:hover{outline:1px dashed rgba(125,164,255,.45);outline-offset:3px;border-radius:3px}
    /* **Where a new row would go.** Nought high until something is being
       dragged, so it can never push a frame anywhere. His ask, 2026-09-06:
       drop between two rows and get a row there. */
    .dgap{height:0;margin:0;border-radius:3px;pointer-events:none}
    :host(.dragging) .dgap{height:14px;margin:3px 0;background:rgba(125,164,255,.14);
      border:1px dashed rgba(125,164,255,.55)}
    :host(.dragging) .dgap.dkover{background:var(--accent,#7DA4FF);border-color:transparent}
`;

/** The bar's own right-click menu is drawn in the light DOM; these are the
 *  rows it offers, said once. */
export function editorBody(base, film, deck, record, styles, body, build = "0", paper = "") {
  const kit = record.paper || null;
  return `<div class="deckedit fh2">
  <header class="dbar">
    <a class="dback" href="${esc(base)}/${esc(deck)}">${esc(film)}</a>
    <span class="dname">${esc(record.name || readable(deck))}</span>

    <div class="dmid">
      <div class="dviews">
        <button type="button" data-view="web" class="on">Web</button>
        <button type="button" data-view="paper">Paper</button>
      </div>
      <div class="dzoom">
        <button type="button" id="zoomout" aria-label="Smaller">−</button>
        <span id="zoomsaid">100%</span>
        <button type="button" id="zoomin" aria-label="Bigger">+</button>
      </div>
    </div>

    <div class="dacts">
      <span class="dstate" id="state">Saved</span>
      <button type="button" id="undo" disabled title="Undo" aria-label="Undo">↶</button>
      <button type="button" id="redo" disabled title="Redo" aria-label="Redo">↷</button>
      <button type="button" id="publish" class="prime">Publish</button>
    </div>
  </header>

  <div class="dbody">
    <aside class="drail">
      <div class="railhead"><span class="dklab">Sections</span><span class="dklab" id="seccount"></span></div>
      <div id="sections"></div>
    </aside>

    <main class="dstage" id="canvas">
      <div id="stage"></div>
      <div id="papered" hidden></div>
      <p class="dknopaper" id="nopaper" hidden>No paper design yet. Publish once from your Mac.</p>
    </main>

    <aside class="dinsp" id="insp"></aside>
  </div>

  <div class="ddrawer" id="drawer">
    <div class="drawerhead">
      <button type="button" id="drawertoggle" class="dkicon" aria-label="Stills">▤</button>
      <span class="dklab">Stills</span>
      <div class="dtabs">
        <button type="button" data-source="deck" class="on">This Deck</button>
        <button type="button" data-source="film">Film</button>
        <button type="button" data-source="unused">Unused</button>
        <button type="button" data-source="notion">Notion</button>
      </div>
      <span class="dkshelfsaid" id="shelfsaid"></span>
      <span class="dsp"></span>
      <button type="button" id="addstills">Add Stills…</button>
      <input id="addfiles" type="file" multiple accept="image/*" hidden>
      <button type="button" id="drawergrid" class="dkicon" title="Grid" aria-label="Grid">▦</button>
      <input id="find" type="search" placeholder="Search stills" aria-label="Search stills">
      <span class="dklab" id="stillcount"></span>
    </div>
    <div class="dkstills" id="stills"></div>
  </div>

  <div class="dklook" id="look" hidden><img alt=""><div class="dklooksaid" id="looksaid"></div></div>

  <div class="dmenu" id="menu" hidden></div>
  <div class="dtoast" id="toast"></div>

  <template id="deckdoc"><style>${styles}</style><style>${HANDLES}</style><div id="deck" class="web">${body}</div></template>

  <template id="paperdoc"><style>${paper}</style><style>${HANDLES}
    /* The sheets, on their table. Furniture around the paper, never on it. */
    #sheets{display:flex;flex-direction:column;align-items:center;gap:26px;
      padding:26px 0 60px;zoom:var(--sheet,1)}
    #sheets .page{box-shadow:0 10px 34px rgba(0,0,0,.55);position:relative;flex:none}
    #sheets .page:after{content:attr(data-sheet);position:absolute;right:-26px;top:0;
      font:11px/1 system-ui,sans-serif;color:#8A8A8A}
    /* A design may hide its own furniture for print; the editor shows it, so
       what he arranges against is the sheet as it comes out. */
    #sheets .phead,#sheets .foot,#sheets .pnote{display:revert}
  </style><div id="sheets"></div></template>

  <script type="application/json" id="record">${
    JSON.stringify(record).replace(/</g, "\\u003c")
  }</script>

  <style>
    /* The editor's own furniture. Everything above this line is his design. */
    /* **The hidden attribute has to win.** A display:flex rule beats the
       browser's own [hidden]{display:none}, so a bar with nothing to say sat
       there empty — a row of blank pills under the toolbar. */
    .deckedit [hidden]{display:none!important}
    .deckedit{height:100vh;display:flex;flex-direction:column;overflow:hidden;
      background:var(--page,#0A0A0A);color:var(--ink,#D9D9D9)}
    .deckedit button{font:inherit;color:inherit;background:transparent;
      border:1px solid var(--line,rgba(255,255,255,.10));border-radius:8px;
      padding:5px 11px;font-size:13px;cursor:pointer;
      transition:background .12s ease,border-color .12s ease,color .12s ease}
    .deckedit button:hover:not(:disabled){background:rgba(255,255,255,.06);
      border-color:var(--line2,rgba(255,255,255,.18))}
    .deckedit button:disabled{opacity:.32;cursor:not-allowed;border-style:dashed}
    .deckedit button.on{background:var(--accent,#7DA4FF);color:#0A0A0A;border-color:transparent}
    .deckedit button.on:disabled{opacity:1;cursor:default;border-style:solid}
    .deckedit .prime:not(:disabled){background:var(--accent,#7DA4FF);color:#0A0A0A;
      border-color:transparent;font-weight:600}
    .deckedit .dklab{font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;
      color:var(--quiet,#8A8A8A)}
    .deckedit kbd{font:11px/1.5 ui-monospace,Menlo,monospace;background:var(--card,#1B1B1B);
      border:1px solid var(--line,rgba(255,255,255,.10));border-radius:4px;padding:1px 5px}

    /* ---- the bar ---- */
    .dbar{flex:none;display:flex;gap:12px;align-items:center;padding:9px 14px;
      background:var(--railbg,#0D0D0D);border-bottom:1px solid var(--line,rgba(255,255,255,.10))}
    .dback{color:var(--quiet,#8A8A8A);text-decoration:none;font-size:13px}
    .dback:hover{color:var(--loud,#F2F2F2)}
    .dname{font-size:14px;font-weight:600;color:var(--loud,#F2F2F2)}
    .dmid{margin:0 auto;display:flex;gap:10px;align-items:center}
    .dviews{display:flex;border:1px solid var(--line2,rgba(255,255,255,.18));
      border-radius:999px;overflow:hidden}
    .dviews button{border:0;border-radius:0;padding:5px 15px}
    .dzoom{display:flex;align-items:center;gap:3px;color:var(--quiet,#8A8A8A);font-size:12px}
    .dzoom button{padding:2px 8px;border-radius:6px}
    .dzoom span{min-width:38px;text-align:center;font-variant-numeric:tabular-nums}
    .dacts{display:flex;gap:8px;align-items:center}
    /* Saving says so where it happens, rather than in a button that changes
       its own name and then changes back. */
    .dstate{font-size:12px;color:var(--quiet,#8A8A8A);min-width:74px;text-align:right}
    .dstate.dkwarn{color:#F2C14E}

    /* ---- three columns ---- */
    .dbody{flex:1;min-height:0;display:grid;grid-template-columns:222px minmax(0,1fr) 286px}
    /* **The deck never leaves the screen.** Hiding the rail with display:none
       took it out of the grid, so the canvas fell into the rail's 0px column
       and the inspector took the deck's — below 1180px the deck was simply
       gone, and his own app opens at 900. Found by driving, 2026-09-07. */
    @media (max-width:1180px){.dbody{grid-template-columns:168px minmax(0,1fr) 262px}
      .dksec .dkstrip{display:none}}
    @media (max-width:980px){.dbody{grid-template-columns:minmax(0,1fr) 250px}
      .drail{display:none}}

    /* ---- the rail ---- */
    .drail{overflow:auto;padding:10px 8px;background:var(--railbg,#0D0D0D);
      border-right:1px solid var(--line,rgba(255,255,255,.10))}
    .railhead{display:flex;justify-content:space-between;padding:2px 6px 8px}
    .dksec{display:grid;grid-template-columns:12px 1fr 22px auto;gap:7px;align-items:center;
      padding:6px;border-radius:8px;cursor:pointer}
    .dksec:hover{background:rgba(255,255,255,.04)}
    .dksec.on{background:rgba(125,164,255,.14)}
    .dksec.on .dkt{color:var(--loud,#F2F2F2)}
    .dksec.off{opacity:.45}
    .dksec.dkover{box-shadow:0 -2px 0 var(--accent,#7DA4FF)}
    .dksec .dkgrip{color:rgba(255,255,255,.22);font-size:11px;cursor:grab;line-height:1}
    .dksec .dkt{font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .dksec .dkstrip{display:flex;gap:2px;margin-top:4px;height:13px}
    .dksec .dkstrip i{flex:1;background-size:cover;background-position:center;border-radius:0}
    .dksec .dkstrip.dkwords i{background:rgba(255,255,255,.08)}
    .dksec .dkeye{width:22px;height:22px;padding:0;border:0;border-radius:6px;
      color:var(--quiet,#8A8A8A);font-size:11px}
    .dksec .dkn{font-size:11px;color:var(--quiet,#8A8A8A);font-variant-numeric:tabular-nums;
      min-width:14px;text-align:right}

    /* ---- the stage ---- */
    .dstage{overflow:auto;position:relative;background:var(--page,#0A0A0A);
      overscroll-behavior:contain}
    .dstage.onpaper{background:#171717}
    /* **Nothing is selected by a drag across the deck.** The browser's own text
       selection fights every gesture in here. */
    .dstage{user-select:none}
    .dstage [data-t]{user-select:text}
    .dknopaper{margin:80px auto;max-width:36ch;text-align:center;color:var(--quiet,#8A8A8A);
      font-size:13px}

    /* ---- the inspector ---- */
    .dinsp{overflow:auto;padding:12px 13px 40px;background:var(--panel,#141414);
      border-left:1px solid var(--line,rgba(255,255,255,.10));
      display:flex;flex-direction:column;gap:14px}
    .dinsp .dkhead{display:flex;align-items:baseline;justify-content:space-between;gap:8px}
    .dinsp .dkhead b{font-size:13.5px;color:var(--loud,#F2F2F2)}
    .dinsp .dkhead span{font-size:11.5px;color:var(--quiet,#8A8A8A);white-space:nowrap;
      overflow:hidden;text-overflow:ellipsis}
    .dkgrp{display:flex;flex-direction:column;gap:8px;padding-top:12px;
      border-top:1px solid var(--line,rgba(255,255,255,.10))}
    .dkgrp:first-of-type{border-top:0;padding-top:0}
    .dkrow{display:flex;gap:6px;flex-wrap:wrap}
    .dkrow.tight{gap:4px}
    .dkrow button,.dkrow .dkbtn{padding:5px 9px;font-size:12px}
    .dkbtn{border:1px solid var(--line,rgba(255,255,255,.10));border-radius:8px;
      padding:5px 9px;font-size:12px;color:var(--ink,#D9D9D9);text-decoration:none;
      display:inline-flex;align-items:center}
    .dkbtn:hover{background:rgba(255,255,255,.06)}
    .dklines{display:grid;gap:5px}
    .dkline{display:flex;justify-content:space-between;align-items:baseline;gap:8px;
      padding:7px 9px;background:var(--card,#1B1B1B);border-radius:8px}
    .dkline b{font-weight:500;font-size:12.5px;color:var(--loud,#F2F2F2)}
    .dkline span{font-size:11.5px;color:var(--quiet,#8A8A8A)}
    .dkline.dkwarn span{color:#F2C14E}
    .dksrc{display:flex;align-items:center;justify-content:space-between;gap:8px;
      padding:8px 9px;background:var(--card,#1B1B1B);border-radius:8px}
    .dksrcname{min-width:0}
    .dksrcname b{display:block;font-weight:500;font-size:12.5px;color:var(--loud,#F2F2F2);
      white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .dksrcname small{display:block;font-size:11px;color:var(--quiet,#8A8A8A);
      white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .dkhint{margin:0;font-size:11.5px;line-height:1.5;color:var(--quiet,#8A8A8A)}
    .dkshot{position:relative;aspect-ratio:16/9;border-radius:0;overflow:hidden;
      background:var(--card,#1B1B1B)}
    .dkshot img{width:100%;height:100%;object-fit:cover;display:block}
    .dkshot .dkspot{position:absolute;width:10px;height:10px;border-radius:50%;
      background:#F2C14E;box-shadow:0 0 0 2px rgba(0,0,0,.5);
      left:calc(var(--x,50%) - 5px);top:calc(var(--y,50%) - 5px);pointer-events:none}
    .dkloud{display:grid;grid-template-columns:repeat(4,1fr);gap:4px}
    .dkloud button{display:flex;flex-direction:column;align-items:center;gap:6px;
      padding:8px 3px;font-size:11px}
    .dkloud i{display:grid;gap:2px;width:34px;height:11px}
    .dkloud i b{background:currentColor;opacity:.65;border-radius:1px}
    .dkside{display:grid;grid-template-columns:46px 1fr;gap:6px;align-items:center}
    .dkstep{display:inline-flex;align-items:center;border:1px solid var(--line,rgba(255,255,255,.10));
      border-radius:8px;overflow:hidden;width:fit-content}
    .dkstep button{border:0;border-radius:0;padding:3px 10px}
    .dkstep span{min-width:24px;text-align:center;font-size:12.5px;color:var(--loud,#F2F2F2);
      font-variant-numeric:tabular-nums}
    .dktick{display:flex;align-items:center;gap:6px;font-size:11.5px;
      color:var(--quiet,#8A8A8A);cursor:pointer}
    .dktick input{accent-color:var(--accent,#7DA4FF)}

    /* ---- the drawer ---- */
    .ddrawer{flex:none;background:var(--railbg,#0D0D0D);
      border-top:1px solid var(--line,rgba(255,255,255,.10))}
    .drawerhead{display:flex;align-items:center;gap:8px;padding:6px 12px}
    .dkicon{padding:4px 8px}
    .dtabs{display:flex;gap:2px}
    .dtabs button{border:0;border-radius:6px;padding:4px 10px;color:var(--quiet,#8A8A8A)}
    .dtabs button.on{background:rgba(255,255,255,.08);color:var(--loud,#F2F2F2)}
    .dsp{flex:1}
    .drawerhead input{background:var(--card,#1B1B1B);color:var(--ink,#D9D9D9);font:inherit;
      font-size:12.5px;border:1px solid var(--line,rgba(255,255,255,.10));
      border-radius:7px;padding:4px 9px;width:150px}
    .dkstills{display:none;gap:6px;padding:0 12px 11px;overflow-x:auto}
    .ddrawer.open .dkstills{display:flex}
    /* **dkpic, the name the drawer writes.** These rules said .pic and
       matched nothing, so every tile drew as a padded bordered button and the
       ✓ and New badges had never once been seen. Found by driving, 2026-09-07. */
    .dkstills .dkpic{flex:none;height:74px;padding:0;border:0;border-radius:0;overflow:hidden;
      position:relative;cursor:grab;outline:1px solid transparent;outline-offset:-1px}
    .dkstills .dkpic img{height:100%;display:block;-webkit-user-drag:none}
    .dkstills .dkpic:hover{outline-color:var(--line2,rgba(255,255,255,.18))}
    .dkstills .dkpic.dkon{outline:2px solid var(--accent,#7DA4FF);outline-offset:-2px}
    .dkstills .dkpic.dkused:after{content:"✓";position:absolute;right:3px;top:2px;width:15px;height:15px;
      display:grid;place-items:center;font-size:10px;color:#0A0A0A;
      background:var(--accent,#7DA4FF);border-radius:50%}
    .dkstills .dkpic.dkfresh:before{content:"New";position:absolute;left:3px;top:2px;font-size:9.5px;
      color:#0A0A0A;background:#F2C14E;border-radius:4px;padding:1px 4px}
    /* **A grid, when the strip is not enough.** Forty stills in one row is a
       long scroll; the same tiles wrapped, with the drawer given some height. */
    .ddrawer.tall .dkstills{flex-wrap:wrap;max-height:42vh;overflow:auto}
    .ddrawer.tall .dkstills .dkpic{height:96px}
    .dkicon.on{background:rgba(255,255,255,.08)}
    .dkshelfsaid{font-size:11px;color:var(--quiet,#8A8A8A);white-space:nowrap}
    /* ---- one still, whole ---- */
    .dklook{position:fixed;inset:0;z-index:40;background:rgba(0,0,0,.9);display:grid;
      place-items:center;cursor:zoom-out}
    .dklook img{max-width:92vw;max-height:84vh;display:block;box-shadow:0 20px 60px rgba(0,0,0,.6)}
    .dklooksaid{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);font-size:12px;
      color:var(--quiet,#8A8A8A);font-variant-numeric:tabular-nums;white-space:nowrap}
    /* ---- the Notion field ---- */
    .dinsp input[type=url]{flex:1;min-width:0;background:var(--card,#1B1B1B);color:var(--ink,#D9D9D9);
      font:inherit;font-size:12px;border:1px solid var(--line,rgba(255,255,255,.10));
      border-radius:7px;padding:5px 8px}
    .dkstills .dkdrop{flex:none;width:104px;border:1px dashed var(--line2,rgba(255,255,255,.18));
      border-radius:7px;display:grid;place-items:center;text-align:center;padding:6px;
      font-size:11px;color:var(--quiet,#8A8A8A)}

    /* ---- what a drag draws ---- */
    /* **Beside the deck, never inside it**, so they are positioned against the
       window and can never be swept into what publishes. The bar had no rule at
       all until 2026-09-06 — made, positioned, shown, and invisible, so every
       drag since the editor landed had been blind. */
    .marquee{position:fixed;z-index:9;pointer-events:none;
      border:1px solid var(--accent,#7DA4FF);background:rgba(125,164,255,.14)}
    .dropbar{position:fixed;width:3px;border-radius:2px;z-index:9;pointer-events:none;
      background:var(--accent,#7DA4FF);box-shadow:0 0 0 1px rgba(10,10,10,.5)}
    .dghost{position:fixed;z-index:10;pointer-events:none;width:118px;opacity:.85;
      transform:translate(0,0);box-shadow:0 8px 24px rgba(0,0,0,.5)}
    .dghost img{width:100%;display:block}
    .dghost .dmany{position:absolute;right:-7px;top:-7px;min-width:20px;height:20px;padding:0 5px;
      display:grid;place-items:center;border-radius:999px;background:var(--accent,#7DA4FF);
      color:#0A0A0A;font:600 11px/1 system-ui,sans-serif}
    body.dragging{cursor:grabbing}

    /* ---- the right-click menu, and what the editor says ---- */
    .dmenu{position:fixed;z-index:20;min-width:168px;padding:4px;border-radius:10px;
      background:var(--card,#1B1B1B);border:1px solid var(--line2,rgba(255,255,255,.18));
      box-shadow:0 12px 34px rgba(0,0,0,.55)}
    .dmenu button{display:block;width:100%;text-align:left;border:0;border-radius:6px;padding:6px 10px}
    .msep{height:1px;background:var(--line,rgba(255,255,255,.10));margin:4px 0}
    .dtoast{position:fixed;left:50%;bottom:96px;transform:translateX(-50%);z-index:30;
      background:#181818;color:#D9D9D9;border:1px solid var(--line2,rgba(255,255,255,.18));
      border-radius:999px;padding:7px 15px;font-size:12px;opacity:0;pointer-events:none;
      transition:opacity .18s ease}
    .dtoast.on{opacity:1}
  </style>
  <script type="module" src="/deck.js?v=${esc(build)}"></script>
</div>`;
}
