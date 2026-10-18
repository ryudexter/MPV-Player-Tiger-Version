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
-- THE OSD RULE (the user's decision, 2026-09-21). The ONLY thing in this script
-- that may put a message on screen is a press of the key above. Not a
-- load-driven rung change, not plugging in, not unplugging, not startup, not a
-- new file. There is exactly ONE mp.osd_message call in this file and it lives
-- in cycle(); if you find yourself adding a second, that is this rule being
-- broken rather than a bug being fixed.
--
-- This deliberately REVERSES the principle the rest of this file was built on -
-- that a picture which changes by itself should say why, or it reads as a
-- fault. The user was told that is exactly what they are giving up and asked
-- for silence regardless: they would rather never see the line than be
-- informed of a change they did not ask for. It is a preference about their own
-- media player, not an oversight to correct.
--
-- Nothing is lost for diagnosis: every chain change and every power change
-- still goes to the log through msg.info, so `--log-file=<path>` (or
-- log-file= in mpv.conf) recovers the entire history after the fact.
--
-- THREE RUNGS - full, light, off - and what runs is whichever one the machine
-- has most recently shown it can afford. `ac_max_chain` and `battery_chain` are
-- the ends of that ladder; the load sampler further down does the moving.
-- Superseding an earlier note here that claimed there was nothing to save: that
-- measurement was taken plugged in, AND on an idle machine. Both halves of that
-- mattered. On battery an M3 Max does NOT have the headroom for
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
-- That is what the ladder is for. On the same machine and file the chains
-- measured off 36% / light 37% / full 76-77% GPU, so `light` is within noise of
-- no shaders at all while `full` costs double either of them. With a quarter of
-- the GPU already gone before mpv opens, `full` is what tips 1080p anime into
-- visible stutter and `light` is not - but on a genuinely idle machine `full`
-- is free and worth having. Neither is right all the time, which is why this no
-- longer picks one and lives with it: it measures, and moves.
--
-- ON BATTERY the default is now OFF rather than the light chain. The light
-- chain is nearly free in dropped frames but it is not free in watt-hours, and
-- it is GPU spent on a picture nobody asked for. `y` -> "always on" still
-- brings it back, and `battery_chain=light` restores the old behaviour.
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
local utils   = require "mp.utils"

local o = {
    -- Semicolon-separated. Matched as plain text anywhere in the file's full
    -- path, ignoring case, so a folder name on its own is enough. Add a show
    -- here when a new animated series joins the library.
    animation_paths = "Solo Leveling;Attack on Titan;One Punch Man;Invincible;Avatar Aang;Anime",

    -- Whether the cable is consulted at all. With this off, `ac_max_chain` is
    -- the ceiling everywhere and `battery_chain` is ignored - the load ladder
    -- still runs, it just never has the cable lowering the ceiling under it.
    power_aware = true,

    -- The BEST chain the ladder may climb to on wall power: "light" or "full".
    -- A ceiling, not a fixed choice - what actually runs is whatever the load
    -- ladder below has earned, up to this.
    ac_max_chain = "full",

    -- What to use on battery: "off", "light" or "full". Off by default - the
    -- full chain drops 43.9% of frames unplugged (measured, see above) and even
    -- the light one is GPU that comes straight out of the battery for a picture
    -- you did not ask for. `y` -> "always on" still overrides this.
    battery_chain = "off",

    -- ---- the load ladder ---------------------------------------------------
    -- Climb to a sharper chain while the machine can afford it, step down when
    -- it cannot. Set to no to pin the chain to ac_max_chain/battery_chain.
    load_aware = true,

    -- How long each measuring window is. At 23.976 fps a 10 s window is about
    -- 240 frames, so the 2% threshold below is ~5 dropped frames - enough to
    -- be a real signal rather than noise. Shorter windows react faster and
    -- convict on nothing.
    load_window_seconds = 10,

    -- Step DOWN a rung when this fraction of the frames in a window is lost.
    load_down_fraction = 0.02,

    -- Step UP only while losses stay under this. The gap between the two is
    -- deliberate: in between, the ladder holds where it is rather than
    -- oscillating around a single threshold.
    load_up_fraction = 0.005,

    -- Seconds of continuous clean playback needed before climbing a rung.
    -- Climbing recompiles the shaders, which is a visible hitch, so this is
    -- slow on purpose while stepping down is immediate. A rung that fails
    -- straight after being climbed to doubles its own wait, up to 8x.
    load_up_after_seconds = 60,

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

-- A misspelt chain name would otherwise be read as level 0 further down and
-- silently turn the shaders off, which looks exactly like the feature being
-- broken. Fail loudly into the documented default instead.
local function validate(name, value, allowed, fallback)
    for _, ok in ipairs(allowed) do if value == ok then return value end end
    msg.warn(name .. " must be one of " .. table.concat(allowed, "/") .. ", got '"
             .. tostring(value) .. "' - using " .. fallback)
    return fallback
end
o.ac_max_chain  = validate("ac_max_chain",  o.ac_max_chain,  {"full", "light"}, "full")
o.battery_chain = validate("battery_chain", o.battery_chain, {"off", "light", "full"}, "off")

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
    -- mpv separates this list with ':' - except on Windows, where ':' is part
    -- of every path (C:/...) and the separator is ';'. Joined with ':' there,
    -- the whole chain reads as one nonexistent file and nothing is sharpened.
    joined[key] = table.concat(paths, mp.get_property("platform") == "windows" and ";" or ":")
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

-- ---- the ladder ------------------------------------------------------------
-- Three rungs. "off" is a rung rather than an absence, so the same stepping
-- logic covers "this machine cannot afford any shaders right now".
local LEVELS     = { off = 0, none = 0, light = 1, full = 2 }
local LEVEL_NAME = { [0] = "none", [1] = "light", [2] = "full" }
local function level_of(word) return LEVELS[word] or 0 end

-- Where the ladder is sitting. Starts at `light`, not at the ceiling: starting
-- at `full` on a machine that is already busy means one bad window - and a
-- visible stutter - before it steps down, while starting light costs 1% of the
-- GPU over nothing at all and climbs within the minute if there is room.
-- Not persisted, for the same reason `mode` is not: what the machine was doing
-- at the last quit says nothing about what it is doing now.
local rung = 1

-- Window state. `dirty` marks the window in progress as unusable: a seek, a
-- pause, a focus change and a shader recompile all drop frames for reasons that
-- have nothing to do with sustained load, and counting those would convict the
-- chain of a cost it is not incurring.
local s_drops, s_delayed, s_time = nil, nil, nil
local dirty      = true
local clean_time = 0
local promo_time = -1e9
local backoff    = { [1] = 1, [2] = 1 }

local function mark_dirty() dirty = true end

-- The best chain allowed right now, cable included.
local function ceiling()
    if o.power_aware and not on_ac then return level_of(o.battery_chain) end
    return level_of(o.ac_max_chain)
end

-- `y` -> "always on" is an explicit instruction, so it floors the ladder at the
-- light chain: a key labelled "always on" that leaves the picture untouched is
-- worse than useless. It never floors at `full`, because the entire point of
-- the ladder is that `full` is not always affordable.
local function floor_level() return mode == "on" and 1 or 0 end

local function target_level()
    return math.max(math.min(rung, ceiling()), floor_level())
end

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
    local key = LEVEL_NAME[target_level()]
    if key == "none" or usable[key] then return key end
    return usable.full and "full" or (usable.light and "light" or "none")
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

-- Returns whether this file WANTS shaders, which is not the same as whether any
-- are loaded: the ladder can hold a wanted file at "none" because the machine
-- cannot afford them. describe() reports the difference.
local function apply()
    local want = wanted()
    local key  = want and chain_key() or "none"
    if key ~= "none" then
        if applied ~= key then
            mp.set_property("glsl-shaders", joined[key])
            applied = key
            mark_dirty()   -- a recompile drops frames; do not bill them to the chain
        end
    elseif applied ~= "none" then
        -- NOT set_property(""): that leaves the list holding one EMPTY path
        -- ([""] rather than []), i.e. mpv still carries a bogus entry around.
        -- 'clr' is the only thing that actually empties the list. Measured.
        mp.commandv("change-list", "glsl-shaders", "clr", "")
        applied = "none"
        mark_dirty()
    end
    return want
end

-- Reports what is actually loaded rather than what the cable says, so a missing
-- light preset can never make this claim the light preset is in use.
local function preset_note()
    if applied == "full"  then return " - full quality" end
    if applied == "light" then return " - light preset" end
    -- Wanted, but nothing is loaded. Which of the two reasons it is matters to
    -- anyone wondering why the picture is not what it was ten minutes ago.
    if o.power_aware and not on_ac then return " - off on battery" end
    return " - off, machine busy"
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

-- ---- reading the load ------------------------------------------------------
-- The signal is mpv's OWN frame counters, not a GPU meter, for two reasons.
--
-- 1. It costs no fork. A load monitor has to sample every few seconds to be any
--    use, and a periodic fork under live audio is exactly the bug fixed in
--    9eac603 - see the long note above refresh_power. `frame-drop-count` is an
--    ordinary property read, entirely in-process, so this timer is free in the
--    way the pmset one was not.
-- 2. It measures the symptom instead of a proxy. Whatever is stealing the
--    machine - another app, a background index, thermal throttling - arrives
--    here as dropped frames, and a chain that cannot be afforded convicts
--    itself. It is self-correcting in a way a utilisation threshold is not.
--
-- Dropped frames stay a valid signal with NO shaders loaded, which is what
-- makes climbing back up possible at all: the 24% no-shader baseline recorded
-- on 2026-09-08 is precisely this, a machine losing a quarter of its frames
-- before mpv had done a single shader pass.
--
-- 🚨 The counters FREEZE while mpv is unfocused - macOS stops compositing it,
-- so every window reads a flawless zero and the ladder would climb to `full` on
-- the strength of a measurement that never happened. Every sample is gated on
-- `focused`, which is the same trap that cost a whole measuring run in 2026-09.
local function sample_load()
    if not o.load_aware or not available then return end

    if mp.get_property("path") == nil
       or mp.get_property("video-format") == nil
       or mp.get_property_bool("pause")
       or not mp.get_property_bool("focused") then
        mark_dirty()
        return
    end

    local drops   = mp.get_property_number("frame-drop-count", 0)
    local delayed = mp.get_property_number("vo-delayed-frame-count", 0)
    local now     = mp.get_time()

    if dirty or not s_time then
        s_drops, s_delayed, s_time, dirty = drops, delayed, now, false
        return
    end

    local elapsed = now - s_time
    local lost    = (drops - s_drops) + (delayed - s_delayed)
    s_drops, s_delayed, s_time = drops, delayed, now
    -- A new file resets mpv's counters, so a negative delta means the window
    -- straddled something this cannot reason about.
    if lost < 0 or elapsed < 1 then return end

    -- As a fraction of the frames that SHOULD have been shown, so one threshold
    -- means the same thing on 23.976 fps film and on 60 fps video.
    local fps = mp.get_property_number("container-fps")
             or mp.get_property_number("estimated-vf-fps") or 24
    local expected = fps * elapsed
    if expected < 1 then return end
    local frac = lost / expected

    -- Unplugging lowers the ceiling under the ladder; never leave `rung` above
    -- it, or plugging back in would restore a rung earned under other
    -- conditions rather than re-earning it.
    local ceil = ceiling()
    if rung > ceil then rung = ceil end

    local before = applied
    if frac >= o.load_down_fraction and rung > 0 then
        -- Failed its probation: this rung was climbed to moments ago and has
        -- already cost frames, so the next attempt waits longer. Capped at 8x
        -- so the longest retry stays bounded - 8 minutes at the default.
        if (now - promo_time) < (o.load_up_after_seconds * 2) then
            backoff[rung] = math.min((backoff[rung] or 1) * 2, 8)
        end
        rung, clean_time = rung - 1, 0
        msg.info(string.format("load %.1f%% of frames lost, stepping down to %s",
                               frac * 100, LEVEL_NAME[rung]))
    elseif frac <= o.load_up_fraction then
        clean_time = clean_time + elapsed
        local up = rung + 1
        if up <= ceil and clean_time >= o.load_up_after_seconds * (backoff[up] or 1) then
            rung, promo_time, clean_time = up, now, 0
            msg.info("clean for " .. math.floor(o.load_up_after_seconds *
                     (backoff[up] or 1)) .. "s, stepping up to " .. LEVEL_NAME[rung])
        end
    else
        clean_time = 0        -- between the two thresholds: hold where we are
    end

    -- NO OSD HERE, and not by oversight - read THE OSD RULE at the top of this
    -- file before putting one back. `before` survives only so the log line
    -- below can record a rung change that nothing on screen will.
    apply()
    if applied ~= before then msg.info("chain now " .. applied) end
end

-- What a change of power source does, whichever way it was found out.
local function set_power(ac)
    if ac == on_ac then return end          -- nothing moved
    on_ac = ac
    -- A different cable is a different regime: what the ladder learned
    -- about what this machine could afford a minute ago does not carry
    -- across, so the penalties and the clean streak both start again.
    backoff, clean_time, promo_time = { [1] = 1, [2] = 1 }, 0, -1e9
    if rung > ceiling() then rung = ceiling() end
    mark_dirty()
    msg.info(ac and ("on AC, ceiling " .. o.ac_max_chain)
                 or ("on battery, " .. o.battery_chain))
    apply_pacing()
    apply()
    -- Silent, including on plug and unplug. THE OSD RULE.
end

-- Linux keeps the answer in sysfs, so there it is a plain file read - no fork,
-- and none of the audio trouble above. AC if any mains or USB supply is online;
-- battery only if a battery says it is discharging; AC otherwise, which covers
-- a desktop with no battery at all.
local function linux_on_ac()
    local base = "/sys/class/power_supply"
    local function read(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local v = f:read("*l")
        f:close()
        return v
    end
    local discharging = false
    for _, name in ipairs(utils.readdir(base, "dirs") or utils.readdir(base) or {}) do
        local dir  = base .. "/" .. name
        local kind = read(dir .. "/type")
        if (kind == "Mains" or kind == "USB" or kind == "USB_C") and read(dir .. "/online") == "1" then
            return true
        end
        if kind == "Battery" and read(dir .. "/status") == "Discharging" then
            discharging = true
        end
    end
    return not discharging
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
-- that matters most. There used to be a `quiet` flag here to suppress the OSD
-- on checks the user had not asked for; every check is silent now, so it went.
local function refresh_power()
    if not o.power_aware then return end
    local platform = mp.get_property("platform")
    if platform == "linux" then return set_power(linux_on_ac()) end

    -- macOS: pmset. Windows: `mpv-open.exe --power` (the launcher install.ps1
    -- builds), which prints ac / battery from the same GetSystemPowerStatus
    -- call the taskbar's battery icon reads. Neither has a file to read.
    local args = { "/usr/bin/pmset", "-g", "ps" }
    if platform == "windows" then
        args = { mp.command_native({ "expand-path", "~~/mpv-open.exe" }), "--power" }
    elseif platform ~= "darwin" then
        return                                  -- the BSDs: stay on AC
    end
    mp.command_native_async({
        name          = "subprocess",
        args          = args,
        capture_stdout = true,
        playback_only = false,
    }, function(ok, res)
        if not ok or not res or res.status ~= 0 or not res.stdout then
            msg.warn("could not read the power source, assuming AC")
            return
        end
        -- "Now drawing from 'AC Power'" / "Now drawing from 'Battery Power'",
        -- or mpv-open.exe's "ac" / "battery" / "unknown"
        if platform == "windows" then
            set_power(not res.stdout:find("battery", 1, true))
        else
            set_power(res.stdout:find("AC Power", 1, true) ~= nil)
        end
    end)
end

-- Every refresh goes through here, so one debounce covers all of them. `gap`
-- is the shortest time allowed since the last check: scrubbing fires `seek`
-- many times a second, and each one would otherwise be a fork.
local last_poll = -1e9
local function poll_power(gap)
    if not o.power_aware then return end
    local now = mp.get_time()
    if gap and (now - last_poll) < gap then return end
    last_poll = now
    refresh_power()
end

local function cycle()
    local i = 1
    for n, m in ipairs(MODES) do if m == mode then i = n end end
    mode = MODES[(i % #MODES) + 1]
    -- The ONE place this script raises an OSD. THE OSD RULE, top of the file.
    mp.osd_message(describe(apply()), 2)
    msg.info("mode " .. mode)
    poll_power()          -- correct the chain; the line above already spoke
end

-- Silent on load, deliberately: mpv says nothing when it picks a video track
-- either, and an OSD line on every single file would be noise. Only the key talks.
mp.register_event("file-loaded", function()
    mark_dirty()
    apply_pacing()
    apply()
    poll_power()              -- no gap: a new file is always worth one check
end)

-- Pausing stops the audio outright, so this is the one moment a fork is
-- certainly free - and it is also when someone who has just reached for the
-- charger is most likely to be sitting in front of it.
mp.observe_property("pause", "bool", function(_, paused)
    mark_dirty()
    if paused then poll_power(3) end
end)

-- A seek flushes and refills the audio buffer anyway, so a fork inside that
-- window has nothing to interrupt.
mp.register_event("seek", function()
    mark_dirty()
    poll_power(15)
end)

-- Both of these drop frames for reasons that are nothing to do with sustained
-- load - a refill after a seek, and a window that macOS simply stopped
-- compositing - so the window in progress is discarded rather than counted.
mp.register_event("playback-restart", mark_dirty)
mp.observe_property("focused", "bool", mark_dirty)

-- Unlike the power poll above, this is a plain in-process property read with no
-- subprocess behind it, so a timer that fires during playback is safe here in
-- exactly the way it was not there.
if o.load_aware and o.load_window_seconds > 0 then
    mp.add_periodic_timer(o.load_window_seconds, sample_load)
end

-- Backstop only, and only while paused: a timer that fires during playback is
-- exactly the bug described above. This is what notices when the machine sat
-- paused for an hour and the charger came out in the meantime.
if o.power_aware and o.power_poll_seconds > 0 then
    mp.add_periodic_timer(o.power_poll_seconds, function()
        if mp.get_property_bool("pause") then poll_power(3) end
    end)
end

poll_power()

mp.add_key_binding(nil, "cycle-video-quality", cycle)
