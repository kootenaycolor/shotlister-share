#!/usr/bin/env node
/**
 * **Drive copies of pictures, the rules on their own** (stage 5 step 5,
 * `src/drivecopies.js`). A film's view and its boards made up here, a Drive
 * held in memory, and the plan and the run checked against both: names, the
 * filing rules' homes (and an older project's spine), a second run doing
 * nothing, a renumbered shot moved rather than copied, a changed picture
 * replaced in place, a removed one left and set aside only when its name is
 * wanted, a new board picture, the cap, a Drive that fails leaving the
 * manifest as it was, a copy taken off the Drive by hand made again, and the
 * switch. The Drive here has no way to delete or trash, and the check says if
 * anything tried.
 *
 *     node hub/drivecopies.mjs
 */
import * as C from "./src/drivecopies.js";

let pass = 0, fail = 0;
const check = (what, good, why = "") => {
  if (good) pass += 1; else fail += 1;
  console.log(`  ${what.padEnd(86)} ${good ? "PASS" : `FAIL — ${String(why).slice(0, 900)}`}`);
};
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const H = (n) => n.toString(16).padStart(2, "0").repeat(32);        // a 64-hex hash
const short = (n) => H(n).slice(0, 32);

// ---- a Drive in memory ------------------------------------------------------
function memoryDrive({ failOn = null, onUpload = () => {} } = {}) {
  const items = new Map([["root", { id: "root", name: "proj", folder: true, parent: null }]]);
  let n = 0;
  const calls = { list: 0, get: 0, mkdir: 0, upload: 0, replace: 0, move: 0, forbidden: 0 };
  const maybeFail = (op) => {
    if (failOn && failOn(op)) throw new Error(`Google Drive answered 500 (${op})`);
  };
  const gone = () => Object.assign(new Error("not found"), { gone: true });
  const api = {
    items, calls,
    async list(parent) {
      calls.list += 1; maybeFail("list");
      return [...items.values()].filter((x) => x.parent === parent).map((x) => ({ ...x, size: x.bytes === undefined ? undefined : Number(x.bytes) }));
    },
    async get(id) { calls.get += 1; const x = items.get(id); return x ? { ...x, trashed: false } : null; },
    async mkdir(parent, name) {
      calls.mkdir += 1; maybeFail("mkdir");
      const id = `d${++n}`; items.set(id, { id, name, folder: true, parent }); return { id, name };
    },
    async upload(parent, name, mime, bytes) {
      calls.upload += 1; maybeFail("upload");
      if (!items.has(parent)) throw new Error("no parent");
      onUpload(); const id = `f${++n}`; items.set(id, { id, name, folder: false, parent, mime, bytes: String(bytes.length) }); return { id, name };
    },
    async replace(id, mime, bytes) {
      calls.replace += 1; maybeFail("replace");
      const x = items.get(id); if (!x) throw gone();
      x.bytes = String(bytes.length); x.mime = mime; return { id };
    },
    async move(id, { name, from, to }) {
      calls.move += 1; maybeFail("move");
      const x = items.get(id); if (!x) throw gone();
      if (from && to) { if (x.parent !== from) throw new Error("not in that folder"); x.parent = to; }
      if (name) x.name = name;
      return { id };
    },
  };
  // Nothing may take anything away.
  for (const bad of ["trash", "delete", "remove"]) Object.defineProperty(api, bad, { get() { calls.forbidden += 1; return undefined; } });
  return api;
}
const pathOf = (d, id) => {
  const parts = [];
  for (let x = d.items.get(id); x && x.id !== "root"; x = d.items.get(x.parent)) parts.unshift(x.name);
  return parts.join("/");
};
const files = (d) => [...d.items.values()].filter((x) => !x.folder).map((x) => `${pathOf(d, x.id)}=${x.bytes}`).sort();
const seedTemplate = (d) => {
  const mk = (parent, name) => { const id = `t${d.items.size}`; d.items.set(id, { id, name, folder: true, parent }); return id; };
  const c = mk("root", "1-creative");
  for (const s of ["previs", "reference", "shot-list", "storyboards"]) mk(c, s);
  mk("root", "2-logistics");
  return d;
};

// ---- a film made up ---------------------------------------------------------
const still = (n, ref, ext = "jpg", kind = "image") => ({ ref: `r${ref}`, hash: H(n), filename: `IMG_${n}.${ext}`, kind });
function film() {
  return {
    scenes: [{ id: "s1", number: "1" }, { id: "s2", number: "2" }, { id: "s3", number: "4A" }],
    groups: [
      { key: "s1", rows: [
        { placement: "p1", number: "1A", sceneId: "s1", stills: [still(1, 1), still(2, 2, "png")] },
        { placement: "p2", number: "1B", sceneId: "s1", stills: [still(3, 3), still(4, 4, "mov", "video")] },
        { placement: "p3", number: "1C", stills: [] },
      ] },
      { key: "s2", rows: [
        { placement: "p4", number: "2A", sceneId: "s2", stills: [still(5, 5)] },
        { placement: "p5", number: "", stills: [still(6, 6)] },
        { placement: "p6", number: "2A", sceneId: "s2", stills: [still(7, 7)] },          // same number mid-edit
        { placement: "p7", number: "2B", sceneId: "s2", stills: [still(99, 99)] },        // picture the server lacks
      ] },
    ],
    boards: [
      { id: "b1", name: "Night Exteriors", syncWithDrive: "", driveFolder: "", media: [still(10, 10), still(11, 11, "mp4", "video")] },
      { id: "b2", name: "Wardrobe", syncWithDrive: "0", driveFolder: "", media: [still(12, 12)] },
      { id: "b3", name: "Look Board", syncWithDrive: "1", driveFolder: "look-board", media: [still(13, 13)] },
    ],
  };
}
const MEDIA = {};
for (const [n, ext] of [[1, "jpg"], [2, "png"], [3, "jpg"], [4, "mov"], [5, "jpg"], [6, "jpg"], [7, "jpg"], [10, "jpg"], [11, "mp4"], [12, "jpg"], [13, "jpg"], [20, "jpg"], [21, "jpg"], [22, "jpg"], [23, "jpg"]]) {
  MEDIA[`${short(n)}.${ext}`] = 1000 + n;
}
const DOCS = { [`${short(30)}.jpg`]: 3030, [`${short(31)}.webp`]: 3131, [`${short(32)}.mp4`]: 9 };
const lookBoard = () => ({
  added: [
    { id: "c1", kind: "still", src: `pic/${short(30)}.jpg` },
    { id: "c2", kind: "ref", src: "https://example.com/x.jpg", figs: [{ src: `pic/${short(31)}.webp` }, { clip: true, src: `pic/${short(32)}.mp4` }] },
    { id: "c3", kind: "clip", src: `pic/${short(32)}.mp4`, poster: `pic/${short(30)}.jpg` },
    { id: "c4", kind: "note", text: "words" },
    { id: "c5", kind: "still", src: `media/${short(20)}.jpg` },
    { id: "c6", kind: "still", src: `pic/${short(30)}.jpg` },
  ],
  gone: ["c6"],
});
const bucket = (src) => {
  const [kind, file] = src.split("/");
  const held = kind === "media" ? MEDIA : DOCS;
  return file in held ? new Uint8Array(held[file]) : null;
};

