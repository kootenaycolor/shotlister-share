/**
 * **Projects Console, from the AI connector** (2026-10-19, his ask: "make sure
 * the mcp can do all actions in project console and shotlister that i can").
 *
 * The parity pass of 10-17 left the console's big actions to his hands: the
 * rituals and big moves, New Project, Create Portal, Replace Link, Take Down,
 * Shared, the Notion-versus-record questions, Customize Record and his
 * standards. His new words take that back. Each is here, as a thin door onto
 * **the code the apps already call** — `answerHere` (cloud.js), the asks the
 * Mac's router and the iPhone send, and for a run too long for one reply the
 * same mailbox and server minute (later.js) the phone's runs go through, so
 * nothing here is a second copy of a rule.
 *
 * **His OK in between** (consolegate.js): whatever moves, deletes, hides,
 * publishes or changes who can see something answers its preview and a
 * confirm token first, and runs only with that token. Everything here is his
 * alone (`isAdmin`), reads included.
 *
 * **His laws, kept in the doors these call and said in every description**:
 * nothing is trashed in a big move (bigmoves.js `noTrash`); Delete is a true
 * delete with a backup and 30 days of undo, never the media drives; media
 * drives are create-only (only a "Make media folders" Mac job, never a move);
 * Prepare Showcase copies exactly what the filing rules and
 * showcase-structure say (showcaseplan.js); Replace Link breaks every link
 * already sent. What only a Mac can do (a showcase's .webp pictures, Studio
 * told where a folder went, a media drive's folders, the agents) is the same
 * Mac job or mailbox ask the app leaves, and the answer says so.
 */
import { canonStage, shownStage } from "./stageword.js";
import { TWO_STEPS, twoSteps as gate } from "./consolegate.js";

/** Who the history and the mailbox say asked. The connector's own words. */
export const BY = "portal AI connector";

const ID32 = /^[0-9a-f]{32}$/;
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const str = (v, n = 400) => String(v == null ? "" : v).slice(0, n);
const bare = (v) => String(v || "").replace(/-/g, "").trim().toLowerCase();

class Declined extends Error {}

// ── the tools ────────────────────────────────────────────────────────────────

const CONFIRM = { type: "string", description: "The token step 1 answered. Only after his yes in the chat." };
const OPEN = "the open project";

