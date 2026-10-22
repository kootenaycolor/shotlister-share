#!/usr/bin/env node
/**
 * **A page that follows a Google Doc** (`src/docfollow.js`, 2026-10-10) — the
 * portal's own clock, the page menu's switch and the console's door, against a
 * pretend Google on this machine.
 *
 * - the page is drawn **exactly** as the Mac's Doc Mirror drew it:
 *   `docfollow/page.html` is the agent's own `render.py` run on
 *   `docfollow/doc.md`, and the portal's page must match it byte for byte;
 * - the doc's picture is put beside the film's documents and the page points at it;
 * - a tick with nothing new does nothing; an edit waits to settle, then redraws;
 * - switched off, a new edit is left alone; Refresh from Doc draws it anyway;
 * - an unshared doc is said as trouble, and the page is left as it was;
 * - the sidebar marks the page, and the switch answers from the page's menu;
 * - Google's sign-in never leaves for anywhere but the fake.
 *
 *     node hub/docfollow.mjs
 *
 * A scratch film in a throwaway bucket, on a hub of its own on 8797.
 */
import { spawn, spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { setTimeout as wait } from "node:timers/promises";
import { readFileSync, mkdtempSync, writeFileSync, rmSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const FILM = "05b07c4ec1ec00000000000000000017";
const TOKEN = "checking-token-not-a-secret";
const PORT = 8797;
const GPORT = 8798;
const H = `http://127.0.0.1:${PORT}`;
const ABOUT = JSON.parse(readFileSync(join(HERE, "docfollow/about.json"), "utf8"));
const DOC = ABOUT.doc;
const MD = readFileSync(join(HERE, "docfollow/doc.md"), "utf8");
const EXPECTED = readFileSync(join(HERE, "docfollow/page.html"), "utf8");

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

/* ---- a pretend Google: one doc, whose version, time and words the check moves */
const google = { version: ABOUT.meta.version, modified: ABOUT.meta.modifiedTime, md: MD, gone: false, tokens: 0, asked: [] };
const fakeGoogle = createServer(async (req, res) => {
  google.asked.push(req.url);
  if (req.url === "/token" && req.method === "POST") {
    google.tokens += 1;
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ access_token: "fake-access", expires_in: 3600 }));
  }
  if (req.headers.authorization !== "Bearer fake-access") { res.writeHead(401); return res.end("no"); }
  if (google.gone) { res.writeHead(404); return res.end("gone"); }
  if (req.url.startsWith(`/drive/v3/files/${DOC}/export`)) {
    res.writeHead(200, { "content-type": "text/markdown" });
    return res.end(google.md);
  }
  if (req.url.startsWith(`/drive/v3/files/${DOC}?`)) {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ ...ABOUT.meta, version: google.version, modifiedTime: google.modified }));
  }
  res.writeHead(404); res.end("no such thing");
});
await new Promise((ok) => fakeGoogle.listen(GPORT, "127.0.0.1", ok));

/* ---- the scratch film */
const state = mkdtempSync(join(tmpdir(), "follow-state-"));
const box = mkdtempSync(join(tmpdir(), "follow-film-"));
const W = join(HERE, "node_modules/.bin/wrangler");
const put = (key, text) => {
  const file = join(box, key.replace(/\//g, "_"));
  writeFileSync(file, text);
  spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
const get = (key) => {
  const got = spawnSync(W, ["r2", "object", "get", `shotlister-preview/${key}`, "--pipe", "--local", "--persist-to", state],
    { cwd: HERE, encoding: "utf8" });
  return got.status === 0 ? got.stdout : null;
};
say("Putting the scratch film in a local bucket…");
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: ABOUT.cfg.film, engine: "0.1.0" }));
put(`p/${FILM}/front.json`, JSON.stringify({
  sections: [{ slug: "outline", name: "Outline", title: "", by: "deck", type: "deck", source: "program", notion: false }],
  groups: [{ name: "Development", rows: ["outline"] }],
}));
put(`p/${FILM}/pages/outline.html`, "<p>the old page</p>");

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--test-scheduled",
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`,
  "--var", "HUB_DEV_EMAIL:owner@example.com",
  "--var", `GOOGLE_FAKE:http://127.0.0.1:${GPORT}`,
  "--var", `GDRIVE:${JSON.stringify({ client_id: "c", client_secret: "s", refresh_token: "r" })}`],
{ cwd: HERE, stdio: "ignore" });

const done = (code) => { hub.kill("SIGTERM"); fakeGoogle.close(); rmSync(box, { recursive: true, force: true }); rmSync(state, { recursive: true, force: true }); process.exit(code); };
for (let i = 0; i < 90; i += 1) {
  try { if ((await fetch(`${H}/version`)).ok) break; } catch { /* not yet */ }
  await wait(500);
}

