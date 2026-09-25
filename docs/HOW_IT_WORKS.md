# Treant Boss — How It Works

A guide to this project for someone new to Godot. It covers how to run it, the Godot concepts you need (mapped to Unity/Unreal), where everything lives, how the boss "thinks", how each attack works, how the Spine player character is set up, how the build lines up against `PK_Boss_CDD.pdf`, and how to tweak things.

---

## 1. Run it

1. Open Godot, open the `treant-boss` project.
2. Press **F5** (or the ▶ button, top right). This runs the **main scene**, `scenes/arena/test_arena.tscn`.
3. **F8** stops the game. **F6** runs whichever scene is open in the editor instead of the main scene.

**Controls** (also shown at the top of the game window):

| Key | Action |
|---|---|
| A / D | Move left / right |
| Space | Jump |
| Shift (while moving) | Dash. You're **invulnerable** during the dash (you turn see-through). This is the CDD's "evade". You're also invulnerable for 0.5s after taking a hit (you flicker). |
| J or Left-click | Attack, 12 damage. You always swing toward the boss. Swinging as the spiked bulb reaches you **parries** it. |
| R | Restart the fight |

What you'll see: you play an animated Spine character (§6), starting at the left end of a long platform with the boss idle ahead of you. A **red line with a post** on the ground marks its aggro range; nothing happens until you cross it. The camera follows you and leans toward the boss. Once the fight starts: yellow numbers over the boss are damage you dealt, red numbers over you are damage you took. The boss's health bar goes green → yellow below 50% (Phase 2) → red at 10% (Phase 3). The text above the boss shows its current state/attack. That text is a debug aid, not final UI.

---

## 2. Godot in five minutes (for a Unity/Unreal person)

| Godot | Unity / Unreal equivalent | Where you'll see it here |
|---|---|---|
| **Node** | A GameObject that *is* one component (Sprite, Area, Timer…) | Everything in the Scene dock (top-left panel) |
| **Scene** (`.tscn`) | Prefab / Blueprint: a saved tree of nodes | `treant_boss.tscn`, `player.tscn`, `test_arena.tscn` |
| **Instancing a scene** | Dropping a prefab into a level | The arena contains one Player and one TreantBoss instance |
| **Script** (`.gd`, GDScript) | MonoBehaviour / Blueprint graph attached to a node | `scripts/…` |
| `_ready()` | `Start()` / `BeginPlay` | Setup in every script |
| `_physics_process(delta)` | `FixedUpdate()` / Tick | Player movement |
| `@export var` | `[SerializeField]` / `EditAnywhere`: shows in the Inspector | `Health.max_health`, `Hitbox.damage` |
| **Signal** | C# event / UnityEvent / Delegate | `Health.died`, `Hurtbox.damaged`, state `state_entered` |
| **Resource** (`.tres`) | ScriptableObject / Data Asset | `resources/attacks/*.tres` (attack data), `resources/guards/*.tres` |
| **GDExtension** | Native plugin (Unity native DLL / Unreal C++ plugin module) | The Spine runtime in `bin/spine/` |
| **Group** | Tag | `"player"`, `"boss"`, `"boss_arena_corner"` |
| `CharacterBody2D` | CharacterController / Character | Player and boss bodies |
| `Area2D` | Trigger collider | Hitboxes, hurtboxes, detection range |
| `await get_tree().create_timer(t).timeout` | `yield return new WaitForSeconds(t)` (coroutine) | Every attack's telegraph → active → recovery timing |
| `Tween` | DOTween / Timeline curve | Boss movement, spike growth, fades |
| **Collision layer / mask** | Physics layers + layer collision matrix | See §7 |

Two Godot quirks that matter here:
- **Y points down.** Negative Y is *up*. Characters' origins sit at their feet; the ground's top edge is `y = 0`.
- **Children inherit their parent's transform.** Mirroring a parent with `scale.x = -1` flips every child. The boss and player face left/right by flipping one `AttackOrigin` node, so all attack hitboxes and indicators flip with it.

**Editor panels:** Scene dock (node tree of the open scene, top-left), FileSystem (project files, bottom-left), Inspector (properties of the selected node, right), Output/Debugger (bottom, where `print()` and errors appear).

---

## 3. Project map