export const CONSOLE_TOOLS = [
  {
    name: "big_move",
    description:
      "Projects Console's big moves on " + OPEN + ", run by the server as the app runs them (`kind`). **His laws**: nothing is sent to any trash by a big move except Delete; Delete is a true delete (Notion row and shoots, Drive folder, showcase, record, Studio side, portal), backed up first and undoable for 30 days (`undo_activity`), and it never touches a media drive (footage stays). Media drives are create-only. Prepare Showcase copies exactly what the filing rules and showcase-structure say: his selects in his order into select-stills/, credits.txt, never website/; its pictures are made on a Mac (an On a Mac job). Rename, Move and Delete need the project's name typed by him in the chat, passed as `typed_name`. " + TWO_STEPS,
    inputSchema: {
      type: "object",
      properties: {
        kind: { type: "string", description: "wrap (park it in Post: its shoot Wrapped, Shoot Dates move on), archive (Drive folder into z-archived/<year>/, showcase into zz-archived/<year>/, status Archived; portal, Studio and footage stay), move_drive (the Drive folder only, by Drive's own move, links keep working), rename (Notion, record, Drive folder and showcase together; ids and links kept; media folders never renamed), turn_off (showcase: moved into zz-archived, never trashed; website: the address forgotten), delete, or showcase (Prepare / Edit Showcase; a select he no longer picks moves to select-stills/z-archive/, a file already there is kept)." },
        new_name: { type: "string", description: "rename: the new name." },
        new_slug: { type: "string", description: "rename: the new folder name (lowercase-with-dashes)." },
        dest: { type: "string", description: "move_drive: projects, gigs, archive or custom." },
        folder: { type: "string", description: "move_drive custom: the Drive folder's id." },
        system: { type: "string", description: "turn_off: showcase or website." },
        typed_name: { type: "string", description: "rename, move_drive, delete: the project's name as he typed it in the chat." },
        confirm: CONFIRM,
      },
      required: ["kind"],
    },
  },
  {
    name: "set_stage",
    description:
      "Move " + OPEN + " to a stage, as the stage picker in Projects Console does. Development and Active apply at once, as in the app, except for an Archived project, which asks first (its folders stay in the archive). Complete, Post and Archived ask first, as the app's pop-up does: Complete \"Shows the selects on the portal home\"; its release date is optional (set_released `released_date`); Post is Wrap and Archived is Archive (both the big moves, with their plans). Closed is close_project. " + TWO_STEPS,
    inputSchema: {
      type: "object",
      properties: { stage: { type: "string", description: "Development, Active, Complete, Post or Archived. (Complete was called Released; either word works.)" }, confirm: CONFIRM },
      required: ["stage"],
    },
  },
  {
    name: "close_project",
    description:
      "Close Project… on " + OPEN + ": it leaves the console and the portal. Its snapshot (record, Notion row and shoots, Drive ids, the portal's pages) is saved as a <slug>.project file in its Drive folder and kept on the server; **nothing is deleted anywhere**; every link already sent answers \"This project is closed.\" at the same address; status becomes Closed. `reason`: Not Produced (the app's one reason). Undone with reopen_project. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { reason: { type: "string" }, confirm: CONFIRM }, required: [] },
  },
  {
    name: "closed_projects",
    description: "Every closed project (Reopen Project's list): its ID, name, when and why it was closed. No project need be open. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "reopen_project",
    description: "Reopen Project…: a closed project (its ID from closed_projects) back in the console and on the portal, its links opening again and its stage what it was. No project need be open. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { project: { type: "string", description: "Its ID, from closed_projects." }, confirm: CONFIRM }, required: ["project"] },
  },
  {
    name: "new_project",
    description:
      "New Project… as the console's sheet makes it, by the server: the Drive folder from his template, the Notion row (a Project; a Job gets a Job Log row instead), the record, the portal, the Studio modes, and a media drive's template folders (an On a Mac job, create-only) when `volume` is named. With no `name`, answers the sheet's choices and writes nothing. Project or Job is his pick, by how big the shoot is: ask him if he hasn't said. " + TWO_STEPS,
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string" }, drive_name: { type: "string", description: "The folder name, lowercase-with-dashes; made from the name when left out." },
        job: { type: "boolean", description: "true: a Job (a loose Drive folder and a Job Log row, no ceremony)." }, type: { type: "string" },
        length: { type: "string" }, status: { type: "string", description: "The Stage." }, date_start: { type: "string" }, date_end: { type: "string" },
        color: { type: "string" }, icon: { type: "string" }, client: { type: "string" }, agency: { type: "string" },
        logline: { type: "string" }, website: { type: "string" }, credits: { type: "object", description: "{role: [{name}]}." },
        volume: { type: "string", description: "A media drive's name: its template folders are made there (create-only)." },
        setup: { type: "object", description: "{drive, notion, portal, media}: true or false each." },
        modes: { type: "array", items: { type: "string" }, description: "Studio modes: shot_list, locations, references, schedule, diagram." }, confirm: CONFIRM,
      },
      required: [],
    },
  },
  {
    name: "create_portal",
    description: "Create Portal for " + OPEN + " when it has none: its portal at your-domain.example, its pages read in from Notion. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { confirm: CONFIRM }, required: [] },
  },
  {
    name: "replace_link",
    description: "Replace Link… on " + OPEN + "'s portal: a new share link in place of the old one. **Every link he has already sent stops working**; only the short share address, when there is one, moves to the new link by itself; people on the list still get in by signing in. Say that to him plainly before he answers. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { confirm: CONFIRM }, required: [] },
  },
  {
    name: "portal_up",
    description: "Take Down Portal… (`up` false: everyone but him sees \"This page is down\"; pages and sharing are kept) or Put Up Portal (`up` true) on " + OPEN + ". " + TWO_STEPS,
    inputSchema: { type: "object", properties: { up: { type: "boolean" }, confirm: CONFIRM }, required: ["up"] },
  },
  {
    name: "portal_shared",
    description: "The portal's Shared / Not Shared switch on " + OPEN + " (the Systems card's Portal switch). Not Shared: only he can open it, sent links stop opening until it is Shared again, nothing is deleted. Shared: people on its list and anyone with its link can open it (a link is made when there is none). " + TWO_STEPS,
    inputSchema: { type: "object", properties: { shared: { type: "boolean" }, confirm: CONFIRM }, required: ["shared"] },
  },
  {
    name: "notion_conflicts",
    description: "The questions waiting between Notion and the project record (Projects Console's Keep Mine / Keep Theirs): a fact changed in both, each with the project, the field, Notion's words and the record's. `all: true` lists every project's; otherwise " + OPEN + "'s. His alone.",
    inputSchema: { type: "object", properties: { all: { type: "boolean" } }, required: [] },
  },
  {
    name: "settle_conflict",
    description: "Settle one Notion-versus-record question (`id` from notion_conflicts): `keep` notion (Notion's words go on the record, and the portal and Studio follow) or record (the record's words are written back to Notion). **Which is right is his call**: ask him, never pick. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { id: { type: "string" }, keep: { type: "string", description: "notion or record." }, confirm: CONFIRM }, required: ["id", "keep"] },
  },
  {
    name: "customize_record",
    description: "Customize Record… on " + OPEN + " and The Story's Show per part (logline, synopsis, directors_note, visual_language): which facts and credits it shows, over its Type's standard. With nothing given, answers what it shows and hides now. `fields` ({logline: false, …}) and `credits` ({Producer: true, …}) say shown (true) or hidden (false); `reset` true goes back to the Type's standard. A hidden fact keeps its words; it is only not shown, on the console, the portal or here. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { fields: { type: "object" }, credits: { type: "object" }, reset: { type: "boolean" }, confirm: CONFIRM }, required: [] },
  },
  {
    name: "record_templates",
    description: "His record standards per Type (Settings › New Projects › Record): which facts and credits each Type shows, and the Studio modes it starts with. No project need be open. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_type_template",
    description: "Change one Type's record standard (Settings › New Projects › Record, Reset to Defaults with `template` null): `type` (Narrative, Commercial, Music Video, Personal) and `template` as record_templates shows it. Every project of that Type follows unless it was customized. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { type: { type: "string" }, template: { type: ["object", "null"] }, confirm: CONFIRM }, required: ["type"] },
  },
  {
    name: "drive_template",
    description: "His folder templates (Settings › New Projects › Folders): the Google Drive folder tree each new project gets, the media drive tree, and whether `.filing-rules.md` on the Drive still says the same (`filing`). No project need be open. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_drive_template",
    description: "Change the Google Drive folder template new projects get (Settings › Folders › Google Drive › Save): `folders` the whole tree as drive_template lists it (paths like \"1-creative/shot-list\"). Existing projects' folders are not touched. The media drive template is changed on his Mac (the drives are the Mac's). Afterwards the filing rules can be brought in line with update_filing_rules. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { folders: { type: "array", items: { type: "string" } }, confirm: CONFIRM }, required: ["folders"] },
  },
  {
    name: "update_filing_rules",
    description: "Settings › Folders › Filing Rules › Update: `.filing-rules.md` on the Drive (the spec every folder rule and GD Filer read) has its template blocks redrawn from the folder templates; every other word is kept byte for byte, and Drive keeps the old version. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { confirm: CONFIRM }, required: [] },
  },
  {
    name: "notion_docs_on_portal",
    description: "The Documents tab's Notion documents on " + OPEN + " (Project Docs rows), each with its `id` and whether it is on the portal. With `doc` and `on`, ticks or unticks its Hub box, as the switch does, and the portal follows: on shows it to everyone who can open the portal. Only a document he named. Drive files are show_on_portal. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { doc: { type: "string", description: "Its id, or its title as listed." }, on: { type: "boolean" }, confirm: CONFIRM }, required: [] },
  },
  {
    name: "activity",
    description: "Projects Console's Activity: the shared log of what was done (newest first), each entry's `id` and whether it can be undone, and " + OPEN + "'s big moves (when one is open). `record: true` gives the open project's Record › History instead: every accepted change to its facts, newest first. `limit` up to 200. His alone.",
    inputSchema: { type: "object", properties: { limit: { type: "integer" }, record: { type: "boolean" } }, required: [] },
  },
  {
    name: "undo_activity",
    description: "Undo one entry from Activity (its `id` from activity), as the app's Undo does: a big move put back (30 days; a Delete brought back from its backup), a linked document unlinked, an icon put back. A file moved on a Mac, or an old rename, is undone on the Mac and refused here. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { id: { type: "string" }, confirm: CONFIRM }, required: ["id"] },
  },
  {
    name: "mac_jobs",
    description: "The On a Mac list: the work the server has left for one of his Macs (a showcase's pictures, Studio told where a folder went, a media drive's folders, a drive's index), each with its state and what it waits for. `all: true` for every project's; otherwise " + OPEN + "'s, or every one when none is open. His alone.",
    inputSchema: { type: "object", properties: { all: { type: "boolean" } }, required: [] },
  },
  {
    name: "mac_job",
    description: "Retry or cancel one job on the On a Mac list (`job` its id from mac_jobs). Retry puts a failed job back to waiting at once. Cancel stops it before a Mac starts it (a running one finishes): " + TWO_STEPS,
    inputSchema: { type: "object", properties: { job: { type: "string" }, action: { type: "string", description: "retry or cancel." }, confirm: CONFIRM }, required: ["job", "action"] },
  },
  {
    name: "media_folders",
    description: "Add a Drive… (the Media chip): " + OPEN + "'s template folders made on a media drive (`drive`, its volume name), by a \"Make media folders\" job for the Mac it is plugged into. **Create-only**: folders are made, nothing on any drive is ever moved, renamed or deleted. His alone.",
    inputSchema: { type: "object", properties: { drive: { type: "string" } }, required: ["drive"] },
  },
  {
    name: "index_drive",
    description: "Index Now on a media drive (`drive`, its volume name): a Mac it is plugged into reads its folders and the server brings Notion's Drive Contents up to date. Reads the drive only; nothing there is written. His alone.",
    inputSchema: { type: "object", properties: { drive: { type: "string" } }, required: ["drive"] },
  },
  {
    name: "project_health",
    description: OPEN[0].toUpperCase() + OPEN.slice(1) + "'s folder health, as the console's: what its Google Drive folder is missing against the filing rules (`gaps`) and its Drive and showcase folder trees. The media drives' half is read on his Mac. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "repair_project",
    description: "Fill in " + OPEN + "'s missing Drive folders, as the console's Repair does: `what` subfolders (the five sections and the template's folders where a section is empty) or setup (every gap at once, the showcase when it is due). Only ever creates folders; nothing is moved or deleted. His alone.",
    inputSchema: { type: "object", properties: { what: { type: "string", description: "subfolders or setup." } }, required: ["what"] },
  },
  {
    name: "studio_backup",
    description: OPEN[0].toUpperCase() + OPEN.slice(1) + "'s Studio side backed up now (`now: true`, the Studio ··· › Back Up: a dated copy in the backups and his Drive), or its backups listed. Restore unpacks a copy onto a Mac's Desktop and is done there. His alone.",
    inputSchema: { type: "object", properties: { now: { type: "boolean" } }, required: [] },
  },
  {
    name: "link_edits",
    description: "The Diagrams page's Link Edits: what people on the share link changed on " + OPEN + "'s plans while Editable by Link is on (it is on unless he switched it off), newest first — who, when, which plan, what — each with its `key` and whether it was undone. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "undo_link_edit",
    description: "Take back one link visitor's change (`key` from link_edits), as the Undo in his Link Edits list does: the server's own edits that undo it, worked out when it was made, applied to the plan. " + TWO_STEPS,
    inputSchema: { type: "object", properties: { key: { type: "string" }, confirm: CONFIRM }, required: ["key"] },
  },
  {
    name: "next_steps",
    description: "The Next box on " + OPEN + "'s Overview: what is still to do for its shoot, each line with its `key`. `hide` a key takes that line off (the ✕), `show` a key, or `show_all` true, brings lines back (the app does these at once, with Undo). Only his reminder list changes; nothing about the project does. His alone.",
    inputSchema: { type: "object", properties: { hide: { type: "string" }, show: { type: "string" }, show_all: { type: "boolean" } }, required: [] },
  },
  {
    name: "project_crew",
    description: "The People tab of " + OPEN + ": each person from his Crew in Notion with their `id`, roles and which shoots they are on, and the shoots' ids. His alone.",
    inputSchema: { type: "object", properties: {}, required: [] },
  },
  {
    name: "set_crew",
    description: "Change one person on " + OPEN + "'s People tab, as the console does in his Notion Crew: `person` (their id from project_crew), `on_project` true/false, `add_shoots` / `remove_shoots` (shoot ids), `roles` (the whole list). A new person: `new_person` ({name, roles, email, phone, company, shoots}) or `new_company` ({name}); a likely duplicate is answered instead of made, unless `force`. Credits are set_credit. His alone.",
    inputSchema: {
      type: "object",
      properties: {
        person: { type: "string" }, on_project: { type: "boolean" }, add_shoots: { type: "array", items: { type: "string" } },
        remove_shoots: { type: "array", items: { type: "string" } }, roles: { type: "array", items: { type: "string" } },
        new_person: { type: "object" }, new_company: { type: "object" }, force: { type: "boolean" },
      },
      required: [],
    },
  },
  {
    name: "suggestions",
    description: "What belongs in " + OPEN + "'s empty places, as the console suggests (a deck, a doc, a call sheet found in Drive or Notion), and `use` one: `slot` and `target` as listed, the console's Link on a suggestion. His alone.",
    inputSchema: { type: "object", properties: { slot: { type: "string" }, target: { type: "string" } }, required: [] },
  },
  {
    name: "agents",
    description: "His agents in Projects Console (they run on his Mac): `action` roster (each agent, on or off, its last run), inbox (the needs-you cards), detail (`agent`), or run_status (`run`). Asked of the Mac through the server's mailbox, as the iPhone asks; when the Mac is asleep the answer waits for it. His alone.",
    inputSchema: { type: "object", properties: { action: { type: "string" }, agent: { type: "string" }, run: { type: "string" } }, required: [] },
  },
  {
    name: "agent_do",
    description: "Do something with one of his agents, on his Mac, as the console's Agents page does: `action` run_now (`agent`), on / off (`agent`), cancel_run (`run`), or a needs-you card's approve (`card`, optional `choice`), discard (`card`) or undo (`card`). Sent to the Mac through the server's mailbox. " + TWO_STEPS,
    inputSchema: {
      type: "object",
      properties: { action: { type: "string" }, agent: { type: "string" }, run: { type: "string" }, card: { type: "string" }, choice: { type: "string" }, confirm: CONFIRM },
      required: ["action"],
    },
  },
  {
    name: "console_result",
    description: "How a console run that was still working went (`ask`, the id a console tool answered). Runs too long for one reply — a big move, a New Project, Add Shoot, Close, Reopen — are finished by the server's own minute, never twice.",
    inputSchema: { type: "object", properties: { ask: { type: "string" } }, required: ["ask"] },
  },
];

