extends CanvasLayer

## The opening cutscene: a thing in the corridor tells you how this usually ends.
##
## Runs once, at level start, before the player has control. The creature rises
## out of the dark, delivers its lines a character at a time, and sinks away
## again; then the player gets the level back.
##
## Built in code by tools/build_corridors.gd, like everything else in that level -
## there is no .tscn. The builder places the model and points `creature_path` at
## it; every other node here is made in _ready().
##
## **Control is taken by turning the player's input handlers off, not by adding a
## paused flag to player.gd.** Freezing is exactly "stop reading input", and
## player.gd and arms.gd already keep all of theirs in _physics_process /
## _unhandled_input / _process. Nothing in either script knows this exists.

signal finished

## What it says, in order. Kept as an export so the lines are data.
@export var lines: PackedStringArray = [
	"Many have walked this hall before you.",
	"Brave ones. Armoured ones. Ones who had names.",
	"Not one of them found the way out.",
	"But you...",
	"There is something different about you. I can smell it.",
	"Go on, then. Let us see how far different gets you.",
]
@export var speaker: String = "THE WARDEN"
@export var creature_path: NodePath
## Typing speed. The font is a 16px pixel face, so this reads as a teletype
## rather than as smooth animation, which is the point.
@export var chars_per_second: float = 42.0
## Beat before it begins, so the level fades up before anything speaks.
@export var start_delay: float = 0.8
## How long the creature takes to rise at the start and sink at the end.
@export var rise_time: float = 1.1
@export var rise_from: float = -2.2

const FONT := "res://assets/fonts/m5x7.ttf"
## FBX import drops texture links, so this is re-bound at load like the dungeon
## kit's atlases are. It happens HERE rather than in the builder because the mesh
## is a node inside an instanced scene, and pack() silently drops property
## overrides on those - the material would not be in the saved file.
const CREATURE_TEX := "res://assets/creature/Material_Base_color.png"
## m5x7 is authored at 16 px. Integer multiples stay pixel-crisp; 34 or 40 do not.
const SIZE_BODY := 48
const SIZE_NAME := 32
const SIZE_HINT := 32
## Panel height. Enough for the three lines above at their sizes plus the
## margins; a body line wraps to two rows at this width and has to fit.
const PANEL_H := 232

const CREAM := Color(0.94, 0.90, 0.80)
const SICKLY := Color(0.62, 0.82, 0.55)
const DIM := Color(0.62, 0.60, 0.55)

var _creature: Node3D
var _light: OmniLight3D
var _body: Label
var _name: Label
var _hint: Label
var _panel: Control

var _i: int = -1
var _typed: float = 0.0
var _age: float = 0.0
var _started: bool = false
var _done: bool = false
var _frozen: Array[Node] = []
var _creature_home: float = 0.0

func _ready() -> void:
	layer = 10
	_creature = get_node_or_null(creature_path) as Node3D
	if _creature:
		_creature_home = _creature.position.y
		_creature.position.y = _creature_home + rise_from
		_creature.visible = false
		_light = _creature.get_node_or_null(^"Lamp") as OmniLight3D
		if _light:
			_light.light_energy = 0.0
		_bind_texture()
	_build_ui()
	_freeze(true)
	set_process(true)

func _bind_texture() -> void:
	if not ResourceLoader.exists(CREATURE_TEX):
		return
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(CREATURE_TEX)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for n in _creature.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = m

# --- ui ---------------------------------------------------------------------

## Built here rather than in the builder: it is all Control nodes with no level
## data in them, and a .tscn for it would be one more thing to keep in step.
func _build_ui() -> void:
	var font := load(FONT) as Font

	var root := Control.new()
	root.name = "Frame"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = Control.new()
	_panel.name = "Box"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_top = -float(PANEL_H)
	_panel.offset_bottom = 0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.02, 0.02, 0.03, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bg)

	# A single lit rule along the top edge. Without it the panel has no edge at
	# all against a dark corridor and the text looks like it is floating.
	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(0.45, 0.58, 0.42, 0.55)
	rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rule.offset_bottom = 2
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(rule)

	var pad := MarginContainer.new()
	pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 64)
	pad.add_theme_constant_override("margin_right", 64)
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 20)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(col)

	_name = _label(font, SIZE_NAME, SICKLY)
	_name.text = speaker
	col.add_child(_name)

	_body = _label(font, SIZE_BODY, CREAM)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	_hint = _label(font, SIZE_HINT, DIM)
	_hint.text = "[E]"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.visible = false
	col.add_child(_hint)

	_panel.modulate.a = 0.0

