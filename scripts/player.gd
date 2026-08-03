extends CharacterBody3D

## First-person controller.
##
## WASD / arrows to move, Shift to CROUCH, Space to jump, E to interact.
## Escape releases the mouse, click recaptures it.
##
## There is one ground speed. Sprint and wall running were both removed: the
## corridor level is 4 m wide and 4 m tall, which is not enough room to wall run
## in, and a sprint on top of a single walk speed only ever made the walk feel
## like the punishment. What Shift does now is lower you.
##
## CROUCHING IS A REAL SIZE CHANGE, not a camera trick. The capsule shrinks from
## `stand_height` to `crouch_height` and the collider is lifted by half the
## difference so the FEET stay put - shrinking it in place would drop the body
## and leave the player standing in a hole. That is what lets a 1.35 m gap under
## a jammed gate be genuinely impassable standing and genuinely passable crouched,
## with no trigger volumes and nothing to keep in sync.
##
## You cannot stand back up under something. Releasing Shift runs a capsule query
## at standing size first, and stays crouched while it hits anything.
##
## ONE HIT KILLS YOU. There is no health, no armour and no damage numbers - the
## same rule the enemies live under. take_hit() is the damage contract every
## other body in the project answers (bat, watcher, breakable, chest), so the
## watchers' mace needed nothing added to it: the call was already there and was
## already landing, it just had nothing to land on. `amount` is accepted for the
## contract and deliberately ignored.

signal died

@export_group("Movement")
@export var walk_speed: float = 8.5
@export var acceleration: float = 75.0
## Air control is deliberately weaker than ground control.
@export var air_acceleration: float = 30.0
@export var respawn_below_y: float = -10.0

@export_group("Crouch")
## Held, not toggled - a toggle plus a ceiling that refuses to let you rise is a
## state the player cannot see and cannot explain.
@export var crouch_key: Key = KEY_SHIFT
## Total capsule height while crouched. The capsule radius is 0.5, so this can
## never go below 1.0 - a capsule is two hemispheres and cannot be shorter than
## its own diameter.
@export var crouch_height: float = 1.15
## Slow enough that ducking under something is a decision rather than a detour.
@export var crouch_speed: float = 3.6
## Seconds for the full stand <-> crouch transition, both ways.
@export var crouch_time: float = 0.14

@export_group("Jump")
@export var jump_velocity: float = 13.0
## Custom gravity rather than the project default (9.8): a snappy jump needs
## to rise fast and fall faster, which one constant cannot give you.
@export var rise_gravity: float = 26.0
@export var fall_gravity: float = 34.0
## Grace period to still jump just after walking off an edge.
@export var coyote_time: float = 0.12

@export_group("Damage")
## Seconds the camera takes to go down. It is the whole death animation - there
## is no third-person body to ragdoll, so the view collapsing IS the death.
@export var death_fall_time: float = 0.5
## Where the eye ends up, in metres above the feet. Low enough to read as lying
## on the floor rather than kneeling.
@export var death_eye_height: float = 0.25
## How far the view tips as you go down. Cosmetic, but a drop with no roll reads
## as the camera sinking through the floor rather than as a body falling over.
@export var death_roll_degrees: float = 78.0
## How long the corpse view holds before control comes back at the spawn point.
## Long enough to see what killed you, short enough not to be a punishment.
@export var respawn_delay: float = 2.2

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_degrees: float = 89.0

@export_group("Interact")
## How far the E prompt reaches. Cast down the camera axis, so it aims at the
## crosshair exactly like the melee swing does.
@export var interact_range: float = 3.5

@export_group("View Bob")
@export var bob_frequency: float = 9.0
@export var bob_amplitude: float = 0.035
@export var sway_amount: float = 0.02

@onready var head: Node3D = $Head
@onready var view_model: Node3D = $Head/Camera3D/ViewModel
@onready var camera: Camera3D = $Head/Camera3D
@onready var _shape: CollisionShape3D = $PlayerCollision

var _focus: Object = null          # what the crosshair is currently over
var _spawn_point: Vector3
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _view_model_rest: Vector3

var _jump_was_down: bool = false
var _coyote: float = 0.0

## 0 = fully standing, 1 = fully crouched.
var _crouch: float = 0.0
var _capsule: CapsuleShape3D
var _stand_height: float = 2.0
var _stand_head_y: float = 0.7
var _stand_shape_y: float = 0.0
## Reused every frame by the stand-up test rather than rebuilt.
var _clearance: CapsuleShape3D
var _clearance_query: PhysicsShapeQueryParameters3D

var _dead: bool = false
var _death_t: float = 0.0
## Which way the view tips, set from the direction of the killing blow.
var _death_roll: float = 0.0
## Whether the viewmodel's handlers were running when the blow landed, so giving
## them back cannot switch on something that was already off - the same rule
## cutscene.gd follows, and for the same reason: dying during the opening scene
## must not hand the player their arms back early.
var _arms_were_active: bool = false

