class_name GameState
extends RefCounted
## Central game-state object.
##
## Owns the BoardState, the Player records, the current phase, and all
## per-turn flags.  Also provides higher-level helpers for prize setup,
## knockout resolution, and win-condition checking — keeping that logic out of
## the visual layer.

var current_player_id: int = 0
var turn_number: int = 1
var phase: int = TurnPhase.Phase.START

var board: BoardState

var players: Array[Player] = []

var has_attacked_this_turn: bool = false
var has_retreated_this_turn: bool = false

## Set true once prizes have been dealt and the game is underway.
## Win-condition checks are suppressed until then.
var game_started: bool = false


func _init(num_players: int = 2, active_slots: int = 1, max_bench: int = 5) -> void:
	board = BoardState.new(num_players, active_slots, max_bench)

	for i in range(num_players):
		var player := Player.new(i)
		players.append(player)


# ---------------------------------------------------------------------------
# Player accessors
# ---------------------------------------------------------------------------

func get_current_player() -> Player:
	if current_player_id >= 0 and current_player_id < players.size():
		return players[current_player_id]
	return null


func get_player(player_id: int) -> Player:
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	return null


# ---------------------------------------------------------------------------
# Turn management
# ---------------------------------------------------------------------------

func begin_turn(player_id: int) -> void:
	current_player_id = player_id
	phase = TurnPhase.Phase.START
	has_attacked_this_turn = false
	has_retreated_this_turn = false

	var player := get_current_player()
	if player:
		player.reset_turn_flags()


func advance_phase() -> void:
	match phase:
		TurnPhase.Phase.START:  phase = TurnPhase.Phase.MAIN
		TurnPhase.Phase.MAIN:   phase = TurnPhase.Phase.END
		TurnPhase.Phase.ATTACK: phase = TurnPhase.Phase.END  # legacy fallback
		TurnPhase.Phase.END:    pass


func end_turn() -> void:
	turn_number += 1
	current_player_id = 1 - current_player_id  # Two-player only.
	begin_turn(current_player_id)


# ---------------------------------------------------------------------------
# Deck and prize setup
# ---------------------------------------------------------------------------

func setup_player_deck(player_id: int, card_data_array: Array[CardData]) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	player.setup_deck(card_data_array)
	player.load_deck_into_board(board)
	player.shuffle_deck_zone(board)


func draw_starting_hand(player_id: int, count: int = 7) -> void:
	var player := get_player(player_id)
	if player == null:
		return
	for _i in count:
		player.draw_card(board)


## Maximum number of mulligan reshuffles before giving up.
## Prevents an infinite loop when a deck has no Basic Pokemon (e.g. corrupt JSON).
const MAX_MULLIGANS := 20

## Draws a starting hand with the mulligan rule: if the hand contains no Basic
## Pokemon, shuffle all cards back into the deck and redraw.  Repeats until a
## hand with at least one Basic Pokemon is found, or MAX_MULLIGANS is reached.
##
## Returns the number of reshuffles (mulligans) that occurred.  The caller may
## log or store this value for debugging purposes.
func draw_starting_hand_with_mulligan(player_id: int, count: int = 7) -> int:
	var player := get_player(player_id)
	if player == null:
		return 0

	var reshuffles := 0
	while reshuffles <= MAX_MULLIGANS:
		for _i in count:
			player.draw_card(board)

		if not _has_no_basic_in_hand(player_id):
			break  ## Hand has at least one Basic Pokemon — keep it.

		## No Basic in hand: return cards to deck and reshuffle.
		var hand_zone := "p%d_hand" % player_id
		var hand_cards := board.get_zone(hand_zone).duplicate()
		for card in hand_cards:
			board.move_card(card, "p%d_deck" % player_id)
		player.shuffle_deck_zone(board)
		reshuffles += 1

		if reshuffles > MAX_MULLIGANS:
			push_error(
				"draw_starting_hand_with_mulligan: P%d exceeded %d mulligans — "
				+ "deck may have no Basic Pokemon." % [player_id, MAX_MULLIGANS]
			)
			break

	return reshuffles


## Deals [count] cards from the top of [player_id]'s deck into their prize
## zone.  Must be called AFTER setup_player_deck() and BEFORE
## draw_starting_hand() so prizes come from the freshly shuffled deck.
## Moves [count] cards from the top of [player_id]'s deck into their prize zone.
## Must be called AFTER setup_player_deck() (deck populated & shuffled) and
## BEFORE draw_starting_hand() so prizes come from the freshly shuffled deck.
## Stops early without error if the deck runs out before [count] cards are taken.
func setup_prizes(player_id: int, count: int) -> void:
	var deck_zone    := "p%d_deck"   % player_id
	var prizes_zone  := "p%d_prizes" % player_id

	for _i in count:
		var deck := board.get_zone(deck_zone)
		if deck.is_empty():
			break
		## Draw from the "top" (back of the array — same convention as Player.draw_card).
		var card := deck.back() as CardInstance
		board.move_card(card, prizes_zone)

	var player := get_player(player_id)
	if player:
		player.prizes_remaining = board.get_zone(prizes_zone).size()


