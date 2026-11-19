-- ReaPersona's window: making a persona: the draft bar, preview and undo, the slot cards.
-- (5.39: ReaPersona.lua split into ui/. Each file runs with R, one table of names every file shares (see ReaPersona.lua); the
-- engine, ImGui and Lua's own functions are kept local here, which is all the speed globals cost. Lines from ReaPersona.lua 2039-2280.)
local ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os = ipairs, pairs, tostring, tonumber, type, select, next, pcall, string, table, math, os
local ImGui, core, reaper = ImGui, core, reaper
function bld_default_name() -- the name it gets when you don't give one
  local keys = core.draft_get(bld.blocks, "keys")
  local from = bld.from or (keys and keys.id ~= "my_reaper" and (core.by_id(keys.id) or {}).name)
  return core.custom_name(from or "My REAPER")
end
function bld_new() -- an empty persona to make from the tabs
  bld.blocks, bld.name, bld.id, bld.msg, bld.active, bld.colour, bld.from = {}, "", nil, "", true, nil, nil
  bld.hist, bld.pos, bld.shown = nil, nil, nil
  bld.preview = reaper.GetExtState(SECTION, "draft preview") == "1"
  say("Making a new persona: choose its shortcuts, mouse, layout, theme, colours and so on on their tabs. The bar at the top shows it; name it and Save there.")
end
function in_persona(b, what) -- a block into its slot of the persona being made
  local _, replaced = core.draft_add(bld.blocks, b)
  bld.active = true
  say(what .. (replaced and " replaces what was" or " is") .. " in your persona" .. (bld.name ~= "" and (" (" .. bld.name .. ")") or "") .. ". Save it from the bar at the top.")
end
function persona_row(st) -- on a persona's page: its parts into the persona being made, each into its own slot
  local has = {}
  for _, f in ipairs(st.feel or {}) do has[core.aspect_of(f)] = true end
  for _, k in ipairs(core.keys_here(st.keys)) do if core.is_wheel(k[1]) then has.mouse = true end end
  local th = core.theme_for(st)
  th = th and reaper.file_exists(themes_dir .. th) and th or nil
  if #(st.keys or {}) == 0 and not next(has) and not th then return end
  ImGui.AlignTextToFramePadding(ctx); ImGui.TextColored(ctx, C.MUTED, "Use in my persona:")
  local function part(label, blocks, what)
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, label .. "##inp" .. st.id) then
      for _, b in ipairs(blocks()) do core.draft_add(bld.blocks, b) end
      bld.active = true
      say(what .. " in your persona. Fine-tune it on the Shortcuts, Mouse, Layout and Themes tabs; Save from the bar at the top.")
    end
  end
  part("All of it", function() return core.split_blocks({ core.new_block("daw", st.id) }) end, "All of " .. st.name .. " is")
  if #(st.keys or {}) > 0 then part("Shortcuts", function() return { core.keys_block(st.id) } end, st.name .. "'s shortcuts are") end
  if has.mouse then part("Mouse", function() return { core.new_block("mouse", st.id) } end, st.name .. "'s mouse is") end
  for _, x in ipairs(core.ASPECTS) do
    if has[x[1]] and x[1] ~= "mouse" then part(x[4], function() return { core.new_block("feel", st.id, x[1]) } end, st.name .. "'s " .. x[4]:lower() .. " is") end
  end
  if th then part("Theme", function() return { core.new_block("theme", th) } end, th:gsub("%.ReaperTheme%a*$", "") .. " is") end
end
function bld_blocks() -- what's saved: built in a fixed order, with your own keys when no shortcuts were chosen (they carry your startup scripts)
  local blocks = core.draft_order(bld.blocks)
  if not core.draft_get(blocks, "keys") then table.insert(blocks, 1, core.keys_block("my_reaper")) end
  return blocks
end
function bld_save() -- -> the saved persona, or nil (bld.msg says why)
  if bld.id == "my_reaper" then -- (My REAPER: everything but its keys becomes its look, on every computer; the look before is kept as a version)
    local st = core.build_style(bld_blocks(), "My REAPER", "built_try")
    if not st then bld.msg = "Not saved."; return end
    core.save_look(core.look_from_style(st))
    if reaper.GetExtState(SECTION, "style") == "my_reaper" then core.use(core.by_id("my_reaper")) end
    local keys = core.draft_get(bld.blocks, "keys")
    bld.msg = "My REAPER is saved: its layout, mouse, theme and colours are your look on every computer (Earlier versions, on its page, puts one back)." ..
      ((keys and keys.id ~= "my_reaper") and " Its shortcuts are your own keymap, so another persona's keys don't go into it." or "")
    say(bld.msg)
    return core.by_id("my_reaper")
  end
  if bld.name:match("^%s*$") then bld.name = bld_default_name() end -- (never over a DAW: a new persona, "<DAW> - custom" unless you name it)
  local st, install = core.save_built(bld_blocks(), bld.name, bld.id)
  if st then
    bld.id, selected, ensure_new = st.id, st.id, true
    if bld.back or reaper.GetExtState(SECTION, "style") == st.id then core.use(st); bld.back = nil end -- (the persona in use: its changes now)
    bld.msg = st.name .. " is saved: it's in Personas > Your personas." .. (install and " Install its shortcuts on Home (REAPER restarts) to use its keys." or "")
    say(bld.msg)
    return st
  end
  bld.msg = "Not saved: " .. tostring(install)
