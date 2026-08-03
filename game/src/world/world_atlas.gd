class_name WorldAtlas
extends RefCounted
## The continent of Aligned, as data — the single source of truth for *where
## everything is*.
##
## This file is the executable half of `docs/WORLD_MAP.md`. That document
## explains and justifies these numbers; this one is what the game reads. The
## world map screen, the minimap, the swim rule, and every future terrain
## stamper all pull from here, so they cannot drift apart. If this file and the
## document ever disagree, **the document is right and this file is the bug.**
##
## Nothing here touches the scene tree — it is pure data plus the coordinate
## maths, so it is safe to call from anywhere, including tools and tests.
##
## ## The two coordinate grids
##
## * **Atlas km** — kilometres on a 0-100 square. `x` east, `y` north. Whole-
##   continent scale; what the map screen draws.
## * **Region-local metres** — Godot convention: `+x` east, **`-z` north**,
##   `+y` up. Each region's local origin sits on its atlas core centre.
##
## The `-z` flip is the thing that will trip somebody up: Godot's forward is
## `-Z`, and the whole codebase already calls that north (see
## `gradient_peaks.gd`). `local_to_km()` / `km_to_local()` below are the only
## place that conversion should ever be written.


## Sea level in world Y. Not a tidy round number by accident — it is derived so
## that every altitude already baked into the terrain code becomes a true
## elevation without changing a line: the millpond lands 9.5 m above the sea,
## the meadow's north seam 38 m, the built massif's ceiling 534 m, and
## WORLDBOOK's 900 m Summit still sits far to the north and far higher.
const SEA_LEVEL_Y: float = -14.0

## The continent's bounding square, in km. Atlas coordinates run 0..100 on both
## axes; the landmass occupies rather less (see COASTLINE_KM).
const WORLD_SPAN_KM: float = 100.0

## Metres per kilometre — spelled out because the conversion appears in enough
## places that a bare 1000.0 stops reading as a unit change.
const M_PER_KM: float = 1000.0


# ---------------------------------------------------------------------------
# Regions
# ---------------------------------------------------------------------------

## The ten regions, keyed by the canonical region id used across all content
## JSON (CLAUDE.md conventions). `core_km` is the authored-density centre and
## the origin of that region's local metre grid; `core_size_km` is the diameter
## of the dense area, not of the region's influence — wilds blend outward from
## there. `tier` is the soft difficulty gate, `chapter` the campaign beat.
##
## `heart_m` is the nest rule made explicit: the size of the hand-built core
## that already exists and must never be moved. 0.0 means nothing is built yet.
const REGIONS: Dictionary = {
	&"datasedge_meadows": {
		"name": "Datasedge Meadows", "core_km": Vector2(20.0, 38.0),
		"core_size_km": 3.0, "tier": 1, "biome": "grassland",
		"chapter": "Prologue, Ch.2", "heart_m": 480.0,
	},
	&"gradient_peaks": {
		"name": "Gradient Peaks", "core_km": Vector2(26.0, 66.0),
		"core_size_km": 28.0, "tier": 3, "biome": "mountains",
		"chapter": "Ch.7", "heart_m": 0.0,
	},
	&"frozen_cache": {
		"name": "The Frozen Cache", "core_km": Vector2(30.0, 90.0),
		"core_size_km": 4.0, "tier": 4, "biome": "tundra",
		"chapter": "Ch.4", "heart_m": 0.0,
	},
	&"latent_forest": {
		"name": "Latent Forest", "core_km": Vector2(45.0, 47.0),
		"core_size_km": 5.0, "tier": 2, "biome": "deep woods",
		"chapter": "Ch.3", "heart_m": 0.0,
	},
	&"overfit_swamp": {
		"name": "Overfit Swamp", "core_km": Vector2(49.0, 23.0),
		"core_size_km": 4.0, "tier": 3, "biome": "bog",
		"chapter": "Ch.3", "heart_m": 0.0,
	},
	&"tensor_desert": {
		"name": "Tensor Desert", "core_km": Vector2(66.0, 58.0),
		"core_size_km": 6.0, "tier": 4, "biome": "dunes",
		"chapter": "Ch.3, Ch.5", "heart_m": 0.0,
	},
	&"backprop_foundry": {
		"name": "Backprop Foundry", "core_km": Vector2(82.0, 83.0),
		"core_size_km": 4.0, "tier": 5, "biome": "volcano",
		"chapter": "Ch.5", "heart_m": 0.0,
	},
	&"convolution_coast": {
		"name": "Convolution Coast", "core_km": Vector2(8.0, 46.0),
		"core_size_km": 4.0, "tier": 2, "biome": "ocean, shore, islands",
		"chapter": "Ch.6", "heart_m": 0.0,
	},
	&"parameter_city": {
		"name": "Parameter City", "core_km": Vector2(29.0, 18.0),
		"core_size_km": 4.0, "tier": 3, "biome": "capital, downs, river",
		"chapter": "Ch.2, Ch.8", "heart_m": 0.0,
	},
	&"corpus_citadel": {
		"name": "Corpus Citadel", "core_km": Vector2(87.0, 50.0),
		"core_size_km": 4.0, "tier": 5, "biome": "the Grand Library",
		"chapter": "Ch.9", "heart_m": 0.0,
	},
}


