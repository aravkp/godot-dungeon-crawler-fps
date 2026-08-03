extends StaticBody3D

## A floating item the player takes with E. Chests spawn these when opened, so
## the loadout is earned rather than granted invisibly: the player starts with
## two empty fists and every weapon arrives as one of these.
##
## Built in code (see spawn()) rather than as a .tscn, matching the rest of the
## project - there is no scene file to keep in sync with the item table.
##
## It is a StaticBody3D because that is what player.gd's interaction ray can
## see, and it satisfies the same contract as the chest:
##   prompt() -> String      the [E] line ("" = offer nothing)
##   interact(by) -> bool    did anything happen
## plus two optional extras the HUD draws above that line:
##   title() -> String       the item's name
##   subtitle() -> String    one line on what it does
##
## The one visual kind is "mesh": it pulls the real weapon model out of its FBX,
## so the dagger pickup is literally the dagger you end up holding. There was a
## second kind, "icon" - a NEAREST-filtered billboard - for the blood pistol, an
## ability with no model of its own. The pistol is gone and that path went with
## it; an item with nothing to show would have to bring it back.

signal taken

const DAGGER_FBX := "res://assets/dagger/dagger.fbx"
const VARIANTS := preload("res://scripts/dagger_variants.gd")

## The dagger's own textures were never shipped with the FBX, so its parts fall
## back to flat colours - the same ones tools/mount_dagger.gd uses, so the
## pickup and the held weapon match.
const DAGGER_COLORS := {
	"blade": Color(0.72, 0.75, 0.80),
	"guard": Color(0.42, 0.38, 0.30),
	"pommel": Color(0.42, 0.38, 0.30),
	"grip": Color(0.30, 0.19, 0.12),
}

## The item table. `grants` is the method called on the viewmodel, which is why
## adding an item needs no changes here beyond a row.
const ITEMS := {
	"dagger": {
		"title": "Lvl 1 Dagger",
		"subtitle": "Melee - hold to swing",
		"kind": "mesh",
		"grants": "unlock_dagger",
		"glow": Color(0.75, 0.80, 0.95),
	},
}

@export var item: String = "dagger"
## Which of dagger_variants.gd's 24 blades this one looks like. "" is the
## original dagger.fbx. **A skin only** - the id, the card and what it grants are
## identical either way, which is the whole point of keeping one item.
@export var variant: String = ""
@export var take_label: String = "Take"
## Bob and spin, so a dropped item reads as loot rather than as scenery.
@export var bob_height: float = 0.10
@export var bob_speed: float = 2.2
@export var spin_speed: float = 1.1
## Pickups have to be legible in the sealed corridor level, which has no key
## light at all - hence a small lamp of their own. Kept deliberately weak and
## short: at 1.6/2.6 the pistol's red lamp repainted an entire corridor, which
## reads as a room light rather than as a glinting item.
@export var glow_energy: float = 0.9
@export var glow_range: float = 1.8

var _base_y: float = 0.0
var _t: float = 0.0
var _taken: bool = false

## Builds a pickup for `item` and drops it into the tree at `at`.
## `host` should outlive the chest that spawned it (pass the chest's parent).
static func spawn(host: Node, at: Vector3, item_id: String,
		variant_id: String = "") -> Node3D:
	if host == null or not host.is_inside_tree():
		return null
	if not ITEMS.has(item_id):
		push_warning("pickup: unknown item '%s'" % item_id)
		return null
	var script := load("res://scripts/pickup.gd") as GDScript
	var p: StaticBody3D = script.new()
	p.name = "Pickup_" + item_id
	p.item = item_id
	# Set BEFORE add_child: _ready() builds the art immediately, and a variant
	# assigned afterwards would arrive one step too late to be seen.
	p.variant = variant_id
	host.add_child(p)
	p.global_position = at
	# _ready() already ran (add_child is immediate) and captured the pre-move
	# height, so the bob origin has to be re-seated after positioning.
	p.set("_base_y", at.y)
	return p

func _ready() -> void:
	add_to_group("interactable", true)
	add_to_group("pickups", true)
	_base_y = global_position.y
	_build()

func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	global_position.y = _base_y + sin(_t * bob_speed) * bob_height
	rotate_y(spin_speed * delta)

# --- the interaction contract ----------------------------------------------

func prompt() -> String:
	return "" if _taken else take_label

func title() -> String:
	return "" if _taken else String(_row().get("title", ""))

func subtitle() -> String:
	return "" if _taken else String(_row().get("subtitle", ""))

