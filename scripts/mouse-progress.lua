-- Show the seek bar when the mouse moves.
--
-- mpv's on-screen controller (the bar with the buttons, filename and timers)
-- pops up on any mouse movement anywhere in the window, which is a lot of
-- furniture to throw over a film every time the pointer twitches.
--
-- The split is:
--   * move the mouse anywhere      -> just the slim seek bar, via show-progress
--   * move it down onto the OSC    -> the full controller, as before
--
-- The second half is not this script: mpv.conf sets osc-deadzonesize=1, which
-- means "the OSC only shows up when the mouse hovers it". This script fills in
-- the first half.
--
-- show-progress draws the same bar a seek does, so it already inherits the
-- styling in mpv.conf (green, 44% opaque, near the bottom) and disappears on
-- its own after --osd-duration.
--
-- The elapsed/duration readout that normally comes with show-progress is
-- blanked in mpv.conf (osd-msg3=" ") and redrawn here instead, at the bottom
-- under the bar. Doing it that way rather than with osd-align-y=bottom keeps
-- every other OSD message ("Subtitles off", "Zoom to fill", ...) in the
-- top-left corner where mpv puts them - osd-align-y is global and would have
-- moved those as well.
-- Colour and opacity match the seek bar and the volume bar: 50DC82 at ASS
-- alpha 51, which is the ~80% the rest of the OSD uses.

local mp = require 'mp'

-- uosc replaces mpv's built-in OSC, and mpv.conf turns the built-in one off
-- when uosc is installed. This script exists only to manage that built-in
-- controller, so with it gone there is nothing here to do and staying active
-- would only fight uosc's own equivalent. Stand down.
if not mp.get_property_bool("osc") then return end

local BOTTOM_ZONE = 0.88   -- below this fraction of the height the OSC takes over
local MIN_MOVE    = 4      -- px; ignore pointer jitter
local REPEAT_GAP  = 0.25   -- s; re-arm the bar while the mouse keeps moving

local last_x, last_y, last_shown = nil, nil, 0
local show_time  -- defined below

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos or not pos.hover then return end

    local _, h = mp.get_osd_size()
    if not h or h == 0 then return end

    local x, y = pos.x, pos.y
    if last_x then
        local dx, dy = x - last_x, y - last_y
        if dx * dx + dy * dy < MIN_MOVE * MIN_MOVE then return end
    end
    last_x, last_y = x, y

    -- Down in the OSC's own strip, leave it alone: showing both at once would
    -- stack the seek bar on top of the controller.
    if y >= h * BOTTOM_ZONE then return end

    local now = mp.get_time()
    if now - last_shown < REPEAT_GAP then return end
    last_shown = now

    mp.commandv("show-progress")
    show_time()
end)

-- ---- the readout under the bar --------------------------------------------

local TEXT_COLOUR = "&H82DC50&"   -- ASS is &HBBGGRR&, i.e. 50DC82 reversed
local TEXT_ALPHA  = "&H33&"       -- 51: ~80% opaque, same as the bars
local TEXT_FRAC   = 0.038         -- font size as a fraction of screen height
local MARGIN_X    = 16

local overlay   = mp.create_osd_overlay("ass-events")
local hide_timer = nil

local function hide_time()
    overlay.data = ""
    overlay:update()
end

function show_time()
    local pos = mp.get_property_osd("playback-time")
    local dur = mp.get_property_osd("duration")
    if not pos or pos == "" then return end

    local w, h = mp.get_osd_size()
    if not w or not h or h == 0 then return end
    overlay.res_x, overlay.res_y = w, h

    local pct  = mp.get_property_number("percent-pos")
    local text = pos .. (dur ~= "" and (" / " .. dur) or "")
    if pct then text = text .. string.format(" (%d%%)", pct) end
    if mp.get_property_bool("pause") then text = "|| " .. text end

    -- \an1 anchors at the bottom-left, so y is the text's baseline area and it
    -- grows upward from the bottom edge rather than down off the screen.
    overlay.data = string.format(
        "{\\an1\\pos(%d,%d)\\fs%d\\bord1\\3c&H000000&\\3a%s\\1c%s\\1a%s}%s",
        MARGIN_X, h - 4, math.floor(h * TEXT_FRAC),
        TEXT_ALPHA, TEXT_COLOUR, TEXT_ALPHA, text)
    overlay:update()

    if hide_timer then hide_timer:kill() end
    local secs = (mp.get_property_number("osd-duration") or 1000) / 1000
    hide_timer = mp.add_timeout(secs, hide_time)
end
