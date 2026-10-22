/**
 * **`add_picture`: a picture or clip onto a shot, scene, location, reference
 * board or edit reference, from the web** (2026-10-17, his ask: "the MCP can
 * do anything I can do"). On the Mac he drops a file on a row; the Mac's
 * connector has `attach`, which reads a path on his disk. Here there is no
 * disk, so the file comes as a web address or as its bytes, and goes the way
 * a board's Add to Shot does (`fileOnShot`): kept by its own contents on the
 * film, put where the film's own pictures live (`media/`) so the Mac and the
 * phone fetch it like any other, then filed by the engine as a change log in
 * this person's name.
 */
import { keys } from "../../relay/layout.js";
import { keepBytes, extensionFor, ownFile, MOST_PICTURE, MOST_CLIP, driveIdOf } from "./boards.js";

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
const MIME = { jpg: "image/jpeg", png: "image/png", webp: "image/webp", gif: "image/gif", heic: "image/heic", mp4: "video/mp4", mov: "video/quicktime" };
const MOVING = new Set(["mp4", "mov"]);
const OWNERS = ["shot", "scene", "location", "board", "edit_reference"];

export const ATTACH_TOOL = {
  name: "add_picture",
  description:
    "Pin a picture or clip to a shot (34A), a scene (34), a location, a reference board or an edit reference (its clip or stills) — what dropping a file on it does in Studio. Name one owner and give the file: `url` (a picture or mp4/mov address, a Drive share link, or a picture this project already holds, `pic/<name>`) or `base64` with its `filename` (up to about 25 MB for a picture). Kept whole, by its own contents: the same file twice is one copy, and on one owner once. `caption` shows under it; `name` is what it is called (the file's type is kept). On a shot it becomes a frame (`update_attachment` `lead` makes it the one that stands for the shot). Only what he asked to put there: a shot's frames are his storyboard. A file already somewhere in the project is copy_attachment, which fetches nothing.",
  inputSchema: {
    type: "object",
    properties: {
      shot: { type: "string" },
      scene: { type: "string" },
      location: { type: "string" },
      board: { type: "string", description: "A reference board's name." },
      edit_reference: { type: "string", description: "An edit reference's name." },
      url: { type: "string", description: "Where the picture or clip is." },
      base64: { type: "string", description: "The file itself. Send this or `url`." },
      filename: { type: "string", description: "With `base64`: its name, for its type (`still.jpg`)." },
      caption: { type: "string" },
      name: { type: "string" },
    },
    required: [],
  },
};

