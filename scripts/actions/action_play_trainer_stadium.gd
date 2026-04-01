class_name ActionPlayTrainerStadium
extends GameAction

## Plays a Stadium trainer card into the shared stadium zone.
## If a different Stadium is already in play it is discarded to its owner's
## discard pile before the new one is placed.
## Playing the exact same Stadium that is already in play is not allowed.

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
	if trainer_data.trainer_kind != TrainerCardData.TrainerKind.STADIUM:
		return ActionResult.fail("Card is not a Stadium card.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Card is not in your hand.")

	# Cannot replace a Stadium with the same named card.
	var existing := state.board.get_zone("stadium")
	if not existing.is_empty():
		var current := existing[0] as CardInstance
		if current.data.card_id == card.data.card_id:
			return ActionResult.fail("That Stadium is already in play.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	# Discard the current Stadium (if any) to its owner's discard pile.
	var existing := state.board.get_zone("stadium")
	if not existing.is_empty():
		var old_stadium := existing[0] as CardInstance
		state.board.move_card(old_stadium, "p%d_discard" % old_stadium.owner_id)

	state.board.move_card(card, "stadium")
	state.get_player(actor_id).mark_stadium_played()
	# TODO: trigger stadium effect via effect system


func description() -> String:
	if card != null and card.data != null:
		return "Play Stadium: %s" % card.data.display_name
	return "Play Stadium"
