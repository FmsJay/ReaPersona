-- ReaPersona's pure checks: the engine (reapersona_core.lua) loaded without REAPER, on a stand-in `reaper` table, from a copy in a
-- folder of its own (tests/_tmp-..., removed at the end), so nothing else in the repo or in a REAPER is written. Asserts only: silence and "ok" means it passed.
-- Run from the repo root with Lua 5.4:   lua tests/test_core.lua
-- or, without Lua (Windows), with lupa:  python -c "import lupa.lua54 as l; l.LuaRuntime().execute(open('tests/test_core.lua').read())"
-- (Added for the left-over items of the 2026-11-16 review, 5.9.3: one check per new piece of logic. 5.10: the Mouse block and syncing.)

local function read(p) local f = io.open(p, "rb"); if not f then return nil end local t = f:read("a"); f:close(); return t end
local function write(p, t) local f = assert(io.open(p, "wb")); f:write(t); f:close() end
local win = package.config:sub(1, 1) == "\\"
local tmp = "tests/_tmp-" .. os.time() .. "-" .. math.random(1000, 9999)
os.execute(win and ('mkdir "' .. tmp:gsub("/", "\\") .. '"') or ("mkdir -p '" .. tmp .. "'"))
write(tmp .. "/reapersona_core.lua", assert(read("ReaPersona/reapersona_core.lua"), "run this from the repo root"))
write(tmp .. "/styles.json", read("ReaPersona/styles.json"))

