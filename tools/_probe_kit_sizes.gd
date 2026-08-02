extends SceneTree

## Prints the world-space bounds of dungeon-kit pieces at the corridor builder's
## scale (S = 0.1), so props and doors can be sized and anchored from measurement
## instead of guesswork.
##
##   Godot --headless --path . -s tools/_probe_kit_sizes.gd
##
## FBX pieces in this kit are NOT authored at their origins (see DESIGN.md), so
## the offset column matters as much as the size one.

const KIT := "res://assets/dungeon/%s.fbx"
const S := 0.1

const PIECES := [
	"Barrel", "Box", "Debris", "Chest", "Candle_01", "Candle_02",
	"Door_01", "Door_02", "Door_03", "Door_Frame_01", "Door_Frame_02",
	"Wall_01", "Floor_Tiles", "Arch",
]

## Pieces whose front silhouette gets printed as an occupancy map, so a doorway's
## opening is measured rather than assumed. Geometry is projected along Z: a cell
## with no triangle over it is a hole all the way through.
const SILHOUETTES := ["Door_Frame_01", "Door_Frame_02", "Wall_01"]
const GRID := 32

func _init() -> void:
	print("piece            size (m)                 centre (m)              min.y")
	for p: String in PIECES:
		var path := KIT % p
		if not ResourceLoader.exists(path):
			print("%-16s MISSING" % p)
			continue
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		inst.transform = Transform3D.IDENTITY
		var acc := [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
		_accumulate(inst, Transform3D.IDENTITY, acc)
		var lo: Vector3 = acc[0] * S
		var hi: Vector3 = acc[1] * S
		var mats: Array[String] = []
		_materials(inst, mats)
		inst.free()
		print("%-16s %-24s %-23s %.3f   mats=%s"
			% [p, str((hi - lo).snappedf(0.001)), str(((hi + lo) * 0.5).snappedf(0.001)),
				lo.y, str(mats)])
	for p: String in SILHOUETTES:
		_silhouette(p)
	quit()

## Projects every triangle along Z and prints which of a GRID x GRID lattice of
## sample points is covered. '#' is solid, '.' is a hole through the piece.
func _silhouette(model: String) -> void:
	var path := KIT % model
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	inst.transform = Transform3D.IDENTITY
	var tris := PackedVector3Array()
	_faces(inst, Transform3D.IDENTITY, tris)
	var acc := [Vector3(1e9, 1e9, 1e9), Vector3(-1e9, -1e9, -1e9)]
	_accumulate(inst, Transform3D.IDENTITY, acc)
	inst.free()
	var lo: Vector3 = acc[0]
	var hi: Vector3 = acc[1]
	print("\n%s  x %.2f..%.2f  y %.2f..%.2f (metres, piece-local, base at 0)"
		% [model, (lo.x - (lo.x + hi.x) * 0.5) * S, (hi.x - (lo.x + hi.x) * 0.5) * S,
			0.0, (hi.y - lo.y) * S])
	# Rows top-down so the printout reads the way the piece stands.
	for r in range(GRID):
		var y: float = hi.y - (float(r) + 0.5) * (hi.y - lo.y) / float(GRID)
		var line := ""
		for c in range(GRID):
			var x: float = lo.x + (float(c) + 0.5) * (hi.x - lo.x) / float(GRID)
			line += "#" if _covered(tris, x, y) else "."
		print("  " + line)

func _covered(tris: PackedVector3Array, x: float, y: float) -> bool:
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var d1 := (x - b.x) * (a.y - b.y) - (a.x - b.x) * (y - b.y)
		var d2 := (x - c.x) * (b.y - c.y) - (b.x - c.x) * (y - c.y)
		var d3 := (x - a.x) * (c.y - a.y) - (c.x - a.x) * (y - a.y)
		var neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
		var pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
		if not (neg and pos):
			return true
	return false

func _faces(n: Node, t: Transform3D, out: PackedVector3Array) -> void:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		if m:
			for v in m.get_faces():
				out.append(lt * v)
	for c in n.get_children():
		_faces(c, lt, out)

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

func _materials(n: Node, out: Array[String]) -> void:
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		if m:
			for s in range(m.get_surface_count()):
				var sm := m.surface_get_material(s)
				var nm: String = sm.resource_name if sm else "<none>"
				if not out.has(nm):
					out.append(nm)
	for c in n.get_children():
		_materials(c, out)
