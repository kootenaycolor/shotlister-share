#!/usr/bin/env node
/**
 * **The portal refresh reads Notion only for pages set up to follow it**
 * (2026-10-17).
 *
 * His word: "Synopsis and logline now come from the portal, not Notion. Only
 * certain pages copy Notion text, if it was started with that intent." A page
 * follows Notion when it says so (`source: "notion"`, Live from Notion) and
 * names the Notion page it came from (`from`). Checked against a Notion
 * stand-in in this process (nothing reaches his workspace) and a bucket in
 * memory:
 *
 * - a card with no such page: Notion is never asked, and no line about it;
 * - a following page is drawn again from its own Notion page, and nothing
 *   else on the card (logline, documents, people, other pages) moves;
 * - a one-ID portal (minted ID, projectid.js) is never looked up in Notion by
 *   that ID — the page's own Notion id is all that is asked for;
 * - the record's facts are still laid on the card.
 *
 * Every check about Notion fails on the refreshhub.js before this date (it
 * read the whole row, said "env is not defined", and asked Notion for the
 * minted ID).
 *
 *     node hub/refreshnotion.mjs
 */
import { register } from "node:module";

register(`data:text/javascript,${encodeURIComponent(`
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  if (url.endsWith(".wasm")) return { format: "module", shortCircuit: true, source: "export default null;" };
  return next(url, context);
}`)}`, import.meta.url);

const RH = await import("./src/refreshhub.js");
const W = await import("./bigmovesworld.mjs");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(84)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 700)}`}`);
};

const PLAIN = "ffffffffffffffffffffffffffff0a01";    // an older portal, no page following Notion
const OLD = "ffffffffffffffffffffffffffff0a02";      // an older portal with one following page
const MINTED = "ffffffffffffffffffffffffffff0b03";   // a one-ID portal (minted ID) with one following page
const PAGE_B = "ffffffffffffffffffffffffffff0c04";   // …its Notion project row
const BIBLE = "ffffffffffffffffffffffffffff0d05";    // the Notion page OLD's Visual Bible came from
const NOTES = "ffffffffffffffffffffffffffff0d06";    // the Notion page MINTED's Notes came from

