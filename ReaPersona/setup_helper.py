"""ReaPersona's helper for syncing REAPER itself to your other computers (Settings > Your other computers, the advanced parts). Run by
reapersona_core.lua; it only reads, except `install`, which adds placeholders to ReaPack's registry for ReaPack's own sync to fill in.
    python setup_helper.py packages <resource path> <out>    -> writes JSON {installed: [[remote, category, package, type, desc, author]], owned: [path]}
                                                                to <out> (REAPER's ExecProcess stalls on a long answer: about 800 KB here)
    python setup_helper.py install <resource path> <json>    -> how many placeholders were added (the json: {"remote|category|package": {type, desc, author}})
How install works: ReaPack's sync updates every package its registry lists to the index's newest version for this system. A package that's
listed at version 0 with no files is one it updates, i.e. installs, with the right files for this computer (a Mac's .dylib, not a .dll).
"""
import json, os, sqlite3, sys
from urllib.request import pathname2url


def registry(res):
    return os.path.join(res, "ReaPack", "registry.db")


def packages(res):
    p = registry(res)
    if not os.path.exists(p):
        return {"installed": [], "owned": []}
    c = sqlite3.connect("file:%s?mode=ro" % pathname2url(os.path.abspath(p)), uri=True, timeout=10)
    try:
        installed = [list(r) for r in c.execute("SELECT remote, category, package, type, desc, author FROM entries WHERE version != '0'")]
        owned = [r[0].replace("\\", "/") for r in c.execute("SELECT path FROM files")]
    finally:
        c.close()
    return {"installed": installed, "owned": owned}


def install(res, listfile):
    want = json.load(open(listfile, encoding="utf-8"))
    c = sqlite3.connect(registry(res), timeout=10)
    added = 0
    try:
        for key, v in want.items():
            parts = key.split("|", 2)
            if len(parts) != 3 or not isinstance(v, dict):
                continue
            remote, category, package = parts
            if c.execute("SELECT 1 FROM entries WHERE remote = ? AND category = ? AND package = ?", (remote, category, package)).fetchone():
                continue
            c.execute("INSERT INTO entries (remote, category, package, desc, type, version, author, flags) VALUES (?, ?, ?, ?, ?, '0', ?, 0)",
                      (remote, category, package, str(v.get("desc", "")), int(v.get("type", 1)), str(v.get("author", ""))))
            added += 1
        c.commit()
    finally:
        c.close()
    return added


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "packages":
        tmp = sys.argv[3] + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(packages(sys.argv[2]), f)
        os.replace(tmp, sys.argv[3])
        sys.stdout.write("ok")
    elif len(sys.argv) >= 4 and sys.argv[1] == "install":
        sys.stdout.write(str(install(sys.argv[2], sys.argv[3])))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
