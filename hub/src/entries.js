/**
 * **Spec-sheet fields with more than one entry** (2026-10-05) — `entries.py`
 * in Projects Console, the other reader of the same words. Change one,
 * change both; the shared cases are `hub/spec-cases.json` (a copy of the
 * console's), checked by `hub/entries.mjs` and checks.sh.
 *
 * Every text field of a Camera Spec Sheet holds one entry per line with an
 * optional label before a colon ("A Cam: Alexa 35"). Cameras come from the
 * Camera field; a labelled line in another field is that camera's, an
 * unlabelled one every camera's — Frame Rate too, since it became text
 * (2026-10-05; a Notion number reads as one unlabelled line). A LUT's label is a line in "LUT Labels"
 * ("Show LUT: file.cube", a link by its address), matched by name.
 */

const LABEL = /^([^:—–\n]{1,24}?):\s+(\S.*)$/;
const NUMBERS = /^[\d.,\s/&x×–-]*(?:mm)?$/i;

/** The sheet's fields a camera can differ in: [Notion property, the page's word, the card's box]. */
export const CAMERA_FIELDS = [
  ["Camera", "Camera", "body"],
  ["Shooting Format", "Shooting format", "format"],
  ["Capture Resolution", "Capture resolution", "capture"],
  ["Codec", "Codec", "codec"],
  ["Color Space", "Colour space", "colour"],
  ["Desqueeze", "Desqueeze", "desqueeze"],
  ["Frame Guides", "Frame guides", "guides"],
  ["Finishing Resolution", "Target finishing", "finishing"],
  ["Frame Rate", "Frame rate", "fps"],
];

/** The record fact naming each camera body ("Alexa 35" → "A Cam"). Notion
 * only lists the bodies (his ruling, 2026-10-13); the grouping is ours. */
export const CAMERA_LABELS = "camera_labels";

/** A spec sheet property as text — `entries.field_text`. The sheet's fields
 * became pills (multi-select, 2026-10-13): a pill reads as one line, so every
 * reader that took a line as an entry takes a pill the same way. */
export function fieldText(field) {
  const f = field || {};
  const kind = f.type || "";
  if (kind === "rich_text" || kind === "title") return (f[kind] || []).map((t) => t.plain_text || "").join("");
  if (kind === "multi_select") return (f.multi_select || []).map((o) => o.name || "").filter(Boolean).join("\n");
  if (kind === "select") return (f.select || {}).name || "";
  if (kind === "number") return f.number == null ? "" : String(f.number);
  return "";
}

/** Pill names from text — `entries.pills_of`: one per line, a comma made a
 * space (Notion refuses one in an option), repeats dropped. */
export function pillsOf(text) {
  const out = [], seen = new Set();
  for (const line of Array.isArray(text) ? text.map(String) : String(text || "").split("\n")) {
    const name = line.replace(/,/g, " ").split(/\s+/).filter(Boolean).join(" ").slice(0, 100);
    if (name && !seen.has(name.toLowerCase())) { seen.add(name.toLowerCase()); out.push(name); }
  }
  return out;
}

/** Camera lines without their labels — `entries.bodies_of`: Notion holds
 * only the body; the label is the record's. */
export function bodiesOf(text) {
  return entries(text).map((e) => e.value).filter(Boolean).join("\n");
}

/** The labels Camera lines carry: {"Alexa 35": "A Cam"} — `entries.labels_of`. */
export function labelsOf(text) {
  return Object.fromEntries(entries(text).filter((e) => e.label && e.value).map((e) => [e.value, e.label]));
}

/** The Camera pills with the record's labels put on ("A Cam: Alexa 35") —
 * `entries.labelled_cameras` — so the camera grouping reads as it always has. */
export function labelledCameras(text, labels) {
  const by = new Map(Object.entries(labels && typeof labels === "object" ? labels : {})
    .filter(([, v]) => String(v || "").trim()).map(([k, v]) => [String(k).toLowerCase(), String(v)]));
  return entries(text).map((e) => {
    const label = by.get(e.value.toLowerCase()) || e.label;
    return label && label !== e.label ? `${label}: ${e.value}` : e.raw;
  }).join("\n");
}

