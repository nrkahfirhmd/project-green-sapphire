# Handoff: Green Sapphire UI

## Overview
This bundle is the full interface for **Green Sapphire**, a landscape-only top-down action game for iPhone that runs in Godot. It covers Home, Settings, the Jail hub HUD, the Fight HUD with touch controls, Result (victory and defeat), Pause, the Boss intro card and the Ending, plus a states board. The world is ASCII. The UI is the only layer that is not ASCII, but it echoes the ASCII look: monospace type, square frames with corner ticks, and diamonds made from rotated squares.

## About the Design Files
The `.dc.html` files are **design references built in HTML**, not production code. Rebuild them in the game's own engine (Godot: Control nodes, `_draw()` and Theme resources) using its usual patterns. Open `Green Sapphire UI.dc.html` in a browser to view every artboard. `Guides.dc.html` only draws the safe-area annotation overlay and does not ship. `ui-brief.md` is the original brief and lists every hard constraint.

## Fidelity
**High fidelity.** Colours, type, sizes, offsets and motion are final. Recreate them exactly.

## Canvas, anchoring, safe area
- Base canvas is **1950 × 900** units. On 16:9 phones the canvas grows to 1950 × 1097 (taller, never wider), so anchor everything to edges or corners.
- Safe area: **135** units inset on the left and on the right (the notch can be on either side), **48** at the bottom, **0** at the top.
- **Safe TL** = (135, 0). **Safe BR** = (1815, 852). The centre x is 975.
- Background art and full-screen effects (overlays, low-HP bands) run edge to edge. Text and controls stay inside the safe area.
- Minimum tap target is 100 units across. The right third holds only the action buttons.
- The game is **mobile-only**, so no keyboard hints appear anywhere in the UI.

## Design Tokens
**Colours.** Only these three hexes, at any alpha. No other hue, no white, no black.
- Deep Moss `#3B4939`: backgrounds, panels, tracks, overlays
  - panel 90 %, idle button fill 60 %, action button fill 45 %
  - result overlay 72 %, pause overlay 82 %, boss-intro dim 40 %, intro band 92 %
- Sapphire Core `#69A062`: all default text, icons and strokes
  - idle stroke 60 %, secondary text 75 %, captions 60 %, disabled 30 %
  - selected fill 15 %, pressed fill 100 % on menus and 50 % on HUD
- Pale Jade `#BBE2B6`: **signal only**, in exactly five places
  - boss health fill and spare-bar squares
  - low-HP edge bands
  - the hit flash on a lost heart
  - a dropped sapphire
  - the gate-lamp opening
  - Never use it for buttons, headings or selection.

**Type.** IBM Plex Mono from Google Fonts, bundled as TTF, weights 400 and 600.

| Role | Weight · size | Letter-spacing |
|---|---|---|
| Title | 600 · 112 | 0.20 em |
| Display: VICTORY, DEFEAT | 600 · 80 | 0.30 em |
| Display: boss-intro name | 600 · 112 | 0.25 em |
| Heading | 600 · 48–56 | 0.20–0.30 em |
| Menu button | 600 · 28–36 | 0.20 em |
| Action button label | 600 · 18 | 0.12 em |
| HUD: boss name | 600 · 20 | 0.15 em |
| HUD: objective | 600 · 26 | 0.12 em |
| HUD: carry chip | 600 · 22 | 0.15 em |
| Timer | 400 · 24, tabular figures | — |
| Caption | 400 · 14–16 | 0.20 em |

All UI text is uppercase.

**Strokes, radii, ornament**
- Strokes are 2 units everywhere, except the dodge cooldown ring at 6.
- Radius is 0 everywhere, with these exceptions:
  - boss bar 6
  - spare-bar squares 5
  - circles (action buttons, stick)
- Panel frame: a 2-unit Core stroke plus 8 × 8 solid Core squares centred on each corner.
- Diamonds are squares rotated 45°.
- No gradients, no shadows, no images.

## Screens
All positions are in canvas units.

### 01 Home
- **Title block**, centred, top +150, flex column with gap 28:
  - Caption "A JAIL OF FIVE CELLS": 400 · 20, 0.4 em, Core 75 %, flanked by 120 × 2 lines.
  - Framed title "GREEN SAPPHIRE": 600 · 112, padding 28 × 64.
  - Ornament row of five diamonds, gap 34: four 18 × 18 outlines and a centre 28 × 28 filled.
- **Buttons** PLAY and SETTINGS: 400 × 100, gap 16, margin-top 24. PLAY is shown in the selected state.

### 02 Settings
- **Framed panel**, 960 wide, centred, top +120, padding 48 × 64, gap 32.
- Heading "SETTINGS", then a 2-unit divider at Core 40 %.
- **VOLUME row** (100 tall, shown selected):
  - 10 blocks, each 32 × 40, gap 8.
  - Filled blocks are Core; empty blocks are a Core 45 % outline.
  - The value "70" sits to the right.
