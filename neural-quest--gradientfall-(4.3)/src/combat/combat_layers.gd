class_name CombatLayers
extends RefCounted
## Central physics-layer bit values for combat, so hitboxes, bodies, and
## projectiles never disagree about who can touch whom.
##
## Godot layer N has bit value (1 << (N-1)). The player body is authored on
## layer 2 in player.tscn (value 2) and the terrain is on the default layer 1
## (value 1); everything here is derived from those two fixed facts.

const WORLD: int = 1        # layer 1 — terrain / static environment
const PLAYER: int = 1 << 1  # layer 2 — Kern's body (matches player.tscn)
const ENEMY: int = 1 << 2   # layer 3 — monster bodies
