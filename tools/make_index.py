"""Write index.xml, the ReaPack index, for the files in ReaPersona/ at a given commit.

    python tools/make_index.py <commit sha> <version> "<changelog>"

ReaPack installs the package into <REAPER resource path>/Scripts/ReaPersona/Workflow/ and registers ReaPersona.lua as an action;
the other files come with it. Run it after committing the files, then commit index.xml (its URLs point at that earlier commit).
"""
import os, sys, time, urllib.parse
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/FmsJay/ReaPersona"


def files():
    out = []
    for root, _, names in os.walk(os.path.join(HERE, "ReaPersona")):
        for n in sorted(names):
            rel = os.path.relpath(os.path.join(root, n), os.path.join(HERE, "ReaPersona")).replace("\\", "/")
            if not rel.startswith(("__pycache__", "venv/", "install_staged/")):  # (each computer's own: the theme builder's venv, a staged install)
                out.append(rel)
    return sorted(out, key=lambda f: (f != "ReaPersona.lua", f))


def main():
    sha, version, changelog = sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
    src = []
    for f in files():
        url = "%s/raw/%s/ReaPersona/%s" % (REPO, sha, urllib.parse.quote(f))
        if f == "ReaPersona.lua":
            src.append('        <source main="main">%s</source>' % escape(url))
        else:
            plat = ' platform="win64"' if f.endswith("-x64.dll") else ""  # (a Windows build: ReaPack gives it to 64-bit Windows only)
            src.append('        <source%s file="%s">%s</source>' % (plat, escape(f, {'"': "&quot;"}), escape(url)))
    # Extensions > ReaPersona and View > ReaPersona (extension/, source shared with StudioSync): a package of its own with a version of its
    # own, raised only when the extension changes, so ReaPersona's updates don't try to replace a file REAPER has loaded.
    ext_version, ext = "1.0.1", []  # (1.0.1: macOS and Linux builds, from StudioSync's .github/workflows/extension.yml)
    for name, plat in (("reaper_reapersona-x64.dll", "win64"), ("reaper_reapersona.dylib", "darwin"),
                       ("reaper_reapersona-x86_64.so", "linux64"), ("reaper_reapersona-aarch64.so", "linux-aarch64")):
        if os.path.exists(os.path.join(HERE, "extension", name)):
            ext.append('        <source platform="%s" file="%s">%s/raw/%s/extension/%s</source>' % (plat, name, REPO, sha, name))
    ext_pkg = ("""
    <reapack name="ReaPersona menus.ext" type="extension" desc="ReaPersona in REAPER's Extensions and View menus">
      <metadata>
        <link rel="website">%s</link>
      </metadata>
      <version name="%s" author="James" time="%s">
        <changelog><![CDATA[ReaPersona in the Extensions and View menus, and the action 'ReaPersona: open'.]]></changelog>
%s
      </version>
    </reapack>""" % (REPO, ext_version, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "\n".join(ext))) if ext else ""
    xml = """<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="ReaPersona">
  <category name="Workflow">
    <reapack name="ReaPersona.lua" type="script" desc="ReaPersona: fit REAPER to your preferred look, workflow or favourite DAW, with import, export and sync across computers">
      <metadata>
        <link rel="website">%s</link>
      </metadata>
      <version name="%s" author="James" time="%s">
        <changelog><![CDATA[%s]]></changelog>
%s
      </version>
    </reapack>%s
  </category>
</index>
""" % (REPO, version, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), changelog, "\n".join(src), ext_pkg)
    open(os.path.join(HERE, "index.xml"), "w", encoding="utf-8", newline="\n").write(xml)
    print("index.xml: %d files at %s" % (len(src), sha[:8]))


if __name__ == "__main__":
    main()
