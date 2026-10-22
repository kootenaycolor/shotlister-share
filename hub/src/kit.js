/**
 * **The kit: a film's Camera Spec Sheets as what its shots pick from**
 * (Ref 1627, his words 2026-10-08: "the spec sheet could also feed the
 * lenses in Shotlister and diagrams and vice versa").
 *
 * **Where the spec sheet lives.** One Notion row per shoot, in Camera Spec
 * Sheets. Notion is its only home: the project record keeps no copy, and
 * Projects Console on the Studio Mac is the one thing that writes it, reading
 * the row just before and comparing it with what the asking screen saw
 * (`shoots.edit_spec_sheet`). The portal's card holds what Notion said at the
 * last refresh: `camera` and `camera_sheet` (the lead shoot's), and each
 * shoot's own `camera` and `sheet`.
 *
 * So this module never stores a spec sheet. It reads the card's, breaks it
 * into picks (`lensPicks`, `entries`), and when Shotlister or the connector
 * changes one it puts `edit_spec_sheet` on the record's pending list — the
 * road the phone and the laptop already take — for the Studio to write into
 * Notion. Until the card catches up, an edit asked for is laid over what the
 * card says and marked `waiting`, so nobody sees their own change vanish.
 *
 *   GET  /kit/<film>    the kit: every shoot's sheet, picks and cameras
 *   POST /kit/<film>    { sheet, seen, changes } or { sheet, add: {lens} | {camera, label} }
 *                       or { sheet, mode: {camera, mode} } (a record sheet: a sensor mode picked)
 *
 * On the MCP's host, with the token the phone uses (the relay's password).
 */
import { entries, pillsOf, CAMERA_LABELS } from "./entries.js";
import { lensPicks } from "./lenses.js";
import { CAMERA, frontOf, leadShoot } from "./front.js";
import { recordPageOf, recordView, writeFacts } from "./facts.js";
import { specPills } from "./specpills.js";
import { PROJECT_KEY, sheetForShoot, textView, recordSheets, specSwitch, applyBoxText, addCamera, checkSheet, applyFrameOp, applyFinishingOp, finishingOf, framesOf, ratioOnCard } from "./specsheet.js";
import { readLibrary, matchLens, itemOf } from "./lenslibrary.js";
import { readModes, pickMode } from "./sensormodes.js";
import { readExtras, pickExtras } from "./kitlibrary.js";

/** A sheet's boxes and the Notion properties they are — `CAMERA_FROM` in
 * notion.js, without the LUT labels (edited with the LUTs, in the console). */
export const SHEET_FIELDS = {
  body: "Camera", lenses: "Lenses", format: "Shooting Format",
  capture: "Capture Resolution",
  colour: "Color Space", codec: "Codec", fps: "Frame Rate",
  desqueeze: "Desqueeze",
};
/** The words each box is called on screen, in a crew's reading order. */
export const SHEET_WORDS = {
  body: "Camera", lenses: "Lenses", modifiers: "Modifiers", filters: "Filters", format: "Shooting Format", capture: "Capture Resolution",
  colour: "Colour Space", codec: "Codec", fps: "Frame Rate",
  desqueeze: "Desqueeze",
};
const PROPERTY_BOX = Object.fromEntries(Object.entries(SHEET_FIELDS).map(([box, prop]) => [prop, box]));

const PAGE = /^[0-9a-f]{32}$/;
const bare = (id) => String(id || "").replace(/-/g, "").toLowerCase();
const same = (a, b) => String(a || "").split(/\s+/).join(" ").trim() === String(b || "").split(/\s+/).join(" ").trim();

/** Cameras off the sheet's Camera box: [{label, body}]. */
export function camerasOf(text) {
  return entries(text).map((e) => ({ label: e.label, body: e.value })).filter((c) => c.body);
}

/** The lenses Shotlister picks off the Lenses box. A pill is a lens, named
 * in full ("Master Prime 25mm", 2026-10-13); a sheet still in the old typed
 * sets ("A Cam: Cooke S4/i — 18, 25mm") is read as before. */
export function lensesOf(text) {
  const lines = String(text || "").split("\n").filter((x) => x.trim());
  const typed = lines.some((x) => /\s[—–|]\s|,/.test(x) || entries(x)[0].label);
  return typed ? lensPicks(text) : pillsOf(lines);
}

/** The film's shoots as sheets, oldest first, before anything is laid over.
 * `sheets` are the record's (specsheet.js), when the switch is on. */
