-- ReaPersona's window: the tabs, Help, search, the top bar, the frame and loop, the screen-reader menu.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 3331-3936.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
GROUPS = { -- { name, what it's for, its pages (tabs), the tabs' labels }
  { "Home", "Get everything set up, and import from another DAW. Drop files here.", { "Setup" }, { "Setup" } },
  { "Personas", "Your favourites, the DAWs, and the personas you made.", { "Favourites", "DAWs", "Presets" }, { "Favourites", "DAWs", "Your personas" } },
  { "Themes", "Your themes, getting more, adjusting the one in use, and building one from others.", { "Themes", "Browse", "Adjust", "Merge" }, { "Your themes", "Get more", "Adjust", "Build one" } },
  { "Colours", "Colour the project: tracks, items and regions, by gradient, folder, instrument, section and more.", { "Colours" }, { "Colours" } }, -- (its own tab since 5.25: James)
  { "Shortcuts", "Your persona's shortcuts, and every key of any persona with REAPER's action for it.", { "Shortcuts" }, { "Shortcuts" } },
  { "Mouse & trackpad", "Your persona's mouse wheel, trackpad gestures, drags and clicks, from any persona.", { "Mouse" }, { "Mouse & trackpad" } },
  { "Layout", "Your persona's mixer, transport, browser, toolbar, MIDI editor, and snap and ripple, each from any persona.", { "Layout" }, { "Layout" } },
  { "Project", "Your persona's project defaults: sample rate, tempo, time signature, grid, starter tracks or a template, a window set.", { "Project" }, { "Project defaults" } },
  { "REAPER", "REAPER's own options and SWS's, an area per tab, each to make part of your persona.", {}, {} }, -- (tabs: below, one per setting group)
  { "Settings", "ReaPersona's own settings: your other computers, what personas may change, scrolling and zoom, its look, updates.", { "Settings", "SetPersonas", "SetScroll", "SetLook", "SetUpdates", "SetRemove" }, { "Sync", "Personas", "Scrolling & zoom", "Look", "Updates", "Remove" } },
  { "Help", "How ReaPersona works and what each page does, what's installed, checking the personas, repairs.", { "Guide", "Check" }, { "How it works", "Check and repair" } },
}
-- Show everything (5.37, product review 2026-11-18: pick your DAW and restart once was hard to see among 30 tabs). Off, the editors and
-- REAPER's own options are out of the way: Mouse & trackpad, Layout, Project, the REAPER tab, and Themes' Adjust and Build one. A new
-- install starts with it off; one that was already in use keeps everything (ExtState "advanced").
if reaper.GetExtState(SECTION, "advanced") == "" then reaper.SetExtState(SECTION, "advanced", (reaper.GetExtState(SECTION, "welcomed") == "" and reaper.GetExtState(SECTION, "style") == "") and "0" or "1", true) end
ADV_ONLY = { Mouse = true, Layout = true, Project = true, Adjust = true, Merge = true }
page_shown = function(pg) return bld.active or reaper.GetExtState(SECTION, "advanced") ~= "0" or not (ADV_ONLY[pg] or tostring(pg):match("^R_")) end -- (making a persona: every part's tab. Review 2 2026-11-18)
set_advanced = function(on)
  reaper.SetExtState(SECTION, "advanced", on and "1" or "0", true)
  say(on and "Every tab is showing: also Mouse & trackpad, Layout, Project, REAPER's options, and adjusting and building themes." or "Showing the main tabs. Show everything brings the rest back.")
  if not page_shown(page) then go("Setup") end -- (not left on a page the list no longer has)
end
page_name = function(pg) -- ("REAPER: Preferences", "Settings: Sync": not "R_prefs", "Settings". Review 2026-11-18)
  for _, g in ipairs(GROUPS) do
    for i, p in ipairs(g[3]) do if p == pg then return #g[3] > 1 and (g[1] .. ": " .. g[4][i]) or g[1] end end
  end
end
do -- (REAPER's tabs: one per setting group. 5.33)
  local short = { playback = "Playback", editing = "Editing", recording = "Recording", view = "View", colours = "Colours & icons", automation = "Automation", monitoring = "Monitoring & FX", mixer = "Mixer" }
  for _, g in ipairs(GROUPS) do
    if g[1] == "REAPER" then
      for _, s in ipairs(core.SETTING_GROUPS) do g[3][#g[3] + 1] = "R_" .. s.id; g[4][#g[4] + 1] = short[s.id] or s.name end
      g[3][#g[3] + 1] = "R_prefs"; g[4][#g[4] + 1] = "Preferences" -- (5.35)
    end
  end
end
-- Help > How it works (5.14), also the screen-reader menu's Help: plain sentences, so the same text reads in a message box.
GUIDE = {
  { "Getting started", {
    "1. Pick the DAW you're coming from: Personas > DAWs, or the first card on Home. REAPER takes on its look and feel straight away, and its shortcuts once they're installed (step 2). Back to My REAPER (top) puts your own setup back, exactly as it was.",
    "2. Finish setting up: Home > Finish setting up. REAPER restarts once (about 10 seconds; it asks about anything unsaved first): your persona's shortcuts go in, and your persona comes back each time REAPER starts. After adding or changing a persona, Home > Install and restart puts its keys in.",
    "3. More than one computer? Settings > Sync: save your setup to a file, or keep them the same through a shared folder." } },
  { "What each page does", {
    "Home: the first steps, what ReaPersona can use and whether it's there (one click for each), importing from another DAW on this computer, and themes by other people. Drop theme, toolbar, keymap or persona files anywhere on the window to add them.",
    "Personas > DAWs: each DAW's persona, with its keys, look and feel: Use it, its cheat sheet, a new project like it, and that DAW's plug-ins with REAPER's own for each (it can add a \"<DAW> -> REAPER\" folder to REAPER's FX browser). Workflow on top (above the cards) adds a kind of session, voiceover or mixing say, to whichever persona is in use. Your personas: the ones you saved or built, and your workflows. Favourites: the ones you starred.",
    "Making your own: New persona (Your personas) or Edit on any persona's page, then choose each part on its tab; the bar at the top shows what's in it, and Save is there. A DAW persona you edit is saved as a new one of yours. Preview as I change (in that bar) puts each change into REAPER a moment after you make it, and Undo and Redo (Ctrl+Z, and Ctrl+Shift+Z or Ctrl+Y; Cmd on a Mac) step through your changes. A preview isn't saved: Go back, Stop or closing this window puts what you had back, and using another persona turns Preview off.",
    "Themes > Your themes: the theme for each persona. Get more: the REAPER Stash and ReaPack. Adjust: change the theme in use, live, and put its settings in your persona. Build one: a theme from parts of others.",
    "Colours: colour the whole project at once: tracks by gradient, folder or instrument, items by section or take, regions too. Try it first, then keep it or put it back.",
    "Shortcuts: your persona's keys (change any, add any action), and every key of every persona with the REAPER action it runs.",
    "Mouse & trackpad: your persona's mouse wheel, trackpad gestures, drags and clicks, from any persona, each one changeable.",
    "Layout: drag the mixer, Media Explorer, transport and MIDI editor where you want them; the toolbar, snap and ripple from any persona; and Other windows: the Actions list, Undo History, Region Manager and the rest, open or closed, docked or in their own window.",
    "Project: what a new project gets with your persona: sample rate, tempo, time signature, grid, render settings, starter tracks or a template, a window set.",
    "REAPER: REAPER's and SWS's options, an area per tab, each one In my persona or not; and Preferences: fades and crossfades, zoom, new tracks, recording and solo, which go in when REAPER restarts.",
    "Settings: Sync (your other computers), Personas (what a persona may change, a persona per project, ReaPersona's actions), Scrolling & zoom, Look (this window, the screen-reader menu), Updates, and Remove.",
    "Show everything (bottom left, or Settings > Look): off, only the main tabs show; on, also Mouse & trackpad, Layout, Project, REAPER's options, and adjusting and building themes. While you make or edit a persona, every tab shows.",
    "Restarting REAPER: some parts go in only when REAPER starts. Home lists what's waiting (REAPER preferences, the window set, things from your other computers) with Restart REAPER now; new shortcuts are Home's Install and restart; an FX folder shows after any restart. REAPER asks about anything unsaved first.",
    "Help > How it works: this page. Check and repair: what's installed, a check of every persona against this REAPER, and registering ReaPersona's actions again." } },
  { "Keyboard", {
    "Tab and Shift+Tab move between controls, the arrow keys move within a page, Enter or Space presses, and Escape closes a menu or clears the search.",
    "Ctrl+K (Cmd+K on a Mac) searches everything: personas, keys, settings and pages, when the window is wide enough to show the search box. F1 opens this page." } },
  { "Screen readers", {
    "This window is drawn by ReaImGui, which a screen reader can't read. ReaPersona's menu it can: a menu at the mouse pointer with the main tasks (pick a persona, back to My REAPER, undo a switch, save what you're using, a new project with a workflow, install the shortcuts, your other computers, the cheat sheet, this help), with each result in a message box.",
    "The action 'ReaPersona - screen-reader menu' (Actions list) always opens it. To have ReaPersona's own action open the menu too, say yes when ReaPersona asks (with OSARA installed), or use the menu's item for it. 'Open ReaPersona's window' opens this window once." } },
  { "Your own setup is safe", {
    "A persona's keys sit in a shortcut layer of their own; keys it doesn't define fall through to yours, and Back to My REAPER puts back whatever a persona changed.",
    "Every install backs up your keymap first, next to it in REAPER's resource folder (reaper-kb.ini.before-reapersona-...). The first backup, from before ReaPersona, is always kept.",
    "Without Python, the install is planned while REAPER runs and a small script (a batch file on Windows, a shell script on a Mac or Linux) swaps it in once REAPER has closed. If anything changed the keymap in between, nothing is swapped in and ReaPersona says so." } },
}
function guide_text() -- (the whole guide as plain text)
  local out = {}
  for _, s in ipairs(GUIDE) do out[#out + 1] = s[1] .. "\n- " .. table.concat(s[2], "\n- ") end
  return table.concat(out, "\n\n")
end
function guide_page()
  if card("guide top") then
    heading("How ReaPersona works")
    muted("ReaPersona makes REAPER feel like the DAW you're coming from: its shortcuts, look, feel and mouse, switched in one click, with your own setup always one click away.")
    if ImGui.SmallButton(ctx, "Copy as plain text") then ImGui.SetClipboardText(ctx, guide_text()); say("The guide is on the clipboard.") end
    ImGui.SetItemTooltip(ctx, "The whole guide as plain text, to paste anywhere or read with a screen reader.")
    card_end()
  end
  for i, s in ipairs(GUIDE) do
    if card("guide " .. i) then
      heading(s[1])
      for _, line in ipairs(s[2]) do ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, line) end
      card_end()
    end
  end
end
function group_of(pg) for _, g in ipairs(GROUPS) do for _, p in ipairs(g[3]) do if p == pg or (pg == "Styles" and p == "DAWs") then return g end end end return GROUPS[2] end
last_tab = {} -- (each group reopens on the tab you left it on)
-- Search everything (top bar, Ctrl+K): styles, shortcuts in every style, where a DAW's feature is in REAPER, themes, settings, pages.
function search_page()
  local q = search_q:lower()
  local function has(...) for i = 1, select("#", ...) do local v = select(i, ...); if type(v) == "string" and v:lower():find(q, 1, true) then return true end end end
  local shown = 0
  local function section(title) heading(title, 15) end
  if card("search") then
    heading("Results for \"" .. search_q .. "\"")
    local hits = {}
    for _, st in ipairs(styles) do if has(st.name, st.id) then hits[#hits + 1] = st end end
    if #hits > 0 then
      section("Personas")
      for i, st in ipairs(hits) do
        if ImGui.SmallButton(ctx, "Use##ss" .. i) then use(st); selected = st.id end
        ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show##ss" .. i) then selected = st.id; search_q = ""; go((st.user or st.preset or st.kind == "built") and "Presets" or "DAWs") end
        ImGui.SameLine(ctx); ImGui.Text(ctx, st.name)
      end
      shown = shown + #hits
    end
    local rows = {}
    for _, st in ipairs(styles) do
      for _, k in ipairs(core.keys_here(st.keys)) do if has(k[1], k[3]) then rows[#rows + 1] = { st, k, "" } end end
      for _, k in ipairs(st.midi_keys or {}) do if has(k[1], k[3]) then rows[#rows + 1] = { st, k, " (MIDI editor)" } end end
    end
    if #rows > 0 then
      section("Shortcuts (" .. #rows .. ")")
      if ImGui.BeginTable(ctx, "srch keys", 3, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
        ImGui.TableSetupColumn(ctx, "style", ImGui.TableColumnFlags_WidthFixed, 150)
        ImGui.TableSetupColumn(ctx, "key", ImGui.TableColumnFlags_WidthFixed, 150)
        ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
        for i, r in ipairs(rows) do
          if i > 60 then break end
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          if ImGui.Selectable(ctx, (r[1].short or r[1].name) .. "##sk" .. i, false) then keys_for = r[1].id; filter = search_q; search_q = ""; go("Shortcuts") end
          ImGui.TableNextColumn(ctx); keycap(r[2][1])
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, r[2][3] .. r[3])
        end
        ImGui.EndTable(ctx)
      end
      if #rows > 60 then muted((#rows - 60) .. " more: add a word to narrow it down.") end
      shown = shown + #rows
    end
    local where = {}
    for _, st in ipairs(styles) do for _, x in ipairs(st.extras or {}) do if has(x[1]) then where[#where + 1] = { st, x } end end end
    if #where > 0 then
      section("Where it is in REAPER")
      for i, w in ipairs(where) do
        if i > 20 then break end
        if w[2][2] ~= nil then if ImGui.SmallButton(ctx, "Open##sw" .. i) then open_extra(w[2][2]) end; ImGui.SameLine(ctx) end
        ImGui.TextWrapped(ctx, (w[1].short or w[1].name) .. ": " .. w[2][1])
      end
      shown = shown + #where
    end
    theme_list = theme_list or theme_files()
    local th = {}
    for _, t in ipairs(theme_list) do if has(t) then th[#th + 1] = t end end
    if #th > 0 then
      section("Themes")
      for i, t in ipairs(th) do
        if i > 15 then break end
        if ImGui.SmallButton(ctx, "Try##st" .. i) then try_theme(t) end
        ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Use##st" .. i) then trying = nil; reaper.OpenColorThemeFile(themes_dir .. t) end
        ImGui.SameLine(ctx); ImGui.Text(ctx, (t:gsub("%.ReaperTheme.*$", "")))
      end
      shown = shown + #th
    end
    local sets = {}
    for _, g in ipairs(core.SETTING_GROUPS) do
      for _, x in ipairs(g.items) do if type(x[1]) ~= "table" and has(x[2], x.tip, g.name) and core.cmd_id(x[1]) ~= 0 then sets[#sets + 1] = x end end
    end
    if #sets > 0 then
      section("REAPER's defaults")
      for i, x in ipairs(sets) do
        if setting_row("##ssx" .. i, x[2], reaper.GetToggleCommandState(core.cmd_id(x[1])) == 1, x.tip) then reaper.Main_OnCommand(core.cmd_id(x[1]), 0) end
      end
      shown = shown + #sets
    end
    for _, a in ipairs(core.ASPECTS) do
      if has(a[2]) then
        if ImGui.SmallButton(ctx, "Open##sa" .. a[1]) then search_q = ""; go("SetPersonas") end
        ImGui.SameLine(ctx); ImGui.Text(ctx, "What a persona may change: " .. a[2]); shown = shown + 1
      end
    end
    for _, g in ipairs(GROUPS) do
      if has(g[1], g[2], table.concat(g[4], " ")) then
        if ImGui.SmallButton(ctx, "Go##sg" .. g[1]) then search_q = ""; go(g[3][1]) end
        ImGui.SameLine(ctx); ImGui.Text(ctx, "Page: " .. g[1] .. " (" .. g[2] .. ")"); shown = shown + 1
      end
    end
    if shown == 0 then muted("Nothing found. Try a shorter word, like \"split\", \"mixer\" or \"loop\".") end
    card_end()
  end
end
function top_bar(alt)
  local cur = core.current()
  local y0 = ImGui.GetCursorPosY(ctx) -- (below the title bar)
  ImGui.SetCursorPos(ctx, 16, y0 + 10)
  ImGui.PushFont(ctx, bold, 20 * UI); ImGui.Text(ctx, "ReaPersona"); ImGui.PopFont(ctx)
  ImGui.SameLine(ctx, 0, 14)
  ImGui.SetCursorPosY(ctx, y0 + 13)
  local col = accent_of(cur)
  local wf = core.current_workflow()
  local trial = cur.id == "built_try" -- (the persona being made, on show: Preview or Try it)
  pill(cur.name .. (trial and " (preview)" or "") .. (wf and wf.id ~= cur.id and ("  +  " .. wf.name) or "") .. ((trial or in_use(cur, alt)) and "" or "  (keys off)"), solid(col))
  if trial then ImGui.SetItemTooltip(ctx, "The persona you're making, in REAPER for now. Save it, or Go back (in the bar below) to put back what you had.")
  elseif not in_use(cur, alt) then ImGui.SetItemTooltip(ctx, "Its shortcuts aren't on (REAPER restarted?): Use it again, or add the startup line on Home so it comes back each time REAPER starts.") end
  local w = ImGui.GetWindowWidth(ctx)
  if w > 760 then -- (search, Ctrl+K; on a narrow window it's left out of the bar)
    ImGui.SameLine(ctx, 0, 16)
    ImGui.SetCursorPosY(ctx, y0 + 8)
    if ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_K) or search_focus then ImGui.SetKeyboardFocusHere(ctx); search_focus = false end
    ImGui.SetNextItemWidth(ctx, math.min(260, w - ImGui.GetCursorPosX(ctx) - 320))
    local _, q = ImGui.InputTextWithHint(ctx, "##search", "Search everything (" .. MOD .. "+K)", search_q)
    search_q = q
  end
  if search_q ~= "" and ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then search_q = "" end
  local undo = last_style and last_style ~= cur.id and last_style ~= "built_try" and core.by_id(last_style)
  local right = (undo and 520 or 410) * UI
  local after = ImGui.GetItemRectMax(ctx) - ImGui.GetWindowPos(ctx) + 12
  if w - right >= after then ImGui.SameLine(ctx, w - right); ImGui.SetCursorPosY(ctx, y0 + 8) else ImGui.SetCursorPosX(ctx, 16) end
  if undo then
    if ImGui.Button(ctx, "Undo switch") then use(undo) end
    ImGui.SetItemTooltip(ctx, "Back to " .. undo.name .. ", as it was before you switched.")
    ImGui.SameLine(ctx)
  end
  if ImGui.Button(ctx, "Save what I'm using...##top") then save_preset_prompt() end
  ImGui.SetItemTooltip(ctx, "Keep what's in use now, under a name: the persona's keys and toolbar, the theme, the layout, snap and the mouse behaviours as they are right now.")
  ImGui.SameLine(ctx)
  ImGui.BeginDisabled(ctx, cur.id == "my_reaper")
  if ImGui.Button(ctx, "Back to My REAPER") then use(core.by_id("my_reaper")) end
  ImGui.EndDisabled(ctx)
  ImGui.SetItemTooltip(ctx, "Your own shortcuts, theme and settings, exactly as you had them.")
  ImGui.SameLine(ctx)
  feedback.button(ctx, ImGui)
  ImGui.SetCursorPosY(ctx, math.max(y0 + 48, ImGui.GetCursorPosY(ctx) + 4))
  ImGui.Separator(ctx)
end

-- (in R: last_error, last_logged)
first_frame = true
function frame()
  ImGui.SetNextWindowSize(ctx, 980, 760, ImGui.Cond_FirstUseEver)
  for _, c in ipairs(COLS) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  for _, v in ipairs(VARS) do ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) end
  ImGui.PushFont(ctx, font, 15 * UI)
  ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Once) -- (a window an older version left in a docker comes out once)
  local visible, open = ImGui.Begin(ctx, "ReaPersona", true, ImGui.WindowFlags_NoDocking)
  images_left = 2
  if visible then
    if ensure_new or core.stubs_stale then core.ensure_scripts(); ensure_new = false end
    core.apply_midi_dock() -- (a style's MIDI editor docking waits for an editor to be open)
    local ask = reaper.GetExtState(SECTION, "search") -- (a search asked for from outside: another script, or a test)
    if ask ~= "" then search_q = ask; reaper.DeleteExtState(SECTION, "search", false) end
    if first_frame then
      first_frame = false
      if reaper.GetExtState(SECTION, "page") == "" and setup_todo() then go("Setup") end
      local note = core.read(here .. "/last_install.txt")
      if note then -- (what the last one-button install did, in a few words; the details stay in the backup's name)
        os.remove(here .. "/last_install.txt")
        local n = note:match("installed (%d+) shortcut")
        say(n and ("Shortcuts installed (" .. n .. "). Your old keymap was backed up first.") or ((note:gsub("%s+$", "")):match("[^\n]*$") or ""):sub(1, 120))
      end
    end
    local alt = core.active_alt()
    local sel = core.by_id(selected) or styles[1]
    local want = reaper.GetExtState(SECTION, "page")
    if want ~= "" and want ~= page then page = want end
    if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) and ImGui.IsKeyPressed(ctx, ImGui.Key_F1) then go("Guide") end
    top_bar(alt)
    trying_bar()
    if last_error then
      ImGui.SetCursorPosX(ctx, 16)
      ImGui.TextColored(ctx, C.RED, "Something went wrong and was written to errors.log: " .. last_error)
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "OK##err") then last_error = nil end
    end
    local narrow = ImGui.GetWindowWidth(ctx) < 600 -- (a small window: the sidebar becomes a drop-down)
    if narrow then
      ImGui.SetCursorPosX(ctx, 16)
      ImGui.SetNextItemWidth(ctx, -16)
      if ImGui.BeginCombo(ctx, "##navc", group_of(page)[1] .. (setup_todo() and "  (Home: something to do)" or "")) then
        for _, g in ipairs(GROUPS) do
          local first = nil
          for _, p in ipairs(g[3]) do if not first and page_shown(p) then first = p end end
          if (first or g == group_of(page)) and ImGui.Selectable(ctx, g[1] .. "##navc", g == group_of(page)) then go(last_tab[g[1]] and page_shown(last_tab[g[1]]) and last_tab[g[1]] or first or page) end
        end
        ImGui.Separator(ctx)
        local adv = reaper.GetExtState(SECTION, "advanced") ~= "0"
        if ImGui.Selectable(ctx, "Show everything##navadv", adv) then set_advanced(not adv) end
        ImGui.EndCombo(ctx)
      end
    end
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, C.NAV)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 10)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_SelectableTextAlign, 0, 0.5)
    if not narrow and ImGui.BeginChild(ctx, "nav", 160 * UI, 0, ImGui.ChildFlags_AlwaysUseWindowPadding) then
      ImGui.PushFont(ctx, nil, 16 * UI)
      local cur_g = group_of(page)
      for _, g in ipairs(GROUPS) do
        local first = nil
        for _, p in ipairs(g[3]) do if not first and page_shown(p) then first = p end end
        if first or g == cur_g then -- (the group you're on stays, even one Show everything hides: reached by a link)
        local x, y = ImGui.GetCursorScreenPos(ctx)
        if ImGui.Selectable(ctx, "  " .. g[1] .. "##nav", g == cur_g, ImGui.SelectableFlags_None, 0, 36) then go(last_tab[g[1]] and page_shown(last_tab[g[1]]) and last_tab[g[1]] or first or page) end
        ImGui.SetItemTooltip(ctx, g[2])
        if g == cur_g then ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx), x - 8, y + 6, x - 4, y + 30, C.ACCENT, 2) end
        if g[1] == "Home" and setup_todo() then ImGui.DrawList_AddCircleFilled(ImGui.GetWindowDrawList(ctx), x + 112, y + 18, 4, C.YELLOW) end -- (something to do)
        end
      end
      ImGui.PopFont(ctx)
      ImGui.Dummy(ctx, 0, 8)
      ImGui.PushFont(ctx, nil, 13 * UI)
      local adv = reaper.GetExtState(SECTION, "advanced") ~= "0"
      local chg, on = ImGui.Checkbox(ctx, "Show everything##navadv", adv)
      if chg then set_advanced(on) end
      ImGui.SetItemTooltip(ctx, "Off: the main tabs only (Home, Personas, Themes, Colours, Shortcuts, Settings, Help). On: also Mouse & trackpad, Layout, Project, REAPER's own options, and adjusting and building themes. While you make or edit a persona, every tab shows.")
      ImGui.PopFont(ctx)
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx)
    if not narrow then ImGui.SameLine(ctx, 0, 0) end
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 16, 12)
    if ImGui.BeginChild(ctx, "page", 0, 0, ImGui.ChildFlags_AlwaysUseWindowPadding) then
      local g = group_of(page)
      last_tab[g[1]] = page
      if #g[3] > 1 then -- (the group's pages as tabs)
        local row_end = ImGui.GetCursorScreenPos(ctx) + ImGui.GetContentRegionAvail(ctx) -- (5.35: tabs that don't fit go on a second line)
        local drawn = 0
        for i, pg in ipairs(g[3]) do
          if page_shown(pg) or page == pg then -- (5.37: Show everything off hides some; one you reached by a link still shows)
          local tw = ImGui.CalcTextSize(ctx, g[4][i]) + 24
          if drawn > 0 then
            ImGui.SameLine(ctx)
            if ImGui.GetCursorScreenPos(ctx) + tw > row_end then ImGui.NewLine(ctx) end
          end
          drawn = drawn + 1
          if ImGui.Selectable(ctx, g[4][i] .. "##tab", page == pg or (page == "Styles" and pg == "DAWs"), ImGui.SelectableFlags_None, tw, 28) then go(pg) end
          end
        end
        ImGui.Separator(ctx)
        ImGui.Dummy(ctx, 0, 2)
      end
      bld.tick() -- (5.38: the change history and the live preview, on every tab and in search)
      if search_q == "" then draft_strip() end -- (the persona being made, over every tab)
      if core.prefs_queued then core.prefs_queued = false; say("Some of this persona's REAPER preferences go in when REAPER restarts (Home > Restart REAPER now).") end
      if core.prefs_need_python then core.prefs_need_python = false; say("This persona's REAPER preferences need Python 3 to go in (python.org): the rest of it is in use.") end
      if search_q ~= "" then search_page()
      elseif page == "Setup" then setup_page()
      elseif page == "DAWs" or page == "Styles" then daws_page(sel, alt)
      elseif page == "Themes" then themes_page(sel, alt)
      elseif page == "Browse" then browse_page()
      elseif page == "Presets" then presets_page(sel, alt)
      elseif page == "Builder" or page == "Favourites" then favourites_page(sel, alt)
      elseif page == "Mouse" then mouse_page()
      elseif page == "Layout" then layout_page()
      elseif page == "Project" then project_page()
      elseif page == "Settings" then settings_page("sync")
      elseif page == "SetPersonas" then settings_page("personas")
      elseif page == "SetScroll" then settings_page("scroll")
      elseif page == "SetLook" then settings_page("look")
      elseif page == "SetUpdates" then settings_page("updates")
      elseif page == "SetRemove" then settings_page("remove")
      elseif page == "Tweaks" then tweaks_page("playback") -- (the old REAPER tweaks page: REAPER's first tab)
      elseif page == "R_prefs" then prefs_page()
      elseif page:match("^R_") then tweaks_page(page:sub(3))
      elseif page == "Shortcuts" then keys_page()
      elseif page == "Adjust" then
        if adjust_out then
          if card("adj out") then heading("Adjust is in its own window"); if ImGui.Button(ctx, "Bring it back here") then adjust_out = false end; card_end() end
        else adjust_page(core.current()) end -- (the theme you adjust is the one in use: its style gets the result)
      elseif page == "Merge" then merge_page(sel)
      elseif page == "Colours" then
        if card("col persona") then -- (5.28: a persona's default colours, apart from colouring this project)
          heading("Your persona's colours", 16)
          muted("The persona's default colour look, for projects that haven't got their own. A project you colour below keeps its own colours, whichever persona is in use.")
          ImGui.Indent(ctx, IND * UI)
          local inb = core.draft_get(bld.blocks, "colours")
          ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, inb and core.colours_label(inb.set) or "None: your own")
          ImGui.SameLine(ctx)
          if ImGui.SmallButton(ctx, "Set as this persona's default##colset") then in_persona(core.new_block("colours"), "The colour look below") end
          ImGui.SetItemTooltip(ctx, "Takes the colour look as set below (and your instrument, folder and section colours) as the persona's default.")
          if inb then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "None##colnone") then core.draft_clear(bld.blocks, "colours") end end
          ImGui.SameLine(ctx); ImGui.Text(ctx, "  Load from:"); ImGui.SameLine(ctx)
          ImGui.SetNextItemWidth(ctx, 200 * UI)
          if ImGui.BeginCombo(ctx, "##colfrom", "a persona of yours") then
            for _, st in ipairs(sources(function(s) return s.colours ~= nil end)) do
              if ImGui.Selectable(ctx, st.name .. "##cf" .. st.id) then core.draft_add(bld.blocks, { kind = "colours", set = st.colours }); bld.active = true end
            end
            ImGui.EndCombo(ctx)
          end
          ImGui.Unindent(ctx, IND * UI)
          card_end()
        end
        colours.draw(ctx, ImGui, reaper.EnumProjects(-1))
      elseif page == "Guide" then guide_page()
      elseif page == "Check" then check_page() end
      ImGui.EndChild(ctx)
    end
    setup_progress() -- (Set up everything's progress window, over the page)
    if ImGui.BeginDragDropTarget(ctx) then -- (files dropped anywhere on the page: themes, packs, toolbars, keymaps, styles, presets)
      local rv, count = ImGui.AcceptDragDropPayloadFiles(ctx)
      if rv then
        local got = {}
        for i = 0, count - 1 do
          local ok, fn = ImGui.GetDragDropPayloadFile(ctx, i)
          if ok then core.import_file(fn, got) end
        end
        drop_report(got)
      end
      ImGui.EndDragDropTarget(ctx)
    end
    ImGui.PopStyleVar(ctx)
    if reaper.time_precise() < toast_until then -- (what just happened, bottom right, for a few seconds)
      local wx, wy = ImGui.GetWindowPos(ctx)
      local ww, wh = ImGui.GetWindowSize(ctx)
      local wrap = math.max(120, ww - 80) -- (wraps: a long message ran off the window's left edge. Review 2026-11-18)
      local tw, th = ImGui.CalcTextSize(ctx, toast, nil, nil, false, wrap)
      local fl = ImGui.GetForegroundDrawList(ctx)
      ImGui.DrawList_AddRectFilled(fl, wx + ww - tw - 40, wy + wh - th - 34, wx + ww - 16, wy + wh - 16, solid(mix(P.text, P.accent, 0.4)), 8)
      ImGui.DrawList_AddTextEx(fl, ImGui.GetFont(ctx), ImGui.GetFontSize(ctx), wx + ww - tw - 28, wy + wh - th - 25, on_colour(mix(P.text, P.accent, 0.4)), toast, wrap)
    end
    ImGui.End(ctx)
  end
  if adjust_out then
    ImGui.SetNextWindowSize(ctx, 520, 680, ImGui.Cond_FirstUseEver)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 10)
    ImGui.SetNextWindowDockID(ctx, 0, ImGui.Cond_Once)
    local v2, o2 = ImGui.Begin(ctx, "ReaPersona: theme adjuster", true, ImGui.WindowFlags_NoDocking)
    if v2 then adjust_page(core.current()); ImGui.End(ctx) end
    ImGui.PopStyleVar(ctx)
    if not o2 then adjust_out = false end
  end
  feedback.draw(ctx, ImGui, core, feedback.VERSION, say)
  ImGui.PopFont(ctx)
  ImGui.PopStyleVar(ctx, #VARS)
  ImGui.PopStyleColor(ctx, #COLS)
  return open
end
-- One frame at a time, protected: an error is logged and the window starts a fresh ImGui context (a frame cut short leaves the old one
-- unbalanced), instead of the whole window closing with a ReaScript error.
errors_in_a_row = 0
starts_next = 0
function loop()
  trial_over()
  if core.starts_missing and #core.starts_missing > 0 and reaper.time_precise() > starts_next then -- (installed through ReaPack since? started, and started with REAPER)
    starts_next = reaper.time_precise() + 3
    local ok, added, _, still = pcall(core.ensure_starts, core.starts_missing)
    if ok then core.starts_missing = still; if #added > 0 then say(table.concat(added, ", ") .. " installed: started, and starts with REAPER from now on.") end end
  end
  if reaper.time_precise() > sync_next and core.sync_folder() ~= "" then sync_step() end
  if quit_check and reaper.time_precise() > quit_check then
    quit_check = nil
    core.write(here .. "/install_cancelled", "quit was cancelled\n")
    if core.cancel_layers then core.cancel_layers() end -- (layer numbers back as installed: review round 1)
    say("REAPER didn't close, so the shortcuts weren't installed.")
  end
  if removing and not core.busy() then removing = nil; if not remove_finish() then return end end -- (My REAPER's windows are back)
  local ok, open = xpcall(frame, debug.traceback)
  errors_in_a_row = ok and 0 or errors_in_a_row + 1
  if not ok then
    if open ~= last_logged then core.log(open); last_logged = open end
    last_error = tostring(open):match("^[^\n]*"):gsub("^.-ReaPersona[/\\]", "")
    if errors_in_a_row >= 2 then -- (a page that fails every frame: back to the styles, so the window stays usable)
      page, selected = "DAWs", core.current().id
      reaper.SetExtState(SECTION, "page", page, false)
    end
    ctx = new_ctx()
    font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
    bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
    for k in pairs(images) do images[k] = nil end
    open = true
  end
  if open then reaper.defer(loop) end
end
-- ---------------------------------------------------------------- the screen-reader route (5.14)
-- ReaImGui draws its window itself, so NVDA, JAWS or VoiceOver (through OSARA) read nothing in it. This is REAPER's own menu (gfx.showmenu),
-- which they read, with the main tasks; every result comes in a message box, and OSARA speaks what say() says.
function show_menu(labels) -- -> the 1-based item picked (separators don't count), or 0
  local x, y = reaper.GetMousePosition()
  gfx.init("ReaPersona", 0, 0, 0, x, y)
  gfx.x, gfx.y = 0, 0
  local i = gfx.showmenu(table.concat(labels, "|"))
  gfx.quit()
  return i
end
function status_text()
  local cur, alt = core.current(), core.active_alt()
  local have, want = shortcuts_state()
  local wf = core.current_workflow()
  local t = { "Persona in use: " .. cur.name .. (in_use(cur, alt) and "" or " (its keys are off: pick it again)") .. (wf and (", with the workflow " .. wf.name .. " on top") or ""),
    "Shortcut layers installed: " .. have .. " of " .. want .. " personas" .. (have < want and " (install the shortcuts next)" or ""),
    "Persona back at REAPER's start: " .. (core.startup_on() and "yes" or "no (add the startup line)"),
    core.sync_folder() ~= "" and ("Syncing with your other computers through " .. core.sync_folder()) or "Not syncing with other computers." }
  local pend = core.restart_pending()
  if #pend > 0 then t[#t + 1] = "Waiting for REAPER to restart: " .. core.pending_words(pend) end
  return table.concat(t, "\n")
end
function screen_reader_menu(once) -- -> true: open the window instead. once: opened by 'ReaPersona - screen-reader menu'
  menu_mode = true
  local note = core.read(here .. "/last_install.txt")
  if note then os.remove(here .. "/last_install.txt"); reaper.MB(note, "ReaPersona: the last install", 0) end
  while true do
    local cur = core.current()
    local labels, acts = {}, {}
    local function item(label, fn) labels[#labels + 1] = (label:gsub("^[#!><]+", ""):gsub("|", "/"):gsub("&", "&&")); acts[#acts + 1] = fn end
    local function sep() labels[#labels + 1] = "" end
    item("Persona in use: " .. cur.name .. ". What's installed", function() reaper.MB(status_text(), "ReaPersona", 0) end)
    item("Pick a persona...", function()
      local names, list = {}, {}
      for _, st in ipairs(styles) do
        list[#list + 1] = st
        names[#names + 1] = (st == cur and "!" or "") .. (st.name:gsub("^[#!><]+", ""):gsub("|", "/"):gsub("&", "&&")) .. (st.user and " (yours)" or "")
      end
      local i = show_menu(names)
      if list[i] then selected = list[i].id; use(list[i]) end
    end)
    if cur.id ~= "my_reaper" then item("Back to My REAPER", function() use(core.by_id("my_reaper")) end) end
    local undo = last_style and last_style ~= cur.id and core.by_id(last_style)
    if undo then item("Undo switch: back to " .. undo.name, function() use(undo) end) end
    item("Save what I'm using as a persona...", save_preset_prompt)
    local wf = core.current_workflow()
    item("Workflow on top: " .. (wf and wf.name or "none") .. ". Pick a workflow...", function()
      local names, ids = { (wf and "" or "!") .. "None: the persona on its own" }, { "" }
      for _, x in ipairs(core.workflow_list()) do
        ids[#ids + 1] = x.id
        names[#names + 1] = (wf and wf.id == x.id and "!" or "") .. (x.name:gsub("^[#!><]+", ""):gsub("|", "/"):gsub("&", "&&")) .. (x.mine and " (yours)" or "")
      end
      local i = show_menu(names)
      if ids[i] then pick_workflow(ids[i]) end
    end)
    if wf and wf.project then
      item("New project with " .. wf.name, function() workflow_new_project(wf) end)
      if reaper.CountTracks(0) > 0 then item("Keep this project's track inputs for " .. wf.name .. " on this computer", function() workflow_keep_inputs(wf) end) end
    end
    if cur.project and not (wf and wf.project) then
      item("New project with " .. cur.name, function()
        if not core.fresh_project(0) then reaper.Main_OnCommand(41929, 0) end
        local done = core.apply_project(cur)
        say("A new project with " .. cur.name .. (#done > 0 and (": " .. table.concat(done, ", ")) or "") .. ".")
      end)
      if reaper.CountTracks(0) > 0 then
        item("Keep this project's track inputs for " .. cur.name .. " on this computer", function()
          local n = core.keep_inputs(cur.id)
          say("Kept the inputs of " .. n .. " track" .. (n == 1 and "" or "s") .. ": new projects with " .. cur.name .. " on this computer get them.")
        end)
      end
    end
    item("Cheat sheet for " .. cur.name .. " (opens in your browser)", function() local p, why = core.cheat_sheet(cur); if p then core.open_url(p) else say(why) end end)
    sep()
    local have, want = shortcuts_state()
    local pend = core.restart_pending()
    item(#pend > 0 and ("Restart REAPER to put in your persona shortcuts and " .. core.pending_words(pend)) or ((have < want and "Install" or "Reinstall") .. " the shortcuts (REAPER restarts)"), "install")
    if not core.startup_on() then item("Bring your persona back when REAPER starts (adds the startup line)", function() local ok, why = core.add_startup(); say(ok and "Startup line added." or tostring(why)) end) end
    sep()
    if core.sync_folder() ~= "" then item("Sync with your other computers now", function() sync_step(true) end)
    else item("Keep your computers the same through a shared folder...", choose_sync_folder) end
    item("Save your setup to a file...", save_setup_file)
    item("Load a setup file...", load_setup_file)
    sep()
    item("How ReaPersona works", function() reaper.MB(guide_text(), "ReaPersona: how it works", 0) end)
    item("Open ReaPersona's window", "window")
    if reaper.GetExtState(SECTION, "screen reader") == "1" then
      item("ReaPersona's own action opens the window from now on", function()
        reaper.SetExtState(SECTION, "screen reader", "0", true); say("ReaPersona's action opens its window from now on. The action 'ReaPersona - screen-reader menu' still opens this menu.")
      end)
    else
      item("ReaPersona's own action opens this menu from now on", function()
        reaper.SetExtState(SECTION, "screen reader", "1", true); say("ReaPersona's action opens this menu from now on.")
      end)
    end
    local fn = acts[show_menu(labels)]
    if not fn then return false end
    if fn == "window" then return true end
    if fn == "install" then install_shortcuts(); return false end
    said = nil
    fn()
    if said then reaper.MB(said, "ReaPersona", 0) end
    if not once and reaper.GetExtState(SECTION, "screen reader") ~= "1" then return false end
  end
end
if reaper.osara_outputMessage and reaper.GetExtState(SECTION, "screen reader") == "" then -- (OSARA installed: ask once)
  reaper.SetExtState(SECTION, "screen reader", reaper.MB("OSARA is installed, so you may be using a screen reader. ReaPersona's window can't be read by one; its menu can.\n\n" ..
    "Open the menu instead of the window each time? (The action 'ReaPersona - screen-reader menu' opens it either way.)", "ReaPersona", 4) == 6 and "1" or "0", true)
end
once = reaper.GetExtState(SECTION, "menu once") == "1" -- (the action 'ReaPersona - screen-reader menu': the menu, whatever the setting)
reaper.DeleteExtState(SECTION, "menu once", false)
from_menu = once or reaper.GetExtState(SECTION, "screen reader") == "1"
if from_menu and not screen_reader_menu(once) then
  local function wait_quit() -- (the install's quit, cancelled: the batch step or the Python is told, as loop() does for the window)
    if not quit_check then return end
    if reaper.time_precise() < quit_check then return reaper.defer(wait_quit) end
    quit_check = nil
    core.write(here .. "/install_cancelled", "quit was cancelled\n")
    if core.cancel_layers then core.cancel_layers() end
    reaper.MB("REAPER didn't close, so the shortcuts weren't installed.", "ReaPersona", 0)
  end
  wait_quit()
  return
end
menu_mode = false
if from_menu then -- (the window from the menu: ReaImGui let go of the context made at the start while the menu was open, unused)
  ctx = new_ctx()
  font = ImGui.CreateFont("sans-serif"); ImGui.Attach(ctx, font)
  bold = ImGui.CreateFont("sans-serif", ImGui.FontFlags_Bold); ImGui.Attach(ctx, bold)
end
cmd = select(4, reaper.get_action_context()) -- (the picker's own action: lit on a toolbar while the window is open)
if cmd and cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, 1); reaper.RefreshToolbar2(0, cmd) end
-- (a preview left by an earlier window, or a persona in use that no longer exists: what you had goes back, never a silent "My REAPER")
if core.is_trial and core.is_trial() and not bld.back and core.end_trial then pcall(core.end_trial) end
do local sid = reaper.GetExtState(SECTION, "style"); if sid ~= "" and not core.by_id(sid) and core.by_id("my_reaper") then pcall(core.use, core.by_id("my_reaper")) end end
reaper.atexit(function()
  if bld.back or (core.is_trial and core.is_trial()) then -- (a preview or Try it ends when the window closes: what you had goes back. Review 2026-11-19)
    local ok, e = pcall(bld_end_trial, true) -- (true: queued window moves can't wait for a frame that won't come)
    if not ok then pcall(core.log, "closing a preview: " .. tostring(e)) end
  end
  if trying then trying.ends = 0; trial_over() end -- (a theme on trial goes back when the window closes)
  pcall(colours.put_back_all) -- (and colours being tried)
  pcall(core.sync_tick) -- (what you changed while it was open, to your other computers)
  if cmd and cmd ~= 0 then reaper.SetToggleCommandState(0, cmd, 0); reaper.RefreshToolbar2(0, cmd) end
end)
pcall(core.upgrade_startup) -- (now too, not only at REAPER's start: updated and removed in one session left the old block. Review, 5.9.4)
reaper.defer(loop)
