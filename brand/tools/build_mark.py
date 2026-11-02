#!/usr/bin/env python3
"""Build the rehalo mark: SVG logos (wordmark outlined, no font needed) + PNG renders + iOS app icon.

Usage:
    python3 build_mark.py /path/to/Unbounded[wght].ttf

Needs `fonttools` and `uharfbuzz` (pip), and `rsvg-convert` + ImageMagick `magick` on PATH for PNGs.
The font is Unbounded (SIL OFL 1.1): https://github.com/google/fonts/tree/main/ofl/unbounded
"""
import math
import pathlib
import subprocess
import sys

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
BRAND = ROOT / "brand"
APPICON = ROOT / "clients/ios/Sources/SmartHalo2App/Assets.xcassets/AppIcon.appiconset"
LAUNCH = ROOT / "clients/ios/Sources/SmartHalo2App/Assets.xcassets/LaunchRing.imageset"

NIGHT, PAPER, LIME = "#0B0D10", "#F2F4F7", "#C6FF3D"
WEIGHT = 800          # Unbounded ExtraBold
TRACKING = -0.03      # em
TEXT = "rehalo"
ACCENT_CHARS = 2      # "re" takes the accent colour

# Spark (variant A), drawn in a 200-unit box: a ring with a gap, the spark sits in the gap.
ANGLE, GAP, STROKE, DOT, R = 45, 60, 26, 15, 70
VIS_MIN, VIS_MAX = 100 - R - STROKE / 2, 100 + R + STROKE / 2   # visible extent inside the box


def pt(a, r):
    t = math.radians(a)
    return 100 + r * math.sin(t), 100 - r * math.cos(t)


def symbol(x, y, size, ring, dot):
    """Symbol whose 200-unit box has its top-left at (x, y)."""
    (sx, sy), (ex, ey), (dx, dy) = pt(ANGLE + GAP / 2, R), pt(ANGLE - GAP / 2, R), pt(ANGLE, R)
    return (
        f'<g transform="translate({x:.2f} {y:.2f}) scale({size / 200:.5f})">'
        f'<path d="M{sx:.2f} {sy:.2f}A{R} {R} 0 1 1 {ex:.2f} {ey:.2f}" fill="none" stroke="{ring}" '
        f'stroke-width="{STROKE}" stroke-linecap="round"/>'
        f'<circle cx="{dx:.2f}" cy="{dy:.2f}" r="{DOT}" fill="{dot}"/></g>'
    )


class Wordmark:
    def __init__(self, font_path):
        data = pathlib.Path(font_path).read_bytes()
        hb_font = hb.Font(hb.Face(data))
        hb_font.set_variations({"wght": WEIGHT})
        buf = hb.Buffer()
        buf.add_str(TEXT)
        buf.guess_segment_properties()
        hb.shape(hb_font, buf, {"kern": True, "liga": True})
        inst = instantiateVariableFont(TTFont(font_path), {"wght": WEIGHT})
        self.upm = inst["head"].unitsPerEm
        self.glyphs = inst.getGlyphSet()
        order = inst.getGlyphOrder()
        self.run = [(order[i.codepoint], i.cluster, p.x_advance, p.x_offset, p.y_offset)
                    for i, p in zip(buf.glyph_infos, buf.glyph_positions)]

    def draw(self, x, baseline, fs, base, accent):
        """Return (svg, (xmin, ymin, xmax, ymax)) for the outlined wordmark."""
        s = fs / self.upm
        cursor, parts, box = 0.0, [], [math.inf, math.inf, -math.inf, -math.inf]
        for name, cluster, adv, xo, yo in self.run:
            m = (s, 0, 0, -s, x + (cursor + xo) * s, baseline - yo * s)
            sp, bp = SVGPathPen(self.glyphs), BoundsPen(self.glyphs)
            self.glyphs[name].draw(TransformPen(sp, m))
            self.glyphs[name].draw(TransformPen(bp, m))
            if bp.bounds:
                b = bp.bounds
                box = [min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3])]
            fill = accent if cluster < ACCENT_CHARS else base
            parts.append(f'<path fill="{fill}" d="{sp.getCommands()}"/>')
            cursor += adv + TRACKING * self.upm
        return "".join(parts), tuple(box)


def svg_doc(body, box, bg=None):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    rect = f'<rect x="{x0:.2f}" y="{y0:.2f}" width="{w:.2f}" height="{h:.2f}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.2f} {y0:.2f} {w:.2f} {h:.2f}" '
            f'width="{w:.0f}" height="{h:.0f}" role="img" aria-label="rehalo">'
            f'<title>rehalo</title>{rect}{body}</svg>\n')


def horizontal(wm, ring, dot, base, accent, fs=100):
    _, tb = wm.draw(0, 0, fs, base, accent)
    size = 1.2 * fs                       # symbol box
    vis = size * (VIS_MAX - VIS_MIN) / 200
    gap = 0.34 * fs                       # ring edge → first letter
    text_x = vis + gap - tb[0]
    cy = (tb[1] + tb[3]) / 2
    sym_x, sym_y = -VIS_MIN * size / 200, cy - size / 2
    text, tb = wm.draw(text_x, 0, fs, base, accent)
    box = (0, min(tb[1], cy - vis / 2), tb[2], max(tb[3], cy + vis / 2))
    return symbol(sym_x, sym_y, size, ring, dot) + text, box


