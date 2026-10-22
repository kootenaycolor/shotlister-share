/**
 * Words into a page.
 *
 * ## Why this exists
 *
 * A section of the record — the Visual Bible, an overheads list, a safety
 * briefing — is stored as a small tree at `p/<film>/pages/<slug>.json` and
 * drawn by `drawBlocks` in `pages.js`. Until now the only thing that could
 * write one was `refresh.py`, reading a page out of Notion. That is the right
 * road for anything he has written in Notion and the wrong one for everything
 * else: an agent that has just read a script, or a spec sheet, or his own
 * notes, had no way to put a page on the portal at all without him first
 * making a Notion page for it and waiting for a refresh.
 *
 * So this is the second road in. An agent writes Markdown — which every model
 * writes fluently and nobody has to be taught — and this turns it into exactly
 * the tree Notion's reader produces, so the two are indistinguishable by the
 * time a page is drawn.
 *
 * ## What it deliberately does not do
 *
 * **No bold, no italic, no colour.** The drawing half (`saidAs`) knows two
 * things: text, and text that is a link. That is not an oversight to be worked
 * around here — a tree carrying emphasis the page cannot draw would be a tree
 * that lies. Emphasis markers are therefore *removed*, not kept: `**a note**`
 * arrives as `a note`, never as `**a note**` sitting on the page with its
 * asterisks showing.
 *
 * **No pictures from elsewhere.** A picture on one of these pages is a file
 * this hub holds, addressed by its own contents, because `pictureUrl` builds
 * `<film>/pic/<name>` and there is nowhere in that address for somebody else's
 * server. An agent puts the bytes here first — `add_document` with `kind` set
 * to `picture` — and writes the name it gets back. Anything else is dropped and
 * *said to have been dropped*: a picture that silently does not appear is the
 * worst of the three outcomes.
 */

/** A stored file: content-addressed, exactly like every other picture here. */
const FILE_NAME = /^[0-9a-f]{32}\.[A-Za-z0-9]{1,8}$/;

/** A stored clip: the same kind of name, a moving picture's ending. */
const CLIP_NAME = /^[0-9a-f]{32}\.(mp4|mov|m4v|webm)$/i;

/**
 * **A clip on its own line** (his decision, 2026-10-06, Ref 1543: the
 * hand-made pages are rebuilt from blocks, with Video as a new one):
 *
 *     !video[The reel](https://livid.com/embed/…)
 *     !video[The trailer](a1b2….mp4 c3d4….jpg)
 *
 * The first word in the brackets is the clip (a file this hub holds, or a
 * Livid, YouTube or Vimeo address); a second, if there is one, is its still.
 */
const VIDEO_LINE = /^!video\[([^\]]*)\]\(\s*([^\s)]+)(?:\s+([^\s)]+))?\s*\)$/i;

/** A line that is one link to a file this hub holds, and nothing else. */
const FILE_LINE = /^\[([^\]]*)\]\(\s*([0-9a-f]{32}\.[A-Za-z0-9]{1,8})\s*\)$/;

/** A line that is pictures and the spaces between them, and nothing else. */
const PICTURES_ONLY = /^!\[[^\]]*\]\(\s*[^\s)]+\s*\)(\s+!\[[^\]]*\]\(\s*[^\s)]+\s*\))*$/;

/**
 * How much of a page we will take.
 *
 * A bible is genuinely long — his own is fifty blocks — so this is not tight.
 * It is here because a page is read into memory whole every time somebody
 * opens it, and because an agent in a loop is a thing that happens.
 */
export const MAX_BLOCKS = 1200;
export const MAX_PAGE = 512 * 1024;

/** Longest single run of text we will keep, before it is simply cut. */
const MOST = 4000;

/**
 * Markdown in, the tree `drawBlocks` draws out.
 *
 * Returns the tree and a short list of what was dropped, so the tool that
 * called this can say so rather than leaving an agent to wonder.
 */
