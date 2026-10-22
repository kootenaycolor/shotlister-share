/**
 * A link inside a copyable row is a link (2026-10-14): the LUTs row copies as
 * a whole, but the file name in it must open its file, not copy.
 *
 *     node hub/copyclick.mjs
 *
 * Runs `public/copy.js` against a stand-in document: just enough of one to
 * catch its click handler and feed it clicks from a row, a link inside the
 * row, and a link that is itself the copyable thing.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
let passed = 0;
let failed = 0;
const check = (name, ok) => { (ok ? passed++ : failed++); console.log(`  ${name.padEnd(72)} ${ok ? "PASS" : "FAIL"}`); };

const handlers = {};
const copied = [];
const node = (tag, attrs = {}, parent = null) => ({
  tag, attrs, parent, children: [],
  getAttribute: (k) => attrs[k] ?? null,
  hasAttribute: (k) => k in attrs,
  setAttribute: (k, v) => { attrs[k] = v; },
  contains(other) { for (let n = other; n; n = n.parent) if (n === this) return true; return false; },
  closest(sel) {
    for (let n = this; n; n = n.parent) {
      if (sel === "[data-copy]" && "data-copy" in n.attrs) return n;
      if (sel === "a" && n.tag === "a") return n;
      if (sel === "a[href]" && n.tag === "a" && "href" in n.attrs) return n;
    }
    return null;
  },
  classList: { add() {}, remove() {} },
  textContent: "",
});

globalThis.document = {
  createElement: () => ({ setAttribute() {}, remove() {}, style: {} }),
  head: { appendChild() {} },
  body: { appendChild() {} },
  addEventListener: (type, fn) => { handlers[type] = fn; },
  querySelectorAll: () => [],
};
globalThis.window = { getSelection: () => ({ isCollapsed: true }), feel: { toast() {} } };
globalThis.navigator = { clipboard: { writeText: async (t) => { copied.push(t); } } };
globalThis.Element = class {};

new Function(readFileSync(process.env.COPYJS || join(HERE, "public/copy.js"), "utf8"))();

const click = (target, extra = {}) => {
  let prevented = false;
  handlers.click({ target, altKey: false, preventDefault: () => { prevented = true; }, ...extra });
  return prevented;
};

const row = node("div", { "data-copy": "A Cam: fb.cube https://example.com/x" });
const chip = node("span", {}, row);
const link = node("a", { href: "https://example.com/x", target: "_blank" }, chip);
const plain = node("span", {}, row);

await Promise.resolve();
check("a click on the file link inside the row is left to the link", click(link) === false);
await Promise.resolve();
check("nothing was copied by that click", copied.length === 0);
check("a click on the rest of the row still copies it", click(plain) === true);
await new Promise((r) => setTimeout(r, 5));
check("and what it copies is the row's words", copied[0] === "A Cam: fb.cube https://example.com/x");
check("alt-click on the link copies the row (the modifier is the copy)", click(link, { altKey: true }) === true);

const mail = node("a", { href: "mailto:a@b.c", "data-copy": "a@b.c" });
check("a copyable link itself still follows its link on a plain click", click(mail) === false);

console.log(`\npassed ${passed}, failed ${failed}`);
process.exit(failed ? 1 : 0);
