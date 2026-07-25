class_name TownBuilding
extends StaticBody3D
## One code-authored Bootstrap building: a timber-framed shell under a gabled
## roof, with shuttered windows that warm up at dusk and per-style extras.
##
## WORLDBOOK Datasedge: Bootstrap is a golden farming town, tutorial-safe and
## welcoming, and its ML puns hide in proper nouns and behavior — never in
## vocabulary. So the architecture is plain honest village carpentry and the
## jokes live on the signboards ("The Warm Start").
##
## Styles:
##   * cottage — an ordinary house: timber frame, flower box, shutters
##   * house   — a cottage with a working window (scholar's ledgers, mender's seat)
##   * inn     — two storeys, jettied upper floor, dormer, hanging sign, bench
##   * forge   — open-fronted smithy: stone chimney, coal glow, anvil, rack
##   * hall    — the mayor's town hall: stone base, portico columns, banner
##   * tower   — the bell tower Clem Clatter rings (his bell is named Confusion)
##   * mill    — the millpond's water mill; `wheel` turns, driven by BootstrapTown
##
## A building is authored facing -Z (Godot forward) and rotated into place by
## BootstrapTown, so "front" always means the -Z face. Collision is one box per
## solid mass: the shells are exterior-only for this milestone (see DEVLOG —
## interiors are their own scope), so doors are painted, not portals.

const BEAM: Color = Color(0.31, 0.22, 0.15)
const STONE: Color = Color(0.55, 0.54, 0.5)

## Set for the mill; BootstrapTown spins it so the pond drives the wheel.
var wheel: Node3D
## Hanging signboards sway; BootstrapTown ticks them together.
var swingers: Array[Node3D] = []
## Where a villager posted "at the door" should stand, in local space.
var door_mark: Vector3 = Vector3.ZERO


## `size` is (width, wall height, depth) in meters. `opts` keys are all
## optional: sign (String), chimney (bool), smoke (bool), porch (bool),
## flowers (bool), lantern (bool).
func build(style: String, size: Vector3, wall: Color, roof: Color,
		opts: Dictionary = {}) -> void:
	var w: float = size.x
	var h: float = size.y
	var d: float = size.z
	door_mark = Vector3(0.0, 0.0, -d * 0.5 - 1.6)

	match style:
		"inn":
			_build_inn(w, h, d, wall, roof, opts)
		"forge":
			_build_forge(w, h, d, wall, roof)
		"hall":
			_build_hall(w, h, d, wall, roof, opts)
		"tower":
			_build_tower(w, h, d, wall, roof)
		"mill":
			_build_mill(w, h, d, wall, roof, opts)
		"house":
			_build_cottage(w, h, d, wall, roof, opts, true)
		_:
			_build_cottage(w, h, d, wall, roof, opts, false)

	if bool(opts.get("chimney", false)):
		_chimney(Vector3(w * 0.34, 0.0, d * 0.2), h, bool(opts.get("smoke", false)))
	if opts.has("sign"):
		_hanging_sign(str(opts["sign"]), Vector3(0.0, h * 0.72, -d * 0.5 - 0.06),
			float(opts.get("sign_side", 1.0)))
	if bool(opts.get("lantern", false)):
		# A flame with nothing around it reads as a floating bead by daylight,
		# so the door lantern gets its bracket and housing like a street lamp.
		var at: Vector3 = Vector3(1.0, 2.3, -d * 0.5 - 0.16)
		TownKit.plank(self, "LanternBracket", Vector3(0.42, 0.06, 0.06),
			at + Vector3(-0.2, 0.3, 0.14), Color(0.2, 0.2, 0.22))
		TownKit.plank(self, "LanternHousing", Vector3(0.26, 0.3, 0.26), at,
			Color(0.2, 0.2, 0.22))
		TownKit.part(self, "LanternCap", TownKit.cyl(0.0, 0.22, 0.14, 4),
			at + Vector3(0.0, 0.21, 0.0), TownKit.toon(Color(0.17, 0.17, 0.19)),
			Vector3(0.0, PI * 0.25, 0.0))
		TownKit.lantern(self, "DoorLantern", at, 8.0)


