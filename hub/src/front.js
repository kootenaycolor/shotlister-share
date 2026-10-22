/**
 * The front of house: what a collaborator meets before they meet the shot list.
 *
 * **This is a projection, not a source, and the distinction is the whole
 * design.** Two things already know the truth and neither of them is here: the
 * *engine* knows what the film is — scenes, shots, locations, days, the ratio —
 * and *Notion* knows what a person wrote about it — the logline, the status,
 * the shoot dates, which documents matter, who the crew are. Nothing on this
 * page is authored here. It is copied here so that a page can be drawn without
 * asking either of them.
 *
 * Why that matters, concretely:
 *
 * - **The shelf cannot be drawn any other way.** The hub knows a film's title
 *   and how many change logs it has. Everything else exists only after every
 *   log has been replayed — 125 of them on his own film — and doing that on the
 *   landing route for three films at once is the six-open-responses trap that
 *   took the MCP down on its first live morning.
 * - **Notion is never on the critical path.** If its token expires or its API
 *   is down, the portal shows yesterday's card rather than an error. A page
 *   that a director opens on a shoot day cannot depend on a third party being
 *   awake.
 * - **It can always be thrown away and rebuilt**, because nothing here is the
 *   only copy of anything.
 *
 * Written by the MCP (`set_front`, `add_document`), so the thinking happens in
 * an agent that can read Notion and the film alike — which is
 * `design/notion-bridge.md`'s standing rule that the clever part lives outside
 * the app, and its one-way bargain: *Notion feeds Shotlister*, never the
 * reverse.
 */

import { ICON_CHOICES } from "./icons.js";
import { keys } from "../../relay/layout.js";
import { cardOf } from "./live.js";
import { filmlessPortal } from "./films.js";
import { tidyCredits } from "./credits.js";

/** Big enough for a long logline and two hundred crew; small enough to refuse a mistake. */
export const MAX_FRONT = 512 * 1024;

const LIMITS = {
  logline: 2000,
  note: 4000,
  look: 1200,
  status: 40,
  type: 40,
  length: 40,
  director: 200,
  producer: 200,
  source: 300,
};

const MAX_DOCUMENTS = 120;
const MAX_CAMERA_FILES = 12;
const MAX_CREW = 300;

/**
 * How many pictures each way in may draw itself with.
 *
 * **Enough to fill the tile and not one more.** These are names only — the
 * pictures themselves are already in the bucket and already served — but a card
 * that carried two hundred of them would be a second copy of the film's media
 * list, going stale, for no gain. The page draws six frames, three location
 * photographs and four board pictures; the spare few are so a missing file
 * leaves a gap rather than a hole.
 */
const MAX_PICTURES = { scenes: 8, locations: 5, boards: 6 };

/** A shoot week, and then some. The tile draws three. */
const MAX_DAYS = 12;

/**
 * The camera spec sheet, in the order a crew reads one.
 *
 * These are his own Notion columns, renamed only where the column name is a
 * sentence: `Camera` → `body`, `Color Space` → `colour`, `Camera Shooting
 * Format` → `format`, `Finishing Resolution` → `finishing`. **Nothing
 * here is computed and nothing is guessed** — a spec sheet that invents a codec
 * is worse than no spec sheet, so a field he has not filled in is simply absent
 * from the page.
 *
 * A camera has no frame guides or finishing resolution of its own (folded
 * into the sheet's Aspect Ratio and Finishing Resolutions lists, 2026-10-15).
 */
export const CAMERA = {
  // room for a line per camera (src/entries.js: "A Cam: Alexa 35")
  body: 400,
  format: 300,
  capture: 200,
  colour: 300,
  codec: 200,
  // a line per camera too, since Frame Rate became text (2026-10-05)
  fps: 200,
  desqueeze: 100,
  lenses: 1000,
  // what the shoot carries beside its lenses (2026-10-14, kitlibrary.js); the
  // record's sheet only, Notion has no column for them
  modifiers: 600,
  filters: 1000,
  // "LUT Labels": a label per Production LUT, one per line
  luts: 2000,
};

/** A stored file is content-addressed, exactly like every picture. */
export const FILE_NAME = /^[0-9a-f]{32}\.[A-Za-z0-9]{1,8}$/;

/** The two piles he asked for: the look book, and everything else worth pinning. */
const KINDS = new Set(["lookbook", "document"]);

/**
 * **The two questions every document on a film answers.**
 *
 * His reading of the plan, 2026-09-08: *"there's kind or maybe type, and then
 * supply could be just called something else... your categorizations are
 * correct."* So the model stands and the words change — `Type` is his own, and
 * `Source` is the plain one, already meaning exactly this on the film's own
 * card (`front.source` is `notion:<page>`).
 *
 * **Type — what draws it.** A spec sheet is ten fixed fields; a deck has an
 * editor of its own; a page is words and pictures. Nothing else has ever said
 * which of the three a rail row is, so the rail could not tell his forty-page
 * bible from a paragraph somebody typed.
 *
 * **Source — where its words come from, and whether they keep coming.** This
 * is the one he could never see, and the one that decides who may write:
 *
 *   `notion`       fetched again every refresh; edit it in Notion
 *   `notion-once`  copied once, then his; Notion has let go of it
 *   `here`         written on the portal or by an agent
 *   `program`      published by the Deck Editor
 *
 * **`notion-once` is new and has never existed.** Until now a Notion page fed
 * a portal page forever or not at all, and the only way to take a snapshot was
 * for an agent to copy it — which locked Notion out permanently with no way
 * back. His decision, 2026-09-08: the source setting decides who wins, and it
 * is changeable both ways, so nothing is ever a one-way door.
 *
 * **Not stored anywhere yet, and that is deliberate.** Both are *derived* from
 * what a card already carries (`by`, the slug, whether a document is a held
 * file or a link), so every film that exists gains both the moment this runs,
 * with nothing migrated and nothing rewritten. A card that starts storing them
 * simply wins over the derivation.
 */
const TYPES = new Set(["page", "deck", "sheet", "board"]);

/**
 * **Who may open a board.** His ruling, 2026-09-25: a board starts as his own
 * sketchpad and is shared when he chooses — Halcyon's went out to the crew
 * because he wanted it to that day, and most boards will not.
 *
 *   `me`    him alone — the film's administrators
 *   `crew`  anybody signed in to the film
 *   `link`  anybody who can open the film, the share link included
 *
 * **Its own switch, not a row in Visibility's hidden list.** That list hides a
 * page from everybody who is not an editor at once, which has no "signed-in
 * crew yes, link no" setting and no "him alone" setting — the two a board
 * needs. `boardOpen` in `films.js` is the one place this is read.
 */
export const SHARES = ["me", "crew", "link"];
export const SOURCES = new Set(["notion", "notion-once", "here", "program"]);

/**
 * The sources a *written page* may be set to, and the only ones a control offers.
 *
 * **`program` is not on this list on purpose.** A deck's words are written by
 * the Deck Editor, so handing one to Notion or to an agent would mean the next
 * publish silently taking it back. A deck says what it is and offers no choice.
 */
export const PAGE_SOURCES = ["notion", "notion-once", "here"];

/** Where a section's words come from, when the card does not say. */
function sourceFrom(by) {
  if (by === "deck") return "program";
  if (by === "mcp") return "here";
  return "notion";
}

/**
 * What draws a section, when the card does not say.
 *
 * **The spec sheet is the one page whose slug decides its type.** `camera` is
 * the record's own sheet however it arrived — a Notion section folded onto it
 * is still ten fixed fields with a tree underneath, not a page of its own.
 */
function typeFrom(slug, by) {
  if (slug === "camera") return "sheet";
  return by === "deck" ? "deck" : "page";
}

