-- Reveal the playing file in Finder, bound to i.
--
-- Was on l until 2026-09-03, when l became the audio-language key.
--
-- `open -R` opens the file's enclosing folder in a Finder window with the file
-- already selected - the same state you would get by clicking it there.
--
-- The subprocess is run ASYNC. The synchronous `subprocess` command blocks
-- mpv's main thread until the child exits, which is a visible hitch in playback
-- for something that takes ~100ms; async costs nothing and still reports back.

local function reveal()
    local path = mp.get_property("path")
    if not path then
        mp.osd_message("Nothing playing", 2)
        return
    end

    -- streams (http://, ytdl://) have no folder to open
    if path:match("^%a[%w+.-]*://") then
        mp.osd_message("Not a local file", 2)
        return
    end

    -- mpv keeps `path` exactly as the playlist entry gave it, which can be
    -- relative; Finder needs an absolute one.
    if not path:match("^/") then
        local wd = mp.get_property("working-directory")
        if wd then path = wd .. "/" .. path end
    end

    mp.command_native_async({
        name           = "subprocess",
        args           = { "open", "-R", path },
        playback_only  = false,          -- must survive the end of a file
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res, err)
        if ok and res and res.status == 0 then
            mp.msg.verbose("revealed " .. path)
            mp.osd_message("Revealed in Finder", 1.5)
        else
            mp.osd_message("Could not reveal this file", 2)
            mp.msg.error("open -R failed: " ..
                tostring(err or (res and res.stderr) or "unknown"))
        end
    end)
end

mp.add_key_binding(nil, "reveal-in-finder", reveal)
