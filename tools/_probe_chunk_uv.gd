extends SceneTree

## Throwaway probe: what a chunk actually ends up looking like, as numbers.
##
##   Godot --headless --path . -s tools/_probe_chunk_uv.gd -- [Crate_1|DaggerChest]
##
## Smashes one prop and prints, for the pile it leaves: the source texture and
## measured density, the UV window each chunk was given, and the colour that
## window resolves to in the texture. A chunk that renders as a white blob and a
## chunk that renders as wood look identical in the scene tree and differ here.

const SCENE := "res://scenes/corridors.tscn"

func _init() -> void:
	var want := "Crate_1"
	for a in OS.get_cmdline_user_args():
		want = a
	var root := (load(SCENE) as PackedScene).instantiate()
	var p := root.find_child("Player", true, false)
	if p:
		p.set_script(null)
	get_root().add_child(root)
	for _i in range(10):
		await physics_frame

	var prop := root.find_child(want, true, false) as Node3D
	if prop == null:
		print("FAIL: no %s" % want)
		quit()
		return

	# The source mesh burst() will be handed, and what it measures off it.
	var art: MeshInstance3D = null
	for n in prop.find_children("*", "MeshInstance3D", true, false):
		art = n as MeshInstance3D
		break
	if art == null:
		print("FAIL: %s has no MeshInstance3D" % want)
		quit()
		return
	var std := art.get_active_material(0) as StandardMaterial3D
	print("\n--- %s ---" % want)
	print("  art:          %s" % art.name)
	print("  material:     %s" % ("null" if std == null else str(std.resource_name)))
	if std:
		print("  albedo_tex:   %s" % ("null" if std.albedo_texture == null
			else "%dx%d" % [std.albedo_texture.get_width(), std.albedo_texture.get_height()]))
		print("  albedo_color: %.3v  filter=%d" % [
			Vector3(std.albedo_color.r, std.albedo_color.g, std.albedo_color.b),
			std.texture_filter])

	var scl := art.global_transform.basis.get_scale()
	var aabb := art.get_aabb()
	print("  art scale:    %.3v   mesh aabb %.3v -> world %.3v" % [
		scl, aabb.size, aabb.size * scl])
	for n in prop.find_children("*", "CollisionShape3D", true, false):
		var sh := (n as CollisionShape3D).shape
		if sh is BoxShape3D:
			print("  collider box: %.3v" % (sh as BoxShape3D).size)

	# What shatter.gd measures off the mesh, before any chunk exists.
	var S := load("res://scripts/shatter.gd") as GDScript
	var look: Dictionary = S.call("_look", art)
	if look.is_empty():
		print("  look:         EMPTY - falls back to flat colours")
	else:
		print("  density:      %.3f uv/m   uv bounds %.3v..%.3v  (span %.3f)" % [
			look["density"], Vector3(look["uv_lo"].x, look["uv_lo"].y, 0),
			Vector3(look["uv_hi"].x, look["uv_hi"].y, 0),
			minf(look["uv_hi"].x - look["uv_lo"].x, look["uv_hi"].y - look["uv_lo"].y)])
		print("  probe tris:   %d" % (look["pts"] as PackedVector3Array).size())
	# The colour the emission lift is derived from, and how bright the texture
	# actually is - the two are not the same, and the lift is tuned against them.
	var pal: Array = S.call("_palette", art, std)
	for e in pal:
		print("  palette:      %.3v  w=%.2f  lum=%.3f" % [
			Vector3((e["color"] as Color).r, (e["color"] as Color).g,
				(e["color"] as Color).b), e["weight"],
			(e["color"] as Color).get_luminance()])

	for i in range(8):
		if not is_instance_valid(prop):
			break
		prop.take_hit(1, prop.global_position + Vector3(0, 0.4, 0), Vector3.FORWARD)
		await physics_frame
	await physics_frame

	var fx := root.find_child("Shatter*", true, false)
	if fx == null:
		print("  FAIL: no chunks")
		quit()
		return
	var img: Image = null
	if std and std.albedo_texture:
		img = std.albedo_texture.get_image()
		if img and img.is_compressed():
			img.decompress()

	var n_chunk := 0
	for body in fx.get_children():
		var mi := body.get_child(0) as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		var arrays := mi.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for uv in uvs:
			lo = lo.min(uv)
			hi = hi.max(uv)
		var col := Color(0, 0, 0)
		if img:
			var c := (lo + hi) * 0.5
			col = img.get_pixel(
				clampi(int(c.x * img.get_width()), 0, img.get_width() - 1),
				clampi(int(c.y * img.get_height()), 0, img.get_height() - 1))
		if n_chunk < 8:
			print("  chunk %2d  uv %.3v..%.3v  ->  rgb %.2v  (verts=%d)" % [
				n_chunk, Vector3(lo.x, lo.y, 0), Vector3(hi.x, hi.y, 0),
				Vector3(col.r, col.g, col.b), uvs.size()])
		if n_chunk == 0 and mat:
			print("  chunk mat:    albedo_tex=%s  albedo=%.2v" % [
				"yes" if mat.albedo_texture else "NO",
				Vector3(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b)])
			print("                emission=%s energy=%.3f tex=%s unshaded=%s" % [
				mat.emission_enabled, mat.emission_energy_multiplier,
				"yes" if mat.emission_texture else "no",
				mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED])
		n_chunk += 1
	print("  chunks:       %d" % n_chunk)
	quit()
