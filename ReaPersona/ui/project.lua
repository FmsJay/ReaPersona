-- ReaPersona's window: Project defaults and the REAPER tab.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 3138-3330.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
function project_editor(b)
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  local sr = tonumber(b.srate) or 0
  if ImGui.BeginCombo(ctx, "Sample rate##psr", sr > 0 and (core.khz(sr)) or "Leave as it is") then
    if ImGui.Selectable(ctx, "Leave as it is", sr == 0) then b.srate = 0 end
    for _, r in ipairs(core.SRATES) do if ImGui.Selectable(ctx, core.khz(r), sr == r) then b.srate = r end end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "A new (still empty) project gets this sample rate, and the audio device follows it when it can.")
  local has = type(b.tracks) == "string" and b.tracks ~= ""
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Starter tracks: " .. (has and ((b.tracks_name or "") ~= "" and b.tracks_name or "yes") or "none"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Use the selected tracks##ptr") then
    local text, n = core.selected_tracks_text()
    if n > 0 then
      b.tracks, b.tracks_name = text, n .. " track" .. (n == 1 and "" or "s") .. " from " .. (reaper.GetProjectName(0, "") ~= "" and reaper.GetProjectName(0, "") or "this project")
      say("The persona keeps " .. n .. " track" .. (n == 1 and "" or "s") .. " (their FX, routing and settings, not their items).")
    else say("No tracks in this project to take.") end
  end
  ImGui.SetItemTooltip(ctx, "The selected tracks (or every track, with none selected), with their FX, sends and settings but not their items, go into every new project that uses this persona.")
  if has then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "None##ptr0") then b.tracks, b.tracks_name = "", "" end end
  local tp = type(b.template) == "string" and b.template ~= ""
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Project template: " .. (tp and (b.template_name or "yes") or "none"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Use this whole project##ptpl") then
    local pj = core.project_now(true)
    if pj.template then b.template, b.template_name = pj.template, pj.template_name; say("The persona keeps " .. pj.template_name .. ".")
    else say("Couldn't read this project.") end
  end
  ImGui.SetItemTooltip(ctx, "This project as the starting point for new ones: every track with its FX, routing and folders, the sample rate, recording format, render settings, tempo, markers and regions. Not its audio or MIDI.")
  if tp then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "None##ptpl0") then b.template, b.template_name = nil, nil end end
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  local w = tonumber(b.wset) or 0
  if ImGui.BeginCombo(ctx, "Window set##pws", w > 0 and ("#" .. w) or "Leave as it is") then
    if ImGui.Selectable(ctx, "Leave as it is", w == 0) then b.wset = 0 end
    for n = 1, 10 do if ImGui.Selectable(ctx, "#" .. n, w == n) then b.wset = n end end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "A layout you saved in REAPER (View > Screensets/layouts > Windows), loaded each time this persona is used.")
  -- (5.33: a new project's tempo, time signature and grid)
  local on = (tonumber(b.bpm) or 0) > 0
  local ch, v = ImGui.Checkbox(ctx, "Tempo##pbpmon", on)
  if ch then b.bpm = v and 120 or nil end
  if on then
    ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 120 * UI)
    local c2, nv = ImGui.DragDouble(ctx, "BPM##pbpm", tonumber(b.bpm) or 120, 0.5, 20, 400, "%.1f")
    if c2 then b.bpm = math.max(20, math.min(400, nv)) end
  end
  ImGui.SetItemTooltip(ctx, "A new (still empty) project starts at this tempo.")
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  local ts = (tonumber(b.ts_num) or 0) > 0 and (b.ts_num .. "/" .. b.ts_den) or "Leave as it is"
  if ImGui.BeginCombo(ctx, "Time signature##pts", ts) then
    if ImGui.Selectable(ctx, "Leave as it is", ts == "Leave as it is") then b.ts_num, b.ts_den = nil, nil end
    for _, x in ipairs({ { 4, 4 }, { 3, 4 }, { 2, 4 }, { 5, 4 }, { 6, 8 }, { 7, 8 }, { 9, 8 }, { 12, 8 }, { 2, 2 } }) do
      if ImGui.Selectable(ctx, x[1] .. "/" .. x[2], ts == x[1] .. "/" .. x[2]) then b.ts_num, b.ts_den = x[1], x[2] end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetNextItemWidth(ctx, 170 * UI)
  if ImGui.BeginCombo(ctx, "Grid##pgrid", (tonumber(b.grid) or 0) > 0 and core.grid_name(b.grid) or "Leave as it is") then
    if ImGui.Selectable(ctx, "Leave as it is", not b.grid) then b.grid = nil end
    for _, g in ipairs(core.GRIDS) do if ImGui.Selectable(ctx, g[2] .. "##g" .. g[2], b.grid == g[1]) then b.grid = g[1] end end
    ImGui.EndCombo(ctx)
  end
  -- (5.35: render settings, taken from the project in front)
  local r = core.safe_render(b.render)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, "Render settings: " .. (r and core.render_words(r) or "leave as they are"))
  ImGui.SameLine(ctx)
  if ImGui.SmallButton(ctx, "Use this project's##prender") then
    b.render = core.render_now(0)
    say(b.render and ("Render settings in your persona: " .. core.render_words(b.render) .. ".") or "This project's render settings couldn't be read.")
  end
  ImGui.SetItemTooltip(ctx, "The format, sample rate, channels and file name pattern of the project in front (File > Render), for each new project. Not the output folder: that's this computer's.")
  if r then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave as they are##prenderx") then b.render = nil end end
