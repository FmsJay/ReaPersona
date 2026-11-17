-- Every built-in persona's mouse behaviour is one REAPER knows: each is set on its context (with Shift+Win, a combination nothing else
-- uses), read back as REAPER's own id, and put back as it was. A name REAPER doesn't know reads back "0". Run it inside REAPER (a
-- throwaway instance, or the dev-eval hook): it returns the lines that failed, or "ok N".
local here = (debug.getinfo(1, "S").source:match("^@?(.*)[/\\]tests[/\\]reaper") or (reaper.GetResourcePath() .. "/Scripts")) .. "/ReaPersona"
local core = dofile((reaper.file_exists(here .. "/reapersona_core.lua") and here or (reaper.GetResourcePath() .. "/Scripts/ReaPersona")) .. "/reapersona_core.lua")
local bad, n, seen = {}, 0, {}
for _, st in ipairs(core.styles_json.styles or {}) do
  for _, f in ipairs(st.feel or {}) do
    if f[1] == "mouse" then
      local ctx = f[2]:gsub("^%a%a%a:", "")
      local key = ctx .. "|" .. f[4]
      if not seen[key] then
        seen[key] = true
        n = n + 1
        local was = reaper.GetMouseModifier(ctx, 9, "")
        reaper.SetMouseModifier(ctx, 9, f[4])
        local got = reaper.GetMouseModifier(ctx, 9, "")
        reaper.SetMouseModifier(ctx, 9, (was ~= "" and was ~= "0") and was or "-1")
        if got == "" or got == "0" then bad[#bad + 1] = st.id .. ": " .. ctx .. " '" .. f[4] .. "'" end
        if reaper.GetMouseModifier(ctx, 9, "") ~= was then bad[#bad + 1] = ctx .. " Shift+Win not put back: was " .. was .. ", now " .. reaper.GetMouseModifier(ctx, 9, "") end
      end
    end
  end
end
return #bad == 0 and ("ok " .. n) or table.concat(bad, "\n")
