class_name AbilityResolver
extends Node
## Async pipeline orchestrator for Poké-Power activation.  Created as a child
## of ManagerSystem in _ready().  Parallel to TrainerResolver / AttackResolver.
##
## Poké-Powers go through the full pipeline (VALIDATE → PROMPT → APPLY →
## POST_APPLY).  Validation runs synchronously from
## ActionUseAbility.validate() via the static validate() helper; dispatch()
## runs as a coroutine that awaits at PROMPT for player input.
##
## Poké-Bodies are passive.  They do NOT go through this resolver — static
## helpers (e.g. AbilityEffects.damage_modifier_for_target) read
## AbilityEffectRegistry.passive_meta and the relevant Pokémon's effect_params
## directly.  Poké-Body effect_keys still register a definition (often
## passive-only) so the helper can detect them.

enum Phase {
	VALIDATE,
	PROMPT,
	APPLY,
	POST_APPLY,
}

signal pipeline_completed
signal player_query_requested(query: AbilityQuery)
signal player_query_resolved(response: Variant)

var _is_resolving: bool = false


func is_resolving() -> bool:
	return _is_resolving


func resolve_query(response: Variant) -> void:
	player_query_resolved.emit(response)


## Helper for handlers that need to ask the player something mid-APPLY.
func ask(query: AbilityQuery) -> Variant:
	player_query_requested.emit(query)
	return await player_query_resolved


## Synchronous precondition check.  Returns ActionResult.success() unless the
## registered VALIDATE handler called ctx.fail_validation().  Abilities with
## no effect_key (or unregistered keys) are auto-allowed (legacy fall-through).
##
## [source_slot] is the slot of the Pokémon whose ability is being activated.
## [ability] is the specific AbilityData entry (a Pokémon may carry more than
## one — pass the chosen entry).
static func validate(ability: AbilityData, source_slot: String, manager,
		player_id: int) -> ActionResult:
	if ability == null or ability.effect_key == "":
		return ActionResult.success()
	if not AbilityEffectRegistry.has_definition(ability.effect_key):
		return ActionResult.success()
	## Wave 3 suppression: Slaking "Lazy" / Muk ex "Toxic Gas".  Resolved
	## here so the action is rejected before the resolver spins up.
	if manager != null and source_slot != "":
		var carrier: PokemonInstance = manager.board_position.get_instance(source_slot)
		if AbilityEffects.is_power_suppressed(carrier, manager):
			return ActionResult.fail(
				"This Poké-Power is suppressed by an opposing ability."
			)
	var ctx := _build_ctx(ability, source_slot, manager, player_id)
	AbilityEffectRegistry.dispatch_phase(ability.effect_key, Phase.VALIDATE, ctx)
	if ctx.validation_failure != "":
		return ActionResult.fail(ctx.validation_failure)
	return ActionResult.success()


## Async pipeline for activated Poké-Powers.  Spawned without await from
## ActionUseAbility.apply(); callers that need to know when resolution
## finishes should listen for pipeline_completed.
func dispatch(ability: AbilityData, source_slot: String, manager,
		player_id: int) -> void:
	if ability == null or ability.effect_key == "":
		return
	if not AbilityEffectRegistry.has_definition(ability.effect_key):
		return
	assert(not _is_resolving, "AbilityResolver: re-entrant call")
	_is_resolving = true

	var ctx := _build_ctx(ability, source_slot, manager, player_id)

	var query: AbilityQuery = await AbilityEffectRegistry.get_query(ability.effect_key, ctx)
	if query != null:
		player_query_requested.emit(query)
		ctx.query_response = await player_query_resolved

	await _await_phase(ability.effect_key, Phase.APPLY, ctx)
	await _await_phase(ability.effect_key, Phase.POST_APPLY, ctx)

	## Abilities can move Pokémon between slots or KO them; re-run the
	## manager's promotion check after the pipeline completes (same pattern as
	## TrainerResolver).
	if manager != null and manager.has_method("_check_all_promotions_needed"):
		manager._check_all_promotions_needed()

	_is_resolving = false
	pipeline_completed.emit()


func _await_phase(key: String, phase: int, ctx: AbilityContext) -> void:
	if not AbilityEffectRegistry.has_definition(key):
		return
	var def := AbilityEffectRegistry.get_definition(key)
	if not def.phase_handlers.has(phase):
		return
	await def.phase_handlers[phase].call(ctx)


static func _build_ctx(ability: AbilityData, source_slot: String, manager,
		player_id: int) -> AbilityContext:
	var ctx := AbilityContext.new()
	ctx.manager     = manager
	ctx.player_id   = player_id
	ctx.source_slot = source_slot
	ctx.ability     = ability
	if ability.effect_params != null:
		ctx.params = ability.effect_params.duplicate(true)
	return ctx
