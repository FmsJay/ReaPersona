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
M.OBJECT = {} -- (metatable marking a decoded JSON object)
local CLEAR, TOGGLE_ALT, MIDI_SEC = 24800, 24802, 32060 -- "Main action section: Clear any override" / "Toggle override to alt-N" = 24802 + N

function M.read(p) -- (a write cut short leaves the whole new text in p.tmp: read that then)
  local f = io.open(p, "rb") or io.open(p .. ".tmp", "rb"); if not f then return nil end local t = f:read("a"); f:close(); return t
end
function M.write(p, t) -- through a temp file and a rename, so a crash mid-write never leaves half a file. -> true / false
  local f = io.open(p .. ".tmp", "wb"); if not f then return false end
  local ok = f:write(t) and true; ok = f:close() and ok
  if not ok then os.remove(p .. ".tmp"); return false end
  os.remove(p) -- (Windows' rename won't replace a file)
  return os.rename(p .. ".tmp", p) == true
end
-- The MIDI editor docks only through an open editor, and REAPER opens new ones the way the last one was: a style's wish is
-- kept (ExtState "midi dock") and applied now if an editor is open, else when one is next active while the picker is open.
function M.midi_docked()
  local want = reaper.GetExtState(M.SECTION, "midi dock")
  if want ~= "" then return want == "1" end
  local ed = reaper.MIDIEditor_GetActive()
  if ed then return reaper.DockIsChildOfDock(ed) >= 0 end
  return (M.ini_section(M.read(res .. "/reaper.ini") or "", "midiedit") or ""):match("\ndock=(%d)") == "1"
end
function M.apply_midi_dock()
  local want = reaper.GetExtState(M.SECTION, "midi dock")
  if want == "" then return end
  local ed = reaper.MIDIEditor_GetActive()
  if not ed then return end
  if (reaper.DockIsChildOfDock(ed) >= 0) ~= (want == "1") then reaper.MIDIEditor_OnCommand(ed, 40018) end -- (Options: Toggle window docking)
  reaper.DeleteExtState(M.SECTION, "midi dock", true)
end
function M.want_midi_dock(on) reaper.SetExtState(M.SECTION, "midi dock", on and "1" or "0", true); M.apply_midi_dock() end
function M.file_name(s) return (tostring(s):gsub('[/\\:%*%?"<>|%c%$`]', "-"):gsub("^%.+", "")) end -- (a name as a safe file name)
function M.log(msg) -- ReaPersona/errors.log: what went wrong, for fixing it
  local f = io.open(M.here .. "/errors.log", "a")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S ") .. tostring(msg) .. "\n"); f:close() end
