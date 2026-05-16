extends Node
## Registers all AbilityEffectRegistry handlers for Poké-Power and Poké-Body
## effects.  Loaded as a child of the match scene after ManagerSystem is
## ready, mirroring effect_handlers.gd (attacks) and trainer_handlers.gd.
##
## Day 3 wave 1 — passive Poké-Bodies that read game state via the
## AbilityEffects static helper.  Powers and the more complex Body patterns
## land in subsequent waves.

func _ready() -> void:
	_register_handlers()


func _register_handlers() -> void:
	## --- Pattern A: Flat damage modifier on the wearer ----------------------
	## Schema:
	##   {"amount": int,
	##    "requires": "" | "has_basic_energy",
	##    "after_wr": bool (informational; handler always applies after W/R)}
	## Cards: Pineco "Exoskeleton" (10), Kabuto "Exoskeleton" (20),
	##         Shelgon "Energy Guard" (10, requires basic energy).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_DAMAGE_REDUCTION,
		AbilityEffectDefinition.passive({"timing": "after_wr"})
	)

	## Pattern A — aura applied to every Pokémon on the same side, only while
	## the carrier is in active.
	## Schema: {"amount": int}
	## Cards: Salamence / Mightyena / Arbok "Intimidating Fang" (10).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_DAMAGE_TAKEN_AURA_ACTIVE,
		AbilityEffectDefinition.passive({"timing": "before_wr"})
	)

	## Pattern A — outgoing-damage bonus on every attack from this player while
	## the carrier is in active.
	## Schema: {"amount": int}
	## Cards: Crawdaunt "Power Pinchers" (10).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_DAMAGE_INCREASE_OUTGOING,
		AbilityEffectDefinition.passive({"timing": "before_wr"})
	)

	## Pattern A — reduction conditional on the attacker's type (and optionally
	## on a partner Pokémon being in play).
	## Schema: {"amount": int, "source_types": [type names],
	##          "requires": "" | "partner_in_play", "partner_slug": "..."}
	## Cards: Illumise "Glowing Screen" (30 from Fighting/Darkness if Volbeat).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_DAMAGE_REDUCTION_FROM_TYPES,
		AbilityEffectDefinition.passive({"timing": "after_wr"})
	)

	## --- Pattern B: Coin-gated reduction -----------------------------------
	## Schema: {"amount": int, "opponent_turn_only": bool}
	## Cards: Flygon "Sand Guard" (20), Cascoon / Silcoon "Hard Cocoon" (30,
	## opp turn only).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_COIN_GATED_REDUCTION,
		AbilityEffectDefinition.passive({"timing": "after_wr"})
	)

	## --- Pattern D: Status immunity ----------------------------------------
	## Schema: {"conditions": ["ALL"] | ["POISONED", "ASLEEP", ...]}
	## Cards: Roselia "Thick Skin" (ALL), Zangoose "Poison Resistance"
	## (POISONED).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_STATUS_IMMUNITY,
		AbilityEffectDefinition.passive({})
	)

	## --- Pattern E: Retaliation -------------------------------------------
	## Damage retaliation. Schema: {"counters": int}
	## Cards: Sharpedo "Rough Skin" (2), Carvanha "Rough Skin" (1).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_RETALIATE_DAMAGE,
		AbilityEffectDefinition.passive({})
	)

	## Status retaliation. Schema: {"condition": "BURNED" | "POISONED" | ...}
	## Cards: Arcanine / Growlithe "Fire Veil" (BURNED), Cacturne / Cacnea
	## "Poison Payback" (POISONED).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_RETALIATE_STATUS,
		AbilityEffectDefinition.passive({})
	)

	## --- Pattern F: Between-turn heal --------------------------------------
	## Schema: {"counters": int}  (1 counter = 10 HP)
	## Cards: Ludicolo / Lombre / Lotad "Rain Dish" (1 each).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_BETWEEN_TURN_HEAL,
		AbilityEffectDefinition.passive({})
	)

	## --- Pattern G: Retreat-cost override ----------------------------------
	## Schema: {"amount": int, "requires": "" | "has_basic_energy" |
	##           "partner_in_play", "partner_slug": "..."}
	## Cards: Vibrava "Levitate" (0, requires basic energy),
	##         Volbeat "Uplifting Glow" (0, requires Illumise in play).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_RETREAT_COST_OVERRIDE,
		AbilityEffectDefinition.passive({})
	)

	## --- Pattern J: Natural Cure ------------------------------------------
	## Triggered when a basic energy of the matching type is attached from
	## hand. Schema: {"required_type": "FIRE" | "WATER" | "GRASS" | ...}
	## Cards: Combusken "Natural Cure" (FIRE), Grovyle "Natural Cure" (GRASS),
	## Marshtomp "Natural Cure" (WATER).
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_NATURAL_CURE,
		AbilityEffectDefinition.passive({})
	)

	## ═══════════════════════════════════════════════════════════════════════
	## Wave 2 — passive Poké-Bodies that don't need per-handler logic; the
	## attack pipeline and play actions consult AbilityEffects helpers
	## directly. Registering them as passives makes the coverage smoke test
	## pass and keeps the registry as the source of truth.
	## ═══════════════════════════════════════════════════════════════════════

	## Beautifly "Withering Dust" — global Resistance disabled while in play.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_GLOBAL_RESISTANCE_DISABLE,
		AbilityEffectDefinition.passive({})
	)
	## Shedinja "Wonder Guard" / Wobbuffet "Safeguard" — source-class total
	## immunity. Schema: {"from": ["EVOLUTION", "POKEMON_EX", "BASIC"]}
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_SOURCE_IMMUNITY,
		AbilityEffectDefinition.passive({})
	)
	## Whiscash "Submerge" — damage immunity while on Bench.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_BENCH_DAMAGE_IMMUNITY,
		AbilityEffectDefinition.passive({})
	)
	## Kecleon "Energy Variation" — pokemon_type morphs from attached basic
	## energy; consulted by W/R compute and the Darkness/Metal helpers.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_TYPE_MORPH_FROM_ENERGY,
		AbilityEffectDefinition.passive({})
	)
	## Aerodactyl ex "Primal Lock" — opponent can't play Pokémon Tools while
	## the carrier is in play. Schema: {"block": ["POKEMON_TOOL"]}
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_OPPONENT_PLAY_LOCK,
		AbilityEffectDefinition.passive({})
	)
	## Dustox "Protective Dust" — attack effects on Dustox are prevented;
	## damage still applies. Consulted by AttackResolver between damage and
	## effect-execution steps.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_ATTACK_EFFECT_IMMUNITY_SELF,
		AbilityEffectDefinition.passive({})
	)

	## ═══════════════════════════════════════════════════════════════════════
	## Wave 3 — ability suppression.  Consulted by AbilityResolver.validate
	## (Power activation) and AbilityEffects._abilities_on (passive bodies).
	## ═══════════════════════════════════════════════════════════════════════

	## Slaking "Lazy" — opp can't use Poké-Powers while Slaking is Active.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_SUPPRESS_OPPONENT_POWERS,
		AbilityEffectDefinition.passive({})
	)
	## Muk ex "Toxic Gas" — all other Powers/Bodies ignored while Muk is Active.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_SUPPRESS_ALL_POWERS_AND_BODIES,
		AbilityEffectDefinition.passive({})
	)

	## ═══════════════════════════════════════════════════════════════════════
	## Wave 4 — Poké-Power wave 2: triggers fired from action callsites
	## rather than activated through the UI.
	## ═══════════════════════════════════════════════════════════════════════

	## Ampharos ex "Conductivity" — fires from ActionAttachEnergy.apply().
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_DAMAGE_ON_OPPONENT_ENERGY_ATTACH,
		AbilityEffectDefinition.passive({})
	)
	## Ninjask "Loose Shell" — fires from ActionEvolve.apply().
	## Schema: {"target_slug": "shedinja"}
	AbilityEffectRegistry.register_def(
		AbilityEffects.POWER_SEARCH_DECK_PLAY_SPECIFIC_BASIC,
		AbilityEffectDefinition.passive({})
	)
	## Plusle / Minun "Chain of Events" — passive trigger fired by
	## AttackResolver._maybe_chain_of_events after a regular attack resolves.
	## The carrier in the other active slot uses its own attack[0] (Cheer On)
	## as a sub-attack, gated by carrier energy cost + manager.chain_of_
	## events_used_this_turn (one chain per turn even with multiple carriers).
	AbilityEffectRegistry.register_def(
		AbilityEffects.POWER_REUSE_LAST_ATTACK,
		AbilityEffectDefinition.passive({})
	)

	## ═══════════════════════════════════════════════════════════════════════
	## Wave 6 — bodies + type-override power.
	## ═══════════════════════════════════════════════════════════════════════

	## Swampert "Natural Remedy" — fires from ActionAttachEnergy.apply() via
	## AbilityEffects.run_on_attached_energy.
	## Schema: {"required_type": "WATER", "counters": 1}
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_HEAL_ON_MATCHING_ENERGY_ATTACH,
		AbilityEffectDefinition.passive({})
	)
	## Cradily "Super Suction Cups" — consulted by ActionRetreat.validate.
	AbilityEffectRegistry.register_def(
		AbilityEffects.BODY_OPPONENT_RETREAT_LOCK,
		AbilityEffectDefinition.passive({})
	)

	## ═══════════════════════════════════════════════════════════════════════
	## Poké-Powers (Day 4 wave 1)
	##
	## All powers route through ActionUseAbility → AbilityResolver.dispatch().
	## Phase contract: VALIDATE rejects before the action commits; PROMPT
	## returns an AbilityQuery for the UI; APPLY mutates state and may use
	## resolver.ask(...) for multi-step picks; POST_APPLY is rarely needed.
	## ═══════════════════════════════════════════════════════════════════════
	_register_powers()


