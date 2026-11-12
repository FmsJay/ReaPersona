"""ReaPersona: build its own DAW themes on this computer, from the Default 7 theme REAPER itself ships (ColorThemes/Default_7.0.ReaperThemeZip).

    python build_themes.py "<ColorThemes folder>" [DAW name ...]

For each recipe in styles.json "own_themes" it writes ColorThemes/ReaPersona - <DAW>.ReaperThemeZip: Default 7's layout, settings and images,
its grey panels tinted to that DAW's palette, mute/solo/arm/play/record in that DAW's colours, and the arrange, ruler, MIDI editor and
list colours from the recipe. Nothing of Default 7 ships with ReaPersona: only the recipes do, and the theme is made from your own copy.
Prints "<code>\n<what was written>".
"""
import colorsys, io, json, os, re, sys, zipfile

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MARKERS = {(255, 0, 255), (255, 255, 0), (0, 0, 255)}  # (layout marker pixels in theme images: never recolour them)


def rgb(h):
    return int(h[1:3], 16), int(h[3:5], 16), int(h[5:7], 16)


def native(h):
    r, g, b = rgb(h)
    return r | g << 8 | b << 16


def tint_image(im, tint, gain, button=None):
    """Grey pixels take the palette's tint (and brightness gain); in a button image, coloured pixels take the button's colour."""
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    rgb_ = a[..., :3]
    mx, mn = rgb_.max(axis=2), rgb_.min(axis=2)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    keep = (a[..., 3] == 0)
    for m in MARKERS:
        keep |= np.all(rgb_ == m, axis=2)
    k = np.array(tint, np.float32) / (sum(tint) / 3.0 or 1.0)
    grey = (sat < 0.15) & ~keep
    lum = rgb_.mean(axis=2) * gain
    out = rgb_.copy()
    out[grey] = np.clip(lum[grey][:, None] * k[None, :], 0, 255)
    if button:
        colour = (sat >= 0.15) & ~keep
        if colour.any():  # (keep each pixel's brightness and shading, give it the button's hue)
            bh, bs, _ = colorsys.rgb_to_hsv(*(c / 255.0 for c in button))
            v = mx[colour] / 255.0
            s = np.maximum(sat[colour], bs * 0.85)
            out[colour] = np.array([colorsys.hsv_to_rgb(bh, si, vi) for si, vi in zip(s, v)], np.float32) * 255
    a[..., :3] = out
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def button_for(name, rec):
    n = name.lower()
    if "mute_on" in n:
        return rgb(rec["mute"])
    if "solo_on" in n or "solo_defeat" in n:
        return rgb(rec["solo"])
    if "recarm_on" in n or "recarm_auto_on" in n or "record_on" in n or "rec_on" in n:
        return rgb(rec["record"])
    if "transport_play_on" in n or "play_on" in n:
        return rgb(rec["play"])
    return None


def colours(theme_text, rec):
    p = rec["palette"]
    bg, odd, even, sel, win, text, ruler, rtext, grid, cursor, play, item, accent, mbg, note = map(native, p)
    set_ = {
        "col_arrangebg": bg, "col_tr1_bg": odd, "col_tr2_bg": even, "selcol_tr1_bg": sel, "selcol_tr2_bg": sel,
        "col_main_bg2": win, "col_mixerbg": win, "col_tracklistbg": win, "col_trans_bg": win, "docker_bg": win, "col_transport_editbk": win,
        "col_main_text2": text, "col_tcp_text": text, "col_tcp_textsel": text, "col_trans_fg": text, "docker_text": text,
        "col_tl_bg": ruler, "col_tl_fg": rtext, "col_tl_fg2": rtext, "region_lane_bg": ruler, "marker_lane_bg": ruler, "ts_lane_bg": ruler,
        "col_gridlines": grid, "col_gridlines2": grid, "col_gridlines3": grid, "col_tr1_divline": win, "col_tr2_divline": win,
        "col_cursor": cursor, "col_cursor2": cursor, "playcursor_color": play, "col_tr1_itembgsel": item, "col_tr2_itembgsel": item,
        "col_tl_bgsel": accent, "col_tl_bgsel2": accent, "areasel_fill": accent, "areasel_outline": accent,
        "midi_trackbg1": mbg, "midi_trackbg2": mbg, "midi_trackbg_outer1": win, "midi_trackbg_outer2": win, "midi_rulerbg": ruler,
        "midi_rulerfg": rtext, "midi_notebg": note, "col_mi_bg": mbg, "col_mi_bg2": mbg, "midi_editcurs": cursor,
        "genlist_bg": win, "genlist_fg": text, "genlist_selbg": sel, "genlist_selfg": text,
    }
    out = []
    for line in theme_text.splitlines():
        k = line.split("=", 1)[0]
        out.append("%s=%d" % (k, set_[k]) if "=" in line and k in set_ else line)
    return "\n".join(out) + "\n"


def build(colorthemes, name, rec):
    src = zipfile.ZipFile(os.path.join(colorthemes, "Default_7.0.ReaperThemeZip"))
    out_name = "ReaPersona - %s.ReaperThemeZip" % name
    folder = "ReaPersona - %s" % name
    tint, gain = rgb(rec["tint"]), float(rec.get("gain", 1.0))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
        for info in src.infolist():
            if info.is_dir():
                continue
            rel = info.filename.split("/", 1)[1] if "/" in info.filename else info.filename
            data = src.read(info)
            low = rel.lower()
            if low.endswith(".reapertheme"):
                text = colours(data.decode("utf-8", "replace").replace("\r\n", "\n"), rec)
                text, n = re.subn(r"(?m)^ui_img=.*$", "ui_img=" + folder, text)  # (its images are in our folder, not Default 7's)
                if not n:
                    text = text.replace("[REAPER]", "[REAPER]\nui_img=" + folder, 1) if "[REAPER]" in text else text + "\n[REAPER]\nui_img=" + folder + "\n"
                out.writestr(folder + ".ReaperTheme", text)  # (at the top of the zip, named as its image folder)
                continue
            if low.endswith(".png") and not os.path.basename(low).startswith("toolbar_"):
                try:
                    im = tint_image(Image.open(io.BytesIO(data)), tint, gain, button_for(os.path.basename(low), rec))
                    b = io.BytesIO(); im.save(b, "PNG"); data = b.getvalue()
                except Exception:
                    pass
            out.writestr(folder + "/" + rel, data)
    open(os.path.join(colorthemes, out_name), "wb").write(buf.getvalue())
    return out_name


def main():
    colorthemes = sys.argv[1]
    if not os.path.exists(os.path.join(colorthemes, "Default_7.0.ReaperThemeZip")):
        print("1\nREAPER's Default_7.0.ReaperThemeZip isn't in " + colorthemes); return
    recipes = json.load(open(os.path.join(HERE, "styles.json"), encoding="utf-8")).get("own_themes", {})
    user = os.path.join(HERE, "user_themes.json")  # (recipes you imported, e.g. from an Ableton Live theme)
    if os.path.exists(user):
        recipes.update(json.load(open(user, encoding="utf-8")))
    want = sys.argv[2:] or list(recipes)
    made = [build(colorthemes, n, recipes[n]) for n in want if n in recipes]
    print("0\n" + "\n".join(made))


if __name__ == "__main__":
    main()
