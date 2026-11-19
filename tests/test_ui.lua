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
  local press, active, images_made, texts = {}, false, 0, {}
  local FN_PREFIX = { DrawList = 1, ListClipper = 1, TextFilter = 1, Viewport = 1, Image = 1, Function = 1, FontAtlas = 1 }
  local OPEN = { Begin = 1, BeginChild = 1, BeginTable = 1, BeginTabBar = 1, BeginTabItem = 1, BeginGroup = 1, TreeNode = 1, TreeNodeEx = 1, CollapsingHeader = 1, BeginMenuBar = 1 }
  local ImGui = setmetatable({
    Button = function(_, label) return press[label] == true end,
    SmallButton = function(_, label) return press[label] == true end,
    IsAnyItemActive = function() return active end,
    CreateImage = function() images_made = images_made + 1; return {} end,
    TextWrapped = function(_, s) texts[s] = true end, -- (what muted() and wrapped lines showed)
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
  local function set_style(id) reaper.SetExtState(R.SECTION, "style", id, true) end
  core.use = function(st) used[#used + 1] = st; set_style(st.id) end -- (a switch: recorded, and the persona in use is noted as the engine does)
  local ended, ended_with = 0, {}
  core.end_trial = function(now) -- (stand-in: records whether the window said "now")
    if not core.is_trial() then return nil end
    ended = ended + 1; ended_with[#ended_with + 1] = now == true
    set_style(R.styles[2].id); return R.styles[2]
  end
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
  assert(said():find("Undone: the B theme", 1, true), "Undo says what it undid, in plain words: " .. said())
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
  assert(#bld.blocks > 0 and mb_said[#mb_said]:find("isn't saved", 1, true), "New asks before throwing an unsaved persona away")
  mb_answer = 6; R.bld_new(); mb_answer = 1
  assert(#bld.blocks == 0, "and goes ahead on yes")
  set_style("my_reaper")
  tick()
  bld.preview = true
  local proj = core.new_block("project"); proj.srate = 48000
  used = {}
  change(proj)
  assert(#used == 0, "not straight away")
  tick(0.7); assert(#used == 1, "once, a moment after the change")
  tick(0.7); assert(#used == 1, "and only once")
  assert(used[1].id == "built_try" and used[1].project == nil, "the project part stays out of a preview")
  assert(used[1].name == R.bld_default_name(), "the preview has the name the bar shows: " .. tostring(used[1].name))
  assert(bld.later and bld.later:find("project part", 1, true), "the bar lists the project part as not shown")
  assert(bld.back == "my_reaper" and bld.preview, "Go back returns to the persona before the preview, and the preview stays on")

  -- 6. What ends a preview: using another persona (James: the draft stays, Preview turns off), a switch made outside the window,
  -- Go back, Stop, closing the window.
  local A, B = R.styles[2], R.styles[3]
  bld.back, bld.preview = A.id, true; set_style("built_try")
  R.use(B)
  assert(bld.back == nil and bld.preview == false, "using another persona ends the preview")
  assert(reaper.GetExtState(R.SECTION, "draft preview") == "0", "and the remembered tick agrees")
  assert(#bld.blocks > 0, "the persona being made stays")
  assert(R.last_style == A.id, "Undo switch goes back to the persona from before the preview, not the trial")
  set_style("built_try") -- (a trial this window didn't start)
  R.use(B)
  assert(R.last_style == A.id, "nor to the trial or My REAPER")
  bld.back, bld.preview = A.id, true; set_style(B.id) -- (B picked from a toolbar or key while previewing)
  tick()
  assert(bld.back == nil and bld.preview == false and #bld.blocks > 0, "a switch outside the window ends the preview, the draft stays")
  assert(said():find("preview has ended", 1, true), "and says so: " .. said())
  ended, ended_with = 0, {}
  bld.back, bld.preview = A.id, true; set_style("built_try")
  press["Go back##strip"] = true; frame("Layout"); press["Go back##strip"] = nil
  assert(ended == 1 and bld.back == nil and bld.preview == false, "Go back ends the trial and turns Preview off")
  bld.back = A.id; set_style("built_try")
  at_exit()
  assert(ended == 2 and bld.back == nil, "closing the window ends a preview")
  assert(ended_with[2] == true, "closing passes true to end_trial, so the window moves happen before the script ends")
  bld.back = A.id; set_style("built_try"); mb_answer = 7
  press["Stop##strip"] = true; frame("Layout"); press["Stop##strip"] = nil
  assert(ended == 2 and #bld.blocks > 0, "Stop asks first, and No keeps everything")
  mb_answer = 6
  press["Stop##strip"] = true; frame("Layout"); press["Stop##strip"] = nil
  mb_answer = 1
  assert(ended == 3 and #bld.blocks == 0 and not bld.active, "Stop on yes ends the trial and the persona being made")
  assert(said():find("Back to " .. R.styles[2].name, 1, true), "Stop says what came back: " .. said())

  -- 7. Small things: a theme saved during a preview goes into the draft; a key capture closes when the page changes; My REAPER saved
  -- doesn't ask again.
  R.bld_new()
  local trial = { id = "built_try", name = "Your persona" }
  local real_current = core.current
  core.current = function() return trial end; set_style("built_try")
  R.add_fork(trial, "Mine (mine 1).ReaperTheme")
  core.current = real_current; set_style(A.id)
  assert(theme_of() == "Mine (mine 1).ReaperTheme", "a theme saved during a preview is the draft's")
  assert(reaper.GetExtState(R.SECTION, "theme built_try") == "", "not a setting for the trial")
  bld.kq.cap = "x"; R.go("Mouse")
  assert(bld.kq.cap == nil, "a key capture closes when the page changes")
  local real_save_look = core.save_look
  core.save_look = function() end
  R.bld_load(core.by_id("my_reaper"))
  core.draft_add(bld.blocks, core.new_block("theme", "Z.ReaperTheme"))
  R.bld_save()
  local asked = #mb_said
  R.bld_new()
  assert(#mb_said == asked and #bld.blocks == 0, "after saving My REAPER, New doesn't warn that it isn't saved")
  core.save_look = real_save_look
  R.bld_load(A); core.draft_add(bld.blocks, core.new_block("theme", "Y.ReaperTheme")); mb_answer = 7
  R.bld_load(B)
  assert(mb_said[#mb_said]:find("Edit " .. B.name .. " instead?", 1, true), "Edit asks in its own words: " .. mb_said[#mb_said])
  mb_answer = 6; R.bld_load(B); mb_answer = 1

  -- 8. The spread-out sync: started, a little each loop, "Syncing..." meanwhile, then the result (round 2, James).
  local real_folder, real_tick = core.sync_folder, core.sync_tick
  local calls, budgets = 0, {}
  core.sync_folder = function() return "sync" end
  core.sync_tick = function(quick, budget)
    calls = calls + 1; budgets[#budgets + 1] = budget
    if budget and calls < 3 then core.sync_job = {}; return nil end
    core.sync_job = nil; return { others = {}, changed = false }
  end
  R.sync_step(true)
  assert(R.syncing and calls == 1 and budgets[1] and budgets[1] <= 20, "Sync now starts a spread-out sync")
  texts = {}; frame("Settings")
  assert(texts["Syncing..."], "Settings > Sync says Syncing... meanwhile")
  R.loop(); assert(R.syncing and calls == 2, "the loop does a little more")
  R.loop(); assert(not R.syncing and calls == 3, "and ends it")
  assert(said():find("Up to date", 1, true), "Sync now says the result: " .. said())
  core.sync_tick = function() core.sync_job = nil; return nil end
  R.sync_step(true)
  assert(not R.syncing and R.sync_err and said():find("Couldn't sync", 1, true), "a sync that fails says so")
  calls = 0 -- (a sync finished from outside the window, e.g. by taking another computer's setup: no second one starts)
  core.sync_tick = function() calls = calls + 1; core.sync_job = {}; return nil end
  R.sync_step(true); assert(R.syncing and calls == 1)
  core.sync_job = nil -- (finished elsewhere)
  R.sync_more()
  assert(not R.syncing and calls == 1, "a sync finished outside the window doesn't start a second one")
  assert(said():find("Synced", 1, true), "and Sync now still gets an answer: " .. said())
  core.sync_folder, core.sync_tick, R.sync_err = real_folder, real_tick, nil

  -- 8b. Round 3: the close handler finishes a sync under way and runs one more (James keeps the full sync at close); an install's result
  -- keeps or puts back the layer numbers (UP1, UP2 from code-health round 3, probe_ui_r3.lua).
  local sync_args = {}
  local rt = core.sync_tick
  core.sync_tick = function(...) sync_args[#sync_args + 1] = select("#", ...) == 0 and "none" or tostring(select(2, ...)); return nil end
  at_exit()
  assert(sync_args[#sync_args] == "none", "UP1: closing finishes the sync, unbudgeted: " .. tostring(sync_args[#sync_args]))
  sync_args = {}; core.sync_job = {} -- (one under way at close)
  core.sync_tick = function(...) sync_args[#sync_args + 1] = select("#", ...); core.sync_job = nil; return nil end
  at_exit()
  core.sync_tick = rt
  assert(#sync_args == 2 and sync_args[1] == 0 and sync_args[2] == 0, "a sync under way at close is finished, then one more runs: " .. #sync_args)
  local lcalls = {}
  local rc, rd = core.cancel_layers, core.layers_done
  core.cancel_layers = function() lcalls[#lcalls + 1] = "cancel" end
  core.layers_done = function() lcalls[#lcalls + 1] = "done" end
  write(dir .. "/last_install.txt", "not installed: a file couldn't be written (your keymap was backed up first)\n")
  R.first_frame = true; frame("Home")
  write(dir .. "/last_install.txt", "installed 12 shortcut(s); backup: reaper-kb.ini.before-reapersona-1\n")
  R.first_frame = true; frame("Home")
  write(dir .. "/last_install.txt", "REAPER didn't close, so the shortcuts weren't installed.\n")
  R.first_frame = true; frame("Home")
  assert(table.concat(lcalls, ",") == "cancel,done,cancel" and not read(dir .. "/last_install.txt"),
    "UP2: failed -> layers back; installed -> done; didn't close -> back: " .. table.concat(lcalls, ","))
  lcalls = {}
  write(dir .. "/last_install.txt", "not installed: no\n")
  assert(R.install_result() and lcalls[1] == "cancel", "the screen-reader menu's path puts them back the same way")
  lcalls = {}
  local rx, rp, rs, rprep = core.relaunch_exe, core.python, core.stage_install, core.prepare_layers
  local asked_exe = 0
  core.relaunch_exe = function() asked_exe = asked_exe + 1; return "/opt/REAPER/reaper" end
  core.python, core.prepare_layers = function() return nil end, function() end
  reaper.get_ini_file = function() return tmp .. "/reaper.ini" end
  core.stage_install = function(o) assert(o.exe == "/opt/REAPER/reaper", "the relaunch is the engine's: " .. tostring(o.exe)); return nil, "probe" end
  R.install_shortcuts(false, nil, true)
  core.relaunch_exe, core.python, core.stage_install, core.prepare_layers = rx, rp, rs, rprep
  assert(asked_exe == 1 and lcalls[1] == "cancel", "an install that can't start asks core.relaunch_exe and puts the layer numbers back")
  core.cancel_layers, core.layers_done = rc, rd

  -- 8c. Round 3 (James): Save during a preview makes the saved persona the one in use, with Undo switch back to what you had.
  R.bld_new(); mb_answer = 6; R.bld_new(); mb_answer = 1
  core.draft_add(bld.blocks, core.new_block("theme", "Saved.ReaperTheme"))
  bld.name = "Test saved " .. os.time()
  bld.back, bld.preview = A.id, true; set_style("built_try"); R.last_style = nil
  local saved = R.bld_save()
  assert(saved and reaper.GetExtState(R.SECTION, "style") == saved.id, "the saved persona is in use")
  assert(bld.back == nil and bld.preview == false, "the preview is over")
  assert(R.last_style == A.id and reaper.GetExtState(R.SECTION, "last style") == A.id, "Undo switch goes back to what you had")
  assert(bld.msg:find("is saved and in use", 1, true) and bld.msg:find("puts " .. A.name .. " back", 1, true), "and it says so: " .. bld.msg)
  core.delete_user_style(saved.id)

  -- 8d. Remove with a workflow on: the workflow is off before My REAPER goes on (engine round 3, 4); the Colours page says when a
  -- persona holds the colours.
  reaper.SetExtState(R.SECTION, "workflow", "voiceover", true)
  local wf_at_use
  core.use = function(st) wf_at_use = reaper.GetExtState(R.SECTION, "workflow"); set_style(st.id) end
  mb_answer = 6; press["Remove ReaPersona..."] = true; frame("SetRemove"); press["Remove ReaPersona..."] = nil; mb_answer = 1
  R.removing = nil
  assert(wf_at_use == "", "Remove takes the workflow off before switching to My REAPER: " .. tostring(wf_at_use))
  local holder = { id = "holds", name = "Holds colours", colours = { look = "x" } }
  core.current = function() return holder end
  texts = {}; frame("Colours")
  core.current = real_current
  local warned = false
  for s in pairs(texts) do if s:find("sets the colours while it's in use", 1, true) then warned = true end end
  assert(warned, "the Colours page says a persona holds the colours")
  core.use, core.busy, core.end_trial = real_use, real_busy, real_end

  -- 9. Opening the window on a preview left from before ends it, through core.fix_current (code health round 2, R2-1).
  local fixed, ended2 = 0, {}
  local real_dofile = dofile
  dofile = function(p, ...) -- (the second window's engine, with stand-ins that record what the window asked)
    local m = real_dofile(p, ...)
    if tostring(p):match("reapersona_core%.lua$") then
      local real_fix = m.fix_current
      m.end_trial = function(now) if not m.is_trial() then return nil end ended2[#ended2 + 1] = now; m.persist(m.SECTION, "style", A.id); return A end
      m.fix_current = function(...) fixed = fixed + 1; return real_fix(...) end
    end
    return m
  end
  set_style("built_try"); reaper.SetExtState(R.SECTION, "trial back", A.id, true)
  deferred = nil
  local ok2, e2 = pcall(real_dofile, dir .. "/ReaPersona.lua")
  dofile = real_dofile
  assert(ok2, tostring(e2))
  local R2; for i = 1, 30 do local n, v = debug.getupvalue(deferred, i); if not n then break end if n == "_ENV" then R2 = v end end
  assert(fixed == 1, "opening the window calls core.fix_current once")
  assert(not R2.core.is_trial(), "and the leftover preview is ended")
  assert(R2.toast:find("A preview was still on", 1, true), "and the window says so: " .. tostring(R2.toast))
end

local ok, err = xpcall(run, debug.traceback)
assert(tmp:match("^tests/_tmp%-ui%-%d+%-%d+$")) -- (the whole test folder goes, pass or fail)
os.execute(win and ('rmdir /s /q "' .. tmp:gsub("/", "\\") .. '"') or ("rm -rf '" .. tmp .. "'"))
if not ok then error(err, 0) end
print("ok")
