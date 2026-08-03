extends Node

## Runtime ragdoll for a skinned enemy. Shared, like blood.gd - used via
## preload rather than a class_name, because global class registration lives in
## the editor's scan cache and headless tool runs never rebuild it.
##
## WHY IT IS BUILT AT RUNTIME. The Skeleton3D lives inside an instanced scene
## (watcher.tscn instances watcher.fbx), and pack() silently drops new child
## nodes added inside an instance - see DESIGN.md. A PhysicalBoneSimulator3D
## baked into watcher.tscn by a tool script would therefore just not be in the
## saved file, with ResourceSaver still returning OK. Building it in code
## sidesteps that completely, and costs nothing until something actually dies.
##
## It is NOT the whole 65-bone Mixamo rig - eleven bodies. Fingers and toes add
## solver cost and jitter for detail nobody sees on a corpse.

## bone, tip bone, radius as a fraction of bone length, mass kg, cone swing deg,
## cone twist deg. Bones are matched by SUFFIX, so `mixamorig_LeftArm` and a
## bare `LeftArm` both resolve; a rig missing an entry just skips it.
##
## MASSES ARE ROUGHLY HUMAN (~64 kg total), and the ratios are what matter rather
## than the absolute numbers: a torso several times heavier than a forearm is
## what makes a corpse fall as one thing that has limbs, instead of as eleven
## objects of similar weight that happen to be tied together.
##
## TWIST IS THE RUBBER-LIMB DIAL. Swing lets a joint bend, which corpses do;
## twist lets it corkscrew about its own axis, which is what reads as boneless.
## The elbows and knees have almost none. They keep a usable swing because a
## dead body's elbows do bend - clamping those shut looks like a mannequin, which
## is the opposite failure and just as obvious.
##
## THE SPINE AND HIPS ARE THE TIGHT ONES, and they are what stop the corpse
## curling into a ball. Give the hips a wide swing and the legs tuck to the chest
## on impact; give the spine one and the torso folds over them. The body then
## lands as a bundle rather than toppling, which is the single most game-like
## thing a ragdoll does. A person falls roughly as a rigid thing with loose
## limbs, so the limbs get the range and the trunk does not.
const CHAIN := [
	["Hips", "Spine1", 0.50, 14.0, 0.0, 0.0],
	["Spine1", "Neck", 0.42, 13.0, 14.0, 10.0],
	["Head", "HeadTop_End", 0.34, 5.0, 22.0, 14.0],
	["LeftArm", "LeftForeArm", 0.28, 2.2, 70.0, 25.0],
	["LeftForeArm", "LeftHand", 0.18, 1.5, 55.0, 6.0],
	["RightArm", "RightForeArm", 0.28, 2.2, 70.0, 25.0],
	["RightForeArm", "RightHand", 0.18, 1.5, 55.0, 6.0],
	["LeftUpLeg", "LeftLeg", 0.22, 8.5, 32.0, 12.0],
	["LeftLeg", "LeftFoot", 0.17, 4.0, 50.0, 5.0],
	["RightUpLeg", "RightLeg", 0.22, 8.5, 32.0, 12.0],
	["RightLeg", "RightFoot", 0.17, 4.0, 50.0, 5.0],
]

## Corpses get their OWN collision layer, and it is not 0.
##
## Layer 0 is the obvious choice for "nothing should target this" and it has a
## consequence that is easy to miss: collision needs `layer & mask` to be
## non-zero on at least one side, so bodies on layer 0 cannot collide with EACH
## OTHER either. The whole ragdoll becomes self-intersecting - arms sink through
## the chest, thighs pass through the pelvis, and the corpse folds into a pile
## thinner than the body it came from.
##
## Layer 2 with a mask of world|self fixes that and keeps the original property,
## because nothing else in this project masks anything but layer 1.
const CORPSE_LAYER := 2
const WORLD_LAYER := 1

