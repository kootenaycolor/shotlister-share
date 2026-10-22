#!/usr/bin/env node
/**
 * **Shoots stay** (2026-10-19, Daybreak: shoots shown in the console for a
 * moment, then gone). The project page and the projects list read the shoots
 * from Notion; when that read failed they showed none, and the console saved
 * that empty answer over its good copy. Now the record's copy of the shoots
 * stands in when Notion cannot be read, and a shoot the record has that Notion
 * did not list is shown beside Notion's. The sync side (a Notion outage never
 * takes a shoot off the record) is in notionsync.mjs, "shoots stay".
 *
 *     node --import hub/nodehook.mjs hub/shootkeep.mjs
 */
import { gather, shootsFromRecord, withRecordShoots } from "./src/projectpage.js";
import { buildList, withRecordCopy } from "./src/onelist.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).padEnd(70)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 500)}`}`);
};

const PAGE = "79199ff67a0385852f11c1eb47a4821f";
const S1 = "b26218e7c6f0814e015ebdeb5d1afbde", S2 = "1b0a0ec0d8b88c4155b86614ce97e448", S3 = "7e3a9c1152d84b0f9a61c2d4e8b0f3a6";
const dashed = (b) => `${b.slice(0, 8)}-${b.slice(8, 12)}-${b.slice(12, 16)}-${b.slice(16, 20)}-${b.slice(20)}`;
const copyRow = (id, title, start, end = "", status = "") => ({ id, title, label: title.split(" — ")[1] || title, name: "",
  n: Number((/Shoot (\d+)/.exec(title) || [])[1]) || null, start, end, status, section: "", changes: "", spec: [], docs: [] });
const COPY = [copyRow(S1, "ZZ Keep — Shoot 1", "2025-10-29", "2025-11-14", "Wrapped"), copyRow(S2, "ZZ Keep — Shoot 2 · Pickup", "2026-02-21", "2026-02-22")];
const CREW = [{ person: "aaaa0000000000000000000000000001", name: "Max", shoots: [S1], all_shoots: false },
  { person: "aaaa0000000000000000000000000002", name: "Clara", shoots: [], all_shoots: true }];
const notionShoot = (id, title, start) => ({ object: "page", id: dashed(id), url: `https://www.notion.so/${id}`, properties: {
  Shoot: { type: "title", title: [{ plain_text: title }] }, Dates: { type: "date", date: { start } },
  Project: { type: "relation", relation: [{ id: dashed(PAGE) }] }, Crew: { type: "relation", relation: [], has_more: false },
  "Camera Spec Sheet": { type: "relation", relation: [], has_more: false }, Status: { type: "select", select: null } } });

/** A stand-in Notion for the page: `shoots` its Shoots rows, `down` a 401 on that list. */
function notion({ shoots = [], down = false } = {}) {
  return {
    async post(path) {
      if (path.includes("feedface-0000-4000-8000-000000000002")) {
        if (down) throw new Error("Notion answered 401: API token is invalid.");
        return { results: shoots, has_more: false };
      }
      return { results: [], has_more: false };
    },
    async get() { return { results: [], has_more: false }; },
  };
}
const project = { page_id: PAGE, name: "ZZ Keep", status: "Active", type: "Narrative", dates: "2025-10-29", dates_end: "2025-11-14" };
const opts = (extra = {}) => ({ media_on: false, portal_on: false, now: "2026-10-19", ...extra });
const ids = (rows) => rows.filter((r) => !r.from_project).map((r) => String(r.id).replace(/-/g, ""));

console.log("the page: Notion down");
{
  const before = await gather(notion({ down: true }), project, CREW, opts());
  check("without the record's copy (as before): no shoots, only the project's own", ids(before.shoots).length === 0, JSON.stringify(ids(before.shoots)));
  const got = await gather(notion({ down: true }), project, CREW, opts({ recordShoots: COPY }));
  check("the record's two shoots shown", ids(got.shoots).join() === [S1, S2].join(), JSON.stringify(ids(got.shoots)));
  check("Notion's trouble still said", got.trouble.some((t) => t.startsWith("shoots:")), JSON.stringify(got.trouble));
  check("marked notion_waits, so the console keeps its last whole page", got.notion_waits === true, "");
  const one = got.shoots.find((r) => String(r.id).replace(/-/g, "") === S1);
  check("a shoot keeps its dates and status", one && one.start === "2025-10-29" && one.status === "Wrapped", JSON.stringify(one));
}

console.log("the page: Notion up");
{
  const live = [notionShoot(S1, "ZZ Keep — Shoot 1", "2025-10-30"), notionShoot(S3, "ZZ Keep — Shoot 3 · May", "2026-05-31")];
  const got = await gather(notion({ shoots: live }), project, CREW, opts({ recordShoots: COPY }));
  check("Notion's shoots and the record's own: three, in date order", ids(got.shoots).join() === [S1, S2, S3].join(), JSON.stringify(ids(got.shoots)));
  const one = got.shoots.find((r) => String(r.id).replace(/-/g, "") === S1);
  check("where both have a shoot, Notion's words", one && one.start === "2025-10-30", JSON.stringify(one));
  const plain = await gather(notion({ shoots: live }), project, CREW, opts());
  check("no record copy: Notion's alone, as before", ids(plain.shoots).join() === [S1, S3].join(), JSON.stringify(ids(plain.shoots)));
  check("read whole: not marked", !plain.notion_waits && !got.notion_waits, "");
}

console.log("the record's copy as rows");
{
  const rows = shootsFromRecord(COPY, CREW, PAGE);
  check("crew from the record: Max on Shoot 1, Clara on every shoot", rows[0].crew.join() === `${CREW[0].person},${CREW[1].person}`
    && rows[1].crew.join() === CREW[1].person, JSON.stringify(rows.map((r) => r.crew)));
  check("nothing that is not a shoot", shootsFromRecord([null, 3, {}, ...COPY], [], PAGE).length === 2, "");
  check("no duplicates when ids are dashed on one side", withRecordShoots([{ id: dashed(S1), start: "2025-10-29" }], rows).length === 2, "");
}

console.log("the list");
{
  const page = { object: "page", id: dashed(PAGE), properties: { Project: { type: "title", title: [{ plain_text: "ZZ Keep" }] },
    Status: { type: "select", select: { name: "Active" } }, Type: { type: "select", select: { name: "Narrative" } },
    "Shoot Dates": { type: "date", date: { start: "2025-10-29", end: "2025-11-14" } } } };
  const records = { [PAGE]: { page: PAGE, facts: { shoots: { value: COPY, v: 1 } } } };
  const down = buildList({ pages: [page], crew: [], shoots: [], records, saved: {}, now: "2026-10-19" });
  const row = down.projects[0];
  check("Shoots list unread: the card keeps the record's two shoots", row.shoots.length === 2 && ids(row.shoots).join() === [S1, S2].join(), JSON.stringify(row.shoots));
  const up = buildList({ pages: [page], crew: [], shoots: [notionShoot(S3, "ZZ Keep — Shoot 3 · May", "2026-05-31")], records, saved: {}, now: "2026-10-19" });
  check("Notion's new one added to the record's", up.projects[0].shoots.length === 3, JSON.stringify(up.projects[0].shoots.map((s) => s.id)));
  check("withRecordCopy leaves Notion's alone when it has them all", withRecordCopy([{ id: S1 }, { id: S2 }], COPY, PAGE).length === 2, "");
}

console.log(fail ? `\n${fail} FAILED, ${pass} passed` : `\nall ${pass} passed, 0 failed`);
process.exit(fail ? 1 : 0);
