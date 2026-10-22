#!/usr/bin/env node
/**
 * **A spec sheet's lens sets as the picks a shot chooses from** (Ref 1627):
 * `lensPicks` in `src/lenses.js`. Primes break into their focal lengths, a
 * zoom stays one lens with its name, a set with no focal lengths stays whole.
 *
 *     node hub/picks.mjs
 */
import { lensPicks } from "./src/lenses.js";

const cases = [
  ["Cooke S4 primes 18/25/32/50", ["18mm", "25mm", "32mm", "50mm"]],
  ["A Cam: Cooke S4/i — 18, 25, 32, 50, 75, 100mm — T2 — rehoused, Keslow", ["18mm", "25mm", "32mm", "50mm", "75mm", "100mm"]],
  ["Angenieux 45-165mm t/2.3", ["Angenieux 45-165mm"]],
  ["Fujinon Premista 28–100mm T2.9", ["Fujinon Premista 28-100mm"]],
  ["Sony G Master 24-70", ["Sony G Master 24-70mm"]],
  ["Signature Primes", ["Signature Primes"]],
  ["Cooke S4/i", ["Cooke S4/i"]],
  ["Zeiss 20.7, 25mm", ["20.7mm", "25mm"]],
  ["Canon Super 16 11-165mm PL Mount Lens (MD)", ["Canon Super 16 11-165mm PL Mount Lens (MD)"]],
  ["Cooke S4 — 25, 32mm\nB Cam: Zeiss Supreme — T1.5 — 25, 35, 50", ["25mm", "32mm", "35mm", "50mm"]],
  ["", []],
];
let pass = 0, fail = 0;
for (const [text, want] of cases) {
  const got = lensPicks(text);
  const good = JSON.stringify(got) === JSON.stringify(want);
  if (good) pass += 1; else fail += 1;
  console.log(`  ${JSON.stringify(text).slice(0, 64).padEnd(66)} ${good ? "PASS" : `FAIL — ${JSON.stringify(got)}`}`);
}
console.log(`passed ${pass}, failed ${fail}`);
process.exit(fail ? 1 : 0);
