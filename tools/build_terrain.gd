extends SceneTree

## Replaces whatever level is in res://scenes/main.tscn with a wide white
## whitebox terrain and a field of obstacles.
##
## Re-runnable - it strips the dungeon, its enemies and any previous terrain
## first, so tune the constants and run it again:
##
##   Godot --headless --path . -s tools/build_terrain.gd
##
## The player, the arms viewmodel and the dagger mount are left untouched.

const GROUND := 120.0           # metres across
const GROUND_THICK := 1.0
const SEED := 20260729          # fixed, so the layout is reproducible

## Steps must stay under the player's jump reach (velocity^2 / 2g). With the
## current 13.0 velocity and 26.0 rise gravity that is ~3.25m, so 0.55 is far
## inside it - it was sized against a much lower jump and left deliberately
## gentle. Raise it if you want the staircase to demand more of the player.
const STEP_RISE := 0.55

var _root: Node
var _terrain: Node3D
var _obstacles: Node3D
var _mats: Dictionary = {}
var _n: int = 0
## XZ footprints the random scatter must stay out of.
var _keepout: Array[Rect2] = []

func _init() -> void:
	_root = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_strip()

	_terrain = Node3D.new()
	_terrain.name = "Terrain"
	_root.add_child(_terrain)
	_terrain.owner = _root

	_build_ground()
	_obstacles = Node3D.new()
	_obstacles.name = "Obstacles"
	_terrain.add_child(_obstacles)
	_obstacles.owner = _root

	_build_stairs()
	_build_ramps()
	_build_wallrun_course()
	_build_pillars()
	# Before the scatter, so camps can register their own keep-out footprints.
	_place_camps()
	_build_scatter()
	_build_sky_and_sun()
	_place_spawner()
	_place_hud()
	_place_player()

	var out := PackedScene.new()
	var err := out.pack(_root)
	if err != OK:
		print("pack failed: ", err); quit(1); return
	err = ResourceSaver.save(out, "res://scenes/main.tscn")
	print("saved main.tscn err=%d  obstacles=%d" % [err, _obstacles.get_child_count()])
	quit()

func _strip() -> void:
	for n in ["Dungeon", "Skeleton", "ChonChons", "Terrain", "Camps", "HUD",
			"Floor", "Crate", "Pillar", "Platform", "Sun", "Bat", "BatSpawner"]:
		var node := _root.get_node_or_null(n)
		if node:
			_root.remove_child(node)
			node.queue_free()

## Screaming Brain Studios "Horror Texture Pack" (CC0), in assets/textures/.
##
## Under the sunset panorama the whole scene wants to collapse into one orange
## mass, so the two materials are picked to fight that: Stone_01 is the darkest
## clean-tiling texture in the pack and gets a cool tint, Wall_03 stays pale.
## That keeps a hard value split between floor and props no matter how warm the
## key light gets, which is what makes the boxes readable as cover.
## Both are non-directional, so heavy tiling dissolves into noise, not a grid.
const TEX_GROUND := "res://assets/textures/Stone/Horror_Stone_01-512x512.png"
const TEX_OBSTACLE := "res://assets/textures/Wall/Horror_Wall_03-512x512.png"

## Metres of world space one texture tile covers.
const GROUND_TILE := 4.0
const OBSTACLE_TILE := 2.5

func _tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("missing texture %s - falling back to flat colour" % path)
		return null
	return load(path) as Texture2D

