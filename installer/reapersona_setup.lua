-- @noindex
-- ReaPersona installer step that runs INSIDE the live REAPER, with no dialogs, so an installer (or an AI one) can drive it:
--   Windows: reaper.exe -nonewinst "<this file>"   macOS: open -a REAPER.app "<this file>"   Linux: reaper -nonewinst "<this file>"
-- It reads reapersona_setup.json next to itself: { "persona": "<a styles.json id>", "repo_url": "<ReaPersona's index.xml>" }
-- and writes reapersona_setup_result.json next to itself: { ok, restart, persona, note, steps = [{ name, ok, detail }] }.
-- What it does: adds ReaPersona's ReaPack repository and syncs (left alone when ReaPersona is already here), waits for ReaPersona to
-- arrive, switches REAPER to the persona (look, mouse, toggles, the startup line), then installs that persona's shortcuts, which
-- needs one REAPER restart (not when a project has unsaved work: then Home > Install is left to the user).
-- Modelled on StudioSync's installer/studiosync_setup.lua (github.com/FmsJay/studiosync, same author, GPL-3.0).

-- ---------- pure helpers (self-checked below when this runs outside REAPER) ----------
-- Every string in the result is made JSON-safe by plain substitution (no escapes), so the Mac and Linux installers can read it with grep.
local function clean(s) return (tostring(s or ""):gsub('[\\"]', { ["\\"] = "/", ['"'] = "'" }):gsub("%c", " ")) end
local function encode(out)
  local b = { '{"ok":' .. tostring(out.ok == true) .. ',"restart":' .. tostring(out.restart == true) .. ',"persona":"' .. clean(out.persona) ..
    '","note":"' .. clean(out.note) .. '","steps":[' }
  for i, s in ipairs(out.steps) do -- (one step a line: install_mac.sh / install_linux.sh grep them)
    b[#b + 1] = '\n{"name":"' .. clean(s.name) .. '","ok":' .. tostring(s.ok == true) .. ',"detail":"' .. clean(s.detail) .. '"}' .. (i < #out.steps and "," or "")
  end
  return table.concat(b) .. "\n]}\n"
end
local function field(text, key) return (text or ""):match('"' .. key .. '"%s*:%s*"([^"]*)"') end -- (the request is two plain strings)

if not reaper then -- run with a plain Lua (lua reapersona_setup.lua, or lupa): check the helpers and stop
  local j = encode({ ok = false, persona = 'A "b"\\c', note = "line\nbreak", steps = { { name = "s1", ok = true, detail = "C:\\x" }, { name = "s2" } } })
  assert(not j:find("\\", 1, true), j)
  assert(j:find('\n{"name":"s1","ok":true,"detail":"C:/x"},', 1, true), j)
  assert(j:find('"persona":"A \'b\'/c"', 1, true) and j:find('"note":"line break"', 1, true) and j:find('"ok":false,"restart":false', 1, true), j)
  assert(j:find('{"name":"s2","ok":false,"detail":""}\n]}', 1, true), j)
  assert(field('{ "persona": "pro_tools",\n  "repo_url" : "https://x/index.xml" }', "persona") == "pro_tools")
  assert(field('{"repo_url":"https://x/index.xml"}', "repo_url") == "https://x/index.xml" and field("{}", "persona") == nil)
  print("reapersona_setup.lua self-check ok")
  return j
end

local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
do -- first: the installer waits for this before handing the step over again (a REAPER already open sometimes misses the first),
  -- and a second hand-off that arrives after all runs nothing (two copies would sync ReaPack twice). As studiosync_setup.lua.
  local was = io.open(here .. "/reapersona_setup_started", "r")
  local at = was and tonumber(was:read("a")); if was then was:close() end
  if at and os.time() - at < 600 then return end
  local s = io.open(here .. "/reapersona_setup_started", "w")
  if s then s:write(tostring(os.time())); s:close() end
end

local out = { ok = true, steps = {} }
local function step(name, ok, detail)
  out.steps[#out.steps + 1] = { name = name, ok = ok, detail = detail }
  if not ok then out.ok = false end
end
local function finish()
  local f = io.open(here .. "/reapersona_setup_result.json", "w")
  if f then f:write(encode(out)); f:close() end
end

local f = io.open(here .. "/reapersona_setup.json", "r")
if not f then step("read request", false, here .. "/reapersona_setup.json missing"); return finish() end
local text = f:read("a"); f:close()
local want = (field(text, "persona") or ""):match("^[%w_]+$") or "base_reaper" -- (nothing picked: plain REAPER, for someone new to it)
local repo_url = field(text, "repo_url") or "https://github.com/FmsJay/ReaPersona/raw/main/index.xml"

-- What ReaPersona needs loaded (the installer put them in UserPlugins before REAPER started): it won't open without ImGui and SWS.
for _, x in ipairs({ { "ReaImGui", "ImGui_GetBuiltinPath", "Extensions > ReaPack > Browse packages > ReaImGui" }, { "SWS", "CF_EnumerateActions", "sws-extension.org" },
                     { "js_ReaScriptAPI", "JS_Window_GetTitle", "Extensions > ReaPack > Browse packages > js_ReaScriptAPI" } }) do
  local here_now = reaper.APIExists(x[2])
  step(x[1] .. " loaded", here_now, not here_now and "not loaded: " .. x[3] or nil)
end

-- ReaPack installs it in Scripts/ReaPersona/Workflow (repository name / category); a copy put there by hand is used as it is.
local base = reaper.GetResourcePath() .. "/Scripts/ReaPersona"
local function core_path()
  for _, d in ipairs({ base .. "/Workflow", base, base .. "/ReaPersona" }) do
    if reaper.file_exists(d .. "/reapersona_core.lua") and reaper.file_exists(d .. "/styles.json") then return d .. "/reapersona_core.lua" end
  end
end

if not reaper.APIExists("ReaPack_AddSetRepository") then
  step("ReaPack loaded", false, "install ReaPack (reapack.com) and restart REAPER first")
  out.note = "ReaPack isn't loaded in REAPER, so ReaPersona couldn't be installed: restart REAPER and run this installer again."
  return finish()
end
if core_path() then
  -- (no ReaPack sync when it's there already: a sync while ReaPack's Transaction report is open crashes REAPER on macOS, and a re-run
  -- is exactly when that window may still be up. StudioSync, 2026-10-28)
  step("ReaPersona already installed", true, "left as it is")
else
  local added, err = reaper.ReaPack_AddSetRepository("ReaPersona", repo_url, true, 1) -- 1: install its packages on sync
  step("add ReaPersona's ReaPack repository", added, err ~= "" and err or repo_url)
  reaper.ReaPack_ProcessQueue(true)
  local sync = reaper.NamedCommandLookup("_REAPACK_SYNC")
  if added and sync ~= 0 then reaper.Main_OnCommand(sync, 0) end
  step("ReaPack sync started", sync ~= 0, "ReaPersona arrives in a minute or two")
end

-- Installs the persona's shortcuts: REAPER reads its keymap only when it starts, so it quits and comes back (about 10 seconds). As
-- ReaPersona.lua's install_shortcuts(): install_shortcuts.py where a real Python runs, else the swap step core.stage_install writes
-- (cmd on Windows, /bin/sh on a Mac or Linux). Everything is planned before the result is written; launch() then starts it and quits.
local function plan_keys(core)
  if not reaper.file_exists(core.here .. "/midi_defaults.json") then core.midi_defaults() end
  -- (on a Mac GetExePath() is the folder holding REAPER.app, "/Applications", not a path inside it: matching ".app" in it found nothing, and
  -- REAPER quit and never came back. install_shortcuts.py opens a .app with `open -a`)
  local d = reaper.GetExePath():gsub("\\", "/"):gsub("/+$", "")
  local exe = d .. (reaper.GetOS():find("^Win") and "/reaper.exe" or "/reaper") -- (Linux: the reaper binary beside it)
  -- (an AppImage: GetExePath is its temporary mount, gone once REAPER quits; $APPIMAGE is the file itself. Round 1, cross-platform 6)
  if not core.IS_MAC and not reaper.GetOS():find("^Win") then exe = os.getenv("APPIMAGE") or exe end
  if core.IS_MAC then
    exe = d:match("^(.-%.app)") or d .. "/REAPER.app"
    for _, a in ipairs({ d .. "/REAPER.app", d .. "/REAPER64.app" }) do if not d:match("%.app") and reaper.file_exists(a .. "/Contents/Info.plist") then exe = a; break end end
  end
  local cfg = reaper.get_ini_file():gsub("\\", "/") -- (-cfgfile users get REAPER back on the same configuration)
  os.remove(core.here .. "/install_cancelled") -- (an old one would stop the install at its first look)
  -- (on a Mac without the developer tools, /usr/bin/python3 is a stub that pops up an install offer: Python only where a real one is)
  local real_py = not core.IS_MAC or (reaper.ExecProcess("/bin/sh -c 'command -v python3 | grep -qv ^/usr/bin/ || xcode-select -p'", 5000) or ""):match("^0\n")
  if real_py and core.python() then
    local cmd = core.py .. ' "' .. core.here .. '/install_shortcuts.py" --after-reaper-quits --relaunch "' .. exe .. '" --cfgfile "' .. cfg .. '"'
    return function() reaper.ExecProcess(cmd, -1) end, "Python" -- (-1: don't wait)
  end
  local stepfile, why = core.stage_install({ pid = core.reaper_pid(), exe = exe, cfg = cfg, projects = {} })
  if not stepfile then return nil, why end
  if reaper.GetOS():find("^Win") then
    return function() reaper.ExecProcess('cmd.exe /c ""' .. stepfile:gsub("/", "\\") .. '""', -2) end, "a batch file" -- (-2: minimized, not closed halfway by mistake)
  end
  return function() reaper.ExecProcess('/bin/sh "' .. stepfile .. '"', -1) end, "a shell script" -- (a full path: a Mac runs a bare name as nothing)
end
-- A new REAPER's first-start windows (the evaluation reminder, the audio device question or error, ReaPack's windows) block File: Quit:
-- on a clean Linux the quit was refused, the install gave up and REAPER never restarted. So the restart waits for them to be answered
-- (up to 20 minutes, then it tries anyway). Needs js_ReaScriptAPI's window search; without it, as before. (Linux VM, 5.17.2)
-- (not a window titled just "REAPER": on Windows that's also the splash screen; the audio device question it would catch is modal, and no
-- script runs until it's answered)
local BLOCKERS = { { "About REAPER", false }, { "Error opening devices", true }, { "ReaPack Notice", true },
                   { "Notice", true }, { "Transaction report", true }, { "Manage repositories", true } }
local function blocker()
  if not reaper.JS_Window_Find then return nil end
  for _, b in ipairs(BLOCKERS) do
    local w = reaper.JS_Window_Find(b[1], b[2])
    if w and (not reaper.JS_Window_IsVisible or reaper.JS_Window_IsVisible(w)) then return b[1] end
  end
end
local function launch(core, start, since)
  since = since or reaper.time_precise()
  if blocker() and reaper.time_precise() - since < 1200 then return reaper.defer(function() launch(core, start, since) end) end
  start()
  reaper.Main_OnCommand(40004, 0) -- File: Quit (REAPER's own save prompts); the install starts it again
  local check = reaper.time_precise() + 4 -- (REAPER still running 4 s after: the quit was cancelled, and the waiting install is told)
  local function quit_check()
    if reaper.time_precise() < check then return reaper.defer(quit_check) end
    core.write(core.here .. "/install_cancelled", "quit was cancelled\n")
  end
  reaper.defer(quit_check)
end

local function apply(path)
  if not path then
    step("ReaPersona arrived", false, "not in " .. base .. " after 4 minutes")
    out.note = "ReaPersona hasn't arrived yet: in REAPER, Extensions > ReaPack > Synchronize packages, then run this installer again (or open ReaPersona from the Actions list and pick your DAW on Home)."
    return finish()
  end
  local ok, core = pcall(dofile, path)
  if not ok or type(core) ~= "table" then step("load ReaPersona", false, core); out.note = "ReaPersona didn't load: open it from the Actions list to see why."; return finish() end
  local st = core.by_id(want)
  if not st then step("persona " .. want, false, "ReaPersona doesn't know it"); out.note = "ReaPersona doesn't know '" .. want .. "': open it (Extensions > ReaPersona) and pick your DAW on Home."; return finish() end
  local rec = st.theme -- (the persona's recommended look-alike theme: downloaded first, so the switch below puts it on)
  if rec and not reaper.file_exists(core.themes_dir .. rec) and core.can_install_theme(rec) then
    local tok, got, why = pcall(core.install_theme, rec)
    local have = reaper.file_exists(core.themes_dir .. rec)
    step(st.name .. "'s look: " .. rec:gsub("%.ReaperTheme%a*$", ""), have,
      have and "downloaded" or ("not installed (" .. tostring((not tok and got) or why or "not in the download") .. "): ReaPersona's Themes page has it"))
  end
  local done, err = pcall(function()
    if core.scripts_missing() > 0 then core.ensure_scripts() end -- (the scripts its keys run, registered before the keys go in)
    core.use(st)
    if not core.startup_on() then core.add_startup() end -- (REAPER forgets the persona's shortcut layer at a restart: this brings it back)
    reaper.SetExtState(core.SECTION, "welcomed", "1", true) -- (its first-run "which DAW?" is answered)
  end)
  step("REAPER set up as " .. st.name, done, err)
  if not done then out.note = "ReaPersona couldn't switch to " .. st.name .. ": open it (Extensions > ReaPersona) and pick it on Home."; return finish() end
  out.persona = st.name
  -- (REAPER in use: quitting asks about unsaved work, and a Cancel left the shortcuts waiting for good. StudioSync review, 0.58.67)
  local unsaved = false
  for i = 0, 99 do local p, fn = reaper.EnumProjects(i); if not p then break end; if reaper.IsProjectDirty(p) ~= 0 and (fn ~= "" or reaper.CountTracks(p) > 0) then unsaved = true end end
  -- (a Flatpak REAPER: when it quits, its sandbox ends and takes the waiting install step with it, so the restart install would quit REAPER
  -- and change nothing. A keymap file to import by hand instead; install_linux.sh says how. Round 1, cross-platform M3)
  if reaper.file_exists("/.flatpak-info") then
    local ok, path, n, skipped = pcall(core.make_keymap)
    local made = ok and path ~= nil
    step("shortcuts", made, made and (n .. " keys in " .. path .. (skipped and #skipped > 0 and (" (" .. #skipped .. " left out)") or ""))
      or ("no keymap file: " .. tostring(not ok and path or (skipped and skipped[1]) or "unknown")))
    out.note = "REAPER now looks and clicks like " .. st.name .. ". This Flatpak REAPER can't restart itself to load shortcuts: " ..
      (made and "in REAPER, Actions > Show action list > Key Map... > Import..., pick " .. path .. " and choose to merge." or
       "open ReaPersona (Extensions > ReaPersona), Help > Check and repair, Make the keymap file, and import that.")
    return finish()
  end
  local start, how
  if not unsaved then start, how = plan_keys(core) end
  if start then
    out.restart = true
    step("shortcuts staged", true, "installed with " .. how .. " while REAPER restarts")
    out.note = "REAPER now looks and clicks like " .. st.name .. ". It restarts once, by itself, to load " .. st.name .. "'s shortcuts (about 10 seconds), " ..
      "as soon as REAPER's first-start windows are answered (the evaluation reminder, the audio device, ReaPack's windows)."
    finish()
    return reaper.defer(function() launch(core, start) end)
  end
  if not unsaved then step("shortcuts staged", false, how) end
  out.note = "REAPER now looks and clicks like " .. st.name .. ". For its shortcuts: " .. (unsaved and "save your project, then " or "") ..
    "open ReaPersona (Extensions > ReaPersona), Home, Install (REAPER restarts once)."
  finish()
end

-- ReaPack's sync is asynchronous: wait INSIDE REAPER, one request per installer run (a request arriving while ReaPack's report window
-- was open crashed REAPER on macOS). Arrived = the core there on two looks 2 s apart, so ReaPack has finished writing it; up to 4 minutes.
local started, seen = reaper.time_precise(), nil
local function look()
  local now, p = reaper.time_precise(), core_path()
  if not p then seen = nil elseif not seen then seen = now elseif now - seen >= 2 then return apply(p) end
  if now - started > 240 then return apply(nil) end
  reaper.defer(look)
end
look()
