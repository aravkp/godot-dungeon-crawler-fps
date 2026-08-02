extends StaticBody3D

## The treasure chest the watchers guard. Press E in range to open it.
##
## Chests are where the loadout comes from: the player starts bare-fisted and the
## dagger floats out of a chest as a pickup.gd item. Set `loot` to decide what,
## or leave it "" for a chest that is only something to open.
##
## The FBX ships its own lid animation ("Take 001", 3.33s, a single track on the
## chest_top node), so opening is just playing it - no hand-animated hinge.
##
## Like every other FBX in this project the texture links were dropped on
## import, so the PBR set is re-bound here at load onto the *shared* mesh
## resources, guarded by a meta flag. That costs one bind no matter how many
## chests are in the level.

signal opened
signal broken

const TEX_DIR := "res://assets/chest/Textures/"
const OPEN_ANIM := "Take 001"

## Interaction contract, shared with anything else the player can look at:
##   prompt() -> String   what the HUD should say ("" = offer nothing)
##   interact(by) -> bool did anything happen
## Chests offer no title()/subtitle(); the pickup that floats out of them does.

@export var open_label: String = "Open"
## An item id from pickup.gd's ITEMS ("dagger" is currently the only one), or ""
## for an empty chest. Opening a loaded chest floats the pickup out of it; the player
## then takes it with a second E. The chest itself grants nothing - it does not
## need to know what the item does.
@export var loot: String = ""
## Where the pickup hovers, relative to the chest. The chest measures 0.947 m
## tall, and the lid swings up and back over that - so anything at chest-top
## height is hidden behind the open lid. This clears both.
@export var loot_offset: Vector3 = Vector3(0.0, 1.35, 0.0)

@export_group("Destruction")
## Whether the chest can be smashed open instead of opened. Off by default - the
## outdoor camps' chests are treasure the watchers guard, and a stray swing
## should not delete one. build_corridors.gd turns it on for that level, as an
## override on the instance ROOT, which is the kind pack() keeps.
@export var destructible: bool = false
## Hits REMAINING, decremented in place - see breakable.gd for why it is not
## copied into a private field. One, like everything else breakable: a chest is
## still the slower route by choice, since opening it plays a 3.33 s lid
## animation that smashing skips entirely.
@export var hits: int = 1
@export var debris_color: Color = Color(0.58, 0.42, 0.22)

const PICKUP := preload("res://scripts/pickup.gd")
const DEBRIS := preload("res://scripts/debris.gd")
const SHATTER := preload("res://scripts/shatter.gd")

var _anim: AnimationPlayer
var _open: bool = false
var _spilled: bool = false
var _dead: bool = false

func _ready() -> void:
	add_to_group("interactable", true)
	_bind_material()
	for n in find_children("*", "AnimationPlayer", true, false):
		_anim = n
		break
	if _anim and _anim.has_animation(OPEN_ANIM):
		var a := _anim.get_animation(OPEN_ANIM)
		a.loop_mode = Animation.LOOP_NONE
		# Hold shut on frame 0. Without this the lid sits in whatever pose the
		# importer left it in.
		_anim.play(OPEN_ANIM)
		_anim.seek(0.0, true)
		_anim.pause()

func is_open() -> bool:
	return _open

func prompt() -> String:
	if _open or _dead:
		return ""
	return open_label

func interact(_by: Node = null) -> bool:
	if _open or _dead:
		return false
	_open = true
	if _anim and _anim.has_animation(OPEN_ANIM):
		_anim.play(OPEN_ANIM)
	_spill()
	opened.emit()
	return true

## Smashing a chest is the other way in, and it has to yield the same loot: the
## dagger is chest loot in both levels, so a chest that could be destroyed with
## its contents still inside would let one stray swing strand the player
## bare-fisted for the rest of the run.
##
## Same signature as the enemies' and breakable.gd's, so nothing that deals
## damage needs a special case for chests.
func take_hit(amount: int = 1, at: Vector3 = Vector3.INF,
		from: Vector3 = Vector3.ZERO) -> bool:
	if _dead or not destructible:
		return false
	var point := at if at != Vector3.INF else global_position + Vector3(0, 0.45, 0)
	hits -= amount
	if hits > 0:
		DEBRIS.burst(get_parent(), point, 16, 4.5, debris_color, 0.5)
		return true
	_dead = true
	DEBRIS.burst(get_parent(), point, 22, 5.0, debris_color, 0.9)
	_break_apart(from)
	_spill()
	broken.emit()
	# Stop answering the interaction and melee rays, both of which run before the
	# free lands.
	collision_layer = 0
	queue_free()
	return true

## Falls into chunks like a crate does. The chest's collider is measured from the
## model at build time by build_chest_scene.gd rather than named, so the box is
## found by type; the lid mesh supplies the texture, being the face you were
## looking at.
func _break_apart(from: Vector3) -> void:
	var cs: CollisionShape3D = null
	for n in find_children("*", "CollisionShape3D", true, false):
		if n is CollisionShape3D and (n as CollisionShape3D).shape is BoxShape3D:
			cs = n as CollisionShape3D
			break
	if cs == null:
		return
	var box := (cs.shape as BoxShape3D).size
	var centre := cs.global_position
	var art: MeshInstance3D = null
	for n in find_children("*", "MeshInstance3D", true, false):
		art = n as MeshInstance3D
		if n.name == "chest_top":
			break
	SHATTER.burst(get_parent(), Transform3D(global_transform.basis, centre),
		box, art, from)

## The loot leaves the chest exactly once, whichever way the chest was got into.
func _spill() -> void:
	if _spilled or loot == "":
		return
	_spilled = true
	# Parented to the chest's parent, not the chest, so the floating item is
	# neither dragged around by the lid animation nor freed with the wreckage.
	PICKUP.spawn(get_parent(), global_position + loot_offset, loot)

func _bind_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.resource_name = "TreasureChest"
	mat.albedo_texture = _tex("BaseColor")
	var nrm := _tex("Normal")
	if nrm:
		mat.normal_enabled = true
		mat.normal_texture = nrm
	var rough := _tex("Roughness")
	if rough:
		mat.roughness_texture = rough
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.roughness = 1.0
	var metal := _tex("Metallic")
	if metal:
		mat.metallic_texture = metal
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		mat.metallic = 1.0

	for n in find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (n as MeshInstance3D).mesh
		if mesh is ArrayMesh and not mesh.has_meta(&"chest_bound"):
			mesh.set_meta(&"chest_bound", true)
			for s in range(mesh.get_surface_count()):
				(mesh as ArrayMesh).surface_set_material(s, mat)

func _tex(kind: String) -> Texture2D:
	var p := "%schest_01_1001_%s.png" % [TEX_DIR, kind]
	if not ResourceLoader.exists(p):
		push_warning("chest texture missing: " + p)
		return null
	return load(p) as Texture2D
