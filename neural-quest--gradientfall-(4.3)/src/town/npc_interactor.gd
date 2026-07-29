class_name NpcInteractor
extends Node
## Kern's side of a conversation: finds the villager he is standing in front
## of, opens the exchange on `interact`, walks it line by line, and closes it
## when it runs out or he wanders off.
##
## It owns the conversation state machine and speaks only through EventBus, so
## the dialogue box is a pure listener and nothing in the world needs a
## reference to the UI (ARCHITECTURE.md: EventBus carries cross-system
## notifications without hard scene dependencies).

const REACH: float = 3.4          ## how close Kern must be to get a prompt
const BREAK_RANGE: float = 6.0    ## walking this far away ends the chat
const FACING_DOT: float = -0.15   ## the villager must be roughly ahead of him

var _player: Node3D
var _target: NpcActor             ## who the prompt is currently offering
var _talking: NpcActor
var _lines: PackedStringArray = PackedStringArray()
var _index: int = 0
var _revealed: bool = true


func setup(player: Node3D) -> void:
	_player = player


func _ready() -> void:
	EventBus.dialogue_line_revealed.connect(_on_line_revealed)


func _process(_delta: float) -> void:
	if _player == null:
		return
	if _talking != null:
		if _player.global_position.distance_to(_talking.global_position) > BREAK_RANGE:
			_end()
	else:
		_refresh_target()
	if Input.is_action_just_pressed(&"interact"):
		_press()


func _refresh_target(force_clear: bool = false) -> void:
	var best: NpcActor = null
	if not force_clear:
		var best_dist: float = REACH
		var forward: Vector3 = _look_direction()
		for node: Node in get_tree().get_nodes_in_group(&"npc"):
			var npc: NpcActor = node as NpcActor
			if npc == null:
				continue
			var to_npc: Vector3 = npc.global_position - _player.global_position
			to_npc.y = 0.0
			var dist: float = to_npc.length()
			if dist > best_dist:
				continue
			# The villager is ahead of Kern, or he's close enough not to care.
			if dist > 1.4 and forward.dot(to_npc.normalized()) < FACING_DOT:
				continue
			best = npc
			best_dist = dist
	if best == _target:
		return
	_target = best
	if _target == null:
		EventBus.interact_target_changed.emit("", "")
	else:
		EventBus.interact_target_changed.emit(_target.npc_id, _target.interact_prompt())


## "Ahead" means ahead of the CAMERA, not of the body: player.gd turns Kern's
## Visual child toward travel and leaves the CharacterBody3D's own basis where
## it spawned, so the body cannot answer this question. The camera can, and in
## third person it is also the honest one — you talk to whoever you are looking
## at.
func _look_direction() -> Vector3:
	var rig: Node3D = _player.get_node_or_null("CameraRig") as Node3D
	var source: Node3D = rig if rig != null else _player
	var forward: Vector3 = -source.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD


func _press() -> void:
	if _talking != null:
		if not _revealed:
			# First press finishes the typewriter, second press turns the page.
			EventBus.dialogue_skip_requested.emit()
			return
		_advance()
	elif _target != null:
		_start(_target)


func _start(npc: NpcActor) -> void:
	_talking = npc
	_lines = npc.conversation()
	_index = 0
	npc.begin_talk()
	_refresh_target(true)
	EventBus.dialogue_started.emit(npc.npc_id, npc.display_name)
	_speak()


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_end()
		return
	_speak()


func _speak() -> void:
	_revealed = false
	EventBus.dialogue_line.emit(_talking.npc_id, _lines[_index])


func _end() -> void:
	var npc: NpcActor = _talking
	_talking = null
	_lines = PackedStringArray()
	_index = 0
	_revealed = true
	if npc != null:
		npc.end_talk()
		EventBus.dialogue_ended.emit(npc.npc_id)


func _on_line_revealed(_npc_id: String) -> void:
	_revealed = true
