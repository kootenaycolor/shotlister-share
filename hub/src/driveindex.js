/**
 * **A drive's index, written by the server** (stage 5 step 7, piece A).
 *
 * engine.upsert_volume_index, ported rule for rule: the R112 split already
 * made the Mac's half a pure read (`engine.scan_volume_full`), so an `index`
 * job has the Mac scan the drive and send the scan, and this writes it into
 * Notion: Drive Contents (a row per folder, the drive added to its Drive
 * list, Year and Size filled in; a row that names this drive but whose
 * folder is gone loses the drive, and is archived when that leaves it on no
 * drive), and the drive's free space in Drive Overview (a row made if it
 * has none). Nothing here touches a drive.
 */

import { notionOf } from "./cloud.js";

/** engine.DRIVES_CONTENT_DB / DRIVES_OVERVIEW_DB, as data sources (2025-09-03). */
export const CONTENT = "86d77bbd-736b-829e-e17a-12ac039c951f";
export const OVERVIEW = "ca3d58da-789e-860a-8b48-24416ddb0aee";

/** engine.fmt_bytes */
export function fmtBytes(n) {
  let v = Number(n) || 0;
  for (const unit of ["B", "KB", "MB", "GB"]) {
    if (v < 1000) return `${Math.round(v)} ${unit}`;
    v /= 1000;
  }
  return v < 100 ? `${v.toFixed(1)} TB` : `${Math.round(v)} TB`;
}

const plainTitle = (props) => {
  for (const p of Object.values(props || {})) if (p && p.type === "title") return (p.title || []).map((t) => t.plain_text || "").join("");
  return "?";
};
const select = (props, name) => ((props[name] || {}).select || {}).name || "";
const multi = (props, name) => ((props[name] || {}).multi_select || []).map((o) => o.name);
const text = (props, name) => ((props[name] || {}).rich_text || []).map((t) => t.plain_text || "").join("");
const rich = (s) => ({ rich_text: [{ text: { content: s } }] });

async function queryAll(n, source) {
  const out = [];
  let cursor;
  for (let i = 0; i < 200; i++) {
    const got = await n.post(`data_sources/${source}/query`, { page_size: 100, ...(cursor ? { start_cursor: cursor } : {}) });
    out.push(...(got.results || []));
    if (!got.has_more) break;
    cursor = got.next_cursor;
  }
  return out;
}

/** upsert_volume_index(scan, token, reporter) → the summary line. */
export async function upsertVolumeIndex(env, scan, { reporter = "", notion = null } = {}) {
  const n = notion || notionOf(env);
  const volName = String(scan.volume), short = String(scan.short || scan.volume);
  const entries = (scan.entries || []).map((e) => [String(e.name), e.parent || null, e.year || null]);
  const sizes = {};
  for (const e of scan.entries || []) sizes[String(e.name).toLowerCase()] = e.size || "";

  const existing = new Map();
  for (const page of await queryAll(n, CONTENT)) {
    const props = page.properties || {};
    existing.set(plainTitle(props).toLowerCase(), {
      page_id: page.id, drives: multi(props, "Drive"), parent: select(props, "Parent Folder"),
      year: text(props, "Year"), size: text(props, "Size"),
    });
  }
  const found = new Set(entries.map(([name]) => name.toLowerCase()));
  let created = 0, updated = 0, unchanged = 0, pruned = 0;
  for (const [name, parent, year] of entries) {
    const sizeTxt = sizes[name.toLowerCase()] || "";
    const row = existing.get(name.toLowerCase());
    if (!row) {
      const props = { "Folder Name": { title: [{ text: { content: name } }] }, Drive: { multi_select: [{ name: short }] } };
      if (parent) props["Parent Folder"] = { select: { name: parent } };
      if (year) props.Year = rich(year);
      if (sizeTxt) props.Size = rich(sizeTxt);
      await n.post("pages", { parent: { type: "data_source_id", data_source_id: CONTENT }, properties: props });
      created += 1;
    } else {
      const patch = {};
      if (!row.drives.includes(short)) patch.Drive = { multi_select: [...row.drives, short].map((d) => ({ name: d })) };
      if (year && !row.year) patch.Year = rich(year);
      if (sizeTxt && sizeTxt !== row.size) patch.Size = rich(sizeTxt);
      if (Object.keys(patch).length) { await n.patch(`pages/${row.page_id}`, { properties: patch }); updated += 1; }
      else unchanged += 1;
    }
  }
  for (const [lname, row] of existing) {
    if (row.drives.includes(short) && !found.has(lname)) {
      const remaining = row.drives.filter((d) => d !== short);
      if (remaining.length) await n.patch(`pages/${row.page_id}`, { properties: { Drive: { multi_select: remaining.map((d) => ({ name: d })) } } });
      else await n.patch(`pages/${row.page_id}`, { archived: true });
      pruned += 1;
    }
  }
  const freeTxt = fmtBytes(scan.free_bytes);
  let hit = null;
  for (const page of await queryAll(n, OVERVIEW)) {
    if (plainTitle(page.properties).toLowerCase() === volName.toLowerCase()) { hit = page; break; }
  }
  if (hit) {
    await n.patch(`pages/${hit.id}`, { properties: { "Avaliable Space": rich(freeTxt) } });
  } else {
    const props = { title: { title: [{ text: { content: volName } }] }, "Avaliable Space": rich(freeTxt) };
    if (scan.total_bytes) props["Capacity (TB)"] = { number: Math.round(scan.total_bytes / 1e11) / 10 };
    if (scan.serial) props["Serial Number"] = rich(String(scan.serial));
    await n.post("pages", { parent: { type: "data_source_id", data_source_id: OVERVIEW }, properties: props });
  }
  const via = reporter ? ` (via ${reporter})` : "";
  return `${volName}${via}: ${created} added, ${updated} updated, ${pruned ? `${pruned} pruned, ` : ""}${unchanged} already current · ${freeTxt} free`;
}
