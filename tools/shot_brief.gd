extends SceneTree

## Stills of scenes/corridors.tscn for a design brief - the level as it actually
## plays, rather than the diagnostic angles shot_corridors.gd takes.
##
## Two things it does that shot_corridors.gd does not, both of which matter if
## the pictures are going to be shown to anyone:
##
##   - It shoots through the PLAYER'S OWN Camera3D. The viewmodel hangs off that
##     camera, so a free camera parked at the same spot renders the arms in world
##     space at the wrong scale and splay - they come out enormous.
##   - It removes the Cutscene CanvasLayer first. It runs at level start and its
##     panel is drawn over every single frame otherwise. One shot is taken WITH
##     it, on purpose, before it goes.
##
## Needs a real display server, so run WITHOUT --headless:
##   "$GODOT" --path . -s tools/shot_brief.gd
##
## Writes .shots/brief/NN_name.png.

const SCENE := "res://scenes/corridors.tscn"
const OUT := "res://.shots/brief"

var _win: Window
var _dir: String
var _n := 0


func _init() -> void:
	_dir = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(_dir)
	_win = get_root()
	DisplayServer.window_set_size(Vector2i(1280, 720)); _win.set_size(Vector2i(1280, 720))

	var scene := (load(SCENE) as PackedScene).instantiate()
	# Stripped before the scene enters the tree, or _ready captures the mouse and
	# the shot machine loses the pointer. Arms keep their own script.
	var player := scene.get_node("Player") as CharacterBody3D
	player.set_script(null)
	get_root().add_child(scene)
	await process_frame

	var cam := scene.get_node("Player/Head/Camera3D") as Camera3D
	cam.current = true
	var arms := scene.get_node("Player/Head/Camera3D/ViewModel/Arms")
	var level := scene.get_node("Corridors") as Node3D
	var packs := scene.get_node_or_null("Packs")
	await process_frame

	# 1. the opening scene, which is the first thing anyone actually sees. The
	# creature has to rise out of the floor and the typewriter has to get going
	# before there is anything on screen, so this waits rather than shooting
	# frame 8 and catching an empty corridor.
	for f in range(190): await process_frame
	await _shoot("opening_cutscene")
	var cut := scene.get_node_or_null("Cutscene")
	if cut:
		cut.queue_free()
		# The Warden is a level node the cutscene only animates, so freeing the
		# CanvasLayer strands it half-risen in the corridor and every later shot
		# reads as though there is an enemy standing in the hall. In play it
		# sinks back into the floor before control is handed over.
		var warden := level.get_node_or_null("Warden") as Node3D
		if warden:
			warden.visible = false
		await process_frame

	# 2. spawn, bare-fisted, looking down the first corridor.
	await _shoot("start_bare_fists")

	# 3. the chest that arms you, from interaction range.
	var chest := scene.get_node("DaggerChest") as Node3D
	await _face(player, chest.global_position + Vector3(0, 0.5, 0), 2.6)
	await _shoot("dagger_chest")

	# ...and once it has been taken.
	arms.unlock_dagger()
	for f in range(20): await process_frame
	await _shoot("dagger_in_hand")

	# 4. a gate head-on: the thing you either smash or lift.
	var gate := _first(level, "Gate_") as Node3D
	if gate:
		await _face(player, gate.global_position + Vector3(0, 1.1, 0), 4.5)
		await _shoot("gate_closed")
		# and the hole it leaves. A Gate_NN is a container: the frame's solid
		# parts are `Solid`, and `Door` is the breakable leaf that carries
		# door.gd. take_hit on the leaf is the same entry point the melee ray
		# uses, so this is the real destruction path and not a special case.
		var leaf := gate.get_node_or_null("Door")
		if leaf and leaf.has_method("take_hit"):
			leaf.take_hit(99, leaf.global_position, Vector3.FORWARD)
			for f in range(70): await process_frame
			await _shoot("gate_smashed")
		else:
			push_warning("gate leaf has no take_hit - no smashed shot")

	# 5. a crate, and the swing that breaks it - the arc paused at its peak,
	# because the whole effect lasts ~215 ms and a save takes ~95.
	var crate := _first(level, "Crate_") as Node3D
	if crate:
		await _face(player, crate.global_position + Vector3(0, 0.5, 0), 2.4)
		arms.attack()
		var vm := scene.get_node("Player/Head/Camera3D/ViewModel")
		var arc := vm.get_node_or_null("SlashArc") as AnimatedSprite3D
		if arc:
			arc.speed_scale = 0.0
			arc.animation_finished.disconnect(arc.queue_free)
			arc.frame = 4
		await _shoot("dagger_slash")
		# Disconnecting queue_free above means nothing frees it, and a paused arc
		# hangs in front of the camera for every shot after this one.
		if arc:
			arc.queue_free()
			await process_frame

	# 6. the two things crouch exists for: a collapsed ramp, and a gate stuck
	# partway up. Shot standing, then again ducked, so the difference the key
	# makes is the thing the pair of pictures is about.
	var ramp := _first(level, "Ramp_") as Node3D
	if ramp:
		await _face(player, ramp.global_position + Vector3(0, 1.0, 0), 3.4)
		await _shoot("ramp_standing")
		await _crouch(player, arms)
		await _shoot("ramp_crouched")
		_uncrouch(player)
	var stuck := _jammed_gate(level)
	if stuck:
		await _face(player, stuck.global_position + Vector3(0, 0.9, 0), 3.6)
		await _shoot("gate_jammed")
		await _crouch(player, arms)
		await _shoot("gate_jammed_crouched")
		_uncrouch(player)

	# 7. a watcher pack, from where you would first meet one.
	# Aimed at a watcher, not at the Pack node: the pack is a bare grouping
	# parent sitting at the cell origin, and framing it put the trio off screen.
	if packs and packs.get_child_count() > 0:
		var pack := packs.get_child(0)
		if pack.get_child_count() > 0:
			var w := pack.get_child(0) as Node3D
			await _face(player, w.global_position + Vector3(0, 1.1, 0), 5.0)
			await _shoot("watcher_pack")

	# 8. the route from above, ceilings stripped. The only shot that is a
	# diagram rather than a view.
	for c in level.get_children():
		if c.name.begins_with("C_"):
			(c as Node3D).visible = false
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for c in level.get_children():
		if c is Node3D and c.name.begins_with("F_"):
			lo = lo.min((c as Node3D).global_position)
			hi = hi.max((c as Node3D).global_position)
	var mid := (lo + hi) * 0.5
	var span: float = maxf(hi.x - lo.x, hi.z - lo.z)
	var top := Camera3D.new()
	top.fov = 70.0; top.far = 500.0
	scene.add_child(top)
	top.current = true
	# 0.62 rather than 0.85: the route is a thin diagonal ribbon, so framing it by
	# its bounding square leaves most of the picture black.
	top.global_position = mid + Vector3(0.01, span * 0.62 + 8.0, 0.01)
	top.look_at(mid, Vector3(0, 0, -1))
	await _shoot("route_plan")
	print("layout spans %.1f m x %.1f m" % [hi.x - lo.x, hi.z - lo.z])
	quit()


