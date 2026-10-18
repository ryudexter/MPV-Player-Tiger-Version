-- Re-time the playing subtitle against the film's own audio, bound to Alt+b.
--
-- A downloaded subtitle is often right but late, because it was timed for a
-- different cut or a different frame rate. Shift+c and Shift+x nudge it by
-- 100ms a press, which is fine for half a second and hopeless for twelve.
--
-- `ffsubsync` fixes it properly: it runs the film's audio through voice
-- detection, does the same to the subtitle's own timings, and slides one
-- against the other until they line up, correcting the frame rate too.
-- Installed with `pipx install ffsubsync` (0.5.1 on 2026-09-02).
--
-- Measured on Margin Call, a 2h02 film: a subtitle deliberately pushed 12s
-- late came back as "offset seconds: -12.040", and its first cue landed within
-- 40ms of where it had started. That 40ms is the method's own accuracy, not a
-- mistake - it aligns speech, not the original file.
--
-- HOW LONG IT TAKES IS UNRESOLVED. The same command on the same film took 12s
-- run from a shell and 242s when mpv spawned it - a 20x gap I could not
-- explain. Ruled out, each by measurement: CPU contention with playback (an
-- IDLE mpv with no file loaded was slower still), pipe backpressure (ffsubsync
-- prints 6KB in total), and the macOS background QoS class (wrapping the call
-- in `taskpolicy -B` changed nothing). Two of those three measurements are
-- themselves suspect, because they used mpv's SYNCHRONOUS subprocess over the
-- JSON IPC rather than the async path this script uses. Worth knowing that the
-- other async subprocesses here - subliminal, `open -R` - are NOT slowed at
-- all, so this looks specific to ffsubsync. Hence the very generous timeout.
--
-- Alt+b, because b downloads the subtitle and Alt is this config's "same key,
-- advanced version" modifier - as Alt+c is to c.

local utils = require "mp.utils"

local PLATFORM = mp.get_property("platform")   -- "darwin", "windows", "linux", ...
local HOME = (PLATFORM == "windows" and os.getenv("USERPROFILE") or os.getenv("HOME")) or ""

-- Absolute, for the reason given in subtitle-fetch.lua: a Finder-launched app
-- inherits no shell PATH, and a bare name would fail silently under mpv.app.
-- Off the Mac, the same pipx location first and then PATH, as there.
-- ffsubsync runs ffmpeg by name, so on Windows and Linux ffmpeg itself has to
-- be on PATH (both installers see to it).
local FFSUBSYNC = HOME .. "/.local/bin/ffsubsync" .. (PLATFORM == "windows" and ".exe" or "")
if PLATFORM ~= "darwin" and not utils.file_info(FFSUBSYNC) then FFSUBSYNC = "ffsubsync" end

-- Deliberately far past the 242s measured above, because the cause of that
-- slowness is not understood and a longer film could well be worse. The ticker
-- counts up on screen throughout, so a slow run looks slow rather than broken.
local TIMEOUT = 900

local busy, handle, ticker, started = false, nil, nil, 0

local function osd(text, dur) mp.osd_message(text, dur or 2.5) end

-- join_path leaves an absolute path alone, Windows ones (C:\) included.
local function absolute(path)
    local wd = mp.get_property("working-directory")
    if path and wd then return utils.join_path(wd, path) end
    return path
end

-- The subtitle to work on: the SELECTED track, and only if it is an external
-- file. An embedded track is not a file that can be rewritten - it would have
-- to be demuxed out first, which is a different feature.
local function current_sub()
    local id = mp.get_property_number("current-tracks/sub/id")
    if not id then return nil, "No subtitles on - press c or b first" end
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "sub" and t.id == id then
            local fn = t["external-filename"]
            if not fn then
                return nil, "Only for downloaded subtitles, not built-in ones"
            end
            return absolute(fn)
        end
    end
    return nil, "Could not find the selected subtitle"
end

local function stop_ticker()
    if ticker then ticker:kill(); ticker = nil end
end

