/**
 * **Update the Portal, from the portal** (2026-10-11, Projects Console
 * without the Mac, stage 3 step 2) — `hub/refresh.py`'s `main()`, which a
 * LaunchAgent on the Studio Mac ran every fifteen minutes, ported to run on
 * the portal's own clock so the Mac does not have to be on.
 *
 * One run, for every film and every portal with no film behind it:
 *
 * 1. **the film half** — what the film itself says (counts, days, director,
 *    producer, ratio, which pictures stand for what), asked of the engine
 *    here (`view()` in the film engine, `factsFromView`), not of `cargo` on
 *    the Mac; a portal whose page id a film names is carried into it first;
 * 2. **the words** — Notion's (the row, its ticked documents and pages, the
 *    spec sheets, the shoots, the crew, the director, the icon) and then the
 *    project record's typed facts over them (`from_record`);
 * 3. **the card** written (`front.json`), and
 * 4. **the link covers** drawn where their words moved (`linkcovers.js`).
 *
 * **Rule for rule.** The Notion half here is `from_notion` and
 * `words_from_notion`, not `refreshFilm` (the Refresh button's, in
 * `notion.js`), because the button's differs from the Python in small ways
 * (it asks Notion only for this project's rows, it finds the page from the
 * card rather than the film, it keeps a card's stored shoots when Shoots is
 * refused). The leaves are shared — reading a page's blocks, copying a file,
 * the documents and pages rules — and are the same in both.
 *
 * **Its own switch**, `GET/PUT /console/studio/owner/portal` (`mac` | `hub`),
 * "mac" until thrown. While the Mac owns it the clock does nothing; a look
 * can be asked for (`POST /console/studio/portal/run {dry: true}`), which
 * reads everything and writes nothing.
 *
 * **Within a worker's limits.** The Mac did all nine cards in one go; a
 * worker gets a bounded slice of time per tick. So a run is a *pass* over a
 * list made at its start, taken a few cards per minute (`BATCH`), with where
 * it got to kept in the bucket. One card's failure is a line in the log and
 * never stops the rest; a tick still going holds a lease so the next minute's
 * does not start the same card.
 */
import { keys, LAYOUT } from "../../relay/layout.js";
import mcpWasm from "./mcp.wasm";
import { begin, feed, take, filmStamp } from "./live.js";
import { listAll, everyPortal, filmlessPortal, titleOf, PROJECT } from "./films.js";
import { carryPortal } from "./carry.js";
import { recordView, layRecordFacts } from "./facts.js";
import {
  asker, notionReady, Refused, plain, bare, dates, relatesTo, related, prose, typedWords, markOf, filesOn,
  without, bothKinds, bothRoads, fedByNotion, slugOf, sectionSlug, pageColumn, readBlocks, mirror, putPage,
  leadOf, FILM_SCREENS, CAMERA_FROM, PROJECTS, PROJECT_DOCS, CAMERA_SHEETS, CREW, SHOOTS,
} from "./notion.js";
import { shootParts, followingPages } from "./notion.js";
import { fieldText } from "./entries.js";
import { specPills, colourIndex } from "./specpills.js";
import { boxesOfRow, recordSheets, laySheets, specSwitch } from "./specsheet.js";
import { factsFromView, pictureCount, pageFor, coversWanted } from "./refreshrules.js";
import { putCovers, drawer } from "./linkcovers.js";
import { stayGone, deletedNote } from "./deletedguard.js";
import { hubOwner } from "./fixedon.js";

export const OWNER_KEY = "s/portal-owner.json";
const STATE = { live: "s/portal-refresh.json", dry: "s/portal-refresh-dry.json" };
/** The Mac's `StartInterval`: a new pass this long after the last one began. */
export const EVERY_MINUTES = 15;
/**
 * Cards a tick takes on. **Two**: a film read cold (its logs not yet in the
 * cache) is a read of every log it has — Let's Bake is 468 — and a worker
 * may make only so many reads and calls in one go (1,000 on the paid plan).
 * Two of his largest films plus their Notion calls stay well under; three
 * did not. Nine cards, two a minute: a pass in five minutes.
 */
export const BATCH = 2;
/** How long a tick holds the pass before another may take it over. */
const LEASE_MS = 4 * 60_000;
/** A tick stops taking new cards once it has run this long. */
const TICK_MS = 40_000;
const READER = "0000000000000001";

/** Who keeps the portal's cards and covers: the server (the Mac's refresh.py
 * went in stage 5 step 9). */
export async function portalOwner(env) {
  const got = await env.BUCKET.get(OWNER_KEY);
  let said = null;
  try { said = got ? await got.json() : null; } catch { said = null; }
  return hubOwner(said);
}

const stamp = (when = Date.now()) => new Date(when).toISOString().replace(/\.\d{3}Z$/, "Z");
const many = (n, word) => `${n} ${word}${n === 1 ? "" : "s"}`;
const moved = (word, was, now) => (was === now ? many(now, word) : `${was} → ${many(now, word)}`);

// ------------------------------------------------- Python's way of reading rows

/**
 * One property as the words a person would read — Python's `prop`, which is
 * not quite `notion.js`'s: a `status` property is "" here, as it is there.
 * (His Status is a select; the difference never shows, and is kept anyway.)
 */
