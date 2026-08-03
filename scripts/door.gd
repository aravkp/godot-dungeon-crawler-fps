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

@export_group("Jammed")
## A JAMMED gate is stuck partway up and cannot be lifted the rest of the way.
## The gap it leaves is the point: too low to walk under, high enough to CROUCH
## under, so the third way past a gate is to go under it rather than through it.
##
## This costs no new art and no trigger volume. The leaf really is raised and its
## collider really is up there with it, so the only thing deciding whether you
## fit is the size of the player capsule - which is exactly what Shift changes.
##
## **The LEAF IS RAISED BY WHOEVER PLACES IT, not here.** `_ready()` runs inside
## `add_child()`, and every builder in this project sets `position` on the line
## *after* that - so a lift applied here is overwritten a moment later and the
## gate silently sits closed. The builder owns the geometry, this script owns the
## refusal to lift. `jam_gap` is the number they agree on.
@export var jammed: bool = false
## How much of a gap is left underneath, in metres. Wants to sit between the
## crouched capsule (1.15) and the standing one (2.0), and not so near either
## that the player has to fight it. 1.35 leaves real clearance both ways.
@export var jam_gap: float = 1.35
@export var jammed_prompt: String = "Jammed - too heavy to lift"

var _open: bool = false

func _ready() -> void:
	super()
	add_to_group("interactable", true)

## A jammed gate still answers the contract, and deliberately says so rather than
## going quiet: a door that offers nothing reads as scenery, and the player needs
## to understand that ducking or smashing are the options.
func prompt() -> String:
	if jammed:
		return "" if _dead else jammed_prompt
	return "" if _open else open_prompt

## Driven by a Tween rather than _process. breakable.gd already owns _process for
## its hit jolt and turns it off the moment the jolt settles, so a rise sharing
## that would stop halfway through.
func interact(_by: Node = null) -> bool:
	if _open or _dead or jammed:
		return false
	_open = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "position:y", position.y + lift, lift_time)
	opened.emit()
	return true

func is_open() -> bool:
	return _open

## True for a gate you have to duck under or break, rather than one you can lift.
func is_jammed() -> bool:
	return jammed and not _dead
