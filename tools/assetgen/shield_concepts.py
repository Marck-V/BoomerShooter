"""Ten metal texturing concepts for the player's shield, rendered on the real model (a throwaway comparison script).

Run from the project root (Blender 5.1 or newer):
    blender --background --factory-startup --python tools/assetgen/shield_concepts.py -- [--out DIR]

It builds the shield exactly as tools/assetgen/player_shield.py does (without saving or exporting anything), paints
each concept as one 512 px picture projected flat onto the face, and renders the front and back of each.
Writes DIR/shield_concept_<n>_{front,back}.png and DIR/shield_concepts_sheet.png (default art/blender/previews): the
sheet has two concepts per row, each as its front then its back. The rim (yellow) and gem (cyan) stay the shield
script's recolourable materials; only the body is textured, with albedo, roughness and metallic maps.
"""
import math
import os
import sys

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gun_metal  # noqa: E402

# Pull in player_shield.py's builders without running its main()
_src = open(os.path.join(HERE, "player_shield.py"), encoding="utf-8").read().rsplit("\nmain()", 1)[0]
ps = {"__file__": os.path.join(HERE, "player_shield.py"), "__name__": "player_shield"}
exec(compile(_src, "player_shield.py", "exec"), ps)

SIZE = 512
RADIUS = ps["RADIUS"]
# radii of the model's steps, as fractions of the shield's radius: edge, first step, slope top / dome base
STEP_OUTER, STEP_MID, STEP_DOME = 0.215 / 0.26, 0.17 / 0.26, 0.11 / 0.26


def grid():
    i = (np.arange(SIZE, dtype=np.float32) + 0.5) / SIZE * 2.0 - 1.0
    x, z = np.meshgrid(i, i)                     # row = z (up), column = x
    return x, z, np.hypot(x, z), np.arctan2(z, x)


def smooth(a, b, x):
    return gun_metal._smoothstep(a, b, x)


BACK_VIEW = False        # while painting the back face's picture: no circle lines at all (they belong to the front's steps)


def ring(r, centre, half):
    if BACK_VIEW:
        return np.zeros_like(r)
    return 1.0 - smooth(half * 0.6, half, np.abs(r - centre))


def blobs(rng, count, rmin, rmax, r):
    """Round dents / studs scattered over the plate, as a 0..1 mask of how far into each one a pixel is."""
    out = np.zeros_like(r)
    x, z, _, _ = grid()
    for _ in range(count):
        cx, cz = rng.uniform(-0.9, 0.9, 2)
        rad = rng.uniform(rmin, rmax)
        d = np.hypot(x - cx, z - cz) / rad
        out = np.maximum(out, 1.0 - smooth(0.5, 1.0, d))
    return out


def col(*c):
    return np.array(c, dtype=np.float32)


def mix(a, b, t):
    return a * (1.0 - t[..., None]) + b * t[..., None]


def steps(img, r, light, dark, lip=0.018):
    """Light lip on each step of the model and a dark seam just inside it."""
    for edge in (STEP_OUTER, STEP_MID, STEP_DOME):
        img = img + ring(r, edge, lip)[..., None] * light
        img = img * (1.0 - ring(r, edge - 0.03, lip * 0.9)[..., None] * dark)
    return img + ring(r, 0.985, 0.025)[..., None] * light


def finish(img, rough, metal, r, edge_colour):
    img[r > 1.0] = edge_colour
    return np.clip(img, 0, 1), np.clip(rough, 0.05, 1), np.clip(metal, 0, 1)


def noises(seed):
    rng = np.random.default_rng(seed)
    return rng, gun_metal._fbm(SIZE, rng), gun_metal._noise(SIZE, 128, rng), gun_metal._scratches(SIZE, rng, 200)


def rings_grain(r, rng, density=200.0):
    if BACK_VIEW:
        # the back plate is brushed in straight lines, not circles
        x, _, _, _ = grid()
        return np.interp((x * 0.5 + 0.5) * density * 0.5, np.arange(0, int(density) + 20), rng.random(int(density) + 20))
    return np.interp(r * density, np.arange(0, int(density) + 20), rng.random(int(density) + 20))


# 1 ------------------------------------------------------------------------------------------------ worn steel
def paint_worn_steel():
    rng, fbm, fine, scratch = noises(11)
    x, z, r, th = grid()
    img = col(0.20, 0.24, 0.31) * (0.85 + fbm[..., None] * 0.35) * (0.94 + rings_grain(r, rng)[..., None] * 0.1)
    dents = blobs(rng, 38, 0.05, 0.12, r)
    img = img * (1.0 - dents[..., None] * 0.28) + (np.roll(dents, 5, axis=0) - dents)[..., None] * 0.12
    img = steps(img, r, col(0.30, 0.31, 0.33), 0.55) + scratch[..., None] * 0.22
    rust = smooth(0.45, 0.85, fbm + (r - 0.6) * 0.9) * smooth(0.55, 1.0, r)
    rust = np.clip(rust + (gun_metal._noise(SIZE, 48, rng) - 0.5) * 0.4, 0, 1) * smooth(0.3, 0.6, fine + fbm * 0.5)
    img = mix(img, col(0.55, 0.26, 0.10) * (0.7 + fine[..., None] * 0.5), rust * 0.85)
    return finish(img, 0.40 + rust * 0.45 - scratch * 0.15, 0.85 - rust * 0.6, r, col(0.14, 0.17, 0.22))


