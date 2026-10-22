#!/usr/bin/env node
/**
 * **A page that syncs from an outside document says so, to him** (2026-10-17,
 * his ask: "an indicator on a page ... so that I understand that that one's
 * syncing to a document, and then I'll link to that document"), and **People
 * are the record's** (his decision the same day: people from the project
 * record, documents not from Notion).
 *
 * - a page Live from Notion with its Notion page, and a page following a
 *   Google Doc with the switch on, each carry a Synced from line under the
 *   title, with the document's name, a link that opens it and when it last
 *   synced — for an editor only; a viewer gets none of it;
 * - the same on the sidebar row (a small mark) and in the Library (a Synced
 *   chip), editors only; a page that does not sync carries no mark;
 * - a card saved through the worker keeps the Notion page a page follows
 *   (`from`), so the clock still finds it;
 * - People and Documents no longer claim Notion;
 * - the record's crew lays the People list, contact details kept by name.
 *
 *     node hub/syncmark.mjs                 the checks
 *     node hub/syncmark.mjs --preview DIR   the crew rule over the backup mirror: what each live portal's
 *                                           People list would become (names only), nothing written
 *
 * No server, no bucket: the page is drawn the way the worker draws it.
 */
import { register } from "node:module";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

const { emptyFront, tidy, syncOf } = await import("./src/front.js");
const { recordBody, libraryBody } = await import("./src/pages.js");
const { layRecordCrew, layRecordFacts } = await import("./src/facts.js");

let pass = 0, fail = 0;
const check = (what, good, why = "not so") => {
  if (good) { pass += 1; console.log(`  ${what.padEnd(66)} PASS`); }
  else { fail += 1; console.log(`  ${what.padEnd(66)} FAIL — ${why}`); }
};

const BASE = "/f/chb";
const NOTION = "feedface00004000800000000000000c";
const DOC = "1ExampleGoogleDocIdCCCCCCCCCCCCCCCCCCCCCCCCC";
const ME = "owner@example.com";

const front = tidy({
  ...emptyFront(), title: "Call Her Back", updated: new Date(Date.now() - 3 * 3600e3).toISOString(),
  sections: [
    { slug: "bible", name: "Visual Bible", from: NOTION, title: "Call Her Back - Visual Language Bible", type: "page", source: "notion", notion: true },
    { slug: "outline", name: "Outline", by: "deck", type: "deck", source: "program", notion: false, follow: { doc: DOC, on: true, credit: "Ivy" } },
    { slug: "stopped", name: "Old Outline", by: "deck", type: "deck", source: "program", notion: false, follow: { doc: DOC, on: false } },
    { slug: "notes", name: "Notes", by: "mcp", type: "page", source: "here", notion: false },
  ],
  crew: [{ name: "Ravi Mehta", email: "amit@example.com", phone: "1" }],
  documents: [{ name: "Script", kind: "document", url: "https://drive.google.com/file/d/x/view", source: "here" }],
});
const TREE = [{ t: "p", text: "Words" }];

// ---- the card keeps what the clock needs
check("a card saved here keeps the Notion page a page follows", tidy(front).sections[0].from === NOTION, JSON.stringify(tidy(front).sections[0]));
check("…and a dashed id is kept bare", tidy({ sections: [{ slug: "b", name: "B", from: "feedface-0000-4000-8000-00000000000c", source: "notion" }] }).sections[0].from === NOTION);
check("a page Live from Notion syncs from its Notion page", (syncOf(front.sections[0]) || {}).url === `https://www.notion.so/${NOTION}`);
check("a page following a Google Doc syncs from it", (syncOf(front.sections[1]) || {}).kind === "gdoc");
check("a page whose follow is off does not", syncOf(front.sections[2]) === null);
check("a page written here does not", syncOf(front.sections[3]) === null);
check("a Notion page with no Notion page behind it does not", syncOf({ slug: "x", name: "X", source: "notion", notion: true }) === null);

