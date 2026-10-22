/**
 * A Google Doc, as Drive's Markdown export, made into a designed portal page.
 *
 * **A line-for-line copy of `~/Developer/agents/doc-mirror/render.py`**, which
 * drew Halcyon's Outline from Ivy's doc on the Mac until 2026-10-10, when he
 * asked for the switch to live on the page instead of in Projects Console
 * (`docfollow.js` does the fetching now). Same Markdown in, same HTML out —
 * `hub/docfollow.mjs` holds the two to that, byte for byte, on a real copy of
 * the doc.
 *
 * Pure: Markdown and a little metadata in, one HTML fragment out (its own
 * <style> plus the page). It recognises a few shapes the way a reader would,
 * and anything it doesn't recognise is still drawn as plain words:
 *
 *   `**— NAME —**`            a section (Characters, Scenes, the film's title)
 *   `**SOME CAPS LINE**`      a scene heading; an italic line under it is who's in it
 *   `**LEFT:** Right`         under Characters, one person
 *   a wholly italic paragraph a writer's note
 *   `[ ... ]`                 an open question
 */

// Bump when the design changes, so every followed page is redrawn once even
// though its doc hasn't moved.
export const RENDER_VERSION = "1";

const CAST_COLORS = ["#E39A9A", "#93C3A3", "#8FB3E3", "#DDB46E", "#BBA0E6",
  "#7FC6C6", "#E0A67E", "#C9C27A"];
const EXTRA_COLOR = "#8E867E";