# 2 ------------------------------------------------------------------------------------------------ chrome
def paint_chrome():
    rng, fbm, fine, scratch = noises(2)
    x, z, r, th = grid()
    img = col(0.86, 0.88, 0.92) * (0.9 + fbm[..., None] * 0.1)
    img = steps(img, r, col(0.1, 0.1, 0.1), 0.0)
    for edge in (STEP_OUTER, STEP_MID, STEP_DOME):
        img = img * (1.0 - ring(r, edge - 0.03, 0.012)[..., None] * 0.7)
    img = img - blobs(rng, 14, 0.03, 0.06, r)[..., None] * 0.12
    img = img - scratch[..., None] * 0.18
    return finish(img, 0.10 + scratch * 0.25 + fbm * 0.08, np.ones_like(r), r, col(0.7, 0.72, 0.76))


# 3 ------------------------------------------------------------------------------------------------ brushed titanium
def paint_titanium():
    rng, fbm, fine, scratch = noises(3)
    x, z, r, th = grid()
    grain = rings_grain(r, rng, 420.0)
    img = col(0.46, 0.49, 0.56) * (0.82 + grain[..., None] * 0.3) * (0.92 + fbm[..., None] * 0.15)
    heat = smooth(0.30, 0.34, r) * (1.0 - smooth(0.42, 0.47, r))
    blend = smooth(0.30, 0.46, r)
    ramp = col(0.85, 0.65, 0.25) * (1 - blend)[..., None] + col(0.35, 0.3, 0.8) * blend[..., None]
    img = mix(img, ramp * 0.9, heat * 0.85)
    img = steps(img, r, col(0.22, 0.23, 0.25), 0.45) + scratch[..., None] * 0.12
    return finish(img, 0.30 + grain * 0.2, 0.95 - blobs(rng, 6, 0.04, 0.07, r) * 0.2, r, col(0.3, 0.32, 0.37))


# 4 ------------------------------------------------------------------------------------------------ hammered bronze
def paint_bronze():
    rng, fbm, fine, scratch = noises(4)
    x, z, r, th = grid()
    dents = blobs(rng, 260, 0.025, 0.06, r)
    lip = np.roll(np.roll(dents, 3, axis=0), 3, axis=1) - dents
    img = col(0.66, 0.43, 0.17) * (0.85 + fbm[..., None] * 0.3)
    img = img * (1.0 - dents[..., None] * 0.22) + lip[..., None] * 0.25
    img = steps(img, r, col(0.35, 0.22, 0.08), 0.5)
    seams = np.maximum(ring(r, STEP_DOME - 0.03, 0.05), ring(r, STEP_MID - 0.03, 0.05))
    green = smooth(0.58, 0.8, fbm + dents * 0.1 + seams * 0.25)
    img = mix(img, col(0.18, 0.52, 0.44) * (0.8 + fine[..., None] * 0.3), green * 0.8)
    return finish(img, 0.38 + green * 0.4 + dents * 0.1, 0.9 - green * 0.6, r, col(0.35, 0.22, 0.08))


# 5 ------------------------------------------------------------------------------------------------ engraved gold
def paint_gold():
    rng, fbm, fine, scratch = noises(5)
    x, z, r, th = grid()
    img = col(0.96, 0.74, 0.27) * (0.88 + fbm[..., None] * 0.14)
    scroll = np.abs(np.sin(th * 12 + r * 24.0 + np.sin(th * 4) * 1.5))
    engrave = (1.0 - smooth(0.05, 0.14, scroll)) * smooth(STEP_DOME + 0.04, STEP_DOME + 0.1, r) * (1.0 - smooth(0.9, 0.93, r))
    for edge in (STEP_OUTER, STEP_MID, STEP_DOME):
        engrave = np.maximum(engrave, ring(r, edge - 0.02, 0.012))
    engrave = np.maximum(engrave, ring(r, 0.93, 0.01))
    for k in range(24):
        a = (k + 0.5) / 24 * math.tau - math.pi
        engrave = np.maximum(engrave, 1.0 - smooth(0.012, 0.024, np.hypot(x - math.cos(a) * 0.96, z - math.sin(a) * 0.96)))
    img = mix(img, col(0.30, 0.18, 0.04), engrave * 0.85) + scratch[..., None] * 0.08
    img = steps(img, r, col(0.25, 0.2, 0.1), 0.0)
    return finish(img, 0.22 + engrave * 0.35 + fine * 0.05, 1.0 - engrave * 0.3, r, col(0.5, 0.35, 0.1))


