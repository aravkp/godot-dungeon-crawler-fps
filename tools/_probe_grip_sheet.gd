extends SceneTree
## Every dagger variant AS HELD, from the player camera, as a contact sheet.
##
## This is the only check that matters for the pack. The mount was solved once,
## against one dagger (tools/mount_dagger.gd), and dagger_variants.gd claims all
## 24 can be normalised onto that same fit. Either the grips all land in the fist
## or some of them are held by the blade, and no amount of measuring says which -
## you have to look at the hand.
##
## Needs a real display server:
##   "$GODOT" --path . -s tools/_probe_grip_sheet.gd -- [first] [count]

const VARIANTS := preload("res://scripts/dagger_variants.gd")
const OUT := "res://.shots/grips"
const W := 420
const H := 360


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 0
	var count := int(args[1]) if args.size() > 1 else 99

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

	var arms := scene.get_node("Player/Head/Camera3D/ViewModel/Arms")
	var ids := VARIANTS.all()
	ids = ids.slice(first, mini(first + count, ids.size()))

	# The original first, as the reference the rest are being matched to.
	arms.unlock_dagger()
	await _settle(arms)

	# A SECOND camera, parked next to the hand. Narrowing the player camera's fov
	# does not work: the viewmodel is welded to it, so zooming just pushes the
	# fist - which sits low and right, not centred - straight out of frame. This
	# one is a free camera in the world looking back at the mount.
	var art := scene.get_node("Player/Head/Camera3D/ViewModel/DaggerMount/Dagger") as Node3D
	var close := Camera3D.new()
	close.fov = 40.0
	close.near = 0.01
	scene.add_child(close)
	close.global_position = art.global_position \
		+ art.global_transform.basis.x * 0.16 \
		+ Vector3(0, 0.10, 0) \
		- (scene.get_node("Player/Head/Camera3D") as Node3D).global_transform.basis.z * -0.34
	close.look_at(art.global_position, Vector3.UP)
	close.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	win.get_texture().get_image().save_png("%s/00_original.png" % dir)
	print("shot original")
	for i in range(ids.size()):
		var id := String(ids[i])
		if not VARIANTS.apply(art, id):
			print("apply FAILED for ", id)
			continue
		await _settle(arms)
		win.get_texture().get_image().save_png("%s/%02d_%s.png" % [dir, i + 1, id])
		print("shot ", id)
	print("wrote to ", dir)
	quit()


## knife_idle seeked to the pose the mount was fitted against, so every shot is
## the same hand in the same place and only the blade differs.
func _settle(arms: Node) -> void:
	var ap: AnimationPlayer = arms.get_node("AnimationPlayer")
	ap.play("knife_idle")
	ap.seek(0.6, true)
	for f in range(4): await process_frame
	await RenderingServer.frame_post_draw