export function pageFrom(markdown) {
  const said = String(markdown == null ? "" : markdown).replace(/\r\n?/g, "\n");
  const lines = said.split("\n");
  const dropped = [];
  const tree = [];

  let at = 0;
  let para = [];

  // **A paragraph is finished by what comes after it, not by itself.** Every
  // branch below that starts a new kind of block has to close the one being
  // gathered first, so this is one call rather than nine copies of two lines.
  const shutParagraph = () => {
    if (!para.length) return;
    push(tree, { t: "p", r: richFrom(para.join(" "), dropped) });
    para = [];
  };

  while (at < lines.length) {
    const raw = lines[at];
    const line = raw.replace(/\s+$/, "");
    const bare = line.trim();

    if (!bare) { shutParagraph(); at += 1; continue; }

    // ---- a rule across the page -------------------------------------------
    if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
      shutParagraph();
      push(tree, { t: "hr" });
      at += 1;
      continue;
    }

    // ---- a heading ---------------------------------------------------------
    // **Three levels and no more.** The page already carries the section's own
    // name as its `h1`, so a `#` here is the first heading *inside* the page,
    // and anything deeper than three has nothing to be drawn as.
    const head = /^(#{1,6})\s+(.*)$/.exec(bare);
    if (head) {
      shutParagraph();
      const level = Math.min(head[1].length, 3);
      push(tree, { t: `h${level}`, r: richFrom(head[2], dropped) });
      at += 1;
      continue;
    }

    // ---- pictures on a line ------------------------------------------------
    //
    // **One is a picture; two or more side by side are a comparison.** A visual
    // bible is laid out in rows — three references across, the thing being
    // argued — and a reader that could only stack them one under another turned
    // every comparison he had made into a column of unrelated stills. Notion's
    // reader has carried his columns since the beginning; this is the same
    // shape said in Markdown, which has no columns of its own:
    //
    //     ![](a1b2….jpg) ![](c3d4….jpg) ![](e5f6….jpg)
    //
    // A row of one is drawn as a picture rather than a row of one, so nothing
    // has to know the difference.
    if (PICTURES_ONLY.test(bare)) {
      shutParagraph();
      const found = [...bare.matchAll(/!\[([^\]]*)\]\(\s*([^\s)]+)\s*\)/g)];
      const kept = [];
      for (const one of found) {
        const src = one[2];
        if (FILE_NAME.test(src)) kept.push({ t: "img", src, cap: words(one[1], 300) });
        else dropped.push(`picture ${short(src)} — put the file here first with add_document (kind: picture) and write the name it gives back`);
      }
      if (kept.length === 1) push(tree, kept[0]);
      else if (kept.length > 1) {
        push(tree, { t: "columns", k: kept.map((one) => ({ t: "column", k: [one] })) });
      }
      at += 1;
      continue;
    }

    // ---- a clip ------------------------------------------------------------
    // The block the phone draws as a still with a play mark (`LookPage.swift`,
    // `clip`) and the portal as a player: `src` a stored clip, `url` an
    // address, `poster` its still, `cap` its words. Field names are the phone's.
    const clip = VIDEO_LINE.exec(bare);
    if (clip) {
      shutParagraph();
      const made = videoFrom(clip[2], clip[3], words(clip[1], 300), dropped);
      if (made) push(tree, made);
      at += 1;
      continue;
    }

    // ---- a file this hub holds, on a line of its own ----------------------
    // `[The trailer](a1b2….mp4)`: drawn as the same card a pinned document
    // gets, which opens or saves it. The spelling `markdownFrom` already
    // writes a file in, so a page with one now reads back as it was.
    const held = FILE_LINE.exec(bare);
    if (held) {
      shutParagraph();
      push(tree, { t: "file", name: words(held[1], 200) || held[2], src: held[2] });
      at += 1;
      continue;
    }

    // ---- a table -----------------------------------------------------------
    // Only when the second line is the row of dashes, so a paragraph that
    // happens to contain a pipe is still a paragraph.
    if (bare.startsWith("|") && isRule(lines[at + 1])) {
      shutParagraph();
      const rows = [];
      let cursor = at;
      while (cursor < lines.length && lines[cursor].trim().startsWith("|")) {
        if (!isRule(lines[cursor])) rows.push(cells(lines[cursor], dropped));
        cursor += 1;
      }
      if (rows.length) {
        push(tree, { t: "table", head: true, k: rows.map((c) => ({ t: "trow", c })) });
      }
      at = cursor;
      continue;
    }

    // ---- a quotation -------------------------------------------------------
    if (/^>\s?/.test(bare)) {
      shutParagraph();
      const gathered = [];
      while (at < lines.length && /^\s*>\s?/.test(lines[at]) && lines[at].trim()) {
        gathered.push(lines[at].replace(/^\s*>\s?/, ""));
        at += 1;
      }
      push(tree, { t: "quote", r: richFrom(gathered.join(" "), dropped) });
      continue;
    }

    // ---- a list ------------------------------------------------------------
    // **Indentation is the nesting, two spaces to a step**, which is what
    // every model writes and what every editor produces. A tab counts as one
    // step so a hand-typed list still nests.
    const item = /^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$/.exec(line);
    if (item) {
      shutParagraph();
      at = gatherList(lines, at, tree, dropped);
      continue;
    }

    para.push(bare);
    at += 1;
  }
  shutParagraph();

  return { tree, dropped };
}

