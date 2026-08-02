extends SceneTree

## Throwaway probe: what is actually inside a character FBX.
##
##   Godot --headless --path . -s tools/_probe_character.gd -- res://path/to.fbx
##
## Answers the only questions that decide whether a rig is usable here: does it
## have a skeleton, what are its bones called, what animations ship with it and
## how long are they, how tall is it in metres, and which way does it face.
##
## Sizes come from BONE GLOBAL POSES, never the mesh AABB - a skinned mesh
## reports garbage (chonchon.fbx reads ~74,000 units), and the measurement is
## taken with an animation applied, since a bind pose can be 50% wrong.

const DEFAULT := "res://assets/retro_character/retro_character.fbx"

func _init() -> void:
	var path := DEFAULT
	for a in OS.get_cmdline_user_args():
		path = a
	var packed := load(path) as PackedScene
	if packed == null:
		print("FAIL: %s did not load as a scene" % path)
		quit()
		return
	var root := packed.instantiate()
	get_root().add_child(root)
	await process_frame

	print("\n=== %s ===" % path)
	print("root: %s [%s]" % [root.name, root.get_class()])
	_tree(root, 1)

	var skel: Skeleton3D = null
	for n in root.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	var ap: AnimationPlayer = null
	for n in root.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break

	if skel == null:
		print("\nNO SKELETON - this is a static mesh, like assets/skeleton/.")
	else:
		print("\n--- skeleton: %s ---" % skel.name)
		print("  bones:     %d" % skel.get_bone_count())
		print("  scale:     %.4v (skeleton global)" % skel.global_transform.basis.get_scale())
		var names := PackedStringArray()
		for i in range(skel.get_bone_count()):
			names.append(skel.get_bone_name(i))
		print("  names:     %s" % ", ".join(names))
		# Which of ragdoll.gd's CHAIN entries this rig could satisfy. Bones are
		# matched by SUFFIX there, so a bare "LeftArm" and "mixamorig_LeftArm"
		# both resolve.
		var want := ["Hips", "Spine", "Head", "LeftArm", "LeftForeArm",
			"RightArm", "RightForeArm", "LeftUpLeg", "LeftLeg", "RightUpLeg",
			"RightLeg"]
		var have := PackedStringArray()
		var miss := PackedStringArray()
		for w in want:
			var found := false
			for n2 in names:
				if n2.to_lower().ends_with(w.to_lower()):
					found = true
					break
			if found:
				have.append(w)
			else:
				miss.append(w)
		print("  ragdoll chain: %d/11 matched" % have.size())
		if miss.size() > 0:
			print("  ragdoll missing: %s" % ", ".join(miss))

	if ap == null:
		print("\nNO ANIMATION PLAYER - no animations ship with this file.")
	else:
		var list := ap.get_animation_list()
		print("\n--- animations: %d ---" % list.size())
		for a in list:
			var anim := ap.get_animation(a)
			print("  %-40s %6.2f s  %3d tracks  loop=%d"
				% [a, anim.length, anim.get_track_count(), anim.loop_mode])
		# Measure with an animation applied, per the project's own rule.
		if skel and list.size() > 0:
			ap.play(list[0])
			ap.seek(anim_mid(ap, list[0]), true)
			await process_frame
			_measure(skel, "during '%s'" % list[0])
	if skel:
		_measure(skel, "as loaded")

	print("\n--- meshes ---")
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var m := mi.mesh
		var surf := m.get_surface_count() if m else 0
		var tris := 0
		for s in range(surf):
			var arr := m.surface_get_arrays(s)
			if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
				tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif arr.size() > Mesh.ARRAY_VERTEX:
				tris += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		print("  %s  surfaces=%d  tris=%d  skinned=%s"
			% [mi.name, surf, tris, mi.skin != null])
		for s in range(surf):
			var mat := mi.get_active_material(s)
			var tex := "none"
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture:
				var t := (mat as StandardMaterial3D).albedo_texture
				tex = "%dx%d" % [t.get_width(), t.get_height()]
			print("      surf %d  material=%s  albedo_tex=%s"
				% [s, "null" if mat == null else str(mat.resource_name), tex])
	quit()

## The node tree, a few levels deep - enough to see how the file is organised.
func _tree(n: Node, depth: int) -> void:
	if depth > 3:
		return
	for c in n.get_children():
		print("%s%s [%s]" % ["  ".repeat(depth), c.name, c.get_class()])
		_tree(c, depth + 1)

func anim_mid(ap: AnimationPlayer, name: String) -> float:
	return ap.get_animation(name).length * 0.5

## Height and reach from bone global poses, in metres after the node's scale.
func _measure(skel: Skeleton3D, when: String) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in range(skel.get_bone_count()):
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	print("  bone bounds %s: %.3v .. %.3v  ->  h=%.3f m  w=%.3f m"
		% [when, lo, hi, hi.y - lo.y, hi.x - lo.x])
