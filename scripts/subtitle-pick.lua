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
-- c steps through the languages the film actually has and then switches off:
-- English, Turkish, off. A film with only one of them is just on, off. Alt+c
-- opens mpv's own searchable track list for anything else.

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

-- Wanted languages, best first. Turkish is here because a Turkish subtitle is
-- perfectly readable when no English one exists; scripts/subtitle-fetch.lua
-- downloads both for the same reason. mpv reports language tags as either a
-- bare code or a locale ("en", "en-US", "tr-TR"), so these match on the front.
-- The Turkish words are matched as plain bytes and Lua's :lower() only folds
-- ASCII, so "TURKCE" folds to "turkce" but "TÜRKÇE" keeps its uppercase Ü -
-- hence both byte spellings of the ü. "turk" is the stem of Turkish, Turkce
-- and Turkiye alike, so one entry covers the lot.
local WANTED = {
    { code = "en", name = "English", score = 1000, words = { "english" } },
    { code = "tr", name = "Turkish", score =  500,
      words = { "turk", "t\195\188rk", "t\195\156rk" } },
}

-- Higher is better, and the language band dominates - see the loop below.
--
-- The stem bonus is what stops this picking the wrong episode. Solo Leveling's
-- season folder holds 12 videos and 12 .srt files together, and every one of
-- those names contains "English" - from "[English Dub]" - so on the language
-- signal alone all twelve tie and episode 1's subtitles win no matter which
-- episode is playing. Verified 2026-09-01: 24 of the filenames match /english/i.
-- The bonus is smaller than a language band on purpose, so it settles ties
-- inside one language without ever reaching across to another.
local function score(t, stem)
    local s = 0
    local lang  = (t.lang or ""):lower()
    local fn    = t["external-filename"]
    local text  = ((t.title or "") .. " " .. (fn or "")):lower()
    -- Language decides first, everything else only sorts within a language.
    -- English is preferred and Turkish is the fallback, and the two bands are
    -- 500 apart - wider than every other signal here added together - so no
    -- amount of being embedded, default or well-named can lift a Turkish track
    -- above an English one, or vice versa.
    --
    -- The tag and the name are treated as one signal with a small bonus for
    -- agreeing, rather than 100 each. It has to work that way round because
    -- the commonest English subtitle in this library, a bare "English.srt" in
    -- a Subs/ folder, has NO language tag at all - name-only English must
    -- still outrank a Turkish track that has both.
    local band                        -- which WANTED entry this track is
    for i, w in ipairs(WANTED) do
        local by_tag  = lang:match("^" .. w.code)
        local by_name = false
        for _, word in ipairs(w.words) do
            if text:find(word, 1, true) then by_name = true end
        end
        if by_tag or by_name then
            s = s + w.score
            if by_tag and by_name then s = s + 25 end
            band = i
            break                     -- first match wins: WANTED is ordered
        end
    end
    if not fn then
        s = s + 50            -- embedded: belongs to this file by definition
    else
        local base = fn:gsub(".*/", ""):gsub("%.[^.]*$", "")
        if base == stem then s = s + 50
        elseif stem ~= "" and base:find(stem, 1, true) then s = s + 40 end
    end
    -- SDH/hearing-impaired tracks caption sound effects and speaker names, so
    -- they are a poor default even though the language is right
    if t["hearing-impaired"] or text:match("sdh") or text:match("%f[%a]hi%f[%A]") then
        s = s - 60
    end
    -- forced tracks only translate the odd foreign line, not the dialogue
    if t.forced or text:match("forced") then s = s - 40 end
    if t.default then s = s + 5 end
    return s, band
end

-- The best track for each wanted language, in preference order, plus the best
-- track overall. A film usually offers one of these languages, sometimes both,
-- occasionally neither (a German-only release), and c has to behave sensibly
-- in all three cases.
local function best_tracks()
    local stem = video_stem()
    local per_band, overall, overall_s = {}, nil, nil
    local n = 0
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "sub" then
            n = n + 1
            local sc, band = score(t, stem)
            if band and (not per_band[band] or sc > per_band[band].score) then
                per_band[band] = { track = t, score = sc }
            end
            if not overall_s or sc > overall_s then overall, overall_s = t, sc end
        end
    end
    local ordered = {}
    for i, w in ipairs(WANTED) do
        if per_band[i] then
            ordered[#ordered + 1] = { track = per_band[i].track, name = w.name }
        end
    end
    return ordered, overall, n
end

local function show(track, name, note)
    mp.set_property_number("sid", track.id)
    mp.set_property_bool("sub-visibility", true)
    mp.osd_message(string.format("Subtitles: %s%s%s",
        name and (name .. " - ") or "", label(track),
        note and ("   (" .. note .. ")") or ""), 2.5)
end

local function off()
    mp.set_property("sid", "no")
    mp.osd_message("Subtitles off", 1.5)
end

-- c steps through the languages this film actually has, then switches off:
-- English, Turkish, off. A film with only one of them is simply on, off.
--
-- The step is worked out from WHAT IS SELECTED, never from a counter, so it
-- still behaves after v, after choosing something by hand with Alt+c, or after
-- moving to another file - a counter would drift out of step with the screen.
local function cycle()
    local ordered, overall, n = best_tracks()

    local cur = mp.get_property_number("current-tracks/sub/id")
    local on  = mp.get_property_bool("sub-visibility") and cur ~= nil

    -- Neither English nor Turkish: fall back to plain on/off at the best track
    -- there is, so a German-only release is not left with a dead key.
    if #ordered == 0 then
        if on then off()
        elseif overall then show(overall, nil, n > 1 and "Alt+c to choose" or nil)
        else mp.osd_message("No subtitles for this file", 2) end
        return
    end

    local pos
    if on then
        for i, e in ipairs(ordered) do
            if e.track.id == cur then pos = i end
        end
    end

    -- Not on, or on something outside the cycle (a track picked with Alt+c):
    -- start again at the preferred language.
    local nxt = (pos and pos + 1) or 1
    local step = ordered[nxt]
    if not step then off(); return end

    local after = ordered[nxt + 1]
    show(step.track, step.name,
         after and ("c again for " .. after.name)
                or (n > 1 and "c again to switch off" or nil))
end

-- Used by scripts/subtitle-fetch.lua after a download: the best track outright,
-- no cycling, and it must never switch subtitles off - they have just been
-- asked for.
local function select_best()
    local ordered, overall, n = best_tracks()
    local first = ordered[1]
    if first then
        show(first.track, first.name, ordered[2] and ("c again for " .. ordered[2].name) or nil)
    elseif overall then
        show(overall, nil, n > 1 and "Alt+c to choose" or nil)
    else
        mp.osd_message("No subtitles for this file", 2)
    end
end

mp.add_key_binding(nil, "subs-toggle", cycle)

-- Used by scripts/subtitle-fetch.lua once a downloaded subtitle has been
-- rescanned into the track list.
mp.register_script_message("subs-pick-best", select_best)
