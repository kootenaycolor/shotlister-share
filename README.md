# Shotlister

A shot-listing app by Nathaniel Regier — a Mac app (Shotlister Studio), an
iPhone app, a Rust engine underneath both, and a web portal (Cloudflare
Workers) for sharing a film with the people working on it.

This is a **shared copy**. It has his code and comments, but none of his films,
people, keys or accounts: real data was removed or swapped for made-up sample
data, and everything tied to his own accounts is a clearly named placeholder
(see *What to fill in* below). The comments still mention his own setup — a
Notion workspace, a status board, `STATUS.md` and `CLAUDE.md` — which are not
part of this copy.

## Getting started

You need a Mac (Apple silicon, macOS 14 or later), Xcode or the Xcode command
line tools (Swift 6), and Rust (`rustup`, stable toolchain).

**Run the engine's tests** (no accounts needed):

    cd engine && cargo test --release

The other Rust crates test the same way: `storage`, `ffi`, `mcp`, `mcpweb`,
`web`, `remote`.

**Build the Mac app** (no accounts needed — it signs ad-hoc when no Developer
ID is found):

    ./studio/build.sh

The app lands in `build/Shotlister Studio.app`. Open it from there. The test
film it is checked against is `studio/fixtures/Daybreak.shotlist` (made up).

**The iPhone app** needs your own Apple Developer team: set `DEVELOPMENT_TEAM`
in `phone/project.yml` (it says `YOURTEAMID`) and build with `phone/build.sh`
(XcodeGen generates the Xcode project).

**The portal (`hub/`) and the sync server (`relay/`)** need a Cloudflare
account (Workers, R2, Durable Objects; Access is optional) and a domain on it.
`cd hub && npm install`, then see `hub/setup.sh` and `relay/setup.sh`. Optional
extras the portal can use: a Notion integration token (`NOTION_TOKEN`), a
read-only Google Drive sign-in (`GDRIVE`, made by `hub/drive-signin.py`), and
Apple push keys for the phone. Secrets are set with `wrangler secret put` and
never live in a file here.

`hub/checks.sh` runs most portal checks on your own machine (first `./hub/build.sh`, and copy `hub/.dev.vars.example` to `hub/.dev.vars`). A handful of his
checks compared the portal against his real Notion and Drive data; those were
removed from this copy, so a few lines in `checks.sh` note that.

## What to fill in

| Placeholder | Where | What it is |
| --- | --- | --- |
| `your-domain.example` (with `sync.`, `share.`, `mcp.`) | `hub/wrangler.toml`, `relay/wrangler.toml`, Swift and JS sources | Your own domain on Cloudflare |
| `your-website.example` | a few links and tests | Your public website |
| `YOUR_SUBDOMAIN.workers.dev` | `hub/wrangler.toml` (`PRESS_HOST`) | Your workers.dev subdomain |
| `owner@example.com`, `owner@your-domain.example` | `hub/wrangler.toml` (`OWNER`), checks | Your sign-in email(s) — each one is an editor on every film |
| `ACCESS_TEAM`, `ACCESS_AUD` (blank) | `hub/wrangler.toml` | Cloudflare Access team name and audience tag, if you use Access |
| `YOURTEAMID` | `phone/project.yml`, `phone/*.entitlements`, `phone/ExportOptions.plist`, `hub/src/push.js` | Your Apple Developer team ID |
| `Developer ID Application: YOUR NAME` | `studio/build.sh` | Your Mac signing identity (optional) |
| `YOUR_KEY_ID`, `YOUR_ISSUER_ID` | `phone/testflight.sh` | App Store Connect API key, for TestFlight uploads |
| `YOUR_SPARKLE_PUBLIC_ED_KEY`, `YOUR_GITHUB_USER/shotlister-releases` | `studio/build.sh`, `release/` | Your own Sparkle update key and releases repo |
| `com.example.*` | bundle identifiers, app group, launch agent | Your own reverse-domain prefix |
| `YOUR_CINEMATOGRAPHY_FOLDER_ID` | `hub/src/step6records.js` | The Google Drive folder id his filing rules live in |
| `feedface0000…` ids | `hub/src/*.js`, tests | Stand-ins for his Notion database ids — use your own databases |
| `/Users/YOUR_USER/…`, `GoogleDrive-you@example.com` | `hub/src/newproject.js`, `step6*.js`, `decks/tools`, the launch agent plist | Paths into your own Google Drive |

**Diagram artwork:** the floor-plan objects in `engine/assets/fso/` are grey
placeholder boxes of the right sizes. His real pictures come from a licensed
pack (*Film Set Objects*) that cannot be shared; if you own the pack,
`tools/fso_import.py` brings it in.

## Double-click, don't type

Everything you'd otherwise run as a command is an app in **[`Apps/`](Apps)**:

| | |
| --- | --- |
| **Rebuild Shotlister** | Build the Mac app from the current code and install it |
| **Install on iPhone** | Build and install the iPhone app |
| **Check the iPhone App** | Run the iPhone checks |
| **Release Shotlister** | Cut a signed, notarised release |
| **Set Up Releasing** | One-time: teach this Mac to talk to Apple |
| **Set Up Sync** | One-time: point this Mac at the sync server |
| **Set Up the Hub** | One-time: put the web portal up |
| **Deploy Shotlister** | Put the relay and the hub up, in that order |
| **Update the Portal** | Pull the latest from Notion into the portal |
| **Back Up Films** / **Restore a Film** | Point-in-time copies into iCloud Drive |
| **Set Up Automatic Backups** | One-time: back up on a schedule |
| **Sync Locations with Drive** / **Automatic Drive Sync** | Mirror location photos to Google Drive |

## What's in here

**The app itself**

| | |
| --- | --- |
| [`engine/`](engine) | Rust. All document state, all rules |
| [`ffi/`](ffi) | The engine's doorway into Swift |
| [`storage/`](storage) | The change log on disk, and merging between devices |
| [`shared/`](shared) | Naming rules compiled into studio, phone and bridge alike |
| [`studio/`](studio) | The Mac app. The real one |
| [`phone/`](phone) | The iPhone app |

**Online**

| | |
| --- | --- |
| [`relay/`](relay) | His own sync server, on Cloudflare |
| [`hub/`](hub) | The portal — where everybody who is not him opens a film |
| [`remote/`](remote) | What should move, and on a Mac, carrying it |
| [`web/`](web) | The engine, in a browser |
| [`mcpweb/`](mcpweb) | The MCP, in a worker |

**Around the edges**

| | |
| --- | --- |
| [`mcp/`](mcp) | Claude's way into a project |
| [`bridge/`](bridge) | Mirrors location photographs and mood board pictures to Google Drive |
| [`backup/`](backup) | Point-in-time copies, so a mistake is undoable |
| [`release/`](release) | How the app gets onto his other Mac and stays current |
| [`tools/`](tools) | The copy checker, and reading text out of a PDF |


## Building by hand

Each part builds with its own `build.sh` and checks itself with its own
`checks.sh` — `studio/build.sh`, `phone/checks.sh` and so on.
`studio/quick.sh` is the fast subset to run while working.

The Mac app always builds to `build/Shotlister Studio.app` and installs to
`/Applications`. Nothing else writes to the installed copy.
