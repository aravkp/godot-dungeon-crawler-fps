extends SceneTree

## Generates res://scenes/bat.tscn, the horde enemy that bat_spawner.gd clones.
##
##   Godot --headless --path . -s tools/build_bat_scene.gd
##
## Reference width is measured DURING the idle animation (9.17 units); the rest
## pose reads 14.06 because the ear-wings are spread wider there.

const MODEL := "res://assets/chonchon/chonchon.fbx"
const ENEMY_SCRIPT := "res://scripts/bat_enemy.gd"
const IDLE_WIDTH := 9.1687
const WINGSPAN := 1.0            # metres, ear tip to ear tip
const BONE_CENTRE := Vector3(-0.563188, 0.821415, 2.552688)

func _init() -> void:
	var body := CharacterBody3D.new()
	body.name = "Bat"
	body.set_script(load(ENEMY_SCRIPT))
	body.add_to_group("enemies", true)
	# "bats" is what the spawner caps on - see bat_spawner.alive_count().
	body.add_to_group("bats", true)
	# It flies; the grounded motion mode would try to snap it to a floor.
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	var model := (load(MODEL) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	body.add_child(model)
	model.owner = body
	var s := WINGSPAN / IDLE_WIDTH
	model.scale = Vector3(s, s, s)
	model.position = -BONE_CENTRE * s

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = body
	var sphere := SphereShape3D.new()
	sphere.radius = 0.38
	cs.shape = sphere

	var packed := PackedScene.new()
	var err := packed.pack(body)
	if err != OK:
		print("pack failed: ", err); quit(1); return
	err = ResourceSaver.save(packed, "res://scenes/bat.tscn")
	print("saved scenes/bat.tscn err=", err)
	quit()
