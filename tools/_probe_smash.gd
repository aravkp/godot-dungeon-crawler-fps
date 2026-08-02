extends SceneTree

## Throwaway probe: proves the corridor level's destructibles actually come
## apart, and - the part that matters - that a smashed door leaves a hole the
## player can walk through.
##
##   Godot --headless --path . -s tools/_probe_smash.gd
##
## Runs headless on purpose: nothing here needs input or a rendered frame, only
## physics. Everything is driven through take_hit(), the same entry point
## arms.gd's melee ray uses.

const SCENE := "res://scenes/corridors.tscn"
## Waist height on the player capsule (r 0.5, h 2), i.e. the line a body has to
## get through.
const EYE := 1.0

var _root: Node

func _init() -> void:
	_root = (load(SCENE) as PackedScene).instantiate()
	# player.gd captures the mouse in _ready(); strip it before the scene enters
	# the tree, the same trick shot_terrain.gd uses.
	var p := _root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	get_root().add_child(_root)
	for _i in range(10):
		await physics_frame

	await _test_door()
	await _test_open()
	await _test_crate()
	await _test_chest()
	quit()

func _test_door() -> void:
	var gate := _root.find_child("Gate_00", true, false) as Node3D
	if gate == null:
		print("FAIL: no Gate_00 - run tools/build_corridors.gd")
		return
	var door := gate.get_node_or_null("Door")
	if door == null:
		print("FAIL: Gate_00 has no Door")
		return
	print("\n--- door ---")
	print("  gate at %.2v  hits=%d" % [gate.global_position, door.get("hits")])
	# Straight through the doorway, along the gate's local Z (the direction of
	# travel), from 3m before it to 3m after.
	var through: Vector3 = gate.global_transform.basis.z.normalized()
	var mid := gate.global_position + Vector3(0, EYE, 0)
	print("  blocked before: %s" % _blocked(mid - through * 3.0, mid + through * 3.0, door))
	# Also check the jamb is solid, so the gate is not simply missing collision.
	var jamb_a := mid - through * 3.0 + gate.global_transform.basis.x * 1.5
	var jamb_b := mid + through * 3.0 + gate.global_transform.basis.x * 1.5
	print("  jamb solid:     %s" % _blocked(jamb_a, jamb_b, null))

	for i in range(4):
		if not is_instance_valid(door):
			break
		var landed: bool = door.take_hit(1, mid, through)
		print("  hit %d -> landed=%s hits_left=%s"
			% [i + 1, landed, door.get("hits") if is_instance_valid(door) else "gone"])
		await physics_frame
		await physics_frame
	print("  door freed:     %s" % not is_instance_valid(door))
	print("  blocked after:  %s" % _blocked(mid - through * 3.0, mid + through * 3.0, null))

## The other way through a gate: [E] instead of a swing. Uses a DIFFERENT gate
## from the smash test, so the two routes are proved independently.
##
## The assertion that matters is the same one - blocked before, clear after - but
## for a door that still exists. A leaf that plays its rise while leaving the
## collider behind looks perfect and seals the corridor exactly as before.
func _test_open() -> void:
	var gate := _root.find_child("Gate_01", true, false) as Node3D
	if gate == null:
		print("\nFAIL: no Gate_01")
		return
	var door := gate.get_node_or_null("Door")
	if door == null:
		print("\nFAIL: Gate_01 has no Door")
		return
	print("\n--- door, opened with E ---")
	var through: Vector3 = gate.global_transform.basis.z.normalized()
	var mid := gate.global_position + Vector3(0, EYE, 0)
	print("  prompt before:  '%s'" % door.call("prompt"))
	print("  blocked before: %s" % _blocked(mid - through * 3.0, mid + through * 3.0, null))
	print("  interact:       %s" % door.call("interact", null))
	print("  interact again: %s  (must be false - it lifts once)"
		% door.call("interact", null))
	# lift_time is 0.9s; give the tween a little past it.
	for _i in range(70):
		await physics_frame
	print("  prompt after:   '%s'  (must be empty)" % door.call("prompt"))
	print("  door still alive: %s  risen %.2f m"
		% [is_instance_valid(door), (door as Node3D).position.y])
	print("  blocked after:  %s" % _blocked(mid - through * 3.0, mid + through * 3.0, null))