export const CONSOLE_TOOL_NAMES = new Set(CONSOLE_TOOLS.map((t) => t.name));
/** The ones that need no open project. */
export const CONSOLE_GLOBAL = new Set(["closed_projects", "reopen_project", "new_project", "record_templates", "set_type_template",
  "drive_template", "set_drive_template", "update_filing_rules", "activity", "undo_activity", "mac_jobs", "mac_job", "index_drive",
  "agents", "agent_do", "console_result", "notion_conflicts", "settle_conflict"]);

// ── reaching the console's code ──────────────────────────────────────────────

/** One console method answered by the server, as the router's door does. */
async function answer(env, method, args) {
  const { answerHere } = await import("./cloud.js");
  const got = await answerHere(env, method, args);
  if (!got) throw new Declined(method);
  if (got.state === "failed") throw new Error(got.error || "It failed, and did not say why.");
  return got.result;
}

const askId = () => {
  const a = new Uint8Array(6);
  crypto.getRandomValues(a);
  return [...a].map((b) => b.toString(16).padStart(2, "0")).join("");
};
const pause = (ms) => new Promise((r) => setTimeout(r, ms));
const waitMs = (env, fallback) => {
  const n = Number(env && env.MCP_ASK_WAIT_MS);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
};

async function waitFor(env, id, ms) {
  const { mailbox } = await import("./studio.js");
  const until = Date.now() + ms;
  for (;;) {
    const item = (await mailbox.asksOf(env)).list.find((x) => x.id === id);
    if (item && ["done", "failed", "declined"].includes(item.state)) return item;
    if (Date.now() >= until) return item || null;
    await pause(Math.min(2500, Math.max(0, until - Date.now())));
  }
}

/**
 * **A run too long for one reply**, the phone's way (later.js): kept in the
 * mailbox as working, by the server, and done by the server's own minute,
 * once — never cut off half-way because a reply was waited on. Waited on here
 * for most of a minute; still working, its `ask` id says where to look.
 */
async function heldRun(env, method, args) {
  const later = await import("./later.js");
  if (!(await later.answeredLater(env, method))) {
    // Not one the server holds right now: answered on the spot, or the Mac's.
    return { state: "done", result: await answer(env, method, args) };
  }
  const { mailbox } = await import("./studio.js");
  const item = later.heldItem({ id: askId(), method, args, by: BY, asked: new Date().toISOString(), state: "pending" });
  const kept = await mailbox.changeAsks(env, (list) => ({ list: [...list, item] }));
  if (kept.refusal) throw new Error("The server's mailbox was busy. Nothing was started; try again.");
  const got = await waitFor(env, item.id, waitMs(env, 50000));
  return got && got.state !== "working" ? got : { state: "working", id: item.id };
}

/** An ask only his Mac answers (the agents), left in the mailbox for it, as the iPhone does. */
async function macAsk(env, method, args, ms) {
  const { mailbox } = await import("./studio.js");
  const item = { id: askId(), method, args, by: BY, asked: new Date().toISOString(), state: "pending" };
  const kept = await mailbox.changeAsks(env, (list) => ({ list: [...list, item] }));
  if (kept.refusal) throw new Error("The server's mailbox was busy. Nothing was asked; try again.");
  const got = await waitFor(env, item.id, waitMs(env, ms));
  return got && ["done", "failed", "declined"].includes(got.state) ? got : { state: "pending", id: item.id };
}

/** What a held run said, in words for the chat. */
function ranSaid(got, what) {
  if (got.state === "working" || got.state === "pending") {
    return { working: true, ask: got.id, said: `${what} is running on the server and finishes within a minute or two. console_result with ask ${got.id} says how it went.` };
  }
  if (got.state === "failed") return { ok: false, why: got.error || "It failed, and did not say why." };
  if (got.state === "declined") return { ok: false, why: "The server did not take it." };
  return got.result;
}

// ── the project ──────────────────────────────────────────────────────────────

/** The open project's ID, name and record — the names the console's asks take. */
async function projectAt(env, found, refuse) {
  const { resolveProject } = await import("./projectid.js");
  const got = await resolveProject(env, found.id || found.project);
  if (!got.key || !got.record) throw refuse(`${found.title || "This project"} has no project record, so Projects Console has nothing to do with it.`);
  const r = got.record;
  const title = r.facts && isObject(r.facts.title) ? r.facts.title.value : "";
  return { id: got.key, page: bare(r.page || got.key), name: String(r.name || title || found.title || ""), record: r };
}

const factOf = (record, k) => {
  const f = record && isObject(record.facts) ? record.facts[k] : null;
  return isObject(f) ? f.value : undefined;
};

// ── the gate ─────────────────────────────────────────────────────────────────

/** The look of a big move, as the plan sheet draws it. */
function shownMove(look) {
  const words = (xs) => (xs || []).map((l) => (typeof l === "string" ? l : `${l.text}${l.who && l.who !== "Server" ? ` (${l.who})` : ""}`));
  const out = {
    title: look.title || "", sub: look.sub || "", heading: look.heading || "",
    lines: words(look.lines), stays: words(look.stays), flags: look.flags || [], notes: look.notes || [],
    warn: look.warn || "", problems: look.problems || [], button: look.button || "", footer: look.footer || "",
  };
  if (Array.isArray(look.files)) out.files = look.files.map((f) => `${f.state === "new" ? "Added" : f.state === "kept" ? "Kept" : f.state}: ${f.path}${f.kind === "archive" ? ` → ${f.to || "select-stills/z-archive/"}` : ""}`);
  if (look.counts) out.counts = look.counts;
  for (const k of Object.keys(out)) if (out[k] === "" || (Array.isArray(out[k]) && !out[k].length)) delete out[k];
  return out;
}

const KIND = { wrap: "wrap", archive: "archive", move_drive: "movedrive", movedrive: "movedrive", move: "movedrive", rename: "rename",
  turn_off: "turnoff", turnoff: "turnoff", delete: "delete", showcase: "showcase", prepare_showcase: "showcase", edit_showcase: "showcase" };

function moveOpts(kind, a) {
  if (kind === "rename") return { new_name: str(a.new_name, 200), new_slug: str(a.new_slug, 120) };
  if (kind === "movedrive") return { dest: str(a.dest, 20), ...(a.folder ? { folder: str(a.folder, 120) } : {}) };
  if (kind === "turnoff") return { system: str(a.system, 20) };
  return {};
}