/**
 * A clip's block, or nothing (and why, in `dropped`).
 *
 * **A stored clip or an http(s) address, and nothing else**, for the reason
 * `richFrom` gives for links. A still that is not a file here is left off and
 * said to be; the clip still plays without it.
 */
function videoFrom(target, still, cap, dropped) {
  const node = { t: "video" };
  if (CLIP_NAME.test(target)) node.src = target;
  else if (FILE_NAME.test(target)) {
    dropped.push(`video ${short(target)} — that is a picture, not a clip; write it as ![](${short(target)})`);
    return null;
  } else {
    const url = safeUrl(target);
    if (!url) {
      dropped.push(`video ${short(target)} — a clip here (add_document hands back its name) or an http or https address`);
      return null;
    }
    node.url = url;
  }
  if (still) {
    if (FILE_NAME.test(still) && !CLIP_NAME.test(still)) node.poster = still;
    else dropped.push(`video still ${short(still)} — put the picture here first with add_document (kind: picture)`);
  }
  if (cap) node.cap = cap;
  return node;
}

/**
 * **Where a clip's address plays in a page**, or "" when it only opens.
 *
 * Livid, YouTube and Vimeo, as their own players; a watch link is turned into
 * the player's address. The same three `pageHtmlOf` lets through in a
 * published page (`PLAYERS` in `films.js`), and nothing else is framed.
 */
export function playerOf(url) {
  let at;
  try { at = new URL(String(url || "")); } catch { return ""; }
  if (at.protocol !== "https:" && at.protocol !== "http:") return "";
  const host = at.hostname.replace(/^www\./, "");
  const id = (said) => (/^[A-Za-z0-9_-]{1,64}$/.test(said || "") ? said : "");
  const parts = at.pathname.split("/").filter(Boolean);
  if (host === "livid.com" && parts[0] === "embed" && id(parts[1])) return `https://livid.com/embed/${parts[1]}`;
  if (host === "youtu.be" && id(parts[0])) return `https://www.youtube-nocookie.com/embed/${parts[0]}`;
  if (host === "youtube.com" || host === "m.youtube.com" || host === "youtube-nocookie.com") {
    const v = parts[0] === "watch" ? at.searchParams.get("v") : (parts[0] === "embed" || parts[0] === "shorts") ? parts[1] : "";
    if (id(v)) return `https://www.youtube-nocookie.com/embed/${v}`;
  }
  if (host === "vimeo.com" && /^\d{1,12}$/.test(parts[0] || "")) return `https://player.vimeo.com/video/${parts[0]}`;
  if (host === "player.vimeo.com" && parts[0] === "video" && /^\d{1,12}$/.test(parts[1] || "")) return `https://player.vimeo.com/video/${parts[1]}`;
  return "";
}

/**
 * A run of list items, however deep they go.
 *
 * A deeper item becomes a child of the last shallower one, which is what
 * `drawBlocks` draws as a list inside a list. An item deeper than its
 * predecessor by more than one step is treated as one step deeper rather than
 * refused — a stray extra space is not worth losing a line over.
 */
function gatherList(lines, from, into, dropped) {
  const stack = [{ depth: -1, list: into }];
  let at = from;
  while (at < lines.length) {
    const line = lines[at].replace(/\s+$/, "");
    if (!line.trim()) {
      // A blank line inside a list ends it only if what follows is not another
      // item — a spaced-out list is still one list.
      const next = lines[at + 1];
      if (next === undefined || !/^(\s*)(?:[-*+]|\d+[.)])\s+/.test(next)) break;
      at += 1;
      continue;
    }
    const item = /^(\s*)(?:[-*+]|\d+[.)])\s+(.*)$/.exec(line);
    if (!item) break;
    const depth = Math.floor(item[1].replace(/\t/g, "  ").length / 2);
    while (stack.length > 1 && depth <= stack[stack.length - 1].depth) stack.pop();
    const parent = stack[stack.length - 1];
    const node = { t: "li", r: richFrom(item[2], dropped) };
    push(parent.list, node);
    node.k = [];
    stack.push({ depth, list: node.k });
    at += 1;
  }
  // An item that gathered no children carries no empty `k`, so the tree looks
  // like the one Notion's reader writes rather than merely behaving like it.
  prune(into);
  return at;
}

function prune(list) {
  for (const node of list || []) {
    if (Array.isArray(node.k)) {
      prune(node.k);
      if (!node.k.length) delete node.k;
    }
  }
}

