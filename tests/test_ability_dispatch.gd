extends GutTest
## Smoke tests for the Poké-Power / Poké-Body dispatch shell.  Verifies the
## registry, resolver, and ActionUseAbility wiring without depending on any
## real handler implementations.  Real handlers (Day 3 / Day 4 waves) will
## land their own per-key tests in subsequent commits.

const _ABILITY_SCRIPT  := preload("res://scripts/cards/ability_data.gd")
const _POKEMON_SCRIPT  := preload("res://scripts/cards/pokemon_card_data.gd")


func before_each() -> void:
	AbilityEffectRegistry.clear()


func after_each() -> void:
	AbilityEffectRegistry.clear()


func _make_ability(kind: int, key: String, params: Dictionary = {}) -> AbilityData:
	var abil: AbilityData = _ABILITY_SCRIPT.new()
	abil.ability_name  = "Test Ability"
	abil.kind          = kind
	abil.effect_key    = key
	abil.effect_params = params
	return abil


func _make_pokemon_with_ability(ability: AbilityData) -> PokemonCardData:
	var card: PokemonCardData = _POKEMON_SCRIPT.new()
	card.card_id      = "TEST_pokemon_ability"
	card.display_name = "Test Mon"
	card.card_type    = CardData.CardType.POKEMON
	card.stage        = PokemonCardData.Stage.BASIC
	card.pokemon_type = PokemonCardData.EnergyType.COLORLESS
	card.hp_max       = 60
	card.abilities    = [ability]
	return card


## ── Registry ────────────────────────────────────────────────────────────────

func test_registry_register_and_lookup() -> void:
	var def := AbilityEffectDefinition.single(
		AbilityResolver.Phase.APPLY,
		func(_ctx: AbilityContext) -> void: pass
	)
	AbilityEffectRegistry.register_def("k1", def)
	assert_true(AbilityEffectRegistry.has_definition("k1"))
	assert_false(AbilityEffectRegistry.has_definition("k2"))
	assert_false(AbilityEffectRegistry.has_definition(""))


func test_passive_meta_lookup() -> void:
	AbilityEffectRegistry.register_def("body_passive_test",
		AbilityEffectDefinition.passive({"damage_taken_delta": -10})
	)
	var meta := AbilityEffectRegistry.passive_meta("body_passive_test")
	assert_eq(int(meta.get("damage_taken_delta", 0)), -10)
	assert_eq(AbilityEffectRegistry.passive_meta("unregistered"), {})


## ── Resolver: synchronous validation ────────────────────────────────────────

func test_validate_passes_when_no_handler() -> void:
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "")
	var result := AbilityResolver.validate(abil, "p0_active1", null, 0)
	assert_true(result.ok, "Empty effect_key should auto-pass validation.")


func test_validate_passes_when_unregistered_key() -> void:
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "missing_key")
	var result := AbilityResolver.validate(abil, "p0_active1", null, 0)
	assert_true(result.ok, "Unregistered key should auto-pass validation.")


func test_validate_rejects_when_handler_fails() -> void:
	AbilityEffectRegistry.register_def("rejector", AbilityEffectDefinition.single(
		AbilityResolver.Phase.VALIDATE,
		func(ctx: AbilityContext) -> void: ctx.fail_validation("nope")
	))
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "rejector")
	var result := AbilityResolver.validate(abil, "p0_active1", null, 0)
	assert_false(result.ok)
	assert_eq(result.reason, "nope")


## ── Resolver: async dispatch ────────────────────────────────────────────────

func test_dispatch_runs_apply_and_post_apply_in_order() -> void:
	var calls: Array = []
	var def := AbilityEffectDefinition.new()
	def.phase_handlers[AbilityResolver.Phase.APPLY] = func(_ctx: AbilityContext) -> void:
		calls.append("apply")
	def.phase_handlers[AbilityResolver.Phase.POST_APPLY] = func(_ctx: AbilityContext) -> void:
		calls.append("post")
	AbilityEffectRegistry.register_def("ordered", def)

	var resolver := AbilityResolver.new()
	add_child_autoqfree(resolver)
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "ordered")
	resolver.dispatch(abil, "p0_active1", null, 0)
	if resolver.is_resolving():
		await resolver.pipeline_completed
	assert_eq(calls, ["apply", "post"])
	assert_false(resolver.is_resolving())


