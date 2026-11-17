"""ReaPersona: write each style's shortcuts into REAPER's keymap. Run with REAPER CLOSED (REAPER reads reaper-kb.ini at start).
Only ReaPersona's own lines are added or replaced (installed.json lists the ones the last install wrote; before that, lines tagged
'# ReaPersona'), and a dated backup is made first.
- Arrange keys go in a shortcut layer per style (Main alt-N); your Main section is never touched.
- MIDI editor keys: the MIDI editor has no layers, so each key any style uses there is bound to a small ReaPersona script that runs
  the style's action, or what the key did in your keymap when the style in use has none. Your own line for that key is moved into
  midi_fallback.json (and put back by --remove or the next install).
- Keys that run a ReaPersona action ('script:...') and the MIDI key scripts need their command ids: open the ReaPersona picker once
  first (it registers them and writes scripts.json).
    python install_shortcuts.py            install or update every style (styles.json and user_styles.json)
    python install_shortcuts.py --remove   take the ReaPersona lines out again
    python install_shortcuts.py --no-midi  arrange layers only
"""
import json, os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
RES = HERE  # (the resource path: the first folder up with REAPER's reaper.ini, or its reaper-kb.ini; a new REAPER may not have the keymap yet)
while not any(os.path.exists(os.path.join(RES, f)) for f in ("reaper.ini", "reaper-kb.ini")) and os.path.dirname(RES) != RES:
    RES = os.path.dirname(RES)
if not any(os.path.exists(os.path.join(RES, f)) for f in ("reaper.ini", "reaper-kb.ini")):
    sys.exit("This has to sit inside REAPER's resource folder (Scripts/ReaPersona): no reaper.ini above " + HERE)
KB = os.path.join(RES, "reaper-kb.ini")
FALLBACK = os.path.join(HERE, "midi_fallback.json")
DEFAULTS = os.path.join(HERE, "midi_defaults.json")  # key -> MIDI editor command REAPER binds it to by default (picker > Check)
MANIFEST = os.path.join(HERE, "installed.json")  # the exact lines the last install wrote ("flags key cmd section")
TAG = "# ReaPersona"
OLD_TAG = "# DAW Styles"  # (lines the old name wrote, before REAPER rewrote their comments)
MIDI = 32060

VIRT, SHIFT, CTRL, ALT, WIN = 1, 4, 8, 16, 32  # (WIN: the Windows key; Control on a Mac)
EXT = 32768  # (extended keys: arrows, Home/End, PgUp/PgDn, Insert/Delete)
NAMED = {"Space": 32, "Enter": 13, "Backspace": 8, "Tab": 9, "Esc": 27,
         "Left": EXT + 37, "Up": EXT + 38, "Right": EXT + 39, "Down": EXT + 40,
         "Home": EXT + 36, "End": EXT + 35, "PgUp": EXT + 33, "PgDn": EXT + 34, "Insert": EXT + 45, "Delete": EXT + 46,
         "Num*": 106, "Num+": 107, "Num-": 109, "Num.": 110, "Num/": 111, "NumEnter": EXT + 13}
NAMED.update({"F%d" % i: 111 + i for i in range(1, 13)})
NAMED.update({"Num%d" % i: 96 + i for i in range(10)})
OEM = {"?": 191, ";": 186, "=": 187, "+": 187, ",": 188, "-": 189, ".": 190, "/": 191, "`": 192, "[": 219, "\\": 220, "]": 221, "'": 222}


# The mouse wheel (5.9.5, as reapersona_core.lua's M.wheel_code): flags 255, key = 248 (wheel) or 216 (horizontal wheel) + Ctrl 1, Alt 2,
# Shift 4, as REAPER writes them (248 Mousewheel, 251 Ctrl+Alt+Mousewheel, 218 Alt+HorizWheel). No code for the Windows key.
WHEELS, WHEEL_MODS = {"Mousewheel": 248, "HorizWheel": 216}, {"Ctrl": 1, "Alt": 2, "Shift": 4}


