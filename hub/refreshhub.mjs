#!/usr/bin/env node
/**
 * **The portal's refresh, rule for rule against the Mac's** (2026-10-11,
 * Projects Console without the Mac, stage 3 step 2) — the parts of
 * `src/refreshhub.js` that need no Notion and no bucket, checked in plain node.
 *
 * Always (made-up cases, the answers asked of Python itself):
 * - a cover's fingerprint is `json.dumps(spec, sort_keys=True)` hashed —
 *   byte for byte, accents, quotes and emoji included;
 * - the shoot dates a cover says (`shoot_dates_text`), Python's quirks too;
 * - the film's mark: which icon address, which outline and colour (`mark_of`);
 * - the film half from a made-up view (`drawn_with`, `_facts`).
 *
 * With real cases (`python3 hub/refreshhub-real.py` first; read from
 * `$REFRESHHUB_CASES`, default `$TMPDIR/refreshhub-real`, never the repo):
 * - every film on this Mac: the engine's own `view()` here, replayed from
 *   the film's logs, gives the same facts as `cargo … dump_view` gave
 *   `refresh.py` — pictures, days, director, producer, ratio, page, counts;
 * - every card the Mac would write: the same covers wanted, the same
 *   fingerprints.
 *
 *     node hub/refreshhub.mjs
 */
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { factsFromView, drawnWith, coversWanted, fingerprint, pyJson, shootDatesText, pageFor, pictureCount, ICON } from "./src/refreshrules.js";
import { notionIconAddress, markFromSvg } from "./src/notionmark.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const CASES = process.env.REFRESHHUB_CASES || join(tmpdir(), "refreshhub-real");
let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${what.padEnd(78)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 700)}`}`);
};
const python = (code, input) => {
  const got = spawnSync("python3", ["-c", code], { input: JSON.stringify(input), encoding: "utf8" });
  if (got.status !== 0) throw new Error(got.stderr);
  return JSON.parse(got.stdout);
};

// ---- fingerprints: json.dumps(sort_keys=True), byte for byte
{
  const specs = [
    { title: "Let's Bake", path: "M1 2L3 4z", colour: "#D9730D", status: "Active", shoot: "2 – 4 November", page: "Shot List" },
    { title: "Café “Noir” \\ <b>", logline: 'A "quoted" line\nwith a break\tand tab', status: "", shoot: "", path: "", colour: "" },
    { title: "Emoji 🎬 and ñ", icon: true, path: "", colour: "#FFFFFF", status: "Post", shoot: "" },
    { title: "\u0000\u001f\u007f\u0080 ", page: "Visual Bible", n: 3, z: false, list: [1, "a"] },
  ];
  const py = python("import json,sys,hashlib\nprint(json.dumps([[json.dumps(s, sort_keys=True), hashlib.sha256(json.dumps(s, sort_keys=True).encode()).hexdigest()[:16]] for s in json.load(sys.stdin)]))", specs);
  for (let i = 0; i < specs.length; i += 1) {
    check(`json.dumps, case ${i + 1}`, pyJson(specs[i]) === py[i][0], `${pyJson(specs[i])} vs ${py[i]?.[0]}`);
  }
}
{
  const specs = [
    { title: "Let's Bake", path: "", colour: "", status: "Active", shoot: "", logline: "Café “Noir” 🎬" },
    { title: "Oddity", icon: true, path: "", colour: "", status: "", shoot: "" },
  ];
  const py = spawnSync("python3", ["-c", "import json,sys,hashlib\nprint(json.dumps([hashlib.sha256(json.dumps(s, sort_keys=True).encode()).hexdigest()[:16] for s in json.load(sys.stdin)]))"],
    { input: JSON.stringify(specs), encoding: "utf8" });
  const want = JSON.parse(py.stdout);
  for (let i = 0; i < specs.length; i += 1) check(`fingerprint, case ${i + 1}`, (await fingerprint(specs[i])) === want[i], `${await fingerprint(specs[i])} vs ${want[i]}`);
}

