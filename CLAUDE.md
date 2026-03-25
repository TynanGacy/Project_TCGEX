# Project TCGEX

Tabletop card game simulator built in Godot 4.6.

## Overview
- Arena-style UI with click-and-drag cards
- 2D card game with zones (hand, board fields, graveyard, deck, etc.)
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
- Cards are Control nodes with drag-and-drop via `_gui_input`
- Hand manages card layout with horizontal fan/spread
- Board contains DropZone areas where cards can be played
- Drag state is managed on the card itself; drop validation on the zones
