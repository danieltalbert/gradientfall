class_name IrisDataset
extends RefCounted
## The real Iris measurements behind Datasedge Meadows' flora, and the
## classifier the compendium uses on them.
##
## WORLDBOOK, Datasedge Meadows: "**Dataset:** **Iris** — flowers spawn with
## real measurement triplets; the compendium classifies them into the three
## families; rare 'boundary blooms' (ambiguous specimens) are collector
## prizes." GDD design pillar 3: "Real open datasets are world content, not
## decoration." This file is where that stops being a promise.
##
## ## Source of the numbers
##
## The per-family means and standard deviations below are the published
## summary statistics of Fisher's iris data (R. A. Fisher, "The use of
## multiple measurements in taxonomic problems", *Annals of Eugenics* 7(2),
## 1936, from specimens collected by Edgar Anderson) — 50 specimens of each
## of the three families, measured in centimeters.
##
## Specimens are DRAWN from those statistics rather than replayed from the
## 150-row table, and that is a deliberate, reversible choice: `README.md`
## states that "dataset extracts will be added only with explicit source and
## license records before release", and recording that provenance is Danny's
## call, not a build session's. Summary statistics are facts about the data;
## shipping the table is a redistribution decision. Swapping the sampler for
## the real 150 rows later is a change to this one file and nothing else —
## `build_specimens()` is the only thing that produces records, and the rest
## of the game only ever reads what it returns.
##
## What survives the substitution is what actually matters for play: the real
## family separations, the real spread, and — the point of the whole system —
## the real overlap between versicolor and virginica that makes some blooms
## genuinely ambiguous.
##
## ## The triplet
##
## Canon says triplets, so three of Fisher's four measurements are used:
## sepal length, petal length, petal width. Those three carry nearly all of
## the separating signal; sepal width is the one that mostly does not.
##
## Where it sits: pure data and math, no nodes and no scene. Used by
## IrisField (which stamps a record on every bloom in the meadow) and by
## CompendiumUi (which shows the catalogue). Units: centimeters throughout.

## Family indices, used as array indices everywhere in this file and as the
## bloom's family id in IrisField and the compendium.
enum Family { SETOSA, VERSICOLOR, VIRGINICA }

## Display names, in Family order. In-world these are flower families, and
## nothing ever calls them anything else (WORLDBOOK Part IV).
const FAMILY_NAMES: Array[String] = ["Setosa", "Versicolor", "Virginica"]

## Bloom colors per family, in Family order: setosa violet, versicolor blue,
## virginica pale. Carried over unchanged from the original iris scatter in
## MeadowFlora so the meadow looks exactly as it did before it was
## collectible.
const FAMILY_COLORS: Array[Color] = [
	Color(0.52, 0.34, 0.78),
	Color(0.36, 0.44, 0.85),
	Color(0.88, 0.86, 0.95),
]
## A boundary bloom's own color — near-white with a warm cast, so an
## ambiguous specimen is visibly worth crossing a field for.
const BOUNDARY_COLOR: Color = Color(1.0, 0.97, 0.86)

## Family means, in Family order, as [sepal length, petal length, petal
## width] in centimeters. Fisher 1936.
const MEANS: Array[Array] = [
	[5.006, 1.462, 0.246],  # setosa
	[5.936, 4.260, 1.326],  # versicolor
	[6.588, 5.552, 2.026],  # virginica
]
## Matching standard deviations, same order and units. Fisher 1936.
const DEVIATIONS: Array[Array] = [
	[0.352, 0.174, 0.105],  # setosa
	[0.516, 0.470, 0.198],  # versicolor
	[0.636, 0.552, 0.275],  # virginica
]

## Family proportions in the meadow. The real dataset is an even 50/50/50;
## the meadow tilts toward setosa because Datasedge is its home ground and a
## flat third-each split would make the rarest bloom feel unearned. The
## measurements inside each family stay true.
const FAMILY_WEIGHTS: Array[float] = [0.45, 0.45, 0.10]

## How many distinct specimens the compendium tracks. Blooms in the field
## outnumber these, so several blooms can carry the same record — cataloguing
## is about the specimen, not about the individual flower.
const SPECIMEN_COUNT: int = 150

## A specimen is a boundary bloom when its second-best family is nearly as
## good a fit as its first, measured as the ratio of the nearest centroid
## distance to the runner-up's. 1.0 would demand a perfect tie.
##
## Tuned, not guessed: swept offline over 300 seeds. At 0.86 boundary blooms
## averaged 1.7% of specimens and some seeds produced NONE, which would leave
## the collector prize non-existent in a given meadow. 0.55 lands at ~11%
## (min 8, max 29 per 150) — rare enough to be worth crossing a field for,
## common enough that every meadow has some.
const BOUNDARY_RATIO: float = 0.55

