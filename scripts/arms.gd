extends Node3D

## Drives the first-person arms viewmodel.
##
## The rig's bind pose is a T-pose, so an idle animation must always be
## playing or the arms splay out sideways across the screen.
##
## ONE ATTACK, ON ONE BUTTON. Left click swings, and holding it keeps swinging
## for as long as it is down. There are no stance keys, no second weapon, no
## ranged attack and no per-arm bindings - what the swing IS depends only on what
## you have picked up:
##
##   bare hands  ->  jab_L / jab_R, alternating
##   dagger      ->  knife_hit_01 / knife_hit_02, alternating
##
## Alternating is what makes a held button read as a punch combo rather than as
## one arm pumping, and it costs nothing: the pack ships both sides of each.
##
## YOU START WITH TWO EMPTY FISTS. The dagger is chest loot (see pickup.gd), so
## the opening idle is guard_idle. Taking the dagger swaps the idle to knife_idle
## - the pose the dagger mount was fitted against (see tools/mount_dagger.gd) -
## and reveals the DaggerMount, which is hidden until then.
##
## LIMITATION: every clip in arms_rig.glb animates BOTH arms (30 .L tracks and
## 30 .R tracks each), so the arms cannot actually act at the same time - one
## action plays at a time and `_busy` gates the next. Genuine per-arm layering
## would need an AnimationTree with a bone filter, which this does not use. With
## a single attack button that limitation no longer costs anything; it is why
## the old two-weapon, two-button layout never really worked.

signal dagger_unlocked

const SLASH := preload("res://scripts/slash_fx.gd")

## Bare-fists idle, used until the dagger is picked up.
@export var idle_anim: StringName = &"guard_idle"
## Idle once the dagger is in hand. The mount was fitted against this pose.
@export var knife_idle_anim: StringName = &"knife_idle"
@export var blend_time: float = 0.15
## The dagger rides a BoneAttachment3D outside this instanced scene, so it is
## a sibling rather than a child.
@export var weapon_path: NodePath = ^"../DaggerMount"

@export_group("Attack")
## Bare fists. Alternated, so holding the button throws left, right, left...
@export var jab_anims: Array[StringName] = [&"jab_L", &"jab_R"]
## The dagger's two swings, likewise alternated.
@export var knife_anims: Array[StringName] = [&"knife_hit_01", &"knife_hit_02"]
## Off until a chest grants it. A level can set this true to start armed.
@export var has_dagger: bool = false
## Playback rate for a swing, and so the whole cadence: the clip's own length is
## what paces a held attack, since the next one starts when the last one ends.
## The jabs are authored at a full 1.0 s and the knife hits at ~0.7 s, which
## sustains at roughly one punch a second - too slow to read as punching. At 1.6
## a jab lands in 0.63 s and a knife hit in 0.44 s.
@export var attack_speed: float = 1.6
## Hold the button to keep swinging. Off makes it strictly one swing per click.
@export var hold_to_repeat: bool = true
## The only binding in the project. Nothing else reads a mouse button and there
## are no InputMap actions, so moving the attack is this one default.
@export var attack_button: MouseButton = MOUSE_BUTTON_LEFT

@export_group("Melee")
@export var melee_range: float = 2.4
@export var melee_damage: int = 1

@export_group("Slash FX")
## Blade slashes, dagger only - bare fists throw no arc. See slash_fx.gd.
@export var slash_fx: bool = true
## How far in front of the camera the arc is drawn. Nearer reads bigger and
## faster; too near and it clips the hands.
@export var slash_distance: float = 0.85
## World size of one arc pixel. 0.0075 puts the 128 px sheet across roughly
## two thirds of the screen height at the default fov and distance.
@export var slash_size: float = 0.0075
## Playback rate of the nine sheet frames. Wants to be a touch shorter than the
## swing clip, or the arc is still hanging there when the blade has stopped.
@export var slash_fps: float = 42.0

@onready var anim: AnimationPlayer = $AnimationPlayer

var _next_swing: int = 0
var _busy: bool = false
var _weapon: Node3D

func _ready() -> void:
	add_to_group("viewmodel", true)
	_weapon = get_node_or_null(weapon_path) as Node3D
	# Hidden until the dagger is looted, so the starting fists are empty.
	if _weapon:
		_weapon.visible = has_dagger
	# glTF animations import with looping off; both idles have to cycle.
	for name: StringName in [idle_anim, knife_idle_anim]:
		var loop := anim.get_animation(name)
		if loop:
			loop.loop_mode = Animation.LOOP_LINEAR
	anim.animation_finished.connect(_on_animation_finished)
	anim.play(_idle())