async function bigMove(env, who, found, a, refuse, { tool = "big_move", kind, popup = null } = {}) {
  const p = await projectAt(env, found, refuse);
  const opts = moveOpts(kind, a);
  const asked = { id: p.id, name: p.name };
  let typed = "";
  const look = async () => {
    let got;
    try { got = await answer(env, "bigmove_look", [asked, kind, { ...opts, by: BY }]); } catch (e) {
      if (e instanceof Declined) throw refuse(`The server doesn't do ${kind} on its own yet; it is done in Projects Console on his Mac.`);
      throw e;
    }
    if (!got || got.ok === false) throw refuse(`Nothing was done: ${(got && got.why) || "the server could not look at it."}`);
    typed = got.arm === "typed" ? String(got.confirm || p.name) : "";
    const shown = shownMove(got);
    if (popup) shown.ask = popup;
    return { shown, can_run: Boolean(got.can_run) };
  };
  // The typed name is known only once looked at.
  const first = await look();
  return await gate(env, who, a, refuse, {
    tool, project: p.id, args: { kind, ...opts }, typed,
    look: async () => first,
    go: async () => {
      const got = await heldRun(env, "bigmove_run", [asked, kind, { ...opts, by: BY, ...(typed ? { confirm: typed } : {}) }]);
      const out = ranSaid(got, popup ? popup.title : first.shown.title);
      if (out && out.ok === false) throw refuse(out.why);
      return out;
    },
  });
}

// ── each tool ────────────────────────────────────────────────────────────────

// "Released" is the record's word for Complete (stageword.js, 2026-10-20): either is taken, Complete is said.
const STAGES = ["Development", "Active", "Released", "Post", "Archived"];

async function setStage(env, who, found, a, refuse) {
  const want = STAGES.find((s) => s.toLowerCase() === canonStage(a.stage).toLowerCase());
  if (!want) throw refuse(`A stage is ${STAGES.map(shownStage).join(", ")}. Closed is close_project.`);
  const p = await projectAt(env, found, refuse);
  const year = new Date().getFullYear();
  if (want === "Post") {
    return bigMove(env, who, found, a, refuse, { tool: "set_stage", kind: "wrap",
      popup: { title: `Move ${p.name} to Post?`, lines: ["Marks the shoot Wrapped in Notion", "Shoot Dates move to the next shoot, if there is one"], button: "Move to Post" } });
  }
  if (want === "Archived") {
    return bigMove(env, who, found, a, refuse, { tool: "set_stage", kind: "archive",
      popup: { title: `Archive ${p.name}?`, lines: [`Moves the Drive folder into z-archived/${year}`, "Moves the showcase into zz-archived"], button: "Archive" } });
  }
  const run = async () => {
    let got;
    try { got = await answer(env, "set_stage", [p.name, want]); } catch (e) {
      if (e instanceof Declined) throw refuse("The server can't set the stage right now; set it in Projects Console.");
      throw e;
    }
    if (!got || got.ok === false) throw refuse(`Not changed: ${(got && got.why) || "no reason given"}.`);
    return `${p.name} is ${shownStage(want)}.`;
  };
  // Moving an Archived project back asks first, as the console does (2026-10-20, confirms-report.md):
  // the stage changes, its folders stay in the archive.
  if ((want === "Development" || want === "Active") && canonStage(factOf(p.record, "status")) === "Archived") {
    return await gate(env, who, a, refuse, {
      tool: "set_stage", project: p.id, args: { stage: want },
      look: async () => ({ shown: { title: `Move ${p.name} Back to ${want}?`, lines: ["Its Drive folder and showcase stay in the archive"], button: `Move to ${want}` }, can_run: true }),
      go: run,
    });
  }
  if (want !== "Released") return await run();
  return await gate(env, who, a, refuse, {
    tool: "set_stage", project: p.id, args: { stage: want },
    look: async () => {
      // the release date is optional (2026-10-20): Complete is set with or without one
      const date = factOf(p.record, "released_date");
      const problems = [];
      if (canonStage(factOf(p.record, "status")) === "Released") problems.push(`${p.name} is already Complete.`);
      return { shown: { title: `Mark ${p.name} Complete?`, lines: ["Shows the selects on the portal home"], button: "Mark Complete", ...(date ? { released_date: date } : {}), ...(problems.length ? { problems } : {}) }, can_run: !problems.length };
    },
    go: run,
  });
}

async function closeProject(env, who, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  const reason = String(a.reason || "Not Produced");
  return await gate(env, who, a, refuse, {
    tool: "close_project", project: p.id, args: { reason },
    look: async () => {
      const got = await answer(env, "close_look", [p.id]).catch((e) => { if (e instanceof Declined) throw refuse("The server can't close projects right now."); throw e; });
      if (!got || got.ok === false) throw refuse(`Nothing was done: ${(got && got.why) || "no reason given"}.`);
      if (!(got.reasons || []).includes(reason)) throw refuse(`A reason is ${(got.reasons || []).join(", ")}.`);
      return {
        shown: {
          title: `Close ${got.name || p.name}?`,
          lines: [`Saved to its Drive folder${got.folder ? ` (${got.folder}/${got.file})` : ""}. Reopen from File › Reopen Project.`,
            "It leaves the console and the portal; every link already sent says \"This project is closed.\" at the same address",
            "Nothing is deleted anywhere"],
          reason, button: "Close Project", ...(got.problems && got.problems.length ? { problems: got.problems } : {}),
        },
        can_run: Boolean(got.can_run),
      };
    },
    go: async () => {
      const out = ranSaid(await heldRun(env, "close_project", [p.id, { reason, by: BY }]), `Closing ${p.name}`);
      if (out && out.ok === false) throw refuse(`Not closed: ${out.why}`);
      return out;
    },
  });
}

async function reopenProject(env, who, a, refuse) {
  const id = bare(a.project);
  if (!ID32.test(id)) throw refuse("Say which project, by its ID from closed_projects.");
  return await gate(env, who, a, refuse, {
    tool: "reopen_project", project: id, args: {},
    look: async () => {
      const list = await answer(env, "closed_projects", []);
      const hit = ((list && list.closed) || []).find((x) => x.id === id);
      if (!hit) throw refuse("That project isn't closed. closed_projects lists the ones that are.");
      return { shown: { title: `Reopen ${hit.name}?`, lines: ["Back in the console and on the portal", "Its links open again", "Its stage goes back to what it was"], closed: hit.at, reason: hit.reason, button: "Reopen" }, can_run: true };
    },
    go: async () => {
      const out = ranSaid(await heldRun(env, "reopen_project", [{ id, by: BY }]), "Reopening it");
      if (out && out.ok === false) throw refuse(`Not reopened: ${out.why}`);
      return out;
    },
  });
}

const FORM_KEYS = ["name", "drive_name", "job", "type", "length", "status", "date_start", "date_end", "color", "icon", "client",
  "agency", "logline", "website", "credits", "volume", "setup", "modes"];

async function newProject(env, who, a, refuse) {
  const form = {};
  for (const k of FORM_KEYS) if (a[k] !== undefined && a[k] !== null) form[k] = a[k];
  if (!String(form.name || "").trim()) {
    let o;
    try { o = await answer(env, "new_project_options", []); } catch (e) {
      if (e instanceof Declined) throw refuse("The server doesn't make new projects right now; New Project is in Projects Console on his Mac.");
      throw e;
    }
    const keep = {};
    for (const k of Object.keys(o || {})) if (!/crew|people|director/i.test(k)) keep[k] = o[k];
    return JSON.stringify({ choices: keep, said: "Give a name (and the rest) to see the plan." }, null, 1);
  }
  return await gate(env, who, a, refuse, {
    tool: "new_project", project: "", args: form,
    look: async () => {
      const { look } = await import("./newprojectdoor.js");
      const got = await look(env, { form });
      const shown = { title: `New ${form.job ? "Job" : "Project"}: ${form.name}` };
      if (got.said) shown.lines = String(got.said).split("\n").filter(Boolean);
      if (got.drive) shown.drive = got.drive;
      if (got.owed) shown.on_a_mac = "Media drive folders: a \"Make media folders\" job for the Mac the drive is plugged into (create-only).";
      if (got.birth && got.birth.record) shown.record = got.birth.record;
      const problems = [];
      if (!got.ok) problems.push(got.why || "The server can't make it right now.");
      if (got.ready === false && got.why_not) problems.push(got.why_not);
      if (problems.length) shown.problems = problems;
      shown.button = "Create";
      return { shown, can_run: Boolean(got.ok) };
    },
    go: async () => {
      const out = ranSaid(await heldRun(env, "create_project", [form]), `Making ${form.name}`);
      if (out && out.ok === false) throw refuse(`Not made: ${out.why}`);
      return out;
    },
  });
}

async function portalRow(env, p, refuse) {
  try { return await answer(env, "portal_people", [p.name]); } catch (e) {
    if (e instanceof Declined) throw refuse("The server can't reach the portal's settings right now.");
    throw e;
  }
}