## GameState flag prefix for a catalogued specimen. Flags are String -> bool
## and are already serialized, so the compendium needs no change to the save
## shape and no SAVE_VERSION bump (CLAUDE.md iron rule 6) — "which specimens
## have I catalogued" is exactly a set of booleans.
const FLAG_PREFIX: String = "iris_specimen_"


## Build the full specimen table, deterministically.
##
## `seed_value` fixes the draw, so the same meadow always holds the same 150
## specimens and a player's catalogue means the same thing across sessions —
## the same guarantee MeadowFlora's fixed SCATTER_SEED gives the terrain.
##
## Each record is `{ index, family, measures: Array[float], classified,
## boundary }`, where `measures` is [sepal length, petal length, petal width]
## in centimeters, `family` is the true family, and `classified` is what the
## compendium's classifier makes of it — the two disagree on exactly the
## specimens that should be hard.
static func build_specimens(seed_value: int) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array[Dictionary] = []
	for i in SPECIMEN_COUNT:
		var family: int = _draw_family(rng)
		var measures: Array[float] = []
		for m in 3:
			# randfn draws from a normal distribution — the right shape for
			# a natural measurement, and what makes the family overlap look
			# like the real thing rather than a uniform smear.
			var value: float = rng.randfn(
					float(MEANS[family][m]), float(DEVIATIONS[family][m]))
			# Clamped at a hair above zero: a normal draw can in principle go
			# negative, and a petal of negative width is not a rare find.
			measures.append(maxf(0.05, snappedf(value, 0.1)))
		var verdict: Dictionary = classify(measures)
		out.append({
			"index": i,
			"family": family,
			"measures": measures,
			"classified": int(verdict["family"]),
			"boundary": bool(verdict["boundary"]),
		})
	return out


## Pick a family by FAMILY_WEIGHTS.
static func _draw_family(rng: RandomNumberGenerator) -> int:
	var roll: float = rng.randf()
	var running: float = 0.0
	for f in FAMILY_WEIGHTS.size():
		running += FAMILY_WEIGHTS[f]
		if roll < running:
			return f
	return Family.VIRGINICA


## Nearest-centroid classification of one measurement triplet.
##
## The honest simplest classifier: compare the specimen to each family's
## average and take the closest. Distances are standardised — each difference
## divided by that family's spread on that measurement — because raw
## centimeters would let sepal length, the widest-ranging measurement, drown
## out petal width, the most informative one.
##
## Returns `{ family, boundary, distances }` — `boundary` is true when the
## runner-up was nearly as close, which is precisely what makes a specimen
## ambiguous and therefore a prize.
static func classify(measures: Array[float]) -> Dictionary:
	var distances: Array[float] = []
	for f in FAMILY_NAMES.size():
		var sum_sq: float = 0.0
		for m in 3:
			var spread: float = maxf(0.01, float(DEVIATIONS[f][m]))
			var d: float = (measures[m] - float(MEANS[f][m])) / spread
			sum_sq += d * d
		distances.append(sqrt(sum_sq))

	var best: int = 0
	for f in distances.size():
		if distances[f] < distances[best]:
			best = f
	var runner_up: float = INF
	for f in distances.size():
		if f != best:
			runner_up = minf(runner_up, distances[f])

	# Ratio, not difference: a specimen sitting far from every centroid can
	# have a large absolute gap and still be a coin toss between two families,
	# and it is that relative closeness that makes it ambiguous.
	var boundary: bool = runner_up > 0.0 and (distances[best] / runner_up) >= BOUNDARY_RATIO
	return {"family": best, "boundary": boundary, "distances": distances}


## The GameState flag that records one catalogued specimen.
static func flag_for(index: int) -> String:
	return FLAG_PREFIX + str(index)


## True once Kern has catalogued this specimen.
static func is_catalogued(index: int) -> bool:
	return GameState.has_flag(flag_for(index))


## How many of `specimens` are catalogued, and how many of those are boundary
## blooms. Returns `{ found, total, boundary_found, boundary_total }` — one
## pass, because the compendium wants all four numbers at once.
static func progress(specimens: Array[Dictionary]) -> Dictionary:
	var found: int = 0
	var boundary_found: int = 0
	var boundary_total: int = 0
	for s: Dictionary in specimens:
		var is_boundary: bool = bool(s["boundary"])
		if is_boundary:
			boundary_total += 1
		if is_catalogued(int(s["index"])):
			found += 1
			if is_boundary:
				boundary_found += 1
	return {
		"found": found,
		"total": specimens.size(),
		"boundary_found": boundary_found,
		"boundary_total": boundary_total,
	}
