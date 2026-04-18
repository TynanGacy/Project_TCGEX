class_name TrainerEffects
## Static implementations of all Trainer-card effects.
##
## Each function receives a CardEffectContext where:
##   ctx.state    — current GameState
##   ctx.actor_id — player who played the card
##   ctx.card     — the CardInstance that was played (already in discard for
##                  Items/Supporters; in the stadium zone for Stadiums; still
##                  attached for Tools)
##
## Called once from CardEffectRegistry.setup() to register everything.


static func register_all() -> void:
	# ---- Items ---------------------------------------------------------------
	CardEffectRegistry.register_item("RS_80_energy_removal_2", _energy_removal_2)
	CardEffectRegistry.register_item("RS_81_energy_restore",   _energy_restore)
	CardEffectRegistry.register_item("RS_82_energy_switch",    _energy_switch)
	CardEffectRegistry.register_item("RS_86_pok_ball",         _poke_ball)
	CardEffectRegistry.register_item("RS_87_pok_mon_reversal", _pokemon_reversal)
	CardEffectRegistry.register_item("RS_88_pok_nav",          _pokenav)
	CardEffectRegistry.register_item("RS_90_energy_search",    _energy_search)
	CardEffectRegistry.register_item("RS_91_potion",           _potion)
	CardEffectRegistry.register_item("RS_92_switch",           _switch)

	CardEffectRegistry.register_item("SS_86_double_full_heal", _double_full_heal)
	CardEffectRegistry.register_item("SS_88_rare_candy",       _rare_candy)
	CardEffectRegistry.register_item("SS_90_claw_fossil",      _play_as_fossil)
	CardEffectRegistry.register_item("SS_91_mysterious_fossil",_play_as_fossil)
	CardEffectRegistry.register_item("SS_92_root_fossil",      _play_as_fossil)

	# ---- Supporters ----------------------------------------------------------
	CardEffectRegistry.register_supporter("RS_83_lady_outing",           _lady_outing)
	CardEffectRegistry.register_supporter("RS_89_professor_birch",       _professor_birch)
	CardEffectRegistry.register_supporter("SS_87_lanette_s_net_search",  _lanette_net_search)
	CardEffectRegistry.register_supporter("SS_89_wally_s_training",      _wally_training)
	CardEffectRegistry.register_supporter("DR_88_tv_reporter",           _tv_reporter)
	CardEffectRegistry.register_supporter("DR_87_mr_briney_s_compassion",_mr_briney)

	# ---- Tool between-turns triggers -----------------------------------------
	CardEffectRegistry.register_tool_between_turns("RS_84_lum_berry",  _lum_berry_tick)
	CardEffectRegistry.register_tool_between_turns("RS_85_oran_berry", _oran_berry_tick)
	# Balloon Berry and Buffer Piece are handled in AttackResolver / action_retreat
	# (no between-turns trigger needed for those).


# =============================================================================
# ITEMS
# =============================================================================

## RS_80: Flip a coin. If heads, discard 1 Energy from an opponent's Pokémon.
static func _energy_removal_2(ctx: CardEffectContext) -> void:
	var results := TurnControllerSingleton.flip_coins(1, "Energy Removal 2")
	if not results[0]:  # tails — no effect
		return
	var opp_id := 1 - ctx.actor_id
	# Auto-target: opponent's Active Pokémon first, then bench.
	var targets := ctx.state.get_all_in_play(opp_id)
	for target in targets:
		if not target.attached_energy.is_empty():
			var energy := target.attached_energy[0] as CardInstance
			target.attached_energy.erase(energy)
			ctx.state.board.move_card(energy, "p%d_discard" % opp_id)
			break


## RS_81: Flip 3 coins. For each heads, retrieve one Basic Energy from discard.
static func _energy_restore(ctx: CardEffectContext) -> void:
	var flip_results := TurnControllerSingleton.flip_coins(3, "Energy Restore")
	var heads := flip_results.count(true)
	if heads == 0:
		return

	var discard := ctx.state.board.get_zone("p%d_discard" % ctx.actor_id).duplicate()
	var basic_energy: Array = []
	for card in discard:
		if card is CardInstance and (card as CardInstance).data is EnergyCardData:
			var edata := (card as CardInstance).data as EnergyCardData
			if _is_basic_energy(edata.energy_type):
				basic_energy.append(card)

	if basic_energy.is_empty():
		return

	var actor_id := ctx.actor_id
	var state := ctx.state
	TurnControllerSingleton.request_card_search(
		basic_energy,
		heads,
		"Energy Restore: Choose up to %d Basic Energy from your discard" % heads,
		func(chosen: Array) -> void:
			for card in chosen:
				state.board.move_card(card, "p%d_hand" % actor_id)
	)


