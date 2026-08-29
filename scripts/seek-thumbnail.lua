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

local mp    = require 'mp'
local utils = require 'mp.utils'

local BOTTOM_ZONE = 0.88   -- keep in step with mouse-progress.lua
local GAP         = 12     -- px between the thumbnail and the OSC strip
local MARGIN      = 8      -- px; keep the thumbnail clear of the screen edges

local info    = nil        -- last thumbfast-info payload (size, availability)
local showing = false

-- thumbfast broadcasts its dimensions and whether it can work on this file
-- (it disables itself for streams, cover art and audio-only).
mp.register_script_message("thumbfast-info", function(json)
    local v = utils.parse_json(json)
    if type(v) == "table" then info = v end
end)

local function clear()
    if not showing then return end
    mp.commandv("script-message-to", "thumbfast", "clear")
    showing = false
end

-- osc-idle-hide.lua pulls the controls after 2s of a stationary pointer. The
-- thumbnail is a separate overlay and would otherwise be left hanging there on
-- its own, so it goes at the same moment.
mp.register_script_message("osc-idle-hidden", clear)

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos or not pos.hover then return clear() end
    if not info or info.disabled or not info.available then return clear() end

    local w, h = mp.get_osd_size()
    if not w or not h or w == 0 or h == 0 then return clear() end

    -- above the strip is mouse-progress.lua's territory
    if pos.y < h * BOTTOM_ZONE then return clear() end

    local dur = mp.get_property_number("duration")
    if not dur or dur <= 0 then return clear() end

    -- The OSC's seek bar spans the full window width in mpv's default
    -- bottombar layout, so the pointer's x maps straight onto the timeline
    -- and matches the time the OSC's own tooltip shows.
    local frac = pos.x / w
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
end)

-- do not carry a stale preview across a file change
mp.register_event("start-file", function() showing = false end)
