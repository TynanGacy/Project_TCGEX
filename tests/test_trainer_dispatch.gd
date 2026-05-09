extends GutTest
## Smoke tests for the trainer-effect dispatch shell.
##
## Verifies the registry, resolver, and Action wiring without depending on
## any real handler implementations.  Real handlers (Potion, Switch, Birch,
## etc.) get their own per-key tests in subsequent PRs.

const _ITEM_SCRIPT := preload("res://scripts/cards/trainer_card_data.gd")


func _make_card(kind: int, key: String, params: Dictionary = {}) -> TrainerCardData:
	var card: TrainerCardData = _ITEM_SCRIPT.new()
	card.card_id      = "TEST_trainer_%d" % kind
	card.display_name = "Test Trainer"
	card.card_type    = CardData.CardType.TRAINER
	card.trainer_kind = kind
	card.effect_key   = key
	card.effect_params = params
	return card


func before_each() -> void:
	TrainerEffectRegistry.clear()


func after_each() -> void:
	TrainerEffectRegistry.clear()


func test_registry_register_and_lookup() -> void:
	var def := TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(_ctx: TrainerContext) -> void: pass
	)
	TrainerEffectRegistry.register_def("k1", def)
	assert_true(TrainerEffectRegistry.has_definition("k1"))
	assert_false(TrainerEffectRegistry.has_definition("k2"))
	assert_false(TrainerEffectRegistry.has_definition(""))


func test_dispatch_phase_invokes_handler() -> void:
	var calls: Array = []
	TrainerEffectRegistry.register_def("k1", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(_ctx: TrainerContext) -> void: calls.append("apply")
	))
	var ctx := TrainerContext.new()
	TrainerEffectRegistry.dispatch_phase("k1", TrainerResolver.Phase.APPLY, ctx)
	assert_eq(calls, ["apply"])
	# Unrelated phase should not fire.
	TrainerEffectRegistry.dispatch_phase("k1", TrainerResolver.Phase.POST_APPLY, ctx)
	assert_eq(calls, ["apply"])


func test_validate_passes_when_no_handler() -> void:
	var card := _make_card(TrainerCardData.TrainerKind.ITEM, "")
	var result := TrainerResolver.validate(card, null, 0)
	assert_true(result.ok, "Empty effect_key should auto-pass validation.")


func test_validate_passes_when_unregistered_key() -> void:
	var card := _make_card(TrainerCardData.TrainerKind.ITEM, "missing_key")
	var result := TrainerResolver.validate(card, null, 0)
	assert_true(result.ok, "Unregistered key should auto-pass validation.")


func test_validate_rejects_when_handler_fails() -> void:
	TrainerEffectRegistry.register_def("rejector", TrainerEffectDefinition.single(
		TrainerResolver.Phase.VALIDATE,
		func(ctx: TrainerContext) -> void: ctx.fail_validation("nope")
	))
	var card := _make_card(TrainerCardData.TrainerKind.ITEM, "rejector")
	var result := TrainerResolver.validate(card, null, 0)
	assert_false(result.ok)
	assert_eq(result.reason, "nope")


func test_dispatch_runs_apply_and_post_apply_in_order() -> void:
	var calls: Array = []
	var def := TrainerEffectDefinition.new()
	def.phase_handlers[TrainerResolver.Phase.APPLY] = func(_ctx: TrainerContext) -> void:
		calls.append("apply")
	def.phase_handlers[TrainerResolver.Phase.POST_APPLY] = func(_ctx: TrainerContext) -> void:
		calls.append("post")
	TrainerEffectRegistry.register_def("ordered", def)
	var resolver := TrainerResolver.new()
	add_child_autoqfree(resolver)
	var card := _make_card(TrainerCardData.TrainerKind.ITEM, "ordered")
	resolver.dispatch(card, null, 0)
	if resolver.is_resolving():
		await resolver.pipeline_completed
	assert_eq(calls, ["apply", "post"])
	assert_false(resolver.is_resolving())


func test_dispatch_passes_params_to_context() -> void:
	var captured: Array = []
	TrainerEffectRegistry.register_def("captures", TrainerEffectDefinition.single(
		TrainerResolver.Phase.APPLY,
		func(ctx: TrainerContext) -> void: captured.append(ctx.params.duplicate(true))
	))
	var resolver := TrainerResolver.new()
	add_child_autoqfree(resolver)
	var card := _make_card(TrainerCardData.TrainerKind.ITEM, "captures", {"x": 7})
	resolver.dispatch(card, null, 0)
	if resolver.is_resolving():
		await resolver.pipeline_completed
	assert_eq(captured.size(), 1)
	assert_eq(captured[0], {"x": 7})


func test_dispatch_awaits_player_query_response() -> void:
	var seen_response: Array = []
	var def := TrainerEffectDefinition.new()
	def.phase_handlers[TrainerResolver.Phase.PROMPT] = func(ctx: TrainerContext) -> TrainerQuery:
		var q := TrainerQuery.new()
		q.player_id = ctx.player_id
		q.prompt = "Pick something"
		return q
	def.phase_handlers[TrainerResolver.Phase.APPLY] = func(ctx: TrainerContext) -> void:
		seen_response.append(ctx.query_response)
	TrainerEffectRegistry.register_def("with_query", def)
	var resolver := TrainerResolver.new()
	add_child_autoqfree(resolver)
	var emitted_queries: Array = []
	resolver.player_query_requested.connect(func(q: TrainerQuery) -> void:
		emitted_queries.append(q)
		# Simulate UI response on the next frame — call_deferred so the
		# resolver has time to reach `await player_query_resolved` before
		# we emit the response.
		resolver.resolve_query.call_deferred("chosen_card_id")
	)
	var card := _make_card(TrainerCardData.TrainerKind.ITEM, "with_query")
	resolver.dispatch(card, null, 0)
	if resolver.is_resolving():
		await resolver.pipeline_completed
	assert_eq(emitted_queries.size(), 1)
	assert_eq(emitted_queries[0].prompt, "Pick something")
	assert_eq(seen_response, ["chosen_card_id"])
