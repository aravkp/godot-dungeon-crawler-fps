extends SceneTree
## Every clip in arms_rig.glb, one still each, so "is there an open palm?" is a
## question you answer by looking rather than by reading clip names. Ten of the
## eighteen are unused, and the names are the animator's, not this project's -
## `push_L` and `relax` could be anything.
##
## Sampled at a FRACTION through each clip rather than at a fixed time: the
## lengths run from 0.5 s to over 2 s, and one timestamp lands mid-swing on some
## and past the end of others.
##
## Needs a real display server:
##   "$GODOT" --path . -s tools/_probe_hand_poses.gd -- [fraction 0..1]

const OUT := "res://.shots/poses"
const W := 480
const H := 400


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var frac := float(args[0]) if args.size() > 0 else 0.55

	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var win := get_root()
	DisplayServer.window_set_size(Vector2i(W, H)); win.set_size(Vector2i(W, H))

	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p: p.set_script(null)
	var sp := scene.get_node_or_null("BatSpawner")
	if sp: sp.set("enabled", false)
	win.add_child(scene)
	await process_frame

	# The dagger would hide the fingers on half of these.
	var mount := scene.get_node_or_null("Player/Head/Camera3D/ViewModel/DaggerMount") as Node3D
	if mount: mount.visible = false

	var ap: AnimationPlayer = scene.get_node(
		"Player/Head/Camera3D/ViewModel/Arms/AnimationPlayer")
	var names := ap.get_animation_list()
	print("%d clips in arms_rig.glb" % names.size())
	for nm in names:
		var a := ap.get_animation(nm)
		print("  %-20s %5.3f s" % [nm, a.length if a else -1.0])

	for nm in names:
		var a := ap.get_animation(nm)
		if a == null:
			continue
		ap.play(nm)
		ap.seek(a.length * frac, true)
		for f in range(3): await process_frame
		await RenderingServer.frame_post_draw
		win.get_texture().get_image().save_png("%s/%s.png" % [dir, nm])
	print("wrote %d stills to %s" % [names.size(), dir])
	quit()
