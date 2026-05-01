extends Node
## Registers all EffectRegistry handlers for attack effects.
## Loaded as an autoload after ManagerSystemSingleton so EffectRegistry is ready.

func _ready() -> void:
	_register_handlers()


func _register_handlers() -> void:
	## ── Group C: coin flip adds bonus damage on heads ─────────────────────────
	EffectRegistry.register("coin_plus_10", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.bonus_damage += 10
	)
	EffectRegistry.register("coin_plus_20", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.bonus_damage += 20
	)
	EffectRegistry.register("coin_plus_30", func(ctx: AttackContext) -> void:
		if ctx.flip_coin():
			ctx.bonus_damage += 30
	)

	## ── Group D: attack does nothing on tails ─────────────────────────────────
	EffectRegistry.register("coin_fail", func(ctx: AttackContext) -> void:
		if not ctx.flip_coin():
			ctx.base_damage = 0
	)

	## ── Group E: discard energy on tails ──────────────────────────────────────
	## Discard 1 Fire energy on tails.
	EffectRegistry.register("coin_discard_fire", func(ctx: AttackContext) -> void:
		if not ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				_discard_typed(ctx, PokemonCardData.EnergyType.FIRE, 1)
			)
	)
	## Discard ALL Fire energy on tails.
	EffectRegistry.register("coin_discard_fire_all", func(ctx: AttackContext) -> void:
		if not ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				_discard_typed(ctx, PokemonCardData.EnergyType.FIRE, -1)
			)
	)
	## Discard 1 energy of any type on tails.  Auto-discards when all attached
	## energy share the same card_id; otherwise prompts the player.
	EffectRegistry.register("coin_discard_any", func(ctx: AttackContext) -> void:
		if not ctx.flip_coin():
			ctx.add_post_action(func() -> void:
				_discard_any(ctx, 1)
			)
	)


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
