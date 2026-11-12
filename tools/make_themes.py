"""Write THEMES.md, the credits for every theme the styles use, from styles.json's theme catalog.

    python tools/make_themes.py
"""
import json, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    d = json.load(open(os.path.join(HERE, "ReaPersona", "styles.json"), encoding="utf-8"))
    cat = d["themes"]
    rows = []
    for st in d["styles"]:
        seen = set()
        for th in [st.get("theme")] + st.get("themes", []):
            if not th or th in seen:
                continue
            seen.add(th)
            c = cat.get(th) or cat.get(th.replace(".ReaperThemeZip", ".ReaperTheme"))
            if not c:
                continue  # (a theme made on your computer with Merge or Adjust)
            name = th.rsplit(".", 1)[0] + (" (%s)" % c["note"] if c.get("note") and c.get("url") not in ("builtin", "reapersona") else "")
            where = {"builtin": "comes with REAPER", "reapersona": "built by Setup"}.get(c.get("url"), "[link](%s)" % c.get("url", ""))
            rows.append("| %s | %s | %s | %s | %s |" % (st["name"], name, c.get("by", ""), c.get("licence", ""), where))
    text = """# Themes the styles use, with credit

**ReaPersona's own themes** (one per DAW) are built on your computer by Setup, from REAPER's Default 7 (© Cockos), which every REAPER has. The recipes for them are in `styles.json` under `own_themes`.

Every other theme here belongs to its author and isn't redistributed. Get it from the link, then drop the file (or the pack's zip) onto ReaPersona's window. A style uses the first of its themes you have, and the Theme list lets you pick another. Most Stash themes state no licence, so their authors keep all rights; where a licence is known it's listed.

| Style | Theme | By | Licence | Where |
|---|---|---|---|---|
%s

Toolbars: the Cubase and Logic styles use the toolbar sets from CubicPack3 (Cubic13) and CLogic (Cubic13). Drop their zips onto ReaPersona's window, then install the shortcuts.

Made a theme with **Merge** or **Adjust**? It's yours to use, but share it only with its source themes' authors' agreement. A theme built from Echolot (mawi) has to stay non-commercial and share-alike (CC BY-NC-SA 4.0).
""" % "\n".join(rows)
    open(os.path.join(HERE, "THEMES.md"), "w", encoding="utf-8", newline="\n").write(text)
    print("THEMES.md: %d rows" % len(rows))


if __name__ == "__main__":
    main()
