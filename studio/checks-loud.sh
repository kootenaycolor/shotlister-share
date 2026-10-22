#!/bin/zsh
# The loud battery — the real path, driven the way a hand drives it.
#
# LOUD MEANS THE APP TAKES THE FRONT. It becomes the active app with a key
# window and a first-responder text view — the exact path Nathaniel's hands
# use, which the quiet lane structurally cannot reach. **Run this only on an
# explicit grant** (his word that the machine is his to take for the moment,
# e.g. "take full control" / overnight), or when he is demonstrably away.
# Every run says LOUD RUN in its output and returns the front to whoever had
# it when the run began.
#
# What only this lane can prove: continuous typing through the real text
# view, click-to-place caret, drag-to-select, ⌘A/⌘C/⌘V, undo inside a cell,
# revise-mode caret arrows, single-click behaviour.
#
# Usage: studio/checks-loud.sh       (from the repo root)
set -u
cd "$(dirname "$0")/.."
APP="build/Shotlister Studio.app/Contents/MacOS/ShotlisterStudio"
SCRATCH="$(mktemp -d)/LoudChecks.shotlist"
cp -R studio/fixtures/Daybreak.shotlist "$SCRATCH"

pass=0; fail=0; skip=0
run() {
  local name="$1"; shift
  local out; out=$("$APP" --loud --project "$SCRATCH" --screen 0 --scene 34 "$@" 2>&1)
  sleep 1   # let the finished run's front-restore land before the next grab
  if echo "$out" | grep -q "NEVER GOT THE KEYBOARD"; then
    # A locked screen makes the loud lane physically impossible: no app can
    # become active, so the run silently exercised the fallback path. Saying
    # FAIL would send someone hunting a code bug that is actually a lock
    # screen — the hunt that cost an hour the night this line was written.
    skip=$((skip+1)); echo "SKIP  $name — could not take the keyboard (screen locked?)"
  elif echo "$out" | grep -qE "MATCHES"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$out" | grep -E "engine holds|expected|got" | sed 's/^/      /'
  fi
}

# Coordinates: description cell text begins at x≈643, row 34A y≈214 (window
# points, top-left origin; standard first-launch window). The run prints what
# a click will hit — re-map from that if layout changes.
#
# ⚠ **STALE AFTER 2026-08-20 — re-measure on the next grant.** The scene
# heading strip above the table was removed and the tab strip moved into the
# top bar, so everything below the chrome sits **34 points higher** than these
# numbers assume (measured on the quiet lane: row 34A went from y263..327 to
# y229..293, and the column-name band from y≈216 to y≈115). The quiet battery
# was re-mapped the same day and is green; this file was left alone on purpose
# rather than guessed at, because confirming a loud coordinate means taking
# his screen. The table taps below want roughly −34; **the document-page taps
# want much more** — that page lost the heading strip *and* the tab strip, so
# its content moved up by something closer to 110 — and that one has to be
# read off a real run, not arithmetic.

run "typing flows through the real text view"  --cell description --type "Real path types whole"
run "revise mode: arrows move the caret"       --cell title --set title "abcdef" --type "↩←←X" --expect "abcdXef"
run "replace mode: an arrow commits"           --cell title --type "xyz→" --expect "xyz"
run "shift-return makes a second line"         --cell notes --type "one⏎two" --expect "one
two"
run "cmd-A selects all, typing replaces"       --cell description --set description "hello world" --type "↩⌘aNew" --expect "New"
run "cmd-C cmd-V duplicates"                   --cell title --set title "abc" --type "↩⌘a⌘c→⌘v" --expect "abcabc"
run "a click places the caret"                 --cell description --set description "abcdefghij" --type "↩" --tap "645,214,1" --after "X↩" --expect "Xabcdefghij"
run "a drag selects, typing replaces"          --cell description --set description "abcdefghij" --type "↩" --tdrag "643,214,895,214" --after "Z↩" --expect "Z"
run "a single click away commits"              --cell description --type "typed then clicked once" --tap "1250,214,1" --expect "typed then clicked once"
run "double-click opens on the value"          --tap "700,470,2" --expect "Wide of the Car — pulls away from station"

