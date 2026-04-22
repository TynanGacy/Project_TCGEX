class_name ActionAttachTool
extends GameAction
## Attaches a Pokemon Tool (a Trainer card with trainer_kind == TOOL) from
## hand onto one of the player's in-play Pokemon.  A Pokemon may hold at
## most one Tool at a time.

var player_id: int = 0
var card: TrainerCardData = null
var target_slot: String = ""


func _init(pid: int, tool_card: TrainerCardData, slot_id: String) -> void:
	player_id   = pid
	card        = tool_card
	target_slot = slot_id


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No tool card specified.")
	if card.trainer_kind != TrainerCardData.TrainerKind.TOOL:
		return ActionResult.fail("Card is not a Pokemon Tool.")
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Tool is not in your hand.")
	if not manager.board_position.has_slot(target_slot):
		return ActionResult.fail("Unknown slot '%s'." % target_slot)
	if manager.board_position.player_of(target_slot) != player_id:
		return ActionResult.fail("Slot does not belong to you.")
	var inst: PokemonInstance = manager.board_position.get_instance(target_slot)
	if inst == null:
		return ActionResult.fail("No Pokemon in that slot to attach to.")
	if not inst.attached_tools.is_empty():
		return ActionResult.fail("That Pokemon already has a Tool attached.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	var inst: PokemonInstance = manager.board_position.get_instance(target_slot)
	inst.attach_tool(card)


func description() -> String:
	var name := card.display_name if card != null else "Tool"
	return "P%d attaches %s to %s" % [player_id, name, target_slot]
