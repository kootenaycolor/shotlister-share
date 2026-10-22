#!/usr/bin/env node
/**
 * His home page — the films shelf — sorted and folded, driven in a real browser.
 *
 * His ask, 2026-10-05: Sort (Next Date, Name, Recently Changed, Status, and No
 * Groups) and stages that fold, on the page he lands on — **his own, and nobody
 * else's**. `checks.sh` asks the worker what each person is *sent*; this opens
 * the shelf in headless Chromium and does what he does: picks a sort from the
 * menu with the keyboard, folds a stage, searches inside a folded one, reloads,
 * and then signs in as a viewer to see that none of it is there.
 *
 * Run it with `node hub/home.mjs`; `SHOTS=<dir>` also writes a picture of each
 * state there. Local only: a throwaway bucket, and an identity that cannot work
 * anywhere but localhost.
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
const PORT = 8794, DEBUG = 9352;
const OWNER = "owner@example.com";
const VIEWER = "clara@example.com";
const SHOTS = process.env.SHOTS || "";

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(62)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(62)} FAIL — ${why}`); };
const check = (what, cond, why = "not so") => (cond ? ok(what) : no(what, why));

const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));

const day = (offset) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);
const ago = (hours) => new Date(Date.now() - hours * 3600000).toISOString();
// title, stage, shoot starts in N days (null: none), hours since refreshed, whether the viewer is on it
const FILMS = [
  ["Halcyon", "Active", 21, 30],
  ["Lets Bake", "Active", 1, 5, true],
  ["Mirrorland", "Active", 40, 200],
  ["Call Her Back", "Active", 28, 3, true],
  ["Oddity", "Active", 46, 90],
  ["Jonas on Edge", "Development", null, 400],
  ["Call Her Back Layout", "Development", null, 12],
  ["ZED", "Post", -400, 700],
  ["Daybreak", "Post", -340, 60],
  ["Static On", "Post", null, 1000],
  ["Quiet Harbor", "Archived", null, 5000],
];

const state = mkdtempSync(join(tmpdir(), "home-state-"));
const box = mkdtempSync(join(tmpdir(), "home-box-"));
const wr = join(HERE, "node_modules/.bin/wrangler");
const put = (key, body) => {
  const file = join(box, "f.bin");
  writeFileSync(file, body);
  spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
say("Putting eleven films in a local bucket…");
FILMS.forEach(([title, status, start, edited, viewer], n) => {
  const id = (0xabc0000 + n + 1).toString(16).padStart(32, "0");
  put(`p/${id}/manifest.json`, JSON.stringify({ format: 1, project: id, title, engine: "0.1.0" }));
  const front = { version: 1, status, updated: ago(edited), director: "Ava Mendes", days: [], sections: [], documents: [] };
  if (start !== null) front.shoot = { start: day(start), end: day(start + 1) };
  put(`p/${id}/front.json`, JSON.stringify(front));
  if (viewer) put(`p/${id}/people.json`, JSON.stringify({ version: 1, people: [{ email: VIEWER, role: "viewer" }], links: [], invites: [] }));
});

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:",
  "--var", "COMMIT:home-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });

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
  const open = async (who = OWNER) => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/?as=${who}` });
    await wait(1500);
  };
  const shot = async (name) => {
    if (!SHOTS) return;
    mkdirSync(SHOTS, { recursive: true });
    const r = await ask("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.result.data, "base64"));
  };
  const key = async (name) => {
    const code = { ArrowDown: 40, ArrowUp: 38, Enter: 13, Escape: 27, Tab: 9 }[name];
    for (const type of ["keyDown", "keyUp"]) {
      await ask("Input.dispatchKeyEvent", { type, key: name, code: name, windowsVirtualKeyCode: code, nativeVirtualKeyCode: code });
    }
    await wait(120);
  };
  // the cards in the order they stand, with each heading in front of its own: "[Active 5] | Lets Bake, …"
  const stand = () => js(`[...document.querySelectorAll('[data-shelf] .fh-grphead, [data-shelf] .pcard')]
    .filter(e => !e.closest('[hidden]') && !e.hidden)
    .map(e => e.classList.contains('fh-grphead') ? '[' + e.dataset.group + ' ' + e.querySelector('.gn').textContent + ']' : e.dataset.title).join(' | ')`);
  const chip = (name) => js(`[...document.querySelectorAll('.fh-chip')].find(c => c.textContent.startsWith(${JSON.stringify(name)})).click()`);
  const pickSort = async (arrows) => {
    await js(`document.querySelector('[data-ownersort]').focus(); document.querySelector('[data-ownersort]').click()`);
    // the open menu rests on the ticked item; arrows move from there
    for (let i = 0; i < Math.abs(arrows); i++) await key(arrows > 0 ? "ArrowDown" : "ArrowUp");
    await key("Enter");
  };

  say("His home page, sorted");
  await open();
  await js(`localStorage.clear()`);
  await open();
  check("the sort is a menu button, starting on Next Date", (await js(`document.querySelector('[data-ownersort]').textContent`)) === "Next Date");
  await chip("All");
  check("the stages are headings, Active first, with their counts",
    (await stand()).startsWith("[Active 5] | Lets Bake | Halcyon | Call Her Back | Mirrorland | Oddity | [Development 2]"), await stand());
  check("Next Date: soonest first, then already shot (latest first), then undated",
    (await stand()).includes("[Post 3] | Daybreak | ZED | Static On"), await stand());
  check("every heading is a button that says whether it is open",
    (await js(`[...document.querySelectorAll('.fh-grphead')].every(h => h.tagName === 'BUTTON' && h.getAttribute('aria-expanded') === 'true')`)) === true);
  await shot("1-next-date");

  await js(`document.querySelector('[data-ownersort]').click()`);
  check("the menu is a menu: four sorts and No Groups, one ticked",
    (await js(`(() => { const m = document.querySelector('.sortmenu'); const r = [...m.querySelectorAll('[role^=menuitem]')];
      return m.getAttribute('role') === 'menu' && r.map(b => b.textContent).join() === 'Next Date,Name,Recently Changed,Status,No Groups'
        && r.filter(b => b.getAttribute('aria-checked') === 'true').length === 1 && document.activeElement === r[0]; })()`)) === true);
  await wait(400);
  await shot("2-sort-menu");
  await key("Escape");
  check("Escape closes it and gives focus back to the button",
    (await js(`!document.querySelector('.sortmenu') && document.activeElement === document.querySelector('[data-ownersort]')`)) === true);
  await pickSort(1);
  check("Name, by keyboard: A to Z inside each stage", (await stand()).startsWith("[Active 5] | Halcyon | Lets Bake | Mirrorland | Call Her Back | Oddity | [Development 2] | Jonas on Edge | Call Her Back Layout"), await stand());
  await pickSort(1);
  check("Recently Changed: the newest refresh first", (await stand()).startsWith("[Active 5] | Call Her Back | Lets Bake | Halcyon | Oddity | Mirrorland"), await stand());
  await shot("3-recently-changed");
  await pickSort(1);
  check("Status keeps the stages and orders by name inside them", (await stand()).startsWith("[Active 5] | Halcyon | Lets Bake"), await stand());
  check("the button names the sort", (await js(`document.querySelector('[data-ownersort]').textContent`)) === "Status");

  say("Folding a stage");
  await pickSort(-3);
  await js(`document.querySelector('.fh-grphead[data-group="Post"]').click()`);
  check("a heading folds its films and keeps its count",
    (await stand()).endsWith("[Archived 1] | Quiet Harbor") && (await stand()).includes("[Post 3] | [Archived 1]"), await stand());
  check("…and says it is closed", (await js(`document.querySelector('.fh-grphead[data-group="Post"]').getAttribute('aria-expanded')`)) === "false");
  check("…and keeps focus, for the keyboard", (await js(`document.activeElement === document.querySelector('.fh-grphead[data-group="Post"]')`)) === true);
  await shot("4-folded");
  await open();
  check("the sort and the fold are still there after a reload",
    (await js(`document.querySelector('[data-ownersort]').textContent`)) === "Next Date"
    && (await stand()).includes("[Post 3] | [Archived 1]"), await stand());
  await js(`document.querySelector('.fh-find').value = 'sun'; document.querySelector('.fh-find').dispatchEvent(new Event('input'))`);
  check("a search finds a film in a folded stage", (await stand()) === "[Post 1] | Daybreak", await stand());
  await js(`document.querySelector('.fh-find').value = ''; document.querySelector('.fh-find').dispatchEvent(new Event('input'))`);
  check("…and the fold is back when the search is cleared", (await stand()).includes("[Post 3] | [Archived 1]"), await stand());
  await js(`document.querySelector('.fh-grphead[data-group="Post"]').click()`);
  check("a second press opens it again", (await stand()).includes("[Post 3] | Daybreak | ZED | Static On"), await stand());

  say("No Groups");
  await js(`document.querySelector('[data-ownersort]').click()`);
  await key("End");
  await key("Enter");
  check("No Groups flattens the list, in the same order",
    (await stand()) === "Lets Bake | Halcyon | Call Her Back | Mirrorland | Oddity | Daybreak | ZED | Jonas on Edge | Call Her Back Layout | Static On | Quiet Harbor", await stand());
  check("…with no headings", (await js(`document.querySelectorAll('.fh-grphead').length`)) === 0);
  await shot("5-no-groups");
  await js(`document.querySelector('[data-shelfview="list"]').click()`);
  await shot("6-no-groups-list");
  await js(`document.querySelector('[data-shelfview="grid"]').click()`);
  await open();
  check("…and it is remembered", (await js(`document.querySelectorAll('.fh-grphead').length`)) === 0 && (await stand()).startsWith("Lets Bake"));
  check("what he chose is kept in this browser, in three fields",
    (await js(`(() => { const s = JSON.parse(localStorage.getItem('shelf.v2')); return s.order === 'next' && s.flat === true && typeof s.folded === 'object'; })()`)) === true);
  await js(`document.querySelector('[data-ownersort]').click()`);
  await key("End");
  await key("Enter");
  check("No Groups, pressed again, brings the stages back", (await js(`document.querySelectorAll('.fh-grphead').length`)) === 4);

  say("The stages in List");
  await js(`document.querySelector('[data-shelfview="list"]').click()`);
  await shot("7-grouped-list");
  await js(`document.querySelector('[data-shelfview="grid"]').click()`);

  say("It stays dark, whatever the device prefers");
  await ask("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] });
  await open();
  await shot("8-light-device");
  check("a light device still gets the portal's dark page", (await js(`getComputedStyle(document.querySelector('.fh2')).backgroundColor`)) === "rgb(10, 10, 10)");
  await ask("Emulation.setEmulatedMedia", { features: [] });

  say("A phone");
  await ask("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
  await open();
  check("the controls fit a phone without sideways scrolling", (await js(`document.documentElement.scrollWidth <= window.innerWidth`)) === true);
  await shot("9-phone");
  await ask("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false });

  say("Somebody else's shelf");
  // the owner's choices are in this browser's storage; a viewer signing in here must not meet them
  await js(`localStorage.setItem('shelf.v2', JSON.stringify({ status: '', sort: 'name', view: 'grid', order: 'recent', flat: false, folded: { Active: true } }))`);
  await open(VIEWER);
  check("a viewer's shelf has none of the controls",
    (await js(`!document.querySelector('[data-owner]') && !document.querySelector('[data-ownersort]') && !document.querySelector('.fh-grphead')`)) === true);
  check("…and keeps the select it always had", (await js(`!!document.querySelector('select[data-shelfsort]')`)) === true);
  check("…its films not folded, not regrouped, and carrying nothing to sort on",
    (await js(`document.querySelectorAll('[data-shelf] > .pcard:not([hidden])').length`)) >= 1
    && (await js(`!document.querySelector('.pcard[data-next], .pcard[data-edited], .fh-grp')`)) === true);
  await shot("10-viewer");
} catch (error) {
  no("the run", String(error && error.stack || error));
}
say(`passed ${pass}, failed ${fail}`);
finish(fail ? 1 : 0);
