# Green Sapphire — Prototype Status

Snapshot of the playable prototype. Pairs with `Claude/Green Sapphire/design-bible.md`
(the locked design) and `sapphire-cast.html` (the character construction sheet).

## How to run

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Godot 4.7.2. Main scene is `scenes/main.tscn`. No external assets — every
visual is drawn in code.

## Controls

| Key | Action |
|---|---|
| WASD | Move (8-direction) |
| Space | Dodge roll (~0.18s dash, ~0.20s i-frames, 0.5s cooldown) |
| K | Light attack (fast, 1 dmg, short recovery) |
| L | Heavy attack (slow, 3 dmg, long recovery) |
| R | Restart |

## Architecture

| File | Responsibility |
|---|---|
| `scripts/game.gd` | Autoload `Game`. Locked palette constants, `hit_stop()`, session-best time/hits. |
| `scripts/player.gd` | `CharacterBody2D`. Move / dodge / attack state machine. Code-drawn 8-part rig oriented to `facing`. Afterimage trail, walk squash. Geometry-based hit on the boss (reach + arc). |
| `scripts/boss.gd` | `CharacterBody2D`. `IDLE → TELEGRAPH → ATTACK → RECOVER` state machine. Three attacks, phase 2, anticipation arm pose, body-contact damage. Geometry-based hits on the player. |
| `scripts/main.gd` | Arena rect + clamp, camera shake, camera `punch()`, particle bursts, run timer, win/lose, restart. |
| `scripts/hud.gd` | `Control`. Boss segmented HP bar, player HP pips, telegraph warning, run timer, low-HP screen-edge pulse, victory/defeat panel. |
| `scenes/main.tscn` | Wires camera, player, boss (collision shapes), HUD canvas layer. |

Combat is pure math — no `Area2D`, no collision layers beyond the two bodies
blocking each other. Every animation is a code tween (squash, stretch,
scale-pulse, rotate) or `_draw()` math. No sprite frames.

### Signals

- `player`: `died`, `health_changed(cur, max)`, `hit_taken`
- `boss`: `died`, `health_changed(cur, max)`, `phase_changed(phase)`, `telegraph_started(kind)`

`main.gd` and `hud.gd` subscribe; these are the audio hook points.

## Palette

Three greens only, from `Game`:

| Const | Hex | Use |
|---|---|---|
| `DEEP_MOSS` | `#3B4939` | arena ground, boss eye idle, sword grip, dim overlays |
| `SAPPHIRE_CORE` | `#69A062` | player, muted text/UI, boss eye mid-charge |
| `PALE_JADE` | `#BBE2B6` | boss body, blade, every telegraph / warning / hit flash |

Danger reads through brightness + motion + pulse speed, not a warning hue.
The boss eye escalates `DEEP_MOSS → SAPPHIRE_CORE → PALE_JADE` across an
attack windup — the palette itself is the telegraph timer.

**Known deviation:** the boss hit-flash uses `Color.WHITE` for ~0.12s per
hit (`boss.gd`, `_draw`). Kept deliberately; everything else stays on-palette.

## What works

- Core loop: telegraph → dodge/reposition → punish → manage HP → restart
- 8-direction movement, arena-boxed, with walk squash-and-stretch + hop
- Dodge roll with i-frames, cooldown, dust burst, fading afterimage trail
- Light + heavy attack sharing one windup/active/recovery skeleton
- Boss: slam cone, ring pulse, charge dash — each with a Pale Jade telegraph shape
- Boss eye brightness-coded windup timer
- Boss anticipation: arms raise through the windup, snap down on the attack
- Boss body-contact damage (1 dmg, 0.6s throttle) when not attacking
- Boss recoils backward after a charge instead of squatting on the player
- Phase 2 at 50% HP: timings ×0.62, 50% chance to chain a second attack
- Both health bars — boss segmented (one segment per hit), player pips
- Juice: hit-stop (scaled light/heavy), screen shake, hit particles,
  Pale Jade damage flash, camera punch-in on heavy hits / taking damage /
  phase-2 / victory
- Low-HP screen-edge Pale Jade pulse; pulse speed rises as HP drops
- Victory/defeat screen: time, hits taken, session-best comparison

## What's missing

Priority order:

1. **Audio — all 7 SFX.** None exist. Bible list: light swing, heavy swing,
   hit, dodge, boss telegraph warning, boss attack, victory/death. Hook points
   are the signals above plus `Game.hit_stop` / `main.add_shake` /
   `main.punch` / `main.spawn_burst`.
2. **Art / silhouette polish.** Rigs are placeholder-plus. The player read
   from a top-down facing angle is a blob — needs a clearer front / shoulder
   asymmetry. Bible Day 4.
3. **Session-best persistence.** Stats live in RAM only, lost on quit. Bible
   only requires within-session, so this is optional.
4. **Phase-2 in-world tell** beyond the HUD text + camera punch (bible allows
   pacing-only).
5. **Balance / tuning pass.** Bible Day 5. All knobs are in the `ATTACKS`
   dict (`player.gd`) and the `ATK` dict + `PHASE2_SPEED` (`boss.gd`).

## Tuning knobs

- Player: `SPEED`, `DODGE_*`, `ATTACKS` dict (windup/active/recovery/dmg/
  reach/arc_deg/shake/hitstop/punch per attack), `MAX_HP`
- Boss: `MAX_HP`, `PHASE2_AT`, `PHASE2_SPEED`, `MOVE_SPEED`, `RADIUS`,
  `ATK` dict (per-attack geometry + timing), idle-wait ranges in `_do_recover`
- Camera: `add_shake` cap and decay in `main.gd`, `punch()` defaults
- Arena: `ARENA_MARGIN` in `main.gd`

## Build plan status

| Day | Focus | State |
|---|---|---|
| 1 | Movement, dodge, light + heavy attack | done |
| 2 | Boss state machine + both health bars | done |
| 3 | Feedback: hit-stop, shake, particles, sound hooks | juice done, audio not wired |
| 4 | Visual pass: shapes, animation, telegraph colors, background, UI | partial — telegraph colors + UI done, rigs placeholder |
| 5 | Feedback tuning, phase-2 twist, playtest, bug fixes | phase-2 done, tuning + playtest not started |
