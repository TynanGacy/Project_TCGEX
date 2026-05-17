# Project TCGEX

Tabletop card game simulator built in Godot 4.6.

## Overview
- Arena-style UI with click-and-drag cards in a 3D environment
- 3D tabletop with camera looking down at the table
- Cards are 3D meshes picked via physics raycasting
- Designed to simulate a physical tabletop card game

## Tech Stack
- **Engine:** Godot 4.6 (GDScript)
- **Testing:** GUT (Godot Unit Testing) addon
- **Renderer:** Forward Plus

## Conventions
- Use static typing in GDScript (e.g., `var health: int = 10`)
- Scene files (.tscn) live alongside their scripts in the same folder
- Use snake_case for files, variables, functions; PascalCase for classes/nodes
- Signals use past tense (e.g., `card_played`, `turn_ended`)
- Keep scripts focused — one responsibility per script
- Prefer composition over inheritance

## Project Structure
```
scenes/
  card/         # Card display and drag behavior
  hand/         # Hand layout and management
  board/        # Game board with play zones
  main/         # Main scene entry point
  overworld/    # 3D overworld mode (player, camera, maps, gates, exits)
assets/
  images/       # Card art, backgrounds, UI elements
  models/       # 3D models (overworld glTFs, etc.)
  textures/     # Texture pack subsets used in scenes
addons/
  gut/          # Unit testing framework
  godot-git-plugin/  # Git integration
tests/          # GUT test scripts
```

## Game modes
- **Match (card game)** — `res://scenes/match/match.tscn`. Card sim.
- **Overworld (3D exploration)** — `res://scenes/overworld/overworld_root.tscn`. Pokemon Colosseum/XD-style 3D world. Phase plan in `.claude/plans/i-m-happy-to-tackle-quirky-moler.md`.

## Isolation Rules — card game ↔ overworld
These two modes must NEVER share state at runtime. Keep them strictly separated:

1. **Mode switches are full scene swaps.** Always `GameStateManager.change_state(...)` / `change_scene_to_file(...)`. No additive `add_child` of the other mode's root.
2. **No cross-imports between mode folders.** Code under `scenes/overworld/` and `autoload/overworld/` must not `preload` or `load` anything under `scenes/match/`, `scenes/card/`, `scenes/hand/`, `scenes/board/`, `scenes/deck_builder/`, or `autoload/manager_system.gd` / `card_database.gd` / `sleeves_manager.gd`. The reverse also applies.
3. **Disjoint collision layers** (configured in `project.godot` → `[layer_names]`):
   - Layer 1 `cards`, Layer 4 `cards_drop_zones` — **card game only**.
   - Layer 2 `ow_player`, Layer 3 `ow_world`, Layer 5 `ow_gates`, Layer 6 `ow_exit_triggers`, Layer 7 `ow_interact` — **overworld only**.
   - Never set Layer 1 or 4 on an overworld node, or Layers 2/3/5/6/7 on a card-game node.
4. **Prefixed input actions** — all overworld actions start with `ow_` (e.g. `ow_move_up`, `ow_interact`, `ow_back`). Card-game actions must not use this prefix.
5. **Disjoint autoloads** — `OverworldInventory` and `OverworldWorldManager` are overworld-only; `ManagerSystemSingleton`, `CardDatabase`, `SleevesManager` are card-game-only. `GameStateManager` and `MCPInputServer` are shared infrastructure.
6. **Only sanctioned crossover point**: `scenes/main_menu/main_menu.tscn` (and `GameStateManager`) — these are allowed to know about both modes.

If you find yourself wanting to bridge them, stop and ask the user before adding the dependency.

## Running Tests
Tests use the GUT addon. Test files go in `tests/` with the prefix `test_`.

## Claude Access & Tooling — READ THIS FIRST EVERY SESSION

### Required setup checklist
Before starting any task, verify all of the following are available. If any
are missing, **stop and tell the user** so they can re-enable access.

| What | How to verify | How to restore |
|---|---|---|
| **godot-ai MCP** (editor control) | `mcp__godot-ai__editor_state` returns a result | User must have Godot open with the godot-ai addon enabled (dock shows "Connected"). `.mcp.json` must exist at repo root. |
| **`.mcp.json`** | File exists at repo root | Re-create: `{"mcpServers":{"godot-ai":{"url":"http://localhost:8000/sse"}}}` |
| **`.claude/settings.local.json`** | File exists at `.claude/settings.local.json` | Re-create from the template at the bottom of this section |
| **MCPInputServer (game UI)** | `curl -s http://localhost:9080/scene_tree` returns JSON | Game must be running (Play in Godot). The autoload `mcp_input_server.gd` starts the server automatically. |

### MCPInputServer — HTTP API (port 9080)
Used to automate the running game's UI without the Chrome extension.

```
# Read all visible Button nodes (text + screen rect)
GET  http://localhost:9080/scene_tree

# Click a button by its label text
POST http://localhost:9080/input
     {"action":"press_button","text":"<button label>"}

# Inject a mouse click at screen coordinates
POST http://localhost:9080/input
     {"action":"mouse_click","x":<px>,"y":<px>}
```

Known button labels in the main scene: `Developer Mode`, `Start Game`,
`Load State`, `Save State`, `End Turn`, `Reset`, `Attack`, `Retreat`.

### godot-ai MCP — key tools
- `editor_state` — check readiness, Godot version, current scene
- `editor_screenshot source:"game"` — screenshot of the running game
- `scene_get_hierarchy` — walk the live scene tree
- `logs_read` — read Godot editor/output logs
- `script_patch` — patch a `.gd` file in the editor

### Permissions in `.claude/settings.local.json`
The file lives at `.claude/settings.local.json` (gitignored). If it is
missing after a worktree cleanup, re-create it with this content:

```json
{
  "permissions": {
    "allow": [
      "Bash(git checkout *)",
      "Bash(git add *)",
      "Bash(git commit -m ' *)",
      "Bash(git push *)",
      "mcp__Claude_in_Chrome__computer",
      "Bash(where godot *)",
      "Bash(where godot4 *)",
      "Read(//c/Program Files/**)",
      "Skill(update-config)",
      "Skill(update-config:*)",
      "mcp__godot-ai__*",
      "Bash(curl -s http://localhost:9080/scene_tree)",
      "Bash(curl -s -X POST http://localhost:9080/input *)"
    ]
  },
  "enabledMcpjsonServers": ["godot-ai"]
}
```

### Worktree hygiene
Claude Code may create git worktrees under `.claude/worktrees/`. These lock
their branch in git, blocking GitHub Desktop branch switches.
- After any Claude session completes, run `git worktree prune` to clear stale locks.
- A `post-checkout` hook already exists at `.git/hooks/post-checkout` that
  auto-prunes on every branch switch — but it only fires after the switch
  succeeds, so manually prune if you are already blocked.

## Key Architecture
- **3D scene tree**: Main (Node3D) → Camera3D, Lights, Board, Hand
- **Cards** are Node3D with MeshInstance3D (BoxMesh) + StaticBody3D for raycast picking
- **Hand** manages card layout as a 3D fan near the camera
- **Board** is a table surface (PlaneMesh) with DropZone children (Area3D)
- **Input**: Main scene raycasts from camera through mouse → picks cards or intersects table plane for drag
- **Collision layers**: Layer 1 = Cards, Layer 4 = Drop zones
- Drag state managed in main.gd; card appearance/tweens on card.gd; drop validation on zones
