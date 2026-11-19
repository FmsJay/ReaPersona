-- @description ReaPersona: fit REAPER to your preferred look, workflow or favourite DAW (Pro Tools, Pro Tools Intro, Logic, GarageBand, Ableton Live, FL Studio, Cubase, Nuendo, Studio One, Bitwig, Cakewalk, Reason, Audacity, Audition, or stock REAPER); build your own personas from any of their parts, give each project its own, tweak and merge themes live, and import, export or sync your setup across computers
-- @author James (with Claude)
-- @version 5.42.0
-- @license GPL-3.0
-- @link https://github.com/FmsJay/ReaPersona
-- @about Each persona is a set of shortcuts (kept apart from your own), a theme, its feel (settings
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
  if not chunk then -- (missing or half-written: reinstalling fixes that)
    return reaper.MB("ReaPersona couldn't load ui/" .. f .. ".lua: " .. tostring(err) .. "\n\nReinstall it: Extensions > ReaPack > Browse packages, right-click ReaPersona > Reinstall.", "ReaPersona", 0)
  end
  local ok, why = xpcall(chunk, debug.traceback) -- (an error while a file runs gets a message too, not REAPER's raw one)
  if not ok then -- (a mistake in ReaPersona: reinstalling the same files wouldn't help. Install review round 2)
    if rawget(R, "core") then pcall(R.core.log, why) end -- (errors.log gets where it was)
    return reaper.MB("ReaPersona stopped with an error while opening (ui/" .. f .. ".lua): " .. tostring(why):match("^[^\n]*") ..
      "\n\nThe details are in errors.log, in ReaPersona's folder (Scripts/ReaPersona): send that file with your report, or look for an update.", "ReaPersona", 0)
  end
end
