/**
 * A Released project's selects on its portal home (portalselects.js,
 * 2026-10-17): read off the record only once Released, ids only, the
 * pictures whole and square, the film's links small. `node hub/portalselects.mjs`
 */
const P = await import("./src/portalselects.js");
let pass = 0, fail = 0;
const check = (what, good, why = "") => { if (good) pass += 1; else fail += 1; console.log(`  ${what.padEnd(80)} ${good ? "PASS" : `FAIL — ${why}`}`); };
const rec = (status, facts = {}) => ({ stage: status, facts: { status: { value: status }, ...facts } });
const ids = ["1ExampleDriveFileIdAAAAAAAAAAAAAA", "1ExampleDriveFileIdBBBBBBBBBBBBBB"];
check("not Released: nothing", P.releasedOf(rec("Post", { selects: { value: ids } })) === null);
check("closed or deleted: nothing", P.releasedOf({ ...rec("Released", { selects: { value: ids } }), closed: {} }) === null && P.releasedOf({ ...rec("Released"), deleted: true }) === null);
const r = P.releasedOf(rec("Released", { selects: { value: [...ids, "../etc", 7] }, website: { value: "https://your-website.example/project/x" },
  links: { value: { custom: [{ slot: "watch", url: "https://vimeo.com/123", title: "vimeo.com" }, { slot: "watch", url: "https://your-website.example/project/x" }, { slot: "other", url: "https://a.b" }] } } }));
check("Released: the picked ids in his order, nothing else", JSON.stringify(r.selects) === JSON.stringify(ids), JSON.stringify(r));
check("the watch links by the site's name, the website once", r.watch.length === 1 && r.watch[0].name === "Vimeo" && r.website === "https://your-website.example/project/x", JSON.stringify(r));
const html = P.selectsBlock("/zz-test", r);
check("the block: each still through the page's own door", html.includes(`src="/zz-test/select/${ids[0]}"`) && html.includes(`src="/zz-test/select/${ids[1]}"`), html);
check("small links: Website first, then his links", /<p class="hm-sel-l"><a href="https:\/\/your-website.example\/project\/x"[^>]*>Website<\/a><span> · <\/span><a href="https:\/\/vimeo.com\/123"[^>]*>Vimeo<\/a><\/p>/.test(html), html);
check("a link's name: the one he typed, else the site's, else its address", P.watchName("https://vimeo.com/1", "My Film") === "My Film" && P.watchName("https://www.youtube.com/watch?v=1", "") === "YouTube" && P.watchName("https://example.org/a", "example.org · a") === "example.org" && P.watchName("https://livid.com/x", "vimeo.com") === "Livid");
check("no selects: no block", P.selectsBlock("/zz", P.releasedOf(rec("Released"))) === "" && P.selectsBlock("/zz", null) === "");
const css = (await import("node:fs")).readFileSync(new URL("./public/front.css", import.meta.url), "utf8");
const rule = (/\.fh2 \.hm-sel-g img\{([^}]*)\}/.exec(css) || [])[1] || "";
check("the pictures whole and square (no cover, no rounding)", /object-fit:contain/.test(rule) && /border-radius:0/.test(rule) && /width:auto/.test(rule), rule);
const worker = (await import("node:fs")).readFileSync(new URL("./src/worker.js", import.meta.url), "utf8");
check("the picture door only serves an id among the selects", /rest\[0\] === "select"[\s\S]{0,400}!rel\.selects\.includes\(rest\[1\]\)/.test(worker));
console.log(`\nportalselects: ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