## Whites need slightly different values or the shapes read as one flat blob.
## The albedo colours survive texturing as a tint, so that separation holds.
func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	# Tints lean blue on purpose. The key light is heavily orange, so a neutral
	# albedo comes back orange; biasing the other way lands them near neutral and
	# keeps the cool shadow / warm light split that sells the dusk.
	match key:
		"ground": m.albedo_color = Color(0.78, 0.84, 1.00)
		"light": m.albedo_color = Color(0.95, 0.96, 1.00)
		"mid": m.albedo_color = Color(0.76, 0.79, 0.88)
		"dark": m.albedo_color = Color(0.58, 0.62, 0.74)
		_: m.albedo_color = Color.WHITE
	m.roughness = 0.95
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	if key == "ground":
		var t := _tex(TEX_GROUND)
		if t:
			m.albedo_texture = t
			# BoxMesh maps UV 0..1 across each face regardless of the box size,
			# so without a scale one tile stretches over the whole 120m plane.
			# The side faces sit below y=0 and are never seen, so plain UVs are
			# enough here - no need for the triplanar cost.
			m.uv1_scale = Vector3(GROUND / GROUND_TILE, GROUND / GROUND_TILE, 1.0)
	else:
		var t := _tex(TEX_OBSTACLE)
		if t:
			m.albedo_texture = t
			# Obstacles range from 0.8m crates to 32m walls and all share these
			# three materials, so per-face UVs would give wildly different texel
			# density. Triplanar projects from position instead, which keeps the
			# tile size constant across every box for one shared material.
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE / OBSTACLE_TILE

	if m.albedo_texture:
		# The ground is seen at grazing angles all the way to the horizon.
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	_mats[key] = m
	return m

