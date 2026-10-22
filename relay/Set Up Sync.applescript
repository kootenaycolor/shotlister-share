-- Set Up Sync — double-click once, ever.
--
-- Puts the sync relay on your own Cloudflare account. It opens a Terminal
-- window because one step is signing in to Cloudflare in a browser, and you
-- need to be able to see that happen and come back to it.
--
-- Everything else is automatic, and running it twice is harmless.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"

	display dialog "This puts your own sync server on Cloudflare." & return & return & ¬
		"It is free at your size, and it takes about two minutes. A browser window will open once, to sign in to Cloudflare." & return & return & ¬
		"A Terminal window will show what is happening." ¬
		with title "Set up sync" buttons {"Later", "Set it up"} default button "Set it up"

	if button returned of result is "Later" then return

	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./relay/setup.sh"
	end tell
end run
