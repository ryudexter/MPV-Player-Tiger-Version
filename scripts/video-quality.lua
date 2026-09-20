-- Sharper picture for animation, via the Anime4K shaders.
--
-- WHAT THIS DOES NOT DO: it never touches your video files. Shaders are a live
-- effect - the GPU redraws each frame on its way to the screen, the way a
-- filter on a camera preview works. The file on disk is opened read-only and
-- stays byte-for-byte identical. Switch this off and the picture is instantly
-- back to exactly what it was.
--
-- Auto rule: a file whose path contains one of the names listed in
-- script-opts/video-quality.conf gets the shaders; everything else does not.
-- Live action is left alone ON PURPOSE. mpv's own `high-quality` profile
-- (already on in mpv.conf) is doing the right thing there, and anime shaders
-- on real footage make skin look waxy and add halos around edges.
--
-- The key is bound in input.conf (nothing is baked in here) and cycles:
--     auto  ->  always on  ->  off  ->  auto
-- `auto` is the startup state and is deliberately NOT remembered across runs:
-- close mpv and it is back to auto. Do not "improve" this by persisting it -
-- a sticky `off` that outlives a restart is impossible to diagnose from the
-- picture alone.
--
-- TWO PRESETS. `light` is the default on BOTH power sources as of 2026-09-20
-- (see `ac_chain` below); `full` is opt-in. Superseding an earlier note here
-- that claimed there was nothing to save: that measurement was taken plugged
-- in, on an idle machine. On battery an M3 Max does NOT have the headroom for
-- the full preset. Measured 2026-09-08 on battery, fullscreen 3456x2168, 1080p
-- HEVC - three focus-gated 12 s samples per chain in a single run, chains
-- swapped over the IPC socket, counting frame-drop-count against wall clock:
--   full   Mode A (HQ)                43.9% of frames dropped,   60 fps
--   light  Clamp + x2_M + downscale    0.5% dropped,            119 fps
--   off    no shaders at all            ~0% dropped,            120 fps
-- Per-sample spread was tight - light 0.0/1.4/0.0, full 43.1/42.1/46.4 - so
-- `light` is within noise of running no shaders at all while still doing a real
-- CNN upscale. Built from the six files already vendored; nothing downloaded.
--
-- A third option was measured and REJECTED: Mode A with only the Restore stage
-- removed, keeping the VL upscale, still dropped 11.8% (85 fps). It is the VL
-- *upscale*, not Restore, that this machine cannot afford unplugged - which is
-- the opposite of what the first attempt at this concluded.
--
-- ON AC the full chain measures clean - 0.00% dropped at 120 fps, verified
-- 2026-09-08 the same way, in the rounds whose no-shader baseline was also
-- 0.00%. So the 43% is a battery ceiling, not a general one. But 0.00% is a
-- QUIET machine, and this one routinely is not once it is plugged in: macOS
-- releases the background work it holds back on battery the moment the cable
-- goes in. Measured 2026-09-20 with no player running at all, mediaanalysisd
-- sat at ~60% CPU with the hardware decoder pegged beside it for 41 hours, and
-- the GPU already read 24% utilisation before mpv was even opened.
--
-- That is why `ac_chain` defaults to `light`. On the same machine and file the
-- chains measured off 36% / light 37% / full 76-77% GPU, so `light` is within
-- noise of no shaders at all and `full` costs double either of them. With a
-- quarter of the GPU already gone, `full` is what tips 1080p anime into visible
-- stutter and `light` is not. Set ac_chain=full to have it back.
--
-- One retraction re-examined rather than reversed: the 42.6%-on-AC reading from
-- 2026-09-08 was thrown out because its no-shader baseline was 24%. As a
-- measurement OF THE FULL CHAIN that was right - the number says nothing about
-- the shaders. But the 24% baseline was not a freak round to be discarded; it
-- is this machine's ordinary plugged-in state, which is exactly the case the
-- default now has to survive.
--
-- WARNING, two ways this went wrong before:
--  1. DO NOT re-derive any of this from per-stage `vo-passes` timings. They
--     lie. The same Restore stage measured 9.05 ms in one run and 0.00 ms in
--     another, and one chain's pass-sum drifted 29.45 -> 11.40 ms minutes apart
--     inside a single run: the GPU timer charges the cost to whichever pass
--     absorbs the pipeline stall. An earlier version of this comment blamed
--     Restore for 80.5% of the frame on that basis and chose the light chain
--     accordingly. Use `frame-drop-count` against wall-clock instead.
--  2. Only measure while mpv HAS FOCUS. Unfocused, macOS stops compositing it:
--     playback carries on, but the drop counters freeze and every chain reads a
--     flawless 0.0% - indistinguishable from success.

