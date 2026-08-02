extends SceneTree

## Throwaway probe: the retro character's unnamed clips as pictures.
##
##   Godot --path . -s tools/_probe_character_sheet.gd -- [first] [count]
##
## Needs a real display server - do NOT run with --headless.
##
## _probe_character_clips.gd narrows what each clip might be; only a picture
## settles it. One row per clip, PHASES poses across the row, in a bare scene so
## nothing but the character is in frame.

const SRC := "res://assets/retro_character/retro_character.fbx"
const OUT := "res://.shots/retro_clips_%d.png"
const CELL := 220
const PHASES := 5

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var first: int = int(args[0]) if args.size() > 0 else 0
	var count: int = int(args[1]) if args.size() > 1 else 8

	Engine.max_fps = 60
	var root := (load(SRC) as PackedScene).instantiate()
	get_root().add_child(root)
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D

	# A plain lit stage: the FBX brings no lighting and no texture binding.
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.4
	get_root().add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 45
	get_root().add_child(cam)
	cam.current = true
	# Frame the whole rig from bone bounds - the mesh AABB of a skinned model is
	# useless, per the project's own rule.
	await process_frame
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in range(skel.get_bone_count()):
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	var mid := (lo + hi) * 0.5
	var h: float = maxf(hi.y - lo.y, 1.0)
	# Three-quarter front, so a punch reads as a punch and a stride as a stride.
	# Close enough that a hand pose is legible at CELL px. The first pass framed
	# from h*1.5 out and every clip came back as an unreadable white matchstick.
	cam.look_at_from_position(mid + Vector3(h * 0.5, h * 0.15, h * 0.85), mid, Vector3.UP)

	var list := ap.get_animation_list()
	var rows: Array = []
	for ci in range(first, mini(first + count, list.size())):
		if ap.get_animation(list[ci]).length > 0.001:
			rows.append(ci)
	var sheet := Image.create(CELL * PHASES, CELL * rows.size(), false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)

	for r in range(rows.size()):
		var ci: int = rows[r]
		var nm: String = list[ci]
		var anim := ap.get_animation(nm)
		ap.play(nm)
		for p in range(PHASES):
			var t: float = anim.length * float(p) / float(PHASES - 1)
			ap.seek(t, true)
			await process_frame
			await process_frame
			var img := get_root().get_texture().get_image()
			img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
				Vector2i(p * CELL, r * CELL))
		print("  row %d = clip %d  (%.2f s)  %s" % [r, ci, anim.length, nm])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	var path := OUT % first
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("wrote ", path)
	quit()
