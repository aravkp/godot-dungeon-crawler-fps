extends SceneTree
## All 24 daggers side-on, in a row, with the model origin marked in red.
##
## The one thing the numbers cannot tell you is WHICH END IS THE HANDLE, and a
## dagger mounted the wrong way round is held by the blade. Every model in this
## pack spans y = 0 .. length with its origin at the base, so the red line is at
## the base of each: if the handles sit on the line, the grip is at +Y = 0.
##
## Needs a real display server:
##   "$GODOT" --path . -s tools/_probe_dagger_sheet.gd

const DIR := "res://assets/daggers/fbx"
const TEX := "res://assets/daggers/texture/Texture_MAp_axe.png"
const OUT := "res://.shots/daggers.png"
const COLS := 12
const SPACING := 0.30


func _init() -> void:
	var win := get_root()
	DisplayServer.window_set_size(Vector2i(1600, 620)); win.set_size(Vector2i(1600, 620))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.82, 0.9)
	e.ambient_light_energy = 1.0
	env.environment = e
	win.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.4
	win.add_child(key)

	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(TEX):
		mat.albedo_texture = load(TEX)
	mat.roughness = 0.7

	var names := _list()
	var rows := int(ceil(float(names.size()) / float(COLS)))
	for i in range(names.size()):
		var scn := load("%s/%s" % [DIR, names[i]]) as PackedScene
		if scn == null:
			continue
		var inst := scn.instantiate() as Node3D
		win.add_child(inst)
		var col := i % COLS
		var row := i / COLS
		inst.position = Vector3((col - (COLS - 1) * 0.5) * SPACING,
			-float(row) * 0.75, 0)
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_override = mat
		# A red tick ON the model origin, which is the base of every model here.
		var tick := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(SPACING * 0.8, 0.006, 0.006)
		tick.mesh = bm
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(1, 0.2, 0.2)
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tick.material_override = red
		inst.add_child(tick)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.80 * float(rows) + 0.25
	win.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 0.30 - 0.75 * float(rows - 1) * 0.5, 3.0)
	cam.look_at(Vector3(0, 0.30 - 0.75 * float(rows - 1) * 0.5, 0), Vector3.UP)

	for f in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	win.get_texture().get_image().save_png(path)
	print("wrote ", path, "  (", names.size(), " models, red tick = model origin)")
	quit()


func _list() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".fbx"):
			out.append(f)
	out.sort_custom(func(a, b):
		return int(a.get_basename().split("_")[-1]) < int(b.get_basename().split("_")[-1]))
	return out
