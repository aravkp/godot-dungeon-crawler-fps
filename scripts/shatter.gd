extends Node3D

## Breaks a prop into real falling chunks.
##
## The particle burst in debris.gd sells the *impact*; this is what sells the
## thing coming apart. A smashed crate leaves a pile of boards on the floor that
## you can walk through and that enemies kick around, for a few seconds.
##
## Built in code and driven by its own _process, so it is created the way
## pickup.gd is - `script.new()` rather than a .tscn. Parent it to something that
## OUTLIVES the prop (the level, or the gate node), never the prop itself, since
## the prop is freed on the same frame.
##
## Used via preload, like blood.gd / debris.gd / ragdoll.gd: global class
## registration lives in the editor's scan cache, which headless runs never
## rebuild.

## Aim for chunks about this big. The grid is derived from the prop's own box, so
## a crate comes apart into cubes and a door into planks without either being
## told what it is.
const TARGET_CHUNK := 0.35
## Cap per axis regardless. A door is 2.0 x 3.0 m, which at TARGET_CHUNK would be
## 6 x 9 = 54 bodies for one door.
const MAX_CELLS := 4
## Shrunk slightly so chunks do not start the frame interpenetrating.
const FIT := 0.92
## Ceiling on how many of a prop's triangles are kept for the nearest-triangle
## lookup that gives a chunk its UVs. The chest is a few thousand; a stride over
## them costs nothing visible and keeps a burst off the frame budget.
const MAX_PROBE_TRIS := 1500
## How many colours a prop breaks into, at most - see _palette().
const PALETTE_MAX := 3
## How much self-lit brightness a chunk is given, before being divided by the
## colour's own luminance. See _chunk_materials().
const EMISSION_LIFT := 0.08
const EMISSION_MAX := 0.45
## The same for a TEXTURED chunk, where the lift is divided by the SQUARE of the
## prop's luminance instead - see _texture_material().
const EMISSION_LIFT_TEX := 0.026
const EMISSION_MAX_TEX := 0.70
## Resolution of the colour clustering, per channel. 5 is enough to keep the
## chest's wood and its steel banding in separate bins without splitting the wood
## itself across several.
const COLOR_BINS := 5

## Gravity here is the project default (9.8), but the game's own fall gravity is
## 34 - chunks dropping at a third of the rate everything else does read as
## floaty polystyrene. See player.gd.
const GRAVITY_SCALE := 2.5

@export var linger: float = 3.0
@export var fade: float = 0.6

var _age: float = 0.0
var _meshes: Array[MeshInstance3D] = []

## Breaks the box `size`, centred and oriented by `xform`, into chunks.
## `source` supplies the look; `dir` is the blow's world direction.
static func burst(host: Node, xform: Transform3D, size: Vector3,
		source: MeshInstance3D, dir: Vector3, strength: float = 2.6) -> Node3D:
	if host == null or not host.is_inside_tree() or size == Vector3.ZERO:
		return null
	var script := load("res://scripts/shatter.gd") as GDScript
	var fx: Node3D = script.new()
	fx.name = "Shatter"
	host.add_child(fx)

	var cells := Vector3i(
		clampi(int(round(size.x / TARGET_CHUNK)), 1, MAX_CELLS),
		clampi(int(round(size.y / TARGET_CHUNK)), 1, MAX_CELLS),
		clampi(int(round(size.z / TARGET_CHUNK)), 1, MAX_CELLS))
	var cell := size / Vector3(cells)
	# The textured path if the prop has a usable texture and UVs, the flat-colour
	# palette if it has not - see _look() and _chunk_materials().
	var look := _look(source)
	var mats: Array[Material] = []
	if look.is_empty():
		mats = _chunk_materials(source)
	# Chunk positions are in the collider box's space; the prop's triangles are in
	# its mesh's. This is what carries one to the other.
	var to_mesh := Transform3D()
	if not look.is_empty():
		to_mesh = source.global_transform.affine_inverse() * xform
	var rng := RandomNumberGenerator.new()
	var kick := dir.normalized() if dir != Vector3.ZERO else Vector3.UP

	var made: Array[MeshInstance3D] = []
	for x in range(cells.x):
		for y in range(cells.y):
			for z in range(cells.z):
				var at := Vector3(
					(float(x) + 0.5) * cell.x - size.x * 0.5,
					(float(y) + 0.5) * cell.y - size.y * 0.5,
					(float(z) + 0.5) * cell.z - size.z * 0.5)
				var mat: Material = null
				var mesh: Mesh = null
				if look.is_empty():
					mat = _pick(mats, rng)
				else:
					mat = look["material"]
					mesh = _uv_box(cell * FIT, _window(look, to_mesh * at, cell))
				made.append(_chunk(fx, xform, at, cell, mat, mesh,
					kick, strength, rng))
	fx.set("_meshes", made)
	return fx