- **HAPTICS** segmented control: ON / OFF, each 150 × 100.
  - Active: Core fill with Moss text.
  - Inactive: Core 60 % outline.
- **BACK** button: 300 × 100.

### 03 Jail hub HUD
- **Pause button**: Safe TL +24, +24. Size 100 × 100; two bars 10 × 36, gap 12.
- **Objective**: top centre, y +28. Text "TAKE A SAPPHIRE FROM EVERY CELL", then four 16 × 16 diamonds (filled = set, outline = missing), then "2 / 4".
- **Carry chip**: top centre, y +82, shown only while carrying.
  - Height 52, padding 0 × 24, Core fill.
  - Moss 18 × 18 diamond plus the text "CARRYING SAPPHIRE III".
- **Carried sapphire in the world**: a 20 × 20 Core diamond 40 units above the player, bobbing 6 units on a 1.2 s sine.
- **Cell labels**, anchored to each cell's top in the world: numeral 600 · 30 plus name 400 · 16, centred. Cleared cells set the whole group to 35 % and add the caption "CLEARED" or "SAPPHIRE TAKEN".
- **Gate V**: place it at bottom centre in the world (x 860–1090) so it stays clear of HEAVY (x ≥ 1460).
  - Four lamps Ø 20, gap 16, above the gate.
  - Empty: outline. Set: Core fill. Gate opening: all four turn Jade.
- **Touch controls**: same as the Fight HUD.

### 04 Fight HUD
Two artboards: notch left, and notch right with the low-HP state. The layout is identical because everything is anchored to the safe area.
- **Pause button**: Safe TL +24, +24, 100 × 100.
- **Hearts**: Safe TL +152, +32.
  - Four heart shapes, 28 × 26 each, gap 10.
  - Full: Core fill. Empty: Core 60 % stroke 2, no fill.
  - SVG path, viewBox 28 × 26: `M14 24 L3.5 13.5 A6.2 6.2 0 0 1 14 5 A6.2 6.2 0 0 1 24.5 13.5 Z`. In Godot this can be a polygon plus two arcs, or a 12-point polygon.
- **Run timer**: Safe TL +152, +70, 400 · 24, format `m:ss.cc`.
- **Boss block**: top centre, 560 wide, flex column with gap 8, starting at y +20.
  - Name "III · THE BELL", 600 · 20, centred.
  - Health bar 560 × 22, radius 6, Core stroke 2, Moss track. The Jade fill width is current HP / max HP for the current bar.
  - **Spare bars** row, right-aligned below the bar: one 24 × 24 square (radius 5, gap 10, Core stroke 2) per extra full health bar the boss still has. Remaining squares are Jade-filled; used ones are outline only.
  - When the current bar empties and a spare remains, the rightmost Jade square empties and the bar refills.
- **Low HP** (2 hearts or fewer): 14-unit Jade bands on all four screen edges, full-bleed, pulsing (see Motion).

### 05 Touch controls
All centres are offsets from a safe-area corner.

| Control | Anchor | Centre offset | Radius |
|---|---|---|---|
| Stick (resting hint) | Safe BL | +150, −170 | ring 115, knob 50 |
| HEAVY | Safe BR | −130, −150 | 70 |
| LIGHT | Safe BR | −295, −77 | 60 |
| DODGE | Safe BR | −160, −322 | 58 |

- **Stick**: it floats to wherever the left thumb lands in the left half of the screen.
  - Resting: ring Core 35 % stroke 2; knob Core 20 % fill with a 35 % stroke.
  - Active: ring Core 60 %; knob Core 50 % fill.
- **Action buttons**: label 600 · 18, centred.

| State | Fill | Stroke | Label | Scale |
|---|---|---|---|---|
| Idle | Moss 45 % | Core 60 % | Core | 1 |
| Pressed | Core 50 % | none | Moss | 0.94 |
| Disabled | none | Core 30 %, dashed | Core 30 % | 1 |
| Dodge cooldown | Moss 45 % | Core 25 % base ring | Core 40 % | 1 |

- **Dodge cooldown**: a Core arc (stroke 6, radius 53) sweeps clockwise from 12 o'clock, 0 → 360° over 0.5 s, on top of the 25 % base ring.

### 06 Result
All results sit on a 72 % Moss overlay over the frozen fight.
- **Victory**: centred column, top +80, gap 28.
  - Caption "CELL II · THE HOUND FALLS".
  - "VICTORY".
  - Sapphire emblem: a 76 × 76 outlined diamond with a 44 × 44 filled one inside, flanked by 80 × 2 lines.
  - Caption "SAPPHIRE II WON".
  - Stats grid with three columns (label / THIS RUN / BEST), gap 14 × 56, values right-aligned so long values stay centred. Rows: TIME and HITS TAKEN. A new best gets a "NEW" chip: Core fill, Moss text, 600 · 14.
  - CONTINUE button 400 × 100, selected.
