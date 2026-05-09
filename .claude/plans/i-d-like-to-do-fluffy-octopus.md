# Project TCGEX — Cleanup & Optimization Plan

## Context

`main.gd` is 2,282 lines handling 16+ concerns. Card image loading eagerly loads all 311 PNGs (~230 MB) into memory at startup. The project has no scene-switching infrastructure for future game states. This plan addresses all three issues in dependency order.

---

## Phase 1: Split main.gd (~2,282 → ~400 lines + 7 new files)

### Why split?
- main.gd handles setup dialogs, drag input, 5 modal dialog types, pile rendering, hand rendering, save/load, and game orchestration — all in one file
- Claude has to chunk-read it; humans face the same problem
- Extracted managers are independently testable and reviewable

### Downsides of splitting
- **Bug risk during extraction** — mitigated by doing one group at a time with testing between each
- **More files to navigate** — 8 files vs 1, but each is focused and findable by name
- **Indirection cost** — managers need a reference to the main node; adds one `init()` call per manager
- **Cross-manager coupling** — a few functions span concerns (e.g., `_try_end_turn_after_attack` bridges attack UI and turn management). These stay on main.gd as orchestration glue.

### Communication pattern
Each manager extends `Node`, is added as a child of Main in `_ready()` (not in .tscn), and receives a reference to main via `init(main_node)`. Direct references, not signals, for calling between managers — signals only for the events already coming from ManagerSystemSingleton.

### New files (all in `scenes/main/`)

| File | Responsibility | ~Lines |
|------|---------------|--------|
| `match_ui_utils.gd` | Static helpers: `make_panel()`, `zone_prefix()`, `format_attack_cost()` | 60 |
| `setup_manager.gd` | Setup dialog, config, mulligan/coin/placement sequence | 580 |
| `input_manager.gd` | `_unhandled_input()`, drag, hover, raycast, drop routing | 320 |
| `dialog_manager.gd` | Attack, retreat, bench modify, prize selection, promotion, energy discard dialogs | 710 |
| `pile_visual_manager.gd` | Deck/discard/prize card rendering | 100 |
| `hand_visual_manager.gd` | Hand card cache, rebuild, sync | 80 |
| `save_load_manager.gd` | Save/load dialog UI + `_load_game_state()` restoration | 230 |

### What stays in main.gd (~400-500 lines)
- All `@onready` vars and preloads
- Shared state: `is_developer_mode`, slot counts, perspective transforms
- `_ready()` — creates managers, wires signals
- `_start_game()` — delegates to setup_manager
- `_reset_game()` / `teardown_match()` — shared cleanup
- Perspective system: `_apply_perspective()`, camera/hand transforms
- Turn/phase signal handlers (thin delegation to dialog_manager)
- `_try_end_turn_after_attack()` — cross-manager orchestration
- Win handler + end-turn button handler

### Extraction order (each step = test before proceeding)

1. **MatchUIUtils** — extract 3 static helpers, find-and-replace calls. Zero risk.
2. **PileVisualManager** — smallest, most isolated. Move `_pile_nodes` + 3 refresh methods.
3. **HandVisualManager** — move `_hand_cards` + rebuild/sync. Verify hand fan updates.
4. **DialogManager** — largest extraction. Move 6 dialog groups + `_attack_dialog` tracking.
5. **InputManager** — move `_unhandled_input()` + all pick/drop/hover. Verify drag works.
6. **SetupManager** — move setup dialog + sequence coroutine. Verify full game start flow.
7. **SaveLoadManager** — move save/load UI + restore. Extract shared `teardown_match()` on main.

### Verification per step
- Start a match (dev mode + player mode)
- Play cards from hand to board
- Attack, retreat, modify bench
- Trigger KO → prize selection → promotion
- Save and load a game state
- Reset and start a new match

---

## Phase 2: Lazy Card Image Loading

### Problem
`TestDeckFactory._build_pool()` loads all 311 card JSONs AND all 311 PNGs into a static cache. A typical match uses ~60-120 unique cards. The other ~200 images waste memory and slow startup.

### Solution: Separate data loading from art loading

**File: `scripts/game/test_deck_factory.gd`**

1. **Remove art loading from `_card_from_json()`** — delete `card.art = _load_art(data["card_id"])` at line 76. Pool now contains data-only CardData (tiny, fast to build).

2. **Add new static method:**
```gdscript
static func load_art_for_deck(deck: Array[CardData]) -> void:
    var loaded: Dictionary = {}   # card_id → Texture2D
    for card in deck:
        if card.art != null:
            continue
        if loaded.has(card.card_id):
            card.art = loaded[card.card_id]
            continue
        card.art = _load_art(card.card_id)
        if card.art != null:
            loaded[card.card_id] = card.art
```

**File: `scenes/main/main.gd` (in `_start_game()`)**

After the two `DeckLoader.load_deck()` calls, add:
```gdscript
TestDeckFactory.load_art_for_deck(p0_deck)
TestDeckFactory.load_art_for_deck(p1_deck)
```

**File: `scripts/game/game_state_serializer.gd`**

After card resolution during restore, collect all resolved CardData and call `TestDeckFactory.load_art_for_deck()` on them.

**No changes needed:**
- `card_face.gd` — already handles `art == null` with a colored-rect fallback
- `deck_loader.gd` — duplicates from pool; art loaded separately after
- `card_library.gd` — doesn't load art

