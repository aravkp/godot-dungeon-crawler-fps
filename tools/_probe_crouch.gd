extends SceneTree
## Does the crouch actually get you through things, and does standing actually
## not? That is the point of the mechanic, and no screenshot can show it - a gap
## you fit through and one you do not look identical in a picture.
##
## Measured with capsule queries rather than by walking a player at each
## obstacle. Simulating the walk sounds more honest and is not: it also measures
## pathing, spawn clearance and which way a piece's local axes happen to point,
## so a failure could mean the gap is wrong OR that the probe aimed the player at
## a wall. This asks the only question that matters - would a standing capsule
## fit here, would a crouched one - and asks it at every point along the passage.
##
##   "$GODOT" --headless --path . -s tools/_probe_crouch.gd

const SCENE := "res://scenes/corridors.tscn"
## Must match player.gd. A mismatch here is itself worth catching.
const STAND_H := 2.0
const CROUCH_H := 1.15
const RADIUS := 0.5
## Sampled along the obstacle's local Z, which is the axis a corridor runs down.
const FROM := -2.4
const TO := 2.4
const STEP := 0.2
## How far off the corridor centre line to sample. The player is not a line.
const LATERAL := [0.0, -0.45, 0.45]

var _space: PhysicsDirectSpaceState3D
var _ignore: Array[RID] = []
var _fails := 0


func _character_rids(root: Node) -> Array[RID]:
	var out: Array[RID] = []
	for n in root.find_children("*", "CharacterBody3D", true, false):
		out.append((n as CharacterBody3D).get_rid())
	return out


