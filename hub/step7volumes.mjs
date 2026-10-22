// His hard rule (2026-10-15): media drives are create-only. The server has no
// media drive; this fails if any server file (not only step 6's) names /Volumes
// in code, so no server path can ever reach one.
import { readdirSync, readFileSync } from "node:fs";
let pass = 0, fail = 0;
for (const f of readdirSync(new URL("./src/", import.meta.url)).filter((x) => x.endsWith(".js"))) {
  const hit = readFileSync(new URL(`./src/${f}`, import.meta.url), "utf8").split("\n")
    .filter((l) => l.includes("/Volumes") && !l.trim().startsWith("*") && !l.trim().startsWith("//") && !l.trim().startsWith("/*"));
  if (hit.length) { fail++; console.log(`  ${f} names /Volumes: ${hit[0].trim()}  FAIL`); } else pass++;
}
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