def wheel_code(spec):
    """'Shift+Mousewheel' (modifiers in any order) -> (255, 252), or None. Pure."""
    parts = spec.split("+")
    if parts[-1] not in WHEELS:
        return None
    add = 0
    for m in parts[:-1]:
        if m not in WHEEL_MODS:
            raise ValueError("no wheel shortcut with " + m + ": " + spec)
        add |= WHEEL_MODS[m]
    return 255, WHEELS[parts[-1]] + add


def encode(spec):
    """'Ctrl+Shift+L' -> (modifier flags, key code), as reaper-kb.ini writes them. Pure."""
    wheel = wheel_code(spec)
    if wheel:
        return wheel
    if spec.endswith("+"):  # ("+", "Num+", "Ctrl++": the key itself ends in a plus)
        rest = spec[:-1]
        cut = rest.rfind("+")
        key, mods = rest[cut + 1:] + "+", [p for p in rest[:max(cut, 0)].split("+") if p]
    else:
        parts = spec.split("+")
        key, mods = parts[-1], [p for p in parts[:-1] if p]
    flags = 0
    for m in mods:
        flags |= {"Shift": SHIFT, "Ctrl": CTRL, "Alt": ALT, "Win": WIN}[m]
    if key in NAMED:
        return VIRT | flags, NAMED[key]
    if len(key) == 1 and key.isalpha():
        return VIRT | flags, ord(key.upper())
    if len(key) == 1 and key.isdigit():
        return VIRT | flags, ord(key)
    if len(key) == 1 and key in OEM:
        if flags == 0:
            return 0, ord(key)  # (unmodified punctuation goes in as the character, as REAPER itself writes '-' and '=')
        return VIRT | flags, OEM[key]
    raise ValueError("unknown key: " + spec)


MAC = sys.platform == "darwin"


def for_os(spec):
    """A key for one system only is written "mac:Alt+Enter" / "win:Ctrl+Enter". -> the key for this system, or None."""
    if spec.startswith("mac:"):
        return spec[4:] if MAC else None
    if spec.startswith("win:"):
        return None if MAC else spec[4:]
    return spec


def main_command(lines, spec, fallback):
    """What the Main section runs on this key now, so a style's Undo/Redo is still StudioSync's when it overrides them."""
    f, k = encode(spec)
    for l in lines:
        p = l.split()
        if len(p) >= 5 and p[0] == "KEY" and p[1] == str(f) and p[2] == str(k) and p[4] == "0" and p[3] != "0":
            return p[3]
    return str(fallback)


def load_styles():
    styles = json.load(open(os.path.join(HERE, "styles.json"), encoding="utf-8"))["styles"]
    user = os.path.join(HERE, "user_styles.json")
    if os.path.exists(user):
        styles += json.load(open(user, encoding="utf-8")).get("styles", [])
    return styles


def read_ini(path):
    """-> (eol, [(header or None, [lines])]) keeping order and text exactly."""
    raw = open(path, "rb").read() if os.path.exists(path) else b""
    eol = "\r\n" if b"\r\n" in raw else "\n"
    secs = [(None, [])]
    for l in raw.decode("utf-8", errors="surrogateescape").replace("\r\n", "\n").split("\n"):
        if l.startswith("[") and l.rstrip().endswith("]"):
            secs.append((l.strip(), []))
        else:
            secs[-1][1].append(l)
    return eol, secs


def write_ini(path, eol, secs):
    out = []
    for h, body in secs:
        if h is not None:
            out.append(h)
        out += body
    while out and out[-1] == "":
        out.pop()
    write_atomic(path, ("\n".join(out) + "\n").replace("\n", eol).encode("utf-8", errors="surrogateescape"))


def toolbar_lines(st, file_key="toolbar_file", list_key="toolbar", label=""):
    """A toolbar section's body for a style: from a .ReaperMenu in toolbars/ (its first section) or the style's own list."""
    if st.get(file_key):
        body, on = [], False
        for l in open(os.path.join(HERE, "toolbars", st[file_key]), encoding="utf-8", errors="surrogateescape").read().splitlines():
            if l.startswith("["):
                if on:
                    break
                on = True
            elif on and l and not l.startswith("title="):
                body.append(l)
    else:
        body = []
        for i, it in enumerate(st[list_key]):
            if it == -1:
                body.append("item_%d=-1" % i)
                continue
            if len(it) > 2:
                body.append("icon_%d=%s" % (i, it[2]))
            body.append("item_%d=%s %s" % (i, it[0], it[1]))
    return body + ["title=ReaPersona: " + st["name"] + label, ""]