func _test_crate() -> void:
	var crate: Node3D = null
	for n in _root.find_children("Crate_*", "StaticBody3D", true, false):
		crate = n as Node3D
		break
	if crate == null:
		print("\nFAIL: no crates in the level")
		return
	print("\n--- crate ---")
	print("  %s hits=%d" % [crate.name, crate.get("hits")])
	# Every pile in the level is called Shatter*, and the door tests above left
	# theirs lying there - so note which ones already exist and report only the
	# new pile. Without this the crate's 8 cubes were counted together with the
	# door's 16 planks, and the planks aged out mid-measurement.
	var before: Dictionary = {}
	for n in _root.find_children("Shatter*", "Node3D", true, false):
		before[n.get_instance_id()] = true
	var at: Vector3 = crate.global_position + Vector3(0, 0.4, 0)
	for i in range(3):
		if not is_instance_valid(crate):
			break
		crate.take_hit(1, at, Vector3.FORWARD)
		print("  hit %d -> hits_left=%s"
			% [i + 1, crate.get("hits") if is_instance_valid(crate) else "gone"])
		await physics_frame
		await physics_frame
	print("  crate freed:    %s" % not is_instance_valid(crate))
	await _report_chunks("crate", before)

## The one that could actually break the level: smashing the dagger chest must
## still yield the dagger, or the run is unwinnable bare-fisted.
func _test_chest() -> void:
	var chest := _root.find_child("DaggerChest", true, false)
	if chest == null:
		print("\nFAIL: no DaggerChest")
		return
	print("\n--- dagger chest ---")
	print("  destructible=%s loot=%s hits=%d"
		% [chest.get("destructible"), chest.get("loot"), chest.get("hits")])
	var at: Vector3 = (chest as Node3D).global_position + Vector3(0, 0.45, 0)
	for i in range(6):
		if not is_instance_valid(chest):
			break
		chest.take_hit(1, at, Vector3.FORWARD)
		await physics_frame
		await physics_frame
	print("  chest freed:    %s" % not is_instance_valid(chest))
	# The chest finds its box by type rather than by name (build_chest_scene.gd
	# measures it), so its path into shatter.gd is a different one worth checking.
	print("  shatter nodes:  %d" % _root.find_children("Shatter*", "Node3D", true, false).size())
	var spilled: Array[String] = []
	for n in get_root().get_tree().get_nodes_in_group("pickups"):
		spilled.append("%s at %.2v" % [n.name, (n as Node3D).global_position])
	print("  pickups now:    %s" % str(spilled))

## The chunks a smash leaves behind: how many, and whether they actually settle
## on the floor rather than falling through it or hanging in the air. Debris that
## never comes to rest is the failure mode a still cannot show.
func _report_chunks(what: String, skip: Dictionary = {}) -> void:
	var fx: Array[Node] = []
	for n in _root.find_children("Shatter*", "Node3D", true, false):
		if not skip.has(n.get_instance_id()):
			fx.append(n)
	if fx.is_empty():
		print("  FAIL: %s left no chunks" % what)
		return
	var bodies: Array[RigidBody3D] = []
	for f in fx:
		for c in f.get_children():
			if c is RigidBody3D:
				bodies.append(c as RigidBody3D)
	var y0 := 0.0
	for b in bodies:
		y0 += b.global_position.y
	y0 /= float(bodies.size())
	print("  chunks:         %d  (layer=%d mask=%d)  mean y=%.2f"
		% [bodies.size(), bodies[0].collision_layer, bodies[0].collision_mask, y0])
	for _i in range(150):        # 2.5s at 60Hz - long enough to land and settle
		await physics_frame
	var lo := 1e9
	var hi := -1e9
	var alive := 0
	var moving := 0
	for b in bodies:
		if not is_instance_valid(b):
			continue
		alive += 1
		lo = minf(lo, b.global_position.y)
		hi = maxf(hi, b.global_position.y)
		if b.linear_velocity.length() > 0.15:
			moving += 1
	print("  after 2.5s:     %d alive, y %.2f..%.2f, %d still moving"
		% [alive, lo, hi, moving])
	# Past linger + fade (3.0 + 0.6): the pile has to clean itself up, or a long
	# run accumulates rigid bodies for the rest of the level.
	for _i in range(120):
		await physics_frame
	var left := 0
	for b in bodies:
		if is_instance_valid(b):
			left += 1
	print("  after 4.5s:     %d alive  (want 0)" % left)

## Whether a straight line from a to b hits anything, ignoring `skip` (used to
## look past the door itself while it still exists).
##
## Actors are excluded: a watcher standing in the doorway is not the doorway
## being blocked, and one drifting into the ray made "blocked after" report an
## enemy instead of "clear". What is under test is the level geometry.
func _blocked(a: Vector3, b: Vector3, skip: Object) -> String:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = _actor_rids()
	var hit := _root.get_viewport().get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return "clear"
	var c = hit.get("collider")
	if c == skip:
		return "the door itself (%s)" % c.get_parent().name
	return "%s [%s]" % [c.name, c.get_class()]

## Every moving body in the level, as physics RIDs for a ray's exclude list.
func _actor_rids() -> Array[RID]:
	var out: Array[RID] = []
	for n in _root.find_children("*", "CharacterBody3D", true, false):
		out.append((n as CollisionObject3D).get_rid())
	return out
