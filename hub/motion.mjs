#!/usr/bin/env -S node --experimental-websocket
/**
 * What actually animates, in a browser that can actually see.
 *
 * ## Why this exists
 *
 * An evening was spent guessing at durations and curves because every reading
 * available was a lie. The Browser pane in an agent session reports
 * `document.visibilityState === "hidden"`, and **a hidden document cancels
 * every view transition** — so `getAnimations()` there returns the animations
 * of a transition that was thrown away a frame later. Four separate "fixes"
 * were shipped against that non-evidence, and each of them made something else
 * worse.
 *
 * A thirty-second screen recording from him found the real fault in one pass.
 * This is that, without needing him: headless Chrome reports *visible*, so the
 * transitions genuinely run, and the browser will hand over the keyframes it
 * generated — the exact pixels a thing travels between.
 *
 * ## What it tells you
 *
 * For each move it prints every `::view-transition-*` animation, its duration,
 * and — for the groups, which are the part that *travels* — the transform and
 * size it goes from and to. A morph that is working reads like this:
 *
 *     group(filmname) 420ms  (381,126) 241x48  ->  (41,16) 52x14
 *
 * A morph that is not working has no `group(…)` line at all, or one that goes
 * nowhere. That distinction is the whole reason this file exists: a transition
 * that *fires* and a transition anybody *sees* are different things, and every
 * cheap way of checking only tells you the first.
 *
 * ## Running it
 *
 *     hub/motion.mjs
 *
 * (The shebang carries `--experimental-websocket`, which node 20 needs and
 * node 22 ignores.)
 *
 * It starts its own hub on 8788 against a throwaway bucket, seeds one film with
 * an icon and a colour, drives the moves, and stops everything after. It needs
 * node's WebSocket (hence `--experimental-websocket` on node 20) and the
 * Chromium that Playwright caches; it says so plainly if either is missing
 * rather than half-working.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const OWNER = "owner@example.com";
const PORT = 8788;
const DEBUG = 9344;

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

function say(...what) {
  console.log(...what);
}

/** The film the moves are driven against: one icon, one colour, one of each. */
function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "motion-"));
  const put = (key, body) => {
    const file = join(box, "one.json");
    writeFileSync(file, body);
    spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
      "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  };
  put(`p/${FILM}/manifest.json`,
    JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
  put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
  put(`p/${FILM}/front.json`, JSON.stringify({
    version: 1, status: "Active", type: "Narrative", length: "Short",
    director: "Clara Moreau", producer: "Max Kowalski", ratio: 1.33,
    logline: "A film long enough to give the page something to hold.",
    key_image: "", note: "", look: "", shoot: { start: "2026-11-02", end: "2026-11-04" },
    mark: {
      path: "M17.5 7.5c0 4.36-4.578 7.972-7.5 10-2.922-2.028-7.5-5.64-7.5-10 0-2.669 1.819-4.375 4.063-4.375" +
            ".984 0 1.878.381 2.546 1L7.5 7.344l2.54 2.54-1.027 2.057 1.118.559 1.431-2.863-2.54-2.54c.922-1.84 " +
            "1.937-3.972 4.416-3.972 2.243 0 4.062 1.706 4.062 4.375",
      colour: "#D44C47",
    },
    camera: {}, counts: { scenes: 22, shots: 56, locations: 7, boards: 3, days: 3, pictures: 0 },
    crew: [], documents: [], pictures: { scenes: [] },
  }));
  rmSync(box, { recursive: true, force: true });
}

/** The script every page is measured with: hook the transitions, keep what ran. */
const WATCHER = `
  window.__moves = [];
  const real = document.startViewTransition.bind(document);
  document.startViewTransition = (change) => {
    const how = document.documentElement.className || "(no class)";
    const moving = real(change);
    moving.ready.then(() => {
      const running = document.getAnimations()
        .filter((a) => a.effect && a.effect.pseudoElement &&
                       a.effect.pseudoElement.includes("view-transition"));
      window.__moves.push({
        how,
        ran: running.map((a) => {
          const what = a.effect.pseudoElement.replace("::view-transition-", "");
          const ms = Math.round(a.effect.getTiming().duration);
          let travels = null;
          if (what.startsWith("group(")) {
            try {
              const [from, to] = a.effect.getKeyframes();
              if (from && from.transform) {
                const box = (k) => {
                  const m = /matrix\\(1, 0, 0, 1, (-?[\\d.]+), (-?[\\d.]+)\\)/.exec(k.transform || "");
                  const at = m ? \`(\${Math.round(+m[1])},\${Math.round(+m[2])})\` : "?";
                  return \`\${at} \${Math.round(parseFloat(k.width))}x\${Math.round(parseFloat(k.height))}\`;
                };
                const a1 = box(from), b1 = box(to);
                travels = a1 === b1 ? "stays put" : \`\${a1} -> \${b1}\`;
              }
            } catch {}
          }
          return { what, ms, travels };
        }),
      });
    }, (why) => window.__moves.push({ how, cancelled: why.name }));
    return moving;
  };
`;

async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1400,900", "about:blank"], { stdio: "ignore" });
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
    const out = await run(ask);
    ws.close();
    return out;
  } finally {
    proc.kill();
  }
}

