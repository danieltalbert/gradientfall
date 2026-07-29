class_name NpcActor
extends StaticBody3D
## One villager standing in the world, built from an approved ContentDB entry.
##
## The runtime never hardcodes authored content (ARCHITECTURE.md): this node is
## handed the whole npc dictionary and takes its name, role, personality, and
## every spoken line from it. BootstrapTown supplies only the things the data
## does not know — where the villager stands, which way they face, and the
## `accent` that picks their props out of the description.
##
## Actors join the "npc" group so NpcInteractor can find the nearest one
## without any direct wiring, exactly as BitLandmark does for the companion.

const NOTICE_RANGE: float = 9.0        ## starts watching Kern
const NAMEPLATE_RANGE: float = 14.0    ## floating name fades in
const TURN_SPEED: float = 5.0
const WALK_SPEED: float = 1.15
const IDLE_LINES_PER_CHAT: int = 2

var npc_id: String = ""
var display_name: String = ""
var role: String = ""

var _dialogue: Dictionary = {}
var _bags: Dictionary = {}             ## pool name -> remaining shuffled indices
var _visual: NpcVisual
var _label: Label3D
var _home: Vector3 = Vector3.ZERO
var _home_yaw: float = 0.0
var _wander_radius: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _wander_wait: float = 0.0
var _terrain: Node
var _player: Node3D
var _talking: bool = false


func configure(entry: Dictionary, accent: String, home: Vector3, yaw: float,
		terrain: Node, wander_radius: float = 0.0) -> void:
	npc_id = str(entry.get("id", ""))
	display_name = str(entry.get("name", "Villager"))
	role = str(entry.get("role", "flavor"))
	_dialogue = entry.get("dialogue", {}) as Dictionary
	_home = home
	_home_yaw = yaw
	_terrain = terrain
	_wander_radius = wander_radius
	_wander_target = home
	name = "Npc_" + npc_id.trim_prefix("npc_")

	position = home
	rotation.y = yaw

	_visual = NpcVisual.new()
	_visual.name = "Visual"
	add_child(_visual)
	_visual.build(role, accent, entry.get("personality", []) as Array, npc_id)

	# A soft capsule so Kern bumps into people instead of walking through them.
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = 0.32
	shape.height = 1.7
	var col: CollisionShape3D = CollisionShape3D.new()
	col.name = "Body"
	col.shape = shape
	col.position = Vector3(0.0, 0.85, 0.0)
	add_child(col)

	_label = Label3D.new()
	_label.name = "Nameplate"
	_label.text = display_name
	_label.font_size = 40
	_label.pixel_size = 0.0034
	_label.outline_size = 12
	_label.modulate = Color(1.0, 0.97, 0.9, 0.0)
	_label.outline_modulate = Color(0.05, 0.06, 0.08, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.position = Vector3(0.0, _visual.eye_height + 0.42, 0.0)
	add_child(_label)

	add_to_group(&"npc")


func _ready() -> void:
	if _player == null:
		var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			_player = players[0] as Node3D
	EventBus.player_spawned.connect(_on_player_spawned)


func _on_player_spawned(player: Node3D) -> void:
	_player = player


func _process(delta: float) -> void:
	if _player == null:
		return
	var to_player: Vector3 = _player.global_position - global_position
	var dist: float = to_player.length()

	var fade: float = clampf(1.0 - (dist - 4.0) / (NAMEPLATE_RANGE - 4.0), 0.0, 1.0)
	if _talking:
		fade = 1.0
	_label.modulate.a = fade
	_label.outline_modulate.a = fade * 0.85

	if _talking or dist < NOTICE_RANGE:
		# Turn to face Kern — being looked at is most of what makes a villager
		# feel like a person rather than a prop. Model forward is -Z (Godot
		# convention), hence the negations, same as player.gd's turn.
		var want: float = atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, TURN_SPEED * delta))
	else:
		_tick_wander(delta)


func _tick_wander(delta: float) -> void:
	if _wander_radius <= 0.0:
		rotation.y = lerp_angle(rotation.y, _home_yaw, minf(1.0, TURN_SPEED * 0.5 * delta))
		return
	_wander_wait -= delta
	var flat_target: Vector2 = Vector2(_wander_target.x, _wander_target.z)
	var flat_here: Vector2 = Vector2(global_position.x, global_position.z)
	if flat_here.distance_to(flat_target) < 0.4:
		if _wander_wait <= 0.0:
			var ang: float = randf() * TAU
			var r: float = sqrt(randf()) * _wander_radius
			_wander_target = _home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			_wander_wait = randf_range(1.5, 4.0)
		return
	var step: Vector2 = (flat_target - flat_here).normalized() * WALK_SPEED * delta
	var next: Vector2 = flat_here + step
	var y: float = _home.y
	if _terrain != null and _terrain.has_method("get_height"):
		y = _terrain.get_height(next.x, next.y)
	global_position = Vector3(next.x, y, next.y)
	rotation.y = lerp_angle(rotation.y, atan2(-step.x, -step.y), minf(1.0, TURN_SPEED * delta))


# --- Conversation ------------------------------------------------------------

func interact_prompt() -> String:
	return "Talk to %s" % display_name


## The whole exchange, assembled fresh each time: a greeting, a couple of the
## villager's idle remarks, and their farewell if the entry has one. Lines are
## drawn from shuffled bags so a short pool never repeats back to back.
func conversation() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var greeting: String = _draw("greeting")
	if greeting != "":
		lines.append(greeting)
	for i in IDLE_LINES_PER_CHAT:
		var idle: String = _draw("idle")
		if idle != "":
			lines.append(idle)
	var farewell: String = _draw("farewell")
	if farewell != "":
		lines.append(farewell)
	if lines.is_empty():
		lines.append("...")
	return lines


func begin_talk() -> void:
	_talking = true
	if not GameState.has_flag(met_flag()):
		GameState.set_flag(met_flag())
		EventBus.npc_met.emit(npc_id, display_name)


func end_talk() -> void:
	_talking = false


func met_flag() -> String:
	return "met_" + npc_id


func _draw(pool_name: String) -> String:
	var pool: Array = _dialogue.get(pool_name, []) as Array
	if pool.is_empty():
		return ""
	var bag: Array = _bags.get(pool_name, []) as Array
	if bag.is_empty():
		for i in pool.size():
			bag.append(i)
		bag.shuffle()
		_bags[pool_name] = bag
	var index: int = int(bag.pop_back())
	return str(pool[index])
