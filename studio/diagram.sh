#!/bin/bash
# The Diagram mode's own checks. **Real mouse events on the real canvas**,
# read back from what the plan then holds — not the engine alone, which has
# its own tests (`cargo test diagram`).
#
#   studio/diagram.sh            — the Labs build
#   SHOTLISTER_APP=…/X.app/Contents/MacOS/Y studio/diagram.sh — any other bundle
#   DIAGRAM_ONLY=walls,corner studio/diagram.sh — just those blocks (run names)
#
# **It never touches the app's own preferences**: the bundle is copied to a
# scratch folder with a bundle id of its own, so every run's preferences are
# new and thrown away at the end (see $PREFS below). Pass the installed Studio
# or main's build as SHOTLISTER_APP and nothing of his changes.
#
# About fifteen minutes: a hundred launches. Each one waits for the last to be
# gone, because two instances overlapping is how a run comes up with no window.
#
# **With the screen locked, a run that carries extra flags gets no window at
# all** (found 2026-09-26). So everything a check asks for — the drive, the
# look, the hold — goes in through the environment, and the command line
# carries only the film, the screen, the mode and the scene.
set -u
cd "$(dirname "$0")/.."
REAL_APP="${SHOTLISTER_APP:-$(pwd)/build/Shotlister Labs.app/Contents/MacOS/ShotlisterStudio}"
SCREEN="${SHOTLISTER_SCREEN:-HP}"
WORK="$(mktemp -d)"

# **Always its own preferences — never the app's real ones** (2026-10-15).
# A run used to share the real Studio's preferences, and its clean-up deleted
# `diagramRecent.light/.grip/.set` from them, which emptied his recent-pieces
# lists. Now the bundle under test is copied into the run's temp folder with a
# bundle identifier of its own (`com.example.diagramcheck.<pid>`) and
# re-signed ad-hoc, so macOS keeps its preferences in a separate domain. The
# checks and the clean-up below only ever name that domain ($PREFS), and the
# domain is wiped on the way out. The real bundle is read, never touched.
PREFS="com.example.diagramcheck.$$"
BUNDLE="${REAL_APP%/Contents/MacOS/*}"
case "$BUNDLE" in *.app) ;; *) echo "SHOTLISTER_APP must be the binary inside an .app bundle (…/X.app/Contents/MacOS/Y): $REAL_APP"; exit 1;; esac
cp -R "$BUNDLE" "$WORK/Check.app" || { echo "could not copy $BUNDLE"; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PREFS" "$WORK/Check.app/Contents/Info.plist" || exit 1
codesign --force --deep --sign - "$WORK/Check.app" >/dev/null 2>&1 || { echo "could not sign the scratch copy"; exit 1; }
APP="$WORK/Check.app/Contents/MacOS/${REAL_APP##*/}"
[ -x "$APP" ] || { echo "no binary at $APP"; exit 1; }
# Waits are on this scratch copy alone: another checkout's copy of the app,
# open for somebody else's work, is not ours to wait on or to close.
gone() { while pgrep -f "$APP" >/dev/null; do sleep 0.5; done; }
wipe_prefs() { defaults delete "$PREFS" >/dev/null 2>&1; rm -f "$HOME/Library/Preferences/$PREFS.plist"; }
trap 'gone; wipe_prefs; rm -rf "$WORK"' EXIT
wipe_prefs
cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
FILM="$WORK/Daybreak.shotlist"
pass=0; fail=0

# (Preferences start empty: the scratch domain above is new every run.)

# **Picking a drawing tool folds the left sidebar** (Diagram.swift: a tool
# other than Select / Move View folds the scenes list away, 0.18 s ease) and
# the canvas widens to the left. A drive step 0.12 s after `tool wall` lands
# mid-animation, so the first click of the run meets a canvas that is still
# sliding and every later click sits a sidebar's width from where the check
# meant (this, not the paper refitting, is what made "clicks at fixed
# spots" miss after 2026-10-04). The fold is part of how Diagram behaves, so
# the run waits it out: a pause right after the first drawing-tool pick.
settle() { echo "$1" | perl -pe 's/\b(tool (?:wall|camera|cast|light|grip|frame|door|sliding|window|opening|set|track|road|text|arrow|connector|measure|shape|pen|cable|note|picture))\b/$1; wait 0.7/'; }

run() { # run <name> <drive> [stay] — prints the log
  local out="$WORK/$1.log"
  # DIAGRAM_ONLY=walls,corner — run just those blocks (by run name), for
  # working on a few checks without the whole quarter of an hour. The others
  # print nothing, so their checks FAIL: read only the ones you asked for.
  if [ -n "${DIAGRAM_ONLY:-}" ] && ! echo ",$DIAGRAM_ONLY," | grep -q ",$1,"; then echo "windows: Shot (skipped)"; return; fi
  # **Every run starts from a fresh copy of the fixture.** Earlier runs
  # leave pieces behind, and the diagram fits its view to whatever the plan
  # holds when its window first draws, so a run on a used film starts at a
  # different zoom and every click lands somewhere else. (`KEEPFILM=1` is for
  # the one run that wants the last run's film: favorites travel with it.)
  if [ "$FILM" = "$WORK/Daybreak.shotlist" ] && [ "${KEEPFILM:-}" != 1 ]; then rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"; fi
  gone
  # Details, once opened, stays open on that Mac (2026-10-17); every run
  # starts as a Mac that has never opened it, unless it asks to keep it.
  [ "${KEEPDETAILS:-}" = 1 ] || defaults delete "$PREFS" diagramDetailsOpen >/dev/null 2>&1
  sleep 1
  SHOTLISTER_STAY="${3:-6}" SHOTLISTER_DIAGRAMDRIVE="$(settle "$2")" \
    "$APP" --project "$FILM" --screen "$SCREEN" --place diagram --scene 34 --snapshot "$WORK/$1.png" >"$out" 2>&1 &
  local p=$!
  for _ in $(seq 1 60); do kill -0 $p 2>/dev/null || break; sleep 0.5; done
  kill $p 2>/dev/null
  cat "$out"
}
check() { # check <name> <condition-result> <why>
  if [ "$2" = "yes" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 — $3"; fi
}
# **Where the chrome is** (design/24, 2026-09-28): the toolbar across the top
# middle, the foot bar at the bottom middle, zoom bottom right, and Details
# down the right (x ≳ 1000) once something is picked. The Light and Set tools
# open their library under the toolbar, over x≈250–630, y≈60–520 — so a check
# that places a library piece clicks below it (y 600–620).
last() { awk '/^drive:/{block=""} {block=block"\n"$0} END{print block}' | sed -n '/^drive:/,$p' | sed '/^picture reads/,$d'; }
# `ex <out> <n>` — the nth `exact:` print of a run.
ex() { echo "$1" | awk -v n="$2" '/^exact:/{k++} k==n'; }

# 1 — walls, a chain closed on its first corner
out=$(run walls "tool wall; click 300 200; click 700 200; click 700 500; click 300 500; click 300 200; report")
echo "$out" | grep -q "^windows: Shot" || { echo "no window — is the screen asleep? (run again with it awake)"; exit 1; }
n=$(echo "$out" | grep -c "^  wall ")
check "a wall drawn corner by corner is one line, closed on its first corner" "$([ "$n" = 1 ] && echo "$out" | grep '^  wall ' | grep -q 'corners 4 closed' && echo yes)" "$n walls: $(echo "$out" | grep '^  wall ')"

# 2 — a camera, placed and aimed, brings its own shot
out=$(run camera "tool camera; down 500 350; drag 530 330; drag 560 320; up 560 320; report; showinlist")
check "a camera is placed" "$(echo "$out" | grep -q '^  camera ' && echo yes)" "no camera"
check "…and stands for a new shot" "$(echo "$out" | grep '^  camera ' | grep -q ' shot ' && echo yes)" "not linked"
check "…and Show in Shot List finds that shot there" "$(echo "$out" | grep -qE '^shotlist: place scenes row 34[A-Z]' && echo yes)" "$(echo "$out" | grep '^shotlist:')"
check "…turned the way it was dragged" "$(echo "$out" | grep '^  camera ' | grep -qE 'rot -?[1-9]' && echo yes)" "not turned"

# 3 — a drag moves it on the grid, a delete takes it and leaves its shot
out=$(run move "tool camera; click 500 350; tool select; pickkind camera; report; haul 40 0; report; key delete; report")
was=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  camera ' | grep '\[picked\]' | grep -o 'at [^ ]*')
now=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep '^  camera ' | grep '\[picked\]' | grep -o 'at [^ ]*')
cam=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  camera ' | grep '\[picked\]' | awk '{print $2}')
# On the grid: both numbers a whole number of feet.
ongrid=$(echo "$now" | python3 -c "import sys; x,y=[float(v) for v in sys.stdin.read().split()[1].split(',')]; print('yes' if all(abs(v/0.3048-round(v/0.3048))<0.02 for v in (x,y)) else '')")
check "a drag moves the camera onto the grid" "$([ -n "$now" ] && [ "$was" != "$now" ] && [ "$ongrid" = yes ] && echo yes)" "$was → $now"
check "delete takes the camera" "$([ -n "$cam" ] && ! echo "$out" | awk '/^drive:/{n++} n==3' | grep -q "^  camera $cam " && echo yes)" "still there"

# 4 — a door onto a wall; a person moved; undo and redo (the beats this block
# once checked are gone: no moves or beats since 2026-10-03)
out=$(run block "tool wall; click 300 200; click 700 200; key return; tool door; click 520 206; tool cast; click 380 420; tool select; pickkind cast; report; haul 40 20; report; key z command; report; key z command shift; report")
wy=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  wall ' | head -1 | grep -o ' at [^ ]*' | cut -d, -f2)
dy=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  door ' | head -1 | grep -o ' at [^ ]*' | cut -d, -f2)
check "a door dropped by a wall lands in it" "$([ -n "$wy" ] && [ "$wy" = "$dy" ] && echo yes)" "wall at y $wy, door at y $dy"
at4() { echo "$out" | awk -v k="$1" '/^drive:/{n++} n==k' | grep '^  cast ' | grep -o ' at [^ ]*'; }
check "a person dragged moves" "$([ -n "$(at4 2)" ] && [ "$(at4 2)" != "$(at4 1)" ] && echo yes)" "$(at4 1) → $(at4 2)"
check "⌘Z takes the move back" "$([ "$(at4 3)" = "$(at4 1)" ] && echo yes)" "$(at4 3), wanted $(at4 1)"
check "⇧⌘Z puts it back" "$([ "$(at4 4)" = "$(at4 2)" ] && echo yes)" "$(at4 4), wanted $(at4 2)"

# 5 — resize from a corner and turn by the knob
# The Film Set Objects pack's bed: a queen, five feet by six foot eight
# (2026-09-30 — it was the picture's 1.62 by 1.89 m).
out=$(run handles "tool set; arm fso-bed; click 400 600; tool select; report; grab corner 2 60 40; report; grab rotate 0 80 80; report")
before=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep 'size 1.52x2.03' | head -1)
after=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep '\[picked\]')
check "a corner resizes a set piece" "$([ -n "$before" ] && [ -n "$after" ] && ! echo "$after" | grep -q 'size 1.52x2.03' && echo yes)" "$after"
check "the knob turns it" "$(echo "$out" | awk '/^drive:/{n++} n==3' | grep '\[picked\]' | grep -qE 'rot [1-9]' && echo yes)" "not turned"

# 5b — put down with the Light tool, the mark is picked and turns by its knob
# straight away: no going back to the arrow first (his report, 2026-09-27).
# The Light tool **stays** the tool after a click (2026-10-03, marks are laid
# in a row: "chose the symbol and click where i want to add lights"); Esc
# goes back to the arrow. A fixture dragged in from the library is picked on
# the arrow, and turns the same way.
out=$(run turnnow "tool light; click 400 600; grab rotate 0 80 80; report; click 500 600; report; key escape; report; drop sym:tungsten-fresnel-1k 700 300; grab rotate 0 -80 80; report")
first=$(echo "$out" | awk '/^drive:/{n++} n==1')
check "a Light clicked down is picked and turns by its knob" "$(echo "$first" | grep -q 'picked 1; tool light' && echo "$first" | grep '^  light .*\[picked\]' | grep -qE 'rot -?[1-9]' && echo yes)" "$(echo "$first" | grep -E '^drive|picked\]')"
check "…the Light tool stays selected, so the next click lays another mark" "$(echo "$out" | awk '/^drive:/{n++} n==2' | grep -q '^drive: 2 els; picked 1; tool light' && echo yes)" "$(echo "$out" | awk '/^drive:/{n++} n==2' | head -1)"
check "…and Esc goes back to the arrow" "$(echo "$out" | awk '/^drive:/{n++} n==3' | grep -q 'tool select' && echo yes)" "$(echo "$out" | awk '/^drive:/{n++} n==3' | head -1)"
fourth=$(echo "$out" | awk '/^drive:/{n++} n==4')
check "…a fixture dragged in from the library is picked on the arrow, and turns by its knob too" "$(echo "$fourth" | grep -q 'picked 1; tool select' && l=$(echo "$fourth" | grep '^  light .*sym tungsten-fresnel-1k.*\[picked\]') && [ -n "$l" ] && ! echo "$l" | grep -q 'rot 270 ' && echo yes)" "$(echo "$fourth" | grep -E '^drive|picked\]')"

# 5d — aimed: the knob let go over a person aims the light at them, and it
# keeps facing them when they move (Scenario's targeting)
out=$(run aim "tool cast; castas MAYA; click 640 600; tool light; arm tungsten-fresnel-1k; click 380 600; aimat cast; report; tool select; click 640 600; haul 0 -160; report")
one=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  light .* aim ')
two=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep '^  light .* aim ')
check "the knob dropped on a person aims the light at them" "$(echo "$one" | grep -q 'aim cast' && echo "$one" | grep -qE 'rot (0|359|1) ' && echo yes)" "$one"
check "…and it turns to follow when they move" "$(echo "$two" | grep -q 'aim cast' && echo "$two" | grep -qE 'rot 3[0-3][0-9] ' && echo yes)" "$two"

# 5g — live while dragging: a lamp aimed at a person turns with them before
# the drag lets go (his ask, 2026-09-28: everything answers mid-move)
out=$(run live "tool cast; castas MAYA; click 640 620; tool light; arm tungsten-fresnel-1k; click 480 620; aimat cast; tool select; click 640 620; down 640 620; drag 640 570; drag 640 490; live; up 640 490")
lamp=$(echo "$out" | grep '^live: light' | tail -1)
check "an aimed lamp turns mid-drag, before the drag lets go" "$(echo "$lamp" | grep -qE 'rot (29[0-9]|3[0-4][0-9])$' && echo yes)" "$lamp"

