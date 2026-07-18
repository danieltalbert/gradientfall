#!/usr/bin/env python3
"""Gradient Peaks Python twin — 1:1 math preview of src/world/gradient_peaks.gd.

Iterate mountain design HERE first (renders in ~2 s), look at the PNGs, then
port the changed constants back to gradient_peaks.gd. Uses pyfastnoiselite —
the SAME FastNoiseLite library Godot ships — so geometry and vertex-color
output is the real thing; only lighting is approximated (lambert + fill +
exp fog vs Godot's SDFGI/TAA pipeline).

Also previews the north-approach DENSITY layer (peaks_approach.gd): alpine
treeline, sorted boulders, and Descent's Rest, plus a grass carpet standing
in for the in-game 400k field — so the framing shows what the player sees,
not a bare heightfield. Grass here is preview-only (the field already ships
in meadow_flora.gd); trees/boulders/village mirror peaks_approach.gd.

Deps: pip install pyfastnoiselite numpy pillow
Run:  python3 tools/proto_mountains.py <outdir>
Out:  proto_peaks_gameangle.png (the meadow_north_peaks screenshot angle),
      proto_peaks_centered.png (hero framing, due north from spawn).
"""
import math
import sys
import numpy as np
from PIL import Image, ImageDraw
from pyfastnoiselite.pyfastnoiselite import (
    FastNoiseLite, NoiseType, FractalType,
)

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
W, H = 1280, 720

# ---------------------------------------------------------------- noise rig
# Mirrors the planned GDScript setup exactly (seed, type, freq, octaves).
MOUNTAIN_SEED = 20260718


def make_noise(seed, freq, octaves=1, ridged=False, ntype=NoiseType.NoiseType_OpenSimplex2S):
    n = FastNoiseLite(seed)
    n.noise_type = ntype
    n.frequency = freq
    if octaves > 1 or ridged:
        n.fractal_type = FractalType.FractalType_Ridged if ridged else FractalType.FractalType_FBm
        n.fractal_octaves = octaves
    return n


def grid_noise(n, xs, zs):
    """Vectorized 2D sample of a FastNoiseLite over a meshgrid (world coords).
    Equivalent to Godot get_noise_2d(x, z) at every grid point."""
    xx, zz = np.meshgrid(xs, zs)
    coords = np.stack([xx.ravel(), zz.ravel()], axis=0).astype(np.float32)
    out = np.asarray(n.gen_from_coords(coords), dtype=np.float64)
    return out.reshape(zz.shape)


# Noise instances — port these constants verbatim to gradient_peaks.gd.
N_RIDGE = make_noise(MOUNTAIN_SEED + 10, 0.0028, octaves=4, ridged=True)
N_WARP_X = make_noise(MOUNTAIN_SEED + 11, 0.0011, octaves=2)
N_WARP_Z = make_noise(MOUNTAIN_SEED + 12, 0.0011, octaves=2)
N_GULLY = make_noise(MOUNTAIN_SEED + 13, 0.0095, octaves=3, ridged=True)
N_CREST = make_noise(MOUNTAIN_SEED + 14, 0.0018, octaves=2)
N_SNOWLINE = make_noise(MOUNTAIN_SEED + 15, 0.004, octaves=2)
N_LITHO = make_noise(MOUNTAIN_SEED + 16, 0.0021, octaves=2)
N_STRATA_WARP = make_noise(MOUNTAIN_SEED + 17, 0.008, octaves=2)
N_CRAG = make_noise(MOUNTAIN_SEED + 18, 0.03, octaves=3)
N_APRON = make_noise(MOUNTAIN_SEED + 19, 0.012, octaves=2)
N_FOREST = make_noise(MOUNTAIN_SEED + 20, 0.016, octaves=3)

# ------------------------------------------------------------- rank config
# Three depth ranks arcing around the meadow's north: foothill rank, main
# wall (hero ridgeline), far rank. Summits: (world_x, height_m, half_width_m)
# — authored skyline, irregular on purpose so nothing reads procedural.
# Skyline generally ASCENDS toward the Summit's bearing (x~320) — "the
# mountains are slowly sorting themselves" — with enough scatter to stay
# natural. Monarch of the main wall sits below-left of THE Summit so the
# eye walks a diagonal up to it.
SUMMITS_MAIN = [
    (-1150.0, 252.0, 170.0),
    (-880.0, 278.0, 170.0),
    (-620.0, 316.0, 185.0),
    (-350.0, 288.0, 145.0),   # west shoulder of the Saddle
    (-140.0, 342.0, 150.0),   # east shoulder of the Saddle
    (80.0, 398.0, 205.0),     # main-wall monarch, below-left of THE Summit
    (290.0, 372.0, 150.0),
    (560.0, 340.0, 195.0),
    (880.0, 310.0, 160.0),
    (1150.0, 284.0, 175.0),
]
# The Saddle: the named pass between the shoulder summits — a deliberate,
# smooth, readable col carved into the main crest.
SADDLE_X = -245.0
SADDLE_HALFW = 150.0
SADDLE_DROP = 0.42  # fraction of local crest height removed at the notch
SUMMITS_FAR = [
    (-1550.0, 560.0, 320.0),
    (-1050.0, 596.0, 320.0),
    (-580.0, 640.0, 300.0),
    (-160.0, 700.0, 280.0),
    (320.0, 900.0, 300.0),    # THE SUMMIT — Shrine 8, the hermitage
    (820.0, 680.0, 300.0),
    (1300.0, 622.0, 320.0),
    (1750.0, 588.0, 330.0),
]
SUMMIT_X = 320.0  # THE Summit's bearing, used for the hermitage marker
SUMMITS_FOOT = [
    (-950.0, 108.0, 180.0),
    (-720.0, 118.0, 180.0),
    (-430.0, 96.0, 160.0),
    (-170.0, 126.0, 170.0),
    (140.0, 104.0, 160.0),
    (420.0, 122.0, 175.0),
    (700.0, 100.0, 160.0),
    (950.0, 95.0, 170.0),
]

RANKS = [
    # zc/depth define the strip; curve recesses the strip at |x| (the arc).
    dict(name="foot", zc=-450.0, depth=260.0, xh=1150.0, summits=SUMMITS_FOOT,
         base_frac=0.55, step=6.0, haze=0.05, snow_frac=2.5, curve=180.0),
    dict(name="main", zc=-760.0, depth=360.0, xh=1500.0, summits=SUMMITS_MAIN,
         base_frac=0.60, step=6.0, haze=0.13, snow_frac=0.78, curve=220.0),
    dict(name="far", zc=-1060.0, depth=460.0, xh=2000.0, summits=SUMMITS_FAR,
         base_frac=0.62, step=10.0, haze=0.52, snow_frac=0.50, curve=340.0),
]
BASE_Y = -12.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def crest_profile(x, summits, base_frac, crest_noise, saddle=False):
    """Connected ridgeline: smooth-max of summit gaussians over an undulating
    base ridge — one massif, not separate cones. saddle=True carves the
    named Saddle col into the main wall."""
    hmax = max(s[1] for s in summits)
    base = hmax * base_frac * (0.82 + 0.18 * crest_noise)
    acc = np.full_like(x, 1e-9)
    k = 9.0  # smooth-max sharpness
    for sx, sh, sw in summits:
        g = sh * np.exp(-((x - sx) / sw) ** 2)
        acc = acc + np.exp((g - hmax) / hmax * k)
    smax = hmax + np.log(acc) * hmax / k
    crest = np.maximum(base, smax)
    if saddle:
        notch = np.exp(-((x - SADDLE_X) / SADDLE_HALFW) ** 2)
        crest = crest * (1.0 - SADDLE_DROP * notch)
    return crest


