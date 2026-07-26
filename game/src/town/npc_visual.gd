class_name NpcVisual
extends Node3D
## A code-built, cel-shaded villager — the same silhouette-first, no-imported-
## assets approach EnemyVisual takes for monsters, pointed at people.
##
## One generator dresses all thirteen approved Bootstrap NPCs. `role` comes
## straight from the ContentDB entry (the npc schema's enum); `accent`
## disambiguates the roles the schema lumps together and carries the detail the
## approved descriptions insist on — Tansy's yellow veil, Orrin's turnip-button
## waistcoat, Clem's four tiny hourglasses, Nessa's two wooden needles, Jory's
## enormous mud boots, Cedric's wool cape, the Mayor's shard chain of office.
##
## Personality (also from the entry) sets posture, because a pompous mayor and
## a shy mender should read differently from across the square before either
## has said a word. Colors are deterministic per NPC id: Bootstrap looks the
## same every boot.

const BODY_HEIGHT: float = 1.78

## Work motions the town ticks: "hammer", "sew", "dig", "cast", "stir",
## "ring", "tend", "write", "watch", "play", "herd", "none".
var work: String = "none"

var eye_height: float = 1.62

var _head: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _prop: Node3D          ## the tool the work motion swings
var _phase: float = 0.0
var _bob: float = 0.0
var _head_tilt: float = 0.0   ## posture, held under the idle sway
var _bees: Array[Node3D] = []


func build(role: String, accent: String, personality: Array, key: String) -> void:
	var rng: RandomNumberGenerator = TownKit.rng_for("npc_" + key)
	_phase = rng.randf() * TAU

	var child: bool = role == "child"
	var stature: float = (0.66 if child else rng.randf_range(0.95, 1.05))
	scale = Vector3(stature, stature, stature)
	eye_height = BODY_HEIGHT * 0.91 * stature

	var cloth: Color = _cloth_color(rng, role, accent)
	var trim: Color = _trim_color(rng, cloth)
	var skin: Color = _skin_color(rng)
	var hair: Color = _hair_color(rng, role)

	_build_body(cloth, trim, skin, hair, rng, role, accent)
	_apply_posture(personality)
	_apply_role(role, accent, cloth, trim, rng)


func _process(delta: float) -> void:
	_phase += delta
	# Everyone breathes; nobody in Bootstrap stands like a statue.
	_bob = sin(_phase * 1.6) * 0.012
	position.y = _bob
	if _head != null:
		_head.rotation.z = _head_tilt + sin(_phase * 0.7) * 0.03
		_head.rotation.y = sin(_phase * 0.43) * 0.12

	match work:
		"hammer":
			# Branna's arm falls, the blade rings, the arm lifts again.
			var swing: float = absf(sin(_phase * 2.6))
			if _arm_right != null:
				_arm_right.rotation.x = -1.2 + swing * 1.5
		"sew":
			if _arm_right != null:
				_arm_right.rotation.x = -0.9 + sin(_phase * 3.4) * 0.28
			if _arm_left != null:
				_arm_left.rotation.x = -0.8
		"dig":
			var dig: float = sin(_phase * 1.5)
			if _arm_right != null:
				_arm_right.rotation.x = -0.7 + dig * 0.5
			if _prop != null:
				_prop.rotation.x = -0.5 + dig * 0.45
		"cast":
			# Fen's rod nods over the millpond; the fish are unimpressed.
			if _prop != null:
				_prop.rotation.x = -0.95 + sin(_phase * 0.9) * 0.1
		"stir":
			if _arm_right != null:
				_arm_right.rotation.x = -1.1
			if _prop != null:
				_prop.rotation.z = sin(_phase * 2.2) * 0.35
		"ring":
			var pull: float = sin(_phase * 1.1)
			if _arm_right != null:
				_arm_right.rotation.x = -1.4 + pull * 0.55
			if _arm_left != null:
				_arm_left.rotation.x = -1.3 + pull * 0.5
		"tend":
			for i in _bees.size():
				var bee: Node3D = _bees[i]
				var t: float = _phase * 1.3 + float(i) * 2.1
				bee.position = Vector3(cos(t) * 0.55, 1.35 + sin(t * 1.7) * 0.22, sin(t) * 0.55)
		"write":
			if _arm_right != null:
				_arm_right.rotation.x = -1.15 + sin(_phase * 2.9) * 0.12
			if _arm_left != null:
				_arm_left.rotation.x = -1.0
		"watch":
			if _prop != null:
				_prop.rotation.z = sin(_phase * 0.5) * 0.04
		"play":
			# Tilly, mid-gallop on Sir Nearest.
			position.y = _bob + absf(sin(_phase * 3.2)) * 0.09
			rotation.z = sin(_phase * 3.2) * 0.05
			if _arm_right != null:
				_arm_right.rotation.x = -1.5
			if _arm_left != null:
				_arm_left.rotation.x = -1.5
		"herd":
			if _prop != null:
				_prop.rotation.z = 0.12 + sin(_phase * 0.8) * 0.05