/** [label, rest] — ["", line] when the line has no label. */
export function splitLabel(line) {
  const s = String(line || "").trim();
  const m = LABEL.exec(s);
  if (!m) return ["", s];
  const label = m[1].trim();
  if (label.split(/\s+/).length > 4 || NUMBERS.test(label) || !/[A-Za-z]/.test(label)) return ["", s];
  return [label, m[2].trim()];
}

/** A field as its entries: [{label, value, raw}], blank lines skipped. */
export function entries(text) {
  return String(text || "").split("\n").filter((line) => line.trim()).map((line) => {
    const [label, value] = splitLabel(line);
    return { label, value, raw: line.trim() };
  });
}

/** How labels are matched: "A-Camera" = "A Cam". */
export function labelKey(label) {
  return String(label || "").toLowerCase().replace(/[^a-z0-9]/g, "").replace("camera", "cam");
}

/** The sheet as cameras — `entries.cameras`. `fields` by Notion property;
 * `lensSets` as lenses.js reads them (each with `label` and `raw`). */
export function cameras(fields, lensSets = []) {
  const body = entries(fields.Camera);
  const multi = body.length > 1;
  const cams = (body.length ? body : [{ label: "", value: "" }]).map((e) => ({ label: e.label, name: e.value, fields: {}, lenses: [] }));
  const find = (label) => {
    const k = labelKey(label);
    if (!k) return null;
    // "FX3: …" for the camera called "Sony FX3"
    return cams.find((c) => k === labelKey(c.label) || k === labelKey(c.name))
      || cams.find((c) => k.length >= 3 && labelKey(c.name).includes(k)) || null;
  };
  const shared = {};
  const unmatched = [];
  for (const [prop] of CAMERA_FIELDS) {
    if (prop === "Camera") continue;
    const text = String(fields[prop] ?? "");
    const common = [];
    for (const e of entries(text)) {
      const c = multi ? find(e.label) : null;
      if (c) c.fields[prop] = prop in c.fields ? `${c.fields[prop]}\n${e.value}` : e.value;
      else if (e.label && multi) unmatched.push({ key: prop, label: e.label, value: e.value });
      else common.push(multi ? e.value : e.raw);
    }
    shared[prop] = common.join("\n");
  }
  const lensesShared = [];
  for (const s of lensSets || []) {
    const c = multi ? find(s.label) : null;
    if (c) c.lenses.push(s); else lensesShared.push(s);
  }
  for (const c of cams) c.fields.Camera = c.name;
  return { multi, cameras: cams, shared, lenses_shared: lensesShared, unmatched };
}

/** A card's camera boxes by Notion property. */
export function fieldsOfCard(camera) {
  return Object.fromEntries(CAMERA_FIELDS.map(([prop, , box]) => [prop, (camera || {})[box] || ""]));
}

/** What a LUT Labels line names a file by: its name, or a link's address. */
export function lutKey(file) {
  const name = String(file.name || "");
  return name && !name.startsWith("http") ? name : String(file.url || "");
}

