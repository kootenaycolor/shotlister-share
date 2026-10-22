#!/usr/bin/env node
/**
 * **Studio reads the card** — `src/studiocards.js` (stage 5 step 4, piece A).
 *
 * 1. The card: the record's words the way a film shows them (the film-facts
 *    rule), its mark, kind from Type, the ids it is known by, the fields
 *    Studio's project list draws.
 * 2. The switch: off by default; the cards door answers either way; the
 *    film-facts copy stands down only while it is on.
 * 3. The portal's renderer and the connector's card lookup: nothing while
 *    off; the card's director, producer and mark while on.
 * 4. The look: every film against its card, writing nothing; a planted
 *    difference is caught.
 *
 *     node hub/studiocards.mjs
 */
import { leaveOpen, takeOpen, cardOf, allCards, cardsOn, setCards, kindOfType, liveCardFor, layCardOnFront, compareFilm, cardsLook, cardsDoor, engineCard } from "./src/studiocards.js";
import { mirrorOne, onFilmFactsTimer, markLookup } from "./src/filmfacts.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  if (!good || process.env.VERBOSE) console.log(`  ${String(what).slice(0, 70).padEnd(72)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 500)}`}`);
};
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

function bucket() {
  const m = new Map();
  return {
    m,
    async get(k) { return m.has(k) ? { json: async () => JSON.parse(m.get(k)), text: async () => m.get(k), etag: "e" } : null; },
    async head(k) { return m.has(k) ? {} : null; },
    async put(k, v) { m.set(k, typeof v === "string" ? v : String(v)); return {}; },
    async list({ prefix, delimiter }) {
      const seen = new Set();
      for (const k of m.keys()) if (k.startsWith(prefix)) seen.add(prefix + k.slice(prefix.length).split(delimiter)[0] + delimiter);
      return { delimitedPrefixes: [...seen], truncated: false };
    },
  };
}
const ID = (n) => n.toString(16).padStart(32, "0");
const RELAY = (n) => "f" + n.toString(16).padStart(31, "0");
const fact = (value) => ({ value, v: 1, at: "2026-10-05T10:00:00.000Z" });
const ICON = "https://www.notion.so/icons/gift_red.svg";
const SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20"><path d="M1 1h18v18H1z" fill="#D44C47"/></svg>';
const fetchText = async (address) => (address === ICON ? SVG : "");

const env = { BUCKET: bucket() };
const put = (key, record) => env.BUCKET.put(`r/${key}/record.json`, JSON.stringify({ page: key, ...record }));

// A narrative with a film and a Notion icon; a commercial whose producer it hides;
// a music video; a minted project (its Notion page on the map); a project with no film.
await put(ID(1), { name: "Call Her Back", type: "Narrative", stage: "Active", film: { relay: RELAY(1) }, notion: "https://app.notion.com/p/x",
  facts: { title: fact("Call Her Back"), director: fact("Clara Moreau"), icon: fact(ICON), status: fact("Active"), shoot_dates: fact("2026-11-02"),
    drive_folder: fact("https://drive.google.com/drive/folders/abc"), logline: fact("A line."),
    credits: fact([{ role: "Director", people: ["Clara Moreau"] }, { role: "Producer", people: ["Max Kowalski"] }, { role: "Line Producer", people: ["Nina Lark"] }]) } });
await put(ID(2), { name: "Lets Bake", type: "Commercial", film: { relay: RELAY(2) }, hidden: ["producer", "logline"],
  facts: { title: fact("Let's Bake"), producer: fact("Owen Fairweather"), client: fact("Acme Express"), logline: fact("hidden"),
    credits: fact([{ role: "Director", people: ["Ollie Hart Brennan"] }, { role: "Producer", people: ["Owen Fairweather"] }]), director: fact("Ollie Hart Brennan") } });
await put(ID(3), { name: "Song", type: "Music Video", film: { relay: ID(3) }, facts: { title: fact("Song") } });
await put(ID(4), { name: "Minted", notion_page: ID(40), facts: { title: fact("Minted"), type: fact("Personal") } });
await put(ID(5), { name: "No Film", type: "Narrative", facts: {} });
await env.BUCKET.put("s/ids.json", JSON.stringify({ notion: { [ID(40)]: ID(4) }, alias: { [RELAY(1)]: ID(1), [RELAY(2)]: ID(2) } }));

// ── 1. the card ──────────────────────────────────────────────────────────────

check("kind follows Type", kindOfType("Commercial") === "commercial" && kindOfType("Music Video") === "commercial"
  && kindOfType("Narrative") === "film" && kindOfType("Personal") === "film" && kindOfType("") === "");

