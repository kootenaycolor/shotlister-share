-- Set Up Releasing — double-click once, ever.
-- Asks for the certificate and the key file Apple needs, and puts them where
-- the release script will find them. Everything it asks is a dialogue.

on run
	set repo to (POSIX path of (path to home folder)) & "Developer/shotlister"
	try
		do shell script "cd " & quoted form of repo & " && ./release/setup-signing.sh 2>&1"
	on error message number code
		-- 1 is this script's own "he clicked Later", which is not a fault.
		if code is not 1 then
			display dialog "Setting up did not finish." & return & return & message ¬
				with title "Set up releasing" buttons {"OK"} default button "OK" with icon stop
		end if
	end try
end run
