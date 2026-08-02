extends SceneTree

## Throwaway probe: smashes one prop in corridors.tscn and sheets it coming
## apart, from where the player would be standing.
##
## The numbers in _probe_smash.gd prove the chunks exist, fall and settle. They
## cannot show whether the pile reads as the thing that was standing there - that
## the boards look like crate boards, that the debris is not a cloud of grey
## cubes, that the chunks are not comically large or small for the prop.
##
## Needs a real display server - do NOT run with --headless.
##
##   Godot --path . -s tools/_probe_shatter.gd -- [Crate_1|Gate_00|DaggerChest] [every]

const OUT := "res://.shots/shatter_%s.png"
const CELL := 260
const COLS := 4
const ROWS := 3

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var want: String = args[0] if args.size() > 0 else "Crate_1"
	var every: int = maxi(1, int(args[1]) if args.size() > 1 else 5)

	Engine.max_fps = 60
	var root := (load("res://scenes/corridors.tscn") as PackedScene).instantiate()
	var p := root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	get_root().add_child(root)
	for _i in range(20):
		await physics_frame

	var target := root.find_child(want, true, false) as Node3D
	if target == null:
		print("no node named ", want)
		quit(1)
		return
	# A gate's door is the breakable, not the gate node itself.
	var hit_me: Node = target
	if target.get_node_or_null("Door"):
		hit_me = target.get_node("Door")
	var focus: Vector3 = (hit_me as Node3D).global_position + Vector3(0, 0.6, 0)

	var cam := Camera3D.new()
	cam.fov = 70
	get_root().add_child(cam)
	cam.current = true
	# Stand back roughly where a player swinging at it would be. A gate fills the
	# whole 4x4 m corridor cross-section, so a diagonal close-up puts the camera
	# inside the doorway - it gets framed head-on from the approach side instead,
	# the way shot_corridors.gd frames one.
	var eye := focus + Vector3(1.9, 1.1, 1.9)
	if target.name.begins_with("Gate_"):
		focus = target.global_position + Vector3(0, 1.5, 0)
		eye = focus - target.global_transform.basis.z * 5.5 + Vector3(0, 0.2, 0)
	cam.look_at_from_position(eye, focus, Vector3.UP)
	print("%s at %.2v  hits=%s" % [want, focus, hit_me.get("hits")])

	var sheet := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	var struck := false
	for i in range(COLS * ROWS):
		if not struck:
			struck = true
			# Enough damage to break it outright, from the camera's direction.
			var dir := (focus - eye).normalized()
			hit_me.call("take_hit", 99, focus, dir)
		for _s in range(every):
			await physics_frame
		cam.current = true
		await process_frame
		var img := get_root().get_texture().get_image()
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
		print("  cell %2d  t=%.2f" % [i, float((i + 1) * every) / 60.0])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	var path := OUT % want.to_lower()
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("wrote ", path)
	quit()