// Python's `\w` is Unicode-aware; JavaScript's is not, even under `u`.
const W = "[\\p{L}\\p{N}_]";
const SECTION = /^[—–-]{1,3}\s*(.+?)\s*[—–-]{1,3}$/u;
const ESCAPED = /\\([\\`*_{}\[\]()#+\-.!|>~<"'=$&])/gu;
const LIST_ITEM = /^\s*(?:[-*+]|\d+[.)])\s+/u;

/** `html.escape`: `&`, `<`, `>`, and with `quote` the two quote marks. */
function escape(s, quote = true) {
  let t = String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  if (quote) t = t.replace(/"/g, "&quot;").replace(/'/g, "&#x27;");
  return t;
}

const NAMED = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };
function unescape(s) {
  return s.replace(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (all, e) => {
    if (e[0] === "#") {
      const code = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try { return String.fromCodePoint(code); } catch { return all; }
    }
    return Object.prototype.hasOwnProperty.call(NAMED, e) ? NAMED[e] : all;
  });
}

/** Python's `str.strip(chars)`. */
function stripChars(s, chars) {
  let a = 0;
  let b = s.length;
  while (a < b && chars.includes(s[a])) a += 1;
  while (b > a && chars.includes(s[b - 1])) b -= 1;
  return s.slice(a, b);
}

/** Python's `str.title()`: each run of letters gets a capital, then lower case. */
function titleCase(s) {
  return s.replace(/\p{L}+/gu, (w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase());
}

/* ------------------------------------------------------------------ inline */

/**
 * Markdown inline → HTML, with the typography a reader expects: curly quotes,
 * real apostrophes, and dialogue lifted a shade brighter.
 */
export function inline(s, imageSrc = null) {
  const keep = [];
  const stash = (x) => { keep.push(x); return `\x00${keep.length - 1}\x00`; };

  s = s.replace(ESCAPED, (m, c) => stash(escape(c, false)));
  s = s.replace(/!\[([^\]]*)\]\[([^\]]+)\]/gu, (m, alt, ref) => {
    const src = imageSrc ? imageSrc(ref) : "";
    if (!src) return "";
    return stash(`<img src="${escape(src)}" alt="${escape(alt)}" loading="lazy">`);
  });
  s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/gu, () => "");
  s = s.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/gu,
    (m, text, href) => stash(`<a href="${escape(href)}" target="_blank" rel="noopener">${escape(text, false)}</a>`));

  s = escape(s, false);
  s = s.replace(/\*\*\*(.+?)\*\*\*/gu, "<strong><em>$1</em></strong>");
  s = s.replace(/\*\*(.+?)\*\*/gu, "<strong>$1</strong>");
  s = s.replace(new RegExp(`(?<![\\p{L}\\p{N}_*])\\*(?!\\s)(.+?)(?<!\\s)\\*(?![\\p{L}\\p{N}_*])`, "gu"), "<em>$1</em>");
  s = s.replace(new RegExp(`(?<![\\p{L}\\p{N}_])_(?!\\s)(.+?)(?<!\\s)_(?![\\p{L}\\p{N}_])`, "gu"), "<em>$1</em>");
  s = s.split("<strong></strong>").join("").split("<em></em>").join("");

  const count = (t, x) => t.split(x).length - 1;
  const balanced = (t) => ["em", "strong"].every((g) => count(t, `<${g}>`) === count(t, `</${g}>`));
  s = s.replace(/["“]([^"“”]*?)["”]/gu, (all, body) => {
    if (!body.trim()) return all;
    if (!balanced(body)) return `“${body}”`;
    return `\x02“${body}”\x03`;
  });
  // Whatever straight quotes are left over had no partner.
  s = s.replace(/(^|[\s(\[—–-])"/gu, "$1“");
  s = s.split("\"").join("”");
  s = s.replace(new RegExp(`(?<=${W})'`, "gu"), "’");
  s = s.split("'").join("‘");
  s = s.split("\x02").join("<span class=\"q\">").split("\x03").join("</span>");
  s = s.replace(/\x00(\d+)\x00/g, (m, n) => keep[Number(n)]);
  return s;
}

function plain(s) {
  return unescape(inline(s).replace(/<[^>]+>/g, "")).trim();
}

/** Is this whole line wrapped in one emphasis (`**` or `*`)? */
function wholly(line, mark) {
  line = line.trim();
  const n = mark.length;
  if (line.length <= 2 * n || !(line.startsWith(mark) && line.endsWith(mark))) return false;
  if (mark === "*" && (line.startsWith("**") || line.endsWith("**"))) {
    // `*a**,** b*` is italic with a bold comma inside — still wholly italic.
    return line.startsWith("*") && !line.startsWith("**") && line.endsWith("*") && !line.endsWith("**");
  }
  return true;
}

function shouting(text) {
  const letters = [...text].filter((c) => /\p{L}/u.test(c));
  const upper = letters.filter((c) => c !== c.toLowerCase() && c === c.toUpperCase()).length;
  return letters.length > 0 && upper / letters.length >= 0.7;
}

/* ------------------------------------------------------------------ blocks */

/** Markdown → a flat list of blocks: heading, rule, list, table, image, para. */
function blocksOf(md) {
  const refs = {};
  md = md.replace(/^\[([^\]]+)\]:\s*<?(data:[^>\s]+)>?\s*$/gmu, (m, ref, uri) => { refs[ref] = uri; return ""; });

  const out = [];
  for (const chunk of md.trim().split(/\n[ \t]*\n/u)) {
    let lines = chunk.split("\n").filter((l) => l.trim());
    while (lines.length) {
      const first = lines[0].trim();
      const h = /^(#{1,6})\s+(.*)$/u.exec(first);
      if (h) {
        out.push({ t: "heading", level: h[1].length, md: h[2].trim() });
        lines = lines.slice(1);
        continue;
      }
      if (/^(-{3,}|\*{3,}|_{3,})$/u.test(first)) {
        out.push({ t: "rule" });
        lines = lines.slice(1);
        continue;
      }
      if (lines.every((l) => LIST_ITEM.test(l))) {
        out.push({ t: "list", ordered: /^\s*\d/u.test(lines[0]), items: lines.map((l) => l.replace(LIST_ITEM, "")) });
        break;
      }
      if (lines.every((l) => l.trim().startsWith("|"))) {
        let rows = lines.map((l) => stripChars(l.trim(), "|").split("|").map((c) => c.trim()));
        rows = rows.filter((r) => !r.filter((c) => c).every((c) => /^:?-{2,}:?$/u.test(c)));
        out.push({ t: "table", rows });
        break;
      }
      const onlyImg = /^!\[[^\]]*\]\[([^\]]+)\]$/u.exec(first);
      if (onlyImg && lines.length === 1) {
        out.push({ t: "image", ref: onlyImg[1] });
        break;
      }
      out.push({ t: "para", lines: lines.map((l) => l.trimEnd()) });
      break;
    }
  }
  return { blocks: out, refs };
}

