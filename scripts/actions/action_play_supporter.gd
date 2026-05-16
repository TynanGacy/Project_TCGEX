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
	## Wave 6 — Armaldo "Primal Veil": Supporter plays locked by either
	## player's Active Armaldo.
	if AbilityEffects.play_locked_for_player(manager, player_id, "SUPPORTER"):
		return ActionResult.fail("Supporter plays are locked by a Poké-Body in play.")
	var effect_check := TrainerResolver.validate(card, manager, player_id)
	if not effect_check.ok:
		return effect_check
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	# The Supporter card stays in the shared supporter slot until end-of-turn
	# cleanup discards it to its owner's pile. Mirrors the Stadium pattern.
	# If a Supporter were somehow still in the slot (shouldn't be — only one
	# per turn), discard it first to its owner's pile.
	if manager.active_supporter != null:
		manager.game_position.put_in_discard(
			manager.active_supporter_owner, manager.active_supporter
		)
	manager.active_supporter       = card
	manager.active_supporter_owner = player_id
	manager.supporter_changed.emit(card, player_id)
	manager.supporter_played_this_turn[player_id] = true
	if manager.trainer_resolver != null:
		manager.trainer_resolver.dispatch(card, manager, player_id)


func description() -> String:
	var name := card.display_name if card != null else "Supporter"
	return "P%d plays supporter %s" % [player_id, name]
