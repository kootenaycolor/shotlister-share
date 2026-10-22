#!/usr/bin/env -S node --experimental-websocket
/**
 * **The portal's Script page draws the shots' marks** (Ref 1568, portal half;
 * Ref 1553 made the ties) — a bar down the margin for each shot beside the
 * lines it holds, its number over the first line, its words tinted, the same
 * as the Mac's Whole Script window and the phone's Script tab.
 *
 * - the page offers Marks only when some shot holds lines, and the draft's
 *   words are in the bucket; a film with no ties offers no switch;
 * - the draft's words are answered under the Script row's door, and refused
 *   to a stranger;
 * - Marks draws the engine's own pages; each tied stretch's tinted words are
 *   exactly the words quoted; a stretch that crosses a page break is numbered
 *   once, and carries its bar onto the next page;
 * - clicking a number follows that shot, and clicking it again lets go;
 * - a newer draft that cuts a shot's words says so (Not in This Draft) and
 *   marks nothing in their place;
 * - at a phone's width the page is whole, with nothing wider than the screen.
 *
 *     hub/marks.mjs
 *
 * The scratch films are made by the Mac's connector (`mcp/`), put in a
 * throwaway bucket, and served by a hub of its own on 8794. Screenshots land
 * in /tmp (or $SHOTS). Nothing here touches a real film or the real bucket.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const TIED = "05b07c4ec1ec00000000000000000003";
const PLAIN = "05b07c4ec1ec00000000000000000004";
const PORT = 8794;
const DEBUG = 9350;
const H = `http://127.0.0.1:${PORT}`;
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

// ---- the Mac's connector, on a folder ---------------------------------------
const PATH = `${process.env.HOME}/.cargo/bin:/opt/homebrew/bin:${process.env.PATH}`;
say("Building the Mac's connector and the hub's engine…");
const built = spawnSync("cargo", ["build", "--quiet", "--manifest-path", join(ROOT, "mcp/Cargo.toml")],
  { env: { ...process.env, PATH } });
if (built.status !== 0) { say(`the connector would not build\n${built.stderr}`); process.exit(1); }
if (spawnSync(join(HERE, "build.sh"), [], { stdio: "ignore", env: { ...process.env, PATH } }).status !== 0) {
  say("the hub's engine would not build — nothing below would mean anything"); process.exit(1);
}
const MCP = join(ROOT, "mcp/target/debug/shotlister-mcp");

function folder(box, id, title) {
  const path = join(box, `${title}.shotlist`);
  mkdirSync(join(path, "changes"), { recursive: true });
  writeFileSync(join(path, "manifest.json"), JSON.stringify({ format: 1, project: id, title, engine: "0.1.0" }));
  return path;
}

function connector(path, calls, device) {
  const lines = [["open_project", { path }], ...calls].map(([name, args], i) =>
    JSON.stringify({ jsonrpc: "2.0", id: i + 1, method: "tools/call", params: { name, arguments: args } }));
  const run = spawnSync(MCP, [], { input: lines.join("\n") + "\n", env: { ...process.env, SHOTLISTER_DEVICE: device } });
  return run.stdout.toString().trim().split("\n").map((l) => JSON.parse(l)).map((r) =>
    r.error ? { error: r.error.message } : r.result.content.map((c) => c.text).join("\n"));
}

// A screenplay long enough to run onto a second page: two scenes, the first
// with a run of action that a stretch can start on page one and end on page two.
const action = (n) => `Anna crosses the kitchen to the window, number ${n}, and looks out at the long grey yard.`;
const scene = (n, heading, body) => `${n} ${heading} ${n}\n\n${body}\n`;
const first = Array.from({ length: 24 }, (_, i) => action(i + 1)).join("\n\n");
const BLUE_TEXT = [
  scene(1, "INT. KITCHEN - DAY", `${first}\n\nANNA\nMorning.`),
  scene(2, "INT. HALL - NIGHT", "BEN\nWho is there?\n\nBen stands very still."),
].join("\n");
// A newer draft with scene 2's line gone.
const NEXT_TEXT = BLUE_TEXT.replace("Who is there?", "Hello?");
// A stretch that starts on page one and ends on page two.
const ACROSS = [17, 18, 19, 20].map(action).join("\n\n");

const box = mkdtempSync(join(tmpdir(), "marks-film-"));
const made = folder(box, TIED, "Marks Check");
let said = connector(made, [
  ["add_scene", { number: "1" }], ["add_shot", { scene: "1" }], ["add_shot", { scene: "1" }],
  ["add_scene", { number: "2" }], ["add_shot", { scene: "2" }],
  ["apply_draft", { text: BLUE_TEXT, revision_name: "White", dated: "2026-09-01T00:00:00Z" }],
  ["tie_lines", { shot: "1A", text: ACROSS }],
  ["tie_lines", { shot: "1B", text: "Morning." }],
  ["tie_lines", { shot: "2A", text: "Who is there?" }],
], "marks-check-mac");
let refused = said.find((s) => s && s.error);
if (refused) { say(`the scratch film could not be made: ${refused.error}`); process.exit(1); }
const whiteStem = readdirSync(join(made, "media", "proxies")).find((n) => n.endsWith(".txt")).slice(0, 32);
said = connector(made, [
  ["apply_draft", { text: NEXT_TEXT, revision_name: "Blue", dated: "2026-10-01T00:00:00Z" }],
], "marks-check-mac");
refused = said.find((s) => s && s.error);
if (refused) { say(`the second draft could not be taken in: ${refused.error}`); process.exit(1); }
const stems = readdirSync(join(made, "media", "proxies")).filter((n) => n.endsWith(".txt")).map((n) => n.slice(0, 32));
const blueStem = stems.find((s) => s !== whiteStem);

// A film whose shots hold no lines of the screenplay: no switch, no marks.
const plainFilm = folder(box, PLAIN, "Plain Check");
said = connector(plainFilm, [
  ["add_scene", { number: "1" }], ["add_shot", { scene: "1" }],
  ["apply_draft", { text: BLUE_TEXT, revision_name: "White" }],
], "marks-check-mac");
refused = said.find((s) => s && s.error);
if (refused) { say(`the plain film could not be made: ${refused.error}`); process.exit(1); }
const plainStem = readdirSync(join(plainFilm, "media", "proxies")).find((n) => n.endsWith(".txt")).slice(0, 32);

const state = mkdtempSync(join(tmpdir(), "marks-state-"));
say("Putting the scratch films in a local bucket…");
const W = join(HERE, "node_modules/.bin/wrangler");
const put = (key, file) => spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
  "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
// A tiny, valid PDF for the older draft, so its page offers the PDF and the switch.
const pdf = join(box, "white.pdf");
writeFileSync(pdf, `%PDF-1.1\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n`);
for (const [id, path, texts] of [[TIED, made, [whiteStem, blueStem]], [PLAIN, plainFilm, [plainStem]]]) {
  put(`p/${id}/manifest.json`, join(path, "manifest.json"));
  for (const name of readdirSync(join(path, "changes")).filter((n) => n.endsWith(".log"))) put(`p/${id}/logs/${name}`, join(path, "changes", name));
  for (const stem of texts) {
    const file = readdirSync(join(path, "media", "proxies")).find((n) => n.startsWith(stem) && n.endsWith(".txt"));
    put(`p/${id}/media/${stem}.txt`, join(path, "media", "proxies", file));
  }
}
put(`p/${TIED}/media/${whiteStem}.pdf`, pdf);

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

/** One headless tab, driven over its own line. */
async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1200,900", "about:blank"], { stdio: "ignore" });
  let line;
  try {
    let up = false;
    for (let i = 0; i < 80 && !up; i++) {
      await wait(150);
      try { up = (await fetch(`http://127.0.0.1:${DEBUG}/json/version`)).ok; } catch {}
    }
    if (!up) throw new Error("the browser never answered — is Playwright's Chromium cached?");
    const t = await (await fetch(`http://127.0.0.1:${DEBUG}/json/new?about:blank`, { method: "PUT" })).json();
    line = new WS(t.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
    await new Promise((y, n) => { line.once("open", y); line.once("error", n); });
    let id = 0;
    const waiting = new Map();
    line.on("message", (m) => {
      const got = JSON.parse(m);
      if (got.id && waiting.has(got.id)) { waiting.get(got.id)(got); waiting.delete(got.id); }
    });
    const ask = (method, params = {}) =>
      new Promise((y) => { const n = ++id; waiting.set(n, y); line.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable");
    const js = async (expression) => {
      const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return got.result?.result?.value;
    };
    const size = (width, height, mobile) => ask("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile });
    const go = async (url) => { await ask("Page.navigate", { url }); await wait(3500); };
    const shot = async (name) => {
      const got = await ask("Page.captureScreenshot", { format: "png" });
      writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
      say(`  → ${join(shots, name)}`);
    };
    return await run({ ask, js, size, go, shot });
  } finally {
    if (line) line.close();
    proc.kill();
  }
}

/** Wait until the page says something, or give up. */
const until = async (js, expression, tries = 40) => {
  for (let i = 0; i < tries; i++) {
    if (await js(expression)) return true;
    await wait(300);
  }
  return false;
};
const norm = (s) => String(s || "").replace(/\s+/g, " ").trim();

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  say("\n  the draft's words");
  let r = await fetch(`${H}/f/${TIED}/script.txt?draft=${whiteStem}`);
  check("an editor is given the draft's words", r.ok && (await r.text()) === BLUE_TEXT, `status ${r.status}`);
  r = await fetch(`${H}/f/${TIED}/script.txt?draft=${whiteStem}&as=stranger@example.com`);
  check("a person not on the film is not", r.status >= 400 && r.status < 500, `status ${r.status}`);
  r = await fetch(`${H}/f/${TIED}/script.txt?draft=${"0".repeat(32)}`);
  check("a draft the film does not have is not found", r.status === 404, `status ${r.status}`);

  await browser(async ({ js, size, go, shot }) => {
    say("\n  the older draft, which has its PDF");
    await size(1200, 900, false);
    await go(`${H}/f/${TIED}/script?draft=${whiteStem}`);
    check("a film with ties offers PDF and Marks", (await js(`document.querySelectorAll("[data-sview]").length`)) === 2, "no switch");
    check("…and opens on the PDF", await js(`!document.querySelector(".reader").hidden && document.querySelector("[data-marks]").hidden`), "marks showing");
    await shot("marks-0-pdf.png");
    await js(`document.querySelector('[data-sview="marks"]').click()`);
    check("Marks draws the draft's pages", await until(js, `document.querySelectorAll(".markpage").length >= 2`), "no pages");
    const pages = await js(`document.querySelectorAll(".markpage").length`);
    say(`    (${pages} pages)`);
    check("the PDF steps aside", await js(`document.querySelector(".reader").hidden`), "still there");

    const ids = (n) => js(`JSON.stringify([...document.querySelectorAll('.mnum b')].filter((b) => b.textContent === "${n}").map((b) => b.dataset.shot))`).then(JSON.parse);
    const numbers = async () => JSON.parse(await js(`JSON.stringify([...document.querySelectorAll('.mnum b')].map((b) => b.textContent).sort())`));
    const [a1] = await ids("1A");
    const words = (id) => js(`[...document.querySelectorAll('mark.mt[data-shots~="${id}"]')].map((m) => m.textContent).join(" ")`);

    check("each shot's number is drawn once, though 1A crosses a page", JSON.stringify(await numbers()) === JSON.stringify(["1A", "1B", "2A"]), JSON.stringify(await numbers()));
    check("1A's tinted words are the words it holds", norm(await words(a1)) === norm(ACROSS), norm(await words(a1)));
    const pagesOfBar = JSON.parse(await js(`JSON.stringify([...new Set([...document.querySelectorAll('.mbar[data-shot="${a1}"]')].map((b) => b.closest(".markpage").dataset.page))])`));
    check("…its bar runs down page 1 and on down page 2", JSON.stringify(pagesOfBar) === JSON.stringify(["1", "2"]), JSON.stringify(pagesOfBar));
    check("…and starts under its own number, not the next page's",
      (await js(`document.querySelectorAll('.markpage[data-page="2"] .mnum b[data-shot="${a1}"]').length`)) === 0, "numbered again");

    await js(`document.querySelector('.mnum b[data-shot="${a1}"]').scrollIntoView({ block: "center" })`);
    await wait(300);
    await shot("marks-1-desktop.png");

    await js(`document.querySelector('.mnum b[data-shot="${a1}"]').click()`);
    const lit = JSON.parse(await js(`JSON.stringify([...document.querySelectorAll(".markpages .f")].map((e) => (e.dataset.shot || e.dataset.shots).split(" ")[0]))`));
    check("clicking a number follows that shot: only its marks go to the accent", lit.length > 3 && lit.every((x) => x === a1), JSON.stringify(lit.slice(0, 4)));
    await shot("marks-2-followed.png");
    await js(`document.querySelector('.mnum b[data-shot="${a1}"]').click()`);
    check("clicking it again lets go", (await js(`document.querySelectorAll(".markpages .f").length`)) === 0, "still lit");

    say("\n  a phone");
    await size(390, 844, true);
    await go(`${H}/f/${TIED}/script?draft=${whiteStem}`);
    await js(`document.querySelector('[data-sview="marks"]').click()`);
    check("the phone draws the pages too", await until(js, `document.querySelectorAll(".markpage").length >= 2`), "no pages");
    const wide = await js(`JSON.stringify({ doc: document.documentElement.scrollWidth, right: Math.max(...[...document.querySelectorAll(".markpage")].map((p) => p.getBoundingClientRect().right)), left: Math.min(...[...document.querySelectorAll(".markpage")].map((p) => p.getBoundingClientRect().left)), fs: parseFloat(getComputedStyle(document.querySelector(".markpage")).fontSize) })`);
    const w = JSON.parse(wide);
    check("a page is whole across the phone, nothing wider than the screen", w.doc <= 391 && w.right <= 391 && w.left >= 0, wide);
    check("…and its type is still readable", w.fs >= 8, wide);
    await js(`document.querySelector('.mnum b').scrollIntoView({ block: "center" })`);
    await wait(300);
    await shot("marks-3-phone.png");

    say("\n  the newer draft, which has no PDF and cuts a shot's words");
    await size(1200, 900, false);
    await go(`${H}/f/${TIED}/script`);
    check("with no PDF to switch from, the marks are the page", await until(js, `document.querySelectorAll(".markpage").length >= 2`) && (await js(`document.querySelectorAll("[data-sview]").length`)) === 0, "no pages, or a switch");
    const lost = norm(await js(`(document.querySelector(".marklost") || {}).textContent`));
    check("it says whose words are not in this draft", /2A/.test(lost) && /Who is there\?/.test(lost), lost);
    check("…and marks nothing in their place", JSON.stringify(await numbers()) === JSON.stringify(["1A", "1B"]), JSON.stringify(await numbers()));
    await shot("marks-4-newer.png");

    say("\n  a film whose shots hold no lines");
    await go(`${H}/f/${PLAIN}/script`);
    check("no switch and no marks", (await js(`document.querySelectorAll("[data-sview],.markpage,[data-marks]").length`)) === 0, "offered");
  });
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