# --- Styles ------------------------------------------------------------------

func _build_cottage(w: float, h: float, d: float, wall: Color, roof: Color,
		opts: Dictionary, working_window: bool) -> void:
	_walls(w, h, d, wall)
	_timber_frame(w, h, d)
	_gable_roof(w, h, d, roof)
	_door(Vector3(0.0, 0.0, -d * 0.5))
	if working_window:
		# A wide shop/ledger window with a sill board — the room behind it is
		# where Elowen's notebooks and Nessa's mending live.
		_window(Vector3(-w * 0.26, h * 0.55, -d * 0.5), Vector2(1.5, 1.05), 0.0, true)
		TownKit.plank(self, "SillBoard", Vector3(1.7, 0.1, 0.5),
			Vector3(-w * 0.26, h * 0.55 - 0.58, -d * 0.5 - 0.2), BEAM)
	else:
		_window(Vector3(-w * 0.28, h * 0.58, -d * 0.5), Vector2(0.8, 0.9), 0.0, true)
	_window(Vector3(w * 0.28, h * 0.58, -d * 0.5), Vector2(0.8, 0.9), 0.0, true)
	_window(Vector3(-w * 0.5, h * 0.58, d * 0.1), Vector2(0.8, 0.9), PI * 0.5, true)
	if bool(opts.get("flowers", true)):
		_flower_box(Vector3(w * 0.28, h * 0.58 - 0.62, -d * 0.5 - 0.22))
	_collide(w, h, d)


func _build_inn(w: float, h: float, d: float, wall: Color, roof: Color,
		_opts: Dictionary) -> void:
	var lower: float = h * 0.5
	_walls(w, lower, d, wall)
	# Jettied upper storey — the overhanging first floor of an old inn.
	var up_w: float = w + 0.7
	var up_d: float = d + 0.7
	TownKit.plank(self, "UpperStorey", Vector3(up_w, h - lower, up_d),
		Vector3(0.0, lower + (h - lower) * 0.5, 0.0), wall.lightened(0.06))
	TownKit.plank(self, "Jetty", Vector3(up_w + 0.2, 0.22, up_d + 0.2),
		Vector3(0.0, lower + 0.06, 0.0), BEAM)
	_timber_frame(w, lower, d)
	_timber_frame_upper(up_w, lower, h, up_d)
	_gable_roof(up_w, h, up_d, roof)
	_dormer(up_w, h, up_d, wall, roof)
	_door(Vector3(0.0, 0.0, -d * 0.5), 2.2)
	_window(Vector3(-w * 0.3, lower * 0.62, -d * 0.5), Vector2(1.0, 0.9), 0.0, true)
	_window(Vector3(w * 0.3, lower * 0.62, -d * 0.5), Vector2(1.0, 0.9), 0.0, true)
	_window(Vector3(-up_w * 0.28, lower + 0.95, -up_d * 0.5), Vector2(0.8, 0.85), 0.0, true)
	_window(Vector3(up_w * 0.28, lower + 0.95, -up_d * 0.5), Vector2(0.8, 0.85), 0.0, true)
	_window(Vector3(-w * 0.5, lower * 0.62, d * 0.15), Vector2(0.9, 0.9), PI * 0.5, true)
	_window(Vector3(w * 0.5, lower * 0.62, d * 0.15), Vector2(0.9, 0.9), -PI * 0.5, true)
	# A bench by the door: Mara seats travelers "wherever the chair looks least
	# opinionated," and the Warm Start's porch is where they wait.
	_bench(Vector3(-w * 0.3, 0.0, -d * 0.5 - 0.9))
	_collide(up_w, h, up_d)


