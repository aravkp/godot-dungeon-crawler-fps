extends CharacterBody3D

## "Watcher of the Hollow Eye" - a Zelda-hobgoblin style guard.
##
## Unlike the bat, this one is not horde fodder. Watchers are placed by hand in
## trios around a camp, stand guard until one of them spots the player, and then
## the whole trio charges together and beats on you in melee. Three hits kill.
##
## Squad alerting is deliberately structural rather than a manager: every
## watcher in a trio is a sibling under one Camp_NN node, so waking the group is
## just "tell my siblings". Placement therefore defines the squad, and there is
## nothing to keep in sync.
##
## ANIMATION: the FBX ships ONE 15.83s take called "all" with every motion baked
## end to end - no clip splits. Rather than surgically slicing the resource,
## playback is driven by seeking within that single take and watching the
## playhead; see CLIPS and _play_clip(). Retiming is then just editing numbers.

signal died

## Preloaded rather than referenced by class_name: global class registration
## lives in the editor's scan cache, which headless tool runs never rebuild.
const BLOOD := preload("res://scripts/blood.gd")
const RAGDOLL := preload("res://scripts/ragdoll.gd")

const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_ATTACK := "attack"
const CLIP_HURT := "hurt"
const CLIP_DEATH := "death"

## start, end (seconds into "all"). The take is CONCATENATED segments, each one
## returning to the same rest pose - the rest pose recurs at 9.70, 11.60 and
## 13.40, and those are the seams. Ranges were measured with
## tools/_probe_watcher_take.gd (per-sample bone motion, foot separation and
## mace-hand height) and read back off a contact sheet:
##
##   0.00-2.00   idle, mace shouldered
##   2.05-8.20   wind-up into an overhead slam, mace bottoming out at 5.00,
##               then a long recovery that swings the mace back up
##   8.24-9.56   the walk cycle - the only span where bone motion is a steady
##               4-6 units/sample instead of 20-60, and the only one where the
##               feet actually alternate
##   9.75-11.55  a lunging thrust (unused)
##   11.70-13.35 a leaping kick (unused; its landing crouch stands in for HURT)
##   13.50-15.80 the collapse
##
## CLIP_WALK used to be [5.90, 8.00], which is the slam's recovery arc, not
## walking - so an alerted watcher chased you while apparently swinging its mace
## over and over. If these are ever re-measured, re-run the probe rather than
## nudging: adjacent segments here look plausible and are not.
const CLIPS := {
	CLIP_IDLE: [0.00, 2.00],
	CLIP_WALK: [8.24, 9.56],
	CLIP_ATTACK: [4.00, 5.60],
	CLIP_HURT: [12.58, 13.12],
	CLIP_DEATH: [13.50, 15.80],
}

## Where inside the attack clip the mace actually lands. The hand reaches its
## lowest point at 5.00s absolute, which is 1.00s into the clip.
const ATTACK_HIT_AT := 1.00

enum State { GUARD, CHASE, ATTACK, HURT, DEAD }

@export_group("Combat")
## Three hits, like a hobgoblin. Every damage source in the game deals 1.
@export var max_health: int = 3
@export var attack_damage: int = 1
## Close enough to stop advancing and start swinging.
@export var attack_range: float = 2.3
## How far the swing actually reaches when it connects - slightly longer than
## attack_range so a player backing off slowly still gets clipped.
@export var attack_reach: float = 3.0
## Total arc, in degrees, the player must be inside before a swing is committed
## to. The swing itself only connects within 70 degrees of facing (see
## _land_hit), so starting one wider than this is a swing that cannot land.
@export var attack_aim_angle: float = 60.0
@export var attack_cooldown: float = 0.55

@export_group("Senses")
@export var sight_range: float = 24.0
## Total cone width in degrees, centred on facing.
@export var sight_angle: float = 120.0
## Inside this radius they notice regardless of facing - walking up behind one
## and standing there should still wake it.
@export var alert_radius: float = 5.0
## Once alerted they stay alerted; this is only how often the cone is tested.
@export var sight_interval: float = 0.2

