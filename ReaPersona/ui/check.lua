-- ReaPersona's window: Help > Check and repair, and the key dump.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 1467-1599.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
-- (in R: keys_for) -- (the style the Shortcuts page shows: its own pick, else the one in use)
function keys_page() shortcuts_page() end -- (5.30: the editor, defined with the persona being made)

function dump(section, file)
  local out = {}
  for i = 0, 200000 do
    local id, name = reaper.CF_EnumerateActions(section, i, "")
    if not id or id <= 0 then break end
    out[#out + 1] = id .. "\t" .. name
  end
  core.write(here .. "/" .. file, table.concat(out, "\n") .. "\n")
  return #out
end
function status_line(ok, text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, ok and C.GREEN or C.YELLOW); ImGui.Text(ctx, ok and "OK" or "Not yet"); ImGui.PopStyleColor(ctx)
  ImGui.SameLine(ctx); ImGui.Text(ctx, text)
end
function check_page()
  if card("check installed") then
    heading("Installed")
    muted("Shortcut layers go into REAPER's keymap with REAPER closed (it reads its keymap at start): " .. INSTALL_WHERE .. ", after adding or changing a persona.")
    for _, st in ipairs(styles) do
      if (st.alt or 0) > 0 then
        local n = installed[st.alt] or 0
        local want = #core.keys_here(st.keys) -- (a key for the other system isn't installed here)
        status_line(n >= want, string.format("%s: %d of %d keys", st.name, n, want))
      end
    end
    local specs = {}
    for _, st in ipairs(styles) do for _, k in ipairs(st.midi_keys or {}) do specs[k[1]] = true end end
    local want = 0
    for _ in pairs(specs) do want = want + 1 end
    status_line(midi_installed >= want, string.format("MIDI editor keys: %d of %d", midi_installed, want))
    status_line(core.scripts_missing() == 0, "One-key actions registered: " .. (core.scripts_missing() == 0 and "yes" or (core.scripts_missing() .. " missing")))
    card_end()
  end
  if card("check install") then
    heading("Install the shortcuts")
    muted("REAPER reads its keymap when it starts, so the shortcut layers go in once, after adding or changing a persona. Two ways:")
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "In one step: " .. INSTALL_WHERE .. " (Windows, Mac or Linux; no Python needed). REAPER closes, the layers and the personas' toolbars go in, your keymap is backed up first, and REAPER opens again. By hand: close REAPER, run install_shortcuts.py in this folder, start REAPER.")
    if ImGui.SmallButton(ctx, "Show the folder") then core.open_url(core.here) end
    ImGui.Bullet(ctx); ImGui.SameLine(ctx); ImGui.TextWrapped(ctx, "Without restarting: make a keymap file, then in REAPER's Actions window open Key Map > Import... and pick it (choose to merge, not replace). Toolbars aren't included: personas keep your own toolbar.")
    if ImGui.SmallButton(ctx, "Make the keymap file") then
      local path, n, skipped = core.make_keymap()
      if not path then reaper.MB("No keymap made: " .. tostring(skipped[1]), "ReaPersona", 0) -- (no early return: the card must close. Review 2026-11-18)
      else
        reaper.MB(n .. " shortcuts written to\n" .. path .. (#skipped > 0 and ("\n\nSkipped (no action here yet): " .. table.concat(skipped, ", ")) or "") ..
          "\n\nNext: Actions window > Key Map > Import..., pick that file, and choose to merge.", "ReaPersona", 0)
        reaper.Main_OnCommand(40605, 0)
      end
    end
    card_end()
  end
  if card("check run") then
    heading("Check every persona against this REAPER")
    if ImGui.Button(ctx, "Check") then
      local bad = {}
      for _, st in ipairs(styles) do
        for _, k in ipairs(st.midi_keys or {}) do
          for _, name in ipairs(type(k[2]) == "table" and k[2] or { k[2] }) do
            if type(name) == "string" and not core.midi_action(name) then bad[#bad + 1] = st.name .. " MIDI " .. k[1] .. ": no action '" .. name .. "'" end
          end
        end
        for _, k in ipairs(st.keys or {}) do
          if type(k[2]) == "number" and (reaper.CF_GetCommandText(0, k[2]) or "") == "" then bad[#bad + 1] = st.name .. " " .. k[1] .. ": no action " .. k[2] end
        end
        for _, x in ipairs(st.feel or {}) do
          if x[1] == "toggle" and reaper.GetToggleCommandState(core.cmd_id(x[2])) < 0 then bad[#bad + 1] = st.name .. ": " .. tostring(x[2]) .. " has no on/off state" end
        end
      end
      local na, nb = dump(0, "actions_main.tsv"), dump(32060, "actions_midi.tsv")
      -- (REAPER's own MIDI editor bindings for the styles' keys, for the My REAPER fallback: only readable before those keys are installed)
      local d = midi_installed == 0 and (core.midi_defaults() .. " MIDI editor defaults saved; now install the shortcuts (Home).") or ""
      check_msg = (#bad == 0 and "Everything resolves." or table.concat(bad, "\n")) .. string.format("\n(Action lists saved for validate.py: %d main, %d MIDI editor.) ", na, nb) .. d
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Register actions again") then check_msg = core.ensure_scripts(true) .. " ReaPersona actions registered (scripts.json)." end
    ImGui.SetItemTooltip(ctx, "Writes and registers the one-key actions: 'ReaPersona - use <style>', 'next style', 'restore last style', and the MIDI key scripts. Put 'use' actions on a toolbar: they light up for the style in use.")
    if check_msg ~= "" then ImGui.TextWrapped(ctx, check_msg) end
    card_end()
  end
  if card("check anywhere") then
    heading("Switch from anywhere")
    muted("Actions list (a style there is a persona): 'ReaPersona - next style' cycles through the personas; 'ReaPersona - use <style>' picks one (toolbar buttons light up for the persona in use). REAPER forgets a persona's shortcuts when it restarts; the startup line runs 'ReaPersona - restore last style' to put them back.")
    card_end()
  end
end

-- ---------------------------------------------------------------- the window: a bar on top, pages down the side
-- ---------------------------------------------------------------- Setup: everything ReaPersona can use, what's there, and one click for each
-- (in R: daws_found) -- (other DAWs on this computer, looked for once)
function drop_report(list) -- what came in, in a few lines (a pack's leftover files are one line, not one each)
  local lines, n, themes = {}, 0, {}
  for _, r in ipairs(list) do
    if r[1] ~= "skipped" and r[1] ~= "note" then n = n + 1 end
    if r[1] == "theme" then themes[#themes + 1] = r[2]:gsub("%.ReaperTheme.*$", "") end
    local head = r[1] == "skipped" and "Left out: " or r[1] == "note" and "Note: " or ("Added " .. ((r[1] == "style" or r[1] == "preset") and "persona" or r[1]) .. ": ")
    if #lines < 12 then lines[#lines + 1] = head .. r[2] .. (r[3] and ("  (" .. r[3] .. ")") or "") end
  end
  if #list > 12 then lines[#lines + 1] = "...and " .. (#list - 12) .. " more" end
  theme_list = nil
  if #themes > 0 then lines[#lines + 1] = "\nThemes are under Themes > Your themes, at the top (marked new)." end
  say(n .. " added" .. (#themes > 0 and (": " .. table.concat(themes, ", ")) or ""))
  if #list > 0 then reaper.MB(table.concat(lines, "\n"), "ReaPersona: added", 0) end
  local stages = {}
  for _, r in ipairs(list) do -- (a pack's fonts and scripts: installed only on a yes)
    if r.stage then stages[r.stage] = true end
    if r[2] == "fonts" and r.files and reaper.MB("Install the " .. #r.files .. " font" .. (#r.files == 1 and "" or "s") .. " the theme uses?\n\nThey go into your own account's fonts " ..
        "(no administrator needed). REAPER uses them after a restart.", "ReaPersona: fonts", 4) == 6 then
      local n, why = core.install_fonts(r.files)
      say(n and (n .. " font" .. (n == 1 and "" or "s") .. " installed. Restart REAPER to see them in the theme.") or ("Fonts not installed: " .. tostring(why)))
    elseif r[2] == "scripts" and r.files and reaper.MB("Add the pack's " .. #r.files .. " script" .. (#r.files == 1 and "" or "s") .. " (a theme adjuster, say) to REAPER's Actions list?\n\n" ..
        "They're the theme author's own scripts; they go in Scripts/ReaPersona theme scripts.", "ReaPersona: scripts", 4) == 6 then
      local names = core.register_scripts(r.files, r.stage)
      say(#names > 0 and ("In the Actions list now: " .. table.concat(names, ", ")) or "No scripts added.")
    end
  end
  for st in pairs(stages) do core.forget_staged(st) end
end
function install_theme_ui(th, st, pick) -- one click: download, take in (fonts and scripts on a yes), and with pick make it st's theme
  local got, why = core.install_theme(th)
  if not got then
    say("Couldn't install " .. th:gsub("%.ReaperTheme%a*$", "") .. ": " .. tostring(why) .. ". Its page opens instead.")
    local c = core.CATALOG[th]
    if c and c.url and c.url:match("^https?:") then core.open_url(c.url) end
    return
  end
  drop_report(got)
  if pick and st and reaper.file_exists(themes_dir .. th) then
    reaper.SetExtState(SECTION, "theme " .. st.id, th, true)
    if core.current() == st then trying = nil; reaper.OpenColorThemeFile(themes_dir .. th) end
  end
end