# 6 ------------------------------------------------------------------------------------------------ damascus
def paint_damascus():
    rng, fbm, fine, scratch = noises(6)
    x, z, r, th = grid()
    warp = x * 34.0 + z * 6.0 + fbm * 26.0 + np.sin(r * 14.0) * 3.0
    bands = 0.5 + 0.5 * np.sin(warp) + (fine - 0.5) * 0.3
    t = smooth(0.35, 0.65, bands)
    img = mix(col(0.20, 0.22, 0.27), col(0.66, 0.68, 0.73), t)
    img = steps(img, r, col(0.25, 0.26, 0.28), 0.5) + scratch[..., None] * 0.1
    return finish(img, 0.28 + t * 0.14, 0.97 - (1 - t) * 0.12, r, col(0.2, 0.22, 0.27))


# 7 ------------------------------------------------------------------------------------------------ rusted iron
def paint_rust():
    rng, fbm, fine, scratch = noises(7)
    x, z, r, th = grid()
    iron = col(0.22, 0.19, 0.18) * (0.8 + fbm[..., None] * 0.4)
    rust = smooth(0.40, 0.66, fbm * 0.8 + fine * 0.25)
    rusty = col(0.52, 0.24, 0.09) * (0.55 + fine[..., None] * 0.7)
    flake = smooth(0.7, 0.9, gun_metal._noise(SIZE, 40, rng) + fine * 0.3)
    img = mix(mix(iron, rusty, rust), col(0.34, 0.14, 0.05), flake * rust * 0.6)
    pits = (fine < 0.18).astype(np.float32)
    img = img * (1.0 - pits[..., None] * 0.5)
    img = steps(img, r, col(0.28, 0.27, 0.27), 0.6) + scratch[..., None] * 0.06
    bare = smooth(0.55, 0.9, ring(r, STEP_OUTER, 0.03) + ring(r, 0.985, 0.04)) * (1 - rust * 0.5)
    img = mix(img, col(0.55, 0.52, 0.5), bare * 0.6)
    return finish(img, 0.55 + rust * 0.4 - bare * 0.3, 0.80 - rust * 0.7 + bare * 0.1, r, col(0.2, 0.15, 0.12))


# 8 ------------------------------------------------------------------------------------------------ riveted plates
def paint_plates():
    rng, fbm, fine, scratch = noises(8)
    x, z, r, th = grid()
    n = 10
    ring_bins = np.array([0.0, STEP_DOME, STEP_MID, STEP_OUTER, 0.93, 2.0])
    band = np.digitize(r, ring_bins) - 1
    wedge = np.floor(((th + math.pi) / math.tau * n) % n).astype(int)
    shade = rng.uniform(0.75, 1.15, (n, len(ring_bins)))[wedge, band]
    img = col(0.34, 0.36, 0.42) * shade[..., None] * (0.9 + fbm[..., None] * 0.2)
    local = ((th + math.pi) / math.tau * n) % 1.0
    seam_w = (1.0 - smooth(0.012, 0.03, np.minimum(local, 1 - local) * (r + 0.1))) * (r > STEP_DOME * 0.7)
    img = img * (1.0 - seam_w[..., None] * 0.75)
    img = steps(img, r, col(0.25, 0.26, 0.28), 0.55)
    rivet = np.zeros_like(r)
    for radius in (0.5, 0.74, 0.9):
        for k in range(n):
            a = k / n * math.tau - math.pi
            for da in (-0.045, 0.045):
                aa = a + da / max(radius, 0.4)
                d = np.hypot(x - math.cos(aa) * radius, z - math.sin(aa) * radius)
                rivet = np.maximum(rivet, 1.0 - smooth(0.014, 0.022, d))
    img = mix(img, col(0.72, 0.74, 0.78), rivet * 0.9) + scratch[..., None] * 0.1
    return finish(img, 0.38 + fbm * 0.1, 0.90 + 0 * r, r, col(0.2, 0.22, 0.26))


# 9 ------------------------------------------------------------------------------------------------ hex armour
def paint_hex():
    rng, fbm, fine, scratch = noises(9)
    x, z, r, th = grid()
    s = 17.0
    p = np.stack([x * s, z * s], axis=-1)
    rr = np.array([1.0, 1.7320508], dtype=np.float32)
    h = rr / 2
    a = (p % rr) - h
    b = ((p - h) % rr) - h
    use_a = (np.sum(a * a, axis=-1) < np.sum(b * b, axis=-1))[..., None]
    gv = np.where(use_a, a, b)
    cell = p - gv
    hexd = np.maximum(np.abs(gv[..., 0]), np.abs(gv[..., 0]) * 0.5 + np.abs(gv[..., 1]) * 0.866)
    ids = (np.sin(cell[..., 0] * 12.9898 + cell[..., 1] * 78.233) * 43758.5453) % 1.0
    img = col(0.13, 0.14, 0.18) * (0.75 + ids[..., None] * 0.5) * (0.9 + fbm[..., None] * 0.2)
    edge = smooth(0.40, 0.48, hexd)
    top_light = np.clip(gv[..., 1] * 1.6 + gv[..., 0] * 0.5, 0, 1) * edge
    img = img * (1.0 - edge[..., None] * 0.6) + top_light[..., None] * col(0.5, 0.52, 0.58)
    plain = smooth(STEP_DOME - 0.02, STEP_DOME + 0.03, r)
    img = mix(col(0.12, 0.13, 0.17) * (0.9 + fbm[..., None] * 0.2), img, plain)
    img = steps(img, r, col(0.35, 0.37, 0.42), 0.6) + scratch[..., None] * 0.1
    return finish(img, 0.30 + ids * 0.15 + edge * 0.1, 0.92 - edge * 0.1, r, col(0.1, 0.11, 0.14))