/** The data-URI pictures a doc's Markdown carries, by reference name. */
export function picturesOf(md) {
  return blocksOf(md).refs;
}

/** A paragraph's lines joined back up: a hard break where Docs put one. */
const paraMd = (lines) => lines.map((l) => l.trimEnd()).join("\n");
const paraHtml = (lines, imageSrc = null) => lines.map((l) => inline(l.trim(), imageSrc)).join("<br>");

/* --------------------------------------------------------------- structure */

/** Blocks grouped into sections, and scenes picked out of them. */
function structure(md) {
  const { blocks, refs } = blocksOf(md);
  let title = "";
  const sections = [];
  let cur = { name: "", items: [] };
  sections.push(cur);
  let scene = null;

  let i = 0;
  while (i < blocks.length) {
    const b = blocks[i];
    i += 1;
    if (b.t === "heading" && b.level === 1 && !title) {
      title = plain(b.md);
      continue;
    }
    if (b.t === "rule") continue;
    if (b.t === "para" && b.lines.length === 1) {
      const m = SECTION.exec(plain(b.lines[0]));
      if (m) {
        scene = null;
        cur = { name: m[1].trim(), items: [] };
        sections.push(cur);
        continue;
      }
    }
    if (b.t === "heading") {
      const m = SECTION.exec(plain(b.md));
      if (m || b.level <= 2) {
        scene = null;
        cur = { name: (m ? m[1] : plain(b.md)).trim(), items: [] };
        sections.push(cur);
        continue;
      }
    }
    // A scene heading: a wholly bold line in capitals, or a small heading.
    let head = null;
    let rest = [];
    if (b.t === "para" && wholly(b.lines[0], "**") && shouting(plain(b.lines[0]))
        && [...plain(b.lines[0])].length <= 160 && !isPair(b.lines[0])) {
      head = b.lines[0];
      rest = b.lines.slice(1);
    } else if (b.t === "heading" && b.level >= 3) {
      head = b.md;
      rest = [];
    }
    if (head !== null) {
      let who = "";
      if (rest.length && wholly(rest[0], "*")) {
        who = plain(rest[0]);
        rest = rest.slice(1);
      } else if (!rest.length && i < blocks.length && blocks[i].t === "para"
          && blocks[i].lines.length === 1 && wholly(blocks[i].lines[0], "*")
          && plain(blocks[i].lines[0]).split(/\s+/u).filter(Boolean).length <= 10) {
        who = plain(blocks[i].lines[0]);
        i += 1;
      }
      scene = { t: "scene", title: plain(head), who: namesIn(who), blocks: [] };
      if (rest.length) scene.blocks.push({ t: "para", lines: rest });
      cur.items.push(scene);
      continue;
    }
    if (scene !== null) scene.blocks.push(b);
    else cur.items.push(b);
  }
  return { title, sections: sections.filter((s) => s.name || s.items.length), refs };
}

function isPair(line) {
  return /^\s*\*\*[^*:]{1,40}:\*\*\s*\S/u.test(line) || /^\s*\*\*[^*:]{1,40}\*\*\s*:\s*\S/u.test(line);
}

function namesIn(who) {
  who = stripChars(who.trim(), ".,;: ");
  if (!who) return [];
  return who.split(new RegExp(`\\s*(?:,|&|\\+|/|(?<!${W})and(?!${W}))\\s*`, "u"))
    .map((p) => stripChars(p, " .")).filter(Boolean);
}

