class_name ActionPromote
extends GameAction
## Moves a bench Pokémon into an empty active slot during a mandatory
## promotion phase (after a KO).  Only valid while manager.promotion_phase_for
## equals this player; the Manager sets/clears that flag.

var player_id: int
var from_slot: String
var to_slot: String


func _init(pid: int, from_s: String, to_s: String) -> void:
	player_id = pid
	from_slot = from_s
	to_slot   = to_s


func validate(manager) -> ActionResult:
	if manager.promotion_phase_for != player_id:
		return ActionResult.fail("Not your promotion phase.")
	if not manager.board_position.has_slot(from_slot):
		return ActionResult.fail("Unknown source slot '%s'." % from_slot)
	if manager.board_position.player_of(from_slot) != player_id:
		return ActionResult.fail("Source slot does not belong to you.")
	if "bench" not in from_slot:
		return ActionResult.fail("Can only promote from the bench.")
	if manager.board_position.get_instance(from_slot) == null:
		return ActionResult.fail("No Pokémon in bench slot.")
	if not manager.board_position.has_slot(to_slot):
		return ActionResult.fail("Unknown target slot '%s'." % to_slot)
	if manager.board_position.player_of(to_slot) != player_id:
		return ActionResult.fail("Target slot does not belong to you.")
	if "active" not in to_slot:
		return ActionResult.fail("Must promote to an active slot.")
	if manager.board_position.get_instance(to_slot) != null:
		return ActionResult.fail("Target active slot is not empty.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.board_position.move(from_slot, to_slot)
	manager.promotion_phase_for = -1
	manager.phase_changed.emit(manager.current_phase)
	manager.promotion_done.emit(player_id, to_slot)
	manager._check_promotion_needed(player_id)


func description() -> String:
	return "P%d promotes %s → %s" % [player_id, from_slot, to_slot]


func affected_slots() -> Array[String]:
	return [from_slot, to_slot]
