# Treant Boss

A 2D side-view boss fight in **Godot 4.7**: a corrupted Treant with three phases, built on a state chart.

## Run it

1. Clone the repo and open the folder in **Godot 4.7** (the standard build, not .NET).
2. Press **F5**.

That's it. Everything it needs is in the repo, including the two plugins it uses.

## Controls

| Key | Action |
|---|---|
| A / D | Move (hold **Ctrl** to walk) |
| Space | Jump |
| Shift | Dash (you can't be hit while dashing) |
| J or left-click | Attack. Hit the spiked bulb as it reaches you to **parry** it and stagger the boss. |
| R | Restart |
| 2 / 3 | Skip the boss to phase 2 / phase 3 (for testing) |

## The fight

Walk past the red line to wake the boss.

- **Phase 1:** a combo of 3–6 melee swings, sometimes with a thrown spiked bulb, then 3 long-range sweeps along the ground. Dodge the swings, jump the sweeps.
- **Phase 2 (below 50% HP):** it also runs to a corner and summons root spikes from the ground. Move off the red warnings.
- **Phase 3 (10% HP):** enraged. Attacks are 10% faster and hit 10% harder.

Every attack shows where it will land before it hits.

## How it's built

- **Boss AI:** a [Godot State Charts](https://github.com/derkork/godot-statecharts) state chart in `scenes/boss/treant_boss.tscn`. It controls every beat of every attack and when it happens. Scripts in `scripts/boss/` only handle what each state looks like and what it hits.
- **Attack tuning:** each attack's timing and damage is a resource in `resources/attacks/`.
- **Player:** an animated [Spine](https://esotericsoftware.com/) character. The Spine runtime is in `bin/spine/`.

For the details (the full state chart, every attack, and what to tweak where), see **[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md)**.

## Status

The boss and arena use placeholder art. The player uses final art. There's no audio yet.