export function pyProp(row, name) {
  const field = ((row && row.properties) || {})[name];
  if (!field) return "";
  const kind = field.type;
  if (kind === "title" || kind === "rich_text") return plain(field[kind]);
  if (kind === "select") return (field.select || {}).name || "";
  if (kind === "multi_select") return (field.multi_select || []).map((o) => o.name || "").join(", ");
  if (kind === "number") {
    const n = field.number;
    return n === null || n === undefined ? "" : String(n);
  }
  if (kind === "url" || kind === "email" || kind === "phone_number") return field[kind] || "";
  if (kind === "checkbox") return field.checkbox ? "yes" : "";
  if (kind === "date") return (field.date || {}).start || "";
  return "";
}

/** `Shoot 2` out of `Lets Bake — Shoot 2` — `shoot_name`, split once (`maxsplit=1`). */
export function shootName(title, project) {
  const loose = (words) => String(words || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  const said = String(title || "");
  const m = /\s+[—–-]\s+/.exec(said);
  if (m && loose(said.slice(0, m.index)) === loose(project)) return said.slice(m.index + m[0].length).trim();
  return said.trim();
}

/** Which spec sheet a shoot uses, out of every row in Camera Spec Sheets — `sheet_for`. */
function sheetFor(shoot, sheets, page, shoots, say, label = "") {
  const newest = (rows) => rows.reduce((a, b) => (String(b.created_time || "") > String(a.created_time || "") ? b : a));
  if (shoot) {
    const own = sheets.filter((s) => shoot.sheets.includes(bare(s.id)) || related(s, "Shoot").includes(shoot.id));
    if (own.length) return newest(own);
  }
  let mine = sheets.filter((s) => relatesTo(s, "Projects", page));
  if (shoots.length) {
    const ours = new Set(shoots.map((one) => one.id));
    const whole = mine.filter((s) => !related(s, "Shoot").some((id) => ours.has(id)));
    mine = whole.length ? whole : mine;
  }
  if (!mine.length) return null;
  const pick = newest(mine);
  if (mine.length > 1) {
    say(`  ${mine.length} spec sheets${label ? ` for ${label}` : ""} and none says which shoot — using the newest, “${pyProp(pick, "Title") || pyProp(pick, "Lenses")}”`);
  }
  return pick;
}

// ------------------------------------------------------------- one run's reads

/**
 * What one tick shares between cards: every row of a data source is read
 * once (`rows_of` read them again for every film; the answer is the same).
 */
function tickReads() {
  const rows = new Map();
  return {
    /** Every row of a data source, following the cursor — `rows_of`. */
    async rowsOf(ask, source) {
      if (!rows.has(source)) {
        rows.set(source, (async () => {
          const out = [];
          let cursor = null;
          for (;;) {
            const body = { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) };
            let answer;
            try {
              answer = await ask.notion(`data_sources/${source}/query`, body);
            } catch (problem) {
              throw new Error(`${source}: ${problem.message}`);
            }
            out.push(...(answer.results || []));
            if (!answer.has_more) return out;
            cursor = answer.next_cursor;
          }
        })());
        rows.get(source).catch(() => rows.delete(source));
      }
      return await rows.get(source);
    },
  };
}

// ------------------------------------------------------------ the film half

/** What the film itself says — `facts(film)`, asked of the engine here. */
export async function filmFacts(env, project, ctx) {
  const { objects } = await filmStamp(env, project);
  if (!objects.length) throw new Error("the film has no change logs on the portal yet");
  const film = await WebAssembly.instantiate(mcpWasm, {});
  const x = film.exports;
  x.set_now(Date.now());
  x.set_seed(1);
  begin(x, project, "", true, READER);
  await feed(env, project, ctx, x, objects);
  const said = take(x, x.view());
  if (!said) throw new Error("the engine would not describe the film");
  const view = JSON.parse(said);
  const names = new Set((await listAll(env, keys.media(project))).map((o) => o.key.split("/").pop()));
  return factsFromView(view, names, pictureCount(names));
}

// ----------------------------------------------------------- the Notion half

/** The project's rows in Shoots, oldest first, or `null` when Notion would not say — `shoots_of`. */
async function shootsOf(reads, ask, page, project, say) {
  let rows;
  try {
    rows = await reads.rowsOf(ask, SHOOTS);
  } catch (problem) {
    if (/stopped early/.test(problem.message)) throw problem;
    say(`  could not read its shoots: ${problem.message}`);
    return null;
  }
  const out = [];
  for (const row of rows) {
    if (!relatesTo(row, "Project", page)) continue;
    const { base, name } = shootParts(shootName(pyProp(row, "Shoot"), project) || "Shoot");
    out.push({
      id: bare(row.id), name, base,
      status: pyProp(row, "Status"),
      dates: dates(row, "Dates"),
      changes: pyProp(row, "What Changes"),
      sections: pyProp(row, "Shot List Section").split(",").map((one) => one.trim()).filter(Boolean),
      crew: related(row, "Crew"),
      sheets: related(row, "Camera Spec Sheet"),
      docs: related(row, "Docs"),
      created: row.created_time || "",
    });
  }
  const key = (one) => [one.dates.start || "9999", one.created];
  out.sort((a, b) => {
    const [x, y] = [key(a), key(b)];
    return x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : x[1] < y[1] ? -1 : x[1] > y[1] ? 1 : 0;
  });
  return out;
}

