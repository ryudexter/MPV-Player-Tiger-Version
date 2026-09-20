-- Shuffle mode: toggle random playback order for the current playlist.
--
-- While ON:
--   * finishing a video jumps to a random one instead of the next in order
--   * the "next" key (x) also picks at random
--   * the "back" key (z) walks the SHUFFLE HISTORY - the video you actually
--     watched before this one, not the one sitting before it in playlist
--     order (which is what plain playlist-prev would give, and is almost
--     never the file you just came from once the order is random)
--   * after going back, x walks forward through that same history again, and
--     only picks a fresh random file once you are at the front of it - the
--     back/forward model a browser uses
--   * a video will not repeat until every other one has been played
-- Turning it OFF restores normal sequential order.
--
-- keep-open is forced to "always" while this is enabled, and put back when it
-- is switched off. "always" pauses at the end of EVERY file, and that pause is
-- what raises the eof-reached this script picks the next video from.
--
-- ⚠️ It has to be "always", not "yes". "yes" holds only at the LAST playlist
-- entry (measured 2026-09-20), so every other file still auto-advanced in
-- playlist order and a shuffled 8-clip folder really played 0..7 before its
-- first random jump. With "always" the order is a true permutation: measured
-- 0,3,1,5,4,7,6,2 then 3,0,7,6,1,5,2,4, no repeat across the boundary.
--
-- ⚠️ "always" is also what keeps this script working under the global
-- loop-playlist=inf in mpv.conf. That loop and a keep-open pause compete for
-- the same instant - the end of the last entry - and whichever holds mpv there
-- first decides who chooses the next video. "yes" lost that race and shuffle
-- silently degraded to sequential play (measured 0..7,0..7); "always" wins it,
-- because it stops mpv at the end of every file, long before the playlist can
-- run out. So loop-playlist is left alone here: it simply never comes up while
-- shuffle is on, and it is fully in charge again the moment shuffle is off.

local enabled    = false
local saved_keep = nil

-- The cycle. Rather than a "already played" set, shuffle mode deals a random
-- PERMUTATION of the playlist and walks it: that is what makes "everything
-- plays once before anything repeats" true by construction.
--   queue    - filenames still to come this cycle, in the order they will play
--   consumed - filenames already dealt this cycle, so the queue can be rebuilt
--              (playlist grew or shrank) without replaying them
local queue    = {}
local consumed = {}

-- Browser-style history of what shuffle actually played, oldest first.
-- Each entry is { filename = <playlist filename>, index = <1-based index> }.
-- hpos points at the entry that is playing now, so hpos > 1 means there is
-- something to go back to and hpos < #history means there is something to go
-- forward to. Session-only: it starts empty every time shuffle is switched on.
local history = {}
local hpos    = 0
-- Set while this script is the one changing files, so the file-loaded hook can
-- tell its own jumps (already recorded) from a file that arrived some other way.
local navigating = false

math.randomseed(os.time() + math.floor((os.clock() * 100000) % 100000))

local function playlist()
    return mp.get_property_native("playlist") or {}
end

local function current_index()
    for i, e in ipairs(playlist()) do
        if e.current then return i end
    end
    return nil
end

local function current_filename()
    local i = current_index()
    local e = i and playlist()[i]
    return e and e.filename or nil
end

-- The entry for whatever is playing right now, or nil if nothing is.
local function current_entry()
    local i = current_index()
    if not i then return nil end
    local e = playlist()[i]
    if not e then return nil end
    return { filename = e.filename, index = i }
end

