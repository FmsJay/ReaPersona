-- @description ReaPersona: make REAPER feel like Pro Tools, Logic, Ableton Live, FL Studio, Cubase, Studio One or Bitwig (or stock REAPER), switch on the fly, save your own presets, tweak and merge themes live
-- @author James (with Claude)
-- @version 4.0.0
-- @license GPL-3.0
-- @link https://github.com/FmsJay/ReaPersona
-- @about Each style is a shortcut layer (REAPER's Main alt-N sections, switched by its override actions), a theme, its feel (settings such
--   as snap, the transport and mixer layout, where the Media Explorer docks, and mouse behaviours such as Pro Tools' Smart Tool), a
--   toolbar and MIDI editor keys. Keys a style doesn't define fall through to your own shortcuts; whatever a style changes is put back
--   when you switch, so My REAPER is always your own setup. Base REAPER is REAPER as it ships. Presets keep a style with your theme and
--   settings under a name. Every style key is the DAW's default from its maker's documentation (styles.json). Adjust changes the theme
--   in use live; Merge builds a theme from several, or a style from two styles' shortcuts. Needs ReaImGui, SWS and js_ReaScriptAPI.
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
  local t, i = {}, 0
  while true do
    local f = reaper.EnumerateFiles(themes_dir, i)
    if not f then break end
    if f:match("%.ReaperTheme$") or f:match("%.ReaperThemeZip$") then t[#t + 1] = f end
    i = i + 1
  end
  table.sort(t, function(a, b) return a:lower() < b:lower() end)
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
local P = PALETTES[reaper.GetExtState(SECTION, "look")] or PALETTES[reaper.GetExtState("BandSync", "theme")] or PALETTES.Dark -- (Settings > look; else StudioSync's)
local C = {
  BG = solid(P.bg), CARD = solid(P.card), CARD_HOVER = solid(mix(P.card, P.text, 0.05)), NAV = solid(P.nav), TEXT = solid(P.text),
  MUTED = solid(P.muted), ACCENT = solid(P.accent), GREEN = solid(P.green), YELLOW = solid(P.yellow), RED = solid(P.red),
  FRAME = solid(mix(P.bg, P.text, 0.16)), KEYCAP = solid(mix(P.card, P.text, 0.12)), BANNER = solid(mix(P.card, P.yellow, 0.16)),
}
local function accent_of(st) return hex(st.accent, P.accent) end
local function t(x) return solid(mix(P.bg, P.text, x)) end
local function a(x) return solid(mix(P.bg, P.accent, x)) end

local ctx = ImGui.CreateContext("ReaPersona")
local font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
local bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
local COLS = {
  { ImGui.Col_WindowBg, C.BG }, { ImGui.Col_ChildBg, 0 }, { ImGui.Col_PopupBg, solid(mix(P.card, P.text, 0.03)) },
  { ImGui.Col_Text, C.TEXT }, { ImGui.Col_TextDisabled, C.MUTED }, { ImGui.Col_Border, t(0.12) },
  { ImGui.Col_FrameBg, C.FRAME }, { ImGui.Col_FrameBgHovered, t(0.21) }, { ImGui.Col_FrameBgActive, t(0.26) },
  { ImGui.Col_Button, t(0.12) }, { ImGui.Col_ButtonHovered, t(0.18) }, { ImGui.Col_ButtonActive, C.ACCENT },
  { ImGui.Col_Header, a(0.2) }, { ImGui.Col_HeaderHovered, a(0.28) }, { ImGui.Col_HeaderActive, a(0.38) },
  { ImGui.Col_CheckMark, C.ACCENT }, { ImGui.Col_SliderGrab, C.ACCENT }, { ImGui.Col_SliderGrabActive, C.ACCENT },
  { ImGui.Col_Separator, t(0.12) }, { ImGui.Col_TitleBg, C.NAV }, { ImGui.Col_TitleBgActive, solid(mix(P.nav, P.text, 0.03)) },
  { ImGui.Col_TableHeaderBg, t(0.08) }, { ImGui.Col_TableRowBgAlt, solid(mix(P.card, P.text, 0.03)) }, { ImGui.Col_TableBorderLight, t(0.1) },
  { ImGui.Col_ScrollbarBg, 0 },
}
local VARS = {
  { ImGui.StyleVar_WindowPadding, 0, 0 }, { ImGui.StyleVar_FramePadding, 10, 6 }, { ImGui.StyleVar_ItemSpacing, 8, 8 },
  { ImGui.StyleVar_FrameRounding, 6 }, { ImGui.StyleVar_ChildRounding, 10 }, { ImGui.StyleVar_WindowRounding, 8 },
  { ImGui.StyleVar_GrabRounding, 6 }, { ImGui.StyleVar_PopupRounding, 6 }, { ImGui.StyleVar_ScrollbarRounding, 8 },
  { ImGui.StyleVar_ChildBorderSize, 0 }, { ImGui.StyleVar_FrameBorderSize, 0 }, { ImGui.StyleVar_CellPadding, 8, 5 },
}

-- A rounded label: status at a glance.
local function pill(text, bg, fg)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = ImGui.CalcTextSize(ctx, text)
  ImGui.Dummy(ctx, w + 16, h + 6)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w + 16, y + h + 6, bg, (h + 6) / 2)
  ImGui.DrawList_AddText(dl, x + 8, y + 3, fg or 0x15171AFF, text)
end
local function keycap(text) -- a key, drawn like one
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local w, h = ImGui.CalcTextSize(ctx, text)
  ImGui.Dummy(ctx, w + 12, h + 4)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w + 12, y + h + 4, C.KEYCAP, 4)
  ImGui.DrawList_AddText(dl, x + 6, y + 2, C.TEXT, text)
end
local function heading(text, size)
  ImGui.PushFont(ctx, bold, size or 17)
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
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, (((col >> 16 & 255) * 299 + (col >> 8 & 255) * 587 + (col & 255) * 114) / 1000 > 150) and 0x15171AFF or 0xFFFFFFFF)
  ImGui.PushFont(ctx, bold, 15)
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
local changed = {} -- key -> native colour, what's been tweaked since the theme was loaded
local function refresh() reaper.ThemeLayout_RefreshAll(); reaper.UpdateArrange(); reaper.TrackList_AdjustWindows(false) end
local function add_fork(st, name)
  local list = reaper.GetExtState(SECTION, "forks " .. st.id)
  reaper.SetExtState(SECTION, "forks " .. st.id, (list ~= "" and (list .. "|") or "") .. name, true)
  reaper.SetExtState(SECTION, "theme " .. st.id, name, true)
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
local merge = { base = "Default_7.0.ReaperThemeZip", colours = "", graphics = "", parts = {}, fonts = false, msg = "" }
local PARTS = { "faders", "knobs", "meters", "transport", "buttons", "toolbar", "backgrounds" }
local km = { base = "pro_tools", from = "ableton", gaps = false, name = "", msg = "" } -- (merge shortcuts)
local ensure_new = false -- (a merged style needs its one-key action registered)
local check_msg, toast, toast_until = "", "", 0
local function say(text) toast, toast_until = text, reaper.time_precise() + 4 end

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
local function use(st)
  core.use(st); say(st.name .. " in use.")
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
  ImGui.DrawList_AddTextEx(dl, bold, 15, x + 26, y + 8 + ih + 8, C.TEXT, st.name)
  local sub = st.preset and ("preset of " .. (core.by_id(st.base) or { name = "" }).name) or st.kind == "theme" and "theme, with your keys"
    or st.id == "my_reaper" and "your own setup" or st.id == "base_reaper" and "REAPER as it ships" or st.user and "your merged style"
    or "keys, theme and layout"
  ImGui.DrawList_AddTextEx(dl, font, 13, x + 26, y + 8 + ih + 27, C.MUTED, sub)
  if on then
    local tw, th = ImGui.CalcTextSize(ctx, "In use")
    local px, py = x + w - 8 - tw - 16, y + 14
    ImGui.DrawList_AddRectFilled(dl, px, py, px + tw + 16, py + th + 6, solid(col), (th + 6) / 2)
    ImGui.DrawList_AddText(dl, px + 8, py + 3, 0x15171AFF, "In use")
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
      if show_open and x[2] and ImGui.SmallButton(ctx, "Open##" .. id .. i) then open_extra(x[2]) end
    end
    ImGui.EndTable(ctx)
  end
