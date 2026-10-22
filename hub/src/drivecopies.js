/**
 * **Always-updating Drive copies of a project's pictures** (stage 5 step 5,
 * his answer 24, 2026-10-14). The rules; the server's side (reading films,
 * the Drive calls, the switch and the clock) is `drivecopiesdoor.js`.
 *
 * Shot stills and storyboard frames, Studio's reference boards and the
 * portal's look boards live on the server, for speed. Each also gets a copy in
 * the project's Drive folder that follows it, the way the linked shot-list
 * spreadsheet already follows the film:
 *
 *   <project>/1-creative/shot-list/images/scene-<n>/<shot>-<k>.<ext>  a shot's pictures, by scene, named by number and letter
 *   <project>/1-creative/reference/<board>/<board>-<n>.<ext>   a board's pictures, by board
 *
 * **Where, by the filing rules** (`cinematography/.filing-rules.md`, which
 * win over code): "Shotlister saves into three of these by name: mood-board
 * pictures into `1-creative/reference/`, shot stills into
 * `1-creative/shot-list/`". So shot pictures sit in the shot-list folder, one
 * folder per scene (`scene-01/1a-1.jpg`, his call of 2026-10-14; a renumbered
 * scene moves its folder's copies, a shot moved to another scene moves its
 * own) — all of them under one `images/` folder (his ask, 2026-10-15), so
 * they do not overtake the folder his own files are in — and a board's in
 * `reference/<board>` — the very folder Studio's Sync with Drive switch has
 * used since 2026-08-30 (`driveFolder` on the board). An older project keeps
 * its own spine ("match the folders already there"): the homes are found by
 * name the way Studio finds a project's locations folder (`homeSteps`).
 *
 * - **A board goes to Drive unless switched off.** His answer 24: reference
 *   boards reach Drive by default. A Studio board whose Sync with Drive is
 *   explicitly off (`"0"`) stays off; never set reads as on. Portal look
 *   boards always go.
 * - **Pictures only.** Clips stay on the server (their size would stall the
 *   clock); a clip is counted, not copied.
 * - **Names are stable.** A picture is known by what it is a picture *of* —
 *   the shot's placement and the picture's use on it, the board and the card —
 *   never by its file name, so renumbering a shot or renaming a board moves
 *   and renames the copy already there instead of making a second one.
 * - **Never deletes.** A picture taken off a shot or a board leaves its copy
 *   where it is, listed as left. Only when a newer picture now wants its exact
 *   name is it renamed aside (`1a-1-removed.jpg`), so a folder never holds two
 *   files of the same name.
 *
 * **What Drive holds is remembered on the server** (a manifest per project,
 * `drivecopiesdoor.js`): each copy's Drive id, place, name and the content
 * hash it was made from. `plan` compares the pictures as they are now with it
 * and says exactly what to do; `carry` does it, one call at a time, through a
 * small Drive (`{list, get, mkdir, upload, replace, move}` — no trash, no
 * delete), updating a copy of the manifest after every call that worked. A
 * second run with nothing changed does nothing.
 */

export const HOMES = {
  shots: { path: ["1-creative", "shot-list"], words: ["shot-list", "shot list", "shotlist"] },
  refs: { path: ["1-creative", "reference"], words: ["reference"] },
};
/** The folder inside `shot-list/` that holds every scene's picture folder. */
export const IMAGES_FOLDER = "images";
/** What the copier called a shot-picture folder before `images/` (2026-10-15): moved, whole, under `images/`. */
const LEGACY_SHOT_SUB = /^(scene-|no-scene$)/;
export const MODES = ["off", "scratch", "live"];
export const SWITCH_KEY = "s/drivecopies.json";
export const DEFAULT_CAP = { files: 30, bytes: 50 * 1024 * 1024 };

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);
const PICTURE_EXT = /^(jpe?g|png|gif|webp|heic|heif|tiff?)$/;
const CLIP_EXT = /^(mp4|mov|m4v|webm)$/;
const MIME = { mp4: "video/mp4", m4v: "video/x-m4v", mov: "video/quicktime", jpg: "image/jpeg", jpeg: "image/jpeg", png: "image/png", gif: "image/gif", webp: "image/webp",
  heic: "image/heic", heif: "image/heif", tif: "image/tiff", tiff: "image/tiff" };
export const mimeOf = (ext) => MIME[String(ext).toLowerCase()] || "application/octet-stream";

// ── names ───────────────────────────────────────────────────────────────────

const ALNUM = /^[\p{L}\p{N}]$/u;

/** A folder or file stem by the filing rules: kebab-case, lower case. `1A` → `1a`, `12.3` → `12-3`. */
export function folderName(said) {
  let out = "";
  for (const c of String(said || "").toLowerCase()) out += ALNUM.test(c) ? c : "-";
  return out.replace(/-+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80);
}

/**
 * A scene's folder: `scene-<number>`, lower case, a leading number padded to
 * two digits so the folders sort in order (`scene-01` … `scene-12`,
 * `scene-04a`). A shot in no scene goes in `no-scene`.
 */
export function sceneFolder(number) {
  const n = folderName(number);
  if (!n) return "no-scene";
  const m = /^(\d+)(.*)$/.exec(n);
  return `scene-${m ? m[1].padStart(2, "0") + m[2] : n}`;
}

/**
 * **A trimmed clip's file name**, `<clip hash>_<in ms>_<out ms>.mp4` (`end` when the out point is
 * the clip's own end). Studio keeps a clip whole and remembers the in and out as numbers; the
 * trimmed file is made once (`hub/trimclips.py`, ffmpeg) and kept in the hub's `trims/` shelf under
 * this name, so a changed trim is a new name and the Drive copy is replaced in place.
 */
