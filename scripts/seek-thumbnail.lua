-- Seek thumbnails: hover the bottom strip, see the frame at that point.
--
-- mpv has no thumbnail preview of its own, and the built-in OSC has no
-- thumbfast support either - checked on 0.41, where the only "thumbnail"
-- strings in the binary belong to the YouTube metadata handler. The usual
-- answer is to replace the whole controller with uosc, which is far more
-- furniture than this setup wants. So instead: thumbfast does the decoding,
-- and this script is the 60 lines that point it at the mouse.
--
-- scripts/thumbfast.lua generates the frames. It spawns a second, hidden mpv
-- the first time you hover, talks to it over a socket, and (per
-- script-opts/thumbfast.conf) shuts it down again after 30s idle. Opening a
-- file costs nothing extra; nothing runs until the bar is hovered.
--
-- The trigger zone is the same BOTTOM_ZONE that mouse-progress.lua deliberately
-- stays out of, so the two never draw at once:
--   * pointer above it  -> the slim seek bar, no thumbnail
--   * pointer below it  -> the OSC, and a thumbnail above the pointer

local mp      = require 'mp'
local utils   = require 'mp.utils'
local options = require 'mp.options'

local BOTTOM_ZONE = 0.88   -- keep in step with mouse-progress.lua
local GAP         = 12     -- px between the thumbnail and the OSC strip
local MARGIN      = 8      -- px; keep the thumbnail clear of the screen edges
local JITTER      = 4      -- px; smaller moves are noise (as in osc-idle-hide.lua)

-- ---- where the OSC's seek bar actually is ----------------------------------
--
-- The thumbnail has to agree with the bar underneath it: hover a point, see
-- that frame, click, land there. An earlier version mapped the pointer across
-- the FULL window width, which is wrong - the bar is inset between the elapsed
-- and remaining timecodes, so mid-bar it was out by ~15s on a 2-minute file.
--
-- These constants are osc.lua's own, for the bottombar layout it uses by
-- default. mpv's OSC is compiled into the binary rather than shipped as a
-- file, but the Lua source is still recoverable:
--   strings /opt/homebrew/bin/mpv | grep -n 'local function bar_layout'
-- from which, with osc_geo.x = -2 and osc_geo.w = playresx + 4:
--   sb_l = osc_geo.x + 5*padX + 3*buttonW + tcW
--   sb_r = osc_geo.x + osc_geo.w - 2*buttonW - 2*tsW - tcW - 6*padX - 10
local OSC_X       = -2
local PAD_X       = 9
local BUTTON_W    = 27
local TRACK_SEL_W = 90     -- tsW: the audio/subtitle track buttons
local TC_W        = 110    -- tcW: timecode width. 170 if the OSC is showing
                           -- milliseconds, which is off unless you click the
                           -- timecode. Not duration-dependent - an hour-long
                           -- film uses the same 110 as a two-minute one.

-- Canvas -> window pixels. osc.lua lays itself out on its own canvas
-- (playresx x playresy) and mpv scales that to the window, so every constant
-- above is in canvas units and has to be converted.
local function seekbar_bounds()
    local w, h, aspect = mp.get_osd_size()
    if not w or not h or w == 0 or h == 0 then return nil end
    if not aspect or aspect <= 0 then aspect = w / h end

    local so = mp.get_property_native("options/script-opts") or {}
    local function num(key, default)
        local v = tonumber(so[key]); return v or default
    end

    local scale = mp.get_property_bool("fullscreen")
        and num("osc-scalefullscreen", 1) or num("osc-scalewindowed", 1)
    if scale <= 0 then return nil end

    local vidscale = so["osc-vidscale"] or "auto"
    local scale_with_video
    if vidscale == "auto" then
        scale_with_video = mp.get_property_bool("osd-scale-by-window")
    else
        scale_with_video = (vidscale == "yes")
    end

    local playresy = (scale_with_video and 720 or h) / scale
    local playresx = playresy * aspect

    local tc = TC_W * (num("osc-tcspace", 100) / 100)

    -- osc.lua enlarges the canvas rather than let the bar collapse on a very
    -- narrow window; same clamp, or the bounds are wrong when small.
    local minw = (BUTTON_W + PAD_X) * 5 + (tc + PAD_X) * 4 + (TRACK_SEL_W + PAD_X) * 2
    if playresx < minw then
        playresy = minw / aspect
        playresx = playresy * aspect
    end

    local k = w / playresx
    local sb_l = OSC_X + 5 * PAD_X + 3 * BUTTON_W + tc
    local sb_r = OSC_X + playresx + 4
                 - 2 * BUTTON_W - 2 * TRACK_SEL_W - tc - 6 * PAD_X - 10
    if sb_r <= sb_l then return nil end
    return sb_l * k, sb_r * k
end

local info    = nil        -- last thumbfast-info payload (size, availability)
local showing = false
local last    = nil        -- where the pointer was last reported, {x, y}
local anchor  = nil        -- where it was when this script last acted on it

