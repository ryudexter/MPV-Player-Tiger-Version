-- Move the playing file to the Trash, bound to Cmd+Delete.
--
-- Playback is deliberately left completely alone: the video keeps playing from
-- the same spot, at the same volume, and mpv never quits as a result of this.
-- Trashing an open file on macOS only unlinks it from its folder, so mpv's
-- already-open handle keeps reading it happily to the end.
--
-- The playlist entry still points at a path that no longer exists, so it is
-- reaped later - once playback has moved off it of its own accord. Removing it
-- straight away is what would disturb things: dropping the CURRENT entry makes
-- mpv start the next file immediately, and on the last entry it ends playback
-- (with keep-open=no that means mpv quits).
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
--
-- A successful trash plays a short, low "poof", so the press is
-- confirmed without looking at the screen. Asked for 2026-10-05. It plays
-- only once the file is really in the Trash - a failure stays silent and says
-- so on screen - and through afplay rather than mpv, so it is heard even with
-- mpv muted. Set sound= (empty) in script-opts/trash_file.conf to switch it
-- off, or point it at any other sound file.
--
-- It started as Finder's own "move to trash", which turned out too long
-- (2.2 s, three crumples) and too loud (-0.6 dB peak). On 2026-10-10 the user
-- auditioned four shorter, lower replacements and picked the Dock's "poof"
-- slowed ~5 semitones and about half as loud: sounds/trash-poof.wav, 0.47 s.
-- sounds/make-trash-sounds.sh builds it and the three paper crumples that
-- lost - trash-crumple, trash-crumple-lower, trash-crumple-fuller.
--
-- Windows and Linux (Ctrl+Delete there, see input.conf):
--   Windows  the Recycle Bin, through `mpv-open.exe --trash` (the launcher
--            install.ps1 builds), so Explorer's "Restore" puts it back. It asks
--            Windows to WARN before deleting anything outright: a file on a
--            drive with no Recycle Bin (a network share, some USB sticks) or one
--            too big for it would otherwise be erased with no prompt at all,
--            which is what the usual one-liners (VB's DeleteFile, PowerShell)
--            quietly do. mpv opens files with FILE_SHARE_DELETE, so the file
--            can be moved while it plays and playback carries on, as on a Mac.
--   Linux    the freedesktop Trash, through `gio trash` (GLib, on nearly every
--            desktop), else `trash-put` (trash-cli), else KDE's kioclient. All
--            three keep the restore information the file manager needs, and
--            none of them falls back to deleting when a mount has no trash.
-- afplay is macOS-only, so there the sound is played by a second, throwaway
-- mpv with no config: still a separate process, so muting this one does not
-- silence it, and sound_volume still applies.

local options = require 'mp.options'
local utils   = require 'mp.utils'

local PLATFORM = mp.get_property("platform")   -- "darwin", "windows", "linux", ...
-- what the bin is called on this system, for the messages
local BIN      = PLATFORM == "windows" and "the Recycle Bin" or "the Trash"
local MOVED_TO = PLATFORM == "windows" and "Moved to the Recycle Bin: " or "Moved to Trash: "

local opts = {
    confirm = false,      -- yes = require a second press within confirm_secs
    confirm_secs = 3,
    -- played on success; empty = no sound. ~~/ is the mpv config folder.
    sound = "~~/sounds/trash-poof.wav",
    sound_volume = 1,     -- afplay -v (mpv --volume elsewhere): 1 = the file's own level
}
options.read_options(opts, "trash_file")

-- entry id -> path, for files already trashed whose playlist entry is still
-- standing because we are still watching it
local pending = {}
local reaping = false

-- mpv keeps `path` exactly as the playlist entry gave it, which can be
-- relative; the Trash API needs an absolute one. join_path leaves an absolute
-- path alone, and knows a Windows one (C:\, \\server\) when it sees it.
local function abs(path)
    local wd = mp.get_property("working-directory")
    return wd and utils.join_path(wd, path) or path
end

-- Entry ids are stable for the life of the playlist, indices are not - they
-- shift as entries come and go, and playlist-remove only takes an index. So
-- remember the id and look its index up again whenever it is needed.
local function index_of_id(id)
    local pl = mp.get_property_native("playlist") or {}
    for i, entry in ipairs(pl) do
        if entry.id == id then return i - 1 end
    end
    return nil
end

local function current_id()
    local pos = mp.get_property_number("playlist-pos")
    local pl  = mp.get_property_native("playlist") or {}
    return pos and pl[pos + 1] and pl[pos + 1].id
end

-- Drop the playlist entries of trashed files, but only ones we are no longer
-- sitting on. Removing an entry that is not the current one does not touch
-- playback: if it sat earlier in the list mpv just renumbers, and playlist-pos
-- follows the file that is playing.
local function reap()
    if reaping then return end       -- our own playlist-remove re-triggers this
    reaping = true
    local cur = current_id()
    for id, path in pairs(pending) do
        if id ~= cur then
            local i = index_of_id(id)
            if i then mp.commandv("playlist-remove", i) end
            -- again here because stepping away with x writes a position first
            mp.commandv("delete-watch-later-config", path)
            pending[id] = nil
            mp.msg.verbose("reaped playlist entry for " .. path)
        end
    end
    reaping = false
end

-- A trashed entry that happens to sit LAST in the playlist strands you: the
-- video plays on, but "next" has nowhere to go, so you are stuck on a file
-- that is already in the Trash. (A 2-video folder hits this constantly - open
-- the second one and it is already the last entry.)
--
-- The entry is on its way out anyway, so its position carries no meaning:
-- slide it one slot earlier and "next" lands on the nearest surviving video
-- instead of nothing. Reordering a playlist does not disturb playback, and
-- moving it only one slot - rather than to the front - keeps the destination
-- adjacent, which at the end of a folder is the only sensible direction left.
--
-- Returns true when nothing could be done because the dead entry is all that
-- is left, so the caller can say so instead of leaving you guessing.
local function shuffle_out_of_last_place(id)
    local i     = index_of_id(id)
    local count = mp.get_property_number("playlist-count") or 0
    if not i or count < 2 then return count < 2 end
    if i == count - 1 then
        -- playlist-move inserts the entry BEFORE the second index
        mp.commandv("playlist-move", i, i - 1)
        mp.msg.verbose("moved the trashed entry off the end of the playlist")
    end
    return false
end

-- Async for the same reason as the trash itself, and fire-and-forget: a
-- missing or unplayable sound file must never turn a successful trash into an
-- error, so afplay's result is not looked at.
local function play_sound()
    if opts.sound == "" then return end
    local file = mp.command_native({ "expand-path", opts.sound })
    local args = { "/usr/bin/afplay", "-v", tostring(opts.sound_volume), file }
    if PLATFORM ~= "darwin" then
        -- bare "mpv": on Windows a child is looked for beside mpv.exe first, so
        -- this is the same mpv; on Linux it is the one on PATH
        args = { "mpv", "--no-config", "--no-terminal", "--no-video",
                 "--force-window=no", "--volume=" .. tostring(opts.sound_volume * 100),
                 "--", file }
    end
    mp.command_native_async({
        name          = "subprocess",
        args          = args,
        playback_only = false,
    }, function() end)
end

-- Run the first of `candidates` that exists on this machine. A candidate that
-- cannot be started at all (error "init": not installed) passes to the next;
-- any other outcome, success or failure, is that tool's answer and is final.
local function run_first(candidates, done, i)
    i = i or 1
    if not candidates[i] then
        return done(false, nil, "none of the trash tools is installed")
    end
    mp.command_native_async({
        name           = "subprocess",
        args           = candidates[i],
        playback_only  = false,          -- must survive the end of a file
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res, err)
        if ok and res and res.error_string == "init" then
            return run_first(candidates, done, i + 1)
        end
        done(ok, res, err)
    end)
end

-- What moves `path` to the bin here, best first.
local function trash_commands(path)
    if PLATFORM == "darwin" then
        return { { "/usr/bin/trash", "-v", path } }
    elseif PLATFORM == "windows" then
        return { { mp.command_native({ "expand-path", "~~/mpv-open.exe" }),
                   "--trash", (path:gsub("/", "\\")) } }
    end
    return {
        { "gio", "trash", path },
        { "trash-put", path },
        { "kioclient6", "move", path, "trash:/" },
        { "kioclient5", "move", path, "trash:/" },
    }
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
    local id   = current_id()

    -- pressing it twice on the same file would otherwise report a failure,
    -- since the second trash cannot find the file any more
    if id and pending[id] then
        mp.osd_message("Already in " .. BIN .. ": " .. name, 2)
        return
    end

    run_first(trash_commands(path), function(ok, res, err)
        if not (ok and res and res.status == 0) then
            -- trash exits 5 when the file is already gone; mpv-open.exe exits
            -- 2 when Windows asked to delete outright and the answer was no
            if PLATFORM == "windows" and res and res.status == 2 then
                mp.osd_message("Kept: not moved to " .. BIN, 2)
                return
            end
            mp.osd_message("Could not trash this file", 2)
            mp.msg.error("trash failed: " ..
                tostring(err or (res and (res.stderr ~= "" and res.stderr or res.error_string))
                         or "unknown"))
            return
        end

        mp.msg.info("trashed " .. path)
        play_sound()
        mp.commandv("delete-watch-later-config", path)

        local stranded = false
        if id and index_of_id(id) then
            -- still in the playlist: leave it, and the file playing, alone
            pending[id] = path
            stranded = shuffle_out_of_last_place(id)
            reap()                       -- in case we have since moved off it
        end
        mp.osd_message(MOVED_TO .. name ..
            (stranded and "  (nothing else in this playlist)" or ""), 2)
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

-- both, because leaving a file and arriving at the next one are not the same
-- moment: end-file fires even when nothing follows it in the playlist
mp.observe_property("playlist-pos", "number", function() reap() end)
mp.register_event("end-file", function() reap() end)
