/**
 * **A shoot's own edits are the record's first** (2026-10-15, his rule: the
 * server record is the master, Notion a one-way mirror, no save waits on
 * Notion). Editing one Shoots row's dates, name or notes used to be written to
 * Notion first and read back; now it is a change to the project's record, the
 * screen shows it at once, and Notion follows on the link's next minute.
 *
 * **Where it lives.** The record already holds a copy of the project's Shoots
 * rows (`shoots`, written from Notion every five minutes by notionsync.js).
 * That copy stays Notion's. Beside it the record holds `shoot_edits`: the
 * edits made here that Notion has not got yet,
 *
 *     { <shoot id>: { want: {start, end, notes, name},   only what was changed
 *                     from: {start, end, notes, name},   what those were when the edit was made
 *                     at } }
 *
 * What a shoot is now = the copy with its waiting edit laid over it
 * (`nowOf`); that is what an edit is checked against, and what the project
 * page shows (`layEdit`, here and in the Mac's projectpage.py).
 *
 * **Notion follows** (`pushEdits`, called by the minute's look): each waiting
 * edit is held to the row as Notion has it now. Notion still as the edit found
 * it → written; already the same → nothing to write; Notion changed those
 * fields meanwhile → Notion's words stay and the edit is let go (it is told in
 * the look's notes). Either way the edit leaves `shoot_edits`.
 *
 * The compare-and-set is the same one the Notion way used (`shootEditPlan`),
 * so what the screen saw (`seen`) is checked first and a shoot that moved is
 * answered `moved`, nothing written.
 */
import { recordOf, shootEditPlan, nameOf, titled, cleanName, bareId, datesOf, plainTitle } from "./cloud.js";
import { shootsSnapshot } from "./notionlink.js";

export const EDITS = "shoot_edits";
const isObject = (x) => x && typeof x === "object" && !Array.isArray(x);
const KEYS = ["start", "end", "notes", "name"];

/** The waiting edits on a record's facts: {shootId: {want, from, at}}. */
export function editsOf(facts) {
  const one = facts && facts[EDITS];
  return one && isObject(one.value) ? one.value : {};
}

const dash = (title) => {
  for (const d of [" — ", " – ", " - "]) if ((title || "").includes(d)) return String(title).slice(String(title).indexOf(d) + d.length).trim();
  return title || "";
};

/** A Shoots row as projectpage reads it (`shootOf`) with a waiting edit laid
 * over it. Anything else about the row is left as it is. */
export function layEdit(row, edit) {
  if (!edit || !isObject(edit.want)) return row;
  const w = edit.want;
  const out = { ...row };
  if ("start" in w) {
    const s = String(w.start || ""), e = String(w.end || "");
    out.start = s;
    out.end = s && e && e !== s ? e : "";
  }
  if ("notes" in w) out.changes = String(w.notes || "");
  if ("name" in w) {
    out.title = titled(row.title, cleanName(w.name));
    out.name = nameOf(out.title);
    out.label = dash(out.title);
  }
  return out;
}

/** Rows with their waiting edits laid on (a shoot's id may carry dashes). */
export function layEdits(rows, edits) {
  if (!isObject(edits) || !Object.keys(edits).length) return rows;
  return rows.map((r) => layEdit(r, edits[bareId(r.id)]));
}

/** What the record says the shoot is now, in the form `shootEditPlan` reads
 * a Notion row in: a stand-in for the row, so the same plan decides. */
function standIn(snap, edit) {
  const w = (edit && edit.want) || {};
  const start = "start" in w ? String(w.start || "") : String(snap.start || "");
  const end = "start" in w ? String(w.end || "") : String(snap.end || "");
  const title = "name" in w ? titled(snap.title, cleanName(w.name)) : String(snap.title || "");
  const notes = "notes" in w ? String(w.notes || "") : String(snap.changes || "");
  const text = (s) => [{ type: "text", plain_text: s, text: { content: s } }];
  return {
    Dates: { type: "date", date: start ? (end && end !== start ? { start, end } : { start }) : null },
    "What Changes": { type: "rich_text", rich_text: notes ? text(notes) : [] },
    Shoot: { type: "title", title: text(title) },
  };
}

const viewOf = (props) => {
  const [start, end] = datesOf(props, "Dates");
  return { start, end: end || start, notes: ((props["What Changes"] || {}).rich_text || []).map((t) => t.plain_text).join(""), name: nameOf(plainTitle(props)) };
};

/** A Notion Shoots row as the record's copy keeps it, or null if it is not on this project. */
function snapshotOf(project, page) {
  return shootsSnapshot(project, [page]).find((x) => x.id === bareId(page.id)) || null;
}

/**
 * One shoot edit, saved on the record. `null` when the project has no record
 * (the caller writes Notion, as before); else the answer in the Notion way's
 * shapes: `{ok, changed[, project_dates]}`, `{ok:false, moved}`, `{ok:false, why}`.
 * `row` is the project's Notion row (read to find the project; nothing else of
 * Notion is read unless the shoot is too new for the record's copy).
 */
