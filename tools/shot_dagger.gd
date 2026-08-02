extends SceneTree

## Renders close-ups of the dagger in the right hand to res://.shots/, for
## judging the grip fit after tuning tools/mount_dagger.gd.
##
## Strips player.gd (mouse capture) and disables the BatSpawner, but keeps
## arms.gd - its _ready() plays knife_idle, which is the pose the mount was
## fitted against. Must run *without* --headless.
##
##   Godot --path . -s tools/shot_dagger.gd

const OUT := "res://.shots"
const HAND := "hand.R"
const SKEL_PATH := "Player/Head/Camera3D/ViewModel/Arms/ArmsRig/Skeleton3D"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var win := get_root()
	win.set_size(Vector2i(1280, 720))
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p:
		p.set_script(null)
	var spawner := scene.get_node_or_null("BatSpawner")
	if spawner:
		spawner.set("enabled", false)
	win.add_child(scene)

	var player_cam := scene.get_node_or_null("Player/Head/Camera3D") as Camera3D
	var skel := scene.get_node_or_null(SKEL_PATH) as Skeleton3D
	if player_cam == null or skel == null:
		print("FAIL: missing camera or skeleton"); quit(1); return

	# Let the idle animation settle into its pose before measuring the hand.
	await process_frame
	for f in range(30):
		await process_frame

	var bone := skel.find_bone(HAND)
	var hand: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bone)).origin
	var basis := player_cam.global_transform.basis
	var right := basis.x
	var up := basis.y
	var fwd := -basis.z

	# First-person view, exactly as in-game.
	player_cam.current = true
	await _snap(win, "dagger_fp")

	# Orbit close-ups of the fist.
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.005
	scene.add_child(cam)
	cam.current = true

	var views := {
		"dagger_side": hand + right * 0.35 + up * 0.05,
		"dagger_top": hand + up * 0.32 + right * 0.06,
		"dagger_front": hand + fwd * 0.35 + up * 0.08,
		"dagger_inside": hand - right * 0.30 + up * 0.06 - fwd * 0.10,
	}
	for vname: String in views:
		cam.global_position = views[vname]
		cam.look_at(hand, Vector3.UP)
		await _snap(win, vname)

	quit()

func _snap(win: Viewport, fname: String) -> void:
	for f in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := win.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, fname])
	print("wrote %s.png" % fname)
