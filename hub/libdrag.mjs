#!/usr/bin/env node
/**
 * **A page dragged between the Library and the sidebar** (2026-10-11), with a
 * real mouse: Chrome's own input pipeline, not events made by a script, then a
 * reload to prove the order was saved and not only drawn.
 *
 * Puts a small film in a throwaway local bucket, starts the hub on its own
 * port, takes a page off the sidebar, drags its Library row onto the rail
 * between two rows, drags it back out onto the Library, and uses the row's ⋯
 * for the same two things. Run it with `node hub/libdrag.mjs`; `SHOTS=<dir>`
 * writes a picture of each state.
 *
 * Local only: it never touches the real bucket.
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
const PORT = 8797, DEBUG = 9353;
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

const state = mkdtempSync(join(tmpdir(), "libdrag-state-"));
const box = mkdtempSync(join(tmpdir(), "libdrag-box-"));
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

  // a real mouse: press, travel in steps, release
  const mouse = (type, x, y) => ask("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons: type === "mouseReleased" ? 0 : 1, clickCount: 1 });
  const centre = (sel, fy = 0.5) => js(`(() => { const el = document.querySelector(${JSON.stringify(sel)}); if (!el) return null; const r = el.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height * ${fy} }; })()`);
  const drag = async (from, to, hold = true) => {
    await mouse("mouseMoved", from.x, from.y);
    await mouse("mousePressed", from.x, from.y);
    for (let i = 1; i <= 14; i++) { await mouse("mouseMoved", from.x + (to.x - from.x) * i / 14, from.y + (to.y - from.y) * i / 14); await wait(25); }
    if (hold) await shot("drag-" + (++shots));
    await mouse("mouseReleased", to.x, to.y);
  };
  let shots = 0;
  const railKeys = () => js(`[...document.querySelectorAll('nav.rail .to[data-key]')].map(r => r.dataset.key)`);
  const headOf = (k) => js(`(document.querySelector('nav.rail .to[data-key="${k}"]') || {}).closest?.('.group')?.dataset.head || ''`);
  const rowsOf = (head) => js(`[...document.querySelectorAll('nav.rail .group[data-head=${JSON.stringify(head)}] > .to[data-key]')].map(r => r.dataset.key)`);

  say("Setting up: one page off the sidebar");
  await open("library");
  await js(`(() => { const b = new FormData(); b.set('bulk', JSON.stringify({ keys: ['reel-notes'], action: 'unpin', to: '' })); return fetch('/f/${FILM}/library?as=${WHO}', { method: 'POST', body: b }).then(r => r.status); })()`);
  await open("library");
  check("Reel Notes is not on the sidebar", !(await railKeys()).includes("reel-notes"), JSON.stringify(await railKeys()));
  check("every Library row leads with its icon and a heading has its own", (await js(`[...document.querySelectorAll('.fh-lcats .fh-lrow')].every(r => r.querySelector('.fh-lico svg')) && [...document.querySelectorAll('.fh-lcats .fh-lhead')].every(h => h.querySelector('.fh-hico svg'))`)) === true);
  check("Add Pages… is not drawn for a mouse", (await js(`getComputedStyle(document.querySelector('nav.rail .fh-addpages')).display`)) === "none");
  check("the Library says New Page and New Category", (await js(`[...document.querySelectorAll('.fh-lbtn')].map(b => b.textContent.trim()).join()`)) === "New Page,New Category");
  check("a heading's + says where a new page goes", (await js(`document.querySelector('nav.rail .grouphead .hplus').getAttribute('aria-label')`)).startsWith("New in "));

  say("Library onto the sidebar");
  await js(`document.querySelectorAll('.fh-lcats .fh-lfold').forEach(d => d.open = true)`);
  await find("reel");
  const before = await rowsOf("Creative");
  const from = await centre(`${row("reel-notes")} .fh-lname`);
  const onto = await centre('nav.rail .to[data-key="night-look"]', 0.2);
  await drag(from, onto);
  await wait(3500);
  const after = await rowsOf("Creative");
  check("it lands on the sidebar under the heading it was dropped in", (await headOf("reel-notes")) === "Creative", await headOf("reel-notes"));
  check("…above the row it was dropped on", after.indexOf("reel-notes") !== -1 && after.indexOf("reel-notes") < after.indexOf("night-look"), JSON.stringify({ before, after }));
  check("the Library page did not open the page it was dragged by", (await js(`location.pathname.endsWith('/library')`)) === true, await js(`location.pathname`));
  await shot("1-on");
  await open("library");
  const reloaded = await rowsOf("Creative");
  check("after a reload it is still there, in the same place", reloaded.join() === after.join(), JSON.stringify({ after, reloaded }));

  say("Sidebar back onto the Library");
  const out = await centre('nav.rail .to[data-key="reel-notes"]');
  const pane = await centre(".fh-lpane", 0.5);
  await drag(out, pane);
  await wait(3000);
  check("it comes off the sidebar", !(await railKeys()).includes("reel-notes"), JSON.stringify(await railKeys()));
  await open("library");
  check("after a reload it is still off", !(await railKeys()).includes("reel-notes"));
  check("…but still in the Library", (await js(`!!document.querySelector('${row("reel-notes")}')`)) === true);

  say("A link: pinned the same way");
  await open("library");
  await js(`document.querySelectorAll('.fh-lcats .fh-lfold').forEach(d => d.open = true)`);
  const dk = 'doc:Deal memo';
  check("a link is a Library row that can be dragged", (await js(`!!document.querySelector('${row(dk)}')`)) === true);
  check("…and is not on the sidebar yet", !(await railKeys()).includes(dk), JSON.stringify(await railKeys()));
  await find("deal");   // a long category shows eight rows; a search shows every match
  const docFrom = await centre(`${row(dk)} .fh-lname`);
  const docOnto = await centre('nav.rail .to[data-key="night-look"]', 0.2);
  await js(`window.__errs = []; addEventListener('error', e => window.__errs.push(String(e.message)));`);
  await drag(docFrom, docOnto);
  await wait(3500);
  if (process.env.DEBUG_DOC) say("DEBUG", JSON.stringify({ keys: (await railKeys()).filter((k) => k.startsWith("doc:")), errs: await js("window.__errs"), pinned: await js(`fetch('/f/${FILM}/library?part=pick&as=${WHO}').then(r => r.json()).then(d => d.pages.filter(p => p.at.startsWith('doc:')).map(p => p.at + ':' + p.on))`), url: await js("location.href"), said: await js("[...document.querySelectorAll('.fx-toast, [role=status]')].map(e => e.textContent).join('|')") }));
  check("dragged onto the sidebar it becomes a row", (await railKeys()).includes(dk), JSON.stringify(await railKeys()));
  check("…under the heading it was dropped in, above the row it was dropped on", (await headOf(dk)) === "Creative" && (await rowsOf("Creative")).indexOf(dk) < (await rowsOf("Creative")).indexOf("night-look"), JSON.stringify(await rowsOf("Creative")));
  check("…and the row opens the link in a new tab", (await js(`(() => { const a = document.querySelector('nav.rail .to[data-key="${dk}"]'); return a && a.target === '_blank' && /^https:/.test(a.href); })()`)) === true);
  await open("library");
  check("after a reload it is still on the sidebar", (await railKeys()).includes(dk) && (await headOf(dk)) === "Creative");
  await openMenu(`${row(dk)} .fh-lmenu > summary`);
  check("its ⋯ offers Remove from Sidebar", (await words()).includes("Remove from Sidebar"), JSON.stringify(await words()));
  await pick("Remove from Sidebar");
  await wait(3000);
  check("…which takes it off", !(await railKeys()).includes(dk), JSON.stringify(await railKeys()));
  await find("deal");
  await openMenu(`${row(dk)} .fh-lmenu > summary`);
  await pick("Add to Sidebar");
  await wait(3000);
  check("Add to Sidebar from the ⋯ puts a link on too", (await railKeys()).includes(dk), JSON.stringify(await railKeys()));
  const pickList = await js(`fetch('/f/${FILM}/library?part=pick&as=${WHO}').then(r => r.json()).then(d => d.pages.filter(p => p.at.startsWith('doc:')).map(p => p.at + ':' + p.on))`);
  check("a touch screen's Add Pages… list offers links and files too", Array.isArray(pickList) && pickList.includes("doc:Deal memo:true") && pickList.some((x) => x.startsWith("doc:Call sheet day 1")), JSON.stringify(pickList));
  await js(`(() => { const b = new FormData(); b.set('bulk', JSON.stringify({ keys: ['${dk}'], action: 'unpin', to: '' })); return fetch('/f/${FILM}/library?as=${WHO}', { method: 'POST', body: b }).then(r => r.status); })()`);

  say("A short drag within the sidebar is still only a reorder");
  await open("library");
  const keys0 = await railKeys();
  const a = await centre('nav.rail .to[data-key="night-look"]');
  const b = await centre('nav.rail .to[data-key="night-look"]', 0.5);
  await drag(a, { x: b.x, y: b.y + 2 }, false);
  await wait(800);
  check("nothing leaves the sidebar", (await railKeys()).join() === keys0.join(), JSON.stringify(await railKeys()));

  say("The ⋯ does the same, for anybody without a mouse");
  await open("library");
  await find("reel");
  await openMenu(`${row("reel-notes")} .fh-lmenu > summary`);
  check("a page off the sidebar offers Add to Sidebar", (await words()).includes("Add to Sidebar"), JSON.stringify(await words()));
  await pick("Add to Sidebar");
  await wait(3000);
  check("…and it is on the sidebar", (await railKeys()).includes("reel-notes"), JSON.stringify(await railKeys()));
  await openMenu(`${row("reel-notes")} .fh-lmenu > summary`);
  check("…then offers Remove from Sidebar", (await words()).includes("Remove from Sidebar"), JSON.stringify(await words()));
  await pick("Remove from Sidebar");
  await wait(3000);
  check("…which takes it off", !(await railKeys()).includes("reel-notes"), JSON.stringify(await railKeys()));
  await shot("2-end");
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
