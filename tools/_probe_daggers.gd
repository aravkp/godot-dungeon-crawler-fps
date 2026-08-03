extends SceneTree
## What is actually inside the free dagger pack: node shape, mesh count, measured
## world bounds, long axis, and where the model origin sits along it.
##
## None of that can be assumed. This project has been bitten twice by FBX pieces
## that are not authored at their origin (the dungeon kit sits 50-60 units out),
## and a weapon has the extra problem that WHICH END IS THE HANDLE decides the
## whole mount - a dagger fitted to the wrong end is held by the blade.
##
##   "$GODOT" --headless --path . -s tools/_probe_daggers.gd

const DIR := "res://assets/daggers/fbx"
## The dagger already in the game, for comparison - the new ones have to end up
## the same size in hand or the mount fitted against it stops meaning anything.
const ORIGINAL := "res://assets/dagger/dagger.fbx"
## Slices used for the width profile that finds the guard.
const SLICES := 48


func _init() -> void:
	await _check_chain()
	_report_original()
	var names := _list()
	print("\n%-13s %6s  %-16s %-13s %s"
		% ["model", "tris", "size (m)", "grip top", "grip centre y"])
	for nm in names:
		var scn := load("%s/%s" % [DIR, nm]) as PackedScene
		if scn == null:
			print("%-14s  FAILED TO LOAD" % nm)
			continue
		var inst := scn.instantiate() as Node3D
		var meshes: Array = []
		_collect(inst, Transform3D.IDENTITY, meshes)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var tris := 0
		for m in meshes:
			var ab: AABB = (m["mesh"] as Mesh).get_aabb()
			var t: Transform3D = m["xform"]
			for i in range(8):
				var p: Vector3 = t * ab.get_endpoint(i)
				lo = lo.min(p)
				hi = hi.max(p)
			for s in range((m["mesh"] as Mesh).get_surface_count()):
				tris += (m["mesh"] as Mesh).surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		var size := hi - lo
		var grip_top := _grip_top(meshes, lo.y, hi.y)
		print("%-13s %6d  %-16s %-13s %.4f"
			% [nm.replace(".fbx", ""), tris,
			"%.3f x %.3f" % [size.x, size.y],
			"%.3f (%.0f%%)" % [grip_top, 100.0 * grip_top / maxf(size.y, 0.001)],
			grip_top * 0.5])
		inst.free()
	quit()


## Where the guard is, in model Y. **DIAGNOSTIC ONLY - this approach was tried
## for the real mount and rejected.** Kept because the numbers it prints are what
## showed it does not work.
##
## The idea: every model runs handle-at-the-bottom along +Y, so the guard should
## be the first place the cross-section gets wide on the way up. Profile the mesh
## in slices and take the widest one below the midpoint.
##
## Why it fails: on about half this pack the widest slice below the midpoint is
## the BLADE, not the guard - several of these blades are broader than the
## crossguards under them - so it reports 45-49% and the pivot lands near the
## tip. `_dagger_12` reports 3%. A pivot that wrong is a dagger held by its
## point.
##
## dagger_variants.gd uses a fixed fraction taken off the ORIGINAL dagger's own
## named grip part instead, after normalising every model to the same length.
## One measured number beats twenty-four unreliable ones.
func _grip_top(meshes: Array, lo_y: float, hi_y: float) -> float:
	var span := hi_y - lo_y
	if span < 0.0001:
		return 0.0
	var width := PackedFloat32Array()
	width.resize(SLICES)
	for m in meshes:
		var mesh: Mesh = m["mesh"]
		var t: Transform3D = m["xform"]
		for s in range(mesh.get_surface_count()):
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var p: Vector3 = t * v
				var i := clampi(int((p.y - lo_y) / span * float(SLICES)), 0, SLICES - 1)
				var r := Vector2(p.x, p.z).length()
				if r > width[i]:
					width[i] = r
	# Widest slice below the midpoint. Above that is blade, and some of these
	# blades are wider than their guards.
	var best := 0
	var best_w := 0.0
	for i in range(SLICES / 2):
		if width[i] > best_w:
			best_w = width[i]
			best = i
	# Mean width of the handle region under it, to decide whether that peak is
	# really a guard or just the widest part of a featureless handle.
	var mean := 0.0
	var n := 0
	for i in range(best):
		mean += width[i]
		n += 1
	mean = mean / float(n) if n > 0 else best_w
	var guard_y := lo_y + (float(best) + 0.5) / float(SLICES) * span
	if best == 0 or best_w < mean * 1.35:
		return lo_y + span * 0.22
	return guard_y