end

local function feel_rows(st)
  if not st.feel or #st.feel == 0 then return end
  if ImGui.BeginTable(ctx, "feel", 2, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
    ImGui.TableSetupColumn(ctx, "kind", ImGui.TableColumnFlags_WidthFixed)
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
  local ok, name = reaper.GetUserInputs("Save preset", 1, "Name,extrawidth=160", (cur.preset and cur.name or (cur.name .. " (mine)")))
  name = ok and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" then return end
  local st = core.save_preset(name)
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
    ImGui.Dummy(ctx, 0, 2)
    ImGui.BeginDisabled(ctx, on)
    if primary(on and "In use" or ("Use " .. sel.name), col) then use(sel) end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Save preset...") then save_preset_prompt() end
    ImGui.SetItemTooltip(ctx, "Keep what's in use now under a name: the style's keys and toolbar, the theme, the transport and mixer layout, snap and ripple, where the Media Explorer sits, and the mouse behaviours, as they are set right now. It joins your Presets.")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cheat sheet") then core.open_url(core.cheat_sheet(sel)) end
    ImGui.SetItemTooltip(ctx, "Every key, setting and feature of this style on one page, laid out for printing.")
    if (sel.alt or 0) > 0 and not sel.preset then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Share...") then
        local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Share " .. sel.name, reaper.GetResourcePath(), sel.name .. ".reapersona.json", "ReaPersona style (*.reapersona.json)\0*.reapersona.json\0\0")
        if ok == 1 and p ~= "" then reaper.MB(core.export(sel, p) and ("Saved " .. p .. ".\n\nAnyone with ReaPersona can import it.") or "Couldn't save it.", "ReaPersona", 0) end
      end
      ImGui.SetItemTooltip(ctx, "Save this style (keys, MIDI keys, feel, and your theme version if you made one) as one file to give someone.")
    end
    if sel.preset or sel.user then
      ImGui.SameLine(ctx)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.RED)
      if ImGui.Button(ctx, sel.preset and "Delete preset" or "Delete style") and reaper.MB("Delete " .. sel.name .. "?", "ReaPersona", 4) == 6 then
        if on then core.use(core.by_id(sel.base or "my_reaper")) end
        if sel.preset then core.delete_preset(sel.id) else core.delete_user_style(sel.id) end
        selected = sel.base or "my_reaper"
      end
      ImGui.PopStyleColor(ctx)
    end
    local options, seen = {}, {}
    for _, th in ipairs(sel.themes or { sel.theme }) do if not seen[th] and reaper.file_exists(themes_dir .. th) then options[#options + 1] = th; seen[th] = true end end
    for _, th in ipairs(core.forks(sel)) do if not seen[th] then options[#options + 1] = th; seen[th] = true end end
    if #options > 1 then
      ImGui.Dummy(ctx, 0, 2)
      ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Theme"); ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, math.min(420, (ImGui.GetContentRegionAvail(ctx))))
      if ImGui.BeginCombo(ctx, "##th", core.theme_for(sel) or "") then
        for _, th in ipairs(options) do
          if ImGui.Selectable(ctx, th, th == core.theme_for(sel)) then
            reaper.SetExtState(SECTION, "theme " .. sel.id, th, true)
            if on then reaper.OpenColorThemeFile(themes_dir .. th) end
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.SetItemTooltip(ctx, "Themes made in this one's likeness, merged ones, themes you added, and your own versions. Remembered per style.")
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
  if ImGui.SmallButton(ctx, "Import a shared style...") then
    local ok, p = reaper.GetUserFileNameForRead("", "Import a ReaPersona style", "*.json")
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
  local list = {}
  for _, st in ipairs(styles) do if st.kind == "theme" then list[#list + 1] = st end end
  if #list > 0 then
    view_switch()
    chooser(list, pick_in(list, sel), alt)
    ImGui.Dummy(ctx, 0, 4)
    detail(pick_in(list, sel), alt)
  end
  if card("all themes") then
    heading("Every theme on this computer")
    muted("Use one on its own (your keys and settings stay as they are), or add it to the Theme list of the style in use.")
    theme_list = theme_list or theme_files()
    ImGui.SetNextItemWidth(ctx, 260)
    local _, f = ImGui.InputTextWithHint(ctx, "##tf", "search " .. #theme_list .. " themes", themes_filter)
    themes_filter = f
    ImGui.SameLine(ctx)
    if primary("Add a theme...") then import_theme() end
    ImGui.SetItemTooltip(ctx, "Copy a .ReaperThemeZip or .ReaperTheme you downloaded into REAPER's ColorThemes folder.")
    local current = (reaper.GetLastColorThemeFile() or ""):gsub("\\", "/"):match("[^/]+$") or ""
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
          if th == current then ImGui.TextColored(ctx, C.GREEN, th .. "  (in use)") else ImGui.Text(ctx, th) end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "Use##u" .. i) then reaper.OpenColorThemeFile(themes_dir .. th); say(th .. " in use.") end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "Add to " .. cur.name .. "##a" .. i) then add_fork(cur, th); say(th .. " is in " .. cur.name .. "'s Theme list.") end
        end
      end
      ImGui.EndTable(ctx)
    end
    card_end()
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
    heading("Presets")
    muted("A preset is a style the way you like it: its keys and toolbar, plus the theme, transport and mixer layout, snap, the Media Explorer's place and the mouse behaviours as they were when you saved it. Use any style, change what you like, then save.")
    if primary("Save what's in use as a preset...") then save_preset_prompt() end
    card_end()
  end
  if #core.presets == 0 then return end
  view_switch()
  chooser(core.presets, pick_in(core.presets, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(core.presets, sel), alt)
end

-- Settings: playback and scrolling feel (REAPER's own, and the smooth playhead / smooth scroll extensions when installed), and the look.
local SETTINGS = {
  { 41817, "Continuous scrolling", "The arrange view moves under a fixed playhead during playback (REAPER: View > Continuous scrolling)." },
  { 40036, "Follow the playhead", "The view scrolls to keep the playhead in sight during playback." },
  { 40262, "Follow while recording", "The same, while recording." },
  { 40390, "Smooth seek", "Jumps during playback wait for the end of the bar or region (Preferences > Audio > Seeking)." },
}
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
  if card("set playback") then
    heading("Playhead and scrolling")
    muted("Saved by REAPER as you change them. A style or preset that sets one of these puts yours back when you switch away.")
    for i, s in ipairs(SETTINGS) do
      if setting_row("##set" .. i, s[2], reaper.GetToggleCommandState(s[1]) == 1, s[3]) then reaper.Main_OnCommand(s[1], 0) end
    end
    ImGui.Dummy(ctx, 0, 4)
    heading("Smooth playhead, scrolling and zoom", 15)
    muted("Most DAWs glide their playhead and zoom smoothly; REAPER steps. These two extensions add that. The DAW styles that feel that way recommend them.")
    for key, x in pairs(core.EXTENSIONS) do
      local state = core.extension_state(key)
      if state == "on" or state == "off" then
        if x.toggle then
          if setting_row("##ext" .. key, x.name, state == "on", x.why) then reaper.Main_OnCommand(reaper.NamedCommandLookup(x.toggle), 0) end
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
      if ImGui.RadioButton(ctx, l, look == l) then reaper.SetExtState(SECTION, "look", l, true); say("The new look shows next time you open ReaPersona.") end
    end
    muted("Follow StudioSync uses StudioSync's colour choice when it's installed (Dark otherwise).")
    card_end()
  end
end

local function adjust_page(sel)
  local current = (reaper.GetLastColorThemeFile() or ""):gsub("\\", "/"):match("[^/]+$") or ""
  if card("adj top") then
    heading("Adjust the theme in use")
    muted(current)
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
      reaper.MB(name and ("Saved as " .. name .. ".\n\nIt's in this style's Theme list now, and in use.") or ("Not saved: " .. tostring(why)), "ReaPersona", 0)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Undo colour changes") then
      for key in pairs(changed) do reaper.SetThemeColor(key, -1, 0) end
      changed = {}
      refresh()
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Every colour...") then run_script("X-Raym Scripts/Theme/X-Raym_Theme color tweaker_ReaImGui.lua") end
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
        add_fork(sel, name)
        merge.list = nil
        merge.msg = "Made " .. name .. ", in use, and in " .. sel.name .. "'s Theme list."
      else merge.msg = "Couldn't merge: " .. tostring(why) end
    end
    ImGui.EndDisabled(ctx)
    if merge.msg ~= "" then ImGui.TextWrapped(ctx, merge.msg) end
    ImGui.Dummy(ctx, 0, 2)
    muted("Most Stash themes carry no licence: share a merged theme only with its authors' permission.")
    card_end()
  end
  if card("merge keys") then
    heading("Merge shortcuts")
    muted("Make a new style from two: the first one's theme, toolbar and feel, with both styles' keys. Pick which keys win where both use the same one.")
    local function style_combo(label, key)
      ImGui.SetNextItemWidth(ctx, 260)
      local cur = core.by_id(km[key])
      if ImGui.BeginCombo(ctx, label, cur and cur.name or "(pick one)") then
        for _, st in ipairs(styles) do
          if #(st.keys or {}) > 0 and ImGui.Selectable(ctx, st.name, st.id == km[key]) then km[key] = st.id end
        end
        ImGui.EndCombo(ctx)
      end
    end
    style_combo("Start from##kb", "base")
    style_combo("Add the keys of##kf", "from")
    local from = core.by_id(km.from)
    if ImGui.RadioButton(ctx, (from and from.name or "The second") .. "'s keys win where both use a key", not km.gaps) then km.gaps = false end
    if ImGui.RadioButton(ctx, "Only keys the first one doesn't use", km.gaps) then km.gaps = true end
    ImGui.SetNextItemWidth(ctx, 260)
    local _, n = ImGui.InputTextWithHint(ctx, "Name##kn", "e.g. Pro Tools + Live", km.name); km.name = n
    ImGui.BeginDisabled(ctx, km.base == km.from or km.name == "")
    if primary("Make the style", accent_of(sel)) then
      local st, why = core.merge_keys(km.base, km.from, km.gaps, km.name)
      km.msg = st and (st.name .. " is in DAWs now, on shortcut layer alt-" .. st.alt .. ". Its keys work once installed: see Check.") or ("Couldn't: " .. tostring(why))
      if st then selected = st.id; ensure_new = true end
    end
    ImGui.EndDisabled(ctx)
    if km.msg ~= "" then ImGui.TextWrapped(ctx, km.msg) end
    card_end()
  end
end

local function key_table(id, keys, title)
  if ImGui.BeginTable(ctx, id, 2, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
    ImGui.TableSetupColumn(ctx, "Key", ImGui.TableColumnFlags_WidthFixed, 170)
    ImGui.TableSetupColumn(ctx, title)
    ImGui.TableHeadersRow(ctx)
    local q = filter:lower()
    for _, k in ipairs(keys) do
      if q == "" or k[1]:lower():find(q, 1, true) or k[3]:lower():find(q, 1, true) then
        ImGui.TableNextRow(ctx)
        ImGui.TableNextColumn(ctx); keycap(k[1])
        ImGui.TableNextColumn(ctx); ImGui.Text(ctx, k[3])
      end
    end
    ImGui.EndTable(ctx)
  end
end
local function keys_page(sel)
  if card("keys") then
    heading(sel.name .. " shortcuts")
    if #(sel.keys or {}) == 0 then
      muted("My REAPER uses your own shortcuts.")
    else
      ImGui.SetNextItemWidth(ctx, 260)
      local _, f = ImGui.InputTextWithHint(ctx, "##kf", "search keys or actions", filter)
      filter = f
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Change them") then reaper.Main_OnCommand(40605, 0) end
      ImGui.SetItemTooltip(ctx, "REAPER's Actions window: pick the section 'Main (alt-" .. sel.alt .. ")' at the top to see and change " .. sel.name .. "'s keys. Changes are live and kept.")
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
    muted("Shortcut layers are written into REAPER's keymap by install_shortcuts.py, with REAPER closed (it reads its keymap at start). Run it after changing styles.json or importing a style.")
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
    muted("REAPER reads its keymap when it starts, so the shortcut layers go in once, after adding or changing a style. Two ways:")
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "With Python: close REAPER, run install_shortcuts.py in this folder, start REAPER. It also installs the styles' toolbars, and keeps a backup of your keymap.")
    if ImGui.SmallButton(ctx, "Show the folder") then core.open_url(core.here) end
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "Without Python: make a keymap file, then in REAPER's Actions window open Key Map > Import... and pick it (choose to merge, not replace). Toolbars aren't included: styles keep your own toolbar.")
    if ImGui.SmallButton(ctx, "Make the keymap file") then
      local path, n, skipped = core.make_keymap()
      reaper.MB(n .. " shortcuts written to\n" .. path .. (#skipped > 0 and ("\n\nSkipped (no action here yet): " .. table.concat(skipped, ", ")) or "") ..
        "\n\nNext: Actions window > Key Map > Import..., pick that file, and choose to merge.", "ReaPersona", 0)
      reaper.Main_OnCommand(40605, 0)
    end
    card_end()
  end
  if card("check run") then
    heading("Check every style against this REAPER")
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
local PAGES = {
  { "DAWs", "Make REAPER feel like another DAW, or stock REAPER, or your own setup." },
  { "Themes", "Theme styles, every theme on this computer, adding your own, and where to find more." },
  { "Presets", "Your saved setups: a style plus your theme and settings." },
  { "Shortcuts", "Every key of the style picked, with REAPER's action for it." },
  { "Adjust", "Change the theme in use, live, and keep your version." },
  { "Merge", "Build a theme from parts of others, or a style from two styles' shortcuts." },
  { "Settings", "Smooth playhead, smooth scrolling and zoom, continuous scrolling, and ReaPersona's look." },
  { "Check", "What's installed, and checking the styles against this REAPER." },
}
local function top_bar(alt)
  local cur = core.current()
  local y0 = ImGui.GetCursorPosY(ctx) -- (below the title bar)
  ImGui.SetCursorPos(ctx, 16, y0 + 10)
  ImGui.PushFont(ctx, bold, 20); ImGui.Text(ctx, "ReaPersona"); ImGui.PopFont(ctx)
  ImGui.SameLine(ctx, 0, 14)
  ImGui.SetCursorPosY(ctx, y0 + 13)
  local col = accent_of(cur)
  pill(cur.name .. (in_use(cur, alt) and "" or "  (keys off)"), solid(col))
  if not in_use(cur, alt) then ImGui.SetItemTooltip(ctx, "Its shortcut layer isn't on (REAPER restarted?): Use it again, or run 'ReaPersona - restore last style'.") end
  local w = ImGui.GetWindowWidth(ctx)
  ImGui.SameLine(ctx, math.max(ImGui.GetCursorPosX(ctx), w - 230))
  ImGui.SetCursorPosY(ctx, y0 + 8)
  if ImGui.Button(ctx, "Save preset...##top") then save_preset_prompt() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Next style") then core.next_style(); selected = core.current().id; say(core.current().name .. " in use.") end
  ImGui.SetCursorPosY(ctx, y0 + 48)
  ImGui.Separator(ctx)
end

local function loop()
  ImGui.SetNextWindowSize(ctx, 980, 760, ImGui.Cond_FirstUseEver)
  for _, c in ipairs(COLS) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  for _, v in ipairs(VARS) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
  ImGui.PushFont(ctx, font, 15)
  local visible, open = ImGui.Begin(ctx, "ReaPersona", true)
  if visible then
    if ensure_new then core.ensure_scripts(); ensure_new = false end
    local alt = core.active_alt()
    local sel = core.by_id(selected) or styles[1]
    local want = reaper.GetExtState(SECTION, "page")
    if want ~= "" and want ~= page then page = want end
    top_bar(alt)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.NAV)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0, 0.5)
    if ImGui.BeginChild(ctx, "nav", 150, 0, ImGui.ChildFlags_AlwaysUseWindowPadding) then
      ImGui.PushFont(ctx, nil, 16)
      for _, p in ipairs(PAGES) do
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.Selectable(ctx, "  " .. p[1] .. "##nav", p[1] == page, ImGui.SelectableFlags_None, 0, 36) then page = p[1]; reaper.SetExtState(SECTION, "page", page, false) end
        ImGui.SetItemTooltip(ctx, p[2])
        if p[1] == page then ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), x - 8, y + 6, x - 4, y + 30, C.ACCENT, 2) end
      end
      ImGui.PopFont(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx)
    ImGui.SameLine(ctx, 0, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 12)
    if ImGui.BeginChild(ctx, "page", 0, 0, ImGui.ChildFlags_AlwaysUseWindowPadding) then
      if page == "DAWs" or page == "Styles" then daws_page(sel, alt)
      elseif page == "Themes" then themes_page(sel, alt)
      elseif page == "Presets" then presets_page(sel, alt)
      elseif page == "Settings" then settings_page()
      elseif page == "Shortcuts" then keys_page(sel)
      elseif page == "Adjust" then adjust_page(sel)
      elseif page == "Merge" then merge_page(sel)
      elseif page == "Check" then check_page() end
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx)
    if reaper.time_precise() < toast_until then -- (what just happened, bottom right, for a few seconds)
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      local tw, th = ImGui.CalcTextSize(ctx, toast)
      local fl = ImGui.GetForegroundDrawList(ctx)
      ImGui.DrawList_AddRectFilled(fl, wx + ww - tw - 40, wy + wh - th - 34, wx + ww - 16, wy + wh - 16, solid(mix(P.text, P.accent, 0.4)), 8)
      ImGui.DrawList_AddText(fl, wx + ww - tw - 28, wy + wh - th - 25, 0x15171AFF, toast)
    end
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx)
  ImGui.PopStyleVar(ctx, #VARS)
  ImGui.PopStyleColor(ctx, #COLS)
  if open then reaper.defer(loop) end
end
reaper.defer(loop)
