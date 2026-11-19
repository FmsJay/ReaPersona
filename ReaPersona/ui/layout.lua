-- ReaPersona's window: Layout: the designer, REAPER > Preferences, other windows, which docker each window goes into.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 2777-3137.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
-- (in R: layout_designer, COVERED) -- (5.32: the designer, and the parts of the layout it sets)
COVERED = { mixer_dock = true, transport = true, browser = true, editor = true }
do -- (the layout designer: its own scope)
  local ZONE_LABEL = { t_top = "Transport: top of the window", d_top = "Top dock", d_left = "Left dock", d_right = "Right dock", d_bottom = "Bottom dock",
    t_ruler = "Transport: above the ruler", t_below = "Transport: below the arrange view", t_bottom = "Transport: bottom of the window",
    float = "In its own window", hidden = "Closed" }
  local cache = { at = -1, items = nil }
  local function deep(t) local o = {}; for k, v in pairs(t) do o[k] = type(v) == "table" and deep(v) or v end return o end
  local function current_items() -- -> the layout the designer shows, and whether it's one you arranged
    local b = core.draft_get(bld.blocks, "layout")
    if b and type(b.items) == "table" then return b.items, true end
    local sig = {} -- (what the persona's layout parts come from now: a change of those shows at once)
    for a in pairs(COVERED) do local fb = core.draft_get(bld.blocks, "feel " .. a); sig[#sig + 1] = a .. "=" .. (fb and tostring(fb.id) or "") end
    table.sort(sig); sig = table.concat(sig, ";")
    if cache.items and cache.sig == sig and (sig:find("=[^;]") or reaper.time_precise() - cache.at < 2) then return cache.items, false end
    local entries = {}
    for a in pairs(COVERED) do
      local fb = core.draft_get(bld.blocks, "feel " .. a)
      if fb then for _, e in ipairs(core.build_preview({ fb })[1]) do if not e.off then entries[#entries + 1] = e.entry end end end
    end
    local from_reaper = #entries == 0
    if from_reaper then entries = core.feel_now(core.by_id("my_reaper") or styles[1], true) end -- (true: closed windows by their toggle, not a search) -- (nothing chosen: REAPER as it is now)
    local items = core.layout_from_entries(entries)
    if from_reaper then items.midi = { zone = core.midi_docked() and "d_bottom" or "float", order = 1 } end
    cache.at, cache.items, cache.sig = reaper.time_precise(), items, sig
    return items, false
  end
  local function move(items, w, zone, before) -- w into zone, before window `before` (or last); the layout becomes the persona's
    local copy = deep(items)
    copy[w] = { zone = zone, order = 0 }
    local list = {}
    for k, it in pairs(copy) do if it.zone == zone and k ~= w then list[#list + 1] = k end end
    table.sort(list, function(a, b) return (copy[a].order or 0) < (copy[b].order or 0) end)
    local pos = #list + 1
    if before then for i, k in ipairs(list) do if k == before then pos = i end end end
    table.insert(list, pos, w)
    for i, k in ipairs(list) do copy[k].order = i end
    for a in pairs(COVERED) do core.draft_clear(bld.blocks, "feel " .. a) end
    core.draft_add(bld.blocks, { kind = "layout", items = copy })
    bld.active, cache.items = true, nil
  end
  local function name_of(w) for _, x in ipairs(core.LAYOUT_WINDOWS) do if x[1] == w then return x[2] end end return w end
  local function dragging() -- the window being dragged, if one is
    local ok, kind, payload = ImGui.GetDragDropPayload(ctx)
    return ok and kind == "RP_WIN" and payload or nil
  end
  function layout_designer()
    if not card("designer") then return end
    heading("Arrange your layout", 16)
    muted("Drag a window to where you want it. Windows in the same dock are tabs, in the order shown: drop one onto another to put it before it. Starts from the persona's own layout (or REAPER as it is now).")
    ImGui.Indent(ctx, IND * UI)
    local items, mine = current_items()
    local x0, y0 = ImGui.GetCursorScreenPos(ctx)
    local W = math.max(420 * UI, math.min(ImGui.GetContentRegionAvail(ctx), 820 * UI))
    local H, th, sidew = 340 * UI, 24 * UI, 160 * UI
    local mw = W - sidew - 14 * UI
    local dl = ImGui.GetWindowDrawList(ctx)
    local Z, y = {}, y0
    Z.t_top = { x0 + 4, y + 4, mw - 8, th }; y = y + th + 8
    Z.d_top = { x0 + 4, y, mw - 8, 44 * UI }; y = y + 44 * UI + 4
    local midH = H - (y - y0) - (58 * UI + th + 16)
    local sw = mw * 0.21
    Z.d_left = { x0 + 4, y, sw, midH }
    Z.d_right = { x0 + mw - 4 - sw, y, sw, midH }
    local ax, aw = x0 + 8 + sw, mw - 16 - 2 * sw
    Z.t_ruler = { ax, y, aw, th }
    local arrange = { ax, y + th + 2, aw, midH - 2 * th - 4 }
    Z.t_below = { ax, y + midH - th, aw, th }
    y = y + midH + 4
    Z.d_bottom = { x0 + 4, y, mw - 8, 58 * UI }; y = y + 58 * UI + 4
    Z.t_bottom = { x0 + 4, y, mw - 8, th }
    Z.float = { x0 + mw + 14 * UI, y0, sidew, H / 2 - 4 }
    Z.hidden = { x0 + mw + 14 * UI, y0 + H / 2 + 4, sidew, H / 2 - 4 }
    ImGui.DrawList_AddRect(dl, x0, y0, x0 + mw, y0 + H, C.MUTED, 6, 0, 1.5)
    ImGui.DrawList_AddRectFilled(dl, arrange[1], arrange[2], arrange[1] + arrange[3], arrange[2] + arrange[4], solid(mix(P.card, P.bg, 0.5)), 4)
    ImGui.DrawList_AddText(dl, arrange[1] + 8, arrange[2] + 6, C.MUTED, "Arrange view")
    local drag = dragging()
    local act
    for z, r in pairs(Z) do -- (each zone: a drop target; lit while a window that can go there is dragged)
      local can = drag and core.zone_ok(drag, z)
      ImGui.DrawList_AddRectFilled(dl, r[1], r[2], r[1] + r[3], r[2] + r[4], can and solid(mix(P.card, P.accent, 0.35)) or C.CARD, 4)
      ImGui.DrawList_AddText(dl, r[1] + 6, r[2] + 3, C.MUTED, ZONE_LABEL[z])
      ImGui.SetCursorScreenPos(ctx, r[1], r[2])
      ImGui.SetNextItemAllowOverlap(ctx) -- (5.35: the windows drawn over it get the mouse first, so they can be dragged; James: "wasn't letting me drag things")
      ImGui.InvisibleButton(ctx, "##zone" .. z, math.max(r[3], 1), math.max(r[4], 1))
      if ImGui.BeginDragDropTarget(ctx) then
        local ok, w = ImGui.AcceptDragDropPayload(ctx, "RP_WIN")
        if ok and core.zone_ok(w, z) then act = { w, z, nil } end
        ImGui.EndDragDropTarget(ctx)
      end
    end
    for z, r in pairs(Z) do -- (the windows in it, as tabs in order)
      local list = {}
      for w, it in pairs(items) do if it.zone == z then list[#list + 1] = w end end
      table.sort(list, function(a, b) return (items[a].order or 0) < (items[b].order or 0) end)
      local tall = r[4] > 40 * UI -- (a dock: its name above its windows; a thin strip: its windows after its name)
      local cx, cy = r[1] + 6 + (tall and 0 or (ImGui.CalcTextSize(ctx, ZONE_LABEL[z]) + 10)), r[2] + (tall and 20 * UI or 1)
      for i, w in ipairs(list) do
        local label = name_of(w) .. ((#list > 1 and z:sub(1, 2) == "d_") and ("  (tab " .. i .. ")") or "")
        local bw = ImGui.CalcTextSize(ctx, label) + 16 * UI
        if tall and cx + bw > r[1] + r[3] - 4 and cx > r[1] + 6 then cx, cy = r[1] + 6, cy + ImGui.GetFrameHeight(ctx) + 4 end
        ImGui.SetCursorScreenPos(ctx, cx, cy)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.ACCENT)
        ImGui.Button(ctx, label .. "##win" .. w, bw, 0)
        ImGui.PopStyleColor(ctx)
        ImGui.SetItemTooltip(ctx, name_of(w) .. ": " .. core.ZONE_WORDS[z] .. ". Drag it somewhere else, or onto another window in a dock to make it the tab before.")
        if ImGui.BeginDragDropSource(ctx) then
          ImGui.SetDragDropPayload(ctx, "RP_WIN", w)
          ImGui.Text(ctx, name_of(w))
          ImGui.EndDragDropSource(ctx)
        end
        if ImGui.BeginDragDropTarget(ctx) then
          local ok, dw = ImGui.AcceptDragDropPayload(ctx, "RP_WIN")
          if ok and dw ~= w and core.zone_ok(dw, z) then act = { dw, z, w } end
          ImGui.EndDragDropTarget(ctx)
        end
        cx = cx + bw + 6
      end
    end
    ImGui.SetCursorScreenPos(ctx, x0, y0 + H + 8)
    ImGui.Dummy(ctx, 1, 1)
    if act then move(items, act[1], act[2], act[3]); say(name_of(act[1]) .. ": " .. core.ZONE_WORDS[act[2]] .. ", in your persona.") end
    if mine then
      muted("This is your own arrangement: it sets the mixer, Media Explorer, transport and MIDI editor parts below.")
      ImGui.SameLine(ctx)
      if ImGui.SmallButton(ctx, "Back to the persona's own##lyreset") then core.draft_clear(bld.blocks, "layout"); cache.items = nil end
    end
    muted("REAPER's other windows (the Actions list, Undo History, Region Manager and the rest) are below, under Other windows.")
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
-- (in R: prefs_page) -- (5.35: REAPER's preferences in a persona)
do
  local pf_seen = {}
  local function block() return core.draft_get(bld.blocks, "feel prefs") end
  local function values() -- the block's values (made from what it loads, the first time it's changed here)
    local b = block()
    if not b then return nil end
    if type(b.values) ~= "table" then
      local v = {}
      for _, e in ipairs(core.build_preview({ b })[1]) do if e.entry[1] == "pref" then v[e.entry[2]] = e.entry[3] end end
      b.values, b.id = v, nil
    end
    return b.values
  end
  local function control(x, v) -- -> changed?, the new value
    local k = x[1]
    ImGui.SetNextItemWidth(ctx, 220 * UI)
    if x[3] == "num" then
      local ch, n = ImGui.DragDouble(ctx, "##pfv" .. k, v, 0.001, x[4], x[5], "%.3f s")
      return ch, math.max(x[4], math.min(x[5], n))
    elseif x[3] == "bool" then
      local ch, on = ImGui.Checkbox(ctx, "##pfv" .. k, v == 1)
      return ch, on and 1 or 0
    elseif x[3] == "db" or x[3] == "db10" then
      local db = x[3] == "db10" and v / 10 or (v <= 0 and -60 or 20 * math.log(v, 10))
      local ch, n = ImGui.SliderDouble(ctx, "##pfv" .. k, db, -60, x[3] == "db10" and -1 or 12, "%.1f dB")
      if x[3] == "db10" then return ch, math.floor(n * 10 + 0.5) end
      return ch, n <= -60 and 0 or 10 ^ (n / 20)
    else
      local labels = {}
      if x[3] == "shape" then for i = 1, (x.max or 7) + 1 do labels[i] = "Shape " .. i end else labels = x[4] end -- (in the order REAPER's fade-shape menu lists them; item fades have 7, crossfades 8)
      local out, changed = v, false
      if ImGui.BeginCombo(ctx, "##pfv" .. k, labels[math.floor(v) + 1] or tostring(v)) then
        for i, l in ipairs(labels) do if ImGui.Selectable(ctx, l .. "##pfo" .. k .. i, i - 1 == v) then out, changed = i - 1, true end end
        ImGui.EndCombo(ctx)
      end
      return changed, out
    end
  end
  function prefs_page()
    if card("pf top") then
      heading("REAPER's preferences")
      muted("The ones REAPER has no action for: fades and crossfades, zoom, new tracks, recording and solo. Tick In my persona and set it: the persona you're making gets that value. REAPER reads its preferences only as it starts, so a persona's go in at REAPER's next restart, and yours go back the same way when you switch away.")
      ImGui.Indent(ctx, IND * UI)
      ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
      ImGui.SetNextItemWidth(ctx, 260 * UI)
      if ImGui.BeginCombo(ctx, "##pfload", "a persona or your saved look") then
        for _, st in ipairs(sources(function(s) return has_aspect(core.source(s.id) or s, "prefs") end)) do
          if ImGui.Selectable(ctx, st.name .. "##pfl" .. st.id) then
            core.draft_add(bld.blocks, core.new_block("feel", st.id, "prefs")); bld.active = true
            say(st.name .. "'s preferences are in your persona: change any below.")
          end
        end
        ImGui.EndCombo(ctx)
      end
      if block() then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave them all as they are##pfclr") then core.draft_clear(bld.blocks, "feel prefs") end end
      if reaper.time_precise() - (pf_seen.at or -10) > 1 then pf_seen.at, pf_seen.v = reaper.time_precise(), core.load_json(here .. "/pending/prefs.json") end
      local waiting = pf_seen.v -- (once a second, not every frame: review 2026-11-18)
      if not core.python() then
        ImGui.TextColored(ctx, C.YELLOW, "This computer has no Python 3, which putting preferences into REAPER needs (python.org). A persona's preferences still go with it to your other computers, but here REAPER's stay as they are.")
      elseif waiting and next(waiting) then
        ImGui.TextColored(ctx, C.YELLOW, "Waiting for REAPER to restart: " .. #(function() local n = {}; for k in pairs(waiting) do n[#n + 1] = k end return n end)() .. " preference(s).")
        ImGui.SameLine(ctx)
        if ImGui.SmallButton(ctx, RESTART_BUTTON .. "##pfrestart") then install_shortcuts() end
        ImGui.SetItemTooltip(ctx, FLATPAK and RESTART_TIP or "REAPER closes (asking about anything unsaved), the preferences go in, and REAPER opens again.")
      end
      ImGui.Unindent(ctx, IND * UI)
      card_end()
    end
    if not card("pf list") then return end
    local vals, group = values(), nil
    ImGui.Indent(ctx, IND * UI)
    for _, x in ipairs(core.PREFS) do
      if x.group ~= group then group = x.group; heading(group, 15) end
      local live = core.pref_now(x[1])
      local v = vals and tonumber(vals[x[1]])
      local ch, on = ImGui.Checkbox(ctx, "##pfin" .. x[1], v ~= nil)
      ImGui.SetItemTooltip(ctx, v and "In your persona: untick to leave it as it is" or "Tick to put it in your persona, at the value set here")
      if ch then
        if not block() then core.draft_add(bld.blocks, { kind = "feel", aspect = "prefs", values = {} }) end
        values()[x[1]] = on and (live or 0) or nil
        bld.active = true
      end
      ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, x[2]); ImGui.SameLine(ctx, 0, 16 * UI)
      if ImGui.GetCursorPosX(ctx) < 400 * UI then ImGui.SetCursorPosX(ctx, 400 * UI) end -- (a long label pushes its value along: review 2026-11-18)
      if ImGui.GetContentRegionAvail(ctx) < 300 * UI then ImGui.NewLine(ctx); ImGui.SetCursorPosX(ctx, 40 * UI) end -- (narrow: on its own line, review 2)
      if v then
        local c2, n = control(x, v)
        if c2 then values()[x[1]] = n; bld.active = true end
        ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "now " .. core.pref_words(x[1], live))
      else
        ImGui.TextColored(ctx, C.MUTED, live and core.pref_words(x[1], live) or "not in this REAPER")
      end
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
-- (in R: windows_card) -- (5.34: every other window, set one by one)
do
  local CHOICES = { { nil, "Leave as it is" }, { "closed", "Closed" }, { "float", "In its own window" }, { "bottom", "Docked at the bottom" },
    { "left", "Docked on the left" }, { "top", "Docked at the top" }, { "right", "Docked on the right" } }
  local undock_note, undock_at = nil, -10
  local wins_seen = {} -- (REAPER's windows as last looked at)
  local function block_items() -- -> the windows block's items (made from what it loads, the first time it's changed here), or nil
    local b = core.draft_get(bld.blocks, "feel windows")
    if not b then return nil end
    if type(b.items) ~= "table" then
      local items = {}
      for _, e in ipairs(core.build_preview({ b })[1]) do if e.entry[1] == "windows" then items = e.entry[2] end end
      b.items, b.id = items, nil
    end
    return b.items
  end
  function windows_card()
    if not card("windows edit") then return end
    heading("Set each window", 16)
    muted("Open or closed, in its own window (where it is now) or docked on a side. Take them as they are now, or choose one by one.")
    ImGui.Indent(ctx, IND * UI)
    if reaper.time_precise() - (wins_seen.at or -10) > 0.5 then wins_seen.at, wins_seen.now = reaper.time_precise(), core.windows_now(true) end -- (review 2026-11-18)
    if not wins_seen.now then
      ImGui.TextColored(ctx, C.YELLOW, "Needs js_ReaScriptAPI (Home) to see REAPER's windows.")
      ImGui.Unindent(ctx, IND * UI); card_end(); return
    end
    if ImGui.Button(ctx, "Take them as they are now##wnow") then
      core.draft_add(bld.blocks, { kind = "feel", aspect = "windows", items = core.windows_now() })
      bld.active = true; core.undock_slot(); undock_at = -10
      say("Every window, as it is now, is in your persona.")
    end
    local items = block_items() or {}
    local now = wins_seen.now or {}
    for _, w in ipairs(core.TOOL_WINDOWS) do
      local x = items[w[1]]
      local cur = not x and "Leave as it is" or x.s ~= 1 and "Closed" or nil
      for _, c in ipairs(CHOICES) do if x and x.s == 1 and c[1] == (x.p or "float") then cur = c[2] end end
      ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, w[4]); ImGui.SameLine(ctx, 210 * UI)
      ImGui.SetNextItemWidth(ctx, 200 * UI)
      if ImGui.BeginCombo(ctx, "##wc" .. w[1], cur or (x and x.s == 1 and "Open") or "Leave as it is") then
        for _, c in ipairs(CHOICES) do
          if (w[2] or c[1] == nil or c[1] == "closed" or c[1] == "float") and ImGui.Selectable(ctx, (not w[2] and c[1] == "float") and "Open" or c[2], cur == c[2]) then
            local list = block_items()
            if not list then core.draft_add(bld.blocks, { kind = "feel", aspect = "windows", items = {} }); list = block_items() end
            if c[1] == nil then list[w[1]] = nil
            elseif c[1] == "closed" then list[w[1]] = { s = 0 }
            else
              local n = now[w[1]]
              list[w[1]] = { s = 1, p = w[2] and c[1] or nil, r = c[1] == "float" and n and n.p == "float" and n.r or nil } -- (its own window: where it is now, when it's open)
              if c[1] ~= "float" then core.undock_slot(); undock_at = -10 end
            end
            bld.active = true
          end
        end
        ImGui.EndCombo(ctx)
      end
      ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "now " .. core.window_words(now[w[1]]))
    end
    if reaper.time_precise() - undock_at > 5 then -- (whether REAPER has ReaPersona's window set: read now and then, not every frame)
      undock_at = reaper.time_precise()
      local slot, why = core.undock_slot_in(core.read(reaper.GetResourcePath() .. "/reaper-screensets.ini")), nil
      if not slot then why = (core.read(here .. "/pending/reaper-screensets.ini") or ""):find(core.UNDOCK_SET, 1, true) and "waiting" or "none" end
      undock_note = why
    end
    if undock_note == "waiting" then
      ImGui.TextColored(ctx, C.YELLOW, "Taking a window out of a docker needs ReaPersona's window set, which goes in when REAPER next restarts.")
      if ImGui.SmallButton(ctx, RESTART_BUTTON .. "##wrestart") then install_shortcuts() end
      ImGui.SetItemTooltip(ctx, FLATPAK and RESTART_TIP or "REAPER closes (asking about anything unsaved), ReaPersona's window set and your persona shortcuts go in, and REAPER opens again.")
    elseif undock_note == "none" then
      muted("Taking a window out of a docker needs a window set of ReaPersona's: it's added (in a free set, View > Screensets) the first time a persona docks one.")
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
-- (in R: dockers_card, dockpref_set) -- (5.43: which docker any dockable window goes into: toolbars, REAPER's windows, StudioSync...)
do
  local seen = { at = -10 } -- (reaper.ini as last read: every 2 s, not every frame)
  local function block_items() -- -> the dockers block's items (made from what it loads, the first time it's changed here), or nil
    local b = core.draft_get(bld.blocks, "feel dockpref")
    if not b then return nil end
    if type(b.items) ~= "table" then
      local items = {}
      for _, e in ipairs(core.build_preview({ b })[1]) do if e.entry[1] == "dockpref" then for k, v in pairs(e.entry[2]) do items[k] = v end end end
      b.items, b.id = items, nil
    end
    return b.items
  end
  function dockpref_set(ident, docker) -- a window's docker in the persona being made; nil ("As it is") takes its row out
    local items = block_items()
    if not items then
      if docker == nil then return end
      core.draft_add(bld.blocks, { kind = "feel", aspect = "dockpref", items = {} }); items = block_items()
    end
    items[ident] = docker
    if next(items) == nil then core.draft_clear(bld.blocks, "feel dockpref") end
    bld.active = true
  end
  function dockers_card()
    if not card("dockers") then return end
    heading("More windows and dockers", 16)
    muted("Pick the docker a window goes into: toolbars, REAPER's windows, and script windows such as StudioSync. Add a window, then choose its docker.")
    ImGui.Indent(ctx, IND * UI)
    if reaper.time_precise() - seen.at > 2 then
      local ini = core.read(reaper.GetResourcePath() .. "/reaper.ini") or ""
      seen.at, seen.prefs, seen.dockers = reaper.time_precise(), core.dock_prefs(ini), core.dockers(ini)
    end
    local inside = {} -- (docker -> the windows REAPER keeps there)
    for _, p in ipairs(seen.prefs) do inside[p.docker] = inside[p.docker] or {}; table.insert(inside[p.docker], core.dock_window_name(p.ident)) end
    for _, d in ipairs(seen.dockers) do
      if inside[d.n] then ImGui.TextColored(ctx, C.MUTED, d.name .. ": " .. table.concat(inside[d.n], ", ")) end
    end
    local b = core.draft_get(bld.blocks, "feel dockpref")
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 260 * UI)
    if ImGui.BeginCombo(ctx, "##dpload", "a persona") then
      for _, st in ipairs(sources(function(s) return has_aspect(s, "dockpref") end)) do
        if ImGui.Selectable(ctx, st.name .. "##dpl" .. st.id) then
          core.draft_add(bld.blocks, core.new_block("feel", st.id, "dockpref")); bld.active = true
          say(st.name .. "'s dockers are in your persona: change any below.")
        end
      end
      ImGui.EndCombo(ctx)
    end
    if b then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave them all as they are##dpclr") then core.draft_clear(bld.blocks, "feel dockpref"); b = nil end end
    local items = b and block_items() or {}
    local docker_at = {}
    for _, p in ipairs(seen.prefs) do docker_at[p.ident] = p.docker end
    local choices, have = {}, {} -- (every window REAPER has docked, then the tool windows it hasn't yet)
    for _, p in ipairs(seen.prefs) do if not have[p.ident] and core.dock_ident_ok(p.ident) then have[p.ident] = true; choices[#choices + 1] = p.ident end end
    for _, w in ipairs(core.TOOL_WINDOWS) do if w[2] and not have[w[1]] then have[w[1]] = true; choices[#choices + 1] = w[1] end end
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Add a window:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 260 * UI)
    if ImGui.BeginCombo(ctx, "##dpadd", "choose a window") then
      for _, id in ipairs(choices) do
        if items[id] == nil and ImGui.Selectable(ctx, core.dock_window_name(id) .. "##dpa" .. id) then
          dockpref_set(id, docker_at[id] or 0)
          say(core.dock_window_name(id) .. " is in your persona: pick its docker below.")
        end
      end
      ImGui.EndCombo(ctx)
    end
    local rows = {}
    for id in pairs(items) do rows[#rows + 1] = id end
    table.sort(rows, function(x, y) return core.dock_window_name(x) < core.dock_window_name(y) end)
    for _, id in ipairs(rows) do
      local d = items[id]
      ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, core.dock_window_name(id)); ImGui.SameLine(ctx, 260 * UI)
      ImGui.SetNextItemWidth(ctx, 200 * UI)
      local cur = seen.dockers[(tonumber(d) or 0) + 1]
      if ImGui.BeginCombo(ctx, "##dpd" .. id, cur and cur.name or "As it is") then
        if ImGui.Selectable(ctx, "As it is##dpn" .. id, false) then dockpref_set(id, nil) end
        for _, x in ipairs(seen.dockers) do
          if ImGui.Selectable(ctx, x.name .. (x.used and "" or " (empty)") .. "##dpo" .. id .. x.n, x.n == d) then dockpref_set(id, x.n) end
        end
        ImGui.EndCombo(ctx)
      end
      if core.dock_is_script(id) then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "moves the next time its script docks it")
      elseif not core.WINDOWS[id] then ImGui.SameLine(ctx); ImGui.TextColored(ctx, C.MUTED, "moves the next time it docks") end
    end
    if #rows == 0 then muted("No windows added: each stays in its own docker.") end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
end
function layout_page()
  layout_designer()
  if card("layout top") then
    heading("Your persona's layout, part by part")
    muted("Each part from whichever persona you like: the mixer from one, the transport from another. Leave a part as it is and yours stays.")
    ImGui.Indent(ctx, IND * UI)
    ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load the whole layout from:"); ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 260 * UI)
    if ImGui.BeginCombo(ctx, "##layoutall", "choose a persona or DAW") then
      for _, st in ipairs(sources(function(s) for _, x in ipairs(core.ASPECTS) do if x[1] ~= "mouse" and x[1] ~= "prefs" and has_aspect(s, x[1]) then return true end end end)) do
        if ImGui.Selectable(ctx, st.name .. "##lall" .. st.id) then
          core.draft_clear(bld.blocks, "layout")
          for _, x in ipairs(core.ASPECTS) do
            if x[1] ~= "mouse" and x[1] ~= "prefs" then
              if has_aspect(st, x[1]) then core.draft_add(bld.blocks, core.new_block("feel", st.id, x[1]))
              elseif x[1] ~= "dockpref" then core.draft_clear(bld.blocks, "feel " .. x[1]) end -- (no DAW has dockers of its own: yours stay)
            end
          end
          bld.active = true
          say(st.name .. "'s layout is in your persona: arrange it above, or change any part below.")
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.Unindent(ctx, IND * UI)
    card_end()
  end
  local arranged = core.draft_get(bld.blocks, "layout") ~= nil
  for _, x in ipairs(core.ASPECTS) do
    if x[1] ~= "mouse" and x[1] ~= "prefs" and x[1] ~= "dockpref" then -- (dockers: their own card, below)
      if arranged and COVERED[x[1]] then
        if card("slot " .. x[1]) then heading(x[4], 16); muted("Set by your arrangement above."); card_end() end
      else
        slot_card(x[1], x[4], x[2], "feel " .. x[1], sources(function(st) return has_aspect(st, x[1]) end), function(st) return core.new_block("feel", st.id, x[1]) end, "Leave as it is")
        if x[1] == "windows" then windows_card() end
      end
    end
  end
  dockers_card()
end
function persona_theme_line() -- (on Themes, over the list of themes)
  local b = core.draft_get(bld.blocks, "theme")
  heading("Your persona's theme", 16)
  ImGui.Indent(ctx, IND * UI)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, b and (b.file:gsub("%.ReaperTheme%a*$", "")) or "Yours (whatever theme is in use)")
  if b then ImGui.SameLine(ctx); if ImGui.SmallButton(ctx, "Leave as it is##thl") then core.draft_clear(bld.blocks, "theme") end end
  ImGui.SameLine(ctx); ImGui.Text(ctx, "  Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 220 * UI)
  if ImGui.BeginCombo(ctx, "##thfrom", "a persona or DAW") then
    for _, st in ipairs(sources(function(s) local th = core.theme_for(s); return th and reaper.file_exists(themes_dir .. th) end)) do
      if ImGui.Selectable(ctx, st.name .. "##thf" .. st.id) then core.draft_add(bld.blocks, core.new_block("theme", core.theme_for(st))); bld.active = true end
    end
    ImGui.EndCombo(ctx)
  end
  muted("Or My persona on a theme's row, below.")
  ImGui.Unindent(ctx, IND * UI)
end