func test_dispatch_passes_params_to_context() -> void:
	var captured: Array = []
	AbilityEffectRegistry.register_def("captures", AbilityEffectDefinition.single(
		AbilityResolver.Phase.APPLY,
		func(ctx: AbilityContext) -> void: captured.append(ctx.params.duplicate(true))
	))
	var resolver := AbilityResolver.new()
	add_child_autoqfree(resolver)
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "captures", {"x": 7})
	resolver.dispatch(abil, "p0_active1", null, 0)
	if resolver.is_resolving():
		await resolver.pipeline_completed
	assert_eq(captured.size(), 1)
	assert_eq(captured[0], {"x": 7})


func test_dispatch_awaits_player_query_response() -> void:
	var seen_response: Array = []
	var def := AbilityEffectDefinition.new()
	def.phase_handlers[AbilityResolver.Phase.PROMPT] = func(ctx: AbilityContext) -> AbilityQuery:
		var q := AbilityQuery.new()
		q.player_id = ctx.player_id
		q.prompt = "Pick something"
		return q
	def.phase_handlers[AbilityResolver.Phase.APPLY] = func(ctx: AbilityContext) -> void:
		seen_response.append(ctx.query_response)
	AbilityEffectRegistry.register_def("with_query", def)

	var resolver := AbilityResolver.new()
	add_child_autoqfree(resolver)
	var emitted_queries: Array = []
	resolver.player_query_requested.connect(func(q: AbilityQuery) -> void:
		emitted_queries.append(q)
		resolver.resolve_query.call_deferred("chosen_target")
	)
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "with_query")
	resolver.dispatch(abil, "p0_active1", null, 0)
	if resolver.is_resolving():
		await resolver.pipeline_completed
	assert_eq(emitted_queries.size(), 1)
	assert_eq(emitted_queries[0].prompt, "Pick something")
	assert_eq(seen_response, ["chosen_target"])


## ── ActionUseAbility integration ────────────────────────────────────────────

func test_action_use_ability_rejects_when_already_used() -> void:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	## Build a Pokémon with a registered Poké-Power and place it active.
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "noop")
	AbilityEffectRegistry.register_def("noop", AbilityEffectDefinition.single(
		AbilityResolver.Phase.APPLY,
		func(_ctx: AbilityContext) -> void: pass
	))
	var card := _make_pokemon_with_ability(abil)
	var inst := PokemonInstance.create(card, 0)
	mgr.board_position.place("p0_active1", inst)
	mgr.current_player = 0
	mgr.current_phase  = 1  ## Phase.MAIN
	mgr.turn_number    = 3
	mgr.first_player   = 0

	## First activation succeeds.
	var r1 := await mgr.request_action_async(ActionUseAbility.new(0, "p0_active1", 0))
	assert_true(r1.ok, "First Poké-Power activation should succeed.")
	assert_true(inst.power_used_this_turn,
		"power_used_this_turn should be set after activation.")
	## Second activation in same turn rejected.
	var r2 := await mgr.request_action_async(ActionUseAbility.new(0, "p0_active1", 0))
	assert_false(r2.ok, "Second activation in same turn should fail.")


func test_action_use_ability_rejects_poke_body() -> void:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	var body_abil := _make_ability(AbilityData.AbilityKind.POKE_BODY, "passive")
	var card := _make_pokemon_with_ability(body_abil)
	var inst := PokemonInstance.create(card, 0)
	mgr.board_position.place("p0_active1", inst)
	mgr.current_player = 0
	mgr.current_phase  = 1
	mgr.turn_number    = 3
	mgr.first_player   = 0

	var r := await mgr.request_action_async(ActionUseAbility.new(0, "p0_active1", 0))
	assert_false(r.ok, "Poké-Bodies cannot be activated via ActionUseAbility.")


func test_action_use_ability_rejects_when_asleep() -> void:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	var abil := _make_ability(AbilityData.AbilityKind.POKE_POWER, "noop2")
	AbilityEffectRegistry.register_def("noop2", AbilityEffectDefinition.single(
		AbilityResolver.Phase.APPLY,
		func(_ctx: AbilityContext) -> void: pass
	))
	var card := _make_pokemon_with_ability(abil)
	var inst := PokemonInstance.create(card, 0)
	inst.special_conditions.append(PokemonInstance.SpecialCondition.ASLEEP)
	mgr.board_position.place("p0_active1", inst)
	mgr.current_player = 0
	mgr.current_phase  = 1
	mgr.turn_number    = 3
	mgr.first_player   = 0

	var r := await mgr.request_action_async(ActionUseAbility.new(0, "p0_active1", 0))
	assert_false(r.ok, "Asleep Pokémon cannot activate Poké-Powers.")
