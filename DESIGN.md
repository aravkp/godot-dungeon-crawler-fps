# godot-dungeon-crawler-fps — design and internals

A first-person action prototype in **Godot 4.7.1**. Player with a rigged
first-person arms viewmodel, a single looted weapon, parkour movement (wall
running), and a Vampire-Survivors style enemy horde, in a Halloween-dusk arena —
dark cracked rock underfoot, pale block obstacles, a pumpkin-mountain sunset sky.

**You start with two empty fists, and there is one attack on one button.** Left
click swings; hold it and it keeps swinging. The *Lvl 1 Dagger* is chest loot —
opening a loaded chest floats a `pickup.gd` item out of it, and a second `E`
takes it — and taking it only changes what the swing is. There are no stance
keys, no second weapon and no ranged attack.

## Running

Godot lives at `/Applications/Godot-1.app` (4.7.1). It is **not** on `PATH`.

```bash
GODOT=/Applications/Godot-1.app/Contents/MacOS/Godot

"$GODOT" --editor --path .          # open the editor
"$GODOT" --path .                   # run the game (F5 in editor)
"$GODOT" --headless --path . -s tools/<script>.gd    # run a tool script
```

`--headless` game runs never exit on their own — background them and kill after
a fixed time, or they hang.

Main scene is `res://scenes/main.tscn`. Physics engine is **Jolt**.

### Editor plugin

`addons/godot_mcp/` is enabled in `project.godot`. It opens a TCP server on
**localhost:6400** while the editor is open, driven by an external MCP server
outside this repo. It is a development convenience, not part of the game. It
must not be relied on by game code.

## Controls

| Input | Action |
|---|---|
| WASD / arrows | move |
| Shift | sprint |
| Space | jump; while wall running, kick off the wall |
| Mouse | look |
| Left click | attack — alternating jabs, or the dagger once looted. **Hold to keep swinging.** |
| E | interact — opens the chest the crosshair is on, lifts the gate, or takes the pickup |
| Escape | release mouse (click to recapture) |

Wall running engages automatically: be airborne, moving above
`wall_run_min_speed`, and alongside a near-vertical surface.

## Scenes

| Scene | What it is |
|---|---|
| `scenes/main.tscn` | The Halloween-dusk arena. **The main scene.** Written by `build_terrain.gd` (or `build_dungeon.gd`). |
| `scenes/corridors.tscn` | Post Void style corridor shooter, and the only level with a cutscene, destructibles and doors. Written by `build_corridors.gd`. A separate level — run it with `"$GODOT" --path . scenes/corridors.tscn`. |
| `scenes/bat.tscn`, `scenes/watcher.tscn`, `scenes/chest.tscn` | Instanced pieces, each with its own generator in `tools/`. |

## Scene structure — `scenes/main.tscn`

```
main (Node)
├─ WorldEnvironment          sky, filmic tonemap, sky-sourced ambient
├─ Player (CharacterBody3D)  group "player" → player.gd
│  ├─ PlayerMesh             capsule, cast_shadow = SHADOWS_ONLY
│  ├─ PlayerCollision        CapsuleShape3D r=0.5 h=2
│  └─ Head (Node3D)          y=0.7, pitch + wall-run roll pivot
│     └─ Camera3D
│        ├─ ViewModel        bob/sway pivot, neutral at origin
│        │  └─ Arms          instance of assets/hands/arms_rig.glb → arms.gd
│        └─ DaggerMount (BoneAttachment3D)
│           └─ Dagger        blade / guard / pommel / grip MeshInstance3D
├─ Terrain (Node3D)
│  ├─ Ground (StaticBody3D)  120×120 m box, top face at y=0
│  └─ Obstacles              52 × Obs_NN (StaticBody3D + Mesh + Collision)
├─ Sun (DirectionalLight3D)  shadows on
└─ BatSpawner (Node3D)       → bat_spawner.gd
```

`scenes/bat.tscn` — the horde enemy the spawner clones:

```
Bat (CharacterBody3D)   group "enemies" → bat_enemy.gd, MOTION_MODE_FLOATING
├─ Model                instance of assets/chonchon/chonchon.fbx
└─ Collision            SphereShape3D r=0.38
```

### Important node relationships

- **`DaggerMount` is a sibling of `Arms`, not a child of the skeleton.** It uses
  `BoneAttachment3D.use_external_skeleton` with
  `external_skeleton = "../Arms/ArmsRig/Skeleton3D"` and `bone_name = "hand.R"`.
  See "pack() drops things" below for why.
- Player is in group **`player`**. Every enemy is in **`enemies`**; bats are
  *also* in **`bats`** and watchers *also* in **`watchers`**. The spawner caps on
  **`bats`**, not `enemies` — hand-placed watchers would otherwise eat the
  horde budget. The bat AI finds its target with
  `get_first_node_in_group("player")`.
- Watcher trios live under `Camps/Camp_NN`. **That parent node is the squad** —
  see `watcher_enemy.gd`.

## Scripts — `scripts/`

### `player.gd` (CharacterBody3D)
First-person controller. Custom gravity, **not** the project default:
`rise_gravity = 26.0`, `fall_gravity = 34.0`, `jump_velocity = 10.5` → measured
apex **2.21 m**. Coyote time 0.12 s. Air acceleration is deliberately lower than
ground (30 vs 75).

Wall running: raycasts each side (`wall_check_distance = 0.85` from body centre)
for a surface with `|normal.y| < 0.3`. Requires `wall_run_min_speed` horizontal
speed. While attached, it drives velocity along the wall tangent in the facing
direction, sinks slowly instead of falling, rolls the camera
`wall_run_tilt_degrees`, and times out after `wall_run_max_time`. Jump kicks off
along the wall normal. `wall_reattach_delay` prevents instant re-grip.

Public: `is_wall_running() -> bool`.

Speeds: walk 8.5, sprint 13.5.

### `arms.gd` (Node3D, on the `Arms` instance)
Viewmodel. **One attack, on one button, and holding it repeats.**

Left click swings and `attack_button` is the whole binding — nothing else in the
project reads a mouse button and there are no InputMap actions. What the swing
*is* depends only on what has been picked up:

| state | clips |
|---|---|
| bare hands | `jab_L` / `jab_R`, alternating |
| dagger | `knife_hit_01` / `knife_hit_02`, alternating |

**Alternating is what makes a held button read as a combo** rather than as one
arm pumping, and it is free — the pack ships both sides of each.

**Both hands start empty.** `has_dagger` defaults `false`, so the opening idle is
`guard_idle` (bare fists) and `DaggerMount` is hidden. A level can set it `true`
to start armed.

- `attack() -> bool` — swings whatever is in hand and advances the alternation.
  Returns false while a swing is already playing, which is what `_busy` enforces:
  one swing per animation.
- `unlock_dagger() -> bool` — granted by a chest pickup; idempotent. Reveals
  `DaggerMount`, swaps the idle to `knife_idle` — **the pose the mount was fitted
  against**, so the grip is right from the first frame — and resets the
  alternation so looting mid-combo cannot open on the second swing. Emits
  `dagger_unlocked`.
- `swing() -> Object` — short raycast (`melee_range = 2.4`) from the camera;
  calls `take_hit` on anything that has it. Fires at the *start* of the clip.

`_idle()` picks between the two idles; `_on_animation_finished` compares against
it rather than a fixed `idle_anim`, or looting the dagger mid-swing re-queues the
stale fists idle. Once looted the dagger stays visible — it is never sheathed.

**A held button chains, it does not re-enter through the idle.** The obvious
implementation — let the swing end, fall back to the idle, and have `_process`
start the next one next frame — blends the idle in for a frame between every pair
of punches, which at this cadence reads as a stutter. So `_on_animation_finished`
checks the trigger and goes straight into the next swing, and only plays the idle
when the button is actually up. `_process` is then just what picks up a button
that was *already* down, since the press event only fires once.

