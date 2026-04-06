class_name ActionPlayBasicPokemon
extends GameAction
## Plays a Basic Pokemon card from hand to the active slot or bench.
##
## If [target_zone] is "bench" but the player has an empty active slot, the
## card is automatically redirected to the active slot.  This implements the
## rule: "you may never have an empty active slot while you have Pokemon in
## play" — so any attempt to play to the bench when the active is open instead
## fills the active slot first.

var card: CardInstance
var target_zone: String  ## "active" or "bench" (may be redirected internally)


func _init(pid: int, p_card: CardInstance, zone: String = "bench") -> void:
	actor_id    = pid
	card        = p_card
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

	var zone_id := _resolve_zone_id(state)
	if zone_id == "":
		return ActionResult.fail("No valid slot available (active full, bench full).")

	if not state.board.can_add_to_zone(zone_id):
		return ActionResult.fail("Cannot play to %s: zone is full." % zone_id)

	return ActionResult.success()


func apply(state: GameState) -> void:
	var zone_id := _resolve_zone_id(state)
	state.board.move_card(card, zone_id)
	card.turn_entered_play = state.turn_number


func description() -> String:
	var dest := _actual_zone_description()
	if card != null and card.data != null:
		return "Play Basic Pokemon %s to %s" % [card.data.display_name, dest]
	return "Play Basic Pokemon to %s" % dest


## Returns the resolved logical zone ID (with active-slot redirect applied).
func _resolve_zone_id(state: GameState) -> String:
	## Rule: if an active slot is open, always fill it first — even when the
	## player nominally requested the bench.
	var empty_active := state.board.get_first_empty_active_slot(actor_id)
	if empty_active >= 0:
		return "p%d_active_%d" % [actor_id, empty_active]

	## All active slots occupied: go to bench (if "bench" was requested).
	if target_zone == "bench":
		return "p%d_bench" % actor_id

	## target_zone == "active" but no empty slot.
	return ""


func _actual_zone_description() -> String:
	return "active" if target_zone == "active" else "bench/active"
