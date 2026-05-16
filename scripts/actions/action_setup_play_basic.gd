class_name ActionSetupPlayBasic
extends GameAction
## Places a Basic Pokémon from hand into a slot during the pre-game setup
## placement phase.  Mirrors ActionPlayPokemon but validates against the setup
## placement state instead of the main phase, and does not track the instance
## in pokemon_entered_play_this_turn (that list is cleared at turn start anyway).

var player_id:   int = 0
var card:        PokemonCardData = null
var target_slot: String = ""


func _init(pid: int, pokemon_card: PokemonCardData, slot_id: String) -> void:
	player_id   = pid
	card        = pokemon_card
	target_slot = slot_id


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No card specified.")
	if card.stage != PokemonCardData.Stage.BASIC:
		return ActionResult.fail("Only Basic Pokémon can be placed during setup.")
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_setup_placement_for(player_id):
		return ActionResult.fail("Not your setup placement turn.")
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
	StadiumEffects.reconcile_aura_for(target_slot, instance, manager)


func description() -> String:
	var name := card.display_name if card != null else "Pokémon"
	return "P%d places %s to %s (setup)" % [player_id, name, target_slot]