/** Everything his Notion says about one film — `from_notion`. */
async function fromNotion(env, reads, ask, page, say) {
  const row = await ask.notion(`pages/${page}`);
  const said = typedWords(row, await prose(ask, page));
  Object.assign(said, {
    mark: await markOf(ask, row),
    status: pyProp(row, "Status"),
    type: pyProp(row, "Type"),
    length: pyProp(row, "Length"),
    shoot: dates(row, "Shoot Dates"),
    source: `notion:${page}`,
  });

  const got = await shootsOf(reads, ask, page, pyProp(row, "Project"), say);
  const known = got !== null;
  const shoots = got || [];
  const lead = leadOf(shoots);
  const slugFor = new Map(shoots.map((one) => [one.id, slugOf(one.base)]));
  const tagged = (doc) => {
    const mine = new Set(related(doc, "Shoot"));
    return shoots.filter((one) => mine.has(one.id) || one.docs.includes(bare(doc.id))).map((one) => slugFor.get(one.id));
  };

  const documents = [];
  const sections = [];
  for (const doc of await reads.rowsOf(ask, PROJECT_DOCS)) {
    if (!relatesTo(doc, "Projects", page) || !pyProp(doc, "Hub")) continue;
    const name = pyProp(doc, "Name");
    let section = pyProp(doc, "Page") || pyProp(doc, "Section");
    if (section && FILM_SCREENS.has(sectionSlug(section))) {
      say(`  “${section}” is one of the film's own screens — “${name}” stays a document`);
      section = "";
    }
    if (section) {
      const slug = sectionSlug(section);
      sections.push({
        slug, name: section, from: String(doc.id || "").replace(/-/g, ""), title: name,
        type: slug === "camera" ? "sheet" : "page", source: "notion", shoots: tagged(doc),
      });
      continue;
    }
    documents.push({
      name,
      kind: name.toLowerCase().includes("look") ? "lookbook" : "document",
      url: pyProp(doc, "URL") || doc.url || "",
      source: "notion",
      shoots: tagged(doc),
    });
  }
  said.documents = documents;
  said.sections = sections;

  // **The Old columns where they kept the camera labels** (specsheet.js,
  // 2026-10-14): the pills alone flatten a two camera sheet.
  const pillNames = Object.fromEntries(Object.entries(await specPills(env)).map(([k, v]) => [k, (v || []).map((o) => o.name)]));
  const boxes = (sheet) => boxesOfRow(sheet, pillNames);
  let camera = Object.fromEntries(Object.keys(CAMERA_FROM).map((k) => [k, ""]));
  let sheetPage = "";
  let sheetFiles = [];
  const sheets = await reads.rowsOf(ask, CAMERA_SHEETS);
  const sheet = sheetFor(lead, sheets, page, shoots, say);
  if (known) {
    said.shoots = [];
    for (const one of shoots) {
      const own = sheetFor(one, sheets, page, shoots, say, one.name);
      said.shoots.push({
        id: one.id, name: one.name, base: one.base, slug: slugOf(one.base),
        status: one.status, start: one.dates.start, end: one.dates.end,
        changes: one.changes, sections: one.sections,
        sheet: own ? bare(own.id) : "",
        sheet_edited: own ? own.last_edited_time || "" : "",
        camera: own ? boxes(own) : {},
        camera_files: own ? filesOn(own, "Production LUT") : [],
      });
    }
  }
  if (sheet) {
    camera = boxes(sheet);
    sheetPage = bare(sheet.id);
    sheetFiles = filesOn(sheet, "Production LUT");
    if (lead) say(`  the spec sheet is ${lead.name}'s — ${camera.lenses || "no lenses named"}`);
  }
  said.camera = camera;
  said.camera_sheet = sheetPage;
  said.camera_files = sheetFiles;

  const person = (mate) => ({
    name: pyProp(mate, "Name"), role: pyProp(mate, "Role"),
    department: pyProp(mate, "Department"), company: pyProp(mate, "Company"),
    email: pyProp(mate, "Email"), phone: pyProp(mate, "Phone"),
  });
  const everyone = await reads.rowsOf(ask, CREW);
  let crew = everyone.filter((mate) => relatesTo(mate, "Projects", page)).map(person);
  if (shoots.length) {
    const ours = new Set(shoots.map((one) => one.id));
    const onSome = new Set(shoots.flatMap((one) => one.crew.map(bare)));
    const whole = everyone.filter((mate) => relatesTo(mate, "Projects", page)
      && !related(mate, "Shoots").some((id) => ours.has(id)) && !onSome.has(bare(mate.id)));
    const kept = said.shoots || [];
    shoots.forEach((one, at) => {
      if (at >= kept.length) return;
      const mine = everyone.filter((mate) => related(mate, "Shoots").includes(one.id) || one.crew.includes(bare(mate.id)));
      kept[at].crew = [...mine, ...whole].map(person);
    });
    if (lead && known && shoots.length > 1) crew = kept[shoots.indexOf(lead)].crew;
  }
  said.crew = crew;
  // The Director relation, by name — `director_of`; left off when it names nobody.
  const named = [];
  const knownMates = new Map(everyone.map((mate) => [bare(mate.id), mate]));
  for (const who of ((((row.properties || {}).Director) || {}).relation) || []) {
    const id = bare(who.id);
    let mate = knownMates.get(id);
    if (mate === undefined && id) {
      try { mate = await ask.notion(`pages/${id}`); } catch (problem) {
        if (problem instanceof Refused) mate = null; else throw problem;
      }
    }
    const name = mate ? pyProp(mate, "Name") : "";
    if (name) named.push(name);
  }
  if (named.length) said.director = named.join(" & ");
  return said;
}

