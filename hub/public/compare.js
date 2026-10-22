// Two frames of the same shot, one lens against another.
//
// **Why it exists.** His ask, 2026-09-21, for the Call Her Back camera tests:
// *"for the lens tests where we are testing master primes, prominars and
// fujinon it would be great to have them in a sort of tool that allows me to
// compare them side by side or with a moving slider."* A published page may
// carry no script of its own — `pageHtmlOf` cuts every one — so the slider
// lives here, in the portal, the way the lightbox lives in `look.js`.
//
// **What a page has to write.** Nothing but frames:
//
//     <div class="cmp" data-cmp="Anya at the window">
//       <figure data-lens="Master Prime 40"><img src="pic/…"></figure>
//       <figure data-lens="Prominar 40"><img src="pic/…"></figure>
//       <figure data-lens="Fujinon 40"><img src="pic/…"></figure>
//     </div>
//
// With no script those figures stand side by side, which is still a
// comparison. With this script the block becomes a stage: two of the frames
// laid over one another, a handle to wipe between them, a row of buttons under
// each edge to choose which two, and *All* to see every frame in a row again.
//
// **One tool for every setup.** His note, 2026-09-22: four sliders down the
// page was *"a bit too spread out … would be nice to have one comparison
// slider."* So a figure may also carry `data-set="Close"`; when a block holds
// more than one set, a row of tabs stands over the stage to choose the
// framing, and the lens pickers and the *All* view show that set alone.
//
// **The ratio tool is its own block.** His note, 2026-09-22, after a first
// try hung a row of ratio chips under this slider: it should be *separate*
// from the lens comparison. So a `.ar` block is one frame at a time under a
// matte, the ratios as big chips over it, every shot as a thumbnail under
// it, and *All shots* to see the chosen ratio across the lot:
//
//     <div class="ar" data-native="1.456" data-size="4608x3164"
//          data-ratios="1.33, 1.66, 1.85, 2.39">
//       <figure data-lens="Master Prime 75 · T1.2"><img src="pic/…"></figure>
//     </div>
//
// With no script its figures stand in a grid.
//
// **Looked into, not bound to.** A deck is sealed in a shadow root by
// `made.js` and the page is swapped under `deep.js`, so this finds the sealed
// root fresh each time and rebuilds what it finds. Anything it has already
// built is marked and left alone.
//
// **A wipe is not a click.** `look.js` opens any picture in a deck on a click,
// and a drag that ends where it started is a click to the browser. The stage
// swallows a click that followed a drag, and lets a plain tap through so the
// frame still opens whole.