@export_group("Corpse")
## Go limp and let physics do the falling, instead of playing CLIP_DEATH.
## Turning this off falls back to the baked death animation.
@export var use_ragdoll: bool = true
## Shove the killing blow gives the corpse, applied to whichever bone was hit.
@export var ragdoll_impulse: float = 7.0
## How long physics is given to bring the ragdoll to rest before it counts as
## having landed. Ragdoll only.
@export var ragdoll_settle: float = 1.2
## How long the body lies there once it has landed.
@export var corpse_linger: float = 1.4
## Then it sinks through the floor instead of blinking out of existence.
@export var corpse_sink_speed: float = 0.7
## A ragdoll sinks by having its collision mask cleared and falling instead, so
## its rate is a fraction of gravity rather than a speed.
@export var corpse_sink_gravity: float = 0.3
@export var corpse_sink_depth: float = 2.2

@export_group("Blood")
## Same burst as the bat (see blood.gd); tuned by the same three knobs.
@export var blood_count: int = 26
@export var blood_speed: float = 5.0
@export var blood_color: Color = Color(0.55, 0.02, 0.04)

@export_group("Movement")
@export var move_speed: float = 5.2
@export var acceleration: float = 18.0
@export var turn_rate: float = 7.0
@export var gravity: float = 24.0
## The walk take is a stroll; played faster it reads as a charge.
@export var walk_playback: float = 1.6

var _anim: AnimationPlayer
var _skel: Skeleton3D
var _ragdoll: PhysicalBoneSimulator3D
var _sinking: bool = false
var _state: State = State.GUARD
var _health: int
var _target: Node3D
var _clip: String = ""
var _clip_loops: bool = false
var _sight_timer: float = 0.0
var _cooldown: float = 0.0
var _swing_hit_done: bool = false
var _home_facing: float = 0.0
var _dead_t: float = 0.0
var _sink_from: float = 0.0

func _ready() -> void:
	_health = max_health
	add_to_group("enemies", true)
	add_to_group("watchers", true)
	_home_facing = rotation.y
	for n in find_children("*", "AnimationPlayer", true, false):
		_anim = n
		break
	for n in find_children("*", "Skeleton3D", true, false):
		_skel = n
		break
	if _anim:
		# One long take that must never stop; clip bounds are enforced by hand
		# in _advance_clip(), so let the player itself run forever.
		var a := _anim.get_animation("all")
		if a:
			a.loop_mode = Animation.LOOP_LINEAR
		_anim.play("all")
		# Desync idle breathing so a trio doesn't move as one object.
		_play_clip(CLIP_IDLE, true, randf())
	_target = get_tree().get_first_node_in_group("player") as Node3D

# --- animation -------------------------------------------------------------

## `phase` 0..1 optionally starts partway in, for desyncing.
func _play_clip(name: String, loop: bool, phase: float = 0.0) -> void:
	if _anim == null or not CLIPS.has(name):
		return
	_clip = name
	_clip_loops = loop
	var span: Array = CLIPS[name]
	var a: float = span[0]
	var b: float = span[1]
	_anim.seek(a + (b - a) * clampf(phase, 0.0, 0.999), true)

## Returns true on the frame a non-looping clip runs out.
func _advance_clip() -> bool:
	if _anim == null or _clip == "":
		return false
	var span: Array = CLIPS[_clip]
	var pos := _anim.current_animation_position
	# Guard against the playhead wrapping past the end of the whole take.
	if pos < span[0] - 0.05 or pos >= span[1]:
		if _clip_loops:
			_anim.seek(span[0], true)
			return false
		_anim.seek(maxf(span[0], span[1] - 0.001), true)
		return true
	return false

func _clip_elapsed() -> float:
	if _anim == null or _clip == "":
		return 0.0
	return _anim.current_animation_position - float(CLIPS[_clip][0])

# --- senses ----------------------------------------------------------------

func _eye() -> Vector3:
	return global_position + Vector3.UP * 1.5

func _can_see_player() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var to := _target.global_position - global_position
	var dist := to.length()
	if dist > sight_range:
		return false
	if dist > alert_radius:
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		var facing := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
		if facing.dot(flat) < cos(deg_to_rad(sight_angle * 0.5)):
			return false
	return _has_line_of_sight()

