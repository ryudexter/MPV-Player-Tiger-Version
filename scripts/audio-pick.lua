-- Play the English soundtrack by default, and step through the film's other
-- languages with l.
--
-- mpv's own --alang=en in mpv.conf does most of the defaulting, and it is the
-- better mechanism because it runs inside mpv's track selection - the right
-- track is chosen before the audio decoder is created, so nothing switches
-- mid-playback. This script exists for the two cases a language list cannot
-- reach, both measured 2026-09-03 on test files:
--
--   1. No language tag. A track titled "English AC3 5.1" with no tag at all
--      is invisible to --alang, so mpv fell back to the default-flagged
--      Turkish track. Same shape as the subtitle problem in subtitle-pick.lua,
--      where a bare "English.srt" carries no tag either.
--   2. Two English tracks, commentary first. With eng/eng/tur and the
--      director's commentary flagged default, --alang=en is satisfied by the
--      commentary and stops there. Measured: mpv selected "Director
--      Commentary" both with and without --alang.
--
-- The auto-pick is deliberately SILENT. mpv says nothing about which audio
-- track it chose, and this is meant to feel the same - the film just comes up
-- in English. l is the key that talks.

------------------------------------------------------------------------------
-- languages
------------------------------------------------------------------------------

-- ISO 639-2 to 639-1, so a "jpn" tag and a "ja" tag land in the same group.
-- Only a mapping table - an unlisted code still works, it just groups and
-- displays under its own tag.
local TO_2 = {
    eng = "en", tur = "tr", jpn = "ja", ger = "de", deu = "de", fre = "fr",
    fra = "fr", spa = "es", ita = "it", rus = "ru", kor = "ko", chi = "zh",
    zho = "zh", por = "pt", ara = "ar", hin = "hi", dut = "nl", nld = "nl",
    pol = "pl", swe = "sv", dan = "da", nor = "no", fin = "fi", gre = "el",
    ell = "el", heb = "he", tha = "th", vie = "vi", ind = "id", hun = "hu",
    cze = "cs", ces = "cs", rum = "ro", ron = "ro", ukr = "uk", per = "fa",
    fas = "fa", hrv = "hr", srp = "sr", bul = "bg", slo = "sk", slk = "sk",
    slv = "sl", cat = "ca", isl = "is", est = "et", lav = "lv", lit = "lt",
}

local NAME = {
    en = "English",   tr = "Turkish",    ja = "Japanese",  de = "German",
    fr = "French",    es = "Spanish",    it = "Italian",   ru = "Russian",
    ko = "Korean",    zh = "Chinese",    pt = "Portuguese", ar = "Arabic",
    hi = "Hindi",     nl = "Dutch",      pl = "Polish",    sv = "Swedish",
    da = "Danish",    no = "Norwegian",  fi = "Finnish",   el = "Greek",
    he = "Hebrew",    th = "Thai",       vi = "Vietnamese", id = "Indonesian",
    hu = "Hungarian", cs = "Czech",      ro = "Romanian",  uk = "Ukrainian",
    fa = "Persian",   hr = "Croatian",   sr = "Serbian",   bg = "Bulgarian",
    sk = "Slovak",    sl = "Slovenian",  ca = "Catalan",   is = "Icelandic",
    et = "Estonian",  lv = "Latvian",    lt = "Lithuanian",
}

-- Language words to look for in a track's TITLE, used only when the track has
-- no usable language tag. The Turkish spellings are matched as plain bytes
-- because Lua's :lower() folds ASCII only - "TURKCE" folds but "TÜRKÇE" keeps
-- its uppercase U-umlaut, so both byte spellings are listed. Same trick as
-- scripts/subtitle-pick.lua.
local WORDS = {
    { "en", { "english" } },
    { "tr", { "turk", "t\195\188rk", "t\195\156rk" } },
    { "ja", { "japan" } },
    { "de", { "german", "deutsch" } },
    { "fr", { "french", "fran\195\167ais", "francais" } },
    { "es", { "spanish", "espa\195\177ol", "espanol", "castellano" } },
    { "it", { "italian", "italiano" } },
    { "ru", { "russian" } },
    { "ko", { "korean" } },
    { "zh", { "chinese", "mandarin", "cantonese" } },
    { "pt", { "portuguese", "portugu\195\170s" } },
    { "ar", { "arabic" } },
    { "hi", { "hindi" } },
}

-- Tags that mean "nobody said" rather than a language: und = undetermined,
-- mis = uncoded, zxx = no linguistic content, plus the empty tag.
local NO_LANG = { und = true, unknown = true, mis = true, zxx = true, mul = true }

