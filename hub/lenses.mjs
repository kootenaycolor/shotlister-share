#!/usr/bin/env node
/**
 * The portal reads a spec sheet's lens sets the way Projects Console does
 * (`src/lenses.js` and the console's `lenses.py`). `lens-cases.json` is the
 * console's file, copied: when one side learns a new line, both do.
 *
 *     node hub/lenses.mjs
 */
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseLine, lensSets, oneLine } from "./src/lenses.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const cases = JSON.parse(readFileSync(join(HERE, "lens-cases.json"), "utf8"));
let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.slice(0, 64).padEnd(66)} ${good ? "PASS" : `FAIL — ${why}`}`);
};
for (const one of cases) {
  const got = parseLine(one.line);
  const want = one.set;
  const same = ["label", "series", "stop", "notes"].every((k) => got[k] === want[k]) && JSON.stringify(got.focals) === JSON.stringify(want.focals);
  check(one.line, same, JSON.stringify(got));
}
check("blank lines are not sets", lensSets("A\n\n  \nB").length === 2);
check("one line joins the sets with ·", oneLine("A Cam: X\nB Cam: Y") === "A Cam: X · B Cam: Y");
console.log(`passed ${pass}, failed ${fail}`);
process.exit(fail ? 1 : 0);