# ---------------------------------------------------------------------------
# Coastline
# ---------------------------------------------------------------------------

## The landmass outline, clockwise from the southwest, in atlas km.
##
## Re-authored 2026-08-03. The outline on the original map artifact did not
## agree with its own coordinates — fitting its axis labels back to kilometres
## put the west coast near x=18, which would have left Strideport (a *harbour*
## town, core x=8) ten kilometres out to open sea. These vertices are checked
## against every region centre: see `docs/WORLD_MAP.md` §2.3.
const COASTLINE_KM: Array[Vector2] = [
	# West coast, south to north
	Vector2(16.0, 4.0), Vector2(13.0, 12.0), Vector2(11.0, 20.0),
	Vector2(10.0, 28.0), Vector2(9.6, 36.0), Vector2(9.2, 44.0),
	Vector2(10.5, 52.0), Vector2(12.0, 60.0), Vector2(15.0, 68.0),
	Vector2(19.0, 76.0), Vector2(24.0, 84.0), Vector2(30.0, 92.0),
	# North coast, west to east
	Vector2(40.0, 94.0), Vector2(52.0, 95.0), Vector2(64.0, 93.0),
	Vector2(74.0, 90.0), Vector2(82.0, 88.0), Vector2(89.0, 84.0),
	# East coast, north to south
	Vector2(93.0, 76.0), Vector2(95.0, 66.0), Vector2(95.5, 56.0),
	Vector2(94.0, 46.0), Vector2(91.0, 36.0), Vector2(87.0, 27.0),
	Vector2(81.0, 19.0), Vector2(73.0, 12.0),
	# South coast, east to west
	Vector2(62.0, 7.0), Vector2(50.0, 4.0), Vector2(38.0, 3.0),
	Vector2(28.0, 3.0), Vector2(21.0, 3.0),
]


# ---------------------------------------------------------------------------
# Waters and roads
# ---------------------------------------------------------------------------

## The six named waterways, as polylines in atlas km. Each is named for the idea
## its region teaches — the map does the teaching before any dialogue does.
## `reaches_sea` false is a design fact, not an omission: the Slow spreads into
## the bog and repeats itself, and the Vanishing dies in the sand.
const RIVERS: Array = [
	{"id": &"the_descent", "name": "The Descent", "reaches_sea": true,
		"note": "Water takes the steepest path down. The continent's main river.",
		"points": [Vector2(26.0, 62.0), Vector2(24.6, 55.0), Vector2(23.4, 47.0),
			Vector2(21.6, 41.0), Vector2(20.5, 39.1), Vector2(19.7, 37.9),
			Vector2(16.0, 36.6), Vector2(12.4, 37.4), Vector2(9.2, 44.0)]},
	{"id": &"the_ledger", "name": "The Ledger", "reaches_sea": true,
		"note": "The capital runs on weights and measures; its river keeps the accounts.",
		"points": [Vector2(34.0, 26.0), Vector2(32.0, 22.0), Vector2(31.0, 18.0),
			Vector2(27.0, 18.0), Vector2(22.0, 16.6), Vector2(17.0, 15.0),
			Vector2(12.5, 14.0)]},
	{"id": &"the_slow", "name": "The Slow", "reaches_sea": false,
		"note": "It memorised one bend and made a hundred of it. The oxbows are identical.",
		"points": [Vector2(47.0, 38.0), Vector2(47.8, 33.0), Vector2(48.4, 28.0),
			Vector2(49.0, 24.6), Vector2(49.2, 22.4)]},
	{"id": &"the_vanishing", "name": "The Vanishing", "reaches_sea": false,
		"note": "It weakens with every kilometre from its source and arrives as nothing. The Rune Rows line the dry channel it leaves.",
		"points": [Vector2(38.0, 60.0), Vector2(45.0, 59.4), Vector2(52.0, 59.0),
			Vector2(58.0, 58.8), Vector2(61.0, 58.6)]},
	{"id": &"the_emberflow", "name": "The Emberflow", "reaches_sea": false,
		"note": "Not water. Error-flame running BACKWARD, uphill from the failure to every furnace that contributed (WORLDBOOK §7).",
		"points": [Vector2(80.0, 80.0), Vector2(81.2, 82.0), Vector2(82.2, 83.6),
			Vector2(83.0, 85.0)]},
	# `frozen` is a third state, not a flavour note. "Reaches the sea" and "dies
	# inland" are the only two options for liquid water, and the Stillwater is
	# neither: it runs all the way to the northern shore and is stopped solid
	# the entire way. Without this key an audit quite reasonably calls it a
	# river that failed to die inland.
	{"id": &"the_stillwater", "name": "The Stillwater", "reaches_sea": false,
		"frozen": true,
		"note": "A river stopped mid-flow, a standing wave caught in the act.",
		"points": [Vector2(28.0, 88.0), Vector2(30.0, 89.6), Vector2(31.6, 91.0),
			Vector2(33.0, 92.0)]},
]