static func _chunk(fx: Node3D, xform: Transform3D, at: Vector3, cell: Vector3,
		mat: Material, mesh: Mesh, kick: Vector3, strength: float,
		rng: RandomNumberGenerator) -> MeshInstance3D:
	var body := RigidBody3D.new()
	# Layer 0 so NOTHING targets a chunk: not the melee ray, not the interaction
	# ray, not another chunk. The mask still sees layer 1, so they land on the
	# floor - the same split ragdoll.gd uses, and for the same reason. Without it
	# a cloud of debris in front of you eats the swing aimed at what is behind it.
	body.collision_layer = 0
	body.collision_mask = 1
	body.gravity_scale = GRAVITY_SCALE
	body.mass = maxf(0.05, cell.x * cell.y * cell.z * 400.0)
	body.continuous_cd = false
	fx.add_child(body)
	body.global_transform = xform * Transform3D(Basis(), at)

	var mi := MeshInstance3D.new()
	mi.name = "Chunk"
	if mesh != null:
		mi.mesh = mesh
	else:
		var box := BoxMesh.new()
		box.size = cell * FIT
		mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = cell * FIT
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)

	# Outward from the middle, plus the blow, plus a little noise - so a pile
	# opens up instead of every chunk taking the same path.
	var out := (xform.basis * at).normalized() if at != Vector3.ZERO else Vector3.UP
	var jitter := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.0),
		rng.randf_range(-1.0, 1.0))
	var impulse := (out * 1.0 + kick * 0.8 + jitter * 0.5) * strength * body.mass
	body.apply_impulse(impulse)
	body.angular_velocity = Vector3(rng.randf_range(-9.0, 9.0),
		rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
	return mi

## Everything a textured burst needs from the prop, measured once per mesh and
## cached: the shared chunk material, the prop's triangles as (position, UV)
## pairs, and its texel density.
##
## **A chunk is textured by giving its box explicit UVs, not by mapping the whole
## texture onto it.** `BoxMesh` divides one 0..1 UV square between its six faces,
## so handing it the prop's UVs gets each face a sixth of the sheet, blown up -
## which is what made the first attempt at this come out a flat wrong grey. So the
## box is built here instead, with all six faces given the SAME small window of
## the texture, taken from where that chunk actually was on the prop: the nearest
## source triangle's UV centroid, sized by the chunk's own size in texture units.
##
## Two consequences worth knowing:
##
## - **The window has to be measured, not chosen.** `density` is UV units per
##   metre, from the ratio of the prop's total UV area to its total surface area
##   in world metres, so a chunk shows the texture at the size the prop showed it
##   at. A door scaled x2 by the builder therefore gets half the density of the
##   same mesh unscaled, which is why the cache key carries the node's scale.
## - **The window is clamped inside the UV bounds the prop actually uses.** The
##   dungeon kit's crate atlas is wood over three quadrants and solid BLACK in the
##   fourth; a window that wandered off an island would take the void with it.
##   Starting from a triangle centroid puts it inside an island by construction,
##   and the clamp keeps the rest of the window near one.
static func _look(source: MeshInstance3D) -> Dictionary:
	if source == null or source.mesh == null:
		return {}
	var std := source.get_active_material(0) as StandardMaterial3D
	if std == null or std.albedo_texture == null:
		return {}
	var scale := source.global_transform.basis.get_scale()
	var key := "%d:%.3v" % [source.mesh.get_instance_id(), scale]
	if _looks.has(key):
		return _looks[key]

	var arrays := source.mesh.surface_get_arrays(0)
	if arrays.is_empty() or arrays[Mesh.ARRAY_TEX_UV] == null:
		_looks[key] = {}
		return {}
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if uvs.is_empty() or verts.is_empty():
		_looks[key] = {}
		return {}
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]

	var pts := PackedVector3Array()
	var mid := PackedVector2Array()
	var uv_lo := Vector2(INF, INF)
	var uv_hi := Vector2(-INF, -INF)
	var area_3d := 0.0
	var area_uv := 0.0
	var tris := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
	var stride := maxi(1, int(ceil(float(tris) / float(MAX_PROBE_TRIS))))
	for t in range(tris):
		var i0: int
		var i1: int
		var i2: int
		if idx.size() > 0:
			i0 = idx[t * 3]; i1 = idx[t * 3 + 1]; i2 = idx[t * 3 + 2]
		else:
			i0 = t * 3; i1 = t * 3 + 1; i2 = t * 3 + 2
		if i2 >= uvs.size() or i2 >= verts.size():
			continue
		# Areas in the units each lives in: world metres for the surface (so the
		# node's scale counts), UV units for the sheet.
		var e1: Vector3 = scale * (verts[i1] - verts[i0])
		var e2: Vector3 = scale * (verts[i2] - verts[i0])
		area_3d += e1.cross(e2).length() * 0.5
		var d1: Vector2 = uvs[i1] - uvs[i0]
		var d2: Vector2 = uvs[i2] - uvs[i0]
		area_uv += absf(d1.x * d2.y - d1.y * d2.x) * 0.5
		# Bounds from the triangle CORNERS, not its centroid. Centroids sit well
		# inside their islands, so a centroid bbox understates the region the prop
		# uses - measured on the kit crate, 0.167 against a true 0.5 - and the
		# window below then clamps to the whole of it and pins every chunk to the
		# same texel. Sampling still starts from a centroid; only the bounds differ.
		var c: Vector2 = (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
		for corner in [uvs[i0], uvs[i1], uvs[i2]]:
			uv_lo = uv_lo.min(corner)
			uv_hi = uv_hi.max(corner)
		if t % stride == 0:
			pts.append((verts[i0] + verts[i1] + verts[i2]) / 3.0)
			mid.append(c)
	if pts.is_empty() or area_3d <= 0.0 or area_uv <= 0.0:
		_looks[key] = {}
		return {}

	var out := {
		"material": _texture_material(source, std),
		"pts": pts,
		"uv": mid,
		"density": sqrt(area_uv / area_3d),
		"uv_lo": uv_lo,
		"uv_hi": uv_hi,
	}
	_looks[key] = out
	return out

## Cached per mesh resource AND per scale - every crate in the level shares one
## mesh, so this runs once for crates however many get smashed.
static var _looks: Dictionary = {}

## The window of the texture one chunk shows: centred on the nearest source
## triangle's UVs, sized by the chunk itself, kept inside the prop's own bounds.
static func _window(look: Dictionary, at: Vector3, cell: Vector3) -> Rect2:
	var pts: PackedVector3Array = look["pts"]
	var uv: PackedVector2Array = look["uv"]
	var best := 0
	var best_d := INF
	for i in range(pts.size()):
		var d := pts[i].distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = i
	var r: float = (cell.x + cell.y + cell.z) / 3.0 * float(look["density"]) * FIT * 0.5
	var lo: Vector2 = look["uv_lo"]
	var hi: Vector2 = look["uv_hi"]
	# A window wider than the region the prop uses can only be centred on it.
	r = minf(r, minf(hi.x - lo.x, hi.y - lo.y) * 0.5)
	var c := uv[best]
	c.x = clampf(c.x, lo.x + r, maxf(lo.x + r, hi.x - r))
	c.y = clampf(c.y, lo.y + r, maxf(lo.y + r, hi.y - r))
	return Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)

