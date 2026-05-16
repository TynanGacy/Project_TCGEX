extends GutTest
## Matrix test asserting every `AbilityEffects.BODY_*` / `POWER_*` constant
## resolves via AbilityEffectRegistry after the handlers node has registered.
## Catches the "added a constant, forgot to register a handler for it"
## failure mode — the dual of test_effect_registry_coverage, which catches
## "card JSON references a key with no handler."
##
## Behavioral assertions per key live in the wave-level test files
## (test_ability_wave1..4, test_baby_evolution, test_chain_of_events,
## test_special_energy_effects). This matrix is intentionally shallow.

var _ability_handlers: Node = null


func before_all() -> void:
	_ability_handlers = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers)


func after_all() -> void:
	if _ability_handlers != null:
		_ability_handlers.queue_free()


## All public effect_key constants the registry is expected to know about.
## Mirror of AbilityEffects.BODY_* / POWER_* constants — keep in sync.
const EXPECTED_KEYS: Array[String] = [
	## Wave 1 — passive Poké-Body patterns.
	"body_damage_reduction",
	"body_damage_increase_outgoing",
	"body_damage_taken_aura_active",
	"body_damage_reduction_from_types",
	"body_coin_gated_reduction",
	"body_status_immunity",
	"body_retaliate_damage",
	"body_retaliate_status",
	"body_between_turn_heal",
	"body_retreat_cost_override",
	"body_natural_cure",
	## Wave 2 patterns.
	"body_global_resistance_disable",
	"body_source_immunity",
	"body_bench_damage_immunity",
	"body_type_morph_from_energy",
	"body_opponent_play_lock",
	"body_attack_effect_immunity_self",
	## Wave 3 — ability suppression.
	"body_suppress_opponent_powers",
	"body_suppress_all_powers_and_bodies",
	## Wave 4 — Poké-Power wave 2.
	"body_damage_on_opponent_energy_attach",
	"power_search_deck_play_specific_basic",
	"power_reuse_last_attack",
	## Wave 5 — Baby Evolution.
	"power_baby_evolution",
	## Wave 6 — wave 3A + 3B.
	"body_heal_on_matching_energy_attach",
	"body_opponent_retreat_lock",
	"power_type_override_until_turn_end",
	## Poké-Power wave 2 — registered as bare strings in ability_handlers.gd
	## (no corresponding AbilityEffects.* constant).
	"power_attach_basic_energy_from_hand_to_active",
	"power_attach_basic_energy_from_discard_to_bench",
	"power_discard_hand_recover_basic_energy",
	"power_search_energy_to_pokemon_with_damage",
	"power_move_basic_energy_between_own",
	"power_move_any_energy_to_self",
	"power_switch_opponent_active_with_bench",
	"power_coin_return_defender_energy_to_hand",
	"power_coin_inflict_status_on_defender",
	"power_discard_energy_draw_n",
	"power_heal_each_own_active",
]


func test_every_expected_key_is_registered() -> void:
	var missing: Array[String] = []
	for key in EXPECTED_KEYS:
		if not AbilityEffectRegistry.has_definition(key):
			missing.append(key)
	assert_eq(missing.size(), 0,
		"AbilityEffects constants without a registered handler:\n  "
			+ "\n  ".join(missing))


func test_registry_keys_match_expected_set() -> void:
	## Inverse check — registered keys should be a superset of EXPECTED_KEYS.
	## Surfaces handlers registered under names that drifted from their
	## constant (typo, rename, dead key).
	var registered := AbilityEffectRegistry.registered_keys()
	var orphans: Array[String] = []
	for k in registered:
		if not EXPECTED_KEYS.has(k):
			orphans.append(k)
	## Orphans aren't necessarily bugs — a future wave may add a key before
	## this list is updated — but the diff is worth surfacing.
	assert_eq(orphans.size(), 0,
		"Registered handler keys missing from EXPECTED_KEYS (update this "
			+ "test alongside ability_handlers.gd):\n  "
			+ "\n  ".join(orphans))