def install_toolbars(styles, remove, warnings):
    """Each style's toolbar into reaper-menu.ini as [Floating toolbar <toolbar_slot>] (the style switches it in place of your main
    toolbar), and its piano roll toolbar as [Floating MIDI toolbar <midi_toolbar_slot>]. A slot holding a toolbar that isn't
    ReaPersona's is left alone. -> how many written"""
    menu = os.path.join(RES, "reaper-menu.ini")
    eol, secs = read_ini(menu)
    if os.path.exists(menu):
        backup_of(menu)
    ours = lambda body: any(l.startswith("title=ReaPersona") or l.startswith("title=DAW Styles") for l in body)
    secs = [s for s in secs if not (s[0] and s[0].startswith("[Floating") and ours(s[1]))]
    n = 0
    for st in [] if remove else styles:
        for slot_key, file_key, list_key, head, label in (("toolbar_slot", "toolbar_file", "toolbar", "[Floating toolbar %d]", ""),
                                                          ("midi_toolbar_slot", "midi_toolbar_file", "midi_toolbar", "[Floating MIDI toolbar %d]", " piano roll")):
            slot = st.get(slot_key)
            if not slot or not (st.get(file_key) or st.get(list_key)):
                continue
            h = head % slot
            if st.get(file_key) and not os.path.exists(os.path.join(HERE, "toolbars", st[file_key])):
                warnings.append("%s: toolbars/%s isn't here (from its theme pack), so it keeps your toolbar" % (st["name"], st[file_key])); continue
            if any(s[0] == h and any(l.startswith("item_") for l in s[1]) for s in secs):
                warnings.append("%s already holds one of your toolbars: %s's not written" % (h, st["name"])); continue
            secs = [s for s in secs if s[0] != h] + [(h, toolbar_lines(st, file_key, list_key, label))]
            n += 1
    write_ini(menu, eol, secs)
    return n


def reaper_running():
    """Is the REAPER this keymap belongs to running? (Another REAPER install on the computer doesn't count, where that can be told.)"""
    # (each running REAPER's resource folder: the -cfgfile ini's folder; else its program folder when that has a reaper.ini
    # (portable); else the user profile's REAPER folder. It's ours when that's RES.)
    if os.name == "nt":
        listed = b"reaper.exe" in subprocess.run(["tasklist", "/FI", "IMAGENAME eq reaper.exe"], capture_output=True).stdout.lower()
        if not listed:
            return False
        try:
            out = subprocess.run(["powershell", "-NoProfile", "-Command", "[Console]::OutputEncoding=[Text.Encoding]::UTF8; "
                                  "Get-CimInstance Win32_Process -Filter \"Name='reaper.exe'\" | ForEach-Object { $_.ExecutablePath + '|' + $_.CommandLine }"],
                                 capture_output=True, encoding="utf-8", errors="replace")
        except OSError:  # (no PowerShell: any REAPER counts)
            return True
        here = os.path.normcase(os.path.abspath(RES))
        if out.returncode != 0 or not out.stdout.strip():
            return True
        for line in out.stdout.splitlines():
            exe, _, cmd = line.strip().partition("|")
            if not exe:  # (a REAPER this can't look into, an elevated one say: it may be ours)
                return True
            m = re.search(r'-cfgfile"?\s+"?([^"]+?\.ini)"?(\s|$)', cmd, re.I)
            if m:
                rdir = os.path.dirname(os.path.abspath(m.group(1)))
            elif os.path.exists(os.path.join(os.path.dirname(exe), "reaper.ini")):
                rdir = os.path.dirname(exe)
            else:
                rdir = os.path.join(os.environ.get("APPDATA", ""), "REAPER")
            if os.path.normcase(os.path.abspath(rdir)) == here:
                return True
        return False
    return subprocess.run(["/usr/bin/pgrep", "-xi", "reaper"], capture_output=True).returncode == 0


