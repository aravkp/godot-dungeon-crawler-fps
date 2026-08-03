extends SceneTree

## Generates res://scenes/corridors.tscn - a Post Void style corridor crawl
## built from the PSX dungeon kit.
##
##   Godot --headless --path . -s tools/build_corridors.gd
##
## Unlike build_terrain.gd and build_dungeon.gd this does NOT write main.tscn.
## It loads main.tscn only to inherit the working Player / Arms / DaggerMount /
## HUD rig, strips every level node, builds the corridors, and saves elsewhere.
## So it is not mutually exclusive with the other two - it is a separate level.
##
## Layout is a seeded drunkard's walk on a COARSE grid where one coarse cell is
## 2x2 kit modules (4x4 m). Corridors are therefore exactly one coarse cell
## wide, turns are trivial, and rooms are a 2x2 coarse block. Change SEED for a
## different dungeon; everything else follows.

const BASE := "res://scenes/main.tscn"
const OUT := "res://scenes/corridors.tscn"
const KIT := "res://assets/dungeon/%s.fbx"
const WATCHER_SCENE := "res://scenes/watcher.tscn"
const CHEST_SCENE := "res://scenes/chest.tscn"
const BREAKABLE := "res://scripts/breakable.gd"
## A gate's leaf gets this instead: breakable.gd plus the [E] that lifts it.
const DOOR := "res://scripts/door.gd"
## The opening cutscene, and the thing that delivers it.
const CUTSCENE := "res://scripts/cutscene.gd"
const CREATURE := "res://assets/creature/creature.fbx"
## Imported at scale 100, which makes it 8.79 m tall - taller than the 4 m
## corridor. Brought down to this, which in a 4 m corridor looms a clear head
## over a 2 m player without touching the ceiling. The scale is derived from the
## model's MEASURED bounds rather than from that 8.79, and so is the offset that
## puts its feet on the floor - see _place_cutscene().
const CREATURE_HEIGHT := 3.0

const S := 0.1                  # kit units -> metres
const CELL := 2.0               # one kit module, in metres
const WALL_H := 2.0             # one wall module
const ROWS := 2                 # stacked wall rows -> 4m ceiling
const WALL_T := 0.4             # collision thickness

const SEED := 20260730
const SEGMENTS := 11            # straight runs before the walk gives up
const SEG_MIN := 3
const SEG_MAX := 5
const ROOM_CHANCE := 0.34

## Every Nth coarse cell along the route gets a lamp / a pack of watchers.
const LAMP_EVERY := 2
const PACK_EVERY := 4

var _rng := RandomNumberGenerator.new()
var _root: Node
var _level: Node3D
var _corr: Dictionary = {}          # piece correction cache
var _size: Dictionary = {}          # piece bounds cache, in kit units
var _coarse: Dictionary = {}        # Vector2i -> true
var _cells: Dictionary = {}         # fine Vector2i -> true
var _route: Array[Vector2i] = []    # coarse cells, in walk order
var _start_dir := Vector2i(0, -1)

func _init() -> void:
	_rng.seed = SEED
	_root = (load(BASE) as PackedScene).instantiate()
	_strip()

	_level = Node3D.new()
	_level.name = "Corridors"
	# Re-binds the kit's atlas textures by material name; FBX import drops them.
	_level.set_script(load("res://scripts/dungeon.gd"))
	_root.add_child(_level)
	_level.owner = _root

	_carve()
	_expand_to_fine()
	_build_shell()
	_build_collision()
	_build_lights()
	_build_environment()
	_place_gates()
	# After the gates, so a ramp never lands on a gate's cell; before the props,
	# so a crate never lands under one and blocks the crouch line.
	_place_ramps()
	_place_props()
	_place_enemies()
	_place_goal()
	_place_player()
	_light_viewmodel()
	_place_cutscene()

	var packed := PackedScene.new()
	var err := packed.pack(_root)
	if err != OK:
		print("pack failed: ", err)
		quit(1)
		return
	err = ResourceSaver.save(packed, OUT)
	print("saved %s err=%d  coarse=%d fine=%d pieces=%d"
		% [OUT, err, _coarse.size(), _cells.size(), _level.get_child_count()])
	quit()

func _strip() -> void:
	for n in ["Terrain", "Camps", "Sun", "BatSpawner", "Dungeon", "Skeleton",
			"ChonChons", "Floor", "Crate", "Pillar", "Platform", "Bat", "Corridors"]:
		var node := _root.get_node_or_null(n)
		if node:
			_root.remove_child(node)
			node.queue_free()

# --- layout ----------------------------------------------------------------

func _carve() -> void:
	var pos := Vector2i.ZERO
	var dir := _start_dir
	_coarse[pos] = true
	_route.append(pos)

	for s in range(SEGMENTS):
		var run := _rng.randi_range(SEG_MIN, SEG_MAX)
		for i in range(run):
			var nxt: Vector2i = pos + dir
			if _coarse.has(nxt):
				break               # never cross our own path
			pos = nxt
			_coarse[pos] = true
			_route.append(pos)

		if _rng.randf() < ROOM_CHANCE:
			_carve_room(pos, dir)

		# Turn. Try both ways so a boxed-in walk still finds an exit.
		var left := Vector2i(dir.y, -dir.x)
		var right := Vector2i(-dir.y, dir.x)
		# Built out longhand: a ternary yields an untyped Array, which will not
		# assign to Array[Vector2i].
		var opts: Array[Vector2i] = []
		if _rng.randf() < 0.5:
			opts.append(left)
			opts.append(right)
		else:
			opts.append(right)
			opts.append(left)
		var turned := false
		for o in opts:
			if not _coarse.has(pos + o):
				dir = o
				turned = true
				break
		if not turned:
			break

