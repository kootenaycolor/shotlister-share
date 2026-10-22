/**
 * **The Diagram, on the portal** — the Mac's Diagram, in a browser.
 *
 * His ask, 2026-09-29: first *"read only but eventually it needs to be
 * collaborative"*, then the same day *"work until the diagrams are displayed on
 * the web portal, look correct and have all the functionality of the
 * shotlister app."* So this is the Mac's Diagram mode: the plan fills the page,
 * the tool rail runs down its left (the Mac's twenty tools, the Mac's keys),
 * and the side panel is the Mac's — Details, Shots, Layers, Gear, Show.
 *
 * **The engine does all of it.** Every picture is `plan` in `web/src/lib.rs`
 * (the very shapes the Mac paints, for exactly the area in view); every edit
 * is one of the engine's own JSON edits (`apply` in engine/src/diagram) made
 * with `plan_edit`; hit-testing, snapping and walls are `plan_where`. This file
 * only turns the pointer into edits and draws the panels.
 *
 * **How an edit travels.** It is made at once on this browser's copy of the
 * film, so the page answers under the hand; then it is sent, in a batch, to
 * `PUT api/diagram`, where the server's engine makes it again on the film as
 * kept and files it as a change log in the editor's name — the same road the
 * Shot mark takes, so the Mac and the phone take it in the ordinary way. The
 * server's ids for new pieces come back (`renamed`) and everything here
 * follows them; then the film is read again. Undo is another edit (the engine
 * hands back the edits that take each one back), because the film's truth is
 * on the server, not in this page's history.
 *
 * **Everybody else's edits** reach the page the moment they are kept, over
 * the relay's live line (`api/live`, in film.js), and redraw the plan in
 * place — the view, the pick and the panels are the viewer's and are kept.
 *
 * A viewer, or anybody on a link, gets the same page without the tools: the
 * server refuses their edits whatever a page draws. **Unless he opens the
 * link for drawing** (Editable by Link, per project): then a visitor with
 * the link and no sign-in gets this whole editor, the same as his (his ask,
 * 2026-10-17: "editing should be available publicly") — every batch kept in
 * his Link Edits list as "Link visitor", a whole diagram never taken away
 * without the page asking, a brake on how fast, and the switch turned off
 * stopping them at the next edit (`hub/src/linkedits.js`, worker.js).
 */

export function startDiagram(H) {
  const { root, HUB, esc } = H;
  const NS = "http://www.w3.org/2000/svg";

  // ------------------------------------------------------------ the lists

  /** Every Show switch, in the Mac's order (`DiagramShow.kinds`), and three of the plan's own. */
  const SHOW = [
    ["cameras", "Cameras"], ["cast", "Cast"], ["lights", "Lamps"], ["grip", "Grip"],
    ["set", "Set Pieces"], ["walls", "Walls"], ["words", "Words"], ["pictures", "Pictures"],
    ["names", "Labels"], ["cones", "Cones"],
    ["sun", "Sun"], ["dims", "Dimensions"], ["grid", "Grid"],
  ];
  const DRAWN_OFF = new Set(["cones", "sun", "dims", "grid"]);
  const OFF_KEY = `shotlister.planoff.${HUB.project}`;

  /**
   * The Mac's tools (`DiagramTool`), in the rail's order, with its keys.
   * **Named as the Mac names them** (Back to Paper, Batch 2): Lamp, Words,
   * Draw. N, once the sticky Note, makes Words (Note is a lamp's second line).
   */
  const TOOLS = [
    ["select", "Select", "v"], ["hand", "Move View", "h"],
    ["camera", "Camera", "c"], ["cast", "Cast", "p"], ["light", "Lamp", "l"], ["grip", "Grip", "q"], ["frame", "Frame", "f"],
    ["wall", "Wall", "w"], ["door", "Door", "d"], ["window", "Window", "i"], ["set", "Piece", "s"],
    ["track", "Track", "k"], ["road", "Street", "r"],
    ["text", "Words", "t"], ["arrow", "Arrow", "a"], ["connector", "Connector", "j"], ["measure", "Ruler", "m"], ["shape", "Shape", "o"],
    ["pen", "Draw", "b"], ["cable", "Cable", "e"], ["picture", "Trace", "g"],
  ];
  /**
   * **Set or Plot** (Ref 1498, design/32 item 10): the layer a tool makes
   * things in; picked by its key, it takes the editor to that layer. Select
   * and Move View work in either. A piece's own layer is the engine's
   * (`diagram::layer`), sent as `layer`.
   */
  const TOOL_LAYER = { wall: "set", door: "set", window: "set", set: "set", road: "set", picture: "set", shape: "set" };
  /** A person works in either layer: they stand in the set and are aimed at from the plot. */
  /** Words and arrows stay in the view they were put down in: made in Set, they say so. */
  const inSetNow = () => (layer === "set" ? { in_set: true } : {});
  const layerOf = (e) => (e && e.kind === "cast" ? layer : e && e.layer) || "plot";
  /** Keys that reach a tool by another name: N makes Words. */
  const KEY_ALIAS = { n: "text" };
  const LINE_TOOLS = new Set(["track", "road", "arrow", "connector", "measure"]);
  const LINE_KINDS = new Set(["wall", "track", "road", "measure", "arrow"]);
  /** What takes steps — moves and turns (`Kind::moves` in the engine). */
  // Nothing takes steps on the lighting plot: moves are cut (2026-10-03).
  const WALKS = new Set([]);
  /** A wall's corners: its points once it has more than two, else its ends. */
  const wallCorners = (e) => (e.points && e.points.length >= 2 ? e.points : [[e.x, e.y], [e.x2, e.y2]]);
  // Everything with a box but a camera, a person and words (the Mac's).
  const RESIZABLE = new Set(["set", "light", "shape", "image", "note", "door", "window", "opening"]);
  /** A camera's colour as it arrives: the Mac's column palette, in turn (`nextCameraColour`). */
  const PALETTE = ["#E5484D", "#D97706", "#16A34A", "#0A6CE8", "#7B4BC4", "#DB2777"];
  const PALETTE_NAMES = ["Red", "Orange", "Green", "Blue", "Purple", "Pink"];
  const WORD = { set: "Set Piece", cast: "Cast", stroke: "Drawing", image: "Picture", opening: "Opening", measure: "Ruler" };
  const word = (k) => WORD[k] || (k ? k[0].toUpperCase() + k.slice(1) : "");
  /** A wall's corners and a ruler's markers are handled alike (his Ruler, 2026-10-01). */
  const cornered = (e) => Boolean(e) && (e.kind === "wall" || e.kind === "measure" || isPath(e));
  /** A drawn stroke WITH handles is a path (the Draw tool's); without, old freehand. Never clear a path's handles. */
  const isPath = (e) => Boolean(e) && e.kind === "stroke" && (e.handles || []).length > 0;
  /** Corner `i`'s two curve handles, as offsets from it: [inX, inY, outX, outY]. */
  const nodeHandles = (e, i) => { const h = (e.handles || [])[i]; return h && h.length >= 4 ? h : [0, 0, 0, 0]; };
  const isSmooth = (e, i) => nodeHandles(e, i).some((v) => Math.abs(v) > 1e-9);
  const BEAT_MS = 1400;
  const TAP = 5;

  // ------------------------------------------------------------ the state

  let off = new Set();
  try { off = new Set(JSON.parse(localStorage.getItem(OFF_KEY) || "[]")); } catch { /* per viewer, and optional */ }
  /** Whether this person may change the film's plans at all. */
  const canEdit = () => (HUB.role === "editor" || linkMay) && Boolean(H.wasm() && H.wasm().plan_edit);
  /**
   * **Whether the share link may draw** (`api/diagram/settings`). The owner
   * opens it from the Diagrams page; `publicEdit` is the switch an editor sees,
   * `linkMay` is what it means for a visitor on the link. Asked once, on
   * arrival, and the page drawn again if the answer is yes.
   */
  let publicEdit = false, linkMay = false;
  /** This browser's own name on the plans it draws, so two people at once are two devices. */
  const me = (() => {
    try {
      let id = localStorage.getItem("shotlister.planme");
      if (!/^[a-z0-9]{6,20}$/.test(id || "")) { id = Math.random().toString(36).slice(2, 12).padEnd(8, "0"); localStorage.setItem("shotlister.planme", id); }
      return id;
    } catch { return Math.random().toString(36).slice(2, 12).padEnd(8, "0"); }
  })();
  function askLink() {
    return fetch(`/f/${HUB.project}/api/diagram/settings`, { credentials: "same-origin", cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((got) => {
        if (!got) return;
        const was = `${publicEdit}${linkMay}`;
        publicEdit = Boolean(got.publicEdit); linkMay = Boolean(got.linkMay);
        if (!linkMay && HUB.role !== "editor" && editing) return linkStopped();
        if (`${publicEdit}${linkMay}` !== was) H.draw();
      })
      .catch(() => { /* the page stays as it was: view only */ });
  }
  askLink();
  /**
   * **The switch turned off stops a visitor at once** (his ask, 2026-10-17):
   * the server refuses their next batch whatever the page thinks, and the
   * page, told so (or finding out on its next look, every 15 seconds while
   * a visitor draws), puts its tools away and says why.
   */
  function linkStopped() {
    linkMay = false;
    if (!editing) return;
    editing = false;
    pending = [];
    undos.length = 0; redos.length = 0;
    picks = []; tool = "select";
    H.draw();
    toast("Editing by link was switched off", true);
  }
  setInterval(() => { if (editing && HUB.role !== "editor" && document.visibilityState !== "hidden") askLink(); }, 15000);
  /**
   * **View first, Edit on purpose** (his ask, 2026-10-02: *"first and
   * foremost, it should be view-friendly first for quick reference on set,
   * and then there can be an edit mode"*). The page opens as a picture to
   * read: a finger pans, a tap on a piece says what it is, a camera says its
   * shot. Edit brings out the Mac's tools; Done puts them away. Kept for
   * the visit, not between visits, so the page always opens to look at.
   */
  let editing = false;
  const editor = () => editing && canEdit();
  let tab = "shots";
  let picks = [];                 // the pieces picked, by the engine's id
  let cam = null;                 // the camera whose shot the Shots tab shows
  const views = new Map();        // scene → { cx, cy, k, fit, fitK } in metres as shown
  let got = null, asked = "";     // the engine's last answer for the view, and its question
  const wholes = new Map();       // the whole plan fitted, per question
  let rev = 0;                    // edits made here since the film was last read
  let play = null, tween = 0;
  let live = null;                // a pan or zoom mid-gesture: { tx, ty, s }
  let settle = 0;
  let sideKey = "";
  let copied = false;
  let watching = false;
  let tool = "select";
  let layer = "plot";             // Set or Plot (Ref 1498): this editor's own, never stored
  let armed = null;               // the library drawing Light / Set Piece puts down
  let libOpen = false, libFind = "", libGroup = "";
  let swap = null;                // a lamp or set piece being swapped for another, in the library: { id, focus }
  let barFold = 0;                // how far the picked bar folded to fit: 0 everything … 3 the name alone
  let wallDraw = null;            // the wall being drawn corner by corner: { pts (as stored), id (once its first stretch stands) }
  let wallAt = null;              // where the next corner would land, while drawing
  let pickedCorner = null;        // a picked wall's corner, picked on its own (Break, Curve, Delete Corner)
  let pickedStep = null;          // { id, i }: one step of a piece, picked on its own by its letter-order index
  let pickedStretch = null;       // a picked wall's stretch, for its Length
  let guides = [];                // what a corner lines up with, as stored: [x1, y1, x2, y2]
  let hover = null;               // the piece under the pointer, outlined
  let readout = null;             // the numbers by the pointer mid-drag: { px, py, text }
  let measuring = false;          // the Measure tool, for anybody: two points and the distance, never kept
  let mpts = [];                  // its points, in the film's own coordinates (so a turned plan keeps them)
  let mhover = null;              // where the pointer is, between the first point and the second
  let renaming = null;            // a piece whose name is being typed over on the plan
  let refocus = false;            // the plan had the keys when the page was drawn again
  let libKind = "", libMaker = "";
  let shapeKind = "rect";
  /**
   * **The Draw tool's path so far** (the Mac's `drawNodes`, his ask of
   * 2026-10-02): a click is a corner, a drag pulls a smooth curve out of the
   * point. As stored: { p: [x, y], hin: [dx, dy], hout: [dx, dy] }.
   */
  let penNodes = [];
  let penAs = "line";             // a plain line, a curved wall, or an object (a filled shape)
  let penFill = false;            // a closed path drawn with a fill (an Object always is)
  let penColour = "";             // the pen's ink: none is the plan's own
  let chainPts = [];              // a cable laid point by point (the Mac's `pending`)
  /** What the Camera tool's next camera stands for, from its button's menu: `new` a new shot, empty no shot, else a shot's id. */
  let armedShot = "new";
  /** A picture waiting to be scaled by a length dragged across it (Set Scale): its id. */
  let calibrating = null;
  let beatsMode = false;          // Beats: a drag sets where a piece stands at this beat
  let drag = null;                // a gesture on the plan in flight
  let preview = null;             // the edit a drag would make, drawn and not kept
  let pending = [];               // edits made here, not yet sent: [{scene, op, made}]
  let sending = null;
  let owed = false;               // read the film again once nothing is in flight
  const undos = [], redos = [];   // [{ scene, ops, label }]
  let clip = null;                // copied pieces
  let toastAt = 0;
  let lib = null;
  let castMenu = null;            // { x, y, sx, sy, rot } while the Cast tool asks who
  let picMenu = null;             // the Picture tool's panel is open
  let editingText = null;         // a Text or Note just put down: its words field takes the keys
  let presenting = false;
  let favOpen = false;            // the nine Favorites slots are open
  let detMore = false;            // a piece's Details has More unfolded
  let emptyOpen = null;           // an empty plan's own panel: null, "copy" or "room"
  let copyPanel = null;           // Copy To / Send to Scene: { ids, mode, ticked }
  let many = false;               // Multi-select: a tap adds to what is picked (the phone's shift)
  let pointer = null;             // where the pointer last was over the plan, as stored — for 1–9
  const FRAMES_KEY = `shotlister.planframes.${HUB.project}`;
  /**
   * **How bright the plan's paper is, for this viewer** (his ask, 2026-10-02,
   * as View → Backdrop… on the Mac): 0 dim … 1 white, the paper's E4E5E7
   * being `BACKDROP_DEFAULT`. The paper and grid light together; a name's
   * thin halo is the paper's own, so it follows (no plates since Back to
   * Paper, 2026-10-04; `--dia-patch` stays for an old engine's picture).
   * The screen only: paper exports keep the paper.
   */
  const BACKDROP_KEY = "shotlister.planbackdrop";
  const BACKDROP_DEFAULT = (0.894 - 0.55) / 0.45;
  let backdrop = BACKDROP_DEFAULT;
  try {
    const v = parseFloat(localStorage.getItem(BACKDROP_KEY));
    if (Number.isFinite(v)) backdrop = Math.min(Math.max(v, 0), 1);
  } catch { /* per viewer, and optional */ }
  const litHex = (hex) => {
    const k = (0.55 + 0.45 * backdrop) / 0.894, n = parseInt(hex.slice(1), 16);
    return "#" + [n >> 16, (n >> 8) & 255, n & 255].map((v) => Math.min(255, Math.round(v * k)).toString(16).padStart(2, "0")).join("");
  };
  function lightBackdrop(vp) {
    const pic = vp && vp.querySelector(".planpic");
    if (!pic) return;
    const plain = Math.abs(backdrop - BACKDROP_DEFAULT) < 0.001;
    for (const [k, hex] of [["paper", "#E4E5E7"], ["grid", "#D8D9DB"], ["grid5", "#B9BABD"]]) {
      if (plain) pic.style.removeProperty(`--dia-${k}`); else pic.style.setProperty(`--dia-${k}`, litHex(hex));
    }
    if (plain) pic.style.removeProperty("--dia-patch"); else pic.style.setProperty("--dia-patch", "#E4E5E7");
    vp.style.background = plain ? "" : litHex("#E4E5E7");
  }
  let frames = true;              // Storyboard Frames (Ref 1504): the pictures cameras lay on the plan (Frame on Plan), this viewer only
  try { frames = localStorage.getItem(FRAMES_KEY) !== "0"; } catch { /* per viewer */ }

  // ------------------------------------------------------------ the engine

  function call(name, text) {
    const w = H.wasm();
    if (!w || !w[name]) return null;
    const [p, n] = H.put(text);
    const out = H.take(w[name](p, n));
    w.dealloc(p, n);
    return out;
  }
  function json(text) { try { return JSON.parse(text); } catch { return null; } }
  function drawn(ask) {
    const got = json(call("plan", ask));
    return got && got.svg ? got : null;
  }
  function answer(ask) {
    const key = `${H.seen()}|${rev}\n${ask}`;
    if (key === asked) return got;
    got = drawn(ask);
    asked = key;
    return got;
  }
  function whole(ask) {
    const key = `${H.seen()}|${rev}\n${ask}`;
    if (!wholes.has(key)) {
      if (wholes.size > 8) wholes.clear();
      wholes.set(key, drawn(ask));
    }
    return wholes.get(key);
  }
  function where(what, x, y, more = {}) {
    return json(call("plan_where", JSON.stringify({ scene: String(chosen()), what, x, y, ...more }))) || {};
  }
  function library() {
    if (lib) return lib;
    const w = H.wasm();
    if (!w || !w.plan_library) return { symbols: [], sensors: [], gels: [], materials: [], pipes: [], grids: [] };
    lib = json(H.take(w.plan_library())) || { symbols: [] };
    return lib;
  }
  function glyph(kind, sym, w, h, px) {
    const x = H.wasm();
    if (!x || !x.plan_glyph) return "";
    const [p, n] = H.put(`${kind} ${sym}`);
    const out = H.take(x.plan_glyph(p, n, w, h, px));
    x.dealloc(p, n);
    return out;
  }

  // ------------------------------------------------------------ the scenes

  /** The scenes the list offers: those with a plan — and, to an editor, every scene, to start one. */
  /** **Hide Empty** (his ask, 2026-10-17), an editor's switch on the Scenes head, kept per film in this browser. */
  function hideKey() { const p = H.model().project; return `shotlister.hideempty.${p ? p.id : ""}`; }
  function hideEmpty() { try { return localStorage.getItem(hideKey()) === "1"; } catch { return false; } }
  function setHideEmpty(on) { try { localStorage.setItem(hideKey(), on ? "1" : "0"); } catch {} }
  /**
   * **Hide from Diagrams** (his ask, 2026-10-17): a scene he picks leaves this
   * list only — the shot list, the schedule and the diagrams are untouched.
   * The engine keeps it on the scene (`diagramHidden`), so it is the same on
   * the Mac and the iPhone. The "N Hidden" line counts these and Hide Empty's
   * together; opening it lists them again, each with Show.
   */
  let revealHidden = false;
  /** Scenes marked in the list with ⌘/Ctrl-click or ⇧-click, to be hidden together. */
  const marked = new Set();
  function rows() {
    const all = (H.model().scenes || []).filter((s) => !s.archived);
    // Viewers see only scenes with something drawn; an editor sees them all
    // unless Hide Empty is on. The scene open always stays.
    const hiding = editor() && hideEmpty();
    const leftOut = (s) => s.id !== H.plan() && (s.diagramHidden === true || (hiding && !(s.diagram > 0)));
    const base = editor() ? all : all.filter((s) => s.diagram > 0);
    const out = base.filter(leftOut);
    if (!out.length) revealHidden = false;
    const shown = revealHidden ? base : base.filter((s) => !leftOut(s));
    const hidden = editor() ? out.length : 0;
    const scenes = shown.map((s) => ({ id: s.id, name: `${s.number}  ${s.heading || s.title || ""}`, count: s.diagram > 0 ? String(s.diagram) : "", deep: false,
      menu: editor(), out: leftOut(s), hand: s.diagramHidden === true, mark: marked.has(s.id) }));
    // **Loose plans** head the list (his ruling, 2026-10-01): diagrams that
    // belong to no scene. An editor always sees the head, for its +.
    const plans = (H.model().plans || []).filter((p) => editor() || p.diagram > 0)
      .map((p) => ({ id: p.id, name: p.name, count: p.diagram > 0 ? String(p.diagram) : "", deep: false, plan: true }));
    if (!plans.length && !editor()) return scenes;
    const tail = hidden ? [{ head: "hidden", reveal: revealHidden ? `Hide ${hidden}` : `${hidden} Hidden` }] : [];
    return [{ head: "Plans", add: editor() ? "pnewplan" : "" }, ...plans, { head: "Scenes", eye: editor() ? (hiding ? "on" : "off") : "" }, ...scenes, ...tail];
  }
  /** Hide scenes from the list, or show them (one step of the page's Undo). */
  function hideScenes(ids, hidden) {
    if (!ids.length) return;
    edit({ op: "diagram_hide", ids, hidden }, { label: hidden ? "Hide from Diagrams" : "Show", on: ids[0] });
    marked.clear();
    if (hidden) revealHidden = false;
    H.relook();
  }
  /** A scene row's menu — right-click, a long press or ⋯: Hide from Diagrams, or Show on one already hidden. */
  function sceneMenu(id, at) {
    if (!editor()) return;
    const scenes = H.model().scenes || [];
    const mine = (x) => scenes.find((y) => y.id === x);
    const acting = marked.has(id) && marked.size > 1 ? [...marked] : [id];
    const items = mine(id) && mine(id).diagramHidden
      ? [{ label: "Show", pick: () => hideScenes(acting.filter((x) => mine(x) && mine(x).diagramHidden), false) }]
      : [{ label: "Hide from Diagrams", pick: () => hideScenes(acting, true) }];
    openMenu(null, items, false, at);
  }
  /**
   * **Which diagram is open.** The list picks a scene or a plan (`row`); a
   * scene with several diagrams (`s.diagrams`) opens the one its tab picked,
   * else its first. Every plan command takes that diagram's own id.
   */
  const tabs = new Map();
  function chosen() {
    const r = row();
    const s = r ? (H.model().scenes || []).find((x) => x.id === r) : null;
    const all = s && Array.isArray(s.diagrams) ? s.diagrams : null;
    if (!all || !all.length) return r;
    const pick = tabs.get(r);
    return all.some((d) => d.id === pick) ? pick : all[0].id;
  }
  /**
   * **One tab a diagram, for a scene with more than one** — and, editing,
   * the Mac's ways to make and keep them (his ask, 2026-10-17: the portal
   * edits diagrams as much as the Mac): + at the end, "+ New Diagram" under
   * a scene with one, and each tab's menu — right-click, a long press, or
   * ⋯ — with Rename, Duplicate, Move Left, Move Right and Delete.
   */
  function diagramTabs(s) {
    if (!s) return "";
    const ed = editor();
    const all = Array.isArray(s.diagrams) ? s.diagrams : [];
    if (all.length < 2) return ed ? `<div class="pdtabs one"><button type="button" class="pdnew" data-pdnew="1">+ New Diagram</button></div>` : "";
    const open = chosen();
    return `<div class="pdtabs" role="tablist">${all.map((d) => `<button type="button" role="tab" class="pdtab${d.id === open ? " on" : ""}${d.name ? "" : " ph"}" aria-selected="${d.id === open}" data-pdtab="${esc(d.id)}"${ed ? ` title="${esc(d.title)} · right-click for more"` : ""}>${esc(d.title)}</button>`).join("")}${ed
      ? `<button type="button" class="pdtab pdadd" data-pdnew="1" title="New Diagram" aria-label="New Diagram">+</button><button type="button" class="pdtab pdadd" data-pdmenu="1" title="This Diagram" aria-label="Diagram Menu">⋯</button>` : ""}</div>`;
  }
  /** A new random id, as the engine keeps them (the page and its server make the same diagram). */
  const newId = () => String(BigInt.asUintN(128, [...crypto.getRandomValues(new Uint32Array(4))].reduce((a, w) => (a << 32n) | BigInt(w), 0n)));
  /** The scene open, and its diagrams as the film lists them. */
  function sceneDiagrams() {
    const r = row();
    const s = r ? (H.model().scenes || []).find((x) => x.id === r) : null;
    if (!s) return null;
    const all = Array.isArray(s.diagrams) && s.diagrams.length ? s.diagrams : [{ id: s.id, name: "", title: "Diagram 1", count: s.diagram || 0 }];
    return { scene: s, all };
  }
  /** A new diagram on the scene, opened, its name asked for at once (the Mac's `add`); `from`: a copy of it. */
  function newDiagram(from = null) {
    const sd = sceneDiagrams();
    if (!sd) return;
    const id = newId();
    const made = edit({ op: "diagram_new", id, name: "", ...(from ? { from: String(from) } : {}) }, { label: from ? "Duplicate Diagram" : "New Diagram", on: sd.scene.id });
    if (!made.length) return;
    tabs.set(sd.scene.id, id);
    chose();
    H.relook();
    requestAnimationFrame(() => {
      const tab = root.querySelector(`[data-pdtab="${CSS.escape(id)}"]`);
      const d = (sceneDiagrams() || { all: [] }).all.find((x) => x.id === id);
      if (tab && d) renameDiagram(tab, d);
    });
  }
  /** A diagram's name typed over its tab: blank keeps the grey placeholder. */
  function renameDiagram(anchor, d) {
    const sd = sceneDiagrams();
    if (!sd) return;
    const input = document.createElement("input");
    input.className = "planrename";
    input.type = "text";
    input.value = d.name || "";
    input.placeholder = d.title;
    input.setAttribute("aria-label", "Diagram Name");
    document.body.append(input);
    const r = anchor.getBoundingClientRect();
    input.style.left = `${r.left + r.width / 2}px`; input.style.top = `${r.top + r.height / 2}px`;
    input.focus(); input.select();
    let done = false;
    const finish = (keep) => {
      if (done) return; done = true;
      const name = input.value.trim();
      input.remove();
      if (keep && name !== (d.name || "")) { edit({ op: "diagram_rename", id: d.id, name }, { label: "Rename Diagram", on: sd.scene.id }); H.relook(); }
    };
    input.addEventListener("keydown", (ev) => { if (ev.key === "Enter") finish(true); if (ev.key === "Escape") finish(false); });
    input.addEventListener("blur", () => finish(true));
  }
  /** A tab's own menu (the Mac's): Rename, Duplicate, Move Left and Right, Delete — asked first, with what it costs. */
  function diagramMenu(anchor, id, at = null) {
    const sd = sceneDiagrams();
    if (!sd) return;
    const i = sd.all.findIndex((d) => d.id === id);
    if (i < 0) return;
    const d = sd.all[i];
    const on = sd.scene.id;
    const move = (to) => { edit({ op: "diagram_move", id, index: to }, { label: to < i ? "Move Left" : "Move Right", on }); H.relook(); };
    const items = [
      { label: "Rename…", pick: () => renameDiagram(anchor, d) },
      { label: "Duplicate", pick: () => newDiagram(id) },
      { rule: true },
      ...(i > 0 ? [{ label: "Move Left", pick: () => move(i - 1) }] : []),
      ...(i < sd.all.length - 1 ? [{ label: "Move Right", pick: () => move(i + 1) }] : []),
    ];
    if (sd.all.length > 1) {
      items.push({ rule: true }, { label: "Delete…", pick: () => openMenu(anchor, [
        { head: d.count ? `Delete ${d.title}? ${pieces(d.count)} on it go with it.` : `Delete ${d.title}?` },
        { label: "Delete", pick: () => {
          const next = sd.all[i + 1] || sd.all[i - 1];
          edit({ op: "diagram_delete", id, confirmed: true }, { label: "Delete Diagram", on });
          // The scene's own, deleted, takes the next one's pieces and place.
          tabs.set(on, id === on ? on : next.id);
          chose();
          H.relook();
        } },
        { label: "Cancel", pick: () => {} },
      ], false, at) });
    }
    openMenu(anchor, items, false, at);
  }
  function row() {
    const list = rows().filter((r) => !r.head);
    const plan = H.plan();
    const withPlan = list.find((r) => r.count);
    const one = list.find((r) => r.id === plan) || withPlan || list[0] || null;
    return one ? one.id : null;
  }
  /** The scene a diagram is of: the scene itself, or the scene one of its further diagrams belongs to. */
  function sceneOf(id) { const all = H.model().scenes || []; return all.find((s) => s.id === id) || all.find((s) => Array.isArray(s.diagrams) && s.diagrams.some((d) => d.id === id)) || null; }
  function planOf(id) { return (H.model().plans || []).find((p) => p.id === id) || null; }
  /** What a plan is called on a page or a print: a scene's number and heading, or a loose plan's name. */
  function titleOf(id) {
    const p = planOf(id);
    if (p) return p.name;
    const s = sceneOf(id);
    const d = s && Array.isArray(s.diagrams) ? s.diagrams.find((x) => x.id === id) : null;
    return s ? `${s.number}  ${s.heading || s.title || ""}${d ? ` — ${d.title}` : ""}` : "";
  }
  function shotRow(shotId) {
    if (!shotId) return null;
    for (const g of H.model().groups || []) for (const r of g.rows || []) if (r.shot === shotId) return r;
    return null;
  }
  function el(id) { return got && (got.els || []).find((e) => e.id === id); }
  const units = () => (got && got.settings && got.settings.units) || "ft";

  // ------------------------------------------------------------ geometry

  const rad = (d) => (d * Math.PI) / 180;
  function turnPt(x, y, deg) { const c = Math.cos(rad(deg)), s = Math.sin(rad(deg)); return [x * c - y * s, x * s + y * c]; }
  const turn = () => (got ? got.turn || 0 : 0);
  const shownOf = (x, y) => turnPt(x, y, turn());
  const storedOf = (x, y) => turnPt(x, y, -turn());
  function view() { return views.get(chosen()); }
  function box() { const vp = root.querySelector(".planvp"); return vp ? { vp, w: vp.clientWidth, h: vp.clientHeight } : null; }
  /** A point in the box, in pixels, to the plan as shown, in metres. */
  function toShown(px, py) {
    const v = view(), b = box();
    return [v.cx + (px - b.w / 2) / v.k, v.cy + (py - b.h / 2) / v.k];
  }
  function toBox(sx, sy) {
    const v = view(), b = box();
    return [(sx - v.cx) * v.k + b.w / 2, (sy - v.cy) * v.k + b.h / 2];
  }
  function toStored(px, py) { const [sx, sy] = toShown(px, py); return storedOf(sx, sy); }
  function storedToBox(x, y) { const [sx, sy] = shownOf(x, y); return toBox(sx, sy); }
  /** A length in the plan's units, to the quarter inch (`6 ft 6 1/2 in`) or the centimetre. */
  function lengthText(m) {
    if (units() === "m") return `${(Math.round(m * 100) / 100).toFixed(2).replace(/\.?0+$/, "")} m`;
    const sign = m < 0 ? "-" : "";
    const q = Math.round(Math.abs(m) / 0.0254 * 4);
    const ft = Math.floor(q / 48), inQ = q % 48;
    const whole = Math.floor(inQ / 4), part = ["", "1/4", "1/2", "3/4"][inQ % 4];
    const inch = inQ ? `${whole ? whole : ""}${whole && part ? " " : ""}${part} in` : "";
    return sign + (inch ? (ft ? `${ft} ft ${inch}` : inch) : `${ft} ft`);
  }
  /** The plan's settings, as the engine last drew them. */
  const settings = () => (got && got.settings) || {};
  /**
   * **The step everything keeps to** — the Mac's `snapStep`: the plan's own
   * step (a foot, or half a metre), finer when zoomed close and coarser far
   * out, so what is drawn is always what is caught.
   */
  function snapStep() {
    const s = settings();
    const metric = (s.units || units()) === "m";
    let base = Math.max(s.step || 0.3048, 0.01);
    if (metric && (Math.abs(base - 0.3048) < 1e-6 || Math.abs(base - 0.1524) < 1e-6)) base = 0.5;
    if (!metric && Math.abs(base - 0.5) < 1e-6) base = 0.3048;
    const steps = metric ? [0.05, 0.1, 0.5, 1, 5, 10, 50] : [0.25, 0.5, 1, 5, 10, 50, 100].map((n) => n * 0.3048);
    if (!steps.some((x) => Math.abs(x - base) < 1e-9)) { steps.push(base); steps.sort((a, b) => a - b); }
    let i = Math.max(0, steps.findIndex((x) => Math.abs(x - base) < 1e-9));
    const v = view();
    const k = v ? v.k : 40;
    while (i > 0 && steps[i - 1] * k >= 40) i -= 1;
    while (i < steps.length - 1 && steps[i] * k < 7) i += 1;
    return steps[i];
  }
  /** How many grid steps apart the darker crossings are (the Mac's `gridEvery`). */
  function gridEvery() {
    const st = snapStep();
    if (units() === "m") return st < 0.075 ? 2 : st < 0.3 ? 10 : st < 0.75 ? 2 : st < 2 ? 5 : 2;
    const ft = st / 0.3048;
    return ft < 0.4 ? 4 : ft < 0.75 ? 2 : ft < 2 ? 5 : ft < 7 ? 2 : 5;
  }
  /** **The dots drawn** (the Mac's `drawGrid`): every crossing of the step caught, or, too close to read apart, only every darker one's. */
  function dotStep() {
    const st = snapStep(), v = view();
    return v && st * v.k < 10 ? st * gridEvery() : st;
  }
  /** An arrow key's small step: a quarter of the grid with Snap on. */
  const nudgeStep = () => (settings().snap ? snapStep() / 4 : (units() === "m" ? 0.1 : 0.03048));
  /**
   * An angle turned by hand, kept to the steps Snap keeps (the Mac's
   * `stepped`): 5° with Snap on, a degree with it off, 15° with ⇧ — and
   * caught at the four square turns when near one.
   */
  function stepped(deg, shift, free) {
    let d = deg;
    if (shift) d = Math.round(d / 15) * 15;
    else if (settings().snap && !free) d = Math.round(d / 5) * 5;
    else { d = Math.round(d); const sq = Math.round(d / 90) * 90; if (Math.abs(d - sq) <= 3) d = sq; }
    return ((d % 360) + 360) % 360;
  }
  /**
   * ⇧ keeps a line to the nearest eighth of a turn: the point dropped
   * straight onto that line, and with Snap on its length a whole number of
   * grid steps (the Mac's `constrained`) — 36 ft drawn reads 36 ft.
   */
  function constrained(a, b, shift, free = false) {
    if (!shift) return b;
    const eighth = Math.round(Math.atan2(b[1] - a[1], b[0] - a[0]) / (Math.PI / 4));
    const k = Math.SQRT1_2;
    const dirs = [[1, 0], [k, k], [0, 1], [-k, k], [-1, 0], [-k, -k], [0, -1], [k, -k]];
    const [cx, cy] = dirs[((eighth % 8) + 8) % 8];
    let len = (b[0] - a[0]) * cx + (b[1] - a[1]) * cy;
    if (settings().snap && !free) { const st = snapStep(); len = Math.round(len / st) * st; }
    return [a[0] + cx * len, a[1] + cy * len];
  }
  /** A length typed in the plan's units — `12`, `12 ft 6`, `3.5 m`, `40 in`. */
  function parseLength(text) {
    const t = String(text || "").trim().toLowerCase();
    if (!t) return null;
    if (/m\s*$/.test(t) && !/ft|in/.test(t)) return parseFloat(t);
    const ft = t.match(/(-?[\d.]+)\s*(?:ft|'|feet|foot)/), inch = t.match(/(-?[\d.]+)\s*(?:in|"|inch)/);
    if (ft || inch) return ((ft ? parseFloat(ft[1]) : 0) * 12 + (inch ? parseFloat(inch[1]) : 0)) * 0.0254;
    const bits = t.split(/\s+/).map(parseFloat).filter(Number.isFinite);
    if (!bits.length) return null;
    return units() === "m" ? bits[0] : ((bits[0] || 0) * 12 + (bits[1] || 0)) * 0.0254;
  }
  function fit(g, w, h) {
    const [x1, y1, x2, y2] = g.extent;
    const m = H.narrow() ? 16 : 36;
    const k = Math.min((w - 2 * m) / (x2 - x1 + 1.2), (h - 2 * m) / (y2 - y1 + 1.2));
    return { cx: (x1 + x2) / 2, cy: (y1 + y2) / 2, k: Math.max(4, k), fit: true, fitK: Math.max(4, k) };
  }
  const area = (v, w, h) => [v.cx - w / 2 / v.k, v.cy - h / 2 / v.k, v.cx + w / 2 / v.k, v.cy + h / 2 / v.k];
  const drawnOff = () => [...off].filter((k) => DRAWN_OFF.has(k)).sort();
  const hiddenIds = () => (got ? (got.els || []).filter((e) => e.show && off.has(e.show)).map((e) => e.id) : []);
  /** The pieces of the layer not being worked in, while editing: drawn back, and clicked straight through. */
  const backIds = () => (got && editor() ? (got.els || []).filter((e) => layerOf(e) !== layer).map((e) => e.id) : []);

  /** The switch, Set · Plot: the other layer drawn back and locked, the tool kept only if it is the new layer's. */
  function setLayer(k) {
    if (k === layer) return;
    layer = k;
    if (TOOL_LAYER[tool] && TOOL_LAYER[tool] !== k) tool = "select";
    if (wallDraw) { wallDraw = null; wallAt = null; preview = null; guides = []; readout = null; }
    libOpen = Boolean(LIBS[tool]); picMenu = tool === "picture";
    picks = picks.filter((id) => layerOf(el(id)) === k);
    cam = picks.includes(cam) ? cam : null;
    hover = null; sideKey = "";
    H.draw();
  }

  // ------------------------------------------------------------ the page

  function mode() {
    // The page is drawn again whole when the film is read; the keys stay
    // with the plan if they were there.
    const a = document.activeElement;
    const has = (c) => Boolean(a && a.classList && a.classList.contains(c));
    refocus = has("planvp") ? "plan" : has("plibfind") ? a.selectionStart || 0 : false;
    const id = chosen();
    if (!id) {
      // Nothing drawn yet: Edit lists every scene, to start one.
      return `${H.listbar("0 diagrams")}<div class="body"><div class="well"><div class="sheetwrap"><p class="empty">No diagrams yet</p>${canEdit() ? `<button type="button" class="pact pedit" data-pedit="1">Edit</button>` : ""}</div></div></div>`;
    }
    const s = sceneOf(id);
    const ed = editor();
    const count = (H.model().scenes || []).filter((x) => !x.archived && x.diagram > 0).length + (H.model().plans || []).filter((p) => p.diagram > 0).length;
    // **The head**: what this plan is, its beats, and what to do. Looking:
    // Export, Present, Edit. Editing: Undo, Redo, Copy, Present, Done.
    const acts = presenting ? `<button type="button" class="pact" data-ppresent="1">Done</button>`
      : ed ? `<button type="button" class="pact" data-pundo="1" disabled>Undo</button><button type="button" class="pact" data-predo="1" disabled>Redo</button>
            <button type="button" class="pact" data-pview="1">View</button>
            <button type="button" class="pact" data-pcopymenu="1">Copy</button>
            <button type="button" class="pact pwide" data-pexport="1">Export</button>
            <button type="button" class="pact pwide" data-ppresent="1">Present</button>
            ${linkSwitch()}<button type="button" class="pact pedit on" data-pedit="1">Done</button>`
      : `<button type="button" class="pact" data-pview="1">View</button>
            <button type="button" class="pact pwide${measuring ? " on" : ""}" data-pmeasure="1" title="Press two points on the plan to read the distance between them (M)">Measure</button>
            <button type="button" class="pact pwide" data-pexport="1">Export</button>
            <button type="button" class="pact pwide" data-ppresent="1">Present</button>
            ${linkSwitch()}${canEdit() ? `<button type="button" class="pact pedit" data-pedit="1">Edit</button>` : ""}`;
    return `${H.listbar(H.many(count, "diagram"))}
    <div class="body">
      <div class="well planwell${ed ? " editing" : " viewing"}${presenting ? " presenting" : ""}${photo && ed ? " photoing" : ""}">
        <div class="planhead">
          ${planOf(id) ? `<h1>${esc(planOf(id).name)}</h1>${ed ? `<button type="button" class="pact" data-pplanmenu="1">Plan</button>` : ""}`
            : `<div class="plantitle"><div class="plantop"><h1>${esc(s ? s.number : "")}&nbsp;&nbsp;${esc(s ? (s.heading || s.title || "") : "")}</h1>${s ? `<span class="pcount">${esc(H.many(shotsOf(id).length, "shot"))}</span>` : ""}</div>${subline(s)}${diagramTabs(s)}</div>`}
          <div class="planbeats" hidden></div>
          <div class="planacts">${acts}</div>
        </div>
        ${ed && H.narrow() ? (photo ? photoToolbar(true) : toolbar(true)) : ""}
        <div class="plangrid">
          <div class="planvp" tabindex="0" aria-label="Diagram">
            ${ed && !H.narrow() ? (photo ? photoToolbar(false) : toolbar(false)) : ""}
            <div class="planpic"></div>
            <div class="planscale" aria-hidden="true"></div>
            <div class="planfloat"></div>
            <div class="plansheet" hidden></div>
            <div class="planzoom">
              <button type="button" data-pzoom="out" aria-label="Zoom Out" title="Zoom Out">${H.mark("less", 15)}</button>
              <button type="button" data-pzoom="in" aria-label="Zoom In" title="Zoom In">${H.mark("more", 15)}</button>
              <button type="button" data-pzoom="fit" title="Fit the Plan">Fit</button>
            </div>
            <div class="plantoast" hidden></div>
            <div class="plancompass" hidden title="North"><svg viewBox="-14 -14 28 28" width="28" height="28" aria-hidden="true"><circle r="12"/><path d=""/></svg></div>
          </div>
          <div class="planside"></div>
        </div>
      </div>
    </div>`;
  }

  /** A scene's shots, in the list's order. */
  function shotsOf(id) {
    const s = sceneOf(id);
    if (s) id = s.id;
    const out = [];
    for (const g of H.model().groups || []) for (const r of g.rows || []) if (r.shot && r.sceneId === id) out.push(r);
    return out;
  }
  /** Under the title (the Mac's head): where the scene is shot, its day, and a room laid from a scan. */
  function subline(s) {
    if (!s) return "";
    const place = (s.locations || []).length ? (H.model().locations || []).find((l) => l.id === s.locations[0]) : null;
    const bits = [];
    if (place && place.name) bits.push(`<span class="pplace"><i></i>${esc(place.name)}</span>`);
    if (s.day) bits.push(`<span>${esc(s.day)}</span>`);
    if (got && got.roomFrom) bits.push(`<span>Room from Scan</span>`);
    return bits.length ? `<div class="plansub">${bits.join("")}</div>` : "";
  }

  /**
   * **A tool's face — the Mac's own drawing of it** (`DiagramToolIcon` in
   * Diagram.swift), line for line, on a 20-point square: the thing each tool
   * puts down, from above. Stroked and filled in the button's own ink.
   */
  const ICONS = (() => {
    const P = (x, y) => `${(x * 20).toFixed(2)} ${(y * 20).toFixed(2)}`;
    const line = (pts) => `M${pts.map(([x, y]) => P(x, y)).join(" L")}`;
    const rect = (x, y, w, h, r = 0) => `<rect x="${x * 20}" y="${y * 20}" width="${w * 20}" height="${h * 20}" rx="${r * 20}"/>`;
    const oval = (x, y, w, h) => `<ellipse cx="${(x + w / 2) * 20}" cy="${(y + h / 2) * 20}" rx="${w * 10}" ry="${h * 10}"/>`;
    const svg = (strokes, fills = "", width = 1.4, extra = "") => `<svg viewBox="0 0 20 20" width="20" height="20" aria-hidden="true">
      <g fill="none" stroke="currentColor" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round">${strokes}</g>
      <g fill="currentColor" stroke="none">${fills}</g>${extra}</svg>`;
    const path = (d) => `<path d="${d}"/>`;
    return {
      select: svg("", path(`${line([[0.28, 0.12], [0.28, 0.8], [0.44, 0.64], [0.56, 0.9], [0.66, 0.85], [0.54, 0.6], [0.76, 0.58]])}Z`)),
      hand: svg(path(`${line([[0.5, 0.1], [0.5, 0.9]])} ${line([[0.1, 0.5], [0.9, 0.5]])} ${line([[0.38, 0.22], [0.5, 0.1], [0.62, 0.22]])} ${line([[0.38, 0.78], [0.5, 0.9], [0.62, 0.78]])} ${line([[0.22, 0.38], [0.1, 0.5], [0.22, 0.62]])} ${line([[0.78, 0.38], [0.9, 0.5], [0.78, 0.62]])}`)),
      camera: svg("", rect(0.1, 0.3, 0.46, 0.4, 0.07) + rect(0.54, 0.4, 0.14, 0.2) + path(`${line([[0.66, 0.37], [0.9, 0.24], [0.9, 0.76], [0.66, 0.63]])}Z`)),
      cast: svg(oval(0.12, 0.34, 0.76, 0.34), oval(0.34, 0.3, 0.32, 0.42)),
      light: svg(path(`${line([[0.6, 0.3], [0.6, 0.7]])} ${line([[0.62, 0.3], [0.88, 0.16]])} ${line([[0.62, 0.7], [0.88, 0.84]])}`), rect(0.12, 0.32, 0.42, 0.36, 0.05)),
      grip: svg(path([[0.22, 0.86], [0.5, 0.56], [0.08, 0.5], [0.56, 0.34]].map((q) => line([[0.24, 0.66], q])).join(" ")), rect(0.5, 0.12, 0.38, 0.22), 1.6),
      frame: svg(rect(0.16, 0.16, 0.68, 0.68), rect(0.24, 0.24, 0.52, 0.52) + [[0.16, 0.16], [0.84, 0.16], [0.84, 0.84], [0.16, 0.84]].map(([x, y]) => oval(x - 0.06, y - 0.06, 0.12, 0.12)).join(""), 1.6),
      set: svg(rect(0.1, 0.28, 0.8, 0.46, 0.06) + path(line([[0.5, 0.4], [0.5, 0.74]])), rect(0.1, 0.28, 0.8, 0.12) + rect(0.1, 0.28, 0.12, 0.46) + rect(0.78, 0.28, 0.12, 0.46)),
      wall: svg(path(line([[0.16, 0.8], [0.16, 0.2], [0.84, 0.2]])), "", 3.4),
      door: svg(path(`${line([[0.08, 0.78], [0.28, 0.78]])} ${line([[0.82, 0.78], [0.92, 0.78]])}`), "", 3.4,
        `<path d="${line([[0.8, 0.78], [0.8, 0.24]])} M${P(0.3, 0.78)} A10 10 0 0 1 ${P(0.8, 0.28)}" fill="none" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-dasharray="2.5 2"/>`),
      window: svg(path(`${line([[0.08, 0.5], [0.22, 0.5]])} ${line([[0.78, 0.5], [0.92, 0.5]])}`), "", 3.4,
        `<g fill="none" stroke="currentColor" stroke-width="1.1">${rect(0.22, 0.42, 0.56, 0.16)}<path d="${line([[0.22, 0.5], [0.78, 0.5]])}"/></g>`),
      track: svg(path(`${line([[0.1, 0.38], [0.9, 0.38]])} ${line([[0.1, 0.62], [0.9, 0.62]])} ${[0.18, 0.31, 0.44, 0.57, 0.7, 0.83].map((x) => line([[x, 0.3], [x, 0.7]])).join(" ")}`), "", 1.1),
      road: svg(path(`${line([[0.28, 0.1], [0.28, 0.9]])} ${line([[0.72, 0.1], [0.72, 0.9]])} ${[0.14, 0.42, 0.7].map((y) => line([[0.5, y], [0.5, y + 0.16]])).join(" ")}`)),
      // Words: "Aa", as the Mac's toolbar draws it.
      text: `<svg viewBox="0 0 20 20" width="20" height="20" aria-hidden="true"><text x="10" y="14.5" text-anchor="middle" font-size="13" font-weight="600" fill="currentColor" font-family="-apple-system,system-ui,sans-serif">Aa</text></svg>`,
      arrow: svg(path(line([[0.15, 0.82], [0.74, 0.26]])), path(`${line([[0.86, 0.14], [0.56, 0.24], [0.76, 0.44]])}Z`), 1.8),
      connector: svg(path(line([[0.26, 0.74], [0.74, 0.26]])), oval(0.08, 0.6, 0.2, 0.2) + oval(0.72, 0.2, 0.2, 0.2), 1.8),
      measure: svg(path(`${line([[0.12, 0.5], [0.88, 0.5]])} ${[0.12, 0.88].map((x) => line([[x, 0.34], [x, 0.66]])).join(" ")} ${[0.31, 0.5, 0.69].map((x) => line([[x, 0.5], [x, 0.4]])).join(" ")}`)),
      shape: svg(rect(0.12, 0.3, 0.44, 0.44) + oval(0.42, 0.14, 0.44, 0.44)),
      pen: svg(path(`M${P(0.12, 0.7)} C${P(0.2, 0.2)} ${P(0.4, 0.2)} ${P(0.5, 0.5)} C${P(0.6, 0.8)} ${P(0.8, 0.8)} ${P(0.88, 0.3)}`), "", 1.8),
      cable: svg(path(`M${P(0.16, 0.22)} C${P(0.8, 0.1)} ${P(0.2, 0.9)} ${P(0.84, 0.78)}`), oval(0.08, 0.14, 0.14, 0.14) + rect(0.78, 0.72, 0.13, 0.13)),
      note: svg(rect(0.1, 0.28, 0.8, 0.44, 0.14) + path(`${line([[0.24, 0.44], [0.72, 0.44]])} ${line([[0.24, 0.56], [0.56, 0.56]])}`)),
      picture: svg(rect(0.12, 0.2, 0.76, 0.6, 0.06), path(`${line([[0.18, 0.74], [0.42, 0.46], [0.56, 0.6], [0.66, 0.52], [0.82, 0.74]])}Z`) + oval(0.62, 0.28, 0.12, 0.12)),
    };
  })();
  const toolFace = (k) => ICONS[k] || "";

  /**
   * **A row of named tools for each layer** (Back to Paper, design/32 items
   * 6 and 10): Set is Select · Wall, Door, Window, Street, Piece, Trace; Plot
   * is Select · Lamp, Frame, Camera · Words, Arrow, Draw — each its picture
   * with its name under it, the switch at the left. The rest wait under More.
   */
  const TOOL_GROUPS_OF = { set: [["select"], ["wall", "door", "window", "road", "set", "cast", "picture"], ["text", "arrow"]], plot: [["select"], ["light", "frame", "camera"], ["text", "arrow", "pen"]] };
  const MORE_OF = { set: ["shape", "hand"], plot: ["connector", "measure", "track", "cast", "cable", "hand"] };
  /** The tools that place one thing, and so can be dragged onto the plan (the Mac's). */
  const DRAGGABLE = new Set(["camera", "cast", "frame", "door", "window", "text"]);
  function toolbar(phone) {
    const named = new Map(TOOLS.map(([k, n, key]) => [k, [n, key]]));
    const TOOL_GROUPS = TOOL_GROUPS_OF[layer];
    const MORE_TOOLS = MORE_OF[layer];
    const sw = `<div class="playerseg" role="group" aria-label="Layer">${[["set", "Set"], ["plot", "Plot"]].map(([k, n]) =>
      `<button type="button" class="${layer === k ? "on" : ""}" data-player="${k}" aria-pressed="${layer === k}">${n}</button>`).join("")}</div><i class="psep"></i>`;
    return `<div class="plantools named${phone ? " phone" : ""}" role="toolbar" aria-label="Tools">${sw}${TOOL_GROUPS.map((g) =>
      g.filter((k) => !(phone && k === "hand")).map((k) => {
        const [n, key] = named.get(k);
        return `<button type="button" class="ptool${tool === k ? " on" : ""}" data-ptool="${k}" aria-label="${n}"${phone ? "" : ` title="${n} · ${key.toUpperCase()}"`}${!phone && DRAGGABLE.has(k) ? ` draggable="true"` : ""}>${toolFace(k)}<span>${n}</span></button>`;
      }).join("")).join(`<i class="psep"></i>`)}<i class="psep"></i><details class="pmore"><summary class="ptool pfav${MORE_TOOLS.includes(tool) ? " on" : ""}" data-pmoresum="1">${MORE_TOOLS.includes(tool) ? esc(named.get(tool)[0]) : "More"}</summary><div class="pmorelist">${MORE_TOOLS.filter((k) => !(phone && k === "hand")).map((k) => {
        const [n, key] = named.get(k);
        return `<button type="button" class="pmoreitem${tool === k ? " on" : ""}" data-ptool="${k}"><span>${esc(n)}</span><kbd>${key.toUpperCase()}</kbd></button>`;
      }).join("")}</div></details><button type="button" class="ptool pfav${favOpen ? " on" : ""}" data-pfavs="1">Favorites</button>${phone ? `<button type="button" class="ptool pfav${many ? " on" : ""}" data-pmany="1">Multi-select</button>` : ""}</div>`;
  }

  // ------------------------------------------------------------ drawing the plan

  function paint() {
    const b = box();
    const pic = b && b.vp.querySelector(".planpic");
    if (!pic) return;
    lightBackdrop(b.vp);
    const { w, h } = b;
    if (w < 60 || h < 60) return;
    const id = chosen();
    const base = { scene: String(id), width: Math.round(w), height: Math.round(h), beat: H.beat(), tween, sel: picks, off: drawnOff(), empty: editor() };
    let v = views.get(id);
    if (!v || v.fit) {
      const g = whole(JSON.stringify({ scene: base.scene, width: base.width, height: base.height, off: base.off, empty: base.empty }));
      if (!g) { pic.innerHTML = `<p class="empty">No diagram</p>`; side(null); return; }
      if (!got || got.hex !== g.hex) got = g;
      const sh = (g.els || []).length ? onPage() : null;
      // **The plan holds still once fitted** (the Mac's): an edit lays the
      // sheet out again round the plan, and fitting again each time would
      // move the plan under the hand. Another paper, or another box, fits
      // the page whole again.
      const fitKey = sh ? `${sh.w}x${sh.h}|${w}x${h}|${editor()}` : "";
      if (sh && v && v.fit && v.fitKey === fitKey) v = { ...v };
      else { v = sh ? fitPage(sh, w, h) : fit(g, w, h); v.fitKey = fitKey; }
      // An empty plan is a blank page, not six metres filling the screen:
      // a room's worth of floor, a foot a grid square.
      if (!(g.els || []).length) { v.k = Math.min(v.k, Math.min(w, h) / 12); v.fitK = v.k; }
      views.set(id, v);
    }
    const ask = { ...base, area: area(v, w, h), grid_step: dotStep(), ...pageAsk() };
    if (preview) ask.preview = preview;
    let g = preview ? drawn(JSON.stringify(ask)) : answer(JSON.stringify(ask));
    // A drag begun before the film was read: its edit, by the film's ids.
    if (preview && !g && aliases.size) g = drawn(JSON.stringify({ ...ask, preview: fwd(preview), sel: fwd(picks) }));
    if (!g) { if (!preview) { pic.innerHTML = `<p class="empty">No diagram</p>`; side(null); } return; }
    let looking = null;
    if (!preview) {
      got = g;
      settleIds(g);
      // Sent here to look at a shot (the Shot List's pop-out): its camera, picked.
      const want = H.takeShot ? H.takeShot() : null;
      const c = want ? (g.cams || []).find((x) => x.shot === want) : null;
      if (c) { picks = [c.id]; cam = c.id; tab = "shots"; sideKey = ""; looking = c.id; }
      // What is picked and no longer there — taken back, deleted by
      // somebody else — is no longer picked.
      const kept = picks.filter((id) => (g.els || []).some((e) => e.id === id));
      if (kept.length !== picks.length) { picks = kept; sideKey = ""; }
    }
    if (photo && !preview && !(g.els || []).some((e) => e.id === photo.id || e.id === current(photo.id))) { photo = null; H.draw(); return; }
    if (H.beat() > Math.max(1, g.lastBeat) && !beatsMode) H.setBeat(1);
    live = null;
    const sh = onPage();
    b.vp.classList.toggle("ondesk", Boolean(sh));
    const [paper, lines] = sh ? pageLayer(sh, v, b) : ["", ""];
    pic.innerHTML = paper + g.svg + lines + hiding(g);
    const svg = pic.querySelector(":scope > svg");
    drawBack(svg, g);
    if (svg) overlay(svg, preview ? g : got);
    if (svg) measureLayer(svg);
    beatsBar(got || g);
    side(got);
    acts();
    // Before the bar: the bar keeps to the right of the scale.
    scaleBar(v.k);
    compass();
    float();
    sheetCard();
    hideTyped();
    if (looking && H.narrow() && !editor()) keepAbove(looking);
    showReadout();
    {
      // A toast still owed, on a page drawn again under it (a refusal read back).
      const t = b.vp.querySelector(".plantoast");
      if (t && toastNow && Date.now() < toastNow.until && t.hidden) {
        t.textContent = toastNow.text; t.hidden = false; t.classList.toggle("loud", toastNow.loud);
        clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.hidden = true; }, toastNow.until - Date.now());
      }
    }
    const pct = b.vp.querySelector("[data-pzoom='fit']");
    if (pct) pct.textContent = v.fit ? "Fit" : `${Math.round((v.k / v.fitK) * 100)}%`;
    b.vp.classList.toggle("placing", editor() && tool !== "select" && tool !== "hand");
    b.vp.classList.toggle("measuring", measuring && !editor());
    b.vp.classList.toggle("panning", tool === "hand");
  }

  /**
   * **The scale bar** (the Mac's `DiagramScaleBar`): the longest round
   * length that stays under 150 points at this zoom, half filled, along
   * the plan's foot on the left — so a distance can be read off the plan
   * on set without a ruler laid.
   */
  const SCALES = {
    m: [[0.1, "10 cm"], [0.25, "25 cm"], [0.5, "50 cm"], [1, "1 m"], [2, "2 m"], [5, "5 m"], [10, "10 m"], [20, "20 m"], [50, "50 m"]],
    ft: [[0.1524, "6 in"], [0.3048, "1 ft"], [0.6096, "2 ft"], [1.524, "5 ft"], [3.048, "10 ft"], [6.096, "20 ft"], [15.24, "50 ft"], [30.48, "100 ft"]],
  };
  function scaleBar(k) {
    const n = root.querySelector(".planscale");
    if (!n || !(k > 0)) return;
    n.style.display = got && got.settings && got.settings.sketch ? "none" : "";
    const steps = SCALES[units() === "m" ? "m" : "ft"];
    let pick = steps[0];
    for (const st of steps) if (st[0] * k <= 150) pick = st;
    const px = Math.round(Math.min(Math.max(pick[0] * k, 10), 400));
    const said = `${px}|${pick[1]}`;
    if (n.dataset.said === said) return;
    n.dataset.said = said;
    n.style.width = `${px}px`;
    n.innerHTML = `<i><b></b></i><span><em>0</em><em>${esc(pick[1])}</em></span>`;
  }

  /**
   * **The compass** (the Mac's): in the bottom right corner, still while the
   * plan turns, once the plan has a north. Its needle points to north on the
   * plan; grabbed and turned like a dial, the needle goes round and the sun
   * with it — the set stays put (his note, 2026-09-29); clicked, it opens
   * the sun. Quiet: a thin ring and a grey needle.
   */
  let liveNorth = null;
  let sunOpen = false;            // the Sun and North panel, opened from the compass
  function compass() {
    const n = root.querySelector(".plancompass");
    if (!n) return;
    const st = settings();
    const has = Boolean(got && (got.els || []).length) && (Number(st.north || 0) !== 0 || Boolean(root.querySelector('.planpic > svg [data-part="north"]')) || st.sun);
    n.hidden = !(editor() && has) || presenting;
    if (n.hidden) return;
    const north = liveNorth ?? Number(st.north || 0);
    const k = 12 * 0.8, r = rad(north);
    const pts = [[0, -k * 0.85], [k * 0.38, k * 0.6], [0, k * 0.35], [-k * 0.38, k * 0.6]].map(([x, y]) => [x * Math.cos(r) - y * Math.sin(r), x * Math.sin(r) + y * Math.cos(r)]);
    n.querySelector("path").setAttribute("d", `M${pts.map(([x, y]) => `${x.toFixed(2)} ${y.toFixed(2)}`).join("L")}Z`);
  }
  function wireCompass(vp) {
    const n = vp.querySelector(".plancompass");
    if (!n) return;
    const dial = (ev) => { const r = n.getBoundingClientRect(); return Math.atan2(ev.clientY - (r.top + r.height / 2), ev.clientX - (r.left + r.width / 2)) * 180 / Math.PI; };
    let held = null;
    n.addEventListener("pointerdown", (ev) => {
      if (!editor()) return;
      ev.preventDefault(); ev.stopPropagation();
      try { n.setPointerCapture(ev.pointerId); } catch { /* gone */ }
      held = { from: dial(ev), was: Number(settings().north || 0), x: ev.clientX, y: ev.clientY, moved: false };
    });
    n.addEventListener("pointermove", (ev) => {
      if (!held) return;
      if (!held.moved && Math.hypot(ev.clientX - held.x, ev.clientY - held.y) < TAP) return;
      held.moved = true;
      let north = held.was + (dial(ev) - held.from);
      if (ev.shiftKey) north = Math.round(north / 15) * 15;
      liveNorth = Math.round(((north % 360) + 360) % 360 * 10) / 10;
      preview = { op: "settings", set: { north: liveNorth } };
      paint();
    });
    n.addEventListener("pointerup", () => {
      if (!held) return;
      const was = held;
      held = null;
      const north = liveNorth;
      liveNorth = null; preview = null;
      // Turned: kept, one step to take back. Clicked: the sun's panel.
      if (was.moved && north !== null) edit({ op: "settings", set: { north } }, { label: "Turn North" });
      else openView(n, "sun");
    });
  }

  // ---- View (the Mac's DiagramViewMenu) ------------------------------------
  //
  // **Everything about how the plan is drawn**, in the head beside Copy and
  // Export. **It stays open while he clicks** (his ask, 2026-10-05: *"I
  // dont want it to go away, i want it to stay until i click off of it"*):
  // how the plan is drawn on the left; what is shown, the sheet, units and
  // panels on the right. Sun and North, and Colours, open in its place.
  // Looking, its switches are this viewer's own (Show); editing, the plan's.

  let viewPanel = null;
  let viewPane = "view";
  let sunScrub = null, northScrub = null;
  const SHOW_KINDS = SHOW.filter(([k]) => !["names", "cones", "sun", "dims", "grid"].includes(k));
  function openView(anchor, pane = "view") {
    closeView();
    const p = document.createElement("div");
    p.className = "planview";
    document.body.append(p);
    viewPanel = p;
    viewPanel.anchor = anchor;
    viewPane = pane;
    drawView();
    setTimeout(() => document.addEventListener("pointerdown", viewAway, true), 0);
    document.addEventListener("keydown", viewKey, true);
    if (anchor && anchor.classList) anchor.classList.add("on");
  }
  function closeView() {
    if (!viewPanel) return;
    const a = viewPanel.anchor;
    viewPanel.remove();
    viewPanel = null;
    sunScrub = null; northScrub = null;
    document.removeEventListener("pointerdown", viewAway, true);
    document.removeEventListener("keydown", viewKey, true);
    if (a && a.classList && a.dataset.pview) a.classList.remove("on");
  }
  function viewAway(ev) {
    if (!viewPanel || viewPanel.contains(ev.target) || (viewPanel.anchor && viewPanel.anchor.contains && viewPanel.anchor.contains(ev.target))) return;
    closeView();
  }
  function viewKey(ev) {
    if (ev.key !== "Escape" || !viewPanel) return;
    ev.stopPropagation();
    if (viewPane !== "view" && viewPanel.anchor && viewPanel.anchor.dataset && viewPanel.anchor.dataset.pview) { viewPane = "view"; drawView(); } else closeView();
  }
  function placeView() {
    if (!viewPanel) return;
    const a = viewPanel.anchor;
    const r = a && a.isConnected ? a.getBoundingClientRect() : null;
    const w = viewPanel.offsetWidth, h = viewPanel.offsetHeight;
    let left = r ? r.right - w : window.innerWidth - w - 12, top = r ? r.bottom + 8 : 70;
    if (r && r.top > window.innerHeight / 2) top = r.top - h - 8;
    viewPanel.style.left = `${Math.max(8, Math.min(left, window.innerWidth - w - 8))}px`;
    viewPanel.style.top = `${Math.max(8, Math.min(top, window.innerHeight - h - 8))}px`;
  }
  const clock = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(Math.round(m) % 60).padStart(2, "0")}`;
  function sunMinutes() {
    const sun = got && got.sun;
    if (sun && Number.isFinite(sun.minutes)) return sun.minutes;
    const t = String(settings().sun_time || "").split(":").map(Number);
    return t.length === 2 && t.every(Number.isFinite) ? t[0] * 60 + t[1] : 780;
  }
  function sunStatus() {
    const s = settings(), sun = got && got.sun;
    if (!s.sun) return "Hidden";
    if (!sun) return "";
    if (sun.why) return sun.why;
    if (!Number.isFinite(sun.azimuth) || !Number.isFinite(sun.altitude)) return "";
    if (sun.altitude <= -0.9) return "Below the horizon";
    if (sun.altitude < 0.5) return "On the horizon";
    const points = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"];
    return `From the ${points[Math.floor(((sun.azimuth + 22.5) % 360) / 45) % 8]}, ${Math.round(sun.altitude)}° up`;
  }
  function viewHTML() {
    const ed = editor(), s = settings();
    const box2 = (label, attr, on, dis = false) => `<label class="pvcheck${dis ? " dis" : ""}"><input type="checkbox" ${attr}${on ? " checked" : ""}${dis ? " disabled" : ""}><span>${esc(label)}</span></label>`;
    const row = (label, go) => `<button type="button" class="pvrow" data-pvgo="${go}">${esc(label)}</button>`;
    const seg = (key, now, opts) => `<div class="pvseg">${opts.map(([v, n]) => `<button type="button" class="${String(now) === String(v) ? "on" : ""}" data-pvseg="${key}" data-pv='${esc(JSON.stringify(v))}'>${esc(n)}</button>`).join("")}</div>`;
    const plan = (label, key, on, dis = false) => ed ? box2(label, `data-pvset="${key}"`, on, dis) : "";
    const mine = (label, key, onFilm) => ed ? box2(label, `data-pvset="${key === "names" ? "labels" : key}"`, onFilm) : box2(label, `data-pvoff="${key}"`, !off.has(key));
    const sunWord = s.sun && got && got.sun && Number.isFinite(got.sun.minutes) ? `Sun ${clock(got.sun.minutes)}` : "Sun";
    const lengths = !s.dims ? "off" : s.all_lengths ? "all" : "picked";
    const left = [
      ed ? row("Colours…", "colours") : "",
      ed ? `<hr>` : "",
      mine("Grid", "grid", s.grid),
      plan("Snap", "snap", s.snap),
      // Sketch (his ask, 2026-10-04): marks and words over a location photo or a drawing.
      plan("Sketch", "sketch", s.sketch),
      ed ? `<div class="pvlabel">Lengths</div>${seg("lengths", lengths, [["off", "Off"], ["picked", "Picked"], ["all", "All"]])}` : box2("Lengths", `data-pvoff="dims"`, !off.has("dims")),
      plan("Measurements", "measures", s.measures !== false),
      mine("Cones", "cones", s.cones),
      mine(sunWord, "sun", s.sun),
      ed ? row("Sun and North…", "sun") : "",
      `<hr>`,
      mine("Labels", "names", s.labels),
      box2("Storyboard Frames", `data-pvframes="1"`, frames),
      plan("All Caps", "caps", Boolean(s.caps)),
      plan("Counts", "counts", Boolean(s.counts)),
      plan("Frame Fabric", "fabric", s.fabric !== false),
      `<div class="pvlabel">Backdrop</div><label class="pvbackdrop"><i>Dim</i><input type="range" min="0" max="1" step="0.01" value="${backdrop.toFixed(2)}" data-pvbackdrop="1" aria-label="Backdrop"><i>Bright</i></label>`,
    ].join("");
    const steps = (s.units || "ft") === "m" ? [[1, "Every Metre"], [0.5, "Every 50 cm"], [0.1, "Every 10 cm"]] : [[0.3048, "Every Foot"], [0.1524, "Every 6 Inches"]];
    const stepNow = steps.reduce((a, b) => (Math.abs(b[0] - (s.step || 0)) < Math.abs(a[0] - (s.step || 0)) ? b : a))[0];
    const right = [
      `<div class="pvhead">Show by Kind</div>`,
      SHOW_KINDS.map(([k, n]) => box2(n, `data-pvoff="${k}"`, !off.has(k))).join(""),
      `<button type="button" class="pvbtn" data-pvshowall="1"${SHOW_KINDS.some(([k]) => off.has(k)) ? "" : " disabled"}>Show All</button>`,
      ed ? `<div class="pvhead">Sheet</div>
        <label class="pvpick"><span>Paper</span><select data-pvsel="paper">${[["letter", "Letter"], ["tabloid", "Tabloid"], ["a4", "A4"]].map(([v, n]) => `<option value="${v}"${(s.paper || "letter") === v ? " selected" : ""}>${n}</option>`).join("")}</select></label>
        ${seg("orientation", s.orientation === "portrait" ? "portrait" : "landscape", [["landscape", "Landscape"], ["portrait", "Portrait"]])}
        ${plan("Legend", "legend", s.legend !== false)}${plan("Show Unlabeled", "unlabeled", Boolean(s.unlabeled))}${plan("Sheet Notes", "notes", s.notes !== false)}${plan("Scale Bar", "scale_bar", Boolean(s.scale_bar), Boolean(s.sketch))}<hr>
        ${seg("units", (s.units || "ft") === "m" ? "m" : "ft", [["ft", "Feet and Inches"], ["m", "Metres"]])}
        <label class="pvpick"><span>Grid Step</span><select data-pvsel="step">${steps.map(([v, n]) => `<option value="${v}"${v === stepNow ? " selected" : ""}>${n}</option>`).join("")}</select></label>` : "",
      `<hr>`,
      ed ? row("Layers", "layers") + row("Details", "details") : "",
      row("Present", "present"),
      ed && got && (got.els || []).length ? row("Clear Plan…", "clear") : "",
    ].join("");
    return `<div class="pvcols"><div class="pvcol">${left}</div><div class="pvcol">${right}</div></div>`;
  }
  function sunHTML() {
    const s = settings(), sun = (got && got.sun) || {};
    const m = sunScrub ?? sunMinutes();
    const n = northScrub ?? (Number(s.north || 0) > 180 ? Number(s.north) - 360 : Number(s.north || 0));
    const picksSun = s.sun ? [["Sunrise", sun.rise], ["Morning Golden Hour", sun.goldenMorning], ["Noon", sun.noon], ["Evening Golden Hour", sun.goldenEvening], ["Sunset", sun.set]].filter(([, at]) => Number.isFinite(at)) : [];
    return `<div class="pvtitle"><b>Sun and North</b><button type="button" class="pvbtn" data-pvdone="1">Done</button></div>
      <label class="pvcheck"><input type="checkbox" data-pvset="sun"${s.sun ? " checked" : ""}><span>Show the Sun</span></label>
      ${s.sun ? `<label class="pvcheck"><input type="checkbox" data-pvset="sun_rays"${s.sun_rays ? " checked" : ""}><span>Rays</span></label>` : ""}
      <label class="pvpick"><span>Day</span><input type="date" data-pvdate="1" value="${esc(s.sun_date || (got && got.sceneDate) || "")}">${s.sun_date ? `<button type="button" class="pvbtn" data-pvreset="sun_date">Shoot Day</button>` : ""}</label>
      <label class="pvpick"><span>Time</span><input type="range" min="0" max="1435" step="5" value="${Math.round(m)}" data-pvtime="1"><b class="pvclock" data-pvclock="time">${clock(m)}</b></label>
      ${picksSun.length ? `<div class="pvpicks">${picksSun.map(([name, at]) => `<button type="button" class="${Math.abs(m - at) < 3 ? "on" : ""}" data-pvsunat="${at}"><span>${name}</span><b>${clock(at)}</b></button>`).join("")}</div>` : ""}
      ${s.sun_time ? `<button type="button" class="pvbtn" data-pvreset="sun_time">Scene's Time of Day</button>` : ""}
      <label class="pvpick"><span>North</span><input type="range" min="-180" max="180" step="1" value="${Math.round(n)}" data-pvnorth="1"><b class="pvclock" data-pvclock="north">${Math.round(n)}°</b></label>
      <div class="pvstatus">${esc(sunStatus())}</div>`;
  }
  /** **The plot's colours** (his ask, 2026-10-03): one colour per category, for every plan in the film at once. */
  const COLOUR_CATEGORIES = [["added", "Film Lights"], ["practical", "Practicals"], ["existing", "Existing Lights"], ["blue", "Third Ink"], ["gripink", "Grip and Frames"], ["camink", "Cameras"], ["plan", "Walls"], ["prop", "Furniture and Props"]];
  function coloursHTML() {
    const mine = (settings().colours) || {};
    return `<div class="pvtitle"><b>Colours</b><button type="button" class="pvbtn" data-pvdone="1">Done</button></div>
      ${COLOUR_CATEGORIES.map(([role, name]) => `<label class="pvcolour"><input type="color" data-pvcolour="${role}" value="${esc(mine[role] || INK_HEX[role] || "#17171A")}"><span>${esc(name)}</span>${mine[role] ? `<button type="button" class="pvbtn" data-pvcolourreset="${role}">Reset</button>` : ""}</label>`).join("")}
      <div class="pvstatus">Every plan in this film</div>`;
  }
  function drawView() {
    if (!viewPanel) return;
    const p = viewPanel;
    p.classList.toggle("narrow", viewPane !== "view");
    p.innerHTML = viewPane === "sun" ? sunHTML() : viewPane === "colours" ? coloursHTML() : viewHTML();
    const after = () => { paint(); drawView(); };
    p.querySelectorAll("[data-pvset]").forEach((b) => b.addEventListener("change", () => { setting(b.dataset.pvset, b.checked); after(); }));
    p.querySelectorAll("[data-pvoff]").forEach((b) => b.addEventListener("change", () => {
      const k = b.dataset.pvoff;
      if (off.has(k)) off.delete(k); else off.add(k);
      try { localStorage.setItem(OFF_KEY, JSON.stringify([...off])); } catch { /* kept for this visit only */ }
      sideKey = ""; after();
    }));
    p.querySelectorAll("[data-pvshowall]").forEach((b) => b.addEventListener("click", () => {
      for (const [k] of SHOW_KINDS) off.delete(k);
      try { localStorage.setItem(OFF_KEY, JSON.stringify([...off])); } catch { /* this visit */ }
      sideKey = ""; after();
    }));
    p.querySelectorAll("[data-pvframes]").forEach((b) => b.addEventListener("change", () => {
      frames = !frames;
      try { localStorage.setItem(FRAMES_KEY, frames ? "1" : "0"); } catch { /* this visit only */ }
      after();
    }));
    p.querySelectorAll("[data-pvseg]").forEach((b) => b.addEventListener("click", () => {
      const key = b.dataset.pvseg, v = JSON.parse(b.dataset.pv);
      // **Lengths** (the Mac's): none, the picked wall's on screen only, or every wall's on screen and on paper.
      if (key === "lengths") edit({ op: "settings", set: v === "off" ? { dims: false } : { dims: true, all_lengths: v === "all" } }, { label: "Lengths" });
      else setting(key, v);
      after();
    }));
    p.querySelectorAll("[data-pvsel]").forEach((b) => b.addEventListener("change", () => { setting(b.dataset.pvsel, b.dataset.pvsel === "step" ? Number(b.value) : b.value); after(); }));
    p.querySelectorAll("[data-pvbackdrop]").forEach((r) => {
      r.addEventListener("input", () => { backdrop = Number(r.value); lightBackdrop(root.querySelector(".planvp")); });
      r.addEventListener("change", () => { try { localStorage.setItem(BACKDROP_KEY, String(backdrop)); } catch { /* this visit only */ } });
    });
    p.querySelectorAll("[data-pvgo]").forEach((b) => b.addEventListener("click", () => {
      const go = b.dataset.pvgo;
      if (go === "colours" || go === "sun") { viewPane = go; return drawView(); }
      closeView();
      if (go === "layers" || go === "details") { tab = go; sideKey = ""; return paint(); }
      if (go === "present") return present();
      if (go === "clear") return doThing("clear", null);
    }));
    p.querySelectorAll("[data-pvdone]").forEach((b) => b.addEventListener("click", () => {
      if (viewPanel.anchor && viewPanel.anchor.dataset && viewPanel.anchor.dataset.pview) { viewPane = "view"; drawView(); } else closeView();
    }));
    p.querySelectorAll("[data-pvreset]").forEach((b) => b.addEventListener("click", () => { setting(b.dataset.pvreset, ""); after(); }));
    p.querySelectorAll("[data-pvsunat]").forEach((b) => b.addEventListener("click", () => { setting("sun_time", clock(Number(b.dataset.pvsunat))); after(); }));
    const date = p.querySelector("[data-pvdate]");
    if (date) date.addEventListener("change", () => { setting("sun_date", date.value); after(); });
    // While a slider is held: what it shows and the plan previews, kept only
    // when it is let go — one step to take back, not a hundred.
    const time = p.querySelector("[data-pvtime]");
    if (time) {
      time.addEventListener("input", () => { sunScrub = Number(time.value); preview = { op: "settings", set: { sun_time: clock(sunScrub) } }; paint(); p.querySelector('[data-pvclock="time"]').textContent = clock(sunScrub); });
      time.addEventListener("change", () => { const v = sunScrub ?? Number(time.value); sunScrub = null; preview = null; setting("sun_time", clock(v)); after(); });
    }
    const north = p.querySelector("[data-pvnorth]");
    if (north) {
      north.addEventListener("input", () => { northScrub = Number(north.value); preview = { op: "settings", set: { north: (northScrub + 360) % 360 } }; paint(); p.querySelector('[data-pvclock="north"]').textContent = `${Math.round(northScrub)}°`; });
      north.addEventListener("change", () => { const v = northScrub ?? Number(north.value); northScrub = null; preview = null; setting("north", (v + 360) % 360); after(); });
    }
    p.querySelectorAll("[data-pvcolour]").forEach((c) => c.addEventListener("change", () => {
      edit({ op: "everywhere", key: "colours", value: { ...(settings().colours || {}), [c.dataset.pvcolour]: c.value.toUpperCase() } }, { label: "Colours" });
      after();
    }));
    p.querySelectorAll("[data-pvcolourreset]").forEach((b) => b.addEventListener("click", () => {
      const now = { ...(settings().colours || {}) };
      delete now[b.dataset.pvcolourreset];
      edit({ op: "everywhere", key: "colours", value: now }, { label: "Colours" });
      after();
    }));
    placeView();
  }

  /** What is held by the page's own ids, carried over to the film's once the plan knows them by those. */
  function settleIds(g) {
    if (!aliases.size) return;
    const has = new Set((g.els || []).map((e) => e.id));
    const now = (id) => (!id || has.has(id) ? id : current(id));
    const was = picks.join(",");
    picks = picks.map(now);
    if (picks.join(",") !== was) sideKey = "";
    cam = now(cam); hover = now(hover); editingText = now(editingText);
    if (wallDraw && wallDraw.id) wallDraw.id = now(wallDraw.id);
    if (pickedStep) pickedStep = { ...pickedStep, id: now(pickedStep.id) };
  }

  /**
   * **Set or Plot** while editing (Ref 1498): the layer not being worked in
   * drawn back — the set grey under the plot, the plot faded over the set —
   * each part's own opacity kept under it. The dots follow the Grid switch
   * on either layer (his note, 2026-10-05: "grid needs to appear if I want it to").
   */
  function drawBack(svg, g) {
    if (!svg || !editor()) return;
    if (photo) {
      // Drawing on a picture: everything else steps back.
      svg.querySelectorAll("[data-el]").forEach((n) => { if (n.getAttribute("data-el") !== photo.id) n.setAttribute("opacity", ((parseFloat(n.getAttribute("opacity")) || 1) * 0.3).toFixed(2)); });
      return;
    }
    // A picture is never drawn back (his pick, 2026-10-15): it shows at the strength he set.
    const back = new Set((g.els || []).filter((e) => layerOf(e) !== layer && e.kind !== "image").map((e) => e.id));
    const a = layer === "set" ? 0.2 : 0.5;
    svg.querySelectorAll("[data-el]").forEach((n) => {
      if (!back.has(n.getAttribute("data-el"))) return;
      n.setAttribute("opacity", ((parseFloat(n.getAttribute("opacity")) || 1) * a).toFixed(2));
    });
  }

  /** The viewer's Show switches the page answers by itself: kinds hidden by id, names by part. */
  function hiding(g) {
    const sels = [];
    const q = (s) => String(s).replace(/["\\]/g, "\\$&");
    for (const e of g.els || []) if (e.show && off.has(e.show)) sels.push(`[data-el="${q(e.id)}"]`);
    if (off.has("names")) sels.push(`[data-part="label"]`, `[data-part="tag"]`, `[data-part="tie"]`);
    if (!frames) sels.push(`[data-part="shotframe"]`);
    return sels.length ? `<style>.planpic svg :is(${sels.join(",")}){display:none}</style>` : "";
  }

  /**
   * What is picked, drawn over the plan: a ring round each piece, and on one
   * piece its handles — the turning knob, the corners that size it, a line's
   * two ends — as the Mac draws them.
   */
  function overlay(svg, g) {
    const layer = document.createElementNS(NS, "g");
    layer.setAttribute("class", "planedit");
    const add = (tag, attrs) => {
      const n = document.createElementNS(NS, tag);
      for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v);
      layer.append(n);
      return n;
    };
    const poly = (pts) => pts.map((p) => p.map((n) => n.toFixed(1)).join(",")).join(" ");
    if (photo && editor()) { photoOverlay(add); svg.append(layer); return; }
    // What a corner lines up with, while it is drawn or dragged.
    for (const [x1, y1, x2, y2] of guides) {
      const [a, b] = [storedToBox(x1, y1), storedToBox(x2, y2)];
      add("line", { class: "planguide", x1: a[0], y1: a[1], x2: b[0], y2: b[1] });
    }
    // The piece under the pointer, outlined in the pick's blue.
    if (hover && !picks.includes(hover) && !drag && tool === "select") {
      const e = (g.els || []).find((x) => x.id === hover);
      if (cornered(e)) {
        const c = wallCorners(e).map(([x, y]) => storedToBox(x, y));
        add(e.closed && c.length > 2 ? "polygon" : "polyline", { class: "planhover", points: poly(c) });
      } else {
        const r = e && outline(svg, e);
        if (r) add("polygon", { class: "planhover", points: poly(r.pts) });
      }
    }
    // The Draw tool's path so far, its next leg following the pointer; its
    // points, the first a ring to close on, and the handle just pulled out.
    if (tool === "pen" && penNodes.length) {
      const v = (q) => storedToBox(q[0], q[1]);
      const plus = (q, h) => v([q[0] + h[0], q[1] + h[1]]);
      const P2 = (q) => q.map((n) => n.toFixed(1)).join(" ");
      let d = `M${P2(v(penNodes[0].p))}`;
      for (let i = 1; i < penNodes.length; i += 1) {
        const a = penNodes[i - 1], b = penNodes[i];
        d += ` C${P2(plus(a.p, a.hout))} ${P2(plus(b.p, b.hin))} ${P2(v(b.p))}`;
      }
      const last = penNodes[penNodes.length - 1];
      if (pointer && !(drag && drag.kind === "node")) d += ` C${P2(plus(last.p, last.hout))} ${P2(v(pointer))} ${P2(v(pointer))}`;
      const ink = penAs === "wall" || !penColour ? "var(--d-ink)" : penColour;
      add("path", { class: "planpen", d, style: `stroke:${ink};stroke-width:${penAs === "wall" ? 3 : 2}` });
      penNodes.forEach((n, i) => {
        const [qx, qy] = v(n.p);
        const close = i === 0 && penNodes.length >= 3 && pointer && Math.hypot(pointer[0] - n.p[0], pointer[1] - n.p[1]) * view().k < 9;
        const r = close ? 6 : 4;
        add("rect", { class: "plannode", x: qx - r, y: qy - r, width: 2 * r, height: 2 * r, style: `stroke:${ink};fill:${close ? ink : "#fff"}` });
        if (i === penNodes.length - 1 && Math.hypot(n.hout[0], n.hout[1]) > 1e-9) {
          for (const h of [n.hin, n.hout]) {
            const [kx, ky] = plus(n.p, h);
            add("line", { class: "plannodeh", x1: qx, y1: qy, x2: kx, y2: ky, style: `stroke:${ink}` });
            add("circle", { class: "plannodek", cx: kx, cy: ky, r: 3, style: `fill:${ink}` });
          }
        }
      });
    }
    // A cable being laid, point by point.
    if (tool === "cable" && chainPts.length) {
      const c = chainPts.map(([x, y]) => storedToBox(x, y));
      if (pointer) c.push(storedToBox(pointer[0], pointer[1]));
      add("polyline", { class: "planpen", points: poly(c), style: "stroke:var(--d-cable);stroke-width:2" });
      chainPts.forEach(([x, y]) => { const [qx, qy] = storedToBox(x, y); add("circle", { class: "plandot", cx: qx, cy: qy, r: 3.5 }); });
    }
    // Set Scale: the length being dragged across the picture.
    if (drag && drag.kind === "calib") {
      const [ax, ay] = storedToBox(...drag.a), [bx2, by2] = storedToBox(...drag.b);
      add("line", { class: "plancalib", x1: ax, y1: ay, x2: bx2, y2: by2 });
    }
    // A picked camera's storyboard frame: its corners, to grow it by.
    if (editor() && picks.length === 1 && tool === "select" && !drag) {
      const fe = (g.els || []).find((x) => x.id === picks[0]);
      if (fe && fe.kind === "camera" && fe.frame_on && frames) {
        const ns = [...svg.querySelectorAll(`[data-part="shotframe"][data-el="${fe.id}"]`)];
        if (ns.length) {
          let b = null;
          for (const n of ns) { try { const r = n.getBBox(); b = b ? [Math.min(b[0], r.x), Math.min(b[1], r.y), Math.max(b[2], r.x + r.width), Math.max(b[3], r.y + r.height)] : [r.x, r.y, r.x + r.width, r.y + r.height]; } catch { /* not drawn */ } }
          if (b) for (const [cx, cy] of [[b[0], b[1]], [b[2], b[1]], [b[2], b[3]], [b[0], b[3]]]) add("rect", { class: "planfcorner", x: cx - 4, y: cy - 4, width: 8, height: 8 });
        }
      }
    }
    // The wall being drawn: its corners so far, the first a ring to close on.
    if (wallDraw) {
      wallDraw.pts.forEach(([x, y], i) => {
        const [px, py] = storedToBox(x, y);
        add("circle", { class: i === 0 && wallDraw.pts.length >= 3 ? "planclose" : "plandot", cx: px, cy: py, r: i === 0 && wallDraw.pts.length >= 3 ? 7 : 3.5 });
      });
    }
    const els = picks.map((id) => (g.els || []).find((e) => e.id === id)).filter(Boolean);
    for (const e of els) {
      if ((cornered(e) && !isPath(e)) || LINE_KINDS.has(e.kind)) {
        // A wall, a ruler or a line picked: its own line, in the pick's blue —
        // never a box round it (his note, 2026-10-01).
        const c = wallCorners(e).map(([x, y]) => storedToBox(x, y));
        add(e.closed && c.length > 2 ? "polygon" : "polyline", { class: "planwalline", points: poly(c) });
        continue;
      }
      const r = outline(svg, e);
      if (r) add("polygon", { class: "planring", points: poly(r.pts) });
    }
    if (editor() && els.length && !drag && tool === "select") {
      const one = els.length === 1 && !els[0].locked ? els[0] : null;
      const box = pickBox(els, svg);
      if (box) {
        // One box round a wall, a line, several pieces or a group, with its
        // own turning knob (the Mac's pick box).
        const grouped = new Set(els.map((e) => e.group)).size === 1 && els[0].group && els.length > 1;
        add("rect", { class: `planbox${grouped ? " group" : ""}`, x: box.x1, y: box.y1, width: box.x2 - box.x1, height: box.y2 - box.y1 });
        if (grouped) { const t = add("text", { class: "planboxname", x: box.x1 + 2, y: box.y1 - 5 }); t.textContent = els[0].groupName || "Group"; }
        const [kx, ky] = box.knob;
        add("line", { class: "planstem", x1: kx, y1: box.y1, x2: kx, y2: ky });
        add("circle", { class: "planhandle knob", cx: kx, cy: ky, r: 6, "data-h": "boxturn" });
      }
      if (one && cornered(one)) {
        for (const h of wallHandles(one)) {
          if (h.kind === "wc") add("rect", { class: `planhandle sq${h.i === pickedCorner ? " on" : ""}`, x: h.at[0] - 5, y: h.at[1] - 5, width: 10, height: 10, "data-h": `wc${h.i}` });
          else if (h.kind === "hin" || h.kind === "hout") {
            add("line", { class: "planhandleline", x1: h.from[0], y1: h.from[1], x2: h.at[0], y2: h.at[1] });
            add("circle", { class: "planhandle knob", cx: h.at[0], cy: h.at[1], r: 4.5, "data-h": `${h.kind}${h.i}` });
          } else {
            const [x, y] = h.at;
            add("circle", { class: "planhandle plus", cx: x, cy: y, r: 7, "data-h": `${h.kind}${h.i}` });
            add("path", { class: "planplus", d: `M${x - 3.5} ${y}H${x + 3.5}M${x} ${y - 3.5}V${y + 3.5}` });
          }
        }
      } else if (one && LINE_KINDS.has(one.kind)) {
        for (const [end, x, y] of [[0, one.x, one.y], [1, one.x2, one.y2]]) {
          const [px, py] = storedToBox(x, y);
          add("circle", { class: `planhandle${one.kind === "arrow" && (end ? one.end_on : one.start_on) ? " pinned" : ""}`, cx: px, cy: py, r: 6, "data-h": `end${end}` });
        }
        // A track, a street or an arrow bends from its middle (the Mac's curve handle).
        if (["track", "road", "arrow"].includes(one.kind)) {
          const [cx, cy] = curveAt(one);
          add("circle", { class: "planhandle knob", cx, cy, r: 5.5, "data-h": "curve" });
        }
      } else if (one && !["cable", "stroke"].includes(one.kind)) {
        const r = outline(svg, one);
        if (r) {
          if (RESIZABLE.has(one.kind) && (one.hug || !(one.kind === "light" && !isFrame(one) && one.emits))) {
            r.pts.forEach(([px, py], i) => add("rect", { class: "planhandle sq", x: px - 5, y: py - 5, width: 10, height: 10, "data-h": `corner${i}` }));
          }
          // The turning knob: out in front of what faces — a lamp's beam,
          // a camera's lens, a person's nose — so dragging it right aims
          // right; off the top of anything else.
          // A frame's is off its side, across from its tilt knob.
          const [ax, ay, arot] = one.at || [one.x, one.y, one.rot];
          const [cx, cy] = storedToBox(ax, ay);
          const side = faces(one) ? 0 : isFrame(one) ? 90 : -90;
          const face = rad(arot + turn() + side);
          const edge = edgeReach(one, side);
          const kx = cx + Math.cos(face) * (edge + 22), ky = cy + Math.sin(face) * (edge + 22);
          add("line", { class: "planstem", x1: cx + Math.cos(face) * edge, y1: cy + Math.sin(face) * edge, x2: kx, y2: ky });
          add("circle", { class: "planhandle knob", cx: kx, cy: ky, r: 7, "data-h": "turn" });
          // How far a camera's cone reaches: a diamond at its tip (the Mac's).
          if (one.kind === "camera" && one.cone) {
            const r0 = rad(arot);
            const [tx, ty] = storedToBox(ax + Math.cos(r0) * ((one.w || 0.4) / 2 + camReach(one)), ay + Math.sin(r0) * ((one.w || 0.4) / 2 + camReach(one)));
            add("path", { class: "planhandle reach", d: `M${tx} ${ty - 6}L${tx + 6} ${ty}L${tx} ${ty + 6}L${tx - 6} ${ty}Z`, "data-h": "reach" });
          }
          if (isFrame(one)) {
            // A frame's tilt knob rides its raised edge on a track out past
            // its side (Scenario's), an arrow each way along it.
            const t = tiltTrack(one);
            add("line", { class: "plantrack", x1: t.flat[0], y1: t.flat[1], x2: t.upright[0], y2: t.upright[1] });
            const [kx2, ky2] = t.knob;
            add("circle", { class: "planhandle tilt", cx: kx2, cy: ky2, r: 8, "data-h": "tilt" });
            const ux = t.upright[0] - t.flat[0], uy = t.upright[1] - t.flat[1], ul = Math.hypot(ux, uy) || 1;
            const [vx, vy] = [ux / ul, uy / ul];
            const arrow = (g) => {
              const [tx, ty] = [kx2 + vx * 5.5 * g, ky2 + vy * 5.5 * g], [bx, by] = [kx2 + vx * 1.5 * g, ky2 + vy * 1.5 * g];
              return `M${tx} ${ty}L${bx - vy * 3.2} ${by + vx * 3.2}L${bx + vy * 3.2} ${by - vx * 3.2}Z`;
            };
            add("path", { class: "plantiltarrows", d: arrow(1) + arrow(-1) });
          }
        }
        // **Its steps** (his ruling, 2026-10-01), each picked and dragged
        // on its own: a ring on every ghost, a knob for every turn.
        const sp = stepPicked();
        const [nx, ny] = one.at || [one.x, one.y];
        (one.seq || []).forEach((st, i) => {
          if (st.turn) {
            const k = stepKnob(one, st);
            add("line", { class: "planstem", x1: k.top[0], y1: k.top[1], x2: k.at[0], y2: k.at[1] });
            add("circle", { class: `planhandle knob${sp && sp.i === i ? " on" : ""}`, cx: k.at[0], cy: k.at[1], r: 6, "data-h": `stepturn${i}` });
          } else if (Math.abs(st.x - nx) > 1e-6 || Math.abs(st.y - ny) > 1e-6) {
            const [bx, by] = storedToBox(st.x, st.y);
            add("circle", { class: `planhandle trip${sp && sp.i === i ? " on" : ""}`, cx: bx, cy: by, r: 9, "data-h": `step${i}` });
          }
        });
      }
    }
    svg.append(layer);
  }

  const isFrame = (e) => e && e.kind === "light" && e.sym === (library().frame || "frame");
  /** A lamp on the plot: a light that gives light (or a bare mark), not a frame or grip (`plot::is_lamp`). */
  const isLamp = (e) => Boolean(e) && e.kind === "light" && !isFrame(e) && (!e.sym || Boolean(e.emits));
  /** Grip: a flag, net, stand or board — a light-kind piece that gives none. */
  const isGrip = (e) => Boolean(e) && e.kind === "light" && !isFrame(e) && !isLamp(e);
  /** What can share a label (`plot::can_share`; his ask, 2026-10-05: frames and any object): any piece that stands on the plan. */
  const canShare = (e) => Boolean(e) && ["light", "set", "camera", "cast", "track", "road", "shape", "image"].includes(e.kind);
  /** A piece's Note field: a lamp's and a frame's `label` (typed as "note"), anything else's `caption`. */
  const noteField = (e) => (isLamp(e) || isFrame(e) ? "note" : "caption");
  /** A lamp hung pointing straight down (`plot::points_down`): its Lean at nought. */
  const pointsDown = (e) => isLamp(e) && (e.tilt ?? 90) < 1;
  /** The pieces a label holds (a shared label), top of the stack first. */
  const heldBy = (id) => (got ? (got.els || []).filter((x) => x.tie_to === id && canShare(x)) : []);
  /** A shared label: words with lamps tied to them. */
  const isShared = (e) => Boolean(e) && e.kind === "text" && heldBy(e.id).length > 0;
  /** The shared label a lamp is tied to, if any. */
  const labelOf = (e) => { const t = e && e.tie_to ? el(e.tie_to) : null; return t && t.kind === "text" ? t : null; };
  /** What faces along its heading — a lamp's beam, a camera's lens, a person's nose — and so turns from a knob in front. */
  const faces = (e) => e.kind === "camera" || e.kind === "cast" || (e.kind === "light" && !isFrame(e));
  /** How far, in pixels, a piece's footprint reaches from its middle toward `off` degrees from its heading. */
  function edgeReach(e, off) {
    const hw = (e.w || 0.3) / 2, hh = ((e.h > 0 ? e.h : e.w) || 0.3) / 2;
    const k = view().k;
    return Math.max((off === 0 ? hw : hh) * k + 4, 12);
  }

  /** A frame's tilt knob and its track, on screen: a fixed way out past its
   * side, level with its raised (back) edge — at its far end lying flat, at
   * its middle standing. The Mac's `tiltTrack`. */
  function tiltTrack(e) {
    const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
    const hh = (e.h > 0 ? e.h : e.w) / 2, tall = e.tall > 0 ? e.tall : e.h;
    const at = (lx, ly) => { const [x, y] = turnPt(lx, ly, arot); return storedToBox(ax + x, ay + y); };
    const edge = at(-e.w / 2, -hh), past = at(-e.w / 2, -hh - 1);
    const len = Math.hypot(past[0] - edge[0], past[1] - edge[1]) || 1;
    const [ox, oy] = [(past[0] - edge[0]) / len * 26, (past[1] - edge[1]) / len * 26];
    const shift = ([x, y]) => [x + ox, y + oy];
    return { knob: shift(edge), flat: shift(at(-tall / 2, -hh)), upright: shift(at(0, -hh)) };
  }

  /** The box round a pick, on screen, and its knob — for anything but a single piece with a body. */
  function pickBox(els, svg) {
    if (!els.length || els.every((e) => e.locked)) return null;
    // One piece alone wears no box: a line is its line and its ends, a
    // footprint its own outline (his note, 2026-10-01).
    if (els.length === 1) return null;
    const pts = [];
    for (const e of els) {
      if (cornered(e)) wallCorners(e).forEach(([x, y]) => pts.push(storedToBox(x, y)));
      else if (LINE_KINDS.has(e.kind)) pts.push(storedToBox(e.x, e.y), storedToBox(e.x2, e.y2));
      else if (e.points && e.points.length) e.points.forEach(([x, y]) => pts.push(storedToBox(x, y)));
      else { const r = outline(svg, e); if (r) pts.push(...r.pts); }
    }
    if (!pts.length) return null;
    const x1 = Math.min(...pts.map((p) => p[0])) - 7, x2 = Math.max(...pts.map((p) => p[0])) + 7;
    const y1 = Math.min(...pts.map((p) => p[1])) - 7, y2 = Math.max(...pts.map((p) => p[1])) + 7;
    let kx;
    if (els.length === 1 && els[0].kind === "wall") kx = x2;
    else { const [px] = storedToBox(...pivot(els)); kx = Math.min(Math.max(px, x1), x2); }
    return { x1, y1, x2, y2, knob: [kx, y1 - 22] };
  }

  /** Every point of a piece as stored — a wall's corners, a line's ends, a footprint's four corners. */
  function pointsOf(e) {
    if (cornered(e)) return wallCorners(e);
    if (LINE_KINDS.has(e.kind)) return [[e.x, e.y], [e.x2, e.y2]];
    if (e.points && e.points.length) return e.points;
    const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
    const hw = (e.w || 0.3) / 2, hh = ((e.h > 0 ? e.h : e.w) || 0.3) / 2;
    return [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].map(([lx, ly]) => { const [x, y] = turnPt(lx, ly, arot); return [ax + x, ay + y]; });
  }
  /** The box round pieces, as stored. */
  function extentOf(els) {
    const pts = els.flatMap(pointsOf);
    if (!pts.length) return null;
    return [Math.min(...pts.map((p) => p[0])), Math.min(...pts.map((p) => p[1])), Math.max(...pts.map((p) => p[0])), Math.max(...pts.map((p) => p[1]))];
  }
  /** Where a pick turns about: its box's middle, on the grid with Snap on (the Mac's `pivot`). */
  function pivot(els) {
    const b = extentOf(els);
    if (!b) return [0, 0];
    let c = [(b[0] + b[2]) / 2, (b[1] + b[3]) / 2];
    if (settings().snap) { const s = snapStep(); c = c.map((n) => Math.round(n / s) * s); }
    return c;
  }

  /**
   * **A picked wall's handles** (the Mac's `wallHandles`): a square on every
   * corner; a + beside the middle of each stretch to add a corner there —
   * off the wall, so a press on the wall still moves it — and a + past each
   * open end to grow it on.
   */
  function wallHandles(e) {
    const c = wallCorners(e);
    const n = c.length;
    const out = c.map(([x, y], i) => ({ kind: "wc", i, at: storedToBox(x, y) }));
    let side = 1;
    if (e.closed && n > 2) {
      let a = 0;
      for (let i = 0; i < n; i++) a += c[i][0] * c[(i + 1) % n][1] - c[(i + 1) % n][0] * c[i][1];
      side = a >= 0 ? -1 : 1;
    }
    const off = (e.thick || 0.15) * view().k / 2 + 14;
    const count = e.closed && n > 2 ? n : n - 1;
    for (let i = 0; i < count; i++) {
      const a = storedToBox(...c[i]), b = storedToBox(...c[(i + 1) % n]);
      const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (len <= 40) continue;
      const nx = -(b[1] - a[1]) / len, ny = (b[0] - a[0]) / len;
      out.push({ kind: "add", i, at: [(a[0] + b[0]) / 2 + nx * side * off, (a[1] + b[1]) / 2 + ny * side * off] });
    }
    // The picked corner's curve handles, and those of its neighbours that
    // lean on the stretches beside it (the Mac's).
    if (pickedCorner !== null && pickedCorner < n && e.kind !== "measure") {
      const shut = e.closed && n > 2;
      const knob = (node, outward) => {
        if (node < 0 || node >= n) return;
        const h = nodeHandles(e, node);
        const v = outward ? [h[2], h[3]] : [h[0], h[1]];
        if (Math.abs(v[0]) + Math.abs(v[1]) <= 1e-9) return;
        out.push({ kind: outward ? "hout" : "hin", i: node, at: storedToBox(c[node][0] + v[0], c[node][1] + v[1]), from: storedToBox(...c[node]) });
      };
      const k = pickedCorner;
      knob(k, false); knob(k, true);
      if (k > 0 || shut) knob((k + n - 1) % n, true);
      if (k + 1 < n || shut) knob((k + 1) % n, false);
    }
    if (!(e.closed && n > 2) && n >= 2) {
      for (const [end, p, q] of [[0, c[0], c[1]], [1, c[n - 1], c[n - 2]]]) {
        const vp = storedToBox(...p), vq = storedToBox(...q);
        const len = Math.max(Math.hypot(vp[0] - vq[0], vp[1] - vq[1]), 1e-6);
        const at = [vp[0] + (vp[0] - vq[0]) / len * 22, vp[1] + (vp[1] - vq[1]) / len * 22];
        if (out.some((h) => Math.hypot(h.at[0] - at[0], h.at[1] - at[1]) < 16)) continue;
        out.push({ kind: "ext", i: end, at });
      }
    }
    return out;
  }

  /** A turn's knob: out the way it faces (off its top, for what does not face), further out than the piece's own. */
  function stepKnob(e, t) {
    const hw = (e.w || 0.4) / 2, hh = ((e.h > 0 ? e.h : e.w) || 0.4) / 2;
    const c = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].map(([lx, ly]) => { const [x, y] = turnPt(lx, ly, t.rot); return storedToBox(t.x + x, t.y + y); });
    const top = faces(e) ? [(c[1][0] + c[2][0]) / 2, (c[1][1] + c[2][1]) / 2] : isFrame(e) ? [(c[2][0] + c[3][0]) / 2, (c[2][1] + c[3][1]) / 2] : [(c[0][0] + c[1][0]) / 2, (c[0][1] + c[1][1]) / 2];
    const mid = [(c[0][0] + c[2][0]) / 2, (c[0][1] + c[2][1]) / 2];
    const dx = top[0] - mid[0], dy = top[1] - mid[1], len = Math.max(Math.hypot(dx, dy), 0.001);
    return { top, at: [top[0] + dx / len * 52, top[1] + dy / len * 52] };
  }

  /** The one picked piece's picked step, when a step is picked: { e, i, s }. */
  function stepPicked() {
    if (!pickedStep || picks.length !== 1 || picks[0] !== pickedStep.id) return null;
    const e = el(pickedStep.id);
    const s = e && e.seq && e.seq[pickedStep.i];
    return s ? { e, i: pickedStep.i, s } : null;
  }

  /**
   * **Add Move / Add Turn** (his ruling, 2026-10-01: not an A and a B but
   * as many steps as he likes, each a beat to play later — the Mac's
   * `addStep`): the next step after the one picked, or after the last with
   * the piece itself picked; From puts it just before. Picked when made.
   */
  function addStep(e, turn, from) {
    const p = stepPicked();
    const n = (e.seq || []).length || 1;
    const home = Math.min(e.lead || 0, (e.steps || []).length);
    const op = { op: "step_add", id: e.id };
    if (turn) op.turn = true;
    let made;
    if (from) { op.before = p ? p.i : home; made = op.before; } else { op.after = p ? p.i : n - 1; made = op.after + 1; }
    edit(op, { label: turn ? "Add Turn" : "Add Move" });
    pickedStep = { id: e.id, i: made };
    sideKey = "";
    paint();
  }

  /** The beats a step can be put on: every beat the plan has, the one after, and none. */
  function stepBeats(e) {
    const top = Math.max(got ? got.lastBeat || 1 : 1, ...(e.seq || []).map((t) => t.beat || 0)) + 1;
    return [...Array.from({ length: top }, (_, k) => k + 1), 0];
  }

  /** A piece's outline on screen: its turned footprint, or what the SVG drew for it. */
  /**
   * **A lamp drawn as a mark is outlined by its mark** (`hug`, 2026-10-17):
   * its drawn size, never under 26 points on screen — what he sees is what
   * he picks and sizes.
   */
  function hugSize(e) {
    if (!e || !e.hug || !Array.isArray(e.drawn)) return null;
    const least = 26 / Math.max(view().k, 1e-6);
    return [Math.max(e.drawn[0], least), Math.max(e.drawn[1], least)];
  }
  function outline(svg, e) {
    if (["camera", "cast", "set", "light", "shape", "image", "note", "door", "window", "opening"].includes(e.kind) && e.w > 0) {
      const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
      const hug = hugSize(e);
      const hw = hug ? hug[0] / 2 : e.w / 2, hh = hug ? hug[1] / 2 : (e.h > 0 ? e.h : e.w) / 2;
      const pts = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]].map(([lx, ly]) => {
        const [x, y] = turnPt(lx, ly, arot);
        return storedToBox(ax + x, ay + y);
      });
      const pad = 4;
      const [cx, cy] = storedToBox(ax, ay);
      const grown = pts.map(([x, y]) => { const d = Math.hypot(x - cx, y - cy) || 1; return [x + ((x - cx) / d) * pad, y + ((y - cy) / d) * pad]; });
      return { pts: grown, half: Math.max(...grown.map(([x, y]) => Math.hypot(x - cx, y - cy))) };
    }
    // Anything else: round what the SVG drew for it.
    const q = String(e.id).replace(/["\\]/g, "\\$&");
    let parts = [...svg.querySelectorAll(`[data-el="${q}"]`)];
    const bodies = parts.filter((p) => p.getAttribute("data-part") === "body");
    if (bodies.length) parts = bodies;
    const inv = svg.getScreenCTM() && svg.getScreenCTM().inverse();
    let x1 = Infinity, y1 = Infinity, x2 = -Infinity, y2 = -Infinity;
    for (const p of parts) {
      let bb;
      try { bb = p.getBBox(); } catch { continue; }
      const m = inv && p.getScreenCTM() ? inv.multiply(p.getScreenCTM()) : null;
      for (const [x, y] of [[bb.x, bb.y], [bb.x + bb.width, bb.y], [bb.x, bb.y + bb.height], [bb.x + bb.width, bb.y + bb.height]]) {
        const pt = m ? new DOMPoint(x, y).matrixTransform(m) : { x, y };
        x1 = Math.min(x1, pt.x); y1 = Math.min(y1, pt.y); x2 = Math.max(x2, pt.x); y2 = Math.max(y2, pt.y);
      }
    }
    if (!Number.isFinite(x1)) return null;
    const pad = 5;
    return { pts: [[x1 - pad, y1 - pad], [x2 + pad, y1 - pad], [x2 + pad, y2 + pad], [x1 - pad, y2 + pad]], half: Math.hypot(x2 - x1, y2 - y1) / 2 };
  }

  function beatsBar(g) {
    const bar = root.querySelector(".planbeats");
    if (!bar || !g) return;
    const last = Math.max(1, g.lastBeat);
    const beat = H.beat();
    const shownLast = beatsMode ? Math.max(last, beat) : last;
    if (shownLast <= 1 && !editor()) { bar.hidden = true; bar.innerHTML = ""; return; }
    bar.hidden = false;
    const want = `${beat}/${shownLast}/${play ? 1 : 0}/${beatsMode ? 1 : 0}/${editor() ? 1 : 0}`;
    if (bar.dataset.at === want) return;
    bar.dataset.at = want;
    const steps = shownLast > 1 || beatsMode ? `
      <button type="button" class="pbtn" data-pbeat="${beat - 1}" aria-label="Beat Before"${beat <= 1 || play ? " disabled" : ""}>${H.mark("before", 14)}</button>
      <span aria-live="polite">Beat <b>${beat}</b> of ${shownLast}</span>
      <button type="button" class="pbtn" data-pbeat="${beat + 1}" aria-label="Beat After"${beat >= shownLast || play ? " disabled" : ""}>${H.mark("after", 14)}</button>` : "";
    const playing = shownLast > 1 ? `<button type="button" class="pplay${play ? " on" : ""}" data-pplay="1">${play ? "Stop" : "Play"}</button>` : "";
    const beats = editor() ? (beatsMode
      ? `<button type="button" class="pplay" data-paddbeat="1">Add Beat</button><button type="button" class="pplay on" data-pbeats="1">Done</button>`
      : `<button type="button" class="pplay" data-pbeats="1">Beats${last > 1 ? ` ${last}` : ""}</button>`) : "";
    // Moves and beats are cut on the lighting plot (his call, 2026-10-03).
    void steps; void playing; void beats;
    bar.innerHTML = "";
    bar.querySelectorAll("[data-pbeat]").forEach((b) => b.addEventListener("click", () => { H.setBeat(Math.max(1, Number(b.dataset.pbeat) || 1)); paint(); }));
    const p = bar.querySelector("[data-pplay]");
    if (p) p.addEventListener("click", playToggle);
    const bm = bar.querySelector("[data-pbeats]");
    if (bm) bm.addEventListener("click", () => { beatsMode = !beatsMode; if (!beatsMode && H.beat() > last) H.setBeat(last); paint(); });
    const ab = bar.querySelector("[data-paddbeat]");
    if (ab) ab.addEventListener("click", () => { H.setBeat(Math.max(last, H.beat()) + 1); paint(); toast(`Beat ${H.beat()}: drag a piece to where it goes`); });
  }

  function acts() {
    const u = root.querySelector("[data-pundo]"), r = root.querySelector("[data-predo]");
    const mine = (list) => list.some((x) => x.scene === String(chosen()) || x.scene === String(row()));
    if (u) { u.disabled = !mine(undos); u.title = undos.length ? `Undo ${undos[undos.length - 1].label || ""}` : "Undo"; }
    if (r) { r.disabled = !mine(redos); }
  }

  // ---- the bar over the plan's foot ----------------------------------------------
  //
  // **What is picked, in three groups** (design/26, direction A, his pick of
  // 2026-10-02: *"right now its just a bunch of words back to back and it's a
  // little overwhelming"*): its name · what it is: each setting a quiet word
  // and its value, one tap to change it · what to do: + Move, + Turn and the
  // plain verbs of this piece · then More, everything every piece has, with
  // its keys. When the plan is narrow the bar stays on the foot's own line,
  // between the scale and the zoom, and folds in steps, never jumping over
  // the zoom: everything · the actions go into More · all values but the first
  // go in too · the name alone, a capsule that opens it all.

  /** The wall thicknesses' names, hairline to very thick. */
  const THICK_NAMES = ["Hairline", "Thin", "Standard", "Thick", "Very Thick"];
  const PERCENTS = [50, 75, 100, 125, 150, 200];
  const POINTS = [10, 12, 14, 18, 24, 36, 48];
  const DIMS = [100, 90, 75, 50, 25, 10, 0];
  /** What takes the None colour besides a colour (the Mac's `DiagramActions.colours`). */
  const CLEARABLE = new Set(["light", "text", "wall", "arrow", "shape", "cable", "stroke"]);
  /** A frame's skin as a swatch: the binding colours, the checkerboards, a gel. */
  const matSwatch = (m) => (m.alt && m.alt !== m.fill
    ? `background:repeating-conic-gradient(${m.fill} 0 25%, ${m.alt} 0 50%) 0 0/8px 8px;border-color:${m.edge || m.fill}`
    : `background:${m.fill};border-color:${m.edge || m.fill}`);

  /** How a piece is sized: a share of its library size, points, or a step up and down. */
  function sizeInfo(e) {
    if (e.kind === "text") return { how: "points", text: `${Math.round(e.size || 0)} pt` };
    if (e.kind === "light" || e.kind === "set") {
      const sym = (library().symbols || []).find((s) => s.id === e.sym);
      if (sym && sym.w > 0 && sym.h > 0) {
        const pct = Math.round(((e.w > 0 ? e.w : sym.w) / sym.w) * 100);
        return { how: "percent", sym, pct, text: `${pct}%` };
      }
      return { how: "step", text: "" };
    }
    if (e.kind === "cast" || e.kind === "shape") return { how: "step", text: "" };
    return null;
  }

  /**
   * **One bar per kind** (Back to Paper, Batch 2 — design/32's Panels and
   * Words): the few things changed every day, each a quiet word and its
   * value or a plain verb; everything else under More, which a right-click
   * opens too, built here once. No name repeated at its start: a title only
   * where the bar acts on several ("Shared Label · 4 Lamps", "4 Lamps",
   * "3 Selected"). Nothing picked, no bar.
   *
   * `vals`: `{ act, label, x (its value), dot | sw | mark, html, read }`;
   * `acts`: verbs, `{ act, label, on }`; `extras`: this kind's own under
   * More, `{ act, label, key, check, value, dot }`, above what every piece
   * has (`common`) and Details….
   */
  function barParts(els) {
    const one = els.length === 1 ? els[0] : null;
    const P = { one, title: "", name: one ? one.name : "", vals: [], acts: [], extras: [], more: true, common: true, details: true, locked: els.every((e) => e.locked), canSend: otherScenes().length > 0 };
    const val = (act, label, x = "", more = {}) => P.vals.push({ act, label, x, ...more });
    const verb = (act, label, more = {}) => P.acts.push({ act, label, ...more });
    const extra = (act, label, more = {}) => P.extras.push({ act, label, ...more });
    const hideLabel = (e) => {
      extra("hidelabel", e.label_hidden ? "Show Label" : "Hide Label");
      if (e.label_dx || e.label_dy || e.label_size) extra("resetlabel", "Reset Label");
    };
    const colour = (e) => extra("colour", "Colour", { dot: e.color || "" });
    // A lamp's own: Symbol, Name, Count, Note, Gel, and Off for one we did not bring.
    const lampVals = (e, count = true) => {
      val("symbol", "Symbol", "", { mark: e.look || "" });
      val("name", "Name", e.lamp_name || "");
      if (count) val("count", "Count", String(Math.max(1, e.count || 1)));
      val("note", "Note", e.label || "");
      val("gel", "Gel", gelNames(e));
      if (e.practical || e.existing) verb("off", "Off", { on: e.action === "off" });
      // **Down, and the height it hangs at** (his ask, 2026-10-05: a LiteMat 8 over the set, pointing straight down).
      verb("down", "Down", { on: pointsDown(e) });
      if (pointsDown(e)) val("height", "Height", e.height || "None");
    };
    // **A legend line clicked**: every lamp of that kind, and the bar acts on all of them.
    const line = legendPicked();
    if (line && line.kind === "legend") {
      // As the plan has them now: renamed or re-marked from this very bar.
      const key = (els[0] && (els[0].legend_key || els[0].look)) || line.key;
      const row = ((got && got.legend) || []).find((r) => r.key === key);
      P.title = lampCount(els.reduce((t, x) => t + Math.max(1, x.count || 1), 0));
      P.name = P.title;
      P.common = true;
      P.details = false;
      val("symbol", "Symbol", "", { mark: key });
      val("name", "Name", row && row.named ? row.name : "");
      if (els.filter(isLamp).length >= 2) verb("sharelabel", "Share Label");
      extra("type", "Type", { value: typeWord(els[0]) });
      extra("gel", "Gel");
      extra("colourall", "Colour", { dot: mixedColour(els) ?? "", value: mixedColour(els) === null ? "Mixed" : undefined });
      extra("gearlist", "Copy Gear List");
      extra("hidelegend", "Hide Legend");
      return P;
    }
    if (!one) {
      const groups = new Set(els.map((e) => e.group));
      const together = els.some((e) => e.group) && groups.size === 1;
      P.title = together && els[0].groupName ? els[0].groupName : `${els.length} Selected`;
      P.name = P.title;
      if (els.filter(canShare).length >= 2) verb("sharelabel", "Share Label");
      val("align", "Align");
      verb(together ? "ungroup" : "group", together ? "Ungroup" : "Group");
      if (els.every((e) => e.kind === "wall")) verb("join", "Join");
      if (els.length > 2) { extra("spacex", "Space Evenly Across"); extra("spacey", "Space Evenly Down"); }
      if (els.filter(canShare).some((x) => x.tie_to)) extra("ownlabelall", "Own Label");
      extra("colourall", "Colour", { dot: mixedColour(els) ?? "" , value: mixedColour(els) === null ? "Mixed" : undefined });
      const named = els.filter(hasName);
      if (named.length) extra("labelsall", named.every((x) => x.label_hidden) ? "Show Label" : "Hide Label");
      return P;
    }
    const e = one, k = e.kind;
    // **A shared label**, or a piece tied to one: one bar for all its pieces.
    const shared = isShared(e) ? e : canShare(e) ? labelOf(e) : null;
    if (shared && !heldBy(shared.id).every(isLamp)) {
      // Frames and any piece share a label too (his ask, 2026-10-05): its Note.
      const held = heldBy(shared.id);
      const word = held.every(isFrame) ? (held.length === 1 ? "Frame" : "Frames") : held.length === 1 ? "Piece" : "Pieces";
      P.title = `Shared Label · ${held.length} ${word}`;
      P.name = P.title;
      const lead = held[0];
      val("sharednote", "Note", (noteField(lead) === "note" ? lead.label : lead.caption) || "");
      extra("ownlabel", "Own Label");
      extra("hidelabel", shared.label_hidden ? "Show Label" : "Hide Label");
      P.common = true;
      return P;
    }
    if (shared) {
      const held = heldBy(shared.id);
      const lead = isLamp(e) ? e : held[0];
      P.title = `Shared Label · ${lampCount(held.reduce((t, x) => t + Math.max(1, x.count || 1), 0))}`;
      P.name = P.title;
      lampVals(lead, false);
      extra("ownlabel", "Own Label");
      if (isLamp(e)) extra("count", "Count", { value: String(Math.max(1, e.count || 1)) });
      extra("hidelabel", shared.label_hidden ? "Show Label" : "Hide Label");
      P.common = true;
      return P;
    }
    if (isLamp(e)) {
      lampVals(e);
      extra("spread", "Spread", { value: { "": "One", line: "Line", ring: "Ring" }[e.spread || ""] || "One" });
      extra("swap", "Swap…");
      extra("fade", "Opacity", { value: `${Math.round((e.opacity ?? 1) * 100)}%` });
      hideLabel(e);
      if (e.aim) extra("stopaim", "Stop Aiming");
    } else if (k === "camera") {
      // A camera is its shot (his design, 2026-10-01): the Camera, Lens and a
      // zoom's focal length are the shot's, off the film's own lists.
      const c = (got.cams || []).find((x) => x.id === e.id) || {};
      const row = shotRow(e.shot);
      val("shotpick", "Shot", row ? row.number : "None");
      val("cam", "Camera", c.unit_label || "None");
      val("lens", "Lens", c.lens || (e.lens > 0 ? `${Math.round(e.lens)}mm` : "None"));
      if (c.zoom && c.zoom[1] > c.zoom[0]) val("focal", "Focal", `${Math.round(c.focal || c.zoom[0])}mm`);
      extra("cone", "Lens Cone", { check: Boolean(e.cone) });
      extra("framepic", "Frame on Plan", { check: Boolean(e.frame_on) });
      const isTrack = (x) => x && (x.kind === "track" || (x.kind === "set" && String(x.sym).includes("circle-track")));
      if (isTrack(el(e.rig_on))) extra("unlock", "Unlock");
      else if ((got.els || []).some(isTrack)) extra("ride", "Ride Track");
      colour(e);
      hideLabel(e);
      if (e.aim) extra("stopaim", "Stop Aiming");
      if (e.shot) extra("showinlist", "Show in Shot List");
    } else if (isFrame(e)) {
      const F = library().frames || {};
      const mat = (F.materials || []).find((m) => m.id === (e.material || F.default)) || { name: "Material", fill: "#ccc" };
      // **Its size and cloth, then its Note** (his notes, 2026-10-05): the
      // callout's first line is the Size and Material set here.
      val("framesize", "Size", frameSize(e) || "Custom");
      val("material", "Material", mat.name, { sw: matSwatch(mat) });
      val("note", "Note", e.label || "");
      val("fade", "Opacity", `${Math.round((e.opacity ?? 1) * 100)}%`);
      colour(e);
      extra("lean", "Lean", { value: leanWord(e.tilt) });
      hideLabel(e);
    } else if (isGrip(e)) {
      val("name", "Name", e.label || "");
      verb("swap", "Swap…");
      colour(e);
      hideLabel(e);
    } else if (k === "cast") {
      val("castname", "Name", e.cast || e.label || "");
      val("pose", "Pose", POSES[e.pose || "standing"] || "Standing");
      if (castWho(e)) extra("castcolour", `Colour for ${castWho(e)}`, { dot: castColourNow(castWho(e)) });
      extra("colour", castWho(e) ? "This Piece" : "Colour", { dot: e.color || "" });
      extra("larger", "Larger");
      extra("smaller", "Smaller");
      hideLabel(e);
    } else if (k === "text" || k === "note") {
      val("words", "Text", String(e.text || "").split("\n")[0]);
      const large = (e.size || 0) >= LARGE_AT;
      verb("regular", "Regular", { on: !large });
      verb("large", "Large", { on: large });
      colour(e);
      extra("textalign", "Align", { value: { left: "Left", right: "Right" }[e.align] || "Centre" });
    } else if (k === "wall") {
      const ti = wallThicknesses().findIndex((t) => Math.abs((e.thick || 0) - t) < 0.002);
      val("thick", "Thickness", ti >= 0 ? THICK_NAMES[ti] : "", { html: thicknessPictures(e) });
      val("walllength", "Length", lengthText(wallLength(e)));
      // A picked corner's own: Break and Round beside it, Delete Corner in More.
      const n = wallCorners(e).length;
      if (pickedCorner !== null && pickedCorner < n) {
        const end = !e.closed && (pickedCorner === 0 || pickedCorner === n - 1);
        verb("smooth", "Smooth", { on: isSmooth(e, pickedCorner) });
        if (!end) { verb("break", "Break"); verb("curve", "Round", { on: (e.round || []).includes(pickedCorner) }); }
        extra("deletecorner", "Delete Corner");
      }
      if (canClose(e)) verb("join", "Join");
      extra("name", "Name", { value: e.label || "" });
      extra("pathkind", "Kind", { value: "Wall" });
      if (e.closed && wallCorners(e).length > 2) extra("pathfill", "Fill", { check: Boolean(e.fill_color) });
      colour(e);
    } else if (k === "door" || k === "window" || k === "opening") {
      val("width", "Width", lengthText(e.w || 0));
      if (k === "door") {
        const sw = Number(e.swing ?? 90), kind = doorKind(e);
        val("doorkind", "Style", (DOOR_KINDS.find(([v]) => v === kind) || ["", "Swing"])[1]);
        verb("doorshut", "Closed", { on: sw < 5 });
        if (e.slide) verb("doorhalf", "Half", { on: sw >= 5 && sw < 89.5 });
        verb("dooropen", "Open", { on: e.slide ? sw >= 89.5 : sw >= 5 });
        verb(kind === "double" || kind === "center" ? "side" : "hinge", "Flip");
        extra("side", "Flip Side");
      } else extra("side", "Flip Side");
    } else if (k === "set") {
      val("name", "Name", e.label || "");
      verb("swap", "Swap…");
      extra("larger", "Larger");
      extra("smaller", "Smaller");
      hideLabel(e);
    } else if (k === "measure") {
      val("", "Length", lengthText(wallLength(e)), { read: true });
      // A picked marker locks to something, lets go, or goes.
      const c = wallCorners(e);
      if (pickedCorner !== null && pickedCorner < c.length) {
        const pin = (e.pins || [])[pickedCorner] || "";
        const t = pin ? el(pin) : null;
        val("lockto", t ? `Locked to ${t.name || word(t.kind)}` : "Lock To");
        if (pin) extra("unlockmarker", "Unlock Marker");
        if (c.length > 2) extra("deletemarker", "Delete Marker");
      }
      extra("under", "Behind Everything", { check: Boolean(e.under) });
      colour(e);
    } else if (k === "track") {
      // A dolly track's length and its pieces: "24 ft · 3 × 8'" (the Mac's).
      const len = Math.hypot((e.x2 || 0) - e.x, (e.y2 || 0) - e.y);
      val("", "Length", lengthText(len) + (units() !== "m" && len > 0.1 ? ` · ${Math.ceil(len / (8 * 0.3048))} × 8'` : ""), { read: true });
      val("name", "Name", e.label || "");
      extra("gauge", "Gauge", { value: lengthText(e.thick || 0) });
    } else if (k === "road") {
      // A street (the Mac's): its Name, its Note, and its Kind by its width.
      val("name", "Name", e.label || "");
      const rk = ROAD_KINDS.find(([, w]) => Math.abs((e.thick || 0) - w) < 0.05);
      val("roadkind", "Kind", rk ? rk[0] : "Custom");
    } else if (k === "arrow") {
      val("heads", "Heads", { end: "One", both: "Both", none: "None" }[e.head || "end"] || "One");
      val("dash", "Line", { dashed: "Dashed", dotted: "Dotted" }[e.dash] || "Solid");
      extra("name", "Name", { value: e.label || "" });
      colour(e);
      extra("weight", "Weight", { value: `${e.weight || 1.5} pt` });
    } else if (k === "shape") {
      val("colour", "Colour", "", { dot: e.color || "" });
      verb("fill", "Fill", { on: Boolean(e.fill) });
      extra("name", "Name", { value: e.label || "" });
    } else if (k === "cable" || k === "stroke") {
      val("colour", "Colour", "", { dot: e.color || "" });
      val("dash", "Line", { dashed: "Dashed", dotted: "Dotted" }[e.dash] || "Solid");
      if (k === "cable" || isPath(e)) extra("name", "Name", { value: e.label || "" });
      // A drawn path (the Draw tool's) is a line, a wall or an object, filled when closed.
      if (isPath(e) && pickedCorner !== null && pickedCorner < wallCorners(e).length) verb("smooth", "Smooth", { on: isSmooth(e, pickedCorner) });
      if (isPath(e)) {
        extra("pathkind", "Kind", { value: e.fill && e.closed ? "Object" : "Line" });
        if (e.closed) extra("pathfill", "Fill", { check: Boolean(e.fill) });
      }
    } else if (k === "image") {
      // A picture's bar (the Mac's): Draw on Photo, Set Scale, then Opacity.
      verb("drawon", "Draw on Photo");
      verb("setscale", "Set Scale");
      if (marksLyingOn(e)) extra("attachmarks", "Attach to Photo");
      val("fade", "Opacity", `${Math.round((e.opacity ?? 1) * 100)}%`);
      extra("showas", "Show As", { value: e.role === "photo" ? "Photo" : "Background" });
    }
    // **Every piece's Note** (his note, 2026-10-05: "alll items should be
    // able to have a note"), after its first setting.
    if (notable(e)) P.vals.splice(Math.min(1, P.vals.length), 0, { act: "caption", label: "Note", x: e.caption || "" });
    return P;
  }

  /** The gels by section, as the Mac lists them (`DiagramGels.groups`). */
  function gelGroups() {
    const of = (g) => /^ct[ob]-/.test(g.id) ? "Colour Temperature" : /^nd/.test(g.id) ? "Neutral Density" : /green/.test(g.id) ? "Green" : "Diffusion";
    const out = new Map([["Colour Temperature", []], ["Neutral Density", []], ["Green", []], ["Diffusion", []]]);
    for (const g of library().gels || []) out.get(of(g)).push(g);
    return [...out].filter(([, list]) => list.length);
  }
  const gelName = (id) => ((library().gels || []).find((g) => g.id === id) || { name: id }).name;
  /** A street's kinds by width (the Mac's `roadKinds`): Street 30 ft, Alley 15, Driveway 10, Path 4. */
  const ROAD_KINDS = [["Street", 9.144], ["Alley", 4.572], ["Driveway", 3.048], ["Path", 1.2192]];
  /** An open wall whose ends nearly meet: Join closes it (the Mac's `canClose`). */
  function canClose(e) {
    if (!e || e.kind !== "wall" || e.closed || e.locked) return false;
    const c = wallCorners(e);
    if (c.length < 3) return false;
    const gap = units() === "m" ? 0.9 : 3 * 0.3048;
    return Math.hypot(c[0][0] - c[c.length - 1][0], c[0][1] - c[c.length - 1][1]) <= gap * 1.7;
  }
  /** What wears a Note of its own, its `caption`: every piece that draws a name, but a lamp's and a frame's Note is their label, and Words are words. */
  function notable(e) {
    if (!e || isLamp(e) || isFrame(e)) return false;
    return ["light", "set", "track", "road", "arrow", "shape", "cable", "wall", "camera", "cast"].includes(e.kind)
      || (e.kind === "stroke" && (e.handles || []).length > 0);
  }

  const POSES = { standing: "Standing", seated: "Seated", lying: "Lying" };
  /** Words stored at or over this size read Large (`render::words_large`); Regular and Large as stored (`WORDS_REGULAR`, `WORDS_LARGE`). */
  const LARGE_AT = 8, WORDS_REGULAR = 20 / 3, WORDS_LARGE = 28 / 3;
  const lampCount = (n) => `${n} ${n === 1 ? "Lamp" : "Lamps"}`;
  const typeWord = (e) => (e && e.existing ? "Existing" : e && e.practical ? "Practical" : "Film Light");
  const gelNames = (e) => (e.gels || []).map((id) => ((library().gels || []).find((g) => g.id === id) || { name: id }).name).join(", ");
  const FRAME_SIZES = [[4, 4], [6, 6], [8, 8], [12, 12], [12, 20], [20, 20], [20, 40]];
  /** A frame's size by name, "12×12", or "" when it is none of the usual. */
  function frameSize(e) {
    const FT = 0.3048, tall = e.tall > 0 ? e.tall : e.h;
    const now = FRAME_SIZES.find(([a, b]) => Math.abs(a * FT - e.h) < 0.05 && Math.abs(b * FT - tall) < 0.05);
    return now ? `${now[0]}×${now[1]}` : "";
  }
  const LEANS = [[0, "Flat"], [15, "15°"], [30, "30°"], [45, "45°"], [60, "60°"], [75, "75°"], [90, "Standing"]];
  const leanWord = (t) => { const n = Math.round(Number(t) || 0); const hit = LEANS.find(([v]) => v === n); return hit ? hit[1] : `${n}°`; };
  /** A wall's or ruler's whole length, corner to corner (a room round to its start). */
  function wallLength(e) {
    const c = wallCorners(e);
    const run = e.closed && c.length > 2 ? [...c, c[0]] : c;
    const s = e.kind === "wall" ? pickedStretch ?? (run.length === 2 ? 0 : null) : null;
    if (s !== null && s < run.length - 1) return stretchShown(e, s);
    return run.slice(1).reduce((t, p, i) => t + Math.hypot(p[0] - run[i][0], p[1] - run[i][1]), 0);
  }

  /** One value as the bar draws it: a quiet word and its value, a colour's dot, a frame's swatch, a lamp's mark. */
  function valHTML(v) {
    if (v.html) return v.html;
    if (v.read) return `<span class="pbv read"><span class="k">${esc(v.label)}</span><span class="x">${esc(v.x)}</span></span>`;
    const mark = v.mark !== undefined ? `<i class="pbmark">${v.mark ? markSvg(lookOf(v.mark), 16) : ""}</i>` : "";
    const solo = !v.x && v.dot === undefined && !mark && !v.sw;
    const said = [v.label, v.x].filter(Boolean).join(" ");
    return `<button type="button" class="pbv${solo ? " solo" : ""}" data-pa="${v.act}" aria-label="${esc(said)}">`
      + `<span class="${solo ? "x" : "k"}">${esc(v.label)}</span>${mark}`
      + `${v.sw ? `<i class="pbsw" style="${esc(v.sw)}"></i>` : ""}`
      + `${v.dot !== undefined ? `<i class="pbdot" style="${v.dot ? `background:${esc(v.dot)}` : "background:transparent"}"></i>` : ""}`
      + `${v.x ? `<span class="x">${esc(v.x)}</span>` : ""}</button>`;
  }
  const actHTML = (a) => `<button type="button" class="pbw${a.on ? " on" : ""}" data-pa="${a.act}">${esc(a.label)}</button>`;

  /**
   * The bar at one of its four steps of folding: 0 everything · 1 verbs
   * folded · 2 values folded but the first · 3 More alone. **No down
   * arrows** on a menu button (his ruling): More is a word like any other.
   */
  function barHTML(P, level) {
    if (level >= 3) return `<button type="button" class="pbbtn pbname" data-pa="more" aria-label="${esc(P.title || "More")}"><span class="pbtxt">${esc(P.title || "More")}</span></button>`;
    const vals = level >= 2 ? P.vals.slice(0, 1) : P.vals;
    const acts = level >= 1 ? [] : P.acts;
    const more = P.more || level >= 1 && (P.acts.length || vals.length < P.vals.length);
    const rule = `<i class="pfrule"></i>`;
    const parts = [P.title ? `<span class="pfname">${esc(P.title)}</span>` : "", vals.map(valHTML).join(""), acts.map(actHTML).join("")].filter(Boolean);
    return `${parts.join(rule)}${more ? `<button type="button" class="pbbtn" data-pa="more">More</button>` : ""}`;
  }

  /**
   * **Put the bar on the foot's line and fold it to fit.** The free line is
   * between the scale (when the plan draws one) and the zoom; the richest of
   * the four steps that fits is kept, measured (drawn off the page
   * first), never guessed. Narrower than the name alone: the scale is covered and the
   * name shortens with an ellipsis. Drawn again only when what it says or the
   * room it has changes.
   */
  function layoutBar(f, P) {
    const vp = f.parentElement;
    const vr = vp.getBoundingClientRect();
    const zoom = vp.querySelector(".planzoom");
    const hi = (zoom ? zoom.getBoundingClientRect().left - vr.left : vr.width - 12) - 10;
    const scale = vp.querySelector(".planscale");
    let lo = scale ? Math.max(12, scale.getBoundingClientRect().right - vr.left + 10) : 12;
    const key = `${barHTML(P, 0)}|${Math.round(lo)}|${Math.round(hi)}`;
    if (f.className === "planfloat bar" && f.dataset.pbk === key && f.firstChild) { if (scale) scale.style.visibility = f.dataset.cover ? "hidden" : ""; return; }
    const m = document.createElement("div");
    m.className = "planfloat bar pbmeasure";
    vp.append(m);
    const fits = (level, room) => { m.innerHTML = barHTML(P, level); return m.getBoundingClientRect().width <= room; };
    let room = hi - lo, level = 0;
    while (level < 3 && !fits(level, room)) level += 1;
    // Folding hides what is changed every day: the bar may lie over the
    // scale instead, the whole foot of the plan to the zoom.
    if (level > 0 && lo > 12) {
      let wide = 0;
      while (wide < level && !fits(wide, hi - 12)) wide += 1;
      if (wide < level) { level = wide; lo = 12; room = hi - lo; }
    }
    m.remove();
    barFold = level;
    // Lying over the scale, the bar hides it rather than sit on top of it.
    f.dataset.cover = scale && lo === 12 && scale.getBoundingClientRect().width > 0 ? "1" : "";
    if (scale) scale.style.visibility = f.dataset.cover ? "hidden" : "";
    f.className = "planfloat bar";
    f.style.top = ""; f.style.transform = ""; delete f.dataset.ax;
    f.dataset.pbk = key;
    f.innerHTML = barHTML(P, level);
    f.style.left = `${lo + room / 2}px`;
    f.style.maxWidth = `${Math.max(room, 48)}px`;
    f.querySelectorAll("[data-pa]").forEach((b) => b.addEventListener("click", () => action(b.dataset.pa, b)));
    f.querySelectorAll("[data-pthick]").forEach((b) => b.addEventListener("click", () => {
      const e = picks.length === 1 ? el(picks[0]) : null;
      if (e) edit({ op: "update", ids: [e.id], set: { thick: Number(b.dataset.pthick) } }, { label: "Thickness" });
    }));
  }

  /** The bar over the plan's foot for what is picked — the Mac's action bar. */
  function float() {
    const f = root.querySelector(".planfloat");
    if (!f) return;
    const sc = root.querySelector(".planscale");
    if (sc && sc.style.visibility) sc.style.visibility = "";
    // The bar sets its own place; a panel here keeps the stylesheet's.
    const panel = (draw) => { f.style.left = ""; f.style.top = ""; f.style.transform = ""; f.style.maxWidth = ""; f.dataset.pbk = ""; delete f.dataset.ax; return draw(f); };
    const none = () => panel(() => { f.innerHTML = ""; f.className = "planfloat"; });
    if (linkPanel) return panel(linkFloat);
    if (photo && editor()) return photoEl() ? panel(photoFoot) : none();
    if (castMenu) return panel(castFloat);
    if (picMenu) return panel(picFloat);
    if (swap) { if (swapping()) return panel(swapFloat); closeSwap(false); }
    if (libOpen && LIBS[tool]) return panel(libFloat);
    if (editor() && tool === "light") return panel(markFloat);
    if (editor() && tool === "pen") return panel(penFloat);
    if (editor() && tool === "shape") return panel(shapeFloat);
    if (favOpen) return panel(favFloat);
    if (copyPanel) return panel(copyFloat);
    if (roomOpen && editor()) return panel(roomFloat);
    if (editor() && got && !(got.els || []).length && tool === "select") return panel(emptyFloat);
    if (!editor()) {
      // One piece, or one whole group: a group is kept as one favorite (his custom objects, 2026-10-04).
    const sameGroup = picks.length > 1 && picks.every((id) => { const x = el(id); return x && x.group && x.group === (el(picks[0]) || {}).group; });
    const one = picks.length === 1 || sameGroup ? el(picks[0]) : null;
      return one && !presenting ? lookFloat(f, one) : none();
    }
    if (!picks.length || drag || wallDraw) return none();
    // Details open: the bar steps aside (Back to Paper, Batch 2).
    if (tab === "details") return none();
    const els = picks.map(el).filter(Boolean);
    if (!els.length) return none();
    // **Several lamps of one kind, picked by hand**, are that kind's legend
    // line (the Mac's `DiagramPick.kind`): one Name, one Symbol, the bar
    // and its menu act on all of them.
    if (!legendPicked() && els.length > 1 && els.every(isLamp)) {
      const key = (x) => x.legend_key || x.look || "";
      if (els.every((x) => key(x) === key(els[0]))) {
        const row = ((got && got.legend) || []).find((r) => r.key === key(els[0]));
        legendPick = { kind: "legend", key: key(els[0]), ids: els.map((x) => x.id), name: row ? row.name : "", count: els.reduce((t, x) => t + Math.max(1, x.count || 1), 0) };
      }
    }
    layoutBar(f, barParts(els));
  }

  // ---- a tool's options, under the toolbar (the Mac's strip) ------------------

  const SHAPES = [["rect", "Rectangle"], ["ellipse", "Ellipse"], ["triangle", "Triangle"], ["diamond", "Diamond"], ["hexagon", "Hexagon"], ["star", "Star"], ["line", "Line"]];
  const PEN_INKS = ["", "#E5484D", "#D97706", "#16A34A", "#0A6CE8", "#7B4BC4"];
  /** The Camera button's menu (the Mac's `choices`): a new shot, any of the scene's shots (ticked when placed), or a camera alone. */
  function cameraChoices(anchor) {
    const cams = (got && got.cams) || [];
    const arm = (v) => () => { armedShot = v; setTool("camera"); };
    const rows = shotsOfScene();
    const items = [{ label: "New Shot", pick: arm("new") }];
    if (rows.length) {
      items.push({ rule: true }, { head: "Shots in This Scene" });
      for (const r of rows) items.push({ label: `${r.number}  ${String(r.description || r.title || "").slice(0, 40)}`, check: cams.some((c) => c.shot === r.shot), pick: arm(r.shot) });
    }
    items.push({ rule: true }, { label: "Camera Only", pick: arm("") });
    const ar = anchor.getBoundingClientRect();
    openMenu(anchor, items, true, [ar.left, ar.bottom + 6]);
  }

  function shapeFloat(f) {
    f.className = "planfloat ptoolopts";
    f.innerHTML = `<div class="ppills">${SHAPES.map(([k, n]) => `<button type="button" class="ppill${shapeKind === k ? " on" : ""}" data-pshapek="${k}">${n}</button>`).join("")}</div>`;
    f.querySelectorAll("[data-pshapek]").forEach((b) => b.addEventListener("click", () => { shapeKind = b.dataset.pshapek; float(); }));
  }
  function penFloat(f) {
    f.className = "planfloat ptoolopts";
    const inks = penAs !== "wall" || penFill
      ? `<div class="pinks">${PEN_INKS.map((c) => `<button type="button" class="pink${penColour === c ? " on" : ""}" data-ppenink="${c}" style="background:${c || "var(--ink)"}" aria-label="${c ? PALETTE_NAMES[PALETTE.indexOf(c)] || "Colour" : "Ink"}"></button>`).join("")}</div>` : "";
    f.innerHTML = `<div class="ppills">${[["line", "Line"], ["wall", "Wall"], ["object", "Object"]].map(([k, n]) =>
      `<button type="button" class="ppill${penAs === k ? " on" : ""}" data-ppenas="${k}">${n}</button>`).join("")}</div>
      <button type="button" class="ppill${penFill || penAs === "object" ? " on" : ""}" data-ppenfill="1">Fill</button>
      <span class="phint">${penNodes.length ? "Return to finish · ⌫ takes a point back" : "Click for a corner · drag for a curve · click the first point to close"}</span>${inks}`;
    f.querySelectorAll("[data-ppenas]").forEach((b) => b.addEventListener("click", () => { penAs = b.dataset.ppenas; float(); frame(); }));
    f.querySelector("[data-ppenfill]").addEventListener("click", () => { if (penAs === "object") { penAs = "line"; penFill = false; } else penFill = !penFill; float(); });
    f.querySelectorAll("[data-ppenink]").forEach((b) => b.addEventListener("click", () => { penColour = b.dataset.ppenink; float(); frame(); }));
  }

  // ---- a piece looked at: what it is, beside it ------------------------------
  //
  // **Looking, a tap says what a thing is** — the Mac's shot card
  // (`DiagramShotPop`), read, not changed: a camera is its shot, so it says
  // the shot (its frame, its words, its size, movement and lens); a lamp says
  // its fixture and how it is set; a person who they are. Beside the piece on
  // a desk, behind a camera so it never sits on its cone; on a phone a card
  // along the plan's foot, over nothing that matters.

  /** A length as it is written on the plan, or a size: `6 ft × 2 ft 6 in`. */
  const sizeText = (w, h) => `${lengthText(w)} × ${lengthText(h)}`;
  function lookVals(e) {
    const L = library();
    const v = [];
    const put = (k, x) => { if (x !== undefined && x !== null && String(x).trim()) v.push([k, String(x)]); };
    const symName = (id) => ((L.symbols || []).find((x) => x.id === id) || {}).name || "";
    const k = e.kind;
    if (k === "camera") {
      const c = ((got && got.cams) || []).find((x) => x.id === e.id) || {};
      const row = shotRow(e.shot);
      if (row) { put("Size", H.named(row.size)); put("Movement", H.named(row.movement)); }
      put("Lens", row && row.lens ? H.named(row.lens) : c.lens || (c.focal ? `${Math.round(c.focal)}mm` : ""));
      if (c.aov) put("View", `${Math.round(c.aov)}°`);
      if (row) put("Angle", (row.angle || []).map(H.named).join(", "));
      // A camera's own Height and Rig draw nothing on a plot (Back to Paper,
      // Batch 2): the shot's Equipment says how it is made.
      if (row && row.support) put("Equipment", H.named(row.support));
      put("Camera", c.unit_label);
    } else if (k === "cast") {
      if (e.cast && e.cast !== e.name) put("Character", e.cast);
      if (e.pose && e.pose !== "standing") put("Pose", e.pose[0].toUpperCase() + e.pose.slice(1));
    } else if (isFrame(e)) {
      put("Material", ((L.materials || []).find((m) => m.id === (e.material || L.material)) || {}).name);
      put("Size", sizeText(e.h, e.tall > 0 ? e.tall : e.h));
    } else if (isLamp(e)) {
      // **Name and Note** (Back to Paper, Batch 2): what it is, its Type, how
      // many, and its second line as the plan writes it — note, gels, Off.
      // Its Name heads the card, its Type beside it (`lookHTML`).
      if ((e.count || 1) > 1) put("Count", String(e.count));
      put("Note", e.label_lines ? e.label_lines[1] : e.label);
    } else if (k === "set") {
      const kind = symName(e.sym);
      if (kind && kind !== e.name) put("Kind", kind);
      if (e.w && e.h) put("Size", sizeText(e.w, e.h));
    } else if (k === "wall" || k === "measure") {
      const c = wallCorners(e);
      let n = 0;
      for (let i = 1; i < c.length; i++) n += Math.hypot(c[i][0] - c[i - 1][0], c[i][1] - c[i - 1][1]);
      if (e.closed && c.length > 2) n += Math.hypot(c[0][0] - c[c.length - 1][0], c[0][1] - c[c.length - 1][1]);
      put(k === "measure" ? "Distance" : "Length", lengthText(n));
    } else if (k === "door" || k === "window" || k === "opening") {
      if (e.w) put("Width", lengthText(e.w));
    }
    // A lamp's gels are on its Note line, as the plan writes them.
    if (!isLamp(e) && (e.gels || []).length) put("Gel", e.gels.map((id) => ((L.gels || []).find((g) => g.id === id) || { name: id }).name).join(", "));
    // Not the per-piece `note`: a room scan keeps its mark there, and a
    // lamp's Note is its second line. Steps and beats draw nothing on a plot.
    return v;
  }
  function lookHTML(e) {
    const row = e.kind === "camera" ? shotRow(e.shot) : null;
    const dot = e.color && /^#/.test(e.color) && (e.kind === "camera" || e.kind === "cast") ? `<span class="pdot" style="background:${esc(e.color)}"></span>` : "";
    // What sort of thing it is, in the library's words: a lamp that throws
    // no light is Grip, a frame is a Frame, a ruler is a Ruler.
    const sort = isFrame(e) ? "Frame" : isGrip(e) ? "Grip" : isLamp(e) ? (e.existing ? "Existing" : e.practical ? "Practical" : "Film Light") : word(e.kind);
    const named = e.kind === "measure" && !e.label ? sort : isLamp(e) ? (e.lamp_name || "Lamp") : e.name;
    const title = row ? `Shot ${row.number}` : named || sort;
    const kind = row ? (e.name && e.name !== row.number ? e.name : "") : named && named !== sort ? sort : "";
    let pic = "", tall = false;
    if (row && row.frame) {
      const r = Number(H.model().project && H.model().project.ratio) || 16 / 9;
      pic = `<div class="plframe${r < 1 ? " tall" : ""}" style="aspect-ratio:${r}">${H.mediaTag(row.frame)}</div>`;
      tall = r < 1;
    }
    const words = row ? [row.title, row.description].filter(Boolean) : e.kind === "text" || e.kind === "note" ? [e.text].filter(Boolean) : [];
    const vals = lookVals(e);
    return `<div class="plhead">${dot}<b>${esc(title)}</b>${kind ? `<span>${esc(kind)}</span>` : ""}
        ${row ? `<button type="button" class="plgo" data-pgoshot="${esc(row.shot)}">Shot List</button>` : ""}</div>
      ${pic || words.length || vals.length ? `<div class="plbody${tall ? " beside" : ""}">${pic}<div class="pltext">
        ${row && row.title ? `<p class="plwords"><b>${esc(row.title)}</b></p>` : ""}
        ${words.filter((w) => !(row && w === row.title)).map((w) => `<p class="plwords">${esc(w)}</p>`).join("")}
        ${vals.length ? `<dl class="plvals">${vals.map(([k, x]) => `<dt>${esc(k)}</dt><dd>${esc(x)}</dd>`).join("")}</dl>` : ""}
      </div></div>` : ""}`;
  }
  function lookFloat(f, e) {
    const sheet = H.narrow();
    const html = lookHTML(e);
    const key = `${e.id}|${sheet}|${html.length}|${html}`;
    if (!(f.classList.contains("look") && f.dataset.pbk === key)) {
      f.className = `planfloat look${sheet ? " sheet" : ""}`;
      f.dataset.pbk = key;
      f.style.maxWidth = "";
      f.innerHTML = html;
      f.querySelectorAll("[data-pgoshot]").forEach((b) => b.addEventListener("click", () => H.showShot(b.dataset.pgoshot)));
    }
    f.style.transform = "";
    if (sheet) { f.style.left = ""; f.style.top = ""; delete f.dataset.ax; return; }
    // Beside it: left, right, above or below — whichever covers least of
    // what the piece faces (a camera's cone, a lamp's throw), then has to be
    // pushed least to fit. Kept on the plan and off the zoom along the foot.
    const b = box();
    const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
    const [px, py] = storedToBox(ax, ay);
    const w = f.offsetWidth, h = f.offsetHeight;
    const gap = Math.max(e.w || 0.4, e.h || 0.4) * view().k / 2 + 22;
    const face = rad(arot + turn());
    const c = e.kind === "camera" ? ((got && got.cams) || []).find((x) => x.id === e.id) : null;
    const half = rad(Math.min(60, Math.max(8, c && c.aov ? c.aov / 2 : 20)));
    // Points along the middle and both edges of what it faces, on screen.
    const ahead = [];
    if (faces(e)) for (const a of [face - half, face, face + half]) for (let d = 24; d <= 420; d += 24) ahead.push([px + Math.cos(a) * d, py + Math.sin(a) * d]);
    const lo = 12, hiX = b.w - 12, hiY = b.h - 60;
    const sides = [
      [-1, 0, px - gap - w, py - h / 2], [1, 0, px + gap, py - h / 2],
      [0, -1, px - w / 2, py - gap - h], [0, 1, px - w / 2, py + gap],
    ].map(([dx, dy, x, y]) => {
      const cx = Math.min(Math.max(x, lo), Math.max(lo, hiX - w)), cy = Math.min(Math.max(y, lo), Math.max(lo, hiY - h));
      const inside = ([qx, qy]) => qx >= cx && qx <= cx + w && qy >= cy && qy <= cy + h;
      const covered = ahead.filter(inside).length;
      const pushed = dx ? Math.abs(cx - x) : Math.abs(cy - y);
      return { x: cx, y: cy, cost: (inside([px, py]) ? 1000 : 0) + covered * 12 + pushed + (dy ? 4 : 0) };
    }).sort((p, q) => p.cost - q.cost);
    const { x, y } = sides[0];
    f.style.left = `${x}px`;
    f.style.top = `${y}px`;
    f.dataset.ax = String(px);
    f.dataset.ay = String(py);
  }

  /**
   * **More, and the right-click: one menu** (Back to Paper, Batch 2). What
   * folded away for width (verbs first, then each folded value, still
   * showing what it is set to, opening its own picker), then this kind's
   * own, then what every piece has with its keys, Details…, and Delete.
   * From a right-click (`pointer`) nothing is folded.
   */
  function openMore(anchor, pointer = null) {
    const els = picks.map(el).filter(Boolean);
    if (!els.length) return;
    const P = barParts(els);
    const level = pointer ? 0 : barFold;
    // By the pointer, what it opens in turn (Spread, Colour…) opens there too.
    if (pointer) anchor = { getBoundingClientRect: () => ({ left: pointer[0], right: pointer[0], top: pointer[1], bottom: pointer[1], width: 0, height: 0 }), contains: () => false };
    const go = (act) => () => action(act, anchor);
    const sections = [];
    const folded = [];
    if (level >= 1) P.acts.forEach((a) => folded.push({ label: a.label, check: a.on, pick: go(a.act) }));
    P.vals.slice(level >= 3 ? 0 : level >= 2 ? 1 : P.vals.length).filter((v) => !v.read && v.act).forEach((v) => folded.push({ label: v.label, value: v.x, dot: v.dot, sw: v.sw, pick: go(v.act) }));
    if (folded.length) sections.push(folded);
    if (P.extras.length) sections.push(P.extras.map((x) => ({ label: x.label, key: x.key, check: x.check, value: x.value, dot: x.dot, pick: go(x.act) })));
    if (P.details) sections.push([{ label: "Details…", key: "Double-click", check: tab === "details", pick: go("details") }]);
    if (P.common) {
      // **What every piece has** (the Mac's `common`): Favorites, the
      // clipboard, Arrange, Group, Lock, Hide — then Delete.
      const one = els.length === 1 ? els[0] : null;
      const sameGroup = els.length > 1 && els.every((x) => x.group && x.group === els[0].group);
      if ((one && !one.locked) || sameGroup) sections.push([{ label: sameGroup ? "Add Group to Favorites" : "Add to Favorites", value: "›", pick: go("favs") }]);
      sections.push([
        { label: "Cut", key: "⌘X", pick: go("cut") },
        { label: "Copy", key: "⌘C", pick: go("copy") },
        { label: "Paste", key: "⌘V", pick: go("paste") },
        { label: "Duplicate", key: "⌘D", pick: go("duplicate") },
        ...(P.canSend ? [{ label: "Send To…", pick: go("send") }] : []),
      ]);
      // **Send to Set / Send to Plot** (his ask, 2026-10-17): where it stands, the other view; Copy leaves it here too.
      const crossing = els.filter(canCross);
      if (crossing.length) {
        const to = otherLayer(crossing);
        const n = to === "set" ? "Set" : "Plot";
        sections.push([{ label: `Send to ${n}`, pick: go("sendlayer") }, { label: `Copy to ${n}`, pick: go("copylayer") }]);
      }
      const arr = [{ label: "Arrange", value: "›", pick: go("arrange") }];
      if (els.length > 1) arr.push({ label: "Group", key: "⌘G", pick: go("group") });
      if (els.some((x) => x.group)) arr.push({ label: "Ungroup", key: "⇧⌘G", pick: go("ungroup") });
      arr.push({ label: P.locked ? "Unlock" : "Lock", key: "⌘L", pick: go("lock") }, { label: "Hide", key: "⇧⌘H", pick: go("hide") });
      sections.push(arr);
    }
    if (P.common || P.title.startsWith("Shared Label")) sections.push([{ label: "Delete", key: "⌫", pick: go("delete") }]);
    const items = sections.flatMap((s, i) => (i ? [{ rule: true }, ...s] : s));
    if (items.length) openMenu(anchor, items, true, pointer);
  }

  /** Where a menu opened from another opens: by the pointer it was opened at, else under its button. */
  const anchorAt = (a) => { const r = a && a.getBoundingClientRect ? a.getBoundingClientRect() : null; return r ? [r.left, r.bottom + 4] : null; };
  /** ⌘C and ⌘X: the picked pieces kept to paste, on the page and on the clipboard. */
  function copyPicks(cut) {
    if (!picks.length) return;
    clip = picks.map(el).filter(Boolean).map((e) => { const c = { ...e }; for (const x of ["id", "name", "show", "at", "emits", "groupName"]) delete c[x]; return c; });
    try { navigator.clipboard.writeText(JSON.stringify({ shotlisterPlan: clip })).catch(() => {}); } catch { /* the page keeps its own copy */ }
    if (cut) remove(picks.slice());
    else toast(`Copied ${H.many(clip.length, "piece")}`);
  }
  /** Right-click on the empty plan (the Mac's `nothing`): Paste, Select All, the hidden shown, the locked let go, Zoom to Fit. */
  function emptyMenu(at) {
    const all = (got && got.els) || [];
    const hidden = all.filter((e) => e.hidden).map((e) => e.id);
    const locked = all.filter((e) => e.locked).map((e) => e.id);
    const items = [
      { label: "Paste", key: "⌘V", pick: () => paste() },
      { label: "Select All", key: "⌘A", pick: () => { picks = all.filter((e) => !e.hidden && !e.locked && layerOf(e) === layer).map((e) => e.id); sideKey = ""; paint(); } },
    ];
    if (hidden.length) items.push({ label: hidden.length === 1 ? "Show Hidden Item" : `Show ${hidden.length} Hidden Items`, pick: () => { edit({ op: "update", ids: hidden, set: { hidden: false } }, { label: "Show" }); picks = hidden.slice(); paint(); } });
    if (locked.length) items.push({ label: "Unlock All", pick: () => edit({ op: "update", ids: locked, set: { locked: false } }, { label: "Unlock All" }) });
    items.push({ rule: true }, { label: "Zoom to Fit", key: "⌘0", pick: () => { const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" }); paint(); } });
    openMenu(null, items, true, at);
  }

  /** The five thicknesses a wall takes in one tap, hairline to very thick — pictures, not numbers (Scenario's). */
  function wallThicknesses() {
    return units() === "m" ? [0.025, 0.1, 0.15, 0.23, 0.3] : [1, 4, 6, 9, 12].map((n) => n * 0.0254);
  }
  function thicknessPictures(e) {
    const drawn = [1, 2.5, 4, 6, 8.5];
    return `<span class="pthicks">${wallThicknesses().map((t, i) =>
      `<button type="button" class="pthick${Math.abs((e.thick || 0) - t) < 0.002 ? " on" : ""}" data-pthick="${t}" title="${THICK_NAMES[i]}" aria-label="${THICK_NAMES[i]}"><i style="height:${drawn[i]}px"></i></button>`).join("")}</span>`;
  }

  /** Lock, or unlock when every piece picked is locked already. */
  function lockPicks() {
    const els = picks.map(el).filter(Boolean);
    if (!els.length) return;
    const all = els.every((e) => e.locked);
    edit({ op: "update", ids: els.map((e) => e.id), set: { locked: !all } }, { label: all ? "Unlock" : "Lock" });
  }
  function hidePicks() {
    if (!picks.length) return;
    edit({ op: "update", ids: picks.slice(), set: { hidden: true } }, { label: "Hide" });
    picks = [];
    sideKey = "";
    paint();
  }

  // ---- a small menu over the plan ------------------------------------------

  let menu = null;
  let shut = null;                // the anchor a press just closed a menu over, so pressing it again leaves it shut
  /**
   * A short list of choices under a button: [{ label, on, pick, swatch, key,
   * value, dot, sw, check, head, rule }]. `at` opens it by the pointer instead
   * (a right-click).
   */
  function openMenu(anchor, items, wide = false, at = null) {
    if (shut && anchor && shut.a === anchor && Date.now() - shut.t < 500) { shut = null; return; }
    closeMenu();
    const b = box();
    if (!b || (!anchor && !at)) return;
    const m = document.createElement("div");
    m.className = `planmenu${wide ? " wide" : ""}`;
    const right = (it) => (it.check ? `<span class="pmkey">✓</span>` : it.value !== undefined || it.dot !== undefined || it.sw
      ? `<span class="pmkey">${it.sw ? `<i class="pmsw" style="${esc(it.sw)}"></i>` : ""}${it.dot !== undefined ? `<i class="pmdot" style="${it.dot ? `background:${esc(it.dot)}` : "background:transparent"}"></i>` : ""}${esc(it.value || "")}</span>`
      : it.key ? `<span class="pmkey">${esc(it.key)}</span>` : "");
    m.innerHTML = items.map((it, i) => it.head ? `<div class="pmhead">${esc(it.head)}</div>`
      : it.rule ? `<hr class="pmrule">`
      : `<button type="button" data-pm="${i}"${it.on ? ` class="on"` : ""}${it.title ? ` title="${esc(it.title)}"` : ""}>${it.swatch ? `<i class="pmsw" style="${it.swatch}"></i>` : ""}<span>${esc(it.label)}</span>${right(it)}</button>`).join("");
    // On the page, not in the plan: the plan is drawn again whole when the
    // film is read after an edit, and a menu inside it would vanish.
    document.body.append(m);
    const vr = b.vp.getBoundingClientRect();
    const mh = m.offsetHeight, mw = m.offsetWidth;
    if (at) {
      m.style.left = `${Math.max(6, Math.min(at[0], window.innerWidth - mw - 8))}px`;
      m.style.top = `${Math.max(6, Math.min(at[1], window.innerHeight - mh - 8))}px`;
    } else {
      const ar = anchor.getBoundingClientRect();
      m.style.left = `${Math.max(vr.left + 6, Math.min(ar.left, vr.right - mw - 6))}px`;
      m.style.top = `${Math.max(vr.top + 6, ar.top - mh - 6)}px`;
    }
    m.querySelectorAll("[data-pm]").forEach((x) => x.addEventListener("click", () => { const it = items[Number(x.dataset.pm)]; closeMenu(); it.pick(); }));
    menu = m;
    menu.anchor = anchor;
    setTimeout(() => document.addEventListener("pointerdown", outside, true), 0);
    document.addEventListener("keydown", menuKey, true);
  }
  /** Escape closes a menu wherever the keys are: on the button that opened it, or in the slider. */
  function menuKey(ev) {
    if (ev.key !== "Escape" || !menu) return;
    ev.stopPropagation();
    closeMenu();
    const b = box();
    if (b) b.vp.focus({ preventScroll: true });
  }
  function outside(ev) {
    if (!menu || menu.contains(ev.target)) return;
    shut = menu.anchor && menu.anchor.contains && menu.anchor.contains(ev.target) ? { a: menu.anchor, t: Date.now() } : null;
    closeMenu();
  }
  function closeMenu() {
    if (menu) menu.remove();
    menu = null;
    document.removeEventListener("pointerdown", outside, true);
    document.removeEventListener("keydown", menuKey, true);
  }

  /** What the pieces wear between them: one colour ("" none), or null when they differ. */
  function mixedColour(els) {
    const now = new Set(els.map((x) => String(x.color || "").toUpperCase()));
    return now.size === 1 ? [...now][0] : null;
  }
  /** **One Colour for several** (his ask, 2026-10-17): every piece takes it, one step of undo; Mixed while they differ. */
  function colourMany(anchor, els) {
    const ids = els.map((x) => current(x.id));
    const one = mixedColour(els);
    const set = (c) => edit({ op: "update", ids, set: { color: c } }, { label: "Change Colour" });
    const items = [];
    if (one === null) items.push({ head: "Mixed" });
    items.push({ label: "None", on: one === "", pick: () => set("") });
    PALETTE.forEach((c, i) => items.push({ label: PALETTE_NAMES[i], swatch: `background:${c};border-color:${c}`, on: one === c.toUpperCase(), pick: () => set(c) }));
    items.push({ label: "Other Colour…", pick: () => otherColour(one || "", set) });
    openMenu(anchor, items, false, anchorAt(anchor));
  }
  /** The system's colour picker, for Other Colour…. */
  function otherColour(now, set) {
    const i = document.createElement("input");
    i.type = "color";
    i.value = /^#[0-9a-f]{6}$/i.test(now || "") ? now : "#888888";
    i.style.cssText = "position:fixed;left:-100px;top:0;opacity:0;pointer-events:none";
    document.body.append(i);
    i.addEventListener("change", () => { set(i.value); i.remove(); });
    setTimeout(() => i.remove(), 120000);
    i.click();
  }
  /** What can go between Set and Plot: anything but walls, doors, windows, openings, the street and people (`can_send`). */
  const canCross = (e) => Boolean(e) && !["wall", "door", "window", "opening", "road", "cast"].includes(e.kind);
  /** The view the pieces would go to: the other one from theirs, else from the one open. */
  function otherLayer(els) {
    const now = new Set(els.map((x) => x.layer || "plot"));
    const from = now.size === 1 ? [...now][0] : layer;
    return from === "set" ? "plot" : "set";
  }
  function sendLayer(els, copy) {
    const crossing = els.filter(canCross);
    if (!crossing.length) return;
    const to = otherLayer(crossing);
    const ids = crossing.map((x) => current(x.id));
    edit({ op: "send_layer", ids, to, copy }, { label: `${copy ? "Copy" : "Send"} to ${to === "set" ? "Set" : "Plot"}` });
    if (!copy) { picks = picks.filter((id) => !ids.includes(id) && !crossing.some((x) => x.id === id)); sideKey = ""; paint(); }
    toast(`${copy ? "Copied" : "Sent"} to ${to === "set" ? "Set" : "Plot"}`);
  }
  /** A person's colour, by character, for the whole project (his ask, 2026-10-17): every plan and the shot list's chips wear it. */
  function castWho(e) { return String((e && (e.cast || e.label)) || "").trim(); }
  function castColourNow(who) {
    const said = json(call("plan_cast", String(chosen()))) || {};
    const all = said.colours || {};
    const key = Object.keys(all).find((k) => k.toLowerCase() === who.toLowerCase());
    return key ? String(all[key]).toUpperCase() : "";
  }
  function setCastColour(who, c) {
    edit({ op: "cast_colour", name: who, color: c }, { label: `Colour for ${who}` });
    H.relook();
  }
  function castColourMenu(anchor, e) {
    const who = castWho(e);
    if (!who) return;
    const now = castColourNow(who);
    const items = [{ head: `Colour for ${who}` }];
    PALETTE.forEach((c, i) => items.push({ label: PALETTE_NAMES[i], swatch: `background:${c};border-color:${c}`, on: now === c.toUpperCase(), pick: () => setCastColour(who, c) }));
    items.push({ label: "Billing Order", title: "Back to the colour the cast list's order gives", pick: () => setCastColour(who, "") });
    items.push({ label: "Other Colour…", pick: () => otherColour(now, (c) => setCastColour(who, c)) });
    openMenu(anchor, items, false, anchorAt(anchor));
  }

  /** A colour: the film's palette, None where a piece may have none, and any other. */
  function colourMenu(anchor, e) {
    const id = () => current(e.id);
    const set = (c) => edit({ op: "update", ids: [id()], set: { color: c } }, { label: "Change Colour" });
    const items = [];
    if (CLEARABLE.has(e.kind) && !(isFrame(e))) items.push({ label: "None", on: !e.color, pick: () => set("") });
    PALETTE.forEach((c, i) => items.push({ label: PALETTE_NAMES[i], swatch: `background:${c};border-color:${c}`, on: String(e.color || "").toLowerCase() === c.toLowerCase(), pick: () => set(c) }));
    items.push({ label: "Other Colour…", pick: () => {
      const i = document.createElement("input");
      i.type = "color";
      i.value = /^#[0-9a-f]{6}$/i.test(e.color || "") ? e.color : "#888888";
      i.style.cssText = "position:fixed;left:-100px;top:0;opacity:0;pointer-events:none";
      document.body.append(i);
      i.addEventListener("change", () => { set(i.value); i.remove(); });
      setTimeout(() => i.remove(), 120000);
      i.click();
    } });
    openMenu(anchor, items);
  }

  /** A size: a share of the library's, points for words, a step up or down for the rest. */
  function sizeMenu(anchor, e) {
    const s = sizeInfo(e);
    if (!s) return;
    const id = () => current(e.id);
    const put = (set) => edit({ op: "update", ids: [id()], set }, { label: "Change Size" });
    if (s.how === "points") return openMenu(anchor, POINTS.map((n) => ({ label: `${n} pt`, on: Math.round(e.size || 0) === n, pick: () => put({ size: n }) })));
    if (s.how === "percent") return openMenu(anchor, PERCENTS.map((n) => ({ label: `${n}%`, on: s.pct === n, pick: () => put({ w: s.sym.w * n / 100, h: s.sym.h * n / 100 }) })));
    const w = e.w > 0 ? e.w : 1, h = e.h > 0 ? e.h : w;
    openMenu(anchor, [{ label: "Larger", pick: () => put({ w: w * 1.25, h: h * 1.25 }) }, { label: "Smaller", pick: () => put({ w: Math.max(w * 0.8, 0.05), h: Math.max(h * 0.8, 0.05) }) }]);
  }

  /**
   * **A zoom's focal length, a slider over the bar**: the short end of the
   * zoom, the slider, the long end, and where it is set. The film has one
   * focal length per shot, so the cone is drawn once it is let go (one
   * edit, one step back), as the Details panel's slider does.
   */
  function openFocal(anchor, e) {
    const c = (got.cams || []).find((x) => x.id === e.id);
    if (!c || !c.zoom || !(c.zoom[1] > c.zoom[0])) return;
    if (shut && shut.a === anchor && Date.now() - shut.t < 500) { shut = null; return; }
    closeMenu();
    const [lo, hi] = c.zoom;
    const now = Math.round(c.focal || lo);
    const p = document.createElement("div");
    p.className = "planpop";
    p.innerHTML = `<span class="pplo">${lo}mm</span><input type="range" data-pfocalpop="1" min="${lo}" max="${hi}" step="1" value="${now}" aria-label="Focal Length"><span class="pphi">${hi}mm</span><b class="ppnow">${now}mm</b>`;
    document.body.append(p);
    const vr = box().vp.getBoundingClientRect(), ar = anchor.getBoundingClientRect();
    p.style.left = `${Math.max(vr.left + 6, Math.min(ar.left + ar.width / 2 - p.offsetWidth / 2, vr.right - p.offsetWidth - 6))}px`;
    p.style.top = `${Math.max(vr.top + 6, ar.top - p.offsetHeight - 8)}px`;
    const range = p.querySelector("input"), out = p.querySelector(".ppnow");
    range.addEventListener("input", () => { out.textContent = `${range.value}mm`; });
    range.addEventListener("change", () => edit({ op: "camera_shot", id: current(e.id), set: { focal: Number(range.value) } }, { label: "Camera", record: false }));
    range.addEventListener("keydown", (ev) => {
      ev.stopPropagation();
      if (ev.key === "Enter") { closeMenu(); const b = box(); if (b) b.vp.focus({ preventScroll: true }); }
    });
    menu = p;
    menu.anchor = anchor;
    setTimeout(() => document.addEventListener("pointerdown", outside, true), 0);
    document.addEventListener("keydown", menuKey, true);
    range.focus({ preventScroll: true });
  }

  /**
   * **A Symbol and its Type, together** (Back to Paper, Batch 2): the eight
   * named marks with Film Light · Practical · Existing along the top, over
   * the bar. On a lamp (or a shared label's lamps) it re-marks them; on a
   * legend line, every lamp drawn with it (`legend` `{key, to}`).
   */
  function openSymbol(anchor, { ids, key, line = false }) {
    if (shut && shut.a === anchor && Date.now() - shut.t < 500) { shut = null; return; }
    closeMenu();
    const b = box();
    if (!b) return;
    const p = document.createElement("div");
    p.className = "plansym";
    let cur = lookOf(key);
    const first = el(ids[0]);
    const draw = () => {
      const type = first ? typeWord(el(first.id) || first) : "Film Light";
      p.innerHTML = `<div class="ptyperow">${["Film Light", "Practical", "Existing"].map((t) =>
        `<button type="button" class="ppill${t === type ? " on" : ""}" data-psymtype="${t}">${t}</button>`).join("")}</div>${markPicker(cur, "psym", true)}`;
      p.querySelectorAll("[data-psymtype]").forEach((x) => x.addEventListener("click", () => {
        const t = x.dataset.psymtype;
        const set = { existing: t === "Existing", practical: t === "Practical", mark_ink: "" };
        if (t === "Film Light") set.action = "";
        edit({ op: "update", ids: ids.map(current), set }, { label: "Type" });
        const now = el(first.id);
        if (now && now.look) cur = lookOf(now.look);
        draw();
      }));
      p.querySelectorAll("[data-psym]").forEach((x) => x.addEventListener("click", () => {
        const l = lookOf(x.dataset.psym);
        if (line) edit({ op: "legend", key, to: lookKey(l) }, { label: "Symbol" });
        else {
          const one = el(ids[0]);
          edit({ op: "update", ids: ids.map(current), set: { mark: l.mark, mark_ink: "", mark_fill: l.solid ? "solid" : "open", ...(one && TUBE_LEN[l.mark] && Math.max(one.w || 0, one.h || 0) < 0.4 ? { w: 0.3, h: TUBE_LEN[l.mark] } : {}) } }, { label: "Symbol" });
        }
        closeMenu();
      }));
      wireLetters(p);
    };
    draw();
    document.body.append(p);
    const vr = b.vp.getBoundingClientRect(), ar = anchor.getBoundingClientRect();
    p.style.left = `${Math.max(vr.left + 6, Math.min(ar.left, vr.right - p.offsetWidth - 6))}px`;
    p.style.top = `${Math.max(vr.top + 6, ar.top - p.offsetHeight - 8)}px`;
    menu = p;
    menu.anchor = anchor;
    setTimeout(() => document.addEventListener("pointerdown", outside, true), 0);
    document.addEventListener("keydown", menuKey, true);
  }

  /**
   * A number or a length typed over the bar — Count, a wall's Length, a
   * door's Width: one field, Return keeps it, Escape leaves it.
   */
  function askValue(anchor, { label, value, len = false, apply }) {
    if (shut && shut.a === anchor && Date.now() - shut.t < 500) { shut = null; return; }
    closeMenu();
    const b = box();
    if (!b) return;
    const p = document.createElement("div");
    p.className = "planpop";
    p.innerHTML = `<span class="pplo">${esc(label)}</span><input type="text" class="ppval" value="${esc(value)}" aria-label="${esc(label)}">`;
    document.body.append(p);
    const vr = b.vp.getBoundingClientRect(), ar = anchor.getBoundingClientRect();
    p.style.left = `${Math.max(vr.left + 6, Math.min(ar.left, vr.right - p.offsetWidth - 6))}px`;
    p.style.top = `${Math.max(vr.top + 6, ar.top - p.offsetHeight - 8)}px`;
    const input = p.querySelector("input");
    input.addEventListener("keydown", (ev) => {
      ev.stopPropagation();
      if (ev.key !== "Enter") return;
      const v = len ? parseLength(input.value) : parseFloat(input.value);
      closeMenu();
      const nb = box();
      if (nb) nb.vp.focus({ preventScroll: true });
      if (v !== null && Number.isFinite(v)) apply(v);
    });
    menu = p;
    menu.anchor = anchor;
    setTimeout(() => document.addEventListener("pointerdown", outside, true), 0);
    document.addEventListener("keydown", menuKey, true);
    input.focus({ preventScroll: true });
    input.select();
  }

  /** The gear the plan uses, counted as the sheet counts it (`sheet::gear`): legend names times Count, frames by size, grip. */
  function gearText() {
    const sh = sheetOf();
    const groups = new Map();
    for (const g of (sh && sh.gear) || []) {
      if (!groups.has(g.group)) groups.set(g.group, []);
      groups.get(g.group).push(`${g.count} × ${g.name}`);
    }
    return [...groups].map(([t, lines]) => [t, ...lines].join("\n")).join("\n\n");
  }
  async function copyGear() {
    const text = gearText();
    if (!text) return toast("No gear on the plan");
    try { await navigator.clipboard.writeText(text); toast("Gear List copied"); } catch { toast("The browser would not copy", true); }
  }

  function action(what, anchor) {
    const line = legendPicked();
    const els = picks.map(el).filter(Boolean);
    const ids = els.map((e) => e.id);
    if (!ids.length) return;
    const e = els[0];
    // What a lamp's own words reach: a lamp, the lead lamp of a shared label, or a legend line's first.
    const shared = isShared(e) ? e : canShare(e) ? labelOf(e) : null;
    const lamp = isLamp(e) ? e : shared ? heldBy(shared.id).find(isLamp) || null : null;
    const lampIds = line && line.kind === "legend" ? ids : shared && els.length === 1 ? heldBy(shared.id).map((x) => x.id) : els.filter(isLamp).map((x) => x.id);
    const upd = (set, label, on = [e.id]) => edit({ op: "update", ids: on.map(current), set }, { label });
    if (what === "more") return openMore(anchor);
    if (what === "ownlabelall") return edit({ op: "own_label", ids: els.filter(canShare).map((x) => x.id) }, { label: "Own Label" });
    if (what === "colourall") return colourMany(anchor, els);
    if (what === "sendlayer" || what === "copylayer") return sendLayer(els, what === "copylayer");
    if (what === "castcolour") return castColourMenu(anchor, e);
    if (what === "details") { tab = "details"; sideKey = ""; return paint(); }
    if (what === "delete") return remove(ids);
    if (what === "duplicate") return duplicate(ids);
    if (what === "lock") return lockPicks();
    if (what === "hide") return hidePicks();
    if (["front", "back", "forward", "backward"].includes(what)) return edit({ op: "order", ids, to: what }, { label: "Arrange" });
    if (what === "cut" || what === "copy") return copyPicks(what === "cut");
    if (what === "paste") return paste();
    if (what === "rot90" || what === "rot-90") return turnPickBy(what === "rot90" ? 90 : -90);
    if (what === "flipx" || what === "flipy") return edit({ op: "flip", ids, axis: what === "flipx" ? "x" : "y" }, { label: "Flip" });
    if (what === "arrange") {
      return openMenu(anchor, [
        { label: "Bring to Front", key: "⌥⌘]", pick: () => action("front", anchor) },
        { label: "Bring Forward", key: "⌘]", pick: () => action("forward", anchor) },
        { label: "Send Backward", key: "⌘[", pick: () => action("backward", anchor) },
        { label: "Send to Back", key: "⌥⌘[", pick: () => action("back", anchor) },
        { rule: true },
        { label: "Rotate 90° Right", key: "⌘R", pick: () => action("rot90", anchor) },
        { label: "Rotate 90° Left", key: "⇧⌘R", pick: () => action("rot-90", anchor) },
        { label: "Flip Horizontal", key: "⇧H", pick: () => action("flipx", anchor) },
        { label: "Flip Vertical", key: "⇧V", pick: () => action("flipy", anchor) },
      ], true, anchorAt(anchor));
    }
    if (what === "favs") {
      // Into one of the nine slots; a whole group is kept as one favorite.
      const slots = favSlots();
      const src = { ...e };
      for (const k of ["name", "show", "at", "emits", "groupName"]) delete src[k];
      return openMenu(anchor, Array.from({ length: 9 }, (_, i) => ({ label: `${i + 1}  ${slots[i] ? slots[i].name : "Empty"}`, pick: () => {
        edit({ op: "favorite", slot: i, el: src }, { label: "Add to Favorites", record: false });
        toast(`Kept in slot ${i + 1}`);
      } })), true, anchorAt(anchor));
    }
    if (what === "pathkind") {
      const now = e.kind === "wall" ? "wall" : e.fill && e.closed ? "object" : "line";
      return openMenu(anchor, [["line", "Line"], ["wall", "Wall"], ["object", "Object"]].map(([v, n]) => ({ label: n, on: now === v, pick: () => edit({ op: "path_as", id: e.id, as: v }, { label: "Kind" }) })), false, anchorAt(anchor));
    }
    if (what === "pathfill") {
      const on = e.kind === "wall" ? Boolean(e.fill_color) : Boolean(e.fill);
      if (e.kind === "wall") return upd({ fill_color: on ? "" : "auto" }, "Fill");
      return upd(on ? { fill: false, fill_color: "" } : { fill: true }, "Fill");
    }
    if (what === "labelsall") {
      const named = els.filter(hasName);
      const hidden = named.every((x) => x.label_hidden);
      return upd({ label_hidden: !hidden }, hidden ? "Show Label" : "Hide Label", named.map((x) => x.id));
    }
    if (what === "showinlist") return H.showShot(e.shot);
    if (what === "send") { copyPanel = { ids, mode: "add", ticked: new Set() }; return float(); }
    if (what === "group") return edit({ op: "group", ids }, { label: "Group" });
    if (what === "ungroup") return edit({ op: "ungroup", ids }, { label: "Ungroup" });
    if (what === "join") { edit({ op: "wall_join", ids }, { label: "Join" }); picks = picks.filter((id) => el(id)); sideKey = ""; return paint(); }
    if (what === "align") {
      return openMenu(anchor, [["left", "Left"], ["hcentre", "Centre"], ["right", "Right"], ["top", "Top"], ["vcentre", "Middle"], ["bottom", "Bottom"]]
        .map(([to, n]) => ({ label: n, pick: () => edit({ op: "align", ids, to }, { label: "Align" }) })));
    }
    if (what === "spacex" || what === "spacey") return edit({ op: "distribute", ids, axis: what === "spacex" ? "x" : "y" }, { label: "Space Evenly" });
    // ---- the lighting plot: Symbol, Name, Count, Note, Gel, Off, Share Label
    if (what === "symbol") {
      if (line && line.kind === "legend") return openSymbol(anchor, { ids, key: e.legend_key || e.look || line.key, line: true });
      if (lamp) return openSymbol(anchor, { ids: [lamp.id], key: lamp.look });
      return;
    }
    if (what === "name") {
      if (line && line.kind === "legend") return typeOn(el(line.ids[0]), "name");
      if (lamp) return typeOn(lamp, "name");
      // A frame's Name is what he types (2026-10-17), never its size or cloth.
      if (isFrame(e)) return typeOn(e, "name");
      return typeOn(e, "label");
    }
    if (what === "note") return lamp ? typeOn(lamp, "note") : isFrame(e) ? typeOn(e, "note") : undefined;
    if (what === "caption") return typeOn(e, "caption");
    if (what === "words") return typeOn(e, "text");
    if (what === "count") {
      const now = Math.max(1, e.count || 1);
      const put = (n) => upd({ count: Math.max(1, Math.min(999, Math.round(n))) }, "Count");
      return openMenu(anchor, [...[1, 2, 3, 4, 5, 6, 8, 10, 12].map((n) => ({ label: String(n), on: n === now, pick: () => put(n) })), { rule: true },
        { label: "Other…", pick: () => askValue(anchor, { label: "Count", value: String(now), apply: put }) }]);
    }
    if (what === "gel") {
      // The gels on these lamps, ticked; a tap adds or takes one off them all.
      const on = lampIds.length ? lampIds : ids;
      const have = new Set((el(on[0]) || {}).gels || []);
      // By section, as the Mac's menu has them, with No Gel first.
      const items = [{ label: "No Gel", check: !have.size, pick: () => upd({ gels: [] }, "Remove Gel", on) }];
      for (const [head, gels] of gelGroups()) {
        items.push({ head });
        for (const g of gels) items.push({ label: g.name, check: have.has(g.id), pick: () => {
          const next = have.has(g.id) ? [...have].filter((x) => x !== g.id) : [...have, g.id];
          upd({ gels: next }, have.has(g.id) ? "Remove Gel" : "Add Gel", on);
        } });
      }
      return openMenu(anchor, items, true);
    }
    if (what === "off") {
      const target = lamp || e;
      return upd({ action: target.action === "off" ? "" : "off" }, target.action === "off" ? "On" : "Off", [target.id]);
    }
    if (what === "type") {
      const now = typeWord(e);
      return openMenu(anchor, ["Film Light", "Practical", "Existing"].map((t) => ({ label: t, on: t === now, pick: () => {
        const set = { existing: t === "Existing", practical: t === "Practical", mark_ink: "" };
        if (t === "Film Light") set.action = "";
        upd(set, "Type", lampIds.length ? lampIds : ids);
      } })));
    }
    if (what === "down") {
      const on = lampIds.length ? lampIds : [e.id];
      const was = pointsDown(el(on[0]));
      return upd({ tilt: was ? 90 : 0 }, "Down", on);
    }
    if (what === "height") {
      const on = lampIds.length ? lampIds : [e.id];
      const now = (el(on[0]) || {}).height || "";
      const hs = (got && got.settings && got.settings.units) === "m" ? ["2 m", "2.5 m", "3 m", "3.5 m", "4 m", "5 m", "6 m"] : ["6'", "7'", "8'", "9'", "10'", "12'", "14'", "16'", "20'"];
      return openMenu(anchor, [...hs.map((h) => ({ label: h, on: h === now, pick: () => upd({ height: h }, "Height", on) })), { rule: true },
        { label: "None", on: !now, pick: () => upd({ height: "" }, "Height", on) },
        { label: "Other…", pick: () => askValue(anchor, { label: "Height", value: now, apply: (v) => upd({ height: String(v).trim() }, "Height", on) }) }]);
    }
    if (what === "sharednote") {
      const held = shared ? heldBy(shared.id) : [];
      if (!held.length) return;
      const lead = held[0];
      return typeOn(lead, noteField(lead));
    }
    if (what === "sharelabel") {
      const pieces = els.filter(canShare).map((x) => x.id);
      const made = edit({ op: "share_label", ids: line && line.kind === "legend" ? lampIds : pieces.length ? pieces : ids }, { label: "Share Label" });
      legendPick = null;
      if (made && made[0]) { picks = [made[0]]; sideKey = ""; paint(); }
      return;
    }
    if (what === "ownlabel") return edit({ op: "own_label", ids: [e.id] }, { label: "Own Label" });
    if (what === "spread") {
      const was = e.spread || "";
      return openMenu(anchor, [["", "One"], ["line", "Line"], ["ring", "Ring"]].map(([v, n]) => ({ label: n, on: v === was, pick: () => {
        if (v === was) return;
        const set = { spread: v };
        if (v === "line") Object.assign(set, { w: 0.3, h: Math.max(e.h || 0, 3), curve: 0, count: Math.max(e.count || 1, 6) });
        if (v === "ring") Object.assign(set, { w: 3, h: 3, count: Math.max(e.count || 1, 8) });
        if (v === "") Object.assign(set, { w: 0.3, h: 0.3, curve: 0 });
        upd(set, "Spread");
      } })));
    }
    if (what === "swap") return openSwap(e.id);
    if (what === "hidelabel") {
      const t = shared || e;
      return upd({ label_hidden: !t.label_hidden }, t.label_hidden ? "Show Label" : "Hide Label", [t.id]);
    }
    if (what === "resetlabel") return upd({ label_dx: 0, label_dy: 0, label_size: 0 }, "Reset Label");
    if (what === "stopaim") return upd({ aim: "" }, "Stop Aiming");
    if (what === "gearlist") return copyGear();
    if (what === "hidelegend") return setting("legend", false);
    // ---- a camera
    if (what === "shotpick") {
      const here = shotsOfScene();
      const items = here.map((r) => ({ label: `${r.number}${r.title || r.description ? ` · ${String(r.title || r.description).slice(0, 36)}` : ""}`, on: r.shot === e.shot, pick: () => upd({ shot: r.shot }, "Shot") }));
      items.push({ rule: true }, { label: "New Shot", pick: () => doThing("newshot", e) });
      if (e.shot) items.push({ label: "Show in Shot List", pick: () => H.showShot(e.shot) }, { label: "Unlink", pick: () => upd({ shot: "" }, "Unlink") });
      return openMenu(anchor, items, true);
    }
    if (what === "cone") return upd({ cone: !e.cone }, "Lens Cone");
    if (what === "framepic") return upd({ frame_on: !e.frame_on }, "Frame on Plan");
    if (what === "ride") return edit({ op: "ride", id: e.id }, { label: "Ride Track" });
    if (what === "unlock") return upd({ rig_on: "" }, "Unlock");
    if (what === "colour") return colourMenu(anchor, e);
    if (what === "size") return sizeMenu(anchor, e);
    if (what === "focal") return openFocal(anchor, e);
    // ---- a frame
    if (what === "framesize") {
      const now = frameSize(e);
      return openMenu(anchor, FRAME_SIZES.map(([a, b2]) => ({ label: `${a}×${b2}`, on: now === `${a}×${b2}`, pick: () => upd({ h: a * 0.3048, tall: b2 * 0.3048 }, "Frame Size") })));
    }
    if (what === "lean") return openMenu(anchor, LEANS.map(([v, n]) => ({ label: n, on: Math.round(Number(e.tilt) || 0) === v, pick: () => upd({ tilt: v }, "Lean") })));
    // ---- a person, words, a set piece
    if (what === "castname") {
      // Who it is: a name off the film's cast is its name and its character (the Mac's), or typed.
      const who = castNames();
      const names = [...who.scene, ...who.film.filter((n) => !who.scene.includes(n))];
      const items = names.length ? names.map((n) => ({ label: n, on: n === e.cast, pick: () => upd({ cast: n, label: n }, "Name") })) : [{ label: "No Cast", pick: () => {} }];
      items.push({ rule: true }, { label: "Type a Name", pick: () => typeOn(e, "label") });
      return openMenu(anchor, items, true);
    }
    if (what === "roadkind") return openMenu(anchor, ROAD_KINDS.map(([n, w]) => ({ label: n, on: Math.abs((e.thick || 0) - w) < 0.05, pick: () => upd({ thick: w }, "Kind") })));
    if (what === "smooth" && pickedCorner !== null) return edit({ op: "wall_smooth", id: e.id, corner: pickedCorner, smooth: !isSmooth(e, pickedCorner) }, { label: isSmooth(e, pickedCorner) ? "Sharp Corner" : "Smooth Corner" });
    if (what === "pose") return openMenu(anchor, Object.entries(POSES).map(([v, n]) => ({ label: n, on: (e.pose || "standing") === v, pick: () => upd({ pose: v }, "Pose") })));
    if (what === "larger" || what === "smaller") {
      const w = e.w > 0 ? e.w : 1, h = e.h > 0 ? e.h : w, k = what === "larger" ? 1.25 : 0.8;
      return upd({ w: Math.max(w * k, 0.05), h: Math.max(h * k, 0.05) }, "Change Size");
    }
    if (what === "regular" || what === "large") return upd({ size: what === "large" ? WORDS_LARGE : WORDS_REGULAR, bold: false }, "Size");
    if (what === "textalign") return openMenu(anchor, [["left", "Left"], ["", "Centre"], ["right", "Right"]].map(([v, n]) => ({ label: n, on: (e.align || "") === v || (!v && e.align === "centre"), pick: () => upd({ align: v }, "Align") })));
    if (what === "fill") return upd({ fill: !e.fill }, "Fill");
    // ---- walls, doors, lines
    if (what === "walllength") {
      const s = pickedStretch ?? (wallCorners(e).length === 2 ? 0 : null);
      if (s === null) { tab = "details"; sideKey = ""; return paint(); }
      return askValue(anchor, { label: "Length", value: lengthText(stretchShown(e, s)), len: true, apply: (v) => edit({ op: "wall_length", id: current(e.id), stretch: s, length: Math.max(v, 0.05) }, { label: "Length" }) });
    }
    if (what === "width") return askValue(anchor, { label: "Width", value: lengthText(e.w || 0), len: true, apply: (v) => upd({ w: Math.max(v, 0.05) }, "Width") });
    if (what === "gauge") return askValue(anchor, { label: "Gauge", value: lengthText(e.thick || 0), len: true, apply: (v) => upd({ thick: Math.max(v, 0.05) }, "Gauge") });
    if (what === "doorshut" || what === "doorhalf" || what === "dooropen") return upd({ swing: { doorshut: 0, doorhalf: 45, dooropen: 90 }[what] }, "Swing");
    if (what === "hinge") return upd({ hinge: e.hinge === "right" ? "" : "right" }, "Flip");
    if (what === "side") return upd({ flip: !e.flip }, "Flip Side");
    if (what === "sliding") return upd(doorChange(e, e.slide ? "swing" : "sliding"), "Style");
    if (what === "doorkind") {
      const now = doorKind(e);
      return openMenu(anchor, DOOR_KINDS.map(([v, n]) => ({ label: n, on: now === v, pick: () => upd(doorChange(e, v), "Style") })), false, anchorAt(anchor));
    }
    if (what === "under") return upd({ under: !e.under }, "Behind Everything");
    if (what === "heads") return openMenu(anchor, [["end", "One"], ["both", "Both"], ["none", "None"]].map(([v, n]) => ({ label: n, on: (e.head || "end") === v, pick: () => upd({ head: v }, "Heads") })));
    if (what === "dash") return openMenu(anchor, [["", "Solid"], ["dashed", "Dashed"], ["dotted", "Dotted"]].map(([v, n]) => ({ label: n, on: (e.dash || "") === v, pick: () => upd({ dash: v }, "Line") })));
    // The Mac's four weights (DiagramMenu); one set some other way still shows, ticked.
    if (what === "weight") { const now = Number(e.weight || 1.5); const list = [0.8, 1.2, 2, 3]; if (!list.some((n) => Math.abs(n - now) < 0.05)) list.push(now); return openMenu(anchor, list.sort((a2, b2) => a2 - b2).map((n) => ({ label: `${n} pt`, on: Math.abs(now - n) < 0.05, pick: () => upd({ weight: n }, "Weight") }))); }
    if (what === "fade") return openMenu(anchor, [100, 85, 70, 50, 30].map((n) => ({ label: `${n}%`, on: Math.round((e.opacity ?? 1) * 100) === n, pick: () => upd({ opacity: n / 100 }, "Change Opacity") })));
    if (what === "setscale") { calibrating = e.id; toast("Drag across a known length"); return; }
    if (what === "drawon") return drawOnPhoto(e.id);
    if (what === "attachmarks") return attachMarks(e.id);
    if (what === "showas") return openMenu(anchor, [["", "Background"], ["photo", "Photo"]].map(([v, n]) => ({ label: n, on: (e.role === "photo" ? "photo" : "") === v, pick: () => upd({ role: v, opacity: v === "photo" ? 1 : 0.85 }, "Show As") })));
    if (what === "thick") {
      return openMenu(anchor, wallThicknesses().map((t, i) => ({ label: THICK_NAMES[i], on: Math.abs((e.thick || 0) - t) < 0.002, pick: () => upd({ thick: t }, "Thickness") })));
    }
    if (what === "lockto" || what === "unlockmarker" || what === "deletemarker") {
      const c = wallCorners(e)[pickedCorner];
      if (!c) return;
      if (what === "deletemarker") { edit({ op: "wall_remove_corner", id: e.id, corner: pickedCorner }, { label: "Delete Marker" }); pickedCorner = null; pickedStretch = null; sideKey = ""; return paint(); }
      if (what === "unlockmarker") return edit({ op: "wall_corner", id: e.id, corner: pickedCorner, x: c[0], y: c[1], on: "" }, { label: "Unlock Marker" });
      // Every piece that can be stood on, by name: its marker then follows it.
      const pieces = (got.els || []).filter((t) => !LINE_KINDS.has(t.kind) && !["cable", "stroke", "image", "text", "note", "shape"].includes(t.kind) && !t.hidden);
      const now = (e.pins || [])[pickedCorner] || "";
      return openMenu(anchor, pieces.length ? pieces.map((t) => ({ label: t.name || word(t.kind), on: t.id === now, pick: () => edit({ op: "wall_corner", id: e.id, corner: pickedCorner, x: c[0], y: c[1], on: t.id }, { label: "Lock Marker" }) })) : [{ label: "Nothing to Lock To", pick: () => {} }], true);
    }
    if (what === "break") { edit({ op: "wall_break", id: e.id, corner: pickedCorner }, { label: "Break" }); pickedCorner = null; picks = [e.id]; sideKey = ""; return paint(); }
    if (what === "curve") return edit({ op: "wall_round", id: e.id, corner: pickedCorner, round: !(e.round || []).includes(pickedCorner) }, { label: "Round" });
    if (what === "deletecorner") { edit({ op: "wall_remove_corner", id: e.id, corner: pickedCorner }, { label: "Delete Corner" }); pickedCorner = null; pickedStretch = null; sideKey = ""; return paint(); }
    if (what === "lens" || what === "cam") {
      // Off the film's own lists — written to the shot (`camera_shot`).
      const cam = (got.cams || []).find((c) => c.id === e.id) || {};
      const items = what === "lens"
        ? (got.lenses || []).map((v) => ({ label: v, on: v === cam.lens, pick: () => edit({ op: "camera_shot", id: current(e.id), set: { lens: v } }, { label: "Lens", record: false }) }))
        : (got.filmCams || []).map((u) => ({ label: u.label, on: u.id === cam.unit, pick: () => edit({ op: "camera_shot", id: current(e.id), set: { unit: u.id } }, { label: "Camera", record: false }) }));
      return openMenu(anchor, items.length ? items : [{ label: what === "lens" ? "No Lenses" : "No Cameras", pick: () => {} }], true);
    }
    if (what === "material") {
      // A frame's skin, by its swatch — the binding colours, the checkerboards, a gel.
      const F = library().frames || {};
      const now = e.material || F.default;
      const items = [];
      let group = "";
      for (const m of F.materials || []) {
        if (m.group && m.group !== group) { group = m.group; items.push({ head: group }); }
        // Gel as the skin: a clear frame in a gel's colour — pick which (the Mac's).
        if (m.id === "gel") items.push({ label: now === "gel" && (e.gels || [])[0] ? `Gel · ${gelName(e.gels[0])}` : m.name, on: m.id === now, swatch: matSwatch(m), pick: () => openMenu(anchor, gelGroups().flatMap(([head, gels]) => [{ head }, ...gels.map((g) => ({ label: g.name, on: now === "gel" && (e.gels || [])[0] === g.id, pick: () => upd({ material: "gel", gels: [g.id] }, "Material") }))]), true) });
        else items.push({ label: m.name, on: m.id === now, swatch: matSwatch(m), pick: () => upd({ material: m.id }, "Material") });
      }
      return openMenu(anchor, items, true);
    }
  }

  // ---- typing on the plan ----------------------------------------------------
  //
  // **Typing happens on the plan** (his call F, Back to Paper, Batch 2): a
  // lamp's Name and Note, a piece's name and Words are typed in the words
  // themselves, where the plan draws them — their size, their capitals,
  // their ink — with no box round them and no Cancel or Done. Return or a
  // click away keeps it; Escape leaves it as it was.

  let typing = null;              // what is being typed on the plan: { id, line }

  /** Whether Return types on a piece: a lamp's Note, Words, or a name typed rather than given (a shot's number, a character's name). */
  function renamable(e) {
    if (!e) return false;
    if (e.kind === "light" || e.kind === "set" || e.kind === "text" || e.kind === "note") return true;
    if (e.kind === "camera") return !e.shot;
    if (e.kind === "cast") return !e.cast;
    return ["wall", "track", "road", "arrow", "measure", "shape", "cable"].includes(e.kind);
  }
  /** Return on one picked piece: a lamp's Note, Words' words, else its name. */
  function startRename(e) {
    if (isShared(e)) { const lead = heldBy(e.id)[0]; return typeOn(lead, noteField(lead)); }
    if (isLamp(e)) return typeOn(e, "note");
    if (isFrame(e)) return typeOn(e, "note");
    if (e.kind === "text" || e.kind === "note") return typeOn(e, "text");
    return typeOn(e, "label");
  }



  /** The words a field is drawn in on the plan, and which of its lines. */
  function drawnWords(e, field) {
    const b = box();
    const svg = b && b.vp.querySelector(".planpic > svg");
    if (!svg) return null;
    const host = canShare(e) && labelOf(e) ? labelOf(e) : e;
    const q = String(host.id).replace(/["\\]/g, "\\$&");
    const text = svg.querySelector(`text[data-el="${q}"][data-part="label"]`) || ((host.kind === "text" || host.kind === "note") ? svg.querySelector(`text[data-el="${q}"]`) : null);
    if (!text) return { svg, text: null, line: null, host };
    const spans = [...text.querySelectorAll("tspan")];
    // A lamp's label: its Name over its Note; either may be missing.
    if (field === "name" || field === "note" || (field === "caption" && isShared(host))) {
      const [first, under] = isShared(host) ? [true, spans.length > 1] : [Boolean((e.label_lines || [])[0]), Boolean((e.label_lines || [])[1])];
      const lines = spans.length ? spans : [text];
      if (field === "name") return { svg, text, line: first ? lines[0] : null, host, near: first ? null : lines[0], above: !first };
      return { svg, text, line: under ? lines[first ? 1 : 0] || null : null, host, near: under ? null : lines[0], above: false };
    }
    // Any piece's own Note: its second line, or a new one under its name.
    if (field === "caption") {
      const lines = spans.length ? spans : [text];
      const has = Boolean(e.caption);
      const name = Boolean(e.label) || lines.length > (has ? 1 : 0);
      if (has) return { svg, text, line: lines[name ? Math.min(1, lines.length - 1) : 0], host };
      return { svg, text, line: null, host, near: lines[lines.length - 1], above: false };
    }
    return { svg, text, line: text, host };
  }

  function typeOn(e, field, { only = false } = {}) {
    if (!e || !editor()) return;
    closeMenu();
    endTyping(true);
    const b = box();
    const where = drawnWords(e, field);
    if (!b || !where) return;
    const vr = b.vp.getBoundingClientRect();
    const svgBox = where.svg.getBoundingClientRect();
    const k = svgBox.width / (Number(where.svg.getAttribute("width")) || svgBox.width || 1);
    const size = where.text ? (parseFloat(where.text.getAttribute("font-size")) || 10) * k : 10;
    let cx, cy, ink = "#17171A";
    const anchorOf = where.line || where.near || where.text;
    if (anchorOf) {
      const r = anchorOf.getBoundingClientRect();
      cx = r.left + r.width / 2; cy = r.top + r.height / 2;
      if (!where.line && where.near) cy += (where.above ? -1 : 1) * size * 1.2;
      if (where.line) ink = getComputedStyle(where.line).fill || ink;
    } else {
      // Nothing drawn yet: just under the piece, where its label will stand.
      const [ax, ay] = e.at || [e.x, e.y];
      const [px, py] = storedToBox(ax, ay);
      cx = vr.left + px; cy = vr.top + py + 22;
    }
    if ((field === "note" || field === "caption") && !where.line) ink = "#5A5A61";
    const now = field === "caption" ? (e.caption || "") : field === "name" ? (e.lamp_name || "") : field === "note" ? (e.label || "") : field === "text" ? (e.text || "") : (e.label || "");
    const words = field === "text";
    // Several lines, as typed (2026-10-17): Shift-Return adds one. A lamp's
    // Name keeps its list of lights while it is one line.
    const listed = field === "name" && isLamp(e) && !now.includes("\n");
    const input = document.createElement(listed ? "input" : "textarea");
    if (input.tagName === "INPUT") input.type = "text";
    // In the plan's capitals when the plan writes them so (labels always; Words as drawn).
    const caps = Boolean(settings().caps) && (!words || Boolean(where.text && /[A-Z]/.test(where.text.textContent) && where.text.textContent === where.text.textContent.toUpperCase()));
    input.className = `plantype${caps ? " caps" : ""}`;
    input.value = now;
    input.setAttribute("aria-label", { name: "Name", note: "Note", caption: "Note", text: "Words", label: "Name" }[field] || "Name");
    if (field === "name" && isLamp(e)) {
      // The light library's names, offered as he types.
      let list = document.getElementById("plantypenames");
      if (!list) { list = document.createElement("datalist"); list.id = "plantypenames"; document.body.append(list); }
      list.innerHTML = lightNames().map((n) => `<option value="${esc(n)}">`).join("");
      input.setAttribute("list", "plantypenames");
    }
    const align = words && where.text ? where.text.getAttribute("text-anchor") : "middle";
    input.style.cssText = `left:${cx}px;top:${cy}px;font-size:${Math.max(size, 9)}px;color:${ink};text-align:${align === "start" ? "left" : align === "end" ? "right" : "center"};`
      + `transform:translate(${align === "start" ? "0" : align === "end" ? "-100%" : "-50%"},-50%)`;
    if (input.tagName === "TEXTAREA") { input.rows = now.split("\n").length; input.addEventListener("input", () => { input.rows = input.value.split("\n").length; }); }
    document.body.append(input);
    const fit = () => {
      const c = fit.c || (fit.c = document.createElement("canvas").getContext("2d"));
      c.font = `${getComputedStyle(input).fontWeight} ${input.style.fontSize} ${getComputedStyle(input).fontFamily}`;
      const longest = (input.value || " ").split("\n").map((l) => c.measureText(caps ? l.toUpperCase() : l).width).reduce((a, x) => Math.max(a, x), 0);
      input.style.width = `${Math.max(longest + size * 1.4, 36)}px`;
    };
    fit();
    typing = { id: where.host.id, el: e.id, field, line: where.line ? [...where.text.querySelectorAll("tspan")].indexOf(where.line) : -2 };
    hideTyped();
    input.focus();
    input.select();
    let over = false;
    const done = (keep) => {
      if (over) return;
      over = true;
      typing = null;
      input.remove();
      hideTyped();
      const nb = box();
      if (nb) nb.vp.focus({ preventScroll: true });
      const v = words ? input.value.replace(/\s+$/, "") : input.value.trim();
      if (!keep || v === now) return;
      const id = current(e.id);
      if (field === "name" && (isLamp(e) || isFrame(e))) edit({ op: "name_piece", id, name: v, only }, { label: "Name" });
      else if (field === "caption") edit({ op: "update", ids: [id], set: { caption: v } }, { label: "Note" });
      else if (field === "note") edit({ op: "update", ids: [id], set: { label: v } }, { label: "Note" });
      else if (field === "text") edit({ op: "update", ids: [id], set: { text: v || now } }, { label: "Words" });
      else edit({ op: "update", ids: [id], set: { label: v } }, { label: "Name" });
    };
    typing.done = done;
    input.addEventListener("input", fit);
    input.addEventListener("keydown", (ev) => {
      ev.stopPropagation();
      if (ev.key === "Enter" && !(input.tagName === "TEXTAREA" && ev.shiftKey)) { ev.preventDefault(); done(true); }
      if (ev.key === "Escape") done(false);
    });
    input.addEventListener("pointerdown", (ev) => ev.stopPropagation());
    input.addEventListener("blur", () => done(true));
  }
  /** What is being typed over is not drawn twice: its line on the plan steps out while the words are typed. */
  function hideTyped() {
    const svg = root.querySelector(".planpic > svg");
    if (!svg) return;
    svg.querySelectorAll(".typing").forEach((n) => n.classList.remove("typing"));
    if (!typing) return;
    const q = String(typing.id).replace(/["\\]/g, "\\$&");
    const text = svg.querySelector(`text[data-el="${q}"][data-part="label"]`) || svg.querySelector(`text[data-el="${q}"]`);
    if (!text) return;
    const spans = [...text.querySelectorAll("tspan")];
    if (typing.line >= 0 && spans[typing.line]) spans[typing.line].classList.add("typing");
    else if (typing.line === -1 || (typing.line === 0 && !spans.length)) text.classList.add("typing");
  }
  function endTyping(keep) {
    if (typing && typing.done) typing.done(keep);
    document.querySelectorAll(".plantype").forEach((n) => n.remove());
  }

  // ------------------------------------------------------------ play

  function playToggle() {
    if (play) return stop();
    const last = got ? Math.max(1, got.lastBeat) : 1;
    if (last <= 1) return;
    if (H.beat() >= last) H.setBeat(1);
    play = { from: H.beat(), t0: performance.now(), frame: 0 };
    const still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const tick = (now) => {
      if (!play || H.mode() !== "diagrams") return stop(false);
      const gone = (now - play.t0) / BEAT_MS;
      const beat = play.from + Math.floor(gone);
      if (beat >= last) { H.setBeat(last); tween = 0; play = null; paint(); return; }
      H.setBeat(beat);
      tween = still ? 0 : gone - Math.floor(gone);
      if (!live && !drag) paint();
      play.frame = requestAnimationFrame(tick);
    };
    play.frame = requestAnimationFrame(tick);
    paint();
  }
  function stop(again = true) {
    if (play && play.frame) cancelAnimationFrame(play.frame);
    play = null;
    tween = 0;
    if (again) paint();
  }

  // ------------------------------------------------------------ editing

  /**
   * **Make an edit**: here at once, then to the server. `label` names it in
   * Undo. Answers the ids of pieces it made (the page's own, until the server
   * says which ids the film gave them).
   */
  function edit(op, { label = "", select = false, record = true, join = false, burst = "", on = null } = {}) {
    if (!editor()) return [];
    // `on`: another diagram than the one open (a scene's tab menu acts on its scene).
    const scene = String(on || chosen());
    const said = made(scene, op);
    if (!said || said.error) { toast(said && said.error ? said.error : "That did not work"); return []; }
    rev++;
    hold();
    // What goes to the film names its pieces by the film's ids, and says
    // what it was in his words — kept beside a link visitor's edits.
    pending.push({ scene, op: fwd(op), made: said.made || [], label: label || op.op });
    if (reading) reading.push({ scene, op: fwd(replayable(op, said.made)) });
    said.undo = fwd(said.undo || []);
    if (record && said.undo && said.undo.length) {
      const last = undos[undos.length - 1];
      // `join`: the same gesture as the edit before (a corner added, then
      // dragged); `burst`: a run of key presses — either is one step back.
      const same = last && last.scene === scene && (join || (burst && last.burst === burst && Date.now() - last.at < 1200));
      if (same) { last.ops = [...said.undo, ...last.ops]; last.at = Date.now(); }
      else undos.push({ scene, ops: said.undo, label: label || op.op, burst, at: Date.now() });
      if (undos.length > 200) undos.shift();
      redos.length = 0;
    }
    if (select && said.made && said.made.length) { picks = said.made.slice(); legendPick = null; }
    sideKey = "";
    soon();
    paint();
    return said.made || [];
  }

  /** Once the plan is being drawn on, the view stays where it is — it is not fitted again round every new piece. */
  function hold() {
    const v = view();
    if (v && v.fit) views.set(chosen(), { ...v, fit: false });
  }

  /** Several edits as one step of Undo — each made in turn, new ids followed within. */
  function edits(ops, label, on = null) {
    const scene = String(on || chosen());
    hold();
    const back = [];
    const renamed = [];
    for (const raw of ops) {
      const text = renamed.reduce((t, [a, b]) => t.split(`"${a}"`).join(`"${b}"`), JSON.stringify(raw));
      const op = JSON.parse(text);
      const said = made(scene, op);
      if (!said || said.error) continue;
      rev++;
      pending.push({ scene, op: fwd(op), made: said.made || [], label: label || op.op });
      if (reading) reading.push({ scene, op: fwd(replayable(op, said.made)) });
      said.undo = fwd(said.undo || []);
      if (op.op === "add" && Array.isArray(op.els)) {
        op.els.forEach((e, i) => { if (e.id && said.made && said.made[i]) renamed.push([e.id, said.made[i]]); });
      }
      back.unshift(...(said.undo || []));
    }
    if (renamed.length) follow(renamed);
    soon();
    return { back, renamed, scene, label };
  }

  function undo() {
    const i = findLast(undos);
    if (i < 0) return;
    const step = undos.splice(i, 1)[0];
    const r = edits(step.ops, step.label, step.scene);
    redos.push({ scene: step.scene, ops: r.back, label: step.label });
    sideKey = "";
    paint();
    toast(`Undid ${step.label || "the last change"}`);
  }
  function redo() {
    const i = findLast(redos);
    if (i < 0) return;
    const step = redos.splice(i, 1)[0];
    const r = edits(step.ops, step.label, step.scene);
    undos.push({ scene: step.scene, ops: r.back, label: step.label });
    sideKey = "";
    paint();
    toast(`Redid ${step.label || "the last change"}`);
  }
  function findLast(list) {
    // This diagram's own steps, and its scene's (a tab made, renamed, moved).
    const s = String(chosen()), r = String(row());
    for (let i = list.length - 1; i >= 0; i--) if (list[i].scene === s || list[i].scene === r) return i;
    return -1;
  }

  /** A piece made here, by the id the film has since given it — for a menu or a box opened before the film answered. */
  const aliases = new Map();
  const swapIds = (text, pairs) => pairs.reduce((t, [a, b]) => t.split(`"${a}"`).join(`"${b}"`), text);
  /**
   * **An edit made on this page's copy.** Between the film giving a new
   * piece its id and the film being read again, this copy still knows the
   * piece by the page's own id: an edit naming the film's id is made here
   * under the old one (and its undo said back in the film's).
   */
  function made(scene, op) {
    const said = json(call("plan_edit", JSON.stringify({ scene, op })));
    if (!said || !said.error || !aliases.size) return said;
    const pairs = [...aliases];
    // The other way too: a gesture begun before the film was read names the
    // page's own ids, and the copy now knows the film's.
    const film = json(call("plan_edit", JSON.stringify({ scene, op: fwd(op) })));
    if (film && !film.error) return film;
    const local = JSON.parse(swapIds(JSON.stringify(op), pairs.map(([a, b]) => [b, a])));
    const again = json(call("plan_edit", JSON.stringify({ scene, op: local })));
    if (!again || again.error) return said;
    return { ...again, undo: JSON.parse(swapIds(JSON.stringify(again.undo || []), pairs)) };
  }
  /** An edit, or its undo, naming pieces by the film's ids. */
  const fwd = (x) => (aliases.size ? JSON.parse(swapIds(JSON.stringify(x), [...aliases])) : x);
  function current(id) {
    let at = id;
    for (let n = 0; n < 8 && aliases.has(at); n++) at = aliases.get(at);
    return at;
  }

  /** Ids the film gave to pieces made here: everything that names the old one names the new. */
  function follow(pairs, film = false) {
    if (!pairs.length) return;
    const swap = (text) => pairs.reduce((t, [a, b]) => t.split(`"${a}"`).join(`"${b}"`), text);
    const fix = (list) => list.forEach((s, i) => { list[i] = { ...s, ops: JSON.parse(swap(JSON.stringify(s.ops))) }; });
    fix(undos); fix(redos);
    pending = pending.map((p) => ({ ...p, op: JSON.parse(swap(JSON.stringify(p.op))) }));
    if (reading) reading = reading.map((p) => ({ ...p, op: JSON.parse(swap(JSON.stringify(p.op))) }));
    // **The film's ids**: this page's copy goes on knowing the pieces by its
    // own until the film is read again, so what is picked keeps its own too
    // and is carried over when the plan is next drawn (`settleIds`).
    if (film) { for (const [a, b] of pairs) aliases.set(a, b); return; }
    const map = new Map(pairs);
    picks = picks.map((id) => map.get(id) || id);
    if (cam && map.has(cam)) cam = map.get(cam);
    if (editingText && map.has(editingText)) editingText = map.get(editingText);
    if (wallDraw && wallDraw.id && map.has(wallDraw.id)) wallDraw.id = map.get(wallDraw.id);
    if (hover && map.has(hover)) hover = map.get(hover);
    if (pickedStep && map.has(pickedStep.id)) pickedStep = { ...pickedStep, id: map.get(pickedStep.id) };
  }

  function remove(ids) {
    edit({ op: "remove", ids }, { label: ids.length > 1 ? "Delete" : `Delete ${(el(ids[0]) || {}).name || ""}`.trim() });
    picks = [];
    paint();
  }
  function duplicate(ids) {
    const step = got && got.settings ? got.settings.step || 0.3048 : 0.3048;
    const made = edit({ op: "duplicate", ids, dx: step, dy: step }, { label: "Duplicate" });
    if (made.length) { picks = made; paint(); }
  }

  // ------------------------------------------------------------ sending

  function soon() {
    clearTimeout(soon.t);
    soon.t = setTimeout(send, drag ? 900 : 350);
  }

  /** Send what is waiting, one batch at a time, a scene at a time. */
  async function send() {
    if (sending || !pending.length) return;
    if (drag) return soon();
    const scene = pending[0].scene;
    const batch = [];
    while (pending.length && pending[0].scene === scene && batch.length < 300) batch.push(pending.shift());
    sending = batch;
    let said = null, trouble = "", stopped = false;
    try {
      const r = await fetch(`/f/${HUB.project}/api/diagram`, {
        method: "PUT",
        headers: { "content-type": "application/json", "x-diagram-me": me },
        body: JSON.stringify({ scene, ops: batch.map((b) => ({ op: b.op, made: b.made })), labels: batch.map((b) => b.label || "") }),
      });
      said = await r.json().catch(() => null);
      if (!r.ok) trouble = (said && (said.error || said.message)) || `The server said ${r.status}`;
      if (r.status === 403 && HUB.role !== "editor") stopped = true;
    } catch {
      trouble = "No connection";
    }
    sending = null;
    if (trouble) {
      // **Nothing half-kept.** What the film holds is read back, and this
      // page's own history goes with what it no longer describes.
      pending = [];
      undos.length = 0;
      redos.length = 0;
      owed = true;
      // A visitor refused: the link's editing was switched off.
      if (stopped) linkStopped(); else toast(`Not saved · ${trouble}`, true);
      return settleUp();
    }
    if (said && said.renamed) follow(said.renamed, true);
    if (said && said.skipped && said.skipped.length) toast(`Skipped: ${said.skipped[0]}`);
    owed = true;
    if (pending.length) return send();
    settleUp();
  }

  /** Read the film again once nothing of ours is in flight: the page's copy becomes the film's. */
  async function settleUp() {
    if (!owed || busy()) return;
    owed = false;
    // Edits made here while the film is being read are not in what is read:
    // they are made again on it, with the ids they were given, so the page
    // never drops one for a moment.
    reading = [];
    let drawn = true;
    try { drawn = await H.reread(() => Boolean(drag || live)); } finally {
      const again = reading;
      reading = null;
      if (again && again.length) {
        for (const { scene, op } of again) call("plan_edit", JSON.stringify({ scene, op }));
        rev++;
        if (!drag) paint();
      }
    }
    // A drag began while the film was read: drawn once it is let go.
    if (drawn === false) owed = true;
  }
  let reading = null;
  /** An edit as it can be made again: an add carries the ids it was given. */
  function replayable(op, made) {
    if (op.op !== "add" || !Array.isArray(op.els) || !made || !made.length) return op;
    return { ...op, els: op.els.map((e, i) => (made[i] ? { ...e, id: made[i] } : e)) };
  }

  /** Something of ours is in the air: the page is not read again under it. */
  function busy() {
    return Boolean(drag || live || pending.length || sending);
  }

  let toastTimer = 0;
  let toastNow = null;           // what the toast says and until when, so a page drawn again keeps saying it
  function toast(text, loud = false) {
    toastNow = { text, loud, until: Date.now() + (loud ? 4200 : 2200) };
    const t = root.querySelector(".plantoast");
    if (!t) return;
    t.textContent = text;
    t.hidden = false;
    t.classList.toggle("loud", loud);
    toastAt = Date.now();
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { t.hidden = true; }, loud ? 4200 : 2200);
  }

  // ------------------------------------------------------------ the side panel

  function side(g) {
    const s = root.querySelector(".planside");
    if (!s) return;
    const ed = editor();
    // **No Gear tab** (Back to Paper, Batch 2): the sheet's legend counts the
    // lamps, and Copy Gear List counts the gear from it. Details opens only
    // when asked — a double-click, More › Details… — never on a pick.
    // Show by Kind, Storyboard Frames and Backdrop live in View (the Mac's).
    const tabs = ed ? [["shots", "Shots"], ["layers", "Layers"], ["details", "Details"]]
      : [["shots", "Shots"]];
    if (!tabs.some(([k]) => k === tab)) tab = tabs[0][0];
    const key = g ? `${H.seen()}|${rev}|${chosen()}|${tab}|${picks.join(",")}|${cam}|${[...off].sort()}|${copied}|${H.beat()}|${editingText}|${pickedStep ? `${pickedStep.id}:${pickedStep.i}` : ""}` : "none";
    if (key === sideKey && s.firstChild) return;
    // A field being typed in is not redrawn under the fingers.
    const typing = s.contains(document.activeElement) && /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName);
    if (typing && key.split("|").slice(0, 5).join("|") === sideKey.split("|").slice(0, 5).join("|")) return;
    sideKey = key;
    if (!g) { s.innerHTML = ""; return; }
    const body = tab === "details" ? details(g)
      : tab === "layers" ? layers(g)
      : tab === "show" ? showList()
      : shots(g);
    s.innerHTML = `<div class="plantabs" role="tablist">${tabs.map(([k, n]) =>
      `<button type="button" role="tab" aria-selected="${k === tab}" class="${k === tab ? "on" : ""}" data-ptab="${k}">${n}</button>`).join("")}</div>
      <div class="planpane">${body}</div>`;
    wireSide(s, g);
  }

  /**
   * **Shots: the scene's shots in order** (the Mac's `DiagramShots`), each
   * with its number, its words and its frame. A shot whose camera stands on
   * the plan is a tap away from it; one that does not is dimmed, and while
   * editing it has Place, which puts its camera in the middle of the view.
   * Cameras that stand for no shot of the scene follow, as the plan's key.
   */
  function shots(g) {
    const cams = g.cams || [];
    const ed = editor();
    const here = planOf(chosen()) ? [] : shotsOfScene();
    const camsFor = (shot) => cams.filter((c) => c.shot === shot);
    const placed = here.filter((r) => camsFor(r.shot).length).length;
    const ratio = Number(H.model().project && H.model().project.ratio) || 16 / 9;
    const list = here.map((r) => {
      const mine = camsFor(r.shot);
      const on = mine.some((c) => c.id === cam || picks.includes(c.id));
      const dot = mine[0] && mine[0].color ? `<span class="pdot" style="background:${esc(mine[0].color)}"></span>` : "";
      const act = !ed ? "" : mine.length ? `<button type="button" class="lact" data-punplace="${esc(r.shot)}">Remove</button>`
        : `<button type="button" class="lact" data-pplace="${esc(r.shot)}">Place</button>`;
      return `<div class="pshot${on ? " on" : ""}${mine.length ? "" : " unplaced"}" data-pshotrow="${esc(r.shot)}"${mine.length ? ` data-pel="${esc(mine[0].id)}" role="button" tabindex="0"` : ed ? ` draggable="true"` : ""}>
        <span class="pshotpic${ratio < 1 ? " tall" : ""}">${r.frame ? H.mediaTag(r.frame) : ""}</span>
        <span class="pshotwho"><b>${dot}${esc(r.number)}</b><span>${esc(r.title || r.description || "Untitled")}</span></span>${act}</div>`;
    }).join("");
    const known = new Set(here.map((r) => r.shot));
    const rest = cams.filter((c) => !c.shot || !known.has(c.shot)).map((c) => {
      const r = shotRow(c.shot);
      const tech = r ? [r.size, r.lens, r.movement].map(H.named).filter(Boolean).join(" · ") : `${Math.round(c.focal)}mm`;
      return `<button type="button" class="plancam${c.id === cam ? " on" : ""}" data-pel="${esc(c.id)}">
        <span class="pdot" style="background:${esc(c.color || "#F2F2F2")}"></span>
        <b>${esc(c.name || "Camera")}</b><span class="ptech">${esc(tech)}</span></button>`;
    }).join("");
    // **Add Shot** (the Mac's): a new shot at the end of the scene, not yet on the plan.
    const addShot = ed && !planOf(chosen()) ? `<button type="button" class="prow" data-paddshot="1">+ Add Shot</button>` : ed ? `<button type="button" class="prow" data-padd="camera">+ Add Camera</button>` : "";
    if (!list && !rest) return `<p class="empty planempty">${here.length ? "No cameras" : "No shots yet"}</p>${addShot}`;
    return `${here.length ? `<div class="pshotcount">${placed} of ${H.many(here.length, "shot")} on the plan</div>` : ""}
      <div class="pshots">${list}</div>${rest ? `<div class="plankey">${rest}</div>` : ""}${addShot}`;
  }

  /** Layers: every piece, top of the stack first, a group's pieces under its name — drag to restack. */
  let layerFind = "";
  const layerWords = (e) => `${e.name} ${word(e.kind)} ${e.groupName || ""} ${e.caption || ""} ${e.label || ""}`.toLowerCase();
  /** Search: the rows that say it stay; a group's head stays while any of its rows does. */
  function findLayers(pane) {
    const q = layerFind.trim().toLowerCase();
    pane.querySelectorAll(".planlayer").forEach((r) => { r.hidden = Boolean(q) && !(r.dataset.words || "").includes(q); });
    pane.querySelectorAll(".plangroup").forEach((h) => {
      let any = false;
      for (let n = h.nextElementSibling; n && n.classList.contains("ingroup"); n = n.nextElementSibling) if (!n.hidden) any = true;
      h.hidden = Boolean(q) && !any;
    });
  }
  /**
   * **Layers** (the Mac's `DiagramLayers`): every piece with a picture of
   * it, top of the stack first, a group's pieces folded under its name —
   * or sorted by Name or by Type under headings. Dragged onto the top or
   * bottom half of a row, a piece lands above or below it, and in or out of
   * its group; a double-click renames; a right-click has the group verbs.
   */
  let layerSort = "manual";
  const foldedGroups = new Set();
  const LAYER_ICON = { camera: "camera", cast: "cast", wall: "wall", door: "door", window: "window", opening: "window", track: "track", road: "road", text: "text", note: "text", arrow: "arrow", measure: "measure", shape: "shape", stroke: "pen", cable: "cable", image: "picture" };
  const KIND_ORDER = ["camera", "cast", "light", "set", "wall", "door", "window", "opening", "track", "road", "image", "text", "note", "arrow", "measure", "shape", "cable", "stroke"];
  const kindHeading = (k) => ({ camera: "Cameras", cast: "Cast", light: "Lights and Grip", set: "Set Pieces", wall: "Walls", door: "Doors and Windows", window: "Doors and Windows", opening: "Doors and Windows", track: "Track and Roads", road: "Track and Roads", image: "Pictures", text: "Words", note: "Words" }[k] || "Marks");
  function layerIcon(e) {
    if (isLamp(e)) return `<i class="licon">${markSvg(lookOf(e.look), 14)}</i>`;
    if (isFrame(e)) return `<i class="licon">${ICONS.frame}</i>`;
    if ((e.kind === "set" || e.kind === "light") && e.sym) { const art = glyph(e.kind, e.sym, 16, 16, 32); if (art) return `<i class="licon art">${art}</i>`; }
    return `<i class="licon">${ICONS[LAYER_ICON[e.kind] || "set"] || ""}</i>`;
  }
  function layers(g) {
    const els = g.els || [];
    if (!els.length) return `<p class="empty planempty">Nothing on the plan</p>`;
    const ed = editor();
    const row = (e, inGroup) => {
      const kind = word(e.kind);
      const dot = e.kind === "camera" && e.color ? `<span class="pdot" style="background:${esc(e.color)}"></span>` : "";
      const hidden = e.show && off.has(e.show);
      const aimed = e.aim && el(e.aim) ? `<span class="lkind">→ ${esc(el(e.aim).name)}</span>` : "";
      const acts = ed ? `<span class="lacts"><button type="button" class="lact" data-lhide="${esc(e.id)}">${e.hidden ? "Show" : "Hide"}</button><button type="button" class="lact" data-llock="${esc(e.id)}">${e.locked ? "Unlock" : "Lock"}</button></span>` : "";
      return `<div class="planlayer${picks.includes(e.id) ? " on" : ""}${e.hidden || hidden ? " dim" : ""}${inGroup ? " ingroup" : ""}" data-pel="${esc(e.id)}" data-pgrp="${esc(e.group || "")}" data-words="${esc(layerWords(e))}"${ed ? ` draggable="true"` : ""} role="button" tabindex="0">
        ${layerIcon(e)}${dot}<span class="lname">${esc(e.name)}</span>${e.name !== kind ? `<span class="lkind">${esc(kind)}</span>` : ""}${aimed}${e.locked ? `<span class="lkind">Locked</span>` : ""}${acts}</div>`;
    };
    const out = [];
    if (layerSort === "name") {
      [...els].sort((a, b) => String(a.name).localeCompare(String(b.name), undefined, { numeric: true })).forEach((e) => out.push(row(e, false)));
    } else if (layerSort === "type") {
      const sorted = [...els].sort((a, b) => (KIND_ORDER.indexOf(a.kind) + 1 || 99) - (KIND_ORDER.indexOf(b.kind) + 1 || 99));
      let head = "";
      for (const e of sorted) {
        const h = kindHeading(e.kind);
        if (h !== head) { head = h; out.push(`<div class="planlayhead">${esc(h)}</div>`); }
        out.push(row(e, false));
      }
    } else {
      const done = new Set();
      for (const e of els) {
        if (done.has(e.id)) continue;
        if (e.group) {
          const members = els.filter((x) => x.group === e.group);
          members.forEach((x) => done.add(x.id));
          const folded = foldedGroups.has(e.group);
          out.push(`<div class="plangroup" data-pgroup="${esc(e.group)}" data-pgrp="${esc(e.group)}"><button type="button" class="lfold${folded ? "" : " open"}" data-pfold="${esc(e.group)}" aria-label="${folded ? "Open" : "Fold"}" aria-expanded="${!folded}"></button><span class="lname"${ed ? ` data-prename="${esc(e.group)}" title="Double-click to Rename"` : ""}>${esc(e.groupName || "Group")}</span><span class="lkind">${H.many(members.length, "piece")}</span>
            ${ed ? `<button type="button" class="lact" data-pungroup="${esc(e.group)}">Ungroup</button>` : ""}</div>`);
          if (!folded) members.forEach((x) => out.push(row(x, true)));
        } else {
          done.add(e.id);
          out.push(row(e, false));
        }
      }
    }
    return `<div class="planlaytop"><select class="planlaysort" data-playsort="1" aria-label="Sort By">${[["manual", "Manual"], ["name", "Name"], ["type", "Type"]].map(([v, n]) => `<option value="${v}"${layerSort === v ? " selected" : ""}>${n}</option>`).join("")}</select>
      <input type="search" class="planfind" data-pfindlayers="1" placeholder="Search" value="${esc(layerFind)}" aria-label="Search pieces"></div>
      <div class="planlayers">${out.join("")}</div>`;
  }

  function showList() {
    return `<div class="planshow">${SHOW.map(([k, n]) =>
      `<button type="button" class="pshow${off.has(k) ? "" : " on"}" data-pshow="${k}" aria-pressed="${!off.has(k)}">${n}<i></i></button>`).join("")}
      <button type="button" class="pshow${frames ? " on" : ""}" data-pframes="1" aria-pressed="${frames}">Storyboard Frames<i></i></button>
    ${off.size ? `<button type="button" class="pcopy" data-pshowall="1">Show All</button>` : ""}
      <div class="pbackdrop"><div class="pbdhead"><span>Backdrop</span>${Math.abs(backdrop - BACKDROP_DEFAULT) < 0.001 ? "" : `<button type="button" class="pcopy" data-pbackdropreset="1">Reset</button>`}</div>
        <label class="pbdrow"><i>Dim</i><input type="range" min="0" max="1" step="0.01" value="${backdrop.toFixed(2)}" data-pbackdrop="1" aria-label="Backdrop"><i>Bright</i></label></div></div>`;
  }

  // ---- the sheet's notes and legend, by the plan ------------------------------
  //
  // **The legend and the notes, for everybody** (Back to Paper, Batch 2, his
  // call C): the sheet's own lines, from the engine (`plan_sheet`, built once
  // — the lines Print, the Mac's sheet and Claude's paper picture carry):
  // the Legend, Film Lights · Practicals · Existing, then Frames by size,
  // each its mark, its NAME and ×N; then his Sheet Notes. A line picks every
  // lamp of its kind, and the bar acts on all of them; editing, a head or
  // the notes are typed into where they stand.

  let sheetGot = null, sheetAsked = "", cardDrawn = "";
  let legendPick = null;          // a legend line clicked: { kind, key, ids, name, count }
  const SHEET_KEY = "shotlister.plansheet";
  let sheetFolded = null;         // this viewer's: the card folded to its head
  try { const v = localStorage.getItem(SHEET_KEY); if (v) sheetFolded = v === "folded"; } catch { /* per viewer */ }

  /** The sheet as the engine lays it out for this plan, read again only when the film is. */
  function sheetOf() {
    const key = `${H.seen()}|${rev}|${chosen()}|${H.beat()}`;
    if (key !== sheetAsked) {
      sheetAsked = key;
      const said = json(call("plan_sheet", JSON.stringify({ scene: String(chosen()), screen: true, furniture: true, beat: H.beat(), tz: -new Date().getTimezoneOffset() })));
      sheetGot = said && said.sheet ? { ...said.sheet, furniture: said.furniture || "" } : null;
    }
    return sheetGot;
  }

  // ---- the sheet on screen (the Mac's DiagramPage) ------------------------
  //
  // **The page that prints, lying on the desk** (Back to Paper, Batch 2, his
  // call C; the Mac's `drawDesk` and `drawPageFurniture`). The engine lays
  // the sheet out once: where the plan's origin lands on the paper and at
  // how many points to the metre, so the paper's corners are found on the
  // plan as shown, and the sheet's own words — the title, north, the
  // legend, the notes, the shots — drawn round it. The plan is lettered at
  // the sheet's scale (`page_scale`), so zooming is looking closer at
  // paper, and what is clicked is what is drawn.
  // **Not on a phone**: a whole printed page fitted to a phone is too small
  // to read on set, so there the plan fills the box and the legend waits
  // folded by it, as it always did.
  const onPage = () => {
    const sh = got && (got.els || []).length && !H.narrow() ? sheetOf() : null;
    return sh && sh.scale > 0 && sh.w > 0 ? sh : null;
  };
  /** The paper's edges, on the plan as shown, in metres. */
  function pageShown(sh) {
    return { x: -sh.ox / sh.scale, y: -sh.oy / sh.scale, w: sh.w / sh.scale, h: sh.h / sh.scale };
  }
  /** Where the plan stands on the paper, as shown: the dots go there and nowhere else. */
  function windowShown(sh) {
    const [x, y, w, h] = sh.window || [0, 0, sh.w, sh.h];
    return [(x - sh.ox) / sh.scale, (y - sh.oy) / sh.scale, (x + w - sh.ox) / sh.scale, (y + h - sh.oy) / sh.scale];
  }
  /** What the plan is asked with, on the page: its lettering and its window. */
  const pageAsk = () => {
    const sh = onPage();
    return sh ? { page_scale: sh.scale, window: windowShown(sh) } : {};
  };
  /** The lamps, frames or camera a sheet line stands for; the FRAMES head is every frame. */
  function pageIds(sh, it) {
    if (it.kind === "head" && it.key === "frames") return sh.items.filter((x) => x.kind === "frames").flatMap((x) => x.ids || []).filter((id) => el(id));
    return (it.ids || []).filter((id) => el(id));
  }
  const pageTyped = (it) => it.kind === "notes" || (it.kind === "head" && /^colour:/.test(it.key));
  /** The page and its lines, as drawn under the plan. */
  function pageLayer(sh, v, b) {
    const p = pageShown(sh);
    const [l, t] = toBox(p.x, p.y);
    const W = p.w * v.k, Ht = p.h * v.k;
    const pct = (a, of) => `${(a / of * 100).toFixed(4)}%`;
    const picked = new Set(picks);
    const lines = sh.items.map((it, i) => {
      const ids = pageIds(sh, it);
      const typedIt = pageTyped(it);
      if (!typedIt && !ids.length) return "";
      if (typedIt && !editor()) return "";
      const [x, y, w, h] = it.box || [0, 0, 0, 0];
      const on = !typedIt && ids.length && ids.length === picked.size && ids.every((id) => picked.has(id));
      return `<i class="ppitem${on ? " on" : ""}${typedIt ? " typed" : ""}" data-ppitem="${i}" style="left:${pct(x - 3, sh.w)};top:${pct(y - 1, sh.h)};width:${pct(w + 6, sh.w)};height:${pct(h + 2, sh.h)}" title="${esc(typedIt ? (it.kind === "notes" ? "Sheet Notes" : "Rename") : it.name || "")}"></i>`;
    }).join("");
    const at = `left:${l.toFixed(1)}px;top:${t.toFixed(1)}px;width:${W.toFixed(1)}px;height:${Ht.toFixed(1)}px`;
    // The paper under the plan; its lines over it, to be clicked.
    return [`<div class="planpaper"><div class="ppsheet" style="${at}">${sh.furniture}</div></div>`,
      `<div class="planpaper pplines"><div class="pplinebox" style="${at}">${lines}</div></div>`];
  }
  /** The page fitted to the box: the whole sheet, clear of the toolbar over it and the zoom under it. */
  function fitPage(sh, w, h) {
    const p = pageShown(sh);
    const narrow = H.narrow();
    const [top, bottom, side] = presenting ? [16, 16, 16] : narrow ? [editor() ? 12 : 12, 58, 10] : [editor() ? 76 : 24, 62, 28];
    const k = Math.min((w - 2 * side) / p.w, (h - top - bottom) / p.h);
    const K = Math.max(4, k);
    return { cx: p.x + p.w / 2, cy: p.y + p.h / 2 + (bottom - top) / 2 / K, k: K, fit: true, fitK: K };
  }
  /** A click on a sheet line: it picks what it counts; the notes or a head is typed into, there. */
  function pageClick(i) {
    const sh = onPage();
    const it = sh && sh.items[i];
    if (!it) return;
    endTyping(true);
    // Typing starts once the press is over: the press itself puts the keys
    // on the plan as it goes down, and would take them back.
    if (pageTyped(it)) return editor() && setTimeout(() => pageType(sh, i), 0);
    const ids = pageIds(sh, it);
    const again = ids.length === picks.length && ids.every((id) => picks.includes(id));
    if (again || !ids.length) { picks = []; legendPick = null; }
    else {
      picks = ids.slice();
      legendPick = it.kind === "legend" || it.kind === "frames" ? { kind: it.kind, key: it.key, ids: ids.slice(), name: it.name, count: it.count } : null;
      cam = it.kind === "shot" && ids.length === 1 ? ids[0] : null;
      if (cam) tab = "shots";
    }
    pickedCorner = null; pickedStretch = null; sideKey = "";
    paint();
  }
  /** Typing on the sheet itself: the Sheet Notes, or what an ink is called at the head of its lines. */
  function pageType(sh, i) {
    const it = sh.items[i];
    const node = root.querySelector(`.ppitem[data-ppitem="${i}"]`);
    const v = view();
    if (!node || !v) return;
    const notes = it.kind === "notes";
    const k = v.k / sh.scale;
    node.classList.add("intype");
    node.style.fontSize = `${((notes ? 8 : 7) * k).toFixed(2)}px`;
    if (notes) { node.style.paddingTop = `${(10 * k).toFixed(1)}px`; node.style.minWidth = node.style.width; node.style.width = "auto"; node.style.maxWidth = `${(Math.min(Math.max((sh.w - 2 * sh.margin) * 0.28, 140), 240) * k).toFixed(0)}px`; node.style.height = "auto"; }
    const now = notes ? String(settings().sheet_notes || "") : it.name;
    inPlace(node, now, !notes, (val) => {
      if (notes) edit({ op: "settings", set: { sheet_notes: val } }, { label: "Sheet Notes" });
      else edit({ op: "legend", key: it.key, name: val }, { label: "Rename" });
    }, () => paint());
  }
  /** The legend line the pick came from, while the pick is still exactly its lamps. */
  function legendPicked() {
    if (!legendPick) return null;
    const same = picks.length === legendPick.ids.length && legendPick.ids.every((id) => picks.includes(id));
    return same ? legendPick : null;
  }

  function sheetCard() {
    const n = root.querySelector(".plansheet");
    if (!n) return;
    // A head or the notes being typed into are not drawn again under the keys.
    if (n.contains(document.activeElement) && document.activeElement.isContentEditable) return;
    const sh = got && !presenting && !onPage() ? sheetOf() : null;
    const st = settings();
    const lines = ((sh && sh.items) || []).filter((i) => i.kind === "head" || i.kind === "legend" || i.kind === "frames");
    const notes = String(st.sheet_notes || "");
    const notesOn = st.notes !== false && Boolean(notes.trim() || editor());
    const ed = editor();
    const picked = legendPicked();
    const folded = lines.length > 0 && (sheetFolded === null ? H.narrow() : sheetFolded);
    const first = "Legend";
    let html = "";
    if (sh && got && (got.els || []).length && (lines.length || notesOn)) {
      const blocks = [];
      if (lines.length) {
        blocks.push(lines.map((it, i) => {
          if (it.kind === "head") {
            const renames = ed && /^colour:/.test(it.key);
            return `<div class="pshd${renames ? " edits" : ""}"${renames ? ` data-pshd="${i}" title="Rename"` : ""}>${esc(it.name)}</div>`;
          }
          const ids = (it.ids || []).filter((id) => el(id));
          const on = picked && picked.key === it.key && picked.kind === it.kind && picked.ids.length === ids.length;
          if (it.kind === "frames") {
            const fw = `${it.name || "Unlabeled"}${st.counts ? ` ×${it.count}` : ""}`;
            return `<button type="button" class="psline${on ? " on" : ""}${it.name ? "" : " dim"}" data-psline="${i}"><i class="psmark frame" style="color:${inkHex("gripink")}"></i><span>${esc(fw)}</span></button>`;
          }
          // Exactly the label as written (2026-10-17); a count only with Counts on.
          const words = `${it.name || "Unlabeled"}${st.counts ? ` ×${it.count}` : ""}`;
          return `<button type="button" class="psline${on ? " on" : ""}" data-psline="${i}"><i class="psmark">${markSvg(lookOf(it.key), 14)}</i><span>${esc(words)}</span></button>`;
        }).join(""));
      }
      if (notesOn) {
        blocks.push(`${lines.length && notes.trim() ? `<div class="psh">Notes</div>` : ""}<div class="psnotes${notes.trim() ? "" : " empty"}${ed ? " edits" : ""}"${ed ? ` data-psnotes="1" title="Sheet Notes"` : ""}>${esc(notes.trim() ? notes : "Notes")}</div>`);
      }
      // A legend folds to its head; Notes alone are just the notes.
      html = lines.length
        ? `<button type="button" class="psh psfold" data-psfold="1" aria-expanded="${!folded}">${first}</button>${folded ? "" : `<div class="psbody">${blocks.join("")}</div>`}`
        : `<div class="psbody">${notes.trim() ? `<div class="psh">Notes</div>` : ""}${blocks.join("")}</div>`;
    }
    n.classList.toggle("caps", Boolean(st.caps));
    if (html === cardDrawn && n.firstChild) return;
    cardDrawn = html;
    n.innerHTML = html;
    n.hidden = !html;
    n.classList.toggle("folded", folded);
    const fold = n.querySelector("[data-psfold]");
    if (fold) fold.addEventListener("click", () => {
      sheetFolded = !folded;
      try { localStorage.setItem(SHEET_KEY, sheetFolded ? "folded" : "open"); } catch { /* this visit */ }
      cardDrawn = ""; sheetCard();
    });
    n.querySelectorAll("[data-psline]").forEach((b) => b.addEventListener("click", () => {
      const it = lines[Number(b.dataset.psline)];
      const ids = (it.ids || []).filter((id) => el(id));
      const again = legendPicked() && legendPick.key === it.key && legendPick.kind === it.kind;
      endTyping(true);
      if (again || !ids.length) { picks = []; legendPick = null; }
      else { picks = ids.slice(); legendPick = { kind: it.kind, key: it.key, ids: ids.slice(), name: it.name, count: it.count }; cam = null; }
      pickedCorner = null; pickedStretch = null; sideKey = "";
      paint();
    }));
    if (!ed) return;
    n.querySelectorAll("[data-pshd]").forEach((h) => h.addEventListener("click", () => {
      const it = lines[Number(h.dataset.pshd)];
      inPlace(h, it.name, true, (v) => edit({ op: "legend", key: it.key, name: v }, { label: "Rename" }));
    }));
    const nb = n.querySelector("[data-psnotes]");
    if (nb) nb.addEventListener("click", () => {
      if (nb.isContentEditable) return;
      inPlace(nb, notes, false, (v) => edit({ op: "settings", set: { sheet_notes: v } }, { label: "Sheet Notes" }));
    });
  }

  /** The words in an edited block as typed — not as the capitals draw them (`innerText` follows text-transform). */
  function typed(n) {
    let t = "";
    n.childNodes.forEach((c) => {
      if (c.nodeType === 3) t += c.nodeValue;
      else if (c.nodeName === "BR") t += "\n";
      else t += `${t && !t.endsWith("\n") ? "\n" : ""}${typed(c)}`;
    });
    return t;
  }

  /**
   * **Typed where it stands** — a legend head or the Sheet Notes, the words
   * themselves made editable: no box, no Cancel or Done. Click away keeps
   * it; Escape leaves it; Return keeps a head (the notes take Return as a
   * new line, ⌘Return keeps them).
   */
  function inPlace(node, now, single, keep, left = null) {
    node.classList.remove("empty");
    node.textContent = now;
    try { node.contentEditable = "plaintext-only"; } catch { node.contentEditable = "true"; }
    if (node.contentEditable !== "plaintext-only") node.contentEditable = "true";
    node.classList.add("typing-in");
    node.focus();
    const range = document.createRange();
    range.selectNodeContents(node);
    const sel = window.getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    let over = false;
    const done = (ok) => {
      if (over) return;
      over = true;
      const v = typed(node).replace(/\s+$/, "").replace(/^\s+/, "");
      node.contentEditable = "false";
      node.classList.remove("typing-in");
      const b = box();
      if (b) b.vp.focus({ preventScroll: true });
      cardDrawn = "";
      if (ok && v !== now.trim()) keep(single ? v.replace(/\s*\n\s*/g, " ") : v);
      else if (left) left();
      else sheetCard();
    };
    node.addEventListener("keydown", (ev) => {
      ev.stopPropagation();
      if (ev.key === "Escape") { ev.preventDefault(); done(false); }
      if (ev.key === "Enter" && (single || ev.metaKey || ev.ctrlKey)) { ev.preventDefault(); done(true); }
    });
    node.addEventListener("blur", () => done(true), { once: true });
  }

  // ---- Details: the Mac's inspector, field for field ----------------------

  const F = {
    text: (label, key, value, extra = "") => `<label class="pf"><span>${label}</span><input type="text" data-pf="${key}" value="${esc(value ?? "")}"${extra}></label>`,
    area: (label, key, value) => `<label class="pf"><span>${label}</span><textarea rows="3" data-pf="${key}">${esc(value ?? "")}</textarea></label>`,
    num: (label, key, value, unit = "", min = "", max = "", step = "any") => `<label class="pf"><span>${label}</span><span class="pfnum"><input type="number" inputmode="decimal" data-pf="${key}" data-num="1" value="${value !== "" && value !== null && value !== undefined && Number.isFinite(Number(value)) ? Math.round(Number(value) * 100) / 100 : ""}"${min !== "" ? ` min="${min}"` : ""}${max !== "" ? ` max="${max}"` : ""} step="${step}">${unit ? `<i>${unit}</i>` : ""}</span></label>`,
    len: (label, key, value) => `<label class="pf"><span>${label}</span><input type="text" data-pf="${key}" data-len="1" value="${esc(lengthText(Number(value) || 0))}"></label>`,
    pick: (label, key, value, options, empty = "") => `<label class="pf"><span>${label}</span><select data-pf="${key}">${empty ? `<option value="">${esc(empty)}</option>` : ""}${options.map((o) => {
      const [v, n] = Array.isArray(o) ? o : [o, o];
      return `<option value="${esc(v)}"${String(v) === String(value ?? "") ? " selected" : ""}>${esc(n)}</option>`;
    }).join("")}</select></label>`,
    flag: (label, key, on) => `<button type="button" class="pshow${on ? " on" : ""}" data-pflag="${key}" aria-pressed="${Boolean(on)}">${label}<i></i></button>`,
    pills: (label, key, value, options) => `<div class="pf"><span>${label}</span><div class="ppills">${options.map(([v, n]) =>
      `<button type="button" class="ppill${String(v) === String(value) ? " on" : ""}" data-pset="${key}" data-pv="${esc(JSON.stringify(v))}">${esc(n)}</button>`).join("")}</div></div>`,
    colour: (label, key, value, none = false) => `<div class="pf"><span>${label}</span><div class="pswatches">${none ? `<button type="button" class="pswatch none${!value ? " on" : ""}" data-pset="${key}" data-pv='""' title="None" aria-label="None"></button>` : ""}${PALETTE.map((c, i) =>
      `<button type="button" class="pswatch${String(value || "").toLowerCase() === c.toLowerCase() ? " on" : ""}" style="background:${c}" data-pset="${key}" data-pv='${JSON.stringify(c)}' title="${PALETTE_NAMES[i]}" aria-label="${PALETTE_NAMES[i]}"></button>`).join("")}
      <label class="pswatch other" title="Other Colour"><input type="color" data-pf="${key}" value="${/^#[0-9a-f]{6}$/i.test(value || "") ? value : "#888888"}"></label></div></div>`,
    btn: (label, act) => `<button type="button" class="pcopy" data-pdo="${act}">${label}</button>`,
  };

  // ---- the lighting plot (his ruling, 2026-10-03) ---------------------------
  //
  // A lamp is a mark he picks — chevron, wedge, bar… — and what kind of light
  // it is comes from what its mark stands for in the legend (the engine's
  // `plot.rs`). The picture style is retired. **Three inks** (Back to Paper,
  // his call 2026-10-04): red for what we bring (film lights, frames, grip),
  // blue for the camera, grey for what is already there; practicals amber
  // (his calls, 2026-10-05).

  const MARKS = [["chevron", "Chevron"], ["wedge", "Wedge"], ["bar", "Bar"], ["double-bar", "Panel"], ["ring", "Ring"], ["dot", "Dot"], ["square", "Square"]];
  const LETTERS = ["A", "B", "C", "D", "E", "F", "G", "H"];
  const SOLID_FIRST = new Set(["wedge", "bar", "double-bar", "dot"]);
  // A tube starts four feet long, a panel two (his call, 2026-10-04).
  const TUBE_LEN = { bar: 1.2192, "double-bar": 0.6096 };
  const INK_HEX = { added: "#B42318", practical: "#E08A00", existing: "#74777C", blue: "#2F5DB8", gripink: "#B42318", camink: "#2F5DB8", plan: "#74777C", prop: "#989BA0" };
  const COLOUR_NAMES = [["added", "Film Lights"], ["practical", "Practicals"], ["existing", "Existing Lights"], ["blue", "Third Ink"], ["gripink", "Grip"], ["camink", "Cameras"], ["plan", "Walls"], ["prop", "Furniture and Props"]];
  const inkHex = (ink) => {
    const role = ink === "ink" ? "existing" : ink;
    const mine = ((got && got.settings && got.settings.colours) || {})[role];
    return mine || INK_HEX[role] || "#17171A";
  };
  const lookOf = (key) => {
    const [mark = "chevron", ink = "added", fill = ""] = String(key || "").split("|");
    return { mark, ink, solid: fill ? fill === "solid" : SOLID_FIRST.has(mark) };
  };
  const lookKey = (l) => `${l.mark}|${l.ink}|${l.solid ? "solid" : "open"}`;
  let armedLook = "chevron|added|open";
  let lettersOpen = false;        // Letters opened in a mark picker, this visit

  /** A mark as the plan draws it, facing right. */
  function markSvg(l, size = 22) {
    const c = inkHex(l.ink), s = size, m = s / 2;
    const p = (x, y) => `${(m + x * s).toFixed(1)},${(m + y * s).toFixed(1)}`;
    const fillOr = (d) => (l.solid ? `<path d="${d}" fill="${c}"/>` : `<path d="${d}" fill="none" stroke="${c}" stroke-width="1.6" stroke-linejoin="round"/>`);
    let body = "";
    if (l.mark === "chevron") body = l.solid ? `<path d="M${p(0.5, -0.42)} L${p(-0.5, 0)} L${p(0.5, 0.42)} L${p(0.18, 0)} Z" fill="${c}"/>` : `<path d="M${p(0.5, -0.42)} L${p(-0.5, 0)} L${p(0.5, 0.42)}" fill="none" stroke="${c}" stroke-width="2" stroke-linejoin="round"/>`;
    else if (l.mark === "wedge") body = fillOr(`M${p(-0.5, 0)} L${p(0.5, -0.45)} L${p(0.5, 0.45)} Z`);
    else if (l.mark === "bar") body = fillOr(`M${p(-0.1, -0.5)} H${(m + 0.1 * s).toFixed(1)} V${(m + 0.5 * s).toFixed(1)} H${(m - 0.1 * s).toFixed(1)} Z`);
    // A panel: a box with a heavy front edge, so it never reads as a tube.
    else if (l.mark === "double-bar") body = fillOr(`M${p(-0.25, -0.5)} H${(m + 0.25 * s).toFixed(1)} V${(m + 0.5 * s).toFixed(1)} H${(m - 0.25 * s).toFixed(1)} Z`) + (l.solid ? "" : `<path d="M${p(0.09, -0.5)} H${(m + 0.25 * s).toFixed(1)} V${(m + 0.5 * s).toFixed(1)} H${(m + 0.09 * s).toFixed(1)} Z" fill="${c}"/>`);
    else if (l.mark === "ring") body = `<circle cx="${m}" cy="${m}" r="${s * 0.36}" fill="${l.solid ? c : "none"}" stroke="${c}" stroke-width="1.6"/><circle cx="${m}" cy="${m}" r="${s * 0.13}" fill="${l.solid ? "#fff" : c}"/>`;
    else if (l.mark === "dot") body = `<circle cx="${m}" cy="${m}" r="${s * 0.3}" fill="${l.solid ? c : "none"}" stroke="${c}" stroke-width="1.6"/>`;
    else if (l.mark === "arrow") body = `<path d="M${p(-0.5, 0)} L${p(0.42, 0)}" stroke="${c}" stroke-width="1.8"/>${l.solid ? `<path d="M${p(0.1, -0.3)} L${p(0.5, 0)} L${p(0.1, 0.3)} Z" fill="${c}"/>` : `<path d="M${p(0.1, -0.3)} L${p(0.5, 0)} L${p(0.1, 0.3)}" fill="none" stroke="${c}" stroke-width="1.8"/>`}`;
    // A soft panel from above: a wide box, a wash, a fine inner line.
    else if (l.mark === "mat") body = `<rect x="${(m - 0.42 * s).toFixed(1)}" y="${(m - 0.27 * s).toFixed(1)}" width="${(0.84 * s).toFixed(1)}" height="${(0.54 * s).toFixed(1)}" fill="${c}" fill-opacity="${l.solid ? 0.42 : 0.13}" stroke="${c}" stroke-width="1.6"/><rect x="${(m - 0.33 * s).toFixed(1)}" y="${(m - 0.18 * s).toFixed(1)}" width="${(0.66 * s).toFixed(1)}" height="${(0.36 * s).toFixed(1)}" fill="none" stroke="${c}" stroke-opacity="0.75" stroke-width="0.7"/>`;
    else if (l.mark === "square") body = fillOr(`M${p(-0.33, -0.33)} H${(m + 0.33 * s).toFixed(1)} V${(m + 0.33 * s).toFixed(1)} H${(m - 0.33 * s).toFixed(1)} Z`);
    else body = `<circle cx="${m}" cy="${m}" r="${s * 0.45}" fill="none" stroke="${c}" stroke-width="1.4"/><text x="${m}" y="${m}" text-anchor="middle" dominant-baseline="central" font-size="${s * 0.55}" font-weight="700" fill="${c}">${esc(l.mark.split("-").pop())}</text>`;
    return `<svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}" aria-hidden="true">${body}</svg>`;
  }

  /**
   * Every mark as a picture, then Letters and Solid: `attr` carries the look
   * picked. No colours: a lamp's colour is its Type (his call, 2026-10-04).
   * **Eight, not sixteen** (Back to Paper, 2026-10-04): the lettered circles
   * wait behind Letters, open when the look is one or he opened them; `named`
   * writes each mark's name under it (the Light tool's palette).
   */
  function markPicker(cur, attr, named = false) {
    const tile = (l, label, word = "") => `<button type="button" class="pmark${word ? " named" : ""}${lookKey(l) === lookKey(cur) ? " on" : ""}" data-${attr}="${esc(lookKey(l))}" title="${esc(label)}">${markSvg(l)}${word ? `<small>${esc(word)}</small>` : ""}</button>`;
    const same = (mark) => ({ mark, ink: cur.ink, solid: mark === cur.mark ? cur.solid : SOLID_FIRST.has(mark) });
    const open = lettersOpen || /^letter-/.test(cur.mark);
    return `<div class="pmarks${named ? " named" : ""}">${MARKS.map(([m, n]) => tile(same(m), n, named ? n : "")).join("")}</div>
      <div class="pmarks letters"${open ? "" : " hidden"}>${LETTERS.map((c) => tile({ mark: `letter-${c}`, ink: cur.ink, solid: false }, `Letter ${c}`)).join("")}</div>
      <div class="pmarkinks">
        <button type="button" class="ppill plet${open ? " on" : ""}" data-pletters="1" aria-expanded="${open}">Letters</button>
        <button type="button" class="ppill${cur.solid ? " on" : ""}" data-${attr}="${esc(lookKey({ ...cur, solid: !cur.solid }))}">Solid</button></div>`;
  }
  /** Letters shows or hides its own picker's lettered circles, and is remembered while the page is open. */
  function wireLetters(scope) {
    scope.querySelectorAll("[data-pletters]").forEach((b) => b.addEventListener("click", () => {
      const row = b.closest(".pmarkinks") && b.closest(".pmarkinks").previousElementSibling;
      if (!row || !row.classList.contains("letters")) return;
      lettersOpen = row.hidden;
      row.hidden = !lettersOpen;
      b.classList.toggle("on", lettersOpen);
      b.setAttribute("aria-expanded", String(lettersOpen));
    }));
  }

  /** The Light tool's palette: pick a mark, click the plan to put lights down. */
  function markFloat(f) {
    f.className = "planfloat lib marks";
    const cur = lookOf(armedLook);
    // **Film Light · Practical · Existing along the top** (his Ref 1466): a lamp's Type is its ink.
    const types = [["added", "Film Light"], ["practical", "Practical"], ["ink", "Existing"]];
    const typeRow = `<div class="ppills ptyperow">${types.map(([ink, n]) => `<button type="button" class="ppill${(cur.ink === ink || (ink === "ink" && cur.ink === "existing")) ? " on" : ""}" data-parmtype="${ink}">${n}</button>`).join("")}</div>`;
    f.innerHTML = `<div class="plibhead"><b>Lamps</b></div>${typeRow}${markPicker(cur, "parm", true)}<div class="plibfoot">Click to place · drag to turn</div>`;
    f.querySelectorAll("[data-parm]").forEach((b) => b.addEventListener("click", () => { armedLook = b.dataset.parm; float(); }));
    f.querySelectorAll("[data-parmtype]").forEach((b) => b.addEventListener("click", () => { armedLook = lookKey({ ...lookOf(armedLook), ink: b.dataset.parmtype }); float(); }));
    wireLetters(f);
  }

  /** The library's light names, short and once each, for naming a mark. */
  function lightNames() {
    const seen = new Set();
    for (const s of library().symbols || []) {
      if (!s.light || (s.lib && s.lib !== "light")) continue;
      seen.add(String(s.name).split(" with ")[0]);
    }
    return [...seen].sort((a, b) => a.localeCompare(b));
  }

  /**
   * **One step of a piece, picked on its own** — the Mac's step panel: the
   * beat it plays on, which way it faces (typed), a person's pose there, and
   * the next step or taking it away. The piece itself is a click away.
   */
  function stepDetails(e, sp) {
    const t = sp.s;
    const home = (e.seq || []).find((x) => x.home);
    const out = [`<div class="pdhead"><b>${esc(e.name)} · ${esc(t.letter)}</b><span>${t.home ? "" : t.turn ? "Turn" : "Move"}</span></div>`];
    out.push(F.pick("Beat", "step_beat", t.beat, stepBeats(e).map((n) => [n, n ? `Beat ${n}` : "No Beat"])));
    out.push(F.num("Rotation", "step_rot", Math.round((((t.rot % 360) + 360) % 360) * 100) / 100, "°", 0, 360));
    if (e.kind === "cast" && !t.home) {
      out.push(F.pills("Pose", "step_pose", t.pose || "", [["", "Same"], ["standing", "Standing"], ["seated", "Seated"], ["lying", "Lying"]]));
    }
    out.push(`<div class="pdbtns">${F.btn("Add Move", "step_addmove")}${F.btn("Add Turn", "step_addturn")}${t.home ? "" : F.btn(`Remove ${esc(t.letter)}`, "step_remove")}${home && !t.home ? F.btn(`Pick ${esc(home.letter)}`, "step_home") : ""}</div>`);
    return `<div class="pdetails">${out.join("")}</div>`;
  }

  /** **What a drawn path or wall is** (his ask, 2026-10-02): a plain line, a wall, or a filled object; the same points either way. */
  function pathKindField(e) {
    const now = e.kind === "wall" ? "wall" : e.fill && e.closed ? "object" : "line";
    return F.pills("Type", "path_as", now, [["line", "Line"], ["wall", "Wall"], ["object", "Object"]]);
  }
  /** A fill out of a closed shape (the Mac's): on or off, its colour (none is the plan's tint) and how solid it is. */
  function fillFields(out, e) {
    if (!e.closed || wallCorners(e).length < 3) return;
    const on = e.kind === "wall" ? Boolean(e.fill_color) : Boolean(e.fill);
    out.push(F.flag("Fill", "fill_on", on));
    if (!on) return;
    const hex = /^#/.test(e.fill_color || "");
    out.push(F.colour("Fill Colour", "fill_colour", hex ? e.fill_color : "", true));
    out.push(F.num("Fill Opacity", "fill_alpha", Math.round(((e.fill_alpha || 0) > 0 ? e.fill_alpha : hex ? 0.55 : 0.16) * 100), "%", 2, 100));
  }
  /** Several from a list, as pills to tick (a shot's Angle, its Cast): the Mac's ticked menu. */
  function multiPills(label, key, now, terms) {
    const all = [...new Set([...terms, ...now])];
    if (!all.length) return `<div class="pf"><span>${esc(label)}</span><b class="pread">—</b></div>`;
    return `<div class="pf"><span>${esc(label)}</span><div class="ppills">${all.map((t) =>
      `<button type="button" class="ppill${now.includes(t) ? " on" : ""}" data-pmulti="${esc(key)}" data-pv="${esc(t)}">${esc(t)}</button>`).join("")}</div></div>`;
  }
  /** Several pieces' one Colour, in Details: their swatches, Mixed while they differ. */
  function manyColour(els) {
    const one = mixedColour(els);
    return F.colour(one === null ? "Colour <i class=\"pmixed\">Mixed</i>" : "Colour", "pick_color", one || "", true);
  }
  /** Send to / Copy to the other view, in Details. */
  function layerBtns(els) {
    const crossing = els.filter(canCross);
    if (!crossing.length) return "";
    const n = otherLayer(crossing) === "set" ? "Set" : "Plot";
    return `<div class="pdbtns">${F.btn(`Send to ${n}`, "sendlayer")}${F.btn(`Copy to ${n}`, "copylayer")}</div>`;
  }
  function details(g) {
    if (!editor()) return "";
    const els = picks.map((id) => (g.els || []).find((e) => e.id === id)).filter(Boolean);
    if (!els.length) return `<p class="empty planempty">Nothing picked</p>`;
    if (els.length > 1) {
      return `<div class="pdetails"><div class="pdhead"><b>${els.length} Selected</b></div>
        <div class="pf"><span>Align</span><div class="ppills">${[["left", "Left"], ["hcentre", "Centre"], ["right", "Right"], ["top", "Top"], ["vcentre", "Middle"], ["bottom", "Bottom"]].map(([k, n]) =>
          `<button type="button" class="ppill" data-palign="${k}">${n}</button>`).join("")}</div></div>
        ${els.length > 2 ? `<div class="pf"><span>Space Evenly</span><div class="ppills"><button type="button" class="ppill" data-pdist="x">Across</button><button type="button" class="ppill" data-pdist="y">Down</button></div></div>` : ""}
        ${F.num("Rotation", "pick_rot", Math.round(heading(els[0]) * 100) / 100, "°", 0, 360)}
        ${F.num("Opacity", "pick_opacity", Math.round((els[0].opacity ?? 1) * 100), "%", 10, 100)}
        ${manyColour(els)}
        ${layerBtns(els)}
        <div class="pdbtns">${els.filter(canShare).length >= 2 ? F.btn("Share Label", "sharelabel") : ""}${F.btn("Group", "group")}${els.some((e) => e.group) ? F.btn("Ungroup", "ungroup") : ""}${F.btn("Duplicate", "duplicate")}${F.btn("Flip Across", "flipx")}${F.btn("Flip Down", "flipy")}${F.btn("Delete", "delete")}</div></div>`;
    }
    const e = els[0];
    const sp = stepPicked();
    if (sp && sp.e.id === e.id) return stepDetails(e, sp);
    const L = library();
    const out = [];
    const k = e.kind;
    const headWord = isFrame(e) ? "Frame" : isGrip(e) ? "Grip" : isLamp(e) ? typeWord(e) : isShared(e) ? "Shared Label" : word(k);
    out.push(`<div class="pdhead"><b>${esc(isShared(e) ? lampCount(heldBy(e.id).reduce((t, x) => t + Math.max(1, x.count || 1), 0)) : e.name)}</b><span>${esc(headWord)}</span></div>`);
    if (k === "camera") {
      const cams = shotsOfScene();
      out.push(F.pick("Shot", "shot", e.shot, cams.map((r) => [r.shot, `${r.number}${r.description ? ` · ${r.description.slice(0, 40)}` : ""}`]), "No Shot"));
      if (!e.shot) out.push(F.btn("New Shot", "newshot"));
      if (!e.shot) out.push(F.text("Name", "label", e.label));
      // **A camera is its shot** (his design, 2026-10-01): its Camera, Lens
      // and a zoom's focal length are the shot's, off the film's own lists —
      // the shot list shows them. With no shot, the plan's camera keeps them.
      const cam = (got.cams || []).find((c) => c.id === e.id) || {};
      const units = got.filmCams || [];
      out.push(F.pick("Camera", "cam_unit", cam.unit || "", units.map((u) => [u.id, u.sensor ? `${u.label} · ${u.sensor}` : u.label]), units.length ? "—" : "No Cameras"));
      out.push(F.pick("Lens", "cam_lens", cam.lens || "", got.lenses || [], (got.lenses || []).length ? "—" : "No Lenses"));
      const shotNow = shotRow(e.shot);
      if (shotNow) {
        // **A camera on the plan is its shot** (the Mac's Details): its
        // frame, its words, and its Size, Angle, Movement, Equipment, Cast.
        const ratio = Number(H.model().project && H.model().project.ratio) || 16 / 9;
        if (shotNow.frame) out.splice(1, 0, `<div class="pdframe${ratio < 1 ? " tall" : ""}">${H.mediaTag(shotNow.frame)}</div>`);
        out.push(F.text("Title", "shot_title", shotNow.title || ""));
        out.push(F.area("Description", "shot_description", shotNow.description || ""));
        out.push(F.pick("Shot Size", "shot_size", H.named(shotNow.size), got.sizes || [], "—"));
        out.push(multiPills("Shot Angle", "angle", (shotNow.angle || []).map(H.named), got.angles || []));
        out.push(F.pick("Movement", "shot_movement", H.named(shotNow.movement), got.movements || [], "—"));
        out.push(F.pick("Equipment", "shot_support", H.named(shotNow.support), got.supports || [], "—"));
        const castCol = Object.entries(got.lists || {}).find(([, c]) => String(c.label).toLowerCase() === "cast");
        if (castCol) {
          const [field, c] = castCol;
          const now = [].concat((shotNow.custom || {})[field] || []).map(H.named).filter(Boolean);
          out.push(multiPills(c.label, `col:${field}`, now, c.terms || []));
        }
      }
      if (cam.zoom && cam.zoom[1] > cam.zoom[0]) {
        const [lo, hi] = cam.zoom, now = Math.round(cam.focal || lo);
        out.push(`<label class="pf"><span>Focal Length</span><span class="pfnum"><input type="range" data-pfocal="1" min="${lo}" max="${hi}" step="1" value="${now}"><input type="number" inputmode="decimal" data-pf="cam_focal" data-num="1" min="${lo}" max="${hi}" step="1" value="${now}" style="width:64px"><i>mm</i></span></label>`);
      } else if (!cam.lens) {
        out.push(F.num("Focal Length", "cam_focal", e.lens > 0 ? e.lens : "", "mm", 1, 2000));
      }
      if (cam.aov) out.push(`<div class="pf"><span>View</span><b class="pread">${cam.aov.toFixed(1)}° <small>${esc(cam.gate_name || "")}</small></b></div>`);
      out.push(F.len("Reach", "reach", e.reach));
      // A camera's own Height and Rig draw nothing on a plot (Back to Paper,
      // Batch 2): kept in the film; the shot's Equipment says how.
      out.push(F.flag("Lens Cone", "cone", e.cone));
      // **Locked to dolly track**: it slides only along the track until unlocked.
      const isTrack = (x) => x && (x.kind === "track" || (x.kind === "set" && String(x.sym).includes("circle-track")));
      if (isTrack(el(e.rig_on))) out.push(`<div class="pf"><span>Track</span><div class="ppills"><b class="pread">On Track</b>${F.btn("Unlock", "unlock")}</div></div>`);
      else if ((got.els || []).some(isTrack)) out.push(F.btn("Ride Track", "ride"));
      out.push(F.colour("Colour", "color", e.color));
    } else if (k === "cast") {
      const who = castNames();
      out.push(F.text("Name", "label", e.label));
      out.push(F.pick("Character", "cast", e.cast, [...who.scene, ...who.film.filter((n) => !who.scene.includes(n))], "—"));
      out.push(F.pills("Pose", "pose", e.pose || "standing", [["standing", "Standing"], ["seated", "Seated"], ["lying", "Lying"]]));
      // **One colour per person, for the whole project** (his ask, 2026-10-17); this piece alone can still wear its own.
      const person = castWho(e);
      if (person) out.push(F.colour(`Colour for ${esc(person)}`, "cast_colour", castColourNow(person)));
      out.push(F.colour(person ? "This Piece" : "Colour", "color", e.color, true));
    } else if (k === "light" && e.sym === (L.frame || "frame")) {
      // **A frame on the plot** (his ask, 2026-10-03): its size and what is
      // in it, and its colour. The lean is dragged on the plan.
      const FT = 0.3048, tall = e.tall > 0 ? e.tall : e.h;
      const sizes = [[4, 4], [6, 6], [8, 8], [12, 12], [12, 20], [20, 20], [20, 40]];
      const now = sizes.find(([a, b]) => Math.abs(a * FT - e.h) < 0.05 && Math.abs(b * FT - tall) < 0.05);
      out.push(`<div class="pfrow">${F.pick("Size", "frame_size", now ? `${now[0]}x${now[1]}` : "", sizes.map(([a, b]) => [`${a}x${b}`, `${a}×${b}`]), now ? "" : "Custom")}${F.pick("Material", "material", e.material || L.material, (L.materials || []).map((m) => [m.id, m.name]))}</div>`);
      // Its Note (2026-10-05): the first line is its size and cloth.
      out.push(F.text("Note", "label", e.label));
      out.push(F.colour("Colour", "color", e.color, true));
    } else if (isGrip(e)) {
      // **Grip** — a flag, net, stand or board: a name and what it is. The
      // lamp's form does nothing to grip (Back to Paper, Batch 2).
      out.push(F.text("Name", "label", e.label));
      out.push(swapField("Kind", e));
      out.push(F.colour("Colour", "color", e.color, true));
    } else if (k === "light") {
      // **One lamp** (Back to Paper, Batch 2): its Symbol with its Type along
      // the top, its Name (its symbol's, the legend's), how many, its Note.
      const type = e.existing ? "existing" : e.practical ? "practical" : "film";
      const look = lookOf(e.look);
      out.push(`<div class="pf"><span>Symbol</span><div class="ppills ptyperow">${[["film", "Film Light"], ["practical", "Practical"], ["existing", "Existing"]].map(([v, n]) =>
        `<button type="button" class="ppill${type === v ? " on" : ""}" data-pset="light_type" data-pv='${JSON.stringify(v)}'>${n}</button>`).join("")}</div>${markPicker(look, "plook")}</div>`);
      if (type !== "film") out.push(F.flag("Off", "off", e.action === "off"));
      out.push(`<datalist id="plightnames">${lightNames().map((n) => `<option value="${esc(n)}">`).join("")}</datalist>
        <label class="pf"><span>Name</span><input type="text" list="plightnames" placeholder="Name" value="${esc(e.lamp_name || "")}" data-pnamelamp="${esc(e.id)}"></label>`);
      // A string of lamps (his ask, 2026-10-04): along a line, bowed if he likes, or round a ring.
      const spread = e.spread || "";
      out.push(`<div class="pf"><span>Spread</span><div class="ppills">${[["", "One"], ["line", "Line"], ["ring", "Ring"]].map(([v, n]) =>
        `<button type="button" class="ppill${spread === v ? " on" : ""}" data-pspread="${v}">${n}</button>`).join("")}</div></div>`);
      if (spread === "line") {
        out.push(F.len("Length", "h", Math.max(e.w, e.h)));
        out.push(F.len("Bend", "curve", e.curve || 0));
      } else if (spread === "ring") {
        out.push(F.len("Width", "w", e.w));
        out.push(F.len("Depth", "h", e.h));
      } else if (TUBE_LEN[look.mark]) {
        // A tube or a panel to scale (the Mac's): as long as its Length.
        out.push(F.len("Length", "h", e.h));
      }
      out.push(F.num("Count", "count", e.count || 1, "", 1, 999, 1));
      // The name is the symbol's; a lamp's own words are a note under it (his call, 2026-10-04).
      if (labelOf(e)) out.push(`<div class="pf"><span>Label</span><div class="ppills"><b class="pread">Shared</b>${F.btn("Own Label", "ownlabel")}</div></div>`);
      out.push(F.text("Note", "label", e.label));
      out.push(gelsField(e, L));
    } else if (k === "set") {
      out.push(swapField("Kind", e));
      out.push(F.text("Name", "label", e.label));
      out.push(F.len("Width", "w", e.w));
      out.push(F.len("Depth", "h", e.h));
    } else if (k === "wall") {
      const c = wallCorners(e);
      const run = e.closed && c.length > 2 ? [...c, c[0]] : c;
      const len = run.slice(1).reduce((t, p, i) => t + Math.hypot(p[0] - run[i][0], p[1] - run[i][1]), 0);
      // A stretch's length, typed — the picked stretch, or a plain wall's only one.
      const s = pickedStretch ?? (run.length === 2 ? 0 : null);
      if (s !== null && s < run.length - 1) out.push(F.len("Length", "wall_length", stretchShown(e, s)));
      else out.push(`<div class="pf"><span>Length</span><b class="pread">${lengthText(len)}</b></div>`);
      if (pickedCorner !== null && pickedCorner < c.length) {
        out.push(`<div class="pfrow">${F.len("X", "corner_x", c[pickedCorner][0])}${F.len("Y", "corner_y", c[pickedCorner][1])}</div>`);
      }
      out.push(F.len("Thickness", "thick", e.thick));
      out.push(pathKindField(e));
      fillFields(out, e);
      out.push(F.text("Name", "label", e.label));
      out.push(F.colour("Colour", "color", e.color, true));
      out.push(F.num("Rotation", "pick_rot", Math.round(heading(e) * 100) / 100, "°", 0, 360));
    } else if (k === "door" || k === "window" || k === "opening") {
      out.push(F.len("Width", "w", e.w));
      if (k === "door") {
        const slides = Boolean(e.slide), sw = Number(e.swing ?? 90), kind = doorKind(e);
        out.push(F.pills("Style", "door_kind", kind, DOOR_KINDS));
        // Shut is no swing, no slide; a sliding door also stops halfway.
        const state = sw <= 0.5 ? "closed" : slides && sw < 89.5 ? "half" : "open";
        out.push(F.pills("State", "door_state", state, slides ? [["closed", "Closed"], ["half", "Half"], ["open", "Open"]] : [["closed", "Closed"], ["open", "Open"]]));
        if (!slides && sw > 0.5) out.push(F.num("Swing", "swing", e.swing, "°", 0, 180));
        const paired = kind === "double" || kind === "center";
        out.push(`<div class="pdbtns">${paired ? "" : F.btn(kind === "pocket" ? "Flip Pocket" : slides ? "Flip Direction" : "Flip Hinge", "hinge")}${F.btn("Flip Side", "side")}</div>`);
      } else out.push(`<div class="pdbtns">${F.btn("Flip Side", "side")}</div>`);
    } else if (k === "track") {
      out.push(`<div class="pf"><span>Length</span><b class="pread">${lengthText(Math.hypot(e.x2 - e.x, e.y2 - e.y))}</b></div>`);
      out.push(F.len("Gauge", "thick", e.thick));
      out.push(F.text("Name", "label", e.label));
    } else if (k === "road") {
      // A road on a plot (his ask, 2026-10-04): two kerbs and a name; its kind is a width to start from.
      out.push(F.text("Name", "label", e.label));
      const kinds = [[9.144, "Street"], [4.572, "Alley"], [3.048, "Driveway"], [1.2192, "Path"]];
      const kind = (kinds.find(([w]) => Math.abs((e.thick || 0) - w) < 0.05) || [""])[0];
      out.push(F.pills("Kind", "thick", kind, kinds));
      out.push(F.len("Width", "thick", e.thick));
    } else if (k === "text" && (g.els || []).some((l) => l.tie_to === e.id && l.kind === "light")) {
      // **A shared label** (his ask, 2026-10-04): it is named by its lights' symbol; its note is theirs.
      const lamps = (g.els || []).filter((l) => l.tie_to === e.id && l.kind === "light");
      out.push(`<div class="pf"><span>Shared Label</span><div class="ppills">${F.btn("Own Label", "ownlabelall")}</div></div>`);
      out.push(`<datalist id="plightnames">${lightNames().map((n) => `<option value="${esc(n)}">`).join("")}</datalist>
        <label class="pf"><span>Name</span><input type="text" list="plightnames" placeholder="Name" value="${esc(lamps[0].lamp_name || "")}" data-pnamelamp="${esc(lamps.map((l) => l.id).join(" "))}"></label>`);
      out.push(`<label class="pf"><span>Note</span><input type="text" data-plabnote="${esc(lamps[0].id)}" value="${esc(lamps[0].label || "")}"></label>`);
    } else if (k === "text" || k === "note") {
      out.push(F.area("Text", "text", e.text));
      // **Regular · Large** (Back to Paper, Batch 2): a name's size, or larger.
      out.push(`<div class="pf"><span>Size</span><div class="ppills">${[[WORDS_REGULAR, "Regular", (e.size || 0) < LARGE_AT], [WORDS_LARGE, "Large", (e.size || 0) >= LARGE_AT]].map(([v, n, on]) =>
        `<button type="button" class="ppill${on ? " on" : ""}" data-pset="size" data-pv='${v}'>${n}</button>`).join("")}</div></div>`);
      out.push(F.num("Points", "words_pt", Math.round((e.size || WORDS_REGULAR) * 1.5), "pt", 4, 200, 1));
      out.push(F.pills("Align", "align", e.align === "centre" ? "" : e.align || "", [["left", "Left"], ["", "Centre"], ["right", "Right"]]));
      out.push(F.colour("Colour", "color", e.color, true));
    } else if (k === "arrow") {
      out.push(F.text("Name", "label", e.label));
      out.push(F.pills("Heads", "head", e.head || "end", [["end", "One"], ["both", "Both"], ["none", "None"]]));
      lineStyle(out, e);
    } else if (k === "measure") {
      // **The Ruler**: its whole length, then each marker — what it is
      // locked to, or Free — with the distance to the next.
      const c = wallCorners(e);
      let total = 0;
      for (let i = 1; i < c.length; i++) total += Math.hypot(c[i][0] - c[i - 1][0], c[i][1] - c[i - 1][1]);
      out.push(`<div class="pf"><span>Length</span><b class="pread">${lengthText(total)}</b></div>`);
      out.push(F.flag("Behind Everything", "under", e.under));
      const pieces = (got.els || []).filter((t) => !LINE_KINDS.has(t.kind) && !["cable", "stroke", "image", "text", "note", "shape"].includes(t.kind) && !t.hidden);
      c.forEach((p, i) => {
        const next = c[i + 1] ? ` · ${lengthText(Math.hypot(c[i + 1][0] - p[0], c[i + 1][1] - p[1]))}` : "";
        out.push(F.pick(`Marker ${i + 1}${next}`, `pin${i}`, (e.pins || [])[i] || "", pieces.map((t) => [t.id, t.name || word(t.kind)]), "Free"));
      });
      out.push(F.text("Name", "label", e.label));
    } else if (k === "shape") {
      out.push(F.text("Name", "label", e.label));
      out.push(F.flag("Fill", "fill", e.fill));
      out.push(`<div class="pfrow">${F.len("Width", "w", e.w)}${F.len("Depth", "h", e.h)}</div>`);
      lineStyle(out, e);
    } else if (k === "cable" || k === "stroke") {
      if (isPath(e)) out.push(pathKindField(e));
      lineStyle(out, e);
      if (k === "cable" || (isPath(e) && e.closed)) out.push(F.text("Name", "label", e.label));
      if (isPath(e)) fillFields(out, e);
    } else if (k === "image") {
      out.push(F.pills("Show As", "role", e.role === "photo" ? "photo" : "", [["", "Background"], ["photo", "Photo"]]));
      out.push(F.num("Opacity", "opacity", Math.round((e.opacity ?? 1) * 100), "%", 0, 100));
      out.push(`<div class="pfrow">${F.len("Width", "w", e.w)}${F.len("Depth", "h", e.h)}</div>`);
    }
    // **Exact spots** (the Mac's Position): where it stands, in the film's
    // units, typed or stepped a grid step at a time.
    if (!LINE_KINDS.has(k) && !["cable", "stroke", "note"].includes(k) && !isShared(e)) {
      const [px0, py0] = e.at || [e.x, e.y];
      const axis = (label, key, v) => `<label class="pf"><span>${label}</span><span class="pfnum"><input type="text" data-pf="${key}" data-len="1" value="${esc((v < -0.0005 ? "-" : "") + lengthText(Math.abs(v)))}"><button type="button" class="pstep" data-pnudge="${key}" data-by="-1" aria-label="Less">−</button><button type="button" class="pstep" data-pnudge="${key}" data-by="1" aria-label="More">+</button></span></label>`;
      out.push(`<div class="pfrow">${axis("X", "pos_x", px0)}${axis("Y", "pos_y", py0)}</div>`);
    }
    if (e.kind === "camera") out.push(F.flag("Frame on Plan", "frame_on", e.frame_on));
    if (hasName(e) || isShared(e)) {
      // **The label** (Back to Paper, Batch 2): one size and weight on a plot,
      // so only shown or hidden, and put back where it sat. Name Size and
      // Bold are kept in the film, not offered.
      out.push(`<div class="pf"><span>Label</span><div class="ppills">
        <button type="button" class="ppill" data-pset="label_hidden" data-pv='${!e.label_hidden}'>${e.label_hidden ? "Show Label" : "Hide Label"}</button>
        ${e.label_dx || e.label_dy || e.label_size ? `<button type="button" class="ppill" data-pnamereset="1">Reset Label</button>` : ""}</div></div>`);
    }
    if (e.group) {
      out.push(`<div class="pf"><span>Group</span><div class="prowline"><b class="pread">${esc(e.groupName || "Group")}</b><button type="button" class="ppill" data-pdo="leavegroup">Remove from Group</button></div></div>`);
    } else {
      const groups = [...new Map((g.els || []).filter((x) => x.group).map((x) => [x.group, x.groupName || "Group"])).entries()];
      if (groups.length) out.push(F.pick("Add to Group", "joingroup", "", groups, "—"));
    }
    if (e.aim) {
      const t = el(e.aim);
      out.push(`<div class="pf"><span>Aimed At</span><div class="prowline"><b class="pread">${esc(t ? t.name : "—")}</b><button type="button" class="ppill" data-pset="aim" data-pv='""'>Stop Aiming</button></div></div>`);
    }
    // **Folded under More** (his call, 2026-10-04: a plain label showed about
    // fifteen controls): turning, fading, locking, copying, hiding, stacking.
    // Right-click has the same verbs. Delete stays in sight.
    const later = [];
    if (!LINE_KINDS.has(k) && !["cable", "stroke"].includes(k)) {
      const [, , arot] = e.at || [e.x, e.y, e.rot];
      later.push(F.num("Rotation", H.beat() > 1 ? "beatrot" : "rot", Math.round(((arot % 360) + 360) % 360), "°", 0, 360));
    }
    // **See through it** (SL-1334, his ask 2026-10-01: an overhead light
    // over the set must not hide what is under it). Every piece fades, lamps
    // and frames too, never its name (Ref 1505).
    if (k !== "image") later.push(F.num("Opacity", "opacity", Math.round((e.opacity ?? 1) * 100), "%", 10, 100));
    // Every piece's Note (2026-10-05), under its name on the plan.
    if (notable(e)) out.push(F.text("Note", "caption", e.caption || ""));
    if (WALKS.has(k)) {
      // **Its steps** in letter order: picked with a click, put on a beat, taken away; and the next one.
      const sp = stepPicked();
      const rows = (e.seq || []).map((t, i) => `<div class="pbeatrow${sp && sp.i === i ? " on" : ""}"><button type="button" class="lact" data-pgostep="${i}"><b>${esc(t.letter)}</b> ${t.home ? "" : t.turn ? "Turn" : "Move"}</button>`
        + `<select class="pstepbeat" data-pstepbeat="${i}" aria-label="Beat">${stepBeats(e).map((n) => `<option value="${n}"${n === t.beat ? " selected" : ""}>${n ? `Beat ${n}` : "No Beat"}</option>`).join("")}</select>`
        + `${t.home ? "" : `<button type="button" class="lact" data-pstepoff="${i}">Remove</button>`}</div>`).join("");
      out.push(`<div class="pf"><span>Steps</span><div class="pbeatlist">${rows}<div class="ppills"><button type="button" class="ppill" data-pstepadd="move">Add Move</button><button type="button" class="ppill" data-pstepadd="turn">Add Turn</button></div></div></div>`);
    }
    later.push(`<div class="pdbtns">${F.btn(e.locked ? "Unlock" : "Lock", "lock")}${F.btn("Duplicate", "duplicate")}${F.btn("Hide", "hide")}</div>`);
    later.push(layerBtns([e]));
    later.push(`<div class="pf"><span>Arrange</span><div class="ppills">${[["front", "Bring to Front"], ["forward", "Bring Forward"], ["backward", "Send Backward"], ["back", "Send to Back"]].map(([t, n]) =>
      `<button type="button" class="ppill" data-porder="${t}">${n}</button>`).join("")}<button type="button" class="ppill" data-pdo="flipx">Flip Horizontal</button><button type="button" class="ppill" data-pdo="flipy">Flip Vertical</button></div></div>`);
    out.push(`<details class="pdmore" data-pdmore="1"${detMore ? " open" : ""}><summary>More</summary>${later.join("")}</details>`);
    out.push(`<div class="pdbtns">${F.btn("Delete", "delete")}</div>`);
    return `<div class="pdetails">${out.join("")}</div>`;
  }

  /**
   * A stretch's length as the plan shows it: a closed room's along its
   * inside face (square corners lose half the wall at each end), else corner
   * to corner — what `wall_length` takes.
   */
  function stretchShown(e, s) {
    const c = wallCorners(e);
    const [a, b] = [c[s], c[(s + 1) % c.length]];
    const l = Math.hypot(b[0] - a[0], b[1] - a[1]);
    return e.closed && c.length > 2 ? Math.max(l - (e.thick || 0), 0) : l;
  }

  /** Whether a piece carries a name on the plan — what Show Name and the name's size speak to. */
  function hasName(e) {
    return ["camera", "cast", "light", "set", "track", "road", "arrow", "measure", "shape", "cable", "door", "window", "wall"].includes(e.kind);
  }

  function lineStyle(out, e) {
    out.push(F.colour("Colour", "color", e.color, true));
    out.push(F.num("Weight", "weight", e.weight, "pt", 0.5, 20, 0.5));
    out.push(F.pick("Line", "dash", e.dash || "", [["", "Solid"], ["dashed", "Dashed"], ["dotted", "Dotted"]]));
  }

  function gelsField(e, L) {
    const have = e.gels || [];
    const name = (id) => ((L.gels || []).find((g) => g.id === id) || { name: id }).name;
    return `<div class="pf"><span>Gel</span><div class="pgels">${have.map((id, i) =>
      `<span class="pgel">${esc(name(id))}<button type="button" class="lact" data-pungel="${i}">Remove</button></span>`).join("")}
      <select data-paddgel="1"><option value="">Add Gel</option>${(L.gels || []).map((g) => `<option value="${esc(g.id)}">${esc(g.name)}</option>`).join("")}</select></div></div>`;
  }

  /** Nothing picked: the plan's own settings — as the Mac's View menu and Sun panel keep them, in the film. */
  function shotsOfScene() {
    // A scene's further diagram stands for the scene: its shots are the scene's.
    const s = sceneOf(chosen());
    const id = s ? s.id : chosen();
    const out = [];
    for (const g of H.model().groups || []) for (const r of g.rows || []) if (r.shot && r.sceneId === id) out.push(r);
    return out;
  }
  function castNames() {
    const said = json(call("plan_cast", String(chosen())));
    return { scene: (said && said.scene) || [], film: (said && said.film) || [] };
  }

  function wireSide(s, g) {
    // A tab changed: the bar steps back in when Details closes.
    s.querySelectorAll("[data-ptab]").forEach((b) => b.addEventListener("click", () => { tab = b.dataset.ptab; sideKey = ""; side(got); float(); }));
    s.querySelectorAll("[data-pel]").forEach((b) => {
      b.addEventListener("click", (ev) => {
        if (ev.target.closest(".lact")) return;
        pickOne(b.dataset.pel, true, ev.shiftKey || ev.metaKey);
        // A phone's list is under the plan: up to the plan, the piece in sight.
        if (H.narrow() && !editor()) {
          const vp = root.querySelector(".planvp");
          if (vp) vp.scrollIntoView({ block: "center", behavior: "smooth" });
          keepAbove(b.dataset.pel);
        }
      });
      b.addEventListener("keydown", (ev) => { if (ev.key === "Enter") pickOne(b.dataset.pel, true); });
    });
    const lf = s.querySelector("[data-pfindlayers]");
    if (lf) {
      findLayers(s);
      lf.addEventListener("input", () => { layerFind = lf.value; findLayers(s); });
      lf.addEventListener("keydown", (ev) => { if (ev.key === "Escape") { layerFind = ""; lf.value = ""; findLayers(s); lf.blur(); } });
    }
    s.querySelectorAll("[data-pshow]").forEach((b) => b.addEventListener("click", () => {
      const k = b.dataset.pshow;
      if (off.has(k)) off.delete(k); else off.add(k);
      try { localStorage.setItem(OFF_KEY, JSON.stringify([...off])); } catch { /* kept for this visit only */ }
      paint();
    }));
    s.querySelectorAll("[data-pshowall]").forEach((b) => b.addEventListener("click", () => {
      off.clear();
      try { localStorage.removeItem(OFF_KEY); } catch { /* nothing kept */ }
      paint();
    }));
    s.querySelectorAll("[data-pgoshot]").forEach((b) => b.addEventListener("click", () => H.showShot(b.dataset.pgoshot)));
    s.querySelectorAll("[data-padd]").forEach((b) => b.addEventListener("click", () => { setTool(b.dataset.padd); toast("Click the plan to put it down"); }));
    s.querySelectorAll("[data-paddshot]").forEach((b) => b.addEventListener("click", () => edit({ op: "add_shot" }, { label: "Add Shot", record: false })));
    // An unplaced shot dragged onto the plan: its camera put down there (the Mac's).
    s.querySelectorAll(".pshot.unplaced[draggable]").forEach((r) => r.addEventListener("dragstart", (ev) => {
      ev.dataTransfer.setData("text/x-plan-shot", r.dataset.pshotrow);
      ev.dataTransfer.effectAllowed = "copy";
    }));
    // A shot's own menu: Remove Camera or Place on Plan, and Show in Shot List.
    s.querySelectorAll("[data-pshotrow]").forEach((r) => r.addEventListener("contextmenu", (ev) => {
      ev.preventDefault();
      const shot = r.dataset.pshotrow;
      const mine = ((got && got.cams) || []).filter((c) => c.shot === shot);
      const items = [];
      if (editor()) {
        if (mine.length) items.push({ label: "Remove Camera", pick: () => remove(mine.map((c) => c.id)) });
        else items.push({ label: "Place on Plan", pick: () => { const pl = r.querySelector("[data-pplace]"); if (pl) pl.click(); } });
      }
      items.push({ label: "Show in Shot List", pick: () => H.showShot(shot) });
      openMenu(null, items, true, [ev.clientX, ev.clientY]);
    }));
    // A shot's camera put down in the middle of the view; taken away, the shot stays.
    s.querySelectorAll("[data-pplace]").forEach((b) => b.addEventListener("click", (ev) => {
      ev.stopPropagation();
      const bx = box();
      if (!bx || !view()) return;
      const [x, y] = snapped(...toStored(bx.w / 2, bx.h / 2), false);
      const n = (got.els || []).filter((e) => e.kind === "camera").length;
      edit({ op: "add", els: [{ kind: "camera", x, y, rot: 0, color: PALETTE[n % PALETTE.length], shot: b.dataset.pplace }] }, { label: "Place Shot", select: true });
    }));
    s.querySelectorAll("[data-punplace]").forEach((b) => b.addEventListener("click", (ev) => {
      ev.stopPropagation();
      remove(((got && got.cams) || []).filter((c) => c.shot === b.dataset.punplace).map((c) => c.id));
    }));
    s.querySelectorAll("[data-pbackdrop]").forEach((r) => {
      const keep = () => { try { localStorage.setItem(BACKDROP_KEY, String(backdrop)); } catch { /* this visit only */ } };
      r.addEventListener("input", () => { backdrop = Number(r.value); lightBackdrop(root.querySelector(".planvp")); });
      r.addEventListener("change", () => { keep(); sideKey = ""; side(got); });
    });
    s.querySelectorAll("[data-pbackdropreset]").forEach((b) => b.addEventListener("click", () => {
      backdrop = BACKDROP_DEFAULT;
      try { localStorage.removeItem(BACKDROP_KEY); } catch { /* nothing kept */ }
      lightBackdrop(root.querySelector(".planvp")); sideKey = ""; side(got);
    }));
    s.querySelectorAll("[data-pframes]").forEach((b) => b.addEventListener("click", () => {
      frames = !frames;
      try { localStorage.setItem(FRAMES_KEY, frames ? "1" : "0"); } catch { /* this visit only */ }
      sideKey = ""; paint();
    }));
    if (!editor()) return;
    // One piece, or one whole group: a group is kept as one favorite (his custom objects, 2026-10-04).
    const sameGroup = picks.length > 1 && picks.every((id) => { const x = el(id); return x && x.group && x.group === (el(picks[0]) || {}).group; });
    const one = picks.length === 1 || sameGroup ? el(picks[0]) : null;
    const set = (key, value) => {
      if (key === "pick_rot") {
        // A wall's or several pieces' heading typed: turned by the difference.
        const first = el(picks[0]);
        let by = (Number(value) - heading(first)) % 360;
        if (by > 180) by -= 360; else if (by < -180) by += 360;
        if (Math.abs(by) > 1e-6) turnPickBy(by);
        return;
      }
      if (key === "pick_color") return edit({ op: "update", ids: picks.slice(), set: { color: value } }, { label: "Change Colour" });
      if (key === "cast_colour" && one) { const who = castWho(one); if (who) setCastColour(who, value); return; }
      if (key === "pick_opacity") {
        const o = Math.min(Math.max(Number(value) / 100, 0.1), 1);
        return edit({ op: "update", ids: picks.slice(), set: { opacity: o } }, { label: "Change Opacity" });
      }
      if (!one) return setting(key, value);
      if (key === "path_as") return edit({ op: "path_as", id: one.id, as: value }, { label: "Type" });
      if (key === "fill_on" || key === "fill_colour") {
        const isWall = one.kind === "wall";
        if (key === "fill_on") {
          const on = !(isWall ? Boolean(one.fill_color) : Boolean(one.fill));
          return edit({ op: "update", ids: [one.id], set: isWall ? { fill_color: on ? "auto" : "" } : on ? { fill: true } : { fill: false, fill_color: "" } }, { label: "Fill" });
        }
        return edit({ op: "update", ids: [one.id], set: isWall ? { fill_color: value || "auto" } : { fill: true, fill_color: value } }, { label: "Fill Colour" });
      }
      if (key === "fill_alpha") return edit({ op: "update", ids: [one.id], set: { fill_alpha: Math.min(Math.max(Number(value), 2), 100) / 100 } }, { label: "Fill Opacity" });
      if (key === "words_pt") return edit({ op: "update", ids: [one.id], set: { size: Math.min(Math.max(Number(value) || 12, 4), 200) / 1.5 } }, { label: "Size" });
      if (key === "door_kind") return edit({ op: "update", ids: [one.id], set: doorChange(one, String(value)) }, { label: "Style" });
      if (key === "door_state") return edit({ op: "update", ids: [one.id], set: { swing: value === "closed" ? 0 : value === "half" ? 45 : 90 } }, { label: "State" });
      if (key === "pos_x" || key === "pos_y") {
        const [px0, py0] = one.at || [one.x, one.y];
        const to = Number(value);
        if (!Number.isFinite(to)) return;
        const dx = key === "pos_x" ? to - px0 : 0, dy = key === "pos_y" ? to - py0 : 0;
        if (Math.abs(dx) + Math.abs(dy) < 1e-9) return;
        return edit({ op: "move", ids: [one.id], dx, dy }, { label: "Move" });
      }
      if (key === "step_beat" || key === "step_rot" || key === "step_pose") {
        // The picked step's own fields (`stepDetails`).
        const sp = stepPicked();
        if (!sp) return;
        if (key === "step_beat") return edit({ op: "step_set", id: sp.e.id, step: sp.i, beat: Number(value) || 0 }, { label: "Set Beat" });
        if (key === "step_pose") return edit({ op: "step_set", id: sp.e.id, step: sp.i, pose: String(value) }, { label: "Pose" });
        const rot = ((Number(value) % 360) + 360) % 360;
        return edit({ op: "step_set", id: sp.e.id, step: sp.i, rot }, { label: "Turn" });
      }
      if (["shot_size", "shot_movement", "shot_title", "shot_description", "shot_support"].includes(key)) {
        const field = key.slice(5);
        return edit({ op: "camera_shot", id: one.id, set: { [field]: value } }, { label: { size: "Size", movement: "Movement", title: "Title", description: "Description", support: "Equipment" }[field], record: false });
      }
      if (key === "cam_unit" || key === "cam_lens" || key === "cam_focal") {
        const field = { cam_unit: "unit", cam_lens: "lens", cam_focal: "focal" }[key];
        return edit({ op: "camera_shot", id: one.id, set: { [field]: key === "cam_focal" ? (Number(value) > 0 ? Number(value) : "") : value } }, { label: "Camera", record: false });
      }
      if (/^pin\d+$/.test(key) && one.kind === "measure") {
        // A marker locked to a piece, or let go where it stands.
        const i = Number(key.slice(3)), c = wallCorners(one)[i];
        if (c) return edit({ op: "wall_corner", id: one.id, corner: i, x: c[0], y: c[1], on: value || "" }, { label: value ? "Lock Marker" : "Unlock Marker" });
      }
      if (key === "wall_length") return edit({ op: "wall_length", id: one.id, stretch: pickedStretch ?? 0, length: Math.max(value, 0.05) }, { label: "Length" });
      if (key === "corner_x" || key === "corner_y") {
        const c = wallCorners(one)[pickedCorner];
        if (!c) return;
        return edit({ op: "wall_corner", id: one.id, corner: pickedCorner, x: key === "corner_x" ? value : c[0], y: key === "corner_y" ? value : c[1] }, { label: "Move Corner" });
      }
      if (key === "beatrot") return turnTo(one, value);
      if (key === "joingroup") {
        const members = (got.els || []).filter((x) => x.group === value);
        if (!members.length) return;
        return edit({ op: "update", ids: [one.id], set: { group: value, group_name: members[0].groupName || "" } }, { label: "Add to Group" });
      }
      // The lighting plot's own fields.
      if (key === "light_type") {
        const set = { existing: value === "existing", practical: value === "practical", mark_ink: "" };
        if (value === "film") set.action = "";
        return edit({ op: "update", ids: [one.id], set }, { label: "Type" });
      }
      if (key === "off") return edit({ op: "update", ids: [one.id], set: { action: value ? "off" : "" } }, { label: value ? "Off" : "On" });
      if (key === "frame_size") {
        const [a, b] = String(value).split("x").map(Number);
        if (a > 0 && b > 0) return edit({ op: "update", ids: [one.id], set: { h: a * 0.3048, tall: b * 0.3048 } }, { label: "Frame Size" });
        return;
      }
      const patch = { [key]: value };
      if (key === "sym") {
        const sym = (library().symbols || []).find((x) => x.id === value);
        if (sym) return edit({ op: "swap", ids: [one.id], sym: value }, { label: `Swap to ${sym.name}` });
      }
      edit({ op: "update", ids: [one.id], set: patch }, { label: `Change ${label(key)}` });
    };
    s.querySelectorAll("[data-pf]").forEach((i) => {
      const commit = () => {
        const key = i.dataset.pf;
        let v = i.value;
        if (i.dataset.num) { v = parseFloat(v); if (!Number.isFinite(v)) { if (key !== "lens" && key !== "cam_focal") return; v = 0; } if (key === "opacity") v /= 100; if (key === "grid") v = Number(v); }
        else if (i.dataset.len) { v = parseLength(v); if (v === null || !Number.isFinite(v)) return; }
        else if (key === "grid") v = Number(v);
        set(key, v);
      };
      if (i.tagName === "SELECT" || i.type === "color") i.addEventListener("change", commit);
      else {
        i.addEventListener("change", commit);
        i.addEventListener("keydown", (ev) => { ev.stopPropagation(); if (ev.key === "Enter" && i.tagName !== "TEXTAREA") { i.blur(); } if (ev.key === "Escape") i.blur(); });
      }
    });
    s.querySelectorAll("[data-pfocal]").forEach((r) => {
      const n = r.parentElement.querySelector('[data-pf="cam_focal"]');
      r.addEventListener("input", () => { if (n) n.value = r.value; });
      r.addEventListener("change", () => set("cam_focal", Number(r.value)));
    });
    s.querySelectorAll("[data-pflag]").forEach((b) => b.addEventListener("click", () => {
      const key = b.dataset.pflag;
      const now = one ? Boolean(one[key]) : Boolean((got.settings || {})[key]);
      set(key, !now);
    }));
    s.querySelectorAll("[data-pdmore]").forEach((d) => d.addEventListener("toggle", () => { detMore = d.open; }));
    s.querySelectorAll("[data-plengths]").forEach((b) => b.addEventListener("click", () => {
      const all = b.dataset.plengths === "true";
      edit({ op: "settings", set: { dims: all, all_lengths: all } }, { label: "Lengths" });
    }));
    s.querySelectorAll("[data-pnamelamp]").forEach((i) => {
      // One lamp, or every lamp on a shared label (2026-10-15: a Name is
      // that lamp's alone, so the label's field names each of its own).
      i.addEventListener("change", () => {
        const ids = i.dataset.pnamelamp.split(" ").filter(Boolean).map(current);
        const name = i.value.trim();
        const ops = ids.map((id) => ({ op: "name_lamp", id, name }));
        edit(ops.length === 1 ? ops[0] : { op: "batch", ops }, { label: "Name" });
      });
      i.addEventListener("keydown", (ev) => { ev.stopPropagation(); if (ev.key === "Enter" || ev.key === "Escape") i.blur(); });
    });
    s.querySelectorAll("[data-plabnote]").forEach((i) => i.addEventListener("change", () => {
      edit({ op: "update", ids: [i.dataset.plabnote], set: { label: i.value.trim() } }, { label: "Note" });
    }));
    s.querySelectorAll("[data-pspread]").forEach((b) => b.addEventListener("click", () => {
      if (!one) return;
      const v = b.dataset.pspread, was = one.spread || "";
      if (v === was) return;
      const set = { spread: v };
      if (v === "line") Object.assign(set, { w: 0.3, h: Math.max(one.h || 0, 3), curve: 0, count: Math.max(one.count || 1, 6) });
      if (v === "ring") Object.assign(set, { w: 3, h: 3, count: Math.max(one.count || 1, 8) });
      if (v === "") Object.assign(set, { w: 0.3, h: 0.3, curve: 0 });
      edit({ op: "update", ids: [one.id], set }, { label: "Spread" });
    }));
    s.querySelectorAll("[data-pset]").forEach((b) => b.addEventListener("click", () => set(b.dataset.pset, JSON.parse(b.dataset.pv))));
    // X and Y stepped a grid step at a time (the Mac's Position steppers).
    s.querySelectorAll("[data-pnudge]").forEach((b) => b.addEventListener("click", () => {
      const e = el(picks[0]);
      if (!e) return;
      const [px0, py0] = e.at || [e.x, e.y];
      const v = b.dataset.pnudge === "pos_x" ? px0 : py0, st = snapStep();
      set(b.dataset.pnudge, Math.round((v + Number(b.dataset.by) * st) / st) * st);
    }));
    // A term ticked on or off a shot's Angle or Cast, written through its camera.
    s.querySelectorAll("[data-pmulti]").forEach((b) => b.addEventListener("click", () => {
      const e = el(picks[0]);
      if (!e || !e.shot) return;
      const ons = [...s.querySelectorAll(`[data-pmulti="${CSS.escape(b.dataset.pmulti)}"].on`)].map((x) => x.dataset.pv);
      const t = b.dataset.pv;
      const next = ons.includes(t) ? ons.filter((x) => x !== t) : [...ons, t];
      const key = b.dataset.pmulti;
      const set = key === "angle" ? { angle: next.join(", ") } : { columns: { [key.slice(4)]: next.join(", ") } };
      b.classList.toggle("on");
      edit({ op: "camera_shot", id: e.id, set }, { label: key === "angle" ? "Shot Angle" : "Cast", record: false });
    }));
    // The plot: a lamp's mark, a legend line re-marked or named, a colour's meaning.
    s.querySelectorAll("[data-plook]").forEach((b) => b.addEventListener("click", () => {
      const l = lookOf(b.dataset.plook);
      if (one) edit({ op: "update", ids: [one.id], set: { mark: l.mark, mark_ink: "", mark_fill: l.solid ? "solid" : "open", ...(TUBE_LEN[l.mark] && Math.max(one.w || 0, one.h || 0) < 0.4 ? { w: 0.3, h: TUBE_LEN[l.mark] } : {}) } }, { label: "Symbol" });
    }));
    wireLetters(s);
    s.querySelectorAll("[data-plegto]").forEach((b) => b.addEventListener("click", () => {
      const from = b.closest(".plegrow") && b.closest(".plegrow").querySelector("[data-plegname]");
      if (from) edit({ op: "legend", key: from.dataset.plegname, to: b.dataset.plegto }, { label: "Symbol" });
    }));
    s.querySelectorAll("[data-plegname]").forEach((i) => {
      const commit = () => { if (i.dataset.plegname) edit({ op: "legend", key: i.dataset.plegname, name: i.value.trim() }, { label: "Name" }); };
      i.addEventListener("change", commit);
      i.addEventListener("keydown", (ev) => { ev.stopPropagation(); if (ev.key === "Enter" || ev.key === "Escape") i.blur(); });
    });
    s.querySelectorAll("[data-pcolname]").forEach((i) => {
      i.addEventListener("change", () => edit({ op: "legend", key: `colour:${i.dataset.pcolname}`, name: i.value.trim() }, { label: "Colour Name" }));
      i.addEventListener("keydown", (ev) => { ev.stopPropagation(); if (ev.key === "Enter" || ev.key === "Escape") i.blur(); });
    });
    s.querySelectorAll("[data-pswap]").forEach((b) => b.addEventListener("click", () => (swap && swap.id === b.dataset.pswap ? closeSwap() : openSwap(b.dataset.pswap))));
    s.querySelectorAll("[data-palign]").forEach((b) => b.addEventListener("click", () => edit({ op: "align", ids: picks.slice(), to: b.dataset.palign }, { label: "Align" })));
    s.querySelectorAll("[data-pdist]").forEach((b) => b.addEventListener("click", () => edit({ op: "distribute", ids: picks.slice(), axis: b.dataset.pdist }, { label: "Space Evenly" })));
    s.querySelectorAll("[data-porder]").forEach((b) => b.addEventListener("click", () => edit({ op: "order", ids: picks.slice(), to: b.dataset.porder }, { label: "Arrange" })));
    s.querySelectorAll("[data-pdo]").forEach((b) => b.addEventListener("click", () => doThing(b.dataset.pdo, one)));
    s.querySelectorAll("[data-pnamereset]").forEach((b) => b.addEventListener("click", () => edit({ op: "update", ids: [one.id], set: { label_dx: 0, label_dy: 0, label_size: 0 } }, { label: "Reset Name" })));
    s.querySelectorAll("[data-pstep]").forEach((b) => b.addEventListener("click", () => setting("step", Number(b.dataset.pstep))));
    s.querySelectorAll("[data-pevery]").forEach((b) => b.addEventListener("click", () => {
      const key = b.dataset.pevery;
      const now = Boolean((got.settings || {})[key]);
      edit({ op: "everywhere", key, value: !now }, { label: key === "beams" ? "Light Beams" : "Light Levels" });
      toast(`${key === "beams" ? "Light beams" : "Light levels"} ${now ? "off" : "on"} in every scene`);
    }));
    s.querySelectorAll("[data-psunreset]").forEach((b) => b.addEventListener("click", () => setting(b.dataset.psunreset, "")));
    s.querySelectorAll("[data-pprint]").forEach((b) => b.addEventListener("click", printPlan));
    s.querySelectorAll("[data-pungel]").forEach((b) => b.addEventListener("click", () => {
      const gels = (one.gels || []).slice(); gels.splice(Number(b.dataset.pungel), 1);
      edit({ op: "update", ids: [one.id], set: { gels } }, { label: "Remove Gel" });
    }));
    const addGel = s.querySelector("[data-paddgel]");
    if (addGel) addGel.addEventListener("change", () => {
      if (!addGel.value) return;
      edit({ op: "update", ids: [one.id], set: { gels: [...(one.gels || []), addGel.value] } }, { label: "Add Gel" });
    });
    s.querySelectorAll("[data-pgostep]").forEach((b) => b.addEventListener("click", () => {
      const i = Number(b.dataset.pgostep), t = (one.seq || [])[i];
      pickedStep = t && !t.home ? { id: one.id, i } : null;
      if (t && t.beat > 0) H.setBeat(t.beat);
      sideKey = ""; paint();
    }));
    s.querySelectorAll("[data-pstepbeat]").forEach((b) => b.addEventListener("change", () => edit({ op: "step_set", id: one.id, step: Number(b.dataset.pstepbeat), beat: Number(b.value) }, { label: "Set Beat" })));
    s.querySelectorAll("[data-pstepoff]").forEach((b) => b.addEventListener("click", () => {
      const i = Number(b.dataset.pstepoff), t = (one.seq || [])[i];
      edit({ op: "step_remove", id: one.id, step: i }, { label: `Remove ${t ? t.letter : "Step"}` });
      pickedStep = null; sideKey = ""; paint();
    }));
    s.querySelectorAll("[data-pstepadd]").forEach((b) => b.addEventListener("click", () => addStep(one, b.dataset.pstepadd === "turn", false)));
    s.querySelectorAll("[data-lhide]").forEach((b) => b.addEventListener("click", () => {
      const e = el(b.dataset.lhide);
      edit({ op: "update", ids: [e.id], set: { hidden: !e.hidden } }, { label: e.hidden ? "Show" : "Hide" });
    }));
    s.querySelectorAll("[data-llock]").forEach((b) => b.addEventListener("click", () => {
      const e = el(b.dataset.llock);
      edit({ op: "update", ids: [e.id], set: { locked: !e.locked } }, { label: e.locked ? "Unlock" : "Lock" });
    }));
    s.querySelectorAll("[data-pungroup]").forEach((b) => b.addEventListener("click", () => {
      const ids = (got.els || []).filter((e) => e.group === b.dataset.pungroup).map((e) => e.id);
      edit({ op: "ungroup", ids }, { label: "Ungroup" });
    }));
    s.querySelectorAll("[data-prename]").forEach((n) => n.addEventListener("dblclick", () => {
      const ids = (got.els || []).filter((e) => e.group === n.dataset.prename).map((e) => e.id);
      const input = document.createElement("input");
      input.type = "text";
      input.className = "prenamebox";
      input.value = n.textContent;
      n.replaceWith(input);
      input.focus(); input.select();
      const done = (keep) => {
        const name = input.value.trim();
        if (keep && name) edit({ op: "update", ids, set: { group_name: name } }, { label: "Rename Group" });
        else { sideKey = ""; side(got); }
      };
      input.addEventListener("keydown", (ev) => { ev.stopPropagation(); if (ev.key === "Enter") done(true); if (ev.key === "Escape") done(false); });
      input.addEventListener("blur", () => done(true));
    }));
    // Restack by dragging a row onto another: just over it.
    let dragged = null;
    const above = (r, ev) => { const b = r.getBoundingClientRect(); return ev.clientY < b.top + b.height / 2; };
    s.querySelectorAll(".planlayer[draggable]").forEach((r) => {
      r.addEventListener("dragstart", (ev) => { dragged = r.dataset.pel; ev.dataTransfer.effectAllowed = "move"; ev.dataTransfer.setData("text/plain", dragged); });
      r.addEventListener("dragover", (ev) => {
        if (!dragged || dragged === r.dataset.pel) return;
        ev.preventDefault();
        const up = above(r, ev);
        r.classList.toggle("dropabove", up); r.classList.toggle("dropbelow", !up);
      });
      r.addEventListener("dragleave", () => r.classList.remove("dropabove", "dropbelow"));
      r.addEventListener("drop", (ev) => {
        ev.preventDefault();
        r.classList.remove("dropabove", "dropbelow");
        if (!dragged || dragged === r.dataset.pel) return;
        const order = { op: "order", ids: [dragged], to: above(r, ev) ? "above" : "below", next: r.dataset.pel };
        const e = el(dragged), group = layerSort === "manual" ? r.dataset.pgrp || "" : (e && e.group) || "";
        // One piece moves in or out of a group with its drop (the Mac's `regroup`).
        if (e && (e.group || "") !== group) {
          const name = ((got.els || []).find((x) => x.group === group) || {}).group_name || "";
          const ops = [{ op: "update", ids: [e.id], set: { group, group_name: group ? name : "" } }];
          const left = e.group ? (got.els || []).filter((x) => x.group === e.group && x.id !== e.id) : [];
          if (left.length === 1) ops.push({ op: "update", ids: [left[0].id], set: { group: "", group_name: "" } });
          ops.push(order);
          edit({ op: "batch", ops }, { label: group ? "Add to Group" : "Remove from Group" });
        } else edit(order, { label: "Restack" });
        dragged = null;
      });
    });
    const sortBy = s.querySelector("[data-playsort]");
    if (sortBy) sortBy.addEventListener("change", () => { layerSort = sortBy.value; sideKey = ""; side(got); });
    s.querySelectorAll("[data-pfold]").forEach((b) => b.addEventListener("click", (ev) => {
      ev.stopPropagation();
      const k = b.dataset.pfold;
      if (foldedGroups.has(k)) foldedGroups.delete(k); else foldedGroups.add(k);
      sideKey = ""; side(got);
    }));
    // A double-click on a row: its name typed, on the plan (the Mac's).
    s.querySelectorAll(".planlayer").forEach((r) => r.addEventListener("dblclick", () => {
      const e = el(r.dataset.pel);
      if (!e || !editor()) return;
      picks = [e.id]; sideKey = ""; paint();
      if (isLamp(e)) setTimeout(() => typeOn(el(e.id), "name"), 0);
      else if (renamable(e)) setTimeout(() => startRename(el(e.id)), 0);
    }));
    // Right-click on a row: the group verbs (the Mac's row menu).
    s.querySelectorAll(".planlayer").forEach((r) => r.addEventListener("contextmenu", (ev) => {
      const e = el(r.dataset.pel);
      if (!e || !editor()) return;
      ev.preventDefault();
      if (!picks.includes(e.id)) { picks = [e.id]; sideKey = ""; paint(); }
      const items = [];
      if (picks.length > 1) items.push({ label: "Group", key: "⌘G", pick: () => edit({ op: "group", ids: picks.slice() }, { label: "Group" }) });
      if (e.group) {
        items.push({ label: "Rename Group…", pick: () => { const n = s.querySelector(`[data-prename="${CSS.escape(e.group)}"]`); if (n) n.dispatchEvent(new MouseEvent("dblclick", { bubbles: true })); } });
        items.push({ label: "Ungroup", key: "⇧⌘G", pick: () => edit({ op: "ungroup", ids: (got.els || []).filter((x) => x.group === e.group).map((x) => x.id) }, { label: "Ungroup" }) });
        items.push({ label: "Remove from Group", pick: () => doThing("leavegroup", e) });
      }
      const groups = [...new Map((got.els || []).filter((x) => x.group && x.group !== e.group).map((x) => [x.group, x.groupName || x.group_name || "Group"]))];
      if (groups.length) {
        items.push({ rule: true }, { head: "Add to Group" });
        for (const [gid, name] of groups) items.push({ label: name, pick: () => {
          const ops = [{ op: "update", ids: [e.id], set: { group: gid, group_name: ((got.els || []).find((x) => x.group === gid) || {}).group_name || name } }];
          const left = e.group ? (got.els || []).filter((x) => x.group === e.group && x.id !== e.id) : [];
          if (left.length === 1) ops.push({ op: "update", ids: [left[0].id], set: { group: "", group_name: "" } });
          edit({ op: "batch", ops }, { label: "Add to Group" });
        } });
      }
      if (items.length) openMenu(null, items, true, [ev.clientX, ev.clientY]);
    }));
    if (editingText) {
      const t = s.querySelector("[data-pf='text']");
      if (t) { t.focus(); t.select(); }
      editingText = null;
    }
  }

  function label(key) {
    return { label: "Name", color: "Colour", lens: "Lens", reach: "Reach", sensor: "Sensor", w: "Width", h: "Depth", rot: "Rotation", text: "Text" }[key] || key;
  }

  function setting(key, value) {
    if (key === "north") value = ((Number(value) % 360) + 360) % 360;
    edit({ op: "settings", set: { [key]: value } }, { label: "Change Plan" });
  }

  function doThing(what, one) {
    const ids = picks.slice();
    if (what.startsWith("step_")) {
      const sp = stepPicked();
      if (!sp) return;
      if (what === "step_addmove" || what === "step_addturn") return addStep(sp.e, what === "step_addturn", false);
      if (what === "step_home") { pickedStep = null; sideKey = ""; return paint(); }
      if (what === "step_remove") {
        edit({ op: "step_remove", id: sp.e.id, step: sp.i }, { label: `Remove ${sp.s.letter}` });
        pickedStep = null; sideKey = ""; return paint();
      }
      return;
    }
    if (what === "delete") return remove(ids);
    if (what === "sendlayer" || what === "copylayer") return sendLayer(ids.map(el).filter(Boolean), what === "copylayer");
    if (what === "duplicate") return duplicate(ids);
    if (what === "group") return edit({ op: "group", ids }, { label: "Group" });
    if (what === "sharelabel") {
      const made = edit({ op: "share_label", ids }, { label: "Share Label" });
      if (made && made[0]) { picks = [made[0]]; paint(); }
      return;
    }
    if (what === "ownlabel") return edit({ op: "own_label", ids }, { label: "Own Label" });
    if (what === "ownlabelall") return edit({ op: "own_label", ids }, { label: "Own Label" });
    if (what === "ride") return edit({ op: "ride", id: one.id }, { label: "Ride Track" });
    if (what === "unlock") return edit({ op: "update", ids: [one.id], set: { rig_on: "" } }, { label: "Unlock" });
    if (what === "ungroup") return edit({ op: "ungroup", ids }, { label: "Ungroup" });
    if (what === "flipx" || what === "flipy") return edit({ op: "flip", ids, axis: what === "flipx" ? "x" : "y" }, { label: "Flip" });
    if (what === "lock") return edit({ op: "update", ids, set: { locked: !(one && one.locked) } }, { label: one && one.locked ? "Unlock" : "Lock" });
    if (what === "hide") { edit({ op: "update", ids, set: { hidden: true } }, { label: "Hide" }); picks = []; paint(); return; }
    if (what === "leavegroup") return edit({ op: "update", ids, set: { group: "", group_name: "" } }, { label: "Remove from Group" });
    if (what === "hinge") return edit({ op: "update", ids, set: { hinge: one.hinge === "right" ? "" : "right" } }, { label: "Flip Hinge" });
    if (what === "side") return edit({ op: "update", ids, set: { flip: !one.flip } }, { label: "Flip Side" });
    if (what === "newshot") {
      // Cadrage's gesture, the Mac's: a camera with no shot gets one, made at
      // the end of the scene — the engine's `new_shot`, on an add. A camera
      // already down is put back down with one, in the same place.
      const full = { ...one };
      for (const k of ["id", "name", "show", "at", "emits", "groupName"]) delete full[k];
      const r = edits([{ op: "remove", ids: [one.id] }, { op: "add", els: [{ ...full, new_shot: true }] }], "New Shot");
      undos.push({ scene: r.scene, ops: r.back, label: "New Shot" });
      redos.length = 0;
      picks = r.renamed.length ? [r.renamed[r.renamed.length - 1][1]] : picks;
      toast("A new shot stands for this camera");
      paint();
      return;
    }
    if (what === "clear") {
      if (!confirm(`Clear the plan? ${H.many((got.els || []).length, "piece")} will go. Undo brings them back.`)) return;
      picks = [];
      return edit({ op: "clear", confirmed: true }, { label: "Clear Plan" });
    }
    if (what === "png") return savePicture();
  }

  // ------------------------------------------------------------ picking

  /** A piece and the rest of its group, if it is in one. */
  function groupOf(id) {
    const e = el(id);
    return e && e.group && got ? (got.els || []).filter((x) => x.group === e.group && !x.locked).map((x) => x.id) : [id];
  }

  function pickOne(id, fromList, add = false) {
    if (add && id) picks = picks.includes(id) ? picks.filter((p) => p !== id) : [...picks, id];
    else picks = id ? [id] : [];
    const e = id && el(id);
    if (e && e.kind === "camera") cam = id;
    else if (!id) cam = null;
    // Details opens only when asked (Back to Paper, Batch 2), never on a pick.
    legendPick = null;
    if (!editor() && e && e.kind === "camera") tab = "shots";
    sideKey = "";
    paint();
    if (!fromList || !id) return;
    // From a list: a piece off the edge of the view is brought into it.
    const e2 = el(id);
    if (!e2) return;
    const [ax, ay] = e2.at || [e2.x, e2.y];
    const [px, py] = storedToBox(ax, ay);
    const b = box();
    if (px > 40 && px < b.w - 40 && py > 40 && py < b.h - 40) return;
    const v = view();
    const [sx, sy] = shownOf(ax, ay);
    views.set(chosen(), { ...v, cx: sx, cy: sy, fit: false });
    paint();
  }

  /**
   * **A tap, looking**: the piece under it is picked and says what it is
   * (`lookFloat`); a camera says its shot. The same piece again, or the
   * floor, and the card goes.
   */
  function lookAt(id) {
    if (!id || (picks.length === 1 && picks[0] === id)) {
      if (!picks.length && !cam) return;
      picks = []; cam = null; sideKey = ""; paint();
      return;
    }
    pickOne(id);
    if (H.narrow()) keepAbove(id);
  }
  /**
   * On a phone the card lies along the plan's foot: a piece it would cover
   * is slid up into the open, so the thing asked about stays in sight.
   */
  function keepAbove(id) {
    const e = el(id), b = box(), f = root.querySelector(".planfloat.look.sheet"), v = view();
    if (!e || !b || !f || !v) return;
    const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
    const [px, py] = storedToBox(ax, ay);
    const top = f.offsetTop - 24;
    if (py < top && py > 24) return;
    // Low in the open if it looks up, high if it looks down: room for its cone.
    const up = faces(e) ? Math.sin(rad(arot + turn())) : 0;
    const want = Math.max(40, up < -0.4 ? top - 40 : up > 0.4 ? 60 : top / 2);
    views.set(chosen(), { ...v, cy: v.cy + (py - want) / v.k, cx: v.cx + (px - b.w / 2) / v.k * 0.5, fit: false });
    paint();
  }

  // ------------------------------------------------------------ the view

  function move() {
    const svg = root.querySelector(".planpic > svg");
    if (!svg || !live) return;
    for (const n of [svg, ...root.querySelectorAll(".planpaper")]) {
      if (!n) continue;
      n.style.transformOrigin = "0 0";
      n.style.transform = `translate(${live.tx}px, ${live.ty}px) scale(${live.s})`;
    }
    { const v = view(); if (v) scaleBar(v.k * live.s); }
    // A card beside a piece goes with it under the hand.
    const f = root.querySelector(".planfloat.look:not(.sheet)");
    if (f && f.dataset.ax) {
      const ax = Number(f.dataset.ax), ay = Number(f.dataset.ay);
      f.style.transform = `translate(${ax * (live.s - 1) + live.tx}px, ${ay * (live.s - 1) + live.ty}px)`;
    }
  }
  function commit() {
    const b = box();
    const id = chosen();
    const v = views.get(id);
    if (!b || !v || !live) { live = null; return; }
    const { tx, ty, s } = live;
    views.set(id, { ...v, cx: v.cx + ((b.w / 2 - tx) / s - b.w / 2) / v.k, cy: v.cy + ((b.h / 2 - ty) / s - b.h / 2) / v.k, k: v.k * s, fit: false });
    live = null;
    paint();
    settleUp();
  }
  function zoomAt(f, mx, my) {
    const v = view();
    if (!v) return;
    const cur = live || { tx: 0, ty: 0, s: 1 };
    const k = Math.max(v.fitK * 0.35, Math.min(700, v.k * cur.s * f));
    const g = k / (v.k * cur.s);
    live = { tx: mx - (mx - cur.tx) * g, ty: my - (my - cur.ty) * g, s: cur.s * g };
    move();
  }
  function soonCommit() { clearTimeout(settle); settle = setTimeout(commit, 160); }

  // ------------------------------------------------------------ the tools

  // Tools that open a library panel. Light is not one: a Light click places a mark
  // (lamps became marks, 9c174dad); the library's lights are reached through Swap and the Fixture field.
  const LIBS = { grip: "grip", set: "set" };
  /** The pieces a library tool offers — lamps under Light, grip under Grip, the rest under Set (the engine's `library.rs`). */
  const libOf = (k) => (library().symbols || []).filter((s) => (s.lib || (s.light ? "light" : "set")) === k);

  function setTool(k) {
    if (k !== tool) { libKind = ""; libMaker = ""; }
    if (TOOL_LAYER[k] && TOOL_LAYER[k] !== layer || (!TOOL_LAYER[k] && !["select", "hand", "cast", "text", "arrow", "note"].includes(k) && layer !== "plot")) {
      tool = k; castMenu = null; picMenu = k === "picture"; libOpen = Boolean(LIBS[k]); if (!libOpen) armed = null;
      closeMenu();
      return setLayer(TOOL_LAYER[k] || "plot");
    }
    if (wallDraw && k !== "wall") { wallDraw = null; wallAt = null; preview = null; guides = []; readout = null; showReadout(); }
    if (k !== tool) { penNodes = []; chainPts = []; }
    if (k !== "select") hover = null;
    closeMenu();
    tool = k;
    castMenu = null;
    picMenu = k === "picture";
    libOpen = Boolean(LIBS[k]);
    if (!libOpen) armed = null;
    if (libOpen && (!armed || !libOf(k).some((s) => s.id === armed.id))) armed = null;
    root.querySelectorAll("[data-ptool]").forEach((b) => b.classList.toggle("on", b.dataset.ptool === k));
    const ms = root.querySelector("[data-pmoresum]");
    if (ms) {
      const m = MORE_OF[layer].includes(k) ? (TOOLS.find((t) => t[0] === k) || [k, k])[1] : "More";
      ms.textContent = m;
      ms.classList.toggle("on", MORE_OF[layer].includes(k));
    }
    float();
    paint();
  }

  /** The library over the plan: search, groups, the pack's own pictures as tiles. */
  /**
   * **A library you can find things in** (the Mac's, 2026-09-30): the tool's
   * own library in its sections, filtered by section and maker, searched by
   * any word a crew calls a thing ("m18", "kino", "4k par"); what was put
   * down lately at the top.
   */
  function libFloat(f) { libPanel(f, { lib: LIBS[tool] }); }

  /**
   * **One library panel, two uses.** Placing: the tool's own library, a click
   * arms a piece. Swapping (`piece`): the very same panel, opened from the
   * Fixture or Kind field in Details or from a right-click, titled for what
   * it does, the piece it is now at the top, and a click swaps it for the one
   * clicked (`swapTo`).
   */
  function libPanel(f, { lib, piece = null }) {
    const L = library();
    const all = libOf(lib);
    const present = new Set(all.map((s) => s.kind || s.group));
    const order = ((L.kinds || {})[lib] || []).filter((k) => present.has(k));
    const kinds = [...order, ...[...present].filter((k) => !order.includes(k)).sort()];
    const makers = [...new Set(all.map((s) => s.maker).filter(Boolean))].sort();
    const words = libFind.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const matches = (s) => { const hay = [s.name, s.group, s.kind, s.maker, s.aka].join(" ").toLowerCase(); return words.every((w) => hay.includes(w)); };
    const shown = all.filter((s) => (!libKind || (s.kind || s.group) === libKind) && (!libMaker || s.maker === libMaker) && matches(s));
    const plain = !words.length && !libKind && !libMaker;
    const byId = new Map(all.map((s) => [s.id, s]));
    // What it is now: the library's own entry, or its own drawing when the
    // library does not list it (a scanned room's table).
    const here = piece ? byId.get(piece.sym) || { id: piece.sym, name: piece.name || piece.sym, light: piece.kind === "light", w: piece.w, h: piece.h } : null;
    const sections = [];
    if (here && plain) sections.push(["Now", [here]]);
    if (plain) {
      const recent = recentIds(lib).filter((id) => !here || id !== here.id).map((id) => byId.get(id)).filter(Boolean);
      if (recent.length) sections.push(["Recent", recent]);
    }
    for (const k of kinds) {
      const items = shown.filter((s) => (s.kind || s.group) === k && !(here && plain && s.id === here.id));
      if (items.length) sections.push([k, items]);
    }
    const noun = lib === "light" ? "lights" : lib === "grip" ? "grip" : "set pieces";
    const title = piece ? (piece.kind === "light" ? "Swap Fixture" : "Swap Kind") : lib === "light" ? "Lights" : lib === "grip" ? "Grip" : "Set Pieces";
    const hint = piece ? "Click to swap · Esc to close" : armed ? "Click to place · drag to turn" : lib === "light" ? "Pick a light" : lib === "grip" ? "Pick a piece of grip" : "Pick a set piece";
    const lit = (s) => (piece ? s.id === piece.sym : Boolean(armed && armed.id === s.id));
    f.className = "planfloat lib";
    f.innerHTML = `<div class="plibhead"><b>${title}</b><input type="search" class="plibfind" placeholder="Search ${noun}" value="${esc(libFind)}"><button type="button" class="lact" data-plibclose="1">Close</button></div>
      <div class="plibchips"><button type="button" class="ppill${libKind ? "" : " on"}" data-pkind="">All</button>${kinds.map((k) => `<button type="button" class="ppill${libKind === k ? " on" : ""}" data-pkind="${esc(k)}">${esc(k)}</button>`).join("")}
        ${makers.length > 1 ? `<select class="plibmaker" data-pmaker="1"><option value="">Maker</option>${makers.map((m) => `<option value="${esc(m)}"${m === libMaker ? " selected" : ""}>${esc(m)}</option>`).join("")}</select>` : ""}</div>
      <div class="plibscroll">${sections.map(([g, items]) => `<div class="plibglab">${esc(g)}</div><div class="pliblist">${items.map((s) => `<button type="button" class="plibrow${lit(s) ? " on" : ""}" data-psym="${esc(s.id)}" title="${esc(s.name)}">
        <span class="ptpic${s.light ? " up" : ""}">${tileArt(s)}</span><span class="plibwords"><span class="ptname">${esc(s.name)}</span>${s.maker && !s.name.toLowerCase().startsWith(s.maker.toLowerCase().slice(0, 4)) ? `<span class="ptmaker">${esc(s.maker)}</span>` : ""}</span></button>`).join("")}</div>`).join("") || `<p class="empty planempty">Nothing called that</p>`}</div>
      <div class="plibfoot">${hint}</div>`;
    const find = f.querySelector(".plibfind");
    find.addEventListener("input", () => { libFind = find.value; const at = find.selectionStart; float(); const again = root.querySelector(".plibfind"); if (again) { again.focus(); again.setSelectionRange(at, at); } });
    find.addEventListener("keydown", (ev) => {
      ev.stopPropagation();
      if (ev.key === "Escape") {
        if (piece) return closeSwap();
        libOpen = false; float(); const b = box(); if (b) b.vp.focus({ preventScroll: true });
      }
    });
    f.querySelectorAll("[data-pkind]").forEach((b) => b.addEventListener("click", () => { libKind = libKind === b.dataset.pkind ? "" : b.dataset.pkind; float(); }));
    const mk = f.querySelector("[data-pmaker]");
    if (mk) mk.addEventListener("change", () => { libMaker = mk.value; float(); });
    f.querySelectorAll("[data-psym]").forEach((b) => {
      if (piece) { b.addEventListener("click", () => swapTo(all.find((s) => s.id === b.dataset.psym))); return; }
      b.addEventListener("click", () => { armed = all.find((s) => s.id === b.dataset.psym) || null; libOpen = false; float(); toast(`Click the plan to put down ${armed ? armed.name : ""}`); });
      b.draggable = true;
      b.addEventListener("dragstart", (ev) => { ev.dataTransfer.setData("text/x-plan-sym", b.dataset.psym); ev.dataTransfer.effectAllowed = "copy"; });
    });
    f.querySelector("[data-plibclose]").addEventListener("click", () => { if (piece) closeSwap(); else { libOpen = false; float(); } });
    if (swap && swap.focus) { swap.focus = false; find.focus({ preventScroll: true }); find.setSelectionRange(find.value.length, find.value.length); }
  }

  // ---- Swap: the toolbar's library, opened from Details or a right-click ------------
  //
  // His ask, 2026-10-02: *"in the detail menu where i can swap out the fixture
  // for another, the list is so large, it needs to be searchable and the same
  // as the one in the top toolbar."* The panel is the toolbar's own; a click
  // is the engine's `swap` (it keeps place, turn, name, colour, notes, steps).

  const swapping = () => Boolean(swap && picks.length === 1 && picks[0] === swap.id && el(swap.id));
  /** The library a piece belongs to: lamps in Light, grip in Grip, the rest in Set Piece. */
  function swapLib(e) {
    const s = (library().symbols || []).find((x) => x.id === e.sym);
    return s ? s.lib || (s.light ? "light" : "set") : e.kind === "light" ? "light" : "set";
  }
  function swapFloat(f) {
    const e = el(swap.id);
    libPanel(f, { lib: swapLib(e), piece: e });
  }
  function openSwap(id) {
    const e = el(id);
    if (!editor() || !e || !(e.kind === "light" || e.kind === "set") || isFrame(e)) return;
    const again = picks.length === 1 && picks[0] === id;
    if (!again) { picks = [id]; sideKey = ""; }
    castMenu = null; picMenu = false; libOpen = false; favOpen = false; copyPanel = null;
    closeMenu();
    libFind = ""; libKind = ""; libMaker = "";
    swap = { id, focus: true };
    document.addEventListener("pointerdown", swapAway, true);
    markSwap();
    if (again) float(); else paint();
  }
  function closeSwap(redraw = true) {
    if (!swap) return;
    swap = null;
    libFind = ""; libKind = ""; libMaker = "";
    document.removeEventListener("pointerdown", swapAway, true);
    markSwap();
    if (!redraw) return;
    float();
    const b = box();
    if (b) b.vp.focus({ preventScroll: true });
  }
  /** A press anywhere but the panel and the field that opened it closes it. */
  function swapAway(ev) {
    const t = ev.target;
    if (t && t.closest && (t.closest(".planfloat.lib") || t.closest("[data-pswap]"))) return;
    closeSwap();
  }
  function markSwap() {
    root.querySelectorAll("[data-pswap]").forEach((b) => b.classList.toggle("open", Boolean(swap && swap.id === b.dataset.pswap)));
  }
  function swapTo(s) {
    const e = swap && el(swap.id);
    if (!e || !s || e.sym === s.id) return;
    const was = (library().symbols || []).find((x) => x.id === e.sym);
    libFind = "";
    swap.focus = true;
    edit({ op: "swap", ids: [e.id], sym: s.id }, { label: `Swap to ${s.name}` });
    if (was) rememberUse(was);
    rememberUse(s);
    toast(`Swapped to ${s.name}`);
  }
  /** The Fixture or Kind field in Details: the piece's picture and name; a press opens the library. */
  function swapField(label, e) {
    const s = (library().symbols || []).find((x) => x.id === e.sym) || { id: e.sym, name: e.name || e.sym, light: e.kind === "light", w: e.w, h: e.h };
    return `<div class="pf"><span>${label}</span><button type="button" class="pswapfield${swap && swap.id === e.id ? " open" : ""}" data-pswap="${esc(e.id)}"><span class="ptpic${s.light ? " up" : ""}">${tileArt(s)}</span><span class="pswapname">${esc(s.name)}</span></button></div>`;
  }
  function tileArt(s) {
    const pack = s.id.startsWith("fso-");
    if (pack) return `<img alt="" loading="lazy" src="fso/${esc(s.id.replace(/^fso-/, ""))}.png">`;
    return glyph(s.light ? "light" : "set", s.id, s.w || 1, s.h || 1, 56);
  }

  function castFloat(f) {
    const who = castNames();
    const onPlan = new Set((got ? got.els || [] : []).filter((e) => e.kind === "cast").map((e) => (e.cast || e.label || "").toLowerCase()));
    const names = [...who.scene, ...who.film.filter((n) => !who.scene.includes(n))];
    f.className = "planfloat lib cast";
    f.innerHTML = `<div class="plibhead"><b>Who Is This?</b><button type="button" class="lact" data-pcastclose="1">Close</button></div>
      <div class="pcastlist">${names.map((n) => `<button type="button" class="pcastrow${onPlan.has(n.toLowerCase()) ? " placed" : ""}" data-pcastas="${esc(n)}">${esc(n)}${onPlan.has(n.toLowerCase()) ? `<i>On the Plan</i>` : ""}</button>`).join("")}
      <button type="button" class="pcastrow" data-pcastas="">Someone</button></div>`;
    f.querySelectorAll("[data-pcastas]").forEach((b) => b.addEventListener("click", () => {
      const m = castMenu;
      castMenu = null;
      const character = b.dataset.pcastas;
      const count = (got ? got.els || [] : []).filter((e) => e.kind === "cast").length;
      const e = { kind: "cast", x: m.x, y: m.y, rot: m.rot };
      if (character) { e.label = character; e.cast = character; } else e.label = `Cast ${count + 1}`;
      edit({ op: "add", els: [e] }, { label: "Add Cast", select: true });
      setTool("select");
    }));
    f.querySelector("[data-pcastclose]").addEventListener("click", () => { castMenu = null; float(); });
  }

  /** The Picture tool: the film's own pictures, to lie under the plan or stand on it. */
  /**
   * **Every picture the film holds that could go on this plan, in groups**
   * (the Mac's `projectPictures`): the scene's own, its shots' frames, its
   * locations', its boards', then every other location's and board's. A
   * picture shows once, in the first group that has it.
   */
  function projectPictures() {
    const m = H.model();
    const id = chosen();
    const seen = new Set();
    const out = [];
    const add = (title, list) => {
      const fresh = (list || []).filter((x) => x && x.hash && x.kind !== "video" && !x.moving && !seen.has(x.hash) && seen.add(x.hash));
      if (fresh.length) out.push([title, fresh]);
    };
    const scene = sceneOf(id);
    if (scene) add("This Scene", scene.attachments || []);
    add("Shots", shotsOf(id).flatMap((r) => [r.frame, ...(r.stills || [])]));
    const here = (m.locations || []).filter((l) => (l.scenes || []).includes(id));
    const boards = (m.boards || []).filter((b) => (b.scenes || []).includes(id));
    for (const l of here) add(l.name || "Location", l.media);
    for (const b of boards) add(b.name || "Board", b.media);
    for (const l of m.locations || []) if (!here.includes(l)) add(l.name || "Location", l.media);
    for (const b of m.boards || []) if (!boards.includes(b)) add(b.name || "Board", b.media);
    return out;
  }
  let picPhoto = false;           // Trace lays a Photo (on the plot, full strength) or a Background to trace over
  /** A picture the film holds, laid on the plan: centred in view, or where it was dropped. */
  function layPicture(m, at = null, aspect = 0.66) {
    const ext = (String(m.filename || "").split(".").pop() || "jpg").toLowerCase();
    const name = `${m.hash.slice(0, 32)}.${/^(png|jpe?g|heic|gif|webp)$/.test(ext) ? ext : "jpg"}`;
    const bx = box();
    const [x, y] = at || toStored(bx.w / 2, bx.h / 2);
    const wide = Math.max(1, (bx.w * (picPhoto ? 0.2 : 0.6)) / view().k);
    picMenu = false;
    const e = { kind: "image", x, y, w: wide, h: wide * aspect, media: name, opacity: picPhoto ? 1 : 0.85 };
    if (picPhoto) e.role = "photo";
    edit({ op: "add", els: [e] }, { label: "Add Picture", select: true });
    setTool("select");
  }
  function picFloat(f) {
    const groups = projectPictures();
    const all = new Map(groups.flatMap(([, list]) => list.map((x) => [x.hash, x])));
    f.className = "planfloat lib";
    f.innerHTML = `<div class="plibhead"><b>Pictures</b><label class="lact pchoose">Choose File…<input type="file" accept="image/*" data-pfile="1" hidden></label><button type="button" class="lact" data-ppicclose="1">Close</button></div>
      <div class="ppills plibchips"><button type="button" class="ppill${picPhoto ? "" : " on"}" data-ppicas="0">Background</button><button type="button" class="ppill${picPhoto ? " on" : ""}" data-ppicas="1">Photo</button></div>
      ${groups.length ? `<div class="plibscroll">${groups.map(([title, list]) => `<div class="plibgroup">${esc(title)}</div><div class="plibtiles pics">${list.map((x) =>
        `<button type="button" class="ptile" draggable="true" data-ppic="${esc(x.hash)}" title="${esc(x.filename || "")}"><span class="ptpic">${H.mediaTag(x)}</span></button>`).join("")}</div>`).join("")}</div>`
        : `<p class="empty planempty">No pictures in this film</p>`}`;
    const aspectOf = (b) => { const img = b.querySelector("img"); return img && img.naturalWidth ? img.naturalHeight / img.naturalWidth : 0.66; };
    f.querySelectorAll("[data-ppic]").forEach((b) => {
      b.addEventListener("click", () => layPicture(all.get(b.dataset.ppic), null, aspectOf(b)));
      b.addEventListener("dragstart", (ev) => { ev.dataTransfer.setData("text/x-plan-pic", JSON.stringify({ hash: b.dataset.ppic, aspect: aspectOf(b) })); ev.dataTransfer.effectAllowed = "copy"; });
    });
    f.querySelectorAll("[data-ppicas]").forEach((b) => b.addEventListener("click", () => { picPhoto = b.dataset.ppicas === "1"; float(); }));
    f.querySelector("[data-ppicclose]").addEventListener("click", () => { picMenu = false; setTool("select"); });
    const file = f.querySelector("[data-pfile]");
    if (file) file.addEventListener("change", () => { if (file.files && file.files[0]) layFile(file.files[0]); });
    picPictures = all;
  }
  let picPictures = new Map();

  // ---- Favorites: nine slots, the Mac's, kept in the film ------------------

  function favSlots() {
    const said = json(call("plan_favorites", ""));
    return (said && said.slots) || [];
  }
  /** A favorite's picture: its mark, its library drawing, or its kind's. */
  function favArt(el0) {
    if (!el0) return "";
    const e = Array.isArray(el0.els) && el0.els.length ? el0.els[0] : el0;
    if (e.mark) return markSvg({ mark: e.mark, ink: e.practical ? "practical" : e.existing ? "ink" : e.mark_ink || "added", solid: e.mark_fill ? e.mark_fill === "solid" : SOLID_FIRST.has(e.mark) }, 26);
    if (e.sym && (e.kind === "set" || e.kind === "light")) { const art = glyph(e.kind, e.sym, 30, 30, 60); if (art) return art; }
    return ICONS[LAYER_ICON[e.kind] || (e.kind === "light" ? "frame" : "set")] || "";
  }
  /**
   * **Favorites** (the Mac's strip): nine tiles, each its picture and name.
   * A tile clicked or 1–9 puts it down; a tile dragged onto the plan puts
   * it there; a Layers row or the picked piece dropped on a tile keeps it.
   */
  function favFloat(f) {
    const slots = favSlots();
    // One piece, or one whole group: a group is kept as one favorite (his custom objects, 2026-10-04).
    const sameGroup = picks.length > 1 && picks.every((id) => { const x = el(id); return x && x.group && x.group === (el(picks[0]) || {}).group; });
    const one = picks.length === 1 || sameGroup ? el(picks[0]) : null;
    f.className = "planfloat lib favs";
    f.innerHTML = `<div class="plibhead"><b>Favorites</b><span class="plibhint">1–9 puts one down</span><button type="button" class="lact" data-pfavclose="1">Close</button></div>
      <div class="pfavtiles">${Array.from({ length: 9 }, (_, i) => {
        const s0 = slots[i];
        return `<button type="button" class="pfavtile${s0 ? "" : " empty"}" data-pfavtile="${i}"${s0 ? ` draggable="true"` : ""} title="${esc(s0 ? s0.name : one ? "Add Picked Item" : "Empty")}">
          <b>${i + 1}</b><span class="pfavart">${s0 ? favArt(s0.el) : one ? "+" : ""}</span><span class="pfavname">${esc(s0 ? s0.name : "Empty")}</span></button>`;
      }).join("")}</div>`;
    const keep = (slot, e) => {
      const src = { ...e };
      for (const k of ["name", "show", "at", "emits", "groupName"]) delete src[k];
      edit({ op: "favorite", slot, el: src }, { label: "Add to Favorites", record: false });
      toast(`Kept in slot ${slot + 1}`);
    };
    f.querySelector("[data-pfavclose]").addEventListener("click", () => {
      favOpen = false;
      const fv = root.querySelector("[data-pfavs]");
      if (fv) fv.classList.remove("on");
      float();
    });
    f.querySelectorAll("[data-pfavtile]").forEach((t) => {
      const i = Number(t.dataset.pfavtile);
      t.addEventListener("click", () => {
        if (slots[i]) { const bx = box(); const [x, y] = toStored(bx.w / 2, bx.h / 2); putFavorite(i, x, y); }
        else if (one) keep(i, one);
      });
      t.addEventListener("contextmenu", (ev) => {
        ev.preventDefault();
        const items = [];
        if (slots[i]) items.push({ label: "Remove", pick: () => edit({ op: "favorite", slot: i, el: null }, { label: "Remove from Favorites", record: false }) });
        if (one) items.push({ label: slots[i] ? "Replace with Picked" : "Add Picked Item", pick: () => keep(i, one) });
        if (items.length) openMenu(null, items, true, [ev.clientX, ev.clientY]);
      });
      t.addEventListener("dragstart", (ev) => { ev.dataTransfer.setData("text/x-plan-fav", String(i)); ev.dataTransfer.effectAllowed = "copy"; });
      // A Layers row dropped here: kept in this slot.
      t.addEventListener("dragover", (ev) => { if (ev.dataTransfer.types.includes("text/plain") && !ev.dataTransfer.types.includes("text/x-plan-fav")) { ev.preventDefault(); t.classList.add("dropon"); } });
      t.addEventListener("dragleave", () => t.classList.remove("dropon"));
      t.addEventListener("drop", (ev) => {
        t.classList.remove("dropon");
        const e = el(ev.dataTransfer.getData("text/plain"));
        if (!e) return;
        ev.preventDefault();
        keep(i, e);
      });
    });
  }
  function putFavorite(slot, x, y) {
    const said = json(call("plan_favorites", `${slot} ${x} ${y}`));
    if (!said || !said.op) return toast(`Slot ${slot + 1} is empty`);
    // A lone piece, or a group put down as one group (his custom objects, 2026-10-04).
    edit(said.op, { label: "Place Favorite", select: true });
  }

  // ---- plans between scenes: Copy From, Copy To, Send to Scene --------------
  //
  // His ask, 2026-10-01: "lets do copying properly". The Mac's `DiagramCopy`:
  // a drawn plan is never replaced without asking, Add on Top keeps it and
  // lays the copies over it where they were drawn. Each scene a plan lands on
  // gets its own step of Undo, taken back from that scene's plan.

  const pieces = (n) => H.many(n, "piece");
  /** Where a plan can go or come from: the loose plans, then the live scenes, never the one open. `diagram`: how many pieces each holds. */
  function otherScenes() {
    const here = String(chosen());
    const plans = (H.model().plans || []).filter((p) => String(p.id) !== here).map((p) => ({ id: p.id, label: p.name, short: p.name, diagram: p.diagram }));
    const scenes = (H.model().scenes || []).filter((x) => !x.archived && String(x.id) !== here)
      .map((x) => ({ id: x.id, label: `${x.number}  ${x.heading || x.title || ""}`, short: x.number, diagram: x.diagram }));
    return [...plans, ...scenes];
  }

  /** A loose plan made here, under an id this page chooses — the server makes the same one (`plan_new`). Then picked. */
  function newPlan(from = null) {
    const id = String(BigInt.asUintN(128, [...crypto.getRandomValues(new Uint32Array(4))].reduce((a, w) => (a << 32n) | BigInt(w), 0n)));
    const name = !from ? "" : planOf(from) ? `${planOf(from).name} Copy` : `Scene ${(sceneOf(from) || {}).number || ""}`.trim();
    edit({ op: "plan_new", id, name, ...(from ? { from: String(from) } : {}) }, { label: "New Plan", record: false });
    H.pickPlan(id);
  }

  /** The Plan button over a loose plan: Rename, Duplicate, Delete. */
  function planMenu(anchor) {
    const p = planOf(chosen());
    if (!p) return;
    openMenu(anchor, [
      { label: "Rename…", pick: () => renamePlan(anchor, p) },
      { label: "Duplicate", pick: () => newPlan(p.id) },
      { label: "Delete…", pick: () => openMenu(anchor, [
        { head: p.diagram ? `${pieces(p.diagram)} on it go with it.` : `Delete ${p.name}` },
        { label: "Delete", pick: () => {
          edit({ op: "plan_delete", confirmed: true }, { label: "Delete Plan", record: false });
          H.pickPlan(null);
        } },
      ]) },
    ]);
  }
  function renamePlan(anchor, p) {
    // The plan's own rename box, as a piece's (`.planrename`), over the button.
    const input = document.createElement("input");
    input.className = "planrename";
    input.type = "text";
    input.value = p.name;
    input.setAttribute("aria-label", "Plan Name");
    document.body.append(input);
    const r = anchor.getBoundingClientRect();
    input.style.left = `${r.left + r.width / 2}px`; input.style.top = `${r.top + r.height / 2}px`;
    input.focus(); input.select();
    let done = false;
    const finish = (keep) => {
      if (done) return; done = true;
      const name = input.value.trim();
      input.remove();
      if (keep && name && name !== p.name) { edit({ op: "plan_rename", name }, { label: "Rename Plan", record: false }); H.relook(); }
    };
    input.addEventListener("keydown", (ev) => { if (ev.key === "Enter") finish(true); if (ev.key === "Escape") finish(false); });
    input.addEventListener("blur", () => finish(true));
  }


  /** The Copy button: Copy To, then Copy From each scene with a plan. */
  function copyMenu(anchor) {
    const from = otherScenes().filter((x) => x.diagram > 0);
    const items = [];
    if ((got && got.els || []).length && otherScenes().length) {
      items.push({ label: "Copy To…", pick: () => { copyPanel = { ids: [], mode: "add", ticked: new Set() }; float(); } });
    }
    if ((got && got.els || []).length) items.push({ label: "Copy to New Plan", pick: () => newPlan(chosen()) });
    if ((got && got.els || []).length) items.push({ label: "Gear List", pick: () => copyGear() });
    // **Room from Scan, any time** (the Mac's header menu): the scene's places' scans first.
    if (scansHere().length) items.push({ label: "Room from Scan…", pick: () => { roomOpen = true; float(); } });
    items.push({ head: from.length ? "Copy From" : "No other scene has a plan" });
    for (const x of from) items.push({ label: x.label, pick: () => copyFrom(x, anchor) });
    openMenu(anchor, items, true);
  }

  /** Copy From one scene — over a drawn plan, Add on Top or Replace first. */
  function copyFrom(x, anchor) {
    const here = (got && got.els || []).length;
    const go = (mode) => {
      // Replace, picked from its own menu over a drawn plan, is the asking.
      edit({ op: "copy_from", from: String(x.id), mode, ...(mode === "replace" ? { confirmed: true } : {}) }, { label: "Copy Diagram" });
      if (mode === "replace") { const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" }); }
      paint();
    };
    if (!here) return go("replace");
    openMenu(anchor, [
      { head: `Copy From ${x.short}` },
      { label: "Add on Top", pick: () => go("add") },
      { label: "Replace", pick: () => go("replace"), title: `Replace takes the place of the ${pieces(here)} on this plan` },
    ]);
  }

  /** This plan, or the pieces `ids`, onto each scene ticked — one edit on each, its Undo its own. */
  function sendTo(targets, ids, mode) {
    const from = String(chosen());
    let n = 0;
    for (const t of targets) {
      const scene = String(t);
      // Replace onto plans with pieces says so in the panel before Copy: the asking.
      const op = { op: "copy_from", from, mode, ...(ids.length ? { ids } : {}), ...(mode === "replace" ? { confirmed: true } : {}) };
      const said = made(scene, op);
      if (!said || said.error) continue;
      rev++;
      pending.push({ scene, op: fwd(op), made: said.made || [] });
      if (reading) reading.push({ scene, op: fwd(replayable(op, said.made)) });
      const back = fwd(said.undo || []);
      if (back.length) { undos.push({ scene, ops: back, label: "Copy Diagram", at: Date.now() }); redos.length = 0; }
      n++;
    }
    soon();
    paint();
    if (n) toast(n === 1 ? "Copied to 1 plan" : `Copied to ${n} plans`);
  }

  /** Copy To (`ids` empty: the whole plan) and Send to Scene: tick the scenes, then Copy. */
  function copyFloat(f) {
    const c = copyPanel;
    const whole = !c.ids.length;
    const scenes = otherScenes();
    const lost = c.mode === "replace" ? scenes.filter((x) => c.ticked.has(String(x.id))).reduce((a, x) => a + (x.diagram || 0), 0) : 0;
    f.className = "planfloat lib copyto";
    f.innerHTML = `<div class="plibhead"><b>${whole ? "Copy To" : "Send To"}</b><i class="pcopyn">${pieces(whole ? (got.els || []).length : c.ids.length)}</i><button type="button" class="lact" data-pcopyclose="1">Close</button></div>
      <div class="pcastlist">${scenes.map((x) => `<label class="pcastrow pcopyrow"><span><input type="checkbox" data-pcopyto="${esc(String(x.id))}"${c.ticked.has(String(x.id)) ? " checked" : ""}> ${esc(x.label)}</span>${x.diagram ? `<i>${pieces(x.diagram)}</i>` : ""}</label>`).join("")}</div>
      <div class="pcopyfoot">${whole ? `<div class="pcopymode"><button type="button" class="ppill${c.mode === "add" ? " on" : ""}" data-pcopymode="add">Add on Top</button><button type="button" class="ppill${c.mode === "replace" ? " on" : ""}" data-pcopymode="replace">Replace</button></div>` : ""}
        ${lost ? `<p class="pcopywarn">${pieces(lost)} on those plans will be replaced.</p>` : ""}
        <button type="button" class="pcopy" data-pcopygo="1"${c.ticked.size ? "" : " disabled"}>${whole ? "Copy" : "Send"}</button></div>`;
    f.querySelectorAll("[data-pcopyto]").forEach((b) => b.addEventListener("change", () => {
      if (b.checked) c.ticked.add(b.dataset.pcopyto); else c.ticked.delete(b.dataset.pcopyto);
      float();
    }));
    f.querySelectorAll("[data-pcopymode]").forEach((b) => b.addEventListener("click", () => { c.mode = b.dataset.pcopymode; float(); }));
    f.querySelector("[data-pcopyclose]").addEventListener("click", () => { copyPanel = null; float(); });
    f.querySelector("[data-pcopygo]").addEventListener("click", () => {
      const targets = [...c.ticked];
      copyPanel = null;
      sendTo(targets, c.ids, c.mode);
    });
  }

  // ---- an empty plan: draw walls, a room from a scan, or another scene's plan --

  // A room named for where it was scanned already says its place, and says
  // when under it; one still wearing the phone's name gives its place first.
  function roomRow(x) {
    const name = x.scan.name || "Scan";
    return name.startsWith("RoomScan_")
      ? `${esc(x.place.name)}<i>${esc(name)}</i>`
      : `${esc(name)}<i>${esc(x.scan.taken || "")}</i>`;
  }

  let roomOpen = false;
  /** Every scan with a room in it: the scene's own places first (a loose plan: all of them, as found). */
  function scansHere() {
    const s = sceneOf(chosen());
    const mine = new Set((s && s.locations) || []);
    const out = [];
    for (const l of H.model().locations || []) for (const sc of l.scans || []) if (sc.plan) out.push({ place: l, scan: sc, here: mine.has(l.id) });
    return out.sort((a, b) => Number(b.here) - Number(a.here));
  }
  async function layRoom(x) {
    const text = await H.roomText(String(x.scan.plan.hash || x.scan.plan).slice(0, 32));
    if (!text) return toast("That scan could not be read", true);
    emptyOpen = null; roomOpen = false;
    edit({ op: "room", scan: text, location: String(x.place.id) }, { label: "Room from Scan" });
    const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" });
    paint();
  }
  function roomFloat(f) {
    f.className = "planfloat lib empty";
    const scans = scansHere();
    const here = scans.filter((x) => x.here), rest = scans.filter((x) => !x.here);
    const rows = (list, at) => list.map((x, i) => `<button type="button" class="pcastrow" data-proomany="${at + i}">${roomRow(x)}</button>`).join("");
    f.innerHTML = `<div class="plibhead"><b>Room from Scan</b><button type="button" class="lact" data-proomclose="1">Close</button></div>
      <div class="pcastlist">${here.length ? rows(here, 0) : ""}${rest.length ? `${here.length ? `<div class="pmhead">Other Places</div>` : ""}${rows(rest, here.length)}` : ""}${scans.length ? "" : `<p class="empty planempty">Nothing scanned</p>`}</div>`;
    f.querySelector("[data-proomclose]").addEventListener("click", () => { roomOpen = false; float(); });
    f.querySelectorAll("[data-proomany]").forEach((b) => b.addEventListener("click", () => layRoom(scans[Number(b.dataset.proomany)])));
  }

  function emptyFloat(f) {
    f.className = "planfloat lib empty";
    const scenes = (H.model().scenes || []).filter((x) => !x.archived && x.diagram > 0 && x.id !== chosen());
    const scans = [];
    for (const l of H.model().locations || []) for (const sc of l.scans || []) if (sc.plan) scans.push({ place: l, scan: sc });
    if (emptyOpen === "copy") {
      f.innerHTML = `<div class="plibhead"><b>Copy From</b><button type="button" class="lact" data-pempty="">Back</button></div>
        <div class="pcastlist">${scenes.map((x) => `<button type="button" class="pcastrow" data-pcopyfrom="${esc(x.id)}">${esc(x.number)} ${esc(x.heading || x.title || "")}<i>${H.many(x.diagram, "piece")}</i></button>`).join("") || `<p class="empty planempty">No other scene has a plan</p>`}</div>`;
    } else if (emptyOpen === "room") {
      f.innerHTML = `<div class="plibhead"><b>Room from Scan</b><button type="button" class="lact" data-pempty="">Back</button></div>
        <div class="pcastlist">${scans.map((x, i) => `<button type="button" class="pcastrow" data-proom="${i}">${roomRow(x)}</button>`).join("") || `<p class="empty planempty">Nothing scanned</p>`}</div>`;
    } else {
      f.innerHTML = `<div class="plibhead"><b>No diagram yet</b></div>
        <div class="pemptybtns"><button type="button" class="pcopy" data-pdraw="1">Draw Walls</button>
        <button type="button" class="pcopy" data-pempty="room"${scans.length ? "" : " disabled"}>Room from Scan</button>
        <button type="button" class="pcopy" data-pempty="copy"${scenes.length ? "" : " disabled"}>Copy From</button></div>`;
    }
    f.querySelectorAll("[data-pempty]").forEach((b) => b.addEventListener("click", () => { emptyOpen = b.dataset.pempty || null; float(); }));
    const draw = f.querySelector("[data-pdraw]");
    if (draw) draw.addEventListener("click", () => { setTool("wall"); toast("Click each corner · ⇧ for a room"); });
    f.querySelectorAll("[data-pcopyfrom]").forEach((b) => b.addEventListener("click", () => {
      emptyOpen = null;
      edit({ op: "copy_from", from: b.dataset.pcopyfrom }, { label: "Copy Plan" });
      const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" });
      paint();
    }));
    f.querySelectorAll("[data-proom]").forEach((b) => b.addEventListener("click", async () => {
      const x = scans[Number(b.dataset.proom)];
      const text = await H.roomText(String(x.scan.plan.hash || x.scan.plan).slice(0, 32));
      if (!text) return toast("That scan could not be read", true);
      emptyOpen = null;
      edit({ op: "room", scan: text, location: String(x.place.id) }, { label: "Room from Scan" });
      const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" });
      paint();
    }));
  }

  /**
   * A picture from the computer: kept among the film's pictures, then laid in
   * the middle of the view, a little narrower than it (the Mac's `addPicture`).
   */
  async function layFile(file) {
    toast("Adding the picture…");
    let pw = 0, ph = 0;
    try { const bmp = await createImageBitmap(file); pw = bmp.width; ph = bmp.height; bmp.close(); } catch { /* sizes come from the file's own shape, when the browser can read it */ }
    let said = null;
    try {
      const r = await fetch(`/f/${HUB.project}/api/picture?name=${encodeURIComponent(file.name)}`, { method: "PUT", headers: { "content-type": file.type || "image/jpeg" }, body: file });
      said = await r.json().catch(() => null);
      if (!r.ok) return toast((said && (said.problem || said.error)) || "That picture would not go up", true);
    } catch {
      return toast("No connection", true);
    }
    const bx = box();
    const [x, y] = toStored(bx.w / 2, bx.h / 2);
    picMenu = false;
    edit({ op: "picture", hash: said.hash, ext: said.ext, pw, ph, bytes: said.bytes, filename: file.name, x, y, width: Math.max(1, (bx.w * 0.6) / view().k), photo: false }, { label: "Add Picture", select: true });
    setTool("select");
  }

  /** Put a thing down where the plan was clicked — the Mac's `placing`. */
  function place(x, y, rot, keep = false) {
    // ⌥ keeps the tool in hand, armed with the same piece, to put down another.
    const done = () => { if (!keep) setTool("select"); };
    if (tool === "camera") {
      const n = (got ? got.els || [] : []).filter((e) => e.kind === "camera").length;
      // Chosen from the Camera button's menu: a shot already in the scene,
      // or none; otherwise a camera brings a new shot (the Mac's `addCamera`).
      const c = { kind: "camera", x, y, rot, color: PALETTE[n % PALETTE.length] };
      if (armedShot === "new") c.new_shot = true; else if (armedShot) c.shot = armedShot;
      edit({ op: "add", els: [c] }, { label: "Add Camera", select: true });
      armedShot = "new";
      return done();
    }
    if (tool === "cast") {
      castMenu = { x, y, rot };
      return float();
    }
    if (tool === "light") {
      // **Pick the mark, click to put lights down** (his ask, 2026-10-03):
      // no unit yet, and no label until he types one (2026-10-15).
      const l = lookOf(armedLook);
      // Its Type from the palette's top row — Film Light, Practical or
      // Existing — which is its ink (the Mac's `addLamp`).
      const lampEl = { kind: "light", sym: "", x, y, rot, w: 0.3, h: TUBE_LEN[l.mark] || 0.3, mark: l.mark, mark_fill: l.solid ? "solid" : "open",
        practical: l.ink === "practical", existing: l.ink === "ink" || l.ink === "existing" };
      if (!["added", "practical", "ink", "existing"].includes(l.ink)) lampEl.mark_ink = l.ink;
      edit({ op: "add", els: [lampEl] }, { label: "Add Lamp", select: true });
      return;
    }
    if ((tool === "set" || tool === "grip") && armed) {
      const s = armed;
      if (s.id === (library().frame || "frame")) { addFrame(x, y, 0); rememberUse(s); return; }
      const e = { kind: s.light ? "light" : "set", sym: s.id, x, y, rot, w: s.w, h: s.h };
      if (s.light) { e.beam = s.beam; e.reach = s.reach; e.kelvin = s.kelvin; e.beam_on = s.beam > 0; }
      edit({ op: "add", els: [e] }, { label: `Add ${s.name}`, select: true });
      rememberUse(s);
      return;
    }
    if (LIBS[tool]) { libOpen = true; float(); return toast(tool === "light" ? "Pick a light" : tool === "grip" ? "Pick a piece of grip" : "Pick a set piece"); }
    if (tool === "frame") {
      addFrame(x, y, rot);
      return done();
    }
    if (tool === "door" || tool === "window") {
      const e = { kind: tool, x, y };
      const [sx, sy] = shownOf(x, y);
      const on = where("wall", sx, sy, { reach: 0.6 });
      if (on && on.x !== null && on.x !== undefined) { e.x = on.sx; e.y = on.sy; e.rot = on.rot; e.h = on.thick; }
      edit({ op: "add", els: [e] }, { label: `Add ${word(tool)}`, select: true });
      return done();
    }
    if (tool === "text" || tool === "note") {
      // **Words, typed where they stand** (his call F): put down at a
      // name's size, the cursor in them at once (Ref 1485).
      const made = edit({ op: "add", els: [{ kind: "text", x, y, text: "Words", size: WORDS_REGULAR, ...inSetNow() }] }, { label: "Add Words", select: true });
      done();
      if (made[0]) { const t = el(made[0]); if (t) typeOn(t, "text"); }
      return;
    }
  }

  /** A new frame: lying flat, 8 × 8 (the engine sees to the flat). */
  function addFrame(x, y, rot = 0) {
    edit({ op: "add", els: [{ kind: "light", sym: library().frame || "frame", x, y, rot, h: 8 * 0.3048, beam: 0, reach: 0, beam_on: false }] }, { label: "Add Frame", select: true });
  }

  /** The library's Recent: the last pieces put down from each library, this viewer's own. */
  const RECENT_KEY = `shotlister.planrecent`;
  function recentIds(lib) {
    try { return (JSON.parse(localStorage.getItem(RECENT_KEY) || "{}")[lib] || []); } catch { return []; }
  }
  function rememberUse(s) {
    try {
      const all = JSON.parse(localStorage.getItem(RECENT_KEY) || "{}");
      const lib = s.lib || (s.light ? "light" : "set");
      all[lib] = [s.id, ...(all[lib] || []).filter((x) => x !== s.id)].slice(0, 6);
      localStorage.setItem(RECENT_KEY, JSON.stringify(all));
    } catch { /* a convenience only */ }
  }

  /**
   * A point snapped (the Mac's `snapped`, the engine's `walls::snap`): onto a
   * wall's corner or line in reach, lined up square with a corner — the
   * line-ups kept in `guides` to draw — else the grid of the step the page
   * shows. `own`: the wall corner being dragged or drawn, `{id, corner}`.
   */
  function snapped(x, y, free, own = null) {
    if (free) { guides = []; return [x, y]; }
    const [sx, sy] = shownOf(x, y);
    const s = where("snap", sx, sy, { reach: 10 / view().k, step: snapStep(), own });
    if (!s || s.sx === undefined) return [x, y];
    guides = own || tool === "wall" ? (s.guides || []) : [];
    return [s.sx, s.sy];
  }

  // ------------------------------------------------------------ the pointer

  /**
   * What is under the pointer. What the picture drew on top wins — a
   * camera's name tag, a person's label, a picture — then the engine's own
   * test, which knows a wall's line and a lamp's footprint.
   */
  function hitAt(px, py, target) {
    // **A locked piece is clicked straight through** (Scenario's way): a
    // floor plan locked under everything no longer swallows the clicks
    // meant for what stands on it. Layers still picks it, to unlock.
    const locked = got ? (got.els || []).filter((e) => e.locked).map((e) => e.id).concat(backIds()) : [];
    const drawnHit = target && target.closest && target.closest("[data-el]");
    if (drawnHit && !["cone", "beam", "level", "ghost", "aim", "sun"].includes(drawnHit.getAttribute("data-part"))) {
      const id = drawnHit.getAttribute("data-el");
      if (el(id) && !locked.includes(id)) return id;
    }
    const [sx, sy] = toShown(px, py);
    const said = where("hit", sx, sy, { tol: 7 / view().k, beat: H.beat(), skip: [...hiddenIds(), ...locked], ...pageAsk() });
    return said && said.id ? said.id : null;
  }

  /** The editor's switch for the share link: whether visitors on it may draw. */
  function linkSwitch() {
    if (HUB.role !== "editor") return "";
    return `<button type="button" class="pact pwide${publicEdit ? " on" : ""}" data-plink="1" title="Whether people who open the share link can draw on the diagrams. Click to switch.">${publicEdit ? "Link can edit ✓" : "Link: view only"}</button>${publicEdit || linkSeen ? `<button type="button" class="pact pwide" data-plinkedits="1" title="What people on the share link changed, and when">Link Edits</button>` : ""}`;
  }

  // ---- what link visitors drew (his history of them, 2026-10-17) -------------
  //
  // Every batch a visitor on the share link sends is kept by the server with
  // who ("Link visitor" and four letters of their browser's name), when,
  // what, on which plan, and the server's own edits that take it back
  // (`hub/src/linkedits.js`). Here he reads them and takes any back: Undo is
  // his own edit, so his Undo takes that back in turn.
  let linkSeen = false, linkPanel = null;
  if (HUB.role === "editor") {
    fetch(`/f/${HUB.project}/api/diagram/linkedits`, { credentials: "same-origin" })
      .then((r) => (r.ok ? r.json() : null))
      .then((said) => { if (said && (said.edits || []).length) { linkSeen = true; H.draw(); } })
      .catch(() => { /* none shown */ });
  }
  async function openLinkEdits() {
    linkPanel = { edits: null };
    float();
    try {
      const r = await fetch(`/f/${HUB.project}/api/diagram/linkedits`, { credentials: "same-origin", cache: "no-store" });
      linkPanel = { edits: r.ok ? ((await r.json()).edits || []) : [] };
    } catch { linkPanel = { edits: [] }; }
    float();
  }
  function linkFloat(f) {
    f.className = "planfloat lib plinkedits";
    const list = linkPanel.edits;
    const when = (iso) => { const d = new Date(iso); const today = new Date().toDateString() === d.toDateString(); return today ? d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : d.toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }); };
    const where = (id) => { const p = planOf(id); if (p) return p.name; const s = sceneOf(id); if (!s) return "A plan since deleted"; const d = (s.diagrams || []).find((x) => x.id === id); return `${s.number}${d && (s.diagrams || []).length > 1 ? ` · ${d.title}` : ""}`; };
    f.innerHTML = `<div class="plibhead"><b>Link Edits</b><button type="button" class="lact" data-plinkclose="1">Close</button></div>
      <div class="pcastlist">${list === null ? `<p class="empty planempty">Reading…</p>` : list.length ? list.map((x, i) => `<div class="pcastrow plinkrow${x.undone ? " undone" : ""}"><span><b>${esc(x.who || "Link visitor")}</b><em>${esc(when(x.at))} · ${esc(where(x.scene))}</em><i>${esc((x.did || []).join(", ") || `${x.ops} change${x.ops === 1 ? "" : "s"}`)}</i></span>${x.undone ? `<i>Undone</i>` : `<button type="button" class="lact" data-plinkundo="${i}">Undo</button>`}</div>`).join("") : `<p class="empty planempty">Nobody on the link has changed anything yet</p>`}</div>`;
    f.querySelector("[data-plinkclose]").addEventListener("click", () => { linkPanel = null; float(); });
    f.querySelectorAll("[data-plinkundo]").forEach((b) => b.addEventListener("click", async () => {
      const x = list[Number(b.dataset.plinkundo)];
      if (!x || !Array.isArray(x.undo) || !x.undo.length) return;
      if (!editor()) setEditing(true);
      if (!editor()) return;
      const r = edits(x.undo, `Undo ${x.who}`, x.scene);
      if (r.back.length) { undos.push({ scene: r.scene, ops: r.back, label: `Undo ${x.who}`, at: Date.now() }); redos.length = 0; }
      x.undone = true;
      paint(); H.relook();
      try { await fetch(`/f/${HUB.project}/api/diagram/linkedits`, { method: "PUT", credentials: "same-origin", headers: { "content-type": "application/json" }, body: JSON.stringify({ key: x.key, undone: true }) }); } catch { /* the list says Undone here; the server learns next time */ }
      toast(`Took back ${x.who}'s change`);
      float();
    }));
  }

  function wire() {
    if (H.mode() !== "diagrams") { if (play) stop(false); closeMenu(); return; }
    root.querySelectorAll("[data-pmeasure]").forEach((x) => x.addEventListener("click", () => setMeasuring(!measuring)));
    root.querySelectorAll("[data-plink]").forEach((x) => x.addEventListener("click", async () => {
      try {
        const r = await fetch(`/f/${HUB.project}/api/diagram/settings`, { method: "PUT", credentials: "same-origin",
          headers: { "content-type": "application/json" }, body: JSON.stringify({ publicEdit: !publicEdit }) });
        if (!r.ok) throw new Error(String(r.status));
        publicEdit = Boolean((await r.json()).publicEdit);
        toast(publicEdit ? "Anyone with the share link can now edit the diagrams" : "The share link is view only again");
        H.draw();
      } catch { toast("Couldn't change that", true); }
    }));
    root.querySelectorAll("[data-pedit]").forEach((x) => x.addEventListener("click", () => setEditing(!editor())));
    root.querySelectorAll("[data-plinkedits]").forEach((x) => x.addEventListener("click", () => (linkPanel ? (linkPanel = null, float()) : openLinkEdits())));
    const b = box();
    if (!b) return;
    const vp = b.vp;
    paint();
    if (refocus === "plan") vp.focus({ preventScroll: true });
    else if (refocus !== false) {
      // Typing in the library's search when the film was read: still typing.
      const find = root.querySelector(".plibfind");
      if (find) { find.focus({ preventScroll: true }); find.setSelectionRange(refocus, refocus); }
    }
    refocus = false;
    root.querySelectorAll("[data-player]").forEach((t) => t.addEventListener("click", () => setLayer(t.dataset.player)));
    root.querySelectorAll(".plantools [data-ptool][draggable]").forEach((t) => t.addEventListener("dragstart", (ev) => {
      ev.dataTransfer.setData("text/x-plan-tool", t.dataset.ptool);
      ev.dataTransfer.effectAllowed = "copy";
    }));
    root.querySelectorAll("[data-ptool]").forEach((t) => t.addEventListener("click", () => {
      const more = t.closest(".pmore");
      if (more) more.open = false;
      // **Camera offers its choices first** (his note, 2026-09-29): which
      // shot — then a click on the plan puts it there.
      if (t.dataset.ptool === "camera" && editor() && !planOf(chosen())) return cameraChoices(t);
      armedShot = "new";
      setTool(t.dataset.ptool);
    }));
    const fv = root.querySelector("[data-pfavs]");
    if (fv) fv.addEventListener("click", () => { favOpen = !favOpen; libOpen = false; castMenu = null; picMenu = false; fv.classList.toggle("on", favOpen); float(); });
    const mn = root.querySelector("[data-pmany]");
    if (mn) mn.addEventListener("click", () => { many = !many; mn.classList.toggle("on", many); });
    const u = root.querySelector("[data-pundo]"), r = root.querySelector("[data-predo]");
    if (u) u.addEventListener("click", undo);
    if (r) r.addEventListener("click", redo);
    const pr = root.querySelector("[data-ppresent]");
    if (pr) pr.addEventListener("click", present);
    const vw = root.querySelector("[data-pview]");
    if (vw) vw.addEventListener("click", () => (viewPanel && viewPanel.anchor === vw ? closeView() : openView(vw)));
    if (vw && viewPanel) { viewPanel.anchor = vw; placeView(); }
    const ex = root.querySelector("[data-pexport]");
    if (ex) ex.addEventListener("click", () => exportMenu(ex));
    const cp = root.querySelector("[data-pcopymenu]");
    if (cp) cp.addEventListener("click", () => copyMenu(cp));
    const pm = root.querySelector("[data-pplanmenu]");
    if (pm) pm.addEventListener("click", () => planMenu(pm));
    root.querySelectorAll("[data-pnewplan]").forEach((b) => b.addEventListener("click", (ev) => { ev.stopPropagation(); newPlan(); }));
    // A scene's diagrams, and Hide Empty (`chosen`, `rows`).
    root.querySelectorAll("[data-pdtab]").forEach((b) => {
      b.addEventListener("click", () => {
        if (b.dataset.held) { delete b.dataset.held; return; }
        const r = row();
        if (!r || tabs.get(r) === b.dataset.pdtab) return;
        tabs.set(r, b.dataset.pdtab);
        chose();
        H.draw();
      });
      if (!editor()) return;
      const d = () => ((sceneDiagrams() || { all: [] }).all.find((x) => x.id === b.dataset.pdtab));
      b.addEventListener("dblclick", () => { const x = d(); if (x) renameDiagram(b, x); });
      b.addEventListener("contextmenu", (ev) => { ev.preventDefault(); diagramMenu(b, b.dataset.pdtab, [ev.clientX, ev.clientY]); });
      // A long press, for a finger (the iPhone's).
      let press = 0;
      b.addEventListener("pointerdown", (ev) => {
        if (ev.pointerType === "mouse") return;
        press = setTimeout(() => { b.dataset.held = "1"; diagramMenu(b, b.dataset.pdtab); }, 500);
      });
      for (const k of ["pointerup", "pointercancel", "pointerleave"]) b.addEventListener(k, () => clearTimeout(press));
    });
    root.querySelectorAll("[data-pdnew]").forEach((b) => b.addEventListener("click", () => newDiagram()));
    root.querySelectorAll("[data-pphototool]").forEach((b) => b.addEventListener("click", () => setPhotoTool(b.dataset.pphototool)));
    root.querySelectorAll("[data-pphotoundo]").forEach((b) => b.addEventListener("click", () => { if (photo) photo.picked = null; undo(); }));
    root.querySelectorAll("[data-pphotoredo]").forEach((b) => b.addEventListener("click", () => { if (photo) photo.picked = null; redo(); }));
    root.querySelectorAll("[data-pdmenu]").forEach((b) => b.addEventListener("click", () => diagramMenu(b, String(chosen()))));
    document.querySelectorAll("[data-phideempty]").forEach((b) => b.addEventListener("click", (ev) => { ev.stopPropagation(); setHideEmpty(b.dataset.phideempty === "off"); H.draw(); }));
    document.querySelectorAll("[data-pshowempty]").forEach((b) => b.addEventListener("click", (ev) => { ev.stopPropagation(); revealHidden = !revealHidden; H.draw(); }));
    // Hide from Diagrams: right-click, a long press or ⋯ on a scene row; ⌘/Ctrl-click or ⇧-click marks several.
    document.querySelectorAll("[data-pdscene]").forEach((row) => {
      const id = row.dataset.pdscene;
      row.addEventListener("click", (ev) => {
        if (ev.target.closest("[data-pdscenemenu]")) return;
        if (ev.metaKey || ev.ctrlKey || ev.shiftKey) {
          ev.preventDefault(); ev.stopImmediatePropagation();
          if (marked.has(id)) marked.delete(id); else marked.add(id);
          row.classList.toggle("mark", marked.has(id));
        } else if (marked.size) marked.clear();
      }, true);
      row.addEventListener("contextmenu", (ev) => { ev.preventDefault(); sceneMenu(id, [ev.clientX, ev.clientY]); });
      let press = 0;
      row.addEventListener("pointerdown", (ev) => {
        if (ev.pointerType === "mouse") return;
        press = setTimeout(() => { row.dataset.held = "1"; sceneMenu(id, [ev.clientX, ev.clientY]); }, 500);
      });
      for (const k of ["pointerup", "pointercancel", "pointerleave"]) row.addEventListener(k, () => clearTimeout(press));
    });
    document.querySelectorAll("[data-pdscenemenu]").forEach((b) => b.addEventListener("click", (ev) => {
      ev.preventDefault(); ev.stopPropagation();
      const r = b.getBoundingClientRect();
      sceneMenu(b.dataset.pdscenemenu, [r.left, r.bottom + 2]);
    }));

    vp.querySelectorAll("[data-pzoom]").forEach((z) => z.addEventListener("click", () => {
      const v = view();
      if (z.dataset.pzoom === "fit") { if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" }); return paint(); }
      zoomAt(z.dataset.pzoom === "in" ? 1.35 : 1 / 1.35, vp.clientWidth / 2, vp.clientHeight / 2);
      commit();
    }));

    const pointers = new Map();
    let spaceHeld = false;
    let lastDown = null;            // the last press, for a second one to make a double
    function doubleAt(px, py, target) {
      if (wallDraw) { finishWall(); return; }
      const hd = target && target.closest && target.closest("[data-h]");
      if (editor() && hd && /^wc\d+$/.test(hd.getAttribute("data-h")) && picks.length === 1) {
        const e = el(picks[0]);
        if (e && (e.kind === "wall" || isPath(e))) {
          const i = Number(hd.getAttribute("data-h").slice(2));
          pickedCorner = i; sideKey = "";
          edit({ op: "wall_smooth", id: e.id, corner: i, smooth: !isSmooth(e, i) }, { label: isSmooth(e, i) ? "Sharp Corner" : "Smooth Corner" });
          return;
        }
      }
      const hit = editor() && tool === "select" ? hitAt(px, py, target) : null;
      if (hit) {
        const e = el(hit);
        // Into a group: one of its pieces, picked on its own.
        if (e && e.group && picks.length > 1 && picks.includes(hit)) { picks = [hit]; sideKey = ""; paint(); return; }
        picks = [hit]; legendPick = null;
        if (e && e.kind === "camera") cam = hit;
        // A picture double-clicked: drawn on (the Mac's).
        if (e && e.kind === "image" && !(target && target.closest && target.closest('[data-part="label"]'))) { setTimeout(() => drawOnPhoto(hit), 0); return; }
        // **On its words, typing there** (his call F): a lamp's Name or
        // Note by the line pressed, Words' words, a piece's name. On the
        // piece itself, its Details (Ref 1356).
        const words = target && target.closest && target.closest('[data-part="label"]');
        // Typing starts once the press is over: the press itself puts the
        // keys on the plan as it goes down, and would take them back.
        const later = (id, field) => setTimeout(() => typeOn(el(id), field), 0);
        if (e && isShared(e)) {
          // A shared label's first line is its lamps' Name, the rest their Note.
          const line = target && target.closest && target.closest("tspan");
          const at = line ? [...line.parentNode.querySelectorAll("tspan")].indexOf(line) : 0;
          const lead = heldBy(e.id)[0];
          sideKey = ""; paint();
          return later(lead.id, at > 0 || !isLamp(lead) ? noteField(lead) : "name");
        }
        if (e && (e.kind === "text" || e.kind === "note")) { sideKey = ""; paint(); return later(hit, "text"); }
        if (words && e) {
          if (isLamp(e) || isShared(e)) {
            const lead = isShared(e) ? heldBy(e.id)[0] : e;
            const first = isShared(e) || Boolean((lead.label_lines || [])[0]);
            const second = target.closest("tspan") && [...words.querySelectorAll("tspan")].indexOf(target.closest("tspan")) > 0;
            sideKey = ""; paint();
            return later(lead.id, second || !first ? "note" : "name");
          }
          sideKey = ""; paint();
          return later(hit, "label");
        }
        tab = "details"; sideKey = ""; paint();
        return;
      }
      zoomAt(1.6, px, py);
      commit();
    }
    const local = (ev) => { const rr = vp.getBoundingClientRect(); return [ev.clientX - rr.left, ev.clientY - rr.top]; };

    vp.addEventListener("pointerdown", (ev) => {
      if (ev.target.closest(".planzoom, .planfloat, .plansheet, .plantoast, .plantools, .planmenu, .planrename, .plancompass")) return;
      const line = ev.target.closest(".ppitem");
      if (line && (!editor() || tool === "select")) {
        if (line.classList.contains("intype")) return;
        ev.preventDefault();
        pageClick(Number(line.dataset.ppitem));
        return;
      }
      if (ev.pointerType === "mouse" && ev.button !== 0 && ev.button !== 1) return;
      try { vp.setPointerCapture(ev.pointerId); } catch { /* a pointer already gone */ }
      vp.focus({ preventScroll: true, focusVisible: false });
      pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
      const cur = live || { tx: 0, ty: 0, s: 1 };
      if (pointers.size === 2) {
        // A second finger: whatever the first was doing becomes a pinch.
        if (drag && drag.kind !== "pan") { preview = null; }
        const [a, c] = [...pointers.values()];
        const rr = vp.getBoundingClientRect();
        drag = { kind: "pinch", d: Math.hypot(a.x - c.x, a.y - c.y) || 1, mx: (a.x + c.x) / 2 - rr.left, my: (a.y + c.y) / 2 - rr.top, tx: cur.tx, ty: cur.ty, s: cur.s, moved: true };
        return;
      }
      if (pointers.size > 2) return;
      const [px, py] = local(ev);
      if (photo && editor()) {
        // **Drawing on a picture**: a drag draws or moves a mark; Space, the
        // middle button or Move View slide the view; two fingers pinch.
        const base = { x: ev.clientX, y: ev.clientY, px, py, px0: px, py0: py, moved: false, shift: ev.shiftKey, alt: ev.altKey, meta: ev.metaKey || ev.ctrlKey, touch: ev.pointerType !== "mouse" };
        if (tool === "hand" || spaceHeld || ev.button === 1) { drag = { ...base, kind: "pan", tx: cur.tx, ty: cur.ty, s: cur.s }; return; }
        drag = photoDown(base, px, py);
        return;
      }
      // **A double press**, timed here: into a group, a camera's shot, a
      // text's words, or closer in.
      const now = performance.now();
      const twice = Boolean(lastDown) && now - lastDown.t < 400 && Math.hypot(ev.clientX - lastDown.x, ev.clientY - lastDown.y) < 8 && (ev.pointerType !== "mouse" || ev.button === 0);
      lastDown = twice ? null : { t: now, x: ev.clientX, y: ev.clientY };
      if (twice && editor() && tool === "pen" && penNodes.length) { drag = { kind: "none", x: ev.clientX, y: ev.clientY, moved: false }; finishPen(false); return; }
      if (twice && editor() && tool === "cable" && chainPts.length) { drag = { kind: "none", x: ev.clientX, y: ev.clientY, moved: false }; finishChain(); return; }
      if (twice && !(measuring && !editor()) && (!editor() || tool === "select" || tool === "hand" || wallDraw)) { drag = { kind: "none", x: ev.clientX, y: ev.clientY, moved: false }; doubleAt(px, py, ev.target); return; }
      const base = { x: ev.clientX, y: ev.clientY, px, py, px0: px, py0: py, moved: false, shift: ev.shiftKey, alt: ev.altKey, meta: ev.metaKey || ev.ctrlKey, touch: ev.pointerType !== "mouse" };
      const panNow = !editor() || tool === "hand" || spaceHeld || ev.button === 1;
      // Looking, a press that does not move is a tap: what is under it is
      // looked at when it lets go (`lookAt`).
      if (panNow) { drag = { ...base, kind: "pan", tx: cur.tx, ty: cur.ty, s: cur.s, look: !editor() && ev.button === 0 && !measuring, measure: !editor() && ev.button === 0 && measuring, shift: ev.shiftKey, alt: ev.altKey, target: ev.target }; return; }
      const handle = ev.target.closest && ev.target.closest("[data-h]");
      const [x, y] = toStored(px, py);
      // **Set Scale**: a line dragged across something of known length.
      if (calibrating) { drag = { ...base, kind: "calib", a: [x, y], b: [x, y] }; return; }
      if (handle && handle.getAttribute("data-h") === "boxturn" && picks.length) {
        // The pick's box's knob: a wall, several, a group — turned about a
        // grid point, the first piece's heading kept to round angles.
        const els = picks.map(el).filter((e) => e && !e.locked);
        const p = pivot(els);
        drag = { ...base, kind: "boxturn", ids: els.map((e) => e.id), pivot: p, from: Math.atan2(y - p[1], x - p[0]) * 180 / Math.PI, base: heading(els[0]), deg: 0 };
        return;
      }
      if (handle && picks.length === 1) {
        const e = el(picks[0]);
        if (e) {
          const h = handle.getAttribute("data-h");
          if (cornered(e) && /^(wc|add|ext)\d+$/.test(h)) return wallHandleDown(e, h, x, y, base);
          // A step's ring or knob picks that step.
          const hk = /^h(in|out)(\d+)$/.exec(h);
          if (hk) {
            const i = Number(hk[2]), c = wallCorners(e)[i], v = nodeHandles(e, i);
            const at = hk[1] === "out" ? [c[0] + v[2], c[1] + v[3]] : [c[0] + v[0], c[1] + v[1]];
            drag = { ...base, kind: "handle", h, e, x, y, grab: [at[0] - x, at[1] - y] };
            return;
          }
          const st = /^step(?:turn)?(\d+)$/.exec(h);
          if (st) { pickedStep = { id: e.id, i: Number(st[1]) }; sideKey = ""; }
          drag = { ...base, kind: "handle", h, e, x, y };
          return;
        }
      }
      const nameOf = ev.target.closest && ev.target.closest('[data-part="label"]');
      if (tool === "select" && nameOf && picks.length === 1 && nameOf.getAttribute("data-el") === picks[0]) {
        // A picked piece's name, dragged: the name moves, the piece stays (the Mac's lane D).
        const e = el(picks[0]);
        if (e) { drag = { ...base, kind: "handle", h: "name", e, x: toStored(px, py)[0], y: toStored(px, py)[1], nx: +(nameOf.getAttribute("data-nx") || 0), ny: +(nameOf.getAttribute("data-ny") || 0) }; return; }
      }
      if (tool === "select" && !base.shift) {
        // **A storyboard frame laid on the plan** (Ref 1517, the Mac's
        // `nameDown`): pressed, it moves; by a corner, it grows or shrinks,
        // its own shape kept, the opposite corner standing still.
        const fr = frameAt(px, py);
        if (fr) {
          picks = [fr.e.id]; cam = fr.e.id; legendPick = null; sideKey = "";
          if (fr.e.locked) { drag = { ...base, kind: "none" }; paint(); return; }
          const dx = fr.e.frame_dx ?? 0, dy = fr.e.frame_dy ?? 1.4;
          if (fr.corner !== null) {
            const c = fr.corners, held = c[fr.corner], anchor = c[(fr.corner + 2) % 4];
            const k = view().k;
            drag = { ...base, kind: "fsize", id: fr.e.id, anchor, cam: [fr.mid[0] - dx * k, fr.mid[1] - dy * k], sx: held[0] >= anchor[0] ? 1 : -1, sy: held[1] >= anchor[1] ? 1 : -1, aspect: fr.w > 0 ? fr.h / fr.w : 9 / 16 };
          } else drag = { ...base, kind: "frame", id: fr.e.id, dx, dy };
          paint();
          return;
        }
      }
      if (tool === "select") {
        const hit = hitAt(px, py, ev.target);
        if (hit) {
          if (base.shift || base.meta || many) { pickOne(hit, false, true); drag = { ...base, kind: "none" }; return; }
          // A press on the wall already picked: let go without moving, and
          // the stretch under the hand is picked, for its length.
          const again = picks.length === 1 && picks[0] === hit && (el(hit) || {}).kind === "wall";
          if (!again) { pickedCorner = null; pickedStretch = null; }
          // The piece itself, not one of its steps.
          if (pickedStep) { pickedStep = null; sideKey = ""; }
          // A piece of a group takes its group: a group is one thing (the Mac's).
          if (!picks.includes(hit)) { picks = groupOf(hit); legendPick = null; const e = el(hit); if (e && e.kind === "camera") cam = hit; sideKey = ""; paint(); }
          const movable = picks.map(el).filter((e) => e && !e.locked);
          const lead = movable.find((e) => e.id === hit) || movable[0];
          // A label moves on its own; the lamps tied to it stay put (his call, 2026-10-04).
          drag = { ...base, kind: movable.length ? "move" : "none", x, y, ids: movable.map((e) => e.id), lead, again, anchor: lead ? anchorOf(movable, lead, [x, y]) : null };
          return;
        }
        // Empty ground: a box to pick with on a desk; the view moves under a finger.
        if (base.touch) drag = { ...base, kind: "pan", tx: cur.tx, ty: cur.ty, s: cur.s, clear: true };
        else drag = { ...base, kind: "marquee", keep: base.shift ? picks.slice() : [] };
        return;
      }
      if (tool === "wall") {
        // **One wall, corner by corner** (the Mac's): the first stretch
        // makes the wall, each click after grows it on — one step to take
        // back each — and a click on its first corner closes it. ⇧ as the
        // first corner goes down draws a whole room: one closed wall.
        if (wallDraw) { drag = { ...base, kind: "none" }; wallClick(x, y, base); return; }
        const a = snapped(x, y, base.alt);
        drag = base.shift ? { ...base, kind: "draw", room: true, a, b: a } : { ...base, kind: "wallleg", a, b: a };
        return;
      }
      if (tool === "shape" || LINE_TOOLS.has(tool)) {
        const [ax, ay] = tool === "shape" ? [x, y] : snapped(x, y, base.alt);
        drag = { ...base, kind: "draw", a: [ax, ay], b: [ax, ay] };
        return;
      }
      if (tool === "pen") {
        // A click is a corner; pulled, a curve. A click on the first point closes it.
        const q = snapped(x, y, base.alt);
        if (penNodes.length >= 3 && Math.hypot(q[0] - penNodes[0].p[0], q[1] - penNodes[0].p[1]) * view().k < 9) { drag = { ...base, kind: "none" }; finishPen(true); return; }
        penNodes.push({ p: q, hin: [0, 0], hout: [0, 0] });
        drag = { ...base, kind: "node" };
        float(); frame();
        return;
      }
      if (tool === "cable") { chainPts.push(snapped(x, y, base.alt)); drag = { ...base, kind: "none" }; frame(); return; }
      if (tool === "picture") { picMenu = true; float(); drag = { ...base, kind: "none" }; return; }
      const [ax, ay] = snapped(x, y, base.alt);
      drag = { ...base, kind: "place", a: [ax, ay] };
    });

    vp.addEventListener("pointermove", (ev) => {
      { const [qx, qy] = local(ev); if (view()) pointer = toStored(qx, qy); }
      if (!pointers.has(ev.pointerId) || !drag) {
        if (!pointers.size && ev.pointerType === "mouse") { const [qx, qy] = local(ev); hoverMove(qx, qy, ev); }
        return;
      }
      pointers.set(ev.pointerId, { x: ev.clientX, y: ev.clientY });
      if (drag.kind === "pinch" && pointers.size >= 2) {
        const [a, c] = [...pointers.values()];
        const rr = vp.getBoundingClientRect();
        const d = Math.hypot(a.x - c.x, a.y - c.y) || 1;
        const mx = (a.x + c.x) / 2 - rr.left, my = (a.y + c.y) / 2 - rr.top;
        const v = view();
        if (!v) return;
        const s = Math.max((v.fitK * 0.35) / v.k, Math.min(700 / v.k, drag.s * (d / drag.d)));
        const g = s / drag.s;
        live = { tx: mx - (drag.mx - drag.tx) * g, ty: my - (drag.my - drag.ty) * g, s };
        return move();
      }
      const dx = ev.clientX - drag.x, dy = ev.clientY - drag.y;
      if (!drag.moved && Math.hypot(dx, dy) < TAP) return;
      drag.moved = true;
      lastDown = null;
      const [px, py] = local(ev);
      if (drag.kind === "pan") { vp.classList.add("dragging"); live = { tx: drag.tx + dx, ty: drag.ty + dy, s: drag.s }; return move(); }
      if (drag.kind === "none") return;
      if (drag.kind === "photo") { photoMove(drag, px, py); return frame(); }
      const [x, y] = toStored(px, py);
      if (drag.kind === "node") {
        // Pulled out from the point it was pressed on: the curve there, the
        // other handle opposite — a corner again if it is not pulled far.
        const n = penNodes[penNodes.length - 1];
        if (n) {
          const v = [x - n.p[0], y - n.p[1]];
          const far = Math.hypot(v[0], v[1]) * view().k > 5;
          n.hout = far ? v : [0, 0];
          n.hin = far ? [-v[0], -v[1]] : [0, 0];
        }
        return frame();
      }
      // ⌥ as a move begins copies (the Mac's); ⌘ then moves it free.
      drag.free = (drag.kind === "move" && drag.alt ? false : ev.altKey) || ev.metaKey || ev.ctrlKey;
      drag.shiftNow = ev.shiftKey;
      drag.px = px; drag.py = py;
      if (drag.kind === "marquee") return marquee(drag, px, py);
      if (drag.kind === "calib") {
        drag.b = constrained(drag.a, [x, y], ev.shiftKey, true);
        readout = { px, py, text: lengthText(Math.hypot(drag.b[0] - drag.a[0], drag.b[1] - drag.a[1])) };
        showReadout();
        return frame();
      }
      if (drag.kind === "frame") {
        const k = view().k;
        const set = { frame_dx: r3(drag.dx + (px - drag.px0) / k), frame_dy: r3(drag.dy + (py - drag.py0) / k) };
        preview = { op: "update", ids: [drag.id], set };
        return frame();
      }
      if (drag.kind === "fsize") {
        // As wide as the pointer is from the corner that stays, across or
        // down, its own shape kept; never under a foot.
        const k = view().k, a = drag.aspect, [ax, ay] = drag.anchor;
        const across = Math.max(drag.sx * (px - ax), drag.sy * (py - ay) / Math.max(a, 0.01), 0.3 * k);
        const mid = [ax + drag.sx * across / 2, ay + drag.sy * across * a / 2];
        preview = { op: "update", ids: [drag.id], set: { frame_w: r3(across / k), frame_dx: r3((mid[0] - drag.cam[0]) / k), frame_dy: r3((mid[1] - drag.cam[1]) / k) } };
        readout = { px, py, text: lengthText(across / k) };
        return frame();
      }
      guides = [];
      if (drag.kind === "move") {
        preview = moveOp(drag, x, y);
        if (drag.alt && preview && !Array.isArray(preview) && preview.op === "move") preview = { op: "duplicate", ids: preview.ids, dx: preview.dx, dy: preview.dy };
      }
      else if (drag.kind === "handle") preview = handleOp(drag, x, y, px, py);
      else if (drag.kind === "boxturn") preview = boxTurnOp(drag, x, y);
      else if (drag.kind === "wallleg") {
        drag.b = constrained(drag.a, snapped(x, y, drag.free), drag.shiftNow, drag.free);
        if (drag.shiftNow) guides = [];
        preview = Math.hypot(drag.b[0] - drag.a[0], drag.b[1] - drag.a[1]) > 0.05 ? { op: "add", els: [{ kind: "wall", x: drag.a[0], y: drag.a[1], x2: drag.b[0], y2: drag.b[1] }] } : null;
        readout = { px, py, text: lengthText(Math.hypot(drag.b[0] - drag.a[0], drag.b[1] - drag.a[1])) };
      }
      else if (drag.kind === "draw") {
        const b = tool === "shape" || drag.room ? snapped(x, y, drag.free) : snapped(x, y, drag.free);
        drag.b = LINE_TOOLS.has(tool) ? constrained(drag.a, b, drag.shiftNow, drag.free) : b;
        if (drag.room || tool === "shape") guides = [];
        preview = drawOp(drag);
        // A connector from a label to a lamp is shown as the tie it will be.
        if (tool === "connector") {
          const pair = tiePair(...storedToBox(...drag.a), px, py);
          if (pair) preview = { op: "share_label", ids: pair };
        }
        const [dx, dy] = [drag.b[0] - drag.a[0], drag.b[1] - drag.a[1]];
        readout = { px, py, text: drag.room || tool === "shape" ? `${lengthText(Math.abs(dx))} × ${lengthText(Math.abs(dy))}` : lengthText(Math.hypot(dx, dy)) };
      }
      else if (drag.kind === "ink") { drag.pts.push([x, y]); preview = inkOp(drag); }
      else if (drag.kind === "place") {
        const far = Math.hypot(x - drag.a[0], y - drag.a[1]) * view().k > 8;
        drag.rot = far ? stepped((Math.atan2(y - drag.a[1], x - drag.a[0]) * 180) / Math.PI, drag.shiftNow, drag.free) : restingRot();
        readout = far ? { px, py, text: `${Math.round(drag.rot)}°` } : null;
        showReadout();
        return;
      }
      frame();
    });

    const up = (ev) => {
      if (!pointers.has(ev.pointerId)) return;
      pointers.delete(ev.pointerId);
      if (pointers.size > 0) {
        const [p] = [...pointers.values()];
        const cur = live || { tx: 0, ty: 0, s: 1 };
        drag = { kind: "pan", x: p.x, y: p.y, tx: cur.tx, ty: cur.ty, s: cur.s, moved: true };
        return;
      }
      vp.classList.remove("dragging");
      const d = drag;
      drag = null;
      guides = [];
      readout = null;
      showReadout();
      const box2 = vp.querySelector(".planmarq");
      if (box2) box2.remove();
      if (!d) return;
      if (d.kind === "photo") { const [qx, qy] = local(ev); photoUp(d, qx, qy); return; }
      if (d.kind === "node") { frame(); return; }
      if (d.kind === "calib") {
        const pic = calibrating, [a, b2] = [d.a, d.b];
        calibrating = null;
        const measured = Math.hypot(b2[0] - a[0], b2[1] - a[1]);
        frame();
        if (measured * view().k <= 6) return;
        const [qx, qy] = local(ev);
        const vr = vp.getBoundingClientRect();
        const spot = { getBoundingClientRect: () => ({ left: vr.left + qx, top: vr.top + qy, right: vr.left + qx, bottom: vr.top + qy, width: 0, height: 0 }) };
        return askValue(spot, { label: "Length", value: lengthText(measured), len: true, apply: (metres) => {
          const e = el(pic);
          if (!e || !(metres > 0)) return;
          const k = metres / measured;
          edit({ op: "update", ids: [pic], set: { w: r3(e.w * k), h: r3(e.h * k), x: r3(a[0] + (e.x - a[0]) * k), y: r3(a[1] + (e.y - a[1]) * k) } }, { label: "Set Scale" });
        } });
      }
      if (d.kind === "frame" || d.kind === "fsize") {
        const op = preview;
        preview = null;
        if (d.moved && op) edit(op, { label: d.kind === "frame" ? "Move Frame" : "Resize Frame" });
        else paint();
        return;
      }
      if (d.kind === "pinch" || d.kind === "pan") {
        if (!d.moved && d.clear) { picks = []; cam = null; sideKey = ""; paint(); }
        if (!d.moved && d.look) lookAt(hitAt(d.px, d.py, d.target));
        if (!d.moved && d.measure) measureTap(d.px, d.py, d.shift, d.alt);
        if (live) commit();
        return settleUp();
      }
      const [px, py] = local(ev);
      if (!d.moved) {
        preview = null;
        if (d.kind === "marquee") { picks = d.keep; cam = null; pickedCorner = null; pickedStretch = null; sideKey = ""; paint(); return; }
        if (d.kind === "place") { const [x, y] = d.a; return place(x, y, restingRot(), d.alt); }
        if (d.kind === "wallleg") { wallDraw = { pts: [d.a], id: null }; paint(); return; }
        if (d.kind === "move" && !d.shift) {
          const hit = hitAt(px, py);
          // One of several picked, clicked: that one alone — unless they are its group.
          if (hit && picks.length > 1) {
            const g = groupOf(hit);
            if (!(g.length === picks.length && g.every((id) => picks.includes(id)))) { picks = [hit]; sideKey = ""; }
          }
          if (d.again) {
            // The wall already picked, clicked: the stretch under the hand.
            const e = el(hit);
            if (cornered(e)) { pickedStretch = nearestStretch(e, toStored(px, py)); pickedCorner = null; sideKey = ""; }
          }
          paint();
        }
        if (d.kind === "handle") { sideKey = ""; paint(); }
        return;
      }
      if (d.kind === "place") { const [x, y] = d.a; return place(x, y, d.rot ?? restingRot(), d.alt); }
      if (d.kind === "marquee") { sideKey = ""; paint(); return; }
      if (d.kind === "wallleg") {
        // Pulled out: that wall stands, and the chain goes on from its far end.
        preview = null;
        const [a, b] = [d.a, d.b];
        if (Math.hypot(b[0] - a[0], b[1] - a[1]) * view().k > 6) {
          const made = edit({ op: "add", els: [{ kind: "wall", x: a[0], y: a[1], x2: b[0], y2: b[1] }] }, { label: "Add Wall", select: true });
          wallDraw = { pts: [a, b], id: made[0] || null };
        } else wallDraw = { pts: [a], id: null };
        paint();
        return settleUp();
      }
      const op = preview;
      preview = null;
      if (!op) return paint();
      if (d.kind === "handle" && d.h === "turn") {
        // Let go over another piece: the knob aims it there (the Mac's Aim At).
        const over = hitAt(px, py);
        if (over && over !== d.e.id) return edit({ op: "update", ids: [d.e.id], set: { aim: over } }, { label: "Aim" });
      }
      if (d.kind === "handle" && /^end\d$/.test(d.h) && d.e.kind === "arrow" && !Array.isArray(op)) {
        // **Arrows that stay attached**: an end let go on a piece is pinned to it.
        const on = pinTarget(px, py, [d.e.id]);
        if (on) op.set[d.h === "end0" ? "start_on" : "end_on"] = on;
      }
      if (d.kind === "handle" && /^wc\d+$/.test(d.h) && d.e.kind === "measure" && !Array.isArray(op) && op.op === "wall_corner") {
        // A ruler's marker let go on a person locks to them.
        const on = rulerTarget(px, py, [d.e.id], d.alt || d.meta);
        if (on) op.on = on;
      }
      if (d.kind === "draw" && tool === "measure" && op.els && op.els[0]) {
        // A ruler laid from or onto a person: that end's marker is locked to them.
        const [ax, ay] = storedToBox(...d.a);
        const a = rulerTarget(ax, ay, [], d.alt || d.meta), b = rulerTarget(px, py, [], d.alt || d.meta);
        if (a || b) op.els[0].pins = [a || "", b && b !== a ? b : ""];
      }
      if (d.kind === "draw" && (tool === "arrow" || tool === "connector") && op.els && op.els[0]) {
        // Drawn from a note to a piece: both ends pinned.
        const [ax, ay] = storedToBox(...d.a);
        const a = pinTarget(ax, ay, []), b = pinTarget(px, py, []);
        if (a) op.els[0].start_on = a;
        if (b && b !== a) op.els[0].end_on = b;
        // **A connector from a label to a lamp ties them**: the lamp shares
        // that label (Same Lamp), and the label's own lines join them. Drag
        // it again to the next lamp.
        const pair = tool === "connector" ? tiePair(ax, ay, px, py) : null;
        if (pair) {
          const made = edit({ op: "share_label", ids: pair }, { label: "Share Label" });
          if (made.length) { picks = [pair[0]]; sideKey = ""; paint(); return settleUp(); }
        }
      }
      if (d.kind === "move" && op.op === "duplicate") {
        const made = edit(op, { label: "Duplicate" });
        if (made.length) { picks = made; sideKey = ""; }
        paint();
        return settleUp();
      }
      const label = d.kind === "move" ? "Move" : d.kind === "boxturn" ? "Turn" : d.kind === "handle" ? (d.h === "turn" || d.h.startsWith("stepturn") ? "Turn" : d.h === "tilt" ? "Tilt" : /^step\d+$/.test(d.h) ? `Move ${((d.e.seq || [])[Number(d.h.slice(4))] || {}).letter || "Step"}` : d.h === "name" ? "Move Name" : d.h.startsWith("end") ? "Move End" : d.h.startsWith("wc") ? "Move Corner" : d.h === "curve" || /^h(in|out)/.test(d.h) ? "Curve" : d.h === "reach" ? "Reach" : "Resize") : d.kind === "draw" ? `Add ${d.room ? "Room" : word(tool)}` : `Add ${word(tool === "pen" ? "stroke" : "cable")}`;
      if (Array.isArray(op)) {
        const r = edits(op, label);
        undos.push({ scene: r.scene, ops: r.back, label });
        redos.length = 0;
        paint();
      } else {
        // A corner just added by its +, then dragged: one step to take back.
        edit(op, { label, select: d.kind === "draw" || d.kind === "ink", join: Boolean(d.made) });
      }
      if (d.kind === "draw" && !(d.alt && !d.room)) setTool("select");
      if (d.kind === "ink" && tool === "cable") setTool("select");
      settleUp();
    };
    vp.addEventListener("pointerup", up);
    vp.addEventListener("pointercancel", up);
    vp.addEventListener("pointerleave", () => {
      if (pointers.size) return;
      pointer = null;
      if (hover) { hover = null; frame(); }
    });

    vp.addEventListener("wheel", (ev) => {
      ev.preventDefault();
      const rr = vp.getBoundingClientRect();
      if (ev.ctrlKey || ev.metaKey) {
        zoomAt(Math.exp(-Math.max(-30, Math.min(30, ev.deltaY)) * 0.01), ev.clientX - rr.left, ev.clientY - rr.top);
      } else {
        const cur = live || { tx: 0, ty: 0, s: 1 };
        live = { ...cur, tx: cur.tx - ev.deltaX, ty: cur.ty - ev.deltaY };
        move();
      }
      soonCommit();
    }, { passive: false });

    // **A right-click on a piece** picks it and opens More by the pointer —
    // everything every piece has, and Swap… on a lamp or set piece.
    vp.addEventListener("contextmenu", (ev) => {
      if (!editor() || tool !== "select" || ev.target.closest(".planzoom, .planfloat, .plansheet, .plantoast, .plantools, .planmenu, .planrename")) return;
      const hit = hitAt(...local(ev), ev.target);
      ev.preventDefault();
      if (!hit) { if (picks.length) { picks = []; cam = null; sideKey = ""; paint(); } return emptyMenu([ev.clientX, ev.clientY]); }
      if (!picks.includes(hit)) pickOne(hit);
      openMore(null, [ev.clientX, ev.clientY]);
    });

    // A double press is caught in pointerdown (`doubleAt`): the plan is
    // drawn again on every press, and a browser's own dblclick never comes
    // to a picture that went away under it.

    // Something from the library dropped on the plan.
    vp.addEventListener("dragover", (ev) => { if (["text/x-plan-sym", "text/x-plan-pic", "text/x-plan-tool", "text/x-plan-shot", "text/x-plan-fav"].some((t) => ev.dataTransfer.types.includes(t))) ev.preventDefault(); });
    vp.addEventListener("drop", (ev) => {
      // A favorite dragged off its tile: put down where it is let go.
      const fav = ev.dataTransfer.getData("text/x-plan-fav");
      if (fav !== "" && editor()) {
        ev.preventDefault();
        const [x, y] = snapped(...toStored(...local(ev)), false);
        putFavorite(Number(fav), x, y);
        return;
      }
      // A shot dragged out of the Shots tab: its camera, where it is let go.
      const shotDrop = ev.dataTransfer.getData("text/x-plan-shot");
      if (shotDrop && editor()) {
        ev.preventDefault();
        const [x, y] = snapped(...toStored(...local(ev)), false);
        const n = (got.els || []).filter((e) => e.kind === "camera").length;
        edit({ op: "add", els: [{ kind: "camera", x, y, rot: 0, color: PALETTE[n % PALETTE.length], shot: shotDrop }] }, { label: "Place Shot", select: true });
        return;
      }
      // A tool dragged off the toolbar: its one thing put down where it is let go.
      const tk = ev.dataTransfer.getData("text/x-plan-tool");
      if (tk && editor() && DRAGGABLE.has(tk)) {
        ev.preventDefault();
        armedShot = "new";
        setTool(tk);
        const [x, y] = snapped(...toStored(...local(ev)), false);
        place(x, y, restingRot());
        return;
      }
      // A picture dragged out of Trace: laid where it is let go.
      const pic = ev.dataTransfer.getData("text/x-plan-pic");
      if (pic && editor()) {
        ev.preventDefault();
        const said = json(pic);
        const m = said && picPictures.get(said.hash);
        if (m) layPicture(m, toStored(...local(ev)), said.aspect || 0.66);
        return;
      }
      const id = ev.dataTransfer.getData("text/x-plan-sym");
      if (!id) return;
      ev.preventDefault();
      const s = (library().symbols || []).find((x) => x.id === id);
      if (!s) return;
      const [px, py] = local(ev);
      // ⇧ as it is let go over a set piece or a lamp: that piece becomes
      // this one, where it stands (the Mac's drop to swap).
      if (ev.shiftKey && editor()) {
        const on = el(hitAt(px, py));
        if (on && (on.kind === "set" || (on.kind === "light" && on.sym)) && on.sym !== s.id) {
          edit({ op: "swap", ids: [on.id], sym: s.id }, { label: `Swap to ${s.name}` });
          rememberUse(s);
          return;
        }
      }
      armed = s;
      const [x, y] = snapped(...toStored(px, py), false);
      place(x, y, s.light ? 270 : 0);
    });

    wireCompass(vp);
    vp.addEventListener("keydown", (ev) => keys(ev, vp));
    vp.addEventListener("keyup", (ev) => { if (ev.key === " ") spaceHeld = false; });
    vp.addEventListener("keydown", (ev) => { if (ev.key === " " && editor()) spaceHeld = true; });

    if (!watching) {
      watching = true;
      // **Delete wherever the keys are** (the Mac's): a row in Layers, the
      // side panel — anywhere but a field being typed in.
      document.addEventListener("keydown", (ev) => {
        if (H.mode() !== "diagrams" || !editor() || !picks.length || (ev.key !== "Delete" && ev.key !== "Backspace")) return;
        const a = document.activeElement;
        if (a && (/INPUT|TEXTAREA|SELECT/.test(a.tagName) || a.isContentEditable || a.classList.contains("planvp"))) return;
        if (menu) return;
        ev.preventDefault();
        remove(picks.slice());
      });
      window.addEventListener("resize", () => { if (H.mode() === "diagrams") requestAnimationFrame(paint); });
      document.addEventListener("fullscreenchange", () => { if (!document.fullscreenElement && presenting) present(); });
    }
  }

  let framed = 0;
  function frame() {
    if (framed) return;
    framed = requestAnimationFrame(() => { framed = 0; paint(); });
  }

  function marquee(d, px, py) {
    const vp = box().vp;
    let m = vp.querySelector(".planmarq");
    if (!m) { m = document.createElement("div"); m.className = "planmarq"; vp.append(m); }
    const x1 = Math.min(d.px, px), y1 = Math.min(d.py, py), x2 = Math.max(d.px, px), y2 = Math.max(d.py, py);
    Object.assign(m.style, { left: `${x1}px`, top: `${y1}px`, width: `${x2 - x1}px`, height: `${y2 - y1}px` });
    const inside = (got.els || []).filter((e) => {
      if (e.hidden || (e.show && off.has(e.show)) || e.locked || layerOf(e) !== layer) return false;
      const pts = cornered(e) ? wallCorners(e) : LINE_KINDS.has(e.kind) ? [[e.x, e.y], [e.x2, e.y2]] : (e.points && e.points.length ? e.points : [e.at ? [e.at[0], e.at[1]] : [e.x, e.y]]);
      return pts.every(([x, y]) => { const [bx, by] = storedToBox(x, y); return bx >= x1 && bx <= x2 && by >= y1 && by <= y2; });
    }).map((e) => e.id);
    const next = [...new Set([...d.keep, ...inside])];
    if (next.join(",") !== picks.join(",")) { picks = next; frame(); }
  }

  /**
   * **What lands on the grid when the pick is moved** (the Mac's
   * `snapRef`), one number each way: a lamp, a camera or a person by its
   * middle; a piece with a body by whichever of its edges is nearer the
   * hand; a wall by its corner nearest the hand; several by the edges of
   * the box round them all.
   */
  /**
   * **Line-up guides** (the Mac's `DiagramGuides`, Scenario's snap-align):
   * while pieces move with Snap on, a thin line where one of their points
   * lines up on screen with a point of another piece, and a pull onto it
   * within six points, ahead of the grid. A camera, lamp, person or words
   * line up by their middle; a set piece, frame, shape or picture by its
   * corners and middle; a wall, track or arrow by its ends (and a line's
   * middle). ⌘ moves free.
   */
  const GUIDE_REACH = 6;
  function lineUpPoints(e) {
    if (cornered(e)) return wallCorners(e);
    if (LINE_KINDS.has(e.kind)) return [[e.x, e.y], [e.x2, e.y2], [(e.x + e.x2) / 2, (e.y + e.y2) / 2]];
    if (e.points && e.points.length && (e.kind === "stroke" || e.kind === "cable")) return e.points;
    const [ax, ay] = e.at || [e.x, e.y];
    const centred = ["camera", "cast", "text"].includes(e.kind) || (e.kind === "light" && !isFrame(e));
    return centred ? [[ax, ay]] : [[ax, ay], ...pointsOf(e)];
  }
  function lineUp(ids, raw, grid, [lockX, lockY]) {
    const k = view() ? view().k : 0;
    if (!k || !got) return grid;
    // What moves with them: the pieces, and whatever rides on them.
    const moving = new Set(ids);
    for (let grew = true; grew;) { grew = false; for (const e of got.els || []) if (!moving.has(e.id) && e.rig_on && moving.has(e.rig_on)) { moving.add(e.id); grew = true; } }
    const unseen = new Set(hiddenIds());
    const mine = ids.map(el).filter(Boolean).flatMap(lineUpPoints).map(([x, y]) => storedToBox(x, y));
    if (!mine.length) return grid;
    const others = (got.els || []).filter((e) => !moving.has(e.id) && !e.hidden && !unseen.has(e.id) && e.kind !== "image")
      .flatMap(lineUpPoints).map(([x, y]) => storedToBox(x, y));
    // The moves on screen: as the hand has it, and as the grid has it.
    const onScreen = ([x, y]) => { const [sx, sy] = turnPt(x, y, turn()); return [sx * k, sy * k]; };
    const hand = onScreen(raw), snap = onScreen(grid);
    const best = (axis) => {
      let found = null;
      for (const w of others) for (const h of mine) {
        const gap = w[axis] - (h[axis] + hand[axis]);
        if (Math.abs(gap) <= GUIDE_REACH && (found === null || Math.abs(gap) < Math.abs(found))) found = gap;
      }
      return found;
    };
    const bx = lockX ? null : best(0), by = lockY ? null : best(1);
    if (bx === null && by === null) return grid;
    const off = [bx !== null ? hand[0] + bx : snap[0], by !== null ? hand[1] + by : snap[1]];
    // The lines to draw: through every point now lined up, end to end.
    const now = mine.map(([x, y]) => [x + off[0], y + off[1]]);
    const lines = [];
    for (const axis of [0, 1]) {
      if ((axis ? by : bx) === null) continue;
      const at = new Set(now.map((p) => Math.round(p[axis] * 2) / 2));
      for (const v of at) {
        const on = [...now, ...others].filter((p) => Math.abs(p[axis] - v) < 0.5);
        if (!on.some((p) => others.includes(p))) continue;
        const across = on.map((p) => p[1 - axis]);
        const lo = Math.min(...across) - 8, hi = Math.max(...across) + 8;
        const ends = axis ? [[lo, v], [hi, v]] : [[v, lo], [v, hi]];
        const [a, b] = ends.map(([x, y]) => toStored(x, y));
        lines.push([a[0], a[1], b[0], b[1]]);
      }
    }
    guides = lines;
    const [sx, sy] = [off[0] / k, off[1] / k];
    return turnPt(sx, sy, -turn());
  }

  function anchorOf(els, lead, [px, py]) {
    const nearer = (a, b, v) => (Math.abs(a - v) <= Math.abs(b - v) ? a : b);
    if (els.length > 1) { const b = extentOf(els); return b ? [nearer(b[0], b[2], px), nearer(b[1], b[3], py)] : null; }
    if (cornered(lead)) return wallCorners(lead).reduce((best, c) => (Math.hypot(c[0] - px, c[1] - py) < Math.hypot(best[0] - px, best[1] - py) ? c : best));
    if (LINE_KINDS.has(lead.kind)) return [nearer(lead.x, lead.x2, px), nearer(lead.y, lead.y2, py)];
    if (lead.points && lead.points.length) return lead.points[0];
    const [ax, ay] = lead.at || [lead.x, lead.y];
    if (faces(lead) || lead.kind === "text") return [ax, ay];
    const b = extentOf([lead]);
    return b ? [nearer(b[0], b[2], px), nearer(b[1], b[3], py)] : [ax, ay];
  }

  function moveOp(d, x, y) {
    let dx = x - d.x, dy = y - d.y;
    const lead = d.lead;
    // ⇧ keeps the move to one way.
    let lockX = false, lockY = false;
    if (d.shiftNow) { if (Math.abs(dx) > Math.abs(dy)) { dy = 0; lockY = true; } else { dx = 0; lockX = true; } }
    const raw = [dx, dy];
    if (settings().snap && !d.free && d.anchor) {
      const step = snapStep();
      const [ax, ay] = d.anchor;
      if (!lockX) dx = Math.round((ax + dx) / step) * step - ax;
      if (!lockY) dy = Math.round((ay + dy) / step) * step - ay;
    }
    // Lined up with another piece where the hand nearly has it, ahead of the grid.
    if (settings().snap && !d.free && !(d.ids.length === 1 && lead && (lead.kind === "door" || lead.kind === "window"))) {
      [dx, dy] = lineUp(d.ids, raw, [dx, dy], [lockX, lockY]);
    }
    readout = { px: d.px, py: d.py, text: `Δx ${lengthText(dx)}  Δy ${lengthText(dy)}` };
    const [lx, ly] = lead ? (lead.at || [lead.x, lead.y]) : [d.x, d.y];
    const beat = H.beat();
    if ((beatsMode || beat > 1) && d.ids.length) {
      // A beat: each piece is set where it stands at this beat — at beat 1 that is the piece itself.
      return d.ids.map((id) => {
        const e = el(id);
        const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
        return { op: "beat", id, beat, x: ax + dx, y: ay + dy, rot: arot };
      });
    }
    // A door or window slides along the wall it is on.
    if (lead && d.ids.length === 1 && (lead.kind === "door" || lead.kind === "window") && !d.free) {
      const [sx, sy] = shownOf(lx + dx, ly + dy);
      // Slid along it by the grid from the nearer corner's face, and how far said.
      const on = where("wall", sx, sy, { reach: Math.max(0.3, 16 / view().k), w: lead.w || 0, step: settings().snap ? snapStep() : 0 });
      if (on && on.x !== null && on.x !== undefined) {
        readout = { px: d.px, py: d.py, text: lengthText(Math.max(0, on.from || 0)) };
        let rot = on.rot;
        const turnBy = Math.abs(((((lead.rot - rot) % 360) + 540) % 360) - 180);
        if (turnBy > 90) rot = (rot + 180) % 360;
        return { op: "update", ids: [lead.id], set: { x: on.sx, y: on.sy, rot, h: on.thick } };
      }
    }
    return { op: "move", ids: d.ids, dx, dy };
  }

  const r3 = (n) => Math.round(n * 1000) / 1000;
  /**
   * The storyboard frame under a point, as the plan drew it (`shotframe`),
   * and which of its corners when within reach: its box in the plan's
   * pixels, its corners top left, top right, bottom right, bottom left.
   */
  function frameAt(px, py) {
    if (!frames || off.has("cameras")) return null;
    const svg = root.querySelector(".planpic > svg");
    if (!svg || !got) return null;
    const back = new Set(backIds());
    const boxes = new Map();
    svg.querySelectorAll('[data-part="shotframe"]').forEach((n) => {
      const id = n.getAttribute("data-el");
      if (back.has(id)) return;
      let b;
      try { b = n.getBBox(); } catch { return; }
      const was = boxes.get(id);
      boxes.set(id, was ? [Math.min(was[0], b.x), Math.min(was[1], b.y), Math.max(was[2], b.x + b.width), Math.max(was[3], b.y + b.height)] : [b.x, b.y, b.x + b.width, b.y + b.height]);
    });
    for (const [id, [x1, y1, x2, y2]] of [...boxes].reverse()) {
      const e = el(id);
      if (!e) continue;
      const corners = [[x1, y1], [x2, y1], [x2, y2], [x1, y2]];
      const corner = corners.findIndex(([cx, cy]) => Math.hypot(px - cx, py - cy) <= 9);
      if (corner >= 0 || (px >= x1 - 2 && px <= x2 + 2 && py >= y1 - 2 && py <= y2 + 2)) {
        return { e, corner: corner >= 0 ? corner : null, corners, mid: [(x1 + x2) / 2, (y1 + y2) / 2], w: x2 - x1, h: y2 - y1 };
      }
    }
    return null;
  }
  /** Where a straight line's curve handle stands: off its middle by its curve, square to it. */
  function curveAt(e) {
    const dx = e.x2 - e.x, dy = e.y2 - e.y, len = Math.max(Math.hypot(dx, dy), 1e-9);
    const c = e.curve || 0;
    return storedToBox((e.x + e.x2) / 2 - dy / len * c, (e.y + e.y2) / 2 + dx / len * c);
  }
  /** How far a camera's cone reaches: its own, else its lens's (the Mac's `cameraReach`). */
  function camReach(e) {
    if (e.reach > 0) return e.reach;
    const c = ((got && got.cams) || []).find((x) => x.id === e.id) || {};
    const focal = c.focal || (e.lens > 0 ? e.lens : 35);
    return Math.min(Math.max(focal / 10, 1.8), 9);
  }
  function handleOp(d, x, y) {
    if (d.h === "reach") {
      const e = d.e, [ax, ay, arot] = e.at || [e.x, e.y, e.rot], r0 = rad(arot);
      const reach = Math.max((x - ax) * Math.cos(r0) + (y - ay) * Math.sin(r0) - (e.w || 0.4) / 2, 0.3);
      readout = { px: d.px, py: d.py, text: lengthText(reach) };
      return { op: "update", ids: [e.id], set: { reach: r3(reach) } };
    }
    if (d.h === "curve") {
      // How far off its middle the hand is, square to the line; near none, straight.
      const e = d.e, dx = e.x2 - e.x, dy = e.y2 - e.y, len = Math.max(Math.hypot(dx, dy), 1e-9);
      let off = (x - (e.x + e.x2) / 2) * (-dy / len) + (y - (e.y + e.y2) / 2) * (dx / len);
      if (Math.abs(off) * view().k < 6) off = 0;
      return { op: "update", ids: [e.id], set: { curve: Math.round(off * 1000) / 1000 } };
    }
    const hk = /^h(in|out)(\d+)$/.exec(d.h);
    if (hk) {
      const [gx, gy] = d.grab || [0, 0];
      const op = { op: "wall_handle", id: d.e.id, corner: Number(hk[2]), side: hk[1], x: x + gx, y: y + gy };
      if (d.free) op.free = true;
      return op;
    }
    const e = d.kind === "handle" && /^wc/.test(d.h) ? (el(d.e.id) || d.e) : d.e;
    const [ax, ay, arot] = e.at || [e.x, e.y, e.rot];
    if (d.h === "turn") {
      // In front of what faces, the heading is where the hand is; off a
      // frame's side, a quarter turn back; off the top of anything else, a
      // quarter turn on.
      const rot = stepped((Math.atan2(y - ay, x - ax) * 180) / Math.PI + (faces(e) ? 0 : isFrame(e) ? -90 : 90), d.shiftNow, d.free);
      readout = { px: d.px, py: d.py, text: `${Math.round(rot)}°` };
      if (H.beat() > 1 || beatsMode) return { op: "beat", id: e.id, beat: H.beat(), x: ax, y: ay, rot };
      return { op: "update", ids: [e.id], set: { rot, aim: "" } };
    }
    if (d.h.startsWith("stepturn")) {
      const i = Number(d.h.slice(8)), t = (e.seq || [])[i];
      if (!t) return null;
      const rot = stepped((Math.atan2(y - t.y, x - t.x) * 180) / Math.PI + (faces(e) ? 0 : isFrame(e) ? -90 : 90), d.shiftNow, d.free);
      readout = { px: d.px, py: d.py, text: `${Math.round(rot)}°` };
      return { op: "step_set", id: e.id, step: i, rot };
    }
    if (d.h === "tilt") {
      // How far a frame stands: the raised edge, which the knob rides,
      // follows the hand toward the middle (up) or away (down), 5° steps
      // from flat to upright.
      const r = rad(arot);
      const half = (e.tall > 0 ? e.tall : e.h) / 2;
      if (!(half > 0)) return null;
      const moved = (x - d.x) * Math.cos(r) + (y - d.y) * Math.sin(r);
      const edge = half * Math.cos(rad(e.tilt || 0)) - moved;
      const deg = (Math.acos(Math.min(Math.max(edge / half, 0), 1)) * 180) / Math.PI;
      const tilt = Math.min(Math.max(Math.round(deg / 5) * 5, 0), 90);
      readout = { px: d.px, py: d.py, text: `${tilt}°` };
      return { op: "update", ids: [e.id], set: { tilt } };
    }
    if (d.h === "name") {
      const [dx, dy] = [x - d.x, y - d.y];
      // From where the plan drew it: a name stepped aside to stay clear (`data-nx`) starts there.
      return { op: "update", ids: [e.id], set: { label_dx: (e.label_dx || 0) + (d.nx || 0) + dx, label_dy: (e.label_dy || 0) + (d.ny || 0) + dy } };
    }
    if (/^step\d+$/.test(d.h)) {
      const [qx, qy] = snapped(x, y, d.free);
      return { op: "step_set", id: e.id, step: Number(d.h.slice(4)), x: qx, y: qy };
    }
    if (d.h.startsWith("wc")) {
      // **One corner of a wall** dragged on its own: the stretches either
      // side follow, and it lines up square with the other corners; ⇧
      // keeps it square to the corner before it. ⌥: nothing joined there
      // comes along.
      const i = Number(d.h.slice(2));
      const c = wallCorners(e);
      let q = snapped(x + (d.grab ? d.grab[0] : 0), y + (d.grab ? d.grab[1] : 0), d.free && !d.alt, { id: e.id, corner: i });
      if (d.shiftNow && c.length > 1) {
        const prev = i > 0 ? c[i - 1] : (e.closed ? c[c.length - 1] : c[1]);
        q = constrained(prev, q, true, d.free);
        guides = [];
      }
      const prev = i > 0 ? c[i - 1] : (e.closed ? c[c.length - 1] : c[1]);
      readout = { px: d.px, py: d.py, text: lengthText(Math.hypot(q[0] - prev[0], q[1] - prev[1])) };
      const op = { op: "wall_corner", id: e.id, corner: i, x: q[0], y: q[1] };
      if (d.alt) op.free = true;
      return op;
    }
    if (d.h.startsWith("end")) {
      const end = d.h === "end0" ? 0 : 1;
      const fixed = end === 0 ? [e.x2, e.y2] : [e.x, e.y];
      const [qx, qy] = constrained(fixed, snapped(x, y, d.free), d.shiftNow, d.free);
      readout = { px: d.px, py: d.py, text: lengthText(Math.hypot(qx - fixed[0], qy - fixed[1])) };
      return { op: "update", ids: [e.id], set: end === 0 ? { x: qx, y: qy } : { x2: qx, y2: qy } };
    }
    if (d.h.startsWith("corner") && hugSize(e)) {
      // **A lamp's mark sized by a corner** (the Mac's `resizeMark`): square,
      // the opposite corner held, `mark_k` written; the readout says how big.
      const i = Number(d.h.slice(6));
      const [dw, dh] = d.hug || (d.hug = hugSize(e));
      const corners = [[-dw / 2, -dh / 2], [dw / 2, -dh / 2], [dw / 2, dh / 2], [-dw / 2, dh / 2]];
      const opp = corners[(i + 2) % 4], mine = corners[i];
      const [lx, ly] = turnPt(x - ax, y - ay, -arot);
      const r = Math.max(Math.abs(lx - opp[0]) / dw, Math.abs(ly - opp[1]) / dh, 0.01);
      const k0 = Number(e.mark_k) > 0 ? Number(e.mark_k) : 1;
      const k = Math.min(Math.max(k0 * r, 0.4), 10);
      const g = k / k0;
      // The box drawn after: the mark grown, never under 26 points — its far corner where it was.
      const least = 26 / Math.max(view().k, 1e-6);
      const real = Array.isArray(e.drawn) ? e.drawn : [dw, dh];
      const nw = Math.max(real[0] * g, least), nh = Math.max(real[1] * g, least);
      const mx = opp[0] + Math.sign(mine[0] - opp[0]) * nw / 2, my = opp[1] + Math.sign(mine[1] - opp[1]) * nh / 2;
      const [cx, cy] = turnPt(mx, my, arot);
      readout = { px: d.px, py: d.py, text: `${Math.round(k * 100)}%` };
      return { op: "update", ids: [e.id], set: { mark_k: Math.round(k * 1000) / 1000, x: ax + cx, y: ay + cy } };
    }
    if (d.h.startsWith("corner")) {
      const i = Number(d.h.slice(6));
      const hw = e.w / 2, hh = (e.h > 0 ? e.h : e.w) / 2;
      const corners = [[-hw, -hh], [hw, -hh], [hw, hh], [-hw, hh]];
      const opp = corners[(i + 2) % 4];
      // The dragged corner lands on the grid with Snap on; the opposite stays put.
      if (settings().snap && !d.free) { const s = snapStep(); x = Math.round(x / s) * s; y = Math.round(y / s) * s; }
      const [lx, ly] = turnPt(x - ax, y - ay, -arot);
      let w = Math.max(0.05, Math.abs(lx - opp[0])), h = Math.max(0.05, Math.abs(ly - opp[1]));
      if (d.shiftNow && e.w > 0 && e.h > 0) { const r = e.h / e.w; if (w * r > h) h = w * r; else w = h / r; }
      const mx = opp[0] + Math.sign(lx - opp[0]) * w / 2, my = opp[1] + Math.sign(ly - opp[1]) * h / 2;
      const [cx, cy] = turnPt(mx, my, arot);
      readout = { px: d.px, py: d.py, text: `${lengthText(w)} × ${lengthText(h)}` };
      return { op: "update", ids: [e.id], set: { w, h, x: ax + cx, y: ay + cy } };
    }
    return null;
  }

  /** The pick's box turned about its pivot: one piece by its own heading, the rest as one (the Mac's `turnPickOp`). */
  function boxTurnOp(d, x, y) {
    const [px, py] = d.pivot;
    const now = (Math.atan2(y - py, x - px) * 180) / Math.PI;
    const to = stepped(d.base + now - d.from, d.shiftNow, d.free);
    let deg = (to - d.base) % 360;
    if (deg > 180) deg -= 360; else if (deg < -180) deg += 360;
    d.deg = deg;
    readout = { px: d.px, py: d.py, text: `${Math.round(to)}°` };
    if (Math.abs(deg) < 1e-9) return null;
    return { op: "rotate", ids: d.ids, deg, px, py };
  }

  /** A pick's heading: a wall's way is its picked stretch's, else its first's; a line's its own. */
  function heading(e) {
    if (!e) return 0;
    if (cornered(e) || LINE_KINDS.has(e.kind)) {
      const c = cornered(e) ? wallCorners(e) : [[e.x, e.y], [e.x2, e.y2]];
      const s = cornered(e) ? Math.min(pickedStretch ?? 0, Math.max(c.length - 2, 0)) : 0;
      const [p, q] = [c[s], c[(s + 1) % c.length]];
      const a = (Math.atan2(q[1] - p[1], q[0] - p[0]) * 180) / Math.PI;
      return Math.round(((a % 360) + 360) % 360 * 100) / 100 % 360;
    }
    return (e.at || [e.x, e.y, e.rot])[2] || 0;
  }

  /** The stretch of a wall nearest a point. */
  function nearestStretch(e, [x, y]) {
    const c = wallCorners(e);
    const n = c.length, count = e.closed && n > 2 ? n : n - 1;
    let best = 0, gap = Infinity;
    for (let i = 0; i < count; i++) {
      const [a, b] = [c[i], c[(i + 1) % n]];
      const dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy || 1e-12;
      const t = Math.max(0, Math.min(1, ((x - a[0]) * dx + (y - a[1]) * dy) / l2));
      const g = Math.hypot(x - a[0] - dx * t, y - a[1] - dy * t);
      if (g < gap) { gap = g; best = i; }
    }
    return best;
  }

  /** A label and a lamp, if a connector drawn between these two points joins one to the other. */
  function tiePair(ax, ay, px, py) {
    const a = pinTarget(ax, ay, []), b = pinTarget(px, py, []);
    const ends = [a && el(a), b && b !== a && el(b)];
    const label = ends.find((x) => x && x.kind === "text");
    const lamp = ends.find((x) => x && canShare(x));
    return label && lamp ? [label.id, lamp.id] : null;
  }

  /** The piece an arrow's end lands on: the top thing under the point that is not a line, a drawing or a picture. */
  function pinTarget(px, py, skip) {
    const [sx, sy] = toShown(px, py);
    const skipped = [...hiddenIds(), ...skip];
    for (let n = 0; n < 6; n++) {
      const said = where("hit", sx, sy, { tol: 6 / view().k, beat: H.beat(), skip: skipped, ...pageAsk() });
      const id = said && said.id;
      const e = id && el(id);
      if (!e) return null;
      if (LINE_KINDS.has(e.kind) || ["cable", "stroke", "image"].includes(e.kind)) { skipped.push(id); continue; }
      return id;
    }
    return null;
  }

  /**
   * **What a ruler's marker holds on to**: a person, a camera or a lamp, whose
   * middle is the point; never a table or any other box, whose edge is what
   * is measured (his report, 2026-10-06). With Snap off, or ⌥/⌘ held, nothing.
   */
  function rulerTarget(px, py, skip, free) {
    if (free || !settings().snap) return null;
    const id = pinTarget(px, py, skip);
    const e = id && el(id);
    return e && ["cast", "camera", "light"].includes(e.kind) ? id : null;
  }

  /** A lamp lands facing up the screen, as its tile shows; anything else as drawn. */
  const restingRot = () => (tool === "light" ? 270 : (tool === "grip" || tool === "set") && armed && armed.light ? 270 : 0);

  // ---- walls, corner by corner ---------------------------------------------

  /** Where the next corner of the wall being drawn lands — lined up with its own corners as well as every other wall's. */
  function drawSnap(x, y, free) {
    const e = wallDraw && wallDraw.id ? el(wallDraw.id) : null;
    return snapped(x, y, free, e ? { id: e.id, corner: wallCorners(e).length } : null);
  }

  /** A click while a wall is being drawn: the next corner, or — on the first — the room closed. */
  function wallClick(x, y, base) {
    const pts = wallDraw.pts;
    const q = drawSnap(x, y, base.alt);
    if (pts.length >= 3 && Math.hypot(pts[0][0] - q[0], pts[0][1] - q[1]) * view().k < 8) {
      if (wallDraw.id) edit({ op: "update", ids: [wallDraw.id], set: { closed: true } }, { label: "Close Wall" });
      return finishWall();
    }
    const last = pts[pts.length - 1];
    const p = constrained(last, q, base.shift, base.alt);
    if (Math.hypot(p[0] - last[0], p[1] - last[1]) <= 0.05) return;
    if (!wallDraw.id) {
      const made = edit({ op: "add", els: [{ kind: "wall", x: last[0], y: last[1], x2: p[0], y2: p[1] }] }, { label: "Add Wall", select: true });
      wallDraw.id = made[0] || null;
    } else {
      edit({ op: "wall_extend", id: wallDraw.id, end: "end", x: p[0], y: p[1] }, { label: "Add Corner" });
      picks = [wallDraw.id];
    }
    pts.push(p);
    preview = null;
    paint();
  }

  /** Done drawing: back to the arrow, to pick up what was drawn. */
  function finishWall() {
    wallDraw = null; wallAt = null; guides = []; preview = null; readout = null;
    showReadout();
    setTool("select");
  }

  /** A press on one of a picked wall's handles: a corner, a + mid-stretch, a + past an end. */
  function wallHandleDown(e, h, x, y, base) {
    const i = Number(h.replace(/^\D+/, ""));
    if (h.startsWith("wc")) {
      const c = wallCorners(e)[i];
      if (!c) return;
      pickedCorner = i; pickedStretch = null; sideKey = "";
      drag = { ...base, kind: "handle", h, e, x, y, grab: [c[0] - x, c[1] - y] };
      paint();
      return;
    }
    if (h.startsWith("add")) {
      // A corner added at the stretch's middle, picked, and dragged from
      // there if the hand moves on — one step to take back.
      edit({ op: "wall_insert", id: e.id, stretch: i }, { label: "Add Corner" });
      const now = el(e.id);
      if (!now || i + 1 >= wallCorners(now).length) return;
      const c = wallCorners(now)[i + 1];
      pickedCorner = i + 1; pickedStretch = null; sideKey = "";
      drag = { ...base, kind: "handle", h: `wc${i + 1}`, e: now, x, y, grab: [c[0] - x, c[1] - y], made: true };
      paint();
      return;
    }
    // A + past an end: grown on the way it runs, about eighty pixels' worth on the grid.
    const c = wallCorners(e);
    const [a, b] = i === 0 ? [c[0], c[1]] : [c[c.length - 1], c[c.length - 2]];
    const len = Math.max(Math.hypot(a[0] - b[0], a[1] - b[1]), 1e-6);
    const step = snapStep();
    const want = Math.max(Math.round((80 / view().k) / step) * step, step);
    const to = [a[0] + (a[0] - b[0]) / len * want, a[1] + (a[1] - b[1]) / len * want];
    edit({ op: "wall_extend", id: e.id, end: i === 0 ? "start" : "end", x: to[0], y: to[1] }, { label: "Add Corner" });
    const now = el(e.id);
    if (!now) return;
    const at = i === 0 ? 0 : wallCorners(now).length - 1;
    pickedCorner = at; pickedStretch = null; sideKey = "";
    drag = { ...base, kind: "handle", h: `wc${at}`, e: now, x, y, grab: [to[0] - x, to[1] - y], made: true };
    paint();
  }

  /** The pointer over the plan with nothing held: the next corner of a wall being drawn, or what is under it, outlined. */
  function hoverMove(px, py, ev) {
    if (measuring && !editor()) return measureHover(px, py, ev);
    if (!view() || !editor()) return;
    if (wallDraw && tool === "wall") {
      const [x, y] = toStored(px, py);
      const last = wallDraw.pts[wallDraw.pts.length - 1];
      const q = constrained(last, drawSnap(x, y, ev.altKey), ev.shiftKey, ev.altKey);
      if (ev.shiftKey) guides = [];
      wallAt = q;
      const far = Math.hypot(q[0] - last[0], q[1] - last[1]) > 0.05;
      preview = !far ? null : wallDraw.id
        ? { op: "wall_extend", id: wallDraw.id, end: "end", x: q[0], y: q[1] }
        : { op: "add", els: [{ kind: "wall", x: last[0], y: last[1], x2: q[0], y2: q[1] }] };
      readout = far ? { px, py, text: lengthText(Math.hypot(q[0] - last[0], q[1] - last[1])) } : null;
      showReadout();
      frame();
      return;
    }
    if ((tool === "pen" && penNodes.length) || (tool === "cable" && chainPts.length)) { hover = null; frame(); return; }
    if (tool !== "select") { if (hover) { hover = null; frame(); } return; }
    const svgHit = document.elementFromPoint(ev.clientX, ev.clientY);
    const now = svgHit && svgHit.closest && svgHit.closest("[data-h]") ? hover : hitAt(px, py, svgHit);
    if (now !== hover) { hover = now; frame(); }
  }

  // ---- Measure, for anybody ------------------------------------------------------
  //
  // **His ask, 2026-10-11:** *"a measure tool should always be available for
  // anyone in diagram mode."* The Ruler tool lays a ruler on the plan, which
  // is an edit — an editor's. This is the looking person's: Measure (or M),
  // press one point and then another, and the distance is written on the
  // line, in the plan's own units. **Nothing is kept and nothing is sent**, so
  // a viewer and a link holder have it whatever the share link allows; it goes
  // when the scene changes or Measure is pressed again. A press catches what
  // the engine's own snap would catch (a wall's end, a piece's centre); ⌥
  // presses exactly where the finger is, ⇧ keeps the line square.
  function setMeasuring(on) {
    if (on === measuring || (on && editor())) return;
    measuring = on;
    mpts = []; mhover = null;
    if (on) { picks = []; cam = null; sideKey = ""; toast("Press two points to measure · Esc to finish"); }
    paint();
    const b = box();
    if (b) b.vp.focus({ preventScroll: true, focusVisible: false });
    const btn = root.querySelector("[data-pmeasure]");
    if (btn) btn.classList.toggle("on", measuring);
  }
  /** Where a press lands for measuring: the engine's snap to the plan's own points, never to the grid. */
  function measureAt(px, py, shift, alt) {
    const [x, y] = toStored(px, py);
    if (alt) return [x, y];
    const [sx, sy] = shownOf(x, y);
    const s = where("snap", sx, sy, { reach: 10 / view().k, step: 0, own: null });
    let q = s && s.sx !== undefined ? [s.sx, s.sy] : [x, y];
    guides = [];
    if (shift && mpts.length === 1) q = constrained(mpts[0], q, true, false);
    return q;
  }
  function measureTap(px, py, shift, alt) {
    if (!view()) return;
    const q = measureAt(px, py, shift, alt);
    mpts = mpts.length === 1 ? [mpts[0], q] : [q];
    mhover = null;
    const svg = root.querySelector(".planpic > svg");
    if (svg) measureLayer(svg);
  }
  function measureHover(px, py, ev) {
    if (!view() || mpts.length !== 1) return;
    mhover = measureAt(px, py, ev.shiftKey, ev.altKey);
    const svg = root.querySelector(".planpic > svg");
    if (svg) measureLayer(svg);
  }
  /** The line, its two dots and the distance, drawn over the plan in the box's own pixels. */
  function measureLayer(svg) {
    svg.querySelector(".planmeasure")?.remove();
    if (!measuring || editor() || !mpts.length || !view()) return;
    const a = mpts[0], b = mpts[1] || mhover;
    const g = document.createElementNS(NS, "g");
    g.setAttribute("class", "planmeasure");
    g.setAttribute("pointer-events", "none");
    const add = (tag, attrs) => { const n = document.createElementNS(NS, tag); for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v); g.append(n); return n; };
    const [ax, ay] = storedToBox(a[0], a[1]);
    if (b) {
      const [bx, by] = storedToBox(b[0], b[1]);
      add("line", { class: "pmline", x1: ax, y1: ay, x2: bx, y2: by });
      const dx = Math.abs(b[0] - a[0]), dy = Math.abs(b[1] - a[1]);
      const text = add("text", { class: "pmtext", x: (ax + bx) / 2, y: (ay + by) / 2 - 10, "text-anchor": "middle" });
      text.textContent = lengthText(Math.hypot(dx, dy));
      // Off the square, the two legs as well: how far across and how far down.
      if (dx > 0.05 && dy > 0.05) {
        const legs = add("text", { class: "pmtext pmsub", x: (ax + bx) / 2, y: (ay + by) / 2 + 8, "text-anchor": "middle" });
        legs.textContent = `${lengthText(dx)} across · ${lengthText(dy)} down`;
      }
      add("circle", { class: "pmdot", cx: bx, cy: by, r: 4.5 });
    }
    add("circle", { class: "pmdot", cx: ax, cy: ay, r: 4.5 });
    svg.append(g);
  }

  /** The numbers by the pointer mid-drag — size, angle, how far — in the plan's units. */
  function showReadout() {
    const b = box();
    if (!b) return;
    let r = b.vp.querySelector(".planread");
    if (!readout) { if (r) r.remove(); return; }
    if (!r) { r = document.createElement("div"); r.className = "planread"; b.vp.append(r); }
    r.textContent = readout.text;
    r.style.left = `${Math.min(readout.px + 16, b.w - 120)}px`;
    r.style.top = `${Math.max(readout.py - 30, 4)}px`;
  }

  function drawOp(d) {
    const [a, b] = [d.a, d.b];
    if (tool === "wall" && d.room) {
      const [x1, y1, x2, y2] = [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[0], b[0]), Math.max(a[1], b[1])];
      if (x2 - x1 < 0.3 || y2 - y1 < 0.3) return null;
      // A room is one closed wall.
      return { op: "add", els: [{ kind: "wall", points: [[x1, y1], [x2, y1], [x2, y2], [x1, y2]], closed: true }] };
    }
    if (Math.hypot(b[0] - a[0], b[1] - a[1]) < 0.05) return null;
    if (tool === "wall") return { op: "add", els: [{ kind: "wall", x: a[0], y: a[1], x2: b[0], y2: b[1] }] };
    if (tool === "shape") {
      return { op: "add", els: [{ kind: "shape", sym: shapeKind, x: (a[0] + b[0]) / 2, y: (a[1] + b[1]) / 2, w: Math.max(Math.abs(b[0] - a[0]), 0.2), h: Math.max(Math.abs(b[1] - a[1]), 0.2) }] };
    }
    // A connector is an arrow with no head and a lighter line (the Mac's).
    const e = { kind: tool === "connector" ? "arrow" : tool, x: a[0], y: a[1], x2: b[0], y2: b[1] };
    if (tool === "arrow") { e.head = "end"; Object.assign(e, inSetNow()); }
    if (tool === "connector") { e.head = "none"; e.weight = 0.8; }
    return { op: "add", els: [e] };
  }

  /** The Draw tool's path laid down as it is (the Mac's `finishPath` and `addPath`): closed, one shape; an open object only an outline. */
  function finishPen(closed) {
    const nodes = penNodes.slice();
    penNodes = [];
    // The same point pressed twice is one point.
    if (nodes.length >= 2) {
      const a = nodes[nodes.length - 1].p, b = nodes[nodes.length - 2].p;
      if (Math.hypot(a[0] - b[0], a[1] - b[1]) * view().k < 3) nodes.pop();
    }
    if (nodes.length < 2) { setTool("select"); return; }
    const r = (n) => Math.round(n * 1000) / 1000;
    const shut = closed && nodes.length >= 3;
    const e = {
      kind: penAs === "wall" ? "wall" : "stroke",
      points: nodes.map((n) => [r(n.p[0]), r(n.p[1])]),
      handles: nodes.map((n) => [r(n.hin[0]), r(n.hin[1]), r(n.hout[0]), r(n.hout[1])]),
    };
    if (shut) e.closed = true;
    const filled = shut && (penAs === "object" || penFill);
    e.fill = filled && penAs !== "wall";
    // A colour picked for the pen is the fill's colour too; none is the plan's tint.
    if (filled) e.fill_color = penColour || (penAs === "wall" ? "auto" : "");
    if (penAs !== "wall" && penColour) e.color = penColour;
    edit({ op: "add", els: [e] }, { label: penAs === "wall" ? "Add Wall" : "Add Drawing", select: true });
    setTool("select");
  }
  /** A cable laid point by point, put down in one go. */
  function finishChain() {
    const pts = chainPts.slice();
    chainPts = [];
    if (pts.length >= 2) edit({ op: "add", els: [{ kind: "cable", points: pts.map(([x, y]) => [Math.round(x * 1000) / 1000, Math.round(y * 1000) / 1000]) }] }, { label: "Add Cable", select: true });
    setTool("select");
  }

  function inkOp(d) {
    const pts = simplify(d.pts, 1.5 / view().k);
    if (pts.length < 2) return null;
    return { op: "add", els: [{ kind: tool === "pen" ? "stroke" : "cable", points: pts.map(([x, y]) => [Math.round(x * 1000) / 1000, Math.round(y * 1000) / 1000]) }] };
  }
  function simplify(pts, tol) {
    if (pts.length < 3) return pts;
    const out = [pts[0]];
    for (const p of pts.slice(1)) { const q = out[out.length - 1]; if (Math.hypot(p[0] - q[0], p[1] - q[1]) >= tol) out.push(p); }
    const last = pts[pts.length - 1];
    if (out[out.length - 1] !== last) out.push(last);
    return out;
  }

  function turnTo(e, deg, burst = "") {
    const rot = ((Number(deg) % 360) + 360) % 360;
    const [ax, ay] = e.at || [e.x, e.y];
    if (H.beat() > 1) return edit({ op: "beat", id: e.id, beat: H.beat(), x: ax, y: ay, rot }, { label: "Turn", burst });
    edit({ op: "update", ids: [e.id], set: { rot, aim: "" } }, { label: "Turn", burst });
  }

  /** The pick turned by some degrees: one piece by its own heading, a wall, a line or several about the pick's middle. */
  function turnPickBy(deg) {
    const els = picks.map(el).filter((e) => e && !e.locked);
    if (!els.length) return;
    const one = els.length === 1 ? els[0] : null;
    if (one && !LINE_KINDS.has(one.kind) && !["cable", "stroke"].includes(one.kind)) {
      const [, , ar] = one.at || [one.x, one.y, one.rot];
      return turnTo(one, ar + deg, "turn");
    }
    const [px, py] = pivot(els);
    edit({ op: "rotate", ids: els.map((e) => e.id), deg, px, py }, { label: "Turn", burst: "turn" });
  }

  // ------------------------------------------------------------ keys

  function keys(ev, vp) {
    if (/INPUT|TEXTAREA|SELECT/.test((ev.target && ev.target.tagName) || "")) return;
    if (photo && editor() && photoKeys(ev)) return;
    const cmd = ev.metaKey || ev.ctrlKey;
    const w = vp.clientWidth, h = vp.clientHeight;
    const k = ev.key;
    const ed = editor();
    if (!ed && !cmd && !ev.altKey && (k === "m" || k === "M")) { ev.preventDefault(); setMeasuring(!measuring); return; }
    if (!ed && measuring && k === "Escape" && !drag) { setMeasuring(false); return; }
    if (cmd && (k === "=" || k === "+")) { zoomAt(1.35, w / 2, h / 2); commit(); }
    else if (cmd && k === "-") { zoomAt(1 / 1.35, w / 2, h / 2); commit(); }
    else if (cmd && k === "0") { const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" }); paint(); }
    else if (!cmd && (k === "+" || k === "=")) { zoomAt(1.35, w / 2, h / 2); commit(); }
    else if (!cmd && (k === "-" || k === "_")) { zoomAt(1 / 1.35, w / 2, h / 2); commit(); }
    else if (!cmd && k === "0") { const v = view(); if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" }); paint(); }
    else if (k === "Escape" && calibrating && !drag) { calibrating = null; paint(); }
    else if (k === "Escape" && drag && drag.kind !== "pan" && drag.kind !== "pinch") {
      // Esc mid-drag: nothing kept, everything back where it was (the Mac's).
      drag = null; preview = null; guides = []; readout = null; showReadout();
      const box2 = vp.querySelector(".planmarq");
      if (box2) box2.remove();
      paint();
    }
    else if (ed && tool === "pen" && penNodes.length && (k === "Enter" || k === "Escape")) { ev.preventDefault(); finishPen(false); }
    else if (ed && tool === "pen" && penNodes.length && (k === "Backspace" || k === "Delete")) { ev.preventDefault(); penNodes.pop(); float(); frame(); }
    else if (ed && tool === "cable" && chainPts.length && (k === "Enter" || k === "Escape")) { ev.preventDefault(); finishChain(); }
    else if (ed && tool === "cable" && chainPts.length && (k === "Backspace" || k === "Delete")) { ev.preventDefault(); chainPts.pop(); frame(); }
    else if (k === "Escape") {
      if (menu) closeMenu();
      else if (swap) closeSwap();
      else if (wallDraw) finishWall();
      else if (castMenu || libOpen || picMenu) { castMenu = null; libOpen = false; picMenu = false; float(); }
      else if (pickedCorner !== null || pickedStretch !== null) { pickedCorner = null; pickedStretch = null; sideKey = ""; paint(); }
      else if (tool !== "select") setTool("select");
      else { picks = []; cam = null; sideKey = ""; paint(); }
    }
    else if (k === "Enter" && wallDraw) finishWall();
    else if (ed && k === "Enter" && !cmd && !ev.shiftKey && !ev.altKey && picks.length === 1 && (el(picks[0]) || {}).kind === "camera" && el(picks[0]).shot) {
      // Return on a camera with a shot: the shot, in Details (the Mac's).
      tab = "details"; sideKey = ""; paint();
    }
    else if (ed && k === "Enter" && !cmd && !ev.shiftKey && !ev.altKey && picks.length === 1) {
      // Return on one picked piece: its name opens for typing on the plan.
      const e = el(picks[0]);
      if (e && renamable(e)) startRename(e);
      else return;
    }
    else if (ed && (k === "Delete" || k === "Backspace") && stepPicked() && !stepPicked().s.home) {
      // One step alone: the step goes, the piece stays.
      const sp = stepPicked();
      edit({ op: "step_remove", id: sp.e.id, step: sp.i }, { label: `Remove ${sp.s.letter}` });
      pickedStep = null; sideKey = ""; paint();
    }
    else if (ed && (k === "Delete" || k === "Backspace") && pickedCorner !== null && picks.length === 1 && cornered(el(picks[0]))) {
      edit({ op: "wall_remove_corner", id: picks[0], corner: pickedCorner }, { label: "Delete Corner" });
      pickedCorner = null; pickedStretch = null; sideKey = ""; paint();
    }
    else if (ed && ev.altKey && !cmd && (k === "ArrowLeft" || k === "ArrowRight") && picks.length) {
      // ⌥← ⌥→ turn the pick: 5° with Snap on, 1° off, 15° with ⇧ — a run of presses one step back.
      const by = (ev.shiftKey ? 15 : settings().snap ? 5 : 1) * (k === "ArrowRight" ? 1 : -1);
      turnPickBy(by);
    }
    else if (ed && ev.altKey && (k === "ArrowUp" || k === "ArrowDown")) { /* ⌥↑↓ do nothing, as on the Mac */ }
    else if (ed && cmd && k.toLowerCase() === "z") { if (ev.shiftKey) redo(); else undo(); }
    else if (ed && cmd && k.toLowerCase() === "y") redo();
    else if (ed && cmd && k.toLowerCase() === "a") { picks = (got.els || []).filter((e) => !e.hidden && !e.locked && !(e.show && off.has(e.show)) && layerOf(e) === layer).map((e) => e.id); sideKey = ""; paint(); }
    else if (ed && cmd && k.toLowerCase() === "d" && picks.length) duplicate(picks.slice());
    else if (ed && cmd && !ev.shiftKey && k.toLowerCase() === "l" && picks.length) lockPicks();
    else if (ed && cmd && ev.shiftKey && k.toLowerCase() === "h" && picks.length) hidePicks();
    else if (ed && cmd && k.toLowerCase() === "g" && picks.length) edit({ op: ev.shiftKey ? "ungroup" : "group", ids: picks.slice() }, { label: ev.shiftKey ? "Ungroup" : "Group" });
    else if (ed && cmd && (k.toLowerCase() === "c" || k.toLowerCase() === "x") && picks.length) copyPicks(k.toLowerCase() === "x");
    else if (ed && cmd && k.toLowerCase() === "v") paste();
    else if (ed && (k === "Delete" || k === "Backspace") && picks.length) remove(picks.slice());
    else if (ed && k.startsWith("Arrow") && picks.length) {
      // A small step, or with ⇧ one step of the grid; a run of presses is one step back.
      const step = ev.shiftKey ? snapStep() : nudgeStep();
      const [bx, by] = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[k];
      const [dx, dy] = storedOf(bx * step, by * step);
      const ids = picks.filter((id) => { const e = el(id); return e && !e.locked; });
      if (H.beat() > 1 || beatsMode) edit({ op: "batch", ops: ids.map((id) => { const e = el(id); const [ax, ay, ar] = e.at || [e.x, e.y, e.rot]; return { op: "beat", id, beat: H.beat(), x: ax + dx, y: ay + dy, rot: ar }; }) }, { label: "Nudge", burst: "nudge" });
      else edit({ op: "move", ids, dx, dy }, { label: "Nudge", burst: "nudge" });
      paint();
    }
    // **Arrange** (the Mac's): ⌘] forward, ⌘[ backward, with ⌥ to the front or back.
    else if (ed && cmd && (ev.code === "BracketRight" || ev.code === "BracketLeft") && picks.length) {
      const up = ev.code === "BracketRight";
      edit({ op: "order", ids: picks.slice(), to: ev.altKey ? (up ? "front" : "back") : (up ? "forward" : "backward") }, { label: "Arrange" });
    }
    // ⌘R a quarter turn right, ⇧⌘R left, about a point on the grid.
    else if (ed && cmd && k.toLowerCase() === "r" && picks.length) turnPickBy(ev.shiftKey ? -90 : 90);
    // ⇧H, ⇧V flip what is picked.
    else if (ed && !cmd && ev.shiftKey && !ev.altKey && (k === "H" || k === "V") && picks.length) edit({ op: "flip", ids: picks.slice(), axis: k === "H" ? "x" : "y" }, { label: "Flip" });
    // ⌃⌘1 Layers, ⌃⌘2 Details.
    else if (ed && ev.ctrlKey && ev.metaKey && (ev.code === "Digit1" || ev.code === "Digit2")) { tab = ev.code === "Digit1" ? "layers" : "details"; sideKey = ""; paint(); }
    else if (ed && (k === "[" || k === "]") && picks.length) turnPickBy(k === "]" ? 15 : -15);
    else if (!ed && (k === "ArrowLeft" || k === "ArrowRight")) {
      const last = got ? Math.max(1, got.lastBeat) : 1;
      const to = H.beat() + (k === "ArrowRight" ? 1 : -1);
      if (to < 1 || to > last || play) return;
      H.setBeat(to); paint();
    }
    else if (k === " " && !ed) playToggle();
    // **One key, one thing at the pointer** (Scenario's, the Mac's
    // `oneKeyAdd`): C a camera, T words, F a frame — and, because A, W and P
    // already pick Arrow, Wall and Cast, ⇧A a person, ⇧W an arrow, ⇧P Pictures.
    else if (ed && !cmd && !ev.altKey && ["c", "t", "f"].includes(k) || (ed && !cmd && !ev.altKey && ["A", "W", "P"].includes(k))) {
      const [x, y] = pointer ? snapped(pointer[0], pointer[1], false) : toStored(w / 2, h / 2);
      if (k === "P") { setTool("picture"); return ev.preventDefault(); }
      if (k === "W") {
        const [hx, hy] = turnPt(0.6, 0, -turn());
        edit({ op: "add", els: [{ kind: "arrow", x: x - hx, y: y - hy, x2: x + hx, y2: y + hy, head: "end", ...inSetNow() }] }, { label: "Add Arrow", select: true });
        return ev.preventDefault();
      }
      const was = tool;
      tool = { c: "camera", t: "text", f: "frame", A: "cast" }[k];
      armedShot = "new";
      place(x, y, 0);
      if (tool === "cast") return ev.preventDefault();
      if (tool !== "select") tool = was;
    }
    else if (ed && !cmd && !ev.altKey && k.length === 1 && KEY_ALIAS[k.toLowerCase()]) setTool(KEY_ALIAS[k.toLowerCase()]);
    else if (ed && !cmd && !ev.altKey && TOOLS.some(([, , key]) => key === k.toLowerCase()) && k.length === 1) setTool(TOOLS.find(([, , key]) => key === k.toLowerCase())[0]);
    else if (cmd && k.toLowerCase() === "f") present();
    else if (ed && !cmd && /^[1-9]$/.test(k)) { const [x, y] = pointer || toStored(w / 2, h / 2); putFavorite(Number(k) - 1, x, y); }
    else return;
    ev.preventDefault();
  }

  async function paste() {
    let pieces = clip;
    try {
      const text = await navigator.clipboard.readText();
      const said = JSON.parse(text);
      if (said && Array.isArray(said.shotlisterPlan)) pieces = said.shotlisterPlan;
    } catch { /* the page's own copy */ }
    if (!pieces || !pieces.length) return;
    const step = settings().snap ? snapStep() : (settings().step || 0.3048);
    // **Paste lands at the pointer** (the Mac's): the copies' middle where
    // the pointer is, on the grid; pasted again there, each steps on.
    let dx = step, dy = step;
    const b = extentOf(pieces.map((e) => ({ ...e, at: null })));
    const vb = box();
    const at = pointer || (vb ? toStored(vb.w / 2, vb.h / 2) : null);
    if (at && b) {
      const again = lastPaste && Math.hypot(lastPaste[0] - at[0], lastPaste[1] - at[1]) < 1e-6;
      pasteRun = again ? pasteRun + 1 : 0;
      lastPaste = at.slice();
      let [mx, my] = [at[0] + pasteRun * step, at[1] + pasteRun * step];
      if (settings().snap) { mx = Math.round(mx / step) * step; my = Math.round(my / step) * step; }
      dx = mx - (b[0] + b[2]) / 2; dy = my - (b[1] + b[3]) / 2;
    }
    const els = pieces.map((e) => ({ ...e, x: (e.x || 0) + dx, y: (e.y || 0) + dy, x2: e.x2 !== undefined ? e.x2 + dx : undefined, y2: e.y2 !== undefined ? e.y2 + dy : undefined, points: (e.points || []).map(([px, py]) => [px + dx, py + dy]), steps: (e.steps || []).map((t) => ({ ...t, x: t.x + dx, y: t.y + dy })), seq: undefined, move: undefined, path: undefined, group: "" }));
    const made = edit({ op: "add", els }, { label: "Paste", select: true });
    if (made.length) { picks = made; paint(); }
  }
  let lastPaste = null, pasteRun = 0;

  // ------------------------------------------------------------ looking and editing

  /**
   * **Edit and Done.** Going in, nothing changes but the tools coming out:
   * the pick stays picked, now with its bar and Details. Coming out, every
   * half-made thing is put away — a wall being drawn, an open library, a
   * menu, Beats, the pick — and what is still on its way to the film keeps
   * going.
   */
  function setEditing(on) {
    if (on === editing || (on && !canEdit())) return;
    if (on && measuring) { measuring = false; mpts = []; mhover = null; }
    if (!on) {
      endTyping(true);
      if (photo) endPhoto(false);
      roomOpen = false;
      if (wallDraw) { wallDraw = null; wallAt = null; guides = []; preview = null; readout = null; showReadout(); }
      tool = "select"; armed = null; libOpen = false; favOpen = false; castMenu = null; picMenu = false;
      copyPanel = null; emptyOpen = null; beatsMode = false; many = false;
      pickedCorner = null; pickedStretch = null; pickedStep = null; editingText = null; hover = null;
      renaming = null;
      closeSwap(false);
      closeMenu();
      if (H.beat() > Math.max(1, got ? got.lastBeat : 1)) H.setBeat(1);
      // Done starts the view clean: what was picked to edit is let go.
      picks = []; cam = null; legendPick = null;
      tab = "shots";
    }
    editing = on;
    sideKey = "";
    H.draw();
  }

  /** Export: the plan on paper, or as a picture to send. */
  function exportMenu(anchor) {
    openMenu(anchor, [
      { label: "Print…", pick: () => { closeMenu(); printPlan(); } },
      { label: "Save Picture", pick: () => { closeMenu(); savePicture(); } },
      { rule: true },
      { label: "Copy Gear List", pick: () => { closeMenu(); copyGear(); } },
    ]);
  }

  // ------------------------------------------------------------ present, and a picture to keep

  let beforePresent = null;       // the view as it was, put back when Present ends (the Mac's)
  function present() {
    presenting = !presenting;
    // To show somebody: nothing picked, the whole plan, nothing over it.
    if (presenting) {
      picks = []; cam = null; sideKey = ""; closeMenu(); closeView();
      const v = view();
      beforePresent = v ? { id: chosen(), v: { ...v } } : null;
      if (v) views.set(chosen(), { ...v, fit: true, fitKey: "" });
    } else if (beforePresent && beforePresent.id === chosen()) {
      views.set(beforePresent.id, beforePresent.v);
      beforePresent = null;
    }
    const well = root.querySelector(".planwell");
    if (presenting && well && well.requestFullscreen) well.requestFullscreen().catch(() => {});
    if (!presenting && document.fullscreenElement) document.exitFullscreen().catch(() => {});
    H.draw();
  }

  /**
   * **The plan on paper is the sheet** (Back to Paper, Batch 2, his call C):
   * the engine's one page — title, north, the plan, its notes, legend and
   * shots key — exactly as the Mac's Export and Claude's paper picture
   * draw it, on the paper and the way round the plan says. A page to
   * print, keep as a PDF, or hand round on set.
   */
  /** What Print prints: every drawn diagram of the scene open, else the one open. */
  function printIds() {
    const s = sceneOf(chosen());
    const all = s && Array.isArray(s.diagrams) && s.diagrams.length > 1 ? s.diagrams.filter((d) => d.count > 0).map((d) => d.id) : [];
    return all.length ? all : [String(chosen())];
  }
  async function printPlan() {
    // **Every diagram of the scene** (the Mac's Export, 2026-10-17), each on
    // its own sheet; a scene with one prints exactly as before.
    const ids = printIds();
    const sheets = [];
    for (const id of ids) { const one = await sheetSvg(0, id); if (one) sheets.push(one); }
    if (!sheets.length) return;
    const got2 = sheets[0];
    const w = window.open("", "_blank");
    if (!w) return toast("The browser would not open a page to print", true);
    const title = `${titleOf(chosen())} · Diagram`;
    const pw = got2.sheet.w, ph = got2.sheet.h;
    const body = sheets.map((x) => `<svg-page style="display:block;width:${x.sheet.w}pt;height:${x.sheet.h}pt;break-after:page;page-break-after:always">${x.svg.replace("<svg ", `<svg style="display:block;width:${x.sheet.w}pt;height:${x.sheet.h}pt" `)}</svg-page>`).join("");
    w.document.write(`<!doctype html><meta charset="utf-8"><title>${esc(title)}</title><style>@page{size:${pw}pt ${ph}pt;margin:0}html,body{margin:0;padding:0;background:#fff}svg-page:last-child{break-after:auto;page-break-after:auto}</style>${body}`);
    w.document.close();
    w.addEventListener("load", () => setTimeout(() => w.print(), 200));
    setTimeout(() => { try { w.print(); } catch { /* the page prints itself */ } }, 900);
  }

  /** The day a sheet is printed, as the Mac writes a date: "Oct 4, 2026". */
  const today = () => new Date().toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });

  /** The sheet as a picture, `width` pixels across (nought: a point a pixel), with the pack's pictures carried inside. */
  async function sheetSvg(width, id = null) {
    const said = json(call("plan_sheet", JSON.stringify({ scene: String(id || chosen()), svg: true, width, beat: H.beat(), printed: today() })));
    if (!said || !said.svg) return null;
    let svg = said.svg;
    const hrefs = [...new Set([...svg.matchAll(/href="((?:fso|media)\/[^"]+)"/g)].map((m) => m[1]))];
    for (const h of hrefs) {
      try {
        const blob = await (await fetch(h)).blob();
        const data = await new Promise((ok) => { const r = new FileReader(); r.onload = () => ok(r.result); r.readAsDataURL(blob); });
        svg = svg.split(`href="${h}"`).join(`href="${data}"`);
      } catch { /* a missing picture is a blank, not a failure */ }
    }
    return { svg, sheet: said.sheet };
  }

  /** The sheet as a picture to keep — the page that prints, at twice its size. */
  async function savePicture() {
    const s = sceneOf(chosen());
    const sh = sheetOf();
    const width = Math.round(((sh && sh.w) || 792) * 2);
    const paper = await sheetSvg(width);
    if (!paper) return;
    const img = new Image();
    const inlined = paper.svg.replace("<svg ", `<svg style="font-family:-apple-system,Helvetica,Arial,sans-serif" `);
    img.src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(inlined)}`;
    await new Promise((ok) => { img.onload = ok; img.onerror = ok; });
    const c = document.createElement("canvas");
    c.width = img.width || width; c.height = img.height || Math.round(width * 0.77);
    const ctx = c.getContext("2d");
    ctx.drawImage(img, 0, 0);
    c.toBlob((blob) => {
      if (!blob) return;
      const a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = `${s ? `${s.number} ` : ""}Diagram.png`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 2000);
    }, "image/png");
  }

  // ------------------------------------------------------------ draw on photo
  //
  // **Drawing on a picture on the plan** (the Mac's Draw on Photo, his ask of
  // 2026-10-15, refined 2026-10-17 from the approved mockup
  // claude.ai/artifact/CnWRuArKE5EkCFQ4s96g69; on the portal 2026-10-17, his
  // ask: "the portal should be able to edit the diagrams as much as the
  // Mac"). Double-click a picture, or Draw on Photo on its bar: the view fits
  // round it, the plan steps back, and the tools are the picture's own —
  // Select, Arrow, Line, Box, Oval, Draw, Words, Perspective (V A L B O D T P),
  // Undo and Redo. What is drawn is the picture's (`El::marks`, fractions of
  // it), read and written by the engine (`photo_marks` in web/src/lib.rs) and
  // kept with the plan's own `update` — the Mac and the iPhone draw the same
  // marks. A drag on its own draws or moves a mark; Space held, the middle
  // button, two fingers or a pinch move the view. Done or Escape goes back.

  const PHOTO_TOOLS = [["select", "Select", "v"], ["arrow", "Arrow", "a"], ["line", "Line", "l"], ["box", "Box", "b"], ["oval", "Oval", "o"], ["draw", "Draw", "d"], ["words", "Words", "t"], ["perspective", "Perspective", "p"]];
  const LOOKS = [["light", "Light", "#FFFFFF", "#000000"], ["dark", "Dark", "#141414", "#F4F4F2"], ["red", "Red", "#D44C47", "#141414"], ["yellow", "Yellow", "#F3C844", "#141414"]];
  const WORD_SIZES = [["Small", 0.032], ["Medium", 0.045], ["Large", 0.07]];
  const GUIDE_INK = "#5FD4FF";
  let photo = null;               // { id, tool, picked, back: view to go back to, strength }
  const photoEl = () => (photo ? el(photo.id) : null);
  const lookOfMark = (m) => m.look || "light";
  function photoLook() { try { return localStorage.getItem("shotlister.photolook") || "yellow"; } catch { return "yellow"; } }
  function setPhotoLook(l) { try { localStorage.setItem("shotlister.photolook", l); } catch { /* this visit */ } }
  function arrowThick() { try { const v = parseFloat(localStorage.getItem("shotlister.arrowthick")); return Number.isFinite(v) ? Math.min(Math.max(v, 0.5), 3) : 1; } catch { return 1; } }
  function setArrowThick(v) { try { localStorage.setItem("shotlister.arrowthick", String(v)); } catch { /* this visit */ } }
  /** The picture's marks, as the engine reads them. */
  function photoMarks(e = photoEl()) {
    if (!e || !e.marks) return [];
    const said = json(call("photo_marks", JSON.stringify({ parse: e.marks })));
    return (said && said.marks) || [];
  }
  function encodeMarks(marks) {
    const said = json(call("photo_marks", JSON.stringify({ encode: marks })));
    return said && typeof said.line === "string" ? said.line : "";
  }
  function photoPersp(e = photoEl()) {
    const s = String((e && e.perspective) || "");
    const i = s.indexOf(":");
    if (i < 0) return null;
    const h = parseFloat(s.slice(0, i)), v = parseFloat(s.slice(i + 1));
    return Number.isFinite(h) ? { horizon: h, vanish: Number.isFinite(v) ? v : null } : null;
  }
  const perspText = (p) => (!p ? "" : p.vanish === null || p.vanish === undefined ? `${p.horizon.toFixed(4)}:` : `${p.horizon.toFixed(4)}:${p.vanish.toFixed(4)}`);
  /** A fraction of the picture, to the box (pixels), and back. */
  function fracToBox(e, fx, fy) {
    const [rx, ry] = turnPt((fx - 0.5) * e.w, (fy - 0.5) * e.h, e.rot || 0);
    return storedToBox(e.x + rx, e.y + ry);
  }
  function boxToFrac(e, px, py) {
    const [x, y] = toStored(px, py);
    const [lx, ly] = turnPt(x - e.x, y - e.y, -(e.rot || 0));
    return [lx / e.w + 0.5, ly / e.h + 0.5];
  }
  /** The picture as drawn now, in pixels across and down. */
  const plate = (e) => [e.w * view().k, e.h * view().k];
  const clamp01 = (v) => Math.min(Math.max(v, 0), 1);

  /** Into the picture, the view fitted round it (the Mac's `drawOnPhoto`). */
  function drawOnPhoto(id) {
    const e = el(id);
    if (!e || e.kind !== "image" || !editor() || presenting) return;
    const b = box(), v = view();
    if (!b || !v) return;
    if (typing) endTyping(true);
    photo = { id, tool: "select", picked: null, back: { ...v }, strength: null, words: null };
    picks = []; legendPick = null; sideKey = ""; tool = "select"; closeMenu();
    const corners = [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.5], [-0.5, 0.5]].map(([a, c]) => { const [rx, ry] = turnPt(a * e.w, c * e.h, e.rot || 0); return shownOf(e.x + rx, e.y + ry); });
    const xs = corners.map((p) => p[0]), ys = corners.map((p) => p[1]);
    const bw = Math.max(...xs) - Math.min(...xs), bh = Math.max(...ys) - Math.min(...ys);
    const room = H.narrow() ? [24, 150] : [80, 190];
    const k = Math.max(Math.min((b.w - room[0]) / Math.max(bw, 0.05), (b.h - room[1]) / Math.max(bh, 0.05), 2000), 4);
    views.set(chosen(), { ...v, cx: (Math.max(...xs) + Math.min(...xs)) / 2, cy: (Math.max(...ys) + Math.min(...ys)) / 2 + 6 / k, k, fit: false });
    H.draw();
  }
  /** Done: back to the plan as it was, the picture picked. */
  function endPhoto(redraw = true) {
    if (!photo) return;
    commitWords();
    const { id, back } = photo;
    photo = null;
    preview = null;
    if (back && redraw) views.set(chosen(), back);
    if (el(id)) picks = [id];
    sideKey = "";
    if (redraw) H.draw();
  }
  function saveMarks(marks, label = "Draw on Photo") {
    if (!photo) return;
    edit({ op: "update", ids: [current(photo.id)], set: { marks: encodeMarks(marks) } }, { label });
  }
  function setPersp(p, label = "Guides") {
    if (!photo) return;
    edit({ op: "update", ids: [current(photo.id)], set: { perspective: perspText(p) } }, { label });
  }
  function setPhotoTool(t) {
    if (!photo) return;
    commitWords();
    photo.tool = t;
    if (t === "perspective" && !photoPersp()) setPersp({ horizon: 0.42, vanish: 0.5 });
    H.draw();
  }

  // ---- a mark's own arithmetic (the Mac's `PhotoMark`)
  function markThick(m) { return m.kind === "arrow" ? m.thickness || 1 : m.kind === "words" ? 1 : m.thick || 1; }
  function withThick(m, t) { t = Math.min(Math.max(t, 0.5), 3); return m.kind === "arrow" ? { ...m, thickness: t } : m.kind === "words" ? m : { ...m, thick: t }; }
  function movedMark(m, dx, dy) {
    const p = (q) => [q[0] + dx, q[1] + dy];
    if (m.kind === "arrow") return { ...m, x1: m.x1 + dx, y1: m.y1 + dy, x2: m.x2 + dx, y2: m.y2 + dy, pins: (m.pins || []).map(p) };
    if (m.kind === "draw") return { ...m, points: m.points.map(p) };
    if (m.kind === "words") return { ...m, at: p(m.at) };
    return { ...m, a: p(m.a), b: p(m.b) };
  }
  /** A mark's handles, by number, as fractions. */
  function markHandles(m) {
    if (m.kind === "arrow") return [[m.x1, m.y1], [m.x2, m.y2]];
    if (m.kind === "line") return [m.a, m.b];
    if (m.kind === "box" || m.kind === "oval") return [m.a, [m.b[0], m.a[1]], m.b, [m.a[0], m.b[1]]];
    return [];
  }
  /** An arrow's end moved, its bends following in share (the Mac's `movingEnd`). */
  function movingEnd(m, head, to) {
    const from = head ? [m.x2, m.y2] : [m.x1, m.y1];
    const dx = to[0] - from[0], dy = to[1] - from[1];
    const n = (m.pins || []).length;
    const pins = (m.pins || []).map((q, k) => { const along = (k + 1) / (n + 1), share = head ? along : 1 - along; return [q[0] + dx * share, q[1] + dy * share]; });
    return head ? { ...m, pins, x2: to[0], y2: to[1] } : { ...m, pins, x1: to[0], y1: to[1] };
  }
  /** How far a point (pixels on the plate) is from a mark, in pixels. */
  function markDistance(m, q, pw, ph) {
    const at = (f) => [f[0] * pw, f[1] * ph];
    const seg = (a, b) => {
      const dx = b[0] - a[0], dy = b[1] - a[1], l2 = Math.max(dx * dx + dy * dy, 1e-4);
      const u = Math.min(Math.max(((q[0] - a[0]) * dx + (q[1] - a[1]) * dy) / l2, 0), 1);
      return Math.hypot(q[0] - (a[0] + dx * u), q[1] - (a[1] + dy * u));
    };
    const chain = (pts) => { let best = Infinity; for (let i = 1; i < pts.length; i++) best = Math.min(best, seg(pts[i - 1], pts[i])); return best; };
    if (m.kind === "arrow") return chain([[m.x1, m.y1], ...(m.pins || []), [m.x2, m.y2]].map(at));
    if (m.kind === "line") return seg(at(m.a), at(m.b));
    if (m.kind === "box") { const [a, b] = [at(m.a), at(m.b)]; return chain([a, [b[0], a[1]], b, [a[0], b[1]], a]); }
    if (m.kind === "oval") {
      const [a, b] = [at(m.a), at(m.b)];
      const cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2, rx = Math.max(Math.abs(b[0] - a[0]) / 2, 1), ry = Math.max(Math.abs(b[1] - a[1]) / 2, 1);
      return Math.abs(Math.hypot((q[0] - cx) / rx, (q[1] - cy) / ry) - 1) * Math.min(rx, ry);
    }
    if (m.kind === "draw") return chain(m.points.map(at));
    if (m.kind === "words") { const r = wordsBox(m, pw, ph); return q[0] >= r[0] - 4 && q[0] <= r[2] + 4 && q[1] >= r[1] - 4 && q[1] <= r[3] + 4 ? 0 : Infinity; }
    return Infinity;
  }
  /** Where words sit on the plate: from their spot, as wide as they read. */
  function wordsBox(m, pw, ph) {
    const h = (m.size || 0.045) * ph;
    const lines = String(m.text || "").split("\n");
    const wide = Math.max(...lines.map((l) => l.length)) * h * 0.58;
    const x = m.at[0] * pw, y = m.at[1] * ph;
    return [x, y, x + Math.max(wide, h), y + h * 1.2 * Math.max(lines.length, 1)];
  }
  /** A line drawn from `a` follows the guides when within 4° of one (the Mac's `snapped`). Fractions in and out. */
  function snapGuide(a, b, pw, ph) {
    const p = photoPersp();
    if (!p) return b;
    const dx = (b[0] - a[0]) * pw, dy = (b[1] - a[1]) * ph, len = Math.hypot(dx, dy);
    if (len <= 6) return b;
    const ang = Math.atan2(dy, dx), close = 4 * Math.PI / 180;
    const diff = (x, y) => { let d = Math.abs(x - y) % (2 * Math.PI); return d > Math.PI ? 2 * Math.PI - d : d; };
    if (p.vanish !== null && p.vanish !== undefined) {
      const vx = (p.vanish - a[0]) * pw, vy = (p.horizon - a[1]) * ph;
      if (Math.hypot(vx, vy) > 4) {
        const toward = Math.atan2(vy, vx);
        for (const dir of [toward, toward + Math.PI]) if (diff(ang, dir) < close) return [a[0] + Math.cos(dir) * len / pw, a[1] + Math.sin(dir) * len / ph];
      }
    }
    for (const dir of [0, Math.PI]) if (diff(ang, dir) < close) return [a[0] + Math.cos(dir) * len / pw, a[1]];
    return b;
  }

  // ---- the hand on the picture (the Mac's `PhotoHand`)
  function photoDown(base, px, py) {
    const e = photoEl();
    if (!e) return { ...base, kind: "none" };
    commitWords();
    const [pw, ph] = plate(e);
    const f = boxToFrac(e, px, py);
    const q = [f[0] * pw, f[1] * ph];
    const marks = photoMarks(e);
    const t = photo.tool;
    const d = { ...base, kind: "photo", f0: f, marks, made: null, grab: null };
    if (t === "perspective") {
      const p = photoPersp(e) || { horizon: f[1], vanish: f[0] };
      const y = p.horizon * ph;
      d.grab = p.vanish !== null && p.vanish !== undefined && Math.hypot(q[0] - p.vanish * pw, q[1] - y) < 14 ? "vanish" : Math.abs(q[1] - y) < 10 ? "horizon" : p.vanish !== null && p.vanish !== undefined ? "vanish" : "horizon";
      d.guide = { ...p };
      return d;
    }
    const i = photo.picked;
    if (i !== null && marks[i]) {
      const k = markHandles(marks[i]).findIndex((h) => Math.hypot(h[0] * pw - q[0], h[1] * ph - q[1]) < 10);
      if (k >= 0) { d.grab = { handle: k }; return d; }
    }
    if (t === "select") {
      let hit = -1;
      for (let j = marks.length - 1; j >= 0; j--) if (markDistance(marks[j], q, pw, ph) < (base.touch ? 14 : 9)) { hit = j; break; }
      photo.picked = hit >= 0 ? hit : null;
      if (hit >= 0) d.grab = { whole: f };
      d.click = true;
      frame(); float();
      return d;
    }
    if (t === "words") { d.click = true; return d; }
    photo.picked = null;
    const look = photoLook();
    const pt = [clamp01(f[0]), clamp01(f[1])];
    if (t === "arrow") d.made = { kind: "arrow", x1: pt[0], y1: pt[1], x2: pt[0], y2: pt[1], pins: [], shape: "smooth", heads: 1, dashed: false, look, thickness: arrowThick(), depth: "flat" };
    else if (t === "line" || t === "box" || t === "oval") d.made = { kind: t, a: pt, b: pt, look, thick: 1, dashed: false };
    else if (t === "draw") { d.trail = [pt]; d.made = { kind: "draw", points: [pt, pt], look, thick: 1 }; }
    return d;
  }
  function photoMove(d, px, py) {
    const e = photoEl();
    if (!e) return;
    const [pw, ph] = plate(e);
    const f = boxToFrac(e, px, py), fc = [clamp01(f[0]), clamp01(f[1])];
    if (d.guide) {
      const g = d.guide;
      if (d.grab === "vanish") { g.horizon = f[1]; g.vanish = f[0]; } else g.horizon = f[1];
      preview = { op: "update", ids: [current(photo.id)], set: { perspective: perspText(g) } };
      return;
    }
    if (d.made) {
      const m = d.made;
      if (m.kind === "arrow") { const end = snapGuide([m.x1, m.y1], fc, pw, ph); m.x2 = end[0]; m.y2 = end[1]; }
      else if (m.kind === "line") m.b = snapGuide(m.a, fc, pw, ph);
      else if (m.kind === "box" || m.kind === "oval") m.b = fc;
      else if (m.kind === "draw") {
        const last = d.trail[d.trail.length - 1];
        if (Math.hypot((fc[0] - last[0]) * pw, (fc[1] - last[1]) * ph) >= 2.5 && d.trail.length < 400) d.trail.push(fc);
        m.points = [...d.trail, fc];
      }
      preview = { op: "update", ids: [current(photo.id)], set: { marks: encodeMarks([...d.marks, m]) } };
      return;
    }
    const i = photo.picked;
    if (!d.grab || i === null || !d.marks[i]) return;
    const work = d.marks.slice();
    if (d.grab.whole) { work[i] = movedMark(d.marks[i], f[0] - d.f0[0], f[1] - d.f0[1]); }
    else {
      const k = d.grab.handle, m = d.marks[i];
      if (m.kind === "arrow") work[i] = movingEnd(m, k === 1, fc);
      else if (m.kind === "line") { const end = snapGuide(k === 0 ? m.b : m.a, fc, pw, ph); work[i] = k === 0 ? { ...m, a: end } : { ...m, b: end }; }
      else {
        const a = m.a.slice(), b = m.b.slice();
        if (k === 0 || k === 3) a[0] = fc[0]; else b[0] = fc[0];
        if (k === 0 || k === 1) a[1] = fc[1]; else b[1] = fc[1];
        work[i] = { ...m, a, b };
      }
    }
    d.work = work;
    preview = { op: "update", ids: [current(photo.id)], set: { marks: encodeMarks(work) } };
  }
  function photoUp(d, px, py) {
    const e = photoEl();
    preview = null;
    if (!e) return paint();
    const [pw, ph] = plate(e);
    const travelled = Math.hypot(px - d.px0, py - d.py0);
    if (d.guide) { setPersp(d.guide); return; }
    if (d.made) {
      if (travelled <= 6) return paint();
      const next = [...d.marks, d.made];
      photo.picked = next.length - 1;
      saveMarks(next, { arrow: "Arrow", line: "Line", box: "Box", oval: "Oval", draw: "Draw" }[d.made.kind] || "Draw on Photo");
      float();
      return;
    }
    if (travelled < 4) {
      // A click: words go down, or are typed over (double-clicked, or with Words).
      const f = boxToFrac(e, px, py), q = [f[0] * pw, f[1] * ph];
      const now = performance.now();
      const double = photo.lastClick && now - photo.lastClick.t < 400 && Math.hypot(q[0] - photo.lastClick.q[0], q[1] - photo.lastClick.q[1]) < 6;
      photo.lastClick = double ? null : { t: now, q };
      const marks = d.marks;
      let hit = -1;
      for (let j = marks.length - 1; j >= 0; j--) if (marks[j].kind === "words" && markDistance(marks[j], q, pw, ph) < 4) { hit = j; break; }
      if (hit >= 0 && (double || photo.tool === "words")) { photo.picked = hit; return openWords(marks[hit].at, marks[hit].text, hit); }
      if (photo.tool === "words") return openWords([clamp01(f[0]), clamp01(f[1])], "", null);
      paint(); float();
      return;
    }
    if (d.work) { saveMarks(d.work, d.grab && d.grab.whole ? "Move Mark" : "Change Mark"); return; }
    paint();
  }

  // ---- words, typed on the picture
  function openWords(at, text, index) {
    const e = photoEl(), b = box();
    if (!e || !b) return;
    photo.words = { at, text, index };
    const [, ph] = plate(e);
    const marks = photoMarks(e);
    const look = index !== null && marks[index] ? lookOfMark(marks[index]) : photoLook();
    const size = index !== null && marks[index] ? marks[index].size || 0.045 : 0.045;
    const [bx, by] = fracToBox(e, at[0], at[1]);
    const r = b.vp.getBoundingClientRect();
    const t = document.createElement("textarea");
    t.className = "pphotowords";
    t.rows = 1;
    t.value = text || "";
    t.setAttribute("aria-label", "Words");
    const fs = Math.max(size * ph, 11);
    const ink = (LOOKS.find((l) => l[0] === look) || LOOKS[3])[2];
    t.style.cssText = `left:${r.left + bx - 3}px;top:${r.top + by}px;font-size:${fs}px;line-height:1.2;color:${ink};min-width:120px`;
    document.body.append(t);
    const fitIt = () => { t.style.height = "auto"; t.style.height = `${t.scrollHeight}px`; };
    fitIt();
    t.addEventListener("input", () => { if (photo && photo.words) photo.words.text = t.value; fitIt(); });
    t.addEventListener("keydown", (ev) => {
      ev.stopPropagation();
      if (ev.key === "Enter" && !ev.shiftKey) { ev.preventDefault(); commitWords(); }
      if (ev.key === "Escape") { ev.preventDefault(); if (photo) photo.words = null; t.remove(); const b = box(); if (b) b.vp.focus({ preventScroll: true }); paint(); }
    });
    t.addEventListener("blur", () => setTimeout(commitWords, 0));
    photo.wordsBox = t;
    setTimeout(() => t.focus(), 0);
  }
  function commitWords() {
    if (!photo || !photo.words) { if (photo && photo.wordsBox) { photo.wordsBox.remove(); photo.wordsBox = null; } return; }
    const w = photo.words;
    photo.words = null;
    if (photo.wordsBox) { photo.wordsBox.remove(); photo.wordsBox = null; }
    // The keys back on the plan: the tools' letters work again at once.
    { const b = box(); if (b) b.vp.focus({ preventScroll: true }); }
    const stored = photoMarks();
    const next = stored.slice();
    const text = String(w.text || "").trim();
    if (w.index !== null && next[w.index]) {
      if (!text) { next.splice(w.index, 1); photo.picked = null; }
      else next[w.index] = { ...next[w.index], text };
    } else if (text) {
      next.push({ kind: "words", at: w.at, text, look: photoLook(), size: 0.045 });
      photo.picked = next.length - 1;
    }
    if (JSON.stringify(next) !== JSON.stringify(stored)) saveMarks(next, "Words");
    else paint();
  }

  // ---- what the overlay draws while drawing on a picture
  function photoOverlay(add) {
    const e = photoEl();
    if (!e) return;
    const [pw, ph] = plate(e);
    const pt = (f) => fracToBox(e, f[0], f[1]);
    // The picture's edge, so its shape reads against the stepped-back plan.
    const c = [[0, 0], [1, 0], [1, 1], [0, 1]].map(pt);
    add("polygon", { class: "pphotoedge", points: c.map((q) => q.map((n) => n.toFixed(1)).join(",")).join(" ") });
    const live = drag && drag.kind === "photo" && drag.guide ? drag.guide : null;
    const p = live || photoPersp(e);
    if (p) {
      const dim = ["box", "oval", "draw", "words"].includes(photo.tool) ? 0.35 : 1;
      const g = add("g", { class: "pphotoguide", opacity: dim });
      const mk = (tag, attrs) => { const n = document.createElementNS(NS, tag); for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v); g.append(n); return n; };
      const [h1, h2] = [pt([0, p.horizon]), pt([1, p.horizon])];
      mk("line", { x1: h1[0], y1: h1[1], x2: h2[0], y2: h2[1], stroke: "rgba(0,0,0,.35)", "stroke-width": 3 });
      mk("line", { x1: h1[0], y1: h1[1], x2: h2[0], y2: h2[1], stroke: GUIDE_INK, "stroke-width": 1.4 });
      const lab = mk("text", { x: h1[0] + 8, y: h1[1] - 4, fill: GUIDE_INK, "font-size": 10, "font-weight": 700 });
      lab.textContent = "HORIZON";
      if (p.vanish !== null && p.vanish !== undefined) {
        const vp = pt([p.vanish, p.horizon]);
        const edges = [];
        for (let t2 = 0; t2 <= 1.0001; t2 += 1 / 6) edges.push([t2, 1], [t2, 0]);
        for (const t2 of [0.25, 0.5, 0.75]) edges.push([0, t2], [1, t2]);
        mk("path", { d: edges.map((q) => { const z = pt(q); return `M${vp[0].toFixed(1)} ${vp[1].toFixed(1)}L${z[0].toFixed(1)} ${z[1].toFixed(1)}`; }).join(""), stroke: GUIDE_INK, "stroke-opacity": 0.75, "stroke-width": 0.9, "stroke-dasharray": "5 5", fill: "none" });
        mk("circle", { cx: vp[0], cy: vp[1], r: 7, fill: "none", stroke: "rgba(0,0,0,.35)", "stroke-width": 3.5 });
        mk("circle", { cx: vp[0], cy: vp[1], r: 7, fill: "none", stroke: GUIDE_INK, "stroke-width": 2 });
        mk("circle", { cx: vp[0], cy: vp[1], r: 2, fill: GUIDE_INK });
      }
    }
    // The picked mark's handles: the arrow's head filled, the rest white.
    if (drag && drag.kind === "photo" && drag.made) return;
    const marks = drag && drag.kind === "photo" && drag.work ? drag.work : photoMarks(e);
    const i = photo.picked;
    if (i === null || !marks[i]) return;
    const m = marks[i];
    if (m.kind === "draw" || m.kind === "words") {
      let x1, y1, x2, y2;
      if (m.kind === "words") { const r = wordsBox(m, pw, ph); [x1, y1, x2, y2] = [r[0] / pw, r[1] / ph, r[2] / pw, r[3] / ph]; }
      else { const xs = m.points.map((q) => q[0]), ys = m.points.map((q) => q[1]); [x1, y1, x2, y2] = [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]; }
      const r = [[x1, y1], [x2, y1], [x2, y2], [x1, y2]].map(pt);
      add("polygon", { class: "pphotopick", points: r.map((q) => q.map((n) => n.toFixed(1)).join(",")).join(" ") });
      return;
    }
    markHandles(m).forEach((h, k) => {
      const [x, y] = pt(h);
      const head = m.kind === "arrow" && k === 1;
      add("circle", { class: `pphotohandle${head ? " head" : ""}`, cx: x, cy: y, r: 5.5 });
    });
  }

  // ---- the tool bar and the foot bar
  const PHOTO_ICONS = {
    select: `<path d="M6 3L15 11L10.8 11.6L13 16L11.2 16.8L9 12.3L6 15Z" fill="currentColor" stroke="none"/>`,
    arrow: `<path d="M4 16L15 5M9 5H15V11"/>`,
    line: `<path d="M3 17L17 3"/>`,
    box: `<rect x="3.5" y="5" width="13" height="10"/>`,
    oval: `<ellipse cx="10" cy="10" rx="7" ry="5.5"/>`,
    draw: `<path d="M3 14C6 8 8 16 11 11C14 6 15 6 17 7"/>`,
    words: `<text x="10" y="14.5" text-anchor="middle" font-size="12" font-weight="700" fill="currentColor" stroke="none" font-family="-apple-system,system-ui,sans-serif">Aa</text>`,
    perspective: `<path d="M1 9H19"/><path d="M10 9L3 17M10 9L17 17M10 9V17" stroke-width="1"/>`,
    undo: `<path d="M7 5L3 9L7 13M3 9H12C15 9 17 11 17 13.5S15 18 12 18H9"/>`,
    redo: `<path d="M13 5L17 9L13 13M17 9H8C5 9 3 11 3 13.5S5 18 8 18H11"/>`,
  };
  const photoIcon = (k) => `<svg viewBox="0 0 20 20" width="20" height="20" aria-hidden="true"><g fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${PHOTO_ICONS[k] || ""}</g></svg>`;
  function photoToolbar(phone) {
    const t = photo.tool;
    const btn = ([k, n, key]) => `<button type="button" class="ptool pphototool${t === k ? " on" : ""}${k === "perspective" ? " wide" : ""}" data-pphototool="${k}" aria-label="${n}" aria-pressed="${t === k}" title="${n} (${key.toUpperCase()})">${photoIcon(k)}<span>${n}</span>${phone ? "" : `<kbd>${key.toUpperCase()}</kbd>`}</button>`;
    const [sel, ...rest] = PHOTO_TOOLS;
    const drawing = rest.slice(0, 6), persp = rest[6];
    const u = undos.some((x) => x.scene === String(chosen())), r = redos.some((x) => x.scene === String(chosen()));
    return `<div class="plantools named pphototools${phone ? " phone" : ""}" role="toolbar" aria-label="Draw on Photo">${btn(sel)}<i class="psep"></i>${drawing.map(btn).join("")}<i class="psep"></i>${btn(persp)}<i class="psep"></i>
      <button type="button" class="ptool pphotoverb" data-pphotoundo="1"${u ? "" : " disabled"} title="Undo (⌘Z)">${photoIcon("undo")}<span>Undo</span></button><button type="button" class="ptool pphotoverb" data-pphotoredo="1"${r ? "" : " disabled"} title="Redo (⇧⌘Z)">${photoIcon("redo")}<span>Redo</span></button></div>`;
  }
  function looksHTML(now, attr) {
    return `<span class="pphotolooks">${LOOKS.map(([k, n, fill, line]) => `<button type="button" class="pphotolook${now === k ? " on" : ""}" data-${attr}="${k}" title="${n}" aria-label="${n}" aria-pressed="${now === k}"><i style="background:${fill};border-color:${line}"></i></button>`).join("")}</span>`;
  }
  function photoFoot(f) {
    const e = photoEl();
    if (!e) return;
    f.className = "planfloat pphotobar";
    const marks = photoMarks(e);
    const i = photo.picked;
    const m = i !== null ? marks[i] : null;
    const sep = `<i class="pphotosep"></i>`;
    const done = `<button type="button" class="pphotodone" data-pphotodone="1" title="Done (Esc)">Done</button>`;
    if (!m) {
      const strength = photo.strength ?? (e.opacity ?? 1);
      const p = photoPersp(e);
      const g = !p ? "off" : p.vanish === null || p.vanish === undefined ? "horizon" : "point";
      f.innerHTML = `<span class="pphotoword">Photo</span><input type="range" min="0.1" max="1" step="0.01" value="${strength}" data-pphotostrength="1" aria-label="Photo Strength" title="Photo Strength"><b class="pphotopct">${Math.round(strength * 100)}%</b>${sep}
        <span class="pphotoword">Guides</span><span class="pphotoseg">${[["off", "Off"], ["horizon", "Horizon"], ["point", "+ Point"]].map(([k, n]) => `<button type="button" class="${g === k ? "on" : ""}" data-pphotoguide="${k}"${k === "point" ? ` title="Horizon and Vanishing Point"` : ""}>${n}</button>`).join("")}</span>${sep}
        <span class="pphotoword">Color</span>${looksHTML(photoLook(), "pphotolookset")}${marks.length ? `${sep}<button type="button" class="pphotobtn" data-pphotoclear="1">Clear All…</button>` : ""}${sep}${done}`;
    } else {
      const kind = { arrow: "Arrow", line: "Line", box: "Box", oval: "Oval", draw: "Drawing", words: "Words" }[m.kind] || "Mark";
      let mid = "";
      if (m.kind === "arrow") mid = `${sep}<button type="button" class="pphotobtn pphotostyle" data-pphotostylemenu="1">Style ▾</button><span class="pphotoword">Thickness</span><input type="range" min="0.5" max="3" step="0.05" value="${markThick(m)}" data-pphotothick="1" aria-label="Thickness">`;
      else if (m.kind === "words") mid = `${sep}${WORD_SIZES.map(([n, v]) => `<button type="button" class="pphotobtn${Math.abs((m.size || 0.045) - v) < 0.002 ? " on" : ""}" data-pphotosize="${v}">${n}</button>`).join("")}`;
      else mid = `${sep}<span class="pphotoword">Thickness</span><input type="range" min="0.5" max="3" step="0.05" value="${markThick(m)}" data-pphotothick="1" aria-label="Thickness">${m.kind === "line" ? `<button type="button" class="pphotobtn${m.dashed ? " on" : ""}" data-pphotodashed="1">Dashed</button>` : ""}`;
      const nudge = [["left", -1, 0, "←"], ["up", 0, -1, "↑"], ["down", 0, 1, "↓"], ["right", 1, 0, "→"]].map(([n, dx, dy, g]) => `<button type="button" class="pphotonudge" data-pphotonudge="${dx},${dy}" title="Nudge ${n} (arrow keys; ⇧ for ten)" aria-label="Nudge ${n}">${g}</button>`).join("");
      f.innerHTML = `<b class="pphotokind">${kind}</b>${sep}${looksHTML(lookOfMark(m), "pphotolookmark")}${mid}${sep}<span class="pphotonudges">${nudge}</span>${sep}<button type="button" class="pphotobtn" data-pphotodelete="1" title="Delete (⌫)">Delete</button>${sep}${done}`;
    }
    wirePhotoFoot(f);
  }
  function replaceMark(i, m, label = "Change Mark") {
    const all = photoMarks();
    if (!all[i] || JSON.stringify(all[i]) === JSON.stringify(m)) return;
    all[i] = m;
    saveMarks(all, label);
  }
  function nudgeMark(dx, dy, ten) {
    const e = photoEl();
    if (!e || photo.picked === null) return;
    const all = photoMarks(e);
    const i = photo.picked;
    if (!all[i]) return;
    const step = (ten ? 10 : 1) / Math.max(view().k, 1e-6);
    all[i] = movedMark(all[i], dx * step / Math.max(e.w, 0.01), dy * step / Math.max(e.h, 0.01));
    saveMarks(all, "Nudge");
  }
  function deleteMark() {
    if (!photo || photo.picked === null) return;
    const all = photoMarks();
    if (!all[photo.picked]) return;
    all.splice(photo.picked, 1);
    photo.picked = null;
    saveMarks(all, "Delete Mark");
    float();
  }
  /** An arrow's look by name, in one menu: Line, Heads, Stroke, Depth (the Mac's Style). */
  function arrowStyleMenu(anchor, i, m) {
    const set = (next) => replaceMark(i, next, "Style");
    const shaped = (shape) => {
      const next = { ...m, shape };
      if (!(m.pins || []).length) {
        if (shape === "corner") next.pins = [[m.x2, m.y1]];
        else { const dx = m.x2 - m.x1, dy = m.y2 - m.y1; next.pins = [[(m.x1 + m.x2) / 2 + dy * 0.15, (m.y1 + m.y2) / 2 - dx * 0.15]]; }
      }
      return next;
    };
    const bent = (m.pins || []).length > 0;
    openMenu(anchor, [
      { head: "Line" },
      { label: "Straight", check: !bent, pick: () => set({ ...m, pins: [] }) },
      { label: "Smooth", check: bent && m.shape === "smooth", pick: () => set(shaped("smooth")) },
      { label: "Corner", check: bent && m.shape === "corner", pick: () => set(shaped("corner")) },
      { head: "Heads" },
      { label: "One Head", check: m.heads === 1, pick: () => set({ ...m, heads: 1 }) },
      { label: "Both Ends", check: m.heads === 2, pick: () => set({ ...m, heads: 2 }) },
      { label: "No Head", check: m.heads === 0, pick: () => set({ ...m, heads: 0 }) },
      { head: "Stroke" },
      { label: "Solid", check: !m.dashed, pick: () => set({ ...m, dashed: false }) },
      { label: "Dashed", check: Boolean(m.dashed), pick: () => set({ ...m, dashed: true }) },
      { head: "Depth" },
      ...[["flat", "Flat"], ["toward", "Toward"], ["away", "Away"]].map(([v, n]) => ({ label: n, check: (m.depth || "flat") === v, pick: () => set({ ...m, depth: v }) })),
    ], true, anchorAt(anchor));
  }
  function wirePhotoFoot(f) {
    const on = (sel, ev, fn) => f.querySelectorAll(sel).forEach((n) => n.addEventListener(ev, (x) => fn(n, x)));
    on("[data-pphotodone]", "click", () => endPhoto());
    on("[data-pphotostrength]", "input", (n) => {
      photo.strength = Number(n.value);
      const pct = f.querySelector(".pphotopct"); if (pct) pct.textContent = `${Math.round(photo.strength * 100)}%`;
      preview = { op: "update", ids: [current(photo.id)], set: { opacity: photo.strength } };
      frame();
    });
    on("[data-pphotostrength]", "change", (n) => {
      const v = Math.round(Number(n.value) * 100) / 100;
      photo.strength = null; preview = null;
      edit({ op: "update", ids: [current(photo.id)], set: { opacity: v } }, { label: "Photo Strength" });
    });
    on("[data-pphotoguide]", "click", (n) => {
      const p = photoPersp();
      const k = n.dataset.pphotoguide;
      if (k === "off") setPersp(null);
      else if (k === "horizon") setPersp({ horizon: p ? p.horizon : 0.42, vanish: null });
      else setPersp({ horizon: p ? p.horizon : 0.42, vanish: p && p.vanish !== null && p.vanish !== undefined ? p.vanish : 0.5 });
    });
    on("[data-pphotolookset]", "click", (n) => { setPhotoLook(n.dataset.pphotolookset); float(); });
    on("[data-pphotolookmark]", "click", (n) => {
      const all = photoMarks(), i = photo.picked;
      if (!all[i]) return;
      setPhotoLook(n.dataset.pphotolookmark);
      replaceMark(i, { ...all[i], look: n.dataset.pphotolookmark }, "Color");
    });
    on("[data-pphotoclear]", "click", () => {
      if (!confirm("Clear all marks on this photo? Undo brings them back.")) return;
      photo.picked = null;
      saveMarks([], "Clear All");
    });
    on("[data-pphotothick]", "change", (n) => {
      const all = photoMarks(), i = photo.picked;
      if (!all[i]) return;
      const v = Number(n.value);
      if (all[i].kind === "arrow") setArrowThick(v);
      replaceMark(i, withThick(all[i], v), "Thickness");
    });
    on("[data-pphotodashed]", "click", () => { const all = photoMarks(), i = photo.picked; if (all[i]) replaceMark(i, { ...all[i], dashed: !all[i].dashed }, "Dashed"); });
    on("[data-pphotosize]", "click", (n) => { const all = photoMarks(), i = photo.picked; if (all[i]) replaceMark(i, { ...all[i], size: Number(n.dataset.pphotosize) }, "Size"); });
    on("[data-pphotostylemenu]", "click", (n) => { const all = photoMarks(), i = photo.picked; if (all[i]) arrowStyleMenu(n, i, all[i]); });
    on("[data-pphotonudge]", "click", (n, ev) => { const [dx, dy] = n.dataset.pphotonudge.split(",").map(Number); nudgeMark(dx, dy, ev.shiftKey); });
    on("[data-pphotodelete]", "click", () => deleteMark());
  }
  /** The keys while drawing on a picture, ahead of the plan's own. */
  function photoKeys(ev) {
    const k = ev.key;
    const cmd = ev.metaKey || ev.ctrlKey;
    if (cmd || ev.altKey) return false;
    if (k === "Escape") { ev.preventDefault(); if (photo.picked !== null) { photo.picked = null; paint(); float(); } else endPhoto(); return true; }
    if (k === "Backspace" || k === "Delete") { ev.preventDefault(); deleteMark(); return true; }
    const arrows = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    if (arrows[k] && photo.picked !== null) { ev.preventDefault(); nudgeMark(...arrows[k], ev.shiftKey); return true; }
    const t = PHOTO_TOOLS.find(([, , key]) => key === k.toLowerCase());
    if (t && !ev.shiftKey) { ev.preventDefault(); setPhotoTool(t[0]); return true; }
    if (k === " ") return false;
    return arrows[k] ? true : false;
  }
  /** How many marks lie wholly on a picture — what Attach to Photo would bring onto it (`photomarks::attach`). */
  function marksLyingOn(p) {
    if (!p || !(p.w > 0 && p.h > 0)) return 0;
    const on = (x, y) => { const [lx, ly] = turnPt(x - p.x, y - p.y, -(p.rot || 0)); return Math.abs(lx) <= p.w / 2 + 0.001 && Math.abs(ly) <= p.h / 2 + 0.001; };
    return ((got && got.els) || []).filter((e) => {
      if (e.id === p.id || e.hidden || e.locked) return false;
      if (e.kind === "arrow") return on(e.x, e.y) && on(e.x2, e.y2);
      if (e.kind === "shape") return [[-1, -1], [1, -1], [1, 1], [-1, 1]].every(([sx, sy]) => { const [rx, ry] = turnPt(sx * e.w / 2, sy * e.h / 2, e.rot || 0); return on(e.x + rx, e.y + ry); });
      if (e.kind === "stroke") return (e.points || []).length >= 2 && e.points.every((q) => on(q[0], q[1]));
      if (e.kind === "text") return String(e.text || "").trim() !== "" && !isShared(e) && on(e.x, e.y);
      return false;
    }).length;
  }
  function attachMarks(id) {
    const n = marksLyingOn(el(id));
    if (!n) return;
    edit({ op: "attach_marks", id: current(id) }, { label: "Attach to Photo" });
    toast(n === 1 ? "1 Mark Attached" : `${n} Marks Attached`);
  }

  // ------------------------------------------------------------ the film's side

  function chose() {
    if (play) stop(false);
    closeSwap(false);
    picks = []; cam = null; beatsMode = false; preview = null; castMenu = null; picMenu = false; libOpen = false; sideKey = ""; copyPanel = null; roomOpen = false;
    if (photo) endPhoto(false);
    wallDraw = null; pickedCorner = null; pickedStretch = null; guides = []; hover = null; readout = null;
    mpts = []; mhover = null;
    closeMenu();
  }

  // For the portal's own checks (hub/diagram.mjs): where things are on the
  // page, read only — the checks press and drag like a hand does.
  window.shotlisterPlan = {
    picks: () => picks.slice(),
    scene: () => String(chosen()),
    library: () => library(),
    els: () => ((got && got.els) || []).map((e) => ({ ...e })),
    legend: () => ((got && got.legend) || []).map((r) => ({ ...r })),
    settings: () => ({ ...settings() }),
    // The engine's sheet, as Print draws it (Back to Paper, Batch 2).
    sheet: () => json(call("plan_sheet", JSON.stringify({ scene: String(chosen()), svg: true, printed: today() }))),
    pick: (ids) => { picks = ids.slice(); paint(); },
    // The sheet's lines as they stand on the page: what each is, and where to press it.
    lines: () => { const sh = onPage(); return sh ? sh.items.map((it, i) => { const n = root.querySelector(`.ppitem[data-ppitem="${i}"]`); const r = n && n.getBoundingClientRect(); return { kind: it.kind, key: it.key, name: it.name, count: it.count, x: r ? r.left + r.width / 2 : null, y: r ? r.top + r.height / 2 : null }; }) : []; },
    words: () => [...root.querySelectorAll(".ppsheet svg text")].map((t) => t.textContent).join(" | "),
    cams: () => ((got && got.cams) || []).map((c) => ({ ...c })),
    edit: (op) => edit(op, { label: "Check", record: false }),
    at: (x, y) => { const b = box(); const r = b.vp.getBoundingClientRect(); const [px, py] = storedToBox(x, y); return [r.left + px, r.top + py]; },
    handles: () => [...root.querySelectorAll(".planpic [data-h]")].map((n) => { const r = n.getBoundingClientRect(); return { h: n.getAttribute("data-h"), x: r.left + r.width / 2, y: r.top + r.height / 2 }; }),
    printIds: () => printIds(),
    photo: () => (photo ? { id: photo.id, tool: photo.tool, picked: photo.picked, marks: photoMarks() } : null),
    state: () => ({ tool, corner: pickedCorner, stretch: pickedStretch, pickedStep, picks: picks.slice(), drawing: Boolean(wallDraw), step: snapStep(), fold: barFold, swap: swap ? swap.id : "", k: view() ? view().k : 0, undo: undos.length ? undos[undos.length - 1].label : "", pending: pending.length + (sending ? 1 : 0) }),
  };

  // The list lights the scene or plan picked; the page draws its open diagram.
  return { mode, wire, chose, busy, rows, chosen: row, settleUp };
}


// **A door's kind** (2026-10-17), as the engine names it (`El::door_style`):
// set by its word, kept as slide / pair / pocket, so an older sliding door is
// Sliding.
const DOOR_KINDS = [["swing", "Swing"], ["double", "Double"], ["sliding", "Sliding"], ["center", "Center"], ["pocket", "Pocket"]];
function doorKind(e) {
  if (!e.slide) return e.pair ? "double" : "swing";
  if (e.pocket) return "pocket";
  return e.pair ? "center" : "sliding";
}
function doorSlides(kind) { return kind === "sliding" || kind === "center" || kind === "pocket"; }
function doorChange(e, kind) {
  const set = { door: kind };
  if (doorSlides(kind) !== Boolean(e.slide) && Number(e.swing ?? 90) > 0.5) set.swing = 90;
  return set;
}
