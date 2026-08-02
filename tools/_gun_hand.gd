extends SceneTree
const OUT := "res://.shots/gh"
## globalize_path, because DirAccess and Image.save_png below take OS paths.
func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var win := get_root()
	DisplayServer.window_set_size(Vector2i(900, 520)); win.set_size(Vector2i(900, 520))
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p: p.set_script(null)
	var sp := scene.get_node_or_null("BatSpawner")
	if sp: sp.set("enabled", false)
	win.add_child(scene)
	await process_frame
	var ap: AnimationPlayer = scene.get_node("Player/Head/Camera3D/ViewModel/Arms/AnimationPlayer")
	var clips := ["guard_idle", "finger_gun_idle", "knife_idle", "jab_L"]
	for i in range(clips.size()):
		ap.play(clips[i]); ap.seek(0.35, true)
		for f in range(4): await process_frame
		await RenderingServer.frame_post_draw
		win.get_texture().get_image().save_png("%s/c%d.png" % [dir, i])
		print("shot ", clips[i])
	quit()
