extends Node
## Registers all EffectRegistry handlers for attack effects.
## Loaded as an autoload after ManagerSystemSingleton so EffectRegistry is ready.
##
## All handlers use the parameterized pattern: a single key reads effect_params
## from AttackData at runtime, covering the full tier-1 card set with 14 keys.
##
## Key inventory:
##   inflict_status           — Group A: unconditional status
##   coin_status              — Group B: coin → status (3 sub-variants via params)
##   coin_bonus_damage        — Group C: heads → +N damage
##   coin_fail                — Group D: tails → attack blocked
##   coin_discard_energy      — Group E: tails → discard energy
##   retreat_lock             — Group F: prevent retreat until end of opponent's next turn
##   inflict_burned_retreat_lock — Group F+: burn + retreat lock
##   heal_self                — Group G: heal attacker
##   rest_self                — Group G: clear conditions, heal 40, fall ASLEEP
##   may_discard_for_bonus    — Group H: player may discard energy for +N bonus
##   discard_energy           — Group I: mandatory post-attack discard
##   kindle                   — Group I: discard 1 fire from self, 1 any from target
##   bonus_per_energy         — Group J: scale damage by energy count
##   bonus_per_damage_counter — Group J: scale damage by damage counters on target
##   inflict_confused_if_equal_energy — Group J: confuse if equal energy counts
##   coin_multiply_damage     — Group K: flip N coins, damage = base × heads
##   attach_from_discard      — Group L: move energy from discard to attacker
##   attach_from_hand         — Group M: move energy from hand to a Pokémon
##   bench_damage             — Group N: deal damage to a chosen bench Pokémon

func _ready() -> void:
	_register_handlers()


