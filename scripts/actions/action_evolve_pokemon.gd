class_name ActionEvolvePokemon
extends GameAction

## Evolves a Pokemon already in play (active or bench).
## card  — the Stage 1 or Stage 2 card from the player's hand.
## target — the in-play Pokemon being evolved.

var card: CardInstance
var target: CardInstance


func _init(pid: int, evolution_card: CardInstance, target_card: CardInstance) -> void:
	actor_id = pid
	card = evolution_card
	target = target_card


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Can only evolve during MAIN phase.")

	if card == null or target == null:
		return ActionResult.fail("Invalid card or target.")

	if not (card.data is PokemonCardData):
		return ActionResult.fail("Card is not a Pokemon.")

	var evolution_data := card.data as PokemonCardData

	if evolution_data.stage == PokemonCardData.Stage.BASIC:
		return ActionResult.fail("Basic Pokemon cannot be played as an evolution.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Evolution card is not in your hand.")

	# Target must be in the player's active or bench zone.
	if not _target_is_in_play(state):
		return ActionResult.fail("Target Pokemon is not in play.")

	# Cannot evolve on the same turn the Pokemon was played.
	if target.turn_entered_play >= state.turn_number:
		return ActionResult.fail("Cannot evolve a Pokemon on the same turn it was played.")

	# Cannot evolve on the player's very first turn.
	# Player 0's first turn is turn 1; Player 1's first turn is turn 2.
	if state.turn_number <= actor_id + 1:
		return ActionResult.fail("Cannot evolve on your first turn.")

	if not (target.data is PokemonCardData):
		return ActionResult.fail("Target is not a Pokemon.")

	var target_data := target.data as PokemonCardData

	if evolution_data.evolves_from == "":
		return ActionResult.fail("Evolution card does not specify what it evolves from.")

	if target_data.card_id != evolution_data.evolves_from:
		return ActionResult.fail(
			"Cannot evolve %s onto %s." % [card.data.display_name, target.data.display_name]
		)

	# Stage consistency check.
	if evolution_data.stage == PokemonCardData.Stage.STAGE1 \
			and target_data.stage != PokemonCardData.Stage.BASIC:
		return ActionResult.fail("Stage 1 must evolve from a Basic Pokemon.")

	if evolution_data.stage == PokemonCardData.Stage.STAGE2 \
			and target_data.stage != PokemonCardData.Stage.STAGE1:
		return ActionResult.fail("Stage 2 must evolve from a Stage 1 Pokemon.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	var target_zone_id := state.board.find_card_location(target)

	# Damage counters carry over to the evolution.
	card.damage = target.damage

	# Keep a reference to the card underneath.
	card.prior_stage = target
	card.turn_entered_play = state.turn_number

	# Remove the prior stage from the board (it goes "under" the evolution).
	state.board.remove_card(target)

	# Move the evolution card from hand into the now-vacant zone.
	state.board.move_card(card, target_zone_id)


func description() -> String:
	if card != null and target != null and card.data != null and target.data != null:
		return "Evolve %s into %s" % [target.data.display_name, card.data.display_name]
	return "Evolve Pokemon"


func _target_is_in_play(state: GameState) -> bool:
	var target_zone := state.board.find_card_location(target)
	for slot_idx in range(state.board.num_active_slots):
		if target_zone == "p%d_active_%d" % [actor_id, slot_idx]:
			return true
	if target_zone == "p%d_bench" % actor_id:
		return true
	return false
