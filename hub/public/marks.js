// The Script page's Marks view (Ref 1568, the portal's half).
//
// **The draft in pages, with each shot's bar beside the lines it holds** — the
// same picture the Mac's Whole Script window and the phone's Script tab draw.
// A bar down the margin for every shot, lit along each line it holds and the
// blank rows between; the shot's number over the first line of a stretch; the
// words themselves tinted. Click a number, a bar or tinted words and that shot
// is the one followed: its marks go to the accent, as the panel's followed shot
// does on the Mac. Click it again to let go.
//
// **Nothing about where a mark goes is worked out here.** The film is replayed
// in the browser's engine (the same replay `film.js` makes, sharing its cache
// of change logs), and the engine is asked `script_marks` for the draft's
// pages: every line with the shots covering it, every shot's stretches, and
// the words a draft no longer has. This file positions and paints.
//
// The PDF stays the default. The switch is offered only when some shot holds
// lines of the screenplay and the draft's words are in the bucket
// (`scriptPage` in `src/pages.js`); with no PDF for a draft, this is the page.
//
// `public/deep.js` swaps pages in place and says `swapped`; this looks again
// every time.

const started = new WeakSet();

function wake() {
  for (const box of document.querySelectorAll("[data-marks]")) {
    // A draft with no PDF has nothing else to show: draw at once. Otherwise
    // the film is not replayed until somebody asks for the marks.
    if (!box.hidden) start(box);
  }
}

function start(box) {
  if (started.has(box)) return;
  started.add(box);
  draw(box).catch((error) => {
    console.error("could not draw the marks:", String(error));
    if (box.isConnected) box.innerHTML = `<p class="empty">The marks would not open</p>`;
  });
}

// ---- the switch ---------------------------------------------------------------

document.addEventListener("click", (event) => {
  const pick = event.target instanceof Element ? event.target.closest("[data-sview]") : null;
  if (pick) {
    const page = pick.closest(".scriptpage");
    if (!page) return;
    const marks = pick.dataset.sview === "marks";
    for (const b of page.querySelectorAll("[data-sview]")) b.classList.toggle("on", b === pick);
    const box = page.querySelector("[data-marks]");
    const reader = page.querySelector(".reader");
    if (reader) reader.hidden = marks;
    if (box) box.hidden = !marks;
    page.dataset.view = marks ? "marks" : "pdf";
    if (marks && box) start(box);
    // The reader sizes its pages to the pane; a pane it could not see has
    // nothing to size to, so ask it to look again now it can.
    if (!marks) window.dispatchEvent(new Event("resize"));
    return;
  }
  const one = event.target instanceof Element ? event.target.closest("[data-shot],[data-shots]") : null;
  if (!one) return;
  const box = one.closest("[data-marks]");
  if (!box) return;
  const id = one.dataset.shot || one.dataset.shots.split(" ")[0];
  follow(box, box.dataset.followed === id ? "" : id);
});

/** One shot's marks in the accent; an empty id lets go. */
function follow(box, id) {
  box.dataset.followed = id;
  for (const el of box.querySelectorAll("[data-shot],[data-shots]")) {
    const ids = (el.dataset.shots || el.dataset.shot || "").split(" ");
    el.classList.toggle("f", Boolean(id) && ids.includes(id));
  }
}

// ---- the engine, and the film in it ------------------------------------------------

let wasm = null;

const put = (text) => {
  const bytes = new TextEncoder().encode(text);
  const at = wasm.alloc(bytes.length);
  new Uint8Array(wasm.memory.buffer).set(bytes, at);
  return [at, bytes.length];
};

const take = (at) => {
  const len = new DataView(wasm.memory.buffer).getUint32(at, true);
  const text = new TextDecoder().decode(new Uint8Array(wasm.memory.buffer).slice(at + 4, at + 4 + len));
  wasm.free_result(at);
  return text;
};

/** The same cache `film.js` keeps its change logs in, under the same names. */
async function oneLog(kept, base, name, size) {
  const key = `/kept/log/${encodeURIComponent(name)}/${size}`;
  if (kept) {
    try {
      const held = await kept.match(key);
      if (held) return await held.text();
    } catch {
      /* fall through to the server */
    }
  }
  try {
    const got = await fetch(`${base}/api/log/${name}`, { credentials: "same-origin" });
    if (!got.ok) return null;
    if (kept) {
      try {
        await kept.put(key, got.clone());
      } catch {
        /* out of room — read it anyway */
      }
    }
    return await got.text();
  } catch {
    return null;
  }
}

async function replay(base) {
  const project = base.split("/").pop();
  let kept = null;
  try {
    kept = typeof caches === "undefined" ? null : await caches.open(`film-${project}`);
  } catch {
    kept = null;
  }
  const [source, state] = await Promise.all([
    WebAssembly.instantiateStreaming(fetch("/shotlister_web.wasm"), {}),
    fetch(`${base}/api/state`, { credentials: "same-origin" }).then((r) => {
      if (!r.ok) throw new Error(`the film answered ${r.status}`);
      return r.json();
    }),
  ]);
  wasm = source.instance.exports;
  wasm.set_now(Date.now());
  wasm.set_seed(Math.floor(Math.random() * 2 ** 53));
  const logs = (state.logs || []).slice().sort((a, b) => (a.name < b.name ? -1 : 1));
  const texts = await Promise.all(logs.map((l) => oneLog(kept, base, l.name, l.size)));
  wasm.reset();
  for (const text of texts) {
    if (text === null) continue;
    const [pointer, length] = put(text);
    wasm.add_log(pointer, length);
    wasm.dealloc(pointer, length);
  }
  wasm.settle();
}

