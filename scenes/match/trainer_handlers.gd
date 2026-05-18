extends Node
## Registers all TrainerEffectRegistry handlers for Trainer-card effects.
## Loaded as a child of the match scene after ManagerSystemSingleton is ready,
## mirroring effect_handlers.gd for attacks.
##
## Active keys (PR #2 — no-input + passive stadium handlers):
##   draw_until                       — RS Professor Birch
##   remove_conditions_all_active     — SS Double Full Heal
##   stadium_passive                  — DR High/Low Pressure System (no-op
##                                      dispatch; effect is read by other code
##                                      via StadiumEffects.retreat_discount_for)
##   stub_not_implemented             — placeholder for deferred Tools/Fossils

func _ready() -> void:
	_register_handlers()


## Flips a coin AND awaits the coin overlay animation so subsequent dialogs
## (typically a `_search_deck_into_hand` follow-up) don't race ahead and hide
## the flip from the player.  Safe when animation_manager is null (GUT tests).
static func _flip_coin_awaited(ctx: TrainerContext) -> bool:
	var heads: bool = ctx.manager.flip_coin(ctx.card.display_name)
	if ctx.manager.animation_manager != null:
		await ctx.manager.animation_manager.wait_until_drained()
	return heads


## Same, for batch flips.  Returns the array of results.
static func _flip_coins_batch_awaited(ctx: TrainerContext, count: int) -> Array[bool]:
	var results: Array[bool] = ctx.manager.flip_coins_batch(count, ctx.card.display_name)
	if ctx.manager.animation_manager != null:
		await ctx.manager.animation_manager.wait_until_drained()
	return results


