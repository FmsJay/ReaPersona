-- @noindex
-- ReaPersona: build the demo song the previews are taken from (demo/ReaPersona demo.rpp), in a new project tab, and save it.
-- Stock REAPER plug-ins only and MIDI parts (no audio files), so it opens the same on any computer.
local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
local path = here .. "/demo/ReaPersona demo.rpp"
reaper.RecursiveCreateDirectory(here .. "/demo", 0)
reaper.Main_OnCommand(40859, 0) -- New project tab
local proj = 0
reaper.PreventUIRefresh(1)
reaper.SetCurrentBPM(proj, 120, false)
local bar = 2.0 -- seconds per 4/4 bar at 120

local function track(name, colour, depth, fx)
  local n = reaper.CountTracks(proj)
  reaper.InsertTrackAtIndex(n, true)
  local tr = reaper.GetTrack(proj, n)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  reaper.SetTrackColor(tr, reaper.ColorToNative(colour[1], colour[2], colour[3]))
  reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", depth or 0)
  for _, f in ipairs(fx or {}) do reaper.TrackFX_AddByName(tr, f, false, -1) end
  return tr
end
local function part(tr, name, from_bar, bars, notes) -- notes: {start beat, length beats, pitch, velocity}, repeated each 4 bars
  local item = reaper.CreateNewMIDIItemInProj(tr, from_bar * bar, (from_bar + bars) * bar, false)
  local take = reaper.GetActiveTake(item)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  for rep = 0, bars - 1, 4 do
    for _, n in ipairs(notes) do
      local s = (from_bar + rep) * bar + n[1] * bar / 4
      local ps = reaper.MIDI_GetPPQPosFromProjTime(take, s)
      local pe = reaper.MIDI_GetPPQPosFromProjTime(take, s + n[2] * bar / 4)
      reaper.MIDI_InsertNote(take, false, false, ps, pe, 0, n[3], n[4] or 96, true)
    end
  end
  reaper.MIDI_Sort(take)
  return item
end

local band = track("Band", { 70, 90, 120 }, 1)
local drums = track("Drums", { 200, 80, 60 }, 0, { "ReaSynth (Cockos)", "ReaComp (Cockos)" })
local bass = track("Bass", { 220, 160, 50 }, 0, { "ReaSynth (Cockos)", "ReaEQ (Cockos)" })
local keys = track("Keys", { 80, 170, 90 }, -1, { "ReaSynth (Cockos)", "ReaEQ (Cockos)", "ReaDelay (Cockos)" })
local lead = track("Lead", { 90, 130, 220 }, 0, { "ReaSynth (Cockos)", "ReaComp (Cockos)", "ReaEQ (Cockos)" })
local verb = track("Reverb", { 150, 100, 200 }, 0, { "ReaVerbate (Cockos)" })
for _, tr in ipairs({ drums, keys, lead }) do reaper.CreateTrackSend(tr, verb) end

local beat = {}
for b = 0, 15 do
  beat[#beat + 1] = { b, 0.5, 42, 70 }                                -- hats
  if b % 8 == 0 or b == 10 then beat[#beat + 1] = { b, 0.5, 36, 110 } end -- kick
  if b % 8 == 4 then beat[#beat + 1] = { b, 0.5, 38, 105 } end        -- snare
end
local chords = { { 0, 4, 57 }, { 0, 4, 60 }, { 0, 4, 64 }, { 4, 4, 53 }, { 4, 4, 57 }, { 4, 4, 60 },
                 { 8, 4, 48 }, { 8, 4, 52 }, { 8, 4, 55 }, { 12, 4, 55 }, { 12, 4, 59 }, { 12, 4, 62 } }
local bassline = { { 0, 3, 45 }, { 3, 1, 45 }, { 4, 3, 41 }, { 7, 1, 43 }, { 8, 3, 36 }, { 11, 1, 38 }, { 12, 4, 43 } }
local melody = { { 0, 2, 69 }, { 2, 1, 72 }, { 3, 1, 71 }, { 4, 3, 69 }, { 8, 2, 67 }, { 10, 2, 64 }, { 12, 3, 67 }, { 15, 1, 69 } }
part(drums, "Beat", 0, 16, beat)
part(bass, "Bassline", 4, 12, bassline)
part(keys, "Chords", 0, 16, chords)
part(lead, "Melody", 8, 8, melody)

for _, r in ipairs({ { 0, 4, "Intro" }, { 4, 8, "Verse" }, { 8, 16, "Chorus" } }) do
  reaper.AddProjectMarker2(proj, true, r[1] * bar, r[2] * bar, r[3], -1, 0)
end
reaper.AddProjectMarker2(proj, false, 12 * bar, 0, "Drop", -1, 0)
-- a volume ride on Keys, so an envelope shows
local env = reaper.GetTrackEnvelopeByName(keys, "Volume")
if not env then reaper.SetOnlyTrackSelected(keys); reaper.Main_OnCommand(40406, 0); env = reaper.GetTrackEnvelopeByName(keys, "Volume") end
if env then
  for i, p in ipairs({ { 0, 0.5 }, { 8, 0.5 }, { 10, 1.0 }, { 16, 0.8 } }) do reaper.InsertEnvelopePoint(env, p[1] * bar, p[2], 0, 0, false, true) end
  reaper.Envelope_SortPoints(env)
end
reaper.GetSet_LoopTimeRange(true, true, 8 * bar, 12 * bar, false)
reaper.SetEditCurPos(6 * bar, false, false)
reaper.SetOnlyTrackSelected(lead)
reaper.PreventUIRefresh(-1)
reaper.Main_OnCommand(40295, 0) -- zoom to the whole song
reaper.Main_SaveProjectEx(proj, path, 0)
return path