func interact(_by: Node = null) -> bool:
	if _taken:
		return false
	var method := String(_row().get("grants", ""))
	var vm := get_tree().get_first_node_in_group("viewmodel")
	if vm == null or not vm.has_method(method):
		push_warning("pickup: nothing in group 'viewmodel' with %s()" % method)
		return false
	# The variant travels with the grant, so the blade you saw floating is the
	# blade you end up holding. An empty one means the original dagger.
	if variant != "":
		vm.call(method, variant)
	else:
		vm.call(method)
	_taken = true
	taken.emit()
	# Stop being a target the moment it is claimed; the ray runs every physics
	# frame and would otherwise re-focus it during the free.
	collision_layer = 0
	queue_free()
	return true

# --- construction ----------------------------------------------------------

func _row() -> Dictionary:
	return ITEMS.get(item, {}) as Dictionary

func _build() -> void:
	var row := _row()
	if row.is_empty():
		push_warning("pickup: unknown item '%s'" % item)
		return

	var art := Node3D.new()
	art.name = "Art"
	add_child(art)
	# A variant is a skin on the same item, so it only changes what gets built -
	# never the id, the card or what the thing grants.
	if variant != "" and VARIANTS.exists(variant):
		var mi := VARIANTS.build(variant, true)
		if mi:
			# The variant is normalised to pivot on its GRIP, which is right in
			# the hand and wrong here: a floating pickup should spin about its
			# middle. get_aabb() is mesh-local, so the centre has to go through
			# the instance's own transform before it can be cancelled out.
			var centre: Vector3 = mi.transform * mi.get_aabb().get_center()
			mi.position -= centre
			art.add_child(mi)
		else:
			_build_dagger(art)
	else:
		_build_dagger(art)

	# One collider for the whole thing, sized generously - the player is aiming
	# at a small floating object with a crosshair, and a tight box makes it
	# fiddly to look at.
	var shape := SphereShape3D.new()
	shape.radius = 0.22
	var col := CollisionShape3D.new()
	col.name = "Collision"
	col.shape = shape
	add_child(col)

	var lamp := OmniLight3D.new()
	lamp.name = "Glow"
	lamp.light_color = row.get("glow", Color.WHITE)
	lamp.light_energy = glow_energy
	lamp.omni_range = glow_range
	lamp.shadow_enabled = false
	add_child(lamp)

## The real dagger model, re-centred on its own bounds so it spins about its
## middle instead of swinging around the model origin.
func _build_dagger(art: Node3D) -> void:
	if not ResourceLoader.exists(DAGGER_FBX):
		push_warning("pickup: missing " + DAGGER_FBX)
		return
	var src := (load(DAGGER_FBX) as PackedScene).instantiate() as Node3D
	src.transform = Transform3D.IDENTITY

	var parts: Array = []
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for part: String in DAGGER_COLORS:
		var found := _find_mesh(src, part, Transform3D.IDENTITY)
		if found.is_empty():
			continue
		parts.append({"part": part, "mesh": found["mesh"], "xform": found["xform"]})
		var ab: AABB = (found["mesh"] as Mesh).get_aabb()
		for i in range(8):
			var pt: Vector3 = (found["xform"] as Transform3D) * ab.get_endpoint(i)
			lo = lo.min(pt)
			hi = hi.max(pt)
	var centre := (lo + hi) * 0.5 if not parts.is_empty() else Vector3.ZERO

	for p: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.name = String(p["part"])
		mi.mesh = p["mesh"]
		var xf: Transform3D = p["xform"]
		xf.origin -= centre
		mi.transform = xf
		var mat := StandardMaterial3D.new()
		mat.albedo_color = DAGGER_COLORS[p["part"]]
		mat.roughness = 0.6 if p["part"] == "blade" else 1.0
		mat.metallic = 0.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		# Lift it out of shadow so it stays readable wherever it is dropped.
		mat.emission_enabled = true
		mat.emission = DAGGER_COLORS[p["part"]]
		mat.emission_energy_multiplier = 0.35
		for s in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, mat)
		art.add_child(mi)
	src.free()

	# The model is ~0.155 units point to pommel; scale it up to read as loot,
	# and cant it so the blade is not edge-on to the player.
	art.scale = Vector3(2.2, 2.2, 2.2)
	art.rotation_degrees = Vector3(0.0, 0.0, 28.0)

func _find_mesh(n: Node, want: String, t: Transform3D) -> Dictionary:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D and n.name == want and (n as MeshInstance3D).mesh != null:
		return {"mesh": (n as MeshInstance3D).mesh, "xform": lt}
	for c in n.get_children():
		var r := _find_mesh(c, want, lt)
		if not r.is_empty():
			return r
	return {}
