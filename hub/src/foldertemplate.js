/**
 * **The folder template, the server's master copy** (2026-10-14, stage 5
 * step 3). What a new project's Google Drive folder and its media-drive
 * folder are born with: `drive` and `media`, each a flat list of relative
 * paths, a parent always before its children.
 *
 * Until now the master was Project Creator's own file on the Studio Mac
 * (`~/.kc-project-creator/profiles.json`, profile "DP Project"), which the
 * console edited in place. His call (stage 5, answer 19): the console stops
 * writing into Project Creator's file; Project Creator keeps its profiles
 * untouched. So the template lives here; every Mac keeps a saved copy for
 * New Project offline, and the Studio Mac still writes the filing rules
 * (`.filing-rules.md`) GD Filer reads.
 *
 * Kept at `s/folder-template.json` `{drive, media, v, at, by}`, written
 * compare-and-set from the version the screen read (`base`). Until first
 * written it answers the template as it stands today (`PROJECT_TEMPLATE`,
 * the drive folders' own switch's `template` when one was set, and
 * `MEDIA_TEMPLATE`), `v: 0`.
 */

import { PROJECT_TEMPLATE, SHOOT_SECTIONS, SHOOT_TEMPLATE } from "./drivefolders.js";

export const KEY = "s/folder-template.json";

/** The "Hard Drive" destination of the DP Project profile, 2026-10-14. */
export const MEDIA_TEMPLATE = [
  "00_PROJECTS", "00_PROJECTS/01_PREMIERE", "00_PROJECTS/01_PREMIERE/01_PROJECT", "00_PROJECTS/01_PREMIERE/02_SCRATCH",
  "00_PROJECTS/02_AFTER EFFECTS", "00_PROJECTS/03_PROTOOLS", "00_PROJECTS/04_DAVINCI",
  "01_PRODUCTION_MEDIA", "01_PRODUCTION_MEDIA/03_PROXIES", "01_PRODUCTION_MEDIA/01_P_FOOTAGE",
  "01_PRODUCTION_MEDIA/02_P_AUDIO", "01_PRODUCTION_MEDIA/04_TESTS",
  "02_COLOR", "02_COLOR/01_PASSES", "02_COLOR/02_MASTERS", "02_COLOR/03_STILLS", "02_COLOR/04_CONFORM",
  "03_EXPORTS",
];

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const BAD = /[:\u0000-\u001f]/;

/** templates.validate: a tree as kept, or a reason. */
export function checkTree(tree) {
  if (!Array.isArray(tree)) return { why: "The template must be a list of folders." };
  const seen = new Set();
  const out = [];
  for (const raw of tree) {
    if (typeof raw !== "string") return { why: "Each folder must be a name." };
    const path = raw.replace(/^\/+|\/+$/g, "");
    if (!path) return { why: "Name can't be empty." };
    for (const part of path.split("/")) {
      if (!part.trim()) return { why: `Name can't be empty. (${path})` };
      if (part !== part.trim()) return { why: `Name can't start or end with a space. (${path})` };
      if (part.startsWith(".")) return { why: `Name can't start with a dot. (${path})` };
      if (BAD.test(part)) return { why: `Name can't contain “:” or line breaks. (${path})` };
    }
    const fold = path.toLowerCase();
    if (seen.has(fold)) return { why: `${path} is listed twice.` };
    const at = path.lastIndexOf("/");
    if (at > 0 && !seen.has(path.slice(0, at).toLowerCase())) return { why: `${path.slice(0, at)} must come before ${path}.` };
    seen.add(fold);
    out.push(path);
  }
  return { tree: out };
}

/** The template now: the kept one, or today's. */
export async function templateOf(env) {
  let kept = null;
  const got = await env.BUCKET.get(KEY);
  if (got) { try { kept = await got.json(); } catch { kept = null; } }
  let drive = PROJECT_TEMPLATE;
  try {
    const s = await env.BUCKET.get("s/drivefolders.json");
    const v = s ? await s.json() : null;
    if (v && Array.isArray(v.template) && v.template.every((t) => typeof t === "string" && t)) drive = v.template;
  } catch { /* today's */ }
  const k = isObject(kept) ? kept : {};
  return {
    drive: Array.isArray(k.drive) ? k.drive : drive,
    media: Array.isArray(k.media) ? k.media : MEDIA_TEMPLATE,
    shoot: { sections: SHOOT_SECTIONS, folders: SHOOT_TEMPLATE },
    v: Number(k.v) || 0, at: k.at || null, by: k.by || null,
  };
}

/** A change: `drive` and/or `media`, from version `base`. Answers the
 * template as kept, `{problem}`, or `{moved}` when it changed meanwhile. */
export async function changeTemplate(env, said) {
  const s = isObject(said) ? said : {};
  const now = await templateOf(env);
  if (Number(s.base) !== now.v) return { moved: now };
  const next = { drive: now.drive, media: now.media };
  for (const which of ["drive", "media"]) {
    if (s[which] === undefined) continue;
    const got = checkTree(s[which]);
    if (got.why) return { problem: got.why };
    next[which] = got.tree;
  }
  const kept = { ...next, v: now.v + 1, at: new Date().toISOString(), by: String(s.by || "").slice(0, 80) };
  const old = await env.BUCKET.head(KEY);
  const put = await env.BUCKET.put(KEY, JSON.stringify(kept), {
    httpMetadata: { contentType: "application/json" },
    onlyIf: old ? { etagMatches: old.etag } : { etagDoesNotMatch: "*" },
  });
  if (!put) return { moved: await templateOf(env) };
  return { ...kept, shoot: now.shoot };
}