end
-- Preview and undo while making a persona (5.38; James: "have changes audition in the background on reaper so you could see how it would
-- look in real time, along with an undo"). Every change on any tab is kept (bld.hist: the blocks as JSON, looked at 4 times a second),
-- Undo/Redo step through them, and with Preview on the persona as it stands goes into REAPER a moment after each change, as Try it does.
function bld.try(quiet) -- the persona as chosen so far, in REAPER now; Go back, Stop or turning Preview off put yours back
  local st, install = core.build_style(bld_blocks(), bld.name ~= "" and bld.name or "Your persona", "built_try")
  if not st then bld.later = "Can't preview it: " .. tostring(install); if not quiet then say("Can't try it: " .. tostring(install)) end return end
  if install then st.alt = 0 end -- (keys from several DAWs need their layer installed: the trial keeps your own keys)
  local later = {} -- (what a preview can't show: it goes in after a restart, or with a new project)
  if install then later[#later + 1] = "its shortcuts (your own until it's saved and installed: they mix DAWs)" end
  for _, b in ipairs(bld.blocks) do
    if b.kind == "feel" and b.aspect == "prefs" then later[#later + 1] = "REAPER preferences (when REAPER restarts)"
    elseif b.kind == "project" then later[#later + 1] = "the project part (a new, empty project)" end
  end
  bld.later = #later > 0 and ("Not shown until later: " .. table.concat(later, "; ") .. ".") or nil
  bld.back = bld.back or core.current().id
  core.use(st)
  if not quiet then say("Trying it" .. (install and " (with your own shortcuts until it's saved and installed)" or "") .. ". Save it, or Go back.") end
end
function bld.step(d) -- Undo (-1) or Redo (+1) of your changes to the persona being made
  local h = bld.hist
  if not (h and h[(bld.pos or 0) + d]) then return end
  local ok, t = pcall(core.json_decode, h[bld.pos + d])
  if not ok or type(t) ~= "table" then return end
  bld.pos, bld.blocks, bld.stepped, bld.changed_at = bld.pos + d, t, true, reaper.time_precise()
  local c = core.draft_get(bld.blocks, "colour")
  bld.colour = c and tonumber((c.hex or ""):gsub("#", ""), 16) or nil
  say((d < 0 and "Undone" or "Redone") .. (bld.preview and ": REAPER follows in a moment." or "."))
end
function bld.tick() -- each frame: the change history, Ctrl+Z / Ctrl+Shift+Z, and the preview
  if not bld.active and #bld.blocks == 0 then bld.hist, bld.pos = nil, nil; return end
  local now = reaper.time_precise()
  if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) and not ImGui.IsAnyItemActive(ctx) and not (bld.kq and bld.kq.cap) then
    if ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Mod_Shift | ImGui.Key_Z) or ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_Y) then bld.step(1)
    elseif ImGui.IsKeyChordPressed(ctx, ImGui.Mod_Ctrl | ImGui.Key_Z) then bld.step(-1) end
  end
  if now - (bld.seen_at or 0) < 0.25 then return end
  bld.seen_at = now
  local s = core.json_encode(bld.blocks)
  if not bld.hist then bld.hist, bld.pos, bld.shown = { s }, 1, s
  elseif bld.stepped then bld.hist[bld.pos], bld.stepped = s, nil -- (the step's own state, as this encodes it)
  elseif s ~= bld.hist[bld.pos] then
    for i = #bld.hist, bld.pos + 1, -1 do bld.hist[i] = nil end -- (a change after an undo: what was undone can't be redone)
    bld.hist[#bld.hist + 1] = s
    if #bld.hist > 60 then table.remove(bld.hist, 1) end
    bld.pos, bld.changed_at = #bld.hist, now
  end
  -- (a moment after the last change, and not while the last switch's window moves are still going)
  if bld.preview and bld.shown ~= bld.hist[bld.pos] and now - (bld.changed_at or 0) > 0.6 and not core.busy() then
    bld.shown = bld.hist[bld.pos]
    bld.try(true)
  end
end
function draft_strip() -- the persona being made, over every tab
  if not bld.active and #bld.blocks == 0 then return end
  local titles = {}
  for _, b in ipairs(core.draft_order(bld.blocks)) do if b.kind ~= "colour" then titles[#titles + 1] = core.block_title(b) end end
  if card("draft strip") then
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, C.ACCENT, bld.id and ("Editing " .. bld.name) or ("Making " .. (bld.name ~= "" and bld.name or bld_default_name())))
    ImGui.SameLine(ctx)
    ImGui.TextWrapped(ctx, #titles > 0 and table.concat(titles, "  ·  ") or "Nothing chosen yet: pick its shortcuts, mouse, layout, theme, colours or project on their tabs (your own setup fills in the rest).")
    ImGui.SetNextItemWidth(ctx, 220 * UI)
    local _, n = ImGui.InputTextWithHint(ctx, "##stripname", bld_default_name(), bld.name); bld.name = n
    ImGui.SetItemTooltip(ctx, "Its name. Left empty, it's saved as the name shown here.")
    ImGui.SameLine(ctx)
    local ch, col = ImGui.ColorEdit3(ctx, "##stripcol", bld.colour or 0x3A86FF, ImGui.ColorEditFlags_NoInputs)
    if ch then bld.colour = col; core.draft_add(bld.blocks, core.new_block("colour", string.format("#%06X", col))) end
    ImGui.SetItemTooltip(ctx, "Its colour in ReaPersona: its card, buttons and badge.")
    ImGui.SameLine(ctx); if ImGui.GetContentRegionAvail(ctx) < 110 * UI then ImGui.NewLine(ctx) end -- (a narrow window: the buttons go on)
    if primary(bld.id and "Save changes##strip" or "Save as new##strip") then bld_save() end
    ImGui.SetItemTooltip(ctx, bld.id and ("Saves over " .. bld.name .. ", which you made.") or "A new persona of yours: the DAWs and personas it came from stay as they are.")
    ImGui.SameLine(ctx); if ImGui.GetContentRegionAvail(ctx) < 60 * UI then ImGui.NewLine(ctx) end
    if not bld.preview and ImGui.Button(ctx, "Try it##strip") then bld.try() end
    ImGui.SameLine(ctx); if ImGui.GetContentRegionAvail(ctx) < 170 * UI then ImGui.NewLine(ctx) end
    local pch, pon = ImGui.Checkbox(ctx, "Preview as I change##strip", bld.preview == true)
    if pch then
      bld.preview = pon
      reaper.SetExtState(SECTION, "draft preview", pon and "1" or "0", true)
      if pon then bld.shown = nil; bld.changed_at = 0; say("Preview on: each change goes into REAPER a moment after you make it. Turning it off puts yours back.")
      elseif bld.back then local back = core.by_id(bld.back); bld.back, bld.later = nil, nil; if back then use(back) end end
    end
    ImGui.SetItemTooltip(ctx, "Each change you make on any tab goes into REAPER a moment later, so you see it as you go. Off, Stop or Go back puts what you had back, exactly as it was.")
    ImGui.SameLine(ctx); if ImGui.GetContentRegionAvail(ctx) < 120 * UI then ImGui.NewLine(ctx) end
    local can_undo, can_redo = bld.hist and bld.pos and bld.pos > 1, bld.hist and bld.pos and bld.hist[bld.pos + 1] ~= nil
    if not can_undo then ImGui.BeginDisabled(ctx) end
    if ImGui.Button(ctx, "Undo##strip") then bld.step(-1) end
    if not can_undo then ImGui.EndDisabled(ctx) end
    ImGui.SetItemTooltip(ctx, "Your last change to this persona, undone (" .. MOD .. "+Z).")
    ImGui.SameLine(ctx)
    if not can_redo then ImGui.BeginDisabled(ctx) end
    if ImGui.Button(ctx, "Redo##strip") then bld.step(1) end
    if not can_redo then ImGui.EndDisabled(ctx) end
    ImGui.SetItemTooltip(ctx, "The change you undid, back (" .. MOD .. "+Shift+Z).")
    if bld.back then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Go back##strip") then local back = core.by_id(bld.back); bld.back, bld.preview, bld.later = nil, false, nil; if back then use(back) end end
      ImGui.SetItemTooltip(ctx, "Back to " .. ((core.by_id(bld.back) or {}).name or "the persona you had") .. ", exactly as it was.")
    end
    ImGui.SameLine(ctx); if ImGui.GetContentRegionAvail(ctx) < 50 * UI then ImGui.NewLine(ctx) end
    if ImGui.Button(ctx, "Stop##strip") and (#bld.blocks == 0 or bld.snap == core.json_encode(bld.blocks)
        or reaper.MB(bld.id and ("Stop editing " .. bld.name .. "? Changes you haven't saved are lost.") or "Stop making this persona? What you chose isn't saved.", "ReaPersona", 4) == 6) then -- (asks first: review 2026-11-18)
      if bld.back then local b = core.by_id(bld.back); bld.back = nil; if b then use(b) end end -- (out of a trial: what you had)
      bld.blocks, bld.name, bld.id, bld.msg, bld.active, bld.colour, bld.from, bld.snap = {}, "", nil, "", false, nil, nil, nil
      bld.hist, bld.pos, bld.later = nil, nil, nil
    end
    ImGui.SetItemTooltip(ctx, "Stop making it: nothing is saved, and personas you have stay as they are.")
    if bld.preview and bld.later then muted(bld.later) end
    if bld.msg ~= "" then muted(bld.msg) end
    card_end()
  end
end

-- One slot on its tab: which persona it comes from (or leave it as it is), then each line it sets, to untick.
function sources(test) -- every persona (DAWs, yours, saved setups) that has something for this slot
  local out = {}
  for _, list in ipairs({ styles, core.presets }) do
    for _, st in ipairs(list) do if st.kind ~= "theme" and st.id ~= "built_try" and test(st) then out[#out + 1] = st end end
  end
  return out
end
function entry_line(e, b)
  local ch, v = ImGui.Checkbox(ctx, "##on" .. e.slot, not e.off)
  if ch then b.off = type(b.off) == "table" and b.off or {}; b.off[e.slot] = (not v) or nil end
  ImGui.SetItemTooltip(ctx, e.off and "Tick to put this back in the persona" or "Untick to leave this out of the persona")
  ImGui.SameLine(ctx)
  local text = (e.key and (keyname(e.key) .. "  ") or "") .. tostring(e.label)
  if e.off then ImGui.TextColored(ctx, C.MUTED, text .. "   (left out)")
  elseif e.kind == "feel" and not core.aspect_on(core.aspect_of(e.entry)) then ImGui.TextColored(ctx, C.YELLOW, text .. "   (off in Settings > Personas)")
  else ImGui.Text(ctx, text) end
end
function slot_card(id, title, tip, slot, list, make, leave, section_of)
  if not card("slot " .. id) then return end
  heading(title, 16)
  if tip then muted(tip) end
  ImGui.Indent(ctx, IND * UI)
  local b = core.draft_get(bld.blocks, slot)
  local from = b and b.id and core.by_id(b.id)
  ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx, "Load from:"); ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 260 * UI)
  if ImGui.BeginCombo(ctx, "##from" .. id, b and (from and from.name or core.block_title(b)) or leave) then
    if ImGui.Selectable(ctx, leave .. "##leave" .. id, b == nil) then core.draft_clear(bld.blocks, slot); bld.active = true end
    for _, st in ipairs(list) do
      if ImGui.Selectable(ctx, st.name .. "##" .. id .. st.id, b ~= nil and b.id == st.id) then core.draft_add(bld.blocks, make(st)); bld.active = true end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetItemTooltip(ctx, "Loads that persona's or DAW's settings for this part only. Choosing here starts a new persona if you're not making one (the bar at the top).")
  if b then
    local lines, keys, sections, order = core.build_preview({ b })[1], {}, {}, {}
    for _, e in ipairs(lines) do
      if e.entry and e.entry[1] == "mouse" and not core.for_os(e.entry[2]) then -- (the other system's mouse lines: not here)
      elseif section_of then
        local s = section_of(e)
        if not sections[s] then sections[s] = {}; order[#order + 1] = s end
        table.insert(sections[s], e)
      elseif e.kind == "key" or e.kind == "midi" then keys[#keys + 1] = e
      else entry_line(e, b) end
    end
    for _, s in ipairs(order) do ImGui.TextColored(ctx, C.MUTED, s); for _, e in ipairs(sections[s]) do entry_line(e, b) end end
    if #keys > 0 and (slot ~= "keys" or ImGui.TreeNode(ctx, #keys .. " shortcuts##k" .. id)) then
      for _, e in ipairs(keys) do entry_line(e, b) end
      if slot == "keys" then ImGui.TreePop(ctx) end
    end
    if #lines == 0 then muted("Nothing of this kind there.") end
  end
  ImGui.Unindent(ctx, IND * UI)
  card_end()
end
function has_aspect(st, a) for _, f in ipairs(st.feel or {}) do if core.aspect_of(f) == a then return true end end return false end
function has_mouse(st)
  if has_aspect(st, "mouse") then return true end
  for _, k in ipairs(core.keys_here(st.keys)) do if core.is_wheel(k[1]) then return true end end
  return false
end
