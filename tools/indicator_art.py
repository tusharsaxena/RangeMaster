#!/usr/bin/env python3
"""tools/indicator_art.py: draw the indicator element's shape x style art.

Writes media/textures/indicators/<shape>_<style>.tga for every shape and style below: 128x128,
uncompressed 32-bit (image type 2, 8 alpha bits, top-left origin), white/grayscale RGB with real
alpha. The client tints it with SetVertexColor, so the gray is the shading the band color is
multiplied by and the alpha is the shape.

Every tile is drawn at 4x and box-filtered down, premultiplied, so the edges are clean and a
transparent pixel never carries a dark color into the client's bilinear filter. The shape sits at
about 70% of the box (radius 0.35) so the glowing and neon halos fit inside it; the script fails if
any tile's border is not transparent.

Deterministic: the same Pillow gives the same bytes on every run (no randomness, no timestamps,
a hand-written TGA header). Dev-only (.pkgmeta ignores tools/). Run from the repo root:

    python3 tools/indicator_art.py            # writes the tiles
    python3 tools/indicator_art.py --sheet x.png   # also a contact sheet, for eyeballing

Needs Pillow only (DEPENDENCIES.md, Release / assets).
"""

import math
import os
import struct
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageMath

SIZE = 128              # the shipped tile
SS = 4                  # supersampling factor
W = SIZE * SS           # the working canvas
C = W / 2.0             # its center
R = 0.35 * W            # the shape's radius

SHAPES = ["dot", "ring", "square", "diamond", "triangle", "hexagon", "star"]
STYLES = ["plain", "matte", "glossy", "glowing", "neon", "gem"]

OUT_DIR = os.path.join("media", "textures", "indicators")


# --------------------------------------------------------------------------------------------
# Per-pixel math on float images. ImageMath.eval is renamed unsafe_eval in newer Pillow.
# --------------------------------------------------------------------------------------------

_EVAL = getattr(ImageMath, "unsafe_eval", None) or ImageMath.eval


def fx(expr, **images):
    """Evaluate `expr` over float ("F") images; the result is an F image."""
    out = _EVAL(expr, **{k: (v if v.mode == "F" else v.convert("F")) for k, v in images.items()})
    return out if out.mode == "F" else out.convert("F")


def const(v):
    return Image.new("F", (W, W), float(v))


def clamp(img, lo=0.0, hi=255.0):
    return fx("min(max(a, %f), %f)" % (lo, hi), a=img)


def blur(img, radius):
    """A Gaussian blur. Pillow blurs 8-bit images only; at 4x that precision is plenty."""
    if img.mode != "L":
        img = clamp(img).convert("L")
    return img.filter(ImageFilter.GaussianBlur(radius)).convert("F")


def erode(mask, r):
    """The mask shrunk by about r working pixels: a blur thresholded high (corners round off)."""
    b = blur(mask, max(r / 1.64, 0.5))
    # A straight edge blurred with sigma s reads 95% at 1.64 s inside: ramp around that.
    return clamp(fx("(b - 0.93 * 255.0) * (255.0 / (0.05 * 255.0))", b=b))


def _axis(horizontal):
    """A float field holding the pixel's x (or y) coordinate, 0..W."""
    line = Image.new("F", (W, 1) if horizontal else (1, W))
    px = line.load()
    for i in range(W):
        if horizontal:
            px[i, 0] = i + 0.5
        else:
            px[0, i] = i + 0.5
    return line.resize((W, W), Image.NEAREST)


X = _axis(True)
Y = _axis(False)


def radial(cx, cy, radius):
    """Distance from (cx, cy) over `radius`, unclamped: 0 at the point, 1 at the radius."""
    return fx("(((x - %f) * (x - %f) + (y - %f) * (y - %f)) ** 0.5) / %f"
              % (cx, cx, cy, cy, radius), x=X, y=Y)


def vertical(top, bottom):
    """0 at y = top, 1 at y = bottom, clamped."""
    return clamp(fx("(y - %f) / %f" % (top, bottom - top), y=Y), 0.0, 1.0)


# --------------------------------------------------------------------------------------------
# Shapes: a white-on-black L mask at the working size.
# --------------------------------------------------------------------------------------------

def _poly(points):
    img = Image.new("L", (W, W), 0)
    ImageDraw.Draw(img).polygon([(C + x * R, C + y * R) for x, y in points], fill=255)
    return img


def _regular(n, radius, phase):
    return [(radius * math.cos(phase + 2 * math.pi * i / n), radius * math.sin(phase + 2 * math.pi * i / n))
            for i in range(n)]