def backup_of(path):
    """A dated copy of path. The first one (your keymap before ReaPersona) and the newest 4 are kept. -> its name"""
    stamp = path + ".before-reapersona-" + time.strftime("%Y%m%d-%H%M%S")
    name, n = stamp, 1
    while os.path.exists(name):
        n += 1
        name = "%s-%d" % (stamp, n)
    shutil.copy2(path, name)
    folder, base = os.path.split(path)
    old = sorted(f for f in os.listdir(folder) if f.startswith(base + ".before-reapersona-"))
    for f in old[1:-4]:  # (the oldest is the one from before ReaPersona ever changed anything: never removed)
        try:
            os.remove(os.path.join(folder, f))
        except OSError:
            pass
    return name


def write_atomic(path, data):
    """Through a temp file and os.replace: a crash never leaves half a file."""
    with open(path + ".tmp", "wb") as f:
        f.write(data)
    os.replace(path + ".tmp", path)


def key_of(line):
    """'KEY f k cmd sec ...' -> 'f k cmd sec', or None."""
    q = line.split()
    return " ".join(q[1:5]) if len(q) >= 5 and q[0] == "KEY" else None


# ---------------------------------------------------------------- your setup from your other computers (5.11, the advanced sync)
# Files REAPER rewrites when it quits wait in ReaPersona/pending until it's closed: they're merged in here, never written over. The keymap
# keeps every line of this computer's and takes the other computer's for the same key or the same script/custom action id (so this
# computer's ReaPack script registrations and ReaPersona's lines stay); the menus, mouse modifiers and window sets take the other computer's
# section where both have it and keep the rest; prefs.json goes into reaper.ini's [REAPER] section.
PENDING = os.path.join(HERE, "pending")


def kb_slot(line):
    p = line.split()
    if len(p) >= 5 and p[0] == "KEY":
        return "KEY %s %s %s" % (p[1], p[2], p[4])
    if len(p) >= 4 and p[0] == "SCR":
        return "SCR %s %s" % (p[2], p[3])
    if len(p) >= 4 and p[0] == "ACT":
        return "ACT %s %s" % (p[2], p[3])
    return None


def kb_takeable(line, mine_scripts):
    """Whether one of the other computer's keymap lines may come in here. Pure. Not taken: keys on ReaPersona's layers (alt-1..16:
    each computer installs its own), "disabled" keys (command 0: REAPER writes those when a key's script isn't known there), and keys
    for a script this computer hasn't registered (scripts get a different id when they live in another folder, so the other
    computer's id runs nothing here and REAPER drops the key: that turned Undo off on the laptop, 5.12.1)."""
    p = line.split()
    if p[:1] != ["KEY"] or len(p) < 5:
        return True
    cmd, sec = p[3], p[4]
    if sec.isdigit() and 1 <= int(sec) <= 16 or cmd == "0":
        return False
    return not cmd.lstrip("_").startswith("RS") or cmd.lstrip("_") in mine_scripts


def merge_kb(mine, theirs):
    """This computer's keymap with the other computer's lines taken in. Pure."""
    mine_scripts = {l.split()[3] for l in mine.splitlines() if l.startswith("SCR ") and len(l.split()) > 3}
    take = [l for l in theirs.splitlines() if kb_slot(l) and not l.startswith("SCR ") and kb_takeable(l, mine_scripts)]
    slots = {kb_slot(l) for l in take}
    keep = [l for l in mine.splitlines() if not (kb_slot(l) and kb_slot(l) in slots)]
    while keep and keep[-1].strip() == "":
        keep.pop()
    return "\n".join(keep + take) + "\n"


def ini_sections(text):
    order, secs, cur = [], {}, None
    for line in text.splitlines():
        m = re.match(r"^\[(.+)\]\s*$", line)
        if m:
            cur = m.group(1)
            if cur not in secs:
                secs[cur] = []
                order.append(cur)
        elif cur is not None and line.strip():
            secs[cur].append(line)
    return order, secs


def merge_ini(mine, theirs):
    """This computer's ini file with the other computer's sections taken in whole. Pure."""
    order, secs = ini_sections(mine)
    t_order, t_secs = ini_sections(theirs)
    for name in t_order:
        if name not in secs:
            order.append(name)
        secs[name] = t_secs[name]
    return "".join("[%s]\n%s" % (n, "".join(l + "\n" for l in secs[n])) for n in order)