## --- Poké-Power handlers ----------------------------------------------------

func _register_powers() -> void:
	## P-A: Water Call (Swampert) — attach a Water Energy from hand to your
	## Active Pokémon (no pick UI; auto-targets the player's first active).
	## Schema: {"energy_type": "WATER"}
	var water_call_def := AbilityEffectDefinition.new()
	water_call_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var t: String = ctx.params.get("energy_type", "")
		if _hand_basic_energy_of_type(ctx, t) == null:
			ctx.fail_validation("No %s Energy in hand." % t.to_lower())
		if _own_active_slot(ctx) == "":
			ctx.fail_validation("No Active Pokémon to attach to.")
	water_call_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var t: String = ctx.params.get("energy_type", "")
		var energy: EnergyCardData = _hand_basic_energy_of_type(ctx, t)
		if energy == null:
			return
		var sid: String = _own_active_slot(ctx)
		if sid == "":
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		ctx.manager.game_position.take_from_hand(ctx.player_id, energy)
		inst.attach_energy(energy)
		ctx.manager.pokemon_state_changed.emit(sid, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — attached %s to Active." % [ctx.ability.ability_name, energy.display_name]
		)
	AbilityEffectRegistry.register_def("power_attach_basic_energy_from_hand_to_active",
		water_call_def)

	## P-A: Firestarter (Blaziken) — attach a Fire Energy from your discard to
	## a chosen Benched Pokémon.
	## Schema: {"energy_type": "FIRE"}
	var firestarter_def := AbilityEffectDefinition.new()
	firestarter_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var t: String = ctx.params.get("energy_type", "")
		if _discard_basic_energy_of_type(ctx, t) == null:
			ctx.fail_validation("No %s Energy in discard pile." % t.to_lower())
		if _own_bench_slots(ctx).is_empty():
			ctx.fail_validation("No Benched Pokémon to attach to.")
	firestarter_def.phase_handlers[AbilityResolver.Phase.PROMPT] = func(ctx: AbilityContext) -> AbilityQuery:
		var q := AbilityQuery.new()
		q.kind = AbilityQuery.Kind.CHOOSE_OWN_BENCH
		q.player_id = ctx.player_id
		q.prompt = "%s — choose a Benched Pokémon" % ctx.ability.ability_name
		var arr: Array = []
		for s in _own_bench_slots(ctx):
			arr.append(s)
		q.options = arr
		return q
	firestarter_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if sid == "":
			return
		var t: String = ctx.params.get("energy_type", "")
		var energy: EnergyCardData = _discard_basic_energy_of_type(ctx, t)
		if energy == null:
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null:
			return
		ctx.manager.game_position.take_from_discard(ctx.player_id, energy)
		inst.attach_energy(energy)
		ctx.manager.pokemon_state_changed.emit(sid, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — attached %s from discard to %s." % [
				ctx.ability.ability_name, energy.display_name, _short_slot(sid),
			]
		)
	AbilityEffectRegistry.register_def("power_attach_basic_energy_from_discard_to_bench",
		firestarter_def)

	## P-A: Magnetic Field (Magneton) — discard 1 hand card, recover up to 2
	## basic energy from discard to hand.
	var magnetic_field_def := AbilityEffectDefinition.new()
	magnetic_field_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		if _basic_energy_in_discard(ctx).is_empty():
			ctx.fail_validation("No basic Energy in discard pile.")
		if (ctx.manager.game_position.hands[ctx.player_id] as Array).is_empty():
			ctx.fail_validation("Hand is empty.")
	magnetic_field_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var resolver = ctx.manager.ability_resolver
		var pid: int = ctx.player_id
		var gp: GamePosition = ctx.manager.game_position
		## Step 1: choose hand card to discard.
		var dq := AbilityQuery.new()
		dq.kind = AbilityQuery.Kind.CHOOSE_FROM_HAND
		dq.player_id = pid
		dq.prompt = "%s — discard 1 card from your hand" % ctx.ability.ability_name
		dq.min_selections = 1
		dq.max_selections = 1
		dq.options = (gp.hands[pid] as Array).duplicate()
		var d_resp: Variant = await resolver.ask(dq)
		if not (d_resp is Array) or (d_resp as Array).is_empty():
			return
		var discarded: CardData = (d_resp as Array)[0] as CardData
		if discarded == null or not (gp.hands[pid] as Array).has(discarded):
			return
		gp.take_from_hand(pid, discarded)
		gp.put_in_discard(pid, discarded)
		## Step 2: choose up to N basic energies from discard.
		var basics: Array[CardData] = _basic_energy_in_discard(ctx)
		if basics.is_empty():
			return
		var rq := AbilityQuery.new()
		rq.kind = AbilityQuery.Kind.CHOOSE_FROM_LIST
		rq.player_id = pid
		rq.prompt = "%s — recover up to 2 basic Energy" % ctx.ability.ability_name
		rq.min_selections = 0
		rq.max_selections = mini(2, basics.size())
		var arr: Array = []
		for e in basics: arr.append(e)
		rq.options = arr
		var r_resp: Variant = await resolver.ask(rq)
		if not (r_resp is Array):
			return
		var moved: int = 0
		for c_variant in r_resp as Array:
			var c: CardData = c_variant as CardData
			if c == null:
				continue
			if gp.take_from_discard(pid, c):
				gp.put_in_hand(pid, c)
				moved += 1
		ctx.manager.log_message.emit(
			"[Power] %s — recovered %d Energy from discard." % [
				ctx.ability.ability_name, moved,
			]
		)
	AbilityEffectRegistry.register_def("power_discard_hand_recover_basic_energy",
		magnetic_field_def)

	## P-A: Psy Shadow (Gardevoir) — search Psychic Energy from deck, attach to
	## a chosen own Pokémon, then put 2 damage counters on that Pokémon.
	## Schema: {"energy_type": "PSYCHIC", "damage_counters": 2}
	var psy_shadow_def := AbilityEffectDefinition.new()
	psy_shadow_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var t: String = ctx.params.get("energy_type", "")
		if _deck_basic_energy_of_type(ctx, t) == null:
			ctx.fail_validation("No %s Energy in deck." % t.to_lower())
		if _all_own_slots(ctx).is_empty():
			ctx.fail_validation("No Pokémon in play.")
	psy_shadow_def.phase_handlers[AbilityResolver.Phase.PROMPT] = func(ctx: AbilityContext) -> AbilityQuery:
		var q := AbilityQuery.new()
		q.kind = AbilityQuery.Kind.CHOOSE_OWN_POKEMON
		q.player_id = ctx.player_id
		q.prompt = "%s — choose a Pokémon to receive the Energy" % ctx.ability.ability_name
		var arr: Array = []
		for s in _all_own_slots(ctx):
			arr.append(s)
		q.options = arr
		return q
	psy_shadow_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if sid == "":
			return
		var t: String = ctx.params.get("energy_type", "")
		var energy: EnergyCardData = _deck_basic_energy_of_type(ctx, t)
		if energy == null:
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null:
			return
		ctx.manager.game_position.take_from_deck(ctx.player_id, energy)
		inst.attach_energy(energy)
		var counters: int = int(ctx.params.get("damage_counters", 0))
		if counters > 0:
			inst.apply_damage(counters * 10)
		ctx.manager.game_position.shuffle_deck(ctx.player_id)
		ctx.manager.pokemon_state_changed.emit(sid, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — attached %s and put %d counter%s on %s." % [
				ctx.ability.ability_name, energy.display_name,
				counters, "" if counters == 1 else "s",
				inst.card.display_name,
			]
		)
	AbilityEffectRegistry.register_def("power_search_energy_to_pokemon_with_damage",
		psy_shadow_def)

	## P-B: Energy Trans (Sceptile) — repeatable; move a Grass Energy between
	## your Pokémon. Schema: {"energy_type": "GRASS"}
	var energy_trans_def := AbilityEffectDefinition.new()
	energy_trans_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var t: String = ctx.params.get("energy_type", "")
		if _own_pokemon_with_energy_of_type(ctx, t).is_empty():
			ctx.fail_validation("No Pokémon with %s Energy attached." % t.to_lower())
		if _all_own_slots(ctx).size() < 2:
			ctx.fail_validation("Need two Pokémon in play.")
	energy_trans_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var t: String = ctx.params.get("energy_type", "")
		await _move_energy_between_own(ctx, t)
	AbilityEffectRegistry.register_def("power_move_basic_energy_between_own",
		energy_trans_def)

	## P-B: Call for Power (Dragonite ex) — repeatable; move ANY energy from
	## one of your Pokémon to the carrier of this power (the ability source).
	var call_for_power_def := AbilityEffectDefinition.new()
	call_for_power_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		if _own_pokemon_with_any_energy_excluding(ctx, ctx.source_slot).is_empty():
			ctx.fail_validation("No other Pokémon with Energy attached.")
	call_for_power_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		await _move_any_energy_to_slot(ctx, ctx.source_slot)
	AbilityEffectRegistry.register_def("power_move_any_energy_to_self",
		call_for_power_def)

	## P-C: Dragon Wind (Salamence) / Drive Off (Swellow) — switch an
	## opponent's Benched Pokémon with the Defending Pokémon. Active-only.
	var switch_opp_def := AbilityEffectDefinition.new()
	switch_opp_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		if not _is_active_slot(ctx.source_slot):
			ctx.fail_validation("Source Pokémon must be Active.")
		if _opp_bench_slots(ctx).is_empty():
			ctx.fail_validation("Opponent has no Benched Pokémon.")
		if _opp_active_slot(ctx) == "":
			ctx.fail_validation("Opponent has no Active Pokémon.")
	switch_opp_def.phase_handlers[AbilityResolver.Phase.PROMPT] = func(ctx: AbilityContext) -> AbilityQuery:
		var q := AbilityQuery.new()
		q.kind = AbilityQuery.Kind.CHOOSE_OPPONENT_BENCH
		q.player_id = ctx.player_id
		q.prompt = "%s — choose opponent's Benched Pokémon" % ctx.ability.ability_name
		var arr: Array = []
		for s in _opp_bench_slots(ctx):
			arr.append(s)
		q.options = arr
		return q
	switch_opp_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var bench_sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if bench_sid == "":
			return
		var opp_active: String = _opp_active_slot(ctx)
		if opp_active == "":
			return
		ctx.manager.board_position.swap(opp_active, bench_sid)
		ctx.manager.log_message.emit(
			"[Power] %s — switched opponent %s ↔ %s." % [
				ctx.ability.ability_name,
				_short_slot(opp_active), _short_slot(bench_sid),
			]
		)
	AbilityEffectRegistry.register_def("power_switch_opponent_active_with_bench",
		switch_opp_def)

	## P-D: Fan Away (Shiftry) — flip a coin; heads → return 1 Energy attached
	## to the Defending Pokémon to opponent's hand.
	var fan_away_def := AbilityEffectDefinition.new()
	fan_away_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var heads: bool = ctx.manager.flip_coin(ctx.ability.ability_name)
		ctx.manager.log_message.emit(
			"[Coin] %s — %s" % [ctx.ability.ability_name, "Heads" if heads else "Tails"]
		)
		if not heads:
			return
		var opp_active: String = _opp_active_slot(ctx)
		if opp_active == "":
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(opp_active)
		if inst == null or inst.attached_energy.is_empty():
			ctx.manager.log_message.emit(
				"[Power] %s — opponent's Active has no Energy." % ctx.ability.ability_name
			)
			return
		var resolver = ctx.manager.ability_resolver
		var q := AbilityQuery.new()
		q.kind = AbilityQuery.Kind.CHOOSE_ENERGY_ON_POKEMON
		q.player_id = ctx.player_id
		q.prompt = "%s — choose Energy to return to opponent's hand" % ctx.ability.ability_name
		var arr: Array = []
		for e in inst.attached_energy:
			arr.append(e)
		q.options = arr
		var resp: Variant = await resolver.ask(q)
		var chosen: CardData = resp as CardData
		if chosen == null:
			return
		inst.attached_energy.erase(chosen)
		inst.refresh_visual()
		var opp_id: int = 1 - ctx.player_id
		ctx.manager.game_position.put_in_hand(opp_id, chosen)
		ctx.manager.pokemon_state_changed.emit(opp_active, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — returned %s to opponent's hand." % [
				ctx.ability.ability_name, chosen.display_name,
			]
		)
	AbilityEffectRegistry.register_def("power_coin_return_defender_energy_to_hand",
		fan_away_def)

	## P-D: Chaos Flash (Golduck) — active only; flip a coin; heads → the
	## Defending Pokémon is now Confused. Schema: {"condition": "CONFUSED"}
	var chaos_flash_def := AbilityEffectDefinition.new()
	chaos_flash_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		if not _is_active_slot(ctx.source_slot):
			ctx.fail_validation("Source Pokémon must be Active.")
		if _opp_active_slot(ctx) == "":
			ctx.fail_validation("Opponent has no Active Pokémon.")
	chaos_flash_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var heads: bool = ctx.manager.flip_coin(ctx.ability.ability_name)
		ctx.manager.log_message.emit(
			"[Coin] %s — %s" % [ctx.ability.ability_name, "Heads" if heads else "Tails"]
		)
		if not heads:
			return
		var cond_name: String = str(ctx.params.get("condition", ""))
		var cond := _condition_from_name(cond_name)
		if cond < 0:
			return
		var opp_active: String = _opp_active_slot(ctx)
		if opp_active == "":
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(opp_active)
		if inst == null:
			return
		inst.add_condition(cond)
		ctx.manager.pokemon_state_changed.emit(opp_active, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — Defending Pokémon is now %s." % [
				ctx.ability.ability_name, cond_name,
			]
		)
	AbilityEffectRegistry.register_def("power_coin_inflict_status_on_defender",
		chaos_flash_def)

	## P-E: Energy Draw (Delcatty) — discard 1 Energy from hand, draw up to 3.
	## Schema: {"draw": 3}
	var energy_draw_def := AbilityEffectDefinition.new()
	energy_draw_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var has_energy: bool = false
		for c in ctx.manager.game_position.hands[ctx.player_id]:
			if c is EnergyCardData:
				has_energy = true
				break
		if not has_energy:
			ctx.fail_validation("No Energy in hand to discard.")
	energy_draw_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var resolver = ctx.manager.ability_resolver
		var pid: int = ctx.player_id
		var gp: GamePosition = ctx.manager.game_position
		var energies: Array = []
		for c in gp.hands[pid]:
			if c is EnergyCardData:
				energies.append(c)
		var q := AbilityQuery.new()
		q.kind = AbilityQuery.Kind.CHOOSE_FROM_HAND
		q.player_id = pid
		q.prompt = "%s — discard 1 Energy from your hand" % ctx.ability.ability_name
		q.min_selections = 1
		q.max_selections = 1
		q.options = energies
		var resp: Variant = await resolver.ask(q)
		if not (resp is Array) or (resp as Array).is_empty():
			return
		var disc: CardData = (resp as Array)[0] as CardData
		if disc == null or not (gp.hands[pid] as Array).has(disc):
			return
		gp.take_from_hand(pid, disc)
		gp.put_in_discard(pid, disc)
		var draw_count: int = int(ctx.params.get("draw", 3))
		var drawn: int = 0
		for _i in range(draw_count):
			if gp.deck_size(pid) <= 0:
				break
			gp.draw(pid)
			drawn += 1
		ctx.manager.log_message.emit(
			"[Power] %s — discarded %s and drew %d card%s." % [
				ctx.ability.ability_name, disc.display_name,
				drawn, "" if drawn == 1 else "s",
			]
		)
	AbilityEffectRegistry.register_def("power_discard_energy_draw_n",
		energy_draw_def)

	## P-G: Healing Wind (Xatu) — remove 1 damage counter from each of your
	## Active Pokémon. Schema: {"counters": 1}
	var healing_wind_def := AbilityEffectDefinition.new()
	healing_wind_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var counters: int = int(ctx.params.get("counters", 1))
		var heal_hp: int = counters * 10
		var healed: int = 0
		for s in BoardPosition.ACTIVE_SLOTS:
			var sid := "p%d_%s" % [ctx.player_id, s]
			var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
			if inst == null:
				continue
			var missing: int = inst.max_hp - inst.current_hp
			if missing <= 0:
				continue
			inst.heal(mini(heal_hp, missing))
			ctx.manager.pokemon_state_changed.emit(sid, inst)
			healed += 1
		ctx.manager.log_message.emit(
			"[Power] %s — healed %d Active Pokémon." % [
				ctx.ability.ability_name, healed,
			]
		)
	AbilityEffectRegistry.register_def("power_heal_each_own_active",
		healing_wind_def)

	## ═══════════════════════════════════════════════════════════════════════
	## Wave 5 — Baby Evolution.  Used by Pichu / Azurill / Elekid / Wynaut.
	## Promotes the baby into a specific Basic Pokémon from hand, clears all
	## damage counters and special conditions on the slot.  Once per turn.
	## Schema: {"evolves_into": "pikachu" (name_slug)}
	## ═══════════════════════════════════════════════════════════════════════
	var baby_def := AbilityEffectDefinition.new()
	baby_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var target_slug: String = str(ctx.params.get("evolves_into", ""))
		if target_slug == "":
			ctx.fail_validation("Baby Evolution: missing evolves_into param.")
			return
		if _find_basic_in_hand(ctx, target_slug) == null:
			ctx.fail_validation("No %s in hand." % target_slug.capitalize())
		## Carrier just-entered-play protection mirrors regular evolution.
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(ctx.source_slot)
		if inst != null and (
				ctx.manager.pokemon_entered_play_this_turn[ctx.player_id] as Array
			).has(inst):
			ctx.fail_validation("This Pokémon just came into play this turn.")
		if ctx.manager.is_first_turn_for(ctx.player_id):
			ctx.fail_validation("Cannot Baby-evolve on your first turn.")
	baby_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var target_slug: String = str(ctx.params.get("evolves_into", ""))
		var target: PokemonCardData = _find_basic_in_hand(ctx, target_slug)
		if target == null:
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(ctx.source_slot)
		if inst == null:
			return
		var baby_card: PokemonCardData = inst.card
		ctx.manager.game_position.take_from_hand(ctx.player_id, target)
		## Stack the new card on top (mirrors evolve_to, but bypasses the
		## evolves_from check since both cards are Basics).
		if baby_card != null:
			inst.prior_stages.append(baby_card)
		inst.card = target
		inst.aura_hp_bonus = 0
		inst.max_hp = target.hp_max
		inst.current_hp = target.hp_max   ## "remove all damage counters".
		inst.special_conditions.clear()
		StadiumEffects.reconcile_aura_for(ctx.source_slot, inst, ctx.manager)
		inst.refresh_visual()
		## Newly-evolved Pokémon can't evolve again this turn.
		ctx.manager.pokemon_entered_play_this_turn[ctx.player_id].append(inst)
		ctx.manager.pokemon_state_changed.emit(ctx.source_slot, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — %s evolved into %s; all damage removed." % [
				ctx.ability.ability_name,
				baby_card.display_name if baby_card != null else "Baby",
				target.display_name,
			]
		)
	AbilityEffectRegistry.register_def(AbilityEffects.POWER_BABY_EVOLUTION,
		baby_def)

	## ═══════════════════════════════════════════════════════════════════════
	## Wave 6 — Type override until end of turn.  Used by Solrock "Solar
	## Eclipse" (→ FIRE if Lunatone partner) and Lunatone "Lunar Eclipse"
	## (→ DARKNESS if Solrock partner).  Reads inst.type_override_until_turn
	## via AbilityEffects.effective_pokemon_type; auto-clears in the manager
	## sweep at the next turn boundary.
	## Schema: {"partner_slug": "lunatone", "new_type": "FIRE"}
	## ═══════════════════════════════════════════════════════════════════════
	var type_morph_def := AbilityEffectDefinition.new()
	type_morph_def.phase_handlers[AbilityResolver.Phase.VALIDATE] = func(ctx: AbilityContext) -> void:
		var partner_slug: String = str(ctx.params.get("partner_slug", ""))
		if partner_slug == "":
			ctx.fail_validation("Type override: missing partner_slug param.")
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(ctx.source_slot)
		## Power rule text: "can't be used if affected by a Special Condition."
		## ActionUseAbility already blocks Asleep/Confused/Paralyzed for every
		## Power; this extends the gate to Burned and Poisoned for this card.
		if inst != null and not inst.special_conditions.is_empty():
			ctx.fail_validation("%s is affected by a Special Condition." % (
				inst.card.display_name if inst.card else "This Pokémon"
			))
		if not _partner_in_play(ctx, partner_slug):
			ctx.fail_validation("%s must be in play." % partner_slug.capitalize())
	type_morph_def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(ctx.source_slot)
		if inst == null:
			return
		var type_name: String = str(ctx.params.get("new_type", ""))
		var type_idx: int = _energy_type_from_name(type_name)
		if type_idx < 0:
			return
		inst.type_override_until_turn = ctx.manager.turn_number
		inst.type_override_value = type_idx
		ctx.manager.pokemon_state_changed.emit(ctx.source_slot, inst)
		ctx.manager.log_message.emit(
			"[Power] %s — %s is now %s type until end of turn." % [
				ctx.ability.ability_name,
				inst.card.display_name if inst.card else "Pokémon",
				type_name,
			]
		)
	AbilityEffectRegistry.register_def(
		AbilityEffects.POWER_TYPE_OVERRIDE_UNTIL_TURN_END, type_morph_def)


