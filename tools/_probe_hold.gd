extends SceneTree

## Throwaway probe: holds the attack button down and watches the viewmodel, both
## as numbers (which clip, where the playhead is, when a new swing starts) and as
## a contact sheet from the player's own camera.
##
## What it is checking:
##   - a held button keeps swinging, bare-fisted and with the dagger
##   - the swings ALTERNATE (jab_L, jab_R, jab_L ... / knife_hit_01, _02, _01)
##   - the idle never appears between two swings. That gap is the thing the
##     chain in _on_animation_finished exists to close, and it is invisible in
##     a still - it shows up here as a `guard_idle` row mid-run.
##
## The button is faked with Input.parse_input_event(), which updates the same
## button mask Input.is_mouse_button_pressed() reads - so arms.gd's real
## hold path runs, rather than the probe standing in for it. That needs the mouse
## captured and a real display server, so do NOT run with --headless. If the mask
## does not take, it falls back to calling attack() per frame and says so.
##
##   Godot --path . -s tools/_probe_hold.gd -- [frames] [every]
##
## `every` is how many frames per sheet cell. The numbers are printed for every
## frame regardless; at 1 a run long enough to show alternation makes cells too
## small to see, so pass 3 or 4 to judge the motion.

const OUT := "res://.shots/hold.png"
const CELL := 200
const COLS := 6

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[0]) if args.size() > 0 else 48
	var every: int = maxi(1, int(args[1]) if args.size() > 1 else 1)

	# Uncapped, a windowed run advances almost no animation time per frame, and
	# the cadence under test is in seconds.
	Engine.max_fps = 60

	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	var spawner := root.find_child("BatSpawner", true, false)
	if spawner:
		spawner.set("enabled", false)
	get_root().add_child(root)
	await process_frame

	var arms := root.find_child("Arms", true, false)
	var ap: AnimationPlayer = arms.get_node("AnimationPlayer")
	var cam: Camera3D = root.find_child("Camera3D", true, false)
	cam.current = true
	print("attack_button=%s (LEFT=%d)  attack_speed=%.2f  hold_to_repeat=%s"
		% [arms.get("attack_button"), MOUSE_BUTTON_LEFT,
			arms.get("attack_speed"), arms.get("hold_to_repeat")])

	# arms.gd ignores input unless the mouse is captured, and the headless
	# display server ignores Input.mouse_mode entirely.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	var real_hold := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	print("faked button registered in the input mask: %s%s"
		% [real_hold, "" if real_hold else "  (falling back to attack() per frame)"])

	var cells := int(ceil(float(frames) / float(every)))
	var rows := int(ceil(float(cells) / float(COLS)))
	var sheet := Image.create(CELL * COLS, CELL * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)

	# Loot the dagger halfway through, mid-hold: the swap has to survive the
	# button already being down.
	# Two thirds of the way in, so there is room for several bare-fisted swings
	# before it and several dagger ones after.
	var swap_at := (frames * 2) / 3
	var order: Array[String] = []
	var idle_rows := 0
	var swings := 0
	# A new swing is a clip that just started - either a different clip, or the
	# same one rewound. Watching arms' own _next_swing counter instead would
	# misread unlock_dagger(), which resets it.
	var prev_clip := ""
	var prev_pos := 0.0
	print("\n frame   t     clip           playhead  swing")
	for i in range(frames):
		if i == swap_at:
			arms.call("unlock_dagger")
			print("  -- dagger looted --")
		if not real_hold:
			arms.call("attack")
		await process_frame
		if i % every == 0:
			var cell := i / every
			var img := get_root().get_texture().get_image()
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i((cell % COLS) * CELL, (cell / COLS) * CELL))

		var clip: String = ap.current_animation
		var pos := ap.current_animation_position
		var attacking := clip != "guard_idle" and clip != "knife_idle"
		var started := attacking and (clip != prev_clip or pos < prev_pos)
		if started:
			swings += 1
			order.append(clip)
		prev_clip = clip
		prev_pos = pos
		# The opening frame is legitimately the idle; after that it is the gap.
		if i > 1 and (clip == "guard_idle" or clip == "knife_idle"):
			idle_rows += 1
		print(" %4d  %5.2f  %-14s  %6.3f    %s"
			% [i, float(i) / 60.0, clip, pos, "SWING" if started else ""])

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("\nswings: %d over %.2fs  ->  %.2f per second"
		% [swings, float(frames) / 60.0, float(swings) / (float(frames) / 60.0)])
	print("order: %s" % str(order))
	print("idle frames between swings: %d  (want 0)" % idle_rows)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()