export function trimName(hash, start, end) {
  const h = String(hash || "").slice(0, 32);
  const ms = (x) => String(Math.max(0, Math.round(Number(x) * 1000)));
  return `${h}_${start == null ? "0" : ms(start)}_${end == null ? "end" : ms(end)}.mp4`;
}
export const TRIM_NAME = /^[0-9a-f]{32}_\d+_(\d+|end)\.mp4$/;
/** A clip's poster frame grabbed on a Mac when the clip came without one (`poster_<clip hash>.jpg`, on the same shelf). */
export const posterName = (hash) => `poster_${String(hash || "").slice(0, 32)}.jpg`;
export const POSTER_NAME = /^poster_[0-9a-f]{32}\.jpg$/;
const hasTrim = (m) => m && (m.trimStart != null || m.trimEnd != null);

/** The extension a picture is kept under, from its own file name: "" when it is not a picture. */
export function extOf(filename) {
  const e = String(filename || "").split(".").pop().toLowerCase().replace(/[^a-z0-9]/g, "").slice(0, 8);
  return e === String(filename || "").toLowerCase() ? "" : e;
}

const isClip = (m) => m && (m.kind === "video" || CLIP_EXT.test(extOf(m.filename)));
const isPicture = (m) => m && !isClip(m) && (m.kind === "image" || m.kind === "gif" || m.kind === "photo" || PICTURE_EXT.test(extOf(m.filename)));

// ── what the project holds ──────────────────────────────────────────────────

/**
 * Every picture that should have a copy, in a stable order:
 * `[{key, what, home, sub, name, hash, src, bytes, mime, label}]`, plus what
 * was passed over and why. Read only.
 *
 * - `view` is the engine's view of the film (`groups[].rows[]` with `number`,
 *   `placement` and `stills`; `boards[]` with `media`).
 * - `looks` are the portal's boards: `[{file, name, slug, cards: [{id, srcs:
 *   [bucket file name]}]}]`.
 * - `media` is what the film's bucket folder holds, `{<file name>: bytes}`:
 *   only a picture the server really has can be copied.
 * - `docs` the same for the portal's own pictures (`pic/…`).
 */
