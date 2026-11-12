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
  { "mixer_dock", "Dock or undock the mixer (Pro Tools, FL and Cubase keep theirs in its own window)", true, "Mixer docking" },
  { "mixer_layout", "Mixer layout: master on the left or right, insert and send slots", true, "Mixer layout" },
  { "transport", "Where the transport sits", true, "Transport position" },
  { "browser", "Where the Media Explorer docks", true, "Media Explorer" },
  { "toolbar", "The DAW's toolbar in place of your main toolbar", true, "Toolbar" },
  { "mouse", "Mouse behaviours (Smart Tool and so on)", true, "Mouse feel" },
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
local function apply_feel(st, windows_left)
  local list = {}
  windows_left = windows_left or {}
  local function save() reaper.SetExtState(M.SECTION, "orig", table.concat(list, ";;"), true) end -- (after every entry: a switch cut short can still be put back)
  for _, f in ipairs(st.feel or {}) do
    local ok, err = pcall(function()
    if not M.aspect_on(M.aspect_of(f)) then return end
    if f[1] == "dock" and WINDOWS[f[2]] and reaper.JS_Window_OnCommand then
      local d, made = f[3] ~= "float" and docker_at(f[3]) or nil, nil
      if f[3] ~= "float" and not d then d = spare_docker(f[3]); made = d and f[3] end -- (no docker on that side yet: one is set up)
      if f[3] ~= "float" and not d then return end -- (no spare docker either: the window stays where it is)
      list[#list + 1] = windows_left[f[2]] or window_now(f[2]) -- (the original from before any style, if the last style moved it)
      windows_left[f[2]] = nil
      move_window(f[2], { shown = f[4] == 1, docker = d, side = made })
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
  for _, line in pairs(windows_left) do window_back(line) end -- (windows the last style moved and this one doesn't: put back)
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
  local d = M.load_json(PRESETS)
  local list = d and d.presets or {}
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
  local list = load_presets()
  local p = { id = M.new_id("preset_"), name = name, base = base.id, saved = os.date("%Y-%m-%d"), feel = feel,
              theme = M.loaded_theme() or M.theme_for(base) }
  list[#list + 1] = p
  local ok, why = M.save_json(PRESETS, { presets = list })
  if not ok then return nil, why end
  load_presets()
  reaper.SetExtState(M.SECTION, "style", p.id, true) -- (it is what's in use now: switching away puts back what the style changed)
  return M.by_id(p.id)
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
  apply_feel(st, left)
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
  if M.follow_on() then M.start_following() end -- (a persona per project: the action that follows project tabs)
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
local STUBS = 3 -- (bump when the stubs below change, so they're written again)
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
    if not M.scripts.main["use " .. st.id] then n = n + 1 end
    for _, k in ipairs(st.midi_keys or {}) do if not M.scripts.midi[k[1]] then n = n + 1 end end
  end
  return n
end
function M.ensure_scripts()
  reaper.RecursiveCreateDirectory(M.here .. "/actions", 0)
  reaper.RecursiveCreateDirectory(M.here .. "/midi_keys", 0)
  local main = { ["next style"] = { "next_style" }, ["restore last style"] = { "restore_last" }, ["memory location"] = { "memory_location" },
                 ["play from start"] = { "play_from_start" }, ["follow projects"] = { "follow_projects" } }
  local names = {}
  for _, st in ipairs(M.styles) do main["use " .. st.id] = { "use_id", st.id }; local l = (st.short or st.name):lower(); names[l] = (names[l] or 0) + 1 end
  local todo = {}
  for name, call in pairs(main) do
    local st = name:match("^use ") and M.by_id(name:sub(5))
    local label = st and ("use " .. (st.short or st.name) .. ((st.user and names[(st.short or st.name):lower()] > 1) and (" (" .. st.id .. ")") or "")) or name -- (yours named like another: its own file)
    local p = M.here .. "/actions/ReaPersona - " .. M.file_name(label) .. ".lua"
    stub(p, call[1], call[2]); todo[#todo + 1] = { 0, p, "main", name }
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
function M.import_theme(path) -- copy a downloaded theme into ColorThemes -> its file name, or nil + why
  local name = path:gsub("\\", "/"):match("[^/]+$") or ""
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
-- A block is { kind = "daw", id, keys, feel, theme } (a DAW's shortcuts, its layout and feel and its theme, each part on or off),
-- { kind = "feel", id, aspect } (one part of a DAW's feel), { kind = "settings", group, values } (REAPER options: values[i] is 0/1
-- for a switch or the option's number for a choice, -1 leaves it alone), { kind = "theme", file } or { kind = "colour", hex }.
-- Where two blocks set the same thing, the lower one wins. The persona keeps its blocks, so the Builder can open it again.
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
    { "_SWS_TOGSEEKMODE1", "Playback follows item moves", tip = "Moving or resizing an item during playback seeks to it (SWS)." } } },
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
    { "_SWS_AWCLRTIMESELCLKTOG", "Time selection and edit cursor linked", tip = "Clicking clears the time selection and moves the cursor together (SWS)." } } },
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
    { "_SWS_AWAUTOGROUPTOG", "Group what's recorded together", tip = "Items recorded in one pass are grouped (SWS)." } } },
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
    { "_SWS_TOGAUTOADDENVS", "Envelopes appear when you move a control in Write mode", tip = "SWS." } } },
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
  if kind == "daw" then return { kind = "daw", id = a, keys = true, feel = true, theme = true }
  elseif kind == "feel" then return { kind = "feel", id = a, aspect = b }
  elseif kind == "settings" then
    local values = {}
    for i, item in ipairs((group_by_id(a) or {}).items or {}) do values[i] = M.setting_now(item) end
    return { kind = "settings", group = a, values = values }
  elseif kind == "theme" then return { kind = "theme", file = a }
  elseif kind == "colour" then return { kind = "colour", hex = a } end
end
function M.block_title(b)
  local st = b.id and M.by_id(b.id)
  local name = st and st.name or tostring(b.id)
  if b.kind == "daw" then return name
  elseif b.kind == "feel" then return name .. ": " .. M.aspect_name(b.aspect)
  elseif b.kind == "settings" then return (group_by_id(b.group) or { name = tostring(b.group) }).name
  elseif b.kind == "theme" then return "Theme: " .. tostring(b.file):gsub("%.ReaperTheme%a*$", "")
  elseif b.kind == "colour" then return "Colour " .. tostring(b.hex) end
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
local function block_entries(b) -- what one block sets: { slot, kind = "key"|"midi"|"feel"|"theme"|"accent", label, key, entry, value }
  local out, st = {}, b.id and M.by_id(b.id)
  local function feel(f) local s = feel_slot(f); if s then out[#out + 1] = { slot = s, kind = "feel", label = f[#f], entry = f } end end
  if b.kind == "daw" and st then
    if b.keys then
      for _, k in ipairs(M.keys_here(st.keys)) do out[#out + 1] = { slot = "key " .. M.canon(k[1]), kind = "key", label = k[3], key = k[1], entry = k } end
      for _, k in ipairs(st.midi_keys or {}) do out[#out + 1] = { slot = "midi " .. M.canon(k[1]), kind = "midi", label = k[3], key = k[1], entry = k } end
    end
    if b.feel then for _, f in ipairs(st.feel or {}) do feel(f) end end
    local th = b.theme and M.theme_for(st)
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
  elseif b.kind == "colour" and b.hex then out[1] = { slot = "accent", kind = "accent", label = "Colour " .. b.hex, value = b.hex } end
  return out
end
function M.build_preview(blocks) -- -> per block its entries, each with .lost_to = the lower block that replaces it
  local per, winner = {}, {}
  for i, b in ipairs(blocks) do -- (b.off[slot]: a line of the block you unticked, left out of the persona)
    per[i] = block_entries(b)
    for _, e in ipairs(per[i]) do if type(b.off) == "table" and b.off[e.slot] then e.off = true else winner[e.slot] = i end end
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
        elseif e.kind == "accent" then st.accent = e.value end
      end
    end
    if src and b.kind == "daw" then
      accent = accent or src.accent
      for _, x in ipairs(src.extras or {}) do st.extras[#st.extras + 1] = x end
      for _, d in ipairs(src.docs or {}) do st.docs[#st.docs + 1] = d end
      for _, r in ipairs(src.recommends or {}) do if not seen[r] then seen[r] = true; st.recommends[#st.recommends + 1] = r end end
    end
  end
  st.accent = st.accent or accent
  st.themes = { st.theme }
  local install = false
  if #daws == 1 then st.keys_from = daws[1]; M.resolve_keys(st) -- (one DAW's keys: its own shortcut layer, nothing to install)
  elseif #daws > 1 then -- (keys from several DAWs: a layer of their own, which needs installing)
    local old = M.by_id(st.id)
    st.alt = old and old.kind == "built" and not old.keys_from and (old.alt or 0) > 0 and old.alt or free_alt()
    if not st.alt then return nil, "all 16 shortcut layers are in use" end
    install = true
  else st.alt = 0 end -- (no shortcuts block: your own keys)
  st.description = name .. ", built from " .. table.concat(names, ", ") .. " (lower blocks win)." ..
    (#daws > 1 and (" Its shortcuts are on layer alt-" .. st.alt .. ".") or "")
  return st, install
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
function M.start_following()
  local id = cmd_id(M.scripts.main["follow projects"] or "")
  if id ~= 0 then reaper.Main_OnCommand(id, 0) end
end
function M.follow_projects()
  if reaper.time_precise() - (tonumber(reaper.GetExtState(M.SECTION, "follow beat")) or -9) < 1.5 then return end -- (one runs already)
  local C, last = M, nil
  reaper.atexit(function() reaper.DeleteExtState(M.SECTION, "follow beat", false) end)
  local function step()
    if not M.follow_on() then return end
    reaper.SetExtState(M.SECTION, "follow beat", tostring(reaper.time_precise()), false)
    local p, fn = reaper.EnumProjects(-1)
    local key = tostring(p) .. "|" .. tostring(fn)
    if key ~= last and not C.busy() then
      last = key
      local want = M.project_persona(p) or reaper.GetExtState(M.SECTION, "project default")
      if want ~= "" and want ~= reaper.GetExtState(M.SECTION, "style") then
        if not C.by_id(want) then C = dofile(M.here .. "/reapersona_core.lua") end -- (a persona made since this started)
        if C.by_id(want) then C.use_id(want) end
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
local WHEEL = { Mousewheel = { 255, 248 }, ["Ctrl+Alt+Mousewheel"] = { 255, 251 } }
function M.encode(spec) -- "Ctrl+Shift+L" -> flags, key as reaper-kb.ini writes them (same as install_shortcuts.encode), or nil
  if WHEEL[spec] then return WHEEL[spec][1], WHEEL[spec][2] end
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
function M.toolbar_installed(section) -- is [Floating toolbar N] / [Floating MIDI toolbar N] one of ours in reaper-menu.ini?
  local t = M.read(res .. "/reaper-menu.ini") or ""
  local body = M.ini_section(t, section)
  return body ~= nil and (body:find("title=ReaPersona", 1, true) ~= nil or body:find("title=DAW Styles", 1, true) ~= nil)
end

-- ---------------------------------------------------------------- setup: Python, ReaPersona's own themes, the startup line
local function sh(cmd, ms) local out = reaper.ExecProcess(cmd, ms or 20000) or ""; local code, text = out:match("^(%-?%d+)\r?\n(.*)$"); return code, text or out end
function M.remove_tree(dir) -- a folder ReaPersona made itself, and everything in it
  if reaper.GetOS():find("^Win") then sh('cmd /c rmdir /s /q "' .. dir:gsub("/", "\\") .. '"', 20000)
  else sh("rm -rf '" .. dir:gsub("'", "'\\''") .. "'", 20000) end
end
function M.python() -- -> "Python 3.x" when a Python 3 runs here, else nil (cached; M.py is the command that worked)
  if M._py == nil then
    M._py = false
    for _, c in ipairs(reaper.GetOS():find("^Win") and { "python", "py -3", "python3" } or { "python3", "python" }) do
      local code, text = sh(c .. " --version", 8000)
      local v = code == "0" and text:match("Python 3%S*")
      if v then M._py, M.py = v, c; break end
    end
  end
  return M._py or nil
end
function M.python_libs() -- -> true when this Python has Pillow and numpy (theme building needs them); cached
  if M._libs == nil then M._libs = M.python() ~= nil and sh(M.py .. ' -c "import PIL, numpy"', 15000) == "0" end
  return M._libs
end
function M.install_python_libs() -- pip install --user pillow numpy (REAPER waits while it downloads). -> true, or nil + what pip said
  if not M.python() then return nil, "no Python 3 here (python.org)" end
  local code, text = sh(M.py .. " -m pip install --user pillow numpy", 600000)
  M._libs = nil
  if code == "0" and M.python_libs() then return true end
  return nil, (text or ""):sub(-400)
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
  if not M.python_libs() then return nil, "Python needs Pillow and numpy: Setup > Install them (or: python -m pip install --user pillow numpy)" end
  local code, text = sh(M.py .. ' "' .. M.here .. '/build_themes.py" "' .. M.themes_dir:gsub("/$", "") .. '"', 180000)
  local first, rest = (text or ""):match("^(%d)\r?\n(.*)$") -- (Python writes \r\n into a pipe on Windows)
  if code ~= "0" or first ~= "0" then return nil, (rest or text or ""):sub(1, 400) end
  apply_own_params()
  local made = {}
  for l in rest:gmatch("[^\r\n]+") do made[#made + 1] = l end
  return made
end
function M.startup_path() return res .. "/Scripts/__startup.lua" end
function M.startup_on() return cached("startup", function() return (M.read(M.startup_path()) or ""):find("reapersona_core.lua", 1, true) ~= nil end) end
function M.add_startup() -- one block in Scripts/__startup.lua that brings back the last style's keys when REAPER starts
  if M.startup_on() then return true end
  -- (relative to the resource folder when it's inside it, so the line works on a drive with another letter; else the full path)
  local r = res:gsub("\\", "/")
  local where
  if M.here:lower():sub(1, #r + 1) == r:lower() .. "/" then where = 'reaper.GetResourcePath() .. ' .. string.format("%q", M.here:sub(#r + 1))
  else where = string.format("%q", M.here) end
  local block = "\n-- >>> ReaPersona: REAPER forgets the shortcut layer at restart, so bring back the last persona's keys\ndo\n" ..
    '  local ok, err = pcall(function() dofile(' .. where .. ' .. "/reapersona_core.lua").restore_last() end)\n' ..
    '  if not ok then reaper.ShowConsoleMsg("[ReaPersona] restore failed: " .. tostring(err) .. "\\n") end\nend\n-- <<< ReaPersona <<<\n'
  local f = io.open(M.startup_path(), "a")
  if not f then return nil, "couldn't write " .. M.startup_path() end
  f:write(block); f:close()
  M.forget()
  return true
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
  local code = sh('curl -s -L --max-time 25 -o "' .. out_file .. '" "' .. url .. '"', 30000)
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
  local code = sh('curl -s -L --max-time 60 -o "' .. path .. '" "' .. url .. '"', 70000)
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
  if not (f and k) or f == 255 then return nil end
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
function M.import_file(path, out, in_zip)
  out = out or {}
  local p = path:gsub("\\", "/")
  local base = p:match("[^/]+$") or p
  local low = base:lower()
  if low:match("%.reaperthemezip$") or low:match("%.reapertheme$") then
    local n, why = M.import_theme(p)
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
    elseif ok and d and d.style then
      local st, why = M.import(p)
      out[#out + 1] = { st and "style" or "skipped", st and st.name or base, st and ("shortcut layer alt-" .. st.alt) or why }
    else out[#out + 1] = { "skipped", base, "not a ReaPersona persona or preset" } end
  elseif low:match("%.zip$") then -- (a theme pack: unpacked with Windows' or macOS's own tar, then the themes and toolbars inside come in)
    if in_zip then out[#out + 1] = { "skipped", base, "a zip inside the pack: unpack it and drop that in" }; return out end
    local nm = M.file_name(base:gsub("%.[Zz][Ii][Pp]$", "")):gsub("^%s+$", "")
    local dir = M.here .. "/_incoming/" .. (nm ~= "" and nm or "pack") .. "-" .. os.time()
    reaper.RecursiveCreateDirectory(dir, 0)
    local win = reaper.GetOS():find("^Win")
    -- (Windows' own tar, by full path: another tar earlier on PATH, Git's say, reads "J:/..." as a remote host)
    local tar = win and ((os.getenv("SystemRoot") or "C:\\Windows") .. "\\System32\\tar.exe") or "/usr/bin/tar"
    local q = win and function(s) return '"' .. s .. '"' end or function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
    local code, text = sh(q(tar) .. " -xf " .. q(p) .. " -C " .. q(dir), 60000)
    local n0 = #out
    local function walk(d)
      reaper.EnumerateFiles(d, -1); reaper.EnumerateSubdirectories(d, -1) -- (REAPER caches folder listings: rescan)
      for i = 0, 2000 do local f = reaper.EnumerateFiles(d, i); if not f then break end M.import_file(d .. "/" .. f, out, true) end
      for i = 0, 200 do local s = reaper.EnumerateSubdirectories(d, i); if not s then break end walk(d .. "/" .. s) end
    end
    walk(dir)
    M.remove_tree(dir) -- (the unpacked copy was ours, made just above: gone again)
    if out.left then out[#out + 1] = { "skipped", out.left .. " other files", "readmes, images and the like: not themes or toolbars" }; out.left = nil end
    if out.fonts then out[#out + 1] = { "note", "fonts", "the pack comes with fonts: unzip it and install them (double-click each) so the theme looks right" }; out.fonts = nil end
    if out.scripts then out[#out + 1] = { "note", "scripts", "the pack has its own scripts (a theme adjuster, say): unzip it and load them in the Actions list if you want them" }; out.scripts = nil end
    if code ~= "0" and #out == n0 then out[#out + 1] = { "skipped", base, "couldn't unpack it: " .. (text or ""):sub(1, 200) }
    elseif #out == n0 then out[#out + 1] = { "skipped", base, "nothing ReaPersona can use inside" } end
  elseif in_zip then -- (a pack's readmes, images, fonts and scripts: counted, not listed one by one)
    out.left = (out.left or 0) + 1
    if low:match("%.ttf$") or low:match("%.otf$") then out.fonts = true end
    if low:match("%.lua$") or low:match("%.eel$") then out.scripts = true end
  else out[#out + 1] = { "skipped", base, "not a theme, toolbar, keymap, persona or preset" } end
  return out
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
  local rows = {}
  for _, k in ipairs(M.keys_here(st.keys)) do rows[#rows + 1] = { M.keyname(k[1]), k[3] } end
  tbl("Arrange", rows)
  rows = {}
  for _, k in ipairs(st.midi_keys or {}) do rows[#rows + 1] = { M.keyname(k[1]), k[3] } end
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
  local p = M.here .. "/cheat sheets/" .. M.file_name(st.name) .. ".html"
  if not M.write(p, table.concat(h, "\n")) then return nil, "couldn't write " .. p end
  return p
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

function M.open_url(u)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(u)
  elseif reaper.GetOS():find("^Win") then os.execute('start "" "' .. u:gsub('"', "%%22") .. '"')
  else os.execute("open '" .. u:gsub("'", "'\\''") .. "'") end
end

return M