```
scenes/
  arena/test_arena.tscn     The level: 2000px ground, invisible side walls, 2 corner markers
                            (they define the arena's extent for the boss), follow camera,
                            controls HUD. Main scene. Script: restart on R.
  player/player.tscn        The player: Spine character (BodySprite), hurtbox, attack hitbox, health.
  boss/treant_boss.tscn     The boss: body, hitboxes, health bar, particles, STATE CHART.

scripts/
  boss/treant_boss.gd       Boss "body": wires the state chart to behaviour, owns the
                            reusable attack beats (swing, sweep, throw, roots, movement).
  boss/attacks/
    melee_combo.gd          Phase 1: 3–6 random melee swings, sometimes plus one bulb throw.
    long_range_attack.gd    Back off, 3 horizontal sweeps with growing reach.
    root_attack.gd          Phase 2: go to a corner, channel, 3 root spikes.
    spiked_bulb.gd          The thrown projectile (parryable).
  boss/detection_area.gd    The aggro range: fires `player_detected` when the player enters,
                            and draws the red line on the ground (fades out once aggro'd).
  common/health.gd          HP + `health_changed` / `died` signals (boss and player).
  common/hitbox.gd          Deals damage while active.
  common/hurtbox.gd         Receives damage; has an `invulnerable` flag (dash, post-hit, death).
  common/floating_text.gd   Damage numbers / "PARRY!" popups.
  player/player_controller.gd  Move, jump, dash, attack, parry window, death, and picks the
                            Spine animation for each (§6).
  arena/test_arena.gd       R = reload the scene.
  arena/follow_camera.gd    Camera follows the player, leans toward the boss, and stops at
                            the platform edges (Camera2D limits).

resources/
  attack_data.gd            The AttackData resource type (like a ScriptableObject class).
  attacks/*.tres            One file per melee attack: timings, damage, colour.
  guards/*.tres             The HP-threshold conditions used by the state chart.

assets/player/              The player's Spine export (player_pk.skel, pk_player.atlas + .png)
                            and pk_player_data.tres, which pairs them (§6).
textures/                   Generated placeholder art for the boss and arena (solid shapes).
addons/godot_state_charts/  Third-party plugin: the state chart system (MIT, by derkork).
bin/spine/                  Third-party GDExtension: the Spine runtime (spine-godot 4.3),
                            prebuilt for every platform. Loads automatically.
```

---

## 4. How the boss thinks: the state chart

The boss's brain is a **state chart** made with the [Godot State Charts](https://github.com/derkork/godot-statecharts) plugin, the Godot counterpart to an Unreal State Tree. It's built out of nodes: open `treant_boss.tscn` and expand `StateChart` in the Scene dock.

```
StateChart
└─ Boss                      (Compound: exactly one child active; starts in Idle)
   │  ToDefeated ── on "died" ──► Defeated          (lives here, so it fires from ANY state)
   ├─ Idle
   │    ToAggro ── on "player_detected" ──► Aggro
   ├─ Aggro                  (Parallel: BOTH children run at the same time)
   │  ├─ AttackPattern       (Compound; starts in Melee)
   │  │  ├─ Melee
   │  │  │    ToLongRange ── on "combo_finished" ──► LongRange
   │  │  ├─ LongRange
   │  │  │    ToRootAttack ── on "ranged_finished" IF hp < 50% ──► RootAttack
   │  │  │    ToMelee      ── on "ranged_finished" (otherwise)  ──► Melee
   │  │  └─ RootAttack
   │  │       ToMelee ── on "root_finished" ──► Melee
   │  └─ EnrageTrack         (Compound; starts in Normal)
   │     ├─ Normal
   │     │    ToEnraged ── on "health_changed" IF hp ≤ 10% ──► Enraged
   │     └─ Enraged
   └─ Defeated
```

**Vocabulary**
- **Compound state:** one active child at a time, like a normal state machine.
- **Parallel state:** all children active at once. `Aggro` runs the attack loop *and* the enrage tracker side by side. Enrage is a separate concern that changes *how hard* attacks hit, not *which* attack plays, so it doesn't have to be re-implemented inside every attack.
- **Transition:** a child node of a state. It fires when its **event** arrives, as long as its **guard** (if any) is true. When a state has two transitions for the same event, the first one in the tree wins. That's why `ToRootAttack` (guarded) sits above `ToMelee` (fallback) under `LongRange`.
- **Guard:** an expression such as `hp_percent <= 0.5 and root_ready`, stored in `resources/guards/*.tres`. The names in it (`hp_percent`, `root_ready`) are **expression properties** that the boss script keeps updated with `state_chart.set_expression_property(...)`.
- **Events** are strings sent with `state_chart.send_event("...")`:

| Event | Sent by | When |
|---|---|---|
| `player_detected` | `treant_boss.gd` (from DetectionArea) | Player crosses the red aggro line (a 1000px-wide zone centred on the boss) |
| `combo_finished` | `melee_combo.gd` | After the 3–6 swings |
| `ranged_finished` | `long_range_attack.gd` | After the 3 sweeps |
| `root_finished` | `root_attack.gd` | After the roots retract |
| `health_changed` | `treant_boss.gd` | Every time the boss takes damage (hp_percent is updated first) |
| `died` | `treant_boss.gd` | HP reaches 0 |

**Division of labour.** The state chart only decides *when* things happen. When a state is entered it emits `state_entered`; `treant_boss.gd` listens (see its `_ready()`) and starts the matching attack script. The attack script plays the attack and sends the "finished" event, which moves the chart on. To change the fight's *flow*, edit the chart. To change *how an attack plays*, edit the attack script.

**Watching it live:** select the `StateChart` node and tick **Track In Editor** in the Inspector. The plugin then shows the active states in a State Charts tab of the bottom Debugger panel while the game runs.

---

## 5. The attacks, one by one

Every attack follows the same rhythm: **telegraph** (visible warning, harmless) → **active** (hitbox on) → **recovery** (harmless, your opening to hit back).

### Phase 1: Melee combo (the default loop)
- The boss walks to about 130px from you before **each** swing (CDD: "stays relatively close").
- It does 3–6 **melee swings**, each picked at random from the four melee attacks. Half the time it also slots **one spiked bulb throw** into the sequence at a random point. The CDD lists the bulb separately, so it doesn't count toward the 3–6.
- Each melee attack has its own hitbox shape, so each one is dodged differently:

| Attack | Hitbox shape | How to dodge | Telegraph | Active | Recovery | Damage | Colour |
|---|---|---|---|---|---|---|---|
| Arm Swipe | Wide, chest height (200×90) | Back off or dash | 0.5s | 0.3s | 0.4s | 10 | orange |
| Overhead Strike | Short but tall (140×200) | Step back: can't be jumped | 0.7s | 0.25s | 0.5s | 16 | red |
| Ground Smash | Very wide, low (360×50), reaches behind the boss too | Jump over it | 0.6s | 0.3s | 0.6s | 14 | brown |
| Short-Range Root/Arm | Low and close (150×60) | Back off or jump | 0.4s | 0.35s | 0.4s | 12 | dark brown |
| Spiked Bulb Throw | Flying projectile | Parry or dash through | 0.6s | (flies) | 0.5s | 8 | purple |

- **Telegraph:** the body tints to the attack's colour and a faint box appears showing *exactly* where the swing will land. **Active:** the box turns solid. That's the hit window.
- **Your answer:** get out of the box, whether by backing off, jumping, dashing (invulnerable), or walking through the boss to its other side. Its body isn't solid, only its attacks hurt.
- **Spiked Bulb:** thrown from where the boss stands and flies straight toward you. Parry it (attack as it arrives, "PARRY!" pops up) or dash through it.