func _register_handlers() -> void:
	## ── draw_until — Professor Birch ─────────────────────────────────────
	## Params: {"target_size": 6}
	## Draws from deck until the player's hand reaches target_size or the
	## deck runs out, whichever comes first.
	TrainerEffectRegistry.register_def("draw_until", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var target: int = int(ctx.params.get("target_size", 6))
			var pid: int = ctx.player_id
			var gp: GamePosition = ctx.manager.game_position
			var drawn: int = 0
			while gp.hand_size(pid) < target and gp.deck_size(pid) > 0:
				gp.draw(pid)
				drawn += 1
			ctx.manager.log_message.emit(
				"[Trainer] %s — drew %d card%s (hand now %d)." % [
					ctx.card.display_name, drawn, "" if drawn == 1 else "s",
					gp.hand_size(pid),
				]
			)
	))

	## ── remove_conditions_all_active — Double Full Heal ──────────────────
	## Clears every special condition from each of the user's active slots.
	TrainerEffectRegistry.register_def("remove_conditions_all_active", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var pid: int = ctx.player_id
			var cleared: int = 0
			for s in BoardPosition.ACTIVE_SLOTS:
				var sid: String = "p%d_%s" % [pid, s]
				var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
				if inst == null:
					continue
				if not inst.special_conditions.is_empty():
					cleared += inst.special_conditions.size()
					inst.special_conditions.clear()
					inst.refresh_visual()
					ctx.manager.pokemon_state_changed.emit(sid, inst)
			ctx.manager.log_message.emit(
				"[Trainer] %s — cleared %d special condition%s." % [
					ctx.card.display_name, cleared, "" if cleared == 1 else "s",
				]
			)
	))

	## ── stadium_passive — High Pressure / Low Pressure System ────────────
	## The board-state mutation (replacing the active stadium) is owned by
	## ActionPlayStadium; the effect itself (retreat discount) is read by
	## ActionRetreat through StadiumEffects.retreat_discount_for().  The
	## handler here just logs entry into play.
	TrainerEffectRegistry.register_def("stadium_passive", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			ctx.manager.log_message.emit(
				"[Stadium] %s comes into play." % ctx.card.display_name
			)
	))

	## ── heal_choice — Potion ─────────────────────────────────────────────
	## Params: {"counters": 2}  (1 counter = 10 HP)
	## PROMPT lists every own Pokémon with damage > 0; APPLY heals the
	## chosen Pokémon by counters * 10, capped at max HP.
	var heal_choice_def := TrainerEffectDefinition.new()
	heal_choice_def.phase_handlers[TrainerResolver.Phase.VALIDATE] = func(ctx: TrainerContext) -> void:
		if _own_damaged_slots(ctx).is_empty():
			ctx.fail_validation("No damaged Pokémon to heal.")
	heal_choice_def.phase_handlers[TrainerResolver.Phase.PROMPT] = func(ctx: TrainerContext) -> TrainerQuery:
		var q := TrainerQuery.new()
		q.kind = TrainerQuery.Kind.CHOOSE_OWN_POKEMON
		q.player_id = ctx.player_id
		var counters: int = int(ctx.params.get("counters", 2))
		q.prompt = "Heal which Pokémon? (%d damage counter%s)" % [
			counters, "" if counters == 1 else "s",
		]
		var arr: Array = []
		for s in _own_damaged_slots(ctx):
			arr.append(s)
		q.options = arr
		return q
	heal_choice_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if sid == "":
			ctx.manager.log_message.emit("[Trainer] %s — cancelled." % ctx.card.display_name)
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null:
			return
		var counters: int = int(ctx.params.get("counters", 2))
		var damage_remaining: int = inst.max_hp - inst.current_hp
		var heal_amount: int = mini(counters * 10, damage_remaining)
		inst.heal(heal_amount)
		ctx.manager.pokemon_state_changed.emit(sid, inst)
		ctx.manager.log_message.emit(
			"[Trainer] %s — healed %s for %d." % [
				ctx.card.display_name, inst.card.display_name, heal_amount,
			]
		)
	TrainerEffectRegistry.register_def("heal_choice", heal_choice_def)

	## ── switch_active — Switch ───────────────────────────────────────────
	## PROMPT lists own benched Pokémon; APPLY swaps with the player's
	## first occupied active slot.
	var switch_def := TrainerEffectDefinition.new()
	switch_def.phase_handlers[TrainerResolver.Phase.VALIDATE] = func(ctx: TrainerContext) -> void:
		if _own_bench_slots(ctx).is_empty():
			ctx.fail_validation("No benched Pokémon to switch with.")
		if _own_active_slot(ctx) == "":
			ctx.fail_validation("No active Pokémon to switch.")
	switch_def.phase_handlers[TrainerResolver.Phase.PROMPT] = func(ctx: TrainerContext) -> TrainerQuery:
		var q := TrainerQuery.new()
		q.kind = TrainerQuery.Kind.CHOOSE_OWN_BENCH
		q.player_id = ctx.player_id
		q.prompt = "Switch in which Pokémon?"
		var arr: Array = []
		for s in _own_bench_slots(ctx):
			arr.append(s)
		q.options = arr
		return q
	switch_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var bench_sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if bench_sid == "":
			ctx.manager.log_message.emit("[Trainer] %s — cancelled." % ctx.card.display_name)
			return
		var active_sid: String = _own_active_slot(ctx)
		if active_sid == "" or bench_sid == "":
			return
		ctx.manager.board_position.swap(active_sid, bench_sid)
		ctx.manager.log_message.emit(
			"[Trainer] %s — switched %s ↔ %s." % [
				ctx.card.display_name, _short_slot(active_sid), _short_slot(bench_sid),
			]
		)
	TrainerEffectRegistry.register_def("switch_active", switch_def)

	## ── return_pokemon_to_hand — Mr. Briney's Compassion ─────────────────
	## PROMPT lists own Pokémon (excluding Pokémon-ex by card_id heuristic);
	## APPLY clears the slot and routes every contained card back into the
	## player's hand.  Empty active slots are filled by the manager's
	## promotion check (re-run by TrainerResolver after pipeline_completed).
	var briney_def := TrainerEffectDefinition.new()
	briney_def.phase_handlers[TrainerResolver.Phase.VALIDATE] = func(ctx: TrainerContext) -> void:
		if _own_pokemon_slots_no_ex(ctx).is_empty():
			ctx.fail_validation("No eligible Pokémon to return.")
	briney_def.phase_handlers[TrainerResolver.Phase.PROMPT] = func(ctx: TrainerContext) -> TrainerQuery:
		var q := TrainerQuery.new()
		q.kind = TrainerQuery.Kind.CHOOSE_OWN_POKEMON
		q.player_id = ctx.player_id
		q.prompt = "Return which Pokémon to your hand?"
		var arr: Array = []
		for s in _own_pokemon_slots_no_ex(ctx):
			arr.append(s)
		q.options = arr
		return q
	briney_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if sid == "":
			ctx.manager.log_message.emit("[Trainer] %s — cancelled." % ctx.card.display_name)
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null:
			return
		var name: String = inst.card.display_name
		var attached_count: int = inst.attached_energy.size() + inst.attached_tools.size()
		var stage_count: int = inst.prior_stages.size()
		ctx.manager.board_position.clear(sid)
		var contained: Array[CardData] = inst.release_cards()
		for c: CardData in contained:
			if c != null:
				ctx.manager.game_position.put_in_hand(ctx.player_id, c)
		inst.queue_free()
		ctx.manager.log_message.emit(
			"[Trainer] %s — returned %s (+%d attached, +%d prior stage%s) to hand." % [
				ctx.card.display_name, name, attached_count,
				stage_count, "" if stage_count == 1 else "s",
			]
		)
	TrainerEffectRegistry.register_def("return_pokemon_to_hand", briney_def)

	## ── gust_opponent_with_flip — Pokémon Reversal ───────────────────────
	## Player flips a coin in PROMPT.  On heads, opens the opponent-bench
	## picker and APPLY swaps that bench Pokémon with the opponent's first
	## occupied active.  On tails, APPLY no-ops.
	##
	## Card text says "your opponent switches" — in solo play we let the
	## active player pick the opponent's bench, since there is no AI yet.
	var reversal_def := TrainerEffectDefinition.new()
	reversal_def.phase_handlers[TrainerResolver.Phase.PROMPT] = func(ctx: TrainerContext) -> TrainerQuery:
		var heads: bool = ctx.manager.flip_coin(ctx.card.display_name)
		ctx.manager.log_message.emit(
			"[Coin] %s — %s" % [ctx.card.display_name, "Heads" if heads else "Tails"]
		)
		ctx.runtime["heads"] = heads
		if not heads:
			return null
		var opp_id: int = 1 - ctx.player_id
		var opts: Array = []
		for s in BoardPosition.BENCH_SLOTS:
			var sid: String = "p%d_%s" % [opp_id, s]
			if ctx.manager.board_position.get_instance(sid) != null:
				opts.append(sid)
		if opts.is_empty():
			ctx.runtime["no_bench"] = true
			return null
		var q := TrainerQuery.new()
		q.kind = TrainerQuery.Kind.CHOOSE_OPPONENT_BENCH
		q.player_id = ctx.player_id
		q.prompt = "Pokémon Reversal — choose opponent bench Pokémon to switch in"
		q.options = opts
		return q
	reversal_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		if not ctx.runtime.get("heads", false):
			ctx.manager.log_message.emit(
				"[Trainer] %s — tails, no effect." % ctx.card.display_name
			)
			return
		if ctx.runtime.get("no_bench", false):
			ctx.manager.log_message.emit(
				"[Trainer] %s — opponent has no bench Pokémon." % ctx.card.display_name
			)
			return
		var bench_sid: String = str(ctx.query_response) if ctx.query_response != null else ""
		if bench_sid == "":
			ctx.manager.log_message.emit("[Trainer] %s — cancelled." % ctx.card.display_name)
			return
		var opp_id: int = 1 - ctx.player_id
		var opp_active_sid: String = ""
		for s in BoardPosition.ACTIVE_SLOTS:
			var sid: String = "p%d_%s" % [opp_id, s]
			if ctx.manager.board_position.get_instance(sid) != null:
				opp_active_sid = sid
				break
		if opp_active_sid == "":
			return
		ctx.manager.board_position.swap(opp_active_sid, bench_sid)
		ctx.manager.log_message.emit(
			"[Trainer] %s — swapped opponent %s ↔ %s." % [
				ctx.card.display_name, _short_slot(opp_active_sid), _short_slot(bench_sid),
			]
		)
	TrainerEffectRegistry.register_def("gust_opponent_with_flip", reversal_def)

	## ── draw_then_discard — TV Reporter ──────────────────────────────────
	## Params: {"draw": 3, "discard": 1}
	## PROMPT draws first (so the discard picker sees the new hand) and
	## returns a hand-card picker constrained to discard count.  APPLY
	## moves chosen cards from hand → discard.
	var reporter_def := TrainerEffectDefinition.new()
	reporter_def.phase_handlers[TrainerResolver.Phase.PROMPT] = func(ctx: TrainerContext) -> TrainerQuery:
		var draw_count: int = int(ctx.params.get("draw", 3))
		var discard_count: int = int(ctx.params.get("discard", 1))
		var pid: int = ctx.player_id
		var gp: GamePosition = ctx.manager.game_position
		var actually_drawn: int = 0
		for _i in range(draw_count):
			if gp.deck_size(pid) <= 0:
				break
			gp.draw(pid)
			actually_drawn += 1
		ctx.manager.log_message.emit(
			"[Trainer] %s — drew %d card%s." % [
				ctx.card.display_name, actually_drawn, "" if actually_drawn == 1 else "s",
			]
		)
		var actual_discard: int = mini(discard_count, gp.hand_size(pid))
		if actual_discard <= 0:
			return null
		var q := TrainerQuery.new()
		q.kind = TrainerQuery.Kind.CHOOSE_FROM_HAND
		q.player_id = pid
		q.prompt = "Discard %d card%s from your hand" % [
			actual_discard, "" if actual_discard == 1 else "s",
		]
		q.min_selections = actual_discard
		q.max_selections = actual_discard
		q.options = (gp.hands[pid] as Array).duplicate()
		return q
	reporter_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var resp: Variant = ctx.query_response
		if resp == null or not (resp is Array):
			return
		var pid: int = ctx.player_id
		var discarded: int = 0
		for c_variant in resp as Array:
			var c: CardData = c_variant as CardData
			if c == null:
				continue
			if (ctx.manager.game_position.hands[pid] as Array).has(c):
				ctx.manager.game_position.take_from_hand(pid, c)
				ctx.manager.game_position.put_in_discard(pid, c)
				discarded += 1
		ctx.manager.log_message.emit(
			"[Trainer] %s — discarded %d card%s." % [
				ctx.card.display_name, discarded, "" if discarded == 1 else "s",
			]
		)
	TrainerEffectRegistry.register_def("draw_then_discard", reporter_def)

	## ── move_basic_energy_between_own — Energy Switch ────────────────────
	## Async APPLY: pick source own Pokémon, pick basic energy on it,
	## pick destination own Pokémon, move the energy.
	var energy_switch_def := TrainerEffectDefinition.new()
	energy_switch_def.phase_handlers[TrainerResolver.Phase.VALIDATE] = func(ctx: TrainerContext) -> void:
		if _own_pokemon_with_basic_energy(ctx).is_empty():
			ctx.fail_validation("No Pokémon with basic energy attached.")
		if _all_own_slots(ctx).size() < 2:
			ctx.fail_validation("Need at least two of your Pokémon in play.")
	energy_switch_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var resolver = ctx.manager.trainer_resolver
		var src_q := TrainerQuery.new()
		src_q.kind = TrainerQuery.Kind.CHOOSE_OWN_POKEMON
		src_q.player_id = ctx.player_id
		src_q.prompt = "Energy Switch — choose source Pokémon"
		var src_arr: Array = []
		for s in _own_pokemon_with_basic_energy(ctx):
			src_arr.append(s)
		src_q.options = src_arr
		var src_sid: String = str(await resolver.ask(src_q))
		if src_sid == "":
			ctx.manager.log_message.emit("[Trainer] Energy Switch — cancelled.")
			return
		var src_inst: PokemonInstance = ctx.manager.board_position.get_instance(src_sid)
		if src_inst == null:
			return
		var basics: Array[CardData] = []
		for e in src_inst.attached_energy:
			if _is_basic_energy(e):
				basics.append(e)
		if basics.is_empty():
			return
		var energy_q := TrainerQuery.new()
		energy_q.kind = TrainerQuery.Kind.CHOOSE_ENERGY_ON_POKEMON
		energy_q.player_id = ctx.player_id
		energy_q.prompt = "Energy Switch — choose energy to move"
		var energy_arr: Array = []
		for e in basics:
			energy_arr.append(e)
		energy_q.options = energy_arr
		var chosen_variant: Variant = await resolver.ask(energy_q)
		var chosen: CardData = chosen_variant as CardData
		if chosen == null:
			ctx.manager.log_message.emit("[Trainer] Energy Switch — cancelled.")
			return
		var dest_q := TrainerQuery.new()
		dest_q.kind = TrainerQuery.Kind.CHOOSE_OWN_POKEMON
		dest_q.player_id = ctx.player_id
		dest_q.prompt = "Energy Switch — choose destination Pokémon"
		var dest_arr: Array = []
		for s in _all_own_slots(ctx):
			if s != src_sid:
				dest_arr.append(s)
		dest_q.options = dest_arr
		var dest_sid: String = str(await resolver.ask(dest_q))
		if dest_sid == "":
			ctx.manager.log_message.emit("[Trainer] Energy Switch — cancelled.")
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
			"[Trainer] Energy Switch — moved %s from %s to %s." % [
				chosen.display_name, _short_slot(src_sid), _short_slot(dest_sid),
			]
		)
	TrainerEffectRegistry.register_def("move_basic_energy_between_own", energy_switch_def)

	## ── coin_discard_defender_energy — Energy Removal 2 ──────────────────
	## Flip coin; on heads, async APPLY picks an opponent Pokémon with energy,
	## then picks an energy on it, then discards.
	var energy_removal_def := TrainerEffectDefinition.new()
	energy_removal_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var heads: bool = await _flip_coin_awaited(ctx)
		ctx.manager.log_message.emit(
			"[Coin] %s — %s" % [ctx.card.display_name, "Heads" if heads else "Tails"]
		)
		if not heads:
			return
		var resolver = ctx.manager.trainer_resolver
		var opp_id: int = 1 - ctx.player_id
		var targets: Array[String] = _opponent_pokemon_with_energy(ctx, opp_id)
		if targets.is_empty():
			ctx.manager.log_message.emit(
				"[Trainer] %s — opponent has no energy attached." % ctx.card.display_name
			)
			return
		var tgt_q := TrainerQuery.new()
		tgt_q.kind = TrainerQuery.Kind.CHOOSE_OPPONENT_POKEMON
		tgt_q.player_id = ctx.player_id
		tgt_q.prompt = "Energy Removal 2 — choose opponent Pokémon"
		var tgt_arr: Array = []
		for s in targets:
			tgt_arr.append(s)
		tgt_q.options = tgt_arr
		var tgt_sid: String = str(await resolver.ask(tgt_q))
		if tgt_sid == "":
			return
		var tgt_inst: PokemonInstance = ctx.manager.board_position.get_instance(tgt_sid)
		if tgt_inst == null or tgt_inst.attached_energy.is_empty():
			return
		var energy_q := TrainerQuery.new()
		energy_q.kind = TrainerQuery.Kind.CHOOSE_ENERGY_ON_POKEMON
		energy_q.player_id = ctx.player_id
		energy_q.prompt = "Energy Removal 2 — choose energy to discard"
		var energy_arr: Array = []
		for e in tgt_inst.attached_energy:
			energy_arr.append(e)
		energy_q.options = energy_arr
		var chosen_variant: Variant = await resolver.ask(energy_q)
		var chosen: CardData = chosen_variant as CardData
		if chosen == null:
			return
		tgt_inst.attached_energy.erase(chosen)
		tgt_inst.refresh_visual()
		ctx.manager.pokemon_state_changed.emit(tgt_sid, tgt_inst)
		ctx.manager.game_position.put_in_discard(opp_id, chosen)
		ctx.manager.log_message.emit(
			"[Trainer] %s — discarded %s from opponent's %s." % [
				ctx.card.display_name, chosen.display_name, _short_slot(tgt_sid),
			]
		)
	TrainerEffectRegistry.register_def("coin_discard_defender_energy", energy_removal_def)

	## ── search_deck_basic_energy — Energy Search ─────────────────────────
	## Search deck for any 1 basic energy, reveal, put in hand, shuffle.
	TrainerEffectRegistry.register_def("search_deck_basic_energy", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			await _search_deck_into_hand(ctx, _is_basic_energy_callable(),
					int(ctx.params.get("count", 1)),
					"Search your deck for a basic Energy")
	))

	## ── search_deck_basic_pokemon — Lanette's Net Search ─────────────────
	## Search deck for any 1 basic Pokémon, reveal, put in hand, shuffle.
	TrainerEffectRegistry.register_def("search_deck_basic_pokemon", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			await _search_deck_into_hand(ctx, _is_basic_pokemon_callable(),
					int(ctx.params.get("count", 1)),
					"Search your deck for a Basic Pokémon")
	))

	## ── search_deck_basic_energy_multi — Lady Outing ─────────────────────
	## Search deck for up to 3 basic Energy.  (We don't enforce the
	## "different types" rule — players are trusted to play fairly.)
	TrainerEffectRegistry.register_def("search_deck_basic_energy_multi", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var max_pick: int = int(ctx.params.get("max", 3))
			await _search_deck_into_hand_range(ctx, _is_basic_energy_callable(),
					0, max_pick,
					"Search your deck for up to %d basic Energy" % max_pick)
	))

	## ── search_deck_basic_pokemon_multi — Lanette's Net Search ───────────
	## Search deck for up to 3 basic Pokémon.  (Different-types rule not
	## enforced; players are trusted.)
	TrainerEffectRegistry.register_def("search_deck_basic_pokemon_multi", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var max_pick: int = int(ctx.params.get("max", 3))
			await _search_deck_into_hand_range(ctx, _is_basic_pokemon_callable(),
					0, max_pick,
					"Search your deck for up to %d Basic Pokémon" % max_pick)
	))

	## ── coin_search_deck_pokemon — Pokéball ──────────────────────────────
	## Flip coin; on heads, search deck for any 1 Pokémon (any stage).
	TrainerEffectRegistry.register_def("coin_search_deck_pokemon", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var heads: bool = await _flip_coin_awaited(ctx)
			ctx.manager.log_message.emit(
				"[Coin] %s — %s" % [ctx.card.display_name, "Heads" if heads else "Tails"]
			)
			if not heads:
				return
			await _search_deck_into_hand(ctx, _is_pokemon_callable(), 1,
					"Search your deck for any 1 Pokémon")
	))

	## ── recover_basic_energy_from_discard — Energy Restore ───────────────
	## Flip N coins (default 3).  For each heads, recover 1 basic energy
	## from discard.  Capped at how many basic energies are actually there.
	TrainerEffectRegistry.register_def("recover_basic_energy_from_discard", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var n: int = int(ctx.params.get("flips", 3))
			var flips: Array[bool] = await _flip_coins_batch_awaited(ctx, n)
			var heads: int = 0
			for h in flips:
				if h: heads += 1
			ctx.manager.log_message.emit(
				"[Coin] %s — %d heads of %d." % [ctx.card.display_name, heads, n]
			)
			if heads <= 0:
				return
			await _recover_from_discard_to_hand(ctx, _is_basic_energy_callable(),
					heads, heads, "Choose %d basic Energy from discard" % heads)
	))

	## ── energy_recycle_choice — Energy Recycle System ────────────────────
	## Two-mode: 1 basic energy from discard → hand, OR 3 basic energies →
	## shuffle into deck.  Asks the player which mode first.
	var recycle_def := TrainerEffectDefinition.new()
	recycle_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var basics_in_discard: Array[CardData] = _basic_energies_in_discard(ctx)
		if basics_in_discard.is_empty():
			ctx.manager.log_message.emit(
				"[Trainer] %s — no basic Energy in discard." % ctx.card.display_name
			)
			return
		var resolver = ctx.manager.trainer_resolver
		## Mode prompt rendered via the generic list-picker: two
		## "fake" placeholder cards are confusing — instead we offer the
		## player both options as simple buttons via a generic-choice query.
		var mode_q := TrainerQuery.new()
		mode_q.kind = TrainerQuery.Kind.GENERIC_CHOICE
		mode_q.player_id = ctx.player_id
		mode_q.prompt = "Energy Recycle System — pick a mode"
		mode_q.options = ["1 to hand", "3 to deck"]
		var mode_resp: Variant = await resolver.ask(mode_q)
		var mode: String = str(mode_resp) if mode_resp != null else ""
		if mode == "":
			return
		if mode == "1 to hand":
			await _recover_from_discard_to_hand(ctx, _is_basic_energy_callable(),
					1, 1, "Choose 1 basic Energy to put in hand")
		else:
			await _recover_from_discard_to_deck(ctx, _is_basic_energy_callable(),
					mini(3, basics_in_discard.size()),
					mini(3, basics_in_discard.size()),
					"Choose 3 basic Energy to shuffle into deck")
	TrainerEffectRegistry.register_def("energy_recycle_choice", recycle_def)

	## ── peek_top_n_pick_one_reorder — PokéNav ────────────────────────────
	## Look at the top N cards of deck; pick 1 to put into hand; reorder
	## the remaining N-1 back on top.
	TrainerEffectRegistry.register_def("peek_top_n_pick_one_reorder", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var n: int = int(ctx.params.get("n", 3))
			var pid: int = ctx.player_id
			var gp: GamePosition = ctx.manager.game_position
			var deck: Array = gp.decks[pid]
			var available: int = mini(n, deck.size())
			if available <= 0:
				ctx.manager.log_message.emit(
					"[Trainer] %s — deck is empty." % ctx.card.display_name
				)
				return
			## "Top of deck" = back of array.  Build top-cards in draw order.
			var top_cards: Array[CardData] = []
			for i in range(available):
				top_cards.append(deck[deck.size() - 1 - i] as CardData)
			## Step 1: pick 1 to put in hand.
			var pick_q := TrainerQuery.new()
			pick_q.kind = TrainerQuery.Kind.CHOOSE_FROM_LIST
			pick_q.player_id = pid
			pick_q.prompt = "PokéNav — choose 1 card to put in hand"
			pick_q.min_selections = 0
			pick_q.max_selections = 1
			var pick_arr: Array = []
			for c in top_cards: pick_arr.append(c)
			pick_q.options = pick_arr
			var pick_resp: Variant = await ctx.manager.trainer_resolver.ask(pick_q)
			var picked: CardData = null
			if pick_resp is Array and not (pick_resp as Array).is_empty():
				picked = (pick_resp as Array)[0] as CardData
			## Remove the top [available] cards from the deck.
			for _i in range(available):
				deck.pop_back()
			if picked != null:
				gp.put_in_hand(pid, picked)
				top_cards.erase(picked)
			## Step 2: reorder remaining cards (if any) back on top.
			if not top_cards.is_empty():
				if top_cards.size() == 1:
					deck.append(top_cards[0])
				else:
					var reorder_q := TrainerQuery.new()
					reorder_q.kind = TrainerQuery.Kind.REORDER_TOP_OF_DECK
					reorder_q.player_id = pid
					reorder_q.prompt = "PokéNav — set draw order for remaining cards"
					var ro_arr: Array = []
					for c in top_cards: ro_arr.append(c)
					reorder_q.options = ro_arr
					var ro_resp: Variant = await ctx.manager.trainer_resolver.ask(reorder_q)
					var ordered: Array = ro_resp if ro_resp is Array else ro_arr
					if ordered.size() != top_cards.size():
						ordered = ro_arr
					## First card in ordered list is drawn first → push last.
					for i in range(ordered.size() - 1, -1, -1):
						deck.append(ordered[i])
			gp.deck_changed.emit(pid)
			ctx.manager.log_message.emit(
				"[Trainer] %s — looked at top %d, took %s." % [
					ctx.card.display_name, available,
					"1 card" if picked != null else "none",
				]
			)
	))

	## ── rare_candy_evolve — Rare Candy ───────────────────────────────────
	## Pick a Basic Pokémon in play; pick a Stage 1 or Stage 2 in your hand
	## that evolves from it (Stage 2 may skip Stage 1 — that is the whole
	## point of Rare Candy).  Evolves directly.
	var rare_candy_def := TrainerEffectDefinition.new()
	rare_candy_def.phase_handlers[TrainerResolver.Phase.VALIDATE] = func(ctx: TrainerContext) -> void:
		if _rare_candy_eligible_slots(ctx).is_empty():
			ctx.fail_validation("No Basic Pokémon with an evolution in your hand.")
	rare_candy_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var resolver = ctx.manager.trainer_resolver
		var slot_q := TrainerQuery.new()
		slot_q.kind = TrainerQuery.Kind.CHOOSE_OWN_POKEMON
		slot_q.player_id = ctx.player_id
		slot_q.prompt = "Rare Candy — choose a Basic Pokémon"
		var slot_arr: Array = []
		for s in _rare_candy_eligible_slots(ctx):
			slot_arr.append(s)
		slot_q.options = slot_arr
		var sid: String = str(await resolver.ask(slot_q))
		if sid == "":
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			return
		var evos: Array[PokemonCardData] = _evolution_cards_in_hand_for(ctx, inst.card)
		if evos.is_empty():
			return
		var hand_q := TrainerQuery.new()
		hand_q.kind = TrainerQuery.Kind.CHOOSE_FROM_HAND
		hand_q.player_id = ctx.player_id
		hand_q.prompt = "Rare Candy — choose evolution to play"
		hand_q.min_selections = 1
		hand_q.max_selections = 1
		var evo_arr: Array = []
		for e in evos: evo_arr.append(e)
		hand_q.options = evo_arr
		var resp: Variant = await resolver.ask(hand_q)
		if not (resp is Array) or (resp as Array).is_empty():
			return
		var evo: PokemonCardData = (resp as Array)[0] as PokemonCardData
		if evo == null:
			return
		ctx.manager.game_position.take_from_hand(ctx.player_id, evo)
		inst.evolve_to(evo)
		inst.special_conditions.clear()
		inst.refresh_visual()
		(ctx.manager.pokemon_entered_play_this_turn[ctx.player_id] as Array).append(inst)
		ctx.manager.pokemon_state_changed.emit(sid, inst)
		ctx.manager.log_message.emit(
			"[Trainer] %s — evolved %s into %s." % [
				ctx.card.display_name, _short_slot(sid), evo.display_name,
			]
		)
	TrainerEffectRegistry.register_def("rare_candy_evolve", rare_candy_def)

	## ── search_deck_evolution_and_evolve — Wally's Training ──────────────
	## Search deck for a Stage 1 / Stage 2 evolution that evolves a Pokémon
	## already in play; play it onto that Pokémon.
	var wally_def := TrainerEffectDefinition.new()
	wally_def.phase_handlers[TrainerResolver.Phase.VALIDATE] = func(ctx: TrainerContext) -> void:
		if _wally_eligible_pairs(ctx).is_empty():
			ctx.fail_validation("No matching evolution in your deck.")
	wally_def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		var resolver = ctx.manager.trainer_resolver
		var pairs: Array = _wally_eligible_pairs(ctx)
		var slot_q := TrainerQuery.new()
		slot_q.kind = TrainerQuery.Kind.CHOOSE_OWN_POKEMON
		slot_q.player_id = ctx.player_id
		slot_q.prompt = "Wally's Training — choose Pokémon to evolve"
		var slot_options: Array = []
		var seen_slots: Dictionary = {}
		for p in pairs:
			var sid: String = p["slot"]
			if not seen_slots.has(sid):
				seen_slots[sid] = true
				slot_options.append(sid)
		slot_q.options = slot_options
		var sid: String = str(await resolver.ask(slot_q))
		if sid == "":
			return
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			return
		var deck_options: Array = []
		for c in ctx.manager.game_position.decks[ctx.player_id]:
			if c is PokemonCardData and (c as PokemonCardData).evolves_from == inst.card.name_slug:
				deck_options.append(c)
		if deck_options.is_empty():
			return
		var search_q := TrainerQuery.new()
		search_q.kind = TrainerQuery.Kind.CHOOSE_FROM_LIST
		search_q.player_id = ctx.player_id
		search_q.prompt = "Wally's Training — choose evolution"
		search_q.min_selections = 0
		search_q.max_selections = 1
		search_q.options = deck_options
		var resp: Variant = await resolver.ask(search_q)
		if not (resp is Array) or (resp as Array).is_empty():
			ctx.manager.game_position.shuffle_deck(ctx.player_id)
			return
		var evo: PokemonCardData = (resp as Array)[0] as PokemonCardData
		if evo == null:
			ctx.manager.game_position.shuffle_deck(ctx.player_id)
			return
		ctx.manager.game_position.take_from_deck(ctx.player_id, evo)
		inst.evolve_to(evo)
		inst.special_conditions.clear()
		inst.refresh_visual()
		(ctx.manager.pokemon_entered_play_this_turn[ctx.player_id] as Array).append(inst)
		ctx.manager.pokemon_state_changed.emit(sid, inst)
		ctx.manager.game_position.shuffle_deck(ctx.player_id)
		ctx.manager.log_message.emit(
			"[Trainer] %s — evolved %s into %s." % [
				ctx.card.display_name, _short_slot(sid), evo.display_name,
			]
		)
	TrainerEffectRegistry.register_def("search_deck_evolution_and_evolve", wally_def)

	## ── Stub for deferred cards (Tools, Fossils, Berries) ────────────────
	TrainerEffectRegistry.register_def("stub_not_implemented", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void:
			var name: String = ctx.card.display_name if ctx.card != null else "Trainer"
			ctx.manager.log_message.emit(
				"[Trainer] %s — effect not yet implemented." % name
			)
	))


