@tool
extends StaticBody3D

## Flying-head enemy (ChonChon). Hovers in place playing a looping idle.
##
## Two kit quirks handled here:
##  - The FBX import drops the texture link, so the atlas is re-bound onto the
##    shared mesh resource (once, no matter how many are in the scene).
##  - FBX animations import with looping off, so the idle would play once and
##    freeze mid-flap.
##
## Animation names carry Blender's export prefix, e.g. "Armature|idle".
## The file also ships "Armature|fly attack", "Armature|hit reaction" and
## "Armature|death", ready for when this gets real behaviour.

const TEXTURE := "res://assets/chonchon/chonchon-texture.png"

@export var idle_animation: StringName = &"Armature|idle"
@export var bob_amplitude: float = 0.09
@export var bob_speed: float = 1.5

var _anim: AnimationPlayer
var _model: Node3D
var _base_y: float
var _phase: float

func _ready() -> void:
	_bind_texture()
	_model = get_node_or_null("Model")
	if _model:
		_base_y = _model.position.y
	# Desync the bob so a group of them doesn't pulse in lockstep.
	_phase = randf() * TAU
	_anim = _find_anim(self)
	if _anim == null:
		push_warning("chonchon: no AnimationPlayer")
		return
	var a := _anim.get_animation(idle_animation)
	if a == null:
		push_warning("chonchon: missing animation '%s'" % idle_animation)
		return
	a.loop_mode = Animation.LOOP_LINEAR
	_anim.play(idle_animation)

func _process(delta: float) -> void:
	# Bob the model, not the body, so the collider stays put.
	if Engine.is_editor_hint() or _model == null:
		return
	_phase += delta * bob_speed
	_model.position.y = _base_y + sin(_phase) * bob_amplitude

func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null

func _bind_texture() -> void:
	for mi: MeshInstance3D in _all_meshes(self):
		var mesh: Mesh = mi.mesh
		if mesh is ArrayMesh and not mesh.has_meta(&"chon_bound"):
			mesh.set_meta(&"chon_bound", true)
			var m := StandardMaterial3D.new()
			m.resource_name = "ChonChon"
			m.albedo_texture = load(TEXTURE)
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.roughness = 1.0
			m.metallic = 0.0
			m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			# Thin wing/ear geometry reads better lit from both sides.
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			for s in range(mesh.get_surface_count()):
				(mesh as ArrayMesh).surface_set_material(s, m)

func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