function sheetsOf(front, sheets = null) {
  const shoots = (front && front.shoots) || [];
  const lead = leadShoot(front);
  const onRecord = (one) => Boolean(sheets && sheetForShoot(sheets, one.id));
  const withSheets = shoots.filter((one) => one.sheet || onRecord(one) || Object.values(one.camera || {}).some(Boolean));
  if (!withSheets.length) {
    if (sheets && sheets[PROJECT_KEY]) {
      return [{ shoot: "", name: "", start: "", end: "", sheet: (front && front.camera_sheet) || "", lead: true, camera: { ...((front && front.camera) || {}) } }];
    }
    const camera = { ...((front && front.camera) || {}) };
    if (!(front && front.camera_sheet) && !Object.values(camera).some(Boolean)) return [];
    return [{ shoot: "", name: "", start: "", end: "", sheet: (front && front.camera_sheet) || "", lead: true, camera }];
  }
  return shoots.map((one) => ({
    shoot: one.id || "", name: one.name || "", start: one.start || "", end: one.end || "",
    sheet: one.sheet || "", lead: one === lead, camera: { ...(one.camera || {}) },
  }));
}

/**
 * **The kit**: each shoot's sheet with what Shotlister picks from it, and any
 * edit still on its way to Notion laid over it. `pending` is the record's
 * queue (`r/<page>/pending.json`); `updated` is when the card last read Notion.
 */
export function kitOf(front, pending = [], updated = "", sheets = null) {
  const card = Date.parse(updated || (front && front.updated) || "") || 0;
  const shoots = sheetsOf(front, sheets).map((one) => ({ ...one, waiting: [], failed: "" }));
  // **The record's sheet, when the switch is on** (specsheet.js): what the
  // shoot reads, as labelled text for the boxes and as itself (`record`).
  for (const one of shoots) {
    const got = sheets ? sheetForShoot(sheets, one.shoot) : null;
    if (!got) continue;
    one.record = { fact: got.fact, v: got.v, sheet: got.sheet };
    one.finishing = finishingOf(sheets, got.fact);
    // the sheet's aspect ratios, Main first (a camera has no frame guides of its own)
    const frames = framesOf(got.sheet).filter((f) => f.ratio || (f.guides || []).length);
    one.ratios = [...frames.filter((f) => f.main), ...frames.filter((f) => !f.main)].map(ratioOnCard);
    one.camera = { ...one.camera, ...textView(got.sheet).boxes };
  }
  for (const item of pending || []) {
    if (!item || item.verb !== "edit_spec_sheet") continue;
    const args = item.args || {};
    const one = shoots.find((s) => !s.record && s.sheet && s.sheet === bare(args.sheet));
    if (!one) continue;
    const asked = Date.parse(item.asked || "") || 0;
    const after = asked > card;
    if (item.state === "failed") {
      if (after) one.failed = item.report || "The Studio could not write it.";
      continue;
    }
    // Pending, working, or done but not yet read back by a refresh.
    if (item.state !== "pending" && item.state !== "working" && !(item.state === "done" && after)) continue;
    // A later ask stands in for one that failed (the queue is oldest first).
    one.failed = "";
    for (const [prop, text] of Object.entries(args.changes || {})) {
      const box = PROPERTY_BOX[prop];
      if (!box) continue;
      one.camera[box] = String(text ?? "");
      if (!one.waiting.includes(box)) one.waiting.push(box);
    }
  }
  return shoots.map((one) => ({
    ...one,
    source: one.record ? "record" : "notion",
    cameras: one.record ? one.record.sheet.cameras.map((c) => ({ label: c.label, body: c.body })).filter((c) => c.body) : camerasOf(one.camera.body),
    lenses: one.record ? one.record.sheet.lenses.map((l) => l.name) : lensesOf(one.camera.lenses),
    // what the shoot carries beside its lenses (kitlibrary.js): the record's sheet only
    modifiers: one.record ? (one.record.sheet.modifiers || []).map((x) => x.name) : [],
    filters: one.record ? (one.record.sheet.filters || []).map((x) => x.name) : [],
  }));
}

/** The kit as the engine takes it (`recordkit`): only what a film needs. */
export function kitForFilm(kit) {
  return kit.map(({ name, start, end, sheet, lead, cameras, lenses, modifiers = [], filters = [] }) => ({ name, start, end, sheet, lead, cameras, lenses, modifiers, filters }));
}

