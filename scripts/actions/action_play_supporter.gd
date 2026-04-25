class_name ActionPlaySupporter
extends GameAction
## Plays a Supporter (a Trainer card with trainer_kind == SUPPORTER).  Only
## one Supporter may be played per turn; the Manager owns the
## supporter_played_this_turn flag, which the turn system clears each turn.
## Supporter goes to the discard after resolving.

var player_id: int = 0
var card: TrainerCardData = null


func _init(pid: int, supporter_card: TrainerCardData) -> void:
	player_id = pid
	card      = supporter_card


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No supporter card specified.")
	if card.trainer_kind != TrainerCardData.TrainerKind.SUPPORTER:
		return ActionResult.fail("Card is not a Supporter.")
	if manager.game_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Supporter is not in your hand.")
	if not manager.can_play_supporter(player_id):
		return ActionResult.fail("Cannot play a Supporter this turn.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	manager.game_position.put_in_discard(player_id, card)
	manager.supporter_played_this_turn[player_id] = true


func description() -> String:
	var name := card.display_name if card != null else "Supporter"
	return "P%d plays supporter %s" % [player_id, name]
