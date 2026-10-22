/**
 * **His OK before the portal's who-sees-what changes** (2026-10-19, his ask:
 * "make sure the mcp can do all actions in project console and shotlister
 * that i can", with the rule that whatever moves, deletes, hides, publishes
 * or changes who can see something waits for his yes).
 *
 * The console's own big actions are gated in `consoletools.js`. These are the
 * connector's older tools that do the same kind of thing: Share (people, the
 * link, its password, Editable by Link), What Viewers See, view links, Show
 * on Portal, a page archived or taken off, a pin board's sharing, and the
 * two real deletes of pictures and clips. Each keeps its own door; this only
 * puts the two steps in front of it (`consolegate.js`, the same token
 * add_shoot and the console tools use), his alone.
 *
 * Studio's own edits (a shot, a scene, a day deleted or moved) are not gated:
 * Studio does them at once with Undo and saved versions, and directors use
 * the connector for them too.
 */
import { TWO_STEPS, twoSteps } from "./consolegate.js";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const list = (v) => (Array.isArray(v) ? v.map((x) => String(isObject(x) ? x.email || x.name || JSON.stringify(x) : x)) : []);
const tryJson = (t) => { try { return JSON.parse(t); } catch { return null; } };

const CONFIRM = { type: "string", description: "Step 2 only: the token step 1 gave. Only after his yes in the chat." };

/** The tools gated here, always, or (set_board) only for the sharing part. */
const ALWAYS = new Set(["set_access", "set_visibility", "share_view", "set_view", "show_on_portal", "remove_page",
  "archive_page", "delete_media", "delete_unused_media"]);
export const HUB_GATED = new Set([...ALWAYS, "set_board"]);

export function needsGate(name, args) {
  if (name === "set_board") return isObject(args) && (args.share !== undefined || args.link_edit !== undefined);
  return ALWAYS.has(name);
}

/** The tool as listed: its description says the two steps; it takes `confirm`. */
export function gatedListing(tool) {
  if (!HUB_GATED.has(tool.name)) return tool;
  const said = tool.name === "set_board"
    ? " **`share` and `link_edit` take two steps**: called with either and no `confirm`, nothing changes and a preview and token come back; show him, and only after his yes call again with the same arguments and `confirm`."
    : ` ${TWO_STEPS}`;
  const schema = isObject(tool.inputSchema) ? tool.inputSchema : { type: "object", properties: {}, required: [] };
  return { ...tool, description: `${tool.description}${said}`, inputSchema: { ...schema, properties: { ...(schema.properties || {}), confirm: CONFIRM } } };
}