**`attack_speed` is what makes a punch read as a punch.** The clip's own length
paces a held attack, because the next swing starts when the last one ends, and
the jabs are authored at a full **1.0 s** (the knife hits at 0.70 / 0.73 s) —
sustaining at about one punch a second, which is too slow to read as punching. At
**1.6** a jab lands in 0.63 s. Measured with `tools/_probe_hold.gd`, holding the
button for 3 s: **`jab_L, jab_R, jab_L, jab_R`, 1.67 swings/s, zero idle frames
between them.**

**One constraint worth knowing before changing this:** every clip animates BOTH
arms (30 `.L` tracks and 30 `.R` tracks each), so the arms cannot genuinely act
at once — one action plays at a time and `_busy` blocks the next. Real per-arm
layering needs an `AnimationTree` with a bone filter, which this does not use.
With a single attack button that limitation costs nothing; it is why the old
two-weapon, two-button layout never really worked.

**All FBX/glTF animations import with looping off.** `_ready()` sets
`loop_mode = LOOP_LINEAR` on every stance idle. Without that an idle plays once
and freezes.

### `bat_enemy.gd` (CharacterBody3D)
Horde enemy. No pathfinding and no states: it accelerates toward
`player.global_position + Vector3.UP * hover_height`, stops within
`stop_distance`, and turns to face the player (the model's front is **+Z**).

Swarm separation is free — bats are physics bodies, so `move_and_slide()` makes
them shoulder past each other. There is no flocking code and none is needed.

`take_hit(amount, at, from) -> bool` is the damage entry point. Non-fatal hits
play `hurt_animation` and a small blood burst; the killing blow disables
collision, plays `death_animation`, sprays a bigger burst, and frees the node
after the animation length. Emits `died`.

Blood is a one-shot `GPUParticles3D` built in code (the burst lives in
`blood.gd`, shared with the watcher) and **parented to the level, not the
bat**, so the spray outlives the corpse. It frees itself on a timer. `blood.gd`
is used via `preload`, not its `BloodFX` class_name — global class registration
lives in the editor's scan cache, which headless runs never rebuild.

`MOTION_MODE_FLOATING` is required — the default grounded mode tries to snap it
to a floor.

### `watcher_enemy.gd` (CharacterBody3D)
Zelda-hobgoblin style guard — the deliberate opposite of the bat. Hand-placed in
trios around a camp, **3 hits to kill**, grounded, melee.

States: `GUARD → CHASE → ATTACK`, plus `HURT` and `DEAD`. In `GUARD` it stands
still and drifts back to its placed facing, testing a vision cone every
`sight_interval`: `sight_range` 24 m, `sight_angle` 120°, plus an
`alert_radius` of 5 m that ignores facing so you cannot stand behind one
unnoticed. Line of sight is a real raycast — the first thing it hits must be the
player.

**Squad alerting is structural, not a manager.** All three watchers in a trio
are siblings under one `Camp_NN` node, so `alert()` just walks
`get_parent().get_children()`. Placement defines the squad; there is nothing to
keep in sync. Taking a hit also alerts the squad, so shooting one from behind
wakes all three.

**A swing is committed to, so the gate on starting one is more than distance.**
`_can_strike()` requires all three of: inside `attack_range` (2.3 m), the player
inside `attack_aim_angle` (60° total) of facing, and line of sight. The swing
takes ~1.6 s and `_land_hit` only connects inside `attack_reach` (3.0 m) and 70°
of facing, so a swing started while still turning, or through a pillar, is one
that can never land — it just reads as flailing.

`take_hit(amount, at, from) -> bool` matches the bat's contract, blood
included: the same `blood.gd` burst, small when hurt and double on the kill,
parented to the camp node so it outlives the corpse. The impact-point fallback
is chest height (+1.2 m) because unlike the bat the origin sits at the feet.
`from` is a normalised world direction at every call site (`arms.gd` passes the
camera axis), which is what makes it usable as a ragdoll impulse.

**Death is a ragdoll, not the baked death clip** (`use_ragdoll`, on by default;
turn it off to fall back to `CLIP_DEATH`). `scripts/ragdoll.gd` builds eleven
physical bones on the spot, and the killing blow's `from` direction is applied
as an impulse to whichever bone was nearest the impact. Then:

- `collision_layer` is cleared but **the shapes are not disabled**. Disabling
  them stops the corpse seeing the floor, so `is_on_floor()` never returns true
  again and the dead branch's gravity drops it through the world — measured at
  **-106 m in 3 seconds**. Emptying the layer keeps the mask.
- The CharacterBody stops moving entirely once a ragdoll exists. Physical bones
  write bone poses in world space, so moving their ancestor only makes the
  skeleton compensate — the corpse would not visibly budge.
- It lies for `ragdoll_settle` + `corpse_linger`, then **sinks by having its
  collision mask cleared** and falling at `corpse_sink_gravity`, rather than by
  the hand-translation the animated corpse uses. Same reason either way: a body
  still colliding with the ground cannot be pushed into it. Freeing on a timer
  instead blinked it out mid-frame.

**The mace swing calls `take_hit` on the player, which currently does nothing** —
there is no player health system. The call is the contract for when there is one.

### `ragdoll.gd`
Shared runtime ragdoll, used via `preload` like `blood.gd` and for the same
reason (class registration lives in the editor's scan cache, which headless runs
never rebuild). `build()` → `start()` → `sink()`.

**Built at runtime, not baked into `watcher.tscn`.** The `Skeleton3D` is inside
an instanced scene, and `pack()` drops new children added inside an instance —
so a `PhysicalBoneSimulator3D` written by a tool script would silently not be in
the saved file, with `ResourceSaver` still returning OK. Building in code
sidesteps that and costs nothing until something dies.

`CHAIN` is **eleven** bodies — pelvis, torso, head, two arm segments and two leg
segments a side. Fingers and toes add solver cost and jitter for detail nobody
sees on a corpse. Bones are matched by **suffix**, so `mixamorig_LeftArm` and a
bare `LeftArm` both resolve and a rig missing an entry just skips it. Joints are
cone twist; spans are per-entry.

**`ignore()` is not optional here.** The bodies sit on collision *layer* 0 so
nothing targets them, but their *mask* still sees layer 1 — and this project has
no layer convention, so the ground, the player and every enemy share layer 1.
Anything that walks over a corpse therefore shoves it. Killing a watcher alerts
its squad and the siblings charge straight across the body: a Camp_00 corpse slid
a measured **3.9 m** before the exceptions went in. Excluding actors one by one
is what avoids a project-wide layer split. Bodies created *after* the call are
not covered — a bat spawned beside a fresh corpse can still nudge it, which has
not been worth chasing given corpses last about four seconds.

See "PhysicalBone3D inverts the skeleton's scale" below before touching the
transforms.

### `chest.gd` (StaticBody3D)
The treasure the watchers guard, and **where the whole loadout comes from**. Set
`loot` to an item id from `pickup.gd`'s `ITEMS` (`"dagger"` is the only one
left, or `""` for an empty chest) and opening it floats that pickup out at
`loot_offset`. The chest grants nothing itself — it does not need to know what
the item does. `loot_offset.y` is **1.35**: the chest is 0.947 m tall and the lid
swings up and back over that, so anything at chest-top height is hidden behind
the open lid. The FBX ships its own lid animation
(`Take 001`, 3.33 s, one track on `chest_top`), so opening is just playing it.
Held shut on frame 0 at `_ready()` — without that the lid sits wherever the
importer left it. Re-binds the PBR set (BaseColor / Normal / Roughness /
Metallic) at load onto the shared meshes, meta-guarded, since FBX drops texture
links.