## One box obstacle: mesh plus a matching collider.
func _box(pos: Vector3, size: Vector3, mat: String = "light",
		rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Obs_%02d" % _n
	_n += 1
	var host := parent if parent else _obstacles
	host.add_child(body)
	body.owner = _root
	body.position = pos
	body.rotation_degrees = rot

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	body.add_child(mi)
	mi.owner = _root
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.set_surface_override_material(0, _mat(mat))

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = _root
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	return body

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	_terrain.add_child(body)
	body.owner = _root
	body.position = Vector3(0, -GROUND_THICK / 2.0, 0)

	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	body.add_child(mi)
	mi.owner = _root
	var bm := BoxMesh.new()
	bm.size = Vector3(GROUND, GROUND_THICK, GROUND)
	mi.mesh = bm
	mi.set_surface_override_material(0, _mat("ground"))

	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	body.add_child(cs)
	cs.owner = _root
	var sh := BoxShape3D.new()
	sh.size = Vector3(GROUND, GROUND_THICK, GROUND)
	cs.shape = sh

## A climbable staircase of platforms, each within one jump of the last.
func _build_stairs() -> void:
	for i in range(6):
		var h := STEP_RISE * (i + 1)
		_box(Vector3(-9.0 - i * 3.2, h / 2.0, -14.0), Vector3(3.0, h, 3.0),
			"light" if i % 2 == 0 else "mid")

func _build_ramps() -> void:
	# Walkable slopes: CharacterBody3D allows up to 45 degrees by default.
	_box(Vector3(10.0, 0.9, -12.0), Vector3(4.0, 0.6, 9.0), "mid", Vector3(-22, 0, 0))
	_box(Vector3(16.5, 1.4, -18.0), Vector3(9.0, 0.6, 4.0), "light", Vector3(0, 0, 18))
	# A platform the ramps lead onto.
	_box(Vector3(13.0, 1.6, -20.0), Vector3(7.0, 3.2, 5.0), "dark")

## Long, tall, flat faces to wall run along. The scattered boxes are far too
## short and stubby to get a run going on.
func _build_wallrun_course() -> void:
	var walls := [
		# East: three parallel slabs, giving two lanes to zig-zag down instead of
		# one. 6m gaps, both crossable in a single kick-off.
		[Vector3(21.0, 4.0, -13.0), Vector3(1.0, 8.0, 28.0), "mid"],
		[Vector3(28.0, 4.0, -13.0), Vector3(1.0, 8.0, 28.0), "light"],
		[Vector3(35.0, 4.0, -13.0), Vector3(1.0, 8.0, 28.0), "mid"],
		# Behind spawn: the straight run, now three deep so you can cross from
		# one to the next instead of dropping out after a single wall.
		[Vector3(-8.0, 3.5, 20.0), Vector3(32.0, 7.0, 1.0), "mid"],
		[Vector3(-8.0, 3.0, 28.0), Vector3(32.0, 6.0, 1.0), "light"],
		[Vector3(-8.0, 3.5, 36.0), Vector3(32.0, 7.0, 1.0), "dark"],
	]
	# West: a staggered gauntlet. The walls alternate sides with a gap between
	# each, so a run cannot be held on one face - it has to be chained: run,
	# kick off, catch the next. Placed out at x=-38/-44 to clear the pillar at
	# x=-34 and the spawn walls, which reach x=-24.
	for i in range(4):
		walls.append([
			Vector3(-38.0 if i % 2 == 0 else -44.0, 3.0, -4.0 + i * 10.0),
			Vector3(1.0, 6.0, 8.0),
			"light" if i % 2 == 0 else "mid",
		])
	for w in walls:
		var pos: Vector3 = w[0]
		var size: Vector3 = w[1]
		_box(pos, size, w[2])
		# Keep the scatter from cluttering the run lanes.
		_keepout.append(Rect2(
			Vector2(pos.x - size.x * 0.5 - 3.0, pos.z - size.z * 0.5 - 3.0),
			Vector2(size.x + 6.0, size.z + 6.0)))

func _build_pillars() -> void:
	# Tall landmarks so the space has a sense of scale and direction.
	var spots := [
		Vector3(-26, 0, -30), Vector3(24, 0, -34), Vector3(-34, 0, 6),
		Vector3(32, 0, 10), Vector3(0, 0, -42),
	]
	for i in range(spots.size()):
		var h := 7.0 + float(i % 3) * 3.0
		var p: Vector3 = spots[i]
		p.y = h / 2.0
		_box(p, Vector3(2.4, h, 2.4), "dark" if i % 2 == 0 else "mid")

func _build_scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var kinds := ["light", "mid", "dark"]
	var placed := 0
	var tries := 0
	while placed < 34 and tries < 400:
		tries += 1
		var p := Vector3(rng.randf_range(-48, 48), 0, rng.randf_range(-48, 48))
		# Keep the spawn area clear so the player is not boxed in.
		if p.length() < 7.0:
			continue
		var blocked := false
		for r: Rect2 in _keepout:
			if r.has_point(Vector2(p.x, p.z)):
				blocked = true
				break
		if blocked:
			continue
		var s := rng.randf_range(0.8, 3.4)
		var sz := Vector3(s, s * rng.randf_range(0.6, 1.8), s)
		p.y = sz.y / 2.0
		_box(p, sz, kinds[rng.randi() % kinds.size()], Vector3(0, rng.randf_range(0, 90), 0))
		placed += 1

## Halloween dusk. The sky is a 360x180 equirectangular panorama, so the sun is
## already painted into it - the DirectionalLight only exists to cast shadows
## that agree with it. Its direction was measured, not guessed: the warm core of
## the glow sits at world yaw 244 degrees, so the light points back the other
## way at yaw 64. Change SKY_PANORAMA and these two numbers go stale.
const SKY_PANORAMA := "res://assets/sky/pumpkin_mountain_2160.png"
const SUN_YAW := 64.0
## The painted sun sits ~14 degrees up, but a sun that low throws 45m shadows
## from the taller pillars and swallows half the arena. Lifted to 26 for
## playability - it reads as the same late dusk and nobody measures it.
const SUN_PITCH := -26.0

func _build_sky_and_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	_root.add_child(sun)
	sun.owner = _root
	sun.rotation_degrees = Vector3(SUN_PITCH, SUN_YAW, 0)
	sun.light_color = Color(1.0, 0.76, 0.52)
	sun.light_energy = 2.1             # warm key, strong enough to model the boxes
	sun.shadow_enabled = true          # shadows are what make the shapes read
	sun.light_angular_distance = 1.2   # slightly soft edges, less whitebox-crisp
	sun.directional_shadow_max_distance = 110.0

	var env := _root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env == null or env.environment == null:
		push_warning("no WorldEnvironment to configure")
		return
	var e := env.environment
	e.background_mode = Environment.BG_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.95

	var pano := _tex(SKY_PANORAMA)
	var sky := Sky.new()
	if pano:
		var psm := PanoramaSkyMaterial.new()
		psm.panorama = pano
		psm.energy_multiplier = 1.0
		sky.sky_material = psm
	else:
		# The panorama is NOT redistributable and is kept out of the repository,
		# so a fresh clone does not have it - see the README. Fall back to a
		# procedural dusk in roughly its colours rather than to BG_SKY with no
		# sky at all, which renders the horizon as flat grey and makes a clone
		# look broken rather than incomplete.
		push_warning("no sky panorama at %s - using the procedural fallback"
			% SKY_PANORAMA)
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.18, 0.16, 0.30)
		proc.sky_horizon_color = Color(0.85, 0.45, 0.20)
		proc.ground_bottom_color = Color(0.08, 0.07, 0.10)
		proc.ground_horizon_color = Color(0.45, 0.28, 0.20)
		proc.sun_angle_max = 12.0
		sky.sky_material = proc
	e.sky = sky

	# The panorama's bottom third is solid black - the author never painted a
	# nadir. Sky ambient alone therefore lights every down-facing surface with
	# nothing at all, so ramp undersides and box bottoms render as holes. Blend
	# the sky against an explicit dusk fill instead of trusting it outright.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.45
	e.ambient_light_color = Color(0.24, 0.30, 0.50)   # cool, to oppose the warm key
	# Generous on purpose. Stone_01 is very dark, and in the wall-run corridor the
	# floor sits in full shadow - too little fill and it crushes to black, which
	# hides both the geometry and any bat standing on it.
	e.ambient_light_energy = 2.1

	# The ground is 120m across but the sky behind it is a black void below the
	# horizon, so the plane used to end at a hard edge against nothing. Depth fog
	# tinted to the horizon hides the edge and gives the arena some air.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	# Deliberately NOT the ground's colour - a brown fog over brown ground is
	# invisible and does nothing for the edge. Dusk purple reads as distance.
	e.fog_light_color = Color(0.32, 0.27, 0.38)
	e.fog_light_energy = 1.0
	# Starts past the far side of the arena. Fog that reaches into the play space
	# greys out approaching bats, which is worse than a visible ground edge.
	e.fog_depth_begin = 48.0
	e.fog_depth_end = 145.0
	e.fog_density = 0.7
	e.fog_sky_affect = 0.0             # never fog the sky - the pumpkins are the view
	e.fog_aerial_perspective = 0.0

	# Makes the pumpkin faces, the orange bolts and the sun-facing box edges
	# carry some bloom instead of clipping flat.
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.05
	e.glow_hdr_threshold = 1.1

