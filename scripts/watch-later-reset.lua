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
    confirm_secs = 5,   -- was 3, which was too short to read the prompt in
    max_depth   = 8,    -- how far to walk into a folder playlist entry
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

-- A watch_later file is one of two quite different things: a saved position
-- (`start=NN.NNNNNN`) or a "# redirect entry" pointer. mpv writes a redirect
-- for EVERY ancestor directory of the file, all the way to the root, so one
-- video eight levels down leaves nine files behind. Counting the folder
-- shrinking therefore reported "reset 12 saved positions" for three videos.
-- Only the contents tell the two apart.
local function is_redirect(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(16) or ""
    f:close()
    return head:sub(1, 10) == "# redirect"
end

-- the set of real saved positions, keyed by filename so two snapshots can be
-- diffed to find what a wipe actually removed
local function positions(dir)
    local set, n = {}, 0
    for _, name in ipairs(entries(dir)) do
        if not is_redirect(utils.join_path(dir, name)) then
            set[name] = true
            n = n + 1
        end
    end
    return set, n
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
    local list, seen, files = {}, {}, 0
    local function add(p, is_file)
        if p and p ~= "" and not seen[p] then
            seen[p] = true
            list[#list + 1] = p
            if is_file then files = files + 1 end
        end
    end

    -- mpv expands a folder LAZILY: only the folder it actually plays is turned
    -- into files, so any other folder stays in the playlist as a single
    -- DIRECTORY entry - and so do sub-folders of the one being played. Open two
    -- folders at once (which mpv-open does whenever Finder hands it more than
    -- one file, and which "mpv dirA dirB" does directly) and the videos inside
    -- the second one are not playlist entries at all. Handing mpv only the
    -- entries would leave every one of those videos still resuming, which is
    -- what "0 0 didn't reset anything" looked like from the outside.
    -- Measured 2026-09-03: 6 videos in two folders = 4 playlist entries.
    local function add_tree(dir, depth)
        add(dir, false)
        if depth > opts.max_depth then return end
        for _, name in ipairs(utils.readdir(dir, "files") or {}) do
            -- a non-video file simply has no entry to delete, so there is no
            -- need to duplicate mpv's extension filter here
            add(utils.join_path(dir, name), true)
        end
        for _, name in ipairs(utils.readdir(dir, "dirs") or {}) do
            add_tree(utils.join_path(dir, name), depth + 1)
        end
    end

    local function add_entry(p)
        if not p or p == "" then return end
        local info = utils.file_info(p)
        if info and info.is_dir then
            add_tree(p, 1)
        else
            add(p, true)
        end
    end

    for i, entry in ipairs(pl) do
        add_entry(entry.filename)
        -- The folder or .m3u an entry came from gets its own watch_later file -
        -- a "# redirect entry", which is what makes reopening the folder land
        -- back on the file you left off on. Clearing the 600 videos but not
        -- that pointer would leave the playlist itself still resumed.
        add(entry["playlist-path"], false)
        add(mp.get_property("playlist/" .. (i - 1) .. "/playlist-path"), false)
    end
    add(mp.get_property("playlist-path"), false)
    return list, files
end

-- macOS stores a filename in whichever Unicode normalisation form created it,
-- and APFS is normalisation-INSENSITIVE: the composed spelling ("ö" as a single
-- codepoint) and the decomposed one ("o" + a combining diaeresis) open the very
-- same inode. mpv, though, keys a saved position on an MD5 of the path BYTES,
-- so the two spellings get two separate watch_later entries, and deleting one
-- leaves the other behind - the video carries on resuming. Measured 2026-09-03:
-- seeding under the decomposed spelling and then deleting under the composed one
-- removed all 8 ancestor redirects but left the position itself, and the file
-- still resumed at 43.2s.
--
-- mpv usually hides this, because --autocreate-playlist rebuilds every entry
-- from its own readdir, i.e. from the spelling actually on disk. It does NOT do
-- that when it is handed several files at once - which is precisely what
-- mpv-open does for a Finder multi-select - so a path arriving in the other form
-- (a NAS share, an .m3u, a path typed by hand) stays in that form, and its entry
-- is then unreachable by any later reset.
--
-- So hand mpv both spellings. iconv's UTF-8-MAC is the decomposed form macOS
-- itself uses, which makes it exactly the pair that can collide.
--
-- macOS only. Linux filesystems and NTFS compare names byte for byte (NTFS
-- per UTF-16 unit), so the two spellings there are two different files, not
-- two names for one - and neither glibc's iconv nor Windows has UTF-8-MAC.
local function alt_spellings(paths)
    if mp.get_property("platform") ~= "darwin" then return {} end
    local batch = {}
    for _, p in ipairs(paths) do
        -- an ASCII path has only one spelling, which covers nearly all of them;
        -- a path containing a newline cannot be round-tripped through a
        -- line-delimited pipe, and is not worth a subprocess of its own
        if p:find("[\128-\255]") and not p:find("\n") then
            batch[#batch + 1] = p
        end
    end
    if #batch == 0 then return {} end

    local seen, extra = {}, {}
    for _, p in ipairs(paths) do seen[p] = true end
    -- one spawn per direction for the whole list, rather than one per path: a
    -- 600-file folder of Turkish titles would otherwise mean 1200 of them
    for _, form in ipairs({ { "UTF-8", "UTF-8-MAC" }, { "UTF-8-MAC", "UTF-8" } }) do
        local r = mp.command_native({
            name = "subprocess", playback_only = false, capture_stdout = true,
            -- -c drops an undecodable byte instead of failing the whole batch;
            -- the mangled line is then just a path that hashes to nothing, and
            -- deleting a watch_later entry that was never there is a no-op
            args = { "iconv", "-c", "-f", form[1], "-t", form[2] },
            stdin_data = table.concat(batch, "\n") .. "\n",
        })
        if r and r.status == 0 and r.stdout then
            for line in r.stdout:gmatch("[^\n]+") do
                if not seen[line] then
                    seen[line] = true
                    extra[#extra + 1] = line
                end
            end
        end
    end
    return extra
end

-- 3. delete, and report how many saved positions actually disappeared
--
-- delete-watch-later-config succeeds whether or not the file existed, so the
-- count comes from diffing the folder, not from the command's return value.
local function wipe(paths)
    local dir = wl_dir()
    local before = positions(dir)
    for _, p in ipairs(paths) do
        mp.commandv("delete-watch-later-config", p)
    end
    -- and the same files under their other Unicode spelling (see above)
    for _, p in ipairs(alt_spellings(paths)) do
        mp.commandv("delete-watch-later-config", p)
    end
    local after = positions(dir)
    local removed = 0
    for name in pairs(before) do
        if not after[name] then removed = removed + 1 end
    end

    -- The file on screen is a special case, and getting it wrong is what made
    -- this whole binding look broken. mpv DELETES a file's watch_later entry
    -- the moment it resumes it (v0.41 player/loadfile.c, mp_delete_watch_later_conf
    -- right after the resume is applied), so while a resumed video is playing
    -- there is nothing on disk for it at all: its position lives only in
    -- time-pos. It therefore contributes 0 to `removed`, and the old code gated
    -- the seek on `removed > 0` - so on the common "reopen the folder, press
    -- 0 0" path nothing was seeked, save-position-on-quit wrote the old
    -- position straight back on quit, and the OSD claimed "Nothing saved for
    -- this playlist" while the video carried on resuming. Send it to the start
    -- unconditionally. Measured 2026-09-03.
    local playing = mp.get_property("path")
    if playing then
        mp.commandv("seek", 0, "absolute", "exact")
    end

    mp.msg.info(string.format("removed %d saved position(s) from %s", removed, dir))
    return removed, playing ~= nil
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
    if mp.get_property("path") then
        mp.commandv("seek", 0, "absolute", "exact")
    end
    mp.msg.info(string.format("reset_all removed %d entries from %s", removed, dir))
    return removed
end

-- bound to a bare key, so a stray press must not silently wipe anything:
-- the first press only arms it, a second within confirm_secs commits
local armed, armed_key, expired_at = nil, nil, nil

local function arm(key, prompt, commit)
    if not opts.confirm then return commit() end
    -- `armed` used to be shared by both bindings, so arming one and then
    -- pressing the other committed the wrong wipe. Key the arm to its action.
    if armed and armed_key == key then
        armed:kill(); armed = nil; armed_key = nil
        return commit()
    end
    if armed then armed:kill(); armed = nil end
    -- A press that lands after the window closed used to re-run the same
    -- prompt, so a slow "0, 0" printed identical text twice and was
    -- indistinguishable from a reset that had done nothing at all.
    local late = expired_at ~= nil and (os.time() - expired_at) <= 30
    if not prompt(late) then return end
    armed_key = key
    armed = mp.add_timeout(opts.confirm_secs, function()
        armed = nil; armed_key = nil; expired_at = os.time()
    end)
end

local function plural(n) return n == 1 and "" or "s" end

local function reset_playlist()
    arm("playlist", function(late)
        local _, n = playlist_targets()
        -- n is how many files are in scope, not how many of them have a saved
        -- position: that is only knowable after mpv has done the deleting.
        mp.osd_message(string.format("%sPress 0 again within %ds to reset %d file%s in this playlist",
                                     late and "Too slow - starting over. " or "",
                                     opts.confirm_secs, n, plural(n)),
                       opts.confirm_secs)
        return true
    end, function()
        local paths = playlist_targets()
        local removed, seeked = wipe(paths)
        if removed == 0 then
            mp.osd_message(seeked
                and "Back to the start. Nothing else in this playlist was saved"
                or  "Nothing saved for this playlist", 2)
        else
            mp.osd_message(string.format("Reset %d saved position%s in this playlist%s",
                                         removed, plural(removed),
                                         seeked and ", and this video" or ""), 2)
        end
    end)
end

local function reset_all()
    arm("all", function(late)
        local _, n = positions(wl_dir())
        if n == 0 then
            mp.osd_message("No saved positions to clear", 2)
            return false
        end
        mp.osd_message(string.format("%sPress again within %ds to clear ALL %d saved position%s",
                                     late and "Too slow - starting over. " or "",
                                     opts.confirm_secs, n, plural(n)),
                       opts.confirm_secs)
        return true
    end, function()
        local removed = wipe_all()
        mp.osd_message(string.format("Cleared %d entr%s",
                                     removed, removed == 1 and "y" or "ies"), 2)
    end)
end

mp.add_key_binding(nil, "reset-playlist-watch-later", reset_playlist)
mp.add_key_binding(nil, "reset-all-watch-later", reset_all)
mp.register_event("file-loaded", function()
    if not _G.__wl_expired then _G.__wl_expired = true; expire() end
end)
