#!/usr/bin/env node
/**
 * **Studio's Export on the server** (src/exportplan.js, the plain half of
 * src/exporting.js): the sheet cut is the Mac's (ZED's real rows, as Studio
 * measured and cut them on 2026-10-17), names come out as Studio names
 * them, a name already in the folder gets _v2, and presets read the way the
 * Export window reads them. `node hub/exporting.mjs`
 */
import { pageBreaks, parseBlocks, spansOf, autoName, plain, typedName, unusedStem, askFrom, stampOf, todayOf, paperOf, MARGIN } from "./src/exportplan.js";

let pass = 0, fail = 0;
const check = (what, good, why) => {
  if (good) { pass += 1; console.log(`  ${what.padEnd(70)} PASS`); }
  else { fail += 1; console.log(`  ${what.padEnd(70)} FAIL — ${JSON.stringify(why)}`); }
};

// Studio's own measure of ZED's table and where it cut it (`cuts table:` under a checking run).
const MAC_BLOCKS = "122-141h 180-275 275-369 397-416h 456-550 550-645 672-691h 731-825 825-920 948-966h 1006-1079 1079-1152 1152-1225 1225-1319 1319-1414 1414-1487 1487-1545 1545-1618 1646-1664h 1704-1798 1798-1856 1856-1883 1883-1978 1978-2021 2021-2078 2106-2125h 2164-2252 2252-2295 2295-2352 2352-2441 2441-2514 2541-2560h 2600-2672 2672-2715 2715-2803 2803-2898 2898-2993 3020-3039h 3079-3106 3106-3148 3148-3243 3243-3316 3344-3362h 3402-3459 3459-3554 3554-3649 3649-3722 3722-3780 3807-3826h 3866-3908 3908-3950 3950-4008 4008-4103 4103-4160 4160-4255 4255-4350 4350-4392 4420-4439h 4479-4573 4573-4668 4668-4695 4695-4790 4817-4836h 4876-4933 4933-4991 4991-5064 5064-5122 5122-5210 5210-5268 5295-5314h 5354-5396 5396-5453 5453-5526 5526-5569 5569-5626 5654-5673h 5713-5770 5770-5812 5812-5870 5870-5928 5928-5985 6013-6032h 6072-6129 6129-6171 6171-6229 6257-6275h 6315-6403 6403-6461 6461-6518 6518-6561 6589-6607h 6647-6720 6720-6762 6762-6804 6804-6877 6877-6935";
const MAC_BREAKS = "0 397 948 1487 2021 2541 3020 3554 4008 4420 4933 5453 6013 6589";
const blocks = parseBlocks(MAC_BLOCKS.split(" ").map((b) => {
  const [a, z] = b.replace("h", "").split("-").map(Number);
  return [a, z, b.endsWith("h") ? 1 : 0, 0];
}));
const got = pageBreaks(blocks, 548).join(" ");
check("ZED's rows cut where Studio cut them (14 sheets)", got === MAC_BREAKS, { got, want: MAC_BREAKS });
check("a heading never ends a sheet: it goes over with its first row",
  pageBreaks(parseBlocks([[0, 500, 0, 0], [500, 520, 1, 0], [530, 600, 0, 0]]), 548).join() === "0,500", pageBreaks(parseBlocks([[0, 500, 0, 0], [500, 520, 1, 0], [530, 600, 0, 0]]), 548));
check("a fresh-page block opens a sheet", pageBreaks(parseBlocks([[0, 50, 0, 0], [60, 90, 0, 1]]), 548).join() === "0,60");
check("a row taller than a sheet steps through it", pageBreaks(parseBlocks([[0, 1200, 0, 0]]), 548).join() === "0,548,1096");
check("…and the last slice is only as tall as what is left", JSON.stringify(spansOf([0, 548, 1096], 1200, 548).pop()) === JSON.stringify({ y: 1096, h: 104 }));
check("Letter either way round, the views' margins", paperOf("portrait").join() === "612,792" && paperOf("landscape").join() === "792,612" && MARGIN.table === 32 && MARGIN.document === 72);

