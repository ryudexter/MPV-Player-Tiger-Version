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
-- c steps through every English and then every Turkish track the film actually
-- has, and then switches off. A film with one of each is English, Turkish, off;
-- one with two English tracks is both of them, then off. Alt+c opens mpv's own
-- searchable track list for anything else.
--
-- It used to offer only the BEST track per language, which broke on a release
-- that ships two of one language. Attack on Titan carries "Signs & Songs" and
-- "Full Subtitles", both embedded and both tagged eng: c landed on the signs
-- track, which titles on-screen text and songs but not a word of the dialogue,
-- and pressing c again went straight to off rather than to the track that
-- actually works. Both halves of that are fixed here - the scoring sinks a
-- signs-only track below a full one, and the cycle now walks all of them.

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
--
-- BOTH ISO 639 spellings are listed, because a prefix test on the two-letter
-- code does not reach the three-letter one for every language. English is
-- lucky - "eng" starts with "en" - but Turkish is "tur", which does not start
-- with "tr", so a Subs/ folder holding "tur.srt" scored as no language at all
-- and c walked straight past it. Found 2026-09-10 on Project Hail Mary, whose
-- 35 subtitle files include exactly that name.
--
-- The Turkish words are matched as plain bytes and Lua's :lower() only folds
-- ASCII, so "TURKCE" folds to "turkce" but "TÜRKÇE" keeps its uppercase Ü -
-- hence both byte spellings of the ü. "turk" is the stem of Turkish, Turkce
-- and Turkiye alike, so one entry covers the lot.
local WANTED = {
    { codes = { "en" },        name = "English", score = 1000,
      words = { "english" } },
    { codes = { "tr", "tur" }, name = "Turkish", score =  500,
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
    -- the external file's name without its path or extension, which is both
    -- the tie-breaker further down and, for a file called nothing but a
    -- language code, the only language signal there is
    local base  = fn and fn:gsub(".*/", ""):gsub("%.[^.]*$", "") or nil
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
        -- mpv only reads a language out of a name shaped "<stem>.<code>.srt",
        -- so "SDH.eng.HI.srt" arrives tagged eng but a file called plainly
        -- "tur.srt" arrives with no tag at all. Comparing the whole stem to
        -- the code catches those. It has to be an EXACT match, not a
        -- substring: "tur" inside a title like "Return" or "Saturday" would
        -- otherwise make an English subtitle Turkish.
        local by_tag = false
        for _, c in ipairs(w.codes) do
            if lang:match("^" .. c) then by_tag = true end
            if base and base:lower() == c then by_tag = true end
        end
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
    -- "Signs & Songs" tracks caption on-screen text and song lyrics and leave
    -- the dialogue alone - the same kind of partial track as a forced one, and
    -- just as wrong to land on by default. Two releases here ship one:
    -- Attack on Titan's is embedded beside "Full Subtitles" and scored
    -- IDENTICALLY (1050 each: same language, both embedded, neither flagged),
    -- so the tie broke on track order and the signs track won - subtitles on,
    -- nothing on screen while people talk. Solo Leveling has the same shape,
    -- "English Signs" embedded against the full dialogue in a sidecar .srt,
    -- where the embedded track's +50 made it win by 25.
    -- -50 clears both of those. Word-bounded so a title like "Designs" or a
    -- film called "Songbird" cannot trip it.
    if text:match("%f[%a]signs?%f[%A]") or text:match("%f[%a]songs?%f[%A]") then
        s = s - 50
    end
    if t.default then s = s + 5 end
    return s, band
end

-- How many tracks of ONE language c will walk before moving on to the next.
-- Only a guard against a pathological release: with the belongs() filter below
-- the real counts in this library are 1 or 2 (measured over all 458 videos:
-- 202 files have no English track, 191 have one, 53 have two, and the twelve
-- Solo Leveling season-1 episodes see thirteen only because mpv loads every
-- .srt in the folder - twelve of those are other episodes and belongs() drops
-- them). Anything past the cap is still reachable with Alt+c.
local MAX_PER_LANG = 5

-- Is this track this file's, or another episode's? An embedded track is by
-- definition; an external one only if its name matches the video's.
--
-- It matters because mpv.conf sets sub-auto=all, so opening one episode loads
-- every subtitle in the folder. Solo Leveling's season 1 folder holds 12 videos
-- and 12 sidecar .srt files whose names all contain "English" (from
-- "[English Dub]"), so on language alone one episode offers thirteen English
-- tracks and twelve of them are the wrong episode's dialogue.
--
-- Only used to FILTER, never to reject outright: a Subs/ folder full of bare
-- language names ("English.srt", "tur.srt" - Project Hail Mary ships 35 of
-- them) matches no stem at all, and those are the only subtitles that release
-- has. So the filter applies when it leaves something, and stands down when it
-- would leave nothing.
local function belongs(t, stem)
    local fn = t["external-filename"]
    if not fn then return true end
    local base = fn:gsub(".*/", ""):gsub("%.[^.]*$", "")
    return base == stem or (stem ~= "" and base:find(stem, 1, true) ~= nil)
end

-- Every track c will step through, in order: all the English ones best first,
-- then all the Turkish ones, then (in cycle()) off. Also returns the best track
-- overall, for a release that has neither language, and the total track count.
local function cycle_tracks()
    local stem = video_stem()
    local bands, overall, overall_s = {}, nil, nil
    local n = 0
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "sub" then
            n = n + 1
            local sc, band = score(t, stem)
            if band then
                bands[band] = bands[band] or {}
                table.insert(bands[band],
                    { track = t, score = sc, own = belongs(t, stem) })
            end
            if not overall_s or sc > overall_s then overall, overall_s = t, sc end
        end
    end
    local ordered = {}
    for i, w in ipairs(WANTED) do
        local list = bands[i]
        if list then
            local own = {}
            for _, e in ipairs(list) do
                if e.own then own[#own + 1] = e end
            end
            if #own > 0 then list = own end
            -- best first; ties break on track order so the walk is stable and
            -- always matches the order the file lists them in
            table.sort(list, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                return a.track.id < b.track.id
            end)
            for k = 1, math.min(#list, MAX_PER_LANG) do
                ordered[#ordered + 1] = { track = list[k].track, name = w.name }
            end
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

-- What the OSD promises the next press will give. Naming the language is the
-- useful thing when the next step changes language, but useless when it does
-- not - "c again for English" while English is already on screen says nothing
-- about which of the two English tracks is coming - so name the track instead.
local function next_hint(after, cur_name, n)
    if not after then
        return n > 1 and "c again to switch off" or nil
    end
    if after.name == cur_name then
        return "c again for " .. label(after.track)
    end
    return "c again for " .. after.name
end

-- c steps through every English track, then every Turkish one, then switches
-- off. A film with one of each is English, Turkish, off; one with two English
-- tracks gives both before off.
--
-- The step is worked out from WHAT IS SELECTED, never from a counter, so it
-- still behaves after v, after choosing something by hand with Alt+c, or after
-- moving to another file - a counter would drift out of step with the screen.
local function cycle()
    local ordered, overall, n = cycle_tracks()

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

    show(step.track, step.name, next_hint(ordered[nxt + 1], step.name, n))
end

-- Used by scripts/subtitle-fetch.lua after a download: the best track outright,
-- no cycling, and it must never switch subtitles off - they have just been
-- asked for.
local function select_best()
    local ordered, overall, n = cycle_tracks()
    local first = ordered[1]
    if first then
        show(first.track, first.name, next_hint(ordered[2], first.name, n))
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
