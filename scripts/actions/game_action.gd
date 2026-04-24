class_name GameAction
extends RefCounted
## Base class for all Game_Actions.
##
## A Game_Action is a DECLARATIVE description of something that should happen
## (play a Pokemon, attach energy, attack, etc.).  It has no executive power:
##   - validate(manager) checks legality against current state.
##   - apply(manager)    performs the mutation via the Manager's subsystems.
##   - description()     returns a human-readable log line.
##
## Actions never mutate state directly.  They call into manager.game_position
## and manager.board_position so the Manager remains the single point of
## dispatch.

func validate(_manager) -> ActionResult:
	return ActionResult.success()

func apply(_manager) -> void:
	pass

func description() -> String:
	return "GameAction"

## Returns the board slot IDs whose in-play Pokemon state changed as a result
## of apply().  The Manager emits pokemon_state_changed for each slot so the
## scene layer (and future online authority) can react without inspecting
## concrete action types.  Override in any action that mutates a PokemonInstance.
func affected_slots() -> Array[String]:
	return []
