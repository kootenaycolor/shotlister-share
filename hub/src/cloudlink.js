/**
 * **Link on a suggestion, and Look Again, answered by the server**
 * (2026-10-13, Projects Console without the Mac, group 3).
 *
 * - `link_suggestion(name, slot, target)` — backend.link_suggestion: he
 *   pressed Link on one of the Suggestions. The suggestions are worked out
 *   afresh (suggest.js, which hands the ask to the Mac when it needs the
 *   Mac's disk), and only one still suggested is linked: the Notion row is
 *   read just before and again after, and the write only ever adds
 *   (`planLink` / `linkedAfter`, linked.py's plan_link / linked_after, rule
 *   for rule). A film the Mac offered is the Mac's: linking one writes into
 *   Shotlister's film on its disk. A film the server offered (the Mac asleep,
 *   switch `linkfilm` on) is linked on its relay copy (linkfilm.js, stage 4
 *   step D). The Mac then kicks the Notion link; here its own minute
 *   looks at every project, so the record follows within a minute.
 * - `project_dossier(name, force)` — the phone's Look Again: the Mac looks
 *   at the project (drives, media, the film on its disk) and republishes the
 *   record. With the Mac awake that is still the Mac's; asleep, the server
 *   brings the record up to date from what it can see (recordlive.js) and the
 *   drive and media lights keep their "as of".
 */

import { Handoff, projectRow, bareId } from "./cloud.js";

const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const bare = (v) => String(v || "").replace(/-/g, "");

/** linked._ids — the ids a relation holds, dashes off. */
export function ids(props, name) {
  return (((props || {})[name] || {}).relation || []).map((r) => bare((r || {}).id));
}

const rel = (list) => ({ relation: list.map((id) => ({ id })) });

/** linked.plan_link — [the PATCH properties, a refusal or ""]; only ever adds. */
export function planLink(kind, slot, props, page, target = "") {
  page = bare(page);
  const shoot = String(slot).startsWith("shoot:") ? String(slot).split(":")[1] : "";
  const patch = {};
  if (kind === "sheet") {
    if (!shoot) return [{}, "A spec sheet belongs to a shoot."];
    const have = ids(props, "Shoot");
    if (!have.includes(shoot)) patch.Shoot = rel([...have, shoot]);
    const projects = ids(props, "Projects");
    if (!projects.includes(page)) patch.Projects = rel([...projects, page]);
    return [patch, ""];
  }
  if (kind === "doc") {
    const projects = ids(props, "Projects");
    if (projects.length && !projects.includes(page)) return [{}, "That document is on another project in Notion."];
    if (!projects.includes(page)) patch.Projects = rel([page]);
    if (shoot) {
      const have = ids(props, "Shoot");
      if (!have.includes(shoot)) patch.Shoot = rel([...have, shoot]);
    }
    return [patch, ""];
  }
  if (kind === "drive") {
    const now = String((((props || {})["Drive Folder"] || {}).url) || "").trim();
    if (now) return [{}, now === target ? "" : "Notion already has a Drive folder for this project."];
    if (!/^https:\/\/drive\.google\.com\//.test(target || "")) return [{}, "That isn't a Drive folder's address."];
    return [{ "Drive Folder": { url: target } }, ""];
  }
  return [{}, `Nothing to link for “${kind}”.`];
}

/** linked.linked_after — the write took, and took nothing away. */
export function linkedAfter(kind, slot, before, after, page, target = "") {
  if (kind === "drive") return String((((after || {})["Drive Folder"] || {}).url) || "").trim() === target;
  for (const name of ["Shoot", "Projects"]) {
    const now = new Set(ids(after, name));
    if (!ids(before, name).every((id) => now.has(id))) return false;
  }
  const [patch, why] = planLink(kind, slot, after, page, target);
  return !Object.keys(patch).length && !why;
}

/** backend.link_suggestion. */
export async function linkSuggestion(env, n, [name, slot, target]) {
  const row = await projectRow(n, name);
  if (!row) return { ok: false, why: "This project has no Notion row." };
  const page = bareId(row.id);
  const { projectSuggestions } = await import("./suggest.js");
  const fresh = await projectSuggestions(env, n, [name, true]);       // a Handoff goes to the Mac
  const sug = ((fresh && fresh.suggestions) || []).find((x) => x.slot === slot && x.target === target);
  if (!sug) return { ok: false, why: "That suggestion is gone. Look again." };
  const kind = sug.kind;
  if (kind === "film") {
    // A film the server offered (the Mac asleep, linkfilm.js) is linked on
    // its relay copy; one the Mac offered is the Mac's to link.
    const { linkFilmOn, linkFilmHere } = await import("./linkfilm.js");
    if (!(await linkFilmOn(env)).on || (await macAwake(env))) {
      throw new Handoff("the Mac links a film: it writes into Shotlister's film on its disk");
    }
    return await linkFilmHere(env, n, row, name, sug);
  }
  let changed;
  try {
    const where = kind === "drive" ? page : target;
    const before = ((await n.get(`pages/${where}`)) || {}).properties || {};
    const [patch, why] = planLink(kind, slot, before, page, target);
    if (why) return { ok: false, why };
    if (Object.keys(patch).length) {
      await n.patch(`pages/${where}`, { properties: patch });
      const after = ((await n.get(`pages/${where}`)) || {}).properties || {};
      if (!linkedAfter(kind, slot, before, after, page, target)) return { ok: false, why: "Notion didn't keep the link. Try again." };
    }
    changed = Object.keys(patch).sort();
  } catch (e) {
    if (e instanceof Handoff) throw e;
    return { ok: false, why: String((e && e.message) || e) };
  }
  return { ok: true, changed, title: sug.title };
}

/** The phone's own rule for an awake Mac (drivelists.js): its snapshot is under three minutes old. */
export async function macAwake(env, now = Date.now()) {
  const got = await env.BUCKET.get("s/studio.json");
  if (!got) return false;
  let studio = null;
  try { studio = await got.json(); } catch { return false; }
  const seen = Date.parse(isObject(studio) ? studio.at : "");
  return Number.isFinite(seen) && now - seen < 180 * 1000;
}

/** backend.project_dossier, as the phone uses it: look again now. */
export async function lookAgain(env, n, [name]) {
  if (await macAwake(env)) throw new Handoff("the Mac is awake: it looks at the drives and the film too");
  const row = await projectRow(n, name);
  if (!row) return { ok: false, why: "no Notion row for this project" };
  const { liveAfterEdit } = await import("./recordlive.js");
  await liveAfterEdit(env, bareId(row.id));
  return { ok: true, server: true, said: "The record was brought up to date by the server; drives and media are as the Mac last saw them." };
}
