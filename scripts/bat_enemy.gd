extends CharacterBody3D

## A horde bat. Vampire-Survivors style: no pathfinding, no states - it simply
## beelines at the player forever and crowds in with the rest of the swarm.
##
## Separation comes free from move_and_slide(): bats are physics bodies, so
## they shoulder past each other instead of stacking into one point.
##
## Dies to anything that calls take_hit(): the finger gun bolt and both melee
## stances do.

const TEXTURE := "res://assets/chonchon/chonchon-texture.png"
## Preloaded rather than referenced by class_name: global class registration
## lives in the editor's scan cache, which headless tool runs never rebuild.
const BLOOD := preload("res://scripts/blood.gd")

@export_group("AI")
@export var move_speed: float = 4.6
## Aim for a point above the player's origin, so they swarm at head height.
@export var hover_height: float = 0.9
@export var stop_distance: float = 0.8
@export var acceleration: float = 14.0
@export var turn_rate: float = 9.0

@export_group("Combat")
## 1 = one shot, one kill. Every damage source in the game deals 1 (the bolt's
## `damage` and the arms' `melee_damage`), so any hit is now fatal and the
## non-fatal branch of take_hit() - and with it `hurt_animation` - never runs.
@export var max_health: int = 1

@export_group("Animation")
@export var idle_animation: StringName = &"Armature|idle"
@export var hurt_animation: StringName = &"Armature|hit reaction"
@export var death_animation: StringName = &"Armature|death"

@export_group("Blood")
@export var blood_count: int = 26
@export var blood_speed: float = 5.0
@export var blood_color: Color = Color(0.55, 0.02, 0.04)

signal died

var _anim: AnimationPlayer
var _target: Node3D
var _health: int
var _dead: bool = false

func _ready() -> void:
	_health = max_health
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # it flies, it doesn't walk
	_bind_texture()
	_target = get_tree().get_first_node_in_group("player") as Node3D
	_anim = _find_anim(self)
	if _anim == null:
		return
	_anim.animation_finished.connect(_on_anim_finished)
	var a := _anim.get_animation(idle_animation)
	if a:
		# FBX animations import with looping off.
		a.loop_mode = Animation.LOOP_LINEAR
		# Desync the flap so a swarm doesn't beat in unison.
		_anim.play(idle_animation)
		_anim.seek(randf() * a.length, true)

func _physics_process(delta: float) -> void:
	if _dead:
		velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		move_and_slide()
		return
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node3D
		return

	var goal := _target.global_position + Vector3.UP * hover_height
	var to := goal - global_position
	var desired := Vector3.ZERO
	if to.length() > stop_distance:
		desired = to.normalized() * move_speed
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()

	# Turn to face the player; the model's front is +Z.
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() > 0.0001:
		var want := atan2(flat.x, flat.z)
		rotation.y = lerp_angle(rotation.y, want, clampf(delta * turn_rate, 0.0, 1.0))

## Returns true if the hit landed. `at` is the world-space impact point.
func take_hit(amount: int = 1, at: Vector3 = Vector3.INF, _from: Vector3 = Vector3.ZERO) -> bool:
	if _dead:
		return false
	var point := at if at != Vector3.INF else global_position
	_health -= amount
	if _health > 0:
		_spray(point, 1.0)
		if _anim and _anim.has_animation(hurt_animation):
			_anim.play(hurt_animation)
		return true
	_die(point)
	return true

func _die(at: Vector3) -> void:
	_dead = true
	died.emit()
	_enable_collision(false)
	_spray(at, 2.0)

	var wait := 1.0
	if _anim and _anim.has_animation(death_animation):
		var d := _anim.get_animation(death_animation)
		d.loop_mode = Animation.LOOP_NONE
		_anim.play(death_animation)
		wait = d.length
	await get_tree().create_timer(wait).timeout
	if is_instance_valid(self):
		queue_free()

## The hit reaction is a one-shot; without this it freezes on its last frame.
func _on_anim_finished(which: StringName) -> void:
	if _dead:
		return
	if which == hurt_animation and _anim:
		_anim.play(idle_animation)

func _enable_collision(on: bool) -> void:
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", not on)

## A one-shot burst of blood, parented to the level so it outlives the corpse.
## The actual burst lives in blood.gd, shared with the watcher.
func _spray(at: Vector3, scale_mult: float) -> void:
	BLOOD.spray(get_parent(), at, blood_count, blood_speed, blood_color, scale_mult)

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

## The FBX import drops the texture link, so re-bind it on the shared mesh.
## Guarded by a meta flag, so this costs nothing after the first bat.
func _bind_texture() -> void:
	for mi: MeshInstance3D in _all_meshes(self):
		var mesh: Mesh = mi.mesh
		if mesh is ArrayMesh and not mesh.has_meta(&"chon_bound"):
			mesh.set_meta(&"chon_bound", true)
			var m := StandardMaterial3D.new()
			m.resource_name = "ChonChon"
			m.albedo_texture = load(TEXTURE)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.roughness = 1.0
			m.metallic = 0.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			for s in range(mesh.get_surface_count()):
				(mesh as ArrayMesh).surface_set_material(s, m)

func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