/** The sheet a shoot is: by its sheet id, its shoot id or name, or the lead. */
export function sheetNamed(kit, said) {
  const s = String(said || "").trim();
  if (!s) return kit.find((one) => one.lead) || kit[0] || null;
  const low = s.toLowerCase();
  return kit.find((one) => one.sheet === bare(s) || one.shoot === bare(s))
    || kit.find((one) => one.name.toLowerCase() === low)
    || kit.find((one) => /^\d+$/.test(s) && new RegExp(`\\bshoot\\s+${s}\\b`, "i").test(one.name))
    || null;
}

/**
 * **What adding one lens or camera writes** (Shotlister's Add to Spec Sheet):
 * {box, text, entries} for the box, the lines put at the end, or {why}. Never
 * removes, never rewrites a line he typed.
 *
 * **The library's name** (phase 2, lenslibrary.js; closes Ref 1724): with the
 * lens library given, a lens is put on as the library names it ("27mm" is
 * "Master Prime 27mm" when one lens of that focal fits, or the one in a set
 * the pool already has), a set adds every lens in it, a whole set one entry.
 * Several that fit and none to choose between: refused with the choices. A
 * lens the library does not know goes on as said.
 */
export function addPlan(one, add, library = null) {
  const lens = String((add && add.lens) || "").trim();
  const body = String((add && add.camera) || "").trim();
  if (lens) {
    let entries = [{ name: lens, note: "" }];
    if (library) {
      const pool = one.record ? one.record.sheet.lenses : one.lenses.map((name) => {
        const hit = itemOf(library, name);
        const set = hit && hit.kind === "lens" && hit.item.set ? library.sets.find((x) => x.id === hit.item.set) : null;
        return { name, set: set ? set.name : "" };
      });
      const hit = matchLens(library, lens, pool);
      if (hit && hit.choices) return { why: `${lens} could be ${hit.choices.join(" or ")}. Say which.`, choices: hit.choices };
      if (hit) entries = hit.entries;
    }
    const fresh = entries.filter((e) => !one.lenses.some((p) => p.toLowerCase() === e.name.toLowerCase()));
    if (!fresh.length) return { why: `${entries.length > 1 ? "Every lens in it is" : `${entries[0].name} is`} on the spec sheet already.` };
    const was = String(one.camera.lenses || "").replace(/\s+$/, "");
    const lines = fresh.map((e) => e.name).join("\n");
    return { box: "lenses", text: was ? `${was}\n${lines}` : lines, entries: fresh };
  }
  if (body) {
    if (one.cameras.some((c) => c.body.toLowerCase() === body.toLowerCase())) return { why: `${body} is on the spec sheet already.` };
    const label = String((add && add.label) || "").trim();
    const was = String(one.camera.body || "").replace(/\s+$/, "");
    // A line of its own, under the camera's name when it has one
    // ("B-Cam: FX6"); a sheet with one unlabelled camera is left as typed.
    const line = label ? `${label}: ${body}` : body;
    return { box: "body", text: was ? `${was}\n${line}` : line };
  }
  return { why: "Say a lens or a camera." };
}

/** Changes asked for, checked: {changes: {box: text}, seen: {box: text}} or {why}. */
/** Boxes only a sheet on the record has (2026-10-14): Notion has no column for them. */
export const RECORD_BOXES = ["modifiers", "filters"];

export function planEdit(one, changes, seen) {
  const out = {};
  const saw = {};
  for (const [box, value] of Object.entries(changes || {})) {
    if (RECORD_BOXES.includes(box) && !one.record) return { why: `${box === "modifiers" ? "Modifiers" : "Filters"} go on a spec sheet kept on the project record. This one is still Notion's.` };
    if (!(box in SHEET_FIELDS) && !RECORD_BOXES.includes(box)) return { why: `A spec sheet has no “${box}”. One of ${Object.keys(SHEET_FIELDS).join(", ")}.` };
    const text = String(value ?? "").replace(/\r\n?/g, "\n");
    if (text.length > (CAMERA[box] || 400)) return { why: `${SHEET_WORDS[box]} is too long.` };
    const now = String(one.camera[box] || "");
    const asSeen = seen && box in seen ? String(seen[box] ?? "") : now;
    if (!same(asSeen, now)) return { moved: box, why: `${SHEET_WORDS[box]} changed since it was read. It says “${now}” now.` };
    if (same(text, now)) continue;
    out[box] = text;
    saw[box] = now;
  }
  return { changes: out, seen: saw };
}

// ---------------------------------------------------------------- the queue

