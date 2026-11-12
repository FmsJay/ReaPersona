-- @noindex
-- ReaPersona: builds templates/<style>.RPP, a new-project layout per DAW (its usual starting tracks, buses and sends), with REAPER's
-- own plugins only. Each is made in a new project tab, saved and the tab closed; your projects aren't touched. Run from the Actions list.
local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
local core = dofile(here .. "/reapersona_core.lua")
local SYNTH, VERB, DELAY = "ReaSynth (Cockos)", "ReaVerbate (Cockos)", "ReaDelay (Cockos)"
-- { name, kind, fx, sends-to (names), folder (1 starts a folder, -1 ends it) }; kind: "audio", "midi", "bus"
local T = {
  pro_tools = { { "Audio 1" }, { "Audio 2" }, { "Audio 3" }, { "Audio 4" }, { "Audio 5" }, { "Audio 6" }, { "Audio 7" }, { "Audio 8" },
    { "Aux 1 (Reverb)", "bus", VERB } },
  logic = { { "Audio 1" }, { "Audio 2" }, { "Inst 1", "midi", SYNTH }, { "Inst 2", "midi", SYNTH }, { "Bus 1 (Reverb)", "bus", VERB } },
  ableton = { { "1 MIDI", "midi", SYNTH }, { "2 MIDI", "midi", SYNTH }, { "3 Audio" }, { "4 Audio" },
    { "A Reverb", "bus", VERB, nil, nil, true }, { "B Delay", "bus", DELAY, nil, nil, true } },
  fl_studio = { { "Drums", nil, nil, nil, 1 }, { "Kick" }, { "Snare" }, { "Hat" }, { "Clap", nil, nil, nil, -1 },
    { "Bass", "midi", SYNTH }, { "Lead", "midi", SYNTH }, { "Insert 1 (Reverb)", "bus", VERB } },
  cubase = { { "Audio 01" }, { "Audio 02" }, { "Audio 03" }, { "Audio 04" }, { "Instrument 01", "midi", SYNTH },
    { "FX 1-Reverb", "bus", VERB } },
  studio_one = { { "Audio 1" }, { "Audio 2" }, { "Audio 3" }, { "Audio 4" }, { "Instrument 1", "midi", SYNTH }, { "FX: Reverb", "bus", VERB } },
  bitwig = { { "Inst 1", "midi", SYNTH }, { "Inst 2", "midi", SYNTH }, { "Audio 1" }, { "Audio 2" },
    { "FX 1 (Reverb)", "bus", VERB, nil, nil, true }, { "FX 2 (Delay)", "bus", DELAY, nil, nil, true } },
  cakewalk = { { "Audio 1" }, { "Audio 2" }, { "Audio 3" }, { "Audio 4" }, { "Instrument 1", "midi", SYNTH }, { "Bus A (Reverb)", "bus", VERB } },
  reason = { { "Mix Channel 1" }, { "Mix Channel 2" }, { "Mix Channel 3" }, { "Instrument 1", "midi", SYNTH }, { "FX Reverb", "bus", VERB } },
  audacity = { { "Voice" }, { "Guest" }, { "Music" } },
  audition = { { "Track 1" }, { "Track 2" }, { "Track 3" }, { "Track 4" }, { "Bus A (Reverb)", "bus", VERB } },
}
local function hexcol(h) h = (h or "#808080"):gsub("#", ""); return reaper.ColorToNative(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) | 0x1000000 end
reaper.RecursiveCreateDirectory(here .. "/templates", 0)
local was = reaper.EnumProjects(-1)
local made = {}
for id, list in pairs(T) do
  local st = core.by_id(id)
  reaper.Main_OnCommand(40859, 0) -- (New project tab)
  local proj = reaper.EnumProjects(-1)
  local buses, tracks = {}, {}
  for i, t in ipairs(list) do
    reaper.InsertTrackAtIndex(i - 1, true)
    local tr = reaper.GetTrack(proj, i - 1)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", t[1], true)
    if t[2] ~= "bus" then reaper.SetTrackColor(tr, hexcol(st and st.accent)) end
    if t[2] == "midi" then reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", 4096 + (63 << 5)) end -- (MIDI: all inputs, all channels)
    if t[3] then reaper.TrackFX_AddByName(tr, t[3], false, -1) end
    if t[5] then reaper.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", t[5]) end
    if t[2] == "bus" then buses[#buses + 1] = { tr = tr, silent = t[6] } else tracks[#tracks + 1] = tr end
  end
  for _, b in ipairs(buses) do -- (every track sends to every bus; Live- and Bitwig-style returns start silent)
    for _, tr in ipairs(tracks) do
      if reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") ~= 1 then
        local s = reaper.CreateTrackSend(tr, b.tr)
        reaper.SetTrackSendInfo_Value(tr, 0, s, "D_VOL", b.silent and 0 or 0.25) -- (-12 dB)
      end
    end
  end
  local path = here .. "/templates/" .. id .. ".RPP"
  reaper.Main_SaveProjectEx(proj, path, 0)
  reaper.Main_openProject("noprompt:" .. path) -- (the saved file back into this tab: nothing unsaved, so it closes without asking)
  reaper.Main_OnCommand(40860, 0) -- (Close current project tab)
  made[#made + 1] = id
end
reaper.SelectProjectInstance(was)
return made