def set_prefs(text, prefs):
    """reaper.ini with these [REAPER] keys set (the section header in any case). Pure."""
    lines = text.splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip().lower() == "[reaper]"), None)
    if start is None:
        lines = ["[REAPER]"] + lines
        start = 0
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    left = dict(prefs)
    for i in range(start + 1, end):
        k = lines[i].split("=", 1)[0]
        if "=" in lines[i] and k in left:
            lines[i] = "%s=%s" % (k, left.pop(k))
    lines[end:end] = ["%s=%s" % (k, v) for k, v in left.items()]
    return "\n".join(lines) + "\n"


def apply_setup():
    """What waits in ReaPersona/pending, merged in (REAPER closed). -> lines saying what was done"""
    done = []
    if not os.path.isdir(PENDING):
        return done
    stamp = time.strftime("%Y%m%d-%H%M%S")
    for name in ("reaper-kb.ini", "reaper-mouse.ini", "reaper-menu.ini", "reaper-screensets.ini"):
        src = os.path.join(PENDING, name)
        if not os.path.exists(src):
            continue
        dst = os.path.join(RES, name)
        theirs = open(src, encoding="utf-8", errors="surrogateescape").read()
        mine = open(dst, encoding="utf-8", errors="surrogateescape").read() if os.path.exists(dst) else ""
        if os.path.exists(dst):
            shutil.copy2(dst, dst + ".before-reapersona-sync-" + stamp)
        merged = merge_kb(mine, theirs) if name == "reaper-kb.ini" else merge_ini(mine, theirs)
        eol = "\r\n" if "\r\n" in mine else "\n"
        write_atomic(dst, merged.replace("\n", eol).encode("utf-8", errors="surrogateescape"))
        os.remove(src)
        done.append("took in %s from your other computers (yours backed up first)" % name)
    pf = os.path.join(PENDING, "prefs.json")
    if os.path.exists(pf):
        prefs = json.load(open(pf, encoding="utf-8"))
        ini = os.path.join(RES, "reaper.ini")
        text = open(ini, encoding="utf-8", errors="surrogateescape").read() if os.path.exists(ini) else ""
        eol = "\r\n" if "\r\n" in text else "\n"
        write_atomic(ini, set_prefs(text, {str(k): str(v) for k, v in prefs.items()}).replace("\n", eol).encode("utf-8", errors="surrogateescape"))
        os.remove(pf)
        done.append("set %d of REAPER's preferences from your other computers" % len(prefs))
    return done