export function wantedOf({ view = {}, looks = [], media = {}, docs = {}, trims = {} } = {}) {
  const out = [];
  const passed = { clips: 0, unnumbered: 0, missing: 0, off_boards: [], trims_waiting: [], posters_waiting: [] };
  const byHash = new Map();
  for (const name of Object.keys(media)) {
    const stem = name.split(".")[0];
    if (!byHash.has(stem)) byHash.set(stem, []);
    byHash.get(stem).push(name);
  }
  /** The bucket file for a picture the engine names: its own extension first. */
  const fileFor = (m) => {
    const h = String(m.hash || "").slice(0, 32);
    if (!/^[0-9a-f]{32}$/.test(h)) return "";
    const want = `${h}.${extOf(m.filename) || "png"}`;
    if (want in media) return want;
    return (byHash.get(h) || []).find((n) => PICTURE_EXT.test(n.split(".").pop())) || "";
  };

  /**
   * **A clip's file, as Studio plays it** (his rule, 2026-10-15: video goes to Drive as the
   * trimmed clip and its picture). A clip with an in and out point is the trimmed file from the
   * hub's `trims/` shelf; until that is made it is listed in `passed.trims_waiting` and not
   * copied (never the whole clip in its place). A clip with no trim is the clip itself.
   */
  const clipSource = (m, label) => {
    const h = String(m.hash || "").slice(0, 32);
    if (!/^[0-9a-f]{32}$/.test(h)) return null;
    const whole = (byHash.get(h) || []).find((n) => CLIP_EXT.test(n.split(".").pop()));
    if (hasTrim(m)) {
      const name = trimName(h, m.trimStart, m.trimEnd);
      if (name in trims) return { src: `trim/${name}`, hash: name.replace(/\.mp4$/, ""), ext: "mp4", bytes: Number(trims[name]) || 0 };
      passed.trims_waiting.push({ name, media: whole || `${h}.mp4`, start: m.trimStart == null ? 0 : Number(m.trimStart), end: m.trimEnd == null ? null : Number(m.trimEnd), label: String(label || "") });
      return null;
    }
    if (!whole) { passed.missing += 1; return null; }
    return { src: `media/${whole}`, hash: h, ext: whole.split(".").pop(), bytes: Number(media[whole]) || 0 };
  };

  // Shots: one folder per scene (his call, 2026-10-14), each shot's pictures
  // named by its number and letter, in the shot's own order.
  const sceneNumber = new Map((Array.isArray(view.scenes) ? view.scenes : []).map((sc) => [String(sc.id), String(sc.number || "")]));
  const takenShot = new Map();
  for (const group of Array.isArray(view.groups) ? view.groups : []) {
    for (const row of Array.isArray(group.rows) ? group.rows : []) {
      const stills = (Array.isArray(row.stills) ? row.stills : []).filter((m) => m && m.hash);
      // **A clip on a shot is shown as its poster frame**, the picture Studio keeps beside
      // the clip (same name, `.jpg`); that frame is what the shot list draws for the shot,
      // so it is copied like any still. The clip itself stays on the server.
      const poster = (m) => {
        const h = String(m.hash || "").slice(0, 32);
        const f = `${h}.jpg`;
        return /^[0-9a-f]{32}$/.test(h) && f in media ? { ...m, kind: "image", filename: f, poster: true } : null;
      };
      passed.clips += stills.filter(isClip).length;
      const pictures = stills.map((m) => (isClip(m) ? poster(m) : m)).filter((m) => m && isPicture(m));
      // **The shot's Print Frame**, when the Mac has baked a current one: the board that
      // stands for it on paper (arrows and all), named `<shot>-print`.
      const baked = row.printFrame && !row.printFrame.stale && row.printFrame.baked && row.printFrame.baked.hash ? row.printFrame.baked : null;
      const bakedFile = baked ? fileFor({ hash: baked.hash, filename: `print.${baked.ext || "jpg"}` }) : "";
      const clipsHere = stills.filter(isClip);
      if (!pictures.length && !bakedFile && !clipsHere.length) continue;
      const base = folderName(row.number);
      if (!base) { passed.unnumbered += 1; continue; }
      const sceneId = String(row.sceneId || (sceneNumber.has(String(group.key)) ? group.key : ""));
      const sub = `${IMAGES_FOLDER}/${sceneFolder(sceneId ? sceneNumber.get(sceneId) : "")}`;
      // Two shots showing the same number (it happens mid-edit) each keep their own names.
      let shot = base;
      for (let k = 2; takenShot.has(`${sub}/${shot}`) && takenShot.get(`${sub}/${shot}`) !== row.placement; k++) shot = `${base}-${k}`;
      takenShot.set(`${sub}/${shot}`, row.placement);
      // **The Print Frame is the shot's picture** (his rule, 2026-10-15): `<shot>.jpg` is the
      // bake of its current Print Frame; a still that went into it is kept beside it as
      // `<shot>-source.jpg` (a clip's poster is not: the bake already shows it). A shot with no
      // current bake — none made, or the Mac has not baked the changed one yet — shows its lead
      // frame as `<shot>.jpg`, as it prints; the bake replaces it in place once the Mac makes it.
      const put = (key, name, m, file) => {
        const ext = file.split(".").pop();
        out.push({ key, what: "shot", home: "shots", sub, name: `${name}.${ext}`,
          hash: String(m.hash), src: `media/${file}`, bytes: Number(media[file]) || 0, mime: mimeOf(ext), label: String(row.number) });
      };
      const withFile = pictures.map((m) => ({ m, file: fileFor(m) }));
      passed.missing += withFile.filter((x) => !x.file).length;
      const have = withFile.filter((x) => x.file);
      if (bakedFile) {
        put(`shot:${row.placement}:print`, shot, baked, bakedFile);
        let k = 0;
        for (const { m, file } of have) {
          if (m.poster) continue;
          k += 1;
          put(`shot:${row.placement}:${m.ref}`, k === 1 ? `${shot}-source` : `${shot}-source-${k}`, m, file);
        }
      } else {
        have.forEach(({ m, file }, i) => put(`shot:${row.placement}:${m.ref}`, i === 0 ? shot : `${shot}-${i + 1}`, m, file));
      }
      // The clip itself, trimmed as Studio plays it, beside the picture: `<shot>.mp4`.
      let ck = 0;
      for (const m of clipsHere) {
        const c = clipSource(m, row.number);
        if (!c) continue;
        ck += 1;
        out.push({ key: `shot:${row.placement}:${m.ref}:clip`, what: "shot", home: "shots", sub, name: `${ck === 1 ? shot : `${shot}-clip-${ck}`}.${c.ext}`,
          hash: c.hash, src: c.src, bytes: c.bytes, mime: mimeOf(c.ext), label: String(row.number) });
      }
    }
  }

  // Studio's reference boards: on unless switched off.
  const refSubs = new Set();
  for (const b of Array.isArray(view.boards) ? view.boards : []) {
    if (String(b.syncWithDrive) === "0") { passed.off_boards.push(String(b.name || "")); continue; }
    const sub = folderName(String(b.driveFolder || "").split("/").pop()) || folderName(b.name) || "board";
    refSubs.add(sub);
    let n = 0, cn = 0;
    for (const m of Array.isArray(b.media) ? b.media : []) {
      if (isClip(m)) {
        passed.clips += 1;
        const c = clipSource(m, b.name);
        if (!c) continue;
        cn += 1;
        const base = `${sub}-clip-${cn}`;
        out.push({ key: `board:${b.id}:${m.ref}:clip`, what: "board", home: "refs", sub, name: `${base}.${c.ext}`, hash: c.hash, src: c.src, bytes: c.bytes, mime: mimeOf(c.ext), label: String(b.name || "") });
        const pf = `${String(m.hash || "").slice(0, 32)}.jpg`;
        const shelved = posterName(m.hash);
        if (!(pf in media) && shelved in trims) out.push({ key: `board:${b.id}:${m.ref}:clipposter`, what: "board", home: "refs", sub, name: `${base}-poster.jpg`, hash: shelved.replace(/\.jpg$/, ""), src: `trim/${shelved}`, bytes: Number(trims[shelved]) || 0, mime: "image/jpeg", label: String(b.name || "") });
        else if (!(pf in media)) passed.posters_waiting.push({ name: shelved, src: `media/${(byHash.get(String(m.hash || "").slice(0, 32)) || []).find((n) => CLIP_EXT.test(n.split(".").pop())) || `${String(m.hash || "").slice(0, 32)}.mp4`}`, label: String(b.name || "") });
        if (pf in media) out.push({ key: `board:${b.id}:${m.ref}:clipposter`, what: "board", home: "refs", sub, name: `${base}-poster.jpg`, hash: String(m.hash), src: `media/${pf}`, bytes: Number(media[pf]) || 0, mime: "image/jpeg", label: String(b.name || "") });
        continue;
      }
      if (!isPicture(m)) continue;
      const file = fileFor(m);
      if (!file) { passed.missing += 1; continue; }
      n += 1;
      const ext = file.split(".").pop();
      out.push({ key: `board:${b.id}:${m.ref}`, what: "board", home: "refs", sub, name: `${sub}-${n}.${ext}`,
        hash: String(m.hash), src: `media/${file}`, bytes: Number(media[file]) || 0, mime: mimeOf(ext), label: String(b.name || "") });
    }
  }

  // **Edit references** (the Edit Reference mod, 2026-10-17): each one's clip, as Studio plays
  // it, and its stills in `reference/edit/`, named by the edit reference — `car-cut.mp4` with
  // `car-cut-poster.jpg`, stills `car-cut-01.jpg`. A project with none files nothing new.
  const editSub = refSubs.has("edit") ? "edit-reference" : "edit";
  const takenEdit = new Set();
  for (const e of Array.isArray(view.editRefs) ? view.editRefs : []) {
    const stem = folderName(e.name) || "edit-reference";
    let base = stem;
    for (let k = 2; takenEdit.has(base); k++) base = `${stem}-${k}`;
    takenEdit.add(base);
    const label = String(e.name || "");
    let n = 0, cn = 0;
    for (const m of Array.isArray(e.media) ? e.media : []) {
      if (isClip(m)) {
        const c = clipSource(m, label);
        if (!c) continue;
        cn += 1;
        const name = cn === 1 ? base : `${base}-clip-${cn}`;
        out.push({ key: `edit:${e.id}:${m.ref}:clip`, what: "edit", home: "refs", sub: editSub, name: `${name}.${c.ext}`, hash: c.hash, src: c.src, bytes: c.bytes, mime: mimeOf(c.ext), label });
        const pf = `${String(m.hash || "").slice(0, 32)}.jpg`;
        if (pf in media) out.push({ key: `edit:${e.id}:${m.ref}:clipposter`, what: "edit", home: "refs", sub: editSub, name: `${name}-poster.jpg`, hash: String(m.hash), src: `media/${pf}`, bytes: Number(media[pf]) || 0, mime: "image/jpeg", label });
        continue;
      }
      if (!isPicture(m)) continue;
      const file = fileFor(m);
      if (!file) { passed.missing += 1; continue; }
      n += 1;
      const ext = file.split(".").pop();
      out.push({ key: `edit:${e.id}:${m.ref}`, what: "edit", home: "refs", sub: editSub, name: `${base}-${String(n).padStart(2, "0")}.${ext}`,
        hash: String(m.hash), src: `media/${file}`, bytes: Number(media[file]) || 0, mime: mimeOf(ext), label });
    }
  }

  // The portal's look boards: always; a name Studio already uses gets -portal.
  for (const look of looks) {
    let sub = folderName(look.slug || look.name) || "look-board";
    if (refSubs.has(sub)) sub = `${sub}-portal`;
    refSubs.add(sub);
    let n = 0, cn = 0;
    for (const card of look.cards || []) {
      // A clip on the board: the clip as the board plays it (whole: boards keep no in and out), and its poster.
      for (const cl of card.clips || []) {
        const [k1, f1] = String(cl.src || "").split("/");
        const heldC = k1 === "media" ? media : k1 === "pic" ? docs : null;
        if (!heldC || !(f1 in heldC) || !CLIP_EXT.test(String(f1).split(".").pop().toLowerCase())) continue;
        cn += 1;
        const base = `${sub}-clip-${cn}`, ext1 = f1.split(".").pop().toLowerCase();
        out.push({ key: `look:${look.file}:${card.id}:${f1.slice(0, 32)}:clip`, what: "look", home: "refs", sub, name: `${base}.${ext1}`,
          hash: f1.slice(0, 32), src: `${k1}/${f1}`, bytes: Number(heldC[f1]) || 0, mime: mimeOf(ext1), label: String(look.name || look.slug || "") });
        const [k2, f2] = String(cl.poster || "").split("/");
        const heldP = k2 === "media" ? media : k2 === "pic" ? docs : null;
        const shelvedL = posterName(f1);
        if (!(heldP && f2 in heldP && PICTURE_EXT.test(String(f2).split(".").pop().toLowerCase()))) {
          if (shelvedL in trims) out.push({ key: `look:${look.file}:${card.id}:${f1.slice(0, 32)}:clipposter`, what: "look", home: "refs", sub, name: `${base}-poster.jpg`,
            hash: shelvedL.replace(/\.jpg$/, ""), src: `trim/${shelvedL}`, bytes: Number(trims[shelvedL]) || 0, mime: "image/jpeg", label: String(look.name || look.slug || "") });
          else passed.posters_waiting.push({ name: shelvedL, src: `${k1}/${f1}`, label: String(look.name || look.slug || "") });
        } else {
          const e2 = f2.split(".").pop().toLowerCase();
          out.push({ key: `look:${look.file}:${card.id}:${f1.slice(0, 32)}:clipposter`, what: "look", home: "refs", sub, name: `${base}-poster.${e2}`,
            hash: f2.slice(0, 32), src: `${k2}/${f2}`, bytes: Number(heldP[f2]) || 0, mime: mimeOf(e2), label: String(look.name || look.slug || "") });
        }
      }
      for (const one of card.srcs || []) {
        const [kind0, file] = String(one).split("/");
        // A `pic/…` address may name a picture the film holds as media (a Dump Board card
        // made from a Studio picture); look in the portal's pictures, then in the media.
        let kind = kind0;
        if (kind === "pic" && !(file in docs) && file in media) kind = "media";
        const held = kind === "media" ? media : kind === "pic" ? docs : null;
        const ext = String(file || "").split(".").pop().toLowerCase();
        if (CLIP_EXT.test(ext)) { passed.clips += 1; continue; }
        if (!held || !PICTURE_EXT.test(ext)) continue;
        if (!(file in held)) { passed.missing += 1; continue; }
        n += 1;
        out.push({ key: `look:${look.file}:${card.id}:${file.slice(0, 32)}`, what: "look", home: "refs", sub, name: `${sub}-${n}.${ext}`,
          hash: file.slice(0, 32), src: `${kind}/${file}`, bytes: Number(held[file]) || 0, mime: mimeOf(ext), label: String(look.name || look.slug || "") });
      }
    }
  }
  // One copy per key (a card naming the same picture twice).
  const seen = new Set();
  return { wanted: out.filter((w) => (seen.has(w.key) ? false : (seen.add(w.key), true))), passed };
}