async function pendingAt(env, page) {
  const got = await env.BUCKET.get(`r/${page}/pending.json`);
  if (!got) return [];
  try {
    const list = await got.json();
    return Array.isArray(list) ? list.filter((x) => x && typeof x === "object") : [];
  } catch { return []; }
}

/**
 * **Ask the Studio to write the sheet** — `edit_spec_sheet` on the record's
 * pending list, in the shape `/console/record/<page>/pending` makes (worker.js
 * `recordDoor`; `record.VERBS` in the console). Notion's property names, and
 * the words the screen saw, so the console refuses an edit that crossed one.
 */
export async function askSheetEdit(env, page, sheet, changes, seen, by) {
  // The Camera box reads "A Cam: Alexa 35"; Notion holds only the body (the
  // label is the record's, `camera_labels`), so the label stays off the sheet.
  const bodies = (text) => entries(text).map((e) => e.value).join("\n");
  const props = (map) => Object.fromEntries(Object.entries(map).map(([box, text]) => [SHEET_FIELDS[box], box === "body" ? bodies(text) : text]));
  const item = {
    id: crypto.randomUUID().replace(/-/g, "").slice(0, 12),
    verb: "edit_spec_sheet",
    args: { sheet, seen: props(seen), changes: props(changes) },
    by: String(by || "Shotlister").slice(0, 80),
    asked: new Date().toISOString(),
    state: "pending",
    report: "",
  };
  const list = await pendingAt(env, page);
  list.push(item);
  await env.BUCKET.put(`r/${page}/pending.json`, JSON.stringify(list), {
    httpMetadata: { contentType: "application/json" },
  });
  return item;
}

/** The film's kit with its record page and queue — what the door and the
 * connector read. `page` is "" for a film with no project record. */
export async function kitHere(env, project, ctx) {
  const front = await frontOf(env, project, ctx);
  const page = await recordPageOf(env, project, front);
  const pending = page ? await pendingAt(env, page) : [];
  // the record first once the switch is on; Notion for a shoot it has no sheet for
  const on = (await specSwitch(env)).on;
  const sheets = on && page ? recordSheets((await recordView(env, page)).facts) : null;
  // the studio's lens library, for Add to Spec Sheet's full names (lenslibrary.js)
  let library = null;
  try { library = (await readLibrary(env)).library; } catch { library = null; }
  // modifiers and filters, for Add to Spec Sheet's full names (kitlibrary.js)
  let extras = null;
  try { extras = (await readExtras(env)).extras; } catch { extras = null; }
  const kit = kitOf(front, pending, front.updated, sheets);
  // each lens's close focus, off the library, by its line ("CF 0.35 m"); only when set (2026-10-15)
  if (library) {
    const { entryOfSheetLens, cfLabel } = await import("./lenslibrary.js");
    for (const one of kit) {
      if (!one.record) continue;
      const cf = {};
      for (const l of one.record.sheet.lenses || []) {
        const said = cfLabel(entryOfSheetLens(library, l));
        if (said) cf[l.note ? `${l.name} · ${l.note}` : l.name] = said;
      }
      if (Object.keys(cf).length) one.lens_cf = cf;
    }
  }
  return { front, page, pending, sheets, on, library, extras, kit };
}

/**
 * **A change to a sheet on the record** (the switch on): laid on the sheet
 * and written through `writeFacts` from the version it was read at, so an
 * edit that crossed another is refused, never written over it.
 */
