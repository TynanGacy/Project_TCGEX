# Plan: Tier 1 Card Attack Implementation — Full Parameterized Overhaul

## Context

Groups A–E and K already have handlers in `autoload/effect_handlers.gd`, but they use per-variant keys (`inflict_asleep`, `coin_plus_10`, `coin_multiply_2`, etc.). This plan replaces ALL per-variant keys with a small set of **parameterized handlers** that read config from a new `effect_params: Dictionary` field on `AttackData`. All 124 tier1 card JSONs are updated to use the new key+params format. Groups F–N are implemented using the same pattern. Result: ~14 keys instead of ~30.

Target branch: `testingAttackManager` — work directly in main repo at `C:\Users\tgsha\OneDrive\Desktop\Important Docs\Github\Project_TCGEX` (NOT in a worktree)

---

## New Unified Key Set (14 total)

| Group | Key | `effect_params` example |
|---|---|---|
| A | `inflict_status` | `{"condition": "ASLEEP"}` |
| B simple | `coin_status` | `{"condition": "PARALYZED"}` (heads → status) |
| B either | `coin_status` | `{"heads_condition": "CONFUSED", "tails_condition": "ASLEEP"}` |
| B damage-or-status | `coin_status` | `{"heads_bonus": 30, "tails_condition": "PARALYZED"}` |
| C | `coin_bonus_damage` | `{"bonus": 10}` |
| D | `coin_fail` | `{}` (no params; unchanged) |
| E | `coin_discard_energy` | `{"type": "FIRE", "count": 1}` (count `-1` = all) |
| F | `retreat_lock` | `{}` |
| F+burn | `inflict_burned_retreat_lock` | `{}` |
| G | `heal_self` | `{"amount": 30}` (amount `-1` = all) |
| G rest | `rest_self` | `{}` |
| H | `may_discard_for_bonus` | `{"type": "FIRE", "count": 1, "bonus": 20}` |
| I | `discard_energy` | `{"type": "FIRE", "count": 1}` |
| I Kindle | `kindle` | `{}` |
| J energy | `bonus_per_energy` | `{"source": "defender", "multiplier": 10}` |
| J counters | `bonus_per_damage_counter` | `{"multiplier": 10}` |
| J equal | `inflict_confused_if_equal_energy` | `{}` |
| K | `coin_multiply_damage` | `{"flips": 2}` |
| L | `attach_from_discard` | `{"type": "FIRE", "count": 2}` |
| M | `attach_from_hand` | `{"type": "GRASS", "count": 1, "target": "self"}` |
| N | `bench_damage` | `{"amount": 20, "unmodified": true}` |

---

## Critical Files

| File | Change |
|---|---|
| `scripts/cards/attack_data.gd` | Add `effect_params: Dictionary = {}` |
| `scripts/cards/card_library.gd` line 173 | Parse `effect_params` from JSON |
| `scripts/game/test_deck_factory.gd` line 251 | Same |
| `scripts/game/attack_context.gd` | Add `_query_response: Variant = null` |
| `autoload/effect_handlers.gd` | Replace all existing handlers + add Groups F–N |
| `scripts/game/pokemon_instance.gd` | Add `retreat_locked_until_turn: int = -1` |
| `scripts/actions/action_retreat.gd` | Check retreat lock in `validate()` |
| `autoload/manager_system.gd` | Clear expired locks in `_begin_turn()` (~line 528) |
| `scripts/game/attack_resolver.gd` | Step 8: await `needs_query` effects |
| `scripts/game/attack_query.gd` | Add `CHOOSE_BENCH_TARGET`, `MAY_DISCARD_FOR_BONUS`, `CHOOSE_ENERGY_FROM_HAND` kinds |
| `data/cards/DR/*.json` | Replace old keys with `effect_key` + `effect_params` |
| `data/cards/RS/*.json` | Same |
| `data/cards/SS/*.json` | Same |
| `tests/test_tier1_attacks.gd` | New GUT test file |

---

## Step-by-Step Implementation

### Step 1 — AttackData: add `effect_params`

`scripts/cards/attack_data.gd`:
```gdscript
@export var effect_params: Dictionary = {}
```

### Step 2 — JSON parsers: read `effect_params`

