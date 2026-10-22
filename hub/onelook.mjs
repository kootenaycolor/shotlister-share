#!/usr/bin/env node
/**
 * One look everywhere (after stage 5, item 7): pictures of the portal's
 * screens, before and after, on a throwaway local bucket.
 *
 *     SHOTS=<dir> [HUB=<a hub folder to run>] node hub/onelook.mjs
 *
 * HUB defaults to this folder; point it at main's hub for the "before". Four
 * projects go in: Daybreak (the Studio fixture's real change logs) and three
 * with only a card, shooting in 12, 19 and 37 days. Each screen is taken on a
 * desk (1440x900) and a phone (390x844). Local only; never the real bucket.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, mkdirSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const HUB = process.env.HUB || HERE;
const SHELL = `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const PORT = Number(process.env.PORT || 8861), DEBUG = Number(process.env.DEBUG || 9381);
const WHO = "owner@example.com";
const SHOTS = process.env.SHOTS || join(tmpdir(), "onelook");
const FIXTURE = join(HERE, "../studio/fixtures/Daybreak.shotlist");
const say = (...w) => console.log(...w);
const day = (n) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

// Simple 20x20 marks standing in for Notion icons.
const SUN = "M10 5a5 5 0 1 0 0 10a5 5 0 1 0 0-10zM9 0h2v3H9zM9 17h2v3H9zM0 9h3v2H0zM17 9h3v2h-3z";
const HOUSE = "M10 2L1 10h3v8h5v-5h2v5h5v-8h3z";
const GIFT = "M2 7h16v4H2zM3 11h14v8H3zM9 7h2v12H9z";
const CROWN = "M2 6l4 4l4-7l4 7l4-4l-2 10H4z";
const FILMS = [
  { id: "01a02852ebb00198e46a252100000000", title: "Daybreak", logs: true,
    front: { version: 1, status: "Post", director: "Clara Ward", ratio: 2.39, mark: { path: SUN, colour: "#E8A33A" },
      days: [{ date: "2025-09-12", label: "Day 1" }], counts: {} } },
  { id: "01a02852ebb00198e46a252100000001", title: "Halcyon",
    front: { version: 1, status: "Active", director: "Ivy Lee", ratio: 1.85, mark: { path: HOUSE, colour: "#F472B6" },
      days: [{ date: day(12), label: "Day 1" }], counts: {} } },
  { id: "01a02852ebb00198e46a252100000002", title: "Call Her Back",
    front: { version: 1, status: "Active", director: "Sam Hart", ratio: 2.0, mark: { path: GIFT, colour: "#F87171" },
      days: [{ date: day(19), label: "Day 1" }], counts: { scenes: 22, shots: 71 } } },
  { id: "01a02852ebb00198e46a252100000003", title: "Oddity",
    front: { version: 1, status: "Active", director: "Dana Cole", mark: { path: CROWN, colour: "#C084FC" },
      days: [{ date: day(37), label: "Day 1" }], counts: {} } },
];

const state = mkdtempSync(join(tmpdir(), "onelook-state-"));
const box = mkdtempSync(join(tmpdir(), "onelook-box-"));
const wr = join(HERE, "node_modules/.bin/wrangler");
const put = (key, body) => {
  const file = join(box, "f.bin");
  writeFileSync(file, body);
  spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HUB, stdio: "ignore" });
};
const putFile = (key, file) => spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HUB, stdio: "ignore" });

say(`Seeding ${FILMS.length} projects (hub: ${HUB})…`);
for (const f of FILMS) {
  put(`p/${f.id}/manifest.json`, JSON.stringify({ format: 1, project: f.id, title: f.title, engine: "0.1.0" }));
  if (f.logs) {
    for (const n of readdirSync(join(FIXTURE, "changes"))) {
      if (n.endsWith(".log")) putFile(`p/${f.id}/logs/${n}`, join(FIXTURE, "changes", n));
    }
  }
  put(`p/${f.id}/front.json`, JSON.stringify(f.front));
  put(`p/${f.id}/people.json`, JSON.stringify({ version: 1, people: [], links: [], invites: [] }));
}

spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:",
  "--var", "COMMIT:onelook", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HUB, stdio: "ignore" });
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
  for (let i = 0; i < 60 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch { /* not yet */ }
  }
  if (!up) { say("the hub would not start"); finish(1); }
  const { default: WS } = await import(join(HERE, "node_modules/ws/index.js"));
  proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1440,900", "about:blank"], { stdio: "ignore" });
  let targets = null;
  for (let i = 0; i < 80 && !targets; i++) {
    await wait(150);
    try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch { /* not yet */ }
  }
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
  const js = async (e) => (await ask("Runtime.evaluate", { expression: e, returnByValue: true, awaitPromise: true })).result?.result?.value;
  const size = (w, h, mobile) => ask("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: mobile ? 2 : 1, mobile });
  mkdirSync(SHOTS, { recursive: true });
  const shot = async (name) => {
    const r = await ask("Page.captureScreenshot", { format: "png" });
    writeFileSync(join(SHOTS, `${name}.png`), Buffer.from(r.result.data, "base64"));
  };
  const open = async (path) => {
    await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}${path}${path.includes("?") ? "&" : "?"}as=${WHO}` });
    await wait(2200);
  };
  const sun = `/f/${FILMS[0].id}`;
  for (const [tag, w, h, mobile] of [["desk", 1440, 900, false], ["phone", 390, 844, true]]) {
    await size(w, h, mobile);
    await open("/");
    await shot(`${tag}-1-projects`);
    const links = await js(`[...document.querySelectorAll('nav.rail a.to, nav.rail .to a, nav.rail a')].map(a => a.getAttribute('href')).filter(Boolean)`);
    await open(sun);
    await shot(`${tag}-2-home`);
    const rail = (await js(`[...document.querySelectorAll('nav.rail a[href]')].map(a => [a.textContent.trim(), a.getAttribute('href')])`)) || [];
    const want = ["Shot List", "Camera Spec Sheet", "Library", "Schedule"];
    let n = 3;
    for (const name of want) {
      const hit = rail.find(([t]) => t.startsWith(name));
      if (!hit) continue;
      await open(hit[1].replace(/\?.*$/, ""));
      await shot(`${tag}-${n++}-${name.toLowerCase().replace(/\s+/g, "-")}`);
    }
    void links;
  }
  say(`pictures in ${SHOTS}; page errors: ${errors.length ? errors.slice(0, 3).join(" | ") : "none"}`);
  finish(0);
} catch (e) {
  say(String(e.stack || e));
  finish(1);
}
