class_name BloodFX
extends Object

## One-shot blood burst shared by every enemy. Originally built inside
## bat_enemy.gd; extracted unchanged when the watchers got the same treatment,
## so both enemies bleed identically and the look is tuned in one place.
##
## The burst is parented to `host` - pass something that OUTLIVES the corpse
## (the enemy's parent, i.e. the level or a camp node), never the enemy itself,
## or the spray vanishes with the body. It frees itself on a timer.
static func spray(host: Node, at: Vector3, count: int, speed: float,
		color: Color, scale_mult: float = 1.0) -> void:
	if host == null or not host.is_inside_tree():
		return
	var fx := GPUParticles3D.new()
	fx.name = "Blood"
	host.add_child(fx)
	fx.global_position = at
	fx.amount = maxi(1, int(count * scale_mult))
	fx.lifetime = 0.85
	fx.one_shot = true
	fx.explosiveness = 0.95
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.35 * scale_mult
	pm.initial_velocity_max = speed * scale_mult
	pm.gravity = Vector3(0, -14.0, 0)
	pm.damping_min = 0.5
	pm.damping_max = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	fx.process_material = pm

	var droplet := SphereMesh.new()
	droplet.radius = 0.035
	droplet.height = 0.07
	droplet.radial_segments = 5
	droplet.rings = 3
	fx.draw_pass_1 = droplet

	var mat := StandardMaterial3D.new()
	# Unshaded so it stays red whatever the local lighting does.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	fx.material_override = mat

	var timer := host.get_tree().create_timer(fx.lifetime + 0.6)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(fx):
			fx.queue_free())