/** Whether a line is a table's row of dashes. */
function isRule(line) {
  return typeof line === "string" && /^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/.test(line) && line.includes("-");
}

/** One table row, as the rich text of each of its cells. */
function cells(line, dropped) {
  return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => richFrom(c.trim(), dropped));
}

/**
 * A line of text, as the pieces the page draws: plain, or a link.
 *
 * **`http` and `https` only, and nothing else at all.** This text arrives from
 * an agent that has been reading somebody else's page, so a `javascript:`
 * address turning up in it is the ordinary shape of the attack rather than a
 * far-fetched one. A refused link keeps its words and loses its address.
 */
function richFrom(said, dropped) {
  const text = plain(said);
  const out = [];
  const link = /\[([^\]]*)\]\(\s*([^\s)]+)\s*\)/g;
  let last = 0;
  let found;
  while ((found = link.exec(text)) !== null) {
    if (found.index > last) out.push({ s: text.slice(last, found.index) });
    const url = safeUrl(found[2]);
    const label = found[1] || found[2];
    if (url) out.push({ s: label, u: url });
    else {
      out.push({ s: label });
      if (dropped) dropped.push(`link ${short(found[2])} — only http and https addresses are kept`);
    }
    last = found.index + found[0].length;
  }
  if (last < text.length) out.push({ s: text.slice(last) });
  return out.filter((bit) => bit.s !== "").map((bit) => ({ ...bit, s: bit.s.slice(0, MOST) }));
}

/**
 * The emphasis markers, taken off.
 *
 * See the head of this file: the page can draw text and links, so `**` and `_`
 * and backticks are noise that would otherwise be printed. Removed here rather
 * than at the door, so a heading and a table cell lose them too.
 */