## Roads. A hundred kilometres of wilderness needs lines for the eye to follow,
## and the wilds need edges to be wild against.
const ROADS: Array = [
	{"id": &"great_east_road", "name": "The Great East Road",
		"note": "The spine, 80 km. You can see your ending down it from almost anywhere.",
		"points": [Vector2(9.6, 46.3), Vector2(14.0, 42.0), Vector2(20.0, 37.97),
			Vector2(28.0, 39.0), Vector2(36.0, 43.0), Vector2(45.0, 47.0),
			Vector2(55.0, 51.0), Vector2(66.0, 58.0), Vector2(74.0, 62.0),
			Vector2(81.0, 55.0), Vector2(86.8, 50.0)]},
	{"id": &"capital_way", "name": "The Capital Way",
		"note": "21 km, about 48 minutes on foot. Chapter 2's road.",
		"points": [Vector2(20.0, 37.97), Vector2(21.8, 33.0), Vector2(24.0, 28.0),
			Vector2(26.4, 23.0), Vector2(29.0, 18.6)]},
	{"id": &"cold_stair", "name": "The Cold Stair",
		"note": "Cut steps, not a road. Closes in storms.",
		"points": [Vector2(24.2, 62.8), Vector2(25.9, 67.4), Vector2(27.0, 74.0),
			Vector2(28.4, 82.0), Vector2(29.4, 89.3)]},
	{"id": &"cinder_track", "name": "The Cinder Track",
		"note": "Slag-ballasted. Warm underfoot for the last 3 km.",
		"points": [Vector2(74.0, 62.0), Vector2(77.0, 70.0), Vector2(79.6, 77.0),
			Vector2(81.6, 82.4)]},
	{"id": &"bog_causeway", "name": "The Bog Causeway",
		"note": "Planks on stilts. Identical planks. You will count them.",
		"points": [Vector2(29.0, 18.6), Vector2(35.0, 19.8), Vector2(42.0, 21.4),
			Vector2(48.4, 22.6)]},
	{"id": &"old_boundary_line", "name": "The Old Boundary Line",
		"note": "A road that is no longer a road. Older than Bootstrap, runs from nothing to nothing; readable as a shallow ridge in the grass and a row of stones. Bit already says nobody can see the line anymore — this is the line.",
		"points": [Vector2(20.28, 38.30), Vector2(20.058, 38.074),
			Vector2(19.86, 37.87), Vector2(19.62, 37.62)]},
]


# ---------------------------------------------------------------------------
# The Deep — swim safety
# ---------------------------------------------------------------------------

## Open water outside these zones is **the Deep**: it drains hearts slowly, the
## screen edge goes cold, and Bit (canonically afraid of deep water) objects.
## It is a soft gate made of danger, not a wall — which is how the GDD's
## "no hard gates" pillar survives having an ocean in it.
##
## Circles in atlas km. Adding safe water later is one entry here, never a code
## change — that is the entire point of keeping it as data.
const SAFE_WATER: Array = [
	{"id": &"coast_shelf", "name": "the Convolution shelf",
		"centre": Vector2(8.0, 46.0), "radius_km": 4.5},
	{"id": &"isle_longstride", "name": "Longstride",
		"centre": Vector2(5.5, 48.0), "radius_km": 1.2},
	{"id": &"isle_halfstride", "name": "Halfstride",
		"centre": Vector2(6.8, 44.5), "radius_km": 0.9},
	{"id": &"isle_padding", "name": "The Padding",
		"centre": Vector2(7.4, 41.2), "radius_km": 0.7},
	{"id": &"kernel_reef", "name": "the Kernel Reef",
		"centre": Vector2(6.2, 45.4), "radius_km": 1.0},
	{"id": &"window_flats", "name": "Window Flats",
		"centre": Vector2(9.3, 46.0), "radius_km": 3.4},
	{"id": &"old_millpond", "name": "the Old Millpond",
		"centre": Vector2(20.095, 37.990), "radius_km": 0.03},
	{"id": &"city_canal", "name": "the Ledger in the capital",
		"centre": Vector2(29.0, 18.0), "radius_km": 2.2},
]

## Hearts drained per second while in the Deep. Tuned so a full-health Kern can
## make a genuine push for something he can SEE — roughly 40 seconds of open
## water — and then must turn back or lose the gamble. Danger, not a wall.
const DEEP_DRAIN_PER_SEC: float = 0.075

## Grace before the drain begins, in seconds. Crossing a river mouth or
## overshooting a jump must never cost hearts; only committing to open sea does.
const DEEP_GRACE_SEC: float = 4.0


# ---------------------------------------------------------------------------
# Sites
# ---------------------------------------------------------------------------

