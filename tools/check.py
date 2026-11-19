"""Every check ReaPersona has, in one command: run it before a release (tools/make_index.py runs it on the commit it indexes).

    python tools/check.py                  the working tree as it is now
    python tools/check.py --commit <sha>   that commit (what a release publishes)

Runs, each in a temp copy of its own so nothing in the repo is written and runs never share tests/_tmp-* folders:
  tests/test_core.lua (through lupa), tests/test_ui.lua (through lupa), tests/test_installers.py, tools/lint.py.
Also checks that no .py/.lua source holds raw invisible line-breaking characters (U+2028, U+2029, U+0085, control characters):
editors and agent tools treat those as line breaks, and one careless edit turns a test of them into a test of nothing (round 2, R2-4).
Exit 1 if anything fails. Needs Python 3 with lupa (pip install lupa) and lua-language-server (see tools/lint.py).
"""
import io, os, shutil, subprocess, sys, tarfile, tempfile, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUPA = "import lupa.lua54 as l; l.LuaRuntime().execute(open(%r, encoding='utf-8').read())"
SUITES = [("test_core.lua", [sys.executable, "-c", LUPA % "tests/test_core.lua"]),
          ("test_ui.lua", [sys.executable, "-c", LUPA % "tests/test_ui.lua"]),
          ("test_installers.py", [sys.executable, "tests/test_installers.py"]),
          ("lint", [sys.executable, "tools/lint.py"])]
SKIP = shutil.ignore_patterns(".git", "__pycache__", "venv", "install_staged", "_downloads", "_tmp-*", "pending")
# (characters that break a line without looking like it; tab, CR and LF are the only control characters a source needs)
BAD_CHARS = {chr(c) for c in range(32) if c not in (9, 10, 13)} | {chr(0x7f), chr(0x85), chr(0x2028), chr(0x2029)}


def copy_tree(dst, commit):
    """The repo's files into dst: the working tree, or the commit's tree through git archive."""
    if commit:
        tar = subprocess.run(["git", "-C", HERE, "archive", "--format=tar", commit], capture_output=True)
        if tar.returncode != 0:
            sys.exit("git archive %s failed: %s" % (commit, tar.stderr.decode("utf-8", "replace").strip()))
        tarfile.open(fileobj=io.BytesIO(tar.stdout)).extractall(dst, **({"filter": "data"} if hasattr(tarfile, "data_filter") else {}))
    else:
        shutil.copytree(HERE, dst, ignore=SKIP)


def bad_sources(root):
    """-> 'path:line: U+XXXX' for each raw invisible line-breaking character in a .py or .lua source. Pure apart from reading."""
    out = []
    for folder in ("ReaPersona", "tests", "tools", "installer"):
        for d, _, names in os.walk(os.path.join(root, folder)):
            for n in names:
                if n.endswith((".py", ".lua")):
                    p = os.path.join(d, n)
                    text = open(p, encoding="utf-8", errors="replace", newline="").read()
                    for i, line in enumerate(text.split("\n"), 1):
                        for c in set(line) & BAD_CHARS:
                            out.append("%s:%d: U+%04X" % (os.path.relpath(p, root), i, ord(c)))
    return out


def main():
    commit = sys.argv[sys.argv.index("--commit") + 1] if "--commit" in sys.argv else None
    work = tempfile.mkdtemp(prefix="reapersona-check-")
    failed = []
    try:
        base = os.path.join(work, "base")
        copy_tree(base, commit)
        bad = bad_sources(base)
        print(("FAIL  sources: raw invisible characters (write them as escapes, \\u2028 and the like):\n      " + "\n      ".join(bad)) if bad
              else "ok    sources: no raw invisible line-breaking characters")
        if bad:
            failed.append("sources")
        runs = []
        for name, cmd in SUITES:  # (all at once, each in its own copy: about as long as the slowest one)
            cwd = os.path.join(work, name.replace(".", "_"))
            shutil.copytree(base, cwd)
            runs.append((name, time.time(), subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)))
        for name, t0, p in runs:
            out = p.communicate()[0].decode("utf-8", "replace")
            if p.returncode == 0:
                print("ok    %s (%.0f s)" % (name, time.time() - t0))
            else:
                failed.append(name)
                tail = out.strip().splitlines()[-30:]
                print("FAIL  %s (exit %d):\n      %s" % (name, p.returncode, "\n      ".join(tail)))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if failed:
        sys.exit("checks failed: " + ", ".join(failed))
    print("all checks passed" + (" for " + commit[:8] if commit else ""))


if __name__ == "__main__":
    main()
