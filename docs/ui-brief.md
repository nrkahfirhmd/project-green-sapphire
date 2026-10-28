# Green Sapphire: UI design brief

For Claude Design. Everything needed to design the game's interface is in this
file; you do not need the codebase.

## The game in one paragraph

A top-down action game for iPhone, played in landscape. A lone swordsman is
locked in a jail with five cells. Four cells each hold a boss guarding a
sapphire; beat the boss, carry its sapphire to the altar in the middle of the
jail, and once four are set the great gate opens on the final boss, the
Mirror. Each fight is short and readable: the boss telegraphs, the player
dodges, then punishes. The whole world is drawn as ASCII glyphs in three
greens. The interface is the only thing on screen that is *not* ASCII.

## What to design

The current UI works but was placed by eye in code: default font, hard-coded
offsets, no shared style. Design one coherent interface for these screens.

| # | Screen | Exists today | What it needs |
|---|---|---|---|
| 1 | Home | Title, PLAY, SETTINGS | A title treatment worth the game; menu styling |
| 2 | Settings | Volume slider, Haptic toggle, BACK | Same style as Home |
| 3 | Jail hub HUD | Objective line, cell numerals I–V, 4 lamps over the gate | A way to see you are **carrying** a sapphire (missing today); boss names on the cells |
| 4 | Fight HUD | Boss health bar and name, phase 2 tag, player hearts, run timer, "! INCOMING", low-HP screen-edge pulse | Hierarchy; a home for the timer away from the notch |
| 5 | Touch controls | Floating stick, HEAVY / LIGHT / DODGE buttons | Pressed state, and a **dodge cooldown** state (missing today) |
| 6 | Result | VICTORY / DEFEAT, time, hits taken, best time, best hits, CONTINUE or RESTART | Victory should show the sapphire won; defeat should be quick to retry |
| 7 | New: Pause | Does not exist | A pause button in the fight HUD and a pause sheet (resume, back to jail, settings) |
| 8 | New: Boss intro | Does not exist | A 1–2 second title card when a fight starts: boss name and cell numeral |
| 9 | New: Ending | Only a one-line hint today | "The Green Sapphire is whole": a short closing screen |

## Hard constraints

### Canvas and safe areas

- **Landscape only**, either way up. Base canvas **1950 × 900** units (iPhone
  15/16 Pro shape, 19.5:9). Design all mockups at this size.
- On 16:9 phones the canvas grows taller (1950 × 1097), never wider, so anchor
  everything to **edges and corners**, not to fixed coordinates.
- **Safe area at 1950 × 900:** about **135 units** on the left and on the right
  (the notch is on whichever side the phone is turned to; design for both), and
  about **48 units** at the bottom (home indicator). Top has no inset in
  landscape. Show these as guides on every mockup.
- Background art and full-screen effects run edge to edge; text and controls
  stay inside the safe area.

### Palette: three colours, no exceptions

| Name | Hex | Role in the UI |
|---|---|---|
| Deep Moss | `#3B4939` | Backgrounds, panels, outlines, dimmed overlays |
| Sapphire Core | `#69A062` | Default UI colour: text, icons, idle buttons, hearts |
| Pale Jade | `#BBE2B6` | **"Look now" only**: danger, boss health, warnings, hit flashes |

- Any alpha of these three is allowed. No other hue, no white, no black.
- **Pale Jade is a signal, not decoration.** In the game it means an attack is
  coming. Using it for a button or a heading would teach the player to ignore
  it. Reserved uses: boss health, telegraph and warning text, the low-HP pulse,
  the dropped sapphire, the gate opening.
- There is no red. Urgency is carried by brightness, pulse speed and motion.

### Look and feel

- The world behind the UI is ASCII: glyphs on a 4 × 5 unit grid, with density
  standing in for brightness. The UI layer sits on top, crisp and not
  converted. You may echo the ASCII world (monospace type, box-drawing frames,
  glyph-built ornaments) or deliberately contrast it. Choose one and apply it
  everywhere.
- Flat shapes only: rectangles, circles, lines, text. No gradients, no
  shadows, no images. Everything must be drawable in code.