check("the name is Studio's: project, pages, order, date",
  autoName({ project: plain("Let's Bake"), document: "shot-list", order: "schedule-order", date: "20261017" }) === "lets-bake-shot-list-schedule-order-20261017");
check("…with scenes when it is a pick", autoName({ project: "zed", document: "storyboard", scope: "sc-4", order: "script-order", date: "20261017" }) === "zed-storyboard-sc-4-script-order-20261017");
check("a typed name is kept exactly, less slashes and its extension", typedName("ZED / Day 2.pdf", "pdf") === "ZED - Day 2");
const taken = new Set(["zed-shot-list-script-order-20261017.pdf", "zed-shot-list-script-order-20261017_v2.pdf", "other.xlsx"]);
check("a name already there gets the next _vN", unusedStem("zed-shot-list-script-order-20261017", taken, ["pdf"]) === "zed-shot-list-script-order-20261017_v3");
check("…a free one is left alone", unusedStem("zed-storyboard-script-order-20261017", taken, ["pdf"]) === "zed-storyboard-script-order-20261017");
check("…and a spreadsheet beside it counts", unusedStem("other", taken, ["pdf", "xlsx"]) === "other_v2");

const presets = [
  { id: "p-ac", name: "AC Sheet: Day by Day", arrange: "schedule", output: "perday", pages: ["table"], auto: true },
  { id: "p-client", name: "Client: Script Order", arrange: "script", pages: ["table", "storyboard", "document"], auto: false,
    looks: { table: { orientation: "portrait", scale: 0.9, frames: "large" } }, columnsExcept: ["notes"] },
  { id: "p-tomorrow", name: "Tomorrow", arrange: "table", filter: "table", filterWords: ["INT"], days: { kind: "next" }, pages: ["table", "diagram"], fileKind: 1 },
];
let a = askFrom({ preset: "ac sheet: day by day" }, presets);
check("a preset by its name, any case: schedule, one file a day", a.ask && a.ask.arrange === "schedule" && a.ask.output === "perday", a);
a = askFrom({ preset: "Client", pages: "table, storyboard" }, presets);
check("…or part of its name; what the call says wins", a.ask.pages.join() === "table,storyboard" && a.ask.auto === false && a.ask.looks.table.scale === 0.9 && a.ask.columns_except[0] === "notes", a);
check("pages go in the Export window's order, however they were named", askFrom({ pages: ["document", "storyboard", "table"] }, null).ask.pages.join() === "table,storyboard,document");
a = askFrom({ preset: "Tomorrow" }, presets);
check("a preset reading the Mac's Table says what the server does instead",
  a.ask.arrange === "script" && a.ask.days.kind === "next" && a.ask.pages.join() === "table" && a.notes.length === 4, a.notes);
check("no such preset names the ones there are", /AC Sheet/.test(askFrom({ preset: "Weekly" }, presets).why || ""));
a = askFrom({ order: "shooting order", days: "3-5", size: 110 }, null);
check("no preset: the shot list on Auto, the order and days as asked", a.ask.pages.join() === "table" && a.ask.auto && a.ask.arrange === "schedule" && a.ask.days === "3-5" && a.ask.size === 1.1, a);
check("pages that are not pages are refused", Boolean(askFrom({ pages: ["diagram"] }, null).why));

check("the footer's time reads as Studio's", /^[A-Z][a-z]{2} \d{1,2}, \d{4} at \d{1,2}:\d{2} (AM|PM)$/.test(stampOf(new Date("2026-10-17T22:25:00Z"))), stampOf(new Date("2026-10-17T22:25:00Z")));
check("…on his clock", stampOf(new Date("2026-10-17T22:25:00Z")) === "Oct 17, 2026 at 3:25 PM" && todayOf(new Date("2026-10-18T05:00:00Z")).compact === "20261017");

import { readFileSync } from "node:fs";
const source = readFileSync(new URL("./src/exporting.js", import.meta.url), "utf8");
check("exports go in shot-list/exports, the name his other exports use", /export const EXPORTS_FOLDER = "exports";/.test(source));
check("the connector tool says so", /\(1-creative\/shot-list\/exports\/,/.test(source));
check("…and no longer files loose in shot-list", !/\(1-creative\/shot-list\/\), beside/.test(source));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
