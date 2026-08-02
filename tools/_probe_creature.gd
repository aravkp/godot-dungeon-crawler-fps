extends SceneTree

## Throwaway probe: the creature model from four sides, plus its real size.
##
##   Godot --path . -s tools/_probe_creature.gd
##
## Needs a real display server - do NOT run with --headless.
##
## There is no convention for which way a pack's model faces (arms_rig is +Z,
## skeleton.fbx is -Z), and this one is a static mesh with no rig to ask. So it
## gets rendered from all four cardinal yaws and the front is read off the sheet.

const SRC := "res://assets/creature/creature.fbx"
const TEX := "res://assets/creature/Material_Base_color.png"
const OUT := "res://.shots/creature.png"
const CELL := 340

func _init() -> void:
	var root := (load(SRC) as PackedScene).instantiate()
	get_root().add_child(root)
	await process_frame

	var mi: MeshInstance3D = null
	for n in root.find_children("*", "MeshInstance3D", true, false):
		mi = n as MeshInstance3D
		break
	var ab := mi.mesh.get_aabb()
	var scl := mi.global_transform.basis.get_scale()
	print("  mesh aabb  %.3v  size %.3v" % [ab.position, ab.size])
	print("  node scale %.3v  ->  world size %.3v" % [scl, ab.size * scl])
	print("  centre     %.3v" % (ab.position + ab.size * 0.5))

	# FBX drops texture links, so bind it the same way dungeon.gd does - onto the
	# shared mesh resource, which costs one bind however many instances exist.
	if ResourceLoader.exists(TEX):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(TEX)
		m.roughness = 1.0
		mi.material_override = m
		print("  texture    bound (%s)" % TEX)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.05, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.8)
	e.ambient_light_energy = 0.8
	env.environment = e
	get_root().add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 35, 0)
	get_root().add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 45
	get_root().add_child(cam)
	cam.current = true

	var mid: Vector3 = mi.global_transform * (ab.position + ab.size * 0.5)
	var r: float = maxf(ab.size.length() * scl.x, 0.5)
	var sheet := Image.create(CELL * 4, CELL, false, Image.FORMAT_RGB8)
	for i in range(4):
		var yaw := float(i) * PI * 0.5
		var eye := mid + Vector3(sin(yaw), 0.15, cos(yaw)) * r * 1.1
		cam.look_at_from_position(eye, mid, Vector3.UP)
		await process_frame
		await process_frame
		var img := get_root().get_texture().get_image()
		img.resize(CELL, CELL, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * CELL, 0))
		print("  yaw %3d rendered" % int(rad_to_deg(yaw)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.shots"))
	sheet.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	quit()
