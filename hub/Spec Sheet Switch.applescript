-- Spec Sheet Switch · shows whether the portal reads the new spec sheet.
--
-- Off: every reader takes the Camera Spec Sheet from Notion, as before. On: a
-- shoot with a sheet on its project record reads that instead (phase 1 of
-- design/spec-sheet.md). He turns it on only once the Console's spec sheet
-- editor is installed, so the sheet has somewhere to be edited.
--
-- Source of `Apps/Spec Sheet Switch.app`; rebuild it with `hub/build-apps.sh`,
-- which also puts `hub/spec-sheets.py` inside the app.

on run
	set helper to quoted form of (POSIX path of (path to me) & "Contents/Resources/spec-sheets.py")

	set state to do shell script "/usr/bin/python3 " & helper & " switch 2>&1 || true"
	set rows to paragraphs of state
	if (count of rows) is 0 or (item 1 of rows) is not in {"On", "Off"} then
		my sayProblem(rows)
		return
	end if
	set now to item 1 of rows

	if now is "Off" then
		display dialog "New spec sheet: Off" & return & return & ¬
			"Turn it on only after the Console editor is installed." ¬
			with title "Spec Sheet Switch" buttons {"Cancel", "Turn On"} default button "Cancel" cancel button "Cancel"
		set want to "on"
	else
		display dialog "New spec sheet: On" ¬
			with title "Spec Sheet Switch" buttons {"Cancel", "Turn Off"} default button "Cancel" cancel button "Cancel"
		set want to "off"
	end if

	set state to do shell script "/usr/bin/python3 " & helper & " switch " & want & " 2>&1 || true"
	set rows to paragraphs of state
	if (count of rows) is 0 or (item 1 of rows) is not in {"On", "Off"} then
		my sayProblem(rows)
		return
	end if
	display dialog "New spec sheet: " & (item 1 of rows) ¬
		with title "Spec Sheet Switch" buttons {"OK"} default button "OK"
end run

on sayProblem(rows)
	if (count of rows) > 0 and (item 1 of rows) is "PROBLEM" then set rows to rest of rows
	set AppleScript's text item delimiters to return
	set said to rows as text
	set AppleScript's text item delimiters to ""
	if said is "" then set said to "Something went wrong and the hub gave no reason. Nothing was changed."
	display dialog said with title "Spec Sheet Switch" buttons {"OK"} default button "OK" with icon caution
end sayProblem