func _build_forge(w: float, h: float, d: float, wall: Color, roof: Color) -> void:
	# Three walls and an open front — Branna's smithy breathes.
	TownKit.plank(self, "BackWall", Vector3(w, h, 0.3), Vector3(0.0, h * 0.5, d * 0.5), wall)
	TownKit.plank(self, "LeftWall", Vector3(0.3, h, d), Vector3(-w * 0.5, h * 0.5, 0.0), wall)
	TownKit.plank(self, "RightWall", Vector3(0.3, h, d), Vector3(w * 0.5, h * 0.5, 0.0), wall)
	for sx: int in [-1, 1]:
		TownKit.plank(self, "FrontPost%d" % sx, Vector3(0.28, h, 0.28),
			Vector3(w * 0.5 * sx, h * 0.5, -d * 0.5), BEAM)
	TownKit.plank(self, "Lintel", Vector3(w + 0.3, 0.3, 0.34), Vector3(0.0, h, -d * 0.5), BEAM)
	_gable_roof(w, h, d, roof)
	# Stone hearth with live coals at the back wall.
	TownKit.plank(self, "Hearth", Vector3(2.0, 1.1, 1.2), Vector3(-w * 0.2, 0.55, d * 0.28), STONE)
	var coals: MeshInstance3D = TownKit.part(self, "Coals", TownKit.box(Vector3(1.5, 0.16, 0.8)),
		Vector3(-w * 0.2, 1.14, d * 0.28), TownKit.emissive(Color(1.0, 0.42, 0.12), 3.4))
	coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var forge_light: OmniLight3D = OmniLight3D.new()
	forge_light.name = "ForgeGlow"
	forge_light.position = Vector3(-w * 0.2, 1.5, d * 0.2)
	forge_light.light_color = Color(1.0, 0.55, 0.24)
	forge_light.light_energy = 3.2
	forge_light.omni_range = 11.0
	forge_light.shadow_enabled = false
	add_child(forge_light)
	# The forge beam Branna notches once per flawed blade she improves.
	var beam: MeshInstance3D = TownKit.plank(self, "NotchBeam", Vector3(0.3, 0.3, d * 0.8),
		Vector3(w * 0.34, h - 0.5, 0.0), BEAM.lightened(0.1))
	for i in 9:
		TownKit.plank(beam, "Notch%d" % i, Vector3(0.34, 0.05, 0.05),
			Vector3(0.0, 0.1, -d * 0.32 + float(i) * 0.24), Color(0.16, 0.11, 0.08))
	_rack(Vector3(w * 0.28, 0.0, d * 0.3))
	_collide(w, h, d)


func _build_hall(w: float, h: float, d: float, wall: Color, roof: Color,
		opts: Dictionary) -> void:
	# Stone base course under painted boards — the grandest thing in town,
	# which is exactly how Mayor Maxwell Pool would want it described.
	TownKit.plank(self, "Base", Vector3(w + 0.5, 1.0, d + 0.5), Vector3(0.0, 0.5, 0.0), STONE)
	_walls(w, h, d, wall, 1.0)
	_timber_frame(w, h, d, 1.0)
	_gable_roof(w, h + 1.0, d, roof)
	# Portico: four columns, a pediment beam, and steps up to double doors.
	for i in 4:
		var cx: float = -w * 0.32 + float(i) * (w * 0.64 / 3.0)
		TownKit.part(self, "Column%d" % i, TownKit.cyl(0.24, 0.28, h - 0.4, 10),
			Vector3(cx, 1.0 + (h - 0.4) * 0.5, -d * 0.5 - 1.4), TownKit.toon(Color(0.86, 0.84, 0.76)))
	TownKit.plank(self, "Architrave", Vector3(w * 0.78, 0.4, 2.0),
		Vector3(0.0, h + 0.8, -d * 0.5 - 1.0), Color(0.86, 0.84, 0.76))
	TownKit.part(self, "Pediment", TownKit.prism(Vector3(w * 0.78, 1.0, 2.0)),
		Vector3(0.0, h + 1.5, -d * 0.5 - 1.0), TownKit.toon(roof))
	for i in 3:
		var step: float = float(i)
		TownKit.plank(self, "Step%d" % i, Vector3(4.6 - step * 0.5, 0.22, 1.4 - step * 0.35),
			Vector3(0.0, 0.11 + step * 0.22, -d * 0.5 - 2.1 + step * 0.35), STONE.lightened(0.08))
	_door(Vector3(-0.55, 1.0, -d * 0.5), 2.5)
	_door(Vector3(0.55, 1.0, -d * 0.5), 2.5)
	_window(Vector3(-w * 0.4, h * 0.6 + 1.0, -d * 0.5), Vector2(1.0, 1.4), 0.0, true)
	_window(Vector3(w * 0.4, h * 0.6 + 1.0, -d * 0.5), Vector2(1.0, 1.4), 0.0, true)
	_window(Vector3(-w * 0.5, h * 0.6 + 1.0, 0.0), Vector2(1.0, 1.4), PI * 0.5, true)
	_window(Vector3(w * 0.5, h * 0.6 + 1.0, 0.0), Vector2(1.0, 1.4), -PI * 0.5, true)
	if bool(opts.get("banner", true)):
		_banner(Vector3(0.0, h + 1.0, -d * 0.5 - 0.4))
	_collide(w, h + 1.0, d)


