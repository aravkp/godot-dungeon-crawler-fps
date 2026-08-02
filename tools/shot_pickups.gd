extends SceneTree

## Renders the loadout flow to res://.shots/ - starting fists, the dagger
## floating with its HUD info card, and the armed viewmodel after taking it.
##
## Drives the real HUD by calling player.gd's contract by hand (set_prompt /
## set_focus_info), because the interaction ray needs the player script, which
## captures the mouse. Must run *without* --headless.
##
##   Godot --path . -s tools/shot_pickups.gd

const OUT := "res://.shots"

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var win := get_root()
	win.set_size(Vector2i(1280, 720))
	DisplayServer.window_set_size(Vector2i(1280, 720))

	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var player := scene.get_node_or_null("Player") as Node3D
	if player:
		player.set_script(null)
	var spawner := scene.get_node_or_null("BatSpawner")
	if spawner:
		spawner.set("enabled", false)
	win.add_child(scene)
	await process_frame

	var cam := scene.get_node_or_null("Player/Head/Camera3D") as Camera3D
	var arms := scene.get_node_or_null("Player/Head/Camera3D/ViewModel/Arms")
	var hud := scene.get_tree().get_first_node_in_group("hud")
	if cam == null or arms == null:
		print("FAIL: no camera or arms"); quit(1); return
	cam.current = true

	# 1. The opening loadout: two empty fists, nothing in either hand.
	await _settle(40)
	await _snap(win, "loadout_0_fists")

	# 2. The one loot chest: open it, stand off the floating item, show the card.
	await _visit(win, scene, player, cam, hud, "Camps/Camp_00/Chest",
		"dagger", "loadout_1_dagger")

	# 3. Armed: the dagger is in the fist.
	if hud:
		hud.set_prompt("")
		hud.set_focus_info("", "")
	await _settle(30)
	await _snap(win, "loadout_2_armed")
	print("has_dagger=%s" % arms.get("has_dagger"))
	quit()

## Opens one chest, frames the pickup that floats out, draws its HUD card, shoots
## it, then takes it.
func _visit(win: Viewport, scene: Node, player: Node3D, cam: Camera3D, hud: Object,
		chest_path: String, item: String, shot: String) -> void:
	var chest := scene.get_node_or_null(chest_path) as Node3D
	if chest == null:
		print("FAIL: no chest at ", chest_path)
		return
	# Stand the player where they would be to reach it, so the viewmodel is in
	# frame alongside the item.
	player.global_position = chest.global_position + Vector3(0.0, 0.0, 2.1)
	await process_frame
	chest.interact(null)
	await _settle(24)

	var pk := _pickup_near(chest)
	if pk == null:
		print("FAIL: no pickup from ", chest_path)
		return
	cam.look_at(pk.global_position, Vector3.UP)
	if hud:
		hud.set_prompt("[E] " + pk.prompt())
		hud.set_focus_info(pk.title(), pk.subtitle())
	await _settle(12)
	await _snap(win, shot)
	pk.interact(null)
	await _settle(10)

func _pickup_near(chest: Node3D) -> Node:
	for c in chest.get_parent().get_children():
		if c.is_in_group("pickups") and not c.is_queued_for_deletion():
			return c
	return null

func _settle(frames: int) -> void:
	for f in range(frames):
		await process_frame

func _snap(win: Viewport, fname: String) -> void:
	await RenderingServer.frame_post_draw
	win.get_texture().get_image().save_png("%s/%s.png" % [OUT, fname])
	print("wrote %s.png" % fname)
