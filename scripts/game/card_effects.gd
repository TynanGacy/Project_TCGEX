class_name CardEffects
## Reusable card-effect building blocks.
##
## Rather than duplicating search-deck / draw / heal logic inside every Trainer
## or attack effect, call these static functions.  Any future card that needs
## "search your deck for a Basic Pokemon" simply calls
##   CardEffects.search_deck_for_basics(state, player_id, 1)
##
## Note: not all functions are wired to card text parsing yet — this library
## exists so future implementations have a single authoritative place to go.


## Draws [count] cards from [player_id]'s deck into their hand.
## Returns each drawn CardInstance; returns fewer if the deck runs out.
static func draw_cards(
	state: GameState,
	player_id: int,
	count: int
) -> Array[CardInstance]:
	var player := state.get_player(player_id)
	if player == null:
		return []
	var drawn: Array[CardInstance] = []
	for _i in count:
		var card := player.draw_card(state.board)
		if card != null:
			drawn.append(card)
		else:
			break  # Deck exhausted.
	return drawn


## Searches [player_id]'s deck for up to [count] cards satisfying [filter_fn],
## moves them to hand, then shuffles the remaining deck.
## filter_fn signature:  func(CardInstance) -> bool
static func search_deck(
	state: GameState,
	player_id: int,
	count: int,
	filter_fn: Callable
) -> Array[CardInstance]:
	var deck := state.board.get_zone("p%d_deck" % player_id).duplicate()
	var matches: Array[CardInstance] = []

	for card in deck:
		if card is CardInstance and filter_fn.call(card):
			matches.append(card)
			if matches.size() >= count:
				break

	for card in matches:
		state.board.move_card(card, "p%d_hand" % player_id)

	var player := state.get_player(player_id)
	if player:
		player.shuffle_deck_zone(state.board)

	return matches


## Convenience: find up to [count] Basic Pokemon in the deck and put them in
## hand.
static func search_deck_for_basics(
	state: GameState,
	player_id: int,
	count: int
) -> Array[CardInstance]:
	return search_deck(state, player_id, count, func(c: CardInstance) -> bool:
		return c.data is PokemonCardData \
			and (c.data as PokemonCardData).stage == PokemonCardData.Stage.BASIC
	)


## Convenience: find up to [count] Energy cards of [energy_type] in the deck.
## Pass EnergyType.NONE to accept any type.
static func search_deck_for_energy(
	state: GameState,
	player_id: int,
	count: int,
	energy_type: int = PokemonCardData.EnergyType.NONE
) -> Array[CardInstance]:
	return search_deck(state, player_id, count, func(c: CardInstance) -> bool:
		if not (c.data is EnergyCardData):
			return false
		if energy_type == PokemonCardData.EnergyType.NONE:
			return true
		return (c.data as EnergyCardData).energy_type == energy_type
	)


## Heals [amount] damage from [target].
static func heal(target: CardInstance, amount: int) -> void:
	target.heal(amount)


## Discards all energy attached to [target] into their owner's discard pile.
static func discard_all_energy(state: GameState, target: CardInstance) -> void:
	for energy in target.attached_energy.duplicate():
		state.board.move_card(energy, "p%d_discard" % target.owner_id)
	target.attached_energy.clear()


## Shuffles [player_id]'s entire hand back into their deck then draws [count].
static func shuffle_hand_and_draw(
	state: GameState,
	player_id: int,
	count: int
) -> Array[CardInstance]:
	var hand := state.board.get_zone("p%d_hand" % player_id).duplicate()
	for card in hand:
		if card is CardInstance:
			state.board.move_card(card, "p%d_deck" % player_id)

	var player := state.get_player(player_id)
	if player:
		player.shuffle_deck_zone(state.board)

	return draw_cards(state, player_id, count)


## Applies a special condition to [target].
static func apply_condition(
	target: CardInstance,
	condition: CardInstance.SpecialCondition
) -> void:
	target.add_condition(condition)


## Removes every special condition from [target].
static func cure_all_conditions(target: CardInstance) -> void:
	target.clear_conditions()


## Deals [damage] damage to every Pokemon on [player_id]'s bench.
## Bench damage ignores weakness and resistance (standard rule).
static func spread_bench_damage(
	state: GameState,
	player_id: int,
	damage: int
) -> void:
	for bench_card in state.board.get_bench_cards(player_id):
		bench_card.apply_damage(damage)


## Moves all cards from [player_id]'s discard pile back into their deck,
## then shuffles.  Useful for "Fisherman"-style effects.
static func recover_from_discard(state: GameState, player_id: int) -> void:
	var discard := state.board.get_zone("p%d_discard" % player_id).duplicate()
	for card in discard:
		if card is CardInstance:
			state.board.move_card(card, "p%d_deck" % player_id)
	var player := state.get_player(player_id)
	if player:
		player.shuffle_deck_zone(state.board)
