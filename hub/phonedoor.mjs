#!/usr/bin/env node
/**
 * **The iPhone app's door into the portal** — Ref 1541 Stage C, 2026-10-06.
 * `GET /phone/<film>/…` on the hub (`phoneDoor` in src/worker.js):
 *
 * - shut without the token, and with a wrong one;
 * - the Library as he sees it: pages, decks, boards, documents, each with its
 *   shelf, pinned, private, archived and icon; a deck's printed PDF; the
 *   phone's own places marked `film`;
 * - a written page, a deck and a board, each naming the pictures it uses;
 * - a page kept only as designed HTML, handed down as blocks, never as HTML;
 * - a picture by name; nothing written, whatever is asked.
 *
 *     hub/phonedoor.mjs
 *
 * A throwaway bucket and a hub of its own on 8843. Nothing here touches a
 * real film or the real bucket.
 *
 * **For looking at it on the iPhone simulator**: `PHONEDOOR_SERVE=<a film's
 * folder in the bucket mirror>` also puts that film in the throwaway bucket,
 * under its own id (several: folders joined by `:`), and leaves the hub
 * running after the checks (Ctrl-C ends it). Launch the app with `-PortalURL http://127.0.0.1:8843 -PortalToken
 * checking-token-not-a-secret` (the second is read on a simulator only).
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, readFileSync, readdirSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const FILM = "0f0e0d0c0b0a00000000000000000543";
const PORT = Number(process.env.PHONEDOOR_PORT || 8843);
const H = `http://127.0.0.1:${PORT}`;
const TOKEN = "checking-token-not-a-secret";
const PIC = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg";
const PDF = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.pdf";
const BOARDPIC = "cccccccccccccccccccccccccccccccc.jpg";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

const state = mkdtempSync(join(tmpdir(), "phonedoor-"));
const w = join(HERE, "node_modules/.bin/wrangler");
function put(key, body) {
  const file = join(state, "put.bin");
  writeFileSync(file, Buffer.isBuffer(body) || typeof body === "string" ? body : JSON.stringify(body));
  spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
}
const free = (port) => spawnSync("sh", ["-c", `lsof -ti tcp:${port} -sTCP:LISTEN | xargs kill -9 2>/dev/null`]);

// ---- the film ---------------------------------------------------------------
put(`p/${FILM}/manifest.json`, { format: 1, project: FILM, title: "Door Check", engine: "0.1.0" });
put(`p/${FILM}/front.json`, {
  version: 1, linked: "link", updated: "2026-10-06T12:00:00Z",
  sections: [
    { slug: "bible", name: "Visual Bible", type: "page", source: "here" },
    { slug: "notes-day-2", name: "Day 2 Notes", type: "page", source: "here" },
    { slug: "lens-character", name: "Lens Character", type: "deck", source: "program", by: "deck" },
    { slug: "dump", name: "Dump Board", type: "board", source: "here", board: "dump-77434d", share: "me" },
    { slug: "old-page", name: "Old Page", type: "page", source: "here" },
    { slug: "outline", name: "Outline", type: "deck", source: "program", by: "deck" },
    { slug: "pd-requests", name: "Production Design Requests", type: "deck", source: "program", by: "deck" },
  ],
  documents: [
    { name: "Lens Character", kind: "lookbook", file: PDF, bytes: 2048, source: "here" },
    { name: "Deal Memo", kind: "document", file: "", url: "https://example.com/memo", source: "here" },
  ],
  library: [{ at: "notes-day-2", head: "" }],
  archive: [{ at: "old-page", head: "", wasPinned: true, wasPrivate: false }],
  shelf: { "notes-day-2": "Camera" },
  icons: { "lens-character": "camera" },
  crew: [], groups: [],
});
put(`p/${FILM}/visible.json`, { sections: ["notes-day-2", "old-page"], crew: [], documents: ["Deal Memo"] });
put(`p/${FILM}/pages/bible.json`, [{ t: "h1", r: [{ x: "Look" }], k: [] }, { t: "img", src: PIC, cap: "" }]);
put(`p/${FILM}/pages/notes-day-2.json`, [{ t: "p", r: [{ x: "Bring the slider." }], k: [] }]);
put(`p/${FILM}/pages/old-page.json`, [{ t: "p", r: [{ x: "Gone." }], k: [] }]);
put(`p/${FILM}/pages/lens-character.html`, "<html><body><h1>Lens Character</h1></body></html>");
// **A page the portal keeps only as designed HTML** (Halcyon's Outline, drawn
// by Doc Mirror): the phone gets it as blocks, never as HTML.
const CLIP = "abababababababababababababababab.mp4";
const STILL = "cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd.jpg";
put(`p/${FILM}/pages/outline.html`, `<style>.ol .init{display:none}.ol .grid{grid-template-columns:repeat(2,1fr)}
@media (max-width:600px){.ol .full{display:none}}</style>
<div class="ol"><header><p class="eyebrow">Door Check<span class="sl">//</span>outline</p>
<a class="docbtn" href="https://docs.google.com/document/d/x/edit">Open the Google Doc<span>↗</span></a>
<h2 class="title">Outline</h2><p class="sub"><span>Ivy’s draft</span><span>2 scenes</span></p></header>
<section><h3 class="label">Characters</h3><div class="castgrid">
<div class="person"><p class="pname">Gracie</p><p class="pbeside">GEMMA</p><p class="pcount">13 scenes</p></div>
<div class="person"><p class="pname">Wren</p><p class="pbeside">BECK</p><p class="pcount">2 scenes</p></div></div></section>
<section><h3 class="label">Scenes <span class="count">2</span></h3>
<table><thead><tr><th></th><th class="who"><span class="full">Gracie</span><span class="init">G</span></th><th class="who"><span class="full">Wren</span><span class="init">W</span></th></tr></thead>
<tbody><tr><td>01</td><td><i class="dot on"></i></td><td><i class="dot off"></i></td></tr></tbody></table>
<article class="scene"><div class="snum">01</div><div class="sbody"><h4 class="stitle">1. GRACIE GOES HUNTING</h4>
<div class="chips"><span class="chip">Gracie</span><span class="chip">Wren</span></div>
<p>Wrapped in bandages.<br>— with a gun</p><aside class="note"><p>Venison is <span class="q">“big”</span>.</p></aside></div></article></section>
<div class="grid"><figure><img src="pic/${PIC}" alt="not drawn"><figcaption>Master Prime 18mm</figcaption></figure><figure><img src="pic/${BOARDPIC}"><figcaption>Prominar 32mm</figcaption></figure></div>
<div class="reel"><iframe src="https://livid.com/embed/exampleClip1" title="Lens Tests"></iframe></div>
<video controls poster="pic/${STILL}" src="pic/${CLIP}"></video>
<p class="cap">The trailer. <a href="pic/${PDF}" download>Download</a> (2 KB)</p>
<script>document.write("never")</script>
<footer><p>1. Not a list.</p></footer></div>`);
// A page with a tree from Notion and a later published document: the portal
// draws the document, so the phone gets the document.
put(`p/${FILM}/pages/pd-requests.json`, [{ t: "p", r: [{ s: "The old tree." }] }]);
put(`p/${FILM}/pages/pd-requests.html`, `<div class="pd"><h1>Requests</h1><p>The document.</p></div>`);
put(`p/${FILM}/decks/lens-character.json`, { version: 1, name: "Lens Character", slug: "lens-character", sections: [{ id: "cover", on: true }], words: {}, pictures: { a1: { name: PIC, ar: 1.5 } } });
put(`p/${FILM}/boards/dump-77434d.json`, { v: 1, added: [{ id: "c1", kind: "image", src: BOARDPIC }], ties: [], lenses: [] });
put(`p/${FILM}/docs/${PIC}`, Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4]));
put(`p/${FILM}/docs/${PDF}`, "%PDF-1.4 checking");

// ---- a film that shoots twice: the record, native (2026-10-06) ---------------
const TWICE = "0f0e0d0c0b0a00000000000000000544";
const LUT = "dddddddddddddddddddddddddddddddd.cube";
const XML = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.xml";
const KEY = "ffffffffffffffffffffffffffffffff.jpg";
const sheet = (lenses) => ({ body: "Alexa Mini LF", lenses, format: "4.3K LF 16:9 UHD", capture: "", finishing: "",
  colour: "LogC3", codec: "ProRes 4444", fps: "23.976", desqueeze: "1.0", guides: "", luts: "Show LUT: show.cube" });
const mate = (name, department, extra = {}) => ({ name, role: "Gaffer", department, company: "", email: `${name.split(" ")[0].toLowerCase()}@example.com`, phone: "+1 555 0100", ...extra });
put(`p/${TWICE}/manifest.json`, { format: 1, project: TWICE, title: "Twice", engine: "0.1.0" });
put(`p/${TWICE}/front.json`, {
  version: 1, linked: "link", updated: "2026-10-06T12:00:00Z",
  status: "Active", type: "Commercial", length: "", director: "Ollie Brennan", producer: "",
  credits: [{ role: "Executive Producer", people: ["Dana Gross"] }],
  logline: "A cook and a camera.", ratio: 0.5625, key_image: KEY, shoot: { start: "2026-10-06", end: "" },
  camera: sheet("Angenieux — 45-165mm — T2.3"), camera_notes: 1,
  camera_files: [{ name: "show.cube", file: LUT, bytes: 900 }],
  days: [{ label: "Day 1", date: "2026-07-09" }, { label: "Day 2", date: "2026-10-06" }],
  crew: [mate("Victor Salinas", "G&E"), mate("Leo Navarro", "G&E", { role: "Key Grip" })],
  documents: [
    { name: "Call Sheet Day 2", kind: "document", file: PDF, bytes: 2048, source: "here", shoots: ["shoot-2"] },
    { name: "Insurance", kind: "document", url: "https://drive.google.com/file/d/x/view", source: "here" },
    { name: "Old Memo", kind: "document", url: "https://example.com/old", source: "here" },
  ],
  archive: [{ at: "doc:Old Memo", head: "" }],
  sections: [
    { slug: "shoot-1-details", name: "Shoot 1 Details", type: "page", source: "here" },
    { slug: "shoot-2-details", name: "Shoot 2 Details", type: "page", source: "here" },
  ],
  shoots: [
    { id: "", name: "Shoot 1", base: "Shoot 1", slug: "shoot-1", status: "Wrapped", start: "2026-07-09", end: "",
      changes: "First shoot.", camera: sheet("Signature Primes"), camera_notes: 1,
      camera_files: [{ name: "show.cube", file: LUT, bytes: 900 }],
      crew: [mate("Victor Salinas", "G&E"), mate("Peter Lund", "Camera", { role: "Loader" })] },
    { id: "", name: "Shoot 2", base: "Shoot 2", slug: "shoot-2", status: "Upcoming", start: "2026-10-06", end: "",
      changes: "A zoom instead of primes.", camera: sheet("Angenieux — 45-165mm — T2.3"), camera_notes: 1,
      camera_files: [{ name: "show.cube", file: LUT, bytes: 900 }],
      crew: [mate("Victor Salinas", "G&E"), mate("Leo Navarro", "G&E", { role: "Key Grip" })] },
  ],
  groups: [],
});
put(`p/${TWICE}/visible.json`, { sections: ["shoot-2-details"], crew: ["Leo Navarro"], documents: ["Insurance"] });
put(`p/${TWICE}/pages/camera-sheet.json`, [{ t: "h2", r: [{ s: "Shoot 2 Settings" }] }, { t: "file", name: "frames.xml", src: XML, bytes: 30 }]);
put(`p/${TWICE}/pages/camera-sheet-shoot-1.json`, [{ t: "h2", r: [{ s: "Shoot 1 Settings" }] }]);
put(`p/${TWICE}/pages/shoot-2-details.json`, [{ t: "p", r: [{ s: "Two new episodes." }] }]);
put(`p/${TWICE}/pages/camera-tests.html`, `<div><h1>Tests</h1><img src="pic/${PIC}"></div>`);

// ---- a real film from the mirror, for the simulator --------------------------
// Several films: their folders joined by `:`.
const serve = process.env.PHONEDOOR_SERVE || "";
for (const one of serve.split(":").filter(Boolean)) seed(one);
function seed(serve) {
  const id = basename(serve);
  say(`Putting ${id} from the mirror in the throwaway bucket…`);
  // `portal.json`: a film with a portal and no film of its own (Halcyon).
  for (const name of ["manifest.json", "front.json", "visible.json", "people.json", "portal.json"]) {
    if (existsSync(join(serve, name))) put(`p/${id}/${name}`, readFileSync(join(serve, name)));
  }
  const used = new Set();
  // **The film's change logs too**, so a page that draws the film (a look
  // board's shots) has one to draw.
  if (existsSync(join(serve, "logs"))) {
    for (const name of readdirSync(join(serve, "logs"))) if (name.endsWith(".log")) put(`p/${id}/logs/${name}`, readFileSync(join(serve, "logs", name)));
  }
  for (const folder of ["pages", "decks", "boards"]) {
    if (!existsSync(join(serve, folder))) continue;
    for (const name of readdirSync(join(serve, folder))) {
      if (!/\.(json|html)$/.test(name)) continue;
      const text = readFileSync(join(serve, folder, name));
      put(`p/${id}/${folder}/${name}`, text);
      for (const m of text.toString().match(/\b[0-9a-f]{32}\.[A-Za-z0-9]{1,8}\b/g) || []) used.add(m);
    }
  }
  const front = JSON.parse(readFileSync(join(serve, "front.json")));
  for (const d of front.documents || []) if (d.file) used.add(d.file);
  // The record's own: camera files on every shoot's sheet, the key image and
  // the pictures the front page may lead with.
  for (const f of [...(front.camera_files || []), ...(front.shoots || []).flatMap((one) => one.camera_files || [])]) if (f.file) used.add(f.file);
  if (front.key_image) used.add(front.key_image);
  for (const list of Object.values(front.pictures || {})) for (const name of list || []) used.add(name);
  for (const name of used) {
    for (const folder of ["docs", "media"]) {
      if (existsSync(join(serve, folder, name))) { put(`p/${id}/${folder}/${name}`, readFileSync(join(serve, folder, name))); break; }
    }
  }
  say(`  ${used.size} pictures and files`);
}

free(PORT);
const hub = spawn(w, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`,
  "--var", "COMMIT:checking-commit", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });
const stop = () => {
  try { hub.kill("SIGTERM"); } catch {}
  spawnSync("pkill", ["-f", `wrangler.*dev --local --port ${PORT}`]);
  free(PORT);
  rmSync(state, { recursive: true, force: true });
};

const ask = (path, token = TOKEN, init = {}) => fetch(`${H}${path}`, {
  ...init, headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(init.headers || {}) },
});

try {
  let up = false;
  for (let i = 0; i < 80 && !up; i++) {
    try { up = (await fetch(`${H}/version`)).ok; } catch {}
    if (!up) await wait(500);
  }
  if (!up) throw new Error("the hub would not start");

  say("\nThe door is shut to anyone without the token");
  let r = await ask(`/phone/${FILM}/library`, "");
  check("no token: refused", r.status === 401, r.status);
  r = await ask(`/phone/${FILM}/library`, "wrong-token-of-the-same-length!");
  check("a wrong token: refused", r.status === 401, r.status);
  r = await ask(`/phone/${FILM}/pic/${PIC}`, "nope");
  check("…pictures too", r.status === 401, r.status);
  r = await ask(`/phone/${FILM}/library`, TOKEN, { method: "POST", body: "{}" });
  check("it writes nothing: a POST is refused", r.status === 405, r.status);
  r = await ask(`/phone/ffffffffffffffffffffffffffffffff/library`);
  check("a film that is not there: 404", r.status === 404, r.status);

  say("\nThe Library, as he sees it");
  r = await ask(`/phone/${FILM}/library`);
  const lib = r.ok ? await r.json() : {};
  check("answers with the token", r.status === 200, r.status);
  const item = (k) => (lib.items || []).find((x) => x.key === k) || {};
  check("four shelves, the portal's order", (lib.shelves || []).join("|") === "Creative|Technical|Logistical|Other", lib.shelves);
  check("the portal's address for the film", lib.portal === `https://your-domain.example/f/${FILM}`, lib.portal);
  check("the Visual Bible: built in, Creative, its page tree", item("bible").kind === "built" && item("bible").shelf === "Creative" && item("bible").tree === true, JSON.stringify(item("bible")));
  const notes = item("notes-day-2");
  check("a page: moved to Technical, off the sidebar, Private", notes.kind === "page" && notes.shelf === "Technical" && notes.pinned === false && notes.private === true, JSON.stringify(notes));
  const deck = item("lens-character");
  check("a deck: Creative, his icon, its web page and content", deck.kind === "deck" && deck.shelf === "Creative" && deck.icon === "camera" && deck.html && deck.deck, JSON.stringify(deck));
  check("…and its printed PDF", deck.pdf && deck.pdf.file === PDF, JSON.stringify(deck.pdf));
  const board = item("dump");
  check("a board only he can open: Private, Creative", board.kind === "board" && board.private === true && board.shelf === "Creative" && board.share === "me", JSON.stringify(board));
  check("an archived page is listed, marked archived", item("old-page").archived === true, JSON.stringify(item("old-page")));
  const pdf = item("doc:Lens Character");
  check("a document file: its file, size and kind", pdf.kind === "file" && pdf.file === PDF && pdf.ext === "pdf" && pdf.bytes === 2048, JSON.stringify(pdf));
  const memo = item("doc:Deal Memo");
  check("a link: Logistical, Private, its address", memo.kind === "link" && memo.shelf === "Logistical" && memo.private === true && memo.url === "https://example.com/memo", JSON.stringify(memo));
  check("pages with something to fetch carry a time", Boolean(item("bible").stamp && deck.stamp), `${item("bible").stamp} ${deck.stamp}`);

  say("\nPages, decks and boards");
  r = await ask(`/phone/${FILM}/page/bible`);
  let got = r.ok ? await r.json() : {};
  check("a written page: its tree and the pictures it uses", Array.isArray(got.tree) && got.tree[0].t === "h1" && (got.pictures || []).includes(PIC), JSON.stringify(got).slice(0, 200));
  r = await ask(`/phone/${FILM}/page/lens-character`);
  got = r.ok ? await r.json() : {};
  check("a deck's web page with no tree: its words as blocks", got.html === true && got.from === "html" && JSON.stringify(got.tree) === JSON.stringify([{ t: "h1", r: [{ s: "Lens Character" }] }]), JSON.stringify(got));
  r = await ask(`/phone/${FILM}/deck/lens-character`);
  got = r.ok ? await r.json() : {};
  check("a deck: its content and its pictures", got.deck && got.deck.slug === "lens-character" && (got.pictures || []).includes(PIC), JSON.stringify(got).slice(0, 200));
  r = await ask(`/phone/${FILM}/board/dump`);
  got = r.ok ? await r.json() : {};
  check("a board: its cards and their pictures", got.board && (got.board.added || []).length === 1 && (got.pictures || []).includes(BOARDPIC), JSON.stringify(got).slice(0, 200));
  r = await ask(`/phone/${FILM}/page/nothing-here`);
  check("a page that is not there: 404", r.status === 404, r.status);
  r = await ask(`/phone/${FILM}/page/..%2Ffront`);
  check("a slug that is not a slug: refused", r.status === 404 || r.status === 400, r.status);

  say("\nPictures");
  r = await ask(`/phone/${FILM}/pic/${PIC}`);
  const bytes = r.ok ? new Uint8Array(await r.arrayBuffer()) : new Uint8Array();
  check("a picture by name, its bytes", r.status === 200 && bytes[0] === 0xff && bytes.length === 8, `${r.status} ${bytes.length}`);
  r = await ask(`/phone/${FILM}/pic/${PDF}`);
  check("the deck's PDF, by the same door", r.status === 200 && (await r.text()).startsWith("%PDF"), r.status);
  r = await ask(`/phone/${FILM}/pic/../front.json`);
  check("anything that is not a stored file: refused", r.status >= 400, r.status);

  say("\nThe film's record, native (a film that shoots twice)");
  r = await ask(`/phone/${TWICE}/front`, "");
  check("the record: shut without the token", r.status === 401, r.status);
  r = await ask(`/phone/${TWICE}/front`);
  const rec = r.ok ? await r.json() : {};
  check("the record answers with the token", r.status === 200, r.status);
  const film = rec.film || {};
  check("the front page: credits as the portal says them", (film.credits || []).map((c) => `${c.role} ${c.people}`).join("|") === "Directed by Ollie Brennan|Executive Producer Dana Gross", JSON.stringify(film.credits));
  check("…its facts line and logline", (film.facts || [])[0] === "Active" && (film.facts || []).includes("0.56 : 1") && film.logline === "A cook and a camera.", JSON.stringify(film.facts));
  check("…its key image as the cover", film.cover === KEY && (rec.pictures || []).includes(KEY), film.cover);
  check("two shoots, oldest first, the next one marked", (rec.shoots || []).map((s) => `${s.slug}:${s.word}`).join(",") === "shoot-1:Wrapped,shoot-2:Next", JSON.stringify(rec.shoots));
  check("…each with its date and what it changes", (rec.shoots || [])[1] && rec.shoots[1].dates === "Oct 6" && rec.shoots[1].changes === "A zoom instead of primes.", JSON.stringify(rec.shoots && rec.shoots[1]));
  const view = (slug) => (rec.views || []).find((v) => v.shoot === slug) || {};
  const one = view("shoot-1"), two = view("shoot-2");
  check("a tab per shoot", (rec.views || []).length === 2 && one.shoot && two.shoot, (rec.views || []).map((v) => v.shoot));
  const lensesOf = (v) => (v.camera && v.camera.lenses) || {};
  check("Shoot 1's sheet: its own lenses, as a set", (lensesOf(one).sets || [])[0] && lensesOf(one).sets[0].series === "Signature Primes", JSON.stringify(lensesOf(one)));
  check("Shoot 2's lenses: the zoom, its stop, marked changed", lensesOf(two).sets[0].stop === "T2.3" && lensesOf(two).changed === true && lensesOf(two).was === "Signature Primes", JSON.stringify(lensesOf(two)));
  const rowOf = (v, label) => ((v.camera || {}).rows || []).find((x) => x.label === label) || {};
  check("a sheet row: its label and value, in the sheet's order", rowOf(two, "Camera").lines[0].value === "Alexa Mini LF" && two.camera.rows[0].label === "Camera", JSON.stringify(two.camera && two.camera.rows[0]));
  check("…an unchanged row is not marked", !rowOf(two, "Codec").changed, JSON.stringify(rowOf(two, "Codec")));
  check("a LUT with the label he gave it", ((two.camera || {}).files || [])[0] && two.camera.files[0].label === "Show LUT" && two.camera.files[0].file === LUT, JSON.stringify(two.camera && two.camera.files));
  check("each shoot's notes page: its own", JSON.stringify(one.camera.notes).includes("Shoot 1 Settings") && JSON.stringify(two.camera.notes).includes("Shoot 2 Settings"), JSON.stringify([one.camera.notes, two.camera.notes]));
  check("…and the files the notes name are fetched with it", (rec.pictures || []).includes(XML) && rec.pictures.includes(LUT), JSON.stringify(rec.pictures));
  const names = (v) => (v.crew || []).flatMap((d) => d.people.map((p) => p.name));
  check("People per shoot, by department", names(one).includes("Peter Lund") && !names(two).includes("Peter Lund") && two.crew[0].department === "G&E", JSON.stringify(two.crew));
  const kevin = (two.crew || []).flatMap((d) => d.people).find((p) => p.name === "Leo Navarro") || {};
  check("…a Private one is his to see, with contacts, marked new", kevin.email && kevin.phone && kevin.fresh === true, JSON.stringify(kevin));
  const docs = (v) => (v.documents || []).map((d) => d.name);
  check("Documents per shoot: tagged ones on theirs only", docs(two).includes("Call Sheet Day 2") && !docs(one).includes("Call Sheet Day 2"), JSON.stringify([docs(one), docs(two)]));
  check("…untagged on both, archived on neither, Private kept", docs(one).includes("Insurance") && !docs(one).includes("Old Memo"), JSON.stringify(docs(one)));
  const call = (two.documents || []).find((d) => d.name === "Call Sheet Day 2") || {};
  check("…a file says its kind and size, a link its host", call.ext === "pdf" && call.bytes === 2048 && (two.documents || []).find((d) => d.name === "Insurance").host === "drive.google.com", JSON.stringify(two.documents));
  check("each shoot's own pages", (two.pages || []).map((p) => p.name).join() === "Shoot 2 Details" && (one.pages || []).map((p) => p.name).join() === "Shoot 1 Details", JSON.stringify([one.pages, two.pages]));
  check("each shoot's days", (one.days || []).map((d) => d.date).join() === "2026-07-09" && (two.days || []).map((d) => d.date).join() === "2026-10-06", JSON.stringify([one.days, two.days]));
  r = await ask(`/phone/${FILM}/front`);
  got = r.ok ? await r.json() : {};
  check("a film that shoots once: one tab, no shoots", r.status === 200 && (got.shoots || []).length === 0 && (got.views || []).length === 1 && got.views[0].shoot === "", JSON.stringify(got).slice(0, 160));

  say("\nA page kept only as designed HTML: blocks, never HTML");
  const outline = item("outline");
  check("in the Library: a page to draw (tree), published (html)", outline.tree === true && outline.html === true && !outline.deck && outline.stamp > 0, JSON.stringify(outline));
  r = await ask(`/phone/${FILM}/page/outline`);
  got = r.ok ? await r.json() : {};
  const tree = got.tree || [];
  const all = JSON.stringify(tree);
  const runs = (b) => (b.r || []).map((x) => x.s).join("");
  const find = (test) => { let hit = null; (function look(ns) { for (const n of ns || []) { if (!hit && test(n)) hit = n; look(n.k); } })(tree); return hit; };
  check("answers with blocks, said to come from the document", r.status === 200 && got.from === "html" && got.html === true && tree.length > 5, JSON.stringify(got).slice(0, 200));
  check("…not one tag, and nothing dropped", !/[<>]/.test(all) && !got.dropped, (all.match(/.{0,40}[<>].{0,40}/) || [""])[0] + JSON.stringify(got.dropped || []));
  check("…a script is not words", !all.includes("never"), all.slice(0, 120));
  check("the page's own name is not said twice", !find((b) => /^h/.test(b.t) && runs(b) === "Outline"), all.slice(0, 300));
  check("headings by rank: a section, a scene", find((b) => b.t === "h2" && runs(b) === "Characters") && find((b) => b.t === "h2" && runs(b) === "Scenes 2"), all.slice(0, 400));
  check("a scene's number leads its heading", Boolean(find((b) => b.t === "h3" && runs(b) === "01 · 1. GRACIE GOES HUNTING")), all.slice(0, 600));
  check("a link keeps its address", Boolean(find((b) => (b.r || []).some((x) => x.u === "https://docs.google.com/document/d/x/edit" && x.s === "Open the Google Doc↗"))), all.slice(0, 300));
  check("parts side by side are joined with a dot", Boolean(find((b) => runs(b) === "Ivy’s draft · 2 scenes")) && Boolean(find((b) => runs(b) === "Gracie · Wren")), all.slice(0, 600));
  check("a grid of cards is a list, a card a line", Boolean(find((b) => b.t === "li" && runs(b) === "Gracie · GEMMA · 13 scenes")) && Boolean(find((b) => b.t === "li" && runs(b) === "Wren · BECK · 2 scenes")), all.slice(0, 700));
  const table = find((b) => b.t === "table") || { k: [] };
  const cell = (row, col) => ((table.k[row] || {}).c || [])[col] || [];
  check("a table: its heading row, what it hides left out", table.head === true && cell(0, 1).map((x) => x.s).join("") === "Gracie" && !all.includes("\"G\""), JSON.stringify(table));
  check("…a mark switched on is ●, off is empty", cell(1, 1).map((x) => x.s).join("") === "●" && cell(1, 2).length === 0, JSON.stringify(table.k[1]));
  check("a line break is a new line, nothing lost", Boolean(find((b) => runs(b) === "Wrapped in bandages.")) && Boolean(find((b) => runs(b) === "— with a gun")), all.slice(0, 900));
  check("a note set apart is a quotation", Boolean(find((b) => b.t === "quote" && runs(b) === "Venison is “big”.")), all.slice(0, 900));
  const cols = find((b) => b.t === "columns") || { k: [] };
  check("a row of pictures, its captions what the page shows", cols.k.length === 2 && cols.k[0].k[0].src === PIC && cols.k[0].k[0].cap === "Master Prime 18mm" && cols.k[1].k[0].cap === "Prominar 32mm", JSON.stringify(cols));
  check("a player's clip, with its title", Boolean(find((b) => b.t === "video" && b.url === "https://livid.com/embed/exampleClip1" && b.cap === "Lens Tests")), all);
  check("a stored clip with its still", Boolean(find((b) => b.t === "video" && b.src === CLIP && b.poster === STILL)), all);
  check("a link to a stored file is its card", Boolean(find((b) => b.t === "file" && b.src === PDF)) && Boolean(find((b) => runs(b) === "The trailer.")) && Boolean(find((b) => runs(b) === "(2 KB)")), all);
  check("words that look like a list stay words", Boolean(find((b) => b.t === "p" && runs(b) === "1. Not a list.")), all.slice(-300));
  check("the pictures it uses, to be fetched with it", [PIC, BOARDPIC, CLIP, STILL, PDF].every((n) => (got.pictures || []).includes(n)), JSON.stringify(got.pictures));
  r = await ask(`/phone/${FILM}/page/pd-requests`);
  got = r.ok ? await r.json() : {};
  check("a tree and a later document: the document, as the portal draws it", JSON.stringify(got.tree || []).includes("The document.") && !JSON.stringify(got.tree || []).includes("The old tree."), JSON.stringify(got));
  r = await ask(`/phone/${TWICE}/page/camera-tests`);
  got = r.ok ? await r.json() : {};
  check("a hand-made page with no row: its blocks", (got.tree || [])[0] && got.tree[0].t === "h1" && (got.pictures || []).includes(PIC), JSON.stringify(got).slice(0, 160));
  r = await ask(`/phone/${TWICE}/html/camera-tests`);
  check("there is no door that hands down HTML", r.status === 404, r.status);

  say("\nThe portal's own pages, inside the app (his trial, 2026-10-08)");
  r = await ask(`/phone/web/f/${FILM}/bible`, "");
  check("no token: refused", r.status === 401, r.status);
  r = await ask(`/phone/web/f/${FILM}/bible`, "wrong-token-of-the-same-length!");
  check("a wrong token: refused", r.status === 401, r.status);
  r = await ask(`/phone/web/f/${FILM}/bible`, TOKEN, { method: "POST", body: "{}" });
  check("reading only: a POST is refused", r.status === 405, r.status);
  r = await ask(`/phone/web/f/${FILM}/bible`);
  let said = r.ok ? await r.text() : "";
  check("a written page, as the portal draws it", r.status === 200 && said.includes("<html") && said.includes("Look"), `${r.status} ${said.slice(0, 120)}`);
  check("…marked for the app, with its stylesheet", said.includes('class="inapp"') && said.includes("/inapp.css"), said.slice(0, 300));
  r = await ask(`/phone/web/f/${FILM}/notes-day-2`);
  said = r.ok ? await r.text() : "";
  check("a Private page: his to see", r.status === 200 && said.includes("Day 2 Notes"), r.status);
  r = await ask(`/phone/web/f/${FILM}/pic/${PIC}`);
  check("its pictures come the same way", r.status === 200 && (await r.arrayBuffer()).byteLength === 8, r.status);
  r = await ask(`/phone/web/inapp.css`);
  check("the app's stylesheet", r.status === 200 && (await r.text()).includes(".inapp"), r.status);
  r = await ask(`/phone/web/hub.css`);
  check("the portal's own stylesheet", r.status === 200, r.status);

  say(`\n${pass} passed, ${fail} failed`);
  if (serve && !fail) {
    say(`\nThe hub stays up on ${H} for the simulator. Ctrl-C ends it.`);
    process.on("SIGINT", () => { stop(); process.exit(0); });
    process.on("SIGTERM", () => { stop(); process.exit(0); });
    await new Promise(() => {});
  }
} catch (error) {
  say(`\n${error.message}`);
  fail += 1;
} finally {
  if (!serve || fail) stop();
}
process.exit(fail ? 1 : 0);
