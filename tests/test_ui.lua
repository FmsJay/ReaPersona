-- ReaPersona's window without REAPER: every page drawn once with a stand-in ImGui (no button pressed unless a test presses it), then the
-- persona being made: its Undo/Redo history, Preview, and what ends a preview. It runs a copy of ReaPersona/ in a resource folder of its
-- own (tests/_tmp-ui-..., removed at the end), so nothing in the repo or in a REAPER is written. Silence and "ok" means it passed.
-- Run from the repo root with Lua 5.4:   lua tests/test_ui.lua
-- or, without Lua (Windows), with lupa:  python -c "import lupa.lua54 as l; l.LuaRuntime().execute(open('tests/test_ui.lua',encoding='utf-8').read())"
-- (Round 1 review 2026-11-19, code health finding 2: the stand-in from its appendix A, grown with the preview and undo checks.)

local function read(p) local f = io.open(p, "rb"); if not f then return nil end local t = f:read("a"); f:close(); return t end
local function write(p, t) local f = assert(io.open(p, "wb")); f:write(t); f:close() end
local win = package.config:sub(1, 1) == "\\"
local function mkdir(d) os.execute(win and ('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') or ("mkdir -p '" .. d .. "'")) end
local tmp = "tests/_tmp-ui-" .. os.time() .. "-" .. math.random(1000, 9999)
local dir = tmp .. "/Scripts/ReaPersona"
mkdir(dir .. "/ui"); mkdir(dir .. "/previews")
local UI_FILES = { "base", "personas", "settings", "theme_tools", "check", "home", "editing", "shortcuts", "mouse", "layout", "project", "main" }
for _, f in ipairs({ "ReaPersona.lua", "reapersona_core.lua", "reapersona_keys.lua", "reapersona_feedback.lua", "colours.lua", "styles.json", "colour_keys.txt" }) do
  write(dir .. "/" .. f, assert(read("ReaPersona/" .. f), "run this from the repo root (" .. f .. ")"))
end
for _, f in ipairs(UI_FILES) do write(dir .. "/ui/" .. f .. ".lua", assert(read("ReaPersona/ui/" .. f .. ".lua"))) end

