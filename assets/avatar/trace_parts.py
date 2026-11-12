# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "potracer", "scipy"]
# ///
"""Trace the painter's animal parts sheets into the avatar's SVG parts.

Each sheet in sheets/<animal>.png follows template.png: a head top left, a body
top right, a pair of legs bottom left and a pair of feet bottom right, on white.
Every pixel is snapped to PALETTE, the outline is redrawn at the house stroke
weight, and each colour is traced with potrace and placed in the part's slot of
the 130x145 avatar. The main fill becomes the part's colour variable.

Sheets are stored snapped to PALETTE, which is all the tracer reads; a fresh
painter sheet is snapped in place on its first run.

To draw a new animal, give the painter template.png and an existing sheet as
references, and ask it to fill each dashed box with one part and leave the boxes
out: a front-facing head ending in a short neck stub, a body with no neck or
legs, each leg with no foot, and each foot with its ankle at the top of its box
and toes along the bottom. Every main fill is #2dd4bf, outlines are #111827,
patches and eye whites are white, and beaks or noses use the PALETTE accents.
New animals go at the end of Flamingo.Avatar's list, since saved avatars store
each part's index.

Run from the repository root:  uv run assets/avatar/trace_parts.py
Writes priv/avatar_parts/<animal>/{head,body,legs,feet}.svg.
"""

from pathlib import Path

import numpy as np
import potrace
from PIL import Image
from scipy import ndimage as ndi

ROOT = Path(__file__).resolve().parents[2]
SHEETS = ROOT / "assets/avatar/sheets"
OUT = ROOT / "priv/avatar_parts"

INK = "#111827"
# White, outline, the main fill (any part colour works; the painter draws it as
# #2dd4bf), then fixed accents such as beaks and noses.
PALETTE = ["#ffffff", INK, "#2dd4bf", "#fb923c", "#f472b6"]
PART_VAR = {"head": "var(--h)", "body": "var(--b)", "legs": "var(--l)", "feet": "var(--f)"}

# Where each piece sits in the 130x145 avatar: centre x, then its top, bottom or
# centre y, the box it is scaled to fit, and its outline width. stretch lets a
# piece be squashed up to that much to fill its box, since the painter only
# roughly follows the template's proportions. core centres a piece on its main
# shape, ignoring thin bits such as tails.
HEAD = dict(cx=63, bottom=70, w=74, h=70, stroke=4)
BODY = dict(cx=61, cy=84, w=92, h=50, stroke=4, stretch=1.5, core=True)
LEGS = [dict(cx=46, top=94, w=22, h=42, stroke=3.5), dict(cx=78, top=94, w=22, h=42, stroke=3.5)]
FEET = [dict(cx=x, top=127, w=28, h=17, stroke=3, stretch=1.5) for x in (42, 83)]


def classify(img):
    pal = np.array([[int(c[i : i + 2], 16) for i in (1, 3, 5)] for c in PALETTE])
    return ((img.astype(np.int32)[:, :, None, :] - pal[None, None]) ** 2).sum(-1).argmin(-1)


def snap_in_place(path, labels):
    snapped = Image.fromarray(labels.astype(np.uint8), mode="P")
    snapped.putpalette([int(c[i : i + 2], 16) for c in PALETTE for i in (1, 3, 5)])
    snapped.save(path, optimize=True)


def trace(mask, transform):
    # Blur away the painter's marker wobble so potrace fits long smooth curves.
    mask = ndi.gaussian_filter(mask.astype(np.float32), 4) > 0.5
    curves = potrace.Bitmap(~mask).trace(turdsize=8, alphamax=1.0, opticurve=True, opttolerance=0.6)
    num = lambda v: f"{round(v, 1):g}" if abs(v) >= 0.05 else "0"
    fmt = lambda p: "%s %s" % tuple(num(v) for v in transform(p.x, p.y))
    out = []
    for curve in curves:
        out.append("M" + fmt(curve.start_point))
        for seg in curve.segments:
            if seg.is_corner:
                out.append("L" + fmt(seg.c) + " " + fmt(seg.end_point))
            else:
                out.append("C" + fmt(seg.c1) + " " + fmt(seg.c2) + " " + fmt(seg.end_point))
        out.append("Z")
    return "".join(out)


