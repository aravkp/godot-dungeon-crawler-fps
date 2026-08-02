extends SceneTree

## Throwaway probe: drops a watcher on a floor, kills it, and renders the death
## as a contact sheet. Needs a real display server - do NOT run with --headless.
##
##   Godot --path . -s tools/_probe_ragdoll.gd -- [steps_between_cells]
##
## Time is counted in PHYSICS frames, not process frames, so the sampling is
## deterministic regardless of how fast the window happens to render.

const SCENE := "res://scenes/watcher.tscn"
const OUT := "res://.shots/ragdoll.png"
const CELL := 200
const COLS := 6
const ROWS := 4

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var every := int(args[0]) if args.size() > 0 else 9   # 0.15s at 60Hz

	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.environment = e
	vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 40, 0)
	key.light_energy = 1.7
	vp.add_child(key)

	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(24, 1, 24)
	gs.shape = box
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	var gm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	gm.mesh = bm
	gm.position = gs.position
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.26, 0.24, 0.28)
	gm.material_override = gmat
	ground.add_child(gm)
	vp.add_child(ground)

	var cam := Camera3D.new()
	var eye := Vector3(1.9, 1.15, 2.1)
	cam.look_at_from_position(eye, Vector3(0, 0.45, 0), Vector3.UP)
	cam.fov = 50
	vp.add_child(cam)
	cam.current = true

	var w := (load(SCENE) as PackedScene).instantiate()
	vp.add_child(w)
	for _i in range(20):
		await physics_frame

	# Killed from the front, chest height - three hits at once.
	var chest: Vector3 = w.global_position + Vector3(0, 1.25, 0.25)
	var landed: bool = w.take_hit(3, chest, Vector3(0, 0.25, -1).normalized())
	print("take_hit -> ", landed)
	var sim := w.find_child("Ragdoll", true, false)
	print("ragdoll node: ", sim)
	if sim:
		print("simulating: ", sim.is_simulating_physics())
		for c in sim.get_children():
			if c is PhysicalBone3D:
				var pb := c as PhysicalBone3D
				var cap: CapsuleShape3D = pb.get_child(0).shape
				print("  %-22s r=%.3f h=%.3f  world_scale=%.3v  pos=%.2v"
					% [pb.name, cap.radius, cap.height,
						pb.global_transform.basis.get_scale(), pb.global_position])

	var sheet := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	for i in range(COLS * ROWS):
		for _s in range(every):
			await physics_frame
		await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
		var alive := is_instance_valid(w)
		print("cell %d  t=%.2fs  valid=%s%s" % [i, float((i + 1) * every) / 60.0,
			alive, ("  hips_y=%.3f" % _hips_y(w)) if alive else ""])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()

func _hips_y(w: Node) -> float:
	var sim := w.find_child("Ragdoll", true, false)
	if sim == null:
		return NAN
	for c in sim.get_children():
		if c is PhysicalBone3D:
			return (c as PhysicalBone3D).global_position.y
	return NAN