def shape_mask(shape):
    img = Image.new("L", (W, W), 0)
    d = ImageDraw.Draw(img)
    if shape == "dot":
        d.ellipse([C - R, C - R, C + R, C + R], fill=255)
    elif shape == "ring":
        d.ellipse([C - R, C - R, C + R, C + R], fill=255)
        r2 = R * 0.58
        d.ellipse([C - r2, C - r2, C + r2, C + r2], fill=0)
    elif shape == "square":
        h = R * 0.86
        d.rounded_rectangle([C - h, C - h, C + h, C + h], radius=R * 0.14, fill=255)
    elif shape == "diamond":
        img = _poly([(0, -1.08), (1.08, 0), (0, 1.08), (-1.08, 0)])
    elif shape == "triangle":
        # Point up, the centroid on the box's center so it sits level with the others.
        img = _poly([(0, -1.08), (1.04, 0.72), (-1.04, 0.72)])
        img = img.transform(img.size, Image.AFFINE, (1, 0, 0, 0, 1, -0.06 * R), Image.NEAREST)
    elif shape == "hexagon":
        img = _poly(_regular(6, 1.0, -math.pi / 2))
    elif shape == "star":
        pts = []
        for i in range(10):
            rad = 1.08 if i % 2 == 0 else 1.08 * 0.47
            a = -math.pi / 2 + math.pi * i / 5
            pts.append((rad * math.cos(a), rad * math.sin(a) + 0.04))
        img = _poly(pts)
    else:
        raise ValueError(shape)
    return img


# --------------------------------------------------------------------------------------------
# Styles: each returns (gray, alpha) as F images 0..255 at the working size.
# --------------------------------------------------------------------------------------------

def rim(mask, width):
    """0 deep inside, rising to 1 at the shape's edge, over about `width` working pixels."""
    return clamp(fx("(m - b) / 127.5", m=mask, b=blur(mask, width)), 0.0, 1.0)


def style_plain(m):
    return const(255), m.convert("F")


def style_matte(m):
    # Soft radial light from the upper left, a dark rim, no highlight.
    r = clamp(radial(C - 0.28 * R, C - 0.32 * R, 1.75 * R), 0.0, 1.0)
    e = rim(m, 0.16 * R)
    g = fx("(248.0 - 92.0 * r) * (1.0 - 0.42 * e)", r=r, e=e)
    return g, m.convert("F")


def style_glossy(m):
    # A body darker toward the bottom, a faint bounce light at the bottom edge, and a white shine
    # clipped to the upper half.
    bbox = m.getbbox()
    top, bottom = bbox[1], bbox[3]
    t = vertical(top, bottom)
    e = rim(m, 0.12 * R)
    body = fx("(215.0 - 95.0 * t) * (1.0 - 0.30 * e) + 40.0 * t * t * e", t=t, e=e)
    sh = Image.new("L", (W, W), 0)
    cy = top + (bottom - top) * 0.30
    ImageDraw.Draw(sh).ellipse([C - 0.80 * R, cy - 0.40 * R, C + 0.80 * R, cy + 0.36 * R], fill=255)
    inner = erode(m, 0.10 * R)
    half = clamp(fx("(%f - y) * 255.0 / %f" % (top + (bottom - top) * 0.50, 0.06 * R), y=Y))
    shine = fx("s * i * h / (255.0 * 255.0)", s=blur(sh, 0.035 * R), i=inner, h=half)
    fade = vertical(top, top + (bottom - top) * 0.55)
    shine = fx("s * (1.0 - 0.55 * f)", s=shine, f=fade)
    g = fx("b + (255.0 - b) * s / 255.0", b=body, s=shine)
    return clamp(g), m.convert("F")


def style_glowing(m):
    # A solid, faintly shaded core and a soft halo around it.
    e = rim(m, 0.10 * R)
    core = fx("255.0 - 30.0 * e", e=e)
    # The halo is capped below full so the core's edge stays crisp inside it.
    halo = fx("min(0.45 * a + 0.70 * b, 115.0)", a=blur(m, 0.08 * R), b=blur(m, 0.17 * R))
    alpha = clamp(fx("max(m, h)", m=m, h=halo))
    # The halo is the tint's own color: full gray outside, the shaded core inside.
    g = fx("(c * m + 255.0 * (255.0 - m)) / 255.0", c=core, m=m)
    return g, alpha


def style_neon(m):
    # A bright outline, a blurred glow off it, a faint fill.
    inner = erode(m, 0.20 * R)
    line = clamp(fx("m - i", m=m, i=inner))
    glow = fx("1.10 * a + 0.60 * b", a=blur(line, 0.06 * R), b=blur(line, 0.14 * R))
    alpha = clamp(fx("max(max(l, g), 0.24 * i)", l=line, g=glow, i=inner))
    return const(255), alpha


def style_gem(m):
    # Two hard facets split on the falling diagonal (light upper left, dark lower right), each
    # graded a little, and a thin light edge.
    split = Image.new("L", (W, W), 0)
    ImageDraw.Draw(split).polygon([(0, 0), (W, 0), (0, W)], fill=255)   # upper-left half
    r = clamp(radial(C - 0.40 * R, C - 0.40 * R, 2.2 * R), 0.0, 1.0)
    light = fx("252.0 - 30.0 * r", r=r)
    dark = fx("150.0 - 35.0 * r", r=r)
    g = fx("(l * s + d * (255.0 - s)) / 255.0", l=light, d=dark, s=split)
    edge = clamp(fx("m - i", m=m, i=erode(m, 0.07 * R)))
    g = fx("g + (240.0 - g) * e / 255.0", g=g, e=edge)
    return clamp(g), m.convert("F")


