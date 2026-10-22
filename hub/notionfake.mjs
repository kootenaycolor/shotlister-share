#!/usr/bin/env node
/**
 * A small Notion, on this machine, for `checks.sh` — Ref 1155.
 *
 * The portal's own Refresh from Notion (`src/notion.js`) cannot be checked
 * against his real workspace: the portal's key is his to make, and the
 * battery must never read his Notion. So it is checked against this — one
 * project, one crew member, one ticked page and one ticked link, one spec
 * sheet — answering only the calls `notion.js` makes, in Notion's own shapes.
 *
 * It refuses any call without the checking token, so a pass also proves the
 * key is sent. `src/notion.js` honours `NOTION_API` only when it points here.
 *
 *     node hub/notionfake.mjs 8795
 */
import { createServer } from "node:http";

const PORT = Number(process.argv[2] || 8795);
const TOKEN = "checking-notion-token";
const HERE = `http://127.0.0.1:${PORT}`;

const PROJECTS = "feedface-0000-4000-8000-000000000001";
const PROJECT_DOCS = "feedface-0000-4000-8000-000000000005";
const CAMERA_SHEETS = "feedface-0000-4000-8000-000000000003";
const CREW = "feedface-0000-4000-8000-000000000004";
const SHOOTS = "feedface-0000-4000-8000-000000000002";
// `node notionfake.mjs <port> no-shoots` refuses Shoots, the way the portal's
// own connection (made for four databases) may.
const NO_SHOOTS = process.argv[3] === "no-shoots";
// `… named`: Shoot 2 has a name of its own and its sheet three lens sets
// (2026-10-05, shoot names and lens sets).
const NAMED = process.argv[3] === "named";

const P = "11111111-2222-3333-4444-555555555555";
const DOC = "aaaaaaaa-bbbb-cccc-dddd-000000000001";
const LINK = "aaaaaaaa-bbbb-cccc-dddd-000000000002";
const SHEET = "aaaaaaaa-bbbb-cccc-dddd-000000000003";
const MATE = "aaaaaaaa-bbbb-cccc-dddd-000000000004";

const text = (s) => [{ plain_text: s, text: { content: s } }];
const title = (s) => ({ type: "title", title: text(s) });
const rich = (s) => ({ type: "rich_text", rich_text: text(s) });
const select = (s) => ({ type: "select", select: { name: s } });
const rel = (...ids) => ({ type: "relation", relation: ids.map((id) => ({ id })) });
const block = (type, body, more = {}) => ({ object: "block", id: more.id || `${type}-${Math.random()}`, type, [type]: body, has_children: Boolean(more.kids) });

const project = {
  object: "page", id: P,
  properties: {
    Project: title("Refresh Film"),
    Status: select("Active"), Type: select("Narrative"), Length: select("Short"),
    "Shoot Dates": { type: "date", date: { start: "2026-11-02", end: "2026-11-04" } },
    Director: rel(MATE),
    // **The logline is a property now** (2026-10-05): the box wins over the
    // page's old Logline heading, which is still below for the fallback.
    Logline: rich("A logline from the Logline box."),
  },
};
const docs = [
  { object: "page", id: DOC, properties: { Name: title("Overheads Page"), Hub: { type: "checkbox", checkbox: true },
    Section: select("Overheads From Notion"), Projects: rel(P) } },
  { object: "page", id: LINK, properties: { Name: title("Call Sheet From Notion"), Hub: { type: "checkbox", checkbox: true },
    URL: { type: "url", url: "https://example.com/call-sheet" }, Projects: rel(P) } },
  { object: "page", id: "aaaaaaaa-bbbb-cccc-dddd-000000000009", properties: { Name: title("Not Ticked"),
    Hub: { type: "checkbox", checkbox: false }, Projects: rel(P) } },
];
const sheets = [{ object: "page", id: SHEET, properties: {
  Camera: rich("ARRI Alexa 35"), Lenses: rich("Cooke S4/i"), Projects: rel(P),
  "Production LUT": { type: "files", files: [{ type: "external", name: "LUT folder", external: { url: "https://example.com/lut" } }] },
} }];
const crew = [{ object: "page", id: MATE, properties: {
  Name: title("Clara Notion"), Role: rich("Director"), Department: select("Direction"), Projects: rel(P),
} }];

