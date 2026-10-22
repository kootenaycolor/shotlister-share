// A pin board for a look that is still being argued about.
//
// **Why it exists.** His ask, 2026-09-23, for Halcyon: a page "like a
// free-form / Obsidian connecting grid / Milanote-style dynamic page" for the
// references, ideas, cameras and tests they are circling — "how all those
// things interconnect, which ones work for what" — where a reference opens to
// its trailer and stills, and "those stills could be pulled out and connected
// to other things." Not tiles, not a comparison: something to play with.
//
// **What a page has to write.** Cards and the threads between them:
//
//     <section class="bd" data-bd="halcyon-look" data-nolook>
//       <article class="bd-n" id="ycse" data-kind="ref" data-x="-600" data-y="-200"
//                data-obs="0.9" data-cam="mini">
//         <p class="bd-k">A24 · 2026</p>
//         <h3>You Can See Everything</h3>
//         <p class="bd-s">The line on the card.</p>
//         <div class="bd-more"><p>What opens in the panel.</p></div>
//         <iframe src="https://www.youtube.com/embed/…" title="Trailer"></iframe>
//         <figure><img src="pic/…"><figcaption>Through the shelves</figcaption></figure>
//       </article>
//       <ol class="bd-ties">
//         <li data-a="ycse" data-b="observe">the purest version of it</li>
//         <li data-a="mini" data-b="handheld" data-kind="tension">heavy on the shoulder</li>
//       </ol>
//     </section>
//
// With no script that is a readable page: every card in turn, then the list
// of what ties to what. With this script it is a board you can pan and zoom,
// cards that pick up and swing when dragged, threads strung pin to pin, and a
// panel that opens a card whole — its trailer, its stills — from which a still
// can be dragged out and pinned as a card of its own.
//
// **It can start bare.** His note, 2026-09-23, on a first board that came
// with ideas pinned and threads strung: he wants to start "from a place where
// i can do the work of connecting and building things out." So a page may be
// nothing but material (references, clips, stills, gear) with no `.bd-ties`
// at all; the board is built by hand from notes, pulled-out clips and pins.
//
// **Three ways to lay the same board out**, because the question he kept
// asking was two questions:
//
//   - *Free* — where people have put things.
//   - *Observe ↔ Move* — every card slides onto one line between the two
//     styles being reconciled. Drop a card somewhere else on the line and that
//     is now where it sits: the board is where the argument is had.
//   - *A-cam / B-cam* — two wells, the Alexa Mini with the S16 zoom and the
//     FX6, with *Both* between them. Drop a card in a well to give it to that
//     camera. It is the mix-and-match, done by hand.
//
// **Kept in the browser, per person.** A page may carry no script and the
// portal has nowhere yet for a viewer to write, so what is moved, tied, cut
// and noted is kept in this browser's storage under the board's name —
// wrapped, because a private window can refuse it — and *Reset* puts the
// board back as published.
//
// **Looked into, not bound to.** Same as `compare.js`: the page is sealed in
// a shadow root by `made.js` and swapped under `deep.js`, so this finds the
// root fresh each time and leaves anything already built alone. The block
// wears `data-nolook` so `look.js` does not open a lightbox on every card.

// The same file the portal lays changes with, at this deploy's address.
const { diffBoard, applyOps } = await import(new URL(`./boardpatch.js${new URL(import.meta.url).search}`, import.meta.url).href);

const KINDS = {
  ref: { name: "References", w: 300 },
  test: { name: "Tests", w: 300 },
  video: { name: "Videos", w: 300 },
  still: { name: "Stills", w: 230 },
  clip: { name: "Clips", w: 270 },
  shot: { name: "Shots", w: 260 },
  scene: { name: "Scenes", w: 250 },
  location: { name: "Locations", w: 260 },
  day: { name: "Days", w: 230 },
  person: { name: "People", w: 220 },
  doc: { name: "Documents", w: 240 },
  link: { name: "Links", w: 260 },
  idea: { name: "Ideas", w: 235 },
  gear: { name: "Gear", w: 275 },
  note: { name: "Notes", w: 215 },
  heading: { name: "Headings", w: 0 },
};
const PICTURED = new Set(["ref", "test", "video", "shot", "scene", "location", "link", "doc"]);
/** What a shot card shows of itself; its panel shows every field it has. */
const CARD_FIELDS = new Set(["Size", "Angle", "Lens", "Movement", "Support", "Scene", "Day"]);
/** A card with more than a picture and a name to it can be collapsed. */
const foldable = (n) => !["note", "heading", "still", "clip"].includes(n.kind);
/** A card with a picture on it can be shown as the picture alone. */
const bareable = (n) => Boolean(n.el && n.el.querySelector(".bd-cov"));
/** How much bigger or smaller than it was made a card is drawn. */
const MIN_SIZE = 0.3, MAX_SIZE = 5;
const sizeOf = (n) => clamp(Number(n.size) || 1, MIN_SIZE, MAX_SIZE);
const LANES = [
  ["Pictures", ["ref", "test", "video", "still", "clip"]],
  ["From the Film", ["shot", "scene", "location", "day", "person", "doc"]],
  ["Ideas", ["idea"]],
  ["Links", ["link"]],
  ["Gear", ["gear"]],
  ["Notes", ["note"]],
];
const SPAN = 1900;

/**
 * **The sorts — the board's own, not the program's.** His question,
 * 2026-09-24: Halcyon's Observe ↔ Move and A-cam / B-cam were made for that
 * board, so how does a standard board keep that without a settings screen?
 * By having only two kinds of sort — a *line* between two words, and a row of
 * *columns* — and letting each board carry its own: made up by Claude when it
 * builds one, added from the toolbar by anybody who may change it.
 *
 * A sort is `{id, type: "line", name, ends: [l, r], under?}` or
 * `{id, type: "columns", name, cols: [{id, name, sub?, chip?, pick?, tone?}], none?}`.
 * A card's place on a line is 0 (left end) to 1; in columns, a column's id or "".
 *
 * **Halcyon's pair, for a page that says nothing about sorts** and whose
 * cards carry `data-obs` / `data-cam` — the only such page. `LEGACY_SORTS` in
 * `src/boards.js` is the same list, for the MCP. Their values stay where they
 * always were (`obs`, 1 = Observe; `cam`), so nothing saved moves.
 */
const LEGACY_SORTS = [
  {
    id: "obs", type: "line", name: "Observe ↔ Move", short: "Obs ↔ Move",
    ends: ["Observe", "Move"], under: ["still · long lens · from outside", "handheld · following · inside it"],
  },
  {
    id: "cam", type: "columns", name: "A-cam / B-cam", short: "A / B cam", none: "Undecided",
    cols: [
      { id: "mini", name: "A-cam", sub: "Alexa Mini + S16 zoom", chip: "A-CAM", pick: "A · Mini", tone: "gold" },
      { id: "both", name: "Both", sub: "either camera", chip: "A + B", pick: "Both", tone: "ink" },
      { id: "fx6", name: "B-cam", sub: "Sony FX6", chip: "B-CAM", pick: "B · FX6", tone: "steel" },
    ],
  },
];
const TONES = ["gold", "steel", "sage", "rose", "ink"];
const COL_GAP = 1300;