# --- Anatomy -----------------------------------------------------------------

func _build_body(cloth: Color, trim: Color, skin: Color, hair: Color,
		rng: RandomNumberGenerator, role: String, accent: String) -> void:
	var boot: Color = Color(0.3, 0.22, 0.16)
	for sx: int in [-1, 1]:
		TownKit.part(self, "Boot%d" % sx, TownKit.box(Vector3(0.16, 0.14, 0.26)),
			Vector3(0.11 * sx, 0.07, -0.02), TownKit.toon(boot))
		TownKit.part(self, "Leg%d" % sx, TownKit.cyl(0.075, 0.065, 0.72, 8),
			Vector3(0.11 * sx, 0.5, 0.0), TownKit.toon(cloth.darkened(0.35)))

	var long_robe: bool = role == "scholar" or accent == "mayor"
	if long_robe:
		TownKit.part(self, "Robe", TownKit.cyl(0.26, 0.42, 0.85, 12), Vector3(0.0, 0.56, 0.0),
			TownKit.toon(cloth))
	TownKit.part(self, "Torso", TownKit.box(Vector3(0.46, 0.58, 0.3)), Vector3(0.0, 1.15, 0.0),
		TownKit.toon(cloth))
	TownKit.part(self, "Belt", TownKit.box(Vector3(0.48, 0.09, 0.32)), Vector3(0.0, 0.9, 0.0),
		TownKit.toon(trim.darkened(0.25)))
	TownKit.part(self, "Collar", TownKit.box(Vector3(0.4, 0.09, 0.28)), Vector3(0.0, 1.42, 0.0),
		TownKit.toon(trim))

	for sx: int in [-1, 1]:
		var shoulder: Node3D = Node3D.new()
		shoulder.name = "Arm%d" % sx
		shoulder.position = Vector3(0.28 * sx, 1.36, 0.0)
		shoulder.rotation.z = 0.16 * sx
		add_child(shoulder)
		TownKit.part(shoulder, "Upper", TownKit.cyl(0.06, 0.055, 0.46, 7),
			Vector3(0.0, -0.23, 0.0), TownKit.toon(cloth.lightened(0.04)))
		TownKit.part(shoulder, "Hand", TownKit.ball(0.065, 8, 5), Vector3(0.0, -0.5, 0.0),
			TownKit.toon(skin))
		if sx < 0:
			_arm_left = shoulder
		else:
			_arm_right = shoulder

	_head = Node3D.new()
	_head.name = "Head"
	_head.position = Vector3(0.0, 1.48, 0.0)
	add_child(_head)
	TownKit.part(_head, "Neck", TownKit.cyl(0.06, 0.07, 0.1, 7), Vector3(0.0, 0.02, 0.0),
		TownKit.toon(skin))
	TownKit.part(_head, "Skull", TownKit.ball(0.155, 12, 8), Vector3(0.0, 0.19, 0.0),
		TownKit.toon(skin))
	TownKit.part(_head, "Nose", TownKit.ball(0.035, 6, 4), Vector3(0.0, 0.18, -0.15),
		TownKit.toon(skin.darkened(0.06)))
	for sx: int in [-1, 1]:
		TownKit.part(_head, "Eye%d" % sx, TownKit.ball(0.022, 6, 4),
			Vector3(0.058 * sx, 0.22, -0.135), TownKit.flat(Color(0.13, 0.11, 0.12)))
		TownKit.part(_head, "Ear%d" % sx, TownKit.ball(0.035, 6, 4),
			Vector3(0.15 * sx, 0.19, 0.0), TownKit.toon(skin))
	var mane: MeshInstance3D = TownKit.part(_head, "Hair", TownKit.ball(0.165, 12, 8),
		Vector3(0.0, 0.23, 0.02), TownKit.toon(hair))
	mane.scale = Vector3(1.0, 0.72, 1.0)
	if rng.randf() < 0.4:
		# A long braid or tail — Branna's soot-black braid, Nessa's pinned silver.
		TownKit.part(_head, "Braid", TownKit.cyl(0.045, 0.03, 0.42, 7),
			Vector3(0.0, 0.02, 0.15), TownKit.toon(hair))


