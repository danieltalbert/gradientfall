#!/usr/bin/env python3
"""Gradient Peaks Python twin — 1:1 math preview of src/world/gradient_peaks.gd.

Iterate mountain design HERE first (renders in ~2 s), look at the PNGs, then
port the changed constants back to gradient_peaks.gd. Uses pyfastnoiselite —
the SAME FastNoiseLite library Godot ships — so geometry and vertex-color
output is the real thing; only lighting is approximated (lambert + fill +
exp fog vs Godot's SDFGI/TAA pipeline).

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
SUMMITS_MAIN = [
    (-1150.0, 286.0, 170.0),
    (-880.0, 306.0, 170.0),
    (-620.0, 352.0, 185.0),
    (-350.0, 292.0, 145.0),
    (-140.0, 334.0, 150.0),
    (80.0, 402.0, 215.0),   # the monarch
    (290.0, 318.0, 140.0),
    (560.0, 364.0, 195.0),
    (880.0, 302.0, 160.0),
    (1150.0, 292.0, 175.0),
]
SUMMITS_FAR = [
    (-1550.0, 640.0, 320.0),
    (-1050.0, 640.0, 320.0),
    (-580.0, 692.0, 300.0),
    (-160.0, 655.0, 280.0),
    (320.0, 760.0, 330.0),
    (820.0, 700.0, 300.0),
    (1300.0, 620.0, 320.0),
    (1750.0, 600.0, 330.0),
]
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
         base_frac=0.60, step=6.0, haze=0.13, snow_frac=0.70, curve=220.0),
    dict(name="far", zc=-1060.0, depth=460.0, xh=2000.0, summits=SUMMITS_FAR,
         base_frac=0.62, step=10.0, haze=0.52, snow_frac=0.44, curve=340.0),
]
BASE_Y = -12.0


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def crest_profile(x, summits, base_frac, crest_noise):
    """Connected ridgeline: smooth-max of summit gaussians over an undulating
    base ridge — one massif, not separate cones."""
    hmax = max(s[1] for s in summits)
    base = hmax * base_frac * (0.82 + 0.18 * crest_noise)
    acc = np.full_like(x, 1e-9)
    k = 9.0  # smooth-max sharpness
    for sx, sh, sw in summits:
        g = sh * np.exp(-((x - sx) / sw) ** 2)
        acc = acc + np.exp((g - hmax) / hmax * k)
    smax = hmax + np.log(acc) * hmax / k
    return np.maximum(base, smax)


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
    crest = crest_profile(xx, rank["summits"], rank["base_frac"], cn)

    hgt = crest * env * (0.50 + 0.60 * r)

    # Couloir carve: ridged channels stretched down-face (z squashed) —
    # the drainage that makes a face read as mountain, not lump.
    g = grid_noise_warped(N_GULLY, xx + wx * 0.4, z_arc * 0.35)
    g = (g + 1.0) * 0.5
    couloir = (1.0 - g) ** 2.2
    hgt -= couloir * 34.0 * env

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
SCREE = np.array([0.398, 0.362, 0.312])
TURF_SAGE = np.array([0.352, 0.408, 0.262])   # muted — no lime allowed
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
    col = col * (1.0 - turf_m[..., None]) + TURF_SAGE[None, None, :] * turf_m[..., None]
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
        sage = TURF_SAGE * 0.96
        col = col * (1.0 - alpine[..., None] * 0.72) + sage[None, None, :] * (alpine[..., None] * 0.72)
        scree_band = smoothstep(190.0, 240.0, -zz)
        col = col * (1.0 - scree_band[..., None] * 0.45) + SCREE[None, None, :] * (scree_band[..., None] * 0.45)
        col *= (1.0 - alpine[..., None] * 0.10)  # calm the grazing-light pop
    # PROTO-ONLY: in game the near field is covered by 400k sage grass
    # blades; tint the bare terrain toward blade color so this render
    # matches what the camera actually sees. Do NOT port this line.
    col *= np.array([0.80, 0.84, 0.82])[None, None, :]
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


# --------------------------------------------------------------- rasterize
def render(view_yaw_deg, out_path, pitch_deg=-6.0):
    print(f"render {out_path} yaw={view_yaw_deg}")
    meshes = []

    for rank in RANKS:
        xs = np.arange(-rank["xh"], rank["xh"] + rank["step"], rank["step"])
        zs = np.arange(rank["zc"] - rank["depth"] * 0.55,
                       rank["zc"] + rank["depth"] * 0.55 + rank["step"], rank["step"])
        hgt, masks = rank_height_and_masks(rank, xs, zs)
        nrm = normals_from_grid(hgt, rank["step"])
        col, snow = rank_colors(rank, xs, zs, hgt, masks, nrm)
        meshes.append(grid_to_tris(xs, zs, hgt, col, snow))

    ms = 4.0
    xs = np.arange(-240.0, 240.0 + ms, ms)
    zs = np.arange(-240.0, 240.0 + ms, ms)
    mh = meadow_height(xs, zs)
    mn = normals_from_grid(mh, ms)
    mc = meadow_colors(xs, zs, mh, mn, fixed=True)
    meshes.append(grid_to_tris(xs, zs, mh, mc))

    # camera at spawn, matching the screenshot rig (approx: eye pulled back).
    spawn = np.array([-58.0, 0.0, -62.0])
    g = meadow_height(np.array([spawn[0]]), np.array([spawn[2]]))[0, 0]
    yaw = math.radians(view_yaw_deg)
    pitch = math.radians(pitch_deg)
    fwd = np.array([-math.sin(yaw), 0.0, -math.cos(yaw)])
    fwd = fwd * math.cos(pitch) + np.array([0, 1, 0]) * math.sin(pitch)
    eye = np.array([spawn[0], g + 1.5, spawn[2]]) - fwd * 4.5 + np.array([0, 0.6, 0])

    up = np.array([0.0, 1.0, 0.0])
    zc = -fwd
    xc = np.cross(up, zc); xc /= np.linalg.norm(xc)
    yc = np.cross(zc, xc)
    Rm = np.stack([xc, yc, zc])

    fl = (H / 2) / math.tan(math.radians(70.0 / 2))

    img = Image.new("RGB", (W, H))
    # sky gradient + sun glow
    sky = np.zeros((H, W, 3))
    tv = np.linspace(0, 1, H)[:, None]
    grade = SKY_HOR[None, None, :] + (SKY_TOP - SKY_HOR)[None, None, :] * ((1 - tv) ** 1.6)[..., None]
    sky[:] = grade
    img.paste(Image.fromarray((np.clip(sky, 0, 1) ** (1 / 2.2) * 255).astype(np.uint8)))
    dr = ImageDraw.Draw(img)

    allV = []; allC = []; allS = []; allT = []; off = 0
    for V, C, S, T in meshes:
        allV.append(V); allC.append(C); allS.append(S); allT.append(T + off)
        off += len(V)
    V = np.concatenate(allV); C = np.concatenate(allC)
    S = np.concatenate(allS); T = np.concatenate(allT)

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
