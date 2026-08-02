extends Control

## Screen-centre crosshair plus the interaction prompt, and - for anything that
## offers them - the focused object's name and one-line description. Looking at
## a floating pickup therefore reads as an item card:
##
##       Lvl 1 Dagger
##     Right arm - melee
##        [E] Take
##
## The crosshair is drawn rather than a texture so it can carry a dark outline
## under a light core. This level runs a near-white sky against near-black
## ground, and a plain white cross vanishes against the pumpkin sunset.
##
## It marks the true aim point: arms.gd casts both the melee swing and the
## finger-gun bolt from the camera origin along -Z, which is exactly the centre
## of the screen. player.gd casts its interaction ray the same way.

@export var arm_length: float = 9.0
@export var gap: float = 5.0
@export var thickness: float = 2.0
@export var dot_radius: float = 1.25
@export var color: Color = Color(1, 1, 1, 0.9)
@export var outline: Color = Color(0, 0, 0, 0.55)
@export var prompt_offset: float = 46.0
@export var title_color: Color = Color(1, 0.86, 0.42)
@export var subtitle_color: Color = Color(0.78, 0.78, 0.82)
@export var prompt_color: Color = Color(1, 0.94, 0.75)

var _prompt: String = ""
var _title: String = ""
var _subtitle: String = ""

func _ready() -> void:
	# Full-rect and never eat clicks - the mouse is captured for looking.
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("hud", true)

## Called by player.gd every frame with "" when nothing is in reach.
func set_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	queue_redraw()

## The focused object's name and description, drawn above the prompt. Both "" for
## things that offer no info - a plain chest just gets its [E] line.
func set_focus_info(item_title: String, item_subtitle: String) -> void:
	if item_title == _title and item_subtitle == _subtitle:
		return
	_title = item_title
	_subtitle = item_subtitle
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	# Outline first, then the core on top, so every arm gets a dark edge.
	for pass_i in range(2):
		var col := outline if pass_i == 0 else color
		var t := thickness + (2.0 if pass_i == 0 else 0.0)
		for d in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + arm_length), col, t)
		if dot_radius > 0.0:
			draw_circle(c, dot_radius + (1.0 if pass_i == 0 else 0.0), col)

	# Name, description, action - each optional, stacked under the crosshair.
	var lines: Array = []
	if _title != "":
		lines.append([_title, 22, title_color])
	if _subtitle != "":
		lines.append([_subtitle, 14, subtitle_color])
	if _prompt != "":
		lines.append([_prompt, 18, prompt_color])
	if lines.is_empty():
		return

	var font := ThemeDB.fallback_font
	var y := c.y + prompt_offset
	for line: Array in lines:
		var text: String = line[0]
		var fs: int = line[1]
		var col: Color = line[2]
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(c.x - w * 0.5, y)
		# Drop shadow: the arena runs a bright sunset behind the crosshair and
		# plain text on its own washes out against it.
		font.draw_string(get_canvas_item(), at + Vector2(1, 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.7))
		font.draw_string(get_canvas_item(), at, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += float(fs) + 6.0
