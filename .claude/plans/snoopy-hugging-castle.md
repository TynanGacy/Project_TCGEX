# Attack Resolution Rework Plan

## Context

The current attack system resolves everything in a single synchronous `ActionAttack.apply()` call: effects fire, damage is applied, KOs resolve, and post-actions run — all in one frame with no pauses for animations or player input. This doesn't match 2007 EX-era TCG rules, which require a multi-phase pipeline where effects are resolved, queued, potentially nullified, and only then executed. It also prevents proper animation timing (coin flips play out-of-sync with game state changes) and blocks future features like mid-attack player queries ("may" abilities, energy discard choice).

The user provided a comprehensive 14-step attack flowchart (steps 0-13) that defines the correct resolution order. This plan implements that flowchart faithfully.

---

## User's Attack Flowchart (my understanding)

**Terminology:**
- **Query** = prompt a player for input (target selection, "may" ability, energy choice)
- **Resolve** = calculate/prepare a game action without executing it yet
- **Queue** = store a resolved action for batch execution later
- **Execute** = mutate game state, or force an animation delay before proceeding

**Steps:**

0. **Validate** — Check each attack is legal (energy costs met, no blocking conditions). Invalid attacks greyed out in UI. Already implemented in `ActionAttack.validate()`.
1. **Select target** — Query player for target(s). Most attacks implicitly target opposing active, but with 2-active-slot boards, explicit selection matters. Handled by UI before action submission.
2. **Declare attack** — Attack is locked in; cannot cancel. Mark `attack_used_this_turn`.
3. **Conditionals** — Resolve/execute things that may block or redirect the attack. Confusion check first (flip; tails = 30 self-damage, attack stops). Then other conditionals like Smokescreen-like effects. Animation delay per coin flip.
4. **Pre-damage effects** — Resolve effects whose text says "before doing damage." May include player queries. Queue resolved effects. Animation delay per flip.
5. **Damage calculation** (substeps):
   - 5a. Start with base damage from AttackData.
   - 5b. Resolve attacker-side modifiers: coin-flip bonuses, tools, abilities, player queries. If total <= 0 after this step, skip to step 6. Animation delay per flip.
   - 5c. Resolve defender-side modifiers: weakness (x2), resistance (-30), tools, abilities, player queries. If total <= 0 after this step, skip to step 6. Animation delay per flip.
   - 5d. Queue the final damage amount.
6. **Post-damage effects** — Resolve remaining attack text effects (status conditions, bench damage, self-damage, energy discards). May include player queries. Queue them. Animation delay per flip.
7. **Nullification** — Check for abilities that block queued effects. Remove nullified effects from queue. Animation delay if applicable.
8. **Execute queue** — Play main attack animation, then execute all surviving queued effects (damage + effects) in order.
9. **On-damage-received** — Resolve effects that trigger when a Pokemon takes damage. Animation delay, then execute.
10. **Exit attack** — Check for KOs simultaneously across all damaged Pokemon. Resolve prizes/promotions.
11. **End of turn** — Handled by ManagerSystem, not the attack pipeline.
12. **Between-turn effects** — Poison (10 damage), sleep (flip to wake), burn (flip; tails = 20 damage). If multiple, controller chooses order. Animation delay per flip, then execute. KOs checked simultaneously after all resolve.
13. **Start next turn** — Handled by ManagerSystem.

---

## Architecture

### AttackResolver — child Node of ManagerSystem

A new `AttackResolver` Node created by ManagerSystem in `_ready()`. Not an autoload — only ManagerSystem calls it. Holds zero persistent state between attacks; it's a stateless pipeline orchestrator.

- Receives an `ActionAttack` + manager reference
- Runs steps 2-10 as an async coroutine (`await` between phases)
- Emits `pipeline_completed` when done
- Has a `_is_resolving` guard against re-entrant calls

### AnimationManager — separate autoload

A new autoload loaded after ManagerSystemSingleton. Globally accessible for attack animations, coin flips, and future systems (retreat, card-play).

- Owns a sequential FIFO queue of `AnimationRequest` objects
- Never overlaps animations
- Connects to ManagerSystem's `coin_flipped` / `coins_batch_flipped` signals to auto-enqueue coin animations
- main.gd passes the CoinFlipOverlay reference to it
- Exposes `enqueue_and_wait(request)` for the resolver to await
- `skip_animations: bool` for tests
- Does NOT modify game state

Autoload order: `ManagerSystemSingleton -> AnimationManager -> EffectHandlers -> SleevesManager -> ...`

### Async request_action

`request_action()` stays synchronous (returns validation result). New `request_action_async()` awaits `pipeline_completed` after a successful attack action. `ActionAttack.apply()` becomes a thin kickoff delegating to `attack_resolver.begin_attack()`.

### Resolve → Queue → Execute pattern

The core behavioral change. Today, effects mutate state immediately. In the new system:
1. **Resolve** (phases 4, 5b, 5c, 6): handlers calculate outcomes (coin flips, queries) and produce `QueuedEffect` objects
2. **Queue**: effects are appended to `ctx.effect_queue`
3. **Nullify** (phase 7): abilities can remove entries from the queue
4. **Execute** (phase 8): all surviving effects are applied to game state

### Player Query System

When a handler needs player input, it includes query metadata in a `QueuedEffect`. The resolver detects this, emits `player_query_requested`, pauses until `player_query_resolved` is received from main.gd's UI. This replaces the current `energy_discard_pending` / `energy_discard_choice_required` pattern.

