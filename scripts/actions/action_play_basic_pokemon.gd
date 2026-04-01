class_name ActionPlayBasicPokemon
extends GameAction

## Plays a Basic Pokemon card from hand to the active slot or bench.
## target_zone must be "active" or "bench".

var card: CardInstance
var target_zone: String


func _init(pid: int, p_card: CardInstance, zone: String = "bench") -> void:
	actor_id = pid
	card = p_card
	target_zone = zone


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Can only play Pokemon during MAIN phase.")

	if card == null:
		return ActionResult.fail("No card specified.")

	if not (card.data is PokemonCardData):
		return ActionResult.fail("Card is not a Pokemon.")

	var pokemon_data := card.data as PokemonCardData
	if pokemon_data.stage != PokemonCardData.Stage.BASIC:
		return ActionResult.fail("Only Basic Pokemon can be played directly from hand.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Card is not in your hand.")

	var zone_id := _get_zone_id(state)
	if zone_id == "":
		return ActionResult.fail("Active slot is already occupied.")

	if not state.board.can_add_to_zone(zone_id):
		return ActionResult.fail("Cannot play to %s: zone is full." % target_zone)

	return ActionResult.success()


func apply(state: GameState) -> void:
	var zone_id := _get_zone_id(state)
	state.board.move_card(card, zone_id)
	card.turn_entered_play = state.turn_number


func description() -> String:
	if card != null and card.data != null:
		return "Play Basic Pokemon %s to %s" % [card.data.display_name, target_zone]
	return "Play Basic Pokemon"


func _get_zone_id(state: GameState) -> String:
	if target_zone == "active":
		var slot := state.board.get_first_empty_active_slot(actor_id)
		if slot == -1:
			return ""
		return "p%d_active_%d" % [actor_id, slot]
	return "p%d_bench" % actor_id
