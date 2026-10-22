/**
 * A world held in memory for the big moves' checks (bigmoves.mjs,
 * drivemoves.mjs): a bucket with etags, a Notion stand-in, a Google Drive
 * stand-in with parents and a trash, and a Mac jobs list.
 */

export const nowFixed = new Date("2026-10-15T19:00:00Z");

export function bucketOf() {
  const objects = new Map();          // key -> {body, etag}
  let tag = 0;
  const writes = [];
  const wrap = (k, o) => ({
    key: k, etag: String(o.etag), body: o.body, httpMetadata: {}, customMetadata: {},
    async json() { return JSON.parse(o.body); }, async text() { return o.body; },
  });
  const bucket = {
    objects, writes,
    async get(k) { const o = objects.get(k); return o ? wrap(k, o) : null; },
    async head(k) { const o = objects.get(k); return o ? { key: k, etag: String(o.etag) } : null; },
    async put(k, v, opts = {}) {
      const cur = objects.get(k);
      const only = opts.onlyIf || {};
      if (only.etagMatches !== undefined && (!cur || String(cur.etag) !== String(only.etagMatches))) return null;
      if (only.etagDoesNotMatch === "*" && cur) return null;
      const body = typeof v === "string" ? v : v && typeof v.text === "function" ? await v.text() : String(v);
      objects.set(k, { body, etag: ++tag });
      writes.push(k);
      return { key: k, etag: String(tag) };
    },
    async delete(k) { for (const key of Array.isArray(k) ? k : [k]) { objects.delete(key); writes.push(`-${key}`); } },
    async list({ prefix = "", cursor, limit = 1000, delimiter } = {}) {
      const keys = [...objects.keys()].filter((x) => x.startsWith(prefix)).sort();
      if (delimiter) {
        const pre = new Set();
        const objs = [];
        for (const key of keys) {
          const rest = key.slice(prefix.length);
          const at = rest.indexOf(delimiter);
          if (at >= 0) pre.add(prefix + rest.slice(0, at + 1)); else objs.push({ key, size: objects.get(key).body.length });
        }
        return { objects: objs, delimitedPrefixes: [...pre], truncated: false };
      }
      const from = cursor ? Number(cursor) : 0;
      const page = keys.slice(from, from + limit);
      const more = from + limit < keys.length;
      return { objects: page.map((key) => ({ key, size: objects.get(key).body.length })), delimitedPrefixes: [], truncated: more, cursor: more ? String(from + limit) : undefined };
    },
  };
  return bucket;
}

const rich = (t) => [{ plain_text: t, text: { content: t } }];