const marks = () => markLookup(env, fetchText);
let cards = await allCards(env, { marks: marks() });
const by = (name) => cards.find((c) => c.name === name);
check("one card per record", cards.length === 5, cards.map((c) => c.name).join());
const chb = by("Call Her Back");
check("facts are the film-facts rule's", same(chb.facts, { title: "Call Her Back", director: "Clara Moreau" }), JSON.stringify(chb.facts));
check("the mark is the Notion icon's outline and fill", chb.mark && chb.mark.colour === "#D44C47" && chb.mark.path.startsWith("M1 1"), JSON.stringify(chb.mark));
check("its film and its other ids", chb.relay === RELAY(1) && chb.aliases.includes(RELAY(1)) && !chb.aliases.includes(ID(1)), JSON.stringify(chb));
check("what the project list draws", chb.status === "Active" && chb.dates === "2026-11-02" && chb.drive_url.endsWith("/abc")
  && chb.notion_url === "https://app.notion.com/p/x" && chb.logline === "A line." && chb.kind === "film" && chb.type === "Narrative", JSON.stringify(chb));
check("every credit, for the name card", chb.credits.length === 3 && chb.credits[2].role === "Line Producer", JSON.stringify(chb.credits));
const cook = by("Lets Bake");
check("a hidden producer is shown as nobody", cook.facts.producer === "" && cook.kind === "commercial", JSON.stringify(cook.facts));
check("a hidden logline is not handed out", cook.logline === "", cook.logline);
check("music video → commercial", by("Song").kind === "commercial");
const minted = by("Minted");
check("a minted project: its Notion page is an alias, Type from its facts", minted.notion === ID(40) && minted.aliases.includes(ID(40)) && minted.kind === "film", JSON.stringify(minted));
check("no film, no relay", by("No Film").relay === "" && same(by("No Film").facts, {}));
check("one by its film's id", (await allCards(env, { marks: marks(), only: RELAY(2) })).map((c) => c.name).join() === "Lets Bake");
check("one by its Notion page", (await allCards(env, { marks: marks(), only: ID(40) })).map((c) => c.name).join() === "Minted");
check("what the engine takes", same(JSON.parse(engineCard(cook)), { facts: cook.facts, mark: null, kind: "commercial", type: "Commercial" }), engineCard(cook));

// ── 2. the switch ────────────────────────────────────────────────────────────

check("off by default", (await cardsOn(env)).on === false);
const reply = async (r) => ({ status: r.status, body: await r.json() });
const door = (rest, method, body) => cardsDoor(env, rest, method, async () => body, undefined, { readFilm: async () => ({}) });
let got = await reply(await door(["cards"], "GET"));
check("the cards door answers while off", got.status === 200 && got.body.on === false && got.body.cards.length === 5, JSON.stringify(got).slice(0, 200));
check("a door it does not know is not its", (await door(["other"], "GET")) === null);
got = await reply(await door(["studiocards"], "PUT", { on: true, by: "check" }));
check("the switch flips", got.body.on === true && got.body.by === "check" && (await cardsOn(env)).on === true);
got = await reply(await door(["cards"], "GET"));
check("and the door says so", got.body.on === true);
check("the switch refuses a wrong method", (await door(["studiocards"], "POST")).status === 405);

// ── film facts stand down only while on ──────────────────────────────────────

const told = [];
const mirror = async (_e, relay, _c, asked) => { told.push({ relay, asked }); return { ok: true, changed: ["director"] }; };
let one = await mirrorOne(env, ID(1), null, mirror);
check("on: nothing is written into the film", told.length === 0 && one.ok && one.card === true && one.want.director === "Clara Moreau", JSON.stringify(one));
one = await mirrorOne(env, ID(1), null, mirror, { dry: true });
check("on: a dry look still opens it", told.length === 1 && told[0].asked.dry === true, JSON.stringify(told));
await env.BUCKET.put("s/film-owner.json", JSON.stringify({ owner: "hub" }));
told.length = 0;
await onFilmFactsTimer(env, null, Date.UTC(2026, 9, 14, 12, 10));
check("on: the minute tells no film", told.length === 0 && !env.BUCKET.m.has("s/filmfacts-last.json"));
one = await setCards(env, { on: false });
check("off is refused: the switch is fixed on", one.on === true && /fixed on/.test(one.problem || "") && (await cardsOn(env)).on === true, JSON.stringify(one));

// ── 3. the renderer and the connector ────────────────────────────────────────