local function run()
  -- ------------------------------------------------ a stand-in REAPER: ExtState in a table, a clock the test moves, message boxes answered
  local ext, deferred, at_exit = {}, nil, nil
  local T = 1000
  local mb_answer, mb_said = 1, {}
  local nil_names = { osara_outputMessage = true, JS_Window_Find = true, ReaPack_BrowsePackages = true }
  reaper = setmetatable({
    GetResourcePath = function() return tmp end, GetOS = function() return "Win64" end,
    GetExtState = function(s, k) return ext[s .. "/" .. k:lower()] or "" end,
    SetExtState = function(s, k, v) ext[s .. "/" .. k:lower()] = tostring(v) end,
    HasExtState = function(s, k) return ext[s .. "/" .. k:lower()] ~= nil end,
    DeleteExtState = function(s, k) ext[s .. "/" .. k:lower()] = nil end,
    file_exists = function(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end,
    NamedCommandLookup = function() return 0 end, GetToggleCommandState = function() return -1 end,
    time_precise = function() return T end,
    ImGui_GetBuiltinPath = function() return tmp end, CF_EnumerateActions = function() return 0 end,
    defer = function(f) deferred = f end, atexit = function(f) at_exit = f end,
    get_action_context = function() return false, "", 0, 0, 0, 0, 0 end,
    MB = function(msg) mb_said[#mb_said + 1] = tostring(msg); return mb_answer end,
    GetAppVersion = function() return "7.50/win64" end, EnumerateFiles = function() end, EnumerateSubdirectories = function() end,
    GetThemeColor = function() return 0x336699 end, ColorFromNative = function() return 1, 2, 3 end,
    CountProjectMarkers = function() return 0 end, CountTracks = function() return 0 end, CountSelectedTracks = function() return 0 end,
    CountMediaItems = function() return 0 end, GetProjectName = function() return "" end, EnumProjects = function() return nil, "" end,
    GetSetProjectInfo = function() return 0 end, Master_GetTempo = function() return 120 end, GetPlayState = function() return 0 end,
    GetCursorPosition = function() return 0 end, AddRemoveReaScript = function() return 0 end, Main_OnCommand = function() end,
    RecursiveCreateDirectory = function(d) mkdir(d) end,
  }, { __index = function(_, k) if nil_names[k] then return nil end return function() return nil end end })

  -- ------------------------------------------------ a stand-in ImGui: flags are 0, windows open, nothing pressed unless `press` says so
  local press, active, images_made = {}, false, 0
  local FN_PREFIX = { DrawList = 1, ListClipper = 1, TextFilter = 1, Viewport = 1, Image = 1, Function = 1, FontAtlas = 1 }
  local OPEN = { Begin = 1, BeginChild = 1, BeginTable = 1, BeginTabBar = 1, BeginTabItem = 1, BeginGroup = 1, TreeNode = 1, TreeNodeEx = 1, CollapsingHeader = 1, BeginMenuBar = 1 }
  local ImGui = setmetatable({
    Button = function(_, label) return press[label] == true end,
    SmallButton = function(_, label) return press[label] == true end,
    IsAnyItemActive = function() return active end,
    CreateImage = function() images_made = images_made + 1; return {} end,
  }, { __index = function(t, k)
    local pre = k:match("^(%w+)_")
    if pre and not FN_PREFIX[pre] then rawset(t, k, 0); return 0 end
    local f
    if OPEN[k] then f = function() return true, true end
    elseif k:match("^Input") or k:match("^Slider") or k:match("^Drag") or k == "Checkbox" or k:match("^Color[EP]") or k:match("^Combo") or k:match("^RadioButtonEx") then
      f = function(_, _, v) return false, v end
    elseif k:match("Get") or k:match("^Calc") then f = function() return 100, 100, 100, 100 end
    elseif k:match("^Create") then f = function() return {} end
    elseif k == "ValidatePtr" then f = function() return true end
    else f = function() return false end end
    rawset(t, k, f); return f
  end })
  package.preload["imgui"] = function() return function() return ImGui end end

  dofile(dir .. "/ReaPersona.lua")
  assert(deferred, "the window didn't start its loop")
  assert(at_exit, "the window didn't set what happens when it closes")
  local R; for i = 1, 30 do local n, v = debug.getupvalue(deferred, i); if not n then break end if n == "_ENV" then R = v end end
  assert(R and R.bld and R.core, "the window's shared names weren't found")
  local core, bld = R.core, R.bld
  local function frame(pg) if pg then R.page = pg; reaper.SetExtState(R.SECTION, "page", pg, false) end local ok, e = xpcall(R.frame, debug.traceback); assert(ok, "page " .. tostring(R.page) .. ": " .. tostring(e)) end

  -- 1. Every page draws (Show everything on, so the editors' pages are listed too).
  reaper.SetExtState(R.SECTION, "advanced", "1", true)
  local pages = {}
  for _, g in ipairs(R.GROUPS) do for _, p in ipairs(g[3]) do pages[#pages + 1] = p end end
  assert(#pages >= 30, "expected 30 pages, got " .. #pages)
  for _, pg in ipairs(pages) do frame(pg) end
  frame("Shortcuts") -- (its first look only says it's reading; this one reads)

  -- 2. DAW pictures: at most 2 load per frame, the rest a frame or two later.
  for _, st in ipairs(R.styles) do write(dir .. "/previews/" .. st.id .. ".png", "") end
  for k in pairs(R.images) do R.images[k] = nil end
  images_made = 0; frame("DAWs")
  assert(images_made <= 2, "pictures loaded in one frame: " .. images_made)
  for _ = 1, 20 do frame("DAWs") end
  assert(images_made > 2, "the rest of the pictures never came")

  -- 3. The persona being made: the change history.
  local used = {}
  local real_use, real_busy, real_end = core.use, core.busy, core.end_trial
  core.use = function(st) used[#used + 1] = st; core.prefs_queued = true end -- (a switch: only recorded)
  core.busy = function() return false end
  local said = function() return R.toast end
  local function theme_of() local b = core.draft_get(bld.blocks, "theme"); return b and b.file end
  local function tick(dt) T = T + (dt or 0.3); bld.tick() end
  local function change(b) core.draft_add(bld.blocks, b); tick() end
  R.bld_new()
  tick()
  assert(#bld.hist == 1 and bld.pos == 1)
  change(core.new_block("theme", "A.ReaperTheme")); assert(#bld.hist == 2)
  change(core.new_block("theme", "B.ReaperTheme")); assert(#bld.hist == 3 and bld.pos == 3)
  bld.step(-1)
  assert(theme_of() == "A.ReaperTheme", "Undo puts the earlier draft back")
  assert(said():find("Undone: Theme: B", 1, true), "Undo says what it undid: " .. said())
  tick(); assert(#bld.hist == 3 and bld.pos == 2, "a step isn't taken for a change")
  bld.step(1); assert(theme_of() == "B.ReaperTheme")
  bld.step(-1)
  change(core.new_block("theme", "C.ReaperTheme"))
  assert(#bld.hist == 3 and bld.hist[4] == nil and bld.pos == 3, "a change after an undo drops what could be redone")
  core.draft_add(bld.blocks, core.new_block("theme", "D.ReaperTheme")) -- (not looked at yet)
  bld.step(-1); assert(theme_of() == "C.ReaperTheme", "Undo straight after a change undoes that change")
  bld.step(1); assert(theme_of() == "D.ReaperTheme", "and Redo brings it back")
  active = true -- (a drag: many changes while an item is held)
  for i = 1, 5 do change(core.new_block("theme", "drag" .. i .. ".ReaperTheme")) end
  local n = #bld.hist
  active = false; tick()
  assert(#bld.hist == n + 1, "a drag is one step")
  for i = 1, 70 do change(core.new_block("theme", "T" .. i .. ".ReaperTheme")) end
  assert(#bld.hist == 60 and bld.pos == 60, "the history keeps 60")

  -- 4. Big strings (a project template) are encoded as tokens, and Undo/Redo puts them back whole.
  local big = string.rep("<TRACK\n  NAME x\n>\n", 20000)
  local pb = core.new_block("project"); pb.template = big
  change(pb)
  assert(#bld.hist[bld.pos] < 20000, "a big template isn't encoded into every step: " .. #bld.hist[bld.pos])
  change(core.new_block("theme", "after.ReaperTheme"))
  bld.step(-1); bld.step(-1)
  assert(not core.draft_get(bld.blocks, "project"), "before the template")
  bld.step(1)
  assert(core.draft_get(bld.blocks, "project").template == big, "the template comes back whole")
  bld.step(1); assert(core.draft_get(bld.blocks, "project").template == big)

  -- 5. Preview: one switch a moment after each change, without the project part, and no preferences toast each time.
  R.bld_new() -- (asks first: this draft isn't saved)
  assert(#bld.blocks > 0 and mb_said[#mb_said]:find("Stop making", 1, true), "New asks before throwing an unsaved persona away")
  mb_answer = 6; R.bld_new(); mb_answer = 1
  assert(#bld.blocks == 0, "and goes ahead on yes")
  tick()
  bld.preview = true
  local proj = core.new_block("project"); proj.srate = 48000
  used = {}
  change(proj)
  assert(#used == 0, "not straight away")
  tick(0.7); assert(#used == 1, "once, a moment after the change")
  tick(0.7); assert(#used == 1, "and only once")
  assert(used[1].id == "built_try" and used[1].project == nil, "the project part stays out of a preview")
  assert(core.prefs_queued == false, "the preferences toast doesn't come after every change")
  assert(bld.later and bld.later:find("project part", 1, true), "the bar lists the project part as not shown")
  assert(bld.back == core.current().id, "Go back returns to the persona before the preview")

  -- 6. What ends a preview: using another persona (James: the draft stays, Preview turns off), Go back, closing the window.
  local A, B = R.styles[2], R.styles[3]
  bld.back, bld.preview = A.id, true
  R.use(B)
  assert(bld.back == nil and bld.preview == false, "using another persona ends the preview")
  assert(reaper.GetExtState(R.SECTION, "draft preview") == "0", "and the remembered tick agrees")
  assert(#bld.blocks > 0, "the persona being made stays")
  assert(R.last_style == A.id, "Undo switch goes back to the persona from before the preview, not the trial")
  reaper.SetExtState(R.SECTION, "style", "built_try"); reaper.SetExtState(R.SECTION, "trial back", B.id) -- (a trial the engine knows about, the window just opened)
  R.use(A)
  assert(R.last_style == B.id, "nor My REAPER")
  reaper.DeleteExtState(R.SECTION, "style"); reaper.DeleteExtState(R.SECTION, "trial back")
  local ended = 0
  core.end_trial = function() ended = ended + 1; return A end
  bld.back, bld.preview = A.id, true
  press["Go back##strip"] = true; frame("Layout"); press["Go back##strip"] = nil
  assert(ended == 1 and bld.back == nil and bld.preview == false, "Go back ends the trial and turns Preview off")
  bld.back = A.id
  at_exit()
  assert(ended == 2 and bld.back == nil, "closing the window ends a preview")
  bld.back = A.id; mb_answer = 7
  press["Stop##strip"] = true; frame("Layout"); press["Stop##strip"] = nil
  assert(ended == 2 and #bld.blocks > 0, "Stop asks first, and No keeps everything")
  mb_answer = 6
  press["Stop##strip"] = true; frame("Layout"); press["Stop##strip"] = nil
  mb_answer = 1
  assert(ended == 3 and #bld.blocks == 0 and not bld.active, "Stop on yes ends the trial and the persona being made")

  -- 7. Small things: a theme saved during a preview goes into the draft; a key capture closes when the page changes.
  R.bld_new()
  R.add_fork({ id = "built_try", name = "Your persona" }, "Mine (mine 1).ReaperTheme")
  assert(theme_of() == "Mine (mine 1).ReaperTheme", "a theme saved during a preview is the draft's")
  assert(reaper.GetExtState(R.SECTION, "theme built_try") == "", "not a setting for the trial")
  bld.kq.cap = "x"; R.go("Mouse")
  assert(bld.kq.cap == nil, "a key capture closes when the page changes")
  core.use, core.busy, core.end_trial = real_use, real_busy, real_end
end

local ok, err = xpcall(run, debug.traceback)
assert(tmp:match("^tests/_tmp%-ui%-%d+%-%d+$")) -- (the whole test folder goes, pass or fail)
os.execute(win and ('rmdir /s /q "' .. tmp:gsub("/", "\\") .. '"') or ("rm -rf '" .. tmp .. "'"))
if not ok then error(err, 0) end
print("ok")
