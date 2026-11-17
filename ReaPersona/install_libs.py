"""ReaPersona: Pillow and numpy for the theme builder (Home > Pillow and numpy > Install them), in a venv of ReaPersona's own.
Run by reapersona_core.lua in the background, so REAPER doesn't wait while pip downloads.

A venv, not `pip install --user`: Homebrew's Python 3.12+ and recent Debian and Ubuntu refuse installs into their own Python
(PEP 668, "externally-managed-environment"), and a venv works the same on every system.

    python install_libs.py <venv folder> <status file>   -> the status file says "ok", or "failed" and what went wrong
"""
import os, shutil, subprocess, sys

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)  # (Windows: no console window for each step)


def run(cmd, timeout):
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=timeout, stdin=subprocess.DEVNULL,
                          creationflags=NO_WINDOW)


def say(status, text):
    with open(status + ".tmp", "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(status + ".tmp", status)


def venv_python(venv):
    return os.path.join(venv, "Scripts", "python.exe") if os.name == "nt" else os.path.join(venv, "bin", "python3")


def install(venv):
    """-> None when Pillow and numpy import in the venv, else what went wrong"""
    py = venv_python(venv)
    if not os.path.exists(py):
        if os.path.isdir(venv):  # (a venv cut short: made again from the start)
            shutil.rmtree(venv, ignore_errors=True)
        r = run([sys.executable, "-m", "venv", venv], 600)
        if r.returncode != 0 or not os.path.exists(py):
            shutil.rmtree(venv, ignore_errors=True)
            why = (r.stderr or r.stdout or "").strip()[-600:]
            if "ensurepip" in why or "python3-venv" in why:  # (Debian and Ubuntu ship venv's pip separately)
                why += "\n\nThis Python can't make a venv yet. On Debian or Ubuntu: sudo apt install python3-venv, then Install them again."
            return "couldn't make the venv: " + why
    r = run([py, "-m", "pip", "install", "--disable-pip-version-check", "--no-input", "pillow", "numpy"], 1800)
    if r.returncode != 0:
        return "pip didn't finish: " + (r.stderr or r.stdout or "").strip()[-600:]
    r = run([py, "-c", "import PIL, numpy"], 120)
    if r.returncode != 0:
        return "installed, but they don't load: " + (r.stderr or "").strip()[-600:]
    return None


def main():
    venv, status = sys.argv[1], sys.argv[2]
    try:
        why = install(venv)
    except BaseException as e:  # (a timeout included: whatever happened is written down for ReaPersona)
        why = "%s: %s" % (type(e).__name__, e)
    say(status, "ok\n" if why is None else "failed\n" + why + "\n")
    return 0 if why is None else 1


if __name__ == "__main__":
    sys.exit(main())
