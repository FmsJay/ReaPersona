"""ReaPersona's two shortcut installers, checked against each other, plus install_shortcuts.py's own self-test and its post-quit path.

    python tests/test_installers.py        (from anywhere; needs Python 3 and lupa: pip install lupa)

The installers: install_shortcuts.py's run() (Python, REAPER closed) and reapersona_core.lua's stage_install() (kb_plan + menu_plan,
the install without Python). They are kept in step by hand, so each case below builds a temp REAPER resource folder (reaper.ini +
Scripts/ReaPersona/ holding copies of the installer, the engine and styles.json), runs the Lua side through lupa (it only plans: the
new files wait in install_staged/), then the Python side (it writes the live files), and compares what each would leave behind:
reaper-kb.ini, reaper-menu.ini, installed.json, midi_fallback.json, and how many things each skipped. Nothing outside the temp folders
is touched: no REAPER, no repo file. Prints one line per case; exit 1 if anything differs.
"""
import contextlib, difflib, importlib.util, io, json, os, re, shutil, subprocess, sys, tempfile

import lupa.lua54 as lupa

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "ReaPersona")
COPIES = ("install_shortcuts.py", "styles.json", "reapersona_core.lua", "reapersona_keys.lua")
STYLES = json.load(open(os.path.join(SRC, "styles.json"), encoding="utf-8"))["styles"]

# The engine on a stand-in `reaper` (as tests/test_core.lua's), resource folder RES, system OS_NAME; then the install planned.
LUA = r'''
local RES, OS_NAME, REMOVE, NO_MIDI = ...
local win = package.config:sub(1, 1) ~= "/"
local ext, listing = {}, {}
reaper = setmetatable({
  GetResourcePath = function() return RES end,
  GetOS = function() return OS_NAME end,
  GetExtState = function(s, k) return ext[s .. "/" .. k] or "" end,
  SetExtState = function(s, k, v) ext[s .. "/" .. k] = v end,
  DeleteExtState = function(s, k) ext[s .. "/" .. k] = nil end,
  file_exists = function(p) local f = io.open(p, "rb"); if f then f:close() end return f ~= nil end,
  NamedCommandLookup = function() return 0 end,
  GetToggleCommandState = function() return -1 end,
  time_precise = os.clock,
  EnumerateFiles = function(d, i)
    if i < 0 then listing[d] = nil; return end
    if not listing[d] then
      listing[d] = {}
      local p = io.popen(win and ('dir /b /a-d "' .. d:gsub("/", "\\") .. '" 2>nul') or ("ls -p '" .. d .. "' 2>/dev/null | grep -v /"))
      for l in p:lines() do listing[d][#listing[d] + 1] = l end
      p:close()
    end
    return listing[d][i + 1]
  end,
  EnumerateSubdirectories = function() end,
  RecursiveCreateDirectory = function(d)
    os.execute(win and ('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') or ("mkdir -p '" .. d .. "'"))
  end,
}, { __index = function() return function() end end })
local core = dofile(RES .. "/Scripts/ReaPersona/reapersona_core.lua")
local step, why = core.stage_install({ pid = "999999", stamp = "20260101-000000", remove = REMOVE, no_midi = NO_MIDI })
return step or false, why
'''