async function createPortal(env, who, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  return await gate(env, who, a, refuse, {
    tool: "create_portal", project: p.id, args: {},
    look: async () => {
      const problems = [];
      if (p.record.portal || (p.record.film && p.record.film.relay)) problems.push(`${p.name} already has its portal.`);
      return { shown: { title: `Create Portal · ${p.name}`, lines: [`A portal for ${p.name} at your-domain.example`, "Its pages read in from Notion"], button: "Create Portal", ...(problems.length ? { problems } : {}) }, can_run: !problems.length };
    },
    go: async () => {
      const got = await answer(env, "create_portal", [p.name]);
      if (!got || got.ok === false) throw refuse(`Not made: ${(got && got.why) || "no reason given"}.`);
      return got;
    },
  });
}

async function replaceLink(env, who, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  const { shortOf } = await import("./films.js");
  return await gate(env, who, a, refuse, {
    tool: "replace_link", project: p.id, args: {},
    look: async () => {
      const people = await portalRow(env, p, refuse);
      if (!people || people.ok === false) throw refuse(`Nothing was done: ${(people && people.why) || "the portal didn't answer"}.`);
      const link = (people.links || []).find((l) => l && l.hash) || people.link || null;
      let short = "";
      try { short = (await shortOf(env, p.id)) || (found.project ? await shortOf(env, found.project) : "") || ""; } catch { short = ""; }
      return {
        shown: {
          title: "Replace the Link?",
          lines: ["Links you've already sent will stop working.",
            short ? `The short share address ${short} keeps working: it moves to the new link by itself.` : "There is no short share address yet, so nothing you sent keeps working.",
            "People on the list still get in by signing in."],
          button: "Replace the Link",
          was: link ? String(link.hash || "").slice(0, 8) : "none",
        },
        can_run: true, hash: link ? link.hash || null : null,
      };
    },
    go: async () => {
      const people = await portalRow(env, p, refuse);
      const link = (people.links || []).find((l) => l && l.hash) || people.link || null;
      const got = await answer(env, "portal_replace_link", [p.name, link ? link.hash : null]);
      if (!got || got.ok === false) throw refuse(`Not replaced: ${(got && (got.why || got.problem)) || "no reason given"}.`);
      return "A new link replaces the old one. Every link sent before no longer opens; copy the new one from Share… (or `access`).";
    },
  });
}

async function portalUp(env, who, found, a, refuse) {
  if (typeof a.up !== "boolean") throw refuse("Say up: true (Put Up Portal) or false (Take Down Portal).");
  const p = await projectAt(env, found, refuse);
  return await gate(env, who, a, refuse, {
    tool: "portal_up", project: p.id, args: { up: a.up },
    look: async () => ({
      shown: a.up
        ? { title: "Put the Portal Up?", lines: ["Everyone who could open it sees its pages again."], button: "Put Up Portal" }
        : { title: "Take Portal Down?", lines: ["Everyone but you sees “This page is down”. Pages and sharing are kept."], button: "Take Down" },
      can_run: true,
    }),
    go: async () => {
      const got = await answer(env, "portal_down", [p.name, !a.up]);
      if (!got || got.ok === false) throw refuse(`${(got && (got.why || got.problem)) || "Portal didn't respond"}.`);
      return a.up ? "Portal is live." : "Portal is off.";
    },
  });
}

async function portalSharedTool(env, who, found, a, refuse) {
  if (typeof a.shared !== "boolean") throw refuse("Say shared: true or false.");
  const p = await projectAt(env, found, refuse);
  return await gate(env, who, a, refuse, {
    tool: "portal_shared", project: p.id, args: { shared: a.shared },
    look: async () => {
      let st = null;
      try { st = await answer(env, "portal_state", [p.id]); } catch { st = null; }
      const problems = [];
      if (st && st.ok && st.shared === a.shared) problems.push(`The portal is already ${a.shared ? "Shared" : "Not Shared"}.`);
      if (st && st.ok === false) problems.push(st.why || st.error || "The portal didn't answer.");
      return {
        shown: a.shared
          ? { title: `Share ${p.name}'s Portal?`, lines: ["People on its list and anyone with its link can open it", "A link is made if it has none"], button: "Shared", ...(problems.length ? { problems } : {}) }
          : { title: `Stop Sharing ${p.name}'s Portal?`, lines: ["Only you can open it", "Links you sent stop opening until it is Shared again", "Nothing is deleted"], button: "Not Shared", ...(problems.length ? { problems } : {}) },
        can_run: !problems.length,
      };
    },
    go: async () => {
      const got = await answer(env, "portal_shared", [p.id, a.shared]);
      if (!got || got.ok === false) throw refuse(`Not changed: ${(got && (got.why || got.error)) || "no reason given"}.`);
      return a.shared ? `Shared.${got.link ? ` Its link: ${got.link}` : ""}` : "Not Shared. Only he can open it now.";
    },
  });
}

async function conflictsNow(env) {
  const { conflictsList } = await import("./notionsync.js");
  const list = await conflictsList(env);
  const names = new Map();
  for (const c of list) {
    if (!c.page || names.has(c.page)) continue;
    const got = await env.BUCKET.get(`r/${c.page}/record.json`);
    let r = null;
    if (got) { try { r = await got.json(); } catch { r = null; } }
    names.set(c.page, r);
  }
  return list.map((c) => {
    const r = names.get(c.page);
    const [field, said] = Object.entries(c.changes || {})[0] || ["", []];
    const record = r && r.facts && isObject(r.facts[field]) ? r.facts[field].value : undefined;
    return { id: c.id, project: (r && r.name) || c.name || "", page: c.page, field, notion: Array.isArray(said) ? said[0] : said, record };
  });
}

async function settleConflictTool(env, who, a, refuse) {
  const keep = String(a.keep || "").toLowerCase();
  if (keep !== "notion" && keep !== "record") throw refuse("Say keep: notion or record — his pick.");
  const id = str(a.id, 80);
  return await gate(env, who, a, refuse, {
    tool: "settle_conflict", project: "", args: { id, keep },
    look: async () => {
      const hit = (await conflictsNow(env)).find((c) => c.id === id);
      if (!hit) throw refuse("That question was already settled, or isn't one. notion_conflicts lists them.");
      return {
        shown: {
          title: `${hit.project || "A project"} · ${hit.field}`,
          lines: [`Notion says: ${JSON.stringify(hit.notion)}`, `The record says: ${JSON.stringify(hit.record === undefined ? "" : hit.record)}`,
            keep === "notion" ? "Keeps Notion's: the record, the portal and Studio follow" : "Keeps the record's: Notion is written back"],
          button: keep === "notion" ? "Keep Notion's" : "Keep the Record's",
        },
        can_run: true,
      };
    },
    go: async () => {
      const got = await answer(env, "settle_facts", [id, keep === "notion" ? "mine" : "theirs"]);
      if (got && got.conflicts) return "It moved again while he decided; notion_conflicts shows the newest.";
      if (!got || got.ok === false) throw refuse(`Not settled: ${(got && got.why) || "no reason given"}.`);
      return "Settled.";
    },
  });
}

async function customizeRecord(env, who, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  const L = await import("./cloudlayout.js");
  const { resolveLayout } = await import("./notionlink.js");
  const saved = await L.savedTemplates(env);
  const facts = (p.record && p.record.facts) || {};
  const typeOf = () => (typeof factOf(p.record, "type") === "string" ? factOf(p.record, "type") : "");
  const shownOf = (f) => { const r = resolveLayout(f, typeOf(), saved); return { type: r.type, fields: r.fields, credits: r.credits }; };
  const now = shownOf(facts);
  const asked = isObject(a.fields) || isObject(a.credits) || a.reset === true;
  if (!asked) return JSON.stringify({ ...now, said: "true is shown, false is hidden." }, null, 1);
  const want = { ...(isObject(a.fields) ? { fields: a.fields } : {}), ...(isObject(a.credits) ? { credits: a.credits } : {}) };
  return await gate(env, who, a, refuse, {
    tool: "customize_record", project: p.id, args: { want, reset: a.reset === true },
    look: async () => {
      const plan = L.layoutPlan(facts, typeOf(), saved, want, a.reset === true);
      const after = shownOf({ ...facts, layout: { value: plan.value } });
      const diff = (x, y) => {
        const out = { hides: [], shows: [] };
        for (const kind of ["fields", "credits"]) {
          const before = isObject(x && x[kind]) ? x[kind] : {};
          const next = isObject(y && y[kind]) ? y[kind] : {};
          for (const k of new Set([...Object.keys(before), ...Object.keys(next)])) {
            if (Boolean(before[k]) && !next[k]) out.hides.push(k);
            if (!before[k] && Boolean(next[k])) out.shows.push(k);
          }
        }
        return out;
      };
      const d = diff(now, after);
      const lines = [];
      if (d.hides.length) lines.push(`Hides: ${d.hides.join(", ")} (their words are kept)`);
      if (d.shows.length) lines.push(`Shows: ${d.shows.join(", ")}`);
      const problems = Object.keys(plan.changes).length ? [] : ["Nothing to change."];
      return { shown: { title: `Customize Record · ${p.name}`, lines, button: "Done", ...(problems.length ? { problems } : {}) }, can_run: !problems.length };
    },
    go: async () => {
      const got = await answer(env, "set_project_layout", [p.name, want, a.reset === true]);
      if (!got || got.ok === false) throw refuse(`Not changed: ${(got && got.why) || "no reason given"}.`);
      return JSON.stringify({ ok: true, layout: got.layout }, null, 1);
    },
  });
}

