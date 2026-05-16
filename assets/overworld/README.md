# Overworld assets

All assets here are from **Kenney.nl**, licensed **CC0** (public domain — attribution optional but appreciated).

| File | Source | Notes |
|---|---|---|
| `tilesets/tiny_town_packed.png` | [Tiny Town v1.1](https://kenney.nl/assets/tiny-town) | 16×16 tiles, packed (no margins), 12×11 = 132 tiles. Primary tileset. |
| `tilesets/tiny_town.png` | Tiny Town v1.1 | Same tiles, 1px margin between tiles. Kept for reference. |
| `tilesets/water_placeholder.png` | Generated locally | 16×16 flat-blue stand-in for water. Replace with proper water art when convenient. |
| `characters/roguelike_characters.png` | [Roguelike Characters](https://kenney.nl/assets/roguelike-characters) | 16×16 sprites, 1px margin. Used for player + future NPCs. |

## TileSet (`tiny_town_tileset.tres`)

Two atlas sources and two custom data layers:

- **Source 0** — Tiny Town sheet, all 132 tiles pre-declared.
- **Source 1** — Water placeholder, single tile at atlas (0, 0), `gating_item = &"surf"` baked in.
- Custom data layer 0: `is_solid: bool` — player cannot enter when `true`.
- Custom data layer 1: `gating_item: StringName` — non-empty blocks (inventory unlock TBD).

### Pre-marked solids

The `.tres` already flags these atlas coords as `is_solid = true`:

| Region | Atlas coords | What |
|---|---|---|
| Trees / bushes | rows 0–2, cols 3–11 | All foliage on rows 0–2. |
| Fences / posts | rows 3–6, cols 8–11 | Wood fence pieces and corner posts. |
| Buildings | rows 4–7, cols 0–7 | Roofs, walls, doors. |
| Castle walls | rows 8–10, cols 0–7 | Stone walls, dungeon, gates. |

Passable rows/cols: grass (row 0, cols 0–2), dirt path (rows 1–3, cols 0–2), plain dirt (row 3, cols 3–6), tile floor (7, 3), item icons (rows 7–10, cols 8–11).

Tweak any of these in the TileSet editor (Inspector → Custom Data Layers) if a tile is mis-classified.

## Painting maps in the editor

1. Open a map scene (e.g. `scenes/overworld/maps/town.tscn`).
2. Select the **Terrain** node — the **TileMap** dock opens at the bottom.
3. Pick a tile from the left palette, paint on the right canvas. Right-click erases, shift drags a line, ctrl drags a rectangle.
4. To use water tiles, switch the atlas selector at the top of the palette from `tiny_town_packed` to `water_placeholder`.
5. Save the scene — tile data is stored inline in the `.tscn`.

Each map's `_ready()` only registers its edge transitions; it does **not** paint terrain. Anything you paint sticks.

### Map dimensions and exit alignment

| Map | Size | Exit edge | Exit rows |
|---|---|---|---|
| `town.tscn` | 22 × 15 | east (col 21) | rows 7, 8, 9 |
| `east_field.tscn` | 22 × 15 | west (col 0) | rows 7, 8, 9 |

Paint the exit cells as something passable (grass, path) so the player can step onto them — the script will then trigger the scene transition.