/** His files, ready to draw: the uploads copied here, the links left alone — `carried_over`. */
async function carriedOver(env, ask, raw, project) {
  const out = [];
  for (const one of raw) {
    if (!one.held) { out.push({ name: one.name, url: one.url }); continue; }
    const got = await mirror(env, ask, one.url, project, false);
    if (got) out.push({ name: one.name, file: got.file, bytes: got.bytes });
  }
  return out;
}

/**
 * **Only the pages he set up to follow Notion** (2026-10-17, his word: "Synopsis
 * and logline now come from the portal, not Notion. Only certain pages copy
 * Notion text, if it was started with that intent.")
 *
 * A page follows Notion when it says so itself: `source: "notion"` (Live from
 * Notion, on the page's own menu) and `from`, the Notion page it was made
 * from. Each such page is drawn again from that Notion page, by its own id, so
 * neither the project's ID nor its Notion row is asked for. Everything else on
 * the card (logline, synopsis, note, look, documents, people, the spec sheet,
 * shoots, the mark) is left exactly as it is, and Notion is never asked about it.
 * Answers how many pages could not be read.
 */
export { followingPages };

async function notionPages(env, card, project, say) {
  const pages = followingPages(card);
  if (!pages.length) return 0;
  if (!notionReady(env)) {
    say(`  no Notion connection — ${pages.map((s) => `“${s.name}”`).join(", ")} left as it was`);
    return 0;
  }
  const ask = asker(env, say);
  let trouble = 0;
  for (const section of pages) {
    let tree;
    try {
      tree = await readBlocks(env, ask, String(section.from).replace(/-/g, ""), project, new Map());
    } catch (problem) {
      if (/stopped early/.test(problem.message)) throw problem;
      say(`  could not read “${section.name}” from Notion: ${problem.message}`);
      trouble += 1;
      continue;
    }
    if (!tree.length) {
      say(`  “${section.name}”: its Notion page is empty — left as it was`);
      continue;
    }
    await putPage(env, project, section.slug, tree);
    section.blocks = tree.length;
    section.synced = new Date().toISOString(); // the page's Synced from line (pages.js)
    say(`  “${section.name}” drawn from Notion — ${tree.length} blocks`);
  }
  return trouble;
}

/**
 * The whole Notion half of one card, films and portals alike — `words_from_notion`.
 * **No longer called by the clock** (2026-10-17, `notionPages` instead); kept,
 * rule for rule with refresh.py, in case he wants any of it back.
 * Returns how many things went wrong; says what it did.
 */
async function wordsFromNotion(env, reads, ask, card, page, how, project, was, say) {
  let trouble = 0;
  card.linked = how;
  if (!page) {
    say("  no Notion project matches this film — its words are left as they were");
    return trouble;
  }
  try {
    const said = await fromNotion(env, reads, ask, page, say);
    said.documents = bothKinds(card.documents || [], said.documents);
    const agents = new Set((card.sections || []).filter((s) => !fedByNotion(s)).map((s) => s.slug));
    const kept = [];
    for (const section of said.sections || []) {
      if (agents.has(section.slug)) {
        say(`  “${section.name}” is written on the portal now — left alone`);
        continue;
      }
      let tree;
      try {
        tree = await readBlocks(env, ask, section.from, project, new Map());
      } catch (problem) {
        if (/stopped early/.test(problem.message)) throw problem;
        say(`  could not read “${section.name}”: ${problem.message}`);
        trouble += 1;
        continue;
      }
      if (!tree.length) continue;
      await putPage(env, project, section.slug, tree);
      section.blocks = tree.length;
      kept.push(section);
      say(`  “${section.name}” drawn from Notion — ${tree.length} blocks`);
    }
    said.sections = bothRoads(card.sections || [], kept, (said.sections || []).map((s) => s.slug));
    said.camera_files = await carriedOver(env, ask, said.camera_files || [], project);
    // each pill's Notion colour, for the camera page (src/specpills.js)
    said.camera_pills = colourIndex(await specPills(env));
    const sheet = said.camera_sheet || "";
    let notes = [];
    if (sheet) {
      try {
        notes = await readBlocks(env, ask, sheet, project, new Map());
      } catch (problem) {
        if (/stopped early/.test(problem.message)) throw problem;
        say(`  could not read the spec sheet's notes: ${problem.message}`);
        trouble += 1;
      }
    }
    notes = without(notes, new Set(said.camera_files.map((one) => String(one.name).trim().toLowerCase())));
    await putPage(env, project, "camera-sheet", notes);
    said.camera_notes = notes.length;
    const had = new Map((card.shoots || []).map((one) => [one.id, one]));
    for (const one of said.shoots || []) {
      const raw = one.camera_files || [];
      delete one.camera_files;
      if (one.sheet === sheet) {
        one.camera_files = said.camera_files;
        one.camera_notes = notes.length;
        await putPage(env, project, `camera-sheet-${one.slug}`, notes);
        continue;
      }
      const last = had.get(one.id) || {};
      if (one.sheet && last.sheet === one.sheet && last.sheet_edited === one.sheet_edited && "camera_notes" in last) {
        one.camera_files = last.camera_files || [];
        one.camera_notes = last.camera_notes;
        continue;
      }
      one.camera_files = await carriedOver(env, ask, raw, project);
      let theirs = [];
      if (one.sheet) {
        try {
          theirs = await readBlocks(env, ask, one.sheet, project, new Map());
        } catch (problem) {
          if (/stopped early/.test(problem.message)) throw problem;
          say(`  could not read ${one.name}'s spec sheet notes: ${problem.message}`);
          trouble += 1;
        }
      }
      theirs = without(theirs, new Set(one.camera_files.map((f) => String(f.name).trim().toLowerCase())));
      await putPage(env, project, `camera-sheet-${one.slug}`, theirs);
      one.camera_notes = theirs.length;
    }
    if ((said.shoots || []).length > 1) {
      const lead = said.shoots.find((one) => String(one.status).toLowerCase() === "upcoming") || said.shoots[said.shoots.length - 1];
      say(`  ${said.shoots.length} shoots — the portal leads with ${lead.name}`);
    } else if (!("shoots" in said) && (card.shoots || []).length > 1) {
      // **Notion would not say** — the shoots on the card stand: the front
      // keeps the next shoot's people, and each row its tags.
      const lead = card.shoots.find((one) => one.status === "Upcoming") || card.shoots[card.shoots.length - 1];
      if (lead.crew && lead.crew.length) said.crew = lead.crew;
      const tags = new Map([...(card.documents || []), ...(card.sections || [])].map((one) => [one.name, one.shoots || []]));
      for (const one of [...said.documents, ...said.sections]) {
        one.shoots = (one.shoots && one.shoots.length ? one.shoots : null) || tags.get(one.name) || [];
      }
    }
    if (notes.length || said.camera_files.length) {
      say(`  the spec sheet carries ${notes.length} note blocks and ${said.camera_files.length} file(s)`);
    }
    Object.assign(card, said);
    say(`  Notion: ${moved("document", was.documents, card.documents.length)}, ${moved("contact", was.crew, card.crew.length)}${
      Object.values(card.camera).some(Boolean) ? ", a camera spec sheet" : ""}`);
  } catch (problem) {
    say(`  could not read Notion for it: ${problem.message}`);
    trouble += 1;
  }
  return trouble;
}