**A chest can also be smashed instead of opened**, but only where a level asks
for it: `destructible` defaults **false** so a stray bolt cannot delete the
outdoor camps' treasure, and `build_corridors.gd` turns it on per chest. It then
answers the same `take_hit(amount, at, from) -> bool` as the enemies and
`breakable.gd`, taking `hits` (4) to break.

**Breaking a chest spills the same pickup opening it would.** Both routes go
through one `_spill()` guarded by `_spilled`, so the loot leaves exactly once and
never twice. This is not a nicety: the dagger *is* chest loot in both levels, so
a destructible chest that took its contents with it could strand the player
bare-fisted for the rest of the run.

### `breakable.gd` (StaticBody3D)
Smashable scenery — the corridor level's crates, barrels and doors. Answers the
same damage contract as the enemies, so `arms.gd`'s melee ray already hits it
with no special case anywhere.

**Everything breakable dies on the first swing that lands.** `hits` defaults to
**1**, and every caller — crates, barrels, doors, the chests — now asks for 1.
The multi-hit path still works and a level can still ask for it, but nothing
does, so the jolt-on-a-non-fatal-hit below is only reachable by setting `hits`
above 1.

**A door is this script plus `door.gd`, and a collider that fills a doorway.**
Blocking a corridor still needs nothing of its own — that is just the box. What
a door has that a crate does not is the `[E]` that lifts it.

Built only by `build_corridors.gd` — there is no `.tscn`. The builder parents the
kit model under `Art`, sizes one `BoxShape3D` from the piece's *measured* bounds,
and puts the yaw on the body rather than on the model, so an unrotated box still
matches what you are aiming at.

`hits` is decremented in place and deliberately **not** copied into a private
field at `_ready()`: the builder sets exported properties on a node it created,
`add_child()` runs `_ready()` immediately, and anything cached there would be
captured before the override lands — the same trap `pickup.gd` hits with its bob
origin. A non-fatal hit jolts the **art only**; the collider must not move or a
half-smashed crate stops lining up with the thing you are aiming at.

The killing blow hands its **collider box** to `shatter.gd` and its first mesh
for the colour, so the pile that lands matches the shape that was standing there.
The same is true of `chest.gd`, which finds its box by *type* rather than by name
— `build_chest_scene.gd` measures that collider rather than naming it.

### `door.gd` (extends `breakable.gd`)
A gate's leaf. Everything a breakable is, **plus `[E]` lifts it straight up out
of the frame, portcullis style.** Smashing it still works, so a gate is a choice
between one swing and one press rather than a wall with a fixed cost — which is
also why `DOOR_HITS` is 1 now: with a smash costing three swings the choice was a
formality.

It extends `breakable.gd` rather than living inside it. A crate has no business
carrying door code, and the two now genuinely differ: this one answers the
interaction contract as well as the damage one, via `interact(by)` and
`prompt()`. That is the whole registration — see "The interaction contract".

- **`lift` is 3.0 m, its own height.** The leaf and the opening are both 3 m, so
  it has to travel its full height or a slab of door hangs in the top of the gap.
  It ends up above the 4 m ceiling slab, which is where a portcullis goes and
  which nothing can see from inside a corridor.
- **The rise is a `Tween`, not `_process`.** `breakable.gd` already owns
  `_process` for its hit jolt and turns it off the moment the jolt settles — a
  rise sharing that would stop halfway up.
- **One-way.** `interact()` returns false once open and `prompt()` returns `""`,
  so a raised door stops advertising itself. There is no closing it.

### `shatter.gd` (Node3D, built in code)
**The pieces a smashed prop falls into.** `debris.gd`'s particle burst sells the
*impact*; this is what sells the thing coming apart. A crate leaves a pile of
boards on the floor for a few seconds, which enemies kick around and the player
walks through.

`burst(host, xform, size, source, dir)` takes the prop's **collider box** and
splits it on a grid: `TARGET_CHUNK` (0.35 m) aims for chunks about that big, and
`MAX_CELLS` (4) caps each axis. So a crate comes apart into 2×2×2 cubes and a
door into a 4×4×1 sheet of planks, with neither told which it is — the box shape
does it. Without the cap a 2 × 3 m door would be 6×9 = 54 bodies.

- **Chunks sit on collision layer 0, mask 1.** They land on the floor and nothing
  targets them — not the melee ray, not the interaction ray, not each other. The
  same split `ragdoll.gd` uses and for the same reason: without it a cloud of
  debris in front of you eats the swing aimed at whatever is behind it.
- **`gravity_scale = 2.5`**, because rigid bodies use the project default (9.8)
  while the game's own fall gravity is 34 — chunks dropping at a third of the
  rate everything else does read as floaty polystyrene.
- They **shrink out** rather than blink out, after `linger` (3 s) + `fade`. Only
  the meshes are scaled; scaling the bodies would drag their collision shapes
  with them and the pile would sag through the floor as it went.

**Chunks carry the prop's own texture.** A crate breaks into pieces of crate
wood and the chest into pieces of chest — wood, and its pale steel banding —
rather than into coloured cubes.

The mechanism is that **a chunk's box is built here with explicit UVs, not
handed the prop's**. `BoxMesh` divides one 0..1 UV square between its six faces,
so giving it the prop's mapping gets each face a sixth of the sheet blown up —
which is exactly why the first attempt at this came out a flat wrong grey and
why the pile was flat-coloured for a while. `_uv_box()` builds the box instead,
giving all six faces the *same* small window of the texture, taken from where
that chunk actually was on the prop: the nearest source triangle's UV centroid.
Three measured things hold it up:

- **The window size is measured, not chosen.** `density` is UV units per metre,
  from the prop's total UV area over its total surface area *in world metres*,
  so a chunk shows the texture at the size the prop showed it at. The crate
  reads **0.625 uv/m**, the ×2-scaled door **0.301** — the same mesh unscaled
  would read double, which is why the cache key carries the node's scale.
- **UV bounds must come from triangle CORNERS, not centroids.** Centroids sit
  well inside their islands, so a centroid bbox understates the region the prop
  uses — measured on the crate, `0.167` against a true `0.500`. The window is
  clamped inside those bounds (the kit's crate atlas is wood over three
  quadrants and solid *black* in the fourth), and with the bounds understated
  the clamp collapsed to the middle and **every chunk got the same texel**.
- **Emission is divided by the square of the prop's luminance** on this path,
  where the flat-colour one divides by luminance once. See below.

The palette below is now the **fallback** for a prop with no texture or no UVs,
and the source of the emission colour on both paths. It is still worth keeping
written down:

1. **Averaging a texture is the wrong operator.** The chest is roughly half brown
   wood and half *blue* steel banding, and the mean of those sits almost exactly
   on grey: measured `(0.21, 0.21, 0.20)` at **saturation 0.06**, so a brown
   chest shattered into grey cubes. Clustering the samples (`COLOR_BINS` per
   channel) and keeping the largest `PALETTE_MAX` gives wood
   `(0.44, 0.30, 0.12)` at **saturation 0.73** as the biggest at 49 %, steel blue
   at 26 %, darker wood at 25 % — so a chest breaks into mostly brown pieces with
   a few steel ones, and chunks are assigned across the palette *by weight*.
2. **Sample at triangle UV centroids, weighted by 3D triangle area** — not on a
   lattice over the UV bounding rectangle. A real unwrap is mostly empty sheet
   between islands (the chest spans `(0.006,0.006)..(0.972,0.996)` of a 2048²
   page), and a lattice samples that black background and drags everything dark.
   A centroid is by construction inside an island. Area weighting stops a hundred
   tiny hinge triangles outvoting the lid.