## Every named place in `WORLDBOOK.md`, positioned. See `docs/WORLD_MAP.md` §6
## for the reasoning behind each placement and §7 for which of them are canon
## versus authored.
##
## Fields: `id` · `name` · `region` · `kind` · `km` (atlas) · `elev` (m above
## sea level) · `built` (true = standing in the game right now; its position is
## read out of the terrain code and must not be moved — the nest rule) ·
## `secret` (optional; true means map-drawing code must skip it).
##
## `kind` is one of: town · dungeon · shrine · world_boss · poi · landmark ·
## district · pass · island · ruin · zone · gate · water · hamlet.
const SITES: Array = [
	# --- Datasedge Meadows -------------------------------------------------
	{"id": &"bootstrap", "name": "Bootstrap", "region": &"datasedge_meadows",
		"kind": &"town", "km": Vector2(20.000, 37.970), "elev": 24.0, "built": true},
	{"id": &"the_mill", "name": "The Mill", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(20.078, 37.996), "elev": 12.0, "built": true},
	{"id": &"old_millpond", "name": "The Old Millpond", "region": &"datasedge_meadows",
		"kind": &"water", "km": Vector2(20.095, 37.990), "elev": 9.5, "built": true},
	{"id": &"seed_vault_ruins", "name": "The Seed Vault ruins", "region": &"datasedge_meadows",
		"kind": &"ruin", "km": Vector2(19.928, 38.070), "elev": 26.0, "built": true},
	{"id": &"whispering_well", "name": "The Whispering Well", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(20.046, 37.976), "elev": 22.0, "built": true},
	{"id": &"old_boundary_stones", "name": "The Old Boundary Stones", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(20.058, 38.074), "elev": 27.0, "built": true},
	{"id": &"hivewise_apiary", "name": "Hivewise Apiary", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(20.070, 38.014), "elev": 21.0, "built": true},
	{"id": &"perceptron_vault", "name": "The Perceptron Vault", "region": &"datasedge_meadows",
		"kind": &"dungeon", "km": Vector2(20.064, 37.872), "elev": 14.3, "built": true},
	{"id": &"iris_flats", "name": "The Iris flats", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(19.958, 38.082), "elev": 20.0, "built": true},
	{"id": &"shrine_first_light", "name": "Shrine of First Light", "region": &"datasedge_meadows",
		"kind": &"shrine", "km": Vector2(20.152, 37.942), "elev": 20.0, "built": false},
	{"id": &"sunrow_fields", "name": "Sunrow Fields", "region": &"datasedge_meadows",
		"kind": &"hamlet", "km": Vector2(19.380, 37.660), "elev": 22.0, "built": false},
	{"id": &"wheelwrights_cross", "name": "Wheelwright's Cross", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(20.410, 38.180), "elev": 31.0, "built": false},
	{"id": &"the_thresher", "name": "The Thresher's cut lines", "region": &"datasedge_meadows",
		"kind": &"world_boss", "km": Vector2(19.020, 38.420), "elev": 44.0, "built": false},
	{"id": &"first_ridge_gate", "name": "The First Ridge gate-valley", "region": &"datasedge_meadows",
		"kind": &"pass", "km": Vector2(20.000, 38.300), "elev": 172.0, "built": true},

	# --- Gradient Peaks ----------------------------------------------------
	{"id": &"descents_rest", "name": "Descent's Rest", "region": &"gradient_peaks",
		"kind": &"town", "km": Vector2(24.2, 62.8), "elev": 430.0, "built": false},
	{"id": &"momentum_mines", "name": "The Momentum Mines", "region": &"gradient_peaks",
		"kind": &"dungeon", "km": Vector2(27.6, 65.1), "elev": 520.0, "built": false},
	{"id": &"the_saddle", "name": "The Saddle", "region": &"gradient_peaks",
		"kind": &"pass", "km": Vector2(25.9, 67.4), "elev": 690.0, "built": false},
	{"id": &"overshoot_ledge", "name": "Overshoot Ledge", "region": &"gradient_peaks",
		"kind": &"poi", "km": Vector2(28.4, 68.0), "elev": 745.0, "built": false},
	{"id": &"the_summit", "name": "The Summit", "region": &"gradient_peaks",
		"kind": &"landmark", "km": Vector2(26.5, 71.2), "elev": 900.0, "built": false},
	{"id": &"shrine_summit", "name": "Shrine of the Summit", "region": &"gradient_peaks",
		"kind": &"shrine", "km": Vector2(26.6, 70.6), "elev": 858.0, "built": false},
	{"id": &"gradient_wyrm", "name": "The Gradient Wyrm's plateau", "region": &"gradient_peaks",
		"kind": &"world_boss", "km": Vector2(22.8, 69.3), "elev": 604.0, "built": false},
	{"id": &"avalanche_choir", "name": "The Avalanche Choir corrie", "region": &"gradient_peaks",
		"kind": &"world_boss", "km": Vector2(29.7, 70.1), "elev": 712.0, "built": false},

	# --- The Frozen Cache --------------------------------------------------
	{"id": &"coldstore", "name": "Coldstore", "region": &"frozen_cache",
		"kind": &"town", "km": Vector2(29.4, 89.3), "elev": 372.0, "built": false},
	{"id": &"cache_depths", "name": "The Cache Depths", "region": &"frozen_cache",
		"kind": &"dungeon", "km": Vector2(31.1, 90.8), "elev": 340.0, "built": false},
	{"id": &"aurora_fields", "name": "Aurora Fields", "region": &"frozen_cache",
		"kind": &"poi", "km": Vector2(32.6, 92.2), "elev": 410.0, "built": false},
	{"id": &"ninety_year_post", "name": "The Ninety-Year Post Office", "region": &"frozen_cache",
		"kind": &"poi", "km": Vector2(28.9, 88.6), "elev": 366.0, "built": false},
	{"id": &"preservation_vaults", "name": "Preservation Vaults", "region": &"frozen_cache",
		"kind": &"poi", "km": Vector2(30.7, 88.1), "elev": 388.0, "built": false},
	{"id": &"shrine_second_voice", "name": "Shrine of the Second Voice", "region": &"frozen_cache",
		"kind": &"shrine", "km": Vector2(31.8, 91.6), "elev": 402.0, "built": false},
	# The Leviathan swims through the SKY, so it is the one boss whose position
	# is an air corridor rather than an arena. It is pinned over the Aurora
	# Fields because that is where the aurora it swims in actually is; it had
	# drifted out over the northern sea, where there is nothing to look at it.
	{"id": &"aurora_leviathan", "name": "Aurora Leviathan's sky-lane", "region": &"frozen_cache",
		"kind": &"world_boss", "km": Vector2(32.4, 92.0), "elev": 460.0, "built": false},

	# --- Latent Forest -----------------------------------------------------
	{"id": &"embedding_hollow", "name": "Embedding Hollow", "region": &"latent_forest",
		"kind": &"town", "km": Vector2(44.3, 46.4), "elev": 108.0, "built": false},
	{"id": &"autoencoder_grove", "name": "The Autoencoder Grove", "region": &"latent_forest",
		"kind": &"dungeon", "km": Vector2(46.2, 48.1), "elev": 96.0, "built": false},
	{"id": &"thin_place_north", "name": "The Thin Places — north", "region": &"latent_forest",
		"kind": &"poi", "km": Vector2(43.1, 48.6), "elev": 112.0, "built": false},
	{"id": &"thin_place_east", "name": "The Thin Places — east", "region": &"latent_forest",
		"kind": &"poi", "km": Vector2(46.9, 45.2), "elev": 112.0, "built": false},
	{"id": &"thin_place_west", "name": "The Thin Places — west", "region": &"latent_forest",
		"kind": &"poi", "km": Vector2(44.8, 49.4), "elev": 112.0, "built": false},
	{"id": &"canopy_post", "name": "Canopy Post", "region": &"latent_forest",
		"kind": &"poi", "km": Vector2(45.6, 45.1), "elev": 134.0, "built": false},
	{"id": &"mosslight_vale", "name": "Mosslight Vale", "region": &"latent_forest",
		"kind": &"poi", "km": Vector2(43.6, 44.8), "elev": 84.0, "built": false},
	{"id": &"shrine_deep_roots", "name": "Shrine of Deep Roots", "region": &"latent_forest",
		"kind": &"shrine", "km": Vector2(44.9, 47.9), "elev": 92.0, "built": false},
	{"id": &"feature_stag", "name": "The Feature Stag's range", "region": &"latent_forest",
		"kind": &"world_boss", "km": Vector2(46.8, 46.7), "elev": 120.0, "built": false},

	# --- Overfit Swamp -----------------------------------------------------
	{"id": &"mirrormoor", "name": "Mirrormoor", "region": &"overfit_swamp",
		"kind": &"town", "km": Vector2(48.4, 22.6), "elev": 12.0, "built": false},
	{"id": &"memorization_mire", "name": "The Memorization Mire", "region": &"overfit_swamp",
		"kind": &"dungeon", "km": Vector2(50.1, 23.9), "elev": 9.0, "built": false},
	{"id": &"same_ten_clearings", "name": "The Same Ten Clearings", "region": &"overfit_swamp",
		"kind": &"poi", "km": Vector2(49.0, 23.0), "elev": 12.0, "built": false},
	{"id": &"grandma_pyes", "name": "Grandma Pye's cottage", "region": &"overfit_swamp",
		"kind": &"poi", "km": Vector2(47.9, 24.1), "elev": 15.0, "built": false},
	{"id": &"one_different_tree", "name": "The One Different Tree", "region": &"overfit_swamp",
		"kind": &"poi", "km": Vector2(50.8, 21.7), "elev": 11.0, "built": false},
	{"id": &"unsupervised_hydra", "name": "The Unsupervised Hydra's centroid pools",
		"region": &"overfit_swamp", "kind": &"world_boss", "km": Vector2(49.6, 21.9),
		"elev": 8.0, "built": false},
	{"id": &"swamp_halluc_zone", "name": "Hallucination Zone", "region": &"overfit_swamp",
		"kind": &"zone", "km": Vector2(49.4, 23.6), "elev": 12.0, "built": false},

	# --- Tensor Desert -----------------------------------------------------
	{"id": &"axis_bazaar", "name": "Axis Bazaar", "region": &"tensor_desert",
		"kind": &"town", "km": Vector2(65.2, 57.4), "elev": 96.0, "built": false},
	{"id": &"matrix_necropolis", "name": "The Matrix Necropolis", "region": &"tensor_desert",
		"kind": &"dungeon", "km": Vector2(67.4, 59.2), "elev": 78.0, "built": false},
	{"id": &"sand_sunk_library", "name": "The Sand-Sunk Library", "region": &"tensor_desert",
		"kind": &"poi", "km": Vector2(64.1, 59.6), "elev": 62.0, "built": false},
	{"id": &"rune_rows", "name": "Rune Rows", "region": &"tensor_desert",
		"kind": &"poi", "km": Vector2(63.0, 58.4), "elev": 90.0, "built": false},
	{"id": &"idle_colossus", "name": "The Idle Colossus's basin", "region": &"tensor_desert",
		"kind": &"world_boss", "km": Vector2(68.1, 56.6), "elev": 28.0, "built": false},
	{"id": &"shrine_broken_scale", "name": "Shrine of the Broken Scale", "region": &"tensor_desert",
		"kind": &"shrine", "km": Vector2(66.8, 58.8), "elev": 84.0, "built": false},
	{"id": &"desert_halluc_zone", "name": "Hallucination Zone", "region": &"tensor_desert",
		"kind": &"zone", "km": Vector2(64.6, 58.9), "elev": 80.0, "built": false},
	# Ashfall Turn exists because the audit refused to let the Cinder Track
	# branch off the Great East Road at an anonymous point. It is the last
	# waystation before the volcano road, and the ash starts here.
	{"id": &"ashfall_turn", "name": "Ashfall Turn", "region": &"tensor_desert",
		"kind": &"poi", "km": Vector2(74.0, 62.0), "elev": 140.0, "built": false},

	# --- Backprop Foundry --------------------------------------------------
	{"id": &"emberworks", "name": "Emberworks", "region": &"backprop_foundry",
		"kind": &"town", "km": Vector2(81.6, 82.4), "elev": 386.0, "built": false},
	{"id": &"chain_rule_works", "name": "The Chain Rule Works", "region": &"backprop_foundry",
		"kind": &"dungeon", "km": Vector2(83.1, 84.2), "elev": 302.0, "built": false},
	{"id": &"slagfields", "name": "The Slagfields", "region": &"backprop_foundry",
		"kind": &"poi", "km": Vector2(80.2, 80.9), "elev": 244.0, "built": false},
	{"id": &"hundred_failures", "name": "The Hundred Failures Gallery", "region": &"backprop_foundry",
		"kind": &"poi", "km": Vector2(81.9, 82.9), "elev": 392.0, "built": false},
	{"id": &"shrine_embers", "name": "Shrine of Embers", "region": &"backprop_foundry",
		"kind": &"shrine", "km": Vector2(82.8, 83.6), "elev": 348.0, "built": false},
	{"id": &"slagheart_colossus", "name": "Slagheart Colossus arena", "region": &"backprop_foundry",
		"kind": &"world_boss", "km": Vector2(80.6, 81.4), "elev": 250.0, "built": false},

	# --- Convolution Coast -------------------------------------------------
	# Strideport sits ON the shoreline (which runs through x ~9.53 at this
	# latitude), not on its region's core centre. Convolution Coast's core is
	# deliberately 1.5 km offshore because the region IS the water — but a
	# harbour town has to have a harbour, and that means land under it.
	{"id": &"strideport", "name": "Strideport", "region": &"convolution_coast",
		"kind": &"town", "km": Vector2(9.6, 46.3), "elev": 8.0, "built": false},
	{"id": &"kernel_reef", "name": "The Kernel Reef", "region": &"convolution_coast",
		"kind": &"dungeon", "km": Vector2(6.2, 45.4), "elev": -18.0, "built": false},
	{"id": &"the_unsinkable", "name": "The Unsinkable", "region": &"convolution_coast",
		"kind": &"world_boss", "km": Vector2(5.9, 47.8), "elev": 0.0, "built": false},
	# Just seaward of the shoreline: the tide-walk zone is meant to be water most
	# of the time and floor for a window of it.
	{"id": &"window_flats", "name": "Window Flats", "region": &"convolution_coast",
		"kind": &"poi", "km": Vector2(9.3, 46.0), "elev": 0.0, "built": false},
	# A headland, so it must be land — the shoreline runs through x ~10.0 here.
	{"id": &"lighthouse_point", "name": "Lighthouse Point", "region": &"convolution_coast",
		"kind": &"landmark", "km": Vector2(10.1, 48.9), "elev": 46.0, "built": false},
	{"id": &"shrine_tide", "name": "Shrine of the Tide", "region": &"convolution_coast",
		"kind": &"shrine", "km": Vector2(7.1, 44.3), "elev": 22.0, "built": false},
	{"id": &"isle_longstride", "name": "Longstride", "region": &"convolution_coast",
		"kind": &"island", "km": Vector2(5.5, 48.0), "elev": 14.0, "built": false},
	{"id": &"isle_halfstride", "name": "Halfstride", "region": &"convolution_coast",
		"kind": &"island", "km": Vector2(6.8, 44.5), "elev": 9.0, "built": false},
	{"id": &"isle_padding", "name": "The Padding", "region": &"convolution_coast",
		"kind": &"island", "km": Vector2(7.4, 41.2), "elev": 6.0, "built": false},

	# --- Parameter City ----------------------------------------------------
	{"id": &"castle_normhold", "name": "Castle Normhold", "region": &"parameter_city",
		"kind": &"landmark", "km": Vector2(29.0, 18.6), "elev": 96.0, "built": false},
	{"id": &"weights_and_measures", "name": "Weights & Measures", "region": &"parameter_city",
		"kind": &"district", "km": Vector2(28.5, 18.1), "elev": 74.0, "built": false},
	{"id": &"regularizers_court", "name": "The Regularizer's Court", "region": &"parameter_city",
		"kind": &"district", "km": Vector2(29.4, 18.2), "elev": 78.0, "built": false},
	{"id": &"feature_quarter", "name": "Feature Quarter", "region": &"parameter_city",
		"kind": &"district", "km": Vector2(28.7, 17.5), "elev": 70.0, "built": false},
	{"id": &"dropout_district", "name": "The Dropout District", "region": &"parameter_city",
		"kind": &"district", "km": Vector2(29.7, 17.4), "elev": 66.0, "built": false},
	{"id": &"homestead_terraces", "name": "Homestead Terraces", "region": &"parameter_city",
		"kind": &"district", "km": Vector2(30.2, 18.8), "elev": 84.0, "built": false},
	{"id": &"shrine_ledger", "name": "Shrine of the Ledger", "region": &"parameter_city",
		"kind": &"shrine", "km": Vector2(29.1, 19.1), "elev": 88.0, "built": false},
	{"id": &"undercroft", "name": "The Undercroft of Unused Parameters",
		"region": &"parameter_city", "kind": &"dungeon", "km": Vector2(29.0, 18.6),
		"elev": 40.0, "built": false},
	{"id": &"the_unregularized", "name": "The Unregularized", "region": &"parameter_city",
		"kind": &"world_boss", "km": Vector2(31.4, 16.9), "elev": 58.0, "built": false},

	# --- Corpus Citadel ----------------------------------------------------
	{"id": &"index_gate", "name": "The Index Gate", "region": &"corpus_citadel",
		"kind": &"gate", "km": Vector2(86.8, 50.0), "elev": 120.0, "built": false},
	{"id": &"stacks_gardens", "name": "The Stacks Gardens", "region": &"corpus_citadel",
		"kind": &"poi", "km": Vector2(86.1, 49.4), "elev": 96.0, "built": false},
	{"id": &"shrine_first_question", "name": "Shrine of the First Question",
		"region": &"corpus_citadel", "kind": &"shrine", "km": Vector2(86.9, 49.2),
		"elev": 112.0, "built": false},
	{"id": &"infinite_stacks", "name": "The Infinite Stacks", "region": &"corpus_citadel",
		"kind": &"dungeon", "km": Vector2(87.0, 50.2), "elev": 60.0, "built": false},
	{"id": &"citadel_spire", "name": "The Citadel spire", "region": &"corpus_citadel",
		"kind": &"landmark", "km": Vector2(87.0, 50.2), "elev": 700.0, "built": false},
]


