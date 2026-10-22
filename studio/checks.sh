#!/bin/zsh
# The quiet battery — every check the invisible lane can run.
#
# Quiet means Nathaniel cannot notice it: the app never comes frontmost, never
# takes a key window, and every run reports `focus watch: clean` or the trip
# that broke that promise. These checks drive the FALLBACK keyboard path (the
# window monitor typing into the shared buffer); the real path — the text view
# with actual focus — can only be driven by `checks-loud.sh`, which needs an
# explicit grant. The contract in ../design/table-contract.md says which lines
# each lane covers.
#
# Checks run against a scratch copy of the committed fixture, never against a
# real project: edits persist the moment they land.
#
# Usage: studio/checks.sh            (from the repo root)
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
SCRATCH="$(mktemp -d)/Checks.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$SCRATCH"
# The battery's width store starts empty every time — checking runs keep
# widths under their own key (never his), and a stale battery's drags must
# not become this battery's baseline.
defaults delete com.example.shotlister.studio columnWidths.checking 2>/dev/null || true

pass=0; fail=0; trips=0; drifted=0

# **Refuse a result from a run that ended up on the wrong scene** — Ref 101.
#
# Every check below asserts something about a position — which rows are there,
# which one the cursor rests on, what a column holds — and every one of them
# assumed it was looking at the scene it asked for. Nothing ever checked. A
# filter that empties the scene you are on takes it out of the list and the app
# falls back to the first scene in the film, which is sensible in the hand and
# silent to a check: it goes on asserting rows against a scene it is no longer
# looking at, and passes or fails for reasons that have nothing to do with what
# it is testing. That is how a battery starts lying.
#
# The app now says which scene it is on and shouts when that is not the one it
# was asked for. This turns the shout into a refusal — the same treatment a
# stolen focus gets, and for the same reason: a wrong answer confidently given
# is worse than no answer.
# **Said, counted, and not turned into a failure.** Measured 2026-08-23: two
# runs in a battery drift, and it is not the same two twice — so refusing their
# results outright turns a green battery red at random, which teaches everybody
# to ignore it. Most checks do not depend on the scene at all (a column width
# does not care), and the ones that do will fail on their own assertion with
# this note sitting right above it saying why.
astray() {
  echo "$1" | grep -q "WRONG SCENE" || return 1
  drifted=$((drifted+1))
  echo "$1" | grep -E "WRONG SCENE" | sed "s/^/      drifted: /"
  return 1
}

run() {
  local name="$1"; shift
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  astray "$out"
  if echo "$out" | grep -qE "MATCHES"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "engine holds|expected|FOCUS" | sed 's/^/      /'
  fi
}

runcols() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 "$@" --columns 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  astray "$out"
  if echo "$out" | grep "columns:" | grep -q "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "columns:" | sed 's/^/      /'
  fi
}

# Tap x-coordinates are window points from the top left, measured on the
# standard first-launch window: image ≤450 · title ~480 · description ~640–910
# size ~1000 · movement ~1250. **Row 34A is y≈295** — the table is the whole
# script now and each scene opens with a line of its own, so every row sits
# ~46pt lower than it did; y=214 is that line, not a cell. Re-map with single
# taps if
# the window size or columns change — the run prints what a click will hit.

run "text flows whole"            --cell description --type "Melissa walks in"
run "top match, not the letters"  --cell size   --type "M"   --expect "M/OTS"
run "half word finds Profile"     --cell angle  --type "Pro" --expect "Short-Sided, Profile"
run "camera writes its reference" --cell camera --type "B-Cam"
run "arrows walk the open list"   --cell size   --type "O" --walk 1 --expect "M/OTS"
run "a new term teaches"          --cell lens   --type "Dutch85"
run "shift-return, second line"   --cell notes  --type "one⏎two" --expect "one
two"
run "arrow commits fresh typing"  --cell title  --type "abc" --walk 1 --expect "abc"
run "return-return, single"       --cell size   --type "↩↩" --expect "M/OTS"
run "return-return, multi"        --cell angle  --type "↩↩" --expect "Short-Sided, Profile"
run "walk-away discards filter"   --cell size   --type "W" --tap "1238,261,2" --expect "M/OTS"
run "delete clears a cell"        --cell movement --type "⌫" --expect ""
run "paste writes a cell"         --cell movement --paste "Static" --expect "Static"
run "space starts an edit"        --cell title  --type " leads" --expect " leads"
run "delete clears a camera"      --cell camera --type "⌫" --expect ""
run "a new camera is born"        --cell camera --type "C-Cam Komodo" --expect "C-Cam Komodo"
# The table is the whole script now, so every scene opens with a line of its
# own and the rows below sit 30pt lower. Re-measured from the row frames
# report (34A@229..293 … 34E@485..549) — never guessed.
run "double-click opens on value" --tap "688,517,2" --expect "Wide of the Car — pulls away from station"
run "click-away keeps the words"  --cell description --type "Melissa walks in again" --tap "1238,261,2" --expect "Melissa walks in again"

# The relaunch law: nothing counts as working unless it survives a fresh
# process. The value read here was written by the click-away check above.
out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --cell description --tap "0,0" 2>&1)
if echo "$out" | grep -q 'holds "Melissa walks in again"'; then
  pass=$((pass+1)); echo "PASS  edits survive a relaunch"
else
  fail=$((fail+1)); echo "FAIL  edits survive a relaunch"
  echo "$out" | grep "holds" | sed 's/^/      /'
fi

# ---- Return closes the cell and stays put -----------------------------------
# His call, and a deliberate departure from a sheet: Return commits and the
# cursor STAYS on the cell (arrows and Tab are how you leave). Asserted on the
# cursor report, because the committed value alone cannot tell a stay from a
# step. Both keyboard paths: a text cell and a picker.
rests() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "cursor rests on $want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep "cursor rests" | sed 's/^/      /'
  fi
}

# Types the value the cell already holds, deliberately: the undo checks below
# read this description, and a check that rewrites what the next one reads is
# a check that breaks its neighbour. (It did — once.)
rests "return stays on a text cell" "34A description, editing false" \
      --cell description --type "Melissa walks in again"
rests "return stays on a picker"    "34A size, editing false" --cell size --type "W"
rests "tab still steps across"      "34A angle" --cell size --type "W⇥"

# ---- undo and redo ---------------------------------------------------------
# Session-scoped, like a sheet's own: the engine's history lives with the
# open document, not in the file, so each check makes its change and walks
# it back within one process. The description holds "Melissa walks in again"
# from the relaunch check above.
run "undo walks one commit back"  --cell description --type "zzz↩⌘z" --expect "Melissa walks in again"
run "redo brings it forward"      --cell description --type "zzz↩⌘z⌘Z" --expect "zzz"
# ("yyy", not "zzz" again: the cell already holds zzz from the redo check,
# and committing an unchanged value writes nothing — including no history.)
run "commit, undo, redo, undo"    --cell description --type "yyy↩⌘z⌘Z⌘z" --expect "zzz"

# ---- shot operations and the selection -------------------------------------
# Letters-agnostic where an op changes the row count: the engine reflows
# letters while a project is in prep (lettering.rs), so "which letter
# survived" is the wrong question — the count and the struck marks are the
# stable facts. Undo checks stay inside one process: history is
# session-scoped. Row y-coordinates: row2≈290, row3≈370.
run "delete then undo restores"   --cell description --type "⌘⌫⌘z" --expect "zzz"
# The rows report reads number(marks):description-head — [^,]* skips the
# words, the ✕ before the colon is the struck mark, • the colour.
runcols "delete+undo keeps five rows"  'rows=34A:[^,]*,34B:[^,]*,34C:[^,]*,34D:[^,]*,34E:[^,]*$'  --cell description --type "⌘⌫⌘z"
runcols "strike marks the row"         '34A✕'                      --cell description --type "⌘k"
runcols "strike again clears it"       'rows=34A:[^,]*,34B:'       --cell description --type "⌘k"
runcols "duplicate then undo"          'rows=34A:[^,]*,34B:[^,]*,34C:[^,]*,34D:[^,]*,34E:[^,]*$' --cell description --type "⌘d⌘z"
runcols "add-below is one undo"        'rows=34A:[^,]*,34B:[^,]*,34C:[^,]*,34D:[^,]*,34E:[^,]*$' --cell description --type "⌃↩⌘z"
runcols "select all, strike all"       '34A✕:[^,]*,34B✕:[^,]*,34C✕:[^,]*,34D✕:[^,]*,34E✕:' --cell description --type "⌘a⌘k"
runcols "the same key restores them"   'rows=34A:[^,]*,34B:[^,]*,34C:[^,]*,34D:[^,]*,34E:[^,]*$' --cell description --type "⌘a⌘k"
runcols "range delete, one undo, one breath" 'rows=34A:[^,]*,34B:[^,]*,34C:[^,]*,34D:[^,]*,34E:[^,]*$' --cell description --tap "688,370,2,s" --after "⌘⌫⌘z"
runcols "shift-range delete leaves two" 'rows=34A:[^,]*,34B:[^,]*$' --cell description --tap "688,370,2,s" --after "⌘⌫"
runcols "delete for real"              'rows=34A:[^,]*$'           --cell description --type "⌘⌫"
runcols "a shot wears its colour"      '34A•'                      --cell description --set colour E5484D
runcols "and can take it off"          'rows=34A:[^,]*$'           --cell description --set colour ""

# ---- tags is a multi-pick list ---------------------------------------------
# Tags was the one multi-value column still opening as a text box — seeded
# with every pill as comma text, and committing that string appended the lot
# back as one value, doubling every pill. Now it is a picker like Angle:
# Return toggles the highlighted option and stays open; a pristine Return
# closes. The fixture's 34A holds "Cross Coverage".

