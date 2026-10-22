// The Script page's reader (SL-1338).
//
// **A PDF reader, in the tab.** His note on the first version, 2026-10-01:
// *"this looks really bad....should be able to read it in tab, like a pdf
// reader but be able to easily download before anything else"* — and, the
// same day: centred, not locked to a fixed width down the left, and the type
// has to grow when the window does. So: the pages are centred in the whole
// pane; **Fit Width** is where it starts, and the pages follow the window;
// Fit Page, zoom in and out, the page you are on of how many, and Download,
// on a bar that stays at the top while the pages scroll under it. The zoom
// he picks is remembered in this browser.
//
// **The real PDF, drawn with pdf.js** — the build a board uses. Not a frame
// round the file: an iPhone shows a framed PDF as its first page and stops.
//
// **The bytes are fetched here, with a bar that fills.** The first version
// handed pdf.js the address and showed an *Open PDF* button until the first
// page was drawn — and on a three-megabyte script over a real connection
// that button, alone on an empty page, is what he saw and judged it by.
//
// **Only the pages near the reader are drawn, and each is kept as a picture**
// at the sharpness it is shown at; zooming in or widening the window draws
// the near pages again, sharper. A page far away gives its picture back. A
// feature script is a hundred and twenty pages, and a canvas per page is
// more than an iPhone will hold. The words are laid over each page as
// invisible text (pdf.js's text layer), so they can be selected, copied and
// found with the browser's own Find.
//
// `public/deep.js` swaps pages in place and says `swapped`; this looks again
// every time.

const PDFJS = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/";
let lib = null;

async function pdfjs() {
  if (!lib) {
    lib = await import(`${PDFJS}pdf.min.mjs`);
    lib.GlobalWorkerOptions.workerSrc = `${PDFJS}pdf.worker.min.mjs`;
  }
  return lib;
}

/** The zoom steps, as a share of the page's printed size. */
const STEPS = [0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4];
const KEPT = "shotlister.reader.zoom";

function remembered() {
  try {
    const was = localStorage.getItem(KEPT);
    if (was === "width" || was === "page") return was;
    const n = Number(was);
    return n >= STEPS[0] && n <= STEPS[STEPS.length - 1] ? n : "width";
  } catch {
    return "width";
  }
}

function remember(mode) {
  try {
    localStorage.setItem(KEPT, String(mode));
  } catch {
    // a private window: the zoom is this visit's only
  }
}

/** Every reader on the page now, so one a swap took away can let its PDF go. */
const open = new Map();

function wake() {
  for (const [box, held] of open) {
    if (box.isConnected) continue;
    held.stop();
    open.delete(box);
  }
  for (const box of document.querySelectorAll(".reader[data-pdf]")) {
    if (open.has(box)) continue;
    const held = { stopped: false, stop() { this.stopped = true; } };
    open.set(box, held);
    read(box, held).catch((error) => {
      console.error("could not draw the script:", String(error));
      if (box.isConnected && !held.stopped) fallback(box);
    });
  }
}

/** The page's own scroller when it has one; on a phone the page itself scrolls. */
function scrollerOf(box) {
  const pane = box.closest(".scrolls");
  return pane && /(auto|scroll)/.test(getComputedStyle(pane).overflowY) ? pane : null;
}

/** The whole file, saying how far along it is. */
async function fetchAll(url, said) {
  const got = await fetch(url, { credentials: "same-origin" });
  if (!got.ok) throw new Error(`the script answered ${got.status}`);
  const total = Number(got.headers.get("content-length")) || 0;
  if (!got.body || !total) return new Uint8Array(await got.arrayBuffer());
  const reader = got.body.getReader();
  const parts = [];
  let have = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    parts.push(value);
    have += value.length;
    said(Math.min(1, have / total));
  }
  const all = new Uint8Array(have);
  let at = 0;
  for (const part of parts) {
    all.set(part, at);
    at += part.length;
  }
  return all;
}