// ---- the page
const bibleAs = (role) => recordBody(BASE, "Call Her Back", role, ME, front, "bible", false, TREE, false, undefined, role === "editor");
const ed = bibleAs("editor");
check("the Visual Bible says Synced from its Notion page, to him", /class="syncline"/.test(ed) && ed.includes("Synced from Call Her Back - Visual Language Bible"));
check("…the line opens the Notion page", ed.includes(`href="https://www.notion.so/${NOTION}" target="_blank"`));
check("…and says when", /class="syncwhen">3 hours ago</.test(ed), (ed.match(/syncwhen">[^<]*/) || [""])[0]);
check("…and the page menu says the same", /class="pmnote">Synced from Call Her Back - Visual Language Bible · 3 hours ago</.test(ed));
const vw = bibleAs("viewer");
check("a viewer gets no Synced from line", !/syncline|Synced from/.test(vw));

const made = "<div>the outline</div>";
const outline = (role, state) => recordBody(BASE, "Halcyon", role, ME, front, "outline", false, null, false, undefined, role === "editor", made,
  state ? { follow: state } : {});
const st = { title: "Halcyon Outline (Ivy)", drawn: new Date(Date.now() - 5 * 60e3).toISOString(), trouble: null };
const oe = outline("editor", st);
check("a page following a Google Doc says Synced from the doc's name", oe.includes("Synced from Halcyon Outline (Ivy)"));
check("…linking the doc", oe.includes(`href="https://docs.google.com/document/d/${DOC}/edit" target="_blank"`));
check("…and when it last redrew", /syncwhen">5 minutes ago</.test(oe));
check("…in its menu too", /pmnote">Synced from Halcyon Outline \(Ivy\) · 5 minutes ago</.test(oe));
check("…a failed check says so", outline("editor", { ...st, trouble: "Drive says no" }).includes("Last sync failed"));
check("…with no name yet it says Google Doc", outline("editor").includes("Synced from Google Doc"));
check("a viewer of it gets no line", !/syncline/.test(outline("viewer", st)));
check("a page whose follow is off has no line", !/syncline/.test(recordBody(BASE, "C", "editor", ME, front, "stopped", false, null, false, undefined, true, made)));

// ---- the rail and the Library
const railOf = (html) => (html.match(/<nav class="rail"[\s\S]*?<\/nav>/) || [""])[0];
const rail = railOf(ed);
const rowOf = (key) => (rail.match(new RegExp(`<a [^>]*data-key="${key}"[\\s\\S]*?</a>`)) || [""])[0];
check("his sidebar marks the Visual Bible as syncing", /syncico" title="Synced from Notion"/.test(rowOf("bible")), rowOf("bible").slice(0, 300));
check("…and the Outline", /syncico" title="Synced from Google Doc"/.test(rowOf("outline")));
check("…not People, Documents or a page written here", !/syncico/.test(rowOf("people") + rowOf("documents") + rowOf("notes")));
check("the old source dots are gone", !/srcdot/.test(rail));
check("a viewer's sidebar carries no mark", !/syncico/.test(railOf(vw)));
const lib = libraryBody(BASE, "Call Her Back", front, ME, "editor", false, "", { admin: true });
const libRow = (key) => (lib.match(new RegExp(`<div class="fh-lrow[^"]*" data-kind="[^"]*" data-key="${key}"[\\s\\S]*?</div>`)) || [""])[0];
check("his Library chips the syncing pages Synced", /fh-lchip">Synced</.test(libRow("bible")) && /fh-lchip">Synced</.test(libRow("outline")), libRow("bible").slice(0, 400));
check("…and no other page", !/Synced/.test(libRow("notes") + libRow("stopped")) && !/fh-lchip">Notion</.test(lib));

// ---- the labels
const people = recordBody(BASE, "N", "editor", ME, front, "people", false, null, false, undefined, true);
check("People says it is the record's", people.includes("From the Project Record") && !people.includes("Crew database"));
const docs = recordBody(BASE, "N", "editor", ME, front, "documents", false, null, false, undefined, true);
check("Documents no longer claims Notion", docs.includes("Added Here") && !/Notion/.test((docs.match(/pmnote">[^<]*/) || [""])[0]));

// ---- the record's crew
const card = {
  crew: [
    { name: "Marta Delgado", role: "Line Producer", department: "Above the Line", company: "", email: "r@x", phone: "2" },
    { name: "Gone Person", role: "Grip", department: "G&E", email: "g@x" },
  ],
  shoots: [
    { id: "4acab7b3-b555-897c-7c58-dce7762aca55", slug: "shoot-1", name: "Shoot 1", crew: [{ name: "Peter Lund", role: "Loader", department: "Camera", email: "a@x", phone: "3" }] },
    { id: "50ad95105a93869dd1c97f9e1a45a05a", slug: "shoot-2", name: "Shoot 2", crew: [] },
  ],
};
const facts = {
  crew: { v: 1, value: [
    { person: "p1", name: "Marta Delgado", roles: ["Line Producer", "Producer"], shoots: [], all_shoots: true },
    { person: "p2", name: "Peter Lund", roles: ["Loader / DIT"], shoots: ["4acab7b3b555897c7c58dce7762aca55"], all_shoots: false },
  ] },
  credits: { v: 1, value: [{ role: "Director", people: ["Ollie Hart Brennan"] }, { role: "Producer", people: ["Marta Delgado"] }] },
};
check("the record's crew lays the People list", layRecordCrew(card, facts) === true);
const names = card.crew.map((p) => p.name);
check("…everyone on the record and in a credit, nobody else", JSON.stringify(names) === JSON.stringify(["Marta Delgado", "Peter Lund", "Ollie Hart Brennan"]), names.join(", "));
check("…roles are the record's", card.crew[0].role === "Line Producer, Producer" && card.crew[1].role === "Loader / DIT");
check("…a credit-only name takes its credit", card.crew[2].role === "Director");
check("…contact details kept from the card by name, shoots included", card.crew[0].email === "r@x" && card.crew[1].phone === "3" && card.crew[1].department === "Camera");
check("…each shoot gets the people on it", card.shoots[0].crew.map((p) => p.name).join() === "Marta Delgado,Peter Lund,Ollie Hart Brennan"
  && card.shoots[1].crew.map((p) => p.name).join() === "Marta Delgado,Ollie Hart Brennan", card.shoots.map((s) => s.crew.map((p) => p.name).join("+")).join(" | "));
check("…laid twice it is no change", layRecordCrew(card, facts) === false);
check("…and through the record's facts too", layRecordFacts(card, facts).includes("crew") === false);
const bare = { crew: [{ name: "Keep Me" }] };
check("a record with no crew leaves the card's people alone", layRecordCrew(bare, {}) === false && bare.crew[0].name === "Keep Me");
const tidied = tidy({ ...emptyFront(), crew: [{ name: "Marta Delgado", role: "Line Producer, Producer", department: "Above the Line", email: "r@x", phone: "2" }] });
check("a card written by the worker (with empty notes) is no change", layRecordCrew(tidied, { crew: { value: [facts.crew.value[0]] } }) === false);

// ---- the preview over the mirror
const at = process.argv.indexOf("--preview");
if (at > 0) {
  const M = `${process.env.HOME}/Library/Mobile Documents/com~apple~CloudDocs/Shotlister Portal Backups/mirror/bucket`;
  const records = new Map();
  for (const page of readdirSync(join(M, "r"))) {
    const f = join(M, "r", page, "record.json");
    if (!existsSync(f)) continue;
    const r = JSON.parse(readFileSync(f, "utf8"));
    records.set(page, r);
    if (r.film && r.film.relay) records.set(r.film.relay, r);
  }
  console.log("\n  crew preview (names only):");
  for (const key of readdirSync(join(M, "p"))) {
    const f = join(M, "p", key, "front.json");
    if (!existsSync(f)) continue;
    const c = JSON.parse(readFileSync(f, "utf8"));
    const r = records.get(key) || records.get(String(c.console_page || "").replace(/-/g, ""));
    if (!r) { console.log(`  ${key.slice(0, 8)}  no record — left as it is`); continue; }
    const was = (c.crew || []).map((p) => p.name);
    const lost = (c.crew || []).filter((p) => p.email || p.phone).length;
    const changed = layRecordCrew(c, r.facts || {});
    const now = (c.crew || []).map((p) => p.name);
    const kept = (c.crew || []).filter((p) => p.email || p.phone).length;
    const added = now.filter((n) => !was.includes(n)), gone = was.filter((n) => !now.includes(n));
    console.log(`  ${key.slice(0, 8)}  ${((r.facts || {}).title || {}).value || "?"}: ${changed ? "changes" : "same"} · ${now.length} people`
      + `${added.length ? ` · added ${added.join(", ")}` : ""}${gone.length ? ` · gone ${gone.join(", ")}` : ""} · with contact ${lost}→${kept}`);
  }
}

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