## Builds the bodies under `skel` but does NOT start them simulating, so the
## caller can apply an impulse in the same frame the corpse goes limp.
## `layer` is the corpse's own, so the bodies collide with the world and with one
## another but nothing targets them - see CORPSE_LAYER.
## Returns null if the rig has too few of the expected bones to be worth it.
static func build(skel: Skeleton3D, layer: int = CORPSE_LAYER,
		mask: int = WORLD_LAYER | CORPSE_LAYER) -> PhysicalBoneSimulator3D:
	var sim := PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	skel.add_child(sim)

	# THE SCALE TRAP. A simulating PhysicalBone3D writes its bone as
	#     pose = skeleton_global.inverse() * body_world * body_offset.inverse()
	# so every bit of scale on the skeleton's ancestors lands in the bone basis,
	# inverted. This rig is scaled to real-world size by build_watcher_scene.gd
	# (Mixamo authors it ~340 units tall), so k is about 0.0028 and an
	# uncompensated ragdoll renders the mesh ~360x too big - it fills the screen.
	#
	# Putting 1/k in body_offset.basis cancels it, and does so in the useful
	# direction: at rest the body's own world transform is
	# skeleton_global * bone_rest * body_offset, which then comes out unit-scale,
	# which is what a physics body needs anyway. The consequence is that the
	# COLLISION SHAPES are in world metres while body_offset.origin stays in
	# skeleton units - the two are not in the same space, and that is correct.
	var k: float = skel.global_transform.basis.get_scale().x
	if is_zero_approx(k):
		k = 1.0

	for entry in CHAIN:
		var bone: int = _find(skel, entry[0])
		var tip: int = _find(skel, entry[1])
		if bone < 0 or tip < 0:
			continue
		# The bone's own frame, so body_offset composes with the live bone pose.
		var local: Vector3 = skel.get_bone_global_rest(bone).affine_inverse() \
			* skel.get_bone_global_rest(tip).origin
		var length := local.length()
		if length < 0.0001:
			continue
		var dir := local / length
		# Shapes are world-space; see the scale note above.
		var world_length := length * k
		var radius: float = world_length * float(entry[2])

		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + skel.get_bone_name(bone)
		# Must be in the tree before bone_name: binding walks up to the skeleton.
		sim.add_child(pb)
		pb.set("bone_name", skel.get_bone_name(bone))

		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		# CapsuleShape3D.height is the TOTAL height, caps included.
		cap.height = maxf(world_length, radius * 2.0 + 0.001)
		cs.shape = cap
		pb.add_child(cs)

		# body_global = bone_global * body_offset, and the capsule's own axis is
		# +Y, so aim +Y down the bone and sit the body at the bone's midpoint.
		var offset := Transform3D(
			_basis_aiming_y_at(dir).scaled(Vector3.ONE / k), dir * (length * 0.5))
		pb.set_body_offset(offset)
		# Put the joint back on the bone's origin - the shoulder end, not the
		# middle of the capsule. set_body_offset() does this itself, but only
		# once a parent skeleton is known, so state it rather than rely on order.
		pb.set_joint_offset(Transform3D(Basis(), offset.affine_inverse().origin))

		pb.set("joint_type", PhysicalBone3D.JOINT_TYPE_CONE)
		pb.set("joint_constraints/swing_span", entry[4])
		pb.set("joint_constraints/twist_span", entry[5])
		pb.mass = entry[3]
		# High friction and no bounce: a body that skids or bounces on landing
		# reads as a prop. Damping is what stops the limbs windmilling after the
		# hit - a corpse is dead weight, and the previous 0.15/0.6 left it
		# swinging for long enough to look like it was still trying.
		pb.friction = 1.0
		pb.bounce = 0.0
		pb.linear_damp = 0.4
		pb.angular_damp = 1.6
		# Let a settled corpse sleep. It stops the solver jittering the pile for
		# the couple of seconds it lingers, and costs nothing - sink() wakes them
		# again explicitly when it is time to go.
		pb.can_sleep = true
		pb.collision_layer = layer
		pb.collision_mask = mask

	if bodies(sim).is_empty():
		sim.queue_free()
		return null
	return sim

static func bodies(sim: PhysicalBoneSimulator3D) -> Array:
	var out: Array = []
	if sim == null or not is_instance_valid(sim):
		return out
	for c in sim.get_children():
		if c is PhysicalBone3D:
			out.append(c)
	return out

