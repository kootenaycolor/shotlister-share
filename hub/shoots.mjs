#!/usr/bin/env node
/**
 * **A project that shoots more than once** — SL-1395 and SL-1396, 2026-10-02.
 *
 * Let's Bake shot on 9 July and shoots again on 6 October, with a new spec
 * sheet, new crew and new sections of the shot list. This runs the portal's
 * own Refresh from Notion against `notionfake.mjs`'s *Two Shoots Film* (a
 * wrapped Shoot 1 on Signature Primes, an Upcoming Shoot 2 on a Premavista
 * zoom, the old sheet listed first) and asks the pages what they show.
 *
 *     hub/shoots.mjs
 *
 * Its own hub on 8801 and its own fake Notion on 8802. Builds the browser
 * half first (`build.sh`). Short on purpose: well under a minute.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = 8801;
const NPORT = 8802;
const OWNER = "owner@example.com";
const FILM = "22222222333344445555666666666666";
const H = `http://localhost:${PORT}`;

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const ok = (what) => { pass += 1; say(`  ${what.padEnd(60)} PASS`); };
const no = (what, why) => { fail += 1; say(`  ${what.padEnd(60)} FAIL — ${String(why).slice(0, 200)}`); };
const check = (what, good, why) => (good ? ok(what) : no(what, why));

const free = (port) => spawnSync("sh", ["-c", `lsof -ti tcp:${port} -sTCP:LISTEN | xargs kill -9 2>/dev/null`]);

say("Building the browser half…");
if (spawnSync(join(HERE, "build.sh"), { stdio: "ignore" }).status !== 0) { say("the browser half would not build"); process.exit(1); }

const state = mkdtempSync(join(tmpdir(), "shoots-"));
const w = join(HERE, "node_modules/.bin/wrangler");
function put(key, body) {
  const file = join(state, "put.json");
  writeFileSync(file, typeof body === "string" ? body : JSON.stringify(body));
  spawnSync(w, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
}

function seed(card = {}) {
  put(`p/${FILM}/manifest.json`, { format: 1, project: FILM, title: "Two Shoots Film", engine: "0.1.0" });
  put(`p/${FILM}/front.json`, { version: 1, linked: "link", source: "notion:22222222333344445555666666666666", ...card });
}

let fake, hub;
async function start(notion = "") {
  free(PORT); free(NPORT);
  fake = spawn("node", [join(HERE, "notionfake.mjs"), String(NPORT), notion], { stdio: "ignore" });
  hub = spawn(w, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
    "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", "CONSOLE_TOKEN:checking-token-not-a-secret",
    "--var", "NOTION_TOKEN:checking-notion-token", "--var", `NOTION_API:http://127.0.0.1:${NPORT}/v1/`,
    "--var", "COMMIT:checking-commit", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(`${H}/health`)).ok) return; } catch {}
    await wait(500);
  }
  throw new Error("the hub would not start");
}
async function stop() {
  try { fake.kill("SIGKILL"); } catch {}
  try { hub.kill("SIGTERM"); } catch {}
  spawnSync("pkill", ["-f", `wrangler.*dev --local --port ${PORT}`]);
  free(PORT); free(NPORT);
  // **Gone before the next start**, or the next run's questions are answered
  // by this one's hub and Notion.
  for (let i = 0; i < 40; i++) {
    const held = spawnSync("sh", ["-c", `lsof -ti tcp:${PORT} -sTCP:LISTEN; lsof -ti tcp:${NPORT} -sTCP:LISTEN`]).stdout.toString().trim();
    if (!held) return;
    await wait(250);
  }
}

const page = async (path, film = FILM) => (await fetch(`${H}/f/${film}${path}${path.includes("?") ? "&" : "?"}as=${OWNER}`)).text();
const refresh = async (film = FILM) => (await fetch(`${H}/f/${film}/refresh?as=${OWNER}`, {
  method: "POST", body: "back=camera", headers: { "content-type": "application/x-www-form-urlencoded" }, redirect: "manual",
})).status;
/** The part of a page between two markers, so a check reads one block. */
const part = (html, from, to) => { const a = html.indexOf(from); if (a < 0) return ""; const b = html.indexOf(to, a + from.length); return html.slice(a, b < 0 ? undefined : b); };
const tabs = (html) => part(html, 'class="shootpick"', 'class="sectionhost"');
const ONE = "33333333444455556666777777777777";   // a film that shoots once

