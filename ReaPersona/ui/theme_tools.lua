-- ReaPersona's window: Themes > Adjust and Build one.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 1302-1466.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
adjust_out = false -- (Adjust in its own window)
function adjust_page(sel)
  local lt = core.loaded_theme()
  if changed_on ~= lt then changed, changed_on = {}, lt end -- (tweaks made on another theme don't carry over)
  local current = core.loaded_theme() or ""
  if card("adj top") then
    heading("Adjust the theme in use")
    muted(current)
    if not adjust_out and ImGui.Button(ctx, "Pop out") then adjust_out = true end
    if not adjust_out then ImGui.SetItemTooltip(ctx, "This page in a window of its own, to keep open beside REAPER while you tweak.") ImGui.SameLine(ctx) end
    if ImGui.Button(ctx, "REAPER's theme adjuster") then reaper.Main_OnCommand(42234, 0) end
    ImGui.SetItemTooltip(ctx, "REAPER's own Theme Adjuster window (Options > Themes > Theme adjuster).")
    ImGui.TextWrapped(ctx, "Everything here changes the look right away. The theme's own settings and layouts are kept by REAPER as you go; colours are kept when you press Save my version.")
    if ImGui.Button(ctx, "Put this theme's settings in my persona##adjin") then -- (5.35)
      local b = core.new_block("themeset")
      if b.set then core.draft_add(bld.blocks, b); bld.active = true; say("In your persona: " .. core.themeset_words(b.set) .. ". Its theme is the one it applies to.")
      else say("This theme's settings are all its own defaults, and it has no layouts chosen: nothing to put in.") end
    end
    ImGui.SetItemTooltip(ctx, "The settings above that differ from the theme's own, and the layouts chosen below, go into the persona you're making. Used only with this theme; your theme's own settings aren't changed.")
    local tb = core.draft_get(bld.blocks, "themeset")
    if tb and core.safe_themeset(tb.set) then
      ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "In your persona: " .. core.themeset_words(core.safe_themeset(tb.set)))
      ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave out##adjout") then core.draft_clear(bld.blocks, "themeset") end
    end
    card_end()
  end
  if card("adj params") then
    heading("This theme's settings")
    local any, shown = false, 0
    for i = 0, 400 do
      local name, desc, val, def, mn, mx = reaper.ThemeLayout_GetParameter(i)
      if not name or name == "" then break end
      if not any then
        ImGui.SetNextItemWidth(ctx, 260)
        local _, f = ImGui.InputTextWithHint(ctx, "##pf", "search settings (a theme can have hundreds)", pfilter)
        pfilter = f
        any = true
      end
      local label = desc ~= "" and desc or name
      if (pfilter == "" and shown < 40) or (pfilter ~= "" and (label:lower():find(pfilter:lower(), 1, true) or name:lower():find(pfilter:lower(), 1, true))) then
        shown = shown + 1
        ImGui.SetNextItemWidth(ctx, 260)
        local ch, v = ImGui.SliderInt(ctx, label .. "##p" .. i, val, mn, mx)
        if ch then reaper.ThemeLayout_SetParameter(i, v, true); refresh() end
        if ImGui.IsItemClicked(ctx, 1) then reaper.ThemeLayout_SetParameter(i, def, true); refresh() end
        ImGui.SetItemTooltip(ctx, "Right-click: back to the theme's own value (" .. def .. ").")
      end
    end
    if any and pfilter == "" and shown >= 40 then ImGui.TextDisabled(ctx, "The first 40 shown: search to find the rest.") end
    if not any then muted("This theme has no adjustable settings of its own; its layouts and colours are below. (Build one can put its colours on a theme that has them.)") end
    card_end()
  end
  if card("adj layouts") then
    heading("Layouts")
    for s = 0, 40 do
      local ok, sec = reaper.ThemeLayout_GetLayout("seclist", s)
      if not ok or sec == "" then break end
      local _, desc = reaper.ThemeLayout_GetLayout(sec, -2)
      local _, cur = reaper.ThemeLayout_GetLayout(sec, -1)
      local names = {}
      for j = 0, 60 do local o, n = reaper.ThemeLayout_GetLayout(sec, j); if not o then break end if n ~= "" then names[#names + 1] = n end end
      if #names > 0 then
        ImGui.SetNextItemWidth(ctx, 260)
        if ImGui.BeginCombo(ctx, (desc ~= "" and desc or sec) .. "##l" .. sec, cur ~= "" and cur or "(theme default)") then
          if ImGui.Selectable(ctx, "(theme default)", cur == "") then reaper.ThemeLayout_SetLayout(sec, ""); refresh() end
          for _, n in ipairs(names) do if ImGui.Selectable(ctx, n, n == cur) then reaper.ThemeLayout_SetLayout(sec, n); refresh() end end
          ImGui.EndCombo(ctx)
        end
      end
    end
    card_end()
  end
  if card("adj colours") then
    heading("Colours")
    for _, c in ipairs(COLOURS) do
      local native = reaper.GetThemeColor(c[1], 0)
      if native >= 0 then
        local r, g, b = reaper.ColorFromNative(native)
        local ch, rgb = ImGui.ColorEdit3(ctx, c[2] .. "##c" .. c[1], (r << 16) | (g << 8) | b, ImGui.ColorEditFlags_NoInputs)
        if ch then
          local n = reaper.ColorToNative((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
          reaper.SetThemeColor(c[1], n, 0)
          changed[c[1]] = n
          refresh()
        end
      end
    end
    ImGui.Dummy(ctx, 0, 2)
    local n = 0
    for _ in pairs(changed) do n = n + 1 end
    ImGui.BeginDisabled(ctx, n == 0)
    if primary(n > 0 and ("Save my version (" .. n .. " colour" .. (n == 1 and "" or "s") .. ")") or "Save my version", accent_of(sel)) then
      local name, why = save_fork(sel, current)
      reaper.MB(name and ("Saved as " .. name .. ".\n\n" .. (core.is_trial() and "It's the theme of the persona you're making now (Save it from the bar at the top), and in use."
        or "It's in this persona's Theme list now, and in use.")) or ("Not saved: " .. tostring(why)), "ReaPersona", 0)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Undo colour changes") then
      for key in pairs(changed) do reaper.SetThemeColor(key, -1, 0) end
      changed = {}
      refresh()
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Every colour...") and not run_script("X-Raym Scripts/Theme/X-Raym_Theme color tweaker_ReaImGui.lua") then
      say("That needs X-Raym's Theme color tweaker: ReaPack, X-Raym Scripts.")
      if reaper.ReaPack_BrowsePackages then reaper.ReaPack_BrowsePackages("Theme color tweaker") end
    end
    ImGui.SetItemTooltip(ctx, "All of the theme's colours, in X-Raym's colour tweaker.")
    card_end()
  end
end

function theme_combo(label, key, allow_none)
  ImGui.SetNextItemWidth(ctx, math.min(420, ImGui.GetContentRegionAvail(ctx) - 180))
  if ImGui.BeginCombo(ctx, label, merge[key] ~= "" and merge[key] or "(none)") then
    if allow_none and ImGui.Selectable(ctx, "(none)", merge[key] == "") then merge[key] = "" end
    for _, f in ipairs(merge.list) do
      if (key ~= "base" and key ~= "graphics") or f:match("Zip$") then
        if ImGui.Selectable(ctx, f, f == merge[key]) then merge[key] = f end
      end
    end
    ImGui.EndCombo(ctx)
  end
end
function merge_page(sel)
  merge.list = merge.list or theme_files()
  if merge.colours == "" then merge.colours = core.theme_for(sel) or "" end
  if card("merge") then
    heading("Build a theme from others")
    muted("Build a theme from the best parts of others. The layout theme gives the layout and every image (pick one with its own settings, like Default 7 or CSIX, and Adjust keeps working on the result); the colours theme gives the colours; graphics can swap in another theme's faders, knobs, meters or buttons where the layout theme has the same images. The result is a new theme of your own in ColorThemes, kept on this computer.")
    ImGui.Dummy(ctx, 0, 2)
    theme_combo("Layout and images from##mb", "base")
    theme_combo("Colours from##mc", "colours")
    local _, f = ImGui.Checkbox(ctx, "Fonts from the colours theme too", merge.fonts); merge.fonts = f
    theme_combo("Graphics from (optional)##mg", "graphics", true)
    if merge.graphics ~= "" then
      ImGui.Indent(ctx)
      for i, p in ipairs(PARTS) do
        if (i - 1) % 4 ~= 0 then ImGui.SameLine(ctx) end
        local _, v = ImGui.Checkbox(ctx, p, merge.parts[p] == true); merge.parts[p] = v
      end
      ImGui.Unindent(ctx)
    end
    ImGui.Dummy(ctx, 0, 2)
    ImGui.BeginDisabled(ctx, merge.base == "" or merge.colours == "")
    if primary("Make it, and use it", accent_of(sel)) then
      local parts = {}
      for _, p in ipairs(PARTS) do if merge.parts[p] then parts[#parts + 1] = p end end
      local name, why = core.merge(themes_dir .. merge.base, themes_dir .. merge.colours, merge.graphics ~= "" and themes_dir .. merge.graphics or nil, parts, merge.fonts)
      if name then
        reaper.OpenColorThemeFile(themes_dir .. name)
        local cur = core.current() -- (the theme goes on now, so it belongs to the style in use)
        add_fork(cur, name)
        merge.list = nil
        merge.msg = "Made " .. name .. ", in use, and " .. (core.is_trial() and "the theme of the persona you're making (Save it from the bar at the top)." or ("in " .. cur.name .. "'s Theme list."))
      else merge.msg = "Couldn't merge: " .. tostring(why) end
    end
    ImGui.EndDisabled(ctx)
    if merge.msg ~= "" then ImGui.TextWrapped(ctx, merge.msg) end
    ImGui.Dummy(ctx, 0, 2)
    muted("Most Stash themes carry no licence: share a merged theme only with its authors' permission.")
    card_end()
  end
end