# 10 ----------------------------------------------------------------------------------------------- black steel, brass inlay
def paint_inlay():
    rng, fbm, fine, scratch = noises(10)
    x, z, r, th = grid()
    grain = rings_grain(r, rng, 300.0)
    img = col(0.07, 0.07, 0.09) * (0.85 + grain[..., None] * 0.35) * (0.9 + fbm[..., None] * 0.25)
    brass = np.zeros_like(r)
    for edge in (STEP_OUTER, STEP_MID, STEP_DOME, 0.93):
        brass = np.maximum(brass, ring(r, edge - 0.02, 0.011))
    brass = np.maximum(brass, ring(r, 0.985, 0.02))
    local = ((th + math.pi) / math.tau * 12) % 1.0
    spokes = (1.0 - smooth(0.01, 0.02, np.minimum(local, 1 - local) * (r + 0.1))) * smooth(STEP_DOME + 0.03, STEP_DOME + 0.06, r) * (1 - smooth(0.9, 0.92, r))
    brass = np.maximum(brass, spokes)
    for k in range(12):
        a = (k + 0.5) / 12 * math.tau - math.pi
        for rad in (0.55, 0.78):
            dx, dz = x - math.cos(a) * rad, z - math.sin(a) * rad
            c, sn = math.cos(a), math.sin(a)
            u, v = dx * c + dz * sn, -dx * sn + dz * c
            brass = np.maximum(brass, 1.0 - smooth(0.035, 0.05, np.abs(u) + np.abs(v) * 1.8))
    img = mix(img, col(0.88, 0.62, 0.22) * (0.85 + fine[..., None] * 0.2), brass)
    img = steps(img, r, col(0.12, 0.12, 0.14), 0.0) + scratch[..., None] * 0.08
    return finish(img, 0.26 + (1 - brass) * 0.1 + grain * 0.1, 0.9 + brass * 0.1, r, col(0.05, 0.05, 0.07))


CONCEPTS = [
    ("Worn Steel", paint_worn_steel), ("Chrome", paint_chrome), ("Brushed Titanium", paint_titanium),
    ("Hammered Bronze", paint_bronze), ("Engraved Gold", paint_gold), ("Damascus", paint_damascus),
    ("Rusted Iron", paint_rust), ("Riveted Plates", paint_plates), ("Hex Armour", paint_hex),
    ("Black Steel, Brass Inlay", paint_inlay),
]


# ============================================================================== the darker set (--set dark)
# Five metals that all sit on the dark side, each with a different character.

# D1 ----------------------------------------------------------------------------------------------- blackened gunmetal
def paint_gunmetal():
    rng, fbm, fine, scratch = noises(21)
    x, z, r, th = grid()
    grain = rings_grain(r, rng, 380.0)
    img = col(0.075, 0.08, 0.095) * (0.78 + grain[..., None] * 0.5) * (0.88 + fbm[..., None] * 0.22)
    img = steps(img, r, col(0.20, 0.21, 0.24), 0.6) + scratch[..., None] * 0.10
    # bare steel showing through where the blackening has worn off the edges of the steps
    edges = np.maximum.reduce([ring(r, e, 0.017) for e in (STEP_OUTER, STEP_MID, STEP_DOME)] + [ring(r, 0.985, 0.03)])
    wear = np.clip(edges * smooth(0.25, 0.6, fine + fbm * 0.3 + 0.2), 0, 1)
    img = mix(img, col(0.58, 0.60, 0.65), wear * 0.85)
    return finish(img, 0.30 + grain * 0.2 - wear * 0.12, 0.96 + 0 * r, r, col(0.06, 0.065, 0.08))


# D2 ----------------------------------------------------------------------------------------------- oil-slick anodised
def paint_oilslick():
    rng, fbm, fine, scratch = noises(22)
    x, z, r, th = grid()
    grain = rings_grain(r, rng, 420.0)
    base = col(0.055, 0.06, 0.085) * (0.8 + grain[..., None] * 0.4)
    # bands of heat-tint colour that drift across the plate: purple, teal and magenta, as on titanium that has been heated
    t = 0.5 + 0.5 * np.sin(r * 17.0 + fbm * 3.5 + np.sin(th * 3.0) * 0.6)
    ramp = col(0.30, 0.09, 0.55) * (1.0 - smooth(0.0, 0.5, t))[..., None] \
        + col(0.05, 0.45, 0.50) * (smooth(0.0, 0.5, t) * (1.0 - smooth(0.5, 1.0, t)))[..., None] \
        + col(0.62, 0.10, 0.38) * smooth(0.5, 1.0, t)[..., None]
    sheen = smooth(0.30, 0.75, fbm + (np.sin(r * 5.0) * 0.15))
    img = base + ramp * sheen[..., None] * 0.55
    img = steps(img, r, col(0.20, 0.18, 0.28), 0.6) + scratch[..., None] * 0.09
    return finish(img, 0.22 + grain * 0.15, 1.0 + 0 * r, r, col(0.05, 0.05, 0.09))


