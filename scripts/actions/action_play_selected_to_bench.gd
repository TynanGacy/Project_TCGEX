# res://scripts/actions/action_play_selected_to_bench.gd
class_name ActionPlaySelectedToBench
extends GameAction

var card_view: Node
var target_player_id: int

func _init(actor: int = -1, cv: Node = null, target_id: int = -1) -> void:
	actor_id = actor
	card_view = cv
	target_player_id = target_id

func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Play to Bench only allowed during MAIN phase.")
	if card_view == null or not is_instance_valid(card_view):
		return ActionResult.fail("No selected card.")
	var table_state := state as TableGameState
	if table_state == null:
		return ActionResult.fail("Bad state type.")
	var t := table_state.table

	if card_view.get_parent() != t._hand_zones[target_player_id]:
		return ActionResult.fail("Selected card is not in that player's hand.")
	if not table_state.can_play_hand_to_bench(target_player_id):
		return ActionResult.fail("That bench is full.")
	return ActionResult.success()

func apply(state: GameState) -> void:
	(state as TableGameState).play_hand_to_bench(target_player_id, card_view)

func description() -> String:
	return "Play selected card to P%d Bench" % target_player_id