### Phase 1: Long-range sweeps (after every combo)
- The boss backs off about 260px, then does **3 sweeps reaching 25%, 40% and 55% of the arena width** (CDD: the limb extends "across the arena"). On the current 1760px arena that's 440 → 704 → 968px, cut off at the arena edge.
- **Telegraph:** a thin yellow line along the ground shows exactly how far the sweep will reach. **Active:** it turns into a thick red bar near the ground.
- **Your answer: jump.** The bar sits about 25px off the ground and a jump clears about 80px. Or stand beyond the yellow line, but the next sweep reaches further.
- Afterwards the boss returns to Melee (or goes to Root Attack if it's below 50% HP).

### Phase 2: Root Attack (unlocks below 50% HP)
- Checked after every long-range sequence. Below 50% the boss goes to Root Attack instead of straight back to Melee, then sits out the next check (a one-cycle cooldown via the `root_ready` expression property), so roots come every other loop.
- It runs to the **nearer** arena edge (the "corners" in a side-view arena) at a steady 450px/s, then **channels** for 1.3s, pulsing purple.
- During the channel, **3 warnings** appear on the ground: a pulsing red crack plus a faint outline of the spike. **One always spawns under you**, and the other two land within 450px of you so they're on screen and relevant.
- Then 3 spikes erupt for 1.4s: 170px tall, taller than your jump, 15 damage.
- **Your answer: move** to a spot without a warning (CDD: "reposition rather than simply jump in place").

### Phase 3: Enraged (at ≤ 10% HP)
- Same attacks, **+10% attack speed and +10% damage** (every telegraph, active and recovery time is divided by 1.1).
- Visuals: red body, pulsing red glow behind it, particles turn crimson and get denser, attack warnings flash hotter (whiter) when they go active, and the bulb is drawn 30% bigger. Warning boxes keep their size because they always match the real hitbox.

### Defeated → cleansing
- At 0 HP the boss stops mid-attack, turns invulnerable, the health bar hides, and the **cleansing sequence** plays: the body fades from corruption to healthy green and the particles turn green and drift up. Press R to fight again.

### Idle (before the fight)
- The boss stands still with a slow "breathing" squash (placeholder idle animation) while purple **corruption particles** rise around its feet (CDD: "environmental corruption continues around the boss").
- It does nothing until you cross the red aggro line: 500px either side of the boss, about 650px of walking from where you spawn. The line fades out once the fight starts; the boss never drops aggro after that.

---

## 6. The player character (Spine)

The player is `pk_player`, a character animated in [Spine](https://esotericsoftware.com/), a 2D skeletal animation tool. Godot can't read Spine files on its own, so the project ships the official **spine-godot runtime** as a GDExtension in `bin/spine/`. Godot loads it at startup; there's nothing to enable in Project Settings.

| File / node | What it is |
|---|---|
| `assets/player/player_pk.skel` | Skeleton and animations, exported from Spine 4.3 as binary. Imports as a `SpineSkeletonFileResource`. |
| `assets/player/pk_player.atlas` + `.png` | The texture atlas the body parts are cut from. Imports as a `SpineAtlasResource`. |
| `assets/player/pk_player_data.tres` | A `SpineSkeletonDataResource` that pairs the two, plus the blend time between animations (Default Mix, 0.1s). |
| `player.tscn` → `BodySprite` | A `SpineSprite` node that draws and animates that data. Its origin is at the character's feet; scale 0.25 makes it about 111px tall, standing over the 100px hurtbox. |

**Which animation plays.** Every physics frame, `_choose_animation()` in `player_controller.gd` picks one from the player's state. The first match wins:

| State | Animation |
|---|---|
| Dashing | `dash` |
| Attacking | `attack_sword` |
| In the air, rising | `jump_start`, then `jumping` |
| In the air, falling | `fall` |
| Just landed, standing still | `landing` once, then `idle` |
| Moving on the ground | `run` |
| Otherwise | `idle` |

The animation only changes when the choice changes, so looping animations play smoothly. Attacks always restart, so back-to-back swings each play in full.

**Three ways a `SpineSprite` differs from a `Sprite2D`:**
- **Facing:** there's no `flip_h`, so the controller mirrors the character by making `scale.x` negative. The rig faces right.
- **Transparency:** the see-through dash and the post-hit flicker set `modulate.a`, not `self_modulate`. `SpineSprite` draws each body part as a child mesh, and `self_modulate` doesn't reach children.
- **Attack timing:** `attack_sword` draws its slash about 0.25s in, but the hitbox is only live from 0.08s to 0.20s into a swing. So the animation plays about 1.8× faster (`ATTACK_ANIM_SPEED`, worked out from the attack timing constants), and the slash shows while the hit is live.

**Not used yet:** the rig also has `walk`, `flip`, `fire_ball`, `attack_sword_up`, `attack_sword_down` and an empty `animation`. It has no hit or death animation, so on death the player goes back to idle and darkens.

**Re-exporting from Spine:** use Spine 4.3.x, because the runtime in `bin/spine/` is 4.3 and refuses other versions. Export as binary `.skel`, or as JSON renamed to `.spine-json`. On a fresh checkout, Godot may log "Can't load texture … pk_player.png" during the first import, because the atlas was imported before its PNG. It's harmless; the texture loads fine afterwards.

---

## 7. Combat plumbing (how damage actually happens)

Three small reusable pieces, shared by the boss and the player:

- **Hitbox** (`Area2D`): switched on only during an attack's active window. When it overlaps a Hurtbox it calls `apply_damage` on it.
- **Hurtbox** (`Area2D`): emits `damaged`, unless `invulnerable` is true (dash, 0.5s after a hit, death).
- **Health** (`Node`): subtracts HP, emits `health_changed` and `died`. Everything else (health bar, state chart, damage numbers) just listens to these signals.

**Collision layers** decide who can hit whom (Project Settings → Layer Names → 2D Physics):

| # | Name | Who is on it | Who looks for it (mask) |
|---|---|---|---|
| 1 | world | Ground, walls | Player body, boss body |
| 2 | player_hurtbox | Player Hurtbox | All boss hitboxes (melee, sweep, roots, bulb) |
| 3 | boss_hurtbox | Boss Hurtbox | Player attack hitbox |
| 4 | player_body | Player body | Boss DetectionArea |
| 5 | boss_body | Boss body | (nothing, so the player can walk through the boss) |

This setup is what stops the boss hitting itself, and what lets you walk through it.

---

## 8. How to tweak things (no code needed for most)

| I want to change… | Where |
|---|---|
| Boss HP (currently 800; the enrage phase is its last 10%, so HP also sets how long that phase lasts) | `treant_boss.tscn` → select `Health` → Inspector → Max Health |
| Player HP (100) | `player.tscn` → `Health` → Max Health |
| A melee attack's timing/damage/colour | Double-click `resources/attacks/<name>.tres` → Inspector |
| Phase thresholds (50% / 10%) | Double-click `resources/guards/*.tres` → edit the expression |
| Aggro range (1000px wide) | `treant_boss.tscn` → `DetectionArea/CollisionShape2D` → Shape → Size. The red line redraws to match. Untick `Show Range` on `DetectionArea` to hide it. |
| Platform length / where the fight can go | `test_arena.tscn`: `Ground` (sprite scale + collision size), `WallLeft`/`WallRight`, and the two `Corners` markers. The boss reads its movement limits from the corners, so no script change is needed. Also update `ArenaCamera` → Limit Left/Right. |
| Spawn positions | `test_arena.tscn` → the `Player` and `TreantBoss` nodes' Position (the `PlayerSpawn`/`BossSpawn` markers just mark the intended spots) |
| A melee attack's hitbox shape | Double-click `resources/attacks/<name>.tres` → Inspector → Hitbox Size / Hitbox Offset. Offset is from the boss's chest; +x is toward the player, +y is down, and the ground is at y = 90. |
| Chance of a bulb throw per combo (50%) | `PROJECTILE_CHANCE` in `scripts/boss/attacks/melee_combo.gd` |
| Sweep reach, corner run speed, root size/timing, enrage multiplier, approach distance | Constants at the top of `scripts/boss/treant_boss.gd` (sweep reach is `LONG_RANGE_REACH_FRACTIONS`, fractions of the arena width) |
| Player speed, jump, dash, attack damage | Constants at the top of `scripts/player/player_controller.gd` |
| Player character size | `player.tscn` → `BodySprite` → Scale. Keep X and Y equal and positive; the script flips X for facing. |
| Which Spine animation plays for what | `ANIM_*` constants at the top of `scripts/player/player_controller.gd` |
| Blend time between player animations (0.1s) | Double-click `assets/player/pk_player_data.tres` → Default Mix (per-pair overrides under Animation Mixes) |

**Adding a new melee attack:** in the FileSystem dock, right-click an existing `resources/attacks/*.tres` → Duplicate, edit its values (including its hitbox shape) in the Inspector, then add its path to `MELEE_ATTACK_PATHS` at the top of `treant_boss.gd`. The combo picks it up automatically.

**When real boss art arrives:** swap the boss's `Sprite2D` textures in the Inspector, and tick **Flip Sprite With Facing** on the `TreantBoss` root node. It's off only because the placeholder texture has the word "TREANT" baked in, which would read backwards when mirrored. If the boss art is a Spine rig, set it up the same way as the player (§6).

---

## 9. CDD tally

| CDD item | Status | Notes / where |
|---|---|---|
| Idle: stationary until player in range | ✅ | `Idle` state, `DetectionArea` (visible red aggro line; you spawn outside it) |
| Idle: idle animation | 🟡 placeholder | Breathing squash tween |
| Idle: environmental corruption around boss | 🟡 placeholder | `CorruptionParticles` |
| Idle: does not attack | ✅ | Nothing runs in `Idle` |
| Aggro starts with melee pattern | ✅ | `AttackPattern` initial state = `Melee` |
| Melee combo: random 3–6 of swipe / overhead / smash / short root | ✅ | `melee_combo.gd` + `resources/attacks`; each attack has its own hitbox shape |
| Player evades melee | ✅ | Dash i-frames, boss body not solid |
| Spiked bulb throw, parryable | ✅ | `spiked_bulb.gd`, parry = attack as it arrives |
| After combo → long-range | ✅ | `combo_finished` |
| Long-range: moves away, 3 horizontal attacks across the arena, increasing range | ✅ | 25% / 40% / 55% of arena width |
| Long-range: player must jump over | ✅ | Low sweep, about 25px off the ground |
| Then returns to player, resumes melee | ✅ | Boss re-approaches before each swing |
| Phase 2 at < 50%: root attack unlocked, old attacks continue | ✅ | Guard on `LongRange → RootAttack` |
| Root: move to corner, channel, warning indicators | ✅ | Nearer left/right edge, purple pulse, ground warnings |
| Root: 3 large spikey roots, positions change, must reposition | ✅ | Random positions, one under the player, too tall to jump |
| Root: return to normal combat | ✅ | `root_finished → Melee` |
| Phase 3 at ≤ 10%: +10% attack speed, +10% damage | ✅ | Parallel `EnrageTrack` |
| Phase 3: red glow, crimson particles, stronger VFX | 🟡 placeholder | Glow rect, crimson particles, hotter attack flashes |
| Phase 3: more aggressive animation | ❌ | Needs real animation |
| Defeated → tree root cleansing sequence | 🟡 placeholder | Colour/particle fade to green |
| Design intent: melee → evade, sweep → jump, roots → move | ✅ | Each attack's counter is enforced by its geometry |

✅ done · 🟡 working placeholder, awaiting art · ❌ not done

**Judgement calls where the CDD is ambiguous:**
- The spiked bulb is part of Phase 1 but separate from the 3–6 melee attacks, as the CDD lists it: at most one throw per combo, 50% of the time.
- Each melee attack got its own hitbox shape. The CDD only names them, so the shapes are my reading of each name.
- "Corner" means the left or right edge, since a side-view arena has no depth.
- One root always targets the player's position, so the attack can't be ignored.
- The boss's body isn't solid. In a one-lane arena, a solid body the player can't jump over would pin them against a wall with no way to reposition.
- The player's attack auto-faces the boss, for playtest comfort.

---

## 10. Known gaps / next steps
- The boss's and arena's art and animation, and all audio, are placeholders. The player uses its final Spine art.
- The player rig has no hit or death animation, and several of its animations aren't hooked up yet (§6).
- A parry just destroys the bulb. No reflect or stagger.
- The boss keeps swinging after the player dies (press R).

## 11. Bugs fixed in the CDD alignment pass
- **Boss never aggroed** (why you could kill it for free): the player's body had moved to its own collision layer but the detection area wasn't updated. The boss sat in Idle, and because "died" was only handled inside Aggro it never reached Defeated either. Both fixed; "died" now lives on the top-level `Boss` state.
- **Dash invulnerability didn't work:** it toggled the wrong Area2D property. Replaced with a `Hurtbox.invulnerable` flag.
- **Long-range sweep always went right:** its position was mirrored twice (by code and by the parent's flip). Fixed.
- **Dead boss kept attacking:** attack coroutines now stop via `is_defeated`.
- **Errors on the killing blow:** hitboxes were toggled mid-physics-callback. Now deferred.
- **You could stand inside the boss and dodge melee:** the melee hitbox now covers the boss's own body.
- **"TREANT" rendered backwards; root spikes hard to see; bulb thrown point-blank after walking up to you; bulb could be freed twice.** All fixed.