/** A look board's cards as their pictures: the bucket names (`media/…`, `pic/…`) each card shows. */
export function lookCards(board) {
  const gone = new Set(Array.isArray(board && board.gone) ? board.gone : []);
  const out = [];
  for (const c of Array.isArray(board && board.added) ? board.added : []) {
    if (!c || !c.id || gone.has(c.id)) continue;
    const srcs = [], clips = [];
    const addr = (s) => {
      const m = /(^|\/)(media|pic)\/([0-9a-f]{32}\.[a-z0-9]{2,5})$/i.exec(String(s || "").split("?")[0]);
      return m ? `${m[2]}/${m[3]}` : "";
    };
    const take = (s) => { const a = addr(s); if (a) srcs.push(a); };
    const clip = (src, poster) => { const a = addr(src); if (a) clips.push({ src: a, poster: addr(poster) }); };
    if (c.kind === "clip") { take(c.src); clip(c.src, c.poster); }        // counted as a clip; the clip and its poster are copied
    else {
      take(c.src);
      take(c.image);
      for (const f of Array.isArray(c.figs) ? c.figs : []) if (f) { if (f.clip) clip(f.src, f.poster); else take(f.src); }
    }
    if (srcs.length || clips.length) out.push({ id: String(c.id), srcs: [...new Set(srcs)], clips });
  }
  return out;
}

