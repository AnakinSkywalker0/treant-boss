# Treant Boss — How It Works

A guide to this project for someone new to Godot. It covers how to run it, the Godot concepts you need (mapped to Unity/Unreal), where everything lives, how the boss "thinks", how each attack works, how the build lines up against `PK_Boss_CDD.pdf`, and how to tweak things.

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

What you'll see: yellow numbers over the boss are damage you dealt, red numbers over you are damage you took. The boss's health bar goes green → yellow at 50% (Phase 2) → red at 10% (Phase 3). The text above the boss shows its current state/attack. That text is a debug aid, not final UI.

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
| **Group** | Tag | `"player"`, `"boss"`, `"boss_arena_corner"` |
| `CharacterBody2D` | CharacterController / Character | Player and boss bodies |
| `Area2D` | Trigger collider | Hitboxes, hurtboxes, detection range |
| `await get_tree().create_timer(t).timeout` | `yield return new WaitForSeconds(t)` (coroutine) | Every attack's telegraph → active → recovery timing |
| `Tween` | DOTween / Timeline curve | Boss movement, spike growth, fades |
| **Collision layer / mask** | Physics layers + layer collision matrix | See §6 |

Two Godot quirks that matter here:
- **Y points down.** Negative Y is *up*. Characters' origins sit at their feet; the ground's top edge is `y = 0`.
- **Children inherit their parent's transform.** Mirroring a parent with `scale.x = -1` flips every child. The boss and player face left/right by flipping one `AttackOrigin` node, so all attack hitboxes and indicators flip with it.

**Editor panels:** Scene dock (node tree of the open scene, top-left), FileSystem (project files, bottom-left), Inspector (properties of the selected node, right), Output/Debugger (bottom, where `print()` and errors appear).

---

## 3. Project map

