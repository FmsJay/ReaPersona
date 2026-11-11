-- @noindex
-- ReaPersona's engine, shared by the picker and its one-key actions (use a style, next style, the MIDI editor keys...).
-- A style = a shortcut layer (Main alt-N, switched live by REAPER's override actions) + a theme + its "feel" (toggles such as snap,
-- and mouse behaviours) + MIDI editor keys. Everything a style changes is snapshotted first and put back when you switch away,
-- so My REAPER is always exactly your own setup.
local M = {}
local res = reaper.GetResourcePath()
M.here = (debug.getinfo(1, "S").source:match("^@?(.*)[/\\]") or (res .. "/Scripts/ReaPersona")):gsub("\\", "/") -- (its own folder, wherever it is installed)
M.themes_dir = res .. "/ColorThemes/"
M.SECTION = "ReaPersona"
if reaper.GetExtState(M.SECTION, "migrated") == "" then -- (once: what DAW Styles kept, under its old section name)
  for _, k in ipairs({ "style", "orig", "view", "look" }) do
    local v = reaper.GetExtState("DAWStyles", k)
    if v ~= "" and reaper.GetExtState(M.SECTION, k) == "" then reaper.SetExtState(M.SECTION, k, v, true) end
  end
  M.migrate_ids = true -- (per-style keys need the style list: copied below)
end
local CLEAR, TOGGLE_ALT, MIDI_SEC = 24800, 24802, 32060 -- "Main action section: Clear any override" / "Toggle override to alt-N" = 24802 + N

function M.read(p) local f = io.open(p, "rb"); if not f then return nil end local t = f:read("a"); f:close(); return t end
function M.write(p, t) local f = io.open(p, "wb"); if not f then return false end f:write(t); f:close(); return true end

