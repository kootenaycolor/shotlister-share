#!/usr/bin/env node
/**
 * **What the portal's boards and pages lean on** — `src/boardheld.js`.
 * Studio asks before its week-old tidy of the sync server deletes a picture.
 *
 *     node hub/boardheld.mjs
 */
import { register } from "node:module";
register(`data:text/javascript,${encodeURIComponent(`
export async function resolve(spec, context, next) {
  if (spec.endsWith(".wasm")) return { url: "data:text/javascript,export default null", shortCircuit: true };
  return next(spec, context);
}
export async function load(url, context, next) {
  if (url.endsWith(".json")) return next(url, { ...context, importAttributes: { type: "json" } });
  return next(url, context);
}`)}`, import.meta.url);

const H = await import("./src/boardheld.js");

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 70).padEnd(72)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 500)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const h = (c) => c.repeat(32);
function bucket(files, { failOn } = {}) {
  return { async list({ prefix }) {
    return { objects: Object.keys(files).filter((k) => k.startsWith(prefix)).map((key) => ({ key, size: 1 })), truncated: false };
  }, async get(k) {
    if (failOn && k.includes(failOn)) return null;
    return k in files ? { text: async () => files[k] } : null;
  } };
}
const F = "p/" + "1".repeat(32) + "/";
const files = {
  [F + "boards/dump.json"]: JSON.stringify({ added: [{ id: "x", src: `pic/${h("a")}.jpg`, image: `/media/${h("b")}.jpg` }] }),
  [F + "boards/dump.settings.json"]: JSON.stringify({ note: `${h("d")}.jpg` }),
  [F + "boards/dump.history/1.json"]: JSON.stringify({ old: `${h("e")}.jpg` }),
  [F + "pages/outline.html"]: `<img src="media/${h("f")}.png"> and ${h("0")}0.jpg`,
  [F + "docs/" + h("9") + ".jpg"]: "binary",
  [F + "media/" + h("8") + ".jpg"]: "binary",
  [F + "logs/0000000000000000-0000000000000000.log"]: `${h("7")}.jpg`,
};
const env = { BUCKET: bucket(files) };

check("stemsIn finds a name after a slash, quote or space", same([...H.stemsIn(`x/${h("a")}.jpg "${h("b")}.png ${h("c")}.mp4`)].sort(), [h("a"), h("b"), h("c")]));
check("stemsIn ignores a longer run of hex", H.stemsIn(`${"a".repeat(40)}.jpg`).size === 0);

const got = await H.heldBy(env, "1".repeat(32));
check("a board's pic/ and media/ pictures are held", got.stems.includes(h("a")) && got.stems.includes(h("b")));
check("a published page's picture is held", got.stems.includes(h("f")));
check("history and settings are not read", !got.stems.includes(h("d")) && !got.stems.includes(h("e")));
check("the film's own logs and media are not the portal's", !got.stems.includes(h("7")) && !got.stems.includes(h("8")));
check("it counts the files it read", got.ok === true && got.scanned === 2, JSON.stringify(got));

const none = await H.heldBy({ BUCKET: bucket({}) }, "2".repeat(32));
check("a film with no portal files answers whole and empty", none.ok === true && none.scanned === 0 && none.stems.length === 0);

let threw = false;
try { await H.heldBy({ BUCKET: bucket(files, { failOn: "boards/dump.json" }) }, "1".repeat(32)); } catch { threw = true; }
check("a file that cannot be read makes the whole answer an error", threw);

const door = await H.heldDoor({ BUCKET: bucket({}, {}) }, ["held", "1".repeat(32)], "GET");
check("the door answers JSON", door.status === 200 && (await door.json()).ok === true);
const bad = await H.heldDoor(env, ["held", "../x"], "GET");
check("a made-up film name is refused", bad.status === 400);
const wrong = await H.heldDoor(env, ["held", "1".repeat(32)], "POST");
check("only GET", wrong.status === 405);
const broken = await H.heldDoor({ BUCKET: bucket(files, { failOn: "pages/" }) }, ["held", "1".repeat(32)], "GET");
check("a read error is a 500 with ok false", broken.status === 500 && (await broken.json()).ok === false);
check("another route is not ours", (await H.heldDoor(env, ["cards"], "GET")) === null);

console.log(`boardheld: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
