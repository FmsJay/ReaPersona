-- @noindex
-- Bug reports, feedback and feature requests from inside ReaPersona (James, 5.11: "add the same feedback button to ReaPersona that's in
-- StudioSync"; StudioSync's lib/feedback.lua, with ReaPersona's places).
--   Your sync folder, when you sync (Settings > Your other computers): <folder>/feedback/<kind>-<UTC>-<computer>.md, one file each (one
--     writer, so Syncthing never conflicts), so it reaches your other computers. Without one: ReaPersona/feedback/ on this computer.
--   GitHub: opens a new issue on github.com/FmsJay/ReaPersona in the browser, filled in (title, body, label), for the person to send with
--     their own GitHub account. Nothing is sent from here: no token, no account of ours.
-- GitHub needs a title: a blank subject takes the body's first line, a blank body says so. A report needs one or the other.
local F = {}

F.REPO = "https://github.com/FmsJay/ReaPersona"
F.KINDS = { { "bug", "Bug report", "bug", "What happened, and what you expected. Steps to make it happen again help most." },
  { "feedback", "Feedback", "feedback", "What works, what's confusing, what you'd change." },
  { "feature", "Feature request", "enhancement", "What you'd like it to do, and what for: a DAW, a function, a setting, a way of working." } }
F.URL_MAX = 7000 -- (browsers and GitHub take about 8 KB of address: the rest is cut, saying so)

local function kind_of(k) for _, x in ipairs(F.KINDS) do if x[1] == k then return x end end return F.KINDS[1] end

-- The title and body a report goes out with. Pure. -> title, body, or nil + why.
function F.compose(kind, subject, body)
  subject, body = (subject or ""):match("^%s*(.-)%s*$"), (body or ""):match("^%s*(.-)%s*$")
  if subject == "" and body == "" then return nil, "Write a subject or what happened first." end
  if subject == "" then subject = body:match("^[^\r\n]*"):sub(1, 80) end
  if body == "" then body = "(no details: the subject says it)" end
  local tag = ({ bug = "[Bug] ", feedback = "[Feedback] ", feature = "[Feature] " })[kind] or ""
  return tag .. subject, body
end

-- %-encoding for a URL's query. Pure.
function F.encode(s) return (s:gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end)) end

-- The new-issue address for GitHub, kept under URL_MAX (the body cut from the end, saying so). Pure.
function F.issue_url(title, body, label)
  local function url(b)
    return F.REPO .. "/issues/new?title=" .. F.encode(title) .. "&labels=" .. F.encode(label) .. "&body=" .. F.encode(b)
  end
  local u = url(body)
  local cut = #body
  while #u > F.URL_MAX and cut > 0 do
    cut = math.floor(cut * 0.8)
    u = url(body:sub(1, cut) .. "\n\n(cut short: the full report is in ReaPersona's feedback folder)")
  end
  return u
end

-- What this computer runs, for the report.
function F.system(core, version)
  local ok, have, mode = pcall(reaper.GetAudioDeviceInfo, "MODE")
  local cur = core.current()
  local lines = { "- ReaPersona " .. tostring(version), "- REAPER " .. reaper.GetAppVersion() .. " on " .. reaper.GetOS(),
    "- Audio: " .. ((ok and have and mode ~= "") and mode or "?"), "- Persona in use: " .. tostring(cur and cur.name),
    "- Syncing: " .. (core.sync_folder() ~= "" and "yes" or "no") }
  return table.concat(lines, "\n")
end

