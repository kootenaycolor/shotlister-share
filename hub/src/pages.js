/**
 * Front of house — the shelf, a film's own page, its documents and its crew.
 *
 * **Two rooms, one building.** These pages are *his*: the wordmark, his blue,
 * his typeface, real key art. Everything past them — the shot list, the
 * locations, the boards, the schedule — is the app, unchanged, in the app's own
 * accent, because `hub.css` reads its palette out of `studio/Sources/Theme.swift`
 * and has to keep doing so or the browser and the Mac drift apart. The accent
 * changing at the door is the design, not an oversight.
 *
 * Drawn on the server from `front.json` alone, which is why they arrive at once
 * rather than after a hundred change logs have been fetched and replayed. The
 * shot list still does that; a page somebody opens on their phone to find out
 * where they are going on Tuesday must not.
 *
 * Shape follows his own "Dossier" sketch for a Notion project hub: vitals as a
 * property strip, then the logline, then the documents that are worth one
 * click, then compact ways into everything else. *Nothing is hidden, nothing
 * scrolls forever.*
 *
 * These return page **bodies**. `worker.js` wraps them in the one document
 * shell it owns.
 */

import { canonStage, shownStage } from "./stageword.js";
import { ICON_CHOICES, ROW_ICONS, defaultIcon, iconName } from "./icons.js";
import { awaySaid, byDepartment, dayParts, everyone, filmBase, hasCamera, isArchived, leadShoot, offSidebar, pinnedDocs, railGroups, shelfOf, shelfIdOf, shelfList, shelfNames, shelvesOf, PAGE_SOURCES, ratioSaid, shootDates, shotListCount, sizeSaid, syncOf, updatedSaid } from "./front.js";
import { emptyVisible, maySee, mayContact, meSees, fileNameOf, boardOpen } from "./films.js";
import { markdownFrom, playerOf } from "./paper.js";
import { creditLine, creditWords } from "./credits.js";
import { selectsBlock } from "./portalselects.js";
import { draftName, draftAlso, draftDate } from "./scriptlabel.js";
import { lensSets, lensSetsShown, arePills, oneLine } from "./lenses.js";
import { cameras, entries, fieldsOfCard, labelKey, lutKey, luts } from "./entries.js";

export function esc(s) {
  return String(s).replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c])
  );
}

/**
 * Who you are, behind the initial in the corner.
 *
 * **It used to do nothing.** His instruction, 2026-09-02: *"the N is not in
 * line and nothing happen when you click it — whats the point?"* Fair. It is
 * the one place on the page that is *about you*, so it holds what there is:
 * the address you came in as, and what you may do here. The Editor pill that
 * stood beside it has gone inside — it was a fact about you sitting out in a
 * bar full of controls, which is why it read as a button and never was one.
 *
 * **A `<details>`, so it needs no script.** These pages are drawn on the
 * server; a menu that only opens once JavaScript has arrived is a menu that is
 * dead on the slowest connection somebody opens a link on.
 */
function meCard(who, role, admin = false, base = "") {
  const named = who && who.email ? esc(who.email) : "Opened with a link";
  // **What you are, in one line, inside the menu.** His instruction,
  // 2026-09-04: the status belongs in the pop-up rather than beside the circle.
  // Administrator is a second thing he is, not a bigger version of Editor — the
  // panel it unlocks is his alone and nobody else on the film can even see it.
  const may = [
    role === "editor" ? "Editor" : role ? "Viewer" : "",
    admin ? "Administrator" : "",
  ].filter(Boolean).join(" · ");
  return `<details class="me">
    <summary class="fh-avatar" title="You" aria-label="You">${
      // **Somebody with no sign-in gets a person, not a full stop.** His
      // instruction, 2026-09-08. A `·` is what a program prints when it has
      // nothing — it named nobody and read as a fault. Initials are a name said
      // short; where there is no name, the mark says *a person*, in the same
      // hand as every other mark here. The menu behind it still says *Opened
      // with a link*, which is the part a word can carry.
      who && who.email ? esc(initials(who)) : mark(PERSON, 15)
    }</summary>
    <div class="mecard">
      <div class="mewho">${named}</div>
      ${may ? `<div class="memay">${may}</div>` : ""}
      ${
        // The one thing worth saying rather than naming: a viewer who cannot
        // work out why a button is missing is a viewer who writes to ask.
        may === "Viewer" ? `<p class="mesaid">View only</p>` : ""
      }
      ${
        /* **The way in to Visibility.** His report, 2026-09-04: he expected
           to find it behind his own initials and it was not there — the panel
           had no link anywhere at all, so the only way to reach it was to
           know the address and type it. It belongs here rather than in the
           rail: the rail is the film, and this is a thing *he* can do that
           nobody else on the film can even see.

           **It says what the page is called.** `Who Sees What` read better and
           named nothing — a link should say where it goes, and the page is
           headed `Visibility`. */
        /* **Retired 2026-10-11**: what a viewer sees is set where the pages
           are, in the Library (each row's one switch, and Crew), so his
           initials no longer lead to a second screen for it. */
        ""
      }
    </div>
  </details>`;
}

function initials(who) {
  if (!who || !who.email) return "·";
  const name = who.email.split("@")[0].replace(/[^A-Za-z]+/g, " ").trim();
  const bits = name.split(/\s+/).filter(Boolean);
  if (!bits.length) return who.email[0].toUpperCase();
  return (bits[0][0] + (bits[1] ? bits[1][0] : "")).toUpperCase();
}

/**
 * The bar every front-of-house page wears.
 *
 * **`back` is the way to the other films, and it says so.** His instruction,
 * 2026-09-02: a bare arrow beside a thumbnail of the film you are already
 * looking at said nothing. It is a word now — *Projects* — and the film's page
 * only offers it to somebody who *has* other films. One film, no way out and
 * nothing where it would have been.
 */
function bar(who, role, back, share) {
  return `<div class="fh-bar">
    ${back ? `<a class="back" href="${esc(back)}">&#8592; Projects</a>` : ""}
    ${back ? "" : `<a class="mark" href="/" aria-label="Nathaniel Regier"></a>`}
    <div class="spacer"></div>
    ${share ? shareButton(share.base, share.shared, share.at) : ""}
    ${meCard(who, role)}
  </div>`;
}

/**
 * A mark, stroked in `currentColor`.
 *
 * **Not an emoji.** One arrives in whatever colour and weight the operating
 * system feels like, at a size that matches nothing beside it, and differs on
 * every machine that opens the page. These are the app's own line weight.
 */
function mark(paths, size = 14) {
  return `<svg viewBox="0 0 16 16" width="${size}" height="${size}" fill="none" stroke="currentColor"
    stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
}

const LOCK =
  '<path d="M4.4 7.2h7.2a1.4 1.4 0 0 1 1.4 1.4v4.2a1.4 1.4 0 0 1-1.4 1.4H4.4A1.4 1.4 0 0 1 3 12.8V8.6a1.4 1.4 0 0 1 1.4-1.4Z"/><path d="M5.6 7.2V5.4a2.4 2.4 0 0 1 4.8 0v1.8"/>';
const GLOBE =
  '<circle cx="8" cy="8" r="5.4"/><path d="M2.6 8h10.8"/><path d="M8 2.6c1.5 1.6 2.3 3.4 2.3 5.4S9.5 11.8 8 13.4C6.5 11.8 5.7 10 5.7 8S6.5 4.2 8 2.6Z"/>';
/* **The way in, drawn.** These three were `&rarr;` — a typed arrow, which comes
 * from whatever font has one and matched neither the type beside it nor the
 * lock in the same bar. His instruction, 2026-09-02: no characters standing in
 * for icons. */
const ARROW = '<path d="M3.2 8h9.6"/><path d="M9.2 4.4 12.8 8l-3.6 3.6"/>';
/* The same arrow, turned round — the way back to the other films. */
const BACK = '<path d="M12.8 8H3.2"/><path d="M6.8 4.4 3.2 8l3.6 3.6"/>';
/* Whoever is reading this and has not signed in: head and shoulders, the mark
   everything from a phone's address book to a passport queue uses for
   *somebody*. */
const PERSON = '<circle cx="8" cy="6" r="2.6"/><path d="M3.4 13.4a4.6 4.6 0 0 1 9.2 0"/>';
/** The two tools under the rail. Stroked, 16-unit, `currentColor` — never an emoji. */
const PLUS = '<path d="M8 3.4v9.2"/><path d="M3.4 8h9.2"/>';
const ROWS = '<path d="M2.8 4.2h10.4"/><path d="M2.8 8h10.4"/><path d="M2.8 11.8h6.4"/>';
/* The Script reader's bar (SL-1338): smaller, and down into a tray. */
const MINUS = '<path d="M3.4 8h9.2"/>';
const SAVE = '<path d="M8 2.8v7.4"/><path d="M4.9 7.3 8 10.4l3.1-3.1"/><path d="M3.2 13.2h9.6"/>';
/** A grip: six dots, the mark every list that can be dragged into order uses. Filled, not stroked. */
const GRIP = '<g fill="currentColor" stroke="none"><circle cx="5.6" cy="3.6" r="1.25"/><circle cx="10.4" cy="3.6" r="1.25"/><circle cx="5.6" cy="8" r="1.25"/><circle cx="10.4" cy="8" r="1.25"/><circle cx="5.6" cy="12.4" r="1.25"/><circle cx="10.4" cy="12.4" r="1.25"/></g>';
/** A magnifier: Find, at the top of the sidebar. */
const SEARCH = '<circle cx="7.2" cy="7.2" r="4.2"/><path d="M10.4 10.4 13.4 13.4"/>';
/** A cross: remove, at the end of a row. */
const CROSS = '<path d="M4 4l8 8"/><path d="M12 4l-8 8"/>';

/**
 * Share, and whether it already is.
 *
 * The lock and the globe are the same two states his documents use, and the
 * reason to draw them here rather than only inside the window: "is this film
 * out in the world" is a thing to be able to see at a glance, not something to
 * go and check.
 */
/**
 * Whether Share is drawn, and in which state.
 *
 * **A link holder gets one too**, and that is the whole of this. His report,
 * 2026-09-08: somebody let in by an unlisted link had no way to pass it on —
 * every link inside the film is a plain address with no key on it, so copying
 * the address bar hands over something that opens nothing. *"just copying the
 * url doesn't lead you to the right place."*
 *
 * They are not offered anything else. The window decides what to draw from
 * what the page was told, and the server refuses every write on the share host
 * whatever a page happens to draw.
 */
function shareFor(base, role, who, shared, at) {
  if (role === "editor") return { base, shared, at };
  // Out in the world by definition — they are reading it on a link.
  if (who && who.via === "link") return { base, shared: true, at };
  return null;
}

/**
 * **The rail's foot is the same on the editor's own pages.** Add, Headings and
 * Visibility drew their rail with no Share and no way back to Visibility in
 * the menu behind his initials, so the foot changed under him as he moved —
 * part of what his walkthrough of 2026-09-23 called inconsistent. Shared as
 * the film's front door: nobody is sent a link to Add.
 */
function toolShare(base, role, who, tools) {
  return tools && typeof tools.shared === "boolean" ? shareFor(base, role, who, tools.shared, "home") : null;
}

function shareButton(base, shared, at) {
  // A real link, so it works with nothing running; `share.js` catches the click
  // and opens the panel where it can.
  //
  // **It carries where it was pressed.** With nothing running the click is a
  // page load onto `/share`, and that page can read every address but the one
  // that matters — the page somebody was standing on. So the button says.
  const from = at && at !== "home" ? `?from=${encodeURIComponent(at)}` : "";
  return `<a class="sharebtn${shared ? " open" : ""}" data-share href="${base}/share${from}">
    ${mark(shared ? GLOBE : LOCK, 13)}Share</a>`;
}

/**
 * A file the portal draws or opens.
 *
 * `pic` rather than `media`: it looks in the portal's own store first and the
 * film's pictures second, so a look book put here and a frame already in the
 * film are one kind of address as far as these pages are concerned.
 */
function pictureUrl(base, file) {
  return `${base}/pic/${esc(file)}`;
}

/**
 * The same address, asking to be saved rather than opened.
 *
 * **`download` on the anchor is not enough**, and that is the whole reason this
 * exists: Safari on iOS ignores it, so a Download button there merely walked
 * you to the PDF and opened it. His report, 2026-09-08. The attribute stays —
 * it is what names the file on a desktop — and this tells the server, which is
 * the half a phone actually listens to.
 */
function saveUrl(base, file) {
  return `${pictureUrl(base, file)}?save=1`;
}

/**
 * A named file's friendly address — `/hla/file/visual-bible.pdf` — falling
 * back to the content address for a file with no name to go by.
 */
function fileUrl(base, doc) {
  const named = fileNameOf(doc);
  return named ? `${base}/file/${esc(named)}` : pictureUrl(base, doc.file);
}

// ------------------------------------------------------------------ the shelf

/**
 * Every film this person may open.
 *
 * **No photograph.** His instruction, 2026-09-04: the shelf should look like
 * the films do. A film's own page is its Notion icon in its Notion colour and
 * nothing else pictorial, so a shelf of key art was the one place in the front
 * of house presenting a film as an image — and a film with no picture set sat
 * beside one that had it as a hole where a photograph should be.
 *
 * So each card wears the same two things every other page of that film wears:
 * the mark, and the colour, which is set on the card itself so `--accent`
 * resolves per film rather than per page. A film with no icon still gets its
 * tile, tinted in the default blue — a plain swatch, which is honest, where an
 * empty box is a fault.
 */

/**
 * The deck editor's own front page.
 *
 * His correction, 2026-09-06: *"the deck editor shouldnt just be a portal to
 * the normal website — it should be its own hub where i can see all the
 * decks/documents, and i can edit them from there. kind of like the old deck
 * editor."* Fair. The old app opened on a list of decks; the new one opened on
 * the film shelf, which is one more step and the wrong subject.
 *
 * **Across every film, not inside one.** A deck belongs to a film, but he does
 * not think about them a film at a time — he thinks about the deck he is
 * working on. So they are all here, newest film first, each with the way in
 * beside it and its printed copy if there is one.
 */
export function decksBody(films, who) {
  const rows = films.flatMap((f) =>
    (f.decks || []).map((d) => ({ film: f, deck: d }))
  );
  if (!rows.length) {
    // **`fh2` is where the colours live**, and `shelfwrap` is the measure every
    // page without a rail uses. Without them this drew as near-black text on a
    // near-black ground — every token undefined and no fallback to catch it.
    return `<div class="fh2 shelf">
      ${bar(who, "", "")}
      <div class="shelfwrap"><h1>Decks</h1><p class="empty">No decks yet</p></div>
    </div>`;
  }
  return `<div class="fh2 shelf">
    ${bar(who, "", "")}
    <div class="shelfwrap">
    <h1>Decks</h1>
    <p class="sub">${rows.length} ${rows.length === 1 ? "deck" : "decks"}</p>
    <div class="decklist">
      ${rows.map(({ film, deck }) => `<div class="deckrow">
        <a class="deckname" href="${esc(film.base)}/${esc(deck.slug)}">
          <span class="dn">${esc(deck.name)}</span>
          <span class="df">${esc(film.title)}</span>
        </a>
        <div class="deckdid">
          ${deck.pdf ? `<a class="deckdo" href="${saveUrl(film.base, deck.pdf)}" download>PDF</a>` : ""}
          ${film.role === "editor" ? `<a class="deckdo prime" href="${esc(film.base)}/${esc(deck.slug)}/edit">Edit</a>` : ""}
        </div>
      </div>`).join("")}
    </div>
    </div>
  </div>`;
}

export function shelfBody(films, who, admin = false) {
  const cards = films
    .map((f) => {
      const front = f.front;
      const ratio = ratioSaid(front.ratio);
      const credit = [front.director, front.producer].filter(Boolean).join(" · ");
      // **A film with no card still has to say something true about itself.**
      // The counts come from the card, and a film nobody has run `set_front`
      // over has none — so it falls back to what the hub has always been able
      // to know on its own, which is how many changes the film is made of.
      // **The ratio is a fact, not a caption.** His instruction, 2026-09-01:
      // take it off the image. On a card there is no property strip to move it
      // to, so it joins the counts rather than disappearing.
      const counts =
        [
          ratio,
          front.counts.scenes ? `${front.counts.scenes} scenes` : "",
          front.counts.shots ? `${front.counts.shots} shots` : "",
          front.counts.days ? `${front.counts.days} shoot ${front.counts.days === 1 ? "day" : "days"}` : "",
        ]
          .filter(Boolean)
          .join(" · ") ||
        // **A portal with no film has no changes to count**, so it says
        // nothing rather than "0 changes" (2026-09-16).
        (Number.isFinite(f.logs) && !f.portal ? `${f.logs} ${f.logs === 1 ? "change" : "changes"}` : "");
      // **What the shelf's own controls sort and filter on** (`public/shelf.js`),
      // said on the card so nothing is fetched: the name, Notion's Status, the
      // first shoot date, and the words a search matches.
      const shoot = (shootDaysOf(front)[0] || {}).date || "";
      const find = [f.title, front.director, front.producer, front.status].filter(Boolean).join(" ").toLowerCase();
      // **The next shoot day, on the card itself.** Coming Up used to say this
      // once for every Active film, in a list that repeated the same films the
      // grid below it already named — his report, 2026-10-02: two lists of the
      // same thing. Folded onto the card it names, whatever the film's status:
      // the fold only works if nothing it said is lost.
      const next = nextShootSaid(front);
      // **What the owner's own sort reads** (`ownerSort` in `public/shelf.js`):
      // the next shoot day ahead, the last one behind, and when the card was
      // last refreshed from Notion. Said only for him — nobody else's shelf
      // has the sort, so nobody else's cards carry what it sorts on.
      const days = shootDaysOf(front);
      const ahead = (days.map((one) => one.date).find((date) => awaySaid(date) !== "" || date === todayIso())) || "";
      const owned = admin
        ? ` data-next="${esc(ahead)}" data-last="${esc((days[days.length - 1] || {}).date || "")}" data-edited="${esc(front.updated || "")}"`
        : "";
      return `<a class="pcard${next ? " haswhen" : ""}" href="${esc(f.base)}"${accent(front)} data-title="${esc(f.title)}" data-status="${esc(shownStage(front.status || ""))}" data-shoot="${esc(shoot)}" data-find="${esc(find)}"${owned}>
        <div class="m">
          <div class="cardhead">
            <span class="mtile">${filmIcon(front)}</span>
            <span class="brandpill${f.role === "editor" ? "" : " view"}">${f.role === "editor" ? "Editor" : "Viewer"}</span>
          </div>
          <div class="t">${esc(f.title)}</div>
          ${credit ? `<div class="by">${esc(credit)}</div>` : ""}
          ${next ? `<div class="when"><b>${esc(next.said)}</b><span${next.soon ? ` class="soon"` : ""}>${esc(next.away)}</span></div>` : ""}
          ${counts ? `<div class="n">${esc(counts)}</div>` : ""}
          ${front.status ? `<div class="foot">${esc(shownStage(front.status))}</div>` : ""}
        </div>
      </a>`;
    })
    .join("");

  // **`fh2`, not `fh`.** Every shelf rule in hub.css is scoped under `.fh`, so
  // the switch hands the whole shelf to front.css in one move and nothing of
  // the old look survives to fight it.
  return `<div class="fh2 shelf">
    ${bar(who, "", "")}
    <div class="shelfwrap">
      <h1>Projects</h1>
      <p class="sub" data-shelfcount>${films.length} ${films.length === 1 ? "project" : "projects"}</p>
      ${films.length > 1 ? shelfTools(films, admin) : ""}
      ${films.length ? `<div class="grid3" data-shelf>${cards}</div>
        <p class="empty" data-shelfnone hidden>No results</p>` : `<p class="empty">No projects</p>`}
    </div>
  </div>`;
}

/**
 * **Finding a film when there are forty.** His walkthrough, 2026-09-23: the
 * shelf needs sorting, filtering and a list as well as a grid, because it will
 * get big.
 *
 * **His own Status words, not new ones.** The chips are the statuses his films
 * actually carry in Notion (Development, Active, Post, Archived), in that
 * order, each with its count — nothing is invented to filter on. Drawn
 * `hidden`: with no script there is nothing for them to do, and the grid still
 * stands. `public/shelf.js` wakes them and remembers the choice per browser.
 */
const STATUS_ORDER = ["Development", "Active", "Post", "Released", "Archived"];

function shelfTools(films, admin = false) {
  const count = new Map();
  for (const f of films) {
    const s = shownStage(f.front.status || "");   // the card, chip and group say Complete
    if (s) count.set(s, (count.get(s) || 0) + 1);
  }
  const rank = (s) => { const i = STATUS_ORDER.indexOf(canonStage(s)); return i === -1 ? STATUS_ORDER.length : i; };
  const statuses = [...count.keys()].sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));
  const chip = (value, name, n) => `<button type="button" class="fh-chip${value === "" ? " on" : ""}" data-status="${esc(value)}">${esc(name)}${
    n ? `<span>${n}</span>` : ""}</button>`;
  // **The owner's sort is a menu, and everybody else's is the select they
  // have always had.** His ask, 2026-10-05: Next Date, Name, Recently Changed
  // and Status, with the stages folding, and a No Groups choice — his own
  // home page only. The menu's words are drawn by `public/shelf.js`, which
  // only builds it where the page says `data-owner`.
  const sorter = admin
    ? `<span class="fh-sort"><span>Sort</span><button type="button" class="fh-sortbtn" data-ownersort aria-haspopup="menu" aria-expanded="false">Next Date</button></span>`
    : `<label class="fh-sort"><span>Sort</span><select data-shelfsort aria-label="Sort">
        <option value="name">Name</option>
        <option value="status">Status</option>
        <option value="shoot">Shoot Date</option>
      </select></label>`;
  return `<div class="fh-shelftools" data-shelftools${admin ? " data-owner" : ""} hidden>
    <input class="fh-find" type="search" placeholder="Search projects" autocomplete="off" aria-label="Search projects" data-shelffind>
    ${statuses.length > 1 ? `<div class="fh-chips" role="group" aria-label="Status">${chip("", "All", 0)}${
      statuses.map((s) => chip(s, s, count.get(s))).join("")}</div>` : ""}
    <div class="fh-shelfright">
      ${sorter}
      <div class="fh-seg" role="group" aria-label="View">
        <button type="button" class="on" data-shelfview="grid">Grid</button>
        <button type="button" data-shelfview="list">List</button>
      </div>
    </div>
  </div>`;
}

// ------------------------------------------------------------- a film's page

/** One fact in the strip: a small tracked label over the thing itself. */
function fact(label, value) {
  // **Every value on the page is copyable**, his ask of 2026-09-02: on a
  // published Notion page he can take a frame rate or a LUT name straight off
  // the sheet, and a page he has to select text on with a mouse is a worse page
  // than the one he is leaving. `fact` is the one funnel every label-and-value
  // pair goes through — the camera sheet and the vitals strip alike — so
  // marking it here covers all of them at once. `copy.js` does the rest.
  return value ? `<div class="fh-fact"><span>${esc(label)}</span><b data-copy>${esc(value)}</b></div>` : "";
}

/**
 * One pinned document.
 *
 * A file we hold opens in the browser; a link goes wherever it goes, in a new
 * tab, with `rel="noopener noreferrer"` because the address came out of
 * somebody else's page and is not ours to vouch for.
 */
function documentCard(base, doc, role = "viewer") {
  // **A Drive file opens through the portal** (portaldocs.js), so crew need
  // no Drive access and a file switched off stops answering.
  const drive = doc.source === "drive" && doc.drive;
  const href = drive ? `${base}/drive/${doc.drive}` : doc.file ? fileUrl(base, doc) : doc.url;
  const outside = !doc.file && !drive;
  const what = drive
    ? [doc.type, docDate(doc.modified)].filter(Boolean).join(" · ")
    : doc.file
    ? [doc.file.split(".").pop().toUpperCase(), sizeSaid(doc.bytes)].filter(Boolean).join(" · ")
    : hostOf(doc.url);
  // **No type glyph.** His ruling, 2026-09-15: a word names the thing, and
  // the line under the name already says PDF or drive.google.com.
  const card = `<a class="fh-doc" href="${esc(href)}"${outside ? ` target="_blank" rel="noopener noreferrer"` : ` target="_blank"`}>
    <span class="fh-docn">
      <b title="${esc(doc.name)}">${esc(doc.name)}</b>
      ${what ? `<span>${esc(what)}</span>` : ""}
    </span>
  </a>`;
  // **Archived, not deleted** — the same Archive every other page has, and it
  // comes back from the Library. A held file is content-addressed and a page
  // may be drawing it, so nothing is ever taken away to tidy a list.
  if (role !== "editor") return card;
  // **Drive's name, Drive's file**: renamed in Drive, switched off in
  // Projects Console. Here an editor can open it in Drive itself.
  if (drive) {
    return `<div class="docrow">${card}<a class="unpin drivego" href="https://drive.google.com/file/d/${esc(doc.drive)}/view" target="_blank" rel="noopener noreferrer">Drive ↗</a></div>`;
  }
  // **Rename is for every document** — a name is the portal's to change even
  // where Notion names the row (it is remembered as `was`, `renameDocument`).
  const rename = `<form method="post" class="unpin renamedoc">
    <input type="hidden" name="rename_doc" value="${esc(doc.name)}">
    <input type="hidden" name="to" value="${esc(doc.name)}">
    <button type="button" class="renamebtn">Rename</button>
  </form>`;
  const archive = `<form method="post" action="${esc(base)}/library" class="unpin">
    <input type="hidden" name="archive" value="${esc(`doc:${doc.name}`)}">
    <input type="hidden" name="on" value="1">
    <input type="hidden" name="back" value="documents">
    <button type="submit">Archive</button>
  </form>`;
  return `<div class="docrow">${card}${rename}${archive}</div>`;
}

