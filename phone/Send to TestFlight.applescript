-- Send to TestFlight — double-click to put the iPhone app on TestFlight.
--
-- Runs `phone/testflight.sh` in one Terminal window: the phone's checks, a
-- signed build with the next number Apple has not seen, and the upload. Its
-- last line says how it went. Apple then takes 5 to 15 minutes before the
-- build shows in the TestFlight app.
--
-- Source of `Apps/Send to TestFlight.app`; rebuild it with osacompile (see
-- hub/build-apps.sh for the icon and signing steps it shares).

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"
	
	display dialog "Build the iPhone app and send it to TestFlight. A Terminal window shows how it goes." with title "Send to TestFlight" buttons {"Cancel", "Send"} default button "Send"
	if button returned of result is "Cancel" then return
	
	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./phone/testflight.sh"
	end tell
end run