func _build_tower(w: float, h: float, d: float, wall: Color, roof: Color) -> void:
	TownKit.plank(self, "Shaft", Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0), wall)
	_timber_frame(w, h, d)
	# Open belfry: four corner posts under a pyramid cap, with the bell inside.
	var belfry: float = 2.2
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			TownKit.plank(self, "Post%d_%d" % [sx, sz], Vector3(0.22, belfry, 0.22),
				Vector3(w * 0.42 * sx, h + belfry * 0.5, d * 0.42 * sz), BEAM)
	TownKit.plank(self, "BelfryFloor", Vector3(w + 0.5, 0.2, d + 0.5),
		Vector3(0.0, h + 0.1, 0.0), BEAM)
	TownKit.part(self, "Cap", TownKit.cyl(0.0, w * 0.95, 1.9, 4),
		Vector3(0.0, h + belfry + 0.95, 0.0), TownKit.toon(roof), Vector3(0.0, PI * 0.25, 0.0))
	# Confusion, the bell: rung for rain, goats, or visiting relatives.
	var bell: MeshInstance3D = TownKit.part(self, "Bell", TownKit.cyl(0.22, 0.52, 0.8, 12),
		Vector3(0.0, h + belfry * 0.55, 0.0), TownKit.toon(Color(0.72, 0.58, 0.24)))
	TownKit.part(bell, "Crown", TownKit.ball(0.16, 8, 5), Vector3(0.0, 0.44, 0.0),
		TownKit.toon(Color(0.66, 0.52, 0.2)))
	swingers.append(bell)
	TownKit.part(self, "BellRope", TownKit.cyl(0.03, 0.03, h * 0.8, 6),
		Vector3(0.0, h * 0.4 + 0.3, -d * 0.2), TownKit.toon(Color(0.78, 0.7, 0.5)))
	_window(Vector3(0.0, h * 0.55, -d * 0.5), Vector2(0.6, 0.8), 0.0, true)
	_collide(w, h, d)


