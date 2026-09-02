-- Download subtitles for the playing file from the internet, bound to b.
--
-- This is the mpv answer to VLC's VLsub extension. mpv has no extension menu,
-- so the work is done by `subliminal`, a Python CLI that searches several
-- subtitle sites at once and picks the best match for THIS release - it hashes
-- the video file, so it can find the exact rip rather than guessing from the
-- title. Installed with `pipx install subliminal` (2.7.1 on 2026-09-02).
--
-- ANONYMOUS PROVIDERS ONLY. subliminal can also query opensubtitles.com, but
-- that needs an account and an API key, so those two providers are left out
-- and nothing here has a login. What is left, measured 2026-09-02:
--   bsplayer    - movies AND episodes, matched by file hash. The workhorse.
--   gestdown    - episodes only (an addic7ed mirror); skips movies by itself.
--   tvsubtitles - episodes only, same.
--   podnapisi   - listed, but www.podnapisi.net currently has NO DNS record at
--                 all, so every search fails instantly. Kept in the list on
--                 purpose: it costs one NXDOMAIN and starts working again by
--                 itself if the site ever comes back.
-- subliminal skips a provider that cannot serve the kind of video being played
-- ("not a valid video"), so passing all four is how one key covers both.
--
-- Downloads land NEXT TO the video as "<name>.en.srt". That name is chosen by
-- subliminal and it is exactly what the rest of this config wants: mpv reads
-- the .en as a language tag, and scripts/subtitle-pick.lua then scores it 140
-- (100 for English + 40 for matching the video's stem), which beats any
-- "English.srt" already sitting in a Subs/ folder for another episode.
--
-- b downloads and switches subtitles on in one press. Shift+b forces a
-- re-download over a subtitle file that is already there.

local utils = require "mp.utils"

local HOME = os.getenv("HOME") or ""

-- Pinned absolute path, NOT bare "subliminal". A Finder-launched app does not
-- inherit the shell PATH, so under mpv.app a bare name fails silently - the
-- same trap that made thumbfast's helper a no-op until mpv_path was pinned.
-- The pipx shim's own shebang is absolute, so nothing else needs PATH either.
local SUBLIMINAL = HOME .. "/.local/bin/subliminal"

local LANGS     = { "en" }
local PROVIDERS = { "bsplayer", "gestdown", "podnapisi", "tvsubtitles" }

-- Used only when the video's own folder is read-only (a mounted disk image, a
-- share). mpv would not auto-discover a subtitle here, so those get sub-added
-- by absolute path instead.
local FALLBACK_DIR = HOME .. "/.config/mpv/subs-fetched"

-- Generous on purpose. A movie comes back from bsplayer in ~4s, but an episode
-- goes to gestdown and tvsubtitles as well, and that measured 57s on House of
-- the Dragon S03E06 - a first draft of this script had TIMEOUT=60 and came
-- within 3s of killing a search that was working perfectly.
local TIMEOUT = 180

local busy, handle, ticker, started = false, nil, nil, 0

local function osd(text, dur) mp.osd_message(text, dur or 2.5) end

-- mpv keeps `path` exactly as the playlist entry gave it, which can be
-- relative; subliminal is run with no working directory of our choosing.
local function abs_path()
    local path = mp.get_property("path")
    if not path then return nil, "Nothing playing" end
    if path:match("^%a[%w+.-]*://") then return nil, "Not a local file" end
    if not path:match("^/") then
        local wd = mp.get_property("working-directory")
        if wd then path = wd .. "/" .. path end
    end
    return path
end

local function dir_of(path) return (path:gsub("/[^/]*$", "")) end

-- Asked directly, because there is no portable way to read permission bits
-- through mp.utils.file_info - and the answer decides where the file goes.
local function writable(dir)
    local probe = dir .. "/.mpv-subtitle-write-test"
    local f = io.open(probe, "w")
    if not f then return false end
    f:close()
    os.remove(probe)
    return true
end

