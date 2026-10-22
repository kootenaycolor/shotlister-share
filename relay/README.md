# The relay

His own sync server, so a film moves between his Mac and his phone when he says
so rather than when iCloud gets round to it.

**Double-click `Set Up Sync` at the top of the repo.** Once, ever. Everything
below is for whoever has to work on it.

## Why there is one at all

iCloud is not wrong about anything; it is just silent and has no buttons. His
complaint, 2026-08-31: *"inconsistent between devices and hard to make
reliable, there's no way to force a manual sync or push one."*

And the measurement explains the feeling. Across his three films:

| | Size |
| --- | --- |
| The shot lists — 140 change logs | **1.3 MB** |
| Photographs and video | **126 MB** |

The part he cares about is a rounding error, and iCloud moves it on the same
schedule as eighty megabytes of footage. A relay that knows the difference
sends the list in under a second on a button press and fetches a picture only
when something needs to draw it.

## What it is

**A Cloudflare Worker that stores files and understands none of them.** It
never parses a change, never merges, never runs the engine — so it cannot lose
an edit or settle a disagreement wrongly, because it does not know what either
of those is. Everything that decides what a change *means* stays in `engine/`,
where it was already written and already tested.

That is the whole reason this is a small, boring file rather than a second
implementation of the app.

```text
p/<project>/logs/<device>-<session>.log       the change logs
p/<project>/logs/<device>-<install>.device    the identity marks (empty)
p/<project>/logs/<device>.folded              what a fold retired and rewrote
p/<project>/media/<32 hex>.<ext>              proxies — pictures and clips
p/<project>/manifest.json                     what the film is called
devices/<sha256 of token>.json                a device's name — never its token
```

## The one route with no password

`GET /i/<project>/<32 hex>.<jpg|png|gif|webp>` hands back one picture and asks
for nothing. **Because Google has to be the one fetching it.** A frame in the
exported spreadsheet is written as an `IMAGE()` formula rather than a picture
pasted over the grid — that is what makes it the cell's *contents*, so it
travels with its row when he sorts, which pasted-on frames never did. Sheets
draws it by having Google's own servers ask for the address, they cannot be
handed his token, and a picture carried inside the formula is refused outright
(*"is not a valid url"*, measured 2026-09-04).

So the address is the permission, and it is kept as narrow as an address can be:

- **One exact name, never a list.** There is no way in from outside except
  already knowing the answer. The name is the first 32 characters of the
  picture's own hash — 128 bits that exist only if you hold the bytes.
- **Pictures only.** Clips, scans and everything else stay behind the token.
- **Reading only.** `PUT` and `DELETE` are refused here; writing is still
  `/v1/p/<project>/media/<name>` with the password.

Ten checks in `checks.sh` are about nothing but how narrow it is.

## A token per device

**Two kinds of key, since 2026-09-16.** The *master password* is the one Set
Up Sync made — the `TOKEN` secret, the item in his Keychain, what the console
and the hub's door hold. It still opens every route, and it is the only thing
that may mint or revoke the second kind. A *device token* is minted for one
Mac or one phone:

```text
POST   /v1/devices            {"name": "Nathaniel's iPhone"}   → {id, name, made, token}   (master only)
GET    /v1/devices                                             → {devices: [{id, name, made, seen}]}
DELETE /v1/devices/<id>                                        → {id, revoked: true}
```

The token is shown once, in that reply, and never stored — the bucket keeps
its hash and the name. Every other route accepts either kind. A log or a
picture put with a device token carries `by: <name>`, and `/state` lists it,
so for the first time the relay can say which device wrote what. Revoking a
device takes its key away and nothing else: its logs stay, and no other
device notices. `seen` moves at most once an hour.

**The apps still use the master password.** `studio/` and `phone/` read the
Keychain item Set Up Sync wrote, and the relay lets that in as it always did.
Switching each device to a token of its own is their threads' work (the row
is in Notion); the relay is ready for it, and a device token in that Keychain
item would work today with no app change.

## The two rules it does enforce

Both are about damage, not meaning, which is why they belong on the server:

- **A log may only ever grow.** Every log has exactly one writer for ever, and
  a writer only appends. A `PUT` whose body does not begin with what is already
  stored is refused — which stops a truncated or half-written local file
  overwriting a good remote one. Folding old logs together (Ref 192) is the one
  case that legitimately rewrites and says so with `?rewrite=1`.
