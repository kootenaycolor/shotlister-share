-- Deploy Shotlister — double-click whenever the relay or the hub has changed.
--
-- Runs `relay/deploy.sh` and then `hub/deploy.sh`, in that order, in one
-- Terminal window. The order is a rule, not a habit: the hub reads what the
-- relay stores, so when a change touches a file format both know, the server
-- goes out first. Each one ends with one line — `relay: 041bb8a live`,
-- `hub: 041bb8a live` — and `hub/drift.sh` can say later how far behind
-- `main` either has drifted.
--
-- It deploys from `main` as the checkout has it, and refuses if any file the
-- worker is built from has uncommitted changes. Set Up Sync and Set Up the
-- Hub are the one-time doors; this is the everyday one.
--
-- Source of `Apps/Deploy Shotlister.app`; rebuild it with `hub/build-apps.sh`.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"

	display dialog "Relay first, then the hub. A Terminal window shows what went live." ¬
		with title "Deploy Shotlister" buttons {"Cancel", "Deploy"} default button "Deploy"
	if button returned of result is "Cancel" then return

	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./relay/deploy.sh && ./hub/deploy.sh"
	end tell
end run