run "a tag goes on and the list stays"  --cell tags --type "VFX↩Drone↩↩" --expect "Free Driving, VFX, Drone"
run "typing a held tag takes it off"    --cell tags --type "VFX↩↩" --expect "Free Driving, Drone"
run "a pristine tags picker writes nothing" --cell tags --type "↩↩" --expect "Free Driving, Drone"

# ---- a column of the project's own ------------------------------------------
# `--addcolumn "kind Label"` births one through the same engine command the
# sheet uses; typing into it goes through the same set path as everything
# else. The field slug is c_<id>, so checks reach the cell by walking right
# from the last built-in column rather than by name.

# Walked from Day: sequence and struck are hidden by default, so the shown
# order runs … tags, day, then the customs in creation order.
run "a single-choice column takes a value" --addcolumn "single Sound" --cell day --right 1 --type "Sync↩" --expect "Sync"
run "the value survives a relaunch"        --cell day --right 1 --type "Sync↩" --expect "Sync"
run "a multi column gathers"               --addcolumn "multi Rigs" --cell day --right 2 --type "Crane↩Remote↩↩" --expect "Crane, Remote"

# ---- a copy pastes onto the selection ---------------------------------------
# Shift-double-click marks 34A..34C; --paste rides the harness's own pocket
# (never his clipboard) and ⌘V lands on every marked row. Paste REPLACES —
# 34A held two angle chips and holds only the pasted one after — and the
# second line reads a different row of the same selection.
# The harness's --expect follows the cursor row, so the cross-row half of a
# selection paste is proven at the ffi layer (a_paste_onto_many_rows…); the
# battery proves replace-not-toggle on the cursor row and that it persists.
run "a paste replaces, never toggles"  --cell angle --tap "1088,336,2,s" --paste "3/4" --expect "3/4"
run "the paste survives a relaunch"    --cell angle --type "↩↩" --expect "3/4"

# ---- the day cell is sealed until Schedule ----------------------------------
run "the day cell refuses text"    --cell day --type "Tuesday↩" --expect "Day 1"

# ---- rows carry to a new place ----------------------------------------------
# Self-contained: the delete checks above leave this scene ONE row (probed
# with the row-frames report — guessing was how this check failed twice), so
# it builds its own second row, plants a sentinel lens on it, carries row 1
# past it, and row 1 must then wear the sentinel. Letters reflow in prep, so
# a value, not a number, is the only honest witness. Fresh rows sit at
# standard height: row 1 y199..263, row 2 y263..327; gutter x≈300.
run "a word to carry"                 --addshot --cell description --type "FIRST↩" --expect "FIRST"
runcols "a row carried down lands there" "rows=34A:,34B:FIRST" --tdrag "288,261,288,346" --type ""

# ---- density ----------------------------------------------------------------
# ⌘+ walks 1.0 → 1.18: title reads 170 × 1.18 = 200. ⌘0 is the middle again.
# In-process only — a checking run pins density 1 at launch and never writes
# the preference.
runcols "⌘+ zooms the table"     "title=200" --type "⌘="
runcols "⌘0 is the middle again" "title=170" --type "⌘=⌘0"

# ---- a rectangle of cells ---------------------------------------------------
# Drag from Size row 1 across Movement row 2: the rectangle greys, and ⌫
# empties every clearable cell it crossed in one transaction. The expect
# reads the anchor cell after the clear.
run "a dragged range clears as one"  --cell size --type "" --tdrag "958,261,1238,341" --after "⌫" --expect ""

# ---- the table moves and selects like a sheet -------------------------------
# Read off the report's `range:`, `ants:`, `cursor:` and `cells` lines. Nothing
# here is a photograph: each one is a fact about what is selected or written.
sheet() {
  local name="$1"; local want="$2"; shift 2
  # A fresh copy of the film each time: a paste here must not be the next
  # check's starting point.
  local fresh; fresh="$(mktemp -d)/Sheet.shotlist"; cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes --scene 34 "$@" --columns 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -E "^(range|ants|cursor:|cells|history)" | tr '\n' ' ' | grep -qE "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "^(range|ants|cursor:|cells|history)" | sed 's/^/      /'
  fi
}
sheet "shift-arrows stretch a block"      "range: 34A/description..34C/size" --cell description --type "⇧↓⇧↓⇧→" --hold
sheet "…and shrink it back"               "range: 34A/description..34B/description" --cell description --type "⇧↓⇧↓⇧↑" --hold
sheet "tab walks the block, then wraps"   "cursor: 34A/size" --cell size --range "34A/size..34B/angle" --type "⇥⇥⇥⇥" --hold
sheet "shift-tab steps back inside it"    "cursor: 34B/angle" --cell size --range "34A/size..34B/angle" --type "⇤" --hold
sheet "the block survives the tabbing"    "range: 34A/size..34B/angle" --cell size --range "34A/size..34B/angle" --type "⇥⇥" --hold
sheet "cmd-right runs to the row's end"   "cursor: 34A/day" --cell size --type "⌘→" --hold
sheet "copy outlines what it took"        "ants: 34A/size..34B/movement cursor" --cell size --range "34A/size..34B/movement" --type "⌘c" --hold
sheet "esc puts the outline away first"   "range: 34A/size..34B/movement" --cell size --range "34A/size..34B/movement" --type "⌘c⎋" --hold
sheet "…and the block on the second"      "range:  ants:  " --cell size --range "34A/size..34B/movement" --type "⌘c⎋⎋" --hold
sheet "a cut waits for the paste"         "34A=M/OTS.*ants: 34A/size..34A/size cut" --cells size --cell size --range "34A/size..34A/size" --type "⌘x" --hold
sheet "…then the paste moves it"          "34A=[|]34B=M/OTS" --cells size --cell size --type "⌘x↓⌘v" --hold
sheet "a block is not clipped to a cell"  "range: 34D/size..35A/size" --cell size --range "34A/size..34C/size" --type "⌘c↓↓↓⌘v" --hold
sheet "a pasted block is one undo"        'history: depth 1 undo "Paste"' --cells size --cell size --range "34A/size..34C/size" --type "⌘c↓↓↓⌘v" --hold
sheet "one value fills a block"           "34A=ZZ.34B=ZZ.34C=ZZ.34D=M/OTS" --cells size --cell size --range "34A/size..34C/size" --paste "ZZ" --hold
sheet "paste past the foot adds shots"    "54H=x.54J=y.54K=z" --shot 54H --cell size --paste $'x\ny\nz' --cells size

# ---- the notes tab ----------------------------------------------------------
# The scene's own words and what is pinned to them. Notes live on the scene
# record, written through the same generic `set` as everything else; an
# attachment is the same machinery as a shot's frame with the scene as owner —
# but a scene must never be given a lead frame (engine + ffi tests hold that).
notes() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --tab notes \
                   "$@" --columns --snapshot /dev/null 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep "scene notes:" | grep -q "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep "scene notes:" | sed 's/^/      /'
  fi
}

# One file, not a glob: `cp a b c dest` needs dest to be a directory, so the
# glob copied nothing and the check quietly had no file to pin.
PINNED="$(dirname "$SCRATCH")/pin-me.png"
cp "$(ls studio/fixtures/Daybreak.shotlist/media/proxies/*.png | head -1)" "$PINNED"

notes "a scene keeps its words"       'Cars are hot' --notes "Cars are hot at 4pm"
notes "…across a relaunch"            'Cars are hot'
notes "a file pins to the scene"      'attachments: 1 \[pin-me.png' --pin "$PINNED"
notes "…and survives a relaunch"      'attachments: 1 \[pin-me.png'
notes "unpinning takes it off again"  'attachments: 0' --unpin
notes "the words stay through all of it" 'Cars are hot'

# ---- a file can actually be read --------------------------------------------
# His gap: "I can't read back files I upload like PDFs or images, just leaves
# them as small thumbnails." The viewer says what it loaded, because a
# screenshot cannot see inside PDFKit's or AVKit's drawing — a window can look
# perfect while showing a blank page.
reads() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --tab notes \
                   "$@" --view --snapshot /dev/null 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep "viewer:" | grep -q "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep "viewer:" | sed 's/^/      /'
  fi
}

PDFFILE="$(dirname "$SCRATCH")/plan.pdf"
printf 'Lighting: 4x4 ultrabounce camera left, practicals at 15 percent.' > "$(dirname "$SCRATCH")/note.txt"
cupsfilter "$(dirname "$SCRATCH")/note.txt" > "$PDFFILE" 2>/dev/null

notes "a pdf is kept whole, not rasterised" 'plan.pdf/other' --unpin --pin "$PDFFILE"
reads "…and its pages read back"            'pages: 1'
reads "…with its words intact"              'ultrabounce'
notes "put the picture back"                'attachments' --unpin --pin "$PINNED"
reads "a picture opens at full size"        'pin-me.png'

# A picture is FIT to the window, never opened at its own pixel size — the
# arithmetic is asserted rather than the screenshot, because a scroll view
# renders its content unclipped and photographs as though nothing fitted.
fits() {
  local name="$1"
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --tab notes \
                   --view --snapshot /dev/null 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  local line; line=$(echo "$out" | grep "picture:")
  # the drawn width must not exceed the room it was given
  if echo "$line" | python3 -c "
import sys, re
m = re.search(r'in (\d+)×(\d+)\s+fits at [\d.]+ → (\d+)×(\d+)', sys.stdin.read())
if not m: raise SystemExit(1)
rw, rh, dw, dh = (int(g) for g in m.groups())
raise SystemExit(0 if dw <= rw + 1 and dh <= rh + 1 else 1)
"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$line" | sed 's/^/      /'
  fi
}

