-- One sound level for everything, remembered across launches.
--
-- mpv's watch-later saves `volume` and `mute` per FILE by default, so every
-- video ended up with its own level. That is wrong twice over: turning a quiet
-- film up meant every other film stayed where it was, and once replaygain
-- landed in mpv.conf the two compounded - a file already boosted by hand got
-- normalised on top and came out too loud.
--
-- mpv.conf now removes volume and mute from watch-later-options, which stops
-- the per-file part. This script supplies the other half: a single level, saved
-- once and restored at startup, so the volume keys mean "louder from now on"
-- rather than "louder for this one video".
--
-- Writes are debounced, because holding a volume key fires the property
-- observer on every step and there is no reason to touch the disk that often.

local utils = require 'mp.utils'

local PATH  = mp.command_native({"expand-path", "~~state/sound-state.json"})
local DELAY = 1     -- seconds of quiet before the level is written

local save_timer = nil
local ready      = false

local function restore()
    local f = io.open(PATH, "r")
    if not f then return end                 -- first run: nothing saved yet
    local raw = f:read("*a")
    f:close()
    local st = utils.parse_json(raw or "")
    if type(st) ~= "table" then
        mp.msg.warn("ignoring unreadable " .. PATH)
        return
    end
    -- guard the range: a corrupt file must not push volume past volume-max
    if type(st.volume) == "number" then
        local max = mp.get_property_number("volume-max") or 100
        mp.set_property_number("volume", math.max(0, math.min(st.volume, max)))
    end
    if type(st.mute) == "boolean" then
        mp.set_property_bool("mute", st.mute)
    end
    mp.msg.verbose(string.format("restored volume=%s mute=%s",
        tostring(st.volume), tostring(st.mute)))
end

local function save()
    save_timer = nil
    local st = {
        volume = mp.get_property_number("volume"),
        mute   = mp.get_property_bool("mute"),
    }
    if st.volume == nil then return end
    local f = io.open(PATH, "w")
    if not f then
        mp.msg.error("could not write " .. PATH)
        return
    end
    f:write(utils.format_json(st))
    f:close()
end

local function schedule()
    if not ready then return end             -- ignore the observers' first fire
    if save_timer then save_timer:kill() end
    save_timer = mp.add_timeout(DELAY, save)
end

restore()
mp.observe_property("volume", "number", schedule)
mp.observe_property("mute", "native", schedule)
ready = true

-- a level changed inside the last DELAY seconds would otherwise be lost
mp.register_event("shutdown", function()
    if save_timer then save_timer:kill(); save() end
end)
