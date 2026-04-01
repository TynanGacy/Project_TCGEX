class_name ActionPlayTrainerSupporter
extends GameAction

## Plays a Supporter trainer card from hand to the discard pile.
## Only one Supporter may be played per turn.
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
	if trainer_data.trainer_kind != TrainerCardData.TrainerKind.SUPPORTER:
		return ActionResult.fail("Card is not a Supporter card.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Card is not in your hand.")

	var player := state.get_player(actor_id)
	if not player.can_play_supporter():
		return ActionResult.fail("Already played a Supporter this turn.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	state.board.move_card(card, "p%d_discard" % actor_id)
	state.get_player(actor_id).mark_supporter_played()
	# TODO: trigger card effect via effect system


func description() -> String:
	if card != null and card.data != null:
		return "Play Supporter: %s" % card.data.display_name
	return "Play Supporter"