def box_blur(a, k):
    """Separable box blur, repeated 3x ≈ gaussian. k = half-width in cells."""
    out = a.copy()
    for _ in range(3):
        c = np.cumsum(np.pad(out, ((0, 0), (k + 1, k)), mode="edge"), axis=1)
        out = (c[:, 2 * k + 1:] - c[:, :-2 * k - 1]) / (2 * k + 1)
        c = np.cumsum(np.pad(out, ((k + 1, k), (0, 0)), mode="edge"), axis=0)
        out = (c[2 * k + 1:, :] - c[:-2 * k - 1, :]) / (2 * k + 1)
    return out


def rank_height_and_masks(rank, xs, zs):
    """Heightfield for one rank. Returns H plus masks used for coloring."""
    zz_axis = zs
    xx, zz = np.meshgrid(xs, zz_axis)
    # The arc: the strip recesses parabolically at |x| so the wall bends
    # around the meadow instead of being a flat billboard.
    z_arc = zz + rank["curve"] * (xx / rank["xh"]) ** 2
    v = (z_arc - (rank["zc"] + rank["depth"] * 0.5)) / (-rank["depth"])  # 0 front → 1 back
    v = np.clip(v, 0.0, 1.0)

    # Domain warp — breaks up any grid feel, makes spurs meander.
    wx = grid_noise(N_WARP_X, xs, zz_axis) * 90.0
    wz = grid_noise(N_WARP_Z, xs, zz_axis) * 90.0

    # Ridged fBm sampled in warped space: the spur/gully skeleton. In [0,1].
    # Low base frequency = big landforms; the ^1.55 sharpens ridge crests
    # without adding sawtooth noise.
    r = grid_noise_warped(N_RIDGE, xx + wx, z_arc + wz)
    r = (r + 1.0) * 0.5
    r = r ** 1.55

    # Depth envelope: steep front face, crest ~62 %, easier back slope.
    front = smoothstep(0.02, 0.62, v) ** 1.25
    back = 1.0 - smoothstep(0.62, 1.0, v) * 0.85
    env = front * back

    # Crest line across x.
    cn = grid_noise(N_CREST, xs, zz_axis)
    crest = crest_profile(xx, rank["summits"], rank["base_frac"], cn,
                          saddle=(rank["name"] == "main"))

    hgt = crest * env * (0.50 + 0.60 * r)

    # Couloir carve: ridged channels stretched down-face (z squashed) —
    # the drainage that makes a face read as mountain, not lump.
    # Long fall-line chutes ("slopes literally follow steepest descent"):
    # channels squashed harder down-face and carved with a smooth parabolic
    # cross-section — slides, not cracks. Loss-surface reading: smooth
    # valley bowls between sharp ridges.
    g = grid_noise_warped(N_GULLY, xx + wx * 0.4, z_arc * 0.22)
    g = (g + 1.0) * 0.5
    couloir = (1.0 - g) ** 1.8
    hgt -= couloir * 40.0 * env

    # Talus aprons flaring at the foot.
    apron = grid_noise(N_APRON, xs, zz_axis)
    hgt += (1.0 - smoothstep(0.0, 0.30, v)) * (10.0 + 8.0 * apron)

    # Micro crag jitter, stronger on the carved faces.
    crag = grid_noise(N_CRAG, xs, zz_axis)
    hgt += crag * 2.2 * env

    hgt = np.maximum(hgt, 0.0) + BASE_Y

    # Crest relaxation: blur the top zone so summits read as solid horns,
    # not needle clusters — mid-face drainage detail is untouched.
    relc = (hgt - BASE_Y) / np.maximum(crest, 1.0)
    smooth_w = smoothstep(0.55, 0.95, relc) * 0.60
    hgt = hgt * (1.0 - smooth_w) + box_blur(hgt, max(2, int(14.0 / rank["step"]))) * smooth_w

    # Valley-bottom relaxation: hollows get an extra smoothing dose so
    # minima read as smooth bowls (the loss-surface look, and everything
    # that "rolls downhill" plausibly comes to rest there).
    hollow0 = np.clip((box_blur(hgt, max(2, int(20.0 / rank["step"]))) - hgt) / 14.0, 0.0, 1.0)
    bowl = box_blur(hgt, max(2, int(10.0 / rank["step"])))
    hgt = hgt * (1.0 - hollow0 * 0.5) + bowl * (hollow0 * 0.5)

    # Cavity: local height vs neighborhood — positive = hollow. Drives the
    # baked ambient-occlusion shading that carves the faces visually.
    k = max(2, int(24.0 / rank["step"]))
    cavity = box_blur(hgt, k) - hgt
    cavity = np.clip(cavity / 18.0, -1.0, 1.0)
    return hgt, dict(v=v, ridge=r, couloir=couloir, crest=crest, cavity=cavity)


def grid_noise_warped(n, wxx, wzz):
    coords = np.stack([wxx.ravel(), wzz.ravel()], axis=0).astype(np.float32)
    out = np.asarray(n.gen_from_coords(coords), dtype=np.float64)
    return out.reshape(wxx.shape)


# ------------------------------------------------------------ rank coloring
ROCK_WARM = np.array([0.302, 0.262, 0.230])
ROCK_COOL = np.array([0.208, 0.226, 0.288])
ROCK_HIGH = np.array([0.238, 0.228, 0.338])   # altitude-cooled violet slate
SCREE = np.array([0.398, 0.362, 0.312])
TURF_SAGE = np.array([0.352, 0.408, 0.262])   # muted — no lime allowed
TURF_GOLD = np.array([0.502, 0.442, 0.224])   # Datasedge golden-farmland kin
SCRUB_SAFFRON = np.array([0.545, 0.418, 0.198])  # summit-saffron scrub band
FROST_RIME = np.array([0.760, 0.790, 0.865])  # the frostline band
CONIFER = np.array([0.172, 0.248, 0.176])     # foothill forest fuzz
SNOW_SUN = np.array([0.930, 0.948, 0.985])
SNOW_SHADE = np.array([0.796, 0.852, 0.950])
HAZE_COL = np.array([0.72, 0.82, 0.90])


