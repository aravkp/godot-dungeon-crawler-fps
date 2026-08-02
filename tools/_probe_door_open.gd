extends SceneTree

## Throwaway probe: a gate being opened with [E], as a contact sheet.
##
##   Godot --path . -s tools/_probe_door_open.gd -- [Gate_01] [frames-per-cell]
##
## Needs a real display server - do NOT run with --headless.
##
## _probe_smash.gd proves the collider leaves the doorway. It cannot show the
## thing this is actually for: whether the leaf reads as a portcullis going up
## rather than as a door dropping through the floor or vanishing, and whether it
## clears the frame instead of stopping with a slab of door in the top of the gap.

const OUT := "res://.shots/door_open.png"
const CELL := 260
const COLS := 4
const ROWS := 3

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var want: String = args[0] if args.size() > 0 else "Gate_01"
	var every: int = maxi(1, int(args[1]) if args.size() > 1 else 6)

	Engine.max_fps = 60
	var root := (load("res://scenes/corridors.tscn") as PackedScene).instantiate()
	var p := root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	get_root().add_child(root)
	for _i in range(20):
		await physics_frame

	var gate := root.find_child(want, true, false) as Node3D
	if gate == null:
		print("no node named ", want)
		quit(1)
		return
	var door := gate.get_node_or_null("Door")
	if door == null:
		print("%s has no Door" % want)
		quit(1)
		return

	# Head-on from the approach side, standing back about where the [E] prompt
	# starts answering (interact_range is 3.5 m).
	var focus: Vector3 = gate.global_position + Vector3(0, 1.6, 0)
	var eye: Vector3 = focus - gate.global_transform.basis.z * 3.2 + Vector3(0, 0.1, 0)
	var cam := Camera3D.new()
	cam.fov = 70
	get_root().add_child(cam)
	cam.current = true
	cam.look_at_from_position(eye, focus, Vector3.UP)

	var sheet := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	var pressed := false
	for i in range(COLS * ROWS):
		# One cell of "before" so the sheet shows what it looked like shut.
		if i == 1 and not pressed:
			pressed = true
			print("  interact -> %s" % door.call("interact", null))
		for _s in range(every):
			await physics_frame
		cam.current = true
		await process_frame
		var img := get_root().get_texture().get_image()
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
		var y: float = (door as Node3D).position.y if is_instance_valid(door) else -1.0
		print("  cell %2d  t=%.2f  door y=%.2f" % [i, float((i + 1) * every) / 60.0, y])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()