async function draw(box) {
  const base = box.dataset.marks;
  const [words] = await Promise.all([
    fetch(box.dataset.text, { credentials: "same-origin" }).then((r) => {
      if (!r.ok) throw new Error(`the draft answered ${r.status}`);
      return r.text();
    }),
    replay(base),
  ]);
  const [pointer, length] = put(words);
  const marks = JSON.parse(take(wasm.script_marks(pointer, length)));
  wasm.dealloc(pointer, length);
  if (!box.isConnected) return;
  box.innerHTML = paper(marks);
  box.dataset.followed = "";
}

// ---- the paper -------------------------------------------------------------------

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

/** A page's lines, as the Mac window reads them: shots only where a line has a place in the draft. */
function paper(marks) {
  const ties = marks.ties || [];
  const known = new Set(ties.map((t) => t.shot));
  const numberOf = new Map(ties.map((t) => [t.shot, t.number]));
  const cover = (line) => (line.shots || []).filter((s) => known.has(s));

  // The widest page's bars, so every page keeps one margin.
  const columnsOn = (page) => {
    const out = [];
    for (const line of page.lines) for (const s of cover(line)) if (!out.includes(s)) out.push(s);
    return out;
  };
  const widest = Math.min(8, Math.max(0, ...marks.pageList.map((p) => columnsOn(p).length)));

  // The shots holding the last line with a place in the draft, before each page.
  let before = new Set();
  const out = [];
  if ((marks.lost || []).length) {
    out.push(`<div class="marklost"><b>Not in This Draft</b>${marks.lost.map((l) =>
      `<p><span class="n">${esc(l.number)}</span> ${l.words.map((w) => `<q>${esc(w)}</q>`).join(" ")}</p>`).join("")}</div>`);
  }
  for (const page of marks.pageList) {
    const columns = columnsOn(page);
    const rows = [];
    const bars = [];
    const numbers = [];
    let previous = null;
    let last = before;
    for (const line of page.lines) {
      rows.push(lineHtml(line, ties));
      if (line.from === undefined) continue;
      const here = cover(line);
      // Bars: the line itself, and the blank rows between two lines a shot holds.
      for (const shot of here) {
        const at = columns.indexOf(shot);
        if (previous && previous.set.has(shot) && line.row > previous.row + 1) {
          bars.push(bar(shot, at, previous.row + 1, line.row - previous.row - 1));
        }
        bars.push(bar(shot, at, line.row, 1));
      }
      // The number: over the first line of a stretch, once.
      const begin = here.filter((s) => !last.has(s));
      if (begin.length) {
        numbers.push(`<span class="mnum" style="top:calc(var(--lh)*${line.row})">${begin.map((s) =>
          `<b data-shot="${s}">${esc(numberOf.get(s) || "")}</b>`).join("")}</span>`);
      }
      previous = { row: line.row, set: new Set(here) };
      last = new Set(here);
    }
    before = last;
    out.push(`<article class="markpage" data-page="${page.number}">
      <div class="markbody" style="--rows:${marks.linesPerPage + 1}">${bars.join("")}${numbers.join("")}${rows.join("")}</div>
      <span class="markno">${page.number}</span></article>`);
  }
  return `<div class="markpages" style="--cols:${widest};--measure:${marks.measure}">${out.join("")}</div>`;
}

function bar(shot, column, row, rows) {
  return `<i class="mbar" data-shot="${shot}" style="left:calc(${column}*var(--bw)*-1 - var(--bw) - 6px);top:calc(var(--lh)*${row});height:calc(var(--lh)*${rows})"></i>`;
}

/** One line, its tied stretches tinted. Offsets are the draft's (UTF-16, as JavaScript indexes). */
function lineHtml(line, ties) {
  const style = `top:calc(var(--lh)*${line.row});padding-left:${Math.max(0, line.indent)}ch`;
  const cls = `ml${line.added ? " added" : ""}`;
  const text = line.text || "";
  if (line.from === undefined || !ties.length) return `<div class="${cls}" style="${style}">${esc(text)}</div>`;
  const stretches = [];
  for (const tie of ties) {
    for (const [a, b] of tie.spans || []) {
      const lo = Math.max(a, line.from) - line.from;
      const hi = Math.min(b, line.from + text.length) - line.from;
      if (hi > lo) stretches.push({ lo, hi, shot: tie.shot });
    }
  }
  if (!stretches.length) return `<div class="${cls}" style="${style}">${esc(text)}</div>`;
  const cuts = [...new Set([0, text.length, ...stretches.flatMap((s) => [s.lo, s.hi])])].sort((x, y) => x - y);
  let html = "";
  for (let i = 0; i + 1 < cuts.length; i++) {
    const [x, y] = [cuts[i], cuts[i + 1]];
    const over = [...new Set(stretches.filter((s) => s.lo <= x && s.hi >= y).map((s) => s.shot))];
    const piece = esc(text.slice(x, y));
    html += over.length
      ? `<mark class="mt${over.length > 1 ? " m2" : ""}" data-shots="${over.join(" ")}">${piece}</mark>`
      : piece;
  }
  return `<div class="${cls}" style="${style}">${html}</div>`;
}

wake();
document.addEventListener("swapped", wake);
document.addEventListener("entering", wake);