func _apply_posture(personality: Array) -> void:
	if _head == null:
		return
	if personality.has("pompous"):
		_head.position.z -= 0.03      # chin up, chest out
		_head.rotation.x = -0.1
	elif personality.has("shy"):
		_head.position.z += 0.04      # tucked in
		_head.rotation.x = 0.14
	elif personality.has("grumpy"):
		_head.rotation.x = 0.06
		if _arm_left != null:
			_arm_left.rotation.x = -1.2
		if _arm_right != null:
			_arm_right.rotation.x = -1.2
	elif personality.has("crazy"):
		_head_tilt = 0.16


# --- Role dressing -----------------------------------------------------------

func _apply_role(role: String, accent: String, cloth: Color, trim: Color,
		rng: RandomNumberGenerator) -> void:
	match accent:
		"mayor":
			_mayor(trim)
			work = "watch"
			return
		"beekeeper":
			_beekeeper()
			work = "tend"
			return
		"greengrocer":
			_greengrocer(trim)
			work = "watch"
			return
		"bellringer":
			_bellringer(rng)
			work = "ring"
			return
		"seamstress":
			_seamstress()
			work = "sew"
			return
		"ditcher":
			_ditcher()
			work = "dig"
			return
		"shepherd":
			_shepherd(cloth)
			work = "herd"
			return

	match role:
		"innkeeper":
			_innkeeper(trim)
			work = "stir"
		"smith":
			_smith()
			work = "hammer"
		"fisher":
			_fisher()
			work = "cast"
		"scholar":
			_scholar()
			work = "write"
		"guard":
			_guard(trim)
			work = "watch"
		"child":
			_child()
			work = "play"
		_:
			work = "watch"


func _apron(color: Color, dusty: bool) -> void:
	TownKit.part(self, "Apron", TownKit.box(Vector3(0.42, 0.72, 0.06)), Vector3(0.0, 1.0, -0.17),
		TownKit.toon(color))
	if dusty:
		for i in 4:
			TownKit.part(self, "Dust%d" % i, TownKit.ball(0.035, 6, 4),
				Vector3(-0.14 + float(i) * 0.09, 0.85 + float(i % 2) * 0.2, -0.21),
				TownKit.toon(color.lightened(0.35)))


func _hat_brim(color: Color, radius: float, y: float) -> void:
	TownKit.part(_head, "Brim", TownKit.cyl(radius, radius, 0.035, 12), Vector3(0.0, y, 0.0),
		TownKit.toon(color))


func _held(part_name: String, right_hand: bool = true) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.name = part_name
	pivot.position = Vector3(0.0, -0.5, 0.0)
	var arm: Node3D = _arm_right if right_hand else _arm_left
	if arm != null:
		arm.add_child(pivot)
	else:
		add_child(pivot)
	return pivot


