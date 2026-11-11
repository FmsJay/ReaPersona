"""ReaPersona: merge themes into a new one of your own, kept in ColorThemes (local only: most Stash themes carry no licence,
so a merged theme isn't shared without its authors' permission).
    python merge_themes.py "<base>.ReaperThemeZip" "<colours from>" [--graphics "<graphics from>" --parts faders,knobs,...] [--fonts]
The base gives the layout (its WALTER rtconfig, so its own adjuster settings keep working) and every image; the colours theme gives
the colour values; --graphics swaps in the other theme's images for the chosen parts, only where the base has an image of the same
name (so the base's layout still fits them); --fonts takes the colours theme's fonts too. Prints the new theme's file name.
"""
import fnmatch, io, os, re, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
THEMES = os.path.join(os.path.dirname(os.path.dirname(HERE)), "ColorThemes")
PARTS = {  # image name patterns per part of the look
    "faders": ["*volthumb*", "*panthumb*", "*widththumb*", "*fader*"],
    "knobs": ["*knob*"],
    "meters": ["meter_*", "*_meter*"],
    "transport": ["transport_*"],
    "buttons": ["*_mute*", "*_solo*", "*_recarm*", "*_fx*", "*_phase*", "*_monitor*", "*_io*", "*_env*", "*_folder*"],
    "toolbar": ["toolbar_*"],
    "backgrounds": ["*_bg*", "*_mainbg*", "*_namebg*", "*_iconbg*"],
}


def theme_text(path):
    """(colour theme text, zip or None, image folder in the zip or None) for a .ReaperTheme or .ReaperThemeZip."""
    if path.lower().endswith(".reapertheme"):
        return open(path, encoding="latin-1").read(), None, None
    z = zipfile.ZipFile(path)
    names = z.namelist()
    top = [n for n in names if n.lower().endswith(".reapertheme") and "/" not in n]
    if not top:
        top = [n for n in names if n.lower().endswith(".reapertheme")]
    rt = [n for n in names if n.lower().endswith("rtconfig.txt")]
    folder = rt[0].rsplit("/", 1)[0] if rt and "/" in rt[0] else None
    if folder is None:
        dirs = [n.split("/")[0] for n in names if "/" in n and n.lower().endswith(".png")]
        folder = max(set(dirs), key=dirs.count) if dirs else None
    return (z.read(top[0]).decode("latin-1") if top else "[color theme]\n"), z, folder


def section(text, name):
    """key -> value for one [section] of a .ReaperTheme."""
    out, on = {}, False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            on = s.lower() == "[" + name.lower() + "]"
        elif on and "=" in s:
            k, v = s.split("=", 1)
            out[k] = v
    return out


def put(text, name, values):
    """text with values written into [name] (replaced where present, added at the section's top where not)."""
    lines = text.replace("\r\n", "\n").split("\n")
    seen, on, out = set(), False, []
    for line in lines:
        s = line.strip()
        if s.startswith("["):
            on = s.lower() == "[" + name.lower() + "]"
        elif on and "=" in s:
            k = s.split("=", 1)[0]
            if k in values:
                line = k + "=" + values[k]
                seen.add(k)
        out.append(line)
    missing = [k + "=" + v for k, v in values.items() if k not in seen]
    if missing:
        i = next((n for n, l in enumerate(out) if l.strip().lower() == "[" + name.lower() + "]"), None)
        if i is None:
            out += ["[" + name + "]"] + missing
        else:
            out[i + 1:i + 1] = missing
    return "\n".join(out)


def stem(p):
    return re.sub(r"\.ReaperTheme(Zip)?$", "", os.path.basename(p), flags=re.I)


def merge(base, colours, graphics=None, parts=(), fonts=False):
    btext, bzip, bfolder = theme_text(base)
    if bzip is None:
        sys.exit("The base needs to be a .ReaperThemeZip (it's where the layout and images are).")
    ctext, _, _ = theme_text(colours)
    text = put(btext, "color theme", section(ctext, "color theme"))
    if fonts:
        text = put(text, "REAPER", {k: v for k, v in section(ctext, "REAPER").items() if k.endswith("_font") or "font" in k})
    swap = {}
    if graphics and parts:
        _, gzip, gfolder = theme_text(graphics)
        if gzip is None:
            sys.exit("Graphics come from a .ReaperThemeZip.")
        pats = [p for part in parts for p in PARTS[part]]
        # (main folder only, both sides: the 150%/200% subfolders hold bigger copies a 100% image mustn't stand in for)
        top = lambda n, f: n.rsplit("/", 1)[0] == f if f else "/" not in n
        gimgs = {n.rsplit("/", 1)[-1].lower(): n for n in gzip.namelist() if n.lower().endswith(".png") and top(n, gfolder)}
        for n in bzip.namelist():
            fn = n.rsplit("/", 1)[-1].lower()
            if fn.endswith(".png") and top(n, bfolder) and fn in gimgs and any(fnmatch.fnmatch(fn, p) for p in pats):
                swap[n] = gzip.read(gimgs[fn])
    name = stem(base) + " + " + stem(colours) + " colours"
    if swap:
        name += " + " + stem(graphics) + " " + "+".join(parts)
    out = os.path.join(THEMES, name + ".ReaperThemeZip")
    folder = bfolder or stem(base)
    text = put(text, "REAPER", {"ui_img": folder})
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(name + ".ReaperTheme", text.replace("\n", "\r\n").encode("latin-1"))
        for n in bzip.namelist():
            if n.lower().endswith(".reapertheme") and "/" not in n:
                continue  # (replaced by the merged colour file)
            z.writestr(n, swap.get(n, bzip.read(n)))
    open(out, "wb").write(buf.getvalue())
    return os.path.basename(out), len(swap)


if __name__ == "__main__":
    assert section("[color theme]\na=1\n[REAPER]\nb=2", "color theme") == {"a": "1"}
    assert put("[color theme]\na=1\n[REAPER]\nb=2", "color theme", {"a": "5", "c": "7"}) == "[color theme]\nc=7\na=5\n[REAPER]\nb=2"
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    def opt(flag):
        if flag in args:
            i = args.index(flag); v = args[i + 1]; del args[i:i + 2]; return v
    g, p = opt("--graphics"), opt("--parts")
    f = "--fonts" in args
    args = [a for a in args if a != "--fonts"]
    full = lambda a: a if os.path.isabs(a) else os.path.join(THEMES, a)
    name, n = merge(full(args[0]), full(args[1]), g and full(g), [x for x in (p or "").split(",") if x], f)
    print(name)
    print("%d image(s) swapped" % n, file=sys.stderr)