# ---- the document page, on the real keyboard --------------------------------
# The page is all real text views and a real picker; none of it can be checked
# on the quiet lane, which never has a first responder.
#
# **Every page check gets its own fresh copy of the fixture.** These are
# coordinate-driven, and each check changes the words on the page — a shared
# copy meant every check moved the next one's target, and the failures that
# produced looked exactly like app bugs.
#
# Coordinates on the standard first-launch window with scene 34 open, fixture
# untouched. The page is the WHOLE script now and opens scrolled to the scene
# the sidebar has, so 34's heading is at the top: 34A's number sits at
# (560, 279), its description at y≈293, its technical line at y≈318.
#
# `page` runs one motion and then asks the ENGINE what it holds, so a line
# that looks right on screen but writes nowhere still fails.
page() {
  local name="$1"; local column="$2"; local want="$3"; shift 3
  local fresh="$(mktemp -d)/Page.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --loud --project "$fresh" --screen 0 --scene 34 \
                   --tab document "$@" 2>&1)
  sleep 1
  local read; read=$("$APP" --project "$fresh" --screen 0 --scene 34 \
                     --cell "$column" --type "" --expect "$want" 2>&1)
  rm -rf "$(dirname "$fresh")"
  if echo "$out" | grep -q "NEVER GOT THE KEYBOARD"; then
    skip=$((skip+1)); echo "SKIP  $name — could not take the keyboard (screen locked?)"
  elif echo "$read" | grep -q "MATCHES"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$read" | grep -E "expected" | sed 's/^/      /'
  fi
}

# The picker takes the HIGHLIGHTED option, never the half-word that filtered
# the list — "CU" must land CU/OTS, the table's oldest picker rule. Reached by
# Tab from the description (one Tab is Shot Size) so the grammar is asserted
# and not the arithmetic of where a word happens to sit.
page "a field's Return takes the option, not the typing" size "CU/OTS" \
     --tap "795,293,1" --after "⇥CU↩"
# The multi field gathers rather than replaces, exactly as the table does.
page "a multi field gathers a second value" angle "Short-Sided, Profile" \
     --tap "795,293,1" --after "⇥⇥Pro↩"
# Return closes the LIST and leaves the keyboard on the same field, so the
# next Tab — not the Return — is what moves on. Two fields written in one
# motion proves both halves: the first Return did not move the cursor, and
# the Tab after it did. (Typing used to arrive one letter at a time and get
# replaced: a text field is never its own first responder, so the claim
# retry re-took the field editor every 30ms and selected all.)
page "Return keeps the caret; the Tab after it moves on" angle "Short-Sided, Profile" \
     --tap "795,293,1" --after "⇥CU↩⇥Pro↩"
# One click on a word of the line opens that field — no double-click, and no
# selecting the shot first. x=780 lands on Movement. The typed word is one
# the project cannot already know, so the check does not depend on what is
# in the vocabulary: with nothing to match, the list offers to create it and
# Return takes that.
page "one click on the line opens that field" movement "ZZTOP" \
     --tap "780,318,1" --after "ZZTOP↩"
# Words typed into a page line survive the app going away: a line still
# holding the keyboard has its words only in the view until something puts
# them down, and quitting used to be the thing that never did. The note is
# clicked rather than tabbed to — a count of presses is not a fact about the
# page, and asserting one made this check fail for the harness's reasons.
# `--cell` selects the shot first, which is what puts its note line on the
# page at y≈370.
page "a line puts its words away when the app goes" notes "PARTING WORDS" \
     --cell description --tap "700,370,1" --after "PARTING WORDS"

# Tab keeps walking forward through the document and crosses out of the shot
# it started in. The exact number of presses is deliberately NOT asserted:
# these events arrive 50ms apart, faster than any hand, and a press landing
# while a line is being built is sometimes swallowed — so a count would be a
# flaky check of the harness rather than a real check of the page. What must
# hold is the direction: enough Tabs always leave the first shot behind, and
# never leave the document (before the page owned Tab, one press walked out
# to the sidebar's "+" and opened a new-scene dialog mid-sentence).
crossing() {
  local fresh="$(mktemp -d)/Cross.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --loud --project "$fresh" --screen 0 --scene 34 \
                   --tab document --tap "795,293,1" \
                   --after "⇥⇥⇥⇥⇥⇥⇥⇥⇥⇥⇥⇥" --columns 2>&1)
  rm -rf "$(dirname "$fresh")"
  sleep 1
  # The layout line names the shot the cursor is in — the page's own report.
  local rests; rests=$(echo "$out" | grep -oE "^layout: [0-9A-Z]+" | tail -1)
  if echo "$out" | grep -q "NEVER GOT THE KEYBOARD"; then
    skip=$((skip+1)); echo "SKIP  Tab crosses into the next shot — no keyboard"
  elif [ -n "$rests" ] && [ "$rests" != "layout: 34A" ]; then
    pass=$((pass+1)); echo "PASS  Tab walks on and crosses out of the shot ($rests)"
  else
    fail=$((fail+1)); echo "FAIL  Tab walks on and crosses out of the shot"
    echo "      $rests"
  fi
}
crossing

