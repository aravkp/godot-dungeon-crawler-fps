@tool
extends Node3D

## Re-binds the dungeon kit's atlas textures.
##
## Godot's FBX import drops the texture links, leaving every piece with a bare
## material named after the atlas it wants: "N64" for architecture,
## "CratesAndBarrels" for props, "DoorsMap" for doors. This walks the kit and
## points each surface at the matching PNG.
##
## The materials go onto the shared imported mesh resources rather than onto
## each node, so 43 unique meshes get touched instead of 137 instances and
## nothing needs baking into main.tscn. @tool so the editor shows it too.

## These five names cover the whole kit.
const ATLASES := {
	"N64": "res://assets/dungeon/Dungeon_Map.png",              # 35 pieces
	"CratesAndBarrels": "res://assets/dungeon/CratesAndBarrels_Map.png",
	"DoorsMap": "res://assets/dungeon/Doors_Map.png",
	"Chain": "res://assets/dungeon/TEX_Chain_02.png",           # chandelier, chain
	"Material": "res://assets/dungeon/Dungeon_Map.png",         # Arch_Roof only
}

var _mats: Dictionary = {}

func _ready() -> void:
	_bind(self)

func _bind(n: Node) -> void:
	if n is MeshInstance3D:
		var mesh := (n as MeshInstance3D).mesh
		# Each mesh is shared by every instance of that piece, so bind once.
		if mesh is ArrayMesh and not mesh.has_meta(&"atlas_bound"):
			mesh.set_meta(&"atlas_bound", true)
			for s in range(mesh.get_surface_count()):
				var src := mesh.surface_get_material(s)
				var mat_name: String = src.resource_name if src else ""
				(mesh as ArrayMesh).surface_set_material(s, _material_for(mat_name))
	for c in n.get_children():
		_bind(c)

func _material_for(mat_name: String) -> StandardMaterial3D:
	if _mats.has(mat_name):
		return _mats[mat_name]
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	if ATLASES.has(mat_name):
		m.albedo_texture = load(ATLASES[mat_name])
	else:
		push_warning("dungeon: no atlas for material '%s'" % mat_name)
	# PSX kit: crunchy texels, no shine.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mats[mat_name] = m
	return m
