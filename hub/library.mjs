#!/usr/bin/env node
/**
 * The Library, driven in a real browser: his Pages list (2026-10-11, the
 * approved layout) and a reader's shelves of covers.
 *
 * `checks.sh` asks the worker questions over curl, which cannot press a
 * button. This puts a small film in a throwaway local bucket, starts the hub,
 * opens the Library in headless Chromium and does what a person does: searches,
 * filters to Hidden, opens a category, flips a page's switch, moves, renames
 * and archives a page, adds and removes a category, sets a crew member's
 * Contact — and, as a reader, checks the shelves and covers did not change.
 * Run it with `node hub/library.mjs`; `SHOTS=<dir>` also writes a picture of
 * each state there.
 *
 * Local only: it never touches the real bucket, and the identity it uses
 * cannot work anywhere but localhost.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL = `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const PORT = 8795, DEBUG = 9351;
const WHO = "owner@example.com";
const READER = "reader@example.com";
const SHOTS = process.env.SHOTS || "";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(60)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(60)} FAIL — ${why}`); };
const check = (what, cond, why = "not so") => (cond ? ok(what) : no(what, why));

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

const FRONT = {
  version: 1, logline: "x",
  sections: [
    { slug: "lighting-plan", name: "Lighting Plan", by: "mcp", type: "page", source: "here" },
    { slug: "safety-briefing", name: "Safety Briefing", by: "mcp", type: "page", source: "here" },
    { slug: "pitch-deck", name: "Pitch Deck", by: "deck", type: "deck", source: "program" },
    { slug: "night-look", name: "Night Look", by: "mcp", type: "page", source: "here" },
    { slug: "wrap-notes", name: "Wrap Notes", by: "mcp", type: "page", source: "here" },
    { slug: "dump-board", name: "Dump Board", by: "mcp", type: "board", source: "here", share: "me" },
    ...["Rain Plan", "Parking Notes", "Lunch Orders", "Reel Notes", "Festival Plan", "Press Kit", "Poster Ideas", "Thank You List", "Music Cues", "Sound Notes"]
      .map((name) => ({ slug: name.toLowerCase().replace(/ /g, "-"), name, by: "mcp", type: "page", source: "here" })),
  ],
  documents: [
    { name: "Deal memo", url: "https://drive.google.com/x", kind: "document" },
    { name: "Call sheet day 1", url: "https://docs.google.com/y", kind: "document" },
    { name: "Lens chart", file: "0123456789abcdef0123456789abcdef.pdf", bytes: 2202009, kind: "document" },
  ],
  crew: [{ name: "Ellis Ward", role: "Gaffer" }],
  groups: [{ name: "Creative", rows: ["night-look", "lighting-plan"] }, { name: "Logistics", rows: ["safety-briefing", "people", "documents"] }],
};

const state = mkdtempSync(join(tmpdir(), "library-state-"));
const box = mkdtempSync(join(tmpdir(), "library-box-"));
const wr = join(HERE, "node_modules/.bin/wrangler");
const put = (key, body) => {
  const file = join(box, "f.bin");
  writeFileSync(file, body);
  spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
say("Putting a small film in a local bucket…");
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
put(`p/${FILM}/front.json`, JSON.stringify(FRONT));
put(`p/${FILM}/people.json`, JSON.stringify({ people: [{ email: READER, role: "viewer" }], links: [] }));
for (const p of FRONT.sections) put(`p/${FILM}/pages/${p.slug}.json`, JSON.stringify([{ t: "p", r: [{ s: `Words for ${p.name}.` }] }]));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:",
  "--var", "COMMIT:library-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

let proc = null;
const finish = (code) => {
  try { proc && proc.kill("SIGKILL"); } catch { /* gone */ }
  try { hub.kill("SIGTERM"); } catch { /* gone */ }
  spawnSync("bash", ["-c", `sleep 1; lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -9 -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
  process.exit(code);
};

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch { /* not yet */ }
  }
  if (!up) { say("the hub would not start"); finish(1); }

  proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1280,900", "about:blank"], { stdio: "ignore" });
  let targets = null;
  for (let i = 0; i < 80 && !targets; i++) {
    await wait(150);
    try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch { /* not yet */ }
  }
  if (!targets) throw new Error("the browser never answered");
  const target = targets.find((t) => t.type === "page");
  const ws = new WS(target.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
  await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
  let id = 0;
  const waiting = new Map();
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
  });
  const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
  await ask("Page.enable");
  await ask("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });
  const js = async (e) => (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
  const open = async (path, who = WHO) => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/${path}?as=${who}` });
    await wait(1800);
  };
  const shot = async (name) => {
    if (!SHOTS) return;
    mkdirSync(SHOTS, { recursive: true });
    const r = await ask("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.result.data, "base64"));
  };
  const right = (sel) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return false;
    const r = el.getBoundingClientRect();
    return el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: r.left + 30, clientY: r.top + 20 })); })()`);
  const click = (sel, mods = {}) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return false;
    return el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, ...${JSON.stringify(mods)} })); })()`);
  const link = (key) => `.fh-card[data-key="${key}"] .fh-cardlink`;
  const menuWords = () => js(`[...document.querySelectorAll('.ctxmenu:not(.ctxsub) > .ctxitem, .ctxmenu:not(.ctxsub) > .ctxwrap > .ctxitem')].map(b => b.textContent)`);

  const words = () => js(`[...document.querySelectorAll('.ctxmenu:not(.ctxsub) > .ctxitem, .ctxmenu:not(.ctxsub) > .ctxwrap > .ctxitem')].map(b => b.textContent)`);
  const row = (key) => `.fh-lrow[data-key="${key}"]`;
  const catOf = (key) => js(`(document.querySelector('${row(key)}') || {}).closest?.('.fh-lcat')?.id || ''`);
  const type = (text) => ask("Input.insertText", { text });
  const key = (k) => ask("Input.dispatchKeyEvent", { type: "keyDown", key: k }).then(() => ask("Input.dispatchKeyEvent", { type: "keyUp", key: k }));
  const find = (text) => js(`(() => { const i = document.querySelector('[data-lfind]'); i.value = ${JSON.stringify(text)}; i.dispatchEvent(new Event('input', { bubbles: true })); })()`);
  const openMenu = (sel) => js(`document.querySelector(${JSON.stringify(sel)}).click()`);
  const pick = (label) => js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === ${JSON.stringify(label)}).click()`);

  say("Pages: the Library for whoever runs the film");
  await open("library");
  const total = await js(`document.querySelectorAll('.fh-lcats .fh-lrow').length`);
  check("one row per page and document, in categories", total >= 20, String(total));
  check("the search says how many pages it looks through", (await js(`document.querySelector('[data-lfind]').placeholder`)) === `Search ${total} pages`, await js(`document.querySelector('[data-lfind]').placeholder`));
  check("All and Hidden, and how many are shown", (await js(`[...document.querySelectorAll('[data-lfilter]')].map(b => b.textContent).join()`)) === "All,Hidden"
    && /^\d+ of \d+ shown$/.test(await js(`document.querySelector('[data-lcount]').textContent`)), await js(`document.querySelector('[data-lcount]').textContent`));
  check("New Page and New Category at the top", (await js(`[...document.querySelectorAll('.fh-lbtn')].map(b => b.textContent.trim()).join()`)) === "New Page,New Category");
  const opened = await js(`[...document.querySelectorAll('.fh-lcats .fh-lfold')].map(d => d.open)`);
  check("categories are folded, but for the first with pages in it", opened.filter(Boolean).length === 1 && opened[0] === true, JSON.stringify(opened));
  check("no Pinned, Private, Icon or covers here", (await js(`!document.querySelector('.fh-lpane .seenon, .fh-lpane .fh-cv, .fh-lpane .fh-card') && !/Pinned|Private/.test(document.querySelector('.fh-lpane').textContent)`)) === true);
  check("each row has one switch, and its ⋯", (await js(`[...document.querySelectorAll('.fh-lcats .fh-lrow')].every(r => r.querySelectorAll('[role=switch]').length === 1 && r.querySelector('.fh-lmenu'))`)) === true);
  const typed = await js(`(() => { const t = (k) => { const r = document.querySelector('.fh-lrow[data-key="' + k + '"]'); return r && [r.dataset.kind, r.querySelector('.fh-lchip').textContent, !!r.querySelector('.fh-lico svg')].join(); }; return ['pitch-deck', 'night-look', 'dump-board', 'shotlist', 'doc:Deal memo'].map(t).join('|'); })()`);
  check("a row's first chip names its type, and its icon is tinted to match", typed === "deck,Deck,true|page,Page,true|board,Board,true|built,Built In,true|link,Link,true", typed);
  check("chips say what a page is", (await js(`document.querySelector('${row("pitch-deck")} .fh-lchip').textContent`)) === "Deck"
    && (await js(`[...document.querySelectorAll('${row("shotlist")} .fh-lchip')].map(c => c.textContent).includes('Built In')`)) === true);
  const notes = await js(`document.querySelector('#shelf-other')`) !== null;
  await js(`document.querySelector('#shelf-other .fh-lfold').open = true`);
  const eight = await js(`(() => { const c = document.querySelector('#shelf-other'); const m = c.querySelector('.fh-lmore'); return [...c.querySelectorAll('.fh-lrow')].filter(r => getComputedStyle(r).display !== 'none').length + '|' + (m ? m.textContent : ''); })()`);
  check("a category holds eight, then Show All", notes && /^8\|Show All \d+$/.test(eight), eight);
  await shot("1-pages");
  await js(`document.querySelector('#shelf-other .fh-lmore').click()`);
  check("…and Show All shows them all", (await js(`[...document.querySelectorAll('#shelf-other .fh-lrow')].every(r => getComputedStyle(r).display !== 'none')`)) === true);

  say("Search and Hidden");
  await open("library");
  await find("wrap");
  check("a search opens the category with a match, and says how many it found", (await js(`(() => { const c = document.querySelector('${row("wrap-notes")}').closest('.fh-lcat'); return c.querySelector('.fh-lfold').open && c.querySelector('.fh-lct').textContent === '1 found'; })()`)) === true);
  check("…and hides every category without one", (await js(`[...document.querySelectorAll('.fh-lcats .fh-lcat')].filter(c => !c.hidden).length`)) === 1);
  await shot("2-search");
  await find("zzzz");
  check("nothing found says so", (await js(`!document.querySelector('[data-lnomatch]').hidden`)) === true);
  await find("");
  check("clearing it puts the categories back as they were", (await js(`[...document.querySelectorAll('.fh-lcats .fh-lfold')].filter(d => d.open).length`)) === 1);
  await js(`document.querySelector('[data-lfilter="hidden"]').click()`);
  check("Hidden shows only what viewers do not see", (await js(`[...document.querySelectorAll('.fh-lcats .fh-lrow')].filter(r => !r.hidden).map(r => r.dataset.key).join()`)) === "dump-board");
  await shot("3-hidden");
  await js(`document.querySelector('[data-lfilter="all"]').click()`);

  say("The switch: shown to viewers");
  await find("night");
  const sw = `${row("night-look")} .fh-lsw`;
  check("a page starts shown", (await js(`document.querySelector('${sw}').getAttribute('aria-checked')`)) === "true");
  await js(`document.querySelector('${sw}').click()`);
  await wait(900);
  check("one press turns it off, and the row dims", (await js(`document.querySelector('${sw}').getAttribute('aria-checked')`)) === "false"
    && (await js(`document.querySelector('${row("night-look")}').classList.contains('fh-loff')`)) === true);
  await open("library");
  check("…and it is saved", (await js(`document.querySelector('${sw}').getAttribute('aria-checked')`)) === "false");
  const viewerSees = await js(`fetch('/f/${FILM}/night-look?as=${READER}').then(r => r.status)`);
  check("…so a viewer cannot open it", viewerSees !== 200, String(viewerSees));
  await js(`document.querySelector('${sw}').click()`);
  await wait(900);
  check("pressing again shows it", (await js(`fetch('/f/${FILM}/night-look?as=${READER}').then(r => r.status)`)) === 200);

  say("A row's ⋯");
  await open("library");
  await find("lighting");
  await openMenu(`${row("lighting-plan")} .fh-lmenu > summary`);
  check("a page he made: Rename, Remove from Sidebar, Move To, Archive", JSON.stringify(await words()) === JSON.stringify(["Rename", "Remove from Sidebar", "Move To", "Archive"]), JSON.stringify(await words()));
  await shot("4-row-menu");
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  await find("shot list");
  await openMenu(`${row("shotlist")} .fh-lmenu > summary`);
  check("a Built In page: Remove from Sidebar, Move To and Archive", JSON.stringify(await words()) === JSON.stringify(["Remove from Sidebar", "Move To", "Archive"]), JSON.stringify(await words()));
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  await find("lighting");
  await openMenu(`${row("lighting-plan")} .fh-lmenu > summary`);
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Move To').click()`);
  await pick("Creative");
  await wait(1200);
  check("Move To moves the row at once", (await catOf("lighting-plan")) === "shelf-creative", await catOf("lighting-plan"));
  await open("library");
  check("…and it is saved", (await catOf("lighting-plan")) === "shelf-creative", await catOf("lighting-plan"));
  await find("lighting");
  await openMenu(`${row("lighting-plan")} .fh-lmenu > summary`);
  await pick("Rename");
  await wait(200);
  check("Rename puts a box where the name is", (await js(`!!document.querySelector('${row("lighting-plan")} .fh-ledit')`)) === true);
  await js(`document.querySelector('.fh-ledit').select()`);
  await type("Lighting Notes");
  await key("Enter");
  await wait(1200);
  check("…and Enter renames it, at its new address", (await js(`document.querySelector('${row("lighting-notes")} .fh-lname').textContent`)) === "Lighting Notes");
  await openMenu(`${row("lighting-notes")} .fh-lmenu > summary`);
  await pick("Archive");
  await wait(2500);
  check("Archive puts it in the Archive, folded at the foot", (await catOf("lighting-notes")) === "shelf-archive" && (await js(`!document.querySelector('#shelf-archive .fh-lfold').open`)) === true, await catOf("lighting-notes"));
  check("…off the sidebar", (await js(`!document.querySelector('nav.rail .to[data-key="lighting-notes"]')`)) === true);
  await js(`document.querySelector('#shelf-archive .fh-lfold').open = true`);
  await openMenu(`${row("lighting-notes")} .fh-lmenu > summary`);
  check("…with Unarchive in its menu", (await words()).includes("Unarchive"), JSON.stringify(await words()));
  await pick("Unarchive");
  await wait(2500);
  check("…which brings it back", (await catOf("lighting-notes")) === "shelf-creative", await catOf("lighting-notes"));

  say("Categories");
  await open("library");
  await openMenu(`#shelf-creative .fh-lcatmenu > summary`);
  check("a starting category's ⋯ has Rename only", JSON.stringify(await words()) === JSON.stringify(["Rename"]), JSON.stringify(await words()));
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  await js(`document.querySelector('.fh-laddcat').open = true`);
  await js(`document.querySelector('.fh-laddcat input[name=name]').value = 'Wrap'`);
  await js(`document.querySelector('.fh-laddcat form').requestSubmit()`);
  await wait(2500);
  const added = await js(`[...document.querySelectorAll('.fh-lcats .fh-lcat')].map(c => c.dataset.shelfname)`);
  check("Add Category adds one, last", added[added.length - 1] === "Wrap", JSON.stringify(added));
  const wrapId = await js(`[...document.querySelectorAll('.fh-lcat')].find(c => c.dataset.shelfname === 'Wrap').id`);
  await openMenu(`#${wrapId} .fh-lcatmenu > summary`);
  check("…and its ⋯ has Rename and Remove", JSON.stringify(await words()) === JSON.stringify(["Rename", "Remove"]), JSON.stringify(await words()));
  await pick("Rename");
  await wait(200);
  await js(`document.querySelector('.fh-lcatedit').select()`);
  await type("Wrap Up");
  await key("Enter");
  await wait(1000);
  check("Rename renames the category in place", (await js(`document.querySelector('#${wrapId} .fh-lhead b').textContent`)) === "Wrap Up");
  await open("library");
  check("…and it is saved, the sidebar's heading too", (await js(`document.querySelector('#${wrapId} .fh-lhead b').textContent`)) === "Wrap Up"
    && (await js(`[...document.querySelectorAll('nav.rail .group[data-head]')].some(g => g.dataset.head === 'Wrap Up')`)) === true);
  await js(`window.confirm = () => true`);
  await openMenu(`#${wrapId} .fh-lcatmenu > summary`);
  await pick("Remove");
  await wait(2500);
  check("Remove takes away one he added", (await js(`!document.querySelector('#${wrapId}')`)) === true);

  say("Crew");
  await open("library");
  await js(`document.querySelector('.fh-lcrew .fh-lfold').open = true`);
  const contact = `.fh-lperson[data-person="Ellis Ward"] [data-kind="contact"]`;
  check("each person has Shown and Contact", (await js(`document.querySelectorAll('.fh-lperson[data-person="Ellis Ward"] [role=switch]').length`)) === 2);
  check("Contact starts off", (await js(`document.querySelector('${contact}').getAttribute('aria-checked')`)) === "false");
  await js(`document.querySelector('${contact}').click()`);
  await wait(900);
  await shot("5-crew");
  await open("library");
  check("…and turned on, it is saved", (await js(`document.querySelector('${contact}').getAttribute('aria-checked')`)) === "true");
  await js(`document.querySelector('.fh-lcrew .fh-lfold').open = true`);
  await js(`document.querySelector('${contact}').click()`);
  await wait(900);

  say("Add Page opens the Add menu");
  await js(`document.querySelector('[data-laddpage]').click()`);
  await wait(400);
  check("Add Page opens the same Add menu as the sidebar's +", (await js(`!!document.querySelector('.addpop, .addbox')`)) === true);
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);

  say("A reader's Library is the shelves it always was");
  await open("library", READER);
  check("a reader gets shelves of cards, not the list", (await js(`document.querySelectorAll('.fh-shelf .fh-card').length`)) >= 5 && (await js(`!document.querySelector('.fh-lpane')`)) === true);
  const cover = (k) => js(`(() => { const c = document.querySelector('.fh-card[data-key=${JSON.stringify(k)}]:not([data-echo])'); const v = c && c.querySelector('.fh-slot .fh-cv'); return v ? v.className + '|' + v.innerText.replace(/\\s+/g, ' ').trim() : ''; })()`);
  check("a deck is a landscape cover", /^fh-cv deck/.test(await cover("pitch-deck")), await cover("pitch-deck"));
  check("a written page is paper with lines", /fh-cv page\|/.test(await cover("safety-briefing")), await cover("safety-briefing"));
  check("a link shows where it goes", /fh-cv link\|drive\.google\.com$/.test(await cover("doc:Deal memo")), await cover("doc:Deal memo"));
  check("a file is plain paper", /^fh-cv file\|$/.test(await cover("doc:Lens chart")), await cover("doc:Lens chart"));
  check("a reader is offered no controls", (await js(`!document.querySelector('.fh-cardmenu, .fh-pick, [data-select]')`)) === true);
  await shot("6-reader");
  await js(`(() => { const el = document.querySelector('.fh-card .fh-cardlink'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: r.left + 30, clientY: r.top + 20 })); })()`);
  const rw = await words();
  check("a reader's right click is the link's three", JSON.stringify(rw) === JSON.stringify(["Open", "Open in New Tab", "Copy Link"]), JSON.stringify(rw));
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);

  say("The portal's other pages");
  await open("night-look");
  await js(`(() => { const el = document.querySelector('.fh-pane'); el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: 600, clientY: 400 })); })()`);
  const page = await words();
  check("the page itself has a menu", page.includes("Copy Page Link") && page.includes("Reload"), JSON.stringify(page));
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);

  say("A phone");
  await ask("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
  await ask("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
  await ask("Emulation.setEmulatedMedia", { features: [{ name: "hover", value: "none" }, { name: "pointer", value: "coarse" }] });
  await open("library");
  const small = await js(`[...document.querySelectorAll('.fh-lcats .fh-lfold[open] .fh-lsw, .fh-lcats .fh-lfold[open] .fh-lmenu summary, .fh-lhead, .fh-lbtn, [data-lfind]')].filter(e => e.offsetParent && Math.round(e.getBoundingClientRect().height) < 44).length`);
  check("every control is a thumb's height", small === 0, `${small} smaller than 44px: ` + await js(`[...document.querySelectorAll('.fh-lcats .fh-lfold[open] .fh-lsw, .fh-lcats .fh-lfold[open] .fh-lmenu summary, .fh-lhead, .fh-lbtn, [data-lfind]')].filter(e => e.offsetParent && Math.round(e.getBoundingClientRect().height) < 44).map(e => e.className + ':' + Math.round(e.getBoundingClientRect().height)).join()`));
  const wide = await js(`document.documentElement.scrollWidth <= innerWidth`);
  check("nothing runs off the side", wide === true);
  await shot("p1-pages");
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