async function changeRecordSheet(env, here, one, asked, by) {
  let sheet = one.record.sheet;
  let boxes;
  if (asked.frame) {
    // one frame change, the console's ops (specsheet.applyFrameOp, stage 5 step 5)
    const got = applyFrameOp(sheet, asked.frame);
    if (got.why) return { status: 409, why: got.why };
    sheet = got.sheet;
    boxes = ["frames"];
  } else if (asked.finishing) {
    // one finishing resolution change (specsheet.applyFinishingOp, 2026-10-15)
    const got = applyFinishingOp(sheet, asked.finishing);
    if (got.why) return { status: 409, why: got.why };
    sheet = got.sheet;
    boxes = ["finishing_resolutions"];
  } else if (asked.mode) {
    // a sensor mode picked for a camera, or every camera (sensormodes.js)
    const modes = (await readModes(env)).modes;
    const got = pickMode(sheet, modes, asked.mode.camera || asked.mode.label || "", asked.mode.mode || asked.mode.name || "");
    if (got.why) return { status: 409, why: got.why };
    sheet = got.sheet;
    boxes = got.mode.capture ? ["format", "capture"] : ["format"];
  } else if (asked.add && (asked.add.modifier || asked.add.filter)) {
    // a shot's modifier or filter the sheet does not carry (2026-10-14): as
    // the library names it, a filter set adding every strength; else as said
    const pool = asked.add.modifier ? "modifiers" : "filters";
    const said = String(asked.add.modifier || asked.add.filter).trim();
    const picked = here.extras ? pickExtras(sheet, here.extras, said) : { why: "no library" };
    if (!picked.why && picked.pool === pool) {
      if (!picked.added.length) return { status: 409, why: `${said} is on the spec sheet already.`, already: true };
      sheet = picked.sheet;
    } else {
      if ((sheet[pool] || []).some((x) => x.name.toLowerCase() === said.toLowerCase())) return { status: 409, why: `${said} is on the spec sheet already.`, already: true };
      sheet = JSON.parse(JSON.stringify(sheet));
      sheet[pool] = [...(sheet[pool] || []), { name: said, note: "" }];
    }
    boxes = [pool];
  } else if (asked.add) {
    const lens = String(asked.add.lens || "").trim();
    const body = String(asked.add.camera || "").trim();
    const plan = addPlan(one, asked.add, here.library);
    if (plan.why) return { status: 409, why: plan.why, already: !plan.choices, ...(plan.choices ? { choices: plan.choices } : {}) };
    sheet = JSON.parse(JSON.stringify(sheet));
    if (lens) sheet.lenses.push(...plan.entries);
    else if (sheet.cameras.length === 1 && !sheet.cameras[0].body) sheet.cameras[0].body = body;
    else addCamera(sheet, { label: String(asked.add.label || "").trim(), body });
    boxes = [lens ? "lenses" : "body"];
  } else {
    const plan = planEdit(one, asked.changes, asked.seen);
    if (plan.why) return { status: 409, why: plan.why, moved: plan.moved || "" };
    boxes = Object.keys(plan.changes);
    if (!boxes.length) return { status: 200, item: null, kit: here.kit, why: "It says that already." };
    for (const box of boxes) {
      const got = applyBoxText(sheet, box, plan.changes[box]);
      if (got.why) return { status: 409, why: got.why };
      sheet = got.sheet;
    }
  }
  const checked = checkSheet(sheet);
  if (checked.why) return { status: 409, why: checked.why };
  const got = await writeFacts(env, here.page, { [one.record.fact]: { value: checked.sheet, base: one.record.v } }, by);
  if (got.status === 409) return { status: 409, why: "The spec sheet changed since it was read. Read it again." };
  if (got.status !== 200) return { status: got.status, why: got.problem || "The record would not take it." };
  const sheets = recordSheets(got.facts);
  const kit = kitOf(here.front, here.pending, here.front.updated, sheets);
  const item = { verb: "spec_sheet", state: "done", args: { sheet: one.sheet, shoot: one.shoot, fact: one.record.fact, changes: Object.fromEntries(boxes.map((b) => [b, true])) }, by };
  return { status: 200, item, kit, record: true };
}

/**
 * **One change to one sheet**, from Shotlister or the connector. `asked` is
 * {sheet|shoot, seen, changes} or {sheet|shoot, add}. Answers {item, kit} or
 * {status, why}.
 */