## The first thing a ray to the player's chest hits must be the player itself.
func _has_line_of_sight() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var q := PhysicsRayQueryParameters3D.create(_eye(),
		_target.global_position + Vector3.UP * 0.8)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit["collider"] == _target

## Everything that has to be true before committing to a swing. Distance alone
## is not enough: the swing is a ~1.6s commitment that only lands inside
## attack_reach and inside a narrow arc, so one started while still turning, or
## with a pillar in the way, can never connect - it just reads as the watcher
## flailing at nothing.
func _can_strike() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	var flat := Vector3(_target.global_position.x - global_position.x, 0.0,
		_target.global_position.z - global_position.z)
	if flat.length() > attack_range:
		return false
	var facing := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if facing.dot(flat.normalized()) < cos(deg_to_rad(attack_aim_angle * 0.5)):
		return false
	return _has_line_of_sight()

## Woken by a squadmate, or by taking a hit from something unseen.
func alert() -> void:
	if _state == State.DEAD or _state == State.CHASE or _state == State.ATTACK:
		return
	_state = State.CHASE
	_play_clip(CLIP_WALK, true)

func _alert_squad() -> void:
	var camp := get_parent()
	if camp == null:
		return
	for sib in camp.get_children():
		if sib != self and sib.has_method("alert"):
			sib.alert()

func is_alerted() -> bool:
	return _state == State.CHASE or _state == State.ATTACK

# --- main loop -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		_tick_dead(delta)
		return

	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group("player") as Node3D

	_cooldown = maxf(0.0, _cooldown - delta)

	match _state:
		State.GUARD: _tick_guard(delta)
		State.CHASE: _tick_chase(delta)
		State.ATTACK: _tick_attack(delta)
		State.HURT: _tick_hurt(delta)

	_fall(delta)
	move_and_slide()

## Lie where you fell, then sink. Freeing the node outright made the corpse
## blink out mid-frame, which reads worse than the death itself.
func _tick_dead(delta: float) -> void:
	_dead_t += delta
	if _ragdoll:
		_tick_ragdoll(delta)
		return
	_advance_clip()
	var span: Array = CLIPS[CLIP_DEATH]
	var settled: float = float(span[1]) - float(span[0]) + corpse_linger
	if _dead_t < settled:
		# Still governed by physics, so it lands on whatever it died on.
		_fall(delta)
		move_and_slide()
		return
	# Sinking is a direct translate: move_and_slide() would refuse to push the
	# body into the floor it is resting on.
	global_position.y -= corpse_sink_speed * delta
	if _sink_from - global_position.y > corpse_sink_depth:
		queue_free()

## Physics owns the fall, so this only has to wait and then let go. The
## CharacterBody deliberately stops moving: the physical bones write bone poses
## in world space, so moving their ancestor would only make the skeleton
## compensate, and the corpse would not visibly budge.
func _tick_ragdoll(_delta: float) -> void:
	if not _sinking:
		if _dead_t < ragdoll_settle + corpse_linger:
			return
		_sinking = true
		_sink_from = RAGDOLL.top_y(_ragdoll)
		RAGDOLL.sink(_ragdoll, corpse_sink_gravity)
		return
	if _sink_from - RAGDOLL.top_y(_ragdoll) > corpse_sink_depth:
		queue_free()

func _fall(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)

func _tick_guard(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	# Drift back to the pose they were placed in, so a camp keeps its shape.
	rotation.y = lerp_angle(rotation.y, _home_facing, clampf(delta * 2.0, 0.0, 1.0))
	_advance_clip()
	_sight_timer -= delta
	if _sight_timer <= 0.0:
		_sight_timer = sight_interval
		if _can_see_player():
			alert()
			_alert_squad()

func _tick_chase(delta: float) -> void:
	if _target == null:
		return
	var to := _target.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	_face(flat, delta)
	if _cooldown <= 0.0 and _can_strike():
		_state = State.ATTACK
		_swing_hit_done = false
		_play_clip(CLIP_ATTACK, false)
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var desired := Vector3.ZERO
	if flat.length() > attack_range * 0.9:
		desired = flat.normalized() * move_speed
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	if _anim:
		_anim.speed_scale = walk_playback
	_advance_clip()

func _tick_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)
	if _target:
		# Keep tracking during the windup, but not during the swing itself -
		# a committed swing is what makes them dodgeable.
		if _clip_elapsed() < ATTACK_HIT_AT * 0.6:
			_face(Vector3(_target.global_position.x - global_position.x, 0.0,
				_target.global_position.z - global_position.z), delta)
	if _anim:
		_anim.speed_scale = 1.0
	if not _swing_hit_done and _clip_elapsed() >= ATTACK_HIT_AT:
		_swing_hit_done = true
		_land_hit()
	if _advance_clip():
		_cooldown = attack_cooldown
		_state = State.CHASE
		_play_clip(CLIP_WALK, true)