# 5h — Layers: every piece listed top of the stack first, and one dragged
# there lands just over another (Scenario's Layers sidebar, his ask 09-28)
# A fresh film: pieces left by earlier checks (the enlarged bed) would
# carry this one's camera now that pieces ride what they stand on.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run layers "tool cast; castas MAYA; click 640 470; tool camera; down 620 600; drag 640 580; up 620 600; drop sym:generic-bounce 760 420; layers; restack light below cast; layers")
one=$(echo "$out" | grep '^layers:' | head -1); two=$(echo "$out" | grep '^layers:' | tail -1)
check "Layers lists the plan top first" "$(echo "$one" | grep -qE '^layers: Bounce \| [0-9]+[A-Z] \| MAYA' && echo yes)" "$one"
check "…and a piece restacked there lands under another" "$(echo "$two" | grep -qE '^layers: [0-9]+[A-Z] \| MAYA \| Bounce' && echo yes)" "$two"

# 5e — Set Scale: a picture sized so a line dragged across it is a length he
# knows. The same line called ten feet, then twenty: the second step is twice
# the first, because it is the same plan length asked to be twice as long.
out=$(run scale "pictures 0 back; report; calibrate 10 ft; down 400 400; drag 450 400; drag 500 400; up 500 400; report; calibrate 20 ft; down 400 400; drag 450 400; drag 500 400; up 500 400; report")
w=( $(for n in 1 2 3; do echo "$out" | awk -v n=$n '/^drive:/{k++} k==n' | grep '^  image ' | tail -1 | grep -o 'size [0-9.]*' | cut -d' ' -f2; done) )
check "Set Scale sizes a picture to a known length" "$(python3 -c "w=[${w[0]:-0},${w[1]:-0},${w[2]:-0}]; print('yes' if w[0] > 0 and w[1] != w[0] and abs((w[2]/w[1]) / (w[1]/w[0]) - 2) < 0.03 else '')" 2>/dev/null)" "${w[*]:-}"
check "…and draws no measure while doing it" "$(echo "$out" | grep -q '^  measure ' || echo yes)" "a measure was left"

# 5f — the gear the plan uses, counted by name (Scenario's self-filling list).
# A Light mark counts under its mark's name (Chevron); a library fixture and
# a grip piece by their own.
out=$(run gear "drop sym:tungsten-fresnel-1k 600 620; drop sym:tungsten-fresnel-1k 700 620; drop sym:generic-bounce 800 620; tool light; click 500 500; gear; gearlist")
check "the plan's gear is counted" "$(echo "$out" | grep '^gear:' | grep -qE 'Lights \| 2 × 1K Tungsten Fresnel.*Grip \| 1 × Bounce' && echo yes)" "$(echo "$out" | grep '^gear:')"
check "…a Light mark counts under its mark's name" "$(echo "$out" | grep '^gear:' | grep -q '1 × Chevron' && echo yes)" "$(echo "$out" | grep '^gear:')"
check "…and Copy › Gear List writes the same list" "$(echo "$out" | grep '^gearlist:' | grep -qE '1K Tungsten Fresnel.*Chevron|Chevron.*1K Tungsten Fresnel' && echo "$out" | grep '^gearlist:' | grep -q 'Bounce' && echo yes)" "$(echo "$out" | grep '^gearlist:')"

# 5c — the film's own pictures: listed by where they live, and laid as a photo
out=$(run pics "pictures; pictures 0 photo; report")
check "the project's pictures are offered" "$(echo "$out" | grep -qE '^pictures: .*=[1-9]' && echo yes)" "$(echo "$out" | grep '^pictures:')"
check "…and one lays on the plan as a photo" "$(echo "$out" | grep '^  image ' | grep -q 'role photo.*\[picked\]' && echo yes)" "$(echo "$out" | grep '^  image ')"

# 6 — a pasted group is its own group
out=$(run paste "drop camera 450 400; drop sym:tungsten-fresnel-1k 700 500; tool select; key a command; key g command; key c command; key v command; report")
groups=$(echo "$out" | grep -o 'group [a-z0-9-]*' | sort -u | wc -l | tr -d ' ')
check "a pasted group does not join the one it was copied from" "$([ "$groups" -ge 2 ] && echo yes)" "$groups groups"

# 7 — a whole room in one drag: one closed wall of four corners
out=$(run room "tool wall; down 250 250 shift; drag 400 350; drag 600 480; up 600 480; report")
n=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep "^  wall " | grep -c 'corners 4 closed')
check "a room is drawn in one drag" "$([ "$n" -ge 1 ] && echo yes)" "$(echo "$out" | grep '^  wall ')"

# 8 — a scanned room laid on the plan, then the whole plan copied to another scene
out=$(run room2 "room; report")
# Its walls come in joined, one closed room, as the Wall tool draws one (2026-10-17).
n=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep "^  wall " | grep -c 'closed')
check "a scanned room lays its walls on the plan, joined and closed" "$([ "$n" -ge 1 ] && echo yes)" "$(echo "$out" | awk '/^drive:/{n++} n==1' | grep "^  wall ")"
gone; sleep 1
SHOTLISTER_STAY=5 SHOTLISTER_DIAGRAMDRIVE="copyfrom 34; report" \
  "$APP" --project "$FILM" --screen "$SCREEN" --place diagram --scene 33 --snapshot "$WORK/copy.png" >"$WORK/copy.log" 2>&1
n=$(awk '/^drive:/{n++} n==1' "$WORK/copy.log" | grep -c "^  ")
check "a plan is copied from another scene" "$([ "$n" -ge 4 ] && echo yes)" "$n things on scene 33"
check "…and its cameras come loose from that scene's shots" "$(awk '/^drive:/{n++} n==1' "$WORK/copy.log" | grep '^  camera ' | grep -q ' shot ' || echo yes)" "still linked"

# 8b — a room's corner dragged on its own: the room stays one closed wall.
# Two walls drawn apart, the second from the first's end: dragging that
# corner carries the second along; ⌥ pulls the first free of it.
corners() { grep "^  wall " | python3 -c "
import sys,re
pts=set()
for l in sys.stdin:
    m=re.search(r'corners [0-9]+(?: closed)? \[([^]]*)\]', l)
    if m:
        for p in m.group(1).split(): pts.add(tuple(round(float(v),2) for v in p.split(',')))
print(len(pts))"; }
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"   # a clean scene: the rooms above left walls on it
out=$(run corner "tool wall; click 300 200; click 700 200; click 700 500; click 300 500; click 300 200; tool select; grab wallcorner 2 30 40; exact" 6)
check "a room's corner dragged keeps it one closed wall of four corners" "$(ex "$out" 1 | grep '^  wall ' | grep -q 'corners 4 closed' && [ "$(ex "$out" 1 | grep -c '^  wall ')" = 1 ] && echo yes)" "$(ex "$out" 1 | grep '^  wall ')"
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run cornerjoin "tool wall; click 300 200; click 600 200; key return; tool wall; click 600 200; click 600 450; key return; tool select; clickon 0; grab wallcorner 1 30 40; exact; key z command; grab wallcorner 1 30 40 option; exact" 8)
check "…a corner dragged carries the wall that meets it there" "$([ "$(ex "$out" 1 | corners)" = 3 ] && echo yes)" "$(ex "$out" 1 | corners) corners"
check "…and ⌥ pulls it free" "$([ "$(ex "$out" 2 | corners)" = 4 ] && echo yes)" "$(ex "$out" 2 | corners) corners"

# 8c — a door goes where its wall goes
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"   # a clean scene: 8b left walls on that line
out=$(run doorwall "tool wall; click 300 200; click 700 200; key return; tool door; click 500 206; tool select; click 350 200; down 350 200; drag 350 230; drag 350 260; up 350 260; report")
wy=$(echo "$out" | grep '^  wall ' | grep '\[picked\]' | grep -o 'at [^ ]*' | cut -d, -f2)
dy=$(echo "$out" | grep '^  door ' | head -1 | grep -o 'at [^ ]*' | cut -d, -f2)
check "a door rides with its wall" "$([ -n "$wy" ] && [ "$wy" = "$dy" ] && echo yes)" "wall at y $wy, door at y $dy"

# 8e — a door dragged onto a wall catches on it, slides along it, and comes off when pulled clear
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run doorsnap "tool wall; click 300 200; click 700 200; key return; tool door; click 500 420; tool select; report; haul 6 -212; report; haul 90 14; report; haul 0 240; report")
wy=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep '^  wall ' | head -1 | grep -o 'at [^ ]*' | cut -d, -f2)
d1=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  door ' | grep -o 'at [^ ]*')
d2=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep '^  door ')
d3=$(echo "$out" | awk '/^drive:/{n++} n==3' | grep '^  door ')
d4=$(echo "$out" | awk '/^drive:/{n++} n==4' | grep '^  door ')
y2=$(echo "$d2" | grep -o 'at [^ ]*' | cut -d, -f2); x2=$(echo "$d2" | grep -o 'at [^ ]*' | cut -d' ' -f2 | cut -d, -f1)
y3=$(echo "$d3" | grep -o 'at [^ ]*' | cut -d, -f2); x3=$(echo "$d3" | grep -o 'at [^ ]*' | cut -d' ' -f2 | cut -d, -f1)
y4=$(echo "$d4" | grep -o 'at [^ ]*' | cut -d, -f2)
check "a door dragged near a wall catches on its line" "$([ -n "$wy" ] && [ "$y2" = "$wy" ] && echo "$d2" | grep -qE 'rot (0|180) ' && echo yes)" "wall y $wy; was $d1; now $d2"
check "…slides along it without coming off" "$([ -n "$y3" ] && [ "$y3" = "$wy" ] && [ "$x3" != "$x2" ] && echo yes)" "$d3"
check "…and comes off when pulled well clear" "$([ -n "$y4" ] && [ "$y4" != "$wy" ] && echo yes)" "$d4"

# 8f — (removed 2026-10-15) steps, moves and ghosts: "Add Move To", the beats
# and a step's knob were taken out on purpose on 2026-10-03 (`dfabb7dc`,
# `28dfeb24`: no moves or beats; the code is kept in archive/picture-style).
# Their checks went with them. Taking moves out leaves a camera or a person
# as a single piece, which the blocks above and below already exercise.

# 8g — a click picks a camera and opens nothing (his note, 2026-09-28: the
# card "constantly gets in the way"). The card itself is gone since
# 2026-10-04 (`b245e8e9`: words are typed in Details, no pop-up box), so
# Return opens Details, and `pop:` only ever says "none".
out=$(run pop "tool camera; down 620 420; drag 660 400; up 660 400; tool select; report; key return; report; pan 120 40; report; keys 2 command control; report; showall; report; tool cast; click 400 300; tool select; report")
pop() { echo "$out" | awk -v k="$1" '/^drive:/{n++} n==k' | grep '^pop:'; }
check "a picked camera opens no card and no side panel" "$(pop 1 | grep -q 'pop: none; panel hidden' && echo yes)" "$(pop 1)"
check "…Return opens Details, not a card" "$(pop 2 | grep -q 'pop: none; panel shown' && echo yes)" "$(pop 2)"
check "…Details stays open when the plan pans" "$(pop 3 | grep -q 'pop: none; panel shown' && echo yes)" "$(pop 3)"
check "…⌃⌘2 shuts it, and Show All brings it back" "$(pop 4 | grep -q 'pop: none; panel hidden' && pop 5 | grep -q 'pop: none; panel shown' && echo yes)" "$(pop 4) / $(pop 5)"
check "anything else picked keeps the side panel" "$(pop 6 | grep -q 'pop: none; panel shown' && echo yes)" "$(pop 6)"

# 8d — every drawing tool leaves its piece. (Draw is clicked out and
# double-clicked to finish; the Note tool makes Words now.)
out=$(run tools "tool track; down 200 600; drag 300 600; drag 400 600; up 400 600; tool road; down 200 660; drag 300 660; drag 400 660; up 400 660; tool arrow; down 500 600; drag 550 610; drag 600 620; up 600 620; tool measure; down 500 660; drag 600 660; drag 700 660; up 700 660; tool shape; down 750 600; drag 800 640; drag 850 680; up 850 680; tool cable; click 500 720; click 600 740; click 650 780; key return; tool note; click 760 740; tool text; click 820 780; settext Hello; tool pen; wait 0.5; click 200 700; click 260 750; click 300 700; dbl 340 740; report" 14)
for k in track road arrow measure shape stroke cable; do
  check "the $k tool draws a $k" "$(echo "$out" | awk '/^drive:/{n++} n==1' | grep -q "^  $k " && echo yes)" "no $k: $(echo "$out" | grep '^drive:')"
done
check "the note tool (N) makes Words, and the text tool makes Words" "$([ "$(echo "$out" | awk '/^drive:/{n++} n==1' | grep -c '^  text ')" = 2 ] && echo yes)" "$(echo "$out" | awk '/^drive:/{n++} n==1' | grep '^  text ')"

# 8e — the compass turned by hand, and kept as one step
out=$(run compass "setting sun true; compass 120 40; report; key z command; report")
n1=$(echo "$out" | grep '^sun:' | sed -n 1p | sed 's/.* north \([0-9]*\).*/\1/')
n2=$(echo "$out" | grep '^sun:' | sed -n 2p | sed 's/.* north \([0-9]*\).*/\1/')
check "the compass turns north when dragged" "$([ -n "$n1" ] && [ "$n1" != 0 ] && echo yes)" "north $n1"
check "…and ⌘Z turns it back in one step" "$([ "$n2" = 0 ] && echo yes)" "north $n2"

# 8h — north turns the compass and the sun; the plan stays put (2026-09-29)
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run northup "tool wall; click 300 200; click 700 200; key return; tool select; setting sun true; report; setting north 90; report")
c1=$(echo "$out" | grep '^view:' | sed -n 1p | sed 's/.* compass \([^ ]*\).*/\1/')
c2=$(echo "$out" | grep '^view:' | sed -n 2p | sed 's/.* compass \([^ ]*\).*/\1/')
w2=$(echo "$out" | grep '^view:' | sed -n 2p | sed 's/.* wall //')
# His note, 2026-09-29, taking back 2026-09-27: turning north turns the
# compass and the sun, and the set stays put.
check "turning north leaves the plan where it stands" "$([ -n "$c1" ] && [ "$c1" = "$c2" ] && echo "$out" | grep '^view:' | sed -n 2p | grep -qE '^view: turn -?0 ' && echo yes)" "$(echo "$out" | grep '^view:' | sed -n 2p)"
check "…so a wall that ran across still runs across" "$(echo "$w2" | awk '{split($1,a,",");split($2,b,","); d=a[2]-b[2]; if (d<0) d=-d; print (d<3 && a[1]!=b[1]) ? "yes" : "no"}')" "wall $w2"

