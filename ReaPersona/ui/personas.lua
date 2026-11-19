-- ReaPersona's window: workflows, persona cards and pages: DAWs, Themes, Your personas, Favourites.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 344-999.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
-- A workflow over the persona in use (5.16): picked here, on the Personas page, or from the screen-reader menu.
function pick_workflow(id)
  local ok, why = core.set_workflow(id)
  if not ok then return say("Not changed: " .. tostring(why)) end
  local w, cur, setup = core.current_workflow(), core.current(), core.last_project_setup or {}
  say((w and (w.name .. " is on top of " .. cur.name) or ("No workflow: " .. cur.name .. " on its own")) ..
    (#setup > 0 and (", and this project has its " .. table.concat(setup, ", ")) or "") .. ".")
end
function workflow_new_project(w) -- a new project set up by the workflow in use, over the persona in use
  if not core.fresh_project(0) then reaper.Main_OnCommand(41929, 0) end -- (a new tab, without the default template's tracks)
  local done = core.apply_project(core.layered(core.current()))
  say("A new project with " .. w.name .. (#done > 0 and (": " .. table.concat(done, ", ")) or "") .. ".")
end
function workflow_keep_inputs(w)
  local n = core.keep_inputs(w.id)
  say("Kept the inputs of this project's " .. n .. " track" .. (n == 1 and "" or "s") .. ": new projects with " .. w.name .. " on this computer get them. Your other computers keep their own.")
end
function workflow_row()
  local w = core.current_workflow()
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Workflow on top:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 230 * UI)
  if ImGui.BeginCombo(ctx, "##workflow", w and w.name or "None") then
    if ImGui.Selectable(ctx, "None: the persona on its own", not w) and w then pick_workflow("") end
    local mine = false
    for _, x in ipairs(core.workflow_list()) do
      if x.mine and not mine then ImGui.Separator(ctx); mine = true end
      local on = w and w.id == x.id
      if ImGui.Selectable(ctx, x.name .. "##wf" .. x.id, on) and not on then pick_workflow(x.id) end
      if x.tip then ImGui.SetItemTooltip(ctx, x.tip) end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "A kind of session over whichever persona is in use: its REAPER settings, and what a new, empty project gets (sample rate, starter tracks or a whole template). The persona keeps its keys, theme and layout. Your personas with a project part are listed too.")
  if w and w.project then
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "New project with " .. w.name) then workflow_new_project(w) end
    ImGui.SetItemTooltip(ctx, "Opens a new project tab set up by " .. w.name .. " (a new project from REAPER's File menu or its key gets it too, while it's on).")
    if reaper.CountTracks(0) > 0 then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Keep these inputs##wf") then workflow_keep_inputs(w) end
      ImGui.SetItemTooltip(ctx, "Each computer's interface numbers its inputs its own way. Set the tracks' inputs here once, press this, and new projects with " .. w.name .. " get them on this computer.")
    end
  end
end

-- A star (5.27: favourites), drawn, so it doesn't depend on the font having one.
function draw_star(dl, cx, cy, r, filled, col)
  local p = {}
  for i = 0, 9 do local a = -math.pi / 2 + i * math.pi / 5; local rr = i % 2 == 0 and r or r * 0.45; p[i] = { cx + rr * math.cos(a), cy + rr * math.sin(a) } end
  if filled then
    for i = 1, 9, 2 do ImGui.DrawList_PathLineTo(dl, p[i][1], p[i][2]) end
    ImGui.DrawList_PathFillConvex(dl, col)
    for i = 0, 8, 2 do local a, b = p[(i + 9) % 10], p[i + 1]; ImGui.DrawList_AddTriangleFilled(dl, p[i][1], p[i][2], a[1], a[2], b[1], b[2], col) end
  else
    for i = 0, 9 do ImGui.DrawList_PathLineTo(dl, p[i][1], p[i][2]) end
    ImGui.DrawList_PathStroke(dl, col, ImGui.DrawFlags_Closed, 1.5)
  end
end
-- One picture card in the grid: click shows it, double-click uses it; the star (top left) adds it to your favourites or takes it off.
function style_card(st, w, sel, alt)
  local dl = ImGui.GetWindowDrawList(ctx)
  local x, y = ImGui.GetCursorScreenPos(ctx)
  local iw = w - 16
  local ih = math.floor(iw * 0.56)
  local h = 8 + ih + 52 * UI -- (the name and its line grow with Settings > text size: round 3)
  local mx, my = ImGui.GetMousePos(ctx)
  local on_star = mx >= x + 10 and mx <= x + 38 and my >= y + 10 and my <= y + 38
  local fav = core.is_favourite(st.id)
  if ImGui.InvisibleButton(ctx, "card" .. st.id, w, h) then
    if on_star then core.set_favourite(st.id, not fav); say(st.name .. (fav and " is off your favourites." or " is in your favourites (Personas > Favourites)."))
    else selected = st.id end
  end
  local hov = ImGui.IsItemHovered(ctx)
  if hov and ImGui.IsMouseDoubleClicked(ctx, 0) then use(st) end
  ImGui.SetItemTooltip(ctx, (hov and on_star) and (fav and "Take it off your favourites" or "Add it to your favourites") or "Click to see it, double-click to use it. The star adds it to your favourites.")
  local col, picked, on = accent_of(st), st.id == sel.id, in_use(st, alt)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, hov and C.CARD_HOVER or C.CARD, 10)
  if picked then ImGui.DrawList_AddRect(dl, x + 1, y + 1, x + w - 1, y + h - 1, solid(col), 10, 0, 2) end
  local img = preview(st)
  if img then
    local sw, sh = ImGui.Image_GetSize(img)
    local v1 = math.min(1, (ih / iw) / math.max(sh / math.max(sw, 1), 0.01)) -- (fill the width, crop from the top down)
    ImGui.DrawList_AddImageRounded(dl, img, x + 8, y + 8, x + 8 + iw, y + 8 + ih, 0, 0, 1, v1, 0xFFFFFFFF, 6)
  else
    ImGui.DrawList_AddRectFilled(dl, x + 8, y + 8, x + 8 + iw, y + 8 + ih, solid(mix(P.card, col, 0.35)), 6)
  end
  ImGui.DrawList_AddCircleFilled(dl, x + 16, y + 8 + ih + 17 * UI, 4.5 * UI, solid(col))
  ImGui.DrawList_AddTextEx(dl, bold, 15 * UI, x + 26, y + 8 + ih + 8 * UI, C.TEXT, st.short or st.name)
  local sub = st.preset and ("yours, on " .. (core.by_id(st.base) or { name = "" }).name) or st.kind == "theme" and "theme, with your keys"
    or st.id == "my_reaper" and "your own setup" or st.id == "base_reaper" and "REAPER as it ships" or core.factory[st.id] and "your version"
    or st.kind == "built" and "built by you" or st.user and "yours"
    or "keys, theme and layout"
  ImGui.DrawList_AddTextEx(dl, font, 13 * UI, x + 26, y + 8 + ih + 27 * UI, C.MUTED, sub)
  if fav or hov then
    ImGui.DrawList_AddCircleFilled(dl, x + 24, y + 24, 13, 0x000000A0)
    draw_star(dl, x + 24, y + 24.5, 9, fav, fav and 0xFFC83CFF or (on_star and 0xFFFFFFFF or 0xFFFFFFB0))
  end
  if on then
    local tw, th = ImGui.CalcTextSize(ctx, "In use")
    local px, py = x + w - 8 - tw - 16, y + 14
    ImGui.DrawList_AddRectFilled(dl, px, py, px + tw + 16, py + th + 6, solid(col), (th + 6) / 2)
    ImGui.DrawList_AddText(dl, px + 8, py + 3, on_colour(col), "In use")
  end
end

-- Rows of things with an optional key and an Open button, as a table so long text wraps beside them.
function rows(id, list, show_open)
  if not list or #list == 0 then return end
  if ImGui.BeginTable(ctx, id, 3, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
    ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "key", ImGui.TableColumnFlags_WidthFixed)
    ImGui.TableSetupColumn(ctx, "open", ImGui.TableColumnFlags_WidthFixed)
    for i, x in ipairs(list) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx); ImGui.PushTextWrapPos(ctx, 0); ImGui.Text(ctx, x[1]); ImGui.PopTextWrapPos(ctx)
      ImGui.TableNextColumn(ctx); if x[3] then keycap(x[3]) end
      ImGui.TableNextColumn(ctx)
      if show_open and x[2] then
        local tool = type(x[2]) == "string" and core.tool_for(x[2])
        if tool and core.cmd_id(x[2]) == 0 then
          if ImGui.SmallButton(ctx, "Get it##" .. id .. i) then core.get_tool(tool) end
          ImGui.SetItemTooltip(ctx, "Needs " .. tool.name .. ": " .. tool.how)
        elseif ImGui.SmallButton(ctx, "Open##" .. id .. i) then open_extra(x[2]) end
      end
    end
    ImGui.EndTable(ctx)
  end
