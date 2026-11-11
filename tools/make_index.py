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
            if not rel.startswith("__pycache__"):
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
            src.append('        <source file="%s">%s</source>' % (escape(f, {'"': "&quot;"}), escape(url)))
    xml = """<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="ReaPersona">
  <category name="Workflow">
    <reapack name="ReaPersona.lua" type="script" desc="ReaPersona: make REAPER feel like other DAWs, switch themes and presets">
      <metadata>
        <link rel="website">%s</link>
      </metadata>
      <version name="%s" author="James" time="%s">
        <changelog><![CDATA[%s]]></changelog>
%s
      </version>
    </reapack>
  </category>
</index>
""" % (REPO, version, time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), changelog, "\n".join(src))
    open(os.path.join(HERE, "index.xml"), "w", encoding="utf-8", newline="\n").write(xml)
    print("index.xml: %d files at %s" % (len(src), sha[:8]))


if __name__ == "__main__":
    main()
