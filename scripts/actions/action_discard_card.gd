class_name ActionDiscardCard
extends GameAction

var card: CardInstance


func _init(pid: int, target_card: CardInstance) -> void:
	actor_id = pid
	card = target_card


func validate(state: GameState) -> ActionResult:
	if card == null:
		return ActionResult.fail("No card specified")
	var zone_id := state.board.find_card_location(card)
	if zone_id == "":
		return ActionResult.fail("Card is not in play")
	if card.controller_id != actor_id:
		return ActionResult.fail("Cannot discard a card you do not control")
	return ActionResult.success()


func apply(state: GameState) -> void:
	state.board.move_card(card, "p%d_discard" % actor_id)


func description() -> String:
	if card != null and card.data != null:
		return "Discard %s" % card.data.display_name
	return "Discard card"
