extends SceneTree
## The dagger slash, frame by frame.
##
## The arc lasts ~215 ms, and saving a 720x420 PNG costs ~95 ms, so screen-
## grabbing it live samples two of its nine frames and misses the rest. This
## pauses the sprite instead (speed_scale = 0) and steps `frame` by hand, which
## is the only way to see the whole animation as it actually renders in game.
##
## Not headless: the dummy display server renders nothing to save.
##   "$GODOT" --path . -s tools/_probe_slash.gd
const OUT := "res://.shots/slash"
## globalize_path, because DirAccess and Image.save_png below take OS paths.
func _init() -> void:
	var dir := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var win := get_root()
	DisplayServer.window_set_size(Vector2i(720, 420)); win.set_size(Vector2i(720, 420))
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	# The player script captures the mouse on _ready and would drive the view.
	var p := scene.get_node_or_null("Player")
	if p: p.set_script(null)
	var sp := scene.get_node_or_null("BatSpawner")
	if sp: sp.set("enabled", false)
	win.add_child(scene)
	await process_frame
	var head: Node3D = scene.get_node("Player/Head")
	var vm: Node3D = scene.get_node("Player/Head/Camera3D/ViewModel")
	var arms := scene.get_node("Player/Head/Camera3D/ViewModel/Arms")
	arms.unlock_dagger()
	for f in range(6): await process_frame

	# Each shot costs ~100 ms to render and save, so nine of them take a second
	# of wall clock - and slash_fx's fallback timer frees the sprite at ~0.7 s,
	# which killed it under the camera around frame 7. SceneTreeTimer obeys
	# time_scale, so slowing the engine right down keeps the sprite alive for
	# the whole strip. Nothing here depends on real-time pacing.
	Engine.time_scale = 0.02

	# Both alternating swings, nine frames each.
	for swing in range(2):
		arms.attack()
		var s := vm.get_node_or_null("SlashArc") as AnimatedSprite3D
		if s == null:
			print("NO ARC on swing ", swing); quit(); return
		s.speed_scale = 0.0
		# Stepping onto the LAST frame emits animation_finished the same as
		# playing onto it does, and slash_fx wires that to queue_free - so the
		# ninth shot would be taken against a freed node.
		s.animation_finished.disconnect(s.queue_free)
		print("swing %d  flip_h=%s  pos=%s" % [swing, s.flip_h, s.position])
		for i in range(9):
			var t := Time.get_ticks_msec()
			s.frame = i
			await process_frame
			await RenderingServer.frame_post_draw
			var t1 := Time.get_ticks_msec()
			win.get_texture().get_image().save_png("%s/a%d_%d.png" % [dir, swing, i])
			print("   frame %d  render %d ms  save %d ms" % [i, t1 - t,
				Time.get_ticks_msec() - t1])
		s.queue_free()
		# Let the swing clip finish at normal speed, or _busy gates the next one.
		Engine.time_scale = 1.0
		for f in range(40): await process_frame
		Engine.time_scale = 0.02

	# ...and the impact burst. A wall dropped in front of the camera rather than
	# a hunt for terrain, so the melee ray is guaranteed to land.
	var cam := scene.get_node("Player/Head/Camera3D") as Camera3D
	var wall := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(4, 4, 0.2)
	col.shape = box; wall.add_child(col)
	var face := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = box.size; face.mesh = bm
	wall.add_child(face)
	scene.add_child(wall)
	wall.global_position = cam.global_position - cam.global_transform.basis.z * 1.6
	wall.global_rotation = cam.global_rotation
	Engine.time_scale = 1.0
	for f in range(4): await process_frame
	print("impact swing started=", arms.attack())
	Engine.time_scale = 0.02
	var burst := scene.find_child("SlashImpact", true, false) as AnimatedSprite3D
	if burst == null:
		print("NO IMPACT - the melee ray hit nothing")
	else:
		burst.speed_scale = 0.0
		burst.animation_finished.disconnect(burst.queue_free)
		print("impact at ", burst.global_position, " parent=", burst.get_parent().name)
		for i in range(9):
			burst.frame = i
			await process_frame
			await RenderingServer.frame_post_draw
			win.get_texture().get_image().save_png("%s/hit_%d.png" % [dir, i])
	print("wrote to ", dir)
	quit()
