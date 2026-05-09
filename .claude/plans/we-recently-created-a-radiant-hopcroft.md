# Retreat & Energy-Discard Dialog Polish + Modify-Bench Removal

## Context

The parent roadmap ([please-do-a-review-cryptic-dewdrop.md](C:\Users\tgsha\.claude\plans\please-do-a-review-cryptic-dewdrop.md)) listed the retreat dialog and energy-discard-choice UI as "skeleton / no consumer / incomplete," and grouped them with removing the legacy "Modify Bench" button.

Reading the code, the parent plan overstated the gap — the three flows are actually wired end-to-end:

- **Retreat** ([dialog_manager.gd:176-288](scenes/match/dialog_manager.gd:176)) — Pokémon picker → bench picker → `ActionRetreat` submission.
- **Mid-attack energy discard** ([dialog_manager.gd:587-626](scenes/match/dialog_manager.gd:587)) — checkbox picker, calls `manager.resolve_energy_discard_choice()`.
- **Retreat surplus energy** ([dialog_manager.gd:628-666](scenes/match/dialog_manager.gd:628)) — checkbox picker, calls `manager.resolve_retreat_energy_choice()`. `ActionRetreat.apply()` ([scripts/actions/action_retreat.gd:68-79](scripts/actions/action_retreat.gd:68)) emits the signal when surplus exists.

What they lack is **UX polish**: checkboxes show only `display_name`, no energy-type hint; the dialogs always open even when the choice is degenerate (all surplus energies are the same type); titles are inconsistent. And per the parent plan, the **Modify Bench** button is dead UI that should come out until variable bench size returns.

Goal: ship a small, focused change that polishes the three dialogs and removes Modify Bench, without touching combat / action logic.

## Scope

**In scope**
1. Energy-type hint (color + name) on each checkbox in both energy-discard dialogs.
2. Auto-skip the energy-discard dialog when the choice is degenerate (all candidates same `energy_type`); auto-pick the first `count` and call the resolver directly.
3. Consistent dialog titles and the existing 0/N "Confirm" counter retained.
4. Remove the "Modify Bench" button and its supporting code.

**Out of scope** — tests, full audit, any change to `ActionRetreat`, `resolve_*` methods, or the attack pipeline.

---

## Changes

### 1. Energy-type label helper — [scenes/match/match_ui_utils.gd](scenes/match/match_ui_utils.gd)

Add one static helper. Reuses `AttachmentDisplay.energy_color()` ([scripts/attachment_display.gd:113](scripts/attachment_display.gd:113)) and `PokemonCardData.energy_type_to_string()` ([scripts/cards/pokemon_card_data.gd:24](scripts/cards/pokemon_card_data.gd:24)) so we don't hand-roll a type→name/color map.

```gdscript
## Returns the display label and tint color for an energy CardData entry,
## suitable for decorating checkboxes in energy-discard pickers.
static func energy_label_and_color(card: CardData) -> Dictionary:
    var name_str := card.display_name if card != null else "Energy"
    var type_str := ""
    if card is EnergyCardData:
        type_str = PokemonCardData.energy_type_to_string((card as EnergyCardData).energy_type)
    var label := "%s — %s" % [name_str, type_str.capitalize()] if type_str != "" else name_str
    return {"label": label, "color": AttachmentDisplay.energy_color(card)}
```

### 2. Polish energy-discard dialogs — [scenes/match/dialog_manager.gd](scenes/match/dialog_manager.gd)

Both `on_energy_discard_choice_required()` ([dialog_manager.gd:587](scenes/match/dialog_manager.gd:587)) and `on_retreat_energy_choice_required()` ([dialog_manager.gd:628](scenes/match/dialog_manager.gd:628)) share the same shape. Refactor the body into a private helper to avoid duplication.

```gdscript
func on_energy_discard_choice_required(player_id: int, eligible: Array, count: int, attacker_slot: String) -> void:
    _show_energy_choice_dialog("Choose %d energy to discard:" % count, eligible, count,
        func(sel: Array[int]) -> void: _main.manager.resolve_energy_discard_choice(sel))

func on_retreat_energy_choice_required(player_id: int, eligible: Array, count: int, active_slot: String) -> void:
    _show_energy_choice_dialog("Retreat — choose %d energy to discard:" % count, eligible, count,
        func(sel: Array[int]) -> void: _main.manager.resolve_retreat_energy_choice(sel))
```

The new `_show_energy_choice_dialog(title, eligible, count, on_confirm)` does:

1. **Degenerate-choice short-circuit.** If every entry in `eligible` is `EnergyCardData` with the same `energy_type`, build an `Array[int]` of the first `count` indices and call `on_confirm.call(indices)` immediately — no panel. This mirrors the same-type optimization in `_discard_any` ([scenes/match/effect_handlers.gd:478](scenes/match/effect_handlers.gd:478)) but at the UI layer so we don't pop a pointless dialog.
2. Otherwise build the panel as today, but for each `CheckBox`:
   - Use `MatchUIUtils.energy_label_and_color(card)` for the text and `cb.add_theme_color_override("font_color", color)` for tint.
3. Track this panel in `_attack_dialog` so it doesn't collide with retreat / promotion panels (existing code does not — minor fix).
4. Confirm-button counter (`Confirm (k/N selected)`) and disabled-until-exact-count behavior are preserved.

### 3. Consistent retreat dialog title — [dialog_manager.gd:217](scenes/match/dialog_manager.gd:217)

Change `"Choose Pokémon to Retreat"` → `"Retreat — choose active Pokémon"` and `"Choose Bench Replacement"` → `"Retreat — choose bench replacement"` so the three retreat-related dialogs read as one flow. Pure label change.

### 4. Remove Modify Bench

Delete the button, its handler, its DialogManager surface, and the bench-overflow plumbing that only exists to support it. `manager.set_bench_count()` and `board.set_bench_count()` stay — they're called elsewhere during placement and are needed when variable bench size returns.

- [scenes/match/match.gd](scenes/match/match.gd):
  - Line 80: remove `var _bench_button: Button = null`.
  - Lines 139-142: remove the four lines that create + connect the button.
  - Line 417-418: remove `_on_modify_bench_pressed()`.
  - Line 447: remove the `_bench_button.disabled = true` line in the disable-buttons block.
- [scenes/match/dialog_manager.gd](scenes/match/dialog_manager.gd):
  - Line 15: remove `_bench_overflow_queue`.
  - Line 27: remove the `clear()` line that touches it.
  - Lines 291-417: remove the entire "Modify Bench dialog" section (`on_modify_bench_pressed`, `_show_modify_bench_dialog`, `_apply_bench_count_change`, `_process_bench_overflow`).
  - Line 576: remove the `_bench_button.disabled = false` line in `on_game_won`.
- [CLAUDE.md](CLAUDE.md): drop `Modify Bench` from the "Known button labels" list (line 73).

---

## Files touched

| File | Change |
|---|---|
| [scenes/match/match_ui_utils.gd](scenes/match/match_ui_utils.gd) | Add `energy_label_and_color()` helper |
| [scenes/match/dialog_manager.gd](scenes/match/dialog_manager.gd) | Extract energy-choice helper, add same-type short-circuit, type-colored labels, consistent retreat titles, delete Modify Bench section |
| [scenes/match/match.gd](scenes/match/match.gd) | Delete `_bench_button` field + creation + handler + disable hooks |
| [CLAUDE.md](CLAUDE.md) | Drop `Modify Bench` from button list |

No changes to `ActionRetreat`, `manager_system.gd` resolvers, or `effect_handlers.gd`.

---

## Verification

Run the game from Godot (`Play`) and verify in this order:

1. **Modify Bench gone.** No third button next to `End Turn` / `Retreat`. `curl -s http://localhost:9080/scene_tree` returns the button list without `Modify Bench`. No errors at scene load.
2. **Retreat — exact energy.** Active Pokémon with retreat_cost == attached_energy → click Retreat → pick Pokémon → pick bench → swap happens, energies discarded, no surplus dialog.
3. **Retreat — surplus, mixed energies.** Attach 2 different energy types beyond cost → on submit, the surplus dialog appears with one checkbox per energy, each label like `"Lightning Energy — Lightning"` tinted yellow, etc. Confirm-button enables only when exactly `count` selected. Confirm → swap happens, selected energies discarded.
4. **Retreat — surplus, all same type (degenerate).** Attach 3 of the same energy type, retreat_cost = 1 → no surplus dialog appears; first energy auto-discarded; swap happens.
5. **Mid-attack energy discard.** Trigger an attack whose effect discards N energy of "any" type with mixed energies attached → checkbox dialog appears with type-colored labels. Confirm proceeds; attack pipeline completes (turn-end logic still fires).
6. **Special-condition / retreat-lock blocks** still surface a log message and no dialog, since the picker excludes them ([dialog_manager.gd:195](scenes/match/dialog_manager.gd:195)) — sanity check unchanged.
7. **Save mid-retreat-surplus**, reload — `retreat_pending` state restoration is out of scope; just confirm the existing behavior isn't regressed (i.e. saving/loading mid-dialog isn't worse than before).

Use `mcp__godot-ai__editor_screenshot source:"game"` to capture each dialog state for the record.