function M.json_decode(s) -- objects, arrays, strings, numbers, booleans, null (pure)
  local i = 1
  local function ws() i = s:find("[^%s]", i) or #s + 1 end
  local val
  local function str()
    local out, j = {}, i + 1
    while true do
      local c = s:sub(j, j)
      if c == "" then error("unterminated string") end
      if c == '"' then i = j + 1; return table.concat(out) end
      if c == "\\" then
        local n = s:sub(j + 1, j + 1)
        if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(j + 2, j + 5), 16)); j = j + 6
        else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n; j = j + 2 end
      else out[#out + 1] = c; j = j + 1 end
    end
  end
  function val()
    ws()
    local c = s:sub(i, i)
    if c == "{" or c == "[" then
      local t, obj = {}, c == "{"
      i = i + 1; ws()
      if s:sub(i, i) == (obj and "}" or "]") then i = i + 1; return t end
      local n = 0
      while true do
        if obj then ws(); local k = str(); ws(); i = i + 1; t[k] = val() else n = n + 1; t[n] = val() end
        ws(); local d = s:sub(i, i); i = i + 1
        if d ~= "," then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil end
    local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not num then error("bad JSON at " .. i) end
    i = i + #num; return tonumber(num)
  end
  return val()
end

function M.json_encode(v, ind) -- for scripts.json and shared styles (pure)
  ind = ind or ""
  local t = type(v)
  if t == "table" then
    local n = #v
    local inner = ind .. "  "
    if n > 0 or next(v) == nil then
      local parts = {}
      for k = 1, n do parts[k] = M.json_encode(v[k], inner) end
      local one = "[" .. table.concat(parts, ", ") .. "]"
      if #one < 100 and not one:find("\n") then return one end
      return "[\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. ind .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = M.json_encode(k) .. ": " .. M.json_encode(v[k], inner) end
    return "{\n" .. inner .. table.concat(parts, ",\n" .. inner) .. "\n" .. ind .. "}"
  elseif t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c) return ({ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" })[c] or string.format("\\u%04x", c:byte()) end) .. '"'
  elseif t == "number" then return (math.type(v) == "integer" or v % 1 == 0) and string.format("%d", v) or tostring(v)
  elseif t == "boolean" then return tostring(v) end
  return "null"
end

-- ---------------------------------------------------------------- styles
local function load(p) local t = M.read(p); if not t then return {} end local ok, d = pcall(M.json_decode, t); return ok and d and d.styles or {} end
M.styles = load(M.here .. "/styles.json")
for _, st in ipairs(load(M.here .. "/user_styles.json")) do st.user = true; M.styles[#M.styles + 1] = st end -- (imported/shared styles)
M.presets = {} -- (your saved presets: filled below, after the feel code)
function M.by_id(id)
  for _, st in ipairs(M.styles) do if st.id == id then return st end end
  for _, st in ipairs(M.presets) do if st.id == id then return st end end
end
M.scripts = (function() local t = M.read(M.here .. "/scripts.json"); local ok, d = pcall(M.json_decode, t or "{}"); return ok and d or {} end)()
M.scripts.main, M.scripts.midi = M.scripts.main or {}, M.scripts.midi or {}

if M.migrate_ids then
  local ids = {}
  for _, st in ipairs(M.styles) do ids[#ids + 1] = st.id end
  for _, p in ipairs((function() local ok, d = pcall(M.json_decode, M.read(M.here .. "/presets.json") or "{}"); return ok and d and d.presets or {} end)()) do ids[#ids + 1] = p.id end
  for _, id in ipairs(ids) do
    for _, k in ipairs({ "theme ", "forks " }) do
      local v = reaper.GetExtState("DAWStyles", k .. id)
      if v ~= "" and reaper.GetExtState(M.SECTION, k .. id) == "" then reaper.SetExtState(M.SECTION, k .. id, v, true) end
    end
  end
  reaper.SetExtState(M.SECTION, "migrated", "1", true)
end
function M.active_alt()
  for n = 1, 16 do if reaper.GetToggleCommandState(TOGGLE_ALT + n) == 1 then return n end end
  return 0
end
function M.current() return M.by_id(reaper.GetExtState(M.SECTION, "style")) or M.styles[1] end
function M.forks(st)
  local t = {}
  for f in reaper.GetExtState(M.SECTION, "forks " .. st.id):gmatch("[^|]+") do if reaper.file_exists(M.themes_dir .. f) then t[#t + 1] = f end end
  return t
end
function M.theme_for(st) -- your pick for this style, else its own theme, else the first of its themes this computer has
  for _, v in ipairs({ reaper.GetExtState(M.SECTION, "theme " .. st.id), st.theme, table.unpack(st.themes or {}) }) do
    if v ~= "" and reaper.file_exists(M.themes_dir .. v) then return v end
  end
  return st.theme
end
local function cmd_id(c)
  if type(c) == "number" then return c end
  if type(c) == "string" and c:match("^script:") then c = M.scripts.main[c:sub(8)] or "" end
  return reaper.NamedCommandLookup(c or "")
end
M.cmd_id = cmd_id

-- ---------------------------------------------------------------- feel: toggles and mouse behaviours, snapshotted and put back
-- Each style's "feel" lists ["toggle", command, wanted state, what it is], ["radio", {commands}, the one wanted, what it is] and
-- ["switch", command, command that undoes it, what it is] and ["mouse", context, modifier flag, behaviour, what it is].
-- Before a style changes one, what it was is kept (ExtState "orig", kept across restarts); switching style puts it all back first.
-- ["dock", window, side ("left"/"right"/"top"/"bottom"/"float"), shown (0/1), what] puts a REAPER window in a docker on that side.
local function orig_list() local t = {}; for l in reaper.GetExtState(M.SECTION, "orig"):gmatch("[^\n]+") do t[#t + 1] = l end return t end

-- Docked windows. REAPER has no API to dock its own windows, but the Media Explorer has "Dock Media Explorer in Docker" (its own section,
-- sent to its window) and Dock_UpdateDockID picks the docker it goes into. Each step needs REAPER's message loop between, so it runs deferred.
local WINDOWS = { explorer = { show = 50124, title = "Media Explorer", dock = 40008, ident = "explorer", name = "Media Explorer" } }
M.WINDOWS = WINDOWS
local SIDES = { bottom = 0, left = 1, top = 2, right = 3 }
local function docker_at(side) -- the first docker REAPER keeps on that side of the main window, or nil
  local want = SIDES[side]
  if not want then return nil end
  for i = 0, 15 do if reaper.DockGetPosition(i) == want then return i end end
end
M.docker_at = docker_at
local function ini_window(w) -- what reaper.ini last saved: docked?, and its docker preference
  local t = M.read(res .. "/reaper.ini") or ""
  local pref = tonumber(((t:match("%[REAPERdockpref%]([^%[]*)") or "")):match("\n" .. WINDOWS[w].ident .. "=%S+ (%d+)") or "") or 0
  local docked = (t:match("%[reaper_" .. w .. "%]([^%[]*)") or ""):match("\ndocked=(%d)") == "1"
  return docked, pref
end
local jobs, busy = {}, false
local function pump()
  local job = jobs[1]
  if not job then busy = false; return end
  if reaper.time_precise() < (job.at or 0) then return reaper.defer(pump) end
  job.n = (job.n or 0) + 1
  if job.step() and job.n < 24 then job.at = reaper.time_precise() + 0.2 else table.remove(jobs, 1) end
  reaper.defer(pump)
end
local function later(step) jobs[#jobs + 1] = { step = step }; if not busy then busy = true; reaper.defer(pump) end end
function M.busy() return busy end
-- Put a window where wanted: { shown = bool, docker = index or nil for a floating window, pref = docker preference to leave }.
local function move_window(w, want)
  local W = WINDOWS[w]
  if not (W and reaper.JS_Window_OnCommand and reaper.Dock_UpdateDockID) then return end
  later(function() -- (returns true: not there yet, try again in a moment)
    if reaper.GetToggleCommandState(W.show) ~= 1 then reaper.Main_OnCommand(W.show, 0); return true end
    local h = reaper.JS_Window_Find(W.title, true)
    if not h then return true end
    local d = reaper.DockIsChildOfDock(h)
    if want.docker and d ~= want.docker then
      if d < 0 then reaper.Dock_UpdateDockID(W.ident, want.docker) end
      reaper.JS_Window_OnCommand(h, W.dock) -- (in the wrong docker: out first, then in)
      return true
    elseif not want.docker and d >= 0 then reaper.JS_Window_OnCommand(h, W.dock); return true end
    if want.pref then reaper.Dock_UpdateDockID(W.ident, want.pref) end
    if not want.shown then reaper.Main_OnCommand(W.show, 0) end
  end)
end
local function window_now(w) -- -> "d|w|shown|docker,pref" as it is now (docker -1 = floating)
  local W = WINDOWS[w]
  local shown = reaper.GetToggleCommandState(W.show) == 1
  local docked, pref = ini_window(w)
  local d = -1
  local h = shown and reaper.JS_Window_Find and reaper.JS_Window_Find(W.title, true)
  if h then d = reaper.DockIsChildOfDock(h) elseif docked then d = pref end
  return "d|" .. w .. "|" .. (shown and 1 or 0) .. "|" .. d .. "," .. pref
end
local function window_back(line)
  local w, shown, d, pref = line:match("^d|([^|]+)|(%d)|(%-?%d+),(%d+)")
  if w then move_window(w, { shown = shown == "1", docker = tonumber(d) >= 0 and tonumber(d) or nil, pref = tonumber(pref) }) end
end

local function restore_feel(windows_left) -- (windows_left: a window's original is kept here when the next style moves it too)
  local list = orig_list()
  for n = #list, 1, -1 do
    local kind, a, b, c = list[n]:match("^(%a)|([^|]*)|([^|]*)|?(.*)$")
    if kind == "d" then
      if windows_left then windows_left[a] = list[n] else window_back(list[n]) end
    elseif kind == "t" then
      local id = cmd_id(tonumber(a) or a)
      if id ~= 0 and reaper.GetToggleCommandState(id) ~= tonumber(b) then reaper.Main_OnCommand(id, 0) end
    elseif kind == "m" then
      reaper.SetMouseModifier(a, tonumber(b), c ~= "" and c or "-1")
    elseif kind == "s" then -- (a one-way switch: run its way back)
      local id = cmd_id(tonumber(a) or a)
      if id ~= 0 then reaper.Main_OnCommand(id, 0) end
    elseif kind == "r" then -- (one of a set of options was on: turn it back on)
      local id = cmd_id(tonumber(a) or a)
      if id ~= 0 and reaper.GetToggleCommandState(id) ~= 1 then reaper.Main_OnCommand(id, 0) end
    end
  end
  reaper.SetExtState(M.SECTION, "orig", "", true)
end
local function apply_feel(st, windows_left)
  local list = {}
  windows_left = windows_left or {}
  for _, f in ipairs(st.feel or {}) do
    if f[1] == "dock" and WINDOWS[f[2]] and reaper.JS_Window_OnCommand then
      list[#list + 1] = windows_left[f[2]] or window_now(f[2]) -- (the original from before any style, if the last style moved it)
      windows_left[f[2]] = nil
      local d = f[3] ~= "float" and docker_at(f[3]) or nil
      move_window(f[2], { shown = f[4] == 1, docker = d })
    elseif f[1] == "toggle" then
      local id = cmd_id(f[2])
      local now = id ~= 0 and reaper.GetToggleCommandState(id) or -1
      if now >= 0 then
        list[#list + 1] = "t|" .. tostring(f[2]) .. "|" .. now
        if now ~= f[3] then reaper.Main_OnCommand(id, 0) end
      end
    elseif f[1] == "switch" then -- ["switch", command, command that undoes it, what]: no on/off state to read (main toolbar contents)
      local id = cmd_id(f[2])
      local slot = type(f[2]) == "number" and ((f[2] >= 42729 and f[2] <= 42744 and ("Floating toolbar " .. (f[2] - 42729 + 17)))
        or (f[2] >= 41956 and f[2] <= 41959 and ("Floating MIDI toolbar " .. (f[2] - 41956 + 5))))
      if slot and not M.toolbar_installed(slot) then id = 0 end -- (its toolbar isn't installed here: an empty one would replace yours)
      if id ~= 0 then reaper.Main_OnCommand(id, 0); list[#list + 1] = "s|" .. tostring(f[3]) .. "|" end
    elseif f[1] == "radio" then -- ["radio", {options}, wanted, what]: options where exactly one is on (transport position, say)
      for _, c in ipairs(f[2]) do
        local id = cmd_id(c)
        if id ~= 0 and reaper.GetToggleCommandState(id) == 1 then list[#list + 1] = "r|" .. tostring(c) .. "|1"; break end
      end
      local id = cmd_id(f[3])
      if id ~= 0 and reaper.GetToggleCommandState(id) ~= 1 then reaper.Main_OnCommand(id, 0) end
    elseif f[1] == "mouse" and reaper.SetMouseModifier then
      list[#list + 1] = "m|" .. f[2] .. "|" .. f[3] .. "|" .. reaper.GetMouseModifier(f[2], f[3], "")
      reaper.SetMouseModifier(f[2], f[3], f[4])
    end
  end
  for _, line in pairs(windows_left) do window_back(line) end -- (windows the last style moved and this one doesn't: put back)
  reaper.SetExtState(M.SECTION, "orig", table.concat(list, "\n"), true)
end
-- what a mouse entry is set to now matches the style? (for the picker's "not applied" warnings)
function M.mouse_ok(f) return reaper.GetMouseModifier and reaper.GetMouseModifier(f[2], f[3], "") ~= "" end

-- ---------------------------------------------------------------- presets: the style in use, its theme and how everything is set now
-- A preset keeps the style's keys (same shortcut layer, MIDI keys and toolbar) and records the theme plus every setting and mouse
-- behaviour any style touches, as they are when you save it. In presets.json; it's used like a style, and put back the same way.
local PRESETS = M.here .. "/presets.json"
local EXTRA_TOGGLES = { 40389, 40549, 40557, 40036 } -- (mixer master on the right, inserts, sends; auto-scroll: shown in the picker too)
local function action_name(id)
  local s = reaper.CF_GetCommandText and reaper.CF_GetCommandText(0, id)
  return ((type(s) == "string" and s or ""):gsub("^[^:]+: ", ""))
end
function M.preset_style(p)
  local base = M.by_id(p.base) or M.styles[1]
  local st = {}
  for k, v in pairs(base) do st[k] = v end
  st.id, st.name, st.theme, st.themes, st.feel, st.preset, st.base = p.id, p.name, p.theme, { p.theme }, p.feel or {}, true, base.id
  st.description = "Your preset, on " .. base.name .. "'s keys" .. ((base.alt or 0) > 0 and "" or " (your own)") .. ": its theme, toolbar, " ..
    "transport and mixer layout, snap and the mouse behaviours as they were when you saved it (" .. (p.saved or "") .. ")."
  local feel_from = p.feel_from and M.by_id(p.feel_from)
  if feel_from then -- (a mix: one style's keys, another's layout and feel, any theme)
    st.feel = feel_from.feel or {}
    st.recommends = feel_from.recommends
    st.description = "Your mix: " .. base.name .. "'s keys" .. ((base.alt or 0) > 0 and "" or " (your own)") .. " with " .. feel_from.name ..
      "'s layout, toolbar and feel, and the theme " .. tostring(p.theme) .. "."
  end
  st.extras, st.tips, st.description_base = base.extras, base.tips, base.description
  return st
end
local function load_presets()
  local ok, d = pcall(M.json_decode, M.read(PRESETS) or "{}")
  local list = ok and d and d.presets or {}
  M.presets = {}
  for _, p in ipairs(list) do if p.id and p.name then M.presets[#M.presets + 1] = M.preset_style(p) end end
  return list
end
load_presets()
function M.save_preset(name) -- -> the new preset (as a style)
  local base = M.current()
  if base.preset then base = M.by_id(base.base) or M.styles[1] end
  local feel, seen = {}, {}
  for _, f in ipairs(base.feel or {}) do if f[1] == "switch" then feel[#feel + 1] = f end end -- (its toolbars: no state to read)
  local function toggle(c, label)
    local id = cmd_id(c)
    local s = id ~= 0 and reaper.GetToggleCommandState(id) or -1
    if s >= 0 and not seen[tostring(c)] then
      seen[tostring(c)] = true
      feel[#feel + 1] = { "toggle", c, s, (label or action_name(id)) .. ": " .. (s == 1 and "on" or "off") }
    end
  end
  for _, st in ipairs(M.styles) do
    for _, f in ipairs(st.feel or {}) do
      if f[1] == "toggle" then toggle(f[2])
      elseif f[1] == "radio" and not seen["r" .. table.concat(f[2], ",")] then
        seen["r" .. table.concat(f[2], ",")] = true
        for _, c in ipairs(f[2]) do
          local id = cmd_id(c)
          if id ~= 0 and reaper.GetToggleCommandState(id) == 1 then feel[#feel + 1] = { "radio", f[2], c, action_name(id) }; break end
        end
      elseif f[1] == "mouse" and reaper.GetMouseModifier and not seen[f[2] .. f[3]] then
        seen[f[2] .. f[3]] = true
        feel[#feel + 1] = { "mouse", f[2], f[3], reaper.GetMouseModifier(f[2], f[3], ""), "As you had it: " .. f[#f] }
      end
    end
  end
  for _, c in ipairs(EXTRA_TOGGLES) do toggle(c) end
  if reaper.JS_Window_OnCommand then
    for w in pairs(WINDOWS) do
      local shown, d = window_now(w):match("^d|[^|]+|(%d)|(%-?%d+)")
      local side = "float"
      for s, pos in pairs(SIDES) do if tonumber(d) >= 0 and reaper.DockGetPosition(tonumber(d)) == pos then side = s end end
      feel[#feel + 1] = { "dock", w, side, tonumber(shown), WINDOWS[w].name .. ": " .. (side == "float" and "its own window" or ("docked " .. side)) .. (shown == "1" and ", open" or ", closed") }
    end
  end
  local list = load_presets()
  local p = { id = "preset_" .. os.time(), name = name, base = base.id, saved = os.date("%Y-%m-%d"), feel = feel,
              theme = ((reaper.GetLastColorThemeFile() or ""):gsub("\\", "/"):match("[^/]+$")) or M.theme_for(base) }
  list[#list + 1] = p
  M.write(PRESETS, M.json_encode({ presets = list }) .. "\n")
  load_presets()
  reaper.SetExtState(M.SECTION, "style", p.id, true) -- (it is what's in use now: switching away puts back what the style changed)
  return M.by_id(p.id)
end
-- Mix and match: one style's keys (its shortcut layer and MIDI keys), another style's layout, toolbar and feel, any theme. -> the profile
function M.save_mix(name, keys_id, feel_id, theme)
  local list = load_presets()
  local p = { id = "mix_" .. os.time(), name = name, base = keys_id, feel_from = feel_id, theme = theme, saved = os.date("%Y-%m-%d") }
  list[#list + 1] = p
  M.write(PRESETS, M.json_encode({ presets = list }) .. "\n")
  load_presets()
  return M.by_id(p.id)
end
-- A preset as a file to give someone, and taking one in (its styles have to exist on that computer). -> true / the preset, or nil + why
function M.export_preset(id, path)
  for _, p in ipairs(load_presets()) do if p.id == id then return M.write(path, M.json_encode({ reapersona_preset = 1, preset = p }) .. "\n") end end
end
function M.import_preset(d)
  local p = d and d.preset
  if not (p and p.name and p.base) then return nil, "not a ReaPersona preset" end
  if not M.by_id(p.base) then return nil, "it's built on the style '" .. p.base .. "', which isn't here" end
  local list = load_presets()
  p.id = (p.feel_from and "mix_" or "preset_") .. os.time() .. "_" .. #list
  list[#list + 1] = p
  M.write(PRESETS, M.json_encode({ presets = list }) .. "\n")
  load_presets()
  return M.by_id(p.id)
end
function M.delete_preset(id)
  local list = load_presets()
  for n = #list, 1, -1 do if list[n].id == id then table.remove(list, n) end end
  M.write(PRESETS, M.json_encode({ presets = list }) .. "\n")
  load_presets()
end

-- ---------------------------------------------------------------- using a style
local function set_toggles(on_id)
  for _, st in ipairs(M.styles) do
    local id = cmd_id(M.scripts.main["use " .. st.id] or "")
    if id ~= 0 then reaper.SetToggleCommandState(0, id, st.id == on_id and 1 or 0); reaper.RefreshToolbar2(0, id) end
  end
end
function M.use(st)
  if not st then return end
  local was = M.current()
  if was and was.id == "my_reaper" then -- (My REAPER's theme is whatever you had in it)
    local th = (reaper.GetLastColorThemeFile() or ""):gsub("\\", "/"):match("[^/]+$")
    if th then reaper.SetExtState(M.SECTION, "theme my_reaper", th, true) end
  end
  reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(CLEAR, 0)
  if (st.alt or 0) > 0 then reaper.Main_OnCommand(TOGGLE_ALT + st.alt, 0) end
  local left = {}
  restore_feel(left)
  apply_feel(st, left)
  local th = M.theme_for(st)
  if th and reaper.file_exists(M.themes_dir .. th) and th ~= (reaper.GetLastColorThemeFile() or ""):gsub("\\", "/"):match("[^/]+$") then
    reaper.OpenColorThemeFile(M.themes_dir .. th)
    local own = th:match("^ReaPersona %- (.+)%.ReaperThemeZip$") -- (a ReaPersona theme built outside REAPER: its Default 7 settings, once)
    if own and M.params_for_loaded and reaper.GetExtState(M.SECTION, "params " .. own) == "" then M.params_for_loaded(own); reaper.ThemeLayout_RefreshAll() end
  end
  reaper.SetExtState(M.SECTION, "style", st.id, true)
  set_toggles(st.base or st.id)
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
end
function M.use_id(id) M.use(M.by_id(id)) end
function M.next_style()
  local cur = M.current()
  for n, st in ipairs(M.styles) do if st == cur then return M.use(M.styles[n % #M.styles + 1]) end end
  M.use(M.styles[1])
end
-- REAPER doesn't keep the shortcut override across a restart (the theme, toggles and mouse behaviours it does keep): put it back.
function M.restore_last()
  local st = M.current()
  if st and (st.alt or 0) > 0 and M.active_alt() ~= st.alt then reaper.Main_OnCommand(CLEAR, 0); reaper.Main_OnCommand(TOGGLE_ALT + st.alt, 0) end
  set_toggles(st and (st.base or st.id))
end

-- ---------------------------------------------------------------- MIDI editor keys
-- The MIDI editor has no shortcut layers, so each MIDI key a style uses is bound (by install_shortcuts.py) to a tiny script that
-- asks here what the style in use wants; with no style key it runs what that key did in your own keymap (midi_fallback.json).
local midi_names
local function midi_action(name)
  if not midi_names then
    midi_names = {}
    for i = 0, 100000 do
      local id, n = reaper.CF_EnumerateActions(MIDI_SEC, i, "")
      if not id or id <= 0 then break end
      midi_names[n] = id
    end
  end
  return midi_names[name]
end
M.midi_action = midi_action
local function midi_run(id) if id and id ~= 0 then reaper.MIDIEditor_LastFocused_OnCommand(id, false) end end
function M.midi_key(spec)
  local st = M.current()
  for _, k in ipairs(st and st.midi_keys or {}) do
    if k[1] == spec then
      local list = type(k[2]) == "table" and k[2] or { k[2] }
      for _ = 1, k[4] or 1 do
        for _, name in ipairs(list) do midi_run(type(name) == "number" and name or midi_action(name) or reaper.NamedCommandLookup(name)) end
      end
      return
    end
  end
  local fb = M.json_decode(M.read(M.here .. "/midi_fallback.json") or "{}") or {}
  local c = fb[spec] and fb[spec].cmd
  if c and c == M.scripts.midi[spec] then return end -- (a fallback that is this very script would run itself forever)
  if c then midi_run(tonumber(c) or reaper.NamedCommandLookup((c:sub(1, 1) == "_" and "" or "_") .. c)) end
end

-- What REAPER's MIDI editor does on each key the styles use, by default (reaper-kb.ini only holds changes, so the installer can't see
-- these): written to midi_defaults.json, read by install_shortcuts.py for the My REAPER fallback. Run it before the MIDI keys are
-- installed (afterwards those keys show the ReaPersona scripts). -> how many keys had a default
local function canon(desc) -- "Shift+Ctrl+Up" / "Ctrl+Shift+Up" -> "Ctrl+Shift+Up"; REAPER's key names to styles.json's
  local mods, key = {}, desc:match("([^+]+)$") or desc
  if desc:sub(-2) == "++" then key = "+" end
  for m in desc:gmatch("(%a+)%+") do mods[m] = true end
  key = ({ ["Page Up"] = "PgUp", ["Page Down"] = "PgDn", PageUp = "PgUp", PageDown = "PgDn", Del = "Delete", Ins = "Insert",
           Return = "Enter", Spacebar = "Space" })[key] or key
  local out = {}
  for _, m in ipairs({ "Ctrl", "Alt", "Shift" }) do if mods[m] then out[#out + 1] = m end end
  out[#out + 1] = key
  return table.concat(out, "+")
end
M.canon = canon
function M.midi_defaults()
  local want = {}
  for _, st in ipairs(M.styles) do for _, k in ipairs(st.midi_keys or {}) do want[canon(k[1])] = k[1] end end
  local sec, found, n = reaper.SectionFromUniqueID(MIDI_SEC), {}, 0
  for i = 0, 100000 do
    local id = reaper.CF_EnumerateActions(MIDI_SEC, i, "")
    if not id or id <= 0 then break end
    for s = 0, reaper.CountActionShortcuts(sec, id) - 1 do
      local _, desc = reaper.GetActionShortcutDesc(sec, id, s, "")
      local spec = want[canon(desc or "")]
      if spec and not found[spec] then found[spec] = id; n = n + 1 end
    end
  end
  M.write(M.here .. "/midi_defaults.json", M.json_encode(found) .. "\n")
  return n
end

-- ---------------------------------------------------------------- helper scripts (written and registered once, by the picker)
local function safe(spec) return (spec:gsub("[^%w]", function(c) return string.format("_%02X", c:byte()) end)) end
local function stub(path, call)
  return M.write(path, '-- @noindex\n-- (made by ReaPersona: ' .. call .. ')\nlocal p = debug.getinfo(1, "S").source:match("^@?(.*)[/\\\\]")\n' ..
    'local core = dofile(p .. "/../reapersona_core.lua")\ncore.' .. call .. '\n')
end
-- What scripts the styles need, and whether they're all registered. -> missing count
function M.scripts_missing()
  local n = 0
  for _, st in ipairs(M.styles) do
    if not M.scripts.main["use " .. st.id] then n = n + 1 end
    for _, k in ipairs(st.midi_keys or {}) do if not M.scripts.midi[k[1]] then n = n + 1 end end
  end
  return n
end
function M.ensure_scripts()
  reaper.RecursiveCreateDirectory(M.here .. "/actions", 0)
  reaper.RecursiveCreateDirectory(M.here .. "/midi_keys", 0)
  local main = { ["next style"] = "next_style()", ["restore last style"] = "restore_last()", ["memory location"] = "memory_location()",
                 ["play from start"] = "play_from_start()" }
  for _, st in ipairs(M.styles) do main["use " .. st.id] = 'use_id("' .. st.id .. '")' end
  local todo = {}
  for name, call in pairs(main) do
    local label = (name:match("^use ") and ("use " .. M.by_id(name:sub(5)).name) or name):gsub('[/\\:%*%?"<>|]', "-") -- (a file name)
    local p = M.here .. "/actions/ReaPersona - " .. label .. ".lua"
    stub(p, call); todo[#todo + 1] = { 0, p, "main", name }
  end
  local specs = {}
  for _, st in ipairs(M.styles) do for _, k in ipairs(st.midi_keys or {}) do specs[k[1]] = true end end
  for spec in pairs(specs) do
    local p = M.here .. "/midi_keys/ReaPersona MIDI key " .. safe(spec) .. ".lua"
    stub(p, 'midi_key("' .. spec:gsub("\\", "\\\\"):gsub('"', '\\"') .. '")'); todo[#todo + 1] = { MIDI_SEC, p, "midi", spec }
  end
  for n, t in ipairs(todo) do
    local id = reaper.AddRemoveReaScript(true, t[1], t[2], n == #todo)
    if id and id ~= 0 then M.scripts[t[3]][t[4]] = "_" .. reaper.ReverseNamedCommandLookup(id) end
  end
  M.write(M.here .. "/scripts.json", M.json_encode(M.scripts) .. "\n")
  return #todo
end

-- ---------------------------------------------------------------- features some styles' keys call
function M.memory_location() -- Pro Tools: period, number, period on the numeric keypad recalls a memory location (here: a marker)
  local ok, s = reaper.GetUserInputs("Memory Location", 1, "Number (then Enter),extrawidth=-40", "")
  local n = ok and tonumber((s:gsub("%D", "")))
  if n then reaper.GoToMarker(0, n, false) end
end
function M.play_from_start() -- Bitwig: Alt+Space plays the arrangement from the beginning
  reaper.CSurf_GoStart(); reaper.OnPlayButton()
end

-- ---------------------------------------------------------------- extensions some styles recommend (smooth playhead, smooth scroll and zoom)
M.EXTENSIONS = {
  playhead = { name = "ReaSmoothPlayhead", toggle = "_PLAYHEAD_TOGGLE_SMOOTH", settings = "_PLAYHEAD_SETTINGS", dll = "reaper_playhead",
    repo = { "ReaSmoothPlayhead", "https://raw.githubusercontent.com/Sakhnovkrg/ReaSmoothPlayheadReapack/main/index.xml" },
    why = "the playhead glides smoothly instead of stepping", feel = "moves its playhead smoothly" },
  smoothscroll = { name = "Smooth Wheel Scroll", settings = "_SWS_SCROLL_TUNE", dll = "reaper_smoothwheelscroll",
    file = "extensions/reaper_smoothwheelscroll-x64.dll", where = "not on ReaPack: ReaPersona installs it only when it carries a copy",
    why = "scrolling and zooming with the mouse wheel glide instead of jumping", feel = "scrolls and zooms smoothly" },
}
local function dll_present(prefix)
  for i = 0, 500 do
    local f = reaper.EnumerateFiles(res .. "/UserPlugins", i)
    if not f then return false end
    if f:lower():find(prefix, 1, true) == 1 then return true end
  end
end
function M.extension_state(key) -- -> "on", "off", "restart" (installed, not loaded yet) or "missing"
  local x = M.EXTENSIONS[key]
  if reaper.NamedCommandLookup(x.toggle or x.settings) ~= 0 then
    return (not x.toggle or reaper.GetToggleCommandState(reaper.NamedCommandLookup(x.toggle)) == 1) and "on" or "off"
  end
  return dll_present(x.dll) and "restart" or "missing"
end
function M.can_install(key)
  local x = M.EXTENSIONS[key]
  return (x.repo and reaper.ReaPack_AddSetRepository ~= nil) or (x.file ~= nil and reaper.file_exists(M.here .. "/" .. x.file))
end
function M.install_extension(key) -- -> true, or nil + why. REAPER loads it at its next start.
  local x = M.EXTENSIONS[key]
  if x.repo and reaper.ReaPack_AddSetRepository then
    -- (one AddSetRepository with the final autoInstall, then one ProcessQueue: a second pass while ReaPack's report is open crashed REAPER)
    local ok, err = reaper.ReaPack_AddSetRepository(x.repo[1], x.repo[2], true, 1, "")
    if not ok then return nil, err end
    reaper.ReaPack_ProcessQueue(true)
    return true
  elseif x.file and reaper.file_exists(M.here .. "/" .. x.file) then
    local data = M.read(M.here .. "/" .. x.file)
    if not (data and M.write(res .. "/UserPlugins/" .. x.file:match("[^/]+$"), data)) then return nil, "couldn't copy it into UserPlugins" end
    return true
  end
  return nil, x.where or "no way to install it from here"
end

-- ---------------------------------------------------------------- themes you add, styles made by merging shortcuts
function M.import_theme(path) -- copy a downloaded theme into ColorThemes -> its file name, or nil + why
  local name = path:gsub("\\", "/"):match("[^/]+$") or ""
  if not (name:match("%.ReaperThemeZip$") or name:match("%.ReaperTheme$")) then return nil, "not a .ReaperThemeZip or .ReaperTheme" end
  if reaper.file_exists(M.themes_dir .. name) then return name end
  local data = M.read(path)
  if not data then return nil, "couldn't read it" end
  if not M.write(M.themes_dir .. name, data) then return nil, "couldn't write into ColorThemes" end
  return name
end
local function copy(v) if type(v) ~= "table" then return v end local t = {}; for k, x in pairs(v) do t[k] = copy(x) end return t end
local function free_alt()
  local used = {}
  for _, s in ipairs(M.styles) do used[s.alt or 0] = true end
  for a = 1, 16 do if not used[a] then return a end end
end
-- A new style: `base`'s theme, feel and keys, plus `from`'s keys (theirs win where both use a key, unless only_gaps). -> the style, or nil + why
function M.merge_keys(base_id, from_id, only_gaps, name)
  local base, from = M.by_id(base_id), M.by_id(from_id)
  if not (base and from) then return nil, "pick two styles" end
  local alt = free_alt()
  if not alt then return nil, "all 16 shortcut layers are in use" end
  local st = copy(base)
  st.id, st.name, st.alt, st.user, st.preset, st.base, st.kind = "merged_" .. os.time(), name, alt, nil, nil, nil, "daw"
  st.description = name .. ": " .. base.name .. "'s theme and feel with " .. base.name .. "'s keys and " .. from.name .. "'s" ..
    (only_gaps and " (only on keys " .. base.name .. " doesn't use)." or " (" .. from.name .. "'s win where both use a key).")
  for _, field in ipairs({ "keys", "midi_keys" }) do
    local by, order = {}, {}
    for _, k in ipairs(base[field] or {}) do if not by[k[1]] then order[#order + 1] = k[1] end by[k[1]] = copy(k) end
    for _, k in ipairs(from[field] or {}) do
      if not by[k[1]] then order[#order + 1] = k[1]; by[k[1]] = copy(k) elseif not only_gaps then by[k[1]] = copy(k) end
    end
    st[field] = {}
    for _, spec in ipairs(order) do st[field][#st[field] + 1] = by[spec] end
  end
  st.docs = {}
  for _, d in ipairs(base.docs or {}) do st.docs[#st.docs + 1] = d end
  for _, d in ipairs(from.docs or {}) do st.docs[#st.docs + 1] = d end
  local users = load(M.here .. "/user_styles.json")
  users[#users + 1] = st
  M.write(M.here .. "/user_styles.json", M.json_encode({ styles = users }) .. "\n")
  st.user = true
  M.styles[#M.styles + 1] = st
  return st
end
function M.delete_user_style(id)
  local users = load(M.here .. "/user_styles.json")
  for n = #users, 1, -1 do if users[n].id == id then table.remove(users, n) end end
  M.write(M.here .. "/user_styles.json", M.json_encode({ styles = users }) .. "\n")
  for n = #M.styles, 1, -1 do if M.styles[n].id == id and M.styles[n].user then table.remove(M.styles, n) end end
end

-- ---------------------------------------------------------------- shortcuts without Python: a .ReaperKeyMap to import
-- (Actions > Key Map > Import, merge.) The same lines install_shortcuts.py writes; it also moves your own MIDI editor lines for the
-- styles' MIDI keys into midi_fallback.json so My REAPER keeps them. Toolbars still need install_shortcuts.py (REAPER closed).
local VIRT, SHIFT, CTRL, ALT, EXT = 1, 4, 8, 16, 32768
local NAMED = { Space = 32, Enter = 13, Backspace = 8, Tab = 9, Esc = 27, Left = EXT + 37, Up = EXT + 38, Right = EXT + 39, Down = EXT + 40,
  Home = EXT + 36, End = EXT + 35, PgUp = EXT + 33, PgDn = EXT + 34, Insert = EXT + 45, Delete = EXT + 46,
  ["Num*"] = 106, ["Num+"] = 107, ["Num-"] = 109, ["Num."] = 110, ["Num/"] = 111 }
for i = 1, 12 do NAMED["F" .. i] = 111 + i end
for i = 0, 9 do NAMED["Num" .. i] = 96 + i end
local OEM = { ["?"] = 191, [";"] = 186, ["="] = 187, ["+"] = 187, [","] = 188, ["-"] = 189, ["."] = 190, ["/"] = 191, ["`"] = 192,
  ["["] = 219, ["\\"] = 220, ["]"] = 221, ["'"] = 222 }
local WHEEL = { Mousewheel = { 255, 248 }, ["Ctrl+Alt+Mousewheel"] = { 255, 251 } }
function M.encode(spec) -- "Ctrl+Shift+L" -> flags, key as reaper-kb.ini writes them (same as install_shortcuts.encode), or nil
  if WHEEL[spec] then return WHEEL[spec][1], WHEEL[spec][2] end
  local key, mods
  if spec:sub(-1) == "+" then -- ("+", "Num+", "Ctrl++": the key itself ends in a plus)
    local rest = spec:sub(1, -2)
    local cut = rest:find("%+[^+]*$")
    if cut then key, mods = rest:sub(cut + 1) .. "+", rest:sub(1, cut - 1) else key, mods = rest .. "+", "" end
  else
    local cut = spec:find("%+[^+]*$")
    if cut then key, mods = spec:sub(cut + 1), spec:sub(1, cut - 1) else key, mods = spec, "" end
  end
  local flags = 0
  for m in mods:gmatch("[^+]+") do
    local f = ({ Shift = SHIFT, Ctrl = CTRL, Alt = ALT })[m]
    if not f then return nil end
    flags = flags | f
  end
  if NAMED[key] then return VIRT | flags, NAMED[key] end
  if #key == 1 and key:match("%a") then return VIRT | flags, key:upper():byte() end
  if #key == 1 and key:match("%d") then return VIRT | flags, key:byte() end
  if #key == 1 and OEM[key] then
    if flags == 0 then return 0, key:byte() end -- (unmodified punctuation goes in as the character, as REAPER itself writes '-' and '=')
    return VIRT | flags, OEM[key]
  end
end
function M.make_keymap() -- -> path of the .ReaperKeyMap, how many lines, what was skipped
  local kb = M.read(res .. "/reaper-kb.ini") or ""
  local midi_cmds = {}
  for _, id in pairs(M.scripts.midi) do midi_cmds[id] = true end
  local main, midi_user = {}, {}
  for line in kb:gmatch("[^\r\n]+") do
    local f, k, cmd, sec = line:match("^KEY (%d+) (%d+) (%S+) (%d+)")
    if sec == "0" and cmd ~= "0" then main[f .. " " .. k] = cmd
    elseif sec == "32060" and not midi_cmds[cmd] and not line:find("MIDI key", 1, true) then midi_user[f .. " " .. k] = { cmd = cmd, line = line } end
  end
  local out, skipped, specs = {}, {}, {}
  for _, st in ipairs(M.styles) do
    local alt = st.alt or 0
    if alt >= 1 and alt <= 16 then
      for _, k in ipairs(st.keys or {}) do
        local f, key = M.encode(k[1])
        local cmd = k[2]
        if type(cmd) == "string" and cmd:match("^MAIN:") then
          local ff, kk = M.encode(cmd:sub(6))
          cmd = (ff and main[ff .. " " .. kk]) or ({ ["Ctrl+Z"] = 40029, ["Ctrl+Shift+Z"] = 40030 })[cmd:sub(6)] or 0
        elseif type(cmd) == "string" and cmd:match("^script:") then cmd = M.scripts.main[cmd:sub(8)] end
        if f and cmd then out[#out + 1] = string.format("KEY %d %d %s %d", f, key, tostring(cmd), alt)
        else skipped[#skipped + 1] = st.name .. " " .. k[1] end
      end
    end
    for _, k in ipairs(st.midi_keys or {}) do specs[k[1]] = true end
  end
  local fb = M.json_decode(M.read(M.here .. "/midi_fallback.json") or "{}") or {}
  local defaults = M.json_decode(M.read(M.here .. "/midi_defaults.json") or "null")
  if not defaults then M.midi_defaults(); defaults = M.json_decode(M.read(M.here .. "/midi_defaults.json") or "{}") or {} end
  for spec in pairs(specs) do
    local f, key = M.encode(spec)
    local cmd = M.scripts.midi[spec]
    if f and cmd then
      if not fb[spec] then
        local mine = midi_user[f .. " " .. key]
        fb[spec] = mine or (defaults[spec] and { cmd = tostring(defaults[spec]) }) or nil
      end
      out[#out + 1] = string.format("KEY %d %d %s 32060", f, key, cmd)
    else skipped[#skipped + 1] = "MIDI " .. spec end
  end
  M.write(M.here .. "/midi_fallback.json", M.json_encode(fb) .. "\n")
  reaper.RecursiveCreateDirectory(res .. "/KeyMaps", 0)
  local p = res .. "/KeyMaps/ReaPersona shortcuts.ReaperKeyMap"
  M.write(p, table.concat(out, "\n") .. "\n")
  return p, #out, skipped
end
function M.toolbar_installed(section) -- is [Floating toolbar N] / [Floating MIDI toolbar N] one of ours in reaper-menu.ini?
  local t = M.read(res .. "/reaper-menu.ini") or ""
  local body = t:match("%[" .. section:gsub("%p", "%%%0") .. "%]([^%[]*)")
  return body ~= nil and (body:find("title=ReaPersona", 1, true) ~= nil or body:find("title=DAW Styles", 1, true) ~= nil)
end

-- ---------------------------------------------------------------- setup: Python, ReaPersona's own themes, the startup line
local function sh(cmd, ms) local out = reaper.ExecProcess(cmd, ms or 20000) or ""; local code, text = out:match("^(%-?%d+)\n(.*)$"); return code, text or out end
function M.python() -- -> "Python 3.x" when python runs here, else nil (cached)
  if M._py == nil then
    local code, text = sh('python --version', 8000)
    M._py = (code == "0" and text:match("Python %S+")) or false
  end
  return M._py or nil
end
function M.python_libs() -- -> true when this Python has Pillow and numpy (theme building needs them); cached
  if M._libs == nil then M._libs = M.python() ~= nil and sh('python -c "import PIL, numpy"', 15000) == "0" end
  return M._libs
end
function M.install_python_libs() -- pip install --user pillow numpy (REAPER waits while it downloads). -> true, or nil + what pip said
  local code, text = sh("python -m pip install --user pillow numpy", 600000)
  M._libs = nil
  if code == "0" and M.python_libs() then return true end
  return nil, (text or ""):sub(-400)
end
M.OWN = (function() local t = M.read(M.here .. "/styles.json"); local ok, d = pcall(M.json_decode, t or "{}"); return ok and d and d.own_themes or {} end)()
M.CATALOG = (function() local t = M.read(M.here .. "/styles.json"); local ok, d = pcall(M.json_decode, t or "{}"); return ok and d and d.themes or {} end)()
function M.own_theme_file(name) return "ReaPersona - " .. name .. ".ReaperThemeZip" end
function M.own_themes_built()
  local n, total = 0, 0
  for name in pairs(M.OWN) do total = total + 1; if reaper.file_exists(M.themes_dir .. M.own_theme_file(name)) then n = n + 1 end end
  return n, total
end
-- Each built theme's Default 7 settings: its panels in the DAW's colour, how strongly track colours show, text brightness. REAPER keeps
-- them per theme (reaper-themeconfig.ini). Loads each theme for a moment, then puts yours back.
local function params_for_loaded(name) -- the recipe's Default 7 settings, onto the ReaPersona theme that's loaded now
  local rec = M.OWN[name]
  if not rec then return end
  local t = rec.tint or "#C8C8C8"
  local r, g, b = tonumber(t:sub(2, 3), 16), tonumber(t:sub(4, 5), 16), tonumber(t:sub(6, 7), 16)
  local scale = 134 / math.max((r + g + b) / 3, 1) * (rec.gain or 1) -- (Default 7's own panel colour sits near 134)
  local want = { textBrightness = rec.text or 100, customColorDepthParam = rec.color_strength or 30, selectStrength = rec.select or 25 }
  for _, part in ipairs({ "tcpBgCol", "mcpBgCol" }) do
    want[part .. "R"], want[part .. "G"], want[part .. "B"] = math.floor(math.min(255, r * scale)), math.floor(math.min(255, g * scale)), math.floor(math.min(255, b * scale))
  end
  for i = 0, 600 do
    local pname = reaper.ThemeLayout_GetParameter(i)
    if not pname then break end
    if want[pname] then reaper.ThemeLayout_SetParameter(i, want[pname], true) end
  end
  reaper.SetExtState(M.SECTION, "params " .. name, "1", true)
end
M.params_for_loaded = params_for_loaded
local function apply_own_params()
  local was = reaper.GetLastColorThemeFile()
  for name in pairs(M.OWN) do
    local path = M.themes_dir .. M.own_theme_file(name)
    if reaper.file_exists(path) then reaper.OpenColorThemeFile(path); params_for_loaded(name) end
  end
  if was and was ~= "" then reaper.OpenColorThemeFile(was) end
  reaper.ThemeLayout_RefreshAll()
end
M.apply_own_params = apply_own_params
function M.build_own_themes() -- -> list of themes written, or nil + why
  if not M.python() then return nil, "it needs Python 3 (python.org), with Pillow and numpy" end
  if not M.python_libs() then return nil, "Python needs Pillow and numpy: Setup > Install them (or: python -m pip install --user pillow numpy)" end
  local code, text = sh('python "' .. M.here .. '/build_themes.py" "' .. M.themes_dir:gsub("/$", "") .. '"', 180000)
  local first, rest = (text or ""):match("^(%d)\n(.*)$")
  if code ~= "0" or first ~= "0" then return nil, (rest or text or ""):sub(1, 400) end
  apply_own_params()
  local made = {}
  for l in rest:gmatch("[^\r\n]+") do made[#made + 1] = l end
  return made
end
function M.startup_path() return res .. "/Scripts/__startup.lua" end
function M.startup_on() return (M.read(M.startup_path()) or ""):find("reapersona_core.lua", 1, true) ~= nil end
function M.add_startup() -- one block in Scripts/__startup.lua that brings back the last style's keys when REAPER starts
  if M.startup_on() then return true end
  local rel = M.here:sub(#res + 2) -- (e.g. Scripts/ReaPersona or Scripts/ReaPersona/Workflow)
  local block = "\n-- >>> ReaPersona: REAPER forgets the shortcut layer at restart, so bring back the last style's keys\ndo\n" ..
    '  local ok, err = pcall(function() dofile(reaper.GetResourcePath() .. "/' .. rel .. '/reapersona_core.lua").restore_last() end)\n' ..
    '  if not ok then reaper.ShowConsoleMsg("[ReaPersona] restore failed: " .. tostring(err) .. "\\n") end\nend\n-- <<< ReaPersona <<<\n'
  local f = io.open(M.startup_path(), "a")
  if not f then return nil, "couldn't write " .. M.startup_path() end
  f:write(block); f:close()
  return true
end

-- ---------------------------------------------------------------- dropping files in: themes, theme packs, toolbars, keymaps, styles, presets
local KEYNAME = {} -- (key code -> name, for keymaps dropped in)
for k, v in pairs(NAMED) do KEYNAME[v] = k end
local function decode(f, k) -- reaper-kb.ini flags, key -> "Ctrl+Shift+L" (the reverse of M.encode), or nil
  f, k = tonumber(f), tonumber(k)
  if not (f and k) or f == 255 then return nil end
  local mods = {}
  if f & CTRL ~= 0 then mods[#mods + 1] = "Ctrl" end
  if f & ALT ~= 0 then mods[#mods + 1] = "Alt" end
  if f & SHIFT ~= 0 then mods[#mods + 1] = "Shift" end
  local key
  if f & VIRT == 0 then key = string.char(k)
  elseif KEYNAME[k] then key = KEYNAME[k]
  elseif (k >= 65 and k <= 90) or (k >= 48 and k <= 57) then key = string.char(k)
  else for ch, code in pairs(OEM) do if code == k and ch ~= "+" and ch ~= "?" then key = ch end end end
  if not key then return nil end
  mods[#mods + 1] = key
  return table.concat(mods, "+")
end
M.decode = decode
-- A .ReaperKeyMap's Main-section keys as a new style on its own shortcut layer. -> the style, or nil + why
function M.style_from_keymap(path)
  local name = (path:gsub("\\", "/"):match("([^/]+)%.[Rr]eaper[Kk]ey[Mm]ap$") or "Keymap")
  local keys, seen = {}, {}
  for line in (M.read(path) or ""):gmatch("[^\r\n]+") do
    local f, k, cmd, sec = line:match("^KEY (%d+) (%d+) (%S+) (%d+)")
    if sec == "0" and cmd ~= "0" then
      local spec = decode(f, k)
      if spec and not seen[spec] then
        seen[spec] = true
        local label = line:match("#%s*[^:]+:%s*[^:]+:%s*(.+)$") or ("action " .. cmd)
        keys[#keys + 1] = { spec, tonumber(cmd) or (cmd:sub(1, 1) == "_" and cmd or "_" .. cmd), label }
      end
    end
  end
  if #keys == 0 then return nil, "no Main-section keys in it" end
  local alt = free_alt()
  if not alt then return nil, "all 16 shortcut layers are in use" end
  local st = { id = "keymap_" .. os.time(), name = name, alt = alt, kind = "daw", keys = keys, feel = {},
    description = name .. ": the keys from " .. name .. ".ReaperKeyMap on their own shortcut layer (alt-" .. alt .. "); your theme and settings." }
  local users = load(M.here .. "/user_styles.json")
  users[#users + 1] = st
  M.write(M.here .. "/user_styles.json", M.json_encode({ styles = users }) .. "\n")
  st.user = true
  M.styles[#M.styles + 1] = st
  return st
end
-- Whatever was dropped on the window. -> list of { kind, name, detail } (kind: theme, toolbar, style, preset, skipped)
function M.import_file(path, out)
  out = out or {}
  local p = path:gsub("\\", "/")
  local base = p:match("[^/]+$") or p
  local low = base:lower()
  if low:match("%.reaperthemezip$") or low:match("%.reapertheme$") then
    local n, why = M.import_theme(p)
    out[#out + 1] = { n and "theme" or "skipped", n or base, why }
  elseif low:match("%.reapermenu$") then
    reaper.RecursiveCreateDirectory(M.here .. "/toolbars", 0)
    local ok = M.write(M.here .. "/toolbars/" .. base, M.read(p) or "")
    out[#out + 1] = { ok and "toolbar" or "skipped", base, ok and "in ReaPersona's toolbars folder: install the shortcuts to use it" or "couldn't copy" }
  elseif low:match("%.reaperkeymap$") then
    local st, why = M.style_from_keymap(p)
    out[#out + 1] = { st and "style" or "skipped", st and st.name or base, st and ("shortcut layer alt-" .. st.alt) or why }
  elseif low:match("%.json$") then
    local ok, d = pcall(M.json_decode, M.read(p) or "")
    if ok and d and d.preset then
      local pr, why = M.import_preset(d)
      out[#out + 1] = { pr and "preset" or "skipped", pr and pr.name or base, why }
    elseif ok and d and d.style then
      local st, why = M.import(p)
      out[#out + 1] = { st and "style" or "skipped", st and st.name or base, st and ("shortcut layer alt-" .. st.alt) or why }
    else out[#out + 1] = { "skipped", base, "not a ReaPersona style or preset" } end
  elseif low:match("%.zip$") then -- (a theme pack: unpacked with Windows' or macOS's own tar, then everything usable inside comes in)
    local dir = M.here .. "/_incoming/" .. base:gsub("%.[Zz][Ii][Pp]$", "")
    reaper.RecursiveCreateDirectory(dir, 0)
    sh('tar -xf "' .. p .. '" -C "' .. dir .. '"', 60000)
    local function walk(d)
      reaper.EnumerateFiles(d, -1); reaper.EnumerateSubdirectories(d, -1) -- (REAPER caches folder listings: rescan)
      for i = 0, 2000 do local f = reaper.EnumerateFiles(d, i); if not f then break end M.import_file(d .. "/" .. f, out) end
      for i = 0, 200 do local s = reaper.EnumerateSubdirectories(d, i); if not s then break end walk(d .. "/" .. s) end
    end
    walk(dir)
    local win = reaper.GetOS():find("^Win") -- (the unpacked copy was ours, made just above: gone again)
    sh(win and ('cmd /c rmdir /s /q "' .. dir:gsub("/", "\\") .. '"') or ("rm -rf '" .. dir .. "'"), 20000)
    if #out == 0 then out[#out + 1] = { "skipped", base, "nothing ReaPersona can use inside" } end
  else out[#out + 1] = { "skipped", base, "not a theme, toolbar, keymap, style or preset" } end
  return out
end

-- ---------------------------------------------------------------- share a style, print its cheat sheet
function M.export(st, path)
  local copy = {}
  for k, v in pairs(st) do if k ~= "user" then copy[k] = v end end
  local th = M.theme_for(st)
  if th and th:match("%.ReaperTheme$") then copy.theme_file = { name = th, text = M.read(M.themes_dir .. th) } end
  return M.write(path, M.json_encode({ reapersona = 1, style = copy }) .. "\n")
end
function M.import(path) -- -> the style, or nil + why. Shortcuts need install_shortcuts.py (REAPER closed) after.
  local ok, d = pcall(M.json_decode, M.read(path) or "")
  local st = ok and d and d.style
  if not st or not st.id or not st.name then return nil, "not a ReaPersona file" end
  local used = {}
  for _, s in ipairs(M.styles) do used[s.alt or 0] = s.id end
  if M.by_id(st.id) and not M.by_id(st.id).user then st.id = st.id .. "_shared" end
  if not st.alt or (used[st.alt] and used[st.alt] ~= st.id) then
    st.alt = nil
    for a = 1, 16 do if not used[a] then st.alt = a; break end end
    if not st.alt then return nil, "all 16 shortcut layers are in use" end
  end
  if st.theme_file and st.theme_file.name and st.theme_file.text then
    if not reaper.file_exists(M.themes_dir .. st.theme_file.name) then M.write(M.themes_dir .. st.theme_file.name, st.theme_file.text) end
    st.theme = st.theme_file.name
  end
  st.theme_file = nil
  local users = load(M.here .. "/user_styles.json")
  for n = #users, 1, -1 do if users[n].id == st.id then table.remove(users, n) end end
  users[#users + 1] = st
  M.write(M.here .. "/user_styles.json", M.json_encode({ styles = users }) .. "\n")
  return st
end
local function esc(s) return (tostring(s):gsub("[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" })) end
function M.cheat_sheet(st) -- -> path of an HTML page laid out for printing
  local h = { "<!doctype html><meta charset='utf-8'><title>" .. esc(st.name) .. " in REAPER</title><style>",
    "body{font:13px/1.35 system-ui,sans-serif;margin:24px;color:#111}h1{font-size:20px;margin:0 0 4px}h2{font-size:14px;margin:16px 0 4px;border-bottom:1px solid #999}",
    "table{border-collapse:collapse;width:100%}td{padding:2px 6px;vertical-align:top}td:first-child{white-space:nowrap;font-weight:600;width:150px}",
    ".cols{columns:2;column-gap:28px}p{margin:4px 0;color:#444}@media print{body{margin:10mm}}</style>",
    "<h1>" .. esc(st.name) .. " in REAPER</h1><p>" .. esc(st.description or "") .. "</p>" }
  local function tbl(title, rows)
    if #rows == 0 then return end
    h[#h + 1] = "<h2>" .. title .. "</h2><div class='cols'><table>"
    for _, r in ipairs(rows) do h[#h + 1] = "<tr><td>" .. esc(r[1]) .. "</td><td>" .. esc(r[2]) .. "</td></tr>" end
    h[#h + 1] = "</table></div>"
  end
  local rows = {}
  for _, k in ipairs(st.keys or {}) do rows[#rows + 1] = { k[1], k[3] } end
  tbl("Arrange", rows)
  rows = {}
  for _, k in ipairs(st.midi_keys or {}) do rows[#rows + 1] = { k[1], k[3] } end
  tbl("MIDI editor", rows)
  rows = {}
  for _, f in ipairs(st.feel or {}) do rows[#rows + 1] = { f[1] == "mouse" and "Mouse" or "Setting", f[#f] } end
  tbl("How it behaves", rows)
  rows = {}
  for _, x in ipairs(st.extras or {}) do rows[#rows + 1] = { x[3] or "", x[1] } end
  tbl("Where " .. esc(st.name) .. "'s features are in REAPER", rows)
  rows = {}
  for _, x in ipairs(st.tips or {}) do rows[#rows + 1] = { x[3] or "", x[1] } end
  tbl("Tips", rows)
  if st.docs then h[#h + 1] = "<p>Keys from: " .. esc(table.concat(st.docs, " · ")) .. "</p>" end
  reaper.RecursiveCreateDirectory(M.here .. "/cheat sheets", 0)
  local p = M.here .. "/cheat sheets/" .. st.name .. ".html"
  M.write(p, table.concat(h, "\n"))
  return p
end

-- ---------------------------------------------------------------- merge themes (merge_themes.py does the zip work)
function M.merge(base, colours, graphics, parts, fonts) -- -> new theme's file name, or nil + what python said
  local function q(s) return '"' .. s .. '"' end
  local cmd = { "python", q(M.here .. "/merge_themes.py"), q(base), q(colours) }
  if graphics and #parts > 0 then cmd[#cmd + 1] = "--graphics " .. q(graphics) .. " --parts " .. table.concat(parts, ",") end
  if fonts then cmd[#cmd + 1] = "--fonts" end
  local out = reaper.ExecProcess(table.concat(cmd, " "), 60000) or ""
  local code, text = out:match("^(%-?%d+)\n(.*)$")
  local name = text and text:match("([^\r\n]+%.ReaperThemeZip)")
  if code == "0" and name then return name end
  return nil, out
end

function M.open_url(u)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(u)
  elseif reaper.GetOS():find("^Win") then os.execute('start "" "' .. u .. '"') else os.execute("open '" .. u .. "'") end
end

return M