-- The last lines of errors.log (newest last). Pure but for the read.
function F.recent_errors(core, n)
  local t = core.read(core.here .. "/errors.log") or ""
  local lines = {}
  for l in t:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
  local out = {}
  for i = math.max(1, #lines - (n or 15) + 1), #lines do out[#out + 1] = "    " .. lines[i] end
  return out
end

-- Where a report is saved. -> the folder, and whether it's the shared one
function F.folder(core)
  local dir = core.sync_folder():gsub("[/\\]+$", "")
  if dir ~= "" then return dir .. "/feedback", true end
  return core.here .. "/feedback", false
end

-- Save it. -> path, or nil + why.
function F.save(core, kind, title, body, extra)
  local dir = F.folder(core)
  reaper.RecursiveCreateDirectory(dir, 0)
  local who = core.computer()
  local path = string.format("%s/%s-%s-%s.md", dir, kind, os.date("!%Y%m%d-%H%M%SZ"), (who:gsub("[^%w%-_]", "_")))
  local text = "# " .. title .. "\n\n" .. kind_of(kind)[2] .. " from " .. who .. ", " .. os.date("!%Y-%m-%d %H:%M UTC") .. "\n\n" .. body .. "\n\n" .. (extra or "") .. "\n"
  if not core.write(path, text) then return nil, "couldn't write " .. path end
  return path
end

-- ---------------------------------------------------------------- the window
local st = { open = false, kind = "bug", subject = "", body = "", folder = true, github = false, log = true }

-- The button that opens it.
function F.button(ctx, ImGui)
  if ImGui.Button(ctx, "Feedback##fb") then st.open = true end
  ImGui.SetItemTooltip(ctx, "Report a bug, give feedback or ask for a feature: saved for whoever looks after ReaPersona, and/or as an issue on GitHub.")
end

-- Draw it while open (each frame, from the main window's loop). say(text): the window's message line.
function F.draw(ctx, ImGui, core, version, say)
  if not st.open then return end
  ImGui.SetNextWindowSize(ctx, 520, 440, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, "ReaPersona feedback##fbwin", true, ImGui.WindowFlags_NoCollapse)
  st.open = open
  if not visible then return end
  local k = kind_of(st.kind)
  ImGui.SetNextItemWidth(ctx, 200)
  if ImGui.BeginCombo(ctx, "##fbkind", k[2]) then
    for _, x in ipairs(F.KINDS) do
      if ImGui.Selectable(ctx, x[2], x[1] == st.kind) then st.kind = x[1]; st.log = x[1] == "bug" end
    end
    ImGui.EndCombo(ctx)
  end
  ImGui.SetNextItemWidth(ctx, -1)
  _, st.subject = ImGui.InputTextWithHint(ctx, "##fbsubject", "subject (or leave it: the first line below is used)", st.subject)
  local _, h = ImGui.GetContentRegionAvail(ctx)
  _, st.body = ImGui.InputTextMultiline(ctx, "##fbbody", st.body, -1, math.max(80, h - 4 * ImGui.GetFrameHeightWithSpacing(ctx)))
  if st.body == "" and not ImGui.IsItemActive(ctx) then -- (a hint for the big box: InputTextMultiline has none)
    local x, y = ImGui.GetItemRectMin(ctx)
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx), x + 6, y + 4, 0x888888FF, k[4])
  end
  local _, shared = F.folder(core)
  _, st.folder = ImGui.Checkbox(ctx, shared and "Save in the sync folder" or "Save on this computer", st.folder)
  ImGui.SetItemTooltip(ctx, shared and "Goes to your other computers with your synced setup (its feedback folder), where it's read later." or
    "Not syncing: kept in ReaPersona's own folder on this computer (ReaPersona/feedback). Use GitHub to send it on.")
  ImGui.SameLine(ctx, 0, 16)
  _, st.github = ImGui.Checkbox(ctx, "Open it on GitHub", st.github)
  ImGui.SetItemTooltip(ctx, "Opens a new issue on GitHub in your browser, filled in, for you to send with your GitHub account (it's free).\nAnyone can read issues there.")
  ImGui.SameLine(ctx, 0, 16)
  _, st.log = ImGui.Checkbox(ctx, "Add what it was doing", st.log)
  ImGui.SetItemTooltip(ctx, "Adds ReaPersona's version, REAPER's, the audio system, the persona in use and the last lines of ReaPersona's error log. No files or audio.")
  local title, body = F.compose(st.kind, st.subject, st.body)
  ImGui.BeginDisabled(ctx, not title or not (st.folder or st.github))
  if ImGui.Button(ctx, "Send##fbsend") then
    local extra = ""
    if st.log then
      extra = "## This computer\n\n" .. F.system(core, version) .. "\n\n## ReaPersona's error log (newest last)\n\n" .. table.concat(F.recent_errors(core, 15), "\n")
    end
    local said = {}
    if st.folder then
      local path, why = F.save(core, st.kind, title, body, extra)
      said[#said + 1] = path and ("saved in " .. (shared and "the sync folder's feedback folder" or path)) or ("couldn't save it: " .. tostring(why))
    end
    if st.github then
      core.open_url(F.issue_url(title, body .. (extra ~= "" and ("\n\n" .. extra) or ""), k[3]))
      said[#said + 1] = "opened on GitHub: press Submit new issue there"
    end
    say(k[2] .. ": " .. table.concat(said, "; ") .. ".")
    st.subject, st.body, st.open = "", "", false
  end
  ImGui.EndDisabled(ctx)
  if not title then ImGui.SameLine(ctx); ImGui.TextDisabled(ctx, "Write a subject or what happened.") end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Cancel##fbcancel") then st.open = false end
  ImGui.End(ctx)
end

return F