const door = (method, body) => fetch(`${H}/console/${FILM}/follow/outline`, {
  method, headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => ({ status: r.status, data: await r.json().catch(() => null) }));
const tick = async () => { await fetch(`${H}/__scheduled?cron=${encodeURIComponent("*/2 * * * *")}`); await wait(400); };
const page = () => get(`p/${FILM}/pages/outline.html`);
const ago = (s) => new Date(Date.now() - s * 1000).toISOString();

try {
  say("\nThe console points the page at a doc, switched off");
  let got = await door("PUT", { doc: `https://docs.google.com/document/d/${DOC}/edit?tab=t.0`, credit: "Ivy", on: false });
  check("the page now follows that doc, not yet on", got.status === 200 && got.data.doc === DOC && got.data.following === false, JSON.stringify(got));
  check("nothing drawn while it is off", page() === "<p>the old page</p>", "page changed");
  await tick();
  check("the clock leaves an off page alone", page() === "<p>the old page</p>", "page changed");
  check("the card keeps the switch", JSON.parse(get(`p/${FILM}/front.json`)).sections[0].follow?.doc === DOC, "front.json lost follow");

  say("\nSwitched on, it draws at once — as the Mac drew it");
  google.modified = ABOUT.meta.modifiedTime;
  got = await door("PUT", { on: true });
  check("turning it on says it drew", got.status === 200 && got.data.on === true && got.data.said === "Updated from the Doc", JSON.stringify(got.data));
  const html = page();
  check("the page is the Mac's drawing, byte for byte", html === EXPECTED,
    html ? `differs at ${[...html].findIndex((c, i) => c !== EXPECTED[i])}: ${html.slice(0, 80)}` : "no page");
  const pic = (EXPECTED.match(/pic\/([0-9a-f]{32}\.png)/) || [])[1];
  check("the doc's picture is filed with the film's documents", Boolean(pic && get(`p/${FILM}/docs/${pic}`)), `no docs/${pic}`);

  say("\nThe clock");
  const asks = google.asked.length;
  await tick();
  check("a tick with no new version asks once and draws nothing", page() === EXPECTED && google.asked.length - asks <= 2, `${google.asked.length - asks} asks`);
  google.version = "8"; google.modified = ago(20); google.md = MD.replace("A *young* woman", "An *older* woman");
  await tick();
  check("an edit a few seconds old waits to settle", page() === EXPECTED, "redrew mid-edit");
  google.modified = ago(200);
  await tick();
  check("once it has sat still, the page is redrawn", (page() || "").includes("An <em>older</em> woman"), "not redrawn");
  got = await door("GET");
  check("the console sees when it last drew, and no trouble", got.status === 200 && got.data.drawn && !got.data.trouble && got.data.connected === true, JSON.stringify(got.data));

  say("\nSwitched off, then Refresh from Doc");
  got = await door("PUT", { on: false });
  check("turning it off says so", got.status === 200 && got.data.on === false && got.data.said === "Stopped Following", JSON.stringify(got.data));
  google.version = "9"; google.modified = ago(300); google.md = MD.replace("A *young* woman", "A *third* woman");
  await tick();
  check("an off page is not redrawn by the clock", !(page() || "").includes("third"), "redrawn while off");
  got = await door("PUT", { refresh: true });
  check("Refresh from Doc draws it anyway", (page() || "").includes("A <em>third</em> woman") && got.data.on === false, JSON.stringify(got.data));

  say("\nTrouble");
  await door("PUT", { on: true });
  google.gone = true; google.version = "10"; google.modified = ago(300);
  const before = page();
  await tick();
  got = await door("GET");
  check("an unshared doc is said, and the page is left as it was", page() === before && /can't be opened/.test(got.data.trouble || ""), JSON.stringify(got.data));
  google.gone = false;
  await tick();
  got = await door("GET");
  check("once it opens again the trouble clears", !got.data.trouble, JSON.stringify(got.data));

  say("\nThe page, as he sees it");
  let r0;
  const rail = await (await fetch(`${H}/f/${FILM}/outline`)).text();
  check("the sidebar row says it is following", /data-key="outline"[^>]*data-follow="1"/.test(rail), "no data-follow on the row");
  check("the page's own menu offers the switch and a redraw", /<button[^>]*pmswitch on[^>]*>Follow Google Doc/.test(rail) && /Refresh from Doc/.test(rail), "not in the page's menu");
  r0 = await fetch(`${H}/f/${FILM}/follow`, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded" }, body: "slug=outline&on=0&back=outline" });
  check("…and its switch, sent as a form, turns it off and goes back to the page", r0.status === 303 && r0.headers.get("location") === `/f/${FILM}/outline`, `${r0.status} ${r0.headers.get("location")}`);
  const off = await (await fetch(`${H}/f/${FILM}/outline`)).text();
  check("…then the menu says it is off, with no redraw", /<button[^>]*pmswitch"[^>]*>Follow Google Doc/.test(off) && !/Refresh from Doc/.test(off), "menu did not follow the switch");
  await fetch(`${H}/f/${FILM}/follow`, { method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded" }, body: "slug=outline&on=1&back=outline" });
  let r = await fetch(`${H}/f/${FILM}/follow`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ slug: "outline", on: false }) });
  let d = await r.json();
  check("the menu's switch turns it off", r.status === 200 && d.on === false, JSON.stringify(d));
  r = await fetch(`${H}/f/${FILM}/follow`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ slug: "nothing-here", on: true }) });
  check("a page that does not exist is refused", r.status === 404, String(r.status));
  const after = await (await fetch(`${H}/f/${FILM}/outline`)).text();
  check("…and the row says so", /data-key="outline"[^>]*data-follow="0"/.test(after), "row still on");

  check("Google was only ever asked at the fake", google.tokens >= 1, "never asked for a token");
} catch (error) {
  check("the run finished", false, error && error.stack);
}

say(`\n${pass} passed, ${fail} failed`);
done(fail ? 1 : 0);
