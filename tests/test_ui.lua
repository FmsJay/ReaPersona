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
  local press, active, images_made, texts, inputs = {}, false, 0, {}, {}
  local FN_PREFIX = { DrawList = 1, ListClipper = 1, TextFilter = 1, Viewport = 1, Image = 1, Function = 1, FontAtlas = 1 }
  local OPEN = { Begin = 1, BeginChild = 1, BeginTable = 1, BeginTabBar = 1, BeginTabItem = 1, BeginGroup = 1, TreeNode = 1, TreeNodeEx = 1, CollapsingHeader = 1, BeginMenuBar = 1,
    BeginCombo = 1, BeginPopup = 1, BeginPopupModal = 1, BeginPopupContextItem = 1, BeginListBox = 1, BeginMenu = 1, BeginTooltip = 1 } -- (round 4: combos and popups open, so what's in them is drawn too)
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
    elseif k == "InputTextWithHint" then f = function(_, label, _, v) if inputs[label] ~= nil then return true, inputs[label] end return false, v end -- (its text is the 4th argument; a test can type one)
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

  -- 10. Layout > More windows and dockers (5.43; by side since round 4, James): the card draws, a window added is a dockpref block in the
  -- persona being made, keeping a side, and "Leave as it is" on the last one takes the block out.
  write(tmp .. "/reaper.ini", "[REAPER]\ndockermode3=1\n[REAPERdockpref]\nreaimgui:16B0B3D8=0.5 3\ntoolbar:26=-0.85 15\n")
  R.bld_new(); mb_answer = 6; R.bld_new(); mb_answer = 1
  T = T + 5; texts = {}; frame("Layout")
  local drew = false
  for s in pairs(texts) do if s:find("^Pick the side a window docks on") then drew = true end end
  assert(drew, "the dockers card draws")
  R.dockpref_set("reaimgui:16B0B3D8", "left")
  local db = core.draft_get(bld.blocks, "feel dockpref")
  assert(db and db.items["reaimgui:16B0B3D8"] == "left" and bld.active, "a window added is in the persona being made, with its side")
  local entry = core.build_preview({ db })[1][1]
  assert(entry and entry.entry[1] == "dockpref" and entry.entry[2]["reaimgui:16B0B3D8"] == "left", "the draft keeps the side")
  frame("Layout") -- (with a row now)
  R.dockpref_set("reaimgui:16B0B3D8", nil)
  assert(not core.draft_get(bld.blocks, "feel dockpref"), "Leave as it is on the last window takes the block out")

  -- 11. Round 4 (code-health probe_ui_r4.lua, adapted to sides; plus C1-C8). Combos are opened by the stand-in (OPEN), so their bodies draw.
  local real_sel, real_chk, real_dl, real_combo = ImGui.Selectable, ImGui.Checkbox, ImGui.DrawList_AddText, ImGui.BeginCombo
  local sel_labels, pick, tick_box, combos = {}, {}, {}, {}
  rawset(ImGui, "BeginCombo", function(_, label) combos[label] = true; return true end)
  rawset(ImGui, "Selectable", function(_, label) sel_labels[#sel_labels + 1] = label; return pick[label] == true end)
  rawset(ImGui, "Checkbox", function(_, label, v) if tick_box[label] then return true, true end return false, v end)
  local function fresh() R.bld_new(); mb_answer = 6; R.bld_new(); mb_answer = 1 end

  -- C5: no persona has dockers yet, so no Load from; the switch off in Settings > Personas is said on the card
  fresh(); combos = {}; texts = {}
  local real_on = core.aspect_on
  core.aspect_on = function(a) if a == "dockpref" then return false end return real_on(a) end
  frame("Layout")
  core.aspect_on = real_on
  assert(not combos["##dpload"], "Load from is left out while no persona has dockers")
  local off_said = false
  for s in pairs(texts) do if s:find("^Off in Settings > Personas") then off_said = true end end
  assert(off_said, "the card says the switch is off")

  -- UPD1: dockers loaded from a persona aren't turned into yours by being drawn; changing one keeps the others, and then it's yours
  core.styles[#core.styles + 1] = { id = "built_dkp", name = "DKP", user = true, kind = "built", keys = {}, alt = 0,
    feel = { { "dockpref", { ["toolbar:26"] = "left", transport = "bottom" }, "x" } } }
  fresh()
  core.draft_add(bld.blocks, core.new_block("feel", "built_dkp", "dockpref"))
  combos = {}; frame("Layout")
  db = core.draft_get(bld.blocks, "feel dockpref")
  assert(db.id == "built_dkp" and db.items == nil, "drawing the card doesn't turn a loaded block into yours")
  assert(combos["##dpload"], "Load from shows once a persona has dockers")
  R.dockpref_set("transport", "top")
  db = core.draft_get(bld.blocks, "feel dockpref")
  assert(db.items["toolbar:26"] == "left" and db.items.transport == "top", "changing one loaded window keeps the others")
  assert(core.block_title(db):lower() == "your window dockers", "and it's your own now: " .. core.block_title(db))

  -- UPD2: loading the whole layout from a DAW leaves your dockers in the persona (no DAW has any)
  local daw
  for _, st in ipairs(R.styles) do if st.id ~= "my_reaper" and not st.user and R.has_aspect(st, "transport") then daw = st; break end end
  assert(daw, "a DAW with a layout")
  pick[daw.name .. "##lall" .. daw.id] = true; frame("Layout"); pick = {}
  assert(core.draft_get(bld.blocks, "feel dockpref"), "the whole layout from " .. daw.name .. " kept your dockers")

  -- UPD3: Leave them all as they are takes the dockers out
  press["Leave them all as they are##dpclr"] = true; frame("Layout"); press["Leave them all as they are##dpclr"] = nil
  assert(not core.draft_get(bld.blocks, "feel dockpref"), "Leave them all as they are")

  -- UPD4: Add a window offers only names a persona can carry, sorted, and a window starts on the side it docks on now
  write(tmp .. "/reaper.ini", "[REAPER]\ndockermode15=1\n[REAPERdockpref]\nbad&name.lua=0.5 2\ntoolbar:26=-0.85 15\nreaimgui=0.5 0\n")
  T = T + 5; sel_labels = {}; frame("Layout")
  local offered, names = 0, {}
  for _, l in ipairs(sel_labels) do
    assert(not l:find("bad&name", 1, true), "a name with & isn't offered: " .. l)
    if l:find("##dpa", 1, true) then offered = offered + 1; names[#names + 1] = l:match("^(.-)##"):lower() end
    assert(l ~= "reaimgui##dpareaimgui", "a bare reaimgui names no window")
  end
  assert(offered > 0, "Add a window offers windows")
  for i = 2, #names do assert(names[i - 1] <= names[i], "the Add list is sorted: " .. names[i - 1] .. " / " .. names[i]) end
  pick["Toolbar 26##dpatoolbar:26"] = true; frame("Layout"); pick = {}
  db = core.draft_get(bld.blocks, "feel dockpref")
  assert(db and db.items["toolbar:26"] == "left", "a window added starts on the side it docks on now: " .. tostring(db and db.items["toolbar:26"]))
  table.remove(core.styles)

  -- UPD5: a window added with no persona being made starts one (the bar at the top shows it)
  bld.blocks, bld.active = {}, false
  R.dockpref_set("transport", "right")
  assert(bld.active and core.draft_get(bld.blocks, "feel dockpref"), "adding a window starts a persona to save")

  -- UW1 + C6: the wheel's modifier ticks are its own, and an action picked there waits for Add, as in the drag form
  fresh()
  local real_find = core.find_actions
  core.find_actions = function() return { { 40001, "Probe action" } } end
  tick_box["Ctrl##mbw2"] = true; pick["Probe action##asrwadd40001"] = true; inputs["##aswadd"] = "probe"
  frame("Mouse")
  inputs = {}
  pick = {}
  assert(not core.draft_get(bld.blocks, "mouse"), "picking an action doesn't add it by itself")
  press["Add to my persona##wadd"] = true; frame("Mouse"); press["Add to my persona##wadd"] = nil
  tick_box = {}
  core.find_actions = real_find
  local mb = core.draft_get(bld.blocks, "mouse")
  local added = mb and mb.extra and mb.extra[#mb.extra]
  assert(added and added[1] == "Ctrl+Mousewheel" and added[2] == 40001, "Ctrl ticked for the wheel, added with Add: " .. tostring(added and added[1]))

  -- US1 + C3: Save during a preview says what the project part did, and leaves the remembered Preview tick as you set it
  fresh()
  core.draft_add(bld.blocks, core.new_block("theme", "Saved4.ReaperTheme"))
  bld.name = "Test saved4 " .. os.time()
  local ru = core.use
  core.use = function(st) core.last_project_setup = { "tempo 120" }; set_style(st.id) end
  reaper.SetExtState(R.SECTION, "draft preview", "1", true)
  bld.back, bld.preview = A.id, true; set_style("built_try")
  local saved4 = R.bld_save()
  assert(saved4 and bld.msg:find("and this project has its tempo 120", 1, true), "the project part, said: " .. bld.msg)
  assert(not bld.preview and reaper.GetExtState(R.SECTION, "draft preview") == "1", "Preview off for this draft, the remembered tick kept")
  core.delete_user_style(saved4.id); core.last_project_setup = {}

  -- C2 (James): saving My REAPER during a preview ends it like any persona: My REAPER in use, Undo switch back
  local rsl = core.save_look
  core.save_look = function() end
  R.bld_load(core.by_id("my_reaper"))
  core.draft_add(bld.blocks, core.new_block("theme", "Mine4.ReaperTheme"))
  bld.back, bld.preview = A.id, true; set_style("built_try"); R.last_style = nil
  R.bld_save()
  core.save_look, core.use = rsl, ru
  assert(reaper.GetExtState(R.SECTION, "style") == "my_reaper" and bld.back == nil, "My REAPER is in use and the preview is over")
  assert(R.last_style == A.id and bld.msg:find("My REAPER is saved and in use", 1, true), "Undo switch goes back, and it says so: " .. bld.msg)

  -- C1 (James): Undo with Preview on: REAPER follows about 0.15 s after the LAST press
  fresh(); set_style(A.id)
  local tries = 0
  core.use = function(st) tries = tries + 1; set_style(st.id) end
  tick()
  change(core.new_block("theme", "U1.ReaperTheme")); change(core.new_block("theme", "U2.ReaperTheme")); change(core.new_block("theme", "U3.ReaperTheme"))
  bld.preview, bld.shown = true, bld.hist[bld.pos]
  bld.step(-1); tick(0.1); bld.step(-1); tick(0.1)
  assert(tries == 0, "not while the presses keep coming")
  tick(0.1)
  assert(tries == 1, "once, about 0.15 s after the last press: " .. tries)
  tick(0.3); assert(tries == 1, "and only once")
  core.use = ru; bld.back, bld.preview = nil, false; set_style(A.id)

  -- C4: Flatpak text from the screen-reader menu without SWS: no ImGui clipboard call on a released context, and no "on the clipboard"
  rawset(reaper, "CF_SetClipboard", false)
  R.menu_mode = true
  local steps = R.flatpak_steps("--apply-setup")
  R.menu_mode = false
  assert(steps:find("type this now", 1, true) and not steps:find("clipboard", 1, true), "not copied, so not said: " .. steps)
  rawset(reaper, "CF_SetClipboard", nil)
  assert(R.flatpak_steps("--apply-setup"):find("paste this now (it's on the clipboard", 1, true), "copied, then said")

  -- UI4: the top bar shows the name the persona being made has now
  local pills = {}
  rawset(ImGui, "DrawList_AddText", function(_, _, _, _, text) pills[#pills + 1] = tostring(text) end)
  bld.back, bld.preview, bld.name = A.id, false, "Renamed probe"; set_style("built_try")
  frame("Home")
  rawset(ImGui, "DrawList_AddText", real_dl)
  bld.back = nil; set_style(A.id)
  local shown = false
  for _, t in ipairs(pills) do if t:find("^Renamed probe %(trying%)") then shown = true end end
  assert(shown, "the top bar follows a rename: " .. table.concat(pills, " | "))

  -- UI5: a workflow with colours is the one named as holding them
  local rcur, rwf = core.current, core.current_workflow
  core.current = function() return { id = "holds", name = "Holds colours", colours = { look = "x" } } end
  core.current_workflow = function() return { id = "wfp", name = "WF probe", colours = { look = "y" } } end
  texts = {}; frame("Colours")
  core.current, core.current_workflow = rcur, rwf
  local wf_named = false
  for s in pairs(texts) do if s:find("^WF probe sets the colours") then wf_named = true end end
  assert(wf_named, "the workflow on top holds the colours")

  -- UI2: a Flatpak import keeps the new layer numbers (nothing comes back to say it went in)
  local lc = {}
  local rcl, rld, rmk, rprep, rflat = core.cancel_layers, core.layers_done, core.make_keymap, core.prepare_layers, R.FLATPAK
  core.cancel_layers = function() lc[#lc + 1] = "cancel" end
  core.layers_done = function() lc[#lc + 1] = "done" end
  core.make_keymap = function() return tmp .. "/probe-keymap.ReaperKeyMap", 3, {} end
  core.prepare_layers = function() end
  R.FLATPAK = true
  R.install_shortcuts(false, nil, true)
  R.FLATPAK = rflat
  assert(table.concat(lc, ",") == "done" and R.recount_keys, "Flatpak: layers kept, Home recounts: " .. table.concat(lc, ","))
  R.recount_keys = nil

  -- UI3: the screen-reader menu's own path reads last_install.txt through install_result
  lc = {}
  local rmenu = R.show_menu
  R.show_menu = function() return 0 end
  write(dir .. "/last_install.txt", "not installed: probe\n")
  R.screen_reader_menu(true)
  R.show_menu = rmenu
  assert(lc[1] == "cancel" and not read(dir .. "/last_install.txt"), "the menu puts the layer numbers back: " .. table.concat(lc, ","))
  core.cancel_layers, core.layers_done, core.make_keymap, core.prepare_layers = rcl, rld, rmk, rprep
  R.menu_mode = nil

  -- C8: closing the window while an install's quit is still being checked tells the installer (the second window's close handler)
  os.remove(dir .. "/install_cancelled")
  R2.quit_check = T + 4
  at_exit()
  assert(read(dir .. "/install_cancelled"), "the installer is told the quit may have been cancelled")
  R2.quit_check = nil; os.remove(dir .. "/install_cancelled")

  rawset(ImGui, "Selectable", real_sel); rawset(ImGui, "Checkbox", real_chk); rawset(ImGui, "BeginCombo", real_combo)
  fresh()

  -- 12. James, 2026-11-19: save over a persona of yours or My REAPER (asked first, never a DAW); a name one of yours has asks too.
  local pick2, labels2 = {}, {}
  rawset(ImGui, "Selectable", function(_, label) labels2[#labels2 + 1] = label; return pick2[label] == true end)
  local ru2, rsl2 = core.use, core.save_look
  core.use = function(st) set_style(st.id) end
  local mine_name = "Over target " .. os.time()
  local target = core.save_built({ core.new_block("theme", "Before.ReaperTheme") }, mine_name)
  assert(target and target.id, "a persona of yours to save over")
  local vers0 = #core.versions(target.id)
  fresh()
  core.draft_add(bld.blocks, core.new_block("theme", "After.ReaperTheme"))
  bld.name = "Typed elsewhere" -- (saved over, it keeps the name it has)
  labels2 = {}; frame("Layout")
  local offers_mine, offers_my, offers_daw = false, false, false
  for _, l in ipairs(labels2) do
    if l == mine_name .. "##sov" .. target.id then offers_mine = true end
    if l == "My REAPER##sovmy_reaper" then offers_my = true end
    for _, st in ipairs(R.styles) do if not st.user and st.id ~= "my_reaper" and l == st.name .. "##sov" .. st.id then offers_daw = true end end
  end
  assert(offers_mine and offers_my and not offers_daw, "Save over lists yours and My REAPER, never a DAW")
  mb_answer = 7; pick2[mine_name .. "##sov" .. target.id] = true; frame("Layout"); pick2 = {}; mb_answer = 1
  assert(mb_said[#mb_said]:find("Save over " .. mine_name .. "?", 1, true), "it asks first")
  assert(core.draft_get(core.by_id(target.id).blocks, "theme").file == "Before.ReaperTheme" and not bld.id, "No leaves it as it was")
  mb_answer = 6; pick2[mine_name .. "##sov" .. target.id] = true; frame("Layout"); pick2 = {}; mb_answer = 1
  local after = core.by_id(target.id)
  assert(after and core.draft_get(after.blocks, "theme").file == "After.ReaperTheme" and after.name == mine_name, "Yes saves over it, keeping its id and name")
  assert(#core.versions(target.id) == vers0 + 1 and bld.id == target.id, "and keeps the one before under Earlier versions")
  -- typing that name and pressing Save as new asks too, instead of making a second one of that name
  fresh()
  core.draft_add(bld.blocks, core.new_block("theme", "Again.ReaperTheme"))
  bld.name = mine_name:upper()
  mb_answer = 6; press["Save as new##strip"] = true; frame("Layout"); press["Save as new##strip"] = nil; mb_answer = 1
  local named = 0
  for _, st in ipairs(R.styles) do if st.name:lower() == mine_name:lower() then named = named + 1 end end
  assert(named == 1 and core.draft_get(core.by_id(target.id).blocks, "theme").file == "Again.ReaperTheme", "a name you have: saved over it, not a second one")
  -- My REAPER, through its own save (its look)
  local looks = 0
  core.save_look = function() looks = looks + 1 end
  fresh()
  core.draft_add(bld.blocks, core.new_block("theme", "Look.ReaperTheme"))
  mb_answer = 6; pick2["My REAPER##sovmy_reaper"] = true; frame("Layout"); pick2 = {}; mb_answer = 1
  assert(looks == 1 and bld.id == "my_reaper" and bld.msg:find("My REAPER is saved", 1, true), "saving over My REAPER saves its look: " .. tostring(bld.msg))
  core.use, core.save_look = ru2, rsl2
  core.delete_user_style(target.id)
  rawset(ImGui, "Selectable", real_sel)
  fresh()

  -- 13. James, 2026-11-19: Every shortcut and Every mouse action show the common ones unless Show all actions is ticked (this computer only)
  assert(R.common_key({ name = "Transport: Play/stop", common = 0 }) and R.common_key({ name = "Item: Split", common = 3 }), "transport, or 3 personas")
  assert(not R.common_key({ name = "Item: Split", common = 2 }), "a key fewer than 3 personas share isn't")
  assert(R.common_mouse({ ctx = "MM_CTX_ENVPT", sources = { "Logic Pro" } }) and R.common_mouse({ ctx = "MM_CTX_ITEM", sources = { "REAPER (as set now)" } }), "a persona's line, or a main place")
  assert(not R.common_mouse({ ctx = "MM_CTX_ENVPT", sources = { "REAPER (as set now)" } }), "REAPER's own line in a side place isn't")
  local adds, real_small = {}, ImGui.SmallButton
  rawset(ImGui, "SmallButton", function(_, label) local i = label:match("^Add##ak(%d+)$"); if i then adds[#adds + 1] = tonumber(i) end return press[label] == true end)
  reaper.SetExtState(R.SECTION, "every action", "0", true)
  local cat = core.catalog(R.styles, core.read(tmp .. "/reaper-kb.ini") or "", nil)
  frame("Shortcuts") -- (its first look may only say it's reading)
  local function more_hidden() for s in pairs(texts) do if s:find("more with Show all actions", 1, true) then return true end end return false end
  local function listed() for s in pairs(texts) do local a = s:match("^%d+ of (%d+) shown"); if a then return tonumber(a) end end return 0 end
  adds, texts = {}, {}; frame("Shortcuts")
  local common_total = listed()
  assert(#adds > 0 and more_hidden(), "by default some rows wait for Show all actions")
  for _, i in ipairs(adds) do assert(R.common_key(cat[i]), "only common rows by default: " .. tostring(cat[i] and cat[i].name)) end
  reaper.SetExtState(R.SECTION, "every action", "1", true)
  adds, texts = {}, {}; frame("Shortcuts")
  assert(listed() > common_total and not more_hidden(), "Show all actions lists the rest too: " .. listed() .. " vs " .. common_total)
  rawset(ImGui, "SmallButton", function(_, label) local i = label:match("^Add##am(%d+)$"); if i then adds[#adds + 1] = tonumber(i) end return press[label] == true end)
  reaper.SetExtState(R.SECTION, "every action", "0", true)
  adds, texts = {}, {}; frame("Mouse"); local mouse_common = #adds
  local mouse_hid = more_hidden()
  reaper.SetExtState(R.SECTION, "every action", "1", true)
  adds, texts = {}, {}; frame("Mouse")
  assert(mouse_common > 0 and #adds >= mouse_common and not more_hidden(), "the mouse list: common by default, all when ticked: " .. mouse_common .. " / " .. #adds)
  assert(mouse_hid or #adds == mouse_common, "and anything left out is counted")
  rawset(ImGui, "SmallButton", real_small)
  reaper.SetExtState(R.SECTION, "every action", "0", true)

  -- 14. James, 2026-11-19: one My REAPER. Saving what you use on My REAPER offers an alt, and a name a persona has saves nothing
  local gui, offered, typed = reaper.GetUserInputs, nil, nil
  reaper.GetUserInputs = function(_, _, _, default) offered = default; return true, typed or default end
  local rsp = core.save_preset
  local saved_as
  core.save_preset = function(name) saved_as = name; return { id = "preset_t", name = name } end
  set_style("my_reaper")
  typed = "my reaper"; R.save_preset_prompt()
  assert(offered:find("^My REAPER alt") and not offered:find("(mine)", 1, true), "on My REAPER the copy is an alt: " .. tostring(offered))
  assert(not saved_as and said():find("already in it", 1, true), "typing My REAPER saves no second one: " .. tostring(said()))
  typed = nil; R.save_preset_prompt()
  assert(saved_as == offered, "the alt name saves")
  core.save_preset, reaper.GetUserInputs = rsp, gui
end

local ok, err = xpcall(run, debug.traceback)
assert(tmp:match("^tests/_tmp%-ui%-%d+%-%d+$")) -- (the whole test folder goes, pass or fail)
os.execute(win and ('rmdir /s /q "' .. tmp:gsub("/", "\\") .. '"') or ("rm -rf '" .. tmp .. "'"))
if not ok then error(err, 0) end
print("ok")