// ---- shoot dates, as the cover says them
{
  const shoots = [null, {}, { start: "" }, { start: "2026-11-02" }, { start: "2026-11-02", end: "2026-11-02" },
    { start: "2026-11-02", end: "2026-11-04" }, { start: "2026-10-30", end: "2026-11-02" }, { start: "2025-12-30", end: "2026-01-02" },
    { start: "2026-00-05" }, { start: "2026-1-5", end: "2026-01-07" }];
  const py = spawnSync("python3", ["-c", `import json,sys
sys.path.insert(0, ${JSON.stringify(HERE)})
import importlib.util
spec = importlib.util.spec_from_file_location("refresh", ${JSON.stringify(join(HERE, "refresh.py"))}); R = importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
out = []
for s in json.load(sys.stdin):
    try: out.append(R.shoot_dates_text(s))
    except Exception as e: out.append({"error": type(e).__name__})
print(json.dumps(out))`], { input: JSON.stringify(shoots), encoding: "utf8" });
  const want = JSON.parse(py.stdout);
  shoots.forEach((s, i) => {
    let got;
    try { got = shootDatesText(s); } catch { got = { error: true }; }
    const same = typeof want[i] === "object" ? typeof got === "object" : got === want[i];
    check(`shoot dates ${JSON.stringify(s)}`, same, `${JSON.stringify(got)} vs ${JSON.stringify(want[i])}`);
  });
  for (const bad of [{ start: "2026-13-01" }, { start: "Nov 2" }]) {
    let threw = false;
    try { shootDatesText(bad); } catch { threw = true; }
    check(`shoot dates ${JSON.stringify(bad)} is an error, as in Python`, threw);
  }
}

// ---- the mark: which address, which outline, which colour
{
  const icons = [
    { type: "icon", icon: { name: "heartbroken", color: "red" } },
    { type: "icon", icon: { name: "dining" } },
    { type: "icon", icon: { name: "Bad Name", color: "red" } },
    { type: "emoji", emoji: "🎬" },
    { type: "external", external: { url: "https://www.notion.so/icons/gift_red.svg" } },
    { type: "external", external: { url: "https://example.com/x.svg" } },
    { type: "file", file: { url: "https://s3.example/notion.so/icons/a.svg?x=1" } },
    null,
  ];
  const svgs = [
    '<svg viewBox="0 0 20 20"><path fill="#d44c47" d="M10 2 L18 18 Z"/><path d="M0 0"/></svg>',
    '<svg><path class="a" d="M1 1h2v2z" fill="#ABCDEF"></path></svg>',
    '<svg><circle r="3" fill="#123456"/></svg>',
    '<svg><path d="M1 1"/></svg>',
  ];
  const py = spawnSync("python3", ["-c", `import json,sys,re
d = json.load(sys.stdin)
def addr(icon):
    icon = icon or {}; address = ""
    if icon.get("type") == "external": address = (icon.get("external") or {}).get("url", "")
    elif icon.get("type") == "file": address = (icon.get("file") or {}).get("url", "")
    elif icon.get("type") == "icon":
        named = icon.get("icon") or {}; who = str(named.get("name") or ""); hue = str(named.get("color") or "gray")
        if re.fullmatch(r"[a-z0-9-]+", who) and re.fullmatch(r"[a-z_]+", hue): address = f"https://www.notion.so/icons/{who}_{hue}.svg"
    return address if "notion.so/icons/" in address else ""
def mark(drawing):
    outline = re.findall(r'<path[^>]*\\sd="([^"]+)"', drawing); colour = re.findall(r'fill="(#[0-9A-Fa-f]{6})"', drawing)
    return {} if not outline else {"path": outline[0], "colour": (colour[0] if colour else "").upper()}
print(json.dumps([[addr(i) for i in d[0]], [mark(s) for s in d[1]]]))`], { input: JSON.stringify([icons, svgs]), encoding: "utf8" });
  const [addrs, marks] = JSON.parse(py.stdout);
  icons.forEach((icon, i) => check(`icon address ${JSON.stringify(icon)}`, notionIconAddress(icon) === addrs[i], `${notionIconAddress(icon)} vs ${addrs[i]}`));
  svgs.forEach((svg, i) => check(`mark from svg ${i + 1}`, JSON.stringify(markFromSvg(svg)) === JSON.stringify(marks[i]), `${JSON.stringify(markFromSvg(svg))} vs ${JSON.stringify(marks[i])}`));
}

