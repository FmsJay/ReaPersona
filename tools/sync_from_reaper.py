"""Copy ReaPersona's files from a REAPER install into this repo (the live copy is where it gets tested).

    python tools/sync_from_reaper.py ["<REAPER resource path>/Scripts/ReaPersona"]

Only what the repo publishes is copied: every file git tracks under ReaPersona/ (what tools/make_index.py publishes), plus new ui/*.lua,
previews/*.png and templates/*.RPP from the live copy. A brand-new file anywhere else: git add it once, then it's copied from then on.
Never this computer's generated files (scripts.json, user_styles.json, presets, action dumps...) and never third-party themes or toolbars.
A ui file gone from the live copy (renamed or removed there) is deleted here too, so make_index doesn't publish a stale one; any other
tracked file missing live is only reported.
"""
import os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DST = os.path.join(HERE, "ReaPersona")
NEW_OK = (("ui/", ".lua"), ("previews/", ".png"), ("templates/", ".RPP"))  # (folders whose new files come in without a git add)


def tracked():
    """ReaPersona/'s files in git (index), relative to ReaPersona/. -z: names with spaces or accents come through unquoted."""
    out = subprocess.run(["git", "-C", HERE, "ls-files", "-z", "ReaPersona/"], capture_output=True, check=True).stdout.decode("utf-8")
    return [p[len("ReaPersona/"):] for p in out.split("\0") if p]


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else r"J:\Portable Workstation\DAW\REAPER\Scripts\ReaPersona"
    if not os.path.exists(os.path.join(src, "reapersona_core.lua")):
        sys.exit("no ReaPersona in " + src)
    files = set(tracked())
    for folder, ext in NEW_OK:
        d = os.path.join(src, folder)
        files |= {folder + f for f in os.listdir(d) if f.endswith(ext)} if os.path.isdir(d) else set()
    copied, removed, missing = 0, [], []
    for f in sorted(files):
        s, d = os.path.join(src, f), os.path.join(DST, f)
        if os.path.exists(s):
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copy2(s, d)
            copied += 1
        elif f.startswith("ui/"):
            if os.path.exists(d):
                os.remove(d)
            removed.append(f)
        else:
            missing.append(f)
    print("copied %d files from %s" % (copied, src))
    if removed:
        print("removed here (gone from the live copy): " + ", ".join(removed))
    if missing:
        print("not in the live copy, left as they are (git rm them if they should go): " + ", ".join(missing))


if __name__ == "__main__":
    main()
