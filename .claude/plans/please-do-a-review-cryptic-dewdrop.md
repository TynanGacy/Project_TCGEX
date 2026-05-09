# Project TCGEX — Review & Roadmap

## Context
You asked for a state-of-the-project review and a tiered roadmap. The end goal is a top-down RPG with TCG matches as the battle scene, plus card-shop / deck-builder / pack-opening / trading UIs and minigames. Your stated near-term priority is a **functional (not pretty)** match scene that supports every card across the three uploaded sets (DR, RS, SS — 309 cards total). This document grounds the roadmap in what's actually in the repo today on `version_0.0.2.0`.

---

## Current State (as of `version_0.0.2.0`)

### What's solid
- **Match scene** (`scenes/match/match.tscn`) is wired end-to-end: 3D board, dual hands, drag/drop via raycast, dev-mode perspective flip.
- **Authority model is clean.** `ManagerSystemSingleton` ([autoload/manager_system.gd](autoload/manager_system.gd)) is the sole state mutator; declarative `GameAction` subclasses ([scripts/actions/](scripts/actions/)) feed into it. Good foundation to build on.
- **Turn loop**: SETUP → DRAW → MAIN → CLEANUP, with per-turn limits (1 energy, 1 supporter, 1 stadium, 1 retreat) enforced.
- **Combat pipeline**: `AttackResolver` ([scripts/game/attack_resolver.gd](scripts/game/attack_resolver.gd)) drives validate → target → declare → damage → KO → prize → promote.
- **Win conditions**: prizes (configurable 2–6), all-actives-KO'd-with-no-bench, signal chain to game-end UI.
- **Save/Load**: serialization works via `SaveLoadManager` + `GameStateSerializer`.
- **Card content**: 309 JSON card definitions across DR / RS / SS, all with art in [assets/images/](assets/images/), schema covers HP / weakness / resistance / retreat / attacks / costs / `effect_key` + `effect_params`.
- **Effect system**: `EffectRegistry` ([scripts/game/effect_registry.gd](scripts/game/effect_registry.gd)) + `EffectDefinition` phase-handler model + 18 implemented handlers in [scenes/match/effect_handlers.gd](scenes/match/effect_handlers.gd). Covers status, coin flips, heal, rest, energy discard/scaling, damage-counter scaling, and basic conditionals.
- **Scene-switching infrastructure** just landed: `GameStateManager` ([autoload/game_state_manager.gd](autoload/game_state_manager.gd)) + `placeholder_state.tscn` stubs.
- **Test baseline**: GUT tests for Tier 0 (24 pure-damage cards) + Tier 1 (single-effect cards) in [tests/](tests/).

### What's stubbed or missing
- **Retreat UI**: `DialogManager.on_retreat_pressed()` is a skeleton — energy-cost picker UI incomplete; `retreat_energy_choice_required` signal has no consumer.
- **Energy-discard-choice UI**: signal emitted, panel framework exists, picking/commit flow incomplete.
- **Modify Bench button**: legacy from older board-state infra. Remove for now; revisit when variable bench size returns.
- **Card effect coverage**:
  - Tier 0 (24 cards) — ✅ functional
  - Tier 1 (~124 cards) — ✅ functional
  - Tier 2 (~63 cards) — ⚠️ partial (bench damage, energy movement, search effects mostly stubs; `attach_from_hand` and `bench_damage` are registry stubs)
  - Tier 3 (~61 cards) — ❌ minimal (hand disruption, prize conditionals, multi-turn effects)
- **Trainer text resolution**: Items, Supporters, Stadiums data-only — `rules_text` not executed.
- **Evolution chain validation**: present but rudimentary.
- **No UI** for: main menu polish, deck builder, shop, pack opening, trading, collection, profile, minigames.
- **No tests** for: scene transitions, UI flows, deck loading, save/load round-trip, Tier 2+ effects.
- **No deck-construction tooling** — decks are hand-authored JSON in [data/decks/](data/decks/).

---

## Roadmap

### Short-Term (next 1–3 versions, ~`0.0.2.x` → `0.0.3.x`) — Finish the match
**Goal: every card in DR/RS/SS playable end-to-end. Match scene fully functional.**

1. **Close the two stubbed dialogs + remove Modify Bench** (highest leverage; unblocks ~all matches that need retreat or overflow):
   - Retreat dialog (energy picker → `ActionRetreat`).
   - Energy-discard-choice dialog (consume the existing signal).
   - Remove the Modify Bench button and its `DialogManager.on_modify_bench_pressed()` skeleton — to be reintroduced when variable bench size comes back.
   - Files: [scenes/match/dialog_manager.gd](scenes/match/dialog_manager.gd), [scenes/match/match.gd](scenes/match/match.gd).