// ---- the film half, from a made-up view
{
  const names = new Set(["a".repeat(32) + ".jpg", "b".repeat(32) + ".png", "c".repeat(32) + ".heic", "d".repeat(32) + ".mp4", "notahash.jpg"]);
  const view = {
    project: { director: "D", producer: "", ratio: 2.39, consolePage: "1234" },
    scenes: [{ id: "s1" }, { id: "s2", archived: true }, { id: "s3" }],
    groups: [{ rows: [{ sceneId: "s1", frame: { hash: "a".repeat(64) } }, { sceneId: "s1", frame: { hash: "b".repeat(64) } }, { sceneId: "s3", frame: { hash: "d".repeat(64) } }, { sceneId: "s3" }] }],
    locations: [{ media: [{ hash: "b".repeat(64) }, { hash: "c".repeat(64) }] }, { media: [] }, { media: [{ hash: "a".repeat(64) }] }],
    boards: [{ media: [{ hash: "d".repeat(64) }] }],
    days: [{ label: "Day 1", date: "2026-01-02" }, { label: "Day 2", date: "" }],
  };
  const got = factsFromView(view, names, pictureCount(names));
  const want = { pictures: { scenes: ["a".repeat(32) + ".jpg"], locations: ["b".repeat(32) + ".png", "a".repeat(32) + ".jpg", "c".repeat(32) + ".heic"], boards: [] },
    days: [{ label: "Day 1", date: "2026-01-02" }], director: "D", producer: "", ratio: 2.39, console_page: "1234",
    counts: { scenes: 3, shots: 4, locations: 3, boards: 1, days: 2, pictures: 3 } };
  check("the film half from a made-up view", JSON.stringify(got) === JSON.stringify(want), JSON.stringify(got));
  const prop = (row, name) => ((row.properties || {})[name] || "");
  check("page by link first", JSON.stringify(pageFor({ console_page: "ab-cd" }, "X", [], prop)) === '{"page":"abcd","how":"link"}');
  check("page by title, case and spaces aside", JSON.stringify(pageFor({ console_page: "" }, " Oddity ", [{ id: "1-2", properties: { Project: "oddity" } }], prop)) === '{"page":"12","how":"name"}');
  check("no page", JSON.stringify(pageFor({ console_page: "" }, "Z", [{ id: "1", properties: { Project: "Y" } }], prop)) === '{"page":"","how":""}');
}

// ---- real films and real cards
if (!existsSync(join(CASES, "mac.json"))) {
  console.log(`  (no real cases at ${CASES} — run python3 hub/refreshhub-real.py for the real-film checks)`);
} else {
  const mac = JSON.parse(readFileSync(join(CASES, "mac.json"), "utf8"));
  const wasm = readFileSync(join(HERE, "src/mcp.wasm"));
  for (const folder of mac.films) {
    const film = join(CASES, "films", folder);
    const { instance } = await WebAssembly.instantiate(wasm, {});
    const x = instance.exports;
    const put = (t) => { const b = new TextEncoder().encode(t); const p = x.alloc(b.length); new Uint8Array(x.memory.buffer, p, b.length).set(b); return [p, b.length]; };
    const take = (p) => { const n = new DataView(x.memory.buffer).getUint32(p, true); const s = new TextDecoder().decode(new Uint8Array(x.memory.buffer, p + 4, n)); x.free_result(p); return s; };
    x.set_now(Date.now()); x.set_seed(1);
    const args = [put("film"), put(""), put("0000000000000001")];
    x.start(args[0][0], args[0][1], args[1][0], args[1][1], 1, args[2][0], args[2][1]);
    for (const name of readdirSync(join(film, "changes")).filter((n) => n.endsWith(".log")).sort()) {
      const [p, l] = put(readFileSync(join(film, "changes", name), "utf8")); x.add_log(p, l); x.dealloc(p, l);
    }
    x.settle();
    const view = JSON.parse(take(x.view()));
    // The relay keeps the proxies under the same names (`media/` in the bucket).
    const names = new Set(readdirSync(join(film, "media", "proxies")));
    const got = factsFromView(view, names, pictureCount(names));
    const want = mac.facts[folder];
    for (const field of ["pictures", "days", "director", "producer", "ratio", "console_page", "counts"]) {
      check(`${folder.replace(".shotlist", "")}: ${field}`, JSON.stringify(got[field]) === JSON.stringify(want[field]),
        `hub ${JSON.stringify(got[field])}\n      mac ${JSON.stringify(want[field])}`);
    }
  }
  const cardOf = (project) => {
    const w = mac.writes.filter((one) => one.key === `p/${project}/front.json`).pop();
    return JSON.parse(readFileSync(join(CASES, "writes", w.file), "utf8"));
  };
  let covers = 0;
  for (const one of mac.covers) {
    const card = cardOf(one.project);
    const wanted = coversWanted(one.title, card);
    const same = JSON.stringify([...wanted.keys()]) === JSON.stringify(Object.keys(one.wanted))
      && [...wanted].every(([slug, spec]) => JSON.stringify(spec) === JSON.stringify(one.wanted[slug]));
    check(`${one.title}: the covers wanted (${wanted.size})`, same, JSON.stringify([...wanted.keys()]));
    let prints = 0;
    for (const [slug, spec] of wanted) if ((await fingerprint(spec)) === one.prints[slug]) prints += 1;
    check(`${one.title}: every fingerprint the Mac's (${prints}/${wanted.size})`, prints === wanted.size);
    covers += wanted.size;
  }
  check(`the icon is one of them, keyed ${ICON}`, mac.covers.every((one) => ICON in one.wanted));
  console.log(`  ${mac.films.length} real films, ${mac.covers.length} real cards, ${covers} covers`);
}

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