// ── the plan ────────────────────────────────────────────────────────────────

export function emptyManifest(root = "", mode = "") {
  return { v: 1, root, mode, homes: {}, subs: {}, items: {}, sig: "", at: null };
}

/** A copy's place, by its name without the extension: `7a-1.jpg` and `7a-1.png` are one name to a person. */
const stemOf = (name) => { const n = String(name); const dot = n.lastIndexOf("."); return dot > 0 ? n.slice(0, dot) : n; };
const where = (x) => `${x.home}/${x.sub}/${stemOf(x.name)}`.toLowerCase();
const removedName = (name, taken) => {
  const dot = name.lastIndexOf(".");
  const stem = dot > 0 ? name.slice(0, dot) : name, ext = dot > 0 ? name.slice(dot) : "";
  for (let k = 1; ; k++) {
    const n = `${stem}-removed${k > 1 ? `-${k}` : ""}`;
    if (!taken.has(n.toLowerCase())) return `${n}${ext}`;
  }
};

/**
 * What to do, in order: `{ops, same, stale, counts, bytes}`. Each op is one of
 *
 *   {op: "aside",  key, from}            a left copy renamed out of a wanted name's way
 *   {op: "movefolder", key, home, from, to, id}  a scene folder made before `images/`, moved there whole (its id kept)
 *   {op: "move",   key, from, to}        renumbered / board renamed: moved and renamed, not copied
 *   {op: "update", key, to, bytes}       same place, the picture changed
 *   {op: "create", key, to, bytes}       new
 *
 * `stale` lists the copies left behind (never removed). Nothing is read or written.
 */
