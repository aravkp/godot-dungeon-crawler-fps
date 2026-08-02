extends SceneTree

## Generates the dungeon into res://scenes/main.tscn from the PSX_Dungeon kit.
##
## Re-runnable: it strips any previously generated "Dungeon" node first, so you
## can tweak the constants below and run it again:
##
##   Godot --headless --path . -s tools/build_dungeon.gd
##
## Kit facts this relies on (measured, not assumed):
##  - Pieces are authored at 1 unit = 10cm, so everything is scaled by 0.1.
##  - The grid module is 20 units = 2.0m; walls are 20 units tall.
##  - Pillars are 30.2 units, taller than one wall, so walls stack two high
##    to make a 4m room. Pillars get stretched slightly to meet the ceiling.
##  - FBX import loses texture links; materials are re-bound by material name.

const KIT := "res://assets/dungeon/%s.fbx"
const S := 0.1                  # kit units -> metres
const CELL := 2.0               # grid module in metres
const WALL_H := 2.0             # one wall module in metres
const ROOM_X := 5               # cells wide
const ROOM_Z := 7               # cells deep

# Enemy placement: down the hall, facing back toward the player.
const ENEMY_POS := Vector3(0, 0, -4.5)
const ENEMY_HEIGHT := 1.9       # metres
const ENEMY_FACING := 180.0     # degrees about Y

# Flying heads, hovering at head height around the hall.
# Reference width is measured DURING the idle animation (9.17 units); the
# rest pose reads 14.06 because the ear-wings are spread wider there.
const CHON_IDLE_WIDTH := 9.1687 # kit units, ear tip to ear tip, mid-idle
const CHON_WINGSPAN := 0.9      # metres, what that should become
const CHON_FACING := 0.0        # its face points +Z, so no turn needed
const CHON_SPOTS: Array[Vector3] = [
	Vector3(-2.5, 1.9, -1.0),
	Vector3(2.6, 2.2, -3.2),
	Vector3(0.6, 1.7, -6.0),
]

var _corr: Dictionary = {}
var _root: Node
var _dungeon: Node3D

func _init() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_root = packed.instantiate()

	_strip_placeholders()
	_dungeon = Node3D.new()
	_dungeon.name = "Dungeon"
	_dungeon.set_script(load("res://scripts/dungeon.gd"))
	_root.add_child(_dungeon)
	_dungeon.owner = _root

	_build_floor_and_ceiling()
	_build_walls()
	_build_pillars()
	_build_props()
	_build_collision()
	_build_lights()
	_place_enemy()
	_place_chonchons()
	_place_player()

	var out := PackedScene.new()
	var err := out.pack(_root)
	if err != OK:
		print("pack failed: ", err); quit(1); return
	err = ResourceSaver.save(out, "res://scenes/main.tscn")
	print("saved main.tscn err=", err, "  dungeon children=", _dungeon.get_child_count())
	quit()

# --- helpers ---------------------------------------------------------------

