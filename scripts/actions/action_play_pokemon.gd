class_name ActionPlayPokemon
extends GameAction
## Plays a Basic Pokemon from hand into a specific slot.  This is the
## foundational Game_Action on top of which the other card-type actions
## (attach energy / attach tool / play item / play supporter / play stadium /
## evolve) are built.  Attack resolution and the formal turn system will be
## layered on top of the same request_action() entry point.

var player_id: int = 0
var card: PokemonCardData = null
var target_slot: String = ""  ## e.g. "p0_bench2" or "p0_active1"


func _init(pid: int, pokemon_card: PokemonCardData, slot_id: String) -> void:
	player_id   = pid
	card        = pokemon_card
	target_slot = slot_id


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No card specified.")
	if card.stage != PokemonCardData.Stage.BASIC:
		return ActionResult.fail("Only Basic Pokemon can be played from hand.")
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Card is not in your hand.")
	if not manager.board_position.has_slot(target_slot):
		return ActionResult.fail("Unknown slot '%s'." % target_slot)
	if not manager.is_valid_slot(target_slot):
		return ActionResult.fail("Slot '%s' is not in use this game." % target_slot)
	if manager.board_position.player_of(target_slot) != player_id:
		return ActionResult.fail("Slot does not belong to you.")
	if not manager.board_position.is_empty(target_slot):
		return ActionResult.fail("Slot '%s' is occupied." % target_slot)
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	var instance := PokemonInstance.create(card, player_id)
	manager.board_position.place(target_slot, instance)
	manager.pokemon_entered_play_this_turn[player_id].append(instance)


func description() -> String:
	var name := card.display_name if card != null else "Pokemon"
	return "P%d plays %s to %s" % [player_id, name, target_slot]