async function setTypeTemplate(env, who, a, refuse) {
  const type = str(a.type, 60).trim();
  if (!type) throw refuse("Say which Type.");
  const template = a.template === undefined ? null : a.template;
  return await gate(env, who, a, refuse, {
    tool: "set_type_template", project: "", args: { type, template },
    look: async () => {
      const now = await answer(env, "record_templates", []);
      return {
        shown: { title: `${type}: Record Standard`, lines: [template === null ? "Back to the defaults" : `Becomes: ${JSON.stringify(template)}`, `Was: ${JSON.stringify(((now && (now.templates || now.saved)) || {})[type] || null)}`, `Every ${type} project follows, unless it was customized`], button: "Save" },
        can_run: true,
      };
    },
    go: async () => {
      const got = await answer(env, "set_record_template", [type, template]);
      if (!got || got.ok === false) throw refuse(`Not saved: ${(got && got.why) || "no reason given"}.`);
      return JSON.stringify({ ok: true, projects: got.projects }, null, 1);
    },
  });
}

async function setDriveTemplate(env, who, a, refuse) {
  if (!Array.isArray(a.folders) || !a.folders.length) throw refuse("Give `folders`: the whole tree, as drive_template lists it.");
  const folders = a.folders.map((x) => str(x, 200));
  return await gate(env, who, a, refuse, {
    tool: "set_drive_template", project: "", args: { folders },
    look: async () => {
      const now = await answer(env, "templates_read", []);
      if (!now || now.ok === false) throw refuse("The server can't read the folder template right now.");
      const before = new Set(now.drive || []);
      const after = new Set(folders);
      const added = folders.filter((x) => !before.has(x));
      const removed = [...before].filter((x) => !after.has(x));
      const lines = [];
      if (added.length) lines.push(`Adds: ${added.join(", ")}`);
      if (removed.length) lines.push(`Takes out of the template: ${removed.join(", ")} (no existing folder is touched)`);
      lines.push("New projects get this tree; existing projects keep their folders");
      return { shown: { title: "Google Drive Folder Template", lines, button: "Save", ...(added.length || removed.length ? {} : { problems: ["Nothing to change."] }) }, can_run: Boolean(added.length || removed.length), base: now.drive };
    },
    go: async () => {
      const now = await answer(env, "templates_read", []);
      const got = await answer(env, "save_drive_template", [folders, now.drive]);
      if (!got || got.ok === false) throw refuse(`Not saved: ${(got && got.why) || "no reason given"}.`);
      return JSON.stringify({ ok: true, drive: got.drive, filing: got.filing }, null, 1);
    },
  });
}

async function updateFiling(env, who, a, refuse) {
  return await gate(env, who, a, refuse, {
    tool: "update_filing_rules", project: "", args: {},
    look: async () => {
      let now;
      try { now = await answer(env, "templates_read", []); } catch (e) {
        if (e instanceof Declined) throw refuse("The server can't read the filing rules on the Drive right now; Update them in Projects Console.");
        throw e;
      }
      if (!now || now.ok === false) throw refuse("The server can't read the filing rules right now.");
      const f = now.filing || {};
      const stale = f.stale || f.differs || f.out_of_date || (f.state && f.state !== "current");
      return {
        shown: { title: "Update the Filing Rules?", lines: ["The template blocks in .filing-rules.md are redrawn from the folder templates", "Every other word stays as it is; Drive keeps the old version"], filing: f, button: "Update", ...(stale === false || f.current === true ? { problems: ["The filing rules already say the same."] } : {}) },
        can_run: !(stale === false || f.current === true),
      };
    },
    go: async () => {
      const got = await answer(env, "update_filing_rules", []);
      if (!got || got.ok === false) throw refuse(`Not updated: ${(got && got.why) || "no reason given"}.`);
      return JSON.stringify(got, null, 1);
    },
  });
}

async function notionDocs(env, who, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  const docsNow = async () => {
    const page = await answer(env, "project_page", [p.name]);
    if (!page || page.ok === false) throw refuse(`Notion didn't answer: ${(page && page.why) || "no reason given"}. The switch needs Notion; try again once it is reconnected.`);
    return (page.documents || []).filter((d) => d.kind === "doc").map((d) => ({ id: d.id, title: d.title, on_portal: d.on_portal, shoots: d.shoots }));
  };
  if (a.doc === undefined) return JSON.stringify(await docsNow(), null, 1);
  if (typeof a.on !== "boolean") throw refuse("Say on: true or false.");
  const want = String(a.doc);
  return await gate(env, who, a, refuse, {
    tool: "notion_docs_on_portal", project: p.id, args: { doc: want, on: a.on },
    look: async () => {
      const list = await docsNow();
      const hit = list.find((d) => d.id === bare(want)) || list.find((d) => d.title.toLowerCase() === want.toLowerCase());
      if (!hit) throw refuse(`No Notion document called ${want}. Call notion_docs_on_portal with no doc to list them.`);
      const problems = hit.on_portal === a.on ? [`${hit.title} is already ${a.on ? "on" : "off"} the portal.`] : [];
      return { shown: { title: `${hit.title} ${a.on ? "on" : "off"} the portal`, lines: [a.on ? `Shows ${hit.title} on ${p.name}'s portal, to everyone who can open it` : `Takes ${hit.title} off ${p.name}'s portal (it stays in Notion)`], doc: hit.id, button: a.on ? "Show on Portal" : "Take Off", ...(problems.length ? { problems } : {}) }, can_run: !problems.length };
    },
    go: async (shown) => {
      const got = await answer(env, "set_document_on_portal", [p.name, shown.doc, a.on]);
      if (!got || got.ok === false) throw refuse(`Not changed: ${(got && got.why) || "no reason given"}.`);
      return `${shown.title}.${got.portal === false ? ` The portal hasn't caught up yet: ${got.why || "it refreshes on its next look"}.` : ""}`;
    },
  });
}

async function activity(env, found, a) {
  if (a.record === true && found) {
    const { resolveProject } = await import("./projectid.js");
    const got = await resolveProject(env, found.id || found.project);
    const name = String((got.record && got.record.name) || found.title || "");
    const h = await answer(env, "project_history", [name]);
    const limit = Math.max(1, Math.min(200, Number(a.limit) || 60));
    return JSON.stringify({ ...(h || {}), history: ((h && h.history) || []).slice(0, limit) }, null, 1);
  }
  const { listActivity } = await import("./step6history.js");
  const limit = Math.max(1, Math.min(200, Number(a.limit) || 60));
  const entries = (await listActivity(env, limit)).map((e) => ({ id: e.id, when: e.ts || "", kind: e.kind, said: e.desc,
    undo: e.undo ? (e.undo.type === "bigmove" || e.undo.type === "link" || e.undo.type === "icon" ? "here" : "on the Mac") : "no" }));
  const out = { activity: entries };
  if (found && found.id) {
    const { movesFor } = await import("./bigmoves.js");
    out.moves = (await movesFor(env, found.id)).map((m) => ({ move: m.id, kind: m.kind, at: m.at, said: m.said, undone: m.undone }));
  }
  return JSON.stringify(out, null, 1);
}

