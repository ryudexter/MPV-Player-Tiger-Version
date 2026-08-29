-- Hide the OSC when the mouse sits still, even while it is over the OSC itself.
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

-- uosc replaces mpv's built-in OSC, and mpv.conf turns the built-in one off
-- when uosc is installed. This script exists only to manage that built-in
-- controller, so with it gone there is nothing here to do and staying active
-- would only fight uosc's own equivalent. Stand down.
if not mp.get_property_bool("osc") then return end

local IDLE   = 2      -- seconds of a stationary mouse before the OSC goes
-- ...but longer while the pointer is down on the seek bar, because since
-- seek-thumbnail.lua that is where you hold still ON PURPOSE, to look at the
-- preview frame. At a flat 2s the thumbnail vanished exactly when you stopped
-- to read it. Still bounded, so a mouse parked there and abandoned - the
-- original complaint this script exists for - clears on its own.
local IDLE_SEEK   = 6
local SEEK_ZONE   = 0.88   -- same strip seek-thumbnail.lua watches
local JITTER = 4      -- px; below this a "move" is just sensor noise (same
                      -- floor mouse-progress.lua uses)

local last_x, last_y = nil, nil
local hidden = false
local timer  = nil

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

timer = mp.add_timeout(IDLE, hide)
timer:kill()

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos then return end

    -- pointer left the window: let the OSC hide on its own terms
    if pos.hover == false then
        timer:kill()
        show()
        last_x, last_y = nil, nil
        return
    end

    if last_x and math.abs(pos.x - last_x) < JITTER
              and math.abs(pos.y - last_y) < JITTER then
        return                      -- not a real move, keep the countdown running
    end
    last_x, last_y = pos.x, pos.y

    show()
    timer:kill()                    -- restart the countdown from this movement
    local _, h = mp.get_osd_size()
    timer.timeout = (h and h > 0 and pos.y >= h * SEEK_ZONE) and IDLE_SEEK or IDLE
    timer:resume()
end)
