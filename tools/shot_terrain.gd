extends SceneTree

## Renders a few stills of main.tscn to res://.shots/ for eyeballing the level
## look - materials, tiling density, how the geometry reads.
##
## Deliberately drops the Player script before the scene enters the tree, so
## player.gd never captures the mouse and the window cannot swallow real input.
## Must run *without* --headless: the dummy display server renders nothing.
##
##   Godot --path . -s tools/shot_terrain.gd

const OUT := "res://.shots"

# position, look-at target
const SHOTS := [
	[Vector3(0, 1.7, 8.0), Vector3(0, 1.4, -20.0)],       # eye level from spawn
	[Vector3(24.5, 3.0, 4.0), Vector3(24.5, 3.0, -30.0)], # down the wall-run corridor
	[Vector3(-41, 2.5, -14.0), Vector3(-41, 3.0, 26.0)],  # up the staggered gauntlet
	# Camp_00, from outside sight_range so the trio is still standing guard.
	[Vector3(-18, 2.2, -27.0), Vector3(-18, 1.0, -38.0)],
	[Vector3(58, 34, 58), Vector3(-6, 0, 0)],             # overview
]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var win := get_root()
	win.set_size(Vector2i(1280, 720))
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p:
		p.set_script(null)
	win.add_child(scene)

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 400.0
	scene.add_child(cam)
	cam.current = true

	# Nodes added during _init are not inside the tree yet, and global_position
	# and look_at both need them to be.
	await process_frame

	for i in range(SHOTS.size()):
		cam.global_position = SHOTS[i][0]
		cam.look_at(SHOTS[i][1], Vector3.UP)
		# Let the renderer settle - shadows and sky need a few frames.
		for f in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var img := win.get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [OUT, i])
		print("wrote shot_%d.png" % i)

	quit()
