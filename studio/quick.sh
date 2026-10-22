#!/bin/bash
# The fast tier. **Twenty checks, not a hundred and twenty.**
#
# His note, 2026-08-20: "is there a way to make these battery tests more
# efficient? … why do they need to be so many of them? They just make the time
# between prompts so slow."
#
# Fair, and the honest answer is that the full battery grew one check per bug
# ever fixed, which is history rather than design. Nearly all of its cost is
# *launching the app* — about two seconds a time, and a flash in his Dock — so
# a hundred and twenty of them is four or five minutes of waiting and flicker
# for a signal that, on the day he asked, caught none of the four bugs he had
# just reported.
#
# So there are two tiers now:
#
#   studio/quick.sh   — this. Twenty checks, ~70 seconds, no Dock flicker. **After every change.**
#   studio/checks.sh  — the full 126. **Before a commit, and not while he works.**
#
# What earns a place here: the things that, when they break, break silently and
# break everything. That is not the same as the things that break most often.
#
# Measured 2026-08-20: 20 checks in 69s with 0 focus trips, against 126 checks
# in ~5 minutes with 112 trips. Same class of signal, a fifth of the wait.
#
# ---- and it grew back, so there is a gate now — Ref 329 ---------------------
#
# Measured again 2026-08-22: **95 checks, 304 seconds.** It had grown one check
# at a time, each for a good reason, and nobody did anything wrong: there was
# simply no moment at which anybody was asked whether a new check belonged in
# the *fast* one. So the four minutes he complained about had quietly come back.
#
# Counted by launch, which is what the time actually is — 111 launches at about
# two and a half seconds each. The gate below runs four sections by default and
# holds the other seventeen behind `--all`. **Nothing is deleted and nothing is
# moved**; every check is still here and still runs.
#
# The four that stayed, and why each one is a *silent* and *total* failure:
#
#   the keyboard reaches the cursor, not the chrome — broken three times, and
#     every time it looked like the app working while the keys went elsewhere
#   a cell takes what is typed, and keeps it — if this is broken, nothing works
#   what a photograph costs — a photograph once went in eight times larger than
#     it came, and every check passed
#   another program changes the project — the Drive sync deleted photographs
#     while the app drew them; nothing else here runs two processes at once
#
# **Adding a check?** It goes behind the gate unless you can say which of those
# two words applies to it. That question is the whole point of the gate; the
# four minutes were only the symptom.
#
# Usage: studio/quick.sh              (from the repo root, the fast four)
#        studio/quick.sh --all        every section, the way it was
#        studio/quick.sh --only "…"   the fast four and one held section, by name
set -u
cd "$(dirname "$0")/.."
# **Which app to drive.** `SHOTLISTER_APP=/path/to/Some.app/Contents/MacOS/ShotlisterStudio`
# points the battery at a bundle of its own. Ref 331: `build/Shotlister
# Studio.app` is one path and any number of threads build to it, and the first
# thing `studio/build.sh` does is delete it — so a thread rebuilding while this
# runs takes the program out from under it. That cost one run 79 confident and
# completely false failures on 2026-08-23.
APP="${SHOTLISTER_APP:-build/Shotlister Studio.app/Contents/MacOS/ShotlisterStudio}"
# **Which display the checking windows open on.** His instruction, 2026-09-02:
# keep them off the monitor he is working on. He has made the PA32UCDM his
# main, and the main display is usually index 0 — so this asks for the HP by
# *name*, which stays right however the displays are arranged.
# `SHOTLISTER_SCREEN=PA32` (or an index) points a run somewhere else.
SCREEN="${SHOTLISTER_SCREEN:-HP}"
[ -x "$APP" ] || { echo "no app built — run studio/build.sh"; exit 1; }
SCRATCH="$(mktemp -d)/Quick.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$SCRATCH"
defaults delete com.example.shotlister.studio columnWidths.checking 2>/dev/null || true
# The export box keeps everything under one key, and a checking run gets its
# own — so there is exactly one thing to clear before a run.
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
# Export presets: a checking run keeps its own copy in the temp folder.
rm -f "${TMPDIR:-/tmp}/shotlister-check-export-presets.json"

# **Every run says which tab it is on.** It did not, and on 2026-08-21 the whole
# battery failed 20 of 30 because the app opened on *Locations* — which is where
# he had left it. Nothing was broken; the table simply was not on screen. The
# rule was already written down after the side panel did the same thing: a check
# whose result depends on his settings is not a check.

pass=0; fail=0; trips=0; held=0
started=$(date +%s)

# The gate. A section named here runs only under `--all`; it is skipped and
# counted, never quietly dropped — the count is printed at the end so nobody
# can mistake a fast run for a full one.
ALL=no
[ "${1:-}" = "--all" ] && ALL=yes
# `studio/quick.sh --only "the console's doors"` runs one held section and
# the fast four — the thing to reach for after a change to one section, when
# `--all` is five minutes for a question one section answers.
ONLY=""
[ "${1:-}" = "--only" ] && ONLY="${2:-}"
slow() {
  [ "$ALL" = yes ] && return 0
  [ -n "$ONLY" ] && [ "${1:-}" = "$ONLY" ] && return 0
  held=$((held+1))
  return 1
}

# One check: run the app once with these flags, look for `want` in what it says.
q() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qE "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "engine holds|expected|cursor rests|columns:" | sed 's/^/       /'
  fi
}

