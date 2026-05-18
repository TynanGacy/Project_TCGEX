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
			var p: Dictionary = ctx.attack.effect_params
			var cond: int = _condition_from_string(p.get("condition", "ASLEEP"))
			var target: String = str(p.get("target", "defender"))
			# Toxic-style "extra strong" poison — applies a doubled-counter
			# flag alongside the POISONED condition.
			var poison_intensity: int = int(p.get("poison_intensity", 1))
			# Optional list of additional conditions to apply alongside the primary.
			var extra: Array = p.get("extra_conditions", []) as Array
			ctx.add_post_action(func() -> void:
				if target == "defender" or target == "both":
					# Refetch by slot so the status follows mid-attack swaps
					# (Luring Flame / Metal Hook / Lure Poison).
					var defender: PokemonInstance = \
						ctx.manager.board_position.get_instance(ctx.target_slot)
					if defender == null: defender = ctx.target
					defender.add_condition(cond)
					if cond == PokemonInstance.SpecialCondition.POISONED \
							and poison_intensity > 1:
						defender.poison_intensity = poison_intensity
					for ec in extra:
						defender.add_condition(_condition_from_string(str(ec)))
				if target == "self" or target == "both":
					ctx.attacker.add_condition(cond)
					for ec in extra:
						ctx.attacker.add_condition(_condition_from_string(str(ec)))
				if target == "each_defending":
					var opp_id: int = 1 - ctx.player_id
					for s: String in BoardPosition.ACTIVE_SLOTS:
						var sid := "p%d_%s" % [opp_id, s]
						var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
						if inst == null: continue
						inst.add_condition(cond)
						for ec in extra:
							inst.add_condition(_condition_from_string(str(ec)))
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
	## damage = base_damage × heads (the multiplier scales base damage).
	## effect_params:
	##   {"flips": 2}
	##   {"flips": 2, "any_heads_condition": "PARALYZED"}
	##     Wave 17 (Double Bubble): if ANY heads, inflict status on defender.
	EffectRegistry.register_def("coin_multiply_damage", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var flips: int = p.get("flips", 2)
			var any_heads_cond: String = str(p.get("any_heads_condition", ""))
			var heads: int = ctx.flip_coins(flips).count(true)
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = "coin_multiply_damage"
			effect.description = "%d/%d heads" % [heads, flips]
			effect.execute = func(c: AttackContext) -> void:
				c.bonus_damage += c.base_damage * heads - c.base_damage
			queue.append(effect)
			if any_heads_cond != "" and heads > 0:
				ctx.add_post_action(func() -> void:
					if ctx.target == null:
						return
					ctx.target.add_condition(_condition_from_string(any_heads_cond))
					ctx.manager.pokemon_state_changed.emit(ctx.target_slot, ctx.target)
				)
	))

	## ── Group L: attach energy from discard ───────────────────────────────────
	## effect_params:
	##   {"type": "FIRE", "count": 2}                    # auto-attach
	##   {"type": "FIRE", "count": 2, "coin_gate": true} # heads = attach, tails = no-op
	##   {"type": "FIRE", "count": 2, "self_damage_per_attached": 10} # Pichu-style
	EffectRegistry.register_def("attach_from_discard", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var type_str: String = p.get("type", "ANY")
			var count: int       = p.get("count", 1)
			var coin_gate: bool  = bool(p.get("coin_gate", false))
			var self_dmg: int    = int(p.get("self_damage_per_attached", 0))
			# Optional basis-driven count override (Spiral Growth uses
			# coin_flips_until_tails). When provided, replaces the static count.
			if p.has("count_basis"):
				count = _count_for_basis(ctx, str(p["count_basis"]), p)
			# Resolve the coin flip eagerly so it lands in the attack log even
			# when no energy is attached afterward.
			var pass_gate: bool = true
			if coin_gate:
				pass_gate = ctx.flip_coin()
			ctx.add_post_action(func() -> void:
				if not pass_gate:
					return
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
				if self_dmg > 0 and attached > 0:
					ctx.attacker.apply_damage(self_dmg * attached)
				ctx.manager.game_position.discard_changed.emit(ctx.player_id)
				ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
			)
	))


	## ── Group L+: attach energy from deck (search & shuffle) ──────────────────
	## effect_params: same shape as attach_from_discard but pulls from deck.
	##   {"type": "LIGHTNING", "count": 1}
	##   {"type": "ANY", "count": 1, "coin_gate": true}
	EffectRegistry.register_def("attach_from_deck", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var type_str: String = p.get("type", "ANY")
			var count: int       = p.get("count", 1)
			var coin_gate: bool  = bool(p.get("coin_gate", false))
			var pass_gate: bool = true
			if coin_gate:
				pass_gate = ctx.flip_coin()
			ctx.add_post_action(func() -> void:
				if not pass_gate:
					return
				var deck: Array = ctx.manager.game_position.decks[ctx.player_id]
				var attached := 0
				for i in range(deck.size() - 1, -1, -1):
					if attached >= count:
						break
					var c = deck[i]
					if not (c is EnergyCardData):
						continue
					if type_str != "ANY":
						var et: int = int((c as EnergyCardData).energy_type)
						if et != _energy_type_from_string(type_str):
							continue
					deck.remove_at(i)
					ctx.attacker.attach_energy(c)
					attached += 1
				ctx.manager.game_position.shuffle_deck(ctx.player_id)
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


	## ── Group R: search deck for basic Pokémon, place on bench (Tier 3 wave 5)
	## Auto-places matching basics into the first empty bench slots up to
	## `count`. Currently picks the first matching cards encountered (no player
	## choice) — sufficient for Call for Family / Team Assembly / Strike and
	## Run cases where you'd typically grab whatever you can. effect_params:
	##   {"count": 3}                                # any basic Pokémon
	##   {"count": 1, "name_slug": "magikarp"}       # specific card
	##   {"count": 2, "name_slug_any_of": ["omanyte","kabuto"], "or_any_basic": true}
	##   {"count": 1, "pokemon_type": "GRASS"}       # type-filtered basics
	EffectRegistry.register_def("search_deck_basic_to_bench", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			ctx.add_post_action(func() -> void:
				_search_deck_basic_to_bench(ctx, p)
			)
	))


	## ── Group Q: multi-turn ongoing flags (Tier 3 wave 3) ─────────────────────
	## All three set a "until_turn" flag on either attacker or defender that
	## ManagerSystem._clear_expired_retreat_locks() reclaims at end of turn.
	## effect_params: {"coin_gate": false}

	## cant_attack_next_turn — flags the ATTACKER. (Slack Off, Critical Move,
	## Lazy Punch, Slowking Amnesia self-lock, etc.)
	EffectRegistry.register_def("cant_attack_next_turn", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			if bool(p.get("coin_gate", false)) and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				ctx.attacker.cant_attack_until_turn = ctx.manager.turn_number + 1
			)
	))

	## damage_immune_next_turn — flags the ATTACKER (self-protection). Zeros
	## any damage targeted at this Pokémon during the opponent's next turn,
	## but non-damage effects still apply. (Scrunch, Dragon Dance.)
	EffectRegistry.register_def("damage_immune_next_turn", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			if bool(p.get("coin_gate", false)) and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				ctx.attacker.damage_immune_until_turn = ctx.manager.turn_number + 1
			)
	))

	## effect_immune_next_turn — flags the ATTACKER for total immunity (no
	## damage, no post-damage effects). (Agility, Iron Defense, Super Speed.)
	EffectRegistry.register_def("effect_immune_next_turn", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			if bool(p.get("coin_gate", false)) and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				ctx.attacker.effect_immune_until_turn = ctx.manager.turn_number + 1
			)
	))


	## ── Group P: conditional bonus damage (Tier 3 wave 1.5) ──────────────────
	## Adds a flat bonus when a binary condition on the defender holds. Covers
	## "If the Defending Pokémon is X / has X / has any damage counters …" attacks.
	## effect_params:
	##   {
	##     "condition": "defender_has_damage_counters" | "defender_is_evolved"
	##                | "defender_is_pokemon_ex" | "defender_has_status"
	##                | "defender_is_card",
	##     "bonus": 30,
	##     "card_slug": "seviper"   # only for defender_is_card
	##   }
	EffectRegistry.register_def("conditional_bonus_damage", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			if not _check_defender_condition(ctx, str(p.get("condition", ""))):
				return
			var bonus: int = int(p.get("bonus", 0))
			if bonus == 0:
				return
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = "conditional_bonus_damage"
			effect.description = "+%d if %s" % [bonus, p.get("condition", "?")]
			effect.execute = func(c: AttackContext) -> void: c.bonus_damage += bonus
			queue.append(effect)
	))


	## ── Group O: damage scaling by board state (Tier 3 wave 1) ────────────────
	## Generalized handler covering 60+ "X damage times Y" attacks. effect_params:
	##   {
	##     "basis":         <see below>,
	##     "per_unit":      10,            # damage per counted unit
	##     "energy_type":   "GRASS",       # optional, for *_of_type bases
	##     "pokemon_type":  "WATER",       # optional, for bench_pokemon_of_type
	##     "max_units":     5,             # optional cap on the count
	##     "flips":         4              # required for coin_flips_heads basis
	##   }
	##
	## Supported basis values:
	##   damage_counters_target      - damage counters on the defender
	##   damage_counters_attacker    - damage counters on the attacker (Flail, Rage)
	##   energy_attached_target      - energy cards attached to the defender
	##   energy_attached_attacker    - energy cards attached to the attacker
	##   energy_attached_all         - energy cards on every Pokémon in play
	##   energy_attached_own         - energy cards on attacker's whole side
	##   energy_attached_opp         - energy cards on defender's whole side
	##   energy_of_type_attacker     - filtered by energy_type, on the attacker
	##   energy_of_type_target       - filtered by energy_type, on the defender
	##   bench_pokemon_count         - own benched Pokémon
	##   bench_pokemon_of_type       - own benched Pokémon filtered by pokemon_type
	##   coin_flips_heads            - flip `flips` coins, count heads
	##   coin_flips_per_energy_heads - flip 1 coin per energy on attacker, count heads
	##   coin_flips_until_tails      - flip until tails, count heads (no upper bound)
	##   extra_energy_beyond_cost    - energy on attacker minus this attack's cost
	##   energy_attached_actives_own - energy on both of attacker's own active slots
	##   energy_attached_actives_both- energy on every active slot in play (both sides)
	##   energy_attached_pair        - attacker + defender combined
	##   energy_types_attacker       - distinct EnergyType count on attacker
	##   damage_counters_actives_own - sum of damage counters on both own actives
	##   retreat_cost_target         - target Pokémon's retreat_cost (in colorless)
	##
	## Optional `direction: "subtract"` reverses the bonus into a damage
	## reduction (with `min_damage` floor). Used for SS_100 Wailord Dwindling Wave.
	EffectRegistry.register_def("damage_scaling", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var basis: String = p.get("basis", "")
			var per_unit: int = int(p.get("per_unit", 10))
			# Optional coin_gate at damage-calc time. Tails = the scaling effect
			# does nothing (base_damage still resolves normally).
			if bool(p.get("coin_gate", false)) and not ctx.flip_coin():
				return
			var units: int = _count_for_basis(ctx, basis, p)
			if p.has("max_units"):
				units = mini(units, int(p["max_units"]))
			if units <= 0:
				return
			var bonus: int = units * per_unit
			var direction: String = str(p.get("direction", "add"))
			var min_damage: int = int(p.get("min_damage", 0))
			var effect := QueuedEffect.new()
			effect.category = QueuedEffect.Category.ATTACKER_MODIFIER
			effect.source_key = "damage_scaling"
			effect.description = "%s × %d %s%d" % [basis, units,
				"-" if direction == "subtract" else "+", bonus]
			if direction == "subtract":
				effect.execute = func(c: AttackContext) -> void:
					c.bonus_damage -= bonus
					# Floor: never let base+bonus drop below min_damage.
					var total: int = c.base_damage + c.bonus_damage
					if total < min_damage:
						c.bonus_damage += (min_damage - total)
			else:
				effect.execute = func(c: AttackContext) -> void: c.bonus_damage += bonus
			queue.append(effect)
	))


	## ── Wave 7: simple damage modifiers and AoE variants ─────────────────────

	## self_damage — attacker deals damage to itself.
	## effect_params:
	##   {"amount": 20}                            # unconditional
	##   {"amount": 10, "coin_gate": true}         # heads → self-damage
	##   {"amount": 10, "coin_gate": true, "tails": true}  # tails → self-damage
	EffectRegistry.register_def("self_damage", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var amount: int   = int(p.get("amount", 10))
			var coin_gate: bool = bool(p.get("coin_gate", false))
			var tails_triggers: bool = bool(p.get("tails", false))
			if coin_gate:
				var heads: bool = ctx.flip_coin()
				# trigger when heads==!tails_triggers
				if heads == tails_triggers:
					return
			ctx.add_post_action(func() -> void:
				ctx.attacker.apply_damage(amount)
				ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
				if ctx.attacker.is_knocked_out():
					ctx.manager.resolve_knockout(ctx.attacker_slot, 1 - ctx.player_id)
			)
	))

	## place_damage_counters — direct damage-counter placement (bypasses W/R, ignores immunities).
	## effect_params:
	##   {"count": 1, "target": "defender"}         # primary target
	##   {"count": 2, "target": "each_defending"}   # both opp active slots
	##   {"count": 1, "target": "each_opp"}         # every opp Pokémon in play
	##   {"count": 1, "target": "any_opp_query"}    # player picks one opp Pokémon
	##   {"count": 1, "count_basis": "damage_counters_attacker"} # Damage Curse:
	##     final count = base count + units from basis. Reuses damage_scaling bases.
	EffectRegistry.register_def("place_damage_counters", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int    = int(p.get("count", 1))
			var target: String = str(p.get("target", "defender"))
			# Optional basis-driven count addition (Damage Curse).
			if p.has("count_basis"):
				count += _count_for_basis(ctx, str(p["count_basis"]), p)
			var dmg: int      = count * 10
			if target == "any_opp_query":
				var opp_id: int = 1 - ctx.player_id
				var options: Array[String] = []
				for sid: String in BoardPosition.all_slot_ids(opp_id):
					if not ctx.manager.board_position.is_empty(sid):
						options.append(sid)
				if options.is_empty():
					return
				var q := AttackQuery.new()
				q.kind      = AttackQuery.Kind.CHOOSE_BENCH_TARGET
				q.player_id = ctx.player_id
				q.prompt    = "Choose 1 of your opponent's Pokémon to place %d damage counter(s)." % count
				q.options   = options
				var eff := QueuedEffect.new()
				eff.category     = QueuedEffect.Category.POST_DAMAGE
				eff.source_key   = "place_damage_counters"
				eff.needs_query  = true
				eff.query_template = q
				eff.execute = func(c: AttackContext) -> void:
					var slot: String = str(c._query_response)
					var inst: PokemonInstance = c.manager.board_position.get_instance(slot)
					if inst == null: return
					inst.apply_damage(dmg)
					c.manager.pokemon_state_changed.emit(slot, inst)
					if inst.is_knocked_out():
						c.manager.resolve_knockout(slot, c.player_id)
				queue.append(eff)
				return
			ctx.add_post_action(func() -> void:
				var slots: Array[String] = _place_counters_targets(ctx, target)
				for sid: String in slots:
					var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
					if inst == null: continue
					inst.apply_damage(dmg)
					ctx.manager.pokemon_state_changed.emit(sid, inst)
					if inst.is_knocked_out():
						ctx.manager.resolve_knockout(sid, ctx.player_id)
			)
	))

	## aoe_damage — flat damage to a group of targets (bypasses W/R for benched
	## per Pokémon TCG rules).
	## effect_params:
	##   {"amount": 10, "side": "opp_bench"}                # each opp benched
	##   {"amount": 10, "side": "own_bench"}                # each own benched
	##   {"amount": 10, "side": "all_bench"}                # each benched (both)
	##   {"amount": 80, "side": "each_active"}              # both players' actives
	##   {"amount": 20, "side": "opp_all"}                  # each opp Pokémon
	##   {"amount": 20, "side": "opp_all", "coin_gate": true} # heads-gated
	##   {"amount": 20, "side": "opp_bench", "count": 2}    # cap to N targets
	EffectRegistry.register_def("aoe_damage", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var amount: int   = int(p.get("amount", 10))
			var side: String  = str(p.get("side", "opp_bench"))
			var coin_gate: bool = bool(p.get("coin_gate", false))
			var max_count: int = int(p.get("count", -1))  # -1 = uncapped
			if coin_gate and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				var slots: Array[String] = _aoe_targets(ctx, side)
				# Cap to `count` targets if specified — keeps the first N
				# encountered (BENCH_SLOTS order).
				if max_count >= 0 and slots.size() > max_count:
					slots.resize(max_count)
				for sid: String in slots:
					var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
					if inst == null: continue
					inst.apply_damage(amount)
					ctx.manager.pokemon_state_changed.emit(sid, inst)
					if inst.is_knocked_out():
						# Owner of KO'd pokemon decides prize side: the opponent of
						# the slot's player gets the prize.
						var slot_owner: int = int(sid.substr(1, 1))
						ctx.manager.resolve_knockout(sid, 1 - slot_owner)
			)
	))

	## heal_team — remove damage counters from each of your Pokémon.
	## effect_params:
	##   {"counters": 1, "scope": "all"}                          # each of your Pokémon
	##   {"counters": 1, "scope": "actives"}                      # each of your Actives
	##   {"counters": 2, "scope": "all", "exclude_attacker": true}# Healing Egg pattern
	##   {"counters": 2, "min_counters": 1}                       # remove min if only some
	EffectRegistry.register_def("heal_team", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var counters: int = int(p.get("counters", 1))
			var scope: String = str(p.get("scope", "all"))
			var exclude_attacker: bool = bool(p.get("exclude_attacker", false))
			ctx.add_post_action(func() -> void:
				var slot_set: Array[String]
				if scope == "actives":
					slot_set = []
					for s: String in BoardPosition.ACTIVE_SLOTS:
						slot_set.append("p%d_%s" % [ctx.player_id, s])
				else:
					slot_set = BoardPosition.all_slot_ids(ctx.player_id)
				for sid: String in slot_set:
					if exclude_attacker and sid == ctx.attacker_slot:
						continue
					var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
					if inst == null: continue
					inst.heal(counters * 10)
					ctx.manager.pokemon_state_changed.emit(sid, inst)
			)
	))

	## ignore_resistance — set the skip_resistance flag for this attack's damage calc.
	## Fires at CONDITIONALS so the flag is set before DAMAGE_CALC builds entries.
	EffectRegistry.register_def("ignore_resistance", EffectDefinition.single(
		AttackResolver.Phase.CONDITIONALS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.skip_resistance = true
	))

	## ignore_weakness_resistance — both flags. Swift, Feint Attack family (when
	## not also requiring target redirection).
	EffectRegistry.register_def("ignore_weakness_resistance", EffectDefinition.single(
		AttackResolver.Phase.CONDITIONALS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.skip_weakness = true
			ctx.skip_resistance = true
	))

	## swap_with_opp_bench_pre_damage — runs at PRE_DAMAGE_EFFECTS. Swaps the
	## defender (primary) with an opponent's bench Pokémon BEFORE damage calc.
	## Used by Luring Flame, Metal Hook, Lure Poison. After the swap, ctx.target
	## is refreshed so DAMAGE_CALC and post-damage chains hit the new defender.
	## effect_params:
	##   {}                                # opp chooses (Luring Flame)
	##   {"attacker_chooses": true}        # attacker picks (Metal Hook, Lure Poison)
	EffectRegistry.register_def("swap_with_opp_bench_pre_damage", EffectDefinition.single(
		AttackResolver.Phase.PRE_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var attacker_chooses: bool = bool(p.get("attacker_chooses", false))
			var opp_id: int = 1 - ctx.player_id
			var bench_slots: Array[String] = []
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					bench_slots.append(sid)
			if bench_slots.is_empty():
				return  # No-op if no bench (rule per card text)
			var q := AttackQuery.new()
			q.kind      = AttackQuery.Kind.CHOOSE_BENCH_TARGET
			q.player_id = ctx.player_id if attacker_chooses else opp_id
			q.prompt    = "Choose a Benched Pokémon to switch into the Active spot."
			q.options   = bench_slots
			var eff := QueuedEffect.new()
			eff.category      = QueuedEffect.Category.PRE_DAMAGE
			eff.source_key    = "swap_with_opp_bench_pre_damage"
			eff.needs_query   = true
			eff.query_template = q
			eff.execute = func(c: AttackContext) -> void:
				var bench_sid: String = str(c._query_response)
				c.manager.board_position.swap(c.target_slot, bench_sid)
				# Refresh ctx.target so downstream phases hit the new occupant.
				c.target = c.manager.board_position.get_instance(c.target_slot)
				c.manager.pokemon_state_changed.emit(c.target_slot, c.target)
				var moved_to_bench: PokemonInstance = \
					c.manager.board_position.get_instance(bench_sid)
				c.manager.pokemon_state_changed.emit(bench_sid, moved_to_bench)
			queue.append(eff)
	))


	## search_deck_to_hand — pull cards matching a filter from your deck into
	## your hand, then shuffle. Auto-picks the first N matching cards from the
	## top of the deck (no player choice).
	## effect_params:
	##   {"count": 2}                                                # any 2
	##   {"count": 1, "filter": "trainer"}                           # Jump Catch
	##   {"count": 1, "filter": "evolution"}                         # Fast Evolution
	##   {"count": 3, "filter": "evolves_from", "evolves_from": "eevee"}  # Signs of Evolution (Eevee)
	##   {"count": 2, "filter": "name_slug_any_of",
	##    "name_slug_any_of": ["silcoon","beautifly","cascoon","dustox"]}  # Wurmple Signs
	##   {"count": 1, "filter": "any", "condition": "same_energy_counts"} # Synchronized Search
	##   {"count_basis": "energy_attached_attacker",
	##    "filter": "basic_or_evolution"}                                   # Alluring Smile
	EffectRegistry.register_def("search_deck_to_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			# Optional gating: condition uses the same predicates as
			# conditional_bonus_damage / conditional_inflict_status.
			var cond: String = str(p.get("condition", ""))
			if cond != "" and not _check_defender_condition(ctx, cond):
				return
			var count: int = int(p.get("count", 1))
			var basis: String = str(p.get("count_basis", ""))
			if basis == "energy_attached_attacker":
				count = ctx.attacker.attached_energy.size()
			var filt: String = str(p.get("filter", "any"))
			var slug: String = str(p.get("evolves_from", ""))
			var slug_any: Array = p.get("name_slug_any_of", []) as Array
			ctx.add_post_action(func() -> void:
				var deck: Array = ctx.manager.game_position.decks[ctx.player_id]
				var candidates: Array[CardData] = []
				for c in deck:
					if _search_match(c, filt, slug, slug_any):
						candidates.append(c)
				var max_pick: int = mini(count, candidates.size())
				if max_pick == 0:
					ctx.manager.game_position.shuffle_deck(ctx.player_id)
					return
				var picks: Array[CardData] = candidates
				if candidates.size() > max_pick:
					picks = await _ask_pick_cards(ctx, candidates, max_pick,
							"Search your deck and put cards into your hand")
				for c in picks:
					deck.erase(c)
					ctx.manager.game_position.put_in_hand(ctx.player_id, c)
				ctx.manager.game_position.shuffle_deck(ctx.player_id)
			)
	))

	## heal_self_by_damage_dealt — remove damage counters from the attacker equal
	## to the damage dealt this attack. Leech Life / Swallow.
	## effect_params: {}
	EffectRegistry.register_def("heal_self_by_damage_dealt", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				if ctx.final_damage > 0:
					ctx.attacker.heal(ctx.final_damage)
					ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
			)
	))

	## damage_to_almost_ko — fill the defender with damage counters until they
	## are `ko_distance` HP away from being knocked out. Coin-gated for Life Drain.
	## effect_params:
	##   {"ko_distance": 10}                    # auto-applies
	##   {"ko_distance": 10, "coin_gate": true} # heads triggers
	EffectRegistry.register_def("damage_to_almost_ko", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var ko_dist: int = int(p.get("ko_distance", 10))
			if bool(p.get("coin_gate", false)) and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				var tgt: PokemonInstance = ctx.target
				if tgt == null: return
				var dmg: int = tgt.current_hp - ko_dist
				if dmg <= 0: return
				tgt.apply_damage(dmg)
				ctx.manager.pokemon_state_changed.emit(ctx.target_slot, tgt)
				# Should never KO by design, but be safe.
				if tgt.is_knocked_out():
					ctx.manager.resolve_knockout(ctx.target_slot, ctx.player_id)
			)
	))

	## coin_count_to_ko — flip N coins; if all are heads, KO the defender directly.
	## effect_params:
	##   {"flips": 2}                              # Judgement
	##   {"flips": 2, "min_heads": 2}              # explicit threshold
	EffectRegistry.register_def("coin_count_to_ko", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var flips: int = int(p.get("flips", 2))
			var min_heads: int = int(p.get("min_heads", flips))  # default = all heads
			var heads: int = ctx.flip_coins(flips).count(true)
			if heads < min_heads:
				return
			ctx.add_post_action(func() -> void:
				var tgt: PokemonInstance = ctx.target
				if tgt == null: return
				# Directly KO: set HP to 0 then resolve.
				tgt.apply_damage(tgt.current_hp)
				ctx.manager.pokemon_state_changed.emit(ctx.target_slot, tgt)
				if tgt.is_knocked_out():
					ctx.manager.resolve_knockout(ctx.target_slot, ctx.player_id)
			)
	))


	## ── Wave 8: target redirection, forced switch, and energy search ─────────

	## damage_chosen_target — "Choose 1 of your opponent's Pokémon. This attack
	## does N damage to that Pokémon." JSON base_damage MUST be 0 — the handler
	## applies damage directly to the chosen slot. By default, W/R is bypassed
	## for benched targets (standard 2007-era rule) and applied for active ones;
	## `ignore_wr` overrides that to always bypass.
	## effect_params:
	##   {"amount": 20}                         # base case
	##   {"amount": 20, "ignore_wr": true}      # Feint Attack family
	##   {"amount": 50, "coin_gate": true, "ignore_wr": true}  # Quick Dive
	EffectRegistry.register_def("damage_chosen_target", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var amount: int   = int(p.get("amount", 10))
			var ignore_wr: bool = bool(p.get("ignore_wr", false))
			var coin_gate: bool = bool(p.get("coin_gate", false))
			if coin_gate and not ctx.flip_coin():
				return
			var opp_id: int = 1 - ctx.player_id
			var options: Array[String] = []
			for sid: String in BoardPosition.all_slot_ids(opp_id):
				if not ctx.manager.board_position.is_empty(sid):
					options.append(sid)
			if options.is_empty():
				return
			var q := AttackQuery.new()
			q.kind      = AttackQuery.Kind.CHOOSE_BENCH_TARGET
			q.player_id = ctx.player_id
			q.prompt    = "Choose 1 of your opponent's Pokémon for %d damage." % amount
			q.options   = options
			var eff := QueuedEffect.new()
			eff.category      = QueuedEffect.Category.POST_DAMAGE
			eff.source_key    = "damage_chosen_target"
			eff.description   = "%d to chosen target" % amount
			eff.needs_query   = true
			eff.query_template = q
			eff.execute = func(c: AttackContext) -> void:
				var slot: String = str(c._query_response)
				var inst: PokemonInstance = c.manager.board_position.get_instance(slot)
				if inst == null:
					return
				# Compute scaled amount if per_unit_basis is set (Breaking Impact).
				var final_amount: int = amount
				if p.has("per_unit_basis"):
					var basis: String = str(p["per_unit_basis"])
					var per_unit: int = int(p.get("per_unit", 10))
					var units: int = 0
					match basis:
						"retreat_cost_chosen_target":
							if inst.card != null:
								units = int(inst.card.retreat_cost)
						"energy_attached_chosen_target":
							units = inst.attached_energy.size()
						"damage_counters_chosen_target":
							units = (inst.max_hp - inst.current_hp) / 10
					final_amount = units * per_unit
				# Bench targets always bypass W/R; active targets apply W/R unless ignore_wr.
				var is_active: bool = slot.ends_with("_active1") or slot.ends_with("_active2")
				var dmg: int
				if ignore_wr or not is_active:
					dmg = final_amount
				else:
					dmg = ActionAttack._compute_damage(final_amount, c.attacker, inst,
						c.skip_weakness, c.skip_resistance)
				if dmg <= 0:
					return
				inst.apply_damage(dmg)
				c.manager.pokemon_state_changed.emit(slot, inst)
				if inst.is_knocked_out():
					c.manager.resolve_knockout(slot, c.player_id)
			queue.append(eff)
	))

	## force_switch_opp — "Your opponent switches the Defending Pokémon with 1 of
	## his or her Benched Pokémon." Queries the OPPONENT (or the ATTACKER if
	## `attacker_chooses: true`) for a bench slot, then swaps. No-op if opp has
	## no bench.
	## effect_params:
	##   {}                          # opp picks (Whirlwind / Roar / Fling)
	##   {"attacker_chooses": true}  # attacker picks (Luring Flame / Metal Hook)
	EffectRegistry.register_def("force_switch_opp", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var attacker_chooses: bool = bool(p.get("attacker_chooses", false))
			var opp_id: int = 1 - ctx.player_id
			# Find a non-empty bench slot on the opponent's side.
			var bench_slots: Array[String] = []
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					bench_slots.append(sid)
			if bench_slots.is_empty():
				return
			var q := AttackQuery.new()
			q.kind      = AttackQuery.Kind.CHOOSE_BENCH_TARGET
			q.player_id = ctx.player_id if attacker_chooses else opp_id
			q.prompt    = "Choose a Benched Pokémon to switch into the Active spot."
			q.options   = bench_slots
			var eff := QueuedEffect.new()
			eff.category      = QueuedEffect.Category.POST_DAMAGE
			eff.source_key    = "force_switch_opp"
			eff.description   = "Force opponent to switch"
			eff.needs_query   = true
			eff.query_template = q
			eff.execute = func(c: AttackContext) -> void:
				var bench_sid: String = str(c._query_response)
				# Defender slot = the attack's primary target (the opp's active).
				c.manager.board_position.swap(c.target_slot, bench_sid)
				c.manager.pokemon_state_changed.emit(c.target_slot,
					c.manager.board_position.get_instance(c.target_slot))
				c.manager.pokemon_state_changed.emit(bench_sid,
					c.manager.board_position.get_instance(bench_sid))
			queue.append(eff)
	))

	## search_deck_energy_to_hand — pull basic Energy cards from your deck into
	## your hand, then shuffle. Auto-picks (no player choice) — first matching
	## cards from the top of the deck.
	## effect_params:
	##   {"count": 2}                            # any 2 basic energy
	##   {"count": 3, "distinct_types": true}    # up to 3 different types
	EffectRegistry.register_def("search_deck_energy_to_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int    = int(p.get("count", 1))
			var distinct: bool = bool(p.get("distinct_types", false))
			ctx.add_post_action(func() -> void:
				var deck: Array = ctx.manager.game_position.decks[ctx.player_id]
				var candidates: Array[CardData] = []
				for c in deck:
					if c is EnergyCardData:
						candidates.append(c)
				## distinct_types: dedupe candidate pool before sizing the cap
				## so e.g. 3 grass + 1 fire with count=3 yields 2 picks, not 3.
				if distinct:
					var seen: Dictionary = {}
					var deduped: Array[CardData] = []
					for c in candidates:
						var et: int = int((c as EnergyCardData).energy_type)
						if seen.has(et):
							continue
						seen[et] = true
						deduped.append(c)
					candidates = deduped
				var max_pick: int = mini(count, candidates.size())
				if max_pick == 0:
					ctx.manager.game_position.shuffle_deck(ctx.player_id)
					return
				var picks: Array[CardData] = candidates
				if candidates.size() > max_pick:
					picks = await _ask_pick_cards(ctx, candidates, max_pick,
							"Search your deck for Energy cards")
				for c in picks:
					deck.erase(c)
					ctx.manager.game_position.put_in_hand(ctx.player_id, c)
				ctx.manager.game_position.shuffle_deck(ctx.player_id)
			)
	))

	## search_discard_energy_to_hand — pull basic Energy cards from your discard
	## into your hand. Auto-picks from the bottom up.
	## effect_params: {"count": 2}
	EffectRegistry.register_def("search_discard_energy_to_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int    = int(p.get("count", 1))
			ctx.add_post_action(func() -> void:
				var discard: Array = ctx.manager.game_position.discards[ctx.player_id]
				var candidates: Array[CardData] = []
				for c in discard:
					if c is EnergyCardData:
						candidates.append(c)
				var max_pick: int = mini(count, candidates.size())
				if max_pick == 0:
					return
				var picks: Array[CardData] = candidates
				if candidates.size() > max_pick:
					picks = await _ask_pick_cards(ctx, candidates, max_pick,
							"Recover Energy cards from your discard pile")
				for c in picks:
					discard.erase(c)
					ctx.manager.game_position.put_in_hand(ctx.player_id, c)
				ctx.manager.game_position.discard_changed.emit(ctx.player_id)
			)
	))


	## ── Wave 9: multi-turn flags, hand disruption, energy discard from target ─

	## smokescreen — set the next-attack-coin-fail flag on the defender. When the
	## defender next attacks, AttackResolver's CONDITIONALS phase flips a coin;
	## tails blocks the attack outright. Flag is one-shot.
	## effect_params: {}
	EffectRegistry.register_def("smokescreen", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				ctx.target.next_attack_coin_fail_until_turn = ctx.manager.turn_number + 1
			)
	))

	## damage_reduction_self_next_turn — Granite Head. Flag attacker so incoming
	## damage during opponent's next turn is reduced by `amount` after W/R.
	## effect_params: {"amount": 10}
	EffectRegistry.register_def("damage_reduction_self_next_turn", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var amount: int = int(ctx.attack.effect_params.get("amount", 10))
			ctx.add_post_action(func() -> void:
				ctx.attacker.damage_reduction_until_turn = ctx.manager.turn_number + 1
				ctx.attacker.damage_reduction_amount    = amount
			)
	))

	## discard_from_hand_random — choose N cards from opponent's hand without
	## looking and discard them. Optional coin gate.
	## effect_params: {"count": 1, "coin_gate": true}
	EffectRegistry.register_def("discard_from_hand_random", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int    = int(p.get("count", 1))
			var coin_gate: bool = bool(p.get("coin_gate", false))
			if coin_gate and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				var opp_id: int = 1 - ctx.player_id
				var hand: Array = ctx.manager.game_position.hands[opp_id]
				var to_discard: int = mini(count, hand.size())
				for i in range(to_discard):
					var idx: int = randi() % hand.size()
					var c: CardData = hand[idx]
					hand.remove_at(idx)
					ctx.manager.game_position.put_in_discard(opp_id, c)
				ctx.manager.game_position.hand_changed.emit(opp_id)
			)
	))

	## discard_attached_energy_target — flip-gated discard of an energy attached
	## to the defender. (Removal Beam.)
	## effect_params: {"count": 1, "coin_gate": true, "type": "ANY"}
	EffectRegistry.register_def("discard_attached_energy_target", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int    = int(p.get("count", 1))
			var coin_gate: bool = bool(p.get("coin_gate", false))
			var type_str: String = str(p.get("type", "ANY"))
			if coin_gate and not ctx.flip_coin():
				return
			ctx.add_post_action(func() -> void:
				var t_energy: Array = ctx.target.attached_energy
				if t_energy.is_empty():
					return
				var taken: int = 0
				var want: int = -1
				if type_str != "ANY":
					want = _energy_type_from_string(type_str)
				for i in range(t_energy.size() - 1, -1, -1):
					if taken >= count: break
					var e = t_energy[i]
					if not (e is EnergyCardData): continue
					if want >= 0 and int((e as EnergyCardData).energy_type) != want: continue
					t_energy.remove_at(i)
					ctx.manager.game_position.put_in_discard(1 - ctx.player_id, e)
					taken += 1
				ctx.target.refresh_visual()
				ctx.manager.pokemon_state_changed.emit(ctx.target_slot, ctx.target)
			)
	))

	## draw_cards — draw N cards from your deck. Optional gating on opponent's
	## board state (e.g. Cosmic Draw fires only if opp has an Evolved Pokémon).
	## effect_params:
	##   {"count": 1}                                 # unconditional
	##   {"count": 3, "condition": "opp_has_evolved"} # gated
	EffectRegistry.register_def("draw_cards", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int    = int(p.get("count", 1))
			var cond: String  = str(p.get("condition", ""))
			ctx.add_post_action(func() -> void:
				if cond == "opp_has_evolved":
					var opp_id: int = 1 - ctx.player_id
					var found: bool = false
					for sid: String in BoardPosition.all_slot_ids(opp_id):
						var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
						if inst == null or inst.card == null:
							continue
						if inst.prior_stages.size() > 0 or int(inst.card.stage) != 0:
							found = true
							break
					if not found:
						return
				var deck: Array = ctx.manager.game_position.decks[ctx.player_id]
				for _i in range(count):
					if deck.is_empty():
						break
					var c: CardData = deck.pop_back()
					ctx.manager.game_position.put_in_hand(ctx.player_id, c)
			)
	))


	## bonus_damage_next_turn — set up a one-shot damage bonus for the attacker's
	## next turn (consumed by AttackResolver at the start of the next attack).
	## effect_params:
	##   {"amount": 40}                        # Dragon Dance — any attack
	##   {"amount": 50, "attack_name": "Slash"} # Focus Energy — specific attack
	EffectRegistry.register_def("bonus_damage_next_turn", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var amount: int = int(p.get("amount", 10))
			var attack_name: String = str(p.get("attack_name", ""))
			ctx.add_post_action(func() -> void:
				ctx.attacker.next_turn_attack_bonuses.append({
					"amount": amount,
					"attack_name": attack_name,
					"until_turn": ctx.manager.turn_number + 2,
				})
			)
	))

	## discard_or_fail — discard N basic Energy cards of [type] attached to the
	## attacker, or the attack does nothing. Fires at CONDITIONALS so attack_blocked
	## can prevent damage from being calculated. Use effect_chain for downstream
	## effects (e.g. Critical Move chains cant_attack_next_turn after discarding).
	## effect_params:
	##   {"count": 2, "type": "ANY"}     # Fire Spin
	##   {"count": 1, "type": "ANY"}     # Critical Move
	EffectRegistry.register_def("discard_or_fail", EffectDefinition.single(
		AttackResolver.Phase.CONDITIONALS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int = int(p.get("count", 1))
			var type_str: String = str(p.get("type", "ANY"))
			var want: int = -1
			if type_str != "ANY":
				want = _energy_type_from_string(type_str)
			# Count eligible basic-energy cards we could discard.
			var eligible: Array[CardData] = []
			for e: CardData in ctx.attacker.attached_energy:
				if not (e is EnergyCardData): continue
				if not DeckValidator.is_basic_energy(e): continue
				if want >= 0 and int((e as EnergyCardData).energy_type) != want: continue
				eligible.append(e)
				if eligible.size() >= count: break
			if eligible.size() < count:
				ctx.attack_blocked = true
				return
			# Discard eagerly so chained effects see the post-discard state.
			for c: CardData in eligible:
				ctx.attacker.attached_energy.erase(c)
			ctx.manager.game_position.discard_all(ctx.player_id, eligible)
			ctx.attacker.refresh_visual()
			ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
	))

	## devolve_each_evolved — for every evolved Pokémon on the opponent's side,
	## remove the highest Stage Evolution card and put it on top of the opponent's
	## deck. Pull Down.
	## effect_params:
	##   {}                                  # all opp evolved
	##   {"coin_gate_per_target": true}      # Time Spiral pattern (per target)
	EffectRegistry.register_def("devolve_each_evolved", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var coin_per: bool = bool(p.get("coin_gate_per_target", false))
			var opp_id: int = 1 - ctx.player_id
			# Collect evolved slots first so we don't iterate while mutating state.
			var targets: Array[String] = []
			for sid: String in BoardPosition.all_slot_ids(opp_id):
				var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
				if inst == null or inst.card == null: continue
				if inst.prior_stages.size() > 0 or int(inst.card.stage) != 0:
					targets.append(sid)
			# Coin flips happen synchronously here (during POST_DAMAGE_EFFECTS resolve).
			var passes: Array[bool] = []
			for _t in targets:
				passes.append(true if not coin_per else ctx.flip_coin())
			ctx.add_post_action(func() -> void:
				for i in range(targets.size()):
					if not passes[i]: continue
					var sid: String = targets[i]
					var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
					if inst == null: continue
					var removed: PokemonCardData = inst.devolve()
					if removed == null: continue
					# Place removed card on top of opp's deck.
					ctx.manager.game_position.decks[opp_id].append(removed)
					ctx.manager.pokemon_state_changed.emit(sid, inst)
			)
	))


	## devolve_one_with_query — coin-flip; on heads, devolve one of the opponent's
	## evolved Pokémon (returning the top-stage card to its deck and shuffling).
	## Auto-picks: highest-stage evolved opp Pokémon, ties broken by active over
	## bench. No-op if opponent has no evolved Pokémon. (Time Spiral.)
	## effect_params: {}
	EffectRegistry.register_def("devolve_one_with_query", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var opp_id: int = 1 - ctx.player_id
			var best_sid: String = ""
			var best_stage: int = -1
			# Active first so ties favor it.
			var slot_order: Array[String] = []
			for s: String in BoardPosition.ACTIVE_SLOTS:
				slot_order.append("p%d_%s" % [opp_id, s])
			for s: String in BoardPosition.BENCH_SLOTS:
				slot_order.append("p%d_%s" % [opp_id, s])
			for sid in slot_order:
				var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
				if inst == null or inst.card == null:
					continue
				if inst.prior_stages.size() == 0 and int(inst.card.stage) == 0:
					continue
				var stage: int = int(inst.card.stage)
				if stage > best_stage:
					best_stage = stage
					best_sid = sid
			if best_sid == "":
				return
			if not ctx.flip_coin():
				return
			var pick_sid := best_sid
			ctx.add_post_action(func() -> void:
				var inst: PokemonInstance = ctx.manager.board_position.get_instance(pick_sid)
				if inst == null:
					return
				var removed: PokemonCardData = inst.devolve()
				if removed == null:
					return
				ctx.manager.game_position.decks[opp_id].append(removed)
				ctx.manager.game_position.shuffle_deck(opp_id)
				ctx.manager.pokemon_state_changed.emit(pick_sid, inst)
			)
	))


	## may_discard_then_switch — auto-discards 1 ANY energy from the attacker and
	## then switches the attacker with the first non-empty bench slot. No-op if
	## either prerequisite is missing (no energy OR no bench occupant). (Backspin.)
	## effect_params: {}
	EffectRegistry.register_def("may_discard_then_switch", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var pid := ctx.player_id
			var att_slot := ctx.attacker_slot
			ctx.add_post_action(func() -> void:
				var att: PokemonInstance = ctx.manager.board_position.get_instance(att_slot)
				if att == null or att.attached_energy.is_empty():
					return
				var bench_slot: String = ""
				for s: String in BoardPosition.BENCH_SLOTS:
					var sid := "p%d_%s" % [pid, s]
					if not ctx.manager.board_position.is_empty(sid):
						bench_slot = sid
						break
				if bench_slot == "":
					return
				var to_discard: CardData = att.attached_energy[0]
				att.attached_energy.remove_at(0)
				ctx.manager.game_position.put_in_discard(pid, to_discard)
				att.refresh_visual()
				ctx.manager.board_position.swap(att_slot, bench_slot)
				ctx.manager.pokemon_state_changed.emit(att_slot,
					ctx.manager.board_position.get_instance(att_slot))
				ctx.manager.pokemon_state_changed.emit(bench_slot,
					ctx.manager.board_position.get_instance(bench_slot))
			)
	))


	## defender_lock_attack — auto-picks ONE of the defender's attacks (highest
	## base_damage; ties broken by higher index) and prevents the defender from
	## using it during the opponent's next turn. No-op if defender is gone or
	## has no attacks. (Amnesia.)
	## effect_params: {}
	EffectRegistry.register_def("defender_lock_attack", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var target_slot := ctx.target_slot
			ctx.add_post_action(func() -> void:
				var t: PokemonInstance = ctx.manager.board_position.get_instance(target_slot)
				if t == null or t.card == null:
					return
				var atks: Array = t.card.attacks
				if atks.is_empty():
					return
				var best_idx: int = 0
				var best_dmg: int = -1
				for i in range(atks.size()):
					var a: AttackData = atks[i]
					if a == null:
						continue
					if a.base_damage >= best_dmg:
						best_dmg = a.base_damage
						best_idx = i
				t.cant_use_attack_indices_until_turn[best_idx] = ctx.manager.turn_number + 1
			)
	))


	## attach_from_hand_free — attach basic Energy cards from hand. Auto-attaches
	## to the attacker (simpler than a player picker; the rules-correct UI can
	## come later). Type filter and count are honored.
	## effect_params:
	##   {"count": 1, "type": "ANY"}                 # Plus Energy
	##   {"count": 2, "type": "GRASS"}               # Speed Growth
	##   {"count": -1, "type": "WATER"}              # Drizzle: any number
	##   {"count": -1, "type": "ANY"}                # Energy Shower
	EffectRegistry.register_def("attach_from_hand_free", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var count: int = int(p.get("count", 1))
			var type_str: String = str(p.get("type", "ANY"))
			ctx.add_post_action(func() -> void:
				var hand: Array = ctx.manager.game_position.hands[ctx.player_id]
				var attached: int = 0
				var want: int = -1
				if type_str != "ANY":
					want = _energy_type_from_string(type_str)
				for i in range(hand.size() - 1, -1, -1):
					if count >= 0 and attached >= count:
						break
					var c = hand[i]
					if not (c is EnergyCardData):
						continue
					if want >= 0 and int((c as EnergyCardData).energy_type) != want:
						continue
					# Only basic Energy attachable via these "from hand" effects.
					if not DeckValidator.is_basic_energy(c):
						continue
					hand.remove_at(i)
					ctx.attacker.attach_energy(c)
					attached += 1
				if attached > 0:
					ctx.manager.game_position.hand_changed.emit(ctx.player_id)
					ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
			)
	))

	## heal_one — remove N damage counters from one of your Pokémon. Auto-picks
	## the most-damaged own Pokémon (no query). Falls back to attacker if no
	## damage anywhere. Dragon Dew uses count_fallback for "remove 1 if only 1".
	## effect_params:
	##   {"counters": 2}                              # remove 2 from most-damaged
	##   {"counters": 2, "count_fallback": 1}         # remove only 1 if only 1 own Pokémon
	EffectRegistry.register_def("heal_one", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var counters: int = int(p.get("counters", 1))
			var fallback: int = int(p.get("count_fallback", counters))
			ctx.add_post_action(func() -> void:
				var own_slots: Array[String] = BoardPosition.all_slot_ids(ctx.player_id)
				var own_count: int = 0
				var best_slot: String = ""
				var best_dmg: int = -1
				for sid: String in own_slots:
					var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
					if inst == null: continue
					own_count += 1
					var dmg: int = inst.max_hp - inst.current_hp
					if dmg > best_dmg:
						best_dmg = dmg
						best_slot = sid
				if best_slot == "":
					return
				var amt: int = (fallback if own_count <= 1 else counters) * 10
				var pick: PokemonInstance = ctx.manager.board_position.get_instance(best_slot)
				pick.heal(amt)
				ctx.manager.pokemon_state_changed.emit(best_slot, pick)
			)
	))

	## mill_one_attach_if_energy — discard the top card of your deck; if it's a
	## basic Energy card, attach it to the attacker. Melting Mountain.
	## effect_params: {}
	EffectRegistry.register_def("mill_one_attach_if_energy", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				var deck: Array = ctx.manager.game_position.decks[ctx.player_id]
				if deck.is_empty():
					return
				var c: CardData = deck.pop_back()
				if c is EnergyCardData and DeckValidator.is_basic_energy(c):
					ctx.attacker.attach_energy(c)
					ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
				else:
					ctx.manager.game_position.put_in_discard(ctx.player_id, c)
			)
	))

	## discard_to_hand_any — put 1 card from your discard pile into your hand.
	## Auto-picks the most-recently discarded card (top of pile). Sniff Out.
	## effect_params: {"count": 1}
	EffectRegistry.register_def("discard_to_hand_any", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var count: int = int(ctx.attack.effect_params.get("count", 1))
			ctx.add_post_action(func() -> void:
				var disc: Array = ctx.manager.game_position.discards[ctx.player_id]
				var taken: int = 0
				while taken < count and not disc.is_empty():
					var c: CardData = disc.pop_back()
					ctx.manager.game_position.put_in_hand(ctx.player_id, c)
					taken += 1
				if taken > 0:
					ctx.manager.game_position.discard_changed.emit(ctx.player_id)
			)
	))

	## conditional_inflict_status — apply a status (or list) when a defender-side
	## predicate holds. Reuses the same condition strings as conditional_bonus_damage.
	## effect_params:
	##   {"condition": "defender_is_pokemon_ex", "statuses": ["ASLEEP","POISONED"]}
	EffectRegistry.register_def("conditional_inflict_status", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			if not _check_defender_condition(ctx, str(p.get("condition", ""))):
				return
			var statuses: Array = p.get("statuses", []) as Array
			ctx.add_post_action(func() -> void:
				for s in statuses:
					ctx.target.add_condition(_condition_from_string(str(s)))
			)
	))

	## inflict_status_by_attached_count — apply different status depending on
	## attacker's attached energy count. Lizard Poison.
	## effect_params:
	##   {"tiers": [{"min": 1, "condition": "ASLEEP"},
	##              {"min": 2, "condition": "CONFUSED"},
	##              {"min": 3, "condition": "PARALYZED"}]}
	## Highest-min matching tier wins.
	EffectRegistry.register_def("inflict_status_by_attached_count", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var tiers: Array = p.get("tiers", []) as Array
			var att_count: int = ctx.attacker.attached_energy.size()
			var chosen_cond: String = ""
			var best_min: int = -1
			for t in tiers:
				if not (t is Dictionary): continue
				var tmin: int = int(t.get("min", 0))
				if att_count >= tmin and tmin > best_min:
					best_min = tmin
					chosen_cond = str(t.get("condition", ""))
			if chosen_cond == "":
				return
			ctx.add_post_action(func() -> void:
				ctx.target.add_condition(_condition_from_string(chosen_cond))
			)
	))


	## switch_self — auto-switch attacker with the first non-empty bench slot
	## after the attack resolves. Simplified: no may-prompt; always switches if
	## a bench slot is occupied. (Bounce.)
	## effect_params: {}
	EffectRegistry.register_def("switch_self", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			ctx.add_post_action(func() -> void:
				var bench_slot: String = ""
				for s: String in BoardPosition.BENCH_SLOTS:
					var sid := "p%d_%s" % [ctx.player_id, s]
					if not ctx.manager.board_position.is_empty(sid):
						bench_slot = sid
						break
				if bench_slot == "":
					return
				ctx.manager.board_position.swap(ctx.attacker_slot, bench_slot)
				ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot,
					ctx.manager.board_position.get_instance(ctx.attacker_slot))
				ctx.manager.pokemon_state_changed.emit(bench_slot,
					ctx.manager.board_position.get_instance(bench_slot))
			)
	))


	## ── Wave 17 handlers ──────────────────────────────────────────────────────

	## flame_pillar — DR_100 Charizard idx 1.
	## After base damage, ask player whether to discard 1 Fire energy from
	## attacker. If yes AND opp has a non-empty bench, ask which bench slot to
	## deal 30 damage to (W/R bypassed for bench). Coroutine — uses
	## ctx.manager.attack_resolver.ask() to sequence the two queries.
	## effect_params: {}
	EffectRegistry.register_def("flame_pillar", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			# Count eligible Fire energy on attacker.
			var fire_count: int = 0
			for e: CardData in ctx.attacker.attached_energy:
				if e is EnergyCardData and int((e as EnergyCardData).energy_type) == \
						PokemonCardData.EnergyType.FIRE:
					fire_count += 1
			if fire_count == 0:
				return
			# Gather opp bench targets.
			var opp_id: int = 1 - ctx.player_id
			var bench_options: Array[String] = []
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					bench_options.append(sid)
			if bench_options.is_empty():
				return
			# Ask the may-discard question.
			var confirm := AttackQuery.new()
			confirm.kind = AttackQuery.Kind.MAY_CONFIRM
			confirm.player_id = ctx.player_id
			confirm.prompt = "Discard 1 Fire energy to do 30 damage to an opp bench Pokémon?"
			confirm.options = [true, false]
			var did_discard: Variant = await ctx.manager.attack_resolver.ask(confirm)
			if did_discard != true:
				return
			# Discard 1 Fire from attacker.
			_discard_typed(ctx, PokemonCardData.EnergyType.FIRE, 1)
			# Ask which bench slot to hit.
			var pick := AttackQuery.new()
			pick.kind = AttackQuery.Kind.CHOOSE_BENCH_TARGET
			pick.player_id = ctx.player_id
			pick.prompt = "Choose an opp bench Pokémon for 30 damage."
			pick.options = bench_options
			var chosen: Variant = await ctx.manager.attack_resolver.ask(pick)
			var slot: String = str(chosen)
			if slot == "" or ctx.manager.board_position.is_empty(slot):
				return
			ctx.add_post_action(func() -> void:
				var inst: PokemonInstance = ctx.manager.board_position.get_instance(slot)
				if inst == null:
					return
				inst.apply_damage(30)
				ctx.manager.pokemon_state_changed.emit(slot, inst)
				if inst.is_knocked_out():
					ctx.manager.resolve_knockout(slot, ctx.player_id)
			)
	))


	## coin_flips_branch_bonus — DR_31 Grovyle Fury Cutter.
	## Flip N coins. If all heads, add `all_heads_bonus` to damage.
	## Otherwise, add `per_head * heads_count`. Damage formula:
	##   base_damage + (all-heads ? all_heads_bonus : per_head * heads)
	## effect_params: {"coin_count": 4, "per_head": 10, "all_heads_bonus": 60}
	EffectRegistry.register_def("coin_flips_branch_bonus", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var coin_count: int = int(p.get("coin_count", 4))
			var per_head: int = int(p.get("per_head", 10))
			var all_heads_bonus: int = int(p.get("all_heads_bonus", 0))
			var heads: int = ctx.flip_coins(coin_count).count(true)
			var bonus: int
			if heads == coin_count:
				bonus = all_heads_bonus
			else:
				bonus = per_head * heads
			var eff := QueuedEffect.new()
			eff.category = QueuedEffect.Category.ATTACKER_MODIFIER
			eff.source_key = "coin_flips_branch_bonus"
			eff.description = "%d/%d heads → +%d" % [heads, coin_count, bonus]
			eff.execute = func(c: AttackContext) -> void:
				c.bonus_damage += bonus
			queue.append(eff)
	))


	## gyarados_dragon_crush — DR_32 Gyarados.
	## Flip 1 coin. Heads: damage `per_target_damage` to each defending Pokémon
	## AND discard `energy_discard_count` energy from each defender that has it.
	## Tails: no damage, no discard.
	## Card JSON must set base_damage=0 and hits_each_defending=true (the per-
	## target damage value goes through ctx.bonus_damage so it lands on every
	## defender slot via the resolver's hits_each_defending loop).
	## effect_params: {"per_target_damage": 10, "energy_discard_count": 1}
	EffectRegistry.register_def("gyarados_dragon_crush", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var per_target: int = int(p.get("per_target_damage", 10))
			var discard_count: int = int(p.get("energy_discard_count", 1))
			var heads: bool = ctx.flip_coin()
			if not heads:
				return
			var eff := QueuedEffect.new()
			eff.category = QueuedEffect.Category.ATTACKER_MODIFIER
			eff.source_key = "gyarados_dragon_crush"
			eff.description = "heads: %d to each + discard %d energy each" % [per_target, discard_count]
			eff.execute = func(c: AttackContext) -> void:
				c.bonus_damage += per_target
			queue.append(eff)
			# Schedule the per-defender energy discard as a post-action so it
			# fires after damage / KO resolution.
			ctx.add_post_action(func() -> void:
				var opp_id: int = 1 - ctx.player_id
				var opp_pid: int = opp_id
				for s: String in BoardPosition.ACTIVE_SLOTS:
					var sid := "p%d_%s" % [opp_id, s]
					var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
					if inst == null or inst.attached_energy.is_empty():
						continue
					_discard_typed_from(inst, ctx.manager, opp_pid, discard_count)
					ctx.manager.pokemon_state_changed.emit(sid, inst)
			)
	))


	## discard_basic_energy_for_bonus_each — DR_95 Magcargo ex Lava Flow.
	## Coroutine: ask the player to pick 0..N basic energies on attacker to
	## discard. Damage += bonus_per_discard × count_discarded.
	## effect_params: {"bonus_per_discard": 20}
	EffectRegistry.register_def("discard_basic_energy_for_bonus_each", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var bonus_per: int = int(p.get("bonus_per_discard", 20))
			var basics: Array[CardData] = []
			for e: CardData in ctx.attacker.attached_energy:
				if e is EnergyCardData and DeckValidator.is_basic_energy(e):
					basics.append(e)
			if basics.is_empty():
				return
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_DISCARD_COUNT
			q.player_id = ctx.player_id
			q.prompt = "Discard any basic Energy for +%d damage each. (0–%d)" % [bonus_per, basics.size()]
			q.options = basics
			q.min_selections = 0
			q.max_selections = basics.size()
			var chosen: Variant = await ctx.manager.attack_resolver.ask(q)
			var picked: Array[CardData] = []
			if chosen is Array:
				for x in (chosen as Array):
					if x is CardData:
						picked.append(x as CardData)
			if picked.is_empty():
				return
			# Discard chosen energies from attacker.
			for c: CardData in picked:
				ctx.attacker.attached_energy.erase(c)
				ctx.discarded_this_attack.append(c)
			ctx.manager.game_position.discard_all(ctx.player_id, picked)
			ctx.attacker.refresh_visual()
			ctx.manager.pokemon_state_changed.emit(ctx.attacker_slot, ctx.attacker)
			var eff := QueuedEffect.new()
			eff.category = QueuedEffect.Category.ATTACKER_MODIFIER
			eff.source_key = "discard_basic_energy_for_bonus_each"
			eff.description = "+%d × %d discarded" % [bonus_per, picked.size()]
			var discarded_count: int = picked.size()
			eff.execute = func(c: AttackContext) -> void:
				c.bonus_damage += bonus_per * discarded_count
			queue.append(eff)
	))


	## discard_all_of_chosen_type — DR_97 Rayquaza ex Dragon Burst.
	## If attacker has at least one of any candidate type, ask which type to
	## discard (auto-pick if only one type has any). Discard ALL of that type
	## from attacker. Damage += damage_per_discard × count_discarded.
	## effect_params: {"types": ["FIRE","LIGHTNING"], "damage_per_discard": 40}
	EffectRegistry.register_def("discard_all_of_chosen_type", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var types_param: Array = p.get("types", []) as Array
			var per_disc: int = int(p.get("damage_per_discard", 40))
			# Tally each candidate type.
			var counts: Dictionary = {}
			for t_var in types_param:
				var t_str: String = str(t_var)
				var t_int: int = _energy_type_from_string(t_str)
				var c: int = 0
				for e: CardData in ctx.attacker.attached_energy:
					if e is EnergyCardData and int((e as EnergyCardData).energy_type) == t_int:
						c += 1
				counts[t_str] = c
			# Eligible types (>=1 attached).
			var eligible: Array[String] = []
			for t_str_var in counts.keys():
				if int(counts[t_str_var]) > 0:
					eligible.append(str(t_str_var))
			if eligible.is_empty():
				return
			var chosen_type: String
			if eligible.size() == 1:
				chosen_type = eligible[0]
			else:
				var q := AttackQuery.new()
				q.kind = AttackQuery.Kind.CHOOSE_ENERGY_TYPE
				q.player_id = ctx.player_id
				q.prompt = "Discard all of which type?"
				q.options = eligible
				var resp: Variant = await ctx.manager.attack_resolver.ask(q)
				chosen_type = str(resp) if resp != null else ""
				if chosen_type == "" or not eligible.has(chosen_type):
					return
			# Discard ALL of chosen type.
			var discard_count_total: int = int(counts[chosen_type])
			_discard_typed(ctx, _energy_type_from_string(chosen_type), discard_count_total)
			var eff := QueuedEffect.new()
			eff.category = QueuedEffect.Category.ATTACKER_MODIFIER
			eff.source_key = "discard_all_of_chosen_type"
			eff.description = "discard %d %s → +%d" % [discard_count_total, chosen_type, per_disc * discard_count_total]
			var disc_n: int = discard_count_total
			eff.execute = func(c: AttackContext) -> void:
				c.bonus_damage += per_disc * disc_n
			queue.append(eff)
	))


	## may_switch_self_then_move_energy — DR_18 Ninjask Quick Touch.
	## Coroutine. After base damage:
	##   1. Ask may-switch self.
	##   2. If yes, pick which bench slot to swap with (auto-pick if only 1).
	##   3. After swap, ask which `energy_type` energies on the old active
	##      (now on bench) to move to the new active (0..N).
	## effect_params: {"energy_type": "GRASS"}
	EffectRegistry.register_def("may_switch_self_then_move_energy", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var type_str: String = str(p.get("energy_type", "ANY"))
			var type_int: int = -1
			if type_str != "ANY":
				type_int = _energy_type_from_string(type_str)
			# Build own bench options.
			var pid: int = ctx.player_id
			var bench_options: Array[String] = []
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [pid, s]
				if not ctx.manager.board_position.is_empty(sid):
					bench_options.append(sid)
			if bench_options.is_empty():
				return
			# Ask may-switch.
			var confirm := AttackQuery.new()
			confirm.kind = AttackQuery.Kind.MAY_CONFIRM
			confirm.player_id = pid
			confirm.prompt = "Switch with a benched Pokémon?"
			confirm.options = [true, false]
			var did_confirm: Variant = await ctx.manager.attack_resolver.ask(confirm)
			if did_confirm != true:
				return
			# Pick bench target (auto if only one).
			var swap_slot: String
			if bench_options.size() == 1:
				swap_slot = bench_options[0]
			else:
				var pick := AttackQuery.new()
				pick.kind = AttackQuery.Kind.CHOOSE_BENCH_TARGET
				pick.player_id = pid
				pick.prompt = "Switch with which Pokémon?"
				pick.options = bench_options
				var resp: Variant = await ctx.manager.attack_resolver.ask(pick)
				swap_slot = str(resp)
				if swap_slot == "" or not bench_options.has(swap_slot):
					return
			# Perform the swap.
			var attacker_slot := ctx.attacker_slot
			ctx.manager.board_position.swap(attacker_slot, swap_slot)
			ctx.manager.pokemon_state_changed.emit(attacker_slot,
				ctx.manager.board_position.get_instance(attacker_slot))
			ctx.manager.pokemon_state_changed.emit(swap_slot,
				ctx.manager.board_position.get_instance(swap_slot))
			# The OLD active (Ninjask) is now in swap_slot; gather its matching energies.
			var old_inst: PokemonInstance = ctx.manager.board_position.get_instance(swap_slot)
			if old_inst == null:
				return
			var movable: Array[CardData] = []
			for e: CardData in old_inst.attached_energy:
				if not (e is EnergyCardData):
					continue
				if type_int == -1 or int((e as EnergyCardData).energy_type) == type_int:
					movable.append(e)
			if movable.is_empty():
				return
			# Ask which to move.
			var mq := AttackQuery.new()
			mq.kind = AttackQuery.Kind.CHOOSE_DISCARD_COUNT
			mq.player_id = pid
			mq.prompt = "Move any %s energy to the new active. (0–%d)" % [type_str, movable.size()]
			mq.options = movable
			mq.min_selections = 0
			mq.max_selections = movable.size()
			var picked_resp: Variant = await ctx.manager.attack_resolver.ask(mq)
			var picked: Array[CardData] = []
			if picked_resp is Array:
				for x in (picked_resp as Array):
					if x is CardData:
						picked.append(x as CardData)
			if picked.is_empty():
				return
			# Move each picked energy from old (now bench) to new active.
			var new_active: PokemonInstance = ctx.manager.board_position.get_instance(attacker_slot)
			if new_active == null:
				return
			for c: CardData in picked:
				old_inst.attached_energy.erase(c)
				new_active.attach_energy(c)
			old_inst.refresh_visual()
			ctx.manager.pokemon_state_changed.emit(swap_slot, old_inst)
			ctx.manager.pokemon_state_changed.emit(attacker_slot, new_active)
	))


	## ── Wave 18 handlers (Hard / 2-active mode) ──────────────────────────────

	## coin_gate_return_defender_to_hand — RS_18 Nosepass Repulsion.
	## Flip a coin. On heads, the opponent returns the defending Pokémon and
	## all attached cards to their hand. No-op if the opp has neither another
	## active Pokémon nor a benched Pokémon to promote into the empty slot.
	## (Pulls full release_cards() so prior_stages + energies + tools all return.)
	## effect_params: {}
	EffectRegistry.register_def("coin_gate_return_defender_to_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			if not ctx.flip_coin():
				return
			# Capture state now so we can decide if the no-op edge applies.
			var opp_id: int = 1 - ctx.player_id
			var has_other_active: bool = false
			for s: String in BoardPosition.ACTIVE_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if sid != ctx.target_slot and not ctx.manager.board_position.is_empty(sid):
					has_other_active = true
					break
			var has_bench: bool = false
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					has_bench = true
					break
			if not has_other_active and not has_bench:
				ctx.manager.log_message.emit(
					"[Repulsion] No bench / other active — attack does nothing."
				)
				return
			var target_slot := ctx.target_slot
			var opp_pid := opp_id
			ctx.add_post_action(func() -> void:
				var inst: PokemonInstance = ctx.manager.board_position.get_instance(target_slot)
				if inst == null:
					return
				# release_cards returns the full content list and zeroes state.
				var cards: Array[CardData] = inst.release_cards()
				for c: CardData in cards:
					ctx.manager.game_position.put_in_hand(opp_pid, c)
				# Remove the now-empty PokemonInstance from the slot.
				var removed: PokemonInstance = ctx.manager.board_position.clear(target_slot)
				if removed != null:
					removed.queue_free()
				ctx.manager.pokemon_state_changed.emit(target_slot, null)
				ctx.manager.game_position.hand_changed.emit(opp_pid)
				# Trigger promotion if the defender slot is now empty.
				ctx.manager._check_all_promotions_needed()
			)
	))


	## move_one_energy_between_defenders — RS_21 Seaking Fast Stream.
	## In 2-active mode, move 1 energy from the primary defender to the OTHER
	## defending Pokémon. No-op if only 1 defender, or if defender has no energy.
	## Auto-picks the first energy. (Query UI for energy choice is a polish task.)
	## effect_params: {}
	EffectRegistry.register_def("move_one_energy_between_defenders", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var opp_id: int = 1 - ctx.player_id
			# Find the OTHER active slot (not the primary target).
			var other_slot: String = ""
			for s: String in BoardPosition.ACTIVE_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if sid != ctx.target_slot and not ctx.manager.board_position.is_empty(sid):
					other_slot = sid
					break
			if other_slot == "":
				return
			var target_slot := ctx.target_slot
			ctx.add_post_action(func() -> void:
				var src: PokemonInstance = ctx.manager.board_position.get_instance(target_slot)
				var dst: PokemonInstance = ctx.manager.board_position.get_instance(other_slot)
				if src == null or dst == null or src.attached_energy.is_empty():
					return
				var moved: CardData = src.attached_energy[0]
				src.attached_energy.remove_at(0)
				dst.attach_energy(moved)
				src.refresh_visual()
				ctx.manager.pokemon_state_changed.emit(target_slot, src)
				ctx.manager.pokemon_state_changed.emit(other_slot, dst)
			)
	))


	## may_split_damage_each — SS_99 Typhlosion ex Split Blast.
	## Coroutine. If opp has >1 defender, ask whether to do `split` to each
	## instead of `full` to the chosen target. If they confirm, set
	## ctx.force_hit_each_defending=true and ctx.base_damage=split. Otherwise
	## (declined OR only 1 defender) set ctx.base_damage=full.
	## effect_params: {"full": 100, "split": 50}
	EffectRegistry.register_def("may_split_damage_each", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var full_dmg: int = int(p.get("full", 100))
			var split_dmg: int = int(p.get("split", 50))
			# Count opp active slots with a Pokémon.
			var opp_id: int = 1 - ctx.player_id
			var active_count: int = 0
			for s: String in BoardPosition.ACTIVE_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					active_count += 1
			if active_count <= 1:
				ctx.base_damage = full_dmg
				return
			# Ask the player.
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.MAY_CONFIRM
			q.player_id = ctx.player_id
			q.prompt = "Split %d to each defending Pokémon instead of %d to chosen?" % [split_dmg, full_dmg]
			q.options = [true, false]
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			if resp == true:
				ctx.base_damage = split_dmg
				ctx.force_hit_each_defending = true
			else:
				ctx.base_damage = full_dmg
	))


	## ── Wave 19 handlers (Cross-system / interactive) ──────────────────────

	## look_take_shuffle_one_from_opp_hand — SS_46/SS_47/SS_61 Surprise.
	## Pick 1 card blind from opp hand; reveal it to attacker; opp shuffles
	## it into their deck. No-op if opp hand is empty.
	## effect_params: {}
	EffectRegistry.register_def("look_take_shuffle_one_from_opp_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var opp_id: int = 1 - ctx.player_id
			var opp_hand: Array = ctx.manager.game_position.hands[opp_id]
			if opp_hand.is_empty():
				return
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_OPP_HAND_BLIND
			q.player_id = ctx.player_id
			q.prompt = "Pick 1 card blind from your opponent's hand."
			q.options = [opp_hand.size()]
			q.min_selections = 1
			q.max_selections = 1
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			var picks: Array = resp as Array if resp is Array else []
			if picks.is_empty():
				return
			var idx: int = int(picks[0])
			if idx < 0 or idx >= opp_hand.size():
				return
			var taken: CardData = opp_hand[idx]
			# Reveal via log (presentation overlay is a polish task).
			ctx.manager.log_message.emit(
				"[Surprise] %s revealed %s — shuffled into opp deck." %
					[ctx.attack.name, taken.display_name if taken != null else "?"]
			)
			opp_hand.remove_at(idx)
			ctx.manager.game_position.decks[opp_id].append(taken)
			ctx.manager.game_position.shuffle_deck(opp_id)
			ctx.manager.game_position.hand_changed.emit(opp_id)
	))


	## look_then_may_use_supporter_from_opp_hand — SS_10 Sableye Supernatural.
	## Show opp hand (Supporter filter). If any Supporter present, ask if
	## the attacker wants to use it. If yes, invoke its effect through the
	## existing TrainerEffectRegistry (Supporter remains in opp hand).
	## effect_params: {}
	EffectRegistry.register_def("look_then_may_use_supporter_from_opp_hand", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var opp_id: int = 1 - ctx.player_id
			var opp_hand: Array = ctx.manager.game_position.hands[opp_id]
			# Build a typed snapshot of opp hand for the picker.
			var hand_snapshot: Array[CardData] = []
			for c in opp_hand:
				if c is CardData:
					hand_snapshot.append(c as CardData)
			# Filter to supporters for the player's decision.
			var supporters: Array[CardData] = []
			for c: CardData in hand_snapshot:
				if c is TrainerCardData and \
						(c as TrainerCardData).trainer_kind == TrainerCardData.TrainerKind.SUPPORTER:
					supporters.append(c)
			if supporters.is_empty():
				ctx.manager.log_message.emit(
					"[Supernatural] No Supporter in opp hand."
				)
				return
			# Present full hand, filtered to allow only supporters; max 1 pick.
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_OPP_HAND_OPEN
			q.player_id = ctx.player_id
			q.prompt = "You may use a Supporter from opp's hand."
			q.options = hand_snapshot
			q.filter = {"supporter_only": true}
			q.min_selections = 0
			q.max_selections = 1
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			var picks: Array = resp as Array if resp is Array else []
			if picks.is_empty():
				return
			var chosen: CardData = picks[0] as CardData
			if chosen == null or not (chosen is TrainerCardData):
				return
			# Confirm.
			var cf := AttackQuery.new()
			cf.kind = AttackQuery.Kind.MAY_CONFIRM
			cf.player_id = ctx.player_id
			cf.prompt = "Use %s?" % chosen.display_name
			cf.options = [true, false]
			var ok: Variant = await ctx.manager.attack_resolver.ask(cf)
			if ok != true:
				return
			var tc := chosen as TrainerCardData
			ctx.manager.log_message.emit(
				"[Supernatural] Using opp's %s." % tc.display_name
			)
			await ctx.manager.attack_resolver.invoke_trainer_effect_inline(
				tc.effect_key, ctx, tc
			)
	))


	## look_then_may_shuffle_opp_supporter_draw_one — SS_9 Mawile Scam.
	## Show opp hand (Supporter filter). If any Supporter present, ask if
	## attacker wants to have opp shuffle it. If yes, supporter goes from
	## opp hand to opp deck (shuffle), and opp draws 1 card.
	## effect_params: {}
	EffectRegistry.register_def("look_then_may_shuffle_opp_supporter_draw_one", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var opp_id: int = 1 - ctx.player_id
			var opp_hand: Array = ctx.manager.game_position.hands[opp_id]
			var hand_snapshot: Array[CardData] = []
			for c in opp_hand:
				if c is CardData:
					hand_snapshot.append(c as CardData)
			var supporters: Array[CardData] = []
			for c: CardData in hand_snapshot:
				if c is TrainerCardData and \
						(c as TrainerCardData).trainer_kind == TrainerCardData.TrainerKind.SUPPORTER:
					supporters.append(c)
			if supporters.is_empty():
				ctx.manager.log_message.emit("[Scam] No Supporter in opp hand.")
				return
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_OPP_HAND_OPEN
			q.player_id = ctx.player_id
			q.prompt = "Have opp shuffle a Supporter into their deck?"
			q.options = hand_snapshot
			q.filter = {"supporter_only": true}
			q.min_selections = 0
			q.max_selections = 1
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			var picks: Array = resp as Array if resp is Array else []
			if picks.is_empty():
				return
			var chosen: CardData = picks[0] as CardData
			if chosen == null:
				return
			var cf := AttackQuery.new()
			cf.kind = AttackQuery.Kind.MAY_CONFIRM
			cf.player_id = ctx.player_id
			cf.prompt = "Shuffle %s into opp deck (opp draws 1)?" % chosen.display_name
			cf.options = [true, false]
			var ok: Variant = await ctx.manager.attack_resolver.ask(cf)
			if ok != true:
				return
			# Remove from opp hand, append to opp deck, shuffle, opp draws 1.
			opp_hand.erase(chosen)
			ctx.manager.game_position.decks[opp_id].append(chosen)
			ctx.manager.game_position.shuffle_deck(opp_id)
			ctx.manager.game_position.hand_changed.emit(opp_id)
			# Draw 1 for opp.
			var opp_deck: Array = ctx.manager.game_position.decks[opp_id]
			if not opp_deck.is_empty():
				var drawn: CardData = opp_deck.pop_back()
				ctx.manager.game_position.put_in_hand(opp_id, drawn)
			ctx.manager.log_message.emit(
				"[Scam] Shuffled %s into opp deck. Opp drew 1." % chosen.display_name
			)
	))


	## pick_blind_from_opp_hand_to_discard_until — DR_1 Absol Bad News.
	## If opp hand size >= threshold, force player to pick (size - target_size)
	## cards blind from opp hand; opp discards them.
	## effect_params: {"threshold": 6, "target_size": 5}
	EffectRegistry.register_def("pick_blind_from_opp_hand_to_discard_until", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var threshold: int = int(p.get("threshold", 6))
			var target_size: int = int(p.get("target_size", 5))
			var opp_id: int = 1 - ctx.player_id
			var opp_hand: Array = ctx.manager.game_position.hands[opp_id]
			if opp_hand.size() < threshold:
				return
			var to_pick: int = opp_hand.size() - target_size
			if to_pick <= 0:
				return
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_OPP_HAND_BLIND
			q.player_id = ctx.player_id
			q.prompt = "Pick %d cards blind from opp hand (they'll be discarded)." % to_pick
			q.options = [opp_hand.size()]
			q.min_selections = to_pick
			q.max_selections = to_pick
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			var picks_raw: Array = resp as Array if resp is Array else []
			var picks_int: Array[int] = []
			for x in picks_raw:
				if x is int:
					picks_int.append(int(x))
			picks_int.sort()
			# Remove in descending order so earlier removes don't shift later indices.
			for i in range(picks_int.size() - 1, -1, -1):
				var idx: int = picks_int[i]
				if idx < 0 or idx >= opp_hand.size():
					continue
				var card: CardData = opp_hand[idx]
				opp_hand.remove_at(idx)
				ctx.manager.game_position.put_in_discard(opp_id, card)
			ctx.manager.game_position.hand_changed.emit(opp_id)
			ctx.manager.log_message.emit(
				"[Bad News] Discarded %d cards from opp hand." % picks_int.size()
			)
	))


	## look_pick_shuffle_opp_hand_until — DR_21 Skarmory Pick On.
	## If opp hand size >= threshold, attacker LOOKS at opp hand and picks
	## (size - target_size) cards; opp shuffles those into their deck.
	## effect_params: {"threshold": 6, "target_size": 5}
	EffectRegistry.register_def("look_pick_shuffle_opp_hand_until", EffectDefinition.single(
		AttackResolver.Phase.POST_DAMAGE_EFFECTS,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			var p: Dictionary = ctx.attack.effect_params
			var threshold: int = int(p.get("threshold", 6))
			var target_size: int = int(p.get("target_size", 5))
			var opp_id: int = 1 - ctx.player_id
			var opp_hand: Array = ctx.manager.game_position.hands[opp_id]
			if opp_hand.size() < threshold:
				return
			var to_pick: int = opp_hand.size() - target_size
			if to_pick <= 0:
				return
			var hand_snapshot: Array[CardData] = []
			for c in opp_hand:
				if c is CardData:
					hand_snapshot.append(c as CardData)
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_OPP_HAND_OPEN
			q.player_id = ctx.player_id
			q.prompt = "Pick %d cards from opp hand to shuffle into their deck." % to_pick
			q.options = hand_snapshot
			q.min_selections = to_pick
			q.max_selections = to_pick
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			var picks_raw: Array = resp as Array if resp is Array else []
			var picks: Array[CardData] = []
			for x in picks_raw:
				if x is CardData:
					picks.append(x as CardData)
			if picks.is_empty():
				return
			# Remove from hand, append to deck, shuffle.
			for c: CardData in picks:
				opp_hand.erase(c)
				ctx.manager.game_position.decks[opp_id].append(c)
			ctx.manager.game_position.shuffle_deck(opp_id)
			ctx.manager.game_position.hand_changed.emit(opp_id)
			ctx.manager.log_message.emit(
				"[Pick On] Shuffled %d cards from opp hand into deck." % picks.size()
			)
	))


	## use_attack_from_prior_stage — DR_92 Kingdra ex Genetic Memory.
	## Build options from attacker.prior_stages (Basic + Stage 1 underneath).
	## Player picks one attack; it resolves through a sub-pipeline with cost
	## waived (begin_attack_with_attack opts: skip_conditionals_gate=true).
	## effect_params: {}
	EffectRegistry.register_def("use_attack_from_prior_stage", EffectDefinition.single(
		AttackResolver.Phase.DAMAGE_CALC,
		func(ctx: AttackContext, _queue: Array[QueuedEffect]) -> void:
			# Build attack options from prior_stages.
			var options: Array[Dictionary] = []
			for stage_card in ctx.attacker.prior_stages:
				if not (stage_card is PokemonCardData):
					continue
				var pcard := stage_card as PokemonCardData
				for i in range(pcard.attacks.size()):
					var atk: AttackData = pcard.attacks[i]
					if atk == null:
						continue
					options.append({
						"card": pcard,
						"index": i,
						"label": "%s — %s (%d dmg)" % [pcard.display_name, atk.name, atk.base_damage]
					})
			if options.is_empty():
				ctx.manager.log_message.emit(
					"[Genetic Memory] No prior-stage attacks available."
				)
				return
			var q := AttackQuery.new()
			q.kind = AttackQuery.Kind.CHOOSE_ATTACK_FROM_CARDS
			q.player_id = ctx.player_id
			q.prompt = "Use which attack from %s's prior stages?" % ctx.attacker.card.display_name
			q.options = options
			var resp: Variant = await ctx.manager.attack_resolver.ask(q)
			if not (resp is Dictionary):
				return
			var entry: Dictionary = resp
			var sub_card: PokemonCardData = entry.get("card", null) as PokemonCardData
			var sub_idx: int = int(entry.get("index", -1))
			if sub_card == null or sub_idx < 0:
				return
			ctx.manager.log_message.emit(
				"[Genetic Memory] Using %s's %s." %
					[sub_card.display_name, sub_card.attacks[sub_idx].name]
			)
			await ctx.manager.attack_resolver.invoke_sub_attack(ctx, sub_card, sub_idx)
			# Sub-pipeline already applied its own damage. Parent has
			# base_damage=0 so its damage_queue entry is filtered as 0.
	))


