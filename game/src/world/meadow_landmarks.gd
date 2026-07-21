class_name MeadowLandmarks
extends Node3D
## Plants the named places Bit will notice across Datasedge Meadows, at the
## canonical map positions baked into MeadowTerrain (town, millpond, Vault,
## etc.). Each spawns a BitLandmark that registers itself for the companion to
## scan. These anchors are also where a later milestone drops the real POI
## props, so the geography stays consistent between Bit's naming and the world.
##
## Naming lines are in Bit's voice (curious, loyal, vain, water-shy) and respect
## canon — including NOT spoiling who Kern is at the Vault.

var _terrain: Node


func build(terrain: Node) -> void:
	_terrain = terrain

	_add("bootstrap_town", "Bootstrap", 0.0, 30.0, 42.0, false, [
		"That's Bootstrap. The whole town grew up from almost nothing, one careful step at a time. Sounds like somebody I know.",
		"Bootstrap, dead ahead — warm beds, warmer gossip, and a mayor forever rehearsing a speech.",
	])
	_add("old_millpond", "the Old Millpond", 95.0, 10.0, 30.0, false, [
		"The Old Millpond. Something down there keeps count of the coins, they say — and I keep my distance. That is a LOT of water.",
		"The mill! Lovely wheel. Absolutely dreadful swimming conditions, in my professional opinion.",
	])
	_add("seed_vault_ruins", "the Seed Vault ruins", -72.0, -70.0, 30.0, false, [
		"The Seed Vault ruins. This is where they found you, Kern. The old machines still stir when you come near — don't ask me how I know. I just do.",
		"Careful in the ruins. The Vault remembers things even you don't.",
	])
	_add("whispering_well", "the Whispering Well", 46.0, 24.0, 16.0, true, [
		"Ooh — the Whispering Well! Toss in a Token, make a wish, and it rounds up if you ask nicely. I have tested this thoroughly.",
	])
	_add("boundary_stones", "the Old Boundary Stones", 58.0, -74.0, 26.0, false, [
		"The Old Boundary Stones. They mark a line nobody can see anymore, and the farmers plow around them without asking why. I ask why constantly.",
	])
	_add("hivewise_apiary", "Hivewise Apiary", 70.0, -14.0, 22.0, false, [
		"Hivewise Apiary. Every bee here has a route and sticks to it. Try to keep up — they will not slow down for you.",
	])
	_add("gradient_peaks_vista", "the Gradient Peaks", 0.0, -205.0, 88.0, false, [
		"Look north — the Gradient Peaks. Every trail up there climbs toward the same cold summit. We'll go someday. Bundle up.",
	])
	_add("latent_forest_vista", "the Latent Forest", 200.0, 44.0, 88.0, false, [
		"That deep treeline to the east is the Latent Forest. Bigger inside than out, they say. Don't wander in without me — you'd never find the way back.",
	])


func _add(id: String, name_text: String, x: float, z: float, radius: float,
		senses: bool, lines: Array[String]) -> void:
	var lm: BitLandmark = BitLandmark.new()
	lm.name = "Landmark_" + id
	lm.configure(id, name_text, radius, lines, senses)
	var y: float = 1.2
	if _terrain != null and _terrain.has_method("get_height"):
		y = _terrain.get_height(x, z) + 1.2
	lm.position = Vector3(x, y, z)
	add_child(lm)