function fromAddress(url) {
  const m = /^https?:\/\/(?:www\.)?([^/?#]+)/.exec(url || "");
  const host = m ? m[1] : "";
  if (/drive\.google|docs\.google/.test(host)) return "Drive link";
  return host || "Link";
}

/** LUT rows with their labels — `entries.luts`: {rows, stray}. */
export function luts(files, labelsText) {
  const lines = entries(labelsText);
  const used = new Set();
  const rows = (files || []).map((f) => {
    // by its name, or a link by its address (the portal names a link after
    // the column it came from)
    const keys = new Set([lutKey(f), f.url || ""].map((k) => k.trim().toLowerCase()).filter(Boolean));
    let label = "";
    for (let i = 0; i < lines.length; i++) {
      const e = lines[i];
      if (!used.has(i) && e.label && keys.has(e.value.trim().toLowerCase())) { label = e.label; used.add(i); break; }
    }
    const name = String(f.name || "");
    return { ...f, label, shown: name && !name.startsWith("http") ? name : fromAddress(f.url) };
  });
  return { rows, stray: lines.filter((_, i) => !used.has(i)).map((e) => e.raw) };
}

const SPLIT_CAMERAS = /\s+\/\s+|\s*;\s*|\s+\+\s+|\s*&\s*/;

/** "FX3 / FX6" → "A Cam: FX3\nB Cam: FX6" (a suggestion; never written). */
export function suggestCameras(text) {
  const es = entries(text);
  if (es.length !== 1 || es[0].label) return String(text || "");
  const parts = es[0].value.split(SPLIT_CAMERAS).map((p) => p.trim()).filter(Boolean);
  if (parts.length < 2) return String(text || "");
  return parts.slice(0, 8).map((p, i) => `${String.fromCharCode(65 + i)} Cam: ${p}`).join("\n");
}

// ── writing (2026-10-10): the server answers the phone's spec-sheet edits
// itself now, so `entries.py`'s writing half is here too. Same rules.

export const LUT_FILES = "Production LUT";
export const LUT_LABELS = "LUT Labels";

const squash = (s) => String(s == null ? "" : s).split(/\s+/).filter(Boolean).join(" ");

/** An entry as its line; an untouched one exactly as typed — `format_entry`. */
export function formatEntry(e) {
  if (e.raw && !e.edited) return String(e.raw).trim();
  const value = squash(e.value);
  const label = squash(String(e.label == null ? "" : e.label).replace(/:/g, " "));
  if (label && value) return `${label}: ${value}`;
  return value || "";
}

/** Entries back to the field's text; empty ones dropped — `write`. */
export function writeEntries(list) {
  return (list || []).filter((e) => e && typeof e === "object" && !Array.isArray(e))
    .map(formatEntry).filter((x) => x.trim()).join("\n");
}

/** The Production LUT files: [{name, url, link}] — `lut_files`. */
export function lutFiles(prop) {
  return ((prop || {}).files || []).map((f) => {
    const link = f.type === "external";
    const url = ((link ? f.external : f.file) || {}).url || "";
    const name = String(f.name || "").trim() || url;
    return { name, url, link };
  });
}

/** The LUT Labels text for rows with labels — `lut_labels_text`. */
export function lutLabelsText(rows) {
  return (rows || []).filter((r) => String(r.label || "").trim())
    .map((r) => `${squash(String(r.label).replace(/:/g, " "))}: ${lutKey(r)}`).join("\n");
}

/** [new Production LUT value, why] — `luts_plan`. */
export function lutsPlan(files, remove = "", add = null) {
  const kept = files.filter((f) => !(remove && lutKey(f) === remove));
  if (remove && kept.length === files.length) return [null, "That LUT is already gone."];
  const held = kept.filter((f) => !f.link);
  if (held.length) {
    return [null, held.length === 1 ? `Notion keeps ${held[0].name} itself, so this list changes in Notion.`
      : "Notion keeps these files itself, so this list changes in Notion."];
  }
  const out = kept.map((f) => ({ name: f.name || f.url, type: "external", external: { url: f.url } }));
  if (add) {
    const url = String(add.url || "").trim();
    if (!/^https?:\/\/\S+$/.test(url)) return [null, "A LUT is added as a link (https://…) — a Drive copy, say."];
    if (kept.some((f) => f.url === url)) return [null, "That link is already there."];
    const name = squash(add.name).slice(0, 100) || url;
    out.push({ name, type: "external", external: { url } });
  }
  return [out, ""];
}

/** Whether any line of the sheet carries a label — the `labelled` that
 * `entries.cameras` answers beside the cameras. */
export function sheetLabelled(fields) {
  if (entries((fields || {}).Camera).some((e) => e.label)) return true;
  return CAMERA_FIELDS.some(([prop]) => prop !== "Camera"
    && String((fields || {})[prop] ?? "").split("\n").some((line) => splitLabel(line)[0]));
}
