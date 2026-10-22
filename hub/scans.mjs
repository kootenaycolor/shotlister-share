#!/usr/bin/env -S node --experimental-websocket
/**
 * **Whether a scanned room actually draws on a location's page.**
 *
 * Ref: the 3D scans panel. `checks.sh` can ask the worker whether a file comes
 * back, and that is not the question — the question is whether a browser fetches
 * a room's measurements, hands them to the engine and gets a floor plan on the
 * screen. Nothing that asks over HTTP can see that, for the same reason
 * `drag.mjs` exists: a check with no browser in it cannot see a drawing.
 *
 * So this seeds **his own film** — the real change logs and the real scans off
 * `Call Her Back`, because a room cannot be invented and a Mac has no LiDAR —
 * opens the Locations page, clicks through to each place, and reads what is on
 * the screen.
 *
 *     hub/scans.mjs
 *
 * It starts its own hub on 8791 against a throwaway bucket and stops everything
 * after. Screenshots land in /tmp, or wherever SHOTS says.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync, readdirSync, existsSync } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const SHELL =
  `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1234` +
  `/chrome-headless-shell-mac-arm64/chrome-headless-shell`;
const FILM = "01a02852ebb00198e46a252100000000";
const PORT = 8791;
const DEBUG = 9347;
const shots = process.env.SHOTS || tmpdir();
/** The film to read. A copy is fine; nothing here writes to it. */
const REAL = process.env.FILM ||
  join(homedir(), "Library/Mobile Documents/com~apple~CloudDocs/Shotlister/Call Her Back.shotlist");

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(58)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(58)} FAIL — ${why}`); };

let WS;
try {
  ({ default: WS } = await import(join(HERE, "node_modules/ws/index.js")));
} catch {
  say("`ws` is not in hub/node_modules — run npm install in hub/ first.");
  process.exit(1);
}

/**
 * His film, as far as the relay is concerned: the manifest, every change log,
 * and **only the scans** out of the media store.
 *
 * The photographs are deliberately left behind — 599 MB of them, and not one
 * is what is being looked at here. They draw as empty frames, which is what an
 * empty frame is for.
 */
function seed(state) {
  const w = join(HERE, "node_modules/.bin/wrangler");
  const box = mkdtempSync(join(tmpdir(), "scans-"));
  const putFile = (key, file) =>
    spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file,
      "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
  const put = (key, body) => {
    const file = join(box, "one.bin");
    writeFileSync(file, body);
    putFile(key, file);
  };
  put(`p/${FILM}/manifest.json`,
    JSON.stringify({ format: 1, project: FILM, title: "Call Her Back", engine: "0.1.0" }));
  let logs = 0;
  for (const name of readdirSync(join(REAL, "changes"))) {
    if (!name.endsWith(".log")) continue;
    putFile(`p/${FILM}/logs/${name}`, join(REAL, "changes", name));
    logs += 1;
  }
  let rooms = 0;
  const store = join(REAL, "media/proxies");
  if (existsSync(store)) {
    for (const name of readdirSync(store)) {
      if (!/\.(usdz|json)$/i.test(name)) continue;
      putFile(`p/${FILM}/media/${name}`, join(store, name));
      rooms += 1;
    }
  }
  rmSync(box, { recursive: true, force: true });
  return { logs, rooms };
}

async function browser(run) {
  const proc = spawn(SHELL, [`--remote-debugging-port=${DEBUG}`, "--no-sandbox",
    "--disable-gpu", "--window-size=1500,1000", "about:blank"], { stdio: "ignore" });
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
    ws.on("message", (m) => {
      const said = JSON.parse(m);
      if (said.id && waiting.has(said.id)) { waiting.get(said.id)(said); waiting.delete(said.id); }
    });
    const ask = (method, params = {}) =>
      new Promise((y) => { const n = ++id; waiting.set(n, y); ws.send(JSON.stringify({ id: n, method, params })); });
    await ask("Page.enable");
    return await run(ask).finally(() => ws.close());
  } finally {
    proc.kill();
  }
}

if (!existsSync(join(REAL, "changes"))) {
  say(`no film at ${REAL} — set FILM to one`);
  process.exit(1);
}
const state = mkdtempSync(join(tmpdir(), "scans-state-"));
say(`Putting ${basename(REAL)} in a local bucket…`);
const seeded = seed(state);
say(`  ${seeded.logs} change logs, ${seeded.rooms} scan files`);
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

  await browser(async (ask) => {
    const js = async (expression) => {
      const got = await ask("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true });
      return got.result?.result?.value;
    };
    const open = async (where) => {
      await ask("Page.navigate", { url: `http://127.0.0.1:${PORT}${where}` });
      await wait(3500);
    };
    const shot = async (name) => {
      const got = await ask("Page.captureScreenshot", { format: "png" });
      writeFileSync(join(shots, name), Buffer.from(got.result.data, "base64"));
      say(`  → ${join(shots, name)}`);
    };
    /** Click a place in the list by the name he gave it. */
    const pick = async (name) => {
      await js(`(() => {
        const row = [...document.querySelectorAll('[data-pick="place"]')]
          .find(b => b.textContent.trim().startsWith(${JSON.stringify(name)}));
        if (row) row.click();
        return !!row;
      })()`);
      await wait(2500);
    };
    const panel = () => js(`JSON.stringify({
      scans: document.querySelectorAll('.scan').length,
      plans: document.querySelectorAll('.plan').length,
      walls: document.querySelectorAll('.plan .pl-wall').length,
      said: [...document.querySelectorAll('.scansaid')].map(e => e.textContent).filter(Boolean),
      parts: [...document.querySelectorAll('.scanparts')].map(e => e.textContent).filter(Boolean),
      empty: [...document.querySelectorAll('.scan .empty')].map(e => e.textContent),
      pictures: document.querySelectorAll('.wall .tile').length,
    })`);

    await open(`/f/${FILM}/locations?as=owner@example.com`);
    const drew = await js(`document.querySelectorAll('[data-pick="place"]').length`);
    drew > 0 ? ok("the locations page draws its places")
             : no("the locations page draws its places", "no rows");

    // ---- a room with measurements ----------------------------------------
    await pick("Kitchen/Living Room");
    let seen = JSON.parse(await panel() || "{}");
    say(`\n  Kitchen/Living Room: ${JSON.stringify(seen)}`);
    seen.scans === 1 ? ok("a location lists the room that was scanned")
                     : no("a location lists the room that was scanned", `${seen.scans} scans`);
    seen.plans === 1 ? ok("the scan draws as a floor plan")
                     : no("the scan draws as a floor plan", `${seen.plans} plans`);
    seen.walls > 10 ? ok("the plan has the room's walls in it")
                    : no("the plan has the room's walls in it", `${seen.walls} walls`);
    /^\d+ ft( \d+ in)? × \d+ ft/.test(seen.said?.[0] || "")
      ? ok("the room is measured in feet and inches")
      : no("the room is measured in feet and inches", seen.said?.[0] || "nothing said");
    /ceiling/.test(seen.said?.[0] || "")
      ? ok("how high the ceiling is, said on the panel")
      : no("how high the ceiling is, said on the panel", seen.said?.[0] || "nothing said");
    // **A scan must never arrive as a photograph.** It is attached the same way
    // one is, and a `.usdz` hung on a wall of pictures is a broken image.
    seen.pictures === 7
      ? ok("the photographs are still only photographs")
      : no("the photographs are still only photographs", `${seen.pictures} tiles, expected 7`);
    await shot("shotlister-scan-kitchen.png");

    // ---- the room can be taken away ---------------------------------------
    //
    // **A download named after its fingerprint is a file nobody can find
    // again.** The store names a file by its own contents, which is right for a
    // store and useless on a desk, so the link carries the name the phone gave
    // the room.
    const take = JSON.parse(await js(`(() => {
      const a = document.querySelector('.scanacts a[download]');
      return JSON.stringify(a ? { name: a.getAttribute('download'), href: a.getAttribute('href'), says: a.textContent.trim() } : {});
    })()`) || "{}");
    say(`\n  the download: ${JSON.stringify(take)}`);
    take.says === "Download"
      ? ok("the room can be downloaded from the panel")
      : no("the room can be downloaded from the panel", take.says || "no link");
    /\.usdz$/i.test(take.name || "") && !/^[0-9a-f]{32}\./.test(take.name || "")
      ? ok("it comes down under the room's own name")
      : no("it comes down under the room's own name", take.name || "unnamed");
    (await js(`fetch(document.querySelector('.scanacts a[download]').getAttribute('href'))
        .then(r => r.ok && r.headers.get('content-type'))`)) === "model/vnd.usdz+zip"
      ? ok("and the file behind it is really there")
      : no("and the file behind it is really there", "not served as a usdz");

    // ---- opened up, and every measurement copyable -------------------------
    await ask("Browser.grantPermissions", {
      origin: `http://127.0.0.1:${PORT}`,
      permissions: ["clipboardReadWrite", "clipboardSanitizedWrite"],
    });
    await js(`document.querySelector('[data-sizes]').click()`);
    await wait(900);
    const room = JSON.parse(await js(`JSON.stringify({
      open: !!document.querySelector('.roomout'),
      title: document.querySelector('.roomout .poptitle')?.textContent || "",
      plan: document.querySelectorAll('.roomplan .plan').length,
      walls: document.querySelectorAll('.roomplan .pl-wall').length,
      heads: [...document.querySelectorAll('.roomsizes .sizehead')].map(h => h.textContent.trim()),
      names: [...document.querySelectorAll('.roomsizes .sizename')].map(n => n.textContent).filter(Boolean),
      values: [...document.querySelectorAll('.sizeval')].map(v => v.textContent),
      buttons: [...document.querySelectorAll('.roomout .popbar .btn')].map(b => b.textContent.trim()),
    })`) || "{}");
    say(`\n  opened up: ${room.heads?.join(" / ")} — ${room.values?.length} numbers`);
    room.open ? ok("Dimensions opens the room in a pop-out")
              : no("Dimensions opens the room in a pop-out", "nothing opened");
    room.plan === 1 ? ok("the plan is drawn again, big")
                    : no("the plan is drawn again, big", `${room.plan} plans`);
    room.walls === seen.walls
      ? ok("the same room, wall for wall")
      : no("the same room, wall for wall", `${room.walls} against the panel's ${seen.walls}`);
    room.names?.slice(0, 3).join(",") === "Width,Depth,Ceiling"
      ? ok("the room's own size is the first thing in it")
      : no("the room's own size is the first thing in it", (room.names || []).slice(0, 3).join(","));
    // His kitchen is 7 ft 11 in at one end and 16 ft 8 in at the other. One
    // number for that ceiling is a lie, and the pop-out says both.
    room.names?.includes("Lowest") && room.names?.includes("Highest")
      ? ok("a ceiling that varies gives both ends")
      : no("a ceiling that varies gives both ends", (room.names || []).join(","));
    room.names?.includes("Wall 1") && room.names?.includes("Door 1")
      ? ok("every wall and every door is measured on its own")
      : no("every wall and every door is measured on its own", (room.names || []).join(",").slice(0, 80));
    // **One Download, and no "Open in 3D".** The second pointed at the same
    // file and did the same thing — his report, 2026-09-10.
    room.buttons?.includes("Download") && !room.buttons?.includes("Open in 3D")
      ? ok("the file is to hand from inside the pop-out, once")
      : no("the file is to hand from inside the pop-out, once", (room.buttons || []).join(","));

    // **The copy is the whole point of the pop-up**, so it is read back out of
    // the clipboard rather than believed.
    const copied = JSON.parse(await js(`(async () => {
      const one = [...document.querySelectorAll('.sizeval')].find(v => /ft/.test(v.textContent));
      const wanted = one.dataset.copy;
      one.click();
      await new Promise(r => setTimeout(r, 250));
      let held = "";
      try { held = await navigator.clipboard.readText(); } catch (e) { held = "cannot read: " + e.message; }
      return JSON.stringify({ wanted, held, said: one.textContent.trim() });
    })()`) || "{}");
    say(`  copied: ${JSON.stringify(copied)}`);
    copied.said === "Copied"
      ? ok("pressing a measurement says it was copied")
      : no("pressing a measurement says it was copied", copied.said || "said nothing");
    copied.held === copied.wanted
      ? ok("and the clipboard really holds that measurement")
      : no("and the clipboard really holds that measurement", `${copied.held} for ${copied.wanted}`);
        const all = JSON.parse(await js(`(async () => {
      try {
        const b = document.querySelector('.sizefoot .btn');
        if (!b) return JSON.stringify({ why: "no Copy All button" });
        b.click();
        await new Promise(r => setTimeout(r, 300));
        const held = await navigator.clipboard.readText();
        const lines = held.split(String.fromCharCode(10));
        return JSON.stringify({ lines: lines.length, first: lines[0], last: lines[lines.length - 1] });
      } catch (e) {
        return JSON.stringify({ why: String((e && e.message) || e) });
      }
    })()`) || "{}");
    say(`  Copy All: ${JSON.stringify(all)}`);
    all.lines > 30 && all.first === `Width\t${seen.said?.[0]?.split(" \u00d7 ")[0] || ""}`
      ? ok("Copy All takes the whole room down at once")
      : no("Copy All takes the whole room down at once", JSON.stringify(all));

    // **A numbered wall nobody can find is a number, not a measurement.**
    const lit = await js(`(() => {
      const row = [...document.querySelectorAll('.sizerow[data-part]')][0];
      row.dispatchEvent(new MouseEvent('mouseenter'));
      return document.querySelectorAll('.roomplan .lit').length;
    })()`);
    lit === 1 ? ok("pointing at a row lights that wall on the plan")
              : no("pointing at a row lights that wall on the plan", `${lit} lit`);
    await shot("shotlister-scan-dimensions.png");

    await js(`document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))`);
    await wait(400);
    (await js(`!document.querySelector('.roomout')`))
      ? ok("escape shuts it again")
      : no("escape shuts it again", "still open");

    // ---- a room is inside a house, and the page says so ---------------------
    //
    // His report, 2026-09-10: *"the web app doesnt distinguish that areas are
    // inside of locations. right now it displays them as equal things."* A test project is one house with six rooms in it, which is the case exactly.
    const tree = JSON.parse(await js(`JSON.stringify({
      rows: document.querySelectorAll('.scopedlist .kid').length,
      deep: document.querySelectorAll('.scopedlist .kid.deep').length,
      firstDeep: document.querySelector('.scopedlist .kid')?.classList.contains('deep') ?? true,
      indent: (() => { const a = document.querySelector('.scopedlist .kid:not(.deep)'), b = document.querySelector('.scopedlist .kid.deep');
        return a && b ? b.querySelector('.hd').getBoundingClientRect().left - a.querySelector('.hd').getBoundingClientRect().left : 0; })(),
      upto: document.querySelector('.upto')?.textContent.trim() || "",
      whose: document.querySelector('.fact .whose')?.textContent.trim() || "",
      own: document.querySelector('.fact .said')?.textContent.trim() || "",
    })`) || "{}");
    say(`\n  the list: ${JSON.stringify(tree)}`);
    tree.deep > 0 && tree.deep < tree.rows && !tree.firstDeep
      ? ok("the rail lists rooms under their house")
      : no("the rail lists rooms under their house", `${tree.deep} of ${tree.rows} deep`);
    tree.indent >= 12
      ? ok("and a room stands in from its house")
      : no("and a room stands in from its house", `${tree.indent}px in`);
    tree.upto === "Mansion"
      ? ok("a room's page names the house above its own name")
      : no("a room's page names the house above its own name", tree.upto || "nothing above the name");
    // Kitchen/Living Room has no address of its own; the panel shows the
    // Mansion's, and now says so.
    tree.whose === "Mansion"
      ? ok("a borrowed address says whose it is")
      : no("a borrowed address says whose it is", tree.whose || "nothing said");
    await js(`document.querySelector('.upto').click()`);
    await wait(1500);
    const house = JSON.parse(await js(`JSON.stringify({
      name: document.querySelector('.detailhead h1')?.textContent.trim() || "",
      areas: [...document.querySelectorAll('.rooms .room .hd')].map(a => a.textContent.trim()),
      upto: !!document.querySelector('.upto'),
      whose: !!document.querySelector('.fact .whose'),
    })`) || "{}");
    say(`  the house: ${JSON.stringify(house)}`);
    house.name === "Mansion"
      ? ok("the house's name is the way back up")
      : no("the house's name is the way back up", house.name || "went nowhere");
    house.areas?.length === tree.deep && house.areas?.includes("Kitchen/Living Room")
      ? ok("a house lists the rooms in it by name")
      : no("a house lists the rooms in it by name", JSON.stringify(house.areas));
    !house.upto && !house.whose
      ? ok("and a house has nothing above it and owns its address")
      : no("and a house has nothing above it and owns its address", JSON.stringify(house));
    await shot("shotlister-house.png");
    await js(`[...document.querySelectorAll('.rooms .room')].find(a => a.textContent.includes('Bedroom')).click()`);
    await wait(1500);
    (await js(`document.querySelector('.detailhead h1')?.textContent.trim()`)) === "Bedroom"
      ? ok("a room listed on its house is a way in")
      : no("a room listed on its house is a way in", "did not land on Bedroom");
    await shot("shotlister-house-and-rooms.png");

    // ---- four scans, three of them aborted --------------------------------
    await pick("Bathroom");
    seen = JSON.parse(await panel() || "{}");
    say(`\n  Bathroom: ${JSON.stringify(seen)}`);
    seen.scans === 4 ? ok("every scan on a place is listed")
                     : no("every scan on a place is listed", `${seen.scans} scans`);
    seen.plans === 1 ? ok("only the scan with a room in it draws one")
                     : no("only the scan with a room in it draws one", `${seen.plans} plans`);
    seen.empty?.filter((t) => /Nothing measured/.test(t)).length === 3
      ? ok("an aborted scan says nothing was measured")
      : no("an aborted scan says nothing was measured", JSON.stringify(seen.empty));
    await shot("shotlister-scan-bathroom.png");

    // ---- and a place nobody scanned ---------------------------------------
    await pick("Mansion");
    const bare = JSON.parse(await panel() || "{}");
    bare.scans === 0 && /Nothing scanned/.test((await js(
      `[...document.querySelectorAll('.fact')].map(f => f.textContent).join('|')`)) || "")
      ? ok("a place nobody scanned says so, in one line")
      : no("a place nobody scanned says so, in one line", JSON.stringify(bare));

    // ---- and on the phone, which is where he is standing -------------------
    //
    // **The panel is not a panel on a phone.** It comes apart and lands in the
    // page in his own order for a place — name, address, pictures, scans,
    // notes — so a scan is drawn by a different branch of `placeFacts` and has
    // to be seen there too.
    await ask("Emulation.setDeviceMetricsOverride",
      { width: 390, height: 844, deviceScaleFactor: 2, mobile: true });
    await open(`/f/${FILM}/locations?as=owner@example.com`);
    await pick("Kitchen/Living Room");
    const phone = JSON.parse(await panel() || "{}");
    say(`\n  on a phone: ${JSON.stringify(phone)}`);
    phone.plans === 1 ? ok("the plan draws on a phone as well")
                      : no("the plan draws on a phone as well", `${phone.plans} plans`);
    (await js(`!!document.querySelector('.facts.rest .scan')`))
      ? ok("on a phone the scan sits under the photographs")
      : no("on a phone the scan sits under the photographs", "not in the rest block");
    await shot("shotlister-scan-phone.png");

    // **The pop-out is where he is standing, too.** 330px of measurements
    // beside a plan is a desk shape; on a phone it stacks, and the whole thing
    // has to still scroll or the walls past the tenth are unreachable.
    await js(`document.querySelector('[data-sizes]').click()`);
    await wait(900);
    const pocket = JSON.parse(await js(`(() => {
      const stage = document.querySelector('.roomstage');
      const plan = document.querySelector('.roomplan');
      const sizes = document.querySelector('.roomsizes');
      return JSON.stringify({
        open: !!stage,
        stacked: plan && sizes ? sizes.getBoundingClientRect().top >= plan.getBoundingClientRect().bottom - 1 : false,
        scrolls: stage ? stage.scrollHeight > stage.clientHeight + 8 : false,
        fits: plan ? plan.getBoundingClientRect().width <= window.innerWidth : false,
      });
    })()`) || "{}");
    say(`  on a phone, opened up: ${JSON.stringify(pocket)}`);
    pocket.open ? ok("the room opens up on a phone as well")
                : no("the room opens up on a phone as well", "nothing opened");
    pocket.stacked ? ok("the measurements stack under the plan there")
                   : no("the measurements stack under the plan there", "still side by side");
    pocket.scrolls && pocket.fits
      ? ok("and the whole of it can be reached")
      : no("and the whole of it can be reached", JSON.stringify(pocket));
    await shot("shotlister-scan-dimensions-phone.png");
    await ask("Emulation.clearDeviceMetricsOverride");
  });
} finally {
  hub.kill();
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs -r kill -9`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
}

say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
