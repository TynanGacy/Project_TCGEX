class_name ActionTakePrize
extends GameAction
## Takes a specific prize card by slot index during prize selection phase.
## The Manager sets prize_selection_phase_for when a KO occurs; this action
## clears it.  After the prize is taken, the Manager checks whether the KO'd
## Pokémon's owner needs to promote.

var player_id: int
var prize_index: int


func _init(pid: int, idx: int) -> void:
	player_id   = pid
	prize_index = idx


func validate(manager) -> ActionResult:
	if manager.prize_selection_phase_for != player_id:
		return ActionResult.fail("Not your prize selection phase.")
	if prize_index < 0 or prize_index >= GamePosition.MAX_PRIZES:
		return ActionResult.fail("Invalid prize index %d." % prize_index)
	if (manager.game_position.prizes[player_id] as Array)[prize_index] == null:
		return ActionResult.fail("Prize slot %d is empty." % (prize_index + 1))
	return ActionResult.success()


func apply(manager) -> void:
	var card: CardData = manager.game_position.take_prize(player_id, prize_index)
	if card != null:
		manager.game_position.put_in_hand(player_id, card)
		manager.log_message.emit("[Prize] P%d takes prize %d." % [player_id, prize_index + 1])

	var defender: int = manager._ko_defender
	manager.prize_selection_phase_for = -1
	manager._ko_defender = -1
	manager.prize_taken.emit(player_id)

	if manager.game_position.prizes_remaining(player_id) == 0:
		manager.log_message.emit("[WIN] P%d takes their last prize and wins!" % player_id)
		manager.current_phase = Phase.ENDED
		manager.phase_changed.emit(manager.current_phase)
		manager.game_won.emit(player_id)
		return

	manager.phase_changed.emit(manager.current_phase)
	if defender >= 0:
		manager._check_promotion_needed(defender)


func description() -> String:
	return "P%d takes prize %d" % [player_id, prize_index + 1]


func affected_slots() -> Array[String]:
	return []