export async function recordShootEdit(env, n, row, shootId, seen, changes) {
  const page = bareId(row.id);
  const sid = bareId(shootId);
  const { writeFacts } = await import("./facts.js");
  for (let tries = 0; tries < 3; tries++) {
    const record = await recordOf(env, page);
    if (!record) return null;
    const facts = isObject(record.facts) ? record.facts : {};
    const copy = isObject(facts.shoots) && Array.isArray(facts.shoots.value) ? facts.shoots.value : null;
    if (copy === null) return null;                                   // never linked: Notion's way
    const write = {};
    let snap = copy.find((x) => x.id === sid);
    if (!snap) {
      // a shoot newer than the record's copy (made since the last five-minute
      // look): its row is read once and added to the copy, then edited as any
      const fresh = await n.get(`pages/${shootId}`);
      snap = snapshotOf(page, fresh);
      if (!snap) return { ok: false, why: "That shoot isn't on this project." };
      write.shoots = { value: [...copy, snap], base: facts.shoots.v || 0 };
    }
    const edits = editsOf(facts);
    const waiting = edits[sid] || null;
    const stand = standIn(snap, waiting);
    const before = viewOf(stand);
    const [patch, moved, why] = shootEditPlan(stand, seen || {}, changes || {});
    if (why) return { ok: false, why };
    if (Object.keys(moved).length) return { ok: false, moved, why: "Changed since you opened it." };
    if (!Object.keys(patch).length) return { ok: true, changed: [] };

    const want = { ...((waiting && waiting.want) || {}) };
    const from = { ...((waiting && waiting.from) || {}) };
    const out = { ok: true, changed: Object.keys(patch).sort(), record: true };
    if (patch.Dates) {
      const when = patch.Dates.date || null;
      const s = when ? String(when.start || "") : "";
      const e = when && when.end ? String(when.end) : "";
      want.start = s; want.end = e;
      if (!("start" in from)) { from.start = before.start; from.end = before.end; }
    }
    if (patch["What Changes"]) {
      want.notes = String(changes.notes || "");
      if (!("notes" in from)) from.notes = before.notes;
    }
    const titleKey = Object.keys(patch).find((k) => k !== "Dates" && k !== "What Changes");
    if (titleKey) {
      want.name = cleanName(changes.name);
      if (!("name" in from)) from.name = before.name;
    }
    write[EDITS] = {
      value: { ...edits, [sid]: { want, from, at: new Date().toISOString() } },
      base: facts[EDITS] ? facts[EDITS].v || 0 : 0,
    };

    // The project's own Shoot Dates follow when they were this shoot's, as the
    // Notion way had it — on the record, where they are read from (a project
    // whose record has no Shoot Dates yet is left, not given a first one).
    const dates = isObject(facts.shoot_dates) && typeof facts.shoot_dates.value === "string" ? facts.shoot_dates : null;
    if (patch.Dates && dates) {
      const { splitDates } = await import("./notionlink.js");
      const [ps, pe] = splitDates(dates.value);
      if (ps === before.start && (pe || ps) === before.end) {
        const when = patch.Dates.date || null;
        const s = when ? String(when.start || "") : "";
        const e = when && when.end ? String(when.end) : "";
        write.shoot_dates = { value: !s ? "" : (e && e !== s ? `${s}/${e}` : s), base: dates.v || 0 };
        out.project_dates = true;
      }
    }
    const got = await writeFacts(env, page, write, "server");
    if (got.status === 200) return out;
    if (got.status !== 409) return { ok: false, why: got.problem || "The record could not be written. Try again." };
  }
  return { ok: false, why: "The record kept changing. Try again." };
}

/**
 * The waiting edits, held to Notion as it is now: [{id, patch|null, note}] —
 * what the look should write to which row, and what to say. `rowOf(id)`
 * reads one Shoots row's properties.
 */
export async function planPush(edits, rowOf) {
  const out = [];
  for (const [id, edit] of Object.entries(edits)) {
    if (!isObject(edit) || !isObject(edit.want)) { out.push({ id, patch: null, note: "dropped (not an edit)" }); continue; }
    let props;
    try {
      props = await rowOf(id);
    } catch (e) {
      out.push({ id, wait: true, note: `kept for the next look (${(e && e.message) || e})` });
      continue;
    }
    const [patch, moved, why] = shootEditPlan(props, edit.from || {}, edit.want);
    if (why) out.push({ id, patch: null, note: `dropped: ${why}` });
    else if (Object.keys(moved).length) out.push({ id, patch: null, note: `dropped: changed in Notion first (${Object.keys(moved).join(", ")}); Notion's stays` });
    else out.push({ id, landed: true, patch: Object.keys(patch).length ? patch : null, note: Object.keys(patch).length ? "written to Notion" : "already in Notion" });
  }
  return out;
}