// ---- a small Notion, answered in this process
const rt = (s) => [{ plain_text: s, text: { content: s } }];
const para = (id, s) => ({ object: "block", id, type: "paragraph", has_children: false, paragraph: { rich_text: rt(s) } });
const BLOCKS = new Map([[BIBLE, [para("b1", "Notion's bible, line one."), para("b2", "Line two.")]], [NOTES, [para("n1", "Notion's notes.")]]]);
const row = (id, logline) => ({ object: "page", id, properties: { Project: { type: "title", title: rt("zz") }, Logline: { type: "rich_text", rich_text: rt(logline) } } });
const ROWS = new Map([[OLD, row(OLD, "Notion's logline")], [PLAIN, row(PLAIN, "Notion's logline")], [PAGE_B, row(PAGE_B, "Notion's logline")]]);
const asked = [];
const realFetch = globalThis.fetch;
globalThis.fetch = async (url) => {
  const u = String(url);
  if (!u.startsWith("https://api.notion.com/v1/")) return new Response("no", { status: 404 });
  const path = u.slice("https://api.notion.com/v1/".length).split("?")[0];
  asked.push(path);
  const answer = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  if (path === "users/me") return answer({ object: "user", name: "Check" });
  if (/^data_sources\//.test(path)) return answer({ object: "list", results: path.includes("feedface-0000-4000-8000-000000000001") ? [...ROWS.values()] : [], has_more: false });
  let m = /^blocks\/([0-9a-f-]+)\/children$/.exec(path);
  if (m) return answer({ object: "list", results: BLOCKS.get(m[1].replace(/-/g, "")) || [], has_more: false });
  m = /^pages\/([0-9a-f-]+)$/.exec(path);
  if (m && ROWS.has(m[1].replace(/-/g, ""))) return answer(ROWS.get(m[1].replace(/-/g, "")));
  return answer({ object: "error", code: "object_not_found", message: `Could not find ${path}` }, 404);
};

// ---- three portals with no film behind them
const b = W.bucketOf();
const put = (k, v) => b.objects.set(k, { body: JSON.stringify(v), etag: 1 });
const card = (title, sections) => ({
  title, logline: "the portal's own line", documents: [{ name: "His link", url: "https://example.com", source: "notion" }],
  crew: [{ name: "Someone", role: "Gaffer" }], sections,
});
const here = { slug: "camera-tests", name: "Camera Tests", source: "here", by: "mcp" };
put(`p/${PLAIN}/portal.json`, { title: "zz plain", page: PLAIN });
put(`p/${PLAIN}/front.json`, card("zz plain", [here]));
put(`r/${PLAIN}/record.json`, { page: PLAIN, facts: { logline: { value: "the record's line", v: 2 } } });
put(`p/${OLD}/portal.json`, { title: "zz old", page: OLD });
put(`p/${OLD}/front.json`, card("zz old", [{ slug: "bible", name: "Visual Bible", from: BIBLE, source: "notion", notion: true, type: "page" }, here]));
put(`p/${OLD}/pages/bible.json`, [{ t: "p", x: "the old bible" }]);
put(`r/${OLD}/record.json`, { page: OLD, facts: {} });
put(`p/${MINTED}/portal.json`, { title: "zz minted", page: MINTED });
put(`p/${MINTED}/front.json`, card("zz minted", [{ slug: "notes", name: "Notes", from: NOTES, source: "notion", notion: true, type: "page" }]));
put(`r/${MINTED}/record.json`, { page: MINTED, notion_page: PAGE_B, facts: {} });
put("s/ids.json", { notion: { [PAGE_B]: MINTED }, alias: {} });
const env = { BUCKET: b, NOTION_TOKEN: "checking-notion-token" };

const t = await RH.refreshTick(env, null, Date.now(), { dry: true, detail: true, all: true, force: true });
const wrote = (key) => { const w = (t.would || []).find((x) => x.key === key); return w && w.body ? JSON.parse(w.body) : null; };
const linesOf = (title) => { const at = t.lines.indexOf(`\n${title}`); const out = []; for (let i = at + 1; i < t.lines.length && !t.lines[i].startsWith("\n"); i += 1) out.push(t.lines[i]); return out; };
const before = (id) => JSON.parse(b.objects.get(`p/${id}/front.json`).body);
const same = (x, y) => JSON.stringify(x) === JSON.stringify(y);

console.log("only pages set up to follow Notion read it");
check("no line anywhere says Notion could not be read", !t.lines.some((l) => /could not read Notion|env is not defined|object_not_found/.test(l)), t.lines.join(" | "));
check("Notion is never asked for a project's row, a database or who it is", !asked.some((p) => /^(pages\/|data_sources\/|users\/me)/.test(p)), asked.join(", "));
check("Notion is asked only for the two following pages", same([...new Set(asked)].sort(), [`blocks/${BIBLE}/children`, `blocks/${NOTES}/children`].sort()), asked.join(", "));
{
  const c = wrote(`p/${PLAIN}/front.json`);
  check("a card with no following page: no Notion line", !linesOf("zz plain").some((l) => /Notion/.test(l)), linesOf("zz plain").join(" | "));
  check("…its documents, people and pages stay as they were", c && same(c.documents, before(PLAIN).documents) && same(c.crew, before(PLAIN).crew) && same(c.sections, before(PLAIN).sections), JSON.stringify(c));
  check("…and the record's logline is still laid on it", c && c.logline === "the record's line", c && c.logline);
}
{
  const c = wrote(`p/${OLD}/front.json`);
  const page = wrote(`p/${OLD}/pages/bible.json`);
  check("a following page is drawn again from its own Notion page", page && page.length === 2 && JSON.stringify(page).includes("Notion's bible"), JSON.stringify(page));
  check("…and nothing else on its card moves (logline, documents, people)", c && c.logline === "the portal's own line"
    && same(c.documents, before(OLD).documents) && same(c.crew, before(OLD).crew), JSON.stringify(c));
  check("…its written-here page is left alone", c && same(c.sections.find((s) => s.slug === "camera-tests"), here) && !wrote(`p/${OLD}/pages/camera-tests.json`));
}
{
  const c = wrote(`p/${MINTED}/front.json`);
  check("a one-ID portal is never looked up by its minted ID", !asked.includes(`pages/${MINTED}`), asked.join(", "));
  check("…its following page is drawn from its own Notion page", JSON.stringify(wrote(`p/${MINTED}/pages/notes.json`) || "").includes("Notion's notes"));
  check("…and its logline stays the portal's", c && c.logline === "the portal's own line", c && c.logline);
}
check("followingPages: only source notion with a Notion page id", typeof RH.followingPages === "function"
  && RH.followingPages({ sections: [{ source: "notion", from: BIBLE }, { source: "notion" }, { from: BIBLE }, { source: "notion-once", from: BIBLE }, here] }).length === 1);
check("a dry look wrote nothing", !b.writes.some((k) => /front\.json$|pages\//.test(k)), b.writes.join(", "));

console.log("the Refresh from Notion button follows the same rule");
{
  const N = await import("./src/notion.js");
  const frontOf = (id) => JSON.parse(b.objects.get(`p/${id}/front.json`).body);
  const was = { plain: frontOf(PLAIN), old: frontOf(OLD) };
  asked.length = 0;
  const none = await N.refreshFilm(env, PLAIN);
  check("a portal with no following page: Notion is never asked", asked.length === 0 && none.ok, asked.join(", "));
  check("…and its card is not touched", same(frontOf(PLAIN), was.plain));
  asked.length = 0;
  const one = await N.refreshFilm(env, OLD);
  check("a following page: only its own Notion page is read, no row, no database", same([...new Set(asked)], [`blocks/${BIBLE}/children`]), asked.join(", "));
  check("…it is drawn again from Notion", one.ok && JSON.stringify(JSON.parse(b.objects.get(`p/${OLD}/pages/bible.json`).body)).includes("Notion's bible"), one.lines.join(" | "));
  const now = frontOf(OLD);
  check("…and the logline, documents and people stay the portal's", now.logline === "the portal's own line" && same(now.documents, was.old.documents) && same(now.crew, was.old.crew), JSON.stringify(now));
  asked.length = 0;
  await N.refreshFilm(env, MINTED);
  check("a one-ID portal is not looked up by its minted ID", !asked.includes(`pages/${MINTED}`) && !asked.some((p) => /^(data_sources\/|users\/me)/.test(p)), asked.join(", "));
}

globalThis.fetch = realFetch;
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