func _innkeeper(trim: Color) -> void:
	# Mara: broad-smiled, flour-dusted green apron; a ladle always in hand.
	_apron(Color(0.36, 0.52, 0.3), true)
	TownKit.part(_head, "Cap", TownKit.cyl(0.15, 0.17, 0.1, 10), Vector3(0.0, 0.33, 0.0),
		TownKit.toon(trim.lightened(0.2)))
	var ladle: Node3D = _held("Ladle")
	TownKit.part(ladle, "Handle", TownKit.cyl(0.018, 0.018, 0.42, 6), Vector3(0.0, -0.18, 0.0),
		TownKit.toon(Color(0.55, 0.4, 0.24)))
	TownKit.part(ladle, "Bowl", TownKit.ball(0.07, 8, 5), Vector3(0.0, -0.4, 0.0),
		TownKit.toon(Color(0.68, 0.6, 0.4)))
	_prop = ladle


func _smith() -> void:
	# Branna: soot-black braid, heavy leather apron stitched with copper rings.
	_apron(Color(0.34, 0.25, 0.18), false)
	for i in 3:
		TownKit.part(self, "CopperRing%d" % i, TownKit.cyl(0.035, 0.035, 0.015, 8),
			Vector3(-0.12 + float(i) * 0.12, 1.12, -0.21), TownKit.toon(Color(0.76, 0.46, 0.22)),
			Vector3(PI * 0.5, 0.0, 0.0))
	for sx: int in [-1, 1]:
		TownKit.part(self, "ArmBand%d" % sx, TownKit.cyl(0.07, 0.07, 0.06, 8),
			Vector3(0.31 * sx, 1.02, 0.0), TownKit.toon(Color(0.42, 0.3, 0.2)))
	var hammer: Node3D = _held("Hammer")
	TownKit.part(hammer, "Haft", TownKit.cyl(0.02, 0.022, 0.4, 6), Vector3(0.0, -0.16, 0.0),
		TownKit.toon(Color(0.5, 0.36, 0.22)))
	TownKit.part(hammer, "Head", TownKit.box(Vector3(0.1, 0.11, 0.22)), Vector3(0.0, -0.36, 0.0),
		TownKit.toon(Color(0.3, 0.31, 0.33)))
	_prop = hammer


func _fisher() -> void:
	# Fen: patched reed hat hung with silver scales, and a rod over the pond.
	_hat_brim(Color(0.72, 0.63, 0.36), 0.3, 0.3)
	TownKit.part(_head, "HatCone", TownKit.cyl(0.0, 0.18, 0.22, 10), Vector3(0.0, 0.42, 0.0),
		TownKit.toon(Color(0.72, 0.63, 0.36)))
	for i in 4:
		TownKit.part(_head, "Scale%d" % i, TownKit.ball(0.03, 6, 4),
			Vector3(cos(float(i) * 1.6) * 0.28, 0.28, sin(float(i) * 1.6) * 0.28),
			TownKit.toon(Color(0.78, 0.82, 0.86)))
	var rod: Node3D = _held("Rod")
	TownKit.part(rod, "Pole", TownKit.cyl(0.012, 0.022, 1.9, 6), Vector3(0.0, -0.7, 0.0),
		TownKit.toon(Color(0.56, 0.42, 0.25)))
	TownKit.part(rod, "Line", TownKit.cyl(0.004, 0.004, 1.2, 4), Vector3(0.0, -1.6, -0.55),
		TownKit.flat(Color(0.9, 0.9, 0.86)))
	rod.rotation.x = -0.95
	_prop = rod