// ---- names -------------------------------------------------------------------
console.log("names");
check("1A → 1a, 12.3 → 12-3, Night Exteriors → night-exteriors", C.folderName("1A") === "1a" && C.folderName("12.3") === "12-3" && C.folderName("Night  Exteriors!") === "night-exteriors");
check("extension from a file name; none for a bare name", C.extOf("IMG.JPG") === "jpg" && C.extOf("noext") === "" && C.extOf("a.b.heic") === "heic");

// ---- what is wanted ---------------------------------------------------------------
console.log("what is wanted");
const looks = [{ file: "look-board", name: "Look Board", slug: "look-board", cards: C.lookCards(lookBoard()) }];
let W = C.wantedOf({ view: film(), looks, media: MEDIA, docs: DOCS });
const at = (w) => `${w.home}/${w.sub}/${w.name}`;
const ws = W.wanted.map(at);
check("scene folders: 1 → scene-01, 12 → scene-12, 4A → scene-04a, none → no-scene", C.sceneFolder("1") === "scene-01" && C.sceneFolder("12") === "scene-12" && C.sceneFolder("4A") === "scene-04a" && C.sceneFolder("") === "no-scene" && C.sceneFolder("Interview 1") === "scene-interview-1");
check("shot pictures in their scene's folder, by number and letter, in order", eq(ws.slice(0, 3), ["shots/images/scene-01/1a.jpg", "shots/images/scene-01/1a-2.png", "shots/images/scene-01/1b.jpg"]), ws);
check("a clip on a shot with no trim is copied as itself, beside its picture", ws.includes("shots/images/scene-01/1b.mov") && W.passed.clips >= 2, JSON.stringify(W.passed));
{
  // The Print Frame is the shot's picture: its bake is <shot>.jpg, a still that went into it <shot>-source.jpg;
  // with no current bake the lead frame (a clip's poster) stands in as <shot>.jpg.
  const M2 = { [`${short(40)}.mp4`]: 5000, [`${short(40)}.jpg`]: 4000, [`${short(41)}.mp4`]: 5001, [`${short(42)}.jpg`]: 4200, [`${short(43)}.jpg`]: 4300,
    [`${short(44)}.jpg`]: 4400, [`${short(45)}.jpg`]: 4500, [`${short(46)}.mp4`]: 5, [`${short(46)}.jpg`]: 4600 };
  const bake = (n, stale = false) => ({ stale, baked: { hash: H(n), ext: "jpg", width: 2000, height: 1500, digest: "x" } });
  const v2 = { scenes: [{ id: "s1", number: "3" }], groups: [{ key: "s1", rows: [
    { placement: "q1", number: "3A", sceneId: "s1", stills: [still(40, 1, "mp4", "video")], printFrame: bake(42) },   // clip, current bake: the bake alone
    { placement: "q2", number: "3B", sceneId: "s1", stills: [still(41, 2, "mp4", "video")] },                         // clip, poster not on the server
    { placement: "q3", number: "3C", sceneId: "s1", stills: [still(44, 3)], printFrame: bake(43) },                   // photo + bake: bake and source
    { placement: "q4", number: "3D", sceneId: "s1", stills: [still(45, 4)] },                                          // photo, no print frame: itself
    { placement: "q5", number: "3E", sceneId: "s1", stills: [still(46, 5, "mp4", "video")], printFrame: bake(43, true) }, // clip, stale bake: poster stands in
  ] }] };
  const r2 = C.wantedOf({ view: v2, media: M2 }).wanted.map(at);
  check("a shot's current Print Frame bake is its picture, <shot>.jpg, and a clip's poster is not kept beside it", r2.includes("shots/images/scene-03/3a.jpg") && !r2.some((x) => x.includes("3a-")), r2);
  check("a photo that went into the bake is kept as <shot>-source", r2.includes("shots/images/scene-03/3c.jpg") && r2.includes("shots/images/scene-03/3c-source.jpg"), r2);
  check("a photo with no print frame is the shot's picture as it is", r2.includes("shots/images/scene-03/3d.jpg") && !r2.some((x) => x.includes("3d-")), r2);
  check("a stale bake is not used: the clip's poster stands in as <shot>.jpg", r2.includes("shots/images/scene-03/3e.jpg"), r2);
  check("a clip with no poster on the server and no bake gets no picture (3b.jpg), only its clip", !r2.includes("shots/images/scene-03/3b.jpg"), r2);
  check("pictures are fetched from the film's media", C.wantedOf({ view: v2, media: M2 }).wanted.filter((w) => w.mime.startsWith("image/")).every((w) => w.src.startsWith("media/") && w.src.endsWith(".jpg")));
}
{
  // Video goes to Drive as the trimmed clip beside the Print Frame; a trim not made yet is waited for, never the whole clip in its place.
  const clip = (n, ref, a, b) => ({ ref: `r${ref}`, hash: H(n), filename: `c${n}.mp4`, kind: "video", ...(a == null ? {} : { trimStart: a }), ...(b == null ? {} : { trimEnd: b }) });
  const M3 = { [`${short(50)}.mp4`]: 9000, [`${short(50)}.jpg`]: 500, [`${short(51)}.mp4`]: 8000, [`${short(51)}.jpg`]: 510, [`${short(52)}.mp4`]: 7000, [`${short(52)}.jpg`]: 520 };
  const v3 = { scenes: [{ id: "s1", number: "5" }], groups: [{ key: "s1", rows: [
    { placement: "t1", number: "5A", sceneId: "s1", stills: [clip(50, 1, 1.5, 6.25)] },   // trimmed
    { placement: "t2", number: "5B", sceneId: "s1", stills: [clip(51, 2)] },             // not trimmed
    { placement: "t3", number: "5C", sceneId: "s1", stills: [clip(52, 3, 2, null)] },    // only an in point
  ] }] };
  const tn = C.trimName(H(50), 1.5, 6.25);
  check("a trim's file name is the clip's hash and its in and out in milliseconds", tn === `${short(50)}_1500_6250.mp4` && C.TRIM_NAME.test(tn) && C.trimName(H(52), 2, null) === `${short(52)}_2000_end.mp4`, tn);
  const w0 = C.wantedOf({ view: v3, media: M3 });
  const n0 = w0.wanted.map(at);
  check("a trimmed clip not made yet is waited for, listed with its in and out, and not copied whole", w0.passed.trims_waiting.length === 2 && !n0.includes("shots/images/scene-05/5a.mp4") && w0.passed.trims_waiting[0].start === 1.5 && w0.passed.trims_waiting[0].end === 6.25 && w0.passed.trims_waiting[1].end === null, JSON.stringify(w0.passed.trims_waiting));
  check("an untrimmed clip is copied as it is", n0.includes("shots/images/scene-05/5b.mp4") && w0.wanted.find((w) => w.name === "5b.mp4").src === `media/${short(51)}.mp4`, n0);
  const T3 = { [tn]: 3333, [C.trimName(H(52), 2, null)]: 2222 };
  const w1 = C.wantedOf({ view: v3, media: M3, trims: T3 });
  const a1 = w1.wanted.find((w) => w.name === "5a.mp4");
  check("once the trimmed file is on the shelf it is the shot's clip (<shot>.mp4)", w1.passed.trims_waiting.length === 0 && a1 && a1.src === `trim/${tn}` && a1.bytes === 3333 && a1.mime === "video/mp4", JSON.stringify(a1));
  const w2 = C.wantedOf({ view: v3, media: M3, trims: { [C.trimName(H(50), 1.5, 6.5)]: 1 } });
  check("a changed trim is a different file: waited for again", w2.passed.trims_waiting.some((x) => x.name === tn));
  // boards
  const v4 = { scenes: [], groups: [], boards: [{ id: "b9", name: "Moves", syncWithDrive: "", driveFolder: "", media: [clip(50, 7, 1.5, 6.25), still(10, 8)] }] };
  const w3 = C.wantedOf({ view: v4, media: { ...M3, [`${short(10)}.jpg`]: 100 }, trims: T3 }).wanted.map(at);
  check("a Studio board's clip: the trimmed clip and its poster in the board's folder, pictures keep their numbers", eq(w3, ["refs/moves/moves-clip-1.mp4", "refs/moves/moves-clip-1-poster.jpg", "refs/moves/moves-1.jpg"]), w3);
  const lk = C.lookCards({ added: [{ id: "k1", kind: "clip", src: `pic/${short(60)}.mp4`, poster: `pic/${short(61)}.jpg` }, { id: "k2", kind: "still", src: `pic/${short(61)}.jpg` }], gone: [] });
  check("lookCards carries a clip card's clip and poster", eq(lk[0].clips, [{ src: `pic/${short(60)}.mp4`, poster: `pic/${short(61)}.jpg` }]) && lk[1].clips.length === 0, JSON.stringify(lk));
  const w4 = C.wantedOf({ view: {}, looks: [{ file: "lb", name: "LB", slug: "lb", cards: lk }], docs: { [`${short(60)}.mp4`]: 4000, [`${short(61)}.jpg`]: 300 } }).wanted.map(at);
  check("a look board's clip and its poster are copied; its pictures keep their numbers", eq(w4, ["refs/lb/lb-clip-1.mp4", "refs/lb/lb-clip-1-poster.jpg", "refs/lb/lb-1.jpg"]), w4);
  // a clip that came with no poster: its first frame is grabbed on a Mac and shelved as poster_<hash>.jpg
  const lk2 = C.lookCards({ added: [{ id: "k9", kind: "clip", src: `pic/${short(62)}.mov` }], gone: [] });
  const w5 = C.wantedOf({ view: {}, looks: [{ file: "lb", name: "LB", slug: "lb", cards: lk2 }], docs: { [`${short(62)}.mov`]: 4000 } });
  check("a look clip with no poster owes one, and is copied without it meanwhile", eq(w5.wanted.map(at), ["refs/lb/lb-clip-1.mov"]) && eq(w5.passed.posters_waiting.map((x) => [x.name, x.src]), [[C.posterName(short(62)), `pic/${short(62)}.mov`]]), JSON.stringify(w5.passed));
  const w6 = C.wantedOf({ view: {}, looks: [{ file: "lb", name: "LB", slug: "lb", cards: lk2 }], docs: { [`${short(62)}.mov`]: 4000 }, trims: { [C.posterName(short(62))]: 321 } });
  check("once shelved, the grabbed frame is the clip's poster", eq(w6.wanted.map(at), ["refs/lb/lb-clip-1.mov", "refs/lb/lb-clip-1-poster.jpg"]) && w6.passed.posters_waiting.length === 0 && w6.wanted[1].src === `trim/${C.posterName(short(62))}`);
}
check("an unnumbered shot is passed over and said", W.passed.unnumbered === 1 && !ws.some((x) => x.includes(short(6))));
check("two shots showing one number each keep their names (2a, 2a-2)", ws.includes("shots/images/scene-02/2a.jpg") && ws.includes("shots/images/scene-02/2a-2.jpg"), ws);
check("a picture the server does not have is passed over", W.passed.missing === 1 && !ws.some((x) => x.includes("/2b-")));
check("a board never switched goes to Drive (his answer 24)", ws.includes("refs/night-exteriors/night-exteriors-1.jpg"));
check("a board switched off stays off", !ws.some((x) => x.includes("wardrobe")) && eq(W.passed.off_boards, ["Wardrobe"]));
check("a board keeps the folder Studio named for it", ws.includes("refs/look-board/look-board-1.jpg"));
check("a look board whose name Studio already uses gets -portal", ws.includes("refs/look-board-portal/look-board-portal-1.jpg"), ws);
check("look board: stills and figures, not clips, not cut cards, media and pic both",
  eq(W.wanted.filter((w) => w.what === "look" && !w.name.includes("-clip-")).map((w) => w.src), [`pic/${short(30)}.jpg`, `pic/${short(31)}.webp`, `media/${short(20)}.jpg`]),
  JSON.stringify(W.wanted.filter((w) => w.what === "look").map((w) => w.src)));
{
  // A Dump Board card says pic/… but the picture is the film's media (not in the portal's docs).
  const m = { ...MEDIA, [`${short(40)}.jpg`]: 4040 };
  const lk = [{ file: "dump", name: "Dump", slug: "dump", cards: [{ id: "d1", srcs: [`pic/${short(40)}.jpg`, `pic/${short(30)}.jpg`, `pic/${short(41)}.jpg`] }] }];
  const got = C.wantedOf({ view: {}, looks: lk, media: m, docs: DOCS });
  check("a pic/ card whose file is the film's media is found there and fetched from media",
    eq(got.wanted.map((w) => w.src), [`media/${short(40)}.jpg`, `pic/${short(30)}.jpg`]) && got.passed.missing === 1 && got.wanted[0].bytes === 4040,
    JSON.stringify(got));
}
check("each picture carries its bytes and kind", W.wanted[1].bytes === 1002 && W.wanted[1].mime === "image/png");
check("keys say what each is a picture of", W.wanted[0].key === "shot:p1:r1" && W.wanted.find((w) => w.what === "board").key === "board:b1:r10");