# ---------------------------------------------------------------------------
# Hidden things
# ---------------------------------------------------------------------------

## Deliberately-hidden places. They are held apart from SITES rather than
## flagged inside it so that no map-drawing code can leak one by forgetting a
## filter — a secret that depends on every consumer remembering to check a bool
## is not a secret for long.
##
## Keeping the registry here, documented, is the compromise between iron rule 3
## (a stranger must be able to read this code) and the point of a secret: the
## code is honest, the game says nothing.
const HIDDEN: Array = [
	{"id": &"the_tenth", "name": "?", "region": &"convolution_coast",
		"kind": &"island", "km": Vector2(4.2, 9.5), "elev": 11.0,
		"note": "A tenth island, far southwest, drawn on no map. It sits deep inside the Deep, so reaching it costs real hearts and the swim back costs more. Nothing marks it. That is the reward."},
	{"id": &"boundary_line_end", "name": "?", "region": &"datasedge_meadows",
		"kind": &"poi", "km": Vector2(19.62, 37.62),
		"elev": 18.0,
		"note": "The southwest terminus of the Old Boundary Line. The road stops. There is no chest, no shrine and no enemy — only the view back up the line, which from here reads as one perfectly straight scar across the whole meadow, and is the only place it does."},
]


# ---------------------------------------------------------------------------
# Coordinate maths
# ---------------------------------------------------------------------------

