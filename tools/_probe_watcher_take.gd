extends SceneTree

## Throwaway probe: samples the watcher's single baked take and reports what is
## actually happening at each moment, so CLIPS ranges can be checked rather than
## trusted. Prints, per sample: overall bone motion, foot separation (walking
## swings the feet apart and back), and mace-hand height (a swing arcs it high).
##
##   Godot --headless --path . -s tools/_probe_watcher_take.gd

const SCENE := "res://scenes/watcher.tscn"

func _init() -> void:
	var w := (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(w)
	w.set_script(null)          # keep the AI out of the way
	await process_frame

	var sk: Skeleton3D = null
	for n in w.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	var ap: AnimationPlayer = null
	for n in w.find_children("*", "AnimationPlayer", true, false):
		ap = n
		break
	if sk == null or ap == null:
		print("missing skeleton/anim")
		quit(1)
		return

	print("bones:")
	var names: PackedStringArray = []
	for i in range(sk.get_bone_count()):
		names.append(sk.get_bone_name(i))
	print("  ", ", ".join(names))

	var anim := ap.get_animation("all")
	print("take length %.3f" % anim.length)

	var l_foot := _find(sk, ["LeftFoot", "foot.L", "LeftToeBase"])
	var r_foot := _find(sk, ["RightFoot", "foot.R", "RightToeBase"])
	var hand := _find(sk, ["RightHand", "hand.R", "LeftHand"])
	var hips := _find(sk, ["Hips", "hips", "Root"])
	print("probe bones: lfoot=%d rfoot=%d hand=%d hips=%d" % [l_foot, r_foot, hand, hips])

	var args := OS.get_cmdline_user_args()
	var from := float(args[0]) if args.size() > 0 else 0.0
	var to: float = float(args[1]) if args.size() > 1 else anim.length
	var step := float(args[2]) if args.size() > 2 else 0.10

	ap.play("all")
	ap.speed_scale = 0.0
	var prev: Array = []
	var t := from
	print("\n   t   motion  footsep  handY  hipY")
	while t <= to:
		ap.seek(t, true)
		await process_frame
		var cur: Array = []
		for i in range(sk.get_bone_count()):
			cur.append(sk.get_bone_global_pose(i).origin)
		var motion := 0.0
		if prev.size() == cur.size():
			for i in range(cur.size()):
				motion += (cur[i] - prev[i]).length()
			motion /= float(cur.size())
		prev = cur
		var footsep := 0.0
		if l_foot >= 0 and r_foot >= 0:
			footsep = (cur[l_foot] - cur[r_foot]).length()
		var handy: float = cur[hand].y if hand >= 0 else 0.0
		var hipy: float = cur[hips].y if hips >= 0 else 0.0
		print("%6.2f  %6.4f  %6.3f  %6.3f  %6.3f" % [t, motion, footsep, handy, hipy])
		t += step
	quit()

func _find(sk: Skeleton3D, wanted: Array) -> int:
	for w in wanted:
		for i in range(sk.get_bone_count()):
			if sk.get_bone_name(i).to_lower().ends_with(String(w).to_lower()):
				return i
	return -1
