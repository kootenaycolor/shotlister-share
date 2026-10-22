#!/usr/bin/env node
/**
 * **Drive files on the portal's Documents page** (portaldocs.js, his decision
 * 2026-10-17): he switches a file on in Projects Console; the record keeps the
 * choice (`portal_docs`); the Documents page lists it, grouped and newest
 * first, opening it through the portal.
 *
 *     node hub/portaldocs.mjs
 *
 * No server, no bucket, no Drive: a fake Drive and a fake record.
 */
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

const pd = await import("./src/portaldocs.js");
const { emptyFront, tidy } = await import("./src/front.js");
const { recordBody } = await import("./src/pages.js");
const { layRecordFacts } = await import("./src/facts.js");
const { bothKinds } = await import("./src/notion.js");

let pass = 0, fail = 0;
const check = (what, good, why = "not so") => {
  if (good) { pass += 1; console.log(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; console.log(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

// ---- the rules
check("a call sheet is Schedule & Call Sheets", pd.groupOf({ name: "Call Sheet Day 1.pdf", path: "2-logistics" }) === "Schedule & Call Sheets");
check("the current draft is Script", pd.groupOf({ name: "Film - Draft 6.pdf", path: "1-creative/script/current-draft" }) === "Script");
check("a look book is Creative", pd.groupOf({ name: "Look Book.pdf", path: "1-creative/decks/look-book" }) === "Creative");
check("a deal memo is Other", pd.groupOf({ name: "Deal Memo.docx", path: "4-financial" }) === "Other");
check("PDFs, pictures, Docs, Sheets and video are shareable",
  ["a.pdf", "a.jpg", "a.mov"].every((name) => pd.shareable({ name })) && pd.shareable({ name: "x", mime: "application/vnd.google-apps.spreadsheet" }));
check("project files and LUTs are not", !pd.shareable({ name: "grade.drp" }) && !pd.shareable({ name: "show.cube" }) && !pd.shareable({ name: "x.json" }));
check("z-archive and z-source are working folders", pd.working("1-creative/script/z-archive") && pd.working("1-creative/decks/x/z-source") && !pd.working("2-logistics"));
check("suggested: call sheets, the current draft, decks", pd.suggested({ name: "Call Sheet.pdf", path: "2-logistics" })
  && pd.suggested({ name: "D6.pdf", path: "1-creative/script/current-draft" }) && pd.suggested({ name: "Look Book.pdf", path: "1-creative/decks/look-book" }));
check("…not an old draft in z-archive", !pd.suggested({ name: "Call Sheet.pdf", path: "2-logistics/z-archive" }));
check("the portal name drops .pdf", pd.shownName("Call Sheet Day 1.pdf") === "Call Sheet Day 1");
check("a Google Sheet says Sheet", pd.typeOf({ name: "Schedule", mime: "application/vnd.google-apps.spreadsheet" }) === "Sheet");

// ---- a fake Drive
const ROOT = "rootfolder000001";
const F = (id, name, parent, mime = "application/pdf", modified = "2026-10-10T10:00:00.000Z") => ({ id, name, parents: [parent], mime, folder: mime === "application/vnd.google-apps.folder", modified, size: 1000 });
const DIR = "application/vnd.google-apps.folder";
const tree = [
  F("logistics0000001", "2-logistics", ROOT, DIR), F("creative00000001", "1-creative", ROOT, DIR),
  F("callsheet0000001", "Call Sheet Day 1.pdf", "logistics0000001", "application/pdf", "2026-10-14T10:00:00.000Z"),
  F("callsheet0000002", "Call Sheet Day 2.pdf", "logistics0000001", "application/pdf", "2026-10-15T10:00:00.000Z"),
  F("script0000000001", "script", "creative00000001", DIR), F("current000000001", "current-draft", "script0000000001", DIR),
  F("draft00000000006", "Film - Draft 6.pdf", "current000000001"),
  F("cache00000000001", "CacheClip", ROOT, DIR), F("cachefile0000001", "x.pdf", "cache00000000001"),
  F("outside000000001", "Elsewhere.pdf", "otherfolder00001"),
];
const api = {
  async list(parent) { return tree.filter((f) => f.parents.includes(parent)); },
  async get(id) { return tree.find((f) => f.id === id) || (id === "otherfolder00001" ? { id, name: "x", parents: [] } : null); },
};
const walked = await pd.walkFolder(api, ROOT);
check("the walk finds every file under the folder", walked.files.length === 3, JSON.stringify(walked.files.map((f) => f.name)));
check("…with where each is", walked.files.find((f) => f.id === "draft00000000006").path === "1-creative/script/current-draft");
check("…and never walks into a cache", !walked.files.some((f) => f.id === "cachefile0000001"));

// ---- the door, with a fake record
let record = { page: "p", facts: { drive_folder: { value: `https://drive.google.com/drive/folders/${ROOT}`, v: 1 } } };
const writes = [];
const deps = {
  api,
  recordOf: async () => record,
  writeFacts: async (env, page, changes, by) => {
    for (const [field, ch] of Object.entries(changes)) {
      const v = (record.facts[field] && record.facts[field].v) || 0;
      if ((ch.base || 0) !== v) return { status: 409, conflicts: {} };
      record = { ...record, facts: { ...record.facts, [field]: { value: ch.value, v: v + 1, by } } };
    }
    writes.push(changes);
    return { status: 200, facts: record.facts };
  },
};
const put = (body) => pd.portalDocsDoor({}, "p", "PUT", async () => body, deps).then((r) => r.json().then((j) => ({ status: r.status, ...j })));
const got = await (await pd.portalDocsDoor({}, "p", "GET", null, deps)).json();
check("the listing names the folder and every file", got.folder.id === ROOT && got.files.length === 3);
check("…newest first, with type, group and suggested", got.files[0].id === "callsheet0000002" && got.files[0].type === "PDF" && got.files[0].suggested && got.files[0].group === "Schedule & Call Sheets");
check("…nothing is on the portal until he says so", got.chosen.length === 0 && got.files.every((f) => !f.on));
const one = await put({ id: "callsheet0000001", on: true, by: "mac" });
check("switching one on keeps it on the record", one.status === 200 && record.facts.portal_docs.value.length === 1 && record.facts.portal_docs.value[0].name === "Call Sheet Day 1.pdf");
check("…with where it is", record.facts.portal_docs.value[0].path === "2-logistics", record.facts.portal_docs.value[0].path);
await put({ id: "draft00000000006", on: true });
check("a second one joins it", record.facts.portal_docs.value.length === 2);
const twice = await put({ id: "draft00000000006", on: true });
check("switching on twice changes nothing", twice.chosen.length === 2 && record.facts.portal_docs.v === 2);
const out = await put({ id: "outside000000001", on: true });
check("a file outside the project folder is refused", out.status === 400 && record.facts.portal_docs.value.length === 2);
const bad = await put({ id: "../etc", on: true });
check("a made-up id is refused", bad.status === 400);
// a rename in Drive follows through on the next read
tree.find((f) => f.id === "callsheet0000001").name = "Call Sheet Day 1 (rev).pdf";
const again = await (await pd.portalDocsDoor({}, "p", "GET", null, deps)).json();
check("a file renamed in Drive takes its new name", record.facts.portal_docs.value[0].name === "Call Sheet Day 1 (rev).pdf" && again.files.find((f) => f.id === "callsheet0000001").on);

// ---- the card
const card = tidy({ ...emptyFront(), title: "Film", documents: [{ name: "Look Book", kind: "lookbook", file: "a".repeat(32) + ".pdf", source: "here" }] });
layRecordFacts(card, record.facts, []);
const laid = tidy(card);
const drive = laid.documents.filter((d) => d.source === "drive");
check("the chosen files are on the card, the held look book kept", drive.length === 2 && laid.documents.some((d) => d.name === "Look Book"), JSON.stringify(laid.documents.map((d) => [d.name, d.source])));
check("…named without .pdf, with type, date and group", drive[0].name === "Call Sheet Day 1 (rev)" && drive[0].type === "PDF" && drive[0].modified && drive[0].group === "Schedule & Call Sheets", JSON.stringify(drive[0]));
check("a saved card lays the same again (no change each pass)", layRecordFacts(laid, record.facts, []).includes("documents") === false);
check("Notion's both_kinds keeps Drive files", bothKinds(laid.documents, []).filter((d) => d.source === "drive").length === 2);
await put({ id: "callsheet0000001", on: false });
layRecordFacts(laid, record.facts, []);
check("switching one off takes it off the card", laid.documents.filter((d) => d.source === "drive").length === 1);
check("a record with no choice leaves the card's documents", (() => { const c = tidy({ ...emptyFront(), documents: [{ name: "X", url: "https://example.com", source: "here" }] }); layRecordFacts(c, {}, []); return c.documents.length === 1; })());

// ---- the page
const page = tidy({ ...emptyFront(), title: "Film", documents: [
  { name: "Call Sheet Day 2", source: "drive", drive: "callsheet0000002", url: "https://drive.google.com/file/d/callsheet0000002/view", type: "PDF", modified: "2026-10-15T10:00:00.000Z", group: "Schedule & Call Sheets" },
  { name: "Call Sheet Day 1", source: "drive", drive: "callsheet0000001", url: "https://drive.google.com/file/d/callsheet0000001/view", type: "PDF", modified: "2026-10-14T10:00:00.000Z", group: "Schedule & Call Sheets" },
  { name: "Film - Draft 6", source: "drive", drive: "draft00000000006", url: "https://drive.google.com/file/d/draft00000000006/view", type: "PDF", modified: "2026-10-09T10:00:00.000Z", group: "Script" },
  { name: "Look Book", kind: "lookbook", file: "a".repeat(32) + ".pdf", source: "here" },
] });
const as = (role) => recordBody("/f/film", "Film", role, "x@example.com", page, "documents", false, null, false, undefined, role === "editor");
const v = as("viewer");
const heads = [...v.matchAll(/class="blockhead">([^<]*)</g)].map((m) => m[1]);
const at = (s) => v.indexOf(s);
check("the page groups: Schedule & Call Sheets, Script, Creative", JSON.stringify(heads) === JSON.stringify(["Schedule &amp; Call Sheets", "Script", "Creative"]), JSON.stringify(heads));
check("…newest first", at("Call Sheet Day 2") < at("Call Sheet Day 1"));
check("…with type and date", /PDF · Oct 15/.test(v));
check("a Drive file opens through the portal, not Drive", v.includes('href="/f/film/drive/callsheet0000002"') && !v.includes("drive.google.com/file"));
check("…a viewer gets no Drive link or controls", !/drivego|Rename|Archive/.test(v));
const e = as("editor");
check("he gets a Drive ↗ link, no Rename, on a Drive file", e.includes("drivego") && e.includes("https://drive.google.com/file/d/callsheet0000002/view") && (e.match(/class="unpin renamedoc"/g) || []).length === 1, String((e.match(/class="unpin renamedoc"/g) || []).length));
check("a long name carries its full name on hover", v.includes('title="Call Sheet Day 2"'));

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