## An 8x8m chamber hung off the corridor - somewhere to actually fight.
func _carve_room(at: Vector2i, dir: Vector2i) -> void:
	var perp := Vector2i(dir.y, -dir.x)
	for a in range(2):
		for b in range(2):
			_coarse[at + dir * a + perp * b] = true

func _expand_to_fine() -> void:
	for c: Vector2i in _coarse:
		for i in range(2):
			for j in range(2):
				_cells[Vector2i(c.x * 2 + i, c.y * 2 + j)] = true

func _world(fine: Vector2i) -> Vector3:
	return Vector3(float(fine.x) * CELL, 0.0, float(fine.y) * CELL)

func _coarse_world(c: Vector2i) -> Vector3:
	# Centre of the 2x2 fine block.
	return Vector3((float(c.x) * 2.0 + 0.5) * CELL, 0.0, (float(c.y) * 2.0 + 0.5) * CELL)

# --- kit placement (same measured-correction trick as build_dungeon) --------

## World bounds of a kit piece, in kit units. FBX pieces here are not authored at
## their origins (the kit's geometry sits 50-60 units out), so this is measured
## rather than read off the node - and a mesh-local AABB would hide it.
func _bounds(model: String) -> AABB:
	if _size.has(model):
		return _size[model]
	var inst := (load(KIT % model) as PackedScene).instantiate() as Node3D
	inst.transform = Transform3D.IDENTITY
	var acc := [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
	_accumulate(inst, Transform3D.IDENTITY, acc)
	inst.free()
	var ab := AABB(acc[0], acc[1] - acc[0])
	_size[model] = ab
	return ab

func _correction(model: String, anchor: String) -> Vector3:
	var key := model + ":" + anchor
	if _corr.has(key):
		return _corr[key]
	var ab := _bounds(model)
	var lo := ab.position
	var hi := ab.position + ab.size
	var ctr := (lo + hi) * 0.5
	var y := lo.y
	if anchor == "top":
		y = hi.y
	elif anchor == "centre":
		y = ctr.y
	var k := Vector3(-ctr.x, -y, -ctr.z)
	_corr[key] = k
	return k

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

func _piece(model: String, nm: String, pos: Vector3, rot_y_deg: float = 0.0,
		scale: Vector3 = Vector3(S, S, S), rot: Vector3 = Vector3.INF,
		anchor: String = "base", parent: Node = null) -> Node3D:
	var path := KIT % model
	if not ResourceLoader.exists(path):
		push_warning("missing kit piece: " + model)
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	inst.name = nm
	var host: Node = parent if parent else _level
	host.add_child(inst)
	inst.owner = _root
	var euler := rot if rot != Vector3.INF else Vector3(0, rot_y_deg, 0)
	inst.rotation_degrees = euler
	inst.scale = scale
	var k := _correction(model, anchor)
	var basis := Basis.from_euler(Vector3(deg_to_rad(euler.x), deg_to_rad(euler.y),
		deg_to_rad(euler.z)))
	inst.position = pos + basis * (k * scale)
	return inst

# --- construction ----------------------------------------------------------

## Neighbour offset -> the Y rotation a Wall_01 needs to face inward.
const EDGES := {
	Vector2i(0, 1): 0.0,
	Vector2i(0, -1): 180.0,
	Vector2i(-1, 0): 90.0,
	Vector2i(1, 0): 270.0,
}

func _build_shell() -> void:
	var ceil_y := WALL_H * float(ROWS)
	for fine: Vector2i in _cells:
		var p := _world(fine)
		_piece("Floor_Tiles", "F_%d_%d" % [fine.x, fine.y], p)
		_piece("Floor_Tiles", "C_%d_%d" % [fine.x, fine.y],
			p + Vector3(0, ceil_y, 0), 0.0, Vector3(S, S, S), Vector3(180, 0, 0))
		for off: Vector2i in EDGES:
			if _cells.has(fine + off):
				continue
			var edge := p + Vector3(float(off.x), 0.0, float(off.y)) * (CELL * 0.5)
			for r in range(ROWS):
				_piece("Wall_01", "W_%d_%d_%d_%d" % [fine.x, fine.y, off.x + 2 * off.y, r],
					edge + Vector3(0, WALL_H * float(r), 0), EDGES[off])

## One slab for the floor and one for the ceiling across the whole footprint -
## the walls make the empty parts unreachable, so per-cell floor colliders would
## be hundreds of shapes for no gain. Walls still need one box per open edge.
func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	_level.add_child(body)
	body.owner = _root

	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for fine: Vector2i in _cells:
		lo.x = mini(lo.x, fine.x); lo.y = mini(lo.y, fine.y)
		hi.x = maxi(hi.x, fine.x); hi.y = maxi(hi.y, fine.y)
	var mid := Vector3((float(lo.x + hi.x) * 0.5) * CELL, 0.0,
		(float(lo.y + hi.y) * 0.5) * CELL)
	var span := Vector3(float(hi.x - lo.x + 1) * CELL, 0.0, float(hi.y - lo.y + 1) * CELL)
	var ceil_y := WALL_H * float(ROWS)

	_slab(body, "FloorSlab", mid + Vector3(0, -WALL_T * 0.5, 0),
		Vector3(span.x, WALL_T, span.z))
	_slab(body, "CeilSlab", mid + Vector3(0, ceil_y + WALL_T * 0.5, 0),
		Vector3(span.x, WALL_T, span.z))

	var n := 0
	for fine: Vector2i in _cells:
		var p := _world(fine)
		for off: Vector2i in EDGES:
			if _cells.has(fine + off):
				continue
			var edge := p + Vector3(float(off.x), 0.0, float(off.y)) * (CELL * 0.5)
			var size := Vector3(CELL, ceil_y, WALL_T) if off.x == 0 \
				else Vector3(WALL_T, ceil_y, CELL)
			_slab(body, "W_%d" % n, edge + Vector3(0, ceil_y * 0.5, 0), size)
			n += 1

func _slab(body: StaticBody3D, nm: String, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = nm
	body.add_child(cs)
	cs.owner = _root
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos

## Post Void runs on saturated, sourceless colour. Mostly hot red with cold
## intrusions, so a turn ahead reads as a different colour before you reach it.
const LAMP_COLORS := [
	Color(1.0, 0.12, 0.18),
	Color(1.0, 0.30, 0.05),
	Color(0.25, 0.45, 1.0),
	Color(1.0, 0.10, 0.55),
	Color(0.10, 0.95, 0.75),
]

func _build_lights() -> void:
	var lit := 0
	for i in range(_route.size()):
		if i % LAMP_EVERY != 0:
			continue
		var l := OmniLight3D.new()
		l.name = "Lamp_%d" % i
		_level.add_child(l)
		l.owner = _root
		l.position = _coarse_world(_route[i]) + Vector3(0, WALL_H * 1.45, 0)
		l.light_color = LAMP_COLORS[(i / LAMP_EVERY) % LAMP_COLORS.size()]
		l.light_energy = _rng.randf_range(3.0, 4.6)
		l.omni_range = 7.5
		# Shadow-casting omnis are the expensive part; a few is plenty.
		l.shadow_enabled = lit % 4 == 0
		lit += 1

func _build_environment() -> void:
	var env := _root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env == null or env.environment == null:
		push_warning("no WorldEnvironment")
		return
	var e := env.environment
	# Indoors and sealed: no sky, and the panorama would leak through nothing.
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.01, 0.03)
	e.sky = null
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.10, 0.16)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	# Short, thick fog - you should not be able to see far enough down a
	# corridor to plan. This is the main thing that sells the claustrophobia.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.35, 0.05, 0.10)
	e.fog_light_energy = 1.0
	e.fog_depth_begin = 3.0
	e.fog_depth_end = 26.0
	e.fog_density = 1.0
	e.fog_sky_affect = 0.0
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.25
	# Above the lit dagger blade (bright steel albedo), below the lamps at
	# energy 3+. Any lower and the blade blooms into a featureless white bar.
	e.glow_hdr_threshold = 1.25