export function emptyFront() {
  return {
    version: 1,
    updated: "",
    source: "",
    // **How this film found its Notion page** — `link` if it carries the
    // page's id, `name` if the two were matched because their titles happen to
    // read the same, empty if it has no Notion page at all. Written by
    // `refresh.py`; see `page_for` there for why the second is fragile.
    //
    // **Listed here or it does not survive.** `tidy` rebuilds a card from this
    // shape and drops anything it has not been taught (Ref 721) — silently,
    // which is how a deck's page once came back claiming Notion had written it.
    linked: "",
    logline: "",
    note: "",
    look: "",
    status: "",
    type: "",
    length: "",
    director: "",
    producer: "",
    // **Every other credit the project shows** (2026-10-05, "more than 1 per
    // title"): {role, people} in the record's order — the director and the
    // producer stay the two lines above, from the film. Laid from the record
    // (`layRecordFacts`), never typed here.
    credits: [],
    ratio: 0,
    shoot: { start: "", end: "" },
    key_image: "",
    // **The film's own icon and colour**, out of its Notion row: the outline of
    // the icon rather than its address, so the page never goes to notion.so for
    // a picture, and the colour that becomes the page's accent.
    mark: { path: "", colour: "" },
    camera: Object.fromEntries(Object.keys(CAMERA).map((k) => [k, ""])),
    // The lead spec sheet's Notion page (Ref 1627): what Shotlister edits for a
    // film with no Shoots rows. A shoot carries its own as `sheet`.
    camera_sheet: "",
    // `diagrams` is the Diagrams row's: without it here `tidy` dropped the
    // film's count, `unfilled` read a zero and the row left every rail.
    counts: { scenes: 0, shots: 0, locations: 0, boards: 0, days: 0, diagrams: 0, pictures: 0 },
    // **What each way in is drawn with.** A file name apiece, in the order the
    // film has them: a frame off the front of each scene, a photograph off each
    // location, a picture off each board. The page draws them; nothing here
    // decides what they mean.
    pictures: { scenes: [], locations: [], boards: [] },
    // The shoot days the film actually has, so the schedule can be drawn as
    // dates rather than as the number 3.
    days: [],
    documents: [],
    // **What is attached to the camera spec sheet, and whether it has notes.**
    // The LUT, mostly. Same shape as a document, because it is the same thing:
    // a file we hold, or a link to Drive. `camera_notes` is only a count — the
    // notes themselves are a page beside the film, read when it is opened.
    camera_files: [],
    camera_notes: 0,
    // **The sections he has named in Notion**, each one a Project Docs row with
    // `Hub` ticked and a `Section` set. Names only: the pages themselves live
    // at `pages/<slug>.json` and are read when one is opened, because a bible
    // is forty pictures and this card is read by every page there is.
    sections: [],
    // **The sidebar's order**, one flat list of page addresses (2026-10-11).
    // His ruling: the sidebar's headings and the Library's categories were two
    // systems naming the same things, and they are one now. The headings *are*
    // the categories (`shelves`, below); a page stands under the heading of the
    // category it is filed in (`shelfIdOf`), and this list is only the order
    // pages come in, within that heading. Anything not named here falls to the
    // end of its category, in its natural order, so a page added this morning
    // appears without being filed first. A card from before this carried
    // `groups` (his own headings and their rows); `tidy` turns each heading
    // into a category of the same name and files its rows there.
    rail: [],
    // **The Library is every page and document the film holds**; the sidebar
    // is only what he has pinned from it. These two lists are the pages taken
    // *off* the sidebar, `{ at }` each (older cards also carry `head`, which
    // nothing reads now) — `library` for ones still in the Library's main
    // list, `archive` for ones tucked into its Archive. Both are off every
    // sidebar and still open from their address. **They stay in `rail`**, so
    // putting one back on the sidebar finds it where it was. Nothing new is
    // ever off: a page added tomorrow is on the sidebar until he says otherwise.
    library: [],
    // **The documents he pinned to the sidebar** (2026-10-11: any page of the
    // portal can be a sidebar row): `{ at: "doc:<name>", head }`. Pages are on
    // the sidebar until `library` says otherwise; a document is off it until
    // it is here.
    docPins: [],
    archive: [],
    // **The film's Library shelves**, `{id, name}` in order (`shelvesOf`):
    // the seven to start, renamed, reordered and added to as he likes.
    shelves: SHELF_DEFAULTS.map((one) => ({ ...one })),
    // **Where he has moved things on the Library's shelves**: item key to shelf
    // id, only for what he has moved (`shelfOf` files everything else). A
    // page's key is its address; a document's is `doc:` and its name.
    shelf: {},
    // **The icon he has picked for a page or document**: item key (the same
    // keys as `shelf`) to an icon name (`ICON_CHOICES`). Only what he has
    // picked; everything else wears `defaultIcon`.
    icons: {},
    // **The name he gave a page Notion names** (2026-10-10, *"rename document
    // pages on the portal"*): address to name, the portal's own. Notion keeps
    // its title and the refresh keeps writing Notion's name into `sections`;
    // `tidy` lays this one over it every time the card is read, so his name
    // wins without the page leaving Notion's hands. The address stays put.
    labels: {},
    // **Where a renamed page went**: an address it left to the address it is
    // at now (`movePage` in `films.js`), so a link sent before the rename
    // forwards. Pages only; kept to the newest 200.
    moved: {},
    crew: [],
    // **A project that shoots more than once** (SL-1396, 2026-10-02): one
    // entry per row of his Shoots database, oldest first, each with its own
    // dates, crew and spec sheet. `crew` and `camera` above are the lead
    // shoot's (`leadShoot`), so everything that reads them reads the next
    // shoot. Empty for a project that shoots once — every film before this.
    shoots: [],
  };
}

const MAX_SECTIONS = 24;

/** The eight built-in rows plus every page a film may hold, and room to spare. */
const MAX_ORDER = 400;

/** More headings than a sidebar of that length can carry meaning with. */
const MAX_GROUPS = 12;

/**
 * One section: a slug a URL can carry, and a name a person reads.
 *
 * **The slug is checked as hard as a file name.** It becomes an address and a
 * link on the page, and it arrives from whatever he typed into a Notion select,
 * so anything that is not plainly lower-case letters, digits and hyphens is
 * dropped rather than escaped and hoped for.
 *
 * **`by` says which road the page came in on**, and it exists because a card
 * quietly drops any field nobody has taught it about (Ref 721) — so a section
 * written by the MCP would arrive here `mcp` and leave here plain, and the next
 * Notion refresh, seeing nothing to tell it apart, would sweep it off the rail
 * as a section Notion no longer names. `mcp` means an agent made it and only an
 * agent may take it away; anything else came from Notion and Notion owns it.
 */
function section(raw) {
  if (!raw || typeof raw !== "object") return null;
  const slug = String(raw.slug || "");
  const name = words(raw.name, 60);
  if (!name || !/^[a-z0-9][a-z0-9-]{0,80}$/.test(slug)) return null;
  // **A stamp it has not been taught is a stamp it drops**, silently, which is
  // how a deck's page came back saying Notion wrote it. Whoever made a page
  // owns it, so the three kinds have to survive a trip through here.
  const by = raw.by === "mcp" || raw.by === "deck" ? raw.by : "";
  // **Derived unless the card says otherwise.** See `TYPES` above: this is what
  // lets every film that already exists carry both without being rewritten.
  const source = SOURCES.has(raw.source) ? raw.source : sourceFrom(by);
  const type = TYPES.has(raw.type) ? raw.type : typeFrom(slug, by);
  /**
   * **Whether Notion names this page at all**, which decides whether *Live from
   * Notion* is a thing that could happen or a label with nothing behind it.
   *
   * His report, 2026-09-08: *"live from notion and copied from notion still
   * dont do anything."* The Source control offered all three on every page,
   * and on one he made on the portal there is no Hub-ticked Project Docs row
   * carrying that Section name — so two of the three changed a word and
   * nothing else, for ever.
   *
   * **Written by `refresh.py`, which is the only thing that can know it.** The
   * worker has no Notion token; see `design/DECISIONS.md`. Until a refresh has
   * run it is derived, and the derivation is exactly right for every film that
   * exists today: a row with no `by` is on the card *because* Notion named it,
   * and a row an agent or the portal made is not.
   */
  const named = typeof raw.notion === "boolean" ? raw.notion : !by;
  const out = { slug, name, title: words(raw.title, 140), by, type, source, notion: named };
  // **A page that belongs to one shoot** — a Project Docs row tagged to it in
  // Notion. A page written here is matched by its name (`shotView`).
  const shoots = shootSlugs(raw.shoots);
  if (shoots.length) out.shoots = shoots;
  // **Where the hand-made page it was rebuilt from is kept** (`rebuild.js`,
  // Ref 1543): a file beside it in `pages/`, never drawn, never deleted.
  if (/^[a-z0-9][a-z0-9-]{0,80}\.handmade(-[0-9TZ-]{10,30})?\.html$/.test(String(raw.handmade || ""))) out.handmade = raw.handmade;
  // **A page drawn from a Google Doc, and whether it is following it now**
  // (`docfollow.js`; his ask of 2026-10-10, the switch on the page rather than
  // in Projects Console). Halcyon's Outline, from Ivy's doc.
  const follow = followOf(raw.follow);
  if (follow) out.follow = follow;
  // **The Notion page a Live from Notion page is drawn from, and when it last
  // was** (2026-10-17). The clock reads only pages that carry `from`
  // (`followingPages`), so a card saved here must never drop it.
  const from = String(raw.from || "").replace(/-/g, "");
  if (/^[0-9a-f]{32}$/.test(from)) out.from = from;
  if (typeof raw.synced === "string" && Number.isFinite(Date.parse(raw.synced))) out.synced = raw.synced.slice(0, 40);
  // **A board keeps its storage name and who may open it.** The name is where
  // its cards live (`boards/<name>.json`) and is never the slug's to decide: a
  // page removed and made again under the same name must not find the old
  // board waiting. Anything unreadable is the private answer, never the open
  // one — a board that forgets who it is for must forget towards "him alone".
  if (type === "board") {
    const board = String(raw.board || "");
    out.board = /^[a-z0-9][a-z0-9-]{0,80}$/.test(board) ? board : slug;
    out.share = SHARES.includes(raw.share) ? raw.share : "me";
  }
  return out;
}

/**
 * **What outside document a page follows, if any** (2026-10-17, his ask: "an
 * indicator on a page ... that that one's syncing to a document"). A page Live
 * from Notion with its Notion page, or a page following a Google Doc with the
 * switch on. `{ kind, url, title, when }` or null.
 */
export function syncOf(sec) {
  if (!sec || typeof sec !== "object") return null;
  const follow = followOf(sec.follow);
  if (follow) {
    return follow.on ? { kind: "gdoc", url: `https://docs.google.com/document/d/${follow.doc}/edit`, title: "", when: "" } : null;
  }
  const from = String(sec.from || "").replace(/-/g, "");
  if (sec.source === "notion" && sec.notion !== false && /^[0-9a-f]{32}$/.test(from)) {
    return { kind: "notion", url: `https://www.notion.so/${from}`, title: sec.title || sec.name || "", when: sec.synced || "" };
  }
  return null;
}

/** `{ doc, on, credit }`: a Drive file id, the switch, and whose draft it is. */
export function followOf(raw) {
  if (!raw || typeof raw !== "object") return null;
  const doc = String(raw.doc || "");
  if (!/^[A-Za-z0-9_-]{20,100}$/.test(doc)) return null;
  const out = { doc, on: raw.on === true };
  const credit = words(raw.credit, 40);
  if (credit) out.credit = credit;
  return out;
}

function words(value, cap) {
  if (value === null || value === undefined) return "";
  return String(value).replace(/\s+/g, " ").trim().slice(0, cap);
}

/** A camera box as kept on the card. **Every box keeps its lines** — one
 * lens set, one camera's value, one LUT's label per line (src/lenses.js,
 * src/entries.js); each line is one line. The frame rate too, since it
 * became text (2026-10-05). */
function cameraWords(field, value, cap) {
  if (value === null || value === undefined) return "";
  return String(value).split("\n").map((line) => line.replace(/\s+/g, " ").trim()).filter(Boolean).join("\n").slice(0, cap);
}

/**
 * A date, or nothing.
 *
 * Deliberately strict: a shoot date drawn wrong on a page somebody plans around
 * is worse than a shoot date missing. Anything that is not plainly `YYYY-MM-DD`
 * is dropped rather than guessed at.
 */