func _build_mill(w: float, h: float, d: float, wall: Color, roof: Color,
		opts: Dictionary) -> void:
	_walls(w, h, d, wall)
	_timber_frame(w, h, d)
	_gable_roof(w, h, d, roof)
	_door(Vector3(0.0, 0.0, -d * 0.5))
	_window(Vector3(-w * 0.3, h * 0.6, -d * 0.5), Vector2(0.8, 0.9), 0.0, true)
	_window(Vector3(w * 0.3, h * 0.6, -d * 0.5), Vector2(0.8, 0.9), 0.0, true)
	# The wheel hangs off the +X side and dips into the pond. Its hub height is
	# handed in by BootstrapTown, which knows the terrain's water level.
	var radius: float = float(opts.get("wheel_radius", 2.4))
	var hub_y: float = float(opts.get("wheel_hub_y", h * 0.45))
	wheel = Node3D.new()
	wheel.name = "Wheel"
	wheel.position = Vector3(w * 0.5 + 0.5, hub_y, 0.0)
	wheel.rotation.z = PI * 0.5  # lay the disc into the X plane
	add_child(wheel)
	var wood: Color = Color(0.42, 0.31, 0.19)
	TownKit.part(wheel, "Hub", TownKit.cyl(0.18, 0.18, 1.1, 8), Vector3.ZERO, TownKit.toon(wood))
	for ring: int in [-1, 1]:
		TownKit.part(wheel, "Rim%d" % ring, _torus(radius - 0.16, radius, 20),
			Vector3(0.0, 0.5 * ring, 0.0), TownKit.toon(wood))
	for i in 10:
		var ang: float = TAU * float(i) / 10.0
		var spoke: MeshInstance3D = TownKit.plank(wheel, "Spoke%d" % i,
			Vector3(0.1, 0.12, radius * 2.0), Vector3.ZERO, wood.lightened(0.08))
		spoke.rotation.y = ang
		var paddle: MeshInstance3D = TownKit.plank(wheel, "Paddle%d" % i,
			Vector3(0.1, 1.1, 0.5),
			Vector3(sin(ang) * radius, 0.0, cos(ang) * radius), wood.darkened(0.12))
		paddle.rotation.y = ang
	TownKit.plank(self, "Sluice", Vector3(1.2, 0.3, d * 0.8),
		Vector3(w * 0.5 + 0.4, hub_y + radius - 0.2, 0.0), wood.darkened(0.2))
	_collide(w, h, d)


# --- Shared pieces -----------------------------------------------------------

func _walls(w: float, h: float, d: float, color: Color, y0: float = 0.0) -> void:
	TownKit.plank(self, "Walls", Vector3(w, h, d), Vector3(0.0, y0 + h * 0.5, 0.0), color)


## Exposed corner posts, a mid rail, and a pair of braces. This is what makes a
## plain box read as a timber-framed village house at 30 meters.
func _timber_frame(w: float, h: float, d: float, y0: float = 0.0) -> void:
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			TownKit.plank(self, "Corner%d_%d" % [sx, sz], Vector3(0.22, h, 0.22),
				Vector3(w * 0.5 * sx, y0 + h * 0.5, d * 0.5 * sz), BEAM)
	TownKit.plank(self, "RailFront", Vector3(w + 0.06, 0.2, 0.14),
		Vector3(0.0, y0 + h * 0.62, -d * 0.5), BEAM)
	TownKit.plank(self, "RailBack", Vector3(w + 0.06, 0.2, 0.14),
		Vector3(0.0, y0 + h * 0.62, d * 0.5), BEAM)
	TownKit.plank(self, "RailLeft", Vector3(0.14, 0.2, d + 0.06),
		Vector3(-w * 0.5, y0 + h * 0.62, 0.0), BEAM)
	TownKit.plank(self, "RailRight", Vector3(0.14, 0.2, d + 0.06),
		Vector3(w * 0.5, y0 + h * 0.62, 0.0), BEAM)
	for sx: int in [-1, 1]:
		var brace: MeshInstance3D = TownKit.plank(self, "Brace%d" % sx,
			Vector3(0.16, h * 0.62, 0.12),
			Vector3(w * 0.34 * sx, y0 + h * 0.32, -d * 0.5 - 0.01), BEAM)
		brace.rotation.z = 0.42 * sx


func _timber_frame_upper(w: float, y0: float, h: float, d: float) -> void:
	for sx: int in [-1, 1]:
		for sz: int in [-1, 1]:
			TownKit.plank(self, "UpCorner%d_%d" % [sx, sz], Vector3(0.2, h - y0, 0.2),
				Vector3(w * 0.5 * sx, y0 + (h - y0) * 0.5, d * 0.5 * sz), BEAM)