```
scenes/
  arena/test_arena.tscn     The level: ground, invisible side walls, 2 corner markers,
                            camera, controls HUD. Main scene. Script: restart on R.
  player/player.tscn        Placeholder player.
  boss/treant_boss.tscn     The boss: body, hitboxes, health bar, particles, STATE CHART.

scripts/
  boss/treant_boss.gd       Boss "body": wires the state chart to behaviour, owns the
                            reusable attack beats (swing, sweep, throw, roots, movement).
  boss/attacks/
    melee_combo.gd          Phase 1: 3–6 random attacks from the attack pool.
    long_range_attack.gd    Back off, 3 horizontal sweeps with growing reach.
    root_attack.gd          Phase 2: go to a corner, channel, 3 root spikes.
    spiked_bulb.gd          The thrown projectile (parryable).
  boss/detection_area.gd    Fires `player_detected` when the player enters range.
  common/health.gd          HP + `health_changed` / `died` signals (boss and player).
  common/hitbox.gd          Deals damage while active.
  common/hurtbox.gd         Receives damage; has an `invulnerable` flag (dash, post-hit, death).
  common/floating_text.gd   Damage numbers / "PARRY!" popups.
  player/player_controller.gd  Move, jump, dash, attack, parry window, death.
  arena/test_arena.gd       R = reload the scene.

resources/
  attack_data.gd            The AttackData resource type (like a ScriptableObject class).
  attacks/*.tres            One file per melee attack: timings, damage, colour.
  guards/*.tres             The HP-threshold conditions used by the state chart.

textures/                   Generated placeholder art (solid shapes, no real sprites yet).
addons/godot_state_charts/  Third-party plugin: the state chart system (MIT, by derkork).
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
   │  │  │    ToRootAttack ── on "ranged_finished" IF hp ≤ 50% ──► RootAttack
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
| `player_detected` | `treant_boss.gd` (from DetectionArea) | Player enters the 600px detection circle |
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
- It picks 3–6 attacks at random from `resources/attacks/`:

| Attack | Telegraph | Active | Recovery | Damage | Arrow colour |
|---|---|---|---|---|---|
| Arm Swipe | 0.5s | 0.3s | 0.4s | 10 | orange |
| Overhead Strike | 0.7s | 0.25s | 0.5s | 16 | red |
| Ground Smash | 0.6s | 0.3s | 0.6s | 14 | brown |
| Short-Range Root/Arm | 0.4s | 0.35s | 0.4s | 12 | dark brown |
| Spiked Bulb Throw | 0.6s | (flies) | 0.5s | 8 | purple |

- **Telegraph:** the body tints to the attack's colour and a small arrow appears in front of the boss. **Active:** the arrow grows to full size. That's the hit window.
- **Your answer:** dash out (invulnerable) or walk through the boss to the other side. Its body isn't solid, only its attacks hurt.
- **Spiked Bulb:** thrown from where the boss stands and flies straight toward you. Parry it (attack as it arrives, "PARRY!" pops up) or dash through it.

### Phase 1: Long-range sweeps (after every combo)
- The boss backs off about 260px, then does **3 sweeps with growing reach: 160 → 270 → 380px**.
- **Telegraph:** a thin yellow line along the ground shows exactly how far the sweep will reach. **Active:** it turns into a thick red bar near the ground.
- **Your answer: jump.** The bar sits about 25px off the ground and a jump clears about 80px. Or stand beyond the yellow line, but the next sweep reaches further.
- Afterwards the boss returns to Melee (or goes to Root Attack if it's below 50% HP).

### Phase 2: Root Attack (unlocks at ≤ 50% HP)
- Checked after every long-range sequence. Below 50% the boss goes to Root Attack instead of straight back to Melee, then sits out the next check (a one-cycle cooldown via the `root_ready` expression property), so roots come every other loop.
- It moves to the left or right arena edge (the "corners" in a side-view arena) and **channels** for 1.3s, pulsing purple.
- During the channel, **3 warnings** appear on the ground: a pulsing red crack plus a faint outline of the spike. **One always spawns under you.**
- Then 3 spikes erupt for 1.4s: 170px tall, taller than your jump, 15 damage.
- **Your answer: move** to a spot without a warning (CDD: "reposition rather than simply jump in place").

### Phase 3: Enraged (at ≤ 10% HP)
- Same attacks, **+10% attack speed and +10% damage** (every telegraph, active and recovery time is divided by 1.1).
- Visuals: red body, pulsing red glow behind it, particles turn crimson and get denser, attack indicators and the bulb are drawn 30% bigger.

### Defeated → cleansing
- At 0 HP the boss stops mid-attack, turns invulnerable, the health bar hides, and the **cleansing sequence** plays: the body fades from corruption to healthy green and the particles turn green and drift up. Press R to fight again.

### Idle (before the fight)
- The boss stands still with a slow "breathing" squash (placeholder idle animation) while purple **corruption particles** rise around its feet (CDD: "environmental corruption continues around the boss").

---

## 6. Combat plumbing (how damage actually happens)

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

## 7. How to tweak things (no code needed for most)

| I want to change… | Where |
|---|---|
| Boss HP (currently 800; the enrage phase is its last 10%, so HP also sets how long that phase lasts) | `treant_boss.tscn` → select `Health` → Inspector → Max Health |
| Player HP (100) | `player.tscn` → `Health` → Max Health |
| A melee attack's timing/damage/colour | Double-click `resources/attacks/<name>.tres` → Inspector |
| Phase thresholds (50% / 10%) | Double-click `resources/guards/*.tres` → edit the expression |
| Detection range (600px) | `treant_boss.tscn` → `DetectionArea/CollisionShape2D` → Shape → Radius |
| Sweep reach, root size/timing, enrage multiplier, approach distance | Constants at the top of `scripts/boss/treant_boss.gd` |
| Player speed, jump, dash, attack damage | Constants at the top of `scripts/player/player_controller.gd` |

**Adding a new melee attack:** in the FileSystem dock, right-click an existing `resources/attacks/*.tres` → Duplicate, edit its values in the Inspector, then add its path to `ATTACK_RESOURCE_PATHS` at the top of `treant_boss.gd`. The combo picks it up automatically.

**When real art arrives:** swap each `Sprite2D`'s texture in the Inspector. On the boss, tick **Flip Sprite With Facing** on the `TreantBoss` root node. It's off only because the placeholder texture has the word "TREANT" baked in, which would read backwards when mirrored.

---

## 8. CDD tally

| CDD item | Status | Notes / where |
|---|---|---|
| Idle: stationary until player in range | ✅ | `Idle` state, `DetectionArea` (600px) |
| Idle: idle animation | 🟡 placeholder | Breathing squash tween |
| Idle: environmental corruption around boss | 🟡 placeholder | `CorruptionParticles` |
| Idle: does not attack | ✅ | Nothing runs in `Idle` |
| Aggro starts with melee pattern | ✅ | `AttackPattern` initial state = `Melee` |
| Melee combo: random 3–6 of swipe / overhead / smash / short root | ✅ | `melee_combo.gd` + `resources/attacks` |
| Player evades melee | ✅ | Dash i-frames, boss body not solid |
| Spiked bulb throw, parryable | ✅ | `spiked_bulb.gd`, parry = attack as it arrives |
| After combo → long-range | ✅ | `combo_finished` |
| Long-range: moves away, 3 horizontal attacks, increasing range | ✅ | 160 / 270 / 380px |
| Long-range: player must jump over | ✅ | Low sweep, about 25px off the ground |
| Then returns to player, resumes melee | ✅ | Boss re-approaches before each swing |
| Phase 2 at < 50%: root attack unlocked, old attacks continue | ✅ | Guard on `LongRange → RootAttack` |
| Root: move to corner, channel, warning indicators | ✅ | Left/right edge, purple pulse, ground warnings |
| Root: 3 large spikey roots, positions change, must reposition | ✅ | Random positions, one under the player, too tall to jump |
| Root: return to normal combat | ✅ | `root_finished → Melee` |
| Phase 3 at ≤ 10%: +10% attack speed, +10% damage | ✅ | Parallel `EnrageTrack` |
| Phase 3: red glow, crimson particles, stronger VFX | 🟡 placeholder | Glow rect, crimson particles, 1.3× indicators |
| Phase 3: more aggressive animation | ❌ | Needs real animation |
| Defeated → tree root cleansing sequence | 🟡 placeholder | Colour/particle fade to green |
| Design intent: melee → evade, sweep → jump, roots → move | ✅ | Each attack's counter is enforced by its geometry |

✅ done · 🟡 working placeholder, awaiting art · ❌ not done

**Judgement calls where the CDD is ambiguous:**
- The spiked bulb is one of the random picks inside the melee combo. The CDD lists it right after the combo, so this is the literal reading.
- "Corner" means the left or right edge, since a side-view arena has no depth.
- One root always targets the player's position, so the attack can't be ignored.
- The boss's body isn't solid. In a one-lane arena, a solid body the player can't jump over would pin them against a wall with no way to reposition.
- The player's attack auto-faces the boss, for playtest comfort.

---

## 9. Known gaps / next steps
- All art, animation and audio are placeholders.
- `AttackData.range` isn't used yet. All melee swings share one hitbox size. Next step: size the hitbox per attack.
- A parry just destroys the bulb. No reflect or stagger.
- The boss keeps swinging after the player dies (press R).

## 10. Bugs fixed in the CDD alignment pass
- **Boss never aggroed** (why you could kill it for free): the player's body had moved to its own collision layer but the detection area wasn't updated. The boss sat in Idle, and because "died" was only handled inside Aggro it never reached Defeated either. Both fixed; "died" now lives on the top-level `Boss` state.
- **Dash invulnerability didn't work:** it toggled the wrong Area2D property. Replaced with a `Hurtbox.invulnerable` flag.
- **Long-range sweep always went right:** its position was mirrored twice (by code and by the parent's flip). Fixed.
- **Dead boss kept attacking:** attack coroutines now stop via `is_defeated`.
- **Errors on the killing blow:** hitboxes were toggled mid-physics-callback. Now deferred.
- **You could stand inside the boss and dodge melee:** the melee hitbox now covers the boss's own body.
- **"TREANT" rendered backwards; root spikes hard to see; bulb thrown point-blank after walking up to you; bulb could be freed twice.** All fixed.