# ---------------------------------------------------------------------------
# Stadium queries
# ---------------------------------------------------------------------------

## Returns the card_id of the currently active Stadium card, or "" if none.
func get_active_stadium_id() -> String:
	var zone := board.get_zone("stadium")
	if zone.is_empty():
		return ""
	var card := zone[0] as CardInstance
	if card == null or card.data == null:
		return ""
	return card.data.card_id


# ---------------------------------------------------------------------------
# In-play Pokemon queries
# ---------------------------------------------------------------------------

func get_active_cards(player_id: int) -> Array[CardInstance]:
	## All currently occupied active slots for [player_id].
	var result: Array[CardInstance] = []
	for slot_idx in range(board.num_active_slots):
		var card := board.get_active_card(player_id, slot_idx)
		if card != null:
			result.append(card)
	return result


## Returns all Pokemon currently in play for [player_id] (active + bench).
func get_all_in_play(player_id: int) -> Array[CardInstance]:
	var result := get_active_cards(player_id)
	result.append_array(board.get_bench_cards(player_id))
	return result


# ---------------------------------------------------------------------------
# Active-slot swap helpers (kept from original)
# ---------------------------------------------------------------------------

func can_swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> bool:
	return board.can_swap_active_with_bench(player_id, active_slot, bench_index)


func swap_active_with_bench(player_id: int, active_slot: int, bench_index: int) -> void:
	var active_card := board.get_active_card(player_id, active_slot)
	var bench_card  := board.get_bench_card_at(player_id, bench_index)
	if active_card != null and bench_card != null:
		board.swap_cards(active_card, bench_card)


func can_retreat_active(player_id: int, active_slot: int, bench_index: int) -> bool:
	if not can_swap_active_with_bench(player_id, active_slot, bench_index):
		return false
	var active_card := board.get_active_card(player_id, active_slot)
	if active_card == null:
		return false
	return active_card.attached_energy.size() >= active_card.get_effective_retreat_cost(self)


## [energy_to_discard] is an optional list of specific energy cards the player
## chose to pay.  When empty the first N cards are discarded automatically
## (fallback for zero-cost retreats and Balloon Berry).
func retreat_active_to_bench(
		player_id: int,
		active_slot: int,
		bench_index: int,
		energy_to_discard: Array[CardInstance] = []
) -> bool:
	if not can_retreat_active(player_id, active_slot, bench_index):
		return false

	var active_card := board.get_active_card(player_id, active_slot)
	if active_card == null:
		return false

	# Balloon Berry: discard the tool when retreating instead of Energy cards.
	var balloon := active_card.get_tool()
	if balloon != null and balloon.data != null and balloon.data.card_id == "DR_82_balloon_berry":
		active_card.attached_tools.erase(balloon)
		board.move_card(balloon, "p%d_discard" % player_id)
	elif not energy_to_discard.is_empty():
		## Use player-chosen energy.
		for energy in energy_to_discard:
			if not active_card.attached_energy.has(energy):
				continue
			active_card.attached_energy.erase(energy)
			board.move_card(energy, "p%d_discard" % player_id)
	else:
		## Fallback: discard the first N energy cards automatically.
		var retreat_cost := active_card.get_effective_retreat_cost(self)
		for i in range(retreat_cost):
			if active_card.attached_energy.is_empty():
				break
			var energy := active_card.attached_energy[0] as CardInstance
			active_card.attached_energy.remove_at(0)
			board.move_card(energy, "p%d_discard" % player_id)

	swap_active_with_bench(player_id, active_slot, bench_index)
	has_retreated_this_turn = true
	return true


func can_promote_from_bench(player_id: int, bench_index: int) -> bool:
	if board.get_first_empty_active_slot(player_id) == -1:
		return false
	return board.get_bench_card_at(player_id, bench_index) != null


func promote_from_bench(player_id: int, bench_index: int) -> void:
	var slot_idx := board.get_first_empty_active_slot(player_id)
	if slot_idx == -1:
		return
	var bench_card := board.get_bench_card_at(player_id, bench_index)
	if bench_card != null:
		board.move_card(bench_card, "p%d_active_%d" % [player_id, slot_idx])


# ---------------------------------------------------------------------------
# Knockout resolution
# ---------------------------------------------------------------------------

## Checks every active slot belonging to [opp_id] for knocked-out Pokemon.
## For each one found:
##   • Moves the KO'd card (and all its attachments + prior stages) to discard.
##   • Returns an Array of Dictionaries: [{victim, slot_idx}]
##
## The caller (TurnController) then handles prize-taking and signals.
func resolve_knockouts(opp_id: int) -> Array[Dictionary]:
	var knocked_out: Array[Dictionary] = []

	for slot_idx in range(board.num_active_slots):
		var card := board.get_active_card(opp_id, slot_idx)
		if card == null:
			continue
		if not card.is_knocked_out():
			continue

		knocked_out.append({"victim": card, "slot_idx": slot_idx})
		_send_to_discard(card, opp_id)

	return knocked_out


