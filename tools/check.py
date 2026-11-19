"""Every check ReaPersona has, in one command: run it before a release (tools/make_index.py runs it on the commit it indexes).

    python tools/check.py                  the working tree as it is now
    python tools/check.py --commit <sha>   that commit (what a release publishes)

Runs, each in a temp copy of its own so nothing in the repo is written and runs never share tests/_tmp-* folders:
  tests/test_core.lua (through lupa), tests/test_ui.lua (through lupa), tests/test_installers.py, tools/lint.py, and
  installer/reapersona_setup.lua's own self-check (the installers fetch it from main, so no release step ever loads it).
Each gets STEP_TIMEOUT seconds: a test stuck in a loop fails instead of hanging the release (round 4, code-health 4).
First, every .py and .lua under ReaPersona/, installer/, tools/ and tests/ is compiled (nothing is run), so a syntax error in a file
no test loads (setup_helper.py, validate.py, make_*.lua...) fails too (round 4). And no source may hold raw invisible line-breaking
characters (U+2028, U+2029, U+0085, control characters): editors and agent tools treat those as line breaks, and one careless edit
turns a test of them into a test of nothing (round 2, R2-4).
Exit 1 if anything fails. Needs Python 3 with lupa (pip install lupa) and lua-language-server (see tools/lint.py).
"""
import io, os, shutil, subprocess, sys, tarfile, tempfile, time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUPA = "import lupa.lua54 as l; l.LuaRuntime().execute(open(%r, encoding='utf-8').read())"
SUITES = [("test_core.lua", [sys.executable, "-c", LUPA % "tests/test_core.lua"]),
          ("test_ui.lua", [sys.executable, "-c", LUPA % "tests/test_ui.lua"]),
          ("test_installers.py", [sys.executable, "tests/test_installers.py"]),
          ("lint", [sys.executable, "tools/lint.py"]),
          ("reapersona_setup.lua self-check", [sys.executable, "-c", LUPA % "installer/reapersona_setup.lua"])]
STEP_TIMEOUT = 600  # (seconds per suite; each takes about 10)
FOLDERS = ("ReaPersona", "tests", "tools", "installer")
SKIP = shutil.ignore_patterns(".git", "__pycache__", "venv", "install_staged", "_downloads", "_tmp-*", "pending")
# (characters that break a line without looking like it; tab, CR and LF are the only control characters a source needs)
BAD_CHARS = {chr(c) for c in range(32) if c not in (9, 10, 13)} | {chr(0x7f), chr(0x85), chr(0x2028), chr(0x2029)}
NL = chr(10)


def copy_tree(dst, commit):
    """The repo's files into dst: the working tree, or the commit's tree through git archive."""
    if commit:
        tar = subprocess.run(["git", "-C", HERE, "archive", "--format=tar", commit], capture_output=True)
        if tar.returncode != 0:
            sys.exit("git archive %s failed: %s" % (commit, tar.stderr.decode("utf-8", "replace").strip()))
        tarfile.open(fileobj=io.BytesIO(tar.stdout)).extractall(dst, **({"filter": "data"} if hasattr(tarfile, "data_filter") else {}))
    else:
        shutil.copytree(HERE, dst, ignore=SKIP)


def sources(root):
    """-> (path relative to root, text) for every .py and .lua source in FOLDERS."""
    for folder in FOLDERS:
        for d, _, names in os.walk(os.path.join(root, folder)):
            for n in sorted(names):
                if n.endswith((".py", ".lua")):
                    p = os.path.join(d, n)
                    yield os.path.relpath(p, root), open(p, encoding="utf-8", errors="replace", newline="").read()


def bad_sources(root):
    """-> 'path:line: U+XXXX' for each raw invisible line-breaking character in a .py or .lua source."""
    out = []
    for rel, text in sources(root):
        for i, line in enumerate(text.split(NL), 1):
            for c in set(line) & BAD_CHARS:
                out.append("%s:%d: U+%04X" % (rel, i, ord(c)))
    return out


def syntax_errors(root):
    """-> 'path:line: error' for each source that doesn't compile: Python's compile(), Lua 5.4's load() through lupa (nothing is run)."""
    import lupa.lua54 as lupa
    lua_load = lupa.LuaRuntime().eval("function(s, n) local f, e = load(s, n) return e end")
    out = []
    for rel, text in sources(root):
        if rel.endswith(".py"):
            try:
                compile(text, rel, "exec")
            except SyntaxError as e:
                out.append("%s:%s: %s" % (rel, e.lineno, e.msg))
        else:
            e = lua_load(text, "@" + rel)
            if e:
                out.append(str(e))
    return out


def report(name, bad, ok_text, fail_text, failed):
    print(("FAIL  %s: %s:%s      %s" % (name, fail_text, NL, (NL + "      ").join(bad))) if bad else "ok    %s: %s" % (name, ok_text))
    if bad:
        failed.append(name)


def main():
    commit = sys.argv[sys.argv.index("--commit") + 1] if "--commit" in sys.argv else None
    work = tempfile.mkdtemp(prefix="reapersona-check-")
    failed = []
    try:
        base = os.path.join(work, "base")
        copy_tree(base, commit)
        report("sources", bad_sources(base), "no raw invisible line-breaking characters",
               "raw invisible characters (write them as escapes, like the six characters backslash u 2 0 2 8)", failed)
        report("syntax", syntax_errors(base), "every .py and .lua compiles", "doesn't compile", failed)
        runs = []
        for name, cmd in SUITES:  # (all at once, each in its own copy: about as long as the slowest one)
            cwd = os.path.join(work, "".join(c if c.isalnum() else "_" for c in name))
            shutil.copytree(base, cwd)
            runs.append((name, time.time(), subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)))
        for name, t0, p in runs:
            try:
                out = p.communicate(timeout=max(1, STEP_TIMEOUT - (time.time() - t0)))[0].decode("utf-8", "replace")
            except subprocess.TimeoutExpired:  # (a loop that never ends: killed and failed, never a hung release)
                p.kill()
                out = p.communicate()[0].decode("utf-8", "replace") + NL + "(killed: still running after %d s)" % STEP_TIMEOUT
            if p.returncode == 0:
                print("ok    %s (%.0f s)" % (name, time.time() - t0))
            else:
                failed.append(name)
                tail = out.strip().splitlines()[-30:]
                print("FAIL  %s (exit %d):%s      %s" % (name, p.returncode, NL, (NL + "      ").join(tail)))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if failed:
        sys.exit("checks failed: " + ", ".join(failed))
    print("all checks passed" + (" for " + commit[:8] if commit else ""))


if __name__ == "__main__":
    main()
