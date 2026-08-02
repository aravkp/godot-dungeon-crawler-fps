extends CharacterBody3D

## First-person controller with wall running.
##
## WASD / arrows to move, Shift to sprint, Space to jump.
## In the air, brush a wall while moving and you will run along it; Space
## while wall running kicks off it.
## Escape releases the mouse, click recaptures it.

@export_group("Movement")
@export var walk_speed: float = 8.5
@export var sprint_speed: float = 13.5
@export var acceleration: float = 75.0
## Air control is deliberately weaker than ground control.
@export var air_acceleration: float = 30.0
@export var respawn_below_y: float = -10.0

@export_group("Jump")
## Apex is velocity^2 / (2 * rise_gravity), so 13.0 reaches ~3.25m - up from
## 2.12m. High enough to clear the 3.2m ramp platform from flat ground and to
## reach a wall run from a standing start.
@export var jump_velocity: float = 13.0
## Custom gravity rather than the project default (9.8): a snappy jump needs
## to rise fast and fall faster, which one constant cannot give you.
@export var rise_gravity: float = 26.0
@export var fall_gravity: float = 34.0
## Grace period to still jump just after walking off an edge.
@export var coyote_time: float = 0.12

@export_group("Wall Run")
@export var wall_run_enabled: bool = true
@export var wall_check_distance: float = 0.85
## Below this horizontal speed a wall is just a wall.
@export var wall_run_min_speed: float = 4.0
@export var wall_run_speed: float = 13.0
@export var wall_run_max_time: float = 1.7
## Downward drift while attached, instead of full gravity.
@export var wall_run_sink: float = 2.5
@export var wall_jump_up: float = 9.5
@export var wall_jump_push: float = 9.0
@export var wall_run_tilt_degrees: float = 14.0
## Stops you re-gripping the wall you just kicked off.
@export var wall_reattach_delay: float = 0.28

@export_group("Look")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_degrees: float = 89.0

@export_group("Interact")
## How far the E prompt reaches. Cast down the camera axis, so it aims at the
## crosshair exactly like the melee swing and the finger gun do.
@export var interact_range: float = 3.5

@export_group("View Bob")
@export var bob_frequency: float = 9.0
@export var bob_amplitude: float = 0.035
@export var sway_amount: float = 0.02

@onready var head: Node3D = $Head
@onready var view_model: Node3D = $Head/Camera3D/ViewModel
@onready var camera: Camera3D = $Head/Camera3D

var _focus: Object = null          # what the crosshair is currently over
var _spawn_point: Vector3
var _pitch: float = 0.0
var _bob_time: float = 0.0
var _view_model_rest: Vector3

var _jump_was_down: bool = false
var _coyote: float = 0.0

var _wall_running: bool = false
var _wall_normal: Vector3 = Vector3.ZERO
var _wall_side: float = 0.0        # +1 wall on the right, -1 on the left
var _wall_timer: float = 0.0
var _wall_cooldown: float = 0.0
var _tilt: float = 0.0

func _ready() -> void:
	_spawn_point = global_position
	_view_model_rest = view_model.position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
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
	var jump_down := Input.is_physical_key_pressed(KEY_SPACE)
	var jump_pressed := jump_down and not _jump_was_down
	_jump_was_down = jump_down

	var wish := _wish_direction()
	_wall_cooldown = maxf(0.0, _wall_cooldown - delta)

	if is_on_floor():
		_coyote = coyote_time
		_end_wall_run()
	else:
		_coyote = maxf(0.0, _coyote - delta)

	if _wall_running:
		_wall_run_step(delta, jump_pressed)
	else:
		_ground_air_step(delta, wish, jump_pressed)
		if wall_run_enabled and not is_on_floor() and _wall_cooldown <= 0.0:
			_try_start_wall_run()

	move_and_slide()
	_update_tilt(delta)
	_update_view_bob(delta)
	_scan_focus()

	if global_position.y < respawn_below_y:
		_respawn()

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

	var speed := sprint_speed if Input.is_physical_key_pressed(KEY_SHIFT) else walk_speed
	var accel := acceleration if is_on_floor() else air_acceleration
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)

## Looks for a wall either side of the player, ignoring floors and ceilings.
func _probe_wall() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.2
	for side: float in [1.0, -1.0]:
		var dir: Vector3 = global_transform.basis.x * side
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * wall_check_distance)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		# A near-vertical surface only; a ramp underfoot is not a wall.
		if hit and absf((hit.normal as Vector3).y) < 0.3:
			return {"side": side, "normal": hit.normal as Vector3}
	return {}

func _try_start_wall_run() -> void:
	if Vector2(velocity.x, velocity.z).length() < wall_run_min_speed:
		return
	var w := _probe_wall()
	if w.is_empty():
		return
	_wall_running = true
	_wall_normal = w["normal"]
	_wall_side = w["side"]
	_wall_timer = 0.0
	# Kill any downward momentum so contact feels like a catch, not a slide.
	velocity.y = maxf(velocity.y, 0.0)

func _wall_run_step(delta: float, jump_pressed: bool) -> void:
	_wall_timer += delta
	var w := _probe_wall()
	if w.is_empty() or _wall_timer > wall_run_max_time or is_on_floor():
		_end_wall_run()
		return
	_wall_normal = w["normal"]

	if jump_pressed:
		# Kick up and away from the wall.
		velocity = _wall_normal * wall_jump_push + Vector3.UP * wall_jump_up
		_end_wall_run()
		return

	# Run along the wall, in whichever direction we are facing.
	var along := _wall_normal.cross(Vector3.UP).normalized()
	if along.dot(-transform.basis.z) < 0.0:
		along = -along
	# A little push into the wall keeps contact through corners.
	var horizontal := along * wall_run_speed - _wall_normal * 2.0
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	velocity.y = move_toward(velocity.y, -wall_run_sink, 45.0 * delta)

func _end_wall_run() -> void:
	if not _wall_running:
		return
	_wall_running = false
	_wall_normal = Vector3.ZERO
	_wall_side = 0.0
	_wall_cooldown = wall_reattach_delay

## Rolls the camera away from the wall while running it.
func _update_tilt(delta: float) -> void:
	var target := 0.0
	if _wall_running:
		target = deg_to_rad(wall_run_tilt_degrees) * -_wall_side
	_tilt = lerpf(_tilt, target, clampf(delta * 9.0, 0.0, 1.0))
	head.rotation = Vector3(_pitch, 0.0, _tilt)

func _update_view_bob(delta: float) -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var reference := maxf(sprint_speed, 0.001)
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

func _respawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
	_pitch = 0.0
	_tilt = 0.0
	_end_wall_run()
	head.rotation = Vector3.ZERO

## True while attached to a wall - handy for other scripts.
func is_wall_running() -> bool:
	return _wall_running
