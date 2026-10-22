#!/usr/bin/env node
/**
 * **The server's Drive moves** (`src/drivemoves.js`, stage 5 step 7):
 * - the client: what each call sends Google (rename keeps the id, a move is
 *   addParents/removeParents, trash and untrash are the `trashed` flag; there
 *   is no delete) — against a stand-in `fetch`;
 * - the fence: anything outside the cinematography and scratch folders, and
 *   the top folders themselves, refused before Google is asked; a move into
 *   itself refused; a look has no write calls at all;
 * - `placeOf`, `weigh`.
 *
 *     node hub/drivemoves.mjs        (PLANT=1 plants a wrong answer)
 */
import * as M from "./src/drivemoves.js";
import { driveOf } from "./bigmovesworld.mjs";
import { readFileSync } from "node:fs";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(84)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};
async function throws(fn) { try { await fn(); return null; } catch (e) { return e; } }

console.log("the client");
{
  const sent = [];
  globalThis.fetch = async (url, init = {}) => {
    sent.push({ url: String(url), method: init.method || "GET", body: init.body ? String(init.body) : "" });
    if (String(url).endsWith("/token")) return new Response(JSON.stringify({ access_token: "t", expires_in: 3600 }));
    if ((init.method || "GET") === "GET") return new Response(JSON.stringify({ id: "folder00001", name: "x", mimeType: "application/vnd.google-apps.folder", parents: ["parent0001"] }));
    return new Response(JSON.stringify({ id: "folder00001", name: "x", mimeType: "application/vnd.google-apps.folder", parents: ["parent0002"] }));
  };
  const env = { GDRIVE_WRITE: JSON.stringify({ client_id: "c", client_secret: "s", refresh_token: "r" }), GOOGLE_FAKE: "http://127.0.0.1:9" };
  const look = M.driveMovesApi(env, { write: false });
  check("a look can read and nothing else", typeof look.get === "function" && !look.rename && !look.move && !look.trash && !look.untrash && !look.mkdir);
  const api = M.driveMovesApi(env, { write: true });
  check("there is no delete", !("delete" in api) && !Object.keys(api).some((k) => /delete|remove|empty/i.test(k)));
  await api.rename("folder00001", "new-name");
  const r = sent.at(-1);
  check("rename: a PATCH of the name, the same id", r.method === "PATCH" && r.url.includes("/files/folder00001?") && JSON.parse(r.body).name === "new-name");
  await api.move("folder00001", "parent0001", "parent0002");
  const m = sent.at(-1);
  check("move: addParents and removeParents, the same id", m.method === "PATCH" && m.url.includes("addParents=parent0002") && m.url.includes("removeParents=parent0001") && m.url.includes("/files/folder00001?"));
  await api.trash("folder00001");
  check("trash: trashed true (the Drive's own trash)", JSON.parse(sent.at(-1).body).trashed === true && sent.at(-1).method === "PATCH");
  await api.untrash("folder00001");
  check("untrash: trashed false", JSON.parse(sent.at(-1).body).trashed === false);
  check("a bad id is refused before Google is asked", Boolean(await throws(() => api.rename("../x", "y"))));
  check("no sign-in, no Drive", M.driveMovesApi({}, { write: true }) === null);
  check("drivewrite.js stays create-only", !/removeParents|trashed: true/.test(readFileSync(new URL("./src/drivewrite.js", import.meta.url), "utf8")));
}

console.log("the fence");
{
  const d = driveOf();
  const cine = d.add(null, "cinematography", true, "cineRoot000001");
  const projects = d.add(cine, "projects", true, "projRoot000001");
  const scratch = d.add(null, "zz-step7-scratch", true, "scratch0000001");
  const elsewhere = d.add(null, "Personal", true, "personal000001");
  const theirs = d.add(elsewhere, "taxes", true, "taxes000000001");
  const proj = d.add(projects, "lets-bake", true, "letsbake000001");
  const deep = d.add(proj, "3-post");
  const test = d.add(scratch, "zz-step7-test", true, "zztest00000001");
  const g = M.guarded(d, { roots: [cine, scratch], keep: [projects] });
  const out = await throws(() => g.trash(theirs));
  check("trash outside the roots is refused, Google never asked", out instanceof M.OutsideRoots && !d.items.get(theirs).trashed && !d.calls.some((c) => c[0] === "trash"));
  check("rename outside is refused", (await throws(() => g.rename(theirs, "x"))) instanceof M.OutsideRoots && d.items.get(theirs).name === "taxes");
  check("moving a folder out of the roots is refused", (await throws(() => g.move(proj, projects, elsewhere))) instanceof M.OutsideRoots && d.items.get(proj).parent === projects);
  check("moving one in from outside is refused", (await throws(() => g.move(theirs, elsewhere, projects))) instanceof M.OutsideRoots);
  check("the cinematography folder itself is never moved or trashed", (await throws(() => g.trash(cine))) instanceof M.OutsideRoots && (await throws(() => g.rename(scratch, "x"))) instanceof M.OutsideRoots);
  check("a section root (projects/) is never moved", (await throws(() => g.rename(projects, "projects-old"))) instanceof M.OutsideRoots);
  check("into itself is refused", (await throws(() => g.move(proj, projects, deep))) instanceof M.OutsideRoots);
  await g.rename(proj, "lets-bake-2");
  check("inside: rename works, id kept", d.items.get(proj).name === "lets-bake-2");
  await g.trash(test);
  await g.untrash(test);
  check("inside the scratch folder: trash and untrash work", !d.items.get(test).trashed && d.calls.filter((c) => c[0] === "trash").length === 1);
  await g.move(test, scratch, projects);
  check("a move between the roots works", d.items.get(test).parent === projects);
  check("no roots, no moves", (await throws(async () => M.guarded(d, { roots: [] }))) instanceof M.OutsideRoots);
  const place = await M.placeOf(d, deep, [cine, scratch]);
  check("placeOf: the root and the path under it", place.root === cine && place.path === "projects/lets-bake-2/3-post");
  check("placeOf: outside answers null", (await M.placeOf(d, theirs, [cine, scratch])) === null);
  d.add(deep, "a.png", false); d.add(deep, ".hidden", false); d.add(proj, "b.txt", false);
  const wgt = await M.weigh(d, proj);
  check("weigh: files and folders under it, hidden files not counted", wgt.files === 2 && wgt.folders === 1 && wgt.items === 3 && !wgt.partial, JSON.stringify(wgt));
  check("no step 7 Drive file names a media drive", !/\/Volumes/.test(readFileSync(new URL("./src/drivemoves.js", import.meta.url), "utf8")));
}

if (process.env.PLANT === "1") check("planted: this must fail", false, "planted");
console.log(`\ndrivemoves: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