## RS_82: Move one Basic Energy from one of your Pokémon to another.
## Auto-select: move the first basic energy from a benched Pokémon to the Active.
static func _energy_switch(ctx: CardEffectContext) -> void:
	var actor_id := ctx.actor_id
	var active := ctx.state.board.get_active_card(actor_id, 0)
	if active == null:
		return
	for bench in ctx.state.board.get_bench_cards(actor_id):
		for energy in bench.attached_energy.duplicate():
			if energy.data is EnergyCardData \
					and _is_basic_energy((energy.data as EnergyCardData).energy_type):
				bench.attached_energy.erase(energy)
				active.attached_energy.append(energy)
				return


## RS_86: Flip a coin. If heads, search deck for any Pokémon card.
static func _poke_ball(ctx: CardEffectContext) -> void:
	var results := TurnControllerSingleton.flip_coins(1, "Poké Ball")
	if not results[0]:  # tails
		return
	var deck := ctx.state.board.get_zone("p%d_deck" % ctx.actor_id).duplicate()
	var pokemon_cards: Array = []
	for card in deck:
		if card is CardInstance and (card as CardInstance).data is PokemonCardData:
			pokemon_cards.append(card)
	if pokemon_cards.is_empty():
		return
	var actor_id := ctx.actor_id
	var state := ctx.state
	TurnControllerSingleton.request_card_search(
		pokemon_cards,
		1,
		"Poké Ball: Search your deck for a Pokémon",
		func(chosen: Array) -> void:
			for card in chosen:
				state.board.move_card(card, "p%d_hand" % actor_id)
			var p := state.get_player(actor_id)
			if p: p.shuffle_deck_zone(state.board)
	)


## RS_87: Flip a coin. If heads, opponent switches their Active with a Bench Pokémon.
static func _pokemon_reversal(ctx: CardEffectContext) -> void:
	var results := TurnControllerSingleton.flip_coins(1, "Pokémon Reversal")
	if not results[0]:  # tails
		return
	var opp_id := 1 - ctx.actor_id
	var bench := ctx.state.board.get_bench_cards(opp_id)
	if bench.is_empty():
		return
	var active := ctx.state.board.get_active_card(opp_id, 0)
	if active == null:
		return
	if bench.size() == 1:
		ctx.state.board.swap_cards(active, bench[0])
		return
	var choices: Array = []
	for b in bench:
		choices.append(b)
	TurnControllerSingleton.request_effect_choice(
		"Choose a Benched Pokemon to switch into Active.",
		opp_id,
		choices,
		func(chosen: Array) -> void:
			if chosen.is_empty():
				return
			var selected := chosen[0] as CardInstance
			var current_active := ctx.state.board.get_active_card(opp_id, 0)
			if current_active == null:
				return
			if ctx.state.board.find_card_location(selected) == "p%d_bench" % opp_id:
				ctx.state.board.swap_cards(current_active, selected)
	)


## RS_88: Look at top 3 cards; take 1 Pokémon/Evolution/Energy, return the rest.
static func _pokenav(ctx: CardEffectContext) -> void:
	var deck_zone := "p%d_deck" % ctx.actor_id
	var deck := ctx.state.board.get_zone(deck_zone)
	if deck.is_empty():
		return
	var look_n := mini(3, deck.size())
	# Top of deck = end of array (same convention as Player.draw_card).
	var top: Array[CardInstance] = []
	for i in look_n:
		top.append(deck[deck.size() - 1 - i] as CardInstance)

	# Take the first Pokémon or Energy card found.
	for card in top:
		if (card.data is PokemonCardData) or (card.data is EnergyCardData):
			ctx.state.board.move_card(card, "p%d_hand" % ctx.actor_id)
			return
	# No Pokémon/Energy in top 3 — take the top card anyway (rules allow this).
	if not top.is_empty():
		ctx.state.board.move_card(top[0], "p%d_hand" % ctx.actor_id)