local msg     = require "mp.msg"
local options = require "mp.options"

local o = {
    -- Semicolon-separated. Matched as plain text anywhere in the file's full
    -- path, ignoring case, so a folder name on its own is enough. Add a show
    -- here when a new animated series joins the library.
    animation_paths = "Solo Leveling;Attack on Titan;One Punch Man;Invincible;Avatar Aang;Anime",

    -- Pick the preset from the power source. On battery that is always the
    -- light chain; on wall power it is whatever `ac_chain` says. Set to no to
    -- ignore the cable and use the wall-power settings everywhere.
    power_aware = true,

    -- Which chain to use on wall power: "light" or "full". See the measurements
    -- at the top of this file - full asks for roughly double the GPU and only
    -- stays clean on a machine with nothing else running, which this one often
    -- is not once it is plugged in.
    ac_chain = "light",

    -- Backstop interval for re-reading the power source, in seconds. It only
    -- fires WHILE PAUSED - see the comment above refresh_power for why a timer
    -- that fires during playback is not free. The refreshes that matter happen
    -- on events instead: a new file, a seek, and pausing.
    power_poll_seconds = 30,

    -- Frame pacing to use on battery, or "" to always keep the one mpv.conf
    -- sets. This is the single biggest saving here, and unlike the shader
    -- presets it applies to EVERY video, not just animation.
    --
    -- mpv.conf sets video-sync=display-resample so playback is locked to the
    -- display clock, which removes a small hitch every ~8 s on 23.976 fps
    -- content. What it costs is that the renderer runs at the DISPLAY's rate
    -- instead of the video's: this panel refreshes 120 times a second for a
    -- film with 24 new frames a second, so four of every five trips through
    -- the scaler and the shaders produce a frame identical to the one already
    -- on screen. video-sync=audio hands the same frames to the same scaler and
    -- the same shaders - the picture is pixel-for-pixel what it was - and only
    -- stops paying for the repeats.
    --
    -- Measured 2026-09-10, 1080p HEVC anime, fullscreen 3456x2168, mpv focused,
    -- no shaders, median GPU "Device Utilization %" over 13 s samples:
    --     video-sync=display-resample    33 / 36 / 36 %
    --     video-sync=audio                        10 %
    --     paused (either mode)                     0 %
    -- For scale, on the same machine and file the shader presets measured
    -- off 36% / light 37% / full 76-77%, so switching the pacing saves rather
    -- more than dropping from the light preset to no shaders at all.
    --
    -- The cost is the hitch coming back: 120 / 23.976 = 5.005, so roughly every
    -- 8 seconds one frame is held for an extra refresh. That is the trade -
    -- smoothness on the cable, endurance off it.
    battery_video_sync = "audio",
}
options.read_options(o, "video-quality")

-- Without this a misspelt value misses `usable[want]` in chain_key and lands on
-- the availability fallback, which picks `full` - the opposite of what anyone
-- typing this option badly is likely to have meant.
if o.ac_chain ~= "full" and o.ac_chain ~= "light" then
    msg.warn("ac_chain must be 'full' or 'light', got '" .. tostring(o.ac_chain)
             .. "' - using light")
    o.ac_chain = "light"
end

-- Anime4K v4.0.1 "Mode A (HQ)", the preset upstream recommends for 1080p anime
-- that is slightly soft: it restores the line art, then upscales it. `light`
-- drops both the Restore stage and the VL upscale, keeping the M upscale, which
-- is the one this machine can afford on battery. The order of these lists
-- matters - each shader feeds the next, and `light` is in the exact order the
-- 0.5% measurement above was taken in.
local CHAINS = {
    full = {
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Restore_CNN_VL.glsl",
        "Anime4K_Upscale_CNN_x2_VL.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
    },
    light = {
        "Anime4K_Clamp_Highlights.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
    },
}

local dir = mp.command_native({"expand-path", "~~/shaders"})

