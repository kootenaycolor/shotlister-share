-- Restore a Film — go back to how a film was on a particular day.
--
-- Lists every backup there is, newest first. Pick a number and the film lands
-- on your Desktop under its own name, so you can open it beside the one you are
-- working in and compare before deciding anything.
--
-- **It cannot overwrite the film you are working in**, on purpose. The whole
-- point of a backup is to be sure, and a restore that clobbers is a second way
-- to lose work.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"
	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./backup/restore.sh"
	end tell
end run