## Recursively discards a Pokemon and everything attached to it.
## Resets all in-play state so the card is logically identical to an unplayed copy.
func _send_to_discard(card: CardInstance, player_id: int) -> void:
	var discard := "p%d_discard" % player_id

	## Discard energy attachments.
	for energy in card.attached_energy.duplicate():
		board.move_card(energy, discard)
	card.attached_energy.clear()

	## Discard tool attachments.
	for tool in card.attached_tools.duplicate():
		board.move_card(tool, discard)
	card.attached_tools.clear()

	## Discard the card that was underneath (prior stage in evolution stack).
	if card.prior_stage != null:
		_send_to_discard(card.prior_stage, player_id)
		card.prior_stage = null

	## Reset in-play state: damage and special conditions don't persist in discard.
	card.damage = 0
	card.clear_conditions()

	board.move_card(card, discard)


# ---------------------------------------------------------------------------
# Win-condition check
# ---------------------------------------------------------------------------

## Returns the winning player_id, or -1 if the game is still ongoing.
##
## Win conditions (checked in priority order):
##   1. A player has taken all their prize cards.
##   2. The opponent has no Pokemon remaining in play and none in hand to play.
func check_win_condition() -> int:
	if not game_started:
		return -1

	## Condition 1: Prize cards exhausted.
	for pid in range(players.size()):
		var player := get_player(pid)
		if player != null and player.prizes_remaining == 0:
			return pid

	## Condition 2: Opponent has no Pokemon left anywhere.
	for pid in range(players.size()):
		var opp := 1 - pid
		if board.count_active_pokemon(opp) == 0 \
				and board.get_bench_cards(opp).is_empty() \
				and _has_no_basic_in_hand(opp):
			return pid

	return -1


func _has_no_basic_in_hand(player_id: int) -> bool:
	for card in board.get_hand_cards(player_id):
		if card.data is PokemonCardData \
				and (card.data as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return false
	return true


# ---------------------------------------------------------------------------
# Special-condition end-of-turn effects
# ---------------------------------------------------------------------------

## Applies end-of-turn damage for Burn and Poison, resolves Sleep/Paralysis,
## and triggers between-turns tool effects (Lum Berry, Oran Berry, Buffer Piece).
## Call at the END of [player_id]'s turn (before the turn counter flips).
##
## Rules (Generation III / RS format):
##   Poison    — 10 damage per turn (1 damage counter).
##   Burn      — coin flip: heads removes Burn; tails deals 20 damage.
##   Paralysis — automatically cured at end of turn.
##   Sleep     — coin flip: heads wakes the Pokemon.
##   Confusion — no end-of-turn effect; resolved on attack.
##
## NOTE: randi() is used for coin flips.  There is no UI feedback for the flip
## outcome beyond what shows up in the damage counter / condition badge changes.
func apply_end_of_turn_conditions(player_id: int) -> void:
	## Process each player's Pokémon to handle special-condition and tool effects.
	for pid in range(players.size()):
		for pokemon in get_all_in_play(pid):
			## --- Special conditions ------------------------------------------
			if pokemon.has_condition(CardInstance.SpecialCondition.POISONED):
				pokemon.apply_damage(10)  ## 1 damage counter per turn.

			if pokemon.has_condition(CardInstance.SpecialCondition.BURNED):
				## Coin flip: heads = remove burn, tails = 20 damage.
				var burn_name := pokemon.data.display_name if pokemon.data else "Pokemon"
				var burn_flip := TurnControllerSingleton.flip_coins(1, "Burn check for " + burn_name)
				if burn_flip[0]:  # heads — remove burn
					pokemon.remove_condition(CardInstance.SpecialCondition.BURNED)
				else:
					pokemon.apply_damage(20)

			## Paralysis wears off after one turn.
			if pokemon.has_condition(CardInstance.SpecialCondition.PARALYZED):
				pokemon.remove_condition(CardInstance.SpecialCondition.PARALYZED)

			## Coin flip to wake up from Sleep.
			if pokemon.has_condition(CardInstance.SpecialCondition.ASLEEP):
				var sleep_name := pokemon.data.display_name if pokemon.data else "Pokemon"
				var sleep_flip := TurnControllerSingleton.flip_coins(1, "Sleep check for " + sleep_name)
				if sleep_flip[0]:  # heads — wake up
					pokemon.remove_condition(CardInstance.SpecialCondition.ASLEEP)

			## --- Tool between-turns triggers --------------------------------
			## Iterate a copy because tools may be removed (discarded) mid-loop.
			for tool in pokemon.attached_tools.duplicate():
				CardEffectRegistry.dispatch_tool_between_turns(tool, pokemon, self)

	## Buffer Piece: discard at the end of the OPPONENT'S turn.
	## We identify Buffer Pieces held by the player whose turn just ended
	## (player_id) and discard them — they were protecting against this turn's
	## attacks and now expire.
	var opp_id := 1 - player_id
	for pokemon in get_all_in_play(opp_id):
		for tool in pokemon.attached_tools.duplicate():
			if tool.data != null and tool.data.card_id == "DR_83_buffer_piece":
				pokemon.attached_tools.erase(tool)
				board.move_card(tool, "p%d_discard" % opp_id)
