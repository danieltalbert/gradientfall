class_name Health
extends Node
## A life pool measured in hearts (halves allowed — monsters carry 1.5, 2.0…).
##
## Reused by Kern and every monster. Damage is refused while dead or during a
## brief post-hit invulnerability window, so a single sword arc or one boar
## charge can't multi-hit in the same frame. The owner decides what a "hit"
## looks like (flash, knockback, dissolve); Health only tracks the number and
## fires signals.

signal changed(current: float, max_hearts: float)
signal damaged(amount: float, from_position: Vector3)
signal died()

@export var invuln_after_hit: float = 0.0  ## seconds of i-frames after a hit

var max_hearts: float = 3.0
var current: float = 3.0

var _invuln_left: float = 0.0
var _external_invuln: bool = false


func setup(max_value: float, start_full: bool = true) -> void:
	max_hearts = maxf(0.5, max_value)
	current = max_hearts if start_full else clampf(current, 0.0, max_hearts)
	changed.emit(current, max_hearts)


func _process(delta: float) -> void:
	if _invuln_left > 0.0:
		_invuln_left = maxf(0.0, _invuln_left - delta)


## Returns true if the blow actually landed (not dead / not invulnerable).
func apply(amount: float, from_position: Vector3 = Vector3.ZERO) -> bool:
	if is_dead() or is_invulnerable() or amount <= 0.0:
		return false
	current = maxf(0.0, current - amount)
	_invuln_left = invuln_after_hit
	changed.emit(current, max_hearts)
	damaged.emit(amount, from_position)
	if current <= 0.0:
		died.emit()
	return true


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	current = minf(max_hearts, current + amount)
	changed.emit(current, max_hearts)


func refill() -> void:
	current = max_hearts
	changed.emit(current, max_hearts)


func fraction() -> float:
	return current / max_hearts if max_hearts > 0.0 else 0.0


func is_dead() -> bool:
	return current <= 0.0


func is_invulnerable() -> bool:
	return _invuln_left > 0.0 or _external_invuln


## Timed invulnerability (reform grace, cutscenes). Extends, never shortens.
func grant_iframes(seconds: float) -> void:
	_invuln_left = maxf(_invuln_left, seconds)


## Dodge i-frames and the like: the owner holds invulnerability open while true.
func set_external_invuln(active: bool) -> void:
	_external_invuln = active
