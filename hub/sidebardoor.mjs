#!/usr/bin/env node
/**
 * **Projects Console's Portal tab, its sidebar editing** (2026-10-10) — the
 * doors `POST /console/<film>/act/…` and the Library's `icon`, knocked on the
 * way the console knocks: the console's token, a form, no browser.
 *
 * - the token is asked, and only the three writes and their own fields pass;
 * - Add makes a page through the page's own Add, under a heading;
 * - a page's Rename moves its address, and a Notion-named page is refused
 *   with the portal's own reason;
 * - the order is the rail's whole shape, headings and all;
 * - an icon is set and put back to the default;
 * - every answer carries the sidebar as it now stands.
 *
 *     node hub/sidebardoor.mjs
 *
 * A scratch film in a throwaway bucket, on a hub of its own on 8796.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const FILM = "05b07c4ec1ec00000000000000000002";
const TOKEN = "checking-token-not-a-secret";
const PORT = 8796;
const H = `http://127.0.0.1:${PORT}`;

let pass = 0, fail = 0;
const say = (...w) => console.log(...w);
const check = (what, good, why) => {
  if (good) { pass += 1; say(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; say(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

const state = mkdtempSync(join(tmpdir(), "sidebar-state-"));
const box = mkdtempSync(join(tmpdir(), "sidebar-film-"));
const W = join(HERE, "node_modules/.bin/wrangler");
const put = (key, text) => {
  const file = join(box, key.replace(/\//g, "_"));
  writeFileSync(file, text);
  spawnSync(W, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state],
    { cwd: HERE, stdio: "ignore" });
};
say("Putting the scratch film in a local bucket…");
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Sidebar Check", engine: "0.1.0" }));
put(`p/${FILM}/front.json`, JSON.stringify({
  title: "Sidebar Check",
  sections: [{ slug: "bible", name: "Visual Bible", by: "notion", type: "page", source: "notion", notion: true },
    { slug: "directors-treatment", name: "Director's Treatment", type: "page", source: "notion", notion: true }],
}));

say(`Starting the hub on ${PORT}…`);
spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(W, ["dev", "--local", "--port", String(PORT), "--persist-to", state,
  "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", `CONSOLE_TOKEN:${TOKEN}`], { cwd: HERE, stdio: "ignore" });

const act = (verb, fields, { token = TOKEN, method = "POST" } = {}) => {
  const body = new URLSearchParams();
  for (const [k, v] of fields) body.append(k, v);
  return fetch(`${H}/console/${FILM}/act/${verb}`, {
    method, headers: { authorization: `Bearer ${token}` }, body: method === "GET" ? undefined : body,
  }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));
};
const library = (body) => fetch(`${H}/console/${FILM}/library`, {
  method: body ? "PUT" : "GET",
  headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" },
  body: body ? JSON.stringify(body) : undefined,
}).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));
const heads = (s) => (s.sidebar || []).map((g) => g.head);
const under = (s, head) => ((s.sidebar || []).find((g) => g.head === head) || { rows: [] }).rows;
const row = (s, at) => (s.rows || []).find((r) => r.at === at) || {};

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`${H}/health`)).ok; } catch {}
  }
  if (!up) { say("the hub would not start"); process.exit(1); }

  // ---- the door's own rules ----
  check("no token, no door", (await act("order", [], { token: "wrong" })).status === 401, "not 401");
  check("it is asked with POST", (await act("order", [], { method: "GET" })).status === 405, "not 405");
  check("only its three writes", (await act("library/x", [])).status === 404, "not 404");
  check("a page's door takes only rename", (await act("bible", [["remove", "1"]])).status === 400, "not 400");

  // ---- what the console reads ----
  let got = await library();
  check("the Library answers with the sidebar", got.status === 200 && Array.isArray(got.body.sidebar), JSON.stringify(got.body).slice(0, 200));
  check("…each row with its icon", row(got.body, "bible").icon === "bible", JSON.stringify(row(got.body, "bible")));
  check("…every page is renamable, the built-in Visual Bible too", row(got.body, "bible").renamable === true, JSON.stringify(row(got.body, "bible")));
  check("…and the icons to pick from, drawn", (got.body.icon_choices || []).includes("star") && /<path/.test((got.body.icon_paths || {}).star || ""), "no star");

  // ---- a heading, by the order ----
  const rail = got.body.sidebar.flatMap((g) => g.rows);
  got = await act("order", [["group", `Prep\n${rail.slice(0, 2).join(",")}`], ["group", `\n${rail.slice(2).join(",")}`]]);
  check("the order makes a heading", got.status === 200 && got.body.ok && heads(got.body)[0] === "Prep", JSON.stringify(got.body.sidebar));
  check("…with its two pages", under(got.body, "Prep").join() === rail.slice(0, 2).join(), JSON.stringify(under(got.body, "Prep")));

  // ---- Add ----
  got = await act("add", [["name", "Night Notes"], ["type", "page"], ["head", "Prep"], ["bogus", "x"]]);
  check("Add makes a page", got.status === 200 && got.body.ok && /night-notes$/.test(got.body.href || ""), JSON.stringify(got.body).slice(0, 300));
  check("…under the heading it was asked for", under(got.body, "Prep").includes("night-notes"), JSON.stringify(under(got.body, "Prep")));
  check("…renamable, as his", row(got.body, "night-notes").renamable === true, JSON.stringify(row(got.body, "night-notes")));
  got = await act("add", [["name", "Night Notes"], ["type", "page"]]);
  check("a name taken is refused with the portal's reason", got.status === 422 && /already a page/.test(got.body.why || ""), JSON.stringify(got.body.why));

  // ---- Rename ----
  got = await act("night-notes", [["rename", "Night Exteriors"]]);
  check("Rename moves the address", got.status === 200 && got.body.ok && /night-exteriors$/.test(got.body.href || ""), JSON.stringify(got.body).slice(0, 300));
  check("…and keeps its place under the heading", under(got.body, "Prep").includes("night-exteriors"), JSON.stringify(under(got.body, "Prep")));
  // A page Notion names: renamed on the portal only, its address kept (2026-10-10)
  check("a Notion page is renamable on the portal", row(got.body, "directors-treatment").renamable === true, JSON.stringify(row(got.body, "directors-treatment")));
  got = await act("directors-treatment", [["rename", "Treatment"]]);
  check("…Rename keeps its address", got.status === 200 && got.body.ok && /directors-treatment$/.test(got.body.href || ""), JSON.stringify(got.body).slice(0, 300));
  check("…and wears the new name", row(got.body, "directors-treatment").name === "Treatment", JSON.stringify(row(got.body, "directors-treatment")));
  check("…still a Notion page", row(got.body, "directors-treatment").notion === true, JSON.stringify(row(got.body, "directors-treatment")));

  // ---- the iPhone's way: the same fields as JSON ----
  const json = (verb, body) => fetch(`${H}/console/${FILM}/act/${verb}`, {
    method: "POST", headers: { authorization: `Bearer ${TOKEN}`, "content-type": "application/json" }, body: JSON.stringify(body),
  }).then(async (r) => ({ status: r.status, body: await r.json().catch(() => ({})) }));
  got = await json("add", { name: "Phone Page", type: "page", head: "Prep" });
  check("JSON: Add makes a page under its heading", got.status === 200 && under(got.body, "Prep").includes("phone-page"), JSON.stringify(got.body.sidebar));
  got = await json("add", { name: "Phone File", type: "file", file: { name: "a.pdf", type: "application/pdf", base64: Buffer.from("%PDF-1.4 x").toString("base64") } });
  check("JSON: a file arrives as a document", got.status === 200 && /documents$/.test(got.body.href || ""), JSON.stringify(got.body).slice(0, 200));
  const now = got.body.sidebar;
  got = await json("order", { groups: [...now].reverse().map((g) => ({ name: g.head, rows: g.rows })) });
  check("JSON: the order is the rail's whole shape", got.status === 200 && heads(got.body).join() === [...now].reverse().map((g) => g.head).join(), JSON.stringify(heads(got.body)));
  got = await json("phone-page", { rename: "Phone Notes" });
  check("JSON: Rename moves the address", got.status === 200 && /phone-notes$/.test(got.body.href || ""), JSON.stringify(got.body).slice(0, 200));

  // ---- Icon ----
  got = await library({ keys: ["night-exteriors"], action: "icon", to: "star" });
  check("an icon is set", got.status === 200 && row(got.body, "night-exteriors").icon === "star", JSON.stringify(row(got.body, "night-exteriors")));
  got = await library({ keys: ["night-exteriors"], action: "icon", to: "" });
  check("…and put back to the default", row(got.body, "night-exteriors").icon === "page", JSON.stringify(row(got.body, "night-exteriors")));
  got = await library({ keys: ["night-exteriors"], action: "icon", to: "nonsense" });
  check("…never one that is not in the set", got.status === 404, String(got.status));
  // ---- a built-in page, renamed (2026-10-10: "rename any page") ----
  got = await act("shotlist", [["rename", "Shots"]]);
  check("a built-in page is renamed, its address kept", got.status === 200 && got.body.ok && /shotlist$/.test(got.body.href || ""), JSON.stringify(got.body).slice(0, 300));
  check("…and the sidebar says the new name", row(got.body, "shotlist").name === "Shots", JSON.stringify(row(got.body, "shotlist")));
  got = await act("script", [["rename", "Treatment"]]);
  check("…never onto a name another page has", got.status === 422 && /already a page/.test(got.body.why || ""), JSON.stringify(got.body).slice(0, 200));
  got = await act("bible", [["rename", "Look Book"]]);
  check("…the Visual Bible too", got.status === 200 && row(got.body, "bible").name === "Look Book", JSON.stringify(row(got.body, "bible")));
  got = await act("shotlist", [["rename", ""]]);
  check("…and an empty name puts the built-in one back", got.status === 200 && row(got.body, "shotlist").name === "Shot List", JSON.stringify(row(got.body, "shotlist")));
  const film = await fetch(`${H}/f/${FILM}/bible`, { headers: { authorization: `Bearer ${TOKEN}` } }).then((r) => r.text()).catch(() => "");
  check("…and the portal's own sidebar says it", /Look Book/.test(film), "no Look Book on the page");
  // the hourly refresh writes Notion's name back into sections and keeps the
  // card's other keys (refresh.py card.update): his name still wins
  put(`p/${FILM}/front.json`, JSON.stringify({ ...JSON.parse(readFileSync(join(box, `p_${FILM}_front.json`), "utf8")),
    labels: { "directors-treatment": "Treatment" } }));
  got = await library();
  check("…and keeps it after a Notion refresh", row(got.body, "directors-treatment").name === "Treatment", JSON.stringify(row(got.body, "directors-treatment")));
} finally {
  hub.kill("SIGTERM");
  await wait(500);
  spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
}
say(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