# ---------------------------------------------------------------- fixtures
SCRIPT_NAMES = sorted({k[1][7:] for s in STYLES for k in s.get("keys", []) if isinstance(k[1], str) and k[1].startswith("script:")})
MIDI_SPECS = sorted({re.sub(r"^(win|mac):", "", m[0]) for s in STYLES for m in s.get("midi_keys", [])})
# scripts.json as the window writes it once it has registered its scripts: every script: action and every MIDI key script has an id
SCRIPTS = {"main": {n: "_RS_" + re.sub(r"\W", "_", n) for n in SCRIPT_NAMES}, "midi": {s: "_RSmidi%02d" % i for i, s in enumerate(MIDI_SPECS)}}
DEFAULTS = {s: 40100 + i for i, s in enumerate(MIDI_SPECS)}  # (midi_defaults.json: what REAPER's MIDI editor runs on each key by default)
FULL = {"scripts.json": json.dumps(SCRIPTS), "midi_defaults.json": json.dumps(DEFAULTS)}
USER_KB = ["KEY 1 65 40001 0\t\t # Main : A : mine", "KEY 9 90 _RSundo 0\t\t # Main : Ctrl+Z : StudioSync undo",
           "KEY 13 76 40099 1\t\t # Main alt-1 : my own Ctrl+Shift+L in Pro Tools' layer", "KEY 1 32 _OSARA_REPORT 0\t\t # OSARA on Space",
           'SCR 4 0 RSabc "Custom: mine.lua" mine.lua', 'ACT 0 0 "mine" "My action" 40001 40002', "KEY 9 81 40777 32060\t\t # MIDI : my own Ctrl+Q"]