## The six faces of a chunk, as (outward normal, u axis, v axis).
const FACES := [
	[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
	[Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
	[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.LEFT, Vector3.UP],
	[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
]

## A box of `size` with every face mapped to the same UV rect. This is the whole
## reason chunks are not BoxMesh any more.
static func _uv_box(size: Vector3, win: Rect2) -> ArrayMesh:
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in FACES:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h
		var du := u * h
		var dv := v * h
		var corner := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		var uv := [win.position + Vector2(0, win.size.y), win.end,
			win.position + Vector2(win.size.x, 0), win.position]
		st.set_normal(n)
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uv[i])
			st.add_vertex(corner[i])
	return st.commit()

## The one material every chunk of a given prop shares. Nothing varies per chunk
## except its UVs, which live in the mesh - so a 64-chunk door is still one
## material and one texture.
static func _texture_material(source: MeshInstance3D, std: StandardMaterial3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = "chunk"
	m.albedo_texture = std.albedo_texture
	# The kit's atlases are 128px and import NEAREST; inheriting the filter keeps
	# a chunk looking like the prop rather than like a blurred version of it.
	m.texture_filter = std.texture_filter
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Chunks are convex and short-lived, so the back faces are never seen; not
	# culling them means the face winding above cannot render a chunk inside-out.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The same readability lift the flat-colour path gets, and for the same reason:
	# see _chunk_materials(). It is the prop's DOMINANT COLOUR at low energy, not
	# the albedo texture routed into emission - `emission_texture` with a white
	# emission colour rendered the whole pile as blown-out white blobs that the
	# corridor's glow pass then bloomed, which is worse than the darkness it was
	# meant to cure. A flat lift under a textured albedo keeps the texture reading.
	#
	# The energy is divided by the SQUARE of the prop's luminance, where the
	# flat-colour path divides by luminance once. Once the albedo is the real texel
	# rather than a palette colour, how much lift a prop needs falls off faster than
	# its own brightness does, and a linear divide cannot fit both ends of what this
	# level actually contains. Measured, with the energies that looked right:
	#
	#   prop    dominant lum   wants
	#   crate       0.196       ~0.67   (dark wood, uniformly dark texture)
	#   chest       0.315       ~0.26   (its pale metal already reads unaided)
	#
	# That is a ratio of 2.6 across a luminance ratio of 1.6, which is a square law,
	# and 0.026/lum^2 reproduces both. Tuned linearly, one end always broke: at the
	# crate's setting the chest came back a garish orange, at the chest's the crate
	# stayed a black lump.
	var lift := std.albedo_color
	var pal := _palette(source, std)
	if not pal.is_empty():
		lift = pal[0]["color"]
	var lum := maxf(lift.get_luminance(), 0.05)
	m.emission_enabled = true
	m.emission = lift
	m.emission_energy_multiplier = clampf(
		EMISSION_LIFT_TEX / (lum * lum), 0.0, EMISSION_MAX_TEX)
	return m

## The FALLBACK look, for a prop with no texture or no UVs: chunks take their
## colours from the prop's own texture, by finding the two or three DOMINANT ones
## rather than by averaging.
##
## **Averaging is the wrong operator for a multi-coloured texture.** The chest
## is roughly half brown wood and half BLUE steel banding, and the mean of those
## two sits almost exactly on grey: measured (0.21, 0.21, 0.20) at saturation
## 0.06. A brown chest shattered into grey cubes. Clustering the samples and
## keeping the biggest few instead gives wood (0.44, 0.30, 0.12) at saturation
## 0.73 as the largest, steel second - so the chest breaks into mostly brown
## pieces with a few steel-blue ones, which is what it looks like.
##
## Still used for the emission energy on the textured path, which is why it stays
## even though a textured prop no longer reaches the flat-colour branch.
##
## Samples are taken at each triangle's UV CENTROID, weighted by that triangle's
## area in 3D. The centroid is by construction inside a UV island, so the black
## sheet between islands is never sampled - a bounding-rectangle lattice picked up
## the background and dragged everything dark. Area weighting keeps a hundred tiny
## hinge triangles from outvoting the lid.
static func _chunk_materials(source: MeshInstance3D) -> Array[Material]:
	var out: Array[Material] = []
	if source == null or source.mesh == null:
		return out
	var src := source.get_active_material(0)
	if not (src is StandardMaterial3D):
		if src:
			out.append(src)
		return out
	var std := src as StandardMaterial3D
	for entry in _palette(source, std):
		var m := StandardMaterial3D.new()
		m.resource_name = "chunk"
		m.roughness = 1.0
		m.metallic = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		var col: Color = entry["color"]
		m.albedo_color = col
		# Lifted out of shadow, for the reason debris.gd goes unshaded outright:
		# the corridor level is pitch dark between its handful of lamps, and a
		# crate smashed between two of them leaves a pile of near-black lumps you
		# cannot read as anything. Chunks are geometry rather than particles, so
		# they keep their lighting and get a low emission of their own colour on
		# top - the same trick pickup.gd uses on the dropped dagger.
		#
		# The energy is SCALED BY HOW DARK THE COLOUR IS rather than fixed. A flat
		# value tuned on the crate's dark wood (luminance 0.19) badly overdrove the
		# chest's, which is twice as bright, and the tell was its steel-blue
		# pieces: under a red corridor lamp a blue surface should go nearly black,
		# and instead they glowed pale blue, because self-lit emission ignores the
		# colour of the light. Dividing by luminance lifts the near-black pieces
		# and leaves the bright ones to the lamps.
		#
		# Capped at both ends: corridors.tscn runs glow at an HDR threshold of
		# 1.25, and a pile of chunks that goes through it comes back as a bloomed
		# white blob.
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = clampf(
			EMISSION_LIFT / maxf(col.get_luminance(), 0.05), 0.0, EMISSION_MAX)
		m.set_meta(&"weight", entry["weight"])
		out.append(m)
	return out

## Picks one of the palette materials, in proportion to how much of the prop that
## colour covers - so a chest is mostly wood-coloured and only occasionally steel.
static func _pick(mats: Array[Material], rng: RandomNumberGenerator) -> Material:
	if mats.is_empty():
		return null
	if mats.size() == 1:
		return mats[0]
	var r := rng.randf()
	var acc := 0.0
	for m in mats:
		acc += float(m.get_meta(&"weight", 0.0))
		if r <= acc:
			return m
	return mats[0]

## Cached per mesh: every crate in the level shares one mesh resource, so this
## runs once for crates however many get smashed.
static var _palettes: Dictionary = {}

## The dominant colours of a mesh's texture, as [{color, weight}], weights
## normalised across the entries returned.
static func _palette(source: MeshInstance3D, std: StandardMaterial3D) -> Array[Dictionary]:
	var key := str(source.mesh.get_instance_id())
	if _palettes.has(key):
		return _palettes[key]
	var fallback: Array[Dictionary] = [{"color": std.albedo_color, "weight": 1.0}]
	var tex := std.albedo_texture
	if tex == null:
		_palettes[key] = fallback
		return fallback
	var img := tex.get_image()
	if img == null:
		_palettes[key] = fallback
		return fallback
	# get_pixel() cannot read a VRAM-compressed image, and the import setting is
	# not this script's to assume.
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()

	var arrays := source.mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_TEX_UV or arrays[Mesh.ARRAY_TEX_UV] == null:
		_palettes[key] = fallback
		return fallback
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	if uvs.is_empty():
		_palettes[key] = fallback
		return fallback

	var bins: Dictionary = {}
	var tris := idx.size() / 3 if idx.size() > 0 else uvs.size() / 3
	for t in range(tris):
		var i0: int
		var i1: int
		var i2: int
		if idx.size() > 0:
			i0 = idx[t * 3]; i1 = idx[t * 3 + 1]; i2 = idx[t * 3 + 2]
		else:
			i0 = t * 3; i1 = t * 3 + 1; i2 = t * 3 + 2
		if i2 >= uvs.size():
			continue
		var c: Vector2 = (uvs[i0] + uvs[i1] + uvs[i2]) / 3.0
		var area := 1.0
		if verts.size() > i2:
			area = maxf(1e-6,
				(verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]).length() * 0.5)
		var px := img.get_pixel(
			clampi(int(c.x * float(w)), 0, w - 1),
			clampi(int(c.y * float(h)), 0, h - 1))
		if px.a < 0.5:
			continue
		var bin := "%d_%d_%d" % [int(px.r * COLOR_BINS), int(px.g * COLOR_BINS),
			int(px.b * COLOR_BINS)]
		if not bins.has(bin):
			bins[bin] = [0.0, Color(0, 0, 0, 0)]
		bins[bin][0] += area
		bins[bin][1] += px * area
	if bins.is_empty():
		_palettes[key] = fallback
		return fallback

	var order := bins.keys()
	order.sort_custom(func(a, b): return bins[a][0] > bins[b][0])
	var kept: Array[Dictionary] = []
	var total := 0.0
	for i in range(mini(PALETTE_MAX, order.size())):
		var e: Array = bins[order[i]]
		var col: Color = e[1] / e[0]
		col.a = 1.0
		kept.append({"color": col, "weight": e[0]})
		total += e[0]
	for e in kept:
		e["weight"] = e["weight"] / total
	_palettes[key] = kept
	return kept

func _process(delta: float) -> void:
	_age += delta
	if _age < linger:
		return
	# Shrink out rather than blink out. Only the meshes are scaled - scaling the
	# bodies would drag their collision shapes with them and the pile would sag
	# through the floor as it went.
	var k := 1.0 - (_age - linger) / maxf(0.01, fade)
	if k <= 0.0:
		queue_free()
		return
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.scale = Vector3(k, k, k)
