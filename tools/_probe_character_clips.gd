extends SceneTree

## Throwaway probe: works out what a pile of unnamed Mixamo clips actually ARE.
##
##   Godot --headless --path . -s tools/_probe_character_clips.gd
##
## The retro character FBX ships 16 animations all called some variant of
## "Armature_010|Armature_003|mixamo_com|Layer0", which says nothing. This walks
## each one and prints the signatures that separate the categories, the same way
## _probe_watcher_take.gd separates the segments of one baked take:
##
##   travel      how far the hips move over the clip - locomotion vs in place
##   hip dy      vertical hip range - a jump and a crouch both show here
##   feet        how many times foot separation peaks - one per stride
##   hands       highest hand above the head - a swing, a throw, a reach
##   lean        chest tilt from vertical - a run leans, an idle does not
##
## Numbers only. Confirm the guess on the contact sheet from
## tools/_probe_character_sheet.gd before trusting any of it.

const SRC := "res://assets/retro_character/retro_character.fbx"
const SAMPLES := 40

func _init() -> void:
	var root := (load(SRC) as PackedScene).instantiate()
	get_root().add_child(root)
	await process_frame
	var skel := root.find_child("Skeleton3D", true, false) as Skeleton3D
	var ap := root.find_child("AnimationPlayer", true, false) as AnimationPlayer

	var hips := skel.find_bone("mixamorig_Hips")
	var head := skel.find_bone("mixamorig_Head")
	var chest := skel.find_bone("mixamorig_Spine2")
	var lfoot := skel.find_bone("mixamorig_LeftFoot")
	var rfoot := skel.find_bone("mixamorig_RightFoot")
	var lhand := skel.find_bone("mixamorig_LeftHand")
	var rhand := skel.find_bone("mixamorig_RightHand")

	# head lo   lowest the head gets, as a fraction of its standing height: a
	#           knockdown or a crawl puts it near the floor and nothing else does
	# reach     furthest a hand gets from the chest along the body's forward axis,
	#           in head-heights - what separates a punch from an arm swing
	print("\n%-6s %7s %7s %7s %6s %6s %6s %7s %6s  %s"
		% ["clip", "len", "travel", "hip dy", "feet", "hands", "lean",
			"head lo", "reach", "name"])
	var list := ap.get_animation_list()
	for ci in range(list.size()):
		var nm: String = list[ci]
		var anim := ap.get_animation(nm)
		if anim.length <= 0.001:
			print("%-6d %7.2f  (zero length - an export artifact)" % [ci, anim.length])
			continue
		ap.play(nm)
		var hip_lo := INF
		var hip_hi := -INF
		var hip_first := Vector3.ZERO
		var hip_last := Vector3.ZERO
		var hand_max := -INF
		var lean_max := 0.0
		var head_lo := INF
		var head_hi := -INF
		var reach_max := 0.0
		var seps: Array[float] = []
		for s in range(SAMPLES):
			var t: float = anim.length * float(s) / float(SAMPLES - 1)
			ap.seek(t, true)
			await process_frame
			var h: Vector3 = skel.get_bone_global_pose(hips).origin
			if s == 0:
				hip_first = h
			hip_last = h
			hip_lo = minf(hip_lo, h.y)
			hip_hi = maxf(hip_hi, h.y)
			var hy: float = skel.get_bone_global_pose(head).origin.y
			head_lo = minf(head_lo, hy)
			head_hi = maxf(head_hi, hy)
			hand_max = maxf(hand_max, maxf(
				skel.get_bone_global_pose(lhand).origin.y,
				skel.get_bone_global_pose(rhand).origin.y) - hy)
			# Forward is the chest bone's own axis, so a turned body still reads.
			var ch := skel.get_bone_global_pose(chest)
			var fwd: Vector3 = ch.basis.z.normalized()
			for hb in [lhand, rhand]:
				var arm: Vector3 = skel.get_bone_global_pose(hb).origin - ch.origin
				reach_max = maxf(reach_max, absf(arm.dot(fwd)))
			seps.append(absf(skel.get_bone_global_pose(lfoot).origin.z
				- skel.get_bone_global_pose(rfoot).origin.z))
			# Chest tilt away from the skeleton's up axis.
			var up: Vector3 = skel.get_bone_global_pose(chest).basis.y.normalized()
			lean_max = maxf(lean_max, rad_to_deg(up.angle_to(Vector3.UP)))
		# A stride is a peak in foot separation: up then down.
		var peaks := 0
		for i in range(1, seps.size() - 1):
			if seps[i] > seps[i - 1] and seps[i] >= seps[i + 1] and seps[i] > 0.3:
				peaks += 1
		print("%-6d %7.2f %7.2f %7.2f %6d %6.2f %6.1f %7.2f %6.2f  %s" % [ci,
			anim.length, (hip_last - hip_first).length(), hip_hi - hip_lo, peaks,
			hand_max, lean_max, head_lo / maxf(head_hi, 0.001),
			reach_max / maxf(head_hi, 0.001), nm])
	quit()
