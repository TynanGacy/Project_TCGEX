class_name ActionPlayTrainerItem
extends GameAction

## Plays an Item trainer card from hand to the discard pile.
## Items have no per-turn play limit.
## Effect resolution is deferred to a future effect system.

var card: CardInstance


func _init(pid: int, trainer_card: CardInstance) -> void:
	actor_id = pid
	card = trainer_card


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Can only play Trainer cards during MAIN phase.")

	if card == null:
		return ActionResult.fail("No card specified.")

	if not (card.data is TrainerCardData):
		return ActionResult.fail("Card is not a Trainer card.")

	var trainer_data := card.data as TrainerCardData
	if trainer_data.trainer_kind != TrainerCardData.TrainerKind.ITEM:
		return ActionResult.fail("Card is not an Item card.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Card is not in your hand.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	state.board.move_card(card, "p%d_discard" % actor_id)
	# TODO: trigger card effect via effect system


func description() -> String:
	if card != null and card.data != null:
		return "Play Item: %s" % card.data.display_name
	return "Play Item"
