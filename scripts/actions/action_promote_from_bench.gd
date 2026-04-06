class_name ActionPromoteFromBench
extends GameAction
## Moves a bench Pokemon into an empty active slot.
##
## This action covers two distinct scenarios:
##   1. Voluntary retreat (player manually promotes during MAIN phase).
##   2. Forced promotion after a knockout (can occur in any phase).
##
## The [forced] flag distinguishes them: when true, TurnController bypasses the
## normal turn-ownership gate so the OPPONENT's board can be fixed mid-turn.

var player_id: int  = -1   ## Whose board to promote on.
var bench_index: int = -1  ## Index into board.get_bench_cards(player_id).
var forced: bool = false    ## True when triggered by a knockout.


func _init(actor: int, p_id: int, bench_i: int, is_forced: bool = false) -> void:
	actor_id    = actor
	player_id   = p_id
	bench_index = bench_i
	forced      = is_forced


func validate(state: GameState) -> ActionResult:
	if actor_id != player_id and not forced:
		return ActionResult.fail("Can only promote cards on your own board.")

	if not forced:
		## Voluntary retreat is restricted to MAIN phase only.
		if state.phase != TurnPhase.Phase.MAIN:
			return ActionResult.fail("Voluntary promotion only allowed during MAIN phase.")

	if not state.can_promote_from_bench(player_id, bench_index):
		return ActionResult.fail("No valid bench Pokemon at index %d." % bench_index)

	return ActionResult.success()


func apply(state: GameState) -> void:
	state.promote_from_bench(player_id, bench_index)


func description() -> String:
	var label := "forced" if forced else "voluntary"
	return "P%d promotes Bench[%d] to Active (%s)" % [player_id, bench_index, label]