// ---- the first run ------------------------------------------------------------------
console.log("the first run");
let P = C.plan(W.wanted, C.emptyManifest("root", "live"));
check("an empty manifest: everything is a create", P.counts.create === W.wanted.length && P.ops.every((o) => o.op === "create"), JSON.stringify(P.counts));
check("bytes are the pictures' sizes", P.bytes === W.wanted.reduce((t, w) => t + w.bytes, 0));
let d = seedTemplate(memoryDrive());
let run = await C.carry(d, P, C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket });
check("all made, nothing failed, nothing left", run.done.length === W.wanted.length && !run.failed && run.left === 0, JSON.stringify(run.failed));
check("shot pictures land in 1-creative/shot-list/images/scene-<n>/", files(d).includes("1-creative/shot-list/images/scene-01/1a-2.png=1002"), files(d).join("\n"));
check("board pictures land in 1-creative/reference/<board>/", files(d).some((f) => f.startsWith("1-creative/reference/night-exteriors/night-exteriors-1.jpg=")));
check("the template's folders were used, not made again", run.made.every((m) => !/^1-creative(\/(shot-list|reference))?$/.test(m)) && d.calls.mkdir === run.made.length, run.made);
check("nothing tried to delete or trash", d.calls.forbidden === 0);
let M = run.manifest;
const n1 = files(d).length;

