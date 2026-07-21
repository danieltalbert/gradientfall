class_name BitLandmark
extends Node3D
## A named place Bit will notice and eagerly name the first time Kern wanders
## near it. Landmarks add themselves to the "bit_landmark" group so the
## companion can scan for them without any direct wiring; MeadowLandmarks
## (or any region builder) spawns and configures them.
##
## Naming is remembered in GameState.flags ("bit_named_<id>"), which is part of
## the already-serialized save shape — so it survives a save without any change
## to the save format. These markers double as canonical anchor points for the
## real POI props a later milestone will drop here.

var landmark_id: String = ""
var display_name: String = ""
var notice_radius: float = 24.0
var bit_sense: bool = false
var lines: Array[String] = []


func configure(id: String, name_text: String, radius: float,
		line_pool: Array[String], senses: bool = false) -> void:
	landmark_id = id
	display_name = name_text
	notice_radius = radius
	lines = line_pool
	bit_sense = senses


func _ready() -> void:
	add_to_group(&"bit_landmark")


func named_flag() -> String:
	return "bit_named_" + landmark_id


func pick_line() -> String:
	if lines.is_empty():
		return "That's %s! I'd know it anywhere." % display_name
	return lines[randi() % lines.size()]