func _label(font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# A hard drop shadow, the way the font's own era did it - the panel is
	# translucent and the corridor behind it is not a flat colour.
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# --- the scene itself -------------------------------------------------------

func _process(delta: float) -> void:
	_age += delta
	if _done:
		return
	if not _started:
		if _age < start_delay:
			return
		_started = true
		if _creature:
			_creature.visible = true
		_advance()
	_rise(delta)
	if _i < 0 or _i >= lines.size():
		return
	# The typewriter. visible_characters is the whole effect - the text is laid
	# out once, so a word never re-wraps as it is revealed.
	var full := _body.text.length()
	if _typed < float(full):
		_typed = minf(float(full), _typed + chars_per_second * delta)
		_body.visible_characters = int(_typed)
		if _typed >= float(full):
			_hint.visible = true
	# Blink the prompt rather than leaving it lit, so a finished line reads as
	# waiting for you rather than as stuck.
	if _hint.visible:
		_hint.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_age * 6.0))

## Rise on entry, bob while talking, sink on the way out. All in code: the model
## is a static mesh with no rig and no animations of its own.
func _rise(delta: float) -> void:
	if _creature == null:
		return
	var k: float = clampf((_age - start_delay) / maxf(0.01, rise_time), 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - k, 3.0)
	var bob: float = sin(_age * 1.3) * 0.05 * k
	_creature.position.y = _creature_home + rise_from * (1.0 - eased) + bob
	_creature.rotation.y += sin(_age * 0.7) * 0.06 * delta
	if _light:
		_light.light_energy = lerpf(_light.light_energy, 2.6 * k, minf(1.0, delta * 4.0))
	_panel.modulate.a = eased

func _unhandled_input(event: InputEvent) -> void:
	if _done or not _started:
		return
	if not _pressed(event):
		return
	get_viewport().set_input_as_handled()
	var full := _body.text.length()
	if _typed < float(full):
		# Impatience finishes the line rather than skipping it - the usual
		# contract, and it stops a fast reader losing text they never saw.
		_typed = float(full)
		_body.visible_characters = -1
		_hint.visible = true
		return
	_advance()

## E, space, enter or a click. The rest of the game reads a raw mouse button and
## has no InputMap actions, so this does the same.
func _pressed(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		return (event as InputEventKey).keycode in [KEY_E, KEY_SPACE, KEY_ENTER]
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	return false

func _advance() -> void:
	_i += 1
	if _i >= lines.size():
		_finish()
		return
	_body.text = lines[_i]
	_body.visible_characters = 0
	_typed = 0.0
	_hint.visible = false

func _finish() -> void:
	_done = true
	_hint.visible = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_panel, "modulate:a", 0.0, 0.45)
	if _creature:
		tw.tween_property(_creature, "position:y",
			_creature_home + rise_from, rise_time * 0.8)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if _light:
		tw.tween_property(_light, "light_energy", 0.0, rise_time * 0.6)
	tw.chain().tween_callback(_release)

func _release() -> void:
	if _creature:
		_creature.visible = false
	_freeze(false)
	finished.emit()
	set_process(false)

# --- taking and giving back control -----------------------------------------

## Turn off the handlers that read input, and remember exactly which ones were
## on so giving control back cannot enable something that was off to begin with.
##
## Restoring is deferred by a frame: the click or keypress that dismissed the
## last line is still being processed, and arms.gd would take a re-enabled
## handler as a swing the moment the panel disappeared.
func _freeze(on: bool) -> void:
	if on:
		var player := get_tree().get_first_node_in_group("player")
		if player:
			_grab(player)
			var arms := player.find_child("Arms", true, false)
			if arms:
				_grab(arms)
		# The crosshair has nothing to aim at yet and sits in the middle of the
		# creature's face.
		for h in get_tree().get_nodes_in_group("hud"):
			if h is CanvasItem:
				(h as CanvasItem).visible = false
		return
	await get_tree().process_frame
	for n in _frozen:
		if is_instance_valid(n):
			n.set_physics_process(true)
			n.set_process(true)
			n.set_process_unhandled_input(true)
	_frozen.clear()
	for h in get_tree().get_nodes_in_group("hud"):
		if h is CanvasItem:
			(h as CanvasItem).visible = true

func _grab(n: Node) -> void:
	_frozen.append(n)
	n.set_physics_process(false)
	n.set_process(false)
	n.set_process_unhandled_input(false)