- One font family, possibly two weights, from Google Fonts (it will be bundled
  as a TTF). Today it is Godot's default sans, which looks generic.
- Motion is limited to tweens: fade, scale, slide, pulse. Name the motion you
  want; don't animate it frame by frame.

### Touch

- Minimum tap target **100 units across** (44 pt on the device).
- The stick floats: it appears wherever the left thumb lands in the left half
  of the screen. Its resting position is only a hint.
- The right thumb owns the action buttons. Keep the right third free of
  anything else that is tappable.
- The game is also playable with a keyboard (WASD, Space, K, L, R), so no
  information may exist only as touch UI.

## Current layout, for reference

All values are in canvas units, relative to the safe area.

**Fight HUD**
- Boss bar: top centre, 26 above the top edge; one 26 × 12 segment per health
  point (12 or 16 segments), 4 apart. Filled segments Pale Jade, empty ones
  Deep Moss, Sapphire Core outline.
- Boss name: 14 px Sapphire Core under the bar's left end. "PHASE 2": 14 px
  Pale Jade under its right end.
- Player hearts: bottom left, 4 circles of radius 10, 30 apart. Full ones
  Sapphire Core, empty ones outlined.
- Run timer: top left, 18 px Sapphire Core, `m:ss.cc`.
- "! INCOMING": 22 px Pale Jade, top centre below the bar, fades over 0.6 s
  whenever a boss starts an attack.
- Low HP (2 hearts or fewer): 14 px Pale Jade bands on all four screen edges,
  pulsing faster as health drops.

**Touch controls**
- Stick: radius 115 with a knob of radius 50; resting at 250 / 250 from the
  bottom-left corner.
- HEAVY radius 70, LIGHT radius 60, DODGE radius 58, clustered at the bottom
  right. 16 px labels.
- Idle: Deep Moss fill at 45 %, Sapphire Core outline at 60 %. Pressed:
  Sapphire Core fill at 50 %, Deep Moss label.
- Dodge has a 0.5 s cooldown that nothing shows today.

**Result**: Deep Moss overlay at 72 % over the frozen fight; 40 px title, 18 px
lines, left-aligned by fixed offsets. The CONTINUE or RESTART button (radius 62)
sits at 72 % of the screen height.

**Jail hub**: a 26 px objective line at the top centre (for example "TAKE A
SAPPHIRE FROM EVERY CELL  2 / 4"); 30 px numerals above each cell, dimmed to
35 % once cleared; four lamps (radius 8) above gate V filling as sapphires are
set. None of it respects the safe area yet.

**Home / Settings**: 64 px title, 360 × 88 text buttons at 34 px. Hover turns
the text **white**, which breaks the palette and should go.

## Known problems to solve

1. The run timer sits in the top-left corner, under the notch when the phone
   is turned that way.
2. Gate V in the jail almost touches the HEAVY button.
3. Result screen text is placed by fixed offsets and does not centre for long
   values.
4. Nothing tells the player they are carrying a sapphire.
5. Dodge cooldown is invisible.
6. No pause on a touch device.
7. White hover text on Home and Settings.
8. The default font.

## Deliverables

1. **Mockups at 1950 × 900** for screens 1–9, with safe-area guides, the
   notch on the left. For the fight HUD and touch controls, add a second
   version with the notch on the right.
2. **States**: button idle, pressed and disabled; dodge on cooldown; heart
   full and empty; boss bar in phase 1 and phase 2; low HP; result as victory
   and as defeat.
3. **A spec sheet** a developer can build from without guessing:
   - each element's anchor (which corner or edge of the safe area) and offset
   - sizes, stroke widths and corner radii
   - every colour as one of the three hexes plus an alpha
   - font, weights and sizes
   - motion: what moves, how far, how long, with which easing
4. **A one-paragraph rationale** for the style direction (echo the ASCII
   world, or contrast it) and for how Pale Jade is rationed.

Keep it buildable: if a design needs anything other than rectangles, circles,
lines, polygons and text in the three colours, flag it as optional.
