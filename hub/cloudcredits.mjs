#!/usr/bin/env node
/**
 * **A credit added with a new person or company, written as the Mac writes
 * it** — `src/cloudrecord.js`'s `changeCredits`, the one `crew_new` /
 * `company_new` call when they carry a credit, against the Mac's own
 * `record.change_credits` (run here in Python with the record's two doors
 * caught), case by case:
 * - a list the phone wrote with its keys the other way round
 *   ({"people", "role"}) that the edit leaves as it was is not written;
 * - names are cleaned and compared by the Mac's rules (Python's spaces,
 *   `casefold`, 120 letters counted as Python counts them);
 * - what is written, and the answer, are the Mac's.
 *
 *     node hub/cloudcredits.mjs
 */
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { pyEqual } from "./src/notionlink.js";

// The worker's own code, bundled as the worker is (its record doors read the
// relay's layout and a wasm file that plain node will not load).
// CREDITS_SOURCE: another cloudrecord.js beside it to check instead.
const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = mkdtempSync(join(tmpdir(), "cloudcredits-"));
const built = spawnSync(join(HERE, "node_modules/.bin/esbuild"), [process.env.CREDITS_SOURCE || join(HERE, "src/cloudrecord.js"),
  "--bundle", "--format=esm", "--platform=node", "--external:*.wasm", `--outfile=${join(OUT, "credits.mjs")}`, "--log-level=error"], { encoding: "utf8" });
if (built.status !== 0) {
  console.error(built.stderr);
  process.exit(1);
}
writeFileSync(join(OUT, "credits.mjs"), readFileSync(join(OUT, "credits.mjs"), "utf8")
  .replace(/^import (\w+) from "\.\/mcp\.wasm";$/gm, "const $1 = null;"));
const { changeCredits } = await import(join(OUT, "credits.mjs"));
rmSync(OUT, { recursive: true, force: true });
const CONSOLE = process.env.CONSOLE_DIR || join(homedir(), "Developer", "projects-console");
const PAGE = "11111111222233334444555555555555";
let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.slice(0, 74).padEnd(76)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 600)}`}`);
};
const fact = (value, v = 1, at = "2026-10-12T10:00:00Z") => ({ value, v, at, by: "phone" });

const FILM_FACTS = {"credits": {"value": [{"people": ["Ollie Hart Brennan"], "role": "Director"}, {"people": ["Owen Fairweather"], "role": "Producer"}, {"role": "Executive Producer", "people": ["Owen Fairweather"]}, {"people": ["Marta Delgado"], "role": "Line Producer"}, {"role": "Production Company", "people": ["Hum Studio"]}], "v": 8, "at": "2026-10-06T13:53:26.046Z", "by": "phone"}, "director": {"value": "Ollie Hart Brennan", "v": 1, "at": "2026-10-05T15:37:58.617Z", "by": "import"}, "producer": {"value": "Owen Fairweather", "v": 5, "at": "2026-10-06T13:53:04.388Z", "by": "phone"}, "executive_producer": {"value": "Owen Fairweather", "v": 1, "at": "2026-10-06T00:52:46.786Z", "by": "Mac-Studio.local"}, "line_producer": {"value": "Marta Delgado", "v": 1, "at": "2026-10-06T00:52:40.555Z", "by": "Mac-Studio.local"}, "production_company": {"value": "Hum Studio", "v": 1, "at": "2026-10-06T13:53:26.046Z", "by": "phone"}};