// --------------------------------------------------------------- the bucket

/** The card exactly as the bucket holds it — `card_now`: parsed, or `{}`. */
async function cardNow(env, project) {
  const got = await env.BUCKET.get(keys.front(project));
  if (!got) return {};
  try {
    const card = JSON.parse(await got.text());
    return card && typeof card === "object" && !Array.isArray(card) ? card : {};
  } catch {
    return {};
  }
}

async function putCard(env, project, card) {
  await env.BUCKET.put(keys.front(project), JSON.stringify(card), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

/**
 * The bucket as a dry look sees it: every read goes through, every write is
 * written down instead. The same code then runs for a look and for real.
 */
function dryEnv(env, writes, detail) {
  const bucket = env.BUCKET;
  const BUCKET = {
    get: (...a) => bucket.get(...a),
    head: (...a) => bucket.head(...a),
    list: (...a) => bucket.list(...a),
    async put(key, body) {
      const text = typeof body === "string" ? body : null;
      const size = text !== null ? new TextEncoder().encode(text).length : body && body.byteLength !== undefined ? body.byteLength : 0;
      writes.push({ key, bytes: size, ...(detail && text !== null ? { body: text } : {}) });
      return { key, size };
    },
    async delete(key) { writes.push({ key, deleted: true }); },
  };
  // An empty target: the real `env` holds its bindings read-only, which a
  // proxy over it may not answer differently for.
  return new Proxy({}, {
    get: (_, name) => (name === "BUCKET" ? BUCKET : env[name]),
    has: (_, name) => name in env,
  });
}

// ------------------------------------------------------------------- the run

/** Every film the relay holds (a manifest, not a portal on its own), by name, then every portal on its own. */
export async function itemsNow(env) {
  const films = [];
  let cursor;
  do {
    const page = await env.BUCKET.list({ prefix: LAYOUT.prefix, delimiter: "/", cursor, limit: 1000 });
    for (const folder of page.delimitedPrefixes || []) {
      const id = folder.slice(LAYOUT.prefix.length).replace(/\/$/, "");
      if (!id || !PROJECT.test(id)) continue;
      if (!(await env.BUCKET.head(keys.manifest(id)))) continue;
      if (await filmlessPortal(env, id)) continue;
      films.push({ kind: "film", project: id, title: String(await titleOf(env, id)) });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  // `sorted(os.listdir(...))` on the Mac: the folder names, by code point.
  films.sort((a, b) => (`${a.title}.shotlist` < `${b.title}.shotlist` ? -1 : `${a.title}.shotlist` > `${b.title}.shotlist` ? 1 : 0));
  const portals = (await everyPortal(env))
    .filter((one) => /^[0-9a-f]{32}$/.test(one.project))
    .map((one) => ({ kind: "portal", project: one.project, title: one.title || one.project }));
  return [...films, ...portals];
}

/**
 * The words a tick needs before any card — `main()`'s opening: is there a
 * Notion connection, does it answer (`users/me`), and every Projects row (for
 * a film held to its project by title). Any refusal is a run without words,
 * as on the Mac.
 */
async function openNotion(env, say) {
  if (!notionReady(env)) {
    say("No Notion token here — refreshing what the films know, and leaving every word alone.");
    return null;
  }
  const reads = tickReads();
  const ask = asker(env, say);
  try {
    const me = await ask.notion("users/me");
    const whose = me.name || ((me.bot || {}).owner || {}).type || "Notion";
    say(`Reading Notion as well, as ${whose}.`);
  } catch (problem) {
    say(`Notion would not answer: ${problem.message}`);
    say("  Refreshing what the films know instead, and leaving every word alone.");
    return null;
  }
  try {
    const projects = await reads.rowsOf(ask, PROJECTS);
    return { reads, projects };
  } catch (problem) {
    say(`Could not read his projects: ${problem.message}`);
    return null;
  }
}

/** The file that makes an item what it is: a film's manifest, a portal's mark. */
function anchorsOf(item) {
  return item.kind === "film" ? [keys.manifest(item.project)] : [keys.portal(item.project)];
}

/** "deleted" / "gone" when the item is no longer there to refresh, else "". */
async function goneSince(env, item) {
  if (await deletedNote(env.BUCKET, item.project)) return "deleted";
  if (item.kind === "film") return (await env.BUCKET.head(keys.manifest(item.project))) ? "" : "gone";
  return (await filmlessPortal(env, item.project)) ? "" : "gone";
}

/** One film's card, from its facts to its covers. Returns {trouble}. */
async function refreshOneFilm(env, ctx, item, standing, opts, say) {
  let trouble = 0;
  let fact;
  try {
    fact = await filmFacts(env, item.project, ctx);
  } catch (problem) {
    say(`  could not read the film: ${problem.message}`);
    return { trouble: 1 };
  }
  // **A film that has arrived takes its portal with it** — `carry_portals`.
  const page0 = String(fact.console_page || "").replace(/-/g, "");
  const { oneIdOn } = await import("./projectid.js");
  if (page0 && standing.has(page0) && (await oneIdOn(env)).on) {
    // One ID (projectid.js): nothing is carried; the portal stays where it is.
    say(`  its portal on its own stays where it is (one ID)`);
  } else if (page0 && standing.has(page0)) {
    if (opts.dry) {
      say(`  would carry its portal on its own into the film`);
      standing.delete(page0);
    } else {
      try {
        const carried = await carryPortal(env, page0, item.project);
        if (carried) {
          const said = ["people", "links", "sections", "documents", "objects"].filter((k) => carried[k]).map((k) => `${carried[k]} ${k}`).join(", ");
          say(`  carried its portal on its own into the film (${said || "nothing left to move"})`);
          standing.delete(page0);
        } else {
          say("  could not carry its portal in: no portal to carry");
        }
      } catch (problem) {
        say(`  could not carry its portal in: ${problem.message}`);
      }
    }
  }

  const card = await cardNow(env, item.project);
  const before = JSON.stringify(card);
  if (!("version" in card)) card.version = 1;
  // **His photograph is never touched.** Everything the film said but its page.
  for (const [k, v] of Object.entries(fact)) if (k !== "console_page") card[k] = v;

  trouble += await notionPages(env, card, item.project, say);
  // The record by the film's own link (its `console_page`); no Notion row is read for it.
  const { page } = pageFor(fact, item.title, [], pyProp);
  if (page) {
    const view = await recordView(env, page);
    const took = layRecordFacts(card, view.facts, view.hidden);
    if (took.length) say(`  from the project record: ${took.join(", ")}`);
    await sheetsFromRecord(env, card, view.facts, say);
  }
  if (sameCard(card, before)) say("  nothing had changed");
  card.updated = stamp();
  try {
    await putCard(env, item.project, card);
  } catch (problem) {
    say(`  could not write its page: ${problem.message}`);
    trouble += 1;
  }
  const covers = await coversFor(env, item, card, opts, say);
  if (!covers.ok) return { trouble };
  const c = card.counts;
  say(`  ${many(c.scenes, "scene")}, ${many(c.shots, "shot")}, ${many(c.locations, "location")}, ${many(c.days, "day")} — your-domain.example/f/${item.project}`);
  return { trouble };
}

/** One portal with no film behind it: the words and the covers, nothing of a film. */
async function refreshOnePortal(env, item, opts, say) {
  let trouble = 0;
  const card = await cardNow(env, item.project);
  const before = JSON.stringify(card);
  if (!("version" in card)) card.version = 1;
  trouble += await notionPages(env, card, item.project, say);
  const view = await recordView(env, item.project);
  const took = layRecordFacts(card, view.facts, view.hidden);
  if (took.length) say(`  from the project record: ${took.join(", ")}`);
  await sheetsFromRecord(env, card, view.facts, say);
  if (sameCard(card, before)) say("  nothing had changed");
  card.updated = stamp();
  try {
    await putCard(env, item.project, card);
  } catch (problem) {
    say(`  could not write its page: ${problem.message}`);
    return { trouble: trouble + 1 };
  }
  await coversFor(env, item, card, opts, say);
  say(`  a portal with no film — your-domain.example/f/${item.project}`);
  return { trouble };
}

/** The record's spec sheets over Notion's, once the switch is on (specsheet.js):
 * read the record first, Notion only for a shoot it has no sheet for. */
async function sheetsFromRecord(env, card, facts, say) {
  if (!(await specSwitch(env)).on) return;
  const laid = laySheets(card, recordSheets(facts));
  if (laid.length) say(`  spec sheet from the project record: ${laid.join(", ")}`);
}

/** `json.dumps(card, sort_keys=True) == before`, as near as JS says it: the same JSON, keys aside. */
function sameCard(card, before) {
  const sorted = (v) => (Array.isArray(v) ? v.map(sorted) : v && typeof v === "object"
    ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])])) : v);
  return JSON.stringify(sorted(card)) === JSON.stringify(sorted(JSON.parse(before)));
}