export function plan(wanted, manifest) {
  const held0 = isObject(manifest && manifest.items) ? manifest.items : {};
  const subs = isObject(manifest && manifest.subs) ? manifest.subs : {};
  const ops = [], same = [], stale = [];
  // **Scene folders made before `images/`** are moved whole, ids kept: one
  // call per folder, and the pictures in them are already where they belong.
  const renamed = new Map();
  for (const [k, id] of Object.entries(subs)) {
    const m = /^shots\/(.+)$/.exec(k);
    if (!m || !id || !LEGACY_SHOT_SUB.test(m[1]) || subs[`shots/${IMAGES_FOLDER}/${m[1]}`]) continue;
    renamed.set(m[1], `${IMAGES_FOLDER}/${m[1]}`);
    ops.push({ op: "movefolder", key: k, home: "shots", from: m[1], to: `${IMAGES_FOLDER}/${m[1]}`, id });
  }
  const held = renamed.size
    ? Object.fromEntries(Object.entries(held0).map(([k, h]) => [k, h && h.home === "shots" && renamed.has(h.sub) ? { ...h, sub: renamed.get(h.sub) } : h]))
    : held0;
  const wantKeys = new Set(wanted.map((w) => w.key));
  const wantedAt = new Set(wanted.map(where));
  const takenNames = new Set([...Object.values(held).map(where), ...wantedAt]);
  for (const [key, h] of Object.entries(held)) {
    if (wantKeys.has(key)) continue;
    if (wantedAt.has(where(h))) {
      const name = removedName(h.name, new Set([...takenNames].filter((p) => p.startsWith(`${h.home}/${h.sub}/`.toLowerCase())).map((p) => p.split("/").pop())));
      takenNames.add(where({ ...h, name }));
      ops.push({ op: "aside", key, from: h, name });
      stale.push({ key, ...h, name });
    } else {
      stale.push({ key, ...h });
    }
  }
  for (const w of wanted) {
    const h = held[w.key];
    const to = { home: w.home, sub: w.sub, name: w.name, hash: w.hash, src: w.src, mime: w.mime, what: w.what, label: w.label };
    if (!h || !h.id) { ops.push({ op: "create", key: w.key, to, bytes: w.bytes }); continue; }
    const moved = h.home !== w.home || h.sub !== w.sub || h.name !== w.name;
    if (moved) ops.push({ op: "move", key: w.key, from: h, to });
    if (h.hash !== w.hash) ops.push({ op: "update", key: w.key, to, bytes: w.bytes });
    if (!moved && h.hash === w.hash) same.push(w.key);
  }
  const rank = { movefolder: -1, aside: 0, move: 1, update: 2, create: 3 };
  ops.sort((a, b) => rank[a.op] - rank[b.op]);
  const counts = { create: 0, update: 0, move: 0, aside: 0, movefolder: 0, same: same.length, stale: stale.length };
  let bytes = 0;
  for (const o of ops) {
    counts[o.op] += 1;
    if (o.op === "create" || o.op === "update") bytes += Number(o.bytes) || 0;
  }
  return { ops, same, stale, counts, bytes };
}

/** A plan as a person reads it: counts, bytes, and a few names of each kind. */
export function shownPlan(p, homes = {}, few = 6) {
  const at = (x) => `${(homes[x.home] && homes[x.home].path) || HOMES[x.home].path.join("/")}/${x.sub}/${x.name}`;
  const of = (op) => p.ops.filter((o) => o.op === op);
  return {
    counts: p.counts,
    bytes: p.bytes,
    create: of("create").slice(0, few).map((o) => at(o.to)),
    move: of("move").slice(0, few).map((o) => `${at(o.from)} → ${at(o.to)}`),
    update: of("update").slice(0, few).map((o) => at(o.to)),
    aside: of("aside").slice(0, few).map((o) => `${at(o.from)} → ${o.name}`),
    folders: of("movefolder").slice(0, few).map((o) => `${(homes[o.home] && homes[o.home].path) || HOMES[o.home].path.join("/")}/${o.from} → ${o.to}`),
    left: p.stale.slice(0, few).map((s) => at(s)),
  };
}

// ── the switch ──────────────────────────────────────────────────────────────

const DRIVE_ID = /^[A-Za-z0-9_-]{10,120}$/;
const PROJECT_ID = /^[0-9a-f]{32}$/;

/** `{mode, drivecopies_root, only, cap, at, by}` — off until set. */
export function settingsShape(v) {
  const o = isObject(v) ? v : {};
  const cap = isObject(o.cap) ? o.cap : {};
  return {
    mode: MODES.includes(o.mode) ? o.mode : "off",
    drivecopies_root: DRIVE_ID.test(String(o.drivecopies_root || "")) ? String(o.drivecopies_root) : "",
    only: (Array.isArray(o.only) ? o.only : []).map((x) => String(x).replace(/-/g, "").toLowerCase()).filter((x) => PROJECT_ID.test(x)),
    cap: {
      files: Number.isInteger(cap.files) && cap.files > 0 && cap.files <= 200 ? cap.files : DEFAULT_CAP.files,
      bytes: Number.isInteger(cap.bytes) && cap.bytes > 0 && cap.bytes <= 500 * 1024 * 1024 ? cap.bytes : DEFAULT_CAP.bytes,
    },
    at: o.at || null,
    by: o.by || null,
  };
}

/** A PUT's settings, or `{problem}`. Only what is said changes. */
export function changedSettings(current, said) {
  if (!isObject(said)) return { problem: "Settings are an object." };
  const next = { ...settingsShape(current) };
  if (said.mode !== undefined) {
    if (!MODES.includes(said.mode)) return { problem: "mode is off, scratch or live." };
    next.mode = said.mode;
  }
  if (said.drivecopies_root !== undefined) {
    const r = String(said.drivecopies_root || "");
    if (r && !DRIVE_ID.test(r)) return { problem: "drivecopies_root is a Drive folder's id." };
    next.drivecopies_root = r;
  }
  if (said.only !== undefined) {
    if (!Array.isArray(said.only)) return { problem: "only is a list of project IDs." };
    next.only = settingsShape({ only: said.only }).only;
  }
  if (said.cap !== undefined) next.cap = settingsShape({ cap: said.cap }).cap;
  next.at = new Date().toISOString();
  next.by = String(said.by || "").slice(0, 80);
  return next;
}

/** Whether a run may write, and where: `{ok, why, root}`; `root` is the scratch folder in scratch mode. */
export function readiness(settings, { signin = false } = {}) {
  const s = settingsShape(settings);
  if (s.mode === "off") return { ok: false, why: "the switch is off" };
  if (!signin) return { ok: false, why: "the server has no Google sign-in that can write" };
  if (s.mode === "scratch" && !s.drivecopies_root) return { ok: false, why: "scratch, with no scratch folder set (drivecopies_root)" };
  return { ok: true, why: "", root: s.mode === "scratch" ? s.drivecopies_root : "" };
}