/** What the change does, in words, against how things stand (`read`: a read tool's answer). */
async function lookOf(name, a, read, title) {
  const lines = [];
  const problems = [];
  let now;
  switch (name) {
    case "set_access": {
      now = tryJson(await read("access", {})) || {};
      if (a.link === "anyone") lines.push("Anyone with the link can open the portal (the link is made if there is none)");
      if (a.link === "restricted") lines.push("Only people on the list can open it; links already sent stop opening until it is turned back on");
      for (const p of Array.isArray(a.add) ? a.add : []) lines.push(`Adds ${p && p.email} as ${(p && p.role) || "viewer"}`);
      for (const p of Array.isArray(a.role) ? a.role : []) lines.push(`Makes ${p && p.email} ${p && p.role}`);
      for (const e of list(a.remove)) lines.push(`Takes ${e} off the list: they can no longer open it`);
      if (typeof a.password === "string" && a.password) lines.push("Puts a password on the link");
      if (a.password === null || a.password === "") lines.push("Takes the link's password off");
      if (a.short !== undefined) lines.push(`The short name becomes ${a.short}; the old one keeps working`);
      if (a.diagram_link_edit === true) lines.push("People with the link can draw on the Diagrams page (Editable by Link on)");
      if (a.diagram_link_edit === false) lines.push("People with the link can only look at the Diagrams page (Editable by Link off)");
      now = { general_access: now.general_access, password: now.password, people: Array.isArray(now.people) ? now.people.length : undefined };
      break;
    }
    case "set_visibility": {
      const words = (g) => (isObject(g) ? ["sections", "people", "documents"].flatMap((k) => list(g[k])) : []);
      const hide = words(a.private || a.hide);
      const show = words(a.public || a.show);
      if (hide.length) lines.push(`Private (only editors see it): ${hide.join(", ")}`);
      if (show.length) lines.push(`Shown again to people with the link: ${show.join(", ")}`);
      if (isObject(a.contact)) {
        if (list(a.contact.on).length) lines.push(`Email and phone shown to people with the link: ${list(a.contact.on).join(", ")}`);
        if (list(a.contact.off).length) lines.push(`Email and phone no longer shown: ${list(a.contact.off).join(", ")}`);
      }
      break;
    }
    case "share_view":
      lines.push(`A new view link: only the shots where ${(Array.isArray(a.filters) ? a.filters : []).map((f) => `${f && f.field} is ${f && f.value}`).join(" and ") || "(no filter)"}, on an address of its own`);
      lines.push("Whoever gets it sees those shots and nothing else of the project");
      break;
    case "set_view":
      if (a.name !== undefined) lines.push(`Renames view ${a.view} to ${a.name} (the link keeps working)`);
      if (a.on === false) lines.push(`Switches view ${a.view} off: its link stops opening`);
      if (a.on === true) lines.push(`Switches view ${a.view} back on: its link opens again`);
      if (a.filters !== undefined) lines.push(`View ${a.view} shows only shots matching the new filter`);
      if (a.shooting_order !== undefined) lines.push(`View ${a.view} ${a.shooting_order ? "in shooting order" : "in script order"}`);
      if (a.remove === true) lines.push(`Deletes view ${a.view} for good: its link stops working and can't come back`);
      break;
    case "show_on_portal":
      lines.push(a.on === true
        ? `Shows ${a.file} on the portal's Documents page, to everyone who can open the portal`
        : `Takes ${a.file} off the portal's Documents page (it stops opening at once; the file stays in Drive)`);
      break;
    case "remove_page":
      lines.push(`Takes the page ${a.slug} off the portal`);
      break;
    case "archive_page":
      lines.push(a.archived === false
        ? `Takes ${a.slug || a.document} out of the Archive: back as it was, pinned or not, private or not`
        : `Archives ${a.slug || a.document}: unpinned, private (only editors see it), filed in the Library's Archive. Nothing is deleted`);
      break;
    case "set_board":
      if (a.share !== undefined) lines.push(`Board ${a.board || a.slug || ""} shared with: ${a.share} (me: only him; crew: people on the list; link: anyone with the link)`);
      if (a.link_edit === true) lines.push("People with the link can change the board");
      if (a.link_edit === false) lines.push("People with the link can only look at the board");
      break;
    case "delete_media": {
      lines.push(`Deletes for real: ${a.media}`);
      lines.push("Every use goes and the file goes from every device; only the name stays. Not undoable");
      break;
    }
    case "delete_unused_media": {
      const said = await read("media", { show: "unused" });
      const got = tryJson(said);
      const items = Array.isArray(got) ? got : got && Array.isArray(got.media) ? got.media : null;
      if (items && !items.length) problems.push("Nothing is unused.");
      lines.push(items ? `Deletes for real ${items.length} unused picture${items.length === 1 ? "" : "s"} and clips: ${items.slice(0, 40).map((m) => m.name || m.file || m.id).join(", ")}${items.length > 40 ? ", …" : ""}` : `Deletes for real every picture and clip nothing uses: ${String(said).slice(0, 1500)}`);
      lines.push("Not undoable");
      break;
    }
    default:
      break;
  }
  if (!lines.length) problems.push("Nothing to change.");
  return { shown: { title: `${title}: ${name.replace(/_/g, " ")}`, lines, ...(now ? { now } : {}), ...(problems.length ? { problems } : {}) }, can_run: !problems.length };
}

/**
 * Before a gated tool runs. Answers `{answer}` (a preview, or a refusal
 * thrown) or `{args}` to run with (`confirm` taken out).
 * `deps.read(name, args)` answers a read tool's text; `deps.run(args)` runs it.
 */
export async function hubGate(env, found, who, name, args, refuse, admin, deps) {
  const a = isObject(args) ? args : {};
  if (!needsGate(name, a)) return { args: a };
  if (!admin) throw refuse("Only he may do that.");
  const { confirm, ...rest } = a;
  const out = await twoSteps(env, who, a, refuse, {
    tool: name, project: String(found.id || found.project || ""), args: rest,
    look: () => lookOf(name, rest, deps.read, found.title || "This project"),
    go: async () => deps.run(rest),
  });
  return { answer: out };
}
