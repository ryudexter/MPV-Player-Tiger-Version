-- Reset rules for saved playback positions (watch_later).
--
-- mpv only clears a saved position when you watch a file to the end.
-- This adds:
--   1. expiry   - positions older than `expire_days` are deleted at startup
--   2. reset    - a binding that wipes the saved position of every file in the
--                 CURRENT playlist and leaves every other one alone
--                 (bound to 0 in input.conf via script-binding)
--   3. reset-all - the older wipe-the-whole-folder behaviour, still registered
--                 as "reset-all-watch-later" but deliberately left unbound

local utils   = require 'mp.utils'
local options = require 'mp.options'

local opts = {
    expire_days = 30,   -- 0 disables expiry
    confirm     = true, -- require a second press within confirm_secs
    confirm_secs = 3,
}
options.read_options(opts, "watch_later_reset")

local function wl_dir()
    -- honour --watch-later-dir if set, otherwise mpv's default location
    local d = mp.get_property("watch-later-dir")
    if d and d ~= "" then
        return mp.command_native({"expand-path", d})
    end
    return mp.command_native({"expand-path", "~~state/watch_later"})
end

local function entries(dir)
    local list = utils.readdir(dir, "files")
    return list or {}
end

local function count(dir)
    return #entries(dir)
end

-- 1. expire old entries, once, at startup
local function expire()
    if opts.expire_days <= 0 then return end
    local dir = wl_dir()
    local cutoff = os.time() - (opts.expire_days * 86400)
    local removed = 0
    for _, name in ipairs(entries(dir)) do
        local path = utils.join_path(dir, name)
        local info = utils.file_info(path)
        if info and not info.is_dir and info.mtime and info.mtime < cutoff then
            if os.remove(path) then removed = removed + 1 end
        end
    end
    if removed > 0 then
        mp.msg.info(string.format("expired %d saved position(s) older than %d days",
                                  removed, opts.expire_days))
    end
end

-- 2. the files this reset is allowed to touch
--
-- Every saved position lives under an MD5 of the file's path, so there is no
-- way to look at the watch_later folder and tell which entries belong to the
-- playlist on screen. Rather than re-implement mpv's hashing here (it also
-- folds in --ignore-path-in-watch-later-config and URL handling, and has
-- changed between releases), hand each path back to mpv and let it delete its
-- own entry: delete-watch-later-config takes the same filename argument that
-- write-watch-later-config would have hashed.
local function playlist_targets()
    local pl = mp.get_property_native("playlist") or {}
    local list, seen = {}, {}
    local function add(p)
        if p and p ~= "" and not seen[p] then
            seen[p] = true
            list[#list + 1] = p
        end
    end
    for i, entry in ipairs(pl) do
        add(entry.filename)
        -- The folder or .m3u an entry came from gets its own watch_later file -
        -- a "# redirect entry", which is what makes reopening the folder land
        -- back on the file you left off on. Clearing the 600 videos but not
        -- that pointer would leave the playlist itself still resumed.
        add(entry["playlist-path"])
        add(mp.get_property("playlist/" .. (i - 1) .. "/playlist-path"))
    end
    add(mp.get_property("playlist-path"))
    return list, #pl
end

-- 3. delete, and report how many entries actually disappeared
--
-- delete-watch-later-config succeeds whether or not the file existed, so the
-- count comes from the folder shrinking, not from the command's return value.
local function wipe(paths)
    local dir = wl_dir()
    local before = count(dir)
    for _, p in ipairs(paths) do
        mp.commandv("delete-watch-later-config", p)
    end
    local removed = before - count(dir)
    -- the file playing right now would otherwise re-save its position on quit,
    -- so send it back to the start too
    if removed > 0 then
        mp.commandv("seek", 0, "absolute")
    end
    mp.msg.info(string.format("removed %d entries from %s", removed, dir))
    return removed
end

local function wipe_all()
    local dir = wl_dir()
    local removed = 0
    for _, name in ipairs(entries(dir)) do
        local path = utils.join_path(dir, name)
        local info = utils.file_info(path)
        if info and not info.is_dir then
            if os.remove(path) then removed = removed + 1 end
        end
    end
    if removed > 0 then
        mp.commandv("seek", 0, "absolute")
    end
    mp.msg.info(string.format("reset_all removed %d entries from %s", removed, dir))
    return removed
end

-- bound to a bare key, so a stray press must not silently wipe anything:
-- the first press only arms it, a second within confirm_secs commits
local armed = nil

local function arm(prompt, commit)
    if not opts.confirm then return commit() end
    if armed then
        armed:kill(); armed = nil
        return commit()
    end
    if not prompt() then return end
    armed = mp.add_timeout(opts.confirm_secs, function() armed = nil end)
end

local function plural(n) return n == 1 and "" or "s" end

local function reset_playlist()
    arm(function()
        local _, n = playlist_targets()
        -- n is how many files are in scope, not how many of them have a saved
        -- position: that is only knowable after mpv has done the deleting.
        mp.osd_message(string.format("Press again to reset %d file%s in this playlist",
                                     n, plural(n)), opts.confirm_secs)
        return true
    end, function()
        local paths = playlist_targets()
        local removed = wipe(paths)
        if removed == 0 then
            mp.osd_message("Nothing saved for this playlist", 2)
        else
            mp.osd_message(string.format("Reset %d saved position%s in this playlist",
                                         removed, plural(removed)), 2)
        end
    end)
end

local function reset_all()
    arm(function()
        local n = count(wl_dir())
        if n == 0 then
            mp.osd_message("No saved positions to clear", 2)
            return false
        end
        mp.osd_message(string.format("Press again to clear ALL %d saved position%s",
                                     n, plural(n)), opts.confirm_secs)
        return true
    end, function()
        local removed = wipe_all()
        mp.osd_message(string.format("Cleared %d saved position%s",
                                     removed, plural(removed)), 2)
    end)
end

mp.add_key_binding(nil, "reset-playlist-watch-later", reset_playlist)
mp.add_key_binding(nil, "reset-all-watch-later", reset_all)
mp.register_event("file-loaded", function()
    if not _G.__wl_expired then _G.__wl_expired = true; expire() end
end)