In `scripts/cards/card_library.gd` (`_parse_attack`, line ~173) and `scripts/game/test_deck_factory.gd` (`_parse_attack`, line ~251):
```gdscript
atk.effect_params = d.get("effect_params", {})
```

### Step 3 — AttackContext: query response slot

`scripts/game/attack_context.gd`:
```gdscript
var _query_response: Variant = null
```

### Step 4 — AttackQuery: new kinds

```gdscript
enum Kind {
    MAY_ABILITY,
    CHOOSE_ENERGY_DISCARD,
    CHOOSE_ORDER,
    GENERIC_CHOICE,
    CHOOSE_BENCH_TARGET,      # Group N
    MAY_DISCARD_FOR_BONUS,    # Group H
    CHOOSE_ENERGY_FROM_HAND,  # Group M (any-bench variant)
}
```

### Step 5 — AttackResolver: query-pausing in Step 8

Replace the effect execution loop (line ~141) to store query responses in `ctx._query_response`:
```gdscript
for effect: QueuedEffect in ctx.effect_queue:
    if effect.category == QueuedEffect.Category.ATTACKER_MODIFIER \
            or effect.category == QueuedEffect.Category.DEFENDER_MODIFIER:
        continue
    ctx._query_response = null
    if effect.needs_query and effect.query_template != null:
        player_query_requested.emit(effect.query_template)
        ctx._query_response = await player_query_resolved
    effect.execute.call(ctx)
```

### Step 6 — PokemonInstance: retreat lock field

Add to dynamic state:
```gdscript
var retreat_locked_until_turn: int = -1
```
Clear it in `release_cards()`.

### Step 7 — ActionRetreat: enforce lock

After energy check in `validate()`:
```gdscript
if active_inst.retreat_locked_until_turn >= manager.turn_number:
    return ActionResult.fail("This Pokémon is retreat-locked until end of opponent's next turn.")
```

### Step 8 — ManagerSystem: clear expired locks at turn start

In `_begin_turn(pid)` around line 528, after the per-turn flag resets:
```gdscript
for s in ["active1","active2","bench1","bench2","bench3","bench4","bench5"]:
    var inst: PokemonInstance = board_position.get_instance("p%d_%s" % [pid, s])
    if inst != null and inst.retreat_locked_until_turn != -1 \
            and inst.retreat_locked_until_turn < turn_number:
        inst.retreat_locked_until_turn = -1
```
Lock duration: handler sets `turn_number + 1`; cleared when the next `_begin_turn` increments past it.

---

### Step 9 — Rewrite ALL handlers in `effect_handlers.gd`

Remove all old per-variant registrations. Register the new parameterized set. Helper at top:
```gdscript
static func _condition_from_string(s: String) -> int:
    return PokemonInstance.SpecialCondition[s.to_upper()]

static func _energy_type_from_string(s: String) -> int:
    return PokemonCardData.EnergyType[s.to_upper()]
```

#### Group A — `inflict_status`
```gdscript
EffectRegistry.register("inflict_status", func(ctx):
    var cond: int = _condition_from_string(ctx.attack.effect_params.get("condition","ASLEEP"))
    ctx.add_post_action(func(): ctx.target.add_condition(cond))
)
```

#### Group B — `coin_status`
Handles all three sub-cases via params:
```gdscript
EffectRegistry.register("coin_status", func(ctx):
    var p: Dictionary = ctx.attack.effect_params
    if p.has("heads_bonus") or p.has("tails_condition"):
        # Ampharos-style: heads = bonus damage, tails = status
        if ctx.flip_coin():
            ctx.bonus_damage += int(p.get("heads_bonus", 0))
        elif p.has("tails_condition"):
            var c := _condition_from_string(p["tails_condition"])
            ctx.add_post_action(func(): ctx.target.add_condition(c))
    elif p.has("heads_condition") and p.has("tails_condition"):
        # Either/or: heads = one condition, tails = another
        var heads: bool = ctx.flip_coin()
        ctx.add_post_action(func():
            var c := _condition_from_string(p["heads_condition"] if heads else p["tails_condition"])
            ctx.target.add_condition(c)
        )
    else:
        # Simple: heads = apply condition
        var cond := _condition_from_string(p.get("condition", "PARALYZED"))
        if ctx.flip_coin():
            ctx.add_post_action(func(): ctx.target.add_condition(cond))
)
```