def rank_colors(rank, xs, zs, hgt, masks, normals):
    xx, zz = np.meshgrid(xs, zs)
    ny = normals[..., 1]
    rel = (hgt - BASE_Y) / np.maximum(masks["crest"], 1.0)

    litho = (grid_noise(N_LITHO, xs, zs) + 1.0) * 0.5
    litho = smoothstep(0.25, 0.75, litho)  # more contrast between lithologies
    col = ROCK_WARM[None, None, :] * litho[..., None] + ROCK_COOL[None, None, :] * (1.0 - litho[..., None])

    # Strata banding, warped so it reads geological not procedural.
    sw = grid_noise(N_STRATA_WARP, xs, zs)
    strata = np.sin(hgt * 0.045 + sw * 2.6) * 0.5 + 0.5
    col *= (0.95 + strata[..., None] * 0.08)

    # THE GRADIENT: rock cools warm→violet-slate with altitude — the
    # region's name painted straight onto the massif, read bottom-to-top.
    grad = smoothstep(0.25, 0.90, rel)
    col = col * (1.0 - grad[..., None] * 0.42) + ROCK_HIGH[None, None, :] * (grad[..., None] * 0.42)

    # Baked AO: cavity (blurred-height diff) + couloir mask — carves the
    # drainage into the faces. Hollows darken AND cool (sky-lit shadow).
    cool = masks["couloir"]
    ao = np.clip(np.maximum(masks["cavity"], 0.0) * 0.9 + cool * 0.45, 0.0, 1.0)
    col *= (1.0 - ao[..., None] * 0.42)
    col[..., 2] += ao * 0.030
    ridge_hi = smoothstep(0.72, 0.95, masks["ridge"]) * np.clip(-masks["cavity"], 0, 1)
    col *= (1.0 + ridge_hi[..., None] * 0.10)     # sun-bleached crests

    # Gentle low slopes: turf → scree by altitude & slope; conifer fuzz
    # patches on the foothill rank's gentler faces (forest at a distance).
    gentle = smoothstep(0.80, 0.94, ny)
    low = 1.0 - smoothstep(0.16, 0.42, rel)
    if rank["name"] == "foot":
        low = 1.0 - smoothstep(0.30, 0.65, rel)
    turf_m = gentle * low
    turf_col = TURF_GOLD if rank["name"] == "foot" else TURF_SAGE
    col = col * (1.0 - turf_m[..., None]) + turf_col[None, None, :] * turf_m[..., None]
    # Saffron scrub: the amber band between turf and bare rock (summit
    # saffron grows here) — one more readable rung on the altitude ladder.
    scrub_n = (grid_noise(N_FOREST, xs, zs) + 1.0) * 0.5
    if rank["name"] == "foot":
        scrub = smoothstep(0.40, 0.55, rel) * (1.0 - smoothstep(0.62, 0.80, rel)) \
            * smoothstep(0.60, 0.82, ny) * (0.5 + 0.5 * scrub_n)
    else:
        scrub = smoothstep(0.28, 0.42, rel) * (1.0 - smoothstep(0.46, 0.62, rel)) \
            * smoothstep(0.66, 0.86, ny) * (0.45 + 0.55 * scrub_n)
    col = col * (1.0 - scrub[..., None] * 0.65) + SCRUB_SAFFRON[None, None, :] * (scrub[..., None] * 0.65)
    if rank["name"] == "foot":
        forest_n = (grid_noise(N_FOREST, xs, zs) + 1.0) * 0.5
        forest = smoothstep(0.58, 0.78, forest_n) * smoothstep(0.74, 0.90, ny) \
            * (1.0 - smoothstep(0.5, 0.75, rel))
        fcol = CONIFER[None, None, :] * (0.9 + 0.2 * forest_n[..., None])
        col = col * (1.0 - forest[..., None]) + fcol * forest[..., None]
    scree_m = smoothstep(0.62, 0.83, ny) * (1.0 - gentle) * (1.0 - smoothstep(0.30, 0.55, rel))
    col = col * (1.0 - scree_m[..., None] * 0.7) + SCREE[None, None, :] * (scree_m[..., None] * 0.7)

    # ---- snow: altitude line (noisy), sheds on steeps, lingers in couloirs.
    snow = np.zeros_like(hgt)
    if rank["snow_frac"] <= 1.0:
        line = masks["crest"] * rank["snow_frac"] + BASE_Y
        wander = grid_noise(N_SNOWLINE, xs, zs) * 30.0
        line = line + wander - cool * 40.0          # couloirs hold snow lower
        alt = smoothstep(0.0, 16.0, hgt - line)
        hold = smoothstep(0.48, 0.78, ny)            # cliffs shed
        hold = np.maximum(hold, cool * 0.9)          # …but couloirs pack it
        cap = smoothstep(40.0, 90.0, hgt - line)     # summit cap: rime holds
        hold = np.maximum(hold, cap)                 # even on the steeps
        snow = alt * hold
        scour = smoothstep(0.90, 1.0, masks["ridge"]) * smoothstep(0.5, 0.9, rel) \
            * (1.0 - cap)
        snow *= (1.0 - scour * 0.30)                 # wind-scoured crests
    if rank["snow_frac"] <= 1.0:
        # The frostline: a crisp pale rime band just below the snow —
        # altitude banding made visible (the Frostline Golems' home turf).
        rime_band = smoothstep(-22.0, -8.0, hgt - line) * (1.0 - smoothstep(-4.0, 4.0, hgt - line))
        col = col * (1.0 - rime_band[..., None] * 0.5) + FROST_RIME[None, None, :] * (rime_band[..., None] * 0.5)
    snow_col = SNOW_SUN[None, None, :] * (1.0 - ao[..., None] * 0.6) + \
        SNOW_SHADE[None, None, :] * (ao[..., None] * 0.6)
    col = col * (1.0 - snow[..., None]) + snow_col * snow[..., None]

    # Rank haze pre-bake (aerial perspective layering).
    col = col * (1.0 - rank["haze"]) + HAZE_COL[None, None, :] * rank["haze"]
    return np.clip(col, 0.0, 1.0), snow


# --------------------------------------------------------------- the meadow
# Port of meadow_terrain.gd (seed 20260716) + the north alpine-blend FIX.
WORLD_SEED = 20260716
M_ROLL = make_noise(WORLD_SEED, 0.008, octaves=4)
M_MACRO = make_noise(WORLD_SEED + 1, 0.0016, octaves=2)
M_DETAIL = make_noise(WORLD_SEED + 2, 0.06, octaves=2)
M_TINT = make_noise(WORLD_SEED + 3, 0.02, octaves=3)
TOWN_CENTER = np.array([0.0, 30.0])
POND_CENTER = np.array([95.0, 10.0])


def meadow_height(xs, zs):
    xx, zz = np.meshgrid(xs, zs)
    h = grid_noise(M_ROLL, xs, zs) * 6.5 + grid_noise(M_MACRO, xs, zs) * 11.0 \
        + grid_noise(M_DETAIL, xs, zs) * 0.45
    h += 22.0 * smoothstep(110.0, 240.0, -zz) ** 1.6
    h -= 9.0 * smoothstep(140.0, 240.0, -xx)
    town_d = np.hypot(xx - TOWN_CENTER[0], zz - TOWN_CENTER[1])
    th = 2.35  # town height approx (sampled once in game)
    h = th + (h - th) * smoothstep(38.0, 75.0, town_d)
    pond_d = np.hypot(xx - POND_CENTER[0], zz - POND_CENTER[1])
    h -= 3.0 * (1.0 - smoothstep(24.0 * 0.35, 24.0, pond_d))
    return h