// ── the run ─────────────────────────────────────────────────────────────────

const lower = (s) => String(s).toLowerCase();
const childFolder = (kids, test) => kids.filter((k) => k.folder && !k.name.startsWith(".")).find(test) || null;

/**
 * Find (or, with `make`, make) a home: the exact template path first
 * (`1-creative/shot-list`), else an older spine's folder by name — at the top
 * (`4-shot-list`) or inside the creative folder — as Studio walks a project's
 * logistics folder for its locations. `{id, path, made}` or null.
 */
export async function findHome(drive, rootId, home, { make = false } = {}) {
  const h = HOMES[home];
  const top = await drive.list(rootId);
  const creative = childFolder(top, (k) => lower(k.name) === h.path[0]) || childFolder(top, (k) => lower(k.name).includes("creative"));
  const has = (k) => h.words.some((w) => lower(k.name).includes(w));
  if (creative) {
    const inside = await drive.list(creative.id);
    const exact = childFolder(inside, (k) => lower(k.name) === h.path[1]) || childFolder(inside, has);
    if (exact) return { id: exact.id, path: `${creative.name}/${exact.name}`, made: [] };
  }
  const older = childFolder(top, has);
  if (older) return { id: older.id, path: older.name, made: [] };
  if (!make) return null;
  const made = [];
  let parent = creative;
  if (!parent) { parent = await drive.mkdir(rootId, h.path[0]); made.push(h.path[0]); }
  const it = await drive.mkdir(parent.id, h.path[1]);
  made.push(`${parent.name || h.path[0]}/${h.path[1]}`);
  return { id: it.id, path: `${parent.name || h.path[0]}/${h.path[1]}`, made };
}

/**
 * Carry out a plan through `drive`, at most `cap` files and bytes, stopping at
 * the first call Google refuses or fails. Answers `{manifest, done, failed,
 * left, made}`; `manifest` is a new object — the one passed in is never
 * changed — holding only what Drive is now known to hold, so a failed call
 * leaves its picture as it was, to be tried again.
 *
 * `bytesOf(src)` fetches a picture's bytes from the server's bucket.
 *
 * **A cut-off run loses nothing** (2026-10-15, the first live try on ZED):
 * - `save(manifest)` is awaited after every call that worked, so the server
 *   keeps what Drive holds as it goes, not only at the end;
 * - before a picture is uploaded, the target folder is looked at: a file with
 *   the exact target name that is the same picture (md5 when both sides give
 *   one, else the same size) is **adopted** into the manifest, not uploaded
 *   again; a same-named file that is a different picture has its bytes
 *   replaced, so a folder never holds two files of one name;
 * - `deadline` (a `clock()` time in ms) stops the run before it starts
 *   another call, leaving the rest (`left`, `timeUp`) for the next tick.
 *
 * `md5Of(bytes)` (hex) is optional; without it a match is by size.
 */