/** The covers — `put_cover`; a cover that will not draw is never a reason to fail the card. */
async function coversFor(env, item, card, opts, say) {
  // **A browser per card, and only for a card with a cover to draw.** One
  // browser kept for a whole run of a hundred-odd covers stopped answering
  // in the local rig; a card is at most seventeen, and most runs draw none.
  const draw = opts.dry ? null : drawer(env);
  try {
    const { todo, drawn } = await putCovers(env, item.project, item.title, card, { draw, dry: opts.dry, redraw: opts.redraw });
    if (opts.dry && todo.length) say(`  would redraw ${many(todo.length, "link cover")}: ${todo.map((s) => s || "the film").join(", ")}`);
    else if (drawn) say(`  ${drawn} link cover${drawn === 1 ? "" : "s"} redrawn`);
    return { ok: true, todo };
  } catch (problem) {
    say(`  its link covers could not be drawn: ${problem.message}`);
    return { ok: false };
  } finally {
    if (draw) await draw.close();
  }
}

async function readState(env, key) {
  const got = await env.BUCKET.get(key);
  if (!got) return { state: {}, etag: null };
  try {
    const state = await got.json();
    return { state: state && typeof state === "object" ? state : {}, etag: got.etag };
  } catch {
    return { state: {}, etag: got.etag };
  }
}

