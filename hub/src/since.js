/**
 * **Since You Looked** — what changed on a film lately, for its home page.
 *
 * Read off the bucket's own listings, never the engine: a list of a prefix
 * answers with every object's name and when it was last written, and that is
 * all a "what changed" line needs. The film's change logs are one object per
 * device, rewritten as that device syncs, so the newest of them says *the film
 * changed* and when, though not what — the engine's replay is what would say
 * what, and a home page that replays the film is the page that must not. A
 * page, a board or a deck is one object apiece, so those say which one.
 *
 * Three small lists, `delimiter: "/"` so a board's save history (up to 300
 * copies under it) is not walked, and none of them opens a body, so this
 * costs the Worker request nothing against its six open answers.
 */
import { keys } from "../../relay/layout.js";
import { maySee, boardOpen } from "./films.js";
import { isArchived } from "./front.js";

/** The raw listings: log, page, board and deck objects with their write times. */
export async function changeListing(env, project) {
  const top = async (prefix) => {
    try {
      const out = await env.BUCKET.list({ prefix, delimiter: "/", limit: 200 });
      return out.objects || [];
    } catch {
      return [];
    }
  };
  const base = keys.pages(project).replace(/pages\/$/, "");
  const [logs, pages, boards, decks] = await Promise.all([
    top(keys.logs(project)), top(keys.pages(project)), top(`${base}boards/`), top(keys.decks(project)),
  ]);
  return { logs, pages, boards, decks, base };
}

const stem = (key, ext) => {
  const name = key.split("/").pop();
  return name.endsWith(ext) && !name.slice(0, -ext.length).includes(".") ? name.slice(0, -ext.length) : "";
};

/**
 * The last few changes this person may know about, newest first.
 *
 * Each is `{ at, said, what, where, href }`: when, the bold name, the rest of
 * the line, the page's name and where it lives. A page the viewer may not see
 * is not in the list, so a link holder never learns it moved.
 */
export function changesOf(listing, front, base, role, who, admin, visible) {
  if (!listing) return [];
  const sections = new Map((front.sections || []).map((one) => [one.slug, one]));
  const may = (one) => maySee(visible, "sections", one.slug, role) && boardOpen(one, who, admin) && !isArchived(front, one.slug);
  const found = [];

  // The film itself: one entry per device's log, those within ten minutes of
  // each other counted once (a fold rewrites them together).
  const logs = listing.logs.filter((o) => o.key.endsWith(".log"))
    .map((o) => new Date(o.uploaded).getTime()).filter(Number.isFinite).sort((a, b) => b - a);
  const apart = [];
  for (const t of logs) if (!apart.length || apart[apart.length - 1] - t > 10 * 60 * 1000) apart.push(t);
  for (const t of apart.slice(0, 3)) {
    found.push({ at: t, said: "Shot List", what: "changed", where: "Shot List", href: `${base}/shotlist` });
  }

  // Pages, boards and decks, by the section that owns them.
  const pageWrites = [];
  const put = (list, ext, nameOf) => {
    for (const o of list) {
      const slug = stem(o.key, ext);
      const one = slug ? nameOf(slug) : null;
      const t = new Date(o.uploaded).getTime();
      if (!one || !may(one) || !Number.isFinite(t)) continue;
      pageWrites.push({ at: t, one });
    }
  };
  put(listing.pages, ".json", (slug) => sections.get(slug));
  const byBoard = new Map((front.sections || []).filter((s) => s.board).map((s) => [s.board, s]));
  put(listing.boards, ".json", (slug) => byBoard.get(slug) || null);
  put(listing.decks, ".json", (slug) => sections.get(slug));

  // A refresh from Notion rewrites every page at once: three or more within
  // ten minutes are one line, not a wall of the same minute.
  pageWrites.sort((a, b) => b.at - a.at);
  const used = new Set();
  for (const w of pageWrites) {
    if (used.has(w.one.slug)) continue;
    const near = pageWrites.filter((x) => !used.has(x.one.slug) && Math.abs(x.at - w.at) <= 10 * 60 * 1000);
    const slugs = [...new Set(near.map((x) => x.one.slug))];
    slugs.forEach((s) => used.add(s));
    if (slugs.length >= 3) {
      found.push({ at: w.at, said: `${slugs.length} Pages`, what: "updated", where: "Library", href: `${base}/library` });
    } else {
      for (const s of slugs) {
        const one = sections.get(s) || byBoard.get(s) || w.one;
        const at = Math.max(...near.filter((x) => x.one.slug === s).map((x) => x.at));
        found.push({
          at, said: one.name, what: "updated", where: one.name,
          href: `${base}/${one.slug}`,
        });
      }
    }
  }

  // The film's details (logline, crew, days), dated by the card.
  const card = Date.parse(front.updated || "");
  if (Number.isFinite(card)) {
    found.push({ at: card, said: "Details", what: "updated", where: "Overview", href: base });
  }

  return found.sort((a, b) => b.at - a.at).slice(0, 5)
    .map((one) => ({ ...one, at: new Date(one.at).toISOString() }));
}