def make_res(work, name, files):
    """A temp resource folder: reaper.ini, Scripts/ReaPersona/ with the copies, and files {path under Scripts/ReaPersona or 'RES/...': text}."""
    res = os.path.join(work, name)
    here = os.path.join(res, "Scripts", "ReaPersona")
    os.makedirs(here)
    open(os.path.join(res, "reaper.ini"), "w").write("[REAPER]\n")
    for f in COPIES:
        shutil.copy2(os.path.join(SRC, f), os.path.join(here, f))
    for rel, text in files.items():
        p = os.path.join(res, rel[4:]) if rel.startswith("RES/") else os.path.join(here, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(text.encode("utf-8"))
    return res, here


_n = [0]


def load_py(here, mac=None):
    """install_shortcuts.py imported from the temp folder (it finds its reaper.ini from there), never asking whether REAPER runs."""
    _n[0] += 1
    spec = importlib.util.spec_from_file_location("install_shortcuts_t%d" % _n[0], os.path.join(here, "install_shortcuts.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.reaper_running = lambda: False  # (a REAPER open on this computer, maybe elevated, must not stop the test)
    if mac is not None:
        mod.MAC = mac
    return mod


def run_py(here, remove=False, no_midi=False, mac=None):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        load_py(here, mac).run(remove=remove, no_midi=no_midi)
    return out.getvalue()


def run_lua(res, os_name, remove=False, no_midi=False):
    L = lupa.LuaRuntime(unpack_returned_tuples=True)
    step, why = L.execute(LUA, res.replace("\\", "/"), os_name, remove, no_midi)
    if not step:
        raise RuntimeError("stage_install: %s" % why)
    return step


def read(p):
    return open(p, "rb").read().decode("utf-8", "surrogateescape") if os.path.exists(p) else None


def rewrite_like_reaper(res):
    """REAPER rewrites reaper-kb.ini with its own comments when it quits, so the '# ReaPersona' tags are gone (installed.json counts)."""
    kb = os.path.join(res, "reaper-kb.ini")
    text = read(kb)
    eol = "\r\n" if "\r\n" in text else "\n"
    lines = [(" ".join(l.split()[:5]) + "\t\t # REAPER's comment") if l.startswith("KEY ") else l for l in text.replace("\r\n", "\n").split("\n")]
    open(kb, "wb").write(eol.join(lines).encode("utf-8"))


def compare(case, res, here, step, py_out, menu_before):
    """-> a list of differences between what the Lua side staged and what the Python side wrote."""
    staged = os.path.dirname(step)
    diffs = []

    def diff_text(what, lua, py):
        if lua != py:
            d = list(difflib.unified_diff((lua or "").splitlines(), (py or "").splitlines(), "lua", "python", lineterm="", n=0))
            diffs.append("%s differs:\n      %s" % (what, "\n      ".join(d[:16] + (["..."] if len(d) > 16 else []))))

    diff_text("reaper-kb.ini", read(os.path.join(staged, "1.new")), read(os.path.join(res, "reaper-kb.ini")))
    lua_menu = read(os.path.join(staged, "2.new"))
    diff_text("reaper-menu.ini", lua_menu if lua_menu is not None else menu_before, read(os.path.join(res, "reaper-menu.ini")))
    for name in ("installed.json", "midi_fallback.json"):
        lua_j, py_j = json.loads(read(os.path.join(staged, name))), json.loads(read(os.path.join(here, name)))
        if name == "installed.json":
            lua_j, py_j = lua_j.get("lines") or [], py_j.get("lines") or []  # (an empty list encodes as {} in Lua)
        if lua_j != py_j:
            diffs.append("%s differs: lua %s / python %s" % (name, json.dumps(lua_j)[:300], json.dumps(py_j)[:300]))
    lua_skips = [l for l in read(os.path.join(staged, "ok.txt")).splitlines() if l.startswith("skipped:")]
    py_skips = [l for l in py_out.splitlines() if l.startswith("skipped:")]
    if len(lua_skips) != len(py_skips):  # (the wording differs between the two, the count must not)
        diffs.append("skipped %d in Lua, %d in Python:\n      lua: %s\n      python: %s" % (len(lua_skips), len(py_skips), lua_skips, py_skips))
    return diffs


def parity(work, case, files, os_name="Win64", remove=False, no_midi=False, before=None):
    """One case: the fixtures, an optional earlier install (before(res, here)), then both installers on the same folder."""
    res, here = make_res(work, re.sub(r"\W+", "_", case), files)
    if before:
        before(res, here)
    menu_before = read(os.path.join(res, "reaper-menu.ini"))
    step = run_lua(res, os_name, remove, no_midi)  # (first: it only plans, from the live files as they are)
    py_out = run_py(here, remove, no_midi, mac=os_name.startswith("mac"))
    return compare(case, res, here, step, py_out, menu_before), read(os.path.join(res, "reaper-kb.ini"))


# ---------------------------------------------------------------- the cases (code-health round 1, finding 4)
def first_install(res, here):
    run_py(here)
    rewrite_like_reaper(res)


def upgrade_edits(res, here):
    first_install(res, here)
    kb = os.path.join(res, "reaper-kb.ini")
    lines = read(kb).split("\n")
    manifest = json.load(open(os.path.join(here, "installed.json")))["lines"]
    for i, l in enumerate(lines):  # (one of the lines the last install wrote, rebound by you since: now it's yours)
        if l.startswith("KEY ") and " ".join(l.split()[1:5]) == manifest[0]:
            q = l.split()
            lines[i] = "KEY %s %s 40123 %s\t\t # REAPER's comment" % (q[1], q[2], q[4])
    lines.insert(1, "KEY 1 75 40001 3\t\t # DAW Styles : old name's line")  # (the old name's tag: still ReaPersona's)
    open(kb, "wb").write("\n".join(lines).encode("utf-8"))


USER_STYLES = {"styles": [
    {"id": "built_both", "name": "Built on both", "kind": "built", "alt": 16,  # (a built persona keeps both systems' keys: round 1, A12)
     "keys": [["win:Ctrl+Tab", 40001, "a"], ["mac:Alt+Tab", 40001, "a"], ["Ctrl+Shift+J", "script:" + SCRIPT_NAMES[0], "s"], ["Ctrl+J"], ["Bogus+Q", 1, "bad"]],
     "midi_keys": [["win:Ctrl+Q", "q"], ["mac:Ctrl+Alt+Q", "q"], ["Ctrl+M", "m"], "Ctrl+B"],
     "toolbar_slot": 30, "toolbar": [[40001, "Play"], -1, [40002, "Stop", "stop.png"]]},
    {"id": "built_borrow", "name": "Borrowed", "kind": "built", "keys_from": "logic"},  # (keys resolved at runtime: nothing stored)
]}
LAYERS = {"map": {"pro_tools": 1, "pro_tools_intro": 1, "logic": 2, "fl_studio": 4, "cubase": 3}}  # (the rest: no layer on this computer)
MENU = "\n".join(["[Floating toolbar 5]", "item_0=40001 old", "title=ReaPersona: Old one", "[Floating toolbar 22]", "item_0=40044 mine",
                  "title=My own toolbar", "[Main toolbar]", "item_0=40001 Play", "[Floating MIDI toolbar 8]", "title=empty, so free", ""])
TOOLBAR_FILE = "[toolbar]\ntitle=CF Logic\nitem_0=40001 Play\nicon_0=play.png\nitem_1=-1\n[second]\nitem_0=1 not this\n"

CASES = [
    # 1. an existing keymap with your own lines (LF), on a computer that hasn't run the window yet (no scripts.json, no MIDI defaults)
    ("1a keymap LF, fresh computer", dict(files={"RES/reaper-kb.ini": "\n".join(USER_KB) + "\n"})),
    ("1b keymap CRLF, scripts registered", dict(files=dict(FULL, **{"RES/reaper-kb.ini": "\r\n".join(USER_KB) + "\r\n"}))),
    # 2. an upgrade: installed.json from the last install, REAPER's rewritten comments, a line you changed since, the old name's tag
    ("2 upgrade over installed.json", dict(files=dict(FULL, **{"RES/reaper-kb.ini": "\n".join(USER_KB) + "\n"}), before=upgrade_edits)),
    # 3. remove after an install: only ReaPersona's lines go, your Ctrl+Q MIDI line comes back from midi_fallback.json
    ("3 remove", dict(files=dict(FULL, **{"RES/reaper-kb.ini": "\n".join(USER_KB) + "\n", "RES/reaper-menu.ini": MENU}), before=first_install, remove=True)),
    # 4. every script: key with its registered id
    ("4 script: keys", dict(files=dict(FULL))),
    # 5. MIDI editor keys with REAPER's defaults, FL Studio's win:/mac: Quantize, your own Ctrl+Q line moved aside; on Windows and on a Mac
    ("5a MIDI keys, Windows", dict(files=dict(FULL, **{"RES/reaper-kb.ini": "\n".join(USER_KB) + "\n"}))),
    ("5b MIDI keys, Mac", dict(files=dict(FULL, **{"RES/reaper-kb.ini": "\n".join(USER_KB) + "\n"}), os_name="macOS-arm64")),
    ("5c --no-midi", dict(files=dict(FULL), no_midi=True)),
    # 6. layers.json (most DAWs without a layer here) and your own personas, a malformed key and MIDI entry among them
    ("6a layers + your personas, Windows", dict(files=dict(FULL, **{"layers.json": json.dumps(LAYERS), "user_styles.json": json.dumps(USER_STYLES)}))),
    ("6b layers + your personas, Mac", dict(files=dict(FULL, **{"layers.json": json.dumps(LAYERS), "user_styles.json": json.dumps(USER_STYLES),
                                                                "RES/reaper-kb.ini": "KEY 1 65 40001 0\n"}), os_name="macOS-arm64")),
    # 7. toolbars: a stale ReaPersona toolbar, one of yours in Ableton's slot, Logic's .ReaperMenu from its theme pack, Cubase's missing
    ("7 toolbars", dict(files=dict(FULL, **{"RES/reaper-menu.ini": MENU, "toolbars/CFLogic_Toolbar1.ReaperMenu": TOOLBAR_FILE,
                                            "toolbars/CFLogic_PianoRollToolbar.ReaperMenu": TOOLBAR_FILE.replace("CF Logic", "CF piano")}))),
]


# ---------------------------------------------------------------- install_shortcuts.py on its own (round 1, B2)
def check_python_alone(work):
    res, here = make_res(work, "py_alone", dict(FULL))
    r = subprocess.run([sys.executable, os.path.join(here, "install_shortcuts.py"), "--self-test"], capture_output=True, text=True)
    assert r.returncode == 0 and "self-test ok" in r.stdout, "--self-test: " + r.stdout + r.stderr
    status = os.path.join(here, "last_install.txt")

    def after(mod, *extra):
        started = []
        mod.relaunch = lambda exe, argv, st: started.append(exe)
        code = mod.after_reaper_quits(["install_shortcuts.py", "--after-reaper-quits", "--relaunch", "REAPER-EXE"] + list(extra))
        return code, started, read(status)

    # a failure inside the install (an assert, say): written down, and REAPER started again
    mod = load_py(here)
    mod.run = lambda **kw: (_ for _ in ()).throw(AssertionError("broken helper"))
    code, started, text = after(mod)
    assert code == 0 and started == ["REAPER-EXE"] and "not installed: AssertionError: broken helper" in text, text
    # a failure while waiting for REAPER to close: the same
    mod = load_py(here)
    mod.reaper_running = lambda: (_ for _ in ()).throw(OSError("no tasklist"))
    code, started, text = after(mod)
    assert started == ["REAPER-EXE"] and "OSError: no tasklist" in text, text
    # the relaunch itself failing: noted after the result
    mod = load_py(here)
    mod.relaunch = None
    mod.run = lambda **kw: print("installed 0 shortcut(s)")
    mod.after_reaper_quits(["x", "--after-reaper-quits", "--relaunch", "REAPER-EXE"])
    text = read(status)
    assert text.startswith("installed 0 shortcut(s)") and "REAPER didn't start again" in text, text
    # the real install: its summary is what the window reads
    code, started, text = after(load_py(here))
    assert started == ["REAPER-EXE"] and re.search(r"installed \d+ shortcut", text), text
    # the quit was cancelled and REAPER is still open a while later: nothing installed, REAPER not started again
    cancel = os.path.join(here, "install_cancelled")
    open(cancel, "w").write("x")
    os.remove(status)
    mod = load_py(here)
    mod.reaper_running, mod.CANCEL_GRACE = (lambda: True), 0.6
    code, started, text = after(mod)
    assert code == 1 and started == [] and text is None and not os.path.exists(cancel)
    # "cancelled", but REAPER was only slow to quit and is gone now (round 2, N6): installed and started again anyway
    open(cancel, "w").write("x")
    code, started, text = after(load_py(here))
    assert code == 0 and started == ["REAPER-EXE"] and re.search(r"installed \d+ shortcut", text) and not os.path.exists(cancel), text

    def running_for(n):  # (a REAPER that answers "running" n more times, then is gone: as one finishing its quit)
        left = [n]

        def running():
            left[0] -= 1
            return left[0] >= 0
        return running
    # ... the same through the grace loop itself (round 3, code-health 8): still running at the first two looks, then gone
    open(cancel, "w").write("x")
    mod = load_py(here)
    mod.reaper_running = running_for(2)
    code, started, text = after(mod)
    assert code == 0 and started == ["REAPER-EXE"] and re.search(r"installed \d+ shortcut", text), text
    # a save prompt left open (round 3, L5): waited for while REAPER is there, then installed and started again; only a long limit ends it
    mod = load_py(here)
    assert mod.WAIT_LIMIT >= 30 * 60
    mod.reaper_running = running_for(4)
    code, started, text = after(mod)
    assert code == 0 and started == ["REAPER-EXE"] and re.search(r"installed \d+ shortcut", text), text
    mod = load_py(here)
    mod.reaper_running, mod.WAIT_LIMIT = (lambda: True), 0.6
    code, started, text = after(mod)
    assert code == 1 and started == [] and text.startswith("REAPER didn't close"), text  # (REAPER is still open: nothing to start)
    # the terminal route refuses while REAPER runs, before anything waiting is merged in (round 3, code-health 8)
    os.makedirs(os.path.join(here, "pending"), exist_ok=True)
    open(os.path.join(here, "pending", "prefs.json"), "w").write('{"undomaxmem": "512"}')
    ini_before = read(os.path.join(res, "reaper.ini"))
    mod = load_py(here)
    mod.reaper_running = lambda: True
    try:
        mod.install_now(["install_shortcuts.py", "--apply-setup"])
        assert False, "install_now ran with REAPER open"
    except SystemExit as e:
        assert "Close REAPER first" in str(e), e
    assert read(os.path.join(res, "reaper.ini")) == ini_before and os.path.exists(os.path.join(here, "pending", "prefs.json")), "nothing merged"
    # the terminal route (a Flatpak REAPER, round 2 B1): --apply-setup puts in what waits, then installs
    os.makedirs(os.path.join(here, "pending"), exist_ok=True)
    open(os.path.join(here, "pending", "prefs.json"), "w").write('{"undomaxmem": "512"}')
    open(os.path.join(here, "pending", "reaper-mouse.ini"), "w").write("[MM_CTX_ITEM]\nmm_0=1 m\n")
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        load_py(here).install_now(["install_shortcuts.py", "--apply-setup"])
    text = out.getvalue()
    assert "took in reaper-mouse.ini" in text and "set 1 of REAPER's preferences" in text and re.search(r"installed \d+ shortcut", text), text
    assert "undomaxmem=512" in read(os.path.join(res, "reaper.ini")) and "mm_0=1 m" in read(os.path.join(res, "reaper-mouse.ini"))
    assert not os.listdir(os.path.join(here, "pending")), "pending/ emptied"
    # ... and --remove --apply-prefs: your preferences back, ReaPersona's window set out, its keys out
    open(os.path.join(here, "pending", "prefs.json"), "w").write('{"undomaxmem": "256"}')
    open(os.path.join(res, "reaper-screensets.ini"), "w").write("[sset1]\nname=Mine\n[sset2]\nname=ReaPersona: windows\nmask=1\n")
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        load_py(here).install_now(["install_shortcuts.py", "--remove", "--apply-prefs"])
    text = out.getvalue()
    assert "set 1 of REAPER's preferences" in text and "window set out" in text and "removed ReaPersona" in text, text
    assert "undomaxmem=256" in read(os.path.join(res, "reaper.ini")) and "ReaPersona" not in read(os.path.join(res, "reaper-screensets.ini"))
    assert "# ReaPersona" not in read(os.path.join(res, "reaper-kb.ini")), "its keys out"
    # outside a resource folder it refuses, as before
    loose = os.path.join(work, "loose")
    os.makedirs(loose)
    shutil.copy2(os.path.join(SRC, "install_shortcuts.py"), loose)
    r = subprocess.run([sys.executable, os.path.join(loose, "install_shortcuts.py"), "--self-test"], capture_output=True, text=True, cwd=loose)
    assert r.returncode != 0 and "resource folder" in r.stderr, r.stderr


def main():
    work = tempfile.mkdtemp(prefix="reapersona-installers-")
    failed = 0
    try:
        try:
            check_python_alone(work)
            print("ok    install_shortcuts.py: --self-test, the post-quit install writes its result and restarts REAPER whatever fails,"
                  " a 'cancelled' quit that did close, a long save prompt, the terminal route (--apply-setup, --remove --apply-prefs,"
                  " refused while REAPER runs)")
        except AssertionError as e:
            failed += 1
            print("FAIL  install_shortcuts.py on its own: %s" % e)
        for case, kw in CASES:
            try:
                diffs, kb = parity(work, case, **kw)
            except Exception as e:  # (one side crashed: that's a difference too)
                diffs, kb = ["%s: %s" % (type(e).__name__, e)], ""
            if diffs:
                failed += 1
                print("FAIL  %s\n    %s" % (case, "\n    ".join(diffs)))
            else:
                print("ok    %s (%d keymap lines, the same from both)" % (case, kb.count("\n")))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if failed:
        sys.exit("%d check(s) failed" % failed)
    print("all installer checks passed")


if __name__ == "__main__":
    main()