- **Defeat**: top +220.
  - "DEFEAT" at Core 75 %.
  - One stats line: boss, time, hits, best.
  - **RETRY** 480 × 120, selected and placed first, plus BACK TO JAIL 360 × 120, gap 24.
  - Appears after 0.4 s.

### 07 Pause
- 82 % Moss overlay. The pause button shows its pressed state: Core 50 % fill with Moss bars.
- **Framed panel**, 640 wide, centred, top +120, padding 48, gap 16:
  - "PAUSED" 600 · 48.
  - Caption "III · THE BELL · 0:42.17".
  - Buttons RESUME (selected), BACK TO JAIL and SETTINGS, each 480 × 100.

### 08 Boss intro, 1.6 s
- The fight is dimmed with a 40 % Moss overlay.
- **Band**: full-bleed, y 330–570, Moss 92 %, 2-unit Core lines top and bottom.
- Inside the band: "◆ CELL III ◆" (600 · 24, 0.5 em, 14 × 14 diamonds), then the name "THE BELL" at 600 · 112.

### 09 Ending
- **Emblem**, 220 × 220: a 120 × 120 outlined diamond, four 44 × 44 filled diamonds at its points, and a 52 × 52 filled diamond in the centre.
- "THE GREEN SAPPHIRE IS WHOLE" at 600 · 56.
- Caption line with total time and hits.
- RETURN HOME button 440 × 100, selected.

## Interactions & Motion
Tweens only.

| What | Change | Duration and easing | Notes |
|---|---|---|---|
| Button press | scale 1 → 0.94 (HUD) / 0.97 (menu) | 0.06 s ease-out | Release: back to 1 over 0.10 s ease-out |
| Selected marker | ▸ slides x −8 → 0; fill 0 → 15 % | 0.12 s ease-out | Replaces the old white hover |
| Boss damage | Fill width shrinks | 0.18 s ease-out | A Core 50 % trailing chunk follows after 0.3 s |
| Boss bar emptied, spare left | Rightmost square empties, scale 1.3 → 1; bar refills | refill 0.4 s | |
| Heart lost | Jade at scale 1.2 → 1 | 0.15 s, then 0.2 s fade | Ends on the empty outline |
| Low HP, 2 hearts | Band alpha 0.15 ↔ 0.45 | 1.0 s period, sine | |
| Low HP, 1 heart | Band alpha 0.25 ↔ 0.70 | 0.5 s period, sine | |
| Dodge ready | Label 40 % → 100 %; button scale 1.08 → 1 | 0.12 s | Fires when the arc completes |
| Carry chip | Slide y −20 → 0 plus fade | 0.2 s ease-out | Reverses on deposit |
| Dropped sapphire | Jade diamond, scale 1 ↔ 1.25 | 0.8 s pulse | |
| Boss intro | See below | 1.6 s total | Input locked until the fade-out starts |
| Result / pause appear | Overlay fades; panel y +24 → 0 | 0.25 s ease-out | |
| Gate opening | Lamps Core → Jade, pulse 3× | 0.3 s each | The only Jade moment outside combat |

Boss intro sequence:
1. Band scaleY 0 → 1, 0.15 s ease-out.
2. Name slides x +40 → 0 and fades in, 0.25 s.
3. Hold 1.0 s.
4. Fade out, 0.2 s.

## State Management
- **Fight**:
  - boss HP for the current bar
  - max HP per bar
  - spare bars remaining
  - player hearts (0–4)
  - run time
  - dodge cooldown remaining (0–0.5 s)
  - pressed state per button
  - stick origin and offset
  - paused flag
- **Hub**:
  - sapphires set (0–4)
  - carried sapphire id, or none
  - cleared cells
  - gate open
- **Result**: win or loss, time, hits, best time, best hits, and a new-best flag for each.

## Assets
None. Everything is drawn from rectangles, circles, lines, polygons and text in the three colours.

Optional items that go beyond those basic shapes:
- The dodge arc: use `draw_arc`. Fallback: fill the circle bottom-up with a clipped rect.
- The heart shape.
- Diamonds, which are 4-point polygons.

Boss names other than THE MIRROR (THE WARDEN, THE HOUND, THE BELL, THE CHAIN) are placeholders.

## Files
- `Green Sapphire UI.dc.html`: all artboards, the states board and the spec sheet. Open it in a browser.
- `Guides.dc.html`: the safe-area and notch annotation overlay. Reference only.
- `ui-brief.md`: the original brief and its constraints.