end

function feel_rows(st)
  if not st.feel or #st.feel == 0 then return end
  if ImGui.BeginTable(ctx, "feel", 2, ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_RowBg) then
    ImGui.TableSetupColumn(ctx, "kind", ImGui.TableColumnFlags_WidthFixed, 72)
    ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
    for _, f in ipairs(st.feel) do
      ImGui.TableNextRow(ctx)
      ImGui.TableNextColumn(ctx)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.MUTED)
      ImGui.Text(ctx, f[1] == "mouse" and "Mouse" or f[1] == "switch" and "Toolbar" or f[1] == "dock" and "Window" or (f[1] == "radio" and "Layout") or "Setting")
      ImGui.PopStyleColor(ctx)
      ImGui.TableNextColumn(ctx); ImGui.PushTextWrapPos(ctx, 0); ImGui.Text(ctx, f[#f]); ImGui.PopTextWrapPos(ctx)
    end
    ImGui.EndTable(ctx)
  end
end

function save_preset_prompt()
  local cur = core.current()
  if core.is_trial() then -- (a preview isn't a persona of its own: saved, it named one that's gone. Review 2026-11-19)
    return say("REAPER is showing the persona you're making: Save it from the bar at the top, or Go back there first to save what you had.")
  end
  local function taken(n)
    for _, list in ipairs({ styles, core.presets }) do for _, s in ipairs(list) do if s.name:lower() == n:lower() then return s end end end
  end
  -- (James, 2026-11-19: "you should be able to overwrite your 'my reaper' but old ones saved as backups. Can do this with the daws too but
  -- for those ones it would recommend the -alt". My REAPER and your setups are offered as themselves, saved over after asking, the one
  -- before kept under Earlier versions; anything else is offered as "<name> - alt")
  local suggest = cur.id == "my_reaper" and "My REAPER" or cur.preset and cur.name or core.custom_name(cur.name, "alt")
  local ok, name = reaper.GetUserInputs("Save as a persona", 1, "Name,extrawidth=160,separator=\n", suggest)
  name = ok and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
  if name == "" then return end
  local same, over = taken(name), nil
  if same and same.id == "my_reaper" then
    if reaper.MB("Save what you're using over My REAPER?\n\nIts theme, layout, mouse and settings become your look on every computer that syncs; its shortcuts stay your own keymap. " ..
        "The look it has now is kept: Earlier versions, on its page, puts it back.\n\n(For a second one instead, Cancel and give it another name, such as " .. core.custom_name("My REAPER", "alt") .. ".)",
        "ReaPersona: save over", 1) ~= 1 then return end
    local look, why = core.save_my_look(true)
    return say(look and ("Saved over My REAPER: " .. core.look_label(look) .. ". Earlier versions, on its page, puts the one before back.") or ("Not saved: " .. tostring(why)))
  elseif same and same.preset then
    if reaper.MB("Save over " .. same.name .. "? The one there now is kept: Earlier versions, on its page, puts it back.", "ReaPersona: save over", 4) ~= 6 then return end
    name, over = same.name, same.id
  elseif same then
    local alt = core.custom_name(same.name, "alt")
    local why = core.is_daw(same) and (same.name .. " comes with ReaPersona. To change it itself, Edit it, change it on the tabs and pick it under Save over: the original stays, to put back.")
      or same.user and (same.name .. " is a persona you made on the tabs: to change it, Edit it there and Save changes (the one before is kept).")
      or (same.name .. " comes with ReaPersona and isn't saved over.")
    if reaper.MB(why .. "\n\nSave this as " .. alt .. " instead?", "ReaPersona: save", 1) ~= 1 then return end
    name = alt
  end
  local all = reaper.CountTracks(0)
  local wf = reaper.MB("Make " .. name .. " a workflow too?\n\nYes: a new, empty project with it starts as this one does: its " .. all .. " track" .. (all == 1 and "" or "s") ..
    " with their FX, routing and folders (not their audio or MIDI), its sample rate, recording format, render settings, tempo, markers and regions." ..
    "\nNo: just the shortcuts, theme, layout and settings, as now.", "ReaPersona: save", 3)
  if wf == 2 then return end
  local st, why = core.save_preset(name, wf == 6, over) -- (yes: the whole project as its template, 5.13)
  if not st then return say("Not saved: " .. tostring(why)) end
  selected = st.id
  say((over and "Saved over " or "Saved ") .. name .. (over and " (Earlier versions, on its page, puts the one before back)" or ": it's in your list") ..
    (wf == 6 and ", and new projects with it start like this one." or "."))
end

-- The grid of cards (or a list of chips, for a narrow window). Double-click uses one.
function chooser(list, sel, alt)
  local as_list = reaper.GetExtState(SECTION, "view") == "list"
  if as_list then
    local right = ImGui.GetCursorPosX(ctx) + ImGui.GetContentRegionAvail(ctx)
    for n, st in ipairs(list) do
      local label = "  " .. st.name .. (in_use(st, alt) and "  (in use)" or "")
      local w = ImGui.CalcTextSize(ctx, label) + 28
      if n > 1 then ImGui.SameLine(ctx, 0, 8); if ImGui.GetCursorPosX(ctx) + w > right then ImGui.NewLine(ctx) end end
      local col = accent_of(st)
      ImGui.PushStyleColor(ctx, ImGui.Col_Button, st.id == sel.id and solid(mix(P.card, col, 0.45)) or C.CARD)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      if ImGui.Button(ctx, label .. "##chip" .. st.id, w, 0) then selected = st.id end
      if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then use(st) end
      ImGui.PopStyleColor(ctx)
      ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), x + 12, y + ImGui.GetFrameHeight(ctx) / 2, 4.5, solid(col))
    end
    return
  end
  local avail = ImGui.GetContentRegionAvail(ctx)
  local per_row = math.max(1, math.min(#list, math.floor((avail + 12) / 190)))
  local w = math.floor((avail - 12 * (per_row - 1)) / per_row)
  for n, st in ipairs(list) do
    if (n - 1) % per_row ~= 0 then ImGui.SameLine(ctx, 0, 12) end
    style_card(st, math.min(w, 280), sel, alt)
  end
end
function view_switch()
  local as_list = reaper.GetExtState(SECTION, "view") == "list"
  if ImGui.SmallButton(ctx, as_list and "Show pictures" or "Show as a list") then reaper.SetExtState(SECTION, "view", as_list and "" or "list", true) end
end

-- The one picked: what it is, use it, and everything it does.
function detail(sel, alt)
  local col = accent_of(sel)
  local on = in_use(sel, alt)
  if card("detail") then
    local dl = ImGui.GetWindowDrawList(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddCircleFilled(dl, x + 7, y + 13, 7, solid(col))
    ImGui.SetCursorScreenPos(ctx, x + 22, y)
    heading(sel.name, 24)
    if on then ImGui.SameLine(ctx, 0, 12); pill("In use", solid(col)) end
    muted(sel.description or "")
    if core.IS_LINUX then -- (Linux: keys the desktop keeps, GNOME and KDE alike: review round 2)
      local taken = core.taken_here(sel.keys)
      if #taken > 0 then muted("Your desktop may keep these for itself, so they don't reach REAPER unless you change them in its keyboard settings: " .. table.concat(taken, ", ") .. ".") end
    end
    if MOD == "Cmd" then -- (a Mac: keys macOS keeps, which never reach REAPER)
      local taken = core.mac_taken(sel.keys)
      if #taken > 0 then muted("macOS keeps these for itself, so they don't reach REAPER unless you turn them off in System Settings > Keyboard > Keyboard Shortcuts: " .. table.concat(taken, ", ") .. ".") end
    end
    if core.needs_layer(sel) then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, "Its shortcuts get a shortcut layer the first time you use it here (" .. (FLATPAK and "you import them; the steps say how" or "REAPER restarts once") .. "). REAPER has 16 layers, so ReaPersona gives them only to the personas you use: your favourites, the one in use and your own.")
      ImGui.PopStyleColor(ctx)
    elseif (sel.alt or 0) > 0 and not installed[sel.alt] then
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, "Its shortcuts aren't installed yet: " .. INSTALL_WHERE .. ".")
      ImGui.PopStyleColor(ctx)
    end
    for i, s in ipairs(on and core.starts_missing or {}) do -- (scripts it starts with REAPER that aren't installed here, 5.24)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
      ImGui.TextWrapped(ctx, s[1] .. " starts with REAPER in this persona, and isn't installed here (" .. s[3].pkg .. ", from " .. s[3].repo .. ").")
      ImGui.PopStyleColor(ctx)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Get it##start" .. i) then local why = core.get_tool({ repos = { { s[3].repo, s[3].url } }, filter = s[3].pkg }); if why then say(why) end end
      ImGui.SetItemTooltip(ctx, "Adds " .. s[3].repo .. " (" .. s[3].url .. ") to ReaPack and shows " .. s[3].pkg .. "; installing is your click. Once it's installed, ReaPersona starts it with REAPER.")
    end
    for _, key in ipairs(sel.recommends or {}) do
      local x = core.EXTENSIONS[key]
      local state = x and core.ext_here(key) and core.extension_state(key)
      if state and state ~= "on" then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.YELLOW)
        ImGui.TextWrapped(ctx, "Recommended for " .. sel.name .. ": " .. x.name .. " (" .. x.why .. ")." .. (state == "restart" and " Installed: restart REAPER to load it." or ""))
        ImGui.PopStyleColor(ctx)
        if state == "missing" then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Install##rec" .. key) then install_ext(key) end end
      end
    end
    local tools, kms = sel.tools or {}, sel.keymaps or {}
    if (#tools > 0 or #kms > 0) and ImGui.CollapsingHeader(ctx, "More of " .. (sel.short or sel.name) .. " in REAPER##more") then
      for i, t in ipairs(tools) do -- (other people's tools: "Get it" adds their ReaPack repository and opens the browser at it)
        if ImGui.SmallButton(ctx, "Get it##tool" .. i) then local why = core.get_tool(t); if why then say(why) end end
        ImGui.SetItemTooltip(ctx, t.repos and ("Adds " .. t.repos[1][1] .. " to ReaPack and shows the package; installing is your click.") or ("Opens " .. tostring(t.url)))
        ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, t.name .. ": " .. t["for"])
      end
      for i, k in ipairs(kms) do
        if ImGui.SmallButton(ctx, "Open##km" .. i) then core.open_url(k[2]) end
        ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "Keymap: " .. k[1] .. " (drop the file on this window to make it a persona)")
      end
    end
    ImGui.Dummy(ctx, 0, 2)
    ImGui.BeginDisabled(ctx, on)
    if primary(on and "In use" or ("Use " .. sel.name), col) then use(sel) end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cheat sheet") then local p, why = core.cheat_sheet(sel); if p then core.open_url(p) else say(why) end end
    ImGui.SetItemTooltip(ctx, "Every key, setting and feature of this persona on one page, laid out for printing.")
    if sel.id == "my_reaper" then -- (your look on every computer, 5.21)
      ImGui.SameLine(ctx)
      ImGui.BeginDisabled(ctx, not on)
      if ImGui.Button(ctx, "Use this look on all my computers") then
        local look, why = core.save_my_look()
        say(look and ("Saved: " .. core.look_label(look) .. ". Your other computers take it at their next sync (or in a setup file you export).") or why)
      end
      ImGui.EndDisabled(ctx)
      ImGui.SetItemTooltip(ctx, "Keeps this computer's theme, transport and mixer places, docked windows, snap, ripple, mouse drags and the scripts REAPER starts with (Chordbox, adaptive grid...) as your look. My REAPER uses it on every computer you sync with, and every persona goes back to it. Press it again after you change your look.")
      local look = core.my_look()
      if look then
        muted("Your look: " .. core.look_label(look))
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, "Forget##look") then core.forget_my_look(); say("My REAPER is each computer's own setup again.") end
      end
    end
    local tpl = here .. "/templates/" .. (sel.preset and sel.base or sel.id) .. ".RPP"
    if reaper.file_exists(tpl) then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New project like " .. (sel.short or sel.name)) then
        reaper.Main_OnCommand(40859, 0) -- (a new tab, so nothing open is replaced)
        reaper.Main_openProject("template:" .. tpl)
      end
      ImGui.SetItemTooltip(ctx, "A new project with the tracks " .. (sel.short or sel.name) .. " starts you with, its buses and sends, using REAPER's own plugins.")
    end
    if sel.project then -- (a workflow)
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "New project with it") then
        -- (a new tab without the default template, whose tracks would stop the workflow's; this tab if it's still untouched. Review, 5.14)
        if not core.fresh_project(0) then reaper.Main_OnCommand(41929, 0) end
        if not on then use(sel)
        else
          local done = core.apply_project(sel)
          say("A new project with " .. sel.name .. (#done > 0 and (": " .. table.concat(done, ", ")) or "") .. ".")
        end
      end
      ImGui.SetItemTooltip(ctx, "Opens a new project tab set up by this workflow.")
      if on and reaper.CountTracks(0) > 0 then
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Keep these inputs on this computer") then
          local n = core.keep_inputs(sel.id)
          say("Kept the inputs of this project's " .. n .. " track" .. (n == 1 and "" or "s") .. ": new projects with " .. sel.name .. " on this computer get them. Your other computers keep their own.")
        end
        ImGui.SetItemTooltip(ctx, "Each computer's interface numbers its inputs its own way. Set the tracks' inputs here once, press this, and new projects with " .. sel.name .. " get them on this computer.")
      end
    end
    if (sel.alt or 0) > 0 and not sel.preset then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Share...") then
        if not reaper.JS_Dialog_BrowseForSaveFile then reaper.MB("Sharing needs js_ReaScriptAPI (Extensions > ReaPack > Browse packages).", "ReaPersona", 0) end
        local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Share " .. sel.name, reaper.GetResourcePath(), core.file_name(sel.name) .. ".reapersona.json", "ReaPersona persona (*.reapersona.json)\0*.reapersona.json\0\0")
        if ok == 1 and p ~= "" then reaper.MB(core.export(sel, p) and ("Saved " .. p .. ".\n\nAnyone with ReaPersona can import it.") or "Couldn't save it.", "ReaPersona", 0) end
      end
      ImGui.SetItemTooltip(ctx, "Save this persona (keys, MIDI keys, feel, and your theme version if you made one) as one file to give someone.")
    end
    if sel.preset then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Share...##preset") then
        if not reaper.JS_Dialog_BrowseForSaveFile then reaper.MB("Sharing needs js_ReaScriptAPI (Extensions > ReaPack > Browse packages).", "ReaPersona", 0) end
        local ok, p = reaper.JS_Dialog_BrowseForSaveFile and reaper.JS_Dialog_BrowseForSaveFile("Share " .. sel.name, reaper.GetResourcePath(), core.file_name(sel.name) .. ".reapersona-preset.json", "ReaPersona preset (*.json)\0*.json\0\0")
        if ok == 1 and p ~= "" then reaper.MB(core.export_preset(sel.id, p) and ("Saved " .. p .. ".\n\nAnyone with ReaPersona can drop it on the window.") or "Couldn't save it.", "ReaPersona", 0) end
      end
      ImGui.SetItemTooltip(ctx, "This persona as one file: drop it on someone's ReaPersona window (they need the DAW personas it's built on).")
    end
    local over = core.factory[sel.id] -- (yours saved over a DAW: deleting it puts the DAW back. 5.46)
    if over then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Put back the original") and reaper.MB("Put back " .. over.name .. " as it comes with ReaPersona?\n\nYour version is kept under Earlier versions, on its page, to put back." ..
          (core.sync_folder() ~= "" and " Your other computers go back to the original too (they sync)." or ""), "ReaPersona", 4) == 6 then
        local ok, why = core.delete_user_style(sel.id)
        say(ok and (over.name .. " is back as it comes with ReaPersona.") or ("Not put back: " .. tostring(why)))
      end
      ImGui.SetItemTooltip(ctx, "Your version replaced " .. over.name .. ". This brings the one that comes with ReaPersona back; yours is kept under Earlier versions.")
    elseif sel.preset or sel.user then
      ImGui.SameLine(ctx)
      ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.RED)
      local deps = ImGui.Button(ctx, "Delete persona") and (sel.preset and {} or core.presets_on(sel.id))
      if deps and reaper.MB("Delete " .. sel.name .. "? This can't be undone." .. (core.sync_folder() ~= "" and " It goes from your other computers too (they sync)." or "") ..
          (#deps > 0 and ("\n\nThese personas are built on it and will use My REAPER's keys instead:\n" .. table.concat(deps, "\n")) or ""), "ReaPersona", 4) == 6 then
        if on and sel.preset then core.use(core.by_id(sel.base or "my_reaper")) end
        local ok, why
        if sel.preset then ok, why = core.delete_preset(sel.id) else ok, why = core.delete_user_style(sel.id) end
        if ok then selected = sel.base or core.current().id else say("Not deleted: " .. tostring(why)) end
      end
      ImGui.PopStyleColor(ctx)
    end
    ImGui.Dummy(ctx, 0, 2)
    persona_row(sel)
    local fav = core.is_favourite(sel.id)
    if ImGui.Button(ctx, (fav and "In favourites" or "Add to favourites") .. "##favp") then core.set_favourite(sel.id, not fav) end
    ImGui.SetItemTooltip(ctx, fav and "Click to take it off Personas > Favourites." or "Puts it on Personas > Favourites (or click the star on its card).")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Edit##editp") then bld_load(sel) end
    ImGui.SetItemTooltip(ctx, sel.id == "my_reaper" and "Change your own layout, mouse, theme and colours on the tabs, then Save changes: it becomes your look on every computer that syncs (Earlier versions, on this page, puts the old one back)."
      or sel.blocks and "Change any part of it on the Shortcuts, Mouse, Layout, Themes, Colours, Project and REAPER tabs, then Save changes in the bar at the top."
      or "Start from " .. sel.name .. " and change any part on the tabs. It's saved as a persona of yours: " .. sel.name .. " stays as it is.")
    -- (a setup, and a DAW: its versions are yours saved over it, so one picked is saved over it again. 5.46)
    local vid = (sel.id == "my_reaper" or (sel.user and sel.kind == "built") or sel.preset or core.is_daw(sel)) and sel.id
    local vers = vid and core.versions(vid) or {}
    if #vers > 0 then -- (5.28: each save keeps the one before)
      ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 190 * UI)
      if ImGui.BeginCombo(ctx, "##vers", "Earlier versions (" .. #vers .. ")") then
        for i, v in ipairs(vers) do
          if ImGui.Selectable(ctx, tostring(v.saved) .. "##v" .. i) and reaper.MB("Put back " .. sel.name .. " as it was on " .. tostring(v.saved) .. "?\n\nThe version you have now is kept too, so you can come back to it.", "ReaPersona", 4) == 6 then
            if vid == "my_reaper" then core.save_look(v.data) elseif sel.preset then core.put_preset(v.data) else core.save_user_style(v.data); core.reload_users() end
            if reaper.GetExtState(SECTION, "style") == vid then core.use(core.by_id(vid)) end
            say(sel.name .. " is back as it was on " .. tostring(v.saved) .. ".")
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.SetItemTooltip(ctx, "Each time it's saved, the version before is kept (the newest 20, on this computer). Pick one to put it back.")
    end
    ImGui.SameLine(ctx)
    if core.project_persona() == sel.id then
      ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.GREEN, "This project uses " .. sel.name .. ".")
      ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Not for this project") then core.set_project_persona(nil) end
    elseif ImGui.Button(ctx, "Use for this project") then
      core.set_project_persona(sel.id)
      if not on then use(sel) end
      say(sel.name .. " is this project's persona (saved with the project)." .. (core.follow_on() and "" or " Turn on 'Switch persona with the project' in Settings to switch automatically."))
    end
    ImGui.SetItemTooltip(ctx, "Saved in the project file. With 'Switch persona with the project' on (Settings), opening this project or switching to its tab switches to this persona.")
    local vers, seen, mine = {}, {}, {}
    for _, th in ipairs(sel.themes or { sel.theme }) do if th and not seen[th] then vers[#vers + 1] = th; seen[th] = true end end
    for _, th in ipairs(core.forks(sel)) do if not seen[th] then vers[#vers + 1] = th; seen[th] = true; mine[th] = true end end
    local have, missing, can = {}, {}, 0
    for _, th in ipairs(vers) do
      if reaper.file_exists(themes_dir .. th) then have[#have + 1] = th
      elseif core.can_install_theme(th) or (core.CATALOG[th] and core.CATALOG[th].url and core.CATALOG[th].url:match("^https?:")) then
        missing[#missing + 1] = th
        if core.can_install_theme(th) then can = can + 1 end
      end
    end
    local rec = sel.theme
    if rec and not reaper.file_exists(themes_dir .. rec) and core.can_install_theme(rec) then
      ImGui.Dummy(ctx, 0, 2)
      if primary("Install " .. sel.name .. "'s recommended look: " .. rec:gsub("%.ReaperTheme%a*$", ""), col) then install_theme_ui(rec, sel, true) end
      local c = core.CATALOG[rec]
      ImGui.SetItemTooltip(ctx, "Downloads it" .. (c.by and (" (by " .. c.by .. ")") or "") .. " and takes it in, with its fonts, scripts and extras on your yes. " .. (c.note or ""))
    end
    if #have > 1 or #missing > 0 then
      ImGui.Dummy(ctx, 0, 2)
      heading("Theme versions", 15)
      muted("Click one to make it " .. sel.name .. "'s theme" .. (on and " (it goes on now)." or " (it goes on when you use " .. sel.name .. ").") ..
        " Add any theme to this list from Themes > Your themes > Add to; right-click one you added to take it off.")
      local cur = core.theme_for(sel)
      local x0 = ImGui.GetCursorScreenPos(ctx)
      local xend, pad, first = x0 + ImGui.GetContentRegionAvail(ctx), ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding), true
      for i, th in ipairs(have) do
        local nice = th:gsub("%.ReaperTheme%a*$", ""):gsub("^ReaPersona %- (.*)$", "ReaPersona's %1")
        local w = ImGui.CalcTextSize(ctx, nice) + 2 * pad
        if not first and ImGui.GetItemRectMax(ctx) + 6 + w <= xend then ImGui.SameLine(ctx, 0, 6) end
        first = false
        local picked = th == cur
        if picked then
          ImGui.PushStyleColor(ctx, ImGui.Col_Button, solid(col)); ImGui.PushStyleColor(ctx, ImGui.Col_Text, on_colour(col))
        end
        if ImGui.Button(ctx, nice .. "##tv" .. i) and not picked then
          reaper.SetExtState(SECTION, "theme " .. sel.id, th, true)
          if on then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th) end
          say(nice .. (on and " is on." or (" is " .. sel.name .. "'s theme now.")))
        end
        if picked then ImGui.PopStyleColor(ctx, 2) end
        local c = core.CATALOG[th]
        ImGui.SetItemTooltip(ctx, (picked and "In use for " .. sel.name .. ". " or "") .. (c and ("By " .. tostring(c.by) .. (c.note and (": " .. c.note) or "") .. ".") or
          mine[th] and "You added this one." or "On this computer."))
        if mine[th] and ImGui.BeginPopupContextItem(ctx, "##tvm" .. i) then
          if ImGui.MenuItem(ctx, "Take off " .. sel.name .. "'s list") then remove_fork(sel, th) end
          ImGui.EndPopup(ctx)
        end
      end
      for i, th in ipairs(have) do -- (mod packs for a version you have: each mod becomes a version of its own)
        for k, m in ipairs((core.CATALOG[th] or {}).mods or {}) do
          if ImGui.SmallButton(ctx, "Add " .. th:gsub("%.ReaperTheme%a*$", "") .. "'s " .. m.name .. "##tvmod" .. i .. "_" .. k) then
            local got, why = core.install_mod(th, k)
            if got then drop_report(got) else say("Couldn't get it: " .. tostring(why)) end
          end
          ImGui.SetItemTooltip(ctx, "Downloads the mod pack and makes each mod a version of " .. th:gsub("%.ReaperTheme%a*$", "") .. " you can click above.")
        end
      end
      if #missing > 0 and ImGui.TreeNode(ctx, #missing .. " more version" .. (#missing == 1 and "" or "s") .. " you can get##tvget") then
        if can > 1 and ImGui.Button(ctx, "Install all " .. can .. "##tvall") then
          for _, th in ipairs(missing) do if core.can_install_theme(th) and not reaper.file_exists(themes_dir .. th) then install_theme_ui(th, sel, false) end end
        end
        for i, th in ipairs(missing) do
          local c = core.CATALOG[th]
          if core.can_install_theme(th) then
            if ImGui.SmallButton(ctx, "Install##tvi" .. i) then install_theme_ui(th, sel, false) end
            ImGui.SetItemTooltip(ctx, "Downloads it and takes it in, with its fonts and extras on your yes.")
          elseif ImGui.SmallButton(ctx, "Get it##tvg" .. i) then core.open_url(c.url) end
          ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, th:gsub("%.ReaperTheme%a*$", "") .. (c.by and (" by " .. c.by) or "") .. (c.note and (" (" .. c.note .. ")") or ""))
        end
        muted("Get it opens a page that needs your browser (a paid theme, or a sign-in): download it there, then drop the file on this window.")
        ImGui.TreePop(ctx)
      end
    end
    if (core.theme_for(sel) or ""):match("^ReaPersona %- ") then
      muted("ReaPersona's own theme is an approximation of " .. sel.name .. "'s colours on REAPER's Default 7 layout. Themes by other authors can look closer to the real thing: Home lists them with Get it links, and Themes > Get more searches the Stash.")
    end
    card_end()
  end
  if sel.feel and #sel.feel > 0 and card("feel card") then
    heading("How it behaves")
    muted("Put back the way you had it when you switch away.")
    feel_rows(sel)
    card_end()
  end
  if sel.extras and #sel.extras > 0 and card("extras card") then
    heading("What " .. (sel.preset and (core.by_id(sel.base) or sel).name or sel.name) .. " has, and where it is in REAPER")
    rows("extras", sel.extras, true)
    card_end()
  end
  if sel.tips and #sel.tips > 0 and card("tips card") then
    heading("REAPER:") -- (not "REAPER tips": it read as the Reapertips theme)
    muted((sel.id == "base_reaper" and "" or "With REAPER's own keys (Base REAPER has them all). ") .. "From REAPER's factory keymap.")
    rows("tips", sel.tips, true)
    if ImGui.SmallButton(ctx, "REAPER User Guide") then core.open_url("https://www.reaper.fm/userguide.php") end
    card_end()
  end
  local fxl = core.fx_equiv(sel.preset and sel.base or sel.id) -- (5.36: its plug-ins, and REAPER's own for each)
  if fxl and card("fx card") then
    local who = sel.preset and core.by_id(sel.base) or sel
    heading(who.name .. "'s plug-ins in REAPER")
    muted("REAPER's own plug-in for each of " .. who.name .. "'s. A folder of them in REAPER's FX browser keeps them together (REAPER shows it after its next restart; it lists REAPER's names).")
    local here, on = core.fx_stock_here(), core.fx_folder_on(who)
    if ImGui.SmallButton(ctx, (on and "Take out" or "Add") .. " the '" .. core.fx_folder_name(who) .. "' folder##fxf") then
      local n, why = core.fx_folder_set(who, not on)
      say(n and (on and "The folder is out of REAPER's FX browser (after its next restart)." or ("The folder, with " .. n .. " of REAPER's plug-ins, is in REAPER's FX browser after its next restart.")) or ("Not changed: " .. tostring(why)))
    end
    ImGui.Indent(ctx, IND * UI)
    for _, x in ipairs(fxl) do
      local f = here[x[2]]
      ImGui.Text(ctx, x[1]); ImGui.SameLine(ctx, 260 * UI)
      if f then ImGui.TextColored(ctx, C.MUTED, core.fx_stock_name(x[2])) else ImGui.TextColored(ctx, C.YELLOW, core.fx_stock_name(x[2]) .. " (not found in this REAPER)") end
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
function pick_in(list, sel) -- the one picked, if it's on this page; else this page's first
  for _, st in ipairs(list) do if st == sel then return sel end end
  return list[1]
end

function daws_page(sel, alt)
  local list = {}
  for _, st in ipairs(styles) do if st.kind ~= "theme" and ((not st.user and st.kind ~= "built") or core.factory[st.id]) then list[#list + 1] = st end end -- (yours: Your personas; yours saved over a DAW: here, in its place)
  workflow_row()
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
  if ImGui.SmallButton(ctx, "Import a shared persona...") then
    local ok, p = reaper.GetUserFileNameForRead("", "Import a ReaPersona persona", "*.json")
    if ok then
      local st, why = core.import(p)
      reaper.MB(st and (st.name .. " is imported: it's in Personas > Your personas. Its shortcuts need installing (" .. INSTALL_WHERE .. ").") or ("Not imported: " .. why), "ReaPersona", 0)
    end
  end
end

-- Themes: theme styles (a theme with your own keys), every theme on this computer, adding your own, and where to find more.
THEME_SOURCES = {
  { "REAPER Stash: themes", "https://stash.reaper.fm/tag/Themes", "Cockos' own library: most REAPER themes live here (sort by downloads)." },
  { "ReaPack: browse themes", "reapack", "Themes you can install and keep updated from inside REAPER (Extensions > ReaPack > Browse packages, type: Theme)." },
  { "Reapertips", "https://www.reapertips.com/", "The Reapertips theme and its updates." },
  { "Cockos forum: Themes", "https://forum.cockos.com/forumdisplay.php?f=21", "Where theme authors post new themes and versions." },
}
themes_filter, theme_list = "", nil
function import_theme()
  local ok, p = reaper.GetUserFileNameForRead("", "Add a theme (.ReaperThemeZip or .ReaperTheme)", "*.ReaperTheme*")
  if not ok then return end
  local name, why = core.import_theme(p)
  theme_list = nil
  if not name then return reaper.MB("Not added: " .. tostring(why), "ReaPersona", 0) end
  local cur = core.current()
  if reaper.MB(name .. " is in ColorThemes now.\n\nUse it now, and " .. (core.is_trial() and "make it the theme of the persona you're making?" or ("keep it in " .. cur.name .. "'s Theme list?")), "ReaPersona", 4) == 6 then
    add_fork(cur, name)
    reaper.OpenColorThemeFile(themes_dir .. name)
  end
  say("Added " .. name)
end
function themes_page(sel, alt)
  if card("theme now") then -- (5.28: the one in use, always first and apart)
    local now = core.loaded_theme() or "?"
    heading("In use: " .. now:gsub("%.ReaperTheme%a*$", ""), 18)
    if ImGui.SmallButton(ctx, "Adjust it##thnow") then go("Adjust") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "My persona's theme##thnowp") then in_persona(core.new_block("theme", now), (now:gsub("%.ReaperTheme%a*$", ""))) end
    ImGui.SetItemTooltip(ctx, "Makes the theme in use the theme of the persona you're making.")
    card_end()
  end
  if card("all themes") then
    persona_theme_line()
    ImGui.Dummy(ctx, 0, 2)
    heading("Every theme on this computer")
    muted("Use one on its own (your keys and settings stay as they are), or add it to the Theme list of the persona in use.")
    theme_list = theme_list or theme_files()
    ImGui.SetNextItemWidth(ctx, 260)
    local _, f = ImGui.InputTextWithHint(ctx, "##tf", "search " .. #theme_list .. " themes", themes_filter)
    themes_filter = f
    ImGui.SameLine(ctx)
    if primary("Add a theme...") then import_theme() end
    ImGui.SetItemTooltip(ctx, "Copy a .ReaperThemeZip or .ReaperTheme you downloaded into REAPER's ColorThemes folder.")
    local current = core.loaded_theme() or ""
    local cur = core.current()
    if ImGui.BeginTable(ctx, "themes", 3, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 320) then
      ImGui.TableSetupColumn(ctx, "name", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "use", ImGui.TableColumnFlags_WidthFixed)
      ImGui.TableSetupColumn(ctx, "add", ImGui.TableColumnFlags_WidthFixed)
      local q = themes_filter:lower()
      for i, th in ipairs(theme_list) do
        if q == "" or th:lower():find(q, 1, true) then
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); ImGui.AlignTextToFramePadding(ctx)
          local nice = th:gsub("%.ReaperThemeZip$", ""):gsub("%.ReaperTheme$", "") -- (theme names, not file names)
          if (core.recent_themes or {})[th] then nice = nice .. "  (new)" end
          if th == current then ImGui.TextColored(ctx, C.GREEN, nice .. "  (in use)") else ImGui.Text(ctx, nice) end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "Try##t" .. i) then try_theme(th) end
          ImGui.SetItemTooltip(ctx, "Wear it for 20 seconds: Keep it, or it goes back to the theme you had.")
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Use##u" .. i) then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th); say(nice .. " in use.") end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "My persona##p" .. i) then in_persona(core.new_block("theme", th), nice) end
          ImGui.SetItemTooltip(ctx, "The theme of the persona you're making (it replaces the one in it).")
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Add to...##a" .. i) then ImGui.OpenPopup(ctx, "addto##" .. i) end
          ImGui.SetItemTooltip(ctx, "Make it one of a persona's theme versions (its page lists them to click).")
          if ImGui.BeginPopup(ctx, "addto##" .. i) then
            for _, st in ipairs(styles) do
              if st.kind ~= "theme" and ImGui.MenuItem(ctx, st.name .. (st == cur and "  (in use)" or "") .. "##at" .. st.id) then
                add_fork(st, th); if st == cur then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th) end
                say(nice .. " is one of " .. st.name .. "'s theme versions" .. (st == cur and ", and on now." or "."))
              end
            end
            ImGui.EndPopup(ctx)
          end
        end
      end
      ImGui.EndTable(ctx)
    end
    card_end()
  end
  local list = {}
  for _, st in ipairs(styles) do if st.kind == "theme" then list[#list + 1] = st end end
  if #list > 0 then
    view_switch()
    chooser(list, pick_in(list, sel), alt)
    ImGui.Dummy(ctx, 0, 4)
    detail(pick_in(list, sel), alt)
  end
  if card("theme sources") then
    heading("Where to get more themes")
    for i, s in ipairs(THEME_SOURCES) do
      if ImGui.Button(ctx, s[1] .. "##src" .. i) then
        if s[2] == "reapack" then
          local id = reaper.NamedCommandLookup("_REAPACK_BROWSE")
          if id ~= 0 then reaper.Main_OnCommand(id, 0) else reaper.MB("ReaPack isn't installed (reapack.com).", "ReaPersona", 0) end
        else core.open_url(s[2]) end
      end
      ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); muted(s[3])
    end
    ImGui.Dummy(ctx, 0, 2)
    muted("Downloaded a theme? Add a theme... above copies it in. A theme's author decides whether it can be shared: most say nothing, so keep merged and edited versions to yourself unless they agree.")
    card_end()
  end
end

function presets_page(sel, alt)
  if card("presets top") then
    heading("Make your own persona")
    muted("Save what you're using now (the persona, plus your theme, layout, snap and mouse as they're set), or make one: New persona, then choose its shortcuts, mouse, layout, theme, colours, project and REAPER settings on their tabs. Edit on any persona's page changes it the same way.")
    if primary("Save what I'm using now...") then save_preset_prompt() end
    ImGui.SameLine(ctx)
    if primary("New persona") then bld_new() end
    ImGui.SetItemTooltip(ctx, "Starts a persona with nothing chosen: your own setup fills in whatever you don't choose on the tabs.")
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Import...") then
      local ok, p = reaper.GetUserFileNameForRead("", "Import a ReaPersona persona", "*.json")
      if ok then
        local r = core.import_file(p)[1] or { "skipped", p, "nothing in it" }
        reaper.MB(r[1] ~= "skipped" and (r[2] .. " is imported.") or ("Not imported: " .. tostring(r[3])), "ReaPersona", 0)
      end
    end
    card_end()
  end
  local list = {}
  for _, st in ipairs(styles) do if (st.user or st.kind == "built") and st.kind ~= "theme" and st.id ~= "built_try" and not core.factory[st.id] then list[#list + 1] = st end end
  for _, st in ipairs(core.presets) do list[#list + 1] = st end
  if #list == 0 then return end
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
end
function favourites_page(sel, alt) -- (5.27) the DAWs and personas you starred
  local list = {}
  for _, id in ipairs(core.favourites()) do local st = core.by_id(id); if st then list[#list + 1] = st end end
  if #list == 0 then
    if card("fav none") then heading("Favourites"); muted("Click the star on any DAW or persona (its card, top left) to keep it here."); card_end() end
    return
  end
  workflow_row()
  view_switch()
  chooser(list, pick_in(list, sel), alt)
  ImGui.Dummy(ctx, 0, 4)
  detail(pick_in(list, sel), alt)
end