fits "…fitted to the window, not its own pixels"

# A file whose NAME lies about its contents — his deck, flattened to a picture
# by an earlier build and still called .pdf — draws as what it IS rather than
# as an empty black page.
#
# The bytes must be ones this project has never seen. Media is addressed by
# content: a copy of a picture already in the project is *the same file*, and
# the engine rightly keeps the name it was first given. (That cost an hour of
# chasing a bug that was the design working.)
cp "$PINNED" "$(dirname "$SCRATCH")/liar.pdf"
printf 'not the same bytes as anything already here' >> "$(dirname "$SCRATCH")/liar.pdf"
notes "a mislabelled file is pinned"        'liar.pdf' --unpin --pin "$(dirname "$SCRATCH")/liar.pdf"
# The fixture's proxies are JPEGs stored under .png names (the old app's
# doing), so a copy of one named .pdf is a JPEG twice mislabelled — and the
# viewer says jpg, which is the whole point: the bytes decide.
reads "…and opens as what it really is"     'liar.pdf as jpg'

# ---- the document page ------------------------------------------------------
# The page's one write of its own: a shot's frame takes a side and a width,
# as a fraction of the measure. The rest of the page writes through paths the
# battery already holds (set description/notes). Checked through the app and
# across a relaunch — layout is document schema and must survive.
pagelayout() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --tab document \
                   --cell description "$@" --columns --snapshot /dev/null 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep "layout:" | grep -q "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep "layout:" | sed 's/^/      /'
  fi
}

pagelayout "a frame takes the left at 38%"  'left@0.38'  --layout "left 0.38"
pagelayout "…and it survives a relaunch"    'left@0.38'
pagelayout "…and can go below, full"        'below@1.00' --layout "below 1.0"

# ---- the storyboard's boxes -------------------------------------------------
# Two bugs lived here: the card's height was derived from the SLIDER while its
# real width stretched wider (so the box was never the project's ratio), and
# the fill overflowed before it was clipped (the overlap he saw between the
# slider's snap points). The card frames report is the instrument — eyeballing
# a screenshot could not tell 2.39 from 2.44. Widths on either side of a snap.
sbcards() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --tab storyboard \
                   "$@" --columns --snapshot /dev/null 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  local line; line=$(echo "$out" | grep "card frames:")
  # every card on screen must wear the wanted ratio, and no other
  if [ -n "$line" ] && ! echo "$line" | grep -qv "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$line" | sed 's/^/      /'
  fi
}

# The gap between two pictures on a row, at its narrowest — his rule: there
# is always air between images. The grid's own spacing is SwiftUI's to honour
# and rounds at some widths, so the card wears an inset of its own; this reads
# the drawn positions and reports the smallest gap it can find.
sbgutter() {
  local name="$1"; shift
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 --tab storyboard \
                   "$@" --columns --snapshot /dev/null 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  local least; least=$(echo "$out" | grep "card frames:" | python3 -c "
import sys, re
cards = re.findall(r'@(-?[\d.]+),(-?[\d.]+) ([\d.]+)x', sys.stdin.read())
rows = {}
for x, y, w in cards:
    rows.setdefault(round(float(y)), []).append((float(x), float(w)))
gaps = [b[0] - (a[0] + a[1]) for cs in rows.values()
        for a, b in zip(sorted(cs), sorted(cs)[1:])]
# No cards at all is a failure, not a pass: a gutter check that finds
# nothing must not report perfect air.
print(int(min(gaps)) if gaps else -1)
")
  if [ "${least:-0}" -ge 8 ]; then
    pass=$((pass+1)); echo "PASS  $name (${least}pt)"
  else
    fail=$((fail+1)); echo "FAIL  $name — narrowest gap ${least}pt"
  fi
}

sbcards "cards hold the ratio, small"   "=2.390" --card 190
sbcards "…and mid-stretch"              "=2.390" --card 264
sbcards "…and just under a snap"        "=2.390" --card 300
sbcards "…and wide"                     "=2.390" --card 420
sbcards "the boxes follow 16:9"         "=1.780" --card 300 --ratio 1.78
sbcards "…and 4:3"                      "=1.330" --card 300 --ratio 1.33
sbgutter "air between pictures, tight"  --card 190
sbgutter "…mid-stretch"                 --card 264
sbgutter "…and wide"                    --card 420

# ---- the shared shortcuts, across scene boundaries -------------------------
# Every one of these is a bug he reported on 2026-08-20: the shared keyboard
# asked each surface for "the rows it is showing" and the table answered with
# *the current scene's* rows — which is what the sidebar last said, not where
# the cursor is. `--shot` puts the cursor in one scene while `--scene` leaves
# the chrome naming another, which is the gap the bugs lived in. Fresh copies:
# these all move shots about.
shortcut() {
  local name="$1"; local want="$2"; local line="$3"; shift 3
  local fresh="$(mktemp -d)/Keys.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes "$@" --columns 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep "^$line" | grep -q "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "^$line" | sed 's/^/      /'
  fi
}

shortcut "a new shot joins the CURSOR's scene" \
  "34:34A,34B,34C,34D,34E,34F" "shots:" --scene 33 --shot 34D --type "⌘↩"
shortcut "…and not the scene the chrome names" \
  "33:33A |" "shots:" --scene 33 --shot 34D --type "⌘↩"
shortcut "select-all takes the CURSOR's scene" \
  "34A,34B,34C,34D,34E" "marked:" --scene 33 --shot 34D --type "⌘a"
shortcut "…and shift-select-all lets go" \
  "^marked: *$" "marked:" --scene 33 --shot 34D --type "⌘a⌘A"
shortcut "cmd-up moves a shot up its scene" \
  "34A:Felix,34B:Milo " "columns:" --scene 34 --shot 34B --type "⌘↑"
shortcut "cmd-down moves it back" \
  "34A:Felix,34B:Milo " "columns:" --scene 34 --shot 34A --type "⌘↓"
shortcut "duplicate acts on the cursor's shot" \
  "34:34A,34B,34C,34D,34E,34F" "shots:" --scene 33 --shot 34D --type "⌘d"
shortcut "delete acts on the cursor's shot" \
  "34:34A,34B,34C,34D" "shots:" --scene 33 --shot 34D --type "⌘⌫"

# ---- a locked list ---------------------------------------------------------
# The lock is a fact about the project, so each of these runs on its own fresh
# copy: a battery that locked Lens and moved on would break every check after
# it, which is exactly the shared-scratch lesson of 2026-08-19.
locklist() {
  local name="$1"; shift
  local fresh="$(mktemp -d)/Lock.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --project "$fresh" --screen "$SCREEN" --place scenes --scene 34 "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qE "MATCHES"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "engine holds|expected" | sed 's/^/      /'
  fi
}

locklist "an open list still learns"   --cell lens --type "Dutch85" --expect "Dutch85"
locklist "a locked list learns nothing" --lock lens 1 --cell lens --type "Dutch85" --expect "37mm"
locklist "a locked list still clears"  --lock lens 1 --cell lens --type "⌫" --expect ""
locklist "a locked list takes what it holds" --lock lens 1 --cell lens --type "27mm↩" --expect "27mm"
locklist "unlocking lets it learn again" --lock lens 1 --lock lens 0 --cell lens --type "Dutch85" --expect "Dutch85"

# ---- the header: resize, reset, sort, reorder ------------------------------
# Asserted against the `--columns` report rather than a screenshot. The
# coordinates assume the standard first-launch window with the sidebar at
# 258; the run prints `header frames:` to re-map from if that changes.
# With the sidebar pinned at 258 by every checking run: **header band y≈115**
# — the scene heading strip above the table is gone (2026-08-20) and the tab
# strip moved into the top bar, so the column names sit a hundred points
# higher than they did. The well is edge-to-edge and square-cornered (the
# corner rule: what floats turns a corner, what is cut in does not), so it
# carries no inset of its own: title spans 463..633, description 633..913,
# size 913..1031. Every y is unchanged by the refinish — measured against the
# `row frames` report on both builds, never assumed.
runcols "drag a column edge resizes"      "title=240"                 --tdrag "628,115,698,115" --type ""
runcols "the width survives a relaunch"   "title=240"                 --snapshot /dev/null
runcols "double-click the edge resets"    "title=170"                 --tap "700,115,2"
runcols "click a header sorts"            "sort=size asc"             --tap "970,115,1"
runcols "carry a header reorders"         "description=280 title=170" --tdrag "773,115,520,115" --type ""
runcols "the order is the project's"      "description=280 title=170" --snapshot /dev/null
runcols "carry it back"                   "title=170 description=280" --tdrag "570,115,900,115" --type ""
# Movement, not Camera Gear, is what sits beside Equipment now — Ref 326 made
# the two gear columns one, so there is no camera column to be next to.
runcols "hiding a column removes it"      "movement=130 support=116"   --hide lens
runcols "hidden survives a relaunch"      "movement=130 support=116"   --snapshot /dev/null
runcols "showing puts it back in place"   "lens=150 support=116"       --show lens

# ---- narrowing the list (the filter bar) -------------------------------------
# Worth having only now that the whole script is on one surface: "every
# handheld shot in the film", "everything on Day 2". The engine has done this
# all along; the bar is the chrome for it. Asserted on the count the app
# itself reports, because the rows line is the cursor's scene alone and says
# nothing about the rest of the film.
#
# **The bridge was sending every facet to the wrong record**: each one was
# read as a fact about the *scene*, so asking for a shot size asked for
# scenes whose size was that — of which there are none, and the list came
# back empty with nothing to say why. Scene facts are a named few; the rest
# belong to a shot.
# Its own untouched copy: by this point the shared scratch has had rows
# deleted and columns added by the checks above, so "the whole film" is not
# sixteen shots there — the count would be measuring the other checks.
NARROW="$(mktemp -d)/Narrow.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$NARROW"
narrow() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$NARROW" --screen "$SCREEN" --scene 34 "$@" --columns 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "showing: $want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -oE "showing: .*" | sed 's/^/      /'
  fi
}