console.log("a second run");
P = C.plan(W.wanted, M);
check("nothing changed: nothing to do", P.ops.length === 0 && P.counts.same === W.wanted.length, JSON.stringify(P.counts));
const calls0 = { ...d.calls };
run = await C.carry(d, P, M, { rootId: "root", bytesOf: bucket });
check("and the run writes nothing", eq(files(d).length, n1) && d.calls.upload === calls0.upload && d.calls.mkdir === calls0.mkdir && d.calls.move === calls0.move && eq(run.manifest.items, M.items));

// ---- renumber ----------------------------------------------------------------------
console.log("a scene renumbered, a shot moved to another scene");
const renum = film();
renum.scenes[0].number = "7";
renum.groups[0].rows[0].number = "7A";
renum.groups[0].rows[1].number = "7B";
W = C.wantedOf({ view: renum, looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, M);
check("scene 1 → 7: four moves (three pictures and the clip), no creates", P.counts.move === 4 && P.counts.create === 0 && P.counts.update === 0, JSON.stringify(P.counts));
run = await C.carry(d, P, M, { rootId: "root", bytesOf: bucket });
check("the copies moved to scene-07 and were renamed, not duplicated", files(d).length === n1 && files(d).includes("1-creative/shot-list/images/scene-07/7a-2.png=1002") && files(d).includes("1-creative/shot-list/images/scene-07/7b.jpg=1003") && !files(d).some((f) => f.includes("/scene-01/")), files(d).join("\n"));
check("the same Drive file, by id", run.manifest.items["shot:p1:r2"].id === M.items["shot:p1:r2"].id);
check("the old folder is left (never removed)", [...d.items.values()].some((x) => x.folder && x.name === "scene-01"));
M = run.manifest;
check("then nothing to do", C.plan(W.wanted, M).ops.length === 0);
const moved = JSON.parse(JSON.stringify(renum));
moved.groups[0].rows[1].sceneId = "s3";                                     // 7B moved to scene 4A
moved.groups[0].rows[1].number = "4AA";
W = C.wantedOf({ view: moved, looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, M);
run = await C.carry(d, P, M, { rootId: "root", bytesOf: bucket });
check("a shot moved to another scene moves its files (picture and clip) to that scene's folder", P.counts.move === 2 && files(d).includes("1-creative/shot-list/images/scene-04a/4aa.jpg=1003") && files(d).length === n1, files(d).join("\n"));
M = run.manifest;
check("then nothing to do", C.plan(W.wanted, M).ops.length === 0);
// back where it was, for what follows
W = C.wantedOf({ view: renum, looks, media: MEDIA, docs: DOCS });
M = (await C.carry(d, C.plan(W.wanted, M), M, { rootId: "root", bytesOf: bucket })).manifest;

// ---- a picture changed in place, a board renamed, a new board picture -----------------
console.log("changes");
const changed = JSON.parse(JSON.stringify(renum));
changed.groups[0].rows[1].stills[0].hash = H(21);                        // 1B's picture replaced, same use
changed.boards[0].name = "Night Exteriors Ext";                            // board renamed
changed.boards[0].media.push(still(22, 22));                               // a new picture on it
W = C.wantedOf({ view: changed, looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, M);
check("one update, two board moves (picture and clip), one create", P.counts.update === 1 && P.counts.move === 2 && P.counts.create === 1, JSON.stringify(P.counts));
const before1b = M.items["shot:p2:r3"].id;
run = await C.carry(d, P, M, { rootId: "root", bytesOf: bucket });
check("1B's copy holds the new picture under the same id and name",
  d.items.get(before1b).bytes === "1021" && pathOf(d, before1b) === "1-creative/shot-list/images/scene-07/7b.jpg", pathOf(d, before1b));
check("the board's folder follows its name", files(d).some((f) => f.startsWith("1-creative/reference/night-exteriors-ext/night-exteriors-ext-1.jpg")));
check("the new board picture is made beside it", files(d).some((f) => f.startsWith("1-creative/reference/night-exteriors-ext/night-exteriors-ext-2.jpg=1022")), files(d).join("\n"));
M = run.manifest;
check("then nothing to do", C.plan(W.wanted, M).ops.length === 0);

// ---- removed pictures -------------------------------------------------------------------
console.log("a picture taken off");
const removed = JSON.parse(JSON.stringify(changed));
removed.groups[0].rows[0].stills.shift();                                  // 7A loses its first picture
W = C.wantedOf({ view: removed, looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, M);
check("the gone one is set aside (its name is wanted), the other moves into 7a",
  P.counts.aside === 1 && P.counts.move === 1 && P.counts.stale === 1 && P.ops[0].op === "aside", JSON.stringify(P.counts));
const goneId = M.items["shot:p1:r1"].id;
run = await C.carry(d, P, M, { rootId: "root", bytesOf: bucket });
check("left on the Drive as 7a-removed.jpg, never deleted", d.items.has(goneId) && d.items.get(goneId).name === "7a-removed.jpg");
check("one file called 7a in the folder", [...d.items.values()].filter((x) => x.name === "7a.png" || x.name === "7a.jpg").length === 1);
M = run.manifest;
P = C.plan(W.wanted, M);
check("then nothing to do, and the left copy is listed", P.ops.length === 0 && P.stale.length === 1 && P.stale[0].name === "7a-removed.jpg");
const removed2 = JSON.parse(JSON.stringify(removed));
removed2.boards[0].media.pop();                                            // last board picture off: name not wanted by anyone
W = C.wantedOf({ view: removed2, looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, M);
check("a removed picture whose name nobody wants is only listed", P.ops.length === 0 && P.stale.length === 2, JSON.stringify(P.counts));
check("shown plan names what is left", C.shownPlan(P).left.some((x) => x.endsWith("night-exteriors-ext-2.jpg")));

// ---- the cap ------------------------------------------------------------------------
console.log("the cap");
const d2 = seedTemplate(memoryDrive());
W = C.wantedOf({ view: film(), looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, C.emptyManifest());
run = await C.carry(d2, P, C.emptyManifest(), { rootId: "root", bytesOf: bucket, cap: { files: 4, bytes: 1e9 } });
check("four files, the rest left for the next run", run.files === 4 && run.left === P.ops.length - 4 && files(d2).length === 4);
run = await C.carry(d2, C.plan(W.wanted, run.manifest), run.manifest, { rootId: "root", bytesOf: bucket, cap: { files: 100, bytes: 1e9 } });
check("the next run finishes, with no file made twice", files(d2).length === W.wanted.length && run.left === 0);
const d3 = seedTemplate(memoryDrive());
run = await C.carry(d3, P, C.emptyManifest(), { rootId: "root", bytesOf: bucket, cap: { files: 100, bytes: 2500 } });
check("a byte cap stops before going over", run.bytes <= 2500 && run.left > 0, `${run.bytes} ${run.files}`);

// ---- a cut-off run, resumed ---------------------------------------------------------
console.log("a run cut off, then resumed");
W = C.wantedOf({ view: film(), looks, media: MEDIA, docs: DOCS });
P = C.plan(W.wanted, C.emptyManifest("root", "live"));
const dc = seedTemplate(memoryDrive());
let saved = null, nsaves = 0;
let nup = 0;
const cut = Object.assign(Object.create(Object.getPrototypeOf(dc)), dc, {
  upload: async (...a) => { if (++nup > 5) throw new Error("the platform stopped the run"); return dc.upload(...a); },
});
await C.carry(cut, P, C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket, save: async (m) => { nsaves += 1; saved = JSON.parse(JSON.stringify(m)); } });
// The returned manifest is thrown away, as when a run is cut off: only what was saved remains.
check("the manifest was saved after every file, not once at the end", nsaves === 5 && Object.keys(saved.items).length === 5, `${nsaves} saves, ${Object.keys(saved.items).length} items`);
const resumed = await C.carry(dc, C.plan(W.wanted, saved), saved, { rootId: "root", bytesOf: bucket, save: async (m) => { saved = JSON.parse(JSON.stringify(m)); } });
check("the resume uploads only what is missing", resumed.done.length === W.wanted.length - 5 && !resumed.failed && resumed.left === 0, `${resumed.done.length} ${JSON.stringify(resumed.failed)}`);
check("every picture is on the Drive exactly once", files(dc).length === W.wanted.length && new Set(files(dc).map((f) => f.split("=")[0])).size === W.wanted.length, files(dc).length);
check("a third run does nothing", C.plan(W.wanted, saved).ops.length === 0);

// ---- files already there are adopted -------------------------------------------------
console.log("files already in the folder are adopted");
const da = seedTemplate(memoryDrive());
const sceneOne = (() => { const c = [...da.items.values()].find((x) => x.name === "shot-list"); da.items.set("pre-images", { id: "pre-images", name: "images", folder: true, parent: c.id }); const id = "pre-scene"; da.items.set(id, { id, name: "scene-01", folder: true, parent: "pre-images" }); return id; })();
da.items.set("pre1", { id: "pre1", name: "1a.jpg", folder: false, parent: sceneOne, bytes: "1001" });           // same picture
da.items.set("pre2", { id: "pre2", name: "1a-2.png", folder: false, parent: sceneOne, bytes: "1002" });           // same picture
da.items.set("pre3", { id: "pre3", name: "1b.jpg", folder: false, parent: sceneOne, bytes: "77" });             // same name, different picture
let saves = 0;
const ra = await C.carry(da, C.plan(W.wanted, C.emptyManifest("root", "live")), C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket, save: async () => { saves += 1; } });
check("same name and same size: recorded as done with the existing id, not uploaded", ra.manifest.items["shot:p1:r1"].id === "pre1" && ra.manifest.items["shot:p1:r2"].id === "pre2" && ra.adopted.length === 2, JSON.stringify(ra.adopted));
check("a same-named different picture is replaced in place, never doubled", ra.manifest.items["shot:p2:r3"].id === "pre3" && da.items.get("pre3").bytes === "1003", da.items.get("pre3").bytes);
check("no file of the same name twice in any folder", (() => { const k = files(da).map((f) => f.split("=")[0]); return new Set(k).size === k.length; })());
check("everything wanted is there once", files(da).length === W.wanted.length, `${files(da).length} of ${W.wanted.length}`);
check("an adopted file is not counted against the cap", ra.files === W.wanted.length - 2, ra.files);
check("every call saved the manifest", saves === W.wanted.length, saves);
check("a run after adopting does nothing", C.plan(W.wanted, ra.manifest).ops.length === 0);
// md5 when both sides give one
const dm = seedTemplate(memoryDrive());
const sceneM = (() => { const c = [...dm.items.values()].find((x) => x.name === "shot-list"); dm.items.set("m-images", { id: "m-images", name: "images", folder: true, parent: c.id }); dm.items.set("m-scene", { id: "m-scene", name: "scene-01", folder: true, parent: "m-images" }); return "m-scene"; })();
dm.items.set("md1", { id: "md1", name: "1a.jpg", folder: false, parent: sceneM, bytes: "1001", md5: "aaaa" });  // same size, different md5
const origList = dm.list.bind(dm);
dm.list = async (parent) => (await origList(parent)).map((x) => (x.md5 ? { ...x, md5: x.md5 } : x));
const rm = await C.carry(dm, C.plan(W.wanted, C.emptyManifest("root", "live")), C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket, md5Of: async () => "bbbb" });
check("md5 decides when both sides have one (same size, different md5: replaced, not adopted)", rm.adopted.length === 0 && rm.manifest.items["shot:p1:r1"].id === "md1" && dm.calls.replace === 1);
const dm2 = seedTemplate(memoryDrive());
const sceneM2 = (() => { const c = [...dm2.items.values()].find((x) => x.name === "shot-list"); dm2.items.set("m-images", { id: "m-images", name: "images", folder: true, parent: c.id }); dm2.items.set("m-scene", { id: "m-scene", name: "scene-01", folder: true, parent: "m-images" }); return "m-scene"; })();
dm2.items.set("md1", { id: "md1", name: "1a.jpg", folder: false, parent: sceneM2, bytes: "5", md5: "bbbb" });    // other size, same md5 (md5 wins)
const rm2 = await C.carry(dm2, C.plan(W.wanted, C.emptyManifest("root", "live")), C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket, md5Of: async () => "bbbb" });
check("…and the same md5 is adopted", rm2.adopted.length === 1 && rm2.manifest.items["shot:p1:r1"].id === "md1" && dm2.calls.replace === 0);

// ---- the time budget -------------------------------------------------------------------
console.log("a tick out of time");
let clockNow = 1_000_000;
const dt = seedTemplate(memoryDrive({ onUpload: () => { clockNow += 1000; } }));          // each upload takes a second
let savedT = null;
const rt = await C.carry(dt, C.plan(W.wanted, C.emptyManifest("root", "live")), C.emptyManifest("root", "live"),
  { rootId: "root", bytesOf: bucket, deadline: clockNow + 3500, clock: () => clockNow, save: async (m) => { savedT = JSON.parse(JSON.stringify(m)); } });
check("it stops cleanly once the time is used, between files", rt.timeUp === true && !rt.failed && rt.files === 4 && rt.left === W.wanted.length - 4, `${rt.files} ${rt.left}`);
check("what it did is saved", Object.keys(savedT.items).length === 4 && files(dt).length === 4);
let rounds = 1;
while (rounds < 30) {
  const again = C.plan(W.wanted, savedT);
  if (!again.ops.length) break;
  const r = await C.carry(dt, again, savedT, { rootId: "root", bytesOf: bucket, deadline: clockNow + 3500, clock: () => clockNow, save: async (m) => { savedT = JSON.parse(JSON.stringify(m)); } });
  rounds += 1;
  if (r.failed) break;
}
check(`the next ticks carry on from the manifest and finish (${rounds} ticks), no duplicates`, files(dt).length === W.wanted.length && new Set(files(dt).map((f) => f.split("=")[0])).size === W.wanted.length, files(dt).length);
check("with no deadline there is no time limit", (await C.carry(seedTemplate(memoryDrive()), P, C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket })).timeUp === false);

// ---- a failing Drive ------------------------------------------------------------------
console.log("a failing Drive");
const d4 = seedTemplate(memoryDrive({ failOn: (op) => op === "upload" }));
const M0 = C.emptyManifest("root", "live");
const snap = JSON.stringify(M0);
run = await C.carry(d4, P, M0, { rootId: "root", bytesOf: bucket });
check("the first upload fails: the run stops and says so", run.failed && run.failed.op === "create" && run.done.length === 0 && run.left === P.ops.length, JSON.stringify(run.failed));
check("no picture is recorded as copied", Object.keys(run.manifest.items).length === 0);
check("the manifest passed in is unchanged", JSON.stringify(M0) === snap);
let ups = 0;
const d5 = seedTemplate(memoryDrive({ failOn: (op) => op === "upload" && ++ups > 3 }));
run = await C.carry(d5, P, M0, { rootId: "root", bytesOf: bucket });
check("failing part way: what was made is kept, the rest is not", Object.keys(run.manifest.items).length === 3 && files(d5).length === 3 && run.failed);
const after = await C.carry(seedTemplate(memoryDrive()), P, M, { rootId: "root", bytesOf: bucket });
void after;
const d6 = seedTemplate(memoryDrive());
let m6 = (await C.carry(d6, C.plan(W.wanted, C.emptyManifest()), C.emptyManifest(), { rootId: "root", bytesOf: bucket })).manifest;
const r6 = film(); r6.scenes[0].number = "9"; r6.groups[0].rows[0].number = "9A";
const W6 = C.wantedOf({ view: r6, looks, media: MEDIA, docs: DOCS }).wanted;
const keep6 = JSON.stringify(m6);
const d6fail = Object.assign(Object.create(Object.getPrototypeOf(d6)), d6, { move: async () => { throw new Error("Google Drive answered 503"); } });
run = await C.carry(d6fail, C.plan(W6, m6), m6, { rootId: "root", bytesOf: bucket });
check("a failed move leaves the manifest as it was (renumber tried again next run)",
  run.failed && run.failed.op === "move" && eq(run.manifest.items, JSON.parse(keep6).items) && JSON.stringify(m6) === keep6);

// ---- copies taken off by hand -----------------------------------------------------------
console.log("a copy taken off the Drive by hand");
const id1 = m6.items["shot:p1:r1"].id;
d6.items.delete(id1);
run = await C.carry(d6, C.plan(W6, m6), m6, { rootId: "root", bytesOf: bucket });
check("renumbering a copy that is gone makes it again in its new place", !run.failed && files(d6).some((f) => f.startsWith("1-creative/shot-list/images/scene-09/9a.jpg")) && run.manifest.items["shot:p1:r1"].id !== id1, JSON.stringify(run.failed));

// ---- homes ------------------------------------------------------------------------------
console.log("homes");
const bare = memoryDrive();
let home = await C.findHome(bare, "root", "shots", { make: false });
check("a look finds nothing and makes nothing", home === null && bare.calls.mkdir === 0);
home = await C.findHome(bare, "root", "shots", { make: true });
check("no spine: 1-creative/shot-list is made", home.path === "1-creative/shot-list" && eq(home.made, ["1-creative", "1-creative/shot-list"]));
const older = memoryDrive();
older.items.set("o1", { id: "o1", name: "4-shot-list", folder: true, parent: "root" });
older.items.set("o2", { id: "o2", name: "2-look", folder: true, parent: "root" });
home = await C.findHome(older, "root", "shots", { make: true });
check("an older spine's 4-shot-list is used as it is", home.id === "o1" && home.made.length === 0);
const refs = await C.findHome(older, "root", "refs", { make: true });
check("…and with no reference folder, 1-creative/reference is made", refs.path === "1-creative/reference");
const cr = memoryDrive();
cr.items.set("c1", { id: "c1", name: "1-Creative", folder: true, parent: "root" });
cr.items.set("c2", { id: "c2", name: "References", folder: true, parent: "c1" });
home = await C.findHome(cr, "root", "refs", { make: true });
check("names are matched without regard to case", home.id === "c2" && home.path === "1-Creative/References");

// ---- the switch ----------------------------------------------------------------------------
console.log("the switch");
const S0 = C.settingsShape(null);
check("off by default, no scratch folder, default cap", S0.mode === "off" && S0.drivecopies_root === "" && eq(S0.cap, C.DEFAULT_CAP));
check("off refuses", !C.readiness(S0, { signin: true }).ok);
const S1 = C.changedSettings(S0, { mode: "scratch", by: "check" });
check("scratch with no scratch folder refuses to write", S1.mode === "scratch" && !C.readiness(S1, { signin: true }).ok && /scratch folder/.test(C.readiness(S1, { signin: true }).why));
const S2 = C.changedSettings(S1, { drivecopies_root: "1AbCdEfGhIjKlMnOpQ" });
check("scratch with a scratch folder writes there", C.readiness(S2, { signin: true }).ok && C.readiness(S2, { signin: true }).root === "1AbCdEfGhIjKlMnOpQ");
check("live writes to each project's own folder", C.readiness(C.changedSettings(S2, { mode: "live" }), { signin: true }).root === "");
check("no write sign-in refuses", !C.readiness(S2, { signin: false }).ok);
check("bad values are refused", Boolean(C.changedSettings(S0, { mode: "on" }).problem) && Boolean(C.changedSettings(S0, { drivecopies_root: "x/y" }).problem) && Boolean(C.changedSettings(S0, { only: "abc" }).problem));
check("only keeps project IDs", eq(C.changedSettings(S0, { only: ["27FD41C6-9232-85EF-FB41-4614BF2884E0", "nope"] }).only, ["27fd41c6923285effb414614bf2884e0"]));

// ---- scene folders made before images/ move whole --------------------------------------------
console.log("scene folders made before images/");
{
  // Build the old layout: copy everything, then put the scene folders back beside the spreadsheet, as the copier used to.
  const dl = seedTemplate(memoryDrive());
  const first = await C.carry(dl, C.plan(W.wanted, C.emptyManifest("root", "live")), C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket });
  const shotList = [...dl.items.values()].find((x) => x.name === "shot-list");
  const legacy = JSON.parse(JSON.stringify(first.manifest));
  for (const [k, id] of Object.entries(first.manifest.subs)) {
    const m = /^shots\/images\/(.+)$/.exec(k);
    if (!m) continue;
    dl.items.get(id).parent = shotList.id;
    legacy.subs[`shots/${m[1]}`] = id; delete legacy.subs[k];
  }
  for (const h of Object.values(legacy.items)) if (h.home === "shots") h.sub = h.sub.replace(/^images\//, "");
  delete legacy.subs["shots/images"];
  dl.items.delete([...dl.items.values()].find((x) => x.name === "images").id);
  const ids = new Map([...dl.items.values()].filter((x) => !x.folder).map((x) => [x.id, x.name]));
  const before = files(dl).map((f) => f.replace("/images/", "/"));
  const lp = C.plan(W.wanted, legacy);
  const nScenes = Object.keys(legacy.subs).filter((k) => k.startsWith("shots/")).length;
  check("a legacy manifest: one folder move per scene folder, no per-file moves, no creates", lp.counts.movefolder === nScenes && lp.counts.move === 0 && lp.counts.create === 0 && lp.counts.update === 0 && lp.counts.aside === 0, JSON.stringify(lp.counts));
  const lr = await C.carry(dl, lp, legacy, { rootId: "root", bytesOf: bucket });
  check("moved, nothing failed", !lr.failed && lr.left === 0 && lr.done.length === nScenes, JSON.stringify(lr.failed));
  check("the pictures are now under shot-list/images/, none left beside the spreadsheet", files(dl).filter((f) => f.startsWith("1-creative/shot-list/scene-")).length === 0 && files(dl).filter((f) => f.startsWith("1-creative/shot-list/images/scene-")).length === before.filter((f) => f.startsWith("1-creative/shot-list/scene-")).length, files(dl).join("\n"));
  check("same Drive files, same ids, nothing uploaded again", [...dl.items.values()].filter((x) => !x.folder && ids.get(x.id) === x.name).length === ids.size && dl.calls.upload === W.wanted.length, `${dl.calls.upload} uploads of ${W.wanted.length}`);
  check("one images folder, the scene folders keep their ids", [...dl.items.values()].filter((x) => x.folder && x.name === "images").length === 1 && Object.entries(legacy.subs).filter(([k]) => k.startsWith("shots/")).every(([k, id]) => lr.manifest.subs[`shots/images/${k.slice(6)}`] === id));
  check("then nothing to do", C.plan(W.wanted, lr.manifest).ops.length === 0);
  check("nothing tried to delete or trash", dl.calls.forbidden === 0);
  // A scene folder somebody took off the Drive by hand: forgotten, its pictures made again under images/.
  const dg = seedTemplate(memoryDrive());
  const f2 = await C.carry(dg, C.plan(W.wanted, C.emptyManifest("root", "live")), C.emptyManifest("root", "live"), { rootId: "root", bytesOf: bucket });
  const lg = JSON.parse(JSON.stringify(f2.manifest));
  const sceneKey = Object.keys(lg.subs).find((k) => /^shots\/images\/scene-/.test(k));
  const sceneId = lg.subs[sceneKey], plain = sceneKey.replace("/images", "");
  lg.subs[plain] = sceneId; delete lg.subs[sceneKey];
  for (const h of Object.values(lg.items)) if (h.home === "shots" && h.sub === sceneKey.slice(6)) h.sub = plain.slice(6);
  dg.items.delete(sceneId);
  for (const x of [...dg.items.values()]) if (x.parent === sceneId) dg.items.delete(x.id);
  const rg0 = await C.carry(dg, C.plan(W.wanted, lg), lg, { rootId: "root", bytesOf: bucket });
  const rg = await C.carry(dg, C.plan(W.wanted, rg0.manifest), rg0.manifest, { rootId: "root", bytesOf: bucket });   // the next tick makes them again
  check("a legacy folder that is gone: its pictures are made again under images/", !rg.failed && files(dg).length === files(dl).length && C.plan(W.wanted, rg.manifest).ops.length === 0, `${JSON.stringify(rg.failed)} ${files(dg).length} vs ${files(dl).length} ops ${JSON.stringify(C.plan(W.wanted, rg.manifest).counts)}`);
}

console.log("edit references (the Edit Reference mod)");
{
  const h = "feedface00004000800000000000000d", st = "0f0cf23afb5d3f3647b331e79692e207";
  const view = { groups: [], boards: [], editRefs: [{ id: "e1", name: "Car Cut!", media: [
    { ref: "r1", hash: h, filename: "car.mp4", kind: "video" },
    { ref: "r2", hash: st, filename: "still.png", kind: "image" }] }] };
  const media = { [`${h}.mp4`]: 3000, [`${h}.jpg`]: 200, [`${st}.png`]: 100 };
  const got = C.wantedOf({ view, media }).wanted;
  const names = got.map((w) => `${w.home}/${w.sub}/${w.name}`).sort();
  check("an edit reference's clip, poster and still go to reference/edit, named by it",
    JSON.stringify(names) === JSON.stringify(["refs/edit/car-cut-01.png", "refs/edit/car-cut-poster.jpg", "refs/edit/car-cut.mp4"]), JSON.stringify(names));
  check("a film with none files nothing new", C.wantedOf({ view: { groups: [], boards: [] }, media }).wanted.length === 0);
  const clash = C.wantedOf({ view: { ...view, boards: [{ id: "b", name: "Edit", media: [] }] }, media }).wanted;
  check("a board already called Edit keeps its folder", clash.every((w) => w.sub === "edit-reference"));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
