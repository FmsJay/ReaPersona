-- ReaPersona's window: the Shortcuts editor.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 2281-2502.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
-- Shortcuts (5.30; James: "add individually ones from other daws or personas into your own persona ... make your own based on custom
-- actions and change keybinds of any already in there ... All keybinds should show here, the most commonly used first ... Can filter by
-- specific action types or scripts"). Your persona's keys, each to leave out, change (press the new keys) or remove; a key of your own for
-- any action; and every key there is (core.catalog), each to add.
do -- (the Shortcuts editor: its own scope)
local kq = { kind = "All", source = "All", section = "All", shown = 120, cat = nil, add = { q = "", cmd = nil, name = nil, spec = nil }, cap = nil }
bld.kq = kq -- (draft_tick: no undo while a key is being captured)
local rp = { data = nil, read = false } -- (5.31: REAPER's "Mouse modifier keys and action shortcuts" page: every key, its defaults too, and every mouse action)
function read_rpage(make) -- make: REAPER writes it first (Help: Mouse modifier keys and action shortcuts, which also opens it in the browser)
  if make then reaper.Main_OnCommand(40308, 0) end
  local path = core.shortcut_page_path()
  rp.data, rp.read, kq.cat = path and core.parse_shortcut_page(core.read(path)) or nil, true, nil
  return rp.data
end
function rpage() if not rp.read then read_rpage(false) end return rp.data end
local function reaper_keys() -- REAPER's own keys off its page, with their command ids found by name
  local d = rpage()
  if not d then return nil end
  local by, out = {}, {}
  for _, a in ipairs(core.action_list()) do by[a[2]] = by[a[2]] or a[1] end
  for _, k in ipairs(d.keys) do local c = by[k[2]]; if c then out[#out + 1] = { k[1], c, k[2], k[3] } end end
  return out
end
local CAP
local function cap_keys() -- ReaImGui's keys, as the key names styles.json and the installer use
  if CAP then return CAP end
  CAP = {}
  local function k(name, as) if ImGui["Key_" .. name] then CAP[#CAP + 1] = { ImGui["Key_" .. name], as } end end
  for c = 65, 90 do k(string.char(c), string.char(c)) end
  for d = 0, 9 do k(tostring(d), tostring(d)); k("Keypad" .. d, "Num" .. d) end
  for i = 1, 12 do k("F" .. i, "F" .. i) end
  for _, x in ipairs({ { "Space", "Space" }, { "Enter", "Enter" }, { "Tab", "Tab" }, { "Backspace", "Backspace" }, { "Delete", "Delete" }, { "Insert", "Insert" },
      { "Home", "Home" }, { "End", "End" }, { "PageUp", "PgUp" }, { "PageDown", "PgDn" }, { "LeftArrow", "Left" }, { "RightArrow", "Right" }, { "UpArrow", "Up" },
      { "DownArrow", "Down" }, { "Comma", "," }, { "Period", "." }, { "Slash", "/" }, { "Semicolon", ";" }, { "Apostrophe", "'" }, { "Minus", "-" },
      { "Equal", "=" }, { "LeftBracket", "[" }, { "RightBracket", "]" }, { "Backslash", "\\" }, { "GraveAccent", "`" }, { "KeypadEnter", "NumEnter" },
      { "KeypadAdd", "Num+" }, { "KeypadSubtract", "Num-" }, { "KeypadMultiply", "Num*" }, { "KeypadDivide", "Num/" }, { "KeypadDecimal", "Num." } }) do k(x[1], x[2]) end
  return CAP
end
local function capture() -- -> the keys pressed ("Ctrl+Shift+K"), false for Esc, nil while waiting
  if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then return false end
  local m = ImGui.GetKeyMods(ctx)
  for _, x in ipairs(cap_keys()) do
    if ImGui.IsKeyPressed(ctx, x[1], false) then
      local mods = {}
      if m & ImGui.Mod_Ctrl ~= 0 then mods[#mods + 1] = "Ctrl" end
      if m & ImGui.Mod_Alt ~= 0 then mods[#mods + 1] = "Alt" end
      if m & ImGui.Mod_Shift ~= 0 then mods[#mods + 1] = "Shift" end
      if ImGui.Mod_Super and m & ImGui.Mod_Super ~= 0 then mods[#mods + 1] = "Win" end
      mods[#mods + 1] = x[2]
      return table.concat(mods, "+")
    end
  end
end
local function keys_block_here() -- the persona's shortcuts block, made (your own keys) when there's none yet
  local b = core.draft_get(bld.blocks, "keys")
  if not b then b = core.keys_block("my_reaper"); core.draft_add(bld.blocks, b) end
  bld.active = true
  b.extra = type(b.extra) == "table" and b.extra or {}
  return b
end
local function add_key(spec, cmd, name)
  if not core.encode(spec) then return say(tostring(spec) .. " isn't a key REAPER can take.") end
  local b = keys_block_here()
  for i = #b.extra, 1, -1 do if core.canon(b.extra[i][1]) == core.canon(spec) then table.remove(b.extra, i) end end
  b.extra[#b.extra + 1] = { spec, cmd, name }
  say(keyname(spec) .. " runs " .. tostring(name) .. " in your persona (it replaces anything else on that key there).")
end
local function cap_button(id, label, on_keys)
  if kq.cap == id then
    ImGui.TextColored(ctx, C.YELLOW, "Press the keys now (Esc cancels)")
    local got = capture()
    if got == false then kq.cap = nil elseif got then kq.cap = nil; on_keys(got) end
  elseif ImGui.SmallButton(ctx, label .. "##cap" .. id) then kq.cap = id end
end
function persona_keys_card()
  if not card("pkeys") then return end
  heading("Your persona's shortcuts", 16)
  muted("Load a persona's keys, then leave any out, change any (press the new keys), or add keys from Every shortcut below or for any action. Its mouse wheel is on Mouse & trackpad.")
  ImGui.Indent(ctx, IND * UI)
  local b = core.draft_get(bld.blocks, "keys")
  local from = b and core.by_id(b.id)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  if ImGui.BeginCombo(ctx, "##keysfrom", b and (b.id == "my_reaper" and "Your own shortcuts" or (from and from.name or tostring(b.id))) or "Your own shortcuts") then
    if ImGui.Selectable(ctx, "Your own shortcuts##kown", b == nil or b.id == "my_reaper") then core.draft_add(bld.blocks, core.keys_block("my_reaper")); bld.active = true end
    for _, st in ipairs(sources(function(s) return #(s.keys or {}) > 0 end)) do
      if ImGui.Selectable(ctx, st.name .. "##kf" .. st.id, b ~= nil and b.id == st.id) then
        local nb = core.keys_block(st.id); nb.extra = b and b.extra or nil -- (keys you added stay)
        core.draft_add(bld.blocks, nb); bld.active = true
      end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "Loads that persona's or DAW's keys. Keys you added stay. Choosing here starts a new persona if you're not making one.")
  if b then
    local lines, count = core.build_preview({ b })[1], {}
    for _, e in ipairs(lines) do if e.kind == "key" and not e.off then count[core.canon(e.key)] = (count[core.canon(e.key)] or 0) + 1 end end
    ImGui.SetNextItemWidth(ctx, 240 * UI)
    local _, f = ImGui.InputTextWithHint(ctx, "##pkf", "search its keys or actions", kq.pfilter or ""); kq.pfilter = f
    local q = (kq.pfilter or ""):lower()
    if ImGui.BeginTable(ctx, "pkeys", 4, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 300 * UI) then
      ImGui.TableSetupColumn(ctx, "on", ImGui.TableColumnFlags_WidthFixed, 28 * UI)
      ImGui.TableSetupColumn(ctx, "Key", ImGui.TableColumnFlags_WidthFixed, 190 * UI)
      ImGui.TableSetupColumn(ctx, "Action", ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed, 150 * UI)
      for _, e in ipairs(lines) do
        if (e.kind == "key" or e.kind == "midi") and (q == "" or tostring(e.key):lower():find(q, 1, true) or tostring(e.label):lower():find(q, 1, true)) then
          ImGui.PushID(ctx, e.slot)
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          local ch, v = ImGui.Checkbox(ctx, "##on", not e.off)
          if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
          ImGui.TableNextColumn(ctx)
          keycap(e.key)
          if e.kind == "key" and not e.off and (count[core.canon(e.key)] or 0) > 1 then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.YELLOW, "twice") end
          ImGui.TableNextColumn(ctx)
          ImGui.TextColored(ctx, e.off and C.MUTED or C.TEXT, tostring(e.label) .. (e.extra and "   (added)" or "") .. (e.kind == "midi" and "   (MIDI editor)" or "")
            .. (e.moved_from and ("   (was " .. keyname(e.moved_from) .. ")") or ""))
          ImGui.TableNextColumn(ctx)
          if e.kind == "key" then
            cap_button(e.slot, "Change", function(spec)
              if not core.encode(spec) then return say(spec .. " isn't a key REAPER can take.") end
              if e.extra then b.extra[e.extra][1] = spec
              else b.rebind = type(b.rebind) == "table" and b.rebind or {}; b.rebind[core.canon(e.moved_from or e.key)] = spec end
              say(tostring(e.label) .. " is on " .. keyname(spec) .. " in your persona.")
            end)
            if e.extra then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Remove") then table.remove(b.extra, e.extra) end
            elseif e.moved_from then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Undo") then b.rebind[core.canon(e.moved_from)] = nil end end
          end
          ImGui.PopID(ctx)
        end
      end
      ImGui.EndTable(ctx)
    end
  end
  -- a key of your own for any action (custom actions and scripts included)
  ImGui.Dummy(ctx, 0, 4)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Add a shortcut for any action:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  local _, aq = ImGui.InputTextWithHint(ctx, "##addq", "search REAPER's actions, scripts, custom actions", kq.add.q); kq.add.q = aq
  if kq.add.name then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.ACCENT, kq.add.name) end
  if #aq >= 2 and aq ~= kq.add.name then
    local found = core.find_actions(aq, 12)
    for _, a in ipairs(found) do
      if ImGui.Selectable(ctx, tostring(a[2]) .. "##act" .. tostring(a[1])) then kq.add.cmd, kq.add.name, kq.add.q = a[1], a[2], a[2] end
    end
    if #found == 0 then muted("No action has that in its name.") end
  end
  if kq.add.cmd then
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Key:"); ImGui.SameLine(ctx)
    if kq.add.spec then keycap(kq.add.spec); ImGui.SameLine(ctx) end
    cap_button("add", kq.add.spec and "Change" or "Press keys", function(spec) kq.add.spec = spec end)
    if kq.add.spec then
      ImGui.SameLine(ctx)
      if primary("Add to my persona##addk") then add_key(kq.add.spec, kq.add.cmd, kq.add.name); kq.add = { q = "", cmd = nil, name = nil, spec = nil } end
    end
  end
  ImGui.Unindent(ctx, IND * UI)
  card_end()
end
local KINDS = { "All", "REAPER action", "Script", "Custom action", "SWS / extension" }
local function shortcuts_catalog()
  if not card("allkeys") then return end
  heading("Every shortcut", 16)
  muted("Every persona's keys and your own keymap's (keys you, a script or an extension set), the actions most personas use first. Add any to your persona.")
  if keys_for then local st = core.by_id(keys_for); if st then kq.source = st.name end; keys_for = nil end -- (from search)
  if not kq.cat then kq.cat = core.catalog(styles, core.read(reaper.GetResourcePath() .. "/reaper-kb.ini") or "", reaper_keys()) end
  if not rpage() then ImGui.TextColored(ctx, C.YELLOW, "REAPER's own keys (its defaults too) haven't been read on this computer yet.") ImGui.SameLine(ctx) end
  if ImGui.SmallButton(ctx, (rpage() and "Read REAPER's keys again" or "Read REAPER's keys") .. "##rpk") then read_rpage(true) end
  ImGui.SetItemTooltip(ctx, "REAPER lists every key it has, its defaults included, with Help > Mouse modifier keys and action shortcuts, which also opens the list in your browser.")
  ImGui.SetNextItemWidth(ctx, 220 * UI)
  local _, f = ImGui.InputTextWithHint(ctx, "##kf", "search keys or actions", filter); filter = f
  local function combo(id, cur, list, set, label)
    ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 190 * UI)
    if ImGui.BeginCombo(ctx, id, label .. ": " .. cur) then for _, x in ipairs(list) do if ImGui.Selectable(ctx, x .. id, x == cur) then set(x) end end ImGui.EndCombo(ctx) end
  end
  combo("##kind", kq.kind, KINDS, function(x) kq.kind = x end, "Type")
  local srcs = { "All", "Your keymap" }
  for _, st in ipairs(styles) do if #(st.keys or {}) > 0 and not st.keys_from then srcs[#srcs + 1] = st.name end end
  combo("##src", kq.source, srcs, function(x) kq.source = x end, "From")
  combo("##sec", kq.section, { "All", "Main", "MIDI editor" }, function(x) kq.section = x end, "Section")
  ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Refresh##kcat") then kq.cat = nil end
  local q, n, total = filter:lower(), 0, 0
  if ImGui.BeginTable(ctx, "allk", 5, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 360 * UI) then
    ImGui.TableSetupColumn(ctx, "Key", ImGui.TableColumnFlags_WidthFixed, 170 * UI)
    ImGui.TableSetupColumn(ctx, "Action", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "From", ImGui.TableColumnFlags_WidthStretch, 0.6)
    ImGui.TableSetupColumn(ctx, "Type", ImGui.TableColumnFlags_WidthFixed, 110 * UI)
    ImGui.TableSetupColumn(ctx, "add", ImGui.TableColumnFlags_WidthFixed, 44 * UI)
    ImGui.TableHeadersRow(ctx)
    for i, r in ipairs(kq.cat or {}) do
      local ok = (kq.kind == "All" or r.kind == kq.kind) and (kq.section == "All" or r.section == kq.section)
      if ok and kq.source ~= "All" then ok = false; for _, s in ipairs(r.sources) do if s == kq.source then ok = true end end end
      if ok and q ~= "" then ok = r.spec:lower():find(q, 1, true) or r.name:lower():find(q, 1, true) or table.concat(r.sources, " "):lower():find(q, 1, true) end
      if ok then
        total = total + 1
        if n < kq.shown then
          n = n + 1
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); keycap(r.spec)
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, r.name .. (r.section == "MIDI editor" and "   (MIDI editor)" or ""))
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, #r.sources > 3 and (r.sources[1] .. ", " .. r.sources[2] .. " and " .. (#r.sources - 2) .. " more") or table.concat(r.sources, ", "))
          if #r.sources > 3 then ImGui.SetItemTooltip(ctx, table.concat(r.sources, ", ")) end
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, r.kind)
          ImGui.TableNextColumn(ctx)
          ImGui.BeginDisabled(ctx, r.section ~= "Main")
          if ImGui.SmallButton(ctx, "Add##ak" .. i) then add_key(r.spec, r.cmd, r.name) end
          ImGui.EndDisabled(ctx)
        end
      end
    end
    ImGui.EndTable(ctx)
  end
  muted(n .. " of " .. total .. " shown")
  if total > n then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show more##kmore") then kq.shown = kq.shown + 200 end end
  card_end()
end
function shortcuts_page() persona_keys_card(); shortcuts_catalog() end
end