func _register_handlers() -> void:

	## ── Group A: unconditional status ─────────────────────────────────────────
	## effect_params: {"condition": "ASLEEP"}  (or POISONED, CONFUSED, BURNED, PARALYZED)
	EffectRegistry.register_def("inflict_status", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var cond: int = _condition_from_string(
				ctx.attack.effect_params.get("condition", "ASLEEP")
			)
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(cond)
			)
	))

	## ── Group B: coin flip → status ───────────────────────────────────────────
	## Sub-variant A — simple: {"condition": "PARALYZED"}
	## Sub-variant B — either: {"heads_condition": "CONFUSED", "tails_condition": "ASLEEP"}
	## Sub-variant C — damage-or-status: {"heads_bonus": 30, "tails_condition": "PARALYZED"}
	## Runs at DAMAGE_CALC so sub-variant C can modify bonus_damage before W/R.
	EffectRegistry.register_def("coin_status", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			if p.has("heads_bonus") or (p.has("tails_condition") and not p.has("heads_condition")):
				# Sub-variant C: heads = bonus damage, tails = status
				if ctx.flip_coin():
					var bonus: int = int(p.get("heads_bonus", 0))
					var e := QueuedEffect.new()
					e.category = QueuedEffect.Category.ATTACKER_MODIFIER
					e.source_key = "coin_status"
					e.execute = func(c: AttackContext) -> void: c.bonus_damage += bonus
					queue.append(e)
				elif p.has("tails_condition"):
					var c: int = _condition_from_string(p["tails_condition"])
					ctx.add_post_action(func() -> void: ctx.target.add_condition(c))
			elif p.has("heads_condition") and p.has("tails_condition"):
				# Sub-variant B: either/or
				var heads: bool = ctx.flip_coin()
				ctx.add_post_action(func() -> void:
					var c: int = _condition_from_string(
						p["heads_condition"] if heads else p["tails_condition"]
					)
					ctx.target.add_condition(c)
				)
			else:
				# Sub-variant A: simple heads → condition
				var cond: int = _condition_from_string(p.get("condition", "PARALYZED"))
				if ctx.flip_coin():
					ctx.add_post_action(func() -> void: ctx.target.add_condition(cond))
	))

	## ── Group C: coin flip adds bonus damage on heads ─────────────────────────
	## effect_params: {"bonus": 10}
	EffectRegistry.register_def("coin_bonus_damage", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if ctx.flip_coin():
				var bonus: int = ctx.attack.effect_params.get("bonus", 10)
				var effect := QueuedEffect.new()
				effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
				effect.source_key = "coin_bonus_damage"
				effect.description = "+%d damage (heads)" % bonus
				effect.execute = func(c: AttackContext) -> void: c.bonus_damage += bonus
				queue.append(effect)
	))

	## ── Group D: attack does nothing on tails ─────────────────────────────────
	EffectRegistry.register_def("coin_fail", EffectDefinition.single(
		AttackResolver.Phase.CONDITIONALS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				ctx.attack_blocked = true
	))

	## ── Group E: discard energy on tails ──────────────────────────────────────
	## effect_params: {"type": "FIRE", "count": 1}  (count -1 = all; type "ANY" = any)
	EffectRegistry.register_def("coin_discard_energy", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				var type_str: String = ctx.attack.effect_params.get("type", "ANY")
				var count: int       = ctx.attack.effect_params.get("count", 1)
				var effect := QueuedEffect.new()
				effect.category = QueuedEffect.Category.POST_DAMAGE
				effect.source_key = "coin_discard_energy"
				effect.description = "Discard %s energy (tails)" % type_str
				effect.execute = func(_c: AttackContext) -> void:
					if type_str == "ANY":
						_discard_any(ctx, count if count > 0 else ctx.attacker.attached_energy.size())
					else:
						_discard_typed(
							ctx,
							_energy_type_from_string(type_str),
							count if count > 0 else ctx.attacker.attached_energy.size()
						)
				queue.append(effect)
	))

	## ── Group F: retreat lock ─────────────────────────────────────────────────
	EffectRegistry.register_def("retreat_lock", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				ctx.target.retreat_locked_until_turn = ctx.manager.turn_number + 1
			)
	))

	## Group F + burn
	EffectRegistry.register_def("inflict_burned_retreat_lock", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(PokemonInstance.SpecialCondition.BURNED)
				ctx.target.retreat_locked_until_turn = ctx.manager.turn_number + 1
			)
	))

	## ── Group G: self-heal ────────────────────────────────────────────────────
	## effect_params: {"amount": 30}  (amount -1 = full heal)
	EffectRegistry.register_def("heal_self", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var amount: int = ctx.attack.effect_params.get("amount", 10)
			ctx.add_post_action(func() -> void:
				ctx.attacker.heal(ctx.attacker.max_hp if amount < 0 else amount)
			)
	))

	## Rest — clear conditions, heal 40, fall asleep
	EffectRegistry.register_def("rest_self", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				ctx.attacker.special_conditions.clear()
				ctx.attacker.heal(40)
				ctx.attacker.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
			)
	))

	## ── Group H: may discard energy for bonus damage ──────────────────────────
	## effect_params: {"type": "FIRE", "count": 1, "bonus": 20}
	EffectRegistry.register_def("may_discard_for_bonus", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary  = ctx.attack.effect_params
			var type_str: String = p.get("type", "ANY")
			var count: int       = p.get("count", 1)
			var bonus: int       = p.get("bonus", 20)
			var q := AttackQuery.new()
			q.kind       = AttackQuery.Kind.MAY_DISCARD_FOR_BONUS
			q.player_id  = ctx.player_id
			q.prompt     = "Discard %d %s energy for +%d damage?" % [count, type_str, bonus]
			q.options    = [true, false]
			var effect := QueuedEffect.new()
			effect.category     = QueuedEffect.Category.POST_DAMAGE
			effect.source_key   = "may_discard_for_bonus"
			effect.description  = "May discard %s x%d for +%d" % [type_str, count, bonus]
			effect.needs_query  = true
			effect.query_template = q
			effect.execute = func(c: AttackContext) -> void:
				if c._query_response == true:
					if type_str == "ANY":
						_discard_any(c, count)
					else:
						_discard_typed(c, _energy_type_from_string(type_str), count)
					c.bonus_damage += bonus
			queue.append(effect)
	))

	## ── Group H variant: may discard energy to inflict status ──────────────────
	## effect_params: {"type": "DARKNESS", "count": 1, "condition": "PARALYZED"}
	EffectRegistry.register_def("may_discard_for_status", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary    = ctx.attack.effect_params
			var type_str: String = p.get("type", "ANY")
			var count: int       = p.get("count", 1)
			var cond: int        = _condition_from_string(p.get("condition", "PARALYZED"))
			var q := AttackQuery.new()
			q.kind       = AttackQuery.Kind.MAY_DISCARD_FOR_BONUS
			q.player_id  = ctx.player_id
			q.prompt     = "Discard %d %s energy to inflict %s?" % [
				count, type_str, p.get("condition", "PARALYZED")
			]
			q.options = [true, false]
			var effect := QueuedEffect.new()
			effect.category      = QueuedEffect.Category.POST_DAMAGE
			effect.source_key    = "may_discard_for_status"
			effect.description   = "May discard %s x%d for status" % [type_str, count]
			effect.needs_query   = true
			effect.query_template = q
			effect.execute = func(c: AttackContext) -> void:
				if c._query_response == true:
					if type_str == "ANY": _discard_any(c, count)
					else: _discard_typed(c, _energy_type_from_string(type_str), count)
					c.target.add_condition(cond)
			queue.append(effect)
	))

	## ── Group I: mandatory post-attack energy discard ─────────────────────────
	## effect_params: {"type": "FIRE", "count": 1}
	EffectRegistry.register_def("discard_energy", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var type_str: String = ctx.attack.effect_params.get("type", "ANY")
			var count: int       = ctx.attack.effect_params.get("count", 1)
			ctx.add_post_action(func() -> void:
				if type_str == "ANY":
					_discard_any(ctx, count)
				else:
					_discard_typed(ctx, _energy_type_from_string(type_str), count)
			)
	))

	## Kindle — discard 1 fire from attacker AND 1 any from target.
	## Inlined (no helper-method calls) so the post-action lambda doesn't rely
	## on resolving instance methods through captured `self` — that path was
	## silently no-op'ing in tests.
	EffectRegistry.register_def("kindle", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				## Discard 1 Fire energy from attacker.
				var att_energy: Array = ctx.attacker.attached_energy
				for i in range(att_energy.size()):
					var e = att_energy[i]
					if e is EnergyCardData and (e as EnergyCardData).energy_type == PokemonCardData.EnergyType.FIRE:
						att_energy.remove_at(i)
						ctx.manager.game_position.put_in_discard(ctx.player_id, e)
						break
				## Discard 1 (any) energy from target.
				var tgt_energy: Array = ctx.target.attached_energy
				if not tgt_energy.is_empty():
					var e2 = tgt_energy[0]
					tgt_energy.remove_at(0)
					ctx.manager.game_position.put_in_discard(1 - ctx.player_id, e2)
			)
	))

	## ── Group J: damage scaling ───────────────────────────────────────────────
	## bonus_per_energy: {"source": "defender", "multiplier": 10}
	EffectRegistry.register_def("bonus_per_energy", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary  = ctx.attack.effect_params
			var source: String = p.get("source", "defender")
			var mult: int      = p.get("multiplier", 10)
			var count: int = (ctx.target.attached_energy.size()
				if source == "defender"
				else ctx.attacker.attached_energy.size())
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = "bonus_per_energy"
			effect.description = "%d energy × %d" % [count, mult]
			effect.execute = func(c: AttackContext) -> void: c.bonus_damage += count * mult
			queue.append(effect)
	))

	## bonus_per_damage_counter: {"multiplier": 10, "source": "defender"}
	## source "attacker" uses attacker's own counters (Rage, Flail, etc.)
	EffectRegistry.register_def("bonus_per_damage_counter", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = "bonus_per_damage_counter"
			effect.description = "bonus_per_damage_counter"
			## Compute everything inside the execute lambda from `c` directly —
			## avoids any closure-capture quirks with locals from the outer
			## handler. (Previous outer-capture form silently dealt only base.)
			effect.execute = func(c: AttackContext) -> void:
				var src: String = c.attack.effect_params.get("source", "defender")
				var m: int      = int(c.attack.effect_params.get("multiplier", 10))
				var who: PokemonInstance = c.attacker if src == "attacker" else c.target
				var ctrs: int   = (who.max_hp - who.current_hp) / 10
				c.bonus_damage += ctrs * m
			queue.append(effect)
	))

	## inflict_confused_if_equal_energy — Mind Trip (equal energy counts → CONFUSED)
	EffectRegistry.register_def("inflict_confused_if_equal_energy", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var atk_count: int = ctx.attacker.attached_energy.size()
			var def_count: int = ctx.target.attached_energy.size()
			if atk_count == def_count:
				ctx.add_post_action(func() -> void:
					ctx.target.add_condition(PokemonInstance.SpecialCondition.CONFUSED)
				)
	))

	## ── Group K: multi-coin damage multiplier ─────────────────────────────────
	## effect_params: {"flips": 2}
	EffectRegistry.register_def("coin_multiply_damage", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var flips: int = ctx.attack.effect_params.get("flips", 2)
			var heads: int = ctx.flip_coins(flips).count(true)
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = "coin_multiply_damage"
			effect.description = "%d/%d heads" % [heads, flips]
			effect.execute = func(c: AttackContext) -> void:
				c.bonus_damage += c.base_damage * heads - c.base_damage
			queue.append(effect)
	))

	## ── Group L: attach energy from discard ───────────────────────────────────
	## effect_params: {"type": "FIRE", "count": 2}
	EffectRegistry.register_def("attach_from_discard", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var type_str: String = ctx.attack.effect_params.get("type", "ANY")
			var count: int       = ctx.attack.effect_params.get("count", 1)
			ctx.add_post_action(func() -> void:
				var discard: Array = ctx.manager.game_position.discards[ctx.player_id]
				var attached := 0
				for i in range(discard.size() - 1, -1, -1):
					if attached >= count:
						break
					var c = discard[i]
					if not (c is EnergyCardData):
						continue
					if type_str != "ANY":
						var et: int = int((c as EnergyCardData).energy_type)
						if et != _energy_type_from_string(type_str):
							continue
					discard.remove_at(i)
					ctx.attacker.attach_energy(c)
					attached += 1
				ctx.manager.game_position.discard_changed.emit(ctx.player_id)
				ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
			)
	))

	## ── Group M: attach energy from hand ──────────────────────────────────────
	## effect_params: {"type": "GRASS", "count": 1, "target": "self"}
	## target "self" auto-attaches first matching energy from hand to attacker.
	## target "any" (future): uses needs_query + CHOOSE_ENERGY_FROM_HAND.
	EffectRegistry.register_def("attach_from_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var type_str: String = ctx.attack.effect_params.get("type", "ANY")
			var count: int       = ctx.attack.effect_params.get("count", 1)
			var target: String   = ctx.attack.effect_params.get("target", "self")
			if target == "self":
				ctx.add_post_action(func() -> void:
					var hand: Array = ctx.manager.game_position.hands[ctx.player_id]
					var attached := 0
					for i in range(hand.size() - 1, -1, -1):
						if attached >= count:
							break
						var c = hand[i]
						if not (c is EnergyCardData):
							continue
						if type_str != "ANY":
							var et: int = int((c as EnergyCardData).energy_type)
							if et != _energy_type_from_string(type_str):
								continue
						hand.remove_at(i)
						ctx.attacker.attach_energy(c)
						attached += 1
					ctx.manager.game_position.hand_changed.emit(ctx.player_id)
					ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
				)
	))

	## ── Group N: deal damage to a chosen bench Pokémon ────────────────────────
	## effect_params: {"amount": 20, "unmodified": true}
	EffectRegistry.register_def("bench_damage", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary  = ctx.attack.effect_params
			var amount: int    = p.get("amount", 20)
			var unmodified: bool = p.get("unmodified", true)
			var opp_id: int    = 1 - ctx.player_id
			var bench_slots: Array[String] = []
			for s: String in ["bench1", "bench2", "bench3", "bench4", "bench5"]:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					bench_slots.append(sid)
			if bench_slots.is_empty():
				return
			var q := AttackQuery.new()
			q.kind      = AttackQuery.Kind.CHOOSE_BENCH_TARGET
			q.player_id = ctx.player_id
			q.prompt    = "Choose an opponent's bench Pokémon to deal %d damage." % amount
			q.options   = bench_slots
			var effect := QueuedEffect.new()
			effect.category      = QueuedEffect.Category.POST_DAMAGE
			effect.source_key    = "bench_damage"
			effect.description   = "Deal %d to bench target" % amount
			effect.needs_query   = true
			effect.query_template = q
			effect.execute = func(c: AttackContext) -> void:
				var chosen_slot: String = str(c._query_response)
				var inst: PokemonInstance = c.manager.board_position.get_instance(chosen_slot)
				if inst == null:
					return
				if unmodified:
					inst.apply_damage(amount)
				else:
					c.deal_damage_to(inst, amount)
				c.manager.pokemon_state_changed.emit(chosen_slot, inst)
				if inst.is_knocked_out():
					c.manager.resolve_knockout(chosen_slot, c.player_id)
			queue.append(effect)
	))


## ── Helpers ───────────────────────────────────────────────────────────────────

static func _condition_from_string(s: String) -> int:
	return PokemonInstance.SpecialCondition[s.to_upper()]


static func _energy_type_from_string(s: String) -> int:
	return PokemonCardData.EnergyType[s.to_upper()]


## Removes [count] energy cards of [energy_type] from the attacker.
## count = -1 removes all of that type.
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


## Removes [count] energy of any type from [inst] (used by kindle for target).
func _discard_typed_from(inst: PokemonInstance, manager, player_id: int, count: int) -> void:
	if inst == null or inst.attached_energy.is_empty():
		return
	var to_remove: Array[CardData] = []
	for i in range(mini(count, inst.attached_energy.size())):
		to_remove.append(inst.attached_energy[i])
	for c: CardData in to_remove:
		inst.attached_energy.erase(c)
	manager.game_position.discard_all(player_id, to_remove)
	inst.refresh_visual()


## Removes [count] energy of any type from the attacker.
## If all energy shares the same card_id, auto-discards; otherwise prompts player.
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