## ── Helpers ───────────────────────────────────────────────────────────────────

## Slot list for place_damage_counters' non-query targets.
func _place_counters_targets(ctx: AttackContext, target: String) -> Array[String]:
	var opp_id: int = 1 - ctx.player_id
	var out: Array[String] = []
	match target:
		"defender":
			out.append(ctx.target_slot)
		"each_defending":
			for s: String in BoardPosition.ACTIVE_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					out.append(sid)
		"each_opp":
			for sid: String in BoardPosition.all_slot_ids(opp_id):
				if not ctx.manager.board_position.is_empty(sid):
					out.append(sid)
		_:
			push_warning("[place_damage_counters] unknown target: %s" % target)
	return out


## Slot list for aoe_damage. Excludes already-damaged primary targets so this
## attack's base damage isn't double-counted.
func _aoe_targets(ctx: AttackContext, side: String) -> Array[String]:
	var opp_id: int = 1 - ctx.player_id
	var out: Array[String] = []
	match side:
		"opp_bench":
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [opp_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					out.append(sid)
		"own_bench":
			for s: String in BoardPosition.BENCH_SLOTS:
				var sid := "p%d_%s" % [ctx.player_id, s]
				if not ctx.manager.board_position.is_empty(sid):
					out.append(sid)
		"all_bench":
			for pid: int in [0, 1]:
				for s: String in BoardPosition.BENCH_SLOTS:
					var sid := "p%d_%s" % [pid, s]
					if not ctx.manager.board_position.is_empty(sid):
						out.append(sid)
		"each_active":
			# Both players' active slots, excluding the attack's primary target
			# (already hit by base damage).
			for pid: int in [0, 1]:
				for s: String in BoardPosition.ACTIVE_SLOTS:
					var sid := "p%d_%s" % [pid, s]
					if ctx.manager.board_position.is_empty(sid):
						continue
					if sid == ctx.target_slot:
						continue
					out.append(sid)
		"opp_all":
			for sid: String in BoardPosition.all_slot_ids(opp_id):
				if ctx.manager.board_position.is_empty(sid):
					continue
				# Skip the primary target — already hit by base damage.
				if sid == ctx.target_slot:
					continue
				out.append(sid)
		_:
			push_warning("[aoe_damage] unknown side: %s" % side)
	return out


## Predicate helper for search_deck_to_hand. Returns true if [c] matches.
static func _search_match(c: CardData, filt: String, evolves_from: String,
		slug_any: Array) -> bool:
	if c == null:
		return false
	match filt:
		"any":
			return true
		"trainer":
			return c.card_type == CardData.CardType.TRAINER
		"energy":
			return c.card_type == CardData.CardType.ENERGY
		"basic_energy":
			return c is EnergyCardData and DeckValidator.is_basic_energy(c)
		"pokemon":
			return c is PokemonCardData
		"evolution":
			return c is PokemonCardData and int((c as PokemonCardData).stage) != 0
		"evolves_from":
			return c is PokemonCardData \
				and (c as PokemonCardData).evolves_from == evolves_from
		"name_slug_any_of":
			return c is PokemonCardData \
				and slug_any.has((c as PokemonCardData).name_slug)
		_:
			return false


static func _condition_from_string(s: String) -> int:
	return PokemonInstance.SpecialCondition[s.to_upper()]


## Predicate helper for conditional_bonus_damage.
func _check_defender_condition(ctx: AttackContext, cond: String) -> bool:
	var t: PokemonInstance = ctx.target
	if t == null:
		return false
	match cond:
		"defender_has_damage_counters":
			return t.current_hp < t.max_hp
		"defender_is_evolved":
			return t.prior_stages.size() > 0 or (t.card != null and int(t.card.stage) != 0)
		"defender_is_pokemon_ex":
			return t.card != null and t.card.name_slug.ends_with("_ex")
		"defender_has_status":
			return t.special_conditions.size() > 0
		"defender_is_card":
			var slug: String = str(ctx.attack.effect_params.get("card_slug", ""))
			return t.card != null and t.card.name_slug == slug
		"you_have_more_prizes_left":
			# Prize cards are stored at game_position.prizes[pid] with `null`
			# entries marking taken prizes. "More prizes left" = more remaining
			# prize cards (i.e. fewer prizes taken).
			var own: int = _prizes_remaining(ctx.manager, ctx.player_id)
			var opp: int = _prizes_remaining(ctx.manager, 1 - ctx.player_id)
			return own > opp
		"defender_has_special_energy":
			# Special Energy = EnergyCardData but not a basic-by-name energy.
			for e: CardData in t.attached_energy:
				if e is EnergyCardData and not DeckValidator.is_basic_energy(e):
					return true
			return false
		"different_energy_counts":
			return ctx.attacker.attached_energy.size() != t.attached_energy.size()
		"same_energy_counts":
			return ctx.attacker.attached_energy.size() == t.attached_energy.size()
		"you_have_less_energy_total":
			# Sum of all energy on every Pokémon in play, per side.
			return (_count_energy_side(ctx.manager, ctx.player_id)
				< _count_energy_side(ctx.manager, 1 - ctx.player_id))
		"you_have_more_energy_total":
			return (_count_energy_side(ctx.manager, ctx.player_id)
				> _count_energy_side(ctx.manager, 1 - ctx.player_id))
		_:
			push_warning("[conditional_bonus_damage] unknown condition: %s" % cond)
			return false


## Count helper for damage_scaling. Returns the unit count for the chosen basis.
func _count_for_basis(ctx: AttackContext, basis: String, p: Dictionary) -> int:
	match basis:
		"damage_counters_target":
			return _count_damage_counters(ctx.target)
		"damage_counters_attacker":
			return _count_damage_counters(ctx.attacker)
		"energy_attached_target":
			return ctx.target.attached_energy.size() if ctx.target != null else 0
		"energy_attached_attacker":
			return ctx.attacker.attached_energy.size() if ctx.attacker != null else 0
		"energy_attached_all":
			return _count_energy_side(ctx.manager, -1)
		"energy_attached_own":
			return _count_energy_side(ctx.manager, ctx.player_id)
		"energy_attached_opp":
			return _count_energy_side(ctx.manager, 1 - ctx.player_id)
		"energy_of_type_attacker":
			return _count_energy_of_type(ctx.attacker, str(p.get("energy_type", "ANY")))
		"energy_of_type_target":
			return _count_energy_of_type(ctx.target, str(p.get("energy_type", "ANY")))
		"bench_pokemon_count":
			return _count_bench(ctx.manager, ctx.player_id, "ANY")
		"bench_pokemon_of_type":
			return _count_bench(ctx.manager, ctx.player_id, str(p.get("pokemon_type", "ANY")))
		"coin_flips_heads":
			var flips: int = int(p.get("flips", 1))
			return ctx.flip_coins(flips).count(true)
		"coin_flips_per_energy_heads":
			var n: int = ctx.attacker.attached_energy.size() if ctx.attacker != null else 0
			if p.has("max_flips"):
				n = mini(n, int(p["max_flips"]))
			return ctx.flip_coins(n).count(true)
		"coin_flips_until_tails":
			# Cap iterations at 50 so a forced-flips queue or rigged RNG can't loop.
			var heads: int = 0
			for _i in range(50):
				if ctx.flip_coin():
					heads += 1
				else:
					break
			return heads
		"coin_per_pokemon_heads":
			# 1 coin per own Pokémon in play (active + bench). Beat Up.
			var pcount: int = 0
			for sid: String in BoardPosition.all_slot_ids(ctx.player_id):
				if not ctx.manager.board_position.is_empty(sid):
					pcount += 1
			return ctx.flip_coins(pcount).count(true)
		"cards_in_opp_hand":
			return ctx.manager.game_position.hands[1 - ctx.player_id].size()
		"cards_in_own_hand":
			return ctx.manager.game_position.hands[ctx.player_id].size()
		"retreat_cost_target_colorless":
			# Number of Colorless energy in target's retreat cost.
			if ctx.target == null or ctx.target.card == null:
				return 0
			return int(ctx.target.card.retreat_cost)
		"coin_per_active_energy_heads":
			# 1 coin per energy attached to all of own Active slots. Max Bubbles.
			var ne: int = _count_energy_actives(ctx.manager, ctx.player_id)
			return ctx.flip_coins(ne).count(true)
		"energy_attached_actives_own":
			return _count_energy_actives(ctx.manager, ctx.player_id)
		"energy_attached_actives_both":
			return _count_energy_actives(ctx.manager, -1)
		"energy_attached_pair":
			var n_a: int = ctx.attacker.attached_energy.size() if ctx.attacker != null else 0
			var n_t: int = ctx.target.attached_energy.size() if ctx.target != null else 0
			return n_a + n_t
		"energy_types_attacker":
			return _count_energy_types(ctx.attacker)
		"damage_counters_actives_own":
			return _count_damage_counters_actives(ctx.manager, ctx.player_id)
		"retreat_cost_target":
			if ctx.target == null or ctx.target.card == null:
				return 0
			return int(ctx.target.card.retreat_cost)
		"extra_energy_beyond_cost":
			var attached: int = ctx.attacker.attached_energy.size() if ctx.attacker != null else 0
			var cost: int = _attack_total_cost(ctx.attack)
			return maxi(0, attached - cost)
		_:
			push_warning("[damage_scaling] unknown basis: %s" % basis)
			return 0


static func _count_damage_counters(inst: PokemonInstance) -> int:
	if inst == null:
		return 0
	return (inst.max_hp - inst.current_hp) / 10


static func _count_energy_of_type(inst: PokemonInstance, type_str: String) -> int:
	if inst == null:
		return 0
	if type_str == "ANY":
		return inst.attached_energy.size()
	var want: int = _energy_type_from_string(type_str)
	var n: int = 0
	for e: CardData in inst.attached_energy:
		if e is EnergyCardData and int((e as EnergyCardData).energy_type) == want:
			n += 1
	return n


## player_id < 0 → both sides; otherwise just that player's slots.
func _count_energy_side(mgr, player_id: int) -> int:
	var n: int = 0
	var slots: Array[String] = BoardPosition.all_slot_ids(player_id)
	for sid: String in slots:
		var inst: PokemonInstance = mgr.board_position.get_instance(sid)
		if inst != null:
			n += inst.attached_energy.size()
	return n


## Sum energy on active1+active2 for player_id (or both sides if -1).
func _count_energy_actives(mgr, player_id: int) -> int:
	var n: int = 0
	var pids := [player_id] if player_id >= 0 else [0, 1]
	for pid: int in pids:
		for s: String in BoardPosition.ACTIVE_SLOTS:
			var inst: PokemonInstance = mgr.board_position.get_instance("p%d_%s" % [pid, s])
			if inst != null:
				n += inst.attached_energy.size()
	return n


## Sum damage counters on active1+active2 for player_id.
func _count_damage_counters_actives(mgr, player_id: int) -> int:
	var n: int = 0
	for s: String in BoardPosition.ACTIVE_SLOTS:
		var inst: PokemonInstance = mgr.board_position.get_instance("p%d_%s" % [player_id, s])
		if inst != null:
			n += (inst.max_hp - inst.current_hp) / 10
	return n


## Wave-5 helper: pulls matching Basic Pokémon out of the player's deck and
## drops them onto the first empty bench slots, then shuffles the deck.
##
## Prompts the player to choose when there is a meaningful choice
## (`candidates.size() > max_pick`); otherwise auto-picks to preserve the
## existing no-choice semantics (and test expectations).
func _search_deck_basic_to_bench(ctx: AttackContext, p: Dictionary) -> void:
	var deck: Array = ctx.manager.game_position.decks[ctx.player_id]
	var count: int = int(p.get("count", 1))
	var slug: String = str(p.get("name_slug", ""))
	var slug_any: Array = p.get("name_slug_any_of", []) as Array
	var or_any_basic: bool = bool(p.get("or_any_basic", false))
	var type_filter: String = str(p.get("pokemon_type", "ANY"))
	var ignore_stage: bool = bool(p.get("ignore_stage", false))

	## Pass 1 — collect candidates without mutating the deck.
	var candidates: Array[PokemonCardData] = []
	for c in deck:
		if not (c is PokemonCardData):
			continue
		var pc := c as PokemonCardData
		if not ignore_stage and int(pc.stage) != 0:  # Stage.BASIC = 0
			continue
		var matched: bool = false
		if slug != "" and pc.name_slug == slug:
			matched = true
		elif slug_any.size() > 0 and slug_any.has(pc.name_slug):
			matched = true
		elif type_filter != "ANY":
			if int(pc.pokemon_type) == _energy_type_from_string(type_filter):
				matched = true
		else:
			matched = (slug == "" and slug_any.is_empty())
		if not matched and or_any_basic:
			matched = true
		if matched:
			candidates.append(pc)

	## Determine the cap: min of the per-effect count, the candidate pool, and
	## the bench capacity.
	var bench_capacity: int = 0
	for i in range(1, ctx.manager.bench_slot_count + 1):
		var slot := "p%d_bench%d" % [ctx.player_id, i]
		if ctx.manager.board_position.is_empty(slot):
			bench_capacity += 1
	var max_pick: int = mini(count, mini(candidates.size(), bench_capacity))

	if max_pick == 0:
		ctx.manager.game_position.shuffle_deck(ctx.player_id)
		return

	## Pick: auto when there is no meaningful choice, prompt otherwise.
	var picks: Array[PokemonCardData] = []
	if candidates.size() <= max_pick:
		picks = candidates
	else:
		var raw: Array[CardData] = []
		for pc in candidates:
			raw.append(pc)
		var chosen: Array[CardData] = await _ask_pick_cards(ctx, raw, max_pick,
				"Search your deck for a Basic Pokémon")
		for c in chosen:
			if c is PokemonCardData:
				picks.append(c as PokemonCardData)

	## Apply: move picks from deck onto empty bench slots, then shuffle.
	for pc in picks:
		deck.erase(pc)
		var bench: String = ctx.manager.board_position.first_empty_bench(ctx.player_id)
		if bench == "":
			break
		var inst := PokemonInstance.create(pc, ctx.player_id)
		ctx.manager.board_position.place(bench, inst)
	ctx.manager.game_position.shuffle_deck(ctx.player_id)

	## Optional follow-up: Dunsparce-style "you may switch attacker with a
	## benched Pokémon" tacked onto the same effect.  Runs inline so the
	## prompts resolve in order with the search (post_action queue would
	## interleave them).
	if bool(p.get("then_may_switch", false)):
		await _may_switch_attacker_with_bench(ctx)


## Prompts the player (MAY_CONFIRM) to switch the attacker with one of their
## benched Pokemon.  No-op if the attacker is no longer in its slot or the
## bench is empty.  Used by attacks with "you may switch" tail text.
func _may_switch_attacker_with_bench(ctx: AttackContext) -> void:
	var pid: int = ctx.player_id
	var atk_slot: String = ctx.attacker_slot
	if ctx.manager.board_position.get_instance(atk_slot) == null:
		return
	var bench_options: Array[String] = []
	for s: String in BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [pid, s]
		if not ctx.manager.board_position.is_empty(sid):
			bench_options.append(sid)
	if bench_options.is_empty():
		return

	var confirm := AttackQuery.new()
	confirm.kind = AttackQuery.Kind.MAY_CONFIRM
	confirm.player_id = pid
	confirm.prompt = "Switch the attacker with a benched Pokémon?"
	confirm.options = [true, false]
	var did_confirm: Variant = await ctx.manager.attack_resolver.ask(confirm)
	if did_confirm != true:
		return

	var swap_slot: String
	if bench_options.size() == 1:
		swap_slot = bench_options[0]
	else:
		var pick := AttackQuery.new()
		pick.kind = AttackQuery.Kind.CHOOSE_BENCH_TARGET
		pick.player_id = pid
		pick.prompt = "Switch with which Pokémon?"
		pick.options = bench_options
		var resp: Variant = await ctx.manager.attack_resolver.ask(pick)
		swap_slot = str(resp)
		if swap_slot == "" or not bench_options.has(swap_slot):
			return

	ctx.manager.board_position.swap(atk_slot, swap_slot)
	ctx.manager.pokemon_state_changed.emit(atk_slot,
		ctx.manager.board_position.get_instance(atk_slot))
	ctx.manager.pokemon_state_changed.emit(swap_slot,
		ctx.manager.board_position.get_instance(swap_slot))


## Emits an AttackQuery.CHOOSE_FROM_LIST and returns the player's picks.
## Caller is responsible for capping max_pick to a sensible value.
##
## When no listener is connected to player_query_requested (i.e. GUT runs
## without DialogManager / AIDriver), auto-picks the first max_pick options
## so deferred effects still resolve synchronously and assertions don't race
## an unanswered query.
func _ask_pick_cards(ctx: AttackContext, options: Array[CardData],
		max_pick: int, prompt: String) -> Array[CardData]:
	var resolver = ctx.manager.attack_resolver
	if resolver == null \
			or resolver.player_query_requested.get_connections().is_empty():
		var auto: Array[CardData] = []
		for i in mini(max_pick, options.size()):
			auto.append(options[i])
		return auto

	var q := AttackQuery.new()
	q.kind = AttackQuery.Kind.CHOOSE_FROM_LIST
	q.player_id = ctx.player_id
	q.prompt = prompt
	var arr: Array = []
	for c in options:
		arr.append(c)
	q.options = arr
	q.min_selections = 0
	q.max_selections = max_pick
	var resp: Variant = await resolver.ask(q)
	if not (resp is Array):
		return []
	var out: Array[CardData] = []
	for v in resp as Array:
		var c: CardData = v as CardData
		if c != null:
			out.append(c)
	return out


## Number of prize cards still in [player_id]'s prize area (not yet taken).
static func _prizes_remaining(mgr, player_id: int) -> int:
	var n: int = 0
	for c in mgr.game_position.prizes[player_id]:
		if c != null:
			n += 1
	return n


## Distinct EnergyType count among attacker's attached_energy.
static func _count_energy_types(inst: PokemonInstance) -> int:
	if inst == null:
		return 0
	var seen: Dictionary = {}
	for e: CardData in inst.attached_energy:
		if e is EnergyCardData:
			seen[int((e as EnergyCardData).energy_type)] = true
	return seen.size()


static func _attack_total_cost(atk: AttackData) -> int:
	if atk == null:
		return 0
	return (atk.cost_colorless + atk.cost_fire + atk.cost_water + atk.cost_grass
		+ atk.cost_lightning + atk.cost_psychic + atk.cost_fighting
		+ atk.cost_darkness + atk.cost_metal)


func _count_bench(mgr, player_id: int, type_str: String) -> int:
	var want: int = -1
	if type_str != "ANY":
		want = _energy_type_from_string(type_str)
	var n: int = 0
	for s: String in BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [player_id, s]
		var inst: PokemonInstance = mgr.board_position.get_instance(sid)
		if inst == null:
			continue
		if want < 0:
			n += 1
		elif inst.card != null and int(inst.card.pokemon_type) == want:
			n += 1
	return n


static func _energy_type_from_string(s: String) -> int:
	return PokemonCardData.EnergyType[s.to_upper()]


## Removes [count] energy cards of [energy_type] from the attacker.
## count = -1 removes all of that type.
## Wave 17: discarded cards are also appended to ctx.discarded_this_attack so
## chained bonus-damage handlers (Lava Flow / Dragon Burst) can scale by count.
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
		ctx.discarded_this_attack.append(c)
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
			ctx.discarded_this_attack.append(c)
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