-- Which language a track is in, as a 2-letter key, or nil when there is no
-- way to tell.
--
-- The tag wins outright when there is one, and the title is read only when
-- there is not. This is the opposite weighting to subtitle-pick.lua, on
-- purpose: an external .srt usually has no tag and has to be identified by
-- name, while an embedded audio track nearly always carries a real tag - and
-- a title is the more easily misread of the two ("Commentary with the English
-- director" on a track tagged fre, say).
local function lang_key(t)
    local tag = (t.lang or ""):lower():gsub("[-_].*", "")
    if tag ~= "" and not NO_LANG[tag] then
        return TO_2[tag] or tag
    end
    local title = (t.title or ""):lower()
    for _, w in ipairs(WORDS) do
        for _, word in ipairs(w[2]) do
            if title:find(word, 1, true) then return w[1] end
        end
    end
    return nil
end

local function lang_name(key)
    return NAME[key] or key:upper()
end

------------------------------------------------------------------------------
-- picking the best track WITHIN one language
------------------------------------------------------------------------------

-- Only ever compares tracks of the same language - the language itself is
-- decided by the grouping below, never by this score.
local function score(t)
    local s = 0
    local title = (t.title or ""):lower()
    -- A commentary is in the film's language but is not the film's audio, and
    -- it is often the first track and flagged default. This is the whole
    -- reason the auto-pick cannot just be --alang=en.
    if title:find("comment", 1, true) then s = s - 100 end
    -- Audio description narrates the picture for blind viewers. Right
    -- language, wrong track, same as an SDH subtitle.
    if t["visual-impaired"] or title:find("descri", 1, true)
       or title:find("narrat", 1, true) then s = s - 100 end
    if title:find("karaoke", 1, true) or title:find("instrumental", 1, true) then
        s = s - 50
    end
    -- The main mix is usually the one with the most channels: a release with
    -- both carries 5.1 as the feature audio and stereo as the compatibility
    -- track. Capped so it can never outweigh a commentary penalty.
    local ch = t["demux-channel-count"] or 0
    if ch > 8 then ch = 8 end
    s = s + ch
    if t.default then s = s + 5 end
    return s
end

------------------------------------------------------------------------------
-- grouping the file's audio into one entry per language
------------------------------------------------------------------------------

-- Returns an ordered list of { key, name, track }, English first and then
-- every other language in the order it appears in the file.
--
-- A track with no identifiable language becomes its OWN entry, keyed by id, so
-- l can still reach it - a file whose tracks are all untagged would otherwise
-- collapse to a single group and leave the key dead.
local function groups()
    local tracks = {}
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "audio" then tracks[#tracks + 1] = t end
    end

    local by_key, order = {}, {}
    for _, t in ipairs(tracks) do
        local key = lang_key(t)
        local name
        if key then
            name = lang_name(key)
        else
            key  = "id:" .. tostring(t.id)     -- unidentifiable: its own group
            name = "Track " .. tostring(t.id)
        end
        local sc = score(t)
        if not by_key[key] then
            by_key[key] = { key = key, name = name, track = t, score = sc }
            order[#order + 1] = key
        elseif sc > by_key[key].score then
            by_key[key].track, by_key[key].score = t, sc
        end
    end

    -- English first, everything else in file order.
    local out = {}
    if by_key.en then out[#out + 1] = by_key.en end
    for _, key in ipairs(order) do
        if key ~= "en" then out[#out + 1] = by_key[key] end
    end

    -- One language but several tracks (two English mixes, or a mix plus a
    -- commentary): step through the tracks instead, so l is never a dead key.
    -- Same reasoning as subtitle-pick.lua falling back to plain on/off when
    -- the film has neither English nor Turkish subtitles.
    if #out == 1 and #tracks > 1 then
        out = {}
        for _, t in ipairs(tracks) do
            local key = lang_key(t)
            out[#out + 1] = {
                key   = "id:" .. tostring(t.id),
                name  = key and lang_name(key) or ("Track " .. tostring(t.id)),
                track = t,
            }
        end
    end

    return out, #tracks
end

------------------------------------------------------------------------------
-- the default: English, chosen before the decoder starts
------------------------------------------------------------------------------

-- on_preloaded runs after the file is open and the track list is known, but
-- BEFORE mpv selects tracks and creates decoders, so setting aid here is
-- indistinguishable from having asked for that track on the command line.
-- Doing it on file-loaded instead would work, but would tear down and rebuild
-- the audio chain a moment after playback had already started.
mp.add_hook("on_preloaded", 50, function()
    local g = groups()
    local eng
    for _, e in ipairs(g) do
        if e.key == "en" then eng = e end
    end
    if not eng then return end             -- no English in this file: leave it
    local cur = mp.get_property_number("current-tracks/audio/id")
    if cur ~= eng.track.id then
        mp.set_property_number("aid", eng.track.id)
    end
end)

------------------------------------------------------------------------------
-- l: step to the next language
------------------------------------------------------------------------------

local function describe(e)
    local title = e.track.title
    if title and title ~= "" and title:lower() ~= e.name:lower() then
        return e.name .. " - " .. title
    end
    return e.name
end

-- Which entry the track on screen belongs to, so the step is worked out from
-- WHAT IS PLAYING rather than from a counter. A counter would drift the moment
-- a track was chosen by hand with Alt+l or #, or the file changed.
local function position(g, cur)
    if not cur then return nil end
    for i, e in ipairs(g) do
        if e.track.id == cur then return i end
    end
    -- Playing a track that is not its language's representative - the English
    -- commentary, say. Step from the language it is in, so l moves on to the
    -- next language instead of jumping back to the top.
    for _, t in ipairs(mp.get_property_native("track-list") or {}) do
        if t.type == "audio" and t.id == cur then
            local key = lang_key(t)
            if key then
                for i, e in ipairs(g) do
                    if e.key == key then return i end
                end
            end
        end
    end
    return nil
end

local function cycle()
    local g, n = groups()

    if n == 0 then
        mp.osd_message("This file has no audio", 2)
        return
    end
    if #g < 2 then
        mp.osd_message("Only one audio track" ..
            (g[1] and (": " .. describe(g[1])) or ""), 2)
        return
    end

    local cur  = mp.get_property_number("current-tracks/audio/id")
    local pos  = position(g, cur)
    local nxt  = g[((pos or 0) % #g) + 1]
    local then_ = g[((pos or 0) + 1) % #g + 1]

    mp.set_property_number("aid", nxt.track.id)
    mp.osd_message(string.format("Audio: %s   (l again for %s)",
        describe(nxt), then_.name), 2.5)
end

mp.add_key_binding(nil, "audio-cycle", cycle)
