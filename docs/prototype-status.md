# Green Sapphire — Prototype Status

Snapshot of the playable prototype. Pairs with `Claude/Green Sapphire/design-bible.md`
(the locked design) and `sapphire-cast.html` (the character construction sheet).

## How to run

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Godot 4.7.2. Main scene is `scenes/main.tscn`, at a 1600x900 viewport
(`canvas_items` stretch, so it scales to any window). No external assets —
every visual is drawn in code.

Smoke check for the rigs — poses both characters through every animated state
and redraws each, so a broken `_draw` fails here instead of mid-fight:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . tools/anim_check.tscn
```

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
| `scripts/game.gd` | Autoload `Game`. Locked palette constants, `hit_stop()`, `ellipse()` for the ground shadows, session-best time/hits. |
| `scripts/player.gd` | `CharacterBody2D`. Move / dodge / attack state machine. Upright 3/4 rig standing on its ground position, every part on a Deep Moss backing. Afterimage trail, stepping walk cycle, dodge tumble. Geometry-based hit on the boss (reach + arc). |
| `scripts/boss.gd` | `CharacterBody2D`. `IDLE → TELEGRAPH → ATTACK → RECOVER` state machine. Three attacks, phase 2, anticipation arm pose, body-contact damage. Geometry-based hits on the player. |
| `scripts/main.gd` | Arena rect + clamp, camera shake, camera `punch()`, particle bursts, run timer, win/lose, restart. |
| `scripts/hud.gd` | `Control`. Boss segmented HP bar, player HP pips, telegraph warning, run timer, low-HP screen-edge pulse, victory/defeat panel. |
| `scenes/main.tscn` | Wires camera, player, boss (collision shapes), HUD canvas layer. |
| `tools/anim_check.tscn` | Dev-only smoke check; not part of the game. |

Combat is pure math — no `Area2D`, no collision layers beyond the two bodies
blocking each other. Every animation is a code tween (squash, stretch,
scale-pulse, rotate) or `_draw()` math. No sprite frames.

### Signals

- `player`: `died`, `health_changed(cur, max)`, `hit_taken`
- `boss`: `died`, `health_changed(cur, max)`, `phase_changed(phase)`, `telegraph_started(kind)`

`main.gd` and `hud.gd` subscribe; these are the audio hook points.

## Perspective

The camera looks down at roughly 60 degrees, not straight overhead. In
practice that means:

- **The ground plane is drawn 1:1.** A world circle is drawn as a circle, so
  every hit test stays plain world-space math and no telegraph can drift out
  of sync with its own hitbox. Squashing the floor into ellipses would look
  more like a real 60-degree camera but would desync all three boss attacks.
- **`global_position` is where a character stands on the floor**, and the body
  is drawn above it — the player from its feet, the boss lifted by `LIFT` so
  the point of the prism hangs just over its own shadow. Collision shapes and
  attack geometry are therefore ground footprints.
- **The player does not rotate with `facing`.** Turning is a horizontal mirror
  (`_face_x`) plus a front/back pose: the eyes only draw on the side of the
  head the camera can see, and the sword arm moves behind the body when it
  walks away.
- **Anything aimed along the ground is projected** through `_project()`, which
  squashes screen Y by `TILT` (0.5). That is what makes a swing toward the
  camera read long and one away from it read short, and it flattens the swing
  arc into an ellipse.
- Both fighters cast a Deep Moss ground shadow, and `Main` has `y_sort_enabled`
  so whoever stands nearer the camera draws in front.

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

**Known deviations:** the boss hit-flash uses `Color.WHITE` for ~0.12s per hit
(`boss.gd`, `_draw`). The arena floor is Deep Moss mixed 13% toward Sapphire
Core, so the ground shadows have something to darken — a blend of two locked
colours rather than a fourth hue. Both kept deliberately.

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
- Player rig: upright 3/4 figure — head, torso, two legs, off arm, sword arm —
  sized so the boss reads at roughly the bible's 2:1. `RIG` scales the lot
- Player animation: stepping walk cycle with a body bob, idle breathing, a
  tumble about the waist through the dodge roll, wind-back/sweep/settle on the
  sword arm, jitter on damage
- Eight-way posing without eight sprite sets: mirror plus front/back plus a
  projected sword angle
- Boss animation: idle bob + facet shimmer + eye blink, arms that raise
  overhead through the windup with fingers splaying wider as it nears,
  telegraph tremble and heartbeat pulse, per-attack pose (lean into the aim,
  stretch along a charge, swell on a ring), hurt jitter, death spin-and-shrink
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
2. **Art / silhouette polish.** The player reads as a standing swordsman from
   every facing. Still rough: there is no distinct back-of-head treatment
   beyond dropping the eyes, and the boss keeps one pose for all eight
   directions. Bible Day 4.
3. **Session-best persistence.** Stats live in RAM only, lost on quit. Bible
   only requires within-session, so this is optional.
4. ~~Phase-2 in-world tell~~ — done: fracture lines across the boss body plus a
   faster idle bob, on top of the HUD text and camera punch.
5. **Balance / tuning pass.** Bible Day 5. All knobs are in the `ATTACKS`
   dict (`player.gd`) and the `ATK` dict + `PHASE2_SPEED` (`boss.gd`).

## Tuning knobs

- Player: `RIG` (whole-rig scale), `OUTLINE`, `TILT` (camera foreshortening),
  `SPEED`, `DODGE_*`, `ATTACKS` dict (windup/active/recovery/dmg/
  reach/arc_deg/shake/hitstop/punch per attack), `MAX_HP`
- Boss: `MAX_HP`, `PHASE2_AT`, `PHASE2_SPEED`, `MOVE_SPEED`, `RADIUS`, `LIFT`,
  `ATK` dict (per-attack geometry + timing), idle-wait ranges in `_do_recover`
- Camera: `add_shake` cap and decay in `main.gd`, `punch()` defaults
- Arena: `ARENA_MARGIN` and `ARENA_TOP` (headroom for the tall boss) in
  `main.gd`; viewport size in `project.godot`

## Build plan status

| Day | Focus | State |
|---|---|---|
| 1 | Movement, dodge, light + heavy attack | done |
| 2 | Boss state machine + both health bars | done |
| 3 | Feedback: hit-stop, shake, particles, sound hooks | juice done, audio not wired |
| 4 | Visual pass: shapes, animation, telegraph colors, background, UI | mostly done — telegraph colors, UI, and both rigs + animation passes done |
| 5 | Feedback tuning, phase-2 twist, playtest, bug fixes | phase-2 done, tuning + playtest not started |