def meadow_colors(xs, zs, hgt, normals, fixed=True):
    xx, zz = np.meshgrid(xs, zs)
    ny = normals[..., 1]
    meadow_light = np.array([0.43, 0.60, 0.22])
    meadow_deep = np.array([0.31, 0.52, 0.18])
    dry_gold = np.array([0.70, 0.62, 0.33])
    rock = np.array([0.50, 0.46, 0.39])
    t = np.clip((grid_noise(M_TINT, xs, zs) + 1.0) * 0.5, 0, 1)
    col = meadow_deep[None, None, :] + (meadow_light - meadow_deep)[None, None, :] * t[..., None]
    dry_n = grid_noise_warped(M_TINT, xx + 900.0, zz - 900.0)
    dry = smoothstep(0.55, 0.8, (dry_n + 1.0) * 0.5)
    col = col * (1.0 - dry[..., None] * 0.35) + dry_gold[None, None, :] * (dry[..., None] * 0.35)
    steep = smoothstep(0.82, 0.60, ny)  # reversed edges in gd: smoothstep(0.82,0.6,ny)
    col = col * (1.0 - steep[..., None]) + rock[None, None, :] * steep[..., None]
    col *= (0.94 + 0.06 * t[..., None])

    if fixed:
        # THE LIME-BAND FIX — north band climbs out of lush meadow into
        # alpine sage then scree as the foothills rise toward the wall.
        alpine = smoothstep(90.0, 205.0, -zz)
        sage = np.array([0.398, 0.398, 0.242])  # warm gold-sage, Datasedge identity
        col = col * (1.0 - alpine[..., None] * 0.72) + sage[None, None, :] * (alpine[..., None] * 0.72)
        scree_band = smoothstep(190.0, 240.0, -zz)
        col = col * (1.0 - scree_band[..., None] * 0.45) + SCREE[None, None, :] * (scree_band[..., None] * 0.45)
        col *= (1.0 - alpine[..., None] * 0.10)  # calm the grazing-light pop
    # PROTO-ONLY: in game the near field is covered by 400k sage grass
    # blades; tint the bare terrain toward blade color so this render
    # matches what the camera actually sees. Do NOT port this line.
    col *= np.array([0.70, 0.76, 0.70])[None, None, :]
    return np.clip(col, 0, 1)


# ------------------------------------------------------------ mesh helpers
def normals_from_grid(hgt, step):
    ny = np.empty(hgt.shape + (3,))
    dx = np.zeros_like(hgt)
    dz = np.zeros_like(hgt)
    dx[:, 1:-1] = hgt[:, :-2] - hgt[:, 2:]
    dz[1:-1, :] = hgt[:-2, :] - hgt[2:, :]
    ny[..., 0] = dx
    ny[..., 1] = 2.0 * step
    ny[..., 2] = dz
    ny /= np.linalg.norm(ny, axis=-1, keepdims=True)
    return ny


def grid_to_tris(xs, zs, hgt, cols, snow=None):
    xx, zz = np.meshgrid(xs, zs)
    P = np.stack([xx, hgt, zz], axis=-1)
    nz, nx = hgt.shape
    i = np.arange(nz - 1)[:, None] * nx + np.arange(nx - 1)[None, :]
    a = i.ravel()
    b = a + 1
    c = a + nx
    d = c + 1
    tris = np.concatenate([np.stack([a, c, b], 1), np.stack([b, c, d], 1)])
    V = P.reshape(-1, 3)
    C = cols.reshape(-1, 3)
    S = snow.reshape(-1) if snow is not None else np.zeros(len(V))
    return V, C, S, tris


# ------------------------------------------------- the Gradientfall cascade
FALL_COL = np.array([0.80, 0.92, 1.00])
FALL_X = -40.0  # spills off the monarch's west flank — dark rock behind it
POOL_COL = np.array([0.62, 0.80, 0.92])


def trace_cascade(xs, zs, hgt, start_x):
    """Run literal gradient descent on the heightfield from the Saddle: the
    waterfall follows the steepest slope; where it stalls in a local
    minimum it forms a plunge pool, then spills onward. Returns
    (path pts Nx3, pool pts Mx3) in world coords."""
    nx_, nz_ = len(xs), len(zs)
    ix = int(np.argmin(np.abs(xs - start_x)))
    # start just below the crest on the FRONT face: from the crest row walk
    # south until altitude dips below the local snowline zone — the fall is
    # born where dark rock begins, so the white ribbon always has contrast.
    iz = int(np.argmax(hgt[:, ix]))
    crest_h = hgt[iz, ix]
    while iz + 1 < nz_ and hgt[iz + 1, ix] > crest_h * 0.88:
        iz += 1
    path, pools = [], []
    seen = set()
    for _ in range(4000):
        path.append((xs[ix], hgt[iz, ix], zs[iz]))
        seen.add((iz, ix))
        best, bh = None, hgt[iz, ix]
        # front-face constraint: the fall may meander in x but only ever
        # moves toward the viewer (south) — it must stream down the face
        # the player actually sees.
        for dz in (0, 1):
            for dx in (-1, 0, 1):
                if dz == 0 and dx == 0:
                    continue
                jz, jx = iz + dz, ix + dx
                if 0 <= jz < nz_ and 0 <= jx < nx_ and (jz, jx) not in seen:
                    if hgt[jz, jx] < bh:
                        bh, best = hgt[jz, jx], (jz, jx)
        if best is None:
            # local minimum: plunge pool, then spill over the lowest rim
            pools.append((xs[ix], hgt[iz, ix], zs[iz]))
            rim, rh = None, 1e9
            for dz in (0, 1, 2):
                for dx in (-2, -1, 0, 1, 2):
                    jz, jx = iz + dz, ix + dx
                    if 0 <= jz < nz_ and 0 <= jx < nx_ and (jz, jx) not in seen:
                        if hgt[jz, jx] < rh:
                            rh, rim = hgt[jz, jx], (jz, jx)
            if rim is None:
                break
            best = rim
        iz, ix = best
        if hgt[iz, ix] < BASE_Y + 14.0:
            break
    return np.array(path), np.array(pools) if pools else np.zeros((0, 3))