## Which idle applies right now - bare fists, or the knife guard.
func _idle() -> StringName:
	return knife_idle_anim if has_dagger else idle_anim

func _unhandled_input(event: InputEvent) -> void:
	# Ignore input while the cursor is free; the click that recaptures the
	# mouse shouldn't also throw a punch.
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == attack_button:
		attack()

func _process(_delta: float) -> void:
	# Picks up a button that was already down - the press event fires once, and
	# this is what turns it into a sustained attack.
	if _trigger_down():
		attack()

func _trigger_down() -> bool:
	return hold_to_repeat \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and Input.is_mouse_button_pressed(attack_button)

## Swing whatever is in hand. Alternates within the set, so a held button throws
## left, right, left rather than the same arm over and over. Returns whether a
## swing actually started - it will not while one is already playing.
func attack() -> bool:
	var clips: Array[StringName] = knife_anims if has_dagger else jab_anims
	if clips.is_empty():
		return false
	if not _melee(clips[_next_swing % clips.size()]):
		return false
	_next_swing += 1
	return true

## Shared one-shot swing: gate on _busy so a swing has to finish, play it, and
## resolve the hit immediately. Returns whether it actually started.
func _melee(clip: StringName) -> bool:
	if _busy or clip == &"" or not anim.has_animation(clip):
		return false
	_busy = true
	anim.play(clip, blend_time, attack_speed)
	# Mirrored on the odd swing, so the alternating pair of knife clips throws
	# an alternating pair of arcs. _next_swing has not been advanced yet, so its
	# parity here is the parity of the clip that just started.
	if slash_fx and has_dagger:
		SLASH.arc(get_parent() as Node3D, _next_swing % 2 == 1,
			slash_distance, slash_size, slash_fps)
	swing()
	return true

## Granted by a chest pickup. Reveals the dagger and swaps the idle to the pose
## the mount was fitted against, so the grip lands correctly from the first frame.
func unlock_dagger() -> bool:
	if has_dagger:
		return false
	has_dagger = true
	if _weapon:
		_weapon.visible = true
	# Start the dagger's pair from the top rather than wherever the fists left
	# off, so looting mid-combo cannot open with the second swing.
	_next_swing = 0
	# Only re-idle if nothing is mid-swing; _on_animation_finished picks up the
	# new idle otherwise.
	if not _busy:
		anim.play(_idle(), blend_time)
	dagger_unlocked.emit()
	return true

## Jab and dagger alike: a short reach straight ahead. Anything with take_hit()
## in range gets hurt. Aimed off the camera, which is exactly screen centre, so
## the crosshair is truthful.
func swing() -> Object:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * melee_range)
	var shooter := _shooter()
	if shooter:
		query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	# Sparks on whatever the blade actually met, wall or throat alike - that is
	# what the ray says happened, and it is what tells a connect from a whiff.
	# Hosted on the level, never on the collider: a killing blow frees the
	# corpse and would take the burst with it.
	if slash_fx and has_dagger:
		SLASH.impact(_level(), hit["position"], -dir)
	var target: Object = hit.get("collider")
	if target and target.has_method("take_hit"):
		target.take_hit(melee_damage, hit["position"], dir)
		return target
	return null

## Somewhere to hang a hit effect that outlives whatever was hit. `owner` is the
## fallback because a tool script that instantiates the level itself never sets
## current_scene, and the effect would silently not appear under the probe.
func _level() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else owner


func _shooter() -> CollisionObject3D:
	var n: Node = self
	while n:
		if n is CollisionObject3D:
			return n as CollisionObject3D
		n = n.get_parent()
	return null

func _on_animation_finished(finished: StringName) -> void:
	# The looping idle never reports finished, so this is always a one-shot.
	# Compared against _idle() rather than idle_anim: taking the dagger changes
	# which one is looping, and the stale one would otherwise be re-queued here.
	if finished == _idle():
		return
	_busy = false
	# Chain straight into the next swing while the button is held, instead of
	# dropping back to the idle and picking the attack up again next frame. That
	# gap is a real one - the idle would blend in for a frame between every pair
	# of punches, which at this cadence reads as a stutter.
	if _trigger_down() and attack():
		return
	anim.play(_idle(), blend_time)
