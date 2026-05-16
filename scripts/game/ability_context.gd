class_name AbilityContext
extends RefCounted
## Data context passed to AbilityEffectRegistry handlers when a Poké-Power is
## activated or when a Poké-Body fires off a game-event hook.  Parallel to
## TrainerContext.
##
## Phase order in AbilityResolver.try_activate() (Poké-Powers only):
##   1. VALIDATE   — sync precondition check; handlers may call
##                   fail_validation() to reject the activation.
##   2. PROMPT     — handler returns an AbilityQuery; resolver awaits the
##                   player's response and stores it in query_response.
##   3. APPLY      — handler mutates state.  Reads query_response if needed.
##   4. POST_APPLY — log lines, signal emissions, deferred cleanup.
##
## Passive Poké-Bodies fire as static helper calls from gameplay code (mirroring
## StadiumEffects / ToolEffects).  They don't go through the resolver phases —
## the registry stores their lookup, and the helper queries the params.

var manager                              ## ManagerSystem node
var player_id: int = 0
var source_slot: String = ""             ## Slot housing the Pokémon whose ability fires.
var ability: AbilityData = null

## Convenience copy of ability.effect_params so handlers don't have to null-guard.
var params: Dictionary = {}

## Populated by AbilityResolver when a PROMPT handler returns a query.
var query_response: Variant = null

## Per-resolution scratch space (coin-flip results, computed counts, etc).
var runtime: Dictionary = {}

## VALIDATE handlers set this via fail_validation() to reject activation.
var validation_failure: String = ""


func fail_validation(reason: String) -> void:
	validation_failure = reason
