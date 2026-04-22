class_name ActionEvolve
extends GameAction
## Evolves an in-play Pokemon by playing an evolution card (Stage 1 or
## Stage 2) from hand onto it.  The occupying PokemonInstance has the new
## card stacked on top of it via PokemonInstance.evolve_to(), which preserves
## damage and carries prior stages.
##
## Classic "same-turn" restrictions (can't evolve on the turn a Pokemon was
## played, can't evolve on your first turn) are not enforced here while the
## turn system is absent; they will be layered in when turns are restored.

var player_id: int = 0
var card: PokemonCardData = null
var target_slot: String = ""


func _init(pid: int, evolution_card: PokemonCardData, slot_id: String) -> void:
	player_id   = pid
	card        = evolution_card
	target_slot = slot_id


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No evolution card specified.")
	if card.stage == PokemonCardData.Stage.BASIC:
		return ActionResult.fail("Basic Pokemon cannot be evolved onto a target.")
	if card.evolves_from == "":
		return ActionResult.fail("Evolution card has no evolves_from slug.")
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Evolution card is not in your hand.")
	if not manager.board_position.has_slot(target_slot):
		return ActionResult.fail("Unknown slot '%s'." % target_slot)
	if manager.board_position.player_of(target_slot) != player_id:
		return ActionResult.fail("Slot does not belong to you.")
	var inst: PokemonInstance = manager.board_position.get_instance(target_slot)
	if inst == null:
		return ActionResult.fail("No Pokemon in that slot to evolve.")
	var current := inst.card
	if current == null:
		return ActionResult.fail("Slot occupant has no card data.")
	if current.name_slug != card.evolves_from:
		return ActionResult.fail(
			"%s does not evolve from %s." % [card.display_name, current.display_name]
		)
	## Enforce stage ordering: Stage 1 must sit on a Basic, Stage 2 on a Stage 1.
	var required_prev: int = (
		PokemonCardData.Stage.BASIC if card.stage == PokemonCardData.Stage.STAGE1
		else PokemonCardData.Stage.STAGE1
	)
	if current.stage != required_prev:
		return ActionResult.fail("Wrong evolution stage to evolve from.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	var inst: PokemonInstance = manager.board_position.get_instance(target_slot)
	inst.evolve_to(card)
	## Evolving clears Special Conditions; damage is carried over by evolve_to().
	inst.special_conditions.clear()
	inst.refresh_visual()


func description() -> String:
	var name := card.display_name if card != null else "Evolution"
	return "P%d evolves %s into %s" % [player_id, target_slot, name]
