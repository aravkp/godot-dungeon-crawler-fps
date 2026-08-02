extends SceneTree
const OUT := "res://.shots/ds"
## globalize_path, because DirAccess and Image.save_png below take OS paths.
func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var win := get_root()
	DisplayServer.window_set_size(Vector2i(420, 420)); win.set_size(Vector2i(420, 420))
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p: p.set_script(null)
	var sp := scene.get_node_or_null("BatSpawner")
	if sp: sp.set("enabled", false)
	win.add_child(scene)
	await process_frame
	var w = scene.get_node("Camps/Camp_00/Watcher_0")
	var cam := Camera3D.new(); cam.fov = 45.0; scene.add_child(cam); cam.current = true
	await process_frame
	cam.global_position = w.global_position + Vector3(3.4, 1.5, 3.4)
	cam.look_at(w.global_position + Vector3(0, 0.8, 0), Vector3.UP)
	# a couple of frames of the live idle first, for the before/after
	for i in range(4): await process_frame
	await RenderingServer.frame_post_draw
	win.get_texture().get_image().save_png(dir + "/s0.png")
	w.take_hit(3)
	var shot := 1
	for i in range(1, 145):
		await physics_frame
		if i % 18 == 0 and shot < 9:
			await RenderingServer.frame_post_draw
			win.get_texture().get_image().save_png("%s/s%d.png" % [dir, shot])
			shot += 1
	print("wrote ", shot)
	quit()
