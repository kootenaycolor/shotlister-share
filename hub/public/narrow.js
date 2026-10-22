/**
 * A filtered shot list, cut down to what one link may see.
 *
 * His ask, 2026-10-02: *"I need a way to be able to share certain views on a
 * web portal. For example, only the techs' shots … Share only the filter view
 * of a shot list to send to people."*
 *
 * **One file, read by both halves.** The page narrows his own Shot List with
 * `keeps` (`public/film.js`), and the worker narrows a view link's with the
 * same function (`src/views.js`), so a filter on his screen and the link he
 * makes from it cannot come to mean two different things. Imported by the
 * worker from here, as `boardpatch.js` is.
 *
 * **The cut is the server's, not the page's.** Every other link hands the
 * browser the whole film and lets it draw what it may; a view link is handed
 * `lensModel` and nothing else — no change logs, no other scenes, no script,
 * no locations, no boards. A filter that only hid things in the browser would
 * be a stylesheet away from the rest of the film, the trap Visibility was
 * built to refuse.
 */

/** What a value is called on screen: a record by its label, a word as itself. */
export function named(value) {
  if (!value) return "";
  if (typeof value === "string") return value;
  return String(value.label || value.title || value.name || "");
}

/**
 * Does this shot carry every value picked? Values of one field are any-of;
 * different fields are all-of — *Tags: Crane or Steadicam, and Camera: B*.
 *
 * `facets` is `[[field, value], …]`, the shape `asking.facets` keeps.
 */
export function keeps(row, facets) {
  if (!facets || !facets.length) return true;
  const wanted = new Map();
  for (const [f, v] of facets) {
    if (!wanted.has(f)) wanted.set(f, new Set());
    wanted.get(f).add(v);
  }
  for (const [field, values] of wanted) {
    let got = row[field];
    if (got === undefined && row.custom) got = row.custom[field];
    const said = (Array.isArray(got) ? got : [got]).map((one) => named(one).trim());
    if (!said.some((one) => values.has(one))) return false;
  }
  return true;
}

/**
 * What the film may say about itself on a view link. **Named, not stripped**:
 * the project carries the paths of his Drive folder and his spreadsheet, and
 * anything added to it later stays off a link until somebody adds it here.
 */
const PROJECT_SAYS = [
  "id", "title", "director", "producer", "kind", "client", "agency",
  "ratio", "markPath", "markColour", "defaultPriority", "docStyle", "docStyleSaid",
];

/** A scene's own words that belong to other pages: its script, notes, references, boards. */
const SCENE_KEEPS_BACK = ["script", "notes", "notesRich", "attachments", "boardIds"];

/**
 * The engine's view of the film, cut to one view's shots.
 *
 * `view` is `{ facets, name }`. The rows kept are the ones `keeps` keeps,
 * outside archived scenes; the scenes, days and sequences kept are only the
 * ones those rows stand in. Everything else the film holds is left out.
 */
export function lensModel(model, view) {
  const m = model || {};
  const facets = (view && view.facets) || [];
  const shelved = new Set((m.scenes || []).filter((s) => s && s.archived).map((s) => s.id));
  const groups = [];
  for (const g of m.groups || []) {
    if (m.groupBy !== "day" && shelved.has(g.key)) continue;
    const rows = (g.rows || []).filter((r) => !shelved.has(r.sceneId) && keeps(r, facets));
    if (rows.length) groups.push({ ...g, rows, count: rows.length });
  }
  const rows = groups.flatMap((g) => g.rows);
  const sceneIds = new Set(rows.map((r) => r.sceneId));
  const dayIds = new Set(rows.map((r) => r.dayId).filter(Boolean));
  if (m.groupBy === "day") for (const g of groups) dayIds.add(g.key);
  const sequenceIds = new Set(rows.map((r) => r.sequenceId).filter(Boolean));

  const scenes = (m.scenes || []).filter((s) => sceneIds.has(s.id)).map((s) => {
    const out = { ...s };
    for (const key of SCENE_KEEPS_BACK) delete out[key];
    if (s.sequence && s.sequence.id) sequenceIds.add(s.sequence.id);
    out.count = rows.filter((r) => r.sceneId === s.id).length;
    return out;
  });
  const project = {};
  for (const key of PROJECT_SAYS) if (m.project && key in m.project) project[key] = m.project[key];
  project.readOnly = true;
  project.unsaved = 0;

  return {
    project,
    columns: m.columns || [],
    fieldLabels: m.fieldLabels || {},
    units: m.units || [],
    scripts: [],
    sequences: (m.sequences || []).filter((q) => sequenceIds.has(q.id)),
    locations: [],
    boards: [],
    days: (m.days || []).filter((d) => dayIds.has(d.id)),
    plans: [],
    scenes,
    filter: {
      ...(m.filter || {}),
      narrowed: true,
      shown: rows.length,
      hiddenScenes: 0,
      hiddenSceneIds: [],
    },
    groupBy: m.groupBy || "scene",
    groups,
  };
}

/** A view's name as the readable half of its address: `Crane Shots` → `crane-shots`. */
export function viewSlug(name) {
  return String(name || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40).replace(/-+$/, "") || "view";
}