func _scholar() -> void:
	# Elowen: round spectacles mended with blue thread, twelve numbered
	# notebooks in a plum robe.
	for sx: int in [-1, 1]:
		var lens: TorusMesh = TorusMesh.new()
		lens.inner_radius = 0.035
		lens.outer_radius = 0.05
		lens.rings = 10
		lens.ring_segments = 5
		TownKit.part(_head, "Lens%d" % sx, lens, Vector3(0.055 * sx, 0.22, -0.14),
			TownKit.toon(Color(0.72, 0.68, 0.5)), Vector3(PI * 0.5, 0.0, 0.0))
	TownKit.part(_head, "Bridge", TownKit.box(Vector3(0.05, 0.012, 0.012)),
		Vector3(0.0, 0.22, -0.145), TownKit.toon(Color(0.3, 0.45, 0.8)))
	var book: Node3D = _held("Notebook", false)
	TownKit.part(book, "Cover", TownKit.box(Vector3(0.2, 0.26, 0.05)), Vector3(0.0, -0.06, -0.08),
		TownKit.toon(Color(0.42, 0.25, 0.4)))
	TownKit.part(book, "Pages", TownKit.box(Vector3(0.18, 0.24, 0.03)),
		Vector3(0.0, -0.06, -0.11), TownKit.toon(Color(0.92, 0.9, 0.82)))
	var quill: Node3D = _held("Quill")
	TownKit.part(quill, "Feather", TownKit.cyl(0.004, 0.014, 0.22, 5), Vector3(0.0, -0.12, 0.0),
		TownKit.toon(Color(0.94, 0.93, 0.9)))
	_prop = quill


func _guard(trim: Color) -> void:
	# Rowan: tidy blue cloak, a helmet polished brighter than necessary.
	TownKit.part(self, "Cloak", TownKit.box(Vector3(0.5, 0.8, 0.08)), Vector3(0.0, 1.06, 0.19),
		TownKit.toon(Color(0.24, 0.36, 0.62)))
	TownKit.part(_head, "Helmet", TownKit.ball(0.175, 12, 8), Vector3(0.0, 0.24, 0.0),
		TownKit.toon(Color(0.74, 0.77, 0.8)))
	TownKit.part(_head, "Crest", TownKit.box(Vector3(0.04, 0.1, 0.3)), Vector3(0.0, 0.4, 0.0),
		TownKit.toon(trim))
	var spear: Node3D = _held("Spear")
	TownKit.part(spear, "Shaft", TownKit.cyl(0.022, 0.024, 2.2, 6), Vector3(0.0, -0.55, 0.0),
		TownKit.toon(Color(0.5, 0.37, 0.23)))
	TownKit.part(spear, "Tip", TownKit.cyl(0.0, 0.05, 0.26, 6), Vector3(0.0, 0.68, 0.0),
		TownKit.toon(Color(0.78, 0.8, 0.84)))
	# One acorn for every harmless noise he once mistook for danger.
	TownKit.part(self, "AcornPouch", TownKit.ball(0.09, 8, 5), Vector3(0.19, 0.88, -0.14),
		TownKit.toon(Color(0.55, 0.42, 0.24)))
	_prop = spear


func _child() -> void:
	# Tilly: clover crown, mismatched boots, and Sir Nearest the broomstick.
	for i in 6:
		var ang: float = TAU * float(i) / 6.0
		TownKit.part(_head, "Clover%d" % i, TownKit.ball(0.035, 6, 4),
			Vector3(cos(ang) * 0.16, 0.33, sin(ang) * 0.16), TownKit.toon(Color(0.42, 0.68, 0.3)))
	var broom: Node3D = _held("SirNearest")
	TownKit.part(broom, "Stick", TownKit.cyl(0.026, 0.03, 1.5, 6), Vector3(0.0, -0.3, 0.1),
		TownKit.toon(Color(0.55, 0.4, 0.24)), Vector3(1.25, 0.0, 0.0))
	TownKit.part(broom, "Bristles", TownKit.cyl(0.02, 0.13, 0.34, 8), Vector3(0.0, -0.36, 0.82),
		TownKit.toon(Color(0.78, 0.66, 0.34)), Vector3(-0.3, 0.0, 0.0))
	_prop = broom