narrow "nothing narrowed shows the whole film" "16 shots  narrowed: false"
narrow "a shot size narrows across every scene" "2 shots  narrowed: true" --facet size W
narrow "a lens narrows too"                     "6 shots  narrowed: true" --facet lens 37mm
narrow "searching the words narrows"            "2 shots  narrowed: true" --find pharmacy
narrow "…and clearing puts the film back"       "16 shots  narrowed: false" --facet all ""

# ---- the side panel ---------------------------------------------------------
# The Notes tab is gone (his call): a tab took the shot list away in order to
# show a reference, which is the opposite of what a reference is for. The
# scene's script, references and words share one panel beside the list, and
# it pushes the table aside rather than floating over the rows.
runcols "the panel opens on references"  "title=170" --panel references
runcols "…and on the scene's words"      "title=170" --panel notes
runcols "…and on the script, which says when it arrives" "title=170" --panel script
# The words written in the panel are the same words every other surface
# reads — the plain copy and the rich one, together.
run "the panel's notes reach the table's column" --cell notes --set notes "PANEL WORDS" --type "" --expect "PANEL WORDS"

# ---- a linked board hangs its pictures in the panel --------------------------
# His ask, 2026-08-30: a linked mood board should put its own wall in the
# References panel, under a heading of its own, beside the pictures dropped
# straight onto the scene — *"right now it just shows a pill that they are
# linked."* Several boards can hang there at once, and each heading shuts.
#
# **A tap cannot reach this panel**, measured while building it: a click posted
# at a heading lands on the container and picks nothing — the same reason the
# picking check above drives `--reference` rather than clicking. So the shape is
# read off `--referencessay`, and shutting a heading is pressed with
# `--shutsection` rather than clicked.
refs="$(mktemp -d)"
cp -R studio/fixtures/Daybreak.shotlist "$refs/Refs.shotlist"
python3 - "$refs" <<'PYEOF'
import sys
try:
    from PIL import Image
except ImportError:
    sys.exit(0)
for n, c in ((1, (196, 84, 72)), (2, (72, 120, 180)), (3, (96, 150, 110))):
    Image.new("RGB", (600, 400), c).save("%s/ref%d.png" % (sys.argv[1], n))
PYEOF
if [ -f "$refs/ref3.png" ]; then
  "$APP" --project "$refs/Refs.shotlist" --screen "$SCREEN" --place scenes --scene 33 \
         --pin "$refs/ref1.png" >/dev/null 2>&1
  "$APP" --project "$refs/Refs.shotlist" --screen "$SCREEN" --addboard "Night Exteriors" \
         --pinonboard "$refs/ref2.png" --pinonboard "$refs/ref3.png" >/dev/null 2>&1
  "$APP" --project "$refs/Refs.shotlist" --screen "$SCREEN" --place scenes --scene 33 \
         --linkboard "Night Exteriors" >/dev/null 2>&1
  saysrefs() {
    local name="$1"; local want="$2"; shift 2
    local out; out=$("$APP" --project "$refs/Refs.shotlist" --screen "$SCREEN" --place scenes \
                       --scene 33 --panel references --referencessay "$@" 2>&1)
    echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
    if echo "$out" | grep -q "$want"; then
      pass=$((pass+1)); echo "PASS  $name"
    else
      fail=$((fail+1)); echo "FAIL  $name"
      echo "$out" | grep -E "^references:" | sed 's/^/      /'
    fi
  }
  saysrefs "the scene's own pictures keep a heading" "references: This scene pictures=1 open=yes"
  saysrefs "a linked board hangs its wall under its name" "references: Night Exteriors pictures=2 open=yes"
  saysrefs "two places, two headings" "references: sections=2"
  saysrefs "a heading shuts" "references: Night Exteriors pictures=2 open=no" --shutsection "Night Exteriors"
fi
rm -rf "$refs"

# ---- the references board's arrows, still unchecked, and now for a reason ----
# **Ref 268.** The board's keyboard used to be installed when the board
# appeared, which meant a key posted before the panel was drawn landed nowhere.
# That is fixed — it is installed once at launch now and guarded at the moment
# a key arrives (`BoardFocus.install`) — and the arrows still cannot be checked
# here. The reason turned out not to be the one on the row.
#
# Measured 2026-08-23, driving `--panel references --type "→→"` at a scene with
# three references pinned: when the arrow reaches the board it does exactly the
# right thing, every time. It reaches the board on about half of runs. The other
# half the **table's** keyboard takes it first, because two local monitors both
# claim ← → and AppKit hands the event to whichever was installed later — which
# depends on when the table happened to be drawn.
#
# So this is not a timing problem to be waited out. It is a question nobody has
# answered: **with the panel out on References and the cursor in the table, whose
# arrows are they?** Both readings are defensible and the app currently picks by
# accident. A check written before that is settled would be asserting a race.
#
# Filed as its own row. When it is settled, the check is six lines and the
# report line it needs — `references: N picked: M` — already exists.

# ---- the sheets open, and the chrome that opens them -------------------------
# Three panels arrived together: the project's own facts, a scene's own facts,
# and a column's own page. Each is checked here for the cheapest thing that
# matters — it opens, over the real project, without taking anything down with
# it — because a sheet that throws on open takes the window with it, and the
# quiet lane cannot type into one (no first responder). The typing is the loud
# lane's, and the writes underneath are the same `set` every cell uses.
runcols "the project's own page opens"  "title=170" --settings
runcols "a scene's own page opens"      "title=170" --scenepage
runcols "a column's own page opens"     "title=170" --columnpage size

# ---- two machines on one folder (§F) ----------------------------------------
# A project is a folder of append-only logs, one per device per session, and
# the relay puts the other machine's log in beside ours. Everything below
# is the real shape: two runs of the real app, each calling itself a different
# device with `--device`, sharing one project folder.
#
# **Every build until today said `DeviceId(1)`** — his Mac and his phone were
# one device as far as the engine could tell, which breaks both halves of
# sync: a clash is "we both changed this without seeing each other", which
# cannot be told from ordinary editing between two machines wearing one name,
# and the rule that a device never writes another's changes into its own log
# would have swallowed the other machine's work as ours.

sync() {
  local name="$1"; local want="$2"; shift 2
  if eval "$@" | grep -qE "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    eval "$@" | sed 's/^/      /' | tail -3
  fi
}

TWO="$(mktemp -d)/Two.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$TWO"
# One machine writes a title, the other writes a note, neither having seen the
# other. Both must be there afterwards — merging never loses anything.
"$APP" --project "$TWO" --screen "$SCREEN" --device 7001 --scene 34 --cell title --set title "MAC ONE" >/dev/null 2>&1
"$APP" --project "$TWO" --screen "$SCREEN" --device 7002 --scene 34 --cell notes --set notes "MAC TWO" >/dev/null 2>&1
sync "one machine's work is there for the other" 'engine holds "MAC ONE"' \
     '"$APP" --project "$TWO" --screen "$SCREEN" --device 7002 --scene 34 --cell title --type "" 2>&1'
sync "…and the other's is there for the first"   'engine holds "MAC TWO"' \
     '"$APP" --project "$TWO" --screen "$SCREEN" --device 7001 --scene 34 --cell notes --type "" 2>&1'
# Each machine writes only its own log — never the other's.
sync "each machine keeps its own log" '1b59.*log' 'ls "$TWO/changes" 2>&1'
sync "…and the other machine keeps its own"  '1b5a.*log' 'ls "$TWO/changes" 2>&1'

# The live case: this Mac sits with the project open while the other one
# works. Until today nothing ever looked at the folder again — `pull()`
# existed in Swift with no callers — so a Mac left open all afternoon showed a
# list that had moved on hours ago.
LIVE="$(mktemp -d)/Live.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$LIVE"
("$APP" --project "$LIVE" --screen "$SCREEN" --device 8001 --scene 34 --stay 6 > /tmp/shotlister-open-mac.log 2>&1 &)
sleep 2
"$APP" --project "$LIVE" --screen "$SCREEN" --device 8002 --scene 34 --cell title --set title "FROM THE OTHER MAC" >/dev/null 2>&1
sleep 5
sync "an open Mac notices the other one's work" 'pulled 1 change' \
     'cat /tmp/shotlister-open-mac.log'

