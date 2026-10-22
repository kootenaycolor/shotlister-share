// **Read-only, by construction.** Two routes, both GET: list the bucket and
// fetch one object. There is no write or delete anywhere in this file, so a
// bug in the backup can never change the portal his crews are using.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "GET") return new Response("read-only", { status: 405 });
    if (url.pathname === "/list") {
      const page = await env.BUCKET.list({
        prefix: url.searchParams.get("prefix") || "",
        cursor: url.searchParams.get("cursor") || undefined,
        limit: 1000,
      });
      return Response.json({
        truncated: page.truncated,
        cursor: page.truncated ? page.cursor : null,
        objects: page.objects.map((o) => ({ key: o.key, size: o.size, etag: o.etag })),
      });
    }
    if (url.pathname === "/get") {
      const object = await env.BUCKET.get(url.searchParams.get("key"));
      if (!object) return new Response("missing", { status: 404 });
      return new Response(object.body, { headers: { "x-etag": object.etag } });
    }
    return new Response("unknown", { status: 404 });
  },
};