-- If a shader file ever goes missing (a bad checkout, a half-done revert), say
-- so in the log once and stay out of the way, rather than making mpv complain
-- about a missing file on every single video. Checked per chain: losing one
-- preset must not take the other down with it.
local joined, usable = {}, {}
for key, names in pairs(CHAINS) do
    local paths, all = {}, true
    for i, name in ipairs(names) do
        paths[i] = dir .. "/" .. name
        local f = io.open(paths[i], "r")
        if f then f:close() else
            all = false
            msg.warn("shader missing, " .. key .. " preset unavailable: " .. paths[i])
        end
    end
    joined[key] = table.concat(paths, ":")   -- mpv separates this list with ':'
    usable[key] = all
end

local available = usable.full or usable.light

local MODES = { "auto", "on", "off" }
local mode  = "auto"

-- Assumed until pmset answers. AC is the safe assumption: guessing wrong here
-- costs a slightly soft frame or two, and it keeps the old behaviour if the
-- power lookup is ever broken or slow.
local on_ac = true

-- Which chain mpv is currently holding: "full", "light", or "none". Starts
-- "unknown" so the first apply() always writes, and thereafter we only touch
-- glsl-shaders when the answer actually changes - reassigning it recompiles
-- the shaders, which is a visible hitch.
local applied = "unknown"

-- Frame pacing. `ac_sync` is whatever mpv.conf asked for, read once before
-- anything here has had a chance to change it, so returning to the cable
-- restores the user's setting rather than a value hard-coded in this script.
local ac_sync      = mp.get_property("video-sync") or "audio"
local applied_sync = nil

local function is_animation(path)
    if not path then return false end
    local lower = path:lower()
    for name in string.gmatch(o.animation_paths, "([^;]+)") do
        name = name:match("^%s*(.-)%s*$")               -- trim stray spaces
        -- plain=true: these are folder names, not patterns, so a '-' or '('
        -- in a show's name must not be read as pattern syntax
        if name ~= "" and lower:find(name:lower(), 1, true) then return true end
    end
    return false
end

local function wanted()
    if not available or mode == "off" then return false end
    if mode == "on" then return true end
    return is_animation(mp.get_property("path"))
end

local function chain_key()
    local want = (o.power_aware and not on_ac) and "light" or o.ac_chain
    if usable[want] then return want end
    return usable.full and "full" or "light"    -- whichever survived
end

-- Pacing is decided by the cable alone: it is not part of the `y` cycle and
-- has nothing to do with whether this file is animation, because the saving is
-- the same on every video.
local function apply_pacing()
    if o.battery_video_sync == "" then return end
    local want = (o.power_aware and not on_ac) and o.battery_video_sync or ac_sync
    if applied_sync ~= want then
        mp.set_property("video-sync", want)
        applied_sync = want
        msg.info("frame pacing: video-sync=" .. want)
    end
end

local function apply()
    local on = wanted()
    if on then
        local key = chain_key()
        if applied ~= key then
            mp.set_property("glsl-shaders", joined[key])
            applied = key
        end
    elseif applied ~= "none" then
        -- NOT set_property(""): that leaves the list holding one EMPTY path
        -- ([""] rather than []), i.e. mpv still carries a bogus entry around.
        -- 'clr' is the only thing that actually empties the list. Measured.
        mp.commandv("change-list", "glsl-shaders", "clr", "")
        applied = "none"
    end
    return on
end

-- Reports what is actually loaded rather than what the cable says, so a missing
-- light preset can never make this claim the light preset is in use.
local function preset_note()
    if applied == "light" then
        if o.power_aware and not on_ac then return " - light preset, on battery" end
        return " - light preset"
    end
    if applied == "full" then return " - full quality" end
    return ""
end

local function describe(on)
    if not available then return "Sharper picture: shader files are missing" end
    if mode == "auto" then
        return on and ("Sharper picture: on (animation)" .. preset_note())
                   or "Sharper picture: off (not animation)"
    elseif mode == "on" then
        return "Sharper picture: always on" .. preset_note()
    end
    return "Sharper picture: off"
end