func _init() -> void:
	var scene := (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(scene)
	await process_frame
	# The controller first, while there is still a player to drive - then it goes,
	# because it is a body in the way of every geometry query below.
	var player := scene.get_node_or_null("Player") as CharacterBody3D
	if player:
		# The cutscene switches the player's handlers off at level start, and a
		# probe driving keys into a disabled handler measures nothing.
		var cut := scene.get_node_or_null("Cutscene")
		if cut:
			cut.queue_free()
			await process_frame
		player.set_physics_process(true)
		await _check_controller(player)
		player.queue_free()
		await process_frame
	_space = (scene.get_node("Corridors") as Node3D).get_world_3d().direct_space_state
	# Every CharacterBody3D is excluded, the same way _probe_smash.gd's gate rays
	# are. A watcher pack spawns on a route cell and one of them stands in the
	# doorway; the query then reports the enemy rather than the hole, and a gap
	# that is perfectly passable is failed for having someone in it. What is under
	# test is the geometry, not who is loitering in it.
	_ignore = _character_rids(scene)
	print("ignoring %d character bod%s" % [_ignore.size(), "y" if _ignore.size() == 1 else "ies"])

	var level := scene.get_node("Corridors")
	var targets: Array[Node3D] = []
	for c in level.get_children():
		if c.name.begins_with("Ramp_"):
			targets.append(c as Node3D)
	for c in level.get_children():
		if not c.name.begins_with("Gate_"):
			continue
		var leaf := c.get_node_or_null("Door")
		if leaf and leaf.get("jammed"):
			targets.append(c as Node3D)

	print("obstacle    stand-blocked   crouch-clear   verdict")
	for t in targets:
		var blocked := _blocked_span(t, STAND_H)
		var crouch_hits := _blocked_span(t, CROUCH_H)
		# Right when a standing capsule is stopped SOMEWHERE along the passage and
		# a crouched one is stopped NOWHERE along it.
		var ok := blocked > 0 and crouch_hits == 0
		if not ok:
			_fails += 1
		print("%-11s %3d samples      %3d samples    %s"
			% [t.name, blocked, crouch_hits,
			"OK" if ok else ("NOT BLOCKED STANDING" if blocked == 0 else "BLOCKS CROUCHED TOO")])
		if crouch_hits > 0:
			# Naming the obstruction is the difference between "the gap is wrong"
			# and "something else was placed in it".
			print("              blockers: %s" % ", ".join(_blockers(t, CROUCH_H)))

	print("\n%d obstacle(s), %d failure(s)" % [targets.size(), _fails])
	quit(1 if _fails > 0 else 0)


## Does the CONTROLLER crouch correctly - as opposed to the level having gaps of
## the right size, which is what everything below this measures.
##
## These are different questions and the geometry checks cannot answer this one:
## they position their own capsules from the floor up and never touch player.gd.
## A sign error in the collider offset passed every geometry check while sinking
## the camera to ankle height in the actual game, which is how this got shipped
## once already.
##
## The assertion that matters is that THE BODY DOES NOT MOVE. Crouching shrinks
## the capsule and lowers its centre by half of what came off, so the feet stay
## put; get the sign backwards and the body is left floating, falls to find the
## floor, and takes the camera down with it.
func _check_controller(player: CharacterBody3D) -> void:
	var cam := player.get_node("Head/Camera3D") as Node3D
	_hold(KEY_SHIFT, false)
	for f in range(70): await physics_frame
	var stand_y := player.global_position.y
	var stand_eye := cam.global_position.y

	_hold(KEY_SHIFT, true)
	for f in range(50): await physics_frame
	var crouch_y := player.global_position.y
	var crouch_eye := cam.global_position.y

	_hold(KEY_SHIFT, false)
	for f in range(50): await physics_frame
	var back_y := player.global_position.y
	var back_eye := cam.global_position.y

	print("controller:  body y  stand %.3f  crouch %.3f  back %.3f" % [stand_y, crouch_y, back_y])
	print("             eye  y  stand %.3f  crouch %.3f  back %.3f" % [stand_eye, crouch_eye, back_eye])

	var drift := absf(crouch_y - stand_y)
	var restored := absf(back_y - stand_y)
	var drop := stand_eye - crouch_eye
	_expect(drift < 0.05, "body must not move when crouching (moved %.3f m)" % drift)
	_expect(restored < 0.05, "body must return on standing (off by %.3f m)" % restored)
	_expect(drop > 0.4 and drop < 0.9, "eye should drop ~0.68 m, dropped %.3f" % drop)
	_expect(absf(back_eye - stand_eye) < 0.05, "eye must return on standing")
	print("")


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("             *** FAIL *** %s" % what)


func _hold(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


## Every distinct collider standing in the way of a capsule of `height`, with the
## local Z it was met at.
func _blockers(target: Node3D, height: float) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS - 0.03
	cap.height = height - 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collide_with_areas = false
	q.exclude = _ignore
	var seen := {}
	var z := FROM
	while z <= TO:
		for x: float in LATERAL:
			q.transform = Transform3D(Basis.IDENTITY,
				target.to_global(Vector3(x, height * 0.5, z)))
			for h in _space.intersect_shape(q, 8):
				var c = h.get("collider")
				if c:
					seen["%s @ z=%.1f" % [_path_from(target, c), z]] = true
		z += STEP
	return seen.keys()

## A readable name: the node's path relative to the level, so "Crate_18" and
## "Ramp_02/Solid" are told apart at a glance.
func _path_from(target: Node3D, c: Object) -> String:
	var n := c as Node
	if n == null:
		return str(c)
	var parent := target.get_parent()
	return str(parent.get_path_to(n)) if parent and parent.is_ancestor_of(n) else n.name

## How many cross-sections along the passage a capsule of `height` cannot get
## through AT ALL.
##
## A cross-section only counts as blocked when EVERY lateral offset is blocked.
## Counting a section the moment any one offset collides is the obvious version
## and it is wrong: a gate's jambs sit 1 m either side of the opening, so the
## outer samples always collide and every gate reads as sealed to a crouching
## player. What is being asked is whether a way through exists, not whether the
## centre line happens to be clear.
func _blocked_span(target: Node3D, height: float) -> int:
	var cap := CapsuleShape3D.new()
	# A hair under, so brushing a wall in passing is not counted as blocked.
	cap.radius = RADIUS - 0.03
	cap.height = height - 0.04
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collide_with_areas = false
	q.exclude = _ignore
	var hits := 0
	var z := FROM
	while z <= TO:
		var any_clear := false
		for x: float in LATERAL:
			# Capsule sits on the floor, so its centre is half its height up.
			var p := target.to_global(Vector3(x, height * 0.5, z))
			q.transform = Transform3D(Basis.IDENTITY, p)
			if _space.intersect_shape(q, 1).is_empty():
				any_clear = true
				break
		if not any_clear:
			hits += 1
		z += STEP
	return hits