func _mayor(trim: Color) -> void:
	# Maxwell: a tricorne, a fine coat, and a chain of office made of polished
	# data shards (GDD: the shards are the world's canon material).
	TownKit.part(_head, "Tricorne", TownKit.cyl(0.3, 0.3, 0.05, 3), Vector3(0.0, 0.3, 0.0),
		TownKit.toon(Color(0.2, 0.18, 0.24)))
	TownKit.part(_head, "TricorneCrown", TownKit.cyl(0.13, 0.16, 0.14, 8), Vector3(0.0, 0.36, 0.0),
		TownKit.toon(Color(0.2, 0.18, 0.24)))
	TownKit.part(self, "Sash", TownKit.box(Vector3(0.5, 0.14, 0.33)), Vector3(0.0, 1.16, 0.0),
		TownKit.toon(trim.lightened(0.15)), Vector3(0.0, 0.0, 0.5))
	for i in 7:
		var ang: float = PI * (0.15 + 0.7 * float(i) / 6.0)
		var shard: MeshInstance3D = TownKit.part(self, "Shard%d" % i,
			TownKit.box(Vector3(0.07, 0.09, 0.03)),
			Vector3(-cos(ang) * 0.2, 1.38 - sin(ang) * 0.14, -0.17),
			TownKit.emissive(Color(0.55, 0.78, 1.0), 1.4))
		shard.rotation.z = ang
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _beekeeper() -> void:
	# Tansy: yellow veil, striped wool sleeves, and bees on their three ribbons.
	_hat_brim(Color(0.85, 0.78, 0.4), 0.32, 0.34)
	var veil: MeshInstance3D = TownKit.part(self, "Veil", TownKit.cyl(0.24, 0.3, 0.5, 12),
		Vector3(0.0, 1.62, 0.0), TownKit.emissive(Color(0.95, 0.88, 0.45), 0.12, 0.42))
	veil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx: int in [-1, 1]:
		for i in 3:
			TownKit.part(self, "Stripe%d_%d" % [sx, i], TownKit.cyl(0.062, 0.062, 0.09, 8),
				Vector3(0.29 * sx, 1.25 - float(i) * 0.14, 0.0),
				TownKit.toon(Color(0.16, 0.14, 0.12)))
	for i in 3:
		var bee: Node3D = Node3D.new()
		bee.name = "Bee%d" % i
		add_child(bee)
		TownKit.part(bee, "Body", TownKit.ball(0.035, 6, 4), Vector3.ZERO,
			TownKit.emissive(Color(0.95, 0.78, 0.2), 1.2))
		_bees.append(bee)


func _greengrocer(trim: Color) -> void:
	# Orrin: russet waistcoat with turnip-shaped buttons.
	TownKit.part(self, "Waistcoat", TownKit.box(Vector3(0.48, 0.5, 0.33)), Vector3(0.0, 1.16, 0.0),
		TownKit.toon(Color(0.5, 0.26, 0.16)))
	for i in 4:
		TownKit.part(self, "TurnipButton%d" % i, TownKit.ball(0.028, 7, 4),
			Vector3(0.0, 1.34 - float(i) * 0.11, -0.17), TownKit.toon(Color(0.93, 0.9, 0.88)))
	TownKit.part(_head, "FlatCap", TownKit.cyl(0.17, 0.19, 0.07, 10), Vector3(0.0, 0.32, -0.03),
		TownKit.toon(trim.darkened(0.2)))


func _bellringer(rng: RandomNumberGenerator) -> void:
	# Clem: patchwork coat lined with four tiny hourglasses.
	var patches: Array[Color] = [
		Color(0.62, 0.3, 0.28), Color(0.3, 0.42, 0.55), Color(0.6, 0.55, 0.25),
		Color(0.38, 0.5, 0.34),
	]
	for i in 8:
		var patch: MeshInstance3D = TownKit.part(self, "Patch%d" % i,
			TownKit.box(Vector3(0.16, 0.16, 0.02)),
			Vector3(rng.randf_range(-0.18, 0.18), 0.95 + rng.randf_range(0.0, 0.42), -0.16),
			TownKit.toon(patches[i % patches.size()]))
		patch.rotation.z = rng.randf_range(-0.3, 0.3)
	for i in 4:
		var glass: Node3D = Node3D.new()
		glass.name = "Hourglass%d" % i
		glass.position = Vector3(-0.16 + float(i) * 0.11, 0.86, -0.19)
		add_child(glass)
		TownKit.part(glass, "Top", TownKit.cyl(0.03, 0.005, 0.05, 6), Vector3(0.0, 0.025, 0.0),
			TownKit.toon(Color(0.85, 0.8, 0.6)))
		TownKit.part(glass, "Bottom", TownKit.cyl(0.005, 0.03, 0.05, 6), Vector3(0.0, -0.025, 0.0),
			TownKit.toon(Color(0.85, 0.8, 0.6)))


