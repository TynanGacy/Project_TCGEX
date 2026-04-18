class_name ActionTakePrize
extends GameAction
## Moves one prize card from a player's prize zone into their hand.
##
## Pass a specific CardInstance as [target] to let the player choose which
## prize to take.  Omit [target] (null) to fall back to prizes.front().

var target_card: CardInstance = null


func _init(pid: int, card: CardInstance = null) -> void:
	actor_id = pid
	target_card = card


func validate(state: GameState) -> ActionResult:
	var prizes := state.board.get_zone("p%d_prizes" % actor_id)
	if prizes.is_empty():
		return ActionResult.fail("No prize cards remaining for P%d." % actor_id)
	return ActionResult.success()


func apply(state: GameState) -> void:
	var prizes_zone_id := "p%d_prizes" % actor_id
	var prizes := state.board.get_zone(prizes_zone_id)
	if prizes.is_empty():
		return

	## Take the chosen card if it is still in the prizes zone; otherwise fall
	## back to the front of the array (legacy / auto-take path).
	var card: CardInstance
	if target_card != null and prizes.has(target_card):
		card = target_card
	else:
		card = prizes.front() as CardInstance

	state.board.move_card(card, "p%d_hand" % actor_id)

	var player := state.get_player(actor_id)
	if player:
		player.prizes_remaining = state.board.get_zone(prizes_zone_id).size()


func description() -> String:
	return "P%d takes a prize card" % actor_id