const CASES = [
  { what: "an unchanged list, keys the phone's way round, is not written",
    facts: { credits: fact([{ people: ["Ivy Sterling", "Robin Vale Arden"], role: "Director" }], 3), director: fact("Ivy Sterling & Robin Vale Arden", 2) },
    edit: { set: "Director", people: ["Ivy Sterling", "Robin Vale Arden"] } },
  { what: "moving the only person, keys the phone's way round, is not written",
    facts: { credits: fact([{ people: ["Marta Delgado"], role: "Producer" }], 4), producer: fact("Marta Delgado") },
    edit: { move: "Producer", person: "Marta Delgado", by: 1 } },
  { what: "a credit that puts back the list as stored rewrites only its line",
    // An older device typed the Director line alone after the list was
    // written; adding the second director back leaves the list as the phone
    // stored it ({"people", "role"}), so only the line moves.
    facts: { credits: fact([{ people: ["Dana Field", "Rhea Moss"], role: "Director" }], 5), director: fact("Dana Field", 3, "2026-10-12T11:00:00Z") },
    edit: { add: "Director", person: "Rhea Moss" } },
  // Let's Bake's credits as the record held them on 2026-10-13 (GET
  // /console/record/e6ee5875f5d789412e0b12538f71cfb5): the phone's
  // {"people", "role"} and the Mac's {"role", "people"} in the one list.
  { what: "Let's Bake as it is: the Director set to who it already is",
    facts: FILM_FACTS, edit: { set: "Director", people: ["Ollie Hart Brennan"] } },
  { what: "Let's Bake as it is: a new person added as Producer",
    facts: FILM_FACTS, edit: { add: "Producer", person: "Rhea Moss" } },
  { what: "Let's Bake as it is: the line producer already credited, refused",
    facts: FILM_FACTS, edit: { add: "Line Producer", person: "marta  delgado" } },
  { what: "a name the same by casefold (Straße / STRASSE) is already credited",
    facts: { credits: fact([{ people: ["Anna Straße"], role: "Producer" }]), producer: fact("Anna Straße") },
    edit: { add: "Producer", person: "ANNA STRASSE" } },
  { what: "a name with Python's spaces (\\x1f, \\u2003) cleaned the Mac's way",
    facts: { credits: fact([{ people: ["Dana Field"], role: "Director" }]), director: fact("Dana Field") },
    edit: { add: "Writer", person: "Kai\x1fRiver  Moss" } },
  { what: "a byte-order mark is a letter to Python, not a space",
    facts: {},
    edit: { add: "Director", person: "﻿Lee Park" } },
  { what: "a long name of emoji cut at 120 letters as Python counts them",
    facts: {},
    edit: { add: "Producer", person: "🎬".repeat(130) } },
  { what: "taken off by a different case: the Mac's casefold match",
    facts: { credits: fact([{ people: ["Anna Straße", "Rhea Moss"], role: "Producer" }]), producer: fact("Anna Straße & Rhea Moss") },
    edit: { remove: "Producer", person: "anna strasse" } },
  { what: "a first credit on a record with none",
    facts: { title: fact("Cloud Film") },
    edit: { add: "Production Company", person: "Night Owl Films" } },
];

// ── the Mac: record.change_credits with facts() and set_facts() caught ───────
const PY = `
import copy, json, sys
sys.path.insert(0, sys.argv[1])
import record
out = []
for case in json.load(sys.stdin):
    store = copy.deepcopy(case["facts"])
    writes = []
    def facts(page_id):
        return copy.deepcopy(store)
    def set_facts(page_id, changes, by="", queue=True):
        writes.append({f: {"value": v, "base": b} for f, (v, b) in changes.items()})
        for f, (v, b) in changes.items():
            store[f] = {"value": v, "v": (store.get(f) or {}).get("v", 0) + 1}
        return {"facts": copy.deepcopy(store)}
    record.facts, record.set_facts = facts, set_facts
    got = record.change_credits("${PAGE}", case["edit"])
    got.pop("facts", None)
    out.append({"result": got, "writes": writes})
print(json.dumps(out))
`;
const ran = spawnSync("python3", ["-I", "-c", PY, CONSOLE], { input: JSON.stringify(CASES), encoding: "utf8" });
if (ran.status !== 0) {
  console.error(ran.stderr);
  process.exit(1);
}
const MAC = JSON.parse(ran.stdout);

// ── the hub: the same facts on a record in a bucket that remembers ───────────
function bucket(facts) {
  const files = new Map([[`r/${PAGE}/record.json`, JSON.stringify({ page: PAGE, facts })]]);
  let etag = 1;
  const writes = [];
  return {
    writes,
    async get(key) {
      if (!files.has(key)) return null;
      const body = files.get(key);
      return { etag: String(etag), json: async () => JSON.parse(body), text: async () => body };
    },
    async head(key) { return files.has(key) ? { etag: String(etag) } : null; },
    async put(key, body, opts = {}) {
      if (opts.onlyIf && opts.onlyIf.etagMatches && opts.onlyIf.etagMatches !== String(etag)) return null;
      if (key.endsWith("/record.json")) {
        const was = JSON.parse(files.get(key)).facts || {};
        const now = JSON.parse(body).facts || {};
        const one = {};
        for (const [f, x] of Object.entries(now)) if (!was[f] || was[f].v !== x.v) one[f] = { value: x.value, base: was[f] ? was[f].v : 0 };
        writes.push(one);
        etag += 1;
      }
      files.set(key, body);
      return { etag: String(etag) };
    },
    async list() { return { objects: [], truncated: false }; },
  };
}

console.log("\nA credit with a new person or company, the Mac's way");
for (const [i, c] of CASES.entries()) {
  const B = bucket(JSON.parse(JSON.stringify(c.facts)));
  let got;
  try {
    got = await changeCredits({ BUCKET: B }, PAGE, c.edit);
  } catch (e) {
    got = { ok: false, why: `threw: ${e.message}` };
  }
  const mine = { ...got };
  delete mine.facts;
  const mac = MAC[i];
  check(c.what, pyEqual(JSON.parse(JSON.stringify(B.writes)), mac.writes) && pyEqual(JSON.parse(JSON.stringify(mine)), mac.result),
    `hub wrote ${JSON.stringify(B.writes)} and said ${JSON.stringify(mine)}; the Mac wrote ${JSON.stringify(mac.writes)} and said ${JSON.stringify(mac.result)}`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