def cascade_mesh(path, pools, width=18.0, lift=3.0):
    """Ribbon quads along the fall path + pool disks. Returns (V, C, S, T)."""
    verts, cols, snows, tris = [], [], [], []
    for i in range(len(path) - 1):
        p0, p1 = path[i], path[i + 1]
        d = p1 - p0
        side = np.cross(d, [0.0, 1.0, 0.0])
        n = np.linalg.norm(side)
        if n < 1e-6:
            continue
        side = side / n * (width * 0.5)
        base = len(verts)
        for q in (p0 - side, p0 + side, p1 - side, p1 + side):
            verts.append([q[0], q[1] + lift, q[2]])
            cols.append(FALL_COL)
            snows.append(0.85)  # rides the snow channel → foam glint
        tris += [[base, base + 2, base + 1], [base + 1, base + 2, base + 3]]
    for p in pools:
        base = len(verts)
        segs = 10
        verts.append([p[0], p[1] + lift * 0.7, p[2]])
        cols.append(POOL_COL)
        snows.append(0.5)
        for a in range(segs):
            th = a / segs * 2 * math.pi
            verts.append([p[0] + math.cos(th) * 11.0, p[1] + lift * 0.7, p[2] + math.sin(th) * 11.0])
            cols.append(POOL_COL)
            snows.append(0.5)
        for a in range(segs):
            tris.append([base, base + 1 + a, base + 1 + (a + 1) % segs])
    return (np.array(verts), np.array(cols), np.array(snows), np.array(tris))


# ------------------------------------------------------- Overshoot Ledge
def ledge_mesh(xs=None, zs=None, hgt=None):
    """The named prow jutting off the monarch's east shoulder — a shelf that
    overshoots the face and hangs over air (the joke IS the landmark).
    Anchored by sampling the real face: back edge buried in rock."""
    cx = 230.0
    if hgt is not None:
        ix = int(np.argmin(np.abs(xs - cx)))
        iz = int(np.argmax(hgt[:, ix]))   # the local crest cell
        cz = zs[iz] + 30.0   # straddles the crest, prow thrust south over air
        cy = hgt[iz, ix] + 3.0
    else:
        cz, cy = -742.0, 296.0
    hw, hd = 56.0, 34.0
    verts, cols, snows, tris = [], [], [], []
    rock = np.array([0.145, 0.148, 0.185])  # deep shadowed underside
    top = np.array([0.90, 0.92, 0.96])  # snow-dusted top
    # top slab (2x1 quads), tilted slightly up toward the tip (overshoot!)
    corners = [(-hw, -hd), (hw, -hd), (-hw, hd + 40.0), (hw, hd + 40.0)]
    for (dx, dz) in corners:
        tip = smoothstep(np.array(-hd), np.array(hd + 40.0), np.array(dz)) * 12.0
        verts.append([cx + dx, cy + float(tip), cz + dz])
        cols.append(top)
        snows.append(0.7)
    tris += [[0, 2, 1], [1, 2, 3]]
    # underside skirt dropping into the face
    base = len(verts)
    for (dx, dz) in corners:
        verts.append([cx + dx * 0.82, cy - 26.0, cz + dz * 0.7])
        cols.append(rock)
        snows.append(0.0)
    tris += [[0, 1, base], [1, base + 1, base], [2, base + 2, 3], [3, base + 2, base + 3],
             [0, base, 2], [2, base, base + 2], [1, 3, base + 1], [3, base + 3, base + 1]]
    return (np.array(verts, dtype=float), np.array(cols), np.array(snows), np.array(tris))


# =================================================================
#  NORTH-APPROACH DENSITY (the BOTW "something is actually there" pass)
#  These previews mirror real game content: grass = the in-game 400k
#  field; trees/boulders/village port to peaks_approach.gd.
# =================================================================
APPROACH_SEED = 20260719
CONIFER_HI = np.array([0.128, 0.196, 0.150])   # alpine spruce, cool
CONIFER_LO = np.array([0.205, 0.300, 0.170])   # warmer lower firs
BOULDER_COL = np.array([0.520, 0.495, 0.470])
GRASS_A = np.array([0.300, 0.470, 0.180])
GRASS_B = np.array([0.410, 0.545, 0.205])
GRASS_GOLD = np.array([0.640, 0.560, 0.235])
GRASS_SAGE = np.array([0.398, 0.430, 0.262])   # alpine grass, high north


def mesh5(V, C, S, T, up=False):
    """Standard mesh tuple + an nflag per triangle: 1 = shade with world-up
    (grass, foliage, thatch — lit bright like ground, not by facet normal)."""
    T = np.asarray(T)
    flag = np.ones(len(T)) if up else np.zeros(len(T))
    return (np.asarray(V, float), np.asarray(C, float), np.asarray(S, float), T, flag)


def _meadow_ground(x, z):
    return meadow_height(np.array([x]), np.array([z]))[0, 0]


def _grass_colors(rng, xs, zs, n, per, nclump):
    clump_t = np.repeat(rng.random(nclump), per)
    base = GRASS_A[None] + (GRASS_B - GRASS_A)[None] * clump_t[:, None]
    goldm = (np.repeat(rng.random(nclump), per) < 0.10)[:, None]
    base = np.where(goldm, base * 0.6 + GRASS_GOLD[None] * 0.4, base)
    alpine = smoothstep(90.0, 215.0, -zs)[:, None]
    col = base * (1 - alpine * 0.8) + GRASS_SAGE[None] * (alpine * 0.8)
    return col * (0.9 + 0.18 * rng.random(n)[:, None])


def _blades_to_mesh(xs, zs, gh, height, lean, col, w):
    n = len(xs)
    # deterministic per-blade azimuth from a position hash (no rng coupling)
    ang = (np.sin(xs * 12.9898 + zs * 78.233) * 43758.5453) % (2 * math.pi)
    dirx, dirz = np.cos(ang), np.sin(ang)
    perpx, perpz = -dirz * w, dirx * w
    V = np.zeros((n * 3, 3)); C = np.zeros((n * 3, 3))
    V[0::3] = np.stack([xs - perpx, gh, zs - perpz], 1)
    V[1::3] = np.stack([xs + perpx, gh, zs + perpz], 1)
    V[2::3] = np.stack([xs + dirx * lean, gh + height, zs + dirz * lean], 1)
    for k in range(3):
        C[k::3] = col
    T = np.arange(n * 3).reshape(n, 3)
    keep = (gh > 0.2) & (np.abs(xs) < 238) & (zs < 248)
    return V, C, T[keep]


def grass_carpet_mesh(cam_center, n=52000):
    """The dense near-field carpet — the thing that makes the foreground read
    as lush grass instead of bare terrain. Concentrated in a disc around the
    point the player is looking at (1/dist falloff), short and full. Mirrors
    the in-game 400k camera-follow field, which is likewise densest underfoot
    (do NOT port — the grass field already ships in meadow_flora.gd)."""
    rng = np.random.default_rng(APPROACH_SEED + 7)
    # radial placement, dense at the center, out to ~150 m
    rad = rng.random(n) ** 1.7 * 150.0
    ang = rng.uniform(0, 2 * math.pi, n)
    xs = cam_center[0] + np.cos(ang) * rad
    zs = cam_center[2] + np.sin(ang) * rad
    gh = _ground_batch(xs, zs)
    height = rng.uniform(0.28, 0.62, n)
    lean = rng.uniform(0.04, 0.16, n)
    # cheap coherent hue: bucket by rounded position
    key = (np.round(xs / 6) * 131 + np.round(zs / 6)).astype(np.int64)
    hue = (np.sin(key.astype(np.float64)) * 0.5 + 0.5)
    base = GRASS_A[None] + (GRASS_B - GRASS_A)[None] * hue[:, None]
    alpine = smoothstep(90.0, 215.0, -zs)[:, None]
    col = base * (1 - alpine * 0.8) + GRASS_SAGE[None] * (alpine * 0.8)
    col = col * (0.88 + 0.2 * rng.random(n)[:, None])
    V, C, T = _blades_to_mesh(xs, zs, gh, height, lean, col, 0.12)
    return mesh5(V, C, np.zeros(len(V)), T, up=True)


