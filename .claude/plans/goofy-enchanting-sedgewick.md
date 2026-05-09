# Next Task — Tier 2 Lock-In, then Tier 3 by Mechanic Family

## Context

Short-term roadmap ([please-do-a-review-cryptic-dewdrop.md](C:\Users\tgsha\.claude\plans\please-do-a-review-cryptic-dewdrop.md)):

1. ✅ Retreat / energy-discard dialogs + Modify Bench removal (commit `32555e5`).
2. ✅ Trainer card execution layer (commit `e40fdee` — full handler set + Slay-the-Spire deck-search UI).
3. ⚠️ **Tier 2 effect handlers** — handlers themselves are done; tests are missing.
4. ❌ **Tier 3 effect handlers (~61 cards)** — minimal coverage today.
5. ❌ Evolution validation hardening + tests.
6. ❌ Save/load round-trip tests.

**Audit finding (this session).** Tier 2 is in better shape than the roadmap suggested:
- `attach_from_hand` — fully implemented at [scenes/match/effect_handlers.gd:354-380](scenes/match/effect_handlers.gd:354). 1 card uses it (`SS_78_shroomish`).
- `bench_damage` — fully implemented at [scenes/match/effect_handlers.gd:382-422](scenes/match/effect_handlers.gd:382). 8 cards use it (`DR_36`, `DR_55`, `RS_4`, `RS_21`, `RS_23`, `SS_35`, `SS_47`, `SS_62`).
- The trainer deck-search query plumbing (`TrainerQuery` + `_show_deck_search_grid` overlay in [dialog_manager.gd:771-1000](scenes/match/dialog_manager.gd:771)) is reusable for any attack that needs a card picker.
- `tests/test_tier2_attacks.gd` does not exist.

**User direction:** do Tier 2 first as an isolated, easily-troubleshot wave; then take Tier 3 with effects grouped by mechanic family so adjacent cards can share handler structure.

---

## Phase 1 — Tier 2 lock-in (own branch / PR)

Goal: prove the two Tier 2 handlers under tests for all 9 cards before stacking Tier 3 work on top of them.

### Steps

1. **Create `tests/test_tier2_attacks.gd`** mirroring the structure of [tests/test_tier1_attacks.gd](tests/test_tier1_attacks.gd) (562 lines, ~40 assertion blocks, uses `TestBoardBuilder`).
2. **`attach_from_hand` cases** (1 card — `SS_78_shroomish`):
   - Auto-attach when target is "self" + matching energy in hand.
   - Type filter respected (only matching `energy_type` consumed).
   - `count` parameter respected.
   - Empty-hand / no-matching-energy edge case (effect no-ops, no crash).
3. **`bench_damage` cases** (8 cards):
   - Query popup surfaces and routes to the bench-pick UI.
   - Damage applies to chosen bench Pokémon, not active.
   - Modified vs unmodified damage variants both correct (weakness/resistance behave per spec).
   - KO trigger fires from bench damage.
   - Empty-bench edge case (effect no-ops or skips picker without crashing).
4. **Manual sanity pass** on a deck containing one card from each affected `effect_key` to confirm the dialog flow looks right in-game.

### Files touched

| File | Change |
|---|---|
| [tests/test_tier2_attacks.gd](tests/test_tier2_attacks.gd) | New file (~150–200 LOC) |

### Verification

- New GUT suite passes: run from Godot via the GUT panel.
- Manually attack with `SS_78_shroomish` and one `bench_damage` card in a real match with `mcp__godot-ai__editor_screenshot source:"game"` capture for the picker dialog.
- No regressions in `tests/test_tier1_attacks.gd`.

**Exit gate:** all Tier 2 tests green, manual sanity passes, commit lands on its own branch before Phase 2 starts.

---

## Phase 2 — Tier 3 audit, by mechanic family

Goal: produce a concrete inventory grouping the ~61 Tier 3 cards by mechanic so adjacent waves can share helpers.

### Steps

