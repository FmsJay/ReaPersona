"""ReaPersona's helper for syncing REAPER itself to your other computers (Settings > Your other computers, the advanced parts). Run by
reapersona_core.lua; it only reads, except `install`, which adds placeholders to ReaPack's registry for ReaPack's own sync to fill in.
    python setup_helper.py packages <resource path> <out>    -> writes JSON {installed: [[remote, category, package, type, desc, author]], owned: [path]}
                                                                to <out> (REAPER's ExecProcess stalls on a long answer: about 800 KB here)
    python setup_helper.py install <resource path> <json>    -> how many placeholders were added (the json: {"remote|category|package": {type, desc, author}})
How install works: ReaPack's sync updates every package its registry lists to the index's newest version for this system. A package that's
listed at version 0 with no files is one it updates, i.e. installs, with the right files for this computer (a Mac's .dylib, not a .dll).
"""
import json, os, platform, sqlite3, sys
import xml.etree.ElementTree as ET
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


def here_platforms():
    """ReaPack's platform names that fit this computer."""
    arm = platform.machine().lower() in ("arm64", "aarch64")
    if sys.platform == "win32":
        return {"all", "windows", "win64", "windows-arm64ec"} if arm else {"all", "windows", "win64"}
    if sys.platform == "darwin":
        return {"all", "darwin", "darwin-arm64"} if arm else {"all", "darwin", "darwin64"}
    return {"all", "linux", "linux-aarch64"} if arm else {"all", "linux", "linux64"}


def available(res, remote, category, package, plats, indexes):
    """Can ReaPack install it here? Its cached index has to offer a version with files for this system: a placeholder for one it doesn't
    (removed upstream, or Windows-only on a Mac) stopped the Mac's whole ReaPack sync on an "Obsolete packages" question (5.12.3).
    No cached index: can't tell, so yes."""
    if remote not in indexes:
        try:
            indexes[remote] = ET.parse(os.path.join(res, "ReaPack", "cache", remote + ".xml")).getroot()
        except (OSError, ET.ParseError):
            indexes[remote] = None
    root = indexes[remote]
    if root is None:
        return True
    for cat in root.iter("category"):
        if cat.get("name") != category:
            continue
        for pkg in cat.iter("reapack"):
            if pkg.get("name") == package:
                return any(src.get("platform", "all") in plats for src in pkg.iter("source"))
    return False


def install(res, listfile):
    want = json.load(open(listfile, encoding="utf-8"))
    c = sqlite3.connect(registry(res), timeout=10)
    added, plats, indexes = 0, here_platforms(), {}
    try:
        for key, v in want.items():
            parts = key.split("|", 2)
            if len(parts) != 3 or not isinstance(v, dict):
                continue
            remote, category, package = parts
            try:
                kind = int(v.get("type", 1))
            except (TypeError, ValueError):  # (one bad entry is skipped, not the whole install)
                continue
            if c.execute("SELECT 1 FROM entries WHERE remote = ? AND category = ? AND package = ?", (remote, category, package)).fetchone():
                continue
            if not available(res, remote, category, package, plats, indexes):
                continue
            c.execute("INSERT INTO entries (remote, category, package, desc, type, version, author, flags) VALUES (?, ?, ?, ?, ?, '0', ?, 0)",
                      (remote, category, package, str(v.get("desc", "")), kind, str(v.get("author", ""))))
            added += 1
        c.commit()
    finally:
        c.close()
    return added


def self_test():
    import tempfile
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, "ReaPack", "cache"))
    with open(os.path.join(d, "ReaPack", "cache", "R.xml"), "w") as f:
        f.write('<index><category name="FX"><reapack name="a.ext"><version name="1"><source platform="win64">u</source></version></reapack>'
                '<reapack name="b.lua"><version name="1"><source>u</source></version></reapack></category></index>')
    ix = {}
    assert available(d, "R", "FX", "a.ext", {"all", "darwin"}, ix) is False and available(d, "R", "FX", "a.ext", {"all", "win64"}, ix)
    assert available(d, "R", "FX", "b.lua", {"all", "darwin"}, ix) and not available(d, "R", "FX", "gone.lua", {"all"}, ix)
    assert available(d, "NoCache", "FX", "x", {"all"}, ix)


def main():
    self_test()
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