-- How long a preview may stay up with the pointer resting on the bar.
-- osc-idle-hide.lua normally pulls it before then, together with the controls
-- (see osc-idle-hidden below); this is the backstop for when that never
-- arrives, so a preview cannot outlive the pointer that asked for it. It reads
-- osc-idle-hide's own options, so raising idle_seek in
-- script-opts/osc_idle_hide.conf still buys the extra time it promises.
local idle_opts = { idle = 2, idle_seek = 2, seek_zone = 0.88, cursor_idle = 1 }
options.read_options(idle_opts, "osc_idle_hide")
local HOLD = idle_opts.idle_seek + 0.5

-- thumbfast broadcasts its dimensions and whether it can work on this file
-- (it disables itself for streams, cover art and audio-only).
mp.register_script_message("thumbfast-info", function(json)
    local v = utils.parse_json(json)
    if type(v) == "table" then info = v end
end)

local expire

-- force: tell thumbfast even if this script thinks nothing is up. After the
-- window changes size that belief is not worth trusting, and a spare clear
-- costs nothing.
local function clear(force)
    if not showing and not force then return end
    mp.commandv("script-message-to", "thumbfast", "clear")
    showing = false
    expire:kill()
end

expire = mp.add_timeout(HOLD, function() clear() end)
expire:kill()

-- osc-idle-hide.lua pulls the controls after 2s of a stationary pointer. The
-- thumbnail is a separate overlay and would otherwise be left hanging there on
-- its own, so it goes at the same moment.
mp.register_script_message("osc-idle-hidden", function() clear() end)

-- ---- when the window changes size ------------------------------------------
--
-- The preview is drawn at fixed window pixels, so it has to go whenever the
-- window changes size: f, a lone video shrinking itself at its end
-- (single-video.lua), dragging an edge. Left alone it stays at its old pixels,
-- which after f is the middle of the picture.
--
-- Worse, mpv re-reports the pointer's LAST position the moment the window
-- changes, before you have moved at all - and that position was measured
-- against the OLD window. Traced 2026-10-15, a 960x540 window going
-- fullscreen: fullscreen=true, then mouse-pos (3358,2144) left over from an
-- earlier fullscreen spell, while osd-dimensions still said 960x540. To that
-- window the spot is "in the bottom strip, past the bar's right end", so a
-- preview of the film's LAST frame went up in its bottom-right corner, and
-- stayed in the middle of the picture once the window had grown. That is the
-- little box of end titles that kept turning up after f. mpv does the same
-- when the pointer comes back into the window after leaving it.
--
-- So: drop the preview, and do not believe the pointer again until it really
-- moves away from where it was last reported. Registered before mouse-pos on
-- purpose - mpv hands a script its property changes in the order they were
-- observed, so a resize and its replay arriving together are seen in that order.
local osd_w, osd_h = nil, nil

local function window_changed()
    clear(true)
    anchor = last
end

mp.observe_property("fullscreen", "bool", window_changed)

mp.observe_property("osd-dimensions", "native", function(_, od)
    if not od then return end
    -- the margins change too (g, a new file's shape); only the size matters
    if od.w == osd_w and od.h == osd_h then return end
    osd_w, osd_h = od.w, od.h
    window_changed()
end)

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos then return clear() end
    last = { x = pos.x, y = pos.y }

    -- Pointer left the window. When it comes back, mpv first re-reports this
    -- spot (see above), so treat that as "not moved yet".
    if not pos.hover then
        anchor = last
        return clear()
    end

    -- Not a real move: sensor noise from a resting finger, the 1px nudge
    -- osc-idle-hide.lua replays, or mpv repeating an old position after the
    -- window changed. Same 4px floor osc-idle-hide.lua uses, so a preview
    -- cannot come back on its own under controls that stayed hidden.
    if anchor and math.abs(pos.x - anchor.x) < JITTER
              and math.abs(pos.y - anchor.y) < JITTER then
        return
    end
    anchor = last

    if not info or info.disabled or not info.available then return clear() end

    local w, h = mp.get_osd_size()
    if not w or not h or w == 0 or h == 0 then return clear() end

    -- above the strip is mouse-progress.lua's territory
    if pos.y < h * BOTTOM_ZONE then return clear() end

    local dur = mp.get_property_number("duration")
    if not dur or dur <= 0 then return clear() end

    -- Map onto the OSC's actual bar, not the window, so the preview agrees
    -- with the bar under it and with where a click would land.
    local sb_l, sb_r = seekbar_bounds()
    if not sb_l then return clear() end
    local frac = (pos.x - sb_l) / (sb_r - sb_l)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    local tw, th = info.width or 0, info.height or 0
    if tw == 0 or th == 0 then return end

    -- centred on the pointer, sitting just above the strip, clamped so it
    -- never runs off either edge at the start and end of the film
    local tx = math.floor(pos.x - tw / 2)
    local ty = math.floor(h * BOTTOM_ZONE - th - GAP)
    if tx < MARGIN then tx = MARGIN end
    if tx + tw > w - MARGIN then tx = w - MARGIN - tw end
    if ty < MARGIN then ty = MARGIN end

    mp.commandv("script-message-to", "thumbfast", "thumb",
                string.format("%.3f", frac * dur),
                string.format("%d", tx),
                string.format("%d", ty))
    showing = true
    expire:kill()
    expire:resume()
end)

-- do not carry a stale preview across a file change
mp.register_event("start-file", function() showing = false; expire:kill() end)
