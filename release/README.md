# Releasing Shotlister Studio

Nathaniel double-clicks **Release Shotlister** at the top of the repo. That is
the whole interface. Everything below is for whoever has to change how it works.

## What is here

| | |
| --- | --- |
| `VERSION` | the human version, e.g. `0.3.0`. **Written by the app, not by hand** — the double-click asks which number to put out and puts it here. The build number comes from the commit count and looks after itself |
| `release.sh` | builds, signs, notarises, staples, packs, publishes. `--dry-run` stops before Apple and GitHub |
| `next-version.sh` | the last released version, the next two numbers, and how many changes have landed. Four lines, for the dialog to read |
| `setup-signing.sh` | one-time: the certificate, Apple's key, and the keychain prompt |
| `appcast.py` | adds one entry to the feed the other Mac reads |
| `Shotlister.entitlements` | deliberately empty — see the comment inside it |
| `icon/Shotlister.icon` | the icon, as an **Icon Composer** document — flat artwork plus a description of how macOS should light it. `icon/build-icon.sh` compiles it |
| `Assets.car`, `Shotlister.icns` | what that compile produces, committed so a plain build needs no Xcode. `Assets.car` is the glass icon macOS 26 uses; the `.icns` is the flat fallback for macOS 14 and 15 |
| `vendor/Sparkle.framework` | Sparkle 2.9.6, exactly as its makers shipped it |

`staging/` and `out/` are working space and are not committed.

## How an update actually reaches the other Mac

1. `release.sh` builds the app with `SHOTLISTER_UPDATES=1`, which embeds Sparkle
   and writes `SUFeedURL` and `SUPublicEDKey` into the app.
2. Apple notarises it. Gatekeeper on a Mac that has never seen the app will
   only open it quietly if this happened.
3. The zip is signed with a private key that exists in his keychain and nowhere
   else, and the signature goes into `appcast.xml`.
4. Both files are attached to a GitHub release on `YOUR_GITHUB_USER/shotlister-releases`
   — a public page that holds no source.
5. The other Mac's copy reads that feed, sees a higher build number, checks the
   signature against the public key baked into itself, and offers the update.

Step 3 is the one that matters for safety: without the matching private key,
nothing can hand his Mac something claiming to be a new Shotlister.

## Things that will bite

- **Order.** Sign → notarise → staple → *then* zip and build the disk image.
  Stapling after packing ships an app whose approval only exists on Apple's
  servers, which fails on a Mac that is offline.
- **Never build a release into `build/`.** Three or four threads share this
  checkout and both batteries drive the bundle there. `release.sh` uses
  `release/staging` through `SHOTLISTER_BUILD` for that reason.
- **The everyday build has no updater in it at all** — no Sparkle, no feed, no
  menu item. That is `-DSHOTLISTER_UPDATES`, and it is what keeps an updater
  from waking up in the middle of a 150-check run.
- **The icon has no shine painted into it.** The gloss, the depth and the
  moving highlight are Apple's, applied at draw time from
  `Shotlister.icon`. Painting a highlight into the artwork would give the icon
  two light sources that disagree. Edit it in Icon Composer:

  ```
  open -a "/Applications/Xcode.app/Contents/Applications/Icon Composer.app" release/icon/Shotlister.icon
  ```

- **The next number comes from the tags, not from `VERSION`.** A tag exists
  only because a release finished; the file is just where the chosen number is
  put on the way in. So a release that dies halfway leaves `VERSION` bumped and
  costs nothing — the next double-click offers the same two numbers again, and
  `release.sh` still refuses a version that already has a tag rather than
  quietly publishing a second one.

- **Rebuilding the double-click apps used to strip their icon.** Every launcher
  at the root wears the same icon and nothing in the repo builds it — it was put
  on by hand once. `osacompile` writes a fresh bundle wearing Apple's generic
  applet icon, so `build-apps.sh` now carries the old one across before signing.
  He finds these by their icon.