# 8k — his notes of 2026-09-29. Walls go down one at a time; Delete takes
# what is picked with the keyboard anywhere but a text field; ⌘-click adds
# and takes away; Cast and Camera offer their choices. (Turn To is gone with
# the moves.)
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run notes0929 "tool wall; click 300 200; report; click 700 200; report; key escape; report; choose cast Person; click 500 520; report; choose camera 34B; click 760 420; report; choices camera; clickon 1; clickon 2 command; report; clickon 1 command; report; focus away; press delete; report")
blk() { echo "$out" | awk -v n=$1 '/^drive:/{k++} k==n'; }
check "a wall stands as soon as its second corner is clicked" "$(blk 1 | grep -q '^drive: 0 els' && blk 2 | grep -q '^drive: 1 els' && echo yes)" "$(blk 2 | head -1)"
check "…and Esc stops drawing and goes back to the arrow" "$(blk 3 | grep -q '1 els; picked [01]; tool select' && echo yes)" "$(blk 3 | head -1)"
check "Cast's Person, chosen, goes down with one click" "$(blk 4 | grep -q '^  cast ' && blk 4 | grep -q 'tool select' && echo yes)" "$(blk 4 | head -1)"
check "Camera's 34B puts down a camera for that shot" "$(blk 5 | grep '^  camera ' | grep -q ' shot ' && echo "$out" | grep -q '^choices: .*✓34B' && echo yes)" "$(blk 5 | grep '^  camera ')"
check "⌘-click adds to the pick" "$(blk 6 | grep -q 'picked 2' && echo yes)" "$(blk 6 | head -1)"
check "…and ⌘-click takes away" "$(blk 7 | grep -q 'picked 1' && echo yes)" "$(blk 7 | head -1)"
gone_id=$(blk 7 | grep '\[picked\]' | head -1 | awk '{print $2}')
check "Delete takes the pick with the keyboard off the plan" "$(echo "$out" | grep -q '^focus: AppKitWindow' && [ -n "$gone_id" ] && ! blk 8 | grep -q "^  [a-z]* $gone_id " && [ "$(blk 8 | grep -c '^  ')" = "$(( $(blk 7 | grep -c '^  ') - 1 ))" ] && echo yes)" "$(blk 7 | head -1) → $(blk 8 | head -1)"

# 8i — the sun's rays: off unless asked for, and kept when turned on. (How
# they fall needs the scene's address, which this film has not got: the
# engine's own tests draw that.)
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run rays "setting sun true; report; setting sun_rays true; report")
r1=$(echo "$out" | grep '^sun:' | sed -n 1p | sed 's/.* rays \([a-z]*\).*/\1/')
r2=$(echo "$out" | grep '^sun:' | sed -n 2p | sed 's/.* rays \([a-z]*\).*/\1/')
check "the sun shows without rays at first" "$([ "$r1" = no ] && echo yes)" "rays $r1"
check "…and the Rays switch keeps them on" "$([ "$r2" = yes ] && echo yes)" "rays $r2"

# 8j — the sun stands still (his note, 2026-09-28: "I can chase it with my
# items"): a person walked right up to it and past, the sun painted in the
# same place every step; then a new hour, and the sun lands in the clear —
# not under the foot bar or the zoom. The scene is given an address first
# (the one run here that carries flags of its own).
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
gone; sleep 1
SHOTLISTER_STAY=2 "$APP" --project "$FILM" --screen "$SCREEN" --addlocation Yard --setlocation latitude 34.05 \
  --setlocation longitude -118.25 --linkscene 34 --snapshot "$WORK/yard.png" >/dev/null 2>&1
out=$(KEEPFILM=1 run sunstill "tool wall; click 450 250; click 800 250; click 800 500; click 450 500; click 450 250; tool cast; castas Anna; click 500 380; tool select; key escape; setting sun true; setting sun_date 2026-09-22; setting sun_time 17:30; pickkind cast; sunwatch -400 0; zoom 2; setting sun_time 12:00; report" 10)
spots=$(echo "$out" | grep '^sunwatch:' | sed 's/.* sun //' | sort -u)
check "the sun is painted in one place while a person is hauled up to it and past" "$([ "$(echo "$out" | grep -c '^sunwatch:')" = 10 ] && [ "$(echo "$spots" | wc -l | tr -d ' ')" = 1 ] && [ "$spots" != none ] && echo yes)" "$(echo "$out" | grep '^sunwatch:' | tr '\n' ' ')"
check "…and the person really went" "$(echo "$out" | grep '^  cast ' | tail -1 | grep -qE 'at -' && echo yes)" "$(echo "$out" | grep '^  cast ' | tail -1)"
disc=$(echo "$out" | grep '^sundisc:' | tail -1)
check "a new hour keeps the sun clear of the bars" "$(echo "$disc" | python3 -c "
import sys,re
m=re.search(r'at (-?\d+),(-?\d+) canvas (\d+)x(\d+) right (\d+)', sys.stdin.read())
x,y,w,h,r=map(int,m.groups()) if m else (0,0,0,0,0)
print('yes' if m and 40<=x<=w-r-40 and 90<=y<=h-120 else '')")" "$disc"

# 12 — the chrome, Scenario's way (Lane A, 2026-09-28): Details and Gear as
# full-height sidebars on keys, the picked piece's action bar, Show by kind,
# and Present. `SHOTLISTER_SNAPS=<dir>` keeps each run's picture.
keep() { if [ -n "${SHOTLISTER_SNAPS:-}" ]; then cp "$WORK/$1.png" "$SHOTLISTER_SNAPS/" 2>/dev/null; fi; true; }
chrome() { echo "$1" | grep '^chrome:' | sed -n "${2}p"; }
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"

# 12a — ⌃⌘1 Layers and ⌃⌘2 Details, open and shut. Details stays closed until
# asked for, even with something picked (2026-10-04, `d122f384`); the Gear tab
# and ⌃⌘3 are gone (`c2077644`: Copy › Gear List writes the list instead,
# checked with the gear above).
out=$(run sidebars "showkind all on; drop sym:tungsten-fresnel-1k 450 620; pickkind light; chrome; keys 1 command control; chrome; keys 3 command control; chrome; keys 2 command control; chrome; keys 2 command control; chrome" 8)
keep sidebars
check "Layers and Details start shut, even with a piece picked" "$(chrome "$out" 1 | grep -q 'layers false details false gear false' && chrome "$out" 1 | grep -q 'picked light' && echo yes)" "$(chrome "$out" 1)"
check "…⌃⌘1 opens Layers" "$(chrome "$out" 2 | grep -q 'layers true details false' && echo yes)" "$(chrome "$out" 2)"
check "…⌃⌘3 opens nothing now: there is no Gear tab" "$(chrome "$out" 3 | grep -q 'layers true details false gear false' && echo yes)" "$(chrome "$out" 3)"
check "…⌃⌘2 opens Details, and again shuts it" "$(chrome "$out" 4 | grep -q 'details true' && chrome "$out" 5 | grep -q 'details false' && echo yes)" "$(chrome "$out" 4) / $(chrome "$out" 5)"

# 12a2 — Details, in sight and staying open (his note, 2026-10-17: "the detail
# panel needs to be easier to pull up"). ⌥⌘I opens it; nothing picked, it stays
# with No Selection; the next pick shows there; ⌥⌘I again shuts it.
out=$(run detailsstay "drop sym:tungsten-fresnel-1k 450 620; pickkind light; press i command option; chrome; key escape; chrome; pickkind light; chrome; press i command option; chrome" 8)
keep detailsstay
check "⌥⌘I opens Details on the picked piece" "$(chrome "$out" 1 | grep -q 'details true .*right details' && echo yes)" "$(chrome "$out" 1)"
check "…nothing picked, it stays open" "$(chrome "$out" 2 | grep -q 'right details' && ! chrome "$out" 2 | grep -q 'picked ' && echo yes)" "$(chrome "$out" 2)"
check "…the next pick is shown in it, and ⌥⌘I shuts it" "$(chrome "$out" 3 | grep -q 'right details' && chrome "$out" 3 | grep -q 'picked light' && chrome "$out" 4 | grep -q 'details false .*right -' && echo yes)" "$(chrome "$out" 3) / $(chrome "$out" 4)"

# 12b — the action bar on a light. A light's bar now offers Symbol, Name,
# Count, Note, Gel and Down (no Colour, Size or Dimmer buttons, and no Beam:
# lamps throw no light for now, his call 2026-10-01); Dimmer, Size and Colour
# are still the light's own settings (`act` sets them as Details does), kept
# in the film, with Lock, Duplicate and Hide.
out=$(run actions "drop sym:tungsten-fresnel-1k 450 620; pickkind light; chrome; act dim 40; act size 150; act colour 0A6CE8; chrome; act lock; chrome; act lock; act duplicate; report; act hide; report" 8)
keep actions
check "a light's bar offers Symbol, Name, Count, Note, Gel and Down, and no Beam" "$(chrome "$out" 1 | grep -q 'actions \[symbol,lampname,count,note,gel,down,more\] picked light' && echo yes)" "$(chrome "$out" 1)"
w1=$(chrome "$out" 1 | sed 's/.* size \([0-9.]*\)x.*/\1/'); w2=$(chrome "$out" 2 | sed 's/.* size \([0-9.]*\)x.*/\1/')
check "…Dimmer, Size and Colour change it" "$(chrome "$out" 2 | grep -q 'colour #0A6CE8 .* beam on dim 40 ' && python3 -c "print('yes' if abs(${w2:-0}/${w1:-1} - 1.5) < 0.02 else '')" && true)" "$(chrome "$out" 2)"
check "…Lock locks it" "$(chrome "$out" 3 | grep -q 'locked yes' && echo yes)" "$(chrome "$out" 3)"
n=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep -c '^  light ')
check "…Duplicate makes a second" "$([ "$n" = 2 ] && echo yes)" "$n lights"
check "…Hide hides it and lets go" "$(echo "$out" | awk '/^drive:/{n++} n==2' | grep -q '^drive: 2 els; picked 0' && echo yes)" "$(echo "$out" | grep '^drive:' | tail -1)"
out=$(KEEPFILM=1 run actions2 "pick 0; chrome; tool camera; down 400 520; drag 430 500; up 430 500; chrome; act lens 85; chrome; tool text; click 600 560; settext Hello; chrome; act size 24; chrome" 8)
keep actions2
check "…the Dimmer is kept in the film" "$(chrome "$out" 1 | grep -q 'dim 40 ' && echo yes)" "$(chrome "$out" 1)"
check "a camera's bar offers Shot, Camera and Lens, and Lens sets its shot's lens" "$(chrome "$out" 2 | grep -q 'actions \[shot,camera,lens,name,piecenote,more\] picked camera' && chrome "$out" 3 | grep -q 'focal 85' && echo yes)" "$(chrome "$out" 2) / $(chrome "$out" 3)"
check "words' Size is their point size" "$(chrome "$out" 4 | grep -q 'picked text' && chrome "$out" 5 | grep -q 'pt 24 ' && echo yes)" "$(chrome "$out" 5)"

# 12c — Show by kind: a hidden kind is neither drawn nor clicked, and the
# choice is this Mac's, not the film's. (Names and Cones are no longer kinds
# here: View › Labels and View › Cones are one switch each, saved with the
# plan and printed, Back to Paper Batch 2.)
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run show "showkind all on; tool camera; down 400 400; up 400 400; tool cast; castas MAYA; click 640 400; tool light; arm tungsten-fresnel-1k; click 520 620; key escape; key escape; chrome; showkind cameras off; chrome; click 400 400; report; showkind cameras on; click 400 400; report; showkind lights off; showkind walls off; showkind cast off; key escape; chrome" 10)
keep show
a=$(chrome "$out" 1 | grep -o 'shapes [0-9]*/' | tr -dc 0-9); b=$(chrome "$out" 2 | grep -o 'shapes [0-9]*/' | tr -dc 0-9)
check "Show: switching Cameras off draws less" "$([ -n "$a" ] && [ -n "$b" ] && [ "$b" -lt "$a" ] && chrome "$out" 2 | grep -q 'unseen \[cameras\]' && echo yes)" "$a → $b"
check "…a hidden camera cannot be clicked" "$(echo "$out" | awk '/^drive:/{n++} n==1' | grep -q '^drive: 3 els; picked 0' && echo yes)" "$(echo "$out" | grep '^drive:' | head -1)"
check "…and shown again, it can" "$(echo "$out" | awk '/^drive:/{n++} n==2' | grep -q '^  camera .*\[picked\]' && echo yes)" "$(echo "$out" | grep '^drive:' | tail -1)"
out=$(run show2 "chrome; showkind all on; chrome" 4)
check "…the choice stays on this Mac between launches" "$(chrome "$out" 1 | grep -q 'unseen \[cast,lights,walls\]' && chrome "$out" 2 | grep -q 'unseen \[\]' && echo yes)" "$(chrome "$out" 1)"

# 12d — Present: ⌘F hides every control and fits the plan; Esc comes back
out=$(run present "tool select; chrome; keys f command; wait 1; chrome; keys escape; wait 0.5; chrome; keys f command" 8)
keep present
s1=$(chrome "$out" 1 | grep -o 'scale [0-9.]*'); s3=$(chrome "$out" 3 | grep -o 'scale [0-9.]*')
check "⌘F presents the plan, fitted" "$(chrome "$out" 2 | grep -q 'presenting true fitted true' && echo yes)" "$(chrome "$out" 2)"
check "…and Esc comes back to the view it left" "$(chrome "$out" 3 | grep -q 'presenting false' && [ "$s1" = "$s3" ] && echo yes)" "$s1 → $s3"

# 12e — the layout of design/24 (2026-09-28): Layers is a tab of the left
# sidebar and names every piece by its own name — a scanned room's pieces
# too, which the pack's drawings hide from the library; Details is the right
# sidebar, shut until asked for (the Gear tab is gone); the foot bar names
# what is picked; Favorites opens its slots under the toolbar
out=$(run layout "room; tool select; sidetab layers; layers; pickkind set; chrome; keys 3 command control; chrome; keys 2 command control; chrome; pick; chrome; keys 1 command control; chrome; favorites on; chrome" 8)
keep layout
l=$(echo "$out" | grep '^layers:')
check "Layers names a scanned room's pieces — Table, Chair, Bed — never Set Piece" "$(echo "$l" | grep -q 'Table' && echo "$l" | grep -q 'Bed' && ! echo "$l" | grep -q 'Set Piece' && echo yes)" "$l"
check "…picked, the foot bar says its name, and Details stays shut" "$(chrome "$out" 1 | grep -q 'tab layers right - favorites false bar "Bed"' && echo yes)" "$(chrome "$out" 1)"
check "…⌃⌘3 brings nothing (no Gear tab); ⌃⌘2 opens Details beside Layers" "$(chrome "$out" 2 | grep -q 'right - ' && chrome "$out" 3 | grep -q 'tab layers right details' && echo yes)" "$(chrome "$out" 2) / $(chrome "$out" 3)"
# Asked for, Details stays with nothing picked and says No Selection (2026-10-17).
check "…nothing picked, Details stays open with nothing in it" "$(chrome "$out" 4 | grep -q 'right details' && ! chrome "$out" 4 | grep -q 'picked ' && echo yes)" "$(chrome "$out" 4)"
check "…⌃⌘1 on Layers goes back to the scenes, and Favorites opens" "$(chrome "$out" 5 | grep -q 'tab scenes' && chrome "$out" 6 | grep -q 'favorites true' && echo yes)" "$(chrome "$out" 5) / $(chrome "$out" 6)"