## Stop live actors kicking the corpse around the level.
##
## The bodies sit on collision LAYER 0 so nothing targets them, but their MASK
## still sees everything on layer 1 - and this project has no layer convention
## at all, so the ground, the player and every enemy are on layer 1 together.
## The result is that anything walking over a corpse shoves it: killing one
## watcher alerts its squad, the siblings charge across the body, and it slid a
## measured 3.9m out of Camp_00. Excluding them one by one is the fix that does
## not need a project-wide layer split.
##
## Bodies that appear AFTER this call are not covered - a bat spawned next to a
## fresh corpse can still nudge it. Corpses last about four seconds and bats
## spawn on a ring around the player, so that has not been worth chasing.
static func ignore(sim: PhysicalBoneSimulator3D, others: Array) -> void:
	if sim == null or not is_instance_valid(sim):
		return
	for o in others:
		if o is CollisionObject3D and is_instance_valid(o):
			sim.physical_bones_add_collision_exception(
				(o as CollisionObject3D).get_rid())

## Go limp. `impulse` is world-space and lands on whichever body is nearest `at`,
## so a headshot snaps the head back and a leg hit sweeps the legs.
##
## `inherit_velocity` should be the character's own velocity the instant it died.
## **Without it a corpse stops dead in the air and then falls straight down**,
## which is precisely what it is - the animation being switched off - and reads
## that way. A watcher killed mid-charge should keep going and land short of
## where it was heading.
##
## `max_spin` caps the initial angular velocity, in radians/sec. An off-centre
## impulse on a 1.5 kg forearm otherwise spins it like a rotor and drags the
## whole body around with it.
static func start(sim: PhysicalBoneSimulator3D, at: Vector3 = Vector3.INF,
		impulse: Vector3 = Vector3.ZERO, inherit_velocity: Vector3 = Vector3.ZERO,
		max_spin: float = 9.0) -> void:
	if sim == null or not is_instance_valid(sim):
		return
	sim.physical_bones_start_simulation()
	var all := bodies(sim)
	if not inherit_velocity.is_zero_approx():
		for pb: PhysicalBone3D in all:
			pb.linear_velocity = inherit_velocity
	if not impulse.is_zero_approx():
		var best: PhysicalBone3D = null
		var best_d := INF
		for pb: PhysicalBone3D in all:
			if at == Vector3.INF:
				best = pb
				break
			var d := pb.global_position.distance_squared_to(at)
			if d < best_d:
				best_d = d
				best = pb
		if best:
			if at == Vector3.INF:
				best.apply_central_impulse(impulse)
			else:
				# Applied OFF-CENTRE, at the actual hit point. A central impulse
				# only shoves the body along; an offset one also turns it, which
				# is most of what makes a blow look like it landed somewhere
				# rather than like the corpse was pushed.
				best.apply_impulse(impulse, at - best.global_position)
	for pb: PhysicalBone3D in all:
		if pb.angular_velocity.length() > max_spin:
			pb.angular_velocity = pb.angular_velocity.normalized() * max_spin

## Stop resting on the floor and slide out of the world. Clearing the mask is
## what does it - a body still colliding with the ground cannot be pushed into
## it, which is the same reason the corpse used to be sunk by hand.
static func sink(sim: PhysicalBoneSimulator3D, gravity_scale: float) -> void:
	for pb: PhysicalBone3D in bodies(sim):
		pb.collision_mask = 0
		# The LAYER goes too, not just the mask. Corpses see each other now, so
		# clearing only the mask leaves a sinking body still solid to a fresher
		# one lying next to it - it hangs up halfway into the floor instead of
		# going. One-hit kills make two corpses in one place the normal case.
		pb.collision_layer = 0
		pb.gravity_scale = gravity_scale
		# Bodies that settled are asleep, and changing gravity does not wake one.
		PhysicsServer3D.body_set_state(pb.get_rid(),
			PhysicsServer3D.BODY_STATE_SLEEPING, false)

## Highest point of the corpse, for measuring how far it has sunk.
static func top_y(sim: PhysicalBoneSimulator3D) -> float:
	var y := -INF
	for pb: PhysicalBone3D in bodies(sim):
		y = maxf(y, pb.global_position.y)
	return y

## Matches by suffix so the mixamorig_ prefix (or its absence) does not matter.
static func _find(skel: Skeleton3D, wanted: String) -> int:
	var exact := skel.find_bone(wanted)
	if exact >= 0:
		return exact
	var suffix := wanted.to_lower()
	for i in range(skel.get_bone_count()):
		if skel.get_bone_name(i).to_lower().ends_with(suffix):
			return i
	return -1

## A basis whose +Y is `dir`; the other two axes are arbitrary but orthonormal,
## which is all a capsule needs.
static func _basis_aiming_y_at(dir: Vector3) -> Basis:
	var up := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := up.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	return Basis(x, dir, z)
