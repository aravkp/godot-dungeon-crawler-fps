extends StaticBody3D

## Scenery the player can smash: crates, barrels and the corridor doors.
##
## It satisfies the same damage contract as the enemies -
##   take_hit(amount, at, from) -> bool
## - so nothing that deals damage needs to know the difference between a bat and
## a barrel. arms.gd's melee ray already calls it on whatever it hits, so a swing
## that lands on a crate needs no special case anywhere.
##
## Built entirely in code by tools/build_corridors.gd, which parents the kit
## model under `art_path` and sizes the collider from the piece's measured
## bounds. There is no .tscn: a breakable is a StaticBody3D + this script + one
## box, and the builder is the only thing that makes them.
##
## A door is the same object as a crate with more `hits` and a collider that
## happens to fill a doorway, which is why blocking the corridor needs no
## separate script.

signal broken

## Hits REMAINING - it is decremented in place. Deliberately not copied into a
## private field at _ready(): the builder sets exported properties on a node it
## created, and add_child() runs _ready() immediately, so anything cached there
## would be captured before the override lands (the same trap pickup.gd hits
## with its bob origin).
##
## ONE by default: scenery comes apart on the first swing that lands. The
## multi-hit path below still works and a level can still ask for it, but nothing
## in the game does any more - so the jolt is now only reachable by setting this
## above 1.
@export var hits: int = 1
## Chunk colour. Wood for crates and doors, grey for anything stone.
@export var debris_color: Color = Color(0.52, 0.36, 0.19)
@export var debris_count: int = 16
@export var chunk_speed: float = 4.5
## The visual, which is jolted on a non-fatal hit. Everything else about the node
## stays put - the collider must not move, or a half-smashed crate stops lining
## up with the thing you are aiming at.
@export var art_path: NodePath = ^"Art"
## How far the model kicks back when hit, and how fast it returns.
@export var jolt_distance: float = 0.07
@export var jolt_recover: float = 9.0

const DEBRIS := preload("res://scripts/debris.gd")
const SHATTER := preload("res://scripts/shatter.gd")

var _dead: bool = false
var _art: Node3D
var _art_home: Vector3 = Vector3.ZERO
var _jolt: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("breakables", true)
	_art = get_node_or_null(art_path) as Node3D
	if _art:
		_art_home = _art.position
	# Nothing to do until something hits it.
	set_process(false)

func _process(delta: float) -> void:
	_jolt = _jolt.lerp(Vector3.ZERO, minf(1.0, jolt_recover * delta))
	if _art:
		_art.position = _art_home + _jolt
	if _jolt.length_squared() < 1.0e-6:
		_jolt = Vector3.ZERO
		if _art:
			_art.position = _art_home
		set_process(false)

## Returns whether the hit registered, matching bat_enemy.gd / watcher_enemy.gd:
## false only once the thing is already gone.
func take_hit(amount: int = 1, at: Vector3 = Vector3.INF,
		from: Vector3 = Vector3.ZERO) -> bool:
	if _dead:
		return false
	var point := at if at != Vector3.INF else global_position
	hits -= amount
	if hits > 0:
		DEBRIS.burst(get_parent(), point, debris_count, chunk_speed,
			debris_color, 0.45)
		if from != Vector3.ZERO:
			# In the node's own space, so a rotated crate still kicks away from
			# the player rather than along some world axis.
			_jolt = global_transform.basis.inverse() * from.normalized() * jolt_distance
			set_process(true)
		return true
	_shatter(point, from)
	return true

func _shatter(at: Vector3, from: Vector3) -> void:
	_dead = true
	# Both are parented to the level, not to this node, so they outlive the prop
	# they came out of - it is freed on this same frame.
	#
	# The particle burst is the impact; the chunks are the thing coming apart.
	# Kept smaller than it was now that it is an accent rather than the whole
	# effect.
	DEBRIS.burst(get_parent(), at, debris_count, chunk_speed, debris_color, 0.9)
	_break_apart(from)
	broken.emit()

## Hands the collider's own box to shatter.gd, so the pile that lands matches the
## shape that was standing there - a door comes apart into planks and a crate
## into cubes without either being told which it is.
func _break_apart(from: Vector3) -> void:
	var cs := get_node_or_null(^"Collision") as CollisionShape3D
	if cs == null or not (cs.shape is BoxShape3D):
		return
	var box := (cs.shape as BoxShape3D).size
	var centre := global_transform * cs.position
	var art_mesh: MeshInstance3D = null
	if _art:
		for n in _art.find_children("*", "MeshInstance3D", true, false):
			art_mesh = n as MeshInstance3D
			break
	SHATTER.burst(get_parent(), Transform3D(global_transform.basis, centre),
		box, art_mesh, from)
	# Stop being a target this frame. The interaction ray and the melee ray both
	# run before the free lands, and a queued-but-alive collider still answers
	# them.
	collision_layer = 0
	queue_free()