#### Group C — `coin_bonus_damage`
```gdscript
EffectRegistry.register_def("coin_bonus_damage", EffectDefinition.single(
    AttackResolver.Phase.DAMAGE_CALC,
    func(ctx, queue):
        var bonus: int = ctx.attack.effect_params.get("bonus", 10)
        if ctx.flip_coin():
            var e := QueuedEffect.new()
            e.category = QueuedEffect.Category.ATTACKER_MODIFIER
            e.execute = func(c: AttackContext) -> void: c.bonus_damage += bonus
            queue.append(e)
))
```

#### Group D — `coin_fail` (unchanged, no params needed)

#### Group E — `coin_discard_energy`
```gdscript
EffectRegistry.register_def("coin_discard_energy", EffectDefinition.single(
    AttackResolver.Phase.POST_DAMAGE_EFFECTS,
    func(ctx, queue):
        if not ctx.flip_coin():
            var type_str: String = ctx.attack.effect_params.get("type", "ANY")
            var count: int       = ctx.attack.effect_params.get("count", 1)
            var e := QueuedEffect.new()
            e.category = QueuedEffect.Category.POST_DAMAGE
            e.execute = func(c: AttackContext) -> void:
                if type_str == "ANY":
                    _discard_any(c, count)
                else:
                    _discard_typed(c, _energy_type_from_string(type_str), count if count > 0 else c.attacker.attached_energy.size())
            queue.append(e)
))
```

#### Group F — `retreat_lock`, `inflict_burned_retreat_lock`
```gdscript
EffectRegistry.register("retreat_lock", func(ctx):
    ctx.add_post_action(func():
        ctx.target.retreat_locked_until_turn = ctx.manager.turn_number + 1
    )
)
EffectRegistry.register("inflict_burned_retreat_lock", func(ctx):
    ctx.add_post_action(func():
        ctx.target.add_condition(PokemonInstance.SpecialCondition.BURNED)
        ctx.target.retreat_locked_until_turn = ctx.manager.turn_number + 1
    )
)
```

#### Group G — `heal_self`, `rest_self`
```gdscript
EffectRegistry.register("heal_self", func(ctx):
    var amount: int = ctx.attack.effect_params.get("amount", 10)
    ctx.add_post_action(func():
        ctx.attacker.heal(ctx.attacker.max_hp if amount < 0 else amount)
    )
)
EffectRegistry.register("rest_self", func(ctx):
    ctx.add_post_action(func():
        ctx.attacker.special_conditions.clear()
        ctx.attacker.heal(40)
        ctx.attacker.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
    )
)
```

#### Group H — `may_discard_for_bonus`
Runs at DAMAGE_CALC; sets `needs_query = true`. Execute reads `ctx._query_response` (bool).
```gdscript
EffectRegistry.register_def("may_discard_for_bonus", EffectDefinition.single(
    AttackResolver.Phase.DAMAGE_CALC,
    func(ctx, queue):
        var p := ctx.attack.effect_params
        var type_str: String = p.get("type", "ANY")
        var count: int = p.get("count", 1)
        var bonus: int = p.get("bonus", 20)
        var q := AttackQuery.new()
        q.kind = AttackQuery.Kind.MAY_DISCARD_FOR_BONUS
        q.player_id = ctx.player_id
        q.prompt = "Discard %d %s energy for +%d damage?" % [count, type_str, bonus]
        q.options = [true, false]
        var e := QueuedEffect.new()
        e.needs_query = true
        e.query_template = q
        e.execute = func(c: AttackContext) -> void:
            if c._query_response == true:
                if type_str == "ANY": _discard_any(c, count)
                else: _discard_typed(c, _energy_type_from_string(type_str), count)
                c.bonus_damage += bonus
        queue.append(e)
))
```

