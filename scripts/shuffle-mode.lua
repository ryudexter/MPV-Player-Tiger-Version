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
-- Two options are forced while this is enabled, and put back when it is
-- switched off:
--
--   keep-open = "yes"    mpv pauses at the end of the last playlist entry
--       instead of terminating, and that pause is what raises the eof-reached
--       this script picks the next file from.
--       ⚠️ Measured 2026-09-20: "yes" holds only at the LAST entry - every
--       other file still auto-advances in playlist order, so a shuffled
--       8-clip folder actually plays 0..7 and only then jumps at random
--       (observed 0,1,...,7,5,6,7,2,3,4). "always" is the choice that pauses
--       at the end of EVERY file; forcing it instead gives a true permutation
--       (observed 0,7,2,4,1,3,6,5 then 4,1,6,2,3,5,0,7). Left at "yes" for
--       now - changing it changes how shuffle feels, not just what it says.
--
--   loop-playlist = "no"  mpv.conf sets inf, so an ordinary folder cycles back
--       to its first video instead of quitting the session. That wrap is taken
--       at the end of the last entry too, and it is served BEFORE the eof hook
--       above, which leaves this script never called at all: with inf left on,
--       shuffle degrades to plain sequential play (measured 0..7,0..7).
--       Nothing is lost by switching it off here - shuffle deals a fresh cycle
--       at the end, so the playlist never runs out while it is on.

local enabled    = false
local saved_keep = nil
local saved_loop = nil

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
local function go_forward()
    if hpos > 0 and hpos < #history then
        local idx = resolve(history[hpos + 1])
        if idx then
            hpos = hpos + 1
            history[hpos].index = idx
            jump_to_index(idx)
            return
        end
        -- that file is gone from the playlist: drop the stale tail and shuffle on
        for i = #history, hpos + 1, -1 do history[i] = nil end
    end

    local idx = take_next()
    if not idx then
        mp.osd_message("Shuffle: nothing else in the playlist", 2)
        return
    end
    local pl = playlist()
    for i = #history, hpos + 1, -1 do history[i] = nil end
    history[#history + 1] = { filename = pl[idx] and pl[idx].filename, index = idx }
    hpos = #history
    jump_to_index(idx)
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

local function on_eof(_, reached)
    if enabled and reached then go_forward() end
end

local function toggle()
    enabled = not enabled
    if enabled then
        saved_keep = mp.get_property("keep-open")
        mp.set_property("keep-open", "yes")
        saved_loop = mp.get_property("loop-playlist")
        mp.set_property("loop-playlist", "no")
        mp.observe_property("eof-reached", "bool", on_eof)
        mp.add_forced_key_binding("x", "shuffle-next", go_forward)
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
        if saved_loop then mp.set_property("loop-playlist", saved_loop) end
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