function hostOf(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

/** The picture a tile is drawn with. */
function tilePic(base, name) {
  return `<span class="pic" style="background-image:url('${pictureUrl(base, name)}')"></span>`;
}

/**
 * The way into the shot list, which is not one of the tiles.
 *
 * His instruction, 2026-09-01: *"shot list blends in too easily — it should
 * feel distinct from the others."* It is the film; the other three are things
 * about the film. So it is not a card in the row at all — it is the band above
 * it, wearing his blue, with the two counts set large enough to read across a
 * room and **no pictures on it whatsoever**, which is the other half of what he
 * said.
 */
function leadIn(href, scenes, shots) {
  const counted = (number, word) =>
    number
      ? `<span class="lc"><b>${number}</b><span>${number === 1 ? word : `${word}s`}</span></span>`
      : "";
  return `<a class="lead" href="${esc(href)}">
    <span class="ln">Shot list</span>
    <span class="lcs">${counted(scenes, "scene")}${counted(shots, "shot")}</span>
    <span class="lgo">Open ${mark(ARROW, 13)}</span>
  </a>`;
}

/**
 * One way in, drawn with what it holds.
 *
 * **The name sits under the picture, not on it.** It was drawn over the picture
 * first, bold and shadowed over a scrim, and his answer was that the tiles were
 * still not clear enough. A name over a photograph is always negotiating with
 * whatever is behind it; a name on the card's own surface is not negotiating
 * with anything. So every tile is a picture with a label under it, all three
 * the same shape whether what they hold is photographs or dates.
 */
function tile(href, name, said, inside) {
  // **No pictures, no box.** A film nobody has photographed yet would otherwise
  // get three grey rectangles holding open nothing, which is the fault this
  // whole pass began with. It becomes a labelled row instead.
  return `<a class="tool" href="${esc(href)}">
    ${inside ? `<span class="top">${inside}</span>` : ""}
    <span class="lab">
      <span class="labt">
        <span class="tn">${esc(name)}</span>
        ${said ? `<span class="td">${esc(said)}</span>` : ""}
      </span>
      <span class="arrow">${mark(ARROW, 14)}</span>
    </span>
  </a>`;
}

/**
 * The pictures a tile is drawn with, in a shape that follows how many there are.
 *
 * One fills it; four make a square. A thing with no pictures yet gets an empty
 * surface rather than an invented illustration, and the label under it still
 * says what it is.
 */
function mosaic(base, pics) {
  if (!pics.length) return "";
  const shape = ["", "one", "two", "three", "four"][Math.min(pics.length, 4)];
  return `<span class="mosaic ${shape}">${pics.slice(0, 4).map((one) => tilePic(base, one)).join("")}</span>`;
}

/**
 * The shoot, as a calendar page.
 *
 * The days the film actually has, with their real dates, because three date
 * squares say what the number 3 does not: which days, how far off, and whether
 * that is this week. Weekday and month are worked out by arithmetic rather than
 * asked of `toLocaleDateString`, which needs ICU data a worker may not carry —
 * the same trap `shootDates` is written around.
 */
function calendar(days) {
  if (!days.length) return "";
  const shown = days.slice(0, 3);
  const squares = shown
    .map((one) => {
      const at = dayParts(one.date);
      return `<span class="day"><i>${esc(at.weekday)}</i><b>${at.day}</b></span>`;
    })
    .join("");
  const first = dayParts(shown[0].date);
  const said = [first.month, awaySaid(shown[0].date), days.length > 3 ? `${days.length - 3} more` : ""]
    .filter(Boolean)
    .join(" · ");
  return `<span class="cal"><span class="dates">${squares}</span>${
    said ? `<span class="dsaid">${esc(said)}</span>` : ""
  }</span>`;
}

function counted(a, aWord, b, bWord) {
  const bits = [];
  if (a) bits.push(`${a} ${a === 1 ? aWord : aWord + "s"}`);
  if (b) bits.push(`${b} ${b === 1 ? bWord : bWord + "s"}`);
  return bits.join(" · ");
}

function crewRow(one, reachable, fresh = false) {
  const under = [one.role, one.company].filter(Boolean).join(" · ");
  // Held back from anyone who is not an editor and not marked visible in
  // Visibility — including a link holder, who is forced to `viewer` on the
  // share host and is the whole reason this gate exists.
  const reach = !reachable ? "" : [
    one.email ? `<a href="mailto:${esc(one.email)}" data-copy="${esc(one.email)}">${esc(one.email)}</a>` : "",
    one.phone ? `<a href="tel:${esc(one.phone.replace(/[^\d+]/g, ""))}" data-copy="${esc(one.phone)}">${esc(one.phone)}</a>` : "",
  ]
    .filter(Boolean)
    .join("");
  return `<div class="mate">
    <div class="mn"><b>${esc(one.name)}${fresh ? ` <i class="newmark">New</i>` : ""}</b>${under ? `<span>${esc(under)}</span>` : ""}</div>
    ${reach ? `<div class="reach">${reach}</div>` : ""}
  </div>`;
}

// ------------------------------------------------------- front of house, v2

/**
 * One line of a spec sheet: what it is, what it says — and the whole line
 * takes it.
 *
 * His ask, 2026-09-10: no small button at the end of the row; press anywhere
 * on the row and the value is on the clipboard. The row carries the value in
 * `data-copy` rather than reading it off the page, so what lands is exactly
 * the value and never the label beside it. Dragging across the words still
 * selects them — `copy.js` leaves a click alone when it ended a selection.
 */
function specRow(label, value, was = null) {
  if (!value) return "";
  // **What changed since the shoot before** (SL-1396): worked out by
  // comparing the two sheets, not written by anybody.
  const changed = was !== null && String(was || "").trim() !== String(value).trim();
  return `<div class="specrow${changed ? " changed" : ""}" data-copy="${esc(value)}" title="Copy ${esc(label)}">
    <dt>${esc(label)}</dt>
    <dd>${esc(value)}${changed && was ? `<span class="was">was ${esc(was)}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

/**
 * **Pills, same as Notion** (2026-10-13). His words: *"if we do pills in
 * notion and the table view, then we stick to it."* Each value of a sheet's
 * box is a pill in the colour Notion gave its option (`camera_pills` on the
 * card, laid by the refresh from `src/specpills.js`). The row still copies
 * the whole box as text, one value per line.
 */
function pillSpan(front, prop, name) {
  const colour = (((front && front.camera_pills) || {})[prop] || {})[String(name).toLowerCase()] || "default";
  return `<span class="np np-${esc(colour)}">${esc(name)}</span>`;
}

function pillRow(front, label, prop, value, was = null, after = null) {
  const changed = was !== null && String(was || "").trim() !== String(value).trim();
  const names = String(value).split("\n").map((x) => x.trim()).filter(Boolean);
  // `after`: a few words after a pill, by its name (a lens's close focus, "CF 0.35 m")
  const more = (n) => (after && after[n] ? `<i class="npcf">${esc(after[n])}</i>` : "");
  return `<div class="specrow pillrow${changed ? " changed" : ""}" data-copy="${esc(names.map((n) => (after && after[n] ? `${n} · ${after[n]}` : n)).join("\n"))}" title="Copy ${esc(label)}">
    <dt>${esc(label)}</dt>
    <dd><span class="nps">${names.map((n) => pillSpan(front, prop, n) + more(n)).join("")}</span>${changed && was ? `<span class="was">was ${esc(oneLine(was))}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

/** The Camera row as pills: each body a pill, its label (A Cam) under it. */
function cameraPillRow(front, group, value, was = null) {
  const changed = was !== null && String(was || "").trim() !== String(value).trim();
  const cams = group.cameras.filter((c) => c.name);
  return `<div class="specrow pillrow${changed ? " changed" : ""}" data-copy="${esc(cams.map((c) => (c.label ? `${c.label}: ${c.name}` : c.name)).join("\n"))}" title="Copy Camera">
    <dt>Camera</dt>
    <dd><span class="nps cams">${cams.map((c) => `<span class="npcam">${pillSpan(front, "Camera", c.name)}${c.label ? `<i>${esc(c.label)}</i>` : ""}</span>`).join("")}</span>${changed && was ? `<span class="was">was ${esc(oneLine(was))}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

/**
 * **Lenses, one set per line** (2026-10-05, `src/lenses.js`). One set reads
 * as it always did; several are a list — camera, lenses, focal lengths and
 * stop, notes under — so an A Cam zoom and a B Cam set of primes are not one
 * long line. The copy button still copies the whole field.
 */
function lensRow(value, was = null) {
  const sets = lensSetsShown(value);
  if (sets.length < 2) return specRow("Lenses", value, was === null ? null : oneLine(was));
  const changed = was !== null && String(was || "").trim() !== String(value).trim();
  const line = (one) => `<li>${one.label ? `<i>${esc(one.label)}</i>` : ""}<b>${esc(one.series || one.raw)}</b>${
    [one.focals.join(", "), one.stop].filter(Boolean).map((bit) => `<span>${esc(bit)}</span>`).join("")}${
    one.notes ? `<small>${esc(one.notes)}</small>` : ""}</li>`;
  return `<div class="specrow lensrow${changed ? " changed" : ""}" data-copy="${esc(value)}" title="Copy Lenses">
    <dt>Lenses</dt>
    <dd><ul class="lenssets">${sets.map(line).join("")}</ul>${changed && was ? `<span class="was">was ${esc(oneLine(was))}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

/**
 * **A setting across the cameras**, 2026-10-07 — his ask that day: *"settings
 * for all cameras should go full width."* One setting to a row, as ever: a
 * value every camera shares fills the row on its own, and one they differ in
 * is a column per camera, under the cameras named in the Camera row above —
 * the same table Projects Console draws. The row still copies the whole
 * field, and a line naming no camera is drawn rather than dropped.
 *
 * `cell` is camCells; `n` the number of cameras, so every row's columns line
 * up with every other's.
 */
function camRow(label, cell, copy, was = null, n = 1) {
  if (cell.said !== undefined) return specRow(label, cell.said, was === null ? null : oneLine(was));
  const changed = was !== null && String(was || "").trim() !== String(copy).trim();
  const cells = cell.cols.map((value, i) => `<li>${cell.labels && cell.labels[i] ? `<i>${esc(cell.labels[i])}</i>` : ""}<b>${esc(value || "—")}</b></li>`)
    .concat((cell.extra || []).map((u) => `<li><i>${esc(u.label)}</i><b>${esc(u.value)}</b></li>`)).join("");
  return `<div class="specrow camrow${changed ? " changed" : ""}" data-copy="${esc(copy)}" title="Copy ${esc(label)}">
    <dt>${esc(label)}</dt>
    <dd><ul class="camcols" style="--cams:${n}">${cells}</ul>${changed && was ? `<span class="was">was ${esc(oneLine(was))}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

/**
 * **The LUTs row, as Projects Console draws it** (2026-10-14, his ask: *"get
 * the portal looking more like the project console in the way it handles
 * luts and notes"*). One row of the sheet's table, `LUTs`; each file a chip
 * by its file name that opens it. A LUT every camera has is drawn once
 * across the row; when the cameras differ, each column holds its own, under
 * the camera named in the Camera row. A label that is not a camera's ("Show
 * LUT") stays beside its file. A file Notion keeps itself says so until it is
 * copied to the shoot's Drive folder.
 *
 * `files` the card's LUT files; `labelsText` the `LUT Labels` lines, by
 * camera ("A Cam: x.cube") or by name ("Show LUT: x.cube").
 */
export function lutPlaces(group, files, labelsText) {
  const lines = entries(labelsText).filter((e) => e.label);
  const multi = group.multi && group.cameras.length > 1;
  const camOf = (label) => {
    const k = labelKey(label);
    return group.cameras.findIndex((c) => c.label && (k === labelKey(c.label) || k.startsWith(labelKey(c.label))));
  };
  const out = (files || []).map((f) => {
    const keys = new Set([lutKey(f), f.url || ""].map((k) => String(k).trim().toLowerCase()).filter(Boolean));
    const said = lines.filter((e) => keys.has(e.value.trim().toLowerCase()));
    const on = new Set();
    let own = "";
    for (const e of said) {
      const i = multi ? camOf(e.label) : -1;
      if (i >= 0) {
        on.add(i);
        // "A Cam Day: x.cube": A Cam's, labelled Day
        const words = e.label.trim().split(/\s+/);
        const camWords = group.cameras[i].label.trim().split(/\s+/).length;
        const rest = labelKey(words.slice(0, camWords).join(" ")) === labelKey(group.cameras[i].label) ? words.slice(camWords).join(" ") : "";
        if (rest && !own) own = rest;
      } else if (!own) own = e.label;
    }
    const name = String(f.name || "");
    return { ...f, own, on, shown: name && !name.startsWith("http") ? name : (f.url || name) };
  });
  const cols = multi ? group.cameras.map((_, i) => out.filter((l) => !l.on.size || l.on.has(i))) : [];
  const same = cols.every((c) => c.length === cols[0].length && c.every((l, j) => l === cols[0][j]));
  return { luts: out, together: !multi || same, cols };
}

function lutChip(base, one) {
  const href = one.file ? fileUrl(base, one) : one.url || "";
  const held = Boolean(one.file || one.held);
  const name = href
    ? `<a class="lutf" href="${esc(href)}" target="_blank" rel="noopener noreferrer" title="${esc(one.shown)}">${esc(one.shown)}</a>`
    : `<span class="lutf" title="${esc(one.shown)}">${esc(one.shown)}</span>`;
  return `<span class="lut">${one.own ? `<i>${esc(one.own)}</i>` : ""}${name}${held ? `<small>File in Notion</small>` : ""}</span>`;
}

/**
 * **Aspect Ratio with its frame guide files** (2026-10-15): each ratio a pill
 * ("Main 2.39:1"), the frame-line files the AC loads under it, each a link
 * that downloads it, its camera before it. A ratio with no files is a pill
 * as ever, so a sheet with none draws as it did.
 */
function ratioRow(front, ratios, label, prop, value, was = null) {
  if (!ratios.some((f) => (f.guides || []).length)) return pillRow(front, label, prop, value, was);
  const changed = was !== null && String(was || "").trim() !== String(value).trim();
  const guide = (g) => {
    const name = g.name || "Frame guide";
    const chip = g.url
      ? `<a class="lutf" href="${esc(g.url)}" target="_blank" rel="noopener noreferrer" download title="${esc(g.note || name)}">${esc(name)}</a>`
      : `<span class="lutf" title="Uploading to Drive">${esc(name)}</span>`;
    return `<span class="lut">${g.camera ? `<i>${esc(g.camera)}</i>` : ""}${chip}${g.url ? "" : `<small>Uploading</small>`}${g.note ? `<small>${esc(g.note)}</small>` : ""}</span>`;
  };
  const block = (f) => `<div class="ratioguides">${pillSpan(front, prop, `${f.name} ${f.ratio}`.trim())}${(f.guides || []).length ? `<span class="luts">${f.guides.map(guide).join("")}</span>` : ""}</div>`;
  const copy = ratios.flatMap((f) => [`${f.name} ${f.ratio}`.trim(), ...(f.guides || []).map((g) => `  ${g.camera ? `${g.camera}: ` : ""}${g.name}${g.url ? ` ${g.url}` : ""}`)]).join("\n");
  return `<div class="specrow pillrow${changed ? " changed" : ""}" data-copy="${esc(copy)}" title="Copy ${esc(label)}">
    <dt>${esc(label)}</dt>
    <dd>${ratios.map(block).join("")}${changed && was ? `<span class="was">was ${esc(oneLine(was))}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

function lutsRow(base, group, files, labelsText) {
  if (!files.length) return "";
  const got = lutPlaces(group, files, labelsText);
  const chips = (list) => (list.length ? `<span class="luts">${list.map((one) => lutChip(base, one)).join("")}</span>` : `<span class="lutnone">None</span>`);
  // what the row copies, as the Console's Copy says it: "A Cam: name link"
  const copy = got.luts.flatMap((one) => {
    const tail = `${one.own ? `${one.own}: ` : ""}${one.shown}${one.url && one.url !== one.shown ? ` ${one.url}` : ""}`;
    if (got.together || !one.on.size) return [tail];
    return [...one.on].sort().map((i) => `${group.cameras[i].label}: ${tail}`);
  }).join("\n");
  const cell = got.together
    ? chips(got.luts)
    : `<ul class="camcols lutcols" style="--cams:${group.cameras.length}">${got.cols.map((list) => `<li>${chips(list)}</li>`).join("")}</ul>`;
  return `<div class="specrow lutrow" data-copy="${esc(copy)}" title="Copy LUTs">
    <dt>LUTs</dt>
    <dd>${cell}</dd>
  </div>`;
}

/**
 * **The Notes row**, the sheet's own (rental notes go here), as the Console
 * draws it: the last row of the table, the words as he typed them, line
 * breaks kept. The record's notes are words and the row copies them; a
 * Notion sheet's notes are its page, drawn in the same row.
 */
/**
 * **Finishing Resolutions** (2026-10-15): the deliverables, one line each —
 * its title, the resolution, a note. Copies as typed lines.
 */
function finishingRow(list, was, text) {
  if (!list.length) return "";
  const changed = was !== null && String(was || "").trim() !== String(text).trim();
  return `<div class="specrow finrow${changed ? " changed" : ""}" data-copy="${esc(text)}" title="Copy Finishing Resolutions">
    <dt>Finishing Resolutions</dt>
    <dd>${list.map((f) => `<span class="finline"><b>${esc(f.title)}</b>${f.resolution ? `<span>${esc(f.resolution)}</span>` : ""}${f.note ? `<i>${esc(f.note)}</i>` : ""}</span>`).join("")}${changed && was ? `<span class="was">was ${esc(oneLine(was))}</span>` : changed ? `<span class="was">new</span>` : ""}</dd>
  </div>`;
}

function notesRow(base, text, tree) {
  const words = String(text || "").trim();
  if (!words && !tree) return "";
  return `<div class="specrow noterow${tree ? " tree" : ""}"${tree ? "" : ` data-copy="${esc(words)}" title="Copy Notes"`}>
    <dt>Notes</dt>
    <dd>${words ? `<span class="specnotes">${esc(words)}</span>` : ""}${tree ? `<div class="notion">${drawBlocks(base, tree)}</div>` : ""}</dd>
  </div>`;
}

/** One setting across the cameras: `{said}` when it is one value for all of
 * them (the row draws it full width), else `{cols}` — one to a camera, in the
 * cameras' own order, a camera with none of its own showing what they share.
 * `labels` names them (the Camera row only); `extra` is a line naming no
 * camera. A one-camera sheet always says `said`, exactly as it is typed. */
function camCells(group, prop, text) {
  if (!group.multi) return { said: entries(text).map((e) => e.raw || e.value).join("\n") };
  if (prop === "Camera") return { cols: group.cameras.map((c) => c.name), labels: group.cameras.map((c) => c.label) };
  const own = group.cameras.map((c) => c.fields[prop]);
  const shared = group.shared[prop] || "";
  const extra = group.unmatched.filter((x) => x.key === prop);
  if (own.every((v) => v === undefined) && !extra.length) return { said: shared };
  return { cols: own.map((v) => (v !== undefined ? v : shared)), extra };
}

/** The lines a fact shows: per camera when the sheet has several (a value
 * they share once, unlabelled), else the field's own lines. */
function cameraLines(group, prop, text) {
  if (!group.multi) return entries(text).map((e) => [e.label, e.value]);
  if (prop === "Camera") return group.cameras.map((c) => [c.label, c.name]);
  const own = group.cameras.map((c) => c.fields[prop]);
  const shared = group.shared[prop] || "";
  if (own.every((v) => v === undefined)) return shared ? [["", shared]] : [];
  const out = group.cameras.map((c, i) => [c.label || c.name, own[i] !== undefined ? own[i] : shared]).filter(([, v]) => v);
  for (const u of group.unmatched.filter((x) => x.key === prop)) out.push([u.label, u.value]);
  return out;
}

const SHORT_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** `Jul 9`, or `Jul 9–11` — his own way of writing a shoot's date. */
function shootDay(one) {
  const at = (ymd) => { const [, m, d] = String(ymd).split("-").map(Number); return { m: SHORT_MONTHS[m - 1], d }; };
  if (!one.start) return "";
  const a = at(one.start);
  if (!one.end || one.end === one.start) return `${a.m} ${a.d}`;
  const b = at(one.end);
  return a.m === b.m ? `${a.m} ${a.d}–${b.d}` : `${a.m} ${a.d} – ${b.m} ${b.d}`;
}

const STEP_BACK = '<path d="M9.8 3.8 5.6 8l4.2 4.2"/>';
const STEP_ON = '<path d="M6.2 3.8 10.4 8l-4.2 4.2"/>';
const OPENS = '<path d="M4.2 6.2 8 10l3.8-3.8"/>';

/**
 * **The shoot switcher** — SL-1396, his design of 2026-10-02 (`Shoot 1 ·
 * Jul 9 · Wrapped` | `Shoot 2 · Oct 6 · Next`), rebuilt the same evening for
 * any number of shoots, his ask: *"that tab for days needs to support what
 * could be many shoots - build it for that purpose."* Ref 1413.
 *
 * **One line, whatever the count**: the shoot you are on, its date and
 * where it stands, with ‹ › stepping to the shoot before and after in one
 * press — the last one is always one click away — and the line itself
 * opening a list of every shoot. Side-by-side tabs ran out of room at three.
 *
 * Each shoot is its own address (`/shoots/<slug>`), so a link sent to a crew
 * member opens the right one and an old one stays readable; moving to
 * another loads it whole, since the rail's rows, counts and the program's
 * narrowing all change with it. `shootTabsHere` in `public/film.js` draws
 * the same thing in the program's rail; change both.
 */
function shootTabs(base, front, at) {
  const shoots = front.shoots || [];
  if (shoots.length < 2 || !front.shootOn) return "";
  if (front.portalmodes) return shootPicker(base, front, at);
  const lead = leadShoot(front);
  const home = filmBase(base);
  const own = front.shootPages || {};
  const mine = own[front.shootOn.slug] || [];
  const here = shoots.findIndex((one) => one.slug === front.shootOn.slug);
  const word = (one) => (one.status === "Wrapped" ? "Wrapped" : one === lead ? "Next" : "Upcoming");
  // The same page on the other shoot — unless it is this shoot's own page,
  // and then the other shoot's own, or its front.
  const href = (one) => {
    const page = mine.includes(at) ? (own[one.slug] || [])[0] || "" : at === "home" ? "" : at;
    return `${home}/shoots/${one.slug}${page ? `/${page}` : ""}`;
  };
  const step = (one, back) => one
    ? `<a class="shootstep" href="${esc(href(one))}" title="${esc(one.name)}" aria-label="${esc(one.name)}">${mark(back ? STEP_BACK : STEP_ON, 14)}</a>`
    : `<span class="shootstep shootend" aria-hidden="true">${mark(back ? STEP_BACK : STEP_ON, 14)}</span>`;
  const on = shoots[here];
  // A shoot he named shows its number beside the name: "Malibu Pickup · Shoot 2".
  const named = (one) => (one.base && one.base !== one.name ? one.base : "");
  const row = (one) => {
    const is = one === on;
    return `<a class="shootrow${is ? " on" : ""}"${is ? ' aria-current="true"' : ""} href="${esc(href(one))}"><b>${esc(one.name)}</b><span>${esc([named(one), shootDay(one)].filter(Boolean).join(" · "))}</span><i>${esc(word(one))}</i></a>`;
  };
  return `<div class="shootpick">
    ${step(shoots[here - 1], true)}
    <details class="shootmenu"><summary aria-label="Shoots"><b>${esc(on.name)}</b><span>${esc([named(on), shootDay(on), word(on)].filter(Boolean).join(" · "))}</span>${mark(OPENS, 13)}</summary>
      <div class="shootlist">${shoots.map(row).join("")}</div></details>
    ${step(shoots[here + 1], false)}
  </div>`;
}

/**
 * **The one shoot picker** (stage 5 step 5, his approved design of
 * 2026-10-14, the same in Studio, the console and here): `‹ Style Server ·
 * Shoot 2 · Oct 6–7 · Next ▾ ›`. The list has All Shoots first, then each
 * shoot with its dates and Wrapped / Next / Upcoming; ‹ › step through the
 * same order. Every shoot keeps its own address (`/shoots/<slug>`), so a
 * crew link can still open on one; All Shoots is `/shoots/all-shoots`.
 * Drawn only with the portal's switch on (`portalmodes.js`); hidden, like
 * the old one, when there is one shoot. `shootPickerHere` in
 * `public/film.js` draws the same in the program's rail; change both.
 */
export function shootPicker(base, front, at) {
  const shoots = front.shoots || [];
  if (shoots.length < 2 || !front.shootOn) return "";
  const lead = leadShoot(front);
  const home = filmBase(base);
  const own = front.shootPages || {};
  const ALL = { slug: "all-shoots", name: "All Shoots", all: true };
  const order = [ALL, ...shoots];
  const here = Math.max(0, order.findIndex((one) => one.slug === front.shootOn.slug));
  const mine = front.shootOn.all ? [] : own[front.shootOn.slug] || [];
  const word = (one) => (one.all ? "" : one.status === "Wrapped" ? "Wrapped" : one === lead ? "Next" : "Upcoming");
  const named = (one) => (one.base && one.base !== one.name ? one.base : "");
  const sub = (one) => (one.all ? `${shoots.length} shoots` : [named(one), shootDay(one)].filter(Boolean).join(" · "));
  const tag = (one) => (word(one) ? `<i class="tag${word(one) === "Next" ? " next" : ""}">${esc(word(one))}</i>` : "");
  const href = (one) => {
    const page = mine.includes(at) ? (one.all ? "" : (own[one.slug] || [])[0] || "") : at === "home" ? "" : at;
    return `${home}/shoots/${one.slug}${page ? `/${page}` : ""}`;
  };
  const step = (one, back) => one
    ? `<a class="shootstep" href="${esc(href(one))}" title="${esc(one.name)}" aria-label="${back ? "Previous shoot" : "Next shoot"}">${mark(back ? STEP_BACK : STEP_ON, 14)}</a>`
    : `<span class="shootstep shootend" aria-hidden="true">${mark(back ? STEP_BACK : STEP_ON, 14)}</span>`;
  const on = order[here];
  const row = (one) => {
    const is = one === on;
    return `<a class="shootrow${is ? " on" : ""}"${is ? ' aria-current="true"' : ""} href="${esc(href(one))}"><b>${esc(one.name)}</b><span>${esc(sub(one))}</span>${tag(one)}</a>`;
  };
  return `<div class="shootpick pick5">
    ${step(order[here - 1], true)}
    <details class="shootmenu"><summary aria-label="Shoots"><b>${esc(on.name)}</b><span>${esc(sub(on))}</span>${tag(on)}${mark(OPENS, 13)}</summary>
      <div class="shootlist">${order.map(row).join("")}</div></details>
    ${step(order[here + 1], false)}
  </div>`;
}

/**
 * The film's own icon, drawn rather than fetched.
 *
 * The outline comes off its Notion row through `refresh.py`, so the page never
 * asks notion.so for a picture — which would say where he is, and would be a
 * hole in the page the day Notion is slow. `currentColor` is how it takes the
 * film's colour.
 */
function filmIcon(front) {
  const d = (front.mark && front.mark.path) || "";
  if (!d) return `<span class="filmicon" aria-hidden="true"></span>`;
  return `<span class="filmicon" aria-hidden="true"><svg viewBox="0 0 20 20" fill="currentColor">
    <path d="${esc(d)}"/></svg></span>`;
}

/**
 * The same mark again, as a file a browser tab can carry.
 *
 * **A document, not a fragment** — it carries its own `xmlns`, because an SVG
 * served on its own is parsed as XML rather than lifted out of HTML, and one
 * without a namespace is a blank tab rather than an error anybody would notice.
 *
 * The colour is baked in here rather than left to `currentColor`: nothing
 * inherits into a favicon, so a mark that relied on the page's accent would
 * come out black on black.
 */
export function filmIconSvg(front) {
  const d = (front && front.mark && front.mark.path) || "";
  if (!d) return null;
  const c = (front && front.mark && front.mark.colour) || "#E8E8EA";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">` +
         `<path fill="${esc(c)}" d="${esc(d)}"/></svg>`;
}

/**
 * The film's colour, as the accent for its whole page — and its shape.
 *
 * **The shape is here because every picture on the page is cropped to it.** His
 * rule, 2026-09-05: *"Conform everything to the project aspect ratio."* A bible
 * is a page of comparisons, and two frames of different shapes compare their
 * shapes before they compare anything he chose them for. The number is the
 * film's own ratio off the card; a film that has not got one leaves its
 * pictures their own shape rather than being given an invented one.
 */
function accent(front) {
  const c = (front.mark && front.mark.colour) || "";
  const r = Number(front.ratio);
  const said = [
    c ? `--accent:${esc(c)}` : "",
    Number.isFinite(r) && r > 0 ? `--filmratio:${r}` : "",
  ].filter(Boolean);
  return said.length ? ` style="${said.join(";")}"` : "";
}

/** The pages of the record, in the order the rail shows them. */
const RECORD = [
  { at: "script", name: "Script" },
  { at: "bible", name: "Visual Bible" },
  { at: "camera", name: "Camera Spec Sheet" },
  { at: "people", name: "People" },
  { at: "documents", name: "Documents" },
];

/**
 * **One rail, and everything is in it.** His brief, 2026-09-04: this is a crew
 * hub for a DP — the look, the plan, the kit — so the split that used to run
 * between four quiet pages and four app modes behind a door is not a split
 * anybody outside this repo would draw. Mood boards and the visual bible are
 * the same kind of thing; locations is reference too. They were on opposite
 * sides of a door only because the web app copied the Mac app's four modes, and
 * that shape was built for him working rather than for them reading.
 *
 * So the door is gone and these are peers. The rows that lead into the program
 * carry `app: true`, which is the only thing that still distinguishes them —
 * and it is a fact about how the page is drawn, not about what it is for.
 */
/* **One list, no headings.** His answer, 2026-09-08, to the objection he
   raised himself: *"'documents' is betraying, for example, what 'visual bible'
   is versus 'people'... The categorization is just kind of confusing."* He was
   right, and every alternative heading had the same fault — a Visual Bible and
   a call sheet are not one species however the group over them is worded.

   So there is no group name to be wrong. The film's own four screens first,
   then everything that is a page, then the ones he has added. **Plan, Look and
   Details are gone**; nothing else about a row changed.

   Still a list of groups rather than a flat array, deliberately: `whereAmI`,
   `railRows` and the visibility panel all walk this shape, and flattening it
   here would have meant touching four things to change one. A group with no
   head draws no head. */
const GROUPS = [
  { head: "", rows: [
    // The scenes the Shot List will show (Ref 1408): set-aside ones and, on
    // a shoot's tab, other shoots' are not counted, as the program counts.
    { at: "shotlist", name: "Shot List", app: true, count: (f) => shotListCount(f) },
    // **The script itself, its newest draft** (SL-1338) — read off the film,
    // so no source dot: like the Shot List, it is the film. `unfilled` keeps
    // it off every rail until a draft has been taken in.
    { at: "script", name: "Script", source: "film" },
    // The overheads, 2026-09-26: one per scene that has one, read only.
    { at: "diagrams", name: "Diagrams", app: true, count: (f) => f.counts.diagrams || 0 },
    { at: "locations", name: "Locations", app: true, count: (f) => f.counts.locations },
    { at: "schedule", name: "Schedule", app: true, count: (f) => f.counts.days },
    { at: "boards", name: "Reference Images", app: true, count: (f) => f.counts.boards },
    { at: "bible", name: "Visual Bible" },
    { at: "camera", name: "Camera Spec Sheet" },
    { at: "people", name: "People", count: (f) => f.crew.length },
    { at: "documents", name: "Documents", count: (f) => f.documents.length },
  ] },
];

/**
 * The rows the film itself provides — and, for a portal with no film behind
 * it, only the ones that need no film. The shot list, the locations, the
 * schedule and the reference images are the program's screens; a project
 * that has no film has nothing to draw in them, so they are not offered
 * rather than opening on nothing (2026-09-16).
 */
/** A page wearing the name he gave it on the portal (`front.labels`), if any. */
function labelled(front, p) {
  const called = (front.labels || {})[p.at];
  return called ? { ...p, name: called } : p;
}

function railRows(front) {
  const rows = GROUPS.flatMap((g) => g.rows).map((p) => labelled(front, p));
  return front.film === false ? rows.filter((p) => !p.app) : rows;
}

/** The program's own screens by key — the rows a portal with no film never offers. */
export const APP_ROWS = GROUPS.flatMap((g) => g.rows).filter((p) => p.app).map((p) => p.at);

/**
 * The rail, on every page including the home one.
 *
 * **Home has it too, which overturns his 2026-09-02 ruling** — and the reason
 * behind that ruling survives intact. It said home *is* the overview, so
 * nothing in a list should point at it; nothing here does. The film's name at
 * the top is the way home, no row is called Overview, and the four cards that
 * used to be the home page's only navigation are gone, so nothing is said
 * twice. What went with them: the four *"Not written yet / No Spec Sheet /
 * No Contacts / Empty"* boxes an unfilled film used to end on.
 *
 * **No well here.** A section's own list — the scenes, the places, the boards —
 * needs the engine, and these pages are drawn on the server from `front.json`
 * alone so that they arrive at once. The well opens inside the program, where
 * the film has actually been read. On these pages the section you are looking
 * at never has one, so nothing is missing.
 */
/**
 * **Every row and heading is named for the browser, so one that moves
 * slides.** The program's rail (`railRows` in `public/film.js`) names its rows
 * the same way, which is what lets a row travel across the door between a
 * record page and the app instead of being replaced — and lets the well
 * opening under a row push the rows beneath it down as a movement rather
 * than a jump. His report, 2026-09-16. A name must be one word the browser
 * accepts, so the key is cleaned first; two rails, one rule.
 */
function railName(kind, key) {
  return ` style="view-transition-name:${kind}-${String(key).replace(/[^A-Za-z0-9_-]/g, "_")}"`;
}

/**
 * **What the sidebar's editor needs to know about each page**, in one place so
 * the record's rail (`railFor`) and the program's (`HUB.rail`, built in
 * `worker.js`) cannot disagree. Keys are the ones the order is stored under.
 *
 * - `off`: pages a link holder is not shown (the Off Links tag and the dimming)
 * - `me`: pages hidden for him (a Seen On segment that is not lit)
 * - `rename`: pages he made himself, which can be renamed here
 * - `built`: the Built In pages with their state, for Add's switches
 * - `follow`: pages that follow a Google Doc, and whether they are following
 *   it now (`docfollow.js`) — the menu's Follow Google Doc switch
 */
export function offLinks(front, visible, at) {
  if (String(at).startsWith("doc:")) return (visible.documents || []).includes(String(at).slice(4));
  const sec = sectionNamed(at, front);
  return sec && sec.type === "board" ? sec.share !== "link" : (visible.sections || []).includes(String(at));
}

export function railEdit(front, visible = emptyVisible(), admin = false) {
  const keys = [...railRows(front).map((p) => p.at), ...sectionsOf(front).filter((p) => p.page).map((p) => p.at), ...pinnedDocs(front).map((d) => d.at)];
  const empty = new Set(unfilled(front, visible));
  const built = BUILT_IN.filter((p) => !(p.app && front.film === false)).map((p) => ({
    at: p.at, name: p.name,
    state: empty.has(p.at) ? "Empty" : p.app ? (front.live ? "Filled" : "") : "Notion",
    on: !offSidebar(front, p.at),
  }));
  return {
    off: keys.filter((at) => offLinks(front, visible, at)),
    rename: sectionsOf(front).filter((p) => p.page).map((p) => p.at),
    follow: Object.fromEntries((front.sections || []).filter((one) => one.follow).map((one) => [one.slug, Boolean(one.follow.on)])),
    // pages syncing from an outside document right now: "notion" or "gdoc" (`syncOf`)
    sync: Object.fromEntries((front.sections || []).map((one) => [one.slug, syncOf(one)]).filter(([, s]) => s).map(([at, s]) => [at, s.kind])),
    built,
    shelves: shelfNames(front),
  };
}

/** `data-follow` on a page that follows a Google Doc: 1 while it is following, 0 while stopped. */
function followFlag(edit, at) {
  return edit && edit.follow && at in edit.follow ? ` data-follow="${edit.follow[at] ? 1 : 0}"` : "";
}

/* **A small line icon on every row of the sidebar and card of the Library**,
 * by what the page is, or the one he picked (`front.icons`). The set is
 * `src/icons.js`; `public/icons.js` is the browser's copy. */
function iconOf(front, p) {
  return iconName(front.icons, p.doc ? `doc:${p.name}` : p.at, defaultIcon(p));
}

function rowIcon(front, p) {
  return `<span class="ico">${mark(ROW_ICONS[iconOf(front, p)], 15)}</span>`;
}

function libraryRow(base, front, at, visible, role, who, admin) {
  const n = libraryCount(front, visible, role, who, admin);
  return `<div class="libgroup"><a class="to librow${at === "library" ? " on" : ""}" data-deep="record" href="${esc(base)}/library"${railName("row", "library")}>${mark(ROW_ICONS.library, 17)}<span class="nm">Library</span>${
    n ? `<span class="n">${n}</span>` : ""}</a></div>`;
}

/**
 * **The documents pinned to the sidebar, as rows** (his ask, 2026-10-11: any
 * page of the portal can be on the sidebar): the ones this reader may see,
 * each opening its file or link. `railFor` draws them and the program's rail
 * (`HUB.rail.docs`) is sent the same list.
 */
export function railDocs(base, front, visible, role, admin) {
  return pinnedDocs(front)
    .filter((d) => maySee(visible, "documents", d.name, role) && meSees(visible, "documents", d.name, admin))
    .map((d) => ({ ...d, href: d.file ? fileUrl(base, d) : d.url }));
}

function railFor(base, title, front, at, who, role, back, share, visible = emptyVisible(), admin = false) {
  const sections = sectionsOf(front);
  const his = sections.filter((p) => p.page);
  // **Nothing there, nothing offered — to him too.** His ruling, 2026-09-23:
  // an empty Visual Bible or spec sheet is clutter in his own rail as much as a
  // reader's. The way to an empty page is Add's Built In table, which names
  // every one; the row he is standing on stays so the rail still says where he
  // is. See `unfilled`.
  const empty = new Set(unfilled(front, visible));
  // **A board he has not shared is not in anybody else's rail** — not greyed,
  // not locked: absent, for the reason a hidden section is (`boardOpen`).
  // **Hidden for him is out of his rail, not shut** (`meSees`): the row he is
  // standing on stays, as an empty one does.
  // **A page taken off the sidebar is off it for everybody**, and still opens
  // from its address and from the Library — the row he is standing on stays,
  // as an empty one does.
  const shows = (p) => maySee(visible, "sections", p.at, role) && boardOpen(p, who, admin)
    && (!empty.has(p.at) || p.at === at) && (meSees(visible, "sections", p.at, admin) || p.at === at)
    && (!offSidebar(front, p.at) || p.at === at)
    // **A mode that is off takes its pages off the rail** (portalmodes.js):
    // as a page in the Library is, still at its address.
    && (!(front.modesOff || []).includes(p.at) || p.at === at);
  // **One flat list of rows, then his own headings laid over it.** `inGroups`
  // in `front.js` is the rule, and `public/film.js` carries a copy — the
  // program draws its own rail and must not draw it differently to this one.
  const groups = railGroups(front, [...railRows(front), ...his, ...railDocs(base, front, visible, role, admin)], { empty: role === "editor" })
    // **A hidden section vanishes rather than showing as locked** — his ruling,
    // 2026-09-04. A row that says a thing exists and refuses it tells a crew
    // member exactly what they were not meant to know.
    .map((g) => ({ ...g, had: g.rows.length, rows: g.rows.filter(shows) }))
    // **A heading whose every row is hidden goes with them.** A crew member
    // reading a bare *Logistics* over nothing has been told there is something
    // there and refused it in the same breath.
    //
    // **But a heading he has just made and not filled yet stays, for him.** It
    // is empty because he is about to drag something into it, and a heading
    // that will not appear until it has rows is a heading with nowhere to drop
    // the first one.
    //
    // **Empty categories he did not make are not drawn at all** (his ruling,
    // 2026-10-11: *"no empty categories, keep things clean"*): the seven every
    // film starts with show only once something stands on them, for the owner
    // as for a crew member. One he added himself stays while it is empty.
    .filter((g) => g.rows.length || (role === "editor" && g.head && !g.had
      && !shelfList(front).some((one) => one.id === g.shelf && one.builtIn)));

  const editing = role === "editor";
  const edit = editing ? railEdit(front, visible, admin) : null;
  // **The headings are the categories** (2026-10-11): an editor's rail says
  // which category each heading is, and which are the seven that stay.
  const builtShelves = new Set(shelfList(front).filter((one) => one.builtIn).map((one) => one.id));
  const row = (p) => {
    // **People and Documents count what their page will show** — less what
    // is hidden on a link, or hidden for him.
    const n = p.doc ? "" : p.at === "people" || p.at === "documents" ? recordCount(p.at, front, visible, role, admin)
      : typeof p.count === "function" ? p.count(front) || "" : recordCount(p.at, front, visible, role, admin);
    // **One line, attributes together.** They were split across a newline,
    // which is valid HTML and invisible to every line-based check in
    // `checks.sh` — "the shot list opens in place" failed against markup that
    // was perfectly correct. A tag somebody greps for is a tag that stays on
    // one line.
    const deep = p.app ? "app" : "record";
    // **What an editor may do from the row** is told here, so the script asks
    // nothing: whether a link holder is shown it (dimmed, with a tag when not),
    // whether it is shown for him, and whether it can be renamed.
    const off = editing && (p.doc ? (visible.documents || []).includes(p.name) : edit.off.includes(p.at));
    const flags = editing
      ? ` data-links="${off ? 0 : 1}"${edit.rename.includes(p.at) || p.doc ? ' data-rename="1"' : ""}${followFlag(edit, p.at)}`
      : "";
    // **A pinned document is a row like any other** that opens its file or link
    // in a new tab (his ask, 2026-10-11), so it is not the program's to carry.
    const where = p.doc ? `data-outside="1" target="_blank" rel="noopener" href="${esc(p.href)}"` : `data-deep="${deep}" href="${esc(base)}/${p.at}"`;
    return `<a class="to${p.at === at ? " on" : ""}${empty.has(p.at) ? " empty" : ""}${off ? " offl" : ""}" data-key="${esc(p.at)}"${flags}${railName("row", p.at)} draggable="false" data-icon="${iconOf(front, p)}" ${where}><span class="dot"></span>${rowIcon(front, p)}<span class="nm">${esc(p.name)}</span>${editing && !p.doc ? syncDot(edit.sync[p.at]) : ""}${
      editing ? `<span class="off-tag" title="Private">${mark(LOCK, 12)}</span>` : ""}${n === "" ? "" : `<span class="n">${esc(String(n))}</span>`}</a>`;
  };

  // **Only an editor may drag it, and the mark says so once** rather than the
  // script asking about roles. `public/arrange.js` looks for exactly this.
  return `<nav class="rail"${role === "editor" ? ` data-arrange="${esc(base)}/order" data-base="${esc(base)}" data-shelves="${esc(JSON.stringify(shelfNames(front)))}" data-built="${esc(JSON.stringify(edit.built))}"${admin ? " data-admin" : ""}` : ""}>
    <div class="grabber" aria-hidden="true"></div>
    <div class="railtop">
      ${back ? `<a class="back" href="${esc(back)}">${mark(BACK, 13)}<span class="bw">Projects</span></a>` : ""}
      ${filmLine(base, front, at, title, admin, filmIcon(front))}
      ${shootTabs(base, front, at)}
      ${findButton()}
    </div>
    <div class="sectionhost"><div class="sections scrolls">
      ${
      // **The Library sits first, for everybody, and is not a row.** It holds
      // every page and document the film has; the rows below are only the ones
      // pinned to the sidebar. Not inside a `.group`, so dragging the rail never
      // files it and the saved order never names it.
      libraryRow(base, front, at, visible, role, who, admin)}
      ${groups.map((g, i) => `${g.head ? `<div class="grouphead"${railName("head", i)}>${esc(g.head)}</div>` : ""}
        <div class="group" data-head="${esc(g.head)}"${editing && g.shelf ? ` data-shelf="${esc(g.shelf)}"${builtShelves.has(g.shelf) ? " data-builtin" : ""}` : ""}>${g.rows.map(row).join("")}</div>`).join("")}
    </div></div>
    <div class="railfoot">${meCard(who, role, admin, base)}${
      // **Add is a button at the foot now, not a tool above it** (move 2): it
      // opens a menu where it stands. A plain link to the old Add page under
      // it, so it still goes somewhere with no script. Headings are edited on
      // the sidebar itself, so their tool is gone from here.
      role === "editor" ? `<a class="railadd" data-add href="${esc(base)}/add" title="New" aria-label="New">${mark(PLUS, 13)}</a>` : ""}${
      share ? shareButton(share.base, share.shared, share.at) : ""}</div>
  </nav>`;
}

/** **Find**, a field-like button under the film's name; it opens the ⌘K jump box (`jump.js`). */
function findButton() {
  return `<button type="button" class="railfind" data-find aria-label="Find">${mark(SEARCH, 13)}<span>Find</span><kbd>⌘K</kbd></button>`;
}

/**
 * **The film's name, and behind it the thing that used to sit at the foot of
 * the sidebar**: when Notion last spoke, and Refresh. Move 1 took the line out
 * of the list; it stays reachable here, for him, in the name's own menu.
 */
function filmLine(base, front, at, title, admin, icon, plainly = false) {
  const fresh = admin ? freshLine(base, front, at, plainly) : "";
  const when = admin && ago(front.updated);
  return `<div class="filmline"><a class="fh-who"${at === "home" ? " data-stowed" : ""} data-deep="home" href="${esc(base)}"${
    when ? ` title="Updated ${esc(when)}"` : ""}>${icon}<span class="filmname">${esc(title)}</span></a>${
    fresh ? `<details class="filmmenu"><summary aria-label="Project Menu" title="Project Menu">${mark(OPENS, 12)}</summary><div class="pmcard">${fresh}</div></details>` : ""}</div>`;
}

/**
 * **"Updated N minutes ago", on every page, for him.** Ref 1161, item 4: he
 * should always know how fresh the Notion words are without going to the
 * film's home to read its line. `updated` is what every refresh stamps —
 * `refresh.py` on the Mac, and `src/notion.js` here.
 *
 * **With Refresh beside it once the portal has its own Notion connection**
 * (Ref 1155). Until he gives it one, it is the line alone: a button that
 * could only refuse is worse than no button.
 *
 * Nothing for a film Notion does not feed and nothing ever stamped — there
 * is no freshness to report.
 */
export function freshLine(base, front, at, plainly = false) {
  const when = ago(front.updated);
  if (!when && !front.refresh) return "";
  if (!front.linked && !front.refresh) return "";
  const said = when ? `Updated ${when}` : "Not updated yet";
  if (!front.refresh) return `<div class="railfresh"><span>${esc(said)}</span></div>`;
  return `<form method="post" action="${esc(base)}/refresh" class="railfresh"${plainly ? ' target="_self"' : ""}>
    <span>${esc(said)}</span><input type="hidden" name="back" value="${esc(at || "home")}">
    <button type="submit" class="railfreshgo" title="Refresh from Notion">Refresh</button></form>`;
}

/**
 * **The phone's own furniture.** The rail is a column beside the work on a
 * desk; laid *above* the work on a phone it costs the top of the screen for
 * ever, and a rail that can hold a hundred and eighty scenes cannot afford
 * that. Measured before this was rewritten: 675 of 862 pixels were chrome.
 *
 * So on a phone the rail is a sheet, raised from a bar at the bottom — bottom
 * because that is the half of a phone a thumb reaches with the other hand on a
 * camera — and the work gets the screen. Both of these are `display:none` on
 * anything wider.
 */
function phoneParts(base, title, front, now, share, back = "", adds = false) {
  // **The way back, on a phone too.** His report, 2026-09-23: the rail's
  // Projects arrow is part of `.railtop`, which the phone's sheet hides — and
  // in the home-screen app there is no browser back button, so a film was a
  // room with no door. The arrow leads the bar, a thumb's width wide.
  //
  // **One dock, 2026-10-03 (phone move 1 of `design/30-portal-phone`).** The
  // top line is only the film's mark and name now, and pressing it opens the
  // sidebar sheet; Share moved into that sheet's header (`share` is no longer
  // drawn here, the rail's foot carries it). The bottom is one floating dock:
  // the page pill (opens the same sheet), Find (the ⌘K box) and, for an
  // editor, a round + that opens Add aimed at this page's heading.
  // `public/dock.js` listens for `data-dockfind` and `data-dockadd`.
  return `<header class="fh-topbar">
      ${back ? `<a class="tback" href="${esc(back)}" aria-label="Projects" title="Projects">${mark(BACK, 17)}</a>` : ""}
      <button type="button" class="tname" data-sheet="open" aria-label="Pages">${filmIcon(front)}<span>${esc(title)}</span></button>
    </header>
    <div class="fh-scrim" data-sheet="shut"></div>
    <div class="dock" data-dock>
      <button class="nowbar" data-sheet="open" type="button" aria-label="Pages">
        <span class="nn">${esc(now.name)}</span>
      </button>
      <button class="dockbtn dockfind" data-dockfind type="button" aria-label="Find">${mark(SEARCH, 17)}</button>
      ${adds ? `<a class="dockbtn dockadd" data-dockadd href="${esc(base)}/add" aria-label="Add">${mark(PLUS, 17)}</a>` : ""}
    </div>`;
}

/** What the bottom bar says you are looking at. */
function whereAmI(front, at) {
  for (const g of GROUPS) for (const p of g.rows) {
    if (p.at !== at) continue;
    const n = typeof p.count === "function" ? p.count(front) || "" : recordCount(p.at, front);
    return { name: p.name, n };
  }
  const his = sectionsOf(front).find((p) => p.at === at);
  return his ? { name: his.name, n: "" } : { name: "Overview", n: "" };
}

/**
 * **The four built-in sections, plus whatever he has named in Notion.**
 *
 * His question, 2026-09-03: *"In the future, what do i do if i want to add a
 * section like overheads for scene specific stuff?"* This is the answer, and it
 * is deliberately not a release: a Project Docs row with `Hub` ticked and a
 * `Section` name set becomes a section here, drawn from its own Notion page.
 * The four above stay hard-coded because they are not pages — they are the
 * camera database, the crew database, and prose off the film's own row.
 *
 * A name that collides with one of the four is not a row of its own, so nothing
 * he types in Notion can take over `/camera` and hide the spec sheet. One of
 * the four takes the page rather than dropping it: a section named `Visual
 * Bible` is drawn *on* the Visual Bible, under the film's own paragraphs.
 */
function sectionsOf(front) {
  const mine = new Set(RECORD.map((p) => p.at));
  const his = (front.sections || [])
    .filter((one) => one.slug && !mine.has(one.slug))
    .map((one) => ({ at: one.slug, name: one.name, page: true, title: one.title, source: one.source,
      type: one.type, share: one.share }));
  return [...RECORD.map((p) => labelled(front, p)), ...his];
}

/**
 * What each of the four sources is called, in words.
 *
 * **`SOURCE_SAID` in `public/film.js` is the same four**, because the program's
 * rail draws the same rows the record's pages do. Two lists that have to agree
 * is the shape of the identity drift `STATUS.md` records; change one and change
 * the other in the same breath.
 */
const SOURCE_SAID = {
  notion: "Live from Notion",
  "notion-once": "Copied from Notion once",
  here: "Written here",
  program: "From the Deck Editor",
};

/**
 * The mark saying where a row's words come from.
 *
 * His question, 2026-09-08, asked of People and true of all of them: *"is it
 * actually live updating?"* Nothing on this rail has ever said.
 *
 * **Never on a row that leads into the program.** The Shot List and the
 * Schedule are the film itself; a source mark there answers a question nobody
 * asked of them. **A built-in page with no section of its own is Notion's** —
 * People is the Crew database, the spec sheet is the Camera Spec Sheets row,
 * Documents is the rows he has ticked, and all three are live.
 */
/**
 * How long ago, in words a person uses.
 *
 * **Worked out as the page is drawn, not in the browser.** These pages are
 * rendered per request from `front.json`, so the answer is right at the moment
 * it is written, and it needs no script to be right on the connection where a
 * script has not arrived.
 */
export function ago(stamp) {
  const then = Date.parse(stamp || "");
  if (!Number.isFinite(then)) return "";
  const mins = Math.floor((Date.now() - then) / 60000);
  if (mins < 0) return "";
  if (mins < 2) return "just now";
  if (mins < 60) return `${mins} minutes ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} ${hours === 1 ? "hour" : "hours"} ago`;
  const days = Math.round(hours / 24);
  return `${days} ${days === 1 ? "day" : "days"} ago`;
}

/**
 * The line under a page's title, saying where it comes from and how fresh it is.
 *
 * **The slot already existed and was already half the answer.** Every one of
 * these pages carried a `sub` naming its origin — *From the Crew database*,
 * *Anything ticked Hub in Notion* — and none of them said the thing he
 * actually asked, 2026-09-08: *"Is it actually live updating?"* A page fed by
 * Notion and a page copied off Notion once read identically, and the
 * difference decides whether editing it in Notion reaches the site at all.
 *
 * So the origin keeps its words and gains two facts: whether it is still being
 * fed, and when it last was. **Not a sentence** — his law of 2026-08-21: the
 * app names things, it does not explain them.
 */
function sourceSub(front, source, origin) {
  const said = SOURCE_SAID[source] || "";
  const when = source === "notion" ? ago(front.updated) : "";
  const bits = [origin || said, when ? `updated ${when}` : ""].filter(Boolean);
  // **In the page's ⋯ menu, not under its title** (his pick, 2026-10-03,
  // `design/31-portal-quiet.html` 3): the fact stays one tap away.
  return bits.length ? `<div class="pmnote">${esc(bits.join(" · "))}</div>` : "";
}

/**
 * **The control that says where a page's words come from.** Ref 871.
 *
 * Until this existed the source was a value with no control: honest and
 * useless. Worse, the only way to take a snapshot of a Notion page was to have
 * an agent copy it — which stamped the row `by: "mcp"` and locked Notion out
 * **for good**, with no way back but unticking `Hub` in Notion and ticking it
 * again. His decision, 2026-09-08: *"Your recommendation is correct"* — the
 * source decides who wins, and **it is changeable both ways, so nothing is ever
 * a one-way door.**
 *
 * **A plain form posting to its own address**, the same bargain the visibility
 * panel strikes: it decides whether his writing survives the next refresh, and
 * a control that only works once a script has arrived is a control that does
 * nothing on the connection where it matters. `refresh.py`'s `both_roads` and
 * its `agents` set read what this writes.
 *
 * **Not offered on a deck.** Its words come out of the Deck Editor, and handing
 * one to Notion would mean the next publish quietly taking it back.
 */
function sourceForm(one, source, role) {
  if (role !== "editor" || source === "program") return "";

  /**
   * **Nothing in Notion names this page, so there is no choice to offer.**
   *
   * His report, 2026-09-08: *"live from notion and copied from notion still
   * dont do anything."* They could not. A page he made on the portal has no
   * Hub-ticked Project Docs row behind it, so setting it *Live from Notion*
   * changed a word and waited for a refresh that would never find anything.
   *
   * The two sentences here are both on the short list the law allows: **why
   * something cannot work here**, and **the one thing he must do himself,
   * once**. There is no third way to say it — the portal cannot reach Notion
   * and cannot connect a page to one; only Notion can.
   */
  if (!one.notion) {
    // **No radio list, because there is nothing to choose between.** A control
    // offering one option that is already set is the same lie in a smaller
    // hat. The only button here is the way *out* of a wrong state — a page set
    // to Live from Notion before this knew better, still waiting for a refresh
    // that will never find it.
    const wrong = source !== "here"
      ? `<input type="hidden" name="source" value="here">
         <div class="seefoot"><button class="savebtn" type="submit">Write Here</button></div>`
      : "";
    return `<form method="post" class="seeform srcset">
      <p class="warn">Not linked to Notion</p>
      ${wrong}
    </form>`;
  }

  const pick = (value) => `<label class="seerow">
    <input type="radio" name="source" value="${esc(value)}"${value === source ? " checked" : ""}>
    <span class="seename">${esc(SOURCE_SAID[value])}</span>
  </label>`;
  return `<form method="post" class="seeform srcset">
    ${
      // **The one sentence the law allows here**: what the change will cost.
      // Handing a page back is not undoable by pressing the button again — the
      // words on it are replaced by Notion's.
      source === "notion" ? "" : `<p class="warn">Notion overwrites on refresh</p>`
    }
    <div class="seelist">${PAGE_SOURCES.map(pick).join("")}</div>
    <div class="seefoot"><button class="savebtn" type="submit">Set Source</button></div>
  </form>`;
}

/**
 * **A written page, with something to write in.** His report, 2026-09-08:
 * *"They all lead to empty ... and have no function."*
 *
 * A page made on the portal used to be an address and a name and nothing else.
 * Only an agent could put words on it, through `set_page` — so the one type
 * called *Written Page* was the one type he could not write. This is the box.
 *
 * **Markdown, and the same Markdown `set_page` takes.** `pageFrom` in
 * `paper.js` makes the page and `markdownFrom` reads it back out, and the two
 * round-trip — so opening this on a page an agent wrote shows what the agent
 * wrote, not an empty box that would wipe it on Save.
 *
 * **Open when the page is empty, folded away when it is not.** An empty page
 * for an editor is not a state to be reported, it is a thing to be filled: the
 * box replaces the "Empty" line rather than sitting under
 * it. On a page with words on it the box is a `<details>` — his writing is what
 * the page is for, and a text area the height of it is not.
 */
function writeBox(said, open, bare = false) {
  const box = `<form method="post" class="seeform writebox">
    <textarea name="markdown" rows="${open && !bare ? 14 : 18}" spellcheck="true"
      placeholder="Write here">${esc(said)}</textarea>
    <div class="seefoot"><button class="savebtn" type="submit">Save</button></div>
  </form>`;
  // **Opened from the page menu** (Ref 1153), the box is the whole panel.
  if (bare) return box;
  return open
    ? `<div class="blockhead">Write</div>${box}`
    : `<details class="writefold"><summary>Write</summary>${box}</details>`;
}

/**
 * **Taking a page off the film.** His question, 2026-09-08: *"how do i delete a
 * page?"* He could not — Add was built and its other half was not, so
 * everything he made on the portal was permanent unless he asked somebody.
 *
 * **Folded away, and it says what it costs.** *Report, never invent — and never
 * destroy*: deleting is a person's decision, so it takes two presses and the
 * second one is under a sentence saying what goes with it. A `<details>` is the
 * two steps with nothing running, which matters because this is the one control
 * on the page that cannot be undone.
 *
 * **Only where Notion does not name it.** A page Notion names comes straight
 * back at the next refresh — removing it here would look like it worked and
 * quietly undo itself within the hour, which is worse than refusing.
 */
function removeBox(one, role) {
  if (role !== "editor") return "";
  if (one.notion) {
    return `<p class="warn">Rename in Notion</p>`;
  }
  const words = one.by === "deck"
    ? "Deletes the page. The PDF stays."
    : "Deletes the page.";
  // **Still two presses** — the menu item, then this button under the
  // sentence saying what goes. It used to be a fold at the foot of the page;
  // since Ref 1153 the page menu opens it (`pageAct`).
  return `<form method="post">
      <p class="warn">${esc(words)} Nothing else on the film changes.</p>
      <input type="hidden" name="remove" value="${esc(one.slug)}">
      <div class="seefoot"><button class="savebtn danger" type="submit">Remove ${esc(one.name)}</button></div>
    </form>`;
}

/**
 * **The mark on a sidebar row whose page syncs from an outside document**
 * (2026-10-17, his ask). Editors only: the old four-colour source dot is gone,
 * because it called People and Documents Notion's long after they were not.
 * `syncDot` in `public/film.js` is the same mark on the program's rail.
 */
export function syncDot(kind) {
  if (!kind) return "";
  const said = kind === "gdoc" ? "Synced from Google Doc" : "Synced from Notion";
  return `<span class="syncico" title="${said}" aria-label="${said}">${mark(SYNC, 12)}</span>`;
}

/** Two arrows chasing each other round: syncing. */
const SYNC = '<path d="M12.6 6.4A4.8 4.8 0 0 0 4 4.6L3 5.6"/><path d="M3 2.8v2.8h2.8"/><path d="M3.4 9.6A4.8 4.8 0 0 0 12 11.4l1-1"/><path d="M13 13.2v-2.8h-2.8"/>';
/** An arrow leaving the page. */
const OUT = '<path d="M5 11 11 5M6.5 5H11v4.5"/>';

/**
 * **The line under a page's title saying which document it syncs from** —
 * the document's name, a link that opens it, and when it last synced.
 * His ask, 2026-10-17: *"an indicator on a page ... so that I understand that
 * that one's syncing to a document, and then I'll link to that document."*
 *
 * **Editors only.** A crew member does not need to know where the words are
 * typed, and a link into his Notion is a sign-in wall to them. A page drawn
 * from a Google Doc already carries its own Open the Google Doc button.
 */
export function syncLine(front, one, role, state = null) {
  if (role !== "editor") return "";
  const sync = syncOf(one);
  if (!sync) return "";
  const gdoc = sync.kind === "gdoc";
  const title = gdoc ? (state && state.title) || "Google Doc" : sync.title || "Notion";
  const when = gdoc ? ago(state && state.drawn) : ago(sync.when || front.updated);
  const bad = gdoc && state && state.trouble;
  return `<p class="syncline"><a href="${esc(sync.url)}" target="_blank" rel="noopener">${mark(SYNC, 13)}<span>Synced from ${esc(title)}</span>${mark(OUT, 12)}</a>${
    bad ? `<span class="syncbad">Last sync failed</span>` : when ? `<span class="syncwhen">${esc(when)}</span>` : ""}</p>`;
}

/** The same, said in the page's ⋯ menu: words only, no link. */
function syncNote(front, one, state = null) {
  const sync = syncOf(one);
  if (!sync) return "";
  const gdoc = sync.kind === "gdoc";
  const title = gdoc ? (state && state.title) || "Google Doc" : sync.title || "Notion";
  const when = gdoc ? ago(state && state.drawn) : ago(sync.when || front.updated);
  return `<div class="pmnote">${esc([`Synced from ${title}`, when].filter(Boolean).join(" · "))}</div>`;
}

/**
 * **The rows with nothing behind them.** His walkthrough, 2026-09-23: a new
 * film's rail offered Visual Bible, Camera Spec Sheet, People and Documents to
 * everybody it was shared with, each opening on *Nothing yet*.
 *
 * **Visibility's own road, not a second one.** A reader who is not an editor
 * is hidden these exactly as a section Visibility hides is hidden — gone from
 * both rails (`railFor` here, `HUB.rail.hidden` in `public/film.js`). An editor
 * still sees every row, drawn quiet (`.to.empty`), because an empty row is his
 * way in to filling it.
 *
 * **Empty means provably empty.** People and Documents count only what the
 * reader may see; the bible and the spec sheet are empty only with no words,
 * no files, no notes and no Notion page folded onto them. The program's three
 * screens are judged on the film's own counts and never on a card nobody has
 * read the film for (`front.live`). The Shot List is the film and always shows.
 */
export function unfilled(front, visible = emptyVisible()) {
  const empty = [];
  const named = (at) => Boolean(sectionNamed(at, front));
  // **The bible is a bible, not the film page's paragraphs.** His ruling,
  // 2026-09-23: the Director's Note and Visual Language are the film's words
  // and live on its front page; the Visual Bible is made in the Deck Editor.
  // So only a page of its own — a deck, or a Notion page he named Visual
  // Bible — fills it.
  if (!named("bible")) empty.push("bible");
  if (!(front.scripts || []).length) empty.push("script");
  if (!hasCamera(front.camera) && !(front.camera_files || []).length && !front.camera_notes && !named("camera")) {
    empty.push("camera");
  }
  if (!(front.crew || []).some((one) => maySee(visible, "crew", one.name, "viewer"))) empty.push("people");
  if (!(front.documents || []).some((doc) => maySee(visible, "documents", doc.name, "viewer"))) empty.push("documents");
  if (front.live && front.film !== false) {
    const c = front.counts || {};
    if (!c.locations) empty.push("locations");
    if (!c.diagrams) empty.push("diagrams");
    if (!c.days) empty.push("schedule");
    if (!c.boards) empty.push("boards");
  }
  return empty;
}

/** **What the page will show, counted** — not what Notion holds. */
function recordCount(at, front, visible = emptyVisible(), role = "editor", admin = false) {
  const seen = (kind, name) => maySee(visible, kind, name, role) && meSees(visible, kind, name, admin);
  if (at === "people") return front.crew.filter((one) => seen("crew", one.name)).length || "";
  if (at === "documents") return front.documents.filter((doc) => !isArchived(front, `doc:${doc.name}`) && seen("documents", doc.name)).length || "";
  return "";
}

function sectionNamed(at, front) {
  return (front.sections || []).find((one) => one.slug === at) || null;
}

/** The first few words of something, cut at a word rather than mid-syllable. */
function opening(words, most) {
  const said = String(words || "").replace(/\s+/g, " ").trim();
  if (said.length <= most) return said;
  const cut = said.slice(0, most);
  return cut.slice(0, cut.lastIndexOf(" ")) + "…";
}

/**
 * **A line of what is actually inside a section, drawn from the section.**
 *
 * His instruction, 2026-09-03: the page should say what is here *"without
 * literally saying 'Shotlister is an app containing locations, shot list,
 * reference images'"*. A sentence explaining the page is the thing he has
 * banned everywhere else in this program, and it would be no better here.
 *
 * So nothing is explained: each section shows a piece of itself, and a crew
 * member reads four real things rather than four nouns. *Alexa 35 · Zeiss
 * Super Speeds* is a camera department knowing at a glance that the spec sheet
 * is filled in; *Clara Moreau, Max Kowalski…* is knowing the contacts are
 * there. An empty section says it is empty and stays in the list, because
 * "no camera spec yet" is also worth knowing on a shoot in two weeks.
 */
function recordPreview(at, front) {
  // **The bible reads its own words first.** His page is folded onto this slug,
  // and its Notion title — *"Call Her Back - Visual Language Bible"* — says the
  // name of the film and the name of the page and nothing about the look. The
  // two paragraphs beneath it do.
  if (at === "bible") return "";
  if (at === "script") return opening(((front.scripts || [])[0] || {}).name, 96);
  const his = sectionNamed(at, front);
  if (his) return opening(his.title === his.name ? "" : his.title, 96);
  if (at === "camera") {
    const cam = front.camera || {};
    return opening([cam.body, oneLine(cam.lenses)].filter(Boolean).join(" · "), 96);
  }
  if (at === "people") {
    return opening(front.crew.map((one) => one.name).filter(Boolean).join(", "), 96);
  }
  return opening(front.documents.map((doc) => doc.name).filter(Boolean).join(", "), 96);
}

const NOTHING_YET = {
  bible: "Not written yet",
  camera: "No Spec Sheet",
  people: "No Contacts",
  documents: "Empty",
};

/**
 * **The home page: who the film is, and nothing else.**
 *
 * The big title, the credits, the vitals and the logline. **No cards and no
 * door** — the four record cards existed to be a menu and the rail is the menu,
 * and the door existed to cross into a program that is no longer somewhere
 * else. What went with the cards: the four *"Not written yet / No spec sheet
 * yet / No Contacts / Empty"* boxes an unfilled film used to
 * end on, which was the worst first impression the page could make.
 *
 * **The name lives here in its big form only** — his instruction, 2026-09-04 —
 * and travels into the rail when you go somewhere, which is why `athome` hides
 * the rail's copy. Two elements may never share a `view-transition-name` at
 * once; that aborts the transition outright rather than degrading.
 *
 * **Camera is in the vitals** because it is the fact a crew member asks for
 * most often and it was otherwise two clicks away.
 *
 * The director's note is still not here, 2026-09-03: it was a second block of
 * prose before the page showed a single thing it holds, and it is on the
 * Visual Bible page, which is where somebody goes looking for it.
 */
export function homeBody(base, title, role, who, front, shared, many, visible = emptyVisible(), admin = false, since = []) {
  const share = shareFor(base, role, who, shared);
  return `<div class="fh2 deep athome"${accent(front)}>
    ${railFor(base, title, front, "home", who, role, many ? "/" : "", share, visible, admin)}
    ${phoneParts(base, title, front, { name: "Overview", n: "" }, share, many ? "/" : "", role === "editor")}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="homewrap hm">
      <div class="hm-main">
        <div class="title">${filmIcon(front)}<h1 class="filmname">${esc(title)}</h1></div>
        <p class="credits">${[
          front.director ? `Directed by <em>${esc(front.director)}</em>` : "",
          front.producer ? `Produced by <em>${esc(front.producer)}</em>` : "",
          ...(front.credits || []).map((c) => `${esc(creditWords(c.role))} <em>${esc(creditLine(c.people))}</em>`),
          [front.type, front.length].filter(Boolean).join(" ")
            ? esc([front.length, front.type].filter(Boolean).join(" ")) : "",
        ].filter(Boolean).join(" · ")}</p>
        ${homeFacts(role, front)}
        ${front.logline ? `<p class="logline hm-fold" data-fold>${esc(front.logline)}</p>${logFold}` : ""}
        ${selectsBlock(base, front.released)}
        ${[
          // **What this shoot changes** (SL-1396) — his own line off the Shoots
          // row, under the shoot's name, so the tab says which shoot it is.
          front.shootOn && front.shootOn.changes
            ? `<div class="said"><div class="blockhead">${esc(front.shootOn.name)}</div><p>${esc(front.shootOn.changes)}</p></div>` : "",
          // **The film's own words, on the film's own page** — moved off the
          // Visual Bible, his ruling of 2026-09-23.
          front.note ? `<div class="said"><div class="blockhead">Director's Note</div><p>${esc(front.note)}</p></div>` : "",
          front.look ? `<div class="said"><div class="blockhead">Visual Language</div><p>${esc(front.look)}</p></div>` : "",
        ].join("")}
        ${nextDayLine(base, front)}
        ${sinceLooked(base, since)}
      </div>
    </div></div></main>
  </div>`;
}

/**
 * **Next Day — one line, not three cards** (his calm pass, 2026-10-03): the
 * next shoot day, its number, how far off, and what is on it (a count off the
 * scene list, a scene on exactly one day), linking to Schedule. A film with no
 * days ahead draws nothing, not a hole. The days are `shootDaysOf` — the
 * schedule's, or Notion's range — and on a film with several Shoots `shotView`
 * has already narrowed them to the shoot being looked at.
 */
function nextDayLine(base, front) {
  const all = shootDaysOf(front);
  const at = all.findIndex((one) => awaySaid(one.date) !== "" || one.date === todayIso());
  if (at < 0) return "";
  const one = all[at];
  const parts = dayParts(one.date);
  const away = awaySaid(one.date) || "today";
  const list = Array.isArray(front.scene_list) ? front.scene_list : [];
  const n = list.filter((scene) => scene.day === one.date && !scene.archived).length;
  return `<a class="hm-nd" data-coming href="${esc(base)}/schedule">
    <span class="hm-ndl">Next Day</span><span class="hm-ndt"><b>${esc(`${parts.weekday} ${parts.day} ${parts.month.slice(0, 3)}`)}</b> · ${esc(one.label || `Day ${at + 1}`)} · <em>${esc(away)}</em></span>
    <span class="hm-ndn">${n ? `${n} ${n === 1 ? "scene" : "scenes"}` : "No scenes yet"}</span>
  </a>`;
}

const MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** A time in the short words a feed line ends with. */
function sinceSaid(stamp) {
  const mins = Math.floor((Date.now() - Date.parse(stamp)) / 60000);
  if (!Number.isFinite(mins) || mins < 0) return "";
  if (mins < 2) return "Just now";
  if (mins < 60) return `${mins} min`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours} h`;
  if (hours < 48) return "Yesterday";
  const days = Math.round(hours / 24);
  if (days < 60) return `${days} days`;
  const at = new Date(stamp);
  return `${MONTHS_SHORT[at.getUTCMonth()]} ${at.getUTCDate()}`;
}

/**
 * **Since You Looked** — what changed since this browser last opened the film,
 * three lines at most, newest first; **nothing new, no block**. The list is
 * `changesOf` in `since.js`, already narrowed to what this person may see. The
 * block is drawn hidden and the script shows it only for rows newer than this
 * browser's last visit (kept per film in localStorage; a reload in the same
 * tab keeps what that visit found, and the first visit finds nothing).
 */
function sinceLooked(base, since) {
  if (!since || !since.length) return "";
  const rows = since.map((one) => `<a class="hm-fr" href="${esc(one.href)}" data-at="${esc(one.at)}"><i></i><span><b>${esc(one.said)}</b> ${esc(one.what)}</span><time>${esc(sinceSaid(one.at))}</time></a>`).join("");
  return `<section class="hm-blk hm-feed" data-since="${esc(base)}" hidden><h2><span>Changes</span></h2>${rows}</section>
  <script type="module">
    try {
      const box = document.querySelector("[data-since]");
      const id = "since:" + box.dataset.since;
      let prev = null;
      try { prev = sessionStorage.getItem(id); } catch {}
      if (prev === null) { try { prev = localStorage.getItem(id); } catch {} }
      try { sessionStorage.setItem(id, prev || ""); } catch {}
      try { localStorage.setItem(id, new Date().toISOString()); } catch {}
      const rows = [...box.querySelectorAll("[data-at]")];
      let kept = 0;
      for (const row of rows) {
        if (prev && row.dataset.at > prev && kept < 3) { row.classList.add("new"); kept += 1; } else row.remove();
      }
      if (kept) box.hidden = false; else box.remove();
    } catch {}
  </script>`;
}

/**
 * **One quiet line of facts under the credits**: Status · Shoot dates · Format
 * · Camera, whichever the film has. The counts live on the sidebar's rows,
 * people on People, and when Notion last fed the film in the film's menu. An
 * editor is still warned when Notion has no link to this film (a warning, not
 * a label).
 */
function homeFacts(role, front) {
  const cam = front.camera || {};
  const facts = [front.status, shootDates(front.shoot), ratioSaid(front.ratio), cam.body || ""].filter(Boolean);
  const warn = role === "editor" && front.linked !== "link" ? notionLine(front, role) : "";
  return facts.length || warn
    ? `${facts.length ? `<p class="hm-facts">${facts.map((f, i) => `<span${i ? "" : ' class="strong"'} data-copy>${esc(f)}</span>`).join(" · ")}</p>` : ""}${warn ? `<div class="hm-chipwarn">${warn}</div>` : ""}`
    : "";
}

/** The logline's `More` toggle, shown by the script only when it runs past three lines. */
const logFold = `<button type="button" class="hm-foldbtn" data-foldbtn hidden>More</button>
  <script type="module">
    try {
      const text = document.querySelector("[data-fold]");
      const btn = document.querySelector("[data-foldbtn]");
      const fits = () => { text.classList.add("clamped"); const over = text.scrollHeight > text.clientHeight + 1; btn.hidden = !over; if (!over) text.classList.remove("clamped"); };
      fits();
      btn.addEventListener("click", () => { const open = text.classList.toggle("clamped") === false; btn.textContent = open ? "Less" : "More"; });
      addEventListener("resize", () => { if (!text.classList.contains("clamped") && btn.textContent === "More") fits(); });
    } catch {}
  </script>`;

/**
 * Whether Notion is feeding this film at all, and how it found it.
 *
 * His question, 2026-09-08: *"when you're making a new project, how do you even
 * set that up in the first place, and what sets that up? ... It just sounds
 * flimsy."*
 *
 * It is flimsy, and this says so. A film with no stored link is matched to its
 * Notion row **by its title**, so renaming either silently ends every update —
 * no error, no empty page, just yesterday's card forever. That is worth the one
 * sentence his 2026-08-21 law allows: a warning about something that cannot
 * work, rather than a label naming a thing.
 *
 * **His alone.** A crew member reading a link has nothing to do with how the
 * words got here, and a warning they cannot act on is noise on their page.
 */
function notionLine(front, role) {
  if (role !== "editor") return "";
  if (front.linked === "link") {
    const when = ago(front.updated);
    return `<p class="sub">Notion${when ? ` · updated ${esc(when)}` : ""}</p>`;
  }
  if (front.linked === "name") {
    return `<p class="warn unfed">Linked by title</p>`;
  }
  return `<p class="warn unfed">Not linked to Notion</p>`;
}

/**
 * The next shoot day, as a date rather than as a number of them.
 *
 * `days` is already in the record and already drawn as a calendar on the
 * schedule; here it answers the single question a collaborator opens the link
 * to ask. A day in the past is not next, and a film with none says nothing —
 * `fact` drops an empty value rather than printing a hole.
 */
function nextDay(front) {
  const soon = nextShootSaid(front);
  return soon ? soon.said : "";
}

/**
 * **The next shoot day, as a shelf card says it** — the date and how far off,
 * coloured the way Coming Up had it (`.when` in `front.css`). `null` for a
 * film with nothing ahead, so a card draws nothing rather than a hole.
 */
function nextShootSaid(front) {
  const soon = shootDaysOf(front).map((one) => one.date)
    .find((date) => awaySaid(date) !== "" || date === todayIso());
  if (!soon) return null;
  const at = dayParts(soon);
  const away = awaySaid(soon) || "today";
  // One look (2026-10-16): the card says "12 days", and only a shoot this
  // close wears a colour (amber, the kit's `soonDays`); further off is grey.
  const days = Math.round((Date.parse(`${soon}T00:00:00Z`) - Date.parse(`${todayIso()}T00:00:00Z`)) / 86400000);
  const short = away.replace(/ away$/, "");
  return {
    said: `${at.weekday} ${at.day} ${at.month.slice(0, 3)}`,
    away: short.charAt(0).toUpperCase() + short.slice(1),
    soon: days >= 0 && days <= 14,
  };
}

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

/**
 * **A film's shoot days, soonest first — the schedule's, or Notion's.** His
 * report, 2026-09-23: Halcyon's shoot dates were not detected. It is a portal
 * with no film behind it, so it has no schedule, and Next Day reads the
 * schedule alone. Its Notion row does carry Shoot Dates (`front.shoot`),
 * so when there are no days of the film's own, every date in that range is a
 * day, called by its place in the run. The film's own schedule, when there is
 * one, wins — it is the more exact of the two — **but only while it agrees
 * with Notion.** His report, 2026-09-25: the home page did not follow a shoot
 * date changed in Notion. Mirrorland' row said 14 Nov; its schedule still had
 * two days dated 11–12 Oct from before, so Next Day said October while the
 * film's own page said November. Notion is where he moves a shoot, so a
 * schedule with any day outside Notion's range is a schedule not yet moved,
 * and Notion's range is drawn instead.
 */
function shootDaysOf(front) {
  const own = (front.days || []).filter((d) => d.date).slice()
    .sort((a, b) => a.date.localeCompare(b.date));
  const shoot = front.shoot || {};
  if (!/^\d{4}-\d{2}-\d{2}$/.test(shoot.start || "")) return own;
  const end = /^\d{4}-\d{2}-\d{2}$/.test(shoot.end || "") && shoot.end >= shoot.start ? shoot.end : shoot.start;
  if (own.length && own.every((d) => d.date >= shoot.start && d.date <= end)) return own;
  const out = [];
  const at = new Date(`${shoot.start}T00:00:00Z`);
  // A cap, so a mistyped year in Notion is a short list rather than a long one.
  while (out.length < 120) {
    const date = at.toISOString().slice(0, 10);
    if (date > end) break;
    out.push({ date, label: `Day ${out.length + 1}` });
    at.setUTCDate(at.getUTCDate() + 1);
  }
  return out;
}

/**
 * **A page of the record, in the same frame as everything else.**
 *
 * The rail is identical on every page now, home included, so moving between
 * these is the one move the whole portal has: the rail sits still and only the
 * middle changes. There is no bar over the pane any more — who you are and
 * Share live in the rail's foot, which is what these pages had been missing
 * entirely: you could not see your own sign-in or share the film from the
 * Visual Bible, Camera, People or Documents.
 */
export function recordBody(base, title, role, who, front, at, shared, tree, many, visible = emptyVisible(), admin = false, made = "", extra = {}) {
  const share = shareFor(base, role, who, shared, at);
  return `<div class="fh2 deep"${accent(front)}>
    ${railFor(base, title, front, at, who, role, many ? "/" : "", share, visible, admin)}
    ${phoneParts(base, title, front, whereAmI(front, at), share, many ? "/" : "", role === "editor")}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="inner">${
      // **One of the four built in wins its own address.** A Notion section can
      // carry the same slug — the Visual Bible does, on purpose — and drawing
      // it as a plain section here threw away everything that page holds of its
      // own: the film's two paragraphs went, and the page came back as the
      // Notion tree and nothing else. The built-in page is handed the tree and
      // draws both.
      RECORD.some((p) => p.at === at)
        ? recordPage(base, front, at, role, visible, tree, made, admin, extra)
        : sectionPage(base, front, at, tree, made, role, admin, visible, extra)
    }</div></div></main>
  </div>`;
}

/**
 * **A Notion page, drawn in this program's own hand.**
 *
 * Not an embed and not an iframe: the blocks arrive as a small tree from
 * `refresh.py` and are drawn here with the portal's own type and spacing, so a
 * bible reads like the rest of the film's page and works with no Notion
 * account. That is the whole point — a pinned Notion link sends a crew member
 * to a sign-in wall this program knows nothing about, which is the seam the
 * crew-hub work exists to close.
 *
 * **Only the blocks his own pages actually use** — headings, paragraphs,
 * pictures, callouts, quotes, lists, toggles and columns. A Notion page can
 * hold thirty kinds of block and drawing all of them would be building a second
 * Notion. Anything else is dropped by `refresh.py` before it ever gets here.
 *
 * A toggle is drawn open. It is closed in Notion to keep a long page navigable
 * while writing; on a phone on a set, a section that hides its own contents
 * behind a triangle is a section nobody reads.
 */
function saidAs(rich) {
  return (rich || []).map((bit) => (bit.u
    ? `<a href="${esc(bit.u)}" target="_blank" rel="noopener noreferrer">${esc(bit.s)}</a>`
    : esc(bit.s))).join("");
}

function drawBlocks(base, tree, deep = 0) {
  const out = [];
  let list = null;
  const shut = () => { if (list) { out.push(`<ul class="nlist">${list.join("")}</ul>`); list = null; } };
  for (const node of tree || []) {
    if (node.t !== "li") shut();
    const kids = node.k && node.k.length ? drawBlocks(base, node.k, deep + 1) : "";
    if (node.t === "li") {
      (list = list || []).push(`<li>${saidAs(node.r)}${kids}</li>`);
      continue;
    }
    if (node.t === "h1") out.push(`<h2 class="nh1">${saidAs(node.r)}</h2>${kids}`);
    else if (node.t === "h2") out.push(`<h3 class="nh2">${saidAs(node.r)}</h3>${kids}`);
    else if (node.t === "h3") out.push(`<h4 class="nh3">${saidAs(node.r)}</h4>${kids}`);
    else if (node.t === "p") out.push(`<p class="np">${saidAs(node.r)}</p>${kids}`);
    else if (node.t === "quote") out.push(`<blockquote class="nq">${saidAs(node.r)}${kids}</blockquote>`);
    else if (node.t === "callout") out.push(`<div class="ncall">${saidAs(node.r)}${kids}</div>`);
    else if (node.t === "hr") out.push(`<hr class="nhr">`);
    else if (node.t === "img") {
      out.push(`<figure class="nfig"><img data-look="page" src="${esc(pictureUrl(base, node.src))}" alt="${esc(node.cap || "")}" loading="lazy">
        ${node.cap ? `<figcaption>${esc(node.cap)}</figcaption>` : ""}</figure>`);
    } else if (node.t === "video") {
      out.push(videoBlock(base, node));
    } else if (node.t === "file") {
      // A file he put in the notes: one we hold opens; a link goes out.
      out.push(documentCard(base, { name: node.name, file: node.src, bytes: node.bytes, url: node.url }));
    } else if (node.t === "table") {
      // **Drawn as a table, not flattened into lines.** His spec sheets keep
      // resolutions in one, and a table read as prose is not a table.
      const rows = (node.k || []).filter((r) => r.t === "trow");
      const head = node.head && rows.length ? rows[0] : null;
      const rest = head ? rows.slice(1) : rows;
      const cells = (row, tag) => row.c.map((c) => `<${tag}>${saidAs(c)}</${tag}>`).join("");
      out.push(`<div class="ntwrap"><table class="ntab">
        ${head ? `<thead><tr>${cells(head, "th")}</tr></thead>` : ""}
        <tbody>${rest.map((r) => `<tr>${cells(r, "td")}</tr>`).join("")}</tbody>
      </table></div>`);
    } else if (node.t === "toggle") {
      out.push(`<section class="ntog"><h4 class="nh3">${saidAs(node.r)}</h4>${kids}</section>`);
    } else if (node.t === "columns") out.push(`<div class="ncols">${kids}</div>`);
    else if (node.t === "column") out.push(`<div class="ncol">${kids}</div>`);
  }
  shut();
  return out.join("");
}

/**
 * **A clip on a written page** (Ref 1543, his decision of 2026-10-06: the
 * hand-made pages are rebuilt from blocks, with Video as a new one). The same
 * block the phone draws (`LookPage.swift`): `src` a clip this film holds,
 * played here; `url` an address, played in its own player when it is Livid,
 * YouTube or Vimeo (`playerOf`) and otherwise its still with a play mark that
 * opens it; `poster` the still; `cap` the words under it.
 */
function videoBlock(base, node) {
  const cap = node.cap || saidAs(node.r);
  const under = cap ? `<figcaption>${node.cap ? esc(node.cap) : cap}</figcaption>` : "";
  const still = node.poster ? pictureUrl(base, node.poster) : "";
  if (node.src) {
    return `<figure class="nvid"><video class="nvidbox" controls playsinline preload="${still ? "none" : "metadata"}"${
      still ? ` poster="${esc(still)}"` : ""} src="${esc(pictureUrl(base, node.src))}"></video>${under}</figure>`;
  }
  const player = playerOf(node.url);
  if (player) {
    return `<figure class="nvid"><div class="nvidbox"><iframe src="${esc(player)}" title="${esc(node.cap || "Video")}" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen loading="lazy" referrerpolicy="strict-origin-when-cross-origin"></iframe></div>${under}</figure>`;
  }
  if (!node.url) return "";
  return `<figure class="nvid"><a class="nvidbox nvidout" href="${esc(node.url)}" target="_blank" rel="noopener noreferrer" aria-label="Play">${
    still ? `<img src="${esc(still)}" alt="" loading="lazy">` : ""}<i class="nplay" aria-hidden="true"></i></a>${under}</figure>`;
}

/**
 * What sits above a deck: the way into the editor, and the printed copy.
 *
 * His two complaints on 2026-09-06, both fair. Opening the app landed him on a
 * page with no way to edit it — the editor existed and nothing linked to it.
 * And a deck is meant to go out two ways; the PDF was filed under Documents
 * where nobody reading the page would think to look.
 */
export function deckBar(base, front, at, role, menu = "") {
  const one = sectionNamed(at, front) || { name: at };
  const pdf = (front.documents || []).find(
    (d) => d.kind === "lookbook" && d.file && d.name === one.name
  );
  // **Edit went into the page menu** (Ref 1153): it is his, like Rename and
  // Remove. Download PDF stays out here because it is the reader's — a crew
  // member looking for the printed copy should not have to open a menu.
  const bits = [
    pdf ? `<a class="deckdo" href="${fileUrl(base, pdf)}?save=1" download>Download PDF</a>` : "",
    menu,
  ].filter(Boolean);
  return bits.length ? `<div class="deckbar">${bits.join("")}</div>` : "";
}

// ------------------------------------------------------------- the page menu

/** Three dots, filled — the page's own menu. */
const DOTS = '<g fill="currentColor" stroke="none"><circle cx="3.4" cy="8" r="1.35"/><circle cx="8" cy="8" r="1.35"/><circle cx="12.6" cy="8" r="1.35"/></g>';

/**
 * **One small menu beside a page's title, holding that page's own actions.**
 * Ref 1153, his pick of 2026-09-23 (option 3): Write, Rename, Source, Shown on
 * Links, Edit and Remove had been scattered — a deck's at the top, a written
 * page's folded at the bottom, the four built-in pages with none — and now
 * every page keeps them in the same place. Share is the film's and stays in
 * the rail's foot; Add and Headings stay under the rail.
 *
 * **A `<details>`, like the menu behind his initials**, so it opens with no
 * script. An item that needs a form opens that form under the title
 * (`pageAct`, by `:target`), so it still needs no script.
 *
 * **No items, no menu.** A reader gets none on most pages: there is nothing
 * of theirs to do.
 */
function pageMenu(items) {
  const got = items.filter(Boolean);
  // A where-from note alone is not a menu: a reader with nothing to do gets none.
  if (!got.some((one) => !one.startsWith('<div class="pmnote"'))) return "";
  return `<details class="pagemenu"><summary title="Page" aria-label="Page">${mark(DOTS, 16)}</summary>
    <div class="pmcard">${got.join("")}</div></details>`;
}

/**
 * **The page's place in the Library, from its own menu.** An editor's: take it
 * off the sidebar (or put it back), or archive it. Neither moves, rewrites or
 * deletes the page, and it keeps opening from its address.
 */
function shelfItems(base, front, at, role) {
  if (role !== "editor") return "";
  const on = !offSidebar(front, at);
  const one = (fields, button) => `<form method="post" action="${esc(base)}/library" class="pmform">${
    fields.map(([k, v]) => `<input type="hidden" name="${k}" value="${esc(v)}">`).join("")
  }${button}</form>`;
  return one([["sidebar", at], ["on", on ? "0" : "1"], ["back", at]],
      `<button type="submit" class="pmitem pmswitch${on ? " on" : ""}" aria-pressed="${on}">Pinned<i></i></button>`)
    + one([["archive", at], ["on", "1"]], `<button type="submit" class="pmitem">Archive</button>`);
}

/** The page's title with its menu beside it. `id="page"` is where Close lands. */
function pageHead(name, menu) {
  return `<div class="pagehead" id="page"><h1>${esc(name)}</h1>${menu}</div>`;
}

/** A menu item that opens one of the page's own forms. */
function pmOpen(id, name) {
  return `<a class="pmitem" href="#pa-${id}">${esc(name)}</a>`;
}

/** A form, shown under the title only when its item was chosen (`:target`). */
function pageAct(id, name, inner) {
  return `<section class="pageact" id="pa-${id}"><div class="pahead"><span>${esc(name)}</span>
    <a class="pashut" href="#page">Close</a></div>${inner}</section>`;
}

/**
 * **Private, for this page — a switch in its own menu.** Ref 1153 and
 * Ref 1154 together: the page menu holds the one switch for *this* page, and
 * the Share panel's What Viewers See tab holds all of them at once. Both write
 * the same `visible.json` through the same address, so neither can disagree
 * with the other. Administrators only, the same gate Visibility has.
 */
function shownSwitch(base, at, visible, admin) {
  if (!admin) return "";
  const one = (kind, on, label) => `<form method="post" action="${esc(base)}/visibility" class="pmform">
    <input type="hidden" name="flip" value="${kind}:${esc(at)}">
    <input type="hidden" name="back" value="${esc(at)}">
    <button type="submit" class="pmitem pmswitch${on ? " on" : ""}" aria-pressed="${on}">${label}<i></i></button>
  </form>`;
  return one("sections", (visible.sections || []).includes(String(at)), "Private");
}

/**
 * **Follow Google Doc, in the page's own menu.** An administrator's, on a page
 * that follows a doc (`docfollow.js`): the switch, and a redraw now while it is
 * on. The sidebar row and the Library card carry the same two (`ctx.js`); this
 * is the menu on the page itself, drawn with plain forms like its neighbours.
 */
function followItems(base, at, one, admin) {
  const follow = admin && one && one.follow;
  if (!follow || !follow.doc) return "";
  const send = (fields, inner) => `<form method="post" action="${esc(base)}/follow" class="pmform">
    <input type="hidden" name="slug" value="${esc(at)}"><input type="hidden" name="back" value="${esc(at)}">${fields}${inner}</form>`;
  return send(`<input type="hidden" name="on" value="${follow.on ? "0" : "1"}">`,
      `<button type="submit" class="pmitem pmswitch${follow.on ? " on" : ""}" aria-pressed="${Boolean(follow.on)}">Follow Google Doc<i></i></button>`)
    + (follow.on ? send(`<input type="hidden" name="refresh" value="1">`, `<button type="submit" class="pmitem">Refresh from Doc</button>`) : "");
}

/**
 * **Renaming a page he made.** His audit, 2026-09-23: no page could be renamed
 * on the portal at all. The address stays — a link already sent keeps working
 * — and only the name on the rail and the heading change. A page Notion names
 * is renamed in Notion, where the next refresh would put the name back anyway.
 */
function renameBox(one, role) {
  if (role !== "editor" || !one) return "";
  if (one.notion) {
    return `<p class="warn">Rename in Notion</p>`;
  }
  return `<form method="post" class="seeform renamebox">
    <div class="seelist"><label class="seerow">
      <input class="namefield" type="text" name="rename" maxlength="60" required autocomplete="off" value="${esc(one.name)}">
    </label></div>
    <div class="seefoot"><button class="savebtn" type="submit">Rename</button></div>
  </form>`;
}

export function sectionPage(base, front, at, tree, made = "", role = "viewer", admin = false, visible = emptyVisible(), extra = {}) {
  const one = sectionNamed(at, front);
  const synced = syncLine(front, one, role, extra.follow);
  const mineToChange = role === "editor" && one;
  // **The shelf items ride with the Shown switches**, so every page with a menu has
  // it and none had to be edited one by one. A board has no Shown switch, so
  // its own menu names it.
  const away = shelfItems(base, front, at, role);
  const shown = shownSwitch(base, at, visible, admin) + away;
  // **A published document brings its own design and is drawn whole.** It is
  // made by `deck-builder/tools/publish.py` out of the same deck that prints
  // the PDF, so what a crew member reads on the site and what they are handed
  // on paper are one design in two media. No heading is added above it: the
  // document has its own, so the menu sits in the deck's bar instead.
  // **A board has no Edit and no Shown on Links here**: it is edited where it
  // stands, and who may open it is the switch on its own toolbar.
  if (made && one && one.type === "board") {
    const menu = pageMenu([
      mineToChange ? pmOpen("rename", "Rename") : "",
      away,
      mineToChange ? pmOpen("remove", "Remove Page") : "",
    ]);
    return `${deckBar(base, front, at, role, menu)}${
      mineToChange ? pageAct("rename", "Rename", renameBox(one, role)) + pageAct("remove", "Remove Page", removeBox(one, role)) : ""}
      <div class="madepage">${made}</div>`;
  }
  if (made) {
    const menu = pageMenu([
      syncNote(front, one, extra.follow),
      role === "editor" ? `<a class="pmitem" href="${esc(base)}/${esc(at)}/edit">Edit</a>` : "",
      mineToChange ? pmOpen("rename", "Rename") : "",
      shown,
      followItems(base, at, one, admin),
      mineToChange ? pmOpen("remove", "Remove Page") : "",
    ]);
    return `${deckBar(base, front, at, role, menu)}${synced}${
      mineToChange ? pageAct("rename", "Rename", renameBox(one, role)) + pageAct("remove", "Remove Page", removeBox(one, role)) : ""}
      <div class="madepage">${made}</div>`;
  }
  const name = one ? one.name : at;
  const from = one && one.title && one.title !== one.name ? one.title : "";
  // **These are the pages he adds, so these are the ones the question is
  // about.** A page fed by Notion and one copied off it once have always read
  // identically here, and the difference decides whether writing in Notion
  // reaches the site at all.
  const source = (one && one.source) || "notion";
  const sub = syncNote(front, one, extra.follow) || sourceSub(front, source, from);
  const set = one ? sourceForm(one, source, role) : "";
  const mine = role === "editor" && source !== "program";
  const filled = Boolean(tree && tree.length);
  const menu = pageMenu([
    sub,
    // An empty page already shows its box, open; Write is for one with words.
    mine && filled ? pmOpen("write", "Write") : "",
    mineToChange ? pmOpen("rename", "Rename") : "",
    set ? pmOpen("source", "Source") : "",
    shown,
    followItems(base, at, one, admin),
    mineToChange ? pmOpen("remove", "Remove Page") : "",
  ]);
  const acts = [
    mine && filled ? pageAct("write", "Write", writeBox(markdownFrom(tree), true, true)) : "",
    mineToChange ? pageAct("rename", "Rename", renameBox(one, role)) : "",
    set ? pageAct("source", "Source", set) : "",
    mineToChange ? pageAct("remove", "Remove Page", removeBox(one, role)) : "",
  ].join("");
  if (!filled) {
    // **For an editor an empty page is a box, not a notice.** A viewer still
    // gets the one line, because for them there is nothing to do about it.
    return `${pageHead(name, menu)}${synced}${acts}${
      mine ? writeBox("", true) : `<p class="empty">Empty</p>`}`;
  }
  return `${pageHead(name, menu)}${synced}${acts}
    <div class="notion">${drawBlocks(base, tree)}</div>`;
}

/**
 * **The Visibility tab, reached from a page.** People and Documents are where
 * per-name visibility bites, so their menu carries the way to it. It is the
 * Share panel's tab when a script is running and the plain page when not.
 */
function visItem(base, admin) {
  // What a viewer sees is set in the Library now (2026-10-11), not a tab of Share.
  return admin ? `<a class="pmitem" data-deep="record" href="${esc(base)}/library">Open Library</a>` : "";
}

function recordPage(base, front, at, role, visible = emptyVisible(), tree = null, made = "", admin = false, extra = {}) {
  const shown = shownSwitch(base, at, visible, admin) + shelfItems(base, front, at, role);
  if (at === "script") return scriptPage(base, front, shown, extra);
  if (made) {
    const menu = pageMenu([
      role === "editor" ? `<a class="pmitem" href="${esc(base)}/${esc(at)}/edit">Edit</a>` : "", shown,
    ]);
    return `${deckBar(base, front, at, role, menu)}<div class="madepage">${made}</div>`;
  }
  if (at === "bible") {
    // **His own bible, on this page rather than beside it.** A Project Docs row
    // ticked Hub and named `Visual Bible` is folded onto this slug by
    // `refresh.py`, so the forty pictures and the two paragraphs off the film's
    // Notion page are one page — which is what a bible is. Everything else he
    // names in Notion is still a section of its own, under Details.
    const his = sectionNamed("bible", front);
    const drawn = tree && tree.length ? `<div class="notion">${drawBlocks(base, tree)}</div>` : "";
    const from = his && his.title && his.title !== his.name ? his.title : "From Notion";
    const source = (his && his.source) || "notion";
    // **His own Notion page is folded onto this slug**, so the bible is one
    // of his pages as much as it is one of the record's four — and taking a
    // snapshot of it is exactly what somebody does before a shoot.
    const set = his ? sourceForm(his, source, role) : "";
    const menu = pageMenu([syncNote(front, his) || sourceSub(front, source, from), set ? pmOpen("source", "Source") : "", shown]);
    if (!his && !drawn) return `${pageHead("Visual Bible", menu)}<p class="empty">No Visual Bible</p>`;
    return `${pageHead("Visual Bible", menu)}${syncLine(front, his, role)}
      ${set ? pageAct("source", "Source", set) : ""}
      ${drawn || `<p class="empty">Empty</p>`}`;
  }
  if (at === "camera") {
    const cam = front.camera;
    // **A spec sheet is the sheet, not only its boxes.** His point, 2026-09-04:
    // he uploads small files onto one and writes notes on it. Both come across
    // now, so a sheet with nothing typed in its ten boxes but a LUT and a page
    // of prep notes on it is not an empty page.
    const files = front.camera_files || [];
    const notes = tree && tree.length ? tree : null;
    if (!hasCamera(cam) && !files.length && !notes && !(cam.finishing_resolutions || []).length && !(cam.ratios || []).length) {
      return `${pageHead("Camera Spec Sheet", pageMenu([shown]))}<p class="empty">No Spec Sheet</p>`;
    }
    // **A spec sheet is a technical list, not a set of tiles** — his ruling,
    // 2026-09-02. One row per fact, in the order somebody prepping a camera
    // reads them, and a copy button against each because these are the values
    // he currently retypes into emails.
    // **In order of operation, three groups** (his ask, 2026-10-15): Camera
    // (bodies, sensor mode, lenses, filters, aspect ratio, the other capture
    // rows), Color (LUTs, colour space), Deliverables (finishing
    // resolutions). Notes last. [label, value, Notion prop, the card's box].
    const ratios = Array.isArray(cam.ratios) ? cam.ratios : [];
    const finishing = Array.isArray(cam.finishing_resolutions) ? cam.finishing_resolutions : [];
    const ratioText = (list) => list.map((f) => `${f.name} ${f.ratio}`.trim()).join("\n");
    const finishingText = (list) => list.map((f) => [f.title, f.resolution, f.note].filter(Boolean).join(" · ")).join("\n");
    const camRows = [
      ["Camera", cam.body, "Camera", "body"],
      ["Shooting Format", cam.format, "Shooting Format", "format"],
      ["Capture Resolution", cam.capture, "Capture Resolution", "capture"],
      ["Lenses", cam.lenses, "Lenses", "lenses"],
      ["Desqueeze", cam.desqueeze, "Desqueeze", "desqueeze"],
      // what the shoot carries beside its lenses (2026-10-14): pills, the shoot's
      ["Filters", cam.filters, "Filters", "filters"],
      ["Modifiers", cam.modifiers, "Modifiers", "modifiers"],
      // the sheet's aspect ratios (a camera has no Frame Guides of its own any more)
      ["Aspect Ratio", ratioText(ratios), "Aspect Ratio", "ratios"],
      ["Frame Rate", cam.fps, "Frame Rate", "fps"],
      ["Codec", cam.codec, "Codec", "codec"],
    ];
    const colourRows = [["Color Space", cam.colour, "Color Space", "colour"]];
    // The shoot before's sheet, box for box, when there is one.
    const was = front.was && front.was.camera;
    const then = (box) => {
      if (!was) return null;
      if (box === "ratios") return Array.isArray(was.ratios) && was.ratios.length ? ratioText(was.ratios) : "";
      return was[box] || "";
    };
    // **Several cameras** (src/entries.js): a column per camera in each fact,
    // a value they all share across the whole row (camRow).
    const group = cameras(fieldsOfCard(cam), lensSetsShown(cam.lenses));
    const row = ([label, value, prop, box]) => {
      const before = then(box);
      if (!value) return "";
      if (box === "ratios") return ratioRow(front, ratios, label, prop, value, before);
      // pills, as Notion has them; a box still in the old typed lines as before
      const typed = /\s[—–|]\s/.test(value) || entries(value).some((e) => e.label);
      if (label === "Camera") return cameraPillRow(front, group, value, before);
      if (label === "Lenses") return arePills(value) ? pillRow(front, label, prop, value, before, cam.lens_cf || null) : lensRow(value, before);
      if (label === "Modifiers" || label === "Filters") return pillRow(front, label, prop, value, before);
      if (!typed) return pillRow(front, label, prop, value, before);
      return camRow(label, camCells(group, prop, value), value, before, group.cameras.length);
    };
    // **LUTs and Notes as Projects Console draws them** (2026-10-14): more
    // rows of the same table, LUTs under each camera's column when the
    // cameras differ. A file that is not a LUT (a camera report) stays below.
    const lutRow = lutsRow(base, group, files.filter((one) => one.kind !== "file"), cam.luts);
    const others = files.filter((one) => one.kind === "file");
    const noteRow = notesRow(base, cam.notes, notes);
    const finRow = finishingRow(finishing, was ? finishingText(was.finishing_resolutions || []) : null, finishingText(finishing));
    const block = (head, html) => (html ? `<div class="blockhead">${head}</div><dl class="spec">${html}</dl>` : "");
    const has = hasCamera(cam) || ratios.length > 0;
    return `${pageHead("Camera Spec Sheet", pageMenu([sourceSub(front, (sectionNamed("camera", front) || {}).source || "notion", "From the Camera Spec Sheets database"), shown]))}
      ${block("Camera", has ? camRows.map(row).join("") : "")}
      ${block("Color", lutRow + (has ? colourRows.map(row).join("") : ""))}
      ${block("Deliverables", finRow)}
      ${noteRow ? `<dl class="spec specnotesblock">${noteRow}</dl>` : ""}
      ${others.length ? `<div class="blockhead">Files</div>
        ${others.map((one) => documentCard(base, one)).join("")}` : ""}`;
  }
  if (at === "people") {
    // **Filtered before it is drawn, never hidden with a stylesheet.** A name
    // and a number that reach the HTML have been published, whatever the page
    // does with them afterwards.
    const sees = (one) => maySee(visible, "crew", one.name, role) && meSees(visible, "crew", one.name, admin);
    const crew = front.crew.filter(sees);
    const menu = pageMenu([sourceSub(front, "here", "From the Project Record"), shown, crew.length ? visItem(base, admin) : ""]);
    // **Who is new since the shoot before** (SL-1396), by name, so nobody has
    // to write it down. **Who is not on this shoot is not drawn** — his
    // ruling, 2026-10-02: "dont highlight whos not on a new shoot".
    const named = (list) => new Set(list.map((one) => one.name.trim().toLowerCase()));
    const before = front.was ? named(front.was.crew) : null;
    if (!crew.length) return `${pageHead("People", menu)}<p class="empty">No Contacts</p>`;
    return `${pageHead("People", menu)}
      ${role === "editor" ? "" : `<p class="sub">Editors only</p>`}
      ${byDepartment(crew).map(([department, list]) => `<div class="blockhead">${esc(department)}</div>
        <div class="mates">${list.map((one) => crewRow(one, mayContact(visible, one.name, role), Boolean(before) && !before.has(one.name.trim().toLowerCase()))).join("")}</div>`).join("")}`;
  }
  const docs = front.documents.filter((doc) => !isArchived(front, `doc:${doc.name}`) && maySee(visible, "documents", doc.name, role) && meSees(visible, "documents", doc.name, admin));
  const menu = pageMenu([sourceSub(front, "here", "Added Here"), shown, docs.length ? visItem(base, admin) : ""]);
  if (!docs.length) return `${pageHead("Documents", menu)}<p class="empty">Empty</p>`;
  // **Grouped by what it is, newest first** (2026-10-17): Schedule & Call
  // Sheets, Script, Creative, Other. One group needs no heading.
  const groups = DOC_GROUPS.map((g) => [g, docs.filter((d) => docGroup(d) === g)
    .sort((a, b) => String(b.modified || "").localeCompare(String(a.modified || "")))]).filter(([, list]) => list.length);
  return `${pageHead("Documents", menu)}
    ${groups.map(([g, list]) => `${groups.length > 1 ? `<div class="blockhead">${esc(g)}</div>` : ""}
      ${list.map((doc) => documentCard(base, doc, role)).join("")}`).join("")}`;
}

const DOC_GROUPS = ["Schedule & Call Sheets", "Script", "Creative", "Other"];

/** A document's group: a Drive file carries its own; anything else is named by its name. */
function docGroup(doc) {
  if (doc.group && DOC_GROUPS.includes(doc.group)) return doc.group;
  const name = String(doc.name || "");
  if (/call ?sheet|callsheet|schedule|stripboard|one[- ]?liner|shot ?list|crew ?list/i.test(name)) return "Schedule & Call Sheets";
  if (/script|screenplay|\bdraft\b|\bsides\b/i.test(name)) return "Script";
  if (doc.kind === "lookbook" || /deck|look ?book|treatment|bible|mood|storyboard|reference/i.test(name)) return "Creative";
  return "Other";
}

/** "Oct 14" this year, "Oct 14, 2025" before it. */
function docDate(iso) {
  const t = Date.parse(String(iso || ""));
  if (!Number.isFinite(t)) return "";
  const d = new Date(t), now = new Date();
  const m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()];
  return `${m} ${d.getUTCDate()}${d.getUTCFullYear() === now.getUTCFullYear() ? "" : `, ${d.getUTCFullYear()}`}`;
}

// ---------------------------------------------------------------- the script

/**
 * **The Script page** (SL-1338). His words, 2026-10-01: *"a script tab on the
 * web portal where you could either read the script from that tab or download
 * it easily … rather than just a tab in Documents"* — *"and make sure that
 * this could update as new versions of the script come in."*
 *
 * **The drafts are the film's**, the ones he takes in with Import Script on
 * the Mac: each keeps its PDF beside its text, and both travel to the bucket
 * with the pictures. `front.scripts` is read off the film on every look
 * (`film_card` in `mcpweb`), newest first — so a new draft is this page's the
 * moment its log arrives, and nothing is pinned or uploaded by hand.
 *
 * **The pages are the real PDF**, drawn by `public/reader.js` with pdf.js —
 * the same one a board uses — because an iPhone's browser shows a PDF in a
 * frame as its first page and stops. Older drafts sit folded under the head.
 *
 * Not the Shot List's Script view (`scriptPaper` in `public/film.js`): that is
 * a commercial's AV script beside its shots, and it stays where the shots are.
 *
 * `extra.draft` is the stem asked for; `extra.pdfs` the stems whose PDF the
 * bucket holds; `extra.text` the draft's words, when its PDF is not there.
 */
function scriptPage(base, front, shown, extra = {}) {
  const drafts = front.scripts || [];
  const menu = pageMenu([shown]);
  if (!drafts.length) return `${pageHead("Script", menu)}<p class="empty">No Script</p>`;
  const one = drafts.find((d) => d.stem === extra.draft) || drafts[0];
  const latest = drafts[0];
  const pdfs = new Set(extra.pdfs || drafts.map((d) => d.stem));
  const file = (d) => `${base}/script.pdf?draft=${d.stem}`;
  const at = (d) => `${base}/script${d === latest ? "" : `?draft=${d.stem}`}`;
  const saveAs = (d) => esc(scriptFileName(d, ""));
  const facts = [draftName(one), draftDate(one.dated), ...draftAlso(one)].filter(Boolean).map((x) => `<span>${esc(x)}</span>`);
  const has = pdfs.has(one.stem);
  // **Marks** (Ref 1568): the draft laid out in pages with each shot's bar
  // beside the lines it holds, drawn by `public/marks.js`. Offered only when
  // some shot holds lines of the screenplay and this draft's words are here.
  const marked = Boolean(extra.marks);
  const switchView = marked && has
    ? `<div class="fh-seg scriptview" role="group" aria-label="View"><button type="button" data-sview="pdf" class="on">PDF</button><button type="button" data-sview="marks">Marks</button></div>`
    : "";
  // **Download first, before anything else** — his note, 2026-10-01: *"be able
  // to easily download before anything else"*. It leads the row, in the
  // film's colour; the reader's own bar carries it again for whoever has
  // scrolled into page forty.
  const head = `<div class="scriptbar">
    ${has ? `<a class="deckdo prime scriptdl" href="${esc(file(one))}&amp;save=1" download="${saveAs(one)}">Download PDF</a>
      <a class="deckdo scriptopen" href="${esc(file(one))}" target="_blank" rel="noopener">Open</a>` : ""}
    ${switchView}
    <span class="scriptfacts">${facts.join("")}<span data-pagecount></span></span>
  </div>`;
  const row = (d) => `<div class="draftrow${d === one ? " on" : ""}">
      <a class="draftname" href="${esc(at(d))}"><b>${esc(draftName(d))}</b>${d === latest ? `<i>Latest</i>` : ""}
        <span>${esc([draftDate(d.dated), ...draftAlso(d)].filter(Boolean).join(" · "))}</span></a>
      ${pdfs.has(d.stem)
        ? `<a class="deckdo" href="${esc(file(d))}&amp;save=1" download="${saveAs(d)}">Download</a>`
        : `<span class="draftnone">Text Only</span>`}
    </div>`;
  const list = drafts.length > 1
    ? `<details class="drafts"><summary>Drafts <span class="n">${drafts.length}</span></summary>
        <div class="draftlist">${drafts.map(row).join("")}</div></details>`
    : "";
  const older = one === latest ? "" : `<p class="warn scriptold">Older draft · <a href="${esc(at(latest))}">Latest: ${esc(draftName(latest))}</a></p>`;
  // **A reader, not a picture of one** (his note, same day: *"like a pdf
  // reader"*). The bar stays at the top of the pane as the pages scroll
  // under it; `public/reader.js` fills it and draws the pages, centred, at the
  // width the bar says — Fit Width until he picks otherwise.
  const marksBox = marked
    ? `<section class="marks" data-marks="${esc(base)}" data-text="${esc(base)}/script.txt?draft=${esc(one.stem)}"${has ? " hidden" : ""}>
      <p class="empty marksnote">Loading</p></section>`
    : "";
  const body = (has
    ? `<link rel="modulepreload" href="${PDFJS_LIB}" crossorigin>
      <section class="reader" data-pdf="${esc(file(one))}" data-save="${esc(file(one))}&amp;save=1" data-name="${saveAs(one)}">
      <div class="readerbar">
        <span class="readerat" data-at>Loading</span>
        <span class="readerzoom">
          <button type="button" class="rbtn" data-zoom="out" aria-label="Zoom Out" title="Zoom Out">${mark(MINUS, 14)}</button>
          <span class="readerpct" data-pct></span>
          <button type="button" class="rbtn" data-zoom="in" aria-label="Zoom In" title="Zoom In">${mark(PLUS, 14)}</button>
          <button type="button" class="rbtn rword" data-fit="width">Fit Width</button>
          <button type="button" class="rbtn rword" data-fit="page">Fit Page</button>
        </span>
        <a class="rbtn rsave" href="${esc(file(one))}&amp;save=1" download="${saveAs(one)}" title="Download PDF" aria-label="Download PDF">${mark(SAVE, 15)}</a>
      </div>
      <div class="readerload"><i data-loaded></i></div>
      <div class="scriptpages"><div class="scriptsheet waiting"></div></div>
    </section>`
    : marked
      ? ""
      : extra.text
        ? `<pre class="scripttext">${esc(extra.text)}</pre>`
        : `<p class="empty">Not Published</p>`) + marksBox;
  return `<div class="scriptpage">${pageHead("Script", menu)}${head}${list}${older}${body}</div>`;
}

/** pdf.js, the build `public/reader.js` and `public/board.js` both load. */
const PDFJS_LIB = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs";

// What a draft is called, its file and its date: `scriptlabel.js`, the one
// rule every app shows (stage 5 step 4, piece C).

/**
 * **What a draft downloads as: the file it came from, under its own name** —
 * `MIRRORLAND_092626.pdf`, as the writer sent it. A draft with no `.pdf`
 * name falls back to the film's and the draft's.
 */
export function scriptFileName(draft, title) {
  const own = String((draft && draft.came_from) || "").split(/[\\/]/).pop().trim();
  if (/\.pdf$/i.test(own)) return own;
  const named = [title, draft && draft.name].filter(Boolean).join(" - ") || "Script";
  return `${named}.pdf`;
}

// -------------------------------------------------------------- visibility

/**
 * **What a crew member sees, and the only screen that can change it.**
 *
 * His instruction, 2026-09-04: administrators get a panel for adjusting what is
 * visible, *"especially for the crew information, since that can be sensitive.
 * as well as other tabs and documents"*.
 *
 * **A plain form, posting to its own address.** Every other panel in the portal
 * is script; this one is not, deliberately. It decides who can see a crew
 * member's mobile number, and a control that only works once JavaScript has
 * arrived is a control that silently does nothing on the connection where it
 * matters most.
 *
 * **Ticked is seen.** The store keeps the *hidden* ones, so anything the film
 * gains later — a section he adds, a name Notion picks up overnight — arrives
 * visible rather than invisible-and-unmentioned.
 */
/**
 * **Where a page is born.** His ruling, 2026-09-05: a deck is always a page of
 * a film, and *which film* is therefore not a field anybody fills in — you
 * stand on a film and add a page to it. So this asks one question and no more.
 *
 * Until now the portal had no way to make a page at all: one was born only by
 * ticking `Hub` on a Project Docs row in Notion, or by an agent calling
 * `set_page`. That gap is why publishing a deck could re-skin a page that
 * already existed and never make a new one.
 */
/**
 * **Add asks the type and the name, and no longer asks the source.**
 *
 * His report, 2026-09-08, an hour after step 3 shipped: *"All of the options
 * under the written page add doesn't work at all. They all lead to empty or
 * broken URLs and have no function."* He was right and the fault was in the
 * question, not the wiring — the address answered and the row was on the rail,
 * but all three answers made the same empty page.
 *
 * **Two of the three could never have worked here.** *Live from Notion* and
 * *Copied from Notion once* both need a Notion page to be fed by or copied
 * from, and **this worker has no Notion token and cannot have one** — Notion is
 * read by `refresh.py` on his Mac, out of his Keychain. Nothing on the portal
 * can list his pages or bind one to a section; only Notion can, by ticking
 * `Hub` and naming a `Section`. The plan's third panel drew a Notion page
 * picker, and that panel is not buildable on this side of the wire.
 *
 * So at birth there is exactly one truthful answer, and a question with one
 * answer is not a question. **A page made here is written here** — and the
 * writing box below `sectionPage` is what makes that mean something. The source
 * stays changeable afterwards, on the page, where a real choice exists because
 * by then there is a page to hand over.
 */
export function newPageBody(base, title, front, who, role, many, said = "", chose = {}, tools = {}) {
  const type = ADD_TYPES.some((t) => t.value === chose.type) ? chose.type : "page";
  const pick = (group, value, name, under, on) => `<label class="seerow" data-pick="${esc(group)}" data-value="${esc(value)}">
    <input type="radio" name="${esc(group)}" value="${esc(value)}"${on ? " checked" : ""}>
    <span class="seename">${esc(name)}${under ? `<span>${esc(under)}</span>` : ""}</span>
  </label>`;

  return `<div class="fh2 deep"${accent(front)}>
    ${railFor(base, title, front, "add", who, role, many ? "/" : "", toolShare(base, role, who, tools), tools.visible || emptyVisible(), Boolean(tools.admin))}
    ${phoneParts(base, title, front, { name: "Add", n: "" }, toolShare(base, role, who, tools), many ? "/" : "", role === "editor")}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="inner">
      <h1>Add</h1>
      ${said ? `<p class="warn">${esc(said)}</p>` : ""}
      <form method="post" class="seeform addform" enctype="multipart/form-data"
            data-base="${esc(base)}">
        <div class="blockhead">Type</div>
        <div class="seelist">${
          ADD_TYPES.map((t) => pick("type", t.value, t.name, t.under, t.value === type)).join("")
        }</div>

        <div class="blockhead">Name</div>
        <div class="seelist"><label class="seerow">
          <input class="namefield" type="text" name="name" maxlength="60" required
                 autocomplete="off" autofocus placeholder="Lighting Plan"
                 value="${esc(chose.name || "")}">
        </label></div>
        ${
          // **Hidden until a script fills it, and outside the list.** The
          // address is worked out in the browser as he types — with nothing
          // running there is nothing to show, and an empty `/f/<film>/` under
          // the name field would read as a bug rather than as a feature that
          // has not arrived. It sits *after* `.seelist` because that is a grid:
          // inside it, the address became a second column beside the field
          // rather than a line under it.
          ""}<p class="fh-addr off" data-only="page deck board"><span class="dim">${esc(base)}/</span><b></b></p>

        <div class="blockhead" data-only="file">File</div>
        <div class="seelist" data-only="file"><label class="seerow">
          <input class="filefield" type="file" name="file">
        </label></div>

        <div class="blockhead" data-only="link">Address</div>
        <div class="seelist" data-only="link"><label class="seerow">
          <input class="namefield" type="url" name="url" maxlength="1200"
                 autocomplete="off" placeholder="https://drive.google.com/…"
                 value="${esc(chose.url || "")}">
        </label></div>

        <div class="seefoot"><button class="savebtn" type="submit">Add</button></div>
      </form>
      ${builtIn(base, front)}
    </div></div></main>
  </div>`;
}

/**
 * **The pages Add does not make, and where each one is filled.** His
 * walkthrough, 2026-09-23: with empty pages gone from a reader's rail
 * (`unfilled`), the built-in ones need one place that still names them all —
 * and this is the page he opens when he means to add something.
 *
 * A table of names, not a paragraph: what the page is, where its words come
 * from, and whether anything is in it yet. The one sentence says what an
 * empty page costs, which a label cannot.
 */
const BUILT_IN = [
  { at: "script", name: "Script", from: "Studio · Import Script", app: true },
  { at: "bible", name: "Visual Bible", from: "Notion · Film Page or Project Docs" },
  { at: "camera", name: "Camera Spec Sheet", from: "Notion · Camera Spec Sheets" },
  { at: "people", name: "People", from: "Notion · Crew" },
  { at: "documents", name: "Documents", from: "Notion · Project Docs, or Add" },
  { at: "locations", name: "Locations", from: "Studio", app: true },
  { at: "schedule", name: "Schedule", from: "Studio", app: true },
  { at: "boards", name: "Reference Images", from: "Studio", app: true },
];

function builtIn(base, front) {
  const empty = new Set(unfilled(front));
  const rows = BUILT_IN.filter((p) => !(p.app && front.film === false));
  // A program screen on a card nobody has read the film for is unknown, not
  // filled — it says nothing rather than guess.
  const state = (p) => (empty.has(p.at) ? "Empty" : p.app && !front.live ? "" : "Filled");
  return `<div class="blockhead">Built In</div>
    <div class="fh-builtin">${rows.map((p) => `<a class="fh-bi" href="${esc(base)}/${p.at}">
      <b>${esc(p.name)}</b><span>${esc(p.from)}</span><i${empty.has(p.at) ? ` class="none"` : ""}>${state(p)}</i>
    </a>`).join("")}</div>`;
}

/**
 * **What you may add, and what each one asks next.** Ref 872, his answer:
 * *"Yes, I think Plan B is the way to go."*
 *
 * **A Link is his, 2026-09-08**, asked for while this was being built: *"I
 * should just be able to add links to not just Notion, but anything I want —
 * for example, a Google Drive folder or a YouTube video."* A link has always
 * been a thing a film can hold; the only way to make one was to tick `Hub` on a
 * Project Docs row, so anything not already in Notion could not be pinned at
 * all. It lands under Documents beside the ones Notion names, and `both_kinds`
 * in `refresh.py` now keeps it there — see the note on `source` in `document`.
 *
 * **A spec sheet is deliberately absent**: the
 * Camera Spec Sheet is ten fixed fields drawn from his Camera Spec Sheets
 * database by `recordPage`, and a section carrying `type: "sheet"` draws as a
 * plain page — so offering it here would make a row that lies about what it is.
 * It is a row in the database rather than a hole in this list.
 *
 * `under` is the one place a sentence is allowed on this screen: it is the
 * difference between the choices, which a bare noun cannot carry.
 */
// **A row names the thing and stops.** The line under each name used to
// explain what it was for; his ruling on how the app talks (2026-08-21,
// carried to the portal 2026-09-15) deletes that sentence rather than
// shortening it.
const ADD_TYPES = [
  { value: "page", name: "Written Page", under: "" },
  { value: "deck", name: "Deck", under: "" },
  { value: "board", name: "Board", under: "" },
  { value: "file", name: "File", under: "" },
  { value: "link", name: "Link", under: "" },
];


/**
 * **His own headings for the sidebar.** His instruction, 2026-09-08: *"allow me
 * to make my own categories on the sidebar and divide things up per project as
 * I want."*
 *
 * **Naming is typing and filing is dragging, so they are two places.** The
 * rail is where things are put under a heading — that is a drag, and it is
 * already there. This is where a heading is made, renamed, removed — and,
 * since 2026-09-10, put in order: his ask, *"I need to be able to reorder my
 * headings. The interface for setting up the headings should be more like a
 * drag-and-drop list than anything else."*
 *
 * **A list of rows, each with a grip**, and every row a plain form field: the
 * page still works with no script — type, press Save — and with `arrange.js`
 * awake the same rows are dragged into order, renamed as the field is left,
 * removed by the cross and added by the button, each change moving the rail
 * beside it at once and saving in the background. **The order the rows are in
 * is the order they are sent in**, which is why the worker reads them by
 * `was` rather than by position.
 *
 * **Removing a heading never removes what is under it.** *Report, never invent
 * — and never destroy.* The rows fall to the bottom of the rail, unfiled, which
 * is where everything he has not sorted lives anyway.
 */
export function groupsBody(base, title, front, who, role, many, said = "", tools = {}) {
  // **The headings are the categories** (2026-10-11): one list, the Library's.
  // A row says how many pages stand in it; a page not yet filed anywhere is
  // counted where it would be filed.
  const counts = new Map(railGroups(front, offeredPages(front), { empty: true }).map((g) => [g.shelf, g.rows.length]));
  const groups = shelfList(front);
  const row = (group) => {
    const n = counts.get(group.id) || 0;
    return `<div class="fh-headrow" data-head="${esc(group.name)}" data-shelf="${esc(group.id)}">
    <span class="fh-grip" aria-hidden="true">${mark(GRIP, 14)}</span>
    <input class="namefield" type="text" name="name" maxlength="40" autocomplete="off"
           value="${esc(group.name)}" aria-label="Category">
    <input type="hidden" name="was" value="${esc(group.id)}">
    <span class="fh-headcount">${n ? `${n} ${n === 1 ? "page" : "pages"}` : ""}</span>
    ${group.builtIn ? `<span class="fh-headdrop" aria-hidden="true"></span>`
      : `<button class="fh-headdrop" type="submit" name="drop" value="${esc(group.id)}" title="Remove" aria-label="Remove">${mark(CROSS, 12)}</button>`}
  </div>`;
  };

  return `<div class="fh2 deep"${accent(front)}>
    ${railFor(base, title, front, "groups", who, role, many ? "/" : "", toolShare(base, role, who, tools), tools.visible || emptyVisible(), Boolean(tools.admin))}
    ${phoneParts(base, title, front, { name: "Categories", n: "" }, toolShare(base, role, who, tools), many ? "/" : "", role === "editor")}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="inner">
      <h1>Categories</h1>
      ${said ? `<p class="warn">${esc(said)}</p>` : ""}
      <form method="post" class="seeform fh-headform">
        <button class="fh-default" type="submit" tabindex="-1" aria-hidden="true"></button>
        <div class="fh-heads" data-headings>${groups.map(row).join("")}</div>
        <template class="fh-headtpl">${row({ id: "", name: "", builtIn: false })}</template>
        <p class="warn fh-headsaid" hidden></p>

        <div class="blockhead">Add Category</div>
        <div class="seelist"><label class="seerow">
          <input class="namefield" type="text" name="new" maxlength="40" autocomplete="off" placeholder="Look">
        </label></div>

        <div class="seefoot"><button class="savebtn" type="submit">Save</button></div>
      </form>
    </div></div></main>
  </div>`;
}

/**
 * **The Library: every page and document the film holds, shelved like a real
 * one.** His words, 2026-10-02: *"the library is just the base where
 * everything is held, and then I can drop things on the sidebar if I want"*,
 * and later *"it would be great if it felt more library like and not just a
 * settings page — organized into categories that made sense to people."*
 *
 * **Shelves, not a table.** Everything stands on one of the film's shelves
 * (`front.shelves`: the seven to start, renamed and added to as he likes;
 * `shelvesOf` in `front.js`), filed by what it is and what it is called, and
 * moved by hand from its card's menu. A card is a name and a line about it;
 * the switches (on the sidebar, shown on links, shown for me), Move To and
 * Archive are tucked in the card's own menu, an editor's, so a reader sees a
 * catalogue and nothing to fiddle with.
 *
 * **The sidebar is a pinned subset of it**, not the other way round. A page is
 * on the sidebar unless taken off (`front.library`), and a page added tomorrow
 * is on it until he says otherwise. **Archive is a folder inside the Library**
 * (`front.archive`). None of it moves, rewrites or deletes a page: its address
 * keeps opening. **Everybody gets it, public link or not**, each reading what
 * they may (`libraryItems`).
 */
/** What this reader may find in the Library: pages, and the film's documents. */
function libraryItems(front, visible, role, who, admin) {
  const built = new Set(railRows(front).map((p) => p.at));
  const empty = new Set(unfilled(front, visible));
  const pages = [...railRows(front), ...sectionsOf(front).filter((p) => p.page)]
    .filter((p) => maySee(visible, "sections", p.at, role) && boardOpen(p, who, admin) && !empty.has(p.at))
    .map((p) => ({ at: p.at, name: p.name, type: p.type, share: p.share, built: built.has(p.at) }));
  const docs = maySee(visible, "sections", "documents", role)
    ? (front.documents || []).filter((d) => maySee(visible, "documents", d.name, role)) : [];
  return { pages, docs };
}

/**
 * The decks, written pages and boards whose covers will say something, as
 * `coversOf` in `covers.js` wants them. Built In pages say their own number.
 */
export function coverWants(front, visible, role, who, admin) {
  const { pages } = libraryItems(front, visible, role, who, admin);
  return pages.filter((p) => !p.built && !isArchived(front, p.at)).slice(0, 80)
    .map((p) => ({ slug: p.at, type: p.type === "deck" ? "deck" : p.type === "board" ? "board" : "page", board: (sectionNamed(p.at, front) || {}).board }));
}

/** How many things the Library holds for this reader — the number on its row. */
export function libraryCount(front, visible, role, who, admin) {
  const { pages, docs } = libraryItems(front, visible, role, who, admin);
  return pages.length + docs.length;
}

/** A shelf's place on the page, by its id, so a rename keeps every link to it. */
const shelfId = (id) => `shelf-${id}`;
/** The icon a shelf wears: the seven their own, one he added a tag. */
const SHELF_ICON_IDS = { creative: "palette", technical: "camera", logistical: "schedule", other: "pencil" };
export const shelfIcon = (id) => SHELF_ICON_IDS[id] || "tag";

/**
 * **The Library, for the people who run the film: Pages** (2026-10-11, his
 * approved layout, `portal-tab-layout.html`). One job: what is on the portal,
 * and who sees it. It has to hold a film with a hundred pages, so it is a
 * list, not shelves of covers:
 *
 * - a search (`Search 100 pages`), All or Hidden, and how many are shown;
 * - a card per category, folded shut but for the first with pages in it,
 *   showing eight rows until Show All; a search or Hidden looks across every
 *   category and opens what it finds (`public/lib.js`);
 * - each row: its name, small chips, **one switch** (shown to viewers, the
 *   same setting What Viewers See ticks) and a ⋯ with Rename, Move To and
 *   Archive. Pinning and icons belong to the sidebar, so they are not here;
 * - a category's own ⋯: Rename, and Remove for one he added;
 * - Crew (Shown and Contact per person) and the Archive, folded.
 *
 * A reader's Library is `libraryBody`'s shelves, unchanged.
 */
function pagesBody(base, title, front, who, role, many, said, tools) {
  const visible = tools.visible || emptyVisible();
  const admin = Boolean(tools.admin);
  const hidden = (kind, key) => (visible[kind] || []).includes(String(key));
  const built = new Set(railRows(front).map((p) => p.at));
  const empty = new Set(unfilled(front, visible));
  const renamable = new Set(sectionsOf(front).filter((p) => p.page).map((p) => p.at));
  const all = offeredPages(front);
  // Pages in the sidebar's own order, so a category reads the way the rail does.
  const onRail = new Map(railGroups(front, all, { empty: true }).flatMap((g) => g.rows).map((p, i) => [p.at, i]));
  all.sort((a, b) => (onRail.get(a.at) ?? 1e6) - (onRail.get(b.at) ?? 1e6));
  const rows = [
    ...all.map((p) => {
      const board = p.type === "board";
      // **What a row is**, said by its icon, its tint and its first chip: the
      // icon is the sidebar's own (his pick, or the type's), so a page looks the
      // same here as on the rail.
      const kind = built.has(p.at) ? "built" : p.type === "deck" ? "deck" : board ? "board" : "page";
      const chips = [
        { built: "Built In", deck: "Deck", board: "Board", page: "Page" }[kind],
        syncOf(sectionNamed(p.at, front)) ? "Synced" : "",
        empty.has(p.at) ? "Empty" : "",
      ].filter(Boolean);
      return {
        key: p.at, name: p.name, chips, kind, icon: iconName(front.icons, p.at, defaultIcon({ at: p.at, type: p.type })),
        href: `${base}/${p.at}`, outside: false,
        shelf: shelfOf(front, p.at, p.name, "page", p.type), archived: isArchived(front, p.at),
        shown: board ? p.share === "link" : !hidden("sections", p.at), flip: `sections:${p.at}`,
        rename: renamable.has(p.at),
      };
    }),
    ...(front.documents || []).filter((d) => d.name).map((d) => ({
      key: `doc:${d.name}`, name: d.name, chips: [d.file ? "File" : "Link"], kind: d.file ? "file" : "link",
      icon: iconName(front.icons, `doc:${d.name}`, defaultIcon({ doc: true, file: Boolean(d.file) })),
      href: d.file ? fileUrl(base, d) : d.url, outside: true,
      shelf: shelfOf(front, `doc:${d.name}`, d.name, "doc"), archived: isArchived(front, `doc:${d.name}`),
      shown: !hidden("documents", d.name), flip: `documents:${d.name}`, rename: true,
    })),
  ];
  const live = rows.filter((r) => !r.archived);
  const archived = rows.filter((r) => r.archived);
  const lib = `${base}/library`;
  const form = (action, fields, inner, attrs = "") => `<form method="post" action="${esc(action)}" class="pmform"${attrs}>${
    fields.map(([k, v]) => `<input type="hidden" name="${k}" value="${esc(v)}">`).join("")}${inner}</form>`;
  const kinds = shelfList(front);
  const names = kinds.map((k) => k.name);

  // **The one switch**: shown to viewers. A plain form (the same flip the page
  // menus post), so it works with no script; `lib.js` saves it in place.
  const toggle = (flip, on, label, extra = "") => `<form method="post" action="${esc(base)}/visibility" class="fh-lswf">
      <input type="hidden" name="flip" value="${esc(flip)}"><input type="hidden" name="back" value="library">
      <button type="submit" class="fh-lsw" role="switch" aria-checked="${on}" aria-label="${esc(label)}"${admin ? "" : " disabled"}${extra}><i class="fx-sw${on ? " on" : ""}" aria-hidden="true"></i></button></form>`;
  const menu = (r) => `<details class="fh-lmenu"><summary aria-label="${esc(`${r.name} Options`)}" title="More">${mark(DOTS, 16)}</summary><div class="pmcard">${[
    r.archived ? "" : `<div class="pmlabel">Move To</div>${names.filter((n) => n !== r.shelf).map((n) =>
      form(lib, [["shelf", r.key], ["to", n]], `<button type="submit" class="pmitem">${esc(n)}</button>`)).join("")}`,
    form(lib, [["archive", r.key], ["on", r.archived ? "0" : "1"]], `<button type="submit" class="pmitem">${r.archived ? "Unarchive" : "Archive"}</button>`),
  ].join("")}</div></details>`;
  const row = (r) => `<div class="fh-lrow${r.shown ? "" : " fh-loff"}" data-kind="${esc(r.kind)}" data-key="${esc(r.key)}" data-name="${esc(r.name)}" data-shelf="${esc(r.shelf)}" data-href="${esc(r.href)}"${
    r.outside ? ' data-outside="1"' : ""}${r.rename ? ' data-rename="1"' : ""} data-archived="${r.archived ? 1 : 0}" data-shown="${r.shown ? 1 : 0}" data-find="${esc(r.name.toLowerCase())}">
      <span class="fh-lico" aria-hidden="true">${mark(ROW_ICONS[r.icon] || ROW_ICONS.page, 17)}</span>
      <a class="fh-lname" ${r.outside ? `href="${esc(r.href)}" target="_blank" rel="noopener noreferrer"` : `data-deep="record" href="${esc(r.href)}"`}>${esc(r.name)}</a>
      ${r.chips.length ? `<span class="fh-lchips">${r.chips.map((c) => `<span class="fh-lchip">${esc(c)}</span>`).join("")}</span>` : ""}
      ${r.archived ? "" : toggle(r.flip, r.shown, `${r.name} · Shown to Viewers`)}
      ${menu(r)}</div>`;
  const CHEVRON = '<path d="M6 4.2 9.8 8 6 11.8"/>';
  const head = (name, count, icon = "page", extra = "") => `<summary class="fh-lhead"${extra}><span class="fh-hico" aria-hidden="true">${mark(ROW_ICONS[icon] || ROW_ICONS.page, 18)}</span><b>${esc(name)}</b><span class="fh-lct">${esc(count)}</span><span class="fh-lchev">${mark(CHEVRON, 14)}</span></summary>`;
  const shownOf = (list) => `${list.filter((r) => r.shown).length} of ${list.length} shown`;

  const firstFull = kinds.findIndex((k) => live.some((r) => r.shelf === k.name));
  const catMenu = (k, n) => `<details class="fh-lcatmenu"><summary aria-label="${esc(`${k.name} Options`)}" title="Category">${mark(DOTS, 16)}</summary><div class="pmcard">${[
    form(lib, [["category", "rename"], ["shelf", k.id]],
      `<input class="fx-pop-field" name="name" value="${esc(k.name)}" maxlength="40" aria-label="Category Name" required><button type="submit" class="pmitem">Rename</button>`, " data-nameform"),
    k.builtIn ? "" : form(lib, [["category", "remove"], ["shelf", k.id]], `<button type="submit" class="pmitem">Remove</button>`,
      ` data-confirm="${esc(`Remove ${k.name}? ${n ? `Its ${n === 1 ? "page goes" : `${n} pages go`} back to the category each would be filed in. ` : ""}Nothing is deleted.`)}"`),
  ].join("")}</div></details>`;
  const cats = kinds.map((k, i) => {
    const list = live.filter((r) => r.shelf === k.name);
    return `<section class="fh-lcat" id="shelf-${esc(k.id)}" data-shelfid="${esc(k.id)}" data-shelfname="${esc(k.name)}"${k.builtIn ? ' data-builtin="1"' : ""}>
      <details class="fh-lfold"${i === firstFull ? " open" : ""}>${head(k.name, list.length ? shownOf(list) : "0 pages", shelfIcon(k.id))}
        <div class="fh-lrows">${list.map(row).join("") || `<p class="fh-lnone">No pages</p>`}</div>
      </details>${catMenu(k, list.length)}</section>`;
  }).join("");

  // **Crew**: per person, shown to viewers and whose contact details a viewer
  // gets — the same lists What Viewers See keeps. An administrator's.
  const crew = everyone(front).filter((one) => one.name);
  const crewCard = admin && crew.length ? `<section class="fh-lcat fh-lcrew" id="shelf-crew">
      <details class="fh-lfold">${head("Crew", `${crew.filter((one) => !hidden("crew", one.name)).length} of ${crew.length} shown`, "people")}
        <div class="fh-lrows"><div class="fh-lcols" aria-hidden="true"><span>Shown</span><span>Contact</span></div>${crew.map((one) => {
          const shown = !hidden("crew", one.name);
          const contact = (visible.contact || []).includes(String(one.name));
          const under = [one.role, one.company].filter(Boolean).join(" · ");
          return `<div class="fh-lrow fh-lperson${shown ? "" : " fh-loff"}" data-person="${esc(one.name)}" data-find="${esc(one.name.toLowerCase())}">
            <span class="fh-lname">${esc(one.name)}${under ? `<small>${esc(under)}</small>` : ""}</span>
            ${toggle(`crew:${one.name}`, shown, `${one.name} · Shown`, ' data-kind="crew"')}
            ${toggle(`contact:${one.name}`, contact, `${one.name} · Contact`, ' data-kind="contact"')}</div>`;
        }).join("")}</div>
      </details></section>` : "";
  const archiveCard = archived.length ? `<section class="fh-lcat fh-larch" id="shelf-archive">
      <details class="fh-lfold">${head("Archive", String(archived.length), "documents")}
        <div class="fh-lrows">${archived.map(row).join("")}</div>
      </details></section>` : "";

  const PLUSM = mark(PLUS, 13);
  return `<div class="fh2 deep"${accent(front)}>
    ${railFor(base, title, front, "library", who, role, many ? "/" : "", toolShare(base, role, who, tools), visible, admin)}
    ${phoneParts(base, title, front, { name: "Library", n: live.length || "" }, toolShare(base, role, who, tools), many ? "/" : "", true)}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="inner fh-lpane" data-lib="${esc(lib)}" data-base="${esc(base)}"${admin ? " data-admin" : ""} data-shelves="${esc(JSON.stringify(names))}">
      <h1>Library</h1>
      ${said ? `<p class="warn">${esc(said)}</p>` : ""}
      <div class="fh-ltools">
        <label class="fh-lsearch">${mark(SEARCH, 15)}<input type="search" data-lfind placeholder="Search ${live.length} ${live.length === 1 ? "page" : "pages"}" autocomplete="off" aria-label="Search Pages"></label>
        <a class="fh-lbtn" data-laddpage href="${esc(base)}/add">${PLUSM}<span>New Page</span></a>
        <details class="fh-laddcat"><summary class="fh-lbtn">${PLUSM}<span>Add Category</span></summary><div class="pmcard">${
          form(lib, [["category", "add"]], `<input class="fx-pop-field" name="name" placeholder="Category name" maxlength="40" aria-label="Category Name" required><button type="submit" class="pmitem">Add</button>`)}</div></details>
      </div>
      <div class="fh-lpills" role="group" aria-label="Filter">
        <button type="button" class="fh-lpill" data-lfilter="all" aria-pressed="true">All</button>
        <button type="button" class="fh-lpill" data-lfilter="hidden" aria-pressed="false">Hidden</button>
        <span class="fh-lcount" data-lcount>${shownOf(live)}</span>
      </div>
      <div class="fh-lcats">${cats}</div>
      <p class="fh-lnomatch" data-lnomatch hidden>No pages match</p>
      ${crewCard}${archiveCard}
    </div></div></main>
  </div>`;
}

export function libraryBody(base, title, front, who, role, many, said = "", tools = {}) {
  if (role === "editor") return pagesBody(base, title, front, who, role, many, said, tools);
  const visible = tools.visible || emptyVisible();
  const admin = Boolean(tools.admin);
  const editor = role === "editor";
  const { pages, docs } = libraryItems(front, visible, role, who, admin);

  // **One list of cards, pages and documents alike**, each knowing its own
  // address, its shelf and the facts its menu switches.
  const kindOf = (p) => (p.built ? "Built In" : p.type === "deck" ? "Deck" : p.type === "board" ? "Board" : "Page");
  // **Pages stand in the sidebar's own order** (headings first, then what is
  // not filed), so a shelf reads the way the sidebar does.
  const onRail = new Map(railGroups(front, pages).flatMap((g) => g.rows).map((p, i) => [p.at, i]));
  pages.sort((a, b) => onRail.get(a.at) - onRail.get(b.at));
  // **Built In pages show a number only when the film really has one** — the
  // scenes and shots, the places, the plans, the days. Never a guess.
  const counts = front.counts || {};
  const builtFact = (at) => {
    const n = { shotlist: shotListCount(front), diagrams: counts.diagrams, locations: counts.locations, schedule: counts.days,
      boards: counts.boards, people: recordCount(at, front, visible, role, admin), documents: recordCount(at, front, visible, role, admin) }[at] || 0;
    if (!n) return null;
    const noun = { shotlist: "Scenes", diagrams: "Plans", locations: "Places", schedule: "Days", boards: "Boards", people: "Contacts", documents: "Pinned" }[at];
    return { n, noun: n === 1 ? noun.replace(/s$/, "") : noun, more: at === "shotlist" && counts.shots ? `${counts.shots} ${counts.shots === 1 ? "Shot" : "Shots"}` : "" };
  };
  const cards = [
    ...pages.map((p) => ({
      key: p.at, at: p.at, name: p.name, kind: kindOf(p), meta: "", href: `${base}/${p.at}`, outside: false,
      cv: p.built ? (p.at === "script" ? "script" : "built") : p.type === "deck" ? "deck" : p.type === "board" ? "board" : "page",
      fact: p.built ? builtFact(p.at) : null,
      said: p.built ? null : (tools.covers || {})[p.at] || null,
      shelf: shelfOf(front, p.at, p.name, "page", p.type), archived: isArchived(front, p.at),
      onSidebar: !offSidebar(front, p.at), onLinks: p.type === "board" ? p.share === "link" : !(visible.sections || []).includes(p.at),
      flip: `sections:${p.at}`, type: p.type, doc: false,
      icon: iconName(front.icons, p.at, defaultIcon({ at: p.at, type: p.type })),
    })),
    ...docs.map((d) => ({
      key: `doc:${d.name}`, name: d.name, kind: d.file ? "File" : "Link", cv: d.file ? "file" : "link",
      ext: d.file ? d.file.split(".").pop().toUpperCase() : "", size: d.file ? sizeSaid(d.bytes) : "", host: d.file ? "" : hostOf(d.url),
      meta: d.file ? [d.file.split(".").pop().toUpperCase(), sizeSaid(d.bytes)].filter(Boolean).join(" · ") : hostOf(d.url),
      href: d.file ? fileUrl(base, d) : d.url, outside: true,
      shelf: shelfOf(front, `doc:${d.name}`, d.name, "doc"), archived: isArchived(front, `doc:${d.name}`), onSidebar: !offSidebar(front, `doc:${d.name}`), at: `doc:${d.name}`,
      onLinks: !(visible.documents || []).includes(d.name),
      flip: `documents:${d.name}`, doc: true,
      icon: iconName(front.icons, `doc:${d.name}`, defaultIcon({ doc: true, file: Boolean(d.file) })),
    })),
  ];

  const form = (action, fields, inner, attrs = "") => `<form method="post" action="${esc(action)}" class="pmform"${attrs}>${
    fields.map(([k, v]) => `<input type="hidden" name="${k}" value="${esc(v)}">`).join("")}${inner}</form>`;
  const toggle = (action, fields, on, label) => form(action, fields,
    `<button type="submit" class="pmitem pmswitch${on ? " on" : ""}" aria-pressed="${on}">${label}<i></i></button>`);

  // **The card's own menu**: an editor's. Pinned, Private (an administrator's
  // — the same form the Visibility panel posts), Move To and Archive. A
  // `<details>`, so it opens with no script.
  const menu = (c) => {
    if (!editor) return "";
    const lib = `${base}/library`;
    const items = [
      c.doc ? "" : toggle(lib, [["sidebar", c.at], ["on", c.onSidebar ? "0" : "1"]], c.onSidebar, "Pinned"),
      admin ? toggle(`${base}/visibility`, [["flip", c.flip], ["back", "library"]], !c.onLinks, "Private") : "",
      `<div class="pmlabel">Move To</div>`,
      ...shelfNames(front).filter((n) => n !== c.shelf).map((n) => form(lib, [["shelf", c.key], ["to", n]], `<button type="submit" class="pmitem">${esc(n)}</button>`, ` data-was="${esc(c.shelf)}"`)),
      form(lib, [["archive", c.at], ["on", c.archived ? "0" : "1"]], `<button type="submit" class="pmitem">${c.archived ? "Unarchive" : "Archive"}</button>`),
    ].filter(Boolean);
    return `<details class="fh-cardmenu"><summary title="More" aria-label="More">${mark(DOTS, 16)}</summary><div class="pmcard">${items.join("")}</div></details>`;
  };

  // **A small lock for the people who set it**, where the card used to carry
  // words: the page is Private, so only editors see it.
  const states = (c) => (editor && !c.onLinks ? [`<span class="fh-tag fh-lock" title="Private">${mark(LOCK, 11)}</span>`] : []);

  const renamable = new Set(sectionsOf(front).filter((p) => p.page).map((p) => p.at));
  const follows = { follow: Object.fromEntries((front.sections || []).filter((one) => one.follow).map((one) => [one.slug, Boolean(one.follow.on)])) };
  const ARROW = `<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><path d="M2.5 9.5 9.5 2.5M4 2.5h5.5V8" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  /**
   * **A cover is type and colour, never a picture** (move 6): a deck is
   * landscape in a deep wash of the film's colour, a written page, file or
   * script is paper, a board is a grid of pins, a link shows where it goes and
   * a Built In page shows its number. Decorative (`aria-hidden`): the name and
   * the quiet line under it are what a reader hears.
   */
  // A Built In page with no number of its own wears the film's mark, faint.
  const MARK = (front && front.mark && front.mark.path)
    ? `<svg viewBox="0 0 20 20" width="34" height="34" aria-hidden="true"><path fill="currentColor" d="${esc(front.mark.path)}"/></svg>` : "";
  const cover = (c) => {
    // **The name lives under the cover, once**, and the kind is the cover's
    // shape: so a cover carries no words of its own, only a Built In page's
    // one number. His note, 2026-10-03: too much said twice.
    const lines = `<span class="lines"><i></i><i></i><i></i><i></i><i></i><i></i></span>`;
    let inner = "";
    // **One real thing each**, from `covers.js`: a deck's own first heading
    // and its slides, a written page's first heading, a board's pin count.
    const said = c.said || {};
    if (c.cv === "deck") {
      inner = said.title || said.n
        ? `${said.title ? `<span class="cvt">${esc(said.title)}</span>` : ""}${said.n ? `<span class="cvn">${esc(said.n)}</span>` : ""}`
        : `<span class="slide"><i></i><i></i><i></i></span>`;
    } else if (c.cv === "page") inner = `${said.title ? `<span class="cvt">${esc(said.title)}</span>` : ""}${lines}`;
    else if (c.cv === "script" || c.cv === "file") inner = lines;
    else if (c.cv === "board") {
      // As many tiles as there are pins, up to nine; nine when not yet counted.
      const tiles = typeof said.n === "number" ? Math.min(said.n, 9) : 9;
      inner = Array.from({ length: tiles }, () => "<i></i>").join("") + (said.n ? `<span class="cvn">${esc(said.n)}</span>` : "");
    }
    else if (c.cv === "link") inner = `<span class="host">${esc(c.host || "")}</span><span class="go">${ARROW}</span>`;
    else inner = c.fact ? `<span class="big">${esc(c.fact.n)}<small>${esc(c.fact.noun)}</small></span>` : `<span class="mk">${MARK}</span>`;
    return `<span class="fh-slot" aria-hidden="true"><span class="fh-cv ${esc(c.cv)}">${inner}</span></span>`;
  };
  const card = (c, shelf) => {
    // The quiet line says only what the cover and the name do not: a file's
    // size, a link's address, the shots behind a Shot List. "Built In" is not
    // news; the kind is, only where the cover cannot show it (a page vs a file).
    const note = c.cv === "built" ? (c.fact && c.fact.more) || ""
      : c.cv === "file" ? c.meta || c.kind : c.cv === "link" ? "Link"
      : c.cv === "script" ? "" : c.kind;
    const st = states(c);
    // **The card carries what the toolbar and the right-click menu need**:
    // its key, where it opens, and its state — read by `public/ctx.js`.
    return `<div class="fh-card" data-key="${esc(c.key)}" data-cv="${esc(c.cv)}" data-shelf="${esc(shelf)}" data-doc="${c.doc ? 1 : 0}" data-icon="${esc(c.icon)}" data-href="${esc(c.href)}" data-outside="${c.outside ? 1 : 0}" data-side="${c.onSidebar ? 1 : 0}" data-archived="${c.archived ? 1 : 0}"${
      editor ? ` data-links="${c.onLinks ? 1 : 0}"${renamable.has(c.at) || c.doc ? ' data-rename="1"' : ""}${followFlag(follows, c.at)}` : ""} data-name="${esc(c.name)}" data-find="${esc(`${c.name} ${c.kind} ${c.shelf}`.toLowerCase())}">${
      editor ? `<label class="fh-pick"><input type="checkbox" aria-label="Select ${esc(c.name)}"></label>` : ""}
      <a class="fh-cardlink" ${c.outside ? `href="${esc(c.href)}" target="_blank" rel="noopener noreferrer"` : `data-deep="record" href="${esc(c.href)}"`}>
        ${cover(c)}<span class="fh-meta"><b><span class="ico">${mark(ROW_ICONS[c.icon], 14)}</span>${esc(c.name)}</b>
        <span class="fh-cardkind">${esc(note)}</span>${st.length ? `<span class="fh-cardstate">${st.join("")}</span>` : ""}</span>
      </a>${menu(c)}</div>`;
  };

  const live = cards.filter((c) => !c.archived);
  const archived = cards.filter((c) => c.archived);
  // **The film's own shelves, in his order** (`front.shelves`). An empty one
  // stays out of a reader's way; an editor sees one he added while it is
  // still empty, so it is there to move things onto.
  const kinds = shelfList(front);
  const shelves = kinds.map((one) => ({ ...one, list: live.filter((c) => c.shelf === one.name) }))
    .filter((x) => x.list.length || (editor && !x.builtIn));
  /**
   * **A shelf's own menu, an editor's** (2026-10-10, *"the categories should
   * be renamable, and I should be able to add new ones"*): Rename in place,
   * Move Up and Down, and Remove for one he added — what stands on it goes
   * back where it would be filed anyway, and the button says so first.
   */
  const lib = `${base}/library`;
  const shelfMenu = (x) => {
    if (!editor) return "";
    const at = kinds.findIndex((one) => one.id === x.id);
    const items = [
      form(lib, [["category", "rename"], ["shelf", x.id]],
        `<input class="fx-pop-field" name="name" value="${esc(x.name)}" maxlength="40" aria-label="Category name" required><button type="submit" class="pmitem">Rename</button>`, ' data-nameform'),
      at > 0 ? form(lib, [["category", "move"], ["shelf", x.id], ["to", "up"]], `<button type="submit" class="pmitem">Move Up</button>`) : "",
      at < kinds.length - 1 ? form(lib, [["category", "move"], ["shelf", x.id], ["to", "down"]], `<button type="submit" class="pmitem">Move Down</button>`) : "",
      x.builtIn ? "" : form(lib, [["category", "remove"], ["shelf", x.id]], `<button type="submit" class="pmitem">Remove Category</button>`,
        ` data-confirm="${esc(`Remove ${x.name}? ${x.list.length ? `Its ${x.list.length === 1 ? "item goes" : `${x.list.length} items go`} back to the category each would be filed in. ` : ""}Nothing is deleted.`)}"`),
    ].filter(Boolean);
    return `<details class="fh-shelfmenu"><summary title="Category" aria-label="${esc(x.name)} options">${mark(DOTS, 16)}</summary><div class="pmcard">${items.join("")}</div></details>`;
  };
  const addShelf = editor ? `<details class="fh-addshelf"><summary class="fh-tool" title="Add Category">Add Category</summary><div class="pmcard">${
    form(lib, [["category", "add"]], `<input class="fx-pop-field" name="name" placeholder="Category name" maxlength="40" aria-label="New category name" required><button type="submit" class="pmitem">Add</button>`)}</div></details>` : "";

  return `<div class="fh2 deep"${accent(front)}>
    ${railFor(base, title, front, "library", who, role, many ? "/" : "", toolShare(base, role, who, tools), visible, admin)}
    ${phoneParts(base, title, front, { name: "Library", n: cards.length || "" }, toolShare(base, role, who, tools), many ? "/" : "", role === "editor")}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="inner fh-libpane" data-view="cards" data-lib="${esc(base)}/library"${
      editor ? ` data-editor="1"` : ""}${admin ? ` data-admin="1"` : ""} data-shelves="${esc(JSON.stringify(shelfNames(front)))}">
      <h1>Library</h1>
      ${said ? `<p class="warn">${esc(said)}</p>` : ""}
      ${cards.length ? `<div class="fh-libtools">${
        cards.length > 6 ? `<input class="fh-libfind" type="search" data-libfind placeholder="Search Library" autocomplete="off" aria-label="Search Library">` : `<span></span>`}
        <div class="fh-seg" role="group" aria-label="View"><button type="button" data-view="cards" aria-pressed="true">Category</button><button type="button" data-view="list" aria-pressed="false">List</button></div>${
        editor ? `<button type="button" class="fh-tool" data-select>Select</button>${addShelf}` : ""}</div>` : ""}
      ${shelves.length > 1 ? `<nav class="fh-shelves" aria-label="Category"><a href="#" class="on" data-shelf="all" aria-pressed="true">All<i>${cards.length}</i></a>${shelves.map((x) =>
        `<a href="#${shelfId(x.id)}" data-shelf="${shelfId(x.id)}" aria-pressed="false">${esc(x.name)}<i>${x.list.length}</i></a>`).join("")}${
        editor && archived.length ? `<a href="#shelf-archive" data-shelf="shelf-archive" aria-pressed="false">Archive<i>${archived.length}</i></a>` : ""}</nav>` : ""}
      ${shelves.map((x) => `<section class="fh-shelf" id="${shelfId(x.id)}" data-shelfid="${esc(x.id)}">
        <h2>${mark(ROW_ICONS[shelfIcon(x.id)] || ROW_ICONS.page, 16)}${esc(x.name)}<span>${x.list.length}</span><button type="button" class="fh-more" data-more hidden>See All</button>${shelfMenu(x)}</h2>
        <div class="fh-cards">${x.list.map((c) => card(c, x.name)).join("") || `<p class="fh-shelfempty">Empty</p>`}</div></section>`).join("") || `<p class="empty">Empty</p>`}
      ${editor && archived.length ? `<details class="fh-archive" id="shelf-archive"><summary>Archive<span>${archived.length}</span></summary>
        <div class="fh-cards">${archived.map((c) => card(c, c.shelf)).join("")}</div></details>` : ""}
      ${editor ? `<div class="fh-bulk" role="toolbar" aria-label="Selected" hidden></div>` : ""}
    </div></div></main>
  </div>`;
}

/**
 * **Every page a film offers** — the rail's rows and his own pages — the list
 * What Viewers See draws (less the archived ones) and the Library holds. One
 * expression, so the panel, the checklist and the Projects Console's door
 * name the same pages.
 */
export function offeredPages(front) {
  return railRows(front).concat(sectionsOf(front).filter((p) => p.page));
}

/**
 * **What the sidebar's Add Pages panel lists** (`GET <film>/library?part=pick`,
 * 2026-10-11): every page not archived, its category and whether it is on the
 * sidebar now, and the categories in his order.
 */
export function sidebarPicks(front) {
  return {
    shelves: shelfList(front).map((one) => ({ id: one.id, name: one.name })),
    pages: offeredPages(front).filter((p) => !isArchived(front, p.at)).map((p) => ({
      at: p.at, name: p.name, shelf: shelfIdOf(front, p.at, p.name, "page", p.type || ""), on: !offSidebar(front, p.at),
    })).concat((front.documents || []).filter((d) => d.name && !isArchived(front, `doc:${d.name}`)).map((d) => ({
      // a link or a file can be on the sidebar too: a row that opens it
      at: `doc:${d.name}`, name: d.name, shelf: shelfIdOf(front, `doc:${d.name}`, d.name, "doc"), on: !offSidebar(front, `doc:${d.name}`),
    }))),
  };
}

/**
 * **What Viewers See, as data** — the Projects Console's door (2026-10-05).
 * The same rows `visibilityForm` and `visibilityChecks` draw, each with what
 * its switch says: a page `shown` (a board is shown when it is shared with the
 * link), a person `shown` and `contact`, a document `shown`. An empty page
 * says so (`empty`): it stays off a reader's rail whatever is ticked.
 */
export function viewersSeeOf(front, visible) {
  const hidden = (kind, key) => (visible[kind] || []).includes(String(key));
  const empty = new Set(unfilled(front, visible));
  return {
    sections: offeredPages(front).filter((p) => !isArchived(front, p.at)).map((p) => (p.type === "board"
      ? { at: p.at, name: p.name, board: true, share: p.share || "", shown: p.share === "link" }
      : { at: p.at, name: p.name, shown: !hidden("sections", p.at), ...(empty.has(p.at) ? { empty: true } : {}) })),
    crew: everyone(front).filter((one) => one.name).map((one) => ({
      name: one.name, shown: !hidden("crew", one.name), contact: (visible.contact || []).includes(String(one.name)),
    })),
    documents: (front.documents || []).filter((d) => d.name && !isArchived(front, `doc:${d.name}`)).map((d) => ({ name: d.name, shown: !hidden("documents", d.name) })),
  };
}

/**
 * **The sidebar, as data** — the Projects Console's Portal tab (2026-10-10).
 * His ask: everything the rail can do, from the console, without the console
 * keeping a second copy of how. So this only says how the rail stands — each
 * heading and the pages under it, as `inGroups` lays the rail out — and every
 * change goes back through the portal's own routes (`/order`, `/add`, a
 * page's rename, the Library's `icon`). Pages off the sidebar are listed in
 * `pages` with `pinned: false` and are not in `sidebar`.
 */
export function sidebarStateOf(front) {
  // **A link or a file is a row like any page** (2026-10-13): `doc:<name>`,
  // in its category, in the order, with its own icon, renamable.
  const docs = (front.documents || []).filter((d) => d && d.name && !isArchived(front, `doc:${d.name}`))
    .map((d) => ({ at: `doc:${d.name}`, name: d.name, doc: true, file: d.file || "", url: d.url || "" }));
  const pages = offeredPages(front).filter((p) => !isArchived(front, p.at)).concat(docs);
  const pinned = pages.filter((p) => !offSidebar(front, p.at));
  const own = new Map((front.sections || []).map((one) => [one.slug, one]));
  return {
    sidebar: railGroups(front, pinned).map((g) => ({ head: g.head || "", rows: g.rows.map((p) => p.at) })),
    rows: pages.map((p) => ({
      at: p.at, name: p.name, type: p.doc ? (p.file ? "file" : "link") : p.type || (p.page ? "page" : "built"),
      icon: iconName(front.icons, p.at, defaultIcon(p.doc ? { doc: true, file: Boolean(p.file) } : { at: p.at, type: p.type })),
      pinned: !offSidebar(front, p.at),
      // **Every page may be renamed** (his ask, 2026-10-10: *"I should just
      // be able to rename any page that's on the portal"*). His own move to
      // the new name's address; a built-in page or one Notion names keeps its
      // address and wears the new name (`front.labels`).
      renamable: true,
      notion: Boolean(own.has(p.at) && own.get(p.at).notion),
    })),
    icon_choices: ICON_CHOICES,
    icon_paths: Object.fromEntries(ICON_CHOICES.map((k) => [k, ROW_ICONS[k]])),
  };
}

/**
 * **The Library, as data** — each page and document with its two settings and
 * whether it is archived, as the Library's own cards say them: `pinned` (a row
 * in the sidebar), `private` (only an editor may see it; a board is private
 * unless it is shared with the link), `archived`.
 */
export function libraryStateOf(front, visible) {
  return {
    pages: offeredPages(front).map((p) => ({
      at: p.at, name: p.name,
      shelf: shelfIdOf(front, p.at, p.name, "page", p.type || ""),
      pinned: !offSidebar(front, p.at),
      private: p.type === "board" ? p.share !== "link" : (visible.sections || []).includes(p.at),
      archived: isArchived(front, p.at),
      ...(p.type === "board" ? { board: true } : {}),
    })),
    documents: (front.documents || []).filter((d) => d.name).map((d) => ({
      name: d.name,
      shelf: shelfIdOf(front, `doc:${d.name}`, d.name, "doc"),
      kind: d.file ? "file" : "link",
      icon: iconName(front.icons, `doc:${d.name}`, defaultIcon({ doc: true, file: Boolean(d.file) })),
      pinned: !offSidebar(front, `doc:${d.name}`),
      private: (visible.documents || []).includes(d.name),
      archived: isArchived(front, `doc:${d.name}`),
    })),
    // **The film's shelves** (2026-10-10), in order: `{ id, name, builtIn, icon }`.
    // `shelf` on each page and document above is one of these ids.
    shelves: shelfList(front).map((one) => ({ ...one, icon: shelfIcon(one.id) })),
  };
}

/**
 * The pages the iPhone app draws from the film itself, never from here: its
 * own Shot List, Script, Diagrams, Locations, Schedule and Reference Images.
 */
const PHONE_OWN = new Set(["shotlist", "script", "diagrams", "locations", "schedule", "boards"]);

/**
 * **The Library for the iPhone app** — Ref 1541 Stage C, read through the
 * phone's door (`phoneDoor` in `worker.js`). The same pages and documents the
 * Library's cards are made of (`libraryItems`, as he sees them: owner and
 * editor, so Private and the Archive are in), each with what the phone needs
 * to file and fetch it:
 *
 * - `kind`: `built` (a Built In page), `page`, `deck`, `board`, `file`, `link`
 * - `film`: a page the phone draws from the film itself (`PHONE_OWN`); listed
 *   so its shelf and pin are known, never fetched
 * - `shelf`, `pinned` (a row in the sidebar), `private`, `archived`, `icon`
 * - `tree` / `html` / `deck`: which of `pages/<at>.json`, `pages/<at>.html`
 *   and `decks/<at>.json` exist, and `stamp` the newest of their times, so
 *   the phone fetches only what changed (`stored` is `{key: ms}` from one
 *   listing of each folder). **A published page says `tree` too**: the door
 *   reads it back into blocks (`treeFromHtml`), so a phone draws it as any
 *   written page, never as HTML; its stamp is one past its newest time, so
 *   a phone holding the stored tree it showed before asks again once.
 * - a deck's printed copy as `pdf` (`deckBar`'s rule: a lookbook document of
 *   the deck's name); a document's `file`, `bytes` and `ext`, or its `url`
 */
export function phoneLibraryOf(front, visible, stored = {}, carried = {}) {
  const who = { email: "", via: "phone" };
  const { pages, docs } = libraryItems(front, visible, "editor", who, true);
  const onRail = new Map(railGroups(front, pages).flatMap((g) => g.rows).map((p, i) => [p.at, i]));
  pages.sort((a, b) => onRail.get(a.at) - onRail.get(b.at));
  const has = (key) => (stored[key] ? stored[key] : 0);
  const items = pages.map((p) => {
    // `carried`: a page published with a board in it (the worker looked), which
    // the phone draws as the board it is (Ref 1562).
    const kind = p.built ? "built" : carried[p.at] ? "board" : p.type === "deck" ? "deck" : p.type === "board" ? "board" : "page";
    const times = { tree: has(`pages/${p.at}.json`), html: has(`pages/${p.at}.html`), deck: has(`decks/${p.at}.json`) };
    const one = {
      key: p.at, name: p.name, kind,
      shelf: shelfOf(front, p.at, p.name, "page", p.type),
      shelfId: shelfIdOf(front, p.at, p.name, "page", p.type),
      pinned: !offSidebar(front, p.at),
      private: p.type === "board" ? p.share !== "link" : (visible.sections || []).includes(p.at),
      archived: isArchived(front, p.at),
      icon: iconName(front.icons, p.at, defaultIcon({ at: p.at, type: p.type })),
    };
    if (PHONE_OWN.has(p.at)) one.film = true;
    if (times.tree || times.html) one.tree = true;
    if (times.html) one.html = true;
    if (times.deck) one.deck = true;
    const stamp = Math.max(times.tree, times.html, times.deck);
    if (stamp) one.stamp = times.html ? stamp + 1 : stamp;
    if (kind === "board" && carried[p.at]) {
      one.published = true;
      if (carried[p.at].stamp) one.stamp = Math.max(one.stamp || 0, carried[p.at].stamp);
    } else if (kind === "board") {
      const sec = sectionNamed(p.at, front) || {};
      one.share = p.share || "me";
      const kept = sec.board ? has(`boards/${sec.board}.json`) : 0;
      if (kept) one.stamp = Math.max(one.stamp || 0, kept);
    }
    if (kind === "deck") {
      const pdf = (front.documents || []).find((d) => d.kind === "lookbook" && d.file && d.name === p.name);
      if (pdf) one.pdf = { file: pdf.file, name: fileNameOf(pdf) || "", bytes: pdf.bytes || 0 };
    }
    return one;
  });
  for (const d of docs) {
    const key = `doc:${d.name}`;
    items.push({
      key, name: d.name, kind: d.file ? "file" : "link",
      shelf: shelfOf(front, key, d.name, "doc"),
      shelfId: shelfIdOf(front, key, d.name, "doc"),
      pinned: false,
      private: (visible.documents || []).includes(d.name),
      archived: isArchived(front, key),
      icon: iconName(front.icons, key, defaultIcon({ doc: true, file: Boolean(d.file) })),
      ...(d.file ? { file: d.file, bytes: d.bytes || 0, ext: d.file.split(".").pop().toLowerCase(), named: fileNameOf(d) || "" } : { url: d.url || "" }),
    });
  }
  // `shelves` is the names, as every phone before 2026-10-10 reads it;
  // `categories` is the same list with ids, which `shelfId` on each item names.
  const kinds = shelfList(front);
  return { shelves: kinds.map((one) => one.name), categories: kinds.map((one) => ({ ...one, icon: shelfIcon(one.id) })), items };
}

/**
 * **The film's record for the iPhone app** — his ask, 2026-10-06, after
 * TestFlight build 4: *"There's still a lot missing like camera spec sheet,
 * etc. everything should feel native. Don't want to click a link to the
 * portal."* Read through the phone's door (`GET /phone/<film>/front`).
 *
 * Everything the portal's own record pages draw, worked out here by the same
 * code that draws them, so the phone only lays it out: the film's front page
 * (`homeBody`), the Camera Spec Sheet (`recordPage` "camera": its rows with
 * a line per camera, lens sets, LUT files with their labels, the notes page),
 * People by department, Documents, and **each shoot as its tab shows it**
 * (`shotView`): its sheet, its crew, its documents, its days and its own
 * pages, with what changed since the shoot before. As he sees it, an owner:
 * Private included, archived documents left to the Archive.
 *
 * `views` are `shotView(front, slug)` for each shoot (one, `shoot: ""`, for a
 * film that shoots once); `notes` the camera notes tree each view reads.
 */
export function phoneFrontOf(front, views, notes = []) {
  const shoots = front.shoots || [];
  const lead = leadShoot(front);
  const word = (one) => (one.status === "Wrapped" ? "Wrapped" : one === lead ? "Next" : "Upcoming");
  const home = views.find((v) => !v.shootOn || v.shootOn.lead) || views[0] || front;
  const cam = home.camera || {};
  const credits = [
    front.director ? { role: "Directed by", people: front.director } : null,
    front.producer ? { role: "Produced by", people: front.producer } : null,
    ...(front.credits || []).map((c) => ({ role: creditWords(c.role), people: creditLine(c.people) })),
  ].filter((c) => c && c.people);
  // **His key image, or none**: a scene's picture standing in for it would
  // be a cover nobody chose.
  const cover = front.key_image || "";
  const next = nextShootSaid(home);
  const film = {
    status: front.status || "", type: front.type || "", length: front.length || "",
    kind: [front.length, front.type].filter(Boolean).join(" "),
    credits,
    facts: [front.status, shootDates(front.shoot), ratioSaid(front.ratio), oneLine(cam.body)].filter(Boolean),
    logline: front.logline || "", note: front.note || "", look: front.look || "",
    key_image: front.key_image || "", cover,
    colour: (front.mark && front.mark.colour) || "",
    counts: front.counts || {},
    next: next ? { said: next.said, away: next.away } : null,
    days: shootDaysOf(home).map((d) => ({ label: d.label || "", date: d.date })),
  };
  const oneShoot = (one) => ({
    slug: one.slug, name: one.name, base: one.base && one.base !== one.name ? one.base : "",
    status: one.status || "", word: word(one), start: one.start || "", end: one.end || "",
    dates: shootDay(one), changes: one.changes || "", lead: one === lead,
  });
  const out = views.map((v, i) => phoneView(front, v, notes[i] || null));
  return {
    film,
    shoots: shoots.length >= 2 ? shoots.map(oneShoot) : [],
    views: out,
    pictures: [...new Set([cover, ...out.flatMap((v) => v.pictures)].filter(Boolean))],
  };
}

/** One shoot's tab (or the film's only one) as the phone draws it. */
function phoneView(front, v, notes) {
  const cam = v.camera || {};
  const was = v.was && v.was.camera ? v.was.camera : null;
  // In order of operation, in three groups (his ask, 2026-10-15): Camera,
  // Color, Deliverables — `group` on each row; the phone heads each group.
  const ratios = Array.isArray(cam.ratios) ? cam.ratios : [];
  const finishing = Array.isArray(cam.finishing_resolutions) ? cam.finishing_resolutions : [];
  const boxes = ["body", "format", "capture", "lenses", "desqueeze", "filters", "modifiers", "ratios", "fps", "codec", "colour", "finishing"];
  const labels = ["Camera", "Shooting Format", "Capture Resolution", "Lenses", "Desqueeze", "Filters", "Modifiers", "Aspect Ratio", "Frame Rate", "Codec", "Color Space", "Finishing Resolutions"];
  const props = ["Camera", "Shooting Format", "Capture Resolution", "Lenses", "Desqueeze", "Filters", "Modifiers", "Aspect Ratio", "Frame Rate", "Codec", "Color Space", "Finishing Resolutions"];
  const groupOf = (box) => (box === "colour" ? "Color" : box === "finishing" ? "Deliverables" : "Camera");
  const group = cameras(fieldsOfCard(cam), lensSetsShown(cam.lenses));
  const rows = [];
  let lenses = null;
  boxes.forEach((box, i) => {
    // the sheet's aspect ratios
    if (box === "ratios") {
      if (!ratios.length) return;
      const copy = ratios.map((f) => `${f.name} ${f.ratio}`.trim()).join("\n");
      // each ratio's frame guide files, flat, with the ratio they sit under (the phone downloads them)
      const guides = ratios.flatMap((f) => (f.guides || []).map((g) => ({ ratio: f.name, name: g.name || "", camera: g.camera || "", note: g.note || "", url: g.url || "" })));
      rows.push({ label: "Aspect Ratio", copy, lines: ratios.map((f) => ({ label: f.name, value: f.ratio })), group: "Camera", ...(guides.length ? { guides } : {}) });
      return;
    }
    if (box === "finishing") {
      if (!finishing.length) return;
      const copy = finishing.map((f) => [f.title, f.resolution, f.note].filter(Boolean).join(" · ")).join("\n");
      rows.push({ label: "Finishing Resolutions", copy, lines: finishing.map((f) => ({ label: f.title, value: [f.resolution, f.note].filter(Boolean).join(" · ") })), group: "Deliverables" });
      return;
    }
    const value = String(cam[box] || "");
    if (!value) return;
    const then = was ? String(was[box] || "") : null;
    const changed = then !== null && then.trim() !== value.trim();
    const change = changed ? { changed: true, was: then ? oneLine(then) : "" } : {};
    if (box === "lenses") {
      lenses = { copy: value, sets: lensSetsShown(value).map(({ label, series, focals, stop, notes: n, raw }) => ({ label, series, focals, stop, notes: n, raw, ...(cam.lens_cf && cam.lens_cf[raw] ? { cf: cam.lens_cf[raw] } : {}) })), ...change };
      return;
    }
    rows.push({ label: labels[i], copy: value, lines: cameraLines(group, props[i], value).map(([label, said]) => ({ label: label || "", value: said })), group: groupOf(box), ...change });
  });
  // the phone's list as it always was: a file it can open (a held one waits for its copy)
  const files = luts((v.camera_files || []).filter((one) => one.url || one.file).map((one) => ({ ...one, url: one.url || "" })), cam.luts).rows
    .map((one) => ({
      name: one.name || "", label: one.label || "", shown: one.shown || one.name || "",
      file: one.file || "", url: one.file ? "" : one.url || "", bytes: one.bytes || 0,
      ext: one.file ? one.file.split(".").pop().toLowerCase() : "", host: one.file ? "" : hostOf(one.url),
    }));
  const before = v.was ? new Set((v.was.crew || []).map((one) => one.name.trim().toLowerCase())) : null;
  const crew = byDepartment(v.crew || []).map(([department, list]) => ({
    department,
    people: list.map((one) => ({
      name: one.name, role: one.role || "", company: one.company || "",
      email: one.email || "", phone: one.phone || "",
      fresh: Boolean(before) && !before.has(one.name.trim().toLowerCase()),
    })),
  }));
  const documents = (v.documents || []).filter((doc) => !isArchived(front, `doc:${doc.name}`)).map((doc) => ({
    key: `doc:${doc.name}`, name: doc.name, kind: doc.file ? "file" : "link",
    file: doc.file || "", url: doc.file ? "" : doc.url || "", bytes: doc.bytes || 0,
    ext: doc.file ? doc.file.split(".").pop().toLowerCase() : "", host: doc.file ? "" : hostOf(doc.url),
  }));
  const own = v.shootOn ? ((v.shootPages || {})[v.shootOn.slug] || []) : [];
  const pages = own.map((slug) => sectionNamed(slug, front)).filter(Boolean).filter((one) => !isArchived(front, one.slug))
    .map((one) => ({ slug: one.slug, name: one.name }));
  const tree = Array.isArray(notes) && notes.length ? notes : null;
  return {
    shoot: v.shootOn ? v.shootOn.slug : "",
    was: v.was ? v.was.name : "",
    camera: { rows, lenses, files, notes: tree },
    crew,
    documents,
    pages,
    days: (v.days || []).filter((d) => d.date).map((d) => ({ label: d.label || "", date: d.date })),
    pictures: [...files.map((f) => f.file), ...(JSON.stringify(tree || null).match(/\b[0-9a-f]{32}\.[A-Za-z0-9]{1,8}\b/g) || [])].filter(Boolean),
  };
}

/**
 * **Who sees what, as a table.** Ref 1154, his pick of 2026-09-23 (option 1).
 *
 * It was one long column of full-width rows — Sections, People, then **the
 * same people again** under Contact Info, then Documents — so a crew of
 * twenty was forty-odd rows, each switch a screen's width from its name. Now:
 *
 * - **People are one row each with two switches side by side**, Shown and
 *   Contact. Contact is dimmed while Shown is off, because a number for
 *   somebody who is not shown is shown to nobody.
 * - **Sections and Documents are a grid of switches**, as many across as fit.
 * - **Save sticks to the bottom** of whatever it is in.
 *
 * **One form, two places.** The same markup is the Visibility tab of the Share
 * panel (fetched as `?part=1` by `public/share.js`) and the plain page at
 * `/visibility`, which is what a browser with no script gets. It is still a
 * plain form posting to its own address, for the reason it always was: it
 * decides who sees a crew member's mobile number.
 *
 * **Ticked is seen.** The store keeps the *hidden* ones — except Contact,
 * which is opt-in and keeps what was ticked. See `mayContact`.
 */
export function visibilityForm(base, front, visible, forMe = false) {
  const hidden = (kind, key) => (visible[kind] || []).includes(String(key));
  const knob = (kind, key, on, label) => `<input type="checkbox" class="vcb" name="${esc(kind)}" value="${esc(key)}"${
    on ? " checked" : ""} aria-label="${esc(label)}"><i class="fh-vtrack" aria-hidden="true"></i>`;
  // **Why a ticked page may still not show**: an empty page is left off a
  // reader's rail whatever is switched on here (`unfilled`).
  const empty = new Set(unfilled(front, visible));
  const cell = (kind, key, name, under, on = !hidden(kind, key)) => `<label class="vcell">
      <span class="vname">${esc(name)}${under ? `<small>${esc(under)}</small>` : ""}</span>
      ${knob(kind, key, on, name)}</label>`;
  // **A board is on Links when it is shared with the link** — its own switch
  // (`SHARES`), not the hidden list. Off says who it is for instead.
  const boardCell = (p) => cell("sections", p.at, p.name,
    p.share === "me" ? "Only Me" : p.share === "crew" ? "Crew" : "", p.share === "link");
  const sections = offeredPages(front).filter((p) => !isArchived(front, p.at));
  // **Every shoot's people** (Ref 1410), once each, saying which shoots.
  const crew = everyone(front);
  const said = (one) => [one.role, one.company, (one.shoots || []).join(", ")].filter(Boolean).join(" · ");
  const docs = (front.documents || []).filter((d) => !isArchived(front, `doc:${d.name}`));
  return `<form method="post" action="${esc(base)}/visibility" class="fh-visform">
    <div class="vpart vlinks">

    <div class="vhead">Sections</div>
    <div class="vgrid">${sections.map((p) => p.type === "board" ? boardCell(p)
      : cell("sections", p.at, p.name, empty.has(p.at) ? "Empty" : "")).join("")}</div>

    <div class="vhead">People</div>
    ${crew.length ? `<table class="vtable">
      <thead><tr><th>Name</th><th>Shown</th><th>Contact</th></tr></thead>
      <tbody>${crew.map((one) => {
        const under = said(one);
        // **Contact runs the other way**: off unless he turned it on.
        const contact = (visible.contact || []).includes(String(one.name));
        return `<tr>
          <td><span class="vname">${esc(one.name)}${under ? `<small>${esc(under)}</small>` : ""}</span></td>
          <td><label class="vsw">${knob("crew", one.name, !hidden("crew", one.name), `${one.name} shown`)}</label></td>
          <td><label class="vsw vcontact">${knob("contact", one.name, contact, `${one.name} contact`)}</label></td>
        </tr>`;
      }).join("")}</tbody>
    </table>` : `<p class="vnone">No Contacts</p>`}

    <div class="vhead">Documents</div>
    ${docs.length
      ? `<div class="vgrid">${docs.map((d) => cell("documents", d.name, d.name, "")).join("")}</div>`
      : `<p class="vnone">Empty</p>`}
    </div>

    <div class="vfoot"><button class="vsave" type="submit">Save</button><span class="vsaid" data-vsaid></span></div>
  </form>`;
}

/**
 * **What the Share popover's second tab draws** (`?part=2`): the same choices as
 * `visibilityForm`, the same field names, posting to the same address, laid out
 * as a checklist of the sidebar. Pages sit under the sidebar's own headings in
 * the sidebar's own order (`inGroups`, as `railFor` does), then the film's
 * Documents, then People with two narrow tick columns. Ticks are neutral
 * (`.fx-ck`); `public/share.js` keeps each one's `on` in step with its box and
 * saves the whole form on every change. The plain `/visibility` page is still
 * `visibilityForm`.
 */
export function visibilityChecks(base, front, visible, forMe = false) {
  const hidden = (kind, key) => (visible[kind] || []).includes(String(key));
  const empty = new Set(unfilled(front, visible));
  // An archived page is private and out of the way: not offered here.
  // **A link or a file stands under its category with the pages**, as it does
  // in the Library and on the sidebar, not in a list of its own at the bottom.
  const docRows = (front.documents || []).filter((d) => d.name && !isArchived(front, `doc:${d.name}`))
    .map((d) => ({ at: `doc:${d.name}`, name: d.name, doc: true }));
  const flat = offeredPages(front).filter((p) => !isArchived(front, p.at)).concat(docRows);
  const groups = railGroups(front, flat);
  const crew = everyone(front);
  const said = (one) => [one.role, one.company, (one.shoots || []).join(", ")].filter(Boolean).join(" · ");
  const tick = (name, value, on, label, extra = "") => `<input type="checkbox" class="vcb" name="${esc(name)}" value="${esc(value)}"${
    on ? " checked" : ""} aria-label="${esc(label)}"${extra}><i class="fx-ck${on ? " on" : ""}" aria-hidden="true"></i>`;
  // **A lock beside a page that is not ticked**: Private. Drawn always and
  // shown by the sheet when its box is off, so it follows a tick at once.
  const line = (name, value, on, label, note, extra, off) => `<label class="sp-li${off ? " dim" : ""}">${
    tick(name, value, on, label, extra)}<span class="sp-nm">${esc(label)}</span>${note ? `<small>${esc(note)}</small>` : ""}<span class="sp-lk" title="Private">${mark(LOCK, 12)}</span></label>`;
  const pagesOf = () => groups.map((g) => `${g.head ? `<div class="sp-grp">${esc(g.head)}</div>` : ""}${
    g.rows.map((p) => {
      if (p.doc) return line("documents", p.name, !hidden("documents", p.name), p.name, "", "");
      const board = p.type === "board";
      const on = board ? p.share === "link" : !hidden("sections", p.at);
      const note = board ? (p.share === "me" ? "Only Me" : p.share === "crew" ? "Crew" : "") : empty.has(p.at) ? "Empty" : "";
      return line("sections", p.at, on, p.name, note, " data-page", empty.has(p.at));
    }).join("")}`).join("");
  const people = crew.length
    ? `<div class="sp-grp">People</div>
       <div class="sp-ppl sp-pplh"><span></span><span>Shown</span><span>Contact</span></div>
       ${crew.map((one) => {
         const under = said(one);
         const shown = !hidden("crew", one.name);
         const contact = (visible.contact || []).includes(String(one.name));
         return `<div class="sp-ppl${shown ? "" : " dim"}"><span class="sp-nm">${esc(one.name)}${under ? `<small>${esc(under)}</small>` : ""}</span>
           <label class="sp-c">${tick("crew", one.name, shown, `${one.name} shown`, " data-shown")}</label>
           <label class="sp-c">${tick("contact", one.name, contact, `${one.name} contact`)}</label></div>`;
       }).join("")}`
    : `<div class="sp-grp">People</div><p class="sp-none">No Contacts</p>`;
  return `<form method="post" action="${esc(base)}/visibility" class="sp-vform">
    <div class="sp-part" data-part="links">${pagesOf()}${people}</div>
  </form>`;
}

export function visibilityBody(base, title, role, who, front, visible, many, tools = {}, forMe = false) {
  return `<div class="fh2 deep"${accent(front)}>
    ${railFor(base, title, front, "visibility", who, role, many ? "/" : "", toolShare(base, role, who, tools), visible, Boolean(tools.admin))}
    ${phoneParts(base, title, front, { name: "Visibility", n: "" }, toolShare(base, role, who, tools), many ? "/" : "", role === "editor")}
    <main class="paneshell"><div class="fh-pane scrolls"><div class="inner wide">
      <h1>What Viewers See</h1>
      ${visibilityForm(base, front, visible, forMe)}
    </div></div></main>
  </div>`;
}
