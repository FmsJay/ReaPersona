-- ReaPersona's window: Settings: sync, personas, scrolling, look, updates, remove.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 1000-1301.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
-- Settings: what personas may change, a persona per project, the smooth playhead / scroll extensions, and the look.
LOOKS = { "Follow StudioSync", "Dark", "Light", "Midnight", "Warm" }
function switch(id, on) -- an on/off switch: -> clicked
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
function setting_row(id, label, on, tip)
  local clicked = switch(id, on)
  if tip then ImGui.SetItemTooltip(ctx, tip) end
  ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, label)
  if tip then ImGui.SetItemTooltip(ctx, tip) end
  return clicked
end
-- Your other computers (5.10): the folder you pick, the first sync (whose setup wins), and a look every 20 s while the window is open.
sync_next, sync_err, sync_seen, sync_full = reaper.time_precise() + 2, nil, "", reaper.time_precise() + 10 -- (the window draws before the first sync, about 1 s of loading: 5.39; and opens without waiting for REAPER's own parts)
function sync_step(now) -- (now: Sync now pressed, so the result is said. The advanced parts every 5 minutes, or on Sync now)
  if core.sync_folder() == "" then return end
  sync_next = reaper.time_precise() + 20
  core.quick = not (now or reaper.time_precise() >= sync_full)
  if not core.quick then sync_full = reaper.time_precise() + 1800 end -- (REAPER's own parts: on opening, Sync now and every 30 minutes)
  local ok, rep, why = pcall(core.sync_now)
  core.quick = nil
  if not ok then why, rep = rep, nil end
  sync_err = not rep and ("Couldn't sync: " .. tostring(why)) or nil
  if not rep then if now then say(sync_err) end return end
  local names = {}
  for _, o in ipairs(rep.others) do if o.d then names[#names + 1] = tostring(o.d.computer or o.name) end end -- (one that doesn't parse: its own line)
  sync_seen = table.concat(names, ", ")
  if rep.changed or now then
    say((rep.changed and ("From your other computers: " .. core.setup_summary(rep) .. ".") or "Up to date.") ..
      ((rep.ext or 0) > 0 and (" " .. core.SETUP_RESTART) or "") .. (rep.install and " New shortcuts need installing (Home)." or ""))
  end
end
function choose_sync_folder()
  if not reaper.JS_Dialog_BrowseForFolder then say("Choosing a folder needs js_ReaScriptAPI (ReaPack).") return end
  local ok, dir = reaper.JS_Dialog_BrowseForFolder("A folder your computers share (Syncthing, Google Drive...)", core.sync_folder() ~= "" and core.sync_folder() or res)
  if ok ~= 1 or dir == "" then return end
  dir = dir:gsub("\\", "/"):gsub("/+$", "")
  local names = {}
  for _, o in ipairs(core.sync_others(dir)) do names[#names + 1] = o.d and tostring(o.d.computer or o.name) or o.name end
  local start
  if #names > 0 then
    local r = reaper.MB("The folder already has the ReaPersona setup of " .. table.concat(names, ", ") .. ".\n\n" ..
      "Yes: take theirs here. Where both have the same persona or setting, theirs wins; what only this computer has goes to them.\n" ..
      "No: this computer's setup wins and goes to them (personas deleted on the others since may come back).\nCancel: don't sync.", "ReaPersona: sync", 3)
    if r == 2 then return end
    start = r == 6 and "theirs" or "mine"
  end
  local rep, why = core.start_sync(dir, start)
  sync_err = not rep and ("Couldn't sync: " .. tostring(why)) or nil
  if rep then sync_next = reaper.time_precise() + 20 end
  say(rep and ("Syncing through " .. dir .. (rep.changed and (": " .. core.setup_summary(rep) .. " came in." .. ((rep.ext or 0) > 0 and (" " .. core.SETUP_RESTART) or "")) or ".")) or sync_err)
end
function save_setup_file() -- (Settings, and the screen-reader menu)
  local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Save your ReaPersona setup", res, "ReaPersona setup " .. os.date("%Y-%m-%d") .. ".reapersona-setup.json", "ReaPersona setup (*.json)\0*.json\0\0")
  if not reaper.JS_Dialog_BrowseForSaveFile then say("Saving a file needs js_ReaScriptAPI (ReaPack).")
  elseif ok == 1 and p ~= "" then
    if not p:lower():match("%.json$") then p = p .. ".reapersona-setup.json" end
    local done, why = core.export_setup(p)
    say(done and ("Saved " .. p .. ". On the other computer: Settings > Load a file, or drop it on ReaPersona's window.") or ("Not saved: " .. tostring(why)))
  end
end
function load_setup_file()
  local ok, p = reaper.GetUserFileNameForRead(res .. "/", "Load a ReaPersona setup", "json")
  local fine, d = false, nil
  if ok and p ~= "" then fine, d = pcall(core.json_decode, core.read(p) or "") end
  if ok and p ~= "" and fine and type(d) == "table" and d.items and not core.confirm_setup(d, p:match("[^/\\]+$")) then ok = false end
  if ok and p ~= "" then
    local r, why = core.import_setup(p)
    if r then
      say("Loaded " .. core.setup_summary(r) .. "." .. ((r.ext or 0) > 0 and (" " .. core.SETUP_RESTART) or "") ..
        (r.install and " Your personas with shortcuts of their own need them installed (Home)." or "") .. (r.skipped and (" Left alone (a file of yours doesn't parse): " .. r.skipped .. ".") or ""))
    else say("Not loaded: " .. tostring(why)) end
  end
end
upd = {} -- (Settings > Updates: what GitHub said, when, and what updating did)
function settings_page(sec) -- (5.33: in sub-tabs; sec = which)
  if sec == "sync" and card("set sync") then
    heading("Your other computers")
    muted("Your personas, presets and ReaPersona's settings, with Smooth Wheel Scroll's and ReaSmoothPlayhead's settings, in one file to take to another computer, or kept the same on all of them through a folder they share (Syncthing, Google Drive, Dropbox...). Themes, and where this computer's windows and dockers are, stay as they are.")
    if ImGui.Button(ctx, "Save to a file...") then save_setup_file() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Load a file...") then load_setup_file() end
    ImGui.Dummy(ctx, 0, 4)
    local dir = core.sync_folder()
    if dir == "" then
      ImGui.Text(ctx, "Keep them the same through a shared folder")
      muted("Pick a folder your computers share, here and then on each of the others. Each computer keeps its own file in it; the newest change to each persona or setting wins. ReaPersona looks when REAPER starts and while its window is open.")
      if primary("Choose a folder...") then choose_sync_folder() end
    else
      ImGui.TextWrapped(ctx, "Syncing through " .. dir)
      local t, what, skipped = reaper.GetExtState(SECTION, "sync last"):match("^(%d+)|([^|]*)|?(.*)$")
      if t then muted("Last looked " .. os.date("%H:%M", tonumber(t)) .. " (" .. what .. ")" .. (sync_seen ~= "" and ("; with " .. sync_seen) or ""))
      else muted("Not synced yet.") end
      if skipped and skipped ~= "" then ImGui.TextColored(ctx, C.YELLOW, "Skipped (doesn't parse, left as it is): " .. skipped:gsub("^skipped ", "")) end
      if sync_err then ImGui.TextColored(ctx, C.YELLOW, sync_err) end
      if ImGui.Button(ctx, "Sync now") then sync_step(true) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Change folder...") then choose_sync_folder() end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Stop syncing") then core.stop_sync(); sync_err, sync_seen = nil, ""; say("Not syncing any more. Your setup here stays as it is.") end
    end
    local pend = core.restart_pending() -- (shown whether or not the advanced parts are unfolded)
    if #pend > 0 then
      ImGui.TextColored(ctx, C.YELLOW, "Waiting for REAPER to restart: " .. core.pending_words(pend))
      if primary("Restart REAPER now##applysetup") then install_shortcuts() end
      ImGui.SetItemTooltip(ctx, "REAPER closes (asking about anything unsaved), these go in (what's replaced is backed up first), and it opens again.")
    end
    ImGui.Dummy(ctx, 0, 4)
    local n_adv = 0
    for _, a in ipairs(core.ADVANCED) do if core.advanced_on(a.id) then n_adv = n_adv + 1 end end
    if setting_row("##advsync", "Advanced: REAPER itself too" .. (n_adv > 0 and ("  (" .. n_adv .. " part" .. (n_adv == 1 and "" or "s") .. " syncing)") or ""), reaper.GetExtState(SECTION, "sync show advanced") == "1",
        "Your preferences, other scripts' settings, shortcuts, menus and toolbars, templates, your own scripts and JSFX, themes and ReaPack packages, each part chosen below.") then
      reaper.SetExtState(SECTION, "sync show advanced", reaper.GetExtState(SECTION, "sync show advanced") == "1" and "" or "1", true)
    end
    if reaper.GetExtState(SECTION, "sync show advanced") == "1" then
      muted("Each part goes in the setup file and the sync folder from this computer, and is taken in here, only while it's ticked here. Paths, audio and MIDI devices and window places always stay this computer's own.")
      for _, a in ipairs(core.ADVANCED) do
        local on = core.advanced_on(a.id)
        local needs_py = (a.id == "code" or a.id == "packages") and not core.python()
        ImGui.BeginDisabled(ctx, needs_py and not on)
        if setting_row("##adv" .. a.id, a.name .. (needs_py and " (needs Python)" or ""), on, a.tip) then
          if on then core.set_advanced(a.id, false)
          else
            local theirs = false
            if core.sync_folder() ~= "" then
              theirs = reaper.MB("Take your other computers' " .. a.name:lower() .. " here first?\n\nYes: where both have one, theirs wins this first time.\nNo: this computer's win and go to them.", "ReaPersona: " .. a.name, 4) == 6
            end
            core.advanced_join(a.id, theirs)
            if core.sync_folder() ~= "" then sync_step(true) end
          end
        end
        ImGui.EndDisabled(ctx)
      end
      if core.advanced_on("packages") then
        local miss = core.packages_missing()
        if #miss > 0 then
          ImGui.TextColored(ctx, C.YELLOW, #miss .. " ReaPack package" .. (#miss == 1 and "" or "s") .. " your other computers have aren't here yet.")
          if ImGui.IsItemHovered(ctx) then
            local names = {}
            for i, m in ipairs(miss) do if i > 25 then names[#names + 1] = "..."; break end names[#names + 1] = m.key:gsub("|", " / ") end
            ImGui.SetTooltip(ctx, table.concat(names, "\n"))
          end
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Install them##instmiss") then
            local n, why = core.install_missing()
            say(n and (n .. " package" .. (n == 1 and "" or "s") .. " handed to ReaPack: it installs this system's versions and shows what it did.") or ("Not installed: " .. tostring(why)))
          end
        end
      end
    end
    card_end()
  end
  if sec == "personas" and card("set aspects") then
    heading("What a persona may change")
    muted("Switch off what you'd rather keep as it is, whatever persona you use. Takes effect the next time you use a persona; what a persona already changed is still put back when you switch away.")
    for i, a in ipairs(core.ASPECTS) do
      if setting_row("##asp" .. i, a[2], core.aspect_on(a[1])) then reaper.SetExtState(SECTION, "aspect " .. a[1], core.aspect_on(a[1]) and "0" or "1", true) end
    end
    card_end()
  end
  if sec == "personas" and card("set actions") then
    heading("REAPER's Actions list")
    muted("ReaPersona opens from Extensions > ReaPersona, View > ReaPersona or the Actions list. Switching persona from a key or a toolbar button needs its actions there: a key or button already using one keeps it either way.")
    if setting_row("##allact", "Every ReaPersona action in REAPER's Actions list", core.all_actions()) then
      reaper.SetExtState(SECTION, "all actions", core.all_actions() and "0" or "1", true)
      core.ensure_scripts()
    end
    card_end()
  end
  if sec == "personas" and card("set projects") then
    heading("A persona per project")
    muted("Give a project its persona with 'Use for this project' on the persona's page; it's saved in the project. With this on, opening that project or switching to its tab switches persona, and a persona's REAPER settings (the REAPER tab, In my persona) make each project's workflow its own.")
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
  if sec == "scroll" and card("set playback") then
    heading("Smooth playhead, scrolling and zoom")
    muted("Most DAWs glide their playhead and zoom smoothly; REAPER steps. These two extensions add that. The DAW personas that feel that way recommend them.")
    for key, x in pairs(core.EXTENSIONS) do
      local state = core.ext_here(key) and core.extension_state(key) -- (one that can't run on this system isn't offered: review round 1)
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
  if sec == "look" and card("set look") then
    heading("ReaPersona's look")
    if setting_row("##advset", "Show everything: also Mouse & trackpad, Layout, Project, REAPER's options, and adjusting and building themes", reaper.GetExtState(SECTION, "advanced") ~= "0",
        "Off, ReaPersona shows its main tabs only (Home, Personas, Themes, Colours, Shortcuts, Settings, Help); while you make or edit a persona every tab shows. The same switch is at the bottom of the list on the left (in the drop-down on a narrow window).") then
      set_advanced(reaper.GetExtState(SECTION, "advanced") == "0")
    end
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
  if sec == "look" and card("set access") then -- (5.14: ReaImGui's window is pixels to a screen reader; the menu is REAPER's own)
    heading("Screen readers")
    muted("A screen reader (NVDA, JAWS or VoiceOver, through OSARA) can't read this window. ReaPersona's menu it can: REAPER's own menu with the main tasks, and the results in message boxes.")
    if setting_row("##srmenu", "Open the menu instead of this window", reaper.GetExtState(SECTION, "screen reader") == "1",
        "ReaPersona's action then opens the menu. The action 'ReaPersona - screen-reader menu' opens it either way.") then
      reaper.SetExtState(SECTION, "screen reader", reaper.GetExtState(SECTION, "screen reader") == "1" and "0" or "1", true)
    end
    card_end()
  end
  if sec == "updates" and card("set update") then -- (5.23: like StudioSync's Update)
    heading("Updates")
    local function check(max_s)
      upd.info, upd.err = core.check_update(max_s)
      upd.at = os.time()
    end
    local seen = tonumber(reaper.GetExtState(SECTION, "update seen"):match("^(%d+)") or "")
    if not upd.at and (not seen or os.time() - seen > 86400) then check(3) end -- (once a day, when Updates opens; 3 s at most, as REAPER waits: review 2026-11-18)
    ImGui.Text(ctx, "ReaPersona " .. core.version())
    if upd.job then -- (downloading in the background)
      local n, why = core.update_poll(upd.job)
      if n then upd.done = "Updated to " .. upd.job.info.version .. " (" .. n .. " files): close this window and open ReaPersona again to use it."; upd.job = nil; say(upd.done)
      elseif n == false then upd.err, upd.job = why, nil
      else muted("Downloading " .. upd.job.info.version .. "...") end
    end
    if upd.done then
      ImGui.TextColored(ctx, C.YELLOW, upd.done)
    elseif upd.info and upd.info.newer and not upd.job then
      ImGui.TextColored(ctx, C.YELLOW, "ReaPersona " .. upd.info.version .. " is ready.")
      if primary("Update to " .. upd.info.version) then
        local r, why = core.update_start(upd.info)
        if r == "reapack" then upd.done = "ReaPack is updating ReaPersona: when it's done, close this window and open ReaPersona again."; say(upd.done)
        elseif r then upd.job, upd.err = r, nil
        else upd.err = why end
      end
    elseif upd.info then
      muted("Up to date (" .. "latest release " .. upd.info.version .. ", looked " .. os.date("%H:%M", upd.at) .. ").")
    end
    if upd.err then ImGui.TextColored(ctx, C.YELLOW, upd.err) end
    if ImGui.Button(ctx, "Check now##upd") then check(15); upd.done = nil end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "What's new##upd") then core.open_url("https://github.com/FmsJay/ReaPersona/blob/main/CHANGELOG.md") end
    card_end()
  end
  if sec == "remove" and card("set remove") then -- (removed with ReaPack alone, its startup block, actions and settings stayed behind. Review, 5.9.4)
    heading("Remove ReaPersona")
    muted("Puts My REAPER back, then takes out the startup line, ReaPersona's actions and its settings, and (REAPER restarting) its shortcut layers and toolbars. Your personas, presets and themes stay in their files. Then uninstall it in ReaPack.")
    ImGui.BeginDisabled(ctx, removing ~= nil)
    if ImGui.Button(ctx, "Remove ReaPersona...") and reaper.MB("Take ReaPersona out of REAPER?\n\n" ..
        "- My REAPER comes back: your own shortcuts, theme, layout and settings\n- the startup line, ReaPersona's actions and its settings go\n" ..
        "- REAPER closes (it asks first if anything is unsaved), the shortcut layers and toolbars come out of your keymap (backed up first), and REAPER opens again\n" ..
        "\nYour personas, presets and themes stay in their files. Last, uninstall ReaPersona in Extensions > ReaPack > Browse packages.", "ReaPersona: remove", 4) == 6 then
      reaper.SetExtState(SECTION, "follow projects", "0", true) -- (the project-following script stops)
      use(core.by_id("my_reaper") or styles[1])
      removing = true -- (the rest once My REAPER's windows are back: loop)
    end
    ImGui.EndDisabled(ctx)
    card_end()
  end
end
