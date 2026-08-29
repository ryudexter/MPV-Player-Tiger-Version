-- Vertical volume bar.
--
-- mpv's built-in OSD bar (--osd-bar-*) is horizontal only and has no
-- orientation option, so this draws its own bar as an ASS overlay.
-- The volume keys in input.conf use "no-osd" so the built-in horizontal
-- bar stays out of the way; the seek bar is untouched and still horizontal.
--
-- Sizes are fractions of the screen, not pixels, so the bar keeps its
-- proportions in fullscreen and on any display.
-- Tunable from mpv.conf, e.g.:
--   script-opts=vertical_volume-bar_h_frac=0.70

local options = require 'mp.options'

local opts = {
    bar_h_frac   = 0.70,   -- length, as a fraction of screen height
    bar_w_frac   = 0.020,  -- thickness, also relative to screen height
    margin_frac  = 0.022,  -- gap from the right edge, fraction of width
    label_frac   = 0.030,  -- % label text size, fraction of screen height
    timeout      = 1.2,    -- seconds on screen
    -- ASS alpha is inverted vs mpv's #AARRGGBB: 0 = opaque, 255 = invisible.
    -- 143 (0x8F) ~= 44% opaque, matching the seek bar.
    alpha        = 143,
    track_alpha  = 208,
    -- bar colour as RRGGBB (ASS wants it byte-reversed, handled below)
    color        = "50DC82",
}
options.read_options(opts, "vertical_volume")

-- ASS colours are &HBBGGRR&, the reverse of the usual RRGGBB
local function ass_colour(rgb)
    return "&H" .. rgb:sub(5,6) .. rgb:sub(3,4) .. rgb:sub(1,2) .. "&"
end

local overlay = mp.create_osd_overlay("ass-events")
local timer   = nil
local ready   = false   -- suppress the observer's initial fire at startup

local function hide()
    overlay.data = ""
    overlay:update()
end

local function rect(x1, y1, x2, y2)
    return string.format("m %d %d l %d %d l %d %d l %d %d",
                         x1, y1, x2, y1, x2, y2, x1, y2)
end

local function draw()
    local vol  = mp.get_property_number("volume")
    local vmax = mp.get_property_number("volume-max") or 100
    if not vol then return end

    local w, h = mp.get_osd_size()
    if not w or not h or w == 0 or h == 0 then return end
    overlay.res_x, overlay.res_y = w, h

    local bar_h = math.floor(h * opts.bar_h_frac)
    local bar_w = math.floor(h * opts.bar_w_frac)

    local x2 = math.floor(w - w * opts.margin_frac)
    local x1 = x2 - bar_w
    local y1 = math.floor((h - bar_h) / 2)
    local y2 = y1 + bar_h

    local frac   = math.max(0, math.min(1, vol / vmax))
    local fill_y = y2 - math.floor((y2 - y1) * frac)

    local C  = ass_colour(opts.color)
    local a  = string.format("&H%02X&", opts.alpha)
    local ta = string.format("&H%02X&", opts.track_alpha)

    local p = {}
    p[#p+1] = string.format(
        "{\\an7\\pos(0,0)\\bord2\\3c" .. C .. "\\3a%s\\1c" .. C .. "\\1a%s\\p1}%s{\\p0}",
        a, ta, rect(x1, y1, x2, y2))
    if fill_y < y2 then
        p[#p+1] = string.format(
            "{\\an7\\pos(0,0)\\bord0\\1c" .. C .. "\\1a%s\\p1}%s{\\p0}",
            a, rect(x1, fill_y, x2, y2))
    end
    -- tick at 100%, so it's obvious the top of the bar is volume-max, not 100
    if vmax > 100 then
        local ty = y2 - math.floor((y2 - y1) * (100 / vmax))
        p[#p+1] = string.format(
            "{\\an7\\pos(0,0)\\bord0\\1c" .. C .. "\\1a%s\\p1}%s{\\p0}",
            a, rect(x1 - math.floor(bar_w/3), ty - 1, x1 - 1, ty + 1))
    end
    p[#p+1] = string.format(
        "{\\an2\\pos(%d,%d)\\fs%d\\bord1\\3c&H000000&\\3a%s\\1c" .. C .. "\\1a%s}%d%%",
        (x1 + x2) / 2, y1 - 6, math.floor(h * opts.label_frac), a, a, math.floor(vol + 0.5))

    overlay.data = table.concat(p, "\n")
    overlay:update()

    if timer then timer:kill() end
    timer = mp.add_timeout(opts.timeout, hide)
end

mp.observe_property("volume", "number", function() if ready then draw() end end)
mp.register_event("file-loaded", function() ready = true end)