# 9 — Export… as a picture
out=$(run png "png $WORK/plan.png")
check "Export… makes a picture" "$([ -s "$WORK/plan.png" ] && echo yes)" "no file"

# 12 — frames and gels (Lane B, 2026-09-28). Each run starts from an empty
# plan: a Fresnel facing east at 400,600 reaches 4.5 m, and a frame 160 pt
# east of it stands 2.7 m into its beam.
#
# "Each run starts from an empty plan" needs the *film* reset, not just the
# "clear" drive string below. The diagram fits its view to whatever the plan
# holds the moment its window first draws — before a single drive command
# has run — so a film still carrying the camera, cast member and light that
# 12c's "show" check left behind (never deleted, only hidden and shown again)
# starts every check in this section at the wrong zoom, and every click and
# move in it lands somewhere other than the screen position it names. Reset
# here once, the same as before every other section that wants a clean film.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
clear="tool select; key a command; key delete; beamsall on"
# A library fixture (`drop`), not the Light tool's mark: these checks are about
# a real unit's name, gels and beam, which a bare Light mark has none of.
lamp="drop sym:tungsten-fresnel-1k 400 600; pickkind light"
out=$(run frametool "$clear; tool frame; click 400 300; report; move 600 300; key f; report")
f1=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep 'sym frame')
f2=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep -c 'sym frame')
# His ruling, 2026-09-30: a new frame lies flat, like Scenario's.
check "the Frame tool puts a frame down, 8 ft square and lying flat" "$(echo "$f1" | grep -q 'size 2.44x2.44.*tilt 0 ' && echo yes)" "$f1"
check "…and F puts another at the pointer" "$([ "$f2" = 2 ] && echo "$out" | awk '/^drive:/{n++} n==2' | grep 'sym frame' | tail -1 | grep -qE 'at 0\.[0-9]+|at [1-9]' && echo yes)" "$(echo "$out" | awk '/^drive:/{n++} n==2' | grep 'sym frame')"
# **Lamps throw no light for now** (his call, 2026-10-01): with Light Beams
# on, a lamp draws no beam, and a frame standing in front of it — a bounce
# it is aimed at included — throws none either. The beam checks of
# 2026-09-28 come back with the beams (`render::LAMP_BEAMS`).
out=$(run framecut "$clear; $lamp; beams; tool frame; click 560 520; frameset tilt 90; frameset material bounce-white; pickkind frame; aimat light; tool select; beams")
check "with Light Beams on, a lamp and the bounce it is aimed at throw no beam" "$(echo "$out" | grep -q '^beams: tungsten-fresnel-1k' && ! echo "$out" | grep '^beams:' | grep -qv ' n 0 ' && echo yes)" "$(echo "$out" | grep '^beams:')"
# A new lamp has no label until one is typed (2026-10-15): this one is given its unit's.
out=$(run gels "$clear; $lamp; update {\"lamp_name\":\"1K Tungsten Fresnel\"}; beams; gels cto-half nd3; beams; report")
before=$(echo "$out" | grep '^beams: tungsten-fresnel-1k' | head -1 | sed 's/.*fills \([^/]*\).*/\1/')
after=$(echo "$out" | grep '^beams: tungsten-fresnel-1k' | tail -1)
check "gels ride under the light's name, a line of their own" "$(echo "$after" | grep -q 'label "1K Tungsten Fresnel / ½ CTO · ND .3"' && echo yes)" "$after"
check "…and are kept on it" "$(echo "$out" | grep 'sym tungsten-fresnel-1k' | grep -q 'gels cto-half,nd3' && echo yes)" "$(echo "$out" | grep 'sym generic')"
out=$(run framelie "$clear; tool frame; click 500 450; frameset tilt 0; frameset pipe speed-rail; frameset grid 40; frameset material silk; gels cto-full; report")
check "a frame laid flat is as deep as it is tall, and keeps its pipe, grid and gel" "$(echo "$out" | grep 'sym frame' | grep -q 'size 2.44x2.44 sym frame gels cto-full material silk pipe speed-rail grid 40 tilt 0 ' && echo yes)" "$(echo "$out" | grep 'sym frame')"

# 12f — frames as good as Scenario's (2026-09-30): the tilt knob stands a
# flat frame up in 5° steps; with Snap on a frame's size keeps to whole
# feet; the new skins, Black Pipe and the 45° grid are kept; the frame's
# bar offers Size, Material, Note and Fade (the Frame Type and Grid buttons
# left the bar with Back to Paper).
out=$(run frametilt "$clear; tool frame; click 500 450; tool select; click 500 450; grab tilt 0 36 0; report; frameset h 2.9; frameset material gold-lame; frameset pipe black-pipe; frameset grid 45; report; chrome")
t1=$(echo "$out" | awk '/^drive:/{n++} n==1' | grep 'sym frame')
tilt=$(echo "$t1" | sed 's/.* tilt \([0-9]*\) .*/\1/')
check "the tilt knob stands a flat frame up, in 5° steps" "$(python3 -c "print('yes' if 30 <= int('$tilt') <= 80 and int('$tilt') % 5 == 0 else '')" 2>/dev/null)" "$t1"
t2=$(echo "$out" | awk '/^drive:/{n++} n==2' | grep 'sym frame')
check "…a frame sized with Snap on is whole feet (2.9 m → 10 ft)" "$(echo "$t2" | grep -q 'x3.05 sym frame' && echo yes)" "$t2"
check "…and keeps Gold Lamé, Black Pipe and a 45° grid" "$(echo "$t2" | grep -q 'material gold-lame pipe black-pipe grid 45' && echo yes)" "$t2"
check "…its bar offers Size, Material, Note and Fade" "$(echo "$out" | grep '^chrome' | grep -q 'actions \[framename,framenote,framesize,material,fade,more\] picked light' && echo yes)" "$(echo "$out" | grep '^chrome' | head -3)"
# His note, 2026-10-01: standing, the turning and tilt knobs sat on each
# other. The tilt knob rides the raised edge off one side, the turning knob
# is off the other — far apart lying, leaning and standing; and the tilt
# knob still stands it up when dragged toward the middle.
out=$(run frameknobs "$clear; tool frame; click 500 450; tool select; click 500 450; handles; frameset tilt 45; handles; frameset tilt 90; handles; grab tilt 0 -60 0; report")
keep frameknobs
apart=$(echo "$out" | grep '^handles:' | python3 -c "
import sys, re, math
d = []
for l in sys.stdin:
    r = re.search(r'rotate0=(-?\d+),(-?\d+)', l); t = re.search(r'tilt0=(-?\d+),(-?\d+)', l)
    if r and t: d.append(round(math.hypot(int(r[1]) - int(t[1]), int(r[2]) - int(t[2]))))
print(' '.join(map(str, d)))")
check "a frame's turning and tilt knobs are far apart at 0°, 45° and 90°" "$(python3 -c "d=[int(x) for x in '$apart'.split()]; print('yes' if len(d) == 3 and min(d) > 60 else '')")" "apart $apart / $(echo "$out" | grep '^handles:')"
check "…and dragged from upright, the tilt knob lays it back" "$(echo "$out" | grep 'sym frame' | sed 's/.* tilt \([0-9]*\) .*/\1/' | python3 -c "import sys; t=sys.stdin.read().strip(); print('yes' if t and int(t) < 90 else '')")" "$(echo "$out" | grep 'sym frame')"

# 12g — the libraries (2026-09-30): Light holds lamps only, Grip frames,
# rags, flags, stands and lifts and no lamps, Set the rest; search knows what
# a crew calls things; a lamp lands facing up the screen, the way its library
# picture shows it. (Grip lost its toolbar button and its Q key when the tools
# became seven named ones per layer, 2026-10-04: the library is still there
# for a drop or the drive's `tool grip`.)
out=$(run libraries "$clear; key q; report; libsays light; libsays grip; libsays set; libsays light 4k par; libsays light kino bare; libsays grip c-stand; libsays light skypanel s60; drop sym:fso-arri-m18 420 620; tool light; click 540 620; report")
check "Q picks no tool now: Grip is not one of the named tools" "$(echo "$out" | awk '/^drive:/{n++} n==1' | grep -q '^drive: 0 els; picked 0; tool select' && echo yes)" "$(echo "$out" | grep '^drive:' | head -1)"
light=$(echo "$out" | grep '^library: light ' | head -1); grip=$(echo "$out" | grep '^library: grip ' | head -1)
# (A lamp seen from behind — a Kino's end, a Diva's back — is a lamp too,
# giving no light: a handful at most.)
check "the Light library is lamps only" "$(echo "$light" | python3 -c "import sys,re; m=re.search(r'light (\d+) lamps (\d+)', sys.stdin.read()); print('yes' if m and int(m.group(1)) - int(m.group(2)) <= 10 and int(m.group(1))>200 else '')")" "$light"
check "the Grip library has grip and no lamps" "$(echo "$grip" | grep -q 'lamps 0 kinds Frames & Rags,Boards & Cards,Rolls,Stands & Rigging,Lifts' && echo yes)" "$grip"
check "search finds a 4K PAR by its nickname, and an M40" "$(echo "$out" | grep '^library: light .* found' | sed -n 2p | grep -q '4K HMI PAR.*Arri M40\|Arri M40.*4K HMI PAR' && echo yes)" "$(echo "$out" | grep '^library: light' | sed -n 2p)"
check "…kino finds the fluorescents, c-stand the stand, skypanel s60 the S60" "$(echo "$out" | grep -q 'found [1-9][0-9]*: .*Kino Bare' && echo "$out" | grep '^library: grip' | tail -1 | grep -q 'C-Stand' && echo "$out" | grep -q 'found [1-9][0-9]*: .*Arri S60c' && echo yes)" "$(echo "$out" | grep '^library:' | tail -4)"
check "a library fixture lands facing up the screen, as its tile shows" "$(echo "$out" | grep 'sym fso-arri-m18' | grep -q 'rot 270' && echo yes)" "$(echo "$out" | grep 'sym fso-arri-m18')"
check "…and so does a Light mark" "$(echo "$out" | grep '^  light ' | grep -v 'sym fso-arri-m18' | grep -q 'rot 270' && echo yes)" "$(echo "$out" | grep '^  light ')"

# 13 — words and shots (Lane D, 2026-09-28): a name dragged by itself,
# sized, un-bolded and hidden (a library fixture's, with a camera beside it:
# the first piece alone on a fresh plan is drawn before its paper has fitted
# and shows no name yet); the Shots tab placing and taking away a
# shot's camera; a camera's frame laid on the plan, dragged, sized, and
# carried along when the camera moves.
nm() { echo "$1" | grep "^names: $2" | sed -n "${3}p"; }
field() { echo "$1" | sed "s/.* $2 \([^ ]*\).*/\1/"; }
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run names "tool select; key a command; key delete; drop camera 700 400; drop sym:fso-arri-m18 450 620; pickkind light; update {\"lamp_name\":\"Arri M18\"}; names; namedrag light 60 40; names; report; name size 14; name bold off; names; name hide; names; name show; names" 8)
keep names
n1=$(nm "$out" light 1); n2=$(nm "$out" light 2); n3=$(nm "$out" light 3); n4=$(nm "$out" light 4)
d1=$(field "$n1" drawn); d2=$(field "$n2" drawn)
check "a light's name drags by itself" "$(python3 -c "
a=[float(v) for v in '$d1'.split(',')]; b=[float(v) for v in '$d2'.split(',')]
print('yes' if abs(b[0]-a[0]-60)<3 and abs(b[1]-a[1]-40)<3 else '')" 2>/dev/null)" "$d1 → $d2"
check "…the offset is kept on the light, which is picked" "$(echo "$out" | grep '^  light ' | grep -q '\[picked\]' && [ "$(field "$n2" dx)" != 0.00 ] && echo yes)" "$(echo "$out" | grep '^  light ') / $n2"
check "…Name Size and Bold are kept on it" "$(echo "$n3" | grep -q 'size 14 bold no hidden no' && echo yes)" "$n3"
check "…Hide Name takes the name off the plan, Show Name brings it back" "$(echo "$n4" | grep -q 'hidden yes drawn none' && nm "$out" light 5 | grep -q 'hidden no drawn [0-9]' && echo yes)" "$n4"

