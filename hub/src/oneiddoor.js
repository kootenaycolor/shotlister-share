/**
 * **The doors of one ID per project** (projectid.js, studioside.js; stage 5
 * step 2). All under `/console/studio/`, with the console's token:
 *
 *   GET  /console/studio/oneid                  { on, at, by } — off until thrown
 *   PUT  /console/studio/oneid                  { on, by }
 *   GET  /console/studio/ids                    the map: { notion, alias, at }
 *   GET  /console/studio/ids/<id>               { key, via, name, notion, studio } — any ID somebody holds
 *   POST /console/studio/ids/aliases            { dry } — every existing film's relay id kept as an
 *                                               alias of its project; dry (the default) writes nothing
 *   POST /console/studio/ids/mint               { notion, id?, name, by } — a project born outside the
 *                                               server (the Mac console's own New Project): its record
 *                                               begun under a minted ID, the Notion page kept as a
 *                                               field. Only while the switch is on.
 *   POST /console/studio/projects/<id>/studio   { dry, by } — the project's Studio side, made under its
 *                                               ID if it has none (studioside.js)
 */

import * as ids from "./projectid.js";
import { studioSideDoor } from "./studioside.js";

const isObject = (x) => Boolean(x) && typeof x === "object" && !Array.isArray(x);

/**
 * Begin a minted project's record: `r/<id>/record.json` with `page` = the ID
 * and `notion_page` = its Notion page, and the map told. A Notion page that
 * already has a record (existing projects keep theirs) or is already mapped
 * answers that, and nothing is made.
 */
export async function beginMinted(env, { notion = "", id = "", name = "", by = "server" } = {}) {
  const page = ids.bare(notion);
  if (page && !ids.ID.test(page)) throw new Error("That is not a Notion page id.");
  if (page) {
    const map = await ids.readIds(env);
    if (map.notion[page]) return { key: map.notion[page], made: false, why: "already minted" };
    // Read below the bucket's door: the page's own record, if it has one.
    if (await env.BUCKET.head(`r/${page}/record.json`)) return { key: page, made: false, why: "an existing project keeps its page id" };
  }
  const key = await ids.freeId(env, id);
  const record = {
    version: 1, page: key, ...(page ? { notion_page: page } : {}), name: String(name || ""),
    facts: {}, lights: {}, by: String(by || "server").slice(0, 80), minted: new Date().toISOString(),
    updated: new Date().toISOString(),
  };
  // The map first, then the record: a record nobody can find by its Notion
  // page would be begun a second time by the next reader.
  if (page) {
    const got = await ids.addIds(env, { notion: { [page]: key } });
    if (got.clashes.length) return { key: got.ids.notion[page], made: false, why: "already minted" };
  }
  const saved = await env.BUCKET.put(`r/${key}/record.json`, JSON.stringify(record), {
    httpMetadata: { contentType: "application/json" }, onlyIf: { etagDoesNotMatch: "*" },
  });
  if (!saved) throw new Error("a record appeared under the new ID while it was being begun");
  return { key, made: true, record };
}

export async function oneIdDoor(env, rest, method, read) {
  const reply = (body, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
  const refuse = (status, problem) => reply({ problem }, status);
  const body = async () => { try { const v = await read(); return isObject(v) ? v : {}; } catch { return null; } };

  if (rest[0] === "oneid" && rest.length === 1) {
    if (method === "GET") return reply(await ids.oneIdOn(env));
    if (method !== "PUT") return refuse(405, "Wrong method.");
    const said = await body();
    if (!said) return refuse(400, "That is not JSON.");
    return reply(await ids.setOneId(env, said));
  }

  if (rest[0] === "ids") {
    if (rest.length === 1) {
      if (method !== "GET") return refuse(405, "Wrong method.");
      return reply(await ids.readIds(env));
    }
    if (rest.length === 2 && rest[1] === "aliases") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      const said = await body();
      if (!said) return refuse(400, "That is not JSON.");
      return reply(await ids.freezeAliases(env, { dry: said.dry !== false }));
    }
    if (rest.length === 2 && rest[1] === "mint") {
      if (method !== "POST") return refuse(405, "Wrong method.");
      const said = await body();
      if (!said) return refuse(400, "That is not JSON.");
      if (!(await ids.oneIdOn(env)).on) return refuse(409, "The one-ID switch is off.");
      try {
        const got = await beginMinted(env, { notion: said.notion, id: said.id, name: said.name, by: said.by });
        return reply({ key: got.key, made: got.made, ...(got.why ? { why: got.why } : {}) });
      } catch (e) {
        return refuse(400, String((e && e.message) || e).slice(0, 300));
      }
    }
    if (rest.length === 2) {
      if (method !== "GET") return refuse(405, "Wrong method.");
      const got = await ids.resolveProject(env, rest[1]);
      if (!got.key) return refuse(404, "No project with that ID.");
      return reply({
        key: got.key, via: got.via, name: String(got.record.name || ""),
        notion: ids.notionOf(got.record, got.key), studio: ids.studioOf(got.record),
      });
    }
    return refuse(404, "No such door.");
  }

  if (rest[0] === "projects" && rest.length === 3 && rest[2] === "studio") {
    if (method !== "POST") return refuse(405, "Wrong method.");
    const said = await body();
    if (!said) return refuse(400, "That is not JSON.");
    const got = await studioSideDoor(env, rest[1], said);
    return reply(got.body, got.status);
  }
  return null;
}