async function undoActivity(env, who, a, refuse) {
  const id = str(a.id, 60);
  const { listActivity } = await import("./step6history.js");
  const entry = (await listActivity(env, 500)).find((e) => e.id === id);
  if (!entry) throw refuse("No Activity entry by that id. `activity` lists them.");
  const u = isObject(entry.undo) ? entry.undo : null;
  if (!u) throw refuse("That one can't be undone.");
  if (u.type !== "bigmove" && u.type !== "link" && u.type !== "icon") throw refuse("That one is undone in Projects Console on his Mac (it was a file on the Mac's Drive, or an older rename).");
  return await gate(env, who, a, refuse, {
    tool: "undo_activity", project: "", args: { id },
    look: async () => {
      const shown = { title: `Undo: ${entry.desc}`, button: "Undo" };
      if (u.type === "bigmove") {
        const { moveOf, UNDO_DAYS } = await import("./bigmoves.js");
        const mv = await moveOf(env, u.move_id);
        const problems = [];
        if (!mv) problems.push("That move isn't kept any more.");
        else if (mv.undone) problems.push("Already undone.");
        else if (Date.now() - Date.parse(mv.at) > UNDO_DAYS * 86400000) problems.push(`Too late to undo. Undo lasts ${UNDO_DAYS} days.`);
        if (mv) shown.lines = [`Puts back what ${mv.kind} did to ${mv.project.name} on ${String(mv.at).slice(0, 10)}`, ...((mv.lines || []).map((l) => `was: ${l.text}`))];
        if (mv && mv.kind === "delete") shown.lines.push("Brings back the Notion row, the Drive folder, the record, Studio and the portal from the backup");
        if (problems.length) shown.problems = problems;
        return { shown, can_run: !problems.length };
      }
      shown.lines = [u.type === "link" ? "Takes the project off that document's Projects in Notion" : "Puts the old icon back in Notion"];
      return { shown, can_run: true };
    },
    go: async () => {
      if (u.type === "bigmove") {
        const out = ranSaid(await heldRun(env, "bigmove_undo", [u.move_id, { by: BY }]), "The undo");
        if (out && out.ok === false) throw refuse(`Not undone: ${out.why}`);
        return out;
      }
      const got = await answer(env, "activity_undo", [entry]);
      return typeof got === "string" ? got : JSON.stringify(got);
    },
  });
}

async function macJobs(env, found, a) {
  const all = a.all === true || !found;
  const got = await answer(env, "mac_jobs", [all ? { all: true } : { project_id: found.id || "" }]);
  return JSON.stringify(got, null, 1);
}

async function macJob(env, who, a, refuse) {
  const action = String(a.action || "").toLowerCase();
  const job = str(a.job, 12);
  if (action === "retry") {
    const got = await answer(env, "mac_job_retry", [job, BY]);
    return JSON.stringify(got, null, 1);
  }
  if (action !== "cancel") throw refuse("Say action: retry or cancel.");
  return await gate(env, who, a, refuse, {
    tool: "mac_job", project: "", args: { job, action },
    look: async () => {
      const list = await answer(env, "mac_jobs", [{ all: true }]);
      const hit = ((list && list.jobs) || []).find((j) => j.id === job);
      if (!hit) throw refuse("No job by that id on the On a Mac list.");
      return { shown: { title: `Cancel ${hit.title || hit.kind}?`, lines: ["A Mac won't start it; one already running finishes", `It is ${hit.state}`], button: "Cancel Job" }, can_run: true };
    },
    go: async () => JSON.stringify(await answer(env, "mac_job_cancel", [job, BY]), null, 1),
  });
}

async function mediaFolders(env, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  const drive = str(a.drive, 80).trim();
  if (!drive || drive.includes("/")) throw refuse("Say the media drive's name, as it shows under Drives.");
  const slug = String(p.record.slug || "").trim();
  if (!slug) throw refuse(`${p.name} has no folder name yet.`);
  const { addJob, macJobsOn } = await import("./macjobs.js");
  if (!(await macJobsOn(env)).on) throw refuse("The On a Mac list is switched off on the server; Add a Drive… in Projects Console.");
  const job = await addJob(env, { kind: "media-folders", project_id: p.id, project_name: p.name, needs: { drive }, args: { slug, name: p.name }, by: BY });
  return `Queued for the Mac ${drive} is plugged into: ${p.name}'s template folders (${slug}) made on ${drive}. Create-only. mac_jobs shows it (${(job && job.id) || ""}).`;
}

async function indexDrive(env, a, refuse) {
  const drive = str(a.drive, 80).trim();
  if (!drive) throw refuse("Say the media drive's name.");
  try { return JSON.stringify(await answer(env, "mac_job_index", [drive, BY]), null, 1); } catch (e) {
    if (e instanceof Declined) throw refuse("The On a Mac list is switched off on the server; Index Now in Projects Console.");
    throw e;
  }
}

async function health(env, found, refuse) {
  const p = await projectAt(env, found, refuse);
  const status = String(factOf(p.record, "status") || "");
  const [gaps, tree] = await Promise.all([
    answer(env, "project_gaps", [p.name, status]).catch((e) => ({ ok: false, why: e instanceof Declined ? "read on the Mac" : String(e.message || e) })),
    answer(env, "project_tree", [p.name]).catch((e) => ({ ok: false, why: e instanceof Declined ? "read on the Mac" : String(e.message || e) })),
  ]);
  return JSON.stringify({ gaps, tree }, null, 1);
}

async function repairProject(env, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  const what = String(a.what || "").toLowerCase();
  if (what !== "subfolders" && what !== "setup") throw refuse("Say what: subfolders or setup.");
  try {
    const got = what === "subfolders" ? await answer(env, "repair_subfolders", [p.name]) : await answer(env, "complete_setup", [p.name, String(factOf(p.record, "status") || "")]);
    return typeof got === "string" ? got : JSON.stringify(got, null, 1);
  } catch (e) {
    if (e instanceof Declined) throw refuse("The server can't make Drive folders right now; Repair in Projects Console.");
    throw e;
  }
}

async function studioBackup(env, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  try {
    if (a.now === true) return JSON.stringify(ranSaid(await heldRun(env, "film_backup", [p.name]), "The backup"), null, 1);
    return JSON.stringify(await answer(env, "film_backups", [p.name]), null, 1);
  } catch (e) {
    if (e instanceof Declined) throw refuse("The server doesn't back Studio up right now; the Mac does (Studio ··· › Back Up).");
    throw e;
  }
}

async function linkBase(env, found) {
  const { keys } = await import("../../relay/layout.js");
  return `${keys.pages(found.project).replace(/pages\/$/, "")}`;
}

async function linkEdits(env, found) {
  const { listLinkEdits } = await import("./linkedits.js");
  const list = await listLinkEdits(env.BUCKET, await linkBase(env, found));
  return JSON.stringify(list.map(({ undo, device, ...e }) => ({ ...e, changes: Array.isArray(undo) ? undo.length : 0 })), null, 1);
}

async function undoLinkEdit(env, who, found, a, refuse, deps) {
  const { listLinkEdits, markLinkEdit } = await import("./linkedits.js");
  const base = await linkBase(env, found);
  const key = str(a.key, 80);
  const pick = async () => (await listLinkEdits(env.BUCKET, base)).find((e) => e.key === key);
  return await gate(env, who, a, refuse, {
    tool: "undo_link_edit", project: found.project, args: { key },
    look: async () => {
      const e = await pick();
      if (!e) throw refuse("No link edit by that key. link_edits lists them.");
      const problems = e.undone ? ["Already undone."] : (!Array.isArray(e.undo) || !e.undo.length) ? ["Nothing kept to undo it with."] : [];
      return { shown: { title: `Undo ${e.who}'s change?`, lines: [`${String(e.at).slice(0, 16).replace("T", " ")} · plan ${e.scene}`, ...(e.did || [])], button: "Undo", ...(problems.length ? { problems } : {}) }, can_run: !problems.length };
    },
    go: async () => {
      const e = await pick();
      // The engine's undo is bare edits; the plan door takes each as {op} (the page's `edits`).
      await deps.diagramEdit({ scene: e.scene, ops: e.undo.map((op) => (isObject(op) && isObject(op.op) ? op : { op })) });
      await markLinkEdit(env.BUCKET, base, key, true);
      return `Took back ${e.who}'s change.`;
    },
  });
}

async function nextSteps(env, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  if (a.hide) {
    const got = await answer(env, "next_check_hide", [p.name, str(a.hide, 200), true]);
    if (got && got.ok === false) throw refuse(got.why);
    return "Hidden.";
  }
  if (a.show) {
    const got = await answer(env, "next_check_hide", [p.name, str(a.show, 200), false]);
    if (got && got.ok === false) throw refuse(got.why);
    return "Back.";
  }
  if (a.show_all === true) {
    const got = await answer(env, "next_check_show", [p.name, ""]);
    return `${(got && got.shown) || 0} back.`;
  }
  const page = await answer(env, "project_page", [p.name]);
  return JSON.stringify((page && page.next) || {}, null, 1);
}

async function projectCrew(env, found, refuse) {
  const p = await projectAt(env, found, refuse);
  const page = await answer(env, "project_page", [p.name]);
  if (!page || page.ok === false) throw refuse((page && page.why) || "Notion didn't answer.");
  return JSON.stringify({ people: page.people, shoots: (page.shoots || []).map((s) => ({ id: s.id, label: s.label || s.title, start: s.start, end: s.end })) }, null, 1);
}

