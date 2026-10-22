# refresh.py on the hub: the gap, and how it was closed

Stage 3 step 2 of Projects Console without the Mac (SL-1705). `hub/refresh.py`
`main()` ran every 15 min from a LaunchAgent on the Studio Mac. Before this,
the hub had `refreshFilm` (`src/notion.js`, the portal's Refresh button) and
nothing else of it. Function by function, what `main()` does and where it
lives now.

## What main() does, and what the hub had

| refresh.py | does | hub before | now |
|---|---|---|---|
| `films_here` | films = `~/Documents/Shotlister/*.shotlist` with `remote.json` | — | `itemsNow`: every `p/<id>/` with a manifest that is not a filmless portal (the relay's own rule; same 6 films) |
| `portals_here` | portals with no film, via `GET /console/portals` | `everyPortal` (the door it asks) | `itemsNow` uses `everyPortal` directly |
| `carry_portals` | a film whose `consolePage` is a standing portal takes it in (`POST …/portal/carry`) | `carryPortal` (only via the door) | `refreshOneFilm`, before the card, from the film's own `console_page` |
| `facts` / `_facts` | `cargo … dump_view` on the film: counts, days, director, producer, ratio, page, which pictures | `cardOf` overlays a similar film half on every *read* (`card()` in the wasm); nothing *wrote* it | `filmFacts`: the wasm's `view()` (the same description dump_view prints) + `factsFromView` (`drawn_with`, `some_pictures`, `proxy_named` against the film's media in the bucket) |
| `card_now` / `put_card` | raw read-modify-write of `front.json` | `storedFront`/`saveFront` (tidied) | `cardNow`/`putCard`, raw, as Python |
| `token`, `users/me`, `rows_of(PROJECTS)` | no words for the whole run if any refuses | partly (per film) | `openNotion`, once per tick |
| `page_for` | film's `consolePage` → "link", else title = Projects row → "name" | `pageFor` from the *card's* `source`, not the film | `pageFor` (`refreshrules.js`), Python's order |
| `from_notion` | row words, mark, status/type/length/dates, Shoots, ticked Project Docs, spec sheets, crew, director | ported in `refreshFilm`, with differences (below) | `fromNotion` in `refreshhub.js`, rule for rule |
| `words_from_notion` | sections' pages, sheets' files and notes, per-shoot sheets, "Notion would not say" | ported in `refreshFilm`, with differences | `wordsFromNotion`, rule for rule |
| `mark_of` | Notion icon → `{path, colour}` | private `markOf` | `notionmark.js` (`notionIconAddress`, `markFromSvg`, `markOfRow`), exported for step 3 (`mirror_mark`); `notion.js` uses it too |
| `director_of` | Director relation by name | `directorOf` | same rule, over every crew row |
| `record_view` / `from_record` / `card_credits` | the record's typed facts over Notion's | `recordView` + `layRecordFacts` (`facts.js`) | reused as is |
| `covers_wanted`, `shoot_dates_text` | one cover per film, page, tab, named page, plus the icon | — | `coversWanted`, `shootDatesText` (`refreshrules.js`) |
| `put_cover` / `covers_drawn` | fingerprint (`sha256(json.dumps(sort_keys))[:16]`) per cover in `media/covers.json`; draw only what changed | — | `putCovers` (`linkcovers.js`), Python's fingerprints byte for byte (`pyJson`) |
| `cover.mjs` | Chrome on the Mac draws the HTML card | "a worker cannot draw" | the same HTML (`src/coverhtml.js`, now shared by `cover.mjs`), drawn by the `BROWSER` binding, Rethink Sans inlined from `env.ASSETS` |
| `covers_only` (`--covers`) | redraw every cover | — | `redraw: true` on a run |
| `give_up_after`, `in_time` | a ceiling on a run | — | a pass of `BATCH` (2) cards a minute, cursor + lease in `s/portal-refresh.json` |
| LaunchAgent | every 900 s | — | the portal's minute (`timer.js` → `onPortalTimer`), a new pass 15 min after the last began |
| `mirror_mark` | (Projects Console, not refresh.py) icon into the film | — | **not ported** (step 3); the pair it needs is `markOfRow` |

## Does the wasm's `card()` give refresh.py's counts? No — `view()` does

`card()` (`film_card`) is the portal's live overlay and differs from
`_facts` on real films: shot counts (Let's Bake 29 vs 58, Call Her Back 66 vs
69, Harbour Light Affair 10 vs 12: it counts each shot once, `_facts` counts
rows in the scene groups), Andromeda B's ratio, and a clip's picture name
(`.mp4` where `_facts` finds the `.jpg` poster). `view()` is the same JSON
`dump_view` prints, so the port reads that: 6 of 6 films identical, every
field (`node hub/refreshhub.mjs`).

## How refreshFilm differs from the Python (why the run does not reuse it)

- asks Notion only for this project's rows (`filter`), and for a shoot's
  sheet or crew outside them one by one; Python reads every row and filters;
- finds the page from the card's `source`, not the film's `consolePage`;
- with Shoots refused, uses the card's stored shoots (sheet choice differs);
- `shoot_name` splits on every dash, Python only the first;
- tidies the card on write; Python writes it raw;
- `prop` reads a `status` property, Python's does not (his Status is a select).

The leaves are shared unchanged: `readBlocks`, `mirror`, `putPage`,
`bothKinds`, `bothRoads`, `prose`, `typedWords`, `filesOn`, `without`, the
slug rules (exported from `notion.js`, otherwise untouched). The Refresh
button keeps `refreshFilm` as it was.

## Deviations that remain (by necessity)

1. `counts.pictures`: Python counted image files in the Mac's proxies
   folder; the hub counts the film's 32-hex image files in the bucket, which
   also holds pictures copied out of Notion (Call Her Back: 170 vs 225).
   Nothing draws it (`withFilm` keeps it as stored).
2. The film half reads the relay's copy of the logs and pictures; when the
   Mac has not synced, the hub is behind it (the Mac was never behind itself).
3. A Notion file already in the bucket is not fetched again (`mirror` heads
   first); Python re-downloaded and re-wrote it every run. Same name, same bytes.
4. Every row of a database is read once per tick, not once per film.
5. A cover the browser will not draw within 30 s is a line, not a hang.
6. Covers are drawn in Cloudflare's Chromium, not the Mac's Chrome.