end
function project_page()
  if card("project top") then
    heading("Project defaults")
    muted("With this persona, a new (still empty) project gets a sample rate, tempo, time signature and grid, starter tracks or a whole project template, and a window set. A persona with a project part is also a workflow you can put on top of any persona. The click, count-in and pre-roll are REAPER options: REAPER > Recording and Playback.")
    if ImGui.SmallButton(ctx, "Recording options##prec") then go("R_recording") end
    ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Playback options##pplay") then go("R_playback") end
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Start from:")
    for _, w in ipairs(core.WORKFLOWS) do
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, w.name .. "##wf") then
        for _, b in ipairs(w.blocks()) do core.draft_add(bld.blocks, b) end
        bld.active = true
        if bld.name == "" then bld.name = w.name end
        say(w.name .. "'s project and settings are in your persona.")
      end
      ImGui.SetItemTooltip(ctx, w.tip)
    end
    local b = core.draft_get(bld.blocks, "project")
    ImGui.Dummy(ctx, 0, 4)
    ImGui.Indent(ctx, IND * UI)
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 240 * UI)
    if ImGui.BeginCombo(ctx, "##projfrom", "a persona of yours") then
      for _, st in ipairs(sources(function(s) return s.project ~= nil end)) do
        if ImGui.Selectable(ctx, st.name .. "##pf" .. st.id) then
          local nb = core.new_block("project")
          for k, v in pairs(st.project) do nb[k] = v end
          core.draft_add(bld.blocks, nb); bld.active = true; b = nb
        end
      end
      ImGui.EndCombo(ctx)
    end
    if b then
      project_editor(b)
      if ImGui.SmallButton(ctx, "No project part##pnone") then core.draft_clear(bld.blocks, "project") end
    elseif ImGui.Button(ctx, "Set what a new project gets") then core.draft_add(bld.blocks, core.new_block("project")); bld.active = true end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end