## --- doors -----------------------------------------------------------------
##
## A gate seals the corridor at a boundary between two route cells and has to be
## smashed through. Sizes are measured (tools/_probe_kit_sizes.gd prints the
## front silhouette of a piece, so the doorway is read off the geometry rather
## than guessed):
##
##   Door_Frame_01  2.0 x 2.0 x 0.5 m at S, with a 1.0 x 1.5 m opening
##   Door_01        1.0 x 1.5 x 0.2 m at S - exactly that opening
##
## Native scale is unusable: a 1.5 m doorway is shorter than the 2 m player
## capsule, so there is no walking through it once it is broken. Scaled x2 across
## and up (and left alone in depth, so the jamb keeps its thickness) one frame
## spans the whole 4 x 4 m corridor cross-section on its own and the opening
## becomes a generous 2.0 x 3.0 m. That is why a gate is one piece rather than
## two side by side.
const GATE_FRAME := "Door_Frame_01"
const GATE_DOOR := "Door_01"
const GATE_SCALE := Vector3(S * 2.0, S * 2.0, S)
## One swing, like everything else breakable. A gate is no longer a wall with a
## fixed cost in swings - it is a choice between one swing and one E, so making
## the smash expensive only made the choice a formality.
const DOOR_HITS := 1
const DOOR_COLOR := Color(0.38, 0.26, 0.14)
## One gate per this many eligible choke points.
const DOOR_EVERY := 3
## Every this-many-th gate after the first is jammed partway open - duck under it
## or smash it, but you cannot lift it. See door.gd.
const JAM_EVERY := 2

## The route index of the first gate, or -1 if the seed produced none. Enemies
## are kept strictly past it - see _is_pack_cell().
var _first_gate_i: int = -1

func _place_gates() -> void:
	var eligible := 0
	var n := 0
	var jammed := 0
	# Never on the very first boundary: the player should see one coming before
	# meeting one.
	for i in range(2, _route.size() - 1):
		var a: Vector2i = _route[i]
		var b: Vector2i = _route[i + 1]
		var dir: Vector2i = b - a
		if absi(dir.x) + absi(dir.y) != 1:
			continue
		if not _is_choke(a, b, Vector2i(dir.y, -dir.x)):
			continue
		eligible += 1
		if eligible % DOOR_EVERY != 1:
			continue
		# The FIRST gate is never jammed. It is where the player learns that a
		# gate is a thing you open, and a jammed one teaches the wrong lesson
		# first. After that every JAM_EVERY-th one is stuck partway up and has to
		# be ducked under or smashed.
		var is_jammed := n > 0 and n % JAM_EVERY == 0
		_gate("Gate_%02d" % n, _coarse_world(a) + Vector3(float(dir.x), 0.0, float(dir.y)) * CELL,
			EDGES[dir], is_jammed)
		if _first_gate_i < 0:
			_first_gate_i = i
		if is_jammed:
			jammed += 1
		_gate_at[i] = true
		n += 1
	print("  gates=%d of %d chokes (%d jammed)  first at route %d"
		% [n, eligible, jammed, _first_gate_i])