# 13b — where names land (2026-10-01): an M18 and an S60c 60 cm apart, a
# camera and two people close by — no name on another; every name drawn on
# the paper itself (no patch behind it any more), in its own ink: a light's
# film-light red, a person's plain ink, a camera in its colour; a camera's
# name drags by itself and a thin line ties it back; Return opens a light's
# Note on the plan, empty (its Name is typed on the bar, 2026-10-05), and Esc
# leaves it be.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run namespots "tool select; key a command; key delete; drop sym:fso-arri-m18 490 360; update {\"lamp_name\":\"Arri M18\"}; drop sym:fso-arri-s60c 527 360; update {\"lamp_name\":\"Arri S60c\"}; drop camera 450 560; tool cast; castas MAYA; click 485 560; key escape; key escape; tool cast; castas JOHN; click 522 560; tool select; key escape; names; namedrag camera 70 60; names; pickkind light; press return; renaming; type Key Light; renaming; press return; renaming; names; pickkind light; press return; type Junk; press escape; renaming; names" 10)
keep namespots
first=$(echo "$out" | grep '^names:' | head -5)
check "five names close together, none on another" "$(echo "$first" | python3 -c "
import sys, re
b = [tuple(map(float, m.group(1).split(','))) for m in re.finditer(r'box ([0-9.,-]+)', sys.stdin.read())]
ok = len(b) == 5 and all(a[2] <= c[0] + 1 or c[2] <= a[0] + 1 or a[3] <= c[1] + 1 or c[3] <= a[1] + 1 for i, a in enumerate(b) for c in b[i+1:])
print('yes' if ok else '')")" "$first"
check "…each drawn on the paper in its own ink — lights red, people plain, a camera in its colour" "$([ "$(echo "$first" | grep -c 'patch no')" = 5 ] && [ "$(echo "$first" | grep '^names: light' | grep -c 'ink added ')" = 2 ] && [ "$(echo "$first" | grep '^names: cast' | grep -c 'ink ink ')" = 2 ] && echo "$first" | grep '^names: camera' | grep -q 'ink #' && echo yes)" "$first"
c1=$(echo "$out" | grep '^names: camera' | sed -n 1p); c2=$(echo "$out" | grep '^names: camera' | sed -n 2p)
moved=$(python3 -c "
a=[float(v) for v in '$(field "$c1" drawn)'.split(',')]; b=[float(v) for v in '$(field "$c2" drawn)'.split(',')]
print('yes' if abs(b[0]-a[0]-70)<3 and abs(b[1]-a[1]-60)<3 else '')" 2>/dev/null)
check "a camera's name drags by itself, tied back by a thin line" "$([ "$moved" = yes ] && echo "$c1" | grep -q 'tie no' && echo "$c2" | grep -q 'tie yes' && echo yes)" "$c1 → $c2"
r1=$(echo "$out" | grep '^typing:' | sed -n 1p); r3=$(echo "$out" | grep '^typing:' | sed -n 3p)
check "Return opens a light's Note on the plan, empty" "$(echo "$r1" | grep -qE '^typing: [0-9]+ note field "" ' && echo yes)" "$r1"
check "…typing fills it and Return keeps it" "$(echo "$r3" | grep -q '^typing: none' && echo "$out" | grep '^names: light' | sed -n 5p | grep -qi 'KEY LIGHT' && echo yes)" "$r3 / $(echo "$out" | grep '^names: light' | sed -n 5p)"
check "…Esc leaves it as it was" "$(echo "$out" | grep '^typing:' | sed -n 4p | grep -q '^typing: none' && echo "$out" | grep '^names: light' | sed -n 7p | grep -qi 'KEY LIGHT' && ! echo "$out" | grep '^names: light' | sed -n 7p | grep -q JUNK && echo yes)" "$(echo "$out" | grep '^names: light' | sed -n 7p)"

# 13c — labels are what he types (his call, 2026-10-15): a lamp put down has
# none; a label typed on one of two mirrorland is that lamp's alone; the
# legend has a line per label and the unlabelled on a faint line; Name This
# One is gone from a lamp's menu.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run labels "tool select; key a command; key delete; drop camera 700 300; drop sym:fso-arri-m18 400 560; tool light; click 520 560; click 640 560; key escape; tool select; names; click 520 560; typename; type Key Light; press return; names; menuat 520 560; report" 10)
keep labels
first=$(echo "$out" | grep '^names: light' | head -3)
check "a lamp put down, from the library or as a mark, has no label" "$([ "$(echo "$first" | grep -c 'drawn none')" = 3 ] && echo yes)" "$first"
after=$(echo "$out" | grep '^names: light' | sed -n 4,6p)
check "…a label typed on one of two mirrorland is that lamp's alone" "$([ "$(echo "$after" | grep -c 'drawn none')" = 2 ] && echo "$out" | grep -c 'lamp_name Key Light' | grep -q '^1$' && echo yes)" "$after / $(echo "$out" | grep 'lamp_name' | tail -3)"
check "…and Name This One is gone from its menu" "$(echo "$out" | grep -q '^menu:' && ! echo "$out" | grep '^menu:' | grep -q 'Name This One' && echo yes)" "$(echo "$out" | grep '^menu:' | head -1)"

# 13d — drawing on a photo (his ask, 2026-10-15): Draw on Photo, marks of
# every kind pinned to it, the perspective helper, Delete takes a mark (never
# the photo), Done goes back; moved and sized, the marks go with it.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run photomarks "pictures 0 photo; wait 1; photoon; wait 1; photoreport; phototool perspective; photodrag 0.5 0.42 0.45 0.38; phototool arrow; photodrag 0.55 0.85 0.75 0.55; phototool oval; photodrag 0.3 0.2 0.5 0.9; phototool box; photodrag 0.05 0.6 0.25 0.95; phototool line; photodrag 0.9 0.9 0.7 0.62; phototool words; photoclick 0.06 0.52; wait 0.5; type Maya; press return; wait 0.5; photoreport; phototool select; photoclick 0.25 0.775; photokey delete; photoreport; photokey escape; wait 0.5; photoreport; update {\"x\":6,\"w\":4.52,\"h\":1.9}; wait 0.5; photoreport" 12)
keep photomarks
p1=$(echo "$out" | grep '^photo:' | sed -n 1p); p2=$(echo "$out" | grep '^photo:' | sed -n 2p); p3=$(echo "$out" | grep '^photo:' | sed -n 3p)
p4=$(echo "$out" | grep '^photo:' | sed -n 4p); p5=$(echo "$out" | grep '^photo:' | sed -n 5p)
check "Draw on Photo opens it, at full strength, with nothing on it yet" "$(echo "$p1" | grep -q 'editing [0-9]' && echo "$p1" | grep -q 'opacity 1.00 .* marks 0' && echo yes)" "$p1"
check "…an arrow, an oval, a box, a line and words are drawn on it" "$(echo "$p2" | grep -q 'marks 5 \[arrow,oval,box,line,words(Maya)\]' && echo yes)" "$p2"
check "…the perspective helper keeps a horizon and a vanishing point" "$(echo "$p2" | grep -q 'perspective 0.3800:0.4500' && echo yes)" "$p2"
check "…Delete takes the picked mark, never the photo" "$(echo "$p3" | grep -q 'marks 4 \[arrow,oval,line,words(Maya)\]' && echo yes)" "$p3"
check "…Escape goes back to the plan, which draws the marks" "$(echo "$p4" | grep -q 'editing none' && echo "$p4" | grep -q 'shapes [1-9]' && echo yes)" "$p4"
check "…moved and made twice as big, the photo keeps its marks" "$(echo "$p5" | grep -q 'marks 4 .* at 6.00,.* size 4.52x1.90' && echo yes)" "$p5"



rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run shotstab "tool select; key a command; key delete; sidetab shots; shots; placeshot 0 400 380; shots; report; key escape; pickshot 0; report; removecam 0; shots; report; addshot; shots" 10)
keep shotstab
s1=$(echo "$out" | grep '^shots:' | sed -n 1p); s2=$(echo "$out" | grep '^shots:' | sed -n 2p)
s3=$(echo "$out" | grep '^shots:' | sed -n 3p); s4=$(echo "$out" | grep '^shots:' | sed -n 4p)
count() { echo "$1" | tr '|' '\n' | grep -c '[0-9]'; }
r1=$(echo "$out" | awk '/^drive:/{n++} n==1')
check "the Shots tab lists the scene's shots, none on the plan" "$([ "$(count "$s1")" -ge 3 ] && ! echo "$s1" | grep -q placed && echo yes)" "$s1"
check "…a shot dragged onto the plan places its camera, and no new shot" "$(echo "$s2" | sed 's/|.*//' | grep -q placed && [ "$(count "$s2")" = "$(count "$s1")" ] && [ "$(echo "$r1" | grep -c '^  camera .* shot ')" = 1 ] && echo yes)" "$s2"
check "…a click on a placed shot picks its camera" "$(echo "$out" | awk '/^drive:/{n++} n==2' | grep -q '^  camera .*\[picked\]' && echo yes)" "$(echo "$out" | awk '/^drive:/{n++} n==2' | grep camera)"
check "…Remove Camera takes the camera and keeps the shot" "$(! echo "$s3" | grep -q placed && [ "$(count "$s3")" = "$(count "$s1")" ] && ! echo "$out" | awk '/^drive:/{n++} n==3' | grep -q '^  camera ' && echo yes)" "$s3"
check "…Add Shot adds one to the scene" "$([ "$(count "$s4")" = $(( $(count "$s1") + 1 )) ] && echo yes)" "$s4"

rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run shotframe "tool select; key a command; key delete; placeshot 0 360 300; frame on; names; framedrag 90 30; names; framesize 60; names; haul 50 0; names; key escape; key escape" 10)
keep shotframe
f1=$(nm "$out" camera 1); f2=$(nm "$out" camera 2); f3=$(nm "$out" camera 3); f4=$(nm "$out" camera 4)
check "Frame on Plan lays the shot's frame by its camera" "$(echo "$f1" | grep -q 'frame on .* picture yes at' && echo yes)" "$f1"
check "…dragged, it stays where it is put" "$(python3 -c "
a=[float(v) for v in '$(field "$f1" offset)'.split(',')]; b=[float(v) for v in '$(field "$f2" offset)'.split(',')]
print('yes' if b[0]-a[0] > 0.5 and b[1]-a[1] > 0.1 else '')" 2>/dev/null)" "$f1 → $f2"
check "…its corner makes it bigger" "$(python3 -c "print('yes' if float('$(field "$f3" w)') > float('$(field "$f2" w)') + 0.3 else '')" 2>/dev/null)" "$f2 → $f3"
check "…and it goes where the camera goes" "$(python3 -c "
a=[float(v) for v in '$(field "$f3" at)'.split(',')]; b=[float(v) for v in '$(field "$f4" at)'.split(',')]
print('yes' if 30 < b[0]-a[0] < 70 and abs(b[1]-a[1])<4 and '$(field "$f3" offset)'=='$(field "$f4" offset)' else '')" 2>/dev/null)" "$f3 → $f4"

# 14 — light levels are off with the beams for now (his call, 2026-10-01;
# `render::LAMP_BEAMS`). Switched on in the film, nothing is drawn. The
# checks of 2026-09-28 (Lane E) come back with them.
clear="tool select; key a command; key delete"
out=$(run levels "$clear; tool cast; castas MAYA; click 560 420; tool light; arm fso-arri-s60c; click 720 520; tool select; pick 1; aimat cast; key escape; setting levels true; key escape; levels" 8)
keep levels
check "light levels switched on draw nothing for now" "$(echo "$out" | grep '^levels: on' | grep -q ' shapes 0 ' && echo yes)" "$(echo "$out" | grep '^levels: ' | head -2)"

# 15 — speed (Lane C, 2026-09-28): rigging, swap, favorites, one-key adds
# and alignment guides. Each run starts from an empty plan. `nth` is one
# report's line for a piece; `xy` its place.
nth() { echo "$1" | awk -v n="$2" '/^drive:/{k++} k==n' | grep -- "$3" | head -1; }
xy() { echo "$1" | sed 's/.* at \([-0-9.]*\),\([-0-9.]*\) .*/\1 \2/'; }
stand="tool set; arm c-stand; click 400 620"
out=$(run rig "$clear; $stand; tool light; arm tungsten-fresnel-1k; click 404 620; report; layers; tool select; haulby 0 -0.8 -0.8 120 60; report; key z command; report" 10)
keep rig
l1=$(nth "$out" 1 "^  light "); s1=$(nth "$out" 1 "^  set "); l2=$(nth "$out" 2 "^  light "); s2=$(nth "$out" 2 "^  set "); l3=$(nth "$out" 3 "^  light ")
check "a lamp put down on a stand rides it" "$(echo "$l1" | grep -q ' on set' && echo yes)" "$l1"
check "…Layers shows it under its stand" "$(echo "$out" | grep -q '^layers: C-Stand | >Light' && echo yes)" "$(echo "$out" | grep '^layers:')"
check "…moving the stand carries the lamp" "$(python3 -c "
a,b,c,d=[list(map(float,x.split())) for x in ['$(xy "$s1")','$(xy "$s2")','$(xy "$l1")','$(xy "$l2")']]
print('yes' if abs(b[0]-a[0])>0.5 and abs((b[0]-a[0])-(d[0]-c[0]))<1e-3 and abs((b[1]-a[1])-(d[1]-c[1]))<1e-3 else '')" 2>/dev/null)" "$s1 → $s2 / $l1 → $l2"
check "…and one undo puts both back" "$([ "$(xy "$l3")" = "$(xy "$l1")" ] && echo yes)" "$l3"
out=$(run rigoff "$clear; $stand; drop sym:tungsten-fresnel-1k 400 620; report; pick 1; haul 200 0; report; tool select; haulby 0 0.8 0.8 80 0; report" 10)
l1=$(nth "$out" 1 "sym tungsten-fresnel-1k"); l2=$(nth "$out" 2 "sym tungsten-fresnel-1k"); l3=$(nth "$out" 3 "sym tungsten-fresnel-1k")
check "a lamp dropped from the library onto a stand rides it" "$(echo "$l1" | grep -q ' on set' && echo yes)" "$l1"
check "…dragged fully off, it gets off and stays put" "$(echo "$l2" | grep -qv ' on ' && [ "$(xy "$l3")" = "$(xy "$l2")" ] && echo yes)" "$l2 / $l3"
out=$(run rigdup "$clear; $stand; drop sym:tungsten-fresnel-1k 400 620; pick 0; key d command; report; pick 0; key delete; report" 8)
check "duplicating a stand duplicates its lamp, riding the copy" "$(nth "$out" 1 "^drive:" | grep -q '4 els' && [ "$(echo "$out" | awk '/^drive:/{k++} k==1' | grep 'sym tungsten-fresnel-1k' | grep -c ' on set')" = 2 ] && echo yes)" "$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  ')"
check "…deleting a stand leaves its lamp, on its own" "$(nth "$out" 2 "^drive:" | grep -q '3 els' && [ "$(echo "$out" | awk '/^drive:/{k++} k==2' | grep 'sym tungsten-fresnel-1k' | grep -c ' on ')" = 1 ] && echo yes)" "$(echo "$out" | awk '/^drive:/{k++} k==2' | grep '^  ')"

out=$(run swap "$clear; tool light; arm tungsten-fresnel-1k; click 400 620; act colour D9483B; report; drop sym:fso-arri-m18 400 620 shift; report; chrome; swap generic-hmi; report; key z command; report" 10)
keep swap
p1=$(nth "$out" 1 "^  light"); p2=$(nth "$out" 2 "^  light"); p3=$(nth "$out" 3 "^  light"); p4=$(nth "$out" 4 "^  light")
check "⇧-dropping a library lamp on a lamp swaps it where it stands" "$(nth "$out" 2 "^drive:" | grep -q '1 els' && echo "$p2" | grep -q 'sym fso-arri-m18' && [ "$(xy "$p2")" = "$(xy "$p1")" ] && echo yes)" "$p1 → $p2"
check "…keeping its colour" "$(chrome "$out" 1 | grep -q 'colour #D9483B' && echo yes)" "$(chrome "$out" 1)"
check "…Swap With does the same, and one undo takes one swap back" "$(echo "$p3" | grep -q 'sym generic-hmi' && echo "$p4" | grep -q 'sym fso-arri-m18' && echo yes)" "$p3 / $p4"