// **A project that shoots twice** (SL-1395, SL-1396) — `hub/shoots.mjs`.
// The wrapped shoot's sheet is listed first, which is what used to win.
const P2 = "22222222-3333-4444-5555-666666666666";
const S1 = "bbbbbbbb-0000-0000-0000-000000000001";
const S2 = "bbbbbbbb-0000-0000-0000-000000000002";
const SH1 = "bbbbbbbb-0000-0000-0000-000000000011";
const SH2 = "bbbbbbbb-0000-0000-0000-000000000012";
const date = (start) => ({ type: "date", date: { start, end: null } });
const tick = { type: "checkbox", checkbox: true };
const project2 = {
  object: "page", id: P2,
  properties: { Project: title("Two Shoots Film"), Status: select("Active"), "Shoot Dates": date("2026-11-10") },
};
const shoots = [
  { object: "page", id: S1, created_time: "2026-10-02T16:58:00.000Z", properties: {
    Shoot: title("Two Shoots Film — Shoot 1"), Project: rel(P2), Status: select("Wrapped"), Dates: date("2026-07-09"),
    Crew: rel("cccccccc-0000-0000-0000-000000000001", "cccccccc-0000-0000-0000-000000000002"), "Camera Spec Sheet": rel(SH1),
    Docs: rel("dddddddd-0000-0000-0000-000000000001"), "Shot List Section": rich("Shoot 1 — July 9"), "What Changes": rich("First shoot."),
  } },
  { object: "page", id: S2, created_time: "2026-10-02T16:58:00.000Z", properties: {
    Shoot: title(NAMED ? "Two Shoots Film — Shoot 2 · Malibu Pickup" : "Two Shoots Film — Shoot 2"), Project: rel(P2), Status: select("Upcoming"), Dates: date("2026-11-10"),
    Crew: rel("cccccccc-0000-0000-0000-000000000002", "cccccccc-0000-0000-0000-000000000003"), "Camera Spec Sheet": rel(SH2),
    Docs: rel("dddddddd-0000-0000-0000-000000000002"), "Shot List Section": rich("Shoot 2 - Kitchen, Shoot 2 - Garden"),
    "What Changes": rich("Lenses change to the zoom."),
  } },
];
sheets.push(
  { object: "page", id: SH1, created_time: "2026-07-01T10:00:00.000Z", properties: {
    Title: title("Shoot 1 Sheet"), Camera: rich("A Cam: Alexa Mini LF\nB Cam: Sony FX3"), Lenses: rich("Signature Primes"), "Frame Rate": rich("23.976"),
    "Codec": rich("ProRes 4444"), "Color Space": rich("A Cam: LogC3\nB Cam: S-Log3"),
    Projects: rel(P2), Shoot: rel(S1) } },
  { object: "page", id: SH2, created_time: "2026-10-01T10:00:00.000Z", properties: {
    Title: title("Shoot 2 Sheet"), Camera: rich("A Cam: Alexa Mini LF\nB Cam: Sony FX3"),
    "Codec": rich("ProRes 4444"), "Color Space": rich("A Cam: LogC3\nB Cam: S-Log3"), Lenses: rich(NAMED ? "A Cam: Fujinon Premavista — 24-100mm — T2.9\nB Cam: Signature Primes — 18, 25, 35, 47mm — T1.8 — from Odd Kinds\nSpecialty: Laowa Probe — 24mm" : "Fujinon Premavista 24-100"), "Frame Rate": rich("23.976"),
    Projects: rel(P2), Shoot: rel(S2) } },
);
crew.push(
  { object: "page", id: "cccccccc-0000-0000-0000-000000000001", properties: {
    Name: title("Wren Wrapped"), Role: rich("Gaffer"), Projects: rel(P2), Shoots: rel(S1) } },
  { object: "page", id: "cccccccc-0000-0000-0000-000000000002", properties: {
    Name: title("Sam Both"), Role: rich("1st AC"), Projects: rel(P2), Shoots: rel(S1, S2) } },
  { object: "page", id: "cccccccc-0000-0000-0000-000000000003", properties: {
    Name: title("Nia New"), Role: rich("Key Grip"), Projects: rel(P2), Shoots: rel(S2) } },
  { object: "page", id: "cccccccc-0000-0000-0000-000000000004", properties: {
    Name: title("Pat Project"), Role: rich("Producer"), Projects: rel(P2) } },
);
docs.push(
  { object: "page", id: "dddddddd-0000-0000-0000-000000000001", properties: { Name: title("Shoot 1 Call Sheet"), Hub: tick,
    URL: { type: "url", url: "https://example.com/call-1" }, Projects: rel(P2), Shoot: rel(S1) } },
  { object: "page", id: "dddddddd-0000-0000-0000-000000000002", properties: { Name: title("Shoot 2 Call Sheet"), Hub: tick,
    URL: { type: "url", url: "https://example.com/call-2" }, Projects: rel(P2), Shoot: rel(S2) } },
  { object: "page", id: "dddddddd-0000-0000-0000-000000000003", properties: { Name: title("Look Deck"), Hub: tick,
    URL: { type: "url", url: "https://example.com/deck" }, Projects: rel(P2) } },
);

