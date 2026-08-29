-- Reset rules for saved playback positions (watch_later).
--
-- mpv only clears a saved position when you watch a file to the end.
-- This adds:
--   1. expiry  - positions older than `expire_days` are deleted at startup
--   2. reset   - a binding that wipes every saved position at once
--                (bound to Cmd+0 in input.conf via script-binding)

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

-- 2. wipe every saved position
local armed_timer = nil

local function do_reset()
    local dir = wl_dir()
    local list = entries(dir)
    local removed = 0
    for _, name in ipairs(list) do
        local path = utils.join_path(dir, name)
        local info = utils.file_info(path)
        if info and not info.is_dir then
            if os.remove(path) then removed = removed + 1 end
        end
    end
    -- the file playing right now would otherwise re-save its position on quit,
    -- so send it back to the start too
    if removed > 0 then
        mp.commandv("seek", 0, "absolute")
    end
    mp.osd_message(string.format("Cleared %d saved position%s",
                                 removed, removed == 1 and "" or "s"), 2)
    mp.msg.info(string.format("reset_all removed %d entries from %s", removed, dir))
end

-- bound to a bare key, so a stray press must not silently wipe everything:
-- the first press only arms it, a second within confirm_secs commits
local function reset_all()
    if not opts.confirm then return do_reset() end
    if armed_timer then
        armed_timer:kill(); armed_timer = nil
        return do_reset()
    end
    local n = #entries(wl_dir())
    if n == 0 then
        mp.osd_message("No saved positions to clear", 2)
        return
    end
    mp.osd_message(string.format("Press again to clear %d saved position%s",
                                 n, n == 1 and "" or "s"), opts.confirm_secs)
    armed_timer = mp.add_timeout(opts.confirm_secs, function() armed_timer = nil end)
end

mp.add_key_binding(nil, "reset-all-watch-later", reset_all)
mp.register_event("file-loaded", function()
    if not _G.__wl_expired then _G.__wl_expired = true; expire() end
end)
