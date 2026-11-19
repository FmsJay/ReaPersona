-- ReaPersona's window: set up: ImGui, the engine, look and colours, fonts, the small helpers, say/go/use.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 18-343.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
ImGui = require "imgui" "0.10"
here = here -- (the ReaPersona folder: R.here, set by ReaPersona.lua; said here so the language server knows it)
core = dofile(here .. "/reapersona_core.lua")
feedback = dofile(here .. "/reapersona_feedback.lua") -- (the Feedback button and its window, as StudioSync has them)
feedback.VERSION = core.version() -- (cached in the engine: the window's file isn't read a second time)
styles, SECTION, themes_dir = core.styles, core.SECTION, core.themes_dir
res = reaper.GetResourcePath()

-- Shortcut lines per style layer, and MIDI editor keys bound to ReaPersona scripts. (Not by install_shortcuts.py's tag: REAPER rewrites the
-- file's comments when it saves it.)
function count_installed() -- (at load, and again when the window is back after a Flatpak keymap import: round 3)
  installed, midi_installed = {}, 0
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
count_installed()
if core.scripts_missing() > 0 then core.ensure_scripts() end -- (first run, or a new style: the one-key actions and MIDI key scripts)

function run_script(rel)
  local p = res .. "/Scripts/" .. rel
  if not reaper.file_exists(p) then return false end
  local id = reaper.AddRemoveReaScript(true, 0, p, true)
  if id ~= 0 then reaper.Main_OnCommand(id, 0); return true end
end
function theme_files()
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
PALETTES = {
  Dark = { bg = 0x1A1C1F, card = 0x26292E, nav = 0x1F2124, text = 0xE6E8EB, muted = 0x8D939B, accent = 0x4C8DF6,
    green = 0x59CC73, yellow = 0xF2BF40, red = 0xE0605A },
  Light = { bg = 0xF2F3F5, card = 0xFFFFFF, nav = 0xE4E6EA, text = 0x1F2328, muted = 0x626A73, accent = 0x2F6FE0,
    green = 0x1C8A47, yellow = 0x9A6B00, red = 0xC8372F },
  Midnight = { bg = 0x0F1626, card = 0x1B2540, nav = 0x141D32, text = 0xE3E9F5, muted = 0x8A97B3, accent = 0x6C8CFF,
    green = 0x5AD08F, yellow = 0xF0C25A, red = 0xEE6B7A },
  Warm = { bg = 0x221D18, card = 0x312A23, nav = 0x29231D, text = 0xEFE6DA, muted = 0xA19383, accent = 0xE0954A,
    green = 0x8CC56A, yellow = 0xEDC05A, red = 0xE5705A },
}
function mix(a, b, t) -- a towards b, each channel; no alpha
  local out = 0
  for s = 16, 0, -8 do
    local x, y = a >> s & 0xFF, b >> s & 0xFF
    out = out | math.floor(x + (y - x) * t + 0.5) << s
  end
  return out
end
function solid(c) return c << 8 | 0xFF end
function hex(s, fallback) local n = tonumber((s or ""):match("^#?(%x%x%x%x%x%x)$") or "", 16); return n or fallback end
P, C = nil, {}
-- (in R: COLS) -- (filled by apply_look below)
function apply_look() -- the palette from Settings > look (else StudioSync's), into P, C and the ImGui colours; live
  P = PALETTES[reaper.GetExtState(SECTION, "look")] or PALETTES[reaper.GetExtState("BandSync", "theme")] or PALETTES.Dark
  C.BG, C.CARD, C.CARD_HOVER, C.NAV, C.TEXT = solid(P.bg), solid(P.card), solid(mix(P.card, P.text, 0.05)), solid(P.nav), solid(P.text)
  C.MUTED, C.ACCENT, C.GREEN, C.YELLOW, C.RED = solid(P.muted), solid(P.accent), solid(P.green), solid(P.yellow), solid(P.red)
  C.FRAME, C.KEYCAP, C.BANNER = solid(mix(P.bg, P.text, 0.16)), solid(mix(P.card, P.text, 0.12)), solid(mix(P.card, P.yellow, 0.16))
  if COLS then COLS.fill() end
end
function accent_of(st) return hex(st.accent, P.accent) end
function t(x) return solid(mix(P.bg, P.text, x)) end
function a(x) return solid(mix(P.bg, P.accent, x)) end

function new_ctx() -- (keyboard navigation on: Tab, arrows, Enter, Esc)
  local c = ImGui.CreateContext("ReaPersona")
  ImGui.SetConfigVar(c, ImGui.ConfigVar_Flags, ImGui.GetConfigVar(c, ImGui.ConfigVar_Flags) | ImGui.ConfigFlags_NavEnableKeyboard)
  return c
end
ctx = new_ctx()
font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
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
VARS = {
  { ImGui.StyleVar_WindowPadding, 0, 0 }, { ImGui.StyleVar_FramePadding, 10, 6 }, { ImGui.StyleVar_ItemSpacing, 8, 8 },
  { ImGui.StyleVar_FrameRounding, 6 }, { ImGui.StyleVar_ChildRounding, 10 }, { ImGui.StyleVar_WindowRounding, 8 },
  { ImGui.StyleVar_GrabRounding, 6 }, { ImGui.StyleVar_PopupRounding, 6 }, { ImGui.StyleVar_ScrollbarRounding, 8 },
  { ImGui.StyleVar_ChildBorderSize, 0 }, { ImGui.StyleVar_FrameBorderSize, 1 }, { ImGui.StyleVar_CellPadding, 8, 5 },
}

function on_colour(col) -- dark or white text, whichever reads better on col (WCAG contrast ratio)
  local function lin(c) c = c / 255; return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
  local L = 0.2126 * lin(col >> 16 & 255) + 0.7152 * lin(col >> 8 & 255) + 0.0722 * lin(col & 255)
  return (L + 0.05) / 0.0545 >= 1.05 / (L + 0.05) and 0x15171AFF or 0xFFFFFFFF -- (0x15171A's luminance is about 0.0045)
end
-- A rounded label: status at a glance.
function pill(text, bg, fg)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = ImGui.CalcTextSize(ctx, text)
  ImGui.Dummy(ctx, w + 16, h + 6)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w + 16, y + h + 6, bg, (h + 6) / 2)
  ImGui.DrawList_AddText(dl, x + 8, y + 3, fg or on_colour(bg >> 8), text)
end
IS_MAC = core.IS_MAC
-- A Flatpak REAPER (Linux): when REAPER quits, Flatpak ends everything it started, an install waiting for it too, so nothing goes in
-- with a restart. The shortcuts go in by import; the rest with the installer run from a terminal while REAPER is closed. (Cross-platform
-- review 2026-11-19; the command lines are the installer's own, round 2)
FLATPAK = not IS_MAC and not reaper.GetOS():find("^Win") and reaper.file_exists("/.flatpak-info")
function flatpak_cmd(args) -- the terminal command, also put on the clipboard: Linux message boxes can't be copied from (round 3)
  local c = "python3 '" .. (here .. "/install_shortcuts.py"):gsub("'", "'\\''") .. "' " .. args -- (single quotes: a $ or ! in the path stays as it is)
  if reaper.CF_SetClipboard then reaper.CF_SetClipboard(c) else ImGui.SetClipboardText(ctx, c) end
  return c
end
-- Where a persona's shortcuts go in, and the button that puts in what waits for a restart: a Flatpak REAPER can't restart itself.
INSTALL_WHERE = FLATPAK and "Home > Install (you import them; the steps say how)" or "Home > Install and restart"
RESTART_BUTTON = FLATPAK and "How to put them in" or "Restart REAPER now"
RESTART_TIP = FLATPAK and "This Flatpak REAPER can't restart itself: the steps say what to run in a terminal while REAPER is closed."
  or "REAPER closes (asking about anything unsaved), these go in (what's replaced is backed up first), and it opens again."
keyname = core.keyname -- (on a Mac REAPER's Ctrl is Cmd, Alt is Option and Win is Control: styles store Windows names)
function keycap(text) -- a key, drawn like one
  text = keyname(text)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = ImGui.CalcTextSize(ctx, text)
  ImGui.Dummy(ctx, w + 12, h + 4)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w + 12, y + h + 4, C.KEYCAP, 4)
  ImGui.DrawList_AddText(dl, x + 6, y + 2, C.TEXT, text)
end
UI = (tonumber(reaper.GetExtState(SECTION, "text size")) or 15) / 15 -- (Settings > text size)
IND = 18 -- (what edits the persona sits a little to the right, so it reads as part of it. 5.28) (up here: the persona pages use it too, 5.36)
function heading(text, size)
  ImGui.PushFont(ctx, bold, (size or 17) * UI)
  ImGui.Text(ctx, text)
  ImGui.PopFont(ctx)
end
function muted(text) ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.MUTED); ImGui.TextWrapped(ctx, text); ImGui.PopStyleColor(ctx) end
-- A card: a rounded panel sized to what's in it. Returns true when its content should be drawn (then call card_end).
function card(id)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.CARD)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 14)
  local open = ImGui.BeginChild(ctx, id, 0, 0, ImGui.ChildFlags_AutoResizeY | ImGui.ChildFlags_AlwaysUseWindowPadding, ImGui.WindowFlags_NoScrollbar)
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
  if open then ImGui.PushTextWrapPos(ctx, 0) end
  return open
