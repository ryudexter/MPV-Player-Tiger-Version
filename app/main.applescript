-- mpv.app wrapper.
-- The real logic lives in ~/.config/mpv/mpv-open, deliberately OUTSIDE this
-- bundle: editing anything inside mpv.app breaks its ad-hoc signature, and
-- re-signing changes the cdhash macOS ties privacy grants to, which makes the
-- "would like to access files in your Desktop folder" prompt come back.
property helper : "$HOME/.config/mpv/mpv-open"

on run
	do shell script "\"$HOME/.config/mpv/mpv-open\" > /dev/null 2>&1 &"
end run

on open theFiles
	set argList to ""
	repeat with f in theFiles
		set argList to argList & " " & quoted form of POSIX path of f
	end repeat
	do shell script "\"$HOME/.config/mpv/mpv-open\"" & argList & " > /dev/null 2>&1 &"
end open