-- Record the current file as a new step forward: anything that was ahead of us
-- in the history is dropped, exactly like opening a new page after going back.
local function push_current()
    local entry = current_entry()
    if not entry then return end
    for i = #history, hpos + 1, -1 do history[i] = nil end
    history[#history + 1] = entry
    hpos = #history
end

-- Playlists can be reordered or appended to while we hold an entry, so match on
-- filename first and only fall back to the index we saw at the time.
local function resolve(entry)
    local pl = playlist()
    for i, e in ipairs(pl) do
        if e.filename == entry.filename then return i end
    end
    if entry.index and pl[entry.index] then return entry.index end
    return nil
end

local function index_of(filename)
    for i, e in ipairs(playlist()) do
        if e.filename == filename then return i end
    end
    return nil
end

local function shuffled(list)
    local t = {}
    for i, v in ipairs(list) do t[i] = v end
    for i = #t, 2, -1 do                       -- Fisher-Yates
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

-- (Re)fill the queue with every playlist file not yet dealt this cycle.
-- Called on a fresh cycle and whenever the playlist itself changes.
local function refill()
    local names = {}
    for _, e in ipairs(playlist()) do
        if not consumed[e.filename] then names[#names + 1] = e.filename end
    end
    queue = shuffled(names)
end

-- How many videos of breathing space to enforce across a cycle boundary. Each
-- cycle is a permutation, so on its own nothing repeats within a cycle - but the
-- last video of one cycle could still be the second of the next, which reads as
-- a repeat even though it is not. Scaled to the folder: a 3-file folder cannot
-- afford any spacing, a large one can.
local function spread_size()
    return math.min(3, math.floor(#playlist() / 3))
end

-- The last n filenames this session actually played.
local function recent_files(n)
    local t = {}
    for i = hpos, math.max(1, hpos - n + 1), -1 do
        local e = history[i]
        if e then t[e.filename] = true end
    end
    local cur = current_filename()
    if cur then t[cur] = true end
    return t
end

-- Keep just-played videos out of the front of a fresh cycle by swapping them
-- with a later slot. Best-effort: a small folder may leave nowhere to put them.
local function spread_front(recent, k)
    if k < 1 or #queue <= k then return end
    for i = 1, k do
        if recent[queue[i]] then
            for _ = 1, 12 do
                local j = math.random(k + 1, #queue)
                if not recent[queue[j]] then
                    queue[i], queue[j] = queue[j], queue[i]
                    break
                end
            end
        end
    end
end

-- Start a new cycle. `playing` is treated as already dealt when the cycle starts
-- WITH it on screen (switching shuffle on); at a cycle boundary it is nil, so the
-- video playing then is still owed to you later in the new cycle.
local function new_cycle(playing)
    consumed = {}
    if playing then consumed[playing] = true end
    local k = spread_size()
    local recent = recent_files(k)
    refill()
    spread_front(recent, k)
end

-- The next playlist index this cycle owes us, dealing a new cycle when the
-- current one runs out. nil only when there is genuinely nothing else to play.
local function take_next()
    local pl = playlist()
    if #pl <= 1 then return nil end
    local cur = current_filename()

    for round = 1, 2 do                        -- at most one refill
        while #queue > 0 do
            local name = table.remove(queue, 1)
            consumed[name] = true
            local idx = index_of(name)
            if not idx then
                -- gone from the playlist: nothing to play, just drop it
            elseif name ~= cur then
                return idx
            elseif #queue > 0 then
                -- it is the file already on screen. DEFER it rather than drop
                -- it, or the cycle would quietly be one video short.
                consumed[name] = nil
                table.insert(queue, math.random(2, #queue + 1), name)
            end
        end
        if round == 1 then
            new_cycle(nil)
            mp.osd_message("Shuffle: all played, starting over", 2)
        end
    end
    return nil
end

local function jump_to_index(idx)
    navigating = true
    mp.commandv("write-watch-later-config")      -- keep the outgoing position
    mp.commandv("playlist-play-index", idx - 1)  -- property is 0-based
    mp.set_property_bool("pause", false)
end

-- x: forward through the history if we have gone back, otherwise a new random.
-- Returns true if it actually moved, so the eof handler can tell "nothing else
-- to play" from a normal advance. opts.quiet suppresses the OSD for that case,
-- which is a keypress message, not something to flash at the end of every lap.
local function go_forward(opts)
    if hpos > 0 and hpos < #history then
        local idx = resolve(history[hpos + 1])
        if idx then
            hpos = hpos + 1
            history[hpos].index = idx
            jump_to_index(idx)
            return true
        end
        -- that file is gone from the playlist: drop the stale tail and shuffle on
        for i = #history, hpos + 1, -1 do history[i] = nil end
    end

    local idx = take_next()
    if not idx then
        if not (opts and opts.quiet) then
            mp.osd_message("Shuffle: nothing else in the playlist", 2)
        end
        return false
    end
    local pl = playlist()
    for i = #history, hpos + 1, -1 do history[i] = nil end
    history[#history + 1] = { filename = pl[idx] and pl[idx].filename, index = idx }
    hpos = #history
    jump_to_index(idx)
    return true
end

-- z: back to the video that actually played before this one.
local function go_back()
    if hpos <= 1 then
        mp.osd_message("Shuffle: no earlier video this session", 2)
        return
    end
    local idx = resolve(history[hpos - 1])
    if not idx then
        table.remove(history, hpos - 1)     -- gone from the playlist, skip it
        hpos = hpos - 1
        return go_back()
    end
    hpos = hpos - 1
    history[hpos].index = idx
    jump_to_index(idx)
end

-- Files opened while shuffle is running join the cycle they arrived in, and
-- removed ones drop out of it, without replaying anything already dealt.
local function on_playlist_change()
    if enabled then refill() end
end

-- End of a file. Normally this deals the next random video; if there is
-- nothing to deal - a one-video folder, or every other entry has vanished -
-- restart this one instead. loop-playlist=inf would have done exactly that,
-- but keep-open=always stops mpv at the end of the file before the playlist
-- can run out, so this script owns the case now. Without it, a folder holding
-- a single video would sit paused on its last frame with shuffle on.
local function on_eof(_, reached)
    if not (enabled and reached) then return end
    if not go_forward({ quiet = true }) then
        mp.commandv("seek", 0, "absolute", "exact")
        mp.set_property_bool("pause", false)
    end
end

local function toggle()
    enabled = not enabled
    if enabled then
        saved_keep = mp.get_property("keep-open")
        mp.set_property("keep-open", "always")
        mp.observe_property("eof-reached", "bool", on_eof)
        -- wrapped, so mpv's own key-event argument cannot arrive as opts
        mp.add_forced_key_binding("x", "shuffle-next", function() go_forward() end)
        mp.add_forced_key_binding("z", "shuffle-prev", go_back)
        history = {}
        hpos    = 0
        navigating = false
        new_cycle(current_filename())      -- this cycle owes us everything else
        mp.observe_property("playlist-count", "number", on_playlist_change)
        push_current()                     -- the file playing now is history[1]
        mp.osd_message("Shuffle: ON", 2)
    else
        if saved_keep then mp.set_property("keep-open", saved_keep) end
        -- Switching off in the instant a file is paused on its last frame would
        -- otherwise leave it there: restoring keep-open does not retroactively
        -- advance a player that has already stopped. Hand it on the way out,
        -- through playlist-next so the restored loop-playlist decides whether
        -- the end of the folder wraps.
        if mp.get_property_bool("eof-reached") then
            mp.commandv("playlist-next")
            mp.set_property_bool("pause", false)
        end
        mp.unobserve_property(on_eof)
        mp.unobserve_property(on_playlist_change)
        mp.remove_key_binding("shuffle-next")
        mp.remove_key_binding("shuffle-prev")
        mp.osd_message("Shuffle: OFF", 2)
    end
    mp.msg.info("shuffle " .. (enabled and "ON" or "OFF"))
end

mp.add_key_binding(nil, "toggle-shuffle", toggle)
mp.register_event("file-loaded", function()
    if not enabled then return end
    if navigating then
        navigating = false                 -- our own jump, already in history
    else
        push_current()                     -- arrived some other way, record it
    end
end)
