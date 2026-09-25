-- Put the green bar in the black strip under the picture, and the subtitles
-- just above it.
--
-- A 16:9 video in fullscreen on this panel does not fill it: the drawable is
-- 3456x2168, the picture 1944 rows, and 112 rows of black are left below it.
-- mpv.conf's osd-bar-align-y=0.90 is a fixed fraction of the WINDOW and knows
-- nothing about that strip, so the bar landed straddling the bottom edge of the
-- picture, most of it over the video, with the strip under it empty.
--
-- This moves the bar into the strip whenever there is one tall enough to hold
-- it, and puts it back at mpv.conf's position when there is not - a window
-- shaped like the video, a video that fills the screen, g (zoom to fill).
-- osd-dimensions reports the strip (mb), and fires on every change of window,
-- fullscreen, file or zoom, so the bar follows without being told.
--
-- It is mpv's ONE built-in bar, so this moves everything that uses it: the
-- seek bar (a seek, or a mouse move via mouse-progress.lua) and the volume bar
-- the trackpad / mouse wheel shows. The upright volume bar on the arrow keys
-- is a separate overlay (vertical-volume.lua) and stays where it is.
--
-- Subtitles are not in the way. Measured 2026-09-25 in a window the shape of
-- fullscreen: on a 16:9 video a subtitle sits OVER the picture, above the bar
-- (sub-margin-y=68 in mpv.conf lifted it there), so moving the bar down moves
-- it away from them. On a 2.39:1 film the subtitle does sit in the black strip,
-- and that is why a tall strip does NOT get the bar in its middle: centred
-- there it landed 2px under the subtitle. It goes no more than MAX_GAP of its
-- own height off the bottom edge instead, which keeps it below the subtitle
-- for any strip.
--
-- ...and they follow it down. That 68 exists to clear the bar at 0.90, so with
-- the bar in the strip it was clearing a bar that was no longer there, and the
-- user asked for the subtitles lower. While the bar is in the strip their
-- bottom edge sits SUB_GAP above the bar's top edge: on 16:9 that is the bottom
-- edge of the picture, where they used to sit about a line higher; on a wide
-- film they drop lower in the black strip. With no strip the bar is back at
-- 0.90 and so are they, at mpv.conf's value. They only ever move down from it.
-- sub-margin-y moves plain-text subtitles only; styled (ASS) subtitles place
-- themselves inside the picture and are left alone.
--
-- The time readout mouse-progress.lua draws used to sit in this strip too. It
-- reads the geometry published here (user-data/bar-in-strip) and splits itself
-- either side of the bar while the bar is down here.

local mp = require 'mp'

-- mpv.conf's spot, used whenever there is no strip. Read before anything
-- below changes it, so mpv.conf stays the one place that sets it.
local FALLBACK = mp.get_property_number("osd-bar-align-y", 0.9)
-- The same for the subtitles: mpv.conf's margin, which clears the bar at 0.90.
local SUB_FALLBACK = mp.get_property_number("sub-margin-y", 68)

-- Both are fractions of the bar's own height, outline included.
local MIN_GAP = 0.15   -- the strip must leave this much free above AND below it
local MAX_GAP = 0.5    -- in a taller strip, the most it sits off the bottom edge

local SUB_GAP = 0.01   -- subtitles to the bar's top edge, fraction of the height

local last_align, last_sub = nil, nil

local function place()
    local d = mp.get_property_native("osd-dimensions")
    if not d or not d.w or not d.h or d.w <= 0 or d.h <= 0 then return end
    local w, h, mb = d.w, d.h, math.max(0, d.mb or 0)

    -- mpv lays the bar out on a 288-row canvas and scales that to the window
    -- (sub/osd_libass.c get_align(), v0.41.0), so the outline is 0.5/288 of
    -- the height and the bar's centre, for an align-y of a, is
    --   border + bar_h/2 + (h - bar_h - 2*border)/2 * (1 + a)
    local bar_h  = h * mp.get_property_number("osd-bar-h", 3.125) / 100
    local bar_w  = w * mp.get_property_number("osd-bar-w", 75) / 100
    local border = mp.get_property_number("osd-bar-outline-size", 0.5) * h / 288
    local full   = bar_h + 2 * border

    local align, info, sub = FALLBACK, { strip = false }, SUB_FALLBACK
    if mb >= full * (1 + 2 * MIN_GAP) then
        local gap = math.min((mb - full) / 2, full * MAX_GAP)
        local cy  = h - gap - full / 2
        align = (cy - border - bar_h / 2) / ((h - bar_h - 2 * border) / 2) - 1
        align = math.max(-1, math.min(1, align))
        local ax   = mp.get_property_number("osd-bar-align-x", 0)
        local left = border + (w - 2 * border - bar_w) / 2 * (1 + ax)
        -- outer edges, outline included, in window pixels
        info = { strip = true, cy = cy, x1 = left - border,
                 x2 = left + bar_w + border, height = full }
        -- sub-margin-y counts from the WINDOW's bottom edge only while
        -- sub-use-margins lets subtitles into the black; otherwise it counts
        -- from the picture's, which is above the strip already. Its unit is a
        -- scaled pixel, 720 of them to the window's height.
        if mp.get_property_bool("sub-use-margins", true) then
            local above_bar = h - (cy - full / 2) + SUB_GAP * h
            sub = math.min(SUB_FALLBACK, math.ceil(above_bar * 720 / h))
        end
    end

    if align ~= last_align then
        mp.set_property_number("osd-bar-align-y", align)
        last_align = align
    end
    if sub ~= last_sub then
        mp.set_property_number("sub-margin-y", sub)
        last_sub = sub
    end
    mp.set_property_native("user-data/bar-in-strip", info)
end

mp.observe_property("osd-dimensions", "native", place)
