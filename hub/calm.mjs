#!/usr/bin/env node
/**
 * The calm pass, driven in a real browser (2026-10-03).
 *
 * Pinned and Private in place of three settings and "Me"; Archive that hides;
 * covers that say one real thing; a calmer film home. A small film goes in a
 * throwaway local bucket, the hub starts on it, and headless Chromium does what
 * a person does. A viewer is another `?as=` address that the film lists as a
 * viewer. Run it with `node hub/calm.mjs`; `SHOTS=<dir>` also writes a picture
 * of each state there. Local only: it never touches the real bucket.
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
const PORT = 8832, DEBUG = 9353;
const WHO = "owner@example.com";
const VIEWER = "viewer@example.com";
const SHOTS = process.env.SHOTS || "";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(70)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(70)} FAIL · ${why}`); };
const check = (what, cond, why = "not so") => (cond ? ok(what) : no(what, why));

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

const soon = new Date(Date.now() + 30 * 86400000).toISOString().slice(0, 10);
const FRONT = {
  version: 1, logline: "A long logline. ".repeat(40), director: "Clara Ward", status: "Pre-Production",
  shoot: { start: soon, end: soon }, ratio: 2.39, camera: { body: "ARRI Alexa Mini" },
  days: [{ date: soon, label: "Day 1" }],
  sections: [
    { slug: "lighting-plan", name: "Lighting Plan", by: "mcp", type: "page", source: "here" },
    { slug: "safety-briefing", name: "Safety Briefing", by: "mcp", type: "page", source: "here" },
    { slug: "pitch-deck", name: "Pitch Deck", by: "deck", type: "deck", source: "program" },
    { slug: "night-look", name: "Night Look", by: "mcp", type: "page", source: "here" },
    { slug: "wrap-notes", name: "Wrap Notes", by: "mcp", type: "page", source: "here" },
    { slug: "dump-board", name: "Dump Board", by: "mcp", type: "board", board: "dump-board", source: "here", share: "me" },
  ],
  documents: [{ name: "Deal memo", url: "https://drive.google.com/x", kind: "document" }],
  crew: [{ name: "Ellis Ward", role: "Gaffer" }],
  groups: [{ name: "Creative", rows: ["night-look", "lighting-plan", "pitch-deck", "dump-board"] }, { name: "Logistics", rows: ["safety-briefing", "wrap-notes", "people", "documents"] }],
  library: [{ at: "safety-briefing", head: "Logistics" }],
};
// safety-briefing starts unpinned AND private; night-look starts hidden For Me (it will migrate to unpinned).
const VISIBLE = { version: 1, sections: ["safety-briefing"], crew: [], documents: [], contact: [], me: { sections: ["night-look"], crew: ["Ellis Ward"], documents: [] } };

const state = mkdtempSync(join(tmpdir(), "calm-state-"));
const box = mkdtempSync(join(tmpdir(), "calm-box-"));
const wr = join(HERE, "node_modules/.bin/wrangler");
const put = (key, body) => {
  const file = join(box, "f.bin");
  writeFileSync(file, body);
  spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
const readObj = (key) => spawnSync(wr, ["r2", "object", "get", `shotlister-preview/${key}`, "--local", "--persist-to", state, "--pipe"], { cwd: HERE, encoding: "utf8" }).stdout;
say("Putting a small film in a local bucket…");
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
put(`p/${FILM}/front.json`, JSON.stringify(FRONT));
put(`p/${FILM}/visible.json`, JSON.stringify(VISIBLE));
put(`p/${FILM}/people.json`, JSON.stringify({ version: 1, people: [{ email: VIEWER, role: "viewer" }], links: [], invites: [] }));
const tree = (heading) => JSON.stringify([...(heading ? [{ t: "h2", r: [{ s: heading }] }] : []), { t: "p", r: [{ s: "Some words." }] }]);
put(`p/${FILM}/pages/lighting-plan.json`, tree("Lighting Approach"));
put(`p/${FILM}/pages/safety-briefing.json`, tree("On Set Safety"));
put(`p/${FILM}/pages/night-look.json`, tree(""));
put(`p/${FILM}/pages/wrap-notes.json`, tree("Wrap Notes Heading"));
put(`p/${FILM}/pages/pitch-deck.html`, `<style>.x{}</style><div class="deckweb"><header class="top"><h1>The Pitch</h1></header><div class="sec" id="s-a"><h2>A</h2></div></div>`);
put(`p/${FILM}/decks/pitch-deck.json`, JSON.stringify({ name: "Pitch Deck", sections: [1, 2, 3, 4, 5].map((i) => ({ id: `s${i}`, title: `S${i}`, on: true })).concat([{ id: "off", title: "Off", on: false }]) }));
put(`p/${FILM}/boards/dump-board.json`, JSON.stringify({ added: [1, 2, 3, 4].map((i) => ({ id: `c${i}`, kind: "note", text: `n${i}`, x: i * 10, y: 0 })) }));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:",
  "--var", "COMMIT:calm-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

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

  proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1440,900", "about:blank"], { stdio: "ignore" });
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
  const errors = [];
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
    if (said.method === "Runtime.exceptionThrown") errors.push(said.params.exceptionDetails.exception?.description || said.params.exceptionDetails.text);
  });
  const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
  await ask("Page.enable");
  await ask("Runtime.enable");
  const desk = () => ask("Emulation.setDeviceMetricsOverride", { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
  await desk();
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
  const get = async (path, who = WHO) => {
    const got = await fetch(`http://127.0.0.1:${PORT}/f/${FILM}/${path}${path.includes("?") ? "&" : "?"}as=${who}`, { redirect: "manual" });
    return { code: got.status, text: await got.text() };
  };
  const bulk = async (action, keys) => {
    const body = new FormData();
    body.set("bulk", JSON.stringify({ keys, action }));
    const got = await fetch(`http://127.0.0.1:${PORT}/f/${FILM}/library?as=${WHO}`, { method: "POST", body });
    return got.status;
  };
  const right = (sel) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return false;
    const r = el.getBoundingClientRect();
    return el.dispatchEvent(new MouseEvent('contextmenu', { bubbles: true, cancelable: true, clientX: r.left + 30, clientY: r.top + 20 })); })()`);
  const press = (sel) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return false; el.click(); return true; })()`);
  const menuShape = () => js(`[...document.querySelectorAll('.ctxmenu:not(.ctxsub) > .ctxsec, .ctxmenu:not(.ctxsub) > .ctxnode .sn, .ctxmenu:not(.ctxsub) > .ctxsep, .ctxmenu:not(.ctxsub) > .ctxitem, .ctxmenu:not(.ctxsub) > .ctxwrap > .ctxitem')].map(e => e.classList.contains('sn') ? 'sn:' + e.textContent : e.classList.contains('ctxsep') ? '-' : e.textContent)`);
  const esc = () => js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);
  const railKeys = () => js(`[...document.querySelectorAll('nav.rail .group .to')].map(a => a.dataset.key)`);

  // ---------------------------------------------------------------- A: Pinned and Private
  say("Me retires: a page hidden For Me becomes unpinned, once");
  await open("library");
  check("night-look, hidden For Me, is no longer pinned", (await js(`document.querySelector('.fh-card[data-key="night-look"]:not([data-echo])').dataset.side`)) === "0"
    && !(await railKeys()).includes("night-look"), JSON.stringify(await railKeys()));
  const vis1 = JSON.parse(readObj(`p/${FILM}/visible.json`));
  check("…and it left visible.me, the rest of the store kept", (vis1.me.sections || []).length === 0 && vis1.me.crew.includes("Ellis Ward"), JSON.stringify(vis1.me));
  await open("library");
  const vis2 = JSON.parse(readObj(`p/${FILM}/visible.json`));
  check("…and reading again changes nothing", JSON.stringify(vis2) === JSON.stringify(vis1));
  check("a page that was already unpinned and private stays so", (await js(`document.querySelector('.fh-card[data-key="safety-briefing"]:not([data-echo])').dataset.side`)) === "0"
    && (await js(`document.querySelector('.fh-card[data-key="safety-briefing"]:not([data-echo])').dataset.links`)) === "0");
  check("no \"Not on Sidebar\" tag, a lock instead", (await js(`!/Not on Sidebar|Off Links/.test(document.body.innerText)`)) === true
    && (await js(`!!document.querySelector('.fh-card[data-key="safety-briefing"] .fh-lock svg')`)) === true);
  check("…and a lock on the sidebar row for an editor", (await js(`!!document.querySelector('nav.rail .to[data-key="people"] .off-tag svg')`)) === true);
  await shot("1-library");

  say("The item menu");
  await right(`.fh-card[data-key="lighting-plan"]:not([data-echo])`);
  const shape = await menuShape();
  check("Pinned, Private, rule, Open, Rename, Icon, Move To, rule, Archive", JSON.stringify(shape) === JSON.stringify(["sn:Pinned", "sn:Private", "-", "Open", "Open in New Tab", "Copy Link", "Rename", "Icon", "Move To", "-", "Archive"]), JSON.stringify(shape));
  check("…no Seen On, no Me, no Links", (await js(`!/Seen On|Shown for Me|Shown on Links|\\bMe\\b/.test(document.querySelector('.ctxmenu').innerText)`)) === true);
  check("Pinned is on, Private is off", (await js(`document.querySelector('.ctxmenu .sn[data-seen="pin"]').getAttribute('aria-pressed')`)) === "true"
    && (await js(`document.querySelector('.ctxmenu .sn[data-seen="priv"]').getAttribute('aria-pressed')`)) === "false");
  await wait(500);
  await shot("2-item-menu");

  say("Pinned and Private save");
  await press('.ctxmenu .sn[data-seen="priv"]');
  await wait(700);
  check("Private lights at once and a lock appears on the card and the sidebar row", (await js(`document.querySelector('.ctxmenu .sn[data-seen="priv"]').getAttribute('aria-pressed')`)) === "true"
    && (await js(`!!document.querySelector('.fh-card[data-key="lighting-plan"]:not([data-echo]) .fh-lock')`)) === true
    && (await js(`document.querySelector('nav.rail .to[data-key="lighting-plan"]').classList.contains('offl')`)) === true);
  check("…the pill says Saved", (await js(`document.querySelector('.fx-toast, .fx-pill, [data-feel-toast]')?.textContent || document.body.innerText.includes('Saved')`)) );
  await esc();
  await open("library");
  check("…and it is still Private after a reload", (await js(`document.querySelector('.fh-card[data-key="lighting-plan"]:not([data-echo])').dataset.links`)) === "0");
  const asViewer = await get("library", VIEWER);
  check("a viewer cannot open it (404) and the Library omits it", (await get("lighting-plan", VIEWER)).code === 404 && !asViewer.text.includes('data-key="lighting-plan"'), `${(await get("lighting-plan", VIEWER)).code}`);
  check("…and a viewer sees no lock at all", !asViewer.text.includes("fh-lock") && !asViewer.text.includes("off-tag"));
  await right(`.fh-card[data-key="lighting-plan"]:not([data-echo])`);
  await press('.ctxmenu .sn[data-seen="priv"]');
  await wait(700);
  await press('.ctxmenu .sn[data-seen="pin"]');
  await wait(700);
  await esc();
  await open("library");
  check("Pinned off takes the row off the sidebar, still in the Library; Private off shows it again", (await js(`document.querySelector('.fh-card[data-key="lighting-plan"]:not([data-echo])').dataset.side`)) === "0"
    && (await js(`document.querySelector('.fh-card[data-key="lighting-plan"]:not([data-echo])').dataset.links`)) === "1"
    && !(await railKeys()).includes("lighting-plan") && (await get("lighting-plan", VIEWER)).code === 200);
  await right(`.fh-card[data-key="lighting-plan"]:not([data-echo])`);
  await press('.ctxmenu .sn[data-seen="pin"]');
  await wait(700);
  await esc();
  await open("library");
  check("…and Pinned on puts it back", (await railKeys()).includes("lighting-plan"));

  say("Share: What Viewers See");
  const checks = (await get("visibility?part=2")).text;
  check("the checklist has no For Me and no On Links control", !/For Me|On Links|me-sections|name="for"/.test(checks), checks.slice(0, 120));
  check("…private pages carry a lock, a ticked page does not need one", checks.includes('class="sp-lk"') && /name="sections" value="safety-briefing"(?![^>]*checked)/.test(checks));
  const plain = (await get("visibility")).text;
  check("the Visibility page is What Viewers See, with no For Me", plain.includes("What Viewers See") && !/For Me|On Links/.test(plain));
  const menus = (await get("lighting-plan")).text;
  check("a page's own menu says Pinned and Private", menus.includes(">Pinned<i>") && menus.includes(">Private<i>") && !/Shown on Links|Shown for Me|Take Off Sidebar/.test(menus));
  await open("lighting-plan");
  await js(`document.querySelector('nav.rail .sharebtn')?.click()`);
  await wait(900);
  await js(`document.querySelector('.fx-pop.sp [data-tab="visibility"]')?.click()`);
  await wait(1200);
  check("the Share tab reads What Viewers See", (await js(`document.querySelector('.sp-h .sp-seg')?.innerText.replace(/\\s+/g,' ')`)) === "People What Viewers See");
  check("…and the list has no For Me control", (await js(`!document.querySelector('.fx-pop.sp .sp-seg.sm')`)) === true);
  await shot("3-what-viewers-see");
  await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))`);

  // ---------------------------------------------------------------- B: Archive that hides
  say("Archive hides, and Unarchive restores exactly");
  await open("library");
  // wrap-notes: pinned, public. safety-briefing: unpinned, private. Archive both.
  check("they start as they were (wrap-notes pinned and public)", (await railKeys()).includes("wrap-notes")
    && (await get("wrap-notes", VIEWER)).code === 200);
  await js(`document.querySelector('[data-select]').click()`);
  await js(`document.querySelector('.fh-card[data-key="wrap-notes"]:not([data-echo]) .fh-cardlink').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))`);
  await js(`document.querySelector('.fh-card[data-key="safety-briefing"]:not([data-echo]) .fh-cardlink').dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))`);
  await js(`[...document.querySelectorAll('.fh-bulkbtn')].find(b => b.textContent === 'Archive').click()`);
  await wait(2400);
  check("both are in a folded Archive, with their count in its head", (await js(`(() => { const d = document.querySelector('.fh-archive'); return !!d && !d.open && /Archive\\s*2/.test(d.querySelector('summary').textContent); })()`)) === true);
  check("…and on no shelf, not on the sidebar", (await js(`document.querySelectorAll('.fh-shelf .fh-card[data-key="wrap-notes"]').length`)) === 0
    && !(await railKeys()).includes("wrap-notes"));
  check("…and the Archive is the last thing in the Library", (await js(`(() => { const p = document.querySelector('.fh-libpane'); const kids = [...p.children].filter(e => !e.classList.contains('fh-bulk')); return kids[kids.length - 1].classList.contains('fh-archive'); })()`)) === true);
  check("a viewer cannot reach an archived page, and does not see it listed", (await get("wrap-notes", VIEWER)).code === 404
    && !(await get("library", VIEWER)).text.includes("wrap-notes") && !(await get("", VIEWER)).text.includes("wrap-notes"));
  check("…and it is not in Find, nor Recently Opened", (await js(`!document.querySelector('#shelf-recent .fh-card[data-key="wrap-notes"]')`)) === true
    && (await js(`![...document.querySelectorAll('nav.rail .to')].some(a => /Wrap Notes/.test(a.textContent))`)) === true);
  await js(`document.querySelector('.fh-archive summary').click()`);
  await wait(300);
  await js(`document.querySelector('.fh-archive').scrollIntoView({ block: 'center' })`);
  await wait(300);
  await shot("4-archive-open");
  await open("library");
  check("the folded state is remembered per film", (await js(`document.querySelector('.fh-archive').open`)) === true);
  await js(`document.querySelector('.fh-archive summary').click()`);
  await js(`document.querySelector('.fh-archive').open = true`);
  await right(`.fh-archive .fh-card[data-key="wrap-notes"]`);
  const arch = await menuShape();
  check("an archived item's menu offers Unarchive", arch.includes("Unarchive"), JSON.stringify(arch));
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Unarchive').click()`);
  await wait(2400);
  await js(`document.querySelector('.fh-archive').open = true`);
  await right(`.fh-archive .fh-card[data-key="safety-briefing"]`);
  await js(`[...document.querySelectorAll('.ctxitem')].find(b => b.textContent === 'Unarchive').click()`);
  await wait(2400);
  const where = await js(`(() => { const a = document.querySelector('nav.rail .to[data-key="wrap-notes"]'); if (!a) return 'missing'; let g = a.closest('.group'); const head = g && (g.querySelector('.grouphead, .hname, h3') || g.previousElementSibling); return (head && head.textContent.trim()) || 'no head: ' + (g ? g.className : 'nogroup'); })()`);
  check("wrap-notes is back on the sidebar under Logistics, public again", /Logistics/.test(where) && (await get("wrap-notes", VIEWER)).code === 200, where);
  check("safety-briefing is still unpinned and private, as it was", (await js(`document.querySelector('.fh-card[data-key="safety-briefing"]:not([data-echo])').dataset.side`)) === "0"
    && (await js(`document.querySelector('.fh-card[data-key="safety-briefing"]:not([data-echo])').dataset.links`)) === "0"
    && (await get("safety-briefing", VIEWER)).code === 404);
  check("…and the Archive is gone when empty", (await js(`!document.querySelector('.fh-archive')`)) === true);
  const connector = await bulk("archive", ["dump-board"]);
  const front = (await get("library")).text;
  check("a board archives too, and a link holder cannot open it", connector === 200 && /class="fh-archive"[\s\S]*data-key="dump-board"/.test(front));
  await bulk("unarchive", ["dump-board"]);

  // ---------------------------------------------------------------- C: covers
  say("Covers that say one real thing");
  await open("library");
  const cv = (key) => js(`(() => { const c = document.querySelector('.fh-card[data-key=${JSON.stringify(key)}]:not([data-echo])'); const v = c && c.querySelector('.fh-slot .fh-cv'); return v ? { cls: v.className, t: v.querySelector('.cvt')?.textContent || '', n: v.querySelector('.cvn')?.textContent || '', tiles: v.querySelectorAll(':scope > i').length } : null; })()`);
  const deck = await cv("pitch-deck"), page = await cv("lighting-plan"), board = await cv("dump-board"), bare = await cv("night-look");
  check("a deck says its first heading and its slide count", deck && deck.t === "The Pitch" && deck.n === "5", JSON.stringify(deck));
  check("a written page says its first heading above the lines", page && page.t === "Lighting Approach" && /page/.test(page.cls), JSON.stringify(page));
  check("a page with no heading says nothing", bare && bare.t === "" && bare.n === "", JSON.stringify(bare));
  check("a board shows as many tiles as pins, and the count", board && board.tiles === 4 && board.n === "4", JSON.stringify(board));
  check("Built In, File and Link covers are unchanged", (await js(`document.querySelector('.fh-card[data-key="people"]:not([data-echo]) .fh-cv').innerText.replace(/\\s+/g,' ').trim()`)) === "1 Contact");
  check("the deck's heading is at most two lines, small", (await js(`getComputedStyle(document.querySelector('.fh-card[data-key="pitch-deck"] .cvt')).webkitLineClamp`)) === "2");
  await shot("5-covers");
  // A write moves the stamp, and the cover follows it.
  put(`p/${FILM}/pages/lighting-plan.json`, tree("A New Heading"));
  await wait(1200);
  await open("library");
  check("a rewritten page is read again, and says its new heading", (await cv("lighting-plan")).t === "A New Heading");

  // The cost: a first look reads each unread body once; afterwards only a listing.
  {
    const t0 = Date.now(); await get("library"); const warm = Date.now() - t0;
    put(`p/${FILM}/pages/lighting-plan.json`, tree("Cost Check"));
    put(`p/${FILM}/pages/wrap-notes.json`, tree("Cost Check"));
    put(`p/${FILM}/decks/pitch-deck.json`, JSON.stringify({ name: "Pitch Deck", sections: [{ id: "a", on: true }] }));
    const t1 = Date.now(); await get("library"); const cold = Date.now() - t1;
    const t2 = Date.now(); await get("library"); const again = Date.now() - t2;
    say(`  measured: Library ${warm} ms with nothing new, ${cold} ms after three writes (three bodies read once), ${again} ms again`);
    check("…three rewritten bodies are read once, then not again", (await cv("pitch-deck")) !== undefined && again <= Math.max(cold, 400));
  }

  // ---------------------------------------------------------------- D: the calm home
  say("The film's home");
  await open("");
  await js(`sessionStorage.clear(); localStorage.clear()`);
  await open("");
  const home = await js(`(() => ({
    props: !!document.querySelector('.hm-props'), chips: !!document.querySelector('.hm-chips'), nd: [...document.querySelectorAll('.hm-nd')].map(e => e.innerText.replace(/\\s+/g, ' ').trim()),
    facts: document.querySelector('.hm-facts')?.innerText.replace(/\\s+/g, ' ').trim() || '', since: !!document.querySelector('[data-since]'),
    width: Math.round(parseFloat(getComputedStyle(document.querySelector('.hm-main')).maxWidth)), left: Math.round(document.querySelector('.hm-main').getBoundingClientRect().left),
    fold: document.querySelector('[data-foldbtn]') && !document.querySelector('[data-foldbtn]').hidden, clamped: document.querySelector('[data-fold]').classList.contains('clamped'),
  }))()`);
  check("no right-hand Properties panel and no chips", home.props === false && home.chips === false, JSON.stringify(home));
  check("one quiet line of facts: Status · Shoot · Camera (Format when the film has one)", /^Pre-Production · \d+ \w+ · ARRI Alexa Mini$/.test(home.facts), home.facts);
  check("one Next Day line with day number and distance", home.nd.length === 1 && /^Next Day .+ · Day 1 · 30 days away No scenes yet$/.test(home.nd[0]), JSON.stringify(home.nd));
  check("the column is at most about 680 wide and left aligned", home.width <= 700 && home.left < 400, JSON.stringify([home.width, home.left]));
  check("the logline folds to three lines with More", home.fold === true && home.clamped === true);
  check("Since You Looked is absent when nothing is new", home.since === false, JSON.stringify(home.since));
  await shot("6-home");
  // Something changes after his visit: the block appears, at most three lines.
  put(`p/${FILM}/pages/night-look.json`, tree("Changed After"));
  put(`p/${FILM}/pages/wrap-notes.json`, tree("Changed After"));
  await wait(1200);
  await js(`sessionStorage.clear()`);
  await open("");
  const sinceRows = await js(`document.querySelector('[data-since]') && !document.querySelector('[data-since]').hidden ? document.querySelectorAll('[data-since] .hm-fr').length : -1`);
  check("…and shows only what changed since the last visit, three lines at most", sinceRows >= 1 && sinceRows <= 3, String(sinceRows));
  await shot("7-home-since");

  check("no errors in the console", errors.length === 0, errors.slice(0, 2).join(" | "));

  // ---------------------------------------------------------------- phone and iPad
  say("A phone");
  const touch = (type, x, y) => ask("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y }] });
  const centre = (sel) => js(`(() => { document.querySelector(${JSON.stringify(sel)}).scrollIntoView({ block: 'center' }); const r = document.querySelector(${JSON.stringify(sel)}).getBoundingClientRect(); return [r.left + r.width / 2, r.top + Math.min(r.height / 2, 30)]; })()`);
  const hold = async (sel, ms = 750) => { const [x, y] = await centre(sel); await touch("touchStart", x, y); await wait(ms); await touch("touchEnd"); await wait(300); };
  const emulate = async (w, h, on) => {
    if (on) {
      await ask("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 2, mobile: true });
      await ask("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
      await ask("Emulation.setEmulatedMedia", { features: [{ name: "hover", value: "none" }, { name: "pointer", value: "coarse" }] });
    } else {
      await ask("Emulation.setTouchEmulationEnabled", { enabled: false });
      await ask("Emulation.setEmulatedMedia", { features: [] });
      await desk();
    }
  };
  await emulate(390, 844, true);
  await open("");
  const ph = await js(`({ props: !!document.querySelector('.hm-props'), chips: !!document.querySelector('.hm-chips'), nd: document.querySelectorAll('.hm-nd').length,
    facts: !!document.querySelector('.hm-facts'), over: document.documentElement.scrollWidth > innerWidth, fold: document.querySelector('[data-foldbtn]') && !document.querySelector('[data-foldbtn]').hidden })`);
  check("the phone home is the same calm column", !ph.props && !ph.chips && ph.nd === 1 && ph.facts && !ph.over && ph.fold, JSON.stringify(ph));
  await shot("p1-home");
  await open("library");
  await hold(`.fh-card[data-key="lighting-plan"]:not([data-echo]) .fh-cardlink`);
  const pshape = await menuShape();
  check("a hold opens Pinned and Private, then Open, Move To, Archive", JSON.stringify(pshape) === JSON.stringify(["-", "sn:Pinned", "sn:Private", "-", "Open", "Rename", "Icon", "Move To", "-", "Archive"]), JSON.stringify(pshape));
  await shot("p2-hold-menu");
  await esc();
  await bulk("archive", ["wrap-notes"]);
  await open("library");
  await js(`document.querySelector('.fh-archive').open = true`);
  await wait(300);
  await js(`document.querySelector('.fh-archive').scrollIntoView()`);
  await shot("p3-library-archive");
  await bulk("unarchive", ["wrap-notes"]);
  await open("lighting-plan");
  await js(`document.querySelector('.sharebtn, [data-share]')?.click()`);
  await wait(1200);
  await js(`[...document.querySelectorAll('[data-tab="visibility"]')].find(b => b.offsetParent)?.click()`);
  await wait(1200);
  check("the phone sheet says What Viewers See and has no For Me", (await js(`/What Viewers See/.test(document.body.innerText) && !/For Me|On the Link/.test(document.body.innerText)`)) === true);
  await shot("p4-what-viewers-see");
  await emulate(1024, 768, true);
  await open("");
  check("an iPad home is the same column", (await js(`!document.querySelector('.hm-props') && document.querySelectorAll('.hm-nd').length === 1`)) === true);
  await shot("i1-ipad-home");
  await emulate(0, 0, false);
} catch (error) {
  no("the run", String((error && error.stack) || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
