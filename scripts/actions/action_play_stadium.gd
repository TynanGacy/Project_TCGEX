class_name ActionPlayStadium
extends GameAction
## Plays a Stadium (a Trainer card with trainer_kind == STADIUM).  Only one
## Stadium is in play at a time across both players; playing a new one sends
## the previously-active Stadium to its owner's discard.  The Manager owns
## the active_stadium / active_stadium_owner pair.

var player_id: int = 0
var card: TrainerCardData = null


func _init(pid: int, stadium_card: TrainerCardData) -> void:
	player_id = pid
	card      = stadium_card


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No stadium card specified.")
	if card.trainer_kind != TrainerCardData.TrainerKind.STADIUM:
		return ActionResult.fail("Card is not a Stadium.")
	if manager.game_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Stadium is not in your hand.")
	## A Stadium with the same card_id already in play cannot be replaced
	## (classic "same-name Stadium" rule).
	if manager.active_stadium != null and manager.active_stadium.card_id == card.card_id:
		return ActionResult.fail("A Stadium with the same name is already in play.")
	var effect_check := TrainerResolver.validate(card, manager, player_id)
	if not effect_check.ok:
		return effect_check
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	if manager.active_stadium != null:
		manager.game_position.put_in_discard(
			manager.active_stadium_owner, manager.active_stadium
		)
	manager.active_stadium       = card
	manager.active_stadium_owner = player_id
	manager.stadium_changed.emit(card, player_id)
	if manager.trainer_resolver != null:
		manager.trainer_resolver.dispatch(card, manager, player_id)


func description() -> String:
	var name := card.display_name if card != null else "Stadium"
	return "P%d plays stadium %s" % [player_id, name]
