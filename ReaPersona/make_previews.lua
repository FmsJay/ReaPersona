-- @noindex
-- ReaPersona: a preview picture of each style, in previews/<id>.png. Opens the demo song (demo/ReaPersona demo.rpp, made by
-- make_demo.lua) in its own tab, uses each style in turn (theme, toolbar, transport, everything) with the mixer docked so its look
-- shows, hides other scripts' windows (StudioSync's) while it captures, then puts back the style, tab and windows you had.
-- Each style is on for about two seconds. Run it as an action (or through a dev hook); js_ReaScriptAPI captures the window.
local here = debug.getinfo(1, "S").source:match("^@?(.*)[/\\]")
local core = dofile(here .. "/reapersona_core.lua")
local only = reaper.GetExtState("ReaPersona", "preview only") -- (a style id to retake just that one; "" = all)
local demo = here .. "/demo/ReaPersona demo.rpp"
if not reaper.file_exists(demo) then return "no demo song yet: run make_demo.lua" end
local WIDTH = 1000
reaper.RecursiveCreateDirectory(here .. "/previews", 0)

local shots = {}
for _, st in ipairs(core.styles) do if only == "" or st.id == only then shots[#shots + 1] = st end end
local was_style, was_proj = core.current(), reaper.EnumProjects(-1)
local was_mixer, was_docked = reaper.GetToggleCommandState(40078), reaper.GetToggleCommandState(40083)
reaper.Main_OnCommand(40859, 0) -- New project tab
reaper.Main_openProject("noprompt:" .. demo)
local demo_proj = reaper.EnumProjects(-1)

local hidden = {}
local function hide_others(on)
  if on then
    local _, list = reaper.JS_Window_ListFind("StudioSync", false)
    for a in (list or ""):gmatch("[^,]+") do
      local h = reaper.JS_Window_HandleFromAddress(tonumber(a) or tonumber(a, 16))
      if h and reaper.JS_Window_IsVisible(h) then reaper.JS_Window_Show(h, "HIDE"); hidden[#hidden + 1] = h end
    end
  else
    for _, h in ipairs(hidden) do reaper.JS_Window_Show(h, "SHOW") end
    hidden = {}
  end
end

local function capture(path)
  local hwnd = reaper.GetMainHwnd()
  local _, l, t, r, b = reaper.JS_Window_GetRect(hwnd)
  local w, h = r - l, b - t
  local full = reaper.JS_LICE_CreateBitmap(true, w, h)
  local src = reaper.JS_GDI_GetWindowDC(hwnd)
  reaper.JS_GDI_Blit(reaper.JS_LICE_GetDC(full), 0, 0, src, 0, 0, w, h)
  reaper.JS_GDI_ReleaseDC(src, hwnd)
  local top = math.floor(36 * w / WIDTH) -- (leave out the title bar, menu and project tabs: your project names)
  local sh = math.floor((h - top) * WIDTH / w)
  local small = reaper.JS_LICE_CreateBitmap(true, WIDTH, sh)
  reaper.JS_LICE_ScaledBlit(small, 0, 0, WIDTH, sh, full, 0, top, w, h - top, 1, "FAST")
  local ok = reaper.JS_LICE_WritePNG(path, small, false)
  reaper.JS_LICE_DestroyBitmap(full); reaper.JS_LICE_DestroyBitmap(small)
  return ok
end

local i, at = 0, 0
local function finish()
  hide_others(false)
  core.use(was_style)
  if reaper.GetToggleCommandState(40083) ~= was_docked then reaper.Main_OnCommand(40083, 0) end -- (the mixer docked as you had it)
  if reaper.GetToggleCommandState(40078) ~= was_mixer then reaper.Main_OnCommand(40078, 0) end
  if reaper.IsProjectDirty(demo_proj) == 0 then reaper.SelectProjectInstance(demo_proj); reaper.Main_OnCommand(40860, 0) end -- close the demo tab
  if was_proj then reaper.SelectProjectInstance(was_proj) end
end
local function step()
  if i > 0 and reaper.time_precise() - at < 2.0 then return reaper.defer(step) end -- (time for the theme, toolbar and docks to settle)
  if i > 0 then capture(here .. "/previews/" .. shots[i].id .. ".png") end
  i = i + 1
  if i > #shots then return finish() end
  hide_others(false)
  core.use(shots[i])
  local docked = true -- (a style whose mixer is its own window shows its edit window instead: a floating mixer isn't in the capture)
  for _, f in ipairs(shots[i].feel or {}) do if f[1] == "toggle" and f[2] == 40083 then docked = f[3] == 1 end end
  if reaper.GetToggleCommandState(40078) ~= (docked and 1 or 0) then reaper.Main_OnCommand(40078, 0) end
  if docked and reaper.GetToggleCommandState(40083) ~= 1 then reaper.Main_OnCommand(40083, 0) end
  reaper.Main_OnCommand(40295, 0)
  hide_others(true)
  at = reaper.time_precise()
  reaper.defer(step)
end
step()
return "taking " .. #shots .. " previews"