def grass_field_mesh(n=26000):
    """Taller accent tufts across the whole meadow (the in-game 36k mid-
    distance layer) — clumped for coherent color drifts, occasional gold."""
    rng = np.random.default_rng(APPROACH_SEED)
    nclump = n // 6
    n = nclump * 6
    cx = rng.uniform(-235, 235, nclump)
    cz = rng.uniform(-235, 245, nclump)
    per = np.full(nclump, 6)
    xs = np.repeat(cx, per) + rng.normal(0, 1.3, n)
    zs = np.repeat(cz, per) + rng.normal(0, 1.3, n)
    gh = _ground_batch(xs, zs)
    height = rng.uniform(0.6, 1.15, n)
    lean = rng.uniform(0.12, 0.34, n)
    col = _grass_colors(rng, xs, zs, n, per, nclump)
    V, C, T = _blades_to_mesh(xs, zs, gh, height, lean, col, 0.09)
    return mesh5(V, C, np.zeros(len(V)), T, up=True)


def _ground_batch(xs, zs):
    """meadow_height over scattered points (not a grid) — chunked meshgrid
    diagonal is wasteful, so sample directly via the noise fields."""
    h = grid_noise_scatter(M_ROLL, xs, zs) * 6.5 + grid_noise_scatter(M_MACRO, xs, zs) * 11.0 \
        + grid_noise_scatter(M_DETAIL, xs, zs) * 0.45
    h += 22.0 * smoothstep(110.0, 240.0, -zs) ** 1.6
    h -= 9.0 * smoothstep(140.0, 240.0, -xs)
    town_d = np.hypot(xs - TOWN_CENTER[0], zs - TOWN_CENTER[1])
    h = 2.35 + (h - 2.35) * smoothstep(38.0, 75.0, town_d)
    pond_d = np.hypot(xs - POND_CENTER[0], zs - POND_CENTER[1])
    h -= 3.0 * (1.0 - smoothstep(24.0 * 0.35, 24.0, pond_d))
    return h


def grid_noise_scatter(n, xs, zs):
    coords = np.stack([xs, zs], axis=0).astype(np.float32)
    return np.asarray(n.gen_from_coords(coords), dtype=np.float64)


def _impostor_tree(x, y, z, h, r, col, verts, cols, snows, tris, canopy_up=True):
    """Cheap 3-blob conifer: a brown spire + stacked foliage triangles facing
    the camera-ish (billboarded in +x). Enough to read as a tree at range."""
    # trunk
    b = len(verts)
    verts += [[x - r * 0.09, y, z], [x + r * 0.09, y, z], [x, y + h * 0.4, z]]
    trunk = [0.20, 0.14, 0.10]
    cols += [trunk, trunk, trunk]; snows += [0, 0, 0]
    tris += [[b, b + 1, b + 2]]
    # 3 stacked foliage triangles (conifer silhouette)
    for k, (fy, fr) in enumerate([(0.30, 1.0), (0.55, 0.72), (0.78, 0.44)]):
        b = len(verts)
        yy = y + h * fy
        verts += [[x - r * fr, yy, z], [x + r * fr, yy, z], [x, yy + h * 0.34, z]]
        c = np.array(col) * (0.85 + 0.15 * k)
        cols += [c, c, c]; snows += [0, 0, 0]
        tris += [[b, b + 1, b + 2]]


def treeline_mesh(count=760):
    """Alpine forest climbing the north foothills — dense at the meadow's
    edge, thinning upward to a ragged treeline, cool spruce up high, warmer
    firs low. This is what fills the empty gap between field and rock wall."""
    rng = np.random.default_rng(APPROACH_SEED + 1)
    verts, cols, snows, tris = [], [], [], []
    placed = 0
    tries = 0
    while placed < count and tries < count * 6:
        tries += 1
        z = rng.uniform(-248, -95)
        # density falls with altitude (latitude here): reject upper trees more
        alt = smoothstep(-248, -110, z)  # 1 low, 0 high
        if rng.random() > 0.15 + 0.85 * alt:
            continue
        x = rng.uniform(-232, 232)
        # avoid the town core and the pond
        if math.hypot(x - TOWN_CENTER[0], z - TOWN_CENTER[1]) < 46:
            continue
        y = _ground_batch(np.array([x]), np.array([z]))[0]
        if y < 0.4:
            continue
        h = rng.uniform(3.4, 6.2) * (1.15 - 0.35 * (1 - alt))
        r = h * rng.uniform(0.26, 0.34)
        col = CONIFER_LO * alt + CONIFER_HI * (1 - alt)
        col = col * (0.85 + 0.3 * rng.random())
        _impostor_tree(x, y, z, h, r, col, verts, cols, snows, tris)
        placed += 1
    print(f"  treeline: {placed} alpine conifers")
    return mesh5(verts, cols, snows, tris, up=True)


def boulder_mesh(count=68):
    """Sorted stones on the approach — WORLDBOOK: 'the mountains are slowly
    sorting themselves.' Low down they are scattered, random-sized erratics;
    climbing toward the peaks they grow larger and visibly ALIGN (shared
    heading, graded sizes) — quiet, on-theme environmental storytelling.
    Geometry: a hexagonal bipyramid (rounded low-poly rock) with per-vertex
    jitter, lit by facet normals so it reads as solid stone."""
    rng = np.random.default_rng(APPROACH_SEED + 2)
    verts, cols, snows, tris = [], [], [], []
    for _ in range(count):
        z = rng.uniform(-250, -35)
        x = rng.uniform(-234, 234)
        if math.hypot(x - TOWN_CENTER[0], z - TOWN_CENTER[1]) < 42:
            continue
        y = _ground_batch(np.array([x]), np.array([z]))[0]
        if y < 0.4:
            continue
        sort = smoothstep(-60, -240, z)               # 0 low → 1 high (sorted)
        size = rng.uniform(1.1, 2.4) * (1.0 + sort * 1.7)
        if sort > 0.4:                                # graded sizes up high
            size = rng.uniform(2.2, 3.4) * (1.0 + sort * 0.8)
        head = rng.uniform(0, math.pi) * (1 - sort) + math.radians(22) * sort
        ch, sh = math.cos(head), math.sin(head)
        b = len(verts)
        # squat, wide, blunt-topped — a sunlit boulder, not a tent.
        top = [x + size * 0.1, y + size * rng.uniform(0.5, 0.68), z]
        bot = [x, y - size * 0.1, z]
        ring = []
        for a in range(6):
            th = a / 6 * 2 * math.pi
            rr = size * (1.02 + 0.32 * rng.random())      # wider than tall
            dx, dz = math.cos(th) * rr, math.sin(th) * rr * 0.9
            ring.append([x + dx * ch - dz * sh,
                         y + size * (0.14 + 0.18 * rng.random()),
                         z + dx * sh + dz * ch])
        base_col = BOULDER_COL * (1.05 - sort * 0.1)
        for p in [top, bot] + ring:
            verts.append(p)
            cols.append(base_col * (0.92 + 0.16 * rng.random()))
            snows.append(0.0)
        for a in range(6):
            n1, n2 = b + 2 + a, b + 2 + (a + 1) % 6
            tris += [[b, n1, n2], [b + 1, n2, n1]]
    print(f"  boulders: {count} sorted stones")
    return mesh5(verts, cols, snows, tris, up=False)


