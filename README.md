# Treant Boss — Progress Notes

## Context
Take-home assignment for a Godot programmer role. Coming from a Unity/Unreal
background (Unity state machines, Unreal State Trees + Blackboards). Goal:
implement the Treant boss fight described in `PK_Boss_CDD.pdf`, using an
event-based state machine approach, third-party plugin allowed per the
studio's instructions.

## Decisions made
- **Engine:** Godot 4.7 (stable), Forward+ renderer (desktop/PC target).
- **State machine approach:** [Godot State Charts](https://github.com/derkork/godot-statecharts)
  by derkork — a Harel-statechart plugin (hierarchical + parallel states,
  event-driven transitions, guard expressions). Closest match in Godot to the
  Unreal State Tree / Blackboard pattern already familiar from past work.
  Chosen over hand-rolling a custom FSM (would show less Godot-native
  knowledge) and over LimboAI (heavier behavior-tree/blackboard framework,
  more than this fight needs).

## Environment setup completed
- [x] Godot 4.7 installed.
- [x] Project created: `D:\treant-boss`, Git version-control metadata enabled.
- [x] `Godot State Charts` addon installed (Asset Store, submitted by
      `derkork`, MIT) and enabled in Project Settings (`editor_plugins/enabled`).

## Current status
- Playable 2D side-view prototype with placeholder art: `scenes/arena/test_arena.tscn`
  is the main scene (F5 in Godot).
- Full boss flow per the CDD is implemented and verified live: Idle → Aggro
  (Melee combo ↔ Long-range sweeps, Root Attack below 50% HP, parallel Enraged
  region at ≤10% HP) → Defeated / cleansing.
- **See [`docs/HOW_IT_WORKS.md`](docs/HOW_IT_WORKS.md)** for controls, the
  Godot concepts used, the state chart, every attack, a CDD tally, and how to
  tweak values.

## Source document
`PK_Boss_CDD.pdf` — Treant Boss creature design doc: 3 combat phases
(melee+ranged, root hazard at <50% HP, enraged stat buffs at ≤10% HP), each
attack type mapped to a distinct player response (evade / jump / reposition).
