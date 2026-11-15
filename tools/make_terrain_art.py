#!/usr/bin/env python3
"""Repaint the placeholder rows of public/images/terrainsprites.png.

The original sheet shipped rows 5-7 (Hill, ForestHill, Mountain) as unfinished
placeholders with the words "Hill", "ForestHill" and "Mountain" painted in red
on flat grass. Now that the world generator produces those terrains on roughly
a fifth of all tiles, this script draws real tiles for them, reusing the grass
and tree art already in the sheet so they match the rest of the set.

Run it from the repo root (needs Pillow and numpy):

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install pillow numpy
    /tmp/venv/bin/python tools/make_terrain_art.py

It reads rows 1-4 (Plain, Forest, Lake/Sea) and rewrites rows 5-7, so running it
on an already-repainted sheet gives the same result. Output is deterministic.
"""
import sys
import numpy as np
from PIL import Image, ImageDraw

SHEET = 'public/images/terrainsprites.png'
T = 128                      # tile size in pixels
ROW_HILL, ROW_FORESTHILL, ROW_MOUNTAIN = 4, 5, 6
SS = 4                       # supersampling for smooth shape edges

rng = np.random.default_rng(1337)
sheet = Image.open(SHEET).convert('RGBA')


def cell(col, row):
    return sheet.crop((col * T, row * T, (col + 1) * T, (row + 1) * T))


def shape_mask(draw_fn):
    """Draw a shape at SS x resolution and shrink it: an anti-aliased 0..1 mask."""
    big = Image.new('L', (T * SS, T * SS), 0)
    draw_fn(ImageDraw.Draw(big))
    return np.asarray(big.resize((T, T), Image.LANCZOS), dtype=np.float32) / 255.0


def diamond_top_face():
    """The walkable top surface of a tile: a diamond (apex y=40, widest y=72..88)."""
    ys, xs = np.mgrid[0:T, 0:T]
    return ((np.abs(xs - 64) / 64.0 + np.abs(ys - 72) / 32.0) <= 1.0) & (ys <= 104)


def composite(base_rgba, layer_rgb, mask):
    out = np.asarray(base_rgba, dtype=np.float32).copy()
    m = mask[..., None]
    out[..., :3] = out[..., :3] * (1 - m) + layer_rgb * m
    out[..., 3] = np.maximum(out[..., 3], mask * 255)
    return out


