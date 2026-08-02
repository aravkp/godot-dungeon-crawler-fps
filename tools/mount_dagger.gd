extends SceneTree

## Mounts the dagger on the right hand of the first-person arms.
##
## Re-runnable - it removes any previous mount first, so tune the constants
## below and run it again:
##
##   Godot --headless --path . -s tools/mount_dagger.gd
##
## The FBX references four textures by the author's local Linux paths
## (blade/grip/guard/pommel.png) which were never shipped, so each part falls
## back to a flat colour - see FALLBACK below.
##
## Meshes are lifted out of the import rather than instanced: property changes
## on nodes inside an instanced scene get silently dropped by pack().

const DAGGER := "res://assets/dagger/dagger.fbx"
const SKEL_PATH := "Player/Head/Camera3D/ViewModel/Arms/ArmsRig/Skeleton3D"
## The mount lives OUTSIDE the Arms instance: pack() silently drops nodes added
## inside an instanced scene. BoneAttachment3D's external-skeleton mode tracks
## the bone from here instead, setting its own global transform each frame.
const MOUNT_PARENT := "Player/Head/Camera3D/ViewModel"
## Relative to the mount, whose parent IS ViewModel - so ".." lands there.
const SKEL_FROM_MOUNT := "../Arms/ArmsRig/Skeleton3D"
const BONE := "hand.R"

# --- tunables: edit these and re-run -----------------------------------------
## Both of these were SOLVED from the hand, not eyeballed. With knife_idle
## playing (seeked to 0.6s), every right-hand joint was sampled in hand.R local
## space and, per finger, the centroid of {palm, .01, .02, .03} taken. Those
## four centroids line up at x~-0.016, y~0.086, z from +0.031 (index) to
## -0.033 (pinky):
##
##   - the grip tunnel axis is almost exactly the hand bone's +Z - ACROSS the
##     fingers, not along them. hand.R +Y runs wrist->fingertips, so D_ROT = 0
##     spears the blade out of the knuckles like a claw.
##   - D_POS  = the centroid mean, then tucked 5mm toward the palm (+X) so the
##     handle nestles against it instead of showing through the finger gaps.
##   - D_ROT  = YXZ euler of a frame whose +Y (the dagger models along +Y) is
##     the tunnel axis canted 22 degrees toward camera-forward, with its +Z
##     rolled to face the camera so the blade reads flat, not edge-on.
##
## The 22 degree cant is the only styling liberty: a blade dead down the tunnel
## points sideways across the screen (knife_idle poses the fist knuckles-out),
## and camera-forward is 101 degrees away from the tunnel in hand space. The
## previous fit slerped 40% of the way there - a 40 degree tilt that drove the
## handle diagonally out of the tunnel, blade out the back of the fist and
## pommel out through the fingers. Past ~25 degrees the pommel starts leaving
## the fist; verify any change with tools/shot_dagger.gd.
const D_POS := Vector3(-0.0105, 0.0837, -0.0015)
const D_ROT := Vector3(63.6, 16.9, 19.6)
const D_SCALE := 1.35    # slight viewmodel exaggeration; reads better in frame
# -----------------------------------------------------------------------------

## The dagger's own PNGs (blade/grip/guard/pommel) were never shipped, so each
## part falls back to a flat colour. Drop the real files into assets/dagger/ and
## re-run and they will be picked up automatically.
##
## The dungeon kit's metal textures were tried first and rejected: TEX_Metal_01
## measures 0.09 luma, which renders the blade nearly black in hand.
const FALLBACK := {
	"blade": Color(0.72, 0.75, 0.80),    # bright steel, reads at a glance
	"guard": Color(0.42, 0.38, 0.30),    # dull brass
	"pommel": Color(0.42, 0.38, 0.30),
	"grip": Color(0.30, 0.19, 0.12),     # dark leather
}

var _root: Node