## Kit pieces are NOT authored at their origins - each was modelled at a
## different spot in the source file and exported without re-centring (a floor
## tile's geometry sits 50 units away from its node origin, a wall 60). So each
## piece needs a correction, in kit units, before placement means anything.
##
## anchor picks what the caller's Y refers to: "base" sits the piece on that
## height, "top" hangs it from there, "centre" centres it.
func _correction(model: String, anchor: String) -> Vector3:
	var key := model + ":" + anchor
	if _corr.has(key):
		return _corr[key]
	var inst := (load(KIT % model) as PackedScene).instantiate() as Node3D
	inst.transform = Transform3D.IDENTITY
	var acc := [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
	_accumulate(inst, Transform3D.IDENTITY, acc)
	var lo: Vector3 = acc[0]
	var hi: Vector3 = acc[1]
	var ctr: Vector3 = (lo + hi) * 0.5
	var y := lo.y
	if anchor == "top":
		y = hi.y
	elif anchor == "centre":
		y = ctr.y
	inst.free()
	var k := Vector3(-ctr.x, -y, -ctr.z)
	_corr[key] = k
	return k

## Walks the piece composing transforms by hand, so no SceneTree is needed.
func _accumulate(n: Node, t: Transform3D, acc: Array) -> void:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D:
		var a := (n as MeshInstance3D).get_aabb()
		for i in range(8):
			var p: Vector3 = lt * a.get_endpoint(i)
			acc[0] = acc[0].min(p)
			acc[1] = acc[1].max(p)
	for c in n.get_children():
		_accumulate(c, lt, acc)

## Instances a kit piece and parents it under the Dungeon node.
func _piece(model: String, nm: String, pos: Vector3, rot_y_deg: float = 0.0,
		scale: Vector3 = Vector3(S, S, S), rot: Vector3 = Vector3.INF,
		anchor: String = "base") -> Node3D:
	var path := KIT % model
	if not ResourceLoader.exists(path):
		push_warning("missing kit piece: " + model)
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	inst.name = nm
	_dungeon.add_child(inst)
	inst.owner = _root
	var euler := rot if rot != Vector3.INF else Vector3(0, rot_y_deg, 0)
	inst.rotation_degrees = euler
	inst.scale = scale
	# Shift by the piece's own baked-in offset, rotated and scaled to match.
	var k := _correction(model, anchor)
	var basis := Basis.from_euler(Vector3(deg_to_rad(euler.x), deg_to_rad(euler.y), deg_to_rad(euler.z)))
	inst.position = pos + basis * (k * scale)
	# Textures are re-bound at load time by scripts/dungeon.gd, not baked here.
	return inst

func _xs() -> Array:
	var a: Array = []
	for i in range(ROOM_X):
		a.append((i - (ROOM_X - 1) / 2.0) * CELL)
	return a

func _zs() -> Array:
	var a: Array = []
	for i in range(ROOM_Z):
		a.append((i - (ROOM_Z - 1) / 2.0) * CELL)
	return a

func _half_x() -> float:
	return ROOM_X * CELL / 2.0        # 5.0

func _half_z() -> float:
	return ROOM_Z * CELL / 2.0        # 7.0

# --- construction ----------------------------------------------------------

func _strip_placeholders() -> void:
	# The flat test plane, the reference boxes, and the outdoor sun.
	# "Terrain" too, so this and build_terrain.gd are mutually exclusive levels.
	for n in ["Floor", "Crate", "Pillar", "Platform", "Sun", "Dungeon", "Skeleton",
			"ChonChons", "Terrain"]:
		var node := _root.get_node_or_null(n)
		if node:
			_root.remove_child(node)
			node.queue_free()

func _build_floor_and_ceiling() -> void:
	for x in _xs():
		for z in _zs():
			_piece("Floor_Tiles", "Floor_%d_%d" % [int(x), int(z)], Vector3(x, 0, z))
			# Same tile flipped over to face down.
			_piece("Floor_Tiles", "Ceil_%d_%d" % [int(x), int(z)],
				Vector3(x, WALL_H * 2.0, z), 0.0, Vector3(S, S, S), Vector3(180, 0, 0))

func _build_walls() -> void:
	var rows: Array[float] = [0.0, WALL_H]
	for row: float in rows:
		var upper: bool = row > 0.0
		# North / south runs (walls span X, thin in Z).
		for x: float in _xs():
			# Leave a doorway in the south wall's lower row.
			var is_door: bool = (not upper) and absf(x) < 0.01
			_piece("Door_Frame_01" if is_door else "Wall_01",
				"Wall_S_%d_%d" % [int(x), int(row)], Vector3(x, row, _half_z()), 0.0)
			_piece("Wall_01", "Wall_N_%d_%d" % [int(x), int(row)],
				Vector3(x, row, -_half_z()), 180.0)
		# East / west runs (rotated a quarter turn).
		for z in _zs():
			_piece("Wall_01", "Wall_W_%d_%d" % [int(z), int(row)],
				Vector3(-_half_x(), row, z), 90.0)
			_piece("Wall_01", "Wall_E_%d_%d" % [int(z), int(row)],
				Vector3(_half_x(), row, z), 270.0)

func _build_pillars() -> void:
	# Pillar is 30.2 units (3.02m); stretch it to meet the 4m ceiling.
	var stretch := (WALL_H * 2.0) / (30.2 * S)
	var sc := Vector3(S, S * stretch, S)
	for x in [-2.0, 2.0]:
		for z in [-4.0, 4.0]:
			_piece("Pillar", "Pillar_%d_%d" % [int(x), int(z)], Vector3(x, 0, z), 0.0, sc)

func _build_props() -> void:
	_piece("Barrel", "Barrel_A", Vector3(-4.0, 0, -5.6), 15.0)
	_piece("Barrel", "Barrel_B", Vector3(-4.3, 0, -4.6), -20.0)
	_piece("Box", "Box_A", Vector3(4.1, 0, -5.4), 30.0)
	_piece("Chest", "Chest_A", Vector3(3.7, 0, 5.2), -110.0)
	_piece("Debris", "Debris_A", Vector3(1.6, 0, -2.0), 45.0)
	_piece("Candle_02", "Candle_A", Vector3(-4.2, 0, 1.0), 0.0)
	_piece("Candle_01", "Candle_B", Vector3(4.2, 0, -1.2), 0.0)
	# Hangs from the ceiling, so anchor its top rather than its base.
	_piece("Chandelier", "Chandelier_A", Vector3(0, WALL_H * 2.0, 0), 0.0,
		Vector3(S, S, S), Vector3.INF, "top")
	_piece("Door_01", "Door_A", Vector3(0, 0, _half_z()))

func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "DungeonCollision"
	_dungeon.add_child(body)
	body.owner = _root

	var hx := _half_x()
	var hz := _half_z()
	var h := WALL_H * 2.0
	var t := 0.5                       # wall thickness in metres
	# floor, ceiling, then the four wall runs
	var slabs := [
		[Vector3(0, -t / 2.0, 0), Vector3(hx * 2, t, hz * 2)],
		[Vector3(0, h + t / 2.0, 0), Vector3(hx * 2, t, hz * 2)],
		[Vector3(0, h / 2.0, -hz - t / 2.0), Vector3(hx * 2 + t * 2, h, t)],
		[Vector3(0, h / 2.0, hz + t / 2.0), Vector3(hx * 2 + t * 2, h, t)],
		[Vector3(-hx - t / 2.0, h / 2.0, 0), Vector3(t, h, hz * 2)],
		[Vector3(hx + t / 2.0, h / 2.0, 0), Vector3(t, h, hz * 2)],
	]
	for i in range(slabs.size()):
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = slabs[i][1]
		cs.shape = box
		cs.position = slabs[i][0]
		cs.name = "Slab_%d" % i
		body.add_child(cs)
		cs.owner = _root
	# Pillars, so you can't walk through them.
	var pi := 0
	for x in [-2.0, 2.0]:
		for z in [-4.0, 4.0]:
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.57, h, 0.57)
			cs.shape = box
			cs.position = Vector3(x, h / 2.0, z)
			cs.name = "PillarCol_%d" % pi
			body.add_child(cs)
			cs.owner = _root
			pi += 1