2. **Trainer card execution layer.** Extend `EffectRegistry` (or a parallel `TrainerEffectRegistry`) so Items / Supporters / Stadiums actually do things. Author handlers for the 27 trainers across the three sets. Reuse the phase-handler pattern from attacks.

3. **Tier 2 effect handlers** (~63 cards): bench damage, energy movement (`attach_from_hand`, `bench_damage` stubs in registry), deck search, hand-look effects. Extend [scenes/match/effect_handlers.gd](scenes/match/effect_handlers.gd) and add tests in `tests/test_tier2_attacks.gd`.

4. **Tier 3 effect handlers** (~61 cards): hand disruption, prize-conditional damage, multi-turn ongoing effects, complex attach-from-X chains. Tests in `tests/test_tier3_attacks.gd`.

5. **Evolution validation hardening** + tests covering "entered play this turn" rule.

6. **Save/load round-trip tests** to catch regressions as the action surface grows.

**Exit criteria:** every card in DR/RS/SS can be played, and matches finish without manual intervention. No "pretty" requirement.

---

### Medium-Term (~`0.0.4.x` → `0.0.6.x`) — Card-management surface
**Goal: build the non-match UIs that surround the TCG loop, on top of the existing `GameStateManager` + placeholder infrastructure.**

1. **Deck Builder** — first because it eliminates hand-edited JSON. Replace `placeholder_state.tscn` for the deckbuilder route. Read [data/cards/](data/cards/), write to [data/decks/](data/decks/) (or user dir). Validation: 60-card decks, energy/Pokémon/trainer counts, evolution-chain sanity.

2. **Collection view** — list cards owned (introduce a player-collection store; today decks are hand-built so there's no concept of ownership). Single source of truth feeds shop, packs, deckbuilder, trading.

3. **Pack Opening** — minimal animation, deterministic seed-able RNG so it's testable. Adds cards to the collection.

4. **Card Shop** — currency model, buy packs / single cards. Keep currency in `GameStateManager` or a dedicated autoload.

5. **Trading (local first)** — UI for two-side card exchange against the same collection store. Defer networking.

6. **Main menu polish** — proper navigation hub between match / deckbuilder / shop / collection / packs.

7. **Match polish (still functional, slightly nicer):** clearer phase indicators, log/history panel, better turn banners — only what's needed for usability.

**Exit criteria:** a player can earn currency, buy packs, build a deck, and play a match without ever editing JSON.

---

### Long-Term (`0.1.x`+) — RPG shell, minigames, online
**Goal: TCG becomes the battle layer of a top-down RPG.**

1. **Top-down overworld scene**: tile-based or 2.5D, NPC interactions, transition into match scene via `GameStateManager`. The match becomes the "battle scene" of the RPG, with overworld context (opponent identity, stake, story flags) passed via the existing pending-state mechanism.

2. **Story / progression layer**: quests, NPC trainers with fixed decks, gym-style milestones.

3. **Minigames**: each as its own scene under `scenes/minigames/`, registered via `GameStateManager`. Reuse coin-flip overlay style for low-friction minis.

4. **Networking pass**: revive [scripts/net/](scripts/net/) for online matches and trading. Replay format on top of the action log. This is where the declarative `GameAction` model pays off.

5. **Polish & art pass**: card 3D feel, board theming per opponent, music, particles. Defer until gameplay is locked.

6. **More sets**: data pipeline for adding sets — by this point, schema and effect registry should be stable enough that new sets are mostly content work.

---

## Recommended Immediate Next Step
Pick up the **retreat dialog** first — smallest scope, highest visibility, exercises the dialog/signal/action plumbing you'll reuse for energy-discard-choice and modify-bench. After that, batch through Tier 2 effect handlers with tests in lockstep.

## Verification (for short-term phase)
- All `tests/test_tier*.gd` suites pass under GUT.
- Manually play a match using a DR-only deck, an RS-only deck, and an SS-only deck through to a prize-out win — no console errors, no stuck dialogs, retreat / energy-discard flows usable.
- `MCPInputServer` smoke test: `Attack`, `Retreat`, `End Turn` buttons reachable via `POST /input` in a running game.
- Save mid-match, reload, finish — state matches.
