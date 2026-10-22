/**
 * **A page kept only as designed HTML, read back as a normal page** — for the
 * iPhone app, which draws every page natively and never shows a web view (his
 * rulings of 2026-10-06: *"I do not want to combine a web app into an iOS app
 * … ugly"* and *"everything should feel native. Don't want to click a link to
 * the portal."*).
 *
 * The portal still draws such a page as its own design. The phone's door
 * (`phoneDoor`, `page/<slug>`) hands it down as the same block tree every
 * written page is, made here, so the phone has one way to draw a page.
 *
 * **The same road the hand-made pages took** (Ref 1543): the page is said as
 * Markdown and read by `pageFrom`, the reader `set_page` and
 * `/console/rebuild` use, so it is held to the same rules: stored pictures
 * only, http(s) links only, and anything that cannot be kept named in
 * `dropped` rather than vanishing.
 *
 * **Words, pictures, clips and tables; nothing invented, nothing left out.**
 * What the page hides (`display:none` outside a screen-size rule, `hidden`)
 * is left out because nobody sees it there either. What a design says with
 * shape alone is said in words a page can carry:
 *
 * - a row of pictures is a row of pictures (`columns`)
 * - a grid of like cards (a cast, a crew) is a list, a card to a line, its
 *   lines joined with ` · `
 * - like things side by side (chips, a subtitle's parts) are joined with ` · `
 * - an empty mark that is switched on (`class="dot on"`, a scene's who-is-in
 *   table) is `●`, switched off is empty, as the page shows it
 * - a short label set before a heading (a scene's number) leads the heading
 *
 * No DOM in a Worker, so a small forgiving reader of its own: tags, text,
 * entities, the end tags HTML lets a page leave out.
 */

import { pageFrom } from "./paper.js";

/** Stored files, the shape `paper.js` insists on. */
const FILE_NAME = /^[0-9a-f]{32}\.[A-Za-z0-9]{1,8}$/;
const FILE_LINK = /^\[[^\]]*\]\(\s*[0-9a-f]{32}\.[A-Za-z0-9]{1,8}\s*\)$/;

const VOID = new Set(["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]);
const RAW = new Set(["script", "style", "textarea", "title", "noscript", "template"]);
const SKIP = new Set(["script", "style", "template", "noscript", "head", "title", "meta", "link", "svg", "button", "input", "select", "textarea", "form", "canvas", "object", "embed"]);
const BLOCK = new Set([
  "address", "article", "aside", "blockquote", "details", "dialog", "dd", "div", "dl", "dt", "fieldset",
  "figcaption", "figure", "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "li",
  "main", "nav", "ol", "p", "pre", "section", "table", "ul", "summary", "video", "iframe", "picture",
  "thead", "tbody", "tfoot", "tr", "td", "th", "caption", "body", "html",
]);
/** Inline marks a run cannot carry anyway (`paper.js` keeps text and links). */
const EMPHASIS = new Set(["b", "strong", "em", "i", "u", "s", "mark", "small", "code", "sup", "sub", "q", "cite", "abbr", "time", "kbd", "var", "del", "ins"]);

const ENTITIES = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", rsquo: "’", lsquo: "‘", rdquo: "”",
  ldquo: "“", hellip: "…", mdash: "—", ndash: "–", middot: "·", bull: "•", times: "×", copy: "©",
  reg: "®", trade: "™", deg: "°", larr: "←", rarr: "→", uarr: "↑", darr: "↓", nearr: "↗", laquo: "«",
  raquo: "»", prime: "′", Prime: "″", frac12: "½", frac14: "¼", frac34: "¾", eacute: "é", egrave: "è",
  agrave: "à", ccedil: "ç", uuml: "ü", ouml: "ö", auml: "ä", ntilde: "ñ", zwj: "‍", shy: "",
};

function decode(text) {
  return String(text).replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);/gi, (all, e) => {
    if (e[0] === "#") {
      const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      try { return String.fromCodePoint(n); } catch { return all; }
    }
    return Object.prototype.hasOwnProperty.call(ENTITIES, e) ? ENTITIES[e] : all;
  });
}

// ------------------------------------------------------------------ reading