def render_piece(labels, region, slot, fill_var):
    """Trace one piece (a head, a body, one leg or one foot) into SVG paths."""
    # Crop with padding so the outline has room to grow.
    pad = 40
    labels, region = np.pad(labels, pad), np.pad(region, pad)
    ys, xs = np.nonzero(region)
    lab = labels[ys.min() - pad : ys.max() + pad, xs.min() - pad : xs.max() + pad]
    reg = region[ys.min() - pad : ys.max() + pad, xs.min() - pad : xs.max() + pad]
    bh, bw = ys.max() - ys.min(), xs.max() - xs.min()
    scale = min(slot["w"] / bw, slot["h"] / bh)
    k = slot.get("stretch", 1.0)
    zy, zx = min(slot["h"] / bh, scale * k) / scale, min(slot["w"] / bw, scale * k) / scale
    if (zy, zx) != (1.0, 1.0):
        # Zoom each colour smoothly and keep the strongest, so edges stay clean.
        lab = np.argmax([ndi.zoom((lab == i).astype(np.float32), (zy, zx), order=1) for i in range(len(PALETTE))], axis=0)
        reg = ndi.zoom(reg.astype(np.float32), (zy, zx), order=1) > 0.5
    ys, xs = np.nonzero(reg)
    bh, bw = ys.max() - ys.min(), xs.max() - xs.min()

    sil = ndi.binary_fill_holes(reg)
    black = sil & (lab == 1)
    inner = sil & ~black
    # Redraw the outline at the slot's stroke weight so every animal matches. For a
    # band w px wide, the median distance to its edge is w/4.
    width = 4 * float(np.median(ndi.distance_transform_edt(black)[black]))
    r = (slot["stroke"] / scale - width) / 2
    if r > 0:
        sil = sil | (ndi.distance_transform_edt(~sil) <= r)
        fill_area = ndi.distance_transform_edt(inner) > r
    else:
        sil = ndi.distance_transform_edt(sil) > -r
        fill_area = inner | (ndi.distance_transform_edt(~inner) <= -r)
    fill_area &= sil
    # Each filled pixel takes the colour of the nearest original filled pixel.
    _, (iy, ix) = ndi.distance_transform_edt(~inner, return_indices=True)
    near = lab[iy, ix]

    ox = slot["cx"] - bw * scale / 2
    if slot.get("core"):
        # The deepest points inside the silhouette lie in the main shape, never in a tail.
        depth = ndi.distance_transform_edt(sil)
        cxs = np.nonzero(depth >= 0.85 * depth.max())[1]
        ox = slot["cx"] - ((cxs.min() + cxs.max()) / 2 - xs.min()) * scale
    if "bottom" in slot:
        oy = slot["bottom"] - bh * scale
    elif "top" in slot:
        oy = slot["top"]
    else:
        oy = slot["cy"] - bh * scale / 2
    transform = lambda x, y: (ox + (x - xs.min()) * scale, oy + (y - ys.min()) * scale)

    # Big white areas such as belly patches become a tint of the part colour; small
    # ones such as eye whites stay white.
    white = fill_area & (near == 0)
    whites, n = ndi.label(white)
    areas = ndi.sum(white, whites, range(1, n + 1)) if n else []
    tint = np.isin(whites, [i + 1 for i, a in enumerate(areas) if a > 0.15 * fill_area.sum()])
    layers = [
        (sil, f'fill="{INK}"'),
        (fill_area & ((near == 2) | tint), f'fill="{fill_var}"'),
        (tint, 'fill="white" fill-opacity="0.35"'),
        (white & ~tint, 'fill="white"'),
    ] + [(fill_area & (near == i), f'fill="{c}"') for i, c in enumerate(PALETTE) if i > 2]
    return [
        f'<path d="{trace(layer, transform)}" {attrs} fill-rule="evenodd"/>'
        for layer, attrs in layers
        if layer.sum() >= 30
    ]


def trace_sheet(path):
    image = Image.open(path)
    labels = classify(np.array(image.convert("RGB")))
    if image.mode != "P":
        snap_in_place(path, labels)

    ink = labels != 0
    comps, n = ndi.label(ink)
    sizes = ndi.sum(ink, comps, range(1, n + 1))
    h, w = ink.shape
    pieces = {"head": [], "body": [], "legs": [], "feet": []}
    for c in (i + 1 for i, s in enumerate(sizes) if s > 0.001 * ink.size):
        cy, cx = ndi.center_of_mass(comps == c)
        pieces[list(pieces)[(cy > h / 2) * 2 + (cx > w / 2)]].append((cx, comps == c))

    out = OUT / path.stem
    out.mkdir(parents=True, exist_ok=True)
    for part, found in pieces.items():
        masks = [m for _, m in sorted(found, key=lambda p: p[0])]
        if part in ("head", "body"):
            slots = [(np.logical_or.reduce(masks), HEAD if part == "head" else BODY)]
        else:
            assert len(masks) == 2, f"{path.name} {part}: expected a left and right piece, found {len(masks)}"
            slots = list(zip(masks, LEGS if part == "legs" else FEET))
        paths = [p for mask, slot in slots for p in render_piece(labels, mask, slot, PART_VAR[part])]
        (out / f"{part}.svg").write_text("\n".join(paths) + "\n")
    print(f"{path.stem}: traced")


for sheet in sorted(SHEETS.glob("*.png")):
    trace_sheet(sheet)
