extends SceneTree

## Throwaway probe: stands a watcher on a floor with a player 18m away, lets it
## spot him, and renders the chase - so "does it walk or does it swing" is
## answered by looking rather than by reading the state machine.
## Needs a real display server - do NOT run with --headless.
##
##   Godot --path . -s tools/_probe_chase.gd

const SCENE := "res://scenes/watcher.tscn"
const OUT := "res://.shots/chase.png"
const CELL := 200
const COLS := 6
const ROWS := 4
const EVERY := 15   # physics frames between cells = 0.25s

func _init() -> void:
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
	key.rotation_degrees = Vector3(-38, 20, 0)
	key.light_energy = 1.7
	vp.add_child(key)

	var ground := StaticBody3D.new()
	var gs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	gs.shape = box
	gs.position = Vector3(0, -0.5, 0)
	ground.add_child(gs)
	vp.add_child(ground)

	# The player only has to exist, be in the group, and be somewhere to walk to.
	var player := Node3D.new()
	player.add_to_group("player", true)
	vp.add_child(player)
	player.global_position = Vector3(0, 0, 18)

	var w := (load(SCENE) as PackedScene).instantiate()
	vp.add_child(w)
	w.global_position = Vector3.ZERO
	# Face the player so it is spotted immediately; the model's front is +Z.
	w.rotation.y = 0.0

	# Track the walker from the side, where a stride is obvious and a mace swing
	# is unmistakable.
	var cam := Camera3D.new()
	cam.fov = 50
	vp.add_child(cam)
	cam.current = true

	for _i in range(10):
		await physics_frame

	var sheet := Image.create(CELL * COLS, CELL * ROWS, false, Image.FORMAT_RGB8)
	sheet.fill(Color.BLACK)
	for i in range(COLS * ROWS):
		for _s in range(EVERY):
			await physics_frame
		var focus: Vector3 = w.global_position + Vector3.UP * 0.95
		cam.look_at_from_position(focus + Vector3(3.4, 0.5, 0.0), focus, Vector3.UP)
		await process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((i % COLS) * CELL, (i / COLS) * CELL))
		print("cell %2d  t=%.2f  state=%s  clip=%-6s  z=%6.2f  gap=%5.2f  speed=%4.1f"
			% [i, float((i + 1) * EVERY) / 60.0, w.get("_state"), w.get("_clip"),
				w.global_position.z,
				w.global_position.distance_to(player.global_position),
				Vector3(w.velocity.x, 0, w.velocity.z).length()])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()
