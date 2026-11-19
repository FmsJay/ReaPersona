-- @description ReaPersona: fit REAPER to your preferred look, workflow or favourite DAW (Pro Tools, Pro Tools Intro, Logic, GarageBand, Ableton Live, FL Studio, Cubase, Nuendo, Studio One, Bitwig, Cakewalk, Reason, Audacity, Audition, or stock REAPER); build your own personas from blocks, give each project its own, tweak and merge themes live, and import, export or sync your setup across computers
-- @author James (with Claude)
-- @version 5.39.0
-- @license GPL-3.0
-- @link https://github.com/FmsJay/ReaPersona
-- @about Each persona is a shortcut layer (REAPER's Main alt-N sections, switched by its override actions), a theme, its feel (settings
--   such as snap, the transport and mixer layout, where the Media Explorer docks), its mouse (wheel scrolling and zooming, and drags
--   such as Pro Tools' Smart Tool),
--   a toolbar and MIDI editor keys. Keys a persona doesn't define fall through to your own shortcuts; whatever a persona changes is put
--   back when you switch, so My REAPER is always your own setup. Base REAPER is REAPER as it ships. Your own personas are made on the tabs (5.27):
--   a DAW's keys, its mouse or one part of its feel, REAPER settings groups, a theme, colours, a project part, each chosen where it lives; and a project
--   can keep its own persona. Your personas and settings go to your other computers as a file or through a shared folder. Every DAW key is that DAW's default from its maker's documentation (styles.json). Adjust changes the theme in use
--   live; Build one makes a theme from several. Needs ReaImGui, SWS and js_ReaScriptAPI.
--   The look follows StudioSync's when it's installed (Settings picks one otherwise).
if not reaper.ImGui_GetBuiltinPath then return reaper.MB("This needs ReaImGui: Extensions > ReaPack > Browse packages > ReaImGui.", "ReaPersona", 0) end
if not reaper.CF_EnumerateActions then return reaper.MB("This needs the SWS extension (sws-extension.org).", "ReaPersona", 0) end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
-- The window's code is in ui/, one file per area (5.39: the one file had reached Lua's 200 locals a function may have). They all
-- run with R, a table of the window's names (the page, the persona being made, the helpers): a name one file sets, the others see.
-- What isn't in R comes from Lua's own globals (__index). Order matters only for what runs as each file loads.
local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
local R = setmetatable({ here = here }, { __index = _G })
for _, f in ipairs({ "base", "personas", "settings", "theme_tools", "check", "home", "editing", "shortcuts", "mouse", "layout", "project", "main" }) do
  local chunk, err = loadfile(here .. "/ui/" .. f .. ".lua", "t", R)
  if not chunk then return reaper.MB("ReaPersona couldn't load ui/" .. f .. ".lua: " .. tostring(err) .. "\n\nReinstall it (ReaPack > Synchronize packages).", "ReaPersona", 0) end
  if chunk() == false then return end -- (a file that stops the window: the screen-reader menu's own run)
end