## A gate is only worth building where the corridor is exactly one cell wide on
## both sides of the boundary. Hung off a room, half of it would seal nothing and
## the player would simply walk around the door.
func _is_choke(a: Vector2i, b: Vector2i, perp: Vector2i) -> bool:
	for c: Vector2i in [a, b]:
		if _coarse.has(c + perp) or _coarse.has(c - perp):
			return false
	return true

## The gate node carries the yaw; everything inside it is built square, with
## local +X across the corridor and local +Z along the direction of travel.
func _gate(nm: String, at: Vector3, yaw: float, jammed: bool = false) -> void:
	var gate := Node3D.new()
	gate.name = nm
	_level.add_child(gate)
	gate.owner = _root
	gate.position = at
	gate.rotation_degrees = Vector3(0, yaw, 0)

	_piece(GATE_FRAME, "Frame", Vector3.ZERO, 0.0, GATE_SCALE, Vector3.INF, "base", gate)

	# The frame's solid parts, from the measured silhouette: two 1 m jambs either
	# side of the 2 m opening, and a 1 m lintel over it up to the 4 m ceiling.
	# The doorway itself is left clear - the leaf below fills it, and once that is
	# smashed the hole is real.
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	gate.add_child(solid)
	solid.owner = _root
	var depth := 0.5
	_slab(solid, "JambL", Vector3(-1.5, 2.0, 0), Vector3(1.0, 4.0, depth))
	_slab(solid, "JambR", Vector3(1.5, 2.0, 0), Vector3(1.0, 4.0, depth))
	_slab(solid, "Lintel", Vector3(0, 3.5, 0), Vector3(2.0, 1.0, depth))

	# A door is a crate with a collider that happens to fill a doorway, plus one
	# thing of its own: door.gd adds the [E] that lifts it. Blocking the corridor
	# still needs nothing - that is just the box.
	# Turned to face back down the corridor: the leaf's lit side is its local -Z,
	# and the player always arrives from the gate's -Z.
	# `jammed` travels with the other exports because door.gd reads it in _ready(),
	# which add_child() runs immediately. Raising the leaf, on the other hand, has
	# to happen HERE and afterwards: _breakable sets position on the line after
	# add_child, so a lift applied inside _ready() is overwritten before anyone
	# sees it. The builder owns where things are.
	var leaf := _breakable(GATE_DOOR, "Door", Vector3.ZERO, 180.0, DOOR_HITS,
		DOOR_COLOR, GATE_SCALE, gate, DOOR, {"jammed": jammed})
	if jammed and leaf:
		leaf.position.y += leaf.get("jam_gap")

	# The corridor lamps sit at cell centres, so a gate on a boundary lands
	# between two of them and the leaf renders as a black hole in the wall - the
	# one thing an obstacle you are meant to attack cannot look like. Its own
	# lamp on the approach side both lights the door and makes gates read as a
	# category from down the corridor. Warm, so it is not mistaken for one of the
	# route lamps' saturated colours.
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	gate.add_child(lamp)
	lamp.owner = _root
	# Level with the middle of the leaf rather than up by the ceiling: the door is
	# the thing that has to be lit, and the higher the lamp sat the more of its
	# throw landed on ceiling tiles and the further the amber washed down the
	# corridor over the route's own colour.
	lamp.position = Vector3(0, 1.7, -1.3)
	lamp.light_color = Color(1.0, 0.62, 0.20)
	lamp.light_energy = 2.0
	lamp.omni_range = 5.0
	lamp.shadow_enabled = false

# --- collapsed ramps -------------------------------------------------------

## A slab of the ceiling that has come down across the corridor and wedged
## itself there. You CROUCH under its low edge.
##
## It is the crouch tutorial before it is an obstacle, which is why the first one
## goes in EARLY - before the first gate, while nothing is chasing the player.
## Meeting a jammed gate as the first thing you ever have to duck under teaches
## the mechanic in the middle of a fight.
##
## Deliberately NOT built from the dungeon kit. It is boxes wearing a texture the
## kit never uses - a pale granite where the shell is warm brick - because a
## collapse has to read as "this was not built like this" at a glance, and down a
## dark corridor the only thing carrying that is the material.
const RAMP_TEX := "res://assets/textures/Stone/Horror_Stone_05-512x512.png"
## How many of the eligible straights get one, and the ceiling on that. Which
## ones is drawn from _rng, so ramps move with SEED like everything else here.
const RAMP_FRACTION := 0.45
const RAMP_MAX := 5
## Minimum route indices between two ramps, so a seed cannot stack them.
const RAMP_MIN_SPACING := 4
## Route indices reserved for the opening and kept clear of ramps: 0 is the
## spawn, **1 is where the Warden rises for the cutscene**, 2 is the dagger
## chest. A ramp on any of them is built through the opening scene.
const RAMP_CLEAR_ROUTE := 2
const RAMP_TILT_DEG := 22.0
## Clearance under the low edge. Has to sit between the crouched player capsule
## (1.15 m) and the standing one (2.0 m), clear of both - see player.gd.
const RAMP_GAP := 1.32
const RAMP_LENGTH := 3.6
const RAMP_THICK := 0.36
## Corridor cross-section: a coarse cell is 2x2 kit modules.
const CORRIDOR_W := CELL * 2.0

