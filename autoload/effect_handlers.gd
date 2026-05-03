extends Node
## Registers all EffectRegistry handlers for attack effects.
## Loaded as an autoload after ManagerSystemSingleton so EffectRegistry is ready.
##
## All handlers now use the phase-aware EffectDefinition API.  Each handler
## receives (ctx: AttackContext, queue: Array[QueuedEffect]) and appends
## QueuedEffect objects rather than mutating state directly.
## ── Effect key tier definitions ───────────────────────────────────────────────
## Group A — Pure status conditions (29 attacks)
##   Unconditional add_condition in a post-action.  No coin flip.
##   inflict_asleep    — Hypnosis, Sleep Powder, Lullaby, Dragon Song, etc. (14)
##   inflict_poisoned  — Poison Thread, Toxic Grip, Poison Barb, etc. (10)
##   inflict_confused  — Confuse Ray (RS_99), Confusion Gas, Supersonic (SS_94) (3)
##   inflict_burned    — Super Singe (RS_100), Ring of Fire [Group F, skip] (2)
##
## Group B — Coin flip → status condition (42 attacks)
##   coin_paralyzed          — heads → PARALYZED (most common, ~22 attacks)
##   coin_confused           — heads → CONFUSED (10 attacks)
##   coin_poisoned           — heads → POISONED (6 attacks)
##   coin_burned             — heads → BURNED (5 attacks)
##   coin_asleep             — heads → ASLEEP (1 attack)
##   coin_confused_or_asleep — heads=CONFUSED / tails=ASLEEP (Illumise)
##   coin_poisoned_or_asleep — heads=POISONED / tails=ASLEEP (Volbeat)
##   coin_plus_30_or_paralyzed — heads=+30 dmg / tails=PARALYZED (Ampharos-ex)
##
## Group C — Coin flip → bonus damage (12): coin_plus_10/20/30
## Group D — Coin flip → attack fails on tails (3): coin_fail
## Group E — Coin flip → discard energy on tails (5): coin_discard_*
## Group F — Retreat lock (6): needs retreat_locked_until_turn flag on PokemonInstance
## Group G — Self-heal / remove damage counters (8): needs ctx.attacker heal + condition clear
## Group H — Energy discard for optional bonus damage (3): needs "you may discard" UI
## Group I — Energy discard, no bonus (7): post-action removes energy from attacker
## Group J — Damage scaling (7): own/defender energy count, damage counters on target
## Group K — Multiple coin flips (5): coin_multiply_2/3
## Group L — Energy from discard (5): post-action searches game_position.discard
## Group M — Energy from hand (3): needs hand interaction API
## Group N — Bench-targeted damage (4): needs chooser UI separate from attack target
## ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_register_handlers()


func _register_handlers() -> void:
	## ── Group A: unconditional status conditions ───────────────────────────────
	EffectRegistry.register("inflict_asleep", func(ctx: AttackContext) -> void:
		ctx.add_post_action(func() -> void:
			ctx.target.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
		)
	)
	EffectRegistry.register("inflict_poisoned", func(ctx: AttackContext) -> void:
		ctx.add_post_action(func() -> void:
			ctx.target.add_condition(PokemonInstance.SpecialCondition.POISONED)
		)
	)
	EffectRegistry.register("inflict_confused", func(ctx: AttackContext) -> void:
		ctx.add_post_action(func() -> void:
			ctx.target.add_condition(PokemonInstance.SpecialCondition.CONFUSED)
		)
	)
	EffectRegistry.register("inflict_burned", func(ctx: AttackContext) -> void:
		ctx.add_post_action(func() -> void:
			ctx.target.add_condition(PokemonInstance.SpecialCondition.BURNED)
		)
	)
	EffectRegistry.register("inflict_paralyzed", func(ctx: AttackContext) -> void:
		ctx.add_post_action(func() -> void:
			ctx.target.add_condition(PokemonInstance.SpecialCondition.PARALYZED)
		)
	)

	## ── Group B: coin flip → status condition ─────────────────────────────────
	EffectRegistry.register("coin_paralyzed", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.PARALYZED)
			)
	)
	EffectRegistry.register("coin_confused", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.CONFUSED)
			)
	)
	EffectRegistry.register("coin_poisoned", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.POISONED)
			)
	)
	EffectRegistry.register("coin_burned", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.BURNED)
			)
	)
	EffectRegistry.register("coin_asleep", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
			)
	)

	## Special two-outcome Group B variants.
	EffectRegistry.register("coin_confused_or_asleep", func(ctx: AttackContext) -> void:
		var heads: bool = ctx.flip_coin()
		ctx.add_post_action(func() -> void:
			if heads:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.CONFUSED)
			else:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
		)
	)
	EffectRegistry.register("coin_poisoned_or_asleep", func(ctx: AttackContext) -> void:
		var heads: bool = ctx.flip_coin()
		ctx.add_post_action(func() -> void:
			if heads:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.POISONED)
			else:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
		)
	)
	## Ampharos-ex Gigavolt: heads = +30 damage, tails = Paralyzed.
	EffectRegistry.register("coin_plus_30_or_paralyzed", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.bonus_damage += 30
		else:
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.PARALYZED)
			)
	)

	## ── Group C: coin flip adds bonus damage on heads ─────────────────────────
	_register_coin_bonus("coin_plus_10", 10)
	_register_coin_bonus("coin_plus_20", 20)
	_register_coin_bonus("coin_plus_30", 30)

	## ── Group D: attack does nothing on tails ─────────────────────────────────
	EffectRegistry.register_def("coin_fail", EffectDefinition.single(
		AttackResolver.Phase.CONDITIONALS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				ctx.attack_blocked = true
	))

	## ── Group E: discard energy on tails ──────────────────────────────────────
	EffectRegistry.register_def("coin_discard_fire", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				var effect := QueuedEffect.new()
				effect.category = QueuedEffect.Category.POST_DAMAGE
				effect.source_key = "coin_discard_fire"
				effect.description = "Discard 1 Fire energy (tails)"
				effect.execute = func(_c: AttackContext) -> void:
					_discard_typed(ctx, PokemonCardData.EnergyType.FIRE, 1)
				queue.append(effect)
	))

	EffectRegistry.register_def("coin_discard_fire_all", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				var effect := QueuedEffect.new()
				effect.category = QueuedEffect.Category.POST_DAMAGE
				effect.source_key = "coin_discard_fire_all"
				effect.description = "Discard all Fire energy (tails)"
				effect.execute = func(_c: AttackContext) -> void:
					_discard_typed(ctx, PokemonCardData.EnergyType.FIRE, -1)
				queue.append(effect)
	))

	EffectRegistry.register_def("coin_discard_any", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				var effect := QueuedEffect.new()
				effect.category = QueuedEffect.Category.POST_DAMAGE
				effect.source_key = "coin_discard_any"
				effect.description = "Discard 1 energy of any type (tails)"
				effect.execute = func(_c: AttackContext) -> void:
					_discard_any(ctx, 1)
				queue.append(effect)
	))

	## ── Group F: multi-coin damage multiplier ─────────────────────────────────
	_register_coin_multiply("coin_multiply_2", 2)
	_register_coin_multiply("coin_multiply_3", 3)


