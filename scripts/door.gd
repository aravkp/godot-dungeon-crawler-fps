extends "res://scripts/breakable.gd"

## A corridor gate's leaf: everything breakable.gd is, plus it can be OPENED.
##
## Press E and it lifts straight up out of the frame, portcullis style, and the
## corridor is clear. Smashing it still works and still leaves a pile - opening
## is an alternative to that, not a replacement for it, so a gate is a choice
## rather than a wall with a fixed cost.
##
## It extends breakable.gd rather than living inside it. A crate has no business
## carrying door code, and the two now genuinely differ: this one answers the
## interaction contract as well as the damage one.
##
##   interact(by) -> bool   lifts it, once
##   prompt() -> String     "" once open, so a raised door stops advertising
##
## That is the whole registration - player.gd casts its ray at whatever the
## crosshair is on and calls these if they exist.

signal opened

## How far it rises. The leaf and the opening are both 3 m, so it has to travel
## its own height for the doorway to come fully clear; anything less leaves a
## lintel of door hanging in the top of the gap. It ends up above the 4 m ceiling
## slab, which is where a portcullis is supposed to go and which nothing can see
## from inside a corridor.
@export var lift: float = 3.0
@export var lift_time: float = 0.9
@export var open_prompt: String = "Open"

var _open: bool = false

func _ready() -> void:
	super()
	add_to_group("interactable", true)

func prompt() -> String:
	return "" if _open else open_prompt

## Driven by a Tween rather than _process. breakable.gd already owns _process for
## its hit jolt and turns it off the moment the jolt settles, so a rise sharing
## that would stop halfway through.
func interact(_by: Node = null) -> bool:
	if _open or _dead:
		return false
	_open = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position:y", position.y + lift, lift_time)
	opened.emit()
	return true

func is_open() -> bool:
	return _open