local function srt_set(dir)
    local names, set = utils.readdir(dir, "files") or {}, {}
    for _, n in ipairs(names) do
        if n:match("%.srt$") or n:match("%.ass$") or n:match("%.sub$") then
            set[n] = true
        end
    end
    return set
end

local function stop_ticker()
    if ticker then ticker:kill(); ticker = nil end
end

-- Everything below runs when subliminal has exited.

local function apply_beside_video(ctx)
    -- keep-selection so re-scanning cannot pull the audio or video track out
    -- from under playback; the sub track is chosen deliberately just below.
    mp.commandv("rescan-external-files", "keep-selection")

    -- Select the file that was just downloaded, in preference to letting
    -- subtitle-pick.lua score the whole list again.
    --
    -- This is not a detail. House of the Dragon S03E06 carries 36 embedded
    -- subtitle tracks, two of them en-US, and the picker rates an embedded
    -- English track (150) above a downloaded one (140) - correctly, in general.
    -- But it means b spent 57s fetching a subtitle and then showed a different
    -- one, which makes the key look broken. Pressing b says "use a subtitle
    -- from the internet"; c is still there for switching to anything else.
    --
    -- subliminal names its output "<video stem>.<lang>.<ext>", and the
    -- extension is whatever the site served, so match on the prefix. Compared
    -- by basename because a rescanned track's external-filename may be either
    -- absolute or relative.
    local want = ctx.stem .. "." .. LANGS[1] .. "."
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        local fn = t.type == "sub" and t["external-filename"]
        if fn then
            local base = fn:gsub(".*/", "")
            if base:sub(1, #want) == want then
                mp.set_property_number("sid", t.id)
                mp.set_property_bool("sub-visibility", true)
                mp.osd_message("Subtitles: " .. base)
                return
            end
        end
    end

    -- The name was not what was expected; the picker is a safe fallback since
    -- the new file is in the track list either way.
    mp.commandv("script-message", "subs-pick-best")
end

local function apply_from_fallback(before)
    local added
    for name in pairs(srt_set(FALLBACK_DIR)) do
        if not before[name] then
            -- The language is passed explicitly: a sub-added file gets no
            -- language at all unless it is given one (measured - the same
            -- subtitle auto-loaded from beside the video reports lang=en,
            -- sub-added it reports none), and subtitle-pick.lua scores the
            -- language tag. Empty title so it still labels by filename.
            mp.commandv("sub-add", FALLBACK_DIR .. "/" .. name,
                        added and "auto" or "select", "", LANGS[1])
            added = added or name
        end
    end
    if added then
        mp.set_property_bool("sub-visibility", true)
        osd("Subtitles: " .. added)
    else
        osd("Downloaded, but the file could not be found")
    end
end

local function finished(ok, res, err, ctx)
    stop_ticker()
    busy, handle = false, nil

    local out   = (res and res.stdout) or ""
    local count = tonumber(out:match("Downloaded (%d+) subtitle"))
    local dead  = out:match("discarded due to unexpected errors: ([^\n]+)")
    if res then mp.msg.verbose("subliminal: " .. out:gsub("%s+$", "")) end

    -- The report on stdout is read BEFORE the exit code, and the exit code is
    -- then only consulted for a run that printed no report at all.
    --
    -- Measured 2026-09-02: subliminal exits 0 even when a provider times out
    -- and is discarded, so the status is not the interesting signal - the
    -- interesting signal is that it can lose one provider and still deliver a
    -- subtitle from another. Reading the report first means that case ends with
    -- the subtitle applied rather than an error message.
    if not ok or (count == nil and not dead) then
        osd("Subtitle search failed - see the log", 3)
        mp.msg.error("subliminal failed (status " ..
            tostring(res and res.status) .. "): " ..
            tostring(err or (res and res.stderr) or "unknown"))
        return
    end
    count = count or 0

    -- The file can have changed while the search was running: b is manual, but
    -- a video can end and the playlist move on. Selecting a track for a file
    -- that is no longer on screen would be worse than saying nothing.
    if mp.get_property("path") and abs_path() ~= ctx.path then
        if count > 0 then osd("Subtitles downloaded for the previous file") end
        return
    end

    if count == 0 then
        -- Nothing new online. If the file DOES have subtitles already - an
        -- embedded track, or the .srt that made subliminal skip the download -
        -- then turning those on is still what pressing b was asking for, so
        -- hand over to the picker rather than reporting a dead end. Its own OSD
        -- names the track it chose, which is the honest answer either way.
        local have = 0
        for _, t in ipairs(mp.get_property_native("track-list") or {}) do
            if t.type == "sub" then have = have + 1 end
        end
        if have > 0 then
            mp.commandv("script-message", "subs-pick-best")
            return
        end

        -- "nothing exists for this film" and "the site fell over" are very
        -- different answers and it is worth saying which. subliminal reports
        -- the second on its own last line, and it does happen: bsplayer is the
        -- only anonymous source that serves MOVIES, and it dropped out after a
        -- run of requests during testing - 57s, then "discarded due to
        -- unexpected errors: bsplayer" and no subtitle.
        local dead = out:match("discarded due to unexpected errors: ([^\n]+)")
        if dead then
            osd("Subtitle site unavailable (" .. dead .. ") - try again", 4)
        elseif ctx.force then
            osd("No subtitles found for this file", 3)
        else
            osd("No subtitles found  (Shift+b re-downloads)", 3)
        end
        return
    end

    if ctx.dir then apply_from_fallback(ctx.before) else apply_beside_video(ctx) end
end

local function fetch(force)
    if busy then osd("Already looking for subtitles"); return end

    local path, why = abs_path()
    if not path then osd(why); return end

    if not utils.file_info(SUBLIMINAL) then
        osd("subliminal is not installed", 3)
        mp.msg.error("expected the subliminal CLI at " .. SUBLIMINAL)
        return
    end

    local args = { SUBLIMINAL, "download" }
    for _, l in ipairs(LANGS)     do args[#args + 1] = "-l"; args[#args + 1] = l end
    for _, p in ipairs(PROVIDERS) do args[#args + 1] = "-p"; args[#args + 1] = p end

    if force then
        -- overwrite whatever is already on disk
        args[#args + 1] = "-f"
    else
        -- Without this, an embedded track counts as "already has subtitles" and
        -- b would do nothing at all on a file whose built-in subs are the very
        -- reason you pressed it. An external .srt is still left alone - that is
        -- what Shift+b is for.
        args[#args + 1] = "--force-embedded-subtitles"
    end

    local ctx = {
        path  = path,
        force = force,
        stem  = (path:gsub(".*/", ""):gsub("%.[^.]*$", "")),
    }
    local dir = dir_of(path)
    if not writable(dir) then
        os.execute("mkdir -p " .. string.format("%q", FALLBACK_DIR))
        ctx.dir    = FALLBACK_DIR
        ctx.before = srt_set(FALLBACK_DIR)
        args[#args + 1] = "-d"; args[#args + 1] = FALLBACK_DIR
    end
    args[#args + 1] = path

    busy, started = true, mp.get_time()
    osd("Looking for subtitles...", 1.4)
    ticker = mp.add_periodic_timer(1, function()
        local secs = math.floor(mp.get_time() - started)
        if secs >= TIMEOUT then
            if handle then mp.abort_async_command(handle) end
            stop_ticker()
            busy, handle = false, nil
            osd("Subtitle search timed out", 3)
            return
        end
        osd(string.format("Looking for subtitles... %ds", secs), 1.4)
    end)

    handle = mp.command_native_async({
        name           = "subprocess",
        args           = args,
        playback_only  = false,   -- a search must survive the end of a file
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res, err) finished(ok, res, err, ctx) end)
end

mp.add_key_binding(nil, "subs-fetch",       function() fetch(false) end)
mp.add_key_binding(nil, "subs-fetch-force", function() fetch(true)  end)
