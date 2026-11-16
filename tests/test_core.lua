-- ReaPersona's pure checks: the engine (reapersona_core.lua) loaded without REAPER, on a stand-in `reaper` table, from a copy in a
-- folder of its own (tests/_tmp-..., removed at the end), so nothing else in the repo or in a REAPER is written. Asserts only: silence and "ok" means it passed.
-- Run from the repo root with Lua 5.4:   lua tests/test_core.lua
-- or, without Lua (Windows), with lupa:  python -c "import lupa.lua54 as l; l.LuaRuntime().execute(open('tests/test_core.lua').read())"
-- (Added for the left-over items of the 2026-11-16 review, 5.9.3: one check per new piece of logic.)

local function read(p) local f = io.open(p, "rb"); if not f then return nil end local t = f:read("a"); f:close(); return t end
local function write(p, t) local f = assert(io.open(p, "wb")); f:write(t); f:close() end
local win = package.config:sub(1, 1) == "\\"
local tmp = "tests/_tmp-" .. os.time() .. "-" .. math.random(1000, 9999)
os.execute(win and ('mkdir "' .. tmp:gsub("/", "\\") .. '"') or ("mkdir -p '" .. tmp .. "'"))
write(tmp .. "/reapersona_core.lua", assert(read("ReaPersona/reapersona_core.lua"), "run this from the repo root"))
write(tmp .. "/styles.json", read("ReaPersona/styles.json"))

local ext = {}
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
assert(moved.alt == 13, "moved to the first free layer, got " .. tostring(moved.alt))
assert(read(tmp .. "/user_styles.json"):find('"alt": 13', 1, true), "and saved")
-- "Make them its own": a copy of the DAW's keys on a free layer, no longer tied to the DAW.
write(tmp .. "/user_styles.json", '{"styles": [{"id": "built_2", "name": "Mixing", "kind": "built", "keys_from": "logic"}]}')
core = load_core()
local mixing, logic = core.by_id("built_2"), core.by_id("logic")
assert(mixing.alt == logic.alt and mixing.keys == logic.keys)
assert(core.own_layer(mixing))
assert(mixing.alt == 13 and mixing.keys_from == nil and mixing.keys ~= logic.keys and #mixing.keys == #logic.keys)
assert(logic.alt == 2 and core.by_id("logic").keys == logic.keys, "the DAW keeps its own")
assert(load_core().by_id("built_2").alt == 13, "saved with its own layer")

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

for _, f in ipairs({ "reapersona_core.lua", "styles.json", "user_styles.json" }) do os.remove(tmp .. "/" .. f) end
os.execute(win and ('rmdir "' .. tmp:gsub("/", "\\") .. '"') or ("rmdir '" .. tmp .. "'")) -- (empty by now: rmdir leaves it if not)
print("ok")
