# The Drive bridge

Location photographs live in two places because two different sets of people
need them: **in the project**, where Shotlister keeps them and the phone writes
them, and **in Google Drive**, where a producer or a gaffer can see them without
owning a copy of an app that was never published.

This keeps those two places the same. It is not part of the app — it is a small
program that watches folders, so there is no Google sign-in, no tokens, and
nothing that can expire. Drive for Desktop already makes Drive an ordinary
folder; this copies between folders.

```
Documents/Shotlister/Daybreak.shotlist/locations/<id>/photos/
      ⟷
Google Drive/…/cinematography/projects/daybreak/2-logistics/<locations>/<Name>/
```

## It asks the engine

The first version walked two folder trees and guessed — matching locations by
folder name, copying whatever was missing either way. **Guessing is why it could
not tell a photograph somebody deleted from a photograph somebody added**, so it
never deleted anything, and a picture removed on a scout came back five minutes
later.

It links the engine now. The engine knows what a location is called and which
photographs belong to it; Drive is made to match.

## Three halves now (the shot list one is retired)

**Retired 2026-10-15:** the shot stills half below no longer runs. The hub's Drive copies write a shot's pictures to `1-creative/shot-list/scene-NN/`. Locations and boards are unchanged.


Locations and mood boards **carry both ways** — a photograph added on either
side reaches the other. The shot list **publishes only**, and that is his
ruling of 2026-09-02.

```
<film>.shotlist  a shot's pictures  ──►  <project>/1-creative/shot list/stills/3G.jpg
```

Every picture hanging on a shot is written there under the shot's own number,
the first taking the clean name and the rest following it — `3G.jpg`,
`3G-2.jpg`. A shot holding a clip publishes the frame that stands for it, never
the video: a folder of stills wants a still, and a `.mp4` written here would be
invisible to the next run and so written again for ever.

**Nothing is ever imported from it, and nothing of his is ever touched.** A file
named `3G.jpg` in a folder is a statement about a shot; a file he drops in
beside it says nothing the engine could act on. The memory names only the files
this program wrote, so those are the only ones it will ever move aside — and a
picture taken off a shot goes to `z-deleted` like everywhere else, rather than
being destroyed.

It asks the engine's own picture gallery, which already groups every picture by
what it hangs on and labels a shot with its display number. There was nothing
new for the engine to learn.

## The rules it runs on

- **It destroys nothing.** A photograph deleted in the app leaves the Drive
  folder so the deletion sticks, but it goes to **`z-deleted`** beside it rather
  than being removed. Deleting is a person's decision; this is only carrying one
  out. A photograph deleted in Drive stops being on that location in the app —
  the picture itself is kept, because the engine stores it by its contents and
  it may be on a shot as well.
- **It remembers.** One small file per location listing what was carried across
  last time. Without a memory a file in Drive that the engine lacks is
  indistinguishable from a file the engine used to have.

  The memory lives in `~/Library/Application Support/Shotlister/drive-sync`,
  **outside the project**, because the project syncs: a memory inside it travels
  to every device, is rewritten whole by each of them, and iCloud answers that
  with conflict copies. What has been carried into Drive is a fact about *this
  computer*, not about the film. A memory it has not got yet is safe — every
  deletion below needs the memory to name the file, so a machine that has never
  run this does nothing at all until it has learned.
- **An unreadable folder is not an empty one.** A folder Drive has not mounted,
  has not sent down to this machine, or will not open for a moment used to come
  back as an empty list — and an empty list says somebody deleted everything in
  it. That is how a hiccup could take every photograph off a location. It is
  told apart now, and a folder that will not open is left alone and said out
  loud.
- **A clean sweep waits to be seen twice.** Even read correctly, *every*
  photograph disappearing at once is far more likely to be Drive than a person:
  somebody deleting pictures leaves the rest behind. So a wholesale
  disappearance has to still be true ten minutes later before it is carried out.
  A partial deletion is believed straight away, because nothing but a person
  produces one.