def village_mesh():
    """Descent's Rest (WORLDBOOK §3): the switchback village on the foothills.
    Terraced houses with warm-lit windows and dark peaked roofs — the vista
    payoff that says 'something is actually there' when you look north."""
    verts, cols, snows, tris = [], [], [], []
    rng = np.random.default_rng(APPROACH_SEED + 3)
    # terraced switchback shelves, climbing NW
    cx0, cz0 = -118.0, -212.0
    wall = np.array([0.62, 0.52, 0.40])
    roof = np.array([0.34, 0.20, 0.17])
    win = np.array([1.0, 0.74, 0.42])
    for row in range(4):
        shelf_x = cx0 - row * 14.0
        shelf_z = cz0 - row * 8.0
        y = _ground_batch(np.array([shelf_x]), np.array([shelf_z]))[0] + row * 2.2
        for h_i in range(3 + (row % 2)):
            hx = shelf_x + h_i * 9.0 + rng.uniform(-1.5, 1.5)
            hz = shelf_z + rng.uniform(-2.0, 2.0)
            w, d, ht = 4.2, 4.0, rng.uniform(3.4, 4.6)
            b = len(verts)
            # box (8 corners)
            for (sx, sz) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
                verts.append([hx + sx * w / 2, y, hz + sz * d / 2]); cols.append(wall); snows.append(0)
            for (sx, sz) in [(-1, -1), (1, -1), (1, 1), (-1, 1)]:
                verts.append([hx + sx * w / 2, y + ht, hz + sz * d / 2]); cols.append(wall); snows.append(0)
            # walls
            for (a, bb) in [(0, 1), (1, 2), (2, 3), (3, 0)]:
                tris += [[b + a, b + bb, b + 4 + bb], [b + a, b + 4 + bb, b + 4 + a]]
            # roof ridge (2 apex verts)
            ap = len(verts)
            verts.append([hx, y + ht + 2.2, hz - d / 2]); cols.append(roof); snows.append(0)
            verts.append([hx, y + ht + 2.2, hz + d / 2]); cols.append(roof); snows.append(0)
            tris += [[b + 4, b + 5, ap], [b + 5, ap + 1, ap],
                     [b + 7, b + 6, ap + 1], [b + 7, ap + 1, ap],
                     [b + 4, ap, b + 7], [b + 5, b + 6, ap + 1]]
            # a lit window (small quad on the south face)
            wq = len(verts)
            wy = y + ht * 0.45
            verts.append([hx - 0.7, wy, hz + d / 2 + 0.02]); cols.append(win); snows.append(0.9)
            verts.append([hx + 0.7, wy, hz + d / 2 + 0.02]); cols.append(win); snows.append(0.9)
            verts.append([hx + 0.7, wy + 1.1, hz + d / 2 + 0.02]); cols.append(win); snows.append(0.9)
            verts.append([hx - 0.7, wy + 1.1, hz + d / 2 + 0.02]); cols.append(win); snows.append(0.9)
            tris += [[wq, wq + 1, wq + 2], [wq, wq + 2, wq + 3]]
    print("  village: Descent's Rest, terraced")
    return mesh5(verts, cols, snows, tris, up=False)


# ---------------------------------------------------------------- lighting
def sun_direction(hour=8.5):
    elev = math.sin((hour - 6.0) / 12.0 * math.pi)
    pitch = math.radians(6.0 + (-82.0 - 6.0) * min(max(elev * 0.5 + 0.5, 0), 1))
    yaw = math.radians(70.0 + (-70.0 - 70.0) * min(max(hour / 24.0, 0), 1))
    cp, sp = math.cos(pitch), math.sin(pitch)
    cy, sy = math.cos(yaw), math.sin(yaw)
    fwd = np.array([-cp * sy, sp, -cp * cy])  # light's -Z in world (YXZ order)
    return -fwd / np.linalg.norm(fwd)  # direction TOWARD sun


SKY_TOP = np.array([0.235, 0.485, 0.875])
SKY_HOR = np.array([0.715, 0.835, 0.935])
SUN_COL = np.array([1.0, 0.955, 0.83])
AMBIENT = np.array([0.72, 0.79, 0.92]) * 0.52
FOG_COL = np.array([0.72, 0.82, 0.90])
FILL = np.array([0.55, 0.68, 0.92])


def shade(albedo, normal, wpos, cam, snow_amt):
    sun = sun_direction()
    lam = np.clip(normal @ sun, 0.0, 1.0)
    lam = lam * 0.72 + 0.28 * np.clip(normal @ sun * 0.5 + 0.5, 0, 1)  # wrap-ish
    c = albedo * (SUN_COL * 1.02 * lam[..., None] + AMBIENT[None, :] * 0.9)
    c += FILL[None, :] * 0.12 * albedo                       # shadow fill
    # snow glint
    vdir = cam - wpos
    vdir /= np.linalg.norm(vdir, axis=-1, keepdims=True)
    hv = (vdir + sun)
    hv /= np.linalg.norm(hv, axis=-1, keepdims=True)
    spec = np.clip((normal * hv).sum(-1), 0, 1) ** 24
    c += snow_amt[..., None] * spec[..., None] * np.array([1.0, 0.98, 0.9]) * 0.35
    # distance fog (exp) + low-altitude extra (grounds the feet)
    d = np.linalg.norm(wpos - cam, axis=-1)
    dens = 0.00034 + np.clip((60.0 - wpos[..., 1]) / 60.0, 0, 1) * 0.00013
    f = 1.0 - np.exp(-d * dens)
    c = c * (1.0 - f[..., None]) + FOG_COL[None, :] * f[..., None]
    # mild tonemap + saturation nudge (approximates env adjustments)
    c = c / (1.0 + 0.18 * c)
    lum = c @ np.array([0.2126, 0.7152, 0.0722])
    c = np.clip(lum[..., None] + (c - lum[..., None]) * 1.14, 0, 1)
    return np.clip(c ** (1 / 2.2), 0.0, 1.0)