# D3 ----------------------------------------------------------------------------------------------- forge-scale cast iron
def paint_cast_iron():
    rng, fbm, fine, scratch = noises(23)
    x, z, r, th = grid()
    img = col(0.115, 0.108, 0.10) * (0.65 + fbm[..., None] * 0.6)
    pits = (fine < 0.22).astype(np.float32)
    img = img * (1.0 - pits[..., None] * 0.55) + blobs(rng, 60, 0.02, 0.05, r)[..., None] * 0.04
    # cooled-lava veins: glowing orange only in the seams between the steps and in a few hairline cracks
    crack_noise = gun_metal._noise(SIZE, 24, rng)
    cracks = (1.0 - smooth(0.0, 0.035, np.abs(crack_noise - 0.5))) * smooth(0.2, 0.7, fbm)
    seams = np.maximum.reduce([ring(r, e - 0.03, 0.02) for e in (STEP_OUTER, STEP_MID, STEP_DOME)])
    ember = np.clip(np.maximum(cracks * 0.9, seams * 0.8), 0, 1)
    img = steps(img, r, col(0.22, 0.21, 0.20), 0.6) + scratch[..., None] * 0.05
    img = mix(img, col(1.0, 0.42, 0.09) * (0.8 + fine[..., None] * 0.4), ember * 0.85)
    return finish(img, 0.68 - ember * 0.35, 0.55 - ember * 0.5, r, col(0.08, 0.075, 0.07))


# D4 ----------------------------------------------------------------------------------------------- obsidian mirror, cyan circuit etching
def paint_obsidian():
    rng, fbm, fine, scratch = noises(24)
    x, z, r, th = grid()
    img = col(0.022, 0.025, 0.034) * (0.9 + fbm[..., None] * 0.25)
    lines = np.maximum.reduce([ring(r, e - 0.02, 0.008) for e in (STEP_OUTER, STEP_MID, STEP_DOME, 0.93)])
    local = ((th + math.pi) / math.tau * 12) % 1.0
    spokes = (1.0 - smooth(0.006, 0.014, np.minimum(local, 1 - local) * (r + 0.1))) \
        * smooth(STEP_DOME + 0.03, STEP_DOME + 0.06, r) * (1 - smooth(0.9, 0.92, r))
    lines = np.maximum(lines, spokes)
    for k in range(12):
        a = (k + 0.5) / 12 * math.tau - math.pi
        for rad in (0.58, 0.8):
            node = np.hypot(x - math.cos(a) * rad, z - math.sin(a) * rad)
            lines = np.maximum(lines, 1.0 - smooth(0.012, 0.022, node))
    img = steps(img, r, col(0.07, 0.08, 0.10), 0.0) + scratch[..., None] * 0.05
    img = mix(img, col(0.10, 0.80, 1.0), lines * 0.9)
    return finish(img, 0.08 + scratch * 0.2 + lines * 0.25, 1.0 - lines * 0.45, r, col(0.02, 0.022, 0.03))


GAME_BAKE = False        # painting the texture for the game (drawn unshaded) rather than for a lit concept render