def to_image(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def shade(rgb, light):
    return np.clip(rgb * light[..., None], 0, 255)


# ---- Hill: a grassy dome -----------------------------------------------------
def make_hill(variant):
    base = cell(variant, 0)                       # Plain tile: grass top + soil sides
    arr = np.asarray(base, dtype=np.float32)
    ys, xs = np.mgrid[0:T, 0:T]
    cx, cy = 64 + (variant % 2) * 2 - 1, 74
    rx, ry_up, ry_dn = 38, 36, 11   # footprint stays inside the diamond top face

    # ground shadow to the lower right of the dome, only on the top face
    shadow = shape_mask(lambda d: d.ellipse(
        [(cx - rx + 14) * SS, (cy - 14) * SS, (cx + rx + 16) * SS, (cy + 24) * SS], fill=255))
    face = diamond_top_face()
    arr[..., :3] *= (1 - 0.28 * shadow * face)[..., None]

    # dome footprint: upper half-ellipse (the rise) + lower half-ellipse (the slope toward us)
    def draw(d):
        d.pieslice([(cx - rx) * SS, (cy - ry_up) * SS, (cx + rx) * SS, (cy + ry_up) * SS], 180, 360, fill=255)
        d.pieslice([(cx - rx) * SS, (cy - ry_dn) * SS, (cx + rx) * SS, (cy + ry_dn) * SS], 0, 180, fill=255)
    mask = shape_mask(draw)

    # grass texture borrowed from another plain tile, shifted up so it reads as the hill's own
    tex = np.asarray(cell((variant + 1) % 4, 0), dtype=np.float32)[..., :3]
    tex = np.roll(tex, shift=(-18, 3 * variant - 4), axis=(0, 1))

    # lighting from the upper left, treating the dome as a half-ellipsoid
    nx = (xs - cx) / float(rx)
    ny = np.where(ys < cy, (ys - cy) / float(ry_up), (ys - cy) / float(ry_dn))
    nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
    light = np.clip(0.62 + 0.75 * (-0.45 * nx - 0.55 * ny + 0.70 * nz) / 1.0, 0.5, 1.28)
    # a soft shade where the front slope meets the ground, so it does not look pasted on
    edge = np.clip((1 - np.sqrt(nx ** 2 + ny ** 2)) * 5.0, 0, 1)
    light *= np.where(ny > 0, 0.90 + 0.10 * edge, 1.0)
    return composite(arr, shade(tex, light), mask)


# ---- ForestHill: a hill with trees from the Forest tiles ----------------------
def _dilate(m, r):
    for _ in range(r):
        n = m.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                n |= np.roll(np.roll(m, dy, 0), dx, 1)
        m = n
    return m


def close_holes(m, r):
    """Morphological closing: fills the small gaps left inside tree crowns."""
    return ~_dilate(~_dilate(m, r), r)


def tree_layer(forest_col, forest_row, plain_col):
    """Pull just the trees out of a Forest tile by differencing against plain grass."""
    forest = np.asarray(cell(forest_col, forest_row), dtype=np.float32)
    plain = np.asarray(cell(plain_col, 0), dtype=np.float32)
    diff = np.sqrt(((forest[..., :3] - plain[..., :3]) ** 2).sum(-1))
    ys = np.mgrid[0:T, 0:T][0]
    keep = (diff > 48) & (forest[..., 3] > 200) & (ys < 108)
    keep = close_holes(keep, 3) & (forest[..., 3] > 200) & (ys < 108)
    return forest, keep.astype(np.float32)


def make_foresthill(variant):
    arr = make_hill(variant)
    forest_col, forest_row = [(0, 1), (1, 1), (1, 2), (2, 2)][variant]
    forest, keep = tree_layer(forest_col, forest_row, variant)
    # trees stand on top of the dome; never lift them past the top edge of the tile
    top = int(np.nonzero(keep.any(axis=1))[0].min())
    lift = max(0, min(14, top - 1))
    forest = np.roll(forest, -lift, axis=0)
    keep = np.roll(keep, -lift, axis=0)
    keep[T - lift:, :] = 0
    return composite(to_image(arr), forest[..., :3], keep)


# ---- Mountain: grey rock with snow caps ---------------------------------------
def peak(apex, left, front, right, snow_y, seed):
    """One shaded pyramid: returns (rgb, alpha) layers for the full tile."""
    r = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:T, 0:T]

    def poly(pts):
        return shape_mask(lambda d: d.polygon([(x * SS, y * SS) for x, y in pts], fill=255))

    left_face = poly([apex, left, front])
    right_face = poly([apex, front, right])
    rgb = np.zeros((T, T, 3), np.float32)
    rgb[:] = (150, 150, 156)                       # lit (left) face
    rgb = np.where(right_face[..., None] > left_face[..., None], np.array([98, 99, 108], np.float32), rgb)

    rock_noise = r.normal(0, 9, (T, T))[..., None]
    # a few darker crack lines running down from the summit
    cracks = Image.new('L', (T, T), 0)
    d = ImageDraw.Draw(cracks)
    for _ in range(7):
        sx = apex[0] + r.integers(-10, 11)
        sy = apex[1] + r.integers(18, 40)
        d.line([(sx, sy), (sx + r.integers(-9, 10), sy + r.integers(12, 28))], fill=255, width=1)
    crack = np.asarray(cracks, np.float32)[..., None] / 255.0
    rgb = np.clip(rgb + rock_noise - 38 * crack, 0, 255)

    # snow above a ragged line, brighter on the lit face
    snow_line = snow_y + 5 * np.sin(xs / 4.3) + r.normal(0, 1.6, (T, T))
    snow = (ys < snow_line).astype(np.float32)[..., None]
    snow_rgb = np.where(right_face[..., None] > left_face[..., None],
                        np.array([196, 205, 220], np.float32), np.array([246, 248, 252], np.float32))
    rgb = rgb * (1 - snow) + snow_rgb * snow
    return rgb, np.maximum(left_face, right_face)


def make_mountain(variant):
    base = np.asarray(cell(variant, 0), dtype=np.float32).copy()
    layouts = [
        [((62, 12), (14, 80), (62, 100), (112, 78), 44)],
        [((58, 16), (10, 78), (58, 99), (108, 76), 46), ((98, 46), (80, 78), (100, 94), (124, 74), 56)],
        [((66, 10), (18, 79), (64, 101), (116, 79), 42), ((28, 50), (6, 76), (26, 92), (52, 78), 60)],
        [((60, 18), (12, 80), (60, 99), (110, 78), 50), ((98, 40), (78, 80), (98, 95), (122, 76), 52),
         ((30, 56), (10, 78), (28, 90), (50, 78), 66)],
    ]
    out = base
    # paint back-to-front: smaller/farther peaks first, the main peak last
    for i, (apex, left, front, right, snow_y) in reversed(list(enumerate(layouts[variant]))):
        rgb, alpha = peak(apex, left, front, right, snow_y, seed=variant * 10 + i)
        out = composite(to_image(out), rgb, alpha)
    return out


def main():
    out = sheet.copy()
    for variant in range(4):
        for row, maker in ((ROW_HILL, make_hill), (ROW_FORESTHILL, make_foresthill), (ROW_MOUNTAIN, make_mountain)):
            tile = maker(variant)
            tile = tile if isinstance(tile, Image.Image) else to_image(tile)
            # clear the old placeholder first so no red text bleeds through
            out.paste((0, 0, 0, 0), (variant * T, row * T, (variant + 1) * T, (row + 1) * T))
            out.alpha_composite(tile, (variant * T, row * T))
    out.save(SHEET, optimize=True)
    print('wrote', SHEET, out.size)


if __name__ == '__main__':
    sys.exit(main())