/** The page as a tree of `{ tag, at, kids }` and strings. */
export function parseHtml(html) {
  const root = { tag: "#root", at: {}, kids: [] };
  const stack = [root];
  const top = () => stack[stack.length - 1];
  const styles = [];
  const said = String(html || "");
  const tag = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<![^>]*>|<\/?([a-zA-Z][a-zA-Z0-9-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'>]+))?)*)\s*\/?>/g;
  let last = 0;
  let found;

  const close = (name) => {
    for (let i = stack.length - 1; i > 0; i -= 1) {
      if (stack[i].tag === name) { stack.length = i; return true; }
    }
    return false;
  };
  // The end tags a page may leave out: a new block shuts an open paragraph,
  // an item the item before it, a cell the cell, a row the row.
  const implied = (name) => {
    if (BLOCK.has(name) && name !== "li" && top().tag === "p") stack.length -= 1;
    const shut = (names, until) => {
      for (let i = stack.length - 1; i > 0; i -= 1) {
        if (until.includes(stack[i].tag)) return;
        if (names.includes(stack[i].tag)) { stack.length = i; return; }
      }
    };
    if (name === "li") shut(["li"], ["ul", "ol"]);
    if (name === "dt" || name === "dd") shut(["dt", "dd"], ["dl"]);
    if (name === "td" || name === "th") shut(["td", "th"], ["tr", "table"]);
    if (name === "tr") shut(["tr"], ["table", "thead", "tbody", "tfoot"]);
    if (name === "thead" || name === "tbody" || name === "tfoot") shut(["thead", "tbody", "tfoot"], ["table"]);
  };

  while ((found = tag.exec(said)) !== null) {
    if (found.index > last) top().kids.push(decode(said.slice(last, found.index)));
    last = tag.lastIndex;
    const name = (found[1] || "").toLowerCase();
    if (!name) continue;                                   // a comment or a doctype
    if (found[0][1] === "/") { close(name); continue; }
    const at = {};
    const attrs = /([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
    let a;
    while ((a = attrs.exec(found[2] || "")) !== null) {
      at[a[1].toLowerCase()] = decode(a[2] ?? a[3] ?? a[4] ?? "");
    }
    implied(name);
    const node = { tag: name, at, kids: [] };
    top().kids.push(node);
    if (RAW.has(name)) {
      const end = said.toLowerCase().indexOf(`</${name}`, last);
      const inner = said.slice(last, end < 0 ? said.length : end);
      if (name === "style") styles.push(inner);
      node.kids.push(inner);
      if (end < 0) { last = said.length; break; }
      last = said.indexOf(">", end) + 1 || said.length;
      tag.lastIndex = last;
      continue;
    }
    if (!VOID.has(name) && !/\/>$/.test(found[0])) stack.push(node);
  }
  if (last < said.length) top().kids.push(decode(said.slice(last)));
  return { root, ...readStyle(styles.join("\n")) };
}

/**
 * **What the page's own style says that words have to carry**, outside any
 * screen-size rule (those only hold on some screens):
 *
 * - `hidden`: the classes it hides, each a list that must all be on an
 *   element. `.olweb .glance .init{display:none}` hides `.init`.
 * - `across`: how many pictures a grid holds across, by its classes
 *   (`.grid{grid-template-columns:repeat(3,1fr)}`), so a wall of twelve
 *   frames is four rows of three on the phone as on the portal.
 */
function readStyle(css) {
  let flat = "";
  let depth = 0;
  let inMedia = 0;
  const said = String(css).replace(/\/\*[\s\S]*?\*\//g, "");
  for (let i = 0; i < said.length; i += 1) {
    const c = said[i];
    if (c === "@" && depth === 0) {
      const brace = said.indexOf("{", i);
      const semi = said.indexOf(";", i);
      if (semi >= 0 && (brace < 0 || semi < brace)) { i = semi; continue; }
      inMedia = 1;
      depth = 1;
      i = brace < 0 ? said.length : brace;
      continue;
    }
    if (inMedia) {
      if (c === "{") depth += 1;
      else if (c === "}") { depth -= 1; if (depth === 0) inMedia = 0; }
      continue;
    }
    flat += c;
  }
  const hidden = [];
  const across = [];
  for (const rule of flat.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    const none = /display\s*:\s*none/i.test(rule[2]);
    const cols = /grid-template-columns\s*:\s*repeat\(\s*(\d+)/i.exec(rule[2]);
    if (!none && !cols) continue;
    for (const one of rule[1].split(",")) {
      const lastPart = one.trim().split(/[\s>+~]+/).pop() || "";
      if (!lastPart || /[:[#]/.test(lastPart)) continue;
      const classes = [...lastPart.matchAll(/\.([A-Za-z0-9_-]+)/g)].map((m) => m[1]);
      if (!classes.length) continue;
      if (none) hidden.push(classes);
      if (cols) across.push({ classes, n: Math.max(1, Math.min(Number(cols[1]), 6)) });
    }
  }
  return { hidden, across };
}

// ------------------------------------------------------------------ saying

const classesOf = (node) => String(node.at.class || "").split(/\s+/).filter(Boolean);

/** Whitespace collapsed; the line break kept as itself. */
const squeeze = (text) => text.replace(/[ \t\r\n\f\v ]+/g, " ");

/**
 * A line that would read as something else in Markdown (`# `, `- `, `1. `,
 * `> `, `|`, a rule, a picture) is guarded with a zero-width space, taken off
 * again once `pageFrom` has read the page.
 */
const GUARD = "​";
function guarded(line) {
  return /^(#|>|\||[-*+]\s|\d+[.)]\s|([-*_])\2{2,}|!\[|!video\[)/i.test(line) ? GUARD + line : line;
}

/** A label for a Markdown link or picture: no brackets to end it early. */
const label = (text) => text.replace(/\[/g, "(").replace(/\]/g, ")").trim();

/** A stored file's own name, from `pic/<name>`, `/f/<film>/pic/<name>` or a full address. */
function storedName(src) {
  const said = String(src || "").trim().split(/[?#]/)[0];
  const tail = said.split("/").pop() || "";
  return FILE_NAME.test(tail) && (said === tail || /(^|\/)(pic|docs|media)\/[^/]+$/.test(said)) ? tail : "";
}

export function markdownFromHtml(html) {
  return said(html).markdown;
}

/** The Markdown, and for each table in order whether its first row is a heading row. */
function said(html) {
  const { root, hidden, across } = parseHtml(html);
  const heads = [];
  const isHidden = (node) => {
    if (SKIP.has(node.tag)) return true;
    if ("hidden" in node.at) return true;
    if (/display\s*:\s*none/i.test(node.at.style || "")) return true;
    const mine = classesOf(node);
    return mine.length > 0 && hidden.some((need) => need.every((c) => mine.includes(c)));
  };
  const visibleKids = (node) => node.kids.filter((k) => typeof k === "string" || !isHidden(k));
  const isBlank = (k) => typeof k === "string" && !k.trim();

  // **Heading levels by rank**, not by tag: a page whose biggest heading is an
  // `h2` starts at the page's first level, and three is as deep as a page goes.
  const levels = new Set();
  (function look(node) {
    for (const k of visibleKids(node)) {
      if (typeof k === "string") continue;
      const h = /^h([1-6])$/.exec(k.tag);
      if (h) levels.add(Number(h[1]));
      look(k);
    }
  })(root);
  const rank = [...levels].sort((a, b) => a - b);
  const levelOf = (tag) => Math.min(rank.indexOf(Number(tag[1])) + 1, 3) || 1;

  const has = (node, test) => {
    for (const k of visibleKids(node)) {
      if (typeof k === "string") continue;
      if (test(k) || has(k, test)) return true;
    }
    return false;
  };
  const hasBlock = (node) => has(node, (k) => BLOCK.has(k.tag) || k.tag === "img");

  // ---- words on a line ------------------------------------------------------

  /**
   * The words of an element as one line (`\n` where a `<br>` was). Like
   * elements side by side are joined with ` · `; a word against a designed
   * piece of its own (`Scenes<span class="count">16</span>`) gets a space.
   */
  function words(node, linked = false) {
    let out = "";
    let before = null;
    let gap = false;
    let apart = false;
    for (const k of visibleKids(node)) {
      if (typeof k === "string") {
        if (!k.trim()) { if (k.length) gap = true; out += squeeze(k); continue; }
        const text = squeeze(k);
        // A piece set apart only by its design (`<b>01</b>FX6`,
        // `<span class="count">16</span>`) keeps a space from the word after it.
        if (apart && /[\p{L}\p{N}]$/u.test(out) && /^[\p{L}\p{N}]/u.test(text)) out += " ";
        out += text;
        before = null;
        apart = false;
        gap = false;
        continue;
      }
      if (k.tag === "br") { out = out.replace(/ +$/, "") + "\n"; before = null; continue; }
      if (k.tag === "img" || k.tag === "video" || k.tag === "iframe") continue;
      let said = k.tag === "a" && !linked ? linkWords(k) : words(k, linked || k.tag === "a");
      if (!said.trim() && !k.kids.length && classesOf(k).includes("on")) said = "●";
      const sig = `${k.tag}.${classesOf(k).join(".")}`;
      const designed = !EMPHASIS.has(k.tag) && k.tag !== "a";
      if (said.trim() && before === sig && designed) {
        out = out.replace(/\s+$/, "") + " · ";
        said = said.trimStart();
      } else if (said.trim() && (classesOf(k).length && designed || /^\d+$/.test(said.trim())) && /[\p{L}\p{N}]$/u.test(out) && /^[\p{L}\p{N}]/u.test(said)) {
        out += " ";
      }
      out += said;
      if (said.trim()) before = sig;
      apart = Boolean(said.trim()) && (designed && classesOf(k).length > 0 || /^\d+$/.test(said.trim()));
      gap = false;
    }
    void gap;
    return out;
  }

  /** A link as Markdown when its address can be kept; its words otherwise. */
  function linkWords(a) {
    const said = words(a, true).replace(/\n/g, " ").trim();
    const href = String(a.at.href || "").trim();
    if (!said) return "";
    if (/^https?:\/\//i.test(href)) return `[${label(said)}](${href.replace(/\s/g, "%20").replace(/\)/g, "%29")})`;
    // A stored file's card is named as the page saves it (`download="…"`),
    // else by its link's words.
    const file = storedName(href);
    if (file) return `[${label(String(a.at.download || "").trim() || said)}](${file})`;
    return said;
  }

  // ---- the page, block by block -----------------------------------------------

  const out = [];
  let held = "";                     // a short label waiting for its heading
  let level = 0;                     // the last heading's level, for a set's own
  const emit = (line, isHeading = false) => {
    if (held) {
      if (isHeading) {
        line = line.replace(/^(#+ )/, `$1${held} · `);
        held = "";
      } else {
        out.push(guarded(held), "");
        held = "";
      }
    }
    out.push(line, "");
  };
  const paragraphs = (text) => {
    for (const piece of text.split("\n")) {
      // **A link to a file held here is the file's card**, on a line of its
      // own (the shape `pageFrom` reads as one), the words either side kept
      // where they were.
      const parts = piece.split(/(\[[^\]]*\]\(\s*[0-9a-f]{32}\.[A-Za-z0-9]{1,8}\s*\))/);
      for (const part of parts) {
        const line = part.trim();
        if (line) emit(FILE_LINK.test(line) ? line : guarded(line));
      }
    }
  };
  const paragraphOrLabel = (text, mayLabel) => {
    const line = text.replace(/\n/g, " ").trim();
    if (!line) return;
    if (mayLabel && /^[\p{L}\p{N}]{1,4}$/u.test(line)) {
      if (held) { out.push(guarded(held), ""); }
      held = line;
      return;
    }
    paragraphs(text);
  };

  /** A picture's line: `![cap](name)`, or its address as a link when it is not kept here. */
  function picture(img, cap = "") {
    const src = img.at.src || img.at["data-src"] || "";
    const name = storedName(src);
    // A caption is what the page shows under the picture; `alt` is for a
    // reader that cannot see it, and is not drawn.
    const said = label(cap || "");
    if (name) return `![${said}](${name})`;
    if (/^https?:\/\//i.test(src)) return `![${said}](${src})`;   // pageFrom says it was dropped
    return "";
  }

  function clip(node, cap = "") {
    let src = node.at.src || "";
    if (!src && node.tag === "video") {
      const source = node.kids.find((k) => typeof k !== "string" && k.tag === "source");
      src = source ? source.at.src || "" : "";
    }
    const name = storedName(src);
    const target = name || (/^https?:\/\//i.test(src) ? src : "");
    if (!target) return "";
    const still = storedName(node.at.poster || "");
    const said = label(cap || (node.tag === "iframe" ? node.at.title || "" : node.at.title || ""));
    return `!video[${said === "Video" && node.tag === "iframe" ? "" : said}](${target}${still ? ` ${still}` : ""})`;
  }

  /** The pictures and clips in an element, each with its caption. */
  function media(node) {
    const found = [];
    const caption = (fig) => {
      const cap = visibleKids(fig).find((k) => typeof k !== "string" && k.tag === "figcaption");
      return cap ? words(cap).replace(/\n/g, " ").trim() : "";
    };
    (function look(n, cap) {
      for (const k of visibleKids(n)) {
        if (typeof k === "string") continue;
        if (k.tag === "img") found.push({ kind: "img", node: k, cap });
        else if (k.tag === "video" || k.tag === "iframe") found.push({ kind: "clip", node: k, cap });
        else look(k, k.tag === "figure" ? caption(k) : cap);
      }
    })(node, node.tag === "figure" ? caption(node) : "");
    return found;
  }

  /** Words outside the pictures (a figure's caption is the picture's). */
  const wordsBeside = (node) => {
    const strip = (n) => ({ ...n, kids: visibleKids(n).filter((k) => typeof k === "string" || k.tag !== "figcaption").map((k) => (typeof k === "string" ? k : strip(k))) });
    return words(strip(node)).trim();
  };

  /** How many across a grid of these classes holds: its own style's say, else three. */
  function acrossOf(node) {
    const mine = classesOf(node);
    let best = null;
    for (const one of across) {
      if (one.classes.every((c) => mine.includes(c)) && (!best || one.classes.length >= best.classes.length)) best = one;
    }
    return best ? best.n : 3;
  }

  /** Lines of pictures, `across` to a line, or a clip on its own, from a run of media. */
  function sayMedia(found, wide = 3) {
    let row = [];
    const flush = () => {
      // Four across is two and two rather than three and one.
      const step = row.length === 4 && wide === 3 ? 2 : wide;
      for (let i = 0; i < row.length; i += step) emit(row.slice(i, i + step).join(" "));
      row = [];
    };
    for (const one of found) {
      if (one.kind === "img") {
        const line = picture(one.node, one.cap);
        if (line) row.push(line);
      } else {
        flush();
        const line = clip(one.node, one.cap);
        if (line) emit(line);
      }
    }
    flush();
  }

  /**
   * **The portal's own picture tools, said in blocks.** A comparison
   * (`data-cmp`, the wipe `compare.js` makes) is its sets in turn, each under
   * its name, each frame captioned with the lens its picker shows. An aspect
   * ratio frame (`data-ratios`) says its native ratio and the ratios it
   * offers, as the rebuilt Camera Tests pages do.
   */
  function sayTool(node) {
    const figures = [];
    (function look(n) {
      for (const k of visibleKids(n)) {
        if (typeof k === "string") continue;
        if (k.tag === "figure" || (k.tag === "img" && k.at["data-set"] !== undefined)) figures.push(k);
        else look(k);
      }
    })(node);
    const capOf = (fig) => fig.at["data-lens"] || "";
    const wide = acrossOf(node);
    if (node.at["data-ratios"] !== undefined) {
      const name = node.at["data-native-name"] || "Native";
      const rows = [];
      if (node.at["data-native"]) rows.push(`| ${name} | ${node.at["data-native"]} |`);
      const ratios = String(node.at["data-ratios"]).split(/\s*,\s*/).filter(Boolean).join(" · ");
      if (ratios) rows.push(`| Ratios | ${ratios} |`);
      if (rows.length === 1) rows.unshift("| Ratios | |");
      if (rows.length) { heads.push(true); emit([rows[0], "| --- | --- |", ...rows.slice(1)].join("\n")); }
    }
    const sets = [];
    for (const fig of figures) {
      const set = fig.at["data-set"] || "";
      if (!sets.length || sets[sets.length - 1].name !== set) sets.push({ name: set, figs: [] });
      sets[sets.length - 1].figs.push(fig);
    }
    for (const one of sets) {
      if (one.name && sets.length > 1 || one.name && node.at["data-cmp"] !== undefined) {
        emit(`${"#".repeat(Math.min(level + 1, 3))} ${one.name}`, true);
      }
      sayMedia(one.figs.flatMap((fig) => media(fig).map((m) => ({ ...m, cap: capOf(fig) || m.cap }))), wide);
    }
  }

  /** Every child a picture (a figure, a link round a picture, a frame holding one): a row. */
  function isPictureRow(node) {
    const kids = visibleKids(node).filter((k) => !isBlank(k));
    if (kids.length < 2 || kids.some((k) => typeof k === "string")) return false;
    return kids.every((k) => {
      if (k.tag === "img") return true;
      const m = media(k);
      return m.length === 1 && m[0].kind === "img" && !wordsBeside(k);
    });
  }

  /**
   * A grid of like cards: two or more children of the same tag and class,
   * each a few short lines of words and nothing else.
   */
  function isCards(node) {
    const kids = visibleKids(node).filter((k) => !isBlank(k));
    if (kids.length < 2 || kids.some((k) => typeof k === "string")) return false;
    const sig = (k) => `${k.tag}.${classesOf(k).join(".")}`;
    if (!["div", "article", "section", "a", "li"].includes(kids[0].tag) || !classesOf(kids[0]).length) return false;
    return kids.every((k) => {
      if (sig(k) !== sig(kids[0])) return false;
      if (has(k, (n) => /^(h[1-6]|img|video|iframe|table|ul|ol)$/.test(n.tag))) return false;
      const lines = cardLines(k);
      return lines.length >= 2 && lines.every((l) => l.length <= 120);
    });
  }
  function cardLines(node) {
    const lines = [];
    const inline = [];
    const flush = () => { const said = inline.join("").replace(/\s+/g, " ").trim(); if (said) lines.push(said); inline.length = 0; };
    for (const k of visibleKids(node)) {
      if (typeof k === "string" || !BLOCK.has(k.tag)) {
        inline.push(typeof k === "string" ? squeeze(k) : words({ tag: "#", at: {}, kids: [k] }));
        continue;
      }
      flush();
      if (hasBlock(k)) lines.push(...cardLines(k));
      else { const said = words(k).replace(/\s+/g, " ").trim(); if (said) lines.push(said); }
    }
    flush();
    return lines;
  }

  function table(node) {
    const rows = [];
    const pictures = [];
    (function look(n) {
      for (const k of visibleKids(n)) {
        if (typeof k === "string") continue;
        if (k.tag === "tr") rows.push(k);
        else if (k.tag !== "table") look(k);
      }
    })(node);
    const cellsOf = (tr) => visibleKids(tr).filter((k) => typeof k !== "string" && (k.tag === "td" || k.tag === "th"));
    const grid = rows.map((tr) => cellsOf(tr).flatMap((cell) => {
      pictures.push(...media(cell));
      const said = words(cell).replace(/\s+/g, " ").trim().replace(/\|/g, "｜");
      const span = Math.max(1, Math.min(Number(cell.at.colspan) || 1, 20));
      return [said, ...Array(span - 1).fill("")];
    })).filter((r) => r.length);
    if (!grid.length) { sayMedia(pictures); return; }
    const width = Math.max(...grid.map((r) => r.length));
    const line = (r) => `| ${[...r, ...Array(width - r.length).fill("")].map((c) => c || " ").join(" | ")} |`;
    const caption = visibleKids(node).find((k) => typeof k !== "string" && k.tag === "caption");
    if (caption) paragraphs(words(caption).trim());
    const said = [line(grid[0]), `| ${Array(width).fill("---").join(" | ")} |`, ...grid.slice(1).map(line)];
    // pageFrom reads every table's first row as its head; a table that had
    // none is told so afterwards (`heads`).
    heads.push(rows[0] && (cellsOf(rows[0]).some((c) => c.tag === "th") || has(node, (k) => k.tag === "thead")));
    emit(said.join("\n"));
    sayMedia(pictures);
  }

  function list(node, depth, after) {
    let number = 0;
    for (const li of visibleKids(node)) {
      if (typeof li === "string" || li.tag !== "li") {
        if (typeof li !== "string") block(li);
        continue;
      }
      number += 1;
      const own = { ...li, kids: visibleKids(li).filter((k) => typeof k === "string" || !/^(ul|ol)$/.test(k.tag)) };
      after.push(...media(own));
      const said = (hasBlock(own) ? cardLines(own).join(" ") : words(own)).replace(/\s+/g, " ").trim();
      const mark = node.tag === "ol" ? `${number}.` : "-";
      out.push(`${"  ".repeat(depth)}${mark} ${said || "·"}`);
      for (const k of visibleKids(li)) {
        if (typeof k !== "string" && (k.tag === "ul" || k.tag === "ol")) list(k, depth + 1, after);
      }
    }
  }

  function block(node) {
    if (isHidden(node)) return;
    const t = node.tag;
    if (/^h[1-6]$/.test(t)) {
      const said = words(node).replace(/\s+/g, " ").trim();
      if (said) { level = levelOf(t); emit(`${"#".repeat(level)} ${said}`, true); }
      sayMedia(media(node));
      return;
    }
    if (t === "hr") { emit("---"); return; }
    if (t === "img") { const line = picture(node); if (line) emit(line); return; }
    if (t === "video" || t === "iframe") { const line = clip(node); if (line) emit(line); return; }
    if (t === "table") { table(node); return; }
    if (t === "ul" || t === "ol") {
      if (held) { out.push(guarded(held), ""); held = ""; }
      const after = [];
      list(node, 0, after);
      out.push("");
      sayMedia(after);
      return;
    }
    if (t === "figure" || t === "picture") {
      const found = media(node);
      const beside = wordsBeside(node);
      if (beside && !found.length) { paragraphs(beside); return; }
      sayMedia(found);
      if (beside && found.length) {
        // words in a figure that are not its caption: said after its pictures
        for (const k of visibleKids(node)) if (typeof k !== "string" && k.tag !== "figcaption" && !media(k).length) block(k);
      }
      return;
    }
    if (t === "blockquote" || t === "aside") {
      if (!has(node, (k) => /^(img|video|iframe|table|ul|ol|h[1-6])$/.test(k.tag))) {
        const lines = hasBlock(node) ? cardLines(node) : [words(node).replace(/\n/g, " ").trim()];
        for (const line of lines) if (line) emit(`> ${line}`);
        return;
      }
    }
    if (t === "p" || t === "pre" || t === "dt" || t === "dd" || t === "summary" || t === "figcaption" || t === "caption") {
      const said = t === "pre" ? (node.kids.filter((k) => typeof k === "string").join("")) : words(node);
      paragraphs(said);
      sayMedia(media(node));
      return;
    }
    // ---- a container ---------------------------------------------------------
    if (node.at["data-cmp"] !== undefined || node.at["data-ratios"] !== undefined) { sayTool(node); return; }
    if (isPictureRow(node)) { sayMedia(media(node), acrossOf(node)); return; }
    if (isCards(node)) {
      if (held) { out.push(guarded(held), ""); held = ""; }
      for (const card of visibleKids(node)) {
        if (typeof card === "string") continue;
        const lines = cardLines(card);
        const href = card.tag === "a" ? String(card.at.href || "") : "";
        const said = lines.join(" · ");
        out.push(`- ${/^https?:\/\//i.test(href) ? `[${label(said)}](${href})` : said}`);
      }
      out.push("");
      return;
    }
    if (!hasBlock(node)) {
      const said = t === "a" ? linkWords(node) : words(node);
      paragraphOrLabel(said, t !== "a");
      return;
    }
    // Mixed: runs of loose words become paragraphs, blocks are themselves.
    let loose = [];
    const flush = () => {
      if (!loose.length) return;
      const said = words({ tag: "#", at: {}, kids: loose });
      paragraphs(said);
      loose = [];
    };
    for (const k of visibleKids(node)) {
      if (typeof k === "string" || (!BLOCK.has(k.tag) && k.tag !== "img" && !hasBlock(k))) { loose.push(k); continue; }
      flush();
      block(k);
    }
    flush();
  }

  block(root);
  if (held) out.push(guarded(held), "");
  return { markdown: out.join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n", heads };
}

/** Takes the guard back off every run, caption and name in the tree. */
function unguard(nodes) {
  for (const node of nodes || []) {
    for (const run of node.r || []) if (typeof run.s === "string") run.s = run.s.replace(/​/g, "");
    if (typeof node.cap === "string") node.cap = node.cap.replace(/​/g, "");
    if (Array.isArray(node.c)) for (const cell of node.c) unguard([{ r: cell }]);
    unguard(node.k);
  }
  return nodes;
}

/**
 * **A designed page as the tree a written page is.** `{ tree, dropped,
 * markdown }`: `dropped` names anything `pageFrom` could not keep (a picture
 * that is not a file here), so a check can insist it is empty.
 */
export function treeFromHtml(html) {
  const { markdown, heads } = said(html);
  const { tree, dropped } = pageFrom(markdown);
  let at = 0;
  (function look(nodes) {
    for (const node of nodes || []) {
      if (node.t === "table") { if (heads[at] === false) node.head = false; at += 1; }
      look(node.k);
    }
  })(tree);
  return { tree: unguard(tree), dropped, markdown };
}
