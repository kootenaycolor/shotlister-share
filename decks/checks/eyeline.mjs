// Re-solve every <!--HEAD--> budget in a deck's print design from the words
// themselves, so a change of type size can never leave one stale.
//
//     node eyeline.mjs <deck folder> [--write]
//
// The rule the Call Her Back bible is set to, 2026-09-08: a sheet's title
// starts at --eye on every sheet in the book, the words take exactly what
// they need, and a fixed gap follows before the plates.  So
//
//     band = eye + words + gap
//
// and the plates are centred in what is left.  Without --write it only
// reports.  Run render.py --html first: this reads build/deck.html, which is
// where the words from text.md have actually been poured in.
import { chromium } from '../checks/node_modules/playwright-core/index.mjs';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SHELL = process.env.CHROME ||
  process.env.HOME + '/Library/Caches/ms-playwright/chromium_headless_shell-1234' +
  '/chrome-headless-shell-mac-arm64/chrome-headless-shell';
const dir = resolve(process.argv[2] || '.');
const write = process.argv.includes('--write');
const GAP = 0.42;

const b = await chromium.launch({ executablePath: SHELL });
const pg = await b.newPage({ viewport: { width: 850, height: 1100 } });
await pg.goto('file://' + encodeURI(dir + '/build/deck.html'));
await pg.waitForTimeout(1500);
const m = await pg.evaluate(() => {
  const eye = parseFloat(getComputedStyle(document.documentElement)
    .getPropertyValue('--eye')) || 1.22;
  return {
    eye,
    stacks: [...document.querySelectorAll('.band > .stack')]
      .map(s => +(s.getBoundingClientRect().height / 96).toFixed(3)),
  };
});
await b.close();

const file = dir + '/template.html';
let tpl = readFileSync(file, 'utf8');
const slugs = [...tpl.matchAll(/<!--HEAD:([a-z_]+):([\d.]+)-->/g)].map(x => [x[1], x[2]]);
if (slugs.length !== m.stacks.length) {
  console.error(`template has ${slugs.length} HEAD blocks but the build drew ` +
    `${m.stacks.length} bands — a HEAD naming a slug with no picture group ` +
    `prints nothing. Turn it on or take it out before solving.`);
  process.exit(1);
}
const want = m.stacks.map(h => +(m.eye + h + GAP).toFixed(2));
let drift = 0;
console.log(`eyeline ${m.eye}in, gap ${GAP}in\n`);
console.log('section'.padEnd(30), 'was'.padStart(6), 'wants'.padStart(6), 'plates'.padStart(8));
slugs.forEach(([slug, was], i) => {
  const d = Math.abs(parseFloat(was) - want[i]);
  if (d > 0.005) drift++;
  console.log(slug.padEnd(30), was.padStart(6), want[i].toFixed(2).padStart(6),
    (10.45 - want[i]).toFixed(2).padStart(7) + 'in', d > 0.005 ? '  stale' : '');
});
if (!write) { console.log(`\n${drift} stale. Pass --write to fix.`); process.exit(drift ? 1 : 0); }
let i = 0;
tpl = tpl.replace(/<!--HEAD:([a-z_]+):([\d.]+)-->/g, (_, s) => `<!--HEAD:${s}:${want[i++].toFixed(2)}-->`);
i = 0;
tpl = tpl.replace(/(<div class="band[^"]*" style="height:)[\d.]+in(">)/g,
  (_, a, c) => a + want[i++].toFixed(2) + 'in' + c);
writeFileSync(file, tpl);
console.log(`\nwrote ${drift} budget(s) into template.html`);
