/**
 * The press, on the portal.
 *
 * **His ask, 2026-09-07:** *"can we get pdf compiling and exporting up and
 * running on the server?"* Until now the Mac was the press: a launchd agent
 * pulled the sheets the editor published, wrapped them in the print design's
 * head, and printed them with a headless Chrome — because a beautiful PDF wants
 * his real typefaces and a real browser, and the portal had neither. It has
 * both now. The typefaces went onto the film with the paper kit (2026-09-07),
 * and Cloudflare's Browser Rendering is a real Chrome beside this worker.
 *
 * So a print is: the sheets the editor published (`decks/<slug>.paper.html`),
 * the kit's stylesheet (`decks/<slug>.paper.json`), every `pic/` address made
 * absolute so the browser can fetch the pictures and fonts off the film, then
 * `page.pdf()` at Letter with backgrounds on. The file is stored by its own
 * contents and filed under the film's Documents exactly as the Mac filed it,
 * and the record is stamped `printed`, which is what the editor reads.
 *
 * **Addresses are made absolute on a host with no sign-in in front of it.** The
 * apex sits behind Cloudflare Access, and a browser with no cookie is sent to
 * the login page in place of every picture. `PRESS_HOST` names the workers.dev
 * address of this same worker, which has no Access application.
 */
import { keys } from "../../relay/layout.js";
import puppeteer from "@cloudflare/puppeteer";
import { frontOf, saveFront } from "./front.js";

const LIMIT_MS = 55_000;

/** Split on a separator that is not inside brackets — `rgba(255, 0, 0, .5)`
 *  is one thing, not four. */
function splitTop(said, sep) {
  const out = []; let depth = 0; let at = 0;
  for (let i = 0; i < said.length; i += 1) {
    const c = said[i];
    if (c === "(") depth += 1;
    else if (c === ")") depth -= 1;
    else if (c === sep && depth === 0) { out.push(said.slice(at, i)); at = i + 1; }
  }
  out.push(said.slice(at));
  return out.map((x) => x.trim()).filter(Boolean);
}

/**
 * **A glow has to be a filter, or the PDF draws it as a box.**
 *
 * His report, 2026-09-07: *"there are these weird blocks of color all over the
 * deck any time there is a title."* Chrome's PDF writer does not put a blurred
 * `text-shadow` in the file as a blur — it writes something macOS renders as
 * the shadow's **bounding box, filled**. So every neon title came out as three
 * or four stacked rectangles of red and amber. It is not the design's fault and
 * it is not visible in every reader: `pdftoppm` draws the same file correctly,
 * which is exactly why it survived a whole evening of checking.
 *
 * `filter: drop-shadow()` is rasterised properly by the same writer — a true
 * glow, with the letterforms still vector and sharp. Proven side by side before
 * this was written: four-layer `text-shadow` → blocks, a single 3px
 * `text-shadow` → still a block, `drop-shadow` → a glow.
 *
 * So every `text-shadow` in a print stylesheet is turned into `drop-shadow` on
 * the way to the press. Done here rather than in any one deck's design, because
 * no deck's designer should have to know this. Layers wider than `WIDEST_BLUR`
 * are dropped: a 60px blur is a whole page of pixels to rasterise for a halo
 * nobody can see, and at most two survive — the tightest and the widest — which
 * is what carries the neon.
 */
const WIDEST_BLUR = 30;

const PER_UNIT = { px: 1, in: 96, pt: 96 / 72, pc: 16, cm: 37.8, mm: 3.78, em: 16, rem: 16 };

/** A shadow layer's blur, in pixels: the third length in it, colours removed
 *  first so a hex or an `rgba()` cannot be read as a number. */
function blurOf(layer) {
  const bare = layer
    .replace(/(?:rgba?|hsla?|var|color|calc)\([^)]*\)/gi, " ")
    .replace(/#[0-9a-f]{3,8}\b/gi, " ");
  const lengths = bare.match(/-?\d*\.?\d+(?:px|in|pt|pc|cm|mm|r?em)?/gi) || [];
  const third = lengths[2];
  if (!third) return 0;
  const unit = (third.match(/[a-z]+$/i) || [""])[0].toLowerCase();
  return Math.abs(parseFloat(third)) * (PER_UNIT[unit] || 1);
}

function glowsForPrint(css) {
  return css.replace(/text-shadow\s*:\s*([^;}]+)([;}])/gi, (whole, value, end) => {
    if (/^\s*none\s*$/i.test(value)) return whole;
    const layers = splitTop(value, ",").map((layer) => ({ layer, blur: blurOf(layer) }))
      .filter((l) => l.blur <= WIDEST_BLUR);
    if (!layers.length) return end;                       // only vast blurs: drop it
    layers.sort((a, b) => a.blur - b.blur);
    const keep = layers.length > 2 ? [layers[0], layers[layers.length - 1]] : layers;
    return `filter:${keep.map((l) => `drop-shadow(${l.layer})`).join(" ")}${end}`;
  });
}

