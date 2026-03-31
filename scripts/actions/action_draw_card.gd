class_name ActionDrawCard
extends GameAction

var count: int = 1


func _init(pid: int, n: int = 1) -> void:
	actor_id = pid
	count = n


func validate(state: GameState) -> ActionResult:
	var deck_zone := "p%d_deck" % actor_id
	if state.board.count_cards_in_zone(deck_zone) == 0:
		return ActionResult.fail("Deck is empty")
	return ActionResult.success()


func apply(state: GameState) -> void:
	var player := state.get_player(actor_id)
	if player == null:
		return
	for i in count:
		if state.board.count_cards_in_zone("p%d_deck" % actor_id) == 0:
			break
		player.draw_card(state.board)


func description() -> String:
	return "Draw %d card(s)" % count