## RS_90: Search deck for 1 Basic Energy card, put in hand.
static func _energy_search(ctx: CardEffectContext) -> void:
	var deck := ctx.state.board.get_zone("p%d_deck" % ctx.actor_id).duplicate()
	var basic_energy: Array = []
	for card in deck:
		if card is CardInstance and (card as CardInstance).data is EnergyCardData:
			if _is_basic_energy((card as CardInstance).data.energy_type):
				basic_energy.append(card)
	if basic_energy.is_empty():
		return
	var actor_id := ctx.actor_id
	var state := ctx.state
	TurnControllerSingleton.request_card_search(
		basic_energy,
		1,
		"Energy Search: Choose a Basic Energy from your deck",
		func(chosen: Array) -> void:
			for card in chosen:
				state.board.move_card(card, "p%d_hand" % actor_id)
			var p := state.get_player(actor_id)
			if p: p.shuffle_deck_zone(state.board)
	)


## RS_91: Remove 2 damage counters (20 HP) from one of your Pokémon.
## Auto-select: most damaged Pokémon.
static func _potion(ctx: CardEffectContext) -> void:
	var best: CardInstance = null
	for pokemon in ctx.state.get_all_in_play(ctx.actor_id):
		if best == null or pokemon.damage > best.damage:
			best = pokemon
	if best != null and best.damage > 0:
		best.heal(20)


## RS_92: Switch your Active Pokémon with one of your Bench Pokémon.
static func _switch(ctx: CardEffectContext) -> void:
	var actor_id := ctx.actor_id
	var active := ctx.state.board.get_active_card(actor_id, 0)
	if active == null:
		return
	var bench := ctx.state.board.get_bench_cards(actor_id)
	if bench.is_empty():
		return
	if bench.size() == 1:
		ctx.state.board.swap_cards(active, bench[0])
		return
	var choices: Array = []
	for b in bench:
		choices.append(b)
	TurnControllerSingleton.request_effect_choice(
		"Choose a Benched Pokemon to switch into Active.",
		actor_id,
		choices,
		func(chosen: Array) -> void:
			if chosen.is_empty():
				return
			var selected := chosen[0] as CardInstance
			var current_active := ctx.state.board.get_active_card(actor_id, 0)
			if current_active == null:
				return
			if ctx.state.board.find_card_location(selected) == "p%d_bench" % actor_id:
				ctx.state.board.swap_cards(current_active, selected)
	)


## SS_86: Remove all Special Conditions from each of your Active Pokémon.
static func _double_full_heal(ctx: CardEffectContext) -> void:
	for slot in range(ctx.state.board.num_active_slots):
		var active := ctx.state.board.get_active_card(ctx.actor_id, slot)
		if active != null:
			active.clear_conditions()


## SS_88: Choose a Basic Pokémon in play; evolve it with a Stage 1 or 2 from hand.
## (Bypasses the "cannot evolve the same turn it was played" restriction.)
## Auto-select: first valid Basic + first matching evolution in hand.
static func _rare_candy(ctx: CardEffectContext) -> void:
	var actor_id := ctx.actor_id
	var hand := ctx.state.board.get_hand_cards(actor_id)
	var in_play := ctx.state.get_all_in_play(actor_id)

	for basic in in_play:
		if not (basic.data is PokemonCardData):
			continue
		if (basic.data as PokemonCardData).stage != PokemonCardData.Stage.BASIC:
			continue
		var slug := (basic.data as PokemonCardData).name_slug
		for evo_card in hand:
			if not (evo_card.data is PokemonCardData):
				continue
			var evo_data := evo_card.data as PokemonCardData
			if evo_data.evolves_from != slug:
				continue
			if evo_data.stage == PokemonCardData.Stage.BASIC:
				continue
			# Perform the evolution manually (mirrors ActionEvolvePokemon.apply).
			var target_zone := ctx.state.board.find_card_location(basic)
			evo_card.damage = basic.damage
			evo_card.attached_energy = basic.attached_energy.duplicate()
			evo_card.attached_tools = basic.attached_tools.duplicate()
			basic.attached_energy.clear()
			basic.attached_tools.clear()
			evo_card.prior_stage = basic
			evo_card.turn_entered_play = ctx.state.turn_number
			ctx.state.board.remove_card(basic)
			ctx.state.board.move_card(evo_card, target_zone)
			return