---

## New Files (7)

| File | Class | Purpose |
|---|---|---|
| `scripts/game/attack_resolver.gd` | `AttackResolver` | Async pipeline orchestrator (steps 2-10) |
| `autoload/animation_manager.gd` | `AnimationManager` | Animation queue autoload |
| `scripts/game/queued_effect.gd` | `QueuedEffect` | Effect data queued during resolve phases |
| `scripts/game/damage_entry.gd` | `DamageEntry` | Damage data queued at step 5d |
| `scripts/game/effect_definition.gd` | `EffectDefinition` | Phase-aware handler container (maps Phase -> Callable) |
| `scripts/game/attack_query.gd` | `AttackQuery` | Player query data (kind, prompt, options) |
| `scripts/game/animation_request.gd` | `AnimationRequest` | Animation request data (kind, duration, metadata) |

## Files to Modify (10)

| File | Changes |
|---|---|
| `autoload/manager_system.gd` | Create AttackResolver child in `_ready()`. Add `request_action_async()`. Add `attack_declared`/`attack_resolved` signals. Make `_run_cleanup()` async. |
| `scripts/game/attack_context.gd` | Add `effect_queue`, `damage_queue`, `damaged_slots`, `attack_blocked`, `current_phase`. Keep `_post_actions` as compatibility shim during migration. |
| `scripts/game/effect_registry.gd` | Add `_definitions` dict, `register_def()`, `register_simple()`, `dispatch_phase()`. Keep old `register()`/`dispatch()` as shims. |
| `autoload/effect_handlers.gd` | Rewrite all handlers to use `EffectDefinition` with explicit phases and `QueuedEffect` creation. |
| `scripts/actions/action_attack.gd` | `apply()` delegates to `attack_resolver.begin_attack()`. Move `_compute_damage()` to AttackResolver. Keep `validate()` and `_check_energy()`. |
| `scripts/net/match_authority.gd` | Add `request_action_async()` and `end_turn_async()` stubs. |
| `scripts/net/local_match_authority.gd` | Forward `request_action_async()` and `end_turn_async()`. |
| `scenes/main/main.gd` | Use `request_action_async()` for attacks. Remove `_anim_end_msec`/`_anim_wait_active`. Connect to `player_query_requested`. Simplify `_try_end_turn_after_attack()`. |
| `project.godot` | Add AnimationManager to autoload list. |

### Handler phase mapping

| Current handler | New phase | Why |
|---|---|---|
| `coin_plus_10/20/30` | DAMAGE_CALC (5b) | Attacker modifier: flip coin, add bonus damage |
| `coin_fail` | CONDITIONALS (3) | Attack fails on tails — should block attack, not zero damage |
| `coin_discard_fire/fire_all/any` | POST_DAMAGE_EFFECTS (6) | Discard effects happen after damage |
| `coin_multiply_2/3` | DAMAGE_CALC (5b) | Multi-coin damage multiplier |

---

## Migration Strategy (5 incremental phases)

Each phase produces a working build. No big-bang rewrite.

### Phase 1: Foundation (zero behavior change)
- Create all 7 new data class / skeleton files
- Add empty AttackResolver as child of ManagerSystem
- Add AnimationManager autoload with `skip_animations = true`
- Register in project.godot
- All existing tests pass unchanged

### Phase 2: Wire the async path
- Add `request_action_async()` to ManagerSystem, MatchAuthority, LocalMatchAuthority
- Implement `AttackResolver.begin_attack()` replicating current `ActionAttack.apply()` logic as an async coroutine
- Switch `ActionAttack.apply()` to delegate to resolver
- Switch main.gd to use `request_action_async()` for attacks
- Remove `_anim_end_msec` watermark system from main.gd

### Phase 3: Effect queue and phase dispatch
- Extend AttackContext with queue fields
- Extend EffectRegistry with `EffectDefinition` / `dispatch_phase()`
- Rewrite effect_handlers.gd with explicit phases
- Implement resolve-queue-execute in AttackResolver
- Change KO resolution to simultaneous (step 10)

### Phase 4: AnimationManager integration
- Wire AnimationManager to coin signals
- AttackResolver awaits `enqueue_and_wait()` after coin flips
- CoinFlipOverlay delegated through AnimationManager
- Remove all animation timing from main.gd

### Phase 5: Player queries and between-turn async
- Implement AttackQuery + resolver signals
- Wire main.gd dialogs to query system
- Remove `energy_discard_pending` state from ManagerSystem
- Make `_run_cleanup()` async with animation delays
- Add player order choice for multiple between-turn effects

---

## Verification

1. **Automated tests**: `tests/test_tier0_attacks.gd` should still pass, but Tier 0 cards are straightforward and don't need manual verification at every phase. Use them as a fallback if Tier 1 issues arise.
2. **Manual testing focus: Tier 1 cards** — these have effects (coin flips, status conditions, energy discards) that exercise the pipeline phases. Verify:
   - Coin flip animations play before effects apply
   - Confusion self-damage (30) animates correctly
   - Status conditions apply after animation completes
   - Between-turn effects (poison 10dmg, burn tails=20dmg, sleep flip) animate in sequence
   - KOs resolve simultaneously after all effects
3. **New test suites** for pipeline phases, effect dispatch, damage calculation, nullification, animation queue, player queries

---

## Flowchart plain-text file

A plain-text version of the attack flowchart will be saved to `docs/attack_flowchart.txt` in the codebase for future reference, as the user requested.