## Route indices that already carry something, so the next placer can avoid them.
var _gate_at := {}
var _ramp_at := {}

func _place_ramps() -> void:
	var mat := _ramp_material()
	var candidates: Array[int] = []
	for i in range(1, _route.size() - 1):
		if _ramp_ok(i):
			candidates.append(i)
	var chosen := _choose_ramps(candidates)
	for i in chosen:
		var a: Vector2i = _route[i]
		var dir: Vector2i = _route[i + 1] - a
		_ramp("Ramp_%02d" % _ramp_at.size(), _coarse_world(a), EDGES[dir], mat)
		_ramp_at[i] = true
	# Candidates are printed too: when no ramp lands before the first gate it is
	# because the seed offered no eligible cell there, not because the picker
	# ignored one, and only this line tells the two apart.
	print("  ramps=%d at routes %s   (candidates %s, first gate %d)"
		% [chosen.size(), str(chosen), str(candidates), _first_gate_i])

## Can a cell take a collapsed ramp at all?
func _ramp_ok(i: int) -> bool:
	# Nothing in the opening. Route 1 is where the Warden rises, and a ramp there
	# is built straight through the cutscene - which is exactly what the first
	# version of this did, because it took the first eligible straight and route
	# 1 is usually it.
	if i <= RAMP_CLEAR_ROUTE:
		return false
	# A gate recorded at index j stands on the boundary between cells j and j+1,
	# so BOTH j and j-1 put one within 2 m of this cell's centre - close enough
	# that the leaf stands inside the crouch gap and seals the very thing you are
	# meant to duck through. Checking only `i` misses half of them.
	if _gate_at.has(i) or _gate_at.has(i - 1):
		return false
	if _is_pack_cell(i):
		return false
	var a: Vector2i = _route[i]
	var dir: Vector2i = _route[i + 1] - a
	if absi(dir.x) + absi(dir.y) != 1:
		return false
	# Straight only. On a turn the slab spans the wrong axis and one end buries
	# itself in the outside wall while the other pokes into the open.
	if a - _route[i - 1] != dir:
		return false
	return _is_choke(a, _route[i + 1], Vector2i(dir.y, -dir.x))

## Which eligible cells actually get one. Drawn from `_rng`, so the ramps are a
## function of SEED like the rest of the level rather than of the order the route
## happens to be walked in.
func _choose_ramps(candidates: Array[int]) -> Array[int]:
	if candidates.is_empty():
		return []
	var pool := candidates.duplicate()
	# Fisher-Yates on _rng, NOT Array.shuffle() - that draws from the global RNG,
	# and the level would stop being reproducible from SEED.
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t: int = pool[i]
		pool[i] = pool[j]
		pool[j] = t

	var out: Array[int] = []
	# One before the first gate if the seed offers one at all. The first ramp a
	# player meets is where crouch gets taught, and after the first gate means
	# teaching it with watchers already in play. WHICH early cell is still the
	# seed's choice - the pool is already shuffled - only that there is one.
	if _first_gate_i > 0:
		for i in pool:
			if i < _first_gate_i:
				out.append(i)
				break

	var want: int = clampi(int(round(candidates.size() * RAMP_FRACTION)), 1, RAMP_MAX)
	for i in pool:
		if out.size() >= want:
			break
		var spaced := true
		for k in out:
			if absi(k - i) < RAMP_MIN_SPACING:
				spaced = false
				break
		if spaced:
			out.append(i)
	out.sort()
	return out

## Triplanar, because a BoxMesh's own UVs stretch a 4.4 x 0.36 x 3.6 slab into
## smears and the whole point of this thing is that its material reads clearly.
func _ramp_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var t := load(RAMP_TEX) as Texture2D
	if t:
		m.albedo_texture = t
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	else:
		push_warning("missing ramp texture: " + RAMP_TEX)
	m.roughness = 0.95
	return m