## Helper: registers a "flip coin, +N on heads" handler at DAMAGE_CALC phase.
func _register_coin_bonus(key: String, amount: int) -> void:
	EffectRegistry.register_def(key, EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if ctx.flip_coin():
				var effect := QueuedEffect.new()
				effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
				effect.source_key = key
				effect.description = "+%d damage (heads)" % amount
				effect.execute = func(c: AttackContext) -> void:
					c.bonus_damage += amount
				queue.append(effect)
	))


## Helper: registers a "flip N coins, damage = base * heads" handler.
func _register_coin_multiply(key: String, count: int) -> void:
	EffectRegistry.register_def(key, EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var heads: int = ctx.flip_coins(count).count(true)
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = key
			effect.description = "%d/%d heads — damage x%d" % [heads, count, heads]
			effect.execute = func(c: AttackContext) -> void:
				c.bonus_damage += c.base_damage * heads - c.base_damage
			queue.append(effect)
	))


## Removes [count] energy cards of [energy_type] from the attacker and
## moves them to the player's discard pile.  count = -1 removes all of that type.
func _discard_typed(ctx: AttackContext, energy_type: int, count: int) -> void:
	var to_remove: Array[CardData] = []
	for e: CardData in ctx.attacker.attached_energy:
		if e is EnergyCardData and int((e as EnergyCardData).energy_type) == energy_type:
			to_remove.append(e)
			if count > 0 and to_remove.size() >= count:
				break
	if to_remove.is_empty():
		return
	for c: CardData in to_remove:
		ctx.attacker.attached_energy.erase(c)
	ctx.manager.game_position.discard_all(ctx.player_id, to_remove)
	ctx.attacker.refresh_visual()
	ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)


## Removes [count] energy of any type from the attacker.
## When all attached energy share the same card_id the discard is automatic.
## When types differ the player is prompted via energy_discard_choice_required.
func _discard_any(ctx: AttackContext, count: int) -> void:
	var energy: Array[CardData] = ctx.attacker.attached_energy
	if energy.is_empty():
		return
	var first_id: String = energy[0].card_id
	var all_same: bool = true
	for e: CardData in energy:
		if e.card_id != first_id:
			all_same = false
			break
	if all_same:
		var to_remove: Array[CardData] = []
		for i in range(mini(count, energy.size())):
			to_remove.append(energy[i])
		for c: CardData in to_remove:
			ctx.attacker.attached_energy.erase(c)
		ctx.manager.game_position.discard_all(ctx.player_id, to_remove)
		ctx.attacker.refresh_visual()
		ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
	else:
		ctx.manager.energy_discard_pending    = true
		ctx.manager.energy_discard_player     = ctx.player_id
		ctx.manager.energy_discard_count      = count
		ctx.manager.energy_discard_slot       = ctx.attacker_slot
		ctx.manager.energy_discard_choice_required.emit(
			ctx.player_id, energy.duplicate(), count, ctx.attacker_slot
		)
