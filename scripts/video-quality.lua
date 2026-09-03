-- Sharper picture for animation, via the Anime4K shaders.
--
-- WHAT THIS DOES NOT DO: it never touches your video files. Shaders are a live
-- effect - the GPU redraws each frame on its way to the screen, the way a
-- filter on a camera preview works. The file on disk is opened read-only and
-- stays byte-for-byte identical. Switch this off and the picture is instantly
-- back to exactly what it was.
--
-- Auto rule: a file whose path contains one of the names listed in
-- script-opts/video-quality.conf gets the shaders; everything else does not.
-- Live action is left alone ON PURPOSE. mpv's own `high-quality` profile
-- (already on in mpv.conf) is doing the right thing there, and anime shaders
-- on real footage make skin look waxy and add halos around edges.
--
-- The key is bound in input.conf (nothing is baked in here) and cycles:
--     auto  ->  always on  ->  off  ->  auto
--
-- Measured on this machine (M3 Max, 3456x2168 fullscreen output): zero dropped
-- and zero delayed frames with these shaders, even at 4x playback speed, so
-- there is no "light" preset - there is nothing to save.

local msg     = require "mp.msg"
local options = require "mp.options"

local o = {
    -- Semicolon-separated. Matched as plain text anywhere in the file's full
    -- path, ignoring case, so a folder name on its own is enough. Add a show
    -- here when a new animated series joins the library.
    animation_paths = "Solo Leveling;Attack on Titan;One Punch Man;Invincible;Avatar Aang;Anime",
}
options.read_options(o, "video-quality")

-- Anime4K v4.0.1 "Mode A (HQ)", the preset upstream recommends for 1080p anime
-- that is slightly soft: it restores the line art, then upscales it. The order
-- of this list matters - each shader feeds the next.
local SHADERS = {
    "Anime4K_Clamp_Highlights.glsl",
    "Anime4K_Restore_CNN_VL.glsl",
    "Anime4K_Upscale_CNN_x2_VL.glsl",
    "Anime4K_AutoDownscalePre_x2.glsl",
    "Anime4K_AutoDownscalePre_x4.glsl",
    "Anime4K_Upscale_CNN_x2_M.glsl",
}

local dir = mp.command_native({"expand-path", "~~/shaders"})

local paths = {}
for i, name in ipairs(SHADERS) do paths[i] = dir .. "/" .. name end
local shader_list = table.concat(paths, ":")   -- mpv separates this list with ':'

-- If the shader files ever go missing (a bad checkout, a half-done revert),
-- say so in the log once and stay out of the way rather than making mpv
-- complain about a missing file on every single video.
local available = true
for _, p in ipairs(paths) do
    local f = io.open(p, "r")
    if f then f:close() else
        available = false
        msg.warn("shader missing, sharper picture disabled: " .. p)
        break
    end
end

local MODES = { "auto", "on", "off" }
local mode  = "auto"

local function is_animation(path)
    if not path then return false end
    local lower = path:lower()
    for name in string.gmatch(o.animation_paths, "([^;]+)") do
        name = name:match("^%s*(.-)%s*$")               -- trim stray spaces
        -- plain=true: these are folder names, not patterns, so a '-' or '('
        -- in a show's name must not be read as pattern syntax
        if name ~= "" and lower:find(name:lower(), 1, true) then return true end
    end
    return false
end

local function wanted()
    if not available or mode == "off" then return false end
    if mode == "on" then return true end
    return is_animation(mp.get_property("path"))
end

local function apply()
    local on = wanted()
    if on then
        mp.set_property("glsl-shaders", shader_list)
    else
        -- NOT set_property(""): that leaves the list holding one EMPTY path
        -- ([""] rather than []), i.e. mpv still carries a bogus entry around.
        -- 'clr' is the only thing that actually empties the list. Measured.
        mp.commandv("change-list", "glsl-shaders", "clr", "")
    end
    return on
end

local function describe(on)
    if not available then return "Sharper picture: shader files are missing" end
    if mode == "auto" then
        return on and "Sharper picture: on (animation)"
                   or "Sharper picture: off (not animation)"
    elseif mode == "on" then
        return "Sharper picture: always on"
    end
    return "Sharper picture: off"
end

local function cycle()
    local i = 1
    for n, m in ipairs(MODES) do if m == mode then i = n end end
    mode = MODES[(i % #MODES) + 1]
    mp.osd_message(describe(apply()), 2)
    msg.info("mode " .. mode)
end

-- Silent on load, deliberately: mpv says nothing when it picks a video track
-- either, and an OSD line on every single file would be noise. Only the key talks.
mp.register_event("file-loaded", function() apply() end)

mp.add_key_binding(nil, "cycle-video-quality", cycle)
