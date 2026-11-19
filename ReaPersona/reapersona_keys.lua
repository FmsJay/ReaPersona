-- ReaPersona's key helpers: what persona keys run through ReaPersona's own scripts (play from start, the Pro Tools edit modes,
-- duplicate, new track like this...). Only REAPER's API: an action stub loads this small file, not the whole engine (5.39; the
-- engine took 25-28 ms to load on every key press). reapersona_core.lua has each of these as M.<name> too.
local M = {}
function M.memory_location() -- Pro Tools: period, number, period on the numeric keypad recalls a memory location (here: a marker)
  local ok, s = reaper.GetUserInputs("Memory Location", 1, "Number (then Enter),extrawidth=-40", "")
  local n = ok and tonumber((s:gsub("%D", "")))
  if n then reaper.GoToMarker(0, n, false) end
end
function M.play_from_start() -- Bitwig: Alt+Space plays the arrangement from the beginning
  reaper.CSurf_GoStart(); reaper.OnPlayButton()
end
function M.duplicate_to_new_track()
  local item = reaper.GetSelectedMediaItem(0, 0)
  if not item then return end
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local pos = s
  if s >= e then
    pos = math.huge
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do pos = math.min(pos, reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, i), "D_POSITION")) end
  end
  local cur = reaper.GetCursorPosition()
  reaper.Undo_BeginBlock(); reaper.PreventUIRefresh(1)
  reaper.Main_OnCommand(s < e and 40060 or 40698, 0) -- (Item: Copy selected area of items / Edit: Copy items)
  local idx = math.floor(reaper.GetMediaTrackInfo_Value(reaper.GetMediaItem_Track(item), "IP_TRACKNUMBER"))
  reaper.InsertTrackAtIndex(idx, true)
  reaper.SetOnlyTrackSelected(reaper.GetTrack(0, idx))
  reaper.Main_OnCommand(40914, 0) -- (the new track is the last touched one, where Paste goes)
  reaper.SetEditCurPos(pos, false, false)
  reaper.Main_OnCommand(42398, 0) -- (Item: Paste items/tracks)
  reaper.SetEditCurPos(cur, false, false)
  reaper.PreventUIRefresh(-1); reaper.Undo_EndBlock("Duplicate to a new track", -1)
end
function M.autopunch()
  reaper.Main_OnCommand(reaper.GetToggleCommandState(40076) == 1 and 40252 or 40076, 0)
end
function M.without_ripple(cmd)
  local id = tonumber(cmd) or reaper.NamedCommandLookup(cmd)
  if id == 0 then return end
  local per, all = reaper.GetToggleCommandState(41990) == 1, reaper.GetToggleCommandState(41991) == 1
  reaper.Undo_BeginBlock()
  if per or all then reaper.Main_OnCommand(40309, 0) end -- (ripple off)
  reaper.Main_OnCommand(id, 0)
  if all then reaper.Main_OnCommand(40311, 0) elseif per then reaper.Main_OnCommand(40310, 0) end
  reaper.Undo_EndBlock("Delete leaving a gap", -1)
end
function M.notation_editor()
  if not reaper.GetSelectedMediaItem(0, 0) then return end
  reaper.Main_OnCommand(40153, 0) -- (Item: Open in built-in MIDI editor)
  local me = reaper.MIDIEditor_GetActive()
  if me then reaper.MIDIEditor_OnCommand(me, 40954) end
end
function M.run_modes(list) -- (5.37) several actions in a row: "40310,40753" (ids, or named "_..." ones). Options only, so no undo step
  for c in tostring(list):gmatch("[^,%s]+") do
    local id = tonumber(c) or reaper.NamedCommandLookup(c)
    if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end
  end
end
function M.run_cmds(list, name) -- the same as one undo step called name
  reaper.Undo_BeginBlock()
  M.run_modes(list)
  reaper.Undo_EndBlock(name or "ReaPersona", -1)
end
function M.duplicate_selection() -- Pro Tools' Cmd+D: the time selection's part of the items when there is one, else the items (41296 alone does nothing then)
  local a, b = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  reaper.Main_OnCommand(b > a and 41296 or 41295, 0)
end
function M.new_track_like_this() -- Logic's "New Track With Duplicate Settings": duplicate, then empty it (items unselected first, so none elsewhere go)
  M.run_cmds("40062,40289,40421,40006", "New track like this")
end
return M
