-- @description ReaPersona: fit REAPER to your preferred look, workflow or favourite DAW (Pro Tools, Pro Tools Intro, Logic, GarageBand, Ableton Live, FL Studio, Cubase, Nuendo, Studio One, Bitwig, Cakewalk, Reason, Audacity, Audition, or stock REAPER); build your own personas from blocks, give each project its own, tweak and merge themes live, and import, export or sync your setup across computers
-- @author James (with Claude)
-- @version 5.36.0
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
local ImGui = require "imgui" "0.10"
local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
local core = dofile(here .. "/reapersona_core.lua")
local feedback = dofile(here .. "/reapersona_feedback.lua") -- (the Feedback button and its window, as StudioSync has them)
feedback.VERSION = (core.read(here .. "/ReaPersona.lua") or ""):match("@version%s+(%S+)") or "?"
local styles, SECTION, themes_dir = core.styles, core.SECTION, core.themes_dir
local res = reaper.GetResourcePath()

-- Shortcut lines per style layer, and MIDI editor keys bound to ReaPersona scripts. (Not by install_shortcuts.py's tag: REAPER rewrites the
-- file's comments when it saves it.)
local installed, midi_installed = {}, 0
do
  local layers, midi_cmds = {}, {}
  for _, st in ipairs(styles) do if (st.alt or 0) > 0 then layers[st.alt] = true end end
  for _, id in pairs(core.scripts.midi) do midi_cmds[id] = true end
  for line in (core.read(res .. "/reaper-kb.ini") or ""):gmatch("[^\n]+") do
    local cmd, sec = line:match("^KEY %d+ %d+ (%S+) (%d+)")
    sec = tonumber(sec)
    if sec == 32060 and midi_cmds[cmd] then midi_installed = midi_installed + 1
    elseif sec and layers[sec] then installed[sec] = (installed[sec] or 0) + 1 end
  end
end
if core.scripts_missing() > 0 then core.ensure_scripts() end -- (first run, or a new style: the one-key actions and MIDI key scripts)

local function run_script(rel)
  local p = res .. "/Scripts/" .. rel
  if not reaper.file_exists(p) then return false end
  local id = reaper.AddRemoveReaScript(true, 0, p, true)
  if id ~= 0 then reaper.Main_OnCommand(id, 0); return true end
end
local function theme_files()
  local t, i, have = {}, 0, {}
  reaper.EnumerateFiles(themes_dir, -1) -- (REAPER caches folder listings: themes just built or added show up)
  while true do
    local f = reaper.EnumerateFiles(themes_dir, i)
    if not f then break end
    if f:match("%.ReaperTheme$") or f:match("%.ReaperThemeZip$") then t[#t + 1] = f; have[f] = true end
    i = i + 1
  end
  for n = #t, 1, -1 do if have[t[n] .. "Zip"] then table.remove(t, n) end end -- (X.ReaperTheme next to X.ReaperThemeZip is REAPER's note of it)
  local new = core.recent_themes or {} -- (themes added this session first)
  table.sort(t, function(a, b) if (new[a] or false) ~= (new[b] or false) then return new[a] or false end return a:lower() < b:lower() end)
  return t
end

-- ---------------------------------------------------------------- the look: StudioSync's palettes (and its theme pick, if it has one)
local PALETTES = {
  Dark = { bg = 0x1A1C1F, card = 0x26292E, nav = 0x1F2124, text = 0xE6E8EB, muted = 0x8D939B, accent = 0x4C8DF6,
    green = 0x59CC73, yellow = 0xF2BF40, red = 0xE0605A },
  Light = { bg = 0xF2F3F5, card = 0xFFFFFF, nav = 0xE4E6EA, text = 0x1F2328, muted = 0x626A73, accent = 0x2F6FE0,
    green = 0x1C8A47, yellow = 0x9A6B00, red = 0xC8372F },
  Midnight = { bg = 0x0F1626, card = 0x1B2540, nav = 0x141D32, text = 0xE3E9F5, muted = 0x8A97B3, accent = 0x6C8CFF,
    green = 0x5AD08F, yellow = 0xF0C25A, red = 0xEE6B7A },
  Warm = { bg = 0x221D18, card = 0x312A23, nav = 0x29231D, text = 0xEFE6DA, muted = 0xA19383, accent = 0xE0954A,
    green = 0x8CC56A, yellow = 0xEDC05A, red = 0xE5705A },
}
local function mix(a, b, t) -- a towards b, each channel; no alpha
  local out = 0
  for s = 16, 0, -8 do
    local x, y = a >> s & 0xFF, b >> s & 0xFF
    out = out | math.floor(x + (y - x) * t + 0.5) << s
  end
  return out
end
local function solid(c) return c << 8 | 0xFF end
local function hex(s, fallback) local n = tonumber((s or ""):match("^#?(%x%x%x%x%x%x)$") or "", 16); return n or fallback end
local P, C = nil, {}
local COLS -- (filled by apply_look below)
local function apply_look() -- the palette from Settings > look (else StudioSync's), into P, C and the ImGui colours; live
  P = PALETTES[reaper.GetExtState(SECTION, "look")] or PALETTES[reaper.GetExtState("BandSync", "theme")] or PALETTES.Dark
  C.BG, C.CARD, C.CARD_HOVER, C.NAV, C.TEXT = solid(P.bg), solid(P.card), solid(mix(P.card, P.text, 0.05)), solid(P.nav), solid(P.text)
  C.MUTED, C.ACCENT, C.GREEN, C.YELLOW, C.RED = solid(P.muted), solid(P.accent), solid(P.green), solid(P.yellow), solid(P.red)
  C.FRAME, C.KEYCAP, C.BANNER = solid(mix(P.bg, P.text, 0.16)), solid(mix(P.card, P.text, 0.12)), solid(mix(P.card, P.yellow, 0.16))
  if COLS then COLS.fill() end
end
local function accent_of(st) return hex(st.accent, P.accent) end
local function t(x) return solid(mix(P.bg, P.text, x)) end
local function a(x) return solid(mix(P.bg, P.accent, x)) end

local function new_ctx() -- (keyboard navigation on: Tab, arrows, Enter, Esc)
  local c = ImGui.CreateContext("ReaPersona")
  ImGui.SetConfigVar(c, ImGui.ConfigVar_Flags, ImGui.GetConfigVar(c, ImGui.ConfigVar_Flags) | ImGui.ConfigFlags_NavEnableKeyboard)
  return c
end
local ctx = new_ctx()
local font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
local bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
COLS = { fill = function()
  for k = #COLS, 1, -1 do COLS[k] = nil end
  for _, c in ipairs({
  { ImGui.Col_WindowBg, C.BG }, { ImGui.Col_ChildBg, 0 }, { ImGui.Col_PopupBg, solid(mix(P.card, P.text, 0.03)) },
  { ImGui.Col_Text, C.TEXT }, { ImGui.Col_TextDisabled, C.MUTED }, { ImGui.Col_Border, t(0.28) }, -- (fields and buttons get a visible edge: 3:1 against the cards)
  { ImGui.Col_FrameBg, C.FRAME }, { ImGui.Col_FrameBgHovered, t(0.21) }, { ImGui.Col_FrameBgActive, t(0.26) },
  { ImGui.Col_Button, t(0.16) }, { ImGui.Col_ButtonHovered, t(0.24) }, { ImGui.Col_ButtonActive, C.ACCENT },
  { ImGui.Col_Header, a(0.2) }, { ImGui.Col_HeaderHovered, a(0.28) }, { ImGui.Col_HeaderActive, a(0.38) },
  { ImGui.Col_CheckMark, C.ACCENT }, { ImGui.Col_SliderGrab, C.ACCENT }, { ImGui.Col_SliderGrabActive, C.ACCENT },
  { ImGui.Col_Separator, t(0.12) }, { ImGui.Col_TitleBg, C.NAV }, { ImGui.Col_TitleBgActive, solid(mix(P.nav, P.text, 0.03)) },
  { ImGui.Col_TableHeaderBg, t(0.08) }, { ImGui.Col_TableRowBgAlt, solid(mix(P.card, P.text, 0.03)) }, { ImGui.Col_TableBorderLight, t(0.1) },
  { ImGui.Col_ScrollbarBg, 0 },
}) do COLS[#COLS + 1] = c end
end }
apply_look()
local VARS = {
  { ImGui.StyleVar_WindowPadding, 0, 0 }, { ImGui.StyleVar_FramePadding, 10, 6 }, { ImGui.StyleVar_ItemSpacing, 8, 8 },
  { ImGui.StyleVar_FrameRounding, 6 }, { ImGui.StyleVar_ChildRounding, 10 }, { ImGui.StyleVar_WindowRounding, 8 },
  { ImGui.StyleVar_GrabRounding, 6 }, { ImGui.StyleVar_PopupRounding, 6 }, { ImGui.StyleVar_ScrollbarRounding, 8 },
  { ImGui.StyleVar_ChildBorderSize, 0 }, { ImGui.StyleVar_FrameBorderSize, 1 }, { ImGui.StyleVar_CellPadding, 8, 5 },
}

local function on_colour(col) -- dark or white text, whichever reads better on col (WCAG contrast ratio)
  local function lin(c) c = c / 255; return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
  local L = 0.2126 * lin(col >> 16 & 255) + 0.7152 * lin(col >> 8 & 255) + 0.0722 * lin(col & 255)
  return (L + 0.05) / 0.0545 >= 1.05 / (L + 0.05) and 0x15171AFF or 0xFFFFFFFF -- (0x15171A's luminance is about 0.0045)
end
-- A rounded label: status at a glance.
local function pill(text, bg, fg)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = ImGui.CalcTextSize(ctx, text)
  ImGui.Dummy(ctx, w + 16, h + 6)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w + 16, y + h + 6, bg, (h + 6) / 2)
  ImGui.DrawList_AddText(dl, x + 8, y + 3, fg or on_colour(bg >> 8), text)
end
local IS_MAC = core.IS_MAC
local keyname = core.keyname -- (on a Mac REAPER's Ctrl is Cmd, Alt is Option and Win is Control: styles store Windows names)
local function keycap(text) -- a key, drawn like one
  text = keyname(text)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = ImGui.CalcTextSize(ctx, text)
  ImGui.Dummy(ctx, w + 12, h + 4)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w + 12, y + h + 4, C.KEYCAP, 4)
  ImGui.DrawList_AddText(dl, x + 6, y + 2, C.TEXT, text)
end
local UI = (tonumber(reaper.GetExtState(SECTION, "text size")) or 15) / 15 -- (Settings > text size)
local IND = 18 -- (what edits the persona sits a little to the right, so it reads as part of it. 5.28) (up here: the persona pages use it too, 5.36)
local function heading(text, size)
  ImGui.PushFont(ctx, bold, (size or 17) * UI)
  ImGui.Text(ctx, text)
  ImGui.PopFont(ctx)
end
local function muted(text) ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.MUTED); ImGui.TextWrapped(ctx, text); ImGui.PopStyleColor(ctx) end
-- A card: a rounded panel sized to what's in it. Returns true when its content should be drawn (then call card_end).
local function card(id)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.CARD)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 14)
  local open = ImGui.BeginChild(ctx, id, 0, 0, ImGui.ChildFlags_AutoResizeY | ImGui.ChildFlags_AlwaysUseWindowPadding, ImGui.WindowFlags_NoScrollbar)
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
  if open then ImGui.PushTextWrapPos(ctx, 0) end
  return open
end
local function card_end() ImGui.PopTextWrapPos(ctx); ImGui.EndChild(ctx); ImGui.Dummy(ctx, 0, 2) end
-- The button that does the main thing, in the style's own colour.
local function primary(label, col)
  col = col or P.accent
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, solid(col))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, solid(mix(col, 0xFFFFFF, 0.15)))
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, solid(mix(col, 0x000000, 0.15)))
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, on_colour(col))
  ImGui.PushFont(ctx, bold, 15 * UI)
  local clicked = ImGui.Button(ctx, label)
  ImGui.PopFont(ctx)
  ImGui.PopStyleColor(ctx, 4)
  return clicked
end

-- ---------------------------------------------------------------- theme adjustments (live)
local COLOURS = {
  { "col_arrangebg", "Arrange background" }, { "col_tr1_bg", "Track background (odd)" }, { "col_tr2_bg", "Track background (even)" },
  { "selcol_tr1_bg", "Selected track (odd)" }, { "selcol_tr2_bg", "Selected track (even)" }, { "col_tr1_itembgsel", "Selected item" },
  { "col_cursor", "Edit cursor" }, { "playcursor_color", "Play cursor" }, { "col_gridlines", "Grid lines" },
  { "col_seltrack", "Selected track control panel" }, { "col_main_bg2", "Window background" }, { "col_main_text2", "Text" },
  { "col_mi_bg", "MIDI editor background" }, { "col_mi_note", "MIDI note" } }
local changed, changed_on = {}, nil -- key -> native colour, what's been tweaked since the theme was loaded; and that theme
-- (declared here, before save_fork: it set a global of that name, so a theme on trial still went back after you saved it. Review, 5.9.3)
local trying, try_theme -- (a theme on trial: { name, back = the theme to go back to, ends = time }; set up with the setup helpers)
local function refresh() reaper.ThemeLayout_RefreshAll(); reaper.UpdateArrange(); reaper.TrackList_AdjustWindows(false) end
local function add_fork(st, name)
  local list = reaper.GetExtState(SECTION, "forks " .. st.id)
  if not ("|" .. list .. "|"):find("|" .. name .. "|", 1, true) then -- (once each)
    reaper.SetExtState(SECTION, "forks " .. st.id, (list ~= "" and (list .. "|") or "") .. name, true)
  end
  reaper.SetExtState(SECTION, "theme " .. st.id, name, true)
