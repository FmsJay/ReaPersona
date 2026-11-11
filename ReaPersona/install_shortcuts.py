"""ReaPersona: write each style's shortcuts into REAPER's keymap. Run with REAPER CLOSED (REAPER reads reaper-kb.ini at start).
Only lines tagged '# ReaPersona' are added or replaced, and a dated backup is made first.
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
import json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
RES = HERE
while RES and not os.path.exists(os.path.join(RES, "reaper-kb.ini")) and os.path.dirname(RES) != RES:  # (the resource path is the first
    RES = os.path.dirname(RES)                                                                    # folder up with reaper-kb.ini)
KB = os.path.join(RES, "reaper-kb.ini")
FALLBACK = os.path.join(HERE, "midi_fallback.json")
DEFAULTS = os.path.join(HERE, "midi_defaults.json")  # key -> MIDI editor command REAPER binds it to by default (picker > Check)
TAG = "# ReaPersona"
OLD_TAG = "# DAW Styles"  # (lines the old name wrote, before REAPER rewrote their comments)
MIDI = 32060

VIRT, SHIFT, CTRL, ALT = 1, 4, 8, 16
EXT = 32768  # (extended keys: arrows, Home/End, PgUp/PgDn, Insert/Delete)
NAMED = {"Space": 32, "Enter": 13, "Backspace": 8, "Tab": 9, "Esc": 27,
         "Left": EXT + 37, "Up": EXT + 38, "Right": EXT + 39, "Down": EXT + 40,
         "Home": EXT + 36, "End": EXT + 35, "PgUp": EXT + 33, "PgDn": EXT + 34, "Insert": EXT + 45, "Delete": EXT + 46,
         "Num*": 106, "Num+": 107, "Num-": 109, "Num.": 110, "Num/": 111}
NAMED.update({"F%d" % i: 111 + i for i in range(1, 13)})
NAMED.update({"Num%d" % i: 96 + i for i in range(10)})
OEM = {"?": 191, ";": 186, "=": 187, "+": 187, ",": 188, "-": 189, ".": 190, "/": 191, "`": 192, "[": 219, "\\": 220, "]": 221, "'": 222}


WHEEL = {"Mousewheel": (255, 248), "Ctrl+Alt+Mousewheel": (255, 251)}  # (as REAPER writes them; other wheel combos aren't needed yet)


def encode(spec):
    """'Ctrl+Shift+L' -> (modifier flags, key code), as reaper-kb.ini writes them. Pure."""
    if spec in WHEEL:
        return WHEEL[spec]
    if spec.endswith("+"):  # ("+", "Num+", "Ctrl++": the key itself ends in a plus)
        rest = spec[:-1]
        cut = rest.rfind("+")
        key, mods = rest[cut + 1:] + "+", [p for p in rest[:max(cut, 0)].split("+") if p]
    else:
        parts = spec.split("+")
        key, mods = parts[-1], [p for p in parts[:-1] if p]
    flags = 0
    for m in mods:
        flags |= {"Shift": SHIFT, "Ctrl": CTRL, "Alt": ALT}[m]
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
    open(path, "wb").write(("\n".join(out) + "\n").replace("\n", eol).encode("utf-8", errors="surrogateescape"))


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
    shutil.copy2(menu, menu + ".before-reapersona-" + time.strftime("%Y%m%d-%H%M%S"))
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


def run(remove=False, no_midi=False):
    if b"reaper.exe" in subprocess.run(["tasklist", "/FI", "IMAGENAME eq reaper.exe"], capture_output=True).stdout.lower():
        sys.exit("Close REAPER first: it reads its keymap only when it starts.")
    raw = open(KB, "rb").read()
    eol = "\r\n" if b"\r\n" in raw else "\n"
    lines = raw.decode("utf-8", errors="surrogateescape").replace("\r\n", "\n").split("\n")
    backup = KB + ".before-reapersona-" + time.strftime("%Y%m%d-%H%M%S")
    shutil.copy2(KB, backup)
    scripts = json.load(open(os.path.join(HERE, "scripts.json"), encoding="utf-8")) if os.path.exists(os.path.join(HERE, "scripts.json")) else {}
    # (REAPER rewrites reaper-kb.ini with its own comments when it saves it, so the tag doesn't survive: a line is also ours when it
    # binds a style's key in that style's layer, or a MIDI editor key to a ReaPersona MIDI key script. Your own keys in a layer stay.)
    style_keys = {(str(f), str(k), str(int(st.get("alt", 0)))) for st in load_styles() if 1 <= int(st.get("alt", 0)) <= 16
                  for f, k in (encode(x[0]) for x in st.get("keys", []))}
    midi_cmds = set(scripts.get("midi", {}).values())

    def ours(line):
        if TAG in line or OLD_TAG in line:
            return True
        q = line.split()
        if len(q) < 5 or q[0] != "KEY":
            return False
        if q[4] == str(MIDI):
            return q[3] in midi_cmds or "MIDI key" in line and ("Script: ReaPersona" in line or "Script: DAW Styles" in line)
        return (q[1], q[2], q[4]) in style_keys
    kept = [l for l in lines if not ours(l)]
    while kept and kept[-1] == "":
        kept.pop()
    if os.path.exists(FALLBACK):  # (your own MIDI editor lines a previous install moved aside)
        kept += [v["line"] for v in json.load(open(FALLBACK, encoding="utf-8")).values() if v.get("line") and not ours(v["line"])]
        os.remove(FALLBACK)
    added, warnings = 0, []
    if not remove:
        midi_specs = {}
        for st in load_styles():
            alt = int(st.get("alt", 0))
            for spec, cmd, what in st.get("keys", []) if 1 <= alt <= 16 else []:
                if isinstance(cmd, str) and cmd.startswith("MAIN:"):
                    cmd = main_command(kept, cmd[5:], {"Ctrl+Z": 40029, "Ctrl+Shift+Z": 40030}.get(cmd[5:], 0))
                if isinstance(cmd, str) and cmd.startswith("script:"):
                    cmd = scripts.get("main", {}).get(cmd[7:])
                    if not cmd:
                        warnings.append("%s %s: open the ReaPersona picker once first (registers its actions)" % (st["name"], spec)); continue
                f, k = encode(spec)
                kept.append("KEY %d %d %s %d\t\t %s : %s : %s : %s" % (f, k, cmd, alt, TAG, st["name"], spec, what))
                added += 1
            for mk in st.get("midi_keys", []):
                midi_specs.setdefault(mk[0], []).append(st["name"])
        fallback = {}
        defaults = json.load(open(DEFAULTS, encoding="utf-8")) if os.path.exists(DEFAULTS) else None
        if no_midi or defaults is None:  # (without REAPER's own MIDI editor defaults, a My REAPER key would lose what it did)
            if not no_midi:
                warnings.append("MIDI editor keys: no midi_defaults.json yet (open REAPER, picker > Check), so they weren't installed")
            midi_specs = {}
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
        json.dump(fallback, open(FALLBACK, "w", encoding="utf-8"), indent=1)
    open(KB, "wb").write(("\n".join(kept) + "\n").replace("\n", eol).encode("utf-8", errors="surrogateescape"))
    tb = install_toolbars(load_styles(), remove, warnings)
    print("%s %d toolbar(s)" % ("removed ReaPersona toolbars;" if remove else "wrote", tb))
    for w in warnings:
        print("skipped:", w)
    print("%s %d shortcut(s); backup: %s" % ("removed ReaPersona," if remove else "installed", added, backup))


if __name__ == "__main__":
    assert encode("Ctrl+Shift+L") == (13, 76) and encode("Space") == (1, 32) and encode("Ctrl+,") == (9, 188)
    assert encode("-") == (0, 45) and encode("Alt+'") == (17, 222) and encode("Left") == (1, EXT + 37) and encode("Shift+4") == (5, 52)
    assert encode("Num3") == (1, 99) and encode("F12") == (1, 123) and encode("+") == (0, 43) and encode("Ctrl+-") == (9, 189)
    assert encode("Shift+\\") == (5, 220) and encode("Shift+Num*") == (5, 106)
    run(remove="--remove" in sys.argv, no_midi="--no-midi" in sys.argv)
