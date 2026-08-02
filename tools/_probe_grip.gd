extends SceneTree

## Throwaway probe: measures how CURLED each hand is in every arms_rig.glb
## animation, to find poses that grip something rather than punch or point.
##
## Per finger: the distance from its tip bone to the hand bone, divided by the
## same distance in the rig's REST pose (the T-pose, fingers straight). 1.00 is
## fully extended, lower is more curled. A gun grip is the interesting shape -
## middle/ring/pinky curled around a handle while the index stays straighter for
## the trigger - which a plain fist does not do.

const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]

func _init() -> void:
	var arms := (load("res://assets/hands/arms_rig.glb") as PackedScene).instantiate()
	get_root().add_child(arms)
	await process_frame
	var skel: Skeleton3D = arms.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = arms.find_children("*", "AnimationPlayer", true, false)[0]

	var names: PackedStringArray = []
	for i in range(skel.get_bone_count()):
		names.append(skel.get_bone_name(i))
	print("bones: ", ", ".join(names))

	var ref := {}
	for side in ["L", "R"]:
		for f in FINGERS:
			var tip := skel.find_bone("f_%s.03.%s" % [f, side])
			if tip < 0:
				tip = skel.find_bone("%s.03.%s" % [f, side])
			var hand := skel.find_bone("hand.%s" % side)
			if tip < 0 or hand < 0:
				continue
			# Rest pose = straight fingers, so this is the extended length.
			ref["%s.%s" % [f, side]] = [tip, hand,
				(skel.get_bone_global_rest(tip).origin
					- skel.get_bone_global_rest(hand).origin).length()]

	print("\n1.00 = finger straight, lower = more curled")
	print("%-18s |   L: idx  mid  rng  pnk  thb |   R: idx  mid  rng  pnk  thb"
		% "animation")
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		ap.play(n)
		ap.speed_scale = 0.0
		ap.seek(a.length * 0.5, true)
		await process_frame
		var row := ""
		for side in ["L", "R"]:
			row += " |     "
			for f in FINGERS:
				var k := "%s.%s" % [f, side]
				if not ref.has(k):
					row += "  -- "
					continue
				var e: Array = ref[k]
				var d: float = (skel.get_bone_global_pose(e[0]).origin
					- skel.get_bone_global_pose(e[1]).origin).length()
				row += " %.2f" % (d / maxf(e[2], 0.0001))
		print("%-18s%s" % [n, row])
	quit()