func _seamstress() -> void:
	# Nessa: silver hair pinned with two wooden needles, a measuring cord at
	# one wrist, and pins in an iris-blossom cushion.
	for sx: int in [-1, 1]:
		TownKit.part(_head, "Needle%d" % sx, TownKit.cyl(0.008, 0.008, 0.28, 5),
			Vector3(0.07 * sx, 0.3, 0.06), TownKit.toon(Color(0.62, 0.46, 0.28)),
			Vector3(0.0, 0.0, 0.6 * sx))
	TownKit.part(self, "MeasuringCord", TownKit.cyl(0.075, 0.075, 0.02, 10),
		Vector3(0.3, 0.9, 0.0), TownKit.toon(Color(0.9, 0.84, 0.6)))
	var cushion: MeshInstance3D = TownKit.part(self, "PinCushion", TownKit.ball(0.09, 8, 5),
		Vector3(-0.24, 0.95, -0.14), TownKit.toon(Color(0.58, 0.42, 0.72)))
	for i in 5:
		TownKit.part(cushion, "Pin%d" % i, TownKit.cyl(0.005, 0.005, 0.1, 4),
			Vector3(cos(float(i) * 1.3) * 0.05, 0.06, sin(float(i) * 1.3) * 0.05),
			TownKit.flat(Color(0.85, 0.86, 0.88)))
	var cloth: Node3D = _held("Mending", false)
	TownKit.part(cloth, "Cloth", TownKit.box(Vector3(0.3, 0.24, 0.03)), Vector3(0.0, -0.1, -0.1),
		TownKit.toon(Color(0.4, 0.55, 0.42)))
	_prop = cloth


func _ditcher() -> void:
	# Jory: enormous mud boots, bent straw hat, and a blue marble he races the
	# water against before he trusts a new channel.
	for sx: int in [-1, 1]:
		TownKit.part(self, "MudBoot%d" % sx, TownKit.box(Vector3(0.22, 0.5, 0.34)),
			Vector3(0.12 * sx, 0.25, -0.03), TownKit.toon(Color(0.25, 0.21, 0.18)))
	_hat_brim(Color(0.78, 0.68, 0.38), 0.3, 0.31)
	var hat_top: MeshInstance3D = TownKit.part(_head, "HatTop", TownKit.cyl(0.13, 0.17, 0.14, 9),
		Vector3(0.0, 0.37, 0.0), TownKit.toon(Color(0.78, 0.68, 0.38)))
	hat_top.rotation.z = 0.18
	TownKit.part(self, "Marble", TownKit.ball(0.03, 7, 4), Vector3(-0.2, 0.92, -0.16),
		TownKit.emissive(Color(0.3, 0.5, 0.9), 0.9))
	var shovel: Node3D = _held("Shovel")
	TownKit.part(shovel, "Handle", TownKit.cyl(0.022, 0.022, 1.1, 6), Vector3(0.0, -0.3, 0.0),
		TownKit.toon(Color(0.54, 0.4, 0.24)))
	TownKit.part(shovel, "Blade", TownKit.box(Vector3(0.22, 0.3, 0.04)), Vector3(0.0, -0.9, 0.0),
		TownKit.toon(Color(0.42, 0.44, 0.46)))
	_prop = shovel