def paint_battle():
    rng, fbm, fine, scratch = noises(25)
    x, z, r, th = grid()
    if GAME_BAKE and BACK_VIEW:
        # The back never sees a hit: clean dark steel, only the faintest brushing and mottling, no scratches, dents, chips
        # or scorching
        grain = rings_grain(r, rng, 380.0)
        img = col(0.105, 0.11, 0.135) * (0.92 + fbm[..., None] * 0.12) * (0.97 + grain[..., None] * 0.06)
        return finish(img, 0.36 + fbm * 0.06, 0.60 + 0 * r, r, col(0.07, 0.07, 0.09))
    img = col(0.125, 0.135, 0.165) * (0.75 + fbm[..., None] * 0.45)
    dents = blobs(rng, 40 if GAME_BAKE else 70, 0.03, 0.09, r)
    lip = np.roll(np.roll(dents, 4, axis=0), 4, axis=1) - dents
    # In a lit render a dent reads as a dent. Drawn unshaded in the game a dark disc is just a black blotch, so there
    # the front has only a few faint ones with a brighter lip on one side (which still reads as a bevel), and the back,
    # which is seen close up all the time, has none.
    dent_dark, dent_lip = (0.05, 0.0) if GAME_BAKE else (0.32, 0.14)     # no light crescents in the game: light marks are the rivets
    img = img * (1.0 - dents[..., None] * dent_dark) + lip[..., None] * dent_lip
    heavy = gun_metal._scratches(SIZE, rng, 650)
    img = steps(img, r, col(0.24, 0.25, 0.28), 0.6) + (scratch * 0.3 + heavy * (0.2 if GAME_BAKE else 0.28))[..., None]
    # scorching: soot, then the blue-purple a steel plate turns when it has been heated, round the edge
    heat = smooth(0.52, 0.80, gun_metal._fbm(SIZE, rng) + (r - 0.55) * 0.7) * smooth(0.45, 1.0, r)
    soot, soot_colour = (0.35, col(0.07, 0.07, 0.08)) if GAME_BAKE else (0.8, col(0.035, 0.035, 0.04))
    img = mix(img, soot_colour, heat * soot)
    temper = smooth(0.25, 0.55, heat) * (1.0 - smooth(0.55, 0.9, heat))
    img = mix(img, col(0.22, 0.17, 0.42), temper * (0.45 if GAME_BAKE else 0.65))
    if GAME_BAKE:
        # Rivets at equal angles along the edge of each step (no scattered chips: light marks are all rivets, in order)
        rivets = np.zeros_like(r)
        shade = np.zeros_like(r)
        for edge, count in ((STEP_OUTER, 28), (STEP_MID, 20), (STEP_DOME, 12)):
            for k in range(count):
                a = (k + 0.5) / count * math.tau
                d = np.hypot(x - math.cos(a) * edge, z - math.sin(a) * edge)
                rivets = np.maximum(rivets, 1.0 - smooth(0.011, 0.015, d))
                shade = np.maximum(shade, 1.0 - smooth(0.015, 0.024, d))
        img = img * (1.0 - (shade - rivets).clip(0, 1)[..., None] * 0.55)       # a dark seat round each, so it stands proud
        img = mix(img, col(0.50, 0.52, 0.56), rivets * 0.9)
        metal = (0.62 - heat * 0.25) * (1.0 - rivets) + 0.8 * rivets            # lit in the game, where full metal only mirrors the sky
        return finish(img, 0.42 + heat * 0.25 - rivets * 0.12, metal, r, col(0.1, 0.1, 0.12))
    # chips in the dark finish near the rim, down to bare steel
    chips = blobs(rng, 40, 0.012, 0.03, r) * smooth(0.6, 0.85, r)
    img = mix(img, col(0.72, 0.74, 0.78), chips * 0.9)
    return finish(img, 0.42 + heat * 0.25 - chips * 0.2, 0.92 - heat * 0.35, r, col(0.1, 0.1, 0.12))


def paint_trim():
    """The game's picture for the parts that are not the big front and back plates: the ribs, hub and studs on the back
    and front, and the thin walls between the steps. Smooth brushed steel, a step lighter than the plates so those parts
    stand out. Very flat, so it does not matter how it is stretched over a wall. Returns (albedo, roughness, metallic)."""
    rng, fbm, fine, scratch = noises(26)
    x, z, r, th = grid()
    grain = np.interp((x * 0.5 + 0.5) * 520.0, np.arange(0, 540), rng.random(540))      # brushed in straight lines
    img = col(0.175, 0.185, 0.215) * (0.95 + grain[..., None] * 0.07) * (0.97 + fbm[..., None] * 0.06)
    return np.clip(img, 0, 1), np.clip(0.28 + grain * 0.05, 0, 1), np.full_like(r, 0.68)


DARK_CONCEPTS = [
    ("Blackened Gunmetal", paint_gunmetal), ("Oil-Slick Anodised", paint_oilslick),
    ("Forge-Scale Cast Iron", paint_cast_iron), ("Obsidian Mirror, Cyan Etching", paint_obsidian),
    ("Battle-Scarred Black Steel", paint_battle),
]


# --------------------------------------------------------------------------------------------------- materials

def make_image(name, array, colour=True):
    if array.ndim == 2:
        array = np.repeat(array[..., None], 3, axis=2)
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    img.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    rgba = np.concatenate([array, np.ones((SIZE, SIZE, 1), dtype=np.float32)], axis=2).astype(np.float32)
    img.pixels.foreach_set(rgba.reshape(-1))
    return img