## --- Poké-Power helpers -----------------------------------------------------


## Returns true when any Pokémon on the caster's side has the given
## name_slug in play (active or bench).  Used by partner-required powers.
static func _partner_in_play(ctx: AbilityContext, target_slug: String) -> bool:
	for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
		var sid := "p%d_%s" % [ctx.player_id, s]
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst != null and inst.card != null and inst.card.name_slug == target_slug:
			return true
	return false

## Returns the first Basic Pokémon card in [ctx.player_id]'s hand whose
## name_slug matches [target_slug], or null.  Used by Baby Evolution.
static func _find_basic_in_hand(ctx: AbilityContext, target_slug: String) -> PokemonCardData:
	for c in ctx.manager.game_position.hands[ctx.player_id]:
		if c is PokemonCardData and (c as PokemonCardData).name_slug == target_slug \
				and (c as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return c
	return null


static func _own_active_slot(ctx: AbilityContext) -> String:
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [ctx.player_id, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			return sid
	return ""


static func _opp_active_slot(ctx: AbilityContext) -> String:
	var opp := 1 - ctx.player_id
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [opp, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			return sid
	return ""


static func _own_bench_slots(ctx: AbilityContext) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [ctx.player_id, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			out.append(sid)
	return out


static func _opp_bench_slots(ctx: AbilityContext) -> Array[String]:
	var opp := 1 - ctx.player_id
	var out: Array[String] = []
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [opp, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			out.append(sid)
	return out


static func _all_own_slots(ctx: AbilityContext) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [ctx.player_id, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			out.append(sid)
	return out


static func _is_active_slot(sid: String) -> bool:
	return "active" in sid


static func _short_slot(slot_id: String) -> String:
	if slot_id.contains("active1"): return "Active 1"
	if slot_id.contains("active2"): return "Active 2"
	if slot_id.contains("bench1"):  return "Bench 1"
	if slot_id.contains("bench2"):  return "Bench 2"
	if slot_id.contains("bench3"):  return "Bench 3"
	if slot_id.contains("bench4"):  return "Bench 4"
	if slot_id.contains("bench5"):  return "Bench 5"
	return slot_id


## Returns the first basic energy card of [type_name] in the player's hand,
## or null. Energy_type comparison uses the enum-name string.
static func _hand_basic_energy_of_type(ctx: AbilityContext, type_name: String) -> EnergyCardData:
	if type_name == "":
		return null
	var target := _energy_type_from_name(type_name)
	if target < 0:
		return null
	for c in ctx.manager.game_position.hands[ctx.player_id]:
		if c is EnergyCardData and int((c as EnergyCardData).energy_type) == target \
				and _is_basic_energy(c as EnergyCardData):
			return c
	return null


static func _discard_basic_energy_of_type(ctx: AbilityContext, type_name: String) -> EnergyCardData:
	if type_name == "":
		return null
	var target := _energy_type_from_name(type_name)
	if target < 0:
		return null
	for c in ctx.manager.game_position.discards[ctx.player_id]:
		if c is EnergyCardData and int((c as EnergyCardData).energy_type) == target \
				and _is_basic_energy(c as EnergyCardData):
			return c
	return null


static func _deck_basic_energy_of_type(ctx: AbilityContext, type_name: String) -> EnergyCardData:
	if type_name == "":
		return null
	var target := _energy_type_from_name(type_name)
	if target < 0:
		return null
	for c in ctx.manager.game_position.decks[ctx.player_id]:
		if c is EnergyCardData and int((c as EnergyCardData).energy_type) == target \
				and _is_basic_energy(c as EnergyCardData):
			return c
	return null


static func _basic_energy_in_discard(ctx: AbilityContext) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in ctx.manager.game_position.discards[ctx.player_id]:
		if c is EnergyCardData and _is_basic_energy(c as EnergyCardData):
			out.append(c)
	return out


static func _is_basic_energy(e: EnergyCardData) -> bool:
	var cid := e.card_id.to_lower()
	if cid.contains("rainbow") or cid.contains("multi"):
		return false
	return true


static func _energy_type_from_name(name: String) -> int:
	var keys: Array = PokemonCardData.EnergyType.keys()
	return keys.find(name.to_upper())


static func _condition_from_name(name: String) -> int:
	var keys: Array = PokemonInstance.SpecialCondition.keys()
	return keys.find(name.to_upper())


## Returns own slots whose Pokémon has at least 1 attached energy of [type_name].
static func _own_pokemon_with_energy_of_type(ctx: AbilityContext,
		type_name: String) -> Array[String]:
	var target := _energy_type_from_name(type_name)
	var out: Array[String] = []
	if target < 0:
		return out
	for sid in _all_own_slots(ctx):
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null:
			continue
		for e in inst.attached_energy:
			if e is EnergyCardData and int((e as EnergyCardData).energy_type) == target:
				out.append(sid)
				break
	return out


## Returns own slots with any energy attached, excluding [exclude_slot].
static func _own_pokemon_with_any_energy_excluding(ctx: AbilityContext,
		exclude_slot: String) -> Array[String]:
	var out: Array[String] = []
	for sid in _all_own_slots(ctx):
		if sid == exclude_slot:
			continue
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst != null and not inst.attached_energy.is_empty():
			out.append(sid)
	return out


## Energy Trans pipeline: pick source pokemon → pick energy → pick destination.
static func _move_energy_between_own(ctx: AbilityContext, type_name: String) -> void:
	var resolver = ctx.manager.ability_resolver
	var src_options: Array[String] = _own_pokemon_with_energy_of_type(ctx, type_name)
	if src_options.is_empty():
		return
	var src_q := AbilityQuery.new()
	src_q.kind = AbilityQuery.Kind.CHOOSE_OWN_POKEMON
	src_q.player_id = ctx.player_id
	src_q.prompt = "%s — choose source Pokémon" % ctx.ability.ability_name
	var s_arr: Array = []
	for s in src_options: s_arr.append(s)
	src_q.options = s_arr
	var src_sid: String = str(await resolver.ask(src_q))
	if src_sid == "":
		return
	var src_inst: PokemonInstance = ctx.manager.board_position.get_instance(src_sid)
	if src_inst == null:
		return
	var target_type := _energy_type_from_name(type_name)
	var matching: Array[CardData] = []
	for e in src_inst.attached_energy:
		if e is EnergyCardData and int((e as EnergyCardData).energy_type) == target_type:
			matching.append(e)
	if matching.is_empty():
		return
	var e_q := AbilityQuery.new()
	e_q.kind = AbilityQuery.Kind.CHOOSE_ENERGY_ON_POKEMON
	e_q.player_id = ctx.player_id
	e_q.prompt = "%s — choose Energy to move" % ctx.ability.ability_name
	var e_arr: Array = []
	for e in matching: e_arr.append(e)
	e_q.options = e_arr
	var chosen: CardData = await resolver.ask(e_q) as CardData
	if chosen == null:
		return
	var dest_options: Array[String] = []
	for s in _all_own_slots(ctx):
		if s != src_sid:
			dest_options.append(s)
	if dest_options.is_empty():
		return
	var d_q := AbilityQuery.new()
	d_q.kind = AbilityQuery.Kind.CHOOSE_OWN_POKEMON
	d_q.player_id = ctx.player_id
	d_q.prompt = "%s — choose destination Pokémon" % ctx.ability.ability_name
	var d_arr: Array = []
	for s in dest_options: d_arr.append(s)
	d_q.options = d_arr
	var dest_sid: String = str(await resolver.ask(d_q))
	if dest_sid == "":
		return
	var dest_inst: PokemonInstance = ctx.manager.board_position.get_instance(dest_sid)
	if dest_inst == null:
		return
	src_inst.attached_energy.erase(chosen)
	src_inst.refresh_visual()
	dest_inst.attach_energy(chosen)
	ctx.manager.pokemon_state_changed.emit(src_sid, src_inst)
	ctx.manager.pokemon_state_changed.emit(dest_sid, dest_inst)
	ctx.manager.log_message.emit(
		"[Power] %s — moved %s from %s to %s." % [
			ctx.ability.ability_name, chosen.display_name,
			_short_slot(src_sid), _short_slot(dest_sid),
		]
	)


## Call for Power pipeline: pick source → pick any energy → move to [dest_sid].
static func _move_any_energy_to_slot(ctx: AbilityContext, dest_sid: String) -> void:
	var resolver = ctx.manager.ability_resolver
	var src_options := _own_pokemon_with_any_energy_excluding(ctx, dest_sid)
	if src_options.is_empty():
		return
	var src_q := AbilityQuery.new()
	src_q.kind = AbilityQuery.Kind.CHOOSE_OWN_POKEMON
	src_q.player_id = ctx.player_id
	src_q.prompt = "%s — choose source Pokémon" % ctx.ability.ability_name
	var s_arr: Array = []
	for s in src_options: s_arr.append(s)
	src_q.options = s_arr
	var src_sid: String = str(await resolver.ask(src_q))
	if src_sid == "":
		return
	var src_inst: PokemonInstance = ctx.manager.board_position.get_instance(src_sid)
	if src_inst == null or src_inst.attached_energy.is_empty():
		return
	var e_q := AbilityQuery.new()
	e_q.kind = AbilityQuery.Kind.CHOOSE_ENERGY_ON_POKEMON
	e_q.player_id = ctx.player_id
	e_q.prompt = "%s — choose Energy to move" % ctx.ability.ability_name
	var e_arr: Array = []
	for e in src_inst.attached_energy: e_arr.append(e)
	e_q.options = e_arr
	var chosen: CardData = await resolver.ask(e_q) as CardData
	if chosen == null:
		return
	var dest_inst: PokemonInstance = ctx.manager.board_position.get_instance(dest_sid)
	if dest_inst == null:
		return
	src_inst.attached_energy.erase(chosen)
	src_inst.refresh_visual()
	dest_inst.attach_energy(chosen)
	ctx.manager.pokemon_state_changed.emit(src_sid, src_inst)
	ctx.manager.pokemon_state_changed.emit(dest_sid, dest_inst)
	ctx.manager.log_message.emit(
		"[Power] %s — moved %s from %s to %s." % [
			ctx.ability.ability_name, chosen.display_name,
			_short_slot(src_sid), _short_slot(dest_sid),
		]
	)