#### Group I — `discard_energy`, `kindle`
```gdscript
EffectRegistry.register("discard_energy", func(ctx):
    var type_str: String = ctx.attack.effect_params.get("type", "ANY")
    var count: int       = ctx.attack.effect_params.get("count", 1)
    ctx.add_post_action(func():
        if type_str == "ANY": _discard_any(ctx, count)
        else: _discard_typed(ctx, _energy_type_from_string(type_str), count)
    )
)
EffectRegistry.register("kindle", func(ctx):
    ctx.add_post_action(func():
        _discard_typed(ctx, PokemonCardData.EnergyType.FIRE, 1)
        _discard_typed_from_target(ctx, 1)
    )
)
```
Add helper: `_discard_typed_from_target(ctx, count)` — removes `count` energies from `ctx.target`.

#### Group J — `bonus_per_energy`, `bonus_per_damage_counter`, `inflict_confused_if_equal_energy`
```gdscript
# bonus_per_energy: {"source":"defender","multiplier":10}  — negative multiplier = damage reduction
EffectRegistry.register_def("bonus_per_energy", EffectDefinition.single(
    AttackResolver.Phase.DAMAGE_CALC,
    func(ctx, queue):
        var p := ctx.attack.effect_params
        var source: String = p.get("source", "defender")
        var mult: int      = p.get("multiplier", 10)
        var count: int = ctx.target.attached_energy.size() if source == "defender" \
                         else ctx.attacker.attached_energy.size()
        var e := QueuedEffect.new()
        e.category = QueuedEffect.Category.ATTACKER_MODIFIER
        e.execute = func(c: AttackContext) -> void: c.bonus_damage += count * mult
        queue.append(e)
))

# bonus_per_damage_counter: {"multiplier":10}
EffectRegistry.register_def("bonus_per_damage_counter", EffectDefinition.single(
    AttackResolver.Phase.DAMAGE_CALC,
    func(ctx, queue):
        var mult: int = ctx.attack.effect_params.get("multiplier", 10)
        var counters: int = (ctx.target.max_hp - ctx.target.current_hp) / 10
        var e := QueuedEffect.new()
        e.category = QueuedEffect.Category.ATTACKER_MODIFIER
        e.execute = func(c: AttackContext) -> void: c.bonus_damage += counters * mult
        queue.append(e)
))

# inflict_confused_if_equal_energy — Mind Trip
EffectRegistry.register("inflict_confused_if_equal_energy", func(ctx):
    var atk_count := ctx.attacker.attached_energy.size()
    var def_count := ctx.target.attached_energy.size()
    if atk_count == def_count:
        ctx.add_post_action(func():
            ctx.target.add_condition(PokemonInstance.SpecialCondition.CONFUSED)
        )
)
```

#### Group K — `coin_multiply_damage`
```gdscript
EffectRegistry.register_def("coin_multiply_damage", EffectDefinition.single(
    AttackResolver.Phase.DAMAGE_CALC,
    func(ctx, queue):
        var flips: int = ctx.attack.effect_params.get("flips", 2)
        var heads: int = ctx.flip_coins(flips).count(true)
        var e := QueuedEffect.new()
        e.category = QueuedEffect.Category.ATTACKER_MODIFIER
        e.execute = func(c: AttackContext) -> void:
            c.bonus_damage += c.base_damage * heads - c.base_damage
        queue.append(e)
))
```

#### Group L — `attach_from_discard`
```gdscript
EffectRegistry.register("attach_from_discard", func(ctx):
    var type_str: String = ctx.attack.effect_params.get("type", "ANY")
    var count: int       = ctx.attack.effect_params.get("count", 1)
    ctx.add_post_action(func():
        var discard: Array = ctx.manager.game_position.discards[ctx.player_id]
        var attached := 0
        for i in range(discard.size() - 1, -1, -1):
            if attached >= count: break
            var c = discard[i]
            if not (c is EnergyCardData): continue
            if type_str != "ANY" and int((c as EnergyCardData).energy_type) != _energy_type_from_string(type_str):
                continue
            discard.remove_at(i)
            ctx.attacker.attach_energy(c)
            attached += 1
        ctx.attacker.refresh_visual()
        ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
    )
)
```

#### Group M — `attach_from_hand`
- `"target": "self"` — no query needed; auto-attach first matching energy from hand to attacker.
- `"target": "any"` — uses `needs_query` + `CHOOSE_ENERGY_FROM_HAND`; pause and let player pick.