Palettes are cached per mesh resource, so this runs once for crates however many
get smashed.

**Emission is divided by the prop's own luminance** (`EMISSION_LIFT` over
luminance, capped at `EMISSION_MAX`). Unlit, a pile smashed between two corridor
lamps is near-black lumps you cannot read — the same problem `debris.gd` solves
by going unshaded outright. But a *fixed* energy tuned on the crate's dark wood
(luminance 0.19) badly overdrove the chest's, which is twice as bright, and the
tell was its steel-blue pieces: under a red corridor lamp a blue surface should
go nearly black, and instead they glowed pale blue, because self-lit emission
ignores the colour of the light. There is a ceiling on it too — `corridors.tscn`
runs glow at an HDR threshold of 1.25, and emission at 0.5 sent a whole pile
through it and it came back as a bloomed white blob.

Two things change once the chunk is **textured**, both with their own constants
(`EMISSION_LIFT_TEX` / `EMISSION_MAX_TEX`):

- **The lift stays a flat colour — the prop's dominant one — under a textured
  albedo.** Routing the albedo texture into `emission_texture` with a white
  emission colour instead is what it looks like it should be, and it rendered
  the whole pile as blown-out white blobs that the glow pass then bloomed. That
  is worse than the darkness it was meant to cure.
- **It is divided by the square of the luminance, not the luminance.** Once the
  albedo is the real texel rather than a flat palette colour, how much lift a
  prop needs falls off faster than its own brightness does. Measured, with the
  energies that looked right: crate at luminance **0.196** wants **~0.67**,
  chest at **0.315** wants **~0.26** — a 2.6× spread across a 1.6× luminance
  ratio, which is a square law, and `0.026 / lum²` reproduces both. Tuned
  linearly one end always broke: at the crate's setting the chest came back a
  garish orange, at the chest's the crate stayed a black lump.

### `debris.gd`
The particle burst that accompanies the chunks — the dust of the hit, kept at a
smaller scale now that it is an accent rather than the whole effect. Built as the
deliberate twin of `blood.gd`:
same static `burst()` shape, same "parent it to something that outlives the
corpse" rule, same self-freeing timer, and used via `preload` for the same reason
(class registration lives in the editor's scan cache, which headless runs never
rebuild). Splinters tumble where droplets do not, which is what tells the two
apart in motion rather than in colour. Unshaded, because the corridor level is
pitch dark between its handful of lamps and a shaded chunk spawned off one is
simply invisible.

### `pickup.gd` (StaticBody3D)
A floating item the player takes with `E`, built **in code** via
`pickup.spawn(host, at, item_id)` — there is no `.tscn`, so the item table is the
only thing to edit. `ITEMS` maps an id to its title, subtitle, visual kind and
the viewmodel method it calls, so a new item is one row.

One visual kind, `"mesh"`: it pulls the real weapon out of its FBX, so the dagger
pickup is literally the dagger you end up holding (same flat fallback colours as
`mount_dagger.gd`). Re-centred on its own bounds so it spins about its middle.
There was a second kind, `"icon"` — a NEAREST-filtered billboard `Sprite3D` — for
the blood pistol, an ability with no model of its own. Both went when the pistol
was cut; an item with nothing to show would have to bring it back.

Each carries a small `OmniLight3D`; pickups have to be legible in the sealed
corridor level, which has no key light at all. Kept weak (**0.9 / 1.8 m**) — at
1.6/2.6 the since-cut pistol's red lamp repainted a whole corridor.

**`spawn()` re-seats `_base_y` after positioning.** `add_child` runs `_ready`
immediately, so the bob origin captured there predates the move.

### `hud.gd` (Control, under a CanvasLayer)
Crosshair and interaction prompt, drawn in `_draw` rather than textured so each
arm carries a dark outline — a plain white cross disappears against the pumpkin
sunset. In group `hud`; `player.gd` pushes text via `set_prompt()`, and the
focused object's name and description via `set_focus_info()`. Those stack into an
item card under the crosshair:

```
     Lvl 1 Dagger        <- title(),    22px warm gold
 Melee - hold to swing     <- subtitle(), 14px grey
    [E] Take           <- prompt(),   18px cream
```

### `cutscene.gd` (CanvasLayer, built in code)
**The opening scene of the corridor level.** A thing rises out of the floor one
cell down the corridor, tells you how this usually ends, and sinks away; then the
player gets control. Runs once, at level start.

- **Control is taken by turning the player's input handlers off**, not by adding
  a paused flag to `player.gd`. Freezing here is exactly "stop reading input",
  and both `player.gd` and `arms.gd` keep all of theirs in `_physics_process` /
  `_unhandled_input` / `_process` — so neither script knows this exists. Which
  handlers were on is remembered, so giving control back cannot switch on
  something that was off to begin with.
- **Restoring is deferred by one frame.** The click or keypress that dismissed
  the last line is still being processed, and `arms.gd` takes a re-enabled
  handler as a swing the moment the panel disappears.
- **The typewriter is `visible_characters`**, so the text is laid out once and a
  word never re-wraps as it is revealed. Pressing `[E]` mid-line finishes the
  line rather than skipping it.
- **The creature is animated in code** — rise, bob, sway, sink — because
  `creature.fbx` is a static mesh with no rig and no animations at all.
- **Its texture is bound here, not in the builder.** The mesh is a node *inside*
  an instanced scene and `pack()` silently drops property overrides on those, so
  a material set at build time would not be in the saved file. Same fix as the
  dungeon kit's atlases, same reason.
- Lines, speaker, typing speed and timings are exports, so the script is the
  machinery and the writing is data.

### The corridor level's own rules
Things `corridors.tscn` needs that the outdoor level does not, all handled in
`build_corridors.gd`:
- **A viewmodel light.** Sealed indoors there is no key light, and the arms
  render as a black silhouette. A short-range lamp rides the `Camera3D`. Its
  energy has to be very low (**0.5**) — the hand is ~0.3 m away, so falloff is
  effectively zero and a room-lamp energy blows it to pure white, which the
  glow pass then blooms.
- **`loot` on each chest**, set from the builder so the corridor arms you as you
  go. This is an override on the *root* of an instanced scene, which `pack()`
  keeps — only overrides on nodes *inside* an instanced scene get dropped.
  `arms.gd` exposes `has_dagger` the same way if a level ever wants to open
  already armed. `destructible` rides on the same override.
- **Everything breakable lives here and nowhere else.** Crates, barrels, the
  three chests and every door are `breakable.gd` / `chest.gd` bodies. The outdoor
  arena has no destructibles at all.
- **A lamp per gate.** The route lamps sit at cell *centres* and a gate stands on
  a *boundary*, so it lands between two of them and the leaf renders as a black
  hole in the wall — the one thing an obstacle you are meant to attack cannot
  look like. Warm amber (**2.0 / 5.0 m**) so gates read as a category rather than
  as one more of the route's saturated colours, and level with the middle of the
  leaf: higher up, most of its throw landed on ceiling tiles and the amber washed
  much further down the corridor over the route's own colour.

### Doors
A **gate** seals the corridor at a boundary between two route cells, and there
are two ways past it: **one swing smashes it, or `[E]` lifts it** (`door.gd`).
Sizes were measured, not guessed — `tools/_probe_kit_sizes.gd`
prints a piece's front silhouette as an occupancy map, so a doorway is read off
the geometry:

| piece | at `S` | opening |
|---|---|---|
| `Door_Frame_01` | 2.0 × 2.0 × 0.5 m | 1.0 × 1.5 m, centred |
| `Door_01` | 1.0 × 1.5 × 0.2 m | — exactly that opening |