# The shot itself: its number in the margin is a handle. Clicking it chooses
# the shot, and then ⌘↑/⌘↓ move it and ⌘⌫ deletes it — the table's grammar,
# on the page. Asserted through the rows report, which prints each row's
# opening words in the scene's order.
shotop() {
  local name="$1"; local want="$2"; shift 2
  local fresh="$(mktemp -d)/Shotop.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --loud --project "$fresh" --screen 0 --scene 34 \
                   --tab document --tap "560,279,1" "$@" 2>&1)
  sleep 1
  local read; read=$("$APP" --project "$fresh" --screen 0 --scene 34 --columns 2>&1)
  rm -rf "$(dirname "$fresh")"
  if echo "$out" | grep -q "NEVER GOT THE KEYBOARD"; then
    skip=$((skip+1)); echo "SKIP  $name — could not take the keyboard (screen locked?)"
  elif echo "$read" | grep "rows=" | grep -q "$want"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$read" | grep -oE "rows=.*" | sed 's/^/      /'
  fi
}

shotop "clicking a number chooses the shot; ⌘↓ moves it" \
       "rows=34A:Felix,34B:Milo" --after "⌘↓"
shotop "…and ⌘⌫ deletes the chosen shot" \
       "rows=34A:Felix,34B:Front,34C:Front,34D:Wide" --after "⌘⌫"

# ---- the sheets, on the real keyboard ---------------------------------------
# Project Settings and Edit Columns are attached sheets. Two things had to be
# true before either could be typed into at all, and neither was:
#   1. A loud run judged itself ready by "is the MAIN window key" — a sheet is
#      key while it is up, so any run that opened one reported that it never
#      got the keyboard.
#   2. The table's key monitor answered for every key with no idea a sheet
#      existed: a name typed into a sheet went into the table's edit buffer,
#      and ⌘A selected every row behind it. That is his bug, not a test's.
#
# The sheet is centred in the standard window: its Title field sits at
# (778, 370).
sheet() {
  local name="$1"; local column="$2"; local want="$3"; shift 3
  local fresh="$(mktemp -d)/Sheet.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --loud --project "$fresh" --screen 0 --scene 34 "$@" 2>&1)
  sleep 1
  local read; read=$("$APP" --project "$fresh" --screen 0 --scene 34 \
                     --cell "$column" --type "" --expect "$want" 2>&1)
  rm -rf "$(dirname "$fresh")"
  if echo "$out" | grep -q "NEVER GOT THE KEYBOARD"; then
    skip=$((skip+1)); echo "SKIP  $name — could not take the keyboard (screen locked?)"
  elif echo "$read" | grep -q "MATCHES"; then
    pass=$((pass+1)); echo "PASS  $name"
  else
    fail=$((fail+1)); echo "FAIL  $name"
    echo "$read" | grep -E "expected" | sed 's/^/      /'
  fi
}

# Typing into a sheet must land in the sheet and nowhere else. Before the fix
# this wrote "ZZZ" into the shot list behind it.
sheet "typing in a sheet never reaches the table" description \
      "Milo French Over — run until \"Did you tell them that you need them?\"" \
      --settings --tap "778,370,1" --after "⌘aZZZ↩"

# And the project's own facts are writable at last: the title was readable
# everywhere and settable nowhere, and the document page prints the credits
# from fields nothing could fill.
project_title() {
  local fresh="$(mktemp -d)/Title.shotlist"
  cp -R studio/fixtures/Daybreak.shotlist "$fresh"
  local out; out=$("$APP" --loud --project "$fresh" --screen 0 --scene 34 \
                   --settings --tap "778,370,1" --after "⌘aTest Name↩" 2>&1)
  sleep 1
  local read; read=$("$APP" --project "$fresh" --screen 0 --scene 34 --columns 2>&1)
  rm -rf "$(dirname "$fresh")"
  if echo "$out" | grep -q "NEVER GOT THE KEYBOARD"; then
    skip=$((skip+1)); echo "SKIP  the project can be renamed — no keyboard"
  elif echo "$read" | grep -q "Test Name"; then
    pass=$((pass+1)); echo "PASS  the project can be renamed, and it sticks"
  else
    fail=$((fail+1)); echo "FAIL  the project can be renamed, and it sticks"
    echo "$read" | grep -oE "titled: .*" | sed 's/^/      /'
  fi
}
project_title

# Undo is informational: cmd-Z inside a cell peels typing back, but the undo
# grouping (whole burst vs last group) is AppKit's own and not asserted.
out=$("$APP" --loud --project "$SCRATCH" --screen 0 --scene 34 --cell notes --type "abc⌘z" 2>&1)
echo "INFO  undo inside the cell: $(echo "$out" | grep 'engine holds' | head -1 | sed 's/.*engine holds/holds/')"

echo "----"
echo "passed $pass, failed $fail, skipped $skip"
[ "$skip" -gt 0 ] && echo "skips mean the loud lane could not take the keyboard — unlock the screen and rerun"
rm -rf "$(dirname "$SCRATCH")"
[ "$fail" -eq 0 ]
