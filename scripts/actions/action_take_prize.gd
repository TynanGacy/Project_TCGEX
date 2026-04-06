class_name ActionTakePrize
extends GameAction
## Moves one prize card from a player's prize zone into their hand.
##
## This action is triggered automatically by TurnController after a knockout —
## it is never submitted directly by the player.  The actor_id here is the
## player who SCORED the knockout (and therefore earns the prize), not the
## player who lost the Pokemon.
##
## Because it is system-generated mid-turn, the normal _gate_action check is
## bypassed in TurnController for this action type.


func _init(pid: int) -> void:
	actor_id = pid


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

	## Move the top prize card (back of the array) to the player's hand.
	var card := prizes.back() as CardInstance
	state.board.move_card(card, "p%d_hand" % actor_id)

	## Keep the player's prize tracker in sync with the actual zone count.
	var player := state.get_player(actor_id)
	if player:
		player.prizes_remaining = state.board.get_zone(prizes_zone_id).size()


func description() -> String:
	return "P%d takes a prize card" % actor_id