func _ready() -> void:
	_spawn_point = global_position
	_view_model_rest = view_model.position
	# Whatever the scene was authored with is the standing pose - read, never
	# assumed, so a level can spawn a differently sized player.
	_capsule = _shape.shape as CapsuleShape3D
	if _capsule:
		_stand_height = _capsule.height
	_stand_head_y = head.position.y
	_stand_shape_y = _shape.position.y
	_build_clearance_probe()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_clearance_probe() -> void:
	_clearance = CapsuleShape3D.new()
	if _capsule:
		# A hair under the real capsule both ways. At exactly its size the probe
		# reports the floor and the wall being leaned on as blockers, and standing
		# up becomes impossible everywhere.
		_clearance.radius = _capsule.radius - 0.02
		_clearance.height = _stand_height - 0.04
	_clearance_query = PhysicsShapeQueryParameters3D.new()
	_clearance_query.shape = _clearance
	_clearance_query.collide_with_areas = false
	_clearance_query.exclude = [get_rid()]

func _unhandled_input(event: InputEvent) -> void:
	# A corpse does not look around, interact, or recapture the mouse. Escape is
	# the one thing still worth honouring - being killed with the cursor locked in
	# should not trap it there.
	if _dead:
		if event.is_action_pressed(&"ui_cancel"):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(pitch_limit_degrees)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -limit, limit)
		view_model.position.x = _view_model_rest.x - event.relative.x * sway_amount * 0.01
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_E:
		# Raw key check to match how the rest of the game reads input - the
		# project has no InputMap actions beyond ui_cancel.
		_try_interact()
	elif event.is_action_pressed(&"ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if _dead:
		_tick_death(delta)
		return

	var jump_down := Input.is_physical_key_pressed(KEY_SPACE)
	var jump_pressed := jump_down and not _jump_was_down
	_jump_was_down = jump_down

	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)

	_update_crouch(delta)
	_ground_air_step(delta, _wish_direction(), jump_pressed)

	move_and_slide()
	head.rotation = Vector3(_pitch, 0.0, 0.0)
	_update_view_bob(delta)
	_scan_focus()

	if global_position.y < respawn_below_y:
		_respawn()

## Drives the capsule, not just the camera. Called before move_and_slide so the
## body moves at the size it is going to be tested at this frame.
func _update_crouch(delta: float) -> void:
	var want := Input.is_physical_key_pressed(crouch_key)
	# Let go under a low ceiling and you stay down. Only worth testing while
	# actually crouched - standing up from standing is free.
	if not want and _crouch > 0.0 and _standing_blocked():
		want = true
	var step: float = delta / maxf(crouch_time, 0.001)
	_crouch = move_toward(_crouch, 1.0 if want else 0.0, step)
	if _capsule == null:
		return
	var h := lerpf(_stand_height, crouch_height, _crouch)
	_capsule.height = h
	# LOWER the collider by half of what came off, so the bottom of the capsule -
	# the feet - stays exactly where it was.
	#
	# The sign here is the whole mechanic. A capsule at local y = 0 with height H
	# spans -H/2 .. +H/2, so its bottom is at -H/2. Shrink H and the bottom rises
	# by (H_stand - H_crouch)/2 unless the centre comes down by the same amount.
	# Getting this backwards does not look like a collider bug: the body is left
	# floating, falls until the raised capsule bottom finds the floor, and the
	# camera goes with it - the player appears to SINK INTO THE GROUND, ending up
	# with the eye about 17 cm off the floor.
	_shape.position.y = _stand_shape_y - (_stand_height - h) * 0.5
	# The body origin sits half a standing height above the feet and does not
	# move, so the crouched capsule's top is at that much below zero plus the
	# crouched height. Park the eye just under it.
	var crouch_eye := crouch_height - _stand_height * 0.5 - 0.13
	head.position.y = lerpf(_stand_head_y, crouch_eye, _crouch)

## Would a standing capsule fit where we are right now?
func _standing_blocked() -> bool:
	if _clearance == null:
		return false
	_clearance_query.transform = Transform3D(Basis.IDENTITY, global_position)
	return not get_world_3d().direct_space_state.intersect_shape(_clearance_query, 1).is_empty()

## True while ducked at all - handy for other scripts.
func is_crouching() -> bool:
	return _crouch > 0.5

## What is the crosshair on? Runs in _physics_process because querying the
## space state outside a physics frame is not safe.
func _scan_focus() -> void:
	_focus = null
	if camera:
		var from := camera.global_position
		var q := PhysicsRayQueryParameters3D.create(
			from, from - camera.global_transform.basis.z * interact_range)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var col: Object = hit.get("collider") if not hit.is_empty() else null
		if col and col.has_method("interact"):
			_focus = col

	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var text := ""
	if _focus and _focus.has_method("prompt"):
		var p: String = _focus.prompt()
		if p != "":
			text = "[E] " + p
	if hud.has_method("set_prompt"):
		hud.set_prompt(text)
	# Optional half of the contract: a name and a one-line description, which
	# pickups carry and plain scenery does not. Cleared whenever the focus offers
	# no action, so a spent object stops advertising itself.
	if hud.has_method("set_focus_info"):
		var t := ""
		var sub := ""
		if text != "" and _focus:
			if _focus.has_method("title"):
				t = _focus.title()
			if _focus.has_method("subtitle"):
				sub = _focus.subtitle()
		hud.set_focus_info(t, sub)