local ext, listing = {}, {}
reaper = setmetatable({ -- (only what loading the engine and these checks touch)
  GetResourcePath = function() return tmp end,
  GetOS = function() return "Win64" end,
  GetExtState = function(s, k) return ext[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) ext[s .. "/" .. k] = v end,
  DeleteExtState = function(s, k) ext[s .. "/" .. k] = nil end,
  file_exists = function(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end,
  NamedCommandLookup = function() return 0 end,
  GetToggleCommandState = function() return -1 end,
  time_precise = os.clock,
  EnumerateFiles = function(d, i) -- (a folder's files, listed once until asked again with -1, as REAPER does)
    if i < 0 then listing[d] = nil; return end
    if not listing[d] then
      listing[d] = {}
      local p = io.popen(win and ('dir /b /a-d "' .. d:gsub("/", "\\") .. '" 2>nul') or ("ls -p '" .. d .. "' 2>/dev/null | grep -v /"))
      for l in p:lines() do listing[d][#listing[d] + 1] = l end
      p:close()
    end
    return listing[d][i + 1]
  end,
  EnumerateSubdirectories = function(d, i) -- (and its folders)
    local key = "dirs " .. d
    if i < 0 then listing[key] = nil; return end
    if not listing[key] then
      listing[key] = {}
      local p = io.popen(win and ('dir /b /ad "' .. d:gsub("/", "\\") .. '" 2>nul') or ("ls -p '" .. d .. "' 2>/dev/null | grep / | tr -d /"))
      for l in p:lines() do listing[key][#listing[key] + 1] = l end
      p:close()
    end
    return listing[key][i + 1]
  end,
  RecursiveCreateDirectory = function(d)
    os.execute(win and ('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') or ("mkdir -p '" .. d .. "'"))
  end,
}, { __index = function(_, k) return function() end end })
local function load_core() return dofile(tmp .. "/reapersona_core.lua") end
local core = load_core()

-- 1. Removal: ReaPersona's startup block found in any wording, everything else in __startup.lua kept exactly.
local others = "-- Start script: Chordbox\nreaper.Main_OnCommand(1, 0)\n-- >>> reaper-agent-bridge (managed) >>>\nlocal x = 1\n-- <<< reaper-agent-bridge (managed) <<<\n"
local by_hand = "\n-- >>> ReaPersona (was DAW Styles, added 2026-11-11): bring back the last style's keys\ndo\n  dofile(core).restore_last()\nend\n-- <<< ReaPersona <<<\n"
local shipped = "\n-- >>> ReaPersona: REAPER forgets the shortcut layer at restart\ndo\n  if reaper.file_exists(core) then end\nend\n-- <<< ReaPersona <<<\n"
assert(core.strip_startup(others .. by_hand) == others)
assert(core.strip_startup(others .. by_hand .. "print(1)\n" .. shipped) == others .. "print(1)\n")
assert(core.strip_startup(by_hand:sub(2)) == "") -- (on the very first line)
assert(core.strip_startup(others) == others)
local open_only = "-- >>> ReaPersona: left without its close\nmine()\n"
assert(core.strip_startup(open_only .. shipped) == open_only, "an opening line without its close never takes your lines with it")
assert(core.strip_startup("-- <<< ReaPersona <<<\nmine()\n" .. shipped) == "-- <<< ReaPersona <<<\nmine()\n")
assert(not core.find_startup(others))
-- ... and the ExtState keys REAPER keeps for it.
local keys = core.extstate_keys("[other]\nstyle=x\n[ReaPersona]\r\nstyle=pro_tools\r\ntheme pro_tools=a.ReaperThemeZip\r\n[next]\nz=1\n", "ReaPersona")
assert(#keys == 2 and keys[1] == "style" and keys[2] == "theme pro_tools")

-- 2. Your own personas' shortcut layers.
local daw = { kind = "daw", id = "pro_tools", keys = true, feel = true, theme = true }
assert(core.keys_layer({}, nil) == "none")
assert(core.keys_layer({ daw }, nil) == "borrow", "one DAW's keys, all of them: its layer")
local cut = { kind = "daw", id = "pro_tools", keys = true, off = { ["key Ctrl+Z"] = true } }
assert(core.keys_layer({ cut }, nil) == "own", "some left out: a layer of their own")
assert(core.keys_layer({ { kind = "daw", id = "pro_tools", keys = true, off = { theme = true } } }, nil) == "borrow", "an unticked theme isn't a key")
assert(core.keys_layer({ daw, { kind = "daw", id = "logic", keys = true } }, nil) == "own")
core.styles[#core.styles + 1] = { id = "built_mine", name = "Mine", user = true, kind = "built", alt = 14 }
local layer, _, own = core.keys_layer({ daw }, "built_mine")
assert(layer == "own" and own == 14, "a persona with a layer of its own keeps it")
table.remove(core.styles)
local clash = core.layer_clashes({ { id = "a", alt = 11 }, { id = "b", alt = 13, user = true }, { id = "c", alt = 11, user = true },
  { id = "d", alt = 13, user = true }, { id = "e", alt = 2, user = true, keys_from = "logic" } })
assert(#clash == 2 and clash[1].id == "c" and clash[2].id == "d", "on a built-in's layer, or on one an earlier persona of yours has")
-- Loading moves one of yours off a built-in's layer (Audacity is alt-11) and saves it.
write(tmp .. "/user_styles.json", '{"styles": [{"id": "keymap_1", "name": "Old keymap", "kind": "daw", "alt": 11, "keys": [["Ctrl+J", 40001, "x"]]}]}')
core = load_core()
local moved = core.by_id("keymap_1")
assert(moved.alt == 16, "moved to the first free layer (13-15: Nuendo, Pro Tools Intro, GarageBand), got " .. tostring(moved.alt))
assert(read(tmp .. "/user_styles.json"):find('"alt": 16', 1, true), "and saved")
-- "Make them its own": a copy of the DAW's keys on a free layer, no longer tied to the DAW.
write(tmp .. "/user_styles.json", '{"styles": [{"id": "built_2", "name": "Mixing", "kind": "built", "keys_from": "logic"}]}')
core = load_core()
local mixing, logic = core.by_id("built_2"), core.by_id("logic")
assert(mixing.alt == logic.alt and mixing.keys == logic.keys)
assert(core.own_layer(mixing))
assert(mixing.alt == 16 and mixing.keys_from == nil and mixing.keys ~= logic.keys and #mixing.keys == #logic.keys)
assert(logic.alt == 2 and core.by_id("logic").keys == logic.keys, "the DAW keeps its own")
assert(load_core().by_id("built_2").alt == 16, "saved with its own layer")
for i = #core.styles, 1, -1 do if core.styles[i].id == "built_2" then table.remove(core.styles, i) end end -- (alt-16 is the last free layer: 6. needs it)

-- 3. Trimming the Actions list: ids a mouse modifier or an SWS cycle action runs count as used.
local mouse = "[MM_CTX_ITEM]\nmm_0=_RSa1b2c3 m\nmm_4=13 m\n"
local cycle = '[Main_Cyclactions]\nAction1="Switch|!_RSdeadbeef,40001,_RS00ff"\n'
local ids = core.ids_in(mouse .. cycle .. 'KEY 1 65 _RS1234 0\nSCR 4 0 RS9999 "Custom: x" x.lua\n')
assert(ids._RSa1b2c3 and ids._RSdeadbeef and ids._RS00ff and ids._RS1234, "mouse, cycle action and key uses")
assert(not ids._RS9999, "a script's own registration line isn't a use")
assert(next(core.ids_in(nil)) == nil)

-- 4. Unpacking theme packs: Windows and macOS unchanged, Linux picks what's installed.
local function have(list) return function(n) return list[n] and ("/usr/bin/" .. n) or nil end end
assert(core.unpack_command("Win64", "C:/a b/p.zip", "C:/d", have({})):match('System32\\tar%.exe" %-xf "C:/a b/p%.zip" %-C "C:/d"$'))
assert(core.unpack_command("macOS-arm64", "/a/p.rar", "/d", have({})) == "'/usr/bin/tar' -xf '/a/p.rar' -C '/d'")
assert(core.unpack_command("Other", "/a/it's.zip", "/d", have({ unzip = 1, bsdtar = 1 })) == "'/usr/bin/unzip' -o -qq '/a/it'\\''s.zip' -d '/d'")
assert(core.unpack_command("Other", "/a/p.ReaperThemeZip", "/d", have({ bsdtar = 1 })) == "'/usr/bin/bsdtar' -xf '/a/p.ReaperThemeZip' -C '/d'")
assert(core.unpack_command("Other", "/a/p.RAR", "/d", have({ unzip = 1, unrar = 1 })) == "'/usr/bin/unrar' x -o+ -idq '/a/p.RAR' '/d/'")
assert(core.unpack_command("Linux-x86_64", "/a/p.rar", "/d", have({ ["7z"] = 1 })) == "'/usr/bin/7z' x -y -o'/d' '/a/p.rar'")
local none, why = core.unpack_command("Other", "/a/p.zip", "/d", have({}))
assert(none == nil and why:find("needs unzip, bsdtar or 7z", 1, true) and why:find("apt install unzip", 1, true))
assert(select(2, core.unpack_command("Other", "/a/p.rar", "/d", have({ unzip = 1 }))):find("needs unrar", 1, true), "unzip can't open a .rar")

-- 5. The mouse wheel as a shortcut (5.9.5): every modifier mix, both wheels, and REAPER's long form read back.
local f, k = core.encode("Mousewheel"); assert(f == 255 and k == 248, "the wheel")
f, k = core.encode("Ctrl+Alt+Mousewheel"); assert(k == 251, "Ctrl+Alt, as before")
f, k = core.encode("Shift+Mousewheel"); assert(k == 252)
f, k = core.encode("Shift+Ctrl+Mousewheel"); assert(k == 253, "modifiers in any order")
f, k = core.encode("Alt+HorizWheel"); assert(f == 255 and k == 218, "the horizontal wheel, as REAPER writes Alt+HorizWheel")
assert(core.encode("Win+Mousewheel") == nil, "no wheel code with the Windows key")
assert(core.decode(255, 2044) == "Shift+Mousewheel" and core.decode(255, 10237) == "Ctrl+Shift+Mousewheel", "REAPER's long forms")
assert(core.decode(255, 216) == "HorizWheel" and core.decode(255, 255) == "Ctrl+Alt+Shift+Mousewheel")
for _, spec in ipairs({ "Mousewheel", "Ctrl+Mousewheel", "Alt+Shift+Mousewheel", "Ctrl+Alt+Shift+HorizWheel" }) do
  assert(core.decode(core.encode(spec)) == spec, "round trip: " .. spec)
end

-- 6. The mouse in the Persona Builder (5.10): a DAW block's mouse part, and a Mouse block that takes over the whole mouse above it.
local A = { id = "t_a", name = "A", alt = 14, -- (layers a built-in has already: alt-16, the one free layer, stays free for build_style)
  keys = { { "Ctrl+Z", 40029, "Undo" }, { "Mousewheel", 989, "Scroll" }, { "Alt+Mousewheel", 990, "Zoom" } },
  feel = { { "mouse", "MM_CTX_ITEM", 4, "Copy item", "Alt+drag copies" }, { "toggle", 1157, 1, "Snap on" } } }
local B = { id = "t_b", name = "B", alt = 15, keys = { { "Ctrl+Y", 40030, "Redo" }, { "Mousewheel", 988, "Scroll sideways" }, { "Ctrl+Mousewheel", 990, "Zoom" } },
  feel = { { "mouse", "MM_CTX_ITEM", 2, "Copy item", "Ctrl+drag copies" } } }
core.styles[#core.styles + 1] = A
core.styles[#core.styles + 1] = B
assert(core.is_wheel("Ctrl+Mousewheel") and core.is_wheel("win:Alt+HorizWheel") and not core.is_wheel("Ctrl+M") and not core.is_wheel(nil))
local mb = core.new_block("mouse", "t_b")
assert(mb.kind == "mouse" and core.block_title(mb) == "B: Mouse")
assert(core.new_block("daw", "t_a").mouse == true, "a new DAW block has its mouse")
local function built(blocks)
  local st = assert(core.build_style(blocks, "T", "built_t"))
  local keys, mice, toggles = {}, {}, 0
  for _, k in ipairs(st.keys) do keys[k[1]] = k[2] end
  for _, f in ipairs(st.feel) do if f[1] == "mouse" then mice[#mice + 1] = f[3] else toggles = toggles + 1 end end
  return keys, mice, toggles
end
local keys, mice, toggles = built({ core.new_block("daw", "t_a"), mb })
assert(keys["Ctrl+Z"] == 40029 and keys["Mousewheel"] == 988 and keys["Ctrl+Mousewheel"] == 990, "A's keys with B's wheel")
assert(keys["Alt+Mousewheel"] == nil, "nothing of A's wheel is left under B's mouse")
assert(#mice == 1 and mice[1] == 2 and toggles == 1, "B's drags, A's snap")
keys = built({ mb, core.new_block("daw", "t_a") }) -- (a DAW block below the mouse block: the lower one wins, line by line)
assert(keys["Mousewheel"] == 989 and keys["Alt+Mousewheel"] == 990 and keys["Ctrl+Mousewheel"] == 990)
local nomouse = core.new_block("daw", "t_a"); nomouse.mouse = false
keys, mice = built({ nomouse })
assert(keys["Ctrl+Z"] and not keys["Mousewheel"] and #mice == 0, "the mouse part off: no wheel, no drags")
keys, mice = built({ { kind = "daw", id = "t_a", keys = true } }) -- (a block saved before 5.10: the wheel with the keys, drags with the feel)
assert(keys["Mousewheel"] == 989 and #mice == 0)
assert(core.keys_layer({ core.new_block("daw", "t_a") }) == "borrow")
assert(core.keys_layer({ core.new_block("daw", "t_a"), core.new_block("mouse", "t_a") }) == "borrow", "its own mouse again is still its keys")
assert(core.keys_layer({ core.new_block("daw", "t_a"), mb }) == "own", "another DAW's wheel: a layer of their own")
assert(core.keys_layer({ nomouse }) == "own", "the wheel left out")
assert(core.keys_layer({ mb }) == "own", "a mouse alone, on your own keys")
local _, ids = core.keys_layer({ core.new_block("daw", "t_a"), mb })
assert(#ids == 2 and ids[1] == "t_a" and ids[2] == "t_b")
table.remove(core.styles); table.remove(core.styles)
-- Every built-in persona's wheel keys encode, and no wheel combination is bound twice for one system.
for _, st in ipairs(core.styles) do
  local seen = {}
  for _, k in ipairs(st.keys or {}) do
    if core.is_wheel(k[1]) then
      local sys, plain = k[1]:match("^(%a%a%a):(.+)$")
      plain = plain or k[1]
      assert(core.wheel_code(plain), st.id .. ": " .. k[1])
      for _, s in ipairs(sys and { sys } or { "win", "mac" }) do
        local c = s .. " " .. select(2, core.wheel_code(plain))
        assert(not seen[c], st.id .. ": " .. k[1] .. " twice")
        seen[c] = true
      end
    end
  end
end

-- 7. Syncing through a folder: per item the newest change wins; deleting one of yours deletes it elsewhere; bad input is left out.
local state = {}
local out = core.sync_merge(state, { ["setting look"] = "Dark" }, {}, {}, 100, 100)
assert(#out == 0 and state["setting look"].t == 100)
out = core.sync_merge(state, { ["setting look"] = "Dark" }, {}, { { items = { ["setting look"] = { t = 200, v = "Light" } } } }, 300, 300)
assert(#out == 1 and out[1].item == "setting look" and out[1].v == "Light" and state["setting look"].t == 200, "a newer change elsewhere wins")
out = core.sync_merge(state, { ["setting look"] = "Light" }, {}, { { items = { ["setting look"] = { t = 150, v = "Dark" } } } }, 310, 310)
assert(#out == 0 and state["setting look"].t == 200, "an older one doesn't (and taking theirs isn't a change of mine)")
out = core.sync_merge(state, { ["setting look"] = "Pink" }, {}, { { items = { ["setting look"] = { t = 250, v = "Dark" } } } }, 320, 320)
assert(#out == 0 and state["setting look"].v == "Pink" and state["setting look"].t == 320, "changed here since: mine is newer")
out = core.sync_merge(state, { ["setting look"] = "Pink" }, {}, { { items = { ["setting look"] = { t = 320, v = "Dark" } } } }, 330, 330)
assert(#out == 0, "the same time keeps this computer's")
state = {}
out = core.sync_merge(state, { ["setting look"] = "Dark", ["persona p1"] = { id = "p1" } }, {},
  { { items = { ["setting look"] = { t = 5, v = "Light" } } } }, 400, 0)
assert(#out == 1 and out[1].v == "Light", "joining with 'take theirs': theirs wins")
assert(state["persona p1"].t == 0, "and what only this computer has goes to them")
state = { ["persona p1"] = { t = 10, h = "x", v = { id = "p1" } }, ["setting look"] = { t = 10, h = '"Dark"', v = "Dark" } }
core.sync_merge(state, { ["setting look"] = "Dark" }, { persona = true }, {}, 500, 500)
assert(not state["persona p1"].del, "a file that doesn't parse deletes nothing")
core.sync_merge(state, { ["setting look"] = "Dark" }, {}, {}, 500, 500)
assert(state["persona p1"].del and state["persona p1"].t == 500, "deleted here")
state = { ["persona p2"] = { t = 10, h = core.json_encode({ id = "p2" }), v = { id = "p2" } } }
out = core.sync_merge(state, { ["persona p2"] = { id = "p2" } }, {}, { { items = { ["persona p2"] = { t = 600, del = true } } } }, 700, 700)
assert(#out == 1 and out[1].item == "persona p2" and out[1].v == nil, "deleted on another computer since")
out = core.sync_merge({}, {}, {}, { { items = { ["setting look"] = { t = 9, v = { "a table" } }, ["persona x"] = { t = 9, v = "text" },
  ["evil x"] = { t = 9, v = "y" }, ["setting text size"] = { v = "15" }, [1] = { t = 9, v = "z" } } } }, 800, 800)
assert(#out == 0, "wrong types, unknown kinds and items without a time are left out")
out = core.sync_merge({}, {}, {}, { { items = { ["ext SmoothWheelScroll|window"] = { t = 1, v = "144" } } },
  { items = { ["ext SmoothWheelScroll|window"] = { t = 2, v = "200" } } } }, 900, 900)
assert(#out == 1 and out[1].v == "200", "the newest of several computers")
assert(not core.synced_setting("look") and not core.synced_setting("text size") and not core.synced_setting("declined smoothscroll") and core.synced_setting("theme pro_tools") and core.synced_setting("aspect mouse"))
assert(not core.synced_setting("style") and not core.synced_setting("docker top") and not core.synced_setting("sync folder") and not core.synced_setting("orig"))
assert(core.setup_summary({ personas = 2, settings = 1, ext = 3 }) == "2 personas, 1 setting and extension settings")
assert(core.setup_summary({}) == "nothing new")

-- 8. A setup file and a shared folder, end to end, in the test folder.
local function set_ext(s, k, v) ext[s .. "/" .. k] = v end
write(tmp .. "/reaper-extstate.ini", "[ReaPersona]\nstyle=pro_tools\naspect mouse=Dark\ndocker top=14\n[SmoothWheelScroll]\nwindow=200.000000\npos=772 84\n")
set_ext("ReaPersona", "style", "pro_tools"); set_ext("ReaPersona", "aspect mouse", "Dark"); set_ext("ReaPersona", "docker top", "14")
set_ext("SmoothWheelScroll", "window", "200.000000"); set_ext("SmoothWheelScroll", "pos", "772 84")
write(tmp .. "/user_styles.json", '{"styles": [{"id": "built_m", "name": "Mixing", "kind": "built", "keys_from": "logic"}]}')
write(tmp .. "/presets.json", '{"presets": [{"id": "preset_1", "name": "Late night", "base": "logic"}]}')
core = load_core()
local items = core.setup_items()
assert(items["setting aspect mouse"] == "Dark" and items["persona built_m"].name == "Mixing" and items["preset preset_1"].name == "Late night")
assert(items["ext SmoothWheelScroll|window"] == "200.000000")
assert(items["setting style"] == nil and items["setting docker top"] == nil and items["ext SmoothWheelScroll|pos"] == nil, "this computer's own state stays")
assert(core.export_setup(tmp .. "/setup.json"))
set_ext("ReaPersona", "aspect mouse", "Light"); set_ext("SmoothWheelScroll", "window", "100")
write(tmp .. "/user_styles.json", '{"styles": []}')
local r = assert(core.import_setup(tmp .. "/setup.json"))
assert(ext["ReaPersona/aspect mouse"] == "Dark" and ext["SmoothWheelScroll/window"] == "200.000000" and ext["SmoothWheelScroll/pos"] == "772 84")
assert(r.personas == 1 and core.by_id("built_m") and core.by_id("built_m").keys == core.by_id("logic").keys, "the persona is back, on Logic's layer")
write(tmp .. "/user_styles.json", "{broken")
r = assert(core.import_setup(tmp .. "/setup.json"))
assert(read(tmp .. "/user_styles.json") == "{broken" and r.skipped == "persona", "a file of yours that doesn't parse is never written over")
assert(core.import_setup({ items = {} }) == nil, "not a setup file")
write(tmp .. "/user_styles.json", '{"styles": [{"id": "built_m", "name": "Mixing", "kind": "built", "keys_from": "logic"}]}')
core = load_core()
-- The folder: this computer's file written, another computer's newer change taken, one that doesn't parse skipped and left alone.
local share = tmp .. "/share"
os.execute(win and ('mkdir "' .. share:gsub("/", "\\") .. '"') or ("mkdir -p '" .. share .. "'"))
set_ext("ReaPersona", "sync folder", share)
r = assert(core.sync_now())
local mine = core.sync_file_name()
local sent = core.json_decode(assert(read(share .. "/" .. mine), "this computer's file"))
assert(sent.reapersona_sync == 1 and sent.items["setting aspect mouse"].v == "Dark" and sent.items["persona built_m"].v.name == "Mixing")
write(share .. "/LAPTOP-1234.reapersona-sync.json", core.json_encode({ reapersona_sync = 1, computer = "LAPTOP", items = {
  ["ext SmoothWheelScroll|window"] = { t = os.time() + 60, v = "250.000000" }, ["persona built_m"] = { t = os.time() + 60, del = true } } }))
write(share .. "/MAC-9.reapersona-sync.json", "{half a file")
r = assert(core.sync_now())
assert(ext["SmoothWheelScroll/window"] == "250.000000", "the laptop's smooth zoom came in")
assert(not core.by_id("built_m") and not read(tmp .. "/user_styles.json"):find("built_m"), "deleted there, deleted here")
assert(r.changed and #r.others == 2 and read(share .. "/MAC-9.reapersona-sync.json") == "{half a file")
assert(ext["ReaPersona/sync last"]:find("skipped MAC%-9"), "and said")
local before = read(share .. "/" .. mine)
r = assert(core.sync_now())
assert(not r.changed and read(share .. "/" .. mine) == before, "nothing new: nothing written")
assert(core.json_decode(before).items["persona built_m"].del, "the deletion goes on to the other computers")
core.stop_sync()
assert(core.sync_folder() == "" and not read(tmp .. "/sync_state.json"))

-- 9. Workflows (5.11): a project block's lines, starter tracks as a template's text, and a workflow's blocks built into a persona.
local pb = core.new_block("project")
assert(pb.kind == "project" and core.block_title(pb) == "Project" and #core.project_entries(pb) == 0, "an empty project block sets nothing")
pb.srate, pb.wset, pb.tracks, pb.tracks_name = 48000, 3, core.track_chunk('Say "hi"', true, false, 0), "VO"
local pe = core.project_entries(pb)
assert(#pe == 3 and pe[1].value.srate == 48000 and pe[3].value.wset == 3)
assert(core.track_chunk('Say "hi"', true, false, 0) == "<TRACK\n  NAME \"Say 'hi'\"\n  REC 1 0 0 0 0 0 0 0\n  NCHAN 2\n>\n")
local chunk = "<TRACK {A}\n  NAME Gtr\n  <FXCHAIN\n    BYPASS 0\n  >\n  <ITEM\n    POSITION 0\n    <SOURCE WAVE\n      FILE \"x.wav\"\n    >\n  >\n  <ITEM\n    POSITION 4\n  >\n>"
assert(core.strip_items(chunk) == "<TRACK {A}\n  NAME Gtr\n  <FXCHAIN\n    BYPASS 0\n  >\n>\n", "items out, FX kept")
local vo = core.workflow("voiceover")
local st_vo = assert(core.build_style(vo.blocks(), "VO", "built_vo"))
assert(st_vo.project and st_vo.project.srate == 48000 and st_vo.project.tracks:find("Voiceover", 1, true), "the persona carries its project part")
assert(st_vo.alt == 0, "a workflow alone keeps your own keys")
local rip
for _, f in ipairs(st_vo.feel) do if f[1] == "choice" and f[2][1] == 40309 then rip = f[3] end end
assert(rip == 40310, "voiceover: ripple per track")
local lower = core.build_style({ vo.blocks()[1], { kind = "project", srate = 44100, tracks = "", wset = 0 } }, "x", "built_x")
assert(lower.project.srate == 44100 and lower.project.tracks:find("Voiceover", 1, true), "the lower block's sample rate wins, its empty tracks don't")
for _, w in ipairs(core.WORKFLOWS) do assert(core.build_style(w.blocks(), w.name, "built_" .. w.id), w.id) end
-- 9b. A workflow on top of any persona (5.16): toggle actions and the project part only, after the persona's own, each computer's own pick.
local pt = core.by_id("pro_tools")
assert(core.layered(pt) == pt and not core.current_workflow(), "no workflow: the persona itself")
ext["ReaPersona/workflow"] = "voiceover"
local lay = core.layered(pt)
assert(lay ~= pt and lay.workflow and lay.project.srate == 48000 and lay.project_id == "voiceover", "the workflow's project part, its own id for inputs")
assert(lay.alt == pt.alt and lay.keys == pt.keys and lay.theme == pt.theme, "the persona keeps its keys and theme")
assert(#lay.feel == #(pt.feel or {}) + #core.current_workflow().feel and #core.current_workflow().feel > 0, "its settings go after the persona's")
for _, f in ipairs(core.current_workflow().feel) do assert(f[1] == "toggle" or f[1] == "choice", "only toggle actions") end
assert(core.layered(lay) == lay, "not layered twice")
ext["ReaPersona/workflow"] = "mixing"
assert(core.layered(pt).project == pt.project, "a workflow with no project part leaves the persona's")
ext["ReaPersona/workflow"] = "nope"
assert(core.layered(pt) == pt, "an unknown workflow is none")
local myvo = assert(core.build_style({ { kind = "daw", id = "logic", keys = true, feel = true, theme = true }, vo.blocks()[1], vo.blocks()[2] }, "My VO", "built_myvo"))
myvo.user = true
core.styles[#core.styles + 1] = myvo
ext["ReaPersona/workflow"] = "built_myvo"
local wl = core.current_workflow()
assert(wl and wl.project.srate == 48000 and #wl.feel == 3, "one of yours: its project part and its settings blocks, not its DAW's feel")
table.remove(core.styles)
ext["ReaPersona/workflow"] = nil
assert(not core.synced_setting("workflow"), "the workflow in use stays this computer's, as the persona does")
local wnames = {}
for _, x in ipairs(core.workflow_list()) do wnames[x.id] = true end
for _, w in ipairs(core.WORKFLOWS) do assert(wnames[w.id], "every starter can be picked: " .. w.id) end

-- 10. Advanced syncing (5.11): what stays this computer's, file identity, the shared keymap and ini files, and seeding per kind.
assert(core.pref_synced("autosaveint", "5") and core.pref_synced("projsrate", "48000") and core.pref_synced("reccfg", "63616C66"))
for _, k in ipairs({ "adjrecmanlatin", "adjrecmanlatout", "wnd_x", "mixwnd_vis", "lastproject", "projecttab3", "vstpath64", "midiins_cs", "dockermode2", "workthreads", "defrecpath", "csurf_0", "zoom", "toolbar:header" }) do
  assert(not core.pref_synced(k, "1"), k .. " stays this computer's")
end
assert(not core.pref_synced("render_pattern_0", "J:\\Music\\x") and not core.pref_synced("foo", "/Users/chilio/x"), "a path in the value stays too")
-- (5.17: a new user's own setup is kept as a persona unless it's REAPER as it ships)
do
  local base = { { "toggle", 1157, 1, "snap" }, { "radio", { 41603, 41604 }, 41603, "transport" }, { "mouse", "MM_CTX_ITEM", 0, "x" } }
  local same = { { "toggle", 1157, 1 }, { "radio", { 41603, 41604 }, 41603 }, { "toggle", 40036, 0 } }
  local kb = "SCR 4 0 RS1 \"Custom: x\" x.lua\n"
  assert(core.stock_setup(kb, nil, "", "Default_7.0.ReaperThemeZip", same, base), "factory: scripts registered, Default 7, factory toggles")
  assert(core.stock_setup(nil, nil, nil, nil, {}, base), "no files at all is factory")
  assert(not core.stock_setup(kb .. "KEY 1 83 40012 0\n", nil, "", nil, same, base), "a key of your own")
  assert(not core.stock_setup(kb, "[MM_CTX_ITEM]\nmm_0=1 m\n", "", nil, same, base), "a changed mouse behaviour")
  local factory_mouse = "[hasimported]\r\nMM_CTX_ARRANGE_MMOUSE=1\r\nMM_CTX_ITEM=1\r\nMM_CTX_TRACK=1\r\n\r\n[MM_CTX_MIDI_NOTE_CLK]\r\nmm_0=1 m\r\nmm_4=2 m\r\n\r\n" -- (what a new REAPER 7.86 writes itself: Windows Sandbox and a clean Linux, 5.17.2)
  assert(not core.stock_setup(kb, "[MM_CTX_MIDI_NOTE_CLK]\nmm_0=3 m\n", nil, nil, same, base), "a factory context set to something else")
  assert(core.stock_setup(kb, factory_mouse, nil, "Default_7.0.ReaperThemeZip", same, base), "REAPER's own [hasimported] list isn't a change")
  assert(not core.stock_setup(kb, factory_mouse .. "[MM_CTX_ITEM]\nmm_3=58 m\n", nil, nil, same, base), "a change after that list still is")
  assert(not core.stock_setup(kb, "", "[Main toolbar]\nitem_0=40001\n", nil, same, base), "your own toolbar")
  assert(not core.stock_setup(kb, "", "", "Reapertips Theme.ReaperThemeZip", same, base), "another theme")
  assert(not core.stock_setup(kb, "", "", nil, { { "toggle", 1157, 0 } }, base), "snap off")
  assert(not core.stock_setup(kb, "", "", nil, { { "radio", { 41603, 41604 }, 41604 } }, base), "transport moved")
end
-- (5.16.1: per-project settings are read from reaper.ini's defaults, not from the project in front)
assert(core.project_var("projsrate") and core.project_var("autoxfade") and core.project_var("projmetroen") and core.project_var("PROJBPM"))
assert(not core.project_var("autosaveint") and not core.project_var("splitautoxfade") and not core.project_var("projsrateX"))
assert(core.xstate_synced("Some Script", "volume", "0.5") and not core.xstate_synced("BandSync", "user", "James"))
assert(not core.xstate_synced("Some Script", "window_pos", "10 20") and not core.xstate_synced("Some Script", "last", "C:\\x\\y.wav"))
assert(not core.xstate_synced("SmoothWheelScroll", "window", "200"), "the extensions ReaPersona already carries")
assert(core.content_hash("abc") ~= core.content_hash("abd") and core.content_hash("") == core.content_hash(""))
assert(core.content_hash(string.rep("x", 17)) ~= core.content_hash(string.rep("x", 16)), "the length counts")
local kb = "KEY 1 65 40001 0\r\nKEY 1 90 40029 3\t\t # ReaPersona : x\r\nKEY 1 81 _RSmidi 32060\r\nSCR 4 0 RSaa \"Custom: a\" \"ReaPersona/actions/x.lua\"\r\nSCR 4 0 RSbb \"Custom: b\" b.lua\r\nKEY 1 66 40002 2\r\n"
local shared = core.kb_shared(kb, { ["1 66 40002 2"] = true }, { _RSmidi = true })
assert(shared == "KEY 1 65 40001 0\nSCR 4 0 RSbb \"Custom: b\" b.lua\n", "ReaPersona's lines and script registrations stay out; sorted: " .. shared)
assert(core.ini_canon("[b]\nz=1\na=2\n[a]\nk=v\n[b]\nq=3\n") == "[a]\nk=v\n[b]\na=2\nq=3\nz=1\n")
state = {}
core.sync_merge(state, { ["pref autosaveint"] = "5", ["setting look"] = "Dark" }, {}, {}, 100, { pref = 0 })
assert(state["pref autosaveint"].t == 0 and state["setting look"].t == 100, "only the kind just switched on with 'take theirs' starts at 0")
out = core.sync_merge({}, {}, {}, { { items = { ["pref autosaveint"] = { t = 5, v = { "not text" } }, ["tpl FXChains/a.RfxChain"] = { t = 5, v = "not a table" } } } }, 9, 9)
assert(#out == 0, "a pref's value is text, a file's is a table")

-- A template file from another computer arrives through the folder's blobs (and only once its content is there).
core = load_core()
set_ext("ReaPersona", "sync folder", share)
set_ext("ReaPersona", "sync advanced", "templates")
os.execute(win and ('mkdir "' .. (tmp .. "/FXChains/Vox"):gsub("/", "\\") .. '"') or ("mkdir -p '" .. tmp .. "/FXChains/Vox'"))
write(tmp .. "/FXChains/Vox/Lead.RfxChain", "BYPASS 0 0 0\n<VST \"VST: ReaComp\">\n")
r = assert(core.sync_now())
sent = core.json_decode(read(share .. "/" .. core.sync_file_name()))
local item = sent.items["tpl FXChains/Vox/Lead.RfxChain"]
assert(item and item.v.h == core.content_hash("BYPASS 0 0 0\n<VST \"VST: ReaComp\">\n"), "this computer's template went out")
assert(read(share .. "/blobs/" .. item.v.h) == "BYPASS 0 0 0\n<VST \"VST: ReaComp\">\n", "with its content in the blobs")
local other = "BYPASS 0 0 0\n<JS \"loser/3BandEQ\">\n"
local oh = core.content_hash(other)
write(share .. "/LAPTOP-1234.reapersona-sync.json", core.json_encode({ reapersona_sync = 1, computer = "LAPTOP", items = {
  ["tpl FXChains/Drums.RfxChain"] = { t = os.time() + 60, v = { h = oh, n = #other } } } }))
r = assert(core.sync_now())
assert(not read(tmp .. "/FXChains/Drums.RfxChain"), "its content isn't in the folder yet: nothing written, tried again later")
write(share .. "/blobs/" .. oh, other)
r = assert(core.sync_now())
assert(read(tmp .. "/FXChains/Drums.RfxChain") == other, "now it is")
r = assert(core.sync_now())
assert(not r.changed, "and taking it in isn't a change of this computer's that goes back out")
set_ext("ReaPersona", "sync advanced", "")
r = assert(core.sync_now())
write(share .. "/LAPTOP-1234.reapersona-sync.json", core.json_encode({ reapersona_sync = 1, computer = "LAPTOP", items = {
  ["tpl FXChains/Bass.RfxChain"] = { t = os.time() + 90, v = { h = oh, n = #other } } } }))
r = assert(core.sync_now())
assert(not read(tmp .. "/FXChains/Bass.RfxChain"), "a part that's off here isn't taken in")
core.stop_sync()

-- 11. The 5.11 review's findings (H1-H5, M3, M6-M7), each checked.
-- H4: a computer whose clock ran ahead can't make later edits here lose; incoming times are clamped to a day ahead.
state = { ["setting aspect mouse"] = { t = 10 ^ 12, h = '"1"', v = "1" } }
core.sync_merge(state, { ["setting aspect mouse"] = "0" }, {}, {}, 1000, 1000)
assert(state["setting aspect mouse"].t == 10 ^ 12 + 1, "a change here is later than what it replaces")
state = {}
out = core.sync_merge(state, {}, {}, { { items = { ["setting aspect mouse"] = { t = 10 ^ 12, v = "1" } } } }, 1000, 1000)
assert(#out == 1 and state["setting aspect mouse"].t == 1000 + 86400, "a time from the future is believed only a day ahead")
-- M7: equal times settle the same way everywhere (the larger hash), between computers and between peers.
local a_state, b_state = {}, {}
core.sync_merge(a_state, { ["pref x"] = "A" }, {}, {}, 50, 0)
core.sync_merge(b_state, { ["pref x"] = "B" }, {}, {}, 50, 0)
local function file_of(st) local it = {}; for k, v in pairs(st) do it[k] = { t = v.t, v = v.v } end return { items = it } end
local fa, fb = file_of(a_state), file_of(b_state)
core.sync_merge(a_state, { ["pref x"] = "A" }, {}, { fb }, 60, 60)
core.sync_merge(b_state, { ["pref x"] = "B" }, {}, { fa }, 60, 60)
assert(a_state["pref x"].v == b_state["pref x"].v, "both 'take theirs' at time 0: they still agree, on " .. tostring(a_state["pref x"].v))
out = core.sync_merge({}, {}, {}, { { items = { ["pref y"] = { t = 5, v = "1" } } }, { items = { ["pref y"] = { t = 5, v = "2" } } } }, 9, 9)
local out2 = core.sync_merge({}, {}, {}, { { items = { ["pref y"] = { t = 5, v = "2" } } }, { items = { ["pref y"] = { t = 5, v = "1" } } } }, 9, 9)
assert(out[1].v == out2[1].v, "peers tied: the same winner whatever order their files are read in")
-- H2: what comes in passes the same checks as what goes out.
for _, item in ipairs({ "setting sync folder", "setting sync advanced", "xstate ReaPersona|sync folder", "ext SomeSection|x", "pref vstpath64",
    "tpl Scripts/__startup.lua", "tpl FXChains/../Scripts/__startup.lua", "theme UserPlugins/x.dll", "code reaper-kb.ini", "code Scripts/ReaPersona/reapersona_core.lua",
    "code Scripts/x.exe", "ini reaper.ini", "persona ../x", "evil x" }) do
  assert(not core.item_allowed(item, item:match("^%a+ ") and ({ tpl = 1, theme = 1, code = 1, ini = 1 })[item:match("^(%a+)")] and { h = "0123456789abcdef", n = 1 } or "v"), item .. " is refused")
end
for _, item in ipairs({ "setting aspect mouse", "ext SmoothWheelScroll|window", "xstate JLOOPER|Scene2", "pref autosaveint", "persona built_1" }) do
  assert(core.item_allowed(item, "1"), item .. " is taken")
end
assert(core.item_allowed("tpl FXChains/Vox/Lead.RfxChain", { h = "0123456789abcdef", n = 3 }) and core.item_allowed("code Scripts/Mine/x.lua", { h = "0123456789abcdef", n = 3 }))
assert(not core.item_allowed("tpl FXChains/a.RfxChain", { h = "../../reaper.ini", n = 3 }) and not core.item_allowed("ini reaper-kb.ini", { h = "../x" }), "a blob's name is only a hash")
assert(not core.item_allowed("ext SmoothWheelScroll|pos", "1 2"), "an extension's window place stays")
-- H3: the persona that keeps a shared layer doesn't depend on the order they're listed in.
local c1 = core.layer_clashes({ { id = "built_b", alt = 14, user = true }, { id = "built_a", alt = 14, user = true } })
local c2 = core.layer_clashes({ { id = "built_a", alt = 14, user = true }, { id = "built_b", alt = 14, user = true } })
assert(#c1 == 1 and #c2 == 1 and c1[1].id == "built_b" and c2[1].id == "built_b", "the smaller id keeps it on every computer")
-- Menus go out without ReaPersona's own toolbars; a setup file says what's in it.
assert(core.menu_shared("[Main toolbar]\nitem_0=1\n[Floating toolbar 20]\ntitle=ReaPersona Pro Tools\nitem_0=2\n[Floating toolbar 3]\ntitle=Mine\n") ==
  "[Main toolbar]\nitem_0=1\n[Floating toolbar 3]\ntitle=Mine\n")
assert(core.setup_kinds({ items = { ["persona a"] = {}, ["persona b"] = {}, ["pref x"] = "1", ["evil x"] = 1 } }) == "2 personas, 1 REAPER preferences")
-- H5: with no sync folder, the parts made of files are left out of a setup file (never written to the drive's root).
core = load_core()
set_ext("ReaPersona", "sync folder", "")
set_ext("ReaPersona", "sync advanced", "templates")
local it = core.setup_items()
for k in pairs(it) do assert(not k:match("^tpl "), "no templates without a folder for their content") end
set_ext("ReaPersona", "sync advanced", "")
-- H1: a keymap waiting in pending/ for the restart isn't read as this computer's (it would go back out and undo the change).
set_ext("ReaPersona", "sync folder", share)
set_ext("ReaPersona", "sync advanced", "keys")
set_ext("ReaPersona", "style", "my_reaper")
write(tmp .. "/reaper-kb.ini", "KEY 1 65 40001 0\n")
it = core.setup_items()
assert(it["ini reaper-kb.ini"], "the keymap goes out normally")
os.execute(win and ('mkdir "' .. (tmp .. "/pending"):gsub("/", "\\") .. '" 2>nul') or ("mkdir -p '" .. tmp .. "/pending'"))
write(tmp .. "/pending/reaper-kb.ini", "KEY 1 65 40099 0\n")
it = core.setup_items()
assert(not it["ini reaper-kb.ini"], "not while the other computer's waits for the restart")
set_ext("ReaPersona", "style", "pro_tools")
os.remove(tmp .. "/pending/reaper-kb.ini")
it = core.setup_items()
assert(not it["ini reaper-kb.ini"], "and not while a persona is in use (it changes them live)")
set_ext("ReaPersona", "sync advanced", "")
set_ext("ReaPersona", "sync folder", "")

-- Preferences never go into REAPER's memory (5.11.2: a type guessed from SWS's getters corrupted int variables and crashed REAPER):
-- they wait in pending/prefs.json for the restart.
core.ADVANCED_APPLY.pref("autosaveint", "7")
assert(core.json_decode(read(tmp .. "/pending/prefs.json")).autosaveint == "7", "a preference waits for the restart")
os.remove(tmp .. "/pending/prefs.json")
-- 5.12.1: a persona saved with "make it a workflow too" carries the project's rate and tracks, and uses them like a Project block.
local wfp = core.preset_style({ id = "preset_vo", name = "VO", base = "pro_tools", feel = {}, project = { srate = 48000, tracks = "<TRACK\n  NAME VO\n>\n", tracks_name = "1 track from x" } })
assert(wfp.project and wfp.project.srate == 48000 and wfp.project.tracks:find("NAME VO", 1, true) and wfp.description:find("48 kHz", 1, true))
assert(core.preset_style({ id = "preset_plain", name = "P", base = "pro_tools", feel = {} }).project == nil, "a plain one has no project part")
-- 5.13: a whole project as a template: no items, media bay, scripts' data or this project's folders; nested blocks handled.
local rpp = '<REAPER_PROJECT 0.1 "7.86/win64" 1\n  RECORD_PATH "C:/rec" ""\n  RENDER_FILE "C:/out"\n  RENDER_PATTERN $project\n  TEMPO 90 4 4\n' ..
  '  MARKER 1 0 "Verse" 0\n  <PROJBAY\n    <ITEM\n    >\n  >\n  <EXTSTATE\n    <StudioSync\n      id 1\n    >\n  >\n  <TRACK\n    NAME Vox\n    <FXCHAIN\n' ..
  '      <VST "VST3: Pro-Q 3 (FabFilter)" Pro-Q.vst3 0 "" 1\n        AAAA\n      >\n      <JS "utility/volume" ""\n      >\n    >\n    <ITEM\n      POSITION 0\n      <SOURCE WAVE\n        FILE "a.wav"\n      >\n    >\n  >\n>\n'
local tpl = core.template_from_rpp(rpp)
assert(not tpl:find("ITEM", 1, true) and not tpl:find("a.wav", 1, true) and not tpl:find("StudioSync", 1, true) and not tpl:find("PROJBAY", 1, true), tpl)
assert(not tpl:find("RECORD_PATH", 1, true) and not tpl:find("C:/out", 1, true), "no folders of this project")
assert(tpl:find("TEMPO 90", 1, true) and tpl:find("MARKER 1", 1, true) and tpl:find("RENDER_PATTERN", 1, true) and tpl:find("NAME Vox", 1, true), "the rest stays")
local _, opens = tpl:gsub("\n%s*<", ""); local _, closes = tpl:gsub("\n%s*>", "")
assert(opens + 1 == closes, "blocks balanced (the project's own opens on the first line)")
local need = core.fx_needed(tpl)
assert(#need == 2 and need[1] == "Pro-Q 3 (FabFilter)" and need[2] == "JS: utility/volume", table.concat(need, ";"))
-- the project template goes into a preset and its description, and into a Builder block's entries
local wft = core.preset_style({ id = "preset_t", name = "T", base = "pro_tools", feel = {}, project = { srate = 48000, tracks = "", template = tpl, template_name = "Song (1 track...)" } })
assert(wft.project.template == tpl and wft.description:find("Song (1 track", 1, true))
local ents = core.project_entries({ kind = "project", template = tpl, template_name = "Song" })
assert(#ents == 1 and ents[1].slot == "project template" and ents[1].value.template == tpl)
-- settings appended at the end of each group (blocks saved before keep their values in place), the new group, the new workflows
assert(core.setting_group("editing").items[1][1] == 1157 and core.setting_group("monitoring").items[1][1] == 41583)
for _, id in ipairs({ "mixing", "mastering", "video" }) do
  local blocks = core.workflow(id).blocks()
  for _, b in ipairs(blocks) do if b.kind == "settings" then assert(core.setting_group(b.group), b.group) end end
  local st = core.build_style(blocks, id)
  assert(st and #st.feel > 0, id)
end
assert(core.synced_setting("inputs preset_x") == false, "each computer's inputs stay on it")
-- 12. The install without Python (5.14): install_shortcuts.py's rules in Lua, and the batch step run for real (Windows).
-- (the same checks as install_shortcuts.py's own asserts)
assert(core.merge_kb("KEY 1 65 40001 0\nSCR 4 0 RSaa \"Custom: a\" a.lua\nKEY 1 66 40002 0\n", "KEY 1 65 40099 0\nACT 0 0 \"x\" \"y\" 1\n") ==
  "SCR 4 0 RSaa \"Custom: a\" a.lua\nKEY 1 66 40002 0\nKEY 1 65 40099 0\nACT 0 0 \"x\" \"y\" 1\n")
local kmine = "SCR 4 0 RSaa \"Custom: a\" a.lua\nKEY 9 90 _RSmine 0\n"
assert(core.merge_kb(kmine, "KEY 9 90 _RSzz 0\nKEY 9 90 0 0\nKEY 1 70 40001 3\nKEY 1 71 _RSaa 0\n") == kmine .. "KEY 1 71 _RSaa 0\n", "another computer's script ids, off keys and persona layers stay out")
assert(core.merge_ini("[a]\nx=1\n[b]\ny=2\n", "[b]\ny=3\n[c]\nz=4\n") == "[a]\nx=1\n[b]\ny=3\n[c]\nz=4\n")
local pst = { { name = "A", alt = 3, keys = { { "Ctrl+Shift+L", 40001, "x" }, { "Ctrl+Z", "MAIN:Ctrl+Z", "Undo" }, { "Q", "script:next", "n" }, { "Bogus+Q", 1, "bad" } },
  midi_keys = { { "Ctrl+M", "x" } } } }
local pscripts = { main = { next = "_RSnext" }, midi = { ["Ctrl+M"] = "_RSmidiM" } }
local pkb = "KEY 9 90 _RSundo 0\r\nKEY 13 76 40099 3\r\nKEY 9 77 40500 32060\r\nKEY 1 65 40001 5\t\t # ReaPersona : old\r\n"
local nkb, nwritten, nfb, nadded, nwarn = core.kb_plan(pkb, pst, pscripts, nil, {}, {}, false, false, true)
assert(nkb:find("KEY 13 76 40099 3", 1, true) and not nkb:find("40001 3", 1, true), "a key you rebound in the layer stays yours")
assert(nkb:find("KEY 9 90 _RSundo 3", 1, true), "MAIN: takes what the Main section runs on that key (StudioSync's Undo)")
assert(nkb:find("KEY 1 81 _RSnext 3", 1, true) and nkb:find("KEY 9 77 _RSmidiM 32060", 1, true))
assert(nfb["Ctrl+M"].cmd == "40500" and not nkb:find("40500", 1, true), "your MIDI editor line moves into midi_fallback.json")
assert(not nkb:find("40001 5", 1, true) and nadded == 3 and #nwritten == 2 and #nwarn == 1 and nwarn[1]:find("Bogus", 1, true))
assert(not nkb:gsub("\r\n", ""):find("\n"), "CRLF kept")
assert(select(5, core.kb_plan(pkb, pst, pscripts, nil, {}, nil))[2]:find("midi_defaults", 1, true), "no MIDI keys without REAPER's MIDI defaults")
-- OSARA's keys stay OSARA's (review 5.14): its Main-section Ctrl+Shift+L and MIDI-editor Ctrl+M keep their actions, with a warning
local okb, _, _, oadded, owarn = core.kb_plan("KEY 13 76 _OSARA_REPORT 0\nKEY 9 77 _OSARA_MIDI 32060\n", pst, pscripts, nil, {}, {}, false, false, false)
assert(not okb:find("40001 3", 1, true) and not okb:find("_RSmidiM", 1, true) and okb:find("_OSARA_MIDI 32060", 1, true) and oadded == 2, okb)
assert(owarn[#owarn]:find("kept OSARA's keys: 2", 1, true), table.concat(owarn, ";"))
local taken = core.mac_taken({ { "Ctrl+Space", 1, "x" }, { "win:Ctrl+H", 1, "x" }, { "mac:Ctrl+M", 1, "x" }, { "Alt+Ctrl+D", 1, "x" }, { "Ctrl+J", 1, "x" } })
assert(#taken == 3 and taken[1]:find("Cmd+M", 1, true) and taken[3]:find("Spotlight", 1, true), table.concat(taken, ";"))
local rkb = core.kb_plan(nkb, pst, pscripts, nwritten, nfb, {}, true)
assert(rkb == "KEY 9 90 _RSundo 0\r\nKEY 13 76 40099 3\r\nKEY 9 77 40500 32060\r\n", "remove: only ReaPersona's lines go, your MIDI line comes back: " .. rkb)
local warns = {}
local nmenu, ntb = core.menu_plan("[Floating toolbar 5]\nitem_0=1 x\ntitle=ReaPersona: Old\n[Floating toolbar 6]\nitem_0=9 mine\n[Main toolbar]\nitem_0=40001 Play\n",
  { { name = "A", toolbar_slot = 5, toolbar = { { 40001, "Play" }, -1, { 40002, "Stop", "icon.png" } } }, { name = "B", toolbar_slot = 6, toolbar = { { 1, "a" } } },
    { name = "C", toolbar_slot = 7, toolbar_file = "missing.ReaperMenu" } }, false, function() return nil end, warns)
assert(ntb == 1 and #warns == 2 and nmenu == "[Floating toolbar 6]\nitem_0=9 mine\n[Main toolbar]\nitem_0=40001 Play\n\n[Floating toolbar 5]\nitem_0=40001 Play\nitem_1=-1\nicon_2=icon.png\nitem_2=40002 Stop\ntitle=ReaPersona: A\n", nmenu)
assert(core.menu_plan(nmenu, {}, true, nil, {}) == "[Floating toolbar 6]\nitem_0=9 mine\n[Main toolbar]\nitem_0=40001 Play\n", "remove takes only ReaPersona's toolbars")
local tl = '0\n"reaper.exe","100","Console","1","9 K","Running","x","0:00:01","REAPER v7 - a.rpp"\n"reaper.exe","200","Console","1","9 K","Running","x","0:00:01","REAPER v7 - b.rpp"\n'
assert(core.pid_from_tasklist(tl, "REAPER v7 - b.rpp") == "200" and core.pid_from_tasklist(tl, "nope") == nil and core.pid_from_tasklist(tl:match("^0\n[^\n]+\n"), nil) == "100")
if win then -- (the staged install, swapped in by its batch file: a process id that isn't running = REAPER has closed)
  write(tmp .. "/styles.json", '{"styles": [{"id": "a", "name": "A", "alt": 3, "keys": [["Ctrl+Shift+L", 40001, "x"]], "toolbar_slot": 5, "toolbar": [[40001, "Play"]]}]}')
  write(tmp .. "/reaper-kb.ini", "KEY 1 65 40001 0\r\n")
  write(tmp .. "/reaper-kb.ini.before-reapersona-20200101-000000", "first\r\n")
  for i = 1, 5 do write(tmp .. "/reaper-kb.ini.before-reapersona-2025010" .. i .. "-000000", "x") end
  local bat = assert(core.stage_install({ pid = "999999", stamp = "20260101-000000" }))
  assert(read(bat):find("chcp 65001", 1, true) and not read(tmp .. "/reaper-kb.ini"):find("40001 3", 1, true), "nothing of REAPER's is touched before it closes")
  os.execute('cmd /c ""' .. bat:gsub("/", "\\") .. '""')
  local after = read(tmp .. "/reaper-kb.ini")
  assert(after:find("KEY 13 76 40001 3", 1, true) and after:find("KEY 1 65 40001 0", 1, true), after)
  assert(read(tmp .. "/reaper-kb.ini.before-reapersona-20260101-000000") == "KEY 1 65 40001 0\r\n", "backed up first")
  assert(read(tmp .. "/reaper-kb.ini.before-reapersona-20200101-000000") and not read(tmp .. "/reaper-kb.ini.before-reapersona-20250102-000000")
    and read(tmp .. "/reaper-kb.ini.before-reapersona-20250103-000000"), "the first backup and the newest 4 kept")
  assert(read(tmp .. "/reaper-menu.ini"):find("title=ReaPersona: A", 1, true) and read(tmp .. "/installed.json"):find("13 76 40001 3", 1, true))
  assert(read(tmp .. "/last_install.txt"):find("installed 1 shortcut", 1, true) and not reaper.file_exists(tmp .. "/install_staged/install.cmd"))
  -- a keymap changed after it was read: nothing swapped in, and you're told
  bat = assert(core.stage_install({ pid = "999999", stamp = "20260101-000001", remove = true }))
  write(tmp .. "/reaper-kb.ini", after .. "KEY 1 66 40002 0\r\n")
  os.execute('cmd /c ""' .. bat:gsub("/", "\\") .. '""')
  assert(read(tmp .. "/reaper-kb.ini") == after .. "KEY 1 66 40002 0\r\n" and read(tmp .. "/last_install.txt"):find("changed", 1, true))
end
-- The theme libraries' background install (5.16): running, then how it ended, told once; one that never ended counts as failed
write(tmp .. "/venv_status.txt", "running " .. os.time() .. "\n"); core._libs_seen = nil
assert(core.libs_job() == "running" and read(tmp .. "/venv_status.txt"), "running: the file stays")
write(tmp .. "/venv_status.txt", "failed\npip didn't finish: no network\n"); core._libs_seen = nil
local lj, lwhy = core.libs_job()
assert(lj == "failed" and lwhy == "pip didn't finish: no network" and not read(tmp .. "/venv_status.txt") and core.libs_job() == nil, "told once")
write(tmp .. "/venv_status.txt", "running " .. (os.time() - 3000) .. "\n"); core._libs_seen = nil
assert(core.libs_job() == "failed", "a run that never ended")
write(tmp .. "/venv_status.txt", "ok\n"); core._libs_seen = nil
assert(core.libs_job() == "ok" and core._libs == nil, "ok: Pillow and numpy are checked again")
assert(core.theme_python() == core.py and not core.venv_python(), "no venv: the Python found")
reaper.RecursiveCreateDirectory(tmp .. "/venv/Scripts"); write(tmp .. "/venv/Scripts/python.exe", "")
assert(core.theme_python() == '"' .. tmp .. '/venv/Scripts/python.exe"', "the venv's, quoted (paths with spaces)")
assert(core.pid_from_ps("0\n4242\n/Applications/REAPER.app/Contents/MacOS/REAPER\n") == "4242" and core.pid_from_ps("0\n77\nreaper\n") == "77")
assert(core.pid_from_ps("0\n4242\n/bin/zsh\n") == nil and core.pid_from_ps("-999\n") == nil, "a parent that isn't REAPER: no id")
-- The same install as a Mac's or Linux's /bin/sh step (5.16), run for real where a sh is found (Git's on Windows)
local sh_exe = not win and "/bin/sh" or nil
for _, p in ipairs(win and { "C:/Program Files/Git/usr/bin/sh.exe", "C:/Program Files/Git/bin/sh.exe" } or {}) do if not sh_exe and read(p) then sh_exe = p end end
if sh_exe then
  local was_os = reaper.GetOS
  reaper.GetOS = function() return "linux-x86_64" end
  for _, f in ipairs({ "reaper-kb.ini", "reaper-menu.ini", "reaper-mouse.ini", "installed.json", "midi_fallback.json", "last_install.txt",
    "pending/reaper-kb.ini", "pending/reaper-menu.ini", "pending/reaper-mouse.ini", "pending/reaper-screensets.ini", "pending/prefs.json" }) do os.remove(tmp .. "/" .. f) end
  reaper.RecursiveCreateDirectory(tmp .. "/pending")
  write(tmp .. "/styles.json", '{"styles": [{"id": "a", "name": "A", "alt": 3, "keys": [["Ctrl+Shift+L", 40001, "x"]], "toolbar_slot": 5, "toolbar": [[40001, "Play"]]}]}')
  write(tmp .. "/installed.json", '{"lines": []}'); write(tmp .. "/midi_fallback.json", "{}")
  write(tmp .. "/reaper-kb.ini", "KEY 1 65 40001 0\n")
  for f in ("20200101-000000 20250101-000000 20250102-000000 20250103-000000 20250104-000000 20250105-000000 20260101-000000 20260101-000001"):gmatch("%S+") do
    os.remove(tmp .. "/reaper-kb.ini.before-reapersona-" .. f)
  end
  write(tmp .. "/reaper-kb.ini.before-reapersona-20200101-000000", "first\n")
  for i = 1, 5 do write(tmp .. "/reaper-kb.ini.before-reapersona-2025010" .. i .. "-000000", "x") end
  write(tmp .. "/reaper-kb.ini.before-reapersona-sync-20990101-000000", "sync") -- (sync backups aren't rotated)
  write(tmp .. "/pending/reaper-mouse.ini", "[m]\nx=1\n") -- (a sync waiting: merged in, and its pending file goes once it's swapped in)
  local function run(step)
    local c = '"' .. sh_exe .. '" "' .. step .. '" --detached'
    return os.execute(win and ('"' .. c .. '"') or c)
  end
  local step = assert(core.stage_install({ pid = "999999", stamp = "20260101-000000" }))
  local text = read(step)
  assert(step:match("install%.sh$") and text:find("^#!/bin/sh\n") and not text:find("\r", 1, true), "a /bin/sh script with LF lines")
  assert(text:find("kill -0 999999", 1, true) and not text:find("open -a", 1, true), "waits on REAPER's id; no relaunch without an exe")
  local order = { text:find("midi_fallback.json' '", 1, true), text:find("reaper-kb.ini.tmp' '", 1, true), text:find("installed.json' '", 1, true) }
  assert(order[1] and order[2] and order[3] and order[1] < order[2] and order[2] < order[3], "the fallback first, then the keymap, then installed.json")
  assert(not read(tmp .. "/reaper-kb.ini"):find("40001 3", 1, true), "nothing of REAPER's is touched before it closes")
  run(step)
  local after = read(tmp .. "/reaper-kb.ini")
  assert(after:find("KEY 13 76 40001 3", 1, true) and after:find("KEY 1 65 40001 0", 1, true), after)
  assert(read(tmp .. "/reaper-kb.ini.before-reapersona-20260101-000000") == "KEY 1 65 40001 0\n", "backed up first")
  assert(read(tmp .. "/reaper-kb.ini.before-reapersona-20200101-000000") and not read(tmp .. "/reaper-kb.ini.before-reapersona-20250102-000000")
    and read(tmp .. "/reaper-kb.ini.before-reapersona-20250103-000000") and read(tmp .. "/reaper-kb.ini.before-reapersona-sync-20990101-000000"),
    "the first backup and the newest 4 kept, the sync backup left alone")
  assert(read(tmp .. "/reaper-mouse.ini") == "[m]\nx=1\n" and not read(tmp .. "/pending/reaper-mouse.ini"), "the sync went in and its pending file went")
  assert(read(tmp .. "/reaper-menu.ini"):find("title=ReaPersona: A", 1, true) and read(tmp .. "/installed.json"):find("13 76 40001 3", 1, true))
  assert(read(tmp .. "/last_install.txt"):find("installed 1 shortcut", 1, true) and not read(tmp .. "/install_staged/install.sh"), "told, and the folder gone")
  -- a keymap changed after it was read: nothing swapped in (not even the fallback), and you're told
  local fb_before = read(tmp .. "/midi_fallback.json")
  step = assert(core.stage_install({ pid = "999999", stamp = "20260101-000001", remove = true }))
  write(tmp .. "/reaper-kb.ini", after .. "KEY 1 66 40002 0\n")
  run(step)
  assert(read(tmp .. "/reaper-kb.ini") == after .. "KEY 1 66 40002 0\n" and read(tmp .. "/last_install.txt"):find("changed", 1, true))
  assert(read(tmp .. "/midi_fallback.json") == fb_before and not read(tmp .. "/reaper-kb.ini.before-reapersona-20260101-000001"), "nothing swapped, no backup")
  -- a pending file that changed after it was merged stays for the next install
  write(tmp .. "/pending/reaper-mouse.ini", "[m]\nx=2\n")
  step = assert(core.stage_install({ pid = "999999", stamp = "20260101-000002" }))
  write(tmp .. "/pending/reaper-mouse.ini", "[m]\nx=3\n")
  run(step)
  assert(read(tmp .. "/pending/reaper-mouse.ini") == "[m]\nx=3\n" and read(tmp .. "/reaper-mouse.ini") == "[m]\nx=2\n", "a newer sync waits")
  os.remove(tmp .. "/pending/reaper-mouse.ini")
  -- the quit cancelled: nothing at all
  local kb_now = read(tmp .. "/reaper-kb.ini")
  step = assert(core.stage_install({ pid = "999999", stamp = "20260101-000003", remove = true }))
  write(tmp .. "/install_cancelled", "x")
  run(step)
  assert(read(tmp .. "/reaper-kb.ini") == kb_now and not read(tmp .. "/install_cancelled") and not read(tmp .. "/install_staged/install.sh"), "cancelled")
  -- the relaunch lines: a Mac opens the app through LaunchServices once it's gone from there; Linux starts the binary
  write(tmp .. "/reaper.ini", "x")
  reaper.GetOS = function() return "macOS-arm64" end
  text = read(assert(core.stage_install({ exe = "/Applications/REAPER.app", cfg = tmp .. "/reaper.ini", projects = { "/p/it's.rpp" } })))
  assert(text:find("open -a '/Applications/REAPER.app' '/p/it'\\''s.rpp' --args '-cfgfile' '" .. tmp .. "/reaper.ini'", 1, true) and text:find("lsappinfo", 1, true), text)
  assert(text:find("running() { any_reaper; }", 1, true), "no id: any REAPER counts")
  reaper.GetOS = function() return "linux-x86_64" end
  text = read(assert(core.stage_install({ exe = "/opt/REAPER/reaper", projects = {} })))
  assert(text:find("detach '/opt/REAPER/reaper' </dev/null", 1, true) and not text:find("open -a", 1, true))
  reaper.GetOS = was_os
end
-- 13. Colours (5.19): StudioSync's colour system, on one computer.
do
  local colours = assert(loadfile("ReaPersona/colours.lua"))(core)
  assert(colours.mix(0x000000, 0xFFFFFF, 0.5) == 0x808080 and colours.ramp({ 0x000000, 0xFFFFFF }, 1) == 0xFFFFFF)
  local tracks = { { name = "Kick", family = 1 }, { name = "Bass", family = 2 }, { name = "Lead Vox", family = 3 } }
  local p = colours.plan(tracks, "instrument", { stops = colours.PALETTES[1][2] })
  assert(p[1] == 0xE5584F and p[2] == 0xF2A33A and p[3] == 0xF06BAF, "drums, bass, vocals from the names")
  local g = colours.plan(tracks, "gradient", { stops = { 0x000000, 0xFFFFFF } })
  assert(g[1] == 0x000000 and g[2] == 0x808080 and g[3] == 0xFFFFFF, "top to bottom along the palette")
  for _, s in ipairs(colours.SCHEMES) do assert(s[1] ~= "person" and s[1] ~= "newest", "StudioSync's own schemes stay there") end
  for _, s in ipairs(colours.ITEM_SCHEMES) do assert(s[1] ~= "person" and s[1] ~= "newest") end
  local m = colours.plan_marks({ { name = "Verse 1", region = true, pos = 0 }, { name = "Chorus", region = true, pos = 10 } }, "sections", { 0, 1 })
  assert(m[1] == 0x4C9BE8 and m[2] == 0xF2A33A, "the common sections keep their colours")
  local items = colours.plan_items({ { kind = "midi" }, { kind = "audio" } }, "kind", { stops = { 0x111111, 0x222222 } })
  assert(items[1] == 0x111111 and items[2] == 0x222222)
  local look, from = colours.look_of(0)
  assert(look.scheme == "gradient" and from == "computer", "nothing picked yet: a gradient")
  ext["ReaPersona/colour look"] = core.json_encode({ scheme = "rainbow", palette = "Ocean" })
  assert(colours.look_of(0).scheme == "rainbow", "this computer's last pick")
  ext["ReaPersona/colour look"] = nil
end
-- 14. Colours with personas and workflows (5.20): saved, checked, built, layered, and put back after a switch.
do
  local look = core.json_encode({ scheme = "gradient", palette = "Ocean" }):gsub("\n%s*", "") -- (one line, as ExtState keeps it)
  assert(core.safe_colours({ ["colour look"] = core.json_encode({ scheme = "gradient", palette = "Ocean" }) })["colour look"] == look, "a multi-line one is made one line")
  local safe = core.safe_colours({ ["colour look"] = look, ["colour kinds"] = "{}", ["evil"] = "{}", ["colour folders"] = "not json", ["colour sections"] = { "a table" } })
  assert(safe["colour look"] == look and safe["colour kinds"] == "{}" and not safe.evil and not safe["colour folders"] and not safe["colour sections"], "only known keys, each JSON text")
  assert(core.safe_colours({ evil = "{}" }) == nil and core.safe_colours("x") == nil)
  assert(core.colours_label({ ["colour look"] = look }) == "Colours: Gradient in Ocean")
  assert(core.colours_now() == nil, "no look picked: nothing to save")
  ext["ReaPersona/colour look"] = look
  ext["ReaPersona/colour kinds"] = core.json_encode({ Drums = "FF0000" })
  local now = core.colours_now()
  assert(now["colour look"] == look and now["colour kinds"]:find("FF0000", 1, true) and now["colour folders"] == nil)
  local cb = core.new_block("colours")
  assert(cb.kind == "colours" and core.block_title(cb) == "Colours: Gradient in Ocean")
  local built = assert(core.build_style({ core.new_block("daw", "logic"), cb }, "Coloured", "built_col"))
  assert(built.colours and built.colours["colour look"] == look, "the Builder's Colours block goes into the persona")
  local ps = core.preset_style({ id = "preset_col", name = "C", base = "pro_tools", feel = {}, colours = { ["colour look"] = look, evil = "{}" } })
  assert(ps.colours["colour look"] == look and not ps.colours.evil and ps.description:find("Gradient in Ocean", 1, true), "a preset carries its colours, checked")
  -- a persona of yours with colours (no project part) is a workflow too, and brings its colours over the persona in use
  built.user = true
  core.styles[#core.styles + 1] = built
  local listed = false
  for _, x in ipairs(core.workflow_list()) do if x.id == "built_col" then listed = true end end
  assert(listed, "a persona of yours with colours is a workflow")
  ext["ReaPersona/workflow"] = "built_col"
  local lay = core.layered(core.by_id("pro_tools"))
  assert(lay.colours and lay.colours["colour look"] == look, "its colours over Pro Tools")
  ext["ReaPersona/workflow"] = nil
  -- switching to it makes its colours yours; switching back puts yours back exactly
  local mine = core.json_encode({ scheme = "rainbow" })
  ext["ReaPersona/colour look"] = mine
  ext["ReaPersona/colour kinds"] = nil
  ext["ReaPersona/style"] = "my_reaper"
  core.use(built)
  assert(ext["ReaPersona/colour look"] == look and ext["ReaPersona/colour kinds"]:find("FF0000", 1, true), "its colours are in use")
  core.use(core.by_id("my_reaper"))
  assert(ext["ReaPersona/colour look"] == mine and ext["ReaPersona/colour kinds"] == nil, "and yours are back, the one you hadn't set gone again")
  table.remove(core.styles)
  ext["ReaPersona/colour look"] = nil
end
-- 15. Your look on every computer (5.21): saved on My REAPER only, one line, applied by My REAPER as your own setup (nothing kept to put
-- back, so a persona's switch comes back to it), checked when it comes from elsewhere, and taken in from a setup file while you're on it.
do
  local TRANSPORT = { 41603, 41604, 41605, 41606, 41608 }
  local states = { [41606] = 1, [40083] = 1, [40078] = 1, [1157] = 0 }
  local gt, mo, lt = reaper.GetToggleCommandState, reaper.Main_OnCommand, reaper.GetLastColorThemeFile
  reaper.GetToggleCommandState = function(id) return states[id] or 0 end
  reaper.Main_OnCommand = function(id)
    for _, c in ipairs(TRANSPORT) do if c == id then for _, o in ipairs(TRANSPORT) do states[o] = 0 end; states[id] = 1; return end end
    states[id] = (states[id] == 1) and 0 or 1
  end
  os.execute(win and ('mkdir "' .. (tmp .. "/ColorThemes"):gsub("/", "\\") .. '" 2>nul') or ("mkdir -p '" .. tmp .. "/ColorThemes'"))
  write(tmp .. "/ColorThemes/Reapertips Theme.ReaperThemeZip", "zip")
  reaper.GetLastColorThemeFile = function() return tmp .. "/ColorThemes/Reapertips Theme.ReaperTheme" end
  ext["ReaPersona/style"] = "base_reaper"
  local none, why = core.save_my_look()
  assert(not none and why:find("My REAPER", 1, true), "a persona's settings aren't your look")
  ext["ReaPersona/style"] = "my_reaper"
  local look = assert(core.save_my_look())
  assert(not ext["ReaPersona/my look"]:find("\n", 1, true), "one line, so REAPER keeps all of it across a restart")
  local back = core.my_look()
  assert(back.theme == "Reapertips Theme.ReaperThemeZip" and #back.feel == #look.feel and core.look_label(back):find("Reapertips Theme", 1, true))
  local top = false
  for _, f in ipairs(back.feel) do if f[1] == "radio" and f[3] == 41606 then top = true end end
  assert(top, "the transport's place is in it")
  -- another computer: transport under the arrange view, its own theme. My REAPER gives it your look, as its own setup
  states = { [41603] = 1, [40083] = 0, [40078] = 0, [1157] = 1 }
  ext["ReaPersona/theme my_reaper"] = "Default_7.0.ReaperThemeZip"
  ext["ReaPersona/orig"] = ""
  core.use(core.by_id("my_reaper"))
  assert(states[41606] == 1 and states[41603] == 0 and states[40083] == 1 and states[40078] == 1 and states[1157] == 0, "your transport, mixer and snap")
  assert(ext["ReaPersona/theme my_reaper"] == "Reapertips Theme.ReaperThemeZip" and ext["ReaPersona/orig"] == "", "your theme, and nothing kept to put back")
  core.use(core.by_id("base_reaper")) -- (Base REAPER puts the transport under the arrange view...)
  assert(states[41603] == 1)
  core.use(core.by_id("my_reaper")) -- (...and leaving it comes back to your look)
  assert(states[41606] == 1 and states[41603] == 0, "back to your look")
  -- from a file or another computer: only what a persona could set, a theme by its file name
  ext["ReaPersona/my look"] = core.json_encode({ theme = "../../evil.ReaperThemeZip", feel = { { "toggle", 99999, 1, "x" }, { "toggle", 1157, 1, "snap" } } }):gsub("\n%s*", "")
  local bad = core.my_look()
  assert(bad.theme == "evil.ReaperThemeZip" and #bad.feel == 1 and bad.feel[1][2] == 1157, "an unknown command is dropped")
  -- a setup file brings it in while you're on My REAPER: used straight away
  states[1157] = 0
  local rep = assert(core.import_setup({ reapersona_setup = 1, items = { ["setting my look"] = { t = 1, v = ext["ReaPersona/my look"] } } }))
  assert(rep.look and states[1157] == 1, "a look that comes in is used at once on My REAPER")
  assert(core.setup_items()["setting my look"], "a saved look syncs")
  core.forget_my_look()
  assert(core.my_look() == nil and core.setup_items()["setting my look"] == "{}", "forgetting it is a change your other computers take")
  ext["ReaPersona/my look"] = nil
  assert(core.setup_items()["setting my look"] == nil, "a look never saved here isn't sent (it would win over the one you saved elsewhere)")
  reaper.GetToggleCommandState, reaper.Main_OnCommand, reaper.GetLastColorThemeFile = gt, mo, lt
  ext["ReaPersona/style"], ext["ReaPersona/theme my_reaper"], ext["ReaPersona/orig"] = nil, nil, nil
end
-- 16. Scripts that start with REAPER (5.22): read from __startup.lua as FTC Tools writes them, kept by your look and the personas you save,
-- and added (and started, when stopped) wherever they're registered. Only command names travel.
do
  local ftc = "-- BandSync render guard\nif os.getenv('X') then return end\n-- Start script: Chordbox\nlocal chord_box_cmd_name = '_RSfe34'\n" ..
    "reaper.Main_OnCommand(reaper.NamedCommandLookup(chord_box_cmd_name), 0)\n\n-- Start script: Gridbox\nlocal grid = '_RS02de'\n" ..
    "reaper.Main_OnCommand(reaper.NamedCommandLookup(grid), 0)\n-- >>> ReaPersona\ndo dofile(core).restore_last() end\n-- <<< ReaPersona <<<\n" ..
    "reaper.Main_OnCommand(reaper.NamedCommandLookup('_SWS_ABOUT'), 0)\nlocal path = '_RSnotacommandcall'\n"
  local s = core.starts_in(ftc)
  assert(#s == 3 and s[1][1] == "Chordbox" and s[1][2] == "_RSfe34" and s[2][1] == "Gridbox" and s[3][1] == "_SWS_ABOUT", "FTC's start lines and a direct one, nothing else")
  assert(#core.safe_starts({ { "evil", "_RS1'); os.execute('x" }, { "ok", "_RSab" } }) == 1, "only command names")
  os.execute(win and ('mkdir "' .. (tmp .. "/Scripts"):gsub("/", "\\") .. '" 2>nul') or ("mkdir -p '" .. tmp .. "/Scripts'"))
  local sp = tmp .. "/Scripts/__startup.lua"
  write(sp, ftc)
  local reg = { _RSfe34 = 101, _RS02de = 102, _RSnew1 = 103, _RSoff = 104 }
  local states = { [101] = 1, [102] = 1, [103] = -1, [104] = 0 }
  local ran = {}
  local nl, gt, mo = reaper.NamedCommandLookup, reaper.GetToggleCommandState, reaper.Main_OnCommand
  reaper.NamedCommandLookup = function(c) return reg[c] or 0 end
  reaper.GetToggleCommandState = function(id) return states[id] or -1 end
  reaper.Main_OnCommand = function(id) ran[#ran + 1] = id; if states[id] == 0 then states[id] = 1 end end
  local added, started = core.ensure_starts({ { "Chordbox", "_RSfe34" }, { "New one", "_RSnew1" }, { "Stopped", "_RSoff" }, { "Not here", "_RSmissing" } })
  assert(#added == 2 and added[1] == "New one" and added[2] == "Stopped", "start lines added for registered scripts not in the file yet")
  assert(#started == 1 and started[1] == "Stopped" and #ran == 1 and ran[1] == 104, "only a stopped one is started: running one again would stop it")
  local text = read(sp)
  assert(text:sub(1, #ftc) == ftc and #core.starts_in(text) == 5 and read(sp .. ".before-reapersona-starts") == ftc, "your lines kept, a backup made")
  local again = core.ensure_starts({ { "New one", "_RSnew1" } })
  assert(#again == 0 and read(sp) == text, "nothing added twice")
  -- your look and the personas you save keep them; using one makes sure they run
  ext["ReaPersona/style"] = "my_reaper"
  local look = assert(core.save_my_look())
  assert(#look.starts == 5 and #core.my_look().starts == 5 and core.look_label(core.my_look()):find("Chordbox at start", 1, true))
  local ps = core.preset_style({ id = "preset_st", name = "S", base = "pro_tools", feel = {}, starts = { { "Stopped", "_RSoff" }, { "bad", "rm -rf" } } })
  assert(#ps.starts == 1 and ps.description:find("Starts with REAPER: Stopped", 1, true), "a saved persona says what it starts")
  write(sp, ftc); states[104] = 0; ran = {}
  core.use(ps)
  assert(read(sp):find("_RSoff", 1, true) and states[104] == 1, "using a persona brings its scripts back")
  local built = assert(core.build_style({ core.new_block("daw", "my_reaper") }, "Built", "built_st"))
  assert(#(built.starts or {}) == 5, "a built persona on My REAPER keeps your scripts")
  core.forget_my_look(); ext["ReaPersona/my look"] = nil
  reaper.NamedCommandLookup, reaper.GetToggleCommandState, reaper.Main_OnCommand = nl, gt, mo
  ext["ReaPersona/style"], ext["ReaPersona/orig"] = nil, nil
end
-- 17. Updates (5.23): versions compared, test versions before their release, and only ReaPersona's own files read from an index.
do
  local lt = core.version_less
  assert(lt("5.21.1", "5.22.0") and lt("5.9.9", "5.10.0") and not lt("5.22.0", "5.22.0") and not lt("5.22.0", "5.21.9"))
  assert(lt("5.23.0-test1", "5.23.0") and not lt("5.23.0", "5.23.0-test1") and lt("5.23.0-test1", "5.23.0-test2") and lt("5.22.0", "5.23.0-test1"))
  local xml = [[<index><category name="Workflow"><reapack name="ReaPersona.lua" type="script"><version name="5.23.0" author="James">
        <source main="main">https://github.com/FmsJay/ReaPersona/raw/abc123/ReaPersona/ReaPersona.lua</source>
        <source file="previews/pro tools.png">https://github.com/FmsJay/ReaPersona/raw/abc123/ReaPersona/previews/pro%20tools.png</source>
        <source file="../../evil.lua">https://github.com/FmsJay/ReaPersona/raw/abc123/ReaPersona/evil.lua</source>
        <source file="x.lua">https://evil.example.com/FmsJay/ReaPersona/raw/abc123/ReaPersona/x.lua</source>
        <source platform="win64" file="reaper_x-x64.dll">https://github.com/FmsJay/ReaPersona/raw/abc123/ReaPersona/reaper_x-x64.dll</source>
      </version></reapack><reapack name="ReaPersona menus.ext"><version name="1.0.1"><source file="y.lua">https://github.com/FmsJay/ReaPersona/raw/abc123/ReaPersona/y.lua</source></version></reapack></category></index>]]
  local info = assert(core.parse_index(xml))
  assert(info.version == "5.23.0" and #info.files == 2 and info.files[1][1] == "ReaPersona.lua" and info.files[2][1] == "previews/pro tools.png",
    "its main script and files; nothing outside its folder, from elsewhere, a loaded extension or another package")
  assert(core.parse_index("<html>rate limited</html>") == nil and core.parse_index(nil) == nil)
  assert(not core.synced_setting("update seen"), "when this computer last looked is its own")
end
-- 18. Where a startup script came from (5.24): ReaPack's repository and package, kept with it, checked when it comes from elsewhere, and
-- a script missing here offered from it (only when the persona says where to get it).
do
  local kb = '\nSCR 4 0 RSfe34 "Custom: Chordbox.lua" "FTC Tools/Transport/Chordbox.lua"\nSCR 4 32060 RS7d3c_fe34 "Custom: x" "y.lua"\nSCR 4 0 RSabs "Custom: z" "C:/z.lua"\n'
  local paths = core.script_paths(kb)
  assert(paths.RSfe34 == "FTC Tools/Transport/Chordbox.lua" and paths.RSabs == "C:/z.lua")
  local owner, gi, gr, fe = reaper.ReaPack_GetOwner, reaper.ReaPack_GetEntryInfo, reaper.ReaPack_GetRepositoryInfo, reaper.ReaPack_FreeEntry
  local asked
  reaper.ReaPack_GetOwner = function(f) asked = f; return f:find("Chordbox", 1, true) and {} or nil end
  reaper.ReaPack_GetEntryInfo = function() return true, "FTC Tools", "Transport", "Chordbox" end
  reaper.ReaPack_GetRepositoryInfo = function(r) return r == "FTC Tools", "https://raw.githubusercontent.com/iliaspoulakis/Reaper-Tools/master/index.xml", true, 0 end
  reaper.ReaPack_FreeEntry = function() end
  local src = assert(core.start_source("_RSfe34", paths))
  assert(asked == tmp .. "/Scripts/FTC Tools/Transport/Chordbox.lua" and src.repo == "FTC Tools" and src.pkg == "Chordbox" and src.url:match("^https://"))
  assert(core.start_source("_RSabs", paths) == nil, "one ReaPack didn't install: no source")
  reaper.ReaPack_GetOwner, reaper.ReaPack_GetEntryInfo, reaper.ReaPack_GetRepositoryInfo, reaper.ReaPack_FreeEntry = owner, gi, gr, fe
  local s = core.safe_starts({ { "Chordbox", "_RSfe34", src }, { "Bad url", "_RSb", { repo = "X", url = "file:///etc/x", pkg = "p" } },
    { "Bad repo", "_RSc", { repo = "X|Y\n", url = "https://x", pkg = "p" } } })
  assert(s[1][3] and s[1][3].repo == "FTC Tools" and not s[2][3] and not s[3][3], "only an https address and a plain repository name come along")
  -- not installed here: offered when the persona knows where it comes from, and nothing written for it
  write(tmp .. "/Scripts/__startup.lua", "")
  local nl = reaper.NamedCommandLookup
  reaper.NamedCommandLookup = function() return 0 end
  local added, _, missing = core.ensure_starts({ s[1], { "Unknown", "_RSzz" } })
  assert(#added == 0 and #missing == 1 and missing[1][1] == "Chordbox" and read(tmp .. "/Scripts/__startup.lua") == "")
  ext["ReaPersona/style"] = "my_reaper"
  core.use(core.preset_style({ id = "preset_src", name = "Src", base = "pro_tools", feel = {}, starts = { s[1] } }))
  assert(#core.starts_missing == 1 and core.starts_missing[1][3].pkg == "Chordbox", "using it tells the window what to offer")
  reaper.NamedCommandLookup = nl
  ext["ReaPersona/style"], ext["ReaPersona/orig"] = nil, nil
end
-- 19. A persona made from every tab (5.26): one of a kind replaces, the same block again moves to the bottom, different ones stack, and
-- any persona opens as blocks to edit.
do
  local list = {}
  core.draft_add(list, core.new_block("theme", "A.ReaperThemeZip"))
  core.draft_add(list, core.new_block("daw", "pro_tools"))
  local _, rep = core.draft_add(list, core.new_block("theme", "B.ReaperThemeZip"))
  assert(rep and #list == 2 and list[2].file == "B.ReaperThemeZip", "a second theme replaces the first, and goes to the bottom")
  local keys = core.new_block("daw", "ableton"); keys.feel, keys.theme, keys.mouse = false, false, false
  core.draft_add(list, keys)
  core.draft_add(list, core.new_block("mouse", "logic"))
  _, rep = core.draft_add(list, core.new_block("mouse", "bitwig"))
  assert(rep and #list == 4 and list[4].id == "bitwig", "one mouse")
  _, rep = core.draft_add(list, core.new_block("daw", "pro_tools"))
  assert(rep and #list == 4 and list[4].kind == "daw" and list[4].id == "pro_tools", "the same block again moves to the bottom (lower wins)")
  _, rep = core.draft_add(list, core.new_block("daw", "ableton"))
  assert(not rep and #list == 5, "Ableton whole is not Ableton's shortcuts: both stay")
  local g = core.SETTING_GROUPS[1].id
  core.draft_add(list, core.new_block("settings", g)); _, rep = core.draft_add(list, core.new_block("settings", g))
  assert(rep and #list == 6, "a settings group once")
  -- editing: a built persona as its blocks (a copy), a DAW persona whole, a saved setup with its colours
  local built = { blocks = { core.new_block("daw", "logic") }, name = "B" }
  built.blocks[1].off = { ["key Ctrl+Z"] = true }
  local bb = core.blocks_of(built)
  bb[1].off["key Ctrl+X"] = true
  assert(#bb > 1 and built.blocks[1].off["key Ctrl+X"] == nil, "a copy: editing doesn't change the saved persona until it's saved")
  local d = core.blocks_of(core.by_id("pro_tools"))
  assert(core.draft_get(d, "keys").id == "pro_tools" and core.draft_get(d, "mouse") and core.draft_get(d, "feel transport") and core.draft_get(d, "theme"),
    "a DAW persona opens as one block per slot (5.27)")
  local p = core.blocks_of({ id = "preset_x", preset = true, colours = { ["colour look"] = "{}" } })
  assert(#p == 2 and p[1].id == "preset_x" and p[2].kind == "colours", "a saved setup keeps its colours")
end
-- 20. One block per slot (5.27): a whole DAW splits into its parts (lines left out stay out), the build order is fixed, its keys and mouse
-- together still borrow its layer, and favourites.
do
  local whole = core.new_block("daw", "pro_tools"); whole.off = { ["key Ctrl+Z"] = true }
  local parts = core.split_blocks({ whole, core.new_block("theme", "X.ReaperThemeZip") })
  local k = core.draft_get(parts, "keys")
  assert(k and k.off and k.off["key Ctrl+Z"] and core.draft_get(parts, "theme").file == "X.ReaperThemeZip", "a later theme block replaces the DAW's own; left-out lines stay out")
  local order = core.draft_order({ core.new_block("project"), core.new_block("theme", "T"), core.new_block("settings", core.SETTING_GROUPS[1].id), core.new_block("feel", "logic", "transport"), core.new_block("mouse", "logic"), core.keys_block("logic") })
  local kinds = {}; for i, b in ipairs(order) do kinds[i] = core.block_slot(b):match("^%a+") end
  assert(table.concat(kinds, ",") == "keys,mouse,feel,settings,theme,project", table.concat(kinds, ","))
  assert(core.keys_layer({ core.keys_block("logic"), core.new_block("mouse", "logic") }) == "borrow", "a DAW's keys and its mouse: its own layer, nothing to install")
  assert(core.keys_layer({ core.keys_block("logic"), core.new_block("mouse", "ableton") }) == "own", "another DAW's mouse wheel: a layer of its own")
  assert(core.block_title(core.keys_block("logic")):find("shortcuts", 1, true) and core.block_title(core.keys_block("my_reaper")) == "Your own shortcuts")
  local has = reaper.HasExtState
  reaper.HasExtState = function(s, key) return ext[s .. "/" .. key] ~= nil end
  ext["ReaPersona/style"] = "ableton"; ext["ReaPersona/favourites"] = nil
  local f = core.favourites()
  assert(#f == 2 and f[1] == "my_reaper" and f[2] == "ableton", "never set: My REAPER and the persona in use")
  core.set_favourite("logic", true); core.set_favourite("my_reaper", false)
  assert(ext["ReaPersona/favourites"] == "ableton;logic" and core.is_favourite("logic") and not core.is_favourite("my_reaper"))
  core.set_favourite("ableton", false); core.set_favourite("logic", false)
  assert(#core.favourites() == 0 and core.setup_items()["setting favourites"] == nil, "none starred: not sent as an empty list that would win elsewhere")
  reaper.HasExtState = has
  ext["ReaPersona/style"], ext["ReaPersona/favourites"] = nil, nil
end
-- 21. Never over a built-in (5.27.1): saving with a DAW's id makes a new persona and leaves the DAW alone; unnamed, "<DAW> - custom".
do
  assert(core.custom_name("Pro Tools") == "Pro Tools - custom")
  local pt = core.by_id("pro_tools")
  local st = assert(core.save_built({ core.keys_block("pro_tools") }, core.custom_name("Pro Tools"), "pro_tools"))
  assert(st.id ~= "pro_tools" and core.by_id("pro_tools") == pt and not pt.user, "the DAW stays as it ships; the save is a persona of yours")
  assert(core.custom_name("Pro Tools") == "Pro Tools - custom 2", "a second one gets a number")
  local again = assert(core.save_built({ core.keys_block("logic") }, "Renamed", st.id))
  assert(again.id == st.id, "one you built is saved over")
  for n = #core.styles, 1, -1 do if core.styles[n].id == st.id then table.remove(core.styles, n) end end
end
-- 22. Versions and My REAPER (5.28): saving over keeps the one before; My REAPER opens as its look and saves as its look.
do
  local st, why0 = core.save_built({ core.new_block("theme", "One.ReaperThemeZip") }, "Versioned", nil); assert(st, why0)
  local n0 = #core.versions(st.id) -- (an id used earlier in this run may have some already)
  assert(core.save_built({ core.new_block("theme", "Two.ReaperThemeZip") }, "Versioned", st.id))
  local v = core.versions(st.id)
  assert(#v == n0 + 1 and v[1].data.blocks[1].file == "One.ReaperThemeZip", "the version before is kept")
  core.save_user_style(v[1].data)
  assert(core.by_id(st.id).blocks[1].file == "One.ReaperThemeZip" and #core.versions(st.id) == n0 + 2, "putting one back keeps the one you had too")
  for n = #core.styles, 1, -1 do if core.styles[n].id == st.id then table.remove(core.styles, n) end end
  -- My REAPER's look: its parts open from the look, and saving keeps the look before
  ext["ReaPersona/my look"] = core.json_encode({ theme = "A.ReaperThemeZip", feel = { { "radio", { 41603, 41604, 41605, 41606, 41608 }, 41606, "Transport at the top" } } }):gsub("\n%s*", "")
  local mine = core.blocks_of(core.by_id("my_reaper"))
  local tr = core.draft_get(mine, "feel transport")
  assert(tr and tr.id == "my_reaper", "My REAPER opens with its look's transport")
  local built = core.build_style(core.draft_order(mine), "My REAPER", "built_try")
  local look = core.look_from_style(built)
  assert(look.feel[1][3] == 41606, "and saves it back as its look")
  core.save_look(look)
  assert(#core.versions("my_reaper") == 1 and core.versions("my_reaper")[1].data.theme == "A.ReaperThemeZip", "the look before is kept")
  ext["ReaPersona/my look"] = nil
end
-- 23. Shortcut layers (5.29): only for the personas used, the same keys share one, one that had a layer keeps it, yours are never taken.
do
  local S = {}
  for _, id in ipairs({ "pro_tools", "pro_tools_intro", "logic", "ableton", "cubase", "nuendo", "base_reaper" }) do
    local st = core.by_id(id); S[#S + 1] = { id = id, default_alt = st.default_alt or st.alt, keys = st.keys }
  end
  local m = core.plan_layers(S, { pro_tools_intro = true, logic = true }, {}, {})
  assert(m.pro_tools_intro and m.pro_tools == m.pro_tools_intro, "Pro Tools and Pro Tools Intro have the same keys: one layer")
  assert(m.logic == 2 and m.ableton == nil and m.cubase == nil, "only what's used; the number it ships with when free")
  local m2 = core.plan_layers(S, { logic = true, ableton = true }, { logic = 9 }, { [3] = true })
  assert(m2.logic == 9, "one that had a layer keeps it (no reinstall)")
  assert(m2.ableton ~= 3 and m2.ableton ~= 9 and m2.ableton >= 1 and m2.ableton <= 16, "a layer of yours is never taken")
  local full = {}; for n = 1, 16 do full[n] = true end
  assert(core.plan_layers(S, { logic = true }, {}, full).logic == nil, "none free: none given")
  local m3 = core.plan_layers(S, { ableton = true }, {}, { [3] = true }, { [1] = true, [2] = true })
  assert(m3.ableton == 4, "a clean layer before one with other tools' keys in it")
  -- applied: a persona with no layer here has none, and remembers the one it ships with
  local A = { { id = "x", alt = 5, keys = {} }, { id = "y", alt = 6, keys = {} }, { id = "mine", alt = 7, user = true } }
  core.apply_layer_map(A, { x = 11 })
  assert(A[1].alt == 11 and A[1].default_alt == 5 and A[2].alt == 0 and A[2].default_alt == 6 and A[3].alt == 7)
  assert(core.needs_layer(A[2]) and not core.needs_layer(A[1]) and not core.needs_layer(A[3]))
  -- what this computer needs: favourites, the one in use, what your own build on
  local has = reaper.HasExtState
  reaper.HasExtState = function(s, key) return ext[s .. "/" .. key] ~= nil end
  ext["ReaPersona/favourites"] = "cubase"; ext["ReaPersona/style"] = "my_reaper"
  local w = core.layers_wanted("bitwig")
  assert(w.cubase and w.bitwig and w.my_reaper and not w.reason)
  reaper.HasExtState = has
  ext["ReaPersona/favourites"], ext["ReaPersona/style"] = nil, nil
end
-- 24. The shortcut editor (5.30): a key moved, a key added (over one the persona had), the catalog of every key, most used first.
do
  local b = core.keys_block("pro_tools")
  local first = core.keys_here(core.by_id("pro_tools").keys)[1]
  b.rebind = { [core.canon(first[1])] = "Ctrl+Alt+Shift+F12" }
  b.extra = { { "Ctrl+Alt+Shift+F11", 40001, "Track: Insert new track" }, { first[1], 40029, "Edit: Undo" }, { "Nonsense+Key", 1, "x" } }
  local lines = core.build_preview({ b })[1]
  local moved, added, on_first, bad = nil, nil, nil, false
  for _, e in ipairs(lines) do
    if e.key == "Ctrl+Alt+Shift+F12" then moved = e end
    if e.key == "Ctrl+Alt+Shift+F11" then added = e end
    if core.canon(e.key or "") == core.canon(first[1]) then on_first = e end
    if e.key == "Nonsense+Key" then bad = true end
  end
  assert(moved and moved.moved_from == first[1] and moved.entry[2] == first[2], "a key moved keeps its action")
  assert(added and added.extra == 1 and added.entry[2] == 40001, "a key added from anywhere")
  assert(on_first and on_first.entry[2] == 40029 and on_first.extra == 2, "an added key on a key the persona had freed: it's the added one")
  assert(not bad, "a key REAPER can't take is left out")
  local st = assert(core.build_style({ b }, "Edited", "built_try"))
  local found = 0
  for _, k in ipairs(st.keys) do if k[1] == "Ctrl+Alt+Shift+F12" or k[1] == "Ctrl+Alt+Shift+F11" then found = found + 1 end end
  assert(found == 2, "the persona has them")
  -- the catalog: your keymap's keys and every persona's, the actions most personas use first
  local kb = "KEY 1 65 40001 0\t\t # Main : A : OVERRIDE DEFAULT : Track: Insert new track\nKEY 9 90 _RS30122590024a7fcbbe25f51663b84ca6c69baea0 0\t\t # Main : Ctrl+Z : Script: StudioSync - Undo.lua\nKEY 1 66 0 0\t\t # Main : B : DISABLED DEFAULT\nKEY 1 67 40002 5\t\t # Main (alt-5) : C : x\n"
  local mine = core.keymap_keys(kb)
  assert(#mine == 2 and mine[1][1] == "A" and mine[1][3] == "Track: Insert new track" and mine[2][3] == "Script: StudioSync - Undo.lua", "Main only, disabled ones out, names from the comments")
  local cat = core.catalog(core.styles, kb)
  assert(#cat > 100 and cat[1].common >= cat[#cat].common, "most used first")
  local seen_mine = false
  for _, r in ipairs(cat) do if r.spec == "A" and r.cmd == 40001 then seen_mine = r.sources[#r.sources] == "Your keymap" end end
  assert(seen_mine, "your keymap's keys are in it")
  assert(core.action_kind(40001) == "REAPER action" and core.action_kind("_RS1234") == "Script" and core.action_kind("_" .. string.rep("a", 32)) == "Custom action" and core.action_kind("_SWS_ABOUT") == "SWS / extension")
end
-- 25. Mouse and trackpad (5.31): REAPER's own page read (contexts, wheel, every key with defaults), the mouse catalog, a mouse line changed
-- or added, a wheel binding added.
do
  local page = table.concat({
    '<TR><TD COLSPAN=2><FONT SIZE=4><B>Mousewheel modifiers</B></FONT></TD></TR>',
    '<TR><TD>Default action</TD><TD>View: Scroll vertically </TD></TR>',
    '<TR><TD>Ctrl</TD><TD>View: Zoom vertically </TD></TR>',
    '<TR><TD COLSPAN=2><FONT SIZE=4><B>Mouse: Media item left drag</B></FONT></TD></TR>',
    '<TR><TD>Default action</TD><TD>Move item ignoring time selection</TD></TR>',
    '<TR><TD>Shift+Ctrl</TD><TD>Copy item ignoring snap</TD></TR>',
    '<TR><TD><BR></TD></TR>',
    '<TR><TD COLSPAN=2><h3>Section: Main</h3></TD></TR>',
    '<TR><TD><B>Key</B></TD><TD><B>Action</B></TD></TR>',
    '<TR><TD>Ctrl+F4</TD><TD>Close current project tab</TD></TR>',
    '<TR><TD>Ctrl+Shift+H (GLOBAL + text fields)</TD><TD>Helgobox/General: Toggle app focus</TD></TR>',
    '<TR><TD COLSPAN=2><h3>Section: Media Explorer</h3></TD></TR>',
    '<TR><TD>Space</TD><TD>Preview: Play</TD></TR>' }, "\n")
  local d = core.parse_shortcut_page(page)
  assert(d.wheel[0] == "View: Scroll vertically" and d.wheel[2] == "View: Zoom vertically", "the wheel, by modifiers")
  assert(d.mouse["Media item left drag"][0] == "Move item ignoring time selection" and d.mouse["Media item left drag"][3] == "Copy item ignoring snap", "Shift+Ctrl is 3")
  assert(#d.keys == 2 and d.keys[1][1] == "Ctrl+F4" and d.keys[2][1] == "Ctrl+Shift+H" and d.keys[1][3] == "Main", "Main's keys, a note after the key dropped, other sections not")
  assert(core.CTX_NAME.MM_CTX_ITEM == "Media item left drag" and core.CTX_NAME.MM_CTX_ITEMLOWER == "Media item bottom half left drag" and #core.MOUSE_CONTEXTS == 88)
  assert(core.mouse_mods(0) == "" and core.mouse_mods(5) == "Shift+Alt" and core.mouse_mods(15) == "Shift+Ctrl+Alt+Win")
  local rows = core.mouse_catalog(core.styles, d, function(ctx, flag) return (ctx == "MM_CTX_ITEM" and flag == 3) and "8 m" or "" end)
  local item0, item3, persona = nil, nil, false
  for _, r in ipairs(rows) do
    if r.ctx == "MM_CTX_ITEM" and r.flag == 0 then item0 = r end
    if r.ctx == "MM_CTX_ITEM" and r.flag == 3 then item3 = r end
    for _, s in ipairs(r.sources) do if s == "Pro Tools" then persona = true end end
  end
  assert(item0.value == "-1" and item3.value == "8 m" and persona, "REAPER's default is -1, a value set is REAPER's id, the personas' are in")
  -- a persona's mouse: a line changed, a line added (over one it had), a wheel binding added
  local b = core.new_block("mouse", "pro_tools")
  local first = core.build_preview({ b })[1]
  local line
  for _, e in ipairs(first) do if e.entry and e.entry[1] == "mouse" then line = e; break end end
  assert(line, "Pro Tools has mouse lines")
  b.mset = { [line.slot] = "4 m" }
  b.mextra = { { "mouse", "MM_CTX_TRACK", 6, "2 m", "Ctrl+Alt+drag a track" }, { "mouse", line.entry[2], line.entry[3], "7 m", "over it" } }
  b.extra = { { "Ctrl+Alt+Shift+Mousewheel", 990, "Zoom" }, { "Ctrl+Z", 40029, "not a wheel" } }
  local lines = core.build_preview({ b })[1]
  local changed, added, over, wheel, notwheel = nil, nil, nil, nil, false
  for _, e in ipairs(lines) do
    if e.slot == line.slot then over = e end
    if e.entry and e.entry[2] == "MM_CTX_TRACK" and e.entry[3] == 6 then added = e end
    if e.key == "Ctrl+Alt+Shift+Mousewheel" then wheel = e end
    if e.key == "Ctrl+Z" then notwheel = true end
  end
  assert(over and over.entry[4] == "7 m" and over.extra == 2, "an added line on a context and modifiers it had: the added one, once " .. tostring(over and over.entry[4]) .. " " .. tostring(over and over.extra) .. " " .. line.slot .. " " .. tostring(over and over.slot))
  assert(added and added.entry[4] == "2 m", "a line added")
  assert(wheel and wheel.entry[2] == 990 and not notwheel, "a wheel binding added; only wheel keys on the mouse")
  b.mextra = nil
  for _, e in ipairs(core.build_preview({ b })[1]) do if e.slot == line.slot then changed = e end end
  assert(changed and changed.entry[4] == "4 m" and changed.changed, "a line changed")
end
-- 26. The layout designer (5.32): a layout as a persona's lines (docked windows in tab order), a persona's lines as a layout, only windows
-- and places ReaPersona can put back, and the layout block over the parts it covers.
do
  local items = { explorer = { zone = "d_bottom", order = 1 }, mixer = { zone = "d_bottom", order = 2 }, transport = { zone = "t_top", order = 1 },
    midi = { zone = "float", order = 1 }, navigator = { zone = "d_left", order = 1 } }
  local e = core.layout_entries(items)
  local docks, radio, midi = {}, nil, nil
  for _, f in ipairs(e) do
    if f[1] == "dock" then docks[#docks + 1] = f[2] .. ":" .. f[3] end
    if f[1] == "radio" then radio = f[3] end
    if f[1] == "midi_dock" then midi = f[2] end
  end
  assert(table.concat(docks, ",") == "explorer:bottom,mixer:bottom", "two tabs in the bottom dock, docked in their order")
  assert(radio == 41606 and midi == 0 and #e == 4, "the transport at the top, the MIDI editor floating, nothing for a window ReaPersona can't put back")
  local bad = core.layout_entries({ transport = { zone = "d_left" }, mixer = { zone = "nowhere" } })
  assert(#bad == 0, "only places each window can go")
  local hidden = core.layout_entries({ mixer = { zone = "hidden" }, explorer = { zone = "hidden" } })
  assert(hidden[1][1] == "toggle" and hidden[1][2] == 40078 and hidden[1][3] == 0 and hidden[2][1] == "dock" and hidden[2][3] == "float" and hidden[2][4] == 0, "closed: the mixer hidden, the Media Explorer closed")
  -- back again: a persona's lines as the layout the designer starts from
  local back = core.layout_from_entries(e)
  assert(back.explorer.zone == "d_bottom" and back.mixer.zone == "d_bottom" and back.transport.zone == "t_top" and back.midi.zone == "float")
  local pt = core.layout_from_entries(core.by_id("pro_tools").feel)
  assert(pt.mixer.zone == "float" or pt.mixer.zone == "hidden", "Pro Tools keeps its mix window apart")
  -- in a persona: the layout block sets those lines and wins over a DAW's parts for them
  local blocks = { core.new_block("feel", "pro_tools", "transport"), { kind = "layout", items = { transport = { zone = "t_bottom", order = 1 } } } }
  local st = assert(core.build_style(core.draft_order(blocks), "Laid out", "built_try"))
  local got
  for _, f in ipairs(st.feel) do if f[1] == "radio" and f[2][1] == 41603 then got = f[3] end end
  assert(got == 41605, "the designer's transport wins")
  assert(core.block_slot({ kind = "layout" }) == "layout" and core.block_title({ kind = "layout" }) == "Layout: your own")
end
do -- 27. project defaults: tempo, time signature and grid (5.33)
  local ents = core.project_entries({ kind = "project", srate = 0, tracks = "", wset = 0, bpm = 92, ts_num = 6, ts_den = 8, grid = 1 / 12 })
  local by = {}
  for _, e in ipairs(ents) do by[e.slot] = e end
  assert(by["project bpm"] and by["project bpm"].value.bpm == 92, "a tempo line")
  assert(by["project ts"] and by["project ts"].value.ts_num == 6 and by["project ts"].value.ts_den == 8, "a time signature line")
  assert(by["project grid"] and by["project grid"].label:find("1/8 triplet", 1, true), "the grid by its name")
  local bad = core.project_entries({ kind = "project", srate = 0, tracks = "", wset = 0, bpm = 5, ts_num = 4, ts_den = 3, grid = 9 })
  assert(#bad == 0, "no tempo under 10, no denominator of 3, no grid over 4")
  assert(core.grid_name(0.25) == "1/4" and core.grid_name(1 / 24) == "1/16 triplet" and core.grid_name(0.3) == "0.3")
  local st = assert(core.build_style({ { kind = "project", srate = 48000, tracks = "", wset = 0, bpm = 140, ts_num = 3, ts_den = 4 } }, "Waltz", "built_x"))
  assert(st.project.srate == 48000 and st.project.bpm == 140 and st.project.ts_num == 3 and st.project.ts_den == 4, "into the persona's project part")
end
assert(tmp:match("^tests/_tmp%-%d+%-%d+$")) -- (the whole test folder goes: setup files, sync files, copies of files that didn't parse)
os.execute(win and ('rmdir /s /q "' .. tmp:gsub("/", "\\") .. '"') or ("rm -rf '" .. tmp .. "'"))
print("ok")