def stacked(wm, ring, dot, base, accent, fs=100):
    _, tb = wm.draw(0, 0, fs, base, accent)
    vis = 2.45 * fs
    size = vis * 200 / (VIS_MAX - VIS_MIN)
    gap = 0.7 * fs
    tw = tb[2] - tb[0]
    width = max(tw, vis)
    text_x = (width - tw) / 2 - tb[0]
    baseline = vis + gap - tb[1]
    text, tb = wm.draw(text_x, baseline, fs, base, accent)
    sx = (width - vis) / 2 - VIS_MIN * size / 200
    sy = -VIS_MIN * size / 200
    return symbol(sx, sy, size, ring, dot) + text, (0, 0, width, tb[3])


def wordmark_only(wm, base, accent, fs=100):
    text, tb = wm.draw(0, 0, fs, base, accent)
    return text, tb


def symbol_only(ring, dot):
    return symbol(0, 0, 200, ring, dot), (VIS_MIN, VIS_MIN, VIS_MAX, VIS_MAX)


def app_icon(ring, dot, bg):
    size = 1024 * 112 / 168               # same proportion as the mark sheet's app icon
    o = (1024 - size) / 2
    rect = f'<rect width="1024" height="1024" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'{rect}{symbol(o, o, size, ring, dot)}</svg>\n')


def dead_ring():
    """The launch screen: the ring's 24 LED segments, dim (the boot sweep starts from this)."""
    segs = []
    for i in range(24):
        (sx, sy), (ex, ey) = pt(15 * i + 1.5, R), pt(15 * i + 13.5, R)
        segs.append(f'<path d="M{sx:.2f} {sy:.2f}A{R} {R} 0 0 1 {ex:.2f} {ey:.2f}"/>')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="150" height="150">'
            f'<g fill="none" stroke="{PAPER}" stroke-opacity="0.14" stroke-width="{STROKE}">'
            f'{"".join(segs)}</g></svg>\n')


def render(svg_path, png_path, height=None, opaque=False):
    args = ["rsvg-convert", str(svg_path), "-o", str(png_path)]
    if height:
        args[1:1] = ["-h", str(height)]
    subprocess.run(args, check=True)
    if opaque:
        subprocess.run(["magick", str(png_path), "-background", NIGHT, "-alpha", "remove",
                        "-alpha", "off", str(png_path)], check=True)


def main(font_path):
    wm = Wordmark(font_path)
    svg_dir, png_dir = BRAND / "svg", BRAND / "png"
    svg_dir.mkdir(parents=True, exist_ok=True)
    png_dir.mkdir(parents=True, exist_ok=True)

    # (suffix, ring, dot, base text, accent text): colour = for dark grounds; night/paper = one colour.
    schemes = [("", PAPER, LIME, PAPER, LIME), ("-night", NIGHT, NIGHT, NIGHT, NIGHT),
               ("-paper", PAPER, PAPER, PAPER, PAPER)]
    outputs = []
    for suffix, ring, dot, base, accent in schemes:
        outputs += [
            (f"rehalo-horizontal{suffix}", *horizontal(wm, ring, dot, base, accent)),
            (f"rehalo-stacked{suffix}", *stacked(wm, ring, dot, base, accent)),
            (f"rehalo-wordmark{suffix}", *wordmark_only(wm, base, accent)),
            (f"rehalo-symbol{suffix}", *symbol_only(ring, dot)),
        ]
    for name, body, box in outputs:
        path = svg_dir / f"{name}.svg"
        path.write_text(svg_doc(body, box))
        render(path, png_dir / f"{name}.png", height=512)

    icon = svg_dir / "rehalo-app-icon.svg"
    icon.write_text(app_icon(PAPER, LIME, NIGHT))
    render(icon, png_dir / "rehalo-app-icon.png", opaque=True)

    # iOS 18 appearances: any (opaque), dark (transparent, system draws the dark ground), tinted (grayscale).
    APPICON.mkdir(parents=True, exist_ok=True)
    render(icon, APPICON / "AppIcon.png", opaque=True)
    for name, svg in [("AppIcon-dark", app_icon(PAPER, LIME, None)),
                      ("AppIcon-tinted", app_icon("#FFFFFF", "#FFFFFF", "#000000"))]:
        tmp = BRAND / f".{name}.svg"
        tmp.write_text(svg)
        render(tmp, APPICON / f"{name}.png")
        tmp.unlink()

    # Launch screen image (150 pt, centred by iOS on the LaunchBackground colour).
    LAUNCH.mkdir(parents=True, exist_ok=True)
    tmp = BRAND / ".launch-ring.svg"
    tmp.write_text(dead_ring())
    for scale in (2, 3):
        render(tmp, LAUNCH / f"LaunchRing@{scale}x.png", height=150 * scale)
    tmp.unlink()
    print(f"wrote {len(outputs) + 1} SVGs to {svg_dir}, PNGs to {png_dir}, app icon to {APPICON}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
