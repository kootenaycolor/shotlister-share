#!/usr/bin/env node
/**
 * A link added to a film is a page like any other (2026-10-13): on the
 * sidebar from the start, filed in a category by its name or its address,
 * private or public from the Library, archived and brought back — and the
 * Share panel lists it under its category, not in a list of its own.
 *
 * Local only: a throwaway bucket and a local hub, asked over plain requests
 * (no browser needed). Run it with `node hub/links.mjs`.
 */
import { spawn, spawnSync } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const FILM = "01a02852ebb00198e46a252100000001";
const PORT = 8796;
const WHO = "owner@example.com";
let pass = 0, fail = 0;
const check = (what, cond, why = "not so") => {
  if (cond) { pass += 1; console.log(`  ${what.padEnd(66)} PASS`); } else { fail += 1; console.log(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

const FRONT = {
  version: 1, logline: "x",
  sections: [{ slug: "night-look", name: "Night Look", by: "mcp", type: "page", source: "here" }],
  documents: [],
  crew: [],
};

const state = mkdtempSync(join(tmpdir(), "links-state-"));
const box = mkdtempSync(join(tmpdir(), "links-box-"));
const wr = join(HERE, "node_modules/.bin/wrangler");
const put = (key, body) => {
  const file = join(box, "f.bin");
  writeFileSync(file, body);
  spawnSync(wr, ["r2", "object", "put", `shotlister-preview/${key}`, "--file", file, "--local", "--persist-to", state], { cwd: HERE, stdio: "ignore" });
};
put(`p/${FILM}/manifest.json`, JSON.stringify({ format: 1, project: FILM, title: "Links Check", engine: "0.1.0" }));
put(`p/${FILM}/logs/0000000000000001-000000000000000a.log`, "shotlister-log 1\n");
put(`p/${FILM}/front.json`, JSON.stringify(FRONT));
put(`p/${FILM}/people.json`, JSON.stringify({ people: [{ email: "reader@example.com", role: "viewer" }], links: [] }));
put(`p/${FILM}/pages/night-look.json`, JSON.stringify([{ t: "p", r: [{ s: "Words." }] }]));

spawnSync("bash", ["-c", `lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null`], { stdio: "ignore" });
const hub = spawn(wr, ["dev", "--local", "--port", String(PORT), "--persist-to", state, "--var", "ACCESS_TEAM:", "--var", "ACCESS_AUD:", "--var", "CONSOLE_TOKEN:links-check-token-0123456789abcdef",
  "--var", "COMMIT:links-check", "--var", "DEPLOYED:2026-01-01T00:00:00Z"], { cwd: HERE, stdio: "ignore" });
const finish = (code) => {
  try { hub.kill("SIGTERM"); } catch { /* gone */ }
  spawnSync("bash", ["-c", `sleep 1; lsof -ti tcp:${PORT} | xargs kill -9 2>/dev/null; pkill -9 -f "wrangler.*dev --local --port ${PORT}"`], { stdio: "ignore" });
  rmSync(state, { recursive: true, force: true });
  rmSync(box, { recursive: true, force: true });
  process.exit(code);
};

try {
  let up = false;
  for (let i = 0; i < 45 && !up; i++) {
    await wait(1000);
    try { up = (await fetch(`http://127.0.0.1:${PORT}/health`)).ok; } catch { /* not yet */ }
  }
  if (!up) { console.log("the hub would not start"); finish(1); }

  const url = (path, who = WHO) => `http://127.0.0.1:${PORT}/f/${FILM}/${path}${path.includes("?") ? "&" : "?"}as=${who}`;
  const get = async (path, who) => (await fetch(url(path, who))).text();
  const post = (path, fields) => fetch(url(path), { method: "POST", redirect: "manual", body: new URLSearchParams(fields) });
  const rowOf = (html, key) => (html.match(new RegExp(`<div class="fh-lrow[^"]*"[^>]*data-key="${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"[^>]*>`)) || [""])[0];
  const onRail = (html, key) => new RegExp(`<nav class="rail"[\\s\\S]*?data-key="${key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}"`).test(html);

  console.log("A link is added");
  const mine = async (name, address) => post("add", { type: "link", name, url: address });
  let r = await mine("Stay in town", "https://www.airbnb.com/rooms/123");
  check("adding answers with a redirect", r.status === 303, String(r.status));
  check("…to the Library, not the Documents page", (r.headers.get("location") || "").endsWith("/library"), r.headers.get("location"));
  await mine("Mock scene cut", "https://livid.com/watch/abc");
  await mine("Weird thing", "https://example.com/x");
  const lib = await get("library");
  check("it is a row in the Library", rowOf(lib, "doc:Stay in town") !== "");
  check("filed under Logistical by its address (airbnb)", /data-shelf="Logistical"/.test(rowOf(lib, "doc:Stay in town")), rowOf(lib, "doc:Stay in town"));
  check("filed under Creative by its name", /data-shelf="Creative"/.test(rowOf(lib, "doc:Mock scene cut")), rowOf(lib, "doc:Mock scene cut"));
  check("a link nothing recognises goes to Other", /data-shelf="Other"/.test(rowOf(lib, "doc:Weird thing")), rowOf(lib, "doc:Weird thing"));

  console.log("On the sidebar");
  const home = await get("night-look");
  check("it is on the sidebar from the start", onRail(home, "doc:Stay in town"));
  const stored = JSON.parse(await (await fetch(url("library?part=pick"))).text());
  check("the sidebar's Add Pages panel says it is on", (stored.pages.find((p) => p.at === "doc:Stay in town") || {}).on === true, JSON.stringify(stored.pages));

  console.log("The Share panel");
  const share = await get("visibility?part=2");
  const groupOf = (name) => {
    const at = share.indexOf(`value="${name}"`);
    if (at < 0) return "";
    const heads = [...share.slice(0, at).matchAll(/<div class="sp-grp">([^<]*)<\/div>/g)];
    return heads.length ? heads[heads.length - 1][1] : "";
  };
  check("a link stands under its category there", groupOf("Stay in town") === "Logistical", groupOf("Stay in town"));
  check("…not in a list of its own", !/<div class="sp-grp">Documents<\/div>/.test(share));

  console.log("Private and public");
  const hid = await post("visibility", { flip: "documents:Stay in town", back: "library" });
  check("the switch answers", hid.status === 303 || hid.status === 200, String(hid.status));
  const asReader = await get("night-look", "reader@example.com");
  check("a viewer no longer sees it on the sidebar", !onRail(asReader, "doc:Stay in town"));
  const asEditor = await get("night-look");
  check("the editor still does, marked private", onRail(asEditor, "doc:Stay in town"));

  console.log("Archive");
  const arch = await post("library", { archive: "doc:Mock scene cut", on: "1" });
  check("archiving answers", arch.status === 303, String(arch.status));
  const after = await get("library");
  check("it is marked archived in the Library", /data-archived="1"/.test(rowOf(after, "doc:Mock scene cut")), rowOf(after, "doc:Mock scene cut"));
  check("and is off the sidebar", !onRail(await get("night-look"), "doc:Mock scene cut"));
  const docsPage = await get("documents");
  check("and off the Documents page", !docsPage.includes("Mock scene cut"));
  const shareAfter = await get("visibility?part=2");
  check("and out of the Share panel", !shareAfter.includes('value="Mock scene cut"'));
  check("the Documents page offers Archive, not Unpin", /name="archive"/.test(docsPage) && !/name="unpin"/.test(docsPage));
  await post("library", { archive: "doc:Mock scene cut", on: "0" });
  check("unarchiving brings it back", /data-archived="0"/.test(rowOf(await get("library"), "doc:Mock scene cut")));

  console.log("The Projects Console's sidebar list");
  const door = (path, init = {}) => fetch(`http://127.0.0.1:${PORT}/console/${FILM}/${path}`, {
    ...init, headers: { authorization: "Bearer links-check-token-0123456789abcdef", "content-type": "application/json" },
  });
  let said = await (await door("library")).json();
  const sideAts = (j) => (j.sidebar || []).flatMap((g) => g.rows);
  check("the sidebar list names the pinned link", sideAts(said).includes("doc:Stay in town"), JSON.stringify(said.sidebar));
  const under = (j, at) => ((j.sidebar || []).find((g) => g.rows.includes(at)) || {}).head;
  check("…under its category, as the portal's rail has it", under(said, "doc:Stay in town") === "Logistical", under(said, "doc:Stay in town"));
  const brow = (said.rows || []).find((x) => x.at === "doc:Stay in town") || {};
  check("…with a name, an icon and the link kind", brow.name === "Stay in town" && brow.type === "link" && brow.icon === "link" && brow.pinned === true, JSON.stringify(brow));
  const doclib = (said.documents || []).find((d) => d.name === "Stay in town") || {};
  check("the Library list says it is pinned, with its icon and kind", doclib.pinned === true && doclib.kind === "link" && doclib.icon === "link", JSON.stringify(doclib));
  // move it under Creative, as a drag on the Console does
  let moved = await (await door("act/order", { method: "POST", body: JSON.stringify({ groups: (said.sidebar || []).map((g) => ({ name: g.head === "Logistical" ? "Creative" : g.head, rows: g.rows })) }) })).json();
  check("dragging it to another heading files it there", under(moved, "doc:Stay in town") === "Creative", under(moved, "doc:Stay in town"));
  await mine("Dailies, day 1", "https://livid.com/watch/dailies");
  const withComma = await (await door("library")).json();
  moved = await (await door("act/order", { method: "POST", body: JSON.stringify({ groups: (withComma.sidebar || []).map((g) => ({ name: g.head, rows: g.rows })) }) })).json();
  check("a link with a comma in its name survives a drag", sideAts(moved).includes("doc:Dailies, day 1") && !sideAts(moved).some((a) => a === "doc:Dailies" || a === "day 1"), JSON.stringify(sideAts(moved)));
  const off = await (await door("library", { method: "PUT", body: JSON.stringify({ keys: ["doc:Stay in town"], action: "unpin" }) })).json();
  check("Remove from Sidebar takes it off the list", !sideAts(off).includes("doc:Stay in town") && (off.rows || []).some((x) => x.at === "doc:Stay in town" && x.pinned === false), JSON.stringify(off.sidebar));
  const on = await (await door("library", { method: "PUT", body: JSON.stringify({ keys: ["doc:Stay in town"], action: "pin" }) })).json();
  check("Add Pages puts it back", sideAts(on).includes("doc:Stay in town"));
} catch (e) {
  fail += 1;
  console.log("  the check broke:", e && e.message);
}
console.log(`\n${pass} passed, ${fail} failed`);
finish(fail ? 1 : 0);
