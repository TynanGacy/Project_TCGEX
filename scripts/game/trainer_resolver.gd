class_name TrainerResolver
extends Node
## Async pipeline orchestrator for Trainer-card resolution.  Created as a
## child of ManagerSystem in _ready().  Parallel to AttackResolver.
##
## Validation runs synchronously from Action*.validate() via the static
## validate() helper.  Once an action commits and the card has moved out of
## hand, dispatch() is invoked from Action*.apply() and the pipeline runs
## as a coroutine, awaiting at PROMPT for player input.

enum Phase {
	VALIDATE,
	PROMPT,
	APPLY,
	POST_APPLY,
}

signal pipeline_completed
signal player_query_requested(query: TrainerQuery)
signal player_query_resolved(response: Variant)

var _is_resolving: bool = false


func is_resolving() -> bool:
	return _is_resolving


## UI / external code calls this to feed a query response back into the
## paused pipeline.  Mirror of AttackResolver.resolve_query().
func resolve_query(response: Variant) -> void:
	player_query_resolved.emit(response)


## Helper for handlers that need to ask the player something mid-APPLY.
## Emits the query and awaits the player's response.
##
## Use this for multi-step picks (e.g. Energy Switch picks a source Pokémon,
## then a basic energy on it, then a destination Pokémon).
func ask(query: TrainerQuery) -> Variant:
	player_query_requested.emit(query)
	return await player_query_resolved


## Synchronous precondition check.  Returns ActionResult.success() unless
## the registered VALIDATE handler called ctx.fail_validation().  Cards
## without an effect_key, or with an unregistered key, are always allowed
## (legacy compatibility — they will fall through to a no-op apply).
static func validate(card: TrainerCardData, manager, player_id: int) -> ActionResult:
	if card == null or card.effect_key == "":
		return ActionResult.success()
	if not TrainerEffectRegistry.has_definition(card.effect_key):
		return ActionResult.success()
	var ctx := _build_ctx(card, manager, player_id)
	TrainerEffectRegistry.dispatch_phase(card.effect_key, Phase.VALIDATE, ctx)
	if ctx.validation_failure != "":
		return ActionResult.fail(ctx.validation_failure)
	return ActionResult.success()


## Async pipeline.  Spawned without await from Action*.apply(); callers that
## need to know when resolution finishes should listen for pipeline_completed
## (see ManagerSystem.request_action_async).
func dispatch(card: TrainerCardData, manager, player_id: int) -> void:
	if card == null or card.effect_key == "":
		return
	if not TrainerEffectRegistry.has_definition(card.effect_key):
		return
	assert(not _is_resolving, "TrainerResolver: re-entrant call")
	_is_resolving = true

	var ctx := _build_ctx(card, manager, player_id)

	var query: TrainerQuery = TrainerEffectRegistry.get_query(card.effect_key, ctx)
	if query != null:
		player_query_requested.emit(query)
		ctx.query_response = await player_query_resolved

	## Phase handlers may be coroutines (use await for additional ask() calls);
	## await them so POST_APPLY does not race ahead of an unfinished APPLY.
	await _await_phase(card.effect_key, Phase.APPLY, ctx)
	await _await_phase(card.effect_key, Phase.POST_APPLY, ctx)

	## Trainer effects can vacate active slots (Mr. Briney's Compassion).
	## Re-run the manager's promotion check now that the pipeline is done.
	if manager != null and manager.has_method("_check_all_promotions_needed"):
		manager._check_all_promotions_needed()

	_is_resolving = false
	pipeline_completed.emit()


## Calls the registered handler for [phase] and awaits its return.  If the
## handler is a regular (non-coroutine) Callable, the await resolves
## immediately.  If it is a coroutine (uses await internally, e.g. via
## ask()), this suspends until it finishes.
func _await_phase(key: String, phase: int, ctx: TrainerContext) -> void:
	if not TrainerEffectRegistry.has_definition(key):
		return
	var def = TrainerEffectRegistry._definitions[key]
	if not def.phase_handlers.has(phase):
		return
	await def.phase_handlers[phase].call(ctx)


static func _build_ctx(card: TrainerCardData, manager, player_id: int) -> TrainerContext:
	var ctx := TrainerContext.new()
	ctx.manager   = manager
	ctx.player_id = player_id
	ctx.card      = card
	if card.effect_params != null:
		ctx.params = card.effect_params.duplicate(true)
	return ctx