## Local +X across the corridor, +Z along the direction of travel - the same
## convention the gates use. The player arrives from -Z, so the -Z edge is the
## low one: they meet the gap before they meet the slab.
func _ramp(nm: String, at: Vector3, yaw: float, mat: Material) -> void:
	var root := Node3D.new()
	root.name = nm
	_level.add_child(root)
	root.owner = _root
	root.position = at
	root.rotation_degrees = Vector3(0, yaw, 0)

	var body := StaticBody3D.new()
	body.name = "Solid"
	root.add_child(body)
	body.owner = _root

	# Negative tilt drops the -Z end: rotating about X by t sends a point at
	# z = -L/2 to y = +L/2 * sin(t), so a negative t is what puts the low edge on
	# the side the player walks in from.
	var tilt := deg_to_rad(RAMP_TILT_DEG)
	# Where the centre has to sit for the low edge's UNDERSIDE to land on
	# RAMP_GAP: half the slab's rise, plus its thickness measured vertically.
	var half_rise := RAMP_LENGTH * 0.5 * sin(tilt)
	var vert_thick := RAMP_THICK * 0.5 / cos(tilt)
	var centre_y := RAMP_GAP + half_rise + vert_thick

	# Wider than the corridor so it buries its ends in the walls and cannot be
	# walked around - the ramp is a gap to fit through, not an obstacle to skirt.
	_ramp_box(body, "Slab", Vector3(0, centre_y, 0),
		Vector3(CORRIDOR_W + 0.4, RAMP_THICK, RAMP_LENGTH),
		Vector3(-RAMP_TILT_DEG, 0, 0), mat)

	# What is holding it up, in the two corners of the low end. They also pinch
	# the gap to the middle of the corridor, so ducking through is a line the
	# player has to aim at rather than a whole wall that happens to be short.
	var low_z := -RAMP_LENGTH * 0.5 + 0.35
	for side: float in [1.0, -1.0]:
		_ramp_box(body, "Prop%s" % ("L" if side < 0.0 else "R"),
			Vector3(side * (CORRIDOR_W * 0.5 - 0.35), RAMP_GAP * 0.5, low_z),
			Vector3(0.7, RAMP_GAP, 0.8), Vector3.ZERO, mat)

	# Loose spill on the floor, so it looks like something fell rather than like
	# a slab that was installed. No collider: ankle height, same rule as DECOR.
	for j in range(3):
		var chunk := MeshInstance3D.new()
		chunk.name = "Chunk%d" % j
		var bm := BoxMesh.new()
		bm.size = Vector3(_rng.randf_range(0.3, 0.7), _rng.randf_range(0.2, 0.4),
			_rng.randf_range(0.3, 0.7))
		chunk.mesh = bm
		chunk.material_override = mat
		root.add_child(chunk)
		chunk.owner = _root
		chunk.position = Vector3(_rng.randf_range(-1.6, 1.6), bm.size.y * 0.5,
			low_z + _rng.randf_range(-0.9, 0.2))
		chunk.rotation.y = _rng.randf_range(0.0, TAU)

