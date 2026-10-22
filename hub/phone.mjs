#!/usr/bin/env -S node --experimental-websocket
/**
 * The portal at phone size, photographed, in both schemes.
 *
 * ## Why
 *
 * Nothing in this repo could see a small screen. `checks.sh` reads what a page
 * *says* and cannot see a line wrap, a column collide, or a colour come out
 * white on white — every one of which shipped. The Browser pane in an agent
 * session cannot be trusted either: it reports itself hidden, which cancels
 * animations and gives a false reading of anything timed.
 *
 * So: headless Chrome, told it is an iPhone, told which colour scheme to
 * pretend, pointed at whichever hub you name. It writes one JPEG per screen and
 * says where they are; you look at them.
 *
 * ## Running it
 *
 *     hub/phone.mjs <where> [light|dark] [outdir]
 *
 * `<where>` is any address the browser can reach without signing in — a share
 * link is the honest one, because it is what a crew member gets:
 *
 *     hub/phone.mjs "https://share.your-domain.example/callherback?k=…" dark
 *
 * **Run it in both schemes.** The one that broke was light, and it broke
 * because a stylesheet meant for the front of house set `--ink` on `:root` —
 * near-white — for the whole document, which is invisible in the dark and
 * unreadable in the light.
 */
import { spawn } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const DEBUG = 9377;

const where = process.argv[2];
const scheme = process.argv[3] || "dark";
const out = process.argv[4] || join(HERE, `../build/phone-${scheme}`);
if (!where) {
  console.log("hub/phone.mjs <where> [light|dark] [outdir]");
  process.exit(1);
}

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  console.log("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

/** Every screen worth looking at, as a path hung off whatever you named. */
const SCREENS = [
  ["1-film", ""],
  ["2-bible", "/bible"],
  ["3-camera", "/camera"],
  ["4-people", "/people"],
  ["5-documents", "/documents"],
  ["6-shot-list", "/shotlist"],
  ["7-locations", "/locations"],
  ["8-boards", "/boards"],
  ["9-schedule", "/schedule"],
];

/** `?k=…` has to survive being hung off a longer path. */
function addressOf(base, path) {
  const url = new URL(base);
  url.pathname = url.pathname.replace(/\/$/, "") + path;
  return url.toString();
}

mkdirSync(out, { recursive: true });
const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
  "--disable-gpu", "--window-size=430,932", "about:blank"], { stdio: "ignore" });
try {
  let targets = null;
  for (let i = 0; i < 80 && !targets; i++) {
    await wait(150);
    try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch {}
  }
  if (!targets) throw new Error("the browser never answered — is Playwright's Chromium cached?");
  const page = targets.find((t) => t.type === "page");
  const ws = new WS(page.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
  await new Promise((ok, no) => { ws.once("open", ok); ws.once("error", no); });
  let id = 0;
  const waiting = new Map();
  ws.on("message", (m) => {
    const said = JSON.parse(m);
    if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
  });
  const ask = (method, params = {}) =>
    new Promise((ok) => { const n = ++id; waiting.set(n, ok); ws.send(JSON.stringify({ id: n, method, params })); });

  await ask("Page.enable");
  await ask("Runtime.enable");
  // An iPhone 15, near enough: 390 points across, three times the pixels, and a
  // browser that says it is Safari on iOS so anything sniffing gets the truth.
  await ask("Emulation.setDeviceMetricsOverride",
    { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
  await ask("Emulation.setTouchEmulationEnabled", { enabled: true, maxTouchPoints: 5 });
  await ask("Emulation.setEmulatedMedia",
    { features: [{ name: "prefers-color-scheme", value: scheme }] });
  await ask("Emulation.setUserAgentOverride", {
    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 " +
               "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
  });

  console.log(`${scheme}, 390×844 — ${out}`);
  for (const [name, path] of SCREENS) {
    await ask("Page.navigate", { url: addressOf(where, path) });
    // The app has an engine to fetch and a film to replay; the pages do not.
    await wait(/shotlist|locations|boards|schedule/.test(path) ? 7000 : 3200);

    // **Anything that reads white on white is worth saying out loud**, because
    // it is the one fault a picture can hide from somebody skimming.
    const looked = await ask("Runtime.evaluate", {
      returnByValue: true,
      expression: `(() => {
        const near = (a, b) => Math.abs(a - b) < 34;
        const rgb = (s) => (s.match(/\\d+/g) || []).slice(0, 3).map(Number);
        const bad = [];
        for (const el of document.querySelectorAll("h1,h2,h3,p,span,b,a,button,dt,dd,div")) {
          if (!el.firstChild || el.firstChild.nodeType !== 3) continue;
          const said = el.textContent.trim();
          if (!said) continue;
          const seen = getComputedStyle(el);
          let box = el, paper = "rgba(0, 0, 0, 0)";
          while (box && paper === "rgba(0, 0, 0, 0)") {
            paper = getComputedStyle(box).backgroundColor; box = box.parentElement;
          }
          const [r1, g1, b1] = rgb(seen.color), [r2, g2, b2] = rgb(paper);
          if ([r1, g1, b1, r2, g2, b2].some((n) => Number.isNaN(n))) continue;
          if (near(r1, r2) && near(g1, g2) && near(b1, b2)) {
            bad.push(said.slice(0, 40) + "  [" + seen.color + " on " + paper + "]");
          }
        }
        return JSON.stringify({ unreadable: [...new Set(bad)].slice(0, 6),
                                wide: document.documentElement.scrollWidth > innerWidth
                                      ? document.documentElement.scrollWidth : 0 });
      })()`,
    });
    const notes = JSON.parse(looked.result?.result?.value || "{}");

    const shot = await ask("Page.captureScreenshot",
      { format: "jpeg", quality: 80, captureBeyondViewport: true });
    if (shot.result?.data) {
      writeFileSync(join(out, `${name}.jpg`), Buffer.from(shot.result.data, "base64"));
      let line = `  ${name}`;
      if (notes.wide) line += `   spills sideways to ${notes.wide}px`;
      if (notes.unreadable?.length) line += `\n     unreadable: ${notes.unreadable.join("\n                 ")}`;
      console.log(line);
    } else {
      console.log(`  ${name}   NO PICTURE`);
    }
  }
  ws.close();
} finally {
  proc.kill();
}