#### Group N — `bench_damage`
- Uses `needs_query = true`, kind `CHOOSE_BENCH_TARGET`.
- `options` = opponent slot IDs with non-empty Pokémon (built at DAMAGE_CALC time).
- Execute: `chosen_inst.apply_damage(amount)` directly, bypassing W/R when `unmodified = true`.

---

### Step 10 — JSON audit: replace ALL old keys with new key+params

Iterate all tier1 card JSONs. For each attack:

**Old key → new key + params:**
| Old | New key | New params |
|---|---|---|
| `inflict_asleep` | `inflict_status` | `{"condition":"ASLEEP"}` |
| `inflict_poisoned` | `inflict_status` | `{"condition":"POISONED"}` |
| `inflict_confused` | `inflict_status` | `{"condition":"CONFUSED"}` |
| `inflict_burned` | `inflict_status` | `{"condition":"BURNED"}` |
| `inflict_paralyzed` | `inflict_status` | `{"condition":"PARALYZED"}` |
| `coin_paralyzed` | `coin_status` | `{"condition":"PARALYZED"}` |
| `coin_confused` | `coin_status` | `{"condition":"CONFUSED"}` |
| `coin_poisoned` | `coin_status` | `{"condition":"POISONED"}` |
| `coin_burned` | `coin_status` | `{"condition":"BURNED"}` |
| `coin_asleep` | `coin_status` | `{"condition":"ASLEEP"}` |
| `coin_confused_or_asleep` | `coin_status` | `{"heads_condition":"CONFUSED","tails_condition":"ASLEEP"}` |
| `coin_poisoned_or_asleep` | `coin_status` | `{"heads_condition":"POISONED","tails_condition":"ASLEEP"}` |
| `coin_plus_30_or_paralyzed` | `coin_status` | `{"heads_bonus":30,"tails_condition":"PARALYZED"}` |
| `coin_plus_10` | `coin_bonus_damage` | `{"bonus":10}` |
| `coin_plus_20` | `coin_bonus_damage` | `{"bonus":20}` |
| `coin_plus_30` | `coin_bonus_damage` | `{"bonus":30}` |
| `coin_discard_fire` | `coin_discard_energy` | `{"type":"FIRE","count":1}` |
| `coin_discard_fire_all` | `coin_discard_energy` | `{"type":"FIRE","count":-1}` |
| `coin_discard_any` | `coin_discard_energy` | `{"type":"ANY","count":1}` |
| `coin_multiply_2` | `coin_multiply_damage` | `{"flips":2}` |
| `coin_multiply_3` | `coin_multiply_damage` | `{"flips":3}` |

For tier1 cards with blank `effect_key`, assign from the text pattern using the Group F–N table from the previous plan section.

---

### Step 11 — Tests: `tests/test_tier1_attacks.gd`

Follow `tests/test_tier0_attacks.gd` pattern. Coverage:
- Group A: `inflict_status` applies each condition (5 sub-cases)
- Group B: `coin_status` — heads/tails for simple, either, and damage-or-status variants
- Group C: `coin_bonus_damage` — heads adds bonus, tails doesn't
- Group D: `coin_fail` — tails blocks attack
- Group E: `coin_discard_energy` — typed and ANY variants; count=-1 removes all
- Group F: retreat lock applies; ActionRetreat fails while locked; clears after `_begin_turn`
- Group G: `heal_self` increases HP; `rest_self` clears conditions + heals + ASLEEP
- Group I: `discard_energy` removes correct energy; `kindle` removes from both sides
- Group J: `bonus_per_energy` for positive/negative multiplier; `bonus_per_damage_counter`
- Group K: `coin_multiply_damage` — 0/1/2 heads give correct damage multipliers
- Group L: `attach_from_discard` moves energy from discard to attacker

---

## Verification

1. `gut -gtest=test_tier0_attacks` still passes (no regressions after handler rewrite)
2. `gut -gtest=test_tier1_attacks` passes for all implemented groups
3. `grep -rl '"effect_key"' data/cards/ | xargs grep -L '"effect_params"'` — should return empty or only cards that intentionally have no params
4. Manual game test: retreat lock, may-discard prompt, bench-damage chooser all surface correctly
5. Push to `testingAttackManager`