func _tick_hurt(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, acceleration * 2.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * 2.0 * delta)
	if _advance_clip():
		_state = State.CHASE
		_play_clip(CLIP_WALK, true)

func _face(flat: Vector3, delta: float) -> void:
	if flat.length_squared() < 0.0001:
		return
	# The model's front is +Z, same as the chonchon.
	var want := atan2(flat.x, flat.z)
	rotation.y = lerp_angle(rotation.y, want, clampf(delta * turn_rate, 0.0, 1.0))

## The mace connects. The player currently has no health system, so this is a
## no-op against them by design - take_hit() is the contract it will use when
## one exists.
func _land_hit() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to := _target.global_position - global_position
	if Vector3(to.x, 0.0, to.z).length() > attack_reach:
		return
	var facing := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
	if facing.dot(Vector3(to.x, 0.0, to.z).normalized()) < 0.35:
		return
	if _target.has_method("take_hit"):
		_target.take_hit(attack_damage, _target.global_position, facing)

# --- damage ----------------------------------------------------------------

## Returns true if the hit landed. Same contract as bat_enemy.
func take_hit(amount: int = 1, at: Vector3 = Vector3.INF,
		from: Vector3 = Vector3.ZERO) -> bool:
	if _state == State.DEAD:
		return false
	# Unlike the bat, the origin sits at the feet - fall back to chest height.
	var point := at if at != Vector3.INF else global_position + Vector3.UP * 1.2
	_health -= amount
	# Being shot counts as being spotted, even from behind.
	if not is_alerted():
		_alert_squad()
	if _health > 0:
		_spray(point, 1.0)
		_state = State.HURT
		_play_clip(CLIP_HURT, false)
		if _anim:
			_anim.speed_scale = 1.0
		return true
	_die(point, from)
	return true

## Parented to the camp node rather than the watcher, so it outlives the corpse.
func _spray(at: Vector3, scale_mult: float) -> void:
	BLOOD.spray(get_parent(), at, blood_count, blood_speed, blood_color, scale_mult)

func _die(at: Vector3, from: Vector3) -> void:
	_spray(at, 2.0)
	_state = State.DEAD
	died.emit()
	velocity = Vector3.ZERO
	# Clear the LAYER, not the shapes. Disabling the shapes stops the corpse
	# detecting the floor, so is_on_floor() never comes back true and the DEAD
	# branch's gravity drops it through the world (measured: -106m in 3s).
	# Emptying the layer keeps the mask intact - it still rests on the ground -
	# while making it untargetable and walk-through for everything else.
	collision_layer = 0
	_dead_t = 0.0
	_sinking = false
	_sink_from = global_position.y

	if use_ragdoll and _skel:
		_ragdoll = RAGDOLL.build(_skel)
	if _ragdoll:
		# The baked death clip is dead weight now - physics does the falling,
		# and leaving the take running would just be overwritten every frame.
		if _anim:
			_anim.pause()
		# This kill has just alerted the squad, and they will charge straight
		# over the body. See RAGDOLL.ignore().
		var actors := get_tree().get_nodes_in_group("enemies")
		actors.append_array(get_tree().get_nodes_in_group("player"))
		RAGDOLL.ignore(_ragdoll, actors)
		var dir := from.normalized() if not from.is_zero_approx() else Vector3.UP
		RAGDOLL.start(_ragdoll, at, dir * ragdoll_impulse)
		return

	if _anim:
		_anim.speed_scale = 1.0
	_play_clip(CLIP_DEATH, false)