- **What it could not do, it does not write down.** A photograph that failed to
  copy into Drive is not remembered as carried — remembering it would make it
  look, on the next run, like one somebody had deleted there.
- **It is never quiet about trouble.** The automatic runs print only when they
  moved something, so a run where every folder failed to open once looked
  exactly like a run with nothing to do, and the log only ever held successes.
- **A folder somebody makes in Drive becomes a location.** They put it there on
  purpose; the way to honour that is to make it a real place rather than leave
  it lying outside the project.
- **It uses the locations folder a project already has.** Every project on his
  Drive has one and no two are named alike — `daybreak-dp-locations`,
  `DEMO - Location Photos`, `Locations`. Making a second one called `locations`
  beside them would give one thing two homes. Only a project with none gets one.
- **It matches a project to its Drive folder by slug**, which is the convention
  his filing system already runs on: `Daybreak.shotlist` → `daybreak`. A
  *location* is matched by a field on its record, not by its name, so renaming
  one renames its Drive folder instead of orphaning it.
- **It says what it will do before it does it.** The first run on any project is
  a dry run.

## The pieces

| what | it is |
| --- | --- |
| `Sources/main.swift` | all of it — the only implementation |
| `--projects P --drive D --only NAME` | a checking door: run the whole thing on scratch folders, which is the only way to watch a deletion cross without deleting one of his photographs |
| `Shotlister Drive Sync.app` | the worker. **This is what gets Full Disk Access.** No window, no Dock icon |
| `projects.txt` | which projects it may touch. **Baked into the bundle by `build.sh`** — editing it alone changes nothing |
| `agent.sh` | turns the every-fifteen-seconds agent on and off |
| `build.sh` | rebuilds the worker |
| `checks.sh` | 16 checks, on scratch folders. Builds its own worker and leaves the installed one alone |

## Running it

**By hand** — double-click **Sync Locations with Drive** at the top of the repo.
It shows what would change and asks.

**By itself** — double-click **Automatic Drive Sync**. Every fifteen seconds,
whether or not anything is open: a settled run costs ten milliseconds, and the
five minutes this used to wait was a number picked out of caution.

## Checking it

`./checks.sh` — 16 checks, about a minute. It makes a scratch project, a scratch
Drive, and real photographs in a temporary folder, then drives the worker
through the things that have gone wrong: a folder that will not open, a folder
somebody emptied, one photograph deleted, a write Drive refuses.

**Every one of them has been watched failing**, with each fix taken back out in
turn — including the original, where a folder that merely would not open left
the location with nothing on it.

### The one-time permission

Automatic running needs **Full Disk Access**, because macOS will not let a
background program read `Library/CloudStorage` without it. Manual running does
not, since it borrows the permission of whatever launched it — which is why the
button works today and the agent does not.

> System Settings ▸ Privacy & Security ▸ Full Disk Access ▸ **+** ▸
> `Developer/shotlister/bridge/Shotlister Drive Sync`

It is granted to **this one program**, which is the whole reason the syncer is a
compiled bundle instead of the Python script it started as: granting it to
`python3` would have handed the same key to every script on the machine.

## Rebuilding

`./build.sh`. Stop the agent first (`./agent.sh remove`) and start it again
after (`./agent.sh install`) — it runs every fifteen seconds, and rebuilding the
bundle underneath a run is a race that fails the signing step.

This file used to say a rebuild **breaks Full Disk Access** and costs three
clicks to restore. **Measured on 2026-08-21 (macOS 26.5): it does not.** After a
full rebuild and reinstall the agent had run ten times with a last exit code of
0 — and a run that cannot reach Drive exits 2 and says so, so it was reading
Drive. Signing ad-hoc under a *stable identifier*, which `build.sh` has always
done, appears to be what carries the grant across.

That is one machine on one macOS, so if a rebuild ever does lose the grant the
answer is still the three clicks above. But do not avoid rebuilding — in
particular, **adding a project to `projects.txt` needs one**, because the list
is copied into the bundle at build time.
