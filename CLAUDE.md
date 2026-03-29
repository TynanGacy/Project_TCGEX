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

## Key Architecture
- **3D scene tree**: Main (Node3D) → Camera3D, Lights, Board, Hand
- **Cards** are Node3D with MeshInstance3D (BoxMesh) + StaticBody3D for raycast picking
- **Hand** manages card layout as a 3D fan near the camera
- **Board** is a table surface (PlaneMesh) with DropZone children (Area3D)
- **Input**: Main scene raycasts from camera through mouse → picks cards or intersects table plane for drag
- **Collision layers**: Layer 1 = Cards, Layer 4 = Drop zones
- Drag state managed in main.gd; card appearance/tweens on card.gd; drop validation on zones
