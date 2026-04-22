class_name ActionPlayItem
extends GameAction
## Plays an Item (a Trainer card with trainer_kind == ITEM) from hand.  The
## card resolves its effect and then goes to the player's discard pile.
##
## Effect dispatch hangs off TrainerCardData.rules_text / a future effect_key
## system — this action is only responsible for moving the card between
## GamePosition lists in accordance with the four-system contract.

var player_id: int = 0
var card: TrainerCardData = null


func _init(pid: int, item_card: TrainerCardData) -> void:
	player_id = pid
	card      = item_card


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No item card specified.")
	if card.trainer_kind != TrainerCardData.TrainerKind.ITEM:
		return ActionResult.fail("Card is not an Item.")
	if manager.game_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Item is not in your hand.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	manager.game_position.put_in_discard(player_id, card)


func description() -> String:
	var name := card.display_name if card != null else "Item"
	return "P%d plays item %s" % [player_id, name]