func _try_interact() -> void:
	if _focus and is_instance_valid(_focus) and _focus.has_method("interact"):
		_focus.interact(self)

func _wish_direction() -> Vector3:
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	input_dir = input_dir.normalized()
	return (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

func _ground_air_step(delta: float, wish: Vector3, jump_pressed: bool) -> void:
	if not is_on_floor():
		# Heavier on the way down so the arc feels snappy rather than floaty.
		var g := fall_gravity if velocity.y < 0.0 else rise_gravity
		velocity.y -= g * delta

	if jump_pressed and (is_on_floor() or _coyote > 0.0):
		velocity.y = jump_velocity
		_coyote = 0.0

	# Speed follows the crouch blend rather than switching at a threshold, so
	# ducking bleeds speed off instead of dropping it in one frame.
	var speed := lerpf(walk_speed, crouch_speed, _crouch)
	var accel := acceleration if is_on_floor() else air_acceleration
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

func _update_view_bob(delta: float) -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var reference := maxf(walk_speed, 0.001)
	if is_on_floor() and planar_speed > 0.1:
		_bob_time += delta * bob_frequency * (planar_speed / reference)
	else:
		_bob_time = lerpf(_bob_time, 0.0, delta * 6.0)

	# Both terms must be zero at _bob_time == 0 so the hands rest dead centre.
	var bob := Vector3(
		sin(_bob_time * 0.5) * bob_amplitude,
		-absf(sin(_bob_time)) * bob_amplitude,
		0.0
	)
	view_model.position = view_model.position.lerp(_view_model_rest + bob, delta * 12.0)

# --- damage ------------------------------------------------------------------

## The damage contract, same signature the enemies and the breakables answer.
## Returns whether the hit landed - false once already dead, so a watcher that
## gets a second swing off before the respawn cannot kill you twice.
##
## `amount` is ignored on purpose: one hit kills, whatever swung it. `at` is
## unused here (there is no body to spray blood off) and `from` only chooses
## which way the view tips.
func take_hit(_amount: int = 1, _at: Vector3 = Vector3.INF,
		from: Vector3 = Vector3.ZERO) -> bool:
	if _dead:
		return false
	_die(from)
	return true

func is_dead() -> bool:
	return _dead

func _die(from: Vector3) -> void:
	_dead = true
	_death_t = 0.0
	velocity = Vector3.ZERO
	# Fall AWAY from the blow: a hit travelling to your right knocks you over to
	# your right. The camera looks down -Z, so tipping the head right is a
	# negative rotation about +Z. Straight-on hits pick a side rather than
	# dropping the view dead level, which reads as sinking through the floor.
	var sideways := global_transform.basis.x.dot(from)
	var side := -1.0 if sideways >= 0.0 else 1.0
	_death_roll = deg_to_rad(death_roll_degrees) * side
	# Stop the viewmodel dead. It keeps its own input in _process, so a held
	# attack button would otherwise go on throwing punches from the floor.
	_set_arms_active(false)
	_set_hud_dead(true)
	died.emit()
	get_tree().create_timer(respawn_delay).timeout.connect(_respawn)

## The whole death animation: the view drops to the floor and rolls over. The
## body still falls, so being killed in mid-air lands the corpse where it would
## have landed rather than leaving it hanging.
func _tick_death(delta: float) -> void:
	_death_t += delta
	if not is_on_floor():
		velocity.y -= fall_gravity * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	move_and_slide()

	var t := clampf(_death_t / maxf(death_fall_time, 0.001), 0.0, 1.0)
	# Ease out, so the head drops fast and settles rather than gliding down.
	var e := 1.0 - pow(1.0 - t, 3.0)
	# The body origin sits half a standing height above the feet, so an eye
	# height measured off the floor has to come back through that.
	var floor_eye := death_eye_height - _stand_height * 0.5
	head.position.y = lerpf(_stand_head_y, floor_eye, e)
	head.rotation = Vector3(_pitch, 0.0, lerpf(0.0, _death_roll, e))

## Both handlers are remembered rather than assumed on - see _arms_were_active.
func _set_arms_active(active: bool) -> void:
	var arms := get_tree().get_first_node_in_group("viewmodel")
	if arms == null:
		return
	if not active:
		_arms_were_active = arms.is_processing()
		arms.set_process(false)
		arms.set_process_unhandled_input(false)
		return
	arms.set_process(_arms_were_active)
	arms.set_process_unhandled_input(_arms_were_active)

func _set_hud_dead(dead: bool) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_dead"):
		hud.set_dead(dead)

func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
	_pitch = 0.0
	_crouch = 0.0
	if _capsule:
		_capsule.height = _stand_height
	_shape.position.y = _stand_shape_y
	head.position.y = _stand_head_y
	head.rotation = Vector3.ZERO
	if _dead:
		_dead = false
		_set_arms_active(true)
		_set_hud_dead(false)
