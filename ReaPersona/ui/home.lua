-- ReaPersona's window: Home: getting started, set up, Get more.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 1600-2038.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
function setup_row(id, done, what, why, button, fn, tip)
  ImGui.TableNextRow(ctx)
  ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx)
  if done == "optional" then ImGui.TextColored(ctx, C.MUTED, "Optional") else ImGui.TextColored(ctx, done and C.GREEN or C.YELLOW, done and "Done" or "To do") end
  ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.PushTextWrapPos(ctx, 0); ImGui.Text(ctx, what)
  if why and why ~= "" then ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.MUTED); ImGui.Text(ctx, why); ImGui.PopStyleColor(ctx) end
  ImGui.PopTextWrapPos(ctx)
  ImGui.TableNextColumn(ctx)
  if button and fn and ImGui.SmallButton(ctx, button .. "##" .. id) then fn() end
  if tip then ImGui.SetItemTooltip(ctx, tip) end
end
function get_url(u)
  if u == "builtin" then return reaper.MB("It comes with REAPER: it should already be in ColorThemes.", "ReaPersona", 0) end
  core.open_url(u)
end
function shortcuts_state()
  local want, have = 0, 0
  for _, st in ipairs(styles) do if (st.alt or 0) > 0 then want = want + 1; if (installed[st.alt] or 0) >= #core.keys_here(st.keys) then have = have + 1 end end end
  return have, want
end
function try_theme(th)
  local back = trying and trying.back or core.loaded_theme()
  reaper.OpenColorThemeFile(themes_dir .. th)
  trying = { name = th, back = back, ends = reaper.time_precise() + 20 }
end
function trial_over() -- (every loop, drawn or not; and when the window closes)
  if not trying or trying.ends > reaper.time_precise() then return end
  if trying.back then reaper.OpenColorThemeFile(themes_dir .. trying.back); say("Back to " .. trying.back:gsub("%.ReaperTheme%a*$", "") .. ".") end
  trying = nil