export async function printDeck(env, project, slug, host) {
  const began = Date.now();
  const [sheets, kit, held] = await Promise.all([
    env.BUCKET.get(keys.paperHtml(project, slug)),
    env.BUCKET.get(keys.paper(project, slug)),
    env.BUCKET.get(keys.deck(project, slug)),
  ]);
  if (!sheets) return { error: "No sheets have been published for this deck yet." };
  if (!kit) return { error: "This deck has no paper design on the portal. Publish once from the Mac." };
  if (!held) return { error: "This deck has no record." };
  let css = "";
  try { css = String(JSON.parse(await kit.text()).css || ""); } catch { css = ""; }
  if (!css) return { error: "The paper design's stylesheet could not be read." };
  let record;
  try { record = JSON.parse(await held.text()); } catch { return { error: "The record could not be read." }; }

  const pics = `${host}/f/${project}/pic/`;
  // The editor's own addresses: `../pic/` in the stylesheet (it sits one level
  // down), `pic/` on the sheets. Both become the film's absolute address.
  css = css.replace(/url\((['"]?)(?:\.\.\/)?pic\//g, `url($1${pics}`);
  css = glowsForPrint(css);
  // **Nothing lazy on paper.** The editor marks every frame `loading="lazy"`
  // so a long deck scrolls lightly; printed, a lazy picture below the fold is
  // never asked for at all, and the first print came out with half its frames
  // empty (2026-09-07, 31 of 62 pictures fetched).
  const body = (await sheets.text())
    .replace(/(\s(?:src|href)=")(?:\.\.\/)?pic\//g, `$1${pics}`)
    .replace(/\s+loading="lazy"/g, "")
    // Read back through a canvas below, which a cross-origin picture allows
    // only when it was fetched with CORS and the answer permitted it.
    .replace(/<img\s/g, '<img crossorigin="anonymous" ');
  const doc = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>${slug}</title>`
    + `<style>${css}</style></head><body>${body}</body></html>`;

  // **A key for the pictures, for this print only.** The worker's `pic` route
  // opens for a request carrying it, for a few minutes, and it is taken off
  // the film again the moment the print is done.
  const key = crypto.randomUUID();
  const keyAt = keys.press(project, key);
  await env.BUCKET.put(keyAt, JSON.stringify({ until: Date.now() + 5 * 60_000 }), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });

  let pdf;
  const browser = await puppeteer.launch(env.BROWSER, { keep_alive: 180_000 });
  try {
    const page = await browser.newPage();
    page.setDefaultTimeout(LIMIT_MS);
    // **One device pixel per CSS pixel, and a window the size of a sheet.** A
    // higher scale factor makes Chrome re-draw every cropped picture as a raw
    // bitmap at that scale instead of passing the JPEG through — the first
    // print here was 160 MB for 62 pictures the Mac had printed into 6 MB.
    await page.setViewport({ width: 816, height: 1056, deviceScaleFactor: 1 });
    await page.setExtraHTTPHeaders({ "x-press": key });
    // **Every picture and every typeface, before printing.** `networkidle0`
    // waits for the fetches to settle; `document.fonts.ready` for the faces
    // to be usable, or a sheet prints in the fallback serif.
    await page.setContent(doc, { waitUntil: "networkidle0", timeout: LIMIT_MS });
    await page.evaluate(() => Promise.all([
      document.fonts.ready,
      ...[...document.images].map((img) => (img.complete ? null
        : new Promise((done) => { img.onload = done; img.onerror = done; }))),
    ]));
    // **Every picture re-drawn at the size it prints, as a JPEG.** Chrome's
    // PDF writer passes a JPEG straight through only when the whole picture is
    // drawn; a picture cropped by `object-fit: cover` — every frame here — is
    // re-encoded as a raw bitmap at print resolution instead, and the first
    // print on Cloudflare came out at 160 MB against the Mac's 6 MB. So each
    // frame is cropped and scaled in the page itself, to three device pixels a
    // CSS pixel (about 290 dpi), and put back as a JPEG the writer can keep.
    await page.evaluate((scale) => {
      const pct = (said, fallback) => {
        const m = /^(-?[\d.]+)%$/.exec(String(said || "").trim());
        return m ? Number(m[1]) / 100 : fallback;
      };
      for (const img of [...document.images]) {
        const box = img.getBoundingClientRect();
        if (!box.width || !box.height || !img.naturalWidth || !img.naturalHeight) continue;
        const style = getComputedStyle(img);
        if (style.objectFit !== "cover" && style.objectFit !== "fill") continue;
        const iw = img.naturalWidth; const ih = img.naturalHeight;
        let sx = 0; let sy = 0; let sw = iw; let sh = ih;
        if (style.objectFit === "cover") {
          const [px, py] = style.objectPosition.split(/\s+/);
          const want = box.width / box.height;
          if (iw / ih > want) { sw = ih * want; sx = (iw - sw) * pct(px, 0.5); }
          else { sh = iw / want; sy = (ih - sh) * pct(py, 0.5); }
        }
        const canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(box.width * scale));
        canvas.height = Math.max(1, Math.round(box.height * scale));
        try {
          canvas.getContext("2d").drawImage(img, sx, sy, sw, sh, 0, 0, canvas.width, canvas.height);
          img.src = canvas.toDataURL("image/jpeg", 0.86);
          img.style.objectFit = "fill";
          img.style.objectPosition = "50% 50%";
        } catch (_) { /* a picture that refused the canvas prints as it was */ }
      }
    }, 3);
    await page.evaluate(() => Promise.all([...document.images].map((img) => (img.complete ? null
      : new Promise((done) => { img.onload = done; img.onerror = done; })))));
    pdf = await page.pdf({
      format: "letter", printBackground: true, preferCSSPageSize: true,
      margin: { top: 0, right: 0, bottom: 0, left: 0 }, timeout: LIMIT_MS,
    });
  } finally {
    await browser.close();
    await env.BUCKET.delete(keyAt).catch(() => {});
  }
  const bytes = pdf instanceof Uint8Array ? pdf : new Uint8Array(pdf);
  if (bytes.length < 1000) return { error: "The print came out empty." };

  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const file = [...new Uint8Array(digest)].slice(0, 16).map((b) => b.toString(16).padStart(2, "0")).join("") + ".pdf";
  await env.BUCKET.put(keys.doc(project, file), bytes, {
    httpMetadata: { contentType: "application/pdf" },
  });

  // **Filed under the name the page has on the rail.** The deck page and the
  // shelf find a deck's PDF by the name of its section, so a print filed under
  // any other name is a print nobody can reach: the first server print went
  // under the record's name, "Bible", while the rail said "Visual Bible" and
  // pointed at a filing from 2026-09-05 whose file had never arrived — so the
  // Download button handed him a "no such picture" note (his report,
  // 2026-09-07). One row per deck: the row under this name, and any under the
  // record's own name from before, are replaced by this print.
  const front = await frontOf(env, project);
  const onRail = (front.sections || []).find((one) => one && one.slug === slug);
  const name = String((onRail && onRail.name) || record.name || slug).slice(0, 140);
  const mine = new Set([name, String(record.name || ""), slug].filter(Boolean));
  const replaced = (front.documents || []).filter((d) => d && d.kind === "lookbook" && mine.has(d.name));
  front.documents = (front.documents || [])
    .filter((d) => d && !(d.kind === "lookbook" && mine.has(d.name)))
    .concat({ name, kind: "lookbook", file, bytes: bytes.length, note: "" });
  front.updated = new Date().toISOString();
  await saveFront(env, project, front);

  // **The print this one replaces goes with its row.** 2026-09-15: every
  // reprint of the bible replaced the row and left the file — 27 prints,
  // 180 MB, that nothing could reach. A superseded print of the same deck
  // is not a picture a page might still be drawing (the case Ref 910 keeps
  // files for); it is the last edition of a book he can print again in
  // twenty seconds. Kept only if some other row still names it.
  const stillNamed = new Set((front.documents || []).map((d) => d && d.file).filter(Boolean));
  const retired = new Set([...replaced.map((d) => d.file), record.pdf].filter(Boolean));
  for (const old of retired) {
    if (old === file || stillNamed.has(old) || !/^[0-9a-f]{32}\.pdf$/.test(old)) continue;
    await env.BUCKET.delete(keys.doc(project, old)).catch(() => {});
  }

  // **Stamped on the record as it is now, not as it was read above.** A save
  // from the editor may have landed while Chrome was printing.
  const again = await env.BUCKET.get(keys.deck(project, slug));
  const latest = again ? JSON.parse(await again.text()) : record;
  latest.printed = new Date().toISOString();
  latest.pdf = file;
  await env.BUCKET.put(keys.deck(project, slug), JSON.stringify(latest), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  return { file, bytes: bytes.length, ms: Date.now() - began };
}