## --- Slot helpers -----------------------------------------------------------

## Returns every slot id (active + bench) on [ctx.player_id]'s side that holds
## a Pokémon with current_hp < max_hp.
static func _own_damaged_slots(ctx: TrainerContext) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS:
		var sid: String = "p%d_%s" % [ctx.player_id, s]
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst != null and inst.current_hp < inst.max_hp:
			out.append(sid)
	return out


## Returns every occupied bench slot for [ctx.player_id].
static func _own_bench_slots(ctx: TrainerContext) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.BENCH_SLOTS:
		var sid: String = "p%d_%s" % [ctx.player_id, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			out.append(sid)
	return out


## Returns the first occupied active slot id for [ctx.player_id], or "".
static func _own_active_slot(ctx: TrainerContext) -> String:
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid: String = "p%d_%s" % [ctx.player_id, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			return sid
	return ""


## Returns every owned in-play slot id excluding Pokémon-ex (heuristic:
## card_id contains "_ex").  Used by Mr. Briney's Compassion.
static func _own_pokemon_slots_no_ex(ctx: TrainerContext) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS:
		var sid: String = "p%d_%s" % [ctx.player_id, s]
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			continue
		if inst.card.card_id.contains("_ex"):
			continue
		out.append(sid)
	return out


## Returns every owned in-play slot id (active + bench).
static func _all_own_slots(ctx: TrainerContext) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS:
		var sid: String = "p%d_%s" % [ctx.player_id, s]
		if ctx.manager.board_position.get_instance(sid) != null:
			out.append(sid)
	return out


## Owned slots whose Pokémon has at least one basic energy attached.
static func _own_pokemon_with_basic_energy(ctx: TrainerContext) -> Array[String]:
	var out: Array[String] = []
	for sid in _all_own_slots(ctx):
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		for e in inst.attached_energy:
			if _is_basic_energy(e):
				out.append(sid)
				break
	return out


## Opponent slots with at least one energy attached.
static func _opponent_pokemon_with_energy(ctx: TrainerContext, opp_id: int) -> Array[String]:
	var out: Array[String] = []
	for s in BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS:
		var sid: String = "p%d_%s" % [opp_id, s]
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst != null and not inst.attached_energy.is_empty():
			out.append(sid)
	return out


## Card-shape predicates.
static func _is_basic_energy(card: CardData) -> bool:
	if not (card is EnergyCardData):
		return false
	## Special energies (Rainbow, Multi) are excluded by id substring.
	var cid: String = card.card_id.to_lower()
	if cid.contains("rainbow") or cid.contains("multi"):
		return false
	return true


static func _is_basic_pokemon(card: CardData) -> bool:
	return card is PokemonCardData \
		and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC


static func _is_pokemon(card: CardData) -> bool:
	return card is PokemonCardData


static func _is_basic_energy_callable() -> Callable:
	return func(c: CardData) -> bool: return _is_basic_energy(c)


static func _is_basic_pokemon_callable() -> Callable:
	return func(c: CardData) -> bool: return _is_basic_pokemon(c)


static func _is_pokemon_callable() -> Callable:
	return func(c: CardData) -> bool: return _is_pokemon(c)


## Common deck-search helper: find cards matching [predicate] in the player's
## deck, prompt the player to pick exactly [count], move the picks to hand,
## then shuffle the deck.  Always shuffles even if the search whiffed.
static func _search_deck_into_hand(ctx: TrainerContext, predicate: Callable,
		count: int, prompt: String) -> void:
	await _search_deck_into_hand_range(ctx, predicate, count, count, prompt)


## Range variant: pick 0..max from the matching candidates.
static func _search_deck_into_hand_range(ctx: TrainerContext, predicate: Callable,
		min_count: int, max_count: int, prompt: String) -> void:
	var pid: int = ctx.player_id
	var gp: GamePosition = ctx.manager.game_position
	var candidates: Array[CardData] = []
	for c in gp.decks[pid]:
		if predicate.call(c):
			candidates.append(c)
	if candidates.is_empty():
		ctx.manager.log_message.emit(
			"[Trainer] %s — no matches in deck." % ctx.card.display_name
		)
		gp.shuffle_deck(pid)
		return
	var q := TrainerQuery.new()
	q.kind = TrainerQuery.Kind.CHOOSE_FROM_LIST
	q.player_id = pid
	q.prompt = prompt
	q.min_selections = min_count
	q.max_selections = max_count
	var arr: Array = []
	for c in candidates: arr.append(c)
	q.options = arr
	var resp: Variant = await ctx.manager.trainer_resolver.ask(q)
	if not (resp is Array):
		gp.shuffle_deck(pid)
		return
	var picks: Array = resp as Array
	for c_variant in picks:
		var c: CardData = c_variant as CardData
		if c == null: continue
		if gp.take_from_deck(pid, c):
			gp.put_in_hand(pid, c)
	gp.shuffle_deck(pid)
	ctx.manager.log_message.emit(
		"[Trainer] %s — added %d card%s to hand." % [
			ctx.card.display_name, picks.size(), "" if picks.size() == 1 else "s",
		]
	)


## Discard pile → hand recovery (Energy Restore, Energy Recycle hand mode).
static func _recover_from_discard_to_hand(ctx: TrainerContext, predicate: Callable,
		min_count: int, max_count: int, prompt: String) -> void:
	var pid: int = ctx.player_id
	var gp: GamePosition = ctx.manager.game_position
	var candidates: Array[CardData] = []
	for c in gp.discards[pid]:
		if predicate.call(c):
			candidates.append(c)
	if candidates.is_empty():
		return
	var q := TrainerQuery.new()
	q.kind = TrainerQuery.Kind.CHOOSE_FROM_LIST
	q.player_id = pid
	q.prompt = prompt
	q.min_selections = mini(min_count, candidates.size())
	q.max_selections = mini(max_count, candidates.size())
	var arr: Array = []
	for c in candidates: arr.append(c)
	q.options = arr
	var resp: Variant = await ctx.manager.trainer_resolver.ask(q)
	if not (resp is Array):
		return
	for c_variant in resp as Array:
		var c: CardData = c_variant as CardData
		if c == null: continue
		if gp.take_from_discard(pid, c):
			gp.put_in_hand(pid, c)
	ctx.manager.log_message.emit(
		"[Trainer] %s — recovered %d card%s." % [
			ctx.card.display_name, (resp as Array).size(),
			"" if (resp as Array).size() == 1 else "s",
		]
	)


## Discard pile → deck (Energy Recycle deck mode), then shuffle.
static func _recover_from_discard_to_deck(ctx: TrainerContext, predicate: Callable,
		min_count: int, max_count: int, prompt: String) -> void:
	var pid: int = ctx.player_id
	var gp: GamePosition = ctx.manager.game_position
	var candidates: Array[CardData] = []
	for c in gp.discards[pid]:
		if predicate.call(c):
			candidates.append(c)
	if candidates.is_empty():
		return
	var q := TrainerQuery.new()
	q.kind = TrainerQuery.Kind.CHOOSE_FROM_LIST
	q.player_id = pid
	q.prompt = prompt
	q.min_selections = mini(min_count, candidates.size())
	q.max_selections = mini(max_count, candidates.size())
	var arr: Array = []
	for c in candidates: arr.append(c)
	q.options = arr
	var resp: Variant = await ctx.manager.trainer_resolver.ask(q)
	if not (resp is Array):
		return
	for c_variant in resp as Array:
		var c: CardData = c_variant as CardData
		if c == null: continue
		if gp.take_from_discard(pid, c):
			gp.put_in_deck(pid, c)
	gp.shuffle_deck(pid)
	ctx.manager.log_message.emit(
		"[Trainer] %s — shuffled %d card%s into deck." % [
			ctx.card.display_name, (resp as Array).size(),
			"" if (resp as Array).size() == 1 else "s",
		]
	)


## Returns every basic energy in the player's discard.
static func _basic_energies_in_discard(ctx: TrainerContext) -> Array[CardData]:
	var out: Array[CardData] = []
	for c in ctx.manager.game_position.discards[ctx.player_id]:
		if _is_basic_energy(c):
			out.append(c)
	return out


## Slots that hold a Basic Pokémon AND have a Stage 1 or Stage 2 evolution
## (chained, for Stage 2) in the player's hand.  Used by Rare Candy.
static func _rare_candy_eligible_slots(ctx: TrainerContext) -> Array[String]:
	var pid: int = ctx.player_id
	var hand: Array = ctx.manager.game_position.hands[pid]
	var out: Array[String] = []
	for sid in _all_own_slots(ctx):
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			continue
		if inst.card.stage != PokemonCardData.Stage.BASIC:
			continue
		var slug: String = inst.card.name_slug
		var has_evo: bool = false
		## Stage 1 directly evolves from this Basic.
		for c in hand:
			if c is PokemonCardData and (c as PokemonCardData).evolves_from == slug:
				has_evo = true
				break
		## Stage 2 evolves from any Stage 1 that itself evolves from this Basic.
		if not has_evo:
			var stage1_slugs: Array[String] = []
			for c in ctx.manager.game_position.decks[pid] + hand + (ctx.manager.game_position.discards[pid] as Array):
				if c is PokemonCardData and (c as PokemonCardData).evolves_from == slug \
						and (c as PokemonCardData).stage == PokemonCardData.Stage.STAGE1:
					stage1_slugs.append((c as PokemonCardData).name_slug)
			for c in hand:
				if c is PokemonCardData \
						and (c as PokemonCardData).stage == PokemonCardData.Stage.STAGE2 \
						and stage1_slugs.has((c as PokemonCardData).evolves_from):
					has_evo = true
					break
		if has_evo:
			out.append(sid)
	return out


## Returns every Stage1/Stage2 PokemonCardData in the hand that can evolve
## the given basic Pokémon (directly for Stage 1, or via a Stage 1 in any
## of player's piles for Stage 2).
static func _evolution_cards_in_hand_for(ctx: TrainerContext, basic: PokemonCardData) -> Array[PokemonCardData]:
	var pid: int = ctx.player_id
	var hand: Array = ctx.manager.game_position.hands[pid]
	var out: Array[PokemonCardData] = []
	## Stage 1 direct.
	for c in hand:
		if c is PokemonCardData \
				and (c as PokemonCardData).evolves_from == basic.name_slug \
				and (c as PokemonCardData).stage == PokemonCardData.Stage.STAGE1:
			out.append(c)
	## Stage 2 via known Stage 1 slugs.
	var stage1_slugs: Array[String] = []
	for c in ctx.manager.game_position.decks[pid] + hand \
			+ (ctx.manager.game_position.discards[pid] as Array):
		if c is PokemonCardData \
				and (c as PokemonCardData).evolves_from == basic.name_slug \
				and (c as PokemonCardData).stage == PokemonCardData.Stage.STAGE1:
			stage1_slugs.append((c as PokemonCardData).name_slug)
	for c in hand:
		if c is PokemonCardData \
				and (c as PokemonCardData).stage == PokemonCardData.Stage.STAGE2 \
				and stage1_slugs.has((c as PokemonCardData).evolves_from):
			out.append(c)
	return out


## Returns [{slot, evo_card}, ...] of ACTIVE Pokémon paired with deck
## evolutions that match.  Used by Wally's Training (active-only rule).
static func _wally_eligible_pairs(ctx: TrainerContext) -> Array:
	var pid: int = ctx.player_id
	var deck: Array = ctx.manager.game_position.decks[pid]
	var out: Array = []
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid: String = "p%d_%s" % [pid, s]
		var inst: PokemonInstance = ctx.manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			continue
		var slug: String = inst.card.name_slug
		var stage_required: int = (
			PokemonCardData.Stage.STAGE1
			if inst.card.stage == PokemonCardData.Stage.BASIC
			else PokemonCardData.Stage.STAGE2
		)
		for c in deck:
			if c is PokemonCardData \
					and (c as PokemonCardData).evolves_from == slug \
					and (c as PokemonCardData).stage == stage_required:
				out.append({"slot": sid, "evo_card": c})
	return out


## Pretty short slot label for log lines.
static func _short_slot(slot_id: String) -> String:
	if slot_id.contains("active1"): return "Active 1"
	if slot_id.contains("active2"): return "Active 2"
	if slot_id.contains("bench1"):  return "Bench 1"
	if slot_id.contains("bench2"):  return "Bench 2"
	if slot_id.contains("bench3"):  return "Bench 3"
	if slot_id.contains("bench4"):  return "Bench 4"
	if slot_id.contains("bench5"):  return "Bench 5"
	return slot_id