func _ramp_box(body: StaticBody3D, nm: String, pos: Vector3, size: Vector3,
		rot_deg: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	body.add_child(mi)
	mi.owner = _root
	mi.position = pos
	mi.rotation_degrees = rot_deg

	var cs := CollisionShape3D.new()
	cs.name = nm + "Col"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	cs.owner = _root
	cs.position = pos
	cs.rotation_degrees = rot_deg

## A prop wrapped in a smashable body: the kit model under "Art", a box collider
## sized from the piece's own measured bounds, and breakable.gd on the root.
##
## The whole body carries the yaw and the art sits square inside it, rather than
## the other way round - an unrotated box shape then matches the model exactly,
## with no need to rotate the collider to follow it.
##
## Exported properties are set BEFORE add_child(), because add_child() runs
## _ready() immediately and anything read there would predate the override.
func _breakable(model: String, nm: String, pos: Vector3, yaw: float,
		hits: int, color: Color, piece_scale: Vector3 = Vector3(S, S, S),
		parent: Node = null, script_path: String = BREAKABLE,
		props: Dictionary = {}) -> Node3D:
	if not ResourceLoader.exists(KIT % model):
		push_warning("missing kit piece: " + model)
		return null
	var body := StaticBody3D.new()
	body.name = nm
	body.set_script(load(script_path))
	body.set("hits", hits)
	body.set("debris_color", color)
	# Anything else the script exports - `jammed` on a door leaf, say. Same
	# before-add_child rule as the two above, and the reason this is a bag rather
	# than more parameters is that only door.gd uses it.
	for k: String in props:
		body.set(k, props[k])
	var host: Node = parent if parent else _level
	host.add_child(body)
	body.owner = _root
	body.position = pos
	body.rotation_degrees = Vector3(0, yaw, 0)

	_piece(model, "Art", Vector3.ZERO, 0.0, piece_scale, Vector3.INF, "base", body)

	var ab := _bounds(model)
	var size := ab.size * piece_scale
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = _root
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	# _piece anchors the art with its base at the body origin, so the box that
	# wraps it is centred half a height up.
	cs.position = Vector3(0, size.y * 0.5, 0)
	return body

## Crates that can be smashed, and the colour they break into. Everything that
## deals damage already calls take_hit() on whatever it hits, so these need no
## registration anywhere - they just answer it.
const CRATES := {
	"Barrel": {"hits": 1, "color": Color(0.44, 0.31, 0.17)},
	"Box": {"hits": 1, "color": Color(0.56, 0.39, 0.21)},
}
## Ankle-height dressing that stays decoration. Rubble and candles are 0.2m and
## 0.3m tall: a collider down there is something to trip over on a sprint, not
## something anyone would aim at.
const DECOR := ["Debris", "Candle_01", "Candle_02"]

func _place_props() -> void:
	# Scatter a little junk so corridors are not bare tubes. Kept off the route
	# centre line, against a wall, so it never blocks a sprint.
	var crates := CRATES.keys()
	var n := 0
	for i in range(_route.size()):
		if i % 3 != 1:
			continue
		# Crates are solid now, so keep them off the cells the watchers spawn on -
		# a pack materialising inside a barrel gets shoved out of formation.
		if _is_pack_cell(i):
			continue
		# ...and off the ramp cells, where a crate would sit in the one gap the
		# player has to crouch through.
		if _ramp_at.has(i):
			continue
		var c := _coarse_world(_route[i])
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var along := _rng.randf_range(-1.2, 1.2)
		var horizontal := _rng.randf() < 0.5
		var off := Vector3(side * 1.35, 0, along) if horizontal \
			else Vector3(along, 0, side * 1.35)
		var yaw := _rng.randf_range(0, 360)
		if _rng.randf() < 0.72:
			var model: String = crates[_rng.randi() % crates.size()]
			var row: Dictionary = CRATES[model]
			_breakable(model, "Crate_%d" % i, c + off, yaw,
				int(row["hits"]), row["color"])
			n += 1
		else:
			_piece(DECOR[_rng.randi() % DECOR.size()], "Prop_%d" % i, c + off, yaw)
	print("  crates=%d" % n)

## Which route cells get a watcher pack. One predicate, asked by BOTH the enemy
## placer and the crate placer - crates skip these cells, and when the two drifted
## apart crates were being kept off cells that no longer had a pack on them.
##
## **Nothing before the first gate.** The opening stretch is where the player
## finds the dagger and meets the first door, and a pack in it means being jumped
## bare-fisted before either. The gate is the level's first real beat; enemies
## start after it.
func _is_pack_cell(i: int) -> bool:
	if i < 3 or i % PACK_EVERY != 0:
		return false
	return i > _first_gate_i

## Watchers, in packs. Each pack shares a parent, and watcher_enemy.alert()
## wakes its siblings - so a pack is exactly "the watchers under this node".
func _place_enemies() -> void:
	if not ResourceLoader.exists(WATCHER_SCENE):
		push_warning("no watcher.tscn - run tools/build_watcher_scene.gd first")
		return
	var watcher := load(WATCHER_SCENE) as PackedScene
	var packs := Node3D.new()
	packs.name = "Packs"
	_root.add_child(packs)
	packs.owner = _root

	var n := 0
	var first := -1
	for i in range(_route.size()):
		if not _is_pack_cell(i):
			continue
		var pack := Node3D.new()
		pack.name = "Pack_%02d" % n
		packs.add_child(pack)
		pack.owner = _root
		pack.position = _coarse_world(_route[i])

		# Face back along the route, so they are looking at you as you arrive.
		var back: Vector2i = _route[i - 1] - _route[i]
		var yaw := atan2(float(back.x), float(back.y))
		var count := 1 if _rng.randf() < 0.45 else 2
		for w in range(count):
			var inst := watcher.instantiate()
			inst.name = "Watcher_%d" % w
			pack.add_child(inst)
			inst.owner = _root
			inst.position = Vector3((float(w) - float(count - 1) * 0.5) * 1.5, 0, 0)
			inst.rotation.y = yaw
		if first < 0:
			first = i
		n += 1
	# The first pack has to sit PAST the first gate - see _is_pack_cell().
	print("  packs=%d  first at route %d (gate at %d)" % [n, first, _first_gate_i])

## Three chests: the dagger right at the start, an empty one partway in, and the
## goal at the far end. The dagger is the level's opening beat - you begin with
## two empty fists and arm yourself on the way. The middle chest carried the
## blood pistol until that was cut; it is kept as something to open (and now, to
## smash) rather than restaked, since the dagger is the only item there is.
const DAGGER_CHEST_AT := 2      # index into _route
## Fraction of the way along the route for the middle chest, clamped clear of
## both the dagger chest and the goal.
const MID_CHEST_FRAC := 0.4

func _place_goal() -> void:
	if not ResourceLoader.exists(CHEST_SCENE) or _route.is_empty():
		return
	var scn := load(CHEST_SCENE) as PackedScene

	var goal := scn.instantiate()
	goal.name = "Goal"
	_root.add_child(goal)
	goal.owner = _root
	# Overrides on the instance ROOT, which pack() keeps - the same trick `loot`
	# uses. Chests are indestructible by default so a stray swing cannot delete
	# the outdoor camps' treasure; this level wants them smashable.
	goal.set("destructible", true)
	goal.position = _coarse_world(_route[-1])
	var back := Vector2i(0, 1)
	if _route.size() > 1:
		back = _route[-2] - _route[-1]
	goal.rotation.y = atan2(float(back.x), float(back.y))

	if _route.size() <= DAGGER_CHEST_AT + 2:
		push_warning("route too short for the loot chests")
		return
	_loot_chest(scn, "DaggerChest", DAGGER_CHEST_AT, "dagger")
	var mid_at := clampi(int(_route.size() * MID_CHEST_FRAC),
		DAGGER_CHEST_AT + 2, _route.size() - 2)
	_loot_chest(scn, "MidChest", mid_at, "")

## A chest tucked against the side of the corridor, so it never blocks a sprint.
func _loot_chest(scn: PackedScene, node_name: String, idx: int, item: String) -> void:
	var chest := scn.instantiate()
	chest.name = node_name
	_root.add_child(chest)
	chest.owner = _root
	var here: Vector2i = _route[idx]
	var dir: Vector2i = here - _route[idx - 1]
	var perp := Vector3(float(dir.y), 0.0, float(-dir.x))
	chest.position = _coarse_world(here) + perp * 1.2
	chest.rotation.y = atan2(float(-dir.x), float(-dir.y))
	# Only the instance ROOT is overridden - pack() drops overrides on nodes
	# inside an instanced scene, but keeps them on the root.
	chest.set("loot", item)
	# Smashing a loot chest spills the same pickup opening it would, so breaking
	# one cannot strand the player bare-fisted. See chest.gd's take_hit().
	chest.set("destructible", true)

## Outdoors the sun models the arms. Sealed in a dungeon there is no key light
## at all and the viewmodel renders as a black silhouette, so it gets its own
## short-range lamp riding the camera. Deliberately tight in range so it lifts
## the hands without flooding the corridor and killing the red.
## The opening cutscene: the creature standing one cell down the corridor, and
## the CanvasLayer that drives it.
##
## The model is placed here; everything else about the scene is cutscene.gd's.
## It carries no collider - the FBX brings none, and it must not be something the
## player can walk into or swing at, since it is gone before either is possible.
func _place_cutscene() -> void:
	if not ResourceLoader.exists(CREATURE):
		push_warning("no creature.fbx - skipping the cutscene")
		return
	var spawn := _coarse_world(_route[0])
	# One cell down the corridor, so it is squarely in view from the spawn
	# without the player having to look for it.
	var at := _coarse_world(_route[1]) if _route.size() > 1 \
		else spawn + Vector3(float(_start_dir.x), 0, float(_start_dir.y)) * CELL

	# A plain wrapper carries the scale and the yaw. Scaling the FBX instance's
	# own children would be an override INSIDE an instanced scene, which pack()
	# drops - the wrapper is a node this builder made, so it survives.
	var warden := Node3D.new()
	warden.name = "Warden"
	_level.add_child(warden)
	warden.owner = _root
	warden.position = at
	# Its front is +Z (measured with tools/_probe_creature.gd), and the player
	# looks down the corridor from the spawn - so facing back at them works out
	# to the same yaw the player is given.
	warden.rotation = Vector3(0, atan2(float(-_start_dir.x), float(-_start_dir.y)), 0)

	var model := (load(CREATURE) as PackedScene).instantiate()
	model.name = "Model"
	warden.add_child(model)
	model.owner = _root

	# **The model hangs BELOW its own origin.** Measured, its mesh spans y
	# -7.6..+1.2 in wrapper units, so a wrapper standing on the floor buries all
	# but 0.3 m of it - which is exactly what the first build looked like, a dark
	# sliver behind the dialogue box. So both the scale and the offset come off
	# the measured bounds: the model is re-centred in x/z and its BASE put on the
	# wrapper origin, and the wrapper then stands on the floor like anything else.
	var acc := [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
	_accumulate(model, Transform3D.IDENTITY, acc)
	var raw := AABB(acc[0], acc[1] - acc[0])
	var k := CREATURE_HEIGHT / maxf(raw.size.y, 0.001)
	warden.scale = Vector3(k, k, k)
	(model as Node3D).position = Vector3(
		-(raw.position.x + raw.size.x * 0.5), -raw.position.y,
		-(raw.position.z + raw.size.z * 0.5))
	print("  warden raw %.2v -> %.2f m tall (x%.4f)" % [raw.size, CREATURE_HEIGHT, k])

	# Its own lamp, for the same reason pickups carry one: the corridor between
	# route lamps is genuinely black, and an unlit speaker is a silhouette
	# talking. cutscene.gd ramps this from zero as it rises.
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	warden.add_child(lamp)
	lamp.owner = _root
	# In front of it and level with its chest, so it is lit from the player's side
	# rather than rimmed by the corridor lamp behind it - unlit it reads as a
	# silhouette. Positions and range are divided by the wrapper's scale, which
	# they are expressed in.
	lamp.position = Vector3(0, 1.9 / k, 1.3 / k)
	lamp.light_color = Color(0.80, 0.95, 0.78)
	lamp.light_energy = 0.0
	# Short: at 7 m it washed the whole corridor green and the walls went with it.
	lamp.omni_range = 4.2 / k
	lamp.shadow_enabled = false

	var cs := CanvasLayer.new()
	cs.name = "Cutscene"
	cs.set_script(load(CUTSCENE))
	_root.add_child(cs)
	cs.owner = _root
	cs.set("creature_path", cs.get_path_to(warden))

func _light_viewmodel() -> void:
	var cam := _root.get_node_or_null("Player/Head/Camera3D") as Camera3D
	if cam == null:
		push_warning("no Camera3D to light the viewmodel")
		return
	var l := OmniLight3D.new()
	l.name = "ViewModelLight"
	cam.add_child(l)
	l.owner = _root
	l.position = Vector3(0, -0.15, -0.35)
	l.light_color = Color(1.0, 0.86, 0.78)
	# The hand sits ~0.3m from this, i.e. effectively zero falloff, so the
	# energy that looks sane for a room lamp blows the viewmodel to pure white
	# and then the glow pass blooms it. It has to be very low.
	# 0.5 still blew the dagger blade (bright steel, roughness 0.6) to a solid
	# white bar once glow got hold of it. The blade is the brightest thing the
	# viewmodel ever holds, so it sets the ceiling.
	l.light_energy = 0.28
	l.omni_range = 1.8
	l.omni_attenuation = 2.2
	l.shadow_enabled = false

func _place_player() -> void:
	var p := _root.get_node_or_null("Player") as Node3D
	if p == null:
		push_warning("no Player node")
		return
	p.add_to_group("player", true)
	p.position = _coarse_world(_route[0]) + Vector3(0, 1.2, 0)
	# Look down the first corridor.
	p.rotation = Vector3(0, atan2(float(-_start_dir.x), float(-_start_dir.y)), 0)
	if p.get_script() == null:
		p.set_script(load("res://scripts/player.gd"))
		print("  re-attached player.gd")