/** `GEMMA: Gracie` lines → [[left, right]], and the blocks that weren't. */
function castOf(section) {
  const pairs = [];
  const other = [];
  for (const b of section.items) {
    if (b.t === "para" && b.lines.length === 1) {
      const m = /^([^:]{1,40}):\s*(.{1,60})$/u.exec(plain(b.lines[0]));
      if (m) { pairs.push([m[1].trim(), m[2].trim()]); continue; }
    }
    other.push(b);
  }
  return [pairs, other];
}

/* ------------------------------------------------------------------ render */

const esc = (s) => escape(s || "", true);
const two = (n) => String(n).padStart(2, "0");

/**
 * The whole page. `meta`: the Drive file (name, modifiedTime, webViewLink).
 * `cfg`: film, name, credit, doc_url. `imageSrc(ref, dataUri)` → a URL.
 */
export function render(md, meta, cfg, imageSrc = null) {
  const film = cfg.film || "";
  const credit = cfg.credit || "";
  const doc = structure(md);
  const refs = doc.refs;
  const src = (ref) => (imageSrc ? imageSrc(ref, refs[ref] || "") : "");

  const sections = doc.sections;
  const castSec = sections.find((s) => ["characters", "character", "cast"].includes(s.name.toLowerCase())) || null;
  const [pairs, castRest] = castSec ? castOf(castSec) : [[], []];
  const scenes = sections.flatMap((s) => s.items.filter((it) => it.t === "scene"));

  // Which side of `GEMMA: Gracie` is the one the scenes use? Count.
  const used = {};
  for (const sc of scenes) for (const n of sc.who) used[n.toLowerCase()] = (used[n.toLowerCase()] || 0) + 1;
  const sum = (f) => pairs.reduce((a, p) => a + (used[f(p).toLowerCase()] || 0), 0);
  const rightWins = sum((p) => p[1]) >= sum((p) => p[0]);
  const people = pairs.map(([l, r]) => (rightWins ? [r, l] : [l, r]));   // [name, beside]

  const color = {};
  people.forEach(([name], n) => { color[name.toLowerCase()] = CAST_COLORS[n % CAST_COLORS.length]; });
  const columns = people.map(([name]) => name);
  for (const sc of scenes) {
    for (const n of sc.who) if (!columns.map((c) => c.toLowerCase()).includes(n.toLowerCase())) columns.push(n);
  }
  for (const c of columns) if (!(c.toLowerCase() in color)) color[c.toLowerCase()] = EXTRA_COLOR;
  const dot = (name) => `<i class="dot" style="--c:${color[name.toLowerCase()] || EXTRA_COLOR}"></i>`;

  const title = cfg.name || (doc.title ? titleCase(doc.title) : meta.name || "");
  const when = updatedLabel(meta.modifiedTime || "");
  const link = cfg.doc_url || meta.webViewLink || "";

  const out = [`<style>${CSS}</style>`, "<div class=\"olweb\"><div class=\"olin\">"];

  // ---- head
  out.push("<header class=\"lead\"><div class=\"toprow\">");
  out.push(`<p class="eyebrow">${esc(film)}<span class="sl">//</span>${esc((cfg.eyebrow || title).toLowerCase())}</p>`);
  if (link) {
    out.push(`<a class="docbtn" href="${esc(link)}" target="_blank" rel="noopener">Open the Google Doc<span class="arr">↗</span></a>`);
  }
  out.push(`</div><h2 class="title">${esc(title)}</h2>`);
  const bits = [];
  if (credit) bits.push(`${esc(credit)}’s working draft`);
  if (when) bits.push(`updated ${esc(when)}`);
  if (scenes.length) bits.push(`${scenes.length} scenes`);
  out.push(`<p class="sub">${bits.map((b) => `<span>${b}</span>`).join("")}</p>`);
  out.push("</header>");

  // ---- sections
  for (const s of sections) {
    const name = s.name;
    const kind = s === castSec ? "cast" : film && name.toLowerCase() === film.toLowerCase() ? "logline" : "body";
    if (kind === "cast") {
      if (!people.length && !castRest.length) continue;
      out.push(`<section class="block cast"><h3 class="label">${esc(titleCase(name))}</h3><div class="castgrid">`);
      for (const [who, beside] of people) {
        const count = scenes.filter((sc) => sc.who.map((w) => w.toLowerCase()).includes(who.toLowerCase())).length;
        out.push(`<div class="person" style="--c:${color[who.toLowerCase()]}"><i class="pdot"></i><p class="pname">${esc(who)}</p><p class="pbeside">${esc(beside)}</p>${
          scenes.length ? `<p class="pcount">${count} scene${count === 1 ? "" : "s"}</p>` : ""}</div>`);
      }
      out.push("</div>");
      out.push(...renderBlocks(castRest, src));
      out.push("</section>");
      continue;
    }
    if (kind === "logline") {
      out.push("<section class=\"block logline\"><h3 class=\"label\">Logline</h3>");
      let first = true;
      for (const b of s.items) {
        if (first && b.t === "para") {
          out.push(`<p class="logtext">${paraHtml(b.lines, src).replace(/<\/?strong>/g, "")}</p>`);
          first = false;
        } else {
          out.push(...renderBlocks([b], src));
        }
      }
      out.push("</section>");
      continue;
    }

    const hasScenes = s.items.some((it) => it.t === "scene");
    out.push(`<section class="block${hasScenes ? " scenes" : ""}">`);
    if (name) {
      out.push(`<h3 class="label">${esc(titleCase(name))}${
        hasScenes ? ` <span class="count">${s.items.filter((it) => it.t === "scene").length}</span>` : ""}</h3>`);
    }
    if (hasScenes && scenes.some((sc) => sc.who.length) && columns.length) out.push(glance(s, columns, color));
    for (const it of s.items) {
      if (it.t === "scene") out.push(sceneHtml(it, scenes.indexOf(it) + 1, dot, src));
      else out.push(...renderBlocks([it], src));
    }
    out.push("</section>");
  }

  // ---- foot
  out.push(`<footer class="foot"><p>This page follows ${credit ? `${esc(credit)}’s` : "the"} Google Doc and redraws itself within a few minutes of every edit.</p>${
    link ? `<a class="docbtn" href="${esc(link)}" target="_blank" rel="noopener">Open the Google Doc<span class="arr">↗</span></a>` : ""}</footer>`);
  out.push("</div></div>");
  return out.join("\n");
}

