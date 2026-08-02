extends SceneTree

## Writes res://scenes/chest.tscn.
##
##   Godot --headless --path . -s tools/build_chest_scene.gd
##
## The collider is measured from the model's world bounds at build time rather
## than typed in, so a re-export or a scale change cannot leave the box wrong.

const MODEL := "res://assets/chest/TreasureChest.FBX"
const SCRIPT := "res://scripts/chest.gd"
const OUT := "res://scenes/chest.tscn"

func _init() -> void:
	var probe := (load(MODEL) as PackedScene).instantiate()
	get_root().add_child(probe)
	await process_frame

	var lo := Vector3.INF
	var hi := -Vector3.INF
	for n in probe.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var ab := mi.mesh.get_aabb()
		var t := mi.global_transform
		for c in range(8):
			var p: Vector3 = t * (ab.position + ab.size * Vector3(
				float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1)))
			lo = lo.min(p)
			hi = hi.max(p)
	var size := hi - lo
	var mid := (lo + hi) * 0.5
	print("chest world bounds %.3v .. %.3v  size %.3v" % [lo, hi, size])
	probe.queue_free()

	var body := StaticBody3D.new()
	body.name = "Chest"
	body.add_to_group("interactable", true)
	body.set_script(load(SCRIPT))

	var model := (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	body.add_child(model)
	model.owner = body

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = body
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = mid

	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		print("pack failed: ", err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	print("saved %s err=%d" % [OUT, err])
	quit()