## SS_90/91/92: Fossil plays to the bench (or active) as a pseudo-Pokémon.
## ActionPlayTrainerItem already moved the card to discard; we pull it back.
static func _play_as_fossil(ctx: CardEffectContext) -> void:
	var actor_id := ctx.actor_id
	# Try active first (if empty), then bench.
	var slot := ctx.state.board.get_first_empty_active_slot(actor_id)
	if slot >= 0:
		ctx.state.board.move_card(ctx.card, "p%d_active_%d" % [actor_id, slot])
		ctx.card.turn_entered_play = ctx.state.turn_number
	elif ctx.state.board.can_play_card_to_bench(actor_id):
		ctx.state.board.move_card(ctx.card, "p%d_bench" % actor_id)
		ctx.card.turn_entered_play = ctx.state.turn_number


# =============================================================================
# SUPPORTERS
# =============================================================================

## RS_83: Search deck for up to 3 different types of Basic Energy; put in hand.
static func _lady_outing(ctx: CardEffectContext) -> void:
	var deck := ctx.state.board.get_zone("p%d_deck" % ctx.actor_id).duplicate()
	## One representative card per energy type (unique types only).
	var found_types: Array[int] = []
	var eligible: Array = []
	for card in deck:
		if not (card is CardInstance) or not (card as CardInstance).data is EnergyCardData:
			continue
		var edata := (card as CardInstance).data as EnergyCardData
		if not _is_basic_energy(edata.energy_type):
			continue
		if found_types.has(edata.energy_type):
			continue
		found_types.append(edata.energy_type)
		eligible.append(card)
	if eligible.is_empty():
		return
	var actor_id := ctx.actor_id
	var state := ctx.state
	TurnControllerSingleton.request_card_search(
		eligible,
		3,
		"Lady's Outing: Choose up to 3 different Basic Energy types",
		func(chosen: Array) -> void:
			for card in chosen:
				state.board.move_card(card, "p%d_hand" % actor_id)
			var p := state.get_player(actor_id)
			if p: p.shuffle_deck_zone(state.board)
	)


## RS_89: Draw cards until you have 6 in hand.
static func _professor_birch(ctx: CardEffectContext) -> void:
	var have := ctx.state.board.get_hand_cards(ctx.actor_id).size()
	var need := maxi(0, 6 - have)
	if need > 0:
		CardEffects.draw_cards(ctx.state, ctx.actor_id, need)


## SS_87: Search deck for up to 3 different types of Basic Pokémon; put in hand.
static func _lanette_net_search(ctx: CardEffectContext) -> void:
	var deck := ctx.state.board.get_zone("p%d_deck" % ctx.actor_id).duplicate()
	## One representative per Pokémon type (unique types only).
	var found_types: Array[int] = []
	var eligible: Array = []
	for card in deck:
		if not (card is CardInstance) or not (card as CardInstance).data is PokemonCardData:
			continue
		var pdata := (card as CardInstance).data as PokemonCardData
		if pdata.stage != PokemonCardData.Stage.BASIC:
			continue
		if found_types.has(pdata.pokemon_type):
			continue
		found_types.append(pdata.pokemon_type)
		eligible.append(card)
	if eligible.is_empty():
		return
	var actor_id := ctx.actor_id
	var state := ctx.state
	TurnControllerSingleton.request_card_search(
		eligible,
		3,
		"Lanette's Net Search: Choose up to 3 different Basic Pokémon types",
		func(chosen: Array) -> void:
			for card in chosen:
				state.board.move_card(card, "p%d_hand" % actor_id)
			var p := state.get_player(actor_id)
			if p: p.shuffle_deck_zone(state.board)
	)