### Why this works
- `_cached_pool` still holds all 311 CardData for random deck building, but without art (~KB each vs MB)
- `DeckLoader` duplicates templates → duplicates inherit `art = null` → `load_art_for_deck()` assigns shared Texture2D references only to deck cards
- Memory drops from ~230 MB (all images) to ~40-80 MB (only in-use images)

### Verification
- Start a random deck game — cards display art, not colored rectangles
- Start a configured deck game — same check
- Monitor memory in Task Manager — should be significantly lower
- Save and load a game state — restored cards display art
- Check that random deck building still works after pool cache is data-only

---

## Phase 3: Multi-State Game Architecture

### Your understanding is correct

Godot's standard pattern:
- **Autoloads** for persistent global state (survive scene changes)
- **`get_tree().change_scene_to_file()`** for state transitions
- Each state is its own scene tree — built on enter, freed on exit

### What needs to change

**1. New autoload: `autoload/game_state_manager.gd`**
- Holds global persistent data (player name, play time — stubs for now)
- `change_state(scene_path: String)` — wraps `get_tree().change_scene_to_file()`
- `return_to_menu()` — convenience for going back to main menu

**2. New scene: `scenes/main_menu/main_menu.tscn`**
- Control-based UI with VBoxContainer
- Title: "Project TCGEX"
- Buttons:
  - "Match" → loads `res://scenes/match/match.tscn`
  - "Overworld (WIP)" → loads placeholder
  - "Deck Builder (WIP)" → loads placeholder
  - "Pack Opening (WIP)" → loads placeholder
  - "Mini Game 1 (WIP)" → loads placeholder

**3. Rename `scenes/main/` → `scenes/match/`**
- `main.tscn` → `match.tscn`, `main.gd` → `match.gd`
- All extracted managers from Phase 1 move with it
- Update internal .tscn script references

**4. New placeholder scene: `scenes/placeholder/placeholder_state.tscn`**
- Shows the state name + "Back to Menu" button
- `GameStateManager` stores the target state name before transitioning

**5. Update `project.godot`**
- `run/main_scene` → `"res://scenes/main_menu/main_menu.tscn"`
- Add autoload: `GameStateManager="*res://autoload/game_state_manager.gd"`
- **Remove** autoloads: `AnimationManagerSingleton`, `EffectHandlers`

**6. Move AnimationManager and EffectHandlers to match-local**
- These are only used during matches — no reason to persist as globals
- `match.gd` creates them in `_ready()` as child nodes, just like the other extracted managers
- Move files from `autoload/` to `scenes/match/`:
  - `autoload/animation_manager.gd` → `scenes/match/animation_manager.gd`
  - `autoload/effect_handlers.gd` → `scenes/match/effect_handlers.gd`
- All code that currently references `AnimationManagerSingleton` or `EffectHandlers` as globals gets updated to use the match-local reference instead (passed via `init()` like the other managers)
- **Key references to update:**
  - `manager_system.gd` uses `AnimationManagerSingleton` for coin flip animations — pass it as a dependency during match setup
  - `attack_resolver.gd` / effect scripts use `EffectHandlers` — same pattern, pass reference
  - `main.gd` (→ `match.gd`) creates the coin flip overlay on the animation manager
- When the match scene is freed, these nodes are freed with it — no cleanup needed

**7. Match cleanup on exit**
- Add `full_reset()` to `ManagerSystemSingleton` — resets game_position, board_position, turn state
- Match scene calls this before transitioning away (or in `_exit_tree()`)
- Add a "Back to Menu" button in the match HUD TopBar

**8. Remaining autoloads**
- `ManagerSystemSingleton` — stays as autoload; reset on match exit, reused on re-entry. It holds game rules and state that the match scene rebuilds each time.
- `SleevesManager` — stays as autoload; cosmetic, lightweight, may be used by deck builder later
- `GameStateManager` — new autoload for scene transitions + global player data
- `MCPInputServer` — stays as autoload; dev tool, harmless when no match is running

### Transition flow
```
Launch → main_menu.tscn
  ├─ "Match" → match.tscn → setup dialog → gameplay → "Back to Menu" → main_menu.tscn
  ├─ "Overworld (WIP)" → placeholder → "Back to Menu" → main_menu.tscn
  ├─ "Deck Builder (WIP)" → placeholder → "Back to Menu" → main_menu.tscn
  ├─ "Pack Opening (WIP)" → placeholder → "Back to Menu" → main_menu.tscn
  └─ "Mini Game 1 (WIP)" → placeholder → "Back to Menu" → main_menu.tscn
```

### Verification
- Launch → main menu appears with all buttons
- Click "Match" → match loads, full gameplay works as before
- Click "Back to Menu" from match → returns to menu, no errors in console
- Click "Match" again → fresh match, no leftover state
- Click each WIP button → placeholder with correct name and working "Back to Menu"
- Repeat match → menu → match cycle 3x to confirm no memory leaks or state corruption

---

## Execution Order

| Step | Area | Why this order |
|------|------|----------------|
| 1 | Split main.gd | Makes Areas 2 & 3 easier — smaller files to modify and move |
| 2 | Lazy image loading | Independent of game states; cleaner after split (save/load isolated) |
| 3 | Multi-state architecture | Builds on the cleaner codebase; renames files last to avoid churn |

Each phase is independently shippable — the project works after each one.