end
function trying_bar() -- (under the top bar while a theme is on trial; goes back by itself when time's up)
  trial_over()
  if not trying then return end
  local left = trying.ends - reaper.time_precise()
  ImGui.SetCursorPosX(ctx, 16)
  ImGui.TextColored(ctx, C.YELLOW, "Trying " .. trying.name:gsub("%.ReaperTheme.*$", "") .. string.format(" (back in %d s)", math.ceil(left)))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Keep it##try") then say((trying.name:gsub("%.ReaperTheme%a*$", "")) .. " kept."); trying = nil; return end
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Go back##try") then trying.ends = 0 end
end
function setup_todo() -- (anything on Home still to do: the nav shows a dot, and the first run opens there)
  local have, want = shortcuts_state()
  return have < want or not core.startup_on()
end
function build_themes()
  say("Building ReaPersona's themes...")
  local made, why = core.build_own_themes()
  theme_list = nil
  reaper.MB(made and (#made .. " themes built in ColorThemes, from your REAPER's own Default 7:\n\n" .. table.concat(made, "\n") ..
    "\n\nEach DAW persona uses its ReaPersona theme unless you've picked another.") or ("Not built: " .. tostring(why)), "ReaPersona", 0)
end
-- REAPER reads its keymap only when it starts: install_shortcuts.py waits for REAPER to close, installs, and starts it again. Without
-- Python the same install is planned here and a swap step puts it in: a batch file on Windows (5.14), a /bin/sh script on a Mac or
-- Linux (5.16; until then a Mac without Python got a keymap to import by hand, and no toolbars). core.stage_install.
-- A Flatpak REAPER (FLATPAK, base.lua): the shortcuts go in by import, the rest with the installer from a terminal.
-- (Round 3: the command first, and on the clipboard, since a Linux message box can't be copied from; Remove's before ReaPack's uninstall,
-- which takes install_shortcuts.py with it.)
local CLIPBOARD = "\n\n(It's on the clipboard: paste it into a terminal.)"
local function flatpak_remove_text()
  return "Close REAPER, run this in a terminal, then start REAPER again:\n\n" .. flatpak_cmd("--remove --apply-prefs") .. CLIPBOARD ..
    "\n\nIt takes the shortcut layers and toolbars out of your keymap (backed up first) and puts your own preferences and windows back. " ..
    "Run it before you uninstall ReaPersona in ReaPack: it needs ReaPersona's files."
end
local function flatpak_install(remove)
  if remove then return reaper.MB("This REAPER runs as a Flatpak, so ReaPersona can't finish with a restart.\n\n" .. flatpak_remove_text(), "ReaPersona: remove", 0) end
  local path, n, skipped = core.make_keymap()
  if not path then core.cancel_layers(); return reaper.MB("No keymap made: " .. tostring(skipped[1]), "ReaPersona", 0) end
  reaper.MB("This REAPER runs as a Flatpak, which closes anything waiting for REAPER to quit, so ReaPersona can't install with a restart.\n\n" ..
    "Everything at once (the shortcuts, toolbars, and whatever is waiting for a restart): close REAPER, run this in a terminal, then start REAPER again:\n\n" ..
    flatpak_cmd("--apply-setup") .. CLIPBOARD ..
    "\n\nOr just the shortcuts, without closing REAPER: in the Actions window (opening now), choose Key Map > Import..., pick\n" .. path ..
    "\nand choose to merge, not replace. That's " .. n .. " shortcuts." .. (#skipped > 0 and (" Skipped (no action here yet): " .. table.concat(skipped, ", ") .. ".") or ""),
    "ReaPersona: install the shortcuts", 0)
  core.layers_done() -- (the layer numbers as the file holds them: nothing comes back to say it went in)
  recount_keys = true -- (Home counts them again when the window is back from the Actions window)
  reaper.Main_OnCommand(40605, 0) -- (Show action list)
end
function install_result() -- the last install's note (last_install.txt, then gone), with the layer numbers kept or put back. -> the note, or nil
  local note = core.read(here .. "/last_install.txt")
  if not note then return end
  os.remove(here .. "/last_install.txt")
  -- (only "installed N shortcut(s)" keeps the new numbers; "not installed", "didn't close ... weren't installed" and the rest put them back.
  -- The window and the screen-reader menu both come here. Round 3)
  if note:match("installed %d+ shortcut") then core.try("the install went in", core.layers_done) else core.try("putting layer numbers back", core.cancel_layers) end
  return note
end
function install_shortcuts(remove, extra, asked) -- (remove: Remove ReaPersona, which has asked already: the lines come out instead. extra: a persona that
  -- needs its layer now; asked: the question was already put)
  if not remove then
    local what = core.pending_words(core.restart_pending())
    if not asked and not FLATPAK and reaper.MB("REAPER closes (it asks about anything unsaved first) and opens again in about 10 seconds, with your projects.\n\n" ..
      "Going in: your persona shortcuts" .. (what ~= "" and (", " .. what) or "") .. ".\n\nYour keymap is backed up first.", "ReaPersona: restart REAPER", 1) ~= 1 then return end
    core.prepare_layers(extra) -- (5.29: layers for the personas this computer uses; shared where the keys are the same)
    if core.scripts_missing() > 0 then core.ensure_scripts() end -- (the scripts the keys run have to be registered first)
    if not reaper.file_exists(here .. "/midi_defaults.json") then core.midi_defaults() end
  end
  if FLATPAK then return flatpak_install(remove) end
  local exe = core.relaunch_exe() -- (what starts this REAPER again: the .app on a Mac, an AppImage's own file. One rule in the engine: round 3)
  local projects, open = {}, {} -- (the projects open now, reopened with REAPER)
  for i = 0, 50 do
    local p, fn = reaper.EnumProjects(i)
    if not p then break end
    if fn ~= "" and not fn:find('"', 1, true) then projects[#projects + 1] = fn; open[#open + 1] = ' --open "' .. fn .. '"' end
  end
  local cfg = reaper.get_ini_file():gsub("\\", "/") -- (-cfgfile users get REAPER back on the same configuration)
  os.remove(here .. "/install_cancelled") -- (before the installer starts: an old one would stop it at its first look)
  if core.python() then
    local setup = #core.restart_pending() > 0 and not remove and " --apply-setup" or "" -- (your setup from your other computers, waiting for a restart)
    if remove and reaper.file_exists(here .. "/pending/prefs.json") then setup = " --apply-prefs" end -- (Remove: your own preferences back. Review 2026-11-18)
    reaper.ExecProcess(core.py_quiet() .. ' "' .. here .. '/install_shortcuts.py" --after-reaper-quits --relaunch "' .. exe .. '" --cfgfile "' .. cfg .. '"' .. (remove and " --remove" or "") .. setup .. table.concat(open), -1) -- (-1: don't wait)
  else
    local step, why = core.stage_install({ remove = remove, pid = core.reaper_pid(), exe = exe, cfg = cfg, projects = projects })
    if not step then core.cancel_layers(); return reaper.MB("Nothing was installed: " .. tostring(why), "ReaPersona", 0) end -- (layer numbers back as installed)
    if reaper.GetOS():find("^Win") then
      reaper.ExecProcess('cmd.exe /c ""' .. step:gsub("/", "\\") .. '""', -2) -- (-2: minimized, so it isn't closed halfway by mistake)
    else
      reaper.ExecProcess('/bin/sh "' .. step .. '"', -1) -- (it starts itself again detached from REAPER and returns; a full path: a Mac runs a bare name as nothing)
    end
  end
  reaper.Main_OnCommand(40004, 0) -- (File: Quit, with REAPER's own save prompts)
  quit_check = reaper.time_precise() + 4 -- (REAPER still running 4 s after: the quit was cancelled, and the installer is told)
end
remove_finish = function() -- (Remove ReaPersona, once My REAPER is back) -> false: the window closes
  local done = core.uninstall()
  reaper.MB(table.concat(done, "\n") .. (FLATPAK and ("\n\nNext, as this REAPER runs as a Flatpak: " .. flatpak_remove_text() ..
      "\n\nLast, once that's done: Extensions > ReaPack > Browse packages, right-click ReaPersona > Uninstall.")
      or ("\n\nNext: REAPER closes (it asks first if anything is unsaved), the shortcut layers and toolbars come out of your keymap, and REAPER opens again." ..
        "\n\nLast: Extensions > ReaPack > Browse packages, right-click ReaPersona > Uninstall.")), "ReaPersona: removed", 0)
  if not FLATPAK then install_shortcuts(true) end -- (Flatpak: the message above is the rest)
  return false
end
-- (in R: setup_job) -- (Set up everything: one step per frame behind a progress window, so REAPER never looks frozen. 5.25)
function finish_setup() -- (5.37: the startup line, quietly, then the shortcuts with REAPER's one restart)
  if not core.startup_on() then local ok, why = core.add_startup(); if not ok then return reaper.MB("The startup line wasn't added: " .. tostring(why), "ReaPersona", 0) end end
  local have, want = shortcuts_state()
  if have < want or #core.restart_pending() > 0 then install_shortcuts() else say("Set up: your persona comes back each time REAPER starts.") end
end
function setup_all()
  if reaper.MB("Set up everything ReaPersona can do from here?\n\n" ..
    "- add the startup line that brings your persona back when REAPER starts\n" ..
    "- offer the smooth playhead / smooth scrolling extensions\n- then the shortcut install: " ..
    (FLATPAK and "the steps to import them (this Flatpak REAPER can't restart itself)" or "REAPER closes and opens again (about 10 seconds), which also loads new extensions") .. "\n\n" ..
    "(ReaPersona's own DAW themes are under Advanced, below.)", "ReaPersona: set up", 4) ~= 6 then return end
  local steps = { { "Adding the startup line", function(done)
    if not core.startup_on() then done[#done + 1] = core.add_startup() and "Startup line added" or "Startup line not added" end
  end } }
  for key, x in pairs(core.EXTENSIONS) do
    if core.ext_here(key) and core.extension_state(key) == "missing" and core.can_install(key) then
      steps[#steps + 1] = { "Offering " .. x.name, function(done)
        if reaper.MB("Install " .. x.name .. "? (" .. x.why .. ")", "ReaPersona", 4) == 6 and core.install_extension(key) then done[#done + 1] = x.name .. " installed (restart REAPER)" end
      end }
    end
  end
  steps[#steps + 1] = { FLATPAK and "The steps to install the shortcuts" or "Installing the shortcuts (REAPER restarts)", function(done)
    reaper.MB((#done > 0 and (table.concat(done, "\n") .. "\n\n") or "") .. "Last step: the shortcuts.", "ReaPersona: set up", 0)
    install_shortcuts()
  end }
  setup_job = { steps = steps, i = 0, done = {} }
end
function setup_progress() -- (drawn every frame while Set up everything runs; a step runs only after the window has been shown)
  if not setup_job then return end
  local j = setup_job
  ImGui.OpenPopup(ctx, "ReaPersona: setting up")
  local cx, cy = ImGui.Viewport_GetCenter(ImGui.GetWindowViewport(ctx))
  ImGui.SetNextWindowPos(ctx, cx, cy, ImGui.Cond_Always, 0.5, 0.5) -- (over the middle of ReaPersona's window)
  if ImGui.BeginPopupModal(ctx, "ReaPersona: setting up", nil, ImGui.WindowFlags_AlwaysAutoResize) then
    local s = j.steps[j.i + 1]
    ImGui.Text(ctx, (s and s[1] or "Done") .. "...")
    ImGui.ProgressBar(ctx, j.i / #j.steps, 360, 0, j.i .. " of " .. #j.steps)
    muted("Each step takes a moment: leave REAPER open until this closes.")
    ImGui.EndPopup(ctx)
  end
  if not j.shown then j.shown = true; return end
  j.i = j.i + 1
  local s = j.steps[j.i]
  if s then local ok, err = pcall(s[2], j.done); if not ok then j.done[#j.done + 1] = s[1] .. ": " .. tostring(err) end end
  if j.i >= #j.steps then setup_job = nil end
  j.shown = false -- (the next step after the window shows the new one)
end
function setup_page()
  if reaper.GetExtState(SECTION, "welcomed") == "" and card("welcome") then -- (the first run: pick your DAW, it's in use straight away)
    heading("Which DAW are you coming from?", 20)
    muted("A persona makes REAPER work like another DAW: its shortcuts, mouse, layout and look. My REAPER is your own setup, and you can always go back to it.")
    muted("Pick it and REAPER takes on its look and layout now, and its shortcuts once they're installed (Getting started, below). You can switch any time, and Back to My REAPER puts everything back. " ..
      "If you'd already set REAPER up your own way, that setup is first kept as a persona of its own, \"My REAPER as it was\".")
    local n = 0
    local row_end = ImGui.GetCursorScreenPos(ctx) + ImGui.GetContentRegionAvail(ctx) -- (buttons that don't fit go on the next line: at Large text they were cut off)
    for _, st in ipairs(styles) do
      if st.kind ~= "theme" and (st.alt or 0) > 0 and not st.user and not st.preset and st.id ~= "base_reaper" then
        if n > 0 then
          ImGui.SameLine(ctx)
          if ImGui.GetCursorScreenPos(ctx) + ImGui.CalcTextSize(ctx, st.name) + 24 * UI > row_end then ImGui.NewLine(ctx) end
        end
        n = n + 1
        if primary(st.name .. "##welcome", accent_of(st)) then
          selected = st.id; use(st); reaper.SetExtState(SECTION, "welcomed", "1", true)
          core.set_favourite("my_reaper", true); core.set_favourite(st.id, true) -- (your setup and the DAW you came from, on Favourites. 5.27)
          local kept = core.by_id(reaper.GetExtState(SECTION, "first setup"))
          if setup_todo() then say(st.name .. " in use." .. (kept and (" Your own setup is kept as " .. kept.name .. ".") or "") .. " Next: Finish setting up, below" .. (FLATPAK and "." or " (REAPER restarts once).")) end
        end
      end
    end
    if ImGui.SmallButton(ctx, "I'll pick later") then reaper.SetExtState(SECTION, "welcomed", "1", true) end
    card_end()
  end
  local have0, want0 = shortcuts_state()
  if reaper.GetExtState(SECTION, "onboarded") == "" and core.current().id ~= "my_reaper" and have0 == want0 and core.startup_on() then
    reaper.SetExtState(SECTION, "onboarded", "1", true) -- (steps 1-3 done: the card goes; step 4 is optional. Review, 5.14)
  end
  if reaper.GetExtState(SECTION, "onboarded") == "" and card("first steps") then -- (5.14: the first run, step by step, until it's done or hidden)
    heading("Getting started")
    local have, want = have0, want0
    local steps = {
      { core.current().id ~= "my_reaper", "1. Pick the DAW you're coming from", "Its look and feel straight away, and its shortcuts once they're installed (step 2). Back to My REAPER (top) puts yours back.", "Pick one", function() go("DAWs") end },
      { have == want and core.startup_on(), FLATPAK and "2. Finish setting up" or "2. Finish setting up (one restart)",
        (FLATPAK and "You import the shortcuts in REAPER's Actions window (the button gives the steps)." or "REAPER restarts once (about 10 seconds; it asks about anything unsaved first).") .. " Your persona's shortcuts go in, and your persona comes back each time REAPER starts. Your keymap is backed up first.", "Finish setting up", function() finish_setup() end }, -- (5.37: one step, one restart)
      { core.sync_folder() ~= "" and true or "optional", "3. More than one computer? (optional)", "Save your setup to a file, or keep them the same through a shared folder.", "Set it up", function() go("Settings") end },
    }
    if ImGui.BeginTable(ctx, "first steps", 3, ImGui.TableFlags_SizingStretchProp) then
      ImGui.TableSetupColumn(ctx, "state", ImGui.TableColumnFlags_WidthFixed, 56)
      ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      for i, s in ipairs(steps) do setup_row("step" .. i, s[1], s[2], s[3], s[1] ~= true and s[4] or nil, s[5]) end
      ImGui.EndTable(ctx)
    end
    if ImGui.SmallButton(ctx, "How it works (F1)##first") then go("Guide") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Hide these steps##first") then reaper.SetExtState(SECTION, "onboarded", "1", true) end
    card_end()
  end
  if card("setup top") then
    heading("Set up ReaPersona")
    muted("What ReaPersona can use, whether it's there, and one click to get each. Drag files onto this window any time to add them: themes (.ReaperThemeZip, .ReaperTheme or the theme pack .zip as downloaded), toolbars (.ReaperMenu), keymaps (.ReaperKeyMap, become a persona of their own), and shared personas and presets.")
    if primary("Set up everything") then setup_all() end
    card_end()
  end
  if card("setup computers") then -- (another computer of yours: its setup in one click, or kept the same through a folder. 5.12.1)
    heading("Your other computers")
    local syncing = core.sync_folder() ~= ""
    muted(syncing and ("Syncing through " .. core.sync_folder() .. ": your personas, presets and settings stay the same on every computer that uses this folder.")
      or "Using ReaPersona on another computer too? Load the setup you saved there, or keep them the same through a shared folder (Syncthing, Google Drive, Dropbox...).")
    if ImGui.Button(ctx, "Save, load or sync your setup##home") then go("Settings") end
    ImGui.SetItemTooltip(ctx, "Settings > Sync: Save to a file, Load a file, and syncing through a folder.")
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
      local have, want = shortcuts_state()
      local layers_used = {}
      for _, st in ipairs(styles) do if (st.alt or 0) > 0 then layers_used[st.alt] = true end end
      local nl = 0; for _ in pairs(layers_used) do nl = nl + 1 end
      setup_row("keys", have == want, "Shortcut layers: " .. have .. " of " .. want .. " personas installed (" .. nl .. " of REAPER's 16 layers in use)",
        "Each persona's keys. " .. (FLATPAK and "You import them in REAPER's Actions window." or "REAPER restarts to load them (about 10 seconds).") .. " REAPER has 16 layers, so ReaPersona gives them to the personas you use (favourites, the one in use, your own); a persona without one gets it the first time it's used, and personas with the same keys share one.", have < want and (FLATPAK and "Install" or "Install and restart") or "Reinstall", install_shortcuts)
      setup_row("start", core.startup_on(), "Brings your persona back when REAPER starts", "A few lines in REAPER's startup script (Scripts/__startup.lua).", not core.startup_on() and "Add it" or nil,
        function() local ok, why = core.add_startup(); say(ok and "Startup line added." or tostring(why)) end)
      local pend = core.restart_pending()
      if #pend > 0 then setup_row("pend", false, "Waiting for REAPER to restart: " .. core.pending_words(pend), "They go in when REAPER starts.", FLATPAK and "How to put them in" or "Restart REAPER now", install_shortcuts) end
      local ext_keys = {}
      for key in pairs(core.EXTENSIONS) do if core.ext_here(key) then ext_keys[#ext_keys + 1] = key end end -- (Windows-only ones only on Windows)
      table.sort(ext_keys)
      for _, key in ipairs(ext_keys) do
        local x, s = core.EXTENSIONS[key], core.extension_state(key)
        setup_row("ext" .. key, s == "on" or s == "off", x.name .. (s == "restart" and " (restart REAPER to load it)" or ""), x.why .. " Recommended by the DAW personas.",
          s == "missing" and core.can_install(key) and "Install" or nil, function() install_ext(key) end)
      end
      ImGui.EndTable(ctx)
    end
    -- (5.25, James: setting everything up shouldn't build ReaPersona's own themes: the themes by other people look closer, and building
    -- them held REAPER. Here for whoever wants them)
    if ImGui.CollapsingHeader(ctx, "Advanced: ReaPersona's own DAW themes##advthemes") then
      if ImGui.BeginTable(ctx, "setup adv", 3, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
        ImGui.TableSetupColumn(ctx, "state", ImGui.TableColumnFlags_WidthFixed, 56)
        ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
        ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed)
      local py = core.python()
      setup_row("py", py ~= nil, "Python 3" .. (py and (" (" .. py .. ")") or ""), "Builds ReaPersona's own themes. The shortcut install doesn't need it.",
        not py and "Get it" or nil, function() core.open_url("https://www.python.org/downloads/") end)
      if py then
        local job, jwhy = core.libs_job() -- (the background install: running, or how it just ended)
        if job == "ok" then say("Pillow and numpy are installed: Build makes ReaPersona's themes.")
        elseif job == "failed" then reaper.MB("Pillow and numpy weren't installed: " .. tostring(jwhy), "ReaPersona", 0) end
        local libs = job ~= "running" and core.python_libs()
        setup_row("libs", libs, "Pillow and numpy for Python" .. (job == "running" and " (installing...)" or ""),
          job == "running" and "pip is downloading them in the background (a minute or two). Keep working: this says when they're in."
            or "The image tools the theme builder uses, in a folder of ReaPersona's own (ReaPersona/venv), so your system's Python isn't changed.",
          not libs and job ~= "running" and "Install them" or nil, function()
          if reaper.MB("ReaPersona makes a Python environment of its own in its folder (venv) and pip installs Pillow and numpy into it, " ..
            "in the background: REAPER keeps working, and this row says when they're in (a minute or two).", "ReaPersona", 1) ~= 1 then return end
          local ok, why = core.install_python_libs()
          if ok then say("Installing Pillow and numpy in the background...") else reaper.MB("Not started: " .. tostring(why), "ReaPersona", 0) end
        end)
      end
      local n, total = core.own_themes_built()
      setup_row("own", n == total, "ReaPersona's own themes: " .. n .. " of " .. total .. " built", "A theme per DAW in its colours, made from your REAPER's own Default 7. They're approximations: the themes by other people below can look closer to the real DAWs.",
        py and core.python_libs() and (n == total and "Rebuild" or "Build") or nil, build_themes)
        ImGui.EndTable(ctx)
      end
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
            reaper.MB(s and (s.name .. " is in Personas (install its shortcuts on Home). " .. #missed .. " of your assignments are for commands ReaPersona doesn't map yet.") or ("Not imported: " .. tostring(missed)), "ReaPersona", 0)
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
        reaper.MB(s and (s.name .. " is in Personas (install the shortcuts on Home).") or ("Not imported: " .. tostring(missed)), "ReaPersona", 0)
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
    muted("Made by REAPER's theme authors in each DAW's likeness. They can't ship with ReaPersona, so Install downloads one from where its author shares it and takes it in, fonts and extras too. Get it opens a page that needs your browser (paid, or a sign-in): download there, then drop the file onto this window.")
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
              not have and (core.can_install_theme(th) and "Install" or "Get it") or nil,
              function() if core.can_install_theme(th) then install_theme_ui(th, st, false) else get_url(c.url) end end, c.url)
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
br = { cat = "Themes", sort = "nd", q = "", page = 1, items = nil, msg = "" }
function browse_load()
  local items, why = core.stash_list(br.cat, br.sort, br.q, br.page)
  br.items, br.msg = items, items and "" or tostring(why)
end
function browse_page()
  if card("br top") then
    heading("Get more themes")
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

-- Making a persona (5.27; James: "all the blocks should move and just be based on the tabs so you can choose more granularly ... Blocks are
-- built automatically from all settings, then constructed into the persona. More tabs for each type of block"). The persona being made holds
-- one block per slot (core.block_slot); each tab chooses what fills its slots, line by line: Shortcuts, Mouse, Layout, Themes, Colours,
-- Project and REAPER. The bar over every tab shows it, names it and saves it. Edit on any persona's page starts from that one.
bld = { blocks = {}, name = "", id = nil, msg = "", colour = nil, back = nil, active = false }
function bld_load(st) -- edit a persona: one you built is saved over itself; any other (a DAW, My REAPER, a saved setup) is saved as a new one of yours
  if not bld_may_drop("Edit " .. st.name .. " instead?") then return end -- (a half-made persona isn't thrown away without asking)
  if bld.back then bld_end_trial() end -- (nor a preview of it left in REAPER)
  local mine = (st.blocks and st.user and st.kind == "built") or st.id == "my_reaper" -- (My REAPER is yours too: saved over, as its look. 5.28)
  bld.blocks = core.blocks_of(st)
  bld.name, bld.id, bld.msg, bld.active = mine and st.name or "", mine and st.id or nil, "", true
  bld.hist, bld.pos, bld.shown = nil, nil, nil
  bld.preview = reaper.GetExtState(SECTION, "draft preview") == "1"
  bld.from = not mine and st.name or nil -- (unnamed, it's saved as "<this> - custom")
  local c = core.draft_get(bld.blocks, "colour")
  bld.colour = c and tonumber((c.hex or ""):gsub("#", ""), 16) or nil
  bld.snap = bld.json(bld.blocks) -- (Stop asks only once something changed)
  say("Editing " .. st.name .. ": change its shortcuts, mouse, layout, theme, colours, project or REAPER settings on their tabs. " ..
    (mine and "Save changes from the bar at the top." or ("Save from the bar at the top makes a new persona (" .. st.name .. " stays as it is).")) ..
    (bld.preview and " Preview is on: REAPER shows it as you change it." or ""))
end