STYLE_FN = {
    "plain": style_plain, "matte": style_matte, "glossy": style_glossy,
    "glowing": style_glowing, "neon": style_neon, "gem": style_gem,
}


# --------------------------------------------------------------------------------------------
# Downsampling and writing.
# --------------------------------------------------------------------------------------------

def downsample(gray, alpha):
    """Premultiplied box filter to SIZE; transparent pixels take their neighbors' gray."""
    p = fx("g * a / 255.0", g=gray, a=alpha).resize((SIZE, SIZE), Image.BOX)
    a = alpha.resize((SIZE, SIZE), Image.BOX)
    g = fx("p * 255.0 / max(a, 0.001)", p=p, a=a)
    # Bleed: where alpha is 0, the blurred premultiplied gray (else white).
    pb, ab = blur(p, 3), blur(a, 3)
    gb = fx("(p * 255.0 / max(a, 0.001)) * (a > 0.01) + 255.0 * (a <= 0.01)", p=pb, a=ab)
    g = fx("g * (a > 0.5) + b * (a <= 0.5)", g=g, b=gb, a=a)
    return clamp(g).convert("L"), clamp(a).convert("L")


def to_tga(gray, alpha):
    """An uncompressed 32-bit TGA, top-left origin, 8 alpha bits."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    g, a = gray.tobytes(), alpha.tobytes()
    body = bytearray(SIZE * SIZE * 4)
    body[0::4] = g
    body[1::4] = g
    body[2::4] = g
    body[3::4] = a
    return header + bytes(body)


def check_border(alpha, name):
    px = alpha.load()
    worst = 0
    for i in range(SIZE):
        worst = max(worst, px[i, 0], px[i, SIZE - 1], px[0, i], px[SIZE - 1, i])
    if worst > 1:
        sys.exit("%s: its border is not transparent (alpha %d); the art clips" % (name, worst))


def render(shape, style):
    m = shape_mask(shape)
    gray, alpha = STYLE_FN[style](m)
    gray, alpha = downsample(gray, alpha)
    check_border(alpha, shape + "_" + style)
    return gray, alpha


def contact_sheet(tiles, path):
    """Each tile large on dark and light, and small (16 px) tinted, for checking by eye."""
    tints = [(64, 220, 96), (255, 200, 40), (235, 64, 52)]
    cell = SIZE + 8
    small = 16
    sheet = Image.new("RGB", (cell * len(STYLES) * 2 + 8, cell * len(SHAPES) + 8), (24, 24, 28))
    for row, shape in enumerate(SHAPES):
        for col, style in enumerate(STYLES):
            gray, alpha = tiles[(shape, style)]
            tint = tints[(row + col) % len(tints)]
            rgb = Image.merge("RGB", [gray.point(lambda v, c=c: v * c // 255) for c in tint])
            x, y = 8 + col * cell, 8 + row * cell
            bg = (24, 24, 28) if (row + col) % 2 == 0 else (90, 90, 96)
            sheet.paste(Image.new("RGB", (SIZE, SIZE), bg), (x, y))
            sheet.paste(rgb, (x, y), alpha)
            # The same tile at 16 px and 24 px, tinted, on the right half.
            sx = 8 + (len(STYLES) + col) * cell
            sheet.paste(Image.new("RGB", (SIZE, SIZE), (40, 40, 44)), (sx, y))
            for k, sz in enumerate((small, 24, 12)):
                s_rgb = rgb.resize((sz, sz), Image.BILINEAR)
                s_a = alpha.resize((sz, sz), Image.BILINEAR)
                big = s_rgb.resize((sz * 3, sz * 3), Image.NEAREST)
                big_a = s_a.resize((sz * 3, sz * 3), Image.NEAREST)
                sheet.paste(big, (sx + 4 + [0, 52, 0][k], y + 4 + [0, 0, 76][k]), big_a)
    sheet.save(path)


def main(argv):
    sheet = None
    if "--sheet" in argv:
        sheet = argv[argv.index("--sheet") + 1]
    os.makedirs(OUT_DIR, exist_ok=True)
    tiles = {}
    for shape in SHAPES:
        for style in STYLES:
            gray, alpha = render(shape, style)
            tiles[(shape, style)] = (gray, alpha)
            with open(os.path.join(OUT_DIR, "%s_%s.tga" % (shape, style)), "wb") as fh:
                fh.write(to_tga(gray, alpha))
    if sheet:
        contact_sheet(tiles, sheet)
    print("wrote %d tiles to %s" % (len(tiles), OUT_DIR))


if __name__ == "__main__":
    main(sys.argv[1:])
