# Crimson Red — Project Constants

## Engine / Framework
- **Framework:** LÖVE2D (lua)
- **Language:** Lua

## Resolution & Display
- **Virtual resolution:** 800 x 450 (locked 16:9)
- All coordinates and sizes are expressed in virtual pixels at this resolution.
- The window may be resizable, but the game renders to an 800×450 canvas that is then scaled to fill the window letterboxed.

## Post-Processing (applied globally after render)
- **RGB chromatic aberration shift** — slight, values TBD
- **Bloom** — slight, values TBD
- These effects are applied via a shader pass on the canvas render texture before blitting to screen.
- Values will be tuned once the title screen is up.

## Color Palette
- **Red:** crimson red — primary accent color (used for logo, title text, menu items)
- **Off-red:** slightly brighter/lighter red — used for hover states
- **White:** used for pressed/active states
- Background is pure black.

## Typography
- **Font:** Dedicool (`Dedicool.ttf`) — sourced from `assets/dedicool/`
- Title text size: ~50px (at 800×450 virtual res — scaled up from the 4:3 reference)
- Button text size: ~16px

## Reference Material
- Title screen visual reference: `reference-material/image.png` (4:3 ratio version)
- C++ raylib reference implementation: `C:\Users\Alex\projects\the-game\crimson-red_v2.0\src\main.cpp`

## Title Screen Layout (800×450)
- Logo (triangle pyramid / Sierpinski triangle): centered horizontally, upper third of screen
- Title text "crimson red": centered, ~50% down
- Menu items (PLAY, OPTIONS, EXIT): left-of-center, ~65% down, stacked vertically
- Hover → off-red; click/hold → white

## Prototype Structure
- `prototype/` — self-contained prototypes, no shared state
- `main-game/` — final integrated game code