end
function card_end() ImGui.PopTextWrapPos(ctx); ImGui.EndChild(ctx); ImGui.Dummy(ctx, 0, 2) end
-- The button that does the main thing, in the style's own colour.
function primary(label, col)
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
COLOURS = {
  { "col_arrangebg", "Arrange background" }, { "col_tr1_bg", "Track background (odd)" }, { "col_tr2_bg", "Track background (even)" },
  { "selcol_tr1_bg", "Selected track (odd)" }, { "selcol_tr2_bg", "Selected track (even)" }, { "col_tr1_itembgsel", "Selected item" },
  { "col_cursor", "Edit cursor" }, { "playcursor_color", "Play cursor" }, { "col_gridlines", "Grid lines" },
  { "col_seltrack", "Selected track control panel" }, { "col_main_bg2", "Window background" }, { "col_main_text2", "Text" },
  { "col_mi_bg", "MIDI editor background" }, { "col_mi_note", "MIDI note" } }
changed, changed_on = {}, nil -- key -> native colour, what's been tweaked since the theme was loaded; and that theme
-- (declared here, before save_fork: it set a global of that name, so a theme on trial still went back after you saved it. Review, 5.9.3)
-- (in R: trying, try_theme) -- (a theme on trial: { name, back = the theme to go back to, ends = time }; set up with the setup helpers)
function refresh() reaper.ThemeLayout_RefreshAll(); reaper.UpdateArrange(); reaper.TrackList_AdjustWindows(false) end
function add_fork(st, name)
  if core.is_trial() and st == core.current() then -- (a theme saved or added while a preview shows belongs to the persona being made: it went on My REAPER's list. Review 2026-11-19)
    core.draft_add(bld.blocks, core.new_block("theme", name)); bld.active = true
    return
  end
  local list = reaper.GetExtState(SECTION, "forks " .. st.id)
  if not ("|" .. list .. "|"):find("|" .. name .. "|", 1, true) then -- (once each)
    reaper.SetExtState(SECTION, "forks " .. st.id, (list ~= "" and (list .. "|") or "") .. name, true)
  end
  reaper.SetExtState(SECTION, "theme " .. st.id, name, true)
end
function remove_fork(st, name) -- (a theme you added to a persona's versions, taken off the list; the file stays)
  local keep = {}
  for f in reaper.GetExtState(SECTION, "forks " .. st.id):gmatch("[^|]+") do if f ~= name then keep[#keep + 1] = f end end
  reaper.SetExtState(SECTION, "forks " .. st.id, table.concat(keep, "|"), true)
  if reaper.GetExtState(SECTION, "theme " .. st.id) == name then reaper.DeleteExtState(SECTION, "theme " .. st.id, true) end
end

-- Save what's been tweaked as a theme of its own (a local fork): a .ReaperTheme over the same images. A .ReaperTheme in use is copied with
-- your colours put in (its fonts and all kept); for a .ReaperThemeZip, every colour REAPER reports for it now (the theme's own, then yours)
-- is written out, from colour_keys.txt, and the zip named as its images. -> its file name, or nil + why
function save_fork(st, current)
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
images = {}
images_left = 2 -- (pictures loaded this frame: 2 at most, frame() resets it. 17 at once held the first frame 100 ms. Performance review 2026-11-19)
function preview(st)
  local id = st.preset and st.base or st.id -- (a preset shows its style's picture)
  if images[id] == nil then
    if images_left <= 0 then return nil end -- (its card shows its colour until the picture comes, a frame or two later)
    images_left = images_left - 1
    local p = here .. "/previews/" .. id .. ".png"
    images[id] = reaper.file_exists(p) and ImGui.CreateImage(p) or false
    if images[id] then ImGui.Attach(ctx, images[id]) end
  end
  return images[id] or nil
end
selected, filter, pfilter = reaper.GetExtState(SECTION, "style"), "", ""
page = reaper.GetExtState(SECTION, "page") ~= "" and reaper.GetExtState(SECTION, "page") or "DAWs" -- (the page you were on)
search_q, search_focus = "", false -- (search everything: top bar, Ctrl+K)
MOD = (reaper.GetOS():find("^OSX") or reaper.GetOS():find("^mac")) and "Cmd" or "Ctrl" -- (what ImGui's Ctrl is called on this computer)
-- (in R: page_name, page_shown, set_advanced) -- (a page's name as the window shows it, whether Show everything hides it, the switch: set up after GROUPS)
function go(pg) -- (a screen reader with OSARA hears the page's name)
  page = pg; search_q = ""; reaper.SetExtState(SECTION, "page", pg, false)
  if bld and bld.kq then bld.kq.cap = nil end -- (a key capture left open on Shortcuts stopped Ctrl+Z on every tab)
  if reaper.osara_outputMessage then reaper.osara_outputMessage(pg == "Guide" and "How it works" or (page_name and page_name(pg)) or pg) end
end
merge = { base = "Default_7.0.ReaperThemeZip", colours = "", graphics = "", parts = {}, fonts = false, msg = "" }
PARTS = { "faders", "knobs", "meters", "transport", "buttons", "toolbar", "backgrounds" }
-- (in R: bld) -- (the persona being made: set up with the tabs' section; pages above it, Adjust say, reach it through this. 5.35)
-- (in R: bld_load) -- (starts the persona being made from one you have; set up with the tabs' section)
-- (in R: in_persona, persona_row, bld_new, persona_keys_card, persona_theme_line, shortcuts_page, rpage, read_rpage) -- (any tab: a block into the persona being made, and the "Use in my persona" buttons for one persona; 5.26)
-- (in R: drop_report, install_theme_ui) -- (what came in, and a one-click theme install: set up with the setup helpers)
-- (in R: quit_check) -- (when the install's quit should be over)
-- (in R: removing, remove_finish) -- (Settings > Remove ReaPersona: waiting for My REAPER's windows to be back, then the rest; set up with Setup)
-- (in R: install_shortcuts) -- (REAPER closes, the shortcuts and your synced setup go in, REAPER opens again: set up with Setup)
ensure_new = false -- (a merged style needs its one-key action registered)
check_msg, toast, toast_until = "", "", 0
-- (in R: said) -- (the last thing said: the screen-reader menu shows it in a message box)
menu_mode = false -- (the screen-reader menu is open: results go in a message box, which the screen reader reads)
function speak(text) if reaper.osara_outputMessage and not menu_mode then reaper.osara_outputMessage(tostring(text)) end end -- (OSARA reads it out)
function say(text) toast, toast_until, said = tostring(text), reaper.time_precise() + 6 + 0.06 * #tostring(text), tostring(text); speak(text) end
colours = assert(loadfile(here .. "/colours.lua"))(core) -- (Colours tab: StudioSync's colour system, 5.19)
colours.say = say

function open_extra(x)
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
function in_use(st, alt) return core.current() == st and (st.alt or 0) == alt end
function install_ext(key)
  local x = core.EXTENSIONS[key]
  local ok, why = core.install_extension(key)
  reaper.MB(ok and (x.name .. " is installed. Restart REAPER to load it (REAPER loads extensions when it starts).")
    or ("Couldn't install " .. x.name .. ": " .. tostring(why)), "ReaPersona", 0)
end
last_style = reaper.GetExtState(SECTION, "last style") -- (the persona before the last switch: Undo switch goes back to it; kept, so
-- closing the window or the menu doesn't lose it. Review, 5.14)
if last_style == "" or last_style == "built_try" then last_style = nil end
function use(st)
  -- (out of a preview or Try it: Undo switch goes back to the persona from before it, never to the trial or to My REAPER, and the
  -- preview ends, the persona being made staying in the bar. James, review 2026-11-19)
  local was, ended
  if bld.back then
    was, ended = core.by_id(bld.back), bld.preview
    bld.back, bld.later = nil, nil
    if ended then bld.preview_off() end
  elseif not core.is_trial() then was = core.current() end -- (a trial the window didn't start: no persona to offer back)
  if was and was.id ~= st.id then last_style = was.id; reaper.SetExtState(SECTION, "last style", was.id, true) end
  -- (a theme on trial gives way to the persona's, but the one it was trying over is what this persona had: leaving My REAPER
  -- mid-trial kept the trial theme as My REAPER's own. Review, 5.9.3)
  if trying and trying.back then reaper.OpenColorThemeFile(themes_dir .. trying.back) end
  trying = nil
  local needs = core.needs_layer(st)
  core.use(st)
  if needs then -- (5.29: REAPER has 16 shortcut layers; a persona gets one the first time it's used here)
    if reaper.MB(st.name .. "'s shortcuts aren't installed on this computer yet: REAPER has only 16 shortcut layers, so ReaPersona gives them to the personas you use.\n\n" ..
        (FLATPAK and "Install them now? You import them in REAPER's Actions window (the steps come next). Until then its look and layout are on, with your own keys."
          or "Install them now? REAPER closes (it asks first if anything is unsaved) and opens again, about 10 seconds. Until then its look and layout are on, with your own keys."), "ReaPersona: " .. st.name, 4) == 6 then
      install_shortcuts(false, st.id, true)
    end
  end
  local setup = core.last_project_setup or {}
  local miss = {}
  for _, s in ipairs(core.starts_missing or {}) do miss[#miss + 1] = s[1] end
  say((ended and "Preview off: " or "") .. st.name .. " in use" .. (#setup > 0 and (", and this project has its " .. table.concat(setup, ", ")) or "") ..
    ((was and was.id ~= st.id) and (". Undo switch " .. (menu_mode and "(in this menu)" or "(top)") .. " puts " .. was.name .. " back.") or ".") ..
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