function glance(section, columns, color) {
  const rows = section.items.filter((it) => it.t === "scene");
  const head = columns.map((c) => `<th class="who" title="${esc(c)}"><i class="dot" style="--c:${color[c.toLowerCase()]}"></i><span class="full">${esc(c)}</span><span class="init">${esc([...c][0] || "")}</span></th>`).join("");
  const body = rows.map((sc, k) => {
    const here = sc.who.map((w) => w.toLowerCase());
    const cells = columns.map((c) => `<td class="who">${
      here.includes(c.toLowerCase()) ? `<i class="dot on" style="--c:${color[c.toLowerCase()]}"></i>` : "<i class=\"dot off\"></i>"}</td>`).join("");
    return `<tr><td class="n">${two(k + 1)}</td><td class="t">${esc(sc.title)}</td>${cells}</tr>`;
  });
  return `<div class="glance"><p class="glabel">At a glance <span>who is in each scene</span></p><div class="gscroll"><table><thead><tr><th class="n"></th><th class="t"></th>${head}</tr></thead><tbody>${body.join("")}</tbody></table></div></div>`;
}

function sceneHtml(sc, n, dot, src) {
  const who = sc.who.map((w) => `<span class="chip">${dot(w)}${esc(w)}</span>`).join("");
  return `<article class="scene"><div class="snum">${two(n)}</div><div class="sbody"><h4 class="stitle">${esc(sc.title)}</h4>${
    who ? `<div class="chips">${who}</div>` : ""}${renderBlocks(sc.blocks, src).join("")}</div></article>`;
}