## Region-local metres to atlas kilometres.
##
## The `-z` on the north axis is not a typo: Godot's forward is `-Z` and the
## terrain code already treats that as north, so travelling north (decreasing
## z) must increase the atlas's northward y.
static func local_to_km(region_id: StringName, local_x: float, local_z: float) -> Vector2:
	var core: Vector2 = core_of(region_id)
	return Vector2(core.x + local_x / M_PER_KM, core.y - local_z / M_PER_KM)


## Atlas kilometres to region-local metres, returned as (x, z).
static func km_to_local(region_id: StringName, km: Vector2) -> Vector2:
	var core: Vector2 = core_of(region_id)
	return Vector2((km.x - core.x) * M_PER_KM, (core.y - km.y) * M_PER_KM)


## A region's core centre in atlas km, or (0, 0) for an unknown id. Callers get
## a usable vector rather than a crash, because a typo'd region id in content
## should degrade to "drawn at the origin, obviously wrong" and not take the
## map screen down with it.
static func core_of(region_id: StringName) -> Vector2:
	if not REGIONS.has(region_id):
		push_warning("WorldAtlas: unknown region id '%s'." % region_id)
		return Vector2.ZERO
	return REGIONS[region_id]["core_km"]


## World Y (metres) to elevation above sea level.
static func y_to_elevation(world_y: float) -> float:
	return world_y - SEA_LEVEL_Y


