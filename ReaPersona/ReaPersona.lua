-- @description ReaPersona: make REAPER feel like Pro Tools, Logic, Ableton Live, FL Studio, Cubase, Studio One, Bitwig, Cakewalk, Reason, Audacity or Audition (or stock REAPER); build your own personas from blocks, give each project its own, tweak and merge themes live
-- @author James (with Claude)
-- @version 5.7.0
-- @license GPL-3.0
-- @link https://github.com/FmsJay/ReaPersona
-- @about Each persona is a shortcut layer (REAPER's Main alt-N sections, switched by its override actions), a theme, its feel (settings
--   such as snap, the transport and mixer layout, where the Media Explorer docks, and mouse behaviours such as Pro Tools' Smart Tool),
--   a toolbar and MIDI editor keys. Keys a persona doesn't define fall through to your own shortcuts; whatever a persona changes is put
--   back when you switch, so My REAPER is always your own setup. Base REAPER is REAPER as it ships. The Persona Builder stacks blocks
--   (a DAW's keys or one part of its feel, REAPER settings groups, a theme, a colour) into a persona of your own, and a project can keep
--   its own persona. Every DAW key is that DAW's default from its maker's documentation (styles.json). Adjust changes the theme in use
--   live; Build one makes a theme from several. Needs ReaImGui, SWS and js_ReaScriptAPI.
--   The look follows StudioSync's when it's installed (Settings picks one otherwise).
if not reaper.ImGui_GetBuiltinPath then return reaper.MB("This needs ReaImGui: Extensions > ReaPack > Browse packages > ReaImGui.", "ReaPersona", 0) end
if not reaper.CF_EnumerateActions then return reaper.MB("This needs the SWS extension (sws-extension.org).", "ReaPersona", 0) end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.10"
local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
local core = dofile(here .. "/reapersona_core.lua")
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
local function go(pg) page = pg; search_q = ""; reaper.SetExtState(SECTION, "page", pg, false) end
local merge = { base = "Default_7.0.ReaperThemeZip", colours = "", graphics = "", parts = {}, fonts = false, msg = "" }
local PARTS = { "faders", "knobs", "meters", "transport", "buttons", "toolbar", "backgrounds" }
local bld_load -- (opens the Persona Builder on a persona; set up with its page)
local trying, try_theme -- (a theme on trial: { name, back = the theme to go back to, ends = time }; set up with the setup helpers)
local quit_check -- (when the install's quit should be over)
local ensure_new = false -- (a merged style needs its one-key action registered)
local check_msg, toast, toast_until = "", "", 0
local function say(text) toast, toast_until = tostring(text), reaper.time_precise() + 6 + 0.06 * #tostring(text) end

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
local last_style -- (the style before the last switch: Undo switch goes back to it)
local function use(st)
  local was = core.current()
  if was and was.id ~= st.id then last_style = was.id end
  trying = nil -- (a theme on trial gives way to the persona's)
  core.use(st); say(st.name .. " in use. Undo switch (top) puts " .. (was and was.name or "the last one") .. " back.")
  for _, key in ipairs(st.recommends or {}) do -- (offered once: no is remembered)
    local x = core.EXTENSIONS[key]
    if x and core.extension_state(key) == "missing" and reaper.GetExtState(SECTION, "declined " .. key) == "" then
      if reaper.MB(st.name .. " " .. x.feel .. ". " .. x.name .. " does that in REAPER: " .. x.why .. ".\n\nInstall it now? (REAPER needs a restart to load it.)", "ReaPersona: recommended for " .. st.name, 4) == 6 then
        install_ext(key)
      else reaper.SetExtState(SECTION, "declined " .. key, "1", true) end
    end
  end
end

-- One picture card in the grid: click shows it, double-click uses it.
local function style_card(st, w, sel, alt)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local iw = w - 16
  local ih = math.floor(iw * 0.56)
  local h = 8 + ih + 52
  if ImGui.InvisibleButton(ctx, "card" .. st.id, w, h) then selected = st.id end
  local hov = ImGui.IsItemHovered(ctx)
  if hov and ImGui.IsMouseDoubleClicked(ctx, 0) then use(st) end
  ImGui.SetItemTooltip(ctx, "Click to see it, double-click to use it.")
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
  local st, why = core.save_preset(name)
  if not st then return say("Not saved: " .. tostring(why)) end
  selected = st.id
  say("Saved " .. name .. ": it's in your list.")
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
    if (sel.alt or 0) > 0 and not installed[sel.alt] then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, "Its shortcuts aren't installed yet: see Check.")
      ImGui.PopStyleColor(ctx)
    end
    for _, key in ipairs(sel.recommends or {}) do
      local x = core.EXTENSIONS[key]
      local state = x and core.extension_state(key)
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
    local tpl = here .. "/templates/" .. (sel.preset and sel.base or sel.id) .. ".RPP"
    if reaper.file_exists(tpl) then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New project like " .. (sel.short or sel.name)) then
        reaper.Main_OnCommand(40859, 0) -- (a new tab, so nothing open is replaced)
        reaper.Main_openProject("template:" .. tpl)
      end
      ImGui.SetItemTooltip(ctx, "A new project with the tracks " .. (sel.short or sel.name) .. " starts you with, its buses and sends, using REAPER's own plugins.")
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
      if deps and reaper.MB("Delete " .. sel.name .. "? This can't be undone." ..
          (#deps > 0 and ("\n\nThese personas are built on it and will use My REAPER's keys instead:\n" .. table.concat(deps, "\n")) or ""), "ReaPersona", 4) == 6 then
        if on and sel.preset then core.use(core.by_id(sel.base or "my_reaper")) end
        local ok, why
        if sel.preset then ok, why = core.delete_preset(sel.id) else ok, why = core.delete_user_style(sel.id) end
        if ok then selected = sel.base or core.current().id else say("Not deleted: " .. tostring(why)) end
      end
      ImGui.PopStyleColor(ctx)
    end
    ImGui.Dummy(ctx, 0, 2)
    if ImGui.Button(ctx, sel.blocks and "Edit in the Builder" or "Build on this") then bld_load(sel) end
    ImGui.SetItemTooltip(ctx, sel.blocks and "Open its blocks in the Persona Builder." or "Start a new persona in the Persona Builder from this one, then add blocks.")
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
    local have, missing = {}, {}
    for _, th in ipairs(vers) do
      if reaper.file_exists(themes_dir .. th) then have[#have + 1] = th
      elseif core.CATALOG[th] and core.CATALOG[th].url and core.CATALOG[th].url:match("^https?:") then missing[#missing + 1] = th end
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
      if #missing > 0 and ImGui.TreeNode(ctx, #missing .. " more version" .. (#missing == 1 and "" or "s") .. " you can get##tvget") then
        for i, th in ipairs(missing) do
          local c = core.CATALOG[th]
          if ImGui.SmallButton(ctx, "Get it##tvg" .. i) then core.open_url(c.url) end
          ImGui.SameLine(ctx); ImGui.Text(ctx, th:gsub("%.ReaperTheme%a*$", "") .. " by " .. tostring(c.by) .. (c.note and (" (" .. c.note .. ")") or ""))
        end
        muted("Drop the download on this window and it joins the list.")
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
    heading("REAPER tips")
    muted((sel.id == "base_reaper" and "" or "With REAPER's own keys (Base REAPER has them all). ") .. "From REAPER 7.85's factory keymap.")
    rows("tips", sel.tips, true)
    if ImGui.SmallButton(ctx, "REAPER User Guide") then core.open_url("https://www.reaper.fm/userguide.php") end
    card_end()
  end
end
local function pick_in(list, sel) -- the one picked, if it's on this page; else this page's first
  for _, st in ipairs(list) do if st == sel then return sel end end
  return list[1]
end

local function daws_page(sel, alt)
  local list = {}
  for _, st in ipairs(styles) do if st.kind ~= "theme" then list[#list + 1] = st end end
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
  if ImGui.SmallButton(ctx, "Import a shared persona...") then
    local ok, p = reaper.GetUserFileNameForRead("", "Import a ReaPersona persona", "*.json")
    if ok then
      local st, why = core.import(p)
      reaper.MB(st and (st.name .. " imported as shortcut layer alt-" .. st.alt .. ".\n\nReopen ReaPersona to see it; its shortcuts need installing (see Check).") or ("Not imported: " .. why), "ReaPersona", 0)
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
  if card("all themes") then
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
    muted("Save what you're using now (the persona, plus your theme, layout, snap and mouse as they're set), or build one from blocks: one DAW's shortcuts, another's mouse feel and mixer, REAPER settings, any theme.")
    if primary("Save what I'm using now...") then save_preset_prompt() end
    ImGui.SameLine(ctx)
    if primary("Persona Builder") then bld_load(core.current()) end
    ImGui.SetItemTooltip(ctx, "Starts from the persona in use; drag in more blocks.")
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
  if #core.presets == 0 then return end
  view_switch()
  chooser(core.presets, pick_in(core.presets, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(core.presets, sel), alt)
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
local function settings_page()
  if card("set aspects") then
    heading("What a persona may change")
    muted("Switch off what you'd rather keep as it is, whatever persona you use. Takes effect the next time you use a persona; what a persona already changed is still put back when you switch away.")
    for i, a in ipairs(core.ASPECTS) do
      if setting_row("##asp" .. i, a[2], core.aspect_on(a[1])) then reaper.SetExtState(SECTION, "aspect " .. a[1], core.aspect_on(a[1]) and "0" or "1", true) end
    end
    card_end()
  end
  if card("set projects") then
    heading("A persona per project")
    muted("Give a project its persona with 'Use for this project' on the persona's page; it's saved in the project. With this on, opening that project or switching to its tab switches persona, and the Builder's REAPER settings blocks make each project's workflow its own.")
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
  if card("set playback") then
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
  if card("set look") then
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

local function key_table(id, keys, title)
  if ImGui.BeginTable(ctx, id, 2, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
    ImGui.TableSetupColumn(ctx, "Key", ImGui.TableColumnFlags_WidthFixed, 170)
    ImGui.TableSetupColumn(ctx, title)
    ImGui.TableHeadersRow(ctx)
    local q = filter:lower()
    for _, k in ipairs(core.keys_here(keys)) do -- (keys marked for the other system left out)
      if q == "" or k[1]:lower():find(q, 1, true) or k[3]:lower():find(q, 1, true) then
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); keycap(k[1])
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, k[3])
      end
    end
    ImGui.EndTable(ctx)
  end
end
local keys_for -- (the style the Shortcuts page shows: its own pick, else the one in use)
local function keys_page()
  local sel = core.by_id(keys_for or "") or core.current()
  if sel.preset then sel = core.by_id(sel.base) or sel end
  if card("keys") then
    ImGui.SetNextItemWidth(ctx, 260)
    if ImGui.BeginCombo(ctx, "##keysfor", sel.name) then
      for _, st in ipairs(styles) do
        if ImGui.Selectable(ctx, st.name .. "##kf" .. st.id, st.id == sel.id) then keys_for = st.id end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx); heading("shortcuts")
    if #(sel.keys or {}) == 0 then
      muted(sel.id == "my_reaper" and "My REAPER uses your own shortcuts." or (sel.name .. " has no shortcuts of its own: your own keys stay as they are."))
    else
      ImGui.SetNextItemWidth(ctx, 260)
      local _, f = ImGui.InputTextWithHint(ctx, "##kf", "search keys or actions", filter)
      filter = f
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Change them") then reaper.Main_OnCommand(40605, 0) end
      ImGui.SetItemTooltip(ctx, "REAPER's Actions window: pick the section 'Main (alt-" .. tostring(sel.alt) .. ")' at the top to see and change " .. sel.name .. "'s keys. Changes are live and kept.")
      if sel.docs then
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Official list") then core.open_url(sel.docs[1]) end
        ImGui.SetItemTooltip(ctx, table.concat(sel.docs, "\n"))
      end
      key_table("arr", sel.keys, "In " .. sel.name)
      if sel.midi_keys and #sel.midi_keys > 0 then
        ImGui.Dummy(ctx, 0, 4)
        heading("MIDI editor", 15)
        key_table("midi", sel.midi_keys, "In " .. sel.name .. "'s piano roll")
      end
    end
    card_end()
  end
end

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
    muted("Shortcut layers are written into REAPER's keymap by install_shortcuts.py, with REAPER closed (it reads its keymap at start). Run it after changing styles.json or importing a persona.")
    for _, st in ipairs(styles) do
      if (st.alt or 0) > 0 then
        local n = installed[st.alt] or 0
        status_line(n >= #st.keys, string.format("%s  (alt-%d): %d of %d keys", st.name, st.alt, n, #st.keys))
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
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "With Python: close REAPER, run install_shortcuts.py in this folder, start REAPER. It also installs the personas' toolbars, and keeps a backup of your keymap.")
    if ImGui.SmallButton(ctx, "Show the folder") then core.open_url(core.here) end
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "Without Python: make a keymap file, then in REAPER's Actions window open Key Map > Import... and pick it (choose to merge, not replace). Toolbars aren't included: personas keep your own toolbar.")
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
      local d = midi_installed == 0 and (core.midi_defaults() .. " MIDI editor defaults saved; now close REAPER and run install_shortcuts.py.") or ""
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
local function drop_report(list) -- what came in, in a few lines (a pack's leftover files are one line, not one each)
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
  for _, st in ipairs(styles) do if (st.alt or 0) > 0 then want = want + 1; if installed[st.alt] then have = have + 1 end end end
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
local function keymap_route() -- (no Python: a keymap file to import by hand)
  local path, n, why = core.make_keymap()
  if not path then return reaper.MB("No keymap made: " .. tostring(why[1]), "ReaPersona", 0) end
  reaper.MB(n .. " shortcuts are in this file:\n" .. path .. "\n\nThe Actions window opens next. In it:\n1. Key Map > Import...\n2. Pick that file.\n" ..
    "3. Choose MERGE. (Replace would remove your own shortcuts.)\n\nToolbars need the Python install.", "ReaPersona: shortcuts", 0)
  reaper.Main_OnCommand(40605, 0)
end
-- REAPER reads its keymap only when it starts: install_shortcuts.py waits for REAPER to close, installs, and starts it again.
local function install_shortcuts()
  if not core.python() then return keymap_route() end
  if reaper.MB("REAPER closes (it asks first if anything is unsaved), the shortcuts install, and REAPER opens again: about 10 seconds.\n\n" ..
    "A backup of your keymap is made first.", "ReaPersona: install shortcuts", 1) ~= 1 then return end
  if core.scripts_missing() > 0 then core.ensure_scripts() end -- (the scripts the keys run have to be registered first)
  if not reaper.file_exists(here .. "/midi_defaults.json") then core.midi_defaults() end
  local exe = reaper.GetExePath():gsub("\\", "/")
  exe = IS_MAC and exe:match("^(.-%.app)") or (exe .. "/reaper.exe")
  local open = {} -- (the projects open now, reopened with REAPER)
  for i = 0, 50 do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if fn ~= "" and not fn:find('"', 1, true) then open[#open + 1] = ' --open "' .. fn .. '"' end
  end
  local cfg = reaper.get_ini_file():gsub("\\", "/") -- (-cfgfile users get REAPER back on the same configuration)
  reaper.ExecProcess(core.py .. ' "' .. here .. '/install_shortcuts.py" --after-reaper-quits --relaunch "' .. exe .. '" --cfgfile "' .. cfg .. '"' .. table.concat(open), -1) -- (-1: don't wait)
  os.remove(here .. "/install_cancelled")
  reaper.Main_OnCommand(40004, 0) -- (File: Quit, with REAPER's own save prompts)
  quit_check = reaper.time_precise() + 4 -- (REAPER still running 4 s after: the quit was cancelled, and the installer is told)
end
local function setup_all()
  if reaper.MB("Set up everything ReaPersona can do from here?\n\n" ..
    "- build ReaPersona's own DAW themes (needs Python)\n- add the startup line that brings your persona back when REAPER starts\n" ..
    "- offer the smooth playhead / smooth scrolling extensions\n- then the shortcut install: REAPER closes and opens again (about 10 seconds), which also loads new extensions", "ReaPersona: set up", 4) ~= 6 then return end
  local done = {}
  if core.python() then local m = core.build_own_themes(); done[#done + 1] = m and (#m .. " themes built") or "themes not built" end
  if not core.startup_on() then done[#done + 1] = core.add_startup() and "startup line added" or "startup line not added" end
  for key, x in pairs(core.EXTENSIONS) do
    if core.extension_state(key) == "missing" and core.can_install(key)
      and reaper.MB("Install " .. x.name .. "? (" .. x.why .. ")", "ReaPersona", 4) == 6 and core.install_extension(key) then
      done[#done + 1] = x.name .. " installed (restart REAPER)"
    end
  end
  theme_list = nil
  reaper.MB(table.concat(done, "\n") .. "\n\nLast step: the shortcuts.", "ReaPersona: set up", 0)
  install_shortcuts()
end
local function setup_page()
  if reaper.GetExtState(SECTION, "welcomed") == "" and card("welcome") then -- (the first run: pick your DAW, it's in use straight away)
    heading("Which DAW are you coming from?", 20)
    muted("Pick it and REAPER takes on its shortcuts, look and layout. You can switch any time, and Back to My REAPER puts everything back.")
    local n = 0
    for _, st in ipairs(styles) do
      if st.kind ~= "theme" and (st.alt or 0) > 0 and not st.user and not st.preset and st.id ~= "base_reaper" then
        if n % 5 ~= 0 then ImGui.SameLine(ctx) end
        n = n + 1
        if primary(st.name .. "##welcome", accent_of(st)) then
          selected = st.id; use(st); reaper.SetExtState(SECTION, "welcomed", "1", true)
          if setup_todo() then say(st.name .. " in use. Next: install its shortcuts below.") end
        end
      end
    end
    if ImGui.SmallButton(ctx, "I'll pick later") then reaper.SetExtState(SECTION, "welcomed", "1", true) end
    card_end()
  end
  if card("setup top") then
    heading("Set up ReaPersona")
    muted("What ReaPersona can use, whether it's there, and one click to get each. Drag files onto this window any time to add them: themes (.ReaperThemeZip, .ReaperTheme or the theme pack .zip as downloaded), toolbars (.ReaperMenu), keymaps (.ReaperKeyMap, become a persona of their own), and shared personas and presets.")
    if primary("Set up everything") then setup_all() end
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
      local py = core.python()
      setup_row("py", py ~= nil, "Python 3" .. (py and (" (" .. py .. ")") or ""), "Builds ReaPersona's themes and installs the shortcuts in one step (pip install pillow numpy).",
        not py and "Get it" or nil, function() core.open_url("https://www.python.org/downloads/") end)
      if py then
        local libs = core.python_libs()
        setup_row("libs", libs, "Pillow and numpy for Python", "The image tools the theme builder uses.", not libs and "Install them" or nil, function()
          if reaper.MB("Run: python -m pip install --user pillow numpy\n\nREAPER waits while pip downloads them (a minute or two).", "ReaPersona", 1) ~= 1 then return end
          local ok, why = core.install_python_libs()
          reaper.MB(ok and "Installed." or ("pip didn't finish: " .. tostring(why)), "ReaPersona", 0)
        end)
      end
      local n, total = core.own_themes_built()
      setup_row("own", n == total, "ReaPersona's own themes: " .. n .. " of " .. total .. " built", "A theme per DAW in its colours, made from your REAPER's own Default 7. They're approximations: the themes by other people below can look closer to the real DAWs.",
        py and core.python_libs() and (n == total and "Rebuild" or "Build") or nil, build_themes)
      local have, want = shortcuts_state()
      setup_row("keys", have == want, "Shortcut layers: " .. have .. " of " .. want .. " personas installed", "Each persona's keys. REAPER restarts to load them (about 10 seconds).", have < want and "Install and restart" or "Reinstall", install_shortcuts)
      setup_row("start", core.startup_on(), "Brings your persona back when REAPER starts", "One block in Scripts/__startup.lua.", not core.startup_on() and "Add it" or nil,
        function() local ok, why = core.add_startup(); say(ok and "Startup line added." or tostring(why)) end)
      for key, x in pairs(core.EXTENSIONS) do
        local s = core.extension_state(key)
        setup_row("ext" .. key, s == "on" or s == "off", x.name .. (s == "restart" and " (restart REAPER to load it)" or ""), x.why .. " Recommended by the DAW personas.",
          s == "missing" and core.can_install(key) and "Install" or nil, function() install_ext(key) end)
      end
      ImGui.EndTable(ctx)
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
            reaper.MB(s and (s.name .. " is in DAWs (shortcut layer alt-" .. s.alt .. "; install the shortcuts in Setup). " .. #missed .. " of your assignments are for commands ReaPersona doesn't map yet.") or ("Not imported: " .. tostring(missed)), "ReaPersona", 0)
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
        reaper.MB(s and (s.name .. " is in DAWs (install the shortcuts in Setup).") or ("Not imported: " .. tostring(missed)), "ReaPersona", 0)
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
    muted("Made by REAPER's theme authors in each DAW's likeness. They can't ship with ReaPersona, so: Get it opens the author's page; download, then drop the file (zip and all) onto this window.")
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
              not have and "Get it" or nil, function() get_url(c.url) end, c.url)
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

-- Persona Builder: blocks dragged (or clicked) into a stack, each showing what it sets; lower blocks win. Saved as a persona of yours.
local bld = { blocks = {}, name = "", id = nil, msg = "", daw = nil, theme = "", colour = 0x3A86FF, back = nil }
function bld_load(st) -- start from a persona: the Builder's own blocks if it made it, else it as one DAW block
  bld.blocks = st.blocks and core.json_decode(core.json_encode(st.blocks)) or { core.new_block("daw", st.base or st.id) }
  bld.name, bld.id, bld.msg = st.blocks and st.name or "", st.blocks and st.id or nil, ""
  go("Builder")
end
local flow_end, flow_first -- (chips wrap onto the next line when the row is full)
local function flow_start() local x = ImGui.GetCursorScreenPos(ctx); flow_end, flow_first = x + ImGui.GetContentRegionAvail(ctx), true end
local function chip(label, make, tip) -- a block to drag in (or click: it goes at the bottom). make() builds it
  local pad = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
  local w = ImGui.CalcTextSize(ctx, label) + 2 * pad
  if not flow_first then
    local x2 = ImGui.GetItemRectMax(ctx)
    if x2 + 6 + w <= flow_end then ImGui.SameLine(ctx, 0, 6) end
  end
  flow_first = false
  if ImGui.Button(ctx, label .. "##chip") then bld.blocks[#bld.blocks + 1] = make() end
  if tip then ImGui.SetItemTooltip(ctx, tip) end
  if ImGui.BeginDragDropSource(ctx) then
    ImGui.SetDragDropPayload(ctx, "RP_BLOCK", core.json_encode(make()))
    ImGui.Text(ctx, label)
    ImGui.EndDragDropSource(ctx)
  end
end
local bld_act -- (a drop or a move, done after the stack is drawn)
local function bld_drop(at) -- a block dropped here goes in at this place; one of the stack dragged here moves here
  if not ImGui.BeginDragDropTarget(ctx) then return end
  local ok, data = ImGui.AcceptDragDropPayload(ctx, "RP_BLOCK")
  if ok then local fine, b = pcall(core.json_decode, data); if fine and type(b) == "table" then bld_act = { "add", at, b } end end
  ok, data = ImGui.AcceptDragDropPayload(ctx, "RP_MOVE")
  if ok and tonumber(data) then bld_act = { "move", at, tonumber(data) } end
  ImGui.EndDragDropTarget(ctx)
end
local function bld_palette()
  heading("Blocks", 16)
  muted("Drag a block into your persona, or click it to add it at the bottom.")
  ImGui.Dummy(ctx, 0, 2)
  ImGui.Text(ctx, "From a DAW")
  local cur = core.by_id(bld.daw or "") or core.by_id(core.current().base or core.current().id) or styles[1]
  if cur.kind == "built" or cur.kind == "theme" or #(cur.keys or {}) == 0 then -- (My REAPER has nothing to borrow: the first DAW)
    for _, st in ipairs(styles) do if #(st.keys or {}) > 0 and st.kind ~= "built" then cur = st; break end end
  end
  ImGui.SetNextItemWidth(ctx, -1)
  if ImGui.BeginCombo(ctx, "##blddaw", cur.name) then
    for _, st in ipairs(styles) do
      if st.kind ~= "built" and st.kind ~= "theme" and (#(st.keys or {}) > 0 or #(st.feel or {}) > 0) then
        if ImGui.Selectable(ctx, st.name .. "##d" .. st.id, st == cur) then bld.daw = st.id end
      end
    end
    ImGui.EndCombo(ctx)
  end
  flow_start()
  chip("Everything", function() return core.new_block("daw", cur.id) end, "Its shortcuts, its layout and feel, and its theme. Each part can be switched off in the block.")
  if #(cur.keys or {}) > 0 then
    chip("Shortcuts", function() local b = core.new_block("daw", cur.id); b.feel, b.theme = false, false; return b end, "Only its keys (and MIDI editor keys).")
  end
  local has = {}
  for _, f in ipairs(cur.feel or {}) do has[core.aspect_of(f)] = true end
  for _, x in ipairs(core.ASPECTS) do
    if has[x[1]] then chip(x[4], function() return core.new_block("feel", cur.id, x[1]) end, x[2]) end
  end
  local tv, seen = {}, {} -- (its theme versions on this computer: each one a block)
  for _, th in ipairs(cur.themes or { cur.theme }) do if th and not seen[th] and reaper.file_exists(themes_dir .. th) then seen[th] = true; tv[#tv + 1] = th end end
  for _, th in ipairs(core.forks(cur)) do if not seen[th] and reaper.file_exists(themes_dir .. th) then seen[th] = true; tv[#tv + 1] = th end end
  if #tv > 0 then
    ImGui.Dummy(ctx, 0, 2)
    ImGui.Text(ctx, cur.name .. "'s theme versions")
    flow_start()
    for _, th in ipairs(tv) do
      chip((th:gsub("%.ReaperTheme%a*$", ""):gsub("^ReaPersona %- (.*)$", "ReaPersona's %1")), function() return core.new_block("theme", th) end, th)
    end
  end
  ImGui.Dummy(ctx, 0, 4)
  ImGui.Text(ctx, "REAPER settings")
  muted("Each starts as you have it now; change it in the block.")
  flow_start()
  for _, g in ipairs(core.SETTING_GROUPS) do chip(g.name, function() return core.new_block("settings", g.id) end) end
  ImGui.Dummy(ctx, 0, 4)
  ImGui.Text(ctx, "Look")
  theme_list = theme_list or theme_files()
  if bld.theme == "" then bld.theme = core.loaded_theme() or theme_list[1] or "" end
  ImGui.SetNextItemWidth(ctx, -1)
  if ImGui.BeginCombo(ctx, "##bldth", (bld.theme:gsub("%.ReaperTheme%a*$", ""))) then
    for i, th in ipairs(theme_list) do if ImGui.Selectable(ctx, th:gsub("%.ReaperTheme%a*$", "") .. "##t" .. i, th == bld.theme) then bld.theme = th end end
    ImGui.EndCombo(ctx)
  end
  flow_start()
  if bld.theme ~= "" then chip("This theme", function() return core.new_block("theme", bld.theme) end, bld.theme) end
  local _, col = ImGui.ColorEdit3(ctx, "##bldcol", bld.colour, ImGui.ColorEditFlags_NoInputs)
  bld.colour = col
  ImGui.SetItemTooltip(ctx, "The persona's colour in ReaPersona: its card, buttons and badge.")
  flow_first = false
  chip("This colour", function() return core.new_block("colour", string.format("#%06X", bld.colour)) end)
end
local function entry_line(e, blocks, b)
  local ch, v = ImGui.Checkbox(ctx, "##on" .. e.slot, not e.off)
  if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
  ImGui.SetItemTooltip(ctx, e.off and "Tick to put this back in the persona" or "Untick to leave this out of the persona")
  ImGui.SameLine(ctx)
  local text = (e.key and (keyname(e.key) .. "  ") or "") .. tostring(e.label)
  if e.off then
    ImGui.TextColored(ctx, C.MUTED, text .. "   (left out)")
  elseif e.lost_to then
    ImGui.TextColored(ctx, C.MUTED, text .. "   (replaced by " .. core.block_title(blocks[e.lost_to]) .. ")")
  elseif e.kind == "feel" and not core.aspect_on(core.aspect_of(e.entry)) then
    ImGui.TextColored(ctx, C.YELLOW, text .. "   (off in Settings > What a persona may change)")
  else ImGui.Text(ctx, text) end
end
local function block_card(i, b, list, blocks)
  local lost, keys = 0, 0
  for _, e in ipairs(list) do if e.lost_to then lost = lost + 1 end; if e.kind == "key" or e.kind == "midi" then keys = keys + 1 end end
  ImGui.PushID(ctx, i)
  if card("blk") then
    ImGui.Selectable(ctx, "::", false, ImGui.SelectableFlags_None, 14, 0)
    ImGui.SetItemTooltip(ctx, "Drag to move this block up or down")
    if ImGui.BeginDragDropSource(ctx) then
      ImGui.SetDragDropPayload(ctx, "RP_MOVE", tostring(i)); ImGui.Text(ctx, core.block_title(b)); ImGui.EndDragDropSource(ctx)
    end
    ImGui.SameLine(ctx); heading(i .. ". " .. core.block_title(b), 15)
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, C.MUTED, #list .. " thing" .. (#list == 1 and "" or "s") .. (lost > 0 and (", " .. lost .. " replaced lower down") or ""))
    local right = ImGui.GetWindowWidth(ctx) - 190 * UI -- (no room beside the title: the buttons go on the next line)
    if ImGui.GetItemRectMax(ctx) - ImGui.GetWindowPos(ctx) + 8 <= right then ImGui.SameLine(ctx, right) end
    ImGui.BeginDisabled(ctx, i == 1); if ImGui.SmallButton(ctx, "Up") then bld_act = { "move", i - 1, i } end; ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, i == #blocks); if ImGui.SmallButton(ctx, "Down") then bld_act = { "move", i + 2, i } end; ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Remove") then bld_act = { "remove", i } end
    if b.kind == "daw" then
      for _, part in ipairs({ { "keys", "Shortcuts" }, { "feel", "Layout and feel" }, { "theme", "Theme" } }) do
        local ch, v = ImGui.Checkbox(ctx, part[2], b[part[1]] and true or false)
        if ch then b[part[1]] = v end
        ImGui.SameLine(ctx)
      end
      ImGui.NewLine(ctx)
    end
    if b.kind == "settings" then
      local g = core.setting_group(b.group) or { items = {} }
      b.values = b.values or {}
      local lost_slot = {}
      for _, e in ipairs(list) do if e.lost_to then lost_slot[e.entry[1] .. " " .. (type(e.entry[2]) == "table" and table.concat(e.entry[2], ",") or tostring(e.entry[2]))] = e.lost_to end end
      for n, item in ipairs(g.items) do
        local v = tonumber(b.values[n]) or -1
        local opts = type(item[1]) == "table" and item[3] or { "Off", "On" }
        local now = type(item[1]) == "table" and (opts[v] or "Leave as it is") or (v >= 0 and opts[v + 1] or "Leave as it is")
        ImGui.SetNextItemWidth(ctx, 170 * UI)
        if ImGui.BeginCombo(ctx, item[2] .. "##s" .. n, now) then
          if ImGui.Selectable(ctx, "Leave as it is", v < 0) then b.values[n] = -1 end
          for k, o in ipairs(opts) do
            local val = type(item[1]) == "table" and k or k - 1
            if ImGui.Selectable(ctx, o, v == val) then b.values[n] = val end
          end
          ImGui.EndCombo(ctx)
        end
        local w = lost_slot[(type(item[1]) == "table" and "choice " .. table.concat(item[1], ",")) or ("toggle " .. tostring(item[1]))]
        if w then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "(replaced by " .. core.block_title(blocks[w]) .. ")") end
      end
    else
      local shown = 0
      for _, e in ipairs(list) do if e.kind ~= "key" and e.kind ~= "midi" then entry_line(e, blocks, b); shown = shown + 1 end end
      if keys > 0 and ImGui.TreeNode(ctx, keys .. " shortcuts##keys") then
        for _, e in ipairs(list) do if e.kind == "key" or e.kind == "midi" then entry_line(e, blocks, b) end end
        ImGui.TreePop(ctx)
      end
      if shown == 0 and keys == 0 then muted(b.kind == "feel" and "Nothing of this kind in that DAW." or "Nothing switched on.") end
    end
    ImGui.PopTextWrapPos(ctx)
    ImGui.EndChild(ctx)
  end
  bld_drop(i)
  ImGui.Dummy(ctx, 0, 2)
  ImGui.PopID(ctx)
end
local function builder_page()
  if card("bld make") then
    heading(bld.id and ("Editing " .. bld.name) or "Persona Builder")
    muted("Stack blocks into a persona: a DAW's shortcuts, another's mouse feel or mixer layout, REAPER settings, a theme, a colour. Each block shows what it sets; untick a line to leave it out. Where two blocks set the same thing, the lower one wins.")
    local daws = {}
    for _, b in ipairs(bld.blocks) do if b.kind == "daw" and b.keys and core.by_id(b.id) then daws[#daws + 1] = core.by_id(b.id).name end end
    ImGui.TextColored(ctx, #daws > 1 and C.YELLOW or C.MUTED, #daws == 0 and "Shortcuts: your own." or #daws == 1 and ("Shortcuts: " .. daws[1] .. "'s, ready as soon as you save.")
      or ("Shortcuts: " .. table.concat(daws, " + ") .. " in a layer of their own, so they need installing once you save (REAPER restarts)."))
    ImGui.SetNextItemWidth(ctx, 280 * UI)
    local _, n = ImGui.InputTextWithHint(ctx, "##bldname", "Name it, e.g. Mixing", bld.name); bld.name = n
    ImGui.SameLine(ctx)
    local ready = #bld.blocks > 0
    ImGui.BeginDisabled(ctx, not ready or bld.name == "")
    if primary(bld.id and "Save changes" or "Save") then
      local st, install = core.save_built(bld.blocks, bld.name, bld.id)
      if st then
        bld.id, selected, ensure_new = st.id, st.id, true
        if bld.back or reaper.GetExtState(SECTION, "style") == st.id then core.use(st); bld.back = nil end -- (the persona in use: its changes now)
        bld.msg = st.name .. " is saved: it's with the DAWs on Personas." .. (install and " Install its shortcuts on Home (REAPER restarts) to use its keys." or "")
        say(bld.msg)
      else bld.msg = "Not saved: " .. tostring(install) end
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    ImGui.BeginDisabled(ctx, not ready)
    if ImGui.Button(ctx, "Try it") then
      local st, install = core.build_style(bld.blocks, bld.name ~= "" and bld.name or "Your build", "built_try")
      if st then
        if install then st.alt = 0 end -- (keys from several DAWs need their layer installed: the trial keeps your own keys)
        bld.back = bld.back or core.current().id
        core.use(st)
        say("Trying it" .. (install and " (with your own shortcuts until it's saved and installed)" or "") .. ". Save it, or Go back.")
      else say("Can't try it: " .. tostring(install)) end
    end
    ImGui.EndDisabled(ctx)
    if bld.back then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Go back") then local back = core.by_id(bld.back); bld.back = nil; if back then use(back) end end
      ImGui.SetItemTooltip(ctx, "Back to " .. ((core.by_id(bld.back) or {}).name or "the persona you had") .. ", exactly as it was.")
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Start again") then bld.blocks, bld.name, bld.id, bld.msg = {}, "", nil, "" end
    if bld.msg ~= "" then ImGui.TextWrapped(ctx, bld.msg) end
    card_end()
  end
  local wide = ImGui.GetContentRegionAvail(ctx) > 700 * UI
  if ImGui.BeginTable(ctx, "bld", wide and 2 or 1, ImGui.TableFlags_SizingStretchProp) then
    if wide then
      ImGui.TableSetupColumn(ctx, "blocks", ImGui.TableColumnFlags_WidthStretch, 0.36)
      ImGui.TableSetupColumn(ctx, "stack", ImGui.TableColumnFlags_WidthStretch, 0.64)
    end
    ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
    if card("bld palette") then bld_palette(); card_end() end
    if wide then ImGui.TableNextColumn(ctx) else ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx) end
    local per = core.build_preview(bld.blocks)
    bld_act = nil
    for i, b in ipairs(bld.blocks) do block_card(i, b, per[i], bld.blocks) end
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local w = ImGui.GetContentRegionAvail(ctx)
    ImGui.InvisibleButton(ctx, "##drop", math.max(w, 10), 64 * UI)
    local dl = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRect(dl, x, y, x + w, y + 64 * UI, C.MUTED, 8, 0, 1.5)
    local tw, th = ImGui.CalcTextSize(ctx, #bld.blocks == 0 and "Drop blocks here" or "Drop more blocks here")
    ImGui.DrawList_AddText(dl, x + (w - tw) / 2, y + (64 * UI - th) / 2, C.MUTED, #bld.blocks == 0 and "Drop blocks here" or "Drop more blocks here")
    bld_drop(#bld.blocks + 1)
    ImGui.EndTable(ctx)
    if bld_act then -- (applied once the stack is drawn)
      local act, list = bld_act, bld.blocks
      if act[1] == "add" then table.insert(list, math.min(act[2], #list + 1), act[3])
      elseif act[1] == "remove" then table.remove(list, act[2])
      elseif act[1] == "move" and list[act[3]] then
        local at, b = act[2], table.remove(list, act[3])
        if act[3] < at then at = at - 1 end
        table.insert(list, math.max(1, math.min(at, #list + 1)), b)
      end
      bld_act = nil
    end
  end
end

-- REAPER tweaks: every setting group the Builder offers, live. A group can go into the Builder as a block, as it's set now.
local function tweaks_page()
  if card("tw top") then
    heading("REAPER tweaks")
    muted("REAPER's own options and SWS's, in groups. Each change happens now and REAPER keeps it. A persona that sets one puts yours back when you switch away; 'Add to the Builder' makes a group, as you've set it here, part of a persona.")
    if ImGui.Button(ctx, "Preferences") then reaper.Main_OnCommand(40016, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Toolbars and menus") then reaper.Main_OnCommand(40905, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Actions and shortcuts") then reaper.Main_OnCommand(40605, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Mouse modifiers") then reaper.Main_OnCommand(41356, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Theme adjuster") then reaper.Main_OnCommand(42234, 0) end
    card_end()
  end
  for gi, g in ipairs(core.SETTING_GROUPS) do
    if card("tw " .. g.id) then
      heading(g.name, 16)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Add to the Builder##twb" .. gi) then
        bld.blocks[#bld.blocks + 1] = core.new_block("settings", g.id)
        say(g.name .. " is in the Persona Builder, set as it is now.")
        go("Builder")
      end
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
  { "Personas", "Make REAPER feel like another DAW, your own personas, and the Persona Builder.", { "DAWs", "Presets", "Builder" }, { "DAWs", "Your personas", "Persona Builder" } },
  { "Shortcuts", "Every key of a persona, with REAPER's action for it.", { "Shortcuts" }, { "Shortcuts" } },
  { "Themes", "Your themes, getting more, adjusting the one in use, building one from others.", { "Themes", "Browse", "Adjust", "Merge" }, { "Your themes", "Get more", "Adjust", "Build one" } },
  { "Settings", "REAPER's and SWS's options in groups, what personas may change, a persona per project, ReaPersona's look.", { "Tweaks", "Settings" }, { "REAPER tweaks", "ReaPersona" } },
  { "Help", "What's installed, checking the personas, repairs.", { "Check" }, { "Check and repair" } },
}
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
        ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show##ss" .. i) then selected = st.id; search_q = ""; go("DAWs") end
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
      section("REAPER tweaks")
      for i, x in ipairs(sets) do
        if setting_row("##ssx" .. i, x[2], reaper.GetToggleCommandState(core.cmd_id(x[1])) == 1, x.tip) then reaper.Main_OnCommand(core.cmd_id(x[1]), 0) end
      end
      shown = shown + #sets
    end
    for _, a in ipairs(core.ASPECTS) do
      if has(a[2]) then
        if ImGui.SmallButton(ctx, "Open##sa" .. a[1]) then search_q = ""; go("Settings") end
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
  pill(cur.name .. (in_use(cur, alt) and "" or "  (keys off)"), solid(col))
  if not in_use(cur, alt) then ImGui.SetItemTooltip(ctx, "Its shortcut layer isn't on (REAPER restarted?): Use it again, or run 'ReaPersona - restore last style'.") end
  local w = ImGui.GetWindowWidth(ctx)
  if w > 760 then -- (search, Ctrl+K; on a narrow window it's left out of the bar)
    ImGui.SameLine(ctx, 0, 16)
    ImGui.SetCursorPosY(ctx, y0 + 8)
    if ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_K) or search_focus then ImGui.SetKeyboardFocusHere(ctx); search_focus = false end
    ImGui.SetNextItemWidth(ctx, math.min(260, w - ImGui.GetCursorPosX(ctx) - 320))
    local _, q = ImGui.InputTextWithHint(ctx, "##search", "Search everything (Ctrl+K)", search_q)
    search_q = q
  end
  if search_q ~= "" and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then search_q = "" end
  local undo = last_style and last_style ~= cur.id and core.by_id(last_style)
  local right = (undo and 430 or 320) * UI
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
  local visible, open = ImGui.Begin(ctx, "ReaPersona", true)
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
    top_bar(alt)
    trying_bar()
    if last_error then
      ImGui.SetCursorPosX(ctx, 16)
      ImGui.TextColored(ctx, C.RED, "Something went wrong and was written to errors.log: " .. last_error)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "OK##err") then last_error = nil end
    end
    local narrow = ImGui.GetWindowWidth(ctx) < 600 -- (docked at the side or a small window: the sidebar becomes a drop-down)
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
        for i, pg in ipairs(g[3]) do
          if i > 1 then ImGui.SameLine(ctx) end
          local tw = ImGui.CalcTextSize(ctx, g[4][i]) + 24
          if ImGui.Selectable(ctx, g[4][i] .. "##tab", page == pg or (page == "Styles" and pg == "DAWs"), ImGui.SelectableFlags_None, tw, 28) then go(pg) end
        end
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 0, 2)
      end
      if search_q ~= "" then search_page()
      elseif page == "Setup" then setup_page()
      elseif page == "DAWs" or page == "Styles" then daws_page(sel, alt)
      elseif page == "Themes" then themes_page(sel, alt)
      elseif page == "Browse" then browse_page()
      elseif page == "Presets" then presets_page(sel, alt)
      elseif page == "Builder" then builder_page()
      elseif page == "Settings" then settings_page()
      elseif page == "Tweaks" then tweaks_page()
      elseif page == "Shortcuts" then keys_page()
      elseif page == "Adjust" then
        if adjust_out then
          if card("adj out") then heading("Adjust is in its own window"); if ImGui.Button(ctx, "Bring it back here") then adjust_out = false end; card_end() end
        else adjust_page(core.current()) end -- (the theme you adjust is the one in use: its style gets the result)
      elseif page == "Merge" then merge_page(sel)
      elseif page == "Check" then check_page() end
      ImGui.EndChild(ctx)
    end
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
    local v2, o2 = ImGui.Begin(ctx, "ReaPersona: theme adjuster", true)
    if v2 then adjust_page(core.current()); ImGui.End(ctx) end
    ImGui.PopStyleVar(ctx)
    if not o2 then adjust_out = false end
  end
  ImGui.PopFont(ctx)
  ImGui.PopStyleVar(ctx, #VARS)
  ImGui.PopStyleColor(ctx, #COLS)
  return open
end
-- One frame at a time, protected: an error is logged and the window starts a fresh ImGui context (a frame cut short leaves the old one
-- unbalanced), instead of the whole window closing with a ReaScript error.
local errors_in_a_row = 0
local function loop()
  trial_over()
  if quit_check and reaper.time_precise() > quit_check then
    quit_check = nil
    core.write(here .. "/install_cancelled", "quit was cancelled\n")
    say("REAPER didn't close, so the shortcuts weren't installed.")
  end
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
local cmd = select(4, reaper.get_action_context()) -- (the picker's own action: lit on a toolbar while the window is open)
if cmd and cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, 1); reaper.RefreshToolbar2(0, cmd) end
reaper.atexit(function()
  if trying then trying.ends = 0; trial_over() end -- (a theme on trial goes back when the window closes)
  if cmd and cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, 0); reaper.RefreshToolbar2(0, cmd) end
end)
reaper.defer(loop)
