--[[
  * skiptosilence.lua v.2022-02-27
  *
  * AUTHORS: detuur, microraptor
  * License: MIT
  * link: https://github.com/detuur/mpv-scripts
  * upstream sha256: 60ee8c05526c7b4a451e0fa4d12272cfc48f9d748047aa9ba2586871a744686d
  *
  * LOCAL PATCH (2026-09-03): upstream has no bail-out. Its video filter is
  * `nullsink,color=...`, an ENDLESS black source, so if the file contains no
  * silence below the threshold mpv never reaches EOF -- it runs at 100x on a
  * black screen forever with the filters still attached. Measured: time-pos
  * 2497s on a 60s file. Everything marked LOCAL below exists to end that.
  * 
  * This script skips to the next silence in the file. The
  * intended use for this is to skip until the end of an
  * opening sequence, at which point there's often a short
  * period of silence.
  *
  * The default keybind is F3. You can change this by adding
  * the following line to your input.conf:
  *     KEY script-binding skip-to-silence
  * 
  * In order to tweak the script parameters, you can place the
  * text below, between the template markers, in a new file at
  * script-opts/skiptosilence.conf in mpv's user folder. The
  * parameters will be automatically loaded on start.
  *
****************** TEMPLATE FOR skiptosilence.conf ******************
# NOTE: upstream's template wrote these as `key = value`. mpv's option parser
# does not accept the spaces and silently ignores every such line - caught
# 2026-09-03 by the config load check. Written `key=value` here.
#
# Maximum amount of noise to trigger, in terms of dB.
# The default is -30 (yes, negative). -60 is very sensitive,
# -10 is more tolerant to noise.
quietness=-30

# Minimum duration of silence to trigger.
duration=0.1

# The fast-forwarded audio can sound jarring. Set to 'yes'
# to mute it while skipping.
mutewhileskipping=no
************************** END OF TEMPLATE **************************
--]]

local opts = {
    quietness=-30,
    duration=0.1,
    mutewhileskipping = false
}

local mp = require 'mp'
local msg = require 'mp.msg'
local options = require 'mp.options'

old_speed = 1
was_paused = false
was_muted = false

-- LOCAL: state for the bail-out.
local skipping = false      -- guards against re-entry and stale callbacks
local start_pos = nil       -- where you pressed the key, so a failed skip can undo
local watchdog = nil        -- wall-clock backstop for streams with no duration
local TIMEOUT = 30          -- seconds of REAL time; a 100x skip covers ~50min of
                            -- video in that, far more than any intro.

--[[
Dev note about the used filters:
- `silencedetect` is an audio filter that listens for silence and
  emits text output with details whenever silence is detected.
- `nullsink` interrupts the video stream requests to the decoder,
  which stops it from bogging down the fast-forward.
- `color` generates a blank image, which renders very quickly and is
  good for fast-forwarding.
- Filter documentation: https://ffmpeg.org/ffmpeg-filters.html
--]]

function doSkip()
    -- LOCAL: pressing the key mid-skip cancels it. That is the reflex you reach
    -- for when a skip is clearly overshooting, so make it the same key.
    if skipping then
        abortSkip("cancelled")
        return
    end
    skipping = true
    start_pos = mp.get_property_native("time-pos")

    -- Get video dimensions
    local width = mp.get_property_native("width");
    local height = mp.get_property_native("height")

    -- Create audio and video filters
    mp.command(
        "no-osd af add @skiptosilence:lavfi=[silencedetect=noise=" ..
        opts.quietness .. "dB:d=" .. opts.duration .. "]"
    )
    mp.command(
        "no-osd vf add @skiptosilence-blackout:lavfi=" ..
        "[nullsink,color=c=black:s=" .. width .. "x" .. height .. "]"
    )

    -- Triggers whenever the `silencedetect` filter emits output
    mp.observe_property("af-metadata/skiptosilence", "string", foundSilence)

    was_muted = mp.get_property_native("mute")
    if opts.mutewhileskipping then
        mp.set_property_bool("mute", true)
    end

    was_paused = mp.get_property_native("pause")
    mp.set_property_bool("pause", false)
    old_speed = mp.get_property_native("speed")
    mp.set_property("speed", 100)

    -- LOCAL: two independent bail-outs. The overrun check is the real one
    -- (duration is known for files); the timer covers streams where it is nil.
    mp.observe_property("time-pos", "native", checkOverrun)
    watchdog = mp.add_timeout(TIMEOUT, function() abortSkip("timed out") end)
end

-- LOCAL: undo everything doSkip changed. Split out of foundSilence so the
-- success and failure paths cannot drift apart.
function restoreState()
    skipping = false
    if watchdog then watchdog:kill(); watchdog = nil end
    mp.unobserve_property(checkOverrun)
    mp.unobserve_property(foundSilence)
    mp.set_property_bool("mute", was_muted)
    mp.set_property_bool("pause", was_paused)
    mp.set_property("speed", old_speed)
    mp.command("no-osd af remove @skiptosilence")
    mp.command("no-osd vf remove @skiptosilence-blackout")
end

-- LOCAL: the skip failed. Put the playhead back where it was -- landing 40
-- minutes deep because the mix was loud is worse than not skipping at all.
function abortSkip(reason)
    if not skipping then return end
    restoreState()
    if start_pos then mp.set_property_number("time-pos", start_pos) end
    msg.info("No silence found (" .. reason .. ")")
    mp.osd_message("No silence found (" .. reason .. ")")
end

-- LOCAL: the endless color source means time-pos sails past duration instead
-- of ending the file, so that overshoot is the signal that there is no silence.
function checkOverrun(_, pos)
    if not skipping or pos == nil then return end
    local dur = mp.get_property_native("duration")
    if dur and pos > dur - 0.5 then abortSkip("reached the end") end
end

function foundSilence(name, value)
    if value == "{}" or value == nil then
        return -- For some reason these are sometimes emitted. Ignore.
    end

    timecode = tonumber(string.match(value, "%d+%.?%d+"))
    time_pos = mp.get_property_native("time-pos")
    if timecode == nil or timecode < time_pos + 1 then
        return -- Ignore anything less than a second ahead.
    end

    restoreState()  -- LOCAL: was five inline statements; see restoreState above.

    -- Seeking to the exact moment even though we've already
    -- fast forwarded here allows the video decoder to skip
    -- the missed video. This prevents massive A-V lag.
    mp.set_property_number("time-pos", timecode)

    -- If we don't wait at least 50ms before messaging the user, we
    -- end up displaying an old value for time-pos.
    mp.add_timeout(0.05, skippedMessage)
end

function skippedMessage()
    msg.info("Skipped to silence at " .. mp.get_property_osd("time-pos"))
    mp.osd_message("Skipped to silence at " .. mp.get_property_osd("time-pos"))
end

-- LOCAL: a skip must never outlive its file. Without this, hitting the next
-- playlist entry mid-skip would leave speed at 100 on the new file.
mp.register_event("end-file", function() if skipping then restoreState() end end)

options.read_options(opts)

-- LOCAL: no default key. The binding lives in input.conf with all the others,
-- so there is one place to look. F3 stays available via script-binding.
mp.add_key_binding(nil, "skip-to-silence", doSkip)