**Native scale is unusable**: a 1.5 m doorway is shorter than the 2 m player
capsule, so there is no walking through it once it is broken. Scaled ×2 across
and up — and left alone in depth, so the jamb keeps its thickness — **one** frame
spans the whole 4 × 4 m corridor cross-section on its own and the opening becomes
a generous 2.0 × 3.0 m. That is why a gate is one piece and not two side by side.

The frame is art; its solid parts are three boxes off the same silhouette (two
1 m jambs, a 1 m lintel), and the doorway is left clear so that smashing *or
raising* the leaf leaves a real hole. The leaf is turned 180°: its lit side is its local −Z and the
player always arrives from the gate's −Z, so unturned it renders as a flat black
rectangle.

Gates go only where the corridor is exactly one cell wide on **both** sides of
the boundary (`_is_choke`). Hung off a room, half a gate would seal nothing and
the player would walk around the door.

### The interaction contract
`player.gd` casts `interact_range` (3.5 m) down the camera axis every physics
frame. Any collider with an `interact(by)` method becomes the focus; if it also
has `prompt() -> String`, that string is shown as `[E] <prompt>`. Return `""`
to offer nothing. **That is the whole contract** — a new usable object needs no
registration, just those two methods. `door.gd` is the proof: making gates
openable took those two methods on the leaf and one constant in the builder, and
nothing in `player.gd` or `hud.gd` changed.

Two optional extras, which `pickup.gd` uses and chests do not: `title()` and
`subtitle()` are drawn above the `[E]` line as an item card. Both are cleared
whenever `prompt()` returns `""`, so a spent object stops advertising itself.

Aim is the camera origin along `-Z` for the melee swing and this ray alike,
which is exactly screen centre, so the crosshair is truthful.

### `bat_spawner.gd` (Node3D)
Spawns `bat_scene` on a ring around the player. Interval ramps
`start_interval → min_interval` over `ramp_seconds`; batch grows
`start_batch → max_batch`, one extra per `batch_every` seconds. Hard cap
`max_alive = 45`.

Rejects spawn points inside geometry with `intersect_point`, retrying up to
`placement_attempts` angles.

Public: `current_interval()`, `current_batch()`, `alive_count()`,
`spawn_one(player)`. Set `enabled = false` to switch the horde off.

### `dungeon.gd`, `chonchon.gd`
Used only by the **alternate dungeon level** (see below). Not referenced by the
current scene. `dungeon.gd` re-binds the dungeon kit's atlas textures by
material name; `chonchon.gd` is the older stationary hovering bat.

## Level generators — `tools/`

Levels are generated by re-runnable scripts rather than hand-built, so layout is
reproducible. Each loads `main.tscn`, strips the nodes it owns, rebuilds, and
saves. The Player, Arms and DaggerMount are always preserved.

```bash
"$GODOT" --headless --path . -s tools/build_terrain.gd     # current level
"$GODOT" --headless --path . -s tools/build_dungeon.gd     # alternate level
"$GODOT" --headless --path . -s tools/build_corridors.gd   # corridor shooter level
"$GODOT" --headless --path . -s tools/build_bat_scene.gd   # regenerate bat.tscn
"$GODOT" --headless --path . -s tools/build_watcher_scene.gd  # regenerate watcher.tscn
"$GODOT" --headless --path . -s tools/build_chest_scene.gd    # regenerate chest.tscn
"$GODOT" --headless --path . -s tools/mount_dagger.gd      # re-mount the dagger
"$GODOT" --path . -s tools/shot_terrain.gd                 # stills, NOT headless
"$GODOT" --path . -s tools/shot_dagger.gd                  # dagger-grip close-ups, NOT headless
"$GODOT" --path . -s tools/shot_pickups.gd                 # loadout flow stills, NOT headless
"$GODOT" --path . -s tools/shot_corridors.gd               # stills, NOT headless
```

Throwaway probes, kept because the numbers they produce are the only defence
against re-guessing (`_`-prefixed, like `_death_strip.gd` / `_gun_hand.gd`):

```bash
# per-sample bone motion / foot separation / mace-hand height across the take
"$GODOT" --headless --path . -s tools/_probe_watcher_take.gd -- 7.6 10.0 0.04
# the same take as a contact sheet:  from to cols rows [name]
"$GODOT" --path . -s tools/_probe_watcher_sheet.gd -- 0 15.83 8 8
"$GODOT" --path . -s tools/_probe_ragdoll.gd -- 9    # kill one, sheet the death
"$GODOT" --path . -s tools/_probe_chase.gd           # sheet an alerted chase
"$GODOT" --path . -s tools/_probe_main_kill.gd       # the same kill in main.tscn
"$GODOT" --path . -s tools/_probe_main_kill.gd -- solo   # ...with the camp removed
# viewmodel: hold the attack button down.  frames [frames-per-sheet-cell]
"$GODOT" --path . -s tools/_probe_hold.gd -- 180     # numbers: alternation + cadence
"$GODOT" --path . -s tools/_probe_hold.gd -- 84 4    # a sheet you can actually read
# kit piece bounds + a front silhouette, so doorways are measured not guessed
"$GODOT" --headless --path . -s tools/_probe_kit_sizes.gd
# smash a door / crate / chest and check what is left behind - and open a gate
"$GODOT" --headless --path . -s tools/_probe_smash.gd
# ...and what OPENING one looks like:  [Gate_01] [frames-per-cell]
"$GODOT" --path . -s tools/_probe_door_open.gd -- Gate_01 6
# ...and what it LOOKS like:  [Crate_1|Gate_00|DaggerChest] [frames-per-cell]
"$GODOT" --path . -s tools/_probe_shatter.gd -- Crate_1 4
# why a pile looks the way it does: texture, density, per-chunk UV window
"$GODOT" --headless --path . -s tools/_probe_chunk_uv.gd -- Crate_1
# the opening cutscene, driven with real E presses:  [frames-per-cell]
"$GODOT" --path . -s tools/_probe_cutscene.gd -- 50
# the creature model from four sides, plus its real size
"$GODOT" --path . -s tools/_probe_creature.gd
# what is inside a character FBX: skeleton, clips, height, ragdoll-chain match
"$GODOT" --headless --path . -s tools/_probe_character.gd -- res://path/to.fbx
```

`_probe_smash.gd` drives everything through `take_hit()`, the same entry point the
melee ray uses, and its real assertions are the ones a still cannot show: the pair
of raycasts either side of a gate (**blocked before, clear after** — a door that
breaks but leaves its collider, or a doorway too small to walk through, both look
fine in a picture), and that the chunks **settle and then clean themselves up**
(0 still moving at 2.5 s, 0 alive at 4.5 s). Those rays **exclude every
`CharacterBody3D`**: a watcher wanders into the doorway and the after-ray then
reports the enemy rather than `clear`, which is a pass reported as a failure —
what is under test is the hole, not who is standing in it. It runs the same
before/after pair for the **`[E]` route** on a *different* gate, so the two ways
past a door are proved independently — a leaf that plays its rise while leaving
its collider behind looks perfect and seals the corridor exactly as before. The
chunk counts also skip any pile that already existed when a test started: every
pile is named `Shatter*`, so the crate's 8 cubes were being counted together with
the door's 16 planks, which then aged out mid-measurement.
`_probe_shatter.gd` is the other
half and needs a display server: whether the pile reads as the thing that was
standing there, rather than as a cloud of grey cubes.

`_probe_cutscene.gd` is the one probe in the folder that leaves **`player.gd`
attached**, where every other one strips it. The assertion that matters there is
the one a screenshot cannot make — that the player is frozen while the thing is
talking and gets control back afterwards — so mouse mode is forced visible every
frame instead, or the preview window swallows the real trackpad. Lines are
advanced with real `E` presses through `Input.parse_input_event`. One trap: a
finished line leaves `visible_characters` equal to the line's length, **not**
`-1`, so a probe that waits for `-1` waits forever.