## Hand-placed watcher camps: a trio standing guard around a chest.
##
## These are NOT spawned - fixed positions are the whole point, so the player
## learns where they are. Each camp is one Camp_NN node holding the chest plus
## three watchers, and that parent IS the squad: watcher_enemy.alert() wakes its
## siblings, so grouping them under a node is all the wiring there is.
const WATCHER_SCENE := "res://scenes/watcher.tscn"
const CAMPS := [
	Vector3(-18, 0, -38),   # north-west flats, past the staircase
	Vector3(16, 0, 30),     # south-east, clear of the spawn walls (they end at x=8)
	Vector3(44, 0, -30),    # east, outside the three-slab corridor
	Vector3(-44, 0, -22),   # west, below the wall-run gauntlet
]
## Watchers stand this far out from the chest, evenly spaced, facing outward.
const CAMP_RADIUS := 2.6
const CHEST_SCENE := "res://scenes/chest.tscn"

## Which camp guards which weapon, by camp index. The player starts with two
## empty fists, so this chest IS the loadout - opening it floats the item out
## (see pickup.gd) and a second E takes it. The remaining camps guard empty
## chests. Item ids come from pickup.gd's ITEMS table, which since the blood
## pistol was cut holds exactly one.
const CAMP_LOOT := {
	0: "dagger",
}

