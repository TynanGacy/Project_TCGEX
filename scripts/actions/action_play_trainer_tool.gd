class_name ActionPlayTrainerTool
extends GameAction

## Attaches a Tool trainer card to a Pokemon in play.
## Each Pokemon may hold at most one Tool.

var card: CardInstance
var target: CardInstance


func _init(pid: int, tool_card: CardInstance, target_pokemon: CardInstance) -> void:
	actor_id = pid
	card = tool_card
	target = target_pokemon


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Can only play Trainer cards during MAIN phase.")

	if card == null or target == null:
		return ActionResult.fail("Invalid card or target.")

	if not (card.data is TrainerCardData):
		return ActionResult.fail("Card is not a Trainer card.")

	var trainer_data := card.data as TrainerCardData
	if trainer_data.trainer_kind != TrainerCardData.TrainerKind.TOOL:
		return ActionResult.fail("Card is not a Tool card.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Card is not in your hand.")

	if not (target.data is PokemonCardData):
		return ActionResult.fail("Target is not a Pokemon.")

	if not _target_is_in_play(state):
		return ActionResult.fail("Target Pokemon is not in play.")

	if not target.attached_tools.is_empty():
		return ActionResult.fail("That Pokemon already has a Tool attached.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	# Remove the Tool from the hand zone; it lives attached to the Pokemon.
	state.board.remove_card(card)
	card.zone = CardInstance.Zone.OTHER

	target.attach_tool(card)


func description() -> String:
	if card != null and target != null and card.data != null and target.data != null:
		return "Attach Tool %s to %s" % [card.data.display_name, target.data.display_name]
	return "Attach Tool"


func _target_is_in_play(state: GameState) -> bool:
	var target_zone := state.board.find_card_location(target)
	for slot_idx in range(state.board.num_active_slots):
		if target_zone == "p%d_active_%d" % [actor_id, slot_idx]:
			return true
	if target_zone == "p%d_bench" % actor_id:
		return true
	return false