async function setCrew(env, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  let got;
  if (isObject(a.new_person)) got = await answer(env, "crew_new", [p.name, a.new_person, a.force === true]);
  else if (isObject(a.new_company)) got = await answer(env, "company_new", [p.name, a.new_company, a.force === true]);
  else {
    if (!a.person) throw refuse("Say which person (their id from project_crew), or give new_person / new_company.");
    got = await answer(env, "crew_edit", [p.name, str(a.person, 64), a.on_project === undefined ? null : Boolean(a.on_project),
      Array.isArray(a.add_shoots) ? a.add_shoots : [], Array.isArray(a.remove_shoots) ? a.remove_shoots : [], Array.isArray(a.roles) ? a.roles : null]);
  }
  if (got && got.dupes) return JSON.stringify({ ok: false, said: "Somebody like this is already in Crew. Use them, or say force: true to make a new one.", dupes: got.dupes }, null, 1);
  if (got && got.ok === false) throw refuse(got.why);
  return JSON.stringify(got, null, 1);
}

async function suggestions(env, found, a, refuse) {
  const p = await projectAt(env, found, refuse);
  if (a.slot && a.target) {
    const got = await answer(env, "link_suggestion", [p.name, str(a.slot, 80), str(a.target, 400)]);
    if (got && got.ok === false) throw refuse(got.why);
    return JSON.stringify(got, null, 1);
  }
  return JSON.stringify(await answer(env, "project_suggestions", [p.name]), null, 1);
}

const AGENT_READS = { roster: "roster", inbox: "inbox", detail: "detail", run_status: "run_status" };
const AGENT_DOES = { run_now: "run_now", on: "toggle", off: "toggle", cancel_run: "cancel_run", approve: "approve", discard: "discard", undo: "undo" };

function agentPayload(action, a) {
  if (action === "on" || action === "off") return { agent_id: str(a.agent, 80), enabled: action === "on" };
  if (action === "run_now") return { agent_id: str(a.agent, 80), dry: false };
  if (action === "cancel_run" || action === "run_status") return { run_id: str(a.run, 80) };
  if (action === "detail") return { agent_id: str(a.agent, 80) };
  if (action === "approve") return { action_id: str(a.card, 80), ...(a.choice ? { choice: str(a.choice, 200) } : {}) };
  if (action === "discard" || action === "undo") return { action_id: str(a.card, 80) };
  return {};
}

function agentSaid(got) {
  if (got.state === "pending") return `His Mac hasn't answered yet (it may be asleep). The ask waits for it: console_result with ask ${got.id}.`;
  if (got.state === "failed") return `The Mac said no: ${got.error || "no reason given"}.`;
  if (got.state === "declined") return "The Mac did not take it.";
  return JSON.stringify(got.result, null, 1);
}

async function agentsRead(env, a, refuse) {
  const action = String(a.action || "roster").toLowerCase();
  if (!AGENT_READS[action]) throw refuse("Say action: roster, inbox, detail or run_status.");
  return agentSaid(await macAsk(env, "agents", [AGENT_READS[action], agentPayload(action, a)], 20000));
}

async function agentDo(env, who, a, refuse) {
  const action = String(a.action || "").toLowerCase();
  if (!AGENT_DOES[action]) throw refuse("Say action: run_now, on, off, cancel_run, approve, discard or undo.");
  const payload = agentPayload(action, a);
  return await gate(env, who, a, refuse, {
    tool: "agent_do", project: "", args: { action, payload },
    look: async () => {
      const words = { run_now: `Run ${payload.agent_id} now`, on: `Switch ${payload.agent_id} on`, off: `Switch ${payload.agent_id} off`, cancel_run: `Stop run ${payload.run_id}`,
        approve: `Approve card ${payload.action_id}${payload.choice ? ` (${payload.choice})` : ""}`, discard: `Discard card ${payload.action_id}`, undo: `Undo card ${payload.action_id}` };
      return { shown: { title: words[action], lines: ["Done by his Mac, as the Agents page does it"], button: "OK" }, can_run: Boolean(payload.agent_id || payload.run_id || payload.action_id) };
    },
    go: async () => agentSaid(await macAsk(env, "agents", [AGENT_DOES[action], payload], action === "approve" || action === "undo" ? 45000 : 20000)),
  });
}

async function consoleResult(env, a, refuse) {
  const id = str(a.ask, 12);
  if (!/^[0-9a-f]{12}$/.test(id)) throw refuse("Say the ask's id, as a console tool answered it.");
  const { mailbox } = await import("./studio.js");
  const item = (await mailbox.asksOf(env)).list.find((x) => x.id === id);
  if (!item) throw refuse("No ask by that id — it may have been answered too long ago (answers are kept ten minutes). The tool's own read (activity, record, mac_jobs) says how things stand.");
  if (item.by !== BY) throw refuse("That ask isn't one the connector made.");
  if (item.state === "working") return "Still working on the server.";
  if (item.state === "pending") return "Waiting for his Mac to answer.";
  if (item.state === "failed") return `It failed: ${item.error || "no reason given"}`;
  return JSON.stringify(item.result === undefined ? null : item.result, null, 1);
}

/**
 * The tool. `found` is the open project (null for one that needs none),
 * `admin` whether this is him; `deps.diagramEdit(asked)` the engine's plan
 * door for this person and project.
 */
export async function consoleTool(env, found, name, args, refuse, who, admin, deps = {}) {
  if (!admin) throw refuse("Only he may do that: Projects Console's actions are his alone.");
  const a = isObject(args) ? args : {};
  if (!CONSOLE_GLOBAL.has(name) && !found) throw refuse("No project is open. Ask for `projects`, then `open_project`.");
  try {
    switch (name) {
      case "big_move": {
        const kind = KIND[String(a.kind || "").toLowerCase()];
        if (!kind) throw refuse("Say kind: wrap, archive, move_drive, rename, turn_off, delete or showcase.");
        return await bigMove(env, who, found, a, refuse, { kind });
      }
      case "set_stage": return await setStage(env, who, found, a, refuse);
      case "close_project": return await closeProject(env, who, found, a, refuse);
      case "closed_projects": return JSON.stringify(await answer(env, "closed_projects", []), null, 1);
      case "reopen_project": return await reopenProject(env, who, a, refuse);
      case "new_project": return await newProject(env, who, a, refuse);
      case "create_portal": return await createPortal(env, who, found, a, refuse);
      case "replace_link": return await replaceLink(env, who, found, a, refuse);
      case "portal_up": return await portalUp(env, who, found, a, refuse);
      case "portal_shared": return await portalSharedTool(env, who, found, a, refuse);
      case "notion_conflicts": {
        let list = await conflictsNow(env);
        if (a.all !== true && found && found.id) list = list.filter((c) => c.page === bare(found.id) || c.page === bare(found.project));
        return JSON.stringify(list, null, 1);
      }
      case "settle_conflict": return await settleConflictTool(env, who, a, refuse);
      case "customize_record": return await customizeRecord(env, who, found, a, refuse);
      case "record_templates": return JSON.stringify(await answer(env, "record_templates", []), null, 1);
      case "set_type_template": return await setTypeTemplate(env, who, a, refuse);
      case "drive_template": return JSON.stringify(await answer(env, "templates_read", []), null, 1);
      case "set_drive_template": return await setDriveTemplate(env, who, a, refuse);
      case "update_filing_rules": return await updateFiling(env, who, a, refuse);
      case "notion_docs_on_portal": return await notionDocs(env, who, found, a, refuse);
      case "activity": return await activity(env, found, a);
      case "undo_activity": return await undoActivity(env, who, a, refuse);
      case "mac_jobs": return await macJobs(env, found, a);
      case "mac_job": return await macJob(env, who, a, refuse);
      case "media_folders": return await mediaFolders(env, found, a, refuse);
      case "index_drive": return await indexDrive(env, a, refuse);
      case "project_health": return await health(env, found, refuse);
      case "repair_project": return await repairProject(env, found, a, refuse);
      case "studio_backup": return await studioBackup(env, found, a, refuse);
      case "link_edits": return await linkEdits(env, found);
      case "undo_link_edit": return await undoLinkEdit(env, who, found, a, refuse, deps);
      case "next_steps": return await nextSteps(env, found, a, refuse);
      case "project_crew": return await projectCrew(env, found, refuse);
      case "set_crew": return await setCrew(env, found, a, refuse);
      case "suggestions": return await suggestions(env, found, a, refuse);
      case "agents": return await agentsRead(env, a, refuse);
      case "agent_do": return await agentDo(env, who, a, refuse);
      case "console_result": return await consoleResult(env, a, refuse);
      default: throw refuse(`Unknown tool: ${name}`);
    }
  } catch (e) {
    if (e instanceof Declined) throw refuse(`The server doesn't do that right now (${e.message}); it is done in Projects Console on his Mac.`);
    throw e;
  }
}