`_probe_chunk_uv.gd` is what to reach for when it does **not** read right, and it
is the reason the numbers above are numbers rather than adjectives: it prints the
prop's texture and measured density, the palette the emission lift comes from,
and the UV window every chunk was actually given, with the colour that window
resolves to. A pile that renders as identical grey lumps and one that renders
correctly look the same in the scene tree and differ here — the centroid-bounds
bug showed up as *every chunk printing the same window*, which no screenshot
would have named.

`_probe_main_kill.gd` earns its place separately from `_probe_ragdoll.gd`: a
synthetic floor cannot show a corpse being trampled by its own squad, and that
was a real bug. It strips `player.gd` before the scene enters the tree — the same
trick `shot_terrain.gd` uses, because `_ready()` captures the mouse.

`_probe_hold.gd` has two traps of its own. It pins `Engine.max_fps` to 60: a
windowed run is otherwise uncapped, and the cadence under test is in seconds, so
uncapped frames advance almost no animation time each. And it **must** run
windowed — `_unhandled_input` refuses to act unless the mouse is captured, and
the headless display server ignores `Input.mouse_mode` entirely.

**A held mouse button CAN be faked**, contrary to what this file used to say.
`Input.parse_input_event()` updates the same button mask
`Input.is_mouse_button_pressed()` reads, so pressing without ever releasing puts
the real hold path under test rather than having the probe stand in for it. The
probe prints whether the mask took and falls back to calling `attack()` per frame
if it ever stops working.

The windowed probes count **physics** frames rather than process frames where
timing matters, since a windowed run is uncapped and process frames are not a
clock.

- **`build_terrain.gd`** — the current level. 120×120 m ground, a 6-step
  staircase (`STEP_RISE = 0.55`, chosen to stay inside the 1.28 m jump reach at
  the time; jump is now higher), two walkable ramps, a wall-run course (a 28 m
  corridor plus two long walls), 5 pillars, 4 watcher camps (camp 0 guards the
  dagger, per `CAMP_LOOT`; the rest are empty since the pistol was cut), the
  HUD, and 34
  seeded scattered boxes that
  respect keep-out rectangles. Also places `BatSpawner`.
  Owns the terrain **materials** (`_mat()`): ground is `Horror_Stone_01`,
  obstacles are `Horror_Wall_03`. Tile density is `GROUND_TILE` /
  `OBSTACLE_TILE`, in metres. Assigning these in the editor instead is pointless
  — the next run rebuilds `Ground` and `Obstacles` from scratch.
  Owns the whole **lighting rig** too — see below.
- **`build_dungeon.gd`** — alternate stone-room level from the PSX dungeon kit
  (137 pieces). `build_terrain` and `build_dungeon` strip each other's nodes, so
  they are **mutually exclusive**; run either for a clean level.
- **`build_corridors.gd`** — **writes `scenes/corridors.tscn`, not
  `main.tscn`**, so it is *not* mutually exclusive with the other two. A Post
  Void style corridor crawl from the dungeon kit: seeded drunkard's walk on a
  coarse grid where one coarse cell is 2×2 kit modules (4×4 m), so corridors are
  one cell wide and turns are trivial; rooms are a 2×2 coarse block. It loads
  `main.tscn` only to inherit the working Player / Arms / DaggerMount / HUD rig,
  then strips every level node. Change `SEED` for a different dungeon. Places
  three chests: the dagger at `DAGGER_CHEST_AT`, an empty one
  `MID_CHEST_FRAC` of the way along, and the goal at the far end — so you open
  bare-fisted and arm yourself as you go. The middle chest carried the blood
  pistol until that was cut and is kept as something to open and to smash, since
  the dagger is now the only item there is. Both are tucked against a corridor
  wall so they never block a sprint, and all three are marked `destructible`.
  Also owns every destructible: crates and barrels via `_breakable()` (`CRATES`
  is the table — a new one is a row), and door gates via `_place_gates()`. Flat
  rubble and candles stay in `DECOR` and get no collider at all: at 0.2 m and
  0.3 m tall they are something to trip over on a sprint, not something anyone
  would aim at. Crates skip the cells the watcher packs spawn on — now that they
  are solid, a pack materialising inside a barrel gets shoved out of formation.
  **`_is_pack_cell()` is the one predicate that decides where a pack goes**, and
  both placers ask it — enemies to place, crates to avoid. They used to test the
  same arithmetic separately, and when this changed they drifted: crates were
  still avoiding cells that no longer had a pack on them.
  **No enemy appears before the first gate.** `_is_pack_cell()` requires the
  route index to be past `_first_gate_i`, recorded by `_place_gates()` — which is
  why gates are placed before enemies. The opening stretch is where the dagger
  and the first door are; a pack in it means being jumped bare-fisted before
  either. On the current seed the first gate is at route 4 and the first pack at
  route 8, and the builder prints both.
  Also places the opening cutscene: the creature one cell down the corridor and
  the `Cutscene` CanvasLayer that drives it (`cutscene.gd`). Both the model's
  scale and the offset that puts its feet on the floor are **measured** off its
  bounds with the same `_accumulate()` the kit pieces use — its origin sits at
  the *top* of the mesh, so a wrapper standing on the floor buried all but 0.3 m
  of it, which looked exactly like a dark sliver behind the dialogue box.
- **`build_bat_scene.gd`** — writes `scenes/bat.tscn`.
- **`build_chest_scene.gd`** — writes `scenes/chest.tscn`; the collider is
  measured from the model's world bounds at build time, not typed in.
- **`build_watcher_scene.gd`** — writes `scenes/watcher.tscn`. Measures the rig
  from bone global poses at build time instead of hardcoding, because the FBX is
  not authored at its origin (bind pose sits ~3.2 units out in +Z) and is 2.36
  units tall; it is re-centred and scaled to `TARGET_HEIGHT` 1.9 m.
- **`mount_dagger.gd`** — rebuilds the dagger on the hand. Tunables `D_POS`,
  `D_ROT`, `D_SCALE` at the top.
- **`shot_terrain.gd`** — renders stills of `main.tscn` to `.shots/` for judging
  materials and tiling. Needs a real display server, so **no `--headless`**. It
  strips `player.gd` before the scene enters the tree, so the preview window
  cannot capture the mouse.

`build_terrain.gd` re-attaches `player.gd` on every run — see below.

### Lighting and sky — `_build_sky_and_sun()`

All of it is rebuilt by `build_terrain.gd`; editing the `WorldEnvironment` or
`Sun` in the editor is overwritten on the next run.

- **The sky is a panorama, so the sun is already painted in.** The
  `DirectionalLight3D` exists only to cast shadows that agree with it. Its
  direction was *measured*, not chosen: the warm core of the glow sits at world
  yaw **244°**, so the light points back the other way at `SUN_YAW = 64`.
  Swapping `SKY_PANORAMA` makes that number wrong — re-measure by rendering the
  sky along the four cardinal yaws and finding the bright, warm lobe.
- `SUN_PITCH` is **−26°**, not the panorama's true ~14° elevation. A sun that
  low throws 45 m shadows off the pillars and swallows half the arena. It reads
  as the same dusk and costs nothing.
- **The panorama's bottom third is solid black** — the author painted no nadir.
  With `AMBIENT_SOURCE_SKY` alone every down-facing surface therefore gets zero
  fill and renders as a hole. Fixed with `ambient_light_sky_contribution = 0.45`
  blended against an explicit cool `ambient_light_color`.
- **Albedo tints lean blue on purpose.** The key light is heavily orange, so a
  neutral albedo comes back orange and floor, props and enemies collapse into
  one hue. Biasing cool lands them near neutral and preserves the warm-light /
  cool-shadow split.