local function finished(ok, res, err, ctx)
    stop_ticker()
    busy, handle = false, nil

    -- ffsubsync logs its report to stderr, including the two numbers worth
    -- reading back: "offset seconds: -12.040" and "score: 234968.000".
    if res and res.error_string == "init" then
        osd("ffsubsync is not installed", 3)
        mp.msg.error("could not run " .. FFSUBSYNC)
        return
    end

    local out    = ((res and res.stderr) or "") .. ((res and res.stdout) or "")
    local offset = tonumber(out:match("offset seconds:%s*(-?[%d.]+)"))

    if not ok or not res or res.status ~= 0 or not offset then
        osd("Could not re-sync this subtitle", 3)
        mp.msg.error("ffsubsync failed (status " .. tostring(res and res.status)
            .. "): " .. tostring(err or out))
        os.remove(ctx.tmp)
        return
    end

    -- Written to a temporary file and moved into place only now, so a failed
    -- or interrupted run cannot leave a half-written subtitle behind.
    local f = io.open(ctx.tmp, "r")
    local size = f and f:seek("end") or 0
    if f then f:close() end
    if size == 0 then
        osd("Re-sync produced an empty subtitle - left alone", 3)
        os.remove(ctx.tmp)
        return
    end

    -- The ORIGINAL is kept once, on the first sync only, so that syncing twice
    -- can never overwrite the backup with an already-synced copy. ".srt.orig"
    -- is not a subtitle extension, so sub-auto=all ignores it and it never
    -- appears as a second track.
    if not utils.file_info(ctx.sub .. ".orig") then
        os.rename(ctx.sub, ctx.sub .. ".orig")
    end
    -- Windows will not rename onto a file that exists, which on the second
    -- sync it does (the backup above is only taken once). The original is safe
    -- in .orig by now either way.
    if PLATFORM == "windows" then os.remove(ctx.sub) end
    os.rename(ctx.tmp, ctx.sub)

    if mp.get_property("path") and absolute(mp.get_property("path")) ~= ctx.path then
        osd(string.format("Re-synced the previous file by %.1fs", offset), 3)
        return
    end

    -- sub-reload re-reads the selected external file in place: no new track, no
    -- change of sid, and the position on screen is untouched.
    mp.commandv("sub-reload")

    -- Any manual nudge is now wrong twice over - it was compensating for the
    -- very offset that has just been corrected in the file itself.
    local delay = mp.get_property_number("sub-delay") or 0
    if math.abs(delay) > 0.001 then
        mp.set_property_number("sub-delay", 0)
        osd(string.format("Subtitles re-synced by %.1fs  (timing nudge reset)",
            offset), 3)
    else
        osd(string.format("Subtitles re-synced by %.1fs", offset), 3)
    end
end

local function sync()
    if busy then osd("Already re-syncing"); return end

    local path = mp.get_property("path")
    if not path then osd("Nothing playing"); return end
    if path:match("^%a[%w+.-]*://") then osd("Not a local file"); return end
    path = absolute(path)

    local sub, why = current_sub()
    if not sub then osd(why, 3); return end

    if FFSUBSYNC ~= "ffsubsync" and not utils.file_info(FFSUBSYNC) then
        osd("ffsubsync is not installed", 3)
        mp.msg.error("expected the ffsubsync CLI at " .. FFSUBSYNC)
        return
    end

    local ctx = { path = path, sub = sub, tmp = sub .. ".resync.tmp.srt" }

    busy, started = true, mp.get_time()
    osd("Re-syncing subtitles...", 1.4)
    ticker = mp.add_periodic_timer(1, function()
        local secs = math.floor(mp.get_time() - started)
        if secs >= TIMEOUT then
            if handle then mp.abort_async_command(handle) end
            stop_ticker()
            busy, handle = false, nil
            os.remove(ctx.tmp)
            osd("Re-sync timed out", 3)
            return
        end
        osd(string.format("Re-syncing subtitles... %ds", secs), 1.4)
    end)

    handle = mp.command_native_async({
        name           = "subprocess",
        args           = { FFSUBSYNC, path, "-i", sub, "-o", ctx.tmp },
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
    }, function(ok, res, err) finished(ok, res, err, ctx) end)
end

mp.add_key_binding(nil, "subs-sync", sync)
