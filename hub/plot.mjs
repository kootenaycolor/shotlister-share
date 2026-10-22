#!/usr/bin/env -S node --experimental-websocket
/**
 * **The lighting plot on the portal** (his ask, 2026-10-03: *"make sure this
 * all works in the web portal"*) — pressed in a real browser: seven named
 * tools, the Lamp tool's marks, lights put down by clicking, one bar per
 * kind, a kind named and a Note typed on the plan, the sheet's legend and
 * notes by the plan, one label for two lamps, Words, the sheet Print draws
 * (Back to Paper, Batch 2); then the film read again to see the server kept
 * every edit.
 *
 *     hub/plot.mjs
 *
 * Its own hub on 8797 and browser on 9352; photographs land in /tmp, or
 * wherever SHOTS says. Builds the browser half first (`build.sh`).
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a00b57e8790941866a989900000000";
const FIXTURE = join(HERE, "../studio/fixtures/Daybreak.shotlist");
const PORT = 8797;
const DEBUG = 9352;
const shots = process.env.SHOTS || tmpdir();

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(60)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(60)} FAIL — ${why}`); };
const check = (what, good, why) => (good ? ok(what) : no(what, why));

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

say("Building the browser half…");
if (spawnSync(join(HERE, "build.sh"), { stdio: "ignore" }).status !== 0) { say("the browser half would not build"); process.exit(1); }

function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const put = (key, file) =>
    spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  put(`p/${FILM}/manifest.json`, join(FIXTURE, "manifest.json"));
  for (const name of readdirSync(join(FIXTURE, "changes"))) if (name.endsWith(".log")) put(`p/${FILM}/logs/${name}`, join(FIXTURE, "changes", name));
  // The Film Set Objects pictures the plan stands its pieces on, so the
  // photographs show a camera body and a lamp, not a broken picture.
  spawnSync(join(HERE, "fso.sh"), ["--local", state], { cwd: HERE, stdio: "ignore" });
}

async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox", "--disable-gpu", "--window-size=1400,900", "about:blank"], { stdio: "ignore" });
  try {
    let targets = null;
    for (let i = 0; i < 80 && !targets; i++) {
      await wait(150);
      try { targets = await (await fetch(`http://127.0.0.1:${DEBUG}/json`)).json(); } catch {}
    }
    if (!targets) throw new Error("the browser never answered — is Playwright's Chromium cached?");
    const page = targets.find((t) => t.type === "page");
    const ws = new WS(page.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
    await new Promise((y, n) => { ws.once("open", y); ws.once("error", n); });
    let id = 0;
    const waiting = new Map();
    const thrown = [];
    ws.on("message", (m) => {
      const said = JSON.parse(m);
      if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
      if (said.method === "Runtime.exceptionThrown") thrown.push(said.params.exceptionDetails.exception?.description || said.params.exceptionDetails.text);
    });
    const ask = (method, params = {}) => new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable");
    await ask("Runtime.enable");
    await ask("Emulation.setDeviceMetricsOverride", { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });
    return await run(ask, thrown).finally(() => ws.close());
  } finally {
    proc.kill();
  }
}

const state = mkdtempSync(join(tmpdir(), "diagram-state-"));
say("Putting Daybreak in a local bucket…");
seed(state);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
const hub = spawn(join(HERE, "node_modules/.bin/wrangler"),
  ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:"], { cwd: HERE, stdio: "ignore" });

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  await browser(async (ask, thrown) => {
    const js = async (expression) => {
      const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return got.result?.result?.value;
    };
    const P = async (expr) => { const t = await js(`JSON.stringify(${expr})`); try { return JSON.parse(t); } catch { return null; } };
    let edits = true;
    const open = async () => {
      await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}/f/${FILM}/diagrams?as=owner@example.com` });
      for (let i = 0; i < 40; i++) { await wait(250); if (await js(`!!(window.shotlisterPlan && (document.querySelector('.planpic > svg') || document.querySelector('[data-pedit]')))`)) break; }
      await wait(300);
      // The page opens to look at (his ask, 2026-10-02); these checks edit.
      if (edits) { await js(`(document.querySelector('[data-pedit]:not(.on)') || { click() {} }).click()`); await wait(400); }
    };
    const shot = async (name) => {
      const got = await ask("Page.captureScreenshot", { format: "png" });
      writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
      say(`    → ${join(shots, name)}`);
    };
    const mods = (m = {}) => (m.alt ? 1 : 0) | (m.meta ? 4 : 0) | (m.shift ? 8 : 0);
    const mouse = (type, x, y, m = {}) => ask("Input.dispatchMouseEvent", { type, x, y, button: type === "mouseMoved" && !m.held ? "none" : "left", buttons: m.held || type === "mousePressed" ? 1 : 0, clickCount: 1, modifiers: mods(m) });
    const click = async (x, y, m = {}) => { await mouse("mouseMoved", x, y, m); await mouse("mousePressed", x, y, m); await mouse("mouseReleased", x, y, m); await wait(150); };
    const drag = async (x1, y1, x2, y2, m = {}) => {
      await mouse("mouseMoved", x1, y1, m); await mouse("mousePressed", x1, y1, m);
      for (let i = 1; i <= 8; i++) { await mouse("mouseMoved", x1 + ((x2 - x1) * i) / 8, y1 + ((y2 - y1) * i) / 8, { ...m, held: true }); await wait(16); }
      await mouse("mouseReleased", x2, y2, m); await wait(200);
    };
    const CODES = { Escape: 27, Enter: 13, Delete: 46, ArrowRight: 39 };
    const key = async (k, m = {}) => {
      const text = k.length === 1 && !m.meta ? k : undefined;
      await ask("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", key: k, windowsVirtualKeyCode: CODES[k] || k.toUpperCase().charCodeAt(0), text, modifiers: mods(m) });
      await ask("Input.dispatchKeyEvent", { type: "keyUp", key: k, windowsVirtualKeyCode: CODES[k] || k.toUpperCase().charCodeAt(0), modifiers: mods(m) });
      await wait(120);
    };
    const els = () => P(`shotlisterPlan.els()`);
    const barText = () => js(`document.querySelector('.planfloat').innerText.replace(/\\s+/g,' ')`);
    const menuText = () => js(`[...document.querySelectorAll('.planmenu')].map((m) => m.innerText.replace(/\\s+/g,' ')).join(' / ')`);
    const rightClick = async (x, y) => {
      await mouse("mouseMoved", x, y);
      await ask("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "right", buttons: 2, clickCount: 1 });
      await ask("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "right", buttons: 0, clickCount: 1 });
      await wait(200);
    };
    const handles = () => P(`shotlisterPlan.handles()`);
    const at = (x, y) => P(`shotlisterPlan.at(${x}, ${y})`);
    const plan = () => js(`document.querySelector('.planvp').focus()`);
    const tool = (k) => js(`document.querySelector('[data-ptool=${k}]').click()`);
    const clear = async () => { await plan(); await key("a", { meta: true }); await key("Delete"); await wait(1500); await open(); await plan(); };
    const settled = async () => { for (let i = 0; i < 40; i++) { const s = await P(`shotlisterPlan.state()`); if (s && !s.pending) break; await wait(150); } await wait(900); };

    const typeIn = async (text) => { await ask("Input.insertText", { text }); await wait(120); };
    const menuPick = async (label) => js(`(() => { const b = [...document.querySelectorAll('.planmenu button')].find((x) => (x.querySelector('span') || x).textContent.trim() === ${JSON.stringify(label)}); if (b) b.click(); return !!b; })()`);
    const tab = (k) => js(`(document.querySelector('[data-ptab=${k}]') || { click() {} }).click()`);
    const openTab = () => js(`(document.querySelector('[data-ptab][aria-selected=true]') || {}).dataset ? document.querySelector('[data-ptab][aria-selected=true]').dataset.ptab : ''`);
    const typing = () => js(`(() => { const t = document.querySelector('.plantype'); return t && document.activeElement === t ? t.getAttribute('aria-label') : ''; })()`);
    const pickIds = async (ids) => { await js(`shotlisterPlan.pick(${JSON.stringify(ids)})`); await wait(300); };

    await open();
    // ---- seven named tools (Back to Paper, Batch 2, design/32 item 6) -------
    const tools = await P(`[...document.querySelectorAll('.plantools > [data-ptool]')].map((b) => b.dataset.ptool)`);
    const names = await P(`[...document.querySelectorAll('.plantools > [data-ptool] span')].map((n) => n.textContent)`);
    const more = await P(`[...document.querySelectorAll('.pmore [data-ptool]')].map((b) => b.dataset.ptool)`);
    check("seven tools across the top", JSON.stringify(tools) === JSON.stringify(["select", "light", "frame", "camera", "text", "arrow", "pen"]), JSON.stringify(tools));
    check("each with its name under it: Select, Lamp, Frame, Camera, Words, Arrow, Draw", JSON.stringify(names) === JSON.stringify(["Select", "Lamp", "Frame", "Camera", "Words", "Arrow", "Draw"]), JSON.stringify(names));
    check("Plot's other tools wait under More", ["connector", "measure", "track", "cast"].every((k) => (more || []).includes(k)) && !(more || []).includes("note") && !(more || []).includes("wall"), JSON.stringify(more));
    // ---- Set · Plot (Batch 3, Ref 1498) -------------------------------------
    const layerSw = await P(`[...document.querySelectorAll('.plantools [data-player]')].map((b) => b.textContent + (b.classList.contains('on') ? '*' : ''))`);
    check("one switch at the left: Set · Plot, on Plot", JSON.stringify(layerSw) === JSON.stringify(["Set", "Plot*"]), JSON.stringify(layerSw));
    // The dots follow the Grid switch on either layer (his note, 2026-10-05).
    check("the grid's dots on Plot too while Grid is on", await js(`!!document.querySelector('.planpic > svg rect[style*="-dots)"]')`), "no dots on Plot");
    await shot("plot-tools.png");
    await js(`document.querySelector('[data-player=set]').click()`); await wait(400);
    const setNames = await P(`[...document.querySelectorAll('.plantools > [data-ptool] span')].map((n) => n.textContent)`);
    check("Set's tools: Select, Wall, Door, Window, Street, Piece, Cast, Trace", JSON.stringify(setNames) === JSON.stringify(["Select", "Wall", "Door", "Window", "Street", "Piece", "Cast", "Trace"]), JSON.stringify(setNames));
    check("faint dots behind the set, not graph paper", await js(`!!document.querySelector('.planpic > svg pattern[id$="-dots"] circle') && !!document.querySelector('.planpic > svg rect[style*="-dots)"]')`), "no dots");
    const faded = await js(`(() => { const ids = (shotlisterPlan.els ? shotlisterPlan.els() : []).filter((e) => e.layer === 'plot').map((e) => e.id); const n = ids.length ? document.querySelector('.planpic > svg [data-el="' + ids[0] + '"]') : null; return n ? Number(n.getAttribute('opacity')) : -1; })()`);
    check("the plot fades while setting", faded === -1 || (faded > 0 && faded <= 0.2), String(faded));
    await shot("plot-set.png");
    await plan(); await key("l"); await wait(400);
    check("a plot tool's key goes back to Plot", await js(`document.querySelector('[data-player=plot]').classList.contains('on')`), "still on Set");
    await tool("select");

    // ---- the Lamp tool: marks as pictures, click to put lights down ---------
    await plan();
    await tool("light");
    await wait(300);
    check("the Lamp tool opens its marks, as pictures", (await js(`document.querySelectorAll('.planfloat.marks [data-parm]').length`)) >= 16, "no mark palette");
    const named = await P(`[...document.querySelectorAll('.planfloat.marks .pmarks.named .pmark small')].map((n) => n.textContent)`);
    // No Arrow: an arrow is not a lighting unit (his note, 2026-10-05).
    check("the palette names its seven marks", JSON.stringify(named) === JSON.stringify(["Chevron", "Wedge", "Bar", "Panel", "Ring", "Dot", "Square"]), JSON.stringify(named));
    const card = await js(`getComputedStyle(document.querySelector('.planfloat.marks')).backgroundColor`);
    check("on an opaque card", /^rgb\(/.test(card || ""), card);
    const lettersShown = () => js(`(() => { const r = document.querySelector('.planfloat.marks .pmarks.letters'); return !!r && getComputedStyle(r).display !== 'none'; })()`);
    check("the lettered circles wait behind Letters", !(await lettersShown()), "letters in the first view");
    await js(`document.querySelector('.planfloat.marks [data-pletters]').click()`); await wait(150);
    check("Letters shows them", await lettersShown(), "Letters did nothing");
    await js(`document.querySelector('.planfloat.marks [data-pletters]').click()`); await wait(150);
    const before = (await els()).length;
    for (const [x, y] of [[500, 560], [760, 640], [620, 760]]) { await click(x, y); await settled(); }
    let lamps = (await els()).filter((e) => e.kind === "light");
    check("three clicks put down three lights", (await els()).length === before + 3 && lamps.length >= 3, `${(await els()).length - before} new`);
    check("each a mark, no fixture", lamps.slice(0, 3).every((e) => e.mark === "chevron" && e.sym === "" && /^chevron\|added\|/.test(e.look || "")), JSON.stringify(lamps.map((e) => [e.mark, e.sym, e.look])));

    // ---- one bar per kind (design/32 item 8) -----------------------------------
    await tool("select");
    const ids = lamps.slice(0, 3).map((e) => e.id);
    const [lx, ly] = await at(lamps[0].x, lamps[0].y);
    await click(lx, ly); await wait(300);
    let bar = (await barText()) || "";
    check("a lamp's bar: Symbol, Name, Count, Note, Gel, More", ["Symbol", "Name", "Count", "Note", "Gel", "More"].every((w) => bar.includes(w)) && !bar.includes("Off"), bar);
    check("no down arrows on More", !/[▾▸]/.test(bar), bar);
    check("picking does not open Details", (await openTab()) !== "details", await openTab());
    await shot("plot-lamp-bar.png");
    await rightClick(lx, ly);
    const rmenu = (await menuText()) || "";
    check("right-click is More's menu: Spread, Swap…, Hide Label, Details…, Delete", ["Spread", "Swap…", "Hide Label", "Details…", "Delete"].every((w) => rmenu.includes(w)), rmenu);
    check("and never Name Size or Bold (Ref 1506)", !/Bold|Smaller|Larger|Name Size/.test(rmenu), rmenu);
    await key("Escape"); await wait(150);
    await js(`document.querySelector('.planfloat [data-pa=more]').click()`); await wait(200);
    await menuPick("Details…"); await wait(300);
    const side = (await js(`document.querySelector('.pdetails') ? document.querySelector('.pdetails').innerText.replace(/\\s+/g,' ') : ''`)) || "";
    check("More › Details… opens Details: Film Light, Practical, Existing, Symbol, Name, Count, Note", ["Film Light", "Practical", "Existing", "Symbol", "Name", "Count", "Note"].every((w) => side.includes(w)), side);
    check("a lamp is offered Opacity in More (Ref 1505), never Name Size or Bold", /Opacity/.test(rmenu) && !/Bold|Smaller/.test(side), rmenu);
    check("and the bar steps aside while Details is open", !(await js(`document.querySelector('.planfloat').classList.contains('bar')`)), "bar still drawn");
    await shot("plot-light-details.png");
    await js(`[...document.querySelectorAll('[data-pset=light_type]')].find((b) => b.textContent === 'Practical').click()`);
    await settled();
    let one = (await els()).find((e) => e.id === ids[0]);
    check("Practical makes it a practical", one && one.practical === true && !one.mark_ink && /\|practical\|/.test(one.look || ""), JSON.stringify(one && [one.practical, one.mark_ink, one.look]));
    const practicalInk = await js(`[...document.querySelectorAll('.planpic > svg [data-el="${ids[0]}"]:not([data-part="label"])')].flatMap((n) => [n, ...n.querySelectorAll('*')]).map((n) => { const c = getComputedStyle(n); return c.stroke + ' ' + c.fill; }).join(' / ')`);
    check("in amber, as practicals are (his calls, 2026-10-05)", /224, 138, 0/.test(practicalInk || ""), practicalInk);
    await tab("shots"); await wait(200);
    bar = (await barText()) || "";
    check("a practical's bar has Off", /\bOff\b/.test(bar), bar);
    await js(`[...document.querySelectorAll('.planfloat [data-pa=symbol]')][0].click()`); await wait(250);
    check("Symbol opens the named marks with Film Light · Practical · Existing on top", (await js(`[...document.querySelectorAll('.plansym [data-psymtype]')].map((b) => b.textContent).join(',')`)) === "Film Light,Practical,Existing" && (await js(`document.querySelectorAll('.plansym .pmark.named').length`)) === 7, await js(`document.querySelector('.plansym') ? document.querySelector('.plansym').innerText : 'none'`));
    await shot("plot-symbol.png");
    await js(`[...document.querySelectorAll('.plansym [data-psymtype]')].find((b) => b.textContent === 'Film Light').click()`); await settled();
    await key("Escape"); await wait(150);

    // ---- the legend on the sheet, and Name typed on the plan ------------------
    await key("Escape"); await wait(300);
    // The sheet on screen (the Mac's DiagramPage): the plan on its page, the
    // legend's lines on the paper under it, each pressed where it stands.
    const pressLine = async (test) => { const l = ((await P(`shotlisterPlan.lines()`)) || []).find(test); if (l && l.x !== null) await click(l.x, l.y); await wait(300); return l; };
    const lines = await P(`shotlisterPlan.lines()`);
    check("with nothing picked, the sheet's legend is on the page", (lines || []).some((l) => l.kind === "legend" && l.count === 3 && l.x !== null), JSON.stringify(lines));
    check("and no bar", !(await js(`document.querySelector('.planfloat').classList.contains('bar')`)), "a bar");
    await pressLine((l) => l.kind === "legend" && l.count === 3);
    check("a legend line picks every lamp of that kind", JSON.stringify((await P(`shotlisterPlan.picks()`)).slice().sort()) === JSON.stringify(ids.slice().sort()), JSON.stringify(await P(`shotlisterPlan.picks()`)));
    bar = (await barText()) || "";
    check("and its bar is 3 Lamps: Symbol, Name, Share Label", /3 Lamps/.test(bar) && ["Symbol", "Name", "Share Label"].every((w) => bar.includes(w)), bar);
    await shot("plot-legend-pick.png");
    await js(`document.querySelector('.planfloat [data-pa=name]').click()`); await wait(250);
    check("Name puts the cursor in the words on the plan, no box", (await typing()) === "Name" && (await js(`getComputedStyle(document.querySelector('.plantype')).borderTopWidth`)) === "0px", await typing());
    await typeIn("2K Blonde");
    await shot("plot-typing-name.png");
    await key("Enter"); await settled();
    const legend = await P(`shotlisterPlan.legend()`);
    check("the kind is named 2K Blonde", (legend || []).some((r) => r.named && r.name === "2K Blonde" && r.count >= 3), JSON.stringify(legend));
    const words = await js(`[...document.querySelectorAll('.planpic > svg text')].map((t) => t.textContent).join(' | ')`);
    check("every chevron is called 2K BLONDE on the plan", (words.match(/2K BLONDE/g) || []).length >= 3, words.slice(0, 300));
    check("and the legend says 2K BLONDE ×3", (await P(`shotlisterPlan.words()`) || "").includes("2K BLONDE ×3"), await P(`shotlisterPlan.words()`));
    const ink = await P(`[...document.querySelectorAll('.planpic > svg text')].filter((t) => /2K BLONDE/.test(t.textContent)).map((t) => { const c = getComputedStyle(t); return [c.fill, c.fontWeight]; })`);
    // A Name in its mark's colour (his call, 2026-10-05): red, a practical's deeper amber.
    check("callouts in their mark's colour, regular weight", (ink || []).length >= 3 && ink.every(([f, w]) => (f === "rgb(180, 35, 24)" || f === "rgb(163, 94, 0)") && Number(w) === 400), JSON.stringify(ink));

    // ---- a Note typed on the plan; Share Label keeps it ---------------------
    await pickIds([ids[0]]);
    await plan(); await key("Enter"); await wait(250);
    check("Return on a lamp types its Note on the plan", (await typing()) === "Note", await typing());
    await typeIn("Uplight Trees"); await key("Enter"); await settled();
    check("the Note is kept", ((await els()).find((e) => e.id === ids[0]) || {}).label === "Uplight Trees", JSON.stringify((await els()).find((e) => e.id === ids[0])));
    await pickIds(ids.slice(0, 2));
    const hasShare = await js(`!!document.querySelector('.planfloat [data-pa=sharelabel]')`);
    check("two lamps picked offer Share Label", hasShare, await barText());
    check("and nothing is called samelamp", !(await js(`!!document.querySelector('[data-pdo=samelamp],[data-pa=samelamp]')`)), "samelamp");
    if (hasShare) { await js(`document.querySelector('.planfloat [data-pa=sharelabel]').click()`); await settled(); }
    const label = (await els()).find((e) => e.kind === "text" && e.shown);
    check("Share Label makes one label for both, the note under the name", label && /2× 2K BLONDE\nUPLIGHT TREES/.test(label.shown), JSON.stringify(label && label.shown));
    bar = (await barText()) || "";
    check("its bar: Shared Label · 2 Lamps, Symbol, Name, Note, Gel", /Shared Label · 2 Lamps/.test(bar) && ["Symbol", "Name", "Note", "Gel"].every((w) => bar.includes(w)), bar);
    await shot("plot-same-lamp.png");

    // ---- Symbol from the bar: a panel, a tube ---------------------------------
    await pickIds([ids[2]]);
    await js(`document.querySelector('.planfloat [data-pa=symbol]').click()`); await wait(250);
    // (The page's tooltips take `title` off; the named marks say their names.)
    const titles = (await js(`[...document.querySelectorAll('.plansym .pmark small')].map((b) => b.textContent).join(',')`)) || "";
    check("the mark is named Panel, not Double Bar", /Panel/.test(titles) && !/Double Bar/.test(titles), titles);
    await js(`document.querySelector('.plansym [data-psym="double-bar|added|solid"]').click()`); await settled();
    const panel = (await els()).find((e) => e.id === ids[2]);
    check("a lamp can be a Panel", panel && panel.mark === "double-bar", JSON.stringify(panel && panel.mark));
    await pickIds([ids[0]]);
    await js(`document.querySelector('.planfloat [data-pa=symbol]').click()`); await wait(250);
    await js(`document.querySelector('.plansym [data-psym="bar|added|solid"]').click()`); await settled();
    const nowEls = await els();
    check("a tube is a Bar", nowEls.find((e) => e.id === ids[0]).mark === "bar", "not a bar");
    // A shared label is not one unit (his call, 2026-10-05): the other lamp keeps its own symbol.
    check("and the lamp under the same label keeps its own symbol", nowEls.find((e) => e.id === ids[1]).mark === "chevron", nowEls.find((e) => e.id === ids[1]).mark);

    // ---- a connector from a label to a lamp ties them ------------------------
    const tied = (await els()).find((e) => e.id === ids[2]);
    check("the third lamp has its own label to begin with", !tied.tie_to, JSON.stringify(tied.tie_to));
    await tool("connector");
    const [tx, ty] = await at(label.x, label.y);
    const [px, py] = await at(panel.x, panel.y);
    await mouse("mouseMoved", tx, ty); await mouse("mousePressed", tx, ty);
    for (let i = 1; i <= 8; i++) { await mouse("mouseMoved", tx + ((px - tx) * i) / 8, ty + ((py - ty) * i) / 8, { held: true }); await wait(16); }
    await wait(300);
    await mouse("mouseReleased", px, py); await wait(200); await settled();
    const joined = (await els()).find((e) => e.id === ids[2]);
    check("a connector dragged from the label to the lamp ties it to that label", joined.tie_to === label.id, JSON.stringify([joined.tie_to, label.id]));
    check("and it keeps its own symbol (2026-10-05)", joined.mark === "double-bar", joined.mark);
    check("and no stray line is left behind", !(await els()).some((e) => e.kind === "arrow"), "an arrow was drawn");

    // ---- Hide Label on a shared label (it obeys it now) -----------------------
    await tool("select");
    await pickIds([label.id]);
    await js(`document.querySelector('.planfloat [data-pa=more]').click()`); await wait(200);
    await menuPick("Hide Label"); await settled();
    check("Hide Label hides a shared label", !(await js(`!!document.querySelector('.planpic > svg text[data-el="${label.id}"]')`)), "still drawn");
    await pickIds([label.id]);
    await js(`document.querySelector('.planfloat [data-pa=more]').click()`); await wait(200);
    const shownMenu = await menuText();
    await menuPick("Show Label"); await settled();
    check("and Show Label brings it back", await js(`!!document.querySelector('.planpic > svg text[data-el="${label.id}"]')`), `not back · ${shownMenu}`);

    // ---- the tubes named from their legend line ---------------------------------
    // All three made tubes, as one Name on one symbol is one legend line.
    await js(`shotlisterPlan.edit({ op: "update", ids: ${JSON.stringify(ids)}, set: { mark: "bar", mark_fill: "solid" } })`); await settled();
    await key("Escape"); await wait(250);
    await pressLine((l) => l.kind === "legend" && l.count === 3);
    await js(`document.querySelector('.planfloat [data-pa=name]').click()`); await wait(250);
    await typeIn("Titan Tube"); await key("Enter"); await settled();
    check("the three tubes are named from their legend line", ((await js(`[...document.querySelectorAll('.planpic > svg text')].map((t) => t.textContent).join(' | ')`)) || "").includes("3× TITAN TUBE"), await js(`[...document.querySelectorAll('.planpic > svg text')].map((t) => t.textContent).join(' | ')`));

    // Double-click on the words: the cursor is in them, on the plan (his call F).
    const lb = await P(`(() => { const t = document.querySelector('.planpic > svg text[data-el="${label.id}"] tspan'); const r = t.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()`);
    await key("Escape"); await wait(150);
    await click(lb[0], lb[1]); await click(lb[0], lb[1]); await wait(300);
    check("a double-click on a label's first line types its Name there", (await typing()) === "Name", await typing());
    await shot("plot-typing-label.png");
    await key("Escape"); await wait(200);
    check("and Escape leaves it as it was", ((await js(`[...document.querySelectorAll('.planpic > svg text')].map((t) => t.textContent).join(' | ')`)) || "").includes("3× TITAN TUBE") && !(await js(`!!document.querySelector('.plantype')`)), "changed");

    // ---- a label moves alone; its lamps stay ---------------------------------------
    const before3 = (await els()).filter((e) => ids.includes(e.id)).map((e) => [e.id, e.x, e.y]);
    const lab = (await els()).find((e) => e.id === label.id);
    const [mx, my] = await at(lab.x, lab.y);
    await key("Escape"); await wait(200);
    await drag(mx, my, mx + 60, my + 40); await settled();
    const after3 = (await els()).filter((e) => ids.includes(e.id));
    const stayed = after3.every((e) => { const b = before3.find((x) => x[0] === e.id); return Math.abs(e.x - b[1]) < 0.01 && Math.abs(e.y - b[2]) < 0.01; });
    check("dragging the label leaves its lamps where they are", stayed, JSON.stringify([before3, after3.map((e) => [e.x, e.y])]));

    // ---- a string of lamps, from More ---------------------------------------
    await pickIds([ids[2]]);
    await js(`document.querySelector('.planfloat [data-pa=more]').click()`); await wait(200);
    await menuPick("Own Label"); await settled();
    await pickIds([ids[2]]);
    await js(`document.querySelector('.planfloat [data-pa=more]').click()`); await wait(200);
    await menuPick("Spread"); await wait(200);
    await menuPick("Ring"); await settled();
    const ringed = (await els()).find((e) => e.id === ids[2]);
    check("More › Spread › Ring makes one lamp a ring of eight", ringed && ringed.spread === "ring" && ringed.count >= 8, JSON.stringify(ringed && [ringed.spread, ringed.count, ringed.tie_to]));

    // ---- Words, typed where they stand ------------------------------------------
    await tool("text");
    await click(420, 380); await wait(300);
    check("the Words tool puts the cursor in the words on the plan", (await typing()) === "Words", await typing());
    await typeIn("Red Curtain"); await key("Enter"); await settled();
    const w = (await els()).find((e) => e.kind === "text" && e.text === "Red Curtain");
    check("Words keep what was typed, at a name's size", w && Math.abs(w.size - 20 / 3) < 0.01, JSON.stringify(w && [w.text, w.size]));
    await pickIds([w.id]);
    bar = (await barText()) || "";
    check("the Words bar: Text, Regular · Large", ["Text", "Regular", "Large"].every((x) => bar.includes(x)), bar);
    await js(`document.querySelector('.planfloat [data-pa=large]').click()`); await settled();
    check("Large makes them larger", Math.abs(((await els()).find((e) => e.id === w.id) || {}).size - 28 / 3) < 0.01, "not large");
    check("Words take no Note: they are words", !bar.includes("Note"), bar);

    // ---- every piece's Note (his note, 2026-10-05) -------------------------------
    await js(`shotlisterPlan.edit({ op: "add", els: [{ kind: "cast", x: 1, y: 1, label: "Maya" }] })`); await settled();
    const piece = (await els()).find((e) => e.kind === "cast");
    check("a person put down to note", Boolean(piece), "none");
    if (piece) {
      await pickIds([piece.id]);
      bar = (await barText()) || "";
      check("a camera or a person offers a Note", bar.includes("Note"), bar);
      await js(`document.querySelector('.planfloat [data-pa=caption]').click()`); await wait(250);
      check("Note types on the plan", (await typing()) === "Note", await typing());
      await typeIn("On Sticks"); await key("Enter"); await settled();
      const noted = (await els()).find((e) => e.id === piece.id) || {};
      check("and is kept as its Note", noted.caption === "On Sticks", JSON.stringify(noted.caption));
      const said = await js(`[...document.querySelectorAll('.planpic > svg text[data-part="label"]')].map((t) => t.textContent).join(' | ')`);
      check("drawn under its name", /ON STICKS/.test(said || ""), (said || "").slice(0, 200));
    }

    // ---- the plan's settings: the sheet, Lengths, Sketch ------------------------
    // In View, as the Mac has them (DiagramViewMenu): it stays open while clicked.
    await js(`shotlisterPlan.pick([])`); await wait(200);
    await js(`document.querySelector('[data-pview]').click()`); await wait(300);
    const plans = (await js(`document.querySelector('.planview').innerText.replace(/\\s+/g,' ')`)) || "";
    check("View: Paper, Landscape, Legend, Sheet Notes, Scale Bar, Lengths Off · Picked · All", ["Paper", "Landscape", "Legend", "Sheet Notes", "Scale Bar", "Lengths", "Off", "Picked", "All"].every((x) => plans.includes(x)) && !/Wall Lengths|Dimensions/.test(plans), plans);
    check("no scale bar on the sheet by default (his call G)", (await P(`shotlisterPlan.settings()`)).scale_bar === false, JSON.stringify(await P(`shotlisterPlan.settings()`)));
    await js(`document.querySelector('[data-pvset="sketch"]').click()`); await settled();
    check("View stays open while it is clicked", await js(`!!document.querySelector('.planview')`), "it closed");
    const st = await P(`shotlisterPlan.settings()`);
    const scaleGone = await js(`(() => { const n = document.querySelector('.planscale'); return !n || getComputedStyle(n).display === 'none'; })()`);
    check("Sketch takes the grid and the scale away", scaleGone && st && st.sketch && !st.grid, JSON.stringify([st && st.sketch, st && st.grid, scaleGone]));
    await js(`document.querySelector('[data-pvset="sketch"]').click()`); await settled();
    await key("Escape"); await wait(200);
    await tab("shots"); await wait(200);

    // ---- Sheet Notes, typed in the sheet --------------------------------------
    await pressLine((l) => l.kind === "notes"); await wait(100);
    check("the Notes are typed where they stand, on the page", await js(`document.activeElement && document.activeElement.matches('.ppitem.intype') && document.activeElement.isContentEditable`), "not editable");
    await typeIn("All lamps to dimmers");
    await js(`document.activeElement.blur()`); await settled();
    check("and kept as the plan's Sheet Notes", (await P(`shotlisterPlan.settings()`)).sheet_notes === "All lamps to dimmers", JSON.stringify((await P(`shotlisterPlan.settings()`)).sheet_notes));
    check("written in capitals under NOTES", (await P(`shotlisterPlan.words()`) || "").includes("ALL LAMPS TO DIMMERS"), await P(`shotlisterPlan.words()`));
    await shot("plot-sheet-card.png");

    // ---- Print is the engine's sheet -------------------------------------------
    const sheet = await P(`shotlisterPlan.sheet()`);
    check("Print draws the engine's sheet: title, legend, notes, shots", sheet && /class="dia sheet"/.test(sheet.svg) && ["LEGEND", "TITAN TUBE", "NOTES", "ALL LAMPS TO DIMMERS"].every((x) => sheet.svg.includes(x)), sheet ? sheet.svg.slice(0, 160) : "none");
    check("on letter, landscape, with nothing to measure off it", sheet && sheet.sheet.paper === "letter" && sheet.sheet.orientation === "landscape" && !sheet.sheet.bar, JSON.stringify(sheet && [sheet.sheet.paper, sheet.sheet.orientation, sheet.sheet.bar]));
    const gear = (sheet && sheet.sheet.gear) || [];
    check("the gear counts from the legend: Titan Tube × every count", gear.some((g) => g.name === "Titan Tube" && g.count >= 10), JSON.stringify(gear));
    if (sheet) writeFileSync(join(shots, "plot-print.svg"), sheet.svg);

    // ---- looking, as a viewer -----------------------------------------------------
    await js(`document.querySelector('[data-pedit].on').click()`); await wait(500);
    check("looking, the legend and notes are on the page", (await P(`shotlisterPlan.words()`) || "").includes("TITAN TUBE"), await P(`shotlisterPlan.words()`));
    const tl = nowEls.find((e) => e.id === ids[0]);
    const [vx, vy] = await at(tl.x, tl.y);
    await click(vx, vy); await wait(400);
    const look = (await js(`document.querySelector('.planfloat.look') ? document.querySelector('.planfloat.look').innerText.replace(/\\s+/g,' ') : ''`)) || "";
    check("a tapped lamp says its Name, Type and Note, never Light", /Titan Tube/.test(look) && /Film Light/.test(look) && /Note UPLIGHT TREES/i.test(look) && !/Light/.test(look.replace("Film Light", "")), look);
    await shot("plot-look.png");
    edits = true;

    // ---- read the film again: the server kept it all -------------------------
    await open(); await wait(600);
    const again = await els();
    const kept = again.filter((e) => ids.includes(e.id));
    check("after a reload the lights are still marks", kept.length === 3 && kept.filter((e) => e.mark === "bar").length >= 2, JSON.stringify(kept.map((e) => e.mark)));
    check("and two still share the label", kept.filter((e) => e.tie_to && again.some((t) => t.id === e.tie_to)).length === 2, JSON.stringify(kept.map((e) => e.tie_to)));
    check("and the Sheet Notes and the name are kept", (await P(`shotlisterPlan.settings()`)).sheet_notes === "All lamps to dimmers" && (await P(`shotlisterPlan.legend()`)).some((r) => r.name === "Titan Tube"), "lost");

    // ---- a phone, looking: the legend folded to its head, a tap opens it ----
    await ask("Emulation.setDeviceMetricsOverride", { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    edits = false; await open(); edits = true; await wait(500);
    const folded = await js(`(() => { const n = document.querySelector('.plansheet'); return !!n && !n.hidden && n.classList.contains('folded') && !n.querySelector('[data-psline]'); })()`);
    check("on a phone the legend waits folded to its head", folded, await js(`document.querySelector('.plansheet') ? document.querySelector('.plansheet').outerHTML.slice(0, 200) : 'none'`));
    await js(`document.querySelector('.plansheet [data-psfold]').click()`); await wait(300);
    check("and a tap on Legend opens it", await js(`!!document.querySelector('.plansheet [data-psline]')`), "still folded");
    await shot("plot-phone.png");
    await js(`document.querySelector('.plansheet [data-psfold]').click()`); await wait(200);
    await ask("Emulation.setDeviceMetricsOverride", { width: 1400, height: 900, deviceScaleFactor: 1, mobile: false });

    // The printed sheet, photographed on its own.
    if (sheet) {
      await ask("Page.navigate", { url: "about:blank" }); await wait(300);
      await js(`document.body.style.margin = '0'; document.body.innerHTML = ${JSON.stringify(sheet.svg.replace(/width="[\d.]+" height="[\d.]+"/, 'width="1100" height="850"'))}; true`);
      await wait(300);
      await shot("plot-print.png");
    }

    check("nothing on the page threw", thrown.length === 0, thrown.slice(0, 2).join(" / "));
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