out=$(run favs "$clear; favclear 3; favclear 5; tool light; arm tungsten-fresnel-1k; click 400 620; act colour 3D7BD9; fav 3; favs; tool select; move 600 300; key 3; report; chrome; pickkind light; favorites on; favdrag 5; favs; report; move 300 500; key 7; report" 12)
keep favs
check "Add to Favorites keeps a Light in slot 3" "$(echo "$out" | grep '^favs:' | head -1 | grep -q '3=Light' && echo yes)" "$(echo "$out" | grep '^favs:' | head -1)"
f1=$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  light ' | tail -1); f0=$(nth "$out" 1 '^  light ')
check "…3 puts one down under the pointer, in its colour" "$(nth "$out" 1 "^drive:" | grep -q '2 els' && [ "$(xy "$f1")" != "$(xy "$f0")" ] && chrome "$out" 1 | grep -q 'colour #3D7BD9' && echo yes)" "$f1 / $(chrome "$out" 1)"
check "…a piece dragged onto slot 5 is kept there and stays where it was" "$(echo "$out" | grep '^favs:' | tail -1 | grep -q '5=Light' && [ "$(xy "$(nth "$out" 2 '^  light ')")" = "$(xy "$f0")" ] && echo yes)" "$(echo "$out" | grep '^favs:' | tail -1)"
check "…an empty slot's key puts nothing down" "$(nth "$out" 3 "^drive:" | grep -q '2 els' && echo yes)" "$(nth "$out" 3 "^drive:")"
out=$(KEEPFILM=1 run favs2 "favs" 4)
check "…and the favorites travel with the film" "$(echo "$out" | grep '^favs:' | grep -q '3=Light.*5=Light' && echo yes)" "$(echo "$out" | grep '^favs:')"

out=$(run keys "$clear; move 300 300; key c; move 520 300; key t; settext Hello; move 300 480; key a shift; move 560 480; key w shift; report; key p shift; report" 10)
keep keys
r1=$(echo "$out" | awk '/^drive:/{k++} k==1')
check "C puts a camera under the pointer, with its shot" "$(echo "$r1" | grep '^  camera ' | grep -q ' shot ' && echo yes)" "$(echo "$r1" | grep '^  camera ')"
check "…T words, ⇧A a person, ⇧W an arrow" "$(echo "$r1" | grep -q 'text "Hello"' && echo "$r1" | grep -q '^  cast ' && echo "$r1" | grep -q '^  arrow ' && echo yes)" "$(echo "$r1" | grep '^  ')"
check "…each where the pointer was" "$(python3 -c "
c,t,p,a=[list(map(float,x.split())) for x in ['$(xy "$(echo "$r1" | grep '^  camera ')")','$(xy "$(echo "$r1" | grep '^  text ')")','$(xy "$(echo "$r1" | grep '^  cast ')")','$(xy "$(echo "$r1" | grep '^  arrow ')")']]
print('yes' if t[0]-c[0]>0.5 and abs(t[1]-c[1])<0.3 and p[1]-c[1]>0.5 and a[0]-p[0]>0.5 else '')" 2>/dev/null)" "$(echo "$r1" | grep '^  ')"
check "…⇧P opens the pictures" "$(nth "$out" 2 "^drive:" | grep -q 'tool picture' && echo yes)" "$(nth "$out" 2 "^drive:")"

# Each piece put down goes back to the arrow (his note, 2026-09-29), so
# the tool is taken up again for the second.
# Two boxes a whole number of feet, on the grid: a line-up is taken only
# where it keeps the piece on the grid (2026-10-01), so both are on it — 16
# checks the one off it.
two="$clear; tool shape; down 400 300; drag 437 337; up 437 337; tool shape; down 700 450; drag 755 487; up 755 487; tool select"
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"   # a fresh view: screen points mean the same feet
out=$(run guides "$two; lineup 1 0 240 6; guides; letgo; report" 10)
g=$(echo "$out" | grep '^guides:'); a=$(nth "$out" 1 '^  shape '); b=$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  shape ' | tail -1)
check "a piece moved near another's line shows a guide" "$(echo "$g" | grep -qE '^guides: [1-9]' && echo yes)" "$g"
check "…and the piece it lines up with lights up" "$(echo "$g" | grep -q ' with shape' && echo yes)" "$g"
check "…and lands in line with it" "$(python3 -c "print('yes' if abs(float('$(xy "$a" | cut -d' ' -f2)')-float('$(xy "$b" | cut -d' ' -f2)'))<1e-3 else '')" 2>/dev/null)" "$a / $b"
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"   # a fresh view: screen points mean the same feet
out=$(run guidesfree "$two; lineup 1 0 240 6 command; guides; letgo; report" 10)
g=$(echo "$out" | grep '^guides:'); a=$(nth "$out" 1 '^  shape '); b=$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  shape ' | tail -1)
check "…⌘ held moves it free" "$(echo "$g" | grep -q '^guides: 0' && python3 -c "print('yes' if abs(float('$(xy "$a" | cut -d' ' -f2)')-float('$(xy "$b" | cut -d' ' -f2)'))>0.005 else '')" 2>/dev/null)" "$g / $a / $b"
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"   # a fresh view: screen points mean the same feet
out=$(run guidesnap "$two; lineup 1 0 240 5; wait 0.5" 4)
keep guidesnap