end

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
        if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(j + 2, j + 5), 16) or 63); j = j + 6
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
      if s:sub(i, i) == (obj and "}" or "]") then i = i + 1; return obj and setmetatable(t, M.OBJECT) or t end
      local n = 0
      if obj then setmetatable(t, M.OBJECT) end -- (so it's written back as {} even when empty)
      while true do
        if obj then ws(); local k = str(); ws(); i = i + 1; t[k] = val()
        else local v = val(); if v ~= nil then n = n + 1; t[n] = v end end -- (a null in a list is left out, not a hole that cuts it short)
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
    if getmetatable(v) == M.OBJECT and next(v) == nil then return "{}" end
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
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    local i = math.tointeger(v)
    return i and string.format("%d", i) or string.format("%.14g", v)
  elseif t == "boolean" then return tostring(v) end
  return "null"
end

-- ---------------------------------------------------------------- styles
-- Your files (user_styles.json, presets.json, user_themes.json): one that doesn't parse (a hand edit, a crash) is copied aside and
-- never written over, so saving one new item can't wipe out the rest.
local bad = {}
function M.load_json(p) -- -> the decoded table ({} when the file isn't there), or nil when it doesn't parse
  local t = M.read(p)
  if not t then return {} end
  local ok, d = pcall(M.json_decode, t)
  if ok and type(d) == "table" then bad[p] = nil; return d end
  if not bad[p] then
    bad[p] = true
    local f = io.open(p .. ".bad-" .. os.date("%Y%m%d-%H%M%S"), "wb"); if f then f:write(t); f:close() end
    M.log(p .. " doesn't parse: kept a copy next to it, and nothing writes over it until it's fixed")
  end
end
function M.save_json(p, d) -- -> true, or nil + why
  if bad[p] then return nil, (p:match("[^/]+$") or p) .. " doesn't parse, so it isn't written over (a copy is next to it)" end
  if not M.write(p, M.json_encode(d) .. "\n") then return nil, "couldn't write " .. (p:match("[^/]+$") or p) end
  return true
end
local USERS = M.here .. "/user_styles.json"
local function load(p) local d = M.load_json(p); return d and d.styles or {} end
M.styles_json = M.load_json(M.here .. "/styles.json") or {} -- (parsed once: the styles, the theme catalog and the theme recipes)
M.styles = M.styles_json.styles or {}
for _, st in ipairs(load(USERS)) do st.user = true; M.styles[#M.styles + 1] = st end -- (imported/shared styles)
function M.new_id(prefix) -- a style/preset id nothing has yet
  local n, id = 0, prefix .. os.time()
  while M.by_id(id) do n = n + 1; id = prefix .. os.time() .. "_" .. n end
  return id
end
local function save_user_style(st) -- add (or replace) a style of yours in user_styles.json and the list. -> st, or nil + why
  local users = load(USERS)
  if bad[USERS] then return nil, "user_styles.json doesn't parse, so it isn't written over (a copy is next to it)" end
  for n = #users, 1, -1 do if users[n].id == st.id then table.remove(users, n) end end
  st.user = nil
  local out = st
  if st.keys_from then out = {}; for k, v in pairs(st) do out[k] = v end; out.keys, out.midi_keys, out.alt = nil, nil, nil end
  users[#users + 1] = out
  local ok, why = M.save_json(USERS, { styles = users })
  st.user = true
  if not ok then return nil, why end
  for n = #M.styles, 1, -1 do if M.styles[n].id == st.id then table.remove(M.styles, n) end end
  M.styles[#M.styles + 1] = st
  M.stubs_stale = true -- (its "use" action gets written next time the picker opens)
  return st
end
M.save_user_style = save_user_style -- (for scripts: a built persona with a key or two added by hand)
M.presets = {} -- (your saved presets: filled below, after the feel code)
function M.by_id(id)
  for _, st in ipairs(M.styles) do if st.id == id then return st end end
  for _, st in ipairs(M.presets) do if st.id == id then return st end end
end
function M.resolve_keys(st) -- a persona on one DAW's shortcut layer: that DAW's keys, MIDI keys and layer
  local src = st.keys_from and M.by_id(st.keys_from)
  if src and src ~= st then st.keys, st.midi_keys, st.alt = src.keys, src.midi_keys, src.alt or 0 end
  st.keys, st.midi_keys = st.keys or {}, st.midi_keys or {}
end
for _, st in ipairs(M.styles) do if st.keys_from then M.resolve_keys(st) end end -- (Builder personas on one DAW's shortcut layer)
M.scripts = (function() local t = M.read(M.here .. "/scripts.json"); local ok, d = pcall(M.json_decode, t or "{}"); return ok and d or {} end)()
M.scripts.main, M.scripts.midi = setmetatable(M.scripts.main or {}, M.OBJECT), setmetatable(M.scripts.midi or {}, M.OBJECT)

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
-- (kept as one line, entries joined by ";;": REAPER keeps only the first line of a multi-line ExtState across a restart. Older
-- versions joined them with newlines, which still read.)
local function orig_list() local t = {}; for l in reaper.GetExtState(M.SECTION, "orig"):gsub(";;", "\n"):gmatch("[^\r\n]+") do t[#t + 1] = l end return t end

-- Docked windows. REAPER has no API to dock its own windows, but the Media Explorer has "Dock Media Explorer in Docker" (its own section,
-- sent to its window) and Dock_UpdateDockID picks the docker it goes into. Each step needs REAPER's message loop between, so it runs deferred.
local WINDOWS = { explorer = { show = 50124, title = "Media Explorer", dock = 40008, ident = "explorer", name = "Media Explorer" },
  -- (the mixer docks with a main action, and reaper.ini keeps its docked state as mixwnd_dock in [REAPER])
  mixer = { show = 40078, title = "Mixer", main_dock = 40083, ident = "mixer", name = "Mixer", ini = "mixwnd_dock" } }
M.WINDOWS = WINDOWS
local SIDES = { bottom = 0, left = 1, top = 2, right = 3 }
local function docker_at(side) -- the first docker REAPER keeps on that side of the main window, or nil
  local want = SIDES[side]
  if not want then return nil end
  for i = 0, 15 do if reaper.DockGetPosition(i) == want then return i end end
end
M.docker_at = docker_at
-- No docker on that side yet: take a spare one (nothing docked in it, no settings of its own) and, once the window is in it, send it
-- to that side with "Docker: Show in <side> of main window" (41598 + side), which acts on the focused window's docker. The same
-- spare is reused next time (ExtState "docker <side>"); left empty, REAPER doesn't show it.
local function spare_docker(side)
  local kept = tonumber(reaper.GetExtState(M.SECTION, "docker " .. side))
  if kept and reaper.DockGetPosition(kept) == SIDES[side] then return kept end
  local t = M.read(res .. "/reaper.ini") or ""
  local used = {}
  for n in t:gmatch("\ndocker[sm][eo][ld][e]?(%d+)=") do used[tonumber(n)] = true end -- (dockersel<N>, dockermode<N>)
  for n in (M.ini_section(t, "REAPERdockpref") or ""):gmatch("=%S+ (%d+)") do used[tonumber(n)] = true end
  for i = 15, 1, -1 do
    if not used[i] and reaper.DockGetPosition(i) == 0 then reaper.SetExtState(M.SECTION, "docker " .. side, tostring(i), true); return i end
  end
end
M.spare_docker = spare_docker
function M.ini_section(t, name) -- the body of [name] in an ini text (up to the next line starting with "["), or nil
  local s = t:find("[" .. name .. "]", 1, true)
  if not s then return nil end
  local e = t:find("\n%[", s + 1)
  return t:sub(s + #name + 2, e or #t)
end
local function ini_window(w) -- what reaper.ini last saved: docked?, and its docker preference
  local t = M.read(res .. "/reaper.ini") or ""
  local pref = tonumber((M.ini_section(t, "REAPERdockpref") or ""):match("\n" .. WINDOWS[w].ident .. "=%S+ (%d+)") or "") or 0
  local docked = WINDOWS[w].ini and (M.ini_section(t, "REAPER") or ""):match("\n" .. WINDOWS[w].ini .. "%s*=%s*(%d)") == "1"
    or (M.ini_section(t, "reaper_" .. w) or ""):match("\ndocked=(%d)") == "1"
  return docked, pref
end
local jobs, busy, pending = {}, false, {}
local function pump()
  local job = jobs[1]
  if not job then busy = false; return end
  if reaper.time_precise() < (job.at or 0) then return reaper.defer(pump) end
  job.n = (job.n or 0) + 1
  local ok, again = pcall(job.step)
  if not ok then M.log("window move: " .. tostring(again)) end
  if ok and again and job.n < 24 then job.at = reaper.time_precise() + 0.2
  else table.remove(jobs, 1); if job.done then job.done() end end
  reaper.defer(pump)
end
local function later(step, done) jobs[#jobs + 1] = { step = step, done = done }; if not busy then busy = true; reaper.defer(pump) end end
function M.busy() return busy end
-- Put a window where wanted: { shown = bool, docker = index or nil for a floating window, pref = docker preference to leave }.
local function move_window(w, want)
  local W = WINDOWS[w]
  if not (W and reaper.JS_Window_OnCommand and reaper.Dock_UpdateDockID) then return end
  local token = {}
  pending[w] = { want = want, token = token } -- (until it's there, this is where the window "is", for the next style's snapshot)
  later(function() -- (returns true: not there yet, try again in a moment)
    if reaper.GetToggleCommandState(W.show) ~= 1 then reaper.Main_OnCommand(W.show, 0); return true end
    local h = reaper.JS_Window_Find(W.title, true)
    if not h then return true end
    local d = reaper.DockIsChildOfDock(h)
    local function toggle_dock() if W.main_dock then reaper.Main_OnCommand(W.main_dock, 0) else reaper.JS_Window_OnCommand(h, W.dock) end end
    if want.docker and d ~= want.docker then
      if d < 0 then reaper.Dock_UpdateDockID(W.ident, want.docker) end
      toggle_dock() -- (in the wrong docker: out first, then in)
      return true
    elseif not want.docker and d >= 0 then toggle_dock(); return true end
    if want.side and want.docker and reaper.DockGetPosition(want.docker) ~= SIDES[want.side] then -- (a spare docker: to its side)
      reaper.JS_Window_SetFocus(h)
      reaper.Main_OnCommand(41598 + SIDES[want.side], 0)
      return true
    end
    if want.pref then reaper.Dock_UpdateDockID(W.ident, want.pref) end
    if not want.shown then reaper.Main_OnCommand(W.show, 0) end
  end, function() if pending[w] and pending[w].token == token then pending[w] = nil end end)
end
local function window_now(w) -- -> "d|w|shown|docker,pref" as it is now (docker -1 = floating)
  local W = WINDOWS[w]
  local docked, pref = ini_window(w)
  local p = pending[w]
  if p then return "d|" .. w .. "|" .. (p.want.shown and 1 or 0) .. "|" .. (p.want.docker or -1) .. "," .. (p.want.pref or pref) end
  local shown = reaper.GetToggleCommandState(W.show) == 1
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
    local ok, err = pcall(function()
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
    elseif kind == "x" and M.COLOUR_KEY[a] then -- (a colour setting the persona brought: yours back)
      local was = b:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)
      if was == "" then reaper.DeleteExtState(M.SECTION, a, true) else reaper.SetExtState(M.SECTION, a, was, true) end
    elseif kind == "e" then -- (the MIDI editor's docking)
      M.want_midi_dock(a == "1")
    elseif kind == "c" then -- (a choice: its "set" action, run)
      local id = cmd_id(tonumber(a) or a)
      if id ~= 0 then reaper.Main_OnCommand(id, 0) end
    elseif kind == "r" and a == "none" then -- (the transport floated or was hidden)
      if b == "0" and reaper.GetToggleCommandState(40260) == 1 then reaper.Main_OnCommand(40260, 0) end
      if c == "0" and reaper.GetToggleCommandState(40259) == 1 then reaper.Main_OnCommand(40259, 0) end
    elseif kind == "r" then -- (one of a set of options was on: turn it back on)
      local id = cmd_id(tonumber(a) or a)
      if id ~= 0 and reaper.GetToggleCommandState(id) ~= 1 then reaper.Main_OnCommand(id, 0) end
    end
    end)
    if not ok then M.log("put back " .. list[n] .. ": " .. tostring(err)) end
  end
  reaper.SetExtState(M.SECTION, "orig", "", true)
end
-- Which parts of a persona's feel you let personas change (Settings). All on by default, so each persona does what its DAW does
-- (Pro Tools, FL Studio and Cubase keep the mixer in its own window); switch one off to keep your own way.
M.ASPECTS = {
  { "mixer_dock", "Show, hide, dock or undock the mixer as the DAW opens (most open on their edit window; Pro Tools, FL and Cubase keep the mixer in its own window)", true, "Mixer" },
  { "mixer_layout", "Mixer layout: master on the left or right, insert and send slots", true, "Mixer layout" },
  { "transport", "Where the transport sits", true, "Transport position" },
  { "browser", "Where the Media Explorer docks", true, "Media Explorer" },
  { "toolbar", "The DAW's toolbar in place of your main toolbar", true, "Toolbar" },
  { "mouse", "Mouse drags and clicks (Smart Tool and so on; the wheel is part of the shortcuts)", true, "Mouse drags and clicks" },
  { "settings", "Snap, ripple, follow-playhead, the loop range and overlapping clips", true, "Snap, ripple and loop" },
  { "editor", "Dock the MIDI editor in the main window, or let it float", true, "MIDI editor docking" },
}
function M.aspect_on(a)
  local v = reaper.GetExtState(M.SECTION, "aspect " .. a)
  if v ~= "" then return v == "1" end
  for _, x in ipairs(M.ASPECTS) do if x[1] == a then return x[3] end end
  return true
end
function M.aspect_of(f)
  if f[1] == "midi_dock" then return "editor" end
  if f[1] == "dock" then return f[2] == "mixer" and "mixer_dock" or "browser" elseif f[1] == "radio" then return "transport" elseif f[1] == "switch" then return "toolbar"
  elseif f[1] == "mouse" then return "mouse"
  elseif f[1] == "toggle" then
    if f[2] == 40083 or f[2] == 40078 then return "mixer_dock" end
    if f[2] == 40389 or f[2] == 40549 or f[2] == 40557 then return "mixer_layout" end
  end
  return "settings"
end
local function apply_feel(st, windows_left, as_base) -- (as_base: your own look under every persona, so nothing kept to put back)
  local list = {}
  windows_left = windows_left or {}
  local function save() if not as_base then reaper.SetExtState(M.SECTION, "orig", table.concat(list, ";;"), true) end end -- (after every entry: a switch cut short can still be put back)
  local moves = {}
  local function wanted(f) return as_base or M.aspect_on(M.aspect_of(f)) end -- (the aspect switches are about personas, not your look)
  for _, f in ipairs(st.feel or {}) do if f[1] == "dock" and wanted(f) then moves[f[2]] = true end end
  for w, line in pairs(windows_left) do -- (windows the last style moved and this one doesn't: put back first, so this style's mixer
    if not moves[w] then window_back(line); windows_left[w] = nil end -- shown/hidden comes after, not under, the move back)
  end
  for _, f in ipairs(st.feel or {}) do
    local ok, err = pcall(function()
    if not wanted(f) then return end
    if f[1] == "dock" and WINDOWS[f[2]] and reaper.JS_Window_OnCommand then
      local d, made = f[3] ~= "float" and docker_at(f[3]) or nil, nil
      if f[3] ~= "float" and not d then d = spare_docker(f[3]); made = d and f[3] end -- (no docker on that side yet: one is set up)
      if f[3] ~= "float" and not d then return end -- (no spare docker either: the window stays where it is)
      list[#list + 1] = windows_left[f[2]] or window_now(f[2]) -- (the original from before any style, if the last style moved it)
      windows_left[f[2]] = nil
      move_window(f[2], { shown = f[4] == 1, docker = d, side = made })
    elseif f[1] == "toggle" then
      local function set()
        local id = cmd_id(f[2])
        local now = id ~= 0 and reaper.GetToggleCommandState(id) or -1
        if now >= 0 then
          list[#list + 1] = "t|" .. tostring(f[2]) .. "|" .. now
          if now ~= f[3] then reaper.Main_OnCommand(id, 0) end
        end
      end
      -- (the mixer shown or docked waits behind window moves still going, such as the last persona's mixer being put back: run
      -- now, the move would undo it, and what it was would be read mid-move)
      if (f[2] == 40078 or f[2] == 40083) and busy then later(function() set(); save() end) else set() end
    elseif f[1] == "switch" then -- ["switch", command, command that undoes it, what]: no on/off state to read (main toolbar contents)
      local id = cmd_id(f[2])
      local slot = type(f[2]) == "number" and ((f[2] >= 42729 and f[2] <= 42744 and ("Floating toolbar " .. (f[2] - 42729 + 17)))
        or (f[2] >= 41956 and f[2] <= 41959 and ("Floating MIDI toolbar " .. (f[2] - 41956 + 5))))
      if slot and not M.toolbar_installed(slot) then id = 0 end -- (its toolbar isn't installed here: an empty one would replace yours)
      if id ~= 0 then reaper.Main_OnCommand(id, 0); list[#list + 1] = "s|" .. tostring(f[3]) .. "|" end
    elseif f[1] == "radio" then -- ["radio", {options}, wanted, what]: options where at most one is on (the transport's position)
      local was
      for _, c in ipairs(f[2]) do
        local id = cmd_id(c)
        if id ~= 0 and reaper.GetToggleCommandState(id) == 1 then was = "r|" .. tostring(c) .. "|1"; break end
      end
      -- (none on: the transport floats or is hidden. Kept as "docked to the main window" and "visible", to put back)
      list[#list + 1] = was or ("r|none|" .. reaper.GetToggleCommandState(40260) .. "|" .. reaper.GetToggleCommandState(40259))
      local id = cmd_id(f[3])
      if id ~= 0 and reaper.GetToggleCommandState(id) ~= 1 then reaper.Main_OnCommand(id, 0) end
    elseif f[1] == "choice" then -- ["choice", {options}, wanted, what]: a REAPER option with several settings (ripple, ruler)
      for _, c in ipairs(f[2]) do
        local id = cmd_id(c)
        if id ~= 0 and reaper.GetToggleCommandState(id) == 1 then list[#list + 1] = "c|" .. tostring(c) .. "|"; break end
      end
      local id = cmd_id(f[3]) -- (these are "set" actions: run every time, as two of the ruler's can read on at once)
      if id ~= 0 then reaper.Main_OnCommand(id, 0) end
    elseif f[1] == "midi_dock" then -- ["midi_dock", 1 docked / 0 floating, what]
      list[#list + 1] = "e|" .. (M.midi_docked() and 1 or 0) .. "|"
      M.want_midi_dock(f[2] == 1)
    elseif f[1] == "mouse" and reaper.SetMouseModifier and M.for_os(f[2]) then -- ("mac:MM_CTX_ITEM": only on a Mac)
      local ctx = M.for_os(f[2])
      list[#list + 1] = "m|" .. ctx .. "|" .. f[3] .. "|" .. reaper.GetMouseModifier(ctx, f[3], "")
      reaper.SetMouseModifier(ctx, f[3], f[4])
    end
    end)
    if not ok then M.log("apply " .. tostring(st.id) .. " " .. tostring(f[1]) .. " " .. tostring(f[2]) .. ": " .. tostring(err)) end
    save()
  end
  for _, line in pairs(windows_left) do window_back(line) end -- (one this style meant to move but couldn't, no docker for it: put back)
  if st.colours then -- (its colour look becomes yours while it's in use)
    for _, k in ipairs(M.COLOUR_KEYS) do
      local v = st.colours[k]
      if v then
        list[#list + 1] = "x|" .. k .. "|" .. (reaper.GetExtState(M.SECTION, k):gsub(".", function(ch) return string.format("%02x", ch:byte()) end))
        reaper.SetExtState(M.SECTION, k, v, true)
      end
    end
  end
  save()
end
-- what a mouse entry is set to now matches the style? (for the picker's "not applied" warnings)
function M.mouse_ok(f) local c = M.for_os(f[2]); return not c or (reaper.GetMouseModifier and reaper.GetMouseModifier(c, f[3], "") ~= "") end

-- ---------------------------------------------------------------- presets: the style in use, its theme and how everything is set now
-- A preset keeps the style's keys (same shortcut layer, MIDI keys and toolbar) and records the theme plus every setting and mouse
-- behaviour any style touches, as they are when you save it. In presets.json; it's used like a style, and put back the same way.
local PRESETS = M.here .. "/presets.json"
local EXTRA_TOGGLES = { 40389, 40549, 40557, 40036 } -- (mixer master on the right, inserts, sends; auto-scroll: shown in the picker too)
local function action_name(id)
  local s = reaper.CF_GetCommandText and reaper.CF_GetCommandText(0, id)
  return ((type(s) == "string" and s or ""):gsub("^[^:]+: ", ""))
end
-- ---------------------------------------------------------------- colours with a persona (5.20)
-- The colour look Themes > Colours keeps (colours.lua): each one ExtState text, JSON. A persona, preset or workflow can carry them
-- (st.colours = { [key] = text }): switching to it makes them your current look (put back when you switch away), and a project its
-- workflow sets up gets its tracks and regions coloured in it.
M.COLOUR_KEYS = { "colour look", "colour kinds", "colour folders", "colour sections", "colour itemkinds" }
local COLOUR_KEY = {}
for _, k in ipairs(M.COLOUR_KEYS) do COLOUR_KEY[k] = true end
M.COLOUR_KEY = COLOUR_KEY -- (restore_feel, above, reads it through M)
function M.colours_now() -- -> the colour set in use here, or nil when no look has been picked yet
  if reaper.GetExtState(M.SECTION, "colour look") == "" then return nil end
  local set = {}
  for _, k in ipairs(M.COLOUR_KEYS) do local v = reaper.GetExtState(M.SECTION, k); if v ~= "" then set[k] = v end end
  return set
end
function M.safe_colours(c) -- a colour set from a file or another computer: only its known keys, each JSON text of an object (pure)
  if type(c) ~= "table" then return nil end
  local out, any = {}, false
  for k, v in pairs(c) do
    if type(v) == "string" then v = v:gsub("\r?\n%s*", "") end -- (one line, as ExtState keeps it)
    if COLOUR_KEY[k] and type(v) == "string" and #v < 20000 and not v:find("%c") then
      local ok, d = pcall(M.json_decode, v)
      if ok and type(d) == "table" then out[k] = v; any = true end
    end
  end
  return any and out or nil
end
function M.colours_label(c) -- "Colours: Gradient in Sunset" (pure)
  local ok, look = pcall(M.json_decode, type(c) == "table" and c["colour look"] or "")
  if not (ok and type(look) == "table") then return "Colours" end
  local names = { gradient = "Gradient", folders = "By folder", instrument = "By instrument", stripes = "Stripes", rainbow = "Rainbow", confetti = "Confetti" }
  local s = names[look.scheme] or tostring(look.scheme or "?")
  local uses = look.scheme == "gradient" or look.scheme == "folders" or look.scheme == "stripes"
  return "Colours: " .. s .. (uses and look.palette and (" in " .. tostring(look.palette)) or "")
end
local colours_mod
function M.colours() -- the colour module (colours.lua), loaded once
  if not colours_mod then colours_mod = assert(loadfile(M.here .. "/colours.lua"))(M) end
  return colours_mod
end
function M.safe_starts(list) -- (pure) -> { {name, command} } with only named commands
  local out = {}
  for _, s in ipairs(type(list) == "table" and list or {}) do
    if type(s) == "table" and type(s[2]) == "string" and s[2]:match("^_[%w_]+$") and #out < 64 then
      -- (where ReaPack got it, 5.24: a repository name and https address, and the package, so another computer can offer it)
      local src = type(s[3]) == "table" and s[3]
      if src and not (type(src.repo) == "string" and src.repo:match("^%w[%w %-%._()]*$") and type(src.url) == "string" and src.url:match("^https://[^%s\"'|]+$")
                      and type(src.pkg) == "string" and src.pkg ~= "" and not src.pkg:find("%c")) then src = nil end
      out[#out + 1] = { (tostring(s[1] or s[2]):gsub("%c", " ")), s[2], src and { repo = src.repo, url = src.url, pkg = src.pkg } or nil }
    end
  end
  return out
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
  st.colours = M.safe_colours(p.colours)
  if st.colours then st.description = st.description .. " " .. M.colours_label(st.colours) .. "." end
  st.starts = M.safe_starts(p.starts)
  if #st.starts > 0 then
    local n = {}; for _, s in ipairs(st.starts) do n[#n + 1] = s[1] end
    st.description = st.description .. " Starts with REAPER: " .. table.concat(n, ", ") .. "."
  end
  if type(p.project) == "table" then -- (a workflow: a new project's sample rate and starter tracks, or a whole project template)
    st.project = { srate = tonumber(p.project.srate) or 0, tracks = type(p.project.tracks) == "string" and p.project.tracks or "",
      tracks_name = tostring(p.project.tracks_name or ""), wset = tonumber(p.project.wset) or 0,
      template = type(p.project.template) == "string" and p.project.template ~= "" and p.project.template or nil, template_name = p.project.template_name and tostring(p.project.template_name) or nil }
    if st.project.template then st.description = st.description .. " A new project with it starts as " .. (st.project.template_name or "its project template") .. "."
    else
      st.description = st.description .. " A new project with it gets " .. ((st.project.srate > 0) and (M.khz(st.project.srate)) or "its sample rate") ..
        (st.project.tracks ~= "" and (" and " .. st.project.tracks_name) or "") .. "."
    end
  end
  return st
end
local function load_presets()
  local d = M.load_json(PRESETS)
  local list = d and d.presets or {}
  M.presets = {}
  for _, p in ipairs(list) do if p.id and p.name then M.presets[#M.presets + 1] = M.preset_style(p) end end
  return list
end
load_presets()
function M.project_now(whole) -- this project as a workflow's project part: its sample rate and its tracks (FX and routing, no items);
  -- whole: the whole project as a template too (its recording and render settings, tempo, markers...: 5.13)
  local text, n = M.selected_tracks_text()
  local sr = math.floor(reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) + 0.5)
  if reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false) ~= 1 then local _, d = reaper.GetAudioDeviceInfo("SRATE"); sr = math.floor((tonumber(d) or sr) + 0.5) end
  local pn = reaper.GetProjectName(0, ""):gsub("%.[Rr][Pp][Pp]$", "")
  local pj = { srate = sr, tracks = n > 0 and text or "", tracks_name = n > 0 and (n .. " track" .. (n == 1 and "" or "s") .. " from " .. (pn ~= "" and pn or "an unsaved project")) or "", wset = 0 }
  if whole then
    local t = M.project_template_text()
    if t then
      local all = reaper.CountTracks(0)
      pj.template, pj.tracks = t, ""
      pj.template_name = (pn ~= "" and pn or "this project") .. " (" .. all .. " track" .. (all == 1 and "" or "s") .. ", its recording and render settings, tempo and markers)"
    end
  end
  return pj, n
end
local function feel_now(base) -- every setting, mouse behaviour and window place any style touches, as it is now (a preset's feel)
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
      elseif f[1] == "mouse" and reaper.GetMouseModifier and M.for_os(f[2]) and not seen[f[2] .. f[3]] then
        seen[f[2] .. f[3]] = true
        feel[#feel + 1] = { "mouse", f[2], f[3], reaper.GetMouseModifier(M.for_os(f[2]), f[3], ""), "As you had it: " .. f[#f] }
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
  return feel
end
M.feel_now = feel_now
function M.save_preset(name, with_project) -- -> the new preset (as a style). with_project: this project's rate and tracks for new projects
  local base = M.current()
  if base.preset then base = M.by_id(base.base) or M.styles[1] end
  local feel = feel_now(base)
  local list = load_presets()
  local p = { id = M.new_id("preset_"), name = name, base = base.id, saved = os.date("%Y-%m-%d"), feel = feel,
              theme = M.loaded_theme() or M.theme_for(base), project = with_project and M.project_now(true) or nil, colours = M.colours_now(),
              starts = M.starts_now() }
  list[#list + 1] = p
  local ok, why = M.save_json(PRESETS, { presets = list })
  if not ok then return nil, why end
  load_presets()
  reaper.SetExtState(M.SECTION, "style", p.id, true) -- (it is what's in use now: switching away puts back what the style changed)
  return M.by_id(p.id)
end
-- A new user's own setup, kept as a persona before ReaPersona first changes anything (5.17), unless it's REAPER as it ships: then Base
-- REAPER already is it. Pure: the keymap, mouse and menu files' text, the theme in use, the settings now (feel_now) and Base REAPER's feel.
M.FACTORY_MOUSE = { MM_CTX_MIDI_NOTE_CLK = { mm_0 = "1 m", mm_4 = "2 m" } } -- (what a new REAPER 7.86 writes in reaper-mouse.ini besides [hasimported])
function M.stock_setup(kb, mouse, menu, theme, feel, base_feel)
  if ("\n" .. (kb or "")):find("\nKEY ") then return false end -- (a key of your own: REAPER's factory keys aren't written there)
  if (menu or ""):find("=", 1, true) then return false end -- (any entry: your own menus or toolbars; a new REAPER has no reaper-menu.ini)
  -- (a mouse behaviour that isn't what a new REAPER writes itself: its [hasimported] list and two MIDI note-click defaults. REAPER 7.86
  -- on Windows Sandbox and a clean Linux, 5.17.2)
  local section = ""
  for line in ((mouse or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    local s = line:match("^%[(.-)%]%s*$")
    if s then section = s
    else
      local k, v = line:match("^%s*([^=]-)%s*=%s*(.-)%s*$")
      if k and section ~= "hasimported" and (M.FACTORY_MOUSE[section] or {})[k] ~= v then return false end
    end
  end
  if theme and theme ~= "" and not theme:match("^Default_7") then return false end
  local now = {}
  for _, f in ipairs(feel or {}) do
    if f[1] == "toggle" then now["t" .. tostring(f[2])] = f[3]
    elseif f[1] == "radio" then now["r" .. table.concat(f[2], ",")] = f[3] end
  end
  for _, f in ipairs(base_feel or {}) do
    local k = f[1] == "toggle" and "t" .. tostring(f[2]) or f[1] == "radio" and "r" .. table.concat(f[2], ",") or nil
    if k and now[k] ~= nil and tostring(now[k]) ~= tostring(f[3]) then return false end
  end
  return true
end
function M.save_first_setup() -- -> the preset made, or nil when the setup is REAPER's own. Once per computer (ExtState "first setup")
  if reaper.GetExtState(M.SECTION, "first setup") ~= "" then return nil end
  reaper.SetExtState(M.SECTION, "first setup", "stock", true) -- (once, whatever happens below)
  local mine = M.by_id("my_reaper") or M.styles[1]
  local feel = feel_now(mine)
  local base = M.by_id("base_reaper")
  if M.stock_setup(M.read(res .. "/reaper-kb.ini"), M.read(res .. "/reaper-mouse.ini"), M.read(res .. "/reaper-menu.ini"), M.loaded_theme(), feel, base and base.feel) then return nil end
  local was = reaper.GetExtState(M.SECTION, "style")
  local ok, st = pcall(M.save_preset, "My REAPER as it was (" .. tostring(M.computer and M.computer() or "this computer") .. ")")
  reaper.SetExtState(M.SECTION, "style", was, true) -- (save_preset marks it in use: nothing has switched yet)
  if not ok or not st then M.log("first setup not saved: " .. tostring(st)); return nil end
  reaper.SetExtState(M.SECTION, "first setup", st.id, true)
  return st
end
-- Your look on every computer (5.21; James: "on mac the my reaper persona doesn't get my transport at the top and other things I've
-- changed in my default look ... import the same look and settings everything across devices"). My REAPER is whatever each computer
-- had, so one computer's look is kept as ExtState "my look" (one line of JSON: theme, and feel_now's layout, mixer, transport, snap and
-- mouse settings), which syncs and travels in setup files like any setting. Using My REAPER applies it as your own setup: not kept to
-- put back, so every persona sits on it and leaving one comes back to it.
M.LOOK_KEY = "my look"
function M.my_look() -- -> { theme, feel, from, saved } or nil (from a file or another computer: only what a persona could set)
  local ok, d = pcall(M.json_decode, reaper.GetExtState(M.SECTION, M.LOOK_KEY))
  if not ok or type(d) ~= "table" or type(d.feel) ~= "table" then return nil end
  return { theme = type(d.theme) == "string" and d.theme:match("[^/\\]+$") or nil, feel = M.safe_feel(d.feel), starts = M.safe_starts(d.starts),
           from = type(d.from) == "string" and d.from:gsub("%c", " ") or nil, saved = type(d.saved) == "string" and d.saved:gsub("%c", " ") or nil }
end
function M.save_my_look() -- -> the look, or nil + why. Only from My REAPER: a persona's settings aren't your look
  if (M.current() or {}).id ~= "my_reaper" then return nil, "switch to My REAPER first: your look is what you have there" end
  local feel = {}
  for _, f in ipairs(feel_now(M.by_id("my_reaper") or M.styles[1])) do
    if f[1] ~= "switch" and not (f[1] == "mouse" and (f[4] or "") == "") then feel[#feel + 1] = f end -- (a mouse context left at REAPER's default: each computer's own)
  end
  local look = { theme = M.loaded_theme(), feel = feel, starts = M.starts_now(), from = M.computer(), saved = os.date("%Y-%m-%d %H:%M") }
  reaper.SetExtState(M.SECTION, M.LOOK_KEY, (M.json_encode(look):gsub("\r?\n%s*", "")), true) -- (one line: REAPER keeps only the first across restarts)
  return look
end
function M.forget_my_look() reaper.SetExtState(M.SECTION, M.LOOK_KEY, "{}", true) end -- (not deleted: "{}" is a change, so your other computers forget it too)
function M.look_label(look) -- "Reapertips Theme, transport at the top of the main window, mixer docked bottom, from JAMES-MAIN on ..." (pure)
  if not look then return nil end
  local bits = { look.theme and (look.theme:gsub("%.ReaperTheme%a*$", "")) or "your theme" }
  for _, f in ipairs(look.feel or {}) do
    if f[1] == "radio" or f[1] == "dock" then bits[#bits + 1] = tostring(f[#f]) end
  end
  for _, s in ipairs(look.starts or {}) do bits[#bits + 1] = s[1] .. " at start" end
  return table.concat(bits, ", ") .. " (" .. #(look.feel or {}) .. " settings" .. (look.from and (", from " .. look.from) or "") .. (look.saved and (", " .. look.saved) or "") .. ")"
end
-- Scripts REAPER starts with you (5.22; James: Chordbox and the adaptive grid were missing on the Mac, "make sure all of those save to
-- my personas as well, and work for other personas"). Your look and the personas you save keep the actions your __startup.lua runs (as
-- FTC Tools and others write them: "-- Start script: <name>" and Main_OnCommand(NamedCommandLookup(<command>))). Using one on a computer
-- that has the script registered adds its start line there and starts it if it's stopped. Only a command name travels, never code,
-- and nothing is removed: they're your scripts, so they keep running under every persona.
function M.starts_in(text) -- (pure) the actions a __startup.lua runs, named by the "-- Start script:" line above each
  local out, seen, vars, name = {}, {}, {}, nil
  for line in (text or ""):gmatch("[^\r\n]+") do
    name = line:match("^%s*%-%-%s*Start script:%s*(.-)%s*$") or name
    local var, v = line:match("^%s*local%s+([%w_]+)%s*=%s*['\"](_[%w_]+)['\"]")
    if var then vars[var] = v end
    local arg = line:find("Main_OnCommand", 1, true) and line:match("NamedCommandLookup%(%s*([^%)]-)%s*%)")
    if arg then
      local cmd = arg:match("^['\"](_[%w_]+)['\"]$") or vars[arg]
      if cmd and not seen[cmd] then seen[cmd] = true; out[#out + 1] = { name or cmd, cmd } end
      name = nil
    end
  end
  return M.safe_starts(out)
end
function M.script_paths(kb) -- (pure) reaper-kb.ini's script registrations: { [command without "_"] = path (relative to Scripts, or full) }
  local t = {}
  for c, p in (kb or ""):gmatch('\nSCR %d+ %d+ (%S+) "[^"\n]*" "([^"\n]+)"') do t[c] = t[c] or p end
  return t
end
function M.start_source(cmd, paths) -- -> { repo, url, pkg } when ReaPack installed the script, else nil
  if not (reaper.ReaPack_GetOwner and reaper.ReaPack_GetEntryInfo and reaper.ReaPack_GetRepositoryInfo) then return nil end
  local rel = (paths or {})[cmd:sub(2)]
  if not rel then return nil end
  local e = reaper.ReaPack_GetOwner(((rel:match("^%a:[\\/]") or rel:match("^/")) and rel) or (res .. "/Scripts/" .. rel))
  if not e then return nil end
  local ok, repo, _, pkg = reaper.ReaPack_GetEntryInfo(e)
  reaper.ReaPack_FreeEntry(e)
  local have, url = false, nil
  if ok then have, url = reaper.ReaPack_GetRepositoryInfo(repo) end
  return have and { repo = repo, url = url, pkg = pkg } or nil
end
function M.starts_now() -- the scripts this computer starts, each with where ReaPack got it
  local list = M.starts_in(M.read(M.startup_path()) or "")
  local paths = M.script_paths("\n" .. (M.read(res .. "/reaper-kb.ini") or ""))
  for _, s in ipairs(list) do s[3] = M.start_source(s[2], paths) end
  return M.safe_starts(list)
end
function M.ensure_starts(list) -- -> names added to __startup.lua, names started now, the ones not installed here that ReaPack can get
  local added, started, add, missing = {}, {}, {}, {}
  local path = M.startup_path()
  local text = M.read(path) or ""
  local have = {}
  for _, s in ipairs(M.starts_in(text)) do have[s[2]] = true end
  for _, s in ipairs(M.safe_starts(list)) do
    local id = reaper.NamedCommandLookup(s[2])
    if id ~= 0 then -- (registered here; one that isn't comes with ReaPack's packages or your scripts, and is added next time)
      if not have[s[2]] then
        have[s[2]] = true
        add[#add + 1] = "\n-- Start script: " .. s[1] .. "\ndo\n  local cmd = '" .. s[2] .. "'\n  reaper.Main_OnCommand(reaper.NamedCommandLookup(cmd), 0)\nend\n"
        added[#added + 1] = s[1]
      end
      -- (only one that says it's off: these toggle, so running one that's on would stop it, and one with no state may not be a background script)
      if reaper.GetToggleCommandState(id) == 0 then reaper.Main_OnCommand(id, 0); started[#started + 1] = s[1] end
    elseif s[3] then missing[#missing + 1] = s end
  end
  if #add > 0 then
    M.write(path .. ".before-reapersona-starts", text) -- (your startup file as it was, once per change)
    M.write(path, text .. table.concat(add))
  end
  return added, started, missing
end
-- Mix and match: one style's keys (its shortcut layer and MIDI keys), another style's layout, toolbar and feel, any theme. -> the profile
function M.save_mix(name, keys_id, feel_id, theme)
  local list = load_presets()
  local p = { id = M.new_id("mix_"), name = name, base = keys_id, feel_from = feel_id, theme = theme, saved = os.date("%Y-%m-%d") }
  list[#list + 1] = p
  local ok, why = M.save_json(PRESETS, { presets = list })
  if not ok then return nil, why end
  load_presets()
  return M.by_id(p.id)
end
-- A preset as a file to give someone, and taking one in (its styles have to exist on that computer). -> true / the preset, or nil + why
function M.export_preset(id, path)
  for _, p in ipairs(load_presets()) do if p.id == id then return M.write(path, M.json_encode({ reapersona_preset = 1, preset = p }) .. "\n") end end
end
function M.import_preset(d)
  local p = d and d.preset
  if not (type(p) == "table" and type(p.name) == "string" and type(p.base) == "string") then return nil, "not a ReaPersona preset" end
  if not M.by_id(p.base) then return nil, "it's built on the persona '" .. p.base .. "', which isn't here" end
  if p.feel_from ~= nil and not (type(p.feel_from) == "string" and M.by_id(p.feel_from)) then return nil, "its layout comes from a persona that isn't here" end
  if p.theme ~= nil then p.theme = type(p.theme) == "string" and p.theme:match("[^/\\]+$") or nil end -- (a file name in ColorThemes, nothing more)
  p.feel = p.feel and M.safe_feel(p.feel)
  p.colours = M.safe_colours(p.colours)
  local list = load_presets()
  p.id = M.new_id(p.feel_from and "mix_" or "preset_")
  list[#list + 1] = p
  local ok, why = M.save_json(PRESETS, { presets = list })
  if not ok then return nil, why end
  load_presets()
  return M.by_id(p.id)
end
function M.delete_preset(id)
  local list = load_presets()
  for n = #list, 1, -1 do if list[n].id == id then table.remove(list, n) end end
  local ok, why = M.save_json(PRESETS, { presets = list })
  load_presets()
  return ok, why
end

-- ---------------------------------------------------------------- using a style
local function set_toggles(on_id)
  for _, st in ipairs(M.styles) do
    local id = cmd_id(M.scripts.main["use " .. st.id] or "")
    if id ~= 0 then reaper.SetToggleCommandState(0, id, st.id == on_id and 1 or 0); reaper.RefreshToolbar2(0, id) end
  end
end
function M.loaded_theme() -- the theme file in use, by the name you picked it by (REAPER names a loaded zip by its .ReaperTheme sidecar)
  local th = (reaper.GetLastColorThemeFile() or ""):gsub("\\", "/"):match("[^/]+$")
  if th and th:match("%.ReaperTheme$") and reaper.file_exists(M.themes_dir .. th .. "Zip") then th = th .. "Zip" end
  return th
end
function M.use(st)
  if not st then return end
  if reaper.GetExtState(M.SECTION, "style") == "" and st.id ~= "my_reaper" then M.save_first_setup() end -- (a new user's first switch: their setup kept first)
  st = M.layered(st) -- (the workflow in use, over it)
  if reaper.GetExtState(M.SECTION, "style") == "my_reaper" or reaper.GetExtState(M.SECTION, "style") == "" then
    local th = M.loaded_theme() -- (My REAPER's theme is whatever you had in it)
    if th then reaper.SetExtState(M.SECTION, "theme my_reaper", th, true) end
    local raw = reaper.GetLastColorThemeFile() or ""
    if raw:match("%.ReaperTheme$") and reaper.file_exists(raw .. "Zip") then raw = raw .. "Zip" end
    reaper.SetExtState(M.SECTION, "theme path my_reaper", raw, true)
  end
  reaper.PreventUIRefresh(1)
  local ok, err = pcall(function()
  reaper.Main_OnCommand(CLEAR, 0)
  if (st.alt or 0) > 0 then reaper.Main_OnCommand(TOGGLE_ALT + st.alt, 0) end
  local left = {}
  -- (REAPER keeps many options per project (snap, ripple, the mixer layout, the metronome...): what the last persona changed is put
  -- back in the project tab it was changed in, even after you've switched tabs)
  local now_p, was, back = reaper.EnumProjects(-1), reaper.GetExtState(M.SECTION, "orig project"), nil
  if was ~= "" and was ~= tostring(now_p) then
    for i = 0, 255 do
      local p = reaper.EnumProjects(i)
      if not p then break end
      if tostring(p) == was then back = now_p; reaper.SelectProjectInstance(p); break end
    end
  end
  restore_feel(left)
  if back then reaper.SelectProjectInstance(back) end
  local look = st.id == "my_reaper" and M.my_look()
  if look then -- (your look from wherever you saved it, as this computer's own setup; its theme when this computer has it)
    apply_feel({ id = "my look", feel = look.feel }, left, true)
    if look.theme and reaper.file_exists(M.themes_dir .. look.theme) then
      reaper.SetExtState(M.SECTION, "theme my_reaper", look.theme, true)
      reaper.SetExtState(M.SECTION, "theme path my_reaper", "", true)
    end
  end
  M.last_project_setup = M.apply_project(st) -- (a workflow's project first: a template loaded after the feel replaced its per-project options)
  apply_feel(st, left)
  M.starts_missing = {} -- (ones not installed here: the window offers them from ReaPack, and finishes the job once they are)
  for _, list in ipairs({ look and look.starts or {}, st.starts or {} }) do -- (your scripts that start with REAPER, kept running under any persona)
    local ok2, why, _, missing = pcall(M.ensure_starts, list)
    if not ok2 then M.log("starts: " .. tostring(why)) else for _, s in ipairs(missing or {}) do M.starts_missing[#M.starts_missing + 1] = s end end
  end
  if st.project and #M.last_project_setup == 0 and (tonumber(st.project.srate) or 0) + #(st.project.tracks or "") + #(st.project.template or "") > 0 and not M.fresh_project(0) then
    M.last_project_setup[#M.last_project_setup + 1] = "not its project setup (this project already has work in it: New project with it opens one)"
  end
  if st.project then pcall(M.start_following) end -- (watches for new projects to set up)
  reaper.SetExtState(M.SECTION, "orig project", tostring(reaper.EnumProjects(-1)), false)
  local th = M.theme_for(st)
  if not th and not (st.themes and st.themes[1]) then th = M.theme_for(M.by_id("my_reaper") or M.styles[1]) end -- (no theme of its own: yours)
  local full = st.id == "my_reaper" and reaper.GetExtState(M.SECTION, "theme path my_reaper") or ""
  if full ~= "" and reaper.file_exists(full) and not (th and reaper.file_exists(M.themes_dir .. th)) then reaper.OpenColorThemeFile(full); th = nil end
  if th and reaper.file_exists(M.themes_dir .. th) and th ~= M.loaded_theme() then
    reaper.OpenColorThemeFile(M.themes_dir .. th)
    local own = th:match("^ReaPersona %- (.+)%.ReaperThemeZip$") -- (a ReaPersona theme built outside REAPER: its Default 7 settings, once)
    if own and M.params_for_loaded and reaper.GetExtState(M.SECTION, "params " .. own) == "" then M.params_for_loaded(own); reaper.ThemeLayout_RefreshAll() end
  end
  reaper.SetExtState(M.SECTION, "style", st.id, true)
  M.write_midi_map(st)
  set_toggles(st.base or st.id)
  end)
  reaper.PreventUIRefresh(-1)
  if not ok then M.log("use " .. tostring(st.id) .. ": " .. tostring(err)) end
  reaper.UpdateArrange()
end
function M.use_id(id) M.use(M.by_id(id)) end
function M.next_style() -- (from a preset or mix: the style after the one it's built on)
  local cur = M.current()
  local at = cur.preset and M.by_id(cur.base) or cur
  for n, st in ipairs(M.styles) do if st == at then return M.use(M.styles[n % #M.styles + 1]) end end
  M.use(M.styles[1])
end
-- REAPER doesn't keep the shortcut override across a restart (the theme, toggles and mouse behaviours it does keep): put it back.
function M.restore_last()
  local st = M.current()
  if st and (st.alt or 0) > 0 and M.active_alt() ~= st.alt then reaper.Main_OnCommand(CLEAR, 0); reaper.Main_OnCommand(TOGGLE_ALT + st.alt, 0) end
  M.write_midi_map(st) -- (script command ids can change between runs)
  set_toggles(st and (st.base or st.id))
  if M.watch_on() then M.start_following() end -- (a persona per project, or a workflow's new projects: the action that follows project tabs)
  pcall(M.upgrade_startup)
  -- (what your other computers changed while this one was off: 10 seconds after the start, so REAPER isn't held up opening)
  local at = reaper.time_precise() + 10
  local function later() if reaper.time_precise() < at then return reaper.defer(later) end M.sync_tick() end
  reaper.defer(later)
end

-- ---------------------------------------------------------------- MIDI editor keys
-- The MIDI editor has no shortcut layers, so each MIDI key a style uses is bound (by install_shortcuts.py) to a tiny script that
-- asks here what the style in use wants; with no style key it runs what that key did in your own keymap (midi_fallback.json).
local midi_names
local function midi_action(name)
  if not midi_names then
    if not reaper.CF_EnumerateActions then return nil end -- (SWS)
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
-- What each MIDI key runs for the style in use: { spec = { n = repeats, command, ... } }, commands as numbers or "_named" ids.
-- With no style key it's your own (midi_fallback.json); a fallback of "0" is a binding REAPER disabled when a script it pointed at
-- went away, not yours, so REAPER's default (midi_defaults.json) runs instead.
local function midi_plan(st)
  local fb = (M.load_json(M.here .. "/midi_fallback.json") or {})
  local defaults = (M.load_json(M.here .. "/midi_defaults.json") or {})
  local mine = {}
  for _, k in ipairs(st and st.midi_keys or {}) do mine[k[1]] = k end
  local plan = {}
  for _, s in ipairs(M.styles) do
    for _, k in ipairs(s.midi_keys or {}) do
      local spec = k[1]
      if not plan[spec] then
        local e = { n = 1 }
        local k2 = mine[spec]
        if k2 then
          e.n = k2[4] or 1
          for _, name in ipairs(type(k2[2]) == "table" and k2[2] or { k2[2] }) do
            e[#e + 1] = type(name) == "number" and name or midi_action(name) or ((name:sub(1, 1) == "_" and "" or "_") .. name)
          end
        else
          local c = fb[spec] and tostring(fb[spec].cmd or "")
          if not c or c == "" or c == "0" then c = defaults[spec] and tostring(defaults[spec]) end
          if c and c ~= M.scripts.midi[spec] and c ~= (M.scripts.midi[spec] or ""):sub(2) then -- (never this very script: it'd run itself forever)
            e[1] = tonumber(c) or ((c:sub(1, 1) == "_" and "" or "_") .. c)
          end
        end
        plan[spec] = e
      end
    end
  end
  return plan
end
function M.write_midi_map(st) -- midi_map.lua, which the MIDI key scripts read on every press (so a press doesn't load all of this)
  local plan, out = midi_plan(st), { "-- @noindex\n-- (written by ReaPersona when a persona is used: what each MIDI editor key runs now)\nreturn {" }
  for spec, e in pairs(plan) do
    local cmds = {}
    for _, c in ipairs(e) do cmds[#cmds + 1] = type(c) == "number" and string.format("%d", c) or string.format("%q", c) end
    out[#out + 1] = string.format("  [%q] = { n = %d, %s },", spec, e.n, table.concat(cmds, ", "))
  end
  out[#out + 1] = "}\n"
  return M.write(M.here .. "/midi_map.lua", table.concat(out, "\n"))
end
function M.midi_key(spec) -- (only when midi_map.lua is missing or lacks the key)
  local e = midi_plan(M.current())[spec]
  for _ = 1, e and e.n or 0 do
    for _, c in ipairs(e) do midi_run(type(c) == "number" and c or reaper.NamedCommandLookup(c)) end
  end
end

-- What REAPER's MIDI editor does on each key the styles use, by default (reaper-kb.ini only holds changes, so the installer can't see
-- these): written to midi_defaults.json, read by install_shortcuts.py for the My REAPER fallback. Run it before the MIDI keys are
-- installed (afterwards those keys show the ReaPersona scripts). -> how many keys had a default
function M.split_spec(spec) -- "Ctrl+Shift+L" -> "Ctrl+Shift", "L"; a key that is itself a plus ("+", "Num+", "Ctrl++") stays whole
  local body, plus = spec, ""
  if spec:sub(-1) == "+" then body, plus = spec:sub(1, -2), "+" end
  local cut = body:find("%+[^+]*$")
  if cut then return body:sub(1, cut - 1), body:sub(cut + 1) .. plus end
  return "", body .. plus
end
local MAC_MODS = { Cmd = "Ctrl", Command = "Ctrl", Opt = "Alt", Option = "Alt", Control = "Win" } -- (REAPER on macOS: Ctrl is Cmd)
local function canon(desc) -- "Shift+Ctrl+Up" / "Ctrl+Shift+Up" -> "Ctrl+Shift+Up"; REAPER's key names to styles.json's
  local rest, key = M.split_spec(desc)
  local mods = {}
  for m in rest:gmatch("[^+]+") do mods[MAC_MODS[m] or m] = true end
  key = ({ ["Page Up"] = "PgUp", ["Page Down"] = "PgDn", PageUp = "PgUp", PageDown = "PgDn", Del = "Delete", Ins = "Insert",
           Return = "Enter", Spacebar = "Space" })[key] or key
  local out = {}
  for _, m in ipairs({ "Ctrl", "Alt", "Shift", "Win" }) do if mods[m] then out[#out + 1] = m end end
  out[#out + 1] = key
  return table.concat(out, "+")
end
M.canon = canon
function M.midi_defaults()
  if not reaper.CF_EnumerateActions then return end -- (SWS)
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
  M.write(M.here .. "/midi_defaults.json", M.json_encode(setmetatable(found, M.OBJECT)) .. "\n")
  return n
end

-- ---------------------------------------------------------------- helper scripts (written and registered once, by the picker)
local function safe(spec) return (spec:gsub("[^%w]", function(c) return string.format("_%02X", c:byte()) end)) end
local STUBS = 7 -- (bump when the stubs below change, so they're written again. 4: the Actions list sorted once, M.ensure_scripts. 5: duplicate, gap, autopunch. 6: screen-reader menu. 7: notation editor)
local HEAD = '-- @noindex\n-- (made by ReaPersona)\nlocal p = debug.getinfo(1, "S").source:match("^@?(.*)[/\\\\]")\n'
local function stub(path, fn, arg) -- a one-line action: core.<fn>(arg), arg written as a Lua string literal
  return M.write(path, HEAD .. 'dofile(p .. "/../reapersona_core.lua").' .. fn .. "(" .. (arg and string.format("%q", arg) or "") .. ")\n")
end
local function midi_stub(path, spec) -- reads midi_map.lua (written when a style is used); loads the whole core only without it
  return M.write(path, HEAD .. "local spec = " .. string.format("%q", spec) .. "\n" ..
    'local ok, map = pcall(dofile, p .. "/../midi_map.lua")\nlocal k = ok and type(map) == "table" and map[spec]\n' ..
    'if not k then return dofile(p .. "/../reapersona_core.lua").midi_key(spec) end\n' ..
    "for _ = 1, k.n or 1 do\n  for _, c in ipairs(k) do\n    local id = type(c) == \"number\" and c or reaper.NamedCommandLookup(c)\n" ..
    "    if id ~= 0 then reaper.MIDIEditor_LastFocused_OnCommand(id, false) end\n  end\nend\n")
end
-- What scripts the styles need, and whether they're all registered. -> missing count
function M.scripts_missing()
  local n = (M.scripts.stubs ~= STUBS or M.stubs_stale) and 1 or 0
  for _, st in ipairs(M.styles) do
    if not M.scripts.main["use " .. st.id] and M.all_actions() then n = n + 1 end -- (out of the Actions list unless asked for: M.ensure_scripts)
    for _, k in ipairs(st.midi_keys or {}) do if not M.scripts.midi[k[1]] then n = n + 1 end end
  end
  return n
end
-- The Actions list for someone who isn't making shortcuts (James, 5.9.0: it listed 20 of ours): what the persona keys run (play from start,
-- memory location) and following projects stay; switching persona ("use <DAW>", next, restore last) is there when a key, a toolbar, a
-- mouse modifier or an SWS cycle action uses it, or with Settings > "Every ReaPersona action in REAPER's Actions list" (ExtState
-- "all actions"). Their ids come from their paths.
-- ReaPersona itself opens from the Actions list, Extensions > ReaPersona or View > ReaPersona (extension/reaper_menu.cpp in StudioSync).
function M.all_actions() return reaper.GetExtState(M.SECTION, "all actions") == "1" end
local function optional(name) return name == "next style" or name == "restore last style" or name:match("^use ") ~= nil end
-- (a mouse modifier (reaper-mouse.ini) or an SWS cycle action (S&M_Cyclaction.ini; older SWS kept them in S&M.ini) runs one by its id
-- too, and lost it when the trim took it out of the Actions list. Their ids sit after "=", ",", "|" or "!", so any non-word character
-- counts. Review, 5.9.4)
function M.ids_in(text) -- the "_RS..." ids a REAPER or SWS ini text runs -> { [id] = true } (pure)
  local t = {}
  for id in ("\n" .. (text or "")):gmatch("[^%w_](_RS%x+)") do t[id] = true end
  return t
end
local function used_ids() -- the "_RS..." ids a key, a toolbar, a mouse modifier or a cycle action runs
  local t = {}
  for _, f in ipairs({ "reaper-kb.ini", "reaper-menu.ini", "reaper-mouse.ini", "S&M_Cyclaction.ini", "S&M.ini" }) do
    for id in pairs(M.ids_in(M.read(res .. "/" .. f))) do t[id] = true end
  end
  return t
end
function M.ensure_scripts()
  reaper.RecursiveCreateDirectory(M.here .. "/actions", 0)
  reaper.RecursiveCreateDirectory(M.here .. "/midi_keys", 0)
  local main = { ["next style"] = { "next_style" }, ["restore last style"] = { "restore_last" }, ["memory location"] = { "memory_location" },
                 ["play from start"] = { "play_from_start" }, ["follow projects"] = { "follow_projects" },
                 ["duplicate to new track"] = { "duplicate_to_new_track" }, ["autopunch"] = { "autopunch" },
                 ["remove leaving a gap"] = { "without_ripple", "40312" }, ["cut leaving a gap"] = { "without_ripple", "40307" },
                 ["screen-reader menu"] = { "screen_reader_menu" }, ["notation editor"] = { "notation_editor" } }
  local names = {}
  for _, st in ipairs(M.styles) do main["use " .. st.id] = { "use_id", st.id }; local l = (st.short or st.name):lower(); names[l] = (names[l] or 0) + 1 end
  local todo, off, all, used = {}, {}, M.all_actions(), used_ids()
  for name, call in pairs(main) do
    local st = name:match("^use ") and M.by_id(name:sub(5))
    local label = st and ("use " .. (st.short or st.name) .. ((st.user and names[(st.short or st.name):lower()] > 1) and (" (" .. st.id .. ")") or "")) or name -- (yours named like another: its own file)
    local p = M.here .. "/actions/ReaPersona - " .. M.file_name(label) .. ".lua"
    stub(p, call[1], call[2])
    if not optional(name) or all or used[M.scripts.main[name] or ""] then todo[#todo + 1] = { 0, p, "main", name }
    else off[#off + 1] = { p, name } end
  end
  for n, o in ipairs(off) do -- (out of the Actions list: nothing runs it by its id)
    reaper.AddRemoveReaScript(false, 0, o[1], n == #off and #todo == 0)
    M.scripts.main[o[2]] = nil
  end
  local specs = {}
  for _, st in ipairs(M.styles) do for _, k in ipairs(st.midi_keys or {}) do specs[k[1]] = true end end
  for spec in pairs(specs) do
    local p = M.here .. "/midi_keys/ReaPersona MIDI key " .. safe(spec) .. ".lua"
    midi_stub(p, spec); todo[#todo + 1] = { MIDI_SEC, p, "midi", spec }
  end
  for n, t in ipairs(todo) do
    local id = reaper.AddRemoveReaScript(true, t[1], t[2], n == #todo)
    if id and id ~= 0 then M.scripts[t[3]][t[4]] = "_" .. reaper.ReverseNamedCommandLookup(id) end
  end
  M.scripts.stubs, M.stubs_stale = STUBS, nil
  M.write(M.here .. "/scripts.json", M.json_encode(M.scripts) .. "\n")
  M.write_midi_map(M.current())
  return #todo
end
function M.remove_script(key) -- unregister and delete one of the "use" actions (a style you deleted)
  if not M.scripts.main[key] then return end
  local call = "use_id(" .. string.format("%q", key:sub(5)) .. ")"
  reaper.EnumerateFiles(M.here .. "/actions", -1)
  for i = 0, 2000 do -- (its file is the stub that calls it)
    local f = reaper.EnumerateFiles(M.here .. "/actions", i)
    if not f then break end
    local p = M.here .. "/actions/" .. f
    if f:match("%.lua$") and (M.read(p) or ""):find(call, 1, true) then reaper.AddRemoveReaScript(false, 0, p, true); os.remove(p); break end
  end
  M.scripts.main[key] = nil
  M.write(M.here .. "/scripts.json", M.json_encode(M.scripts) .. "\n")
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
-- Audacity: Ctrl+D puts a copy of the selection (the time selection's part of the selected items, else the items) on a new track below,
-- at the same time. shortcut: one new track, below the first selected item's track; items on several tracks paste onto the tracks under it.
function M.duplicate_to_new_track()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return end
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local pos = s
  if s >= e then
    pos = math.huge
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do pos = math.min(pos, reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, i), "D_POSITION")) end
  end
  local cur = reaper.GetCursorPosition()
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(s < e and 40060 or 40698, 0) -- (Item: Copy selected area of items / Edit: Copy items)
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(item), "IP_TRACKNUMBER"))
  reaper.InsertTrackAtIndex(idx, true)
  reaper.SetOnlyTrackSelected(reaper.GetTrack(0, idx))
  reaper.Main_OnCommand(40914, 0) -- (the new track is the last touched one, where Paste goes)
  reaper.SetEditCurPos(pos, false, false)
  reaper.Main_OnCommand(42398, 0) -- (Item: Paste items/tracks)
  reaper.SetEditCurPos(cur, false, false)
  reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("Duplicate to a new track", -1)
end
-- Audacity's Silence, "Delete and leave gap" and "Cut and leave gap": remove or cut the selected area of the items with ripple editing off
-- for this one edit (REAPER's own actions: SWS's smart remove took whole items when run from a script).
function M.without_ripple(cmd)
  local id = tonumber(cmd) or reaper.NamedCommandLookup(cmd)
  if id == 0 then return end
  local per, all = reaper.GetToggleCommandState(41990) == 1, reaper.GetToggleCommandState(41991) == 1
  reaper.Undo_BeginBlock()
  if per or all then reaper.Main_OnCommand(40309, 0) end -- (ripple off)
  reaper.Main_OnCommand(id, 0)
  if all then reaper.Main_OnCommand(40311, 0) elseif per then reaper.Main_OnCommand(40310, 0) end
  reaper.Undo_EndBlock("Delete leaving a gap", -1)
end
-- GarageBand: N shows the Score Editor (here: the selected MIDI item in the MIDI editor, in notation view: "Mode: Notation").
-- shortcut: it opens and switches to notation, it doesn't hide the editor again; REAPER's Escape or the window's close does that.
function M.notation_editor()
  if not reaper.GetSelectedMediaItem(0, 0) then return end
  reaper.Main_OnCommand(40153, 0) -- (Item: Open in built-in MIDI editor)
  local me = reaper.MIDIEditor_GetActive()
  if me then reaper.MIDIEditor_OnCommand(me, 40954) end
end
-- Logic and Studio One: one key turns Autopunch on and off (here: REAPER's time-selection auto-punch, else normal recording).
function M.autopunch()
  reaper.Main_OnCommand(reaper.GetToggleCommandState(40076) == 1 and 40252 or 40076, 0)
end

-- ---------------------------------------------------------------- extensions some styles recommend (smooth playhead, smooth scroll and zoom)
M.EXTENSIONS = {
  playhead = { name = "ReaSmoothPlayhead", toggle = "_PLAYHEAD_TOGGLE_SMOOTH", settings = "_PLAYHEAD_SETTINGS", dll = "reaper_playhead",
    repo = { "ReaSmoothPlayhead", "https://raw.githubusercontent.com/Sakhnovkrg/ReaSmoothPlayheadReapack/main/index.xml" },
    why = "the playhead glides smoothly instead of stepping", feel = "moves its playhead smoothly" },
  smoothscroll = { name = "Smooth Wheel Scroll", settings = "_SWS_SCROLL_TUNE", dll = "reaper_smoothwheelscroll",
    file = "extensions/reaper_smoothwheelscroll-x64.dll", win_only = true, by = "bobo198504 (MIT licence)",
    url = "https://github.com/bobo198504/SmoothWheelScroll/releases",
    where = "not on ReaPack: ReaPersona carries a copy for Windows (MIT, by bobo198504); for macOS see github.com/bobo198504/SmoothWheelScroll",
    why = "scrolling and zooming with the mouse wheel glide instead of jumping", feel = "scrolls and zooms smoothly" },
}
function M.ext_here(key) -- can this extension run on this system at all?
  local x = M.EXTENSIONS[key]
  return x ~= nil and not (x.win_only and not reaper.GetOS():find("^Win"))
end
local function dll_present(prefix)
  for i = 0, 500 do
    local f = reaper.EnumerateFiles(res .. "/UserPlugins", i)
    if not f then return false end
    if f:lower():find(prefix, 1, true) == 1 then return true end
  end
end
local cache = {} -- (answers the pages ask every frame, kept a couple of seconds)
local function cached(key, fn) local c, now = cache[key], reaper.time_precise(); if c and now - c.t < 2 then return c.v end local v = fn(); cache[key] = { t = now, v = v }; return v end
function M.forget() cache = {} end
function M.extension_state(key) return cached("ext " .. key, function() return M.extension_state_now(key) end) end
function M.extension_state_now(key) -- -> "on", "off", "restart" (installed, not loaded yet) or "missing"
  local x = M.EXTENSIONS[key]
  if reaper.NamedCommandLookup(x.toggle or x.settings) ~= 0 then
    return (not x.toggle or reaper.GetToggleCommandState(reaper.NamedCommandLookup(x.toggle)) == 1) and "on" or "off"
  end
  return dll_present(x.dll) and "restart" or "missing"
end
function M.can_install(key)
  local x = M.EXTENSIONS[key]
  return (x.repo and reaper.ReaPack_AddSetRepository ~= nil) or (x.file ~= nil and not (x.win_only and M.IS_MAC) and reaper.file_exists(M.here .. "/" .. x.file))
end
function M.install_extension(key) -- -> true, or nil + why. REAPER loads it at its next start.
  local x = M.EXTENSIONS[key]
  if x.repo and reaper.ReaPack_AddSetRepository then
    -- (one AddSetRepository with the final autoInstall, then one ProcessQueue: a second pass while ReaPack's report is open crashed REAPER)
    local ok, err = reaper.ReaPack_AddSetRepository(x.repo[1], x.repo[2], true, 1, "")
    if not ok then return nil, err end
    reaper.ReaPack_ProcessQueue(true)
    M.forget()
    return true
  elseif x.file and not (x.win_only and M.IS_MAC) and reaper.file_exists(M.here .. "/" .. x.file) then
    local data = M.read(M.here .. "/" .. x.file)
    if not (data and M.write(res .. "/UserPlugins/" .. x.file:match("[^/]+$"), data)) then return nil, "couldn't copy it into UserPlugins" end
    M.forget()
    return true
  end
  return nil, x.where or "no way to install it from here"
end

-- ---------------------------------------------------------------- themes you add, styles made by merging shortcuts
function M.import_theme(path, as_name) -- copy a downloaded theme into ColorThemes (as as_name, when given) -> its file name, or nil + why
  local name = as_name or path:gsub("\\", "/"):match("[^/]+$") or ""
  if not (name:match("%.ReaperThemeZip$") or name:match("%.ReaperTheme$")) then return nil, "not a .ReaperThemeZip or .ReaperTheme" end
  local data = M.read(path)
  if not data then return nil, "couldn't read it" end
  M.recent_themes[name] = true
  local old = M.read(M.themes_dir .. name)
  if old == data then return name, "you already had this one" end
  local note
  if old then -- (a newer download of a theme you have: the older copy is kept next to it, out of the theme lists)
    local keep = name .. ".before-" .. os.date("%Y%m%d-%H%M%S")
    if not M.write(M.themes_dir .. keep, old) then return nil, "couldn't keep a copy of the one you had" end
    note = "replaced the copy you had (kept as " .. keep .. ")"
  end
  if not M.write(M.themes_dir .. name, data) then return nil, "couldn't write into ColorThemes" end
  return name, note
end
M.recent_themes = {} -- (themes added this session: the theme list shows them first, marked new)
local function copy(v) if type(v) ~= "table" then return v end local t = {}; for k, x in pairs(v) do t[k] = copy(x) end return t end
local function free_alt() -- a shortcut layer no style uses and that holds none of your own keys
  local used, mine = {}, {}
  for _, s in ipairs(M.styles) do used[s.alt or 0] = true end
  for _, l in ipairs((M.load_json(M.here .. "/installed.json") or {}).lines or {}) do mine[l] = true end -- (lines ReaPersona wrote)
  for line in (M.read(res .. "/reaper-kb.ini") or ""):gmatch("[^\r\n]+") do
    local f, k, cmd, sec = line:match("^KEY (%d+) (%d+) (%S+) (%d+)")
    local a = tonumber(sec)
    if a and a >= 1 and a <= 16 and not mine[f .. " " .. k .. " " .. cmd .. " " .. sec] and not line:find("# ReaPersona", 1, true) then used[a] = true end
  end
  for a = 1, 16 do if not used[a] then return a end end
end
-- A persona of yours keeps a layer of its own. One a later version gave a new DAW (Audacity took alt-11 in 5.3.0, Audition alt-12 in
-- 5.4.0) held both sets of keys, so each changed the other's; yours moves to a free layer, and its keys go in at the next shortcut
-- install. Review, 5.9.4
function M.layer_clashes(styles) -- -> your personas whose own layer a built-in one, or one of yours with a smaller id, also has (pure)
  local taken, out = {}, {}
  for _, s in ipairs(styles) do if not s.user and (s.alt or 0) > 0 then taken[s.alt] = true end end
  local mine = {}
  for _, s in ipairs(styles) do if s.user then mine[#mine + 1] = s end end
  table.sort(mine, function(a, b) return tostring(a.id) < tostring(b.id) end) -- (the same answer on every computer, whatever order they're in: Review 5.11, H3)
  for _, s in ipairs(mine) do
    if s.user and not s.keys_from and (s.alt or 0) > 0 then
      if taken[s.alt] then out[#out + 1] = s else taken[s.alt] = true end
    end
  end
  return out
end
local function fix_clashes()
  local moved = M.layer_clashes(M.styles)
  for _, st in ipairs(moved) do
    local a = free_alt()
    if a then st.alt = a; save_user_style(st) else M.log(st.name .. " shares shortcut layer alt-" .. st.alt .. " and no layer is free") end
  end
  if #moved > 0 then load_presets() end -- (presets on one of them take its new layer)
end
fix_clashes()
function M.reload_users() -- your personas, presets and theme recipes read again, in place (a sync or a setup file changed the files)
  for n = #M.styles, 1, -1 do if M.styles[n].user then table.remove(M.styles, n) end end
  for _, st in ipairs(load(USERS)) do st.user = true; M.styles[#M.styles + 1] = st end
  for _, st in ipairs(M.styles) do if st.user and st.keys_from then M.resolve_keys(st) end end
  fix_clashes()
  load_presets()
  for k, v in pairs(M.load_json(M.here .. "/user_themes.json") or {}) do M.OWN[k] = v end
  M.stubs_stale = true -- (a new persona's "use" action)
end
-- ---------------------------------------------------------------- combining styles: several DAWs' keys and feel in one style
-- Styles are taken in priority order (first wins); `choice` overrides that per clash: choice["key " .. spec], choice["midi " .. spec]
-- or choice[feel slot] = the style id whose version you want.
local function feel_slot(f)
  if f[1] == "toggle" then return "toggle " .. tostring(f[2])
  elseif f[1] == "radio" then return "radio " .. table.concat(f[2], ",")
  elseif f[1] == "dock" then return "dock " .. f[2]
  elseif f[1] == "midi_dock" then return "midi_dock"
  elseif f[1] == "choice" then return "choice " .. table.concat(f[2], ",")
  elseif f[1] == "mouse" then return "mouse " .. f[2] .. " " .. f[3]
  elseif f[1] == "switch" then local c = tonumber(f[2]) or 0; return (c >= 41956 and c <= 41959) and "switch midi" or "switch main" end
end
local function feel_value(f)
  if f[1] == "dock" then return f[3] .. "/" .. tostring(f[4]) elseif f[1] == "mouse" then return tostring(f[4])
  elseif f[1] == "midi_dock" then return tostring(f[2])
  elseif f[1] == "switch" then return tostring(f[2]) else return tostring(f[3]) end
end
-- ---------------------------------------------------------------- the Persona Builder: blocks stacked into a persona
-- A block is { kind = "daw", id, keys, feel, theme, mouse } (a DAW's shortcuts, its layout and feel, its theme and its mouse, each
-- part on or off), { kind = "mouse", id } (a DAW's mouse alone: its wheel shortcuts and its drags and clicks), { kind = "feel", id,
-- aspect } (one part of a DAW's feel), { kind = "settings", group, values } (REAPER options: values[i] is 0/1 for a switch or the
-- option's number for a choice, -1 leaves it alone), { kind = "theme", file }, { kind = "colour", hex } or { kind = "project", srate,
-- tracks, tracks_name, wset } (a workflow's project: its sample rate, starter tracks and window set, for a project that's still empty).
-- Where two blocks set the same thing, the lower one wins. A mouse block also takes the whole mouse from the blocks above it, so one
-- DAW's keys with another's mouse is that DAW's mouse and nothing of the first one's (James, 5.10: "a Builder block for them").
-- The persona keeps its blocks, so the Builder can open it again.
M.SETTING_GROUPS = { -- (REAPER's own actions, checked against its action list; "_SWS..." and "_S&M..." ones need SWS)
  { id = "playback", name = "Playback and scrolling", items = {
    { 41817, "Continuous scrolling", tip = "The arrange view moves under a fixed playhead during playback." },
    { 40036, "Follow the playhead", tip = "The view scrolls to keep the playhead in sight during playback." },
    { 40262, "Follow while recording", tip = "The same, while recording." },
    { 40390, "Smooth seek", tip = "Jumps during playback wait for the end of the bar or region (Preferences > Audio > Seeking)." },
    { 1068, "Loop playback", tip = "Playback repeats the loop range." },
    { 40621, "Loop follows the time selection", tip = "Selecting time sets the loop range too." },
    { 41818, "Pre-roll on play", tip = "Playback starts a little before the cursor." },
    { 40364, "Metronome", tip = "REAPER's click." },
    { "_SWS_AWMPLAYTOG", "Metronome during playback", tip = "The click sounds when playing (SWS)." },
    { "_SWS_AWCOUNTPLAYTOG", "Count-in before playback", tip = "A bar of click before playback starts (SWS)." },
    { "_SWS_TOGSEEKMODE1", "Playback follows item moves", tip = "Moving or resizing an item during playback seeks to it (SWS)." },
    { 41834, "Stop at the end of the loop when repeat is off", tip = "Playback stops at the loop range's end instead of carrying on." },
    { 40671, "Keep the pitch when changing the playback rate", tip = "The master playrate speeds audio up without changing its pitch." },
    { 40868, "Home and End go to markers", tip = "The transport's Home and End jump between project markers." } } },
  { id = "editing", name = "Editing", items = {
    { 1157, "Snap", tip = "Edits snap to the grid." },
    { { 40309, 40310, 40311 }, "Ripple editing", { "Off", "Per track", "All tracks" }, tip = "Moving or deleting an item shifts what comes after it." },
    { 40041, "Auto-crossfade", tip = "Overlapping items crossfade." },
    { 40912, "Crossfade on split", tip = "A short crossfade where you split." },
    { 41117, "Trim content behind items", tip = "An item moved over another cuts the one underneath." },
    { 40070, "Envelope points move with items", tip = "Automation under an item moves with it." },
    { 1156, "Item grouping", tip = "Grouped items move together." },
    { 41156, "Clicking a grouped item selects its group" },
    { 1135, "Locking", tip = "Locked items and envelopes can't be moved (Shift+L sets what)." },
    { 40507, "Overlapping items shown in lanes", tip = "Items that overlap on a track sit in lanes, one above the other." },
    { 40276, "Edit cursor jumps to a new time selection", tip = "Selecting time moves the edit cursor to its start." },
    { "_SWS_AWCLRTIMESELCLKTOG", "Time selection and edit cursor linked", tip = "Clicking clears the time selection and moves the cursor together (SWS)." },
    { 42421, "Razor edits always trim what's behind", tip = "Otherwise razor edits follow the item editing options above." },
    { 42459, "Razor edits in the item lane take the envelopes too", tip = "A razor edit over items also edits that track's automation." },
    { 41338, "Slip editing moves every take", tip = "Slipping an item's content moves all its takes, not just the active one." },
    { 41071, "Copied MIDI items share their notes (pooled)", tip = "Editing one copy edits them all (ghost copies)." },
    { 43651, "Group names and colours in the arrange view" } } },
  { id = "recording", name = "Recording", items = {
    { { 40252, 40076, 40253 }, "Record mode", { "Normal", "Punch in the time selection", "Punch in selected items" } },
    { { 41330, 41186, 42677 }, "Recording over an item", { "Splits it and adds a take", "Replaces it (tape)", "Adds a layer" }, tip = "What happens when you record over an existing item." },
    { { 43153, 43152, 43151 }, "Lanes", { "No lanes", "New lanes play alone", "Lanes in layers" }, tip = "Whether new recordings get fixed lanes (REAPER 7's comping lanes)." },
    { 40114, "Loop recording always adds takes", tip = "Each pass of a looped recording is a take." },
    { 41819, "Pre-roll on record", tip = "Recording starts a little before the cursor." },
    { 40364, "Metronome" },
    { "_SWS_AWMRECTOG", "Metronome while recording", tip = "The click sounds when recording (SWS)." },
    { "_SWS_AWCOUNTRECTOG", "Count-in before recording", tip = "A bar of click before recording starts (SWS)." },
    { 40300, "Edit cursor to the end of a new recording", tip = "When recording stops, the edit cursor moves to its end." },
    { "_SWS_AWAUTOGROUPTOG", "Group what's recorded together", tip = "Items recorded in one pass are grouped (SWS)." },
    { 42631, "Auto-fades when comping in lanes", tip = "Comp areas in fixed lanes get fades and crossfades." },
    { 42601, "Razor edits on collapsed lanes take every lane" } } },
  { id = "view", name = "View", items = {
    { { 40366, 40367, 40365, 40370, 40368 }, "Ruler", { "Bars and beats + time", "Bars and beats", "Minutes:seconds", "Timecode", "Seconds" } }, -- (+ time first: it reads "Bars and beats" as on too)
    { 40651, "Item labels", tip = "Names on media items." },
    { 40258, "Labels above items", tip = "Item names sit above the item, not inside it." },
    { 40145, "Grid lines", tip = "Vertical grid lines in the arrange view." },
    { 40435, "Show all takes", tip = "Every take of an item stacked, when there's room." },
    { 42073, "Spectral peaks", tip = "Waveforms coloured by frequency." },
    { 43145, "Peaks coloured by loudness", tip = "Waveforms coloured by momentary loudness (LUFS-M)." },
    { 40691, "Media cues in items", tip = "Cue markers from the file show inside items." },
    { 41344, "Tooltips on items and envelopes" },
    { 43149, "Peak values in item tooltips" },
    { 43642, "Item timebase buttons" },
    { 40302, "FX inserts in the track panel", tip = "FX slots on each track's panel, when it's tall enough." },
    { 40677, "Sends in the track panel", tip = "Sends on each track's panel, when it's tall enough." },
    { 42373, "Track panel on the right", tip = "Track controls to the right of the arrange view, as in some DAWs." } } },
  { id = "colours", name = "Colours and icons (SWS)", items = {
    { "_SWSAUTOCOLOR_ENABLE", "Auto-colour tracks", tip = "New and renamed tracks take colours from SWS's rules (drums red, say)." },
    { "_S&MAUTOCOLOR_MKR_ENABLE", "Auto-colour markers" },
    { "_S&MAUTOCOLOR_RGN_ENABLE", "Auto-colour regions" },
    { "_S&MAUTOICON_ENABLE", "Auto track icons", tip = "Tracks get icons from SWS's rules." },
    { "_S&MAUTOLAYOUT_ENABLE", "Auto track layouts", tip = "Tracks get theme layouts from SWS's rules." },
    { "_SWS_RECREDRULER", "Ruler goes red while recording" } } },
  { id = "automation", name = "Automation", items = {
    { 41576, "Envelope points follow the time selection", tip = "Selecting time selects the envelope points in it." },
    { 42206, "Trim behind automation items", tip = "An automation item moved over another cuts it." },
    { 42640, "Keep trailing values when recording automation" },
    { "_SWS_TOGAUTOADDENVS", "Envelopes appear when you move a control in Write mode", tip = "SWS." },
    { 42220, "An automation item when you arm a bypassed envelope", tip = "Activating a hidden, bypassed envelope puts in an automation item." } } },
  { id = "monitoring", name = "Monitoring and FX", items = {
    { 41583, "FX run while stopped", tip = "Plug-ins keep processing when the transport is stopped (reverb tails, synths you play live)." },
    { 41884, "Monitoring FX bypassed", tip = "The monitoring FX chain (headphone or room correction, say) is off: it never reaches renders either way." },
    { 42034, "MIDI input quantize on every track", tip = "Live MIDI is quantized as it's recorded." },
    { 41187, "Looped-segment scrub at the edit cursor", tip = "Moving the edit cursor plays a short looped bit there." } } },
  { id = "mixer", name = "Mixer", items = {
    { 40389, "Master on the right" }, { 40549, "FX inserts" }, { 40557, "Sends" }, { 40910, "FX parameters" }, { 40903, "Track icons" },
    { 40371, "Multiple rows" }, { 40745, "Solo in front", tip = "Soloing dims the rest instead of muting it." } } },
}
local function group_by_id(id) for _, g in ipairs(M.SETTING_GROUPS) do if g.id == id then return g end end end
M.setting_group = group_by_id
function M.aspect_name(a) for _, x in ipairs(M.ASPECTS) do if x[1] == a then return x[4] end end return tostring(a) end
function M.setting_now(item) -- -> the item as REAPER has it now (0/1, or the option's number), or -1 when it can't be read
  if type(item[1]) == "table" then
    for n, c in ipairs(item[1]) do if reaper.GetToggleCommandState(cmd_id(c)) == 1 then return n end end
    return -1
  end
  return reaper.GetToggleCommandState(cmd_id(item[1]))
end
function M.new_block(kind, a, b) -- every part on; a settings block starts as REAPER is set now
  if kind == "daw" then return { kind = "daw", id = a, keys = true, feel = true, theme = true, mouse = true }
  elseif kind == "mouse" then return { kind = "mouse", id = a }
  elseif kind == "feel" then return { kind = "feel", id = a, aspect = b }
  elseif kind == "settings" then
    local values = {}
    for i, item in ipairs((group_by_id(a) or {}).items or {}) do values[i] = M.setting_now(item) end
    return { kind = "settings", group = a, values = values }
  elseif kind == "theme" then return { kind = "theme", file = a }
  elseif kind == "colour" then return { kind = "colour", hex = a }
  elseif kind == "colours" then return { kind = "colours", set = M.colours_now() or {} }
  elseif kind == "project" then return { kind = "project", srate = 0, tracks = "", tracks_name = "", wset = 0 } end
end
-- A persona made from the tabs (5.27; James: "all the blocks should move and just be based on the tabs so you can choose more granularly ...
-- Blocks are built automatically from all settings, then constructed into the persona. More tabs for each type of block"). The persona being
-- made holds at most one block per slot: the shortcuts, the mouse, each part of the layout (mixer, transport, browser, toolbar, MIDI editor,
-- snap and ripple), each group of REAPER settings, the theme, the persona's colour, the colour look and the project. Each tab picks what goes
-- in its slots, line by line; the order they're built in is fixed, so nothing depends on where a block was added. (5.26 had a stack.)
function M.block_slot(b) -- (pure) -> the slot a block fills
  if b.kind == "daw" then
    if b.keys and not b.feel and not b.theme and not b.mouse then return "keys" end
    return "daw " .. tostring(b.id) -- (a whole DAW, as personas built before 5.27 have: split by M.split_blocks)
  elseif b.kind == "feel" then return "feel " .. tostring(b.aspect)
  elseif b.kind == "settings" then return "settings " .. tostring(b.group) end
  return b.kind -- (mouse, theme, colour, colours, project: one each)
end
function M.draft_add(blocks, b) -- the block into its slot (replacing what was there). -> the list, true when one was replaced (pure)
  local slot, replaced = M.block_slot(b), false
  for i = #blocks, 1, -1 do if M.block_slot(blocks[i]) == slot then table.remove(blocks, i); replaced = true end end
  blocks[#blocks + 1] = b
  return blocks, replaced
end
function M.draft_get(blocks, slot) for _, b in ipairs(blocks) do if M.block_slot(b) == slot then return b end end end
function M.draft_clear(blocks, slot) for i = #blocks, 1, -1 do if M.block_slot(blocks[i]) == slot then table.remove(blocks, i) end end return blocks end
function M.keys_block(id) local b = M.new_block("daw", id); b.feel, b.theme, b.mouse = false, false, false; return b end
-- A whole DAW block as one block per slot: its keys, its mouse, each part of its layout it has, and its theme. Lines left out stay left out.
function M.split_blocks(blocks) -- (pure but for M.by_id)
  local out = {}
  for _, b in ipairs(blocks or {}) do
    local st = b.kind == "daw" and M.by_id(b.id)
    if st and M.block_slot(b) ~= "keys" then
      local mouse = b.mouse; if mouse == nil then mouse = b.keys and b.feel end -- (a block from before 5.10)
      local function part(nb) nb.off = type(b.off) == "table" and M.json_decode(M.json_encode(b.off)) or nil; M.draft_add(out, nb) end -- (a copy: unticking while editing mustn't change the saved one)
      if b.keys then part(M.keys_block(b.id)) end
      if mouse then part(M.new_block("mouse", b.id)) end
      if b.feel then
        local has = {}
        for _, f in ipairs(st.feel or {}) do has[M.aspect_of(f)] = true end
        for _, x in ipairs(M.ASPECTS) do if has[x[1]] and x[1] ~= "mouse" then part(M.new_block("feel", b.id, x[1])) end end
      end
      local th = b.theme and M.theme_for(st)
      if th then part(M.new_block("theme", th)) end
    else M.draft_add(out, M.json_decode(M.json_encode(b))) end
  end
  return out
end
local SLOT_ORDER = { keys = 1, mouse = 2, feel = 3, settings = 4, theme = 5, colour = 6, colours = 7, project = 8 }
function M.draft_order(blocks) -- (pure) the order they're built in: the shortcuts first, then the mouse, the layout, REAPER settings (over a DAW's snap and ripple), the look, the project
  local out = {}
  for i, b in ipairs(blocks) do out[i] = b end
  local function rank(b) return SLOT_ORDER[(M.block_slot(b):match("^(%a+)"))] or 0 end
  table.sort(out, function(a, b) local ra, rb = rank(a), rank(b); if ra ~= rb then return ra < rb end return M.block_slot(a) < M.block_slot(b) end)
  return out
end
function M.blocks_of(st) -- a persona as the tabs' choices: one you built as its blocks, any other whole (a saved setup with its colours)
  local out = M.split_blocks(type(st.blocks) == "table" and st.blocks or { M.new_block("daw", st.id) })
  if not st.blocks and st.preset and st.colours then M.draft_add(out, { kind = "colours", set = st.colours }) end
  return out
end

-- Favourites (5.27): a star on any DAW or persona; Personas > Favourites lists them. Kept as ExtState "favourites" (ids joined by ";"),
-- which syncs like any setting. Never set: My REAPER and the persona in use (setting up ReaPersona stars the DAW you pick).
function M.favourites()
  local out, seen = {}, {}
  local function add(id) if id ~= "" and not seen[id] then seen[id] = true; out[#out + 1] = id end end
  if reaper.HasExtState(M.SECTION, "favourites") then
    for id in reaper.GetExtState(M.SECTION, "favourites"):gmatch("[^;]+") do add(id) end
  else
    add("my_reaper")
    local cur = M.current()
    if cur then add(cur.base or cur.id) end
  end
  return out
end
function M.is_favourite(id) for _, f in ipairs(M.favourites()) do if f == id then return true end end return false end
function M.set_favourite(id, on)
  local keep = {}
  for _, f in ipairs(M.favourites()) do if f ~= id then keep[#keep + 1] = f end end
  if on then keep[#keep + 1] = id end
  reaper.SetExtState(M.SECTION, "favourites", table.concat(keep, ";"), true)
end
function M.block_title(b)
  local st = b.id and M.by_id(b.id)
  local name = st and st.name or tostring(b.id)
  if b.kind == "daw" then
    if M.block_slot(b) == "keys" then return b.id == "my_reaper" and "Your own shortcuts" or (name .. "'s shortcuts") end
    return name
  elseif b.kind == "mouse" then return name .. ": Mouse"
  elseif b.kind == "feel" then return name .. ": " .. M.aspect_name(b.aspect)
  elseif b.kind == "settings" then return (group_by_id(b.group) or { name = tostring(b.group) }).name
  elseif b.kind == "theme" then return "Theme: " .. tostring(b.file):gsub("%.ReaperTheme%a*$", "")
  elseif b.kind == "colour" then return "Colour " .. tostring(b.hex)
  elseif b.kind == "colours" then return M.colours_label(b.set)
  elseif b.kind == "project" then return "Project" .. ((b.name or "") ~= "" and (": " .. b.name) or "") end
  return "?"
end
function M.safe_feel(list) -- a shared file's feel, keeping only commands ReaPersona's own personas and settings use (a file can't run others)
  local ok = {}
  local function add(c) ok[tostring(c)] = true end
  for _, st in ipairs(M.styles_json.styles or {}) do
    for _, f in ipairs(st.feel or {}) do
      if f[1] == "toggle" then add(f[2]) elseif f[1] == "switch" then add(f[2]); add(f[3])
      elseif f[1] == "radio" or f[1] == "choice" then for _, c in ipairs(f[2]) do add(c) end end
    end
  end
  for _, g in ipairs(M.SETTING_GROUPS) do for _, it in ipairs(g.items) do if type(it[1]) == "table" then for _, c in ipairs(it[1]) do add(c) end else add(it[1]) end end end
  for _, c in ipairs(EXTRA_TOGGLES) do add(c) end
  local out = {}
  for _, f in ipairs(type(list) == "table" and list or {}) do
    local good = type(f) == "table" and type(f[1]) == "string"
    if good and f[1] == "toggle" then good = ok[tostring(f[2])]
    elseif good and f[1] == "switch" then good = ok[tostring(f[2])] and ok[tostring(f[3])]
    elseif good and (f[1] == "radio" or f[1] == "choice") then
      good = type(f[2]) == "table" and ok[tostring(f[3])]
      for _, c in ipairs(good and f[2] or {}) do good = good and ok[tostring(c)] end
    elseif good and f[1] == "mouse" then good = type(f[2]) == "string" and type(f[4]) == "string" and not f[4]:find("_", 1, true) -- (no custom actions)
    elseif good then good = f[1] == "dock" or f[1] == "midi_dock" end
    if good then out[#out + 1] = f end
  end
  return out
end
-- (e.mouse: a wheel shortcut or a mouse drag/click, the part a mouse block takes over)
local function block_entries(b) -- what one block sets: { slot, kind = "key"|"midi"|"feel"|"theme"|"accent", label, key, entry, value }
  local out, st = {}, b.id and M.by_id(b.id)
  local function feel(f) local s = feel_slot(f); if s then out[#out + 1] = { slot = s, kind = "feel", label = f[#f], entry = f, mouse = f[1] == "mouse" or nil } end end
  local function key(k, wheel) out[#out + 1] = { slot = "key " .. M.canon(k[1]), kind = "key", label = k[3], key = k[1], entry = k, mouse = wheel or nil } end
  if (b.kind == "daw" or b.kind == "mouse") and st then
    -- (a DAW block saved before 5.10 has no mouse part: its wheel keys go with its keys and its drags with its feel, as they did)
    local mouse, daw = b.kind == "mouse" or b.mouse, b.kind == "daw"
    for _, k in ipairs(M.keys_here(st.keys)) do
      local wheel = M.is_wheel(k[1])
      if wheel and (mouse or (mouse == nil and b.keys)) or (not wheel and daw and b.keys) then key(k, wheel) end
    end
    if daw and b.keys then
      for _, k in ipairs(st.midi_keys or {}) do out[#out + 1] = { slot = "midi " .. M.canon(k[1]), kind = "midi", label = k[3], key = k[1], entry = k } end
    end
    for _, f in ipairs(st.feel or {}) do
      if f[1] == "mouse" then if mouse or (mouse == nil and b.feel) then feel(f) end
      elseif daw and b.feel then feel(f) end
    end
    local th = daw and b.theme and M.theme_for(st)
    if th then out[#out + 1] = { slot = "theme", kind = "theme", label = th, value = th } end
  elseif b.kind == "feel" and st then
    for _, f in ipairs(st.feel or {}) do if M.aspect_of(f) == b.aspect then feel(f) end end
  elseif b.kind == "settings" then
    for i, item in ipairs((group_by_id(b.group) or {}).items or {}) do
      local v = tonumber((b.values or {})[i]) or -1
      if type(item[1]) == "table" and item[1][v] then feel({ "choice", item[1], item[1][v], item[2] .. ": " .. item[3][v] })
      elseif type(item[1]) ~= "table" and v >= 0 then feel({ "toggle", item[1], v, item[2] .. ": " .. (v == 1 and "on" or "off") }) end
    end
  elseif b.kind == "theme" and b.file then out[1] = { slot = "theme", kind = "theme", label = b.file, value = b.file }
  elseif b.kind == "colour" and b.hex then out[1] = { slot = "accent", kind = "accent", label = "Colour " .. b.hex, value = b.hex }
  elseif b.kind == "colours" and M.safe_colours(b.set) then
    out[1] = { slot = "colours", kind = "colours", label = M.colours_label(b.set) .. " (tracks, items and regions)", value = M.safe_colours(b.set) }
  elseif b.kind == "project" then
    for _, e in ipairs(M.project_entries(b)) do out[#out + 1] = e end
  end
  return out
end
function M.build_preview(blocks) -- -> per block its entries, each with .lost_to = the lower block that replaces it
  local per, winner, mouse = {}, {}, {}
  for i, b in ipairs(blocks) do -- (b.off[slot]: a line of the block you unticked, left out of the persona)
    per[i] = block_entries(b)
    if b.kind == "mouse" then for slot in pairs(mouse) do winner[slot] = i end end -- (the whole mouse from the blocks above: this one's)
    for _, e in ipairs(per[i]) do
      if type(b.off) == "table" and b.off[e.slot] then e.off = true else winner[e.slot] = i; mouse[e.slot] = e.mouse end
    end
  end
  for i, list in ipairs(per) do for _, e in ipairs(list) do if not e.off and winner[e.slot] ~= i then e.lost_to = winner[e.slot] end end end
  return per
end
function M.build_style(blocks, name, id) -- -> the persona (not saved yet), true when its shortcuts need installing; or nil + why
  local per = M.build_preview(blocks)
  local st = { id = id or M.new_id("built_"), name = name, kind = "built", blocks = copy(blocks), feel = {}, keys = {}, midi_keys = {},
    extras = {}, docs = {}, recommends = {} }
  local daws, names, seen, accent = {}, {}, {}, nil
  for i, b in ipairs(blocks) do
    local src = b.id and M.by_id(b.id)
    if b.kind == "daw" and b.keys and src then daws[#daws + 1] = b.id end
    names[#names + 1] = M.block_title(b)
    for _, e in ipairs(per[i]) do
      if not e.lost_to and not e.off then
        if e.kind == "key" then st.keys[#st.keys + 1] = copy(e.entry)
        elseif e.kind == "midi" then st.midi_keys[#st.midi_keys + 1] = copy(e.entry)
        elseif e.kind == "feel" then st.feel[#st.feel + 1] = copy(e.entry)
        elseif e.kind == "theme" then st.theme = e.value
        elseif e.kind == "accent" then st.accent = e.value
        elseif e.kind == "colours" then st.colours = e.value
        elseif e.kind == "project" then st.project = st.project or {}; for k, v in pairs(e.value) do st.project[k] = v end end
      end
    end
    if src and b.kind == "daw" then
      accent = accent or src.accent
      for _, x in ipairs(src.extras or {}) do st.extras[#st.extras + 1] = x end
      for _, d in ipairs(src.docs or {}) do st.docs[#st.docs + 1] = d end
      for _, r in ipairs(src.recommends or {}) do if not seen[r] then seen[r] = true; st.recommends[#st.recommends + 1] = r end end
      local look = src.id == "my_reaper" and M.my_look()
      local starts = src.id == "my_reaper" and (look and look.starts or M.starts_now()) or src.starts or {}
      st.starts = st.starts or {}
      for _, s in ipairs(starts) do if not seen["start " .. s[2]] then seen["start " .. s[2]] = true; st.starts[#st.starts + 1] = s end end -- (your scripts at start, 5.22)
    end
  end
  st.accent = st.accent or accent
  st.themes = { st.theme }
  local install = false
  local layer, _, own = M.keys_layer(blocks, st.id)
  if layer == "borrow" then st.keys_from = daws[1]; M.resolve_keys(st) -- (one DAW's keys, all of them: its shortcut layer, nothing to install)
  elseif layer == "own" then -- (a layer of their own, which needs installing)
    st.alt = own or free_alt()
    if not st.alt then return nil, "its keys need a shortcut layer of their own (some left out, or one persona's shortcuts with another's mouse wheel) and all 16 are in use. " ..
      "Use one persona's shortcuts with its own mouse, or your own shortcuts, or delete a persona of yours you don't use" end
    install = true
  else st.alt = 0 end -- (no shortcuts block: your own keys)
  st.description = name .. ", built from " .. table.concat(names, ", ") .. " (lower blocks win)." ..
    (layer == "own" and (" Its shortcuts are on layer alt-" .. st.alt .. ".") or "")
  return st, install
end
-- ---------------------------------------------------------------- workflows: what a new project gets
-- (James, 5.11: "usually I want 44.1 kHz but when I'm recording voiceover for video I may want 48 kHz and a different layout, or different
-- for live looping ... open a new project, select the persona (on any device) and it's ready to go".) A persona's project part: its
-- sample rate, starter tracks (a track template's text, kept in the persona so it goes to your other computers with it) and a window set
-- (View > Screensets). The sample rate and tracks go into a project that's still empty, never one with your work in it; the window set
-- loads every time.
M.SRATES = { 44100, 48000, 88200, 96000, 176400, 192000 }
function M.khz(sr) return string.format("%g kHz", (tonumber(sr) or 0) / 1000) end -- (48000 -> "48 kHz", 44100 -> "44.1 kHz"; pure)
M.WSET_LOAD = 40454 -- "Screenset: Load window set #01" (#01-#10: 40454-40463)
function M.project_entries(b) -- a project block's lines, for the Builder (pure)
  local out = {}
  local sr = tonumber(b.srate) or 0
  if sr > 0 then out[#out + 1] = { slot = "project srate", kind = "project", label = "Sample rate " .. M.khz(sr) .. " (a new project)", value = { srate = sr } } end
  if type(b.tracks) == "string" and b.tracks ~= "" then
    local n = select(2, b.tracks:gsub("<TRACK", ""))
    out[#out + 1] = { slot = "project tracks", kind = "project", label = "Starter tracks: " .. ((b.tracks_name or "") ~= "" and b.tracks_name or (n .. " track" .. (n == 1 and "" or "s"))) .. " (a new project)",
      value = { tracks = b.tracks, tracks_name = b.tracks_name } }
  end
  if type(b.template) == "string" and b.template ~= "" then
    out[#out + 1] = { slot = "project template", kind = "project", label = "Project template: " .. tostring(b.template_name or "a whole project") .. " (a new project)",
      value = { template = b.template, template_name = b.template_name } }
  end
  local w = tonumber(b.wset) or 0
  if w >= 1 and w <= 10 then out[#out + 1] = { slot = "project wset", kind = "project", label = "Window set #" .. w, value = { wset = w } } end
  return out
end
function M.track_chunk(name, armed, monitor, input) -- a starter track as a track template's text (pure). input: 0 = mono input 1, 1024 = stereo 1/2
  return "<TRACK\n  NAME \"" .. tostring(name):gsub('"', "'") .. "\"\n  REC " .. (armed and 1 or 0) .. " " .. (input or 0) .. " " .. (monitor and 1 or 0) ..
    " 0 0 0 0 0\n  NCHAN 2\n>\n"
end
function M.strip_blocks(text, names) -- the text without the <NAME ...> chunks named, at any depth (pure)
  local out, depth = {}, 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local t = line:match("^%s*(.-)%s*$")
    if depth > 0 then
      if t:sub(1, 1) == "<" then depth = depth + 1 elseif t == ">" then depth = depth - 1 end
    elseif names[t:match("^<(%S+)") or ""] then depth = 1
    else out[#out + 1] = line end
  end
  return (table.concat(out, "\n"):gsub("\n+$", "")) .. "\n"
end
function M.strip_items(chunk) return M.strip_blocks(chunk, { ITEM = true }) end -- a track's state without its media items, for a template (pure)
-- A project as a project template (James, 5.13: "can be built with project templates as well"): everything REAPER keeps in the project
-- (its tracks with their FX, routing and folders, sample rate, recording format, render settings, tempo and time signature, markers and
-- regions, grid, notes) without its media items, its media bay, scripts' data stored in it (StudioSync's would make a new project look
-- shared) or its own folders (recording path, render file). Pure.
local TEMPLATE_DROP = { ITEM = true, EXTSTATE = true, PROJBAY = true }
local TEMPLATE_DROP_LINE = { RECORD_PATH = true, RENDER_FILE = true }
function M.template_from_rpp(t)
  local out = {}
  for line in M.strip_blocks(t, TEMPLATE_DROP):gmatch("[^\n]*\n") do
    if not TEMPLATE_DROP_LINE[line:match("^%s*(%S+)") or ""] then out[#out + 1] = line end
  end
  return table.concat(out)
end
function M.project_template_text() -- this project as a template's text, or nil (REAPER writes a copy: the project keeps its file, name and changes)
  local f = M.here .. "/_capture.RPP"
  reaper.Main_SaveProjectEx(0, f, 0) -- (options 0: not a track template, and without &8 the project doesn't take the copy's name)
  local t = M.read(f)
  os.remove(f); os.remove(f .. "-bak")
  return t and t:find("<REAPER_PROJECT", 1, true) and M.template_from_rpp(t) or nil
end
-- The plug-ins a workflow's tracks use, and which of them this computer hasn't got (the review: "a check for plugins a workflow's tracks
-- need but a computer lacks"). Names as REAPER's FX browser shows them without the format ("Pro-Q 3 (FabFilter)"), so a VST3 on one
-- computer and an AU of the same plug-in on a Mac count as the same; JSFX by their file. fx_needed is pure.
function M.fx_needed(text)
  local out, seen = {}, {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local kind, rest = line:match("^%s*<(%u+%d?) (.*)$")
    local name
    if kind == "VST" or kind == "AU" or kind == "CLAP" or kind == "LV2" or kind == "DX" then
      name = rest:match('^"([^"]*)"') or rest:match("^(%S+)")
      name = name and (name:gsub("^[%w]+: ", ""))
    elseif kind == "JS" then
      local f = rest:match('^"([^"]*)"') or rest:match("^(%S+)")
      name = f and ("JS: " .. f)
    end
    if name and name ~= "" and name ~= "JS: " and not seen[name] then seen[name] = true; out[#out + 1] = name end
  end
  return out
end
function M.fx_missing(names)
  if #names == 0 or not reaper.EnumInstalledFX then return {} end
  local have, i = {}, 0
  while true do
    local ok, name = reaper.EnumInstalledFX(i)
    if not ok then break end
    have[(name:gsub("^[%w]+: ", ""))] = true
    i = i + 1
  end
  local out = {}
  for _, n in ipairs(names) do
    local js = n:match("^JS: (.+)$")
    if js then if not reaper.file_exists(res .. "/Effects/" .. js) then out[#out + 1] = n end
    elseif not have[n] then out[#out + 1] = n end
  end
  return out
end
-- Each computer's own track inputs for a workflow: its interface numbers them its own way, so they're kept here, never synced
-- ("inputs <persona id>" is one of HERE_PREFIX), and put on the workflow's tracks when a new project gets them.
function M.keep_inputs(id) -- -> how many tracks' inputs were kept
  local list = {}
  for i = 0, reaper.CountTracks(0) - 1 do list[#list + 1] = math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(0, i), "I_RECINPUT")) end
  if #list == 0 then reaper.DeleteExtState(M.SECTION, "inputs " .. tostring(id), true)
  else reaper.SetExtState(M.SECTION, "inputs " .. tostring(id), table.concat(list, ","), true) end
  return #list
end
function M.inputs_for(id) -- (nil: none kept on this computer)
  local s, t = reaper.GetExtState(M.SECTION, "inputs " .. tostring(id)), {}
  for n in s:gmatch("%-?%d+") do t[#t + 1] = tonumber(n) end
  return #t > 0 and t or nil
end
function M.selected_tracks_text() -- the selected tracks (or every track) as a template's text, without media items -> text, how many
  local list = {}
  local n = reaper.CountSelectedTracks(0)
  for i = 0, (n > 0 and n or reaper.CountTracks(0)) - 1 do
    local tr = n > 0 and reaper.GetSelectedTrack(0, i) or reaper.GetTrack(0, i)
    local ok, chunk = reaper.GetTrackStateChunk(tr, "", false)
    if ok then list[#list + 1] = (M.strip_items(chunk):gsub("\n%s*AUXRECV [^\n]*", "")) end -- (receives name tracks by number: not here)
  end
  return table.concat(list), #list
end
function M.project_empty(proj) return reaper.CountMediaItems(proj or 0) == 0 end
-- A new project nothing's been done in, the only kind a workflow sets up: untitled and unchanged (not dirty), with no items, markers,
-- tempo changes or master FX. Its tracks, if any, are the default project template's. (Review, 5.14: with a default template the new tab
-- had tracks and the workflow was skipped; and a saved or changed project with no tracks could be replaced by a workflow's template.)
function M.fresh_project(proj)
  proj = proj or 0
  local fn
  if proj == 0 then fn = select(2, reaper.EnumProjects(-1))
  else for i = 0, 255 do local p, f = reaper.EnumProjects(i); if not p then break end if p == proj then fn = f end end end
  local master = reaper.GetMasterTrack(proj)
  -- (tracks only when you have a default project template: they're its. A script's tracks don't mark a project changed)
  local tmpl = reaper.get_config_var_string and select(2, reaper.get_config_var_string("newprojtmpl")) or ""
  return fn == "" and reaper.IsProjectDirty(proj) == 0 and M.project_empty(proj) and reaper.CountProjectMarkers(proj) == 0
    and reaper.CountTempoTimeSigMarkers(proj) == 0 and (not master or reaper.TrackFX_GetCount(master) == 0)
    and (reaper.CountTracks(proj) == 0 or (tmpl or "") ~= "")
end
-- The screen-reader menu, whatever the window setting: the action 'ReaPersona - screen-reader menu' (a screen-reader user who turned the
-- menu off couldn't get back to it: the switch is in the window. Review, 5.14)
function M.screen_reader_menu()
  reaper.SetExtState(M.SECTION, "menu once", "1", false)
  dofile(M.here .. "/ReaPersona.lua")
end
-- The audio device at the project's rate: restarted once; if the driver still asks for its own rate (Preferences > Device > Request sample
-- rate), that's set to this rate for the driver in use and it's restarted again. -> nil when the device is at the rate, else a note
local DRIVER_RATE = { ASIO = "asio_srate", KS = "ks_srate", DS = "dsound_srate", DSOUND = "dsound_srate", WAVEOUT = "waveout_srate", WASAPI = "wasapi_srate" }
function M.device_rate(sr)
  if not (reaper.Audio_Quit and reaper.Audio_Init) then return nil end
  local function now() local _, d = reaper.GetAudioDeviceInfo("SRATE"); return tonumber(d) end
  if now() == sr then return nil end
  for i = 0, 255 do -- (another tab playing or recording: the device isn't restarted under it)
    local pj = reaper.EnumProjects(i)
    if not pj then break end
    if reaper.GetPlayStateEx(pj) ~= 0 then return " (the audio device wasn't restarted: another project is playing or recording)" end
  end
  reaper.Audio_Quit(); reaper.Audio_Init()
  if now() == sr then return nil end
  local _, mode = reaper.GetAudioDeviceInfo("MODE")
  local key = DRIVER_RATE[tostring(mode or ""):upper():match("^(%a+)") or ""]
  if key and reaper.get_config_var_string and reaper.get_config_var_string(key) and reaper.SNM_SetIntConfigVar then
    reaper.SNM_SetIntConfigVar(key, sr)
    reaper.Audio_Quit(); reaper.Audio_Init()
    if now() == sr then return nil end
  end
  local d = now()
  return " (but the audio device stays at " .. (d and (M.khz(d)) or "its own rate") .. ": set it in Preferences > Audio > Device)"
end
function M.apply_project(st) -- the persona's project part, in the project in front. -> what it did (for the window to say)
  local p, done = st and st.project, {}
  if type(p) ~= "table" then return done end
  local pid = tostring(st.project_id or st.id) -- (a workflow over the persona: the workflow's, for its inputs and "set up")
  local fresh = M.fresh_project(0)
  local empty = fresh -- (below: "still fresh", the rate and starter tracks)
  local added = false
  local _, was = reaper.GetProjExtState(0, M.SECTION, "set up")
  if type(p.template) == "string" and p.template ~= "" and fresh and was ~= pid then
    local f = M.here .. "/_template.RPP"
    if M.write(f, p.template) then
      reaper.Main_openProject("template:" .. f) -- (into this tab, as a new untitled project: a fresh one has nothing to lose, and REAPER would ask if it had)
      os.remove(f)
      reaper.SetProjExtState(0, M.SECTION, "set up", pid) -- (so it isn't loaded again over itself)
      local n = reaper.CountTracks(0)
      done[#done + 1] = "its project template (" .. n .. " track" .. (n == 1 and "" or "s") .. ", recording and render settings, tempo and markers)"
      if reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false) == 1 then
        local r = math.floor(reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) + 0.5)
        local note = M.device_rate(r)
        if note then done[#done + 1] = M.khz(r) .. note end
      end
      empty, added = false, n > 0 -- (its rate and tracks came with it)
    end
  end
  local sr = tonumber(p.srate) or 0
  if sr > 0 and empty and (reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) ~= sr or reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 0, false) ~= 1) then
    reaper.GetSetProjectInfo(0, "PROJECT_SRATE", sr, true)
    reaper.GetSetProjectInfo(0, "PROJECT_SRATE_USE", 1, true) -- (REAPER mixes at the project's rate, not the device's)
    done[#done + 1] = "sample rate " .. M.khz(sr) .. (M.device_rate(sr) or "")
  end
  if type(p.tracks) == "string" and p.tracks ~= "" and empty and was ~= pid then
    local f = M.here .. "/_starter.RTrackTemplate"
    if M.write(f, p.tracks) then
      reaper.Main_openProject(f) -- (a track template opened adds its tracks)
      os.remove(f)
      done[#done + 1] = reaper.CountTracks(0) .. " starter track" .. (reaper.CountTracks(0) == 1 and "" or "s")
      added = reaper.CountTracks(0) > 0
    end
  end
  if added then
    local inputs = M.inputs_for(pid)
    if inputs then
      for i, v in ipairs(inputs) do local tr = reaper.GetTrack(0, i - 1); if tr then reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", v) end end
      done[#done + 1] = "this computer's track inputs"
    end
    local miss = M.fx_missing(M.fx_needed(p.template or p.tracks))
    if #miss > 0 then done[#done + 1] = "not on this computer: " .. table.concat(miss, ", ") end
  end
  local w = tonumber(p.wset) or 0
  if w >= 1 and w <= 10 then reaper.Main_OnCommand(M.WSET_LOAD + w - 1, 0); done[#done + 1] = "window set #" .. w end
  if st.colours and st.colours["colour look"] and #done > 0 and reaper.CountTracks(0) > 0 then -- (the tracks it brought, in its colours)
    local ok, n = pcall(function() return M.colours().colour_project(0, st.colours) end)
    if ok and n and n > 0 then done[#done + 1] = M.colours_label(st.colours):lower() elseif not ok then M.log("colouring the new project: " .. tostring(n)) end
  end
  return done
end
-- Starter workflows for the Builder: a project block and settings blocks, each set the way that kind of session usually wants.
local function settings_with(group, want) -- a settings block that sets only these items (by their first command) and leaves the rest
  local b = { kind = "settings", group = group, values = {} }
  for i, item in ipairs((M.setting_group(group) or { items = {} }).items) do
    local key = type(item[1]) == "table" and item[1][1] or item[1]
    b.values[i] = want[key] == nil and -1 or want[key]
  end
  return b
end
M.WORKFLOWS = {
  { id = "voiceover", name = "Voiceover (48 kHz)", tip = "Video voiceover: a 48 kHz project with one armed mono track (monitoring off), ripple editing per track so cuts close the gap, auto-crossfades, no click.",
    blocks = function() return {
      { kind = "project", name = "Voiceover", srate = 48000, tracks = M.track_chunk("Voiceover", true, false, 0), tracks_name = "Voiceover (armed, mono input 1)", wset = 0 },
      settings_with("editing", { [40309] = 2, [40041] = 1, [1157] = 0 }),
      settings_with("recording", { [40252] = 1, [40300] = 1, [40364] = 0, [41819] = 1 }),
      settings_with("playback", { [40364] = 0, [1068] = 0 }) } end },
  { id = "podcast", name = "Podcast (48 kHz)", tip = "Two armed mono tracks, Host and Guest, at 48 kHz, ripple editing across all tracks, no click.",
    blocks = function() return {
      { kind = "project", name = "Podcast", srate = 48000, tracks = M.track_chunk("Host", true, false, 0) .. M.track_chunk("Guest", true, false, 1), tracks_name = "Host and Guest (armed, inputs 1 and 2)", wset = 0 },
      settings_with("editing", { [40309] = 3, [40041] = 1, [1157] = 0 }),
      settings_with("playback", { [40364] = 0 }) } end },
  { id = "music", name = "Music (44.1 kHz)", tip = "A 44.1 kHz project with snap on and the click ready.",
    blocks = function() return {
      { kind = "project", name = "Music", srate = 44100, tracks = "", tracks_name = "", wset = 0 },
      settings_with("editing", { [1157] = 1, [40309] = 1 }),
      settings_with("playback", { [40364] = 1 }) } end },
  { id = "looping", name = "Live looping", tip = "Loop playback on, every pass a new take, a bar of count-in, the click on, and four armed loop tracks with monitoring on.",
    blocks = function() return {
      { kind = "project", name = "Live looping", srate = 0, tracks = M.track_chunk("Loop 1", true, true, 0) .. M.track_chunk("Loop 2", true, true, 0) ..
        M.track_chunk("Loop 3", true, true, 0) .. M.track_chunk("Loop 4", true, true, 0), tracks_name = "Loop 1-4 (armed, monitoring on)", wset = 0 },
      settings_with("playback", { [1068] = 1, [40364] = 1, [41817] = 0 }),
      settings_with("recording", { [40114] = 1, ["_SWS_AWCOUNTRECTOG"] = 1, [41330] = 1 }),
      settings_with("monitoring", { [41583] = 1 }) } end },
  { id = "mixing", name = "Mixing", tip = "The project's own rate, no click, the loop following the time selection, FX and sends shown on tracks and in the mixer, and FX running while stopped.",
    blocks = function() return {
      settings_with("playback", { [40364] = 0, [40621] = 1, [1068] = 1 }),
      settings_with("view", { [40302] = 1, [40677] = 1 }),
      settings_with("mixer", { [40549] = 1, [40557] = 1, [40389] = 1, [40745] = 1 }),
      settings_with("monitoring", { [41583] = 1 }) } end },
  { id = "mastering", name = "Mastering", tip = "One Mix track, waveforms coloured by loudness, snap and ripple off, auto-crossfades on, no click.",
    blocks = function() return {
      { kind = "project", name = "Mastering", srate = 0, tracks = M.track_chunk("Mix", false, false, 1024), tracks_name = "Mix (stereo)", wset = 0 },
      settings_with("editing", { [1157] = 0, [40309] = 1, [40041] = 1 }),
      settings_with("view", { [43145] = 1 }),
      settings_with("playback", { [40364] = 0 }),
      settings_with("monitoring", { [41884] = 0 }) } end },
  { id = "video", name = "Video post (48 kHz)", tip = "A 48 kHz project with Dialogue, Music and Effects tracks, the ruler in timecode, snap and ripple off, following the playhead.",
    blocks = function() return {
      { kind = "project", name = "Video post", srate = 48000, tracks = M.track_chunk("Dialogue", false, false, 0) .. M.track_chunk("Music", false, false, 1024) ..
        M.track_chunk("Effects", false, false, 1024), tracks_name = "Dialogue, Music and Effects", wset = 0 },
      settings_with("view", { [40366] = 4 }),
      settings_with("editing", { [1157] = 0, [40309] = 1 }),
      settings_with("playback", { [40036] = 1, [40364] = 0 }) } end },
}
function M.workflow(id) for _, w in ipairs(M.WORKFLOWS) do if w.id == id then return w end end end
-- ---------------------------------------------------------------- a workflow on top of the persona in use (5.16)
-- (Review, 5.14: "workflows can't sit on top of another persona": a Pro Tools user had to build a persona to add Voiceover.) A workflow
-- picked on its own goes over whatever persona is in use: its settings after the persona's (so they win where both set one) and its
-- project part in place of the persona's. Only a project part and REAPER toggle actions: never keys, theme, windows or the mouse.
-- The pick is each computer's own ("workflow", like the persona in use): a starter's id, or one of your personas with a project part,
-- which brings that project part and its Builder settings blocks.
local layers = {}
function M.workflow_list() -- -> { id, name, tip, mine } for every workflow you can pick
  local out = {}
  for _, w in ipairs(M.WORKFLOWS) do out[#out + 1] = { id = w.id, name = w.name, tip = w.tip } end
  for _, st in ipairs(M.styles) do if st.user and (st.project or st.colours) then out[#out + 1] = { id = st.id, name = st.name, tip = st.description, mine = true } end end
  for _, st in ipairs(M.presets) do if st.project or st.colours then out[#out + 1] = { id = st.id, name = st.name, tip = st.description, mine = true } end end
  return out
end
function M.workflow_layer(id) -- -> { id, name, feel, project } or nil
  if not id or id == "" then return nil end
  local w, st = M.workflow(id), M.by_id(id)
  local src = w or st
  if not src or (not w and not st.project and not st.colours) then return nil end
  if layers[id] and layers[id].src == src then return layers[id] end
  local blocks = {}
  if w then blocks = w.blocks()
  else for _, b in ipairs(st.blocks or {}) do if b.kind == "settings" or b.kind == "colours" then blocks[#blocks + 1] = b end end end
  local built = M.build_style(blocks, src.name, "workflow_" .. id)
  local feel = {}
  for _, f in ipairs(built and built.feel or {}) do if f[1] == "toggle" or f[1] == "choice" then feel[#feel + 1] = f end end -- (toggle actions only)
  layers[id] = { src = src, id = id, name = src.name, feel = feel, project = w and built and built.project or (st and st.project),
    colours = (built and built.colours) or (st and st.colours) }
  return layers[id]
end
function M.current_workflow() return M.workflow_layer(reaper.GetExtState(M.SECTION, "workflow")) end
function M.layered(st) -- the persona with the workflow in use over it (a copy), or the persona itself
  local w = st and not st.workflow and M.current_workflow()
  if not w or w.id == st.id then return st end
  local t = {}
  for k, v in pairs(st) do t[k] = v end
  t.feel = {}
  for _, f in ipairs(st.feel or {}) do t.feel[#t.feel + 1] = f end
  for _, f in ipairs(w.feel) do t.feel[#t.feel + 1] = f end -- (after the persona's: the workflow's win, and switching away puts back both)
  if w.project then t.project, t.project_id = w.project, w.id end -- (no project part, as Mixing: the persona's own stays)
  if w.colours then t.colours = w.colours end -- (its colour look over the persona's)
  t.workflow = w
  return t
end
function M.set_workflow(id) -- "" for none: the persona in use goes on again with it. -> true, or nil + why
  id = id or ""
  if id ~= "" and not M.workflow_layer(id) then return nil, "there's no workflow " .. id end
  reaper.SetExtState(M.SECTION, "workflow", id, true)
  M.use(M.current())
  return true
end

-- Whose shortcut layer a built persona's keys are on. Borrowing a DAW's layer is only for one DAW's keys taken whole: one with some keys
-- left out took the whole layer anyway, and changing the keys of one of yours on a borrowed layer changed that DAW's too. So keys from
-- several DAWs (another's mouse wheel included), keys left out, or a persona that has a layer of its own already (its keys may have been
-- changed there) get a layer of their own. Review, 5.9.3; the mouse, 5.10. -> "none" (your own keys), "borrow" or "own"; the DAW ids;
-- the layer it keeps, if any
function M.keys_layer(blocks, id)
  local per, daws, count = M.build_preview(blocks), {}, {}
  for i, b in ipairs(blocks) do
    for _, e in ipairs(per[i]) do
      if (e.kind == "key" or e.kind == "midi") and not e.off and not e.lost_to then
        if not count[b.id] then count[b.id] = 0; daws[#daws + 1] = b.id end
        count[b.id] = count[b.id] + 1
      end
    end
  end
  local old = id and M.by_id(id)
  local own = old and old.user and not old.keys_from and (old.alt or 0) > 0 and old.alt or nil
  if #daws == 0 then return "none", daws end
  local st = M.by_id(daws[1])
  if #daws == 1 and not own and count[daws[1]] == #M.keys_here(st.keys) + #(st.midi_keys or {}) then return "borrow", daws end
  return "own", daws, own
end
-- One of yours on a DAW's layer gets a copy of those keys on a layer of its own, so changing them in REAPER's Actions window changes
-- yours and not the DAW's (Review, 5.9.3). Its keys go in at the next shortcut install. -> the persona, or nil + why
function M.own_layer(st)
  if not (st and st.user and st.keys_from) then return st end
  local a = free_alt()
  if not a then return nil, "all 16 shortcut layers are in use" end
  local was = { st.keys, st.midi_keys, st.alt, st.keys_from }
  st.keys, st.midi_keys, st.alt, st.keys_from = copy(st.keys), copy(st.midi_keys), a, nil
  local ok, why = save_user_style(st)
  if not ok then st.keys, st.midi_keys, st.alt, st.keys_from = table.unpack(was) end
  return ok, why
end
function M.save_built(blocks, name, id) -- -> the persona, true when its shortcuts need installing; or nil + why
  local st, install = M.build_style(blocks, name, id)
  if not st then return nil, install end
  local ok, why = save_user_style(st)
  if not ok then return nil, why end
  return st, install
end

-- ---------------------------------------------------------------- a persona per project
-- A project can name its persona (kept in the project file). With "switch with the project" on (Settings), the "follow projects" action
-- runs in the background and switches persona when you change project tab or open a project.
function M.project_persona(proj) local _, v = reaper.GetProjExtState(proj or 0, M.SECTION, "persona"); return v ~= "" and v or nil end
function M.set_project_persona(id) reaper.SetProjExtState(0, M.SECTION, "persona", id or "") end
function M.follow_on() return reaper.GetExtState(M.SECTION, "follow projects") == "1" end
function M.watch_on() local cur = M.layered(M.current()); return M.follow_on() or (cur ~= nil and cur.project ~= nil) end -- (the loop has work to do)
function M.start_following()
  local id = cmd_id(M.scripts.main["follow projects"] or "")
  if id ~= 0 then reaper.Main_OnCommand(id, 0) end
end
function M.follow_projects()
  if reaper.time_precise() - (tonumber(reaper.GetExtState(M.SECTION, "follow beat")) or -9) < 1.5 then return end -- (one runs already)
  local C, last = M, nil
  reaper.atexit(function() reaper.DeleteExtState(M.SECTION, "follow beat", false) end)
  local function step()
    local cur = C.layered(C.current()) -- (with the workflow in use: its project part)
    if not (M.follow_on() or (cur and cur.project)) then return end
    reaper.SetExtState(M.SECTION, "follow beat", tostring(reaper.time_precise()), false)
    local p, fn = reaper.EnumProjects(-1)
    local key = tostring(p) .. "|" .. tostring(fn)
    if key ~= last and not C.busy() then
      local first = last == nil
      last = key
      local want = M.follow_on() and (M.project_persona(p) or reaper.GetExtState(M.SECTION, "project default")) or ""
      if want ~= "" and want ~= reaper.GetExtState(M.SECTION, "style") then
        if not C.by_id(want) then C = dofile(M.here .. "/reapersona_core.lua") end -- (a persona made since this started)
        if C.by_id(want) then C.use_id(want) end
      elseif not first and fn == "" and cur and cur.project and C.fresh_project(p) then
        C.apply_project(cur) -- (a new, empty project: the workflow's rate and starter tracks)
      end
    end
    reaper.defer(step)
  end
  step()
end
function M.presets_on(id) -- names of your presets and mixes built on a style
  local out = {}
  for _, p in ipairs(load_presets()) do if p.base == id or p.feel_from == id then out[#out + 1] = p.name end end
  return out
end
function M.delete_user_style(id) -- -> true, or nil + why. Its "use" action goes too; if it's in use, My REAPER takes over.
  local users = load(USERS)
  if bad[USERS] then return nil, "user_styles.json doesn't parse, so it isn't written over" end
  for n = #users, 1, -1 do if users[n].id == id then table.remove(users, n) end end
  local ok, why = M.save_json(USERS, { styles = users })
  if not ok then return nil, why end
  if reaper.GetExtState(M.SECTION, "workflow") == id then reaper.SetExtState(M.SECTION, "workflow", "", true) end
  if reaper.GetExtState(M.SECTION, "style") == id then M.use(M.by_id("my_reaper") or M.styles[1]) end
  for n = #M.styles, 1, -1 do if M.styles[n].id == id and M.styles[n].user then table.remove(M.styles, n) end end
  M.remove_script("use " .. id)
  return true
end

-- ---------------------------------------------------------------- shortcuts without Python: a .ReaperKeyMap to import
-- (Actions > Key Map > Import, merge.) The same lines install_shortcuts.py writes; it also moves your own MIDI editor lines for the
-- styles' MIDI keys into midi_fallback.json so My REAPER keeps them. Toolbars still need install_shortcuts.py (REAPER closed).
local VIRT, SHIFT, CTRL, ALT, WIN, EXT = 1, 4, 8, 16, 32, 32768 -- (WIN: the Windows key; Control on a Mac)
M.IS_MAC = tostring(reaper.GetOS()):find("^OSX") ~= nil or tostring(reaper.GetOS()):find("^macOS") ~= nil
function M.for_os(spec) -- a key or mouse context for one system only is written "mac:..." / "win:...": -> it for this system, or nil
  if type(spec) ~= "string" then return spec end
  local os_, rest = spec:match("^(%a%a%a):(.+)$")
  if os_ == "mac" then return M.IS_MAC and rest or nil elseif os_ == "win" then return (not M.IS_MAC) and rest or nil end
  return spec
end
-- Keys macOS keeps for itself (REAPER's Ctrl is Cmd and Alt is Option there): a persona key on one never reaches REAPER. Review 5.14.
M.MAC_TAKEN = { ["Ctrl+Space"] = "Spotlight", ["Ctrl+H"] = "hides REAPER", ["Ctrl+M"] = "minimizes the window", F11 = "Show Desktop", ["Ctrl+Alt+D"] = "hides the Dock" }
function M.mac_taken(keys) -- -> "Cmd+Space (Spotlight)", ... for the keys given that macOS takes (pure; the keys as in styles.json)
  local want, out = {}, {}
  for k, what in pairs(M.MAC_TAKEN) do want[canon(k)] = what end
  for _, k in ipairs(keys or {}) do
    local spec = tostring(k[1])
    if not spec:match("^win:") then
      spec = spec:gsub("^mac:", "")
      local what = want[canon(spec)]
      if what then out[#out + 1] = (canon(spec):gsub("Ctrl", "Cmd"):gsub("Alt", "Option")) .. " (" .. what .. ")" end
    end
  end
  table.sort(out)
  return out
end
function M.keys_here(list) -- a style's keys for this system, with the "mac:"/"win:" mark taken off
  local out = {}
  for _, k in ipairs(list or {}) do
    local s = M.for_os(k[1])
    if s then if s == k[1] then out[#out + 1] = k else local c = { table.unpack(k) }; c[1] = s; out[#out + 1] = c end end
  end
  return out
end
local NAMED = { Space = 32, Enter = 13, Backspace = 8, Tab = 9, Esc = 27, Left = EXT + 37, Up = EXT + 38, Right = EXT + 39, Down = EXT + 40,
  Home = EXT + 36, End = EXT + 35, PgUp = EXT + 33, PgDn = EXT + 34, Insert = EXT + 45, Delete = EXT + 46,
  ["Num*"] = 106, ["Num+"] = 107, ["Num-"] = 109, ["Num."] = 110, ["Num/"] = 111, NumEnter = EXT + 13 }
for i = 1, 12 do NAMED["F" .. i] = 111 + i end
for i = 0, 9 do NAMED["Num" .. i] = 96 + i end
local OEM = { ["?"] = 191, [";"] = 186, ["="] = 187, ["+"] = 187, [","] = 188, ["-"] = 189, ["."] = 190, ["/"] = 191, ["`"] = 192,
  ["["] = 219, ["\\"] = 220, ["]"] = 221, ["'"] = 222 }
-- The mouse wheel as a shortcut (James, 5.9.5: "can the mouse controls be part of reapersona?"): flags 255, and a key that's the wheel's
-- base, 248 for the wheel and 216 for the horizontal one, plus Ctrl 1, Alt 2, Shift 4 (as REAPER writes them: 248 Mousewheel, 251
-- Ctrl+Alt+Mousewheel, 218 Alt+HorizWheel; the full table from the Ultraschall reaper-kb.ini description). REAPER 7 also writes a long
-- form, the same code plus a multiple of 256 (2044 for Shift+Mousewheel, on the desktop), so reading looks at the low byte. The Windows
-- key has no wheel code: a wheel shortcut with Win is skipped.
local WHEELS, WHEEL_MODS = { Mousewheel = 248, HorizWheel = 216 }, { Ctrl = 1, Alt = 2, Shift = 4 }
function M.wheel_code(spec) -- "Shift+Mousewheel" (modifiers in any order) -> 255, 252; or nil
  local mods, key = M.split_spec(spec)
  local base = WHEELS[key]
  if not base then return nil end
  local add = 0
  for m in mods:gmatch("[^+]+") do
    local v = WHEEL_MODS[m]
    if not v then return nil end
    add = add | v
  end
  return 255, base + add
end
function M.is_wheel(spec) return type(spec) == "string" and M.wheel_code(M.for_os(spec) or spec) ~= nil end -- (a persona's key that's the wheel)
function M.wheel_name(k) -- a wheel key as reaper-kb.ini has it (short or long form) -> "Ctrl+Shift+Mousewheel", or nil
  k = tonumber(k)
  if not k then return nil end
  k = k & 0xFF
  local base = k >= 248 and 248 or (k >= 216 and k < 224) and 216 or nil
  if not base then return nil end
  local add, mods = k - base, {}
  for _, m in ipairs({ { "Ctrl", 1 }, { "Alt", 2 }, { "Shift", 4 } }) do if add & m[2] ~= 0 then mods[#mods + 1] = m[1] end end
  mods[#mods + 1] = base == 248 and "Mousewheel" or "HorizWheel"
  return table.concat(mods, "+")
end
function M.encode(spec) -- "Ctrl+Shift+L" -> flags, key as reaper-kb.ini writes them (same as install_shortcuts.encode), or nil
  local wf, wk = M.wheel_code(spec)
  if wf then return wf, wk end
  local mods, key = M.split_spec(spec)
  local flags = 0
  for m in mods:gmatch("[^+]+") do
    local f = ({ Shift = SHIFT, Ctrl = CTRL, Alt = ALT, Win = WIN })[m]
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
    elseif sec == "32060" and cmd ~= "0" and not midi_cmds[cmd] and not line:find("MIDI key", 1, true) then -- ("0": REAPER disabled it, not you)
      midi_user[f .. " " .. k] = { cmd = cmd, line = line }
    end
  end
  local out, skipped, specs = {}, {}, {}
  for _, st in ipairs(M.styles) do
    local alt = st.alt or 0
    if alt >= 1 and alt <= 16 then
      for _, k in ipairs(M.keys_here(st.keys)) do
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
  local fbj = M.load_json(M.here .. "/midi_fallback.json")
  if not fbj then return nil, 0, { "midi_fallback.json doesn't parse, so it isn't written over (a copy is next to it)" } end
  local fb = setmetatable(fbj, M.OBJECT)
  if not reaper.file_exists(M.here .. "/midi_defaults.json") then M.midi_defaults() end
  local defaults = M.load_json(M.here .. "/midi_defaults.json") or {}
  for spec in pairs(specs) do
    local f, key = M.encode(spec)
    local cmd = M.scripts.midi[spec]
    if f and cmd then
      if not fb[spec] or tostring(fb[spec].cmd) == "0" then
        local mine = midi_user[f .. " " .. key]
        fb[spec] = mine or (defaults[spec] and { cmd = tostring(defaults[spec]) }) or nil
      end
      out[#out + 1] = string.format("KEY %d %d %s 32060", f, key, cmd)
    else skipped[#skipped + 1] = "MIDI " .. spec end
  end
  local saved, why = M.save_json(M.here .. "/midi_fallback.json", fb)
  if not saved then return nil, 0, { why } end
  reaper.RecursiveCreateDirectory(res .. "/KeyMaps", 0)
  local p = res .. "/KeyMaps/ReaPersona shortcuts.ReaperKeyMap"
  M.write(p, table.concat(out, "\n") .. "\n")
  return p, #out, skipped
end
-- ---------------------------------------------------------------- the one-button install without Python (Windows 5.14, Mac and Linux 5.16)
-- install_shortcuts.py's run() and install_toolbars() in Lua, rule for rule (keep the two in step): planned while REAPER runs, from the
-- keymap and menus as they are now. The new files wait in ReaPersona/install_staged next to a copy of each file as it was read, and a
-- swap step (a cmd batch file on Windows, a /bin/sh script on a Mac or Linux) waits for this REAPER to close,
-- swaps them in only if nothing changed them since, backs each up first, and starts REAPER again. Preferences from your other computers
-- (pending/prefs.json) stay waiting for the Python route: REAPER writes reaper.ini as it quits, so they can't be planned beforehand.
local KB_TAG, KB_OLD_TAG = "# ReaPersona", "# DAW Styles"
local function words(l) local t = {}; for w in l:gmatch("%S+") do t[#t + 1] = w end return t end
local function idstr(v) local i = math.tointeger(v); return i and string.format("%d", i) or tostring(v) end -- (40001, not 40001.0)
local function lines_of(text) -- Python's text.replace("\r\n", "\n").split("\n"): exact lines, a last "" after a final newline
  local t = {}
  for l in ((text or ""):gsub("\r\n", "\n") .. "\n"):gmatch("([^\n]*)\n") do t[#t + 1] = l end
  return t
end
local function splitlines(text) local t = lines_of(text); if #t > 0 and t[#t] == "" then t[#t] = nil end return t end
function M.kb_slot(line) -- what a keymap line binds: "KEY flags key section", "SCR section id", "ACT section id"; or nil (pure)
  local p = words(line)
  if #p >= 5 and p[1] == "KEY" then return "KEY " .. p[2] .. " " .. p[3] .. " " .. p[5] end
  if #p >= 4 and (p[1] == "SCR" or p[1] == "ACT") then return p[1] .. " " .. p[3] .. " " .. p[4] end
end
function M.kb_takeable(line, mine_scripts) -- as install_shortcuts.kb_takeable: whether another computer's keymap line may come in (pure)
  local p = words(line)
  if p[1] ~= "KEY" or #p < 5 then return true end
  local cmd, sec = p[4], p[5]
  if (sec:match("^%d+$") and tonumber(sec) >= 1 and tonumber(sec) <= 16) or cmd == "0" then return false end
  local bare = cmd:gsub("^_+", "")
  return not bare:match("^RS") or mine_scripts[bare] == true
end
function M.merge_kb(mine, theirs) -- this computer's keymap with the other computer's lines taken in (pure; LF)
  local mine_scripts = {}
  for _, l in ipairs(splitlines(mine)) do local p = words(l); if p[1] == "SCR" and #p > 3 then mine_scripts[p[4]] = true end end
  local take, slots = {}, {}
  for _, l in ipairs(splitlines(theirs)) do
    if M.kb_slot(l) and not l:match("^SCR ") and M.kb_takeable(l, mine_scripts) then take[#take + 1] = l; slots[M.kb_slot(l)] = true end
  end
  local keep = {}
  for _, l in ipairs(splitlines(mine)) do if not (M.kb_slot(l) and slots[M.kb_slot(l)]) then keep[#keep + 1] = l end end
  while #keep > 0 and keep[#keep]:match("^%s*$") do keep[#keep] = nil end
  for _, l in ipairs(take) do keep[#keep + 1] = l end
  return table.concat(keep, "\n") .. "\n"
end
function M.merge_ini(mine, theirs) -- this computer's ini file with the other computer's sections taken in whole (pure; LF)
  local function sections(text)
    local order, secs, cur = {}, {}, nil
    for _, l in ipairs(splitlines(text)) do
      local name = l:match("^%[(.+)%]%s*$")
      if name then cur = name; if not secs[cur] then secs[cur] = {}; order[#order + 1] = cur end
      elseif cur and l:match("%S") then table.insert(secs[cur], l) end
    end
    return order, secs
  end
  local order, secs = sections(mine)
  local t_order, t_secs = sections(theirs)
  for _, n in ipairs(t_order) do if not secs[n] then order[#order + 1] = n end secs[n] = t_secs[n] end
  local out = {}
  for _, n in ipairs(order) do out[#out + 1] = "[" .. n .. "]\n"; for _, l in ipairs(secs[n]) do out[#out + 1] = l .. "\n" end end
  return table.concat(out)
end

-- The keymap with every style's lines planned in (install_shortcuts.run, steps 1-3). Pure. kb: reaper-kb.ini's text; styles: styles.json's
-- and user_styles.json's; scripts: scripts.json; manifest: installed.json's lines (or nil); old_fb: midi_fallback.json; defaults:
-- midi_defaults.json (or nil). -> the new text, the lines written (installed.json), the MIDI fallback, how many added, warnings
function M.kb_plan(kb, styles, scripts, manifest, old_fb, defaults, remove, no_midi, windows)
  local warnings, plan, midi_specs = {}, {}, {}
  scripts = scripts or {}
  for _, st in ipairs(remove and {} or styles) do
    local alt = tonumber(st.alt) or 0
    for _, e in ipairs((alt >= 1 and alt <= 16) and (st.keys or {}) or {}) do
      local spec, cmd, what = M.for_os(e[1]), e[2], e[3]
      if spec then
        local why
        if type(cmd) == "string" and cmd:match("^script:") then
          cmd = (scripts.main or {})[cmd:sub(8)]
          if not cmd then why = "open"; warnings[#warnings + 1] = string.format("%s %s: open the ReaPersona picker once first (registers its actions)", st.name, spec) end
        end
        if not why then
          if type(cmd) == "string" and cmd:match("^MAIN:") then if not M.encode(cmd:sub(6)) then why = "unknown key: " .. cmd:sub(6) end
          elseif not (math.tointeger(cmd) or (type(cmd) == "string" and cmd ~= "" and not cmd:find("%s"))) then why = "bad command " .. tostring(cmd) end
          local f, k = M.encode(spec)
          if not f then why = why or ("unknown key: " .. spec) end
          if why then warnings[#warnings + 1] = string.format("%s: skipped key %s (%s)", tostring(st.name), tostring(e[1]), why)
          else plan[#plan + 1] = { f, k, idstr(cmd), alt, string.format("%s : %s : %s : %s", KB_TAG, st.name, spec, tostring(what)) } end
        end
      end
    end
    for _, mk in ipairs(st.midi_keys or {}) do
      if type(mk) == "table" and type(mk[1]) == "string" and M.encode(mk[1]) then
        midi_specs[mk[1]] = midi_specs[mk[1]] or {}
        table.insert(midi_specs[mk[1]], st.name)
      else warnings[#warnings + 1] = string.format("%s: skipped MIDI key %s", tostring(st.name), tostring(type(mk) == "table" and mk[1] or mk)) end
    end
  end
  if no_midi or (defaults == nil and not remove) then -- (without REAPER's own MIDI editor defaults, a My REAPER key would lose what it did)
    if not no_midi then warnings[#warnings + 1] = "MIDI editor keys: no midi_defaults.json yet (open REAPER, picker > Check), so they weren't installed" end
    midi_specs = {}
  end
  old_fb = type(old_fb) == "table" and old_fb or {}
  local eol = ((kb or ""):find("\r\n", 1, true) or ((kb or "") == "" and windows)) and "\r\n" or "\n"
  local lines = lines_of(kb)
  local man = nil
  if type(manifest) == "table" then man = {}; for _, l in ipairs(manifest) do man[l] = true end end
  local midi_cmds, midi_keys = {}, {}
  for _, id in pairs(scripts.midi or {}) do midi_cmds[idstr(id)] = true end
  for _, src in ipairs({ midi_specs, old_fb }) do
    for spec in pairs(src) do local f, k = M.encode(tostring(spec)); if f then midi_keys[f .. " " .. k] = true end end
  end
  local function ours(line)
    if line:find(KB_TAG, 1, true) or line:find(KB_OLD_TAG, 1, true) then return true end
    local q = words(line)
    if #q < 5 or q[1] ~= "KEY" then return false end
    if q[5] == tostring(MIDI_SEC) then -- (a "0 ... DISABLED DEFAULT" line on one of our MIDI keys: REAPER wrote it when a key script moved)
      return midi_cmds[q[4]] or (line:find("MIDI key", 1, true) and (line:find("Script: ReaPersona", 1, true) or line:find("Script: DAW Styles", 1, true)))
        or (q[4] == "0" and midi_keys[q[2] .. " " .. q[3]]) or false
    end
    return man ~= nil and man[table.concat(q, " ", 2, 5)] == true
  end
  local kept = {}
  for _, l in ipairs(lines) do if not ours(l) then kept[#kept + 1] = l end end
  while #kept > 0 and kept[#kept] == "" do kept[#kept] = nil end
  local fb_specs = {}
  for spec in pairs(old_fb) do fb_specs[#fb_specs + 1] = tostring(spec) end
  table.sort(fb_specs)
  for _, spec in ipairs(fb_specs) do -- (your own MIDI editor lines a previous install moved aside)
    local v = old_fb[spec]
    if type(v) == "table" and type(v.line) == "string" and v.line ~= "" and not ours(v.line) then kept[#kept + 1] = v.line end
  end
  local added, written, fallback, yours = 0, {}, setmetatable({}, M.OBJECT), {}
  local osara, skipped = {}, 0 -- (OSARA's keys stay OSARA's: a persona key over one took a screen-reader user's navigation and reports away. Review 5.14)
  for _, l in ipairs(kept) do
    local q = words(l)
    if q[1] == "KEY" and #q >= 5 then
      yours[q[2] .. " " .. q[3] .. " " .. q[5]] = true
      if q[4]:sub(1, 6) == "_OSARA" then osara[q[2] .. " " .. q[3] .. " " .. q[5]] = true end
    end
  end
  for _, p in ipairs(plan) do
    local f, k, cmd, alt, comment = table.unpack(p)
    local mine = yours[f .. " " .. k .. " " .. alt]
    if not mine and osara[f .. " " .. k .. " 0"] then skipped = skipped + 1; mine = true end
    if not mine then -- (you rebound this key in the style's layer: yours stays)
      if cmd:match("^MAIN:") then -- (what the Main section runs on that key now, so a style's Undo/Redo is still StudioSync's)
        local mf, mk = M.encode(cmd:sub(6))
        local found
        for _, l in ipairs(kept) do
          local q = words(l)
          if #q >= 5 and q[1] == "KEY" and q[2] == tostring(mf) and q[3] == tostring(mk) and q[5] == "0" and q[4] ~= "0" then found = q[4]; break end
        end
        cmd = found or tostring(({ ["Ctrl+Z"] = 40029, ["Ctrl+Shift+Z"] = 40030 })[cmd:sub(6)] or 0)
      end
      kept[#kept + 1] = string.format("KEY %d %d %s %d\t\t %s", f, k, cmd, alt, comment)
      written[#written + 1] = string.format("%d %d %s %d", f, k, cmd, alt)
      added = added + 1
    end
  end
  local specs = {}
  for spec in pairs(midi_specs) do specs[#specs + 1] = spec end
  table.sort(specs)
  for _, spec in ipairs(specs) do
    local cmd = (scripts.midi or {})[spec]
    local f, k = M.encode(spec)
    if not cmd then warnings[#warnings + 1] = "MIDI " .. spec .. ": open the ReaPersona picker once first (registers the MIDI key scripts)"
    elseif osara[f .. " " .. k .. " " .. MIDI_SEC] then skipped = skipped + 1
    else
      for n = #kept, 1, -1 do
        local q = words(kept[n])
        if #q >= 5 and q[1] == "KEY" and q[2] == tostring(f) and q[3] == tostring(k) and q[5] == tostring(MIDI_SEC) and not ours(kept[n]) then
          fallback[spec] = { cmd = q[4], line = kept[n] }
          table.remove(kept, n)
        end
      end
      if not fallback[spec] and defaults and defaults[spec] then fallback[spec] = { cmd = idstr(defaults[spec]) } end -- (REAPER's built-in binding: kb.ini only holds changes)
      kept[#kept + 1] = string.format("KEY %d %d %s %d\t\t %s : MIDI editor : %s : %s", f, k, idstr(cmd), MIDI_SEC, KB_TAG, spec, table.concat(midi_specs[spec], ", "))
      added = added + 1
    end
  end
  if skipped > 0 then warnings[#warnings + 1] = "kept OSARA's keys: " .. skipped .. " persona key(s) left out" end
  return (table.concat(kept, "\n") .. "\n"):gsub("\n", eol), written, fallback, added, warnings
end

-- reaper-menu.ini with each style's toolbars in their slots (install_shortcuts.install_toolbars). Pure. read_toolbar(file) -> a .ReaperMenu's
-- text from toolbars/, or nil. -> the new text, how many written
function M.menu_plan(menu, styles, remove, read_toolbar, warnings)
  local eol = (menu or ""):find("\r\n", 1, true) and "\r\n" or "\n"
  local secs = { { nil, {} } }
  for _, l in ipairs(lines_of(menu)) do
    if l:match("^%[") and l:match("%]%s*$") then secs[#secs + 1] = { l:match("^%s*(.-)%s*$"), {} } else table.insert(secs[#secs][2], l) end
  end
  local function ours(body) for _, l in ipairs(body) do if l:match("^title=ReaPersona") or l:match("^title=DAW Styles") then return true end end end
  for n = #secs, 1, -1 do if secs[n][1] and secs[n][1]:match("^%[Floating") and ours(secs[n][2]) then table.remove(secs, n) end end
  local written = 0
  for _, st in ipairs(remove and {} or styles) do
    for _, kind in ipairs({ { "toolbar_slot", "toolbar_file", "toolbar", "[Floating toolbar %d]", "" },
                            { "midi_toolbar_slot", "midi_toolbar_file", "midi_toolbar", "[Floating MIDI toolbar %d]", " piano roll" } }) do
      local slot, file, list = math.tointeger(st[kind[1]]), st[kind[2]], st[kind[3]]
      if slot and slot ~= 0 and (file or list) then
        local h, body = string.format(kind[4], slot), nil
        local text = file and read_toolbar(file)
        local taken = false
        for _, s in ipairs(secs) do if s[1] == h then for _, l in ipairs(s[2]) do if l:match("^item_") then taken = true end end end end
        if file and not text then warnings[#warnings + 1] = string.format("%s: toolbars/%s isn't here (from its theme pack), so it keeps your toolbar", st.name, file)
        elseif taken then warnings[#warnings + 1] = string.format("%s already holds one of your toolbars: %s's not written", h, st.name)
        else
          body = {}
          if file then
            local on = false
            for _, l in ipairs(splitlines(text)) do
              if l:match("^%[") then if on then break end on = true
              elseif on and l ~= "" and not l:match("^title=") then body[#body + 1] = l end
            end
          else
            for i, it in ipairs(list) do
              if it == -1 then body[#body + 1] = string.format("item_%d=-1", i - 1)
              else
                if it[3] then body[#body + 1] = string.format("icon_%d=%s", i - 1, idstr(it[3])) end
                body[#body + 1] = string.format("item_%d=%s %s", i - 1, idstr(it[1]), idstr(it[2]))
              end
            end
          end
          body[#body + 1] = "title=ReaPersona: " .. st.name .. kind[5]
          body[#body + 1] = ""
          for n = #secs, 1, -1 do if secs[n][1] == h then table.remove(secs, n) end end
          secs[#secs + 1] = { h, body }
          written = written + 1
        end
      end
    end
  end
  local out = {}
  for _, s in ipairs(secs) do if s[1] then out[#out + 1] = s[1] end for _, l in ipairs(s[2]) do out[#out + 1] = l end end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  return (table.concat(out, "\n") .. "\n"):gsub("\n", eol), written
end

function M.pid_from_tasklist(out, title) -- `tasklist /V /FO CSV /NH` rows for reaper.exe -> this REAPER's process id (by its main window's title), or nil (pure)
  local rows, hit = {}, nil
  for line in (out or ""):gmatch("[^\r\n]+") do
    local pid = line:match('^"[^"]*","(%d+)"')
    if pid then rows[#rows + 1] = { pid, line:match('"([^"]*)"%s*$') } end
  end
  if #rows == 1 then return rows[1][1] end
  for _, r in ipairs(rows) do if title and r[2] == title then if hit then return nil end hit = r[1] end end -- (two with that title: can't tell)
  return hit
end
function M.pid_from_ps(out) -- ExecProcess's "code\n<pid>\n<command>" from the shell REAPER started -> the pid when it's a REAPER, or nil (pure)
  local code, pid, comm = (out or ""):match("^(%-?%d+)\r?\n(%d+)\r?\n([^\r\n]+)")
  if code == "0" and comm:lower():match("reaper%s*$") then return pid end -- (a Mac: /Applications/REAPER.app/Contents/MacOS/REAPER; Linux: reaper)
end
function M.reaper_pid()
  if not reaper.GetOS():find("^Win") then -- (a Mac or Linux: the shell REAPER starts has REAPER for its parent; believed only when ps says it's a REAPER)
    return M.pid_from_ps(reaper.ExecProcess("/bin/sh -c 'echo $PPID; ps -p $PPID -o comm='", 8000))
  end
  local title = reaper.JS_Window_GetTitle and reaper.JS_Window_GetTitle(reaper.GetMainHwnd()) or nil
  return M.pid_from_tasklist(reaper.ExecProcess('tasklist /V /FO CSV /NH /FI "IMAGENAME eq reaper.exe"', 15000), title)
end

-- The swap step, from the same plan, as Windows' cmd or a Mac's and Linux's /bin/sh (5.16). p: { checks = { {"same", live, seen} |
-- {"absent", live} }, swaps = { {"copy", from, to} | {"move", from, to} | {"del", path} }, pend = { {was, path} }, pid, exe, args,
-- projects, cancel, status, mac }. Every check runs before any swap; ok/changed/failed/notclosed.txt in dir say how it ended.
local function cmd_step(dir, p) -- (cmd, not PowerShell: PowerShell hangs at start while a network drive isn't answering)
  -- Paths in Windows form, % doubled (cmd reads it as a variable even inside quotes); UTF-8 (chcp 65001) for names like ChiliØ.
  local function w(x) return '"' .. x:gsub("/", "\\"):gsub("%%", "%%%%") .. '"' end
  local b = { "@echo off", "chcp 65001 >nul", "rem ReaPersona: the shortcut install without Python, written by reapersona_core.lua (M.stage_install). It waits for",
    "rem REAPER to close, swaps the staged files in if nothing changed the originals since they were read, and starts REAPER again.", "set n=0", ":wait" }
  b[#b + 1] = "if exist " .. w(p.cancel) .. " goto cancelled"
  local sys = '"%SystemRoot%\\System32\\' -- (Windows' own tools by full path: Git's find on the PATH is another program)
  if p.pid then b[#b + 1] = sys .. 'tasklist.exe" /FI "PID eq ' .. p.pid .. '" /NH 2>nul | ' .. sys .. 'find.exe" " ' .. p.pid .. ' " >nul || goto closed'
  else b[#b + 1] = sys .. 'tasklist.exe" /FI "IMAGENAME eq reaper.exe" /NH 2>nul | ' .. sys .. 'find.exe" /i "reaper.exe" >nul || goto closed' end -- shortcut: any REAPER counts when this one's id wasn't found
  for _, l in ipairs({ "set /a n+=1", "if %n% geq 180 goto notclosed", sys .. 'ping.exe" -n 2 127.0.0.1 >nul', "goto wait", ":closed" }) do b[#b + 1] = l end -- (180 x 1 s: REAPER may be asking whether to save)
  for _, c in ipairs(p.checks) do
    if c[1] == "same" then b[#b + 1] = sys .. 'fc.exe" /b ' .. w(c[2]) .. " " .. w(c[3]) .. " >nul 2>&1 || goto changed"
    else b[#b + 1] = "if exist " .. w(c[2]) .. " goto changed" end
  end
  for _, s in ipairs(p.swaps) do
    if s[1] == "del" then b[#b + 1] = "del " .. w(s[2]) .. " 2>nul"
    else b[#b + 1] = (s[1] == "copy" and "copy /y " or "move /y ") .. w(s[2]) .. " " .. w(s[3]) .. " >nul || goto failed" end
  end
  for _, d in ipairs(p.pend) do b[#b + 1] = sys .. 'fc.exe" /b ' .. w(d[1]) .. " " .. w(d[2]) .. " >nul 2>nul && del " .. w(d[2]) .. " 2>nul" end
  for _, l in ipairs({ "copy /y " .. w(dir .. "/ok.txt") .. " " .. w(p.status) .. " >nul", "goto relaunch",
    ":changed", "copy /y " .. w(dir .. "/changed.txt") .. " " .. w(p.status) .. " >nul", "goto relaunch",
    ":failed", "copy /y " .. w(dir .. "/failed.txt") .. " " .. w(p.status) .. " >nul", "goto relaunch",
    ":notclosed", "copy /y " .. w(dir .. "/notclosed.txt") .. " " .. w(p.status) .. " >nul", "goto done",
    ":cancelled", "del " .. w(p.cancel) .. " 2>nul", "goto done", ":relaunch" }) do b[#b + 1] = l end
  if p.exe then
    local args = ""
    for _, a in ipairs(p.args) do args = args .. " " .. w(a) end
    for _, a in ipairs(p.projects) do args = args .. " " .. w(a) end
    b[#b + 1] = 'start "" ' .. w(p.exe) .. args
  end
  b[#b + 1] = ":done"
  b[#b + 1] = "(goto) 2>nul & rmdir /s /q " .. w(dir) -- (the folder goes, this file with it: cmd stops reading it there)
  return table.concat(b, "\r\n") .. "\r\n", "install.cmd"
end
local function sh_step(dir, p) -- (POSIX sh and the tools every Mac and Linux has: ps, kill, cmp, cp, mv, rm; on a Mac open and lsappinfo)
  local function q(x) return "'" .. x:gsub("'", "'\\''") .. "'" end
  local function list(t) local o = {}; for _, x in ipairs(t) do o[#o + 1] = q(x) end return table.concat(o, " ") end
  local b = { "#!/bin/sh",
    "# ReaPersona: the shortcut install without Python, written by reapersona_core.lua (M.stage_install). It waits for REAPER to",
    "# close, swaps the staged files in if nothing changed the originals since they were read, and starts REAPER again.",
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH",
    "detach() { if command -v setsid >/dev/null 2>&1; then exec setsid \"$@\"; else exec nohup \"$@\"; fi; }", -- (always run with &: the subshell becomes it, nothing left waiting)
    -- (REAPER starts this and quits: it goes on in a session of its own with nothing tied to REAPER's pipes, or the REAPER it starts
    -- again is killed writing its first line to the old one's. install_shortcuts.py's Linux VM finding, 5.9.2)
    'if [ "$1" != --detached ]; then detach /bin/sh "$0" --detached </dev/null >/dev/null 2>&1 & exit 0; fi',
    "dir=" .. q(dir) .. "; st=" .. q(p.status) .. "; cancel=" .. q(p.cancel),
    "any_reaper() { ps -A -o comm= 2>/dev/null | grep -i -q -E '(^|/)reaper$'; }",
    "running() { " .. (p.pid and ("kill -0 " .. p.pid .. " 2>/dev/null") or "any_reaper") .. "; }", -- (no id found: any REAPER counts, as the batch)
    'finish() { rm -rf "$dir"; exit 0; }',
    "relaunch() {" }
  if p.exe and p.mac then -- (install_shortcuts.py's Mac relaunch: open hands REAPER to LaunchServices and returns; right after the quit
    -- LaunchServices still lists the REAPER going away, and open "activated" that one, said 0, and nothing started (5.8.4). So: wait until it's
    -- gone from there too, then open, and believe it only once a REAPER runs; once more if not)
    for _, l in ipairs({ "  n=0",
      "  while [ $n -lt 15 ] && { lsappinfo find bundleid=com.cockos.reaper 2>/dev/null | grep -q ASN: || any_reaper; }; do n=$((n + 1)); sleep 1; done",
      "  sleep 1", "  note=\"REAPER didn't start again: open it yourself\"", "  for try in 1 2; do",
      "    open -a " .. q(p.exe) .. (#p.projects > 0 and (" " .. list(p.projects)) or "") .. (#p.args > 0 and (" --args " .. list(p.args)) or "") ..
        " >/dev/null 2>&1 || note=\"REAPER didn't start again (open failed): open it yourself\"",
      "    n=0; while [ $n -lt 15 ] && ! any_reaper; do n=$((n + 1)); sleep 1; done",
      "    if any_reaper; then note=\"REAPER started again\"; break; fi", "  done", '  printf \'%s\\n\' "$note" >> "$st"' }) do b[#b + 1] = l end
  elseif p.exe then -- (Linux: the binary, in a session of its own with nothing inherited, believed only once it runs; once more if not)
    for _, l in ipairs({ "  note=\"REAPER didn't start again: open it yourself\"", "  for try in 1 2; do",
      "    detach " .. q(p.exe) .. (#p.args > 0 and (" " .. list(p.args)) or "") .. (#p.projects > 0 and (" " .. list(p.projects)) or "") .. " </dev/null >/dev/null 2>&1 &",
      "    n=0; while [ $n -lt 15 ] && ! any_reaper; do n=$((n + 1)); sleep 1; done",
      "    if any_reaper; then note=\"REAPER started again\"; break; fi", "  done", '  printf \'%s\\n\' "$note" >> "$st"' }) do b[#b + 1] = l end
  end
  for _, l in ipairs({ "  finish", "}",
    'outcome() { cp -f "$dir/$1.txt" "$st"; [ "$1" = notclosed ] && finish; relaunch; }',
    "n=0", "while :; do", '  if [ -e "$cancel" ]; then rm -f "$cancel"; finish; fi', "  running || break",
    "  n=$((n + 1)); [ $n -ge 180 ] && outcome notclosed", "  sleep 1", "done" }) do b[#b + 1] = l end -- (180 x 1 s: REAPER may be asking whether to save)
  for _, c in ipairs(p.checks) do
    if c[1] == "same" then b[#b + 1] = "cmp -s " .. q(c[2]) .. " " .. q(c[3]) .. " || outcome changed"
    else b[#b + 1] = "[ -e " .. q(c[2]) .. " ] && outcome changed" end
  end
  for _, s in ipairs(p.swaps) do
    if s[1] == "del" then b[#b + 1] = "rm -f " .. q(s[2])
    else b[#b + 1] = (s[1] == "copy" and "cp -f " or "mv -f ") .. q(s[2]) .. " " .. q(s[3]) .. " || outcome failed" end
  end
  for _, d in ipairs(p.pend) do b[#b + 1] = "cmp -s " .. q(d[1]) .. " " .. q(d[2]) .. " && rm -f " .. q(d[2]) end
  b[#b + 1] = "outcome ok"
  return table.concat(b, "\n") .. "\n", "install.sh"
end

-- Plan the install and write the swap step. o: { remove, no_midi, pid, exe, cfg, projects = {...}, stamp }. Nothing of REAPER's is
-- touched here: the swap step does that once REAPER has closed. Windows: install.cmd, run with cmd; a Mac or Linux: install.sh, run
-- with /bin/sh (5.16). -> the step's path, or nil + why
function M.stage_install(o)
  local function slurp(p) local f = io.open(p, "rb"); if not f then return nil end local t = f:read("a"); f:close(); return t end
  local dir = M.here .. "/install_staged"
  reaper.RecursiveCreateDirectory(dir, 0)
  reaper.EnumerateFiles(dir, -1)
  local old = {}
  for i = 0, 200 do local f = reaper.EnumerateFiles(dir, i); if not f then break end old[#old + 1] = f end
  for _, f in ipairs(old) do os.remove(dir .. "/" .. f) end -- (a plan from before that never ran)
  local styles = M.load_json(M.here .. "/styles.json")
  local user = M.load_json(M.here .. "/user_styles.json")
  local scripts = M.load_json(M.here .. "/scripts.json")
  local man = M.load_json(M.here .. "/installed.json")
  local old_fb = M.load_json(M.here .. "/midi_fallback.json")
  for _, v in ipairs({ { "styles.json", styles }, { "user_styles.json", user }, { "scripts.json", scripts }, { "installed.json", man }, { "midi_fallback.json", old_fb } }) do
    if not v[2] then return nil, v[1] .. " doesn't parse, so nothing was installed (a copy of it is next to it)" end
  end
  if not o.remove and (type(styles.styles) ~= "table" or #styles.styles == 0) then -- (install_shortcuts.py stops here too: no personas would remove them all)
    return nil, "styles.json is missing or has no personas, so nothing was installed"
  end
  styles = styles.styles or {}
  for _, s in ipairs(user.styles or {}) do styles[#styles + 1] = s end
  local defaults = reaper.file_exists(M.here .. "/midi_defaults.json") and M.load_json(M.here .. "/midi_defaults.json") or nil
  local status, moves, deletes = {}, {}, {}
  local pend = {}
  for _, name in ipairs({ "reaper-kb.ini", "reaper-mouse.ini", "reaper-menu.ini", "reaper-screensets.ini" }) do
    pend[name] = not o.remove and slurp(M.here .. "/pending/" .. name) or nil
    if pend[name] then deletes[#deletes + 1] = { M.here .. "/pending/" .. name, pend[name] }; status[#status + 1] = "took in " .. name .. " from your other computers (yours backed up first)" end
  end
  local function eol_of(t) return (t or ""):find("\r\n", 1, true) and "\r\n" or "\n" end
  local function merged(name, live, fn) if not pend[name] then return live end return (fn(live or "", pend[name]):gsub("\n", eol_of(live))) end
  local windows = reaper.GetOS():find("^Win") ~= nil
  local kb_live = slurp(res .. "/reaper-kb.ini")
  local kb, written, fallback, added, warnings = M.kb_plan(merged("reaper-kb.ini", kb_live, M.merge_kb), styles, scripts, man.lines, old_fb, defaults, o.remove, o.no_midi, windows)
  local menu_live = slurp(res .. "/reaper-menu.ini")
  local menu, tb = M.menu_plan(merged("reaper-menu.ini", menu_live, M.merge_ini) or "", styles, o.remove, function(f)
    if f:find("..", 1, true) then return nil end return slurp(M.here .. "/toolbars/" .. f) end, warnings)
  moves[#moves + 1] = { "reaper-kb.ini", kb_live, kb, "rotate" }
  moves[#moves + 1] = { "reaper-menu.ini", menu_live, menu, "rotate" }
  for _, name in ipairs({ "reaper-mouse.ini", "reaper-screensets.ini" }) do
    if pend[name] then local live = slurp(res .. "/" .. name); moves[#moves + 1] = { name, live, merged(name, live, M.merge_ini), "sync" } end
  end
  status[#status + 1] = string.format("%s %d toolbar(s)", o.remove and "removed ReaPersona toolbars;" or "wrote", tb)
  for _, w in ipairs(warnings) do status[#status + 1] = "skipped: " .. w end
  if reaper.file_exists(M.here .. "/pending/prefs.json") and not o.remove then
    status[#status + 1] = "REAPER's preferences from your other computers still wait: putting them in needs Python (REAPER writes them as it quits)"
  end
  -- The swap step's plan: the checks (each live file as it was read), then the swaps, in order. Rendered as cmd or sh below.
  local stamp = o.stamp or os.date("%Y%m%d-%H%M%S")
  local checks, swaps, backup_of = {}, {}, {}
  local own_copy = {}
  for _, own in ipairs({ { "midi_fallback.json", M.json_encode(fallback) .. "\n" }, { "installed.json", M.json_encode({ lines = written }) .. "\n" } }) do
    if not M.write(dir .. "/" .. own[1], own[2]) then return nil, "couldn't write in " .. dir end
    own_copy[own[1]] = { "copy", dir .. "/" .. own[1], M.here .. "/" .. own[1] }
  end
  swaps[#swaps + 1] = own_copy["midi_fallback.json"] -- (as install_shortcuts.py: the fallback first, the keymap, then installed.json. Review 5.14, M2)
  for i, m in ipairs(moves) do
    local name, live, new, kind = m[1], m[2], m[3], m[4]
    local dst = res .. "/" .. name
    if live == new and name ~= "reaper-kb.ini" then goto next_move end -- (unchanged menus: nothing to check or swap)
    if not M.write(dir .. "/" .. i .. ".new", new) then return nil, "couldn't write in " .. dir end
    if live then
      if not M.write(dir .. "/" .. i .. ".seen", live) then return nil, "couldn't write in " .. dir end
      checks[#checks + 1] = { "same", dst, dir .. "/" .. i .. ".seen" }
      local base = name .. ".before-reapersona-" .. (kind == "sync" and "sync-" or "")
      local bk, n = res .. "/" .. base .. stamp, 1
      while reaper.file_exists(bk) do n = n + 1; bk = res .. "/" .. base .. stamp .. "-" .. n end
      backup_of[name] = bk
      swaps[#swaps + 1] = { "copy", dst, bk }
      if kind == "rotate" then -- (install_shortcuts.backup_of: the first backup, your keymap before ReaPersona, and the newest 4 are kept)
        local have = {}
        reaper.EnumerateFiles(res, -1)
        for j = 0, 100000 do
          local f = reaper.EnumerateFiles(res, j)
          if not f then break end
          if f:sub(1, #name + 19) == name .. ".before-reapersona-" and not f:find(".before-reapersona-sync-", 1, true) then have[#have + 1] = f end -- (sync backups: their own, review 5.14)
        end
        table.sort(have)
        for j = 2, #have - 3 do swaps[#swaps + 1] = { "del", res .. "/" .. have[j] } end
      end
    else checks[#checks + 1] = { "absent", dst } end
    swaps[#swaps + 1] = { "copy", dir .. "/" .. i .. ".new", dst .. ".tmp" }
    swaps[#swaps + 1] = { "move", dst .. ".tmp", dst }
    if name == "reaper-kb.ini" then swaps[#swaps + 1] = own_copy["installed.json"] end
    ::next_move::
  end
  status[#status + 1] = string.format("%s %d shortcut(s); backup: %s", o.remove and "removed ReaPersona," or "installed", added, backup_of["reaper-kb.ini"] or "(none: there was no keymap yet)")
  local st_file = M.here .. "/last_install.txt"
  M.write(dir .. "/ok.txt", table.concat(status, "\n") .. "\n")
  M.write(dir .. "/changed.txt", "not installed: REAPER's keymap or menus changed after ReaPersona read them, so nothing was swapped in. Press Install again.\n")
  M.write(dir .. "/failed.txt", "not installed: a file couldn't be written (your keymap was backed up first, next to reaper-kb.ini)\n")
  M.write(dir .. "/notclosed.txt", "REAPER didn't close, so the shortcuts weren't installed.\n")
  local pend_dels = {}
  for i, d in ipairs(deletes) do -- (only if it's still what was merged: a newer one, synced in as REAPER quit, waits for the next install. Review 5.14, M3)
    local copy = dir .. "/pend" .. i .. ".was"
    if not M.write(copy, d[2]) then return nil, "couldn't write in " .. dir end
    pend_dels[#pend_dels + 1] = { copy, d[1] }
  end
  local os_name = reaper.GetOS()
  local text, file = (windows and cmd_step or sh_step)(dir, { checks = checks, swaps = swaps, pend = pend_dels, pid = o.pid, exe = o.exe,
    args = (o.cfg and reaper.file_exists(o.cfg)) and { "-cfgfile", o.cfg } or {}, projects = o.projects or {},
    cancel = M.here .. "/install_cancelled", status = st_file, mac = os_name:find("^OSX") ~= nil or os_name:find("^macOS") ~= nil })
  local step = dir .. "/" .. file
  if not M.write(step, text) then return nil, "couldn't write " .. step end
  return step
end

function M.toolbar_installed(section) -- is [Floating toolbar N] / [Floating MIDI toolbar N] one of ours in reaper-menu.ini?
  local t = M.read(res .. "/reaper-menu.ini") or ""
  local body = M.ini_section(t, section)
  return body ~= nil and (body:find("title=ReaPersona", 1, true) ~= nil or body:find("title=DAW Styles", 1, true) ~= nil)
end

-- ---------------------------------------------------------------- setup: Python, ReaPersona's own themes, the startup line
local CURL = reaper.GetOS():find("^Win") and "curl" or "/usr/bin/curl" -- (a full path on a Mac: REAPER runs a bare name there as nothing, code -999)
local function sh(cmd, ms) local out = reaper.ExecProcess(cmd, ms or 20000) or ""; local code, text = out:match("^(%-?%d+)\r?\n(.*)$"); return code, text or out end
function M.remove_tree(dir) -- a folder ReaPersona made itself, and everything in it
  if reaper.GetOS():find("^Win") then sh('cmd /c rmdir /s /q "' .. dir:gsub("/", "\\") .. '"', 20000)
  else sh("/bin/rm -rf '" .. dir:gsub("'", "'\\''") .. "'", 20000) end -- (a full path: on a Mac REAPER runs a bare name as nothing, code -999)
end
function M.python() -- -> "Python 3.x" when a Python 3 runs here, else nil (cached; M.py is the command that worked)
  if M._py == nil then
    M._py = false
    local win = reaper.GetOS():find("^Win")
    for _, c in ipairs(win and { "python", "py -3", "python3" } or { "python3", "python" }) do
      -- (on a Mac REAPER runs a bare "python3" as nothing (code -999, no PATH search), so no Mac ever found Python: the shell finds its full
      -- path, and that's what runs from then on. /usr/bin's is only a stub offering the developer tools, unless they're installed. Mac test, 5.8.2)
      if not win then
        local _, where = sh("/bin/sh -c 'command -v " .. c .. "'", 8000)
        local found = where and where:match("^(/%S+)")
        if c == "python3" and (not found or found:match("^/usr/bin/")) then -- (Homebrew's and python.org's, which that PATH doesn't reach)
          for _, p in ipairs({ "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/Library/Frameworks/Python.framework/Versions/Current/bin/python3" }) do
            if reaper.file_exists(p) then found = p; break end
          end
        end
        c = found
        if c and M.IS_MAC and c:match("^/usr/bin/") and sh("/usr/bin/xcode-select -p", 8000) ~= "0" then c = nil end
      end
      local code, text
      if c then code, text = sh(c .. " --version", 8000) end
      local v = code == "0" and text:match("Python 3%S*")
      if v then M._py, M.py = v, c; break end
    end
  end
  return M._py or nil
end
-- Pillow and numpy go in a venv of ReaPersona's own (5.16): `pip install --user` failed on Homebrew's Python 3.12+ and recent Debian and
-- Ubuntu ("externally-managed-environment", PEP 668), and REAPER waited up to 10 minutes while it ran. install_libs.py makes the venv
-- and runs pip in the background; Home shows it running and says how it ended. (The folder is called venv: syncing your scripts skips it.)
M.VENV = M.here .. "/venv"
local LIBS_STATUS = M.here .. "/venv_status.txt"
function M.venv_python() -- -> the venv's Python when it's there, else nil
  local p = M.VENV .. (reaper.GetOS():find("^Win") and "/Scripts/python.exe" or "/bin/python3")
  return reaper.file_exists(p) and p or nil
end
function M.theme_python() -- the Python the theme builder runs with: the venv's when there is one, else the one found (it may have them already)
  local v = M.venv_python()
  return v and ('"' .. v .. '"') or M.py
end
function M.python_libs() -- -> true when the theme builder's Python has Pillow and numpy; cached
  if M._libs == nil then M._libs = M.python() ~= nil and sh(M.theme_python() .. ' -c "import PIL, numpy"', 15000) == "0" end
  return M._libs
end
function M.install_python_libs() -- starts install_libs.py, and REAPER doesn't wait. -> true, or nil + why (M.libs_job says how it goes)
  if not M.python() then return nil, "no Python 3 here (python.org)" end
  if not M.write(LIBS_STATUS, "running " .. os.time() .. "\n") then return nil, "couldn't write in " .. M.here end
  M._libs_seen = nil
  reaper.ExecProcess(M.py .. ' "' .. M.here .. '/install_libs.py" "' .. M.VENV .. '" "' .. LIBS_STATUS .. '"', -1) -- (-1: don't wait)
  return true
end
-- How the background install goes: nil (none), "running", or once when it ends "ok" / "failed" + why (the status file goes then).
-- Read at most once a second (Home asks every frame). One running for over 40 minutes stopped without saying (REAPER closed, say).
function M.libs_job()
  local now = reaper.time_precise()
  if M._libs_seen and now - M._libs_seen[1] < 1 then return M._libs_seen[2] end
  local t = M.read(LIBS_STATUS)
  local state, rest = (t or ""):match("^(%a+)[ \r\n]*(.*)$")
  local why
  if state == "running" and os.time() - (tonumber(rest:match("^%d+")) or 0) > 2400 then state, rest = "failed", "it stopped without finishing: press Install them again" end
  if state == "ok" or state == "failed" then
    os.remove(LIBS_STATUS)
    M._libs = nil
    why = rest:gsub("%s+$", "")
  elseif state ~= "running" then state = nil end
  M._libs_seen = { now, state == "running" and "running" or nil } -- (an end is told once, never from the cache)
  return state, why
end
M.OWN = M.styles_json.own_themes or {}
for k, v in pairs(M.load_json(M.here .. "/user_themes.json") or {}) do M.OWN[k] = v end -- (theme recipes you imported, e.g. from an Ableton Live theme)
M.CATALOG = M.styles_json.themes or {}
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
  if not M.python_libs() then return nil, "it needs Pillow and numpy: Home > Pillow and numpy > Install them" end
  local code, text = sh(M.theme_python() .. ' "' .. M.here .. '/build_themes.py" "' .. M.themes_dir:gsub("/$", "") .. '"', 180000)
  local first, rest = (text or ""):match("^(%d)\r?\n(.*)$") -- (Python writes \r\n into a pipe on Windows)
  if code ~= "0" or first ~= "0" then return nil, (rest or text or ""):sub(1, 400) end
  apply_own_params()
  local made = {}
  for l in rest:gmatch("[^\r\n]+") do made[#made + 1] = l end
  return made
end
function M.startup_path() return res .. "/Scripts/__startup.lua" end
function M.startup_on() return cached("startup", function() return (M.read(M.startup_path()) or ""):find("reapersona_core.lua", 1, true) ~= nil end) end
local STARTUP_OPEN, STARTUP_CLOSE = "\n-- >>> ReaPersona:", "-- <<< ReaPersona <<<\n"
local function startup_block()
  -- (relative to the resource folder when it's inside it, so the line works on a drive with another letter; else the full path)
  local r = res:gsub("\\", "/")
  local where
  if M.here:lower():sub(1, #r + 1) == r:lower() .. "/" then where = 'reaper.GetResourcePath() .. ' .. string.format("%q", M.here:sub(#r + 1))
  else where = string.format("%q", M.here) end
  -- (only while ReaPersona is there: removed, the block said "restore failed" at every start. Review, 5.9.3)
  return STARTUP_OPEN .. " REAPER forgets the shortcut layer at restart, so bring back the last persona's keys\ndo\n" ..
    '  local core = ' .. where .. ' .. "/reapersona_core.lua"\n' ..
    '  local ok, err = true, nil\n' ..
    '  if reaper.file_exists(core) then ok, err = pcall(function() dofile(core).restore_last() end) end\n' ..
    '  if not ok then reaper.ShowConsoleMsg("[ReaPersona] restore failed: " .. tostring(err) .. "\\n") end\nend\n' .. STARTUP_CLOSE
end
-- Where ReaPersona's block is in __startup.lua's text: from a line starting "-- >>> ReaPersona" or "-- >>> DAW Styles" to the next
-- "-- <<< ReaPersona <<<" (or DAW Styles) line, with the newline before it. Any wording after the name counts: a block written by hand
-- ("-- >>> ReaPersona (was DAW Styles, ...)") was never matched, so it was never swapped for one with the file check and kept saying
-- "restore failed" once ReaPersona was gone. Review, 5.9.3. -> first, last character of the first block, or nil (pure)
function M.find_startup(text)
  local t, from = "\n" .. text, 1 -- (a block on the very first line has no newline before it)
  while true do
    local b, a
    for _, name in ipairs({ "ReaPersona", "DAW Styles" }) do
      local _, y = t:find("\n%-%- <<< " .. name .. " <<<[^\n]*\n?", from)
      if y and (not b or y < b) then b = y end
    end
    if not b then return nil end
    -- (the last opening line before that close: an opening line left without its close never takes your own lines with it)
    for _, name in ipairs({ "ReaPersona", "DAW Styles" }) do
      local i = from
      while true do
        local x = t:find("\n%-%- >>> " .. name, i)
        if not x or x >= b then break end
        a, i = math.max(a or 0, x), x + 1
      end
    end
    if a then return math.max(a - 1, 1), b - 1 end
    from = b -- (a closing line with nothing opened: look further on)
  end
end
function M.strip_startup(text) -- every ReaPersona block out of __startup.lua's text, the rest left exactly as it was (pure)
  while true do
    local a, b = M.find_startup(text)
    if not a then return text end
    text = text:sub(1, a - 1) .. text:sub(b + 1)
  end
end
-- A block from before 5.9.3 (no file check), or one written by hand, is swapped for today's, and a second copy goes. Called at each
-- start (restore_last) and when the window opens, so updating and then removing ReaPersona without a restart leaves no old block.
function M.upgrade_startup()
  local text = M.read(M.startup_path()) or ""
  local a, b = M.find_startup(text)
  if not a then return end
  local rest = M.strip_startup(text:sub(b + 1))
  if text:sub(a, b):find("file_exists", 1, true) and rest == text:sub(b + 1) then return end
  M.write(M.startup_path(), text:sub(1, a - 1) .. startup_block() .. rest)
  M.forget()
end
function M.remove_startup() -- ReaPersona's block (any version's) out of Scripts/__startup.lua -> true, or nil + why
  local text = M.read(M.startup_path())
  if not text then return true end
  local out = M.strip_startup(text)
  M.forget()
  if out == text then return true end
  if not M.write(M.startup_path(), out) then return nil, "couldn't write " .. M.startup_path() end
  return true
end
function M.add_startup() -- one block in Scripts/__startup.lua that brings back the last style's keys when REAPER starts
  if M.startup_on() then return true end
  local block = startup_block()
  local f = io.open(M.startup_path(), "a")
  if not f then return nil, "couldn't write " .. M.startup_path() end
  f:write(block); f:close()
  M.forget()
  return true
end

-- ---------------------------------------------------------------- removing ReaPersona (Settings > Remove ReaPersona)
-- Removed with ReaPack alone, ReaPersona left its startup block, its actions and its ExtState behind (Review, 5.9.3). The window puts
-- My REAPER back first, so everything a persona changed is undone; then this takes out the startup block, ReaPersona's actions and what
-- it keeps in REAPER's ExtState. The shortcut layers and toolbars need REAPER closed: install_shortcuts.py --remove does those. Your
-- personas, presets and themes stay in their files, so nothing of yours is lost if you come back.
function M.extstate_keys(text, section) -- the keys reaper-extstate.ini's text keeps for section (pure)
  local out = {}
  for k in (M.ini_section(text, section) or ""):gmatch("\n([^=\r\n]+)=") do out[#out + 1] = k end
  return out
end
local function extstate_names() -- every key this version sets: some may not be in reaper-extstate.ini yet (REAPER writes it later)
  local t = { "style", "orig", "orig project", "view", "look", "migrated", "page", "welcomed", "text size", "all actions", "follow projects",
    "follow beat", "project default", "midi dock", "workflow", "search", "theme my_reaper", "theme path my_reaper", "sync folder", "sync id", "sync last", "sync file", M.LOOK_KEY, "update seen", "favourites" }
  for _, list in ipairs({ M.styles, M.presets }) do
    for _, st in ipairs(list) do for _, k in ipairs({ "theme ", "forks ", "declined theme " }) do t[#t + 1] = k .. st.id end end
  end
  for name in pairs(M.OWN) do t[#t + 1] = "params " .. name end
  for _, a in ipairs(M.ASPECTS) do t[#t + 1] = "aspect " .. a[1] end
  for side in pairs(SIDES) do t[#t + 1] = "docker " .. side end
  for key in pairs(M.EXTENSIONS) do t[#t + 1] = "declined " .. key end
  return t
end
function M.uninstall() -- -> lines saying what was done
  local done = {}
  local ok, why = M.remove_startup()
  done[#done + 1] = ok and "The startup block is out of __startup.lua." or ("The startup block is still in __startup.lua: " .. tostring(why))
  local list = {}
  for _, sub in ipairs({ { "actions", 0 }, { "midi_keys", MIDI_SEC } }) do
    local d = M.here .. "/" .. sub[1]
    reaper.EnumerateFiles(d, -1)
    for i = 0, 2000 do
      local f = reaper.EnumerateFiles(d, i)
      if not f then break end
      if f:match("%.lua$") then list[#list + 1] = { sub[2], d .. "/" .. f } end
    end
  end
  for n, s in ipairs(list) do reaper.AddRemoveReaScript(false, s[1], s[2], n == #list) end
  done[#done + 1] = #list .. " ReaPersona actions are out of the Actions list."
  M.scripts.stubs = nil -- (registered afresh if you come back; the ids stay, so --remove still knows ReaPersona's MIDI editor keys)
  M.write(M.here .. "/scripts.json", M.json_encode(M.scripts) .. "\n")
  local ini = M.read(res .. "/reaper-extstate.ini") or ""
  for _, k in ipairs(extstate_names()) do reaper.DeleteExtState(M.SECTION, k, true) end
  for _, sec in ipairs({ M.SECTION, "DAWStyles" }) do -- (DAWStyles: what the old name kept)
    for _, k in ipairs(M.extstate_keys(ini, sec)) do reaper.DeleteExtState(sec, k, true) end
  end
  done[#done + 1] = "ReaPersona's settings are out of REAPER's ExtState."
  M.forget()
  return done
end

-- ---------------------------------------------------------------- helper tools some styles' features use (offered when missing)
M.TOOLS = {
  { match = "^_HB_", name = "Helgobox (Playtime clip launcher)", how = "ReaPack, repository Helgoboss Projects", filter = "Helgobox" },
  { match = "^_RSa31e94c408150d20aad669ba609f01c4083975ae$", name = "MPL's RS5k step sequencer", how = "ReaPack, MPL Scripts", filter = "step sequencer" },
  { match = "^_FNG_", name = "SWS", how = "sws-extension.org", url = "https://www.sws-extension.org/" },
  { match = "^_SWS", name = "SWS", how = "sws-extension.org", url = "https://www.sws-extension.org/" },
  { match = "^_BR_", name = "SWS", how = "sws-extension.org", url = "https://www.sws-extension.org/" },
}
function M.tool_for(named) for _, t in ipairs(M.TOOLS) do if named:match(t.match) then return t end end end
function M.get_tool(t) -- ReaPack's package browser, filtered to it, or its web page (installing stays the user's click). -> nil, or why not
  local find = t.filter or t.find
  if find and reaper.ReaPack_BrowsePackages then
    if t.repos and reaper.ReaPack_AddSetRepository then -- (its repository first, enabled; nothing installs until you pick it)
      local added
      for _, r in ipairs(t.repos) do
        local have, _, enabled = false, nil, false
        if reaper.ReaPack_GetRepositoryInfo then have, _, enabled = reaper.ReaPack_GetRepositoryInfo(r[1]) end
        if not (have and enabled) then -- (one you have stays as it is; one switched off is switched on, its address kept)
          local ok, err = reaper.ReaPack_AddSetRepository(r[1], have and "" or r[2], true, 2, "") -- (2: auto-install as ReaPack is set)
          if not ok then return "couldn't add " .. r[1] .. ": " .. tostring(err) end
          added = true
        end
      end
      if added then reaper.ReaPack_ProcessQueue(true) end -- (fetches the new lists, so the browser can show the package)
    end
    reaper.ReaPack_BrowsePackages(find)
  else M.open_url(t.url or "https://reapack.com/") end
end

-- ---------------------------------------------------------------- importing from another DAW on this computer
-- What can be read: Cubase/Nuendo's Key Commands.xml (your own key assignments) and an Ableton Live theme (.ask colours). The others
-- keep their settings in binary files, or don't let you change keys at all: for those, their style and its tools are the import.
local function env(k) return os.getenv(k) or "" end
local function first_dir(pattern_parent, prefix) -- newest folder under pattern_parent whose name starts with prefix
  local best, best_v
  local function version(d) local v = {}; for n in d:gmatch("%d+") do v[#v + 1] = tonumber(n) end return v end
  local function newer(a, b) for i = 1, math.max(#a, #b) do if (a[i] or 0) ~= (b[i] or 0) then return (a[i] or 0) > (b[i] or 0) end end return false end
  for i = 0, 200 do
    local d = reaper.EnumerateSubdirectories(pattern_parent, i)
    if not d then break end
    if d:find(prefix, 1, true) == 1 and (not best or newer(version(d), best_v)) then best, best_v = d, version(d) end -- ("Cubase 14" > "Cubase 9")
  end
  return best and (pattern_parent .. "/" .. best) or nil
end
function M.detect_daws() -- -> { {style, name, found = path or nil, can = {...}} }
  local win = reaper.GetOS():find("^Win")
  local appdata, pf, home = env("APPDATA"):gsub("\\", "/"), "C:/Program Files", env("HOME")
  local out = {}
  local function add(style, name, paths, can)
    local found
    for i = 1, 10 do -- (not ipairs: a path that wasn't found is a nil in the list, and ipairs stops there)
      local p = paths[i]
      if p and (reaper.file_exists(p) or reaper.EnumerateFiles(p, 0) or reaper.EnumerateSubdirectories(p, 0)) then found = p; break end
    end
    out[#out + 1] = { style = style, name = name, found = found, can = can or {} }
  end
  if win then
    local cub = first_dir(appdata .. "/Steinberg", "Cubase") or first_dir(appdata .. "/Steinberg", "Nuendo")
    add("cubase", "Cubase / Nuendo", { cub and (cub .. "/Key Commands.xml"), pf .. "/Steinberg/Cubase 14", pf .. "/Steinberg/Cubase 13" }, { keys = cub and (cub .. "/Key Commands.xml") })
    add("ableton", "Ableton Live", { first_dir("C:/ProgramData/Ableton", "Live"), appdata .. "/Ableton" }, { theme = first_dir("C:/ProgramData/Ableton", "Live") })
    add("pro_tools", "Pro Tools", { pf .. "/Avid/Pro Tools" })
    add("fl_studio", "FL Studio", { first_dir(pf .. "/Image-Line", "FL Studio"), pf .. "/Image-Line" })
    add("studio_one", "Studio One / Fender Studio Pro", { first_dir(pf .. "/PreSonus", "Studio One"), pf .. "/Fender Studio Pro", appdata .. "/PreSonus" })
    add("bitwig", "Bitwig Studio", { pf .. "/Bitwig Studio" })
    add("reason", "Reason", { first_dir(pf .. "/Reason Studios", "Reason") })
    add("cakewalk", "Cakewalk / Sonar", { pf .. "/Cakewalk", pf .. "/BandLab/Cakewalk", pf .. "/BandLab/Sonar" })
  else
    local lib = home .. "/Library"
    local cub = first_dir(lib .. "/Preferences", "Cubase") or first_dir(lib .. "/Preferences", "Nuendo")
    add("cubase", "Cubase / Nuendo", { cub and (cub .. "/Key Commands.xml"), "/Applications/Cubase 14.app" }, { keys = cub and (cub .. "/Key Commands.xml") })
    add("ableton", "Ableton Live", { first_dir("/Applications", "Ableton Live") }, {})
    add("logic", "Logic Pro", { "/Applications/Logic Pro.app", "/Applications/Logic Pro X.app" })
    add("pro_tools", "Pro Tools", { "/Applications/Pro Tools.app" })
    add("fl_studio", "FL Studio", { first_dir("/Applications", "FL Studio") })
    add("studio_one", "Studio One / Fender Studio Pro", { first_dir("/Applications", "Studio One"), "/Applications/Fender Studio Pro.app" })
    add("bitwig", "Bitwig Studio", { "/Applications/Bitwig Studio.app" })
    add("reason", "Reason", { first_dir("/Applications", "Reason") })
  end
  return out
end
local CUBASE_KEYS = { Return = "Enter", Del = "Delete", Escape = "Esc", ["Page Up"] = "PgUp", ["Page Down"] = "PgDn", PageUp = "PgUp", PageDown = "PgDn",
  ["Left Arrow"] = "Left", ["Right Arrow"] = "Right", ["Up Arrow"] = "Up", ["Down Arrow"] = "Down", ["Space"] = "Space" }
local function cubase_spec(k) -- "Ctrl+Shift+Pad 1" -> "Ctrl+Shift+Num1"
  local mods, key = M.split_spec(k)
  key = key:gsub("^Pad ?", "Num"):gsub("^Num (.)", "Num%1")
  key = CUBASE_KEYS[key] or key
  return M.canon(mods ~= "" and (mods .. "+" .. key) or key)
end
-- Your Cubase key assignments as a style: Cubase's own style with your keys on the commands it knows. -> the style, list not matched; or nil + why
function M.import_cubase_keys(path)
  local xml = M.read(path)
  if not xml then return nil, "couldn't read " .. tostring(path) end
  local base = M.by_id("cubase")
  local by_name = {}
  for _, k in ipairs(base.keys) do by_name[k[3]:lower()] = k[2] end
  local keys, seen, missed = {}, {}, {}
  local found = {} -- (a Key belongs to the Name just before it: categories nest their commands, so items can't be read one by one)
  local name_now
  for kind, val in xml:gmatch('<string name="(%a+)" value="([^"]*)"') do
    if kind == "Name" then name_now = val elseif kind == "Key" and name_now then found[#found + 1] = { name_now, val } end
  end
  for _, nk in ipairs(found) do
    local name, key = nk[1], nk[2]
    if key ~= "" then
      local cmd = by_name[name:lower()]
      local spec = cubase_spec(key)
      if cmd and M.encode(spec) and not seen[spec] then seen[spec] = true; keys[#keys + 1] = { spec, cmd, name .. " (yours)" }
      elseif not cmd then missed[#missed + 1] = name .. " = " .. key end
    end
  end
  if #keys == 0 then return nil, "none of its key assignments match a Cubase command ReaPersona knows (" .. #missed .. " others)" end
  for _, k in ipairs(base.keys) do if not seen[M.canon(k[1])] then keys[#keys + 1] = copy(k); seen[M.canon(k[1])] = true end end
  local alt = free_alt()
  if not alt then return nil, "all 16 shortcut layers are in use" end
  local st = copy(base)
  st.id, st.name, st.alt, st.keys, st.user = M.new_id("cubase_mine_"), "Cubase (your keys)", alt, keys, nil
  st.toolbar_slot, st.midi_toolbar_slot = nil, nil -- (Cubase's own style installs those toolbars; this one switches to the same)
  st.description = "Cubase with your own key assignments from " .. path:gsub("\\", "/"):match("[^/]+$") .. " on top of its defaults; shortcut layer alt-" .. alt .. "."
  local ok, why = save_user_style(st)
  if not ok then return nil, why end
  return st, missed
end
-- An Ableton Live theme (.ask) as a ReaPersona theme recipe (user_themes.json), built like the others. -> recipe name, or nil + why
function M.import_live_theme(path)
  local xml = M.read(path)
  if not xml then return nil, "couldn't read " .. tostring(path) end
  local function col(...)
    for _, n in ipairs({ ... }) do local v = xml:match("<" .. n .. '%s+Value="(#%x%x%x%x%x%x)') ; if v then return v:upper() end end
  end
  local base = M.OWN["Ableton Live"] and copy(M.OWN["Ableton Live"]) or { palette = {} }
  local p = base.palette
  local bg, surf, text, sel, accent = col("Desktop", "SurfaceBackground"), col("SurfaceBackground", "SurfaceArea"), col("ControlForeground", "TextDisabled"),
    col("SelectionBackground", "SelectionFrame"), col("ChosenDefault", "ChosenAlert")
  if not (bg or surf) then return nil, "no colours found: is it a Live theme (.ask)?" end
  p[1], p[2], p[3], p[5] = surf or p[1], surf or p[2], surf or p[3], bg or p[5]
  if sel then p[4] = sel end
  if text then p[6] = text; p[8] = text end
  if accent then p[10], p[13], p[15] = accent, accent, accent end
  base.tint = surf or base.tint
  local name = "Ableton Live - " .. (path:gsub("\\", "/"):match("([^/]+)%.ask$") or "imported")
  local d = M.load_json(M.here .. "/user_themes.json")
  if not d then return nil, "user_themes.json doesn't parse, so it isn't written over" end
  d[name] = base
  local ok, why = M.save_json(M.here .. "/user_themes.json", d)
  if not ok then return nil, why end
  M.OWN[name] = base
  return name
end

-- ---------------------------------------------------------------- browsing the REAPER Stash (curl comes with Windows 10+ and macOS)
M.STASH_CATS = { { "Themes", "Themes" }, { "Key-Maps", "Key maps" }, { "Custom-Actions", "Custom actions" }, { "Classic-Themes", "Classic themes" },
  { "Scripts", "Scripts" }, { "Project-and-Track-Templates", "Templates" } }
M.STASH_SORTS = { { "nd", "Newest" }, { "ha", "Most popular" }, { "hr", "Top rated" } }
local function unhtml(s) return (s:gsub("&amp;", "&"):gsub("&#039;", "'"):gsub("&quot;", '"'):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("^%s+", ""):gsub("%s+$", "")) end
local function urldecode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
-- One page of the Stash: -> { {title, page, file, date, views} }, or nil + why
function M.stash_list(cat, sort, query, pageno)
  reaper.RecursiveCreateDirectory(M.here .. "/_downloads", 0)
  local out_file = M.here .. "/_downloads/stash.html"
  local url = "https://stash.reaper.fm/browse.php?q=" .. (query or ""):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end) ..
    "&cat=" .. cat .. "&v=th&o=" .. sort .. "&pp=48&p=" .. (pageno or 1)
  local code = sh(CURL .. ' -s -L --max-time 25 -o "' .. out_file .. '" "' .. url .. '"', 30000)
  local html = M.read(out_file)
  os.remove(out_file)
  if code ~= "0" or not html then return nil, "couldn't reach stash.reaper.fm" end
  local items, starts = {}, {}
  for pos in html:gmatch('()class="file ') do starts[#starts + 1] = pos end -- (cut between item markers: matching up to the next one ate it)
  starts[#starts + 1] = #html + 1
  for n = 1, #starts - 1 do
    local chunk = html:sub(starts[n], starts[n + 1] - 1)
    local page = chunk:match('href="(/[tv][a-z]*/%d+/[^"]+)"')
    local title = chunk:match('<div class="title">.-<a[^>]*>%s*(.-)%s*</a>')
    local file = chunk:match('report_file%.php%?url=([^"]+)"')
    if page and title then
      items[#items + 1] = { title = unhtml(title), page = "https://stash.reaper.fm" .. page, file = file and urldecode(file),
        date = (chunk:match('<div class="date">%s*(.-)%s*</div>') or ""), views = tonumber(chunk:match("<span>(%d+)</span> Views") or "") }
    end
  end
  return items
end
-- Fetch one Stash file and take it in like a dropped file. A web page coming back instead (sign-in, a human check) isn't worked around:
-- -> import results, or nil + "page" (open item.page in the browser instead)
function M.stash_get(item)
  -- (the link and name come from a web page: only a plain stash.reaper.fm file link, saved under a plain name, gets near the shell)
  local url = item.file and item.file:gsub("[^%w%-%._~/:%%]", function(c) return string.format("%%%02X", c:byte()) end)
  if not (url and url:match("^https://stash%.reaper%.fm/[%w%-%._~/%%]+$")) then return nil, "page" end
  local name = urldecode(url:match("[^/]+$") or ""):gsub("[^%w%._ %-%(%)]", "_"):gsub("^[%. ]+", "")
  if name == "" then name = "download" end
  local dir = M.here .. "/_downloads"
  reaper.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "/" .. name
  local code = sh(CURL .. ' -s -L --max-time 60 -o "' .. path .. '" "' .. url .. '"', 70000)
  local head = (M.read(path) or ""):sub(1, 200):lower()
  if code ~= "0" or head == "" or head:find("<!doctype", 1, true) or head:find("<html", 1, true) then os.remove(path); return nil, "page" end
  local got = M.import_file(path)
  os.remove(path)
  for _, r in ipairs(got) do if r[1] == "theme" and item.title then r[3] = "from \"" .. item.title .. "\"" .. (r[3] and ("; " .. r[3]) or "") end end
  return got
end

-- ---------------------------------------------------------------- dropping files in: themes, theme packs, toolbars, keymaps, styles, presets
local KEYNAME = {} -- (key code -> name, for keymaps dropped in)
for k, v in pairs(NAMED) do KEYNAME[v] = k end
local function decode(f, k) -- reaper-kb.ini flags, key -> "Ctrl+Shift+L" (the reverse of M.encode), or nil
  f, k = tonumber(f), tonumber(k)
  if f == 255 then return M.wheel_name(k) end
  if not (f and k) then return nil end
  local mods = {}
  if f & CTRL ~= 0 then mods[#mods + 1] = "Ctrl" end
  if f & ALT ~= 0 then mods[#mods + 1] = "Alt" end
  if f & SHIFT ~= 0 then mods[#mods + 1] = "Shift" end
  if f & WIN ~= 0 then mods[#mods + 1] = "Win" end
  local key
  if f & VIRT == 0 then key = k <= 0x10FFFF and utf8.char(k) or nil
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
  local st = { id = M.new_id("keymap_"), name = name, alt = alt, kind = "daw", keys = keys, feel = {},
    description = name .. ": the keys from " .. name .. ".ReaperKeyMap on their own shortcut layer (alt-" .. alt .. "); your theme and settings." }
  return save_user_style(st)
end
-- Whatever was dropped on the window. -> list of { kind, name, detail } (kind: theme, toolbar, style, preset, skipped)
-- Inside a zip (in_zip) only themes and toolbars come in: a pack's keymaps go to REAPER's KeyMaps folder, to drop in on purpose,
-- rather than each taking one of the few free shortcut layers.
function M.import_file(path, out, in_zip, depth) -- (depth: how many packs deep; a pack inside a pack is opened, one more is not)
  out = out or {}
  local p = path:gsub("\\", "/")
  local base = p:match("[^/]+$") or p
  local low = base:lower()
  if low:match("%.reaperthemezip$") or low:match("%.reapertheme$") then
    local n, why = M.import_theme(p)
    local folder = in_zip and low:match("%.reapertheme$") and p:gsub("%.[Rr][Ee][Aa][Pp][Ee][Rr][Tt][Hh][Ee][Mm][Ee]$", "")
    if n and folder and M.is_dir(folder) then -- (its images: without them the theme draws nothing)
      local to = M.themes_dir .. folder:match("[^/]+$")
      if M.is_dir(to) then os.rename(to, to .. ".before-" .. os.date("%Y%m%d-%H%M%S")) end
      if not os.rename(folder, to) then M.copy_tree(folder, to) end
      why = (why and (why .. "; ") or "") .. "with its folder of images"
    end
    out[#out + 1] = { n and "theme" or "skipped", n or base, why }
  elseif low:match("%.reapermenu$") then
    reaper.RecursiveCreateDirectory(M.here .. "/toolbars", 0)
    local ok = M.write(M.here .. "/toolbars/" .. M.file_name(base), M.read(p) or "")
    out[#out + 1] = { ok and "toolbar" or "skipped", base, ok and "in ReaPersona's toolbars folder: install the shortcuts to use it" or "couldn't copy" }
  elseif in_zip and (low:match("%.reaperkeymap$") or low:match("%.json$")) then
    reaper.RecursiveCreateDirectory(res .. "/KeyMaps", 0)
    local to = res .. "/KeyMaps/" .. M.file_name(base)
    local ok = low:match("%.reaperkeymap$") and not reaper.file_exists(to) and M.write(to, M.read(p) or "")
    if low:match("%.reaperkeymap$") then
      out[#out + 1] = { "skipped", base, ok and "saved in REAPER's KeyMaps folder: drop it on this window to make it a persona" or "in the pack; not added" }
    end
  elseif low:match("%.reaperkeymap$") then
    local st, why = M.style_from_keymap(p)
    out[#out + 1] = { st and "style" or "skipped", st and st.name or base, st and ("shortcut layer alt-" .. st.alt) or why }
  elseif low:match("%.json$") then
    local ok, d = pcall(M.json_decode, M.read(p) or "")
    if ok and d and d.preset then
      local pr, why = M.import_preset(d)
      out[#out + 1] = { pr and "preset" or "skipped", pr and pr.name or base, why }
    elseif ok and d and (d.reapersona_setup or d.reapersona_sync) then
      local r, why
      if M.confirm_setup(d, base) then r, why = M.import_setup(d) else why = "not taken in (you said no)" end
      out[#out + 1] = { r and "setup" or "skipped", base, r and (M.setup_summary(r) .. (r.install and "; install the shortcuts for your personas' keys" or "")) or why }
    elseif ok and d and d.style then
      local st, why = M.import(p)
      out[#out + 1] = { st and "style" or "skipped", st and st.name or base, st and ("shortcut layer alt-" .. st.alt) or why }
    else out[#out + 1] = { "skipped", base, "not a ReaPersona persona or preset" } end
  elseif low:match("%.zip$") or low:match("%.rar$") then -- (a theme pack: unpacked (M.unpack), then what's inside comes in)
    if in_zip and (depth or 1) >= 2 then out[#out + 1] = { "skipped", base, "a pack inside a pack inside a pack: unpack it and drop that in" }; return out end
    local nm = M.file_name(base:gsub("%.[ZzRr][IiAa][PpRr]$", "")):gsub("^%s+$", "")
    local dir = M.here .. "/_incoming/" .. (nm ~= "" and nm or "pack") .. "-" .. os.time()
    local code, text = M.unpack(p, dir)
    local n0 = #out
    local skip = M.pack_prepass(dir, nm, out) -- (fonts, scripts and mods for themes you have: dealt with before the walk)
    local function walk(d)
      reaper.EnumerateFiles(d, -1); reaper.EnumerateSubdirectories(d, -1) -- (REAPER caches folder listings: rescan)
      for i = 0, 2000 do local f = reaper.EnumerateFiles(d, i); if not f then break end if not skip[d .. "/" .. f] then M.import_file(d .. "/" .. f, out, true, (depth or 0) + 1) end end
      for i = 0, 200 do local s = reaper.EnumerateSubdirectories(d, i); if not s then break end if not skip[d .. "/" .. s] then walk(d .. "/" .. s) end end
    end
    walk(dir)
    M.remove_tree(dir) -- (the unpacked copy was ours, made just above: gone again)
    if out.left then out[#out + 1] = { "skipped", out.left .. " other files", "readmes, images and the like: not themes or toolbars" }; out.left = nil end
    out.fonts, out.scripts = nil, nil
    if code ~= "0" and #out == n0 then out[#out + 1] = { "skipped", base, "couldn't unpack it: " .. (text or ""):sub(1, 200) }
    elseif #out == n0 then out[#out + 1] = { "skipped", base, "nothing ReaPersona can use inside" } end
  elseif in_zip then -- (a pack's readmes, images, fonts and scripts: counted, not listed one by one)
    out.left = (out.left or 0) + 1
    if low:match("%.ttf$") or low:match("%.otf$") then out.fonts = true end
    if low:match("%.lua$") or low:match("%.eel$") then out.scripts = true end
  else out[#out + 1] = { "skipped", base, "not a theme, toolbar, keymap, persona or preset" } end
  return out
end

-- ---------------------------------------------------------------- installing themes: one click from the catalog, and packs made easy
function M.is_dir(d) reaper.EnumerateFiles(d, -1); reaper.EnumerateSubdirectories(d, -1); return (reaper.EnumerateFiles(d, 0) or reaper.EnumerateSubdirectories(d, 0)) ~= nil end
function M.copy_tree(from, to) -- every file under from, to the same place under to -> how many copied
  reaper.RecursiveCreateDirectory(to, 0)
  reaper.EnumerateFiles(from, -1); reaper.EnumerateSubdirectories(from, -1)
  local n = 0
  for i = 0, 5000 do local f = reaper.EnumerateFiles(from, i); if not f then break end if M.write(to .. "/" .. f, M.read(from .. "/" .. f) or "") then n = n + 1 end end
  for i = 0, 500 do local d = reaper.EnumerateSubdirectories(from, i); if not d then break end n = n + M.copy_tree(from .. "/" .. d, to .. "/" .. d) end
  return n
end
-- How a pack (.zip or .rar, or a .ReaperThemeZip, which is a zip) is unpacked on this system. Windows' and macOS's own tar is bsdtar,
-- which opens both; Linux's tar is GNU tar, which opens neither, so there it's unzip or unrar, else bsdtar or 7z, whichever is installed
-- (Review, 5.9.3). have(name) -> that program's full path, or nil. -> the command, or nil + what to install (pure)
function M.unpack_command(os_name, archive, dir, have)
  local win = os_name:find("^Win") ~= nil
  local q = win and function(x) return '"' .. x .. '"' end or function(x) return "'" .. x:gsub("'", "'\\''") .. "'" end
  -- (Windows' own tar by full path: another tar on PATH, Git's say, reads "J:/..." as a remote host)
  if win then return q((os.getenv("SystemRoot") or "C:\\Windows") .. "\\System32\\tar.exe") .. " -xf " .. q(archive) .. " -C " .. q(dir) end
  if os_name:find("^OSX") or os_name:find("^macOS") then return q("/usr/bin/tar") .. " -xf " .. q(archive) .. " -C " .. q(dir) end
  local rar = archive:lower():match("%.rar$") ~= nil
  for _, t in ipairs(rar and { "unrar", "bsdtar", "7z", "7zz" } or { "unzip", "bsdtar", "7z", "7zz" }) do
    local p = have(t)
    if p and t == "unzip" then return q(p) .. " -o -qq " .. q(archive) .. " -d " .. q(dir)
    elseif p and t == "unrar" then return q(p) .. " x -o+ -idq " .. q(archive) .. " " .. q(dir .. "/") -- (unrar: a folder ends in /)
    elseif p and t == "bsdtar" then return q(p) .. " -xf " .. q(archive) .. " -C " .. q(dir)
    elseif p then return q(p) .. " x -y -o" .. q(dir) .. " " .. q(archive) end -- (7z: no space after -o)
  end
  return nil, "opening a ." .. (rar and "rar" or "zip") .. " needs " .. (rar and "unrar" or "unzip") .. ", bsdtar or 7z, and none of them is installed" ..
    " (Ubuntu and Debian: sudo apt install " .. (rar and "libarchive-tools" or "unzip") .. ")"
end
local function find_program(name) -- (Linux: its full path, as M.python finds Python's)
  local code, where = sh("/bin/sh -c 'command -v " .. name .. "'", 8000)
  return code == "0" and where and where:match("^(/%S+)") or nil
end
function M.unpack(archive, dir) -- archive's files into dir -> exit code, output; or nil + what's missing
  reaper.RecursiveCreateDirectory(dir, 0)
  local cmd, why = M.unpack_command(reaper.GetOS(), archive, dir, find_program)
  if not cmd then return nil, why end
  return sh(cmd, 60000)
end
-- A mod for a theme you have (a pack folder holding "Name/" images, maybe "Name.ReaperTheme", where Name.ReaperThemeZip is installed):
-- the theme unpacked, the mod laid over it, saved as "Name (label)" next to it. -> the new theme's file name, or nil + why
function M.make_variant(base, mod_dir, label)
  local name = M.file_name(base .. " (" .. label .. ")")
  local tmp = M.here .. "/_incoming/variant-" .. os.time() .. "-" .. math.random(1000, 9999)
  local done, missing = M.unpack(M.themes_dir .. base .. ".ReaperThemeZip", tmp)
  local rt = M.read(mod_dir .. "/" .. base .. ".ReaperTheme") or M.read(tmp .. "/" .. base .. ".ReaperTheme")
  if not (rt and M.is_dir(tmp .. "/" .. base)) then M.remove_tree(tmp); return nil, "couldn't unpack " .. base .. (done and "" or (": " .. missing)) end
  M.copy_tree(mod_dir .. "/" .. base, tmp .. "/" .. base)
  local to = M.themes_dir .. name
  if M.is_dir(to) then os.rename(to, to .. ".before-" .. os.date("%Y%m%d-%H%M%S")) end
  if not os.rename(tmp .. "/" .. base, to) then M.copy_tree(tmp .. "/" .. base, to) end
  M.remove_tree(tmp)
  if rt:find("\nui_img=[^\n]*") then rt = rt:gsub("\nui_img=[^\r\n]*", "\nui_img=" .. name, 1)
  elseif rt:find("%[REAPER%]") then rt = rt:gsub("%[REAPER%]", "[REAPER]\nui_img=" .. name, 1)
  else rt = rt .. "\n[REAPER]\nui_img=" .. name .. "\n" end
  if not M.write(M.themes_dir .. name .. ".ReaperTheme", rt) then return nil, "couldn't write into ColorThemes" end
  M.recent_themes[name .. ".ReaperTheme"] = true
  return name .. ".ReaperTheme"
end
-- Before a pack's walk: its fonts and scripts are put aside (installed on your yes), and mods for themes you have become theme versions.
-- -> the paths the walk leaves out
function M.pack_prepass(root, pack, out)
  local skip, fonts, scripts, script_dirs = {}, {}, {}, {}
  local stage = M.here .. "/_staged/" .. M.file_name(pack)
  M.remove_tree(stage)
  reaper.EnumerateSubdirectories(root, -1); reaper.EnumerateFiles(root, -1)
  local one_top = reaper.EnumerateSubdirectories(root, 0) and not reaper.EnumerateSubdirectories(root, 1) and not reaper.EnumerateFiles(root, 0)
  local function scan(d, rel)
    reaper.EnumerateFiles(d, -1); reaper.EnumerateSubdirectories(d, -1)
    for i = 0, 5000 do
      local f = reaper.EnumerateFiles(d, i)
      if not f then break end
      local low = f:lower()
      if low:match("%.ttf$") or low:match("%.otf$") then
        reaper.RecursiveCreateDirectory(stage .. "/fonts", 0)
        if M.write(stage .. "/fonts/" .. f, M.read(d .. "/" .. f) or "") then fonts[#fonts + 1] = stage .. "/fonts/" .. f end
      elseif (low:match("%.lua$") or low:match("%.eel$")) and not script_dirs[d] and not (function()
          for k in pairs(script_dirs) do if d:sub(1, #k + 1) == k .. "/" then return true end end end)() then -- (helpers inside a copied folder: not actions)
        script_dirs[d] = true -- (the script's whole folder: its images and helpers come along)
        local to = stage .. "/scripts/" .. M.file_name(d:match("[^/]+$") or "scripts")
        M.copy_tree(d, to)
        reaper.EnumerateFiles(to, -1)
        for k = 0, 500 do local g = reaper.EnumerateFiles(to, k); if not g then break end if g:lower():match("%.lua$") or g:lower():match("%.eel$") then scripts[#scripts + 1] = to .. "/" .. g end end
      end
    end
    for i = 0, 500 do
      local s = reaper.EnumerateSubdirectories(d, i)
      if not s then break end
      local full, label = d .. "/" .. s, rel
      if s:lower() ~= "fonts" and reaper.file_exists(M.themes_dir .. s .. ".ReaperThemeZip") and not reaper.file_exists(d .. "/" .. s .. ".ReaperThemeZip") then
        label = (label ~= "" and label or pack)
        local v, why = M.make_variant(s, d, label)
        out[#out + 1] = { v and "theme" or "skipped", v or (s .. " (" .. label .. ")"), v and ("a version of " .. s .. " with this mod") or why }
        skip[full], skip[d .. "/" .. s .. ".ReaperTheme"] = true, true
      else
        scan(full, (one_top and d == root) and "" or ((rel ~= "" and (rel .. " ") or "") .. s))
      end
    end
  end
  scan(root, "")
  if #fonts > 0 then out[#out + 1] = { "note", "fonts", #fonts .. " font" .. (#fonts == 1 and "" or "s") .. " the theme uses: ReaPersona can install them for you", files = fonts, stage = stage } end
  if #scripts > 0 then out[#out + 1] = { "note", "scripts", #scripts .. " script" .. (#scripts == 1 and "" or "s") .. " (a theme adjuster, say): ReaPersona can add them to the Actions list", files = scripts, stage = stage } end
  return skip
end
-- Fonts for your account only (no administrator): Windows' per-user fonts folder and registry key, ~/Library/Fonts on a Mac.
-- REAPER sees them after a restart. -> how many, or nil + why
function M.install_fonts(files)
  if #files == 0 then return 0 end
  if reaper.GetOS():find("^Win") then
    local lines = { "$ErrorActionPreference = 'Stop'", "$d = Join-Path $env:LOCALAPPDATA 'Microsoft\\Windows\\Fonts'",
      "New-Item -ItemType Directory -Force -Path $d | Out-Null", "$k = 'HKCU:\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts'", "$n = 0" }
    for _, f in ipairs(files) do
      local w = f:gsub("/", "\\"):gsub("'", "''")
      lines[#lines + 1] = "$t = Join-Path $d (Split-Path -Leaf '" .. w .. "'); Copy-Item -LiteralPath '" .. w .. "' -Destination $t -Force; " ..
        "New-ItemProperty -Path $k -Name ([IO.Path]::GetFileNameWithoutExtension($t) + ' (TrueType)') -Value $t -PropertyType String -Force | Out-Null; $n++"
    end
    lines[#lines + 1] = "Write-Output $n"
    local ps1 = M.here .. "/_staged/install_fonts.ps1"
    reaper.RecursiveCreateDirectory(M.here .. "/_staged", 0)
    M.write(ps1, table.concat(lines, "\r\n") .. "\r\n")
    local code, text = sh('powershell -NoProfile -ExecutionPolicy Bypass -File "' .. ps1:gsub("/", "\\") .. '"', 60000)
    os.remove(ps1)
    if code ~= "0" then return nil, (text or ""):sub(1, 200) end
    return tonumber((text or ""):match("(%d+)%s*$")) or #files
  end
  local to = (os.getenv("HOME") or "") .. (M.IS_MAC and "/Library/Fonts" or "/.local/share/fonts")
  reaper.RecursiveCreateDirectory(to, 0)
  local n = 0
  for _, f in ipairs(files) do if M.write(to .. "/" .. f:match("[^/]+$"), M.read(f) or "") then n = n + 1 end end
  return n
end
-- A pack's scripts into Scripts/ReaPersona theme scripts/<pack>/, each added to the Actions list. -> the action names, or nil + why
function M.register_scripts(files, stage)
  local dest = res .. "/Scripts/ReaPersona theme scripts/" .. M.file_name(stage:match("[^/]+$") or "pack")
  M.copy_tree(stage .. "/scripts", dest)
  local names = {}
  for n, f in ipairs(files) do
    local p = dest .. f:sub(#stage + #"/scripts" + 1)
    if reaper.file_exists(p) and reaper.AddRemoveReaScript(true, 0, p, n == #files) ~= 0 then names[#names + 1] = p:match("[^/]+$") end
  end
  return names
end
function M.forget_staged(stage) if stage then M.remove_tree(stage) end end
local GET_OK = { "^https://stash%.reaper%.fm/", "^https://www%.dropbox%.com/", "^https://dl%.dropboxusercontent%.com/" }
local function fetch(url) -- a catalog download into _downloads -> its path, or nil + why
  url = url:gsub("[^%w%-%._~/:%%%?=&]", function(c) return string.format("%%%02X", c:byte()) end)
  local ok = false
  for _, pat in ipairs(GET_OK) do if url:match(pat) then ok = true end end
  if not ok then return nil, "not a download ReaPersona knows" end
  if url:match("dropbox%.com") then url = url:gsub("dl=0", "dl=1"); if not url:find("dl=1", 1, true) then url = url .. (url:find("?", 1, true) and "&" or "?") .. "dl=1" end end
  local name = urldecode(url:match("([^/?]+)%?") or url:match("[^/]+$") or ""):gsub("[^%w%._ %-%(%)]", "_"):gsub("^[%. ]+", "")
  local dir = M.here .. "/_downloads"
  reaper.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "/" .. (name ~= "" and name or "download")
  local code = sh(CURL .. ' -s -L --max-time 120 -o "' .. path .. '" "' .. url .. '"', 130000)
  local head = (M.read(path) or ""):sub(1, 300):lower()
  if code ~= "0" or head == "" or head:find("<!doctype", 1, true) or head:find("<html", 1, true) then os.remove(path); return nil, "the download didn't come (offline, or the site wants a browser)" end
  return path
end
function M.can_install_theme(name) local c = M.CATALOG[name]; return c ~= nil and type(c.get) == "string" end
-- One click: a catalog theme (or the pack it comes in) downloaded and taken in, under the name the catalog knows it by.
-- -> import results (like a dropped file), or nil + why
function M.install_theme(name)
  local c = M.CATALOG[name]
  if not (c and c.get) then return nil, "no download known" end
  local path, why = fetch(c.get)
  if not path then return nil, why end
  local low, got = path:lower(), nil
  if low:match("%.reaperthemezip$") or low:match("%.reapertheme$") then
    local n, w = M.import_theme(path, name)
    got = { { n and "theme" or "skipped", n or name, w } }
  else got = M.import_file(path) end
  os.remove(path)
  if not reaper.file_exists(M.themes_dir .. name) then got[#got + 1] = { "note", name, "wasn't in the download under that name: the pack's own themes are in your list" } end
  return got
end
function M.install_mod(base, n) -- one of a theme's mod packs from the catalog (rLive's ModPack, say) -> import results, or nil + why
  local m = ((M.CATALOG[base] or {}).mods or {})[n]
  if not (m and m.get) then return nil, "no download known" end
  local path, why = fetch(m.get)
  if not path then return nil, why end
  local got = M.import_file(path)
  os.remove(path)
  return got
end

-- ---------------------------------------------------------------- share a style, print its cheat sheet
function M.export(st, path)
  local out = {}
  for k, v in pairs(st) do if k ~= "user" then out[k] = v end end
  local th = M.theme_for(st)
  if th and th:match("%.ReaperTheme$") then out.theme_file = { name = th, text = M.read(M.themes_dir .. th) } end
  return M.write(path, M.json_encode({ reapersona = 1, style = out }) .. "\n")
end
function M.import(path) -- -> the style, or nil + why. Shortcuts need install_shortcuts.py (REAPER closed) after.
  local ok, d = pcall(M.json_decode, M.read(path) or "")
  local st = ok and type(d) == "table" and d.style
  if type(st) ~= "table" or type(st.id) ~= "string" or type(st.name) ~= "string" then return nil, "not a ReaPersona file" end
  -- (a file from someone else: its id goes into generated scripts and its names into file names, so only plain ones get through)
  if not st.id:match("^[%w_%-]+$") then st.id = "shared" end
  st.name = st.name:gsub("%c", " ")
  local same = M.by_id(st.id)
  if same and not same.user then st.id = M.new_id(st.id .. "_shared_") end -- (the same style of yours again replaces it)
  for _, field in ipairs({ "keys", "midi_keys", "feel" }) do
    if st[field] ~= nil and type(st[field]) ~= "table" then st[field] = nil end
  end
  for _, k in ipairs(st.midi_keys or {}) do if type(k[1]) ~= "string" or k[1]:find("%c") then return nil, "a MIDI key in it isn't a key name" end end
  if not (same and same.user and same.alt == st.alt) then -- (the same one of yours again keeps its layer)
    st.alt = free_alt()
    if not st.alt then return nil, "all 16 shortcut layers are in use" end
  end
  st.feel = M.safe_feel(st.feel)
  st.colours = M.safe_colours(st.colours)
  st.keys_from, st.blocks = nil, nil
  if type(st.theme_file) == "table" and type(st.theme_file.name) == "string" and type(st.theme_file.text) == "string" then
    local name = st.theme_file.name:match("[^/\\]+$") or ""
    if name:match("%.ReaperTheme$") and not name:find("..", 1, true) then
      if not reaper.file_exists(M.themes_dir .. name) then M.write(M.themes_dir .. name, st.theme_file.text) end
      st.theme = name
    end
  end
  st.theme_file = nil
  if st.theme ~= nil then st.theme = type(st.theme) == "string" and st.theme:match("[^/\\]+$") or nil end
  return save_user_style(st)
end
function M.keyname(s) -- styles store Windows key names; on a Mac REAPER's Ctrl is Cmd, Alt is Option and Win is Control
  if M.IS_MAC then s = s:gsub("Ctrl", "Cmd"):gsub("Alt", "Opt"):gsub("Win", "Control") end
  return s
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
  local rows, mouse = {}, {}
  for _, k in ipairs(M.keys_here(st.keys)) do table.insert(M.is_wheel(k[1]) and mouse or rows, { M.keyname(k[1]), k[3] }) end
  tbl("Arrange", rows)
  rows = {}
  for _, k in ipairs(st.midi_keys or {}) do rows[#rows + 1] = { M.keyname(k[1]), k[3] } end
  tbl("MIDI editor", rows)
  rows = {}
  for _, f in ipairs(st.feel or {}) do
    if f[1] == "mouse" then if M.for_os(f[2]) then mouse[#mouse + 1] = { "Drag/click", f[#f] } end else rows[#rows + 1] = { "Setting", f[#f] } end
  end
  tbl("Mouse", mouse)
  tbl("How it behaves", rows)
  rows = {}
  for _, x in ipairs(st.extras or {}) do rows[#rows + 1] = { x[3] or "", x[1] } end
  tbl("Where " .. esc(st.name) .. "'s features are in REAPER", rows)
  rows = {}
  for _, x in ipairs(st.tips or {}) do rows[#rows + 1] = { x[3] or "", x[1] } end
  tbl("Tips", rows)
  if st.docs then h[#h + 1] = "<p>Keys from: " .. esc(table.concat(st.docs, " · ")) .. "</p>" end
  reaper.RecursiveCreateDirectory(M.here .. "/cheat sheets", 0)
  local p = M.here .. "/cheat sheets/" .. M.file_name(st.name) .. ".html"
  if not M.write(p, table.concat(h, "\n")) then return nil, "couldn't write " .. p end
  return p
end

-- ---------------------------------------------------------------- your setup on another computer: one file, or a shared folder
-- (James, 5.10: "sync ReaPersona settings across my computers", e.g. smooth zoom changed on the laptop, and "export/import ... or sync
-- through Syncthing like StudioSync does".) Everything of yours as items: "persona <id>", "preset <id>", "recipe <name>" (a theme
-- recipe you imported), "setting <key>" (ReaPersona's own choices; not this computer's state such as the persona in use or where a
-- docker is) and "ext <section>|<key>" (the extensions ReaPersona recommends, which keep their settings in REAPER's ExtState). A setup
-- file holds them all; a shared folder (Syncthing, Google Drive, Dropbox...) holds one file per computer, so two computers never write
-- the same file, and per item the newest change wins. Your themes stay where they are: a persona naming a theme this computer doesn't
-- have uses the next one it does, as always.
M.EXT_SETTINGS = { -- (here: keys that belong to this computer, never copied)
  { section = "SmoothWheelScroll", name = "Smooth Wheel Scroll", here = { pos = true, win = true, dock = true } }, -- (its window's place)
  { section = "smooth_playhead", name = "ReaSmoothPlayhead", here = { orig_drawmode = true } }, -- (the theme's playhead, with its path)
}
local HERE_ONLY = { style = true, orig = true, ["orig project"] = true, migrated = true, page = true, search = true, ["follow beat"] = true,
  ["midi dock"] = true, ["theme my_reaper"] = true, ["theme path my_reaper"] = true, welcomed = true, ["text size"] = true, look = true, view = true,
  ["last style"] = true, ["menu once"] = true, onboarded = true, ["screen reader"] = true, workflow = true, ["first setup"] = true,
  ["update seen"] = true } -- (when this computer last looked, 5.23) -- (screen reader: each computer's own, or one
  -- computer turning the menu off could lock a screen-reader user on another out of it. Review, 5.14)
local HERE_PREFIX = { "docker ", "params ", "forks ", "sync ", "declined ", "inputs " }
function M.synced_setting(k) -- a ReaPersona ExtState key that goes to your other computers (pure)
  if HERE_ONLY[k] then return false end
  for _, p in ipairs(HERE_PREFIX) do if k:sub(1, #p) == p then return false end end
  return true
end
local SYNC_KINDS = { persona = true, preset = true, recipe = true, setting = true, ext = true, -- (the advanced ones: M.ADVANCED)
  pref = true, xstate = true, repo = true, pkg = true, tpl = true, code = true, theme = true, ini = true }
local TEXT_KINDS = { setting = true, ext = true, pref = true, xstate = true, repo = true } -- (their values are strings; the rest are tables)
local GONE_KINDS = { persona = true, preset = true, recipe = true } -- (deleting one of these deletes it on your other computers too)
function M.setup_items() -- -> everything of yours as items; the kinds whose file doesn't parse (left alone: nothing deleted or written)
  local items, skip = {}, {}
  M.sync_bad = {}
  local function add(kind, list, field, path)
    if not list then skip[kind] = true; M.sync_bad[#M.sync_bad + 1] = ({ persona = "user_styles.json", preset = "presets.json", recipe = "user_themes.json" })[kind]; return end
    for k, v in pairs(list) do
      local id = field and type(v) == "table" and v[field] or (not field and k)
      if type(id) == "string" and id ~= "" and type(v) == "table" then items[kind .. " " .. id] = v end
    end
  end
  local function readable(path) local d = M.load_json(path); if d and next(d) == nil and reaper.file_exists(path) and not M.read(path) then return nil end return d end
  local u, pr, rc = readable(USERS), readable(PRESETS), readable(M.here .. "/user_themes.json")
  add("persona", u and (u.styles or {}), "id")
  add("preset", pr and (pr.presets or {}), "id")
  add("recipe", rc, nil)
  local ini, keys = M.read(res .. "/reaper-extstate.ini") or "", {}
  for _, k in ipairs(M.extstate_keys(ini, M.SECTION)) do keys[k] = true end
  for _, k in ipairs(extstate_names()) do keys[k] = true end -- (some may not be in the file yet: REAPER writes it later)
  for k in pairs(keys) do
    local v = reaper.GetExtState(M.SECTION, k)
    -- (a look never saved here isn't a change: sent as "", it was newer than the look another computer saved, and won. 5.21.1)
    if M.synced_setting(k) and not ((k == M.LOOK_KEY or k == "favourites") and v == "") then items["setting " .. k] = v end
  end
  for _, x in ipairs(M.EXT_SETTINGS) do
    for _, k in ipairs(M.extstate_keys(ini, x.section)) do
      if not x.here[k] then items["ext " .. x.section .. "|" .. k] = reaper.GetExtState(x.section, k) end
    end
  end
  local mine_now = (M.current() or {}).id == "my_reaper" -- (a persona sets mouse modifiers and options live: those aren't your own setup)
  for _, a in ipairs(M.ADVANCED) do -- (advanced: only the parts switched on; the rest are left alone both ways)
    if M.advanced_on(a.id) and not M.quick and (mine_now or (a.id ~= "prefs" and a.id ~= "keys")) and (M.sync_folder() ~= "" or not M.FILE_PARTS[a.id]) then
      local ok, err = pcall(a.collect, items, ini)
      if not ok then M.log("sync " .. a.id .. ": " .. tostring(err)); for _, k in ipairs(a.kinds) do skip[k] = true end end
    else for _, k in ipairs(a.kinds) do skip[k] = true end end
  end
  return items, skip
end
-- Merging: state[item] = { t = when it last changed (seconds), h = its text, v = its value, del = true once deleted }. What changed here
-- since the last look gets the time now (an item seen for the first time gets `seed`: 0 when you chose to take the folder's setup,
-- so the other computers' versions win); then each item another computer changed later than this one is taken. Equal times keep
-- this computer's. -> the items to change here: { item, v (nil: delete it), was (its state before, to put back if writing fails) }
function M.sync_merge(state, mine, skip, theirs, now, seed) -- (pure; seed: a time, or { [kind] = time } with now for the rest)
  local function kind(item) return item:match("^(%a+) ") end
  local function seed_of(item) if type(seed) == "table" then return seed[kind(item)] or now end return seed or now end
  -- (a change here is always later than what it replaces, even after a computer with a clock ahead wrote a time from the future; and an
  -- incoming time is never believed beyond a day ahead. Review 5.11, H4)
  local function later_than(st) return math.max(now, (st and tonumber(st.t) or 0) + 1) end
  local changes = 0
  for item, v in pairs(mine) do
    local h, st = M.json_encode(v), state[item]
    if not st then state[item] = { t = seed_of(item), h = h, v = v }; changes = changes + 1
    elseif st.del or st.h ~= h then state[item] = { t = later_than(st), h = h, v = v }; changes = changes + 1 end
  end
  for item, st in pairs(state) do
    local k = kind(item)
    if not st.del and mine[item] == nil and GONE_KINDS[k] and not skip[k] then state[item] = { t = later_than(st), h = "", del = true }; changes = changes + 1 end
  end
  local best = {}
  for _, f in ipairs(theirs) do
    for item, r in pairs(type(f.items) == "table" and f.items or {}) do
      local k = type(item) == "string" and kind(item)
      local good = type(r) == "table" and tonumber(r.t) and k and SYNC_KINDS[k] and not skip[k]
      if good and not r.del then
        if TEXT_KINDS[k] then good = type(r.v) == "string" else good = type(r.v) == "table" end
      end
      local t = good and math.min(tonumber(r.t), now + 86400)
      if good then
        local h = r.del and "" or M.json_encode(r.v)
        local b = best[item]
        if not b or t > b.t or (t == b.t and h > b.h) then best[item] = { t = t, h = h, v = r.v, del = r.del and true or nil } end -- (ties: the larger hash, everywhere)
      end
    end
  end
  local out = {}
  for item, r in pairs(best) do
    local st = state[item]
    local h = r.h
    if (not st or r.t > st.t or (r.t == st.t and h > (st.h or ""))) and not (st and st.h == h and (st.del or false) == (r.del or false)) then
      if not (r.del and (not st or st.del)) then out[#out + 1] = { item = item, v = (not r.del) and r.v or nil, was = st } end
      state[item] = { t = r.t, h = h, v = r.v, del = r.del }
      changes = changes + 1
    end
  end
  table.sort(out, function(a, b) return a.item < b.item end)
  return out, changes
end
-- Items into this computer's files and ExtState. A file of yours that doesn't parse is never written over: its items wait (they're
-- put back in the state, so they're tried again once it's fixed). -> { personas, presets, recipes, settings, ext = counts, install =
-- true when a persona with a shortcut layer of its own came in (its keys need installing), failed = { items } }
-- What may come in: the same checks as what goes out, so a sync or setup file written by someone else can't switch on syncing, point it
-- elsewhere, set paths, or put files where REAPER runs them (Review 5.11, H2). -> true when the item may be taken in (pure but for EXT_SETTINGS)
local FILE_DIRS = { tpl = { "FXChains/", "TrackTemplates/", "ProjectTemplates/", "MIDINoteNames/", "KeyMaps/" }, code = { "Scripts/", "Effects/" }, theme = { "ColorThemes/" } }
function M.item_allowed(item, v)
  local k, rest = tostring(item):match("^(%a+) (.+)$")
  if not k then return false end
  if k == "setting" then return M.synced_setting(rest) end
  if k == "ext" then
    local sec, key = rest:match("^([^|]+)|(.+)$")
    for _, x in ipairs(M.EXT_SETTINGS) do if x.section == sec then return not x.here[key] end end
    return false
  end
  if k == "xstate" then local sec, key = rest:match("^([^|]+)|(.+)$"); return sec ~= nil and M.xstate_synced(sec, key, v) end
  if k == "pref" then return M.pref_synced(rest, v) end
  if FILE_DIRS[k] then
    if rest:find("..", 1, true) or rest:find("\\", 1, true) or rest:match("^/") or rest:find(":", 1, true) or rest:lower():find("__startup") then return false end
    local ok = false
    for _, d in ipairs(FILE_DIRS[k]) do if rest:sub(1, #d) == d then ok = true end end
    if k == "code" then
      for _, x in ipairs(M.CODE_SKIP) do if rest:sub(1, #x) == x then ok = false end end
      ok = ok and M.code_file(rest)
    end
    return ok and (v == nil or (type(v) == "table" and tostring(v.h):match("^%x+$") ~= nil and #tostring(v.h) == 16))
  end
  if k == "ini" then return ({ ["reaper-kb.ini"] = 1, ["reaper-mouse.ini"] = 1, ["reaper-menu.ini"] = 1 })[rest] ~= nil and (v == nil or (type(v) == "table" and tostring(v.h):match("^%x+$") ~= nil)) end
  if k == "persona" or k == "preset" then return rest:match("^[%w_%-]+$") ~= nil end
  return SYNC_KINDS[k] ~= nil
end
local function apply_items(list)
  local rep = { personas = 0, presets = 0, recipes = 0, settings = 0, ext = 0, failed = {}, refused = 0 }
  local by = { persona = {}, preset = {}, recipe = {} }
  local kept = {}
  for _, a in ipairs(list) do if M.item_allowed(a.item, a.v) then kept[#kept + 1] = a else rep.refused = rep.refused + 1; M.log("sync: not taken in (not allowed): " .. tostring(a.item)) end end
  list = kept
  for _, a in ipairs(list) do
    local k, rest = a.item:match("^(%a+) (.+)$")
    if k == "setting" then reaper.SetExtState(M.SECTION, rest, a.v or "", true); rep.settings = rep.settings + 1
      if rest == "follow projects" and a.v == "1" then M.start_following() end
      if rest == "sync advanced" then M.repos_changed = true end
      if rest == M.LOOK_KEY then rep.look = true end
    elseif k == "ext" then
      local sec, key = rest:match("^([^|]+)|(.+)$")
      if sec then reaper.SetExtState(sec, key, a.v or "", true); rep.ext = rep.ext + 1 end
    elseif by[k] then by[k][#by[k] + 1] = { id = rest, a = a }
    elseif M.ADVANCED_APPLY[k] then
      local ok, res = pcall(M.ADVANCED_APPLY[k], rest, a.v, rep)
      if ok and res ~= false then rep.advanced = (rep.advanced or 0) + 1 else rep.failed[#rep.failed + 1] = a; if not ok then M.log("sync apply " .. a.item .. ": " .. tostring(res)) end end
    end
  end
  local function files(kind, path, wrap, count)
    if #by[kind] == 0 then return end
    local d = M.load_json(path)
    local list = d and (wrap and (d[wrap] or {}) or d)
    if not list then for _, x in ipairs(by[kind]) do rep.failed[#rep.failed + 1] = x.a end return end
    for _, x in ipairs(by[kind]) do
      local v = x.a.v
      if wrap then
        for n = #list, 1, -1 do if type(list[n]) == "table" and list[n].id == x.id then table.remove(list, n) end end
        if v then
          v.id = x.id
          if type(v.name) == "string" then v.name = v.name:gsub("%c", " ") end
          if kind == "persona" and v.feel ~= nil then v.feel = M.safe_feel(v.feel) end
          if (kind == "persona" or kind == "preset") and v.colours ~= nil then v.colours = M.safe_colours(v.colours) end
          list[#list + 1] = v
          if kind == "persona" and not v.keys_from and (tonumber(v.alt) or 0) > 0 and #(v.keys or {}) > 0 then rep.install = true end
        end
      else list[x.id] = v end
    end
    local ok = M.save_json(path, wrap and { [wrap] = list } or setmetatable(list, M.OBJECT))
    if ok then rep[count] = rep[count] + #by[kind] else for _, x in ipairs(by[kind]) do rep.failed[#rep.failed + 1] = x.a end end
  end
  files("persona", USERS, "styles", "personas")
  files("preset", PRESETS, "presets", "presets")
  files("recipe", M.here .. "/user_themes.json", nil, "recipes")
  if rep.personas + rep.presets + rep.recipes > 0 then M.reload_users() end
  if M.repos_changed and reaper.ReaPack_ProcessQueue then M.repos_changed = nil; reaper.ReaPack_ProcessQueue(true) end -- (repositories kept)
  if rep.look and (M.current() or {}).id == "my_reaper" then M.use(M.current()) end -- (your look came in while you're on it: shown now; otherwise next time)
  return rep
end
function M.setup_summary(rep) -- "2 personas, 5 settings and Smooth Wheel Scroll's settings" (pure)
  local parts = {}
  for _, x in ipairs({ { "personas", "persona" }, { "presets", "preset" }, { "recipes", "theme recipe" }, { "settings", "setting" } }) do
    local n = rep[x[1]] or 0
    if n > 0 then parts[#parts + 1] = n .. " " .. x[2] .. (n == 1 and "" or "s") end
  end
  if (rep.ext or 0) > 0 then parts[#parts + 1] = "extension settings" end
  if (rep.advanced or 0) > 0 then parts[#parts + 1] = rep.advanced .. " of REAPER's own" end
  if #parts == 0 then return (rep.failed and #rep.failed > 0) and (#rep.failed .. " waiting to come in") or "nothing new" end
  return #parts == 1 and parts[1] or (table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts])
end
M.SETUP_RESTART = "Smooth Wheel Scroll and ReaSmoothPlayhead read their settings when REAPER starts."

-- ---------------------------------------------------------------- advanced: REAPER itself, on your other computers too
-- (James, 5.11: "all settings and defaults ... and even additional scripts and other things that are used ... as an advanced feature
-- checkbox ... all my settings saved and loadable across devices including mac (install anything it's missing)".) Each part is switched
-- on in Settings (ExtState "sync advanced", a list of ids), on each computer: a part that's off is neither sent nor taken there.
--   pref     REAPER's preferences (reaper.ini's [REAPER] keys), written into reaper.ini when REAPER restarts (Apply). Never this computer's:
--            window places, recent files, paths, audio and MIDI devices, dockers.
--   xstate   other scripts' settings (their ExtState), but not ones that hold this computer's paths or StudioSync's machine state.
--   ini      the keymap, mouse modifiers, menus and toolbars, window sets: merged (never replaced) into this computer's when REAPER
--            restarts (Apply, like installing shortcuts). The keymap keeps this computer's script registrations and ReaPersona's lines.
--   tpl      FX chains, track and project templates, MIDI note names, key maps: copied as files.
--   code     your own scripts and JSFX: the ones ReaPack didn't install (it installs those itself, see pkg), not ReaPersona's own.
--   theme    the themes in ColorThemes.
--   repo/pkg ReaPack's repositories, and its packages: the ones another computer has and this one doesn't are offered (Install).
-- Files travel by content: <folder>/blobs/<hash>, written once, read by the others. Deleting a file doesn't delete it elsewhere.
M.ADVANCED = {
  { id = "prefs", name = "REAPER's preferences", kinds = { "pref" }, tip = "Everything in Preferences that isn't this computer's own (paths, audio and MIDI devices, window places, recent files): taken in when REAPER restarts (Apply)." },
  { id = "xstate", name = "Other scripts' settings", kinds = { "xstate" }, tip = "What your other scripts and extensions remember in REAPER (their ExtState), apart from file paths and StudioSync's own." },
  { id = "keys", name = "Shortcuts, mouse, menus and toolbars", kinds = { "ini" }, tip = "Your keymap, mouse modifiers, menus and toolbars, merged into this computer's when REAPER restarts (Apply). Window sets stay each computer's: they hold its screens' places." },
  { id = "templates", name = "FX chains and templates", kinds = { "tpl" }, tip = "FX chains, track templates, project templates, MIDI note names and key map files." },
  { id = "code", name = "Your scripts and JSFX", kinds = { "code" }, tip = "Scripts and JSFX you made or copied in yourself (ReaPack's are installed by ReaPack, below). Needs Python." },
  { id = "themes", name = "Themes", kinds = { "theme" }, tip = "Every theme file in ColorThemes. Can be large." },
  { id = "packages", name = "ReaPack repositories and packages", kinds = { "repo", "pkg" }, tip = "Your ReaPack repositories, and the packages your other computers have and this one doesn't, ready to install. Needs Python." },
}
function M.advanced_on(id) return (";" .. reaper.GetExtState(M.SECTION, "sync advanced") .. ";"):find(";" .. id .. ";", 1, true) ~= nil end
function M.set_advanced(id, on)
  local keep = {}
  for x in reaper.GetExtState(M.SECTION, "sync advanced"):gmatch("[^;]+") do if x ~= id then keep[#keep + 1] = x end end
  if on then keep[#keep + 1] = id end
  reaper.SetExtState(M.SECTION, "sync advanced", table.concat(keep, ";"), true)
end

-- Preferences that belong to this computer (pure): window places and sizes, recent files and tabs, paths, devices, dockers, splash.
local PREF_HERE = { "_x$", "_y$", "_w$", "_h$", "_ew$", "_eh$", "_dx$", "_dy$", "_mh$", "^wnd_", "_vis$", "_dock$", "_max$", "wid$", "wid_",
  "colwid", "_div", "^last", "recent", "projecttab", "path", "dir$", "^mf_", "^midiins", "^midiouts", "^midilat", "^midiinflag", "^csurf",
  "^docker", "^dockheight", "fullscreenrect", "^splash", "^multinst", "^hwfx", "^vst", "^lv2", "^clap", "^au_", "workthreads", "renderthreads",
  "^prefs", "^pspage", "^config", "screensetwnd", "^audio", "^asio", "^wasapi", "^dsound", "^coreaudio", "^waveout", "^alsa", "^jack", "^pulse", "^ks_",
  "font", "uiscale", "retina", "hidpi", "^adjrec", "lat[io][nu]t?$", "latency", "^bsize", "^bufsize", -- (an interface's latency offsets, buffers)
  "hwout", "^zoom$", "^vzoom", "^toppane", "^langpack", "tmpl", "^lastproj", ":", "^ccresettab", "^insertmtracklast", "^errnowarn" }
function M.pref_synced(k, v) -- (pure)
  local low = k:lower()
  for _, pat in ipairs(PREF_HERE) do if low:find(pat) then return false end end
  if type(v) == "string" and (v:match("^%a:[\\/]") or v:match("^/") or v:match("^\\\\")) then return false end -- (a path on this computer)
  return true
end
-- Settings REAPER keeps per project (Mespotine's config-variable reference, REAPER 7.34): reaper.ini holds the defaults for new projects,
-- but asking REAPER answers for the project in front, so a 48 kHz voiceover tab would go out as everyone's default. These are read from
-- the file. (5.16.1)
local PROJECT_VARS = {}
for k in ([[afxcfg audioprshift autoxfade defpitchcfg defstretchmode envmgropts feedbackmode itemmixflag itemtimelock loop loopgran loopgranlen
  mastermutesolo mixrowflags opennotes panlaw panlawflags panmode playrate playresamplemode pooledenvattach projalignbeatsrate projbeatbase projbpm
  projdefrecpath projfrbase projfrdrop projgriddiv projgriddivsnap projgridframe projgridmin projgridsnapmin projgridswing projgroupover projgroupsel
  projintmix projmasternch projmasterpanlaw projmasterpanlawflags projmasterpanmode projmastervuflags projmaxlen projmaxlenuse projmeaslen projmeasoffs
  projmeasoffsruler projmetrobeatlen projmetroclick projmetrocountin projmetroen projmetrof1 projmetrof2 projmetropattern projmetrov1 projmetrov2
  projpeaksgain projrecforopencopy projrecmode projrelpath projrenderaddtoproj projrenderbrickwall projrenderdither projrenderfadein
  projrenderfadeinshape projrenderfadeout projrenderfadeoutshape projrenderlimit projrendernch projrendernorm projrendernormtgt projrenderpadend
  projrenderpadstart projrenderqdelay projrenderrateinternal projrenderresample projrendersrate projrenderstems projrendertrimend projrendertrimstart
  projripedit projripeditcfg projsellock projshowgrid projsmpteahead projsmptefw_rec projsmpteinput projsmptemaxfree projsmpteoffs projsmpterate
  projsmpterateuseproj projsmpteresync projsmpteresync_rec projsmpteskip projsmptesync projsrate projsrateuse projtakelane projtimemode projtimeoffs
  projtrackgroupdisabled projtsdenom projvidflags projvidh projvidw psmaxv psminv reccfg rendercfg renderclosewhendone rendertaillen rendertails
  silenceflags silencethreshdb tempoenvtimelock vzoom2 vzoom3 zoom]]):gmatch("%S+") do PROJECT_VARS[k] = true end
function M.project_var(k) return PROJECT_VARS[k:lower()] == true end -- (pure)
local XSTATE_HERE ={ ReaPersona = true, BandSync = true, StudioSync = true, ["reaper-daemon"] = true, reaper_daemon = true }
function M.xstate_synced(section, k, v) -- (pure)
  if XSTATE_HERE[section] then return false end
  for _, x in ipairs(M.EXT_SETTINGS) do if x.section == section then return false end end -- (already: the "ext" items)
  local low = k:lower()
  if low:find("pos") or low:find("dock") or low:find("^wnd") or low:find("window") or low:find("_x$") or low:find("_y$") or low:find("path") or low:find("dir$") then return false end
  if type(v) == "string" and (v:match("^%a:[\\/]") or v:match("^/Users/") or v:match("^/home/") or v:match("^\\\\")) then return false end
  if k:find("{%x%x%x%x%x%x%x%x%-") or low:find("undo") or (type(v) == "string" and #v > 4096) then return false end -- (one project's, or a cache)
  return true
end

-- A content hash (64-bit FNV-1a over 8-byte words, then the length), enough to tell files apart for syncing. Pure.
function M.content_hash(s)
  local h, prime, n, i = -3750763034362895579, 1099511628211, #s, 1
  while i + 7 <= n do h = (h ~ string.unpack("<i8", s, i)) * prime; i = i + 8 end
  for j = i, n do h = (h ~ s:byte(j)) * prime end
  return string.format("%016x", h ~ n)
end
-- The keymap as it goes to your other computers: without ReaPersona's own lines (each computer installs its own) and without
-- registrations of ReaPersona's scripts (their paths differ between installs). Pure. installed: { ["flags key cmd section"] = true },
-- midi_cmds: { [command] = true } (the MIDI key scripts).
function M.kb_shared(text, installed, midi_cmds)
  local out = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local f, k, cmd, sec = line:match("^KEY (%d+) (%d+) (%S+) (%d+)")
    local drop = false
    if f then drop = installed[f .. " " .. k .. " " .. cmd .. " " .. sec] or (sec == "32060" and midi_cmds[cmd]) or line:find("# ReaPersona", 1, true) ~= nil
    elseif line:match("^SCR ") then drop = line:find('"?ReaPersona/') ~= nil end
    if not drop then out[#out + 1] = line end
  end
  table.sort(out) -- (a canonical order: two computers that have taken each other's lines end up with the same text, so nothing goes round again)
  return table.concat(out, "\n") .. "\n"
end
function M.menu_shared(text) -- the menus as they go out: without ReaPersona's own toolbars (each computer installs its own) (pure)
  local out, drop, cur = {}, false, {}
  local function flush() if not drop then for _, l in ipairs(cur) do out[#out + 1] = l end end cur, drop = {}, false end
  for line in (text or ""):gmatch("[^\r\n]+") do
    if line:match("^%[") then flush() end
    cur[#cur + 1] = line
    if line:match("^title=ReaPersona") or line:match("^title=DAW Styles") then drop = true end
  end
  flush()
  return table.concat(out, "\n") .. "\n"
end
function M.ini_canon(text) -- an ini file in a canonical order: sections sorted, and keys within each (pure)
  local secs, order, cur = {}, {}, nil
  for line in (text or ""):gmatch("[^\r\n]+") do
    local name = line:match("^%[(.+)%]%s*$")
    if name then cur = name; if not secs[name] then secs[name] = {}; order[#order + 1] = name end end
    if not name and cur and line:find("=", 1, true) then secs[cur][#secs[cur] + 1] = line end
  end
  table.sort(order)
  local out = {}
  for _, name in ipairs(order) do
    table.sort(secs[name])
    out[#out + 1] = "[" .. name .. "]"
    for _, l in ipairs(secs[name]) do out[#out + 1] = l end
  end
  return table.concat(out, "\n") .. "\n"
end

-- Folders that hold a script's data, not the script (restore points, logs, test results, caches, version control): never walked.
M.JUNK_DIRS = { backups = 1, autosaves = 1, __pycache__ = 1, [".git"] = 1, [".stfolder"] = 1, [".stversions"] = 1, _tmp = 1, tmp = 1, temp = 1,
  cache = 1, logs = 1, log = 1, results = 1, restore_points = 1, node_modules = 1, [".svn"] = 1, venv = 1, [".venv"] = 1, ["site-packages"] = 1 }
-- Your own scripts are code and what it needs (images, fonts, text): not projects, audio, logs, archives or programs, nor big files.
local CODE_NOT = { rpp = 1, ["rpp-bak"] = 1, ["rpp-undo"] = 1, wav = 1, mp3 = 1, flac = 1, ogg = 1, aif = 1, aiff = 1, m4a = 1, mp4 = 1, mov = 1,
  log = 1, pyc = 1, bak = 1, pack = 1, idx = 1, pdf = 1, zip = 1, rar = 1, ["7z"] = 1, exe = 1, dll = 1, dylib = 1, so = 1, reapeaks = 1 }
function M.code_file(rel) -- one of your scripts' files worth carrying? (pure)
  local e = rel:match("%.([^./]+)$")
  return not (e and CODE_NOT[e:lower()])
end
local CODE_MAX = 4 * 1024 * 1024
-- Files: walk a folder of the resource path. -> { [relative path] = full path }
local function walk(base, rel, out, keep)
  local dir = base .. (rel ~= "" and ("/" .. rel) or "")
  reaper.EnumerateFiles(dir, -1)
  for i = 0, 100000 do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    local r = (rel ~= "" and (rel .. "/") or "") .. f
    if not f:match("%.bak$") and not f:match("%.tmp$") and not f:match("~$") and not f:match("%.bad%-") and (not keep or keep(r)) then out[r] = dir .. "/" .. f end
  end
  reaper.EnumerateSubdirectories(dir, -1)
  for i = 0, 100000 do
    local d = reaper.EnumerateSubdirectories(dir, i)
    if not d then break end
    if not M.JUNK_DIRS[d:lower()] and not d:match("^_tmp") then
      local r = (rel ~= "" and (rel .. "/") or "") .. d
      if not keep or keep(r .. "/") then walk(base, r, out, keep) end
    end
  end
  return out
end
M.walk = walk
local MAX_FILE = 64 * 1024 * 1024 -- (bigger files stay where they are)
local sig_cache -- (path -> { sig = "size|mtime", h = hash }: hashed again only when a file changed; kept in sync_state.json)
local function file_value(path, max)
  local sig
  max = max or MAX_FILE
  if reaper.JS_File_Stat then
    local ok, size, _, mtime = reaper.JS_File_Stat(path)
    if ok == 0 then if size > max then return nil end sig = size .. "|" .. tostring(mtime) end
  end
  local c = sig and sig_cache and sig_cache[path]
  if c and c.sig == sig then return { h = c.h, n = c.n } end
  local text = M.read(path)
  if not text or #text > max then return nil end
  local h = M.content_hash(text)
  if sig_cache and sig then sig_cache[path] = { sig = sig, h = h, n = #text } end
  return { h = h, n = #text }, text
end
local function blob_dir() return M.sync_folder():gsub("[/\\]+$", "") .. "/blobs" end
local function publish(path, v, text) -- the file's content into the folder's blobs, once
  local b = blob_dir() .. "/" .. v.h
  if reaper.file_exists(b) then return true end
  reaper.RecursiveCreateDirectory(blob_dir(), 0)
  text = text or M.read(path)
  return text ~= nil and M.write(b, text)
end
local function collect_files(items, kind, base_rel, keep, max)
  for rel, full in pairs(walk(res, base_rel, {}, keep)) do
    local v, text = file_value(full, max)
    if v and publish(full, v, text) then items[kind .. " " .. rel] = v end
  end
end
-- (not presets/ or reaper-render.ini: one file per plug-in, or one for all render presets, that every computer has its own of, so the newest
-- whole file would replace another computer's presets. In 5.13.0 only, review 5.14)
local TPL_DIRS = { "FXChains", "TrackTemplates", "ProjectTemplates", "MIDINoteNames", "KeyMaps" }
-- (ReaPersona and StudioSync are kept apart from package syncing: a computer may run a copy installed by hand, and ReaPack's would be a
-- second one beside it)
M.PKG_HERE = { ReaPersona = true, StudioSync = true }
local CODE_SKIP = { "Scripts/ReaPersona/", "Scripts/__startup.lua", "Scripts/MIDI Control Center/midi_control_center/dev/", "Scripts/StudioSync",
  "Scripts/Cockos/", "Scripts/reaper-daemon/", "Scripts/BandSync" } -- (ReaPersona's own; each computer's startup; StudioSync's (and its old BandSync name); REAPER's own; a tool with its data)
M.CODE_SKIP = CODE_SKIP
M.owned = nil -- (ReaPack's files, relative to the resource path: from setup_helper.py; nil until read)
local function read_packages() -- -> { installed = { {remote, category, package, type, desc, author} }, owned = { path } }, or nil + why
  if not M.python() then return nil, "it needs Python" end
  local out = M.here .. "/_packages.json" -- (REAPER's ExecProcess stalls on a long answer: it comes back in a file)
  local code, text = sh(M.py .. ' "' .. M.here .. '/setup_helper.py" packages "' .. res .. '" "' .. out .. '"', 30000)
  local ok, d = pcall(M.json_decode, code == "0" and M.read(out) or "")
  os.remove(out)
  if code ~= "0" or not ok or type(d) ~= "table" then return nil, "setup_helper.py: " .. tostring(text):sub(1, 200) end
  M.owned = {}
  for _, f in ipairs(d.owned or {}) do M.owned[f] = true end
  return d
end
local COLLECT = {
  pref = function(items)
    local waiting = M.load_json(M.here .. "/pending/prefs.json") or {} -- (taken in, waiting for the restart: not this computer's change)
    local t = M.read(res .. "/reaper.ini") or ""
    local body = t:match("^%[[Rr][Ee][Aa][Pp][Ee][Rr]%]\r?\n(.-)\n%[") or t:match("\n%[[Rr][Ee][Aa][Pp][Ee][Rr]%]\r?\n(.-)\n%[") or ""
    for k, v in body:gmatch("([^=\r\n]+)=([^\r\n]*)") do
      if reaper.get_config_var_string and not M.project_var(k) then local ok, live = reaper.get_config_var_string(k); if ok then v = live end end
      if M.pref_synced(k, v) and waiting[k] == nil then items["pref " .. k] = v end
    end
  end,
  xstate = function(items, ini)
    for section in ini:gmatch("\n%[([^%]\r\n]+)%]") do
      for _, k in ipairs(M.extstate_keys(ini, section)) do
        local v = reaper.GetExtState(section, k)
        if M.xstate_synced(section, k, v) then items["xstate " .. section .. "|" .. k] = v end
      end
    end
    local first = ini:match("^%[([^%]\r\n]+)%]") -- (the file's first section has no newline before it)
    if first then for _, k in ipairs(M.extstate_keys("\n" .. ini, first)) do
      local v = reaper.GetExtState(first, k)
      if M.xstate_synced(first, k, v) then items["xstate " .. first .. "|" .. k] = v end
    end end
  end,
  ini = function(items)
    local installed, midi = {}, {}
    for _, l in ipairs((M.load_json(M.here .. "/installed.json") or {}).lines or {}) do installed[l] = true end
    for _, id in pairs(M.scripts.midi or {}) do midi[tostring(id)] = true end
    for _, name in ipairs({ "reaper-kb.ini", "reaper-mouse.ini", "reaper-menu.ini" }) do -- (not reaper-screensets.ini: screen places)
      -- (one waiting in pending/ for the restart isn't read: the old file would go back out as a change and undo it. Review 5.11, H1)
      local text = not reaper.file_exists(M.here .. "/pending/" .. name) and M.read(res .. "/" .. name)
      if text and name == "reaper-menu.ini" then text = M.menu_shared(text) end
      if text then
        if name == "reaper-kb.ini" then text = M.kb_shared(text, installed, midi) else text = M.ini_canon(text) end
        local v = { h = M.content_hash(text), n = #text }
        if publish(nil, v, text) then items["ini " .. name] = v end
      end
    end
  end,
  tpl = function(items) for _, d in ipairs(TPL_DIRS) do collect_files(items, "tpl", d) end end,
  code = function(items)
    if not M.owned and not read_packages() then error("ReaPack's file list (needs Python)") end
    for _, d in ipairs({ "Scripts", "Effects" }) do
      collect_files(items, "code", d, function(r)
        for _, x in ipairs(CODE_SKIP) do if r:sub(1, #x) == x then return false end end
        return not M.owned[r] and (r:sub(-1) == "/" or M.code_file(r))
      end, CODE_MAX)
    end
  end,
  theme = function(items) collect_files(items, "theme", "ColorThemes") end,
  repo = function(items)
    local t = M.read(res .. "/reapack.ini") or ""
    for name, url, en, auto in (M.ini_section(t, "remotes") or ""):gmatch("\nremote%d+=([^|\r\n]+)|([^|\r\n]+)|(%d)|(%d)") do
      if not M.PKG_HERE[name] then items["repo " .. name] = url .. "|" .. en .. "|" .. auto end
    end
  end,
  pkg = function(items)
    local d = assert(read_packages())
    for _, e in ipairs(d.installed or {}) do
      if not M.PKG_HERE[e[1]] then items["pkg " .. e[1] .. "|" .. e[2] .. "|" .. e[3]] = { type = e[4], desc = e[5], author = e[6] } end
    end
  end,
}
for _, a in ipairs(M.ADVANCED) do a.collect = function(items, ini) for _, k in ipairs(a.kinds) do COLLECT[k](items, ini) end end end
-- (H5: the parts made of files need the sync folder for their content: without one they're left out, never written to the drive's root)
M.FILE_PARTS = { keys = true, templates = true, code = true, themes = true }

-- Taking an item in. A file whose content hasn't arrived yet (Syncthing still copying it) returns false: it's tried again next time.
local function from_blob(v)
  local h = tostring(v and v.h)
  if not h:match("^%x+$") then return nil end
  local b = blob_dir() .. "/" .. h
  local text = reaper.file_exists(b) and M.read(b) or nil
  if text and M.content_hash(text) ~= h then return nil end -- (still being copied in, or not what it says)
  return text
end
local function put_file(rel, v)
  if rel:find("%.%.") or rel:match("^[/\\]") or rel:match("^%a:") then return false end -- (only inside the resource path)
  local text = from_blob(v)
  if not text or M.content_hash(text) ~= v.h then return false end
  local full = res .. "/" .. rel
  reaper.RecursiveCreateDirectory(full:match("^(.*)/[^/]*$"), 0)
  local ok = M.write(full, text)
  if ok and sig_cache and reaper.JS_File_Stat then -- (so the copy isn't taken for a change of this computer's)
    local o, size, _, mtime = reaper.JS_File_Stat(full)
    if o == 0 then sig_cache[full] = { sig = size .. "|" .. tostring(mtime), h = v.h, n = #text } end
  end
  return ok
end
function M.restart_pending() -- what waits for REAPER's next restart (Apply): file names under ReaPersona/pending
  local out = {}
  reaper.EnumerateFiles(M.here .. "/pending", -1)
  for i = 0, 100 do local f = reaper.EnumerateFiles(M.here .. "/pending", i); if not f then break end out[#out + 1] = f end
  return out
end
local function pend_pref(k, v)
  reaper.RecursiveCreateDirectory(M.here .. "/pending", 0)
  local p = M.here .. "/pending/prefs.json"
  local d = M.load_json(p) or {}
  d[k] = v
  return M.save_json(p, setmetatable(d, M.OBJECT))
end
M.ADVANCED_APPLY = {
  -- (Preferences are never written into REAPER's memory: SWS's double getter also answers for int variables, so a type guessed from it
  -- wrote 8 bytes into 4-byte ones and the laptop's REAPER crashed seconds later (5.11.1, found the next night). They wait for the restart
  -- and go into reaper.ini, which REAPER reads itself.)
  pref = function(k, v)
    if not v then return true end
    return pend_pref(k, v) and true or false
  end,
  xstate = function(rest, v)
    local sec, key = rest:match("^([^|]+)|(.+)$")
    if not sec then return false end
    reaper.SetExtState(sec, key, v or "", true)
  end,
  ini = function(name, v)
    if not ({ ["reaper-kb.ini"] = 1, ["reaper-mouse.ini"] = 1, ["reaper-menu.ini"] = 1 })[name] or not v then return true end -- (others: not taken)
    local text = from_blob(v) -- (checked against its hash)
    if not text then return false end
    reaper.RecursiveCreateDirectory(M.here .. "/pending", 0)
    return M.write(M.here .. "/pending/" .. name, text) -- (merged in when REAPER restarts: install_shortcuts.py --apply-setup)
  end,
  tpl = function(rel, v) if not v then return true end return put_file(rel, v) end,
  code = function(rel, v) if not v then return true end return put_file(rel, v) end,
  theme = function(rel, v) if not v then return true end return put_file(rel, v) end,
  repo = function(name, v)
    if M.PKG_HERE[name] then return true end
    local url, en, auto = (v or ""):match("^(.-)|(%d)|(%d)$")
    if not url or not reaper.ReaPack_AddSetRepository then return false end
    local ok = reaper.ReaPack_AddSetRepository(name, url, en == "1", 0, "") -- (0: never "install everything in it": its packages come one by one, Install them)
    M.repos_changed = true
    return ok and true or false
  end,
  pkg = function(rest, v, rep) -- (offered, not installed by itself: Settings > Install what's missing)
    if not v or M.PKG_HERE[rest:match("^[^|]+")] then return true end
    local p = M.here .. "/packages_missing.json"
    local d = M.load_json(p) or {}
    d[rest] = v
    rep.packages = (rep.packages or 0) + 1
    return M.save_json(p, setmetatable(d, M.OBJECT)) and true or false
  end,
}
local missing_cache
function M.packages_missing(fresh) -- the packages your other computers have and this one doesn't (still): { { key = "remote|category|package", v } }
  if missing_cache and not fresh then return missing_cache end
  local d = M.load_json(M.here .. "/packages_missing.json") or {}
  local have = {}
  local cur = next(d) and read_packages() or {}
  for _, e in ipairs((cur or {}).installed or {}) do have[e[1] .. "|" .. e[2] .. "|" .. e[3]] = true end
  local out = {}
  for k, v in pairs(d) do if not have[k] then out[#out + 1] = { key = k, v = v } end end
  table.sort(out, function(a, b) return a.key < b.key end)
  missing_cache = out
  return out
end
function M.install_missing() -- ReaPack installs them: a placeholder of each in its registry, then its sync. -> how many, or nil + why
  local list = M.packages_missing(true)
  if #list == 0 then return 0 end
  local f = M.here .. "/packages_missing.json"
  local code, text = sh(M.py .. ' "' .. M.here .. '/setup_helper.py" install "' .. res .. '" "' .. f .. '"', 30000)
  if code ~= "0" then return nil, tostring(text):sub(1, 300) end
  if M.repos_changed and reaper.ReaPack_ProcessQueue then reaper.ReaPack_ProcessQueue(true) end
  local sync = reaper.NamedCommandLookup("_REAPACK_SYNC")
  if sync == 0 then return nil, "ReaPack isn't here" end
  reaper.Main_OnCommand(sync, 0) -- (ReaPack fetches each package's newest version for this system, and says what it did)
  os.remove(f)
  missing_cache = nil
  return #list
end

-- A setup file: everything of yours, to take to another computer by hand.
function M.computer()
  local n = os.getenv("COMPUTERNAME")
  if not n and not tostring(reaper.GetOS()):find("^Win") then
    local p = io.popen(M.IS_MAC and "/usr/sbin/scutil --get ComputerName 2>/dev/null" or "hostname 2>/dev/null")
    if p then n = (p:read("l") or ""):gsub("%..*$", ""); p:close() end
  end
  return (n and n ~= "") and n or "this computer"
end
function M.export_setup(path) -- -> true, or nil + why
  local items = M.setup_items()
  local out = setmetatable({}, M.OBJECT)
  for item, v in pairs(items) do out[item] = { v = v } end
  if not M.write(path, M.json_encode({ reapersona_setup = 1, computer = M.computer(), saved = os.time(), items = out }) .. "\n") then
    return nil, "couldn't write " .. path
  end
  return true
end
local KIND_NAMES = { persona = "personas", preset = "presets", recipe = "theme recipes", setting = "ReaPersona settings", ext = "smooth scroll/playhead settings",
  pref = "REAPER preferences", xstate = "other scripts' settings", ini = "shortcuts, mouse and menus", tpl = "FX chains and templates", code = "scripts and JSFX",
  theme = "themes", repo = "ReaPack repositories", pkg = "ReaPack packages" }
function M.setup_kinds(d) -- what a setup file holds, as words: "3 personas, 12 ReaPersona settings" (pure)
  local n, order = {}, {}
  for item in pairs(type(d) == "table" and type(d.items) == "table" and d.items or {}) do
    local k = type(item) == "string" and item:match("^(%a+) ")
    if k and KIND_NAMES[k] then if not n[k] then n[k] = 0; order[#order + 1] = k end n[k] = n[k] + 1 end
  end
  table.sort(order)
  local out = {}
  for _, k in ipairs(order) do out[#out + 1] = n[k] .. " " .. KIND_NAMES[k] end
  return table.concat(out, ", ")
end
function M.confirm_setup(d, name) -- a dropped setup file changes your setup: asked first, saying what's in it (Review 5.11, H2)
  return reaper.MB((name or "This file") .. " is a ReaPersona setup" .. (d.computer and (" from " .. tostring(d.computer):gsub("%c", "")) or "") ..
    ".\n\nIt holds: " .. M.setup_kinds(d) .. ".\n\nTake it in here? Where both have one, the file's wins. Only parts you sync here (Settings) are taken.",
    "ReaPersona: setup file", 4) == 6
end
function M.import_setup(d) -- a setup file (decoded, or its path): every item in it taken, the file's version winning -> report, or nil + why
  if type(d) == "string" then local ok, t = pcall(M.json_decode, M.read(d) or ""); d = ok and t or nil end
  if type(d) ~= "table" or not (d.reapersona_setup or d.reapersona_sync) or type(d.items) ~= "table" then return nil, "not a ReaPersona setup file" end
  local list = {}
  local skip = {}
  for _, a in ipairs(M.ADVANCED) do if not M.advanced_on(a.id) then for _, k in ipairs(a.kinds) do skip[k] = true end end end
  for kind, f in pairs({ persona = USERS, preset = PRESETS, recipe = M.here .. "/user_themes.json" }) do if not M.load_json(f) then skip[kind] = true end end
  if M.sync_folder() == "" then for _, k in ipairs({ "ini", "tpl", "code", "theme" }) do skip[k] = true end end -- (their content is in a sync folder)
  for item, r in pairs(d.items) do
    local k = type(item) == "string" and item:match("^(%a+) ")
    if k and SYNC_KINDS[k] and not skip[k] and type(r) == "table" and not r.del then
      local good = TEXT_KINDS[k] and type(r.v) == "string" or (not TEXT_KINDS[k] and type(r.v) == "table")
      if good then list[#list + 1] = { item = item, v = r.v } end
    end
  end
  table.sort(list, function(a, b) return a.item < b.item end)
  local rep = apply_items(list)
  for k in pairs(skip) do if GONE_KINDS[k] then rep.skipped = (rep.skipped and (rep.skipped .. ", ") or "") .. k end end
  return rep
end

-- A shared folder: <computer>-<id>.reapersona-sync.json per computer, written only when something changed (so Syncthing and the like
-- send nothing the rest of the time), read from every other computer. Looked at when REAPER starts, while the window is open and when
-- it closes. Another computer's file that doesn't parse (half-synced, or edited by hand) is skipped and left as it is.
local SYNC_STATE = M.here .. "/sync_state.json"
-- (Kept in memory between looks while the window is open: the state and the other computers' files, decoded again only when they change on
-- disk, and nothing written when nothing changed. With every advanced part on, the state is megabytes: reading and writing it every 20 s
-- held REAPER up for a second.)
local mem = { others = {} }
local function file_sig(path)
  if not reaper.JS_File_Stat then return nil end
  local ok, size, _, mtime = reaper.JS_File_Stat(path)
  return ok == 0 and (size .. "|" .. tostring(mtime)) or nil
end
function M.sync_folder() return reaper.GetExtState(M.SECTION, "sync folder") end
local function sync_file_name()
  local kept = reaper.GetExtState(M.SECTION, "sync file")
  if kept:match("^[^/\\]+%.reapersona%-sync%.json$") then return kept end
  local id = reaper.GetExtState(M.SECTION, "sync id")
  if id == "" then
    math.randomseed(os.time() + math.floor(reaper.time_precise() * 1000))
    id = string.format("%04x", math.random(0, 0xFFFF))
    reaper.SetExtState(M.SECTION, "sync id", id, true)
  end
  local name = M.file_name(M.computer() .. "-" .. id) .. ".reapersona-sync.json"
  reaper.SetExtState(M.SECTION, "sync file", name, true)
  return name
end
M.sync_file_name = sync_file_name
function M.sync_others(dir) -- -> the other computers' files: { name, d (decoded) or bad = true }
  local out, own = {}, sync_file_name()
  reaper.EnumerateFiles(dir, -1)
  for i = 0, 1000 do
    local f = reaper.EnumerateFiles(dir, i)
    if not f then break end
    if f:match("%.reapersona%-sync%.json$") and f ~= own then
      local sig = file_sig(dir .. "/" .. f)
      local c = mem.others[dir .. "/" .. f]
      if sig and c and c.sig == sig then out[#out + 1] = c.entry
      else
        local ok, d = pcall(M.json_decode, M.read(dir .. "/" .. f) or "")
        local entry = (ok and type(d) == "table" and d.reapersona_sync and type(d.items) == "table") and { name = f, d = d } or { name = f, bad = true }
        out[#out + 1] = entry
        mem.others[dir .. "/" .. f] = sig and { sig = sig, entry = entry } or nil
      end
    end
  end
  return out
end
-- start: "theirs" the first time, when you chose to take the folder's setup (the other computers' versions win), "mine" to send this
-- computer's. -> a report ({ ..., others = their files, changed = true when this computer took something }), or nil + why
function M.sync_now(start)
  local dir = M.sync_folder():gsub("[/\\]+$", "")
  if dir == "" then return nil, "no sync folder chosen" end
  local ssig = file_sig(SYNC_STATE)
  local state = (ssig and mem.state_sig == ssig and mem.state) or M.load_json(SYNC_STATE)
  if not state then return nil, "sync_state.json doesn't parse (a copy is next to it): fix or delete it, then sync again" end
  state.items = type(state.items) == "table" and state.items or {}
  sig_cache = type(state.sigs) == "table" and state.sigs or {}
  state.sigs = sig_cache
  local nsigs = 0; for _ in pairs(sig_cache) do nsigs = nsigs + 1 end
  local now, first = os.time(), next(state.items) == nil
  local others = M.sync_others(dir)
  local theirs = {}
  for _, o in ipairs(others) do if o.d then theirs[#theirs + 1] = o.d end end
  local mine, skip = M.setup_items()
  local seed = (first and start == "theirs") and 0 or now
  if type(state.seed0) == "table" and next(state.seed0) then -- (advanced parts just switched on with "take theirs")
    seed = { }
    for k in pairs(state.seed0) do if not skip[k] then seed[k] = 0 end end
  end
  local todo, changes = M.sync_merge(state.items, mine, skip, theirs, now, seed)
  if type(state.seed0) == "table" then for k in pairs(state.seed0) do if not skip[k] then state.seed0[k] = nil; changes = changes + 1 end end end
  local rep = apply_items(todo)
  for _, a in ipairs(rep.failed) do state.items[a.item] = a.was end
  rep.others, rep.changed = others, #todo > #rep.failed
  local nsigs2 = 0; for _ in pairs(sig_cache) do nsigs2 = nsigs2 + 1 end
  local path = dir .. "/" .. sync_file_name()
  local bad = {}
  for _, o in ipairs(others) do if o.bad then bad[#bad + 1] = o.name end end
  for _, f in ipairs(M.sync_bad or {}) do bad[#bad + 1] = "your " .. f .. " (it doesn't parse: a copy is next to it; fix it to sync it again)" end
  if changes == 0 and #todo == 0 and nsigs2 == nsigs and ssig and mem.own_sig and file_sig(path) == mem.own_sig then -- (nothing changed: nothing written)
    mem.state, mem.state_sig = state, ssig
    reaper.SetExtState(M.SECTION, "sync last", os.time() .. "|" .. M.setup_summary(rep) .. (#bad > 0 and ("|skipped " .. table.concat(bad, ", ")) or ""), true)
    if not M.quick then pcall(M.tidy_blobs, dir, state.items, others) end
    return rep
  end
  local items = setmetatable({}, M.OBJECT)
  for item, st in pairs(state.items) do items[item] = st.del and { t = st.t, del = true } or { t = st.t, v = st.v } end
  local text = M.json_encode({ reapersona_sync = 1, computer = M.computer(), items = items }) .. "\n"
  local keep = setmetatable({}, M.OBJECT) -- (kept before the folder is written: what came in is never sent back as a change of this computer's)
  for item, st in pairs(state.items) do keep[item] = st end
  M.save_json(SYNC_STATE, { items = keep, sigs = setmetatable(sig_cache or {}, M.OBJECT), seed0 = state.seed0 })
  mem.state, mem.state_sig = state, file_sig(SYNC_STATE)
  if M.read(path) ~= text and not M.write(path, text) then return nil, "couldn't write in " .. dir .. " (is the folder there, and its drive connected?)" end
  mem.own_sig = file_sig(path)
  reaper.SetExtState(M.SECTION, "sync last", os.time() .. "|" .. M.setup_summary(rep) .. (#bad > 0 and ("|skipped " .. table.concat(bad, ", ")) or ""), true)
  if not M.quick then pcall(M.tidy_blobs, dir, state.items, others) end
  return rep
end
function M.tidy_blobs(dir, mine, others)
  if not reaper.JS_File_Stat then return end
  local used = {}
  local function mark(items) for _, it in pairs(type(items) == "table" and items or {}) do if type(it) == "table" and type(it.v) == "table" and it.v.h then used[it.v.h] = true end end end
  mark(mine)
  for _, o in ipairs(others) do if o.d then mark(o.d.items) else return end end -- (one that doesn't parse might name any of them: keep all)
  local b = dir .. "/blobs"
  reaper.EnumerateFiles(b, -1)
  local gone, list = 0, {}
  for i = 0, 100000 do local f = reaper.EnumerateFiles(b, i); if not f then break end list[#list + 1] = f end
  for _, f in ipairs(list) do
    if not used[f] then
      local ok, _, _, mtime = reaper.JS_File_Stat(b .. "/" .. f)
      local y, mo, d, h, mi, se = tostring(mtime or ""):match("(%d+)%.(%d+)%.(%d+) (%d+):(%d+):(%d+)")
      local t = y and os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
      if ok == 0 and t and os.time() - t > 86400 and os.remove(b .. "/" .. f) then gone = gone + 1 end
    end
  end
  return gone
end
function M.start_sync(dir, start) -- the folder chosen: -> the first sync's report, or nil + why
  reaper.SetExtState(M.SECTION, "sync folder", dir, true)
  os.remove(SYNC_STATE) -- (a new folder: every item seen afresh, as `start` says)
  mem = { others = {} }
  local rep, why = M.sync_now(start)
  if not rep then M.stop_sync() end
  return rep, why
end
function M.stop_sync()
  reaper.DeleteExtState(M.SECTION, "sync folder", true)
  os.remove(SYNC_STATE)
  mem = { others = {} }
end
function M.advanced_join(id, theirs) -- an advanced part switched on: with theirs, what your other computers have wins the first time
  M.set_advanced(id, true)
  if not theirs then return end
  local state = M.load_json(SYNC_STATE)
  if not state then return end
  state.seed0 = type(state.seed0) == "table" and state.seed0 or setmetatable({}, M.OBJECT)
  for _, a in ipairs(M.ADVANCED) do
    if a.id == id then
      for _, k in ipairs(a.kinds) do
        state.seed0[k] = true
        for item in pairs(state.items or {}) do if item:sub(1, #k + 1) == k .. " " then state.items[item] = nil end end -- (seen afresh: theirs win)
      end
    end
  end
  M.save_json(SYNC_STATE, state)
end
function M.sync_tick(quick) -- (REAPER's start, and the window's loop: quiet, a problem goes to errors.log. quick: not the advanced parts)
  if M.sync_folder() == "" then return end
  M.quick = quick
  local ok, rep, why = pcall(M.sync_now)
  M.quick = nil
  if not ok then M.log("sync: " .. tostring(rep)) elseif not rep then M.log("sync: " .. tostring(why)) end
  return ok and rep or nil
end

-- ---------------------------------------------------------------- merge themes (merge_themes.py does the zip work)
function M.merge(base, colours, graphics, parts, fonts) -- -> new theme's file name, or nil + what python said
  if not M.python() then return nil, "it needs Python 3 (python.org)" end
  local function q(s) return '"' .. s .. '"' end
  local cmd = { M.py, q(M.here .. "/merge_themes.py"), q(base), q(colours) }
  if graphics and #parts > 0 then cmd[#cmd + 1] = "--graphics " .. q(graphics) .. " --parts " .. table.concat(parts, ",") end
  if fonts then cmd[#cmd + 1] = "--fonts" end
  cmd[#cmd + 1] = "--themes " .. q(M.themes_dir:gsub("/$", ""))
  local code, text = sh(table.concat(cmd, " "), 60000)
  local name = text and text:match("([^\r\n]+%.ReaperThemeZip)")
  if code == "0" and name then return name end
  return nil, text
end

-- ---------------------------------------------------------------- updates (5.23; James: "an update button in settings like studiosync to
-- keep up to date and test new features"). Settings > Updates reads ReaPersona's ReaPack index on GitHub: the released version from main,
-- on main. Updating: a
-- ReaPack install on released versions runs ReaPack's sync, as StudioSync's Update does; anything else (test versions, or a copy not
-- installed by ReaPack) downloads the version's files into a folder of their own and puts them in place only once every one has come.
M.REPO_RAW = "https://raw.githubusercontent.com/FmsJay/ReaPersona/"
M.UPDATE_BRANCH = "main" -- (test versions came and went in 5.23: "not needed for now")
function M.version() return (M.read(M.here .. "/ReaPersona.lua") or ""):match("@version%s+(%S+)") or "0" end
function M.version_less(a, b) -- (pure) "5.21.1" < "5.22.0"; a test version ("5.23.0-test1") comes before its release
  local function parts(v)
    local n, pre = tostring(v):match("^([%d%.]*)(.*)$")
    local t = {}; for d in n:gmatch("%d+") do t[#t + 1] = tonumber(d) end
    return t, pre
  end
  local x, xp = parts(a)
  local y, yp = parts(b)
  for i = 1, math.max(#x, #y) do if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) < (y[i] or 0) end end
  if xp == yp or xp == "" then return false end
  return yp == "" or xp < yp
end
local function unxml(s) return (s:gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&amp;", "&")) end
function M.parse_index(xml) -- (pure) -> { version, files = { {path, url} } } for ReaPersona's own package, or nil
  local pkg = type(xml) == "string" and xml:match('<reapack name="ReaPersona%.lua".-</reapack>')
  local v = pkg and pkg:match('<version name="([^"]+)"')
  if not v then return nil end
  local files = {}
  for attrs, url in pkg:gmatch("<source([^>]*)>([^<]+)</source>") do
    local f = attrs:match('file="([^"]+)"')
    f = f and unxml(f) or (attrs:find('main=', 1, true) and "ReaPersona.lua")
    url = unxml(url)
    -- (only ReaPersona's own files, from its own repository, inside its folder; a platform build is a loaded extension: ReaPack's job)
    if f and not attrs:find("platform=", 1, true) and url:match("^https://github%.com/FmsJay/ReaPersona/raw/%x+/ReaPersona/[%w%%%-%._/~]+$")
       and not f:find("..", 1, true) and not f:match("^[/\\]") and not f:find(":", 1, true) and not f:find("\\", 1, true) then
      files[#files + 1] = { f, url }
    end
  end
  return #files > 0 and { version = v, files = files } or nil
end
function M.reapack_owned() -- installed by ReaPack?
  local e = reaper.ReaPack_GetOwner and reaper.ReaPack_GetOwner(M.here .. "/ReaPersona.lua")
  if e then reaper.ReaPack_FreeEntry(e); return true end
  return false
end
function M.check_update(max_s) -- -> { version, files, newer }, or nil + why. Reads the released index.xml (a few KB)
  local dir = M.here .. "/_downloads"
  reaper.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "/index-latest.xml"
  os.remove(path)
  -- shortcut: waits for GitHub (up to max_s seconds, REAPER held); a background download if that ever gets in the way
  local code = sh(CURL .. ' -s -L --fail --max-time ' .. (max_s or 15) .. ' -o "' .. path .. '" "' .. M.REPO_RAW .. M.UPDATE_BRANCH .. '/index.xml"', ((max_s or 15) + 5) * 1000)
  local info = code == "0" and M.parse_index(M.read(path))
  os.remove(path)
  if not info then return nil, "couldn't reach ReaPersona on GitHub (offline?)" end
  local now = M.version()
  -- (a newer release, or the release when this copy says a version with letters in it)
  info.newer = info.version ~= now and (M.version_less(now, info.version) or now:find("%a") ~= nil)
  reaper.SetExtState(M.SECTION, "update seen", os.time() .. "|" .. info.version, true)
  return info
end
function M.update_start(info) -- -> "reapack" (ReaPack's sync started), or a job for M.update_poll; or nil + why
  if M.reapack_owned() then
    local cmd = reaper.NamedCommandLookup("_REAPACK_SYNC")
    if cmd ~= 0 then reaper.Main_OnCommand(cmd, 0); return "reapack" end
  end
  local stage = M.here .. "/_downloads/update"
  M.remove_tree(stage)
  reaper.RecursiveCreateDirectory(stage, 0)
  local cfg = { "silent", "location", "fail", "create-dirs", "max-time = 120" }
  for _, f in ipairs(info.files) do cfg[#cfg + 1] = 'url = "' .. f[2] .. '"'; cfg[#cfg + 1] = 'output = "' .. stage .. "/" .. f[1] .. '"' end
  -- (last, the index again: curl fetches in order, so once it's there every file has come or failed)
  cfg[#cfg + 1] = 'url = "' .. M.REPO_RAW .. M.UPDATE_BRANCH .. '/index.xml"'; cfg[#cfg + 1] = 'output = "' .. stage .. '.done"'
  if not M.write(stage .. ".cfg", table.concat(cfg, "\n") .. "\n") then return nil, "couldn't write in " .. M.here end
  os.remove(stage .. ".done")
  -- (in the background, so REAPER isn't held for the 15 s or so it takes; one curl, one connection; no --parallel: older Windows 10 curl lacks it)
  reaper.ExecProcess(CURL .. ' -K "' .. stage .. '.cfg"', reaper.GetOS():find("^Win") and -2 or -1)
  return { info = info, stage = stage, until_t = reaper.time_precise() + 240 }
end
function M.update_poll(job) -- -> nil while it's downloading; then how many files were written, or false + why
  local stage, info = job.stage, job.info
  if not (M.read(stage .. ".done") or ""):find("</index>", 1, true) then
    if reaper.time_precise() < job.until_t then return nil end
    M.remove_tree(stage); os.remove(stage .. ".cfg"); return false, "the download didn't finish (offline?): nothing was changed"
  end
  os.remove(stage .. ".done"); os.remove(stage .. ".cfg")
  local got = {}
  for _, f in ipairs(info.files) do
    got[f[1]] = M.read(stage .. "/" .. f[1])
    if not got[f[1]] or #got[f[1]] == 0 then M.remove_tree(stage); return false, "not every file came (" .. f[1] .. "): nothing was changed" end
  end
  if (got["ReaPersona.lua"] or ""):match("@version%s+(%S+)") ~= info.version then M.remove_tree(stage); return false, "the download isn't version " .. info.version .. ": nothing was changed" end
  for _, f in ipairs(info.files) do
    local dest = M.here .. "/" .. f[1]
    reaper.RecursiveCreateDirectory(dest:match("^(.*)/[^/]*$") or M.here, 0)
    if not M.write(dest, got[f[1]]) then M.remove_tree(stage); return false, "couldn't write " .. f[1] .. " (some files are new already: update again)" end
  end
  M.remove_tree(stage)
  return #info.files
end
function M.open_url(u)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(u)
  elseif reaper.GetOS():find("^Win") then os.execute('start "" "' .. u:gsub('"', "%%22") .. '"')
  else os.execute("open '" .. u:gsub("'", "'\\''") .. "'") end
end

return M
