-- How fullscreen behaves, chosen automatically per display, and overridable
-- with p (bound in input.conf).
--
--   native-fs=yes  fullscreen gets its own Space, the usual macOS behaviour
--   native-fs=no   fullscreen just covers the desktop you are already on
--
-- Why both exist
-- --------------
-- Legacy fullscreen keeps a real window, and macOS strokes a window with a 1pt
-- 20%-white edge that lands on the screen border as a visible hairline
-- (measured 2026-08-27: (51,51,51) over the black letterbox). Native fullscreen
-- has no window to stroke, so the hairline is gone. That is why mpv.conf sets
-- native-fs=yes.
--
-- But native fullscreen builds a dedicated fullscreen *Space*, and macOS binds
-- a Space to one display ("Displays have separate Spaces" is on by default).
-- With a second screen attached, the fullscreen Space and the window's original
-- Space can sit on different displays, and f then shuttles between Spaces
-- instead of restoring the window where it was.
--
-- So: native on the built-in panel, legacy on anything external. A 1pt hairline
-- is invisible on a TV across the room; fullscreen that will not exit is not.
--
-- native-fs is only read when the window ENTERS fullscreen, and flipping it and
-- then toggling fullscreen from inside a native fullscreen Space killed mpv
-- outright (verified 2026-08-27). Every change here therefore goes:
--     leave fullscreen -> wait until it has really left -> flip -> re-enter.

local mp = require 'mp'

local SETTLE     = 0.35   -- margin after the window reports it left fullscreen
local switching  = false
local overridden = false  -- p was pressed: stop auto-managing until displays change
local seen       = nil    -- last display set, to spot real changes

-- Every display mpv reports is the built-in panel?
local function builtin_only()
    local names = mp.get_property_native("display-names")
    if not names or #names == 0 then return true end   -- unknown: assume built-in
    for _, n in ipairs(names) do
        if not tostring(n):find("Built%-in") then return false end
    end
    return true
end

local function label()
    if mp.get_property_bool("native-fs") then
        return "Fullscreen: separate Space"
    end
    return "Fullscreen: this desktop"
end

-- Set native-fs, rebuilding the window if we are fullscreen right now.
local function apply(target, announce)
    if mp.get_property_bool("native-fs") == target then return end

    if not mp.get_property_bool("fullscreen") then
        mp.set_property_bool("native-fs", target)
        if announce then mp.osd_message(label() .. "  (on next fullscreen)", 1.8) end
        return
    end

    if switching then return end
    switching = true
    mp.set_property_bool("fullscreen", false)

    local waited = 0
    local function once_out()
        if mp.get_property_bool("fullscreen") == false or waited > 4 then
            mp.add_timeout(SETTLE, function()
                mp.set_property_bool("native-fs", target)
                mp.add_timeout(SETTLE, function()
                    mp.set_property_bool("fullscreen", true)
                    mp.add_timeout(0.6, function()
                        switching = false
                        if announce then mp.osd_message(label(), 1.5) end
                    end)
                end)
            end)
        else
            waited = waited + 0.05
            mp.add_timeout(0.05, once_out)
        end
    end
    once_out()
end

-- p: flip by hand, and stop auto-managing until the displays change, so the
-- automatic rule cannot immediately undo what was just asked for.
mp.add_key_binding(nil, "toggle-fullscreen-mode", function()
    if switching then return end
    overridden = true
    apply(not mp.get_property_bool("native-fs"), true)
end)

-- Follow the display the window is on: plugging in, unplugging, or dragging the
-- window to another screen all land here.
mp.observe_property("display-names", "native", function()
    local names = mp.get_property_native("display-names") or {}
    local key = table.concat(names, "|")
    if key == seen then return end          -- same screens, nothing to decide
    local first = (seen == nil)
    seen = key
    overridden = false                      -- new screen context, resume auto
    apply(builtin_only(), not first)        -- silent on the very first call
end)