- **Fog colour must not match the ground.** A brown fog over brown ground is
  invisible. It is dusk purple, and `fog_depth_begin = 48` keeps it past the far
  side of the arena — fog inside the play space greys out approaching bats,
  which is worse than a visible ground edge.
- The bats need no help to read: the chonchon texture is pale and they hover at
  eye level against a bright sky.

## Assets

| Path | Contents | Used by |
|---|---|---|
| `assets/hands/` | `arms_rig.glb` — 52-bone rig, both arms, 18 animations, embedded texture | Player viewmodel |
| `assets/chonchon/` | `chonchon.fbx` — 22-bone rig, 14 animations | Bat enemy |
| `assets/dagger/` | `dagger.fbx` — static, 4 parts (blade/guard/pommel/grip) | Held dagger + its pickup |
| `assets/dungeon/` | PSX dungeon kit, 43 FBX + textures | `build_dungeon.gd` and `build_corridors.gd` (shell, crates, doors) |
| `assets/skeleton/` | `skeleton.fbx` — **no rig, static mesh** | unused |
| `assets/textures/` | Screaming Brain Studios Horror Texture Pack, **CC0** — 100 seamless 512² PNGs in Brick/Floor/Metal/Misc/Stains/Stone/Wall | `build_terrain.gd` (2 of them) |
| `assets/sky/` | `pumpkin_mountain_2160.png` — 8639×2160 equirectangular sunset panorama by psychopom. **Not CC0**: free to use, *no redistribution* — do not ship it in a public repo | `build_terrain.gd` sky |
| `assets/chest/` | `TreasureChest.FBX` + PBR set in `Textures/`. Lid (`chest_top`) is a separate mesh and the file carries its own open animation | Chest |
| `assets/watcher/` | `watcher.fbx` — "Watcher of the Hollow Eye", 65-bone Mixamo rig, mace. Textures **must** live at `assets/watcher/minimosnter/texture/` — the FBX hardcodes that relative path, and moving them silently unbinds every material | Watcher enemy |
| `assets/creature/` | `creature.fbx` — the Warden. **Static mesh, no rig, no animations**, 5960 tris, one material. Its origin sits at the *top* of the mesh and its bounds are dominated by the blade, so size and offset are both measured, never typed | The opening cutscene |
| `assets/fonts/` | `m5x7.ttf` — pixel font, authored at **16 px**. Godot's importer detects it as a pixel font and turns off subpixel positioning and hinting by itself. Use integer multiples of 16 for sizes; 34 and 40 come out mushy | `cutscene.gd` |
| `assets/retro_character/` | `retro_character.fbx` — 38-bone Mixamo rig, 1504 tris, 16 clips (idle, walk, run, strafe, three boxing attacks, a knockdown, plus a 37.8 s concatenation of all of them and two export artifacts). 4.198 units tall as imported. Matches **11/11** of `ragdoll.gd`'s `CHAIN`. Texture needs re-binding by material name `BODY.011` | unused — see "Not implemented" |

### Animation names

`arms_rig.glb` — dots became underscores on import:
`guard_idle`, `guard_draw`, `jab_L`, `jab_R`, `knife_idle`, `knife_draw`,
`knife_hit_01`, `knife_hit_02`, `finger_gun_idle`, `finger_gun_fire`,
`finger_gun_broken`, `finger_gun_fix`, `push_L/R`, `grab_L/R`, `relax`, `rest`.

Lengths of the six still in use, which are what `attack_speed` is compensating
for: `jab_L` and `jab_R` **1.000 s** each, `knife_hit_01` 0.700, `knife_hit_02`
0.733, `guard_idle` 2.167, `knife_idle` 1.667.

`chonchon.fbx` — Blender export prefix retained:
`Armature|idle`, `Armature|fly attack`, `Armature|hit reaction`,
`Armature|death`. The file also contains ~10 duplicate export artifacts with
stacked `Armature|Armature|...` prefixes, two of them zero length — ignore them.

### Asset facts worth not rediscovering

- **`arms_rig.glb` forward axis is +Z**, so the `Arms` node carries a 180° Y
  rotation. `chonchon.fbx` front is also +Z. `skeleton.fbx` faces −Z. There is
  no convention across packs; check by rendering both sides.
- The arms rig contains a **`camera` bone** marking intended eye position
  (y = 1.7432). The `Arms` node is offset by exactly that so the bone lands on
  `Camera3D`.
- **The arms bind pose is a T-pose.** An idle must always be playing or the arms
  splay across the screen.
- **Not every texture in the horror pack actually tiles.** Wrap-edge continuity
  was measured against interior gradient; most score ~1.0, but `Floor_11`–`14`
  (3.3–7.6), `Wall_09` (3.7) and `Brick_04` (4.4) have a hard seam on one axis.
  They are grid/plank patterns — avoid them on anything tiled more than a few
  times, and never on the 120 m ground.
- **The dagger models along +Y and `hand.R` +Y runs wrist->fingertips**, so
  `D_ROT = 0` spears the blade straight out of the knuckles like a claw. A fist
  grips a handle *across* the fingers, not along them — measured, the grip
  tunnel is almost exactly the hand bone's **+Z**.
- **`D_POS`/`D_ROT` were solved from the rig, not eyeballed.** With `knife_idle`
  playing, per-finger joint centroids in `hand.R` local space give the grip
  tunnel: centre ≈ (-0.016, 0.086, ±z), axis ≈ the hand bone's +Z. If the idle
  animation is ever re-authored, re-solve rather than nudge. One liberty: a
  blade exactly down the tunnel points sideways across the screen (the idle
  poses the fist knuckles-out), so the axis is canted **22°** toward
  camera-forward. Camera-forward is 101° away in hand space — an earlier 40%
  slerp (a 40° tilt) drove the handle diagonally through the fingers; past ~25°
  the pommel leaves the fist. Verify any change with `tools/shot_dagger.gd`.
- **`mount_dagger.gd` re-centres the parts on the grip.** The model origin sits
  ~8cm down the blade axis from the grip, so rotating about it swung the handle
  out of the palm on an 8cm arm and every `D_ROT` change meant re-chasing
  `D_POS`. Pivoting on the grip makes the two independent.
- `dagger.fbx` references four textures by the author's absolute Linux paths
  which were never shipped. `mount_dagger.gd` falls back to flat colours, and
  will pick up `assets/dagger/{blade,grip,guard,pommel}.png` automatically if
  those files ever appear.

## Engine gotchas that affect this project

These are properties of Godot's importer and `PackedScene`, not style choices.

**FBX import drops texture links.** Every FBX in this project came in with bare
materials named after the texture they want. The fix in use is to re-bind by
material name at load onto the *shared mesh resource* (see `dungeon.gd`,
`bat_enemy.gd`) so it costs one bind regardless of instance count. glTF does not
have this problem — `arms_rig.glb` imported textured with no fixup.

**`pack()` silently drops things.** `ResourceSaver.save()` still returns OK.
Three distinct cases hit this project:
1. Property overrides on nodes *inside* an instanced scene.
2. New child nodes added *inside* an instanced scene. (This is why `DaggerMount`
   lives outside the `Arms` instance and uses an external skeleton reference.)
3. **A node's script, if that script had a parse error when `pack()` ran.** The
   node then loads with no script and every `@export` access fails at runtime.
   Fixing the syntax afterwards does not restore it. `build_terrain.gd`
   re-attaches `player.gd` defensively each run because of this.

After any tool run that logged a parse error, check:
```bash
grep "^script = ExtResource" scenes/main.tscn
```

**Godot omits default values from `.tscn`.** An absent property means "equals
default", not "failed to write".