def textured_material(name, image, rough_image, metal_image, tint=1.0, back=None):
    """`back`: optional (albedo, roughness, metallic) images used on the faces that look the way the back plate does
    (object-space normal pointing along +Y, away from the front), so the back can differ from the front."""
    mat = bpy.data.materials.new(name)
    try:
        mat.use_nodes = True
    except AttributeError:
        pass
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Object"], sep.inputs["Vector"])
    # the disc lies in the XZ plane: u = x, v = z, scaled so the shield's edge is the picture's edge
    scale = 0.5 / ps["RADIUS"]
    u = nodes.new("ShaderNodeMath")
    u.operation = "MULTIPLY_ADD"
    u.inputs[1].default_value, u.inputs[2].default_value = scale, 0.5
    v = nodes.new("ShaderNodeMath")
    v.operation = "MULTIPLY_ADD"
    v.inputs[1].default_value, v.inputs[2].default_value = scale, 0.5
    links.new(sep.outputs["X"], u.inputs[0])
    links.new(sep.outputs["Z"], v.inputs[0])
    comb = nodes.new("ShaderNodeCombineXYZ")
    links.new(u.outputs[0], comb.inputs["X"])
    links.new(v.outputs[0], comb.inputs["Y"])

    def tex(img):
        t = nodes.new("ShaderNodeTexImage")
        t.image = img
        t.interpolation = "Closest"
        t.extension = "EXTEND"
        links.new(comb.outputs["Vector"], t.inputs["Vector"])
        return t

    # 1 on the faces that face down the back of the shield, 0 elsewhere
    normal_y = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Normal"], normal_y.inputs["Vector"])
    is_back = nodes.new("ShaderNodeMath")
    is_back.operation = "GREATER_THAN"       # the front looks along -Y (the camera for the front shot is at -Y)
    is_back.inputs[1].default_value = 0.3
    links.new(normal_y.outputs["Y"], is_back.inputs[0])

    def pick(front_img, back_img):
        front_tex = tex(front_img)
        if back_img is None:
            return front_tex.outputs["Color"]
        back_tex = tex(back_img)
        chooser = nodes.new("ShaderNodeMix")
        chooser.data_type = "RGBA"
        links.new(is_back.outputs[0], chooser.inputs["Factor"])
        links.new(front_tex.outputs["Color"], chooser.inputs["A"])
        links.new(back_tex.outputs["Color"], chooser.inputs["B"])
        return chooser.outputs["Result"]

    back_a, back_r, back_m = back if back else (None, None, None)
    colour = pick(image, back_a)
    links.new(pick(rough_image, back_r), shader.inputs["Roughness"])
    links.new(pick(metal_image, back_m), shader.inputs["Metallic"])
    if tint != 1.0:
        mixer = nodes.new("ShaderNodeMix")
        mixer.data_type = "RGBA"
        mixer.blend_type = "MULTIPLY"
        mixer.inputs["Factor"].default_value = 1.0
        mixer.inputs["B"].default_value = (tint, tint, tint, 1.0)
        links.new(colour, mixer.inputs["A"])
        links.new(mixer.outputs["Result"], shader.inputs["Base Color"])
    else:
        links.new(colour, shader.inputs["Base Color"])
    return mat


def studio_world(scene):
    """What the metal reflects: a bright studio gradient, while the camera still sees the purple backdrop."""
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputWorld")
    coord = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coord.outputs["Generated"], sep.inputs["Vector"])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.04, 0.03, 0.08, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (2.2, 2.1, 2.3, 1)
    mid = ramp.color_ramp.elements.new(0.5)
    mid.color = (0.30, 0.28, 0.40, 1)
    maprange = nodes.new("ShaderNodeMapRange")
    maprange.inputs["From Min"].default_value, maprange.inputs["From Max"].default_value = -0.6, 1.0
    links.new(sep.outputs["Z"], maprange.inputs["Value"])
    links.new(maprange.outputs["Result"], ramp.inputs["Fac"])
    studio = nodes.new("ShaderNodeBackground")
    links.new(ramp.outputs["Color"], studio.inputs["Color"])
    backdrop = nodes.new("ShaderNodeBackground")
    backdrop.inputs["Color"].default_value = (0.12, 0.0, 0.07, 1.0)
    path = nodes.new("ShaderNodeLightPath")
    mixer = nodes.new("ShaderNodeMixShader")
    links.new(path.outputs["Is Camera Ray"], mixer.inputs["Fac"])
    links.new(studio.outputs["Background"], mixer.inputs[1])
    links.new(backdrop.outputs["Background"], mixer.inputs[2])
    links.new(mixer.outputs["Shader"], out.inputs["Surface"])
    scene.world = world


# --------------------------------------------------------------------------------------------------------- main

