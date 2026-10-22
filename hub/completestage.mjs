#!/usr/bin/env node
/**
 * **Complete, and Notion's waiting list in order** (2026-10-20, his answers
 * to the console audit's #6, #8 and #9), on a bucket held in memory:
 *
 * - `stageword.js`: either word is the record's "Released"; Notion's
 *   "Complete" is read as it, and "Released" is said to Notion as "Complete";
 * - a crew edit and a document's Hub tick wait when Notion is out of reach,
 *   and are made the first time it answers;
 * - a part Notion refuses holds back the later parts for its project (one
 *   quiet line), and no other project's; Notion out of reach says nothing.
 *
 *     node --import ./hub/nodehook.mjs hub/completestage.mjs
 */
import { bucketOf } from "./bigmovesworld.mjs";

let passed = 0, failed = 0;
function check(name, ok, said = "") {
  if (ok) passed++; else failed++;
  console.log(`  ${name.padEnd(90).slice(0, 90)} ${ok ? "PASS" : `FAIL — ${said}`}`);
}

const S = await import("./src/stageword.js");
const W = await import("./src/notionwaits.js");

// ── the words ──
check("either word is the record's Released; he reads Complete",
  ["Complete", "Released", " complete ", "RELEASED"].every((w) => S.canonStage(w) === "Released" && S.shownStage(w) === "Complete")
  && ["Development", "Active", "Post", "Archived", "Closed", ""].every((w) => S.canonStage(w) === w && S.shownStage(w) === w));
{
  const page = { properties: { Status: { type: "select", select: { name: "Complete" } }, Type: { select: { name: "Complete" } } } };
  const q = { results: [JSON.parse(JSON.stringify(page)), { properties: { Status: { select: { name: "Wrapped" } } } }] };
  const ds = { properties: { Status: { select: { options: [{ id: "a", name: "Post" }, { id: "645d", name: "Complete" }] } } } };
  S.notionIn(page); S.notionIn(q); S.notionIn(ds);
  check("Notion's Complete reads as Released: a page, a query, a schema; nothing else touched",
    page.properties.Status.select.name === "Released" && page.properties.Type.select.name === "Complete"
    && q.results.map((r) => r.properties.Status.select.name).join() === "Released,Wrapped"
    && ds.properties.Status.select.options.map((o) => o.name).join() === "Post,Released");
  const body = { properties: { Status: { select: { name: "Released" } } } };
  const out = S.notionOut(body);
  check("Released is sent to Notion as its option's id (the API can't rename it); the caller's body untouched; other stages by name",
    JSON.stringify(out.properties.Status.select) === JSON.stringify({ id: "feedface-0000-4000-8000-000000000007" }) && S.OPTION_ID === "feedface-0000-4000-8000-000000000007"
    && body.properties.Status.select.name === "Released"
    && S.notionOut({ properties: { Status: { select: { name: "Post" } } } }).properties.Status.select.name === "Post" && S.notionOut(null) === null);
}

// ── the waiting list ──
const P1 = "79199ff67a0385852f11c1eb47a4821f", P2 = "8f8312387570842ce1ec42091f2fae2a";
const fresh = () => ({ BUCKET: bucketOf() });
const down = () => { throw new TypeError("fetch failed"); };          // no connection: notionDown
const refuse = () => { throw new Error("Notion: validation_error — no"); };