try {
  // The hand-written what-changed page, as Let's Bake has it.
  seed({ sections: [{ slug: "shoot-2", name: "Shoot 2 Details", by: "mcp", source: "here", type: "page" }],
    groups: [{ name: "", rows: ["shoot-2", "camera", "people", "documents"] }] });
  put(`p/${FILM}/people.json`, { version: 1, people: [{ email: "crew@example.com", role: "viewer" }], links: [], invites: [] });
  put(`p/${ONE}/manifest.json`, { format: 1, project: ONE, title: "Refresh Film", engine: "0.1.0" });
  put(`p/${ONE}/front.json`, { version: 1, linked: "link", source: "notion:11111111222233334444555555555555" });
  await start();
  say("\nThe spec sheet (SL-1395)");
  check("Refresh from Notion runs", (await refresh()) === 303, "not 303");
  let got = await page("/camera");
  check("the camera page shows the next shoot's lenses", got.includes("Fujinon Premavista 24-100"), "no zoom");
  check("…not the wrapped shoot's, though Notion lists it first", !part(got, "<dl", "</dl>").includes("Signature Primes") || got.includes("was Signature Primes"), "primes shown as the value");

  say("\nShoot tabs (SL-1396)");
  got = await page("");
  const t = tabs(got);
  check("the film's page has a tab for each shoot", t.includes("Shoot 1") && t.includes("Shoot 2"), t || "no tabs");
  check("…and opens on the next shoot", /<summary[^>]*><b>Shoot 2<\/b><span>Nov 10 · Next<\/span>/.test(t), t);
  check("…its list says the other Wrapped", /<b>Shoot 1<\/b><span>Jul 9<\/span><i>Wrapped<\/i>/.test(t), t);
  check("…each tab with its own address", t.includes(`href="/f/${FILM}/shoots/shoot-1"`), t);
  check("the film's page says what this shoot changes", got.includes("Lenses change to the zoom."), "no What Changes");

  got = await page("/camera");
  check("the lens change is marked, with what it was", /class="specrow pillrow changed"[^>]*>\s*<dt>Lenses<\/dt>\s*<dd><span class="nps"><span class="np np-[a-z]+">Fujinon Premavista 24-100<\/span><\/span><span class="was">was Signature Primes<\/span>/.test(got), part(got, "<dt>Lenses", "</div>"));
  check("…and what did not change is not", !/class="specrow changed"[^>]*>\s*<dt>Camera</.test(got), "Camera marked");
  got = await page("/shoots/shoot-1/camera");
  check("Shoot 1's tab has Shoot 1's sheet", got.includes("Signature Primes") && !got.includes("Fujinon"), "wrong sheet");
  check("…with nothing marked, being the first", !got.includes("specrow changed"), "marked");

  got = await page("/people");
  check("People on the next shoot: its own crew and the whole project's", got.includes("Nia New") && got.includes("Sam Both") && got.includes("Pat Project"), "crew");
  check("…a new face marked New", /Nia New <i class="newmark">New<\/i>/.test(got) && !/Sam Both <i class="newmark">/.test(got), part(got, "Nia New", "</div>"));
  check("…and nobody listed who is not on it (his ruling)", !got.includes("Not on This Shoot") && !got.includes("Wren Wrapped"), "listed");
  got = await page("/shoots/shoot-1/people");
  check("Shoot 1's People: its own crew", got.includes("Wren Wrapped") && got.includes("Sam Both") && !got.includes("Nia New"), "crew");
  check("…and nobody marked, being the first", !got.includes("newmark") && !got.includes("Not on This Shoot"), "marked");

  got = await page("/documents");
  check("Documents on the next shoot: its call sheet and the deck", got.includes("Shoot 2 Call Sheet") && got.includes("Look Deck") && !got.includes("Shoot 1 Call Sheet"), "documents");
  got = await page("/shoots/shoot-1/documents");
  check("…and on Shoot 1, its own", got.includes("Shoot 1 Call Sheet") && got.includes("Look Deck") && !got.includes("Shoot 2 Call Sheet"), "documents");

  got = await page("");
  check("the next shoot's rail has its Details page", got.includes('data-key="shoot-2"'), "no Shoot 2 Details");
  got = await page("/shoots/shoot-1");
  check("…and Shoot 1's rail does not", !got.includes('data-key="shoot-2"'), "Shoot 2 Details on Shoot 1");
  check("every row on Shoot 1's rail stays on Shoot 1", got.includes(`href="/f/${FILM}/shoots/shoot-1/people"`), "rows lead off the shoot");
  got = await page("/shoot-2");
  check("switching from Shoot 2 Details goes to Shoot 1's front", tabs(got).includes(`href="/f/${FILM}/shoots/shoot-1"`), tabs(got));
  check("Shoot 1's address keeps working past its people", (await fetch(`${H}/f/${FILM}/shoots/shoot-1/people?as=${OWNER}`)).status === 200, "not 200");

  say("\nVisibility lists every shoot's people (Ref 1410)");
  got = await page("/visibility");
  check("someone only on Shoot 1 has a switch", /Wren Wrapped<small>Gaffer · Shoot 1<\/small>/.test(got), part(got, "Wren", "</tr>") || "not listed");
  check("…and someone on both says both", /Sam Both<small>1st AC · Shoot 1, Shoot 2<\/small>/.test(got), part(got, "Sam Both", "</tr>"));
  const form = new URLSearchParams([["for", "links"],
    ...["shotlist", "script", "diagrams", "locations", "schedule", "bible", "boards", "camera", "people", "documents", "shoot-2"].map((k) => ["sections", k]),
    ...["Sam Both", "Nia New", "Pat Project"].map((n) => ["crew", n])]);
  const saved = await fetch(`${H}/f/${FILM}/visibility?as=${OWNER}`, { method: "POST", body: form, redirect: "manual",
    headers: { "content-type": "application/x-www-form-urlencoded" } });
  check("hiding Shoot 1's gaffer saves", [200, 303].includes(saved.status), saved.status);
  got = await (await fetch(`${H}/f/${FILM}/shoots/shoot-1/people?as=crew@example.com`)).text();
  check("…and a crew member on Shoot 1's tab no longer sees them", got.includes("Sam Both") && !got.includes("Wren Wrapped"), "still there");

  check("a film that shoots once refreshes as before", (await refresh(ONE)) === 303, "not 303");
  got = await page("", ONE);
  check("…and has no switcher", !got.includes("shootpick"), "switcher on a film with no shoots");
  check("…and all its crew", (await page("/people", ONE)).includes("Clara Notion"), "crew");

  say("\nMany shoots, and one (Ref 1413)");
  const MANY = "33333333444455556666777777777777", SOLO = "44444444555566667777888888888888";
  put(`p/${MANY}/manifest.json`, { format: 1, project: MANY, title: "Many Shoots Film", engine: "0.1.0" });
  put(`p/${MANY}/front.json`, { version: 1, linked: "link", source: `notion:${MANY}` });
  put(`p/${SOLO}/manifest.json`, { format: 1, project: SOLO, title: "One Shoot Film", engine: "0.1.0" });
  put(`p/${SOLO}/front.json`, { version: 1, linked: "link", source: `notion:${SOLO}` });
  check("a nine-shoot film refreshes", (await refresh(MANY)) === 303, "not 303");
  got = await page("", MANY);
  let pick = tabs(got);
  check("…one line, on the next shoot of nine", /<summary[^>]*><b>Shoot 6<\/b><span>Jun 15 · Next<\/span>/.test(pick), pick.slice(0, 300));
  check("…its list holds all nine", (pick.match(/class="shootrow/g) || []).length === 9, (pick.match(/class="shootrow/g) || []).length);
  check("…with Shoot 6 the one you are on", /class="shootrow on" aria-current="true"[^>]*><b>Shoot 6</.test(pick), "not marked");
  check("…and later ones Upcoming", /<b>Shoot 8<\/b><span>Aug 15<\/span><i>Upcoming<\/i>/.test(pick), "no Upcoming");
  check("‹ and › step to the shoots either side", pick.includes(`class="shootstep" href="/f/${MANY}/shoots/shoot-5"`) && pick.includes(`class="shootstep" href="/f/${MANY}/shoots/shoot-7"`), "steps");
  pick = tabs(await page("/shoots/shoot-1/camera", MANY));
  check("the first shoot has nowhere back to step", /^class="shootpick">\s*<span class="shootstep shootend"/.test(pick) && pick.includes(`href="/f/${MANY}/shoots/shoot-2/camera"`), pick.slice(0, 200));
  pick = tabs(await page("/shoots/shoot-9", MANY));
  check("…and the last nowhere on", pick.lastIndexOf('class="shootstep shootend"') > pick.lastIndexOf('class="shootstep" href') && pick.includes(`href="/f/${MANY}/shoots/shoot-8"`), pick.slice(-300));
  got = await page("/shoots/shoot-3/camera", MANY);
  check("a shoot's sheet says what the one before used", got.includes("Lens Set 3") && got.includes("was Lens Set 2"), "no was");
  const before = await (await fetch(`http://127.0.0.1:${NPORT}/reads`)).json();
  await refresh(MANY);
  const after = await (await fetch(`http://127.0.0.1:${NPORT}/reads`)).json();
  const sheet = (n) => `aaaaaaaa33330000000000000000000${n}`.slice(0, 30) + String(n).padStart(2, "0");
  const reread = [1, 2, 3, 4, 5, 7, 8, 9].filter((n) => (after[sheet(n)] || 0) !== (before[sheet(n)] || 0));
  check("a second refresh reads only the next shoot's sheet again", reread.length === 0 && (after[sheet(6)] || 0) > (before[sheet(6)] || 0), `re-read ${reread.join(", ") || "none"}; lead ${before[sheet(6)]}→${after[sheet(6)]}`);

  check("a film with one Shoots row refreshes", (await refresh(SOLO)) === 303, "not 303");
  got = await page("", SOLO);
  check("…and shows no switcher", !got.includes("shootpick"), "switcher on a one-shoot film");
  got = await page("/people", SOLO);
  check("…People is the whole project, tagged or not", got.includes("On No Shoot") && got.includes("Tagged To The Shoot") && !got.includes("newmark"), "crew");
  check("…its sheet is the one sheet", (await page("/camera", SOLO)).includes("Ultra Primes"), "sheet");
  check("…and a shoot address there is the film as usual", !(await page("/shoots/shoot-1/people", SOLO)).includes("shootpick"), "switcher");
  await stop();

  // **Notion refuses Shoots** — the portal's connection was made for four
  // databases — and the shoots the Mac last wrote on the card stand in. This
  // card says Shoot 1 is the one coming up, so its sheet is the one taken:
  // newest-first would have taken Shoot 2's.
  seed({ shoots: [
    { id: "bbbbbbbb000000000000000000000001", name: "Shoot 1", slug: "shoot-1", status: "Upcoming", start: "2026-07-09", sheet: "bbbbbbbb000000000000000000000011",
      crew: [{ name: "Stored Person", role: "Gaffer" }] },
    { id: "bbbbbbbb000000000000000000000002", name: "Shoot 2", slug: "shoot-2", status: "Upcoming", start: "2026-11-10", sheet: "bbbbbbbb000000000000000000000012" },
  ], documents: [{ name: "Shoot 1 Call Sheet", url: "https://example.com/call-1", source: "notion", shoots: ["shoot-1"] }] });
  await start("no-shoots");
  const refused = await fetch(`http://127.0.0.1:${NPORT}/v1/data_sources/feedface-0000-4000-8000-000000000002/query`, {
    method: "POST", headers: { authorization: "Bearer checking-notion-token" }, body: "{}" });
  check("this Notion refuses Shoots", refused.status === 404, refused.status);
  check("with Shoots refused, a refresh still runs", (await refresh()) === 303, "not 303");
  got = await page("/camera");
  check("…and takes the sheet of the shoot the card says is next", got.includes("Signature Primes") && !got.includes("Fujinon Premavista 24-100"), "wrong sheet");
  check("…keeps a document's shoot as the card had it", !(await page("/shoots/shoot-2/documents")).includes("Shoot 1 Call Sheet"), "tag lost");
  check("…and the next shoot's people as the card had them", (await page("/people")).includes("Stored Person"), "crew from Notion");
  await stop();

  // **A shoot he named, and a sheet with several lens sets** (2026-10-05).
  // Shoot 2 is "Two Shoots Film — Shoot 2 · Malibu Pickup" in Notion: the
  // portal shows the name, and every address and page stays Shoot 2's.
  say("\nShoot names and lens sets");
  seed({ sections: [{ slug: "shoot-2", name: "Shoot 2 Details", by: "mcp", source: "here", type: "page" }],
    groups: [{ name: "", rows: ["shoot-2", "camera", "people", "documents"] }] });
  await start("named");
  check("a refresh with a named shoot runs", (await refresh()) === 303, "not 303");
  got = await page("");
  const named = tabs(got);
  check("the switcher shows the shoot's name, with its number", /<summary[^>]*><b>Malibu Pickup<\/b><span>Shoot 2 · Nov 10 · Next<\/span>/.test(named), named.slice(0, 400));
  check("…and its address is still the number's", named.includes(`href="/f/${FILM}/shoots/shoot-2"`) && !named.includes("malibu"), named.slice(0, 400));
  check("…a link already sent to Shoot 2 still opens it", (await fetch(`${H}/f/${FILM}/shoots/shoot-2?as=${OWNER}`)).status === 200, "not 200");
  check("…and Shoot 2 Details is still on its rail", got.includes('data-key="shoot-2"'), "no Shoot 2 Details");
  check("…and not on Shoot 1's", !(await page("/shoots/shoot-1")).includes('data-key="shoot-2"'), "on Shoot 1");
  got = await page("/camera");
  const lens = part(got, "lensrow", "</div>");
  check("the camera page lists each lens set on its own line", (lens.match(/<li>/g) || []).length === 3, lens || "no list");
  check("…camera, lenses, focal lengths and stop", /<li><i>A Cam<\/i><b>Fujinon Premavista<\/b><span>24-100mm<\/span><span>T2\.9<\/span><\/li>/.test(lens), lens);
  check("…notes under the set", /<b>Signature Primes<\/b><span>18, 25, 35, 47mm<\/span><span>T1\.8<\/span><small>from Odd Kinds<\/small>/.test(lens), lens);
  check("…marked changed from Shoot 1, with what it was", lens.includes("changed") && lens.includes("was Signature Primes"), lens);
  check("…and copying it copies the whole field", /data-copy="A Cam: Fujinon Premavista — 24-100mm — T2\.9&#10;|data-copy="A Cam: Fujinon Premavista — 24-100mm — T2\.9\n/.test(got), part(got, 'lensrow', '>'));
  // **Two cameras: a column each, a setting they share across the whole row**
  // (2026-10-07). Every row is given the same count, so the columns line up.
  const body = part(got, "<dt>Camera</dt>", "</div>");
  check("the cameras sit side by side as pills, each named", /<span class="npcam"><span class="np np-[a-z]+">Alexa Mini LF<\/span><i>A Cam<\/i><\/span><span class="npcam"><span class="np np-[a-z]+">Sony FX3<\/span><i>B Cam<\/i><\/span>/.test(body), body);
  const colour = part(got, "<dt>Colour Space</dt>", "</div>");
  check("…a setting they differ in is a column each, unlabelled", /--cams:2.*<li><b>LogC3<\/b><\/li><li><b>S-Log3<\/b><\/li>/.test(colour), colour);
  const codec = part(got, "<dt>Codec</dt>", "</div>");
  check("…and one they share is the row, full width", /<span class="np np-[a-z]+">ProRes 4444<\/span>/.test(codec) && !codec.includes("camcols"), codec);
} catch (problem) {
  no("the run", problem.message);
} finally {
  await stop();
  rmSync(state, { recursive: true, force: true });
}

say(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