export async function changeSheet(env, project, ctx, asked, by) {
  const here = await kitHere(env, project, ctx);
  if (!here.page) return { status: 409, why: "This film has no project record, so its spec sheet is changed in Notion or Projects Console." };
  const one = sheetNamed(here.kit, asked.sheet || asked.shoot);
  if (!one) return { status: 404, why: `No spec sheet called “${asked.sheet || asked.shoot}”. ${here.kit.map((k) => k.name || "The film's").join(", ") || "This film has none yet"}.` };
  if (one.record) return await changeRecordSheet(env, here, one, asked, by);
  if (asked.mode) return { status: 409, why: "A sensor mode is picked on a sheet kept on the project record. This one is still Notion's." };
  if (asked.frame) return { status: 409, why: "Aspect ratios are kept on a spec sheet on the project record. This one is still Notion's." };
  if (asked.finishing) return { status: 409, why: "Finishing resolutions are kept on a spec sheet on the project record. This one is still Notion's." };
  if (asked.add && (asked.add.modifier || asked.add.filter)) return { status: 409, why: "Modifiers and filters go on a spec sheet kept on the project record. This one is still Notion's." };
  if (!PAGE.test(one.sheet)) {
    return { status: 409, why: `${one.name || "This film"} has no Camera Spec Sheet in Notion yet. Projects Console makes one (New Shoot, or the Shoots tab).` };
  }
  let changes;
  let seen;
  if (asked.add) {
    const plan = addPlan(one, asked.add, here.library);
    if (plan.why) return { status: 409, why: plan.why, already: !plan.choices, ...(plan.choices ? { choices: plan.choices } : {}) };
    changes = { [plan.box]: plan.text };
    seen = { [plan.box]: String(one.camera[plan.box] || "") };
  } else {
    const plan = planEdit(one, asked.changes, asked.seen);
    if (plan.why) return { status: 409, why: plan.why, moved: plan.moved || "" };
    changes = plan.changes;
    seen = plan.seen;
  }
  if (!Object.keys(changes).length) return { status: 200, item: null, kit: here.kit, why: "It says that already." };
  if ("body" in changes) await keepCameraLabels(env, here.page, changes.body, by);
  const item = await askSheetEdit(env, here.page, one.sheet, changes, seen, by);
  return { status: 200, item, kit: kitOf(here.front, [...here.pending, item], here.front.updated) };
}

/** The labels a Camera box carries ("B Cam: FX6"), put on the record's
 * `camera_labels` beside the ones it has. A body named with no label keeps
 * the label it had. */
export async function keepCameraLabels(env, page, text, by) {
  const named = entries(text).filter((e) => e.label && e.value);
  if (!named.length) return;
  for (let tries = 0; tries < 2; tries++) {
    const one = ((await recordView(env, page)).facts || {})[CAMERA_LABELS] || null;
    const was = one && one.value && typeof one.value === "object" ? one.value : {};
    const next = { ...was };
    for (const e of named) next[e.value] = e.label;
    if (JSON.stringify(next) === JSON.stringify(was)) return;
    const got = await writeFacts(env, page, { [CAMERA_LABELS]: { value: next, base: one ? one.v || 0 : 0 } }, by);
    if (got.status !== 409) return;
  }
}

// ---------------------------------------------------------------- the door

/**
 * `GET|POST /kit/<film>`. `helpers` are the worker's own: {carriesToken,
 * hasFilm, portalOf, json, problem}, so this file needs nothing of worker.js.
 */
export async function kitDoor(request, env, url, ctx, helpers) {
  const { carriesToken, hasFilm, portalOf, json, problem } = helpers;
  const expected = env.CONSOLE_TOKEN;
  if (!expected) return problem(503, "No token is set on the hub.");
  if (!carriesToken(request, expected)) return problem(401, "Not this hub's token.");
  const parts = url.pathname.split("/").filter(Boolean);
  const project = parts[1] || "";
  if (parts.length !== 2 || !/^[0-9a-f]{32}$/.test(project)) return problem(404, "No such film.");
  if (!(await hasFilm(env, project)) && !(await portalOf(env, project))) return problem(404, "No such film.");

  if (request.method === "GET") {
    const here = await kitHere(env, project, ctx);
    // every pill each box offers, in Notion's colours: {box: [{name, color}]}
    const offered = await specPills(env);
    const pills = Object.fromEntries(Object.entries(SHEET_FIELDS).map(([box, prop]) => [box, offered[prop] || []]));
    return json({
      project, page: here.page, updated: here.front.updated || null, editable: Boolean(here.page),
      // the switch (specsheet.js): on, a shoot with `source: "record"` is the record's sheet
      on_record: here.on,
      fields: SHEET_WORDS, shoots: here.kit, pills,
      pending: here.pending.filter((x) => x.verb === "edit_spec_sheet").slice(-12),
    });
  }
  if (request.method !== "POST") return problem(405, "GET or POST.");
  let asked;
  try { asked = await request.json(); } catch { return problem(400, "That is not JSON."); }
  if (!asked || typeof asked !== "object" || Array.isArray(asked)) return problem(400, "Say what changes.");
  const got = await changeSheet(env, project, ctx, asked, `Shotlister${asked.by ? ` on ${String(asked.by).slice(0, 40)}` : ""}`);
  if (got.status !== 200) return json({ ok: false, why: got.why, moved: got.moved || "", already: Boolean(got.already), ...(got.choices ? { choices: got.choices } : {}) }, got.status);
  return json({ ok: true, item: got.item, said: got.why || "", shoots: got.kit });
}
