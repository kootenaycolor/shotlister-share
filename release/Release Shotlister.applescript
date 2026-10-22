-- Release Shotlister — double-click to put a new version out.
-- Nathaniel does not run commands; this is the command, wearing an icon.
--
-- The work takes about ten minutes, nearly all of it waiting on Apple, so this
-- does not just block and go quiet: it starts the script in the background and
-- reads its output back into a progress window, so there is always a line
-- saying what is happening. A ten-minute silence is indistinguishable from a
-- hang, and a hang is the thing he would reasonably kill.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"
	set logf to repo & "/release/out/release.log"

	-- **Which number is going out.** Until 2026-09-01 this was a line he had to
	-- edit in a text file first, and forgetting it was the only thing a
	-- double-click ever did: release.sh refuses a version that already has a
	-- tag, so the app stopped one second in saying "put a newer number in
	-- release/VERSION". Asking is the whole fix. The choice is his because it
	-- is a judgement -- a handful of fixes is not a new set of features -- and
	-- nothing else in here can make it.
	try
		set facts to paragraphs of (do shell script quoted form of (repo & "/release/next-version.sh"))
	on error reason
		display dialog "Cannot work out the next version number." & return & return & reason ¬
			with title "Release Shotlister" buttons {"OK"} default button "OK" with icon stop
		return
	end try
	set lastVersion to item 1 of facts
	set fixVersion to item 2 of facts
	set featureVersion to item 3 of facts
	set changeCount to item 4 of facts

	if changeCount is "0" then
		display dialog "Nothing new since " & lastVersion & "." ¬
			with title "Release Shotlister" buttons {"OK"} default button "OK" with icon note
		return
	end if

	if changeCount is "1" then
		set sinceLine to "1 change since."
	else
		set sinceLine to changeCount & " changes since."
	end if

	set fixButton to "Small fixes — " & fixVersion
	set featureButton to "New features — " & featureVersion
	try
		display dialog "Last release: " & lastVersion & return & sinceLine ¬
			with title "Release Shotlister" ¬
			buttons {"Cancel", fixButton, featureButton} default button featureButton with icon note
		set chosen to button returned of result
	on error number -128
		return
	end try
	if chosen is fixButton then
		set newVersion to fixVersion
	else
		set newVersion to featureVersion
	end if

	-- Written, not appended: release.sh reads this file and nothing else for
	-- the number it publishes under.
	do shell script "printf '%s\\n' " & quoted form of newVersion & " > " & ¬
		quoted form of (repo & "/release/VERSION")

	do shell script "mkdir -p " & quoted form of (repo & "/release/out") & " && rm -f " & quoted form of logf
	set pid to do shell script "cd " & quoted form of repo & ¬
		" && nohup ./release/release.sh > " & quoted form of logf & " 2>&1 & echo $!"

	set progress total steps to -1
	set progress description to "Releasing Shotlister " & newVersion
	set progress additional description to "Starting…"

	repeat
		delay 2
		-- The last line of output, with the bold codes stripped out of it.
		try
			set lastLine to do shell script "tail -n 1 " & quoted form of logf & ¬
				" | sed $'s/\\033\\[[0-9;]*m//g' | sed 's/^→ //'"
			if lastLine is not "" then set progress additional description to lastLine
		end try
		try
			do shell script "kill -0 " & pid
		on error
			exit repeat
		end try
	end repeat

	set progress additional description to "Finishing…"
	set outcome to do shell script "cat " & quoted form of logf & " | sed $'s/\\033\\[[0-9;]*m//g'"
	set progress total steps to 0

	if outcome contains "✓ Shotlister Studio" then
		set version to do shell script "cat " & quoted form of (repo & "/release/VERSION")
		display dialog "Shotlister Studio " & version & " is out." & return & return & ¬
			"Your other Mac will be offered it the next time the app is open. Nothing else to do." ¬
			with title "Release Shotlister" buttons {"OK", "Show the download page"} default button "OK" with icon note
		if button returned of result is "Show the download page" then
			open location "https://github.com/YOUR_GITHUB_USER/shotlister-releases/releases/latest"
		end if
	else
		-- The reason, not the wall of output it came wrapped in.
		set trouble to do shell script "printf %s " & quoted form of outcome & ¬
			" | grep -v '^ ' | tail -n 8"
		display dialog "The release did not finish." & return & return & trouble ¬
			with title "Release Shotlister" buttons {"OK"} default button "OK" with icon stop
	end if
end run