async function writeState(env, key, state, etag) {
  return await env.BUCKET.put(key, JSON.stringify(state), {
    httpMetadata: { contentType: "application/json" },
    ...(etag === undefined ? {} : { onlyIf: etag ? { etagMatches: etag } : { etagDoesNotMatch: "*" } }),
  });
}

/**
 * One tick of the refresh: start a pass when one is due, take the next few
 * cards of it, keep where it got to. Answers what it did.
 *
 * - `dry`: read everything, write nothing (its own pass and state, so a look
 *   never moves the real pass along); `detail` adds every would-be write.
 * - `force`: start a pass now even if one ran in the last fifteen minutes.
 * - `all`: take every remaining card in this one call (a check, or a person
 *   asking — the clock never does).
 * - `only`: one card by project id or a piece of its title, outside any pass
 *   (`refresh.py "ZED"`).
 * - `redraw`: draw every cover again (`refresh.py --covers`).
 */
export async function refreshTick(env, ctx, when = Date.now(), opts = {}) {
  const dry = Boolean(opts.dry);
  const stateKey = dry ? STATE.dry : STATE.live;
  const started = Date.now();
  const lines = [];
  const say = (line) => lines.push(line);
  const writes = [];
  const work = dry ? dryEnv(env, writes, Boolean(opts.detail)) : env;

  const { state, etag } = await readState(env, stateKey);
  if (state.lease && state.lease.until > when && !opts.only) {
    return { busy: true, lease: state.lease, at: stamp(when) };
  }

  let items;
  let pass = state.pass && !state.pass.done ? state.pass : null;
  if (opts.only) {
    const asked = String(opts.only).toLowerCase();
    items = (await itemsNow(env)).filter((one) => one.project === asked || one.title.toLowerCase().includes(asked));
    pass = { id: `only-${stamp(when)}`, started: stamp(when), items, at: 0, standing: [], only: true };
  } else if (!pass) {
    const last = state.last_pass && Date.parse(state.last_pass.started);
    const due = opts.force || !last || when - last >= EVERY_MINUTES * 60_000 - 30_000;
    if (!due) return { idle: true, at: stamp(when), next: new Date(last + EVERY_MINUTES * 60_000).toISOString() };
    items = await itemsNow(env);
    pass = {
      id: stamp(when), started: stamp(when), items, at: 0,
      standing: items.filter((one) => one.kind === "portal").map((one) => one.project),
      results: {},
    };
  }
  if (!opts.only) {
    const claimed = await writeState(env, stateKey, { ...state, pass, lease: { until: when + LEASE_MS, at: stamp(when) } }, etag);
    if (!claimed) return { busy: true, at: stamp(when) };
  }

  const standing = new Set(pass.standing || []);
  const opened = { dry, redraw: Boolean(opts.redraw) };
  const done = [];
  try {
    if (!pass.items.length) say("No films to update.");
    const limit = opts.all || opts.only ? Infinity : Math.max(1, Number(opts.batch) || BATCH);
    while (pass.at < pass.items.length && done.length < limit && (opts.all || opts.only || Date.now() - started < TICK_MS)) {
      const item = pass.items[pass.at];
      pass.at += 1;
      // **Its place kept before the card is begun**, so a card that brings
      // the whole tick down (a limit, not an error it can catch) is passed
      // over by the next minute rather than tried for ever.
      if (!opts.only) {
        const now = (await readState(env, stateKey)).state;
        await writeState(env, stateKey, { ...now, pass: { ...pass, standing: [...standing] }, lease: { until: Date.now() + LEASE_MS, at: stamp() } });
      }
      if (item.kind === "portal" && !standing.has(item.project)) {
        say(`\n${item.title}`);
        say("  carried into its film — left to the film's card");
        done.push({ project: item.project, title: item.title, skipped: "carried" });
        continue;
      }
      const mine = [];
      const sayMine = (line) => { mine.push(line); say(line); };
      sayMine(`\n${item.title}`);
      // **Asked again now, not at the pass's start** (2026-10-17): a project
      // deleted since the list was made is passed over, and the card's own
      // writes go through `stayGone`, which refuses them the moment its
      // project file goes, so a delete during the card is not written back.
      const gone = await goneSince(env, item);
      if (gone) {
        sayMine(`  ${gone} since this pass began — left alone`);
        done.push({ project: item.project, title: item.title, kind: item.kind, skipped: "gone", trouble: 0, lines: mine.slice(1) });
        continue;
      }
      const cardEnv = stayGone(work, { anchors: { [item.project]: anchorsOf(item) } });
      let trouble = 0;
      try {
        if (item.kind === "film") ({ trouble } = await refreshOneFilm(cardEnv, ctx, item, standing, opened, sayMine));
        else ({ trouble } = await refreshOnePortal(cardEnv, item, opened, sayMine));
      } catch (problem) {
        trouble += 1;
        sayMine(`  stopped: ${String((problem && problem.message) || problem).slice(0, 300)}`);
      }
      done.push({ project: item.project, title: item.title, kind: item.kind, trouble, lines: mine.slice(1) });
    }
  } catch (problem) {
    // Never a card's fault (each has its own catch): the run itself, kept
    // as a line so the pass's place and the lease are still written below.
    say(`Stopped: ${String((problem && problem.message) || problem).slice(0, 300)}`);
  }
  pass.standing = [...standing];
  const finished = pass.at >= pass.items.length;
  if (finished && done.length) {
    const all = [...Object.values(pass.results || {}), ...done].reduce((n, d) => n + (d.trouble || 0), 0);
    say(all ? `\nDone, with ${all} problem(s) above.` : "\nDone.");
  }
  const out = {
    at: stamp(when), pass: pass.id, dry, took: done.length, left: pass.items.length - pass.at,
    trouble: done.reduce((n, d) => n + (d.trouble || 0), 0), lines,
    ...(dry ? { writes: writes.length, ...(opts.detail ? { would: writes } : {}) } : {}),
  };
  if (!opts.only) {
    const next = { ...(await readState(env, stateKey)).state };
    next.pass = finished ? { ...pass, done: true, finished: stamp() } : pass;
    next.pass.results = { ...(pass.results || {}), ...Object.fromEntries(done.map((d) => [d.project, { at: out.at, ...d }])) };
    if (finished) next.last_pass = { started: pass.started, finished: stamp(), cards: pass.items.length, trouble: Object.values(next.pass.results).reduce((n, d) => n + (d.trouble || 0), 0) };
    next.last_tick = { at: out.at, took: out.took, left: out.left, trouble: out.trouble, lines: lines.slice(-200) };
    delete next.lease;
    await writeState(env, stateKey, next);
  }
  return out;
}