async function read(box, held) {
  const pages = box.querySelector(".scriptpages");
  const loaded = box.querySelector("[data-loaded]");
  const where = box.querySelector("[data-at]");
  const pct = box.querySelector("[data-pct]");
  const bar = box.querySelector(".readerbar");
  const scroller = scrollerOf(box);

  const [pdf, bytes] = await Promise.all([
    pdfjs(),
    fetchAll(box.dataset.pdf, (part) => {
      if (loaded) loaded.style.width = `${Math.round(part * 100)}%`;
    }),
  ]);
  if (held.stopped || !box.isConnected) return;
  const doc = await pdf.getDocument({ data: bytes }).promise;
  if (held.stopped || !box.isConnected) {
    doc.destroy();
    return;
  }
  const first = (await doc.getPage(1)).getViewport({ scale: 1 });
  const count = doc.numPages;
  box.classList.add("ready");
  const pageCount = document.querySelector("[data-pagecount]");
  if (pageCount) pageCount.textContent = `${count} page${count === 1 ? "" : "s"}`;

  pages.textContent = "";
  const sheets = [];
  for (let n = 1; n <= count; n++) {
    const sheet = document.createElement("div");
    sheet.className = "scriptsheet";
    sheet.dataset.page = String(n);
    sheet.style.aspectRatio = `${first.width} / ${first.height}`;
    pages.append(sheet);
    sheets.push(sheet);
  }

  // ---- how wide the pages are --------------------------------------------
  // A page's printed size on screen is 96 pixels to the inch; 100% is that.
  const printed = (first.width * 96) / 72;
  let mode = remembered();
  let wide = 0;

  const fitWidth = () => {
    const style = getComputedStyle(pages);
    const inside = pages.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    return Math.max(160, inside - 1);
  };
  const fitPage = () => {
    const tall = (scroller ? scroller.clientHeight : window.innerHeight) - bar.offsetHeight - 40;
    return Math.min(fitWidth(), Math.max(160, (tall * first.width) / first.height));
  };
  const widthFor = (m) => (m === "width" ? fitWidth() : m === "page" ? fitPage() : printed * m);

  function layout() {
    const next = Math.round(widthFor(mode));
    for (const b of box.querySelectorAll("[data-fit]")) b.classList.toggle("on", b.dataset.fit === mode);
    if (pct) pct.textContent = `${Math.round((next / printed) * 100)}%`;
    if (next === wide) return;
    wide = next;
    box.style.setProperty("--sheet-w", `${wide}px`);
    // pdf.js sizes its invisible words by this; it is the page's own scale.
    box.style.setProperty("--scale-factor", String(wide / first.width));
    soon();
  }

  function zoom(way) {
    const now = wide / printed;
    const next = way === "in"
      ? STEPS.find((s) => s > now * 1.02) || STEPS[STEPS.length - 1]
      : [...STEPS].reverse().find((s) => s < now * 0.98) || STEPS[0];
    setMode(next);
  }

  function setMode(next) {
    // **Keep the page he is reading in view** — a zoom that throws him back
    // to page one is a zoom nobody uses twice.
    const on = current();
    const sheet = sheets[on - 1];
    const before = sheet ? sheet.getBoundingClientRect().top : 0;
    mode = next;
    remember(mode);
    layout();
    if (sheet) {
      const after = sheet.getBoundingClientRect().top;
      if (scroller) scroller.scrollTop += after - before;
      else window.scrollBy(0, after - before);
    }
  }

  box.addEventListener("click", (event) => {
    const z = event.target.closest("[data-zoom]");
    if (z) return zoom(z.dataset.zoom);
    const f = event.target.closest("[data-fit]");
    if (f) setMode(f.dataset.fit);
  });

  // ---- which pages to draw -----------------------------------------------
  const near = new Set();
  const queue = [];
  let busy = false;
  const sharp = () => Math.min(window.devicePixelRatio || 1, 2);
  // **Never under twice a printed page's width**: on a phone the page is
  // pinched open to read, and a picture drawn for 340 points is a blur at the
  // size it is read at. Never over 3000 across: an iPhone refuses a canvas
  // much past sixteen million pixels.
  const wanted = () => Math.min(3000, Math.max(wide * sharp(), first.width * 2));
  const needs = (sheet) => near.has(sheet) && Number(sheet.dataset.res || 0) < wanted() * 0.9;

  function soon() {
    clearTimeout(soon.timer);
    soon.timer = setTimeout(() => {
      for (const sheet of near) if (needs(sheet) && !queue.includes(sheet)) queue.push(sheet);
      run();
    }, 120);
  }

  async function run() {
    if (busy) return;
    busy = true;
    while (queue.length && !held.stopped) {
      // The page he is on first, then outwards from it.
      const on = current();
      queue.sort((a, b) => Math.abs(a.dataset.page - on) - Math.abs(b.dataset.page - on));
      const sheet = queue.shift();
      if (!needs(sheet)) continue;
      try {
        await draw(pdf, doc, sheet, wanted());
      } catch (error) {
        console.error("could not draw a page:", String(error));
      }
    }
    busy = false;
  }

  const watch = new IntersectionObserver((seen) => {
    for (const one of seen) {
      if (one.isIntersecting) {
        near.add(one.target);
        if (needs(one.target) && !queue.includes(one.target)) queue.push(one.target);
      } else {
        near.delete(one.target);
        letGo(one.target);
      }
    }
    run();
  }, { root: scroller, rootMargin: "150% 0px" });
  for (const sheet of sheets) watch.observe(sheet);

  // ---- the page he is on -------------------------------------------------
  function current() {
    const top = (scroller ? scroller.getBoundingClientRect().top : 0) + bar.offsetHeight;
    const tall = scroller ? scroller.clientHeight : window.innerHeight;
    const line = top + (tall - bar.offsetHeight) / 3;
    let lo = 0;
    let hi = sheets.length - 1;
    while (lo < hi) {
      const mid = (lo + hi) >> 1;
      if (sheets[mid].getBoundingClientRect().bottom < line) lo = mid + 1;
      else hi = mid;
    }
    return lo + 1;
  }
  let ticking = false;
  const said = () => {
    ticking = false;
    if (where) where.textContent = `Page ${current()} of ${count}`;
  };
  const onScroll = () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(said);
  };
  (scroller || window).addEventListener("scroll", onScroll, { passive: true });

  const resized = new ResizeObserver(() => layout());
  resized.observe(pages);

  layout();
  said();

  held.stop = () => {
    held.stopped = true;
    watch.disconnect();
    resized.disconnect();
    (scroller || window).removeEventListener("scroll", onScroll);
    for (const sheet of sheets) letGo(sheet);
    doc.destroy();
  };
}

