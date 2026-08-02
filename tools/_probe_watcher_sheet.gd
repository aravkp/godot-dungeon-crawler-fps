extends SceneTree

## Throwaway probe: renders the watcher's baked take as one contact sheet so the
## CLIPS ranges can be read off by eye instead of inferred from bone numbers.
## Needs a real display server - do NOT run with --headless.
##
##   Godot --path . -s tools/_probe_watcher_sheet.gd [from] [to] [cols] [rows]

const SCENE := "res://scenes/watcher.tscn"
const OUT := "res://.shots/watcher_take.png"
const CELL := 168

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var from := float(args[0]) if args.size() > 0 else 0.0
	var to := float(args[1]) if args.size() > 1 else -1.0
	var cols := int(args[2]) if args.size() > 2 else 8
	var rows := int(args[3]) if args.size() > 3 else 8
	var out: String = OUT if args.size() < 5 else "res://.shots/%s.png" % args[4]

	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 1.0
	env.environment = e
	vp.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-32, 38, 0)
	key.light_energy = 1.6
	vp.add_child(key)

	var w := (load(SCENE) as PackedScene).instantiate()
	w.set_script(null)
	vp.add_child(w)
	await process_frame

	var ap: AnimationPlayer = null
	for n in w.find_children("*", "AnimationPlayer", true, false):
		ap = n
		break
	var anim := ap.get_animation("all")
	if to < 0.0:
		to = anim.length

	# 3/4 view: reads both the arm arc and the leg stride.
	var cam := Camera3D.new()
	cam.position = Vector3(2.4, 1.35, 3.0)
	cam.look_at_from_position(Vector3(2.4, 1.35, 3.0), Vector3(0, 0.95, 0), Vector3.UP)
	cam.fov = 46
	vp.add_child(cam)
	cam.current = true

	ap.play("all")
	ap.speed_scale = 0.0

	var sheet := Image.create(CELL * cols, CELL * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	var font := ThemeDB.fallback_font
	var n := cols * rows
	for i in range(n):
		var t: float = from + (to - from) * (float(i) / float(maxi(n - 1, 1)))
		ap.seek(t, true)
		await process_frame
		await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var col := i % cols
		var row := i / cols
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(col * CELL, row * CELL))
		print("cell %d,%d  t=%.2f" % [col, row, t])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out, "  range %.2f..%.2f  grid %dx%d" % [from, to, cols, rows])
	quit()