1. **Walk `data/cards/`** and pull every card whose `effect_key` is unhandled by the current registry (or has non-empty `rules_text` with no `effect_key`).
2. **Bucket each card** into one of these mechanic families (initial proposal — refine as the audit reveals real distribution):
   - **F1. Hand disruption** (opponent reveals/discards/shuffles hand).
   - **F2. Prize-conditional damage** (damage scales with prizes remaining on either side).
   - **F3. Multi-turn ongoing effects** (effect persists across turns — needs a per-Pokémon ongoing-effect store).
   - **F4. Attach-from-discard / attach-from-deck** (extends the Phase-1 `attach_from_hand` pattern to other zones).
   - **F5. Opponent-controlled choices** (defender picks, not attacker).
   - **F6. Devolve / evolution-conditional** (touches evolution stack — feeds into roadmap #5).
   - **F7. Catch-all / one-offs** that don't share enough with anything else.
3. **Write `docs/tier3_audit.md`** (or append to an existing planning doc — confirm before creating a new file) with the bucketed list and a count per family.
4. **Pick wave order** by descending family size (most cards first → biggest leverage from any shared helper).

### Files touched

| File | Change |
|---|---|
| `docs/tier3_audit.md` *(only if user OKs new doc; otherwise inline in the plan file)* | Bucketed inventory |

### Verification

- Sum of per-family counts equals the total set of unhandled cards (no card uncategorized, no double-count).
- Each family entry lists the card IDs that depend on it, so wave PRs can be scoped precisely.

**Exit gate:** audit reviewed with you; wave order agreed before any Tier 3 handler code is written.

---

## Phase 3 — Tier 3 implementation, one wave per family

Goal: ship handlers in waves, biggest family first; each wave is one branch / PR with tests in lockstep.

### Per-wave shape

For each family (F1, F2, …):

1. **Add / extend handlers** in [scenes/match/effect_handlers.gd](scenes/match/effect_handlers.gd). Where a family needs a shared helper (e.g. F4's "attach from zone X to Pokémon Y" generalization of `attach_from_hand`), introduce one helper function and call it from each card's effect closure.
2. **Register `effect_key`s** in [scripts/game/effect_registry.gd](scripts/game/effect_registry.gd).
3. **Reuse query UI** — for any family that needs a card picker (F1 hand-look, F4 deck/discard search), surface a `TrainerQuery`-like request and route to [dialog_manager.gd:771-1000](scenes/match/dialog_manager.gd:771)'s grid overlay rather than building new UI.
4. **Possible new helper** on [scripts/game/attack_resolver.gd](scripts/game/attack_resolver.gd): an `ask()` analogue to the one at [scripts/game/trainer_handlers.gd:336](scripts/game/trainer_handlers.gd:336) so attacks can `await` mid-resolution prompts cleanly. Add only when the first family that needs it lands.
5. **Tests in `tests/test_tier3_attacks.gd`** — append per wave; mirror Tier 1 / Tier 2 patterns.
6. **Smoke test the wave** in a real match with one representative card.

### Final pass after all waves

- Three-deck manual run-through: DR-only, RS-only, SS-only deck each played to a prize-out win, no console errors, all dialogs reachable.
- `MCPInputServer` smoke (`POST /input` reaches `Attack` / `Retreat` / `End Turn`).
- Save mid-match → reload → finish, state intact (catches any new per-card field a Tier 3 handler added that wasn't serialized — which feeds into roadmap #6).

---

## Critical files (cross-phase reference)

| File | Role |
|---|---|
| [scenes/match/effect_handlers.gd](scenes/match/effect_handlers.gd) | Where new handlers live |
| [scripts/game/effect_registry.gd](scripts/game/effect_registry.gd) | Registers new `effect_key`s |
| [scenes/match/dialog_manager.gd](scenes/match/dialog_manager.gd) | Reuse `_show_deck_search_grid` (lines 771-1000) for picker UI |
| [scripts/game/attack_resolver.gd](scripts/game/attack_resolver.gd) | May need an `ask()` helper analogous to `trainer_handlers.gd:336` |
| [data/cards/](data/cards/) | Source of `effect_key` audit |
| [tests/test_tier1_attacks.gd](tests/test_tier1_attacks.gd) | Test pattern to mirror |
| [tests/test_tier2_attacks.gd](tests/test_tier2_attacks.gd) | Created in Phase 1 |
| [tests/test_tier3_attacks.gd](tests/test_tier3_attacks.gd) | Created in Phase 3, wave 1 |

## Branching note

Per memory: don't edit `main` directly, don't use worktrees, ask before pushing a new remote branch. Phase 1 should land on its own branch off `version_0.0.2.1` (current branch); confirm naming with you before pushing.
