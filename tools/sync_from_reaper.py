"""Copy ReaPersona's files from a REAPER install into this repo (the live copy is where it gets tested).

    python tools/sync_from_reaper.py ["<REAPER resource path>/Scripts/ReaPersona"]

Only what the repo publishes is copied: the scripts, styles.json, previews and the demo song. Never this computer's generated
files (scripts.json, midi_fallback.json, midi_defaults.json, presets, action dumps) and never third-party themes or toolbars.
"""
import os, shutil, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(HERE, "ReaPersona")
FILES = ["ReaPersona.lua", "reapersona_core.lua", "styles.json", "install_shortcuts.py", "validate.py", "merge_themes.py",
         "make_demo.lua", "make_previews.lua", "build_themes.py", "colour_keys.txt", "demo/ReaPersona demo.rpp",
         "extensions/reaper_smoothwheelscroll-x64.dll", "extensions/SmoothWheelScroll-LICENSE.txt"]


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else r"J:\Portable Workstation\DAW\REAPER\Scripts\ReaPersona"
    files = FILES + ["previews/" + f for f in sorted(os.listdir(os.path.join(src, "previews"))) if f.endswith(".png")]
    for f in files:
        os.makedirs(os.path.dirname(os.path.join(DST, f)), exist_ok=True)
        shutil.copy2(os.path.join(src, f), os.path.join(DST, f))
    print("copied %d files from %s" % (len(files), src))


if __name__ == "__main__":
    main()
