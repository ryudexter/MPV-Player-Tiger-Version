-- How a video that is alone in its playlist ends: it rewinds to its start and
-- waits there, paused, in a small window - and Space plays it again from the
-- beginning. Asked for 2026-10-07.
--
-- The playlist is the folder (autocreate-playlist in mpv.conf), so "alone"
-- means a folder holding one video, a URL, or anything else that queues nothing
-- behind it. A folder with more than one video is not touched: it still wraps
-- back to its first video and keeps going.
--
-- Why it needs a script
-- ---------------------
-- loop-playlist=inf in mpv.conf is what keeps a folder going round, and on a
-- one-entry playlist "the next lap" is the same video again: it went back to 0
-- and played forever. loop-playlist has no "only when there is more than one"
-- setting, so this switches it off while the playlist holds a single entry and
-- puts back whatever it was the moment a second one arrives. With the loop out
-- of the way, keep-open=yes (mpv.conf) gets the end of the file: mpv pauses on
-- the last frame instead of quitting.
--
-- From there this rewinds to 0, still paused. That is what makes Space "play it
-- again" without a binding of its own - Space is mpv's stock cycle pause - and
-- the same goes for the play button, a media key, and opening the file again
-- from Finder (mpv-open lifts the pause). Left on the last frame, every one of
-- those would unpause straight into the end and stop again.
--
-- ⚠️ Rewind once keep-open has PAUSED, not the moment eof-reached flips.
-- keep-open is still at work when eof-reached goes true - it waits for the
-- audio to drain before it pauses - and a seek sent into that gap can be
-- overridden. Measured 2026-10-07 on a 3s clip: rewinding on eof-reached alone
-- left the player parked at 2.97s in 1 run of 5; waiting for the pause, 9 of 9
-- landed on 0.0 (windowed, minimised, and out of fullscreen).
--
-- The window
-- ----------
-- The end also leaves fullscreen and shrinks the window to the size mpv opens
-- at with nothing loaded (960x540 pixels, 480x270 points on this panel) - the
-- "Drop files or URLs to play here" window, but with the video still in it.
-- A video smaller than that keeps its own size, and so does a window that was
-- already dragged smaller.
--
-- It is written to current-window-scale, NOT window-scale. window-scale is the
-- OPTION every later file is sized from, so the next video opened would come up
-- shrunken too. current-window-scale resizes this window only (measured: the
-- window went 640x360 -> 480x270 points while window-scale stayed 1.0).
--
-- Shuffle
-- -------
-- shuffle-mode.lua forces keep-open=always, so it stops at the end of every
-- file anyway. With a single video it has nothing to deal, and it leaves the
-- player paused there for this script rather than restarting the video.

local mp = require 'mp'

-- What mpv opens at with nothing loaded, in video pixels. Measured 2026-10-07
-- through osd-width/osd-height on an idle player.
local BOX_W, BOX_H = 960, 540

-- loop-playlist as it was before a one-entry playlist switched it off; nil
-- while it is not switched off.
local held = nil

local function on_count(_, n)
    if (n or 0) <= 1 then
        if held == nil then
            held = mp.get_property("loop-playlist")
            mp.set_property("loop-playlist", "no")
        end
    elseif held ~= nil then
        mp.set_property("loop-playlist", held)
        held = nil
    end
end

local function shrink()
    local p = mp.get_property_native("video-out-params")
    if not p or not p.dw or p.dw == 0 then return end   -- audio only: nothing to size
    local w, h = p.dw, p.dh
    -- dw/dh are measured BEFORE rotation: a phone video shot upright reports
    -- 1280x720 with rotate=270 and is shown 720x1280 (measured)
    if (p.rotate or 0) % 180 == 90 then w, h = h, w end
    local cur = mp.get_property_number("current-window-scale") or 1
    mp.set_property_number("current-window-scale", math.min(BOX_W / w, BOX_H / h, cur))
    mp.set_property_bool("fullscreen", false)
end

local function at_end()
    if not (mp.get_property_bool("eof-reached") and mp.get_property_bool("pause")) then
        return
    end
    if (mp.get_property_number("playlist-count") or 0) > 1 then return end
    mp.commandv("seek", 0, "absolute", "exact")
    shrink()
end

mp.observe_property("playlist-count", "number", on_count)
mp.observe_property("eof-reached", "bool", at_end)
mp.observe_property("pause", "bool", at_end)