## SS_89: Search deck for a Stage 1 that evolves from your Active; evolve it now.
## (Does NOT bypass the first-turn/same-turn restriction in this implementation.)
static func _wally_training(ctx: CardEffectContext) -> void:
	var actor_id := ctx.actor_id
	var active := ctx.state.board.get_active_card(actor_id, 0)
	if not (active != null and active.data is PokemonCardData):
		return
	var active_slug := (active.data as PokemonCardData).name_slug
	var deck := ctx.state.board.get_zone("p%d_deck" % actor_id).duplicate()

	var eligible: Array = []
	for card in deck:
		if not (card is CardInstance) or not (card as CardInstance).data is PokemonCardData:
			continue
		var pdata := (card as CardInstance).data as PokemonCardData
		if pdata.evolves_from != active_slug or pdata.stage != PokemonCardData.Stage.STAGE1:
			continue
		eligible.append(card)
	if eligible.is_empty():
		return

	var state := ctx.state
	var active_ref := active
	TurnControllerSingleton.request_card_search(
		eligible,
		1,
		"Wally's Training: Choose a Stage 1 to evolve your Active",
		func(chosen: Array) -> void:
			if chosen.is_empty():
				return
			var evo_card := chosen[0] as CardInstance
			var target_zone := state.board.find_card_location(active_ref)
			evo_card.damage           = active_ref.damage
			evo_card.attached_energy  = active_ref.attached_energy.duplicate()
			evo_card.attached_tools   = active_ref.attached_tools.duplicate()
			active_ref.attached_energy.clear()
			active_ref.attached_tools.clear()
			evo_card.prior_stage      = active_ref
			evo_card.turn_entered_play = state.turn_number
			state.board.remove_card(active_ref)
			state.board.move_card(evo_card, target_zone)
			var p := state.get_player(actor_id)
			if p: p.shuffle_deck_zone(state.board)
	)


## DR_88: Draw 3 cards, then discard 1 from hand.
## Auto-select: discard the first card in hand after drawing.
static func _tv_reporter(ctx: CardEffectContext) -> void:
	CardEffects.draw_cards(ctx.state, ctx.actor_id, 3)
	var hand := ctx.state.board.get_hand_cards(ctx.actor_id)
	if not hand.is_empty():
		ctx.state.board.move_card(hand[0], "p%d_discard" % ctx.actor_id)


## DR_87: Return 1 non-EX Pokémon (and all its attachments) from play to hand.
## Auto-select: active slot first; fallback to bench.
static func _mr_briney(ctx: CardEffectContext) -> void:
	var actor_id := ctx.actor_id
	var candidate: CardInstance = null

	for slot in range(ctx.state.board.num_active_slots):
		var a := ctx.state.board.get_active_card(actor_id, slot)
		if a != null and not _is_ex(a):
			candidate = a
			break

	if candidate == null:
		for b in ctx.state.board.get_bench_cards(actor_id):
			if not _is_ex(b):
				candidate = b
				break

	if candidate == null:
		return

	# Return all energy and tools to hand.
	for energy in candidate.attached_energy.duplicate():
		ctx.state.board.move_card(energy, "p%d_hand" % actor_id)
	candidate.attached_energy.clear()
	for tool in candidate.attached_tools.duplicate():
		ctx.state.board.move_card(tool, "p%d_hand" % actor_id)
	candidate.attached_tools.clear()

	# Reset in-play state.
	candidate.damage = 0
	candidate.clear_conditions()
	candidate.prior_stage = null

	ctx.state.board.move_card(candidate, "p%d_hand" % actor_id)


# =============================================================================
# TOOL BETWEEN-TURNS TRIGGERS
# =============================================================================

## RS_84: Remove all Special Conditions from the holder; then discard the berry.
static func _lum_berry_tick(
		tool: CardInstance,
		holder: CardInstance,
		state: GameState
) -> void:
	if holder.special_conditions.is_empty():
		return
	holder.clear_conditions()
	holder.attached_tools.erase(tool)
	state.board.move_card(tool, "p%d_discard" % holder.owner_id)


## RS_85: Remove 2 damage counters if holder has ≥ 20 damage; then discard.
static func _oran_berry_tick(
		tool: CardInstance,
		holder: CardInstance,
		state: GameState
) -> void:
	if holder.damage < 20:
		return
	holder.heal(20)
	holder.attached_tools.erase(tool)
	state.board.move_card(tool, "p%d_discard" % holder.owner_id)


# =============================================================================
# HELPERS
# =============================================================================

static func _is_basic_energy(etype: PokemonCardData.EnergyType) -> bool:
	return etype in [
		PokemonCardData.EnergyType.FIRE,
		PokemonCardData.EnergyType.WATER,
		PokemonCardData.EnergyType.GRASS,
		PokemonCardData.EnergyType.LIGHTNING,
		PokemonCardData.EnergyType.PSYCHIC,
		PokemonCardData.EnergyType.FIGHTING,
		PokemonCardData.EnergyType.DARKNESS,
		PokemonCardData.EnergyType.METAL,
	]


static func _is_ex(card: CardInstance) -> bool:
	if not (card.data is PokemonCardData):
		return false
	return card.data.card_id.ends_with("_ex") \
		or (card.data as PokemonCardData).display_name.ends_with(" ex")