const STYLE = `
.bd.on{--ground:#0C0B0A;--card:#171513;--card2:#1E1B18;--ink:#F3EFE9;--quiet:#9A9189;
  --rule:rgba(243,239,233,.12);--gold:#D9A867;--rose:#E58FA8;--steel:#8FB3C9;--sage:#A9C29A;
  --paper:#EDE3CB;--thread:rgba(217,168,103,.42);--tension:#E07A6A;
  position:relative;display:block;height:min(82vh,900px);min-height:520px;
  background:var(--ground);border-radius:4px;overflow:hidden;border:1px solid var(--rule);
  font-family:RS,system-ui,sans-serif;color:var(--ink);user-select:none;-webkit-user-select:none;
  -webkit-touch-callout:none;touch-action:none}
.bd.on:fullscreen{height:100vh!important;border-radius:0;border:0}
.bd.on > .bd-n,.bd.on > .bd-ties{display:none}
.bd-vp{position:absolute;inset:0;overflow:hidden;cursor:grab}
/* **The dots move; they are not painted again.** Two pixels apart at the
   farthest zoom, a background of dots redrawn on every frame of a pan was
   millions of tiny circles a frame across his screen (2026-09-25). They are a
   sheet of their own now, slid by its layer, and gone when too fine to see. */
.bd-dots{position:absolute;left:0;top:0;right:-80px;bottom:-80px;pointer-events:none;will-change:transform;
  background-image:radial-gradient(circle,rgba(243,239,233,.09) 1px,transparent 1.4px)}
.bd-dots[hidden]{display:none}
.bd-vp.panning{cursor:grabbing}
.bd-vp::after{content:"";position:absolute;inset:0;pointer-events:none;
  background:radial-gradient(ellipse at 50% 40%,transparent 40%,rgba(0,0,0,.55) 100%)}
.bd-world{position:absolute;left:0;top:0;transform-origin:0 0;will-change:transform}
.bd-wires{position:absolute;left:0;top:0;width:1px;height:1px;overflow:visible;pointer-events:none}
.bd-wires path{fill:none}
/* **Threads show on hover.** His notes, 2026-09-23: every thread drawn in
   full is a tangle to anyone who doesn't know what they're looking at, and
   even short tails at rest were too much. So a thread shows only while one
   of its cards is pointed at, opened or picked, growing from each card to
   meet in the middle (its dashes are set in drawTies); *Threads: all* draws
   every one faintly for the whole map. */
.bd-line{stroke:var(--thread);stroke-width:1.5;opacity:.75;stroke-linecap:round;vector-effect:non-scaling-stroke;
  transition:stroke .3s,stroke-width .3s,opacity .3s,stroke-dasharray .55s cubic-bezier(.3,.7,.2,1)}
.bd-line.tension{stroke:rgba(224,122,106,.55)}
.bd-line.user{stroke:rgba(229,143,168,.6)}
.bd.threads-all .bd-line{opacity:.3}
.bd:not(.threads-all) .bd-tie:not(.hot):not(.lit) .bd-line{opacity:0}
.bd:not(.threads-all) .bd-tie:not(.hot):not(.lit) .bd-hit{pointer-events:none}
.bd-hit{stroke:transparent;stroke-width:18;pointer-events:stroke;cursor:pointer}
.bd-lab{font:600 13px RS,system-ui,sans-serif;fill:var(--ink);opacity:0;
  paint-order:stroke;stroke:var(--ground);stroke-width:5px;stroke-linejoin:round;
  transition:opacity .25s;pointer-events:none}
.bd.close.threads-all .bd-lab{opacity:.45}
.bd-tie.hot .bd-line,.bd-tie.lit .bd-line{stroke:var(--gold);stroke-width:2.2;opacity:.95}
.bd-tie.lit:not(.hot) .bd-line{opacity:.6}
.bd-tie.hot .bd-line.tension{stroke:var(--tension)}
.bd-tie.hot .bd-lab{opacity:1}
.bd.focus .bd-tie:not(.hot):not(.lit) .bd-line{opacity:.1}
/* A fade is a sheet of its own for as long as it runs, and a thread's is as
   big as the board it crosses: pointing along a big board's cards was
   dozens of them at once (2026-09-25). There, a thread still grows from its
   cards, but shows and hides without fading. */
.bd.big .bd-line{transition-property:stroke,stroke-width,stroke-dasharray}
.bd.big .bd-lab{transition:none}
.bd.big:not(.threads-all):not(.focus) .bd-tie:not(.hot):not(.lit){display:none}
@keyframes bd-flow{to{stroke-dashoffset:-32}}
.bd-drawing{stroke:var(--rose);stroke-width:2;stroke-dasharray:4 6;animation:bd-flow .8s linear infinite}

/* **A card is painted with the board, not held as a picture of its own.**
   His report, 2026-09-25: on the Call Her Back board (~390 cards) the whole
   portal flickered and went black in patches when the mouse moved — the
   sidebar too. Every card was its own compositor layer (\`will-change\`, and a
   blur on its way in), every thread label that crossed one was forced into a
   layer the size of the board, and every hover faded all the others, which
   makes a layer of each while it fades: 640 layers, billions of pixels, more
   than a graphics chip holds. So a card is a layer only while it is being
   dragged; it arrives with a fade, never a blur; and dimming is instant. */
.bd-n{position:absolute;left:0;top:0;box-sizing:border-box;background:var(--card);
  border:1px solid rgba(243,239,233,.1);border-radius:6px;cursor:pointer;
  box-shadow:0 10px 30px rgba(0,0,0,.45),0 1px 0 rgba(255,255,255,.04) inset;
  transition:box-shadow .25s,border-color .25s;
  animation:bd-in .5s ease-out both}
@keyframes bd-in{from{opacity:0}to{opacity:1}}
.bd.big .bd-n{animation:none}
/* **Far out on a big board, a card is its picture.** Nothing on it could be
   read at that size, and every word and shadow was paint for all four hundred
   cards at once. The same size stays, so nothing moves; headings keep their
   words, which is what they are for. */
.bd.lod .bd-n{box-shadow:none;border-color:transparent;transition:none}
.bd.lod .bd-n .bd-pin,.bd.lod .bd-n .bd-x,.bd.lod .bd-loop{visibility:hidden}
/* **A card keeps its name and his words until they are too small to be
   anything.** His note, 2026-09-25: "text disappears too easily when zooming
   out on the boards, and it makes them look like blank cards" — every word
   went at 28%, where a title is still a readable line. Far out only the small
   print goes (kickers, captions, fields, the footer); the title and his own
   note stay until 12%, where they are two pixels high. */
.bd.lod .bd-n .bd-b > :not(h3):not(.bd-t){visibility:hidden}
.bd.mute .bd-n .bd-b{visibility:hidden}
.bd-n.lift{box-shadow:0 30px 60px rgba(0,0,0,.6);cursor:grabbing;border-color:rgba(243,239,233,.28);will-change:transform}
.bd-n.hot{border-color:rgba(217,168,103,.6)}
.bd.focus .bd-n:not(.hot):not(.near){opacity:.28}
.bd-n.sel{border-color:var(--gold);box-shadow:0 0 0 1px var(--gold),0 20px 50px rgba(0,0,0,.6)}
.bd-pin{position:absolute;left:50%;top:-7px;width:14px;height:14px;margin-left:-7px;border-radius:50%;
  background:radial-gradient(circle at 35% 30%,#fff5 0,transparent 45%),var(--pc,var(--gold));
  box-shadow:0 3px 6px rgba(0,0,0,.6);cursor:crosshair;z-index:2;transition:transform .15s}
.bd-pin:hover{transform:scale(1.35)}
.bd-pin::before{content:"";position:absolute;inset:-16px;border-radius:50%}
.bd.far .bd-pin{transform:scale(2)}
.bd-cov{display:block;width:100%;height:auto;border-radius:0;
  background:#000;pointer-events:none}
.bd-n:has(.bd-cov){border-radius:0}
.bd-b{padding:14px 16px 14px}
.bd-n h3{margin:0;font-size:19px;line-height:1.15;font-weight:600;letter-spacing:-.005em}
.bd-k{margin:0 0 6px;font-size:10px;letter-spacing:.18em;text-transform:uppercase;color:var(--kc,var(--gold))}
.bd-s{margin:8px 0 0;font-size:13px;line-height:1.45;color:#CFC7BE}
.bd-meta{margin:10px 0 0;font-size:11px;letter-spacing:.06em;color:var(--quiet)}
.bd-ft{display:flex;align-items:center;gap:10px;margin-top:12px}
.bd-cam{font-size:10px;font-weight:600;letter-spacing:.1em;padding:3px 7px;border-radius:99px;
  border:1px solid var(--rule);color:var(--quiet);white-space:nowrap}
.bd-cam.t-gold{color:var(--gold);border-color:rgba(217,168,103,.45)}
.bd-cam.t-steel{color:var(--steel);border-color:rgba(143,179,201,.45)}
.bd-cam.t-sage{color:var(--sage);border-color:rgba(169,194,154,.45)}
.bd-cam.t-rose{color:var(--rose);border-color:rgba(229,143,168,.45)}
.bd-cam.t-ink{color:var(--ink);border-color:rgba(243,239,233,.35)}
.bd-meter{flex:1;height:3px;border-radius:3px;position:relative;
  background:linear-gradient(90deg,rgba(217,168,103,.5),rgba(229,143,168,.5))}
.bd-meter i{position:absolute;top:50%;width:9px;height:9px;margin:-4.5px 0 0 -4.5px;border-radius:50%;
  background:var(--ink);box-shadow:0 0 0 2px var(--card)}
.bd-n[data-read]::after{content:attr(data-read);position:absolute;left:50%;bottom:-34px;transform:translateX(-50%);
  font-size:12px;font-weight:600;letter-spacing:.06em;white-space:nowrap;color:var(--ground);
  background:var(--gold);padding:5px 10px;border-radius:99px}
.bd-x{position:absolute;top:6px;right:6px;width:22px;height:22px;border-radius:50%;border:0;
  background:rgba(0,0,0,.55);color:var(--ink);font:14px/22px system-ui;cursor:pointer;opacity:0;
  transition:opacity .2s;z-index:3;padding:0}
.bd-n:hover .bd-x{opacity:1}

.bd-n.k-ref{--pc:var(--gold)}
.bd-n.k-test{--pc:var(--sage);--kc:var(--sage)}
.bd-n.k-idea{--pc:var(--ink);--kc:var(--quiet);background:transparent;border:1px solid rgba(243,239,233,.28);
  box-shadow:none;backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px)}
.bd-n.k-idea h3{font-size:24px;font-weight:600}
.bd-n.k-scene{--pc:var(--rose);--kc:var(--rose);background:linear-gradient(160deg,#2A1A20,#1A1315)}
.bd-n.k-gear{--pc:var(--steel);--kc:var(--steel);background:linear-gradient(160deg,#18202A,#131619)}
.bd-n.k-gear h3{font-size:21px}
.bd-spec{margin:10px 0 0;padding:0;list-style:none;font-size:12px;line-height:1.5;color:#B9C4CC}
.bd-spec li{display:flex;gap:8px}.bd-spec li::before{content:"—";color:var(--steel)}
.bd-n.k-still{--pc:var(--rose);padding:6px 6px 0;background:#F1ECE4;color:#111;border-color:transparent}
.bd-n.k-still .bd-cov{border-radius:0}
.bd-n.k-still .bd-b{padding:8px 4px 10px}
.bd-n.k-still .bd-s{color:#333;margin:0;font-size:12px}
.bd-n.k-still .bd-k{color:#8A5A64}
.bd-n.k-still .bd-ft{display:none}
.bd-n.k-clip{--pc:var(--rose);padding:6px 6px 0;background:#0A0908;border-color:rgba(243,239,233,.2)}
.bd-n.k-clip .bd-cov{border-radius:0}
.bd-n.k-clip .bd-b{padding:8px 4px 10px}
.bd-n.k-clip .bd-s{margin:0;font-size:12px}
.bd-n.k-clip .bd-k{color:var(--rose)}
.bd-n.k-clip .bd-ft{display:none}
.bd-loop{position:absolute;top:12px;left:12px;font-size:9px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;
  background:rgba(0,0,0,.6);color:var(--ink);padding:3px 6px;border-radius:2px;pointer-events:none}
.bd-loop::before{content:"";display:inline-block;width:6px;height:6px;border-radius:50%;background:#E0584A;
  margin-right:5px;vertical-align:1px;animation:bd-rec 1.6s ease-in-out infinite}
@keyframes bd-rec{50%{opacity:.25}}
.bd-st video{display:block;width:100%;height:auto;pointer-events:none}
.bd-st .bd-cap{position:absolute;left:0;right:0;bottom:0;padding:14px 6px 5px;font-size:10px;line-height:1.3;color:var(--ink);
  background:linear-gradient(transparent,rgba(0,0,0,.8));opacity:0;transition:opacity .2s;pointer-events:none}
.bd-st:hover .bd-cap{opacity:1}
.bd-st.clip::after{display:none}
.bd-note{display:block;width:100%;box-sizing:border-box;margin-top:14px;min-height:64px;resize:vertical;
  font:14px/1.5 RS,system-ui,sans-serif;color:var(--ink);background:rgba(243,239,233,.04);
  border:1px solid var(--rule);border-radius:6px;padding:10px 12px;outline:none}
.bd-note:focus{border-color:rgba(217,168,103,.5)}
.bd-players{display:flex;flex-direction:column;gap:6px}
.bd-player button{width:100%;text-align:left;font:600 13px RS,system-ui,sans-serif;color:var(--ink);background:transparent;
  border:1px solid var(--rule);border-radius:6px;padding:10px 12px;cursor:pointer}
.bd-player button.on{border-color:var(--gold);color:var(--gold)}
.bd-n .bd-t{font-size:13px;min-height:0;margin-top:8px;color:#CFC7BE}
.bd-n.k-note .bd-t{font-size:15px;min-height:44px;margin-top:0;color:inherit}
.bd-n.k-still .bd-t{color:#333}
.bd-sub{margin:16px 0 8px;font-size:12px;font-weight:600;color:var(--ink)}
.bd-stills{grid-template-columns:repeat(3,1fr)}
.bd-big video{max-width:100%;max-height:calc(100% - 40px)}
.bd-n.k-note{--pc:var(--rose);background:var(--paper);color:#1B1712;border-color:transparent}
.bd-n.k-note .bd-k{color:#8A5A64}
.bd-t{margin:0;font-size:15px;line-height:1.4;min-height:44px;outline:none;cursor:text;
  user-select:text;-webkit-user-select:text;white-space:pre-wrap}
.bd-t:empty::before{content:attr(data-ph);color:#8C8274}
.bd-n.k-note .bd-ft{display:none}
.bd-n.picked{outline:2px solid var(--rose);outline-offset:5px}
.bd.linking .bd-vp{cursor:crosshair}
.bd.linking .bd-n:not(.picked):hover{outline:2px dashed var(--gold);outline-offset:5px}
.bd-vp.selecting{cursor:crosshair}
.bd-marq{position:absolute;z-index:15;pointer-events:none;border:1px dashed var(--rose);background:rgba(229,143,168,.08);border-radius:2px}
.bd-n.k-heading{background:transparent;border:0;box-shadow:none;padding:0 4px;--pc:var(--ink)}
.bd-n.k-heading .bd-pin{opacity:0;transition:opacity .2s}
.bd-n.k-heading:hover .bd-pin,.bd-n.k-heading.hot .bd-pin{opacity:1}
.bd-hd{font:600 64px/1.05 RS,system-ui,sans-serif;letter-spacing:-.015em;color:var(--ink);white-space:pre;
  min-width:160px;outline:none;padding:6px 2px 10px;border-bottom:2px solid rgba(243,239,233,.16)}
.bd-hd:empty::before{content:attr(data-ph);color:rgba(243,239,233,.28)}
.bd-hd[contenteditable=true]{cursor:text;border-bottom-color:var(--gold);user-select:text;-webkit-user-select:text}
.bd[data-mode=line] .k-heading,.bd[data-mode=columns] .k-heading{opacity:.08!important;pointer-events:none}
.bd-selbar{position:absolute;left:50%;bottom:16px;z-index:26;display:flex;flex-wrap:wrap;gap:10px 14px;align-items:center;
  max-width:calc(100% - 24px);box-sizing:border-box;padding:10px 12px;border-radius:14px;
  background:rgba(20,18,16,.95);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);
  border:1px solid rgba(229,143,168,.4);box-shadow:0 20px 50px rgba(0,0,0,.55);
  transform:translate(-50%,24px);opacity:0;pointer-events:none;transition:opacity .25s,transform .3s cubic-bezier(.2,.8,.2,1)}
.bd.picking .bd-selbar{opacity:1;transform:translate(-50%,0);pointer-events:auto}
.bd-selbar{bottom:72px!important}
.bd-selcount{font-size:12px;font-weight:600;letter-spacing:.06em;color:var(--rose);white-space:nowrap}
.bd-selbar .bd-range{min-width:220px}
.bd-selbar button{font:600 12px RS,system-ui,sans-serif;color:var(--quiet);background:transparent;
  border:1px solid var(--rule);border-radius:99px;padding:7px 12px;cursor:pointer;white-space:nowrap}
.bd-selbar .bd-mix button.on{background:var(--ink);color:#111;border-color:var(--ink)}
.bd-selbar .bd-act2{color:var(--ink)}
.bd-selbar .warn{color:var(--tension);border-color:rgba(224,122,106,.45)}
.bd-tools button.on{background:var(--ink);color:#111}
.bd-tools button[hidden]{display:none}
.bd-sync{display:flex;align-items:center;gap:7px;font-size:11px;letter-spacing:.04em;color:var(--quiet);padding:0 8px;white-space:nowrap}
.bd-sync::before{content:"";width:7px;height:7px;border-radius:50%;background:var(--gold);flex:0 0 auto}
.bd-sync.ok{font-size:0;padding:0 6px}
.bd-sync.ok::before{background:var(--sage)}
.bd-sync.warn{color:var(--tension)}
.bd-sync.warn::before{background:var(--tension)}
.bd-hist{display:flex;flex-direction:column;gap:8px;margin-top:18px}
.bd-hrow{display:flex;align-items:center;gap:12px;border:1px solid var(--rule);border-radius:8px;padding:10px 12px}
.bd-htext{flex:1;display:flex;flex-direction:column;gap:3px;min-width:0}
.bd-htext b{font-size:14px;font-weight:600}
.bd-htext span{font-size:12px;color:var(--quiet);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bd-hrow button{font:600 12px RS,system-ui,sans-serif;color:var(--ink);background:transparent;border:1px solid var(--rule);
  border-radius:99px;padding:7px 12px;cursor:pointer;white-space:nowrap}
.bd-n.missing{border-style:dashed;border-color:rgba(229,143,168,.55)}
.bd.hide-ref .k-ref,.bd.hide-test .k-test,.bd.hide-idea .k-idea,.bd.hide-scene .k-scene,
.bd.hide-gear .k-gear,.bd.hide-still .k-still,.bd.hide-clip .k-clip,.bd.hide-note .k-note,
.bd.hide-video .k-video,.bd.hide-shot .k-shot,.bd.hide-location .k-location,.bd.hide-day .k-day,
.bd.hide-person .k-person,.bd.hide-doc .k-doc,.bd.hide-link .k-link,.bd.hide-heading .k-heading{opacity:.07!important;pointer-events:none}

.bd-guides{position:absolute;left:0;top:0;pointer-events:none}
.bd-g{position:absolute;opacity:0;transition:opacity .6s}
.bd[data-mode=line] .bd-g.spec,.bd[data-mode=columns] .bd-g.cams{opacity:1}
.bd-track{height:4px;border-radius:4px;background:linear-gradient(90deg,var(--gold),#6d6258 50%,var(--rose))}
.bd-track b{position:absolute;top:-62px;font-size:40px;letter-spacing:.2em;font-weight:600;text-transform:uppercase}
.bd-track b.l{left:0;color:var(--gold)}.bd-track b.r{right:0;color:var(--rose)}
.bd-track span{position:absolute;top:18px;font-size:15px;color:var(--quiet);letter-spacing:.04em}
.bd-track span.l{left:0}.bd-track span.r{right:0}
.bd-lane{font-size:15px;letter-spacing:.24em;text-transform:uppercase;color:rgba(243,239,233,.28);white-space:nowrap}
.bd-well{border-radius:36px;border:1px dashed rgba(243,239,233,.18);
  background:radial-gradient(circle,rgba(243,239,233,.05),transparent 70%);transition:border-color .3s,background .3s}
.bd-well.t-gold{border-color:rgba(217,168,103,.35);background:radial-gradient(circle,rgba(217,168,103,.09),transparent 70%)}
.bd-well.t-steel{border-color:rgba(143,179,201,.35);background:radial-gradient(circle,rgba(143,179,201,.09),transparent 70%)}
.bd-well.t-sage{border-color:rgba(169,194,154,.35);background:radial-gradient(circle,rgba(169,194,154,.09),transparent 70%)}
.bd-well.t-rose{border-color:rgba(229,143,168,.35);background:radial-gradient(circle,rgba(229,143,168,.09),transparent 70%)}
.bd-well.hot{border-style:solid;border-width:2px}
.bd-well b{position:absolute;left:0;right:0;top:-104px;text-align:center;font-size:44px;letter-spacing:.14em;
  text-transform:uppercase;font-weight:600}
.bd-well.t-gold b{color:var(--gold)}.bd-well.t-steel b{color:var(--steel)}.bd-well.t-sage b{color:var(--sage)}.bd-well.t-rose b{color:var(--rose)}
.bd-well span{position:absolute;left:0;right:0;top:-48px;text-align:center;font-size:17px;color:var(--quiet)}
.bd-undec{font-size:15px;letter-spacing:.24em;text-transform:uppercase;color:rgba(243,239,233,.3);
  border-top:1px dashed rgba(243,239,233,.18);padding-top:12px}

.bd-bar{position:absolute;left:12px;right:12px;top:12px;display:flex;gap:10px;align-items:center;
  flex-wrap:nowrap;z-index:32;pointer-events:none}
.bd-seg .sm{display:none}
.bd-right{display:flex;gap:6px;align-items:center;margin-left:auto}
.bd-faces{display:flex;align-items:center}
.bd-faces:empty{display:none}
.bd-face{width:24px;height:24px;border-radius:50%;background:var(--hc);color:#0C0B0A;font-size:10px;font-weight:600;letter-spacing:.02em;
  display:flex;align-items:center;justify-content:center;border:2px solid var(--ground);margin-left:-6px;cursor:default}
.bd-face:first-child{margin-left:0}
.bd-face.more{background:var(--card2);color:var(--ink)}
.bd-cursors{position:absolute;left:0;top:0;width:1px;height:1px;overflow:visible;pointer-events:none;z-index:100000}
.bd-cur{position:absolute;left:0;top:0;transform-origin:0 0;transition:transform .09s linear;pointer-events:none}
.bd-cur i{position:absolute;left:0;top:0;width:0;height:0;border-left:7px solid var(--hc);border-top:7px solid var(--hc);
  border-right:7px solid transparent;border-bottom:7px solid transparent;border-top-left-radius:2px}
.bd-cur span{position:absolute;left:11px;top:11px;background:var(--hc);color:#0C0B0A;font-size:11px;font-weight:600;
  padding:2px 7px;border-radius:9px;white-space:nowrap}
.bd-n.held{outline:2px solid var(--hc);outline-offset:4px}
.bd-mwrap{position:relative}
.bd-mbtn{font:600 12px RS,system-ui,sans-serif!important;color:var(--ink)!important;padding:8px 13px!important;
  background:rgba(20,18,16,.82)!important;backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);
  border:1px solid var(--rule)!important;border-radius:99px!important}
.bd-mwrap.on .bd-mbtn{background:var(--ink)!important;color:#111!important}
.bd-menu{position:absolute;top:calc(100% + 8px);right:0;min-width:240px;display:none;flex-direction:column;gap:1px;
  padding:6px;border-radius:12px;background:rgba(20,18,16,.97);border:1px solid var(--rule);
  box-shadow:0 20px 50px rgba(0,0,0,.55);z-index:40}
.bd-mwrap.on .bd-menu{display:flex}
.bd-menu button{display:flex!important;align-items:center;gap:8px;width:100%;text-align:left;border-radius:8px!important;
  padding:9px 10px!important;color:var(--ink)!important;background:transparent!important;font-weight:500!important}
.bd-menu button:hover{background:rgba(243,239,233,.07)!important}
.bd-menu button[hidden]{display:none!important}
.bd-menu button i{width:8px;height:8px;border-radius:50%;background:var(--c)}
.bd-menu button.off{opacity:.4;text-decoration:line-through}
.bd-menu .danger{color:var(--tension)!important}
.bd-menu hr{border:0;border-top:1px solid var(--rule);margin:5px 4px;width:calc(100% - 8px)}
.bd-mh{margin:6px 10px 4px;font-size:10px;letter-spacing:.16em;text-transform:uppercase;color:var(--quiet)}
.bd-mtip{margin:4px 10px 6px;font-size:11px;line-height:1.5;color:var(--quiet);max-width:240px}
.bd-dock{position:absolute;left:50%;bottom:14px;transform:translateX(-50%);z-index:22;display:flex;align-items:center;gap:2px;
  padding:4px;border-radius:14px;background:rgba(20,18,16,.9);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);
  border:1px solid var(--rule);box-shadow:0 14px 34px rgba(0,0,0,.45)}
.bd-dock button{font:600 12px RS,system-ui,sans-serif;color:var(--ink);background:transparent;border:0;border-radius:10px;
  padding:9px 12px;cursor:pointer;white-space:nowrap}
.bd-dock button:hover{background:rgba(243,239,233,.08)}
.bd-dock button.on{background:var(--ink);color:#111}
.bd-sep{width:1px;align-self:stretch;margin:6px 4px;background:var(--rule)}
.bd-bar > *{pointer-events:auto}
.bd-seg,.bd-tools,.bd-legend{display:flex;gap:2px;padding:3px;border-radius:99px;
  background:rgba(20,18,16,.82);backdrop-filter:blur(10px);-webkit-backdrop-filter:blur(10px);
  border:1px solid var(--rule)}
.bd-bar button{font:600 12px RS,system-ui,sans-serif;letter-spacing:.04em;color:var(--quiet);
  background:transparent;border:0;border-radius:99px;padding:7px 12px;cursor:pointer;white-space:nowrap;
  transition:background .2s,color .2s}
.bd-bar button:hover{color:var(--ink)}
.bd-seg button.on{background:var(--ink);color:#111}
.bd-legend button{display:flex;align-items:center;gap:6px;padding:7px 10px}
.bd-legend button i{width:8px;height:8px;border-radius:50%;background:var(--c)}
.bd-legend button.off{opacity:.4;text-decoration:line-through}
.bd-tools{margin-left:auto}
.bd-hint{position:absolute;left:14px;bottom:12px;z-index:20;font-size:11px;letter-spacing:.05em;color:var(--quiet);
  pointer-events:none;transition:opacity .6s;max-width:calc(100% - 28px)}
.bd-zoom{position:absolute;right:14px;bottom:12px;z-index:20;display:flex;gap:2px;padding:3px;border-radius:99px;
  background:rgba(20,18,16,.82);border:1px solid var(--rule)}
.bd-zoom button{font:600 15px system-ui;color:var(--quiet);background:none;border:0;width:30px;height:28px;
  border-radius:99px;cursor:pointer}
.bd-zoom button:hover{color:var(--ink)}

/* **Below the toolbar, and never over it.** His note, 2026-09-24: the side
   panel covered the toolbar and its × scrolled away. It floats under the top
   bar now, and the × rides the top of it however far it is scrolled. */
.bd-loupe{position:absolute;top:62px;right:10px;bottom:10px;width:min(440px,calc(100% - 20px));z-index:30;box-sizing:border-box;
  background:rgba(16,14,13,.95);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px);border-radius:14px;
  border:1px solid var(--rule);box-shadow:0 24px 60px rgba(0,0,0,.5);
  transform:translateX(calc(100% + 24px));transition:transform .45s cubic-bezier(.2,.8,.2,1);
  overflow-y:auto;overscroll-behavior:contain;padding:22px 24px 40px;user-select:text;-webkit-user-select:text;touch-action:pan-y}
.bd.loupe-on .bd-loupe{transform:none}
.bd-loupe h2{margin:6px 0 0;font-size:30px;line-height:1.08;font-weight:600;padding-right:34px}
.bd-loupe .bd-lead{font-size:15px;line-height:1.5;color:#DDD5CB;margin:12px 0 0}
.bd-loupe .bd-body{font-size:14px;line-height:1.6;color:#C3BBB2}
.bd-loupe .bd-body p{margin:12px 0 0}
.bd-loupe .bd-body ul{margin:10px 0 0;padding-left:18px}
.bd-lhead{position:sticky;top:-12px;height:0;z-index:5}
.bd-close{position:absolute;top:0;right:-10px;width:34px;height:34px;border-radius:50%;border:1px solid var(--rule);
  background:rgba(22,20,18,.96);color:var(--ink);font:18px/32px system-ui;cursor:pointer;padding:0;
  box-shadow:0 6px 16px rgba(0,0,0,.45)}
.bd-h{margin:26px 0 10px;font-size:10px;letter-spacing:.2em;text-transform:uppercase;color:var(--quiet)}
.bd-play{position:relative;aspect-ratio:16/9;background:#000;border-radius:0;overflow:hidden;margin-top:10px}
.bd-play iframe{position:absolute;inset:0;width:100%;height:100%;border:0}
.bd-stills{display:grid;grid-template-columns:1fr 1fr;gap:6px;align-items:start}
.bd-st{position:relative;cursor:grab;border-radius:0;overflow:hidden;background:#000;touch-action:none}
.bd-st img{display:block;width:100%;height:auto;pointer-events:none;transition:transform .3s}
.bd-st:hover img{transform:scale(1.04)}
.bd-st::after{content:"drag out";position:absolute;right:5px;bottom:5px;font-size:9px;letter-spacing:.1em;
  text-transform:uppercase;background:rgba(0,0,0,.6);color:var(--ink);padding:2px 5px;border-radius:2px;opacity:0;transition:opacity .2s}
.bd-st:hover::after{opacity:1}
.bd-mix{display:flex;flex-wrap:wrap;gap:4px}
.bd-mix button,.bd-act,.bd-tied button{font:600 12px RS,system-ui,sans-serif;color:var(--quiet);background:transparent;
  border:1px solid var(--rule);border-radius:99px;padding:7px 12px;cursor:pointer}
.bd-mix button.on{background:var(--ink);color:#111;border-color:var(--ink)}
.bd-range{display:flex;align-items:center;gap:10px;font-size:11px;letter-spacing:.12em;text-transform:uppercase}
.bd-range b{font-weight:600}.bd-range b.l{color:var(--gold)}.bd-range b.r{color:var(--rose)}
.bd-range input{flex:1;accent-color:var(--gold)}
.bd-tied{display:flex;flex-direction:column;gap:6px}
.bd-tied button{display:flex;gap:10px;text-align:left;border-radius:6px;padding:9px 12px;color:var(--ink)}
.bd-tied button span{color:var(--quiet);font-weight:500}
.bd-tied button.tension{border-color:rgba(224,122,106,.4)}
.bd-act{margin-top:24px}
.bd-big{position:absolute;inset:0;z-index:40;background:rgba(8,7,6,.94);display:flex;flex-direction:column;
  align-items:center;justify-content:center;padding:28px;box-sizing:border-box;cursor:zoom-out;animation:bd-fade .3s}
.bd-big img{max-width:100%;max-height:calc(100% - 40px);object-fit:contain}
.bd-big p{margin:12px 0 0;font-size:13px;color:var(--quiet)}
@keyframes bd-fade{from{opacity:0}}
.bd-ghost{position:fixed;z-index:100;width:200px;pointer-events:none;border:4px solid #F1ECE4;border-bottom-width:16px;
  box-shadow:0 30px 60px rgba(0,0,0,.6);transform:translate(-50%,-50%) rotate(-3deg)}
.bd-ghost img{display:block;width:100%}
.bd-pop{position:absolute;z-index:35;display:none;gap:6px;align-items:center;padding:6px;border-radius:10px;
  background:rgba(20,18,16,.96);border:1px solid var(--rule);box-shadow:0 20px 40px rgba(0,0,0,.5);
  transform:translate(-50%,calc(-100% - 12px))}
.bd-pop.on{display:flex}
.bd-pop input{font:14px RS,system-ui,sans-serif;background:#0C0B0A;color:var(--ink);border:1px solid var(--rule);
  border-radius:6px;padding:7px 9px;width:220px;outline:none}
.bd-pop button{font:600 12px RS,system-ui,sans-serif;border:0;border-radius:6px;padding:8px 10px;cursor:pointer;
  background:var(--ink);color:#111}
.bd-pop button.cut{background:transparent;color:var(--tension);border:1px solid rgba(224,122,106,.5)}

/* ---- the kinds a board of any film holds (2026-09-25) ---- */
.bd-n.k-video{--pc:var(--rose);--kc:var(--rose)}
.bd [hidden]{display:none!important}
.bd-n.k-link{--pc:var(--steel);--kc:var(--steel)}
.bd-n.k-link h3,.bd-n.k-doc h3{font-size:16px}
.bd-n.k-shot{--pc:var(--gold);--kc:var(--gold);background:linear-gradient(160deg,#211B14,#161310)}
.bd-n.k-shot h3,.bd-n.k-scene h3,.bd-n.k-location h3{font-size:17px}
.bd-n.k-location{--pc:var(--sage);--kc:var(--sage);background:linear-gradient(160deg,#1A2019,#131612)}
.bd-n.k-day{--pc:var(--steel);--kc:var(--steel);background:linear-gradient(160deg,#18202A,#131619)}
.bd-n.k-day h3{font-size:24px}
.bd-n.k-person{--pc:var(--paper);--kc:var(--quiet)}
.bd-n.k-person h3{font-size:18px}
.bd-n.k-doc{--pc:var(--paper);--kc:var(--quiet)}
.bd-facts{margin:8px 0 0;padding:0;list-style:none;display:flex;flex-wrap:wrap;gap:4px 10px;font-size:11px;letter-spacing:.04em;color:var(--quiet)}
.bd-open{display:inline-block;margin-top:16px;font:600 12px RS,system-ui,sans-serif;color:var(--ink);text-decoration:none;
  border:1px solid var(--rule);border-radius:99px;padding:8px 14px}
.bd-open:hover{border-color:var(--gold);color:var(--gold)}
.bd-said{font-size:14px;line-height:1.55;color:#C3BBB2;white-space:pre-wrap;margin:12px 0 0}

/* the empty board: one line and the ways in */
.bd-empty{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);z-index:12;display:flex;flex-direction:column;
  align-items:center;gap:16px;text-align:center;pointer-events:none}
.bd-empty p{margin:0;font-size:15px;color:var(--quiet)}
.bd-empty div{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;pointer-events:auto}
.bd-empty button{font:600 13px RS,system-ui,sans-serif;color:var(--ink);background:rgba(20,18,16,.9);
  border:1px solid var(--rule);border-radius:99px;padding:10px 16px;cursor:pointer}
.bd-empty button:hover{border-color:var(--gold)}
.bd.has-cards .bd-empty{display:none}

/* adding: the dock's menu, the address box, the drop veil */
.bd-dock .bd-mwrap .bd-menu{top:auto;bottom:calc(100% + 10px);right:auto;left:0}
.bd-dock .bd-mbtn{background:transparent!important;border:0!important;border-radius:10px!important;padding:9px 12px!important}
.bd-veil{position:absolute;inset:0;z-index:45;display:none;align-items:center;justify-content:center;
  background:rgba(12,11,10,.72);border:2px dashed var(--gold);border-radius:4px;font-size:18px;color:var(--ink);pointer-events:none}
.bd.dropping .bd-veil{display:flex}
.bd-busy{position:absolute;left:50%;top:64px;transform:translateX(-50%);z-index:33;font-size:12px;color:var(--ink);
  background:rgba(20,18,16,.92);border:1px solid var(--rule);border-radius:99px;padding:7px 14px;display:none}
.bd-busy.on{display:block}

/* who may open it */
.bd-share .bd-mbtn{white-space:nowrap}
.bd-menu button.on{color:var(--gold)!important}

/* From the Film */
.bd-tabs{display:flex;flex-wrap:wrap;gap:4px;margin:16px 0 4px}
.bd-tabs button{font:600 12px RS,system-ui,sans-serif;color:var(--quiet);background:transparent;border:1px solid var(--rule);
  border-radius:99px;padding:6px 11px;cursor:pointer}
.bd-tabs button.on{background:var(--ink);color:#111;border-color:var(--ink)}
.bd-find{display:block;width:100%;box-sizing:border-box;margin:10px 0 4px;font:14px RS,system-ui,sans-serif;color:var(--ink);
  background:rgba(243,239,233,.04);border:1px solid var(--rule);border-radius:8px;padding:9px 12px;outline:none}
.bd-rows{display:flex;flex-direction:column;gap:6px;margin-top:8px}
.bd-row{display:flex;align-items:center;gap:10px;border:1px solid var(--rule);border-radius:8px;padding:8px;cursor:grab;
  background:rgba(243,239,233,.02);touch-action:none}
.bd-row:hover{border-color:rgba(217,168,103,.5)}
.bd-row img{width:64px;height:40px;object-fit:cover;border-radius:0;flex:0 0 auto;background:#000;pointer-events:none}
.bd-row .bd-rt{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px;pointer-events:none}
.bd-row b{font-size:13px;font-weight:600;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bd-row span{font-size:11px;color:var(--quiet);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.bd-row .bd-plus{flex:0 0 auto;font:600 16px system-ui;color:var(--quiet);background:none;border:0;cursor:pointer;padding:4px 8px;pointer-events:auto}
.bd-wall{display:grid;grid-template-columns:repeat(3,1fr);gap:5px;margin-top:8px}
/* **The Add panel's head stays put.** His note, 2026-09-25: the title and the
   tabs scrolled away with the list, while the × stayed. The whole head rides
   the top now, over a ground of its own. */
.bd-fhead{position:sticky;top:-22px;z-index:4;margin:-22px -24px 0;padding:22px 24px 10px;
  background:#12100F;border-bottom:1px solid var(--rule)}
.bd-fhead .bd-find{margin-bottom:0}
.bd-fpick{display:flex;align-items:center;gap:8px;margin-top:10px;font-size:12px;color:var(--rose)}
.bd-fpick b{font-weight:600;margin-right:auto}
.bd-fpick button{font:600 12px RS,system-ui,sans-serif;color:var(--ink);background:transparent;border:1px solid var(--rule);
  border-radius:99px;padding:6px 11px;cursor:pointer}
.bd-fpick button.go{background:var(--ink);color:#111;border-color:var(--ink)}
/* Pictures in the panel keep one shape each, so a picture not yet fetched
   still takes its room — and only the ones scrolled to are fetched. */
.bd-wall .bd-st{aspect-ratio:4/3}
.bd-wall .bd-st img,.bd-wall .bd-st video{width:100%;height:100%;object-fit:cover}
.bd-wall .bd-st video{position:absolute;inset:0}
.bd-wall .bd-st.clip::before{content:"";position:absolute;left:6px;top:6px;width:7px;height:7px;border-radius:50%;
  background:#E0584A;box-shadow:0 0 0 2px rgba(0,0,0,.5);z-index:1}
.bd-st.fp,.bd-row.fp{outline:2px solid var(--rose);outline-offset:1px}
.bd-row.fp{border-color:var(--rose)}
.bd-ghost.many::after{content:attr(data-n);position:absolute;right:-12px;top:-12px;min-width:26px;height:26px;border-radius:13px;
  background:var(--rose);color:#111;font:600 13px/26px RS,system-ui,sans-serif;text-align:center;padding:0 6px;box-sizing:border-box}

/* **A shot, shown as a shot.** His note, 2026-09-25: one small line of
   facts was not enough. Label and value, the way the shot list says them. */
.bd-fields{display:grid;grid-template-columns:auto 1fr;gap:3px 12px;margin:10px 0 0;font-size:12px;line-height:1.35}
.bd-fields dt{color:var(--quiet);letter-spacing:.04em}
.bd-fields dd{margin:0;color:var(--ink);min-width:0;overflow-wrap:anywhere}
.bd-loupe .bd-fields{font-size:14px;gap:8px 18px;margin-top:16px}
.bd-n .bd-t[hidden]{display:none}
/* **Collapsed: its picture, what it is, its name.** His ask, 2026-09-25: a
   shot or anything with a lot of detail should fold small so the board
   doesn't fill with tall cards. A note he wrote on it stays. */
.bd-n.folded .bd-s,.bd-n.folded .bd-fields,.bd-n.folded .bd-facts,.bd-n.folded .bd-spec,
.bd-n.folded .bd-meta,.bd-n.folded .bd-ft{display:none}
.bd-n.folded img.bd-cov{max-height:150px;object-fit:cover}
.bd-n.folded .bd-b{padding-bottom:12px}
.bd-n.folded h3{display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
/* **Picture Only: the picture, and no card around it.** His ask, 2026-09-25:
   the option to drop the sticky-note feel and just show the image. No paper,
   no edge, no tilt (\`place\`); the pin shows only when pointed at, so a
   thread can still be tied from it. Picked, held or lit, it still says so. */
.bd-n.bare{background:transparent;border-color:transparent;box-shadow:none;border-radius:0}
.bd-n.bare .bd-b,.bd-n.bare .bd-loop{display:none}
.bd-n.bare .bd-cov{border-radius:0}
.bd-n.bare.folded img.bd-cov{max-height:none}
.bd-n.bare .bd-pin{visibility:hidden}
.bd-n.bare:hover .bd-pin,.bd-n.bare.sel .bd-pin{visibility:visible}
.bd-n.bare.hot{border-color:rgba(217,168,103,.6)}
.bd-n.bare.sel{border-color:var(--gold);box-shadow:0 0 0 1px var(--gold)}
.bd-n.bare.lift{box-shadow:0 30px 60px rgba(0,0,0,.6)}
/* **Any card, any size.** His ask, 2026-09-25 — words included, so the whole
   card grows: \`size\` scales it in \`place\`, from its top-left corner as the
   handle is dragged. The pin, × and the handle stay their own size. */
.bd-rs{position:absolute;right:-5px;bottom:-5px;width:18px;height:18px;cursor:nwse-resize;z-index:3;
  visibility:hidden;touch-action:none}
.bd-rs::after{content:"";position:absolute;right:5px;bottom:5px;width:8px;height:8px;
  border-right:2px solid var(--gold);border-bottom:2px solid var(--gold);border-radius:0 0 3px 0}
.bd-n:hover .bd-rs,.bd-n.sel .bd-rs,.bd-n.sizing .bd-rs{visibility:visible}
.bd.lod .bd-rs,.bd-n.lift .bd-rs{visibility:hidden}
.bd-pin,.bd-x,.bd-rs{scale:var(--iz,1)}

/* the card's own menu, on a right-click */
.bd-ctx{position:absolute;z-index:42;display:none;flex-direction:column;gap:1px;min-width:190px;padding:6px;border-radius:12px;
  background:rgba(20,18,16,.97);border:1px solid var(--rule);box-shadow:0 20px 50px rgba(0,0,0,.55)}
.bd-ctx.on{display:flex}
.bd-ctx button{display:flex;justify-content:space-between;gap:16px;width:100%;text-align:left;border:0;border-radius:8px;
  padding:8px 10px;font:500 13px RS,system-ui,sans-serif;color:var(--ink);background:transparent;cursor:pointer}
.bd-ctx button:hover{background:rgba(243,239,233,.07)}
.bd-ctx button kbd{font:12px RS,system-ui,sans-serif;color:var(--quiet)}
.bd-ctx button.danger{color:var(--tension)}
.bd-ctx hr{border:0;border-top:1px solid var(--rule);margin:5px 4px}

/* Add to Shot */
.bd-toshot{display:flex;flex-direction:column;gap:6px;margin-top:10px}
.bd-said-ok{margin:10px 0 0;font-size:13px;color:var(--sage)}
.bd-said-no{margin:10px 0 0;font-size:13px;color:var(--tension)}
.bd-pop .bd-popsay{font-size:13px;color:var(--ink);white-space:nowrap;padding:0 4px}
.bd-pop button.no{background:transparent;color:var(--quiet);border:1px solid var(--rule)}

/* sorts, as a list he can change */
.bd-sorts{display:flex;flex-direction:column;gap:14px;margin-top:16px}
.bd-sort{border:1px solid var(--rule);border-radius:10px;padding:12px}
.bd-sort label{display:block;font-size:10px;letter-spacing:.16em;text-transform:uppercase;color:var(--quiet);margin:8px 0 4px}
.bd-sort input{display:block;width:100%;box-sizing:border-box;font:14px RS,system-ui,sans-serif;color:var(--ink);
  background:rgba(243,239,233,.04);border:1px solid var(--rule);border-radius:6px;padding:7px 10px;outline:none}
.bd-sort .bd-two{display:flex;gap:8px}
.bd-sort .bd-col{display:flex;gap:6px;margin-top:6px}
.bd-sort .bd-col button,.bd-sort .bd-srm{font:600 12px RS,system-ui,sans-serif;background:transparent;border:1px solid var(--rule);
  color:var(--quiet);border-radius:99px;padding:6px 10px;cursor:pointer;white-space:nowrap}
.bd-sort .bd-srm{margin-top:10px;color:var(--tension);border-color:rgba(224,122,106,.45)}
.bd-sort .bd-kind{font-size:11px;color:var(--quiet);margin:0 0 2px}
.bd-addsort{display:flex;gap:8px;margin-top:4px}
.bd-addsort button{flex:1;font:600 12px RS,system-ui,sans-serif;color:var(--ink);background:transparent;border:1px solid var(--rule);
  border-radius:99px;padding:9px 12px;cursor:pointer}
@media (max-width:700px){
  .bd.on{height:78vh;min-height:440px}
  .bd-legend{display:none}
  .bd-bar{flex-wrap:nowrap;overflow-x:auto;overscroll-behavior-x:contain;scrollbar-width:none;
    left:0;right:0;top:8px;padding:0 10px;-webkit-mask-image:linear-gradient(90deg,#000 88%,transparent)}
  .bd-bar::-webkit-scrollbar{display:none}
  .bd-bar > *{flex:0 0 auto}
  .bd-seg .lg{display:none}.bd-seg .sm{display:inline}
  .bd-right{margin-left:0}
  .bd-bar{-webkit-mask-image:none;overflow:visible}
  .bd-bar button{padding:7px 9px;font-size:11px}
  .bd-mbtn{padding:7px 10px!important}
  .bd-sync{font-size:0;padding:0 2px}
  .bd-bar{gap:4px;left:6px;right:6px}
  .bd-right{gap:4px}
  .bd-seg button{padding:6px 8px!important}
  .bd-right > .bd-mbtn:last-child{display:none}
  .bd-dock{bottom:10px}
  .bd-dock button{padding:9px 9px;font-size:11px}

  .bd-selbar{gap:8px 10px;padding:8px 10px;bottom:62px!important}
  .bd-selbar .bd-range{min-width:0;flex:1 1 180px}
  .bd-loupe{top:auto;left:6px;right:6px;bottom:6px;height:74%;width:auto;
    transform:translateY(calc(100% + 20px));border-radius:14px}
  .bd-hint{display:none}
  .bd-fhead{padding-bottom:8px}
  .bd-fhead h2{font-size:22px}
  .bd-fhead .bd-tabs{margin-top:10px}
  .bd-fhead .bd-tabs button{padding:5px 9px}
}
/* **On a phone the dock is for a thumb.** His note, 2026-09-25: the board on
   the phone "isn't exactly great". Two fingers already zoom, so − and + go,
   and what is left is tall enough to hit. */
@media (max-width:700px) and (pointer:coarse){
  .bd-dock .bd-zb,.bd-dock .bd-sep{display:none}
  .bd-dock button,.bd-dock .bd-mbtn{min-height:44px;padding:0 13px!important;font-size:13px}
}
@media (prefers-reduced-motion:reduce){
  .bd-n{animation:none}.bd-line{transition:none}
}
`;

const NS = "http://www.w3.org/2000/svg";
const boards = new Set();

function madeRoot() {
  const host = document.querySelector(".madepage");
  return host && host.shadowRoot ? host.shadowRoot : null;
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}
function sv(tag, attrs) {
  const e = document.createElementNS(NS, tag);
  for (const k in attrs || {}) e.setAttribute(k, attrs[k]);
  return e;
}
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const tieKey = (a, b) => [a, b].sort().join("~");
function hash(s) {
  let h = 0;
  for (const c of s) h = (h * 31 + c.charCodeAt(0)) | 0;
  return h;
}

function load(key) {
  try { return JSON.parse(localStorage.getItem(key) || "null") || {}; } catch { return {}; }
}
function store(key, v) {
  try { localStorage.setItem(key, JSON.stringify(v)); } catch { /* a private window */ }
}
function forget(key) {
  try { localStorage.removeItem(key); } catch { /* nothing kept */ }
}

/** What an authored card says, read once off the page's own markup. */
/**
 * **A shoot day's date in words, spelled out — "Mon, Nov 2".** Not asked of
 * `toLocaleDateString`: a worker may carry no locale data, and the MCP
 * (`dayWords` in `src/boards.js`) and this page must write a day card the
 * same, or every day card a chat makes is rewritten the first time a board
 * opens. **The same function lives in both files; change one, change both.**
 */
function dayWords(iso) {
  const m = String(iso || "").match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return String(iso || "");
  const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3])));
  return `${["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getUTCDay()]}, ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()]} ${d.getUTCDate()}`;
}

function readArticle(art) {
  const all = [...art.querySelectorAll("figure")].map((f) => {
    const v = f.querySelector("video");
    const im = f.querySelector("img");
    const cap = f.querySelector("figcaption");
    const from = f.dataset.from || "";
    if (v && v.getAttribute("src")) return { clip: true, from, src: v.getAttribute("src"), poster: v.getAttribute("poster") || "", cap: cap ? cap.textContent.trim() : "" };
    if (im && im.getAttribute("src")) return { from, src: im.getAttribute("src"), cap: cap ? cap.textContent.trim() : "" };
    return null;
  }).filter(Boolean);
  const figs = all.filter((f) => !f.clip);
  const clips = all.filter((f) => f.clip);
  const more = art.querySelector(".bd-more");
  const spec = [...art.querySelectorAll(".bd-spec li")].map((li) => li.textContent.trim());
  return {
    id: art.id,
    kind: KINDS[art.dataset.kind] ? art.dataset.kind : "idea",
    title: (art.querySelector("h3") || {}).textContent?.trim() || art.id,
    kicker: (art.querySelector(".bd-k") || {}).textContent?.trim() || "",
    sub: (art.querySelector(".bd-s") || {}).textContent?.trim() || "",
    more: more ? more.innerHTML : "",
    spec,
    players: [...art.querySelectorAll("iframe")].map((f) => ({ src: f.getAttribute("src"), title: f.getAttribute("title") || "Video" })),
    figs,
    clips,
    x: Number(art.dataset.x) || 0,
    y: Number(art.dataset.y) || 0,
    obs: art.dataset.obs != null ? clamp(Number(art.dataset.obs), 0, 1) : 0.5,
    cam: art.dataset.cam || "",
    missing: art.hasAttribute("data-missing"),
  };
}

/** A card's places on the sorts, from what it carries — Halcyon's two included. */
function valsFrom(d) {
  const v = { ...(d.vals || {}) };
  if (typeof d.obs === "number" && !("obs" in v)) v.obs = 1 - d.obs;
  if (d.cam && !("cam" in v)) v.cam = d.cam;
  return v;
}