/** The clock's door: a tick of the real pass while the portal owns it, nothing while the Mac does. */
export async function onPortalTimer(env, ctx, when = Date.now()) {
  const { owner } = await portalOwner(env);
  if (owner !== "hub") return null;
  try {
    return await refreshTick(env, ctx, when, {});
  } catch (e) {
    const { state } = await readState(env, STATE.live);
    state.last_tick = { at: stamp(when), trouble: 1, lines: [String((e && e.stack) || e).slice(0, 2000)] };
    delete state.lease;
    await writeState(env, STATE.live, state);
    return null;
  }
}

/** What the status door shows: who owns it, the real pass, the last look. */
export async function portalStatus(env) {
  const [owner, live, dry] = await Promise.all([portalOwner(env), readState(env, STATE.live), readState(env, STATE.dry)]);
  const brief = (state) => {
    const pass = state.pass || null;
    return {
      pass: pass ? { id: pass.id, started: pass.started, done: Boolean(pass.done), at: pass.at, of: (pass.items || []).length,
        results: pass.results || {} } : null,
      last_pass: state.last_pass || null,
      last_tick: state.last_tick || null,
      lease: state.lease || null,
    };
  };
  return { owner: owner.owner, at: owner.at, by: owner.by, live: brief(live.state), dry: brief(dry.state) };
}

/**
 * **One cover drawn now and handed back, nothing kept** — to see what
 * Cloudflare's browser makes of a card before the switch is thrown (the Mac
 * keeps drawing until then). `only` finds the card as a run would; `slug` is
 * the page (`""` the film's, `icon.png` the icon). Answers the PNG's bytes,
 * or throws in words.
 */
export async function trialCover(env, only, slug = "") {
  const asked = String(only || "").toLowerCase();
  const item = (await itemsNow(env)).find((one) => one.project === asked || one.title.toLowerCase().includes(asked));
  if (!asked || !item) throw new Error("No film or portal by that name.");
  const spec = coversWanted(item.title, await cardNow(env, item.project)).get(String(slug || ""));
  if (!spec) throw new Error("That card has no cover by that name.");
  const draw = drawer(env);
  try {
    return await draw.draw(spec);
  } finally {
    await draw.close();
  }
}
