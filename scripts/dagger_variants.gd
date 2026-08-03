class_name DaggerVariants
extends Object

## The 24 daggers from the CraftPix low-poly pack, as interchangeable skins for
## the ONE dagger item. Same `item` id, same `unlock_dagger`, same HUD card - a
## chest just picks a different-looking blade each time. Used via `preload` like
## blood.gd and slash_fx.gd, for the same class-registration reason.
##
## WHAT THE PACK IS, measured with tools/_probe_daggers.gd rather than assumed:
## every model is a SINGLE mesh, 148-1260 tris, running handle-at-the-bottom
## along +Y with the model origin on the butt of the grip, and 0.29-0.60 m long.
## They share one texture. That consistency is what makes one rule work for all
## 24; a pack that disagreed with itself would need a table.
##
## TWO NORMALISATIONS, and both matter for the thing sitting in the hand:
##
##   1. SCALE. Each is scaled so its length matches the original dagger.fbx
##      (0.254 m). DaggerMount's position and rotation were solved against that
##      dagger - see tools/mount_dagger.gd - so anything else lands wrong, and a
##      0.60 m model is a short sword in a first-person hand.
##   2. PIVOT. The mesh is moved so the GRIP CENTRE is on the node origin, not
##      the model origin. mount_dagger.gd found this the hard way: rotating about
##      the model origin swings the handle out of the palm on a lever as long as
##      the blade, and you end up chasing the position every time you touch the
##      angle. Pivot on the grip and rotation behaves like a wrist.
##
## GRIP_FRAC is not a guess. The original's own named `grip` part centres 10.6%
## of the model's length up from its base, so after the length normalisation
## above that same fraction puts the new grips where the old one was. Detecting
## each guard from the mesh was tried first and is not reliable - on half this
## pack the widest cross-section below the midpoint is the blade, not the guard,
## which put the pivot up near the tip.

const DIR := "res://assets/daggers/fbx"
const TEX := "res://assets/daggers/texture/Texture_MAp_axe.png"
## The original dagger.fbx's own Y extent. Everything is scaled to match it.
const TARGET_LENGTH := 0.254
## Grip centre as a fraction of length up from the base. See above.
const GRIP_FRAC := 0.105
## Sampled to find where the handle actually sits in X/Z - a few of these models
## have the grip well off the mesh centre line.
const GRIP_BAND := 2.0


## Every variant id, sorted numerically so "_dagger_2" precedes "_dagger_10".
static func all() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		push_warning("dagger_variants: no such directory " + DIR)
		return out
	for f in d.get_files():
		if f.ends_with(".fbx"):
			out.append(f.get_basename())
	out.sort_custom(func(a, b):
		return int(String(a).split("_")[-1]) < int(String(b).split("_")[-1]))
	return out


## One at random. Pass an RNG to make it reproducible; omit for plain chance.
static func pick(rng: RandomNumberGenerator = null) -> String:
	var ids := all()
	if ids.is_empty():
		return ""
	var i: int = rng.randi_range(0, ids.size() - 1) if rng \
		else randi() % ids.size()
	return String(ids[i])


static func exists(id: String) -> bool:
	return id != "" and ResourceLoader.exists("%s/%s.fbx" % [DIR, id])


## Replace whatever `host` is showing with variant `id`. Returns false and leaves
## the host untouched if the id is unknown, so a bad id shows the original dagger
## rather than an empty hand.
static func apply(host: Node3D, id: String, emissive: bool = false) -> bool:
	if host == null or not exists(id):
		return false
	var mi := build(id, emissive)
	if mi == null:
		return false
	for c in host.get_children():
		host.remove_child(c)
		c.queue_free()
	host.add_child(mi)
	return true


## A MeshInstance3D for one variant, normalised: grip centre on the origin, and
## scaled to the original dagger's length.
static func build(id: String, emissive: bool = false) -> MeshInstance3D:
	var path := "%s/%s.fbx" % [DIR, id]
	if not ResourceLoader.exists(path):
		return null
	var src := (load(path) as PackedScene).instantiate() as Node3D
	src.transform = Transform3D.IDENTITY
	var found := _first_mesh(src, Transform3D.IDENTITY)
	if found.is_empty():
		src.free()
		return null

	var mesh: Mesh = found["mesh"]
	var xf: Transform3D = found["xform"]
	var ab := mesh.get_aabb()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in range(8):
		var p: Vector3 = xf * ab.get_endpoint(i)
		lo = lo.min(p)
		hi = hi.max(p)
	var length: float = maxf(hi.y - lo.y, 0.0001)
	var k := TARGET_LENGTH / length

	var grip := _grip_centre(mesh, xf, lo.y, length)

	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = mesh
	# Scale about the grip: shift the grip to the origin first, then scale, which
	# is what `Basis * (-grip)` in the origin term does.
	var basis := xf.basis.scaled(Vector3(k, k, k))
	mi.transform = Transform3D(basis, (xf.origin - grip) * k)

	var mat := StandardMaterial3D.new()
	mat.resource_name = "dagger_pack"
	if ResourceLoader.exists(TEX):
		mat.albedo_texture = load(TEX)
	else:
		mat.albedo_color = Color(0.72, 0.75, 0.80)
	mat.roughness = 0.55
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emissive:
		# A dropped pickup has to stay readable in the corridor level, which has
		# no key light at all. The viewmodel copy does not want this - it already
		# has the camera lamp on it.
		mat.emission_enabled = true
		mat.emission = Color(0.75, 0.78, 0.85)
		mat.emission_energy_multiplier = 0.30
	mi.material_override = mat
	src.free()
	return mi


## Centre of the handle in model space: GRIP_FRAC of the way up, and at the mean
## X/Z of the vertices around that height rather than of the whole model. A few
## of these have the grip well off the mesh centre line (the hooked ones), and
## using the model centre there cants the handle out of the palm.
static func _grip_centre(mesh: Mesh, xf: Transform3D, base_y: float,
		length: float) -> Vector3:
	var y := base_y + GRIP_FRAC * length
	var band := GRIP_FRAC * length * GRIP_BAND
	var sum := Vector3.ZERO
	var n := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p: Vector3 = xf * v
			if absf(p.y - y) <= band:
				sum += Vector3(p.x, 0.0, p.z)
				n += 1
	var mid := sum / float(n) if n > 0 else Vector3.ZERO
	return Vector3(mid.x, y, mid.z)


static func _first_mesh(n: Node, t: Transform3D) -> Dictionary:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return {"mesh": (n as MeshInstance3D).mesh, "xform": lt}
	for c in n.get_children():
		var r := _first_mesh(c, lt)
		if not r.is_empty():
			return r
	return {}