def _paint_sky(eye, Rm, fl):
    """Vertical gradient + warm horizon + a projected sun disk and bloom.
    Approximates the painterly sky the Environment/glow stack produces."""
    sky = np.zeros((H, W, 3))
    tv = np.linspace(0, 1, H)[:, None]
    grade = SKY_HOR[None, None, :] + (SKY_TOP - SKY_HOR)[None, None, :] * ((1 - tv) ** 1.6)[..., None]
    sky[:] = grade
    # warm haze band hugging the horizon line
    horizon = 1.0 - np.abs(np.linspace(-1, 1, H))[:, None]
    warm = np.array([0.93, 0.86, 0.74])
    sky = sky * (1 - (horizon ** 6) * 0.35)[..., None] + warm[None, None, :] * ((horizon ** 6) * 0.35)[..., None]
    # sun: project the light direction onto the screen
    sun = sun_direction()
    sc = (sun) @ Rm.T
    if -sc[2] > 0.05:
        sxp = W / 2 + sc[0] / (-sc[2]) * fl
        syp = H / 2 - sc[1] / (-sc[2]) * fl
        yy, xx = np.mgrid[0:H, 0:W]
        r = np.hypot(xx - sxp, yy - syp)
        glow = np.exp(-(r / 240.0) ** 2) * 0.5 + np.exp(-(r / 70.0) ** 2) * 0.8
        disk = (r < 26).astype(float)
        sunc = np.array([1.0, 0.96, 0.86])
        sky += sunc[None, None, :] * np.clip(glow + disk, 0, 1)[..., None]
    return np.clip(sky, 0, 1)


# --------------------------------------------------------------- rasterize
def render(view_yaw_deg, out_path, pitch_deg=-6.0):
    print(f"render {out_path} yaw={view_yaw_deg}")
    # camera at spawn, matching the screenshot rig (approx: eye pulled back).
    spawn = np.array([-58.0, 0.0, -62.0])
    g = meadow_height(np.array([spawn[0]]), np.array([spawn[2]]))[0, 0]
    yaw = math.radians(view_yaw_deg)
    pitch = math.radians(pitch_deg)
    fwd = np.array([-math.sin(yaw), 0.0, -math.cos(yaw)])
    fwd = fwd * math.cos(pitch) + np.array([0, 1, 0]) * math.sin(pitch)
    eye = np.array([spawn[0], g + 1.5, spawn[2]]) - fwd * 4.5 + np.array([0, 0.6, 0])
    # ground point ~55 m ahead — the near-grass carpet densifies around here.
    fwd_g = np.array([fwd[0], 0.0, fwd[2]])
    fwd_g /= np.linalg.norm(fwd_g)
    cam_center = np.array([eye[0], 0.0, eye[2]]) + fwd_g * 55.0

    meshes = []

    for rank in RANKS:
        xs = np.arange(-rank["xh"], rank["xh"] + rank["step"], rank["step"])
        zs = np.arange(rank["zc"] - rank["depth"] * 0.55,
                       rank["zc"] + rank["depth"] * 0.55 + rank["step"], rank["step"])
        hgt, masks = rank_height_and_masks(rank, xs, zs)
        nrm = normals_from_grid(hgt, rank["step"])
        col, snow = rank_colors(rank, xs, zs, hgt, masks, nrm)
        meshes.append(grid_to_tris(xs, zs, hgt, col, snow))
        if rank["name"] == "main":
            path, pools = trace_cascade(xs, zs, hgt, FALL_X)
            print(f"  cascade: {len(path)} steps, {len(pools)} plunge pools")
            meshes.append(cascade_mesh(path, pools))
            meshes.append(ledge_mesh(xs, zs, hgt))

    ms = 4.0
    xs = np.arange(-240.0, 240.0 + ms, ms)
    zs = np.arange(-240.0, 240.0 + ms, ms)
    mh = meadow_height(xs, zs)
    mn = normals_from_grid(mh, ms)
    mc = meadow_colors(xs, zs, mh, mn, fixed=True)
    meshes.append(grid_to_tris(xs, zs, mh, mc))

    # North-approach density: the BOTW "something is actually there" layer.
    meshes.append(village_mesh())
    meshes.append(boulder_mesh())
    meshes.append(treeline_mesh())
    meshes.append(grass_carpet_mesh(cam_center))
    meshes.append(grass_field_mesh())

    up = np.array([0.0, 1.0, 0.0])
    zc = -fwd
    xc = np.cross(up, zc); xc /= np.linalg.norm(xc)
    yc = np.cross(zc, xc)
    Rm = np.stack([xc, yc, zc])

    fl = (H / 2) / math.tan(math.radians(70.0 / 2))

    img = Image.new("RGB", (W, H))
    # sky gradient + a real sun disk and glow, projected from the light dir.
    sky = _paint_sky(eye, Rm, fl)
    img.paste(Image.fromarray((np.clip(sky, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)))
    dr = ImageDraw.Draw(img)

    allV = []; allC = []; allS = []; allT = []; allN = []; off = 0
    for m in meshes:
        V, C, S, T = m[0], m[1], m[2], np.asarray(m[3])
        Nf = m[4] if len(m) == 5 else np.zeros(len(T))
        allV.append(V); allC.append(C); allS.append(S)
        allT.append(T + off); allN.append(Nf)
        off += len(V)
    V = np.concatenate(allV); C = np.concatenate(allC)
    S = np.concatenate(allS); T = np.concatenate(allT)
    Nf = np.concatenate(allN)

    Vc = (V - eye) @ Rm.T
    depth = -Vc[:, 2]
    tri_d = depth[T].mean(axis=1)
    tri_ok = (depth[T] > 1.0).all(axis=1)

    # backface + frustum-ish cull then painter sort
    order = np.argsort(-tri_d)
    order = order[tri_ok[order]]

    px = W / 2 + Vc[:, 0] / np.maximum(depth, 1e-3) * fl
    py = H / 2 - Vc[:, 1] / np.maximum(depth, 1e-3) * fl

    tn_all = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    tn_all /= np.maximum(np.linalg.norm(tn_all, axis=-1, keepdims=True), 1e-9)
    # up-lit meshes (grass, foliage, thatch): shade by world-up so vertical
    # geometry catches light like ground instead of going flat-dark.
    up_mask = Nf > 0.5
    tn_all[up_mask] = np.array([0.0, 1.0, 0.0])
    cen_all = V[T].mean(axis=1)
    alb_all = C[T].mean(axis=1)
    snow_all = S[T].mean(axis=1)
    shaded = shade(alb_all, tn_all, cen_all, eye, snow_all)

    xs_t = px[T]; ys_t = py[T]
    onscreen = ((xs_t > -80) & (xs_t < W + 80) & (ys_t > -80) & (ys_t < H + 80)).any(axis=1)

    count = 0
    for i in order:
        if not onscreen[i]:
            continue
        p = [(xs_t[i, 0], ys_t[i, 0]), (xs_t[i, 1], ys_t[i, 1]), (xs_t[i, 2], ys_t[i, 2])]
        rgb = tuple((shaded[i] * 255).astype(int))
        dr.polygon(p, fill=rgb)
        count += 1
    img.save(out_path)
    print(f"  {count} tris drawn -> {out_path}")


if __name__ == "__main__":
    render(35.0, f"{OUT_DIR}/proto_peaks_gameangle.png")
    render(8.0, f"{OUT_DIR}/proto_peaks_centered.png", pitch_deg=2.0)