function renderBlocks(blocks, src) {
  const out = [];
  for (const b of blocks) {
    if (b.t === "para") {
      const p = plain(paraMd(b.lines));
      const bracketed = p.startsWith("[") && p.endsWith("]");
      if ((bracketed && b.lines.length === 1) || (wholly(b.lines[0], "*") && bracketed)) {
        let inner = paraHtml(b.lines, src);
        inner = inner.replace(/^(<em>)?\[/, "$1").replace(/\](<\/em>)?$/, "$1").replace(/<\/?em>/g, "");
        out.push(`<aside class="ask"><span class="asklabel">Open question</span><p>${inner}</p></aside>`);
      } else if (b.lines.every((l) => wholly(l, "*"))) {
        out.push(`<aside class="note"><p>${paraHtml(b.lines, src).replace(/<\/?em>/g, "")}</p></aside>`);
      } else {
        out.push(`<p>${paraHtml(b.lines, src)}</p>`);
      }
    } else if (b.t === "heading") {
      out.push(`<h5 class="subhead">${inline(b.md, src)}</h5>`);
    } else if (b.t === "list") {
      const tag = b.ordered ? "ol" : "ul";
      out.push(`<${tag}>${b.items.map((x) => `<li>${inline(x, src)}</li>`).join("")}</${tag}>`);
    } else if (b.t === "table") {
      const rows = b.rows;
      if (rows.length) {
        const head = rows[0].map((c) => `<th>${inline(c, src)}</th>`).join("");
        const body = rows.slice(1).map((r) => `<tr>${r.map((c) => `<td>${inline(c, src)}</td>`).join("")}</tr>`).join("");
        out.push(`<div class="tbl"><table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`);
      }
    } else if (b.t === "image") {
      const u = src(b.ref);
      if (u) out.push(`<figure class="pic"><img src="${esc(u)}" alt="" loading="lazy"></figure>`);
    }
  }
  return out;
}

/**
 * "10 Oct 2026, 9:41 pm", on his clock. The Mac drew this in its own time
 * zone; the worker has none, so it is named.
 */
export function updatedLabel(iso) {
  if (!iso) return "";
  const t = new Date(iso);
  if (Number.isNaN(t.getTime())) return "";
  const part = {};
  for (const p of new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles", day: "numeric", month: "short", year: "numeric",
    hour: "numeric", minute: "2-digit", hour12: true,
  }).formatToParts(t)) part[p.type] = p.value;
  return `${part.day} ${part.month} ${part.year}, ${part.hour}:${part.minute} ${String(part.dayPeriod || "").toLowerCase()}`;
}