-- Polled, not subscribed: macOS raises no power-source event mpv can listen
-- for, so the only way to know is to run `pmset -g ps`.
--
-- 🔴 THAT FORK IS NOT FREE WHILE AUDIO IS PLAYING, and this used to run on a
-- flat 30-second timer. macOS logged the result plainly:
--     mpv  HALC_ProxyIOContext::IOWorkLoop: skipping cycle due to overload
-- - a skipped audio I/O cycle, which is a short gap in the sound, i.e. an
-- audible thump. 59 of them in one 75-minute sitting on 2026-09-10, and 31 of
-- the 33 gaps between them were an exact multiple of 30 seconds (±0.1 s) with
-- the sub-second phase drifting smoothly across the whole session - one
-- periodic timer, not scattered load. mpv's own logs show nothing: at the ao
-- layer there is no underrun, because mpv fed the buffer in time; it is the
-- CoreAudio render callback that misses its deadline while the process forks.
--
-- It only ever bit ANIMATION, which is what made it so hard to place from the
-- symptom: the timer was gated on wanted(), so it only ran while the shaders
-- were in use. "A thump, but only on anime" was this.
--
-- It does not fire on every tick - only when the machine is already busy - so
-- it comes and goes, and it is likelier in a scene that is working the GPU.
--
-- The fix is to stop forking underneath live audio. Refreshes now happen where
-- the audio is already stopped or being flushed, so a skipped cycle has
-- nothing to skip: a new file, a seek, and pausing. The timer survives only as
-- a backstop while paused. Debounced through poll_power so that scrubbing,
-- which fires `seek` repeatedly, cannot turn back into a fork per second.
--
-- playback_only=false so it still answers while paused - which is now the case
-- that matters most. quiet=true suppresses the OSD for checks the user did not
-- ask for (script load, file load).
local function refresh_power(quiet)
    if not o.power_aware then return end
    mp.command_native_async({
        name          = "subprocess",
        args          = { "/usr/bin/pmset", "-g", "ps" },
        capture_stdout = true,
        playback_only = false,
    }, function(ok, res)
        if not ok or not res or res.status ~= 0 or not res.stdout then
            msg.warn("could not read the power source, keeping the full preset")
            return
        end
        -- "Now drawing from 'AC Power'" / "Now drawing from 'Battery Power'"
        local ac = res.stdout:find("AC Power", 1, true) ~= nil
        if ac == on_ac then return end          -- nothing moved
        on_ac = ac
        msg.info(ac and "on AC, full preset" or "on battery, light preset")
        local before = applied
        apply_pacing()
        local on = apply()
        -- The picture visibly changes here without the user having touched a
        -- key, so say why: an unexplained softer frame mid-episode reads as a bug.
        if on and applied ~= before and not quiet then
            mp.osd_message(describe(on), 2)
        end
    end)
end

-- Every refresh goes through here, so one debounce covers all of them. `gap`
-- is the shortest time allowed since the last check: scrubbing fires `seek`
-- many times a second, and each one would otherwise be a fork.
local last_poll = -1e9
local function poll_power(quiet, gap)
    if not o.power_aware then return end
    local now = mp.get_time()
    if gap and (now - last_poll) < gap then return end
    last_poll = now
    refresh_power(quiet)
end

local function cycle()
    local i = 1
    for n, m in ipairs(MODES) do if m == mode then i = n end end
    mode = MODES[(i % #MODES) + 1]
    mp.osd_message(describe(apply()), 2)
    msg.info("mode " .. mode)
    poll_power(true)      -- correct the preset silently; the line above already spoke
end

-- Silent on load, deliberately: mpv says nothing when it picks a video track
-- either, and an OSD line on every single file would be noise. Only the key talks.
mp.register_event("file-loaded", function()
    apply_pacing()
    apply()
    poll_power(true)          -- no gap: a new file is always worth one check
end)

-- Pausing stops the audio outright, so this is the one moment a fork is
-- certainly free - and it is also when someone who has just reached for the
-- charger is most likely to be sitting in front of it.
mp.observe_property("pause", "bool", function(_, paused)
    if paused then poll_power(false, 3) end
end)

-- A seek flushes and refills the audio buffer anyway, so a fork inside that
-- window has nothing to interrupt.
mp.register_event("seek", function() poll_power(false, 15) end)

-- Backstop only, and only while paused: a timer that fires during playback is
-- exactly the bug described above. This is what notices when the machine sat
-- paused for an hour and the charger came out in the meantime.
if o.power_aware and o.power_poll_seconds > 0 then
    mp.add_periodic_timer(o.power_poll_seconds, function()
        if mp.get_property_bool("pause") then poll_power(false, 3) end
    end)
end

poll_power(true)

mp.add_key_binding(nil, "cycle-video-quality", cycle)