func _build_lights() -> void:
	# Indoors with a ceiling: the sky no longer lights anything.
	var lamps := [
		[Vector3(0, 2.7, 0), 4.0, 9.0],
		[Vector3(-4.2, 0.6, 1.0), 1.6, 4.0],
		[Vector3(4.2, 0.6, -1.2), 1.6, 4.0],
		[Vector3(0, 2.4, -5.4), 2.0, 6.0],
		[Vector3(0, 2.4, 5.4), 2.0, 6.0],
	]
	for i in range(lamps.size()):
		var l := OmniLight3D.new()
		l.name = "Lamp_%d" % i
		_dungeon.add_child(l)
		l.owner = _root
		l.position = lamps[i][0]
		l.light_energy = lamps[i][1]
		l.omni_range = lamps[i][2]
		l.light_color = Color(1.0, 0.76, 0.45)   # torchlight
		l.shadow_enabled = i == 0                # one shadow caster is enough
	var env := _root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env and env.environment:
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.16, 0.15, 0.20)
		env.environment.ambient_light_energy = 0.7

## The skeleton FBX has no rig or animations (verified: no Deformer/Skin/
## AnimationStack in the file), so it goes in as a static, solid body.
## Its mesh is lifted out of the import and given a plain MeshInstance3D, which
## lets the material bake into main.tscn - unlike nodes inside an instanced
## scene, whose overrides pack() silently drops.
func _place_enemy() -> void:
	var src := (load("res://assets/skeleton/skeleton.fbx") as PackedScene).instantiate() as Node3D
	src.transform = Transform3D.IDENTITY
	var acc := [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
	_accumulate(src, Transform3D.IDENTITY, acc)
	var lo: Vector3 = acc[0]
	var hi: Vector3 = acc[1]
	var ctr: Vector3 = (lo + hi) * 0.5

	# The mesh alone is not enough: the MeshInstance3D inside the FBX carries a
	# x100 scale and a -90 deg X rotation (Blender Z-up). Drop that and you get
	# a 3cm speck lying on its face, so capture the transform down to it.
	var mesh: Mesh = null
	var inner := Transform3D.IDENTITY
	var found := _find_mesh(src, Transform3D.IDENTITY)
	if found.is_empty():
		push_warning("skeleton: no mesh found")
		src.free()
		return
	mesh = found["mesh"]
	inner = found["xform"]

	var s := ENEMY_HEIGHT / (hi.y - lo.y)

	var body := StaticBody3D.new()
	body.name = "Skeleton"
	_root.add_child(body)
	body.owner = _root
	body.position = ENEMY_POS
	body.rotation_degrees = Vector3(0, ENEMY_FACING, 0)
	body.add_to_group("enemies", true)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	body.add_child(mi)
	mi.owner = _root
	mi.mesh = mesh
	# Centre horizontally, stand on the floor, then re-apply the FBX's own
	# inner transform so the geometry keeps its authored scale and orientation.
	var place := Transform3D(
		Basis.IDENTITY.scaled(Vector3(s, s, s)),
		Vector3(-ctr.x, -lo.y, -ctr.z) * s)
	mi.transform = place * inner

	var mat := StandardMaterial3D.new()
	mat.resource_name = "SkeletonBase"
	mat.albedo_texture = load("res://assets/skeleton/base.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Thin bones read better without backface culling.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in range(mesh.get_surface_count()):
		mi.set_surface_override_material(i, mat)

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = _root
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = ENEMY_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, ENEMY_HEIGHT / 2.0, 0)
	src.free()

## ChonChons are properly rigged (22 bones, plus fly attack / hit reaction /
## death), so unlike the skeleton these are instanced whole and driven by
## scripts/chonchon.gd.
##
## Their size can't come from the mesh AABB: it's a skinned mesh, so vertices
## follow bone matrices rather than the node transform and the raw AABB reports
## millions of units. Measured from the bones instead - 14.06 units wingspan.
func _place_chonchons() -> void:
	var flock := Node3D.new()
	flock.name = "ChonChons"
	_root.add_child(flock)
	flock.owner = _root

	var s := CHON_WINGSPAN / CHON_IDLE_WIDTH
	var centre := Vector3(-0.563188, 0.821415, 2.552688)   # bone-space centre
	var i := 0
	for spot: Vector3 in CHON_SPOTS:
		var body := StaticBody3D.new()
		body.name = "ChonChon_%d" % i
		body.set_script(load("res://scripts/chonchon.gd"))
		flock.add_child(body)
		body.owner = _root
		body.position = spot
		body.rotation_degrees = Vector3(0, CHON_FACING, 0)
		body.add_to_group("enemies", true)

		var model := (load("res://assets/chonchon/chonchon.fbx") as PackedScene).instantiate() as Node3D
		model.name = "Model"
		body.add_child(model)
		model.owner = _root
		model.scale = Vector3(s, s, s)
		model.position = -centre * s          # centre the creature on its node

		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		body.add_child(cs)
		cs.owner = _root
		var sph := SphereShape3D.new()
		sph.radius = 0.28
		cs.shape = sph
		i += 1

## Returns the first mesh plus its transform relative to the piece root.
func _find_mesh(n: Node, t: Transform3D) -> Dictionary:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return {"mesh": (n as MeshInstance3D).mesh, "xform": lt}
	for c in n.get_children():
		var r := _find_mesh(c, lt)
		if not r.is_empty():
			return r
	return {}

func _place_player() -> void:
	var p := _root.get_node_or_null("Player") as Node3D
	if p:
		# Just inside the doorway, looking up the hall.
		p.position = Vector3(0, 1.2, 5.0)
		p.rotation_degrees = Vector3.ZERO
