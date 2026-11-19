"""Lint ReaPersona's Lua with LuaLS (lua-language-server --check) on a copy, with the repo's .luarc.json.

    python tools/lint.py [folder]      (default: ReaPersona/; exit 1 when something must be fixed)

Fails on:
- undefined-global anywhere: a name read that nothing ever sets (a typo, or a ui name that was renamed in one file only). The window's
  ui/*.lua files run in one shared environment table (R in ReaPersona.lua), so a name one ui file sets is a global the others read;
  LuaLS sees every file of the folder at once, so it counts those as defined. That's why the folder is checked as a whole.
- lowercase-global outside ui/: the engine, the key helpers, colours and the loader are modules; a global written there leaks into
  every script REAPER runs. (In ui/ every shared name is such a global by design, so it's ignored there.)
- a syntax error (miss-end, miss-symbol, unexpect-symbol...: round 4). tools/check.py also compiles every file.
Everything else is counted and printed, not failed: known false positives include unbalanced-assignments on
`ok, p = reaper.JS_x and reaper.JS_x(...)`, undefined-field on tables filled at runtime, and need-check-nil.
"""
import json, os, shutil, subprocess, sys, tempfile, urllib.parse
from collections import Counter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUALS = os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\LuaLS.lua-language-server_Microsoft.Winget.Source_8wekyb3d8bbwe\bin\lua-language-server.exe")


def luals():
    if os.path.exists(LUALS):
        return LUALS
    found = shutil.which("lua-language-server")
    if not found:
        sys.exit("lua-language-server not found (winget install LuaLS.lua-language-server, or put it on PATH)")
    return found


def syntax_code(code):
    """LuaLS's syntax-error codes (miss-end, miss-symbol, unexpect-symbol, err-..., malformed-number...). Pure."""
    return code.startswith(("miss-", "unexpect-", "err-", "malformed-")) or code in ("unknown-symbol", "unsupport-symbol", "keyword")


def must_fix(rel, code):
    """Is this diagnostic a failure? rel: the file's path inside the checked folder, with / separators. Pure."""
    return code == "undefined-global" or (code == "lowercase-global" and not rel.startswith("ui/")) or syntax_code(code)


def main():
    src = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "ReaPersona"))
    work = tempfile.mkdtemp(prefix="reapersona-lint-")
    try:
        # (a copy: only the Lua files, so LuaLS doesn't index venv/, generated stubs or downloads, and writes nothing into the repo)
        ws = os.path.join(work, "ws")
        for root, dirs, names in os.walk(src):
            rel = os.path.relpath(root, src)
            dirs[:] = [d for d in dirs if rel != "." or d == "ui"]  # (the top folder and ui/: what ships and runs as the script)
            for n in names:
                if n.endswith(".lua"):
                    os.makedirs(os.path.join(ws, rel), exist_ok=True)
                    shutil.copy2(os.path.join(root, n), os.path.join(ws, rel, n))
        shutil.copy2(os.path.join(HERE, ".luarc.json"), os.path.join(ws, ".luarc.json"))
        out = os.path.join(work, "check.json")
        r = subprocess.run([luals(), "--check=" + ws, "--checklevel=Information", "--check_format=json", "--check_out_path=" + out,
                            "--logpath=" + os.path.join(work, "log")], capture_output=True, text=True, errors="replace")
        # (no report is never a clean result: the ui files always carry their shared-name diagnostics. A LuaLS that ignores
        # --check_out_path, an older one on PATH say, exits 0 and leaves the report elsewhere: that passed as "lint ok" before. Round 2, R2-5)
        if not os.path.exists(out):
            sys.exit("lua-language-server wrote no report (exit %d; check its version, 3.7 or newer takes --check_out_path): %s"
                     % (r.returncode, (r.stderr or r.stdout).strip()[-500:]))
        report = json.load(open(out, encoding="utf-8"))
        counts, failures, ui_seen = Counter(), [], False
        base = "file:///" + ws.replace("\\", "/").lstrip("/")
        for uri, diags in report.items():
            path = urllib.parse.unquote(uri)
            rel = path[len(base):].lstrip("/") if path.lower().startswith(base.lower()) else path
            ui_seen = ui_seen or (rel.startswith("ui/") and len(diags) > 0)
            for d in diags:
                counts[d["code"]] += 1
                if must_fix(rel, d["code"]):
                    failures.append("%s:%d: %s: %s" % (rel, d["range"]["start"]["line"] + 1, d["code"], d["message"]))
        print("checked %s: %s" % (src, ", ".join("%s %d" % c for c in counts.most_common()) or "no diagnostics"))
        for f in sorted(failures):
            print("FIX " + f)
        if failures:
            sys.exit(1)
        if os.path.isdir(os.path.join(ws, "ui")) and not ui_seen:  # (ui/ was copied but nothing in it reported: it wasn't really checked)
            sys.exit("lua-language-server reported nothing for ui/, which always has shared-name diagnostics: it didn't check the folder")
        print("lint ok: no undefined globals, no globals written outside ui/")
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
