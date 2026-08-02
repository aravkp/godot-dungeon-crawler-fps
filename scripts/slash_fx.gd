class_name SlashFX
extends Object

## Pixel-art blade slashes for the dagger. Same shape as blood.gd and debris.gd
## - static helpers on an Object, pulled in with `preload` rather than by
## class_name, because global class registration lives in the editor's scan
## cache and a headless run never rebuilds it.
##
## Two effects, both from one asset pack (see assets/vfx/LICENSE.txt):
##
##   arc()     a crescent swept in front of the camera on EVERY dagger swing
##   impact()  a small scratch burst wherever the swing actually connected
##
## The arc is the one that sells the swing, because it fires whether or not you
## hit anything - a whiff still reads as a swing. The impact only fires when the
## melee ray lands, which is what makes connecting feel different from missing.
##
## COLOUR: the pack's blue/cyan ramp (#00eeff over a white core). Red is left
## free for blood, which shares the same hit position; a cold blade arc and a
## warm blood spray stay legible on top of each other.
##
## Both sheets are 640x256 - a 5-column, 2-row grid of 128x128 cells read in
## ROW-MAJOR order, nine frames used and the tenth cell empty. That is the whole
## reason for COLS/FRAMES rather than a plain hframes count.

const ARC_SHEET: Texture2D = preload("res://assets/vfx/slash_arc.png")
const IMPACT_SHEET: Texture2D = preload("res://assets/vfx/slash_impact.png")

const CELL := 128
const COLS := 5
const FRAMES := 9

## Crescent trail across the middle of the screen.
##
## `host` must be the ViewModel node, NOT the Arms instance under it: the arms
## rig carries a 180 deg Y rotation to correct its +Z forward axis (see
## DESIGN.md), and a sprite parented there lands behind the camera, invisible.
## Parenting to the ViewModel also means the arc inherits the weapon bob and
## sway for free, so it swings with the hands instead of floating over them.
##
## `mirrored` flips the crescent so the two alternating dagger clips do not
## throw the identical arc twice - it costs one bool and is most of what stops a
## held attack looking like a looping GIF.
static func arc(host: Node3D, mirrored: bool = false, distance: float = 0.85,
		size: float = 0.0075, fps: float = 42.0) -> AnimatedSprite3D:
	if host == null or not host.is_inside_tree():
		return null
	var s := _sprite(ARC_SHEET, fps, size)
	s.name = "SlashArc"
	s.flip_h = mirrored
	# Drawn over the arms and the world both. The arc is a screen effect, not an
	# object in the level, and depth-testing it against a wall the player is
	# standing near would clip it in half mid-swing.
	s.no_depth_test = true
	s.render_priority = 8
	host.add_child(s)
	s.position = Vector3(0.06 if mirrored else -0.06, -0.12, -distance)
	# A few degrees of tilt per swing, mirrored with the sprite so both sides
	# lean the way the blade is travelling.
	var lean := randf_range(4.0, 14.0)
	s.rotation.z = deg_to_rad(-lean if mirrored else lean)
	_start(s)
	return s


## Scratch burst at a point the swing connected with.
##
## `host` has to OUTLIVE the thing that was hit - pass the level, never the
## enemy, or a killing blow takes its own hit spark down with the corpse. Same
## rule as blood.gd's `host`.
##
## `toward` is the direction back along the swing (i.e. -ray direction). The
## sprite is lifted a few centimetres that way so it does not z-fight the
## surface it is sitting on.
##
## `host` does NOT have to be a Node3D, and must not be required to be: the
## level roots in this project are plain Nodes. A Node3D parented under one just
## gets an identity parent transform, so global_position lands where it should.
static func impact(host: Node, at: Vector3, toward: Vector3,
		size: float = 0.0045, fps: float = 40.0) -> AnimatedSprite3D:
	if host == null or not host.is_inside_tree():
		return null
	var s := _sprite(IMPACT_SHEET, fps, size)
	s.name = "SlashImpact"
	# A world-space effect, so it faces the player from wherever they hit it.
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Binary-ish alpha, so discarding beats blending here: it lets the burst
	# depth-sort against geometry and against the blood sharing this position.
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.render_priority = 4
	host.add_child(s)
	s.global_position = at + toward.normalized() * 0.06
	s.rotation.z = randf_range(0.0, TAU)
	_start(s)
	return s


## One AnimatedSprite3D over one sheet. Unshaded on purpose - a slash is emitted
## light, and letting the level's lighting dim it in a dark corridor is exactly
## where it is needed most.
static func _sprite(sheet: Texture2D, fps: float, size: float) -> AnimatedSprite3D:
	var s := AnimatedSprite3D.new()
	s.sprite_frames = _frames(sheet, fps)
	s.pixel_size = size
	s.shaded = false
	s.double_sided = true
	# Pixel art: the default linear filter smears a 128px cell blown up to most
	# of the screen into mush.
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return s


static func _frames(sheet: Texture2D, fps: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.set_animation_speed(&"default", fps)
	# Looping would also mean animation_finished never fires and the sprite
	# never frees itself.
	sf.set_animation_loop(&"default", false)
	for i in FRAMES:
		var cell := AtlasTexture.new()
		cell.atlas = sheet
		cell.region = Rect2(float((i % COLS) * CELL), float((i / COLS) * CELL),
			float(CELL), float(CELL))
		sf.add_frame(&"default", cell)
	return sf


static func _start(s: AnimatedSprite3D) -> void:
	s.animation_finished.connect(s.queue_free)
	s.play()
	# Belt and braces: animation_finished does not fire while the tree is
	# paused, and a sprite that outlives its swing is a stuck decal on screen.
	var life := float(FRAMES) / maxf(1.0, s.sprite_frames.get_animation_speed(&"default"))
	var timer := s.get_tree().create_timer(life + 0.5)
	# s.queue_free rather than a lambda that captures s: the normal path frees
	# the sprite first, and a lambda's captured reference then dangles and
	# errors when the timer catches up. A connection to a method of a freed
	# object is dropped with the object.
	timer.timeout.connect(s.queue_free)
