extends SceneTree

## Throwaway probe: runs the opening cutscene end to end and sheets it.
##
##   Godot --path . -s tools/_probe_cutscene.gd -- [frames-per-cell]
##
## Needs a real display server - do NOT run with --headless: the text is the
## thing under test, and the dummy server draws none of it.
##
## player.gd is left ATTACHED here, unlike every other probe in this folder,
## because the assertion that matters is the one a screenshot cannot make -
## that the player is frozen while the thing is talking and gets control back
## afterwards. Mouse mode is forced visible every frame instead, or the preview
## window swallows the real trackpad.
##
## Lines are advanced with real E presses through Input.parse_input_event, so the
## path under test is the one the player uses.

const OUT := "res://.shots/cutscene.png"
const CELL := 300
const COLS := 4
const ROWS := 3

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var every: int = maxi(1, int(args[0]) if args.size() > 0 else 26)

	Engine.max_fps = 60
	var root := (load("res://scenes/corridors.tscn") as PackedScene).instantiate()
	get_root().add_child(root)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var cut := root.get_node_or_null("Cutscene")
	var player := root.get_node_or_null("Player")
	var warden := root.find_child("Warden", true, false) as Node3D
	if cut == null or player == null:
		print("FAIL: cutscene=%s player=%s" % [cut, player])
		quit(1)
		return
	await physics_frame
	if warden:
		print("  warden at %.2v  scale %.3v  %.2f m from the player" % [
			warden.global_position, warden.scale,
			warden.global_position.distance_to((player as Node3D).global_position)])
	else:
		print("  FAIL: no Warden")

	var sheet := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	var froze := false
	for i in range(COLS * ROWS):
		for _s in range(every):
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			await physics_frame
			# Advance whenever the current line has finished typing, the same as
			# leaning on E. The tell is the [E] hint appearing - visible_characters
			# ends up equal to the line length, not -1, so testing for -1 waits
			# forever.
			if cut.get("_started") and not cut.get("_done"):
				var hint := cut.get("_hint") as Label
				if hint and hint.visible:
					_press()
		if not player.is_physics_processing():
			froze = true
		await process_frame
		var img := get_root().get_texture().get_image()
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
		print("  cell %2d  t=%5.2f  line=%s  done=%s  player frozen=%s" % [i,
			float((i + 1) * every) / 60.0, cut.get("_i"), cut.get("_done"),
			not player.is_physics_processing()])

	# The whole point of freezing is that it ends.
	for _s in range(30):
		await physics_frame
	print("\n  froze at some point:   %s  (must be true)" % froze)
	print("  player physics back:   %s  (must be true)" % player.is_physics_processing())
	print("  player input back:     %s  (must be true)" % player.is_processing_unhandled_input())
	var arms := player.find_child("Arms", true, false)
	if arms:
		print("  arms process back:     %s  (must be true)" % arms.is_processing())
	print("  warden hidden after:   %s  (must be true)"
		% (not warden.visible if warden else "no warden"))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()

func _press() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_E
	e.physical_keycode = KEY_E
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventKey.new()
	up.keycode = KEY_E
	up.physical_keycode = KEY_E
	up.pressed = false
	Input.parse_input_event(up)