end
local function remove_fork(st, name) -- (a theme you added to a persona's versions, taken off the list; the file stays)
  local keep = {}
  for f in reaper.GetExtState(SECTION, "forks " .. st.id):gmatch("[^|]+") do if f ~= name then keep[#keep + 1] = f end end
  reaper.SetExtState(SECTION, "forks " .. st.id, table.concat(keep, "|"), true)
  if reaper.GetExtState(SECTION, "theme " .. st.id) == name then reaper.DeleteExtState(SECTION, "theme " .. st.id, true) end
end

-- Save what's been tweaked as a theme of its own (a local fork): a .ReaperTheme over the same images. A .ReaperTheme in use is copied with
-- your colours put in (its fonts and all kept); for a .ReaperThemeZip, every colour REAPER reports for it now (the theme's own, then yours)
-- is written out, from colour_keys.txt, and the zip named as its images. -> its file name, or nil + why
local function save_fork(st, current)
  local text
  if current:match("%.ReaperTheme$") then
    text = core.read(themes_dir .. current)
    if not text then return nil, "couldn't read " .. current end
    for key, col in pairs(changed) do
      if text:find("\n" .. key .. "=[^\r\n]*") then text = text:gsub("\n" .. key .. "=[^\r\n]*", "\n" .. key .. "=" .. col, 1)
      else text = text:gsub("%[color theme%]", "[color theme]\n" .. key .. "=" .. col, 1) end
    end
  else
    local lines = { "[color theme]" }
    for key in (core.read(here .. "/colour_keys.txt") or ""):gmatch("[^\r\n]+") do
      local col = changed[key] or reaper.GetThemeColor(key, 1)
      if col and col ~= -1 then lines[#lines + 1] = key .. "=" .. col end
    end
    lines[#lines + 1] = "[REAPER]"
    lines[#lines + 1] = "ui_img=" .. current
    text = table.concat(lines, "\n") .. "\n"
  end
  local base = current:gsub("%.ReaperThemeZip$", ""):gsub("%.ReaperTheme$", ""):gsub(" %(mine %d+%)$", "")
  local n = 1
  while reaper.file_exists(themes_dir .. base .. " (mine " .. n .. ").ReaperTheme") do n = n + 1 end
  local name = base .. " (mine " .. n .. ").ReaperTheme"
  if not core.write(themes_dir .. name, text) then return nil, "couldn't write " .. name end
  add_fork(st, name)
  changed = {}
  trying = nil
  reaper.OpenColorThemeFile(themes_dir .. name)
  return name
end

-- ---------------------------------------------------------------- pages
local images = {}
local function preview(st)
  local id = st.preset and st.base or st.id -- (a preset shows its style's picture)
  if images[id] == nil then
    local p = here .. "/previews/" .. id .. ".png"
    images[id] = reaper.file_exists(p) and ImGui.CreateImage(p) or false
    if images[id] then ImGui.Attach(ctx, images[id]) end
  end
  return images[id] or nil
end
local selected, filter, pfilter = reaper.GetExtState(SECTION, "style"), "", ""
local page = reaper.GetExtState(SECTION, "page") ~= "" and reaper.GetExtState(SECTION, "page") or "DAWs" -- (the page you were on)
local search_q, search_focus = "", false -- (search everything: top bar, Ctrl+K)
local MOD = (reaper.GetOS():find("^OSX") or reaper.GetOS():find("^mac")) and "Cmd" or "Ctrl" -- (what ImGui's Ctrl is called on this computer)
local function go(pg) -- (a screen reader with OSARA hears the page's name)
  page = pg; search_q = ""; reaper.SetExtState(SECTION, "page", pg, false)
  if reaper.osara_outputMessage then reaper.osara_outputMessage(pg == "Guide" and "How it works" or pg) end
end
local merge = { base = "Default_7.0.ReaperThemeZip", colours = "", graphics = "", parts = {}, fonts = false, msg = "" }
local PARTS = { "faders", "knobs", "meters", "transport", "buttons", "toolbar", "backgrounds" }
local bld -- (the persona being made: set up with the tabs' section; pages above it, Adjust say, reach it through this. 5.35)
local bld_load -- (starts the persona being made from one you have; set up with the tabs' section)
local in_persona, persona_row, bld_new, persona_keys_card, persona_theme_line, shortcuts_page, rpage, read_rpage -- (any tab: a block into the persona being made, and the "Use in my persona" buttons for one persona; 5.26)
local drop_report, install_theme_ui -- (what came in, and a one-click theme install: set up with the setup helpers)
local quit_check -- (when the install's quit should be over)
local removing, remove_finish -- (Settings > Remove ReaPersona: waiting for My REAPER's windows to be back, then the rest; set up with Setup)
local install_shortcuts -- (REAPER closes, the shortcuts and your synced setup go in, REAPER opens again: set up with Setup)
local ensure_new = false -- (a merged style needs its one-key action registered)
local check_msg, toast, toast_until = "", "", 0
local said -- (the last thing said: the screen-reader menu shows it in a message box)
local menu_mode = false -- (the screen-reader menu is open: results go in a message box, which the screen reader reads)
local function speak(text) if reaper.osara_outputMessage and not menu_mode then reaper.osara_outputMessage(tostring(text)) end end -- (OSARA reads it out)
local function say(text) toast, toast_until, said = tostring(text), reaper.time_precise() + 6 + 0.06 * #tostring(text), tostring(text); speak(text) end
local colours = assert(loadfile(here .. "/colours.lua"))(core) -- (Colours tab: StudioSync's colour system, 5.19)
colours.say = say

local function open_extra(x)
  local id = 0
  if x == "playtime" then -- (Helgobox's Playtime, found by its action's name: its id isn't fixed)
    for n = 0, 100000 do
      local cmd, name = reaper.CF_EnumerateActions(0, n, "")
      if not cmd or cmd <= 0 then break end
      local l = name:lower()
      if l:find("playtime") and (l:find("show") or l:find("open")) then id = cmd; break end
    end
    if id == 0 then reaper.MB("Playtime isn't installed: it comes with Helgobox (ReaPack: Helgoboss Projects).", "ReaPersona", 0) end
  elseif type(x) == "string" and x:match("%.lua$") then run_script(x)
  else id = core.cmd_id(x) end
  if id ~= 0 then reaper.Main_OnCommand(id, 0) end
end
local function in_use(st, alt) return core.current() == st and (st.alt or 0) == alt end
local function install_ext(key)
  local x = core.EXTENSIONS[key]
  local ok, why = core.install_extension(key)
  reaper.MB(ok and (x.name .. " is installed. Restart REAPER to load it (REAPER loads extensions when it starts).")
    or ("Couldn't install " .. x.name .. ": " .. tostring(why)), "ReaPersona", 0)
end
local last_style = reaper.GetExtState(SECTION, "last style") -- (the persona before the last switch: Undo switch goes back to it; kept, so
-- closing the window or the menu doesn't lose it. Review, 5.14)
if last_style == "" then last_style = nil end
local function use(st)
  local was = core.current()
  if was and was.id ~= st.id then last_style = was.id; reaper.SetExtState(SECTION, "last style", was.id, true) end
  -- (a theme on trial gives way to the persona's, but the one it was trying over is what this persona had: leaving My REAPER
  -- mid-trial kept the trial theme as My REAPER's own. Review, 5.9.3)
  if trying and trying.back then reaper.OpenColorThemeFile(themes_dir .. trying.back) end
  trying = nil
  local needs = core.needs_layer(st)
  core.use(st)
  if needs then -- (5.29: REAPER has 16 shortcut layers; a persona gets one the first time it's used here)
    if reaper.MB(st.name .. "'s shortcuts aren't installed on this computer yet: REAPER has only 16 shortcut layers, so ReaPersona gives them to the personas you use.\n\n" ..
        "Install them now? REAPER closes (it asks first if anything is unsaved) and opens again, about 10 seconds. Until then its look and layout are on, with your own keys.", "ReaPersona: " .. st.name, 4) == 6 then
      install_shortcuts(false, st.id, true)
    end
  end
  local setup = core.last_project_setup or {}
  local miss = {}
  for _, s in ipairs(core.starts_missing or {}) do miss[#miss + 1] = s[1] end
  say(st.name .. " in use" .. (#setup > 0 and (", and this project has its " .. table.concat(setup, ", ")) or "") .. ". Undo switch (top) puts " .. (was and was.name or "the last one") .. " back." ..
    (#miss > 0 and (" It starts " .. table.concat(miss, ", ") .. " with REAPER, not installed here: Get it on its page.") or ""))
  for _, key in ipairs(st.recommends or {}) do -- (offered once: no is remembered)
    local x = core.EXTENSIONS[key]
    if x and core.ext_here(key) and core.extension_state(key) == "missing" and reaper.GetExtState(SECTION, "declined " .. key) == "" then
      if reaper.MB(st.name .. " " .. x.feel .. ". " .. x.name .. " does that in REAPER: " .. x.why .. ".\n\nInstall it now? (REAPER needs a restart to load it.)", "ReaPersona: recommended for " .. st.name, 4) == 6 then
        install_ext(key)
      else reaper.SetExtState(SECTION, "declined " .. key, "1", true) end
    end
  end
  local rec = st.theme -- (its recommended look, when there's a download for it: offered once too)
  if rec and not reaper.file_exists(themes_dir .. rec) and core.can_install_theme(rec) and reaper.GetExtState(SECTION, "declined theme " .. st.id) == "" then
    local c = core.CATALOG[rec]
    if reaper.MB(st.name .. "'s recommended look is " .. rec:gsub("%.ReaperTheme%a*$", "") .. (c.by and (", by " .. c.by) or "") .. (c.note and (" (" .. c.note .. ")") or "") ..
        ".\n\nInstall it now? ReaPersona downloads it and takes it in, with its fonts and extras on your yes.", "ReaPersona: recommended for " .. st.name, 4) == 6 then
      install_theme_ui(rec, st, true)
    else reaper.SetExtState(SECTION, "declined theme " .. st.id, "1", true) end
  end
end

-- A workflow over the persona in use (5.16): picked here, on the Personas page, or from the screen-reader menu.
local function pick_workflow(id)
  local ok, why = core.set_workflow(id)
  if not ok then return say("Not changed: " .. tostring(why)) end
  local w, cur, setup = core.current_workflow(), core.current(), core.last_project_setup or {}
  say((w and (w.name .. " is on top of " .. cur.name) or ("No workflow: " .. cur.name .. " on its own")) ..
    (#setup > 0 and (", and this project has its " .. table.concat(setup, ", ")) or "") .. ".")
end
local function workflow_new_project(w) -- a new project set up by the workflow in use, over the persona in use
  if not core.fresh_project(0) then reaper.Main_OnCommand(41929, 0) end -- (a new tab, without the default template's tracks)
  local done = core.apply_project(core.layered(core.current()))
  say("A new project with " .. w.name .. (#done > 0 and (": " .. table.concat(done, ", ")) or "") .. ".")
end
local function workflow_keep_inputs(w)
  local n = core.keep_inputs(w.id)
  say("Kept the inputs of this project's " .. n .. " track" .. (n == 1 and "" or "s") .. ": new projects with " .. w.name .. " on this computer get them. Your other computers keep their own.")
end
local function workflow_row()
  local w = core.current_workflow()
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Workflow on top:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 230 * UI)
  if ImGui.BeginCombo(ctx, "##workflow", w and w.name or "None") then
    if ImGui.Selectable(ctx, "None: the persona on its own", not w) and w then pick_workflow("") end
    local mine = false
    for _, x in ipairs(core.workflow_list()) do
      if x.mine and not mine then ImGui.Separator(ctx); mine = true end
      local on = w and w.id == x.id
      if ImGui.Selectable(ctx, x.name .. "##wf" .. x.id, on) and not on then pick_workflow(x.id) end
      if x.tip then ImGui.SetItemTooltip(ctx, x.tip) end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "A kind of session over whichever persona is in use: its REAPER settings, and what a new, empty project gets (sample rate, starter tracks or a whole template). The persona keeps its keys, theme and layout. Your personas with a project part are listed too.")
  if w and w.project then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "New project with " .. w.name) then workflow_new_project(w) end
    ImGui.SetItemTooltip(ctx, "Opens a new project tab set up by " .. w.name .. " (a new project from REAPER's File menu or its key gets it too, while it's on).")
    if reaper.CountTracks(0) > 0 then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Keep these inputs##wf") then workflow_keep_inputs(w) end
      ImGui.SetItemTooltip(ctx, "Each computer's interface numbers its inputs its own way. Set the tracks' inputs here once, press this, and new projects with " .. w.name .. " get them on this computer.")
    end
  end
end

-- A star (5.27: favourites), drawn, so it doesn't depend on the font having one.
local function draw_star(dl, cx, cy, r, filled, col)
  local p = {}
  for i = 0, 9 do local a = -math.pi / 2 + i * math.pi / 5; local rr = i % 2 == 0 and r or r * 0.45; p[i] = { cx + rr * math.cos(a), cy + rr * math.sin(a) } end
  if filled then
    for i = 1, 9, 2 do ImGui.DrawList_PathLineTo(dl, p[i][1], p[i][2]) end
    ImGui.DrawList_PathFillConvex(dl, col)
    for i = 0, 8, 2 do local a, b = p[(i + 9) % 10], p[i + 1]; ImGui.DrawList_AddTriangleFilled(dl, p[i][1], p[i][2], a[1], a[2], b[1], b[2], col) end
  else
    for i = 0, 9 do ImGui.DrawList_PathLineTo(dl, p[i][1], p[i][2]) end
    ImGui.DrawList_PathStroke(dl, col, ImGui.DrawFlags_Closed, 1.5)
  end
end
-- One picture card in the grid: click shows it, double-click uses it; the star (top left) adds it to your favourites or takes it off.
local function style_card(st, w, sel, alt)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local iw = w - 16
  local ih = math.floor(iw * 0.56)
  local h = 8 + ih + 52
  local mx, my = ImGui.GetMousePos(ctx)
  local on_star = mx >= x + 10 and mx <= x + 38 and my >= y + 10 and my <= y + 38
  local fav = core.is_favourite(st.id)
  if ImGui.InvisibleButton(ctx, "card" .. st.id, w, h) then
    if on_star then core.set_favourite(st.id, not fav); say(st.name .. (fav and " is off your favourites." or " is in your favourites (Personas > Favourites)."))
    else selected = st.id end
  end
  local hov = ImGui.IsItemHovered(ctx)
  if hov and ImGui.IsMouseDoubleClicked(ctx, 0) then use(st) end
  ImGui.SetItemTooltip(ctx, (hov and on_star) and (fav and "Take it off your favourites" or "Add it to your favourites") or "Click to see it, double-click to use it. The star adds it to your favourites.")
  local col, picked, on = accent_of(st), st.id == sel.id, in_use(st, alt)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, hov and C.CARD_HOVER or C.CARD, 10)
  if picked then ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + w - 1, y + h - 1, solid(col), 10, 0, 2) end
  local img = preview(st)
  if img then
    local sw, sh = ImGui.Image_GetSize(img)
    local v1 = math.min(1, (ih / iw) / math.max(sh / math.max(sw, 1), 0.01)) -- (fill the width, crop from the top down)
    ImGui.DrawList_AddImageRounded(dl, img, x + 8, y + 8, x + 8 + iw, y + 8 + ih, 0, 0, 1, v1, 0xFFFFFFFF, 6)
  else
    ImGui.DrawList_AddRectFilled(dl, x + 8, y + 8, x + 8 + iw, y + 8 + ih, solid(mix(P.card, col, 0.35)), 6)
  end
  ImGui.DrawList_AddCircleFilled(dl, x + 16, y + 8 + ih + 17, 4.5, solid(col))
  ImGui.DrawList_AddTextEx(dl, bold, 15, x + 26, y + 8 + ih + 8, C.TEXT, st.short or st.name)
  local sub = st.preset and ("yours, on " .. (core.by_id(st.base) or { name = "" }).name) or st.kind == "theme" and "theme, with your keys"
    or st.id == "my_reaper" and "your own setup" or st.id == "base_reaper" and "REAPER as it ships" or st.kind == "built" and "built by you" or st.user and "yours"
    or "keys, theme and layout"
  ImGui.DrawList_AddTextEx(dl, font, 13, x + 26, y + 8 + ih + 27, C.MUTED, sub)
  if fav or hov then
    ImGui.DrawList_AddCircleFilled(dl, x + 24, y + 24, 13, 0x000000A0)
    draw_star(dl, x + 24, y + 24.5, 9, fav, fav and 0xFFC83CFF or (on_star and 0xFFFFFFFF or 0xFFFFFFB0))
  end
  if on then
    local tw, th = ImGui.CalcTextSize(ctx, "In use")
    local px, py = x + w - 8 - tw - 16, y + 14
    ImGui.DrawList_AddRectFilled(dl, px, py, px + tw + 16, py + th + 6, solid(col), (th + 6) / 2)
    ImGui.DrawList_AddText(dl, px + 8, py + 3, on_colour(col), "In use")
  end
end

-- Rows of things with an optional key and an Open button, as a table so long text wraps beside them.
local function rows(id, list, show_open)
  if not list or #list == 0 then return end
  if ImGui.BeginTable(ctx, id, 3, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
    ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "key", ImGui.TableColumnFlags_WidthFixed)
    ImGui.TableSetupColumn(ctx, "open", ImGui.TableColumnFlags_WidthFixed)
    for i, x in ipairs(list) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx); ImGui.PushTextWrapPos(ctx, 0); ImGui.Text(ctx, x[1]); ImGui.PopTextWrapPos(ctx)
      ImGui.TableNextColumn(ctx); if x[3] then keycap(x[3]) end
      ImGui.TableNextColumn(ctx)
      if show_open and x[2] then
        local tool = type(x[2]) == "string" and core.tool_for(x[2])
        if tool and core.cmd_id(x[2]) == 0 then
          if ImGui.SmallButton(ctx, "Get it##" .. id .. i) then core.get_tool(tool) end
          ImGui.SetItemTooltip(ctx, "Needs " .. tool.name .. ": " .. tool.how)
        elseif ImGui.SmallButton(ctx, "Open##" .. id .. i) then open_extra(x[2]) end
      end
    end
    ImGui.EndTable(ctx)
  end
end

local function feel_rows(st)
  if not st.feel or #st.feel == 0 then return end
  if ImGui.BeginTable(ctx, "feel", 2, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
    ImGui.TableSetupColumn(ctx, "kind", ImGui.TableColumnFlags_WidthFixed, 72)
    ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
    for _, f in ipairs(st.feel) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.MUTED)
      ImGui.Text(ctx, f[1] == "mouse" and "Mouse" or f[1] == "switch" and "Toolbar" or f[1] == "dock" and "Window" or (f[1] == "radio" and "Layout") or "Setting")
      ImGui.PopStyleColor(ctx)
      ImGui.TableNextColumn(ctx); ImGui.PushTextWrapPos(ctx, 0); ImGui.Text(ctx, f[#f]); ImGui.PopTextWrapPos(ctx)
    end
    ImGui.EndTable(ctx)
  end
end

local function save_preset_prompt()
  local cur = core.current()
  local ok, name = reaper.GetUserInputs("Save as a persona", 1, "Name,extrawidth=160,separator=\n", (cur.preset and cur.name or (cur.name .. " (mine)")))
  name = ok and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" then return end
  local all = reaper.CountTracks(0)
  local wf = reaper.MB("Make " .. name .. " a workflow too?\n\nYes: a new, empty project with it starts as this one does: its " .. all .. " track" .. (all == 1 and "" or "s") ..
    " with their FX, routing and folders (not their audio or MIDI), its sample rate, recording format, render settings, tempo, markers and regions." ..
    "\nNo: just the shortcuts, theme, layout and settings, as now.", "ReaPersona: save", 3)
  if wf == 2 then return end
  local st, why = core.save_preset(name, wf == 6) -- (yes: the whole project as its template, 5.13)
  if not st then return say("Not saved: " .. tostring(why)) end
  selected = st.id
  say("Saved " .. name .. ": it's in your list" .. (wf == 6 and ", and new projects with it start like this one." or "."))
end

-- The grid of cards (or a list of chips, for a narrow window). Double-click uses one.
local function chooser(list, sel, alt)
  local as_list = reaper.GetExtState(SECTION, "view") == "list"
  if as_list then
    local right = ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx)
    for n, st in ipairs(list) do
      local label = "  " .. st.name .. (in_use(st, alt) and "  (in use)" or "")
      local w = ImGui.CalcTextSize(ctx, label) + 28
      if n > 1 then ImGui.SameLine(ctx, 0, 8); if ImGui.GetCursorPosX(ctx) + w > right then ImGui.NewLine(ctx) end end
      local col = accent_of(st)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, st.id == sel.id and solid(mix(P.card, col, 0.45)) or C.CARD)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Button(ctx, label .. "##chip" .. st.id, w, 0) then selected = st.id end
      if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then use(st) end
      ImGui.PopStyleColor(ctx)
      ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), x + 12, y + ImGui.GetFrameHeight(ctx) / 2, 4.5, solid(col))
    end
    return
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  local per_row = math.max(1, math.min(#list, math.floor((avail + 12) / 190)))
  local w = math.floor((avail - 12 * (per_row - 1)) / per_row)
  for n, st in ipairs(list) do
    if (n - 1) % per_row ~= 0 then ImGui.SameLine(ctx, 0, 12) end
    style_card(st, math.min(w, 280), sel, alt)
  end
end
local function view_switch()
  local as_list = reaper.GetExtState(SECTION, "view") == "list"
  if ImGui.SmallButton(ctx, as_list and "Show pictures" or "Show as a list") then reaper.SetExtState(SECTION, "view", as_list and "" or "list", true) end
end

-- The one picked: what it is, use it, and everything it does.
local function detail(sel, alt)
  local col = accent_of(sel)
  local on = in_use(sel, alt)
  if card("detail") then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddCircleFilled(dl, x + 7, y + 13, 7, solid(col))
    ImGui.SetCursorScreenPos(ctx, x + 22, y)
    heading(sel.name, 24)
    if on then ImGui.SameLine(ctx, 0, 12); pill("In use", solid(col)) end
    muted(sel.description or "")
    if MOD == "Cmd" then -- (a Mac: keys macOS keeps, which never reach REAPER)
      local taken = core.mac_taken(sel.keys)
      if #taken > 0 then muted("macOS keeps these for itself, so they don't reach REAPER unless you turn them off in System Settings > Keyboard > Keyboard Shortcuts: " .. table.concat(taken, ", ") .. ".") end
    end
    if core.needs_layer(sel) then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, "Its shortcuts get a shortcut layer the first time you use it here (REAPER restarts once). REAPER has 16 layers, so ReaPersona gives them only to the personas you use: your favourites, the one in use and your own.")
      ImGui.PopStyleColor(ctx)
    elseif (sel.alt or 0) > 0 and not installed[sel.alt] then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, "Its shortcuts aren't installed yet: Home > Shortcut layers > Install and restart.")
      ImGui.PopStyleColor(ctx)
    end
    for i, s in ipairs(on and core.starts_missing or {}) do -- (scripts it starts with REAPER that aren't installed here, 5.24)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, s[1] .. " starts with REAPER in this persona, and isn't installed here (" .. s[3].pkg .. ", from " .. s[3].repo .. ").")
      ImGui.PopStyleColor(ctx)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Get it##start" .. i) then local why = core.get_tool({ repos = { { s[3].repo, s[3].url } }, filter = s[3].pkg }); if why then say(why) end end
      ImGui.SetItemTooltip(ctx, "Adds " .. s[3].repo .. " (" .. s[3].url .. ") to ReaPack and shows " .. s[3].pkg .. "; installing is your click. Once it's installed, ReaPersona starts it with REAPER.")
    end
    for _, key in ipairs(sel.recommends or {}) do
      local x = core.EXTENSIONS[key]
      local state = x and core.ext_here(key) and core.extension_state(key)
      if state and state ~= "on" then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
        ImGui.TextWrapped(ctx, "Recommended for " .. sel.name .. ": " .. x.name .. " (" .. x.why .. ")." .. (state == "restart" and " Installed: restart REAPER to load it." or ""))
        ImGui.PopStyleColor(ctx)
        if state == "missing" then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Install##rec" .. key) then install_ext(key) end end
      end
    end
    local tools, kms = sel.tools or {}, sel.keymaps or {}
    if (#tools > 0 or #kms > 0) and ImGui.CollapsingHeader(ctx, "More of " .. (sel.short or sel.name) .. " in REAPER##more") then
      for i, t in ipairs(tools) do -- (other people's tools: "Get it" adds their ReaPack repository and opens the browser at it)
        if ImGui.SmallButton(ctx, "Get it##tool" .. i) then local why = core.get_tool(t); if why then say(why) end end
        ImGui.SetItemTooltip(ctx, t.repos and ("Adds " .. t.repos[1][1] .. " to ReaPack and shows the package; installing is your click.") or ("Opens " .. tostring(t.url)))
        ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, t.name .. ": " .. t["for"])
      end
      for i, k in ipairs(kms) do
        if ImGui.SmallButton(ctx, "Open##km" .. i) then core.open_url(k[2]) end
        ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "Keymap: " .. k[1] .. " (drop the file on this window to make it a persona)")
      end
    end
    ImGui.Dummy(ctx, 0, 2)
    ImGui.BeginDisabled(ctx, on)
    if primary(on and "In use" or ("Use " .. sel.name), col) then use(sel) end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cheat sheet") then local p, why = core.cheat_sheet(sel); if p then core.open_url(p) else say(why) end end
    ImGui.SetItemTooltip(ctx, "Every key, setting and feature of this persona on one page, laid out for printing.")
    if sel.id == "my_reaper" then -- (your look on every computer, 5.21)
      ImGui.SameLine(ctx)
      ImGui.BeginDisabled(ctx, not on)
      if ImGui.Button(ctx, "Use this look on all my computers") then
        local look, why = core.save_my_look()
        say(look and ("Saved: " .. core.look_label(look) .. ". Your other computers take it at their next sync (or in a setup file you export).") or why)
      end
      ImGui.EndDisabled(ctx)
      ImGui.SetItemTooltip(ctx, "Keeps this computer's theme, transport and mixer places, docked windows, snap, ripple, mouse drags and the scripts REAPER starts with (Chordbox, adaptive grid...) as your look. My REAPER uses it on every computer you sync with, and every persona goes back to it. Press it again after you change your look.")
      local look = core.my_look()
      if look then
        muted("Your look: " .. core.look_label(look))
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Forget##look") then core.forget_my_look(); say("My REAPER is each computer's own setup again.") end
      end
    end
    local tpl = here .. "/templates/" .. (sel.preset and sel.base or sel.id) .. ".RPP"
    if reaper.file_exists(tpl) then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New project like " .. (sel.short or sel.name)) then
        reaper.Main_OnCommand(40859, 0) -- (a new tab, so nothing open is replaced)
        reaper.Main_openProject("template:" .. tpl)
      end
      ImGui.SetItemTooltip(ctx, "A new project with the tracks " .. (sel.short or sel.name) .. " starts you with, its buses and sends, using REAPER's own plugins.")
    end
    if sel.project then -- (a workflow)
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New project with it") then
        -- (a new tab without the default template, whose tracks would stop the workflow's; this tab if it's still untouched. Review, 5.14)
        if not core.fresh_project(0) then reaper.Main_OnCommand(41929, 0) end
        if not on then use(sel)
        else
          local done = core.apply_project(sel)
          say("A new project with " .. sel.name .. (#done > 0 and (": " .. table.concat(done, ", ")) or "") .. ".")
        end
      end
      ImGui.SetItemTooltip(ctx, "Opens a new project tab set up by this workflow.")
      if on and reaper.CountTracks(0) > 0 then
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Keep these inputs on this computer") then
          local n = core.keep_inputs(sel.id)
          say("Kept the inputs of this project's " .. n .. " track" .. (n == 1 and "" or "s") .. ": new projects with " .. sel.name .. " on this computer get them. Your other computers keep their own.")
        end
        ImGui.SetItemTooltip(ctx, "Each computer's interface numbers its inputs its own way. Set the tracks' inputs here once, press this, and new projects with " .. sel.name .. " get them on this computer.")
      end
    end
    if (sel.alt or 0) > 0 and not sel.preset then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Share...") then
        if not reaper.JS_Dialog_BrowseForSaveFile then reaper.MB("Sharing needs js_ReaScriptAPI (Extensions > ReaPack > Browse packages).", "ReaPersona", 0) end
        local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Share " .. sel.name, reaper.GetResourcePath(), core.file_name(sel.name) .. ".reapersona.json", "ReaPersona persona (*.reapersona.json)\0*.reapersona.json\0\0")
        if ok == 1 and p ~= "" then reaper.MB(core.export(sel, p) and ("Saved " .. p .. ".\n\nAnyone with ReaPersona can import it.") or "Couldn't save it.", "ReaPersona", 0) end
      end
      ImGui.SetItemTooltip(ctx, "Save this persona (keys, MIDI keys, feel, and your theme version if you made one) as one file to give someone.")
    end
    if sel.preset then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Share...##preset") then
        if not reaper.JS_Dialog_BrowseForSaveFile then reaper.MB("Sharing needs js_ReaScriptAPI (Extensions > ReaPack > Browse packages).", "ReaPersona", 0) end
        local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Share " .. sel.name, reaper.GetResourcePath(), core.file_name(sel.name) .. ".reapersona-preset.json", "ReaPersona preset (*.json)\0*.json\0\0")
        if ok == 1 and p ~= "" then reaper.MB(core.export_preset(sel.id, p) and ("Saved " .. p .. ".\n\nAnyone with ReaPersona can drop it on the window.") or "Couldn't save it.", "ReaPersona", 0) end
      end
      ImGui.SetItemTooltip(ctx, "This persona as one file: drop it on someone's ReaPersona window (they need the DAW personas it's built on).")
    end
    if sel.preset or sel.user then
      ImGui.SameLine(ctx)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.RED)
      local deps = ImGui.Button(ctx, "Delete persona") and (sel.preset and {} or core.presets_on(sel.id))
      if deps and reaper.MB("Delete " .. sel.name .. "? This can't be undone." .. (core.sync_folder() ~= "" and " It goes from your other computers too (they sync)." or "") ..
          (#deps > 0 and ("\n\nThese personas are built on it and will use My REAPER's keys instead:\n" .. table.concat(deps, "\n")) or ""), "ReaPersona", 4) == 6 then
        if on and sel.preset then core.use(core.by_id(sel.base or "my_reaper")) end
        local ok, why
        if sel.preset then ok, why = core.delete_preset(sel.id) else ok, why = core.delete_user_style(sel.id) end
        if ok then selected = sel.base or core.current().id else say("Not deleted: " .. tostring(why)) end
      end
      ImGui.PopStyleColor(ctx)
    end
    ImGui.Dummy(ctx, 0, 2)
    persona_row(sel)
    local fav = core.is_favourite(sel.id)
    if ImGui.Button(ctx, (fav and "In favourites" or "Add to favourites") .. "##favp") then core.set_favourite(sel.id, not fav) end
    ImGui.SetItemTooltip(ctx, fav and "Click to take it off Personas > Favourites." or "Puts it on Personas > Favourites (or click the star on its card).")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Edit##editp") then bld_load(sel) end
    local vid = (sel.id == "my_reaper" or (sel.user and sel.kind == "built")) and sel.id
    local vers = vid and core.versions(vid) or {}
    if #vers > 0 then -- (5.28: each save keeps the one before)
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 190 * UI)
      if ImGui.BeginCombo(ctx, "##vers", "Earlier versions (" .. #vers .. ")") then
        for i, v in ipairs(vers) do
          if ImGui.Selectable(ctx, tostring(v.saved) .. "##v" .. i) and reaper.MB("Put back " .. sel.name .. " as it was on " .. tostring(v.saved) .. "?\n\nThe version you have now is kept too, so you can come back to it.", "ReaPersona", 4) == 6 then
            if vid == "my_reaper" then core.save_look(v.data) else core.save_user_style(v.data); core.reload_users() end
            if reaper.GetExtState(SECTION, "style") == vid then core.use(core.by_id(vid)) end
            say(sel.name .. " is back as it was on " .. tostring(v.saved) .. ".")
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.SetItemTooltip(ctx, "Each time it's saved, the version before is kept (the newest 20, on this computer). Pick one to put it back.")
    end
    ImGui.SetItemTooltip(ctx, sel.blocks and "Change any part of it on the Shortcuts, Mouse, Layout, Themes, Colours, Project and REAPER tabs, then Save changes in the bar at the top."
      or "Start from " .. sel.name .. " and change any part on the tabs. It's saved as a persona of yours: " .. sel.name .. " stays as it is.")
    ImGui.SameLine(ctx)
    if core.project_persona() == sel.id then
      ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.GREEN, "This project uses " .. sel.name .. ".")
      ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Not for this project") then core.set_project_persona(nil) end
    elseif ImGui.Button(ctx, "Use for this project") then
      core.set_project_persona(sel.id)
      if not on then use(sel) end
      say(sel.name .. " is this project's persona (saved with the project)." .. (core.follow_on() and "" or " Turn on 'Switch persona with the project' in Settings to switch automatically."))
    end
    ImGui.SetItemTooltip(ctx, "Saved in the project file. With 'Switch persona with the project' on (Settings), opening this project or switching to its tab switches to this persona.")
    local vers, seen, mine = {}, {}, {}
    for _, th in ipairs(sel.themes or { sel.theme }) do if th and not seen[th] then vers[#vers + 1] = th; seen[th] = true end end
    for _, th in ipairs(core.forks(sel)) do if not seen[th] then vers[#vers + 1] = th; seen[th] = true; mine[th] = true end end
    local have, missing, can = {}, {}, 0
    for _, th in ipairs(vers) do
      if reaper.file_exists(themes_dir .. th) then have[#have + 1] = th
      elseif core.can_install_theme(th) or (core.CATALOG[th] and core.CATALOG[th].url and core.CATALOG[th].url:match("^https?:")) then
        missing[#missing + 1] = th
        if core.can_install_theme(th) then can = can + 1 end
      end
    end
    local rec = sel.theme
    if rec and not reaper.file_exists(themes_dir .. rec) and core.can_install_theme(rec) then
      ImGui.Dummy(ctx, 0, 2)
      if primary("Install " .. sel.name .. "'s recommended look: " .. rec:gsub("%.ReaperTheme%a*$", ""), col) then install_theme_ui(rec, sel, true) end
      local c = core.CATALOG[rec]
      ImGui.SetItemTooltip(ctx, "Downloads it" .. (c.by and (" (by " .. c.by .. ")") or "") .. " and takes it in, with its fonts, scripts and extras on your yes. " .. (c.note or ""))
    end
    if #have > 1 or #missing > 0 then
      ImGui.Dummy(ctx, 0, 2)
      heading("Theme versions", 15)
      muted("Click one to make it " .. sel.name .. "'s theme" .. (on and " (it goes on now)." or " (it goes on when you use " .. sel.name .. ").") ..
        " Add any theme to this list from Themes > Your themes > Add to; right-click one you added to take it off.")
      local cur = core.theme_for(sel)
      local x0 = ImGui.GetCursorScreenPos(ctx)
      local xend, pad, first = x0 + ImGui.GetContentRegionAvail(ctx), ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding), true
      for i, th in ipairs(have) do
        local nice = th:gsub("%.ReaperTheme%a*$", ""):gsub("^ReaPersona %- (.*)$", "ReaPersona's %1")
        local w = ImGui.CalcTextSize(ctx, nice) + 2 * pad
        if not first and ImGui.GetItemRectMax(ctx) + 6 + w <= xend then ImGui.SameLine(ctx, 0, 6) end
        first = false
        local picked = th == cur
        if picked then
          ImGui.PushStyleColor(ctx, ImGui.Col_Button, solid(col)); ImGui.PushStyleColor(ctx, ImGui.Col_Text, on_colour(col))
        end
        if ImGui.Button(ctx, nice .. "##tv" .. i) and not picked then
          reaper.SetExtState(SECTION, "theme " .. sel.id, th, true)
          if on then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th) end
          say(nice .. (on and " is on." or (" is " .. sel.name .. "'s theme now.")))
        end
        if picked then ImGui.PopStyleColor(ctx, 2) end
        local c = core.CATALOG[th]
        ImGui.SetItemTooltip(ctx, (picked and "In use for " .. sel.name .. ". " or "") .. (c and ("By " .. tostring(c.by) .. (c.note and (": " .. c.note) or "") .. ".") or
          mine[th] and "You added this one." or "On this computer."))
        if mine[th] and ImGui.BeginPopupContextItem(ctx, "##tvm" .. i) then
          if ImGui.MenuItem(ctx, "Take off " .. sel.name .. "'s list") then remove_fork(sel, th) end
          ImGui.EndPopup(ctx)
        end
      end
      for i, th in ipairs(have) do -- (mod packs for a version you have: each mod becomes a version of its own)
        for k, m in ipairs((core.CATALOG[th] or {}).mods or {}) do
          if ImGui.SmallButton(ctx, "Add " .. th:gsub("%.ReaperTheme%a*$", "") .. "'s " .. m.name .. "##tvmod" .. i .. "_" .. k) then
            local got, why = core.install_mod(th, k)
            if got then drop_report(got) else say("Couldn't get it: " .. tostring(why)) end
          end
          ImGui.SetItemTooltip(ctx, "Downloads the mod pack and makes each mod a version of " .. th:gsub("%.ReaperTheme%a*$", "") .. " you can click above.")
        end
      end
      if #missing > 0 and ImGui.TreeNode(ctx, #missing .. " more version" .. (#missing == 1 and "" or "s") .. " you can get##tvget") then
        if can > 1 and ImGui.Button(ctx, "Install all " .. can .. "##tvall") then
          for _, th in ipairs(missing) do if core.can_install_theme(th) and not reaper.file_exists(themes_dir .. th) then install_theme_ui(th, sel, false) end end
        end
        for i, th in ipairs(missing) do
          local c = core.CATALOG[th]
          if core.can_install_theme(th) then
            if ImGui.SmallButton(ctx, "Install##tvi" .. i) then install_theme_ui(th, sel, false) end
            ImGui.SetItemTooltip(ctx, "Downloads it and takes it in, with its fonts and extras on your yes.")
          elseif ImGui.SmallButton(ctx, "Get it##tvg" .. i) then core.open_url(c.url) end
          ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, th:gsub("%.ReaperTheme%a*$", "") .. (c.by and (" by " .. c.by) or "") .. (c.note and (" (" .. c.note .. ")") or ""))
        end
        muted("Get it opens a page that needs your browser (a paid theme, or a sign-in): download it there, then drop the file on this window.")
        ImGui.TreePop(ctx)
      end
    end
    if (core.theme_for(sel) or ""):match("^ReaPersona %- ") then
      muted("ReaPersona's own theme is an approximation of " .. sel.name .. "'s colours on REAPER's Default 7 layout. Themes by other authors can look closer to the real thing: Setup lists them with Get it links, and Browse searches the Stash.")
    end
    card_end()
  end
  if sel.feel and #sel.feel > 0 and card("feel card") then
    heading("How it behaves")
    muted("Put back the way you had it when you switch away.")
    feel_rows(sel)
    card_end()
  end
  if sel.extras and #sel.extras > 0 and card("extras card") then
    heading("What " .. (sel.preset and (core.by_id(sel.base) or sel).name or sel.name) .. " has, and where it is in REAPER")
    rows("extras", sel.extras, true)
    card_end()
  end
  if sel.tips and #sel.tips > 0 and card("tips card") then
    heading("REAPER:") -- (not "REAPER tips": it read as the Reapertips theme)
    muted((sel.id == "base_reaper" and "" or "With REAPER's own keys (Base REAPER has them all). ") .. "From REAPER 7.85's factory keymap.")
    rows("tips", sel.tips, true)
    if ImGui.SmallButton(ctx, "REAPER User Guide") then core.open_url("https://www.reaper.fm/userguide.php") end
    card_end()
  end
  local fxl = core.fx_equiv(sel.preset and sel.base or sel.id) -- (5.36: its plug-ins, and REAPER's own for each)
  if fxl and card("fx card") then
    local who = sel.preset and core.by_id(sel.base) or sel
    heading(who.name .. "'s plug-ins in REAPER")
    muted("REAPER's own plug-in for each of " .. who.name .. "'s. A folder of them in REAPER's FX browser keeps them together (REAPER shows it after its next restart; it lists REAPER's names).")
    local here, on = core.fx_stock_here(), core.fx_folder_on(who)
    if ImGui.SmallButton(ctx, (on and "Take out" or "Add") .. " the '" .. core.fx_folder_name(who) .. "' folder##fxf") then
      local n, why = core.fx_folder_set(who, not on)
      say(n and (on and "The folder is out of REAPER's FX browser (after its next restart)." or ("The folder, with " .. n .. " of REAPER's plug-ins, is in REAPER's FX browser after its next restart.")) or ("Not changed: " .. tostring(why)))
    end
    ImGui.Indent(ctx, IND * UI)
    for _, x in ipairs(fxl) do
      local f = here[x[2]]
      ImGui.Text(ctx, x[1]); ImGui.SameLine(ctx, 260 * UI)
      if f then ImGui.TextColored(ctx, C.MUTED, core.fx_stock_name(x[2])) else ImGui.TextColored(ctx, C.YELLOW, core.fx_stock_name(x[2]) .. " (not found in this REAPER)") end
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
local function pick_in(list, sel) -- the one picked, if it's on this page; else this page's first
  for _, st in ipairs(list) do if st == sel then return sel end end
  return list[1]
end

local function daws_page(sel, alt)
  local list = {}
  for _, st in ipairs(styles) do if st.kind ~= "theme" and not st.user and st.kind ~= "built" then list[#list + 1] = st end end -- (yours: Your personas)
  workflow_row()
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
  if ImGui.SmallButton(ctx, "Import a shared persona...") then
    local ok, p = reaper.GetUserFileNameForRead("", "Import a ReaPersona persona", "*.json")
    if ok then
      local st, why = core.import(p)
      reaper.MB(st and (st.name .. " imported as shortcut layer alt-" .. st.alt .. ".\n\nReopen ReaPersona to see it; its shortcuts need installing (Home > Shortcut layers).") or ("Not imported: " .. why), "ReaPersona", 0)
    end
  end
end

-- Themes: theme styles (a theme with your own keys), every theme on this computer, adding your own, and where to find more.
local THEME_SOURCES = {
  { "REAPER Stash: themes", "https://stash.reaper.fm/tag/Themes", "Cockos' own library: most REAPER themes live here (sort by downloads)." },
  { "ReaPack: browse themes", "reapack", "Themes you can install and keep updated from inside REAPER (Extensions > ReaPack > Browse packages, type: Theme)." },
  { "Reapertips", "https://www.reapertips.com/", "The Reapertips theme and its updates." },
  { "Cockos forum: Themes", "https://forum.cockos.com/forumdisplay.php?f=21", "Where theme authors post new themes and versions." },
}
local themes_filter, theme_list = "", nil
local function import_theme()
  local ok, p = reaper.GetUserFileNameForRead("", "Add a theme (.ReaperThemeZip or .ReaperTheme)", "*.ReaperTheme*")
  if not ok then return end
  local name, why = core.import_theme(p)
  theme_list = nil
  if not name then return reaper.MB("Not added: " .. tostring(why), "ReaPersona", 0) end
  local cur = core.current()
  if reaper.MB(name .. " is in ColorThemes now.\n\nUse it now, and keep it in " .. cur.name .. "'s Theme list?", "ReaPersona", 4) == 6 then
    add_fork(cur, name)
    reaper.OpenColorThemeFile(themes_dir .. name)
  end
  say("Added " .. name)
end
local function themes_page(sel, alt)
  if card("theme now") then -- (5.28: the one in use, always first and apart)
    local now = core.loaded_theme() or "?"
    heading("In use: " .. now:gsub("%.ReaperTheme%a*$", ""), 18)
    if ImGui.SmallButton(ctx, "Adjust it##thnow") then go("Adjust") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "My persona's theme##thnowp") then in_persona(core.new_block("theme", now), (now:gsub("%.ReaperTheme%a*$", ""))) end
    ImGui.SetItemTooltip(ctx, "Makes the theme in use the theme of the persona you're making.")
    card_end()
  end
  if card("all themes") then
    persona_theme_line()
    ImGui.Dummy(ctx, 0, 2)
    heading("Every theme on this computer")
    muted("Use one on its own (your keys and settings stay as they are), or add it to the Theme list of the persona in use.")
    theme_list = theme_list or theme_files()
    ImGui.SetNextItemWidth(ctx, 260)
    local _, f = ImGui.InputTextWithHint(ctx, "##tf", "search " .. #theme_list .. " themes", themes_filter)
    themes_filter = f
    ImGui.SameLine(ctx)
    if primary("Add a theme...") then import_theme() end
    ImGui.SetItemTooltip(ctx, "Copy a .ReaperThemeZip or .ReaperTheme you downloaded into REAPER's ColorThemes folder.")
    local current = core.loaded_theme() or ""
    local cur = core.current()
    if ImGui.BeginTable(ctx, "themes", 3, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 320) then
      ImGui.TableSetupColumn(ctx, "name", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "use", ImGui.TableColumnFlags_WidthFixed)
      ImGui.TableSetupColumn(ctx, "add", ImGui.TableColumnFlags_WidthFixed)
      local q = themes_filter:lower()
      for i, th in ipairs(theme_list) do
        if q == "" or th:lower():find(q, 1, true) then
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx)
          local nice = th:gsub("%.ReaperThemeZip$", ""):gsub("%.ReaperTheme$", "") -- (theme names, not file names)
          if (core.recent_themes or {})[th] then nice = nice .. "  (new)" end
          if th == current then ImGui.TextColored(ctx, C.GREEN, nice .. "  (in use)") else ImGui.Text(ctx, nice) end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "Try##t" .. i) then try_theme(th) end
          ImGui.SetItemTooltip(ctx, "Wear it for 20 seconds: Keep it, or it goes back to the theme you had.")
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Use##u" .. i) then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th); say(nice .. " in use.") end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "My persona##p" .. i) then in_persona(core.new_block("theme", th), nice) end
          ImGui.SetItemTooltip(ctx, "The theme of the persona you're making (it replaces the one in it).")
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Add to...##a" .. i) then ImGui.OpenPopup(ctx, "addto##" .. i) end
          ImGui.SetItemTooltip(ctx, "Make it one of a persona's theme versions (its page lists them to click).")
          if ImGui.BeginPopup(ctx, "addto##" .. i) then
            for _, st in ipairs(styles) do
              if st.kind ~= "theme" and ImGui.MenuItem(ctx, st.name .. (st == cur and "  (in use)" or "") .. "##at" .. st.id) then
                add_fork(st, th); if st == cur then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th) end
                say(nice .. " is one of " .. st.name .. "'s theme versions" .. (st == cur and ", and on now." or "."))
              end
            end
            ImGui.EndPopup(ctx)
          end
        end
      end
      ImGui.EndTable(ctx)
    end
    card_end()
  end
  local list = {}
  for _, st in ipairs(styles) do if st.kind == "theme" then list[#list + 1] = st end end
  if #list > 0 then
    view_switch()
    chooser(list, pick_in(list, sel), alt)
    ImGui.Dummy(ctx, 0, 4)
    detail(pick_in(list, sel), alt)
  end
  if card("theme sources") then
    heading("Where to get more themes")
    for i, s in ipairs(THEME_SOURCES) do
      if ImGui.Button(ctx, s[1] .. "##src" .. i) then
        if s[2] == "reapack" then
          local id = reaper.NamedCommandLookup("_REAPACK_BROWSE")
          if id ~= 0 then reaper.Main_OnCommand(id, 0) else reaper.MB("ReaPack isn't installed (reapack.com).", "ReaPersona", 0) end
        else core.open_url(s[2]) end
      end
      ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); muted(s[3])
    end
    ImGui.Dummy(ctx, 0, 2)
    muted("Downloaded a theme? Add a theme... above copies it in. A theme's author decides whether it can be shared: most say nothing, so keep merged and edited versions to yourself unless they agree.")
    card_end()
  end
end

local function presets_page(sel, alt)
  if card("presets top") then
    heading("Make your own persona")
    muted("Save what you're using now (the persona, plus your theme, layout, snap and mouse as they're set), or make one: New persona, then choose its shortcuts, mouse, layout, theme, colours, project and REAPER settings on their tabs. Edit on any persona's page changes it the same way.")
    if primary("Save what I'm using now...") then save_preset_prompt() end
    ImGui.SameLine(ctx)
    if primary("New persona") then bld_new() end
    ImGui.SetItemTooltip(ctx, "Starts a persona with nothing chosen: your own setup fills in whatever you don't choose on the tabs.")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Import...") then
      local ok, p = reaper.GetUserFileNameForRead("", "Import a ReaPersona persona", "*.json")
      if ok then
        local r = core.import_file(p)[1] or { "skipped", p, "nothing in it" }
        reaper.MB(r[1] ~= "skipped" and (r[2] .. " is imported.") or ("Not imported: " .. tostring(r[3])), "ReaPersona", 0)
      end
    end
    card_end()
  end
  local list = {}
  for _, st in ipairs(styles) do if (st.user or st.kind == "built") and st.kind ~= "theme" and st.id ~= "built_try" then list[#list + 1] = st end end
  for _, st in ipairs(core.presets) do list[#list + 1] = st end
  if #list == 0 then return end
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
end
local function favourites_page(sel, alt) -- (5.27) the DAWs and personas you starred
  local list = {}
  for _, id in ipairs(core.favourites()) do local st = core.by_id(id); if st then list[#list + 1] = st end end
  if #list == 0 then
    if card("fav none") then heading("Favourites"); muted("Click the star on any DAW or persona (its card, top left) to keep it here."); card_end() end
    return
  end
  workflow_row()
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
end

-- Settings: what personas may change, a persona per project, the smooth playhead / scroll extensions, and the look.
local LOOKS = { "Follow StudioSync", "Dark", "Light", "Midnight", "Warm" }
local function switch(id, on) -- an on/off switch: -> clicked
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local h = ImGui.GetFrameHeight(ctx) - 4
  local w = h * 1.8
  ImGui.SetCursorScreenPos(ctx, x, y + 2)
  local clicked = ImGui.InvisibleButton(ctx, id, w, h)
  ImGui.DrawList_AddRectFilled(dl, x, y + 2, x + w, y + 2 + h, on and C.ACCENT or solid(mix(P.bg, P.text, 0.36)), h / 2)
  ImGui.DrawList_AddCircleFilled(dl, on and (x + w - h / 2) or (x + h / 2), y + 2 + h / 2, h / 2 - 3, 0xFFFFFFFF)
  return clicked
end
local function setting_row(id, label, on, tip)
  local clicked = switch(id, on)
  if tip then ImGui.SetItemTooltip(ctx, tip) end
  ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, label)
  if tip then ImGui.SetItemTooltip(ctx, tip) end
  return clicked
end
-- Your other computers (5.10): the folder you pick, the first sync (whose setup wins), and a look every 20 s while the window is open.
local sync_next, sync_err, sync_seen, sync_full = 0, nil, "", reaper.time_precise() + 10 -- (the window opens without waiting for REAPER's own parts)
local function sync_step(now) -- (now: Sync now pressed, so the result is said. The advanced parts every 5 minutes, or on Sync now)
  if core.sync_folder() == "" then return end
  sync_next = reaper.time_precise() + 20
  core.quick = not (now or reaper.time_precise() >= sync_full)
  if not core.quick then sync_full = reaper.time_precise() + 1800 end -- (REAPER's own parts: on opening, Sync now and every 30 minutes)
  local ok, rep, why = pcall(core.sync_now)
  core.quick = nil
  if not ok then why, rep = rep, nil end
  sync_err = not rep and ("Couldn't sync: " .. tostring(why)) or nil
  if not rep then if now then say(sync_err) end return end
  local names = {}
  for _, o in ipairs(rep.others) do if o.d then names[#names + 1] = tostring(o.d.computer or o.name) end end -- (one that doesn't parse: its own line)
  sync_seen = table.concat(names, ", ")
  if rep.changed or now then
    say((rep.changed and ("From your other computers: " .. core.setup_summary(rep) .. ".") or "Up to date.") ..
      ((rep.ext or 0) > 0 and (" " .. core.SETUP_RESTART) or "") .. (rep.install and " New shortcuts need installing (Home)." or ""))
  end
end
local function choose_sync_folder()
  if not reaper.JS_Dialog_BrowseForFolder then say("Choosing a folder needs js_ReaScriptAPI (ReaPack).") return end
  local ok, dir = reaper.JS_Dialog_BrowseForFolder("A folder your computers share (Syncthing, Google Drive...)", core.sync_folder() ~= "" and core.sync_folder() or res)
  if ok ~= 1 or dir == "" then return end
  dir = dir:gsub("\\", "/"):gsub("/+$", "")
  local names = {}
  for _, o in ipairs(core.sync_others(dir)) do names[#names + 1] = o.d and tostring(o.d.computer or o.name) or o.name end
  local start
  if #names > 0 then
    local r = reaper.MB("The folder already has the ReaPersona setup of " .. table.concat(names, ", ") .. ".\n\n" ..
      "Yes: take theirs here. Where both have the same persona or setting, theirs wins; what only this computer has goes to them.\n" ..
      "No: this computer's setup wins and goes to them (personas deleted on the others since may come back).\nCancel: don't sync.", "ReaPersona: sync", 3)
    if r == 2 then return end
    start = r == 6 and "theirs" or "mine"
  end
  local rep, why = core.start_sync(dir, start)
  sync_err = not rep and ("Couldn't sync: " .. tostring(why)) or nil
  if rep then sync_next = reaper.time_precise() + 20 end
  say(rep and ("Syncing through " .. dir .. (rep.changed and (": " .. core.setup_summary(rep) .. " came in." .. ((rep.ext or 0) > 0 and (" " .. core.SETUP_RESTART) or "")) or ".")) or sync_err)
end
local function save_setup_file() -- (Settings, and the screen-reader menu)
  local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Save your ReaPersona setup", res, "ReaPersona setup " .. os.date("%Y-%m-%d") .. ".reapersona-setup.json", "ReaPersona setup (*.json)\0*.json\0\0")
  if not reaper.JS_Dialog_BrowseForSaveFile then say("Saving a file needs js_ReaScriptAPI (ReaPack).")
  elseif ok == 1 and p ~= "" then
    if not p:lower():match("%.json$") then p = p .. ".reapersona-setup.json" end
    local done, why = core.export_setup(p)
    say(done and ("Saved " .. p .. ". On the other computer: Settings > Load a file, or drop it on ReaPersona's window.") or ("Not saved: " .. tostring(why)))
  end
end
local function load_setup_file()
  local ok, p = reaper.GetUserFileNameForRead(res .. "/", "Load a ReaPersona setup", "json")
  local fine, d = false, nil
  if ok and p ~= "" then fine, d = pcall(core.json_decode, core.read(p) or "") end
  if ok and p ~= "" and fine and type(d) == "table" and d.items and not core.confirm_setup(d, p:match("[^/\\]+$")) then ok = false end
  if ok and p ~= "" then
    local r, why = core.import_setup(p)
    if r then
      say("Loaded " .. core.setup_summary(r) .. "." .. ((r.ext or 0) > 0 and (" " .. core.SETUP_RESTART) or "") ..
        (r.install and " Your personas with shortcuts of their own need them installed (Home)." or "") .. (r.skipped and (" Left alone (a file of yours doesn't parse): " .. r.skipped .. ".") or ""))
    else say("Not loaded: " .. tostring(why)) end
  end
end
local upd = {} -- (Settings > Updates: what GitHub said, when, and what updating did)
local function settings_page(sec) -- (5.33: in sub-tabs; sec = which)
  if sec == "sync" and card("set sync") then
    heading("Your other computers")
    muted("Your personas, presets and ReaPersona's settings, with Smooth Wheel Scroll's and ReaSmoothPlayhead's settings, in one file to take to another computer, or kept the same on all of them through a folder they share (Syncthing, Google Drive, Dropbox...). Themes, and where this computer's windows and dockers are, stay as they are.")
    if ImGui.Button(ctx, "Save to a file...") then save_setup_file() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Load a file...") then load_setup_file() end
    ImGui.Dummy(ctx, 0, 4)
    local dir = core.sync_folder()
    if dir == "" then
      ImGui.Text(ctx, "Keep them the same through a shared folder")
      muted("Pick a folder your computers share, here and then on each of the others. Each computer keeps its own file in it; the newest change to each persona or setting wins. ReaPersona looks when REAPER starts and while its window is open.")
      if primary("Choose a folder...") then choose_sync_folder() end
    else
      ImGui.TextWrapped(ctx, "Syncing through " .. dir)
      local t, what, skipped = reaper.GetExtState(SECTION, "sync last"):match("^(%d+)|([^|]*)|?(.*)$")
      if t then muted("Last looked " .. os.date("%H:%M", tonumber(t)) .. " (" .. what .. ")" .. (sync_seen ~= "" and ("; with " .. sync_seen) or ""))
      else muted("Not synced yet.") end
      if skipped and skipped ~= "" then ImGui.TextColored(ctx, C.YELLOW, "Skipped (doesn't parse, left as it is): " .. skipped:gsub("^skipped ", "")) end
      if sync_err then ImGui.TextColored(ctx, C.YELLOW, sync_err) end
      if ImGui.Button(ctx, "Sync now") then sync_step(true) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Change folder...") then choose_sync_folder() end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Stop syncing") then core.stop_sync(); sync_err, sync_seen = nil, ""; say("Not syncing any more. Your setup here stays as it is.") end
    end
    local pend = core.restart_pending() -- (shown whether or not the advanced parts are unfolded)
    if #pend > 0 then
      ImGui.TextColored(ctx, C.YELLOW, "Waiting for REAPER to restart (from your other computers, or ReaPersona's window set): " .. table.concat(pend, ", "))
      if primary("Apply (REAPER restarts)##applysetup") then install_shortcuts() end
      ImGui.SetItemTooltip(ctx, "REAPER closes (asking about anything unsaved), they're merged into this computer's (backed up first), your persona shortcuts go back in, and REAPER opens again.")
    end
    ImGui.Dummy(ctx, 0, 4)
    local n_adv = 0
    for _, a in ipairs(core.ADVANCED) do if core.advanced_on(a.id) then n_adv = n_adv + 1 end end
    if setting_row("##advsync", "Advanced: REAPER itself too" .. (n_adv > 0 and ("  (" .. n_adv .. " part" .. (n_adv == 1 and "" or "s") .. " syncing)") or ""), reaper.GetExtState(SECTION, "sync show advanced") == "1",
        "Your preferences, other scripts' settings, shortcuts, menus and toolbars, templates, your own scripts and JSFX, themes and ReaPack packages, each part chosen below.") then
      reaper.SetExtState(SECTION, "sync show advanced", reaper.GetExtState(SECTION, "sync show advanced") == "1" and "" or "1", true)
    end
    if reaper.GetExtState(SECTION, "sync show advanced") == "1" then
      muted("Each part goes in the setup file and the sync folder from this computer, and is taken in here, only while it's ticked here. Paths, audio and MIDI devices and window places always stay this computer's own.")
      for _, a in ipairs(core.ADVANCED) do
        local on = core.advanced_on(a.id)
        local needs_py = (a.id == "code" or a.id == "packages") and not core.python()
        ImGui.BeginDisabled(ctx, needs_py and not on)
        if setting_row("##adv" .. a.id, a.name .. (needs_py and " (needs Python)" or ""), on, a.tip) then
          if on then core.set_advanced(a.id, false)
          else
            local theirs = false
            if core.sync_folder() ~= "" then
              theirs = reaper.MB("Take your other computers' " .. a.name:lower() .. " here first?\n\nYes: where both have one, theirs wins this first time.\nNo: this computer's win and go to them.", "ReaPersona: " .. a.name, 4) == 6
            end
            core.advanced_join(a.id, theirs)
            if core.sync_folder() ~= "" then sync_step(true) end
          end
        end
        ImGui.EndDisabled(ctx)
      end
      if core.advanced_on("packages") then
        local miss = core.packages_missing()
        if #miss > 0 then
          ImGui.TextColored(ctx, C.YELLOW, #miss .. " ReaPack package" .. (#miss == 1 and "" or "s") .. " your other computers have aren't here yet.")
          if ImGui.IsItemHovered(ctx) then
            local names = {}
            for i, m in ipairs(miss) do if i > 25 then names[#names + 1] = "..."; break end names[#names + 1] = m.key:gsub("|", " / ") end
            ImGui.SetTooltip(ctx, table.concat(names, "\n"))
          end
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Install them##instmiss") then
            local n, why = core.install_missing()
            say(n and (n .. " package" .. (n == 1 and "" or "s") .. " handed to ReaPack: it installs this system's versions and shows what it did.") or ("Not installed: " .. tostring(why)))
          end
        end
      end
    end
    card_end()
  end
  if sec == "personas" and card("set aspects") then
    heading("What a persona may change")
    muted("Switch off what you'd rather keep as it is, whatever persona you use. Takes effect the next time you use a persona; what a persona already changed is still put back when you switch away.")
    for i, a in ipairs(core.ASPECTS) do
      if setting_row("##asp" .. i, a[2], core.aspect_on(a[1])) then reaper.SetExtState(SECTION, "aspect " .. a[1], core.aspect_on(a[1]) and "0" or "1", true) end
    end
    card_end()
  end
  if sec == "personas" and card("set actions") then
    heading("REAPER's Actions list")
    muted("ReaPersona opens from Extensions > ReaPersona, View > ReaPersona or the Actions list. Switching persona from a key or a toolbar button needs its actions there: a key or button already using one keeps it either way.")
    if setting_row("##allact", "Every ReaPersona action in REAPER's Actions list", core.all_actions()) then
      reaper.SetExtState(SECTION, "all actions", core.all_actions() and "0" or "1", true)
      core.ensure_scripts()
    end
    card_end()
  end
  if sec == "personas" and card("set projects") then
    heading("A persona per project")
    muted("Give a project its persona with 'Use for this project' on the persona's page; it's saved in the project. With this on, opening that project or switching to its tab switches persona, and a persona's REAPER settings (the REAPER tab, In my persona) make each project's workflow its own.")
    if setting_row("##follow", "Switch persona with the project", core.follow_on()) then
      reaper.SetExtState(SECTION, "follow projects", core.follow_on() and "0" or "1", true)
      if core.follow_on() then core.start_following() end
    end
    local def = core.by_id(reaper.GetExtState(SECTION, "project default"))
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Projects without one"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 260 * UI)
    if ImGui.BeginCombo(ctx, "##projdef", def and ("switch to " .. def.name) or "keep the persona in use") then
      if ImGui.Selectable(ctx, "keep the persona in use", not def) then reaper.SetExtState(SECTION, "project default", "", true) end
      for _, st in ipairs(styles) do
        if ImGui.Selectable(ctx, "switch to " .. st.name .. "##pd" .. st.id, def == st) then reaper.SetExtState(SECTION, "project default", st.id, true) end
      end
      ImGui.EndCombo(ctx)
    end
    if core.follow_on() and not core.startup_on() then
      ImGui.TextColored(ctx, C.YELLOW, "Add the startup line (Home) so this keeps working after REAPER restarts.")
    end
    card_end()
  end
  if sec == "scroll" and card("set playback") then
    heading("Smooth playhead, scrolling and zoom")
    muted("Most DAWs glide their playhead and zoom smoothly; REAPER steps. These two extensions add that. The DAW personas that feel that way recommend them.")
    for key, x in pairs(core.EXTENSIONS) do
      local state = core.extension_state(key)
      if state == "on" or state == "off" then
        if x.toggle then
          if setting_row("##ext" .. key, x.name, state == "on", x.why) then reaper.Main_OnCommand(reaper.NamedCommandLookup(x.toggle), 0); core.forget() end
        else ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, x.name .. ": installed") end
        if x.settings then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Settings##set" .. key) then reaper.Main_OnCommand(reaper.NamedCommandLookup(x.settings), 0) end end
      elseif state == "restart" then
        ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.YELLOW, x.name .. ": installed, restart REAPER to load it")
      else
        ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, x.name .. ": not installed")
        ImGui.SameLine(ctx)
        if core.can_install(key) then
          if primary("Install##inst" .. key) then install_ext(key) end
        else muted("(" .. (x.where or "no download known") .. ")") end
      end
      ImGui.SetItemTooltip(ctx, x.why)
    end
    card_end()
  end
  if sec == "look" and card("set look") then
    heading("ReaPersona's look")
    local look = reaper.GetExtState(SECTION, "look")
    if look == "" then look = "Follow StudioSync" end
    for i, l in ipairs(LOOKS) do
      if i > 1 then ImGui.SameLine(ctx) end
      if ImGui.RadioButton(ctx, l, look == l) then reaper.SetExtState(SECTION, "look", l, true); apply_look() end
    end
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Text size"); ImGui.SameLine(ctx)
    for _, z in ipairs({ { 13, "Small" }, { 15, "Normal" }, { 17, "Large" }, { 19, "Larger" } }) do
      ImGui.SameLine(ctx)
      if ImGui.RadioButton(ctx, z[2] .. "##ts", math.floor(UI * 15 + 0.5) == z[1]) then UI = z[1] / 15; reaper.SetExtState(SECTION, "text size", tostring(z[1]), true) end
    end
    muted("Follow StudioSync uses StudioSync's colour choice when it's installed (Dark otherwise).")
    card_end()
  end
  if sec == "look" and card("set access") then -- (5.14: ReaImGui's window is pixels to a screen reader; the menu is REAPER's own)
    heading("Screen readers")
    muted("A screen reader (NVDA, JAWS or VoiceOver, through OSARA) can't read this window. ReaPersona's menu it can: REAPER's own menu with the main tasks, and the results in message boxes.")
    if setting_row("##srmenu", "Open the menu instead of this window", reaper.GetExtState(SECTION, "screen reader") == "1",
        "ReaPersona's action then opens the menu. The action 'ReaPersona - screen-reader menu' opens it either way.") then
      reaper.SetExtState(SECTION, "screen reader", reaper.GetExtState(SECTION, "screen reader") == "1" and "0" or "1", true)
    end
    card_end()
  end
  if sec == "updates" and card("set update") then -- (5.23: like StudioSync's Update)
    heading("Updates")
    local function check(max_s)
      upd.info, upd.err = core.check_update(max_s)
      upd.at = os.time()
    end
    local seen = tonumber(reaper.GetExtState(SECTION, "update seen"):match("^(%d+)") or "")
    if not upd.at and (not seen or os.time() - seen > 86400) then check(6) end -- (once a day, when Settings opens)
    ImGui.Text(ctx, "ReaPersona " .. core.version())
    if upd.job then -- (downloading in the background)
      local n, why = core.update_poll(upd.job)
      if n then upd.done = "Updated to " .. upd.job.info.version .. " (" .. n .. " files): close this window and open ReaPersona again to use it."; upd.job = nil; say(upd.done)
      elseif n == false then upd.err, upd.job = why, nil
      else muted("Downloading " .. upd.job.info.version .. "...") end
    end
    if upd.done then
      ImGui.TextColored(ctx, C.YELLOW, upd.done)
    elseif upd.info and upd.info.newer and not upd.job then
      ImGui.TextColored(ctx, C.YELLOW, "ReaPersona " .. upd.info.version .. " is ready.")
      if primary("Update to " .. upd.info.version) then
        local r, why = core.update_start(upd.info)
        if r == "reapack" then upd.done = "ReaPack is updating ReaPersona: when it's done, close this window and open ReaPersona again."; say(upd.done)
        elseif r then upd.job, upd.err = r, nil
        else upd.err = why end
      end
    elseif upd.info then
      muted("Up to date (" .. "latest release " .. upd.info.version .. ", looked " .. os.date("%H:%M", upd.at) .. ").")
    end
    if upd.err then ImGui.TextColored(ctx, C.YELLOW, upd.err) end
    if ImGui.Button(ctx, "Check now##upd") then check(15); upd.done = nil end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "What's new##upd") then core.open_url("https://github.com/FmsJay/ReaPersona/blob/main/CHANGELOG.md") end
    card_end()
  end
  if sec == "remove" and card("set remove") then -- (removed with ReaPack alone, its startup block, actions and settings stayed behind. Review, 5.9.4)
    heading("Remove ReaPersona")
    muted("Puts My REAPER back, then takes out the startup block, ReaPersona's actions and its settings, and (REAPER restarting) its shortcut layers and toolbars. Your personas, presets and themes stay in their files. Then uninstall it in ReaPack.")
    ImGui.BeginDisabled(ctx, removing ~= nil)
    if ImGui.Button(ctx, "Remove ReaPersona...") and reaper.MB("Take ReaPersona out of REAPER?\n\n" ..
        "- My REAPER comes back: your own shortcuts, theme, layout and settings\n- the startup block, ReaPersona's actions and its settings go\n" ..
        "- REAPER closes (it asks first if anything is unsaved), the shortcut layers and toolbars come out of your keymap (backed up first), and REAPER opens again\n" ..
        "\nYour personas, presets and themes stay in their files. Last, uninstall ReaPersona in Extensions > ReaPack > Browse packages.", "ReaPersona: remove", 4) == 6 then
      reaper.SetExtState(SECTION, "follow projects", "0", true) -- (the project-following script stops)
      use(core.by_id("my_reaper") or styles[1])
      removing = true -- (the rest once My REAPER's windows are back: loop)
    end
    ImGui.EndDisabled(ctx)
    card_end()
  end
end

local adjust_out = false -- (Adjust in its own window)
local function adjust_page(sel)
  local lt = core.loaded_theme()
  if changed_on ~= lt then changed, changed_on = {}, lt end -- (tweaks made on another theme don't carry over)
  local current = core.loaded_theme() or ""
  if card("adj top") then
    heading("Adjust the theme in use")
    muted(current)
    if not adjust_out and ImGui.Button(ctx, "Pop out") then adjust_out = true end
    if not adjust_out then ImGui.SetItemTooltip(ctx, "This page in a window of its own, to keep open beside REAPER while you tweak.") ImGui.SameLine(ctx) end
    if ImGui.Button(ctx, "REAPER's theme adjuster") then reaper.Main_OnCommand(42234, 0) end
    ImGui.SetItemTooltip(ctx, "REAPER's own Theme Adjuster window (Options > Themes > Theme adjuster).")
    ImGui.TextWrapped(ctx, "Everything here changes the look right away. The theme's own settings and layouts are kept by REAPER as you go; colours are kept when you press Save my version.")
    if ImGui.Button(ctx, "Put this theme's settings in my persona##adjin") then -- (5.35)
      local b = core.new_block("themeset")
      if b.set then core.draft_add(bld.blocks, b); bld.active = true; say("In your persona: " .. core.themeset_words(b.set) .. ". Its theme is the one it applies to.")
      else say("This theme's settings are all its own defaults, and it has no layouts chosen: nothing to put in.") end
    end
    ImGui.SetItemTooltip(ctx, "The settings above that differ from the theme's own, and the layouts chosen below, go into the persona you're making. Used only with this theme; your theme's own settings aren't changed.")
    local tb = core.draft_get(bld.blocks, "themeset")
    if tb and core.safe_themeset(tb.set) then
      ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "In your persona: " .. core.themeset_words(core.safe_themeset(tb.set)))
      ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave out##adjout") then core.draft_clear(bld.blocks, "themeset") end
    end
    card_end()
  end
  if card("adj params") then
    heading("This theme's settings")
    local any, shown = false, 0
    for i = 0, 400 do
      local name, desc, val, def, mn, mx = reaper.ThemeLayout_GetParameter(i)
      if not name or name == "" then break end
      if not any then
        ImGui.SetNextItemWidth(ctx, 260)
        local _, f = ImGui.InputTextWithHint(ctx, "##pf", "search settings (a theme can have hundreds)", pfilter)
        pfilter = f
        any = true
      end
      local label = desc ~= "" and desc or name
      if (pfilter == "" and shown < 40) or (pfilter ~= "" and (label:lower():find(pfilter:lower(), 1, true) or name:lower():find(pfilter:lower(), 1, true))) then
        shown = shown + 1
        ImGui.SetNextItemWidth(ctx, 260)
        local ch, v = ImGui.SliderInt(ctx, label .. "##p" .. i, val, mn, mx)
        if ch then reaper.ThemeLayout_SetParameter(i, v, true); refresh() end
        if ImGui.IsItemClicked(ctx, 1) then reaper.ThemeLayout_SetParameter(i, def, true); refresh() end
        ImGui.SetItemTooltip(ctx, "Right-click: back to the theme's own value (" .. def .. ").")
      end
    end
    if any and pfilter == "" and shown >= 40 then ImGui.TextDisabled(ctx, "The first 40 shown: search to find the rest.") end
    if not any then muted("This theme has no adjustable settings of its own; its layouts and colours are below. (Merge can put its colours on a theme that has them.)") end
    card_end()
  end
  if card("adj layouts") then
    heading("Layouts")
    for s = 0, 40 do
      local ok, sec = reaper.ThemeLayout_GetLayout("seclist", s)
      if not ok or sec == "" then break end
      local _, desc = reaper.ThemeLayout_GetLayout(sec, -2)
      local _, cur = reaper.ThemeLayout_GetLayout(sec, -1)
      local names = {}
      for j = 0, 60 do local o, n = reaper.ThemeLayout_GetLayout(sec, j); if not o then break end if n ~= "" then names[#names + 1] = n end end
      if #names > 0 then
        ImGui.SetNextItemWidth(ctx, 260)
        if ImGui.BeginCombo(ctx, (desc ~= "" and desc or sec) .. "##l" .. sec, cur ~= "" and cur or "(theme default)") then
          if ImGui.Selectable(ctx, "(theme default)", cur == "") then reaper.ThemeLayout_SetLayout(sec, ""); refresh() end
          for _, n in ipairs(names) do if ImGui.Selectable(ctx, n, n == cur) then reaper.ThemeLayout_SetLayout(sec, n); refresh() end end
          ImGui.EndCombo(ctx)
        end
      end
    end
    card_end()
  end
  if card("adj colours") then
    heading("Colours")
    for _, c in ipairs(COLOURS) do
      local native = reaper.GetThemeColor(c[1], 0)
      if native >= 0 then
        local r, g, b = reaper.ColorFromNative(native)
        local ch, rgb = ImGui.ColorEdit3(ctx, c[2] .. "##c" .. c[1], (r << 16) | (g << 8) | b, ImGui.ColorEditFlags_NoInputs)
        if ch then
          local n = reaper.ColorToNative((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
          reaper.SetThemeColor(c[1], n, 0)
          changed[c[1]] = n
          refresh()
        end
      end
    end
    ImGui.Dummy(ctx, 0, 2)
    local n = 0
    for _ in pairs(changed) do n = n + 1 end
    ImGui.BeginDisabled(ctx, n == 0)
    if primary(n > 0 and ("Save my version (" .. n .. " colour" .. (n == 1 and "" or "s") .. ")") or "Save my version", accent_of(sel)) then
      local name, why = save_fork(sel, current)
      reaper.MB(name and ("Saved as " .. name .. ".\n\nIt's in this persona's Theme list now, and in use.") or ("Not saved: " .. tostring(why)), "ReaPersona", 0)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Undo colour changes") then
      for key in pairs(changed) do reaper.SetThemeColor(key, -1, 0) end
      changed = {}
      refresh()
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Every colour...") and not run_script("X-Raym Scripts/Theme/X-Raym_Theme color tweaker_ReaImGui.lua") then
      say("That needs X-Raym's Theme color tweaker: ReaPack, X-Raym Scripts.")
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages("Theme color tweaker") end
    end
    ImGui.SetItemTooltip(ctx, "All of the theme's colours, in X-Raym's colour tweaker.")
    card_end()
  end
end

local function theme_combo(label, key, allow_none)
  ImGui.SetNextItemWidth(ctx, math.min(420, ImGui.GetContentRegionAvail(ctx) - 180))
  if ImGui.BeginCombo(ctx, label, merge[key] ~= "" and merge[key] or "(none)") then
    if allow_none and ImGui.Selectable(ctx, "(none)", merge[key] == "") then merge[key] = "" end
    for _, f in ipairs(merge.list) do
      if (key ~= "base" and key ~= "graphics") or f:match("Zip$") then
        if ImGui.Selectable(ctx, f, f == merge[key]) then merge[key] = f end
      end
    end
    ImGui.EndCombo(ctx)
  end
end
local function merge_page(sel)
  merge.list = merge.list or theme_files()
  if merge.colours == "" then merge.colours = core.theme_for(sel) or "" end
  if card("merge") then
    heading("Merge themes")
    muted("Build a theme from the best parts of others. The layout theme gives the layout and every image (pick one with its own settings, like Default 7 or CSIX, and Adjust keeps working on the result); the colours theme gives the colours; graphics can swap in another theme's faders, knobs, meters or buttons where the layout theme has the same images. The result is a new theme of your own in ColorThemes, kept on this computer.")
    ImGui.Dummy(ctx, 0, 2)
    theme_combo("Layout and images from##mb", "base")
    theme_combo("Colours from##mc", "colours")
    local _, f = ImGui.Checkbox(ctx, "Fonts from the colours theme too", merge.fonts); merge.fonts = f
    theme_combo("Graphics from (optional)##mg", "graphics", true)
    if merge.graphics ~= "" then
      ImGui.Indent(ctx)
      for i, p in ipairs(PARTS) do
        if (i - 1) % 4 ~= 0 then ImGui.SameLine(ctx) end
        local _, v = ImGui.Checkbox(ctx, p, merge.parts[p] == true); merge.parts[p] = v
      end
      ImGui.Unindent(ctx)
    end
    ImGui.Dummy(ctx, 0, 2)
    ImGui.BeginDisabled(ctx, merge.base == "" or merge.colours == "")
    if primary("Make it, and use it", accent_of(sel)) then
      local parts = {}
      for _, p in ipairs(PARTS) do if merge.parts[p] then parts[#parts + 1] = p end end
      local name, why = core.merge(themes_dir .. merge.base, themes_dir .. merge.colours, merge.graphics ~= "" and themes_dir .. merge.graphics or nil, parts, merge.fonts)
      if name then
        reaper.OpenColorThemeFile(themes_dir .. name)
        local cur = core.current() -- (the theme goes on now, so it belongs to the style in use)
        add_fork(cur, name)
        merge.list = nil
        merge.msg = "Made " .. name .. ", in use, and in " .. cur.name .. "'s Theme list."
      else merge.msg = "Couldn't merge: " .. tostring(why) end
    end
    ImGui.EndDisabled(ctx)
    if merge.msg ~= "" then ImGui.TextWrapped(ctx, merge.msg) end
    ImGui.Dummy(ctx, 0, 2)
    muted("Most Stash themes carry no licence: share a merged theme only with its authors' permission.")
    card_end()
  end
end

local keys_for -- (the style the Shortcuts page shows: its own pick, else the one in use)
local function keys_page() shortcuts_page() end -- (5.30: the editor, defined with the persona being made)

local function dump(section, file)
  local out = {}
  for i = 0, 200000 do
    local id, name = reaper.CF_EnumerateActions(section, i, "")
    if not id or id <= 0 then break end
    out[#out + 1] = id .. "\t" .. name
  end
  core.write(here .. "/" .. file, table.concat(out, "\n") .. "\n")
  return #out
end
local function status_line(ok, text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, ok and C.GREEN or C.YELLOW); ImGui.Text(ctx, ok and "OK" or "Not yet"); ImGui.PopStyleColor(ctx)
  ImGui.SameLine(ctx); ImGui.Text(ctx, text)
end
local function check_page()
  if card("check installed") then
    heading("Installed")
    muted("Shortcut layers go into REAPER's keymap with REAPER closed (it reads its keymap at start): Home > Install and restart, after changing styles.json or importing a persona.")
    for _, st in ipairs(styles) do
      if (st.alt or 0) > 0 then
        local n = installed[st.alt] or 0
        local want = #core.keys_here(st.keys) -- (a key for the other system isn't installed here)
        status_line(n >= want, string.format("%s  (alt-%d): %d of %d keys", st.name, st.alt, n, want))
      end
    end
    local specs = {}
    for _, st in ipairs(styles) do for _, k in ipairs(st.midi_keys or {}) do specs[k[1]] = true end end
    local want = 0
    for _ in pairs(specs) do want = want + 1 end
    status_line(midi_installed >= want, string.format("MIDI editor keys: %d of %d", midi_installed, want))
    status_line(core.scripts_missing() == 0, "One-key actions registered: " .. (core.scripts_missing() == 0 and "yes" or (core.scripts_missing() .. " missing")))
    card_end()
  end
  if card("check install") then
    heading("Install the shortcuts")
    muted("REAPER reads its keymap when it starts, so the shortcut layers go in once, after adding or changing a persona. Two ways:")
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "In one step: Home > Install and restart (Windows, Mac or Linux; no Python needed). REAPER closes, the layers and the personas' toolbars go in, your keymap is backed up first, and REAPER opens again. By hand: close REAPER, run install_shortcuts.py in this folder, start REAPER.")
    if ImGui.SmallButton(ctx, "Show the folder") then core.open_url(core.here) end
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "Without restarting: make a keymap file, then in REAPER's Actions window open Key Map > Import... and pick it (choose to merge, not replace). Toolbars aren't included: personas keep your own toolbar.")
    if ImGui.SmallButton(ctx, "Make the keymap file") then
      local path, n, skipped = core.make_keymap()
      if not path then return reaper.MB("No keymap made: " .. tostring(skipped[1]), "ReaPersona", 0) end
      reaper.MB(n .. " shortcuts written to\n" .. path .. (#skipped > 0 and ("\n\nSkipped (no action here yet): " .. table.concat(skipped, ", ")) or "") ..
        "\n\nNext: Actions window > Key Map > Import..., pick that file, and choose to merge.", "ReaPersona", 0)
      reaper.Main_OnCommand(40605, 0)
    end
    card_end()
  end
  if card("check run") then
    heading("Check every persona against this REAPER")
    if ImGui.Button(ctx, "Check") then
      local bad = {}
      for _, st in ipairs(styles) do
        for _, k in ipairs(st.midi_keys or {}) do
          for _, name in ipairs(type(k[2]) == "table" and k[2] or { k[2] }) do
            if type(name) == "string" and not core.midi_action(name) then bad[#bad + 1] = st.name .. " MIDI " .. k[1] .. ": no action '" .. name .. "'" end
          end
        end
        for _, k in ipairs(st.keys or {}) do
          if type(k[2]) == "number" and (reaper.CF_GetCommandText(0, k[2]) or "") == "" then bad[#bad + 1] = st.name .. " " .. k[1] .. ": no action " .. k[2] end
        end
        for _, x in ipairs(st.feel or {}) do
          if x[1] == "toggle" and reaper.GetToggleCommandState(core.cmd_id(x[2])) < 0 then bad[#bad + 1] = st.name .. ": " .. tostring(x[2]) .. " has no on/off state" end
        end
      end
      local na, nb = dump(0, "actions_main.tsv"), dump(32060, "actions_midi.tsv")
      -- (REAPER's own MIDI editor bindings for the styles' keys, for the My REAPER fallback: only readable before those keys are installed)
      local d = midi_installed == 0 and (core.midi_defaults() .. " MIDI editor defaults saved; now install the shortcuts (Home).") or ""
      check_msg = (#bad == 0 and "Everything resolves." or table.concat(bad, "\n")) .. string.format("\n(Action lists saved for validate.py: %d main, %d MIDI editor.) ", na, nb) .. d
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Register actions again") then check_msg = core.ensure_scripts() .. " ReaPersona actions registered (scripts.json)." end
    ImGui.SetItemTooltip(ctx, "Writes and registers the one-key actions: 'ReaPersona - use <style>', 'next style', 'restore last style', and the MIDI key scripts. Put 'use' actions on a toolbar: they light up for the style in use.")
    if check_msg ~= "" then ImGui.TextWrapped(ctx, check_msg) end
    card_end()
  end
  if card("check anywhere") then
    heading("Switch from anywhere")
    muted("Actions list: 'ReaPersona - next style' cycles through the styles; 'ReaPersona - use <style>' picks one (toolbar buttons light up for the style in use). REAPER forgets the shortcut layer when it restarts; __startup.lua runs 'ReaPersona - restore last style' to put it back.")
    card_end()
  end
end

-- ---------------------------------------------------------------- the window: a bar on top, pages down the side
-- ---------------------------------------------------------------- Setup: everything ReaPersona can use, what's there, and one click for each
local daws_found -- (other DAWs on this computer, looked for once)
function drop_report(list) -- what came in, in a few lines (a pack's leftover files are one line, not one each)
  local lines, n, themes = {}, 0, {}
  for _, r in ipairs(list) do
    if r[1] ~= "skipped" and r[1] ~= "note" then n = n + 1 end
    if r[1] == "theme" then themes[#themes + 1] = r[2]:gsub("%.ReaperTheme.*$", "") end
    local head = r[1] == "skipped" and "Left out: " or r[1] == "note" and "Note: " or ("Added " .. ((r[1] == "style" or r[1] == "preset") and "persona" or r[1]) .. ": ")
    if #lines < 12 then lines[#lines + 1] = head .. r[2] .. (r[3] and ("  (" .. r[3] .. ")") or "") end
  end
  if #list > 12 then lines[#lines + 1] = "...and " .. (#list - 12) .. " more" end
  theme_list = nil
  if #themes > 0 then lines[#lines + 1] = "\nThemes are under Themes > Your themes, at the top (marked new)." end
  say(n .. " added" .. (#themes > 0 and (": " .. table.concat(themes, ", ")) or ""))
  if #list > 0 then reaper.MB(table.concat(lines, "\n"), "ReaPersona: added", 0) end
  local stages = {}
  for _, r in ipairs(list) do -- (a pack's fonts and scripts: installed only on a yes)
    if r.stage then stages[r.stage] = true end
    if r[2] == "fonts" and r.files and reaper.MB("Install the " .. #r.files .. " font" .. (#r.files == 1 and "" or "s") .. " the theme uses?\n\nThey go into your own account's fonts " ..
        "(no administrator needed). REAPER uses them after a restart.", "ReaPersona: fonts", 4) == 6 then
      local n, why = core.install_fonts(r.files)
      say(n and (n .. " font" .. (n == 1 and "" or "s") .. " installed. Restart REAPER to see them in the theme.") or ("Fonts not installed: " .. tostring(why)))
    elseif r[2] == "scripts" and r.files and reaper.MB("Add the pack's " .. #r.files .. " script" .. (#r.files == 1 and "" or "s") .. " (a theme adjuster, say) to REAPER's Actions list?\n\n" ..
        "They're the theme author's own scripts; they go in Scripts/ReaPersona theme scripts.", "ReaPersona: scripts", 4) == 6 then
      local names = core.register_scripts(r.files, r.stage)
      say(#names > 0 and ("In the Actions list now: " .. table.concat(names, ", ")) or "No scripts added.")
    end
  end
  for st in pairs(stages) do core.forget_staged(st) end
end
function install_theme_ui(th, st, pick) -- one click: download, take in (fonts and scripts on a yes), and with pick make it st's theme
  local got, why = core.install_theme(th)
  if not got then
    say("Couldn't install " .. th:gsub("%.ReaperTheme%a*$", "") .. ": " .. tostring(why) .. ". Its page opens instead.")
    local c = core.CATALOG[th]
    if c and c.url and c.url:match("^https?:") then core.open_url(c.url) end
    return
  end
  drop_report(got)
  if pick and st and reaper.file_exists(themes_dir .. th) then
    reaper.SetExtState(SECTION, "theme " .. st.id, th, true)
    if core.current() == st then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th) end
  end
end
local function setup_row(id, done, what, why, button, fn, tip)
  ImGui.TableNextRow(ctx)
  ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextColored(ctx, done and C.GREEN or C.YELLOW, done and "Done" or "To do")
  ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.PushTextWrapPos(ctx, 0); ImGui.Text(ctx, what)
  if why and why ~= "" then ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.MUTED); ImGui.Text(ctx, why); ImGui.PopStyleColor(ctx) end
  ImGui.PopTextWrapPos(ctx)
  ImGui.TableNextColumn(ctx)
  if button and fn and ImGui.SmallButton(ctx, button .. "##" .. id) then fn() end
  if tip then ImGui.SetItemTooltip(ctx, tip) end
end
local function get_url(u)
  if u == "builtin" then return reaper.MB("It comes with REAPER: it should already be in ColorThemes.", "ReaPersona", 0) end
  core.open_url(u)
end
local function shortcuts_state()
  local want, have = 0, 0
  for _, st in ipairs(styles) do if (st.alt or 0) > 0 then want = want + 1; if (installed[st.alt] or 0) >= #core.keys_here(st.keys) then have = have + 1 end end end
  return have, want
end
function try_theme(th)
  local back = trying and trying.back or core.loaded_theme()
  reaper.OpenColorThemeFile(themes_dir .. th)
  trying = { name = th, back = back, ends = reaper.time_precise() + 20 }
end
local function trial_over() -- (every loop, drawn or not; and when the window closes)
  if not trying or trying.ends > reaper.time_precise() then return end
  if trying.back then reaper.OpenColorThemeFile(themes_dir .. trying.back); say("Back to " .. trying.back:gsub("%.ReaperTheme%a*$", "") .. ".") end
  trying = nil
end
local function trying_bar() -- (under the top bar while a theme is on trial; goes back by itself when time's up)
  trial_over()
  if not trying then return end
  local left = trying.ends - reaper.time_precise()
  ImGui.SetCursorPosX(ctx, 16)
  ImGui.TextColored(ctx, C.YELLOW, "Trying " .. trying.name:gsub("%.ReaperTheme.*$", "") .. string.format(" (back in %d s)", math.ceil(left)))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Keep it##try") then say(trying.name .. " kept."); trying = nil; return end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Go back##try") then trying.ends = 0 end
end
local function setup_todo() -- (anything on Home still to do: the nav shows a dot, and the first run opens there)
  local have, want = shortcuts_state()
  return have < want or not core.startup_on()
end
local function build_themes()
  say("Building ReaPersona's themes...")
  local made, why = core.build_own_themes()
  theme_list = nil
  reaper.MB(made and (#made .. " themes built in ColorThemes, from your REAPER's own Default 7:\n\n" .. table.concat(made, "\n") ..
    "\n\nEach DAW persona uses its ReaPersona theme unless you've picked another.") or ("Not built: " .. tostring(why)), "ReaPersona", 0)
end
-- REAPER reads its keymap only when it starts: install_shortcuts.py waits for REAPER to close, installs, and starts it again. Without
-- Python the same install is planned here and a swap step puts it in: a batch file on Windows (5.14), a /bin/sh script on a Mac or
-- Linux (5.16; until then a Mac without Python got a keymap to import by hand, and no toolbars). core.stage_install.
function install_shortcuts(remove, extra, asked) -- (remove: Remove ReaPersona, which has asked already: the lines come out instead. extra: a persona that
  -- needs its layer now; asked: the question was already put)
  if not remove then
    if not asked and reaper.MB("REAPER closes (it asks first if anything is unsaved), the shortcuts install, and REAPER opens again: about 10 seconds.\n\n" ..
      "A backup of your keymap is made first.", "ReaPersona: install shortcuts", 1) ~= 1 then return end
    core.prepare_layers(extra) -- (5.29: layers for the personas this computer uses; shared where the keys are the same)
    if core.scripts_missing() > 0 then core.ensure_scripts() end -- (the scripts the keys run have to be registered first)
    if not reaper.file_exists(here .. "/midi_defaults.json") then core.midi_defaults() end
  end
  -- (on a Mac GetExePath is the folder holding REAPER.app, e.g. /Applications, not the app: matching ".app" in it found nothing and REAPER never came back)
  local d = reaper.GetExePath():gsub("\\", "/"):gsub("/+$", "")
  local exe = d .. (reaper.GetOS():find("^Win") and "/reaper.exe" or "/reaper") -- (Linux: the reaper binary beside it)
  if IS_MAC then
    exe = d:match("^(.-%.app)") or d .. "/REAPER.app"
    for _, a in ipairs({ d .. "/REAPER.app", d .. "/REAPER64.app" }) do if not d:match("%.app") and reaper.file_exists(a .. "/Contents/Info.plist") then exe = a; break end end
  end
  local projects, open = {}, {} -- (the projects open now, reopened with REAPER)
  for i = 0, 50 do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if fn ~= "" and not fn:find('"', 1, true) then projects[#projects + 1] = fn; open[#open + 1] = ' --open "' .. fn .. '"' end
  end
  local cfg = reaper.get_ini_file():gsub("\\", "/") -- (-cfgfile users get REAPER back on the same configuration)
  os.remove(here .. "/install_cancelled") -- (before the installer starts: an old one would stop it at its first look)
  if core.python() then
    local setup = #core.restart_pending() > 0 and not remove and " --apply-setup" or "" -- (your setup from your other computers, waiting for a restart)
    reaper.ExecProcess(core.py_quiet() .. ' "' .. here .. '/install_shortcuts.py" --after-reaper-quits --relaunch "' .. exe .. '" --cfgfile "' .. cfg .. '"' .. (remove and " --remove" or "") .. setup .. table.concat(open), -1) -- (-1: don't wait)
  else
    local step, why = core.stage_install({ remove = remove, pid = core.reaper_pid(), exe = exe, cfg = cfg, projects = projects })
    if not step then return reaper.MB("Nothing was installed: " .. tostring(why), "ReaPersona", 0) end
    if reaper.GetOS():find("^Win") then
      reaper.ExecProcess('cmd.exe /c ""' .. step:gsub("/", "\\") .. '""', -2) -- (-2: minimized, so it isn't closed halfway by mistake)
    else
      reaper.ExecProcess('/bin/sh "' .. step .. '"', -1) -- (it starts itself again detached from REAPER and returns; a full path: a Mac runs a bare name as nothing)
    end
  end
  reaper.Main_OnCommand(40004, 0) -- (File: Quit, with REAPER's own save prompts)
  quit_check = reaper.time_precise() + 4 -- (REAPER still running 4 s after: the quit was cancelled, and the installer is told)
end
remove_finish = function() -- (Remove ReaPersona, once My REAPER is back) -> false: the window closes
  local done = core.uninstall()
  reaper.MB(table.concat(done, "\n") .. "\n\nNext: REAPER closes (it asks first if anything is unsaved), the shortcut layers and toolbars come out of your keymap, and REAPER opens again." ..
    "\n\nLast: Extensions > ReaPack > Browse packages, right-click ReaPersona > Uninstall.", "ReaPersona: removed", 0)
  install_shortcuts(true)
  return false
end
local setup_job -- (Set up everything: one step per frame behind a progress window, so REAPER never looks frozen. 5.25)
local function setup_all()
  if reaper.MB("Set up everything ReaPersona can do from here?\n\n" ..
    "- add the startup line that brings your persona back when REAPER starts\n" ..
    "- offer the smooth playhead / smooth scrolling extensions\n- then the shortcut install: REAPER closes and opens again (about 10 seconds), which also loads new extensions\n\n" ..
    "(ReaPersona's own DAW themes are under Advanced, below.)", "ReaPersona: set up", 4) ~= 6 then return end
  local steps = { { "Adding the startup line", function(done)
    if not core.startup_on() then done[#done + 1] = core.add_startup() and "Startup line added" or "Startup line not added" end
  end } }
  for key, x in pairs(core.EXTENSIONS) do
    if core.ext_here(key) and core.extension_state(key) == "missing" and core.can_install(key) then
      steps[#steps + 1] = { "Offering " .. x.name, function(done)
        if reaper.MB("Install " .. x.name .. "? (" .. x.why .. ")", "ReaPersona", 4) == 6 and core.install_extension(key) then done[#done + 1] = x.name .. " installed (restart REAPER)" end
      end }
    end
  end
  steps[#steps + 1] = { "Installing the shortcuts (REAPER restarts)", function(done)
    reaper.MB((#done > 0 and (table.concat(done, "\n") .. "\n\n") or "") .. "Last step: the shortcuts.", "ReaPersona: set up", 0)
    install_shortcuts()
  end }
  setup_job = { steps = steps, i = 0, done = {} }
end
local function setup_progress() -- (drawn every frame while Set up everything runs; a step runs only after the window has been shown)
  if not setup_job then return end
  local j = setup_job
  ImGui.OpenPopup(ctx, "ReaPersona: setting up")
  local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx))
  ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Always, 0.5, 0.5) -- (over the middle of ReaPersona's window)
  if ImGui.BeginPopupModal(ctx, "ReaPersona: setting up", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    local s = j.steps[j.i + 1]
    ImGui.Text(ctx, (s and s[1] or "Done") .. "...")
    ImGui.ProgressBar(ctx, j.i / #j.steps, 360, 0, j.i .. " of " .. #j.steps)
    muted("Each step takes a moment: leave REAPER open until this closes.")
    ImGui.EndPopup(ctx)
  end
  if not j.shown then j.shown = true; return end
  j.i = j.i + 1
  local s = j.steps[j.i]
  if s then local ok, err = pcall(s[2], j.done); if not ok then j.done[#j.done + 1] = s[1] .. ": " .. tostring(err) end end
  if j.i >= #j.steps then setup_job = nil end
  j.shown = false -- (the next step after the window shows the new one)
end
local function setup_page()
  if reaper.GetExtState(SECTION, "welcomed") == "" and card("welcome") then -- (the first run: pick your DAW, it's in use straight away)
    heading("Which DAW are you coming from?", 20)
    muted("Pick it and REAPER takes on its look and layout now, and its shortcuts once they're installed (Getting started, below). You can switch any time, and Back to My REAPER puts everything back. " ..
      "If you'd already set REAPER up your own way, that setup is first kept as a persona of its own, \"My REAPER as it was\".")
    local n = 0
    for _, st in ipairs(styles) do
      if st.kind ~= "theme" and (st.alt or 0) > 0 and not st.user and not st.preset and st.id ~= "base_reaper" then
        if n % 5 ~= 0 then ImGui.SameLine(ctx) end
        n = n + 1
        if primary(st.name .. "##welcome", accent_of(st)) then
          selected = st.id; use(st); reaper.SetExtState(SECTION, "welcomed", "1", true)
          core.set_favourite("my_reaper", true); core.set_favourite(st.id, true) -- (your setup and the DAW you came from, on Favourites. 5.27)
          local kept = core.by_id(reaper.GetExtState(SECTION, "first setup"))
          if setup_todo() then say(st.name .. " in use." .. (kept and (" Your own setup is kept as " .. kept.name .. ".") or "") .. " Next: install its shortcuts below.") end
        end
      end
    end
    if ImGui.SmallButton(ctx, "I'll pick later") then reaper.SetExtState(SECTION, "welcomed", "1", true) end
    card_end()
  end
  local have0, want0 = shortcuts_state()
  if reaper.GetExtState(SECTION, "onboarded") == "" and core.current().id ~= "my_reaper" and have0 == want0 and core.startup_on() then
    reaper.SetExtState(SECTION, "onboarded", "1", true) -- (steps 1-3 done: the card goes; step 4 is optional. Review, 5.14)
  end
  if reaper.GetExtState(SECTION, "onboarded") == "" and card("first steps") then -- (5.14: the first run, step by step, until it's done or hidden)
    heading("Getting started")
    local have, want = have0, want0
    local steps = {
      { core.current().id ~= "my_reaper", "1. Pick the DAW you're coming from", "Its look and feel straight away, and its shortcuts once they're installed (step 2). Back to My REAPER (top) puts yours back.", "Pick one", function() go("DAWs") end },
      { have == want, "2. Install the shortcuts", "REAPER reads its keymap only when it starts: it closes, the persona layers go in (your keymap is backed up first) and it opens again.", "Install and restart", function() install_shortcuts() end },
      { core.startup_on(), "3. Bring your persona back when REAPER starts", "One block in Scripts/__startup.lua.", "Add it", function() local ok, why = core.add_startup(); say(ok and "Startup line added." or tostring(why)) end },
      { core.sync_folder() ~= "" and true or "optional", "4. More than one computer? (optional)", "Save your setup to a file, or keep them the same through a shared folder.", "Set it up", function() go("Settings") end },
    }
    if ImGui.BeginTable(ctx, "first steps", 3, ImGui.TableFlags_SizingStretchProp) then
      ImGui.TableSetupColumn(ctx, "state", ImGui.TableColumnFlags_WidthFixed, 56)
      ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      for i, s in ipairs(steps) do setup_row("step" .. i, s[1], s[2], s[3], not s[1] and s[4] or nil, s[5]) end
      ImGui.EndTable(ctx)
    end
    if ImGui.SmallButton(ctx, "How it works (F1)##first") then go("Guide") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Hide these steps##first") then reaper.SetExtState(SECTION, "onboarded", "1", true) end
    card_end()
  end
  if card("setup top") then
    heading("Set up ReaPersona")
    muted("What ReaPersona can use, whether it's there, and one click to get each. Drag files onto this window any time to add them: themes (.ReaperThemeZip, .ReaperTheme or the theme pack .zip as downloaded), toolbars (.ReaperMenu), keymaps (.ReaperKeyMap, become a persona of their own), and shared personas and presets.")
    if primary("Set up everything") then setup_all() end
    card_end()
  end
  if card("setup computers") then -- (another computer of yours: its setup in one click, or kept the same through a folder. 5.12.1)
    heading("Your other computers")
    local syncing = core.sync_folder() ~= ""
    muted(syncing and ("Syncing through " .. core.sync_folder() .. ": your personas, presets and settings stay the same on every computer that uses this folder.")
      or "Using ReaPersona on another computer too? Load the setup you saved there, or keep them the same through a shared folder (Syncthing, Google Drive, Dropbox...).")
    if ImGui.Button(ctx, "Save, load or sync your setup##home") then go("Settings") end
    ImGui.SetItemTooltip(ctx, "Settings > Sync: Save to a file, Load a file, and syncing through a folder.")
    card_end()
  end
  if card("setup core") then
    heading("ReaPersona")
    if ImGui.BeginTable(ctx, "setup", 3, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
      ImGui.TableSetupColumn(ctx, "state", ImGui.TableColumnFlags_WidthFixed, 56)
      ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      local js = reaper.JS_Window_Find ~= nil
      setup_row("js", js, "js_ReaScriptAPI", "Docks the Media Explorer where each DAW keeps its browser, and the file dialogs.", not js and "Get it" or nil,
        function() if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages("js_ReaScriptAPI") else core.open_url("https://forum.cockos.com/showthread.php?t=212174") end end)
      local rp = reaper.ReaPack_BrowsePackages ~= nil
      setup_row("rp", rp, "ReaPack", "Installs the smooth playhead and keeps ReaPersona up to date.", not rp and "Get it" or nil, function() core.open_url("https://reapack.com/") end)
      local have, want = shortcuts_state()
      local layers_used = {}
      for _, st in ipairs(styles) do if (st.alt or 0) > 0 then layers_used[st.alt] = true end end
      local nl = 0; for _ in pairs(layers_used) do nl = nl + 1 end
      setup_row("keys", have == want, "Shortcut layers: " .. have .. " of " .. want .. " personas installed (" .. nl .. " of REAPER's 16 layers in use)",
        "Each persona's keys. REAPER restarts to load them (about 10 seconds). REAPER has 16 layers, so ReaPersona gives them to the personas you use (favourites, the one in use, your own); a persona without one gets it the first time it's used, and personas with the same keys share one.", have < want and "Install and restart" or "Reinstall", install_shortcuts)
      setup_row("start", core.startup_on(), "Brings your persona back when REAPER starts", "One block in Scripts/__startup.lua.", not core.startup_on() and "Add it" or nil,
        function() local ok, why = core.add_startup(); say(ok and "Startup line added." or tostring(why)) end)
      local ext_keys = {}
      for key in pairs(core.EXTENSIONS) do if core.ext_here(key) then ext_keys[#ext_keys + 1] = key end end -- (Windows-only ones only on Windows)
      table.sort(ext_keys)
      for _, key in ipairs(ext_keys) do
        local x, s = core.EXTENSIONS[key], core.extension_state(key)
        setup_row("ext" .. key, s == "on" or s == "off", x.name .. (s == "restart" and " (restart REAPER to load it)" or ""), x.why .. " Recommended by the DAW personas.",
          s == "missing" and core.can_install(key) and "Install" or nil, function() install_ext(key) end)
      end
      ImGui.EndTable(ctx)
    end
    -- (5.25, James: setting everything up shouldn't build ReaPersona's own themes: the themes by other people look closer, and building
    -- them held REAPER. Here for whoever wants them)
    if ImGui.CollapsingHeader(ctx, "Advanced: ReaPersona's own DAW themes##advthemes") then
      if ImGui.BeginTable(ctx, "setup adv", 3, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, "state", ImGui.TableColumnFlags_WidthFixed, 56)
        ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
        ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      local py = core.python()
      setup_row("py", py ~= nil, "Python 3" .. (py and (" (" .. py .. ")") or ""), "Builds ReaPersona's own themes. The shortcut install doesn't need it.",
        not py and "Get it" or nil, function() core.open_url("https://www.python.org/downloads/") end)
      if py then
        local job, jwhy = core.libs_job() -- (the background install: running, or how it just ended)
        if job == "ok" then say("Pillow and numpy are installed: Build makes ReaPersona's themes.")
        elseif job == "failed" then reaper.MB("Pillow and numpy weren't installed: " .. tostring(jwhy), "ReaPersona", 0) end
        local libs = job ~= "running" and core.python_libs()
        setup_row("libs", libs, "Pillow and numpy for Python" .. (job == "running" and " (installing...)" or ""),
          job == "running" and "pip is downloading them in the background (a minute or two). Keep working: this says when they're in."
            or "The image tools the theme builder uses, in a folder of ReaPersona's own (ReaPersona/venv), so your system's Python isn't changed.",
          not libs and job ~= "running" and "Install them" or nil, function()
          if reaper.MB("ReaPersona makes a Python environment of its own in its folder (venv) and pip installs Pillow and numpy into it, " ..
            "in the background: REAPER keeps working, and this row says when they're in (a minute or two).", "ReaPersona", 1) ~= 1 then return end
          local ok, why = core.install_python_libs()
          if ok then say("Installing Pillow and numpy in the background...") else reaper.MB("Not started: " .. tostring(why), "ReaPersona", 0) end
        end)
      end
      local n, total = core.own_themes_built()
      setup_row("own", n == total, "ReaPersona's own themes: " .. n .. " of " .. total .. " built", "A theme per DAW in its colours, made from your REAPER's own Default 7. They're approximations: the themes by other people below can look closer to the real DAWs.",
        py and core.python_libs() and (n == total and "Rebuild" or "Build") or nil, build_themes)
        ImGui.EndTable(ctx)
      end
    end
    card_end()
  end
  if card("setup import") then
    heading("Import from another DAW")
    muted("What ReaPersona can take from a DAW on this computer. Cubase/Nuendo key commands and Ableton Live themes can be read; the others keep their settings in files no other program can read (or don't let you change keys), so their persona is the import.")
    daws_found = daws_found or core.detect_daws()
    local any = false
    for i, d in ipairs(daws_found) do
      if d.found then
        any = true
        local st = core.by_id(d.style)
        ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, d.name .. " is on this computer")
        ImGui.SameLine(ctx)
        if st and ImGui.SmallButton(ctx, "Use its persona##imp" .. i) then use(st) end
        if d.can.keys and reaper.file_exists(d.can.keys) then
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Import your key commands##impk" .. i) then
            local s, missed = core.import_cubase_keys(d.can.keys)
            if s then ensure_new = true; selected = s.id end
            reaper.MB(s and (s.name .. " is in Personas (shortcut layer alt-" .. s.alt .. "; install the shortcuts on Home). " .. #missed .. " of your assignments are for commands ReaPersona doesn't map yet.") or ("Not imported: " .. tostring(missed)), "ReaPersona", 0)
          end
        end
      end
    end
    if not any then muted("No other DAW found here. You can still import from files copied from another computer:") end
    if ImGui.Button(ctx, "Cubase / Nuendo Key Commands.xml...") then
      local ok, p = reaper.GetUserFileNameForRead("", "Cubase or Nuendo Key Commands.xml", "*.xml")
      if ok then
        local s, missed = core.import_cubase_keys(p)
        if s then ensure_new = true; selected = s.id end
        reaper.MB(s and (s.name .. " is in Personas (install the shortcuts on Home).") or ("Not imported: " .. tostring(missed)), "ReaPersona", 0)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Ableton Live theme (.ask)...") then
      local ok, p = reaper.GetUserFileNameForRead("", "An Ableton Live theme", "*.ask")
      if ok then
        local name, why = core.import_live_theme(p)
        if name then
          local made, bwhy = core.build_own_themes()
          local file = core.own_theme_file(name)
          if made then add_fork(core.by_id("ableton"), file) end
          reaper.MB(made and (file .. " is built, and in Ableton Live's Theme list.") or ("Its colours are saved; building the theme needs Python: " .. tostring(bwhy)), "ReaPersona", 0)
          theme_list = nil
        else reaper.MB("Not imported: " .. tostring(why), "ReaPersona", 0) end
      end
    end
    card_end()
  end
  if card("setup themes") then
    heading("Themes by other people")
    muted("Made by REAPER's theme authors in each DAW's likeness. They can't ship with ReaPersona, so Install downloads one from where its author shares it and takes it in, fonts and extras too. Get it opens a page that needs your browser (paid, or a sign-in): download there, then drop the file onto this window.")
    if ImGui.BeginTable(ctx, "setup themes", 3, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
      ImGui.TableSetupColumn(ctx, "state", ImGui.TableColumnFlags_WidthFixed, 56)
      ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      local shown = {}
      for _, st in ipairs(styles) do
        for _, th in ipairs(st.themes or {}) do
          local c = core.CATALOG[th]
          if c and c.url ~= "reapersona" and c.url ~= "builtin" and not c.from and not shown[th] then
            shown[th] = true
            local have = reaper.file_exists(themes_dir .. th)
            setup_row("t" .. th, have, st.name .. ": " .. th:gsub("%.ReaperThemeZip$", ""), (c.by and ("by " .. c.by) or "") .. (c.note and ((c.by and ", " or "") .. c.note) or ""),
              not have and (core.can_install_theme(th) and "Install" or "Get it") or nil,
              function() if core.can_install_theme(th) then install_theme_ui(th, st, false) else get_url(c.url) end end, c.url)
          end
        end
      end
      local tb = reaper.file_exists(core.here .. "/toolbars/CubeX_Toolbar1.ReaperMenu")
      setup_row("tbcube", tb, "Cubase toolbars (from CubicPack3)", "Its .ReaperMenu files: drop the CubicPack3 zip here.", not tb and "Get it" or nil,
        function() core.open_url("https://stash.reaper.fm/theme/2310/CubicPack3.zip") end)
      local tl = reaper.file_exists(core.here .. "/toolbars/CFLogic_Toolbar1.ReaperMenu")
      setup_row("tblogic", tl, "Logic toolbars (from CLogic)", "Its .ReaperMenu files: drop the CLogic zip here.", not tl and "Get it" or nil,
        function() core.open_url("https://stash.reaper.fm/theme/1932/CLogic.zip") end)
      ImGui.EndTable(ctx)
    end
    card_end()
  end
end

-- ---------------------------------------------------------------- Browse: the REAPER Stash (newest, most popular), and ReaPack
local br = { cat = "Themes", sort = "nd", q = "", page = 1, items = nil, msg = "" }
local function browse_load()
  local items, why = core.stash_list(br.cat, br.sort, br.q, br.page)
  br.items, br.msg = items, items and "" or tostring(why)
end
local function browse_page()
  if card("br top") then
    heading("Browse")
    muted("The REAPER Stash, where most themes, key maps and custom actions are shared. Add downloads one and takes it in like a dropped file; anything that needs a sign-in opens its page instead.")
    for i, c in ipairs(core.STASH_CATS) do
      if i > 1 then ImGui.SameLine(ctx) end
      if ImGui.RadioButton(ctx, c[2] .. "##bc" .. i, br.cat == c[1]) then br.cat, br.page, br.items, br.msg = c[1], 1, nil, "" end
    end
    for i, s in ipairs(core.STASH_SORTS) do
      if i > 1 then ImGui.SameLine(ctx) end
      if ImGui.RadioButton(ctx, s[2] .. "##bs" .. i, br.sort == s[1]) then br.sort, br.page, br.items, br.msg = s[1], 1, nil, "" end
    end
    ImGui.SetNextItemWidth(ctx, 240)
    local enter, q = ImGui.InputTextWithHint(ctx, "##bq", "search, e.g. Pro Tools", br.q, ImGui.InputTextFlags_EnterReturnsTrue)
    br.q = q
    ImGui.SameLine(ctx)
    if primary("Search") or enter then br.page = 1; browse_load() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Themes on ReaPack") then
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages("theme") else core.open_url("https://reapack.com/") end
    end
    ImGui.SetItemTooltip(ctx, "ReaPack's browser, showing themes you can install and keep updated (ReaTeam Themes and others).")
    card_end()
  end
  if br.items == nil and br.msg == "" then
    if br.wait then br.wait = nil; browse_load() else br.wait = true; muted("Loading the REAPER Stash... (REAPER waits for it for a moment)"); return end
  end
  if br.msg ~= "" then ImGui.TextColored(ctx, C.YELLOW, br.msg) end
  if br.items and card("br list") then
    if #br.items == 0 then muted("Nothing found.") end
    if ImGui.BeginTable(ctx, "br", 4, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
      ImGui.TableSetupColumn(ctx, "name", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "when", ImGui.TableColumnFlags_WidthFixed, 72)
      ImGui.TableSetupColumn(ctx, "views", ImGui.TableColumnFlags_WidthFixed, 100)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      for i, it in ipairs(br.items) do
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, it.title)
        ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.MUTED, it.date)
        ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.MUTED, it.views and (it.views .. " views") or "")
        ImGui.TableNextColumn(ctx)
        if it.file and ImGui.SmallButton(ctx, "Add##ba" .. i) then
          local res = core.stash_get(it)
          if res then drop_report(res) else core.open_url(it.page); say("Opened its page: download it there, then drop it here.") end
        end
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Page##bp" .. i) then core.open_url(it.page) end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.BeginDisabled(ctx, br.page <= 1)
    if ImGui.Button(ctx, "Previous") then br.page = br.page - 1; browse_load() end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx); ImGui.Text(ctx, "Page " .. br.page); ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, #br.items < 48)
    if ImGui.Button(ctx, "Next") then br.page = br.page + 1; browse_load() end
    ImGui.EndDisabled(ctx)
    card_end()
  end
end

-- Making a persona (5.27; James: "all the blocks should move and just be based on the tabs so you can choose more granularly ... Blocks are
-- built automatically from all settings, then constructed into the persona. More tabs for each type of block"). The persona being made holds
-- one block per slot (core.block_slot); each tab chooses what fills its slots, line by line: Shortcuts, Mouse, Layout, Themes, Colours,
-- Project and REAPER. The bar over every tab shows it, names it and saves it. Edit on any persona's page starts from that one.
bld = { blocks = {}, name = "", id = nil, msg = "", colour = nil, back = nil, active = false }
function bld_load(st) -- edit a persona: one you built is saved over itself; any other (a DAW, My REAPER, a saved setup) is saved as a new one of yours
  local mine = (st.blocks and st.user and st.kind == "built") or st.id == "my_reaper" -- (My REAPER is yours too: saved over, as its look. 5.28)
  bld.blocks = core.blocks_of(st)
  bld.name, bld.id, bld.msg, bld.active = mine and st.name or "", mine and st.id or nil, "", true
  bld.from = not mine and st.name or nil -- (unnamed, it's saved as "<this> - custom")
  local c = core.draft_get(bld.blocks, "colour")
  bld.colour = c and tonumber((c.hex or ""):gsub("#", ""), 16) or nil
  say("Editing " .. st.name .. ": change its shortcuts, mouse, layout, theme, colours, project or REAPER settings on their tabs. " ..
    (mine and "Save changes from the bar at the top." or ("Save from the bar at the top makes a new persona (" .. st.name .. " stays as it is).")))
end
local function bld_default_name() -- the name it gets when you don't give one
  local keys = core.draft_get(bld.blocks, "keys")
  local from = bld.from or (keys and keys.id ~= "my_reaper" and (core.by_id(keys.id) or {}).name)
  return core.custom_name(from or "My REAPER")
end
function bld_new() -- an empty persona to make from the tabs
  bld.blocks, bld.name, bld.id, bld.msg, bld.active, bld.colour, bld.from = {}, "", nil, "", true, nil, nil
  say("Making a new persona: choose its shortcuts, mouse, layout, theme, colours and so on on their tabs. The bar at the top shows it; name it and Save there.")
end
function in_persona(b, what) -- a block into its slot of the persona being made
  local _, replaced = core.draft_add(bld.blocks, b)
  bld.active = true
  say(what .. (replaced and " replaces what was" or " is") .. " in your persona" .. (bld.name ~= "" and (" (" .. bld.name .. ")") or "") .. ". Save it from the bar at the top.")
end
function persona_row(st) -- on a persona's page: its parts into the persona being made, each into its own slot
  local has = {}
  for _, f in ipairs(st.feel or {}) do has[core.aspect_of(f)] = true end
  for _, k in ipairs(core.keys_here(st.keys)) do if core.is_wheel(k[1]) then has.mouse = true end end
  local th = core.theme_for(st)
  th = th and reaper.file_exists(themes_dir .. th) and th or nil
  if #(st.keys or {}) == 0 and not next(has) and not th then return end
  ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.MUTED, "Use in my persona:")
  local function part(label, blocks, what)
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, label .. "##inp" .. st.id) then
      for _, b in ipairs(blocks()) do core.draft_add(bld.blocks, b) end
      bld.active = true
      say(what .. " in your persona. Fine-tune it on the Shortcuts, Mouse, Layout and Themes tabs; Save from the bar at the top.")
    end
  end
  part("All of it", function() return core.split_blocks({ core.new_block("daw", st.id) }) end, "All of " .. st.name .. " is")
  if #(st.keys or {}) > 0 then part("Shortcuts", function() return { core.keys_block(st.id) } end, st.name .. "'s shortcuts are") end
  if has.mouse then part("Mouse", function() return { core.new_block("mouse", st.id) } end, st.name .. "'s mouse is") end
  for _, x in ipairs(core.ASPECTS) do
    if has[x[1]] and x[1] ~= "mouse" then part(x[4], function() return { core.new_block("feel", st.id, x[1]) } end, st.name .. "'s " .. x[4]:lower() .. " is") end
  end
  if th then part("Theme", function() return { core.new_block("theme", th) } end, th:gsub("%.ReaperTheme%a*$", "") .. " is") end
end
local function bld_blocks() -- what's saved: built in a fixed order, with your own keys when no shortcuts were chosen (they carry your startup scripts)
  local blocks = core.draft_order(bld.blocks)
  if not core.draft_get(blocks, "keys") then table.insert(blocks, 1, core.keys_block("my_reaper")) end
  return blocks
end
local function bld_save() -- -> the saved persona, or nil (bld.msg says why)
  if bld.id == "my_reaper" then -- (My REAPER: everything but its keys becomes its look, on every computer; the look before is kept as a version)
    local st = core.build_style(bld_blocks(), "My REAPER", "built_try")
    if not st then bld.msg = "Not saved."; return end
    core.save_look(core.look_from_style(st))
    if reaper.GetExtState(SECTION, "style") == "my_reaper" then core.use(core.by_id("my_reaper")) end
    local keys = core.draft_get(bld.blocks, "keys")
    bld.msg = "My REAPER is saved: its layout, mouse, theme and colours are your look on every computer (Earlier versions, on its page, puts one back)." ..
      ((keys and keys.id ~= "my_reaper") and " Its shortcuts are your own keymap, so another persona's keys don't go into it." or "")
    say(bld.msg)
    return core.by_id("my_reaper")
  end
  if bld.name:match("^%s*$") then bld.name = bld_default_name() end -- (never over a DAW: a new persona, "<DAW> - custom" unless you name it)
  local st, install = core.save_built(bld_blocks(), bld.name, bld.id)
  if st then
    bld.id, selected, ensure_new = st.id, st.id, true
    if bld.back or reaper.GetExtState(SECTION, "style") == st.id then core.use(st); bld.back = nil end -- (the persona in use: its changes now)
    bld.msg = st.name .. " is saved: it's in Personas > Your personas." .. (install and " Install its shortcuts on Home (REAPER restarts) to use its keys." or "")
    say(bld.msg)
    return st
  end
  bld.msg = "Not saved: " .. tostring(install)
end
local function draft_strip() -- the persona being made, over every tab
  if not bld.active and #bld.blocks == 0 then return end
  local titles = {}
  for _, b in ipairs(core.draft_order(bld.blocks)) do if b.kind ~= "colour" then titles[#titles + 1] = core.block_title(b) end end
  if card("draft strip") then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, C.ACCENT, bld.id and ("Editing " .. bld.name) or ("Making " .. (bld.name ~= "" and bld.name or bld_default_name())))
    ImGui.SameLine(ctx)
    ImGui.TextWrapped(ctx, #titles > 0 and table.concat(titles, "  ·  ") or "Nothing chosen yet: pick its shortcuts, mouse, layout, theme, colours or project on their tabs (your own setup fills in the rest).")
    ImGui.SetNextItemWidth(ctx, 220 * UI)
    local _, n = ImGui.InputTextWithHint(ctx, "##stripname", bld_default_name(), bld.name); bld.name = n
    ImGui.SetItemTooltip(ctx, "Its name. Left empty, it's saved as the name shown here.")
    ImGui.SameLine(ctx)
    local ch, col = ImGui.ColorEdit3(ctx, "##stripcol", bld.colour or 0x3A86FF, ImGui.ColorEditFlags_NoInputs)
    if ch then bld.colour = col; core.draft_add(bld.blocks, core.new_block("colour", string.format("#%06X", col))) end
    ImGui.SetItemTooltip(ctx, "Its colour in ReaPersona: its card, buttons and badge.")
    ImGui.SameLine(ctx)
    if primary(bld.id and "Save changes##strip" or "Save as new##strip") then bld_save() end
    ImGui.SetItemTooltip(ctx, bld.id and ("Saves over " .. bld.name .. ", which you made.") or "A new persona of yours: the DAWs and personas it came from stay as they are.")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Try it##strip") then
      local st, install = core.build_style(bld_blocks(), bld.name ~= "" and bld.name or "Your persona", "built_try")
      if st then
        if install then st.alt = 0 end -- (keys from several DAWs need their layer installed: the trial keeps your own keys)
        bld.back = bld.back or core.current().id
        core.use(st)
        say("Trying it" .. (install and " (with your own shortcuts until it's saved and installed)" or "") .. ". Save it, or Go back.")
      else say("Can't try it: " .. tostring(install)) end
    end
    if bld.back then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Go back##strip") then local back = core.by_id(bld.back); bld.back = nil; if back then use(back) end end
      ImGui.SetItemTooltip(ctx, "Back to " .. ((core.by_id(bld.back) or {}).name or "the persona you had") .. ", exactly as it was.")
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Stop##strip") then bld.blocks, bld.name, bld.id, bld.msg, bld.active, bld.colour, bld.from = {}, "", nil, "", false, nil, nil end
    ImGui.SetItemTooltip(ctx, "Stop making it: nothing is saved, and personas you have stay as they are.")
    if bld.msg ~= "" then muted(bld.msg) end
    card_end()
  end
end

-- One slot on its tab: which persona it comes from (or leave it as it is), then each line it sets, to untick.
local function sources(test) -- every persona (DAWs, yours, saved setups) that has something for this slot
  local out = {}
  for _, list in ipairs({ styles, core.presets }) do
    for _, st in ipairs(list) do if st.kind ~= "theme" and st.id ~= "built_try" and test(st) then out[#out + 1] = st end end
  end
  return out
end
local function entry_line(e, b)
  local ch, v = ImGui.Checkbox(ctx, "##on" .. e.slot, not e.off)
  if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
  ImGui.SetItemTooltip(ctx, e.off and "Tick to put this back in the persona" or "Untick to leave this out of the persona")
  ImGui.SameLine(ctx)
  local text = (e.key and (keyname(e.key) .. "  ") or "") .. tostring(e.label)
  if e.off then ImGui.TextColored(ctx, C.MUTED, text .. "   (left out)")
  elseif e.kind == "feel" and not core.aspect_on(core.aspect_of(e.entry)) then ImGui.TextColored(ctx, C.YELLOW, text .. "   (off in Settings > Personas)")
  else ImGui.Text(ctx, text) end
end
local function slot_card(id, title, tip, slot, list, make, leave, section_of)
  if not card("slot " .. id) then return end
  heading(title, 16)
  if tip then muted(tip) end
  ImGui.Indent(ctx, IND * UI)
  local b = core.draft_get(bld.blocks, slot)
  local from = b and b.id and core.by_id(b.id)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  if ImGui.BeginCombo(ctx, "##from" .. id, b and (from and from.name or core.block_title(b)) or leave) then
    if ImGui.Selectable(ctx, leave .. "##leave" .. id, b == nil) then core.draft_clear(bld.blocks, slot); bld.active = true end
    for _, st in ipairs(list) do
      if ImGui.Selectable(ctx, st.name .. "##" .. id .. st.id, b ~= nil and b.id == st.id) then core.draft_add(bld.blocks, make(st)); bld.active = true end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "Loads that persona's or DAW's settings for this part only. Choosing here starts a new persona if you're not making one (the bar at the top).")
  if b then
    local lines, keys, sections, order = core.build_preview({ b })[1], {}, {}, {}
    for _, e in ipairs(lines) do
      if e.entry and e.entry[1] == "mouse" and not core.for_os(e.entry[2]) then -- (the other system's mouse lines: not here)
      elseif section_of then
        local s = section_of(e)
        if not sections[s] then sections[s] = {}; order[#order + 1] = s end
        table.insert(sections[s], e)
      elseif e.kind == "key" or e.kind == "midi" then keys[#keys + 1] = e
      else entry_line(e, b) end
    end
    for _, s in ipairs(order) do ImGui.TextColored(ctx, C.MUTED, s); for _, e in ipairs(sections[s]) do entry_line(e, b) end end
    if #keys > 0 and (slot ~= "keys" or ImGui.TreeNode(ctx, #keys .. " shortcuts##k" .. id)) then
      for _, e in ipairs(keys) do entry_line(e, b) end
      if slot == "keys" then ImGui.TreePop(ctx) end
    end
    if #lines == 0 then muted("Nothing of this kind there.") end
  end
  ImGui.Unindent(ctx, IND * UI)
  card_end()
end
local function has_aspect(st, a) for _, f in ipairs(st.feel or {}) do if core.aspect_of(f) == a then return true end end return false end
local function has_mouse(st)
  if has_aspect(st, "mouse") then return true end
  for _, k in ipairs(core.keys_here(st.keys)) do if core.is_wheel(k[1]) then return true end end
  return false
end
-- Shortcuts (5.30; James: "add individually ones from other daws or personas into your own persona ... make your own based on custom
-- actions and change keybinds of any already in there ... All keybinds should show here, the most commonly used first ... Can filter by
-- specific action types or scripts"). Your persona's keys, each to leave out, change (press the new keys) or remove; a key of your own for
-- any action; and every key there is (core.catalog), each to add.
do -- (the Shortcuts editor: its own scope)
local kq = { kind = "All", source = "All", section = "All", shown = 120, cat = nil, add = { q = "", cmd = nil, name = nil, spec = nil }, cap = nil }
local rp = { data = nil, read = false } -- (5.31: REAPER's "Mouse modifier keys and action shortcuts" page: every key, its defaults too, and every mouse action)
function read_rpage(make) -- make: REAPER writes it first (Help: Mouse modifier keys and action shortcuts, which also opens it in the browser)
  if make then reaper.Main_OnCommand(40308, 0) end
  local path = core.shortcut_page_path()
  rp.data, rp.read, kq.cat = path and core.parse_shortcut_page(core.read(path)) or nil, true, nil
  return rp.data
end
function rpage() if not rp.read then read_rpage(false) end return rp.data end
local function reaper_keys() -- REAPER's own keys off its page, with their command ids found by name
  local d = rpage()
  if not d then return nil end
  local by, out = {}, {}
  for _, a in ipairs(core.action_list()) do by[a[2]] = by[a[2]] or a[1] end
  for _, k in ipairs(d.keys) do local c = by[k[2]]; if c then out[#out + 1] = { k[1], c, k[2], k[3] } end end
  return out
end
local CAP
local function cap_keys() -- ReaImGui's keys, as the key names styles.json and the installer use
  if CAP then return CAP end
  CAP = {}
  local function k(name, as) if ImGui["Key_" .. name] then CAP[#CAP + 1] = { ImGui["Key_" .. name], as } end end
  for c = 65, 90 do k(string.char(c), string.char(c)) end
  for d = 0, 9 do k(tostring(d), tostring(d)); k("Keypad" .. d, "Num" .. d) end
  for i = 1, 12 do k("F" .. i, "F" .. i) end
  for _, x in ipairs({ { "Space", "Space" }, { "Enter", "Enter" }, { "Tab", "Tab" }, { "Backspace", "Backspace" }, { "Delete", "Delete" }, { "Insert", "Insert" },
      { "Home", "Home" }, { "End", "End" }, { "PageUp", "PgUp" }, { "PageDown", "PgDn" }, { "LeftArrow", "Left" }, { "RightArrow", "Right" }, { "UpArrow", "Up" },
      { "DownArrow", "Down" }, { "Comma", "," }, { "Period", "." }, { "Slash", "/" }, { "Semicolon", ";" }, { "Apostrophe", "'" }, { "Minus", "-" },
      { "Equal", "=" }, { "LeftBracket", "[" }, { "RightBracket", "]" }, { "Backslash", "\\" }, { "GraveAccent", "`" }, { "KeypadEnter", "NumEnter" },
      { "KeypadAdd", "Num+" }, { "KeypadSubtract", "Num-" }, { "KeypadMultiply", "Num*" }, { "KeypadDivide", "Num/" }, { "KeypadDecimal", "Num." } }) do k(x[1], x[2]) end
  return CAP
end
local function capture() -- -> the keys pressed ("Ctrl+Shift+K"), false for Esc, nil while waiting
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then return false end
  local m = ImGui.GetKeyMods(ctx)
  for _, x in ipairs(cap_keys()) do
    if ImGui.IsKeyPressed(ctx, x[1], false) then
      local mods = {}
      if m & ImGui.Mod_Ctrl ~= 0 then mods[#mods + 1] = "Ctrl" end
      if m & ImGui.Mod_Alt ~= 0 then mods[#mods + 1] = "Alt" end
      if m & ImGui.Mod_Shift ~= 0 then mods[#mods + 1] = "Shift" end
      if ImGui.Mod_Super and m & ImGui.Mod_Super ~= 0 then mods[#mods + 1] = "Win" end
      mods[#mods + 1] = x[2]
      return table.concat(mods, "+")
    end
  end
end
local function keys_block_here() -- the persona's shortcuts block, made (your own keys) when there's none yet
  local b = core.draft_get(bld.blocks, "keys")
  if not b then b = core.keys_block("my_reaper"); core.draft_add(bld.blocks, b) end
  bld.active = true
  b.extra = type(b.extra) == "table" and b.extra or {}
  return b
end
local function add_key(spec, cmd, name)
  if not core.encode(spec) then return say(tostring(spec) .. " isn't a key REAPER can take.") end
  local b = keys_block_here()
  for i = #b.extra, 1, -1 do if core.canon(b.extra[i][1]) == core.canon(spec) then table.remove(b.extra, i) end end
  b.extra[#b.extra + 1] = { spec, cmd, name }
  say(keyname(spec) .. " runs " .. tostring(name) .. " in your persona (it replaces anything else on that key there).")
end
local function cap_button(id, label, on_keys)
  if kq.cap == id then
    ImGui.TextColored(ctx, C.YELLOW, "Press the keys now (Esc cancels)")
    local got = capture()
    if got == false then kq.cap = nil elseif got then kq.cap = nil; on_keys(got) end
  elseif ImGui.SmallButton(ctx, label .. "##cap" .. id) then kq.cap = id end
end
function persona_keys_card()
  if not card("pkeys") then return end
  heading("Your persona's shortcuts", 16)
  muted("Load a persona's keys, then leave any out, change any (press the new keys), or add keys from Every shortcut below or for any action. Its mouse wheel is on Mouse & trackpad.")
  ImGui.Indent(ctx, IND * UI)
  local b = core.draft_get(bld.blocks, "keys")
  local from = b and core.by_id(b.id)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  if ImGui.BeginCombo(ctx, "##keysfrom", b and (b.id == "my_reaper" and "Your own shortcuts" or (from and from.name or tostring(b.id))) or "Your own shortcuts") then
    if ImGui.Selectable(ctx, "Your own shortcuts##kown", b == nil or b.id == "my_reaper") then core.draft_add(bld.blocks, core.keys_block("my_reaper")); bld.active = true end
    for _, st in ipairs(sources(function(s) return #(s.keys or {}) > 0 end)) do
      if ImGui.Selectable(ctx, st.name .. "##kf" .. st.id, b ~= nil and b.id == st.id) then
        local nb = core.keys_block(st.id); nb.extra = b and b.extra or nil -- (keys you added stay)
        core.draft_add(bld.blocks, nb); bld.active = true
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "Loads that persona's or DAW's keys. Keys you added stay. Choosing here starts a new persona if you're not making one.")
  if b then
    local lines, count = core.build_preview({ b })[1], {}
    for _, e in ipairs(lines) do if e.kind == "key" and not e.off then count[core.canon(e.key)] = (count[core.canon(e.key)] or 0) + 1 end end
    ImGui.SetNextItemWidth(ctx, 240 * UI)
    local _, f = ImGui.InputTextWithHint(ctx, "##pkf", "search its keys or actions", kq.pfilter or ""); kq.pfilter = f
    local q = (kq.pfilter or ""):lower()
    if ImGui.BeginTable(ctx, "pkeys", 4, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 300 * UI) then
      ImGui.TableSetupColumn(ctx, "on", ImGui.TableColumnFlags_WidthFixed, 28 * UI)
      ImGui.TableSetupColumn(ctx, "Key", ImGui.TableColumnFlags_WidthFixed, 190 * UI)
      ImGui.TableSetupColumn(ctx, "Action", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed, 150 * UI)
      for _, e in ipairs(lines) do
        if (e.kind == "key" or e.kind == "midi") and (q == "" or tostring(e.key):lower():find(q, 1, true) or tostring(e.label):lower():find(q, 1, true)) then
          ImGui.PushID(ctx, e.slot)
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          local ch, v = ImGui.Checkbox(ctx, "##on", not e.off)
          if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
          ImGui.TableNextColumn(ctx)
          keycap(e.key)
          if e.kind == "key" and not e.off and (count[core.canon(e.key)] or 0) > 1 then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.YELLOW, "twice") end
          ImGui.TableNextColumn(ctx)
          ImGui.TextColored(ctx, e.off and C.MUTED or C.TEXT, tostring(e.label) .. (e.extra and "   (added)" or "") .. (e.kind == "midi" and "   (MIDI editor)" or "")
            .. (e.moved_from and ("   (was " .. keyname(e.moved_from) .. ")") or ""))
          ImGui.TableNextColumn(ctx)
          if e.kind == "key" then
            cap_button(e.slot, "Change", function(spec)
              if not core.encode(spec) then return say(spec .. " isn't a key REAPER can take.") end
              if e.extra then b.extra[e.extra][1] = spec
              else b.rebind = type(b.rebind) == "table" and b.rebind or {}; b.rebind[core.canon(e.moved_from or e.key)] = spec end
              say(tostring(e.label) .. " is on " .. keyname(spec) .. " in your persona.")
            end)
            if e.extra then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Remove") then table.remove(b.extra, e.extra) end
            elseif e.moved_from then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Undo") then b.rebind[core.canon(e.moved_from)] = nil end end
          end
          ImGui.PopID(ctx)
        end
      end
      ImGui.EndTable(ctx)
    end
  end
  -- a key of your own for any action (custom actions and scripts included)
  ImGui.Dummy(ctx, 0, 4)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Add a shortcut for any action:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  local _, aq = ImGui.InputTextWithHint(ctx, "##addq", "search REAPER's actions, scripts, custom actions", kq.add.q); kq.add.q = aq
  if kq.add.name then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.ACCENT, kq.add.name) end
  if #aq >= 2 and aq ~= kq.add.name then
    local n, ql = 0, aq:lower()
    for _, a in ipairs(core.action_list()) do
      if tostring(a[2]):lower():find(ql, 1, true) then
        if ImGui.Selectable(ctx, tostring(a[2]) .. "##act" .. tostring(a[1])) then kq.add.cmd, kq.add.name, kq.add.q = a[1], a[2], a[2] end
        n = n + 1; if n >= 12 then break end
      end
    end
    if n == 0 then muted("No action has that in its name.") end
  end
  if kq.add.cmd then
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Key:"); ImGui.SameLine(ctx)
    if kq.add.spec then keycap(kq.add.spec); ImGui.SameLine(ctx) end
    cap_button("add", kq.add.spec and "Change" or "Press keys", function(spec) kq.add.spec = spec end)
    if kq.add.spec then
      ImGui.SameLine(ctx)
      if primary("Add to my persona##addk") then add_key(kq.add.spec, kq.add.cmd, kq.add.name); kq.add = { q = "", cmd = nil, name = nil, spec = nil } end
    end
  end
  ImGui.Unindent(ctx, IND * UI)
  card_end()
end
local KINDS = { "All", "REAPER action", "Script", "Custom action", "SWS / extension" }
local function shortcuts_catalog()
  if not card("allkeys") then return end
  heading("Every shortcut", 16)
  muted("Every persona's keys and your own keymap's (keys you, a script or an extension set), the actions most personas use first. Add any to your persona.")
  if keys_for then local st = core.by_id(keys_for); if st then kq.source = st.name end; keys_for = nil end -- (from search)
  if not kq.cat then kq.cat = core.catalog(styles, core.read(reaper.GetResourcePath() .. "/reaper-kb.ini") or "", reaper_keys()) end
  if not rpage() then ImGui.TextColored(ctx, C.YELLOW, "REAPER's own keys (its defaults too) haven't been read on this computer yet.") ImGui.SameLine(ctx) end
  if ImGui.SmallButton(ctx, (rpage() and "Read REAPER's keys again" or "Read REAPER's keys") .. "##rpk") then read_rpage(true) end
  ImGui.SetItemTooltip(ctx, "REAPER lists every key it has, its defaults included, with Help > Mouse modifier keys and action shortcuts, which also opens the list in your browser.")
  ImGui.SetNextItemWidth(ctx, 220 * UI)
  local _, f = ImGui.InputTextWithHint(ctx, "##kf", "search keys or actions", filter); filter = f
  local function combo(id, cur, list, set, label)
    ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 190 * UI)
    if ImGui.BeginCombo(ctx, id, label .. ": " .. cur) then for _, x in ipairs(list) do if ImGui.Selectable(ctx, x .. id, x == cur) then set(x) end end ImGui.EndCombo(ctx) end
  end
  combo("##kind", kq.kind, KINDS, function(x) kq.kind = x end, "Type")
  local srcs = { "All", "Your keymap" }
  for _, st in ipairs(styles) do if #(st.keys or {}) > 0 and not st.keys_from then srcs[#srcs + 1] = st.name end end
  combo("##src", kq.source, srcs, function(x) kq.source = x end, "From")
  combo("##sec", kq.section, { "All", "Main", "MIDI editor" }, function(x) kq.section = x end, "Section")
  ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Refresh##kcat") then kq.cat = nil end
  local q, n, total = filter:lower(), 0, 0
  if ImGui.BeginTable(ctx, "allk", 5, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 360 * UI) then
    ImGui.TableSetupColumn(ctx, "Key", ImGui.TableColumnFlags_WidthFixed, 170 * UI)
    ImGui.TableSetupColumn(ctx, "Action", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "From", ImGui.TableColumnFlags_WidthStretch, 0.6)
    ImGui.TableSetupColumn(ctx, "Type", ImGui.TableColumnFlags_WidthFixed, 110 * UI)
    ImGui.TableSetupColumn(ctx, "add", ImGui.TableColumnFlags_WidthFixed, 44 * UI)
    ImGui.TableHeadersRow(ctx)
    for i, r in ipairs(kq.cat or {}) do
      local ok = (kq.kind == "All" or r.kind == kq.kind) and (kq.section == "All" or r.section == kq.section)
      if ok and kq.source ~= "All" then ok = false; for _, s in ipairs(r.sources) do if s == kq.source then ok = true end end end
      if ok and q ~= "" then ok = r.spec:lower():find(q, 1, true) or r.name:lower():find(q, 1, true) or table.concat(r.sources, " "):lower():find(q, 1, true) end
      if ok then
        total = total + 1
        if n < kq.shown then
          n = n + 1
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); keycap(r.spec)
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, r.name .. (r.section == "MIDI editor" and "   (MIDI editor)" or ""))
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, #r.sources > 3 and (r.sources[1] .. ", " .. r.sources[2] .. " and " .. (#r.sources - 2) .. " more") or table.concat(r.sources, ", "))
          if #r.sources > 3 then ImGui.SetItemTooltip(ctx, table.concat(r.sources, ", ")) end
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, r.kind)
          ImGui.TableNextColumn(ctx)
          ImGui.BeginDisabled(ctx, r.section ~= "Main")
          if ImGui.SmallButton(ctx, "Add##ak" .. i) then add_key(r.spec, r.cmd, r.name) end
          ImGui.EndDisabled(ctx)
        end
      end
    end
    ImGui.EndTable(ctx)
  end
  muted(n .. " of " .. total .. " shown")
  if total > n then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show more##kmore") then kq.shown = kq.shown + 200 end end
  card_end()
end
function shortcuts_page() persona_keys_card(); shortcuts_catalog() end
end
-- Mouse & trackpad (5.31; James: "Same thing should happen for mouse/trackpad - shows what all the mouse commands do, lets you edit them or
-- add your own as well"). Your persona's wheel, trackpad swipe, drags and clicks, each to leave out, change or remove; your own; and every
-- mouse action REAPER has (its own page, rpage) and every persona's.
local mouse_page
do -- (the Mouse & trackpad editor: its own scope)
local mq = { area = "All", source = "All", shown = 150, cat = nil, kind = "drag", ctx = "MM_CTX_ITEM", mods = 0, wheel = "Mousewheel", act = "", pick = nil, pick_name = nil, value = nil }
local AREAS = { "All", "Items", "Tracks and mixer", "MIDI editor", "Envelopes", "Ruler, markers and regions", "Razor edits", "Arrange view", "Lanes" }
local function area_of(name)
  if name:match("^MIDI") then return "MIDI editor" end
  if name:match("^Media item") or name:match("^Sample edit") then return "Items" end
  if name:match("^Track") or name:match("^Mixer") or name:match("^Fader") then return "Tracks and mixer" end
  if name:match("^Envelope") or name:match("^Automation") then return "Envelopes" end
  if name:match("^Ruler") or name:match("^Marker") or name:match("^Region") or name:match("^Tempo") then return "Ruler, markers and regions" end
  if name:match("^Razor") then return "Razor edits" end
  if name:match("^Fixed lane") then return "Lanes" end
  return "Arrange view"
end
local function mouse_cat()
  if not mq.cat then mq.cat = core.mouse_catalog(styles, rpage(), function(ctx, flag) return reaper.GetMouseModifier(ctx, flag, "") end) end
  return mq.cat
end
local function choices(ctx) -- what this context's lines can be: the behaviours known for it (REAPER's and the personas'), with their names
  local out, seen = {}, {}
  for _, r in ipairs(mouse_cat()) do
    if r.ctx == ctx and r.value ~= "-1" and not seen[r.value] then seen[r.value] = true; out[#out + 1] = { r.value, r.name } end
  end
  table.sort(out, function(a, b) return a[2] < b[2] end)
  return out
end
local function value_name(c, v) -- what a behaviour id does, in words
  if v == "-1" then return "REAPER's default for these keys" end
  for _, x in ipairs(choices(c)) do if x[1] == v then return x[2] end end
  local id = tonumber(v) or (type(v) == "string" and v:match("^_") and reaper.NamedCommandLookup(v))
  local name = id and id ~= 0 and reaper.kbd_getTextFromCmd and reaper.kbd_getTextFromCmd(id, reaper.SectionFromUniqueID(0))
  return (name and name ~= "") and name or tostring(v)
end
local function mouse_block_here()
  local b = core.draft_get(bld.blocks, "mouse")
  if not b then b = core.new_block("mouse", "my_reaper"); core.draft_add(bld.blocks, b) end
  bld.active = true
  return b
end
local function add_mouse_line(ctx, flag, value, name)
  local b = mouse_block_here()
  b.mextra = type(b.mextra) == "table" and b.mextra or {}
  for i = #b.mextra, 1, -1 do if b.mextra[i][2] == ctx and tonumber(b.mextra[i][3]) == flag then table.remove(b.mextra, i) end end
  b.mextra[#b.mextra + 1] = { "mouse", ctx, flag, value, name }
  say((core.CTX_NAME[ctx] or ctx) .. (flag > 0 and (" with " .. core.mouse_mods(flag)) or "") .. ": " .. tostring(name) .. ", in your persona.")
end
local function add_wheel(spec, cmd, name)
  if not core.encode(spec) then return say(spec .. " isn't a wheel REAPER can take.") end
  local b = mouse_block_here()
  b.extra = type(b.extra) == "table" and b.extra or {}
  for i = #b.extra, 1, -1 do if core.canon(b.extra[i][1]) == core.canon(spec) then table.remove(b.extra, i) end end
  b.extra[#b.extra + 1] = { spec, cmd, name }
  say(spec .. ": " .. tostring(name) .. ", in your persona.")
end
local function action_search(id, filter_words) -- -> cmd, name once one is picked
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  local _, q = ImGui.InputTextWithHint(ctx, "##as" .. id, "search actions", mq.act); mq.act = q
  if #q >= 2 then
    local n, ql = 0, q:lower()
    for _, a in ipairs(core.action_list()) do
      local nm = tostring(a[2]):lower()
      if nm:find(ql, 1, true) and (not filter_words or nm:find(filter_words, 1, true)) then
        if ImGui.Selectable(ctx, tostring(a[2]) .. "##asr" .. id .. tostring(a[1])) then mq.act = ""; return a[1], a[2] end
        n = n + 1; if n >= 10 then break end
      end
    end
  end
end
local function mods_boxes(id) -- Ctrl / Alt / Shift / Win ticks -> mq.mods (REAPER's mouse flags: Shift 1, Ctrl 2, Alt 4, Win 8)
  for _, x in ipairs({ { 2, MOD }, { 4, IS_MAC and "Option" or "Alt" }, { 1, "Shift" }, { 8, IS_MAC and "Control" or "Win" } }) do
    ImGui.SameLine(ctx)
    local ch, v = ImGui.Checkbox(ctx, x[2] .. "##mb" .. id .. x[1], mq.mods & x[1] ~= 0)
    if ch then mq.mods = v and (mq.mods | x[1]) or (mq.mods & ~x[1]) end
  end
end
local function wheel_spec(mods, wheel) local m = core.mouse_mods(mods):gsub("Shift%+Ctrl", "Ctrl+Shift"); return (m ~= "" and (m .. "+") or "") .. wheel end
local function change_popup(e, b) -- a line's new behaviour: a known one, REAPER's default, or an action
  if not ImGui.BeginPopup(ctx, "mch" .. e.slot) then return end
  local mctx = e.entry and core.for_os(e.entry[2]) or nil
  local function set(v, name)
    if e.extra then b.mextra[e.extra][4], b.mextra[e.extra][5] = v, name
    else b.mset = type(b.mset) == "table" and b.mset or {}; b.mset[e.slot] = v end
    ImGui.CloseCurrentPopup(ctx)
  end
  if ImGui.Selectable(ctx, "REAPER's default for these keys") then set("-1", "REAPER's default") end
  for _, c in ipairs(mctx and choices(mctx) or {}) do if ImGui.Selectable(ctx, c[2] .. "##ch" .. c[1]) then set(c[1], c[2]) end end
  ImGui.Separator(ctx); ImGui.Text(ctx, "Or run an action:")
  local cmd, name = action_search("ch" .. e.slot)
  if cmd then set(tostring(cmd), name) end
  ImGui.EndPopup(ctx)
end
local function persona_mouse_card()
  if not card("pmouse") then return end
  heading("Your persona's mouse and trackpad", 16)
  muted("Load a persona's mouse, then leave any line out, change what it does, or add your own (below, or from Every mouse action). A trackpad's two-finger scroll and pinch arrive as the wheel and Ctrl+wheel, its sideways swipe as the horizontal wheel.")
  ImGui.Indent(ctx, IND * UI)
  local b = core.draft_get(bld.blocks, "mouse")
  local from = b and core.by_id(b.id)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  if ImGui.BeginCombo(ctx, "##mfrom", b and (from and from.name or tostring(b.id)) or "Your own mouse and trackpad") then
    if ImGui.Selectable(ctx, "Your own mouse and trackpad##mown", b == nil) then core.draft_clear(bld.blocks, "mouse"); bld.active = true end
    for _, st in ipairs(sources(has_mouse)) do
      if ImGui.Selectable(ctx, st.name .. "##mf" .. st.id, b ~= nil and b.id == st.id) then
        local nb = core.new_block("mouse", st.id); nb.mextra, nb.extra = b and b.mextra or nil, b and b.extra or nil -- (lines you added stay)
        core.draft_add(bld.blocks, nb); bld.active = true
      end
    end
    ImGui.EndCombo(ctx)
  end
  if b then
    local groups = { { "Mouse wheel", {} }, { "Trackpad: two-finger swipe left and right", {} }, { "Drags and clicks", {} } }
    for _, e in ipairs(core.build_preview({ b })[1]) do
      if e.key and e.key:find("HorizWheel", 1, true) then table.insert(groups[2][2], e)
      elseif e.key then table.insert(groups[1][2], e)
      elseif not (e.entry and e.entry[1] == "mouse" and not core.for_os(e.entry[2])) then table.insert(groups[3][2], e) end
    end
    for _, g in ipairs(groups) do
      if #g[2] > 0 then
        ImGui.TextColored(ctx, C.MUTED, g[1])
        if ImGui.BeginTable(ctx, "pm" .. g[1], 4, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
          ImGui.TableSetupColumn(ctx, "on", ImGui.TableColumnFlags_WidthFixed, 28 * UI)
          ImGui.TableSetupColumn(ctx, "where", ImGui.TableColumnFlags_WidthStretch, 0.45)
          ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
          ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed, 140 * UI)
          for _, e in ipairs(g[2]) do
            ImGui.PushID(ctx, e.slot)
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            local ch, v = ImGui.Checkbox(ctx, "##on", not e.off)
            if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
            ImGui.TableNextColumn(ctx)
            if e.key then keycap(e.key)
            else
              local c = core.for_os(e.entry[2]) or e.entry[2]
              ImGui.Text(ctx, (core.CTX_NAME[c] or c) .. (tonumber(e.entry[3]) > 0 and ("  +  " .. core.mouse_mods(e.entry[3])) or ""))
            end
            ImGui.TableNextColumn(ctx)
            local label = e.changed and value_name(core.for_os(e.entry[2]) or e.entry[2], e.entry[4]) or tostring(e.label)
            ImGui.TextColored(ctx, e.off and C.MUTED or C.TEXT, label .. (e.extra and "   (added)" or "") .. (e.changed and "   (changed)" or ""))
            ImGui.TableNextColumn(ctx)
            if e.key then
              if ImGui.SmallButton(ctx, "Change") then ImGui.OpenPopup(ctx, "wch" .. e.slot) end
              if ImGui.BeginPopup(ctx, "wch" .. e.slot) then
                ImGui.Text(ctx, "What " .. e.key .. " does:")
                local cmd, name = action_search("w" .. e.slot)
                if cmd then add_wheel(e.key, cmd, name); ImGui.CloseCurrentPopup(ctx) end
                ImGui.EndPopup(ctx)
              end
            else
              if ImGui.SmallButton(ctx, "Change") then ImGui.OpenPopup(ctx, "mch" .. e.slot) end
              change_popup(e, b)
            end
            if e.extra then
              ImGui.SameLine(ctx)
              if ImGui.SmallButton(ctx, "Remove") then if e.key then table.remove(b.extra, e.extra) else table.remove(b.mextra, e.extra) end end
            elseif e.changed then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Undo") then b.mset[e.slot] = nil end end
            ImGui.PopID(ctx)
          end
          ImGui.EndTable(ctx)
        end
      end
    end
  end
  -- your own: a wheel or swipe binding, or a drag or click
  ImGui.Dummy(ctx, 0, 4)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Add your own:")
  ImGui.SameLine(ctx); if ImGui.RadioButton(ctx, "Drag or click##mk", mq.kind == "drag") then mq.kind = "drag" end
  ImGui.SameLine(ctx); if ImGui.RadioButton(ctx, "Wheel or trackpad##mk", mq.kind == "wheel") then mq.kind = "wheel" end
  if mq.kind == "wheel" then
    ImGui.SetNextItemWidth(ctx, 200 * UI)
    if ImGui.BeginCombo(ctx, "##wh", mq.wheel == "HorizWheel" and "Sideways (trackpad swipe)" or "Wheel (or two-finger scroll)") then
      if ImGui.Selectable(ctx, "Wheel (or two-finger scroll)", mq.wheel == "Mousewheel") then mq.wheel = "Mousewheel" end
      if ImGui.Selectable(ctx, "Sideways (trackpad swipe)", mq.wheel == "HorizWheel") then mq.wheel = "HorizWheel" end
      ImGui.EndCombo(ctx)
    end
    mods_boxes("w")
    local cmd, name = action_search("wadd", nil)
    if cmd then add_wheel(wheel_spec(mq.mods, mq.wheel), cmd, name) end
    muted("Pick the action to add " .. wheel_spec(mq.mods, mq.wheel) .. " (the View: Scroll and Zoom actions marked mousewheel are the usual ones).")
  else
    ImGui.SetNextItemWidth(ctx, 280 * UI)
    if ImGui.BeginCombo(ctx, "##mctx", core.CTX_NAME[mq.ctx] or mq.ctx) then
      for _, c in ipairs(core.MOUSE_CONTEXTS) do if ImGui.Selectable(ctx, c[2] .. "##mc" .. c[1], c[1] == mq.ctx) then mq.ctx, mq.value = c[1], nil end end
      ImGui.EndCombo(ctx)
    end
    mods_boxes("d")
    ImGui.SetNextItemWidth(ctx, 280 * UI)
    local cur = mq.value and (mq.pick_name or mq.value) or "what it does"
    if ImGui.BeginCombo(ctx, "##mval", cur) then
      if ImGui.Selectable(ctx, "REAPER's default for these keys") then mq.value, mq.pick_name = "-1", "REAPER's default" end
      for _, c in ipairs(choices(mq.ctx)) do if ImGui.Selectable(ctx, c[2] .. "##mv" .. c[1]) then mq.value, mq.pick_name = c[1], c[2] end end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx); ImGui.Text(ctx, "or an action:"); ImGui.SameLine(ctx)
    local cmd, name = action_search("dadd")
    if cmd then mq.value, mq.pick_name = tostring(cmd), name end
    if mq.value then
      if primary("Add to my persona##madd") then add_mouse_line(mq.ctx, mq.mods, mq.value, mq.pick_name); mq.value, mq.pick_name = nil, nil end
    end
  end
  ImGui.Unindent(ctx, IND * UI)
  card_end()
end
local function mouse_catalog_card()
  if not card("allmouse") then return end
  heading("Every mouse action", 16)
  muted("Everything the mouse does in REAPER now, its defaults included, and every persona's, grouped by where you click or drag. Add any to your persona.")
  if not rpage() then
    ImGui.TextColored(ctx, C.YELLOW, "REAPER's own list hasn't been read on this computer yet: only the personas' are below.")
  end
  if ImGui.SmallButton(ctx, (rpage() and "Read REAPER's list again" or "Read REAPER's list") .. "##rp") then read_rpage(true); mq.cat = nil end
  ImGui.SetItemTooltip(ctx, "REAPER writes it with Help > Mouse modifier keys and action shortcuts, which also opens it in your browser.")
  ImGui.SetNextItemWidth(ctx, 200 * UI)
  local _, f = ImGui.InputTextWithHint(ctx, "##mcf", "search", mq.filter or ""); mq.filter = f
  ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 220 * UI)
  if ImGui.BeginCombo(ctx, "##marea", "Where: " .. mq.area) then for _, a in ipairs(AREAS) do if ImGui.Selectable(ctx, a .. "##ma", a == mq.area) then mq.area = a end end ImGui.EndCombo(ctx) end
  local srcs = { "All", "REAPER (as set now)" }
  for _, st in ipairs(styles) do if has_mouse(st) and not st.keys_from then srcs[#srcs + 1] = st.name end end
  ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 200 * UI)
  if ImGui.BeginCombo(ctx, "##msrc", "From: " .. mq.source) then for _, s in ipairs(srcs) do if ImGui.Selectable(ctx, s .. "##ms", s == mq.source) then mq.source = s end end ImGui.EndCombo(ctx) end
  local q, n, total = (mq.filter or ""):lower(), 0, 0
  if ImGui.BeginTable(ctx, "allm", 5, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 360 * UI) then
    ImGui.TableSetupColumn(ctx, "Where", ImGui.TableColumnFlags_WidthStretch, 0.5)
    ImGui.TableSetupColumn(ctx, "Keys", ImGui.TableColumnFlags_WidthFixed, 130 * UI)
    ImGui.TableSetupColumn(ctx, "What it does", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "From", ImGui.TableColumnFlags_WidthStretch, 0.4)
    ImGui.TableSetupColumn(ctx, "add", ImGui.TableColumnFlags_WidthFixed, 44 * UI)
    ImGui.TableHeadersRow(ctx)
    for i, r in ipairs(mouse_cat()) do
      local ok = mq.area == "All" or area_of(r.ctxname) == mq.area
      if ok and mq.source ~= "All" then ok = false; for _, s in ipairs(r.sources) do if s == mq.source then ok = true end end end
      if ok and q ~= "" then ok = r.ctxname:lower():find(q, 1, true) or tostring(r.name):lower():find(q, 1, true) end
      if ok then
        total = total + 1
        if n < mq.shown then
          n = n + 1
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, r.ctxname)
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, r.flag == 0 and "(none)" or core.mouse_mods(r.flag))
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, tostring(r.name))
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, #r.sources > 2 and (r.sources[1] .. " and " .. (#r.sources - 1) .. " more") or table.concat(r.sources, ", "))
          if #r.sources > 2 then ImGui.SetItemTooltip(ctx, table.concat(r.sources, ", ")) end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "Add##am" .. i) then add_mouse_line(r.ctx, r.flag, r.value, r.name) end
        end
      end
    end
    ImGui.EndTable(ctx)
  end
  muted(n .. " of " .. total .. " shown")
  if total > n then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show more##mmore") then mq.shown = mq.shown + 200 end end
  card_end()
end
function mouse_page() -- (5.28: mouse and trackpad; 5.31: the editor)
  persona_mouse_card()
  mouse_catalog_card()
  if card("trackpad here") then
    heading("Trackpad on this computer", 16)
    muted("Windows and macOS send a trackpad's two-finger scroll as the mouse wheel, a sideways swipe as the horizontal wheel, and a pinch as Ctrl+wheel (Cmd on a Mac), so the persona's lines above cover both. Holding Shift while swiping turns it into a plain sideways scroll on Windows: pinch is the way to zoom.")
    if reaper.HasExtState("SmoothWheelScroll", "tprevzoom") then
      local on = reaper.GetExtState("SmoothWheelScroll", "tprevzoom") == "1"
      local ch, v = ImGui.Checkbox(ctx, "Smooth Wheel Scroll: reverse zooming on a trackpad##tprev", on)
      if ch then reaper.SetExtState("SmoothWheelScroll", "tprevzoom", v and "1" or "0", true); say("Smooth Wheel Scroll reads this when REAPER starts.") end
      ImGui.SetItemTooltip(ctx, "Smooth Wheel Scroll tells a trackpad from a wheel; this flips zoom for the trackpad only. Remote desktops (Chrome Remote Desktop) can look like a trackpad to it. Read when REAPER starts.")
    end
    card_end()
  end
end
end
local layout_designer, COVERED -- (5.32: the designer, and the parts of the layout it sets)
COVERED = { mixer_dock = true, transport = true, browser = true, editor = true }
do -- (the layout designer: its own scope)
  local ZONE_LABEL = { t_top = "Transport: top of the window", d_top = "Top dock", d_left = "Left dock", d_right = "Right dock", d_bottom = "Bottom dock",
    t_ruler = "Transport: above the ruler", t_below = "Transport: below the arrange view", t_bottom = "Transport: bottom of the window",
    float = "In its own window", hidden = "Closed" }
  local cache = { at = -1, items = nil }
  local function deep(t) local o = {}; for k, v in pairs(t) do o[k] = type(v) == "table" and deep(v) or v end return o end
  local function current_items() -- -> the layout the designer shows, and whether it's one you arranged
    local b = core.draft_get(bld.blocks, "layout")
    if b and type(b.items) == "table" then return b.items, true end
    local sig = {} -- (what the persona's layout parts come from now: a change of those shows at once)
    for a in pairs(COVERED) do local fb = core.draft_get(bld.blocks, "feel " .. a); sig[#sig + 1] = a .. "=" .. (fb and tostring(fb.id) or "") end
    table.sort(sig); sig = table.concat(sig, ";")
    if cache.items and cache.sig == sig and (sig:find("=[^;]") or reaper.time_precise() - cache.at < 2) then return cache.items, false end
    local entries = {}
    for a in pairs(COVERED) do
      local fb = core.draft_get(bld.blocks, "feel " .. a)
      if fb then for _, e in ipairs(core.build_preview({ fb })[1]) do if not e.off then entries[#entries + 1] = e.entry end end end
    end
    local from_reaper = #entries == 0
    if from_reaper then entries = core.feel_now(core.by_id("my_reaper") or styles[1]) end -- (nothing chosen: REAPER as it is now)
    local items = core.layout_from_entries(entries)
    if from_reaper then items.midi = { zone = core.midi_docked() and "d_bottom" or "float", order = 1 } end
    cache.at, cache.items, cache.sig = reaper.time_precise(), items, sig
    return items, false
  end
  local function move(items, w, zone, before) -- w into zone, before window `before` (or last); the layout becomes the persona's
    local copy = deep(items)
    copy[w] = { zone = zone, order = 0 }
    local list = {}
    for k, it in pairs(copy) do if it.zone == zone and k ~= w then list[#list + 1] = k end end
    table.sort(list, function(a, b) return (copy[a].order or 0) < (copy[b].order or 0) end)
    local pos = #list + 1
    if before then for i, k in ipairs(list) do if k == before then pos = i end end end
    table.insert(list, pos, w)
    for i, k in ipairs(list) do copy[k].order = i end
    for a in pairs(COVERED) do core.draft_clear(bld.blocks, "feel " .. a) end
    core.draft_add(bld.blocks, { kind = "layout", items = copy })
    bld.active, cache.items = true, nil
  end
  local function name_of(w) for _, x in ipairs(core.LAYOUT_WINDOWS) do if x[1] == w then return x[2] end end return w end
  local function dragging() -- the window being dragged, if one is
    local ok, kind, payload = ImGui.GetDragDropPayload(ctx)
    return ok and kind == "RP_WIN" and payload or nil
  end
  function layout_designer()
    if not card("designer") then return end
    heading("Arrange your layout", 16)
    muted("Drag a window to where you want it. Windows in the same dock are tabs, in the order shown: drop one onto another to put it before it. Starts from the persona's own layout (or REAPER as it is now).")
    ImGui.Indent(ctx, IND * UI)
    local items, mine = current_items()
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    local W = math.max(420 * UI, math.min(ImGui.GetContentRegionAvail(ctx), 820 * UI))
    local H, th, sidew = 340 * UI, 24 * UI, 160 * UI
    local mw = W - sidew - 14 * UI
    local dl = ImGui.GetWindowDrawList(ctx)
    local Z, y = {}, y0
    Z.t_top = { x0 + 4, y + 4, mw - 8, th }; y = y + th + 8
    Z.d_top = { x0 + 4, y, mw - 8, 44 * UI }; y = y + 44 * UI + 4
    local midH = H - (y - y0) - (58 * UI + th + 16)
    local sw = mw * 0.21
    Z.d_left = { x0 + 4, y, sw, midH }
    Z.d_right = { x0 + mw - 4 - sw, y, sw, midH }
    local ax, aw = x0 + 8 + sw, mw - 16 - 2 * sw
    Z.t_ruler = { ax, y, aw, th }
    local arrange = { ax, y + th + 2, aw, midH - 2 * th - 4 }
    Z.t_below = { ax, y + midH - th, aw, th }
    y = y + midH + 4
    Z.d_bottom = { x0 + 4, y, mw - 8, 58 * UI }; y = y + 58 * UI + 4
    Z.t_bottom = { x0 + 4, y, mw - 8, th }
    Z.float = { x0 + mw + 14 * UI, y0, sidew, H / 2 - 4 }
    Z.hidden = { x0 + mw + 14 * UI, y0 + H / 2 + 4, sidew, H / 2 - 4 }
    ImGui.DrawList_AddRect(dl, x0, y0, x0 + mw, y0 + H, C.MUTED, 6, 0, 1.5)
    ImGui.DrawList_AddRectFilled(dl, arrange[1], arrange[2], arrange[1] + arrange[3], arrange[2] + arrange[4], solid(mix(P.card, P.bg, 0.5)), 4)
    ImGui.DrawList_AddText(dl, arrange[1] + 8, arrange[2] + 6, C.MUTED, "Arrange view")
    local drag = dragging()
    local act
    for z, r in pairs(Z) do -- (each zone: a drop target; lit while a window that can go there is dragged)
      local can = drag and core.zone_ok(drag, z)
      ImGui.DrawList_AddRectFilled(dl, r[1], r[2], r[1] + r[3], r[2] + r[4], can and solid(mix(P.card, P.accent, 0.35)) or C.CARD, 4)
      ImGui.DrawList_AddText(dl, r[1] + 6, r[2] + 3, C.MUTED, ZONE_LABEL[z])
      ImGui.SetCursorScreenPos(ctx, r[1], r[2])
      ImGui.SetNextItemAllowOverlap(ctx) -- (5.35: the windows drawn over it get the mouse first, so they can be dragged; James: "wasn't letting me drag things")
      ImGui.InvisibleButton(ctx, "##zone" .. z, math.max(r[3], 1), math.max(r[4], 1))
      if ImGui.BeginDragDropTarget(ctx) then
        local ok, w = ImGui.AcceptDragDropPayload(ctx, "RP_WIN")
        if ok and core.zone_ok(w, z) then act = { w, z, nil } end
        ImGui.EndDragDropTarget(ctx)
      end
    end
    for z, r in pairs(Z) do -- (the windows in it, as tabs in order)
      local list = {}
      for w, it in pairs(items) do if it.zone == z then list[#list + 1] = w end end
      table.sort(list, function(a, b) return (items[a].order or 0) < (items[b].order or 0) end)
      local tall = r[4] > 40 * UI -- (a dock: its name above its windows; a thin strip: its windows after its name)
      local cx, cy = r[1] + 6 + (tall and 0 or (ImGui.CalcTextSize(ctx, ZONE_LABEL[z]) + 10)), r[2] + (tall and 20 * UI or 1)
      for i, w in ipairs(list) do
        local label = name_of(w) .. ((#list > 1 and z:sub(1, 2) == "d_") and ("  (tab " .. i .. ")") or "")
        local bw = ImGui.CalcTextSize(ctx, label) + 16 * UI
        if tall and cx + bw > r[1] + r[3] - 4 and cx > r[1] + 6 then cx, cy = r[1] + 6, cy + ImGui.GetFrameHeight(ctx) + 4 end
        ImGui.SetCursorScreenPos(ctx, cx, cy)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.ACCENT)
        ImGui.Button(ctx, label .. "##win" .. w, bw, 0)
        ImGui.PopStyleColor(ctx)
        ImGui.SetItemTooltip(ctx, name_of(w) .. ": " .. core.ZONE_WORDS[z] .. ". Drag it somewhere else, or onto another window in a dock to make it the tab before.")
        if ImGui.BeginDragDropSource(ctx) then
          ImGui.SetDragDropPayload(ctx, "RP_WIN", w)
          ImGui.Text(ctx, name_of(w))
          ImGui.EndDragDropSource(ctx)
        end
        if ImGui.BeginDragDropTarget(ctx) then
          local ok, dw = ImGui.AcceptDragDropPayload(ctx, "RP_WIN")
          if ok and dw ~= w and core.zone_ok(dw, z) then act = { dw, z, w } end
          ImGui.EndDragDropTarget(ctx)
        end
        cx = cx + bw + 6
      end
    end
    ImGui.SetCursorScreenPos(ctx, x0, y0 + H + 8)
    ImGui.Dummy(ctx, 1, 1)
    if act then move(items, act[1], act[2], act[3]); say(name_of(act[1]) .. ": " .. core.ZONE_WORDS[act[2]] .. ", in your persona.") end
    if mine then
      muted("This is your own arrangement: it sets the mixer, Media Explorer, transport and MIDI editor parts below.")
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Back to the persona's own##lyreset") then core.draft_clear(bld.blocks, "layout"); cache.items = nil end
    end
    muted("REAPER's other windows (the Actions list, Undo History, Region Manager and the rest) are below, under Other windows.")
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
local prefs_page -- (5.35: REAPER's preferences in a persona)
do
  local function block() return core.draft_get(bld.blocks, "feel prefs") end
  local function values() -- the block's values (made from what it loads, the first time it's changed here)
    local b = block()
    if not b then return nil end
    if type(b.values) ~= "table" then
      local v = {}
      for _, e in ipairs(core.build_preview({ b })[1]) do if e.entry[1] == "pref" then v[e.entry[2]] = e.entry[3] end end
      b.values, b.id = v, nil
    end
    return b.values
  end
  local function control(x, v) -- -> changed?, the new value
    local k = x[1]
    ImGui.SetNextItemWidth(ctx, 220 * UI)
    if x[3] == "num" then
      local ch, n = ImGui.DragDouble(ctx, "##pfv" .. k, v, 0.001, x[4], x[5], "%.3f s")
      return ch, math.max(x[4], math.min(x[5], n))
    elseif x[3] == "bool" then
      local ch, on = ImGui.Checkbox(ctx, "##pfv" .. k, v == 1)
      return ch, on and 1 or 0
    elseif x[3] == "db" or x[3] == "db10" then
      local db = x[3] == "db10" and v / 10 or (v <= 0 and -60 or 20 * math.log(v, 10))
      local ch, n = ImGui.SliderDouble(ctx, "##pfv" .. k, db, -60, x[3] == "db10" and -1 or 12, "%.1f dB")
      if x[3] == "db10" then return ch, math.floor(n * 10 + 0.5) end
      return ch, n <= -60 and 0 or 10 ^ (n / 20)
    else
      local labels = {}
      if x[3] == "shape" then for i = 1, 7 do labels[i] = "Shape " .. i end else labels = x[4] end
      local out, changed = v, false
      if ImGui.BeginCombo(ctx, "##pfv" .. k, labels[math.floor(v) + 1] or tostring(v)) then
        for i, l in ipairs(labels) do if ImGui.Selectable(ctx, l .. "##pfo" .. k .. i, i - 1 == v) then out, changed = i - 1, true end end
        ImGui.EndCombo(ctx)
      end
      return changed, out
    end
  end
  function prefs_page()
    if card("pf top") then
      heading("REAPER's preferences")
      muted("The ones REAPER has no action for: fades and crossfades, zoom, new tracks, recording and solo. Tick In my persona and set it: the persona you're making gets that value. REAPER reads its preferences only as it starts, so a persona's go in at REAPER's next restart, and yours go back the same way when you switch away.")
      ImGui.Indent(ctx, IND * UI)
      ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 260 * UI)
      if ImGui.BeginCombo(ctx, "##pfload", "a persona or your saved look") then
        for _, st in ipairs(sources(function(s) return has_aspect(core.source(s.id) or s, "prefs") end)) do
          if ImGui.Selectable(ctx, st.name .. "##pfl" .. st.id) then
            core.draft_add(bld.blocks, core.new_block("feel", st.id, "prefs")); bld.active = true
            say(st.name .. "'s preferences are in your persona: change any below.")
          end
        end
        ImGui.EndCombo(ctx)
      end
      if block() then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave them all as they are##pfclr") then core.draft_clear(bld.blocks, "feel prefs") end end
      local waiting = core.load_json(here .. "/pending/prefs.json")
      if waiting and next(waiting) then
        ImGui.TextColored(ctx, C.YELLOW, "Waiting for REAPER to restart: " .. #(function() local n = {}; for k in pairs(waiting) do n[#n + 1] = k end return n end)() .. " preference(s).")
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Restart REAPER now##pfrestart") then install_shortcuts() end
        ImGui.SetItemTooltip(ctx, "REAPER closes (asking about anything unsaved), the preferences go in, and REAPER opens again.")
        if not core.python() then muted("Putting them in needs Python 3 (python.org) on this computer.") end
      end
      ImGui.Unindent(ctx, IND * UI)
      card_end()
    end
    if not card("pf list") then return end
    local vals, group = values(), nil
    ImGui.Indent(ctx, IND * UI)
    for _, x in ipairs(core.PREFS) do
      if x.group ~= group then group = x.group; heading(group, 15) end
      local live = core.pref_now(x[1])
      local v = vals and tonumber(vals[x[1]])
      local ch, on = ImGui.Checkbox(ctx, "##pfin" .. x[1], v ~= nil)
      ImGui.SetItemTooltip(ctx, v and "In your persona: untick to leave it as it is" or "Tick to put it in your persona, at the value set here")
      if ch then
        if not block() then core.draft_add(bld.blocks, { kind = "feel", aspect = "prefs", values = {} }) end
        values()[x[1]] = on and (live or 0) or nil
        bld.active = true
      end
      ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, x[2]); ImGui.SameLine(ctx, 400 * UI)
      if v then
        local c2, n = control(x, v)
        if c2 then values()[x[1]] = n; bld.active = true end
        ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "now " .. core.pref_words(x[1], live))
      else
        ImGui.TextColored(ctx, C.MUTED, live and core.pref_words(x[1], live) or "not in this REAPER")
      end
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
local windows_card -- (5.34: every other window, set one by one)
do
  local CHOICES = { { nil, "Leave as it is" }, { "closed", "Closed" }, { "float", "In its own window" }, { "bottom", "Docked at the bottom" },
    { "left", "Docked on the left" }, { "top", "Docked at the top" }, { "right", "Docked on the right" } }
  local undock_note, undock_at = nil, -10
  local function block_items() -- -> the windows block's items (made from what it loads, the first time it's changed here), or nil
    local b = core.draft_get(bld.blocks, "feel windows")
    if not b then return nil end
    if type(b.items) ~= "table" then
      local items = {}
      for _, e in ipairs(core.build_preview({ b })[1]) do if e.entry[1] == "windows" then items = e.entry[2] end end
      b.items, b.id = items, nil
    end
    return b.items
  end
  function windows_card()
    if not card("windows edit") then return end
    heading("Set each window", 16)
    muted("Open or closed, in its own window (where it is now) or docked on a side. Take them as they are now, or choose one by one.")
    ImGui.Indent(ctx, IND * UI)
    if not core.windows_now() then
      ImGui.TextColored(ctx, C.YELLOW, "Needs js_ReaScriptAPI (Home > Setup) to see REAPER's windows.")
      ImGui.Unindent(ctx, IND * UI); card_end(); return
    end
    if ImGui.Button(ctx, "Take them as they are now##wnow") then
      core.draft_add(bld.blocks, { kind = "feel", aspect = "windows", items = core.windows_now() })
      bld.active = true; core.undock_slot(); undock_at = -10
      say("Every window, as it is now, is in your persona.")
    end
    local items = block_items() or {}
    local now = core.windows_now() or {}
    for _, w in ipairs(core.TOOL_WINDOWS) do
      local x = items[w[1]]
      local cur = not x and "Leave as it is" or x.s ~= 1 and "Closed" or nil
      for _, c in ipairs(CHOICES) do if x and x.s == 1 and c[1] == (x.p or "float") then cur = c[2] end end
      ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, w[4]); ImGui.SameLine(ctx, 210 * UI)
      ImGui.SetNextItemWidth(ctx, 200 * UI)
      if ImGui.BeginCombo(ctx, "##wc" .. w[1], cur or (x and x.s == 1 and "Open") or "Leave as it is") then
        for _, c in ipairs(CHOICES) do
          if (w[2] or c[1] == nil or c[1] == "closed" or c[1] == "float") and ImGui.Selectable(ctx, (not w[2] and c[1] == "float") and "Open" or c[2], cur == c[2]) then
            local list = block_items()
            if not list then core.draft_add(bld.blocks, { kind = "feel", aspect = "windows", items = {} }); list = block_items() end
            if c[1] == nil then list[w[1]] = nil
            elseif c[1] == "closed" then list[w[1]] = { s = 0 }
            else
              local n = now[w[1]]
              list[w[1]] = { s = 1, p = w[2] and c[1] or nil, r = c[1] == "float" and n and n.p == "float" and n.r or nil } -- (its own window: where it is now, when it's open)
              if c[1] ~= "float" then core.undock_slot(); undock_at = -10 end
            end
            bld.active = true
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "now " .. core.window_words(now[w[1]]))
    end
    if reaper.time_precise() - undock_at > 5 then -- (whether REAPER has ReaPersona's window set: read now and then, not every frame)
      undock_at = reaper.time_precise()
      local slot, why = core.undock_slot_in(core.read(reaper.GetResourcePath() .. "/reaper-screensets.ini")), nil
      if not slot then why = (core.read(here .. "/pending/reaper-screensets.ini") or ""):find(core.UNDOCK_SET, 1, true) and "waiting" or "none" end
      undock_note = why
    end
    if undock_note == "waiting" then
      ImGui.TextColored(ctx, C.YELLOW, "Taking a window out of a docker needs ReaPersona's window set, which goes in when REAPER next restarts.")
      if ImGui.SmallButton(ctx, "Restart REAPER now##wrestart") then install_shortcuts() end
      ImGui.SetItemTooltip(ctx, "REAPER closes (asking about anything unsaved), ReaPersona's window set and your persona shortcuts go in, and REAPER opens again.")
    elseif undock_note == "none" then
      muted("Taking a window out of a docker needs a window set of ReaPersona's: it's added (in a free set, View > Screensets) the first time a persona docks one.")
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
local function layout_page()
  layout_designer()
  if card("layout top") then
    heading("Your persona's layout, part by part")
    muted("Each part from whichever persona you like: the mixer from one, the transport from another. Leave a part as it is and yours stays.")
    ImGui.Indent(ctx, IND * UI)
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load the whole layout from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 260 * UI)
    if ImGui.BeginCombo(ctx, "##layoutall", "choose a persona or DAW") then
      for _, st in ipairs(sources(function(s) for _, x in ipairs(core.ASPECTS) do if x[1] ~= "mouse" and x[1] ~= "prefs" and has_aspect(s, x[1]) then return true end end end)) do
        if ImGui.Selectable(ctx, st.name .. "##lall" .. st.id) then
          core.draft_clear(bld.blocks, "layout")
          for _, x in ipairs(core.ASPECTS) do
            if x[1] ~= "mouse" and x[1] ~= "prefs" then
              if has_aspect(st, x[1]) then core.draft_add(bld.blocks, core.new_block("feel", st.id, x[1])) else core.draft_clear(bld.blocks, "feel " .. x[1]) end
            end
          end
          bld.active = true
          say(st.name .. "'s layout is in your persona: arrange it above, or change any part below.")
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
  local arranged = core.draft_get(bld.blocks, "layout") ~= nil
  for _, x in ipairs(core.ASPECTS) do
    if x[1] ~= "mouse" and x[1] ~= "prefs" then
      if arranged and COVERED[x[1]] then
        if card("slot " .. x[1]) then heading(x[4], 16); muted("Set by your arrangement above."); card_end() end
      else
        slot_card(x[1], x[4], x[2], "feel " .. x[1], sources(function(st) return has_aspect(st, x[1]) end), function(st) return core.new_block("feel", st.id, x[1]) end, "Leave as it is")
        if x[1] == "windows" then windows_card() end
      end
    end
  end
end
function persona_theme_line() -- (on Themes, over the list of themes)
  local b = core.draft_get(bld.blocks, "theme")
  heading("Your persona's theme", 16)
  ImGui.Indent(ctx, IND * UI)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, b and (b.file:gsub("%.ReaperTheme%a*$", "")) or "Yours (whatever theme is in use)")
  if b then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave as it is##thl") then core.draft_clear(bld.blocks, "theme") end end
  ImGui.SameLine(ctx); ImGui.Text(ctx, "  Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 220 * UI)
  if ImGui.BeginCombo(ctx, "##thfrom", "a persona or DAW") then
    for _, st in ipairs(sources(function(s) local th = core.theme_for(s); return th and reaper.file_exists(themes_dir .. th) end)) do
      if ImGui.Selectable(ctx, st.name .. "##thf" .. st.id) then core.draft_add(bld.blocks, core.new_block("theme", core.theme_for(st))); bld.active = true end
    end
    ImGui.EndCombo(ctx)
  end
  muted("Or My persona on a theme's row, below.")
  ImGui.Unindent(ctx, IND * UI)
end
local function project_editor(b)
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  local sr = tonumber(b.srate) or 0
  if ImGui.BeginCombo(ctx, "Sample rate##psr", sr > 0 and (core.khz(sr)) or "Leave as it is") then
    if ImGui.Selectable(ctx, "Leave as it is", sr == 0) then b.srate = 0 end
    for _, r in ipairs(core.SRATES) do if ImGui.Selectable(ctx, core.khz(r), sr == r) then b.srate = r end end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "A new (still empty) project gets this sample rate, and the audio device follows it when it can.")
  local has = type(b.tracks) == "string" and b.tracks ~= ""
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Starter tracks: " .. (has and ((b.tracks_name or "") ~= "" and b.tracks_name or "yes") or "none"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Use the selected tracks##ptr") then
    local text, n = core.selected_tracks_text()
    if n > 0 then
      b.tracks, b.tracks_name = text, n .. " track" .. (n == 1 and "" or "s") .. " from " .. (reaper.GetProjectName(0, "") ~= "" and reaper.GetProjectName(0, "") or "this project")
      say("The persona keeps " .. n .. " track" .. (n == 1 and "" or "s") .. " (their FX, routing and settings, not their items).")
    else say("No tracks in this project to take.") end
  end
  ImGui.SetItemTooltip(ctx, "The selected tracks (or every track, with none selected), with their FX, sends and settings but not their items, go into every new project that uses this persona.")
  if has then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "None##ptr0") then b.tracks, b.tracks_name = "", "" end end
  local tp = type(b.template) == "string" and b.template ~= ""
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Project template: " .. (tp and (b.template_name or "yes") or "none"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Use this whole project##ptpl") then
    local pj = core.project_now(true)
    if pj.template then b.template, b.template_name = pj.template, pj.template_name; say("The persona keeps " .. pj.template_name .. ".")
    else say("Couldn't read this project.") end
  end
  ImGui.SetItemTooltip(ctx, "This project as the starting point for new ones: every track with its FX, routing and folders, the sample rate, recording format, render settings, tempo, markers and regions. Not its audio or MIDI.")
  if tp then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "None##ptpl0") then b.template, b.template_name = nil, nil end end
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  local w = tonumber(b.wset) or 0
  if ImGui.BeginCombo(ctx, "Window set##pws", w > 0 and ("#" .. w) or "Leave as it is") then
    if ImGui.Selectable(ctx, "Leave as it is", w == 0) then b.wset = 0 end
    for n = 1, 10 do if ImGui.Selectable(ctx, "#" .. n, w == n) then b.wset = n end end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "A layout you saved in REAPER (View > Screensets/layouts > Windows), loaded each time this persona is used.")
  -- (5.33: a new project's tempo, time signature and grid)
  local on = (tonumber(b.bpm) or 0) > 0
  local ch, v = ImGui.Checkbox(ctx, "Tempo##pbpmon", on)
  if ch then b.bpm = v and 120 or nil end
  if on then
    ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 120 * UI)
    local c2, nv = ImGui.DragDouble(ctx, "BPM##pbpm", tonumber(b.bpm) or 120, 0.5, 20, 400, "%.1f")
    if c2 then b.bpm = math.max(20, math.min(400, nv)) end
  end
  ImGui.SetItemTooltip(ctx, "A new (still empty) project starts at this tempo.")
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  local ts = (tonumber(b.ts_num) or 0) > 0 and (b.ts_num .. "/" .. b.ts_den) or "Leave as it is"
  if ImGui.BeginCombo(ctx, "Time signature##pts", ts) then
    if ImGui.Selectable(ctx, "Leave as it is", ts == "Leave as it is") then b.ts_num, b.ts_den = nil, nil end
    for _, x in ipairs({ { 4, 4 }, { 3, 4 }, { 2, 4 }, { 5, 4 }, { 6, 8 }, { 7, 8 }, { 9, 8 }, { 12, 8 }, { 2, 2 } }) do
      if ImGui.Selectable(ctx, x[1] .. "/" .. x[2], ts == x[1] .. "/" .. x[2]) then b.ts_num, b.ts_den = x[1], x[2] end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  if ImGui.BeginCombo(ctx, "Grid##pgrid", (tonumber(b.grid) or 0) > 0 and core.grid_name(b.grid) or "Leave as it is") then
    if ImGui.Selectable(ctx, "Leave as it is", not b.grid) then b.grid = nil end
    for _, g in ipairs(core.GRIDS) do if ImGui.Selectable(ctx, g[2] .. "##g" .. g[2], b.grid == g[1]) then b.grid = g[1] end end
    ImGui.EndCombo(ctx)
  end
  -- (5.35: render settings, taken from the project in front)
  local r = core.safe_render(b.render)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Render settings: " .. (r and core.render_words(r) or "leave as they are"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Use this project's##prender") then
    b.render = core.render_now(0)
    say(b.render and ("Render settings in your persona: " .. core.render_words(b.render) .. ".") or "This project's render settings couldn't be read.")
  end
  ImGui.SetItemTooltip(ctx, "The format, sample rate, channels and file name pattern of the project in front (File > Render), for each new project. Not the output folder: that's this computer's.")
  if r then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave as they are##prenderx") then b.render = nil end end
end
local function project_page()
  if card("project top") then
    heading("Project defaults")
    muted("With this persona, a new (still empty) project gets a sample rate, tempo, time signature and grid, starter tracks or a whole project template, and a window set. A persona with a project part is also a workflow you can put on top of any persona. The click, count-in and pre-roll are REAPER options: REAPER > Recording and Playback.")
    if ImGui.SmallButton(ctx, "Recording options##prec") then go("R_recording") end
    ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Playback options##pplay") then go("R_playback") end
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Start from:")
    for _, w in ipairs(core.WORKFLOWS) do
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, w.name .. "##wf") then
        for _, b in ipairs(w.blocks()) do core.draft_add(bld.blocks, b) end
        bld.active = true
        if bld.name == "" then bld.name = w.name end
        say(w.name .. "'s project and settings are in your persona.")
      end
      ImGui.SetItemTooltip(ctx, w.tip)
    end
    local b = core.draft_get(bld.blocks, "project")
    ImGui.Dummy(ctx, 0, 4)
    ImGui.Indent(ctx, IND * UI)
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 240 * UI)
    if ImGui.BeginCombo(ctx, "##projfrom", "a persona of yours") then
      for _, st in ipairs(sources(function(s) return s.project ~= nil end)) do
        if ImGui.Selectable(ctx, st.name .. "##pf" .. st.id) then
          local nb = core.new_block("project")
          for k, v in pairs(st.project) do nb[k] = v end
          core.draft_add(bld.blocks, nb); bld.active = true; b = nb
        end
      end
      ImGui.EndCombo(ctx)
    end
    if b then
      project_editor(b)
      if ImGui.SmallButton(ctx, "No project part##pnone") then core.draft_clear(bld.blocks, "project") end
    elseif ImGui.Button(ctx, "Set what a new project gets") then core.draft_add(bld.blocks, core.new_block("project")); bld.active = true end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end

-- REAPER's defaults: a tab per setting group, live. A group can go into the persona being made, and follows what's set here.
local function tweaks_page(only) -- (5.33: REAPER's defaults, one group per tab; only = that group's id)
  if card("tw top") then
    heading("REAPER's defaults")
    muted("REAPER's own options and SWS's. Each change happens now and REAPER keeps it. A persona that sets one puts yours back when you switch away; In my persona makes a group, as you've set it here, part of the persona you're making.")
    if ImGui.Button(ctx, "Preferences") then reaper.Main_OnCommand(40016, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Toolbars and menus") then reaper.Main_OnCommand(40905, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Actions and shortcuts") then reaper.Main_OnCommand(40605, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Mouse modifiers") then reaper.Main_OnCommand(41356, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Theme adjuster") then reaper.Main_OnCommand(42234, 0) end
    card_end()
  end
  if card("tw from") then
    heading("Your persona's REAPER settings", 16)
    muted("Tick In my persona on a group below and the persona you're making sets it as you have it here (and follows what you change).")
    ImGui.Indent(ctx, IND * UI)
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 240 * UI)
    if ImGui.BeginCombo(ctx, "##twfrom", "a persona of yours") then
      for _, st in ipairs(sources(function(s) for _, b in ipairs(s.blocks or {}) do if b.kind == "settings" then return true end end end)) do
        if ImGui.Selectable(ctx, st.name .. "##twf" .. st.id) then
          for _, b in ipairs(st.blocks) do if b.kind == "settings" then core.draft_add(bld.blocks, core.json_decode(core.json_encode(b))) end end
          bld.active = true; say(st.name .. "'s REAPER settings are in your persona (they don't change REAPER until it's used).")
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
  for gi, g in ipairs(core.SETTING_GROUPS) do
    if (not only or g.id == only) and card("tw " .. g.id) then
      heading(g.name, 16)
      ImGui.SameLine(ctx)
      local inb = core.draft_get(bld.blocks, "settings " .. g.id)
      local ch, v = ImGui.Checkbox(ctx, "In my persona##twb" .. gi, inb ~= nil)
      if ch then if v then in_persona(core.new_block("settings", g.id), g.name .. ", as you set it here,") else core.draft_clear(bld.blocks, "settings " .. g.id) end end
      ImGui.SetItemTooltip(ctx, "The persona you're making sets these as they are here; change them here and it follows.")
      if inb then local nb = core.new_block("settings", g.id); inb.values = nb.values end -- (it follows what you set here)
      for n, it in ipairs(g.items) do
        ImGui.PushID(ctx, gi * 100 + n)
        if type(it[1]) == "table" then
          local now = core.setting_now(it)
          ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, it[2])
          if it.tip then ImGui.SetItemTooltip(ctx, it.tip) end
          for k, o in ipairs(it[3]) do
            ImGui.SameLine(ctx)
            if ImGui.RadioButton(ctx, o .. "##ch" .. k, now == k) and now ~= k then reaper.Main_OnCommand(core.cmd_id(it[1][k]), 0) end
          end
        else
          local id = core.cmd_id(it[1])
          if id == 0 then
            ImGui.BeginDisabled(ctx); setting_row("##tw", it[2] .. "  (needs SWS)", false, it.tip); ImGui.EndDisabled(ctx)
          elseif setting_row("##tw", it[2], reaper.GetToggleCommandState(id) == 1, it.tip) then
            reaper.Main_OnCommand(id, 0)
          end
        end
        ImGui.PopID(ctx)
      end
      if g.id == "colours" and core.cmd_id("_SWSAUTOCOLOR_APPLY") ~= 0 then
        ImGui.Dummy(ctx, 0, 2)
        if ImGui.Button(ctx, "Colour the tracks now") then reaper.Main_OnCommand(core.cmd_id("_SWSAUTOCOLOR_APPLY"), 0); say("Tracks coloured by SWS's rules.") end
        ImGui.SetItemTooltip(ctx, "Applies SWS's auto-colour rules to every track now.")
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Colour and icon rules...") then reaper.Main_OnCommand(core.cmd_id("_SWSAUTOCOLOR_OPEN"), 0) end
        ImGui.SetItemTooltip(ctx, "SWS's window for the rules: which track names get which colour, icon and layout.")
      end
      card_end()
    end
  end
end

local GROUPS = { -- { name, what it's for, its pages (tabs), the tabs' labels }
  { "Home", "Get everything set up, and import from another DAW. Drop files here.", { "Setup" }, { "Setup" } },
  { "Personas", "Your favourites, the DAWs, and the personas you made.", { "Favourites", "DAWs", "Presets" }, { "Favourites", "DAWs", "Your personas" } },
  { "Themes", "Your themes, getting more, adjusting the one in use, and building one from others.", { "Themes", "Browse", "Adjust", "Merge" }, { "Your themes", "Get more", "Adjust", "Build one" } },
  { "Colours", "Colour the project: tracks, items and regions, by gradient, folder, instrument, section and more.", { "Colours" }, { "Colours" } }, -- (its own tab since 5.25: James)
  { "Shortcuts", "Your persona's shortcuts, and every key of any persona with REAPER's action for it.", { "Shortcuts" }, { "Shortcuts" } },
  { "Mouse & trackpad", "Your persona's mouse wheel, trackpad gestures, drags and clicks, from any persona.", { "Mouse" }, { "Mouse & trackpad" } },
  { "Layout", "Your persona's mixer, transport, browser, toolbar, MIDI editor, and snap and ripple, each from any persona.", { "Layout" }, { "Layout" } },
  { "Project", "Your persona's project defaults: sample rate, tempo, time signature, grid, starter tracks or a template, a window set.", { "Project" }, { "Project defaults" } },
  { "REAPER", "REAPER's own options and SWS's, an area per tab, each to make part of your persona.", {}, {} }, -- (tabs: below, one per setting group)
  { "Settings", "ReaPersona's own settings: your other computers, what personas may change, scrolling and zoom, its look, updates.", { "Settings", "SetPersonas", "SetScroll", "SetLook", "SetUpdates", "SetRemove" }, { "Sync", "Personas", "Scrolling & zoom", "Look", "Updates", "Remove" } },
  { "Help", "How ReaPersona works and what each page does, what's installed, checking the personas, repairs.", { "Guide", "Check" }, { "How it works", "Check and repair" } },
}
do -- (REAPER's tabs: one per setting group. 5.33)
  local short = { playback = "Playback", editing = "Editing", recording = "Recording", view = "View", colours = "Colours & icons", automation = "Automation", monitoring = "Monitoring & FX", mixer = "Mixer" }
  for _, g in ipairs(GROUPS) do
    if g[1] == "REAPER" then
      for _, s in ipairs(core.SETTING_GROUPS) do g[3][#g[3] + 1] = "R_" .. s.id; g[4][#g[4] + 1] = short[s.id] or s.name end
      g[3][#g[3] + 1] = "R_prefs"; g[4][#g[4] + 1] = "Preferences" -- (5.35)
    end
  end
end
-- Help > How it works (5.14), also the screen-reader menu's Help: plain sentences, so the same text reads in a message box.
local GUIDE = {
  { "Getting started", {
    "1. Pick the DAW you're coming from: Personas > DAWs, or the first card on Home. REAPER takes on its look and feel straight away, and its shortcuts once they're installed (step 2). Back to My REAPER (top) puts your own setup back, exactly as it was.",
    "2. Install the shortcuts: Home > Install and restart. REAPER reads its keymap only when it starts, so it closes (asking about anything unsaved), the persona layers go in and it opens again, in about 10 seconds. Do it again after adding or changing a persona.",
    "3. Add the startup line on Home, so your persona's keys come back each time REAPER starts.",
    "4. More than one computer? Settings > Sync: save your setup to a file, or keep them the same through a shared folder." } },
  { "What each page does", {
    "Home > Setup: the first steps, what ReaPersona can use and whether it's there (one click for each), importing from another DAW on this computer, and themes by other people. Drop theme, toolbar, keymap or persona files anywhere on the window to add them.",
    "Personas > DAWs: each DAW's persona, with its keys, look and feel: Use it, its cheat sheet, and a new project like it. Workflow on top (above the cards) adds a kind of session, voiceover or mixing say, to whichever persona is in use: its REAPER settings and what a new project gets, while the persona keeps its keys and look. Your personas: the ones you saved or built, and your workflows. Make your own: New persona (Your personas), then Use in my persona on any tab (a DAW or just its keys, mouse or mixer, a theme, a colour look, a group of REAPER tweaks); the bar at the top shows what's in it, and Save is there. Edit on any persona's page changes it the same way (a DAW persona is saved as your own version). Favourites: the DAWs and personas you starred (the star on a card).",
    "Shortcuts: every key of a persona, with the REAPER action it runs.",
    "Themes > Your themes: the theme for each persona. Get more: the REAPER Stash and ReaPack. Adjust: change the theme in use, live. Build one: a theme from parts of others.",
    "Colours: colour the whole project at once: tracks by gradient, folder or instrument, items by section or take, regions too, with your own colours per instrument, folder and section. Try it first, then keep it or put it back.",
    "Project: what a new project gets with your persona: sample rate, tempo, time signature, grid, starter tracks or a template, a window set.",
    "REAPER: REAPER's and SWS's options, an area per tab (Playback, Editing, Recording, View, Colours & icons, Automation, Monitoring & FX, Mixer); In my persona makes an area part of the persona you're making.",
    "Settings: Sync (your other computers), Personas (what a persona may change, a persona per project, ReaPersona's actions), Scrolling & zoom, Look (this window, the screen-reader menu), Updates, and Remove.",
    "Help > How it works: this page. Check and repair: what's installed, a check of every persona against this REAPER, and registering ReaPersona's actions again." } },
  { "Keyboard", {
    "Tab and Shift+Tab move between controls, the arrow keys move within a page, Enter or Space presses, and Escape closes a menu or clears the search.",
    "Ctrl+K (Cmd+K on a Mac) searches everything: personas, keys, settings and pages, when the window is wide enough to show the search box. F1 opens this page." } },
  { "Screen readers", {
    "This window is drawn by ReaImGui, which a screen reader can't read. ReaPersona's menu it can: a menu at the mouse pointer with the main tasks (pick a persona, back to My REAPER, undo a switch, save what you're using, a new project with a workflow, install the shortcuts, your other computers, the cheat sheet, this help), with each result in a message box.",
    "The action 'ReaPersona - screen-reader menu' (Actions list) always opens it. To have ReaPersona's own action open the menu too, say yes when ReaPersona asks (with OSARA installed), or use the menu's item for it. 'Open ReaPersona's window' opens this window once." } },
  { "Your own setup is safe", {
    "A persona's keys sit in a shortcut layer of their own; keys it doesn't define fall through to yours, and Back to My REAPER puts back whatever a persona changed.",
    "Every install backs up your keymap first, next to it in REAPER's resource folder (reaper-kb.ini.before-reapersona-...). The first backup, from before ReaPersona, is always kept.",
    "Without Python, the install is planned while REAPER runs and a small script (a batch file on Windows, a shell script on a Mac or Linux) swaps it in once REAPER has closed. If anything changed the keymap in between, nothing is swapped in and ReaPersona says so." } },
}
local function guide_text() -- (the whole guide as plain text)
  local out = {}
  for _, s in ipairs(GUIDE) do out[#out + 1] = s[1] .. "\n- " .. table.concat(s[2], "\n- ") end
  return table.concat(out, "\n\n")
end
local function guide_page()
  if card("guide top") then
    heading("How ReaPersona works")
    muted("ReaPersona makes REAPER feel like the DAW you're coming from: its shortcuts, look, feel and mouse, switched in one click, with your own setup always one click away.")
    if ImGui.SmallButton(ctx, "Copy as plain text") then ImGui.SetClipboardText(ctx, guide_text()); say("The guide is on the clipboard.") end
    ImGui.SetItemTooltip(ctx, "The whole guide as plain text, to paste anywhere or read with a screen reader.")
    card_end()
  end
  for i, s in ipairs(GUIDE) do
    if card("guide " .. i) then
      heading(s[1])
      for _, line in ipairs(s[2]) do ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, line) end
      card_end()
    end
  end
end
local function group_of(pg) for _, g in ipairs(GROUPS) do for _, p in ipairs(g[3]) do if p == pg or (pg == "Styles" and p == "DAWs") then return g end end end return GROUPS[2] end
local last_tab = {} -- (each group reopens on the tab you left it on)
-- Search everything (top bar, Ctrl+K): styles, shortcuts in every style, where a DAW's feature is in REAPER, themes, settings, pages.
local function search_page()
  local q = search_q:lower()
  local function has(...) for _, v in ipairs({ ... }) do if type(v) == "string" and v:lower():find(q, 1, true) then return true end end end
  local shown = 0
  local function section(title) heading(title, 15) end
  if card("search") then
    heading("Results for \"" .. search_q .. "\"")
    local hits = {}
    for _, st in ipairs(styles) do if has(st.name, st.id) then hits[#hits + 1] = st end end
    if #hits > 0 then
      section("Styles")
      for i, st in ipairs(hits) do
        if ImGui.SmallButton(ctx, "Use##ss" .. i) then use(st); selected = st.id end
        ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show##ss" .. i) then selected = st.id; search_q = ""; go((st.user or st.preset or st.kind == "built") and "Presets" or "DAWs") end
        ImGui.SameLine(ctx); ImGui.Text(ctx, st.name)
      end
      shown = shown + #hits
    end
    local rows = {}
    for _, st in ipairs(styles) do
      for _, k in ipairs(core.keys_here(st.keys)) do if has(k[1], k[3]) then rows[#rows + 1] = { st, k, "" } end end
      for _, k in ipairs(st.midi_keys or {}) do if has(k[1], k[3]) then rows[#rows + 1] = { st, k, " (piano roll)" } end end
    end
    if #rows > 0 then
      section("Shortcuts (" .. #rows .. ")")
      if ImGui.BeginTable(ctx, "srch keys", 3, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
        ImGui.TableSetupColumn(ctx, "style", ImGui.TableColumnFlags_WidthFixed, 150)
        ImGui.TableSetupColumn(ctx, "key", ImGui.TableColumnFlags_WidthFixed, 150)
        ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
        for i, r in ipairs(rows) do
          if i > 60 then break end
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          if ImGui.Selectable(ctx, (r[1].short or r[1].name) .. "##sk" .. i, false) then keys_for = r[1].id; filter = search_q; search_q = ""; go("Shortcuts") end
          ImGui.TableNextColumn(ctx); keycap(r[2][1])
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, r[2][3] .. r[3])
        end
        ImGui.EndTable(ctx)
      end
      if #rows > 60 then muted((#rows - 60) .. " more: add a word to narrow it down.") end
      shown = shown + #rows
    end
    local where = {}
    for _, st in ipairs(styles) do for _, x in ipairs(st.extras or {}) do if has(x[1]) then where[#where + 1] = { st, x } end end end
    if #where > 0 then
      section("Where it is in REAPER")
      for i, w in ipairs(where) do
        if i > 20 then break end
        if w[2][2] ~= nil then if ImGui.SmallButton(ctx, "Open##sw" .. i) then open_extra(w[2][2]) end; ImGui.SameLine(ctx) end
        ImGui.TextWrapped(ctx, (w[1].short or w[1].name) .. ": " .. w[2][1])
      end
      shown = shown + #where
    end
    theme_list = theme_list or theme_files()
    local th = {}
    for _, t in ipairs(theme_list) do if has(t) then th[#th + 1] = t end end
    if #th > 0 then
      section("Themes")
      for i, t in ipairs(th) do
        if i > 15 then break end
        if ImGui.SmallButton(ctx, "Try##st" .. i) then try_theme(t) end
        ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Use##st" .. i) then trying = nil; reaper.OpenColorThemeFile(themes_dir .. t) end
        ImGui.SameLine(ctx); ImGui.Text(ctx, (t:gsub("%.ReaperTheme.*$", "")))
      end
      shown = shown + #th
    end
    local sets = {}
    for _, g in ipairs(core.SETTING_GROUPS) do
      for _, x in ipairs(g.items) do if type(x[1]) ~= "table" and has(x[2], x.tip, g.name) and core.cmd_id(x[1]) ~= 0 then sets[#sets + 1] = x end end
    end
    if #sets > 0 then
      section("REAPER's defaults")
      for i, x in ipairs(sets) do
        if setting_row("##ssx" .. i, x[2], reaper.GetToggleCommandState(core.cmd_id(x[1])) == 1, x.tip) then reaper.Main_OnCommand(core.cmd_id(x[1]), 0) end
      end
      shown = shown + #sets
    end
    for _, a in ipairs(core.ASPECTS) do
      if has(a[2]) then
        if ImGui.SmallButton(ctx, "Open##sa" .. a[1]) then search_q = ""; go("SetPersonas") end
        ImGui.SameLine(ctx); ImGui.Text(ctx, "What a persona may change: " .. a[2]); shown = shown + 1
      end
    end
    for _, g in ipairs(GROUPS) do
      if has(g[1], g[2], table.concat(g[4], " ")) then
        if ImGui.SmallButton(ctx, "Go##sg" .. g[1]) then search_q = ""; go(g[3][1]) end
        ImGui.SameLine(ctx); ImGui.Text(ctx, "Page: " .. g[1] .. " (" .. g[2] .. ")"); shown = shown + 1
      end
    end
    if shown == 0 then muted("Nothing found. Try a shorter word, like \"split\", \"mixer\" or \"loop\".") end
    card_end()
  end
end
local function top_bar(alt)
  local cur = core.current()
  local y0 = ImGui.GetCursorPosY(ctx) -- (below the title bar)
  ImGui.SetCursorPos(ctx, 16, y0 + 10)
  ImGui.PushFont(ctx, bold, 20 * UI); ImGui.Text(ctx, "ReaPersona"); ImGui.PopFont(ctx)
  ImGui.SameLine(ctx, 0, 14)
  ImGui.SetCursorPosY(ctx, y0 + 13)
  local col = accent_of(cur)
  local wf = core.current_workflow()
  pill(cur.name .. (wf and wf.id ~= cur.id and ("  +  " .. wf.name) or "") .. (in_use(cur, alt) and "" or "  (keys off)"), solid(col))
  if not in_use(cur, alt) then ImGui.SetItemTooltip(ctx, "Its shortcut layer isn't on (REAPER restarted?): Use it again, or add the startup line on Home so it comes back each time REAPER starts.") end
  local w = ImGui.GetWindowWidth(ctx)
  if w > 760 then -- (search, Ctrl+K; on a narrow window it's left out of the bar)
    ImGui.SameLine(ctx, 0, 16)
    ImGui.SetCursorPosY(ctx, y0 + 8)
    if ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_K) or search_focus then ImGui.SetKeyboardFocusHere(ctx); search_focus = false end
    ImGui.SetNextItemWidth(ctx, math.min(260, w - ImGui.GetCursorPosX(ctx) - 320))
    local _, q = ImGui.InputTextWithHint(ctx, "##search", "Search everything (" .. MOD .. "+K)", search_q)
    search_q = q
  end
  if search_q ~= "" and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then search_q = "" end
  local undo = last_style and last_style ~= cur.id and core.by_id(last_style)
  local right = (undo and 520 or 410) * UI
  local after = ImGui.GetItemRectMax(ctx) - ImGui.GetWindowPos(ctx) + 12
  if w - right >= after then ImGui.SameLine(ctx, w - right); ImGui.SetCursorPosY(ctx, y0 + 8) else ImGui.SetCursorPosX(ctx, 16) end
  if undo then
    if ImGui.Button(ctx, "Undo switch") then use(undo) end
    ImGui.SetItemTooltip(ctx, "Back to " .. undo.name .. ", as it was before you switched.")
    ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, "Save what I'm using...##top") then save_preset_prompt() end
  ImGui.SetItemTooltip(ctx, "Keep what's in use now, under a name: the persona's keys and toolbar, the theme, the layout, snap and the mouse behaviours as they are right now.")
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, cur.id == "my_reaper")
  if ImGui.Button(ctx, "Back to My REAPER") then use(core.by_id("my_reaper")) end
  ImGui.EndDisabled(ctx)
  ImGui.SetItemTooltip(ctx, "Your own shortcuts, theme and settings, exactly as you had them.")
  ImGui.SameLine(ctx)
  feedback.button(ctx, ImGui)
  ImGui.SetCursorPosY(ctx, math.max(y0 + 48, ImGui.GetCursorPosY(ctx) + 4))
  ImGui.Separator(ctx)
end

local last_error, last_logged
local first_frame = true
local function frame()
  ImGui.SetNextWindowSize(ctx, 980, 760, ImGui.Cond_FirstUseEver)
  for _, c in ipairs(COLS) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  for _, v in ipairs(VARS) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
  ImGui.PushFont(ctx, font, 15 * UI)
  ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Once) -- (a window an older version left in a docker comes out once)
  local visible, open = ImGui.Begin(ctx, "ReaPersona", true, ImGui.WindowFlags_NoDocking)
  if visible then
    if ensure_new or core.stubs_stale then core.ensure_scripts(); ensure_new = false end
    core.apply_midi_dock() -- (a style's MIDI editor docking waits for an editor to be open)
    local ask = reaper.GetExtState(SECTION, "search") -- (a search asked for from outside: another script, or a test)
    if ask ~= "" then search_q = ask; reaper.DeleteExtState(SECTION, "search", false) end
    if first_frame then
      first_frame = false
      if reaper.GetExtState(SECTION, "page") == "" and setup_todo() then go("Setup") end
      local note = core.read(here .. "/last_install.txt")
      if note then -- (what the last one-button install did, in a few words; the details stay in the backup's name)
        os.remove(here .. "/last_install.txt")
        local n = note:match("installed (%d+) shortcut")
        say(n and ("Shortcuts installed (" .. n .. "). Your old keymap was backed up first.") or ((note:gsub("%s+$", "")):match("[^\n]*$") or ""):sub(1, 120))
      end
    end
    local alt = core.active_alt()
    local sel = core.by_id(selected) or styles[1]
    local want = reaper.GetExtState(SECTION, "page")
    if want ~= "" and want ~= page then page = want end
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) and ImGui.IsKeyPressed(ctx, ImGui.Key_F1) then go("Guide") end
    top_bar(alt)
    trying_bar()
    if last_error then
      ImGui.SetCursorPosX(ctx, 16)
      ImGui.TextColored(ctx, C.RED, "Something went wrong and was written to errors.log: " .. last_error)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "OK##err") then last_error = nil end
    end
    local narrow = ImGui.GetWindowWidth(ctx) < 600 -- (a small window: the sidebar becomes a drop-down)
    if narrow then
      ImGui.SetCursorPosX(ctx, 16)
      ImGui.SetNextItemWidth(ctx, -16)
      if ImGui.BeginCombo(ctx, "##navc", group_of(page)[1] .. (setup_todo() and "  (Home: something to do)" or "")) then
        for _, g in ipairs(GROUPS) do if ImGui.Selectable(ctx, g[1] .. "##navc", g == group_of(page)) then go(last_tab[g[1]] or g[3][1]) end end
        ImGui.EndCombo(ctx)
      end
    end
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.NAV)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0, 0.5)
    if not narrow and ImGui.BeginChild(ctx, "nav", 150, 0, ImGui.ChildFlags_AlwaysUseWindowPadding) then
      ImGui.PushFont(ctx, nil, 16 * UI)
      local cur_g = group_of(page)
      for _, g in ipairs(GROUPS) do
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.Selectable(ctx, "  " .. g[1] .. "##nav", g == cur_g, ImGui.SelectableFlags_None, 0, 36) then go(last_tab[g[1]] or g[3][1]) end
        ImGui.SetItemTooltip(ctx, g[2])
        if g == cur_g then ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), x - 8, y + 6, x - 4, y + 30, C.ACCENT, 2) end
        if g[1] == "Home" and setup_todo() then ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), x + 112, y + 18, 4, C.YELLOW) end -- (something to do)
      end
      ImGui.PopFont(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx)
    if not narrow then ImGui.SameLine(ctx, 0, 0) end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 12)
    if ImGui.BeginChild(ctx, "page", 0, 0, ImGui.ChildFlags_AlwaysUseWindowPadding) then
      local g = group_of(page)
      last_tab[g[1]] = page
      if #g[3] > 1 then -- (the group's pages as tabs)
        local row_end = ImGui.GetCursorScreenPos(ctx) + ImGui.GetContentRegionAvail(ctx) -- (5.35: tabs that don't fit go on a second line)
        for i, pg in ipairs(g[3]) do
          local tw = ImGui.CalcTextSize(ctx, g[4][i]) + 24
          if i > 1 then
            ImGui.SameLine(ctx)
            if ImGui.GetCursorScreenPos(ctx) + tw > row_end then ImGui.NewLine(ctx) end
          end
          if ImGui.Selectable(ctx, g[4][i] .. "##tab", page == pg or (page == "Styles" and pg == "DAWs"), ImGui.SelectableFlags_None, tw, 28) then go(pg) end
        end
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 0, 2)
      end
      if search_q == "" then draft_strip() end -- (the persona being made, over every tab)
      if core.prefs_queued then core.prefs_queued = false; say("Some of this persona's REAPER preferences go in when REAPER restarts: REAPER > Preferences has Restart REAPER now.") end
      if search_q ~= "" then search_page()
      elseif page == "Setup" then setup_page()
      elseif page == "DAWs" or page == "Styles" then daws_page(sel, alt)
      elseif page == "Themes" then themes_page(sel, alt)
      elseif page == "Browse" then browse_page()
      elseif page == "Presets" then presets_page(sel, alt)
      elseif page == "Builder" or page == "Favourites" then favourites_page(sel, alt)
      elseif page == "Mouse" then mouse_page()
      elseif page == "Layout" then layout_page()
      elseif page == "Project" then project_page()
      elseif page == "Settings" then settings_page("sync")
      elseif page == "SetPersonas" then settings_page("personas")
      elseif page == "SetScroll" then settings_page("scroll")
      elseif page == "SetLook" then settings_page("look")
      elseif page == "SetUpdates" then settings_page("updates")
      elseif page == "SetRemove" then settings_page("remove")
      elseif page == "Tweaks" then tweaks_page("playback") -- (the old REAPER tweaks page: REAPER's first tab)
      elseif page == "R_prefs" then prefs_page()
      elseif page:match("^R_") then tweaks_page(page:sub(3))
      elseif page == "Shortcuts" then keys_page()
      elseif page == "Adjust" then
        if adjust_out then
          if card("adj out") then heading("Adjust is in its own window"); if ImGui.Button(ctx, "Bring it back here") then adjust_out = false end; card_end() end
        else adjust_page(core.current()) end -- (the theme you adjust is the one in use: its style gets the result)
      elseif page == "Merge" then merge_page(sel)
      elseif page == "Colours" then
        if card("col persona") then -- (5.28: a persona's default colours, apart from colouring this project)
          heading("Your persona's colours", 16)
          muted("The persona's default colour look, for projects that haven't got their own. A project you colour below keeps its own colours, whichever persona is in use.")
          ImGui.Indent(ctx, IND * UI)
          local inb = core.draft_get(bld.blocks, "colours")
          ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, inb and core.colours_label(inb.set) or "None: your own")
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Set as this persona's default##colset") then in_persona(core.new_block("colours"), "The colour look below") end
          ImGui.SetItemTooltip(ctx, "Takes the colour look as set below (and your instrument, folder and section colours) as the persona's default.")
          if inb then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "None##colnone") then core.draft_clear(bld.blocks, "colours") end end
          ImGui.SameLine(ctx); ImGui.Text(ctx, "  Load from:"); ImGui.SameLine(ctx)
          ImGui.SetNextItemWidth(ctx, 200 * UI)
          if ImGui.BeginCombo(ctx, "##colfrom", "a persona of yours") then
            for _, st in ipairs(sources(function(s) return s.colours ~= nil end)) do
              if ImGui.Selectable(ctx, st.name .. "##cf" .. st.id) then core.draft_add(bld.blocks, { kind = "colours", set = st.colours }); bld.active = true end
            end
            ImGui.EndCombo(ctx)
          end
          ImGui.Unindent(ctx, IND * UI)
          card_end()
        end
        colours.draw(ctx, ImGui, reaper.EnumProjects(-1))
      elseif page == "Guide" then guide_page()
      elseif page == "Check" then check_page() end
      ImGui.EndChild(ctx)
    end
    setup_progress() -- (Set up everything's progress window, over the page)
    if ImGui.BeginDragDropTarget(ctx) then -- (files dropped anywhere on the page: themes, packs, toolbars, keymaps, styles, presets)
      local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
      if rv then
        local got = {}
        for i = 0, count - 1 do
          local ok, fn = ImGui.GetDragDropPayloadFile(ctx, i)
          if ok then core.import_file(fn, got) end
        end
        drop_report(got)
      end
      ImGui.EndDragDropTarget(ctx)
    end
    ImGui.PopStyleVar(ctx)
    if reaper.time_precise() < toast_until then -- (what just happened, bottom right, for a few seconds)
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      local tw, th = ImGui.CalcTextSize(ctx, toast)
      local fl = ImGui.GetForegroundDrawList(ctx)
      ImGui.DrawList_AddRectFilled(fl, wx + ww - tw - 40, wy + wh - th - 34, wx + ww - 16, wy + wh - 16, solid(mix(P.text, P.accent, 0.4)), 8)
      ImGui.DrawList_AddText(fl, wx + ww - tw - 28, wy + wh - th - 25, on_colour(mix(P.text, P.accent, 0.4)), toast)
    end
    ImGui.End(ctx)
  end
  if adjust_out then
    ImGui.SetNextWindowSize(ctx, 520, 680, ImGui.Cond_FirstUseEver)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 10)
    ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Once)
    local v2, o2 = ImGui.Begin(ctx, "ReaPersona: theme adjuster", true, ImGui.WindowFlags_NoDocking)
    if v2 then adjust_page(core.current()); ImGui.End(ctx) end
    ImGui.PopStyleVar(ctx)
    if not o2 then adjust_out = false end
  end
  feedback.draw(ctx, ImGui, core, feedback.VERSION, say)
  ImGui.PopFont(ctx)
  ImGui.PopStyleVar(ctx, #VARS)
  ImGui.PopStyleColor(ctx, #COLS)
  return open
end
-- One frame at a time, protected: an error is logged and the window starts a fresh ImGui context (a frame cut short leaves the old one
-- unbalanced), instead of the whole window closing with a ReaScript error.
local errors_in_a_row = 0
local starts_next = 0
local function loop()
  trial_over()
  if core.starts_missing and #core.starts_missing > 0 and reaper.time_precise() > starts_next then -- (installed through ReaPack since? started, and started with REAPER)
    starts_next = reaper.time_precise() + 3
    local ok, added, _, still = pcall(core.ensure_starts, core.starts_missing)
    if ok then core.starts_missing = still; if #added > 0 then say(table.concat(added, ", ") .. " installed: started, and starts with REAPER from now on.") end end
  end
  if reaper.time_precise() > sync_next and core.sync_folder() ~= "" then sync_step() end
  if quit_check and reaper.time_precise() > quit_check then
    quit_check = nil
    core.write(here .. "/install_cancelled", "quit was cancelled\n")
    say("REAPER didn't close, so the shortcuts weren't installed.")
  end
  if removing and not core.busy() then removing = nil; if not remove_finish() then return end end -- (My REAPER's windows are back)
  local ok, open = xpcall(frame, debug.traceback)
  errors_in_a_row = ok and 0 or errors_in_a_row + 1
  if not ok then
    if open ~= last_logged then core.log(open); last_logged = open end
    last_error = tostring(open):match("^[^\n]*"):gsub("^.-ReaPersona[/\\]", "")
    if errors_in_a_row >= 2 then -- (a page that fails every frame: back to the styles, so the window stays usable)
      page, selected = "DAWs", core.current().id
      reaper.SetExtState(SECTION, "page", page, false)
    end
    ctx = new_ctx()
    font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
    bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
    for k in pairs(images) do images[k] = nil end
    open = true
  end
  if open then reaper.defer(loop) end
end
-- ---------------------------------------------------------------- the screen-reader route (5.14)
-- ReaImGui draws its window itself, so NVDA, JAWS or VoiceOver (through OSARA) read nothing in it. This is REAPER's own menu (gfx.showmenu),
-- which they read, with the main tasks; every result comes in a message box, and OSARA speaks what say() says.
local function show_menu(labels) -- -> the 1-based item picked (separators don't count), or 0
  local x, y = reaper.GetMousePosition()
  gfx.init("ReaPersona", 0, 0, 0, x, y)
  gfx.x, gfx.y = 0, 0
  local i = gfx.showmenu(table.concat(labels, "|"))
  gfx.quit()
  return i
end
local function status_text()
  local cur, alt = core.current(), core.active_alt()
  local have, want = shortcuts_state()
  local wf = core.current_workflow()
  local t = { "Persona in use: " .. cur.name .. (in_use(cur, alt) and "" or " (its keys are off: pick it again)") .. (wf and (", with the workflow " .. wf.name .. " on top") or ""),
    "Shortcut layers installed: " .. have .. " of " .. want .. " personas" .. (have < want and " (install the shortcuts next)" or ""),
    "Persona back at REAPER's start: " .. (core.startup_on() and "yes" or "no (add the startup line)"),
    core.sync_folder() ~= "" and ("Syncing with your other computers through " .. core.sync_folder()) or "Not syncing with other computers." }
  local pend = core.restart_pending()
  if #pend > 0 then t[#t + 1] = "Waiting for REAPER to restart: " .. table.concat(pend, ", ") end
  return table.concat(t, "\n")
end
local function screen_reader_menu(once) -- -> true: open the window instead. once: opened by 'ReaPersona - screen-reader menu'
  menu_mode = true
  local note = core.read(here .. "/last_install.txt")
  if note then os.remove(here .. "/last_install.txt"); reaper.MB(note, "ReaPersona: the last install", 0) end
  while true do
    local cur = core.current()
    local labels, acts = {}, {}
    local function item(label, fn) labels[#labels + 1] = (label:gsub("^[#!><]+", ""):gsub("|", "/"):gsub("&", "&&")); acts[#acts + 1] = fn end
    local function sep() labels[#labels + 1] = "" end
    item("Persona in use: " .. cur.name .. ". What's installed", function() reaper.MB(status_text(), "ReaPersona", 0) end)
    item("Pick a persona...", function()
      local names, list = {}, {}
      for _, st in ipairs(styles) do
        list[#list + 1] = st
        names[#names + 1] = (st == cur and "!" or "") .. (st.name:gsub("^[#!><]+", ""):gsub("|", "/"):gsub("&", "&&")) .. (st.user and " (yours)" or "")
      end
      local i = show_menu(names)
      if list[i] then selected = list[i].id; use(list[i]) end
    end)
    if cur.id ~= "my_reaper" then item("Back to My REAPER", function() use(core.by_id("my_reaper")) end) end
    local undo = last_style and last_style ~= cur.id and core.by_id(last_style)
    if undo then item("Undo switch: back to " .. undo.name, function() use(undo) end) end
    item("Save what I'm using as a persona...", save_preset_prompt)
    local wf = core.current_workflow()
    item("Workflow on top: " .. (wf and wf.name or "none") .. ". Pick a workflow...", function()
      local names, ids = { (wf and "" or "!") .. "None: the persona on its own" }, { "" }
      for _, x in ipairs(core.workflow_list()) do
        ids[#ids + 1] = x.id
        names[#names + 1] = (wf and wf.id == x.id and "!" or "") .. (x.name:gsub("^[#!><]+", ""):gsub("|", "/"):gsub("&", "&&")) .. (x.mine and " (yours)" or "")
      end
      local i = show_menu(names)
      if ids[i] then pick_workflow(ids[i]) end
    end)
    if wf and wf.project then
      item("New project with " .. wf.name, function() workflow_new_project(wf) end)
      if reaper.CountTracks(0) > 0 then item("Keep this project's track inputs for " .. wf.name .. " on this computer", function() workflow_keep_inputs(wf) end) end
    end
    if cur.project and not (wf and wf.project) then
      item("New project with " .. cur.name, function()
        if not core.fresh_project(0) then reaper.Main_OnCommand(41929, 0) end
        local done = core.apply_project(cur)
        say("A new project with " .. cur.name .. (#done > 0 and (": " .. table.concat(done, ", ")) or "") .. ".")
      end)
      if reaper.CountTracks(0) > 0 then
        item("Keep this project's track inputs for " .. cur.name .. " on this computer", function()
          local n = core.keep_inputs(cur.id)
          say("Kept the inputs of " .. n .. " track" .. (n == 1 and "" or "s") .. ": new projects with " .. cur.name .. " on this computer get them.")
        end)
      end
    end
    item("Cheat sheet for " .. cur.name .. " (opens in your browser)", function() local p, why = core.cheat_sheet(cur); if p then core.open_url(p) else say(why) end end)
    sep()
    local have, want = shortcuts_state()
    item((have < want and "Install" or "Reinstall") .. " the shortcuts (REAPER restarts)", "install")
    if not core.startup_on() then item("Bring your persona back when REAPER starts (adds the startup line)", function() local ok, why = core.add_startup(); say(ok and "Startup line added." or tostring(why)) end) end
    sep()
    if core.sync_folder() ~= "" then item("Sync with your other computers now", function() sync_step(true) end)
    else item("Keep your computers the same through a shared folder...", choose_sync_folder) end
    item("Save your setup to a file...", save_setup_file)
    item("Load a setup file...", load_setup_file)
    if #core.restart_pending() > 0 then item("Apply what came from your other computers (REAPER restarts)", "install") end
    sep()
    item("How ReaPersona works", function() reaper.MB(guide_text(), "ReaPersona: how it works", 0) end)
    item("Open ReaPersona's window", "window")
    if reaper.GetExtState(SECTION, "screen reader") == "1" then
      item("ReaPersona's own action opens the window from now on", function()
        reaper.SetExtState(SECTION, "screen reader", "0", true); say("ReaPersona's action opens its window from now on. The action 'ReaPersona - screen-reader menu' still opens this menu.")
      end)
    else
      item("ReaPersona's own action opens this menu from now on", function()
        reaper.SetExtState(SECTION, "screen reader", "1", true); say("ReaPersona's action opens this menu from now on.")
      end)
    end
    local fn = acts[show_menu(labels)]
    if not fn then return false end
    if fn == "window" then return true end
    if fn == "install" then install_shortcuts(); return false end
    said = nil
    fn()
    if said then reaper.MB(said, "ReaPersona", 0) end
    if not once and reaper.GetExtState(SECTION, "screen reader") ~= "1" then return false end
  end
end
if reaper.osara_outputMessage and reaper.GetExtState(SECTION, "screen reader") == "" then -- (OSARA installed: ask once)
  reaper.SetExtState(SECTION, "screen reader", reaper.MB("OSARA is installed, so you may be using a screen reader. ReaPersona's window can't be read by one; its menu can.\n\n" ..
    "Open the menu instead of the window each time? (The action 'ReaPersona - screen-reader menu' opens it either way.)", "ReaPersona", 4) == 6 and "1" or "0", true)
end
local once = reaper.GetExtState(SECTION, "menu once") == "1" -- (the action 'ReaPersona - screen-reader menu': the menu, whatever the setting)
reaper.DeleteExtState(SECTION, "menu once", false)
local from_menu = once or reaper.GetExtState(SECTION, "screen reader") == "1"
if from_menu and not screen_reader_menu(once) then
  local function wait_quit() -- (the install's quit, cancelled: the batch step or the Python is told, as loop() does for the window)
    if not quit_check then return end
    if reaper.time_precise() < quit_check then return reaper.defer(wait_quit) end
    quit_check = nil
    core.write(here .. "/install_cancelled", "quit was cancelled\n")
    reaper.MB("REAPER didn't close, so the shortcuts weren't installed.", "ReaPersona", 0)
  end
  wait_quit()
  return
end
menu_mode = false
if from_menu then -- (the window from the menu: ReaImGui let go of the context made at the start while the menu was open, unused)
  ctx = new_ctx()
  font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
  bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
end
local cmd = select(4, reaper.get_action_context()) -- (the picker's own action: lit on a toolbar while the window is open)
if cmd and cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, 1); reaper.RefreshToolbar2(0, cmd) end
reaper.atexit(function()
  if trying then trying.ends = 0; trial_over() end -- (a theme on trial goes back when the window closes)
  pcall(colours.put_back_all) -- (and colours being tried)
  pcall(core.sync_tick) -- (what you changed while it was open, to your other computers)
  if cmd and cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, 0); reaper.RefreshToolbar2(0, cmd) end
end)
pcall(core.upgrade_startup) -- (now too, not only at REAPER's start: updated and removed in one session left the old block. Review, 5.9.4)
reaper.defer(loop)
