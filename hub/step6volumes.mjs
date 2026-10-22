// His hard rule (2026-10-15): nothing moves, renames, trashes or deletes on a media drive.
// The server has no media drive; this fails if any step 6 server file even names /Volumes.
import { readdirSync, readFileSync } from "node:fs";
let pass = 0, fail = 0;
for (const f of readdirSync(new URL("./src/", import.meta.url)).filter((x) => /^step6.*\.js$/.test(x))) {
  const hit = readFileSync(new URL(`./src/${f}`, import.meta.url), "utf8").split("\n").filter((l) => l.includes("/Volumes") && !l.trim().startsWith("*") && !l.trim().startsWith("//"));
  if (hit.length) { fail++; console.log(`  ${f} names /Volumes: ${hit[0].trim()}  FAIL`); } else pass++;
}
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
