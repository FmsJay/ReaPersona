-- ReaPersona's window: the Mouse & trackpad editor.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 2503-2776.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
-- Mouse & trackpad (5.31; James: "Same thing should happen for mouse/trackpad - shows what all the mouse commands do, lets you edit them or
-- add your own as well"). Your persona's wheel, trackpad swipe, drags and clicks, each to leave out, change or remove; your own; and every
-- mouse action REAPER has (its own page, rpage) and every persona's.
-- (in R: mouse_page)
do -- (the Mouse & trackpad editor: its own scope)
local mq = { area = "All", source = "All", shown = 150, cat = nil, kind = "drag", ctx = "MM_CTX_ITEM", mods = 0, wheel = "Mousewheel", act = "", pick = nil, pick_name = nil, value = nil }
local AREAS = { "All", "Items", "Tracks and mixer", "MIDI editor", "Envelopes", "Ruler, markers and regions", "Razor edits", "Arrange view", "Lanes" }
local function area_of(name)
  if name:match("^MIDI") then return "MIDI editor" end
  if name:match("^Media item") or name:match("^Sample edit") then return "Items" end
  if name:match("^Track") or name:match("^Mixer") or name:match("^Fader") then return "Tracks and mixer" end
  if name:match("^Envelope") or name:match("^Automation") then return "Envelopes" end
  if name:match("^Ruler") or name:match("^Marker") or name:match("^Region") or name:match("^Tempo") then return "Ruler, markers and regions" end
  if name:match("^Razor") then return "Razor edits" end
  if name:match("^Fixed lane") then return "Lanes" end
  return "Arrange view"
end
local function mouse_cat()
  if not mq.cat then mq.cat = core.mouse_catalog(styles, rpage(), function(ctx, flag) return reaper.GetMouseModifier(ctx, flag, "") end) end
  return mq.cat
end
local function choices(ctx) -- what this context's lines can be: the behaviours known for it (REAPER's and the personas'), with their names
  local out, seen = {}, {}
  for _, r in ipairs(mouse_cat()) do
    if r.ctx == ctx and r.value ~= "-1" and not seen[r.value] then seen[r.value] = true; out[#out + 1] = { r.value, r.name } end
  end
  table.sort(out, function(a, b) return a[2] < b[2] end)
  return out
end
local function value_name(c, v) -- what a behaviour id does, in words
  if v == "-1" then return "REAPER's default for these keys" end
  for _, x in ipairs(choices(c)) do if x[1] == v then return x[2] end end
  local id = tonumber(v) or (type(v) == "string" and v:match("^_") and reaper.NamedCommandLookup(v))
  local name = id and id ~= 0 and reaper.kbd_getTextFromCmd and reaper.kbd_getTextFromCmd(id, reaper.SectionFromUniqueID(0))
  return (name and name ~= "") and name or tostring(v)
end
local function mouse_block_here()
  local b = core.draft_get(bld.blocks, "mouse")
  if not b then b = core.new_block("mouse", "my_reaper"); core.draft_add(bld.blocks, b) end
  bld.active = true
  return b
end
local function add_mouse_line(ctx, flag, value, name)
  local b = mouse_block_here()
  b.mextra = type(b.mextra) == "table" and b.mextra or {}
  for i = #b.mextra, 1, -1 do if b.mextra[i][2] == ctx and tonumber(b.mextra[i][3]) == flag then table.remove(b.mextra, i) end end
  b.mextra[#b.mextra + 1] = { "mouse", ctx, flag, value, name }
  say((core.CTX_NAME[ctx] or ctx) .. (flag > 0 and (" with " .. keyname(core.mouse_mods(flag))) or "") .. ": " .. tostring(name) .. ", in your persona.")
end
local function add_wheel(spec, cmd, name)
  if not core.encode(spec) then return say(keyname(spec) .. " isn't a wheel REAPER can take.") end
  local b = mouse_block_here()
  b.extra = type(b.extra) == "table" and b.extra or {}
  for i = #b.extra, 1, -1 do if core.canon(b.extra[i][1]) == core.canon(spec) then table.remove(b.extra, i) end end
  b.extra[#b.extra + 1] = { spec, cmd, name }
  say(keyname(spec) .. ": " .. tostring(name) .. ", in your persona.")
end
local function action_search(id, filter_words) -- -> cmd, name once one is picked
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  mq.acts = type(mq.acts) == "table" and mq.acts or {} -- (one text per search box: review 2026-11-18)
  local _, q = ImGui.InputTextWithHint(ctx, "##as" .. id, "search actions", mq.acts[id] or ""); mq.acts[id] = q
  if #q >= 2 then
    for _, a in ipairs(core.find_actions(q, 10, filter_words)) do
      if ImGui.Selectable(ctx, tostring(a[2]) .. "##asr" .. id .. tostring(a[1])) then mq.acts[id] = ""; return a[1], a[2] end
    end
  end
end
local function mods_boxes(id, field) -- Ctrl / Alt / Shift / Win ticks -> mq[field] (REAPER's mouse flags: Shift 1, Ctrl 2, Alt 4, Win 8)
  field = field or "mods"
  for _, x in ipairs({ { 2, MOD }, { 4, IS_MAC and "Option" or "Alt" }, { 1, "Shift" }, { 8, IS_MAC and "Control" or (reaper.GetOS():find("^Win") and "Win" or "Super") } }) do
    ImGui.SameLine(ctx)
    local ch, v = ImGui.Checkbox(ctx, x[2] .. "##mb" .. id .. x[1], (mq[field] or 0) & x[1] ~= 0)
    if ch then mq[field] = v and ((mq[field] or 0) | x[1]) or ((mq[field] or 0) & ~x[1]) end
  end
end
local function wheel_spec(mods, wheel) local m = core.mouse_mods(mods):gsub("Shift%+Ctrl", "Ctrl+Shift"); return (m ~= "" and (m .. "+") or "") .. wheel end
local function change_popup(e, b) -- a line's new behaviour: a known one, REAPER's default, or an action
  if not ImGui.BeginPopup(ctx, "mch" .. e.slot) then return end
  local mctx = e.entry and core.for_os(e.entry[2]) or nil
  local function set(v, name)
    if e.extra then b.mextra[e.extra][4], b.mextra[e.extra][5] = v, name
    else b.mset = type(b.mset) == "table" and b.mset or {}; b.mset[e.slot] = v end
    ImGui.CloseCurrentPopup(ctx)
  end
  if ImGui.Selectable(ctx, "REAPER's default for these keys") then set("-1", "REAPER's default") end
  for _, c in ipairs(mctx and choices(mctx) or {}) do if ImGui.Selectable(ctx, c[2] .. "##ch" .. c[1]) then set(c[1], c[2]) end end
  ImGui.Separator(ctx); ImGui.Text(ctx, "Or run an action:")
  local cmd, name = action_search("ch" .. e.slot)
  if cmd then set(tostring(cmd), name) end
  ImGui.EndPopup(ctx)
end
local function persona_mouse_card()
  if not card("pmouse") then return end
  heading("Your persona's mouse and trackpad", 16)
  muted("Load a persona's mouse, then leave any line out, change what it does, or add your own (below, or from Every mouse action). A trackpad's two-finger scroll and pinch arrive as the wheel and Ctrl+wheel (Cmd on a Mac), its sideways swipe as the horizontal wheel.")
  ImGui.Indent(ctx, IND * UI)
  local b = core.draft_get(bld.blocks, "mouse")
  local from = b and core.by_id(b.id)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  if ImGui.BeginCombo(ctx, "##mfrom", b and (from and from.name or tostring(b.id)) or "Your own mouse and trackpad") then
    if ImGui.Selectable(ctx, "Your own mouse and trackpad##mown", b == nil) then core.draft_clear(bld.blocks, "mouse"); bld.active = true end
    for _, st in ipairs(sources(has_mouse)) do
      if ImGui.Selectable(ctx, st.name .. "##mf" .. st.id, b ~= nil and b.id == st.id) then
        local nb = core.new_block("mouse", st.id); nb.mextra, nb.extra = b and b.mextra or nil, b and b.extra or nil -- (lines you added stay)
        core.draft_add(bld.blocks, nb); bld.active = true
      end
    end
    ImGui.EndCombo(ctx)
  end
  if b then
    local groups = { { "Mouse wheel", {} }, { "Trackpad: two-finger swipe left and right", {} }, { "Drags and clicks", {} } }
    for _, e in ipairs(core.build_preview({ b })[1]) do
      if e.key and e.key:find("HorizWheel", 1, true) then table.insert(groups[2][2], e)
      elseif e.key then table.insert(groups[1][2], e)
      elseif not (e.entry and e.entry[1] == "mouse" and not core.for_os(e.entry[2])) then table.insert(groups[3][2], e) end
    end
    for _, g in ipairs(groups) do
      if #g[2] > 0 then
        ImGui.TextColored(ctx, C.MUTED, g[1])
        if ImGui.BeginTable(ctx, "pm" .. g[1], 4, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp) then
          ImGui.TableSetupColumn(ctx, "on", ImGui.TableColumnFlags_WidthFixed, 28 * UI)
          ImGui.TableSetupColumn(ctx, "where", ImGui.TableColumnFlags_WidthStretch, 0.45)
          ImGui.TableSetupColumn(ctx, "what", ImGui.TableColumnFlags_WidthStretch)
          ImGui.TableSetupColumn(ctx, "do", ImGui.TableColumnFlags_WidthFixed, 160 * UI) -- (Change + Put back)
          for _, e in ipairs(g[2]) do
            ImGui.PushID(ctx, e.slot)
            ImGui.TableNextRow(ctx)
            ImGui.TableNextColumn(ctx)
            local ch, v = ImGui.Checkbox(ctx, "##on", not e.off)
            if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
            ImGui.TableNextColumn(ctx)
            if e.key then keycap(e.key)
            else
              local c = core.for_os(e.entry[2]) or e.entry[2]
              ImGui.Text(ctx, (core.CTX_NAME[c] or c) .. (tonumber(e.entry[3]) > 0 and ("  +  " .. keyname(core.mouse_mods(e.entry[3]))) or ""))
            end
            ImGui.TableNextColumn(ctx)
            local label = e.changed and value_name(core.for_os(e.entry[2]) or e.entry[2], e.entry[4]) or tostring(e.label)
            ImGui.TextColored(ctx, e.off and C.MUTED or C.TEXT, label .. (e.extra and "   (added)" or "") .. (e.changed and "   (changed)" or ""))
            ImGui.TableNextColumn(ctx)
            if e.key then
              if ImGui.SmallButton(ctx, "Change") then ImGui.OpenPopup(ctx, "wch" .. e.slot) end
              if ImGui.BeginPopup(ctx, "wch" .. e.slot) then
                ImGui.Text(ctx, "What " .. keyname(e.key) .. " does:")
                local cmd, name = action_search("w" .. e.slot)
                if cmd then add_wheel(e.key, cmd, name); ImGui.CloseCurrentPopup(ctx) end
                ImGui.EndPopup(ctx)
              end
            else
              if ImGui.SmallButton(ctx, "Change") then ImGui.OpenPopup(ctx, "mch" .. e.slot) end
              change_popup(e, b)
            end
            if e.extra then
              ImGui.SameLine(ctx)
              if ImGui.SmallButton(ctx, "Remove") then if e.key then table.remove(b.extra, e.extra) else table.remove(b.mextra, e.extra) end end
            elseif e.changed then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Put back") then b.mset[e.slot] = nil end; ImGui.SetItemTooltip(ctx, "Back to what this line did in the persona you loaded.") end
            ImGui.PopID(ctx)
          end
          ImGui.EndTable(ctx)
        end
      end
    end
  end
  -- your own: a wheel or swipe binding, or a drag or click
  ImGui.Dummy(ctx, 0, 4)
  -- (both ways to add one are shown at once: there were two radio buttons to switch between them. James, 2026-11-19)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Add a wheel or trackpad move:"); ImGui.SameLine(ctx)
  do
    ImGui.SetNextItemWidth(ctx, 200 * UI)
    if ImGui.BeginCombo(ctx, "##wh", mq.wheel == "HorizWheel" and "Sideways (trackpad swipe)" or "Wheel (or two-finger scroll)") then
      if ImGui.Selectable(ctx, "Wheel (or two-finger scroll)", mq.wheel == "Mousewheel") then mq.wheel = "Mousewheel" end
      if ImGui.Selectable(ctx, "Sideways (trackpad swipe)", mq.wheel == "HorizWheel") then mq.wheel = "HorizWheel" end
      ImGui.EndCombo(ctx)
    end
    mods_boxes("w", "wmods")
    -- (an action picked here waits for Add, as in the drag form below: a click while browsing added a line. Round 4)
    local cmd, name = action_search("wadd", nil)
    if cmd then mq.wact, mq.wact_name = cmd, name end
    if mq.wact then
      ImGui.SameLine(ctx); ImGui.Text(ctx, tostring(mq.wact_name)); ImGui.SameLine(ctx)
      if primary("Add to my persona##wadd") then add_wheel(wheel_spec(mq.wmods or 0, mq.wheel), mq.wact, mq.wact_name); mq.wact, mq.wact_name = nil, nil end
    end
    muted("Search for what " .. keyname(wheel_spec(mq.wmods or 0, mq.wheel)) .. " should do, then Add (the View: Scroll and Zoom actions marked mousewheel are the usual ones).")
  end
  ImGui.Dummy(ctx, 0, 4)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Add a drag or click:"); ImGui.SameLine(ctx)
  do
    ImGui.SetNextItemWidth(ctx, 280 * UI)
    if ImGui.BeginCombo(ctx, "##mctx", core.CTX_NAME[mq.ctx] or mq.ctx) then
      for _, c in ipairs(core.MOUSE_CONTEXTS) do if ImGui.Selectable(ctx, c[2] .. "##mc" .. c[1], c[1] == mq.ctx) then mq.ctx, mq.value = c[1], nil end end
      ImGui.EndCombo(ctx)
    end
    mods_boxes("d")
    ImGui.SetNextItemWidth(ctx, 280 * UI)
    local cur = mq.value and (mq.pick_name or mq.value) or "what it does"
    if ImGui.BeginCombo(ctx, "##mval", cur) then
      if ImGui.Selectable(ctx, "REAPER's default for these keys") then mq.value, mq.pick_name = "-1", "REAPER's default" end
      for _, c in ipairs(choices(mq.ctx)) do if ImGui.Selectable(ctx, c[2] .. "##mv" .. c[1]) then mq.value, mq.pick_name = c[1], c[2] end end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx); ImGui.Text(ctx, "or an action:"); ImGui.SameLine(ctx)
    local cmd, name = action_search("dadd")
    if cmd then mq.value, mq.pick_name = tostring(cmd), name end
    if mq.value then
      if primary("Add to my persona##madd") then add_mouse_line(mq.ctx, mq.mods, mq.value, mq.pick_name); mq.value, mq.pick_name = nil, nil end
    end
  end
  ImGui.Unindent(ctx, IND * UI)
  card_end()
end
local function mouse_catalog_card()
  if not card("allmouse") then return end
  heading("Every mouse action", 16)
  muted("Everything the mouse does in REAPER now, its defaults included, and every persona's, grouped by where you click or drag. Add any to your persona.")
  if not rpage() then
    ImGui.TextColored(ctx, C.YELLOW, "REAPER's own list hasn't been read on this computer yet: only the personas' are below.")
  end
  if ImGui.SmallButton(ctx, (rpage() and "Read REAPER's list again" or "Read REAPER's list") .. "##rp") then read_rpage(true); mq.cat = nil end
  ImGui.SetItemTooltip(ctx, "REAPER writes it with Help > Mouse modifier keys and action shortcuts, which also opens it in your browser.")
  ImGui.SetNextItemWidth(ctx, 200 * UI)
  local _, f = ImGui.InputTextWithHint(ctx, "##mcf", "search", mq.filter or ""); mq.filter = f
  ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 220 * UI)
  if ImGui.BeginCombo(ctx, "##marea", "Where: " .. mq.area) then for _, a in ipairs(AREAS) do if ImGui.Selectable(ctx, a .. "##ma", a == mq.area) then mq.area = a end end ImGui.EndCombo(ctx) end
  local srcs = { "All", "REAPER (as set now)" }
  for _, st in ipairs(styles) do if has_mouse(st) and not st.keys_from then srcs[#srcs + 1] = st.name end end
  ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx, 200 * UI)
  if ImGui.BeginCombo(ctx, "##msrc", "From: " .. mq.source) then for _, s in ipairs(srcs) do if ImGui.Selectable(ctx, s .. "##ms", s == mq.source) then mq.source = s end end ImGui.EndCombo(ctx) end
  local q, n, total = (mq.filter or ""):lower(), 0, 0
  if ImGui.BeginTable(ctx, "allm", 5, ImGui.TableFlags_RowBg | ImGui.TableFlags_SizingStretchProp | ImGui.TableFlags_ScrollY, 0, 360 * UI) then
    ImGui.TableSetupColumn(ctx, "Where", ImGui.TableColumnFlags_WidthStretch, 0.5)
    ImGui.TableSetupColumn(ctx, "Keys", ImGui.TableColumnFlags_WidthFixed, 130 * UI)
    ImGui.TableSetupColumn(ctx, "What it does", ImGui.TableColumnFlags_WidthStretch)
    ImGui.TableSetupColumn(ctx, "From", ImGui.TableColumnFlags_WidthStretch, 0.4)
    ImGui.TableSetupColumn(ctx, "add", ImGui.TableColumnFlags_WidthFixed, 44 * UI)
    ImGui.TableHeadersRow(ctx)
    for i, r in ipairs(mouse_cat()) do
      local ok = mq.area == "All" or area_of(r.ctxname) == mq.area
      if ok and mq.source ~= "All" then ok = false; for _, s in ipairs(r.sources) do if s == mq.source then ok = true end end end
      if ok and q ~= "" then ok = r.ctxname:lower():find(q, 1, true) or tostring(r.name):lower():find(q, 1, true) end
      if ok then
        total = total + 1
        if n < mq.shown then
          n = n + 1
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, r.ctxname)
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, r.flag == 0 and "(none)" or keyname(core.mouse_mods(r.flag)))
          ImGui.TableNextColumn(ctx); ImGui.Text(ctx, tostring(r.name))
          ImGui.TableNextColumn(ctx); ImGui.TextColored(ctx, C.MUTED, #r.sources > 2 and (r.sources[1] .. " and " .. (#r.sources - 1) .. " more") or table.concat(r.sources, ", "))
          if #r.sources > 2 then ImGui.SetItemTooltip(ctx, table.concat(r.sources, ", ")) end
          ImGui.TableNextColumn(ctx)
          if ImGui.SmallButton(ctx, "Add##am" .. i) then add_mouse_line(r.ctx, r.flag, r.value, r.name) end
        end
      end
    end
    ImGui.EndTable(ctx)
  end
  muted(n .. " of " .. total .. " shown")
  if total > n then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Show more##mmore") then mq.shown = mq.shown + 200 end end
  card_end()
end
function mouse_page() -- (5.28: mouse and trackpad; 5.31: the editor)
  persona_mouse_card()
  mouse_catalog_card()
  if card("trackpad here") then
    heading("Trackpad on this computer", 16)
    muted("Windows and macOS send a trackpad's two-finger scroll as the mouse wheel, a sideways swipe as the horizontal wheel, and a pinch as Ctrl+wheel (Cmd on a Mac), so the persona's lines above cover both. Holding Shift while swiping turns it into a plain sideways scroll on Windows: pinch is the way to zoom.")
    if reaper.HasExtState("SmoothWheelScroll", "tprevzoom") then
      local on = reaper.GetExtState("SmoothWheelScroll", "tprevzoom") == "1"
      local ch, v = ImGui.Checkbox(ctx, "Smooth Wheel Scroll: reverse zooming on a trackpad##tprev", on)
      if ch then reaper.SetExtState("SmoothWheelScroll", "tprevzoom", v and "1" or "0", true); say("Smooth Wheel Scroll reads this when REAPER starts.") end
      ImGui.SetItemTooltip(ctx, "Smooth Wheel Scroll tells a trackpad from a wheel; this flips zoom for the trackpad only. Remote desktops (Chrome Remote Desktop) can look like a trackpad to it. Read when REAPER starts.")
    end
    card_end()
  end
end
end