def run(remove=False, no_midi=False):
    if reaper_running():
        sys.exit("Close REAPER first: it reads its keymap only when it starts.")
    scripts = json.load(open(os.path.join(HERE, "scripts.json"), encoding="utf-8")) if os.path.exists(os.path.join(HERE, "scripts.json")) else {}
    styles = load_styles()
    warnings = []

    # 1. Plan every line first, so a bad entry in a shared style is skipped with a warning before anything is changed.
    plan, midi_specs = [], {}  # plan: (flags, key, cmd or "MAIN:spec", alt, comment)
    for st in [] if remove else styles:
        alt = int(st.get("alt") or 0)
        for entry in st.get("keys", []) if 1 <= alt <= 16 else []:
            try:
                spec, cmd, what = entry
                spec = for_os(spec)
                if spec is None:
                    continue
                if isinstance(cmd, str) and cmd.startswith("script:"):
                    cmd = scripts.get("main", {}).get(cmd[7:])
                    if not cmd:
                        warnings.append("%s %s: open the ReaPersona picker once first (registers its actions)" % (st["name"], spec)); continue
                if isinstance(cmd, str) and cmd.startswith("MAIN:"):
                    encode(cmd[5:])
                elif not (isinstance(cmd, int) or (isinstance(cmd, str) and cmd and not any(c.isspace() for c in cmd))):
                    raise ValueError("bad command %r" % (cmd,))
                f, k = encode(spec)
                plan.append((f, k, cmd, alt, "%s : %s : %s : %s" % (TAG, st["name"], spec, what)))
            except (ValueError, KeyError, TypeError) as e:
                warnings.append("%s: skipped key %r (%s)" % (st.get("name"), entry, e))
        for mk in st.get("midi_keys", []):
            try:
                encode(mk[0])
                midi_specs.setdefault(mk[0], []).append(st["name"])
            except (ValueError, KeyError, TypeError, IndexError) as e:
                warnings.append("%s: skipped MIDI key %r (%s)" % (st.get("name"), mk, e))
    defaults = json.load(open(DEFAULTS, encoding="utf-8")) if os.path.exists(DEFAULTS) else None
    if no_midi or (defaults is None and not remove):  # (without REAPER's own MIDI editor defaults, a My REAPER key would lose what it did)
        if not no_midi:
            warnings.append("MIDI editor keys: no midi_defaults.json yet (open REAPER, picker > Check), so they weren't installed")
        midi_specs = {}
    old_fallback = json.load(open(FALLBACK, encoding="utf-8")) if os.path.exists(FALLBACK) else {}
    if not isinstance(old_fallback, dict):
        old_fallback = {}

    raw = open(KB, "rb").read() if os.path.exists(KB) else b""  # (a new REAPER may not have written its keymap yet)
    eol = "\r\n" if b"\r\n" in raw or (not raw and os.name == "nt") else "\n"
    lines = raw.decode("utf-8", errors="surrogateescape").replace("\r\n", "\n").split("\n")
    if raw:
        backup = backup_of(KB)
    else:
        backup = "(none: there was no keymap yet)"

    # 2. Which lines are ReaPersona's. REAPER rewrites reaper-kb.ini with its own comments, so the tag doesn't survive: installed.json
    # keeps the exact lines the last install wrote, and a line you changed since (another command) is yours. Without it (installs
    # before 5.2) a style's key in that style's layer counts as ours.
    manifest = json.load(open(MANIFEST, encoding="utf-8")).get("lines") if os.path.exists(MANIFEST) else None
    manifest = set(manifest) if isinstance(manifest, list) else None
    midi_cmds = set(scripts.get("midi", {}).values())
    midi_keys = set()
    for spec in set(midi_specs) | set(old_fallback):
        try:
            midi_keys.add("%d %d" % encode(spec))
        except (ValueError, KeyError, TypeError):
            pass

    def ours(line):
        if TAG in line or OLD_TAG in line:
            return True
        q = line.split()
        if len(q) < 5 or q[0] != "KEY":
            return False
        if q[4] == str(MIDI):  # (a "0 ... DISABLED DEFAULT" line on one of our MIDI keys: REAPER wrote it when a key script moved)
            return (q[3] in midi_cmds or "MIDI key" in line and ("Script: ReaPersona" in line or "Script: DAW Styles" in line)
                    or (q[3] == "0" and "%s %s" % (q[1], q[2]) in midi_keys))
        return manifest is not None and key_of(line) in manifest
    kept = [l for l in lines if not ours(l)]
    while kept and kept[-1] == "":
        kept.pop()
    kept += [v["line"] for v in old_fallback.values()  # (your own MIDI editor lines a previous install moved aside)
             if isinstance(v, dict) and v.get("line") and not ours(v["line"])]

    # 3. The new lines.
    added, written, fallback = 0, [], {}
    yours = {" ".join(l.split()[1:3] + l.split()[4:5]) for l in kept if key_of(l)}  # ("flags key section" of lines that stay)
    for f, k, cmd, alt, comment in plan:
        if "%d %d %d" % (f, k, alt) in yours:  # (you rebound this key in the style's layer: yours stays)
            continue
        if isinstance(cmd, str) and cmd.startswith("MAIN:"):
            cmd = main_command(kept, cmd[5:], {"Ctrl+Z": 40029, "Ctrl+Shift+Z": 40030}.get(cmd[5:], 0))
        kept.append("KEY %d %d %s %d\t\t %s" % (f, k, cmd, alt, comment))
        written.append("%d %d %s %d" % (f, k, cmd, alt))
        added += 1
    for spec in sorted(midi_specs):
        cmd = scripts.get("midi", {}).get(spec)
        if not cmd:
            warnings.append("MIDI %s: open the ReaPersona picker once first (registers the MIDI key scripts)" % spec); continue
        f, k = encode(spec)
        for l in list(kept):
            p = l.split()
            if len(p) >= 5 and p[0] == "KEY" and p[1] == str(f) and p[2] == str(k) and p[4] == str(MIDI) and not ours(l):
                fallback[spec] = {"cmd": p[3], "line": l}
                kept.remove(l)
        if spec not in fallback and spec in defaults:  # (REAPER's built-in binding: kb.ini only holds changes)
            fallback[spec] = {"cmd": str(defaults[spec])}
        kept.append("KEY %d %d %s %d\t\t %s : MIDI editor : %s : %s" % (f, k, cmd, MIDI, TAG, spec, ", ".join(midi_specs[spec])))
        added += 1

    # 4. Write: your moved MIDI editor lines first (midi_fallback.json), then the keymap, then the list of what was written.
    write_atomic(FALLBACK, json.dumps(fallback, indent=1).encode("utf-8"))
    write_atomic(KB, ("\n".join(kept) + "\n").replace("\n", eol).encode("utf-8", errors="surrogateescape"))
    write_atomic(MANIFEST, json.dumps({"lines": written}, indent=0).encode("utf-8"))
    tb = install_toolbars(styles, remove, warnings)
    print("%s %d toolbar(s)" % ("removed ReaPersona toolbars;" if remove else "wrote", tb))
    for w in warnings:
        print("skipped:", w)
    print("%s %d shortcut(s); backup: %s" % ("removed ReaPersona," if remove else "installed", added, backup))