/** A page far from the reader gives its picture back; its words stay. */
function letGo(sheet) {
  const img = sheet.querySelector("img");
  if (!img) return;
  URL.revokeObjectURL(img.src);
  img.remove();
  sheet.dataset.res = "0";
}

async function draw(pdf, doc, sheet, across) {
  const page = await doc.getPage(Number(sheet.dataset.page));
  const one = page.getViewport({ scale: 1 });
  const view = page.getViewport({ scale: across / one.width });
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(view.width);
  canvas.height = Math.round(view.height);
  const g = canvas.getContext("2d");
  g.fillStyle = "#fff";
  g.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: g, viewport: view }).promise;
  const blob = await new Promise((done) => canvas.toBlob(done, "image/jpeg", 0.9));
  // Let the canvas's memory go now, not when the collector gets round to it.
  canvas.width = 0;
  canvas.height = 0;
  if (!blob || !sheet.isConnected) return;

  // **The sharper picture replaces the softer one once it has loaded**, so a
  // zoom never flashes white.
  const img = document.createElement("img");
  img.alt = `Page ${sheet.dataset.page}`;
  img.src = URL.createObjectURL(blob);
  await img.decode().catch(() => {});
  const was = sheet.querySelector("img");
  if (was) {
    URL.revokeObjectURL(was.src);
    was.replaceWith(img);
  } else {
    sheet.prepend(img);
  }
  sheet.dataset.res = String(Math.round(across));

  if (!sheet.querySelector(".textLayer")) {
    const words = document.createElement("div");
    words.className = "textLayer";
    sheet.append(words);
    try {
      await new pdf.TextLayer({
        textContentSource: page.streamTextContent(),
        container: words,
        viewport: one,
      }).render();
    } catch {
      words.remove();
    }
  }
  page.cleanup();
}

/** pdf.js would not come: the browser's own viewer, and a line saying so. */
function fallback(box) {
  box.classList.add("ready", "framed");
  const pages = box.querySelector(".scriptpages");
  pages.textContent = "";
  const frame = document.createElement("iframe");
  frame.className = "scriptframe";
  frame.title = "Script";
  frame.src = box.dataset.pdf;
  pages.append(frame);
  const where = box.querySelector("[data-at]");
  if (where) where.textContent = "";
}

wake();
document.addEventListener("swapped", wake);
document.addEventListener("entering", wake);
