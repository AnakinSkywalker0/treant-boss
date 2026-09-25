# Treant Boss

A small boss fight I built in Godot 4.7. You face a corrupted Treant that gets meaner as it loses health. It swings at you up close and sweeps its roots across the ground from a distance. Once it's below half health it starts pulling spikes up out of the floor, and near the end it gets enraged and hits faster and harder.

Open the project in Godot 4.7 and press F5. The first time you open it, do Project > Reload Current Project once, otherwise the player's animations won't have imported yet.

## Controls

- A / D to move, hold Ctrl to walk
- Space to jump
- Shift to dash (you can't be hit mid-dash)
- J or left click to attack
- R to restart

Hit the spiked bulb right as it reaches you to parry it. That staggers the boss for a moment and gives you a free window to attack.

If you just want to see the later phases, press 2 or 3 to skip ahead.

More detail on how it all works is in [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).
