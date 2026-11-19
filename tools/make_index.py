"""Write index.xml, the ReaPack index, for the files in ReaPersona/ at a given commit.

    python tools/make_index.py <commit sha> <version> "<changelog>" [--skip-checks]

It runs tools/check.py on that commit first (every test suite and the lint) and writes nothing if a check fails; --skip-checks
writes the index anyway (round 2: a release used to run none of them).

ReaPack installs the package into <REAPER resource path>/Scripts/ReaPersona/Workflow/ and registers ReaPersona.lua as an action;
the other files come with it. Run it after committing the files, then commit index.xml (its URLs point at that earlier commit).
"""
import os, subprocess, sys, time, urllib.parse
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "https://github.com/FmsJay/ReaPersona"

# Files ReaPersona writes on each computer (its .gitignore lists most). Published, ReaPack and the self-updater would write the
# author's copy over every user's own (their personas, presets, sync state...), so a commit holding one of these isn't indexed.
PER_COMPUTER = ("scripts.json", "user_styles.json", "presets.json", "sync_state.json", "layers.json", "user_themes.json", "midi_map.lua",
                "midi_fallback.json", "midi_defaults.json", "installed.json", "errors.log", "last_install.txt", "install_cancelled", "layers.json.before-install",
                "packages_missing.json", "_packages.json", "venv_status.txt", "_starter.RTrackTemplate", "_template.RPP", "_capture.RPP")
PER_COMPUTER_DIRS = ("actions/", "midi_keys/", "cheat sheets/", "pending/", "_downloads/", "_incoming/", "_staged/", "install_staged/",
                     "feedback/", "versions/", "toolbars/", "venv/", "__pycache__/", "backups/")


def tracked(sha, folder):
    """The files under folder/ in commit sha, relative to folder: exactly what the raw URLs at that sha serve (review round 1: the
    working tree was listed before, so an untracked or ignored file got a URL that 404s and broke the whole update)."""
    out = subprocess.run(["git", "-C", HERE, "ls-tree", "-r", "--name-only", "-z", sha, folder + "/"], capture_output=True)
    if out.returncode != 0:
        sys.exit("git ls-tree %s failed: %s" % (sha, out.stderr.decode("utf-8", "replace").strip()))
    return [p[len(folder) + 1:] for p in out.stdout.decode("utf-8").split("\0") if p.startswith(folder + "/")]  # (-z: names unquoted)


def per_computer(rel):
    """Is this ReaPersona/ path one of each computer's own files? Pure."""
    name = rel.rsplit("/", 1)[-1]
    return (name in PER_COMPUTER or rel.startswith(PER_COMPUTER_DIRS) or (name.startswith("actions_") and name.endswith(".tsv"))
            or name.endswith((".ReaperTheme", ".ReaperThemeZip", ".tmp", ".new")) or ".bad-" in name or ".before-" in name)


def files(sha):
    out = tracked(sha, "ReaPersona")
    bad = [f for f in out if per_computer(f)]
    if bad:
        sys.exit("not indexed: commit %s holds each computer's own files (remove them with git rm --cached): %s" % (sha[:8], ", ".join(bad)))
    if "ReaPersona.lua" not in out:
        sys.exit("not indexed: commit %s has no ReaPersona/ReaPersona.lua" % sha[:8])
    return sorted(out, key=lambda f: (f != "ReaPersona.lua", f))


def main():
    skip = "--skip-checks" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--skip-checks"]
    sha, version, changelog = args[0], args[1], args[2] if len(args) > 2 else ""
    # (the full commit id: a short one or a name like HEAD would put a moving or ambiguous ref in every URL)
    full = subprocess.run(["git", "-C", HERE, "rev-parse", "--verify", sha + "^{commit}"], capture_output=True, text=True)
    if full.returncode != 0:
        sys.exit("not a commit here: " + sha)
    sha = full.stdout.strip()
    if not skip:  # (the commit being published, checked in a temp copy: tests, parity, lint)
        if subprocess.run([sys.executable, os.path.join(HERE, "tools", "check.py"), "--commit", sha]).returncode != 0:
            sys.exit("not indexed: tools/check.py failed for %s (fix it, or --skip-checks to write the index anyway)" % sha[:8])
    src = []
    for f in files(sha):
        url = "%s/raw/%s/ReaPersona/%s" % (REPO, sha, urllib.parse.quote(f))
        if f == "ReaPersona.lua":
            src.append('        <source main="main">%s</source>' % escape(url))
        else:
            plat = ' platform="win64"' if f.endswith("-x64.dll") else ""  # (a Windows build: ReaPack gives it to 64-bit Windows only)
            src.append('        <source%s file="%s">%s</source>' % (plat, escape(f, {'"': "&quot;"}), escape(url)))
    # Extensions > ReaPersona and View > ReaPersona (extension/, source shared with StudioSync): a package of its own with a version of its
    # own, raised only when the extension changes, so ReaPersona's updates don't try to replace a file REAPER has loaded.
    ext_version, ext = "1.0.1", []  # (1.0.1: macOS and Linux builds, from StudioSync's .github/workflows/extension.yml)
    ext_files = set(tracked(sha, "extension"))  # (from the commit too: a build only on disk would be a 404)
    for name, plat in (("reaper_reapersona-x64.dll", "win64"), ("reaper_reapersona.dylib", "darwin"),
                       ("reaper_reapersona-x86_64.so", "linux64"), ("reaper_reapersona-aarch64.so", "linux-aarch64")):
        if name in ext_files:
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