def bake_final(painter, out_path, size=1024, gain=1.0):
    """Writes the chosen concept as the game's body texture: one atlas of three pictures side by side, `size` px each:
    the front's picture, the back's (no circle lines) and the trim (ribs, hub, studs and the thin walls: lighter worn
    steel). tools/assetgen/player_shield.py maps the body's faces onto the matching picture. It is painted at `size`
    px, with the dents and soot toned down for the game, the back left clean and the trim smooth. Writes the colour
    atlas and, beside it, the packed roughness/metallic atlas (the body is lit like the guns). `gain` scales the colour."""
    global BACK_VIEW, GAME_BAKE, SIZE
    SIZE, GAME_BAKE = size, True
    front = painter()
    BACK_VIEW = True
    back = painter()
    BACK_VIEW = False
    trim = paint_trim()
    albedo = np.clip(np.concatenate([front[0], back[0], trim[0]], axis=1) * gain, 0.0, 1.0).astype(np.float32)
    rough = np.concatenate([front[1], back[1], trim[1]], axis=1)
    metal = np.concatenate([front[2], back[2], trim[2]], axis=1)
    # glTF-style packed map, as the guns use: red = occlusion (none painted), green = roughness, blue = metallic
    orm = np.stack([np.ones_like(rough), rough, metal], axis=-1).astype(np.float32)

    def save(path, array, colour):
        h, w = array.shape[:2]
        image = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
        image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
        rgba = np.concatenate([array, np.ones((h, w, 1), dtype=np.float32)], axis=2)
        image.pixels.foreach_set(rgba.reshape(-1))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        image.filepath_raw = path
        image.file_format = "PNG"
        image.save()
        print("baked", path, w, "x", h)

    save(out_path, albedo, True)
    save(out_path.replace("_albedo", "_orm"), orm, False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--bake" in argv:
        # --bake [--size N] [--gain G]: the final body texture (the battle-scarred black steel) for the game
        size = int(argv[argv.index("--size") + 1]) if "--size" in argv else 1024
        gain = float(argv[argv.index("--gain") + 1]) if "--gain" in argv else 1.8
        bake_final(paint_battle, os.path.join(ps["ROOT"], "models", "player_shield", "shield_body_albedo.png"), size, gain)
        return
    out_dir = os.path.join(ps["ROOT"], "art", "blender", "previews")
    if "--out" in argv:
        out_dir = argv[argv.index("--out") + 1]
    os.makedirs(out_dir, exist_ok=True)
    dark = "--set" in argv and argv[argv.index("--set") + 1] == "dark"
    concepts = DARK_CONCEPTS if dark else CONCEPTS
    prefix = "shield_dark" if dark else "shield"

    bpy.ops.wm.read_factory_settings(use_empty=True)
    m = {
        "body": ps["body_material"]("Body", ps["BODY"]),
        "body_light": ps["body_material"]("BodyLight", ps["BODY_LIGHT"], 0.7, 0.3),
        "rim": ps["glow_material"]("Rim", ps["RIM"], 1.6),
        "gem": ps["glow_material"]("Gem", ps["GEM"], 1.6),
    }
    coll = ps["new_collection"]("Shield")
    ps["build_boss"](0.0, m, coll, "Front_")
    ps["back_ribs"](0.0, m, coll, "Back_")
    cam = ps["build_preview_scene"]()
    studio_world(bpy.context.scene)
    lights = [o for o in bpy.data.objects if o.type == "LIGHT"]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]

    shots = []
    for n, (title, painter) in enumerate(concepts, 1):
        global BACK_VIEW
        albedo, rough, metal = painter()
        BACK_VIEW = True                     # the back plate is flat: the same metal, painted without the circle lines
        back_albedo, back_rough, back_metal = painter()
        BACK_VIEW = False
        ia, ir, im = make_image(f"c{n}a", albedo), make_image(f"c{n}r", rough, False), make_image(f"c{n}m", metal, False)
        ba, br, bm = make_image(f"c{n}ba", back_albedo), make_image(f"c{n}br", back_rough, False), make_image(f"c{n}bm", back_metal, False)
        body = textured_material(f"Body{n}", ia, ir, im, back=(ba, br, bm))
        light = textured_material(f"BodyLight{n}", ia, ir, im, 1.2, back=(ba, br, bm))
        for ob in meshes:
            for slot in ob.material_slots:
                if slot.material.name.startswith("BodyLight"):
                    slot.material = light
                elif slot.material.name.startswith("Body"):
                    slot.material = body
        for side, lz, loc in (("front", 0.0, (0.9, -1.2, 0.6)), ("back", math.pi, (-0.9, 1.2, 0.6))):
            for lt in lights:
                lt.rotation_euler.z += lz
            path = os.path.join(out_dir, f"{prefix}_concept_{n}_{side}.png")
            ps["render"](cam, path, ps["v"](*loc), ps["v"](0, 0, 0), 50, (700, 700))
            for lt in lights:
                lt.rotation_euler.z -= lz
            shots.append(path)
        print("concept", n, title)

    tiles = []
    for path in shots:
        img = bpy.data.images.load(path)
        px = np.empty(700 * 700 * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        tiles.append(px.reshape(700, 700, 4)[130:570, 130:570])          # crop the empty margin
    while len(tiles) % 4:
        tiles.append(np.broadcast_to(tiles[0][0, 0], tiles[0].shape).copy())   # backdrop-coloured tiles pad the last row
    rows = [np.concatenate(tiles[i:i + 4], axis=1) for i in range(0, len(tiles), 4)]
    sheet = np.concatenate(rows[::-1], axis=0)                           # image rows run bottom to top
    h, w = sheet.shape[:2]
    out = bpy.data.images.new("sheet", w, h, alpha=False)
    out.pixels.foreach_set(sheet.reshape(-1))
    out.filepath_raw = os.path.join(out_dir, f"{prefix}_concepts_sheet.png")
    out.file_format = "PNG"
    out.save()
    print("sheet", out.filepath_raw)


main()