## The whole chain, end to end: a chest spills a random blade, the pickup shows
## THAT blade, and taking it puts THAT blade in the hand. The three are separate
## pieces of code and the variant has to survive all of them - a skin that is
## picked but not carried through just silently shows the original.
func _check_chain() -> void:
	var pickup := load("res://scripts/pickup.gd")
	var variants := load("res://scripts/dagger_variants.gd")
	var scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var p := scene.get_node_or_null("Player")
	if p: p.set_script(null)
	get_root().add_child(scene)
	await process_frame

	var arms := scene.get_node("Player/Head/Camera3D/ViewModel/Arms")
	var art := scene.get_node("Player/Head/Camera3D/ViewModel/DaggerMount/Dagger") as Node3D
	var want: String = "_dagger_7"
	var item: Node = pickup.spawn(scene, Vector3(0, 1, 0), "dagger", want)
	var shown: String = "-none-"
	if item:
		var a: Node = item.get_node_or_null("Art")
		if a and a.get_child_count() > 0:
			shown = String(a.get_child(0).name)
	print("pickup shows: %s   (wanted %s)  %s"
		% [shown, want, "OK" if shown == want else "*** WRONG ***"])

	if item:
		item.interact(null)
	await process_frame
	var held: String = String(art.get_child(0).name) if art.get_child_count() > 0 else "-none-"
	print("hand holds:   %s   (wanted %s)  %s"
		% [held, want, "OK" if held == want else "*** WRONG ***"])
	print("has_dagger:   %s" % str(arms.get("has_dagger")))

	# And that the random pick actually varies.
	var seen := {}
	for i in range(40):
		seen[variants.pick()] = true
	print("random pick:  %d distinct of %d ids over 40 rolls"
		% [seen.size(), variants.all().size()])
	scene.queue_free()
	await process_frame
	print("")


func _report_original() -> void:
	if not ResourceLoader.exists(ORIGINAL):
		print("original dagger not found at ", ORIGINAL)
		return
	var inst := (load(ORIGINAL) as PackedScene).instantiate() as Node3D
	var meshes: Array = []
	_collect(inst, Transform3D.IDENTITY, meshes)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	var grip_lo := Vector3.INF
	var grip_hi := -Vector3.INF
	for m in meshes:
		var ab: AABB = (m["mesh"] as Mesh).get_aabb()
		var t: Transform3D = m["xform"]
		for i in range(8):
			var p: Vector3 = t * ab.get_endpoint(i)
			lo = lo.min(p); hi = hi.max(p)
			if String(m["name"]) == "grip":
				grip_lo = grip_lo.min(p); grip_hi = grip_hi.max(p)
	print("ORIGINAL dagger.fbx: parts=%s  size=%.3f x %.3f x %.3f"
		% [str(meshes.size()), hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])
	if grip_lo != Vector3.INF:
		print("  named grip spans y %.3f .. %.3f, centre %.4f"
			% [grip_lo.y, grip_hi.y, (grip_lo.y + grip_hi.y) * 0.5])
	inst.free()


func _collect(n: Node, t: Transform3D, out: Array) -> void:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"name": n.name, "mesh": (n as MeshInstance3D).mesh, "xform": lt})
	for c in n.get_children():
		_collect(c, lt, out)


func _list() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		push_error("no such dir: " + DIR)
		return out
	for f in d.get_files():
		if f.ends_with(".fbx"):
			out.append(f)
	out.sort_custom(func(a, b):
		return int(a.get_basename().split("_")[-1]) < int(b.get_basename().split("_")[-1]))
	return out