- **A picture is written once and never again.** Media is named after the hash
  of its contents, so a name means one set of bytes for ever. That also makes
  an upload cut off halfway safe to simply repeat.

The hash is *checked* when the sender claims it with an `x-sha256` header, and
that check is deliberately optional. **A clip is stored twice under one name** —
the movie, and the still that stands for it wherever a picture is drawn
(`storage/src/lib.rs:1019`). The still is different bytes under the same stem,
so it hashes to something else entirely. A relay that insisted would have
refused the poster of every video in the project. Found by hashing his real
media rather than by assuming, which is the note worth keeping.

## The layout is named once

**`layout.json` is where everything in the bucket sits**, and it is the only
place. The relay's worker and every file under `hub/src/` import it through
`layout.js` (`keys.manifest(project)`, `keys.log(project, name)`, the hub's
`keys.page`, `keys.deck`, `keys.cover`…) and spell no path of their own;
`hub/refresh.py` reads the JSON for the one key it writes. Three readers
cannot import it — the page (`hub/public/film.js`), the browser engine
(`web/src/lib.rs`) and the two Swift apps — so each repeats one word and
`relay/checks.sh` measures them against the file, and against the engine's
own names in `engine/src/package.rs`. The same battery fails if anyone spells
`p/${project}/…` by hand again.

Why: the layout is the contract between the relay, the hub and the apps, and
until 2026-09-16 nobody owned it. The Mac's clip posters turned JPEG on
2026-09-15 and the hub went on asking for PNG — blank thumbnails on every
clip until somebody read both files. A name that lives in one place, with a
check on every reader that cannot take it from there, is what stops the next
one.

## Only the proxies travel

Full-size originals stay on the machine that made them. They are the biggest
files in a project, every device currently drags them all down, and none of
them needs to — **Ref 332**, fixed here by not doing it. The proxy is what
every screen and every export actually draws.

## Checking it

```bash
relay/checks.sh     # 64 checks against Cloudflare's own runtime, on this machine
remote/checks.sh    # two devices that share nothing but a relay, plus a real film
```

Neither touches the internet, his account, or his films — `remote/checks.sh`
copies a film before it goes near it.

**One trap, and it cost half an hour.** `wrangler dev` runs the real server in a
child process called `workerd` and *puts a new one back* whenever it dies. So
killing whatever holds the port achieves nothing, and killing only the shell
that launched it leaves wrangler orphaned onto init — still serving **the
version of the script it started with**. The next run finds the port answering,
talks to a stale server, and fails in a way that reads exactly like a bug in the
code. Both check scripts now kill wrangler by its own command line and refuse to
start at all if the port is somebody else's.

## Running it by hand

```bash
cd relay && npx wrangler@4 dev          # needs Node 22+; Homebrew's is current
relay/deploy.sh                         # what Deploy Shotlister does, relay half
```

**Deploy through `deploy.sh`, never `wrangler deploy` by hand.** It stamps
the commit onto the worker as it goes up, so `/v1/version` answers `{commit,
deployed, build}` with no token — and `hub/drift.sh` can then say `relay:
041bb8a live, 3 commits behind main`. A relay put up any other way says
`unknown`. It refuses an uncommitted `relay/` (three threads share the
checkout; a hash that says "clean" over somebody's half-written change is the
worse outcome), and it waits until `sync.your-domain.example` says the new
commit before it calls itself done. **Deploy Shotlister** in `Apps/` runs it
and then the hub's, in that order — the hub reads what the relay stores.

The token lives in his Keychain under `shotlister-relay`, never in a file here.
`.dev.vars` is written by the check scripts and is not committed.

## What is not done yet

- **The apps have no buttons.** `remote/` decides what should move and the
  courier can carry it from a command line, but Studio and the phone do not yet
  push or pull. That is the next piece.
- **Folding reaches the relay, but nothing sends it yet.** The relay honours
  a `<device>.folded` record since 2026-09-16 (`fold` in `src/worker.js`):
  it retires that device's own logs once every log the fold rewrote is here,
  and refuses a record that names another device's. Neither app puts the
  record up — `remote/` reads it on disk and the Swift twins do not carry
  it. Until one does, the relay still holds every retired log; harmless, the
  same change merged twice is nothing.
- **The apps still speak with the one password.** The relay can mint a token
  per device now (above) and name who wrote, but neither app asks for one yet.
  Directors editing will still need real accounts, which is the hub's side.
