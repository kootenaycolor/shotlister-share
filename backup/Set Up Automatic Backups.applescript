-- Set Up Automatic Backups — double-click once, ever.
--
-- Asks macOS to run the backup every day at lunchtime, and whenever the Mac
-- wakes up having missed it. Nothing else changes; you can still take one by
-- hand with "Back Up Films" whenever you want.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"

	display dialog "Back your films up automatically, once a day?" & return & return & ¬
		"A snapshot of every film's full history goes into iCloud Drive. It is about a third of a megabyte, so it costs nothing." & return & return & ¬
		"You can still take one by hand at any time." ¬
		with title "Automatic backups" buttons {"Not now", "Set it up"} default button "Set it up"

	if button returned of result is "Not now" then return

	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./backup/agent.sh"
	end tell
end run