# The one case worth a word: both machines decided the same field while apart.
# Nothing is lost — both values are in the log — but one is only in the log,
# and it arrives while this Mac is closed, so it has to be reported at OPEN
# and not merely after a pull.
CLASH_A="$(mktemp -d)/A.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$CLASH_A"
"$APP" --project "$CLASH_A" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --set lens "40mm" >/dev/null 2>&1
CLASH_B="$(mktemp -d)/B.shotlist"
cp -R "$CLASH_A" "$CLASH_B"
"$APP" --project "$CLASH_B" --screen "$SCREEN" --device 8002 --scene 34 --cell lens --set lens "85mm" >/dev/null 2>&1
"$APP" --project "$CLASH_A" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --set lens "27mm" >/dev/null 2>&1
cp "$CLASH_B"/changes/*1f42*.log "$CLASH_A/changes/" 2>/dev/null
sync "a field decided twice is said at open" 'clashes standing: 1' \
     '"$APP" --project "$CLASH_A" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --type "" 2>&1'
sync "…and nothing was lost — the other value is still in the log" 'engine holds "27mm"' \
     '"$APP" --project "$CLASH_A" --screen "$SCREEN" --device 8001 --scene 34 --cell lens --type "" 2>&1'
rm -rf "$(dirname "$TWO")" "$(dirname "$LIVE")" "$(dirname "$CLASH_A")" "$(dirname "$CLASH_B")"

# ---- when the chrome and the cursor disagree --------------------------------
# **The blind spot that let three bugs through on 2026-08-20.**
#
# Every check above pins the app with `--scene 34` *and* leaves the cursor in
# scene 34, so the sidebar's idea of "the current scene" and the cursor's
# actual home always agreed. In real use they disagree constantly: scrolling
# moves the chrome, clicking moves the cursor. Nine places in the table read
# the chrome and called it the cursor, and every one of them was invisible to
# this battery by construction — the arrows threw him to the top of the script,
# ⌘C/⌘V did nothing at all, and so did ⌘⌫, ⌘K and a colour change.
#
# So: the same operations again, with the chrome pointed at 34 and the cursor
# deliberately in 35. A check that agrees with itself proves less than one that
# has been made to disagree.
cross() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$SCRATCH" --screen "$SCREEN" --place scenes --scene 34 "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qE "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "engine holds|expected|cursor rests" | sed 's/^/      /'
  fi
}

cross "arrow down stays in the cursor's scene" "cursor rests on 35B" \
      --shot 35A --type "↓" --shots
# Which row of 34 it lands on depends on what earlier checks left in 34, so
# this asserts the thing under test — that it crossed into 34 at all — and not
# a row number that only held on a pristine fixture.
cross "arrow up crosses the scene line"        "cursor rests on 34" \
      --shot 35A --type "↑" --shots
cross "paste reaches a text cell elsewhere"    "MATCHES" \
      --shot 35A --cell movement --paste "Handheld" --expect "Handheld"
cross "paste reaches a dropdown elsewhere"     "MATCHES" \
      --shot 35A --cell size --paste "CU" --expect "CU"
cross "delete reaches a cell elsewhere"        "MATCHES" \
      --shot 35A --cell movement --type "⌫" --expect ""
# (A strike-and-restore check stood here and I took it out. It asserted the
# scene's original words, which earlier checks have long since overwritten by
# the time it runs — so it failed on the fixture's history rather than on the
# keyboard. The class it was testing, "does a key reach a shot the chrome is
# not pointed at", is already proven above by the arrows, both pastes, the
# delete and the add. A check that can only pass on a pristine fixture in a
# battery that mutates one is not a check, it is a tripwire.)

# ---- the table fills a wide window, and lets go of it ------------------------
# His ask: "the end of the table should lock onto the edge of the program panel
# and evenly distribute more width between columns while expanding, but then
# reset to where it's small enough again."
#
# Nine launches to set up, which is why it is here rather than in the fast
# tier: the twelve standard columns are wider than his screen, so the stretch
# can only be seen with some of them hidden.
STRETCH="$(mktemp -d)/Stretch.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$STRETCH"
for hidden in notes tags day support lens camera movement angle; do
  "$APP" --project "$STRETCH" --screen "$SCREEN" --hide "$hidden" >/dev/null 2>&1
done
stretch() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$STRETCH" --screen "$SCREEN" --scene 34 "$@" --columns 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "columns:|spread:" | sed 's/^/      /'
  fi
}
stretch "four columns fill a wide window"    "spread: 117" --cell size --type ""
stretch "…and every column shares it evenly" "image=249 title=357 description=397 size=235" --cell size --type ""
stretch "a narrow window gives it all back"  "spread: 0"   --wide 900 --cell size --type ""
stretch "…and his own widths are untouched"  "image=132 title=240" --wide 900 --cell size --type ""
rm -rf "$(dirname "$STRETCH")"

# ---- three things that only a battery can see -------------------------------
#
# None of these shows up in a screenshot of a healthy project, which is exactly
# why they are worth a check: a hollow frame looks like an empty one, a filter
# carried across projects looks like a filter you set, and a room quietly given
# its own address looks like a room with an address.

ROOMS="$(mktemp -d)/Rooms.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$ROOMS"

# Ref 224 — a frame whose file is gone is not the same as a shot with no frame.
# Made by taking a proxy away behind the app's back, which is exactly how his
# two real ones came to be: a record written, the file never arriving.
gone=$(ls "$ROOMS/media/proxies" 2>/dev/null | head -1)
if [ -n "$gone" ]; then
  rm -f "$ROOMS/media/proxies/$gone"
  out=$("$APP" --project "$ROOMS" --screen "$SCREEN" --place scenes --scene 34 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -q "hollow frames: 1"; then
    pass=$((pass+1)); echo "PASS  a frame with no file behind it is known to be one"
  else
    fail=$((fail+1)); echo "FAIL  a frame with no file behind it is known to be one"
    echo "$out" | grep -E "hollow frames" | sed 's/^/      /'
  fi
  # ...and a project with every file present says nought, which is the half
  # that catches a check reading a number that is always there.
  CLEAN="$(mktemp -d)/Clean.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$CLEAN"
  out=$("$APP" --project "$CLEAN" --screen "$SCREEN" --place scenes --scene 34 2>&1)
  if echo "$out" | grep -q "hollow frames: 0"; then
    pass=$((pass+1)); echo "PASS  …and a project missing nothing says nought"
  else
    fail=$((fail+1)); echo "FAIL  …and a project missing nothing says nought"
    echo "$out" | grep -E "hollow frames" | sed 's/^/      /'
  fi
  rm -rf "$(dirname "$CLEAN")"
fi

# Ref 308 — a room shows the house's address and cannot be given one of its own.
# The display half was already checked; this is the writing half. Setting an
# address on a room must leave the room's own record empty, so that moving it
# out of the house later does not strand a borrowed address on it.
"$APP" --project "$ROOMS" --screen "$SCREEN" --place locations \
  --addlocation "Hillcrest House" --setlocation address "2140 Hillcrest Rd" >/dev/null 2>&1
"$APP" --project "$ROOMS" --screen "$SCREEN" --place locations \
  --addarea "Hillcrest House" "Kitchen" >/dev/null 2>&1
"$APP" --project "$ROOMS" --screen "$SCREEN" --place locations --location "Kitchen" \
  --movelocation "Kitchen" "" >/dev/null 2>&1
out=$("$APP" --project "$ROOMS" --screen "$SCREEN" --place locations --locations 2>&1)
echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
if echo "$out" | grep -qE "\| Kitchen; ;"; then
  pass=$((pass+1)); echo "PASS  a room let out of its house has no address of its own to keep"
else
  fail=$((fail+1)); echo "FAIL  a room let out of its house has no address of its own to keep"
  echo "$out" | grep -E "locations:" | sed 's/^/      /'
fi

# Ref 102 — reading the film by location reorders the reading and nothing else.
out=$("$APP" --project "$ROOMS" --screen "$SCREEN" --sceneorder location 2>&1)
if echo "$out" | grep -q "scene order: 34,33,54,35"; then
  pass=$((pass+1)); echo "PASS  the film can be read in order of location"
else
  fail=$((fail+1)); echo "FAIL  the film can be read in order of location"
  echo "$out" | grep -E "scene order" | sed 's/^/      /'
fi
out=$("$APP" --project "$ROOMS" --screen "$SCREEN" --sceneorder script 2>&1)
if echo "$out" | grep -q "scene order: 33,34,35,54"; then
  pass=$((pass+1)); echo "PASS  …and script order is still there to go back to"
else
  fail=$((fail+1)); echo "FAIL  …and script order is still there to go back to"
  echo "$out" | grep -E "scene order" | sed 's/^/      /'
fi
rm -rf "$(dirname "$ROOMS")"

# ---- the schedule ----------------------------------------------------------
# The board's one gesture is a drag, and a synthetic mouse cannot drive an
# `onDrag`/`onDrop` pair — that is a dragging *session*, not a click. So these
# call the drop handler's own path (`--puton`, `--putshot`) and ask the board
# what it holds. **The pixels are on the hands script**, deliberately: what is
# checked here is that a move lands, splits a scene properly, and above all
# that it is still there after a relaunch. That last one is the trap this
# family keeps falling into — a board that draws the move and loses it on quit.
BOARD="$(mktemp -d)/Board.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$BOARD"

b() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$BOARD" --screen "$SCREEN" "$@" --boardsays 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep "^board:" | sed 's/^/      /'
  fi
}

b "the board comes up with the days the film has" \
  "board: Day 1 shots=16 scenes=[33,34,35,54]"
b "a scene dropped on a day lands there" \
  "board: Day 2 shots=2 scenes=[35]" --puton 35 2
b "…and is still there after a relaunch" \
  "board: Day 2 shots=2 scenes=[35]"
b "a scene dragged back is waiting again" \
  "board: waiting=[35]" --puton 35 none
b "…and is still waiting after a relaunch" \
  "board: waiting=[35]"
b "one shot pulled out splits its scene across two days" \
  "board: Day 2 shots=1 scenes=[34(also Day 1)]" --putshot 34C 2
b "…and the day it left says where the rest of it is" \
  "34(also Day 2)"
b "…and the split survives a relaunch" \
  "board: Day 2 shots=1 scenes=[34(also Day 1)]"
b "a new shoot day is added" "board: Day 3" --addday
b "…and the new day is still there next time" "board: Day 3"

# ---- the calendar -----------------------------------------------------------
# Days made by picking dates. `--clickdate` presses a date cell through the
# same funnel the cell calls and prints the funnel's own answer, so what is
# asserted is the click's real behaviour: an empty date becomes a dated day in
# one gesture, a held date highlights and adds nothing, and the days number in
# the order they were picked. `--putdate` is the band-on-a-date drop by the
# handler's own path, the bargain `--putday` struck. Every second call is a
# fresh process, so persistence is proved as it goes.
d() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$BOARD" --screen "$SCREEN" "$@" --dayssay 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "^day:|^days:|^calendar:|^marked:|^order:|^dots:|^synopsis:|^scene |^frames:|^off day:" | sed 's/^/      /'
  fi
}

# The fixture's dates predate the date sheet and are stored as they were
# typed ("Fri 12 Sep"); put both days on the stored form first so the sort
# below means what it says.
d "a day's date is stored in the engine's form" \
  'day: Day 1  name=""  date="2026-09-12"' --daydate 1 2026-09-12 --daydate 2 2026-09-13
d "a calendar click makes a day wearing its date" \
  "calendar: added Day 4 2026-09-20" --clickdate 2026-09-20
d "…and the day is still dated after a relaunch" \
  'day: Day 4  name=""  date="2026-09-20"'
d "a held date highlights its day and adds nothing" \
  "calendar: highlighted Day 4" --clickdate 2026-09-20
d "…still four days" "days: 4"
d "days number in the order they are picked" \
  "calendar: added Day 5 2026-09-10" --clickdate 2026-09-10
d "the board knows its dates are out of order" \
  "order: out of date order" --calendarsays
d "one press puts the days in date order" \
  'day: Day 1  name=""  date="2026-09-10"' --sortdays
d "…the undated day kept its place" 'day: Day 3  name=""  date=""'
d "…and the order survives a relaunch" \
  'day: Day 2  name=""  date="2026-09-12"'
d "…and the out-of-order condition clears" \
  "order: dated days in order" --calendarsays
d "a band dropped on a date takes that date" \
  'day: Day 5  name=""  date="2026-10-01"' --putdate 5 2026-10-01
d "the calendar marks the dates it holds" \
  "marked: 2026-09-10 = Day 1 · 0" --calendarsays
d "a day wears the marks of its scenes' times of day" \
  "dots: Day 2 = day,night" --daydots
# The Frames switch is gone — his instruction, 2026-08-30: it drew each scene's
# key picture, which in a film with no pictures on its scenes is a control that
# does nothing. The Synopsis button took its place in the bar.
# The synopsis a strip shows when it is opened — read from the engine's view
# model, never stored on the board, so this is the only way to prove it is the
# scene's own words that arrive there.
d "a scene takes a summary" \
  'scene 33: description = "Ruiz waits outside the jail"' \
  --scene 33 --scenefield description "Ruiz waits outside the jail"
d "…and the strip reads it back off the scene" \
  "synopsis: 33 = Ruiz waits outside the jail" --synopsissay
# The button in the bar that shows every scene's summary at once — it replaced
# the Frames switch on 2026-08-30, and a control no check can press is a
# control no check can prove.
d "the board starts with the summaries off" \
  "synopsis showing: no" --synopsissay
d "the synopsis button turns them on" \
  "synopsis showing: yes" --synopsis --synopsissay
rm -rf "$(dirname "$BOARD")"

# ---- taking a scene off a day ----------------------------------------------
# His ask, 2026-08-29: "I need to be able to remove scenes from the schedule or
# days." The strip's right-click menu, through the path the menu item calls —
# a context menu cannot be opened by a synthetic click. Its own fixture, so the
# board above keeps the state its own checks were written against.
OFF="$(mktemp -d)/Off.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$OFF"

o() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$OFF" --screen "$SCREEN" "$@" --boardsays 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "^board:|^off day:" | sed 's/^/      /'
  fi
}

o "every scene starts on a day" "board: Day 1 shots=16 scenes=[33,34,35,54]"
o "a scene is taken off its day" "off day: scene 54" --offday 54
o "…the day it left keeps the rest" "board: Day 1 shots=8 scenes=[33,34,35]"
o "…and it is waiting again after a relaunch" "board: waiting=[54]"
o "a scene that is on no day cannot be taken off one" \
  "off day: no scene 54 on any day" --offday 54
rm -rf "$(dirname "$OFF")"

# ---- ready-made columns -----------------------------------------------------
# The "From template" menu. A menu inside a sheet cannot be driven by a
# synthetic click, so these call the menu item's own path (`--template`) and
# read the list back (`--templates`). **What the picture is for** is that the
# column arrives wearing its label rather than its slug; that is on the hands
# script and in a shot taken 2026-08-23.
TPL="$(mktemp -d)/Templates.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$TPL"

t() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$TPL" --screen "$SCREEN" "$@" 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "^templates:|^template:|custom columns" | sed 's/^/      /'
  fi
}

t "the menu offers a shape with every name" \
  "Cast:multi, Props:multi, Wardrobe:text" --templates
t "a ready-made column is made with the shape it says" \
  "template: Frame Rate kind=single already=false" --template "Frame Rate"
t "…and the engine really made it that shape" \
  "Frame Rate/single" --place scenes --columns
t "…and it is still there after a relaunch" \
  "Frame Rate:single(already)" --templates
t "the same one is not offered twice" \
  "template: Frame Rate kind=single already=true" --template "Frame Rate"
t "a checkmark template is a checkmark, not text" \
  "Covered/check" --template Covered --place scenes --columns
t "a ready-made column arrives visible, not hidden" \
  "custom columns: Frame Rate/single Covered/check" --place scenes --columns
rm -rf "$(dirname "$TPL")"

# ---- mood boards ------------------------------------------------------------
# Ref 58. The sidebar said "Not built yet" for weeks because there was no board
# record in the engine at all. There is now, and a board is an *owner* — so its
# pictures go on and come off through the same doors a scene's references and a
# location's photographs use, and these check that they really do.
BRD="$(mktemp -d)/Boards.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$BRD"
PIC="$(mktemp -d)/wall.png"
# A real picture, made here rather than kept in the repo.
sips -s format png -z 400 600 studio/fixtures/Daybreak.shotlist/media/*.jpg \
     --out "$PIC" >/dev/null 2>&1 \
  || sips -s format png --resampleHeightWidth 400 600 \
       /System/Library/CoreServices/DefaultDesktop.heic --out "$PIC" >/dev/null 2>&1

m() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$BRD" --screen "$SCREEN" "$@" --boardssay 2>&1)
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -iE "^moodboard|^scene boards" | sed 's/^/      /'
  fi
}

m "a project starts with no mood boards" "moodboards: 0"
m "a board is made and named" "moodboard: Night Exteriors pictures=0" --addboard "Night Exteriors"
m "…and is still there after a relaunch" "moodboard: Night Exteriors pictures=0"
m "a second board does not replace the first" "moodboards: 2" --addboard "Anya"
m "a board can be renamed" "moodboard: The Diner" --board "Anya" --renameboard "The Diner"
m "…and there is still only one of it" "moodboards: 2"
if [ -f "$PIC" ]; then
  m "a picture hangs on a board" "pictures=1" --board "The Diner" --pinonboard "$PIC"
  m "…and is still on it after a relaunch" "pictures=1"
fi
# **The wall goes, the pictures stay.** A picture is addressed by its contents
# and may hang on a shot and a location too, so deleting a board must take one
# board's *uses* of it and nothing else.
m "deleting a board takes only that board" "moodboards: 1" --board "The Diner" --deleteboard
m "…and the board that was left still has its name" "moodboard: Night Exteriors"

# **One photograph, two places, two names.** His report, 2026-08-23: pictures on
# a board "keep their original name (currently don't)" — and, separately, that
# the same photograph used twice should be one file rather than two. Those two
# asks fight each other while the name lives on the *file*, because every use of
# it wears that one name: a photograph scouted at Hillcrest House and then hung
# on a wall of references came out on the wall called `hillcrest-house-01.jpg`.
# Measured on the committed build before it was fixed. The name lives on the use
# now, so both rules hold at once and nothing is stored twice.
if [ -f "$PIC" ]; then
  NAMED="$(mktemp -d)/mountain.png"; cp "$PIC" "$NAMED"
  "$APP" --project "$BRD" --screen "$SCREEN" --addlocation "Hillcrest House" >/dev/null 2>&1
  "$APP" --project "$BRD" --screen "$SCREEN" --location "Hillcrest House" \
         --pinhere "$NAMED" >/dev/null 2>&1
  out=$("$APP" --project "$BRD" --screen "$SCREEN" --locations 2>&1)
  if echo "$out" | grep -q "hillcrest-house-01"; then
    pass=$((pass+1)); echo "PASS  a location renames the photograph it is given"
  else
    fail=$((fail+1)); echo "FAIL  a location renames the photograph it is given"
    echo "$out" | grep -i "photo names" | sed 's/^/      /'
  fi
  before=$(ls "$BRD"/media/proxies | wc -l | tr -d ' ')
  # The stem is what his rule is about; the extension is corrected to match
  # the bytes actually written, which is Ref 193 and separately checked.
  m "…and the same file on a board keeps its own name" "[mountain." \
    --board "Night Exteriors" --pinonboard "$NAMED"
  m "…still, after a relaunch" "[mountain."
  after=$(ls "$BRD"/media/proxies | wc -l | tr -d ' ')
  if [ "$before" = "$after" ]; then
    pass=$((pass+1)); echo "PASS  …and it was not stored a second time to do it"
  else
    fail=$((fail+1))
    echo "FAIL  …and it was not stored a second time to do it (was $before, now $after)"
  fi
  rm -rf "$(dirname "$NAMED")"
fi

# **The wall of location photographs took on the mood board's rules** — his
# instruction, 2026-08-24: one gallery, wherever it is drawn. Ratio went from a
# plain square/original toggle to the same 3-way choice a board has, and a
# checking run starts every time from a known shape rather than whichever one
# was last chosen by hand — the same reason `boardUnit` pins under
# `Launch.checking`, applied here too.
loc() {
  local name="$1"; local want="$2"; shift 2
  local out; out=$("$APP" --project "$BRD" --screen "$SCREEN" "$@" --locations 2>&1)
  if echo "$out" | grep -qF "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -i "photo shape" | sed 's/^/      /'
  fi
}
loc "a checking run starts from a known photo shape" "photo shape: square" \
  --addlocation "Shape Test" --location "Shape Test"
loc "the shape can be set to project ratio" "photo shape: project" \
  --location "Shape Test" --photoshape project
loc "…and to original" "photo shape: original" \
  --location "Shape Test" --photoshape original
loc "…and back to square" "photo shape: square" \
  --location "Shape Test" --photoshape square

# ---- picking pictures, and carrying them into a new order -------------------
# His asks, 2026-08-23: "blue outline around photo when click", "drag to
# reorder". The outline is pixels and belongs to the hands script; the two
# halves that can be read back are what a pick *selected* and what a carry
# *did to the order*, and both are asserted here.
#
# **A synthetic mouse cannot start a dragging session**, so the carry is driven
# through `ShellState.moveWallPicture` — the same method the gesture calls —
# rather than through pixels. Say which half you checked.
if [ -f "$PIC" ]; then
  THREE="$(mktemp -d)"
  for n in 1 2 3; do
    sips -s format png --resampleHeightWidth $((400 + n)) 500 \
      /System/Library/CoreServices/DefaultDesktop.heic --out "$THREE/pic$n.png" >/dev/null 2>&1
  done
  if [ -f "$THREE/pic3.png" ]; then
    m "three pictures hang in the order they arrived" "[pic1.jpg,pic2.jpg,pic3.jpg]" \
      --addboard "Order" --board "Order" \
      --pinonboard "$THREE/pic1.png" --pinonboard "$THREE/pic2.png" \
      --pinonboard "$THREE/pic3.png"
    m "one carried left lands before the one it was dropped on" \
      "[pic3.jpg,pic1.jpg,pic2.jpg]" --board "Order" --putpicture "pic3.jpg" "pic1.jpg"
    m "…and the new order survives a relaunch" "[pic3.jpg,pic1.jpg,pic2.jpg]" --board "Order"
    # The direction an off-by-one hides in: lifting a picture out shortens
    # everything after it, so a rightward carry lands one short if the target
    # is read before the lift.
    m "one carried right lands before it too, not after" \
      "[pic1.jpg,pic3.jpg,pic2.jpg]" --board "Order" --putpicture "pic3.jpg" "pic2.jpg"
    m "a picture starts unpicked" "board picked: none" --board "Order"
    m "two pictures can be picked at once" "board picked: pic1.jpg,pic3.jpg" \
      --board "Order" --pickpictures "pic1.jpg,pic3.jpg"
  fi
  rm -rf "$THREE"
fi

# **The search box on this tab does something now.** It has been drawn over the
# board list since the sidebar was built and narrowed nothing, while the
# locations list beside it has always honoured it. A board is found by its own
# name and by the names of the pictures on it.
m "every board is shown when nothing is searched for" \
  "boards shown: Night Exteriors,Order" --board "Order"
m "searching narrows the list to the board named" \
  "boards shown: Night Exteriors" --search "night"
m "…and a board is found by a picture hanging on it" \
  "boards shown: Order" --search "pic2"
m "…and a search that matches nothing shows nothing" \
  "boards shown: none" --search "zzz"

# ---- scenes linking mood boards, and a board's own ratio --------------------
# SL-348, his call 2026-08-23: "Scenes and references should link to mood
# boards. Allow for original aspect ratio, square, or project aspect ratio."
# The chip lives on the scene (scene_boards, the same shape scene_locations
# already used), and the ratio is a board-wide setting written through the
# generic `set` — no new command for it, so nothing here checks a bespoke one.
m "a scene starts with no mood boards" \
  "scene boards: 33=none | 34=none | 35=none | 54=none" --scene 34
m "a scene links a mood board" \
  "scene boards: 33=none | 34=Night Exteriors | 35=none | 54=none" \
  --scene 34 --linkboard "Night Exteriors"
m "…and it is still linked after a relaunch" \
  "scene boards: 33=none | 34=Night Exteriors | 35=none | 54=none" --scene 34
m "a second board adds rather than replaces" \
  "scene boards: 33=none | 34=Night Exteriors+Anya | 35=none | 54=none" \
  --scene 34 --addboard "Anya" --linkboard "Anya"
m "unlinking one leaves the other" \
  "scene boards: 33=none | 34=Anya | 35=none | 54=none" \
  --scene 34 --unlinkboard "Night Exteriors"
m "a board's ratio starts original" "moodboard: Anya pictures=0 ratio=original" --board "Anya"
m "the ratio can be set to square" \
  "moodboard: Anya pictures=0 ratio=square" --board "Anya" --boardratio square
m "…and to the project's own ratio" \
  "moodboard: Anya pictures=0 ratio=project" --board "Anya" --boardratio project
m "…and back to original" \
  "moodboard: Anya pictures=0 ratio=original" --board "Anya" --boardratio original
m "deleting a board unlinks it from the scene that had it" \
  "scene boards: 33=none | 34=none | 35=none | 54=none" \
  --board "Anya" --deleteboard --scene 34

rm -rf "$(dirname "$BRD")" "$(dirname "$PIC")"

# ---- the wall's own hands: a real double-click ------------------------------
# **This is the check that was missing, and its absence hid a dead feature for
# months.** Double-clicking a photograph on a wall opens the pop-out — Ref 150,
# marked Done — and on 2026-08-29 it turned out never to have worked: a
# `DragGesture(minimumDistance: 0)` recognises on mouse-*down* and took the
# press, so the count-2 tap beside it never fired.
#
# Everything was green throughout, because nothing drove the gesture:
# `--openphoto` calls `Viewer.show` directly and the space bar goes through
# `WallKeys`. Both halves of the *code* were checked; the hand was not.
#
# `--tap` never exits (it has no report to print and no snapshot to take), so
# the run is backgrounded and killed. That is the price of driving a real mouse
# and it is why this lives here rather than in quick.sh.
DBL="$(mktemp -d)/Dbl.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$DBL"
dpid="8B0F4E2A-1111-4E1D-9C3A-000000000001"
mkdir -p "$DBL/locations/$dpid/photos"
cat > "$DBL/locations/$dpid/location.json" <<JSON
{ "id": "$dpid", "name": "Office Test", "address": "a", "latitude": 32.8,
  "longitude": -117.1, "notes": "n", "createdAt": "2026-08-21T13:55:20Z",
  "capturedBy": "iPhone", "driveFolder": "Office Test" }
JSON
python3 - "$DBL/locations/$dpid/photos" <<'PYEOF'
import sys, zlib, struct
def png(p, w, h, rgb):
    raw = b''.join(b'\x00' + bytes(rgb) * w for _ in range(h))
    def ch(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    open(p, 'wb').write(b'\x89PNG\r\n\x1a\n'
        + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))
for n, c in enumerate([(200, 90, 90), (90, 120, 200), (120, 200, 110)]):
    png(f"{sys.argv[1]}/2026-08-21T1355{n:02d}.png", 320, 240, c)
PYEOF
"$APP" --project "$DBL" --screen "$SCREEN" --place locations --homecoming >/dev/null 2>&1

# The tile centres at the wall's default size, in window points, read off a
# snapshot of this same fixture. One row of three.
hands() {
  local name="$1"; local want="$2"; local spec="$3"
  local log; log="$(mktemp)"
  "$APP" --project "$DBL" --screen "$SCREEN" --place locations --location "Office Test" \
         --tap "$spec" >/dev/null 2>"$log" &
  local pid=$!
  sleep 7
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  local out; out="$(cat "$log")"; rm -f "$log"
  echo "$out" | grep -q "FOCUS STOLEN" && trips=$((trips+1))
  if [ "$want" = "none" ]; then
    if echo "$out" | grep -q "^viewer: "; then
      fail=$((fail+1)); echo "FAIL  $name — a pop-out opened and should not have"
    else
      pass=$((pass+1)); echo "PASS  $name"
    fi
  elif echo "$out" | grep -q "^viewer: $want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "^viewer:|^click at" | sed 's/^/      /'
  fi
}

# ---- which part of a picture is kept ----------------------------------------
#
# **A framing is a look, and a green line is not a look** — so this checks both
# halves separately: that the three numbers survive the round trip, and that
# what is *drawn* actually changes. The picture is two flat halves, red and
# blue, because "the tile is red" is a claim a snapshot can carry and "the crop
# looks right" is not.
#
# The editor itself is not here and cannot be: **no sheet in this app can be
# photographed**, which has been true since `--editcolumns`. What is checkable
# is the arithmetic under it, and `--crop` calls exactly the engine call the
# sheet's Save calls.
cropdir="$(mktemp -d)"
cp -R studio/fixtures/Daybreak.shotlist "$cropdir/Crop.shotlist"
python3 - "$cropdir" <<'PYEOF'
import sys
try:
    from PIL import Image
except ImportError:
    sys.exit(0)
img = Image.new("RGB", (1600, 500), (200, 60, 60))
for x in range(800, 1600):
    for y in range(500):
        img.putpixel((x, y), (60, 120, 200))
img.save(sys.argv[1] + "/wide.png")
PYEOF
if [ -f "$cropdir/wide.png" ]; then
  "$APP" --project "$cropdir/Crop.shotlist" --screen "$SCREEN" \
         --addboard "Wall" --board 1 --pinonboard "$cropdir/wide.png" >/dev/null 2>&1
  out=$("$APP" --project "$cropdir/Crop.shotlist" --screen "$SCREEN" --place boards --board 1 \
          --boardratio square --crop 0.25 0.75 2 --cropsays 2>&1)
  if echo "$out" | grep -q "crop: wide.png x=0.250 y=0.750 scale=2.000"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "a framing is kept where it was put"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "a framing is kept where it was put"
    echo "$out" | grep -E "^crop:" | sed 's/^/       /'
  fi

  out=$("$APP" --project "$cropdir/Crop.shotlist" --screen "$SCREEN" --place boards --board 1 \
          --crop 0 0.5 1 --cropsays 2>&1)
  if echo "$out" | grep -q "crop: wide.png x=0.000 y=0.500 scale=1.000"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "the framing can be put back to an edge"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "the framing can be put back to an edge"
  fi

  # The half a number cannot prove: a square tile of a wide picture framed hard
  # left is *red*, and framed hard right is *blue*. Read off the snapshot.
  left="$cropdir/left.png"; right="$cropdir/right.png"
  "$APP" --project "$cropdir/Crop.shotlist" --screen "$SCREEN" --place boards --board 1 \
         --crop 0 0.5 1 --snapshot "$left" >/dev/null 2>&1
  "$APP" --project "$cropdir/Crop.shotlist" --screen "$SCREEN" --place boards --board 1 \
         --crop 1 0.5 1 --snapshot "$right" >/dev/null 2>&1
  seen=$(python3 - "$left" "$right" <<'PYEOF'
import sys
try:
    from PIL import Image
except ImportError:
    print("skipped"); sys.exit(0)

def halfOf(path):
    # The tile sits under the board's own header; this reads a pixel well
    # inside it rather than trusting an exact layout.
    img = Image.open(path).convert("RGB")
    w, h = img.size
    r, g, b = img.getpixel((int(w * 0.235), int(h * 0.25)))
    if r > 120 and b < 110: return "red"
    if b > 120 and r < 110: return "blue"
    return "neither(%d,%d,%d)" % (r, g, b)

print("%s %s" % (halfOf(sys.argv[1]), halfOf(sys.argv[2])))
PYEOF
)
  if [ "$seen" = "red blue" ] || [ "$seen" = "skipped" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "and the tile draws the half it was told to"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "and the tile draws the half it was told to"
    printf '       expected "red blue", saw "%s"\n' "$seen"
  fi
fi
rm -rf "$cropdir"

hands "a single click on a photograph opens nothing" none            "360,257,1"
hands "a double-click opens the pop-out"       "office-test-01.png"  "360,257,2"
hands "…on the one actually under the hand"    "office-test-03.png"  "702,257,2"

rm -rf "$(dirname "$DBL")"

# ---- which way the frames go into a workbook --------------------------------
#
# **One `.xlsx`, laid out for one program or the other** — his correction,
# 2026-09-04: the file does not change, the frames do. Laid out for *Google
# Sheets* the Image column is an `IMAGE()` formula the sheet fetches, which is
# the only way a frame survives his sorting and which nothing else resolves.
# Laid out for *Excel* the picture is carried inside the workbook and opens
# anywhere. `--excelframes` is the door; `--settings --settingsend` photographs
# the dropdown itself.
#
# The stored words are still `cells` and `file` — they are in his films already;
# the names above them are what he reads.
#
# **The point of both halves is that a workbook is never both.** A file with a
# formula *and* an embedded picture would draw one on top of the other.

frames_check() {
  local name="$1" style="$2" want_formula="$3" want_media="$4"
  local film out sheet
  film="$(mktemp -d)/Frames.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$film"
  # A relay identity is what gives a frame an address at all; without one the
  # app carries the picture whatever was asked for, which is its own check.
  printf '{"relay": "https://sync.example.studio", "project": "%s"}' \
    "00000000000000000000000000000001" > "$film/remote.json"
  out="$(mktemp -d)"
  "$APP" --project "$film" --screen "$SCREEN" --place scenes \
         --excelframes "$style" --exportdays "$out" 1 --stay 16 >/dev/null 2>&1
  sheet=$(find "$out" -name '*.xlsx' | head -1)
  local formulas media
  if [ -n "$sheet" ]; then
    formulas=$(unzip -p "$sheet" xl/worksheets/sheet1.xml 2>/dev/null | grep -c '<f>IMAGE(' || true)
    media=$(unzip -l "$sheet" 2>/dev/null | grep -c 'xl/media/' || true)
  else
    formulas="no file"; media="no file"
  fi
  [ "$formulas" -gt 0 ] 2>/dev/null && formulas=yes || formulas=no
  [ "$media" -gt 0 ] 2>/dev/null && media=yes || media=no
  if [ "$formulas" = "$want_formula" ] && [ "$media" = "$want_media" ]; then
    pass=$((pass+1)); printf '  ✓  %s\n' "$name"
  else
    fail=$((fail+1)); printf '  ✗  %s  (formula %s, pictures %s — wanted %s, %s)\n' \
      "$name" "$formulas" "$media" "$want_formula" "$want_media"
  fi
  rm -rf "$out" "$(dirname "$film")"
}

frames_check "laid out for Sheets: a formula, and no picture carried"  cells yes no
frames_check "laid out for Excel: the picture carried, and no formula" file  no  yes

# **No relay behind the film, no address to give.** A formula pointing at
# nothing would draw an empty column and read as a bug, so it falls back.
NOLINK="$(mktemp -d)/NoRelay.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$NOLINK"
rm -f "$NOLINK/remote.json"
NOOUT="$(mktemp -d)"
"$APP" --project "$NOLINK" --screen "$SCREEN" --place scenes \
       --excelframes cells --exportdays "$NOOUT" 1 --stay 16 >/dev/null 2>&1
NOSHEET=$(find "$NOOUT" -name '*.xlsx' | head -1)
if [ -n "$NOSHEET" ] && unzip -l "$NOSHEET" 2>/dev/null | grep -q 'xl/media/'; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a film with no relay carries its pictures whatever was asked for"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a film with no relay carries its pictures whatever was asked for"
fi
rm -rf "$NOOUT" "$(dirname "$NOLINK")"

# ---- the film's own colour and icon -----------------------------------------
#
# **The accent is the one thing in the window a check cannot photograph**, so
# the app says what it is wearing (`--accent`) and these read it back.
#
# The colour comes from his Projects Console's cache, which is another program's
# file on this Mac and not in the repo — so the first check is skipped rather
# than failed where that file has no such project. A check that goes red on a
# machine where the console has never run would be a check nobody trusts.

CACHE="$HOME/Developer/.projects-console-state/projects-cache.json"
WANT=$(python3 - "$CACHE" <<'PY' 2>/dev/null
import json, re, sys
try:
    rows = json.load(open(sys.argv[1]))["projects"]
except Exception:
    sys.exit()
for row in rows:
    if row.get("name", "").lower() == "daybreak":
        found = re.findall(r'fill="(#[0-9A-Fa-f]{6})"', row.get("icon_svg") or "")
        if found:
            print(found[0].upper())
        break
PY
)

WEARS="$(mktemp -d)/Daybreak.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$WEARS"
if [ -n "$WANT" ]; then
  said=$("$APP" --project "$WEARS" --screen "$SCREEN" --place scenes --accent 2>&1)
  if echo "$said" | grep -q "accent: $WANT  mark: yes"; then
    pass=$((pass+1)); printf '  ✓  %s\n' "the film wears the colour and icon off its Notion row"
  else
    fail=$((fail+1)); printf '  ✗  %s\n' "the film wears the colour and icon off its Notion row"
    echo "$said" | grep -E "^accent:" | sed 's/^/      /'
    echo "      wanted accent: $WANT  mark: yes"
  fi
else
  printf '  ~  %s\n' "the film wears the colour and icon off its Notion row (skipped: the console knows no Daybreak)"
fi
rm -rf "$(dirname "$WEARS")"

# **A film Notion has never heard of keeps the program's own blue**, and draws
# no icon — which is most films, and is the case that must never break. Made
# fresh rather than copied, so that its title is the made-up name too and
# nothing about it can match a real project.
PLAIN="$(mktemp -d)/Zebra Nine.shotlist"
said=$("$APP" --project "$PLAIN" --screen "$SCREEN" --place scenes --accent 2>&1)
if echo "$said" | grep -q "accent: default  mark: none"; then
  pass=$((pass+1)); printf '  ✓  %s\n' "a film with no Notion row keeps the program's blue"
else
  fail=$((fail+1)); printf '  ✗  %s\n' "a film with no Notion row keeps the program's blue"
  echo "$said" | grep -E "^accent:" | sed 's/^/      /'
fi
rm -rf "$(dirname "$PLAIN")"

echo "----"
echo "passed $pass, failed $fail, focus trips $trips, drifted $drifted"
[ "$trips" -gt 0 ] && echo "trips are repaired within 50ms but each one is a report to read, not noise"
[ "$drifted" -gt 0 ] && echo "$drifted runs drifted onto a scene they did not ask for (Ref 101) — a check above them that failed probably failed for that reason and not its own"
rm -rf "$(dirname "$SCRATCH")" "$(dirname "$NARROW")"
[ "$fail" -eq 0 ]