func _init() -> void:
	_root = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var skel := _root.get_node_or_null(SKEL_PATH) as Skeleton3D
	if skel == null:
		print("FAIL: no Skeleton3D at ", SKEL_PATH); quit(1); return
	if skel.find_bone(BONE) < 0:
		print("FAIL: no bone named ", BONE); quit(1); return

	var host := _root.get_node_or_null(MOUNT_PARENT) as Node3D
	if host == null:
		print("FAIL: no node at ", MOUNT_PARENT); quit(1); return
	var old := host.get_node_or_null("DaggerMount")
	if old:
		host.remove_child(old)
		old.queue_free()

	var mount := BoneAttachment3D.new()
	mount.name = "DaggerMount"
	host.add_child(mount)
	mount.owner = _root
	mount.use_external_skeleton = true
	mount.set_external_skeleton(NodePath(SKEL_FROM_MOUNT))
	mount.bone_name = BONE

	var dagger := Node3D.new()
	dagger.name = "Dagger"
	mount.add_child(dagger)
	dagger.owner = _root
	dagger.position = D_POS
	dagger.rotation_degrees = D_ROT
	dagger.scale = Vector3(D_SCALE, D_SCALE, D_SCALE)

	var src := (load(DAGGER) as PackedScene).instantiate() as Node3D
	src.transform = Transform3D.IDENTITY

	# Re-centre every part on the GRIP. Without this the Dagger node's origin
	# is the model origin, which sits ~8cm down the blade axis from the grip -
	# so any D_ROT swings the handle out of the palm on an 8cm arm and you end
	# up chasing D_POS every time you touch the angle. Pivoting on the grip
	# makes rotation behave like a wrist.
	var pivot := _part_centre(src, "grip")
	print("grip centre in model space: %.4v" % [pivot])

	var made := 0
	for part: String in FALLBACK:
		var found := _find(src, part, Transform3D.IDENTITY)
		if found.is_empty():
			push_warning("dagger: no part named " + part)
			continue
		var mi := MeshInstance3D.new()
		mi.name = part
		dagger.add_child(mi)
		mi.owner = _root
		mi.mesh = found["mesh"]
		# Keep the FBX's own inner transform or the parts fly apart, then slide
		# the whole assembly so the grip lands on the node origin.
		var xf: Transform3D = found["xform"]
		xf.origin -= pivot
		mi.transform = xf
		var mat := StandardMaterial3D.new()
		mat.resource_name = "dagger_" + part
		var own_tex := "res://assets/dagger/%s.png" % part
		if ResourceLoader.exists(own_tex):
			mat.albedo_texture = load(own_tex)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		else:
			mat.albedo_color = FALLBACK[part]
		mat.roughness = 0.6 if part == "blade" else 1.0
		mat.metallic = 0.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		for s in range(mi.mesh.get_surface_count()):
			mi.set_surface_override_material(s, mat)
		made += 1
	src.free()

	var out := PackedScene.new()
	var err := out.pack(_root)
	if err != OK:
		print("pack failed: ", err); quit(1); return
	err = ResourceSaver.save(out, "res://scenes/main.tscn")
	print("mounted %d dagger parts on '%s', save err=%d" % [made, BONE, err])
	quit()

## World-space centre of one named part, in the FBX root's frame.
func _part_centre(src: Node3D, part: String) -> Vector3:
	var f := _find(src, part, Transform3D.IDENTITY)
	if f.is_empty():
		return Vector3.ZERO
	var ab: AABB = (f["mesh"] as Mesh).get_aabb()
	var t: Transform3D = f["xform"]
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for i in range(8):
		var p: Vector3 = t * ab.get_endpoint(i)
		lo = lo.min(p)
		hi = hi.max(p)
	return (lo + hi) * 0.5

## Finds a named MeshInstance3D plus its transform relative to the FBX root.
func _find(n: Node, want: String, t: Transform3D) -> Dictionary:
	var lt := t
	if n is Node3D:
		lt = t * (n as Node3D).transform
	if n is MeshInstance3D and n.name == want and (n as MeshInstance3D).mesh != null:
		return {"mesh": (n as MeshInstance3D).mesh, "xform": lt}
	for c in n.get_children():
		var r := _find(c, want, lt)
		if not r.is_empty():
			return r
	return {}
