class_name InputSetup
extends RefCounted
## Registers gameplay input actions in code, idempotently, at player spawn.
##
## Deliberately NOT defined in project.godot: hand-serializing InputEvent
## Object(...) blobs is the one part of the project file a no-Godot
## environment can't statically verify, while plain GDScript is fully
## lint-checkable. Also consistent with the project's generated-in-code rule.
## Keyboard+mouse and gamepad are both bound here.

static var _done: bool = false


static func ensure() -> void:
	if _done:
		return
	_done = true
	# Movement — WASD + left stick.
	_key(&"move_forward", KEY_W)
	_key(&"move_back", KEY_S)
	_key(&"move_left", KEY_A)
	_key(&"move_right", KEY_D)
	_pad_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_pad_axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0)
	_pad_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_pad_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	# Camera — right stick (mouse is handled as relative motion, no action).
	_pad_axis(&"cam_up", JOY_AXIS_RIGHT_Y, -1.0)
	_pad_axis(&"cam_down", JOY_AXIS_RIGHT_Y, 1.0)
	_pad_axis(&"cam_left", JOY_AXIS_RIGHT_X, -1.0)
	_pad_axis(&"cam_right", JOY_AXIS_RIGHT_X, 1.0)
	# Actions.
	_key(&"jump", KEY_SPACE)
	_pad_button(&"jump", JOY_BUTTON_A)
	_key(&"sprint", KEY_SHIFT)
	_pad_button(&"sprint", JOY_BUTTON_LEFT_STICK)
	# Combat (milestone 6).
	_mouse(&"attack", MOUSE_BUTTON_LEFT)
	_pad_button(&"attack", JOY_BUTTON_X)
	_mouse(&"block", MOUSE_BUTTON_RIGHT)
	_pad_button(&"block", JOY_BUTTON_RIGHT_SHOULDER)
	_key(&"dodge", KEY_CTRL)
	_pad_button(&"dodge", JOY_BUTTON_B)
	_key(&"special", KEY_Q)
	_pad_button(&"special", JOY_BUTTON_Y)
	# Knowledge charge (milestone 7) — answering the in-combat question. Number
	# row + numpad on keyboard; the d-pad reads clockwise from up on a gamepad,
	# so the four choices map to four directions you never have to look for.
	_key(&"quiz_choice_1", KEY_1)
	_key(&"quiz_choice_1", KEY_KP_1)
	_pad_button(&"quiz_choice_1", JOY_BUTTON_DPAD_UP)
	_key(&"quiz_choice_2", KEY_2)
	_key(&"quiz_choice_2", KEY_KP_2)
	_pad_button(&"quiz_choice_2", JOY_BUTTON_DPAD_RIGHT)
	_key(&"quiz_choice_3", KEY_3)
	_key(&"quiz_choice_3", KEY_KP_3)
	_pad_button(&"quiz_choice_3", JOY_BUTTON_DPAD_DOWN)
	_key(&"quiz_choice_4", KEY_4)
	_key(&"quiz_choice_4", KEY_KP_4)
	_pad_button(&"quiz_choice_4", JOY_BUTTON_DPAD_LEFT)
	# Dev-only: fill the focus meter (F) / force a question outside a fight (G).
	_key(&"debug_charge", KEY_F)
	_key(&"debug_quiz", KEY_G)


static func _action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


static func _key(action: StringName, key: Key) -> void:
	_action(action)
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


static func _mouse(action: StringName, button: MouseButton) -> void:
	_action(action)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


static func _pad_button(action: StringName, button: JoyButton) -> void:
	_action(action)
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


static func _pad_axis(action: StringName, axis: JoyAxis, direction: float) -> void:
	_action(action)
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = direction
	InputMap.action_add_event(action, ev)
