extends SceneTree

## Writes res://scenes/watcher.tscn - the Watcher of the Hollow Eye enemy.
##
##   Godot --headless --path . -s tools/build_watcher_scene.gd
##
## The FBX is NOT authored at its origin: the bind pose sits ~3.2 units out in
## +Z and is 2.36 units tall. Both are measured here from bone global poses
## rather than hardcoded, because a mesh-local AABB on a skinned model is
## meaningless. If the asset is ever re-exported this still lands on its feet.

const MODEL := "res://assets/watcher/watcher.fbx"
const SCRIPT := "res://scripts/watcher_enemy.gd"
const OUT := "res://scenes/watcher.tscn"

## Player is 2.0m. A shade shorter reads as a goblin rather than an ogre.
const TARGET_HEIGHT := 1.9
const BODY_RADIUS := 0.45

func _init() -> void:
	var probe := (load(MODEL) as PackedScene).instantiate()
	get_root().add_child(probe)
	await process_frame

	var sk: Skeleton3D = null
	for n in probe.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk == null:
		print("no Skeleton3D in ", MODEL)
		quit(1)
		return

	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in range(sk.get_bone_count()):
		var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	var height: float = maxf(hi.y - lo.y, 0.001)
	var scale_f := TARGET_HEIGHT / height
	print("bind pose: %.3v .. %.3v" % [lo, hi])
	print("height %.3f -> scale %.4f" % [height, scale_f])
	probe.queue_free()

	var body := CharacterBody3D.new()
	body.name = "Watcher"
	body.add_to_group("enemies", true)
	body.add_to_group("watchers", true)
	body.set_script(load(SCRIPT))

	var model := (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	body.add_child(model)
	model.owner = body
	# Re-centre on XZ and drop the feet to y=0, then scale about that origin.
	var mid := (lo + hi) * 0.5
	model.scale = Vector3.ONE * scale_f
	model.position = Vector3(-mid.x, -lo.y, -mid.z) * scale_f

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = body
	var cap := CapsuleShape3D.new()
	cap.radius = BODY_RADIUS
	cap.height = TARGET_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, TARGET_HEIGHT * 0.5, 0)

	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		print("pack failed: ", err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	print("saved %s err=%d  model_offset=%.3v scale=%.4f"
		% [OUT, err, model.position, scale_f])
	quit()
