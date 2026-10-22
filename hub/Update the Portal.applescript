-- Update the Portal — double-click when you have written something in Notion.
--
-- Brings every film's words at your-domain.example up to date from Notion —
-- the logline, the status, the shoot dates, the documents you have ticked Hub
-- on, the camera spec sheet and the crew. What the film itself knows (credits,
-- format, scenes, shots, locations, days) the portal reads from the film on
-- every look, since 2026-09-16; nothing has to be pressed for that.
--
-- Source of `Apps/Update the Portal.app`; rebuild it with `hub/build-apps.sh`.
--
-- **Your chosen photograph is never touched.** That is set on the portal, and a
-- refresh that quietly changed it would be the worst kind of automation.
--
-- Running it twice is harmless. Nothing here can change a film — it only ever
-- writes the small card the portal draws from.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"

	set connected to false
	try
		do shell script "security find-generic-password -s shotlister-notion -a shotlister-notion-token -w"
		set connected to true
	end try

	if connected then
		display dialog "Notion words, onto every film's page. A Terminal window shows what it found." ¬
			with title "Update the Portal" buttons {"Cancel", "Update"} default button "Update"
		if button returned of result is "Cancel" then return
	else
		display dialog "Notion is not connected." & return & return & ¬
			"Connecting it puts the logline, the status, the shoot dates, the documents you tick Hub on, the camera spec sheet and the crew on each film's page. About a minute, once." ¬
			with title "Update the Portal" buttons {"Cancel", "Connect Notion…", "Update anyway"} default button "Connect Notion…"

		set chose to button returned of result
		if chose is "Cancel" then return

		if chose is "Connect Notion…" then
			display dialog "Notion's developer page will open in your browser." & return & return & ¬
				"1.  Press “New token”." & return & ¬
				"2.  Name it Shotlister and choose your workspace." & return & ¬
				"3.  Tick the “Notion API” capability." & return & ¬
				"4.  Press “Create token”, then copy it." & return & return & ¬
				"Then come back here and paste it. Notion shows it once." ¬
				with title "Connect Notion" buttons {"Cancel", "Open Notion"} default button "Open Notion"
			if button returned of result is "Cancel" then return

			open location "https://www.notion.so/developers"

			-- **Off the clipboard, not out of a text field.** A `with hidden
			-- answer` box is a secure text field, and macOS turns paste into one
			-- unreliable whenever anything else on the machine has secure input
			-- enabled — a password manager, usually. He hit exactly that. The
			-- relay password already travels this way for the same reason.
			display dialog "Copy the token in Notion — the whole thing." & return & return & ¬
				"Then press Take it from the clipboard, and nothing has to be typed or pasted anywhere." ¬
				with title "Connect Notion" buttons {"Cancel", "Take it from the clipboard"} ¬
				default button "Take it from the clipboard"
			if button returned of result is "Cancel" then return

			set secret to ""
			try
				set secret to (the clipboard as text)
			end try
			set secret to my trimmed(secret)

			if secret is "" then
				display dialog "There is nothing on the clipboard." & return & return & ¬
					"Copy the token in Notion, then run this again." ¬
					with title "Connect Notion" buttons {"Alright"} default button "Alright"
				return
			end if

			-- Said rather than assumed: a token he half-copied, or the page's
			-- title copied by accident, would otherwise be saved and then fail
			-- every time with nothing to point at.
			if secret does not start with "ntn_" and secret does not start with "secret_" then
				display dialog "That does not look like a Notion token." & return & return & ¬
					"A token begins with ntn_ and is about fifty characters. What is on the clipboard begins with:" & return & return & ¬
					"“" & (text 1 thru (my atMost(secret, 24)) of secret) & "…”" & return & return & ¬
					"Copy the token itself and run this again." ¬
					with title "Connect Notion" buttons {"Alright"} default button "Alright"
				return
			end if

			do shell script "security add-generic-password -s shotlister-notion -a shotlister-notion-token -w " & quoted form of secret & " -U"

			-- **A token of this kind needs no page shared with it**, which is the
			-- whole reason to prefer it: it reads as you, with your own
			-- permissions. The older kind — a "connection" — sees nothing at all
			-- until a page is added to it, and fails silently when one has not
			-- been. Said here in case he made one of those instead.
			display dialog "Saved." & return & return & ¬
				"A token reads Notion as you, so there is nothing else to set up. The Terminal window will say whose workspace it reached." & return & return & ¬
				"If you made a connection rather than a token, it also needs adding to your Cinematography page: ••• at the top right, then Add connections. Without that it sees nothing and says nothing." ¬
				with title "Connect Notion" buttons {"Done"} default button "Done"
		end if
	end if

	tell application "Terminal"
		activate
		do script "cd " & quoted form of repo & " && ./hub/refresh.py"
	end tell
end run

-- Whitespace either end, because a copied token often brings a newline with it
-- and the Keychain would keep it.
on trimmed(said)
	set was to said
	repeat while was is not "" and (character 1 of was) is in {" ", tab, return, linefeed}
		set was to text 2 thru -1 of was
	end repeat
	repeat while was is not "" and (character -1 of was) is in {" ", tab, return, linefeed}
		set was to text 1 thru -2 of was
	end repeat
	return was
end trimmed

on atMost(said, many)
	if (count of said) < many then return (count of said)
	return many
end atMost