func _gable_roof(w: float, h: float, d: float, color: Color) -> void:
	var over: float = 0.65
	var roof_h: float = maxf(1.3, minf(w, d) * 0.42)
	var ridge_along_z: bool = d >= w
	var mesh_size: Vector3 = Vector3(w + over, roof_h, d + over) if ridge_along_z \
		else Vector3(d + over, roof_h, w + over)
	var yaw: float = 0.0 if ridge_along_z else PI * 0.5
	TownKit.part(self, "Roof", TownKit.prism(mesh_size), Vector3(0.0, h + roof_h * 0.5, 0.0),
		TownKit.toon(color), Vector3(0.0, yaw, 0.0))
	# Ridge cap + eave boards: the silhouette details that stop a roof looking
	# like a wedge of geometry. The eaves run along the roof's two LOW edges,
	# which sit across the ridge.
	var ridge_len: float = (d + over) if ridge_along_z else (w + over)
	var cap: MeshInstance3D = TownKit.plank(self, "RidgeCap", Vector3(0.28, 0.16, ridge_len),
		Vector3(0.0, h + roof_h + 0.02, 0.0), color.darkened(0.18))
	cap.rotation.y = yaw
	for s: int in [-1, 1]:
		var eave_size: Vector3 = Vector3(0.18, 0.16, d + over) if ridge_along_z \
			else Vector3(w + over, 0.16, 0.18)
		var eave_pos: Vector3 = Vector3((w + over) * 0.5 * s, h + 0.02, 0.0) if ridge_along_z \
			else Vector3(0.0, h + 0.02, (d + over) * 0.5 * s)
		TownKit.plank(self, "Eave%d" % s, eave_size, eave_pos, BEAM)


func _dormer(w: float, h: float, d: float, wall: Color, roof: Color) -> void:
	var dormer: Node3D = Node3D.new()
	dormer.name = "Dormer"
	dormer.position = Vector3(0.0, h + 0.35, -d * 0.28)
	add_child(dormer)
	TownKit.plank(dormer, "Box", Vector3(1.5, 1.1, 1.6), Vector3.ZERO, wall)
	TownKit.part(dormer, "Cap", TownKit.prism(Vector3(1.8, 0.8, 1.8)), Vector3(0.0, 0.95, 0.0),
		TownKit.toon(roof), Vector3(0.0, PI * 0.5, 0.0))
	TownKit.window_pane(dormer, "Pane", Vector2(0.75, 0.7), Vector3(0.0, 0.05, -0.81))


func _door(local: Vector3, height: float = 2.0) -> void:
	var door: MeshInstance3D = TownKit.plank(self, "Door", Vector3(1.0, height, 0.16),
		local + Vector3(0.0, height * 0.5, -0.06), Color(0.36, 0.24, 0.15))
	TownKit.plank(door, "Plank", Vector3(0.08, height - 0.2, 0.06), Vector3(-0.3, 0.0, -0.08),
		Color(0.28, 0.18, 0.11))
	TownKit.plank(door, "Plank2", Vector3(0.08, height - 0.2, 0.06), Vector3(0.3, 0.0, -0.08),
		Color(0.28, 0.18, 0.11))
	TownKit.part(door, "Handle", TownKit.ball(0.07, 7, 4), Vector3(0.32, -0.05, -0.12),
		TownKit.toon(Color(0.72, 0.6, 0.28)))
	TownKit.plank(self, "DoorLintel", Vector3(1.4, 0.18, 0.4),
		local + Vector3(0.0, height + 0.1, -0.14), BEAM)