const front = { director: "Old Name", producer: "Old Producer", mark: { path: "M0 0", colour: "#000000" }, title: "Stored" };
const live = await liveCardFor(env, RELAY(1), { marks: marks() });
check("on: the card by the film's relay id", live && live.id === ID(1), JSON.stringify(live));
const laid = layCardOnFront(front, live);
check("the portal draws the card's director and mark", laid.director === "Clara Moreau" && laid.mark.colour === "#D44C47", JSON.stringify(laid));
check("and keeps what the card does not hold", laid.producer === "Old Producer" && laid.title === "Stored", JSON.stringify(laid));
check("a card that hides the producer clears the line", layCardOnFront(front, await liveCardFor(env, RELAY(2), { marks: marks() })).producer === "");
check("no record, no card", (await liveCardFor(env, ID(99), { marks: marks() })) === null);
check("no card leaves the front alone", same(layCardOnFront(front, null), front));

// ── 4. the look ──────────────────────────────────────────────────────────────

check("a film that shows its card is the same", same(compareFilm(chb, { displayTitle: "Call Her Back", director: "Clara Moreau", markPath: chb.mark.path, markColour: "#d44c47", kind: "film" }).differs, []));
const planted = compareFilm(chb, { displayTitle: "Call Her Back", director: "Someone Else", markPath: chb.mark.path, markColour: "#D44C47", kind: "commercial" });
check("a planted difference is caught", same(planted.differs, ["director", "kind"]) && planted.detail.director.film === "Someone Else", JSON.stringify(planted));
check("his hand mark is not a difference", same(compareFilm(chb, { displayTitle: "Call Her Back", director: "Clara Moreau", markPath: "M9", markColour: "#00FF00", markSource: "hand", kind: "film" }).differs, []));
const read = async (_e, relay) => {
  if (relay === RELAY(2)) throw new Error("no logs");
  return { displayTitle: relay === RELAY(1) ? "Call Her Back" : "Song", director: relay === RELAY(1) ? "Clara Moreau" : "", markPath: chb.mark.path, markColour: "#D44C47", kind: relay === ID(3) ? "commercial" : "film" };
};
const before = [...env.BUCKET.m.entries()].filter(([k]) => k.startsWith("r/")).map(([k, v]) => k + v).join();
const look = await cardsLook(env, null, read, { marks: marks() });
check("the look reads every film", look.films === 3 && look.cards === 5, JSON.stringify(look).slice(0, 300));
check("the look says which are the same", look.same === 2 && look.rows.find((r) => r.relay === RELAY(2)).trouble === "no logs", JSON.stringify(look.rows));
const after = [...env.BUCKET.m.entries()].filter(([k]) => k.startsWith("r/")).map(([k, v]) => k + v).join();
check("the look writes no record", before === after);

// ── 5. opening the console ───────────────────────────────────────────────────

const T = Date.UTC(2026, 9, 14, 12, 0);
check("a request needs a Mac and a project", (await leaveOpen(env, { page: ID(1) }, T)).status === 400 && (await leaveOpen(env, { mac: "Mac-Studio.local" }, T)).status === 400);
check("only archive or delete", (await leaveOpen(env, { mac: "M", page: ID(1), action: "rename" }, T)).status === 400);
let left = await leaveOpen(env, { mac: "Mac-Studio.local", page: "58831215-c468-8f52-9ea9-d49ee258a917", id: ID(1), action: "archive", by: "studio" }, T);
check("left for that Mac, page made bare", left.ok && left.request.page === "58831215c4688f529ea9d49ee258a917" && left.request.action === "archive", JSON.stringify(left));
check("another Mac takes nothing", (await takeOpen(env, { mac: "Laptop.local" }, T + 1000)).request === null);
let took = await takeOpen(env, { mac: "Mac-Studio.local" }, T + 1000);
check("its own Mac takes it", took.request && took.request.id === ID(1) && took.request.type === "project", JSON.stringify(took));
check("once", (await takeOpen(env, { mac: "Mac-Studio.local" }, T + 2000)).request === null);
await leaveOpen(env, { mac: "Mac-Studio.local", page: ID(1) }, T);
check("an old request is not acted on", (await takeOpen(env, { mac: "Mac-Studio.local" }, T + 3 * 60 * 1000)).request === null);
got = await reply(await cardsDoor(env, ["open"], "POST", async () => ({ mac: "X", page: ID(2) }), undefined));
check("the door leaves one", got.status === 200 && got.body.request.page === ID(2), JSON.stringify(got));
got = await reply(await cardsDoor(env, ["open", "take"], "POST", async () => ({ mac: "X" }), undefined));
check("the door hands it over", got.body.request && got.body.request.page === ID(2), JSON.stringify(got));

console.log(`\nstudiocards: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
