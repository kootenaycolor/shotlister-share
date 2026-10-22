-- Move Spec Sheets · double-click once, after ticking the look.
--
-- Copies every Camera Spec Sheet from Notion onto its project record on the
-- hub (phase 1 of design/spec-sheet.md). First it shows what each sheet would
-- become, then asks. Notion is only read, never written.
--
-- Source of `Apps/Move Spec Sheets.app`; rebuild it with `hub/build-apps.sh`,
-- which also puts `hub/spec-sheets.py` inside the app. That helper does the
-- talking to the hub, with the sync password read from the Keychain when he
-- runs it.
--
-- **Running it twice is harmless.** The hub's move never writes over a sheet
-- the record already has; a second run says there is nothing left to move.

on run
	set helper to quoted form of (POSIX path of (path to me) & "Contents/Resources/spec-sheets.py")

	set looked to do shell script "/usr/bin/python3 " & helper & " look 2>&1 || true"
	set rows to paragraphs of looked
	if (count of rows) is 0 or (item 1 of rows) does not start with "MOVABLE " then
		my sayProblem(rows)
		return
	end if

	-- "MOVABLE <n> OF <m>"
	set counts to words of (item 1 of rows)
	set movable to (item 2 of counts) as integer
	set total to (item 4 of counts) as integer
	set summary to my joined(rest of rows)

	if movable is 0 then
		display dialog "Nothing to move." & return & return & summary ¬
			with title "Move Spec Sheets" buttons {"OK"} default button "OK"
		return
	end if

	if movable is 1 then
		set question to "Move this spec sheet?"
	else
		set question to "Move these " & movable & " spec sheets?"
	end if

	display dialog summary & return & return & question ¬
		with title "Move Spec Sheets" buttons {"Cancel", "Move"} default button "Move" cancel button "Cancel"

	set moved to do shell script "/usr/bin/python3 " & helper & " move 2>&1 || true"
	set rows to paragraphs of moved
	if (count of rows) is 0 or (item 1 of rows) is not "DONE" then
		my sayProblem(rows)
		return
	end if
	display dialog my joined(rest of rows) ¬
		with title "Move Spec Sheets" buttons {"OK"} default button "OK"
end run

on sayProblem(rows)
	if (count of rows) > 0 and (item 1 of rows) is "PROBLEM" then set rows to rest of rows
	set said to my joined(rows)
	if said is "" then set said to "Something went wrong and the hub gave no reason. Nothing was changed."
	display dialog said with title "Move Spec Sheets" buttons {"OK"} default button "OK" with icon caution
end sayProblem

on joined(rows)
	set AppleScript's text item delimiters to return
	set out to rows as text
	set AppleScript's text item delimiters to ""
	return out
end joined
