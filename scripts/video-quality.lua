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
-- TWO PRESETS, chosen by the power cable (see `power_aware` below). Superseding
-- an earlier note here that claimed there was nothing to save: that measurement
-- was taken plugged in. On battery an M3 Max does NOT have the GPU headroom for
-- the full preset. Measured 2026-09-08, fullscreen 3456x2168, 1080p HEVC, in one
-- run with the chains swapped over the IPC socket so conditions are identical:
--   full   Mode A (HQ)            ~45% of frames dropped,  display rate ~60 fps
--   light  Mode A minus Restore   ~6-14% dropped,          display rate 87-106
--   off    no shaders at all         0% dropped,           display rate 120
-- So `light` cuts the damage by roughly three quarters but does NOT eliminate
-- it. It is the better of the two presets while unplugged, not a clean fix - if
-- you want no dropped frames at all on battery, `y` to off is the honest answer.
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

    -- Pick the preset from the power source: full on AC, light on battery.
    -- Set to no to always use the full preset, whatever the cable is doing.
    power_aware = true,

    -- How often to re-read the power source, in seconds. Only polled while the
    -- shaders are actually in use, so an idle player costs nothing. This is
    -- also the worst-case delay before unplugging takes effect.
    power_poll_seconds = 30,
}
options.read_options(o, "video-quality")

-- Anime4K v4.0.1 "Mode A (HQ)", the preset upstream recommends for 1080p anime
-- that is slightly soft: it restores the line art, then upscales it. `light` is
-- the same chain with the Restore stage removed. The order of these lists
-- matters - each shader feeds the next.
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
        "Anime4K_Upscale_CNN_x2_VL.glsl",
        "Anime4K_AutoDownscalePre_x2.glsl",
        "Anime4K_AutoDownscalePre_x4.glsl",
        "Anime4K_Upscale_CNN_x2_M.glsl",
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
    local want = (o.power_aware and not on_ac) and "light" or "full"
    if usable[want] then return want end
    return usable.full and "full" or "light"    -- whichever survived
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
    if applied == "light" then return " - light preset, on battery" end
    if applied == "full" and o.power_aware then return " - full quality" end
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
-- for. `pmset -g ps` is a ~10 ms fork, and playback_only=false so it still
-- answers while paused. quiet=true suppresses the OSD for checks the user did
-- not ask for (script load, file load).
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
        local on = apply()
        -- The picture visibly changes here without the user having touched a
        -- key, so say why: an unexplained softer frame mid-episode reads as a bug.
        if on and applied ~= before and not quiet then
            mp.osd_message(describe(on), 2)
        end
    end)
end

local function cycle()
    local i = 1
    for n, m in ipairs(MODES) do if m == mode then i = n end end
    mode = MODES[(i % #MODES) + 1]
    mp.osd_message(describe(apply()), 2)
    msg.info("mode " .. mode)
    refresh_power(true)   -- correct the preset silently; the line above already spoke
end

-- Silent on load, deliberately: mpv says nothing when it picks a video track
-- either, and an OSD line on every single file would be noise. Only the key talks.
mp.register_event("file-loaded", function()
    apply()
    refresh_power(true)
end)

if o.power_aware and o.power_poll_seconds > 0 then
    mp.add_periodic_timer(o.power_poll_seconds, function()
        if wanted() then refresh_power(false) end
    end)
end

refresh_power(true)

mp.add_key_binding(nil, "cycle-video-quality", cycle)