const CSS = String.raw`
.olweb{--ink:#F3EFE9;--body:#CFC7BD;--gold:#D9A867;--quiet:#9A9189;
  --rule:rgba(243,239,233,.13);--panel:rgba(243,239,233,.035);
  --serif:"Iowan Old Style","Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;
  font-family:-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;color:var(--body);
  -webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}
.olweb *{box-sizing:border-box}
.olweb .olin{max-width:1120px;margin:0 auto;padding:0 40px}
.olweb p{margin:0}
.olweb a{color:inherit}

.olweb .lead{padding:56px 0 44px;border-bottom:1px solid var(--rule)}
.olweb .toprow{display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap}
.olweb .eyebrow{font-size:11px;letter-spacing:.22em;text-transform:uppercase;color:var(--gold)}
.olweb .eyebrow .sl{color:var(--quiet);padding:0 .5em}
.olweb .title{font-size:clamp(40px,7vw,76px);line-height:1;font-weight:600;color:var(--ink);
  margin:22px 0 0;letter-spacing:-.015em}
.olweb .sub{font-size:13px;letter-spacing:.04em;color:var(--quiet);margin-top:16px;
  display:flex;flex-wrap:wrap;gap:4px 0}
.olweb .sub span{white-space:nowrap}
.olweb .sub span+span::before{content:"·";padding:0 .6em;opacity:.6}

.olweb .docbtn{display:inline-flex;align-items:center;gap:.6em;font-size:11px;font-weight:600;
  letter-spacing:.16em;text-transform:uppercase;text-decoration:none;color:var(--gold);
  border:1px solid rgba(217,168,103,.45);border-radius:999px;padding:10px 16px 10px 18px;
  transition:background .2s,color .2s,border-color .2s;white-space:nowrap}
.olweb .docbtn .arr{font-size:13px;letter-spacing:0;transition:transform .2s}
.olweb .docbtn:hover{background:var(--gold);color:#0A0A0A;border-color:var(--gold)}
.olweb .docbtn:hover .arr{transform:translate(2px,-2px)}

.olweb .block{padding:56px 0 8px}
.olweb .label{font-size:11px;font-weight:600;letter-spacing:.22em;text-transform:uppercase;
  color:var(--gold);margin:0 0 26px;display:flex;align-items:center;gap:14px}
.olweb .label::after{content:"";flex:1;height:1px;background:var(--rule)}
.olweb .label .count{color:var(--quiet);font-weight:500;letter-spacing:.1em}

.olweb .logline{padding-top:64px}
.olweb .block>p.logtext{margin:0;font-family:var(--serif);font-size:clamp(24px,3.2vw,38px);line-height:1.34;
  color:var(--ink);max-width:23em;letter-spacing:-.005em;font-weight:400;text-wrap:pretty}
.olweb .logtext::before{content:"\201C";color:var(--gold);margin-left:-.45em;padding-right:.05em}
.olweb .logtext::after{content:"\201D";color:var(--gold);padding-left:.05em}

.olweb .castgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}
.olweb .person{position:relative;background:var(--panel);border:1px solid var(--rule);border-radius:3px;
  padding:22px 20px 20px;overflow:hidden}
.olweb .person::before{content:"";position:absolute;left:0;top:0;right:0;height:2px;background:var(--c);opacity:.85}
.olweb .pdot{display:none}
.olweb .pname{font-family:var(--serif);font-size:28px;line-height:1.1;color:var(--ink)}
.olweb .pbeside{font-size:11px;letter-spacing:.2em;text-transform:uppercase;color:var(--quiet);margin-top:10px}
.olweb .pcount{font-size:12px;color:var(--c);margin-top:18px;letter-spacing:.02em}

.olweb .glance{background:var(--panel);border:1px solid var(--rule);border-radius:3px;
  padding:22px 22px 14px;margin-bottom:40px}
.olweb .glabel{font-size:11px;letter-spacing:.2em;text-transform:uppercase;color:var(--ink);font-weight:600;margin-bottom:14px}
.olweb .glabel span{color:var(--quiet);font-weight:500;letter-spacing:.06em;text-transform:none;font-size:12px;padding-left:.6em}
.olweb .gscroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
.olweb .glance table{border-collapse:collapse;width:100%;min-width:0}
.olweb .glance th{font-size:10px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;
  color:var(--quiet);padding:0 0 12px;text-align:center;white-space:nowrap}
.olweb .glance th .dot{margin-right:6px;vertical-align:1px}
.olweb .glance td{padding:9px 0;border-top:1px solid var(--rule);vertical-align:middle}
.olweb .glance tr:hover td{background:rgba(243,239,233,.03)}
.olweb .glance td.n{width:40px;font-size:12px;color:var(--gold);font-variant-numeric:tabular-nums;padding-left:4px}
.olweb .glance td.t{font-size:12px;letter-spacing:.06em;text-transform:uppercase;color:var(--ink);
  padding-right:18px;line-height:1.35}
.olweb .glance .who{width:82px;text-align:center}
.olweb .glance .init{display:none}
.olweb .dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--c,#8E867E)}
.olweb .glance td .dot.on{width:10px;height:10px;box-shadow:0 0 0 3px color-mix(in srgb,var(--c) 18%,transparent)}
.olweb .glance td .dot.off{width:4px;height:4px;background:rgba(243,239,233,.16)}

.olweb .scene{display:grid;grid-template-columns:96px minmax(0,1fr);gap:0 8px;
  padding:40px 0 36px;border-top:1px solid var(--rule)}
.olweb .snum{font-family:var(--serif);font-size:40px;line-height:1;color:var(--gold);
  font-variant-numeric:lining-nums tabular-nums;opacity:.9;padding-top:2px}
.olweb .stitle{font-size:17px;font-weight:600;letter-spacing:.09em;text-transform:uppercase;
  color:var(--ink);margin:0;line-height:1.35;max-width:46em}
.olweb .chips{display:flex;flex-wrap:wrap;gap:6px;margin:14px 0 4px}
.olweb .chip{display:inline-flex;align-items:center;gap:7px;font-size:12px;color:var(--ink);
  border:1px solid var(--rule);border-radius:999px;padding:4px 11px 4px 9px;background:var(--panel)}
.olweb .sbody>p,.olweb .block>p,.olweb .sbody ul,.olweb .sbody ol,.olweb .block>ul,.olweb .block>ol{
  font-size:17px;line-height:1.72;max-width:40em;margin:18px 0 0;text-wrap:pretty}
.olweb .sbody li,.olweb .block li{margin:4px 0}
.olweb .q{color:var(--ink)}
.olweb strong{color:var(--ink);font-weight:600}
.olweb em{font-family:var(--serif);font-style:italic;font-size:1.04em}

.olweb .note{margin:22px 0 0;max-width:40em;padding:2px 0 2px 20px;border-left:2px solid rgba(217,168,103,.55)}
.olweb .note p{font-family:var(--serif);font-style:italic;font-size:17.5px;line-height:1.6;color:#BFB6AB}
.olweb .ask{margin:22px 0 0;max-width:40em;border:1px dashed rgba(217,168,103,.45);border-radius:3px;
  padding:14px 18px 15px;background:rgba(217,168,103,.05)}
.olweb .asklabel{display:block;font-size:10px;font-weight:600;letter-spacing:.2em;text-transform:uppercase;color:var(--gold);margin-bottom:6px}
.olweb .ask p{font-size:15px;line-height:1.6;color:var(--ink)}
.olweb .subhead{font-size:13px;font-weight:600;letter-spacing:.14em;text-transform:uppercase;color:var(--ink);margin:30px 0 0}
.olweb .pic{margin:24px 0 0;max-width:40em}
.olweb .pic img,.olweb p img{max-width:100%;height:auto;display:block;border-radius:2px}
.olweb .tbl{overflow-x:auto;margin:20px 0 0}
.olweb .tbl table{border-collapse:collapse;font-size:14px}
.olweb .tbl th,.olweb .tbl td{border-bottom:1px solid var(--rule);padding:8px 14px 8px 0;text-align:left;vertical-align:top}
.olweb .tbl th{color:var(--ink);font-weight:600}

.olweb .foot{margin-top:56px;padding:28px 0 64px;border-top:1px solid var(--rule);
  display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap}
.olweb .foot p{font-size:13px;color:var(--quiet);max-width:36em;line-height:1.55}

@media (max-width:900px){
  .olweb .olin{padding:0 28px}
  .olweb .scene{grid-template-columns:72px minmax(0,1fr)}
  .olweb .snum{font-size:32px}
  .olweb .glance .who{width:56px}
}
@media (max-width:640px){
  .olweb .olin{padding:0 16px}
  .olweb .lead{padding:36px 0 32px}
  .olweb .sub{gap:6px 16px}
  .olweb .sub span+span::before{content:none}
  .olweb .block{padding-top:44px}
  .olweb .scene{grid-template-columns:1fr;padding:32px 0 28px}
  .olweb .snum{font-size:26px;margin-bottom:10px}
  .olweb .stitle{font-size:15px}
  .olweb .sbody>p,.olweb .block>p{font-size:16px;line-height:1.68}
  .olweb .castgrid{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
  .olweb .person{padding:18px 14px 16px}
  .olweb .pname{font-size:23px}
  .olweb .glance{padding:16px 12px 8px;margin-left:-4px;margin-right:-4px}
  .olweb .glance .who{width:26px}
  .olweb .glance .full{display:none}
  .olweb .glance .init{display:inline}
  .olweb .glance th .dot{display:none}
  .olweb .glance td.n{width:26px;padding-left:0}
  .olweb .glance td.t{font-size:11px;padding-right:8px}
  .olweb .docbtn{padding:9px 14px 9px 15px}
}
`;