// **A project that shoots nine times, and one that shoots once** (Ref 1413):
// Shoots 1–5 wrapped, 6–9 to come, each with its own sheet; and a single
// Shoots row, which the portal treats as no shoots at all.
const P3 = "33333333-4444-5555-6666-777777777777";
const P4 = "44444444-5555-6666-7777-888888888888";
const id3 = (kind, n) => `${kind}${kind}${kind}${kind}${kind}${kind}${kind}${kind}-3333-0000-0000-0000000000${String(n).padStart(2, "0")}`;
const projects34 = [
  { object: "page", id: P3, properties: { Project: title("Many Shoots Film"), Status: select("Active") } },
  { object: "page", id: P4, properties: { Project: title("One Shoot Film"), Status: select("Active") } },
];
for (let n = 1; n <= 9; n += 1) {
  const day = `2026-${String(n).padStart(2, "0")}-15`;
  shoots.push({ object: "page", id: id3("e", n), created_time: "2026-10-02T16:58:00.000Z", properties: {
    Shoot: title(`Many Shoots Film — Shoot ${n}`), Project: rel(P3), Status: select(n <= 5 ? "Wrapped" : "Upcoming"),
    Dates: date(day), Crew: rel(id3("f", n)), "Camera Spec Sheet": rel(id3("a", n)),
  } });
  sheets.push({ object: "page", id: id3("a", n), created_time: "2026-01-01T10:00:00.000Z", last_edited_time: "2026-01-02T10:00:00.000Z",
    properties: { Title: title(`Sheet ${n}`), Camera: rich("Alexa 35"), Lenses: rich(`Lens Set ${n}`), Projects: rel(P3), Shoot: rel(id3("e", n)) } });
  crew.push({ object: "page", id: id3("f", n), properties: { Name: title(`Crew Of Shoot ${n}`), Role: rich("Grip"), Projects: rel(P3), Shoots: rel(id3("e", n)) } });
}
shoots.push({ object: "page", id: id3("d", 1), created_time: "2026-10-02T16:58:00.000Z", properties: {
  Shoot: title("One Shoot Film — Shoot 1"), Project: rel(P4), Status: select("Upcoming"), Dates: date("2026-12-01"),
  Crew: rel(id3("c", 1)), "Camera Spec Sheet": rel(id3("b", 1)) } });