func _place_camps() -> void:
	if not ResourceLoader.exists(WATCHER_SCENE):
		push_warning("no watcher.tscn - run tools/build_watcher_scene.gd first")
		return
	var watcher := load(WATCHER_SCENE) as PackedScene
	var chest_scene: PackedScene = null
	if ResourceLoader.exists(CHEST_SCENE):
		chest_scene = load(CHEST_SCENE) as PackedScene
	else:
		push_warning("no chest.tscn - run tools/build_chest_scene.gd first")
	var camps := Node3D.new()
	camps.name = "Camps"
	_root.add_child(camps)
	camps.owner = _root

	for i in range(CAMPS.size()):
		var at: Vector3 = CAMPS[i]
		var camp := Node3D.new()
		camp.name = "Camp_%02d" % i
		camps.add_child(camp)
		camp.owner = _root
		camp.position = at

		# The treasure. Its own StaticBody, so it also blocks movement.
		if chest_scene:
			var chest := chest_scene.instantiate()
			chest.name = "Chest"
			camp.add_child(chest)
			chest.owner = _root
			# Same per-camp offset as the watcher ring, so the chest faces into
			# the trio rather than every camp being laid out identically.
			chest.rotation.y = float(i) * 0.7 + PI
			# Only the instance ROOT is overridden - pack() drops overrides on
			# nodes inside an instanced scene, but keeps them on the root.
			chest.set("loot", String(CAMP_LOOT.get(i, "")))

		for w in range(3):
			var ang := TAU * float(w) / 3.0 + float(i) * 0.7
			var inst := watcher.instantiate()
			inst.name = "Watcher_%d" % w
			camp.add_child(inst)
			inst.owner = _root
			# Only the transform is overridden on the instance root. Anything set
			# on nodes *inside* an instanced scene is dropped by pack().
			inst.position = Vector3(sin(ang), 0.0, cos(ang)) * CAMP_RADIUS
			inst.rotation.y = ang          # +Z is forward, so this faces outward

		# Keep the random scatter from burying the camp in crates.
		var r := CAMP_RADIUS + 3.5
		_keepout.append(Rect2(Vector2(at.x - r, at.z - r), Vector2(r * 2.0, r * 2.0)))

## Vampire-Survivors style horde spawner. Bats stream in on a ring around the
## player; scenes/bat.tscn is generated by tools/build_bat_scene.gd.
const BAT_SCENE := "res://scenes/bat.tscn"
const SPAWNER_SCRIPT := "res://scripts/bat_spawner.gd"

func _place_spawner() -> void:
	if not ResourceLoader.exists(BAT_SCENE):
		push_warning("no bat.tscn - run tools/build_bat_scene.gd first")
		return
	var spawner := Node3D.new()
	spawner.name = "BatSpawner"
	spawner.set_script(load(SPAWNER_SCRIPT))
	_root.add_child(spawner)
	spawner.owner = _root
	spawner.set("bat_scene", load(BAT_SCENE))

## Crosshair + interaction prompt. A CanvasLayer so it always draws over the 3D
## view regardless of what else ends up in the scene.
const HUD_SCRIPT := "res://scripts/hud.gd"

func _place_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	_root.add_child(layer)
	layer.owner = _root
	var cross := Control.new()
	cross.name = "Crosshair"
	cross.set_script(load(HUD_SCRIPT))
	layer.add_child(cross)
	cross.owner = _root
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE

const PLAYER_SCRIPT := "res://scripts/player.gd"

func _place_player() -> void:
	var p := _root.get_node_or_null("Player") as Node3D
	if p == null:
		push_warning("no Player node to place")
		return
	p.add_to_group("player", true)
	p.position = Vector3(0, 1.2, 8.0)
	p.rotation_degrees = Vector3.ZERO
	# If a script fails to parse when pack() runs, the reference is dropped
	# silently and the player ends up inert with no error at load. Re-attach
	# on every build so a transient syntax error cannot strand the scene.
	if p.get_script() == null:
		p.set_script(load(PLAYER_SCRIPT))
		print("  re-attached ", PLAYER_SCRIPT, " to Player")
