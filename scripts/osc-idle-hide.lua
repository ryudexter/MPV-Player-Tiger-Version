-- Hide the OSC *and the mouse cursor* when the mouse sits still, even while it
-- is over the OSC itself.
--
-- mpv's own osc.lua refuses to auto-hide whenever the pointer is inside the OSC
-- area (see its render loop: the hidetimeout is ignored while mouse_over_osc).
-- With osc-deadzonesize=1 the only way to SEE the OSC is to put the pointer down
-- there, so in this setup it could never time out at all - park the mouse at the
-- bottom edge and the controls stayed up indefinitely.
--
-- This watches mouse-pos and, after IDLE seconds without real movement, tells the
-- OSC to go away; the next real movement hands control straight back to it.
-- Nothing here changes what the OSC does while the mouse is actually moving.
--
-- The cursor is handled here too, on its own shorter timer, because mpv's
-- --cursor-autohide could not do the job alone. That option restarts its
-- countdown on ANY movement, and a finger resting on a trackpad never really
-- stops moving, so a pointer left over the picture stayed lit through a whole
-- film even at the 1000ms default. The JITTER floor below is the fix: sub-4px
-- twitches are not movement, so the countdown actually finishes.
--
-- mpv has no explicit hide-the-cursor command, but cursor-autohide=always is
-- exactly that, and setting it back to its configured value brings the pointer
-- back. The cursor keeps a separate timer from the OSC so the two can differ:
-- the pointer is pure clutter and goes at 1s, while the controls are worth a
-- moment longer.

local options = require 'mp.options'

-- idle_seek used to be 6, to keep seek-thumbnail.lua's preview frame on screen
-- while you hold still ON PURPOSE to read it. The problem is that with
-- osc-deadzonesize=1 the ONLY way to summon the OSC is to put the pointer into
-- the bottom strip - the very strip seek_zone covers - so the 6s branch was
-- taken every single time and the 2s below was dead code. Measured by parking
-- the pointer at y=690 in a 720-high window and screenshotting: the OSC was
-- still up at 1.0s, 2.5s and 4.0s, and only gone by 6.5s.
--
-- So both are 2s now, which is what "hide it when I stop moving" actually
-- means. The cost is that a thumbnail you stopped to read also goes after 2s;
-- raise idle_seek in script-opts/osc_idle_hide.conf to buy that time back
-- without touching this file.
local opts = {
    idle        = 2,     -- seconds of a stationary mouse before the OSC goes
    idle_seek   = 2,     -- ...and the same while down on the seek bar
    seek_zone   = 0.88,  -- same strip seek-thumbnail.lua watches
    cursor_idle = 1,     -- ...and before the mouse cursor itself goes
}
options.read_options(opts, "osc_idle_hide")

local JITTER = 4      -- px; below this a "move" is just sensor noise (same
                      -- floor mouse-progress.lua uses)

local last_x, last_y = nil, nil
local hidden = false
local timer  = nil

-- whatever mpv.conf asked for, so movement restores that rather than a guess
local CURSOR_NORMAL = mp.get_property("cursor-autohide") or "1000"

local function show()
    if not hidden then return end
    -- back to normal behaviour: the OSC decides for itself again
    mp.commandv("script-message", "osc-visibility", "auto", "no-osd")
    hidden = false

    -- The movement that got us here reached the OSC while it was still in
    -- "never", so it was ignored, and switching back to "auto" does not re-show
    -- it for a pointer that is already sitting still. Replay the position as a
    -- fresh event once the mode has landed. Measured: without this the controls
    -- stay hidden until you leave the bottom edge and come back.
    -- Offset by a pixel: mpv drops a mouse event that lands on the coordinates
    -- the pointer is already at, so replaying the exact position is a no-op.
    -- Staying on the same row keeps it inside the OSC's trigger zone.
    if last_x and last_y then
        local y  = math.floor(last_y)
        local x  = math.floor(last_x)
        local dx = x > 0 and -1 or 1
        mp.add_timeout(0.05, function() mp.commandv("mouse", x + dx, y) end)
    end
end

local function hide()
    if not hidden then
        mp.commandv("script-message", "osc-visibility", "never", "no-osd")
        hidden = true
        -- seek-thumbnail.lua draws its preview as a separate overlay, which
        -- would otherwise be left floating above a controller that is no
        -- longer there. Let it drop the thumbnail at the same moment.
        mp.commandv("script-message", "osc-idle-hidden")
    end
end

-- ---- the cursor, on its own clock ------------------------------------------

local cursor_timer  = nil
local cursor_hidden = false

local function cursor_show()
    if cursor_timer then cursor_timer:kill(); cursor_timer = nil end
    if not cursor_hidden then return end
    mp.set_property("cursor-autohide", CURSOR_NORMAL)
    cursor_hidden = false
end

local function cursor_hide()
    cursor_timer = nil
    if cursor_hidden then return end
    mp.set_property("cursor-autohide", "always")
    cursor_hidden = true
end

timer = mp.add_timeout(opts.idle, hide)
timer:kill()

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos then return end

    -- pointer left the window: let the OSC hide on its own terms, and never
    -- leave the cursor forced off for whatever it moved onto next
    if pos.hover == false then
        timer:kill()
        cursor_show()
        show()
        last_x, last_y = nil, nil
        return
    end

    if last_x and math.abs(pos.x - last_x) < JITTER
              and math.abs(pos.y - last_y) < JITTER then
        return                      -- not a real move, keep the countdown running
    end
    last_x, last_y = pos.x, pos.y

    -- cursor first: show() replays a mouse event, and that event can only
    -- re-light the pointer once cursor-autohide is off 'always' again
    cursor_show()
    cursor_timer = mp.add_timeout(opts.cursor_idle, cursor_hide)

    show()
    timer:kill()                    -- restart the countdown from this movement
    local _, h = mp.get_osd_size()
    timer.timeout = (h and h > 0 and pos.y >= h * opts.seek_zone)
                    and opts.idle_seek or opts.idle
    timer:resume()
end)
