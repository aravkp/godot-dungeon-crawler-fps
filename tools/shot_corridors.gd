extends SceneTree

## Stills of scenes/corridors.tscn into .shots/. Needs a real display server,
## so run WITHOUT --headless:
##
##   Godot --path . -s tools/shot_corridors.gd
##
## Drops the Player script before the scene enters the tree so the preview
## window cannot capture the mouse. The last shot hides the ceiling tiles and
## pulls the camera up, which is the quickest way to see whether the generated
## layout is actually a connected route.

const SCENE := "res://scenes/corridors.tscn"
const OUT := "res://.shots"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var win := get_root()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	win.set_size(Vector2i(1280, 720))

	var scene := (load(SCENE) as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p:
		p.set_script(null)
	win.add_child(scene)
	await process_frame

	var level := scene.get_node("Corridors")
	var cam := Camera3D.new()
	cam.fov = 78.0
	cam.far = 500.0
	scene.add_child(cam)
	cam.current = true
	await process_frame

	# 1. eye level at the spawn, looking down the opening corridor
	var start: Vector3 = p.global_position if p else Vector3.ZERO
	cam.global_position = start + Vector3(0, 0.5, 0)
	cam.global_transform.basis = (p as Node3D).global_transform.basis if p else Basis.IDENTITY
	await _shoot(win, "corr_start")

	# 2. from each of the first few enemy packs, looking back up the corridor
	var packs := scene.get_node_or_null("Packs")
	if packs:
		var i := 0
		for pack in packs.get_children():
			if i >= 2:
				break
			var w := pack.get_child(0) as Node3D
			cam.global_position = pack.global_position + Vector3(0, 1.7, 0) \
				- w.global_transform.basis.z * 5.0
			cam.look_at(pack.global_position + Vector3(0, 1.2, 0), Vector3.UP)
			await _shoot(win, "corr_pack%d" % i)
			i += 1

	# 3. the destructibles: a door gate head-on, and a crate beside it. Both are
	# breakable.gd bodies, and the thing to judge here is whether the doorway
	# reads as something you could walk through once it is smashed.
	var shots := 0
	for c in level.get_children():
		if shots >= 2 or not c.name.begins_with("Gate_"):
			continue
		var g := c as Node3D
		# Along the gate's local Z, which is the direction of travel.
		cam.global_position = g.global_position - g.global_transform.basis.z * 5.5 \
			+ Vector3(0, 1.6, 0)
		cam.look_at(g.global_position + Vector3(0, 1.6, 0), Vector3.UP)
		await _shoot(win, "corr_gate%d" % shots)
		shots += 1
	for c in level.get_children():
		if not c.name.begins_with("Crate_"):
			continue
		var cr := c as Node3D
		cam.global_position = cr.global_position + Vector3(1.6, 1.4, 1.6)
		cam.look_at(cr.global_position + Vector3(0, 0.4, 0), Vector3.UP)
		await _shoot(win, "corr_crate")
		break

	# 4. plan view with the ceiling stripped
	for c in level.get_children():
		if c.name.begins_with("C_"):
			(c as Node3D).visible = false
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for c in level.get_children():
		if c is Node3D and c.name.begins_with("F_"):
			lo = lo.min((c as Node3D).global_position)
			hi = hi.max((c as Node3D).global_position)
	var mid := (lo + hi) * 0.5
	var span: float = maxf(hi.x - lo.x, hi.z - lo.z)
	cam.global_position = mid + Vector3(0.01, span * 0.95 + 12.0, 0.01)
	cam.look_at(mid, Vector3(0, 0, -1))
	await _shoot(win, "corr_plan")
	print("layout spans %.1fm x %.1fm" % [hi.x - lo.x, hi.z - lo.z])
	quit()

func _shoot(win: Window, nm: String) -> void:
	for f in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	win.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])
	print("wrote ", nm)