function day(value) {
  const said = words(value, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(said) ? said : "";
}

function count(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.min(Math.round(number), 1e6) : 0;
}

/**
 * A number of bytes.
 *
 * **Not `count`.** That caps at a million, which is the right ceiling for
 * scenes and the wrong one for a file: an eight-megabyte look book came back
 * from it as 977 KB, on the page, looking entirely plausible.
 */
function size(value) {
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? Math.min(Math.round(number), 1e12) : 0;
}

/**
 * Read a film's card — the words as stored, the film half as the film is now.
 *
 * **Never throws and never refuses.** A film with no card, or a card written by
 * something newer, still has to draw — the page falls back to what the engine
 * and the manifest know, which is what the hub did before any of this existed.
 *
 * **The film half is asked of the film on every look**, since 2026-09-16:
 * credits, ratio, counts, dated days and which pictures stand for the scenes,
 * locations and boards come from `cardOf` — the logs replayed in the worker,
 * cached under their own names and sizes — so a page is never behind the
 * film. What is stored is only what Notion knows, and what an older refresh
 * wrote before this; the stored film half is the fallback when the film has
 * no logs in the bucket yet. Pass `ctx` where there is one so the cache write
 * outlives the response.
 */
export async function frontOf(env, project, ctx) {
  const [stored, card, own, portal] = await Promise.all([
    storedFront(env, project), cardOf(env, project, ctx), ownMark(env, project),
    filmlessPortal(env, project),
  ]);
  // **Stray logs under a portal are not a film** (SL-1376). The engine will
  // happily replay whatever logs it is given, so a portal a chat wrote into
  // had a card with counts and drafts, and everything reading `live` took it
  // for a film. The one rule (`filmlessPortal`) says what it is, and the
  // replay is set aside.
  const live = portal ? null : card;
  let front = live ? withFilm(stored, live) : stored;
  // **Studio reads the card** (studiocards.js, stage 5 step 4 piece A): with
  // its switch on, the record's director, producer and mark are drawn rather
  // than what the film last had copied into it. Off (or no record), as before.
  if (live) {
    const { liveCardFor, layCardOnFront } = await import("./studiocards.js");
    front = tidy(layCardOnFront(front, await liveCardFor(env, project), live));
  }
  // **Whether the counts are the film's own**, so a zero can be believed
  // (`unfilled` in `pages.js`). A card nobody has read the film for carries
  // `emptyFront`'s zeros, which say nothing. Never stored, like `film` below.
  front.live = Boolean(live);
  // **The script's drafts, newest first** (SL-1338) — the film's, never
  // stored: `tidy` does not know the field, so it is read off the film on
  // every look and a new draft is on the Script page with nobody re-pinning.
  front.scripts = live ? scriptsOf(live.scripts) : [];
  // **How many shots hold lines of the screenplay** (Ref 1568): the Script
  // page offers its Marks view only when there are some. Never stored.
  front.play_shots = live ? Math.max(0, Math.min(100000, Math.floor(Number(live.play_shots) || 0))) : 0;
  // **Each scene's section, day and set-aside** (Ref 1408), so the sidebar
  // counts the scenes the Shot List will show (`shotListCount`). Never
  // stored, like `scripts`.
  front.scene_list = live ? sceneListOf(live.scene_list) : null;
  // **Whether the portal can refresh this from Notion itself** (Ref 1155) —
  // true only once he has given it its own connection, the `NOTION_TOKEN`
  // secret. Never stored, like `live`: `tidy` drops it on the way back.
  front.refresh = Boolean(env && typeof env.NOTION_TOKEN === "string" && env.NOTION_TOKEN.trim());
  // **Every page wears the film — his ruling, 2026-09-16.** The card's mark
  // is Notion's, written by a refresh; a film with no Notion row, or one
  // whose colour was picked on the Mac after the last refresh, has none there
  // and used to fall to the portal's blue. The film's own mark stands in
  // wherever the card has none, so nothing under a film is ever the default.
  if (!front.mark.path && own) front.mark = own;
  // **The spec sheet from the project record** (specsheet.js, 2026-10-14):
  // once the switch is on, each shoot's sheet is the record's, laid on here
  // as the labelled lines every reader takes, so the portal is right
  // whichever refresh last wrote the card. Never stored from here.
  try {
    const { withRecordSheets } = await import("./specsheet.js");
    await withRecordSheets(env, project, front);
  } catch {
    // the card's own (Notion's) sheet stands
  }
  // **The pages of a mode that is off** (portalmodes.js, stage 5 step 5):
  // with its switch on, the rail leaves them off as it does a page in the
  // Library; each still opens at its address. Never stored, like `live`.
  try {
    const { modesOffFor } = await import("./portalmodes.js");
    const got = await modesOffFor(env, project, front);
    front.portalmodes = got.on;
    front.modesOff = got.off;
  } catch {
    front.portalmodes = false;
    front.modesOff = [];
  }
  // **A portal with no film behind it says so on the card** — `film: false`
  // — and the rail leaves the film's four screens off (2026-09-16). Never
  // stored: `tidy` does not know the field, so a card written back drops it,
  // and the mark in the bucket stays the one place that says it. The same
  // question the screens' own gate asks (`MODES` in `worker.js`), so the
  // rail never offers a page that answers *No such page*.
  if (portal) return { ...front, film: false };
  return front;
}

/** The scenes as the engine listed them, held to plain words and dates. */
function sceneListOf(raw) {
  return Array.isArray(raw)
    ? raw.slice(0, 2000).map((one) => ({
        section: words(one && one.section, 120),
        day: day(one && one.day),
        archived: Boolean(one && one.archived),
        // The shoot the scene names (step 4 piece D), as stored.
        shoot: one && /^[0-9a-f]{32}$/.test(String(one.shoot || "")) ? String(one.shoot) : "",
      }))
    : null;
}

/**
 * The drafts as the engine listed them, held to the bucket's naming rule: a
 * stem is 32 hex characters or the draft is not one this page can find.
 */
function scriptsOf(raw) {
  // **One file is one draft.** The same PDF taken in twice is two revisions
  // to the film and one script to a reader; the newer stands for both.
  const seen = new Set();
  return (Array.isArray(raw) ? raw : [])
    .filter((one) => one && /^[0-9a-f]{32}$/.test(String(one.stem || "")))
    .filter((one) => !seen.has(one.stem) && seen.add(one.stem))
    .slice(0, 60)
    .map((one) => ({
      stem: String(one.stem),
      name: words(one.name, 120),
      came_from: words(one.came_from, 200),
      dated: words(one.dated, 40),
    }));
}

/**
 * The film's own mark and colour, as the Mac wrote them on the manifest.
 *
 * Held to the same rule as a mark off the card (`tidy`, below): an outline of
 * path characters only, a six-digit colour — or nothing. A manifest older
 * than the mark, or one that cannot be read, is a film with no mark, which is
 * exactly what it was before.
 */
async function ownMark(env, project) {
  const got = await env.BUCKET.get(keys.manifest(project));
  if (!got) return null;
  try {
    const manifest = await got.json();
    const mark = tidy({ mark: { path: manifest.markPath, colour: manifest.markColour } }).mark;
    return mark.path && mark.colour ? mark : null;
  } catch {
    return null;
  }
}

/** The card exactly as the bucket holds it — what a refresh reads back and rewrites. */
export async function storedFront(env, project) {
  const got = await env.BUCKET.get(keys.front(project));
  if (!got) return emptyFront();
  try {
    return tidy(await got.json());
  } catch {
    return emptyFront();
  }
}

/**
 * The stored card with the film's own facts laid over it.
 *
 * Through `tidy` again, so a name the engine hands back is held to the same
 * rule as one a script wrote. `counts.pictures` stays as stored: it is a count
 * of files in the bucket, not of the film, and nothing draws it.
 */
export function withFilm(stored, live) {
  return tidy({
    ...stored,
    director: live.director,
    producer: live.producer,
    ratio: live.ratio,
    counts: { ...stored.counts, ...(live.counts || {}), pictures: stored.counts.pictures },
    days: live.days,
    pictures: live.pictures,
  });
}

/** Everything a stored card may be, and nothing it may not. */
export function tidy(raw) {
  const front = emptyFront();
  if (!raw || typeof raw !== "object") return front;

  for (const [field, cap] of Object.entries(LIMITS)) front[field] = words(raw[field], cap);

  front.updated = words(raw.updated, 40);
  front.linked = raw.linked === "link" || raw.linked === "name" ? raw.linked : "";
  front.ratio = Number.isFinite(Number(raw.ratio)) ? Math.min(Math.max(Number(raw.ratio), 0), 10) : 0;
  front.key_image = FILE_NAME.test(String(raw.key_image || "")) ? String(raw.key_image) : "";

  // **A drawing is not text, and this one is written into the page.** The
  // outline is allowed only the characters SVG path data is made of — the
  // commands, digits, and the separators between them — so nothing that
  // arrives here can close the attribute and start being markup. The colour
  // must be a plain six-digit hex, because it is written into a style.
  const mark = raw.mark && typeof raw.mark === "object" ? raw.mark : {};
  const outline = String(mark.path || "");
  front.mark = {
    path: outline.length <= 4000 && /^[MmLlHhVvCcSsQqTtAaZz0-9eE,.\s+-]*$/.test(outline) ? outline : "",
    colour: /^#[0-9A-Fa-f]{6}$/.test(String(mark.colour || "")) ? String(mark.colour).toUpperCase() : "",
  };

  const shoot = raw.shoot && typeof raw.shoot === "object" ? raw.shoot : {};
  front.shoot = { start: day(shoot.start), end: day(shoot.end) };

  const camera = raw.camera && typeof raw.camera === "object" ? raw.camera : {};
  for (const [field, cap] of Object.entries(CAMERA)) front.camera[field] = cameraWords(field, camera[field], cap);
  front.camera_sheet = PAGE_ID.test(String(raw.camera_sheet || "")) ? String(raw.camera_sheet) : "";

  const counts = raw.counts && typeof raw.counts === "object" ? raw.counts : {};
  for (const key of Object.keys(front.counts)) front.counts[key] = count(counts[key]);

  // **A name that is not a stored file is dropped, not drawn.** These arrive
  // from a script and end up in a `url(...)`, so the same rule the key image
  // has always had applies to every one of them.
  const pictures = raw.pictures && typeof raw.pictures === "object" ? raw.pictures : {};
  for (const group of Object.keys(front.pictures)) {
    front.pictures[group] = (Array.isArray(pictures[group]) ? pictures[group] : [])
      .filter((name) => FILE_NAME.test(String(name || "")))
      .slice(0, MAX_PICTURES[group])
      .map(String);
  }

  front.credits = tidyCredits(raw.credits);

  front.days = (Array.isArray(raw.days) ? raw.days : [])
    .slice(0, MAX_DAYS)
    .map((one) => (one && typeof one === "object" ? { label: words(one.label, 40), date: day(one.date), ...(PAGE_ID.test(String(one.shoot || "")) ? { shoot: String(one.shoot) } : {}) } : null))
    .filter((one) => one && one.date);

  front.documents = (Array.isArray(raw.documents) ? raw.documents : [])
    .slice(0, MAX_DOCUMENTS)
    .map(document)
    .filter(Boolean);

  // **The spec sheet's attachments go through the document rule, not past it.**
  // They arrive from a Notion row like everything else here, so a held file has
  // to be a stored name and a link has to be one the page will put in an href.
  front.camera_files = (Array.isArray(raw.camera_files) ? raw.camera_files : [])
    .slice(0, MAX_CAMERA_FILES)
    .map(document)
    .filter(Boolean);
  front.camera_notes = count(raw.camera_notes);
  // Each spec sheet pill's Notion colour, {prop: {name: colour}} — only
  // Notion's own colour names, so nothing else can reach a class attribute.
  const COLOURS = new Set(["default", "gray", "brown", "orange", "yellow", "green", "blue", "purple", "pink", "red"]);
  front.camera_pills = Object.fromEntries(Object.entries(raw.camera_pills && typeof raw.camera_pills === "object" ? raw.camera_pills : {})
    .slice(0, 20).map(([prop, names]) => [String(prop).slice(0, 60), Object.fromEntries(Object.entries(names && typeof names === "object" ? names : {})
      .slice(0, 400).filter(([, c]) => COLOURS.has(c)).map(([n, c]) => [String(n).slice(0, 100), c]))]));

  const seen = new Set();
  front.sections = (Array.isArray(raw.sections) ? raw.sections : [])
    .slice(0, MAX_SECTIONS)
    .map(section)
    .filter((one) => one && !seen.has(one.slug) && seen.add(one.slug));

  // **The film's categories first, and where he has filed things**: the
  // sidebar's headings are drawn from them, so they are read before the order.
  // **Only a shelf that exists, and only for a key that is short enough to be
  // one** — the same gate every list on the card goes through.
  // **The film's own shelves** (2026-10-10), then where things were moved:
  // kept by id. A move written by name — every card before ids, or a program
  // that says "Look" — is turned into its shelf's id here.
  front.shelves = tidyShelves(raw.shelves);
  front.shelf = {};
  if (raw.shelf && typeof raw.shelf === "object" && !Array.isArray(raw.shelf)) {
    for (const [key, to] of Object.entries(raw.shelf).slice(0, 400)) {
      const id = shelfIdFor(front, to);
      if (id && key.length <= 140 && /^(doc:.+|[a-z0-9][a-z0-9-]{0,80})$/.test(key)) front.shelf[key] = id;
    }
  }

  // **A row is in the order once.** Named twice it would be drawn twice. First
  // mention wins.
  const named = new Set();
  const key = (one) => {
    const said = String(one || "");
    return /^(doc:.{1,140}|[a-z0-9][a-z0-9-]{0,80})$/.test(said) && !named.has(said) && named.add(said) ? said : "";
  };
  if (Array.isArray(raw.rail)) {
    front.rail = raw.rail.map(key).filter(Boolean).slice(0, MAX_ORDER);
  } else {
    // **A card from before the headings were the categories** carried
    // `groups` (his own headings and their rows), or before that a flat
    // `order`. Each named heading becomes a category of the same name — the
    // one already called that, or a new one — and every row under it is filed
    // there, so the sidebar reads as it did. The heading wins over an older
    // Library move: it is what readers saw. Rows under no heading keep the
    // category they were filed in. The order is every row, in the order the
    // groups listed them.
    const legacy = Array.isArray(raw.groups) ? raw.groups : [{ name: "", rows: Array.isArray(raw.order) ? raw.order : [] }];
    front.rail = [];
    const was = front.updated;
    for (const one of legacy.slice(0, MAX_GROUPS)) {
      if (!one || typeof one !== "object") continue;
      const heading = words(one.name, 40);
      let id = heading ? shelfIdFor(front, heading) : "";
      if (heading && !id) id = editShelves(front, { action: "add", name: heading }).id || "";
      for (const row of (Array.isArray(one.rows) ? one.rows : []).map(key).filter(Boolean)) {
        if (front.rail.length < MAX_ORDER) front.rail.push(row);
        if (id) front.shelf[row] = id;
      }
    }
    front.updated = was;
  }

  // **Off the sidebar is a list of addresses and the name of the heading each
  // sat under.** The same gate a group's rows go through: a slug or nothing,
  // once each — and a page is in one list, not both (archived wins).
  const gone = new Set();
  const offList = (list) => (Array.isArray(list) ? list : [])
    .map((one) => {
      if (!one || typeof one !== "object") return null;
      const out = { at: String(one.at || ""), head: words(one.head, 40) };
      // What an archived page was before, so Unarchive can put it back.
      if (typeof one.wasPinned === "boolean") out.wasPinned = one.wasPinned;
      if (typeof one.wasPrivate === "boolean") out.wasPrivate = one.wasPrivate;
      if (SHARES.includes(one.wasShare)) out.wasShare = one.wasShare;
      return out;
    })
    // A document is archived by its name, `doc:` in front, like its shelf key.
    .filter((one) => one && /^(doc:.{1,140}|[a-z0-9][a-z0-9-]{0,80})$/.test(one.at) && !gone.has(one.at) && gone.add(one.at))
    .slice(0, MAX_ORDER);
  front.archive = offList(raw.archive);
  front.library = offList(raw.library);
  front.docPins = offList(raw.docPins).filter((one) => one.at.startsWith("doc:"));
  front.icons = {};
  if (raw.icons && typeof raw.icons === "object" && !Array.isArray(raw.icons)) {
    for (const [key, name] of Object.entries(raw.icons).slice(0, 400)) {
      if (ICON_CHOICES.includes(name) && key.length <= 140 && /^(doc:.+|[a-z0-9][a-z0-9-]{0,80})$/.test(key)) front.icons[key] = name;
    }
  }

  front.labels = {};
  if (raw.labels && typeof raw.labels === "object" && !Array.isArray(raw.labels)) {
    for (const [at, called] of Object.entries(raw.labels).slice(0, 200)) {
      const name = words(called, 60);
      if (name && /^[a-z0-9][a-z0-9-]{0,80}$/.test(at)) front.labels[at] = name;
    }
  }
  for (const one of front.sections) if (one.notion && front.labels[one.slug]) one.name = front.labels[one.slug];

  front.moved = {};
  if (raw.moved && typeof raw.moved === "object" && !Array.isArray(raw.moved)) {
    const address = /^[a-z0-9][a-z0-9-]{0,80}$/;
    for (const [was, now] of Object.entries(raw.moved).slice(-200)) {
      if (address.test(was) && address.test(String(now)) && was !== now) front.moved[was] = String(now);
    }
  }

  front.crew = (Array.isArray(raw.crew) ? raw.crew : []).slice(0, MAX_CREW).map(person).filter(Boolean);

  const slugs = new Set();
  front.shoots = (Array.isArray(raw.shoots) ? raw.shoots : [])
    .slice(0, MAX_SHOOTS)
    .map(shootOf)
    .filter((one) => one && !slugs.has(one.slug) && slugs.add(one.slug));

  return front;
}

// **Many shoots** (Ref 1413): a series shoots for a year. Each carries its
// crew, so this is what keeps the card well inside `MAX_FRONT`.
const MAX_SHOOTS = 40;
const PAGE_ID = /^[0-9a-f]{32}$/;

/**
 * One shoot of a project that shoots more than once — written by
 * `refresh.py` (`shoots_on_card`) off his Shoots database.
 */
function shootOf(raw) {
  if (!raw || typeof raw !== "object") return null;
  const name = words(raw.name, 60);
  const slug = String(raw.slug || "");
  if (!name || !/^[a-z0-9][a-z0-9-]{0,40}$/.test(slug)) return null;
  const camera = raw.camera && typeof raw.camera === "object" ? raw.camera : {};
  return {
    // bare (no dashes, lowercase), as a scene or day names it (piece D)
    id: PAGE_ID.test(String(raw.id || "").replace(/-/g, "").toLowerCase()) ? String(raw.id).replace(/-/g, "").toLowerCase() : "",
    name,
    // the number's words when he named the shoot ("Shoot 2"), else its name —
    // `shootParts` in notion.js
    base: words(raw.base, 60) || name,
    slug,
    status: raw.status === "Wrapped" || raw.status === "Upcoming" ? raw.status : "",
    start: day(raw.start),
    end: day(raw.end),
    changes: words(raw.changes, 600),
    sections: (Array.isArray(raw.sections) ? raw.sections : []).slice(0, 24).map((one) => words(one, 120)).filter(Boolean),
    sheet: PAGE_ID.test(String(raw.sheet || "")) ? String(raw.sheet) : "",
    // When Notion last changed the sheet, so a refresh reads it again only
    // when it has changed (Ref 1413: many shoots, most of them wrapped).
    sheet_edited: words(raw.sheet_edited, 40),
    camera: Object.fromEntries(Object.entries(CAMERA).map(([field, cap]) => [field, cameraWords(field, camera[field], cap)])),
    camera_files: (Array.isArray(raw.camera_files) ? raw.camera_files : []).slice(0, MAX_CAMERA_FILES).map(document).filter(Boolean),
    camera_notes: count(raw.camera_notes),
    crew: (Array.isArray(raw.crew) ? raw.crew : []).slice(0, MAX_CREW).map(person).filter(Boolean),
  };
}

/**
 * **The shoot the portal leads with**: the earliest Upcoming one, or the last
 * once every shoot has wrapped. `lead_of` in `refresh.py` is the same rule —
 * change one, change both. Null for a project that shoots once.
 */
export function leadShoot(front) {
  const shoots = (front && front.shoots) || [];
  if (!shoots.length) return null;
  return shoots.find((one) => one.status === "Upcoming") || shoots[shoots.length - 1];
}

/**
 * **Everybody on the film, across its shoots, once each** — Visibility's
 * list, Ref 1410. Since the shoot tabs the card's `crew` is the next shoot's,
 * so someone only on Shoot 1 had no switch. Hiding is by name, so a person
 * on two shoots is one switch; `shoots` says which they are on. A film with
 * no shoots gets its crew as before.
 */
export function everyone(front) {
  const out = new Map();
  const add = (one, shoot) => {
    if (!one || !one.name) return;
    const had = out.get(one.name) || { ...one, shoots: [] };
    if (shoot && !had.shoots.includes(shoot)) had.shoots.push(shoot);
    out.set(one.name, had);
  };
  for (const shoot of (front && front.shoots) || []) for (const one of shoot.crew || []) add(one, shoot.name);
  for (const one of (front && front.crew) || []) add(one, "");
  return [...out.values()];
}

/** The shoot slug an address carries — `/f/<film>/shoots/<slug>` — or "". */
export function shootIn(base) {
  const said = /\/shoots\/([a-z0-9][a-z0-9-]{0,40})$/.exec(String(base || ""));
  return said ? said[1] : "";
}

/** The film's own address, without a shoot on it. */
export function filmBase(base) {
  return String(base || "").replace(/\/shoots\/[a-z0-9][a-z0-9-]{0,40}$/, "");
}

const loose = (words) => String(words || "").toLowerCase().replace(/[—–-]/g, " ").replace(/\s+/g, " ").trim();

/** Whether a page's name is a shoot's own: `Shoot 2 Details` is Shoot 2's. */
function namesShoot(page, shoot) {
  const a = loose(page), b = loose(shoot);
  return Boolean(b) && (a === b || a.startsWith(`${b} `));
}

/** Whether a date falls on one of a shoot's days. */
function onShoot(shoot, date) {
  return Boolean(date && shoot.start && date >= shoot.start && date <= (shoot.end || shoot.start));
}

/**
 * **Shoot fields** (stage 5 step 4 piece D): once a film's scenes or days
 * name their shoot (Studio's picker, Move to Shoot, the converter), that is
 * the rule, the same one Studio's engine uses (`Doc::scene_shoot`,
 * `Doc::day_shoot` in `engine/src/shoots.rs`), and every scene belongs to
 * exactly one shoot. A film with no shoot fields keeps the section/date
 * rule. `public/film.js` has the same three (`byFields`, `dayShootOf`,
 * `sceneShootOf`); change one, change both.
 */
export function byFields(tabs, scenes, days) {
  const ids = new Set((tabs || []).map((one) => one.id).filter(Boolean));
  if ((tabs || []).length < 2 || !ids.size) return false;
  return (scenes || []).some((one) => one && ids.has(one.shoot)) || (days || []).some((one) => one && ids.has(one.shoot));
}
/** A day's shoot (slug): its own, else the one its date falls in, else the last that began before it, else the first. */
export function dayShootOf(tabs, dayRow) {
  const own = dayRow && dayRow.shoot && tabs.find((one) => one.id === dayRow.shoot);
  if (own) return own.slug;
  const date = dayRow && dayRow.date;
  const covering = date && tabs.find((one) => onShoot(one, date));
  if (covering) return covering.slug;
  const before = date ? tabs.filter((one) => one.start && one.start <= date).sort((a, b) => (a.start < b.start ? -1 : 1)).pop() : null;
  return (before || tabs[0]).slug;
}
/** A scene's shoot (slug): its own, else its one day's, else the first. */
export function sceneShootOf(tabs, scene, dayRow) {
  const own = scene && scene.shoot && tabs.find((one) => one.id === scene.shoot);
  if (own) return own.slug;
  if (dayRow) return dayShootOf(tabs, dayRow);
  return tabs[0].slug;
}

/** The shoots a page belongs to: its Notion tag, or else its name. */
export function pageShoots(section, shoots) {
  if (section.shoots && section.shoots.length) return section.shoots;
  return shoots.filter((one) => namesShoot(section.name, one.base || one.name) || namesShoot(section.name, one.name)).map((one) => one.slug);
}

/**
 * **A film's card as one of its shoots sees it** — SL-1396, his design of
 * 2026-10-02: *"a sub tab for 'shoot 1' 'shoot 2' and it swaps out
 * information depending on what's different so you can always refer back to
 * the old one."*
 *
 * Swapped: People (the shoot's crew), the spec sheet, the documents tagged
 * to it, the days that fall on it, and its own pages (`Shoot 2 Details`).
 * Anything that belongs to no shoot is the same on every tab — his rule, an
 * empty Shoot means the whole project. `was` is the shoot before, so the
 * pages can mark what changed rather than anybody writing it down.
 *
 * **For drawing only.** A card written back must be the stored one; this is
 * a copy with one shoot's things laid over it. A film with no shoots comes
 * back untouched.
 */
/**
 * **How many scenes the Shot List will show** — the sidebar's number, Ref
 * 1408. The program counts in the browser (`railGroups` in `public/film.js`):
 * scenes not set aside, and on a shoot's tab only that shoot's. This is that
 * rule, so the number does not change crossing into the Shot List. A scene
 * is a shoot's through its section, else its one day; one no shoot claims is
 * on every tab; a wrapped shoot's tab keeps its archived scenes, its record.
 * Change one, change both (`shootsOfScene`, `inShoot`, `setAside`).
 */
export function shotListCount(front) {
  const list = front && front.scene_list;
  if (!Array.isArray(list)) return (front && front.counts && front.counts.scenes) || 0;
  const tabs = (front.shoots || []);
  const on = front.shootOn ? tabs.find((one) => one.slug === front.shootOn.slug) : null;
  const fields = byFields(tabs, list, front.days);
  const of = (scene) => {
    if (fields) return [sceneShootOf(tabs, scene, scene.day ? ((front.days || []).find((d) => d.date === scene.day) || { date: scene.day }) : null)];
    const named = loose(scene.section);
    let claimed = named ? tabs.filter((one) => (one.sections || []).some((n) => loose(n) === named)) : [];
    if (!claimed.length && scene.day) claimed = tabs.filter((one) => onShoot(one, scene.day));
    return claimed.length ? claimed.map((one) => one.slug) : null;
  };
  return list.filter((scene) => {
    const mine = on ? of(scene) : null;
    if (on && mine && !mine.includes(on.slug)) return false;
    if (!scene.archived) return true;
    return Boolean(on && on.status === "Wrapped" && mine && mine.includes(on.slug));
  }).length;
}

export function shotView(front, asked = "") {
  const shoots = (front && front.shoots) || [];
  // **One shoot is no shoots** — his ruling, 2026-10-02: *"if a project only
  // has one shoot these features are ignored."* No switcher, no narrowing.
  if (shoots.length < 2) return front;
  const lead = leadShoot(front);
  const pagesOf = () => Object.fromEntries(shoots.map((one) => [one.slug,
    (front.sections || []).filter((sec) => pageShoots(sec, shoots).includes(one.slug)).map((sec) => sec.slug)]));
  // **All Shoots** (portalmodes.js, stage 5 step 5): the one shoot picker's
  // first row, at its own address beside each shoot's. Nothing narrowed —
  // the card as it is. Only with the portal's switch on; a shoot that is
  // really called that keeps its address, and with the switch off the
  // address is the lead shoot's, as any address it does not know.
  if (asked === "all-shoots" && front.portalmodes && !shoots.some((one) => one.slug === asked)) {
    return { ...front, shootOn: { slug: asked, all: true, name: "All Shoots", base: "", status: "", start: "", end: "", lead: false, changes: "" }, shootPages: pagesOf() };
  }
  const on = shoots.find((one) => one.slug === asked) || lead;
  const at = shoots.indexOf(on);
  const before = at > 0 ? shoots[at - 1] : null;
  const ours = (list) => !list.length || list.includes(on.slug);
  const days = byFields(shoots, front.scene_list, front.days)
    ? (front.days || []).filter((d) => dayShootOf(shoots, d) === on.slug)
    : (front.days || []).filter((d) => onShoot(on, d.date) || !shoots.some((one) => onShoot(one, d.date)));
  const view = {
    ...front,
    shootOn: { slug: on.slug, name: on.name, base: on.base || on.name, status: on.status, start: on.start, end: on.end, lead: on === lead, changes: on.changes },
    shoot: { start: on.start, end: on.end },
    documents: (front.documents || []).filter((doc) => ours(doc.shoots || [])),
    sections: (front.sections || []).filter((one) => ours(pageShoots(one, shoots))),
    days,
    counts: { ...front.counts, days: days.length },
    // Each shoot's own pages, so a switch made on `Shoot 2 Details` lands on
    // the other shoot's details rather than on a page it does not have.
    shootPages: Object.fromEntries(shoots.map((one) => [one.slug,
      (front.sections || []).filter((sec) => pageShoots(sec, shoots).includes(one.slug)).map((sec) => sec.slug)])),
  };
  // **The lead's are the card's own** — `refresh.py` writes the next shoot's
  // crew and sheet at the top, with its files and notes.
  if (on !== lead) {
    view.camera = on.camera;
    view.camera_files = on.camera_files;
    view.camera_notes = on.camera_notes;
    view.camera_page = `camera-sheet-${on.slug}`;
    view.crew = on.crew;
  } else if (on.crew.length) {
    view.crew = on.crew;
  }
  if (before) view.was = { name: before.name, camera: before.camera, crew: before.crew };
  return view;
}

/**
 * One document: a file we hold, or a link somewhere else.
 *
 * **A link is not second best.** Most of what he wants pinned already lives in
 * Google Drive or Notion, and copying it here would make a second copy that can
 * go stale. A file is for the things a collaborator must be able to open
 * without an account anywhere — the look book, mainly.
 */
function document(raw) {
  if (!raw || typeof raw !== "object") return null;
  const name = words(raw.name, 140);
  if (!name) return null;
  const file = FILE_NAME.test(String(raw.file || "")) ? String(raw.file) : "";
  const url = safeUrl(raw.url);
  if (!file && !url) return null;
  const drive = raw.source === "drive" && /^[A-Za-z0-9_-]{10,160}$/.test(String(raw.drive || "")) ? String(raw.drive) : "";
  return {
    name,
    // **`kind` is not `type`.** This one has always meant the flavour of the
    // file — a look book against an ordinary document — and it keeps that job.
    // `type` and `source` above are the two questions a *rail row* answers.
    kind: KINDS.has(raw.kind) ? raw.kind : "document",
    file,
    url: file ? "" : url,
    bytes: size(raw.bytes),
    note: words(raw.note, 200),
    // **The name Notion gives it, when the portal wears another.** A renamed
    // Notion document is still Notion's; the refresh finds it again by this.
    was: words(raw.was, 140),
    // **Derived from what it carries, which is already the rule.** `both_kinds`
    // in `refresh.py` tells the two apart exactly this way: a document with a
    // `file` was uploaded here and only an agent may remove it; one with a
    // `url` came from Notion and is replaced by whatever Notion says now. So
    // this names a rule that already governs the data rather than adding one.
    source: drive ? "drive" : SOURCES.has(raw.source) ? raw.source : (file ? "here" : "notion"),
    // **Which shoots it belongs to**, by slug — empty for the whole project
    // (his rule, 2026-10-02). A call sheet is one shoot's; a deck is every
    // shoot's.
    shoots: shootSlugs(raw.shoots),
    // **A Drive file he switched on in Projects Console** (portaldocs.js,
    // 2026-10-17): the record's `portal_docs`, opened through `/drive/<id>`.
    ...(drive ? {
      drive,
      mime: words(raw.mime, 120),
      modified: /^\d{4}-\d\d-\d\dT[\d:.]+Z?$/.test(String(raw.modified || "")) ? String(raw.modified) : "",
      type: words(raw.type, 12),
      group: DOC_GROUPS.includes(raw.group) ? raw.group : "Other",
    } : {}),
  };
}
const DOC_GROUPS = ["Schedule & Call Sheets", "Script", "Creative", "Other"];

/** A list of shoot slugs, as `document` and `section` carry them. */
function shootSlugs(raw) {
  return (Array.isArray(raw) ? raw : []).map(String).filter((one) => /^[a-z0-9][a-z0-9-]{0,40}$/.test(one)).slice(0, 12);
}

/**
 * A link the page will actually put in an `href`.
 *
 * **`http` and `https` only.** A card is written by an agent reading somebody
 * else's page, so a `javascript:` or `data:` address arriving in it is not a
 * far-fetched thing to guard against — it is the ordinary shape of the attack.
 */
function safeUrl(value) {
  const said = words(value, 1200);
  if (!said) return "";
  try {
    const url = new URL(said);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : "";
  } catch {
    return "";
  }
}

function person(raw) {
  if (!raw || typeof raw !== "object") return null;
  const name = words(raw.name, 120);
  if (!name) return null;
  return {
    name,
    role: words(raw.role, 120),
    department: words(raw.department, 60),
    company: words(raw.company, 120),
    email: words(raw.email, 200),
    phone: words(raw.phone, 60),
    note: words(raw.note, 200),
  };
}

/**
 * Write a film's card.
 *
 * No compare-and-set here, unlike the list of people: a card is derived, so two
 * writers racing lose nothing that cannot be made again by asking for it again.
 * The list of people is the opposite — it is the only copy — which is why that
 * one takes an etag and this one does not.
 */
export async function saveFront(env, project, front) {
  const body = JSON.stringify({ ...tidy(front), version: 1 });
  if (body.length > MAX_FRONT) throw new Error("That card is too big.");
  await env.BUCKET.put(keys.front(project), body, {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
}

/**
 * **The Library's shelves**, in the order a film person reads a project: what
 * is being made, how it looks, how it is shot, when and where, who, and the
 * paper. These seven are every film's to start with; since 2026-10-10 (*"the
 * categories should be renamable, and I should be able to add new ones"*)
 * each film keeps its own list on the card (`front.shelves`, `{id, name}`).
 *
 * **A shelf is its id; its name is only what it says.** Filing (`SHELF_BUILT`,
 * `SHELF_WORDS`) and his moves (`front.shelf`) point at ids, so renaming Look
 * keeps everything on it, and the iPhone's Look tab (id `look`) still finds
 * it. The seven may be renamed and reordered, never removed; one he adds may
 * be removed, and what stood on it goes back where it would be filed anyway.
 */
export const SHELF_DEFAULTS = Object.freeze([
  { id: "creative", name: "Creative" },
  { id: "technical", name: "Technical" },
  { id: "logistical", name: "Logistical" },
  { id: "other", name: "Other" },
].map((one) => Object.freeze(one)));
/**
 * **The seven this list replaced** (his ruling, 2026-10-11: *"Creative /
 * Technical / Logistical should be the starting"*, then *"Other"*): each old
 * id and where it went. A film that still keeps the old list reads as the new
 * one, its categories of his own kept, and a move he made to an old shelf
 * lands on the new.
 */
const LEGACY_NAMES = Object.freeze({
  "script & shots": "script", look: "look", camera: "camera", "schedule & locations": "schedule",
  people: "people", paperwork: "paperwork", notes: "notes",
});
export const LEGACY_SHELVES = Object.freeze({
  script: "creative", look: "creative", notes: "other",
  camera: "technical",
  schedule: "logistical", people: "logistical", paperwork: "logistical",
});
/** The starting names, for anything that still wants the fixed list. */
export const SHELVES = SHELF_DEFAULTS.map((one) => one.name);
const SHELF_DEFAULT_IDS = new Set(SHELF_DEFAULTS.map((one) => one.id));
/** Names a shelf may not take: the Library's own chips and folders. */
const SHELF_RESERVED = new Set(["all", "archive", "recently opened"]);
const SHELF_ID = /^[a-z][a-z0-9-]{0,40}$/;
const MAX_SHELVES = 30;

/** A card's shelves as kept: every default id there, names unique, at most thirty. */
function tidyShelves(raw) {
  if (!Array.isArray(raw) || !raw.length) return SHELF_DEFAULTS.map((one) => ({ ...one }));
  raw = upgradeShelves(raw);
  const ids = new Set();
  const names = new Set();
  const out = [];
  for (const one of raw.slice(0, MAX_SHELVES + 10)) {
    if (!one || typeof one !== "object") continue;
    const id = String(one.id || "");
    if (!SHELF_ID.test(id) || ids.has(id)) continue;
    const fallback = (SHELF_DEFAULTS.find((d) => d.id === id) || {}).name || "";
    let name = words(one.name, 40) || fallback;
    if (!name || names.has(name.toLowerCase()) || SHELF_RESERVED.has(name.toLowerCase())) name = fallback;
    if (!name || names.has(name.toLowerCase())) continue;
    ids.add(id); names.add(name.toLowerCase());
    out.push({ id, name });
  }
  // A default that went missing comes back, last, under its own name (or its id's, if that is taken).
  for (const d of SHELF_DEFAULTS) {
    if (ids.has(d.id)) continue;
    const name = names.has(d.name.toLowerCase()) ? `${d.name} (${d.id})` : d.name;
    ids.add(d.id); names.add(name.toLowerCase());
    out.push({ id: d.id, name });
  }
  return out.slice(0, Math.max(MAX_SHELVES, SHELF_DEFAULTS.length));
}

/** A list that still holds the old seven becomes the new four, then his own. */
function upgradeShelves(list) {
  if (!list.some((one) => one && LEGACY_SHELVES[one.id])) return list;
  const own = list.filter((one) => one && !LEGACY_SHELVES[one.id] && !SHELF_DEFAULT_IDS.has(one.id));
  return [...SHELF_DEFAULTS.map((one) => ({ ...one })), ...own];
}

/** The film's shelves, in its order: `[{id, name}]`. */
export function shelvesOf(front) {
  const kept = front && Array.isArray(front.shelves) && front.shelves.length ? front.shelves : SHELF_DEFAULTS;
  return upgradeShelves(kept).map((one) => ({ id: one.id, name: one.name }));
}

/** The film's shelves for anything that lists them: each with `builtIn` (one of the seven, which cannot be removed). */
export function shelfList(front) {
  return shelvesOf(front).map((one) => ({ ...one, builtIn: SHELF_DEFAULT_IDS.has(one.id) }));
}

/** The film's shelf names, in order. */
export function shelfNames(front) {
  return shelvesOf(front).map((one) => one.name);
}

/**
 * **Which shelf he means**, by its id or by what it is called — its name now,
 * or one of the seven's starting names (so a program that still says "Look"
 * after he renamed it finds it). "" when none.
 */
export function shelfIdFor(front, said) {
  let text = String(said || "").trim();
  if (!text) return "";
  const list = shelvesOf(front);
  // A move he made to one of the old seven lands on where it went.
  if (!list.some((one) => one.id === text || one.name === text)) {
    const old = LEGACY_SHELVES[text] || LEGACY_SHELVES[LEGACY_NAMES[text.toLowerCase()]];
    if (old) text = old;
  }
  const exact = list.find((one) => one.name === text);
  if (exact) return exact.id;
  if (list.some((one) => one.id === text)) return text;
  const low = text.toLowerCase();
  const named = list.find((one) => one.name.toLowerCase() === low);
  if (named) return named.id;
  const was = SHELF_DEFAULTS.find((one) => one.name.toLowerCase() === low);
  return was && list.some((one) => one.id === was.id) ? was.id : "";
}

/** A shelf's name from its id ("" when the film has no such shelf). */
export function shelfName(front, id) {
  return (shelvesOf(front).find((one) => one.id === id) || {}).name || "";
}

// What a thing is called says what it is, in the order that settles ties:
// "Deal memo" is paper before it is anything, "Lighting Plan" is camera
// department, "Call Sheet Day 1" is the schedule.
const SHELF_WORDS = [
  ["logistical", /contract|deal|insurance|budget|invoice|agreement|clearance|w-?9|nda\b|policy|safety|waiver|rider|deliverable|license|licence|permit|release form|\bcrew\b|\bcast\b|contact|release|people|talent|actor|director|producer|schedule|call sheet|callsheet|location|scout|calendar|logistics|map\b|travel|parking|hotel|day \d/],
  ["technical", /camera|lens|lut\b|cdl|gear|spec|rig\b|grip|lighting|light plan|g&e|equipment|exposure|codec|diagram|overhead/],
  ["creative", /script|shot ?list|scene|breakdown|beat|storyboard|look|bible|reference|mood|palette|colou?r|treatment|pitch|lookbook|deck|moodboard|inspiration|style/],
];
const SHELF_BUILT = {
  script: "creative", shotlist: "creative", bible: "creative", boards: "creative",
  diagrams: "technical", camera: "technical",
  schedule: "logistical", locations: "logistical", people: "logistical", documents: "logistical",
};

/**
 * **Which shelf an item stands on, by id.** What he moved it to wins (while
 * that shelf is still there); otherwise the film's own pages know theirs,
 * decks and boards are Look, and anything else is filed by its name. A page
 * nothing recognises goes to Notes and a document to Paperwork.
 */
export function shelfIdOf(front, key, name, kind, type = "") {
  const moved = (front.shelf || {})[key];
  if (moved) {
    const id = shelfIdFor(front, moved);
    if (id) return id;
  }
  if (kind === "page" && SHELF_BUILT[key]) return SHELF_BUILT[key];
  if (type === "deck" || type === "board") return "creative";
  const said = String(name || "").toLowerCase();
  for (const [shelf, words] of SHELF_WORDS) if (words.test(said)) return shelf;
  // **A link is also filed by where it goes**, when its name says nothing: a
  // video site is Creative, a booking or a map is Logistical.
  if (kind === "doc") {
    const doc = (front.documents || []).find((d) => d && `doc:${d.name}` === key);
    const host = doc && doc.url ? hostFiling(doc.url) : "";
    if (host) return host;
  }
  return "other";
}

const HOST_SHELVES = [
  ["creative", /(^|\.)(youtube\.com|youtu\.be|vimeo\.com|livid\.com|frame\.io|louper\.io|pinterest\.com|instagram\.com|behance\.net|savee\.it|are\.na|scenario\.film)$/],
  ["logistical", /(^|\.)(airbnb\.com|vrbo\.com|booking\.com|maps\.google\.com|maps\.apple\.com|maps\.app\.goo\.gl|calendar\.google\.com|flightaware\.com|eventbrite\.com|weather\.com)$/],
];

/** The shelf a link's address suggests, "" when it suggests none. */
function hostFiling(url) {
  let host = "";
  try { host = new URL(url).hostname.toLowerCase(); } catch { return ""; }
  const hit = HOST_SHELVES.find(([, words]) => words.test(host));
  return hit ? hit[0] : "";
}

/** **Which shelf an item stands on**, by the name it shows (`shelfIdOf`). */
export function shelfOf(front, key, name, kind, type = "") {
  return shelfName(front, shelfIdOf(front, key, name, kind, type));
}

/** Give a page or document an icon of his own; an empty name goes back to the default. */
export function setIcon(front, key, name) {
  const next = { ...(front.icons || {}) };
  if (name && ICON_CHOICES.includes(name)) next[key] = name; else delete next[key];
  front.icons = next;
}

/**
 * Move an item to a shelf, named by its id or its name. Moving it to where it
 * would be filed anyway forgets the move. Answers whether the shelf exists
 * (nothing changes when it does not).
 */
export function setShelf(front, key, to, name, kind, type = "") {
  const id = shelfIdFor(front, to);
  if (!id) return false;
  const next = { ...(front.shelf || {}) };
  delete next[key];
  const filed = shelfIdOf({ ...front, shelf: next }, key, name, kind, type);
  if (id !== filed) next[key] = id;
  front.shelf = next;
  return true;
}

/**
 * **Change the film's shelves** — his ask, 2026-10-10. One of:
 *
 * - `{ action: "add", name }` — a new shelf, last; answers its `id`
 * - `{ action: "rename", shelf, name }` — everything on it stays on it
 * - `{ action: "remove", shelf }` — one he added, never one of the seven;
 *   what stood on it goes back to where it would be filed anyway
 * - `{ action: "move", shelf, to }` — `to` is `"up"`, `"down"` or a place (0 first)
 * - `{ action: "order", ids }` — the whole order; any left out keep theirs, after
 *
 * `shelf` is an id or a name. Changes `front` in place; answers
 * `{ ok, why?, id? }` — `why` is a sentence for him when it is refused.
 */
export function editShelves(front, ask) {
  const list = shelvesOf(front);
  const action = String((ask && ask.action) || "");
  const no = (why) => ({ ok: false, why });
  const nameOk = (raw, except = "") => {
    const name = words(raw, 40);
    if (!name) return { why: "Give it a name." };
    if (SHELF_RESERVED.has(name.toLowerCase())) return { why: `${name} is a name the Library uses already.` };
    if (list.some((one) => one.id !== except && one.name.toLowerCase() === name.toLowerCase())) return { why: `There is already a ${name} category.` };
    return { name };
  };
  const done = (next, id) => {
    front.shelves = next;
    front.updated = new Date().toISOString();
    return { ok: true, ...(id ? { id } : {}) };
  };
  if (action === "add") {
    if (list.length >= MAX_SHELVES) return no(`A Library holds at most ${MAX_SHELVES} categories.`);
    const { name, why } = nameOk(ask.name);
    if (why) return no(why);
    const stem = `x-${name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 30) || "shelf"}`;
    let id = stem;
    for (let n = 2; list.some((one) => one.id === id); n += 1) id = `${stem}-${n}`;
    return done([...list, { id, name }], id);
  }
  const id = action === "order" ? "" : shelfIdFor(front, ask && ask.shelf);
  if (action !== "order" && !id) return no("Category not found");
  if (action === "rename") {
    const { name, why } = nameOk(ask.name, id);
    if (why) return no(why);
    return done(list.map((one) => (one.id === id ? { id, name } : one)), id);
  }
  if (action === "remove") {
    if (SHELF_DEFAULT_IDS.has(id)) return no("Starting categories can't be removed");
    const next = { ...(front.shelf || {}) };
    for (const [key, to] of Object.entries(next)) if (to === id) delete next[key];
    front.shelf = next;
    return done(list.filter((one) => one.id !== id), id);
  }
  if (action === "move") {
    const at = list.findIndex((one) => one.id === id);
    const to = ask.to === "up" ? at - 1 : ask.to === "down" ? at + 1 : Number(ask.to);
    if (!Number.isInteger(to)) return no("Category not found");
    const place = Math.max(0, Math.min(list.length - 1, to));
    const next = list.filter((one) => one.id !== id);
    next.splice(place, 0, list[at]);
    return done(next, id);
  }
  if (action === "order") {
    const want = (Array.isArray(ask.ids) ? ask.ids : []).map((one) => shelfIdFor(front, one)).filter(Boolean);
    const seen = new Set();
    const first = want.filter((one) => !seen.has(one) && seen.add(one)).map((one) => list.find((x) => x.id === one));
    return done([...first, ...list.filter((one) => !seen.has(one.id))]);
  }
  return no("Category not found");
}

/** Whether a page is off the sidebar — taken off, or archived. Still at its address. */
export function offSidebar(front, at) {
  if (String(at).startsWith("doc:")) {
    return !(front.docPins || []).some((one) => one.at === at) || (front.archive || []).some((one) => one.at === at);
  }
  return (front.library || []).some((one) => one.at === at) || (front.archive || []).some((one) => one.at === at);
}

/** Whether a page is in the Archive. */
export function isArchived(front, at) {
  return (front.archive || []).some((one) => one.at === at);
}

/**
 * **Put a page on the sidebar, or take it off.** The page keeps its place in
 * `rail`, so coming back is the same spot. Returns whether anything changed.
 */
export function setOnSidebar(front, at, on) {
  if (String(at).startsWith("doc:")) {
    const kept = (front.docPins || []).filter((one) => one.at !== at);
    const was = kept.length !== (front.docPins || []).length;
    if (on) kept.push({ at, head: "" });
    front.docPins = kept;
    return on ? !was : was;
  }
  const list = (front.library || []).filter((one) => one.at !== at);
  const was = list.length !== (front.library || []).length;
  if (!on) list.push({ at, head: "" });
  front.library = list;
  return on ? was : !was;
}

/**
 * **Archive a page, or take it out.** Archiving unpins it, makes it private
 * and files it in the Library's Archive; taking it out puts back exactly what
 * it was (`wasPinned`, `wasPrivate`, and for a board `wasShare`), in the
 * place it sat. `visible` is the film's Visibility lists, changed in
 * place for the caller to save; without it only the front card changes.
 * Returns whether anything changed.
 *
 * An entry archived before these were kept has no memory: it comes back
 * pinned, and its privacy is left as it stands.
 */
export function setArchived(front, at, archived, visible = null) {
  // **A document is archived by `doc:` and its name**, and its privacy lives
  // in Visibility's `documents`, not `sections`.
  const doc = at.startsWith("doc:") ? at.slice(4) : "";
  const listKey = doc ? "documents" : "sections";
  const listItem = doc || at;
  const sec = doc ? null : (front.sections || []).find((one) => one.slug === at);
  const board = Boolean(sec && sec.type === "board");
  const mine = (front.archive || []).find((one) => one.at === at);
  if (archived) {
    if (mine) return false;
    const wasPinned = doc ? (front.docPins || []).some((one) => one.at === at) : !(front.library || []).some((one) => one.at === at);
    const entry = { at, head: "", wasPinned };
    if (visible) {
      if (board) { entry.wasPrivate = sec.share !== "link"; entry.wasShare = sec.share; sec.share = "me"; }
      else {
        entry.wasPrivate = (visible[listKey] || []).includes(listItem);
        if (!entry.wasPrivate) visible[listKey] = [...(visible[listKey] || []), listItem];
      }
    }
    front.library = (front.library || []).filter((one) => one.at !== at);
    front.docPins = (front.docPins || []).filter((one) => one.at !== at);
    front.archive = [...(front.archive || []), entry];
    return true;
  }
  if (!mine) return false;
  front.archive = (front.archive || []).filter((one) => one.at !== at);
  if (doc && mine.wasPinned) front.docPins = [...(front.docPins || []).filter((one) => one.at !== at), { at, head: "" }];
  if (!doc && mine.wasPinned === false) front.library = [...(front.library || []).filter((one) => one.at !== at), { at, head: "" }];
  if (visible && board && mine.wasShare) sec.share = mine.wasShare;
  else if (visible && !board && mine.wasPrivate === false) visible[listKey] = (visible[listKey] || []).filter((k) => k !== listItem);
  return true;
}

/**
 * **A rail's rows, under their categories, in his order** (2026-10-11).
 *
 * The sidebar's headings are the film's categories: a row stands under the
 * category it is filed in (`shelfIdOf`, the same call the Library makes, so
 * the two can never disagree), in the order of `front.rail`. A category with
 * no rows draws no heading. Anything `front.rail` does not name falls to the
 * end of its category in the order it arrived, so a page added this morning
 * appears without being placed first.
 *
 * Each row needs `at`; `name`, `type` and `page` (false for a document) are
 * used to file it. Answers `[{ head, shelf, rows }]`, headings in the order of
 * the film's categories; `empty` keeps the categories with no rows.
 *
 * **`public/film.js` carries the same rule**, because the program draws its
 * own rail in the browser and cannot import from here. Two copies of one rule
 * is the identity drift `STATUS.md` records; change one and change the other
 * in the same breath.
 */
export function railGroups(front, rows, { empty = false, keyOf = (r) => r.at } = {}) {
  const place = new Map((front.rail || []).map((at, i) => [at, i]));
  const arrived = new Map(rows.map((row, i) => [row, i]));
  const sorted = [...rows].sort((a, b) => {
    const pa = place.has(keyOf(a)) ? place.get(keyOf(a)) : Infinity;
    const pb = place.has(keyOf(b)) ? place.get(keyOf(b)) : Infinity;
    return pa - pb || arrived.get(a) - arrived.get(b);
  });
  const by = new Map(shelvesOf(front).map((one) => [one.id, { head: one.name, shelf: one.id, rows: [] }]));
  for (const row of sorted) {
    const id = shelfIdOf(front, keyOf(row), row.name, row.doc ? "doc" : "page", row.type || "");
    (by.get(id) || by.get("other") || [...by.values()][0]).rows.push(row);
  }
  // An editor also gets the categories with nothing in them yet, to drop a page on.
  return [...by.values()].filter((g) => empty || g.rows.length);
}

/**
 * **The order, after a drag that only saw the rows on screen.** `visible` is
 * the new order of the pages the sidebar was showing; pages that are off the
 * sidebar are not in it, and keep their place beside the neighbour they had.
 * Changes `front.rail` in place.
 */
export function applyOrder(front, visible) {
  const keep = [];
  const seen = new Set();
  for (const at of visible) if (!seen.has(at)) { seen.add(at); keep.push(at); }
  const hidden = (front.rail || []).filter((at) => !seen.has(at));
  const after = new Map();
  let prior = "";
  for (const at of front.rail || []) {
    if (seen.has(at)) { prior = at; continue; }
    (after.get(prior) || after.set(prior, []).get(prior)).push(at);
  }
  const out = [...(after.get("") || [])];
  for (const at of keep) { out.push(at); out.push(...(after.get(at) || [])); }
  const placed = new Set(out);
  for (const at of hidden) if (!placed.has(at)) out.push(at);
  front.rail = out.slice(0, MAX_ORDER);
}

/**
 * **The rail as a person or an agent draws it** — `[{ name, rows }]`, headings
 * and the pages under each — taken into the film (2026-10-11). The headings
 * are the categories, so this files each row under the category its heading
 * names (a heading no category carries yet becomes one, if there is room),
 * puts the categories in the order the headings came, and keeps the order of
 * the rows. A group with no name only contributes order: its rows stay filed
 * where they were. `infoOf(at)` says `{ name, type }` for a row so it can be
 * filed as the Library files it. Answers a sentence when something could not
 * be done (a category that would not fit), else "".
 */
export function arrangeRail(front, groups, infoOf = () => ({})) {
  // `updated` says when Notion last fed the film; a drag does not change it.
  const updated = front.updated;
  let said = "";
  const flat = [];
  const present = [];
  for (const group of Array.isArray(groups) ? groups : []) {
    const heading = words(group && group.name, 40);
    const rows = (Array.isArray(group && group.rows) ? group.rows : []).map((one) => String(one || "").trim()).filter(Boolean);
    let id = heading ? shelfIdFor(front, heading) : "";
    if (heading && !id) {
      const made = editShelves(front, { action: "add", name: heading });
      if (made.ok) id = made.id; else said = made.why;
    }
    if (id && !present.includes(id)) present.push(id);
    for (const at of rows) {
      flat.push(at);
      if (!id) continue;
      const info = infoOf(at) || {};
      setShelf(front, at, id, info.name || at, at.startsWith("doc:") ? "doc" : "page", info.type || "");
    }
  }
  // The categories he saw, in the order he saw them, in the slots they held.
  const all = shelvesOf(front).map((one) => one.id);
  const slots = all.map((id, i) => (present.includes(id) ? i : -1)).filter((i) => i >= 0);
  const next = [...all];
  slots.forEach((slot, n) => { next[slot] = present[n]; });
  if (next.join() !== all.join()) editShelves(front, { action: "order", ids: next });
  applyOrder(front, flat);
  front.updated = updated;
  return said;
}

/**
 * The order departments come in on a call sheet, roughly.
 *
 * Anything not named falls to the end in the order it arrived, which is how a
 * crew list he has not tidied still reads sensibly.
 */
const DEPARTMENTS = [
  "Above the Line",
  "Production",
  "AD",
  "Camera",
  "G&E",
  "Sound",
  "Art",
  "Costume",
  "Wardrobe",
  "Makeup",
  "Editorial",
  "Post",
  "Vendor",
  "Other",
];

/** The crew, in departments, in call-sheet order. */
export function byDepartment(crew) {
  const groups = new Map();
  for (const one of crew) {
    const key = one.department || "Crew";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(one);
  }
  return [...groups.entries()].sort((a, b) => {
    const left = DEPARTMENTS.indexOf(a[0]);
    const right = DEPARTMENTS.indexOf(b[0]);
    return (left < 0 ? 99 : left) - (right < 0 ? 99 : right);
  });
}


/**
 * `2 – 4 November`, or `2 November`, or nothing at all.
 *
 * **The months are written out rather than asked of `toLocaleDateString`.**
 * That depends on the runtime carrying ICU data, which is a fact about where
 * this happens to be running rather than about this code, and when it is
 * missing the failure is silent: a shoot date that reads `2026-11-02` on a page
 * somebody is planning around. Twelve words are cheaper than finding that out
 * on his director's phone.
 */
export function shootDates(shoot) {
  if (!shoot || !shoot.start) return "";
  const at = (said) => {
    const [year, month, day] = said.split("-").map(Number);
    return { year, month: MONTHS[month - 1] || "", day };
  };
  const start = at(shoot.start);
  if (!shoot.end || shoot.end === shoot.start) return `${start.day} ${start.month}`;
  const end = at(shoot.end);
  if (start.month === end.month && start.year === end.year) {
    return `${start.day} – ${end.day} ${end.month}`;
  }
  return `${start.day} ${start.month} – ${end.day} ${end.month}`;
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/**
 * A date, in the pieces a calendar square is drawn from.
 *
 * **Arithmetic, not `toLocaleDateString`** — the same reason the months are
 * written out above. A worker without ICU data answers that call with the
 * numbers back, and the failure is silent: a shoot day drawn as `2026-11-02` on
 * a page somebody is planning around.
 */
export function dayParts(said) {
  const [year, month, day] = String(said).split("-").map(Number);
  const at = new Date(Date.UTC(year, month - 1, day));
  return { weekday: WEEKDAYS[at.getUTCDay()] || "", day, month: MONTHS[month - 1] || "", year };
}

/**
 * How far off a day is, in the words a person uses.
 *
 * Whole days apart in UTC rather than hours, so a shoot the day after tomorrow
 * does not read as "1 day away" because of the time it happens to be here. A
 * day already past says nothing at all rather than counting upwards.
 */
export function awaySaid(said, now = new Date()) {
  const [year, month, day] = String(said).split("-").map(Number);
  if (!year || !month || !day) return "";
  const then = Date.UTC(year, month - 1, day);
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const days = Math.round((then - today) / 86400000);
  if (days === 0) return "today";
  if (days === 1) return "tomorrow";
  return days > 1 ? `${days} days away` : "";
}

/** `2.39 : 1`, from a number nobody should have to read as a decimal. */
export function ratioSaid(ratio) {
  return ratio > 0 ? `${Number(ratio.toFixed(2))} : 1` : "";
}

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

/**
 * When the page was last brought up to date, in words.
 *
 * Quiet, and at the foot — but it is the answer to "did that actually do
 * anything", which otherwise takes a Terminal window to find out.
 */
export function updatedSaid(said) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(said || "")) return "";
  const [date, clock] = said.split("T");
  const [year, month, day] = date.split("-").map(Number);
  return `${day} ${MONTHS[month - 1] || ""} ${year}, ${clock.slice(0, 5)}`;
}

/** Whether a spec sheet has anything on it at all. */
export function hasCamera(camera) {
  return Boolean(camera) && Object.entries(camera).some(([k, v]) => k !== "luts" && (Array.isArray(v) ? v.length > 0 : v));
}

/** How big a file is, in the words a person uses. */
export function sizeSaid(bytes) {
  if (!bytes) return "";
  if (bytes < 1024) return `${bytes} bytes`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/**
 * **The documents on the sidebar** (his ask, 2026-10-11: *"this should be a
 * function of any page on the portal"*): a file or a link pinned from the
 * Library, each its own row that opens it. In pin order; archived ones are off.
 */
export function pinnedDocs(front) {
  const pins = new Set((front.docPins || []).map((one) => one.at));
  return (front.documents || [])
    .filter((d) => d && d.name && pins.has(`doc:${d.name}`) && !isArchived(front, `doc:${d.name}`))
    .map((d) => ({ at: `doc:${d.name}`, name: d.name, doc: true, file: d.file || "", url: d.url || "" }));
}