{
  const env = fresh();
  await W.addWait(env, { kind: "crew-edit", project: P1, page: P1, shoot: "crew1", changes: { on_project: true, add_shoots: ["s1"], remove_shoots: [] }, label: "Crew" });
  await W.addWait(env, { kind: "crew-edit", project: P1, page: P1, shoot: "crew1", changes: { on_project: null, add_shoots: ["s2"], remove_shoots: ["s1"] }, label: "Crew" });
  await W.addWait(env, { kind: "crew-edit", project: P2, page: P2, shoot: "crew1", changes: { on_project: true, add_shoots: [], remove_shoots: [] }, label: "Crew" });
  const items = await W.waitsList(env);
  check("one person's edits on one project wait as one, the later wins; another project's are their own",
    items.length === 2 && JSON.stringify(items[0].changes) === JSON.stringify({ on_project: true, add_shoots: ["s2"], remove_shoots: ["s1"] }), JSON.stringify(items));
  const said = await W.flushWaits(env, down);
  check("Notion out of reach: everything waits, no try counted, nothing said", said.length === 0 && (await W.waitsList(env)).every((x) => !x.tries), JSON.stringify(said));
}
{
  const env = fresh();
  await W.addWait(env, { kind: "doc-hub", project: P1, page: "doc1", status: "on", label: "Daybreak" });
  await W.addWait(env, { kind: "doc-hub", project: P1, page: "doc1", status: "off", label: "Daybreak" });
  const sent = [];
  const said = await W.flushWaits(env, async (path, method = "GET", body) => { sent.push([path, method, body]); return {}; });
  check("a document's Hub tick waits as one (his last word) and is made when Notion answers",
    JSON.stringify(sent) === JSON.stringify([["pages/doc1", "PATCH", { properties: { Hub: { checkbox: false } } }]])
    && said[0] === "Daybreak · document in Notion, kept from earlier" && !(await W.waitsList(env)).length, JSON.stringify({ sent, said }));
}
{
  const env = fresh();
  await W.addWait(env, { kind: "project-status", project: P1, page: P1, status: "Released", label: "Daybreak" });
  await W.addWait(env, { kind: "project-title", project: P1, page: P1, status: "Daybreak II", label: "Daybreak II" });
  await W.addWait(env, { kind: "project-status", project: P2, page: P2, status: "Active", label: "Halcyon" });
  const sent = [];
  let said = await W.flushWaits(env, async (path, method = "GET", body) => {
    sent.push(`${method} ${path}`);
    if (method === "GET") return { properties: { Status: { select: { name: "Post" } } } };
    if (path === `pages/${P1}` && body.properties.Status) refuse();
    return {};
  });
  const left = await W.waitsList(env);
  check("a refused part holds back the later ones for its project only, and says so once",
    JSON.stringify(sent) === JSON.stringify([`GET pages/${P1}`, `PATCH pages/${P1}`, `GET pages/${P2}`, `PATCH pages/${P2}`])
    && JSON.stringify(said) === JSON.stringify(["Halcyon · Active in Notion, kept from earlier", "Daybreak II · waits for the change before it"])
    && left.length === 2 && left[0].tries === 1 && !left[1].tries, JSON.stringify({ sent, said, left }));
  const bodies = [];
  said = await W.flushWaits(env, async (path, method = "GET", body) => { if (method === "GET") return { properties: { Status: { select: { name: "Post" } } } }; bodies.push(body); return {}; });
  check("once Notion takes it, both go, in order, and the stage reads Complete",
    bodies.length === 2 && bodies[0].properties.Status.select.name === "Released" && bodies[1].properties.Project
    && said[0] === "Daybreak · Complete in Notion, kept from earlier" && !(await W.waitsList(env)).length, JSON.stringify({ bodies, said }));
}
{
  const env = fresh();
  await W.addWait(env, { kind: "project-status", project: P1, page: P1, status: "Released", label: "Daybreak" });
  const writes = [];
  await W.flushWaits(env, async (path, method = "GET") => { if (method === "GET") return { properties: { Status: { select: { name: "Released" } } } }; writes.push(path); return {}; });
  check("a stage Notion already has (read through stageword) is let go without a write", !writes.length && !(await W.waitsList(env)).length);
}

{
  // a crew edit kept while Notion was out, made against the Crew row when it answers
  const env = fresh();
  await W.addWait(env, { kind: "crew-edit", project: P1, page: P1, shoot: "crew1", changes: { on_project: true, add_shoots: ["shoot2"], remove_shoots: [] }, label: "Crew" });
  const row = { id: "crew1", properties: { Projects: { relation: [{ id: P2 }] }, Shoots: { relation: [{ id: "shoot1" }] } } };
  const sent = [];
  const said = await W.flushWaits(env, async (path, method = "GET", body) => {
    if (method === "PATCH") { sent.push(body); for (const [k, v] of Object.entries(body.properties)) row.properties[k] = v; return {}; }
    return JSON.parse(JSON.stringify(row));
  });
  check("a waiting crew edit is made when Notion answers: on the project, the shoot added, nothing else lost",
    sent.length === 1 && row.properties.Projects.relation.map((r) => r.id).join() === `${P2},${P1}`
    && row.properties.Shoots.relation.map((r) => r.id).join() === "shoot1,shoot2"
    && said[0] === "Crew · crew in Notion, kept from earlier" && !(await W.waitsList(env)).length, JSON.stringify({ sent, said }));
}

{
  // the server's own crew edit and Hub tick with Notion out of reach (nothing answers on port 9): they wait
  const C = await import("./src/cloud.js");
  const env = { ...fresh(), NOTION_TOKEN: "stand-in", NOTION_API: "http://127.0.0.1:9/v1/" };
  await env.BUCKET.put(C.NAMES_KEY, JSON.stringify({ names: { Daybreak: P1 } }));
  const crew = await C.answerHere(env, "crew_edit", ["Daybreak", "crew-1", true, ["s1"], null, null]);
  const doc = await C.answerHere(env, "set_document_on_portal", ["Daybreak", "doc-1", true]);
  const items = await W.waitsList(env);
  check("crew_edit with Notion out: done, \"Notion waits\", kept for later",
    crew && crew.state === "done" && crew.result.ok && crew.result.waits === W.QUIET
    && items.some((x) => x.kind === "crew-edit" && x.page === P1 && x.shoot === "crew1" && x.changes.add_shoots[0] === "s1"), JSON.stringify({ crew, items }));
  check("set_document_on_portal with Notion out: done, \"Notion waits\", kept for later",
    doc && doc.state === "done" && doc.result.ok && doc.result.waits === W.QUIET
    && items.some((x) => x.kind === "doc-hub" && x.page === "doc1" && x.status === "on" && x.project === P1), JSON.stringify({ doc, items }));
  const none = await C.answerHere(env, "crew_edit", ["Nowhere", "crew-1", true, null, null, null]);
  check("…a project the server has no record of still says the quiet line, nothing kept", none && none.state === "failed" && none.error === W.QUIET && (await W.waitsList(env)).length === 2, JSON.stringify(none));
}

console.log(`completestage: ${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
