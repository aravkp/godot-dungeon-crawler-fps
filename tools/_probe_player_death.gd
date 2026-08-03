extends SceneTree

## Throwaway probe: can a watcher actually kill you, and do you come back?
##
##   Godot --headless --path . -s tools/_probe_player_death.gd
##
## Exits non-zero on any failure, so it is an assertion rather than a report.
##
## It drives the WHOLE chain rather than calling player.take_hit() directly:
## a watcher is walked into the player, alerts on its own, chases, commits a
## swing, and _land_hit() is what deals the blow. Calling take_hit() by hand
## would pass just as happily with the mace never connecting to anything - which
## is exactly the state this project was in before, since the call site existed
## and the method it called did not.
##
## Headless is fine here: nothing under test needs a display server, and the only
## input involved is the input NOT being read while dead. Physics frames are the
## clock, since a headless run is uncapped.

const SCENE := "res://scenes/main.tscn"
const HZ := 60.0
## Generous: the watcher has to notice, close, turn, and get 1.0 s into a swing.
const KILL_TIMEOUT := 12.0

var _fails: int = 0

func _init() -> void:
	var scene := (load(SCENE) as PackedScene).instantiate()
	get_root().add_child(scene)
	# Group membership is not queryable on the frame the scene enters the tree -
	# every lookup below comes back null without this.
	await physics_frame

	var player: Node = get_first_node_in_group("player")
	var watcher: Node = get_first_node_in_group("watchers")
	var hud: Node = get_first_node_in_group("hud")
	var arms: Node = get_first_node_in_group("viewmodel")
	if player == null or watcher == null:
		print("no player or no watcher in ", SCENE)
		quit(1)
		return

	# The horde is not the subject and its bats shove things around.
	var spawner := scene.get_node_or_null("BatSpawner")
	if spawner:
		spawner.set("enabled", false)

	var spawn: Vector3 = player.global_position
	# Stand one watcher just inside its own alert radius, facing the player, so
	# the run is about the swing rather than about pathing 30 m of arena.
	var at: Vector3 = spawn + Vector3(0, 0, 4.0)
	watcher.global_position = Vector3(at.x, spawn.y, at.z)
	for _i in range(10):
		await physics_frame

	print("player spawn %.2v   watcher at %.2v" % [spawn, watcher.global_position])
	_check("player answers take_hit", player.has_method("take_hit"))
	_check("player starts alive", not bool(player.call("is_dead")))

	var eye_before: float = player.get_node("Head").position.y
	var t := 0.0
	var alerted := false
	while t < KILL_TIMEOUT and not bool(player.call("is_dead")):
		await physics_frame
		t += 1.0 / HZ
		if not alerted and bool(watcher.call("is_alerted")):
			alerted = true
			print("  alerted at t=%.2fs, %.2f m away"
				% [t, player.global_position.distance_to(watcher.global_position)])

	_check("the mace killed the player", bool(player.call("is_dead")))
	print("died at t=%.2fs" % t)
	if not bool(player.call("is_dead")):
		_report()
		return

	# A second blow must not land - one hit is already fatal, and a watcher gets
	# more swings off before the respawn.
	_check("a dead player refuses further hits",
		not bool(player.call("take_hit", 1, Vector3.INF, Vector3.FORWARD)))

	# Walk the killer off before the respawn is measured. The spawn point is
	# where the player comes back, the watcher was parked next to it, and it is
	# still alerted - so it simply kills them again about a second in, and every
	# check below reads as a failed respawn when what actually happened is a
	# second successful kill. (It is also real behaviour, not a probe artifact:
	# respawning inside an alerted camp is fatal.)
	watcher.global_position += Vector3(0, 0, 60.0)

	# Let the camera finish going down.
	for _i in range(45):
		await physics_frame
	var head: Node3D = player.get_node("Head")
	var eye_after: float = head.position.y
	print("eye %.3f -> %.3f   roll %.1f deg"
		% [eye_before, eye_after, rad_to_deg(head.rotation.z)])
	_check("the view dropped to the floor", eye_after < eye_before - 0.8)
	_check("the view rolled over", absf(head.rotation.z) > 0.5)
	_check("the viewmodel stopped taking input", not arms.is_processing())
	_check("the HUD went to its death state", bool(hud.get("_dead")))

	var delay: float = float(player.get("respawn_delay"))
	var wait := int((delay + 0.6) * HZ)
	for _i in range(wait):
		await physics_frame
	print("after respawn: alive=%s  at %.2v (spawn %.2v)  eye %.3f  roll %.1f deg"
		% [not bool(player.call("is_dead")), player.global_position, spawn,
			head.position.y, rad_to_deg(head.rotation.z)])
	_check("control comes back", not bool(player.call("is_dead")))
	_check("respawned at the spawn point",
		Vector2(player.global_position.x - spawn.x,
			player.global_position.z - spawn.z).length() < 0.5)
	_check("the view came back up", absf(head.position.y - eye_before) < 0.01)
	_check("the roll cleared", absf(head.rotation.z) < 0.01)
	_check("the viewmodel took its input back", arms.is_processing())
	_check("the HUD cleared", not bool(hud.get("_dead")))

	await _check_dodgeable(player, watcher)
	_report()

## The other half of "the mace does damage": that it can also MISS. _land_hit()
## tests its reach at the moment of impact rather than when the swing started,
## which is the whole reason a committed 1.6 s swing is fair - so back out of one
## mid-windup and it has to come down on nothing.
func _check_dodgeable(player: Node, watcher: Node) -> void:
	watcher.global_position = player.global_position + Vector3(0, -0.37, 3.2)
	# State.ATTACK is 2 in {GUARD, CHASE, ATTACK, HURT, DEAD}.
	var t := 0.0
	while t < KILL_TIMEOUT and int(watcher.get("_state")) != 2:
		await physics_frame
		t += 1.0 / HZ
	if int(watcher.get("_state")) != 2:
		_check("watcher committed a second swing to dodge", false)
		return
	print("swing committed at t=%.2fs - stepping out of it" % t)
	# Out of attack_reach (3.0 m) but not so far the watcher can close again
	# before the swing lands.
	player.global_position += Vector3(0, 0, -9.0)
	for _i in range(int(1.2 * HZ)):
		await physics_frame
	_check("a swing stepped out of misses", not bool(player.call("is_dead")))

func _check(what: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])

func _report() -> void:
	print("\n%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