function plain(said) {
  return String(said)
    .replace(/`{1,3}([^`]*)`{1,3}/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/__([^_]+)__/g, "$1")
    .replace(/(^|[\s(])\*([^*\n]+)\*(?=[\s.,;:!?)]|$)/g, "$1$2")
    .replace(/(^|[\s(])_([^_\n]+)_(?=[\s.,;:!?)]|$)/g, "$1$2")
    .replace(/\s+/g, " ")
    .trim();
}

function safeUrl(value) {
  const said = String(value || "").trim().slice(0, 1200);
  if (!said) return "";
  try {
    const url = new URL(said);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : "";
  } catch {
    return "";
  }
}

function words(value, cap) {
  return String(value == null ? "" : value).replace(/\s+/g, " ").trim().slice(0, cap);
}

function short(said) {
  return words(said, 60);
}

/** Nothing past the ceiling, and nothing empty. */
function push(list, node) {
  if (list.length >= MAX_BLOCKS) return;
  if ((node.t === "p" || node.t === "li" || node.t === "quote") && !(node.r || []).length) return;
  list.push(node);
}

/**
 * A name a URL can carry, out of a name a person reads.
 *
 * The same shape the router and `front.js` insist on, made here rather than
 * asked of the caller — an agent that has to invent a slug invents `Visual
 * Bible` half the time and then wonders why the page will not open.
 */
export function slugFrom(name) {
  const said = String(name || "")
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 60)
    .replace(/-+$/g, "");
  return /^[a-z0-9][a-z0-9-]*$/.test(said) ? said : "";
}

// ------------------------------------------------------------ and back again

/**
 * A page, back into the Markdown that would make it.
 *
 * ## Why this has to exist
 *
 * His decision, 2026-09-04: the film's page on the portal becomes the **source
 * of truth** for a visual bible's content — the words, which pictures, and
 * their order — with the deck editor on his Mac keeping only what print needs
 * (the arrangement, the template, the page size) and rendering a PDF from the
 * same source.
 *
 * That only works if a page can be *read back*. Until now this store was write
 * only: `set_page` wrote a tree, `pages` listed what existed, and nothing could
 * say what was on one. An agent asked to revise a bible had no way to see what
 * it was revising, and the deck builder had nothing to render.
 *
 * So this is `pageFrom` run backwards, and the pair is meant to round-trip:
 * Markdown in, tree stored, Markdown out, and writing that Markdown again
 * gives the same tree. A check holds it.
 *
 * ## What it cannot give back, and why that is honest
 *
 * A tree written by `refresh.py` out of Notion carries things this vocabulary
 * has no spelling for — a callout, a toggle, a file card. Those come back as
 * the nearest plain thing (a quotation, a heading and its contents, a link)
 * rather than being dropped or invented. **A round trip through here is
 * lossless for anything an agent wrote and lossy for some of what Notion
 * wrote**, which is the right way round: Notion's pages are owned by Notion and
 * are never written back from here.
 */
export function markdownFrom(tree) {
  return blocksOut(tree || [], 0).join("\n").replace(/\n{3,}/g, "\n\n").trim() + "\n";
}

function blocksOut(nodes, depth) {
  const out = [];
  for (const node of nodes || []) {
    if (!node || typeof node !== "object") continue;
    const said = textOut(node.r);
    const kids = node.k && node.k.length ? node.k : null;

    if (node.t === "h1") { out.push(`# ${said}`, ""); }
    else if (node.t === "h2") { out.push(`## ${said}`, ""); }
    else if (node.t === "h3") { out.push(`### ${said}`, ""); }
    else if (node.t === "p") { out.push(said, ""); }
    else if (node.t === "hr") { out.push("---", ""); }
    else if (node.t === "quote") { out.push(`> ${said}`, ""); }
    // **A callout is a quotation here.** There is no fence for one, and a
    // quotation is what it looks like on the page — closer than dropping it.
    else if (node.t === "callout") { out.push(`> ${said}`, ""); }
    else if (node.t === "li") {
      out.push(`${"  ".repeat(depth)}- ${said}`);
      if (kids) out.push(...blocksOut(kids, depth + 1));
      // **A list is closed by the thing after it.** Without this the quotation
      // or paragraph that follows sits hard against the last bullet, and
      // reading that back makes it part of the list.
      if (depth === 0 && !isItem(nodes[nodes.indexOf(node) + 1])) out.push("");
      continue;
    }
    else if (node.t === "img") { out.push(picture(node), ""); }
    else if (node.t === "video") {
      const target = node.src || node.url || "";
      if (target) out.push(`!video[${(node.cap || said || "").replace(/[\[\]]/g, "")}](${target}${node.poster ? ` ${node.poster}` : ""})`, "");
    }
    // A file he pinned inside a page: the words and where it goes, which is
    // all a link can carry.
    else if (node.t === "file") {
      const where = node.url || (node.src ? node.src : "");
      out.push(where ? `[${node.name || "File"}](${where})` : `${node.name || "File"}`, "");
    }
    else if (node.t === "table") { out.push(...tableOut(node), ""); }
    // **A toggle is its heading and then its contents.** Nothing on the page
    // is hidden behind a twist-down, so flattening it loses nothing a reader
    // would have seen.
    else if (node.t === "toggle") {
      if (said) out.push(`### ${said}`, "");
      if (kids) out.push(...blocksOut(kids, depth));
      continue;
    }
    // **Columns of pictures come back as a picture row**, which is the spelling
    // that made them — one line, several pictures, which `pageFrom` reads back
    // as columns again.
    else if (node.t === "columns") {
      const row = picturesIn(kids);
      if (row.length) out.push(row.join(" "), "");
      else if (kids) out.push(...blocksOut(kids, depth));
      continue;
    }
    else if (node.t === "column") { if (kids) out.push(...blocksOut(kids, depth)); continue; }
    else { if (said) out.push(said, ""); }

    if (kids && node.t !== "li") out.push(...blocksOut(kids, depth));
  }
  return out;
}

function isItem(node) {
  return Boolean(node) && typeof node === "object" && node.t === "li";
}

/** Every picture directly inside a set of columns, in order, or nothing. */
function picturesIn(columns) {
  const row = [];
  for (const col of columns || []) {
    const inside = col && col.t === "column" ? col.k || [] : [col];
    for (const one of inside) {
      if (!one || one.t !== "img") return [];
      row.push(picture(one));
    }
  }
  return row;
}

function picture(node) {
  return `![${(node.cap || "").replace(/[\[\]]/g, "")}](${node.src || ""})`;
}

function tableOut(node) {
  const rows = (node.k || []).filter((r) => r && r.t === "trow");
  if (!rows.length) return [];
  const line = (cells) => `| ${cells.map((c) => textOut(c).replace(/\|/g, "\\|")).join(" | ")} |`;
  const wide = Math.max(...rows.map((r) => (r.c || []).length));
  const out = [line(rows[0].c || []), `| ${Array(wide).fill("---").join(" | ")} |`];
  for (const r of rows.slice(1)) out.push(line(r.c || []));
  return out;
}

/**
 * Rich text back to a line.
 *
 * A link becomes `[words](address)` again. Nothing else is marked up, because
 * nothing else was ever kept — see the head of this file.
 */
function textOut(rich) {
  return (rich || [])
    .map((bit) => {
      const said = String((bit && bit.s) || "");
      return bit && bit.u ? `[${said.replace(/[\[\]]/g, "")}](${bit.u})` : said;
    })
    .join("")
    .trim();
}
