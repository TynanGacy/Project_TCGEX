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
assets/
  images/       # Card art, backgrounds, UI elements
addons/
  gut/          # Unit testing framework
  godot-git-plugin/  # Git integration
tests/          # GUT test scripts
```

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
`Load State`, `Save State`, `End Turn`, `Reset`, `Attack`, `Retreat`,
`Modify Bench`.

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
