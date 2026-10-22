#!/usr/bin/env node
/**
 * **The Library's categories, his to name** (2026-10-10, *"the seven fixed
 * categories should be renamable, and I should be able to add new ones; Move
 * To must work from the apps"*) — knocked on the way each asker knocks: the
 * portal's own forms as him, the console's door and the phone's, with the
 * token.
 *
 * - every film starts with the seven, by id, in their order;
 * - a rename keeps everything on the shelf, and a move made by the old name
 *   still finds it (the Look tab on the phone asks for `look`);
 * - a new category comes last, can be moved onto and moved up;
 * - one of the seven cannot be removed; one he added can, and what stood on it
 *   goes back where it would be filed;
 * - names are unique and never one the Library uses (All, Archive);
 * - Move To works from the console (`action: "shelf"`) and the phone
 *   (`PUT /phone/<film>/library`), and the phone moves nothing else;
 * - the portal's Library draws his names, the heading menus and Add Category.
 *
 *     node hub/shelves.mjs
 *
 * A scratch film in a throwaway bucket, on a hub of its own on 8811.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const FILM = "05b07c4ec1ec00000000000000000003";
const TOKEN = "checking-token-not-a-secret";
const WHO = "owner@example.com";
const PORT = 8811;
const H = `http://127.0.0.1:${PORT}`;

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

const state = mkdtempSync(join(tmpdir(), "shelves-state-"));
const box = mkdtempSync(join(tmpdir(), "shelves-film-"));
const W = join(HERE, "node_modules/.bin/wrangler");
const put = (key, text) => {
  const file = join(box, key.replace(/\//g, "_"));
  writeFileSync(file, text);
  spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
say("Putting the scratch film in a local bucket…");
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Shelves Check", engine: "0.1.0" }));
put(`p/${FILM}/front.json`, JSON.stringify({
  title: "Shelves Check",
  sections: [
    { slug: "bible", name: "Visual Bible", by: "notion", type: "page", source: "notion", notion: true },
    { slug: "night-notes", name: "Night Notes", type: "page", source: "here", by: "mcp" },
    { slug: "mood", name: "Mood Reel", type: "page", source: "here", by: "mcp" },
  ],
  documents: [{ name: "Crew Deal Memo", url: "https://example.com/memo" }],
  // A move written by name, as every card before ids was.
  shelf: { "night-notes": "Technical" },
}));
put(`p/${FILM}/people.json`, JSON.stringify({ version: 1, people: [{ email: "clara@example.com", role: "viewer" }], links: [], invites: [] }));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`], { cwd: HERE, stdio: "ignore" });

const call = (path, body, { method = body ? "PUT" : "GET", token = TOKEN } = {}) => fetch(`${H}${path}`, {
  method, headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));
const library = (body) => call(`/console/${FILM}/library`, body);
const shelves = (body) => call(`/console/${FILM}/shelves`, body);
const phone = (what, body, opts) => call(`/phone/${FILM}/${what}`, body, opts);
const portal = (fields) => {
  const form = new URLSearchParams();
  for (const [k, v] of fields) form.append(k, v);
  return fetch(`${H}/f/${FILM}/library?as=${WHO}`, { method: "POST", body: form, redirect: "manual" })
    .then(async (r) => ({ status: r.status, text: await r.text() }));
};
const page = (at, s) => (s.pages || []).find((p) => p.at === at) || {};
const doc = (name, s) => (s.documents || []).find((d) => d.name === name) || {};
const names = (s) => (s.shelves || []).map((one) => one.name);
const ids = (s) => (s.shelves || []).map((one) => one.id);

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  // ---- the seven, to start ----
  let got = await library();
  check("a film starts with the four, in order", ids(got.body).join() === "creative,technical,logistical,other", JSON.stringify(got.body.shelves));
  check("…each built in, each with an icon", got.body.shelves.every((one) => one.builtIn === true && one.icon), JSON.stringify(got.body.shelves));
  check("a move written by name reads as its id", page("night-notes", got.body).shelf === "technical", JSON.stringify(page("night-notes", got.body)));
  check("everything else is filed by id", page("bible", got.body).shelf === "creative" && page("mood", got.body).shelf === "creative"
    && doc("Crew Deal Memo", got.body).shelf === "logistical", JSON.stringify([page("bible", got.body), doc("Crew Deal Memo", got.body)]));

  // ---- rename ----
  got = await shelves({ action: "rename", shelf: "creative", name: "Lookbook" });
  check("Rename answers the shelves as they stand", got.status === 200 && names(got.body)[0] === "Lookbook", JSON.stringify(got.body).slice(0, 200));
  check("…and what was on it stays on it", page("bible", got.body).shelf === "creative" && page("mood", got.body).shelf === "creative", JSON.stringify(page("mood", got.body)));
  got = await shelves({ action: "rename", shelf: "Technical", name: "lookbook" });
  check("a name another shelf has is refused", got.status === 422 && /already/.test(got.body.problem || got.body.error || JSON.stringify(got.body)), JSON.stringify(got.body));
  got = await shelves({ action: "rename", shelf: "Technical", name: "Archive" });
  check("…and so is one the Library uses", got.status === 422, JSON.stringify(got.body));

  // ---- Move To, from the console, by the old name ----
  got = await library({ keys: ["night-notes"], action: "shelf", to: "Creative" });
  check("Move To from the console, by the shelf's starting name", got.status === 200 && page("night-notes", got.body).shelf === "creative", JSON.stringify(page("night-notes", got.body)));

  // ---- add, move onto it, move it up ----
  got = await shelves({ action: "add", name: "Lighting" });
  check("Add makes a category, last", got.status === 200 && names(got.body).at(-1) === "Lighting" && got.body.id === "x-lighting", JSON.stringify(got.body.shelves));
  check("…not built in", got.body.shelves.at(-1).builtIn === false, JSON.stringify(got.body.shelves.at(-1)));
  got = await library({ keys: ["night-notes", "doc:Crew Deal Memo"], action: "shelf", to: "x-lighting" });
  check("a page and a document moved onto it", page("night-notes", got.body).shelf === "x-lighting" && doc("Crew Deal Memo", got.body).shelf === "x-lighting", JSON.stringify([page("night-notes", got.body), doc("Crew Deal Memo", got.body)]));
  got = await shelves({ action: "move", shelf: "Lighting", to: "up" });
  check("Move Up puts it one higher", ids(got.body).at(-2) === "x-lighting", JSON.stringify(ids(got.body)));
  got = await shelves({ action: "move", shelf: "x-lighting", to: 0 });
  check("…or anywhere", ids(got.body)[0] === "x-lighting", JSON.stringify(ids(got.body)));
  got = await library({ keys: ["night-notes"], action: "shelf", to: "No Such Shelf" });
  check("a shelf that is not there is refused", got.status === 404, String(got.status));

  // ---- the phone ----
  got = await phone("library");
  const item = (k) => (got.body.items || []).find((one) => one.key === k) || {};
  check("the phone reads the categories with ids", (got.body.categories || []).map((one) => one.id)[0] === "x-lighting"
    && (got.body.categories || []).some((one) => one.id === "creative" && one.name === "Lookbook"), JSON.stringify(got.body.categories));
  check("…the names as every phone before read them", Array.isArray(got.body.shelves) && got.body.shelves.includes("Lookbook"), JSON.stringify(got.body.shelves));
  check("…and each item's shelf by id and by name", item("night-notes").shelfId === "x-lighting" && item("night-notes").shelf === "Lighting", JSON.stringify(item("night-notes")));
  got = await phone("library", { keys: ["night-notes"], action: "shelf", to: "camera" });
  check("Move To from the phone", got.status === 200 && page("night-notes", got.body).shelf === "technical", JSON.stringify(got.body).slice(0, 200));
  got = await phone("library", { keys: ["night-notes"], action: "archive" });
  check("…and nothing else from the phone", got.status === 400, String(got.status));
  got = await phone("shelves", { action: "rename", shelf: "x-lighting", name: "Lighting & Grip" });
  check("the phone renames a category", got.status === 200 && names(got.body)[0] === "Lighting & Grip", JSON.stringify(names(got.body)));
  got = await phone("shelves", { action: "rename", shelf: "x-lighting", name: "X" }, { token: "wrong" });
  check("…never without the token", got.status === 401, String(got.status));

  // ---- remove ----
  got = await shelves({ action: "remove", shelf: "creative" });
  check("one of the seven cannot be removed", got.status === 422 && /renamed but not removed/.test(JSON.stringify(got.body)), JSON.stringify(got.body));
  got = await shelves({ action: "remove", shelf: "x-lighting" });
  check("one he added can", got.status === 200 && !ids(got.body).includes("x-lighting"), JSON.stringify(ids(got.body)));
  check("…and what stood on it goes back where it would be filed", doc("Crew Deal Memo", got.body).shelf === "logistical", JSON.stringify(doc("Crew Deal Memo", got.body)));
  check("…a page moved elsewhere stays moved", page("night-notes", got.body).shelf === "technical", JSON.stringify(page("night-notes", got.body)));

  // ---- the portal's own forms, as him ----
  let said = await portal([["category", "add"], ["name", "Sound"]]);
  check("the portal's Add Category saves and lands on the Library", said.status === 303, String(said.status));
  said = await portal([["category", "rename"], ["shelf", "x-sound"], ["name", "Sound Dept"]]);
  check("…its Rename too", said.status === 303, String(said.status));
  said = await portal([["shelf", "mood"], ["to", "Sound Dept"]]);
  check("…and its Move To, by the name it shows", said.status === 303, String(said.status));
  said = await portal([["category", "remove"], ["shelf", "technical"]]);
  check("…and it refuses to remove one of the seven", said.status === 422, String(said.status));
  const html = await fetch(`${H}/f/${FILM}/library?as=${WHO}`).then((r) => r.text());
  check("the Library draws his names", /id="shelf-creative"[^>]*>\s*<h2>[\s\S]*?Lookbook/.test(html) && /id="shelf-x-sound"/.test(html), "no Lookbook / Sound Dept shelf");
  check("…each heading with its menu, Remove only on his own", (html.match(/class="fh-shelfmenu"/g) || []).length >= 3
    && /Remove Sound Dept\?/.test(html) && !/Remove Lookbook\?/.test(html), "menus wrong");
  check("…Add Category in the tools", /class="fh-addshelf"/.test(html) && /name="category" value="add"/.test(html), "no Add Category");
  check("…and Move To offers every category by name", /name="to" value="Sound Dept"/.test(html) && /name="to" value="Lookbook"/.test(html), "Move To lacks his names");
  // ---- a document pinned to the sidebar (his ask, 2026-10-11) ----
  got = await library({ keys: ["doc:Crew Deal Memo"], action: "pin" });
  check("a document can be pinned", got.status === 200, JSON.stringify(got.body || got).slice(0, 160));
  let rail = await fetch(`${H}/f/${FILM}/library?as=${WHO}`).then((r) => r.text());
  check("…and is a row of the sidebar that opens its link", /<a class="to[^"]*" data-key="doc:Crew Deal Memo"[^>]*target="_blank"[^>]*href="https:\/\/example.com\/memo"/.test(rail), "no row");
  got = await library({ keys: ["doc:Crew Deal Memo"], action: "unpin" });
  rail = await fetch(`${H}/f/${FILM}/library?as=${WHO}`).then((r) => r.text());
  check("…and unpinned it leaves the sidebar", got.status === 200 && !/<a class="to[^"]*" data-key="doc:Crew Deal Memo"/.test(rail), "still there");
  const viewer = await fetch(`${H}/f/${FILM}/library?as=clara@example.com`).then((r) => r.text()).catch(() => "");
  check("a reader gets no category menus", /fh-shelf"/.test(viewer) && !/fh-shelfmenu|fh-addshelf/.test(viewer), "menus shown to a reader, or no Library");
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