const STYLE = `
/* A design may set --cmp-ink, --cmp-line, --cmp-loud, --cmp-on-loud (text on
   a chosen button), --cmp-quiet and --cmp-font on .cmp to dress the furniture in its own colours. */
.cmp{display:flex;flex-wrap:wrap;gap:10px}
.cmp>figure{margin:0;flex:1 1 220px;min-width:0}
.cmp>figure img{width:100%;display:block;border-radius:0;background:#000}
.cmp.on{display:block}
.cmp.on>figure{display:none}
.cmp-stage{position:relative;overflow:hidden;border-radius:0;background:#000;
  touch-action:pan-y;user-select:none;-webkit-user-select:none;cursor:ew-resize}
.cmp-stage img{width:100%;display:block;pointer-events:none;-webkit-user-drag:none}
.cmp-b{position:relative}
.cmp-a{position:absolute;inset:0;clip-path:inset(0 var(--cut,50%) 0 0)}
.cmp-bar{position:absolute;top:0;bottom:0;left:calc(100% - var(--cut,50%));width:0;
  border-left:1px solid rgba(255,255,255,.9);box-shadow:0 0 0 1px rgba(0,0,0,.35);
  pointer-events:none}
.cmp-bar i{position:absolute;top:50%;left:0;transform:translate(-50%,-50%);
  width:34px;height:34px;border-radius:50%;background:rgba(10,10,10,.72);
  border:1px solid rgba(255,255,255,.9);backdrop-filter:blur(6px);
  display:flex;align-items:center;justify-content:center;gap:5px;
  font-family:var(--cmp-font,RS,system-ui,sans-serif);font-size:10px;color:#fff;letter-spacing:.05em}
.cmp-bar i:before,.cmp-bar i:after{content:"";display:block;width:0;height:0;
  border:5px solid transparent}
.cmp-bar i:before{border-right-color:#fff;margin-left:-4px}
.cmp-bar i:after{border-left-color:#fff;margin-right:-4px}
.cmp-tag{position:absolute;top:10px;font-family:var(--cmp-font,RS,system-ui,sans-serif);font-size:11px;
  letter-spacing:.16em;text-transform:uppercase;color:#fff;
  background:rgba(10,10,10,.62);padding:5px 9px;border-radius:2px;pointer-events:none;
  backdrop-filter:blur(6px)}
.cmp-tag.l{left:10px}.cmp-tag.r{right:10px}
.cmp-sets{display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px;font-family:var(--cmp-font,RS,system-ui,sans-serif)}
.cmp-sets button{appearance:none;font:inherit;font-family:var(--cmp-font,RS,system-ui,sans-serif);
  font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--cmp-quiet,rgba(239,225,214,.55));
  background:none;border:0;border-bottom:1px solid transparent;padding:6px 2px;margin-right:12px;
  cursor:pointer;line-height:1.2}
.cmp-sets button:hover{color:var(--cmp-ink,#EFE1D6)}
.cmp-sets button.on{color:var(--cmp-loud,#F2B45E);border-bottom-color:var(--cmp-loud,#F2B45E)}
.cmp.grid>figure[hidden]{display:none}
.cmp-picks{display:flex;justify-content:space-between;align-items:flex-start;gap:14px;
  margin-top:10px;font-family:var(--cmp-font,RS,system-ui,sans-serif)}
.cmp-pick{display:flex;flex-wrap:wrap;gap:6px;align-items:center}
.cmp-pick.r{justify-content:flex-end}
.cmp-pick b{font-size:10px;letter-spacing:.2em;text-transform:uppercase;font-weight:600;
  color:var(--cmp-quiet,rgba(239,225,214,.55));margin-right:4px}
.cmp-pick button,.cmp-all{appearance:none;font:inherit;font-family:var(--cmp-font,RS,system-ui,sans-serif);font-size:12px;letter-spacing:.04em;
  color:var(--cmp-ink,#EFE1D6);background:none;border:1px solid var(--cmp-line,rgba(255,255,255,.22));border-radius:999px;
  padding:5px 11px;cursor:pointer;line-height:1.2;white-space:nowrap}
.cmp-pick button:hover,.cmp-all:hover{border-color:var(--cmp-ink,#EFE1D6)}
.cmp-pick button.on{color:var(--cmp-on-loud,#0A0A0A);background:var(--cmp-loud,#F2B45E);border-color:var(--cmp-loud,#F2B45E)}
.cmp-pick button:disabled{opacity:.35;cursor:default}
.cmp-all{margin:10px auto 0;display:block;color:var(--cmp-quiet,rgba(239,225,214,.55))}
.cmp.grid .cmp-stage,.cmp.grid .cmp-picks{display:none}
.cmp.grid>figure{display:block}
.cmp.grid{display:grid;grid-template-columns:repeat(var(--cols,3),1fr);gap:10px}
.cmp.grid .cmp-all{grid-column:1/-1;margin-top:4px}
.cmp.grid .cmp-sets{grid-column:1/-1;margin-bottom:0}
.cmp figure figcaption{font-family:var(--cmp-font,RS,system-ui,sans-serif);font-size:11px;letter-spacing:.16em;
  text-transform:uppercase;color:var(--cmp-quiet,rgba(239,225,214,.55));margin-top:7px}
.cmp-mat{position:absolute;inset:0;overflow:hidden;pointer-events:none;z-index:1}
.cmp-win{position:absolute;top:var(--my,0%);bottom:var(--my,0%);left:var(--mx,0%);right:var(--mx,0%);
  box-shadow:0 0 0 9999px rgba(0,0,0,var(--mat,1));transition:top .25s,bottom .25s,left .25s,right .25s}
.ar.dim .cmp-win{outline:1px solid rgba(255,255,255,.6)}
.ar.native .cmp-win{box-shadow:none;outline:0}
.ar{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}
.ar>figure{margin:0}.ar>figure img{width:100%;display:block}
.ar.on{display:block}
.ar.on>figure{display:none}
.ar-chips{display:flex;flex-wrap:wrap;gap:8px;align-items:center;font-family:var(--cmp-font,RS,system-ui,sans-serif)}
.ar-chips button,.ar-tools button{appearance:none;font:inherit;font-family:var(--cmp-font,RS,system-ui,sans-serif);
  color:var(--cmp-ink,#EFE1D6);background:none;border:1px solid var(--cmp-line,rgba(255,255,255,.22));border-radius:999px;
  cursor:pointer;line-height:1.1;white-space:nowrap;font-variant-numeric:tabular-nums}
.ar-chips button{font-size:15px;padding:9px 16px;letter-spacing:.02em}
.ar-chips button:hover,.ar-tools button:hover{border-color:var(--cmp-ink,#EFE1D6)}
.ar-chips button.on,.ar-tools button.on{color:var(--cmp-on-loud,#0A0A0A);background:var(--cmp-loud,#F2B45E);border-color:var(--cmp-loud,#F2B45E)}
.ar-read{display:flex;justify-content:space-between;align-items:baseline;gap:12px;flex-wrap:wrap;margin:16px 0 10px;
  font-family:var(--cmp-font,RS,system-ui,sans-serif);font-size:11px;letter-spacing:.16em;text-transform:uppercase;
  color:var(--cmp-quiet,rgba(239,225,214,.55))}
.ar-read b{color:var(--cmp-ink,#EFE1D6);font-weight:600}
.ar-tools{display:flex;gap:6px}
.ar-tools button{font-size:12px;padding:5px 11px;letter-spacing:.04em}
.ar-stage{position:relative;border-radius:0;overflow:hidden;background:#000}
.ar-stage img{width:100%;display:block}
.ar-pic{position:relative;border-radius:0;overflow:hidden;background:#000}
.ar-pic img{width:100%;display:block}
.ar-thumbs{display:grid;grid-template-columns:repeat(auto-fill,minmax(104px,1fr));gap:8px 6px;margin-top:12px;align-items:start}
.ar-thumbs button{appearance:none;display:flex;flex-direction:column;justify-content:flex-start;width:100%;padding:0;border:0;background:none;cursor:pointer;text-align:left;
  font-family:var(--cmp-font,RS,system-ui,sans-serif);opacity:.55;transition:opacity .15s}
.ar-thumbs button:hover{opacity:.85}
.ar-thumbs button.on{opacity:1}
.ar-thumbs button.on .ar-pic{outline:2px solid var(--cmp-loud,#F2B45E);outline-offset:1px}
.ar-thumbs span{display:block;font-size:9px;letter-spacing:.08em;text-transform:uppercase;
  color:var(--cmp-quiet,rgba(239,225,214,.55));margin-top:4px;line-height:1.3}
.ar-grid{display:none;grid-template-columns:repeat(3,1fr);gap:10px}
.ar-grid figure{margin:0}
.ar-grid figcaption{font-family:var(--cmp-font,RS,system-ui,sans-serif);font-size:10px;letter-spacing:.14em;
  text-transform:uppercase;color:var(--cmp-quiet,rgba(239,225,214,.55));margin-top:6px}
.ar.all .ar-grid{display:grid}
.ar.all .ar-stage,.ar.all .ar-thumbs{display:none}
@media (max-width:700px){
  .ar-chips button{font-size:13px;padding:7px 12px}
  .ar-grid{grid-template-columns:repeat(2,1fr)}
  .cmp-tag{font-size:9px;letter-spacing:.08em;padding:4px 6px;max-width:calc(50% - 22px);
    overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .cmp-tag.l{left:6px}.cmp-tag.r{right:6px}
  .cmp-picks{flex-direction:column;align-items:stretch}
  .cmp-pick.r{justify-content:flex-start}
}
`;