function decode(text) {
  const binary = atob(String(text || "").replace(/\s+/g, ""));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

async function fetched(raw) {
  let url;
  try { url = new URL(String(raw || "").trim()); } catch { return null; }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  const drive = driveIdOf(url);
  const tries = drive
    ? [`https://drive.google.com/uc?export=download&id=${drive}`, `https://drive.google.com/thumbnail?id=${drive}&sz=w2400`]
    : [url.toString()];
  for (const where of tries) {
    try {
      const r = await fetch(where, { headers: { "user-agent": UA, accept: "*/*" }, redirect: "follow" });
      if (!r.ok) continue;
      const size = Number(r.headers.get("content-length") || 0);
      if (size && size > MOST_CLIP) return { why: "That file is too big to bring in here." };
      const ext = extensionFor(r.headers.get("content-type"), new URL(where).pathname);
      if (!ext) continue;
      const bytes = new Uint8Array(await r.arrayBuffer());
      const most = MOVING.has(ext) ? MOST_CLIP : MOST_PICTURE;
      if (bytes.length > most) return { why: "That file is too big to bring in here." };
      if (bytes.length < 200) continue;
      return { ext, bytes };
    } catch { /* the next road, or none */ }
  }
  return null;
}

/**
 * The tool. `deps.attach(asked)` is `attachToShot` bound to this person and
 * project: the engine's own door, which names the owner as every attachment
 * tool does.
 */
export async function attachTool(env, found, args, refuse, deps) {
  if (found.role !== "editor") throw refuse("You may look at this project, not change it.");
  const a = args && typeof args === "object" ? args : {};
  const named = OWNERS.filter((k) => typeof a[k] === "string" && a[k].trim());
  if (named.length !== 1) throw refuse("Name one owner: shot, scene, location, board or edit_reference.");
  const project = found.project;

  let file = "";
  let ext = "";
  if (a.url && a.base64) throw refuse("Send `url` or `base64`, not both.");
  if (a.url) {
    const own = await ownFile(env, project, a.url);
    if (own) {
      file = own.file;
      ext = file.split(".").pop();
    } else {
      const got = await fetched(a.url);
      if (!got) throw refuse("Could not fetch a picture or clip from that address.");
      if (got.why) throw refuse(got.why);
      ext = got.ext;
      file = await keepBytes(env, project, ext, got.bytes);
    }
  } else if (a.base64) {
    ext = extensionFor("", String(a.filename || ""));
    if (!ext) throw refuse("Say its `filename`, a picture (jpg, png, webp, gif, heic) or a clip (mp4, mov).");
    let bytes;
    try { bytes = decode(a.base64); } catch { throw refuse("That did not decode as base64."); }
    if (bytes.length > (MOVING.has(ext) ? MOST_CLIP : MOST_PICTURE)) throw refuse("That file is too big to bring in here. Send its address instead.");
    file = await keepBytes(env, project, ext, bytes);
  } else {
    throw refuse("Give the file: `url`, or `base64` with its `filename`.");
  }

  // Where the film's own pictures live, so the Mac and the phone fetch it as
  // they fetch any other; its whole hash is the engine's name for it.
  let bytes;
  const inMedia = await env.BUCKET.get(keys.medium(project, file));
  if (inMedia) {
    bytes = new Uint8Array(await inMedia.arrayBuffer());
  } else {
    const kept = await env.BUCKET.get(keys.doc(project, file));
    if (!kept) throw refuse("That file could not be kept.");
    bytes = new Uint8Array(await kept.arrayBuffer());
    await env.BUCKET.put(keys.medium(project, file), bytes, { httpMetadata: { contentType: MIME[ext] || "application/octet-stream" } });
  }
  const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((b) => b.toString(16).padStart(2, "0")).join("");
  if (!hash.startsWith(file.slice(0, 32))) throw refuse("That file is not what its name says.");

  const title = String(a.name || "").replace(/\.[a-z0-9]{2,5}$/i, "").replace(/[\\/:*?"<>|\n\r]+/g, " ").trim().slice(0, 60)
    || (MOVING.has(ext) ? "Clip" : "Still");
  const asked = { [named[0]]: a[named[0]].trim(), hash, name: `${title}.${ext}`, size: bytes.length, caption: String(a.caption || "").slice(0, 200) };
  return await deps.attach(asked);
}

/**
 * **Refresh from Notion** — the portal's own button (worker.js `/refresh`),
 * his alone, as the button is: the pages Notion feeds, the crew and the
 * spec sheet copied in again. A page written here (Source: here) is left
 * alone, as the button leaves it.
 */
export const REFRESH_TOOL = {
  name: "refresh_from_notion",
  description: "Refresh the open project's portal from Notion now, as the Refresh button on the portal does: every page Notion feeds (Source: Notion), the crew list and the camera spec sheet are copied in again from his Notion pages. A page written here or by an agent (Source: here), and a snapshot (notion-once), is left alone. His alone. Answers what changed.",
  inputSchema: { type: "object", properties: {}, required: [] },
};

export async function refreshTool(env, found, admin, refuse) {
  if (!admin) throw refuse("Only he may refresh a portal from Notion.");
  const { notionReady, refreshFilm } = await import("./notion.js");
  if (!notionReady(env)) throw refuse("The portal is not connected to Notion; refresh from Projects Console.");
  const got = await refreshFilm(env, found.project);
  if (!got.ok && !got.updated) throw refuse(`Notion did not refresh it: ${(got.lines || []).join(" · ") || "no reason given"}.`);
  return (got.lines || []).length ? got.lines.join("\n") : "Refreshed. Nothing had changed in Notion.";
}
