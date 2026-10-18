-- Reveal the playing file in Finder, bound to i.
--
-- Was on l until 2026-09-03, when l became the audio-language key.
--
-- `open -R` opens the file's enclosing folder in a Finder window with the file
-- already selected - the same state you would get by clicking it there.
--
-- Windows and Linux get the same thing from their own file manager:
--   Windows  File Explorer, through `mpv-open.exe --reveal` (the launcher
--            install.ps1 builds), which calls SHOpenFolderAndSelectItems - the
--            API behind Explorer's own "Open file location". Without that exe
--            it falls back to `explorer /select,`, which works too but always
--            exits 1, success or not, so its exit status says nothing.
--   Linux    the org.freedesktop.FileManager1 D-Bus call that Files (GNOME),
--            Dolphin, Nemo, Caja and Thunar all answer, which opens the folder
--            with the file selected. A desktop with no such file manager gets
--            the folder opened with xdg-open instead, without the selection.
--
-- The subprocess is run ASYNC. The synchronous `subprocess` command blocks
-- mpv's main thread until the child exits, which is a visible hitch in playback
-- for something that takes ~100ms; async costs nothing and still reports back.

local utils = require 'mp.utils'

local PLATFORM = mp.get_property("platform")   -- "darwin", "windows", "linux", ...

local function run(args, done)
    mp.command_native_async({
        name           = "subprocess",
        args           = args,
        playback_only  = false,          -- must survive the end of a file
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res, err) done(ok and res or {}, err) end)
end

local function failed(what, res, err)
    mp.osd_message("Could not reveal this file", 2)
    mp.msg.error(what .. " failed: " ..
        tostring(err or res.stderr or res.error_string or "unknown"))
end

local function reveal_mac(path)
    run({ "open", "-R", path }, function(res, err)
        if res.status == 0 then
            mp.msg.verbose("revealed " .. path)
            mp.osd_message("Revealed in Finder", 1.5)
        else
            failed("open -R", res, err)
        end
    end)
end

local function reveal_windows(path)
    path = path:gsub("/", "\\")          -- Explorer reads only backslashes
    local helper = mp.command_native({ "expand-path", "~~/mpv-open.exe" })
    local function explorer()
        run({ "explorer.exe", "/select," .. path }, function(res, err)
            if res.error_string == "init" then return failed("explorer", res, err) end
            mp.osd_message("Revealed in File Explorer", 1.5)
        end)
    end
    if not utils.file_info(helper) then return explorer() end
    run({ helper, "--reveal", path }, function(res, err)
        if res.status == 0 then
            mp.msg.verbose("revealed " .. path)
            mp.osd_message("Revealed in File Explorer", 1.5)
        elseif res.error_string == "init" then
            explorer()
        else
            failed("mpv-open --reveal", res, err)
        end
    end)
end

-- A file:// URI, as FileManager1 wants it. Every byte outside the unreserved
-- set is escaped - commas included, since dbus-send splits array items on them.
local function file_uri(path)
    return "file://" .. path:gsub("[^%w%-%._~/]", function(c)
        return string.format("%%%02X", c:byte())
    end)
end

local function reveal_linux(path)
    local dir = utils.split_path(path)
    run({ "dbus-send", "--session", "--print-reply",
          "--dest=org.freedesktop.FileManager1", "--type=method_call",
          "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1.ShowItems",
          "array:string:" .. file_uri(path), "string:" }, function(res)
        if res.status == 0 then
            mp.msg.verbose("revealed " .. path)
            mp.osd_message("Revealed in the file manager", 1.5)
            return
        end
        mp.msg.verbose("FileManager1 did not answer, opening the folder instead")
        run({ "xdg-open", dir }, function(res2, err2)
            if res2.status == 0 then
                mp.osd_message("Opened its folder", 1.5)
            else
                failed("xdg-open", res2, err2)
            end
        end)
    end)
end

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
    -- relative; Finder needs an absolute one. join_path leaves an absolute
    -- path alone, and knows a Windows one (C:\, \\server\) when it sees it.
    local wd = mp.get_property("working-directory")
    if wd then path = utils.join_path(wd, path) end

    if PLATFORM == "windows" then
        reveal_windows(path)
    elseif PLATFORM == "darwin" then
        reveal_mac(path)
    else
        reveal_linux(path)
    end
end

mp.add_key_binding(nil, "reveal-in-finder", reveal)