## Elevation above sea level to world Y.
static func elevation_to_y(elevation_m: float) -> float:
	return elevation_m + SEA_LEVEL_Y


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

## True if this atlas point is inside a named safe-water zone. Everything else
## that is water is the Deep. Used by the swim rule; also used by the map screen
## to shade the safe shelf.
static func is_safe_water(km: Vector2) -> bool:
	for zone in SAFE_WATER:
		if km.distance_to(zone["centre"]) <= float(zone["radius_km"]):
			return true
	return false


## The safe-water zone containing a point, or an empty Dictionary. Separate from
## `is_safe_water()` so callers that want to name the water ("the Kernel Reef")
## do not pay for a second search.
static func safe_water_at(km: Vector2) -> Dictionary:
	for zone in SAFE_WATER:
		if km.distance_to(zone["centre"]) <= float(zone["radius_km"]):
			return zone
	return {}


## Every site belonging to one region, in declaration order.
static func sites_in_region(region_id: StringName) -> Array:
	var out: Array = []
	for site in SITES:
		if site["region"] == region_id:
			out.append(site)
	return out


## Every site of one kind across the whole continent — `sites_of_kind(&"shrine")`
## returns the nine Memory Shrines in canonical order.
static func sites_of_kind(kind: StringName) -> Array:
	var out: Array = []
	for site in SITES:
		if site["kind"] == kind:
			out.append(site)
	return out


