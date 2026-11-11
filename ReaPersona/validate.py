"""ReaPersona: check styles.json before installing. Every key must encode, no key twice in one style's layer, every built-in command
id must exist (checked against an action list dumped from REAPER: actions_main.tsv / actions_midi.tsv, id<TAB>name, made by the
picker's Check button), every MIDI editor action name must exist, every theme must be in ColorThemes. Prints what to look at.
    python validate.py [--names]    (--names lists every key with the REAPER action it runs, to read through)
"""
import json, os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from install_shortcuts import encode, load_styles  # noqa: E402

THEMES = os.path.join(os.path.dirname(os.path.dirname(HERE)), "ColorThemes")


def table(name):
    p = os.path.join(HERE, name)
    if not os.path.exists(p):
        return None
    out = {}
    for l in open(p, encoding="utf-8", errors="replace"):
        if "\t" in l:
            i, n = l.rstrip("\n").split("\t", 1)
            out[i] = n
    return out


main, midi = table("actions_main.tsv"), table("actions_midi.tsv")
midi_names = set(midi.values()) if midi else None
problems = 0
for st in load_styles():
    seen = {}
    for spec, cmd, what in st.get("keys", []):
        try:
            encode(spec)
        except Exception as e:
            print("%s: %s" % (st["name"], e)); problems += 1
        if spec in seen:
            print("%s: %s twice (%s / %s)" % (st["name"], spec, seen[spec], what)); problems += 1
        seen[spec] = what
        name = "?"
        if isinstance(cmd, int):
            if main is not None:
                name = main.get(str(cmd))
                if name is None:
                    print("%s: %s -> %d is not a REAPER action" % (st["name"], spec, cmd)); problems += 1
        if "--names" in sys.argv:
            print("  %-12s %-16s %-55s | %s" % (st["id"], spec, str(cmd) + " " + str(name), what))
    mseen = set()
    for mk in st.get("midi_keys", []):
        encode(mk[0])
        if mk[0] in mseen:
            print("%s: MIDI %s twice" % (st["name"], mk[0])); problems += 1
        mseen.add(mk[0])
        for n in (mk[1] if isinstance(mk[1], list) else [mk[1]]):
            if midi_names is not None and isinstance(n, str) and not n.startswith("_") and n not in midi_names:
                print("%s: MIDI %s -> no MIDI editor action named %r" % (st["name"], mk[0], n)); problems += 1
    for f in st.get("feel", []):
        if f[0] == "toggle" and isinstance(f[1], int) and main is not None and str(f[1]) not in main:
            print("%s: feel toggle %d is not a REAPER action" % (st["name"], f[1])); problems += 1
    have = [th for th in [st.get("theme")] + st.get("themes", []) if th and os.path.exists(os.path.join(THEMES, th))]
    if not have:
        print("%s: none of its themes are in ColorThemes" % st["name"]); problems += 1
    elif st.get("theme") not in have:
        print("(%s: its theme isn't here; it'll use %s)" % (st["name"], have[0]))
if main is None or midi is None:
    print("(no action list yet: open the picker and press Check to dump REAPER's actions, then run this again)")
print("%d problem(s)" % problems)
sys.exit(1 if problems else 0)