export function notionOf() {
  const pages = new Map();
  const calls = [];
  let failOn = null;
  const n = {
    pages, calls,
    failNext(fn) { failOn = fn; },
    outage: null,        // () => the error every call throws (a refused key: a Handoff), while set
    async get(path) {
      calls.push(["GET", path]);
      if (n.outage) throw n.outage();
      const id = path.replace(/^pages\//, "");
      const p = pages.get(id) || pages.get(id.replace(/-/g, ""));
      if (!p) { const e = new Error("Notion: object_not_found"); e.code = 404; throw e; }
      return JSON.parse(JSON.stringify(p));
    },
    async patch(path, body) {
      calls.push(["PATCH", path, body]);
      if (n.outage) throw n.outage();
      if (failOn && failOn(path, body)) { failOn = null; throw new Error("Notion: planted failure"); }
      const id = path.replace(/^pages\//, "");
      const p = pages.get(id);
      if (!p) throw new Error("Notion: object_not_found");
      if (body.in_trash !== undefined) p.in_trash = body.in_trash;
      for (const [k, v] of Object.entries(body.properties || {})) {
        const t = p.properties[k] && p.properties[k].type;
        if (v.title) p.properties[k] = { type: "title", title: v.title.map((x) => ({ plain_text: x.text.content, text: x.text })) };
        else p.properties[k] = { type: t || Object.keys(v)[0], ...v };
      }
      return p;
    },
    async post(path, body) {
      calls.push(["POST", path, body]);
      if (n.outage) throw n.outage();
      const f = (body && body.filter) || {};
      const want = f.relation && f.relation.contains;
      const out = [...pages.values()].filter((p) => !p.in_trash && p.source === path.split("/")[1]
        && (!want || ((p.properties[f.property] || {}).relation || []).some((r) => r.id.replace(/-/g, "") === want.replace(/-/g, ""))));
      return { results: JSON.parse(JSON.stringify(out)), has_more: false };
    },
  };
  n.addProject = (id, { name, status = "Active", drive = "", website = "", dates = null }) => {
    pages.set(id, { id, object: "page", source: "feedface-0000-4000-8000-000000000001", in_trash: false, properties: {
      Project: { type: "title", title: rich(name) }, Status: { type: "select", select: { name: status } },
      "Drive Folder": { type: "url", url: drive || null }, Website: { type: "url", url: website || null },
      "Shoot Dates": { type: "date", date: dates },
    } });
  };
  n.addShoot = (id, project, { title, start, end = "", status = "Upcoming" }) => {
    pages.set(id, { id, object: "page", source: "feedface-0000-4000-8000-000000000002", in_trash: false, properties: {
      Name: { type: "title", title: rich(title) }, Status: { type: "select", select: { name: status } },
      Dates: { type: "date", date: { start, ...(end ? { end } : {}) } }, Project: { type: "relation", relation: [{ id: project }] },
    } });
  };
  n.status = (id) => (((pages.get(id) || {}).properties || {}).Status || {}).select?.name || "";
  n.title = (id) => ((((pages.get(id) || {}).properties || {}).Project || {}).title || []).map((t) => t.plain_text).join("");
  return n;
}

export function driveOf() {
  const items = new Map();
  let seq = 0;
  const calls = [];
  let failOn = null;
  const id = () => `fake${String(++seq).padStart(10, "0")}`;
  const it = (x) => (x ? { id: x.id, name: x.name, folder: x.folder, mime: x.folder ? "application/vnd.google-apps.folder" : "text/plain", trashed: x.trashed, parents: [x.parent].filter(Boolean) } : null);
  const d = {
    items, calls,
    failNext(fn) { failOn = fn; },
    add(parent, name, folder = true, fixed = "") {
      const x = { id: fixed || id(), name, folder, parent, trashed: false };
      items.set(x.id, x);
      return x.id;
    },
    path(i) {
      const parts = [];
      for (let x = items.get(i); x; x = items.get(x.parent)) parts.unshift(x.name);
      return parts.join("/");
    },
    tree(top) {
      const out = [];
      const walk = (p, pre) => { for (const x of [...items.values()].filter((y) => y.parent === p).sort((a, b) => (a.name < b.name ? -1 : 1))) { out.push(`${pre}${x.name}${x.folder ? "/" : ""}${x.trashed ? " (trash)" : ""}`); if (x.folder) walk(x.id, `${pre}${x.name}/`); } };
      walk(top, "");
      return out;
    },
    async get(i) { calls.push(["get", i]); return it(items.get(i)); },
    async list(parent) { calls.push(["list", parent]); return [...items.values()].filter((x) => x.parent === parent && !x.trashed).map(it); },
    async text(i) { return (items.get(i) || {}).text || ""; },
  };
  const write = (op) => async (...a) => {
    calls.push([op, ...a]);
    if (failOn && failOn(op, ...a)) { failOn = null; throw new Error(`Google Drive answered 500: planted failure on ${op}`); }
    if (op === "rename") { items.get(a[0]).name = a[1]; return it(items.get(a[0])); }
    if (op === "move") { const x = items.get(a[0]); if (x.parent !== a[1]) throw new Error("wrong from"); x.parent = a[2]; return it(x); }
    if (op === "trash") { items.get(a[0]).trashed = true; return it(items.get(a[0])); }
    if (op === "untrash") { items.get(a[0]).trashed = false; return it(items.get(a[0])); }
    if (op === "mkdir") return it(items.get(d.add(a[0], a[1], true)));
    if (op === "mkfile") { const made = d.add(a[0], a[1], false); items.get(made).text = a[2]; return it(items.get(made)); }
    return null;
  };
  for (const op of ["rename", "move", "trash", "untrash", "mkdir", "mkfile"]) d[op] = write(op);
  return d;
}

export function jobsOf() {
  const list = [];
  return {
    READY: true, list,
    async addJob(env, job) { const j = { id: `job${list.length + 1}`, state: "waiting", ...job }; list.push(j); return j; },
    async cancelJobs(env, { move_id }) {
      let cancelled = 0, running = 0;
      for (const j of list) if (j.move_id === move_id) { if (j.state === "running") running += 1; else if (j.state === "waiting") { j.state = "cancelled"; cancelled += 1; } }
      return { cancelled, running };
    },
    async jobsFor(env, { move_id }) { return list.filter((j) => j.move_id === move_id); },
  };
}

/**
 * The standing world: a real cinematography tree and a scratch folder, a
 * scratch test project "zz step7 test" (two shoots, selects with two PNGs,
 * a showcase, a film and a portal) and a real project for the refusals.
 */
export function standing() {
  const drive = driveOf();
  const BUCKET = bucketOf();
  const n = notionOf();
  const cine = drive.add(null, "cinematography", true, "cineRoot000001");
  const projects = drive.add(cine, "projects", true, "projRoot000001");
  const gigs = drive.add(cine, "gigs", true, "gigsRoot000001");
  const portfolio = drive.add(cine, "portfolio", true, "portRoot000001");
  const showcases = drive.add(portfolio, "project-showcases", true, "showRoot000001");
  const outside = drive.add(null, "Somebody Else", true, "outside0000001");
  const scratch = drive.add(cine, "zz-step7-scratch", true, "scratch0000001");
  const sp = drive.add(scratch, "projects");
  drive.add(scratch, "gigs");
  const spf = drive.add(scratch, "portfolio");
  const ssc = drive.add(spf, "project-showcases");
  const pdir = drive.add(sp, "zz-step7-test", true, "testFolder0001");
  const post = drive.add(pdir, "3-post");
  const s1 = drive.add(post, "shoot-1");
  const sel = drive.add(s1, "selects");
  drive.add(sel, "A001_1.2.3.png", false);
  drive.add(sel, "A001_01034821.png", false);
  drive.add(pdir, "1-creative");
  drive.add(pdir, ".gdrive-project", false);
  const show = drive.add(ssc, "zz-step7-test-showcase", true, "testShow000001");
  drive.add(show, "stills");
  drive.add(drive.items.get(show).id, ".portfolio-project", false);
  const real = drive.add(projects, "real-one", true, "realFolder0001");
  drive.add(real, "1-creative");
  const P = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa01";
  const R = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb02";
  const RELAY = "cccccccccccccccccccccccccccccc03";
  n.addProject(P, { name: "zz step7 test", status: "Active", drive: `https://drive.google.com/drive/folders/${pdir}`, website: "https://your-website.example/zz", dates: { start: "2026-10-01" } });
  n.addShoot("dddddddddddddddddddddddddddddd11", P, { title: "zz step7 test — Shoot 1", start: "2026-10-01", status: "Upcoming" });
  n.addShoot("dddddddddddddddddddddddddddddd12", P, { title: "zz step7 test — Shoot 2", start: "2026-11-04", end: "2026-11-05", status: "Upcoming" });
  n.addProject(R, { name: "Real One", status: "Active", drive: `https://drive.google.com/drive/folders/${real}` });
  const record = (page, name, slug, extra = {}) => JSON.stringify({ version: 1, page, name, slug, stage: "Active",
    facts: { title: { value: name, v: 1 }, status: { value: "Active", v: 1 } }, ...extra });
  BUCKET.objects.set(`r/${P}/record.json`, { body: record(P, "zz step7 test", "zz-step7-test", {
    film: { title: "zz step7 test", relay: RELAY, shots: 14, scenes: 3 }, media: [{ drive: "zz-scratch-media", size: "1 GB" }],
    drive: { where: "projects/", name: "zz-step7-test" }, portal: { share: { people: 2 } } }), etag: 1 });
  BUCKET.objects.set(`r/${R}/record.json`, { body: record(R, "Real One", "real-one"), etag: 1 });
  for (const [k, v] of [[`p/${RELAY}/manifest.json`, "{}"], [`p/${RELAY}/logs/0123456789abcdef-0123456789abcdef.log`, "log"],
    [`p/${RELAY}/people.json`, JSON.stringify({ people: [{ email: "a@b.c" }], links: [{ key: "k1" }], invites: [] })],
    [`p/${RELAY}/front.json`, JSON.stringify({ title: "zz step7 test" })], ["p/eeeeeeeeeeeeeeeeeeeeeeeeeeeeee99/people.json", "{}"]]) {
    BUCKET.objects.set(k, { body: v, etag: 1 });
  }
  BUCKET.objects.set("s/bigmoves.json", { body: JSON.stringify({ wrap: "scratch", archive: "scratch", movedrive: "scratch", rename: "scratch", turnoff: "scratch", delete: "scratch", showcase: "scratch", scratch }), etag: 1 });
  const jobs = jobsOf();
  const env = { BUCKET, NOTION_TOKEN: "checking" };
  const world = (extra = {}) => ({ env, n, raw: drive, create: drive, driveSettings: { roots: { projects, gigs, showcases }, scratch: null },
    jobs, now: () => nowFixed, by: "check", filmBackup: false, ...extra });
  return { drive, BUCKET, n, env, jobs, world, ids: { cine, projects, gigs, showcases, portfolio, scratch, sp, ssc, pdir, show, sel, real, outside, P, R, RELAY } };
}
