-- Turn subtitles on at the right track in one press, bound to c.
--
-- mpv.conf now searches Subs/ and loads every subtitle it finds there, because
-- releases park them in a subfolder under names like "English.srt" that match
-- nothing about the video. That is the only way to see them at all - but one
-- film in this library ships 35 of them, and c used to be
-- "set sub-visibility yes; cycle sub", stepping one track per press. Reaching
-- English meant tapping it thirty times, and switching them off again meant
-- tapping through the rest.
--
-- mpv cannot pick for us: a language tag only appears when the filename
-- carries a code. Measured 2026-09-01 on Project Hail Mary - "Brazilian.por.srt"
-- came back as --slang=por, while plain "English.srt" got no language at all,
-- so slang=eng would never have found it. Hence the scoring below, which reads
-- the filename as well as the tag.
--
-- c is now a toggle: on at the best English track, off again. Alt+c opens
-- mpv's own searchable track list for anything else.

local function label(t)
    if t.title and t.title ~= "" then return t.title end
    local fn = t["external-filename"]
    if fn then return (fn:gsub(".*/", "")) end
    return "track " .. tostring(t.id) .. (t.lang and (" (" .. t.lang .. ")") or "")
end

-- The stem of the file being played, so a subtitle sitting beside it can be
-- told apart from one belonging to a different episode in the same folder.
local function video_stem()
    local path = mp.get_property("path") or ""
    return (path:gsub(".*/", ""):gsub("%.[^.]*$", ""))
end

-- Higher is better. Both signals count, so a file tagged eng AND named english
-- outranks one with only a tag.
--
-- The stem bonus is what stops this picking the wrong episode. Solo Leveling's
-- season folder holds 12 videos and 12 .srt files together, and every one of
-- those names contains "English" - from "[English Dub]" - so on the language
-- signal alone all twelve tie and episode 1's subtitles win no matter which
-- episode is playing. Verified 2026-09-01: 24 of the filenames match /english/i.
-- The bonus is smaller than a language signal on purpose, so it settles ties
-- without letting an untagged neighbour outrank a file actually named English.
local function score(t, stem)
    local s = 0
    local lang  = (t.lang or ""):lower()
    local fn    = t["external-filename"]
    local text  = ((t.title or "") .. " " .. (fn or "")):lower()
    if lang:match("^en")     then s = s + 100 end
    if text:match("english") then s = s + 100 end
    if not fn then
        s = s + 50            -- embedded: belongs to this file by definition
    else
        local base = fn:gsub(".*/", ""):gsub("%.[^.]*$", "")
        if base == stem then s = s + 50
        elseif stem ~= "" and base:find(stem, 1, true) then s = s + 40 end
    end
    -- SDH/hearing-impaired tracks caption sound effects and speaker names, so
    -- they are a poor default even though they are perfectly good English
    if t["hearing-impaired"] or text:match("sdh") or text:match("%f[%a]hi%f[%A]") then
        s = s - 60
    end
    -- forced tracks only translate the odd foreign line, not the dialogue
    if t.forced or text:match("forced") then s = s - 40 end
    if t.default then s = s + 5 end
    return s
end

-- Turn subtitles on at the best-scoring track, whatever is selected now.
-- Split out of toggle() so scripts/subtitle-fetch.lua can reuse it after a
-- download: the scoring is the whole point of this script and belongs in one
-- place, and unlike toggle() this must never switch subtitles OFF - you have
-- just asked for them.
local function select_best()
    local best, best_score
    local stem = video_stem()
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "sub" then
            local s = score(t, stem)
            if not best_score or s > best_score then best, best_score = t, s end
        end
    end
    if not best then
        mp.osd_message("No subtitles for this file", 2)
        return
    end

    mp.set_property_number("sid", best.id)
    mp.set_property_bool("sub-visibility", true)
    local n = 0
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "sub" then n = n + 1 end
    end
    mp.osd_message(string.format("Subtitles: %s%s", label(best),
        n > 1 and string.format("   (%d available - Alt+c to choose)", n) or ""), 2.5)
end

local function toggle()
    local on = mp.get_property_bool("sub-visibility")
              and (mp.get_property("current-tracks/sub/id") ~= nil)
    if on then
        mp.set_property("sid", "no")
        mp.osd_message("Subtitles off", 1.5)
        return
    end
    select_best()
end

mp.add_key_binding(nil, "subs-toggle", toggle)

-- Used by scripts/subtitle-fetch.lua once a downloaded subtitle has been
-- rescanned into the track list.
mp.register_script_message("subs-pick-best", select_best)
