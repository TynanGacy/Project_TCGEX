# res://scripts/actions/action_play_selected_to_empty_active.gd
class_name ActionPlaySelectedToEmptyActive
extends GameAction

var card_view: Node
var target_player_id: int
var slot_index: int

func _init(actor: int = -1, cv: Node = null, target_id: int = -1, slot_i: int = -1) -> void:
	actor_id = actor
	card_view = cv
	target_player_id = target_id
	slot_index = slot_i

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Play to Active only allowed during MAIN phase.")
	if card_view == null or not is_instance_valid(card_view):
		return ActionResult.fail("No selected card.")
	var table_state := state as TableGameState
	if table_state == null:
		return ActionResult.fail("Bad state type.")
	var t := table_state.table

	if slot_index < 0:
		return ActionResult.fail("No empty Active slot.")
	if card_view.get_parent() != t._hand_zones[target_player_id]:
		return ActionResult.fail("Selected card is not in that player's hand.")
	if not table_state.can_play_hand_to_active(target_player_id):
		return ActionResult.fail("That Active zone is full.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	(state as TableGameState).play_hand_to_active(target_player_id, card_view, slot_index)

func description() -> String:
	return "Play selected card to P%d Active[%d]" % [target_player_id, slot_index]