function build(block) {
  if (block.dataset.bdBuilt) return;
  const articles = [...block.querySelectorAll(":scope > .bd-n")].filter((a) => a.id);
  // **A Board page starts with nothing on it**, and that is a board, not a
  // page that failed to load. Only a published page with no cards is skipped.
  if (!articles.length && !block.dataset.api) return;
  block.dataset.bdBuilt = "1";

  const KEY = "bd:" + (block.dataset.bd || "board");
  let saved = load(KEY);
  // **The film's own address**, where its pictures and change logs are read
  // from. Said on a Board page; worked out from the address on Halcyon's.
  // **Served** means from the portal: a web address, or the iPhone app's own
  // scheme, which asks the portal for everything (`PortalWeb.swift`, his
  // trial of 2026-10-08). Anything else is a page saved to disk.
  const SERVED = /^(https?|shotlister-portal):$/.test(location.protocol);
  const FILM = block.dataset.film || (SERVED
    ? location.pathname.replace(/\/+$/, "").split("/").slice(0, -1).join("/") : "");
  const authored = articles.map(readArticle);
  // The page's own sorts — said outright on a Board page, Halcyon's pair on
  // the one page that predates them — and the board's, once anybody has
  // changed them, which win.
  let pageSorts = [];
  if (block.hasAttribute("data-lenses")) {
    try { pageSorts = JSON.parse(block.dataset.lenses || "[]"); } catch { pageSorts = []; }
  } else if (articles.some((a) => a.hasAttribute("data-obs") || a.hasAttribute("data-cam"))) {
    pageSorts = LEGACY_SORTS;
  }
  let sorts = Array.isArray(saved.lenses) ? saved.lenses : pageSorts;
  const sortOf = (id) => sorts.find((x) => x.id === id) || null;
  const valOf = (n, x) => {
    const v = n.vals[x.id];
    return x.type === "line" ? (typeof v === "number" ? v : 0.5) : v || "";
  };
  const lineSort = () => sorts.find((x) => x.type === "line") || null;
  const colSort = () => sorts.find((x) => x.type === "columns") || null;
  const colsOf = (x) => (x && Array.isArray(x.cols) ? x.cols : []);
  const noneOf = (x) => (x && x.none) || "Unsorted";
  const authoredTies = [...block.querySelectorAll(":scope > .bd-ties > li")].map((li) => ({
    a: li.dataset.a, b: li.dataset.b, label: li.textContent.trim(), kind: li.dataset.kind || "", user: false,
  }));
  // Read once, then taken out: the board draws its own cards, and the page's
  // copies would only sit hidden holding two dozen <video> elements.
  for (const a of articles) a.remove();
  for (const t of block.querySelectorAll(":scope > .bd-ties")) t.remove();

  // ---------------------------------------------------------------- scaffold
  const vp = el("div", "bd-vp");
  const dots = el("div", "bd-dots");
  vp.append(dots);
  const world = el("div", "bd-world");
  const guides = el("div", "bd-guides");
  const wires = sv("svg", { class: "bd-wires" });
  const drawing = sv("path", { class: "bd-drawing" });
  drawing.style.display = "none";
  wires.append(drawing);
  world.append(guides, wires);
  vp.append(world);
  const bar = el("div", "bd-bar");
  const loupe = el("aside", "bd-loupe");
  const pop = el("div", "bd-pop");
  const hint = el("div", "bd-hint", "Drag cards around · click one to open it · shift-click or shift-drag to select several · pull a card's pin onto another to tie a thread · double-click the board for a note");
  const zoom = el("div", "bd-zoom");
  block.append(vp, bar, zoom, hint, loupe, pop);
  block.classList.add("on");

  const nodes = new Map();
  let ties = [];
  // **What is shared and what is his.** The board — cards, threads, notes —
  // is one for everyone (see `sync` below); how he is looking at it, the sort
  // and the threads switch, stays with each person's own browser.
  const VIEWKEY = KEY + ":view";
  const pref = load(VIEWKEY);
  if (!pref.mode && saved.mode) pref.mode = saved.mode;
  if (!pref.threads && saved.threads) pref.threads = saved.threads;
  const keepPref = () => store(VIEWKEY, pref);
  // **A view is "free" or a sort's id.** Halcyon's two were once called
  // `spectrum` and `cams`, and a browser that remembers them keeps its view.
  if (pref.mode === "spectrum") pref.mode = "obs";
  if (pref.mode === "cams") pref.mode = "cam";
  let mode = pref.mode && sortOf(pref.mode) ? pref.mode : "free";
  const view = { x: 0, y: 0, s: 0.5 };
  let viewTo = null;
  let z = 10;
  let open = null;
  let hover = null;
  // Who else is on the board, and the cards they are holding (see *live*).
  const people = new Map();
  let heldBy = new Map();

  // ---------------------------------------------------------------- guides
  let geo = { spec: null, cams: null };
  function drawGuides() {
    guides.innerHTML = "";
    const spec = el("div", "bd-g spec");
    if (geo.spec) {
      const track = el("div", "bd-track");
      const ls = geo.spec.sort;
      Object.assign(track.style, { position: "absolute", left: `${-SPAN - 150}px`, top: `${geo.spec.trackY}px`, width: `${2 * SPAN + 300}px` });
      track.append(el("b", "l", ls.ends[0]), el("b", "r", ls.ends[1]));
      if (ls.under) track.append(el("span", "l", ls.under[0]), el("span", "r", ls.under[1]));
      spec.append(track);
      for (const [y, name] of geo.spec.lanes) {
        const l = el("div", "bd-lane", name);
        Object.assign(l.style, { position: "absolute", left: `${-SPAN - 560}px`, top: `${y}px` });
        spec.append(l);
      }
    }
    const cams = el("div", "bd-g cams");
    if (geo.cams) {
      for (const c of colsOf(geo.cams.sort)) {
        const z = geo.cams.zones[c.id];
        if (!z) continue;
        const d = el("div", `bd-well t-${c.tone || "ink"}`);
        d.dataset.well = c.id;
        Object.assign(d.style, { position: "absolute", left: `${z.x0}px`, top: `${z.y0}px`, width: `${z.x1 - z.x0}px`, height: `${z.y1 - z.y0}px` });
        d.append(el("b", "", c.name));
        if (c.sub) d.append(el("span", "", c.sub));
        cams.append(d);
      }
      const u = el("div", "bd-undec", `${noneOf(geo.cams.sort)} — drag a card into a column`);
      Object.assign(u.style, { position: "absolute", left: `${geo.cams.x0}px`, width: `${geo.cams.x1 - geo.cams.x0}px`, top: `${geo.cams.undecY}px` });
      cams.append(u);
    }
    guides.append(spec, cams);
  }

  // ---------------------------------------------------------------- cards
  /** The small marks on a card: its column on the first column sort, and —
   *  only while that line is the view — its place on the line. His note,
   *  2026-09-25: a slider on every card in the free board is clutter; it
   *  stays in the card's panel. Neither, and the card's foot is not drawn. */
  function paintTags(n) {
    const cs = colSort();
    const on = sortOf(mode);
    const ls = on && on.type === "line" ? on : null;
    const cam = n.el.querySelector(".bd-cam");
    if (cam) {
      const col = cs ? colsOf(cs).find((c) => c.id === valOf(n, cs)) : null;
      cam.className = "bd-cam" + (col ? ` t-${col.tone || "ink"}` : "");
      cam.textContent = col ? col.chip || col.name.toUpperCase() : "—";
      cam.hidden = !cs;
      cam.title = cs ? cs.name : "";
    }
    const m = n.el.querySelector(".bd-meter");
    if (m) {
      m.hidden = !ls;
      m.title = ls ? ls.name : "";
      if (ls) m.querySelector("i").style.left = `${valOf(n, ls) * 100}%`;
    }
    const ft = n.el.querySelector(".bd-ft");
    if (ft) ft.hidden = !cs && !ls;
  }

  function makeCard(n) {
    const c = el("div", `bd-n k-${n.kind}`);
    if (n.missing) c.classList.add("missing");
    if (n.folded && foldable(n)) c.classList.add("folded");
    c.dataset.id = n.id;
    const pin = el("i", "bd-pin");
    pin.title = "Drag onto another card to tie a thread";
    c.append(pin);
    // **A heading is words on the board, not a card.** His ask, 2026-09-23.
    // Clicked, it takes typing; dragged, it moves like anything else.
    if (n.kind === "heading") {
      const h = el("div", "bd-hd");
      h.dataset.ph = "Heading";
      h.textContent = n.text || "";
      h.addEventListener("pointerdown", (e) => { if (h.isContentEditable) e.stopPropagation(); });
      h.addEventListener("input", () => { n.text = h.innerText; measure(n); wake(); save(); });
      h.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === "Escape") { e.preventDefault(); h.blur(); } });
      h.addEventListener("blur", () => {
        h.contentEditable = "false";
        if (!(n.text || "").trim()) removeNode(n);
      });
      c.append(h);
    } else {
      // A card from the film, a link or a video carries its picture as `src`
      // or as the first of its stills; a reference, as its first still.
      const cover = n.kind === "still" ? { src: n.src }
        : n.kind === "doc" ? (n.src || n.localSrc ? { src: n.src || n.localSrc } : null)
        : PICTURED.has(n.kind) ? ((n.src && n.kind !== "ref" && n.kind !== "test" ? { src: n.src } : null) || n.figs[0]
          || (n.clips[0] && n.clips[0].poster && { src: n.clips[0].poster }) || (n.src ? { src: n.src } : null))
        : null;
      if (n.kind === "clip") {
        const v = document.createElement("video");
        v.className = "bd-cov";
        Object.assign(v, { muted: true, loop: true, autoplay: true, playsInline: true, preload: "auto" });
        v.setAttribute("muted", "");
        v.setAttribute("playsinline", "");
        if (n.poster) v.poster = n.poster;
        v.addEventListener("loadedmetadata", () => { measure(n); wake(); });
        // A browser that holds back `autoplay` on an element made by a script
        // still plays one that is asked, when it is muted.
        v.addEventListener("canplay", () => { if (v.paused && !n.culled && !lod) v.play().catch(() => {}); });
        v.src = n.src;
        c.append(v, el("span", "bd-loop", "loop"));
      } else if (cover && cover.src) {
        const im = el("img", "bd-cov");
        im.alt = "";
        im.draggable = false;
        im.decoding = "async";
        im.addEventListener("load", () => {
          // Its shape kept, so a big board can let the picture go off screen
          // (`seen`) without the card folding flat and the threads jumping.
          if (!im.style.aspectRatio && im.naturalWidth) im.style.aspectRatio = `${im.naturalWidth} / ${im.naturalHeight}`;
          measure(n); wake();
        });
        im.dataset.full = cover.src;
        smallOf(im, n);
        c.append(im);
      }
      const b = el("div", "bd-b");
      if (n.kicker) b.append(el("p", "bd-k", n.kicker));
      // **Every card has a line of his own.** His note, 2026-09-23: no
      // descriptions or commentary written for him — "let me do that". So
      // each card, a clip or still pulled out included, carries a line he
      // types into, kept with the rest of the board. **Shown once it has
      // words.** His note, 2026-09-25: an empty "Add a note…" on every card
      // took room; a note is started from the card's menu or its panel.
      const mine = () => {
        const t = el("p", "bd-t");
        t.contentEditable = "true";
        t.dataset.ph = n.kind === "note" ? "Write a thought…" : "Add a note…";
        t.textContent = n.text || "";
        t.hidden = n.kind !== "note" && !n.text;
        t.addEventListener("input", () => { n.text = t.innerText; measure(n); wake(); save(); });
        t.addEventListener("pointerdown", (e) => e.stopPropagation());
        t.addEventListener("blur", () => {
          if (n.kind !== "note" && !(n.text || "").trim()) { t.hidden = true; measure(n); wake(); }
        });
        return t;
      };
      if (n.kind === "note") {
        b.append(mine());
      } else {
        if (n.kind !== "still" && n.kind !== "clip") b.append(el("h3", "", n.title));
        if (n.sub || n.cap) b.append(el("p", "bd-s", n.sub || n.cap));
        // A Drive file shared only with him has no preview anybody else's
        // server can reach — the one sentence the card needs.
        if (n.kind === "doc" && n.closed && !n.src) b.append(el("p", "bd-meta", "Private on Google Drive — no preview"));
        if (n.fields && n.fields.length) {
          // The handful a shot is known by, on the card; every one in its panel.
          const dl = el("dl", "bd-fields");
          for (const [k, v] of n.fields.filter(([k]) => CARD_FIELDS.has(k)).slice(0, 7)) dl.append(el("dt", "", k), el("dd", "", v));
          if (dl.children.length) b.append(dl);
        } else if (n.facts && n.facts.length) {
          const ul = el("ul", "bd-facts");
          for (const f of n.facts.slice(0, 6)) ul.append(el("li", "", f));
          b.append(ul);
        }
        if (n.spec && n.spec.length) {
          const ul = el("ul", "bd-spec");
          for (const s of n.spec.slice(0, 4)) ul.append(el("li", "", s));
          b.append(ul);
        }
        const bits = [];
        if (n.players && n.players.length) bits.push(`▶ ${n.players.length > 1 ? n.players.length + " videos" : "video"}`);
        if (n.clips && n.clips.length) bits.push(`${n.clips.length} clip${n.clips.length === 1 ? "" : "s"}`);
        if (n.figs && n.figs.length) bits.push(`${n.figs.length} still${n.figs.length === 1 ? "" : "s"}`);
        if (bits.length) b.append(el("p", "bd-meta", bits.join("   ·   ")));
        b.append(mine());
        const ft = el("div", "bd-ft");
        const m = el("div", "bd-meter");
        m.title = "Observe ↔ Move";
        m.append(el("i"));
        ft.append(el("span", "bd-cam"), m);
        b.append(ft);
      }
      c.append(b);
    }
    if (n.user) {
      const x = el("button", "bd-x", "×");
      x.title = "Take off the board";
      x.addEventListener("pointerdown", (e) => e.stopPropagation());
      x.addEventListener("click", (e) => { e.stopPropagation(); removeNode(n); });
      c.append(x);
    }
    if (KINDS[n.kind].w) c.style.width = `${KINDS[n.kind].w}px`;
    if (n.culled) c.style.display = "none";
    const rs = el("i", "bd-rs");
    rs.title = "Resize";
    c.append(rs);
    n.el = c;
    if (n.bare && bareable(n)) c.classList.add("bare");
    c.style.setProperty("--iz", (1 / sizeOf(n)).toFixed(3));
    paintTags(n);
    return c;
  }

  function measure(n) {
    // A card set aside off screen has no size to read; it keeps its last.
    if (n.culled) return;
    // `bw`/`bh` are the card as laid out; `w`/`h` as drawn, at its size.
    n.bw = n.el.offsetWidth || KINDS[n.kind].w;
    n.bh = n.el.offsetHeight || 120;
    const k = sizeOf(n);
    n.w = n.bw * k;
    n.h = n.bh * k;
  }

  /** A card's look: its picture alone or on a card, and how big it is drawn. */
  function setLook(n, { bare, size } = {}) {
    if (bare !== undefined) {
      if (bare && bareable(n)) n.bare = true; else delete n.bare;
      n.el.classList.toggle("bare", Boolean(n.bare));
    }
    if (size !== undefined) {
      const k = clamp(Math.round((Number(size) || 1) * 100) / 100, MIN_SIZE, MAX_SIZE);
      if (k === 1) delete n.size; else n.size = k;
      n.el.style.setProperty("--iz", (1 / k).toFixed(3));
    }
    measure(n);
    place(n);
  }

  function addNode(data, burst) {
    const vals = valsFrom(data);
    const n = {
      figs: [], clips: [], players: [], spec: [], more: "", sub: "", kicker: "",
      ...data,
      vals,
      tx: data.x, ty: data.y, fx: data.x, fy: data.y,
      base: { vals: { ...vals }, x: data.x, y: data.y },
      rot: 0, sc: 1, vx: 0, rest: data.kind === "heading" ? 0 : ((hash(data.id) % 100) / 100) * 2.4 - 1.2,
    };
    n.x = burst ? n.tx * 0.12 : n.tx;
    n.y = burst ? n.ty * 0.12 : n.ty;
    makeCard(n);
    world.append(n.el);
    nodes.set(n.id, n);
    measure(n);
    return n;
  }

  // ---------------------------------------------------------------- ties
  function addTie(t, entrance) {
    const g = sv("g", { class: "bd-tie" });
    const line = sv("path", { class: "bd-line" + (t.kind === "tension" ? " tension" : "") + (t.user ? " user" : "") });
    const hit = sv("path", { class: "bd-hit" });
    const lab = sv("text", { class: "bd-lab", "text-anchor": "middle" });
    lab.textContent = t.label || "";
    g.append(line, hit, lab);
    wires.insertBefore(g, drawing);
    t.key = tieKey(t.a, t.b);
    Object.assign(t, { g, line, hit, lab });
    hit.addEventListener("pointerdown", (e) => { e.stopPropagation(); editTie(t, e); });
    hit.addEventListener("pointerenter", () => g.classList.add("hot"));
    hit.addEventListener("pointerleave", () => { if (!isFocusTie(t)) g.classList.remove("hot"); });
    ties.push(t);
    return t;
  }

  function pinOf(n) {
    return { x: n.x, y: n.y - n.h / 2 + 1 };
  }
  /** Where a thread leaves a card: the point on its edge facing the other. */
  function edgeOf(n, o) {
    const dx = o.x - n.x, dy = o.y - n.y;
    if (!dx && !dy) return { x: n.x, y: n.y };
    const k = Math.min(dx ? (n.w / 2 + 3) / Math.abs(dx) : Infinity, dy ? (n.h / 2 + 3) / Math.abs(dy) : Infinity);
    return { x: n.x + dx * Math.min(k, 1), y: n.y + dy * Math.min(k, 1) };
  }
  // **Nothing, or the whole thread.** A thread leaves each card from the
  // edge that faces the other, so its ends are never hidden under a card.
  // At rest it is drawn at no length; pointed at, opened or picked (or with
  // *Threads: all*), its two ends grow from the cards to meet.
  /**
   * **The threads' drawing is as big as the board, not one pixel.** It was a
   * 1×1 box letting every line spill out of it, and inside the board's moving
   * layer the browser could not tell where a spilt line ended — so each line
   * and each label was lifted into a layer of its own, as big as the board:
   * 330 of them on Call Her Back (2026-09-25), the flicker he reported. Sized
   * to every card with room to spare, in steps so it is rarely resized.
   */
  let wireBox = "";
  function sizeWires() {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const n of nodes.values()) {
      x0 = Math.min(x0, n.x - n.w / 2); x1 = Math.max(x1, n.x + n.w / 2);
      y0 = Math.min(y0, n.y - n.h / 2); y1 = Math.max(y1, n.y + n.h / 2);
    }
    if (!Number.isFinite(x0)) { x0 = y0 = -500; x1 = y1 = 500; }
    const STEP = 2000;
    const L = Math.floor((x0 - 400) / STEP) * STEP, T = Math.floor((y0 - 400) / STEP) * STEP;
    const R = Math.ceil((x1 + 400) / STEP) * STEP, B = Math.ceil((y1 + 600) / STEP) * STEP;
    const box = `${L} ${T} ${R - L} ${B - T}`;
    if (box === wireBox) return;
    wireBox = box;
    wires.setAttribute("viewBox", box);
    Object.assign(wires.style, { left: `${L}px`, top: `${T}px`, width: `${R - L}px`, height: `${B - T}px` });
  }
  function drawTies() {
    const all = block.classList.contains("threads-all");
    const still = block.classList.contains("dragging");
    sizeWires();
    for (const t of ties) {
      const a = nodes.get(t.a), b = nodes.get(t.b);
      if (!a || !b) continue;
      const p = edgeOf(a, b), q = edgeOf(b, a);
      const d = Math.hypot(q.x - p.x, q.y - p.y);
      const sag = Math.min(110, d * 0.12);
      const cx = (p.x + q.x) / 2, cy = (p.y + q.y) / 2 + sag * 2;
      const path = `M${p.x.toFixed(1)} ${p.y.toFixed(1)} Q${cx.toFixed(1)} ${cy.toFixed(1)} ${q.x.toFixed(1)} ${q.y.toFixed(1)}`;
      // **Written only when it changed.** A thread runs across the board, so
      // touching it repaints everything under it — every picture it crosses.
      if (path !== t.d) {
        t.d = path;
        t.line.setAttribute("d", path);
        t.hit.setAttribute("d", path);
        t.lab.setAttribute("x", ((p.x + q.x) / 2).toFixed(1));
        t.lab.setAttribute("y", ((p.y + q.y) / 2 + sag - 8).toFixed(1));
      }
      const len = d + (sag * sag * 8) / (3 * Math.max(d, 1)) + 2;
      const full = all || t.g.classList.contains("hot") || t.g.classList.contains("lit");
      // Resting, nothing shows: the two ends are drawn at no length, and grow
      // from each card to meet in the middle when it comes into focus.
      const tail = 0;
      // Only a change between tails and whole thread is animated; a card
      // being moved redraws its threads at once, or they would trail it.
      const now = performance.now();
      if (full !== t.full) { t.flip = now; t.full = full; }
      const tr = !still && now - (t.flip || -1e9) < 650 ? "" : "none";
      if (tr !== t.tr) { t.tr = tr; t.line.style.transition = tr; }
      const dash = full ? `${(len / 2).toFixed(1)} 0 ${(len / 2).toFixed(1)}` : `${tail.toFixed(1)} ${Math.max(0, len - 2 * tail).toFixed(1)} ${tail.toFixed(1)}`;
      if (dash !== t.dash) { t.dash = dash; t.line.style.strokeDasharray = dash; }
    }
  }

  // ---------------------------------------------------------------- the loop
  let raf = 0;
  function place(n) {
    // Scaled about its middle, so the laid-out box is centred on the card.
    const bw = n.bw || n.w, bh = n.bh || n.h;
    const tilt = n.drag || n.bare ? 0 : n.rest;
    const tf = `translate(${(n.x - bw / 2).toFixed(1)}px,${(n.y - bh / 2).toFixed(1)}px) rotate(${(n.rot + tilt).toFixed(2)}deg) scale(${(n.sc * sizeOf(n)).toFixed(3)})`;
    // Only a card that moved is written: four hundred unchanged ones each
    // frame of a pan was style work for nothing.
    if (tf !== n.tf || n.el.style.transform !== tf) { n.el.style.transform = tf; n.tf = tf; }
  }
  function tick() {
    raf = 0;
    if (!block.isConnected) return;
    let moving = false;
    for (const n of nodes.values()) {
      const k = n.drag ? 0.35 : 0.12;
      const px = n.x;
      n.x += (n.tx - n.x) * k;
      n.y += (n.ty - n.y) * k;
      n.vx = n.x - px;
      const rt = n.drag ? clamp(n.vx * 0.5, -9, 9) : 0;
      n.rot += (rt - n.rot) * 0.2;
      n.sc += ((n.drag ? 1.04 : 1) - n.sc) * 0.25;
      if (Math.abs(n.tx - n.x) > 0.3 || Math.abs(n.ty - n.y) > 0.3 || Math.abs(n.rot - rt) > 0.05 || Math.abs(n.sc - (n.drag ? 1.04 : 1)) > 0.002) moving = true;
      else { n.x = n.tx; n.y = n.ty; }
      place(n);
    }
    if (viewTo) {
      view.x += (viewTo.x - view.x) * 0.14;
      view.y += (viewTo.y - view.y) * 0.14;
      view.s += (viewTo.s - view.s) * 0.14;
      if (Math.abs(viewTo.x - view.x) < 0.5 && Math.abs(viewTo.y - view.y) < 0.5 && Math.abs(viewTo.s - view.s) < 0.001) {
        Object.assign(view, viewTo);
        viewTo = null;
      } else moving = true;
      applyView();
    }
    drawTies();
    lookSoon();
    if (moving) wake();
  }
  function wake() {
    if (!raf) raf = requestAnimationFrame(tick);
  }

  function applyView() {
    world.style.transform = `translate(${view.x}px,${view.y}px) scale(${view.s})`;
    // The dots: a new size only when the zoom changes; a pan only slides them.
    let g = 36 * view.s;
    while (g < 9) g *= 4;
    const size = `${g.toFixed(2)}px ${g.toFixed(2)}px`;
    if (dots.style.backgroundSize !== size) dots.style.backgroundSize = size;
    dots.hidden = view.s < 0.1;
    const mod = (v) => ((v % g) + g) % g - g;
    dots.style.transform = `translate(${mod(view.x).toFixed(1)}px,${mod(view.y).toFixed(1)}px)`;
    block.classList.toggle("close", view.s > 0.95);
    block.classList.toggle("far", view.s < 0.45);
    // A big board, far out: cards as their pictures (with a little give, so
    // it does not flap on the line).
    const lodNow = nodes.size > BIG && (lod ? view.s < 0.34 : view.s < 0.28);
    if (lodNow !== lod) { lod = lodNow; block.classList.toggle("lod", lod); for (const n of nodes.values()) playIf(n); }
    const muteNow = nodes.size > BIG && (mute ? view.s < 0.14 : view.s < 0.12);
    if (muteNow !== mute) { mute = muteNow; block.classList.toggle("mute", mute); }
    lookSoon();
    if (view.s !== lastS) { lastS = view.s; clearTimeout(settleT); settleT = setTimeout(settled, 250); }
    // Zooming out, it is drawn afresh each time the zoom halves, not only
    // once it stops: the whole board coming into view at close-up sharpness
    // is where the memory ran out.
    if (view.s < drawnAt * 0.5) redrawWorld();
    for (const p of people.values()) if (p.cur && p.at) p.cur.style.transform = `translate(${p.at.x}px,${p.at.y}px) scale(${(1 / view.s).toFixed(3)})`;
    // No threads redrawn here: where they run is the board's, not the view's.
  }
  // ---------------------------------------------------------------- what is seen
  // **Only what is on screen is drawn, and at the size it is seen.** His
  // report, 2026-09-25, after the layers were fixed: the Call Her Back board
  // was still slow and flickering — four hundred cards and two hundred and
  // twenty full-size pictures, all drawn at once, all the time. The way the
  // pin-board apps he is used to cope: a card well off screen is set aside
  // (not drawn, its clip paused); a picture is shown from a small copy made
  // once and kept in this browser, and fetched whole only when it is zoomed
  // near enough to need it; and far out, a card is only its picture.
  let lod = false, mute = false, lastS = 0, settleT = 0, seenF = 0;
  // **The board is drawn again at the zoom it settles on.** His report,
  // 2026-09-25: smooth at first, then — after some zooming in and out — the
  // whole portal flickered and went black in patches, the sidebar too. The
  // board is one sheet the size of the board (it has to be, to slide), and
  // the browser keeps such a sheet at the sharpness it was first drawn at, or
  // the closest zoom since. Zoomed in and back out, that was the whole board
  // at close-up sharpness: gigabytes, where the browser keeps about half of
  // one for everything on screen. It ran out and left holes, anywhere. So
  // once a zoom settles the sheet is let go for one frame and taken up
  // again, which draws it afresh at the size it is seen.
  let drawnAt = 1, redrawF = 0;
  function redrawWorld() {
    drawnAt = view.s;
    if (redrawF) return;
    world.style.willChange = "auto";
    redrawF = requestAnimationFrame(() => requestAnimationFrame(() => { redrawF = 0; world.style.willChange = ""; }));
  }
  function settled() {
    sharpen();
    if (Math.abs(view.s / drawnAt - 1) > 0.05) redrawWorld();
  }
  const THUMB_W = 480;
  const lookSoon = () => { if (!seenF) seenF = requestAnimationFrame(seen); };
  function seen() {
    seenF = 0;
    const r = vp.getBoundingClientRect();
    if (!r.width || !r.height) return;
    // Half a screen spare on every side, so a pan does not show a gap.
    const mx = (r.width * 0.5) / view.s, my = (r.height * 0.5) / view.s;
    const x0 = -view.x / view.s - mx, y0 = -view.y / view.s - my;
    const x1 = (r.width - view.x) / view.s + mx, y1 = (r.height - view.y) / view.s + my;
    const back = [];
    for (const n of nodes.values()) {
      const keep = n.drag || open === n || picked.has(n)
        || (n.x + n.w / 2 >= x0 && n.x - n.w / 2 <= x1 && n.y + n.h / 2 >= y0 && n.y - n.h / 2 <= y1);
      if (keep === !n.culled) continue;
      n.culled = !keep;
      n.el.style.display = keep ? "" : "none";
      if (keep) back.push(n);
      else { const im = n.el.querySelector("img.bd-cov"); if (im) setPic(im, picFor(n, im)); }
      playIf(n);
    }
    for (const n of back) measure(n);
    if (back.length) { sharpen(); pumpSmall(); wake(); }
  }
  /** A clip plays only on screen, and not while the board is far out. */
  function playIf(n) {
    const v = n.el && n.el.querySelector("video.bd-cov");
    if (!v) return;
    if (n.culled || lod) { if (!v.paused) v.pause(); } else if (v.paused) v.play().catch(() => {});
  }
  /** Each picture on screen at the size it is seen: its small copy, or whole when zoomed near. */
  function sharpen() {
    for (const n of nodes.values()) {
      if (n.culled) continue;
      const im = n.el.querySelector("img.bd-cov");
      if (im && im.dataset.full) setPic(im, picFor(n, im));
    }
  }
  // **A big board holds only the pictures it is showing.** His report,
  // 2026-09-25: on his iPhone the Dump Board ran for a while, "things kept
  // loading and loading", and then the page quit. Each picture zoomed near
  // went whole and stayed whole once it was panned away — a hundred whole
  // pictures held after five minutes, the page growing all the while, and a
  // phone closes a page that outgrows it. So on a board over `BIG` a card set
  // aside lets its picture go (its shape is kept, see `makeCard`), and one
  // whose small copy is still being made waits for it rather than drawing
  // the whole picture in the meantime. A small board is as it was.
  /** The picture a card should show now: its whole one, its small one, "" for none, null to leave it be. */
  // **Set aside, a card keeps its small copy.** His report, 2026-09-25, the
  // day this landed: the board flickered again after zooming in and out.
  // Letting every picture go off screen meant that zooming back out brought
  // three hundred cards into view at once with nothing in them, each
  // fetching its picture again — the board blinking in, card by card. Only a
  // whole picture is let go now; the small copy (a few dozen KB) stays.
  function picFor(n, im) {
    const lean = Math.max(nodes.size, expect) > BIG;
    if (lean && n.culled) {
      if (im.dataset.small) return im.dataset.small;
      const own = small.get(abs(im.dataset.full));
      // Small already, and still: it is its own small copy.
      return own === "" && !/\.gif(\?|$)/i.test(im.dataset.full) ? im.dataset.full : "";
    }
    const near = n.w * view.s * (window.devicePixelRatio || 1) > THUMB_W * 1.15;
    if (near || small.get(abs(im.dataset.full)) === "") return im.dataset.full;
    if (im.dataset.small) return im.dataset.small;
    return lean ? null : im.dataset.full;
  }
  // **One picture gives way to another only once the new one is ready.**
  // A card zoomed near swaps its small copy for the whole picture, and back;
  // Safari blanks an image between the two, which across a screen of cards
  // is a flicker. So the new one is fetched and decoded aside first.
  function setPic(im, want) {
    if (want === null) return;
    if (!want) { im._want = ""; if (im.hasAttribute("src")) im.removeAttribute("src"); return; }
    if (im.getAttribute("src") === want) { im._want = want; return; }
    if (im._want === want) return;
    im._want = want;
    if (!im.getAttribute("src") || !im.complete) { im.src = want; return; }
    const next = new Image();
    next.decoding = "async";
    next.src = want;
    next.decode().catch(() => {}).then(() => { if (im._want === want) im.src = want; });
  }
  // The small copies: made once from the whole picture, kept in this
  // browser's cache under the picture's own address — which never changes,
  // being its contents — and made nearest-the-screen first, a few at a time.
  const small = new Map();
  const waiting = new Map();
  let making = 0, box = null, expect = 0;
  const abs = (src) => { try { return new URL(src, location.href).href; } catch { return src; } };
  async function smallBox() {
    if (box === null) { try { box = await caches.open("bd-small-1"); } catch { box = false; } }
    return box;
  }
  function smallOf(im, n) {
    const key = abs(im.dataset.full);
    const got = small.get(key);
    if (got !== undefined) {
      if (got) im.dataset.small = got;
      setPic(im, picFor(n, im));
      return;
    }
    // A moving picture is kept whole; a small still of it would stop it.
    if (/\.gif(\?|$)/i.test(key)) { small.set(key, ""); setPic(im, picFor(n, im)); return; }
    const list = waiting.get(key) || [];
    list.push({ im, n });
    waiting.set(key, list);
    pumpSmall();
  }
  function pumpSmall() {
    while (making < 3 && waiting.size) {
      // Whatever is on screen first, then the rest.
      let key = null;
      for (const [k, list] of waiting) { if (list.some((w) => !w.n.culled)) { key = k; break; } }
      if (!key) key = waiting.keys().next().value;
      const list = waiting.get(key);
      waiting.delete(key);
      making++;
      makeSmall(key).then(({ url, shape }) => {
        small.set(key, url);
        for (const { im, n } of list) {
          if (!im.isConnected && !nodes.has(n.id)) continue;
          if (url) im.dataset.small = url;
          // Its shape, so a card never yet on screen is the right size when
          // it first comes into view, before its picture is drawn.
          if (shape && !im.style.aspectRatio) { im.style.aspectRatio = shape; if (!n.culled) measure(n); }
          setPic(im, picFor(n, im));
        }
      }, () => {
        small.set(key, "");
        for (const { im, n } of list) setPic(im, picFor(n, im));
      }).finally(() => { making--; pumpSmall(); });
    }
  }
  /** A picture's small copy (`url`, "" when it is small already) and its shape, "w / h". */
  async function makeSmall(key) {
    const kept = await smallBox();
    if (kept) {
      const hit = await kept.match(key);
      if (hit) {
        const b = await hit.blob();
        let shape = hit.headers.get("x-shape") || "";
        // Kept before shapes were: read it off the small copy itself.
        if (!shape && b.size) { const m = await createImageBitmap(b); shape = `${m.width} / ${m.height}`; if (m.close) m.close(); }
        return { url: b.size ? URL.createObjectURL(b) : "", shape };
      }
    }
    const r = await fetch(key, { credentials: "same-origin" });
    if (!r.ok) throw new Error(String(r.status));
    const blob = await r.blob();
    const bmp = await createImageBitmap(blob);
    const shape = `${bmp.width} / ${bmp.height}`;
    // Already small: the picture itself will do. Kept as an empty answer so
    // it is not measured again.
    if (bmp.width <= THUMB_W * 1.25) {
      if (bmp.close) bmp.close();
      if (kept) kept.put(key, new Response(new Blob([]), { headers: { "x-shape": shape } })).catch(() => {});
      return { url: "", shape };
    }
    const w = THUMB_W, h = Math.max(1, Math.round((bmp.height * THUMB_W) / bmp.width));
    const c = document.createElement("canvas");
    c.width = w; c.height = h;
    const g = c.getContext("2d");
    g.imageSmoothingQuality = "high";
    g.drawImage(bmp, 0, 0, w, h);
    if (bmp.close) bmp.close();
    const type = /png/i.test(blob.type) ? "image/png" : "image/jpeg";
    const out = await new Promise((res) => c.toBlob(res, type, 0.84));
    // Let the canvas go now: Safari on a phone lets a page hold only so much
    // canvas at once, and frees one only when it gets round to it.
    c.width = c.height = 0;
    if (!out) return { url: "", shape };
    if (kept) kept.put(key, new Response(out, { headers: { "content-type": type, "x-shape": shape } })).catch(() => {});
    return { url: URL.createObjectURL(out), shape };
  }

  function toWorld(cx, cy) {
    const r = vp.getBoundingClientRect();
    return { x: (cx - r.left - view.x) / view.s, y: (cy - r.top - view.y) / view.s };
  }
  /**
   * **How far out the board goes.** 0.12 held the Halcyon board; the test
   * dump board (2026-09-25) holds the whole bible, the shot list and four
   * folders of references — near 400 cards — and Fit could not show it all.
   */
  const FARTHEST = 0.05;
  function fitView(list) {
    const all = list || [...nodes.values()].filter((n) => mode === "free" || n.kind !== "heading");
    // An empty board looks at its own middle, where the first card will land.
    if (!all.length) {
      const r = vp.getBoundingClientRect();
      return { s: 0.6, x: r.width / 2, y: r.height / 2 };
    }
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const n of all) {
      x0 = Math.min(x0, n.tx - n.w / 2); x1 = Math.max(x1, n.tx + n.w / 2);
      y0 = Math.min(y0, n.ty - n.h / 2); y1 = Math.max(y1, n.ty + n.h / 2);
    }
    const on = sortOf(mode);
    if (on && on.type === "line" && geo.spec) { y0 = Math.min(y0, geo.spec.trackY - 90); x0 = Math.min(x0, -SPAN - 580); x1 = Math.max(x1, SPAN + 160); }
    if (on && on.type === "columns" && geo.cams) { y0 = Math.min(y0, -190); x0 = Math.min(x0, geo.cams.x0); x1 = Math.max(x1, geo.cams.x1); }
    const r = vp.getBoundingClientRect();
    const top = (bar.offsetHeight || 40) + 30;
    const s = clamp(Math.min((r.width - 60) / (x1 - x0), (r.height - top - 40) / (y1 - y0)), FARTHEST, 1.1);
    return { s, x: r.width / 2 - ((x0 + x1) / 2) * s, y: top + (r.height - top) / 2 - ((y0 + y1) / 2) * s };
  }
  function fit() { viewTo = fitView(); wake(); }
  function flyToNode(n) {
    const r = vp.getBoundingClientRect();
    const s = Math.max(view.s, 0.75);
    const room = block.classList.contains("loupe-on") && r.width > 700 ? r.width - loupe.offsetWidth : r.width;
    viewTo = { s, x: room / 2 - n.tx * s, y: r.height / 2 - n.ty * s };
    wake();
  }

  // ---------------------------------------------------------------- layouts
  function layout() {
    const on = sortOf(mode);
    if (!on) mode = "free";
    block.dataset.mode = on ? on.type : "free";
    geo = { spec: null, cams: null };
    // A card's slider shows only in its own line's view, so a change of view
    // repaints them first — a card's height changes with it.
    for (const n of nodes.values()) { paintTags(n); measure(n); }
    // Headings belong to the free board; the sorts lay out cards only.
    const list = [...nodes.values()].filter((n) => mode === "free" || n.kind !== "heading");
    if (!on) {
      for (const n of list) if (!heldBy.has(n.id)) { n.tx = n.fx; n.ty = n.fy; }
    } else if (on.type === "line") {
      // Lane by lane, top to bottom. **Side by side, not stacked.** His note,
      // 2026-09-23: cards that share a place on the line piled into one
      // column far too tall to read. So a lane is a row: each card as near its
      // place on the line as the others let it be, a crowd spreading sideways
      // around the middle of where it belongs. Only a lane of more than ten
      // wraps, into as few rows as it needs.
      let top = 0;
      const lanes = [];
      const GAP = 26;
      const pack = (row) => {
        const clusters = [];
        const settle = (c) => {
          let off = 0;
          c.offs = c.its.map((n) => { const o = off; off += n.w + GAP; return o; });
          c.w = off - GAP;
          c.left = c.its.reduce((t, n, i) => t + (n.want - n.w / 2 - c.offs[i]), 0) / c.its.length;
        };
        for (const n of row.slice().sort((p, q) => p.want - q.want)) {
          const c = { its: [n] };
          settle(c);
          clusters.push(c);
          while (clusters.length > 1) {
            const c2 = clusters[clusters.length - 1], c1 = clusters[clusters.length - 2];
            if (c1.left + c1.w + GAP <= c2.left) break;
            c1.its = c1.its.concat(c2.its);
            settle(c1);
            clusters.pop();
          }
        }
        for (const c of clusters) c.its.forEach((n, i) => { n.tx = c.left + c.offs[i] + n.w / 2; });
      };
      for (const [name, kinds] of LANES) {
        const members = list.filter((n) => kinds.includes(n.kind)).sort((a, b) => valOf(a, on) - valOf(b, on));
        if (!members.length) continue;
        lanes.push([top - 34, name]);
        for (const n of members) n.want = -SPAN + valOf(n, on) * 2 * SPAN;
        const rows = Math.ceil(members.length / 10);
        for (let r = 0; r < rows; r++) {
          const row = members.filter((_, i) => i % rows === r);
          pack(row);
          const h = Math.max(...row.map((n) => n.h));
          for (const n of row) n.ty = top + n.h / 2;
          top += h + 40;
        }
        top += 110;
      }
      geo.spec = { trackY: -190, lanes, bottom: top, sort: on };
    } else {
      // A column each, each a small grid under its name; anything not in one
      // yet waits in a row underneath.
      const cols = colsOf(on);
      const xs = {};
      cols.forEach((c, i) => { xs[c.id] = (i - (cols.length - 1) / 2) * COL_GAP; });
      const groups = { "": [] };
      for (const c of cols) groups[c.id] = [];
      for (const n of list) (groups[valOf(n, on)] || groups[""]).push(n);
      const zones = {};
      let lowest = 0;
      const lane = (n) => LANES.findIndex((l) => l[1].includes(n.kind));
      for (const c of cols) {
        const k = c.id;
        const cx = xs[k];
        const g = groups[k].slice().sort((a, b) => (a.id === k ? -1 : b.id === k ? 1 : 0) || (lane(a) - lane(b)));
        const per = g.length <= 2 ? 1 : g.length <= 6 ? 2 : 3;
        const cw = 330;
        let y = 0;
        let i = 0;
        const anchor = g[0] && g[0].id === k ? g[0] : null;
        if (anchor) { anchor.tx = cx; anchor.ty = anchor.h / 2; y = anchor.h + 40; i = 1; }
        while (i < g.length) {
          const row = g.slice(i, i + per);
          const rh = Math.max(...row.map((n) => n.h));
          row.forEach((n, j) => {
            n.tx = cx + (j - (row.length - 1) / 2) * cw;
            n.ty = y + n.h / 2;
          });
          y += rh + 36;
          i += per;
        }
        const half = Math.max(1, per) * cw / 2 + 50;
        zones[k] = { x0: cx - half, x1: cx + half, y0: -70, y1: Math.max(y, 260) + 40 };
        lowest = Math.max(lowest, zones[k].y1);
      }
      const undecY = lowest + 130;
      const u = groups[""];
      const perRow = 6;
      u.forEach((n, i) => {
        const r = Math.floor(i / perRow), c = i % perRow;
        const inRow = Math.min(perRow, u.length - r * perRow);
        n.tx = (c - (inRow - 1) / 2) * 310;
        n.ty = undecY + 90 + r * 330 + n.h / 2;
      });
      const first = cols.length ? zones[cols[0].id] : { x0: -600 };
      const last = cols.length ? zones[cols[cols.length - 1].id] : { x1: 600 };
      geo.cams = { zones, undecY, xs, x0: Math.min(first.x0, -960), x1: Math.max(last.x1, 960), sort: on };
    }
    drawGuides();
    for (const b of bar.querySelectorAll(".bd-seg button")) b.classList.toggle("on", b.dataset.mode === mode);
    wake();
  }

  function setMode(m) {
    mode = m === "free" || sortOf(m) ? m : "free";
    pref.mode = m;
    keepPref();
    layout();
    viewTo = fitView();
  }

  // ---------------------------------------------------------------- focus
  function isFocusTie(t) {
    const f = open || hover;
    return f && (t.a === f.id || t.b === f.id);
  }
  /** More cards than a board can fade and dim as one without strain. */
  const BIG = 80;
  function refocus() {
    block.classList.toggle("has-cards", nodes.size > 0);
    const big = nodes.size > BIG;
    block.classList.toggle("big", big);
    const f = open || hover;
    // On a big board only an open card dims the rest; pointing at one lights
    // its threads and nothing else — every hover repainting four hundred
    // cards was the flicker.
    block.classList.toggle("focus", Boolean(big ? open : f));
    const near = new Set();
    const pk = new Set([...picked].map((n) => n.id));
    for (const t of ties) {
      const on = f && (t.a === f.id || t.b === f.id);
      t.g.classList.toggle("hot", Boolean(on));
      t.g.classList.toggle("lit", pk.has(t.a) || pk.has(t.b));
      if (on) { near.add(t.a); near.add(t.b); }
    }
    for (const n of nodes.values()) {
      n.el.classList.toggle("hot", f === n);
      n.el.classList.toggle("near", near.has(n.id) && f !== n);
      n.el.classList.toggle("sel", open === n);
    }
    drawTies();
  }

  // ---------------------------------------------------------------- saving
  /** A card somebody put on the board, as it is kept: only what it has. */
  const KEEP = ["text", "src", "poster", "hash", "cap", "kicker", "title", "sub", "href", "said", "closed", "folded", "bare", "size"];
  function cardOut(n) {
    const o = { id: n.id, kind: n.kind, x: Math.round(n.fx), y: Math.round(n.fy) };
    for (const k of KEEP) if (n[k]) o[k] = n[k];
    if (n.live) o.live = n.live;
    for (const k of ["facts", "fields", "figs", "clips", "players", "spec"]) if (n[k] && n[k].length) o[k] = n[k];
    const vals = {};
    for (const [k, v] of Object.entries(n.vals || {})) if (v !== "" && v !== undefined && v !== null) vals[k] = v;
    if (Object.keys(vals).length) o.vals = vals;
    if ("obs" in vals) o.obs = 1 - vals.obs;
    if ("cam" in vals) o.cam = vals.cam;
    return o;
  }
  /**
   * **Cards taken off the board.** One somebody added simply goes; one the
   * page was published with (Halcyon's) cannot leave the page, so it is
   * kept out of sight by id — his note, 2026-09-25: Delete takes any card,
   * not only the ones he made. Undo, or History, brings it back.
   */
  const gone = new Set(saved.gone || []);
  /** The board as it stands, in the shape it is kept in. */
  function stateNow() {
    const out = { v: 1, at: saved.at, snap: saved.snap, free: {}, obs: {}, cam: {}, vals: {}, text: {}, added: [], ties: [], cut: saved.cut || [], labels: saved.labels || {},
      ...(Array.isArray(saved.lenses) ? { lenses: saved.lenses } : {}) };
    const folded = {}, bare = {}, size = {};
    for (const n of nodes.values()) {
      if (n.user) {
        out.added.push(cardOut(n));
        continue;
      }
      if (n.fx !== n.base.x || n.fy !== n.base.y) out.free[n.id] = [Math.round(n.fx), Math.round(n.fy)];
      for (const k of new Set([...Object.keys(n.vals), ...Object.keys(n.base.vals)])) {
        if (n.vals[k] === n.base.vals[k]) continue;
        // Halcyon's two stay where they always were.
        if (k === "obs") out.obs[n.id] = 1 - n.vals[k];
        else if (k === "cam") out.cam[n.id] = n.vals[k] || "";
        else (out.vals[k] = out.vals[k] || {})[n.id] = n.vals[k];
      }
      if (n.text) out.text[n.id] = n.text;
      if (n.folded) folded[n.id] = true;
      if (n.bare) bare[n.id] = true;
      if (n.size) size[n.id] = n.size;
    }
    for (const t of ties) if (t.user) out.ties.push({ a: t.a, b: t.b, label: t.label });
    if (gone.size) out.gone = [...gone];
    if (Object.keys(folded).length) out.folded = folded;
    if (Object.keys(bare).length) out.bare = bare;
    if (Object.keys(size).length) out.size = size;
    return out;
  }
  let saveT = 0;
  function commit() {
    saveT = 0;
    const out = stateNow();
    remember(out);
    saved = out;
    store(KEY, out);
    push();
  }
  function save() {
    clearTimeout(saveT);
    saveT = setTimeout(commit, 250);
    dirty = true;
  }
  /** A change still waiting its quarter second, kept now. */
  function flush() {
    if (saveT) { clearTimeout(saveT); commit(); }
  }

  // ---------------------------------------------------------------- undo
  // **⌘Z and ⌘⇧Z.** His note, 2026-09-25. Every kept change is a step: the
  // board as it was is put on a stack, and undo puts it back the way History
  // does — whole — so there is no second way of changing a board to go wrong.
  // Changes a moment apart (a word typed, a card nudged twice) are one step.
  // **Each step is what this browser changed, not the whole board.** With
  // several people on one board, putting back a whole earlier board would
  // take away whatever the others did since; a step undoes only its own.
  const hist = { back: [], ahead: [], cur: null, at: 0, group: null };
  const shapeOf = (st) => { const { at, snap, by, v, ...rest } = st || {}; return JSON.stringify(rest); };
  function remember(out) {
    const k = shapeOf(out);
    if (hist.cur === null || k === hist.cur) { hist.cur = k; return; }
    const now = Date.now();
    if (now - hist.at > 600 || !hist.back.length || !hist.group) {
      hist.group = JSON.parse(hist.cur);
      hist.back.push(null);
      if (hist.back.length > 150) hist.back.shift();
    }
    const after = JSON.parse(k);
    hist.back[hist.back.length - 1] = { undo: diffBoard(after, hist.group), redo: diffBoard(hist.group, after) };
    hist.ahead = [];
    hist.at = now;
    hist.cur = k;
  }
  function step(back) {
    if (!mayEdit) return false;
    flush();
    const from = back ? hist.back : hist.ahead;
    if (!from.length) return false;
    const one = from.pop();
    (back ? hist.ahead : hist.back).push(one);
    const next = applyOps(stateNow(), back ? one.undo : one.redo);
    reconcile({ ...next, v: 1, at: saved.at, snap: saved.snap });
    hist.cur = shapeOf(stateNow());
    hist.at = 0;
    hist.group = null;
    dirty = true;
    push();
    return true;
  }

  // ---------------------------------------------------------------- sync
  // **One board for everyone, kept on the portal.** His report, 2026-09-23:
  // what he built in one browser was missing on his phone — and "it should
  // save globally for everyone."
  //
  // **Live, since 2026-09-25.** His ask: "live collaboration features to the
  // look board, so people can see changes in real time." Two halves:
  //
  // - **What changed goes up, not the board.** `base` is the board as the
  //   portal last had it; what this browser has done since is the difference
  //   between that and `saved` (`boardpatch.js`), and that difference is all
  //   that is sent. The portal lays it on the board as it stands, so somebody
  //   else's change a second earlier is kept, not overwritten.
  // - **Everybody's changes come down at once.** A line to the board's room
  //   (`src/boardroom.js`) brings each kept change the moment it is kept; it
  //   is laid on `base`, and this browser's own unsent work on top of that,
  //   and only the cards that changed are touched — so a card being dragged or
  //   a note being typed in is never pulled out from under anybody.
  //
  // The board still asks now and then, in case the line was down.
  //
  // **The first time a browser meets the shared board, its own work is
  // merged in, not thrown away** — the notes, threads and pulled-out pieces
  // it kept before this existed are added to whatever is already there.
  const REMOTE = (() => {
    // **A Board page says where it saves**, so it saves wherever it is served
    // — a local run of the portal included, which is how it is checked.
    if (block.dataset.api && SERVED) return block.dataset.api;
    if (!SERVED || /^(127\.|localhost$)/.test(location.hostname)) return "";
    const parts = location.pathname.replace(/\/+$/, "").split("/");
    parts.pop();
    return `${parts.join("/")}/api/board/${block.dataset.bd || "board"}`;
  })();
  let dirty = false, pushT = 0, mayEdit = true, isEditor = false, publicEdit = false, synced = false;
  // Who may open it — Only Me, Crew, Anyone with the Link — on a Board page;
  // `null` on Halcyon's, which is a published page and has its Visibility.
  let share = null, isAdmin = false;
  /** The board as the portal last had it. */
  let base = null;
  /** This browser, to the room: so its own changes are not sent back to it. */
  const ME = (Math.random().toString(36).slice(2) + Date.now().toString(36)).slice(0, 12);
  let sending = false, again = false, stale = false, live = false;
  const syncEl = el("span", "bd-sync", REMOTE ? "Opening…" : "On this device");
  const sayState = (t, warn) => {
    syncEl.textContent = t;
    syncEl.title = t;
    syncEl.classList.toggle("warn", Boolean(warn));
    syncEl.classList.toggle("ok", t === "Saved");
  };
  const copyOf = (v) => JSON.parse(JSON.stringify(v || {}));
  function push(now) {
    if (!REMOTE || !synced) return;
    if (!mayEdit) { dirty = false; sayState("View only", true); return; }
    dirty = true;
    sayState("Saving…");
    clearTimeout(pushT);
    if (now === "restore") { putWhole(); return; }
    // Live, a change goes up almost at once; a word typed is still one send.
    pushT = setTimeout(send, now ? 0 : live ? 150 : 700);
  }
  /** What this browser has done since the portal's copy, sent as changes. */
  async function send() {
    if (sending) { again = true; return; }
    if (saveT) { flush(); return; }
    const ops = diffBoard(base || {}, saved);
    if (!ops.length) { dirty = false; sayState("Saved"); if (stale) resync(); return; }
    sending = true;
    let got;
    try {
      const r = await fetch(REMOTE, {
        method: "PATCH", credentials: "same-origin",
        headers: { "content-type": "application/json", "x-board-me": ME },
        body: JSON.stringify({ ops }),
      });
      if (r.status === 403) { sending = false; mayEdit = false; dirty = false; sayState("View only", true); return; }
      if (!r.ok) throw new Error(String(r.status));
      got = await r.json();
    } catch {
      sending = false;
      sayState("Not saved yet — retrying", true);
      pushT = setTimeout(() => push(), 6000);
      return;
    }
    sending = false;
    // Nobody else's change came in between: the portal's copy is ours plus
    // these. Otherwise it is fetched — these are in it, and so is theirs.
    if (base && got.prev === (base.at || "")) base = { ...applyOps(base, ops), at: got.at, snap: base.snap };
    else stale = true;
    saved.at = got.at;
    store(KEY, saved);
    if (stale) { await resync(); return; }
    if (again || diffBoard(base, saved).length) { again = false; send(); return; }
    dirty = false;
    sayState("Saved");
  }
  /** A version put back from History goes up whole. */
  async function putWhole() {
    if (sending) { pushT = setTimeout(putWhole, 200); return; }
    sending = true;
    try {
      const r = await fetch(REMOTE, {
        method: "PUT", credentials: "same-origin",
        headers: { "content-type": "application/json", "x-board-restore": "1", "x-board-me": ME },
        body: JSON.stringify(saved),
      });
      if (r.status === 403) { mayEdit = false; dirty = false; sayState("View only", true); return; }
      if (!r.ok) throw new Error(String(r.status));
      const got = await r.json();
      saved.at = got.at;
      base = { ...copyOf(saved), at: got.at };
      store(KEY, saved);
      dirty = false;
      sayState("Saved");
    } catch {
      sayState("Not saved yet — retrying", true);
      pushT = setTimeout(() => push("restore"), 6000);
    } finally { sending = false; }
  }
  /**
   * **Somebody else's change, laid under this browser's own.** `theirs` is
   * the portal's board; whatever this browser has done that the portal does
   * not have yet is laid on top, and only what differs is redrawn.
   */
  function takeTheirs(theirs) {
    if (saveT) { clearTimeout(saveT); saveT = 0; const out = stateNow(); remember(out); saved = out; store(KEY, out); }
    const mine = diffBoard(base || {}, saved);
    base = theirs;
    const next = applyOps(theirs, mine);
    next.at = theirs.at;
    next.snap = theirs.snap;
    if (shapeOf(next) !== shapeOf(saved)) reconcile(next);
    else { saved = next; store(KEY, saved); }
    // Their change is where this browser now starts from; its own undo
    // steps before it still stand, and undo only its own.
    hist.cur = shapeOf(stateNow());
    hist.group = null;
    if (mine.length) push(); else if (!dirty) sayState(mayEdit ? "Saved" : "View only", !mayEdit);
  }
  /** The whole board fetched again and taken in. */
  async function resync() {
    if (!REMOTE || !synced) return;
    if (sending) { stale = true; return; }
    stale = false;
    let got;
    try {
      const r = await fetch(REMOTE, { credentials: "same-origin", cache: "no-store" });
      if (!r.ok) throw new Error(String(r.status));
      got = await r.json();
    } catch { return; }
    if (sending) { stale = true; return; }
    readRights(got);
    const theirs = got.board || {};
    if (base && theirs.at === base.at) return;
    takeTheirs(theirs);
  }
  function readRights(got) {
    mayEdit = Boolean(got.mayEdit);
    isEditor = Boolean(got.isEditor);
    publicEdit = Boolean(got.publicEdit);
    share = got.share || null;
    isAdmin = Boolean(got.isAdmin);
    paintAdmin();
  }
  const busy = () => {
    const a = root().activeElement;
    return dirty || gesture || (a && (a.isContentEditable || a.tagName === "INPUT" || a.tagName === "TEXTAREA"));
  };
  const root = () => block.getRootNode();
  const hasWork = (b) => b && ((b.added || []).length || (b.ties || []).length || Object.keys(b.text || {}).length ||
    Object.keys(b.free || {}).length || Object.keys(b.obs || {}).length || Object.keys(b.cam || {}).length ||
    Object.keys(b.vals || {}).length || Array.isArray(b.lenses) || (b.gone || []).length || Object.keys(b.folded || {}).length ||
    Object.keys(b.bare || {}).length || Object.keys(b.size || {}).length);
  function merge(theirs, mine) {
    const out = { ...theirs };
    const ids = new Set((theirs.added || []).map((d) => d.id));
    out.added = [...(theirs.added || []), ...(mine.added || []).filter((d) => !ids.has(d.id))];
    const tk = new Set((theirs.ties || []).map((t) => tieKey(t.a, t.b)));
    out.ties = [...(theirs.ties || []), ...(mine.ties || []).filter((t) => !tk.has(tieKey(t.a, t.b)))];
    for (const f of ["free", "obs", "cam", "vals", "text", "labels", "folded", "bare", "size"]) out[f] = { ...(mine[f] || {}), ...(theirs[f] || {}) };
    if (!Array.isArray(theirs.lenses) && Array.isArray(mine.lenses)) out.lenses = mine.lenses;
    out.cut = [...new Set([...(theirs.cut || []), ...(mine.cut || [])])];
    const off = [...new Set([...(theirs.gone || []), ...(mine.gone || [])])];
    if (off.length) out.gone = off;
    return out;
  }
  async function pull(first) {
    if (!REMOTE) return;
    if (!first) { resync(); return; }
    let got;
    try {
      const r = await fetch(REMOTE, { credentials: "same-origin", cache: "no-store" });
      if (!r.ok) throw new Error(String(r.status));
      got = await r.json();
    } catch {
      sayState("Offline — kept on this device", true);
      return;
    }
    readRights(got);
    if (Array.isArray(got.posters) && got.posters.length) setTimeout(() => payPosters(got.posters), 1500);
    const theirs = got.board || {};
    synced = true;
    base = copyOf(theirs);
    connect();
    if (!theirs.at) {
      // Nothing on the portal yet: what this browser has becomes the board.
      if (hasWork(saved) && mayEdit) push(true); else sayState(mayEdit ? "Saved" : "View only", !mayEdit);
      return;
    }
    if (!saved.at && hasWork(saved) && mayEdit) {
      rebuild(merge(theirs, saved));
      push(true);
      return;
    }
    if (theirs.at !== saved.at) rebuild(copyOf(theirs));
    sayState(mayEdit ? "Saved" : "View only", !mayEdit);
  }
  function rebuild(state) {
    reconcile(state);
    hist.cur = shapeOf(stateNow());
    hist.group = null;
  }

  // ---------------------------------------------------------------- reconcile
  /** What a card somebody added is, less where it sits and what is written on it. */
  const MOVABLE = new Set(["x", "y", "text", "vals", "obs", "cam", "folded", "bare", "size"]);
  const sigOf = (d) => JSON.stringify(Object.keys(d || {}).filter((k) => !MOVABLE.has(k)).sort().map((k) => [k, d[k]]));
  /**
   * **The board brought to `state`, touching only what differs.** Cards that
   * went are taken off, new ones put on, and the rest moved, rewritten or
   * re-sorted where they stand — a card being dragged keeps its place, a
   * note being typed in keeps its words and its caret, the open panel stays
   * open. Threads are drawn again; they are only lines.
   */
  function reconcile(state) {
    const had = saved;
    saved = state;
    store(KEY, saved);
    gone.clear();
    for (const id of state.gone || []) gone.add(id);
    sorts = Array.isArray(saved.lenses) ? saved.lenses : pageSorts;
    if (mode !== "free" && !sortOf(mode)) mode = "free";
    if (JSON.stringify(had.lenses) !== JSON.stringify(saved.lenses)) drawSeg();
    const want = new Map();
    for (const d of authored) if (!gone.has(d.id)) want.set(d.id, { d, user: false });
    for (const d of state.added || []) if (d && d.id) want.set(d.id, { d, user: true });
    for (const n of [...nodes.values()]) {
      const w = want.get(n.id);
      if (w && w.user === Boolean(n.user)) continue;
      if (typeof picked !== "undefined") picked.delete(n);
      n.el.remove();
      nodes.delete(n.id);
      if (open === n) closeLoupe();
      if (hover === n) hover = null;
    }
    let redrawOpen = false, anyLive = false;
    for (const [id, { d, user }] of want) {
      let n = nodes.get(id);
      if (!n) {
        n = user ? addNode({ figs: [], clips: [], players: [], ...d, user: true }, false) : addNode({ ...d }, false);
        n.sig = user ? sigOf(d) : "";
        n.el.style.zIndex = ++z;
        if (n.live) anyLive = true;
      } else if (user) {
        const sig = sigOf(d);
        if (n.sig === undefined) n.sig = sigOf(cardOut(n));
        if (sig !== n.sig) {
          // The card itself changed — a picture arrived, a title — so it is
          // drawn again, in the same place and the same object.
          for (const k of [...KEEP, "live", "facts", "fields", "figs", "clips", "players", "spec"]) delete n[k];
          Object.assign(n, { figs: [], clips: [], players: [], spec: [], more: "", sub: "", kicker: "" }, d, { user: true });
          const old = n.el;
          makeCard(n);
          n.el.style.zIndex = old.style.zIndex;
          n.el.classList.toggle("picked", typeof picked !== "undefined" && picked.has(n));
          old.replaceWith(n.el);
          n.sig = sig;
          place(n);
          if (open === n) redrawOpen = true;
          if (n.live) anyLive = true;
        }
      }
      settle(n, d, user, state);
    }
    for (const t of ties) t.g.remove();
    ties = [];
    const cut = new Set(state.cut || []);
    for (const t of authoredTies) {
      if (!nodes.has(t.a) || !nodes.has(t.b) || cut.has(tieKey(t.a, t.b))) continue;
      const k = tieKey(t.a, t.b);
      addTie({ ...t, label: state.labels && k in state.labels ? state.labels[k] : t.label }, 0);
    }
    for (const t of state.ties || []) if (nodes.has(t.a) && nodes.has(t.b)) addTie({ ...t, user: true, kind: "" }, 0);
    layout();
    refocus();
    if (typeof drawSelbar === "function") drawSelbar();
    const inPanel = loupe.contains(root().activeElement);
    if (open && nodes.has(open.id) && redrawOpen && !inPanel) openLoupe(open, true);
    if (anyLive) setTimeout(() => refreshLive(), 400);
    wake();
  }
  /** Where a card sits, what it says, where it is on the sorts — as `state` has it. */
  function settle(n, d, user, state) {
    if (!n.drag && !(heldBy && heldBy.has(n.id))) {
      const f = !user && state.free && state.free[n.id];
      const fx = user ? d.x : f ? f[0] : n.base.x;
      const fy = user ? d.y : f ? f[1] : n.base.y;
      if (Number.isFinite(fx) && Number.isFinite(fy)) { n.fx = fx; n.fy = fy; }
    }
    if (user) n.vals = valsFrom(d);
    else {
      const v = { ...n.base.vals };
      if (state.obs && n.id in state.obs) v.obs = 1 - state.obs[n.id];
      if (state.cam && n.id in state.cam) v.cam = state.cam[n.id];
      for (const [k, m] of Object.entries(state.vals || {})) if (m && n.id in m) v[k] = m[n.id];
      n.vals = v;
    }
    const text = (user ? d.text : state.text && state.text[n.id]) || "";
    if (text !== (n.text || "")) {
      n.text = text;
      const t = n.el.querySelector(n.kind === "heading" ? ".bd-hd" : ".bd-t");
      if (t && root().activeElement !== t) {
        t.textContent = text;
        if (n.kind !== "note" && n.kind !== "heading") t.hidden = !text;
      }
    }
    const folded = Boolean(user ? d.folded : state.folded && state.folded[n.id]);
    if (foldable(n) && Boolean(n.folded) !== folded) { n.folded = folded; n.el.classList.toggle("folded", folded); }
    const bare = Boolean(user ? d.bare : state.bare && state.bare[n.id]);
    if (Boolean(n.bare) !== bare) setLook(n, { bare });
    const size = Number(user ? d.size : state.size && state.size[n.id]) || 0;
    if ((n.size || 0) !== size && !(gesture && gesture.resize === n)) setLook(n, { size });
    paintTags(n);
    measure(n);
  }

  // ---------------------------------------------------------------- live
  // **The line to the board's room**, and who else is on the board. Each
  // person gets a colour; their pointer is drawn where it is on the board
  // with their name, and a card they are holding wears their colour and moves
  // as they move it. Nothing here is kept — it is only where people are.
  let sock = null, tries = 0, pingT = 0;
  const faces = el("div", "bd-faces");
  const cursors = el("div", "bd-cursors");
  world.append(cursors);
  function connect() {
    // The iPhone app reads only and has no line to a room.
    if (!REMOTE || !block.isConnected || sock || typeof WebSocket === "undefined" || location.protocol === "shotlister-portal:") return;
    let u;
    try {
      u = new URL(`${REMOTE}/live`, location.href);
      u.protocol = u.protocol === "https:" ? "wss:" : "ws:";
      u.searchParams.set("me", ME);
      for (const [k, v] of new URLSearchParams(location.search)) if (k === "k" || k === "as") u.searchParams.set(k, v);
    } catch { return; }
    const ws = new WebSocket(u.href);
    sock = ws;
    ws.addEventListener("open", () => {
      tries = 0;
      live = true;
      clearInterval(pingT);
      pingT = setInterval(() => { try { ws.send("ping"); } catch { /* closing */ } }, 25000);
      // Anything missed while the line was down.
      resync();
    });
    ws.addEventListener("message", (e) => {
      if (e.data === "pong") return;
      let m;
      try { m = JSON.parse(e.data); } catch { return; }
      heard(m);
    });
    ws.addEventListener("close", () => {
      if (sock === ws) sock = null;
      live = false;
      clearInterval(pingT);
      for (const id of [...people.keys()]) gone1(id);
      if (block.isConnected) setTimeout(connect, Math.min(30000, 1000 * 2 ** tries++));
    });
  }
  function heard(m) {
    if (m.t === "hello") {
      for (const p of m.here || []) people.set(p.id, { ...p });
      drawFaces();
    } else if (m.t === "join") {
      people.set(m.who.id, { ...m.who });
      drawFaces();
    } else if (m.t === "leave") {
      gone1(m.id);
    } else if (m.t === "here") {
      const p = people.get(m.id);
      if (!p) return;
      if ("at" in m) { p.at = m.at; drawCursor(p); }
      if ("holding" in m) hold(p, m.holding || [], m.moving || null);
      else if (m.moving) hold(p, p.holding || [], m.moving);
    } else if (m.t === "ops") {
      if (m.from === ME) return;
      if (sending || !base || m.prev !== (base.at || "")) { stale = true; if (!sending) resync(); return; }
      takeTheirs({ ...applyOps(base, m.ops), at: m.at, snap: base.snap });
    } else if (m.t === "reload") {
      if (m.from !== ME) resync();
    }
  }
  function gone1(id) {
    const p = people.get(id);
    if (!p) return;
    hold(p, [], null);
    if (p.cur) p.cur.remove();
    people.delete(id);
    drawFaces();
  }
  const initials = (name) => String(name || "?").split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join("") || "?";
  function drawFaces() {
    faces.innerHTML = "";
    const list = [...people.values()];
    for (const p of list.slice(0, 5)) {
      const f = el("span", "bd-face", initials(p.name));
      f.style.setProperty("--hc", p.colour);
      f.title = p.name;
      faces.append(f);
    }
    if (list.length > 5) faces.append(el("span", "bd-face more", `+${list.length - 5}`));
    faces.title = list.map((p) => p.name).join(", ");
  }
  function drawCursor(p) {
    if (!p.at) { if (p.cur) p.cur.style.display = "none"; return; }
    if (!p.cur) {
      p.cur = el("div", "bd-cur");
      p.cur.append(el("i"), el("span", "", p.name));
      p.cur.style.setProperty("--hc", p.colour);
      cursors.append(p.cur);
    }
    p.cur.style.display = "";
    p.cur.style.transform = `translate(${p.at.x}px,${p.at.y}px) scale(${(1 / view.s).toFixed(3)})`;
  }
  function hold(p, ids, moving) {
    const before = new Set(p.holding || []);
    p.holding = ids;
    heldBy = new Map();
    for (const q of people.values()) for (const id of q.holding || []) heldBy.set(id, q);
    for (const id of before) {
      if (heldBy.has(id)) continue;
      const n = nodes.get(id);
      if (n) { n.el.classList.remove("held"); n.el.style.removeProperty("--hc"); }
    }
    for (const id of ids) {
      const n = nodes.get(id);
      if (!n || n.drag) continue;
      n.el.classList.add("held");
      n.el.style.setProperty("--hc", p.colour);
      // Where they have it now, drawn at once — kept only when they let go.
      if (moving && moving[id] && mode === "free") { n.tx = moving[id][0]; n.ty = moving[id][1]; }
    }
    // Let go: their change is on its way. If none comes (a drag that went
    // nowhere), the card goes home.
    if ([...before].some((id) => !heldBy.has(id))) setTimeout(() => { if (block.isConnected) layout(); }, 2500);
    wake();
  }
  // What this browser says: its pointer, and the cards it is holding.
  let sayT = 0, sayNext = null;
  function say(what) {
    if (!sock || sock.readyState !== 1) return;
    sayNext = { ...(sayNext || {}), ...what };
    if (sayT) return;
    sayT = setTimeout(() => {
      sayT = 0;
      const m = sayNext;
      sayNext = null;
      try { sock.send(JSON.stringify({ t: "here", ...m })); } catch { /* closing */ }
    }, 60);
  }
  vp.addEventListener("pointermove", (e) => {
    if (!live || e.pointerType === "touch") return;
    const w = toWorld(e.clientX, e.clientY);
    say({ at: { x: w.x, y: w.y } });
  });
  vp.addEventListener("pointerleave", () => { if (live) say({ at: null }); });
  /** Called as a drag goes: the cards in hand and where they are. */
  function sayHolding(list) {
    if (!live) return;
    const moving = {};
    for (const m of list.slice(0, 60)) moving[m.id] = [Math.round(m.tx), Math.round(m.ty)];
    say({ holding: list.map((m) => m.id), moving });
  }

  // ---------------------------------------------------------------- populate
  function populate(entrance) {
    // How big the board is going to be, known before its cards are made, so
    // its first cards already load their pictures as a big board's do.
    expect = authored.length + (saved.added || []).length;
    authored.filter((d) => !gone.has(d.id)).forEach((d, i) => {
      const n = addNode({ ...d }, entrance);
      if (saved.free && saved.free[d.id]) [n.fx, n.fy] = saved.free[d.id];
      if (saved.obs && d.id in saved.obs) n.vals.obs = 1 - saved.obs[d.id];
      if (saved.cam && d.id in saved.cam) n.vals.cam = saved.cam[d.id];
      for (const [k, m] of Object.entries(saved.vals || {})) if (m && d.id in m) n.vals[k] = m[d.id];
      if (saved.folded && saved.folded[d.id] && foldable(n)) { n.folded = true; n.el.classList.add("folded"); measure(n); }
      if ((saved.bare && saved.bare[d.id]) || (saved.size && saved.size[d.id])) setLook(n, { bare: Boolean(saved.bare && saved.bare[d.id]), size: saved.size && saved.size[d.id] });
      if (saved.text && saved.text[d.id]) { n.text = saved.text[d.id]; const t = n.el.querySelector(".bd-t"); if (t) { t.textContent = n.text; t.hidden = false; } measure(n); }
      paintTags(n);
      if (entrance) n.el.style.animationDelay = `${i * 45}ms`;
    });
    for (const d of saved.added || []) {
      // **What a card was given, it keeps** — a reference an agent built with
      // its trailers and stills, a shot's frames — so the panel opens to them.
      const n = addNode({ figs: [], clips: [], players: [], ...d, user: true }, entrance);
      n.fx = d.x; n.fy = d.y;
      n.sig = sigOf(d);
    }
    const cut = new Set(saved.cut || []);
    authoredTies.forEach((t, i) => {
      if (!nodes.has(t.a) || !nodes.has(t.b) || cut.has(tieKey(t.a, t.b))) return;
      const k = tieKey(t.a, t.b);
      const label = saved.labels && k in saved.labels ? saved.labels[k] : t.label;
      addTie({ ...t, label }, entrance ? 500 + i * 35 : 0);
    });
    for (const t of saved.ties || []) {
      if (nodes.has(t.a) && nodes.has(t.b)) addTie({ ...t, user: true, kind: "" }, entrance ? 900 : 0);
    }
    // Cards from the film catch up with it, once it has been read.
    if ([...nodes.values()].some((n) => n.live)) setTimeout(() => refreshLive(), 400);
  }

  // ---------------------------------------------------------------- editing
  function newId(p) { return p + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36); }

  function addNote(at) {
    const n = addNode({ id: newId("note-"), kind: "note", kicker: "Note", x: at.x, y: at.y, user: true, text: "" }, false);
    n.x = at.x; n.y = at.y + 40; n.sc = 0.6;
    n.el.style.zIndex = ++z;
    if (mode !== "free") layout();
    save();
    wake();
    requestAnimationFrame(() => n.el.querySelector(".bd-t").focus());
  }

  function addStill(from, fig, at) {
    const n = addNode({
      id: newId(fig.clip ? "clip-" : "still-"), kind: fig.clip ? "clip" : "still", src: fig.src, poster: fig.poster || "", hash: fig.hash || "",
      cap: fig.cap, title: fig.cap || (fig.clip ? "Clip" : "Still"),
      kicker: from.title, x: at.x, y: at.y, vals: { ...from.vals }, user: true,
    }, false);
    n.x = at.x; n.y = at.y; n.sc = 1.2;
    n.el.style.zIndex = ++z;
    addTie({ a: from.id, b: n.id, label: fig.clip ? "clip" : "still", user: true, kind: "" }, 1);
    if (mode !== "free") layout();
    refocus();
    save();
    wake();
    return n;
  }

  function removeNode(n) {
    if (typeof picked !== "undefined") picked.delete(n);
    if (!n.user) gone.add(n.id);
    for (const t of ties.filter((t) => t.a === n.id || t.b === n.id)) dropTie(t);
    n.el.remove();
    nodes.delete(n.id);
    if (open === n) closeLoupe();
    if (hover === n) hover = null;
    refocus();
    if (mode !== "free") layout();
    save();
  }

  function dropTie(t) {
    t.g.remove();
    ties = ties.filter((x) => x !== t);
    if (!t.user) {
      saved.cut = [...new Set([...(saved.cut || []), t.key])];
    }
  }

  function editTie(one, e) {
    const all = Array.isArray(one) ? one : [one];
    const t = all[0];
    const r = block.getBoundingClientRect();
    pop.innerHTML = "";
    const inp = el("input");
    inp.placeholder = all.length > 1 ? `What ties these ${all.length}?` : "What ties these?";
    inp.value = t.label || "";
    const ok = el("button", "", "Save");
    const cut = el("button", "cut", "Cut");
    pop.append(inp, ok, cut);
    pop.style.left = `${e.clientX - r.left}px`;
    pop.style.top = `${e.clientY - r.top}px`;
    pop.classList.add("on");
    const done = () => {
      for (const t of all) {
        t.label = inp.value.trim();
        t.lab.textContent = t.label;
        if (!t.user) saved.labels = { ...(saved.labels || {}), [t.key]: t.label };
      }
      pop.classList.remove("on");
      save();
      if (open) openLoupe(open, true);
    };
    ok.addEventListener("click", done);
    inp.addEventListener("keydown", (k) => { if (k.key === "Enter") done(); if (k.key === "Escape") pop.classList.remove("on"); });
    cut.addEventListener("click", () => {
      for (const t of all) dropTie(t);
      pop.classList.remove("on");
      refocus();
      save();
      if (open) openLoupe(open, true);
    });
    setTimeout(() => inp.focus(), 0);
  }

  /**
   * One sort's control, for one card or several: a row of columns to pick
   * from, or a slider along a line. `after` runs once a pick has landed.
   */
  function sortControl(x, list, after) {
    if (x.type === "columns") {
      const mix = el("div", "bd-mix");
      const now = list.every((m) => valOf(m, x) === valOf(list[0], x)) ? valOf(list[0], x) : null;
      for (const c of [...colsOf(x), { id: "", name: noneOf(x) }]) {
        const b = el("button", now === c.id ? "on" : "", c.pick || c.name);
        b.addEventListener("click", () => {
          for (const m of list) { m.vals[x.id] = c.id; paintTags(m); }
          for (const o of mix.children) o.classList.toggle("on", o === b);
          if (mode === x.id) layout();
          save();
          if (after) after();
        });
        mix.append(b);
      }
      return mix;
    }
    const rg = el("label", "bd-range");
    const inp = el("input");
    inp.type = "range"; inp.min = "0"; inp.max = "100";
    inp.value = String(Math.round((list.reduce((t, m) => t + valOf(m, x), 0) / list.length) * 100));
    inp.addEventListener("input", () => {
      for (const m of list) { m.vals[x.id] = Number(inp.value) / 100; paintTags(m); }
      if (mode === x.id) layout();
      save();
    });
    rg.append(el("b", "l", x.ends[0]), inp, el("b", "r", x.ends[1]));
    return rg;
  }

  // ---------------------------------------------------------------- loupe
  function openLoupe(n, keep) {
    const scroll = keep ? loupe.scrollTop : 0;
    open = n;
    loupe.innerHTML = "";
    const close = el("button", "bd-close", "×");
    close.addEventListener("click", closeLoupe);
    const head = el("div", "bd-lhead");
    head.append(close);
    loupe.append(head);
    const kick = el("p", "bd-k", n.kicker || KINDS[n.kind].name);
    kick.style.color = getComputedStyle(n.el).getPropertyValue("--kc") || "";
    loupe.append(kick, el("h2", "", n.kind === "note" ? "Note" : n.title));
    const said = el("textarea", "bd-note");
    said.placeholder = n.kind === "note" ? "Write a thought…" : "Add a note…";
    said.value = n.text || "";
    said.addEventListener("input", () => {
      n.text = said.value;
      const t = n.el.querySelector(".bd-t");
      if (t) { t.textContent = n.text; t.hidden = n.kind !== "note" && !n.text; }
      measure(n); wake(); save();
    });
    loupe.append(said);
    if (n.sub) loupe.append(el("p", "bd-lead", n.sub));
    if (n.fields && n.fields.length) {
      const dl = el("dl", "bd-fields");
      for (const [k, v] of n.fields) dl.append(el("dt", "", k), el("dd", "", v));
      loupe.append(dl);
    } else if (n.facts && n.facts.length) {
      const ul = el("ul", "bd-facts");
      for (const f of n.facts) ul.append(el("li", "", f));
      loupe.append(ul);
    }
    if (n.said) loupe.append(el("p", "bd-said", n.said));
    // **Where it lives**: a link's page, a document's file, the film's own
    // screen for a card that came from it. Opened beside the board, never in
    // place of it.
    const away = n.href || (n.live && FILM && { shot: "shotlist", scene: "shotlist", location: "locations", day: "schedule", "board-image": "boards" }[n.live.type]
      ? `${FILM}/${{ shot: "shotlist", scene: "shotlist", location: "locations", day: "schedule", "board-image": "boards" }[n.live.type]}` : "");
    if (away) {
      const a = el("a", "bd-open", n.kind === "doc" ? "Open Document" : n.live && !n.href ? `Open ${{ shot: "Shot List", scene: "Shot List", location: "Locations", day: "Schedule", "board-image": "Reference Images" }[n.live.type]}` : "Open Link");
      a.href = n.href && n.href.startsWith("pic/") ? `${FILM}/${n.href}` : away;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      loupe.append(a);
    }
    if (n.kind === "still" || n.kind === "clip") {
      const im = el(n.kind === "clip" ? "video" : "img");
      if (n.kind === "clip") Object.assign(im, { muted: true, loop: true, autoplay: true, playsInline: true, controls: true });
      if (n.kind === "clip" && n.poster) im.poster = n.poster;
      im.src = n.src;
      im.style.cssText = "width:100%;margin-top:14px;border-radius:0;display:block";
      loupe.append(im);
      if (n.cap) loupe.append(el("p", "bd-lead", n.cap));
      if (mayShot()) {
        const to = el("button", "bd-act", "Add to Shot…");
        to.style.marginTop = "14px";
        to.addEventListener("click", () => openToShot(n));
        loupe.append(to);
      }
    }
    if (n.more) {
      const body = el("div", "bd-body");
      body.innerHTML = n.more;
      loupe.append(body);
    }
    if (n.spec && n.spec.length) {
      const ul = el("ul", "bd-spec");
      for (const s of n.spec) ul.append(el("li", "", s));
      loupe.append(ul);
    }
    // **Hundreds of pieces, so grouped and lazy.** A reference may bring a
    // few trailers' worth of shots; each group is headed by the source named
    // before " · " in its caption, a clip plays only while it is in view, and
    // a still is fetched only when scrolled to.
    const groups = (list) => {
      const out = new Map();
      for (const f of list) {
        const k = f.from || ((f.cap || "").includes(" · ") ? f.cap.split(" · ")[0] : "");
        if (!out.has(k)) out.set(k, []);
        out.get(k).push(f);
      }
      return out;
    };
    const seen = new IntersectionObserver((es) => {
      for (const e of es) {
        const v = e.target;
        v.dataset.on = e.isIntersecting ? "1" : "";
        if (e.isIntersecting) {
          if (!v.src) { v.autoplay = true; v.src = v.dataset.src; } else v.play().catch(() => {});
        } else v.pause();
      }
    }, { root: loupe, rootMargin: "200px" });
    const shelf = (list, kind) => {
      const g = groups(list);
      loupe.append(el("p", "bd-h", `${list.length} ${list.length === 1 ? kind.replace(/s$/, "") : kind} — drag one onto the board to pin it`));
      for (const [name, items] of g) {
        if (g.size > 1 && name) loupe.append(el("p", "bd-sub", `${name} · ${items.length}`));
        const grid = el("div", "bd-stills");
        for (const fig of items) {
          const s = el("div", "bd-st" + (fig.clip ? " clip" : ""));
          s.title = fig.cap || "";
          if (fig.clip) {
            const v = document.createElement("video");
            Object.assign(v, { muted: true, loop: true, playsInline: true, preload: "none" });
            v.setAttribute("muted", "");
            v.setAttribute("playsinline", "");
            if (fig.poster) v.poster = fig.poster;
            v.dataset.src = fig.src;
            // Asked to play the moment its address is set, a clip is not ready
            // and the ask is dropped; it starts when it can, if still in view.
            v.addEventListener("canplay", () => { if (v.dataset.on && v.paused) v.play().catch(() => {}); });
            s.append(v);
            seen.observe(v);
          } else {
            const im = el("img");
            im.loading = "lazy";
            im.src = fig.src;
            im.alt = fig.cap || "";
            im.draggable = false;
            s.append(im);
          }
          if (fig.cap) s.append(el("span", "bd-cap", fig.cap));
          s.addEventListener("pointerdown", (e) => dragStill(e, n, fig));
          grid.append(s);
        }
        loupe.append(grid);
      }
    };
    if (n.clips && n.clips.length) shelf(n.clips, "clips");
    if (n.figs && n.figs.length) shelf(n.figs, "stills");

    // **The full trailers last, and shut.** His note, 2026-09-23: a player at
    // the top took the room the clips need. Each is a line that opens its
    // player where it stands, one at a time.
    if (n.players && n.players.length) {
      loupe.append(el("p", "bd-h", n.kind === "video" ? "Video" : n.players.length > 1 ? `Full trailers · ${n.players.length}` : "Full trailer"));
      const list = el("div", "bd-players");
      for (const p of n.players) {
        const row = el("div", "bd-player");
        const b = el("button", "", `▶  ${p.title}`);
        b.addEventListener("click", () => {
          const was = row.querySelector(".bd-play");
          for (const o of list.querySelectorAll(".bd-play")) o.remove();
          for (const o of list.querySelectorAll("button")) o.classList.remove("on");
          if (was) return;
          b.classList.add("on");
          const w = el("div", "bd-play");
          const f = document.createElement("iframe");
          f.src = p.src + (p.src.includes("?") ? "&" : "?") + "autoplay=1";
          f.title = p.title;
          f.allow = "autoplay; fullscreen; picture-in-picture; encrypted-media";
          f.allowFullscreen = true;
          f.referrerPolicy = "strict-origin-when-cross-origin";
          w.append(f);
          row.append(w);
        });
        row.append(b);
        list.append(row);
      }
      loupe.append(list);
    }

    // **Every sort the board has, each its own control** — columns as a row
    // of choices, a line as a slider between its two words.
    for (const x of sorts) {
      loupe.append(el("p", "bd-h", x.name));
      loupe.append(sortControl(x, [n], () => { if (open === n) openLoupe(n, true); }));
    }

    const mine = ties.filter((t) => t.a === n.id || t.b === n.id);
    if (mine.length) {
      loupe.append(el("p", "bd-h", `Tied to ${mine.length}`));
      const list = el("div", "bd-tied");
      for (const t of mine) {
        const o = nodes.get(t.a === n.id ? t.b : t.a);
        if (!o) continue;
        const b = el("button", t.kind === "tension" ? "tension" : "");
        b.append(document.createTextNode(o.kind === "note" ? (o.text || "Note").slice(0, 40) : o.title));
        if (t.label) b.append(el("span", "", `— ${t.label}`));
        b.addEventListener("click", () => { openLoupe(o); flyToNode(o); });
        list.append(b);
      }
      loupe.append(list);
    }
    if (mayEdit) {
      const row = el("div", "bd-mix");
      row.style.marginTop = "24px";
      if (foldable(n)) {
        const fold = el("button", "", n.folded ? "Expand Card" : "Collapse Card");
        fold.addEventListener("click", () => setFold([n], !n.folded));
        row.append(fold);
      }
      if (bareable(n)) {
        const bb = el("button", "", n.bare ? "Show Card" : "Picture Only");
        bb.addEventListener("click", () => setBare([n], !n.bare));
        row.append(bb);
      }
      if (n.size) {
        const rz = el("button", "", "Reset Size");
        rz.addEventListener("click", () => { resetSize([n]); openLoupe(n, true); });
        row.append(rz);
      }
      const rm = el("button", "", "Delete");
      rm.addEventListener("click", () => takeOff([n]));
      row.append(rm);
      loupe.append(row);
    }
    block.classList.add("loupe-on");
    loupe.scrollTop = scroll;
    refocus();
  }
  function closeLoupe() {
    open = null;
    block.classList.remove("loupe-on");
    loupe.querySelectorAll("iframe, video").forEach((f) => f.remove());
    refocus();
  }

  function enlarge(fig) {
    const big = el("div", "bd-big");
    const im = el(fig.clip ? "video" : "img");
    if (fig.clip) Object.assign(im, { muted: true, loop: true, autoplay: true, playsInline: true });
    im.src = fig.src;
    big.append(im);
    if (fig.cap) big.append(el("p", "", fig.cap));
    big.addEventListener("click", () => big.remove());
    block.append(big);
  }

  function dragStill(e, from, fig) {
    e.preventDefault();
    const sx = e.clientX, sy = e.clientY;
    let ghost = null;
    const move = (m) => {
      if (!ghost && Math.hypot(m.clientX - sx, m.clientY - sy) > 6) {
        ghost = el("div", "bd-ghost");
        const im = el("img");
        im.src = fig.clip ? fig.poster : fig.src;
        ghost.append(im);
        block.append(ghost);
        if (innerWidth <= 700) block.classList.remove("loupe-on");
      }
      if (ghost) { ghost.style.left = `${m.clientX}px`; ghost.style.top = `${m.clientY}px`; }
    };
    const up = (u) => {
      removeEventListener("pointermove", move);
      removeEventListener("pointerup", up);
      removeEventListener("pointercancel", up);
      if (!ghost) { enlarge(fig); return; }
      ghost.remove();
      const lr = loupe.getBoundingClientRect();
      const vr = vp.getBoundingClientRect();
      const overLoupe = block.classList.contains("loupe-on") && u.clientX >= lr.left && u.clientY >= lr.top;
      const inside = u.clientX >= vr.left && u.clientX <= vr.right && u.clientY >= vr.top && u.clientY <= vr.bottom;
      if (u.type === "pointercancel" || overLoupe || !inside) {
        if (open) block.classList.add("loupe-on");
        return;
      }
      addStill(from, fig, toWorld(u.clientX, u.clientY));
      if (open) block.classList.add("loupe-on");
    };
    addEventListener("pointermove", move);
    addEventListener("pointerup", up);
    addEventListener("pointercancel", up);
  }

  // ---------------------------------------------------------------- pointer
  const pointers = new Map();
  let gesture = null;

  function nodeAt(w) {
    let best = null;
    for (const n of nodes.values()) {
      if (Math.abs(w.x - n.x) <= n.w / 2 && Math.abs(w.y - n.y) <= n.h / 2) {
        if (!best || Number(n.el.style.zIndex || 0) > Number(best.el.style.zIndex || 0)) best = n;
      }
    }
    return best;
  }

  function nearestWell(n) {
    if (!geo.cams || n.ty > geo.cams.undecY) return "";
    let best = "", bd = Infinity;
    for (const [k, x] of Object.entries(geo.cams.xs)) {
      const d = Math.abs(n.tx - x);
      if (d < bd) { bd = d; best = k; }
    }
    return best;
  }

  // ---------------------------------------------------------------- picking
  // **Several cards at once.** His ask, 2026-09-23: select tiles of every
  // kind and set their parameters together — a common link, the Observe ↔
  // Move slider. Shift-click adds or drops one; shift-drag on the board (or
  // any drag with *Select* on) draws a box. A bar then sets the camera and
  // the slider for all of them, links them all to one card, or takes the
  // ones he made off the board. Dragging one moves the lot.
  const picked = new Set();
  let linking = false;
  let selecting = false;
  const selbar = el("div", "bd-selbar");
  block.append(selbar);
  function pick(n, on) {
    if (on) picked.add(n); else picked.delete(n);
    n.el.classList.toggle("picked", on);
    refocus();
  }
  function clearPick() {
    for (const n of [...picked]) pick(n, false);
    linking = false;
    block.classList.remove("linking");
    drawSelbar();
  }
  function drawSelbar() {
    for (const n of [...picked]) if (!nodes.has(n.id)) picked.delete(n);
    block.classList.toggle("picking", picked.size > 0);
    selbar.innerHTML = "";
    if (!picked.size) return;
    const list = [...picked];
    if (linking) {
      selbar.append(el("span", "bd-selcount", `Click the card to link these ${list.length} to`));
      const x = el("button", "", "Cancel");
      x.addEventListener("click", () => { linking = false; block.classList.remove("linking"); drawSelbar(); });
      selbar.append(x);
      return;
    }
    selbar.append(el("span", "bd-selcount", `${list.length} selected`));
    // The sort being looked at, or every sort when the board is free — most
    // boards have one or two.
    for (const x of mode !== "free" && sortOf(mode) ? [sortOf(mode)] : sorts) {
      selbar.append(sortControl(x, list, () => {
        if (x.type === "columns" && mode === x.id) viewTo = fitView();
        if (open && picked.has(open)) openLoupe(open, true);
        drawSelbar();
      }));
    }
    const link = el("button", "bd-act2", "Link to…");
    link.title = "Tie every selected card to one card, with one label";
    link.addEventListener("click", () => { linking = true; block.classList.add("linking"); drawSelbar(); });
    selbar.append(link);
    if (mayEdit) {
      const rm = el("button", "bd-act2 warn", "Delete");
      rm.title = "Delete (⌫) — ⌘Z brings them back";
      rm.addEventListener("click", () => takeOff(list));
      selbar.append(rm);
    }
    const done = el("button", "bd-act2", "Done");
    done.addEventListener("click", clearPick);
    selbar.append(done);
  }
  function linkAll(target, e) {
    const made = [];
    for (const m of picked) {
      if (m === target || ties.some((t) => t.key === tieKey(m.id, target.id))) continue;
      made.push(addTie({ a: m.id, b: target.id, label: "", user: true, kind: "" }, 1));
    }
    linking = false;
    block.classList.remove("linking");
    drawTies();
    refocus();
    save();
    drawSelbar();
    if (made.length) editTie(made, e);
  }
  // ---------------------------------------------------------------- keys
  // **Delete, cut, copy, paste — the way every other board does them.** His
  // note, 2026-09-25: Backspace should delete a card, ⌘Z should undo, ⌘X
  // should work. What they act on: every picked card, else the one open.
  const targets = () => (picked.size ? [...picked].filter((m) => nodes.has(m.id)) : open && nodes.has(open.id) ? [open] : []);
  /** Collapse or expand cards — picture and name, or everything. */
  function setFold(list, on) {
    const them = list.filter((m) => nodes.has(m.id) && foldable(m));
    if (!them.length) return;
    for (const m of them) {
      m.folded = on;
      m.el.classList.toggle("folded", on);
      measure(m);
    }
    if (mode !== "free") layout();
    if (open && them.includes(open)) openLoupe(open, true);
    refocus();
    save();
    wake();
  }
  /** Show cards as their picture alone, or put them back on a card. */
  function setBare(list, on) {
    const them = list.filter((m) => nodes.has(m.id) && bareable(m));
    if (!them.length) return;
    for (const m of them) setLook(m, { bare: on });
    if (mode !== "free") layout();
    if (open && them.includes(open)) openLoupe(open, true);
    refocus();
    save();
    wake();
  }
  /** Cards back to the size they were made. */
  function resetSize(list) {
    const them = list.filter((m) => nodes.has(m.id) && m.size);
    if (!them.length) return;
    for (const m of them) setLook(m, { size: 1 });
    if (mode !== "free") layout();
    drawTies();
    sharpen();
    refocus();
    save();
    wake();
  }
  function takeOff(list) {
    if (!mayEdit) return;
    for (const m of list) if (nodes.has(m.id)) removeNode(m);
    drawSelbar();
  }
  /**
   * **Copied cards travel as the board keeps them**, under a type of their
   * own beside a plain line of their names, so pasting into another board —
   * or another tab — brings the cards, and pasting into a note brings words.
   * Kept here too, for a browser that will not carry a type it does not know.
   */
  const CLIPTYPE = "application/x-shotlister-cards";
  let clipMem = null, clipNow = null, pasteWait = 0;
  function cardsOf(list) {
    const ids = new Set(list.map((m) => m.id));
    const text = list.map((m) => (m.kind === "note" || m.kind === "heading" ? m.text || "" : m.title || m.cap || "")).filter(Boolean).join("\n") || "Cards";
    return {
      text,
      got: { cards: list.map((m) => cardOut(m)), ties: ties.filter((t) => ids.has(t.a) && ids.has(t.b)).map((t) => ({ a: t.a, b: t.b, label: t.label || "" })) },
    };
  }
  function copyCards(list, cut) {
    if (!list.length) return;
    clipMem = cardsOf(list);
    clipNow = { at: Date.now(), cut: cut ? list : null };
    // The browser's own copy runs next and carries them out; if it does not
    // run, the board still has them.
    setTimeout(() => {
      if (clipNow && clipNow.cut) takeOff(clipNow.cut);
      clipNow = null;
    }, 0);
  }
  document.addEventListener("copy", (e) => onClip(e));
  document.addEventListener("cut", (e) => onClip(e));
  function onClip(e) {
    if (!block.isConnected || !clipNow || Date.now() - clipNow.at > 500 || !e.clipboardData) return;
    e.preventDefault();
    e.clipboardData.setData("text/plain", clipMem.text);
    try { e.clipboardData.setData(CLIPTYPE, JSON.stringify(clipMem.got)); } catch { /* the words still go */ }
  }
  /** Pasted cards land where the pointer is, or in the middle of the view. */
  function pasteCards(got) {
    if (!mayEdit || !got || !Array.isArray(got.cards)) return false;
    const list = got.cards.filter((c) => c && KINDS[c.kind]);
    if (!list.length) return false;
    const xs = list.map((c) => Number(c.x) || 0), ys = list.map((c) => Number(c.y) || 0);
    const cx = (Math.min(...xs) + Math.max(...xs)) / 2, cy = (Math.min(...ys) + Math.max(...ys)) / 2;
    const r = vp.getBoundingClientRect();
    const onBoard = lastAt && Date.now() - lastAt.t < 120000 && lastAt.x >= r.left && lastAt.x <= r.right && lastAt.y >= r.top && lastAt.y <= r.bottom;
    let at = onBoard ? toWorld(lastAt.x, lastAt.y) : middle();
    // Pasted over where they were copied from, they step aside, so both show.
    if (Math.hypot(at.x - cx, at.y - cy) < 40) at = { x: cx + 48, y: cy + 48 };
    const ids = new Map();
    clearPick();
    for (const c of list) {
      const id = newId(`${c.kind}-`);
      ids.set(c.id, id);
      const x = at.x + (Number(c.x) || 0) - cx, y = at.y + (Number(c.y) || 0) - cy;
      const n = addNode({ figs: [], clips: [], players: [], ...c, id, user: true, x, y }, false);
      n.fx = x; n.fy = y; n.sc = 1.08;
      n.el.style.zIndex = ++z;
      pick(n, true);
    }
    for (const t of got.ties || []) {
      if (ids.has(t.a) && ids.has(t.b)) addTie({ a: ids.get(t.a), b: ids.get(t.b), label: String(t.label || ""), user: true, kind: "" }, 1);
    }
    if (mode !== "free") layout();
    block.classList.add("has-cards");
    drawSelbar();
    refocus();
    save();
    wake();
    return true;
  }
  /** Start the note line on a card — shown, and typed into. */
  function noteOn(n) {
    if (n.kind === "heading") { startEdit(n); return; }
    const t = n.el.querySelector(".bd-t");
    if (!t) { openLoupe(n); const box = loupe.querySelector(".bd-note"); if (box) box.focus(); return; }
    t.hidden = false;
    measure(n);
    wake();
    t.focus();
    const rg = document.createRange();
    rg.selectNodeContents(t);
    rg.collapse(false);
    const sel = (t.getRootNode().getSelection ? t.getRootNode() : window).getSelection();
    sel.removeAllRanges();
    sel.addRange(rg);
  }

  // **A card's own menu, on a right-click.** His note, 2026-09-25: notes are
  // started from a card's menu rather than sitting empty on every card.
  const ctx = el("div", "bd-ctx");
  block.append(ctx);
  function closeCtx() { ctx.classList.remove("on"); }
  const MAC = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || "");
  const keyOf = (k) => (MAC ? `⌘${k}` : `Ctrl+${k}`);
  function showCtx(n, e) {
    closeMenus();
    ctx.innerHTML = "";
    const item = (label, key, act, danger) => {
      const b = el("button", danger ? "danger" : "");
      b.append(document.createTextNode(label));
      if (key) b.append(el("kbd", "", key));
      b.addEventListener("click", () => { closeCtx(); act(); });
      ctx.append(b);
    };
    const line = () => ctx.append(el("hr"));
    if (n) {
      // Several picked and this one among them: the menu is for all of them.
      const list = picked.has(n) && picked.size > 1 ? [...picked] : [n];
      const many = list.length > 1;
      if (!many) item("Open", "", () => { openLoupe(n); flyToNode(n); });
      if (!many && mayEdit && n.kind !== "heading") item(n.text ? "Edit Note" : "Add Note", "", () => noteOn(n));
      if (!many && n.kind === "heading" && mayEdit) item("Edit", "", () => startEdit(n));
      if (!many && (n.kind === "still" || n.kind === "clip") && mayShot()) item("Add to Shot…", "", () => openToShot(n));
      const folds = list.filter(foldable);
      if (folds.length && mayEdit) {
        const shut = folds.every((m) => m.folded);
        const count = folds.length > 1 ? ` ${folds.length}` : "";
        item(shut ? `Expand${count}` : `Collapse${count}`, "", () => setFold(folds, !shut));
      }
      const pics = list.filter(bareable);
      if (pics.length && mayEdit) {
        const all = pics.every((m) => m.bare);
        const count = pics.length > 1 ? ` ${pics.length}` : "";
        item(all ? `Show Card${pics.length > 1 ? "s" : ""}${count}` : `Picture Only${count}`, "", () => setBare(pics, !all));
      }
      const sized = list.filter((m) => m.size);
      if (sized.length && mayEdit) item(sized.length > 1 ? `Reset Size ${sized.length}` : "Reset Size", "", () => resetSize(sized));
      line();
      item(many ? `Copy ${list.length}` : "Copy", keyOf("C"), () => { clipMem = cardsOf(list); });
      if (mayEdit) {
        item(many ? `Cut ${list.length}` : "Cut", keyOf("X"), () => { clipMem = cardsOf(list); takeOff(list); });
        item("Duplicate", keyOf("D"), () => { const was = clipMem; pasteCards(cardsOf(list).got); clipMem = was; });
        if (clipMem) item("Paste", keyOf("V"), () => pasteCards(clipMem.got));
        line();
        item(many ? `Delete ${list.length}` : "Delete", "⌫", () => takeOff(list), true);
      }
    } else {
      if (!mayEdit) return;
      const w = toWorld(e.clientX, e.clientY);
      item("New Note", "", () => addNote(w));
      if (clipMem) item("Paste", keyOf("V"), () => pasteCards(clipMem.got));
      item("Select All", keyOf("A"), selectAll);
      const folds = [...nodes.values()].filter(foldable);
      if (folds.length) {
        line();
        if (folds.some((m) => !m.folded)) item("Collapse All", "", () => setFold(folds, true));
        if (folds.some((m) => m.folded)) item("Expand All", "", () => setFold(folds, false));
      }
      const pics = [...nodes.values()].filter(bareable);
      if (pics.length) {
        if (!folds.length) line();
        if (pics.some((m) => !m.bare)) item("All Pictures Only", "", () => setBare(pics, true));
        if (pics.some((m) => m.bare)) item("All as Cards", "", () => setBare(pics, false));
      }
    }
    while (ctx.lastChild && ctx.lastChild.tagName === "HR") ctx.lastChild.remove();
    if (!ctx.children.length) return;
    const r = block.getBoundingClientRect();
    ctx.classList.add("on");
    const x = Math.min(e.clientX - r.left, r.width - ctx.offsetWidth - 8);
    const y = Math.min(e.clientY - r.top, r.height - ctx.offsetHeight - 8);
    ctx.style.left = `${Math.max(8, x)}px`;
    ctx.style.top = `${Math.max(8, y)}px`;
  }
  function selectAll() {
    for (const n of nodes.values()) if (getComputedStyle(n.el).pointerEvents !== "none") pick(n, true);
    drawSelbar();
  }
  vp.addEventListener("contextmenu", (e) => {
    const path = e.composedPath ? e.composedPath() : [];
    // Typing in a note keeps the browser's own menu — spelling, paste.
    if (path.some((x) => x && (x.isContentEditable || x.tagName === "INPUT" || x.tagName === "TEXTAREA"))) return;
    e.preventDefault();
    const card = e.target.closest ? e.target.closest(".bd-n") : null;
    showCtx(card ? nodes.get(card.dataset.id) : null, e);
  });
  block.addEventListener("pointerdown", (e) => { if (!ctx.contains(e.target)) closeCtx(); }, true);

  const marq = el("div", "bd-marq");
  marq.style.display = "none";
  vp.append(marq);

  function startEdit(n) {
    const h = n.el.querySelector(".bd-hd");
    if (!h) return;
    h.contentEditable = "true";
    h.focus();
    const r = document.createRange();
    r.selectNodeContents(h);
    r.collapse(false);
    const sel = (h.getRootNode().getSelection ? h.getRootNode() : window).getSelection();
    sel.removeAllRanges();
    sel.addRange(r);
  }

  // **The middle button pans**, wherever it is pressed — over a card too —
  // the way every canvas app he uses does. His note, 2026-09-25. The browser's
  // own autoscroll (a middle press on Windows) is kept out of it.
  vp.addEventListener("mousedown", (e) => { if (e.button === 1) e.preventDefault(); });
  vp.addEventListener("auxclick", (e) => { if (e.button === 1) e.preventDefault(); });
  vp.addEventListener("pointerdown", (e) => {
    if (e.pointerType === "mouse" && e.button === 1) {
      e.preventDefault();
      pop.classList.remove("on");
      closeCtx();
      viewTo = null;
      pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
      try { vp.setPointerCapture(e.pointerId); } catch { /* already gone */ }
      gesture = { pan: true, middle: true, sx: e.clientX, sy: e.clientY, vx: view.x, vy: view.y };
      vp.classList.add("panning");
      return;
    }
    if (e.button !== 0 && e.pointerType === "mouse") return;
    pop.classList.remove("on");
    closeCtx();
    const card = e.target.closest ? e.target.closest(".bd-n") : null;
    const n = card ? nodes.get(card.dataset.id) : null;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    try { vp.setPointerCapture(e.pointerId); } catch { /* already gone */ }

    if (pointers.size === 2) {
      // A second finger turns whatever the first was doing into a pinch.
      if (gesture && gesture.node) { gesture.node.drag = false; gesture.node.el.classList.remove("lift"); gesture.node.el.removeAttribute("data-read"); }
      const [a, b] = [...pointers.values()];
      gesture = { pinch: true, d: Math.hypot(a.x - b.x, a.y - b.y), s: view.s, mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }, vx: view.x, vy: view.y };
      return;
    }
    const w = toWorld(e.clientX, e.clientY);
    if (n && e.target.classList.contains("bd-rs") && mayEdit) {
      // Dragged by its corner, a card grows or shrinks from its top-left —
      // and the words it is dragged across are not picked up as a selection.
      e.preventDefault();
      getSelection().removeAllRanges();
      gesture = { resize: n, tl: { x: n.x - n.w / 2, y: n.y - n.h / 2 }, was: n.size || 0 };
      n.el.classList.add("sizing");
      n.el.style.zIndex = ++z;
      return;
    }
    if (n && e.target.classList.contains("bd-pin")) {
      gesture = { tie: n };
      drawing.style.display = "";
      return;
    }
    if (n && linking) {
      gesture = { link: n, sx: e.clientX, sy: e.clientY };
      return;
    }
    if (n) {
      gesture = { node: n, off: { x: w.x - n.tx, y: w.y - n.ty }, sx: e.clientX, sy: e.clientY, moved: false,
        toggle: e.shiftKey || e.metaKey || e.ctrlKey,
        group: picked.has(n) && picked.size > 1 ? [...picked].map((m) => ({ m, off: { x: w.x - m.tx, y: w.y - m.ty } })) : null };
      for (const m of gesture.group ? picked : [n]) m.el.style.zIndex = ++z;
      // **A finger moves the board; a finger held picks the card up.** His
      // note, 2026-09-25, on the phone: on a full board nearly every touch
      // lands on a card, so a drag moved cards when he meant to look
      // around. With a finger a drag pans, a tap opens, and a card is only
      // lifted once it has been held still for a moment.
      if (e.pointerType === "touch") {
        const g = gesture;
        Object.assign(g, { touch: true, held: false, vx: view.x, vy: view.y });
        setTimeout(() => {
          if (gesture !== g || g.moved) return;
          g.held = true;
          for (const m of g.group ? g.group.map((x) => x.m) : [n]) m.el.classList.add("lift");
          if (navigator.vibrate) navigator.vibrate(8);
        }, 380);
      }
      return;
    }
    viewTo = null;
    // Shift- or ⌘-drag on the empty board draws a box.
    if (e.shiftKey || e.metaKey || e.ctrlKey || selecting) {
      gesture = { marq: true, sx: e.clientX, sy: e.clientY };
      return;
    }
    gesture = { pan: true, sx: e.clientX, sy: e.clientY, vx: view.x, vy: view.y };
    vp.classList.add("panning");
  });

  let lastAt = null;
  vp.addEventListener("pointermove", (e) => {
    lastAt = { x: e.clientX, y: e.clientY, t: Date.now() };
    if (pointers.has(e.pointerId)) pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (!gesture) {
      if (e.pointerType !== "mouse") return;
      const card = e.target.closest ? e.target.closest(".bd-n") : null;
      const n = card ? nodes.get(card.dataset.id) : null;
      if (n !== hover) { hover = n; refocus(); }
      return;
    }
    if (gesture.pinch && pointers.size >= 2) {
      const [a, b] = [...pointers.values()];
      const d = Math.hypot(a.x - b.x, a.y - b.y);
      const s = clamp(gesture.s * (d / gesture.d), FARTHEST, 2.2);
      const r = vp.getBoundingClientRect();
      const mx = gesture.mid.x - r.left, my = gesture.mid.y - r.top;
      const nx = (a.x + b.x) / 2 - r.left, ny = (a.y + b.y) / 2 - r.top;
      view.x = nx - (mx - gesture.vx) * (s / gesture.s);
      view.y = ny - (my - gesture.vy) * (s / gesture.s);
      view.s = s;
      applyView();
      return;
    }
    if (gesture.marq) {
      const r = vp.getBoundingClientRect();
      const x0 = Math.min(gesture.sx, e.clientX) - r.left, y0 = Math.min(gesture.sy, e.clientY) - r.top;
      Object.assign(marq.style, { display: "", left: `${x0}px`, top: `${y0}px`,
        width: `${Math.abs(e.clientX - gesture.sx)}px`, height: `${Math.abs(e.clientY - gesture.sy)}px` });
      return;
    }
    if (gesture.pan) {
      view.x = gesture.vx + (e.clientX - gesture.sx);
      view.y = gesture.vy + (e.clientY - gesture.sy);
      applyView();
      return;
    }
    if (gesture.resize) {
      const n = gesture.resize, { tl } = gesture;
      const w = toWorld(e.clientX, e.clientY);
      // The corner follows the pointer along the card's own diagonal.
      const dx = w.x - tl.x, dy = w.y - tl.y;
      setLook(n, { size: (dx * n.bw + dy * n.bh) / (n.bw * n.bw + n.bh * n.bh) });
      n.x = n.tx = tl.x + n.w / 2;
      n.y = n.ty = tl.y + n.h / 2;
      place(n);
      drawTies();
      return;
    }
    if (gesture.tie) {
      const p = pinOf(gesture.tie);
      const w = toWorld(e.clientX, e.clientY);
      drawing.setAttribute("d", `M${p.x} ${p.y} L${w.x} ${w.y}`);
      const over = nodeAt(w);
      if (over !== hover) { hover = over && over !== gesture.tie ? over : null; refocus(); }
      return;
    }
    if (gesture.node && gesture.touch && !gesture.held) {
      if (Math.hypot(e.clientX - gesture.sx, e.clientY - gesture.sy) < 10) return;
      const g = gesture;
      gesture = { pan: true, sx: g.sx, sy: g.sy, vx: g.vx, vy: g.vy };
      vp.classList.add("panning");
      view.x = gesture.vx + (e.clientX - gesture.sx);
      view.y = gesture.vy + (e.clientY - gesture.sy);
      applyView();
      return;
    }
    if (gesture.node) {
      const n = gesture.node;
      if (!gesture.moved && Math.hypot(e.clientX - gesture.sx, e.clientY - gesture.sy) < 5) return;
      if (!gesture.moved) {
        gesture.moved = true;
        for (const m of gesture.group ? gesture.group.map((g) => g.m) : [n]) { m.drag = true; m.el.classList.add("lift"); }
        block.classList.add("dragging");
        hover = n; refocus();
      }
      const w = toWorld(e.clientX, e.clientY);
      n.tx = w.x - gesture.off.x;
      n.ty = w.y - gesture.off.y;
      if (gesture.group) for (const g of gesture.group) { g.m.tx = w.x - g.off.x; g.m.ty = w.y - g.off.y; }
      sayHolding(gesture.group ? gesture.group.map((g) => g.m) : [n]);
      const on = sortOf(mode);
      if (on && on.type === "line") {
        const p = clamp(0.5 + n.tx / (2 * SPAN), 0, 1);
        const [l, r] = on.ends.map((e) => String(e).toLowerCase());
        n.el.dataset.read = p < 0.45 ? `${Math.round((1 - p) * 100)}% ${l}` : p > 0.55 ? `${Math.round(p * 100)}% ${r}` : "right between";
      }
      if (on && on.type === "columns") {
        const k = nearestWell(n);
        for (const d of guides.querySelectorAll(".bd-well")) d.classList.toggle("hot", d.dataset.well === k);
      }
      wake();
    }
  });

  function endPointer(e) {
    pointers.delete(e.pointerId);
    if (!gesture) return;
    if (gesture.pinch) {
      if (pointers.size === 0) gesture = null;
      return;
    }
    const g = gesture;
    gesture = null;
    vp.classList.remove("panning");
    if (g.marq) {
      marq.style.display = "none";
      const a = toWorld(Math.min(g.sx, e.clientX), Math.min(g.sy, e.clientY));
      const b = toWorld(Math.max(g.sx, e.clientX), Math.max(g.sy, e.clientY));
      if (Math.hypot(e.clientX - g.sx, e.clientY - g.sy) < 5) { clearPick(); return; }
      for (const n of nodes.values()) {
        if (getComputedStyle(n.el).pointerEvents === "none") continue;
        if (n.x + n.w / 2 >= a.x && n.x - n.w / 2 <= b.x && n.y + n.h / 2 >= a.y && n.y - n.h / 2 <= b.y) pick(n, true);
      }
      drawSelbar();
      return;
    }
    if (g.link) {
      if (Math.hypot(e.clientX - g.sx, e.clientY - g.sy) < 6) linkAll(g.link, e);
      return;
    }
    if (g.resize) {
      const n = g.resize;
      n.el.classList.remove("sizing");
      if ((n.size || 0) === g.was) return;
      if (mode === "free") { n.fx = n.tx; n.fy = n.ty; } else layout();
      sharpen();
      if (open === n) openLoupe(n, true);
      refocus();
      save();
      wake();
      return;
    }
    if (g.pan && !g.middle && Math.hypot(e.clientX - g.sx, e.clientY - g.sy) < 4 && picked.size) {
      clearPick();
      return;
    }
    if (g.tie) {
      drawing.style.display = "none";
      const target = nodeAt(toWorld(e.clientX, e.clientY));
      hover = null;
      if (target && target !== g.tie && !ties.some((t) => t.key === tieKey(g.tie.id, target.id))) {
        const t = addTie({ a: g.tie.id, b: target.id, label: "", user: true, kind: "" }, 1);
        drawTies();
        refocus();
        save();
        editTie(t, e);
      } else refocus();
      return;
    }
    if (g.node) {
      const n = g.node;
      if (!g.moved) {
        if (g.held) for (const m of g.group ? g.group.map((x) => x.m) : [n]) m.el.classList.remove("lift");
        if (e.type === "pointercancel") return;
        if (g.toggle) {
          // **⌘-click starts a selection from what is already chosen.** His
          // note, 2026-09-25: ⌘-click "doesn't work" — it did, but a card
          // clicked open first was left out, so ⌘-clicking a second picked
          // one card and it never looked like several. The open card joins.
          if (!picked.size && open && open !== n && nodes.has(open.id)) pick(open, true);
          pick(n, !picked.has(n));
          drawSelbar();
          return;
        }
        if (n.kind === "heading") { startEdit(n); return; }
        openLoupe(n); flyToNode(n);
        return;
      }
      block.classList.remove("dragging");
      const moved = g.group ? g.group.map((x) => x.m) : [n];
      say({ holding: [] });
      const on = sortOf(mode);
      const well = on && on.type === "columns" ? nearestWell(n) : "";
      for (const m of moved) {
        m.drag = false;
        m.el.classList.remove("lift");
        m.el.removeAttribute("data-read");
        if (!on) { m.fx = m.tx; m.fy = m.ty; }
        else if (on.type === "line") m.vals[on.id] = clamp(0.5 + m.tx / (2 * SPAN), 0, 1);
        else m.vals[on.id] = well;
        paintTags(m);
      }
      for (const d of guides.querySelectorAll(".bd-well")) d.classList.remove("hot");
      if (mode !== "free") layout();
      if (picked.size) drawSelbar();
      if (open === n) openLoupe(n, true);
      hover = null;
      refocus();
      save();
      wake();
      // **A picture laid on a shot is asked about, never filed.** His
      // question, 2026-09-25: should it go to that shot in Shotlister too?
      // Only when he says so — a board is for playing around.
      if (!g.group && (n.kind === "still" || n.kind === "clip") && mayShot()) {
        const w = toWorld(e.clientX, e.clientY);
        const under = [...nodes.values()].filter((m) => m !== n && m.kind === "shot" && m.live
          && Math.abs(w.x - m.x) <= m.w / 2 && Math.abs(w.y - m.y) <= m.h / 2)
          .sort((p, q) => Number(q.el.style.zIndex || 0) - Number(p.el.style.zIndex || 0))[0];
        if (under) offerShot(n, under, e);
      }
    }
  }
  vp.addEventListener("pointerup", endPointer);
  vp.addEventListener("pointercancel", endPointer);
  vp.addEventListener("pointerleave", () => { if (!gesture && hover) { hover = null; refocus(); } });

  vp.addEventListener("dblclick", (e) => {
    if (e.target.closest && e.target.closest(".bd-n")) return;
    addNote(toWorld(e.clientX, e.clientY));
  });

  vp.addEventListener("wheel", (e) => {
    e.preventDefault();
    viewTo = null;
    if (e.ctrlKey || e.metaKey) {
      const r = vp.getBoundingClientRect();
      const mx = e.clientX - r.left, my = e.clientY - r.top;
      const s = clamp(view.s * Math.exp(-e.deltaY * 0.01), FARTHEST, 2.2);
      view.x = mx - (mx - view.x) * (s / view.s);
      view.y = my - (my - view.y) * (s / view.s);
      view.s = s;
    } else {
      view.x -= e.deltaX;
      view.y -= e.deltaY;
    }
    applyView();
  }, { passive: false });

  // ---------------------------------------------------------------- toolbar
  const seg = el("div", "bd-seg");
  /** Free, then one button per sort, then the way to make another. */
  function drawSeg() {
    seg.innerHTML = "";
    for (const [m, name, short] of [["free", "Free", "Free"], ...sorts.map((x) => [x.id, x.name, x.short || x.name])]) {
      const b = el("button", m === mode ? "on" : "");
      b.append(el("span", "lg", name), el("span", "sm", short));
      b.dataset.mode = m;
      b.addEventListener("click", () => setMode(m));
      seg.append(b);
    }
    if (mayEdit && (block.dataset.api || sorts.length)) {
      const add = el("button", "", "+ Sort");
      add.title = "Add a way to sort the cards";
      add.addEventListener("click", () => openSorts(true));
      seg.append(add);
    }
  }
  const legend = el("div", "bd-legend");
  const colours = { ref: "var(--gold)", test: "var(--sage)", scene: "var(--rose)", idea: "var(--ink)", gear: "var(--steel)", still: "#F1ECE4", clip: "#E0584A", note: "var(--paper)", heading: "var(--ink)" };
  // Only the kinds this board has, plus the three anyone can add to it.
  // Only the kinds this board has, plus the ones anyone can add to it — which,
  // on a Board page, is every kind there is.
  const present = block.dataset.api ? new Set(Object.keys(KINDS))
    : new Set([...authored.map((d) => d.kind), ...(saved.added || []).map((d) => d.kind), "clip", "still", "note", "heading"]);
  for (const k of Object.keys(KINDS)) {
    if (!present.has(k)) continue;
    const b = el("button");
    b.style.setProperty("--c", colours[k]);
    b.append(el("i"), document.createTextNode(KINDS[k].name));
    b.title = `Show or hide ${KINDS[k].name.toLowerCase()}`;
    b.addEventListener("click", () => { b.classList.toggle("off"); block.classList.toggle(`hide-${k}`); });
    legend.append(b);
  }
  const tools = el("div", "bd-tools");
  const noteB = el("button", "", "+ Note");
  noteB.addEventListener("click", () => {
    const r = vp.getBoundingClientRect();
    addNote(toWorld(r.left + r.width / 2, r.top + r.height / 2));
  });
  const fitB = el("button", "", "Fit");
  fitB.addEventListener("click", fit);
  const resetB = el("button", "", "Reset");
  resetB.title = "Put the board back as published — your moves, notes and threads go";
  resetB.addEventListener("click", () => {
    // **Done at once, with Undo in the pill** (`feel.js`): the board as it was
    // is kept here and in History, so there is nothing to ask.
    const before = JSON.parse(JSON.stringify(stateNow()));
    forget(KEY);
    saved = { at: saved.at, snap: saved.snap };
    gone.clear();
    closeLoupe();
    for (const n of nodes.values()) n.el.remove();
    nodes.clear();
    for (const t of ties) t.g.remove();
    ties = [];
    populate(true);
    layout();
    viewTo = fitView();
    wake();
    push(true);
    if (window.feel) feel.toast("Board Reset", { undo: () => { before.at = saved.at; rebuild(before); push("restore"); } });
  });
  const fullB = el("button", "", "⤢");
  fullB.title = "Full screen";
  fullB.addEventListener("click", () => {
    if (document.fullscreenElement) document.exitFullscreen();
    else if (block.requestFullscreen) block.requestFullscreen().catch(() => {});
  });
  const headB = el("button", "", "+ Heading");
  headB.addEventListener("click", () => {
    const r = vp.getBoundingClientRect();
    const at = toWorld(r.left + r.width / 2, r.top + r.height / 2);
    if (mode !== "free") setMode("free");
    const n = addNode({ id: newId("hd-"), kind: "heading", x: at.x, y: at.y, user: true, text: "" }, false);
    n.sc = 0.8;
    n.el.style.zIndex = ++z;
    save();
    wake();
    requestAnimationFrame(() => startEdit(n));
  });
  const selB = el("button", "", "Select");
  selB.title = "Drag on the board to box-select cards (or hold shift)";
  selB.addEventListener("click", () => { selecting = !selecting; selB.classList.toggle("on", selecting); vp.classList.toggle("selecting", selecting); });
  // His note, 2026-09-23: not even tails at rest — "only on hover".
  const THREADS = [["hover", "Threads: show on hover"], ["all", "Threads: always show"]];
  let threads = pref.threads === "all" ? "all" : "hover";
  const threadB = el("button");
  threadB.title = "On hover: a card's threads show when you point at it, open it or select it";
  const paintThreads = () => {
    block.classList.toggle("threads-all", threads === "all");
    threadB.textContent = THREADS.find(([k]) => k === threads)[1];
    drawTies();
  };
  threadB.addEventListener("click", () => {
    threads = THREADS[(THREADS.findIndex(([k]) => k === threads) + 1) % THREADS.length][0];
    paintThreads();
    pref.threads = threads;
    keepPref();
  });
  paintThreads();
  const pubB = el("button");
  pubB.title = "Whether people who open the portal's share link can change this board. Click to switch.";
  pubB.addEventListener("click", async () => {
    try {
      const r = await fetch(`${REMOTE}/settings`, { method: "PUT", credentials: "same-origin",
        headers: { "content-type": "application/json" }, body: JSON.stringify({ publicEdit: !publicEdit }) });
      if (!r.ok) throw new Error(String(r.status));
      publicEdit = Boolean((await r.json()).publicEdit);
      paintAdmin();
    } catch { sayState("Couldn't change that", true); }
  });
  const histB = el("button", "", "History");
  histB.title = "Earlier versions of this board — put one back";
  histB.addEventListener("click", openHistory);
  function paintAdmin() {
    pubB.hidden = histB.hidden = !isEditor;
    // Editing from the link only means something once the link opens it.
    if (share && share !== "link") pubB.hidden = true;
    pubB.textContent = publicEdit ? "Link visitors can edit ✓" : "Link visitors can only view";
    pubB.classList.toggle("on", publicEdit);
    resetB.hidden = !mayEdit || !authored.length;
    sortsB.hidden = !mayEdit;
    addWrap.hidden = !mayEdit;
    for (const b of emptyBtns) b.hidden = !mayEdit;
    if (typeof drawSeg === "function") drawSeg();
    paintShare();
  }


  async function openHistory() {
    open = null;
    loupe.innerHTML = "";
    const close = el("button", "bd-close", "×");
    close.addEventListener("click", closeLoupe);
    const head = el("div", "bd-lhead");
    head.append(close);
    loupe.append(head, el("p", "bd-k", "This board"), el("h2", "", "History"));
    loupe.append(el("p", "bd-lead", "A copy is kept every ten minutes while people work, and before anything big is cleared. Putting one back keeps the current board here too, so it can be undone."));
    const list = el("div", "bd-hist");
    list.append(el("p", "bd-meta", "Loading…"));
    loupe.append(list);
    block.classList.add("loupe-on");
    let versions = [];
    try {
      const r = await fetch(`${REMOTE}/history`, { credentials: "same-origin", cache: "no-store" });
      if (!r.ok) throw new Error(String(r.status));
      versions = (await r.json()).versions || [];
    } catch {
      list.innerHTML = "";
      list.append(el("p", "bd-meta", "Couldn't load the history."));
      return;
    }
    list.innerHTML = "";
    if (!versions.length) list.append(el("p", "bd-meta", "No earlier versions yet. One is kept as soon as the board has been worked on for a while."));
    const when = (iso) => { try { return new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }); } catch { return iso; } };
    for (const v of versions) {
      const row = el("div", "bd-hrow");
      const t = el("div", "bd-htext");
      t.append(el("b", "", when(v.at)), el("span", "", `${v.by || "someone"} · ${v.cards} added · ${v.threads} threads`));
      const back = el("button", "", "Put back");
      back.addEventListener("click", async () => {
        const was = JSON.parse(JSON.stringify(stateNow()));
        try {
          const r = await fetch(`${REMOTE}/history/${v.id}`, { credentials: "same-origin", cache: "no-store" });
          if (!r.ok) throw new Error(String(r.status));
          const old = await r.json();
          old.at = saved.at;
          rebuild(old);
          push("restore");
          closeLoupe();
          if (window.feel) feel.toast("Board Put Back", { undo: () => { was.at = saved.at; rebuild(was); push("restore"); } });
        } catch { sayState("Couldn't put that back", true); }
      });
      row.append(t, back);
      list.append(row);
    }
  }
  // **Arranged by what a button is for.** His note, 2026-09-24: the bars
  // felt clunky — one long strip of everything, in no order. So: how you are
  // looking at the board, top left; small things about the board itself top
  // right — whether it is saved, what is shown, its settings, full screen;
  // and the things you make with, in a dock at the bottom, with the zoom.
  const menus = [];
  const closeMenus = () => { for (const w of menus) w.classList.remove("on"); };
  const menuOf = (label, title, items) => {
    const wrap = el("div", "bd-mwrap");
    const b = el("button", "bd-mbtn", label);
    b.title = title;
    const m = el("div", "bd-menu");
    m.append(...items);
    wrap.append(b, m);
    b.addEventListener("click", (e) => {
      e.stopPropagation();
      const on = !wrap.classList.contains("on");
      closeMenus();
      wrap.classList.toggle("on", on);
    });
    menus.push(wrap);
    return wrap;
  };
  block.addEventListener("pointerdown", (e) => { if (!e.target.closest || !e.target.closest(".bd-mwrap")) closeMenus(); }, true);
  // ---------------------------------------------------------------- sharing
  // **Only Me, Crew, Anyone with the Link.** His ruling, 2026-09-25: a board
  // is his sketchpad first and shared when he chooses. His alone to change;
  // anybody else sees nothing here, because nothing here is theirs to set.
  const SHARE_SAID = { me: "Only Me", crew: "Crew", link: "Anyone with the Link" };
  const shareItems = Object.entries(SHARE_SAID).map(([k, name]) => {
    const b = el("button", "", name);
    b.dataset.share = k;
    b.addEventListener("click", async () => {
      closeMenus();
      try {
        const r = await fetch(`${REMOTE}/share`, { method: "PUT", credentials: "same-origin",
          headers: { "content-type": "application/json" }, body: JSON.stringify({ share: k }) });
        if (!r.ok) throw new Error(String(r.status));
        share = (await r.json()).share;
        paintAdmin();
      } catch { sayState("Couldn't change that", true); }
    });
    return b;
  });
  const shareMenu = menuOf("Only Me", "Who can open this board", [el("p", "bd-mh", "Who Can Open It"), ...shareItems]);
  shareMenu.classList.add("bd-share");
  function paintShare() {
    shareMenu.hidden = !(share && isAdmin);
    if (!share) return;
    shareMenu.querySelector(".bd-mbtn").textContent = SHARE_SAID[share] || "Only Me";
    for (const b of shareItems) b.classList.toggle("on", b.dataset.share === share);
  }

  // ---------------------------------------------------------------- sorts
  /**
   * **The board's sorts, as a list he can change.** A name, and either the
   * two words at the ends of a line or the names of its columns. Nothing
   * else — no settings beyond what a sort is. Kept on the board, so it is
   * the same for everybody.
   */
  function keepSorts(next) {
    sorts = next;
    saved.lenses = next;
    if (mode !== "free" && !sortOf(mode)) mode = "free";
    for (const n of nodes.values()) paintTags(n);
    drawSeg();
    layout();
    save();
  }
  function sortSlug(name, taken) {
    let base = String(name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 24) || "sort";
    if (base === "obs" || base === "cam") base += "-2";
    let id = base, i = 2;
    while (taken.has(id)) id = `${base}-${i++}`;
    return id;
  }
  function openSorts(adding) {
    open = null;
    closeMenus();
    loupe.innerHTML = "";
    const close = el("button", "bd-close", "×");
    close.addEventListener("click", closeLoupe);
    const head = el("div", "bd-lhead");
    head.append(close);
    loupe.append(head, el("p", "bd-k", "This board"), el("h2", "", "Sorts"));
    const list = el("div", "bd-sorts");
    const field = (label, value, onChange) => {
      const l = el("label", "", label);
      const i = el("input");
      i.value = value;
      i.addEventListener("change", () => onChange(i.value.replace(/\s+/g, " ").trim()));
      return [l, i];
    };
    sorts.forEach((x, at) => {
      const box = el("div", "bd-sort");
      box.append(el("p", "bd-kind", x.type === "line" ? "Line" : "Columns"));
      box.append(...field("Name", x.name, (v) => { if (!v) return; keepSorts(sorts.map((y, i) => (i === at ? { ...y, name: v, short: undefined } : y))); }));
      if (x.type === "line") {
        const two = el("div", "bd-two");
        for (const e of [0, 1]) {
          const w = el("div");
          w.append(...field(e ? "Right" : "Left", x.ends[e], (v) => {
            if (!v) return;
            const ends = [...x.ends];
            ends[e] = v;
            keepSorts(sorts.map((y, i) => (i === at ? { ...y, ends, under: undefined } : y)));
          }));
          w.style.flex = "1";
          two.append(w);
        }
        box.append(two);
      } else {
        box.append(el("label", "", "Columns"));
        colsOf(x).forEach((c, ci) => {
          const row = el("div", "bd-col");
          const i = el("input");
          i.value = c.name;
          i.addEventListener("change", () => {
            const v = i.value.replace(/\s+/g, " ").trim();
            if (!v) return;
            keepSorts(sorts.map((y, yi) => (yi === at ? { ...y, cols: colsOf(y).map((d, di) => (di === ci ? { ...d, name: v, chip: undefined, pick: undefined, sub: v === d.name ? d.sub : undefined } : d)) } : y)));
          });
          const rm = el("button", "", "Remove");
          rm.addEventListener("click", () => {
            keepSorts(sorts.map((y, yi) => (yi === at ? { ...y, cols: colsOf(y).filter((_, di) => di !== ci) } : y)));
            openSorts();
          });
          row.append(i, rm);
          box.append(row);
        });
        const more = el("button", "", "+ Column");
        more.style.cssText = "margin-top:8px;font:600 12px RS,system-ui,sans-serif;background:transparent;border:1px solid var(--rule);color:var(--ink);border-radius:99px;padding:6px 10px;cursor:pointer";
        more.addEventListener("click", () => {
          const taken = new Set(colsOf(x).map((c) => c.id));
          const name = `Column ${colsOf(x).length + 1}`;
          keepSorts(sorts.map((y, yi) => (yi === at ? { ...y, cols: [...colsOf(y), { id: sortSlug(name, taken), name, tone: TONES[colsOf(y).length % TONES.length] }] } : y)));
          openSorts();
        });
        box.append(more);
      }
      const rm = el("button", "bd-srm", "Remove Sort");
      rm.addEventListener("click", () => {
        const before = sorts;
        keepSorts(sorts.filter((_, i) => i !== at));
        openSorts();
        if (window.feel) feel.toast("Sort Removed", { undo: () => { keepSorts(before); openSorts(); } });
      });
      box.append(rm);
      list.append(box);
    });
    if (!sorts.length) list.append(el("p", "bd-meta", "No sorts yet"));
    loupe.append(list);
    loupe.append(el("p", "bd-h", "Add a Sort"));
    const adds = el("div", "bd-addsort");
    const make = (type) => {
      const taken = new Set(sorts.map((x) => x.id));
      const name = type === "line" ? "New Line" : "New Columns";
      const one = type === "line"
        ? { id: sortSlug(name, taken), type, name, ends: ["Less", "More"] }
        : { id: sortSlug(name, taken), type, name, cols: [{ id: "one", name: "One", tone: TONES[0] }, { id: "two", name: "Two", tone: TONES[1] }] };
      keepSorts([...sorts, one]);
      setMode(one.id);
      openSorts();
      const inputs = loupe.querySelectorAll(".bd-sort");
      const last = inputs[inputs.length - 1];
      if (last) { const i = last.querySelector("input"); i.focus(); i.select(); }
    };
    const lineB = el("button", "", "Line");
    lineB.title = "Two words at either end — Observe ↔ Move";
    lineB.addEventListener("click", () => make("line"));
    const colB = el("button", "", "Columns");
    colB.title = "A column each — A-cam / B-cam";
    colB.addEventListener("click", () => make("columns"));
    adds.append(lineB, colB);
    loupe.append(adds);
    block.classList.add("loupe-on");
    refocus();
    if (adding && !sorts.length) lineB.focus();
  }
  const sortsB = el("button", "", "Sorts…");
  sortsB.title = "The ways this board's cards can be sorted";
  sortsB.addEventListener("click", () => openSorts());

  // ---------------------------------------------------------------- adding
  // **Anything, from anywhere.** A link pasted, a picture dropped, a clip
  // uploaded, and — his reminder, 2026-09-25 — *everything in the film*, as
  // standard: reference images, shots, scenes, locations, days, people,
  // documents. Each lands where it was dropped, or in the middle of the view.
  const busyEl = el("div", "bd-busy");
  const veil = el("div", "bd-veil", "Drop to add");
  block.append(busyEl, veil);
  let busyN = 0;
  const busy1 = (said) => { busyN++; busyEl.textContent = said; busyEl.classList.add("on"); };
  const busy0 = () => { if (--busyN <= 0) { busyN = 0; busyEl.classList.remove("on"); } };
  /** **The nearest empty spot to the middle of the view**, so things added one
   *  after another lay out side by side instead of landing in a pile. */
  const middle = () => {
    const r = vp.getBoundingClientRect();
    const room = block.classList.contains("loupe-on") && r.width > 700 ? r.width - loupe.offsetWidth - 20 : r.width;
    const at = toWorld(r.left + room / 2, r.top + r.height / 2);
    const free = (x, y) => ![...nodes.values()].some((n) => Math.abs(n.tx - x) < (n.w || 240) / 2 + 150 && Math.abs(n.ty - y) < (n.h || 200) / 2 + 130);
    // Ring by ring outwards; in each ring the same row first, then below,
    // then above — the top of the view is under the toolbar.
    for (let ring = 0; ring < 12; ring++) {
      const cells = [];
      for (let dy = -ring; dy <= ring; dy++) {
        for (let dx = -ring; dx <= ring; dx++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) === ring) cells.push([dx, dy]);
        }
      }
      cells.sort((a, b) => (a[1] < 0) - (b[1] < 0) || Math.abs(a[1]) - Math.abs(b[1]) || Math.abs(a[0]) - Math.abs(b[0]));
      for (const [dx, dy] of cells) {
        const x = at.x + dx * 300, y = at.y + dy * 280;
        if (free(x, y)) return { x, y };
      }
    }
    return { x: at.x + (Math.random() - 0.5) * 80, y: at.y + (Math.random() - 0.5) * 60 };
  };
  /** Put a card on the board — from anywhere — and keep it. */
  function putOn(data, at) {
    const spot = at || middle();
    const n = addNode({ id: newId(`${data.kind}-`), user: true, text: "", ...data, x: spot.x, y: spot.y }, false);
    n.x = spot.x; n.y = spot.y; n.sc = 1.15;
    n.el.style.zIndex = ++z;
    if (mode !== "free") layout();
    block.classList.add("has-cards");
    refocus();
    save();
    wake();
    if (n.kind === "doc") previewDoc(n);
    return n;
  }
  async function upload(file, at) {
    if (!REMOTE) { sayState("Pictures need the portal", true); return; }
    const moving = /^video\//.test(file.type) || /\.(mp4|mov|m4v)$/i.test(file.name);
    if (!/^image\//.test(file.type) && !moving) { sayState("Only pictures and clips", true); return; }
    busy1(`Adding ${file.name || (moving ? "clip" : "picture")}…`);
    try {
      const r = await fetch(`${REMOTE}/upload?name=${encodeURIComponent(file.name || "")}`, {
        method: "PUT", credentials: "same-origin", headers: { "content-type": file.type || "application/octet-stream" }, body: file,
      });
      if (!r.ok) { const said = await r.json().catch(() => ({})); throw new Error(said.problem || said.error || String(r.status)); }
      const got = await r.json();
      putOn({ kind: got.kind, src: got.src, title: got.kind === "clip" ? "Clip" : "Still", cap: "" }, at);
    } catch (e) {
      sayState(`Couldn't add that${e && e.message && !/^\d+$/.test(e.message) ? ` — ${e.message}` : ""}`, true);
    } finally { busy0(); }
  }
  async function fromAddress(url, at) {
    if (!REMOTE) { sayState("Links need the portal", true); return; }
    busy1("Fetching…");
    try {
      const r = await fetch(`${REMOTE}/fetch`, { method: "POST", credentials: "same-origin",
        headers: { "content-type": "application/json" }, body: JSON.stringify({ url }) });
      if (!r.ok) throw new Error(String(r.status));
      const got = await r.json();
      if (got.kind === "video") {
        putOn({ kind: "video", title: got.title, kicker: [got.site, got.by].filter(Boolean).join(" · "), href: got.href,
          players: [{ src: got.embed, title: got.title }], src: got.image || "" }, at);
      } else if (got.kind === "still" || got.kind === "clip") {
        putOn({ kind: got.kind, src: got.src, title: got.kind === "clip" ? "Clip" : "Still", cap: "" }, at);
      } else {
        putOn({ kind: "link", title: got.title || url, kicker: got.site || "", href: got.href || url, src: got.image || "" }, at);
      }
    } catch { sayState("Couldn't fetch that", true); } finally { busy0(); }
  }
  const fileIn = el("input");
  fileIn.type = "file";
  fileIn.accept = "image/*,video/mp4,video/quicktime";
  fileIn.multiple = true;
  fileIn.hidden = true;
  fileIn.addEventListener("change", () => { for (const f of fileIn.files) upload(f); fileIn.value = ""; });
  block.append(fileIn);
  function askAddress() {
    closeMenus();
    const r = block.getBoundingClientRect();
    const d = dock.getBoundingClientRect();
    pop.innerHTML = "";
    const inp = el("input");
    inp.placeholder = "Paste a link — YouTube, a picture, any page";
    const ok = el("button", "", "Add");
    pop.append(inp, ok);
    pop.style.left = `${d.left - r.left + d.width / 2}px`;
    pop.style.top = `${d.top - r.top}px`;
    pop.classList.add("on");
    const go = () => {
      const v = inp.value.trim();
      pop.classList.remove("on");
      if (/^https?:\/\//i.test(v)) fromAddress(v);
      else if (v) putOn({ kind: "note", kicker: "Note", text: v });
    };
    ok.addEventListener("click", go);
    inp.addEventListener("keydown", (k) => { if (k.key === "Enter") go(); if (k.key === "Escape") pop.classList.remove("on"); });
    setTimeout(() => inp.focus(), 0);
  }

  // Dropped from the desktop, from another page, or from a browser tab.
  let dragDepth = 0;
  block.addEventListener("dragenter", (e) => {
    if (!mayEdit || !e.dataTransfer || ![...e.dataTransfer.types].some((t) => t === "Files" || t === "text/uri-list" || t === "text/plain")) return;
    e.preventDefault();
    dragDepth++;
    block.classList.add("dropping");
  });
  block.addEventListener("dragover", (e) => { if (block.classList.contains("dropping")) e.preventDefault(); });
  block.addEventListener("dragleave", () => { if (--dragDepth <= 0) { dragDepth = 0; block.classList.remove("dropping"); } });
  block.addEventListener("drop", (e) => {
    if (!block.classList.contains("dropping")) return;
    e.preventDefault();
    dragDepth = 0;
    block.classList.remove("dropping");
    const at = toWorld(e.clientX, e.clientY);
    const files = [...(e.dataTransfer.files || [])];
    if (files.length) { files.forEach((f, i) => upload(f, { x: at.x + i * 40, y: at.y + i * 40 })); return; }
    const said = (e.dataTransfer.getData("text/uri-list") || e.dataTransfer.getData("text/plain") || "").split("\n").map((x) => x.trim()).find((x) => x && !x.startsWith("#"));
    if (said && /^https?:\/\//i.test(said)) fromAddress(said, at);
    else if (said) putOn({ kind: "note", kicker: "Note", text: said }, at);
  });
  /**
   * **What was pasted, put on the board**: cards copied off a board come back
   * as cards; pictures and clips are kept on the film; an address is fetched;
   * anything else is a note. True when something was taken.
   */
  function pasteWhat({ cards = null, files = [], text = "" }) {
    if (!cards && clipMem && text && text === clipMem.text) cards = clipMem.got;
    if (cards && pasteCards(cards)) return true;
    if (files.length) { for (const f of files) upload(f); return true; }
    const said = String(text || "").split("\n").map((x) => x.trim()).filter((x) => x && !x.startsWith("#")).join("\n").trim();
    if (!said) return false;
    if (/^https?:\/\/\S+$/i.test(said)) fromAddress(said);
    else putOn({ kind: "note", kicker: "Note", text: said.slice(0, 4000) });
    return true;
  }
  // Pasted, when nothing is being typed into.
  document.addEventListener("paste", (e) => {
    clearTimeout(pasteWait);
    if (!block.isConnected || !mayEdit) return;
    const path = e.composedPath ? e.composedPath() : [];
    if (path.some((x) => x && (x.isContentEditable || x.tagName === "INPUT" || x.tagName === "TEXTAREA"))) return;
    if (!path.includes(block) && document.activeElement && document.activeElement !== document.body) return;
    // Already being read the Safari way, below: once is enough.
    if (Date.now() - readingAt < 2000) { e.preventDefault(); return; }
    let cards = null;
    try { cards = JSON.parse((e.clipboardData && e.clipboardData.getData(CLIPTYPE)) || "null"); } catch { cards = null; }
    const files = [...((e.clipboardData && e.clipboardData.files) || [])];
    const text = (e.clipboardData && e.clipboardData.getData("text/plain")) || "";
    if (pasteWhat({ cards, files, text })) e.preventDefault();
  });
  /**
   * **Safari, asked outright.** His note, 2026-09-25: pasting a link or a
   * picture onto a board did nothing in Safari — Safari sends a page no paste
   * when there is nothing to type into. So ⌘V there asks for the clipboard
   * itself; Safari shows its small Paste button, and a press of it brings
   * whatever was copied. Refused or cancelled, the cards copied here still
   * paste.
   */
  let readingAt = 0;
  const isSafari = () => /^((?!chrome|chromium|crios|fxios|edg|android).)*safari/i.test(navigator.userAgent || "");
  async function readClipboard() {
    readingAt = Date.now();
    let items;
    try { items = await navigator.clipboard.read(); } catch { if (clipMem) pasteCards(clipMem.got); return; }
    const files = [];
    const texts = [];
    for (const it of items || []) {
      const types = it.types || [];
      const pic = types.find((t) => /^image\//.test(t));
      if (pic) {
        const blob = await it.getType(pic);
        files.push(new File([blob], `pasted.${pic.split("/")[1].replace("jpeg", "jpg")}`, { type: pic }));
        continue;
      }
      const words = types.find((t) => t === "text/uri-list") || types.find((t) => t === "text/plain");
      if (words) texts.push(await (await it.getType(words)).text());
    }
    if (!pasteWhat({ files, text: texts.join("\n") }) && clipMem) pasteCards(clipMem.got);
  }

  // ---------------------------------------------------------------- the film
  /**
   * **Everything in the film, ready to drag in.** The same engine the Shot
   * List runs in this browser reads the film's change logs, so what is here is
   * what the film says *now* — and a card taken from it stays live: opened
   * again tomorrow, it shows tomorrow's shot. People and pinned documents come
   * off the film's page, as its other pages read them.
   */
  let film = null, filmLoading = null, frontCard = null;
  const extOf = (m) => String(m.filename || "").split(".").pop().toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8) || "png";
  const isClip = (m) => Boolean(m && (m.kind === "video" || /\.(mp4|mov|m4v)$/i.test(m.filename || "")));
  const isPicture = (m) => Boolean(m && !isClip(m) && (m.kind === "image" || m.kind === "gif" || m.kind === "photo" || /\.(jpe?g|png|webp|gif|heic)$/i.test(m.filename || "")));
  /**
   * **Where the film keeps a file** — the relay's name for it. A clip is
   * always its MP4: the Mac keeps every clip on the relay as an MP4 proxy,
   * whatever the original was called, so a `.mov` spelled from the filename
   * was asked for and never found (his note, 2026-09-25: videos from
   * Shotlister don't appear).
   */
  function mediaSrc(m) {
    if (!m || !m.hash) return "";
    return `${FILM}/media/${m.hash.slice(0, 32)}.${isClip(m) ? "mp4" : extOf(m)}`;
  }
  /** A clip's poster: a JPEG beside it, under the same name. */
  const posterSrc = (m) => (m && m.hash ? `${FILM}/media/${m.hash.slice(0, 32)}.jpg` : "");
  /** A picture or clip of the film's, as a card's still or clip — its whole hash kept for Add to Shot. */
  function figOf(m, from) {
    if (isClip(m)) return { clip: true, src: mediaSrc(m), poster: posterSrc(m), from, hash: m.hash, cap: m.caption || "" };
    if (isPicture(m)) return { src: mediaSrc(m), from, hash: m.hash, cap: m.caption || "" };
    return null;
  }
  async function loadFilm() {
    if (film) return film;
    if (filmLoading) return filmLoading;
    filmLoading = (async () => {
      const [wasm, state, front] = await Promise.all([
        WebAssembly.instantiateStreaming(fetch("/shotlister_web.wasm"), {}).then((s0) => s0.instance.exports),
        fetch(`${FILM}/api/state`, { credentials: "same-origin" }).then((r) => (r.ok ? r.json() : { logs: [] })),
        fetch(`${FILM}/api/front`, { credentials: "same-origin" }).then((r) => (r.ok ? r.json() : {})).catch(() => ({})),
      ]);
      frontCard = front || {};
      const mem = () => new Uint8Array(wasm.memory.buffer);
      const put = (text) => {
        const bytes = new TextEncoder().encode(text);
        const at = wasm.alloc(bytes.length);
        mem().set(bytes, at);
        return [at, bytes.length];
      };
      const take = (at) => {
        const len = new DataView(wasm.memory.buffer).getUint32(at, true);
        const text = new TextDecoder().decode(mem().slice(at + 4, at + 4 + len));
        wasm.free_result(at);
        return text;
      };
      wasm.set_now(Date.now());
      wasm.set_seed(Math.floor(Math.random() * 2 ** 53));
      wasm.reset();
      const names = (state.logs || []).map((l) => l.name).sort();
      const texts = await Promise.all(names.map((n0) => fetch(`${FILM}/api/log/${n0}`, { credentials: "same-origin" })
        .then((r) => (r.ok ? r.text() : null)).catch(() => null)));
      for (const t of texts) {
        if (t === null) continue;
        const [at, len] = put(t);
        wasm.add_log(at, len);
        wasm.dealloc(at, len);
      }
      wasm.settle();
      const [at, len] = put(JSON.stringify({ search: "", sortColumn: "", sortDescending: false, facets: [], groupBy: "scene" }));
      const model = JSON.parse(take(wasm.view(1, at, len)));
      wasm.dealloc(at, len);
      film = model;
      return model;
    })();
    try { return await filmLoading; } catch (e) { filmLoading = null; throw e; }
  }

  /** What a card from the film shows, from what the film says now. */
  const cap = (list, most) => list.filter(Boolean).slice(0, most);
  function shotsOf(model) {
    const out = [];
    for (const g of model.groups || []) for (const row of g.rows || []) out.push(row);
    return out;
  }
  /** Pictures and clips of one thing, split the way a card holds them, and what stands for it. */
  function mediaOf(list, from) {
    const all = (list || []).map((m) => figOf(m, from)).filter(Boolean);
    const first = all[0];
    return { figs: cap(all.filter((f) => !f.clip), 24), clips: cap(all.filter((f) => f.clip), 12),
      src: first ? (first.clip ? first.poster : first.src) : "" };
  }
  function cardFor(type, it, model) {
    if (type === "shot") {
      // The key frame first, so it is the one that stands for the shot.
      const got = mediaOf([...(it.stills || [])].sort((a, b) => (b.key ? 1 : 0) - (a.key ? 1 : 0)), "Frames");
      const scene = (model.scenes || []).find((x) => x.id === it.sceneId);
      const list = (v) => [].concat(v || []).filter(Boolean).join(", ");
      // **Every field the shot has, with its label.** His note, 2026-09-25:
      // a shot card should show its data properly, not one small line.
      const fields = [
        ["Size", it.size], ["Angle", list(it.angle)], ["Lens", it.lens], ["Movement", it.movement], ["Support", it.support],
        ["Scene", scene ? [scene.number, scene.heading || scene.title].filter(Boolean).join("  ") : ""],
        ["Day", typeof it.day === "string" ? it.day : it.day && it.day.label ? it.day.label : ""],
        ["Unit", typeof it.unit === "string" ? it.unit : ""], ["Priority", it.priority], ["Tags", list(it.tags)],
      ].filter(([, v]) => v);
      return { kind: "shot", live: { type, id: it.shot, key: it.number }, title: it.title || it.description || `Shot ${it.number}`,
        kicker: `Shot ${it.number}`, sub: it.title && it.description ? it.description.slice(0, 220) : "",
        fields, facts: [it.size, it.lens, it.movement, it.support].filter(Boolean), said: it.notes || "",
        figs: got.figs, clips: got.clips, src: got.src };
    }
    if (type === "scene") {
      const got = mediaOf(it.attachments, "Attachments");
      return { kind: "scene", live: { type, id: it.id, key: it.number }, title: it.heading || it.title || `Scene ${it.number}`,
        kicker: `Scene ${it.number}`, sub: (it.description || "").slice(0, 200),
        facts: [it.count ? `${it.count} shot${it.count === 1 ? "" : "s"}` : "", it.timeOfDay, it.shootingLocation].filter(Boolean),
        said: it.script || "", figs: got.figs, clips: got.clips, src: got.src };
    }
    if (type === "location") {
      const got = mediaOf(it.media, "Photos");
      return { kind: "location", live: { type, id: it.id, key: it.name }, title: it.fullName || it.name || "Location",
        kicker: "Location", sub: it.effectiveAddress || it.address || "", said: it.effectiveNotes || it.notes || "",
        facts: [(it.scenes || []).length ? `${it.scenes.length} scene${it.scenes.length === 1 ? "" : "s"}` : ""].filter(Boolean),
        figs: got.figs, clips: got.clips, src: got.src };
    }
    if (type === "day") {
      let when = "";
      when = dayWords(it.date);
      return { kind: "day", live: { type, id: it.id, key: it.label }, title: it.label || "Day", kicker: "Schedule",
        sub: when, facts: [it.count ? `${it.count} shot${it.count === 1 ? "" : "s"}` : ""].filter(Boolean) };
    }
    return null;
  }
  function personCard(p) {
    return { kind: "person", live: { type: "person", key: p.name }, title: p.name,
      kicker: [p.role, p.department].filter(Boolean).join(" · ") || "Crew", sub: p.company || "" };
  }
  function docCard(d) {
    return { kind: "doc", live: { type: "doc", key: d.name }, title: d.name, kicker: "Document",
      href: d.url || (d.file ? `pic/${d.file}` : "") };
  }
  /** The film's thing a live card points at, found again by id, then by name. */
  function findLive(model, live) {
    if (live.type === "shot") {
      const all = shotsOf(model);
      return all.find((r) => r.shot === live.id) || all.find((r) => String(r.number) === String(live.key)) || null;
    }
    if (live.type === "scene") return (model.scenes || []).find((x) => x.id === live.id) || (model.scenes || []).find((x) => String(x.number) === String(live.key)) || null;
    if (live.type === "location") return (model.locations || []).find((x) => x.id === live.id) || (model.locations || []).find((x) => (x.name || "").toLowerCase() === String(live.key).toLowerCase()) || null;
    if (live.type === "day") return (model.days || []).find((x) => x.id === live.id) || (model.days || []).find((x) => (x.label || "").toLowerCase() === String(live.key).toLowerCase()) || null;
    return null;
  }
  /**
   * **Bring every live card up to date**, once the film has been read. A card
   * whose words or pictures changed is redrawn where it stands; only somebody
   * who may change the board writes the refreshed copy back.
   */
  async function refreshLive() {
    const live = [...nodes.values()].filter((n) => n.live);
    if (!live.length || !FILM) return;
    let model;
    try { model = await loadFilm(); } catch { return; }
    let changed = false;
    for (const n of live) {
      let fresh = null;
      if (n.live.type === "person") {
        const p = (frontCard.crew || []).find((x) => x.name === n.live.key);
        fresh = p ? personCard(p) : null;
      } else if (n.live.type === "doc") {
        const d = (frontCard.documents || []).find((x) => x.name === n.live.key);
        fresh = d ? docCard(d) : null;
        // Its preview was made for this file; kept while the file is the same.
        if (fresh && fresh.href === n.href) { fresh.src = n.src || ""; if (n.closed) fresh.closed = true; }
      } else {
        const it = findLive(model, n.live);
        fresh = it ? cardFor(n.live.type, it, model) : null;
      }
      if (!fresh) {
        if (!n.el.classList.contains("missing")) { n.el.classList.add("missing"); n.el.title = "Not in the film any more"; }
        continue;
      }
      n.el.classList.remove("missing");
      // **One picture, two spellings, no change.** A card a chat made (the
      // MCP's `filmCard` in `src/boards.js`) points at `media/…`, which is
      // right at every door to the film; this page spells the same file
      // `${FILM}/media/…`. Read alike, so opening a chat's board is not a save.
      const same = (s) => (FILM ? s.split(`"${FILM}/media/`).join('"media/') : s);
      const before = same(JSON.stringify([n.title, n.kicker, n.sub, n.facts || [], n.fields || [], n.said || "", n.src || "", n.figs || [], n.clips || [], n.live]));
      const after = same(JSON.stringify([fresh.title, fresh.kicker, fresh.sub, fresh.facts || [], fresh.fields || [], fresh.said || "", fresh.src || "", fresh.figs || [], fresh.clips || [], fresh.live]));
      if (before === after) continue;
      Object.assign(n, { facts: [], fields: [], said: "", src: "", figs: [], clips: [], ...fresh, kind: n.kind });
      const was = n.el;
      makeCard(n);
      n.el.style.zIndex = was.style.zIndex;
      n.el.style.animation = "none";
      was.replaceWith(n.el);
      measure(n);
      place(n);
      changed = true;
    }
    if (changed) {
      if (mode !== "free") layout();
      refocus();
      if (mayEdit) save();
      wake();
    }
    for (const n of live) if (n.kind === "doc") previewDoc(n);
  }

  let filmTab = "boards";
  const FILM_TABS = [["boards", "Reference Images"], ["shots", "Shots"], ["scenes", "Scenes"], ["locations", "Locations"], ["days", "Schedule"], ["people", "People"], ["docs", "Documents"]];

  // **Only what is scrolled to is fetched.** His note, 2026-09-25: pictures
  // came in slowly. Every picture in the panel was asked for at once — a
  // picture with no size yet is no height, so the browser's own lazy loading
  // judged them all on screen — and every clip opened a player. Now each has
  // its room before it has its picture, the few in view (and a screen's worth
  // ahead) are fetched, and a clip is its poster until pointed at. The same
  // bargain the film's own pages strike (`playWhatIsSeen` in `film.js`).
  let lazy = null;
  function later(im, src) {
    if (!src) return;
    im.decoding = "async";
    if (!lazy && "IntersectionObserver" in window) {
      lazy = new IntersectionObserver((es) => {
        for (const e of es) {
          if (!e.isIntersecting) continue;
          const t = e.target;
          if (t.dataset.src) { t.src = t.dataset.src; delete t.dataset.src; }
          lazy.unobserve(t);
        }
      }, { root: loupe, rootMargin: "600px 0px" });
    }
    if (lazy) { im.dataset.src = src; lazy.observe(im); } else im.src = src;
  }
  /** A clip in a list plays only while pointed at. */
  function playOnHover(cell, src) {
    cell.addEventListener("pointerenter", () => {
      if (cell.querySelector("video")) return;
      const v = document.createElement("video");
      Object.assign(v, { muted: true, loop: true, playsInline: true, autoplay: true });
      v.setAttribute("muted", "");
      v.setAttribute("playsinline", "");
      v.src = src;
      cell.append(v);
      v.play().catch(() => {});
    });
    cell.addEventListener("pointerleave", () => {
      const v = cell.querySelector("video");
      if (!v) return;
      v.pause();
      v.removeAttribute("src");
      v.load();
      v.remove();
    });
  }

  // **Several at once.** His note, 2026-09-25: pick several things in the
  // panel and drag them all in. ⌘-, ctrl- or shift-click picks; dragging (or
  // clicking) any picked one brings the lot, laid side by side.
  const fpicked = new Map();
  const fpickBar = el("div", "bd-fpick");
  function paintFpick() {
    fpickBar.innerHTML = "";
    fpickBar.hidden = !fpicked.size;
    if (!fpicked.size) return;
    const all = [...fpicked.values()];
    const add = el("button", "go", `Add ${all.length}`);
    add.addEventListener("click", () => { putMany(all.map((f) => f.data())); clearFpick(); });
    const clear = el("button", "", "Clear");
    clear.addEventListener("click", clearFpick);
    fpickBar.append(el("b", "", `${all.length} Picked`), add, clear);
  }
  function clearFpick() {
    for (const node of fpicked.keys()) node.classList.remove("fp");
    fpicked.clear();
    paintFpick();
  }
  /** A thing in the panel: picked with a modifier, else dragged or clicked in. */
  function fpItem(node, data, pic) {
    node.addEventListener("pointerdown", (e) => {
      if (e.button !== 0 && e.pointerType === "mouse") return;
      if (e.metaKey || e.ctrlKey || e.shiftKey) {
        e.preventDefault();
        if (fpicked.has(node)) fpicked.delete(node); else fpicked.set(node, { data, pic });
        node.classList.toggle("fp", fpicked.has(node));
        paintFpick();
        return;
      }
      const group = fpicked.has(node) && fpicked.size > 1 ? [...fpicked.values()] : null;
      dragIn(e, pic, data, group);
    });
  }

  /** A thing from the film, draggable onto the board, or added with its +. */
  function filmRow(data, pic, title, under) {
    const row = el("div", "bd-row");
    if (pic) { const im = el("img"); im.alt = ""; im.draggable = false; later(im, pic); row.append(im); }
    const t = el("div", "bd-rt");
    t.append(el("b", "", title || "Untitled"));
    if (under) t.append(el("span", "", under));
    const plus = el("button", "bd-plus", "+");
    plus.title = "Add to the board";
    plus.addEventListener("pointerdown", (e) => e.stopPropagation());
    plus.addEventListener("click", () => putOn(data()));
    row.append(t, plus);
    fpItem(row, data, pic);
    return row;
  }
  async function openFilm(tab) {
    if (tab) filmTab = tab;
    open = null;
    closeMenus();
    closeCtx();
    fpicked.clear();
    loupe.innerHTML = "";
    const close = el("button", "bd-close", "×");
    close.addEventListener("click", closeLoupe);
    const head = el("div", "bd-lhead");
    head.append(close);
    const tabs = el("div", "bd-tabs");
    for (const [k, name] of FILM_TABS) {
      const b = el("button", k === filmTab ? "on" : "", name);
      b.addEventListener("click", () => openFilm(k));
      tabs.append(b);
    }
    const find = el("input", "bd-find");
    find.placeholder = "Search";
    // **The head stays at the top** — kicker, title, tabs, search — while
    // the list scrolls under it. His note, 2026-09-25.
    const fhead = el("div", "bd-fhead");
    fhead.append(el("p", "bd-k", "Add"), el("h2", "", "From the Film"), tabs, find, fpickBar);
    paintFpick();
    const body = el("div");
    loupe.append(head, fhead, body);
    loupe.scrollTop = 0;
    block.classList.add("loupe-on");
    refocus();
    if (!FILM) { body.append(el("p", "bd-meta", "Not on the portal")); return; }
    body.append(el("p", "bd-meta", "Reading the film…"));
    let model;
    try { model = await loadFilm(); } catch { body.innerHTML = ""; body.append(el("p", "bd-meta", "Couldn't read the film")); return; }
    if (!loupe.contains(body)) return;
    const draw = () => {
      body.innerHTML = "";
      clearFpick();
      const q = find.value.trim().toLowerCase();
      const hit = (...bits) => !q || bits.filter(Boolean).join(" ").toLowerCase().includes(q);
      const rows = el("div", "bd-rows");
      let count = 0;
      const push = (row) => { rows.append(row); count++; };
      if (filmTab === "boards") {
        for (const b of model.boards || []) {
          const pics = (b.media || []).filter((m) => isPicture(m) || isClip(m));
          if (!pics.length || !hit(b.name, ...pics.map((m) => m.caption))) continue;
          body.append(el("p", "bd-sub", `${b.name} · ${pics.length}`));
          const wall = el("div", "bd-wall");
          for (const m of pics) {
            const f = figOf(m, b.name);
            const clip = Boolean(f.clip);
            const cell = el("div", "bd-st" + (clip ? " clip" : ""));
            const im = el("img");
            im.alt = m.caption || "";
            im.draggable = false;
            later(im, clip ? f.poster : f.src);
            cell.append(im);
            if (clip) playOnHover(cell, f.src);
            if (m.caption) cell.append(el("span", "bd-cap", m.caption));
            const data = () => (clip
              ? { kind: "clip", src: f.src, poster: f.poster, hash: m.hash, title: m.caption || b.name, cap: m.caption || "", kicker: b.name }
              : { kind: "still", src: f.src, hash: m.hash, title: m.caption || b.name, cap: m.caption || "", kicker: b.name });
            fpItem(cell, data, clip ? f.poster : f.src);
            wall.append(cell);
            count++;
          }
          body.append(wall);
        }
        if (!count) body.append(el("p", "bd-meta", q ? "Nothing matches" : "No reference images yet"));
        return;
      }
      if (filmTab === "shots") {
        for (const r of shotsOf(model)) {
          const c = cardFor("shot", r, model);
          if (!hit(r.number, r.title, r.description, r.size, r.lens)) continue;
          push(filmRow(() => cardFor("shot", r, model), c.src, `${r.number}  ${r.title || r.description || ""}`.trim(), c.facts.join(" · ")));
        }
      } else if (filmTab === "scenes") {
        for (const x of (model.scenes || []).filter((x) => !x.archived)) {
          const c = cardFor("scene", x, model);
          if (!hit(x.number, x.heading, x.title, x.description)) continue;
          push(filmRow(() => cardFor("scene", x, model), c.src, `${x.number}  ${x.heading || x.title || ""}`.trim(), c.facts.join(" · ")));
        }
      } else if (filmTab === "locations") {
        for (const x of model.locations || []) {
          const c = cardFor("location", x, model);
          if (!hit(x.name, x.fullName, x.address)) continue;
          push(filmRow(() => cardFor("location", x, model), c.src, x.fullName || x.name, c.sub));
        }
      } else if (filmTab === "days") {
        for (const x of model.days || []) {
          const c = cardFor("day", x, model);
          if (!hit(x.label, x.date)) continue;
          push(filmRow(() => cardFor("day", x, model), "", x.label, [c.sub, ...c.facts].filter(Boolean).join(" · ")));
        }
      } else if (filmTab === "people") {
        for (const p of frontCard.crew || []) {
          if (!hit(p.name, p.role, p.department)) continue;
          push(filmRow(() => personCard(p), "", p.name, [p.role, p.department].filter(Boolean).join(" · ")));
        }
      } else if (filmTab === "docs") {
        for (const d of frontCard.documents || []) {
          if (!hit(d.name)) continue;
          push(filmRow(() => docCard(d), "", d.name, d.url ? (() => { try { return new URL(d.url).hostname.replace(/^www\./, ""); } catch { return ""; } })() : "File"));
        }
      }
      if (!count) {
        const none = { shots: "No shots yet", scenes: "No scenes yet", locations: "No locations yet", days: "No shoot days yet", people: "No crew yet", docs: "Nothing pinned yet" }[filmTab];
        body.append(el("p", "bd-meta", q ? "Nothing matches" : none));
      } else body.append(rows);
    };
    find.addEventListener("input", draw);
    draw();
  }

  /** Several things put down side by side, rows of six, centred where they land. */
  function putMany(list, at) {
    const spot = at || middle();
    const GAP = 30;
    const made = [];
    for (let r = 0; r * 6 < list.length; r++) {
      const row = list.slice(r * 6, r * 6 + 6);
      const ws = row.map((d) => (KINDS[d.kind] && KINDS[d.kind].w) || 240);
      let x = spot.x - (ws.reduce((t, w) => t + w, 0) + GAP * (row.length - 1)) / 2;
      row.forEach((d, i) => { made.push(putOn(d, { x: x + ws[i] / 2, y: spot.y + r * 360 })); x += ws[i] + GAP; });
    }
    // Picked, so the lot can be moved on together straight away.
    if (made.length > 1) { clearPick(); for (const n of made) pick(n, true); drawSelbar(); }
    return made;
  }

  /** Dragged out of a panel onto the board; a click without a drag adds it too. */
  function dragIn(e, pic, data, group) {
    if (e.button !== 0 && e.pointerType === "mouse") return;
    e.preventDefault();
    const sx = e.clientX, sy = e.clientY;
    let ghost = null;
    const move = (m) => {
      if (!ghost && Math.hypot(m.clientX - sx, m.clientY - sy) > 6) {
        ghost = el("div", "bd-ghost" + (group ? " many" : ""));
        if (group) ghost.dataset.n = String(group.length);
        if (pic) { const im = el("img"); im.src = pic; ghost.append(im); }
        else { ghost.style.cssText += ";background:#F1ECE4;height:60px"; }
        block.append(ghost);
        if (innerWidth <= 700) block.classList.remove("loupe-on");
      }
      if (ghost) { ghost.style.left = `${m.clientX}px`; ghost.style.top = `${m.clientY}px`; }
    };
    const up = (u) => {
      removeEventListener("pointermove", move);
      removeEventListener("pointerup", up);
      removeEventListener("pointercancel", up);
      const bring = (at) => {
        if (group) { putMany(group.map((g) => g.data()), at); clearFpick(); } else putOn(data(), at);
      };
      if (!ghost) {
        if (u.type !== "pointercancel") bring();
        return;
      }
      ghost.remove();
      const lr = loupe.getBoundingClientRect();
      const vr = vp.getBoundingClientRect();
      const overLoupe = block.classList.contains("loupe-on") && u.clientX >= lr.left && u.clientY >= lr.top && u.clientX <= lr.right && u.clientY <= lr.bottom;
      const inside = u.clientX >= vr.left && u.clientX <= vr.right && u.clientY >= vr.top && u.clientY <= vr.bottom;
      if (innerWidth <= 700) block.classList.add("loupe-on");
      if (u.type === "pointercancel" || overLoupe || !inside) return;
      bring(toWorld(u.clientX, u.clientY));
    };
    addEventListener("pointermove", move);
    addEventListener("pointerup", up);
    addEventListener("pointercancel", up);
  }

  // ---------------------------------------------------------------- previews
  /**
   * **A document shows its first page.** His note, 2026-09-25: a script on
   * the board should look like the script. A PDF kept on the film is drawn
   * here, once, and the picture kept on the board like any other; a link is
   * asked of the portal, which fetches a page's own picture — and a Google
   * Drive file's first page when Drive will show it (shared as *anyone with
   * the link*). A private Drive file has no preview the portal can reach, and
   * says so.
   */
  const previewing = new Set();
  let pdfjs = null;
  const PDFJS = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/";
  async function pdfFirstPage(url) {
    if (!pdfjs) {
      pdfjs = await import(`${PDFJS}pdf.min.mjs`);
      pdfjs.GlobalWorkerOptions.workerSrc = `${PDFJS}pdf.worker.min.mjs`;
    }
    const r = await fetch(url, { credentials: "same-origin" });
    if (!r.ok) return null;
    const doc = await pdfjs.getDocument({ data: await r.arrayBuffer() }).promise;
    try {
      const page = await doc.getPage(1);
      const one = page.getViewport({ scale: 1 });
      const vw = page.getViewport({ scale: Math.min(3, 900 / one.width) });
      const c = document.createElement("canvas");
      c.width = Math.round(vw.width);
      c.height = Math.round(vw.height);
      const g = c.getContext("2d");
      g.fillStyle = "#fff";
      g.fillRect(0, 0, c.width, c.height);
      await page.render({ canvasContext: g, viewport: vw }).promise;
      return await new Promise((res) => c.toBlob(res, "image/jpeg", 0.86));
    } finally { doc.destroy(); }
  }
  function redraw(n) {
    const was = n.el;
    makeCard(n);
    n.el.style.zIndex = was.style.zIndex;
    n.el.style.animation = "none";
    if (picked.has(n)) n.el.classList.add("picked");
    was.replaceWith(n.el);
    measure(n);
    place(n);
    if (open === n) openLoupe(n, true);
    refocus();
    wake();
  }
  async function previewDoc(n) {
    if (n.kind !== "doc" || n.src || n.localSrc || n.closed || !n.href || previewing.has(n.id)) return;
    previewing.add(n.id);
    try {
      if (/^pic\/[0-9a-f]{32}\.pdf$/i.test(n.href) && FILM) {
        const blob = await pdfFirstPage(`${FILM}/${n.href}`);
        if (!blob || !nodes.has(n.id)) return;
        if (mayEdit && REMOTE) {
          const r = await fetch(`${REMOTE}/upload?name=preview.jpg`, { method: "PUT", credentials: "same-origin", headers: { "content-type": "image/jpeg" }, body: blob });
          if (r.ok) n.src = (await r.json()).src;
        }
        // Somebody who may only look sees it too; it is just not kept.
        if (!n.src) n.localSrc = URL.createObjectURL(blob);
      } else if (/^https?:\/\//i.test(n.href) && mayEdit && REMOTE) {
        const r = await fetch(`${REMOTE}/fetch`, { method: "POST", credentials: "same-origin",
          headers: { "content-type": "application/json" }, body: JSON.stringify({ url: n.href }) });
        if (!r.ok) return;
        const got = await r.json();
        if (got.image) n.src = got.image;
        else if (got.closed) n.closed = true;
        else return;
      } else return;
      if (!nodes.has(n.id)) return;
      redraw(n);
      if (n.src || n.closed) save();
    } catch { /* no preview is still a document */ } finally { previewing.delete(n.id); }
  }

  // ---------------------------------------------------------------- to a shot
  // **Add to Shot** — his question, 2026-09-25: a picture attached to a shot
  // on the board, should it go to that shot in Shotlister too? Yes, but only
  // as a step he takes: from the picture's panel or menu, or by answering the
  // question asked when a picture is dropped on a shot. A board is for playing
  // around; the shot list is not where experiments go.
  const mayShot = () => Boolean(FILM && REMOTE && isEditor && mayEdit);
  /** A clip's first frame, kept on the film as its poster. */
  async function posterOf(n) {
    try {
      const v = document.createElement("video");
      Object.assign(v, { muted: true, playsInline: true, preload: "auto", crossOrigin: "use-credentials" });
      v.src = n.src;
      await new Promise((res, rej) => { v.addEventListener("loadeddata", res, { once: true }); v.addEventListener("error", rej, { once: true }); });
      await new Promise((res) => { v.addEventListener("seeked", res, { once: true }); v.currentTime = Math.min(0.1, v.duration || 0); });
      const c = document.createElement("canvas");
      c.width = v.videoWidth; c.height = v.videoHeight;
      c.getContext("2d").drawImage(v, 0, 0);
      const blob = await new Promise((res) => c.toBlob(res, "image/jpeg", 0.86));
      if (!blob) return "";
      const r = await fetch(`${REMOTE}/upload?name=poster.jpg`, { method: "PUT", credentials: "same-origin", headers: { "content-type": "image/jpeg" }, body: blob });
      return r.ok ? (await r.json()).src : "";
    } catch { return ""; }
  }
  /**
   * **Posters a chat could not make.** A clip a chat filed on a shot has no
   * first frame beside it — only a browser can play the clip to take one — so
   * the portal keeps a list (`postersOwed` in `src/boards.js`) and the first
   * board an editor opens on the film makes each and files it through the
   * same `attach` door, which crosses it off. Quietly: nothing on the board
   * changes, and a clip that will not play is simply left for next time.
   */
  async function payPosters(list) {
    if (!mayShot()) return;
    for (const o of list.slice(0, 6)) {
      const poster = await posterOf({ src: o.src });
      if (!poster) continue;
      try {
        await fetch(`${REMOTE}/attach`, { method: "POST", credentials: "same-origin", headers: { "content-type": "application/json" },
          body: JSON.stringify({ src: o.src, shot: String(o.shot || ""), poster }) });
      } catch { /* next time */ }
    }
  }
  async function sendToShot(n, number) {
    busy1(`Adding to Shot ${number}…`);
    try {
      const poster = n.kind === "clip" && !n.hash ? await posterOf(n) : "";
      const r = await fetch(`${REMOTE}/attach`, { method: "POST", credentials: "same-origin", headers: { "content-type": "application/json" },
        body: JSON.stringify({ src: n.src, hash: n.hash || "", shot: String(number), caption: n.cap || "", poster, name: n.cap || "" }) });
      const got = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(got.problem || got.error || `${r.status}`);
      // The film has changed: read it again, and bring the shot's cards up to date.
      film = null; filmLoading = null;
      setTimeout(() => refreshLive(), 50);
      return { ok: true, said: got.said || `Added to Shot ${number}.` };
    } catch (e) {
      return { ok: false, said: e && e.message && !/^\d+$/.test(e.message) ? e.message : "Couldn't add it to the shot" };
    } finally { busy0(); }
  }
  async function openToShot(n) {
    if (!mayShot()) return;
    open = null;
    closeMenus();
    closeCtx();
    loupe.innerHTML = "";
    const close = el("button", "bd-close", "×");
    close.addEventListener("click", () => { if (nodes.has(n.id)) openLoupe(n); else closeLoupe(); });
    const head = el("div", "bd-lhead");
    head.append(close);
    const find = el("input", "bd-find");
    find.placeholder = "Search Shots";
    const fhead = el("div", "bd-fhead");
    fhead.append(el("p", "bd-k", "Add to Shot"), el("h2", "", n.cap || n.kicker || n.title || (n.kind === "clip" ? "Clip" : "Still")), find);
    const body = el("div");
    loupe.append(head, fhead, body);
    loupe.scrollTop = 0;
    block.classList.add("loupe-on");
    refocus();
    body.append(el("p", "bd-meta", "Reading the film…"));
    let model;
    try { model = await loadFilm(); } catch { body.innerHTML = ""; body.append(el("p", "bd-meta", "Couldn't read the film")); return; }
    const draw = () => {
      body.innerHTML = "";
      const q = find.value.trim().toLowerCase();
      const list = el("div", "bd-rows");
      for (const r of shotsOf(model)) {
        if (q && ![r.number, r.title, r.description].join(" ").toLowerCase().includes(q)) continue;
        const c = cardFor("shot", r, model);
        const row = el("div", "bd-row");
        row.style.cursor = "pointer";
        if (c.src) { const im = el("img"); im.alt = ""; later(im, c.src); row.append(im); }
        const t = el("div", "bd-rt");
        t.append(el("b", "", `${r.number}  ${r.title || r.description || ""}`.trim()));
        if (c.facts.length) t.append(el("span", "", c.facts.join(" · ")));
        row.append(t);
        row.addEventListener("click", async () => {
          const got = await sendToShot(n, r.number);
          if (!loupe.contains(body)) return;
          body.innerHTML = "";
          body.append(el("p", got.ok ? "bd-said-ok" : "bd-said-no", got.said));
          const back = el("button", "bd-act", got.ok ? "Done" : "Back");
          back.addEventListener("click", () => (got.ok && nodes.has(n.id) ? openLoupe(n) : draw()));
          body.append(back);
        });
        list.append(row);
      }
      body.append(list.children.length ? list : el("p", "bd-meta", q ? "Nothing matches" : "No shots yet"));
    };
    find.addEventListener("input", draw);
    draw();
    setTimeout(() => find.focus(), 0);
  }
  /** Dropped on a shot's card: asked, never done on its own. */
  function offerShot(n, shot, e) {
    const number = shot.live && shot.live.key;
    if (!number) return;
    const r = block.getBoundingClientRect();
    pop.innerHTML = "";
    const say = el("span", "bd-popsay", "");
    const yes = el("button", "", `Add to Shot ${number}`);
    const no = el("button", "no", "Not Now");
    pop.append(yes, no);
    pop.style.left = `${e.clientX - r.left}px`;
    pop.style.top = `${e.clientY - r.top}px`;
    pop.classList.add("on");
    no.addEventListener("click", () => pop.classList.remove("on"));
    yes.addEventListener("click", async () => {
      yes.disabled = true;
      const got = await sendToShot(n, number);
      pop.innerHTML = "";
      say.textContent = got.said;
      say.style.color = got.ok ? "var(--sage)" : "var(--tension)";
      pop.append(say);
      setTimeout(() => pop.classList.remove("on"), got.ok ? 1800 : 4000);
    });
  }

  const filmB = el("button", "", "From the Film…");
  filmB.addEventListener("click", () => { closeMenus(); openFilm(); });
  const linkB = el("button", "", "Link…");
  linkB.addEventListener("click", askAddress);
  const upB = el("button", "", "Upload…");
  upB.addEventListener("click", () => { closeMenus(); fileIn.click(); });
  for (const [b, t] of [[filmB, "Shots, scenes, reference images, locations, days, people, documents"], [linkB, "A YouTube or Vimeo video, a picture, any page"], [upB, "Pictures and clips from this device"]]) b.title = t;

  // The empty board: one line, and the ways in.
  const empty = el("div", "bd-empty");
  const emptyRow = el("div");
  const emptyBtns = [["Add From the Film", () => openFilm()], ["Paste a Link", askAddress], ["Upload", () => fileIn.click()]].map(([t, f]) => {
    const b = el("button", "", t);
    b.addEventListener("click", f);
    emptyRow.append(b);
    return b;
  });
  empty.append(el("p", "", "Nothing on this board yet"), emptyRow);
  if (block.dataset.api) block.append(empty);
  const showMenu = menuOf("Show", "Show or hide kinds of card", [el("p", "bd-mh", "Show on the board"), ...legend.children]);
  const tip = el("p", "bd-mtip", "Drag to move · click to open · ⌘- or shift-click to pick several · ⌘- or shift-drag to box-select · right-click a card for its menu · middle button to pan · pull a card's pin onto another to tie a thread · double-click the board for a note");
  for (const b of [threadB, histB, resetB]) b.addEventListener("click", closeMenus);
  resetB.classList.add("danger");
  resetB.textContent = "Reset board…";
  histB.textContent = "History…";
  sortsB.addEventListener("click", closeMenus);
  const moreMenu = menuOf("⋯", "Board settings", [sortsB, threadB, histB, pubB, el("hr"), resetB, el("hr"), tip]);
  const right = el("div", "bd-right");
  fullB.classList.add("bd-mbtn");
  right.append(faces, syncEl, shareMenu, showMenu, moreMenu, fullB);
  bar.append(seg, right);
  drawSeg();

  const dock = el("div", "bd-dock");
  for (const [b, t] of [[noteB, "Add a note (or double-click the board)"], [headB, "Add a heading"], [selB, "Drag on the board to box-select cards"]]) b.title = t;
  block.append(dock);

  const zo = el("button", "bd-zb", "−"), zi = el("button", "bd-zb", "+");
  const zoomBy = (f) => {
    const r = vp.getBoundingClientRect();
    const s = clamp(view.s * f, FARTHEST, 2.2);
    viewTo = { s, x: r.width / 2 - (r.width / 2 - view.x) * (s / view.s), y: r.height / 2 - (r.height / 2 - view.y) * (s / view.s) };
    wake();
  };
  zo.addEventListener("click", () => zoomBy(1 / 1.3));
  zi.addEventListener("click", () => zoomBy(1.3));
  zo.title = "Zoom out"; zi.title = "Zoom in"; fitB.title = "Fit everything in view";
  // **Adding, first in the dock** — from the film, a link, an upload.
  const addWrap = menuOf("+ Add", "Add to the board", [filmB, linkB, upB]);
  dock.append(addWrap, noteB, headB, selB, el("i", "bd-sep"), zo, zi, fitB);
  paintAdmin();
  zoom.remove();
  hint.remove();

  // ---------------------------------------------------------------- go
  populate(true);
  layout();
  // Says whether there are cards, so the empty board's line is not drawn
  // over a board this browser already has — as it was when nothing newer
  // came from the portal to redraw it.
  refocus();
  hist.cur = shapeOf(stateNow());
  // **On a phone the whole board is too small to read**, so it opens at a
  // readable size on its middle; a pinch or *Fit* shows the lot.
  const opening = () => {
    const f = fitView();
    if (vp.clientWidth >= 700 || f.s >= 0.34) return f;
    // Its top edge, not its middle: a board being started has its material
    // round the edges and nothing yet in the centre.
    const r = vp.getBoundingClientRect();
    const cx = (r.width / 2 - f.x) / f.s;
    // The top of what is in view across, not of the whole board: on his Dump
    // Board (2026-09-25) the highest card sat far off to one side, and the
    // phone opened on a screen of empty board above the first row it showed.
    const half = r.width / 2 / 0.34;
    const all = [...nodes.values()];
    const across = all.filter((n) => Math.abs(n.tx - cx) < half + n.w / 2);
    const top = Math.min(...(across.length ? across : all).map((n) => n.ty - n.h / 2));
    return { s: 0.34, x: r.width / 2 - cx * 0.34, y: 80 - top * 0.34 };
  };
  Object.assign(view, opening());
  view.s *= 0.9;
  applyView();
  viewTo = opening();
  wake();
  setTimeout(() => { hint.style.opacity = "0.55"; }, 9000);
  // **Framed again once the pictures are in.** The first fit is made before
  // the covers have loaded, so every card is shorter than it will be and the
  // top row ends up under the toolbar. Left alone once he has touched it.
  let touched = false;
  vp.addEventListener("pointerdown", () => { touched = true; }, true);
  vp.addEventListener("wheel", () => { touched = true; }, { capture: true, passive: true });
  for (const ms of [1200, 3000]) setTimeout(() => { if (!touched && block.isConnected) { viewTo = opening(); wake(); } }, ms);

  pull(true);
  // **Asking now and then, as well as listening.** With the live line up a
  // look every minute is only a safety net; without it, every eight seconds.
  let quiet = 0;
  const poll = setInterval(() => {
    if (!block.isConnected) { clearInterval(poll); return; }
    if (document.visibilityState === "visible" && (!live || ++quiet % 8 === 0)) pull(false);
  }, 8000);
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && block.isConnected) pull(false); });

  // **The board is the page.** His question, 2026-09-23: in a square on the
  // page, or the page itself? The page — so it runs from where it starts to
  // the bottom of the screen, less the room the portal's floating page button
  // takes on a phone, and full screen is still a press away.
  const sizeTo = () => {
    if (!block.isConnected || document.fullscreenElement) return;
    const top = block.getBoundingClientRect().top + window.scrollY;
    const phone = innerWidth <= 700;
    let h = Math.max(420, Math.round(innerHeight - top - (phone ? 92 : 16)));
    block.style.height = `${h}px`;
    // Whatever the portal puts under the page (its own padding) is taken off
    // too, so the page itself never scrolls.
    const over = document.documentElement.scrollHeight - innerHeight;
    if (over > 0 && over < 240 && h - over >= 420) block.style.height = `${h - over}px`;
  };
  sizeTo();
  addEventListener("resize", sizeTo);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(sizeTo);

  let lastW = vp.clientWidth, lastH = vp.clientHeight;
  new ResizeObserver(() => {
    if (!block.isConnected) return;
    if (Math.abs(vp.clientWidth - lastW) > 40 || Math.abs(vp.clientHeight - lastH) > 40) {
      lastW = vp.clientWidth; lastH = vp.clientHeight;
      fit();
    }
  }).observe(vp);

  boards.add({
    block,
    key(e) {
      const path = e.composedPath ? e.composedPath() : [];
      // **Never while typing.** A note, a heading, a search box, the panel's
      // note: their own keys are theirs — Backspace deletes a letter there.
      const typing = path.some((x) => x && (x.isContentEditable || x.tagName === "INPUT" || x.tagName === "TEXTAREA" || x.tagName === "SELECT"));
      const mod = e.metaKey || e.ctrlKey;
      const k = (e.key || "").toLowerCase();
      if (e.key === "Escape") {
        if (ctx.classList.contains("on")) closeCtx();
        else if (block.querySelector(".bd-big")) block.querySelector(".bd-big").remove();
        else if (pop.classList.contains("on")) pop.classList.remove("on");
        else if (linking) { linking = false; block.classList.remove("linking"); drawSelbar(); }
        else if (open || block.classList.contains("loupe-on")) closeLoupe();
        else if (picked.size) clearPick();
        return;
      }
      if (typing) return;
      // Another page's board, or none in view: only the one on screen answers.
      if (!block.isConnected || !block.getClientRects().length) return;
      if (mod && k === "z") {
        e.preventDefault();
        step(!e.shiftKey);
      } else if (mod && k === "y") {
        e.preventDefault();
        step(false);
      } else if (mod && (k === "c" || k === "x")) {
        const list = targets();
        if (!list.length) return;
        copyCards(list, k === "x" && mayEdit);
      } else if (mod && k === "v") {
        if (!mayEdit) return;
        // Safari: read the clipboard outright (`readClipboard`, above).
        if (isSafari() && navigator.clipboard && navigator.clipboard.read) { readClipboard(); return; }
        // Anywhere else that sends no paste event, the cards copied here.
        if (!clipMem) return;
        clearTimeout(pasteWait);
        pasteWait = setTimeout(() => { pasteWait = 0; pasteCards(clipMem.got); }, 80);
      } else if (mod && k === "d") {
        const list = targets();
        if (!list.length || !mayEdit) return;
        e.preventDefault();
        const was = clipMem;
        pasteCards(cardsOf(list).got);
        clipMem = was;
      } else if (mod && k === "a") {
        e.preventDefault();
        selectAll();
      } else if (!mod && (e.key === "Delete" || e.key === "Backspace")) {
        const list = targets();
        if (!list.length || !mayEdit) return;
        e.preventDefault();
        takeOff(list);
      } else if (!mod && k === "f") fit();
    },
  });
}

document.addEventListener("keydown", (e) => {
  for (const b of [...boards]) {
    if (!b.block.isConnected) { boards.delete(b); continue; }
    b.key(e);
  }
});

function wire() {
  const root = madeRoot();
  if (!root) return;
  if (!root.querySelector(".bd")) return;
  if (!root.querySelector("style[data-bd]")) {
    const st = document.createElement("style");
    st.dataset.bd = "1";
    st.textContent = STYLE;
    root.append(st);
  }
  for (const block of root.querySelectorAll(".bd")) build(block);
}

wire();
document.addEventListener("swapped", wire);
