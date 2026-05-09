class_name TrainerContext
extends RefCounted
## Data context passed to TrainerEffectRegistry handlers when a Trainer card
## (Item, Supporter, Stadium, Tool) resolves.  Mirrors AttackContext's role
## in the attack pipeline.
##
## Phase order in TrainerResolver.dispatch():
##   1. VALIDATE   — sync precondition check.  Handler may call
##                   fail_validation() to reject the play before the card
##                   leaves hand.
##   2. PROMPT     — handler returns a TrainerQuery; resolver awaits the
##                   response and stores it in query_response.
##   3. APPLY      — handler mutates state.  Reads query_response if needed.
##   4. POST_APPLY — log lines, signal emissions, deferred cleanup.

var manager                              ## ManagerSystem node
var player_id: int = 0
var card: TrainerCardData = null

## Convenience copy of card.effect_params so handlers don't have to null-guard.
var params: Dictionary = {}

## Populated by TrainerResolver when a PROMPT handler returns a query.
var query_response: Variant = null

## Per-resolution scratch space for handler internal state passed between
## PROMPT and APPLY (e.g. coin-flip results, computed counts).  Keyed by
## handler convention; not inspected by the resolver.
var runtime: Dictionary = {}

## VALIDATE handlers set this via fail_validation() to reject the play.
var validation_failure: String = ""


## Reject the play during VALIDATE phase.  No-op outside VALIDATE.
func fail_validation(reason: String) -> void:
	validation_failure = reason
