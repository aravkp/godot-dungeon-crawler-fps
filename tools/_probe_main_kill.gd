extends SceneTree

## Throwaway probe: loads the real main.tscn, finds a hand-placed watcher in its
## camp, kills it, and sheets the death against actual terrain and lighting.
## The synthetic-floor probe cannot catch a camp node's own transform feeding
## into the skeleton scale, which is the thing most likely to break this.
## Needs a real display server - do NOT run with --headless.
##
##   Godot --path . -s tools/_probe_main_kill.gd

const OUT := "res://.shots/main_kill.png"
const CELL := 220
const COLS := 6
const ROWS := 3
const EVERY := 12   # physics frames per cell = 0.20s

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var root := packed.instantiate()
	# player.gd captures the mouse in _ready(), which would eat the real
	# trackpad for the length of the run. Same trick shot_terrain.gd uses.
	var p := root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	# The horde would otherwise wander through frame during the shot.
	var spawner := root.find_child("BatSpawner", true, false)
	if spawner:
		spawner.set("enabled", false)
	get_root().add_child(root)
	for _i in range(30):
		await physics_frame

	var watcher: Node3D = null
	for n in root.find_children("*", "CharacterBody3D", true, false):
		if n.is_in_group("watchers"):
			watcher = n
			break
	if watcher == null:
		print("no watcher in main.tscn - has build_terrain.gd been run?")
		quit(1)
		return
	print("watcher: ", root.get_path_to(watcher), " at %.2v" % watcher.global_position)
	for sib in watcher.get_parent().get_children():
		if sib != watcher:
			print("  camp sibling %s at %.2v  (%.2fm away)"
				% [sib.name, sib.global_position,
					sib.global_position.distance_to(watcher.global_position)])
	# Anything solid within 3m that the corpse could be squeezed out of.
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 3.0
	q.shape = sph
	q.transform = Transform3D(Basis(), watcher.global_position + Vector3.UP)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	for h in watcher.get_world_3d().direct_space_state.intersect_shape(q, 32):
		var c = h["collider"]
		print("  near: %s [%s] layer=%d at %.2v"
			% [c.name, c.get_class(), c.collision_layer, c.global_position])
	if OS.get_cmdline_user_args().has("solo"):
		for sib in watcher.get_parent().get_children():
			if sib != watcher:
				sib.free()
		print("  -> siblings removed")
	var sk: Skeleton3D = watcher.find_children("*", "Skeleton3D", true, false)[0]
	print("camp parent: ", watcher.get_parent().name,
		"  skeleton global scale: ", sk.global_transform.basis.get_scale())

	var cam := Camera3D.new()
	cam.fov = 50
	get_root().add_child(cam)
	cam.current = true
	var focus: Vector3 = watcher.global_position + Vector3.UP * 0.9
	cam.look_at_from_position(focus + Vector3(2.6, 0.9, 2.6), focus, Vector3.UP)

	watcher.take_hit(3, watcher.global_position + Vector3(0, 1.25, 0),
		Vector3(0.3, 0.2, 1.0).normalized())

	var sheet := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	for i in range(COLS * ROWS):
		for _s in range(EVERY):
			await physics_frame
		# Re-assert: main.tscn ships its own Camera3D and it must not win.
		cam.current = true
		cam.look_at_from_position(focus + Vector3(2.6, 0.9, 2.6), focus, Vector3.UP)
		await process_frame
		var img := get_root().get_texture().get_image()
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
		var where := "freed"
		if is_instance_valid(watcher):
			var sim := watcher.find_child("Ragdoll", true, false)
			where = "body=%.2v" % watcher.global_position
			if sim:
				for c in sim.get_children():
					if c is PhysicalBone3D:
						where += "  hips=%.2v" % (c as PhysicalBone3D).global_position
						break
		print("cell %2d  t=%.2f  active_cam=%s  %s" % [i, float((i + 1) * EVERY) / 60.0,
			get_root().get_camera_3d() == cam, where])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()
