/**
 * **The `mods` tool** (2026-10-17): the open project's mods, the same switch
 * as the console card and Studio (studiomods.js). Off by default; off hides a
 * mod's content and deletes nothing.
 */
import { readMods, setMod, SHELF, MOD_KEYS } from "./studiomods.js";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

export const MODS_TOOL = {
  name: "mods",
  description: "The open project's mods: small add-ons from one shared shelf, off until a project switches one on. Edit Reference (adds to Shot List): a clip, stills or animatic joined to a run of shots, shown as a gold bracket in the shot list with a play button. Read: the shelf and which are on. Give `mod` and `on` to switch one; off hides it and deletes nothing. Ask him before switching one off.",
  inputSchema: {
    type: "object",
    properties: {
      mod: { type: "string", enum: [...MOD_KEYS], description: "edit_reference (or its title, \"Edit Reference\")." },
      on: { type: "boolean" },
    },
    required: [],
  },
};

export function modKey(said) {
  const flat = String(said || "").trim().toLowerCase().replace(/[\s_-]+/g, "");
  const hit = SHELF.find((m) => m.key.replace(/_/g, "") === flat || m.title.toLowerCase().replace(/\s/g, "") === flat);
  return hit ? hit.key : "";
}

const titleOf = (k) => (SHELF.find((m) => m.key === k) || { title: k }).title;

export async function modsTool(env, found, args, refuse, who, deps = {}) {
  const a = isObject(args) ? args : {};
  if (!found.id) throw refuse(`${found.title || "This project"} has no project record yet, so it has no mods.`);
  if (a.mod === undefined && a.on === undefined) {
    const got = await readMods(env, found.id);
    if (!got.ok) throw refuse(got.why || "No project with that ID.");
    return JSON.stringify({ project: found.title, id: got.id, shelf: got.shelf.map((m) => ({ ...m, on: got.mods.includes(m.key) })) }, null, 1);
  }
  if (found.role !== "editor") throw refuse("Only an editor may switch a project's mods.");
  const mod = modKey(a.mod);
  if (!mod) throw refuse(`Say which mod: ${MOD_KEYS.join(", ")}.`);
  if (typeof a.on !== "boolean") throw refuse("Say on: true or on: false.");
  const by = `AI connector${who && who.email ? ` (${who.email})` : ""}`.slice(0, 80);
  const set = deps.setMod || ((id, said) => setMod(env, id, said));
  const got = await set(found.id, { mod, on: a.on, by });
  if (!got || !got.ok) throw refuse((got && got.why) || "The mod could not be switched.");
  const on = got.mods.map(titleOf);
  return `${titleOf(mod)} ${got.unchanged ? "was already" : "is"} ${a.on ? "on" : "off"}.${!a.on && !got.unchanged ? " Nothing is deleted." : ""} On: ${on.length ? on.join(", ") : "none"}.`;
}