## Put the player `back` metres from `at`, looking at it, at eye height.
func _face(player: Node3D, at: Vector3, back: float) -> void:
	var from := at + Vector3(0, 0, 1) * back
	# Approach along whichever horizontal axis has more clearance, so the camera
	# is not buried in a corridor wall.
	var space := player.get_world_3d().direct_space_state
	var best := from
	var best_d := -1.0
	for dir in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var q := PhysicsRayQueryParameters3D.create(at, at + dir * back)
		var h := space.intersect_ray(q)
		var d: float = back if h.is_empty() else at.distance_to(h["position"])
		if d > best_d:
			best_d = d
			best = at + dir * minf(back, d * 0.85)
	player.global_position = best + Vector3(0, 0.35, 0)
	var head := player.get_node("Head") as Node3D
	# Yaw on the body, pitch on the head - the same split player.gd uses.
	var flat := (at - player.global_position)
	# A Node3D with yaw t has forward -basis.z = (-sin t, 0, -cos t), so facing
	# `flat` is atan2(-x, -z). No half turn: adding one aims at the wall behind.
	player.global_rotation = Vector3(0, atan2(-flat.x, -flat.z), 0)
	head.rotation.x = atan2(flat.y, Vector2(flat.x, flat.z).length())
	for f in range(6): await process_frame


## player.gd was stripped for these shots, so nothing is reading Shift. The
## capsule and the eye height are driven straight instead, to exactly the numbers
## player.gd would settle on - the picture is of the crouched pose either way.
func _crouch(player: CharacterBody3D, _arms: Node) -> void:
	var shape := player.get_node("PlayerCollision") as CollisionShape3D
	var cap := shape.shape as CapsuleShape3D
	var stand_h := 2.0
	var crouch_h := 1.15
	cap.height = crouch_h
	# Negative: the centre comes DOWN so the capsule's bottom stays on the floor.
	# See player.gd - the opposite sign sinks the camera to ankle height.
	shape.position.y = -(stand_h - crouch_h) * 0.5
	(player.get_node("Head") as Node3D).position.y = crouch_h - stand_h * 0.5 - 0.13
	for f in range(6): await process_frame

func _uncrouch(player: CharacterBody3D) -> void:
	var shape := player.get_node("PlayerCollision") as CollisionShape3D
	(shape.shape as CapsuleShape3D).height = 2.0
	shape.position.y = 0.0
	(player.get_node("Head") as Node3D).position.y = 0.7

func _jammed_gate(level: Node) -> Node3D:
	for c in level.get_children():
		if not c.name.begins_with("Gate_"):
			continue
		var leaf := c.get_node_or_null("Door")
		if leaf and leaf.get("jammed"):
			return c as Node3D
	return null

func _first(parent: Node, prefix: String) -> Node:
	for c in parent.get_children():
		if c.name.begins_with(prefix):
			return c
	return null


func _shoot(nm: String) -> void:
	for f in range(8): await process_frame
	await RenderingServer.frame_post_draw
	_n += 1
	var path := "%s/%02d_%s.png" % [_dir, _n, nm]
	_win.get_texture().get_image().save_png(path)
	print("wrote ", path.get_file())
