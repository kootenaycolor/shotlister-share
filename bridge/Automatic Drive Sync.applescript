-- Turn the automatic Drive sync on or off.
--
-- Its own thing: not behind the ◉ menu, not part of the projects console.
--
-- **This file is the source; the app at the repo root is built from it.**
-- It lived only as a compiled script inside the bundle until 2026-08-23, which
-- is why it went on saying "every five minutes" for two days after that number
-- was corrected everywhere else. Edit here, then run bridge/build-toggle.sh.

set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"

set state to do shell script "cd " & quoted form of repo & " && ./bridge/agent.sh status"

if state is "on" then
	set answer to button returned of (display dialog "Automatic syncing is ON." & return & return & "Location photos move between Shotlister and Google Drive by themselves, every fifteen seconds." buttons {"See the log", "Turn off", "Leave it on"} default button "Leave it on" with title "Automatic Drive Sync")
	if answer is "Turn off" then
		do shell script "cd " & quoted form of repo & " && ./bridge/agent.sh remove"
		display dialog "Automatic syncing is off." & return & return & "You can still sync whenever you like by double-clicking Sync Locations with Drive." buttons {"OK"} default button "OK" with title "Automatic Drive Sync"
	else if answer is "See the log" then
		set theLog to do shell script "cd " & quoted form of repo & " && ./bridge/agent.sh log"
		display dialog theLog buttons {"OK"} default button "OK" with title "Automatic Drive Sync"
	end if
else
	set answer to button returned of (display dialog "Automatic syncing is OFF." & return & return & "Turn it on and location photos will move between Shotlister and Google Drive by themselves, every fifteen seconds." & return & return & "It never deletes anything, on either side." buttons {"Cancel", "Turn on"} default button "Turn on" with title "Automatic Drive Sync")
	if answer is "Turn on" then
		do shell script "cd " & quoted form of repo & " && ./bridge/agent.sh install"
		display dialog "Automatic syncing is on." & return & return & "It runs every fifteen seconds, whether or not this app is open. Double-click here again to check on it or turn it off." buttons {"Good"} default button "Good" with title "Automatic Drive Sync"
	end if
end if