**Seeking between clips in one baked take always pops.** There is no blend —
`_play_clip()` jumps the playhead, so entering the death or hurt clip snaps the
pose. It is inherent to driving one take this way; fixing it properly would mean
slicing the take into real Animation resources so `play()` could cross-fade.

**An FBX may ship one baked take instead of named clips.** `watcher.fbx` has a
single 15.83 s animation called `all` with idle, walk, attacks and death run end
to end. `watcher_enemy.gd` does not slice the resource — it plays `all` on a loop
and seeks within it, with the ranges in a `CLIPS` dictionary and the playhead
policed each frame. Retiming is then editing numbers, not editing a resource.

**Getting those ranges wrong is invisible in code and obvious in play.**
`CLIP_WALK` was `[5.90, 8.00]`, which is the *recovery arc of the overhead slam*
— so an alerted watcher chased you while apparently swinging its mace over and
over, and it read as "the attack animation loops when it spots me". Adjacent
segments in a take like this look plausible and are not. The take is
**concatenated segments that each return to the same rest pose**, and that rest
pose is the seam — it recurs at 9.70, 11.60 and 13.40 s:

| span | what it is |
|---|---|
| 0.00–2.00 | idle, mace shouldered |
| 2.05–8.20 | wind-up → overhead slam, mace bottoming out at **5.00** → long recovery |
| 8.24–9.56 | the walk cycle |
| 9.75–11.55 | a lunging thrust (unused) |
| 11.70–13.35 | a leaping kick (unused; its landing crouch stands in for `HURT`) |
| 13.50–15.80 | the collapse |

Re-measure with `tools/_probe_watcher_take.gd` (per-sample bone motion, foot
separation, mace-hand height) and confirm on a contact sheet from
`tools/_probe_watcher_sheet.gd` — do not nudge the numbers. The two tells: the
walk is the only span where bone motion is a steady **4–6 units/sample** instead
of 20–60, and the only one where **foot separation oscillates**. There is no
flinch anywhere in the take; `CLIP_HURT` is the kick's landing crouch.

**PhysicalBone3D inverts the skeleton's scale into the bone pose.** A simulating
bone writes `pose = skeleton_global.inverse() * body_world * body_offset.inverse()`,
so any scale on the skeleton's ancestors lands in the bone *basis*. The watcher
rig is scaled to real-world size by `build_watcher_scene.gd` (Mixamo authors it
~340 units tall), giving a skeleton scale of **0.002778** — an uncompensated
ragdoll therefore renders the mesh ~360× too large and fills the screen, with no
error printed. `ragdoll.gd` puts `1/k` in `body_offset.basis`, which cancels it
and, usefully, makes the body's own world transform come out unit-scale — which
is what a physics body wants anyway. The consequence is that **the collision
shapes are in world metres while `body_offset.origin` stays in skeleton units**.
They are not in the same space, and that is correct.

**Skinned meshes report useless AABBs.** `chonchon.fbx` reports ~74,000 units
because vertices follow bone matrices, not the node transform. Size skinned
models from **bone global poses**, and measure *during* the idle animation — the
chonchon reads 14.06 units wide at rest but 9.17 mid-idle.

**FBX pieces may not be authored at their origin.** The dungeon kit's geometry
sits 50–60 units from its node origins; `build_dungeon.gd` measures and
compensates per piece. A mesh-local AABB hides this — measure world bounds.

**Testing headlessly has two traps.** The dummy display server ignores
`Input.mouse_mode`, so input-gated code never runs; and headless runs uncapped,
so a fixed frame count advances far less animation time than expected. Use a
real display server for anything timing- or input-dependent — but note
`player.gd` captures the mouse in `_ready()`, so a test window will swallow real
trackpad input unless you force `MOUSE_MODE_VISIBLE` every frame.

## Not implemented

- **No damage to the player.** Bats swarm and hover; there is no player health,
  no contact damage, no death or restart. The HUD draws only a crosshair and the
  interaction prompt plus the focused item's card — no health, ammo or score. The
  watchers' mace swing does
  call `take_hit` on the player at the right moment in the animation — the
  method just does not exist yet, so it is a no-op. Adding player health is
  enough to make them dangerous; nothing in the enemy needs changing.
- **Opening a chest does nothing but open it**, unless it has `loot` set. The two
  weapons are the only items — there is no inventory and no other loot beyond
  them, and "Lvl 1" implies no upgrade path yet. `chest.gd` emits `opened`.
- **Wreckage is temporary and boxy.** A smashed prop falls into real chunks
  (`shatter.gd`) which carry the prop's own texture, but they are axis-aligned
  boxes off the collider, not cut from the model — so a chunk shows a *window* of
  the texture rather than the surface that was really there, and a broken edge is
  as textured as an outer face. The pile also shrinks out after ~3.6 s rather than
  persisting. Cutting the mesh properly is the next step if that stops being
  enough. Crates
  drop no loot: `breakable.gd` emits `broken`, and `chest.gd`'s `_spill()` is the
  only thing that drops anything.
- **Nothing but the player can break or open a door.** A watcher chasing you
  through a gate stops at it; there is no AI that attacks scenery and none that
  presses `[E]`. A raised door also never comes back down — `door.gd` is one-way,
  so a gate cannot be shut behind you to break line of sight. The outdoor arena
  has no destructibles at all — `chest.gd`'s `destructible` defaults false and
  `breakable.gd` is only ever built by `build_corridors.gd`.
- **One cutscene, in one level.** `cutscene.gd` runs at the start of
  `corridors.tscn` and nowhere else; there is no scene for the goal chest, no
  ending, and nothing calls it a second time. It is general enough to reuse —
  lines, speaker and timings are exports — but it hard-codes taking control from
  the player, so two of them running at once would fight over it.
- **`assets/retro_character/` is imported and unused.** A 38-bone Mixamo rig with
  idle / walk / run / three punches / a knockdown, and 11/11 of `ragdoll.gd`'s
  chain matching by name — enough for a second melee enemy with no new ragdoll
  work. It cannot be the first-person viewmodel: one finger chain per hand, no
  thumb, and its clips are authored for a camera 3 m away. As a third-person
  player body it is also missing a jump and a fall, which this game needs.
- **No score, waves UI, or progression** beyond the spawner's rate ramp.
- **No audio** anywhere.
- **No save/load, no menus.**
- **No ranged attack.** The blood pistol, its bolt (`projectile.gd`), its pickup
  icon and the whole two-button layout were cut: melee is the only way to deal
  damage, and left click is the only attack. Ten of the rig's eighteen clips are
  now unused — `finger_gun_*` (all four), `push_L/R`, `grab_L/R`, `guard_draw`,
  `knife_draw`, `relax` and `rest`. In use: `guard_idle`, `knife_idle`, `jab_L`,
  `jab_R`, `knife_hit_01`, `knife_hit_02`.
- No decals or impact effects on a melee hit beyond the blood/debris burst.
- Two enemy types: the swarming `bat_enemy.gd` and the hand-placed
  `watcher_enemy.gd`. Either is a template for more; `take_hit` is the damage
  contract.
- **Only the watcher ragdolls.** `ragdoll.gd` is written to be shared, but
  `bat_enemy.gd` still plays `Armature|death` and frees itself on a timer. A bat
  is a one-hit swarm unit whose corpse is on screen for under a second, so the
  eleven bodies would mostly be cost — but the call is `RAGDOLL.build()` +
  `RAGDOLL.start()` if that changes. Its `CHAIN` would need the chonchon's own
  bone names.
- `CLIP_DEATH` is now only reachable with `use_ragdoll = false`, and the take's
  lunging thrust and leaping kick (9.75–11.55, 11.70–13.35) are still unused —
  a second attack is one `CLIPS` entry and one branch away.