if __name__ == "__main__":
    assert encode("Ctrl+Shift+L") == (13, 76) and encode("Space") == (1, 32) and encode("Ctrl+,") == (9, 188)
    assert encode("-") == (0, 45) and encode("Alt+'") == (17, 222) and encode("Left") == (1, EXT + 37) and encode("Shift+4") == (5, 52)
    assert encode("Num3") == (1, 99) and encode("F12") == (1, 123) and encode("+") == (0, 43) and encode("Ctrl+-") == (9, 189)
    assert encode("Shift+\\") == (5, 220) and encode("Shift+Num*") == (5, 106)
    assert encode("NumEnter") == (1, EXT + 13) and encode("Win+M") == (33, 77) and for_os("mac:Win+M") in (None, "Win+M")
    assert merge_kb("KEY 1 65 40001 0\nSCR 4 0 RSaa \"Custom: a\" a.lua\nKEY 1 66 40002 0\n", "KEY 1 65 40099 0\nACT 0 0 \"x\" \"y\" 1\n") == \
        "SCR 4 0 RSaa \"Custom: a\" a.lua\nKEY 1 66 40002 0\nKEY 1 65 40099 0\nACT 0 0 \"x\" \"y\" 1\n"
    # theirs: a script unknown here, a disabled key, a persona layer, a known script: only the known one is taken
    mine = "SCR 4 0 RSaa \"Custom: a\" a.lua\nKEY 9 90 _RSmine 0\n"
    assert merge_kb(mine, "KEY 9 90 _RSzz 0\nKEY 9 90 0 0\nKEY 1 70 40001 3\nKEY 1 71 _RSaa 0\n") == mine + "KEY 1 71 _RSaa 0\n"
    assert merge_ini("[a]\nx=1\n[b]\ny=2\n", "[b]\ny=3\n[c]\nz=4\n") == "[a]\nx=1\n[b]\ny=3\n[c]\nz=4\n"
    assert set_prefs("[reaper]\nfoo=1\nbar=2\n[x]\nq=1", {"bar": "5", "new": "7"}) == "[reaper]\nfoo=1\nbar=5\nnew=7\n[x]\nq=1\n"
    if "--help" in sys.argv or "-h" in sys.argv:
        sys.exit(__doc__)
    if "--after-reaper-quits" in sys.argv:
        # (the picker's one-button install, or with --remove its Remove ReaPersona: REAPER starts this, then quits; we wait, install or
        # remove, note the result and start REAPER again)
        exe = sys.argv[sys.argv.index("--relaunch") + 1] if "--relaunch" in sys.argv else None
        status = os.path.join(HERE, "last_install.txt")
        cancelled = os.path.join(HERE, "install_cancelled")
        give_up = time.time() + 180  # (3 minutes: REAPER may be asking whether to save)
        while reaper_running() and time.time() < give_up and not os.path.exists(cancelled):
            time.sleep(0.5)
        if os.path.exists(cancelled):  # (the picker saw the quit cancelled: nothing to do)
            os.remove(cancelled)
            sys.exit(1)
        if reaper_running():
            open(status, "w", encoding="utf-8").write("REAPER didn't close, so the shortcuts weren't installed.\n")
            sys.exit(1)
        import contextlib, io as _io
        out = _io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                if "--apply-setup" in sys.argv:  # (your setup from your other computers, waiting for REAPER to close: 5.11)
                    for line in apply_setup():
                        print(line)
                run(remove="--remove" in sys.argv, no_midi="--no-midi" in sys.argv)  # (--remove: Settings > Remove ReaPersona, review 5.9.4)
        except BaseException as e:  # (SystemExit included: whatever happened is written down for the picker)
            out.write("not installed: %s\n" % e)
        open(status, "w", encoding="utf-8").write(out.getvalue())
        projects = [sys.argv[i + 1] for i, a in enumerate(sys.argv[:-1]) if a == "--open"]  # (the projects that were open)
        cfg = sys.argv[sys.argv.index("--cfgfile") + 1] if "--cfgfile" in sys.argv else None  # (the same configuration again)
        if exe:
            args = ["-cfgfile", cfg] if cfg and os.path.exists(cfg) else []
            if exe.endswith(".app"):
                # (a Mac: open hands REAPER to LaunchServices and returns, so it's waited for, by its full path, in a session of its own. Started
                # and left as this script exited, it never brought REAPER back (5.8.3). And right after the quit, LaunchServices still lists the
                # REAPER going away: open "activated" that one, said 0, and nothing started (5.8.4). So: wait until it's gone from there too, then
                # open, and believe it only when a REAPER is running; once more if not. StudioSync's Mac test)
                def listed():
                    try:
                        return "ASN:" in subprocess.run(["/usr/bin/lsappinfo", "find", "bundleid=com.cockos.reaper"], capture_output=True,
                                                        text=True, timeout=5).stdout or reaper_running()  # (it prints the app's ASN while it's listed)
                    except Exception:
                        return reaper_running()
                gone_by = time.time() + 15
                while listed() and time.time() < gone_by:
                    time.sleep(0.5)
                time.sleep(1)
                note = "REAPER didn't start again: open it yourself"
                for _ in range(2):
                    try:
                        r = subprocess.run(["/usr/bin/open", "-a", exe] + projects + (["--args"] + args if args else []), capture_output=True,
                                           text=True, timeout=60, start_new_session=True)
                        if r.returncode != 0:
                            note = "REAPER didn't start again (open said %s: %s)" % (r.returncode, r.stderr.strip())
                    except Exception as e:
                        note = "REAPER didn't start again: %s" % e
                    up_by = time.time() + 15
                    while not reaper_running() and time.time() < up_by:
                        time.sleep(0.5)
                    if reaper_running():
                        note = "REAPER started again"
                        break
                open(status, "a", encoding="utf-8").write(note + "\n")
            elif os.name == "nt":
                subprocess.Popen([exe] + args + projects, close_fds=True,
                                 creationflags=getattr(subprocess, "DETACHED_PROCESS", 0) | getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0))
            else:
                # (Linux: this script's output is a pipe to the REAPER that just quit, and the new one, writing its first line there, was killed by
                # SIGPIPE before it showed: nothing inherited, a session of its own, and believed only once it runs; once more if not. Linux VM, 5.9.2)
                note = "REAPER didn't start again: open it yourself"
                for _ in range(2):
                    try:
                        subprocess.Popen([exe] + args + projects, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                         close_fds=True, start_new_session=True)
                    except Exception as e:
                        note = "REAPER didn't start again: %s" % e
                    up_by = time.time() + 15
                    while not reaper_running() and time.time() < up_by:
                        time.sleep(0.5)
                    if reaper_running():
                        note = "REAPER started again"
                        break
                open(status, "a", encoding="utf-8").write(note + "\n")
        sys.exit(0)
    run(remove="--remove" in sys.argv, no_midi="--no-midi" in sys.argv)