sheets.push({ object: "page", id: id3("b", 1), created_time: "2026-09-01T10:00:00.000Z",
  properties: { Title: title("Only Sheet"), Camera: rich("Venice 2"), Lenses: rich("Ultra Primes"), Projects: rel(P4), Shoot: rel(id3("d", 1)) } });
crew.push(
  { object: "page", id: id3("c", 1), properties: { Name: title("Tagged To The Shoot"), Role: rich("Gaffer"), Projects: rel(P4), Shoots: rel(id3("d", 1)) } },
  { object: "page", id: id3("c", 2), properties: { Name: title("On No Shoot"), Role: rich("Producer"), Projects: rel(P4) } },
);

// How often each page's blocks were read, so a check can see an unchanged
// sheet is not read again (`GET /reads`, no token: it is only ever local).
const reads = {};

const blocks = {
  [P.replace(/-/g, "")]: [
    block("heading_2", { rich_text: text("Logline") }),
    block("paragraph", { rich_text: text("A logline that came from the fake Notion.") }),
    block("heading_2", { rich_text: text("Visual Language") }),
    block("paragraph", { rich_text: text("*Insert here*") }),
  ],
  [DOC.replace(/-/g, "")]: [
    block("heading_2", { rich_text: text("Rigging") }),
    block("paragraph", { rich_text: text("Two overheads on the east wall.") }),
    block("image", { type: "external", external: { url: `${HERE}/pic/overhead.png` }, caption: text("Overhead one") }),
    block("toggle", { rich_text: text("Kit") }, { id: "toggle-1", kids: true }),
  ],
  "toggle-1": [block("bulleted_list_item", { rich_text: text("Two 12x12 frames") })],
  [SHEET.replace(/-/g, "")]: [block("paragraph", { rich_text: text("Rate 23.976 everywhere.") })],
};

// A one-pixel PNG, so the mirror has real bytes to carry.
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==", "base64");

function answer(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

createServer((req, res) => {
  const url = new URL(req.url, HERE);
  if (url.pathname === "/reads") return answer(res, 200, reads);
  if (url.pathname === "/pic/overhead.png") {
    res.writeHead(200, { "content-type": "image/png", "content-length": PNG.length });
    return res.end(PNG);
  }
  if (req.headers.authorization !== `Bearer ${TOKEN}`) {
    return answer(res, 401, { object: "error", code: "unauthorized", message: "API token is invalid." });
  }
  let sent = "";
  req.on("data", (c) => { sent += c; });
  req.on("end", () => {
    const path = url.pathname.replace(/^\/v1\//, "");
    const query = /^data_sources\/([^/]+)\/query$/.exec(path);
    if (query && req.method === "POST") {
      const rows = { [PROJECTS]: [project, project2, ...projects34], [PROJECT_DOCS]: docs, [CAMERA_SHEETS]: sheets, [CREW]: crew,
        ...(NO_SHOOTS ? {} : { [SHOOTS]: shoots }) }[query[1]];
      if (!rows) return answer(res, 404, { object: "error", code: "object_not_found", message: "Not shared." });
      return answer(res, 200, { object: "list", results: rows, has_more: false, next_cursor: null });
    }
    const page = /^pages\/([0-9a-f-]+)$/.exec(path);
    if (page) {
      const id = page[1].replace(/-/g, "");
      const one = [project, project2, ...projects34, ...crew, ...sheets].find((p) => p.id.replace(/-/g, "") === id);
      return one ? answer(res, 200, one) : answer(res, 404, { object: "error", code: "object_not_found", message: "No." });
    }
    const kids = /^blocks\/([^/]+)\/children$/.exec(path);
    if (kids) {
      reads[kids[1].replace(/-/g, "")] = (reads[kids[1].replace(/-/g, "")] || 0) + 1;
      const got = blocks[kids[1].replace(/-/g, "")] || blocks[kids[1]];
      return answer(res, 200, { object: "list", results: got || [], has_more: false, next_cursor: null });
    }
    return answer(res, 404, { object: "error", code: "object_not_found", message: `No ${path}` });
  });
}).listen(PORT, "127.0.0.1");