## The site nearest an atlas point, with its distance in km, as
## `{"site": Dictionary, "km": float}`. Returns an empty Dictionary only if
## SITES is empty, which would mean this file had been gutted.
##
## `within_km` <= 0 means "no limit". The minimap uses a limit; the map screen
## does not.
static func nearest_site(km: Vector2, within_km: float = 0.0) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for site in SITES:
		var d: float = km.distance_to(site["km"])
		if d < best_d:
			best_d = d
			best = site
	if best.is_empty():
		return {}
	if within_km > 0.0 and best_d > within_km:
		return {}
	return {"site": best, "km": best_d}


## Which region's core a point falls closest to. Every point on the continent
## belongs to *some* region for labelling purposes, even out in the wilds
## halfway between two — that is what a region name on a minimap means.
static func region_at(km: Vector2) -> StringName:
	var best: StringName = &""
	var best_d: float = INF
	for region_id in REGIONS:
		var d: float = km.distance_to(REGIONS[region_id]["core_km"])
		if d < best_d:
			best_d = d
			best = region_id
	return best


## True if an atlas point is inside the landmass outline. Ray-casting parity
## test against COASTLINE_KM — the polygon is closed implicitly, so the last
## vertex joins back to the first.
static func is_on_land(km: Vector2) -> bool:
	var inside: bool = false
	var count: int = COASTLINE_KM.size()
	var j: int = count - 1
	for i in count:
		var a: Vector2 = COASTLINE_KM[i]
		var b: Vector2 = COASTLINE_KM[j]
		if (a.y > km.y) != (b.y > km.y):
			var x_cross: float = (b.x - a.x) * (km.y - a.y) / (b.y - a.y) + a.x
			if km.x < x_cross:
				inside = not inside
		j = i
	return inside