# The same, but on a **fresh copy of the project** each time. Checks that
# assert particular words can only do that on a fixture nothing has touched —
# and this file deliberately mutates one as it goes. Two of my own checks failed
# on the fixture's history rather than on the code before I gave them this.
qfresh() {
  local name="$1"; local want="$2"; shift 2
  local fresh; fresh="$(mktemp -d)/Fresh.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "rows=" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}

echo "── the keyboard reaches the cursor, not the chrome ──"
# The class that has broken three times: something asks the sidebar where the
# cursor is. Every check here puts the two in *different* scenes on purpose,
# which is the only way this class is visible at all.
q "arrow down stays in the cursor's scene" "cursor rests on 35B" \
  --scene 34 --shot 35A --type "↓" --shots
q "arrow up crosses the scene line"        "cursor rests on 34" \
  --scene 34 --shot 35A --type "↑" --shots
q "paste reaches a text cell elsewhere"    "MATCHES" \
  --scene 34 --shot 35A --cell movement --paste "Handheld" --expect "Handheld"
q "paste reaches a dropdown elsewhere"     "MATCHES" \
  --scene 34 --shot 35A --cell size --paste "CU" --expect "CU"
q "delete reaches a cell elsewhere"        "MATCHES" \
  --scene 34 --shot 35A --cell movement --type "⌫" --expect ""
q "add-shot lands in the cursor's scene"   "35" \
  --scene 34 --shot 35A --type "⌘↩" --shots

echo "── a cell takes what is typed, and keeps it ──"
q "typing writes a cell"        "MATCHES" --scene 34 --cell title --type "abc" --expect "abc"
# Typing one letter into a dropdown lands on the first term that starts with it.
# **This expected "M/OTS" until 2026-08-22**, and was right to: the fixture's only
# size beginning with M was M/OTS. His standing lists put a plain "M" on every
# project, so "M" now completes to itself — the check was stale, not the app.
q "a dropdown takes a value"    "MATCHES" --scene 34 --cell size --type "M" --expect "M"
q "delete clears a cell"        "MATCHES" --scene 34 --cell movement --type "⌫" --expect ""
q "the words survive a relaunch" "MATCHES" --scene 34 --cell title --type "↩↩" --expect "abc"

# Lens Stack is always on: Modifiers and Filters are never columns of their
# own, so Lens is followed straight by Equipment.
q "lens stack folds two columns into Lens" "lens=200 support=" --columns

if slow "a selection, and what a paste does to one"; then
echo "── a selection, and what a paste does to one ──"
q "one value fills a range"     "rows=34A:FILLE,34B:FILLE" \
  --scene 34 --cell description --type "" --tdrag "880,247,880,503" --paste "FILLED" --columns
q "a block lands row by row"    "rows=34A:one,34B:two" \
  --scene 34 --cell description --type "" --tdrag "880,247,880,503" --paste "one
two
three
four" --columns

# **A range made by dragging, checked by what a paste does to it.** The
# `range:` report races the drag's own timers and reads empty even when the
# range is there, so the honest probe is behavioural: paste one value and see
# how far it spreads. Five cells means five cells were selected.
qfresh "a plain drag selects a range" "rows=34A:XX,34B:XX,34C:XX,34D:XX,34E:XX" \
  --scene 34 --tdrag "880,250,880,600" --paste "XX" --cell description --columns

fi
if slow "a shot can be picked up and put down"; then
echo "── a shot can be picked up and put down ──"
# Both cases, because they used to disagree: the sidebar on the shot's own
# scene, and the sidebar somewhere else entirely.
# On a fresh copy: it used to read the words an earlier check had pasted into the
# shared one, so it only ever passed in a full run. 34A (Milo) is dropped two rows down.
qfresh "carried within the shown scene"  "rows=34A:Felix,34B:Front,34C:Milo ,34D:Front,34E:Wide" \
  --scene 34 --tdrag "288,264,288,400" --type "" --columns
q "carried while the chrome is away" "34" \
  --scene 33 --tdrag "288,465,288,600" --type "" --shots
# Into a *different scene*, and **the letters close up behind it** — his call,
# "no gap". This used to assert `34B:` because the hole stayed open; the engine
# now reflows the scene a shot leaves, exactly as it always did for a deletion.
qfresh "carried into another scene, no gap" "rows=34A:Felix,34B:Front,34C:Front,34D:Wide" \
  --scene 34 --tdrag "288,250,288,740" --type "" --columns
# Copy several cells, click *one* cell, paste: the block lands from there and
# runs down. Pasting all three lines into the one cell was the old behaviour and
# the only reading that is never useful.
qfresh "a copied block spills from one cell" "rows=34A:Milo ,34B:one,34C:two,34D:three,34E:Wide" \
  --scene 34 --shot 34B --cell description --paste "one
two
three" --columns
# **A run of whole shots travels together, in order.** `--pick` hands the app a
# selection by shot number, because a checking run gets one click and building
# a set takes several — without it this could only be checked by reading.
# Three carried to the foot: the two left behind come first, then the run.
qfresh "a run of shots carries together" "rows=34A:Front,34B:Wide ,34C:Milo ,34D:Felix,34E:Front" \
  --scene 34 --pick "34A,34B,34C" --tdrag "288,250,288,560" --type "" --columns
qfresh "…and lands mid-scene in order"   "rows=34A:Front,34B:Milo ,34C:Felix" \
  --scene 34 --pick "34A,34B" --tdrag "288,250,288,430" --type "" --columns

# **Copying whole shots is not a paste of cells.** A shot carries its frames and
# its gear; smearing its columns as text loses all of that and lands them in
# whatever column the cursor was in — which is what he photographed.
qfresh "shots copied into another scene" "rows=35A:Shot ,35B:Wide ,35C:Milo ,35D:Felix" \
  --scene 35 --pick "34A,34B" --copyto "35" --cell description --columns
# **And the whole batch is one thing to take back.** Per-shot undo steps are
# what made undo feel arbitrary: "hitting Command-Z should undo the duplication
# of those four shots all at once."
qfresh "one undo takes the whole copy back" "rows=35A:Shot ,35B:Wide " \
  --scene 35 --pick "34A,34B" --copyto "35" --type "⌘z" --cell description --columns

fi
if slow "narrowing, both kinds"; then
echo "── narrowing, both kinds ──"
q "a shot facet narrows"    "narrowed: true"  --scene 34 --facet size W --columns
q "a scene facet narrows"   "hidden scenes: [1-9]" --scene 34 --facet location CAR --columns
q "clearing puts it back"   "narrowed: false" --scene 34 --facet all "" --columns
# **And the chip says the place's name.** His report: "filter by location shows
# up as a hash of numbers and letters." A location is narrowed by id, and every
# other line of every report prints that id and is right to — so this is the one
# check that can see it. Ref 301.
qfresh "a location chip says the place, not its id" "filter chips: location_id→County Jail" \
  --addlocation "County Jail" --linkscene 34 --facet location_id "County Jail" --filtering

fi
if slow "the shape of the table"; then
echo "── the shape of the table ──"
# Zoom before resize, deliberately: a dragged column edge is remembered, and
# the zoom is measured *against* the column's width. Run the other way round
# the zoom checks compute from 240 rather than 170 and fail for a reason that
# has nothing to do with zoom — which is the trap the full battery already
# walked into once today.
q "the zoom reaches the type" "title=200" --scene 34 --type "⌘=" --columns
q "⌘0 is the middle again"  "title=170" --scene 34 --type "⌘=⌘0" --columns
q "a column edge resizes"   "title=240" --scene 34 --tdrag "628,115,698,115" --type "" --columns
# **The stretch lets go.** Columns share out whatever a wide window has spare;
# narrow it and they must return to exactly the widths he set. This is the half
# that would quietly corrupt his stored widths if it went wrong, so it is the
# half worth a check every time. (The stretching half is proved by hand with
# `--wide` and a few columns hidden — it needs nine launches to set up, so it
# lives in the full battery rather than here.)
qfresh "a narrow window keeps his own widths" "spread: 0" \
  --wide 900 --scene 34 --cell size --type "" --columns
# **Both side panels resize.** The handle sits on the table's right edge — the
# `table:` report gives that number, so this coordinate is measured rather than
# guessed. Three of my guesses missed it before I made the app say where it was.
qfresh "the right panel can be dragged wider" "panel: 480" \
  --scene 34 --panel --tdrag "1243,400,1083,400" --type "" --columns
# ...and never narrower than it opens at, which is the half that would spoil it.
qfresh "…but never below the width it opens at" "panel: 320" \
  --scene 34 --panel --tdrag "1243,400,1500,400" --type "" --columns

fi
if slow "locations"; then
echo "── locations ──"
# **A location is a record, and the scene's own word survives it.** The two
# facts a scene now carries — the slugline's "CAR" and the address the crew
# drives to — are exactly the pair that would be quietly conflated by a wrong
# field name, and nothing on screen would look wrong when it was.
qloc() {
  local name="$1"; local want="$2"; shift 2
  local fresh; fresh="$(mktemp -d)/Places.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place locations "$@" --locations 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "^locations:|^open location|^scene locations:" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}

qloc "a location holds an address and a pin" \
  "County Jail; 1 Jail Rd; 34.0500/-118.2500" \
  --addlocation "County Jail" --setlocation address "1 Jail Rd" \
  --setlocation latitude "34.0500" --setlocation longitude "-118.2500"
qloc "a scene can be shot at one" "1 scenes" \
  --addlocation "County Jail" --linkscene 34
# The other half, and the one that would be a silent disaster: pointing a scene
# at a location must not touch the word the script wrote on its slugline.
qloc "…and the script's own word is untouched" "34=CAR/County Jail" \
  --scenefield location CAR --addlocation "County Jail" --linkscene 34

# **What the phone brought home.** A fabricated scout folder, in the layout
# `handoff/from-phone.md` specifies — read in, and read in *once*.
scout() {
  local into="$1"; local id="8B0F4E2A-1111-4E1D-9C3A-000000000001"
  mkdir -p "$into/locations/$id/photos"
  cat > "$into/locations/$id/location.json" <<JSON
{ "id": "$id", "name": "Office Test", "address": "100 Example Way",
  "latitude": 34.0522, "longitude": -118.2437, "notes": "Gate code 1234",
  "createdAt": "2026-08-21T13:55:20Z", "capturedBy": "iPhone" }
JSON
}
scouted="$(mktemp -d)/Scout.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$scouted"
scout "$scouted"
out=$("$APP" --project "$scouted" --screen "$SCREEN" --place scenes --locations 2>&1)
if echo "$out" | grep -qF "locations: "; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a scout waiting in the folder is not imported by itself"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a scout waiting in the folder is not imported by itself"
fi
out=$("$APP" --project "$scouted" --screen "$SCREEN" --place locations --homecoming --locations 2>&1)
if echo "$out" | grep -qF "Office Test; 100 Example Way; 34.0522/-118.2437"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and comes in whole when asked"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and comes in whole when asked"
  echo "$out" | grep -E "^locations:" | sed 's/^/       /'
fi
# Twice must make one. The record carries the folder's name for exactly this.
out=$("$APP" --project "$scouted" --screen "$SCREEN" --place locations --homecoming --locations 2>&1)
# Counted inside the `locations:` line alone — `open location:` names it too,
# and counting whole lines made a correct answer look like a doubled one.
if [ "$(echo "$out" | grep '^locations:' | grep -o 'Office Test' | wc -l | tr -d ' ')" = "1" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and bringing it in twice makes one of it"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and bringing it in twice makes one of it"
  echo "$out" | grep -E "^locations:" | sed 's/^/       /'
fi
rm -rf "$(dirname "$scouted")"

# **A scene that moves between two places.** His ask, 2026-08-22: "add multiple
# locations or areas per scene (in case it moves between)". Two runs, because
# the harness opens whichever location was added last and one run can only ever
# hold one open — the check that tried to do it in one run passed while proving
# nothing.
moving="$(mktemp -d)/Moving.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$moving"
"$APP" --project "$moving" --screen "$SCREEN" --place locations \
  --addlocation "County Jail" --linkscene 34 >/dev/null 2>&1
"$APP" --project "$moving" --screen "$SCREEN" --place locations \
  --addlocation "Pharmacy" --alsoscene 34 >/dev/null 2>&1
out=$("$APP" --project "$moving" --screen "$SCREEN" --place locations --locations 2>&1)
if echo "$out" | grep -qF "34=CAR/County Jail+Pharmacy"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a scene can be shot at two places"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a scene can be shot at two places"
  echo "$out" | grep -E "^scene locations:" | sed 's/^/       /'
fi
# …and narrowing to the second of them finds it, which is the half that would
# quietly go wrong: the single field holds only the first.
out=$("$APP" --project "$moving" --screen "$SCREEN" --place scenes \
       --facet location_id "Pharmacy" --filtering 2>&1)
if echo "$out" | grep -qE "hiddenScenes 3.*narrowed true"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and narrowing to the second one finds it"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and narrowing to the second one finds it"
  echo "$out" | grep -E "^filter" | sed 's/^/       /'
fi
rm -rf "$(dirname "$moving")"

fi
if slow "photographs: pointing, and looking"; then
echo "── photographs: pointing, and looking ──"
# **Two gestures, not one.** His ask of 2026-08-21: a click puts a blue box round
# a still and *nothing else happens*; a double-click or the space bar pops the
# viewer out. Both halves look identical in a photograph — a blue box with a
# window and a blue box without one — so the report says which in words.
photos="$(mktemp -d)/Photos.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$photos"
pid="8B0F4E2A-1111-4E1D-9C3A-000000000001"
mkdir -p "$photos/locations/$pid/photos"
cat > "$photos/locations/$pid/location.json" <<JSON
{ "id": "$pid", "name": "Office Test", "address": "100 Example Way",
  "latitude": 34.0522, "longitude": -118.2437, "notes": "Gate code 1234",
  "createdAt": "2026-08-21T13:55:20Z", "capturedBy": "iPhone",
  "driveFolder": "Office Test" }
JSON
python3 - "$photos/locations/$pid/photos" <<'PYEOF'
import sys, zlib, struct
def png(path, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
d = sys.argv[1]
for n, colour in enumerate([(180,140,90), (90,120,180), (120,170,110)]):
    png(f"{d}/2026-08-21T1355{n:02d}.png", 320, 240, colour)
PYEOF
"$APP" --project "$photos" --screen "$SCREEN" --place locations --homecoming >/dev/null 2>&1

qphoto() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$photos" --screen "$SCREEN" --place locations \
                    --location "Office Test" "$@" --locations 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "^photos:" | sed 's/^/       /'
  fi
}

qphoto "a click picks a photograph and opens nothing" \
  "picked: 2  across: 6  viewer: false" --photo 2
qphoto "an arrow walks to the next one, still opening nothing" \
  "picked: 2  across: 6  viewer: false" --photo 1 --hold --type "→"
qphoto "…and back again" \
  "picked: 1  across: 6  viewer: false" --photo 2 --hold --type "←"
# **The space bar is the gesture he named** — "almost like hitting the space bar
# in preview in Finder".
qphoto "the space bar pops the viewer out" \
  "picked: 1  across: 6  viewer: true" --photo 1 --hold --type " "
# And once it is out, the arrows carry it. Two viewer lines, two different files.
out=$("$APP" --project "$photos" --screen "$SCREEN" --place locations --location "Office Test" \
        --photo 1 --hold --type " →" --locations 2>&1)
if [ "$(echo "$out" | grep -c '^viewer: ')" -ge 2 ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and then the arrows carry it with them"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and then the arrows carry it with them"
  echo "$out" | grep -E "^viewer:|^photos:" | sed 's/^/       /'
fi
# **Clicking another photograph carries the viewer with it** — the thing he asked
# for after using it: "when you click another photo, it live updates."
out=$("$APP" --project "$photos" --screen "$SCREEN" --place locations --location "Office Test" \
        --openphoto 1 --photo 3 --locations 2>&1)
if [ "$(echo "$out" | grep -c '^viewer: ')" -ge 2 ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "clicking another photograph updates the open viewer"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "clicking another photograph updates the open viewer"
  echo "$out" | grep -E "^viewer:|^photos:" | sed 's/^/       /'
fi
rm -rf "$(dirname "$photos")"

fi
echo "── what a photograph costs ──"
# **A photograph is sized on the way in, and is still a photograph afterwards.**
# The first version of the compressor produced a bitmap of the right size, in the
# right format, at a plausible number of bytes — and every pixel of it was black.
# Size and dimensions both passed. So this asserts a *floor* as well as a
# ceiling: a blank 2560×1920 JPEG compresses to well under 100 KB, and a real one
# cannot. It is the cheapest stand-in for looking at the picture.
sized="$(mktemp -d)/Sized.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$sized"
mkdir -p "$sized/locations/AAA/photos"
cat > "$sized/locations/AAA/location.json" <<'JSON'
{ "id": "AAA", "name": "Big", "address": "", "notes": "",
  "createdAt": "x", "capturedBy": "iPhone" }
JSON
python3 - "$sized/locations/AAA/photos/room.jpg" <<'PYEOF'
import sys, random
from struct import pack
# A 4032×3024 photograph's worth of detail, without a fixture in the repo.
try:
    from PIL import Image
except ImportError:
    sys.exit(0)
random.seed(7)
w, h = 4032, 3024
im = Image.new("RGB", (w, h))
px = im.load()
for y in range(0, h, 8):
    for x in range(0, w, 8):
        c = (int(120 + 80 * (x / w)) + random.randint(-20, 20),
             int(110 + 70 * (y / h)) + random.randint(-20, 20),
             int(100 + 60 * ((x + y) / (w + h))) + random.randint(-20, 20))
        for dy in range(8):
            for dx in range(8):
                if x + dx < w and y + dy < h:
                    px[x + dx, y + dy] = c
im.save(sys.argv[1], quality=88)
PYEOF
if [ -f "$sized/locations/AAA/photos/room.jpg" ]; then
  before=$(stat -f%z "$sized/locations/AAA/photos/room.jpg")
  "$APP" --project "$sized" --screen "$SCREEN" --place locations --homecoming >/dev/null 2>&1
  after=$(find "$sized/media" -name "*.jpg" -exec stat -f%z {} \; | sort -rn | head -1)
  after=${after:-0}
  # Never bigger than it arrived, and never so small it came out blank.
  if [ "$after" -gt 200000 ] && [ "$after" -le "$before" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a photograph is made smaller, and is still a photograph"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a photograph is made smaller, and is still a photograph"
    printf '       source %s bytes, stored %s — under 200k means it came out blank\n' "$before" "$after"
  fi
  # And it must not be re-imported for ever: the name it is filed under changes
  # extension when it is re-encoded, so the "have I got this?" test compares
  # stems. Getting that wrong re-imports every photograph on every visit.
  out=$("$APP" --project "$sized" --screen "$SCREEN" --place locations --homecoming \
          --location "Big" --locations 2>&1)
  if echo "$out" | grep -q "^photos: 1 "; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and importing it twice does not make two"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and importing it twice does not make two"
    echo "$out" | grep -E "^photos:|^photo names:" | sed 's/^/       /'
  fi

  # **And it wears the location's name.**
  #
  # This check used to assert the opposite — that a photograph keeps the name it
  # arrived with — and that was right until 2026-08-22, when he ruled on Ref 273
  # that a photograph *on a location* is renamed after the location and its
  # area, while everywhere else keeps its own name. The newer instruction wins;
  # the old expectation is written here rather than deleted so that nobody
  # reads the change as a regression and puts it back.
  #
  # `Big` is the location the scout folder brings in, so `big-01.jpg`.
  if echo "$out" | grep -q "^photo names: big-01\."; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and it is named after the location it landed on"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and it is named after the location it landed on"
    echo "$out" | grep -E "^photo names:" | sed 's/^/       /'
  fi
fi
rm -rf "$(dirname "$sized")"

echo "── another program changes the project ──"
# **The thing that actually bit him**: the Drive sync deleted a location's
# photographs while the app sat open, and the app went on drawing them. This
# opens a run, has a *second* run delete them two seconds later, and asks the
# first one what it thinks afterwards. Nothing else in the battery involves two
# processes at once, and nothing else could have caught it.
watched="$(mktemp -d)/Watch.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$watched"
mkdir -p "$watched/locations/AAA/photos"
cat > "$watched/locations/AAA/location.json" <<'JSON'
{ "id": "AAA", "name": "Office", "address": "", "notes": "",
  "createdAt": "x", "capturedBy": "iPhone" }
JSON
python3 - "$watched/locations/AAA/photos" <<'PYEOF'
import sys, zlib, struct
def png(path, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
for n, c in enumerate([(180,140,90), (90,120,180), (120,170,110)]):
    png(f"{sys.argv[1]}/p{n}.png", 320, 240, c)
PYEOF
"$APP" --project "$watched" --screen "$SCREEN" --place locations --homecoming >/dev/null 2>&1
# Order matters: the keeping check needs photographs, so it runs first.
( sleep 2
  "$APP" --project "$watched" --screen "$SCREEN" --place scenes --device 2 \
     --scene 34 --set description "something else" >/dev/null 2>&1 ) &
out=$("$APP" --project "$watched" --screen "$SCREEN" --place locations --location "Office" \
        --photo 1 --stay 8 --locations 2>&1)
wait
if echo "$out" | grep -qE "^photos: 3 .*cached: [1-9]"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a merge that touches no photograph keeps them in hand"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a merge that touches no photograph keeps them in hand"
  echo "$out" | grep -E "^photos:|pulled" | sed 's/^/       /'
fi

( sleep 2
  "$APP" --project "$watched" --screen "$SCREEN" --place locations --device 2 --location "Office" \
     --dropphoto 1 --dropphoto 1 --dropphoto 1 >/dev/null 2>&1 ) &
out=$("$APP" --project "$watched" --screen "$SCREEN" --place locations --location "Office" \
        --stay 8 --locations 2>&1)
wait
if echo "$out" | grep -q "^photos: 0 "; then
  pass=$((pass+1)); printf '  ✓  %s\n' "an open app notices what another program deleted"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "an open app notices what another program deleted"
  echo "$out" | grep -E "^photos:|pulled" | sed 's/^/       /'
fi
rm -rf "$(dirname "$watched")"

echo "── sync, on a Mac that has never had it ──"
# **The laptop's whole journey.** The sync button is drawn only where sync
# already works, so it cannot be the way in — and until 2026-09-01 there was no
# other way in at all on a Mac without the repo, because *Set Up Sync* runs a
# script out of a hard-coded path. His laptop simply had no button, for ever.
#
# The Keychain itself is not touched here and cannot be: `token` short-circuits
# for a checking run. What is checked is everything around it — that the sheet
# opens, that a half-filled one is refused *with the reason*, and that a saved
# address and password turn `ready` on, which is what puts the button on screen.
q "the way in is in the menu"            "menu items:.*Set Up Sync" --menu
q "the setup sheet opens"                "sync setup: shown" --syncsetup
q "nothing saved, nothing offered"       "sync ready: false" --syncsave "" ""
q "a half-filled one says which half"    "sync save: No password yet." --syncsave "sync.example.com" ""
q "saving turns the sync button on"      "sync ready: true" --syncsave "sync.example.com" "abc123"

if slow "a scanned room"; then
echo "── a scanned room ──"
# The geometry is the engine's and has its own tests (`engine/tests/rooms.rs`).
# What these check is the half that only exists in the app: that the window
# opens, that it asks the engine, and that it says so when a scan has no
# measurements in it rather than drawing an approximation.
qroom() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place locations "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "^scan:" | sed 's/^/       /'
  fi
}
qroom "the sample room draws, six walls and all" \
  "measured: true  walls: 6  items: 12" --floorplan
qroom "a scan with no measurements says so" \
  "measured: false  walls: 0" --floorplan /dev/null

fi
if slow "a column the project made"; then
echo "── a column the project made ──"
# **Deleting one takes what is written in it**, which is why it says so first.
# Only a column this film made: Shot Size is the app's shape, not the project's.
col="$(mktemp -d)/Columns.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$col"
out=$("$APP" --project "$col" --screen "$SCREEN" --place scenes \
        --addcolumn "text Rigging" --columns 2>&1)
echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
if echo "$out" | grep -q "^custom columns: Rigging/text"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a column the project made exists"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a column the project made exists"
  echo "$out" | grep -E "^custom columns:" | sed 's/^/       /'
fi
out=$("$APP" --project "$col" --screen "$SCREEN" --place scenes \
        --deletecolumn "Rigging" --columns 2>&1)
if echo "$out" | grep -q "^custom columns: *$"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and can be taken away again"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and can be taken away again"
  echo "$out" | grep -E "^custom columns:" | sed 's/^/       /'
fi
rm -rf "$(dirname "$col")"

fi
if slow "the references board"; then
echo "── the references board ──"
# **The same hands as the photograph wall** (Ref 151): a click points, the
# arrows walk, ⌘ and ⇧ build a set, and right-clicking a picked set offers to
# unpin all of it.
#
# `--after 1.8` is not decoration, and it is not superstition either. The board
# installs its keyboard when it appears, so without a settle the arrow is posted
# before the panel is on screen and lands nowhere — one run in three at 0, and
# it still missed once at 1.0 under a loaded battery. The real fix is to install
# the monitor at app level rather than on the view's appearance; until then this
# is the honest number.
board="$(mktemp -d)"
cp -R studio/fixtures/Daybreak.shotlist "$board/Refs.shotlist"
python3 - "$board" <<'PYEOF'
import sys
try:
    from PIL import Image
except ImportError:
    sys.exit(0)
for n, c in ((1, (200, 60, 60)), (2, (60, 140, 200))):
    Image.new("RGB", (600, 400), c).save("%s/ref%d.png" % (sys.argv[1], n))
PYEOF
if [ -f "$board/ref2.png" ]; then
  for n in 1 2; do
    "$APP" --project "$board/Refs.shotlist" --screen "$SCREEN" --place scenes --scene 33 \
           --pin "$board/ref$n.png" >/dev/null 2>&1
  done
  out=$("$APP" --project "$board/Refs.shotlist" --screen "$SCREEN" --place scenes --scene 33 \
          --panel references --reference 1 --columns 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "references: 2  picked: 1"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a click points at a reference"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a click points at a reference"
    echo "$out" | grep -E "^references:" | sed 's/^/       /'
  fi

  # **The arrow is not checked here, and that is deliberate.**
  #
  # It works — proved four runs out of four on its own — but the board installs
  # its keyboard when it *appears*, so inside a loaded battery the key is posted
  # before the panel is on screen and lands nowhere. It failed at a 1.0 second
  # settle and again at 1.8, which says the fix is not a longer wait: the
  # monitor belongs at app level, guarded by which panel is showing, the way the
  # photograph wall's is. Until then a check here would fail for a reason that
  # has nothing to do with the feature, and a flaky check is worse than none.
  # Written down rather than left as a mystery for whoever meets it next.
fi
rm -rf "$board"

fi
if slow "a shot other shots stand in for"; then
echo "── a shot other shots stand in for ──"
# **Master and linked shots**, carried over from the old app. A film breaks a
# scene up and comes back to the same setup later; rather than describing it
# twice and letting the two drift, one shot is the master and the others point
# at it. His ask, 2026-08-22: *"they were tied together with auto update, and
# you would know what shot it was referring to, even if it was in another
# scene."*
mast="$(mktemp -d)/Master.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$mast"
out=$("$APP" --project "$mast" --screen "$SCREEN" --place scenes --scene 34 \
        --master 34A 1 --link 54A 34A --columns 2>&1)
echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
if echo "$out" | grep -q "rows=34AM:"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a shot can be made a master"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a shot can be made a master"
  echo "$out" | grep -oE "rows=[^ ]*" | sed 's/^/       /'
fi

# **Typing into either face types into both** — that is the whole of it.
"$APP" --project "$mast" --screen "$SCREEN" --place scenes --scene 54 --shot 54A \
       --set description "SAID ONCE" >/dev/null 2>&1
out=$("$APP" --project "$mast" --screen "$SCREEN" --place scenes --scene 34 --columns 2>&1)
if echo "$out" | grep -q "rows=34AM:SAID"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and typing into the one standing in reaches the master"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and typing into the one standing in reaches the master"
  echo "$out" | grep -oE "rows=[^ ]*" | sed 's/^/       /'
fi

# And the shot that stands in says which one it is, wherever it lives.
out=$("$APP" --project "$mast" --screen "$SCREEN" --place scenes --scene 54 --columns 2>&1)
if echo "$out" | grep -q "rows=54A→34A:SAID"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and it says which shot it is standing in for"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and it says which shot it is standing in for"
  echo "$out" | grep -oE "rows=[^ ]*" | sed 's/^/       /'
fi

# **And the picture comes across too.** His report, 2026-08-22: the words
# carried over and the image did not. A frame is the loudest thing on a row.
out=$("$APP" --project "$mast" --screen "$SCREEN" --place scenes --scene 54 --columns 2>&1)
if echo "$out" | grep -q "^frames: 54A:1,"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and it shows the master's picture, not an empty box"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and it shows the master's picture, not an empty box"
  echo "$out" | grep -E "^frames:" | sed 's/^/       /'
fi

# **Report, never destroy.** Cutting a link leaves the shot saying what it was
# saying a moment ago, not what it said before it was ever linked.
"$APP" --project "$mast" --screen "$SCREEN" --place scenes --link 54A none >/dev/null 2>&1
out=$("$APP" --project "$mast" --screen "$SCREEN" --place scenes --scene 54 --columns 2>&1)
if echo "$out" | grep -q "rows=54A:SAID"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and cutting it loose keeps what it was showing"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and cutting it loose keeps what it was showing"
  echo "$out" | grep -oE "rows=[^ ]*" | sed 's/^/       /'
fi
rm -rf "$(dirname "$mast")"

fi
if slow "narrowing the film"; then
echo "── narrowing the film ──"
# **The filter, measured rather than photographed.** Every other report reads
# the scene outline, which is deliberately never narrowed, so a filter that did
# nothing and one that did everything looked identical from outside.
narrow="$(mktemp -d)/Narrow.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$narrow"
out=$("$APP" --project "$narrow" --screen "$SCREEN" --place scenes \
        --facet time_of_day NIGHT --filtering 2>&1)
echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
if echo "$out" | grep -q "shown 8  hiddenScenes 3  narrowed true"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "narrowing to night leaves the night scene"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "narrowing to night leaves the night scene"
  echo "$out" | grep -E "^filter" | sed 's/^/       /'
fi

# **A field that points at a record could never match anything.** Narrowing to
# a location asked "is this scene's location the text 'abc123'?" of a value that
# is a reference, and a reference fell through to no. So the answer was always
# none, on every filter of that kind. Found 2026-08-22 while reading why some of
# his filter categories came back empty.
"$APP" --project "$narrow" --screen "$SCREEN" --place scenes \
       --addlocation "Car Park" --linkscene 34 >/dev/null 2>&1
out=$("$APP" --project "$narrow" --screen "$SCREEN" --place scenes \
        --facet location_id "Car Park" --filtering 2>&1)
if echo "$out" | grep -q "shown 5  hiddenScenes 3  narrowed true"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and narrowing to a location leaves the scenes shot there"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and narrowing to a location leaves the scenes shot there"
  echo "$out" | grep -E "^filter" | sed 's/^/       /'
fi

# **A category with nothing in it is never offered.** An empty submenu is a
# filter nobody can use, and it looks exactly like one that does not work.
out=$("$APP" --project "$narrow" --screen "$SCREEN" --place scenes --filtering 2>&1)
if echo "$out" | grep -q "filter options: location_id:1 location:4"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and every category offered has something in it"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and every category offered has something in it"
  echo "$out" | grep -E "^filter options" | sed 's/^/       /'
fi
rm -rf "$(dirname "$narrow")"

fi
if slow "a film gets a name"; then
echo "── a film gets a name ──"
# **The package follows the title, while the project is still new.** The
# project browser and the Finder both list the *file's* name, so a film called
# Call Her Back living in Untitled.shotlist is named on exactly one screen. The
# rename moves a folder on disk, which makes it the riskiest thing on the setup
# screen and the one most worth checking.
naming="$(mktemp -d)"
"$APP" --project "$naming/Untitled.shotlist" --screen "$SCREEN" --place scenes \
       --rename "Call Her Back" >/dev/null 2>&1
if [ -d "$naming/Call Her Back.shotlist" ] && [ ! -d "$naming/Untitled.shotlist" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "naming a new film names its file too"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "naming a new film names its file too"
  ls "$naming" | sed 's/^/       /'
fi

# **And never once there is work in it.** Renaming a package another Mac or the
# Drive bridge is watching would look to them like the old one vanished and a
# different one appeared.
cp -R studio/fixtures/Daybreak.shotlist "$naming/Keep.shotlist"
out=$("$APP" --project "$naming/Keep.shotlist" --screen "$SCREEN" --place scenes \
        --rename "Renamed Away" 2>&1)
echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
if echo "$out" | grep -q 'renamed: title "Renamed Away"  file "Keep"'; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…but a film with work in it keeps its file"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…but a film with work in it keeps its file"
  echo "$out" | grep -E "^renamed:" | sed 's/^/       /'
fi
rm -rf "$naming"

fi
if slow "linked to the rest of his systems"; then
echo "── linked to the rest of his systems ──"
# **The Projects Console link, and the folder it finds.** His ask: a film can
# say which of his console projects it is, and that link tells the Google Drive
# sync which folder to use — found automatically where it can be, chosen by hand
# where it cannot.
#
# Skipped where the console has never run, because the cache it keeps is what
# this reads. Named after one of his real films on purpose: the part worth
# checking is the one that reads Google Drive's own id off a folder on this Mac,
# and that cannot be faked with a fixture.
console="$HOME/Developer/.projects-console-state/projects-cache.json"
if [ -f "$console" ] && grep -q '"Call Her Back"' "$console"; then
  linkdir="$(mktemp -d)"
  cp -R studio/fixtures/Daybreak.shotlist "$linkdir/Linked.shotlist"
  out=$("$APP" --project "$linkdir/Linked.shotlist" --screen "$SCREEN" --place scenes \
          --link "Call Her Back" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  folder=$(echo "$out" | sed -n 's/^linked: .*folder "\(.*\)"$/\1/p')
  if echo "$out" | grep -q 'linked: "Call Her Back"' \
     && [ -n "$folder" ] && [ -d "$folder" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a film says which project it is, and finds its Drive folder"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a film says which project it is, and finds its Drive folder"
    echo "$out" | grep -E "^linked:" | sed 's/^/       /'
  fi

  # It is a fact about the project, not about this run of the app.
  out=$("$APP" --project "$linkdir/Linked.shotlist" --screen "$SCREEN" --place scenes --settings 2>&1)
  if echo "$out" | grep -q "FOCUS STOLEN"; then trips=$((trips+1)); fi
  out=$("$APP" --project "$linkdir/Linked.shotlist" --screen "$SCREEN" --place scenes \
          --link "Call Her Back" 2>&1)
  if echo "$out" | grep -q 'linked: "Call Her Back"'; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and it is still linked next time it opens"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and it is still linked next time it opens"
    echo "$out" | grep -E "^linked:" | sed 's/^/       /'
  fi

  # And unlinking really unlinks — a name that is not one of his takes the same
  # road the "Not linked" choice does.
  out=$("$APP" --project "$linkdir/Linked.shotlist" --screen "$SCREEN" --place scenes \
          --link "no such film" 2>&1)
  if echo "$out" | grep -q 'linked: ""'; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and it can be unlinked again"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and it can be unlinked again"
    echo "$out" | grep -E "^linked:" | sed 's/^/       /'
  fi
  rm -rf "$linkdir"
fi

fi
if slow "the console's doors"; then
echo "── the console's doors ──"
# **The Projects Console makes and describes films through these**, 2026-09-15,
# and never writes into a film itself (its rule 7). Each door is a checking run
# that says one line on stderr, so the console can read the answer back.
#
# Made in a folder of the run's own — `SHOTLISTER_FILMS` — never in his real
# films. The link half is skipped where the console has never run, for the
# same reason the section above is.
doors="$(mktemp -d)"
console="$HOME/Developer/.projects-console-state/projects-cache.json"
if [ -f "$console" ] && grep -q '"Call Her Back"' "$console"; then
  out=$(SHOTLISTER_FILMS="$doors" "$APP" --screen "$SCREEN" --newfilm "Door Check" --link "Call Her Back" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "^newfilm: \"Door Check\"  at \"$doors/Door Check.shotlist\"" \
     && echo "$out" | grep -q '^linked: "Call Her Back"  folder "/' \
     && [ -d "$doors/Door Check.shotlist" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a new film is made and linked in one run, and says where it is"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a new film is made and linked in one run, and says where it is"
    echo "$out" | grep -E "^newfilm:|^linked:" | sed 's/^/       /'
  fi
else
  out=$(SHOTLISTER_FILMS="$doors" "$APP" --screen "$SCREEN" --newfilm "Door Check" 2>&1)
  if echo "$out" | grep -q "^newfilm: \"Door Check\"  at \"$doors/Door Check.shotlist\"" \
     && [ -d "$doors/Door Check.shotlist" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a new film is made, and says where it is (the console knows no Call Her Back, so not linked)"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a new film is made, and says where it is"
    echo "$out" | grep -E "^newfilm:" | sed 's/^/       /'
  fi
fi

# **Refused, not renamed.** `freeName`'s "Door Check 2" is right for a hand
# on the New Project sheet and wrong for a program that asked for this title;
# the run says so and ends with status 1, and the disk is as it was.
out=$(SHOTLISTER_FILMS="$doors" "$APP" --screen "$SCREEN" --newfilm "door check" 2>&1); status=$?
if [ "$status" -eq 1 ] && echo "$out" | grep -q '^newfilm: refused — a film called "door check" already exists at ' \
   && [ "$(ls "$doors" | wc -l | tr -d ' ')" = 1 ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and a second film of the same name is refused, whatever its case"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and a second film of the same name is refused, whatever its case"
  echo "       status $status"; echo "$out" | grep -E "^newfilm:" | sed 's/^/       /'; ls "$doors" | sed 's/^/       /'
fi

# **The director, set and cleared through the engine**, and read back by a
# later run — a fact about the film, not about the run that wrote it.
"$APP" --project "$doors/Door Check.shotlist" --screen "$SCREEN" --place scenes \
       --setdirector "Clara Example" >/dev/null 2>&1
out=$("$APP" --project "$doors/Door Check.shotlist" --screen "$SCREEN" --place scenes --filmsays 2>&1)
if echo "$out" | grep -q '^film: title "Door Check"  director "Clara Example"  producer ""'; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a director set from the console is still there next time"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a director set from the console is still there next time"
  echo "$out" | grep -E "^film:" | sed 's/^/       /'
fi
out=$("$APP" --project "$doors/Door Check.shotlist" --screen "$SCREEN" --place scenes --setdirector none --filmsays 2>&1)
if echo "$out" | grep -q '^director: ""' && echo "$out" | grep -q '^film: title "Door Check"  director ""'; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and none clears it"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and none clears it"
  echo "$out" | grep -E "^director:|^film:" | sed 's/^/       /'
fi
rm -rf "$doors"

fi
if slow "the keyboard"; then
echo "── the keyboard ──"
# **His ask, 2026-08-22: ⌘1 · ⌘2 · ⌘3 for the three tabs.** The menu bar is
# invisible to everything else in this harness, so this reads the keys the menu
# actually claims and then sends one through it — a menu item that exists and
# does nothing looks identical to one that works.
out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --tab shots --menu 2>&1)
echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
# **The modes take ⌘, the views take ⌥⌘.** They were the other way round until
# 2026-08-23 and these two lines were not turned round with them, so both had
# been failing ever since — invisibly, because this section only runs under
# `--all`. Fixed 2026-09-02 along with the door in `reportMenu` that sent the
# wrong key.
if echo "$out" | grep -q "⌘1=Shot List" \
   && echo "$out" | grep -q "⌘⌥1=Table" \
   && echo "$out" | grep -q "⌘⌥2=Storyboard" \
   && echo "$out" | grep -q "⌘⌥3=Document"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "the modes and the views have their own keys"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "the modes and the views have their own keys"
  echo "$out" | grep -E "^menu keys" | sed 's/^/       /'
fi
# **The press is reported and not asserted, and that is deliberate.**
#
# There used to be a second check here — send ⌘2 and watch the tab move — and
# it had been failing since 2026-08-23 without anybody seeing it, because this
# section only runs under `--all`. Fixing the key it sends did not make it
# pass: a key equivalent is dispatched to the key window, and a checking run
# is **never frontmost and never key** on purpose. There is no posture in
# which this harness can press a menu item for real.
#
# So the line is still printed by `--menu` — it is worth reading when
# something is wrong — but nothing is asserted on it, rather than leaving a
# check that can only ever be red. Filed in Notion.
echo "$out" | grep -E "^menu press" | sed 's/^/       (not asserted) /' 

fi
if slow "storyboard arrows on a still"; then
echo "── storyboard arrows on a still ──"
# **Drawing one is a drag, and a synthetic mouse cannot drive a drag.** So the
# doors call the same road the hand takes — `ArrowBoard.save` — and the claims
# here are the stored values. What they cannot see is whether the mark lands in
# the right place on the photograph; that is a screenshot's job, and the
# screenshots are in the 2026-08-31 entry of `handoff/from-studio.md`.
qfresh "a picture starts with no arrows on it" "count=0" \
  --scene 34 --shot 34A --arrowssays
qfresh "a pan is two arrows across the frame" "count=2" \
  --scene 34 --shot 34A --arrows "Pan right" --arrowssays
qfresh "a push in is four arrows out of the corners" "count=4" \
  --scene 34 --shot 34A --arrows "Push in" --arrowssays
qfresh "a zoom in is one frame inside the frame, the picture's shape" "count=1  first=0.202,0.202-0.798,0.798 heads=0" \
  --scene 34 --shot 34A --arrows "Zoom in" --arrowssays
qfresh "a zoom out survives the stored line" "count=1  first=0.150,0.200-0.650,0.700 heads=0" \
  --scene 34 --shot 34A --arrowline "zoom:out,0.15,0.2,0.65,0.95,look:red" --arrowssays

# **A preset lands in the film's frame, not on the whole photograph** — his
# instruction, 2026-08-31. The proof needs a picture that is *not* the film's
# shape, so this makes a square one: in a 2.39 film the frame is the middle
# band of it, from 0.291 to 0.709, and a pan's top arrow sits a sixth of the
# way down **that band** — 0.358, not the 0.160 it would be if the frame were
# ignored. Nothing else in this file can tell those two apart.
square="$(mktemp -d)/Square.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$square"
python3 - /tmp/quick-square.png <<'PYEOF'
import sys, zlib, struct
w = h = 900
raw = b''.join(b'\x00' + bytes((180, 180, 180)) * w for _ in range(h))
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
PYEOF
out=$("$APP" --project "$square" --screen "$SCREEN" --place scenes --shot 35A \
      --frame /tmp/quick-square.png --arrows "Pan right" --arrowssays 2>&1)
if echo "$out" | grep -qF "count=2  first=0.180,0.358"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a preset lands in the film's frame, not on the photograph"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a preset lands in the film's frame, not on the photograph"
  echo "$out" | grep "arrows:" | sed 's/^/       /'
fi
rm -rf "$(dirname "$square")"
# **Adding does not replace.** A preset dropped onto a marked picture has to
# join what is there; this is the one that would silently eat his work.
qfresh "a second mark joins the first rather than replacing it" "count=3" \
  --scene 34 --shot 34A --arrows "Arrow" --arrows "Pan left" --arrowssays
qfresh "clearing leaves the picture bare" "count=0" \
  --scene 34 --shot 34A --arrows "Arrow" --arrows clear --arrowssays

# **The two width handles** (2026-10-15): a head handle that sets the triangle's
# base and a shaft handle that sets the rectangle behind it. A synthetic mouse
# cannot drag, so the drag arithmetic is run directly: the pointer is put 30 pt
# out from where each handle sits and the widths read back. Untouched arrows
# have two handles; no-head ones have one.
qfresh "an untouched arrow has two width handles" "handles=2" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,1;1;0;0"
qfresh "dragging the head handle out widens only the head" "widths=0.0" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,1;1;30;0"
qfresh "dragging the shaft handle in cannot go below the floor" "handles=2" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,1;0;-500;0"
qfresh "a no-head arrow has only the shaft handle" "handles=1" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,0;0;0;0"
# **Solid Toward / Away arrows** (2026-10-15): the handles sit on the drawn
# corners in perspective, and dragging the head's out widens only the head.
qfresh "a solid Toward arrow has two width handles" "handles=2" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.1,0.5,0.5,0.5,0.9,1,depth:toward;1;0;0"
qfresh "dragging a solid arrow's head handle out widens its head" "drawn=" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,1,depth:away,stance:standing;1;40;0"
# **The back can be wider than the front** (2026-10-15): the shaft handle can be
# dragged out past the head's width, on Away, Toward and Flat arrows.
qfresh "an Away arrow's tail can be dragged wider than its head" "wide=1" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,1,depth:away;0;200;0"
qfresh "a Toward arrow's shaft can be dragged wider than its head" "wide=1" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.1,0.5,0.5,0.5,0.9,1,depth:toward,stance:standing;0;300;0"
qfresh "a Flat arrow's shaft can be dragged wider than its head" "wide=1" \
  --scene 34 --shot 34A --arrowdrag "0.5,0.9,0.5,0.5,0.5,0.1,1;0;200;0"

# **An arrow's thickness stays** (2026-10-15: "the thickness slider on arrows
# doesn't stay — it always resets to its default"). Every button on the bar,
# a save and a reopen (a second launch on the same copy) must leave it alone;
# the slider's release must save what it was moved to even when no redraw came
# between (a click in the track); and a new arrow starts at the last one
# picked. A synthetic mouse cannot drag the slider, so the draft it saves
# through is run directly (`--arrowslide`).
tk="$(mktemp -d)/Thick.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$tk"
tline="0.5,0.9,0.5,0.5,0.5,0.1,1,thick:2.30"
tok() {  # name, wanted text, then flags for one launch on the shared copy
  local name="$1" want="$2"; shift 2
  local out; out=$("$APP" --project "$tk" --screen "$SCREEN" --place scenes --scene 34 --shot 34A "$@" 2>&1)
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "^arrow" | sed 's/^/       /'
  fi
}
tok "an arrow drawn thick is saved thick" "thick=2.30" --arrowline "$tline" --arrowssays
tok "…and is still thick when the project is reopened" "thick=2.30" --arrowssays
for edit in straighten resetwidths toward away flat standing floor dashed heads2 red corner pin movehead movewhole \
            "widths,resetwidths" "toward,standing,resetwidths,pin,movehead,red,flat"; do
  tok "thickness survives: $edit" "arrowedit: before=2.30 after=2.30" --arrowedit "$tline;$edit"
  tok "…saved, and reopened: $edit" "thick=2.30" --arrowssays
done
tok "a click in the Thickness track saves what it was moved to" "arrowslide: saved=2.40" \
  --arrowremember reset --arrowslide "0.5,0.9,0.5,0.5,0.5,0.1,1;2.4;0" --arrowssays
tok "…and the arrow is that thick after reopening" "thick=2.40" --arrowssays
tok "…and a new arrow starts at the last thickness picked, on the next launch" "arrowremember: next=2.40 mark=2.40" --arrowremember
tok "a slider that was redrawn before release saves the same" "arrowslide: saved=1.70" \
  --arrowslide "0.5,0.9,0.5,0.5,0.5,0.1,1;1.7;1" --arrowssays
rm -rf "$(dirname "$tk")"
# The real Slider, pressed and let go in a window of its own: the way the bar
# saves (through the shared draft) keeps what it was moved to, click or drag.
slk="$(mktemp -d)"
cp studio/checks-extra/slider-release.swift "$slk/main.swift"
if swiftc "$slk/main.swift" -o "$slk/run" >/dev/null 2>&1; then
  sout=$("$slk/run" 2>&1)
  for how in click "drag "; do
    if echo "$sout" | grep -qF "slider draft $how saved the new value"; then
      pass=$((pass+1)); printf '  ✓  %s\n' "a real slider let go after a ${how% } saves where it was moved"
    else
      fail=$((fail+1)); printf '  ✗  %s\n' "a real slider let go after a ${how% } saves where it was moved"
      echo "$sout" | sed 's/^/       /'
    fi
  done
else
  fail=$((fail+1)); printf '  ✗  %s\n' "the slider check compiles"
fi
rm -rf "$slk"
fi

if slow "a clip that plays"; then
echo "── a clip that plays ──"
# **A screenshot cannot tell a playing clip from a still of its first frame**,
# so this reads the playhead instead: a playhead that has moved can only have
# moved by playing. `--playing` lets a checking run animate, which is otherwise
# off — a photograph of a moving thing is a photograph of whichever frame the
# decoder reached, and a check that cannot repeat itself is worse than none.
if command -v ffmpeg >/dev/null 2>&1; then
  moving="$(mktemp -d)"
  ffmpeg -y -f lavfi -i "testsrc=size=640x360:rate=12:duration=3" \
         -pix_fmt yuv420p -c:v libx264 "$moving/clip.mp4" >/dev/null 2>&1
  cp -R studio/fixtures/Daybreak.shotlist "$moving/Clip.shotlist"
  "$APP" --project "$moving/Clip.shotlist" --screen "$SCREEN" --place scenes \
         --shot 34A --frame "$moving/clip.mp4" >/dev/null 2>&1
  out=$("$APP" --project "$moving/Clip.shotlist" --screen "$SCREEN" --place scenes \
          --scene 34 --playing --after 1.6 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "^clip: rate 1.0" \
     && ! echo "$out" | grep -q "playhead 0.00"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a clip on a shot plays itself in the table"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a clip on a shot plays itself in the table"
    echo "$out" | grep -E "^clip:" | sed 's/^/       /'
  fi
  # **…and waits when he says so** (2026-09-30): with Play Clips Automatically
  # off, a clip draws its still and a play button, and no player is ever made —
  # so no `clip:` line at all, even with motion allowed.
  out=$("$APP" --project "$moving/Clip.shotlist" --screen "$SCREEN" --place scenes \
          --scene 34 --playing --clipswait --after 1.6 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if ! echo "$out" | grep -q "^clip:"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and waits for play when clips don't play on their own"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and waits for play when clips don't play on their own"
    echo "$out" | grep -E "^clip:" | sed 's/^/       /'
  fi
  rm -rf "$moving"
fi

fi
if slow "a script comes in"; then
echo "── a script comes in ──"
# **The whole import, end to end, on a screenplay laid out like a screenplay.**
# The fixture is written by `studio/fixtures/screenplay.py` rather than checked
# in as a PDF, because the engine decides what a line *is* from where it sits on
# the page — a fixture is only a fixture if its geometry is a real script's.
script="$(mktemp -d)"
python3 studio/fixtures/screenplay.py "$script/script.pdf" 2>/dev/null
if [ -f "$script/script.pdf" ]; then
  taking="$script/Taking.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$taking"

  # The demo has 33, 34, 35 and 54. The draft has 33, 34, 35 and 36, with a bare
  # room name under 34 that the rules find and leave unticked.
  out=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes \
          --script "$script/script.pdf" --scriptdo confirm 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "detected 5  matched 3  new 1  omitted 1"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a PDF is read, and the numbers are the script's"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a PDF is read, and the numbers are the script's"
    echo "$out" | grep -E "^script" | sed 's/^/       /'
  fi

  # **The report and the import have to agree.** They did not on 2026-08-22:
  # the sheet said three scenes matched and the import linked two and archived
  # one that was still in the draft, because the two readings were made under
  # different rules and the indices meant different scenes. This is that, in one
  # line, for ever.
  if echo "$out" | grep -q "linked 3  created 1  archived 1"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and what it promises is what the reading found"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and what it promises is what the reading found"
    echo "$out" | grep -E "^script plan" | sed 's/^/       /'
  fi

  # **Name merging changes the list on screen, not just the import.** The
  # control could not exist until `readscript` took the cast options: a merging
  # setting that changed what landed while the list went on describing
  # something else is the same lie as the indices bug above. The draft has one
  # cue wearing a (V.O.), so None finds one more person than Regular.
  loose=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes \
            --script "$script/script.pdf" --scriptmerge none 2>&1 \
          | grep -o "cast [0-9]*/[0-9]*")
  tight=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes \
            --script "$script/script.pdf" --scriptmerge regular 2>&1 \
          | grep -o "cast [0-9]*/[0-9]*")
  if [ "$loose" = "cast 4/4" ] && [ "$tight" = "cast 3/3" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "merging names folds the list you are looking at"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "merging names folds the list you are looking at"
    printf '       none: %s   regular: %s\n' "$loose" "$tight"
  fi

  # **A draft nobody numbered still comes in.** Most of the scripts he is handed
  # have no scene numbers on them, and until 2026-08-22 every one of them
  # imported as nothing: the first heading became a scene with no number and
  # every heading after it became a room, and the import skips a scene with no
  # number. Numbered by position now — which is what an AD writes on an
  # unnumbered draft before anybody can talk about it.
  # ---- a scene that moved to a new number — Ref 241 -------------------------
  #
  # The import compares by number, so a scene printed at 60 that used to be 54
  # reads as one scene gone and one scene new — and eight shots are stranded on
  # a scene nobody looks at again. The pairing has to be **found and offered**,
  # never taken: this checks it is found, and that nothing has happened to the
  # project because of it.
  python3 studio/fixtures/screenplay.py "$script/moved.pdf" --renumbered 2>/dev/null
  cp -R studio/fixtures/Daybreak.shotlist "$script/Moved.shotlist"
  "$APP" --project "$script/Moved.shotlist" --screen "$SCREEN" --place scenes --scene 54 \
    --scenefield script "Milo and Felix walk in through the crowd. BRUNO is in the ring. Somebody is already bleeding." \
    >/dev/null 2>&1
  out=$("$APP" --project "$script/Moved.shotlist" --screen "$SCREEN" --place scenes \
          --script "$script/moved.pdf" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "moved 54→60"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a scene printed at a new number is spotted"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a scene printed at a new number is spotted"
    echo "$out" | grep -E "^script:" | sed 's/^/       /'
  fi
  # **Found is not taken.** Reading a draft must leave the project exactly as it
  # was, and this is the one that would hurt: 54 renumbering itself because a
  # reading noticed something.
  out=$("$APP" --project "$script/Moved.shotlist" --screen "$SCREEN" --place scenes --scenes 2>&1)
  if echo "$out" | grep -q "scenes: 4"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and reading it moved nothing"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and reading it moved nothing"
    echo "$out" | grep -E "^project:" | sed 's/^/       /'
  fi

  python3 studio/fixtures/screenplay.py "$script/plain.pdf" --unnumbered 2>/dev/null
  cp -R studio/fixtures/Daybreak.shotlist "$script/Plain.shotlist"
  out=$("$APP" --project "$script/Plain.shotlist" --screen "$SCREEN" --place scenes \
          --script "$script/plain.pdf" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "ticked 0:1,1:2,3:3,4:4"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a draft with no scene numbers is numbered in order"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a draft with no scene numbers is numbered in order"
    echo "$out" | grep -E "^script:" | sed 's/^/       /'
  fi

  # **And the scenes land where their numbers say.** Taking 1-4 into a project
  # holding 33, 34, 35 and 54 used to append them, so the film read 33, 34, 35,
  # 54, 1, 2, 3, 4 — his report the same day.
  "$APP" --project "$script/Plain.shotlist" --screen "$SCREEN" --place scenes \
         --script "$script/plain.pdf" --scriptdo take >/dev/null 2>&1
  out=$("$APP" --project "$script/Plain.shotlist" --screen "$SCREEN" --place scenes --locations 2>&1)
  if echo "$out" | grep -q "1=COUNTY JAIL/none | 2=CAR PARK/none | 3=PHARMACY/none | 4=HIGHWAY/none | 33="; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and they sort into the film by number"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and they sort into the film by number"
    echo "$out" | grep -E "^scene locations" | sed 's/^/       /'
  fi

  # Weighing is a rehearsal: it must not have written anything.
  before=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes --revisions 2>&1 \
           | grep -c "revisions: 0")
  if [ "$before" -eq 1 ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and reading it changed nothing"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and reading it changed nothing"
  fi

  # **Five, not four:** the pages lay out every scene the draft prints, and the
  # draft prints the bare room under 34 as 34A, which the import leaves unticked
  # (see "detected 5" above). The check said 4 until 2026-10-06, when it was
  # found failing: `scriptpages` reads with the project's own rules, as the
  # import does, so it counts 34A; the build from before that day's commits
  # says 5 too, and this section runs only under --all, so nobody saw it.
  out=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes \
          --script "$script/script.pdf" --scriptdo take --revisions 2>&1)
  if echo "$out" | grep -q "revisions: 1" \
     && echo "$out" | grep -q "script pages: 1  scenes 5  \[33=1/8 34=1/8 34A=1/8 35=1/8 36=1/8\]"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "taking it keeps the draft and lays it out"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "taking it keeps the draft and lays it out"
    echo "$out" | grep -E "^script|^revisions" | sed 's/^/       /'
  fi

  # **The revision keeps the file it came from**, so the script can be read as
  # printed rather than as we draw it. His call: the button opens the real PDF
  # in Preview. A draft taken in before this still opens our own window, so the
  # button is never dead — that is the fallback, not the plan.
  out=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes --scene 33 \
          --wholescript 2>&1)
  if echo "$out" | grep -q "^script file:" && ! echo "$out" | grep -q "^script window:"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "the script opens as the file it came from"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "the script opens as the file it came from"
    echo "$out" | grep -E "^script (file|window)" | sed 's/^/       /'
  fi

  # **And the button is never dead.** A project with no script at all — or a
  # draft taken in before revisions kept their pages — has no file to open, and
  # falls back to our own drawing of it rather than doing nothing.
  spare="$script/Nothing.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$spare"
  out=$("$APP" --project "$spare" --screen "$SCREEN" --place scenes --scene 33 \
          --wholescript 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "^script window:"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "…and with no file kept, our own reader opens instead"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "…and with no file kept, our own reader opens instead"
    echo "$out" | grep -E "^script (file|window)" | sed 's/^/       /'
  fi

  # **Shots hold lines of the screenplay, and the reader shows them** (Ref
  # 1568). A shot tied to one action line in the draft's text is marked in the
  # Whole Script window: its number and its stretch, in a line.
  "$APP" --project "$taking" --screen "$SCREEN" --place scenes --scene 34 \
         --tielines 34A 163 211 >/dev/null 2>&1
  out=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes --scene 34 \
          --wholescriptwindow 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "^script window:.* marks 34A=163-210"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "the reading window marks the lines a shot holds"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "the reading window marks the lines a shot holds"
    echo "$out" | grep -E "^script window" | sed 's/^/       /'
  fi

  # And the scene the draft dropped is archived, not deleted — the law.
  out=$("$APP" --project "$taking" --screen "$SCREEN" --place scenes --scene 33 \
          --panel script --locations 2>&1)
  if echo "$out" | grep -q "script panel: scene 33  script true  lines 9"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "the panel draws the scene you are standing on"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "the panel draws the scene you are standing on"
    echo "$out" | grep -E "^script panel" | sed 's/^/       /'
  fi
fi
rm -rf "$script"

# ---- a disagreement answered stays answered -------------------------------
#
# **His report, 2026-08-21:** the same sync notice every single launch, however
# often he clicked it away. A clash is worked out from the log each time it is
# asked for, so the banner's OK — which emptied a Swift array and told the
# engine nothing — could never end one. Nothing in the app could.
#
# The check has to span *two launches*, because one launch always looked right.
fi
if slow "a disagreement answered stays answered"; then
echo "── a disagreement answered stays answered ──"
# Out of range of each other, the full battery's way: each machine writes into
# its own copy, and only afterwards does one hand the other its log. Two
# launches against one folder cannot do it — the second opens, merges the
# first's work, and has therefore seen it.
CA="$(mktemp -d)/A.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$CA"
"$APP" --project "$CA" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --set lens "40mm" >/dev/null 2>&1
CB="$(mktemp -d)/B.shotlist"
cp -R "$CA" "$CB"
"$APP" --project "$CB" --screen "$SCREEN" --device 8002 --scene 34 --cell lens --set lens "85mm" >/dev/null 2>&1
"$APP" --project "$CA" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --set lens "27mm" >/dev/null 2>&1
cp "$CB"/changes/*1f42*.log "$CA/changes/" 2>/dev/null

ask() { "$APP" --project "$CA" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --type "" 2>&1; }

if ask | grep -q "clashes standing: 1"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a field decided twice is said at open"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a field decided twice is said at open"
  ask | grep -E "clashes standing" | sed 's/^/       /'
fi

"$APP" --project "$CA" --screen "$SCREEN" --device 8001 --scene 34 --settle >/dev/null 2>&1

# The whole of his complaint is here: not that it goes, but that it stays gone.
if ask | grep -q "clashes standing: 0" && ask | grep -q "clashes standing: 0"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and answered, it stays answered across relaunches"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and answered, it stays answered across relaunches"
  ask | grep -E "clashes standing" | sed 's/^/       /'
fi

# Answering keeps what is on screen. It records a decision; it changes nothing.
if ask | grep -q 'engine holds "27mm"'; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and it kept the value that was on screen"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and it kept the value that was on screen"
  ask | grep -E "engine holds" | sed 's/^/       /'
fi
rm -rf "$(dirname "$CA")" "$(dirname "$CB")"

# ---- rooms inside a location — Ref 269 -------------------------------------
#
# One house, one address, and a kitchen and a garage inside it. Three facts
# worth a check: the room borrows, the house counts what is under its roof, and
# the engine refuses to nest deeper than one.

RM="$(mktemp -d)/Rooms.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$RM"
"$APP" --project "$RM" --screen "$SCREEN" --place locations \
  --addlocation "Hillcrest House" --setlocation address "2140 Hillcrest Rd" >/dev/null 2>&1
"$APP" --project "$RM" --screen "$SCREEN" --place locations --addarea "Hillcrest House" "Kitchen" >/dev/null 2>&1
"$APP" --project "$RM" --screen "$SCREEN" --place locations --addarea "Hillcrest House" "Garage" >/dev/null 2>&1
"$APP" --project "$RM" --screen "$SCREEN" --place locations --location "Kitchen" --linkscene 33 >/dev/null 2>&1
"$APP" --project "$RM" --screen "$SCREEN" --place locations --location "Garage" --linkscene 34 >/dev/null 2>&1

rooms() { "$APP" --project "$RM" --screen "$SCREEN" --place locations --locations 2>&1; }

r() {
  local name="$1"; local want="$2"
  if rooms | grep -qE "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    rooms | grep -E "^locations:|^scene locations:" | sed 's/^/       /'
  fi
}

r "a room borrows the house's address" "Hillcrest House — Kitchen; \(from house\) 2140 Hillcrest Rd"
r "the house counts the scenes in its rooms" "Hillcrest House; 2140 Hillcrest Rd;[^|]*2 inside"
r "a scene names the room and the house it is in" "33=COUNTY JAIL/Hillcrest House — Kitchen"

# **One level, always.** Filing the house inside its own kitchen has to be
# refused rather than obeyed — the failure this guards is a silent grandchild
# nobody can find in the list.
"$APP" --project "$RM" --screen "$SCREEN" --place locations \
  --movelocation "Hillcrest House" "Kitchen" >/dev/null 2>&1
r "…and a house cannot be filed inside its own room" "Hillcrest House; 2140 Hillcrest Rd"

# Letting a room out keeps everything of its own and drops the borrowed address.
"$APP" --project "$RM" --screen "$SCREEN" --place locations --movelocation "Kitchen" "" >/dev/null 2>&1
r "letting a room out keeps its scene and stops borrowing" "\| Kitchen; ; no pin; 1 scenes"

# ---- a photograph on a location is named after it — Ref 273 -----------------
#
# His ruling, 2026-08-22: a photograph on a **location** is renamed after the
# location and its area; everywhere else a file keeps the name it came with.
# This is the one place in the app a file is renamed against its will, so it is
# worth a check that it happens *there* and only there.

python3 - "$RM" <<'PYEOF' 2>/dev/null
import sys, struct, zlib, os
# A tiny PNG written by hand — no Pillow on a machine that has not been set up.
def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))
    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(raw))
    out += chunk(b"IEND", b"")
    open(path, "wb").write(out)
here = os.path.dirname(sys.argv[1])
png(os.path.join(here, "IMG_4471.png"), 40, 30, (90, 120, 150))
png(os.path.join(here, "DSC_0099.png"), 40, 30, (150, 90, 120))
PYEOF
shots="$(dirname "$RM")"
if [ -f "$shots/IMG_4471.png" ]; then
  "$APP" --project "$RM" --screen "$SCREEN" --place locations --location "Garage" \
    --pinhere "$shots/IMG_4471.png" >/dev/null 2>&1
  "$APP" --project "$RM" --screen "$SCREEN" --place locations --location "Garage" \
    --pinhere "$shots/DSC_0099.png" >/dev/null 2>&1
  out=$("$APP" --project "$RM" --screen "$SCREEN" --place locations --location "Garage" \
          --locations 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "photo names: hillcrest-house-garage-01.png, hillcrest-house-garage-02.png"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a photograph on a room is named after the house and the room"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a photograph on a room is named after the house and the room"
    echo "$out" | grep -E "^photo names:" | sed 's/^/       /'
  fi
fi

# ---- several scenes at once — Ref 240 ---------------------------------------
#
# `pickedScenes` is deliberately not `sceneId`: standing on a scene and having
# several picked are different facts, and every other screen reads the first.

PS="$(mktemp -d)/Picked.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$PS"
"$APP" --project "$PS" --screen "$SCREEN" --place locations --addlocation "Hillcrest House" >/dev/null 2>&1
"$APP" --project "$PS" --screen "$SCREEN" --place locations --addarea "Hillcrest House" "Kitchen" >/dev/null 2>&1

p() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$PS" --screen "$SCREEN" --place scenes "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qE "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "standing on|scene locations" | sed 's/^/       /'
  fi
}

p "several scenes can be picked at once" "picked scenes: 33,35" --pickscenes 33,35
# One is not a selection — it is where you are standing, and every other screen
# reads that. Getting this wrong would leave a stale set behind every click.
p "…and picking one moves the cursor instead" "standing on: 34  picked scenes: $" --pickscenes 34
p "a location can be set on all of them at once" \
  "33=COUNTY JAIL/Hillcrest House — Kitchen \| 34=CAR/Hillcrest House — Kitchen" \
  --pickscenes 33,34 --pickedlocation "Kitchen" --locations
# His ask, 2026-09-02: right-click several scenes and set the time of day on
# all of them. The dot the sidebar draws is a colour and a photograph of four
# coloured dots proves nothing, so the words are what is asserted.
p "a time of day can be set on all of them at once" \
  "scene times: 33=SUNSET \| 34=SUNSET \| 35=DAY" \
  --pickscenes 33,34 --pickedtime SUNSET --scenetimes
p "…and the scenes nobody picked are untouched" \
  "scene times: 33=SUNSET \| 34=SUNSET \| 35=DAY \| 54=NIGHT" --scenetimes
p "…and None clears it" \
  "scene times: 33=— \| 34=—" --pickscenes 33,34 --pickedtime "" --scenetimes
rm -rf "$(dirname "$PS")"
rm -rf "$(dirname "$RM")"

fi
if slow "the document page by keys"; then
echo "── the document page by keys ──"
# His ask, 2026-09-30: add shots and fill them in without touching the mouse.
# `--pagekeys` drives the page one key at a time and reports after each. Its
# own copy of the film, so what the rest of this run did cannot move the letters.
pk() {
  local name="$1"; local want="$2"; shift 2
  local film; film="$(mktemp -d)/Keys.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$film"
  local out; out=$("$APP" --project "$film" --screen "$SCREEN" --place scenes --tab document "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qE "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "pagekeys|^  3" | sed 's/^/       /'
  fi
}
pk "⌘↩ mid-sentence starts the next shot, caret in its words" \
  '34B: "Beta"' --shot 34A --pagekeys "⇥; ⇥; type  more; ⌘↩; type Beta; ⎋; rows"
pk "…and the words typed before it stay on their own shot" \
  '34A: ".* more"' --shot 34A --pagekeys "⇥; ⇥; type  more; ⌘↩; type Beta; ⎋; rows"
pk "Escape picks the whole shot, arrows walk, ⇧ reaches" \
  '\[⇧↓\] cursor=34C .*marked=\[34B,34C\]' --shot 34A --pagekeys "⇥; ⇥; ⎋; ↓; ⇧↓"
pk "…and Escape lets go" \
  '\[⎋\] cursor=34B .*marked=\[\] ' --shot 34A --pagekeys "⇥; ⇥; ⎋; ↓; ⎋"
# His trackpad over an open list moved the page instead (2026-09-30). A swipe
# through the app's queue must move the list (208 tall) and leave the page
# where it was. The page's own offset is this run's; the list's must leave 0.
pk "a swipe over an open list scrolls the list, not the page" \
  '\[swipe [^]]*\].*scrolls=804h@0 812h@409 208h@[1-9]' \
  --scene 34 --shot 34A --pagekeys "⇥; ⇥; ⇥; swipe 860 400 -20 6"
fi

if slow "how the document page is set"; then
echo "── how the document page is set ──"
# **The page's type used to live twice** — Swift constants in Document.swift
# and Rust constants in the export's stylesheet, each with a note saying "if
# one moves, the other moves" and nothing enforcing it. It lives in the engine
# now, so these prove the app reads what the engine says.
qfresh_style() {
  local name="$1"; local want="$2"; shift 2
  local fresh; fresh="$(mktemp -d)/Type.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes --tab document \
                   "$@" --docstylesays 2>&1)
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "^doc style:" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}
qfresh_style "an untouched page is the one it has always been" \
  "body=105/serif/as" --stay 3
qfresh_style "a size, a face and a case land on the page" \
  "credits=90/sans/lower" --docstyle "credits:9:sans:lower" --stay 3
# **A case cannot be forced on words he types.** A page that shouts back a
# sentence he wrote is a page disagreeing with the file it came from, and the
# moment he edits that line he is looking at letters he never typed.
qfresh_style "…but not on the words he types himself" \
  "body=140/sans/as" --docstyle "body:14:sans:upper" --stay 3
qfresh_style "and reset puts the whole page back" \
  "body=105/serif/as" --docstyle "reset" --stay 3
# **An ink per class** — his ask, 2026-09-03. The colours the page has always
# been drawn in are the standard, so an untouched page still says them.
qfresh_style "every class says what it is drawn in" \
  "body=105/serif/as/17171a" --stay 3
qfresh_style "a quiet class is quiet by default, not black" \
  "notes=115/serif/as/5c5c63" --stay 3
qfresh_style "and an ink he picks lands on the page" \
  "notes=115/serif/as/b3261e" --docstyle "notes:11.5:serif:as:b3261e" --stay 3

# **The size he sets reaches the words already written.** His report,
# 2026-09-03: *"the body didn't seem to change size with my adjustments."*
#
# The words of a shot are stored as RTF carrying their own point size, so the
# class landing on the *page* and the class landing on the *words* are two
# different things — and only the second was ever broken. A run may be
# overwritten only when the page itself handed out its size; 10.5 had to join
# that list, being the page's body from August until the day it became his to
# set, which is every sentence in both his real films.
#
# Two runs, on purpose. One at the page's own size, which must follow. One at a
# size nothing ever handed out — the shape of a run he sized himself — which
# must not, or the ⌃ and ⌄ buttons in the bar are a lie.
qrich() {
  local name="$1"; local want="$2"; local half="$3"
  local words="One sentence, whose size the page decides."
  local fresh; fresh="$(mktemp -d)/Rich.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  # The words, and then the same words as stored formatting. `\fsN` is in half
  # points, so 21 is 10.5 — and the two have to say the same thing or the
  # formatted copy is not trusted at all, which is its own old rule.
  local rtf; rtf=$(printf '{\\rtf1\\ansi\\ansicpg1252{\\fonttbl\\f0\\froman\\fcharset0 Times-Roman;}\n\\f0\\fs%s \\cf0 %s}' \
                   "$half" "$words" | base64 | tr -d '\n')
  "$APP" --project "$fresh" --screen "$SCREEN" --place scenes --scene 33 --shot 33A \
    --cell description --paste "$words" >/dev/null 2>&1
  "$APP" --project "$fresh" --screen "$SCREEN" --place scenes --scene 33 --shot 33A \
    --set description_rich "$rtf" >/dev/null 2>&1
  "$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
    --docstyle "body:20:serif:as" >/dev/null 2>&1
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
                   --scene 33 --shot 33A --richsays 2>&1)
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | grep -E "rich sizes:" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}
qrich "a class size reaches words already written" "rich sizes: 20.0" 21
qrich "…and leaves alone the ones he sized himself" "rich sizes: 12.0" 24

# **The page every film starts from.** His ask, 2026-09-04: *"the formatting
# settings I've set right now … to be the default from here on out for all
# projects. also allow me to set new defaults per project."* Two levels, and
# the film always wins — so both halves are checked, because a default that
# overwrote a film he had set would be worse than no default at all.
qfresh_style "a film nobody has set takes the default" \
  "body=140/sans/as/1f4e9c" --pagedefault "body=14/sans/as/1f4e9c" --stay 3
qdefault_keeps() {
  local fresh; fresh="$(mktemp -d)/Own.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  "$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
    --docstyle "body:9:mono:as" >/dev/null 2>&1
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
                   --pagedefault "body=14/sans/as/1f4e9c" --docstylesays 2>&1)
  if echo "$out" | grep -qF "body=90/mono/as"; then
    pass=$((pass+1)); printf '  ✓  …and a film he has set keeps its own\n'
  else
    fail=$((fail+1)); printf '  ✗  …and a film he has set keeps its own\n'
    echo "$out" | grep -E "^doc style:" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}
qdefault_keeps
qfresh_style "keeping this page as the default says so" \
  "page default: body=14/sans/as/17171a" \
  --docstyle "body:14:sans:as" --pagedefault save --pagedefaultsays --stay 3

# **What a single change costs.** His report, 2026-09-04: *"it's feeling
# sluggish."* Nothing could see it — every check draws the screen once, and
# once is cheap however much of the film it drew. The document builds the
# whole film on purpose, so the page breaks fall where they really fall; what
# was wrong is that it built it **again** whenever anything anywhere changed.
# Measured on his own film: 56 shots rebuilt per pass, 73ms a change, against
# 38ms for the table beside it.
#
# Zero is the assertion. A shot rebuilds when something about *it* changes and
# not otherwise, and the day that stops being true this line goes red.
qfresh_style "a change does not redraw the whole film" \
  "built: 0 rows 0 paragraphs" --redraws 4

# **A storyboard card shows the frames, not a number saying there are some.**
# His ask, 2026-09-04. The card drew the key frame alone with a small count in
# the corner; it lays them side by side now, up to four, and says `+n` for any
# it could not fit. Four is where a frame stops being a picture and becomes a
# sliver — that is the number this pins.
#
# The drawing is pixels and no battery can see those, so the card and the door
# ask the same function.
qboard() {
  local fresh; fresh="$(mktemp -d)/Board.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local pics; pics="$(mktemp -d)"
  local n=0
  for src in studio/fixtures/Daybreak.shotlist/media/proxies/*.png; do
    n=$((n+1)); [ "$n" -gt 5 ] && break
    cp "$src" "$pics/$n.png"
    "$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
      --scene 33 --shot 33A --frame "$pics/$n.png" >/dev/null 2>&1
  done
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
                   --scene 33 --tab storyboard --boardframes 2>&1)
  if echo "$out" | grep -qF "33A=4+"; then
    pass=$((pass+1)); printf '  ✓  a card shows every frame it can fit, and says what it cannot\n'
  else
    fail=$((fail+1)); printf '  ✗  a card shows every frame it can fit, and says what it cannot\n'
    echo "$out" | grep -E "board frames:" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")" "$pics"
}
qboard
qfresh_style "one frame is still one frame" "board frames: 33A=1" \
  --scene 33 --tab storyboard --boardframes --stay 3

fi
if slow "the export, which nothing has ever checked"; then
echo "── the export, which nothing has ever checked ──"
# **The first checks the export has ever had.** The doors (--exportpdf,
# --exportdays, --framesize, --colwidths) were built and never wired into
# either battery: `git log -S "--exportpdf"` on this file and checks.sh
# returned nothing. So every export change ever made was checked by hand.
#
# `--stay` on each, because a render is a WKWebView load plus a fixed 0.4s
# settle per view, and the ordinary exit timer kills the process before the
# completion prints. A missing line is not a failed export.
EX="$(mktemp -d)"
# **13 listed (15 before Filters and Modifiers left the list, 2026-10-15), 11 ticked, and the four unticked are named.** Fourteen when
# written (2026-09-02); the Script column joined the order on 2026-09-19 and is
# listed on every project, ticked only on a commercial with a script, so a film
# lists 15 and ticks 11 (not Camera, Sequence, Struck, Script). The Daybreak
# fixture holds no column of its own. It read 14 and went on failing unseen
# because this section is held back; it was not today's Ref 1555 (the build
# before that commit lists 15 too).
q "the box opens holding the film's columns" \
  "export box: columns 15 ticked 11 " --exportbox --stay 4 --window export --snapshot /dev/null
# Ref: the Columns list was empty for months. Every column carries a label
# since Ref 249, and the box filtered custom ones out with `label == nil`, so
# it matched nothing at all. `ticked 0` here means that regression is back.
q "two views make one stamped file" \
  "exported: yes pages: [0-9]+" --exportpdf "$EX/two.pdf" table,storyboard --stay 10
# **The bug per-view paper exists to fix.** One orientation used to be forced
# on the whole export, so a film exported as Table *and* Document had the
# document pages come out sideways. Landscape then portrait, in one file.
q "the document page prints portrait inside a landscape export" \
  "page shapes: landscape.*portrait" --exportpdf "$EX/mix.pdf" table,document --stay 10
q "…and the paper can still be overridden per view" \
  "page shapes: (landscape )+landscape$" \
  --exportpdf "$EX/flat.pdf" table,document --paper document:landscape --stay 10
q "a narrowed column set reaches the page" \
  "exported: yes pages: [0-9]+" \
  --exportpdf "$EX/thin.pdf" table --exportcolumns description,notes --stay 10
# **Flat or editable** — his ask, 2026-09-16. A flat file is the same pages
# baked into pictures, so the one thing it must not carry is a word of text;
# an editable one must still carry all of them.
q "an editable export still carries its words" \
  "text: [1-9][0-9]* chars" --exportpdf "$EX/words.pdf" table --stay 10
q "a flat export carries none" \
  "text: 0 chars" --exportpdf "$EX/baked.pdf" table --flat --stay 10
# **The document page is never scaled from the exporter.** His report,
# 2026-09-03: *"a discrepancy between the layout in the editor and the preview
# of what the first page will look like."* The text-size dial was taken out of
# the box's Document pane on 2026-09-02 because the page sets its own type now
# — and the *stored* value went on being applied, so his own film exported at
# the 50% he had left there, half the size the document view drew, with nothing
# on screen saying why. The same page count at any dial is the assertion.
# **Five now, and the fifth is the section heads.** Daybreak has three sections
# (Jail Release, The Drive, The Fight) and since 2026-09-19 each opens a chapter
# head on the page (a8e95bb1), which pushes the last shots onto a fifth page.
# Four was true before that. The second check takes the three sections out of a
# copy and wants four again, so the number is pinned to its cause, and a
# change that adds a page for any other reason fails one of the two.
qfresh "the document ignores the exporter's text dial" \
  "exported: yes pages: 5" --exportpdf "$EX/half.pdf" document --textsize 0.5 --stay 10
nosec="$(mktemp -d)/NoSections.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$nosec"
for sec in "Jail Release" "The Drive" "The Fight"; do
  "$APP" --project "$nosec" --screen "$SCREEN" --place scenes --deletesection "$sec" --stay 3 >/dev/null 2>&1
done
out=$("$APP" --project "$nosec" --screen "$SCREEN" --place scenes \
  --exportpdf "$EX/nosec.pdf" document --textsize 0.5 --stay 10 2>&1)
if echo "$out" | grep -qF "exported: yes pages: 4"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and without its three sections the same film is four"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "…and without its three sections the same film is four"
  echo "$out" | grep -E "exported|sections:" | sed 's/^/       /'
fi
rm -rf "$(dirname "$nosec")"
q "…and the table still obeys it" \
  "exported: yes pages: 2" --exportpdf "$EX/halft.pdf" table --textsize 0.5 --stay 10
# **It forgets nothing now.** Every dial was a plain @State with a fixed
# default, so the same day-package export was re-specified from scratch every
# time — the single biggest reason he called the box clunky. Set a look on one
# launch, and assert a second launch still has it.
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
q "a look is set" \
  "paper table=portrait" --exportbox --exportpaper table:portrait --stay 4 \
  --window export --snapshot /dev/null
q "…and it is still there next time the box opens" \
  "paper table=portrait" --exportbox --stay 4 --window export --snapshot /dev/null
# **The export he does every week, kept.** Save a look under a name, work on
# to something else, then ask for the name back.
rm -f "${TMPDIR:-/tmp}/shotlister-check-export-presets.json"
q "a set-up is saved" \
  "preset Day package presets 4" \
  --exportbox --exportpaper table:portrait --exportsetup "save:Day package" \
  --stay 4 --window export --snapshot /dev/null
q "…and working on does not disturb it" \
  "paper table=landscape" --exportbox --exportpaper table:landscape --stay 4 \
  --window export --snapshot /dev/null
q "…and asking for it back brings the look with it" \
  "paper table=portrait" --exportbox --exportsetup "use:Day package" --stay 4 \
  --window export --snapshot /dev/null
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
# **A page already drawn costs nothing.** His complaint, 2026-09-02, was that
# the box felt laggy. Measured: the engine answers in 1-2ms and a page render
# costs 560-1200ms, and opening used to do six of them. Opening now draws the
# table; visiting the storyboard draws it; going back to either draws neither.
# Four visits, two renders. A claim about speed with no number under it is
# worth nothing, so this counts them.
# (Since 2026-10-15 the box also draws the other tabs in the background while
# he looks at the first, so the count is of *repeats*: no page drawn twice.)
seen=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --exportbox \
       --exportvisit storyboard,table,storyboard --stay 14 \
       --window export --snapshot /dev/null 2>&1 | grep "^timing " | cut -d: -f1 | sort | uniq -d | wc -l | tr -d ' ')
if [ "$seen" = "0" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a page already drawn is not drawn again"
else
  fail=$((fail+1))
  printf '  ✗  %s  (%s pages drawn twice, wanted 0)\n' \
    "a page already drawn is not drawn again" "$seen"
fi
# **Export… has to produce a file.** His report, 2026-10-15: "I tried to export
# a PDF but it didn't go." What he had left ticked from another film (a
# commercial's Script, *Each day* from a scheduled one) meant nothing was left
# to draw here, and the button made a save panel and no file. This presses the
# real button (`--exportsave` answers its save panel with a folder), with that
# stale setting planted, and wants a PDF on disk with pages and a lowercase,
# hyphened, dated name.
saved="$(mktemp -d)"
defaults write com.example.shotlister.studio export.checking \
  '<dict><key>workbookOffByDefault</key><true/><key>included</key><array><string>avscript</string></array></dict>'
out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --exportbox \
      --exportsave "$saved" --stay 14 --window export --snapshot /dev/null 2>&1)
made=$(ls "$saved" 2>/dev/null | head -1)
if echo "$out" | grep -q "^export wrote: .* pages: [1-9]" \
   && echo "$made" | grep -qE '^[a-z0-9-]+-[a-z0-9-]+-(script|schedule|location)-order-[0-9]{8}\.pdf$' \
   && [ -s "$saved/$made" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "Export… writes a named PDF with pages, even from stale settings"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "Export… writes a named PDF with pages, even from stale settings"
  echo "$out" | grep -E "^export" | sed 's/^/       /'; echo "       made: $made"
fi
rm -rf "$saved"
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
# ---- Order, Filter, Days, File per day and Presets (2026-10-15) ----------
# His approved redesign: As in Table carries the Table's sort; a Schedule
# picks days out of sixty; File per day writes a named folder; the name
# follows every choice; a preset comes back as it was saved.
rm -f "${TMPDIR:-/tmp}/shotlister-check-export-presets.json"
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
q "As in Table carries the Table's sort, into the page's corner and the name" \
  "order table .*caption SORTED BY SHOT SIZE .*name daybreak-[a-z-]+-sorted-by-shot-size-[0-9]{8}\.pdf" \
  --sortby size --exportbox --stay 4 --window export --snapshot /dev/null
q "Script order is named script-order, and a typed name is kept exactly" \
  "order script .*name My Call Sheet 3\.pdf" \
  --exportbox --exportset "arrange=script;name=My Call Sheet 3" --stay 4 --window export --snapshot /dev/null
q "a preset is saved with its order, filter and days rule" \
  "preset Round Trip presets 4 .*order schedule picked Day 2 " \
  --exportbox --exportset "arrange=schedule;days=2;filter=none" --exportsetup "save:Round Trip" \
  --stay 4 --window export --snapshot /dev/null
q "…and comes back the same on the next launch" \
  "preset Round Trip presets 4 .*order schedule picked Day 2 .*narrowing arrange=schedule&days=" \
  --exportbox --exportsetup "use:Round Trip" --stay 4 --window export --snapshot /dev/null
q "…and a change after picking it shows as Edited until updated" \
  "preset Round Trip .*order script .*edited yes" \
  --exportbox --exportsetup "use:Round Trip" --exportset "arrange=script" --stay 4 --window export --snapshot /dev/null
# **Auto keeps its own dials.** His words, 2026-10-16: "one slider that makes
# the information small or larger … i can also turn off column in auto mode as
# well without going manual … i can choose landscape or portrait for auto".
q "Auto's Size, paper and a column turned off leave the table on Auto" \
  "layout auto size 1\.20 autopaper portrait" \
  --exportbox --exportset "autosize=1.2;autopaper=portrait;off=notes" --stay 4 --window export --snapshot /dev/null
q "…and Auto lays the table out on the paper he said" \
  "auto table: portrait" \
  --exportbox --exportset "autosize=1.2;autopaper=portrait" --stay 6 --window export --snapshot /dev/null
q "…and a preset keeps Auto's Size and paper" \
  "preset Big Auto .*layout auto size 1\.20 autopaper portrait" \
  --exportbox --exportset "autosize=1.2;autopaper=portrait" --exportsetup "save:Big Auto" \
  --stay 4 --window export --snapshot /dev/null
q "…and brings them back on the next launch" \
  "preset Big Auto .*edited no layout auto size 1\.20 autopaper portrait" \
  --exportbox --exportsetup "use:Big Auto" \
  --stay 4 --window export --snapshot /dev/null
q "dragging Auto's Size keeps the table on Auto" \
  "export drag: slider was .* size [0-9.]+ auto" \
  --exportbox --exportdrag handsize:10 --stay 14 --window export --snapshot /dev/null
q "Manual is its own choice" \
  "layout manual" \
  --exportbox --exportset "layout=manual" --stay 4 --window export --snapshot /dev/null
# **The width dials are Manual's.** His words, 2026-10-17: "the individual
# column [controls] should be unavailable in auto mode … otherwise, what's the
# difference between the modes". Columns on and off stay on Auto.
q "On Auto there are no column width dials" \
  "export dials: width 0 layout auto" \
  --exportbox --exportset "layout=auto" --exportdrag dials --stay 10 --window export --snapshot /dev/null
q "…and Manual has them" \
  "export dials: width [1-9][0-9]* layout manual" \
  --exportbox --exportset "layout=manual" --exportdrag dials --stay 10 --window export --snapshot /dev/null
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
rm -f "${TMPDIR:-/tmp}/shotlister-check-export-presets.json"
# Sixty days: a copy of the fixture given 58 more, its shots spread one a day
# (`ffi/examples/run_commands.rs`), then Days 12–18 and 22 asked for.
RUNNER="ffi/target/debug/examples/run_commands"
( cd ffi && cargo build --quiet --example run_commands 2>/dev/null )
D60="$(mktemp -d)/Sixty.shotlist"; cp -R studio/fixtures/Daybreak.shotlist "$D60"
python3 - "$RUNNER" "$D60" <<'PY'
import json, subprocess, sys, datetime
runner, film = sys.argv[1], sys.argv[2]
d = datetime.date(2026, 11, 2); dates = []
while len(dates) < 58:
    if d.weekday() < 5: dates.append(d.isoformat())
    d += datetime.timedelta(days=1)
run = lambda cmds: subprocess.run([runner, film], input="\n".join(cmds) + "\n", capture_output=True, text=True).stdout.strip().split("\n")
v = json.loads(run(["day\tnew\t" + x for x in dates] + ["view"])[-1])
days = v["days"]; rows = [r for g in v["groups"] for r in g["rows"]]
cmds = ["place\t%s\t%s" % (r["placement"], days[11 + i]["id"]) for i, r in enumerate(rows[:11])]
run(cmds + ["view"])
PY
out=$("$APP" --project "$D60" --screen "$SCREEN" --place scenes --exportbox \
      --exportset "arrange=schedule;days=12-18+22" --stay 4 --window export --snapshot /dev/null 2>&1)
if echo "$out" | grep -q "days 60 .*picked Days 12–18, 22 (8 days) .*name daybreak-[a-z-]*days-12-18-22-[0-9]\{8\}\.pdf"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "the 60-day picker picks Days 12–18 and 22, and the name says so"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "the 60-day picker picks Days 12–18 and 22, and the name says so"
  echo "$out" | grep "export box" | cut -c1-300 | sed 's/^/       /'
fi
saved="$(mktemp -d)"
out=$("$APP" --project "$D60" --screen "$SCREEN" --place scenes --exportbox \
      --exportset "arrange=schedule;days=12-18+22" --exportsave "$saved" --stay 16 \
      --window export --snapshot /dev/null 2>&1)
pdf=$(ls "$saved"/*.pdf 2>/dev/null | head -1)
heads=$(pdftotext "$pdf" - 2>/dev/null | grep -oE "^Day [0-9]+$" | sort -u | tr '\n' ' ')
if [ -s "$pdf" ] && [ "$heads" = "Day 12 Day 13 Day 14 Day 15 Day 16 Day 17 Day 18 Day 22 " ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and the PDF holds exactly those days"
else
  fail=$((fail+1)); printf '  ✗  %s  (%s)\n' "…and the PDF holds exactly those days" "$heads"
fi
rm -rf "$saved"; saved="$(mktemp -d)"
"$APP" --project "$D60" --screen "$SCREEN" --place scenes --exportbox \
  --exportset "arrange=schedule;days=12-18+22;output=perday" --exportsave "$saved" --stay 30 \
  --window export --snapshot /dev/null >/dev/null 2>&1
folder=$(ls "$saved" 2>/dev/null | head -1)
pdfs=$(find "$saved/$folder" -name 'daybreak-*-day-*-[0-9]*.pdf' -size +1k 2>/dev/null | wc -l | tr -d ' ')
if echo "$folder" | grep -qE '^daybreak-[a-z-]+-days-12-18-22-[0-9]{8}$' && [ "$pdfs" = "8" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "File per day writes a named folder of eight PDFs"
else
  fail=$((fail+1)); printf '  ✗  %s  (folder %s, %s PDFs)\n' "File per day writes a named folder of eight PDFs" "$folder" "$pdfs"
fi
rm -rf "$saved" "$(dirname "$D60")"
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
rm -f "${TMPDIR:-/tmp}/shotlister-check-export-presets.json"
# **Each day writes a PDF a day, every one with pages.** The loose end of
# 2026-10-15: one Each-day run wrote nothing. The window used to close the
# moment the days began, and in a run where it was the last window the app
# quit with them unwritten. It now stays until the folder is written. Every
# day of a multi-day film, each file opened and its pages counted.
saved="$(mktemp -d)"; DD="$(mktemp -d)/Days.shotlist"; cp -R studio/fixtures/Daybreak.shotlist "$DD"
defaults write com.example.shotlister.studio export.checking \
  '<dict><key>workbookOffByDefault</key><true/><key>delivery</key><string>perDay</string></dict>'
out=$("$APP" --project "$DD" --screen "$SCREEN" --place scenes --exportbox \
      --exportset "arrange=schedule;days=all;output=perday" --exportsave "$saved" --stay 30 \
      --window export --snapshot /dev/null 2>&1)
want=$(echo "$out" | grep -oE "ticked [0-9]+ days [0-9]+" | grep -oE "[0-9]+$")
got=0; empty=0
while IFS= read -r f; do
  n=$(pdfinfo "$f" 2>/dev/null | awk '/^Pages:/{print $2}')
  if [ "${n:-0}" -ge 1 ]; then got=$((got+1)); else empty=$((empty+1)); fi
done < <(find "$saved" -name '*.pdf' -path '*day-*')
if [ -n "$want" ] && [ "$want" -ge 2 ] && [ "$got" -ge "$want" ] && [ "$empty" = "0" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "Each day writes one PDF per day, each with pages ($got)"
else
  fail=$((fail+1)); printf '  ✗  %s  (days %s, PDFs with pages %s, empty %s)\n' \
    "Each day writes one PDF per day, each with pages" "$want" "$got" "$empty"
fi
rm -rf "$saved" "$(dirname "$DD")"
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
# **A slider never freezes the window.** His report, 2026-10-15: "Every time I
# adjust a slider in the Export tab, there is a freeze with a rainbow wheel."
# Each run moves a dial twenty times a frame apart (`--exportdrag`: the width
# and size dials by value, and the size dial by real mouse events through the
# slider itself) while a helper thread knocks on the main thread every 4ms;
# the longest any knock waited, until the new page is drawn, must stay under
# 100ms. It was 4.7 seconds on Call Her Back.
for how in width:20 scale:20 handscale:20 size:20 handsize:20; do
  defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
  out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --exportbox \
        --exportdrag "$how" --stay 20 --window export --snapshot /dev/null 2>&1)
  worst=$(echo "$out" | sed -n 's/.*worst stall until drawn \([0-9]*\)ms.*/\1/p' | head -1)
  if [ -n "$worst" ] && [ "$worst" -lt 100 ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "dragging a slider ($how) never stalls the window (worst ${worst}ms)"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "dragging a slider ($how) never stalls the window (worst ${worst:-none}ms)"
    echo "$out" | grep -E "^export drag|^timing" | sed 's/^/       /'
  fi
done
defaults delete com.example.shotlister.studio export.checking 2>/dev/null || true
# **A clip strip reads back as made.** On macOS 27 ImageIO stopped returning the
# header word every strip is stamped with, so every strip looked stale and all
# forty of Call Her Back's were remade on every printed page: the freeze above.
q "a clip strip's header says which drawing made it" \
  "strip header: made shotlister-strip-[0-9]+" --stripcheck --stay 2
# **One press, one page.** His report, 2026-09-02: the arrows under the page
# needed clicking several times. PDFKit posts its own page-changed notice from
# inside the jump, while it still believes it is on the old page, and that came
# straight back and overwrote the new number — so every other press undid
# itself. And ← / → now turn the page at all, which they did not.
# **On a fresh copy each time.** These count pages, and this file deliberately
# edits the shared scratch as it goes — so on the shared one the answer depends
# on which checks ran before it, which is not a check at all.
qpage() {
  local name="$1"; local want="$2"; shift 2
  local fresh; fresh="$(mktemp -d)/Pages.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes "$@" 2>&1)
  if echo "$out" | grep -qE "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s  (%s)\n' "$name" \
      "$(echo "$out" | grep -E '^page:' | head -1)"
  fi
  rm -rf "$(dirname "$fresh")"
}
qpage "a press of the button turns exactly one page" \
  "^page: 2 of " --exportbox table --exportnext 1 --stay 14 --window export --snapshot /dev/null
qpage "…and three presses turn three"  \
  "^page: 4 of " --exportbox table --exportnext 3 --stay 16 --window export --snapshot /dev/null
# **Real key events, through the real monitor.** The harness's own typist fires
# about fifty milliseconds in, before this window exists, so its keys land in
# nothing; --exportkey posts them once the page is drawn.
qpage "the right arrow turns the page" \
  "^page: 3 of " --exportbox table --exportkey right,right --stay 16 --window export --snapshot /dev/null
qpage "…and the left arrow turns it back" \
  "^page: 2 of " --exportbox table --exportkey right,right,left --stay 16 --window export --snapshot /dev/null
# **The folder of days, checked by looking in the folder.** Its own summary
# line is not trustworthy — the archived note is explicit that the exit timer
# can kill the run before a WKWebView completion prints, so a missing line is
# not a failed export. The files are the only honest answer.
qdays() {
  local name="$1"; local pdfs_want="$2"; local xlsx_want="$3"; local wait="$4"; shift 4
  local dir; dir="$(mktemp -d)"
  local fresh; fresh="$(mktemp -d)/Days.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  "$APP" --project "$fresh" --screen "$SCREEN" --place scenes \
         --exportdays "$dir" "$@" --stay "$wait" >/dev/null 2>&1
  local pdfs xlsxs empty
  pdfs=$(find "$dir" -name '*.pdf' | wc -l | tr -d ' ')
  xlsxs=$(find "$dir" -name '*.xlsx' | wc -l | tr -d ' ')
  # A nought-byte PDF counts as written by any test that only counts files.
  empty=$(find "$dir" -name '*.pdf' -size -1k | wc -l | tr -d ' ')
  if [ "$pdfs" = "$pdfs_want" ] && [ "$xlsxs" = "$xlsx_want" ] && [ "$empty" = "0" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1))
    printf '  ✗  %s  (%s pdf, %s xlsx, %s empty — wanted %s, %s, 0)\n' \
      "$name" "$pdfs" "$xlsxs" "$empty" "$pdfs_want" "$xlsx_want"
  fi
  rm -rf "$dir" "$(dirname "$fresh")"
}
qdays "one day writes its page and its workbook" 1 1 9 1
qdays "…and two days write two of each"          2 2 15 1,2
# **A day's file is that day\'s.** Two files of identical content would mean
# the narrowing never happened and both days got the whole film — which is the
# shape of Ref 610, seen from the app end rather than the engine\'s.
DD="$(mktemp -d)"; DF="$(mktemp -d)/Days.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$DF"
"$APP" --project "$DF" --screen "$SCREEN" --place scenes --exportdays "$DD" 1,2 --stay 15 >/dev/null 2>&1
same=$(find "$DD" -name '*.pdf' -exec shasum {} \; | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
if [ "$same" = "2" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "…and the two days are not the same file"
else
  fail=$((fail+1)); printf '  ✗  %s  (%s distinct)\n' "…and the two days are not the same file" "$same"
fi
rm -rf "$DD" "$(dirname "$DF")"
# **A day's diagram file holds that day's scenes only** (Ref 1503, the Mac end
# of the engine's `day=`). Two scenes drawn, the second put on Day 2, then
# each day's Diagram PDF is read for its scene headings.
if command -v pdftotext >/dev/null 2>&1; then
  DD="$(mktemp -d)"; DF="$(mktemp -d)/Days.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$DF"
  for sc in 34 35; do
    "$APP" --project "$DF" --screen "$SCREEN" --place diagram --scene $sc --diagramsample --stay 4 >/dev/null 2>&1
    sleep 1
  done
  "$APP" --project "$DF" --screen "$SCREEN" --place scenes --puton 35 2 \
         --exportdays "$DD" 1,2 --daysections diagram --stay 15 >/dev/null 2>&1
  d1="$(pdftotext "$(ls "$DD"/*Day-01*.pdf 2>/dev/null | head -1)" - 2>/dev/null)"
  d2="$(pdftotext "$(ls "$DD"/*Day-02*.pdf 2>/dev/null | head -1)" - 2>/dev/null)"
  if echo "$d1" | grep -q "^34 · " && ! echo "$d1" | grep -q "^35 · " \
     && echo "$d2" | grep -q "^35 · " && ! echo "$d2" | grep -q "^34 · "; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a day's diagram file holds only that day's scenes"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a day's diagram file holds only that day's scenes"
  fi
  rm -rf "$DD" "$(dirname "$DF")"
fi
rm -rf "$EX"

fi

# ---- one file holding a whole film -------------------------------------
#
# **`Copies`, both ways.** His ask, 2026-09-04: *"the ability to export a
# project file with everything you'd ever need to restore it."* The word doing
# the work is *everything* — a backup zip deliberately leaves the photographs
# out, and this is the one thing in the app that does not.
#
# So the check is a count, not a spot test: every file that went in comes back
# out. A copy that quietly dropped the pictures would still open, still draw a
# shot list, and still look completely right.
#
# **The bin itself is not checked here and that is a hole**, filed as its own
# row: archiving reaches into *Documents/Shotlister*, which is his real films
# folder, and a battery that makes and deletes a film in there every run is a
# worse idea than the coverage is worth.
if slow; then
echo "── one file holding a whole film ──"
CP="$(mktemp -d)"
cp -R studio/fixtures/Daybreak.shotlist "$CP/Copied.shotlist"
# A picture nothing points at, so a copy that only carries what the document
# mentions is caught. It is the exact case that made archiving fetch first.
mkdir -p "$CP/Copied.shotlist/media/proxies"
printf 'a photograph' > "$CP/Copied.shotlist/media/proxies/ffffffffffffffffffffffffffffffff.jpg"

out=$("$APP" --project "$CP/Copied.shotlist" --screen "$SCREEN" --place scenes \
        --exportcopy "$CP/Copied.shotlist.zip" 2>&1)
# **Counted after the export, not before.** Opening a film puts this Mac's own
# identity mark beside the logs, so a count taken before the run is one short of
# what the copy actually holds — 18 in, 19 out, and nothing wrong with either.
before=$(find "$CP/Copied.shotlist" -type f ! -name '.*' | wc -l | tr -d ' ')
if echo "$out" | grep -q "^exported: .*[0-9] bytes"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a film can be written as one file"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a film can be written as one file"
  echo "$out" | grep -i exported | sed 's/^/       /'
fi

out=$("$APP" --project "$CP/Copied.shotlist" --screen "$SCREEN" --place scenes \
        --openedcopy "$CP/Copied.shotlist.zip" 2>&1)
back=$(echo "$out" | sed -n 's/^opened copy: //p')
after=$(find "$back" -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')
if [ -n "$back" ] && [ "$before" = "$after" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "and everything in it comes back out"
else
  fail=$((fail+1)); printf '  ✗  %s  (%s files in, %s out)\n' "and everything in it comes back out" "$before" "$after"
fi
if [ -f "$back/media/proxies/ffffffffffffffffffffffffffffffff.jpg" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "the photographs are in it, which is the whole difference from a backup"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "the photographs are in it, which is the whole difference from a backup"
fi
# **Never over the top of a film.** A copy is opened to compare it with what is
# here; one that clobbers is a second way to lose the work.
if [ -n "$back" ] && [ "$back" != "$CP/Copied.shotlist" ] && [ -d "$CP/Copied.shotlist" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "and it lands beside the film, never over it"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "and it lands beside the film, never over it"
fi
rm -rf "$CP"
fi

if slow "the schedule's hand"; then
echo "── the schedule's hand ──"
# **Every drag on the Schedule, driven the way his mouse drives it** — his
# report, 2026-09-29: scenes dragged onto the schedule "just get stuck, won't
# come over, start multi selecting". The board carries things itself now
# (`ScheduleHands.swift`) instead of through a system drag session, which no
# synthetic mouse can drive, so `--mouse` presses, pulls and lets go with
# real events and the app prints what the engine holds afterwards. Window
# points on the untouched fixture: Day 1 holds 33, 34, 35, 54 at y 155, 193,
# 231, 269; Day 2 is empty at y 319–405; the scene list's rows are at y 111,
# 141, 171, 201.
hand() {
  local name="$1" script="$2"; shift 2
  local fresh; fresh="$(mktemp -d)/Fresh.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place schedule ${HAND_FIRST:-} --mouse "$script" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  local miss=""
  for want in "$@"; do echo "$out" | grep -qF "$want" || miss="$miss [$want]"; done
  if [ -z "$miss" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s — missing%s\n' "$name" "$miss"
    echo "$out" | grep -E "^(strips|picked|open|tab|hand):" | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}
hand "a strip lands where it is let go in its day" \
  "down 600 269; move 600 145 8; up 600 145" "strips: Day 1 = 54,33,34,35"
hand "a strip carried to another day moves there" \
  "down 600 193; move 600 360 10; up 600 360" "strips: Day 1 = 33,35,54" "strips: Day 2 = 34"
hand "a scene pulled from the list picks up no rows it crosses" \
  "down 120 171; move 120 205 4; move 600 360 10; up 600 360" "picked: 33" "hand: carry Scene 35"
hand "a strip let go on the scene list comes off its day" \
  "down 600 231; move 120 500 10; up 120 500" "strips: Day 1 = 33,34,54" "land off the board"
hand "a day's band carried above another swaps them" \
  "down 500 319; move 500 110 10; up 500 110" "strips: Day 2 = 33,34,35,54"
hand "a click on a strip's chevron opens it, once, and stays here" \
  "click 293 155" "open: 33" "tab: schedule" "hand: click"
hand "escape puts a carried strip back" \
  "down 600 193; move 600 360 10; key esc; up 600 360" "strips: Day 1 = 33,34,35,54" "put back"
# A press on a scene row is held from the list until it is known to be a
# click (his report, 2026-09-30: the second drag "doesn't really move, and it
# ends up highlighting" rows) — so a click must still pick, ⌘ and ⇧ with it.
hand "a click on the scene list still picks the scene" \
  "click 120 171" "picked: 35" "tab: schedule"
hand "…and ⌘-click and ⇧-click still add" \
  "click 120 141; wait 0.6; click 120 201 cmd; wait 0.6; click 120 171 shift" "picked: 34,35,54"
hand "two scenes pulled from the list, one after the other, both land" \
  "down 600 269; move 120 500 10; up 120 500; wait 0.5; down 600 231; move 120 500 10; up 120 500; wait 0.8; down 120 201; wait 0.5; move 121 201 1; move 600 160 10; up 600 160; wait 0.8; down 120 171; wait 0.5; move 121 171 1; move 600 160 10; up 600 160" "strips: Day 1 = 33,35,54,34"
# **A scene partly on a day: only what is left travels** — his report,
# 2026-10-17, on Call Her Back: scene 16 read "Day 3 · 3 left", and dragging it
# took its Day 3 shots along (or nowhere he wanted). Here 34C is taken off
# Day 1 first, so 34 reads "Day 1 · 1 left"; its row (y 141) carried to Day 2
# brings 34C alone, and 34's other shots stay on Day 1. Then the row opened
# by its chevron (x 216) shows 34C on a row of its own (y 171), which can be
# dragged by itself.
HAND_FIRST="--putshot 34C none" hand "drag remaining shots of a partly scheduled scene onto a day" \
  "down 120 141; move 125 145 3; move 600 360 10; up 600 360" \
  "strips: Day 1 = 33,34,35,54" "strips: Day 2 = 34" "run: Day 2 = 34C" "carry Scene 34 · 1 shot"
HAND_FIRST="--putshot 34C none" hand "…a scene opened in the list shows what is left, and one shot drags by itself" \
  "click 216 141; wait 0.5; down 120 171; move 125 175 3; move 600 360 10; up 600 360" \
  "remainders open: 34" "run: Day 2 = 34C" "carry 34C" "strips: Day 1 = 33,34,35,54"
HAND_FIRST="--putshot 34C none" hand "…and ⌘Z takes it back in one step" \
  "down 120 141; move 125 145 3; move 600 360 10; up 600 360; wait 0.3; key undo; wait 0.3" \
  "waiting: 34x1" "land Day 2 at 0"
hand "⌘Z takes back a whole drop in one step" \
  "down 600 269; move 600 145 8; up 600 145; wait 0.3; key undo; wait 0.3" "strips: Day 1 = 33,34,35,54" "land Day 1 at 0"
fi

if slow "copy, cut, paste, undo and redo"; then
echo "── copy, cut, paste, undo and redo, on every kind of selection ──"
# Ref 390. A fresh copy each time; `--cells` prints what every shot holds, the
# clipboard the run copied through (never his) and how deep the history is.
# A newline inside a value is printed as ~ so one line holds the lot.
cc() {
  local name="$1"; local want="$2"; shift 2
  local fresh; fresh="$(mktemp -d)/Clip.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes --scene 34 "$@" --columns 2>&1 \
    | tr '\n' '~')
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qE "$want"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "$name"
    echo "$out" | tr '~' '\n' | grep -E "^(cells|clip|history|shots)" | cut -c1-200 | sed 's/^/       /'
  fi
  rm -rf "$(dirname "$fresh")"
}
SIZES='34A=M/OTS\|34B=CU/OTS\|34C=M/OTS\|34D=M/OTS'
cc "ticked shots copy their column, a line each" 'clip: M/OTS\\nCU/OTS\\nM/OTS' \
  --mark 34A,34B,34C --cell size --shot 34C --cells size --type "⌘c" --hold
cc "ticked shots cut together" 'cells size: [^~]*34A=\|34B=\|34C=\|34D=M/OTS' \
  --mark 34A,34B,34C --cell size --shot 34C --cells size --type "⌘x" --hold
cc "…one ⌘Z gives them all back" "cells size: [^~]*$SIZES" \
  --mark 34A,34B,34C --cell size --shot 34C --cells size --type "⌘x⌘z" --hold
cc "…and ⇧⌘Z cuts them again" 'cells size: [^~]*34A=\|34B=\|34C=\|34D=M/OTS' \
  --mark 34A,34B,34C --cell size --shot 34C --cells size --type "⌘x⌘z⌘Z" --hold
cc "a block pasted onto ticked shots lands a line each" 'cells size: [^~]*34A=X\|34B=Y\|34C=Z\|34D=M/OTS' \
  --mark 34A,34B,34C --cell size --shot 34A --cells size --paste "X
Y
Z"
cc "…and is one step to take back" 'history: depth 1 undo "Paste"' \
  --mark 34A,34B,34C --cell size --shot 34A --cells size --paste "X
Y
Z"
cc "a dragged block copies as rows and columns" 'clip: M/OTS\\tShort-Sided\\nCU/OTS\\tShort-Sided' \
  --range 34A/size..34B/angle --cells size --type "⌘c" --hold
cc "a block spills from one cell, one ⌘Z takes it back" 'cells size: [^~]*34D=M/OTS\|34E=W\|.*history: depth 0 undo "" redo "Paste"' \
  --range 34A/size..34B/angle --cells size --type "⌘c↓↓↓⌘v⌘z" --hold
cc "a dragged block cuts in one step" 'history: depth 1 undo "Clear cells"' \
  --range 34A/size..34B/angle --cells size --type "⌘x" --hold
cc "…takes back and goes again" 'cells size: [^~]*34A=\|34B=\|34C=M/OTS.*history: depth 1 undo "Clear cells"' \
  --range 34A/size..34B/angle --cells size --type "⌘x⌘z⌘Z" --hold
cc "different values over a range are one ⌘Z" 'history: depth 1 undo "Paste" redo ""' \
  --range 34A/size..34C/angle --cells size --paste "A	B
C	D
E	F"
cc "a cell of two lines pastes as one cell" 'cells notes: [^~]*34A=one~two\|34B=\|34C=' \
  --shot 34A --cell notes --cells notes --paste "\"one
two\""
cc "a block from Sheets does not clear the row after it" 'cells size: [^~]*34A=P\|34B=Q\|34C=M/OTS' \
  --shot 34A --cell size --cells size --paste "P
Q
"
cc "a cell that cannot be cut still copies" 'clip: Day 1' \
  --shot 34A --cell day --cells day --type "⌘c" --hold
cc "whole shots copy and paste as shots" '34:34A,34B,34C,34D,34E,34F,34G' \
  --pick 34A,34B --cell size --type "⌘c⌘v" --hold
cc "…one ⌘Z takes the pair back" '34:34A,34B,34C,34D,34E \|' \
  --pick 34A,34B --cell size --type "⌘c⌘v⌘z" --hold
cc "whole shots cut away, the letters closing up" '34:34A,34B,34C \|' \
  --pick 34A,34B --cell size --type "⌘x" --hold
cc "…stay on the clipboard, and the cut is one step" 'clip: [^~]*Milo French.*history: depth 1 undo "Delete 2 shots"' \
  --pick 34A,34B --cell size --cells size --type "⌘x" --hold
cc "…one ⌘Z brings them back" '34:34A,34B,34C,34D,34E \|' \
  --pick 34A,34B --cell size --type "⌘x⌘z" --hold
cc "…and ⇧⌘Z cuts them again" '34:34A,34B,34C \|' \
  --pick 34A,34B --cell size --type "⌘x⌘z⌘Z" --hold
cc "delete takes every ringed shot" '34:34A,34B,34C \|' \
  --pick 34A,34B --cell size --type "⌘⌫" --hold
cc "…and ⌘Z brings them all back" '34:34A,34B,34C,34D,34E \|' \
  --pick 34A,34B --cell size --type "⌘⌫⌘z" --hold
fi

# Mods (2026-10-17): Edit Reference draws only while the project has the mod
# on; off, the same film draws exactly as before. A fresh copy each time.
if slow "edit reference"; then
echo "── edit reference (the first mod) ──"
qfresh "with the mod on: a bracket from 34A to 34D" \
  "edit pieces: 34A:first Car cut, 34B:Car cut, 34C:Car cut, 34D:last Car cut" \
  --modson edit_reference --addeditref 34A,34B,34C,34D --editrefsays
qfresh "with the mod off: the same film draws no bracket" \
  "edit pieces: none" --addeditref 34A,34B --editrefsays
# His note, 2026-10-17: a run across a scene heading is one bracket.
qfresh "across scenes 34 and 35: one bracket" \
  "edit pieces: 34D:first Car cut, 34E:Car cut, 35A:last Car cut" \
  --modson edit_reference --addeditref 34D,34E,35A --editrefsays 1
qfresh "across scenes 34 and 35: the line runs over the heading" \
  "edit through: under 34, over 35" \
  --modson edit_reference --addeditref 34D,34E,35A --editrefsays 1
# His report, 2026-10-17: a press on the gold play button only picked the row
# behind it. A real mouse press (--tap sends one): the button opens the player
# and leaves the row alone; the shot number beside it still picks the row.
qfresh "a press on the play button opens the player, picks no row" \
  "editref tap: player open, cursor on none" \
  --modson edit_reference --addeditref 34C,34D,34E --tap 272,545
qfresh "…a press on the shot number beside it still picks the row" \
  "editref tap: player closed, cursor on 34C" \
  --modson edit_reference --addeditref 34C,34D,34E --tap 300,545
fi

# The always-updating spreadsheet gets its own folder (2026-10-15): one linked
# beside his own spreadsheets is moved into shot-list/live-sheet/ and the link
# follows it; his own files stay exactly where they are.
LS="$(mktemp -d)"
cp -R studio/fixtures/Daybreak.shotlist "$LS/Q.shotlist"
mkdir -p "$LS/proj/1-creative/shot-list"
echo old > "$LS/proj/1-creative/shot-list/Film.xlsx"; echo mine > "$LS/proj/1-creative/shot-list/His own.xlsx"
lsout=$("$APP" --project "$LS/Q.shotlist" --screen "$SCREEN" --place scenes \
  --excellink "$LS/proj/1-creative/shot-list/Film.xlsx" --excelauto on --excelnow --excelsays 2>&1)
if echo "$lsout" | grep -q "excel path: .*/shot-list/live-sheet/Film.xlsx .*exists: true" \
   && [ ! -e "$LS/proj/1-creative/shot-list/Film.xlsx" ] \
   && [ "$(cat "$LS/proj/1-creative/shot-list/His own.xlsx")" = "mine" ]; then
  pass=$((pass+1)); printf '  ✓  %s\n' "the linked spreadsheet moves into live-sheet/, his own stays"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "the linked spreadsheet moves into live-sheet/, his own stays"; echo "$lsout" | grep -i excel | sed 's/^/       /'
fi
rm -rf "$LS"

echo "────"
echo "passed $pass, failed $fail, focus trips $trips, $(( $(date +%s) - started ))s"
[ "$held" -gt 0 ] && echo "$held sections held back — studio/quick.sh --all runs them, and studio/checks.sh is the real battery"
echo
echo "── copy, against the law in CLAUDE.md ──"
tools/check-copy.sh
rm -rf "$(dirname "$SCRATCH")"
[ "$fail" -eq 0 ]
