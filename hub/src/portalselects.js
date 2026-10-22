/**
 * **A Released project's selects on its portal home** (2026-10-17, his call
 * on the Released → Showcase flow): once the project is Released, the stills
 * he picked show on the home page as a quiet grid, every still whole at its
 * own shape with square corners, with small links to the finished film under
 * them. Nothing else changes on the page, and no address moves.
 *
 * The pictures come through `<base>/select/<drive id>`, behind the page's own
 * door (the same permission as the page), and only for an id that is one of
 * this project's selects — so no other Drive file can be asked for by it. The
 * bytes are the still door's (`step6shelf.stillBytes`, kept in the bucket after
 * the first read).
 */

import { resolveProject } from "./projectid.js";

const DRIVE_ID = /^[A-Za-z0-9_-]{10,120}$/;
const MAX = 30;
const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const valueOf = (record, k) => {
  const f = record && isObject(record.facts) ? record.facts[k] : null;
  return isObject(f) ? f.value : undefined;
};

function escHtml(s) {
  return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

/** A link's name: the one he gave it, else the site's own (Vimeo, YouTube, else its address). */
const SITES = [["vimeo.com", "Vimeo"], ["youtube.com", "YouTube"], ["youtu.be", "YouTube"], ["instagram.com", "Instagram"], ["livid.com", "Livid"], ["frame.io", "Frame.io"], ["imdb.com", "IMDb"]];
export function watchName(url, title = "") {
  const t = String(title || "");
  if (t && !/^https?:/i.test(t) && !/^[a-z0-9.-]+\.[a-z]{2,}( · |\/|$)/i.test(t)) return t;
  const host = String(url || "").replace(/^https?:\/\//i, "").split(/[/?#]/)[0].toLowerCase().replace(/^www\./, "");
  for (const [tail, name] of SITES) if (host === tail || host.endsWith("." + tail)) return name;
  return host;
}

/** What a record shows once Released, or null: its selects (ids, his order), the website and the watch links. */
export function releasedOf(record) {
  if (!isObject(record) || record.deleted || record.closed) return null;
  const status = String(valueOf(record, "status") || record.stage || "");
  if (status !== "Released") return null;
  const raw = valueOf(record, "selects");
  const selects = (Array.isArray(raw) ? raw : []).filter((x) => typeof x === "string" && DRIVE_ID.test(x)).slice(0, MAX);
  const website = String(valueOf(record, "website") || "");
  const links = valueOf(record, "links");
  const watch = (isObject(links) && Array.isArray(links.custom) ? links.custom : [])
    .filter((l) => isObject(l) && l.slot === "watch" && /^https?:\/\//i.test(String(l.url || "")) && String(l.url) !== website)
    .slice(0, 6).map((l) => ({ url: String(l.url), name: watchName(l.url, l.title) }));
  return { selects, website: /^https?:\/\//i.test(website) ? website : "", watch };
}

/** The same for a portal (a film's relay id, a record key, a page): null unless Released. */
export async function releasedFor(env, project) {
  try {
    const found = await resolveProject(env, project);
    return releasedOf(found && found.record);
  } catch {
    return null;
  }
}

/** The home page's block: the selects, then the small links. "" with no selects. */
export function selectsBlock(base, rel) {
  if (!rel || !rel.selects.length) return "";
  const pics = rel.selects.map((id) => `<img src="${escHtml(base)}/select/${escHtml(id)}" alt="" loading="lazy" decoding="async">`).join("");
  const links = [
    rel.website ? `<a href="${escHtml(rel.website)}" target="_blank" rel="noopener">Website</a>` : "",
    ...rel.watch.map((l) => `<a href="${escHtml(l.url)}" target="_blank" rel="noopener">${escHtml(l.name)}</a>`),
  ].filter(Boolean);
  return `<section class="hm-sel" aria-label="Selects"><div class="hm-sel-g">${pics}</div>${links.length ? `<p class="hm-sel-l">${links.join("<span> · </span>")}</p>` : ""}</section>`;
}