-- REAPER's defaults: a tab per setting group, live. A group can go into the persona being made, and follows what's set here.
function tweaks_page(only) -- (5.33: REAPER's defaults, one group per tab; only = that group's id)
  if card("tw top") then
    heading("REAPER's defaults")
    muted("REAPER's own options and SWS's. Each change happens now and REAPER keeps it. A persona that sets one puts yours back when you switch away; In my persona makes a group, as you've set it here, part of the persona you're making.")
    if ImGui.Button(ctx, "REAPER's Preferences window") then reaper.Main_OnCommand(40016, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Toolbars and menus") then reaper.Main_OnCommand(40905, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Actions and shortcuts") then reaper.Main_OnCommand(40605, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Mouse modifiers") then reaper.Main_OnCommand(41356, 0) end
    ImGui.SameLine(ctx); if ImGui.Button(ctx, "Theme adjuster") then reaper.Main_OnCommand(42234, 0) end
    card_end()
  end
  if card("tw from") then
    heading("Your persona's REAPER settings", 16)
    muted("Tick In my persona on a group below and the persona you're making sets it as you have it here (and follows what you change).")
    ImGui.Indent(ctx, IND * UI)
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 240 * UI)
    if ImGui.BeginCombo(ctx, "##twfrom", "a persona of yours") then
      for _, st in ipairs(sources(function(s) for _, b in ipairs(s.blocks or {}) do if b.kind == "settings" then return true end end end)) do
        if ImGui.Selectable(ctx, st.name .. "##twf" .. st.id) then
          for _, b in ipairs(st.blocks) do if b.kind == "settings" then core.draft_add(bld.blocks, core.json_decode(core.json_encode(b))) end end
          bld.active = true; say(st.name .. "'s REAPER settings are in your persona (they don't change REAPER until it's used).")
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
  for gi, g in ipairs(core.SETTING_GROUPS) do
    if (not only or g.id == only) and card("tw " .. g.id) then
      heading(g.name, 16)
      ImGui.SameLine(ctx)
      local inb = core.draft_get(bld.blocks, "settings " .. g.id)
      local ch, v = ImGui.Checkbox(ctx, "In my persona##twb" .. gi, inb ~= nil)
      if ch then if v then in_persona(core.new_block("settings", g.id), g.name .. ", as you set it here,") else core.draft_clear(bld.blocks, "settings " .. g.id) end end
      ImGui.SetItemTooltip(ctx, "The persona you're making sets these as they are here; change them here and it follows.")
      local touched = false -- (review 2026-11-18: it follows what you change here, not REAPER as it is on every frame: that undid Load from, and
      -- editing a saved persona that isn't in use took your live settings into it)
      for n, it in ipairs(g.items) do
        ImGui.PushID(ctx, gi * 100 + n)
        if type(it[1]) == "table" then
          local now = core.setting_now(it)
          ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, it[2])
          if it.tip then ImGui.SetItemTooltip(ctx, it.tip) end
          for k, o in ipairs(it[3]) do
            ImGui.SameLine(ctx)
            if ImGui.RadioButton(ctx, o .. "##ch" .. k, now == k) and now ~= k then reaper.Main_OnCommand(core.cmd_id(it[1][k]), 0); touched = n end
          end
        else
          local id = core.cmd_id(it[1])
          if id == 0 then
            ImGui.BeginDisabled(ctx); setting_row("##tw", it[2] .. "  (needs SWS)", false, it.tip); ImGui.EndDisabled(ctx)
          elseif setting_row("##tw", it[2], reaper.GetToggleCommandState(id) == 1, it.tip) then
            reaper.Main_OnCommand(id, 0); touched = n
          end
        end
        ImGui.PopID(ctx)
      end
      if inb and touched then inb.values = type(inb.values) == "table" and inb.values or {}; inb.values[touched] = core.new_block("settings", g.id).values[touched] end -- (that one only: review 2)
      if g.id == "colours" and core.cmd_id("_SWSAUTOCOLOR_APPLY") ~= 0 then
        ImGui.Dummy(ctx, 0, 2)
        if ImGui.Button(ctx, "Colour the tracks now") then reaper.Main_OnCommand(core.cmd_id("_SWSAUTOCOLOR_APPLY"), 0); say("Tracks coloured by SWS's rules.") end
        ImGui.SetItemTooltip(ctx, "Applies SWS's auto-colour rules to every track now.")
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Colour and icon rules...") then reaper.Main_OnCommand(core.cmd_id("_SWSAUTOCOLOR_OPEN"), 0) end
        ImGui.SetItemTooltip(ctx, "SWS's window for the rules: which track names get which colour, icon and layout.")
      end
      card_end()
    end
  end
end