/** One journey: open a page, do a thing, say what moved. */
async function journey(ask, { name, open, doing }) {
  await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}${open}` });
  await wait(3800);
  await ask("Runtime.evaluate", { expression: WATCHER });
  await ask("Runtime.evaluate", { expression: `(async () => { ${doing} })()`, awaitPromise: true });
  const got = await ask("Runtime.evaluate", {
    expression: "JSON.stringify(window.__moves)", returnByValue: true,
  });
  const moves = JSON.parse(got.result?.result?.value || "[]");
  say(`\n${name}`);
  if (!moves.length) return say("   nothing animated at all");
  for (const move of moves) {
    if (move.cancelled) { say(`   [${move.how}] the browser cancelled it: ${move.cancelled}`); continue; }
    say(`   [${move.how}]`);
    for (const a of move.ran.filter((a) => a.what.startsWith("group("))) {
      say(`      ${a.what.padEnd(22)} ${String(a.ms).padStart(4)}ms   ${a.travels || ""}`);
    }
    const rest = move.ran.filter((a) => !a.what.startsWith("group("))
      .map((a) => `${a.what} ${a.ms}`).sort();
    if (rest.length) say(`      and: ${[...new Set(rest)].join(", ")}`);
  }
}

const state = mkdtempSync(join(tmpdir(), "motion-state-"));
say("Putting one film in a local bucket…");
seed(state);
say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state,
   "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });
try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  const at = `/f/${FILM}`;
  const as = `?as=${OWNER}`;
  await browser(async (ask) => {
    await journey(ask, {
      name: "The film's page, into a record page — the rail should arrive",
      open: `${at}${as}`,
      doing: `document.querySelector('a[data-deep="record"][href$="/camera"]').click();
              await new Promise(r => setTimeout(r, 1200));`,
    });
    await journey(ask, {
      name: "Between two record pages — the rail must NOT move again",
      open: `${at}/camera${as}`,
      doing: `document.querySelector('a[data-deep="record"][href$="/people"]').click();
              await new Promise(r => setTimeout(r, 1200));`,
    });
    await journey(ask, {
      name: "Into Shotlister — the title and its mark travel to the corner",
      open: `${at}${as}`,
      doing: `document.querySelector('a[data-deep="app"]').click();
              await new Promise(r => setTimeout(r, 4000));`,
    });
    await journey(ask, {
      name: "Out of Shotlister — the title and its mark travel back to the big one",
      open: `${at}${as}`,
      doing: `document.querySelector('a[data-deep="app"]').click();
              await new Promise(r => setTimeout(r, 4500));
              window.__moves.length = 0;
              document.querySelector('#film a[data-deep="home"]').click();
              await new Promise(r => setTimeout(r, 1500));`,
    });
    await journey(ask, {
      name: "Out of Shotlister when you ARRIVED there — the film's page has never been here",
      open: `${at}/shotlist${as}`,
      doing: `document.querySelector('#film a[data-deep="home"]').click();
              await new Promise(r => setTimeout(r, 2500));`,
    });
    await journey(ask, {
      name: "Inside Shotlister, opening the side panel — the middle should narrow, not jump",
      open: `${at}/shotlist${as}`,
      doing: `document.querySelector('[data-panel="toggle"]').click();
              await new Promise(r => setTimeout(r, 1200));`,
    });
    await journey(ask, {
      name: "Inside Shotlister, changing mode — nothing should change size",
      open: `${at}/shotlist${as}`,
      doing: `document.querySelector('[data-mode="locations"]').click();
              await new Promise(r => setTimeout(r, 1200));`,
    });
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  say("");
}
