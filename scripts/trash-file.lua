-- Move the playing file to the Trash, bound to Cmd+Delete.
--
-- /usr/bin/trash ships with macOS (14+) and goes through the real Trash API,
-- so Finder records where the file came from and its right-click "Put Back"
-- restores it. That is the only undo here on purpose - moving files back out
-- of ~/.Trash ourselves would need Full Disk Access, which mpv has no reason
-- to hold. Two rejected alternatives, for the record:
--   * mv to ~/.Trash        - no Put Back info, and breaks across volumes
--   * NSFileManager via JXA - segfaulted (exit 139) while still trashing the
--                             file, so success could not be told from failure
--
-- The subprocess is ASYNC, like reveal-in-finder.lua: the sync `subprocess`
-- command blocks mpv's main thread until the child exits, which is a visible
-- hitch in playback.

local options = require 'mp.options'

local opts = {
    confirm = false,      -- yes = require a second press within confirm_secs
    confirm_secs = 3,
}
options.read_options(opts, "trash_file")

-- mpv keeps `path` exactly as the playlist entry gave it, which can be
-- relative; the Trash API needs an absolute one.
local function abs(path)
    if path:match("^/") then return path end
    local wd = mp.get_property("working-directory")
    return wd and (wd .. "/" .. path) or path
end

-- Entry ids are stable for the life of the playlist, indices are not: by the
-- time the trash subprocess reports back the user may have stepped to another
-- file, and playlist-remove only takes an index. So remember the id and look
-- its index up again at the end.
local function index_of_id(id)
    local pl = mp.get_property_native("playlist") or {}
    for i, entry in ipairs(pl) do
        if entry.id == id then return i - 1 end
    end
    return nil
end

local function do_trash()
    local path = mp.get_property("path")
    if not path then
        mp.osd_message("Nothing playing", 2)
        return
    end

    -- streams (http://, ytdl://) are not files and cannot be trashed
    if path:match("^%a[%w+.-]*://") then
        mp.osd_message("Not a local file", 2)
        return
    end

    path = abs(path)
    local name = mp.get_property("filename") or path
    local pos  = mp.get_property_number("playlist-pos")
    local pl   = mp.get_property_native("playlist") or {}
    local id   = pos and pl[pos + 1] and pl[pos + 1].id

    mp.command_native_async({
        name           = "subprocess",
        args           = { "/usr/bin/trash", "-v", path },
        playback_only  = false,          -- must survive the end of a file
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res, err)
        if not (ok and res and res.status == 0) then
            -- trash exits 5 when the file is already gone
            mp.osd_message("Could not trash this file", 2)
            mp.msg.error("trash failed: " ..
                tostring(err or (res and res.stderr) or "unknown"))
            return
        end

        mp.msg.info("trashed " .. path)

        -- Dropping the current entry is what moves playback on: mpv starts the
        -- next file by itself. On the last entry there is nothing to start, so
        -- mpv ends playback - with keep-open=no in mpv.conf that means it quits.
        local i = id and index_of_id(id)
        if i then
            mp.commandv("playlist-remove", i)
        end

        -- after the remove, so a position written during the handover goes too
        mp.commandv("delete-watch-later-config", path)
        mp.osd_message("Moved to Trash: " .. name, 2)
    end)
end

-- off by default: Cmd+Delete is a deliberate chord, and Finder's Put Back
-- means a mistake is recoverable. Set confirm=yes in script-opts/trash_file.conf
-- to require two presses instead.
local armed = nil

local function trash()
    if not opts.confirm then return do_trash() end
    if armed then
        armed:kill(); armed = nil
        return do_trash()
    end
    local name = mp.get_property("filename")
    if not name then
        mp.osd_message("Nothing playing", 2)
        return
    end
    mp.osd_message("Press again to trash: " .. name, opts.confirm_secs)
    armed = mp.add_timeout(opts.confirm_secs, function() armed = nil end)
end

mp.add_key_binding(nil, "trash-file", trash)