## `yaw` turns the window onto another wall, and must point the pane OUTWARD:
## 0 is the front (-Z) wall, +PI/2 the -X wall, -PI/2 the +X wall.
func _window(local: Vector3, size: Vector2, yaw: float, shutters: bool) -> void:
	var win: Node3D = Node3D.new()
	win.name = "Window"
	win.position = local
	win.rotation.y = yaw
	add_child(win)
	TownKit.plank(win, "Frame", Vector3(size.x + 0.22, size.y + 0.22, 0.14),
		Vector3(0.0, 0.0, -0.06), BEAM)
	TownKit.window_pane(win, "Pane", size, Vector3(0.0, 0.0, -0.14))
	TownKit.plank(win, "MullionV", Vector3(0.06, size.y, 0.08), Vector3(0.0, 0.0, -0.17), BEAM)
	TownKit.plank(win, "MullionH", Vector3(size.x, 0.06, 0.08), Vector3(0.0, 0.0, -0.17), BEAM)
	if shutters:
		for sx: int in [-1, 1]:
			var shutter: MeshInstance3D = TownKit.plank(win, "Shutter%d" % sx,
				Vector3(size.x * 0.55, size.y + 0.16, 0.08),
				Vector3((size.x * 0.62) * sx, 0.0, -0.24), Color(0.4, 0.5, 0.36))
			shutter.rotation.y = -0.5 * sx


func _flower_box(local: Vector3) -> void:
	var box: Node3D = Node3D.new()
	box.name = "FlowerBox"
	box.position = local
	add_child(box)
	TownKit.plank(box, "Trough", Vector3(1.1, 0.26, 0.34), Vector3.ZERO, Color(0.42, 0.3, 0.18))
	var rng: RandomNumberGenerator = TownKit.rng_for("flowers" + str(local))
	var petals: Array[Color] = [
		Color(0.86, 0.4, 0.55), Color(0.95, 0.82, 0.35), Color(0.62, 0.45, 0.82),
		Color(0.92, 0.94, 0.9),
	]
	for i in 7:
		var fx: float = -0.45 + float(i) * 0.15
		TownKit.part(box, "Stem%d" % i, TownKit.cyl(0.02, 0.02, 0.3, 5),
			Vector3(fx, 0.24, rng.randf_range(-0.08, 0.08)), TownKit.toon(Color(0.3, 0.5, 0.2)))
		TownKit.part(box, "Bloom%d" % i, TownKit.ball(0.07, 7, 4),
			Vector3(fx, 0.4, 0.0), TownKit.toon(petals[rng.randi() % petals.size()]))


func _bench(local: Vector3) -> void:
	var bench: Node3D = Node3D.new()
	bench.name = "Bench"
	bench.position = local
	add_child(bench)
	TownKit.plank(bench, "Seat", Vector3(1.9, 0.12, 0.5), Vector3(0.0, 0.45, 0.0),
		Color(0.48, 0.35, 0.21))
	TownKit.plank(bench, "Back", Vector3(1.9, 0.5, 0.1), Vector3(0.0, 0.72, 0.2),
		Color(0.48, 0.35, 0.21))
	for sx: int in [-1, 1]:
		TownKit.plank(bench, "Leg%d" % sx, Vector3(0.12, 0.45, 0.44),
			Vector3(0.8 * sx, 0.22, 0.0), Color(0.4, 0.29, 0.18))


func _rack(local: Vector3) -> void:
	var rack: Node3D = Node3D.new()
	rack.name = "ToolRack"
	rack.position = local
	add_child(rack)
	TownKit.plank(rack, "Frame", Vector3(0.16, 1.9, 0.16), Vector3.ZERO, BEAM)
	TownKit.plank(rack, "Bar", Vector3(0.12, 0.12, 1.4), Vector3(0.0, 0.85, 0.0), BEAM)
	for i in 3:
		TownKit.part(rack, "Blade%d" % i, TownKit.box(Vector3(0.07, 0.9, 0.16)),
			Vector3(0.0, 0.35, -0.5 + float(i) * 0.5), TownKit.toon(Color(0.74, 0.77, 0.8)))


