extends Node3D

## Vampire-Survivors style horde spawner.
##
## Bats appear on a ring around the player - far enough to be off-screen behind
## you, close enough to arrive quickly - and beeline in. The interval shrinks
## and the batch size grows over time, so pressure ramps rather than starting
## overwhelming.
##
## A hard cap on live enemies keeps the framerate sane: these are skinned
## meshes with their own AnimationPlayer, not sprites, so a few dozen is a very
## different cost to a few hundred.

@export var bat_scene: PackedScene
@export var enabled: bool = true

@export_group("Rate")
@export var first_wave_delay: float = 2.0
@export var start_interval: float = 1.6
@export var min_interval: float = 0.35
## Seconds to ramp from start_interval down to min_interval.
@export var ramp_seconds: float = 120.0
@export var start_batch: int = 2
@export var max_batch: int = 7
## Seconds of survival per extra bat in a batch.
@export var batch_every: float = 22.0
@export var max_alive: int = 45

@export_group("Placement")
@export var spawn_radius: float = 26.0
@export var radius_jitter: float = 7.0
@export var hover_min: float = 1.0
@export var hover_max: float = 3.6
## Tries this many angles to avoid spawning inside a wall or crate.
@export var placement_attempts: int = 8

var _elapsed: float = 0.0
var _timer: float = 0.0

func _process(delta: float) -> void:
	if not enabled or bat_scene == null:
		return
	_elapsed += delta
	if _elapsed < first_wave_delay:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = current_interval()
	_spawn_wave()

func current_interval() -> float:
	var t := clampf(_elapsed / maxf(ramp_seconds, 0.001), 0.0, 1.0)
	return lerpf(start_interval, min_interval, t)

func current_batch() -> int:
	return clampi(start_batch + int(_elapsed / maxf(batch_every, 0.001)), 1, max_batch)

## Counts "bats", not "enemies". Hand-placed watchers are also in "enemies", and
## counting those would let a few camps eat the whole horde budget.
func alive_count() -> int:
	return get_tree().get_nodes_in_group("bats").size()

func _spawn_wave() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var room := max_alive - alive_count()
	if room <= 0:
		return
	for i in range(mini(room, current_batch())):
		spawn_one(player)

## Spawns a single bat on the ring. Returns it, or null if no clear spot.
func spawn_one(player: Node3D) -> Node3D:
	var space := get_world_3d().direct_space_state
	for attempt in range(placement_attempts):
		var angle := randf() * TAU
		var r := spawn_radius + randf_range(-radius_jitter, radius_jitter)
		var pos := player.global_position + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		pos.y = player.global_position.y + randf_range(hover_min, hover_max)

		# Reject points inside geometry, or the bat spawns stuck in a crate.
		var q := PhysicsPointQueryParameters3D.new()
		q.position = pos
		if not space.intersect_point(q, 1).is_empty():
			continue

		var bat := bat_scene.instantiate() as Node3D
		var host := get_parent()
		if host == null:
			host = self
		host.add_child(bat)
		bat.global_position = pos
		return bat
	return null