/** The sealed deck's root, if this page has one. */
function madeRoot() {
  const host = document.querySelector(".madepage");
  return host && host.shadowRoot ? host.shadowRoot : null;
}

function build(block) {
  if (block.dataset.cmpBuilt) return;
  const figs = [...block.querySelectorAll(":scope > figure")].filter((f) => f.querySelector("img"));
  if (figs.length < 2) return;
  block.dataset.cmpBuilt = "1";

  // Every figure gets a caption saying which lens it is, so the *All* view
  // and the no-script view both name what they show.
  for (const f of figs) {
    if (!f.querySelector("figcaption") && f.dataset.lens) {
      const c = document.createElement("figcaption");
      c.textContent = f.dataset.lens;
      f.append(c);
    }
  }

  const frameOf = (f) => ({ name: f.dataset.lens || "", set: f.dataset.set || "", src: f.querySelector("img").src, alt: f.querySelector("img").alt || "", fig: f });
  const frames = figs.map(frameOf);
  const sets = [...new Set(frames.map((f) => f.set))];
  let set = 0, a = 0, b = 1, cut = 50, mode = "wipe";
  let lenses = [];

  const stage = document.createElement("div");
  stage.className = "cmp-stage";
  stage.innerHTML = `<div class="cmp-b"><img></div><div class="cmp-a"><img></div><div class="cmp-bar"><i></i></div><span class="cmp-tag l"></span><span class="cmp-tag r"></span>`;
  const imgA = stage.querySelector(".cmp-a img");
  const imgB = stage.querySelector(".cmp-b img");
  const tagL = stage.querySelector(".cmp-tag.l");
  const tagR = stage.querySelector(".cmp-tag.r");

  const picks = document.createElement("div");
  picks.className = "cmp-picks";
  const pickL = document.createElement("div"); pickL.className = "cmp-pick l";
  const pickR = document.createElement("div"); pickR.className = "cmp-pick r";
  picks.append(pickL, pickR);

  const all = document.createElement("button");
  all.type = "button";
  all.className = "cmp-all";

  const button = (side, i) => {
    const el = document.createElement("button");
    el.type = "button";
    el.textContent = lenses[i].name || `Frame ${i + 1}`;
    el.addEventListener("click", () => {
      if (side === "a") a = i; else b = i;
      draw();
    });
    return el;
  };

  // The tabs over the stage, only when there is more than one framing.
  const tabs = document.createElement("div");
  tabs.className = "cmp-sets";
  if (sets.length > 1) {
    sets.forEach((name, i) => {
      const el = document.createElement("button");
      el.type = "button";
      el.textContent = name || `Set ${i + 1}`;
      el.addEventListener("click", () => { set = i; choose(); });
      tabs.append(el);
    });
  }

  // Take up one framing: its lenses become the pickers, and the first two
  // stand on the stage.
  function choose() {
    lenses = frames.filter((f) => f.set === sets[set]);
    a = 0; b = Math.min(1, lenses.length - 1);
    const labelL = document.createElement("b"); labelL.textContent = "Left";
    const labelR = document.createElement("b"); labelR.textContent = "Right";
    pickL.replaceChildren(labelL, ...lenses.map((_, i) => button("a", i)));
    pickR.replaceChildren(labelR, ...lenses.map((_, i) => button("b", i)));
    for (const f of frames) f.fig.hidden = f.set !== sets[set];
    [...tabs.querySelectorAll("button")].forEach((el, i) => el.classList.toggle("on", i === set));
    draw();
  }

  function draw() {
    imgA.src = lenses[a].src; imgA.alt = lenses[a].alt;
    imgB.src = lenses[b].src; imgB.alt = lenses[b].alt;
    tagL.textContent = lenses[a].name;
    tagR.textContent = lenses[b].name;
    stage.style.setProperty("--cut", `${100 - cut}%`);
    [...pickL.querySelectorAll("button")].forEach((el, i) => { el.classList.toggle("on", i === a); el.disabled = i === b; });
    [...pickR.querySelectorAll("button")].forEach((el, i) => { el.classList.toggle("on", i === b); el.disabled = i === a; });
    block.classList.toggle("grid", mode === "grid");
    // Three across, or fewer when the set is smaller; two on a phone.
    const most = block.clientWidth < 640 ? 2 : 3;
    block.style.setProperty("--cols", String(Math.max(1, Math.min(most, lenses.length))));
    all.textContent = mode === "grid" ? "Back to the slider" : "See all side by side";
  }

  // The wipe. Pointer events cover mouse, pen and touch alike; the stage
  // captures the pointer so a drag that leaves it keeps moving the bar.
  let down = null, dragged = false;
  const at = (e) => {
    const r = stage.getBoundingClientRect();
    cut = Math.max(0, Math.min(100, ((e.clientX - r.left) / r.width) * 100));
    stage.style.setProperty("--cut", `${100 - cut}%`);
  };
  stage.addEventListener("pointerdown", (e) => {
    if (e.button !== 0 && e.pointerType === "mouse") return;
    down = e.clientX; dragged = false;
    stage.setPointerCapture(e.pointerId);
    at(e);
  });
  stage.addEventListener("pointermove", (e) => {
    if (down === null) return;
    if (Math.abs(e.clientX - down) > 3) dragged = true;
    at(e);
  });
  const up = () => { down = null; };
  stage.addEventListener("pointerup", up);
  stage.addEventListener("pointercancel", up);
  // A drag ends in a click as far as the browser is concerned; `look.js`
  // would open the frame. Swallow that one, let a plain tap through.
  stage.addEventListener("click", (e) => {
    if (dragged) { e.stopPropagation(); e.preventDefault(); dragged = false; }
  }, true);
  stage.addEventListener("keydown", (e) => {
    if (e.key === "ArrowLeft") { cut = Math.max(0, cut - 2); draw(); e.preventDefault(); }
    if (e.key === "ArrowRight") { cut = Math.min(100, cut + 2); draw(); e.preventDefault(); }
  });
  stage.tabIndex = 0;
  stage.setAttribute("role", "slider");
  stage.setAttribute("aria-label", block.dataset.cmp || "Lens comparison");

  all.addEventListener("click", () => { mode = mode === "grid" ? "wipe" : "grid"; draw(); });
  window.addEventListener("resize", () => { if (mode === "grid") draw(); });

  block.prepend(tabs, stage, picks);
  block.append(all);
  block.classList.add("on");
  choose();
}