func _banner(local: Vector3) -> void:
	var pole: Node3D = Node3D.new()
	pole.name = "Banner"
	pole.position = local
	add_child(pole)
	TownKit.part(pole, "Pole", TownKit.cyl(0.06, 0.06, 3.0, 8), Vector3(0.0, 1.5, 0.0),
		TownKit.toon(BEAM))
	# Bootstrap's colors: meadow green and seed gold, hung from a crossbar.
	TownKit.plank(pole, "Crossbar", Vector3(1.4, 0.07, 0.07), Vector3(0.0, 2.9, 0.0), BEAM)
	var cloth: MeshInstance3D = TownKit.plank(pole, "Cloth", Vector3(1.25, 1.5, 0.05),
		Vector3(0.0, 2.1, 0.02), Color(0.29, 0.5, 0.26))
	TownKit.plank(cloth, "Stripe", Vector3(1.25, 0.34, 0.06), Vector3(0.0, -0.2, -0.01),
		Color(0.88, 0.74, 0.32))
	swingers.append(cloth)


func _hanging_sign(text: String, local: Vector3, side: float) -> void:
	var bracket: Node3D = Node3D.new()
	bracket.name = "SignBracket"
	bracket.position = local + Vector3(1.9 * side, 0.0, 0.0)
	add_child(bracket)
	TownKit.plank(bracket, "Arm", Vector3(1.5, 0.1, 0.1), Vector3(-0.75 * side, 0.0, -0.1),
		Color(0.2, 0.2, 0.22))
	TownKit.plank(bracket, "Strut", Vector3(0.08, 0.7, 0.08), Vector3(-1.4 * side, -0.35, -0.1),
		Color(0.2, 0.2, 0.22))
	var swing: Node3D = Node3D.new()
	swing.name = "SignSwing"
	swing.position = Vector3(-0.2 * side, -0.08, -0.1)
	bracket.add_child(swing)
	for sx: int in [-1, 1]:
		TownKit.part(swing, "Chain%d" % sx, TownKit.cyl(0.02, 0.02, 0.3, 5),
			Vector3(0.42 * sx, -0.15, 0.0), TownKit.toon(Color(0.24, 0.24, 0.26)))
	var board: MeshInstance3D = TownKit.plank(swing, "Board", Vector3(1.5, 0.72, 0.09),
		Vector3(0.0, -0.66, 0.0), Color(0.46, 0.32, 0.2))
	TownKit.plank(board, "Border", Vector3(1.35, 0.58, 0.11), Vector3.ZERO, Color(0.86, 0.76, 0.5))
	for sz: int in [-1, 1]:
		var label: Label3D = Label3D.new()
		label.name = "SignText%d" % sz
		label.text = text
		label.font_size = 44
		label.pixel_size = 0.006
		label.modulate = Color(0.24, 0.16, 0.1)
		label.outline_size = 0
		label.position = Vector3(0.0, 0.0, 0.07 * sz)
		label.rotation.y = 0.0 if sz < 0 else PI
		label.double_sided = false  # back-to-back pair; see TownProps.fingerpost
		label.width = 260.0
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		board.add_child(label)
	swingers.append(swing)


func _chimney(local: Vector3, h: float, smoking: bool) -> void:
	var stack: Node3D = Node3D.new()
	stack.name = "Chimney"
	stack.position = local
	add_child(stack)
	TownKit.plank(stack, "Stack", Vector3(0.9, h + 2.4, 0.9), Vector3(0.0, (h + 2.4) * 0.5, 0.0),
		STONE.darkened(0.08))
	TownKit.plank(stack, "Crown", Vector3(1.1, 0.22, 1.1), Vector3(0.0, h + 2.5, 0.0),
		STONE.darkened(0.2))
	if smoking:
		var puff: GPUParticles3D = TownKit.smoke(14.0, 0.6, Color(0.86, 0.86, 0.88))
		puff.position = Vector3(0.0, h + 2.7, 0.0)
		stack.add_child(puff)


func _torus(inner: float, outer: float, segments: int) -> TorusMesh:
	var m: TorusMesh = TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segments
	m.ring_segments = 6
	return m


func _collide(w: float, h: float, d: float) -> void:
	TownKit.collide_box(self, Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0))