export async function carry(drive, p, manifest0, { rootId, bytesOf, cap = DEFAULT_CAP, now = () => new Date().toISOString(),
  save = null, deadline = 0, clock = () => Date.now(), md5Of = null }) {
  const manifest = JSON.parse(JSON.stringify(manifest0 || emptyManifest()));
  manifest.homes ||= {}; manifest.subs ||= {}; manifest.items ||= {};
  const done = [], made = [], adopted = [];
  let failed = null, files = 0, bytes = 0, left = 0, timeUp = false;
  const homeOf = async (home) => {
    const held = manifest.homes[home];
    if (held && held.id) {
      const there = await drive.get(held.id);
      if (there && there.folder && !there.trashed) return held;
      delete manifest.homes[home];
      for (const k of Object.keys(manifest.subs)) if (k.startsWith(`${home}/`)) delete manifest.subs[k];
    }
    const found = await findHome(drive, rootId, home, { make: true });
    made.push(...found.made);
    manifest.homes[home] = { id: found.id, path: found.path };
    return manifest.homes[home];
  };
  const folderKids = new Map();                       // folder id → what it holds, listed once per run
  const kidsOf = async (folderId) => {
    if (!folderKids.has(folderId)) folderKids.set(folderId, await drive.list(folderId));
    return folderKids.get(folderId);
  };
  /** Put a picture in a folder: adopt the same-named file already there, else upload. `{id, adopted}`. */
  const place = async (parent, to, body) => {
    const same = (await kidsOf(parent)).filter((x) => !x.folder && x.name === to.name);
    if (same.length) {
      const mine = md5Of ? await md5Of(body).catch(() => "") : "";
      const sameBytes = (x) => (mine && x.md5 ? String(x.md5).toLowerCase() === mine : x.size !== undefined && x.size !== null && Number(x.size) === body.length);
      const hit = same.find(sameBytes);
      if (hit) { adopted.push({ key: "", name: to.name }); return { id: hit.id, adopted: true }; }
      await drive.replace(same[0].id, to.mime, body);   // the app's own folder: the name follows the picture
      same[0].size = body.length; same[0].md5 = mine;
      return { id: same[0].id, adopted: false };
    }
    const got = await drive.upload(parent, to.name, to.mime, body);
    (await kidsOf(parent)).push({ id: got.id, name: to.name, folder: false, size: body.length, md5: "" });
    return { id: got.id, adopted: false };
  };
  /** A folder under a home, nested names (`images/scene-01`) one level at a time: found by name, else made. */
  const subOf = async (home, sub) => {
    const k = `${home}/${sub}`;
    if (manifest.subs[k]) return manifest.subs[k];
    const top = await homeOf(home);
    let parent = top.id, path = top.path, key = home;
    for (const seg of sub.split("/")) {
      key += `/${seg}`;
      if (manifest.subs[key]) { parent = manifest.subs[key]; path += `/${seg}`; continue; }
      const kids = await kidsOf(parent);
      const there = kids.find((x) => x.folder && lower(x.name) === lower(seg));
      let id;
      if (there) id = there.id;
      else {
        id = (await drive.mkdir(parent, seg)).id;
        made.push(`${path}/${seg}`);
        kids.push({ id, name: seg, folder: true });
        folderKids.set(id, []);
      }
      manifest.subs[key] = id;
      parent = id; path += `/${seg}`;
    }
    return parent;
  };
  for (const o of p.ops) {
    let adoptedNow = false;
    const big = o.op === "create" || o.op === "update" ? Number(o.bytes) || 0 : 0;
    if (files >= cap.files || (files > 0 && bytes + big > cap.bytes)) { left += 1; continue; }
    if (failed) { left += 1; continue; }
    if (deadline && clock() >= deadline) { timeUp = true; left += 1; continue; }
    try {
      // A copy somebody took off the Drive by hand (`gone`): a left one is
      // forgotten, a wanted one is made again.
      const gone = (e) => e && e.gone === true;
      if (o.op === "movefolder") {
        // A scene folder, whole, into `images/` — same folder, same id, same pictures.
        const fromKey = `${o.home}/${o.from}`;
        const folder = manifest.subs[fromKey];
        const into = await subOf(o.home, IMAGES_FOLDER);
        const top = await homeOf(o.home);
        delete manifest.subs[fromKey];
        try {
          await drive.move(folder, { from: top.id, to: into });
          manifest.subs[`${o.home}/${o.to}`] = folder;
          for (const h of Object.values(manifest.items)) if (h.home === o.home && h.sub === o.from) h.sub = o.to;
        } catch (e) {
          if (!gone(e)) { manifest.subs[fromKey] = folder; throw e; }
          // Taken off the Drive by hand: forgotten, and its pictures made again where they now belong.
          for (const [k, h] of Object.entries(manifest.items)) if (h.home === o.home && h.sub === o.from) delete manifest.items[k];
        }
      } else if (o.op === "aside") {
        try {
          await drive.move(o.from.id, { name: o.name });
          manifest.items[o.key] = { ...manifest.items[o.key], name: o.name, stale: true, at: now() };
        } catch (e) {
          if (!gone(e)) throw e;
          delete manifest.items[o.key];
        }
      } else if (o.op === "move") {
        const to = await subOf(o.to.home, o.to.sub);
        const fromFolder = o.from.parent || manifest.subs[`${o.from.home}/${o.from.sub}`] || "";
        try {
          await drive.move(o.from.id, { name: o.to.name, from: fromFolder !== to ? fromFolder : "", to: fromFolder !== to ? to : "" });
          const { stale, ...h } = manifest.items[o.key];
          manifest.items[o.key] = { ...h, home: o.to.home, sub: o.to.sub, name: o.to.name, parent: to, at: now() };
        } catch (e) {
          if (!gone(e)) throw e;
          // Made again where it now belongs, from the server's copy.
          const body = await bytesOf(o.to.src);
          if (!body) throw new Error(`the server no longer has ${o.to.src}`);
          const got = await place(to, o.to, body);
          manifest.items[o.key] = { id: got.id, home: o.to.home, sub: o.to.sub, name: o.to.name, parent: to, hash: o.to.hash,
            bytes: body.length, what: o.to.what, label: o.to.label, at: now() };
          if (got.adopted) adopted[adopted.length - 1].key = o.key; else bytes += body.length;
        }
      } else {
        const body = await bytesOf(o.to.src);
        if (!body) throw new Error(`the server no longer has ${o.to.src}`);
        const h = manifest.items[o.key];
        let replaced = false;
        if (o.op === "update" && h && h.id) {
          try {
            await drive.replace(h.id, o.to.mime, body);
            manifest.items[o.key] = { ...h, hash: o.to.hash, bytes: body.length, at: now() };
            replaced = true;
          } catch (e) {
            if (!gone(e)) throw e;
          }
        }
        if (replaced) {
          /* done */
        } else {
          const parent = await subOf(o.to.home, o.to.sub);
          const got = await place(parent, o.to, body);
          manifest.items[o.key] = { id: got.id, home: o.to.home, sub: o.to.sub, name: o.to.name, parent, hash: o.to.hash,
            bytes: body.length, what: o.to.what, label: o.to.label, at: now() };
          if (got.adopted) { adopted[adopted.length - 1].key = o.key; adoptedNow = true; }
        }
        if (!adoptedNow) bytes += body.length;
      }
      // An adopted file cost Google nothing: it is not counted against the cap.
      if (adoptedNow) adoptedNow = false; else files += 1;
      done.push({ op: o.op, key: o.key });
      // What Drive holds is kept as it goes, so a run cut off here loses nothing.
      if (save) await save(manifest);
    } catch (e) {
      failed = { op: o.op, key: o.key, why: String((e && e.message) || e).slice(0, 300) };
      left += 1;
    }
  }
  return { manifest, done, failed, left, made, files, bytes, adopted, timeUp };
}