function buildRatio(block) {
  if (block.dataset.arBuilt) return;
  const figs = [...block.querySelectorAll(":scope > figure")].filter((f) => f.querySelector("img"));
  if (!figs.length) return;
  block.dataset.arBuilt = "1";
  const shots = figs.map((f) => ({ name: f.dataset.lens || "", src: f.querySelector("img").src }));
  const ratios = [0, ...(block.dataset.ratios || "").split(",").map((r) => parseFloat(r)).filter((r) => r > 0)];
  const [sw, sh] = (block.dataset.size || "").split("x").map(Number);
  let native = parseFloat(block.dataset.native) || (sw && sh ? sw / sh : 0);
  let chosen = 0, at = 0;

  const mat = () => { const m = document.createElement("div"); m.className = "cmp-mat"; m.innerHTML = `<div class="cmp-win"></div>`; return m; };
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

  const chips = el("div", "ar-chips");
  const chipEls = ratios.map((r, i) => {
    const b = el("button", "", r ? r.toFixed(2) : (block.dataset.nativeName || "Open Gate"));
    b.type = "button";
    b.addEventListener("click", () => { chosen = i; draw(); });
    chips.append(b);
    return b;
  });

  const read = el("div", "ar-read");
  const say = el("span");
  const tools = el("span", "ar-tools");
  const dim = el("button", "", "Dim"); dim.type = "button";
  const all = el("button", "", "All Shots"); all.type = "button";
  tools.append(dim, all);
  read.append(say, tools);
  dim.addEventListener("click", () => { block.classList.toggle("dim"); draw(); });
  all.addEventListener("click", () => { block.classList.toggle("all"); draw(); });

  const stage = el("div", "ar-stage");
  const big = el("img"); big.alt = "";
  stage.append(big, mat());

  const thumbs = el("div", "ar-thumbs");
  const grid = el("div", "ar-grid");
  const thumbEls = shots.map((s, i) => {
    const b = el("button"); b.type = "button";
    const pic = el("div", "ar-pic");
    const im = el("img"); im.src = s.src; im.alt = s.name; im.loading = "lazy";
    pic.append(im, mat());
    b.append(pic, el("span", "", s.name));
    b.addEventListener("click", () => { at = i; draw(); });
    thumbs.append(b);
    const fig = el("figure");
    const gp = el("div", "ar-pic");
    const gi = el("img"); gi.src = s.src; gi.alt = s.name; gi.loading = "lazy";
    gp.append(gi, mat());
    fig.append(gp, el("figcaption", "", s.name));
    fig.addEventListener("click", () => { at = i; block.classList.remove("all"); draw(); stage.scrollIntoView({ block: "nearest", behavior: "smooth" }); });
    grid.append(fig);
    return b;
  });

  function draw() {
    const r = ratios[chosen];
    const n = native || 1;
    const my = r > n ? ((1 - n / r) / 2) * 100 : 0;
    const mx = r && r < n ? ((1 - r / n) / 2) * 100 : 0;
    block.style.setProperty("--my", `${my}%`);
    block.style.setProperty("--mx", `${mx}%`);
    block.style.setProperty("--mat", block.classList.contains("dim") ? ".62" : "1");
    block.classList.toggle("native", !r);
    chipEls.forEach((b, i) => b.classList.toggle("on", i === chosen));
    thumbEls.forEach((b, i) => b.classList.toggle("on", i === at));
    dim.classList.toggle("on", block.classList.contains("dim"));
    dim.hidden = !r;
    all.classList.toggle("on", block.classList.contains("all"));
    big.src = shots[at].src; big.alt = shots[at].name;
    // What the ratio takes out of the frame as shot, in the camera's pixels.
    const shape = r ? `${r.toFixed(2)}:1` : (native ? `${native.toFixed(2)}:1` : "");
    let size = "";
    if (sw && sh) {
      const w = r && r < n ? Math.round(sh * r) : sw;
      const h = r > n ? Math.round(sw / r) : sh;
      size = ` · ${w} × ${h}`;
    }
    say.innerHTML = "";
    const b = el("b", "", block.classList.contains("all") ? `${shots.length} shots` : shots[at].name);
    say.append(b, document.createTextNode(`  ·  ${shape}${size}`));
  }

  block.append(chips, read, stage, thumbs, grid);
  block.classList.add("on");
  if (!native) {
    const first = big;
    first.addEventListener("load", () => { if (!native && first.naturalWidth) { native = first.naturalWidth / first.naturalHeight; draw(); } }, { once: true });
  }
  draw();
}

function wire() {
  const root = madeRoot();
  if (!root) return;
  if (!root.querySelector("style[data-cmp]")) {
    const st = document.createElement("style");
    st.dataset.cmp = "1";
    st.textContent = STYLE;
    root.append(st);
  }
  for (const block of root.querySelectorAll(".cmp")) build(block);
  for (const block of root.querySelectorAll(".ar")) buildRatio(block);
}

wire();
document.addEventListener("swapped", wire);
