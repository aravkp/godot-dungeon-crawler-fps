extends SceneTree

## Throwaway probe: renders every animation in arms_rig.glb from the player's
## own camera, so "is there a gun-holding pose in this rig" can be answered by
## looking. Writes one PNG per sample into .shots/poses/.
## Needs a real display server - do NOT run with --headless.

func _init() -> void:
	var root := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	var sp := root.find_child("BatSpawner", true, false)
	if sp:
		sp.set("enabled", false)
	get_root().add_child(root)
	await process_frame

	var arms := root.find_child("Arms", true, false)
	var ap: AnimationPlayer = arms.get_node("AnimationPlayer")
	var cam: Camera3D = root.find_child("Camera3D", true, false)
	cam.current = true
	# Hide the dagger so it doesn't confuse which poses are gripping.
	var mount := root.find_child("DaggerMount", true, false)
	if mount:
		mount.visible = false

	var names := ap.get_animation_list()
	print("animations (%d): %s" % [names.size(), ", ".join(names)])
	var dir := ProjectSettings.globalize_path("res://.shots/poses")
	DirAccess.make_dir_recursive_absolute(dir)

	for n in names:
		var a := ap.get_animation(n)
		ap.play(n)
		ap.speed_scale = 0.0
		# Mid-clip: past any wind-up, before any recovery.
		for phase in [0.45, 0.75]:
			ap.seek(a.length * phase, true)
			await process_frame
			await process_frame
			var img := get_root().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png("%s/%s_%d.png" % [dir, n, int(phase * 100)])
		print("  %-18s len=%.2fs tracks=%d" % [n, a.length, a.get_track_count()])
	print("done")
	quit()