func _shepherd(cloth: Color) -> void:
	# Cedric: a grand cape of his flock's own wool, and a crook strung with
	# colored cords for the flock's many moods.
	var cape: MeshInstance3D = TownKit.part(self, "WoolCape", TownKit.cyl(0.3, 0.44, 0.9, 12),
		Vector3(0.0, 1.05, 0.06), TownKit.toon(Color(0.9, 0.88, 0.84)))
	cape.scale = Vector3(1.0, 1.0, 0.8)
	TownKit.part(self, "CapeClasp", TownKit.ball(0.05, 7, 4), Vector3(0.0, 1.42, -0.16),
		TownKit.toon(cloth.lightened(0.3)))
	var crook: Node3D = _held("Crook")
	TownKit.part(crook, "Staff", TownKit.cyl(0.024, 0.028, 1.8, 6), Vector3(0.0, -0.5, 0.0),
		TownKit.toon(Color(0.58, 0.44, 0.26)))
	var hook: TorusMesh = TorusMesh.new()
	hook.inner_radius = 0.1
	hook.outer_radius = 0.15
	hook.rings = 10
	hook.ring_segments = 5
	TownKit.part(crook, "Hook", hook, Vector3(0.1, 0.36, 0.0),
		TownKit.toon(Color(0.58, 0.44, 0.26)), Vector3(PI * 0.5, 0.0, 0.0))
	var cords: Array[Color] = [
		Color(0.85, 0.32, 0.3), Color(0.35, 0.6, 0.85), Color(0.95, 0.84, 0.3),
		Color(0.5, 0.8, 0.45),
	]
	for i in cords.size():
		TownKit.part(crook, "Cord%d" % i, TownKit.cyl(0.012, 0.012, 0.24, 5),
			Vector3(0.0, 0.1 - float(i) * 0.09, 0.03), TownKit.toon(cords[i]))
	_prop = crook


# --- Palette -----------------------------------------------------------------

func _cloth_color(rng: RandomNumberGenerator, role: String, accent: String) -> Color:
	if accent == "mayor":
		return Color(0.35, 0.27, 0.45)        # mayoral plum-and-slate
	if role == "scholar":
		return Color(0.45, 0.3, 0.46)         # Elowen's plum robe
	if role == "guard":
		return Color(0.28, 0.38, 0.6)         # Bootstrap blue
	var village: Array[Color] = [
		Color(0.46, 0.5, 0.32), Color(0.58, 0.42, 0.28), Color(0.36, 0.46, 0.5),
		Color(0.6, 0.5, 0.32), Color(0.44, 0.38, 0.5), Color(0.52, 0.36, 0.32),
	]
	return village[rng.randi() % village.size()]


func _trim_color(rng: RandomNumberGenerator, cloth: Color) -> Color:
	var trims: Array[Color] = [
		Color(0.78, 0.68, 0.4), Color(0.66, 0.3, 0.3), Color(0.32, 0.5, 0.42),
		Color(0.8, 0.76, 0.66),
	]
	var pick: Color = trims[rng.randi() % trims.size()]
	# Trim that lands too close to the cloth reads as a smudge, not a trim.
	var apart: float = absf(pick.r - cloth.r) + absf(pick.g - cloth.g) + absf(pick.b - cloth.b)
	return pick if apart > 0.45 else cloth.lightened(0.28)


func _skin_color(rng: RandomNumberGenerator) -> Color:
	var tones: Array[Color] = [
		Color(0.92, 0.76, 0.62), Color(0.82, 0.63, 0.47), Color(0.66, 0.47, 0.34),
		Color(0.5, 0.35, 0.25), Color(0.36, 0.25, 0.18), Color(0.95, 0.82, 0.71),
	]
	return tones[rng.randi() % tones.size()]


func _hair_color(rng: RandomNumberGenerator, role: String) -> Color:
	var hairs: Array[Color] = [
		Color(0.16, 0.13, 0.11), Color(0.32, 0.2, 0.12), Color(0.55, 0.42, 0.22),
		Color(0.68, 0.66, 0.62), Color(0.45, 0.24, 0.14),
	]
	if role == "flavor" and rng.randf() < 0.35:
		return Color(0.78, 0.77, 0.74)        # a village full of one age reads wrong
	return hairs[rng.randi() % hairs.size()]
