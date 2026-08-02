class_name DebrisFX
extends Object

## One-shot chunk burst for smashed scenery - the crate/door/chest counterpart to
## blood.gd, and deliberately built the same way so the two read as one family.
##
## Like the blood burst it is parented to `host`, which must OUTLIVE the thing
## that spawned it (the level, not the crate), or the chunks vanish on the same
## frame as the prop they came out of. It frees itself on a timer.
##
## Used via preload rather than this class_name, for the same reason blood.gd is:
## global class registration lives in the editor's scan cache, which headless
## runs never rebuild.
static func burst(host: Node, at: Vector3, count: int, speed: float,
		color: Color, scale_mult: float = 1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var fx := GPUParticles3D.new()
	fx.name = "Debris"
	host.add_child(fx)
	fx.global_position = at
	fx.amount = maxi(1, int(count * scale_mult))
	fx.lifetime = 1.1
	fx.one_shot = true
	fx.explosiveness = 0.95
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.3 * scale_mult
	pm.initial_velocity_max = speed * scale_mult
	pm.gravity = Vector3(0, -16.0, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.8
	# Splinters tumble; droplets do not. This is the main thing that tells the
	# two bursts apart in motion rather than in colour.
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	pm.angular_velocity_min = -520.0
	pm.angular_velocity_max = 520.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	fx.process_material = pm

	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.09, 0.09, 0.045)
	fx.draw_pass_1 = chunk

	var mat := StandardMaterial3D.new()
	# Unshaded, like the blood. The corridor level is lit by a handful of
	# coloured lamps and is pitch dark between them; a shaded chunk that spawns
	# off a lamp is simply invisible, which is the one thing a hit reaction
	# cannot be.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	fx.material_override = mat

	var timer := host.get_tree().create_timer(fx.lifetime + 0.6)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(fx):
			fx.queue_free())
