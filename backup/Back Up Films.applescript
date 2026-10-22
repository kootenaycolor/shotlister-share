-- Back Up Films — double-click any time you want a copy of where things stand.
--
-- It takes a dated snapshot of every film's complete history and puts it in
-- iCloud Drive, beside the films themselves. Photographs are not in it: they
-- already exist in three places and are three hundred times the size of the
-- list. See backup/backup.sh for the reasoning.
--
-- Running it twice in a row is harmless — a film that has not changed since the
-- last one is skipped rather than copied again.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"
	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./backup/backup.sh; echo; echo 'Done — you can close this window.'"
	end tell
end run