# 16 — exact numbers, and turning anything (his notes of 2026-09-30, the
# Diagram master list's sections 1 and 2). `exact` prints every piece to the
# ten-thousandth of a metre, its length as Details reads it and whether it
# sits on the grid; `ex <out> <n>` is the nth such print.
ex() { echo "$1" | awk -v n="$2" '/^exact:/{k++} k==n'; }
fresh() { rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"; }
fresh
# ⇧ held while a wall, a measure and an arrow are drawn long with the hand a
# little low: each reads an exact whole number of feet (it read 36 ft 1 in).
# (How many feet depends on the zoom the plan opens at, so it is read back,
# not assumed.)
fresh
out=$(run exact36 "tool wall; down 200 300; drag 500 320 shift; drag 858 336 shift; up 858 336 shift; key escape; tool measure; down 200 500; drag 600 520 shift; drag 858 540 shift; up 858 540 shift; tool arrow; down 200 600; drag 852 590 shift; up 852 590 shift; exact" 6)
keep exact36
check "⇧ keeps a wall, a measure and an arrow straight, an exact whole number of feet long" "$(ex "$out" 1 | python3 -c "
import sys, re
ls = [l for l in sys.stdin.read().splitlines() if re.match(r'  (wall|measure|arrow) ', l)]
ok = len(ls) == 3
for l in ls:
    m = re.search(r'rot (-?[0-9.]+) .* len ([0-9.]+) \"(\d+) ft\" grid yes', l)
    if not m: ok = False; continue
    ft = float(m.group(2)) / 0.3048
    ok = ok and abs(float(m.group(1))) < 1e-6 and abs(ft - round(ft)) < 1e-6 and int(m.group(3)) == round(ft) and ft >= 10
print('yes' if ok else '')")" "$(ex "$out" 1 | grep '^  ')"
# A box (a whole number of feet each way) moved twice keeps its edges on the grid; a bed (not a
# whole number of feet) lands an edge on it each way; a corner dragged lands
# on the grid, so the bed is then on it all round.
fresh
out=$(run exactbox "tool shape; down 400 300; drag 500 400; drag 601 446; up 601 446; tool select; pickkind shape; haul 37 23; exact; haul -13 51; exact; tool set; arm fso-bed; click 900 620; tool select; haul 31 17; exact; grab corner 2 23 30; exact" 8)
s2=$(ex "$out" 2 | grep '^  shape '); bed=$(ex "$out" 3 | grep '^  set '); bed2=$(ex "$out" 4 | grep '^  set ')
check "a box moved keeps its edges on the grid" "$(python3 -c "
import re, sys
ok = True
for l in sys.argv[1:]:
    m = re.search(r'size ([0-9.]+)x([0-9.]+) edges (yes|no)', l)
    if not m: ok = False; continue
    w, h = float(m.group(1)) / 0.3048, float(m.group(2)) / 0.3048
    ok = ok and m.group(3) == 'yes' and abs(w - round(w)) < 1e-3 and abs(h - round(h)) < 1e-3
print('yes' if ok else '')" "$(ex "$out" 1 | grep '^  shape ')" "$s2" 2>/dev/null)" "$(ex "$out" 1 | grep '^  shape ') / $s2"
check "…a piece of no whole size lands an edge each way on the grid" "$(python3 -c "
import re
m=re.search(r'at (-?[0-9.]+),(-?[0-9.]+) rot [0-9.]+ size ([0-9.]+)x([0-9.]+)', '''$bed''')
x,y,w,h=map(float,m.groups()); s=0.3048
on=lambda v: abs(v/s-round(v/s))<1e-3
print('yes' if (on(x-w/2) or on(x+w/2)) and (on(y-h/2) or on(y+h/2)) else '')" 2>/dev/null)" "$bed"
check "…and a corner dragged lands on the grid" "$(echo "$bed2" | grep -q 'edges yes' && echo yes)" "$bed2"
# Lined up with a piece off the grid, the grid wins; with one on it, the
# piece lines up and stays on it.
gs="tool shape; down 400 300 command; drag 437 337 command; up 437 337 command; tool shape; down 700 450; drag 755 487; up 755 487; tool select"
fresh
out=$(run exactguide "$gs; lineup 1 0 240 4; letgo; exact" 8)
check "a line-up never pulls a piece off the grid" "$(ex "$out" 1 | grep '^  shape ' | tail -1 | grep -q 'edges yes' && echo yes)" "$(ex "$out" 1 | grep '^  shape ')"
# Metres: switching units switches the grid to half a metre; a ⇧ wall reads
# whole number of metres on it; closer in the step goes to 10 cm, further out it stays put.
fresh
out=$(run exactmetric "setting units m; tool wall; down 200 300; drag 600 310 shift; drag 862 320 shift; up 862 320 shift; key escape; exact; zoom 9; exact; setting units ft; exact" 6)
check "metres snap to half a metre, and a ⇧ wall reads a whole number of them" "$(ex "$out" 1 | python3 -c "
import sys, re
t = sys.stdin.read(); m = re.search(r'  wall .* len ([0-9.]+) \"([0-9.]+) m\" grid yes', t)
n = float(m.group(1)) if m else 0
print('yes' if m and 'step 0.5000 units m' in t and n >= 3 and abs(n * 2 - round(n * 2)) < 1e-6 and abs(float(m.group(2)) - n) < 0.005 else '')")" "$(ex "$out" 1)"
check "…closer in, the step goes finer" "$(ex "$out" 2 | grep -q 'step 0.1000 units m' && echo yes)" "$(ex "$out" 2 | head -1)"
check "…and back in feet, a foot step again" "$(ex "$out" 3 | grep -qE 'step 0.(0762|1524|3048) units ft' && echo yes)" "$(ex "$out" 3 | head -1)"
fresh
# Nudges: an arrow is a quarter of the grid, ⇧-arrow one step, and a run of
# presses is one step of undo. ⌥→ turns 5° a press with Snap on, one step of
# undo for the run; with Snap off a degree.
fresh
out=$(run exactkeys "tool light; arm tungsten-fresnel-1k; click 700 620; tool select; exact; history; key right; key right; key down shift; exact; history; key z command; exact; key right option; key right option; key right option; exact; history; key z command; exact; setting snap false; pick 0; key right option; exact" 8)
xy4() { ex "$out" "$1" | grep '^  light ' | sed 's/.* at \([-0-9.]*\),\([-0-9.]*\) rot \([0-9.]*\).*/\1 \2 \3/'; }
# turned <n> <deg> — the nth print's lamp is turned deg from the first's
# (a lamp lands facing up, 270°)
turned() { python3 -c "
a=float('$(xy4 1)'.split()[2]); b=float('$(xy4 "$1")'.split()[2])
exit(0 if abs((b-a-$2+180)%360-180)<1e-6 else 1)" 2>/dev/null; }
dep() { echo "$out" | grep '^history:' | sed -n "${1}p" | grep -o 'depth [0-9]*' | cut -d' ' -f2; }
check "arrows nudge a quarter step, ⇧-arrow a whole one, one undo for the run" "$(python3 -c "
a=list(map(float,'$(xy4 1)'.split())); b=list(map(float,'$(xy4 2)'.split())); c=list(map(float,'$(xy4 3)'.split()))
print('yes' if abs(b[0]-a[0]-0.1524)<1e-4 and abs(b[1]-a[1]-0.3048)<1e-4 and c[:2]==a[:2] and $(dep 2)==$(dep 1)+1 else '')" 2>/dev/null)" "$(xy4 1) → $(xy4 2) → $(xy4 3); depth $(dep 1) → $(dep 2)"
check "⌥→ turns 5° a press, the run one undo" "$(turned 4 15 && [ "$(dep 3)" = "$(( $(dep 1) + 1 ))" ] && turned 5 0 && echo yes)" "$(xy4 4) / $(xy4 5); depth $(dep 1) → $(dep 3)"
check "…a degree with Snap off" "$(turned 6 1 && echo yes)" "$(xy4 1) / $(xy4 6)"
fresh
# Turning by hand: a light's knob out in front, dragged to the right, points
# right; a set piece's knob turns in 5° steps. (A lamp has no reach handle
# now: lamps throw no beam.)
fresh
out=$(run exactknob "tool light; arm tungsten-fresnel-1k; click 700 620; tool select; exact; knobto 120 0; exact; handles; tool set; arm fso-bed; click 500 620; tool select; grab rotate 0 37 61; exact" 8)
check "a light's knob dragged right points it right" "$(ex "$out" 1 | grep '^  light ' | grep -q 'rot 270.00' && ex "$out" 2 | grep '^  light ' | grep -q 'rot 0.00' && echo yes)" "$(ex "$out" 2 | grep '^  light ')"
check "…its knob stands in front of it (it has no reach handle: lamps throw no beam)" "$(echo "$out" | grep '^handles:' | python3 -c "
import sys,re
t=sys.stdin.read(); g=lambda k: list(map(float,re.search(k+r'=(-?[0-9.]+),(-?[0-9.]+)',t).groups()))
r,m=g('rotate0'),g('middle')
print('yes' if r[0]>m[0]+10 and abs(r[1]-m[1])<2 and 'reach0' not in t else '')" 2>/dev/null)" "$(echo "$out" | grep '^handles:')"
check "a set piece turned by hand turns in 5° steps" "$(ex "$out" 3 | grep '^  set ' | python3 -c "
import sys,re; r=float(re.search(r'rot ([0-9.]+)',sys.stdin.read()).group(1)); print('yes' if r>0 and abs(r/5-round(r/5))<1e-6 else '')" 2>/dev/null)" "$(ex "$out" 3 | grep '^  set ')"
fresh
# A room drawn with ⇧ is one closed wall: a click takes it whole, ⌘R turns
# it a quarter about a grid point and every corner stays on the grid; ⌥→
# turns it 5° at a time (its box and knob are gone).
fresh
out=$(run exactroom "tool wall; down 400 300 shift; drag 500 400; drag 601 446; up 601 446; key escape; tool select; clickon 0; report; key r command; exact; key right option; exact" 10)
keep exactroom
check "a ⇧-drawn room is one closed wall, and a click takes it whole" "$(echo "$out" | awk '/^drive:/{k++} k==1' | grep -q '^drive: 1 els; picked 1' && echo "$out" | grep '^  wall ' | head -1 | grep -q 'corners 4 closed' && echo yes)" "$(echo "$out" | awk '/^drive:/{k++} k==1' | head -1)"
check "…turned a quarter, every corner stays on the grid" "$(ex "$out" 1 | grep '^  wall ' | grep -q 'grid yes' && echo yes)" "$(ex "$out" 1 | grep '^  ')"
check "…⌥→ turns it 5° at a time (a room has no box to turn by now)" "$(python3 -c "
import sys,re,math
def edge(l):
    m=re.search(r'\[(-?[0-9.]+),(-?[0-9.]+) (-?[0-9.]+),(-?[0-9.]+)', l); a,b,c,d=map(float,m.groups()); return math.degrees(math.atan2(d-b,c-a))
try:
    d=(edge(sys.argv[2])-edge(sys.argv[1])+180)%360-180
    print('yes' if abs(d-5)<0.05 else '')
except Exception: print('')" "$(ex "$out" 1 | grep '^  wall ' | head -1)" "$(ex "$out" 2 | grep '^  wall ' | head -1)")" "$(ex "$out" 1 | grep '^  wall ' | head -1) → $(ex "$out" 2 | grep '^  wall ' | head -1)"
fresh
# ⌥-click without moving makes no copy; ⌥-drag makes one, and one undo
# takes the copy and its move back. A small piece far out is moved by its
# body, not stretched by a handle.
fresh
out=$(run exactcopy "tool light; arm tungsten-fresnel-1k; click 700 620; tool select; key escape; history; down 700 620 option; up 700 620 option; report; down 700 620 option; drag 720 620 option; drag 760 620 option; up 760 620 option; report; history; key z command; report; zoom 0.5; pick 0; haul 30 0; exact" 8)
check "⌥-click without moving makes no copy" "$(echo "$out" | awk '/^drive:/{k++} k==1' | grep -q '^drive: 1 els' && echo yes)" "$(echo "$out" | awk '/^drive:/{k++} k==1' | head -1)"
check "…⌥-drag makes one, and one undo takes copy and move back" "$(echo "$out" | awk '/^drive:/{k++} k==2' | grep -q '^drive: 2 els' && echo "$out" | awk '/^drive:/{k++} k==3' | grep -q '^drive: 1 els' && [ "$(echo "$out" | grep '^history:' | sed -n 2p | grep -o 'depth [0-9]*')" = "$(echo "$out" | grep '^history:' | sed -n 1p | grep -o 'depth [0-9]*' | awk '{print "depth " $2+1}')" ] && echo yes)" "$(echo "$out" | grep -E '^(drive|history):')"
check "…a small piece dragged by its middle moves, and keeps its size" "$(ex "$out" 1 | grep '^  light ' | grep -q 'size 0.3000x0.3000' && ! ex "$out" 1 | grep '^  light ' | grep -q 'at 1.2192,3.6576' && echo yes)" "$(ex "$out" 1 | grep '^  light ')"
fresh
# Details › Length reads fractions, and keeps the corner the wall shares.
fresh
out=$(run exactlen "tool wall; click 300 200; click 700 200; click 700 500; click 300 500; click 300 200; tool select; pick 0; length 25' 6 1/2\"; exact; parse 6 1/2\"; parse 36' 6 1/2\"; parse 11m" 6)
check "a length typed with a fraction is read as typed" "$(echo "$out" | grep -q 'parse: "6 1/2"" reads 0.1651 m 6 ½ in' && echo "$out" | grep -q 'parse: "36'"'"' 6 1/2"" reads 11.1379 m 36 ft 6 ½ in' && echo "$out" | grep -q 'parse: "11m" reads 11.0000' && echo yes)" "$(echo "$out" | grep '^parse:')"
check "…and a room's stretch given a length is its inside, the room kept closed" "$(ex "$out" 1 | grep '^  wall ' | grep -q 'lengths \[25 ft 6 ½ in|' && ex "$out" 1 | grep -q 'corners 4 closed' && echo yes)" "$(ex "$out" 1 | grep '^  ')"
fresh

# 14 — walls as one line (master list 3, 2026-10-01). A + beside a stretch
# adds a corner and drags it, one undo for both; Break opens a door-wide
# gap; a T stays on its wall when the wall moves; lengths are off until
# asked for (quiet by default, Back to Paper Batch 1), then show on the
# picked wall only, or every wall with View › Wall Lengths › All; five
# thicknesses in one tap.
fresh
out=$(run wallline "tool wall; click 300 250; click 700 250; click 700 520; key return; tool select; history; report; grab addcorner 0 0 -60; exact; history; report; setting dims true; report; key escape; key escape; report; setting all_lengths true; report" 8)
keep wallline
dep() { echo "$out" | grep '^history:' | sed -n "${1}p" | grep -o 'depth [0-9]*' | cut -d' ' -f2; }
wl() { echo "$out" | grep '^walls:' | sed -n "${1}p"; }
check "a + adds a corner and drags it, one step to take back" "$(ex "$out" 1 | grep '^  wall ' | grep -q 'corners 4 \[' && [ "$(dep 2)" = "$(( $(dep 1) + 1 ))" ] && wl 2 | grep -q 'corner 1 ' && echo yes)" "$(ex "$out" 1 | grep '^  wall '); $(wl 2)"
check "…lengths are off until asked for, then show on the picked wall only, or on every wall with All" "$(wl 2 | grep -q 'lengths 0 ' && wl 3 | grep -q 'lengths 3 ' && wl 4 | grep -q 'lengths 0 ' && wl 5 | grep -q 'lengths 3 ' && echo yes)" "$(wl 2) / $(wl 3) / $(wl 4) / $(wl 5)"
fresh
out=$(run wallbreak "tool wall; click 300 250; click 700 250; click 700 520; click 300 520; click 300 250; tool select; grab addcorner 0 0 0; wallact break; exact; thick 0; exact" 8)
keep wallbreak
check "Break opens a three-foot gap in a room's stretch" "$(ex "$out" 1 | grep '^  wall ' | python3 -c "
import sys,re
l=sys.stdin.read(); m=re.search(r'corners ([0-9]+) \[([^]]*)\]',l)
p=[tuple(map(float,q.split(','))) for q in m.group(2).split()]
gap=((p[0][0]-p[-1][0])**2+(p[0][1]-p[-1][1])**2)**.5
print('yes' if m.group(1)=='6' and 'closed' not in l and abs(gap-0.9144)<1e-3 else '')" 2>/dev/null)" "$(ex "$out" 1 | grep '^  wall ')"
check "…and a thickness is one tap" "$(ex "$out" 2 | grep '^  wall ' | grep -q 'thick 0.0254' && echo yes)" "$(ex "$out" 2 | grep '^  wall ')"
fresh
out=$(run walltee "tool wall; click 300 250; click 700 250; click 700 520; click 300 520; click 300 250; tool wall; click 470 248; click 470 400; key return; tool select; key escape; clickon 0; haul 40 -60; exact" 8)
keep walltee
check "a wall started on another's middle stays on it when that wall moves" "$(ex "$out" 1 | python3 -c "
import sys,re
ws=[l for l in sys.stdin.read().splitlines() if l.startswith('  wall ')]
room=[l for l in ws if 'closed' in l][0]; tee=[l for l in ws if 'closed' not in l][0]
ry=float(re.search(r'\[(-?[0-9.]+),(-?[0-9.]+)',room).group(2)); ty=float(re.search(r'\[(-?[0-9.]+),(-?[0-9.]+)',tee).group(2))
print('yes' if abs(ry-ty)<1e-3 else '')" 2>/dev/null)" "$(ex "$out" 1 | grep '^  wall ')"
fresh
out=$(run wallflush "tool wall; click 300 250; click 700 250; click 700 520; click 300 520; click 300 250; tool select; drop sym:fso-double-couch 500 420; pickkind set; haul 13 -122; exact; tool door; click 380 246; tool select; haul 37 2; exact; place x 3'; exact" 8)
keep wallflush
check "a couch pushed into a wall stops flush with its inside face" "$(ex "$out" 1 | python3 -c "
import sys,re
t=sys.stdin.read()
w=re.search(r'wall .*corners 4 closed \[(-?[0-9.]+),(-?[0-9.]+)',t); s=re.search(r'set .* at (-?[0-9.]+),(-?[0-9.]+) rot [0-9.]+ size ([0-9.]+)x([0-9.]+)',t)
wy=float(w.group(2)); sy=float(s.group(2)); h=float(s.group(4))
print('yes' if abs((sy-h/2)-(wy+0.0762))<1e-3 else '')" 2>/dev/null)" "$(ex "$out" 1 | grep -E '^  (set|wall) ')"
check "…a door slid along a wall steps a foot at a time from its corner" "$(ex "$out" 2 | python3 -c "
import sys,re
t=sys.stdin.read()
w=re.search(r'wall .*corners 4 closed \[(-?[0-9.]+),(-?[0-9.]+)',t); d=re.search(r'door .* at (-?[0-9.]+),(-?[0-9.]+) rot [0-9.]+ size ([0-9.]+)x',t)
k=((float(d.group(1))-float(d.group(3))/2)-(float(w.group(1))+0.0762))/0.3048
print('yes' if k>0.5 and abs(k-round(k))<1e-3 else '')" 2>/dev/null)" "$(ex "$out" 2 | grep -E '^  (door|wall) ')"
check "…and Details' X puts a piece at an exact spot" "$(ex "$out" 3 | grep '^  door ' | grep -q 'at 0.9144,' && echo yes)" "$(ex "$out" 3 | grep '^  door ')"
fresh

# 17 — the master list's section 7 (2026-10-01): what shows while a thing
# changes, a picked lamp showing no beam (for now), paste at the pointer, locked
# pieces clicked through, hover, ⌥ keeping the tool, and undo saying what.
fresh
# The size, the angle, how far — beside the pointer, mid-drag.
out=$(run readmove "tool set; arm fso-bed; click 500 600; tool select; down 500 600; drag 540 600; drag 600 580; readout; up 600 580; hold corner 2 60 40; readout" 6)
check "dragging shows how far it has gone" "$(echo "$out" | grep '^readout:' | sed -n 1p | grep -qE '^readout: Δx [0-9]+ ft' && echo yes)" "$(echo "$out" | grep '^readout:')"
check "…a corner pulled shows the size" "$(echo "$out" | grep '^readout:' | sed -n 2p | grep -qE '^readout: [0-9]+ ft( [0-9]+ in)? × [0-9]+ ft' && echo yes)" "$(echo "$out" | grep '^readout:')"
fresh
# A lamp picked shows no beam for now (his call, 2026-10-01) — neither does
# the lamp beside it (library fixtures, which have a beam to show). Turning,
# its angle.
out=$(run readturn "drop sym:tungsten-fresnel-1k 300 600; drop sym:tungsten-fresnel-1k 500 600; pickkind light; beams; hold rotate 0 80 60; readout" 6)
keep readturn
picked=$(echo "$out" | grep '^beams: tungsten-fresnel-1k' | tail -1); other=$(echo "$out" | grep '^beams: tungsten-fresnel-1k' | head -1)
check "a picked lamp shows no beam, edge or spread for now" "$(echo "$picked" | grep -q ' n 0 ' && echo "$picked" | grep -q 'lines 0 note ""' && echo yes)" "$picked"
check "…nor does the lamp not picked" "$(echo "$other" | grep -q 'lines 0 note ""' && echo yes)" "$other"
check "…and turning it shows the angle" "$(echo "$out" | grep -qE '^readout: [0-9]+°$' && echo yes)" "$(echo "$out" | grep '^readout:')"
fresh
# Paste lands at the pointer; again, a step on; a lamp's copy aims at its
# person's copy.
out=$(run pastehere "tool cast; castas MAYA; click 700 600; tool light; arm tungsten-fresnel-1k; click 500 600; aimat cast; tool select; key a command; key c command; move 800 350; key v command; key v command; report" 6)
keep pastehere
ys=$(echo "$out" | grep '^  light ' | sed 's/.* at [-0-9.]*,\([-0-9.]*\) .*/\1/' | tr '\n' ' ')
xs=$(echo "$out" | grep '^  light ' | sed 's/.* at \([-0-9.]*\),.*/\1/' | tr '\n' ' ')
check "paste lands at the pointer, and again a step on" "$(python3 -c "
y=[float(v) for v in '$ys'.split()]; x=[float(v) for v in '$xs'.split()]
print('yes' if len(y)==3 and y[0]-y[1]>2 and abs((y[2]-y[1])-(x[2]-x[1]))<0.011 and 0.1<y[2]-y[1]<1 else '')" 2>/dev/null)" "$(echo "$out" | grep '^  ')"
check "…and the copies keep their aim, at each other" "$([ "$(echo "$out" | grep -c '^  light .* aim cast')" = 3 ] && echo "$out" | grep '^  light ' | tail -1 | grep -q ' rot 0 ' && echo yes)" "$(echo "$out" | grep '^  light ')"
fresh
# A copy moved before the next ⌘D teaches the step: the third lands as far
# from the second as the second from the first.
out=$(run duprow "tool set; arm fso-bed; click 400 620; tool select; key d command; haul 60 0; key d command; report" 6)
xs=$(echo "$out" | grep '^  set ' | sed 's/.* at \([-0-9.]*\),\([-0-9.]*\) .*/\1 \2/' | tr '\n' ' ')
check "duplicate steps on as far as the last copy was moved" "$(python3 -c "
v=[float(t) for t in '$xs'.split()]
print('yes' if len(v)==6 and abs((v[4]-v[2])-(v[2]-v[0]))<0.015 and abs((v[5]-v[3])-(v[3]-v[1]))<0.015 and v[2]-v[0]>0.6 else '')" 2>/dev/null)" "$(echo "$out" | grep '^  set ')"
fresh
# A locked floor plan is clicked through: a click on it picks nothing, a
# drag over it picks what is on it; a right-click still finds it, to Unlock.
out=$(run lockedthrough "pictures 0 back; act lock; tool cast; castas MAYA; click 640 600; tool select; key escape; click 800 400; report; down 300 250; drag 600 450; drag 900 680; up 900 680; report; menuat 800 400" 6)
check "a locked picture is clicked through" "$(echo "$out" | awk '/^drive:/{k++} k==1' | grep -q 'picked 0' && echo yes)" "$(echo "$out" | grep '^drive:')"
check "…a drag over it picks what is on it" "$(echo "$out" | awk '/^drive:/{k++} k==2' | grep -q 'picked 1' && echo "$out" | awk '/^drive:/{k++} k==2' | grep '^  cast ' | grep -q picked && echo yes)" "$(echo "$out" | awk '/^drive:/{k++} k==2' | grep '^  ')"
check "…and a right-click on it offers Unlock" "$(echo "$out" | grep '^menu:' | grep -q '| Unlock |' && echo yes)" "$(echo "$out" | grep '^menu:')"
fresh
# ⌥-click keeps the tool (a plain click goes back to the arrow, except for the
# Light tool, which stays to lay the next mark: checked with the lights above);
# hover names what a click would take; undo says what it took back.
out=$(run touches "tool cast; castas MAYA; click 640 600; tool camera; click 400 600 option; click 500 600; report; tool select; key escape; move 640 600; hovered; pickkind cast; haul 60 0; key z command" 6)
keep touches
check "⌥-click keeps the tool for the next" "$(echo "$out" | grep -q '^drive: 3 els; picked 1; tool select' && echo yes)" "$(echo "$out" | grep '^drive:')"
check "…hover finds what a click would take" "$(echo "$out" | grep -q '^hovered: cast' && echo yes)" "$(echo "$out" | grep '^hovered:')"
check "…and undo says what it undid" "$(echo "$out" | grep -q '^toast: Undo Move' && echo yes)" "$(echo "$out" | grep '^toast:')"
fresh

# 18 — the master list's Later items (2026-10-01). Arrows that stay
# attached: words with three arrows drawn onto a person, a lamp and a couch,
# pinned; the couch moved and its arrow following; an end dragged off and
# freed, then dropped on the couch and pinned again. A camera's body picked
# from the action bar; the distance written on a picked camera's aim line.
arrowed="tool select; key a command; key delete; tool text; click 330 420; settext Hide the tubes; tool cast; castas MAYA; click 640 260; drop sym:fso-arri-s60c 700 640; drop sym:fso-double-couch 420 620; tool select; key escape; tool arrow; drawto text cast; tool arrow; drawto text light; tool arrow; drawto text set; tool select; key escape"
out=$(run pinned "$arrowed; report; pickkind set; haul 0 -120; key escape; report" 8)
keep pinned
pins=$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  arrow ' | grep -o 'pins [a-z-]*,[a-z-]*' | sort | tr '\n' ' ')
check "an arrow drawn from words onto a piece is pinned at both ends — three fanning out" "$([ "$pins" = "pins text,cast pins text,light pins text,set " ] && echo yes)" "$pins"
ends() { echo "$1" | awk -v n="$2" '/^drive:/{k++} k==n' | grep '^  arrow ' | grep 'pins text,set' | sed 's/.* to \([-0-9.]*\),\([-0-9.]*\).*/\1 \2/'; }
setat() { echo "$1" | awk -v n="$2" '/^drive:/{k++} k==n' | grep '^  set ' | sed 's/.* at \([-0-9.]*\),\([-0-9.]*\) .*/\1 \2/'; }
check "…the couch moved, its arrow's head goes with it and stops at its edge" "$(python3 -c "
a=[float(v) for v in '$(ends "$out" 1)'.split()]; b=[float(v) for v in '$(ends "$out" 2)'.split()]; s=[float(v) for v in '$(setat "$out" 2)'.split()]
print('yes' if b[1] < a[1] - 1 and 0.3 < ((b[0]-s[0])**2+(b[1]-s[1])**2)**0.5 < 1.2 else '')" 2>/dev/null)" "$(ends "$out" 1) → $(ends "$out" 2) couch $(setat "$out" 2)"
# One arrow, from the words to the couch: picked by what it is (the stack's order
# is the engine's, not the order things were drawn in).
one="tool select; key a command; key delete; tool text; click 330 420; settext Hide the tubes; drop sym:fso-double-couch 420 620; tool select; key escape; tool arrow; drawto text set; tool select; key escape"
out=$(run unpinned "$one; pickkind arrow; endto 1 900 500; key escape; report; pickkind arrow; endto 1 set; key escape; report" 8)
first=$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  arrow ' | sed -n 1p | grep -o 'pins [a-z-]*,[a-z-]*')
again=$(echo "$out" | awk '/^drive:/{k++} k==2' | grep '^  arrow ' | sed -n 1p | grep -o 'pins [a-z-]*,[a-z-]*')
check "…its end dragged off a piece is free, and dropped on another is pinned there" "$([ "$first" = "pins text,-" ] && [ "$again" = "pins text,set" ] && echo yes)" "$first / $again"
out=$(run body "tool select; key a command; key delete; tool cast; castas MAYA; click 640 300; tool camera; down 420 560; drag 440 550; up 440 550; tool select; key escape; pickkind camera; aimat cast; chrome; report; act body fso-sony-venice; report" 8)
keep body
check "a camera's bar offers Shot, Camera and Lens, and it shows the Alexa Mini until picked" "$(chrome "$out" 1 | grep -q 'actions \[shot,camera,lens,' && echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  camera ' | grep -q 'body fso-arri-alexa-mini' && echo yes)" "$(chrome "$out" 1)"
check "…Sony Venice picked: that body, at its own size" "$(echo "$out" | awk '/^drive:/{k++} k==2' | grep '^  camera ' | grep -q 'size 0.33x0.27 aim cast body fso-sony-venice' && echo yes)" "$(echo "$out" | grep '^  camera ')"
check "…aimed at a person and picked, the distance is written on its aim line" "$(echo "$out" | awk '/^drive:/{k++} k==1' | grep '^  camera ' | grep -qiE 'distance "[0-9]+ ft( [0-9]+ in)?"' && echo yes)" "$(echo "$out" | grep '^  camera ' | head -1)"

# 11 — a film a newer Shotlister wrote: looked at, never drawn on
mkdir -p "$WORK/ro" && cp -R studio/fixtures/Daybreak.shotlist "$WORK/ro/"
sed -i '' 's/"format": *1/"format": 0/' "$WORK/ro/Daybreak.shotlist/manifest.json"
KEEP="$FILM"; FILM="$WORK/ro/Daybreak.shotlist"
out=$(run readonly "tool wall; click 300 200; click 700 200; key return; report")
FILM="$KEEP"
check "a read-only film's plan cannot be drawn on" "$(echo "$out" | grep -q '^drive: 0 els; picked 0; tool select' && echo yes)" "$(echo "$out" | grep '^drive:')"

# 12g — the picked bar (design/26, his pick 2026-10-02): a zoom's Focal in
# the bar, the bar folding into More in a narrow window rather than jumping
# over the zoom, and Swap keeping a lamp where it stands.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
cam="tool select; key a command; key delete; tool camera; down 600 420; drag 620 400; up 620 400; tool select; key escape; pickkind camera"
out=$(run zoombar "$cam; lensname 24-70mm; chrome; focal 50; chrome" 8)
check "a zoom camera's bar adds Focal, and Focal sets where it is" "$(chrome "$out" 1 | grep -q 'actions \[shot,camera,lens,focal,name,piecenote,more\] picked camera' && chrome "$out" 1 | grep -q 'fold 0' && chrome "$out" 2 | grep -q 'focal 50 ' && echo yes)" "$(chrome "$out" 1) / $(chrome "$out" 2)"
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
# The window cannot be made narrower than its content now (it keeps its
# width whatever SHOTLISTER_WIDTH asks), so the room is taken the way a
# user takes it: Layers on the left and Details on the right shorten the plan.
out=$(run narrowbar "$cam; lensname 24-70mm; keys 1 command control; keys 2 command control; wait 0.8; chrome" 8)
check "…with Layers and Details open the plan is short and the bar folds into More instead" "$(chrome "$out" 1 | grep -qE 'fold [1-3] ' && echo yes)" "$(chrome "$out" 1)"
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run swapbar "tool select; key a command; key delete; tool light; arm tungsten-fresnel-1k; click 600 420; tool select; pickkind light; report; swap fso-arri-m18; report" 8)
l1=$(nth "$out" 1 "^  light "); l2=$(nth "$out" 2 "^  light ")
check "Swap makes a lamp another, where it stands and as it turns" "$(echo "$l2" | grep -q 'sym fso-arri-m18' && [ "$(xy "$l1")" = "$(xy "$l2")" ] && [ "$(echo "$l1" | grep -o 'rot [0-9.-]*')" = "$(echo "$l2" | grep -o 'rot [0-9.-]*')" ] && echo yes)" "$l1 → $l2"

# 12h — Backdrop (his ask, 2026-10-02): the plan's paper on this Mac's screen,
# dim to white, the grid with it. A checking run shares his Studio's
# preferences, so his own setting is put back the moment the block ends.
rm -rf "$FILM"; cp -R studio/fixtures/Daybreak.shotlist "$WORK/"
out=$(run backdrop "$cam; act backdrop 0; chrome; act backdrop 1; chrome" 6)
defaults delete "$PREFS" diagramBackdrop >/dev/null 2>&1   # this run's own copy only
check "Backdrop dims the plan's paper and brightens it to white" "$(chrome "$out" 1 | grep -q 'backdrop 0.00 paper #8C8D8E' && chrome "$out" 2 | grep -q 'backdrop 1.00 paper #FFFFFF' && echo yes)" "$(chrome "$out" 1 | grep -o 'backdrop.*paper #[0-9A-F]*') / $(chrome "$out" 2 | grep -o 'backdrop.*paper #[0-9A-F]*')"

# 10 — on paper: one page with the plan and its key
gone
SHOTLISTER_STAY=8 "$APP" --project "$FILM" --screen "$SCREEN" --place diagram --scene 34 \
  --exportpdf "$WORK/d.pdf" diagram --snapshot "$WORK/pdf.png" >"$WORK/pdf.log" 2>&1
check "the scene's PDF carries its diagram page" "$(grep -qE 'exported: yes pages: [1-9]' "$WORK/pdf.log" && echo yes)" "$(grep exported "$WORK/pdf.log")"

# 11 — measuring a table's edge (his report, 2026-10-06): a ruler's marker
# pressed on a table stays where it was pressed, never jumps to the table's
# middle; with Snap on it holds on to a person, with Snap off to nothing; and
# Set has a Cast tool, with the person drawn at full strength there.
table='{"op":"add","els":[{"kind":"set","id":"tbl","sym":"table","x":1.0,"y":3.66,"w":1.6,"h":0.9}]}'
ruler="tool cast; castas MAYA; click 900 600; tool measure; down 640 600; drag 780 600; drag 900 600; up 900 600; tool select; report"
out=$(run edge "wait 1; setting snap true; op $table; $ruler" 7)
check "a ruler pressed on a table starts where it was pressed, not at its middle" "$(echo "$out" | grep '^  measure ' | grep -q ' at 0\.6' && echo yes)" "$(echo "$out" | grep '^  measure ')"
check "…and with Snap on its far end holds on to the person" "$(echo "$out" | grep '^  measure ' | grep -q 'locks -,cast' && echo yes)" "$(echo "$out" | grep '^  measure ')"
out=$(run edgeoff "wait 1; setting snap false; op $table; $ruler" 7)
check "with Snap off a ruler holds on to nothing" "$(echo "$out" | grep '^  measure ' | grep -qE 'locks *(\[|$)' && echo yes)" "$(echo "$out" | grep '^  measure ')"

echo
# Send to Set / Send to Plot (his ask, 2026-10-17): several pieces moved in
# one step, where they stood, and one ⌘Z puts them back.
out=$(run sendlayer 'op {"op":"add","els":[{"kind":"set","sym":"sofa","x":1,"y":2,"label":"Hero sofa"},{"kind":"light","sym":"","mark":"chevron","x":3,"y":3},{"kind":"text","text":"Hi","x":0,"y":0}]}; wait 0.5; tool select; pickall; report; sendlayer set; wait 0.4; report; key z command; wait 0.4; report')
setn() { echo "$out" | awk -v k="$1" '/^drive:/{n++} n==k' | grep -E '^  (light|text) ' | grep -c ' in set'; }
check "Send to Set moves the picked lamp and words to Set" "$([ "$(setn 2)" = 2 ] && echo yes)" "$(setn 2) of 2 in Set"
check "…and one ⌘Z puts them back in Plot" "$([ "$(setn 3)" = 0 ] && echo yes)" "$(setn 3) still in Set"

echo
# Hide from Diagrams (his ask, 2026-10-17): scenes he picks leave the Diagram's
# list only. The "N Hidden" line counts them with Hide Empty's, lists them
# again when opened, Show puts one back for good, the scene he is on always
# stays, and the shot list's scenes are untouched. The film holds it.
out=$(run hidescenes "wait 1; scenelist; hidescenes 33,35; scenelist; revealhidden on; scenelist; showscenes 33; scenelist; revealhidden off; scenelist; hidescenes 34; scenelist; hideempty on; scenelist; hideempty off" 8)
sl() { echo "$out" | grep '^scenelist:' | sed -n "${1}p"; }
check "the Diagram lists every scene to start with" "$(sl 1 | grep -q 'all 4 listed \[33,34,35,54\] hidden 0' && echo yes)" "$(sl 1)"
check "Hide from Diagrams takes two picked scenes off the list, and counts them" "$(sl 2 | grep -q 'listed \[34,54\] hidden 2 byhand \[33,35\]' && echo yes)" "$(sl 2)"
check "…the shot list's scenes are untouched" "$(sl 2 | grep -q 'all 4 ' && echo yes)" "$(sl 2)"
check "…the \"N Hidden\" line lists them again" "$(sl 3 | grep -q 'listed \[33,34,35,54\] hidden 2 .* open true' && echo yes)" "$(sl 3)"
check "…Show puts one back for good" "$(sl 4 | grep -q 'hidden 1 byhand \[35\]' && sl 5 | grep -q 'listed \[33,34,54\] hidden 1 byhand \[35\] open false' && echo yes)" "$(sl 4) / $(sl 5)"
check "…the scene he is on always stays" "$(sl 6 | grep -q 'listed \[33,34,54\] hidden 1 byhand \[34,35\]' && echo yes)" "$(sl 6)"
check "…the line counts Hide Empty's and his own together" "$(sl 7 | grep -q 'listed \[34\] hidden 3 ' && echo yes)" "$(sl 7)"
out=$(KEEPFILM=1 run hidekept "wait 1; scenelist" 6)
check "…and the film remembers it after a relaunch" "$(sl 1 | grep -q 'listed \[33,34,54\] hidden 1 byhand \[34,35\]' && echo yes)" "$(sl 1)"

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
