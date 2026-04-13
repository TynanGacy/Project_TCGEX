class_name CardEffectRegistry
## String-to-callable registry for reusable card effects.
##
## Why this exists:
## - Card JSON can safely refer to effect IDs (strings).
## - We resolve IDs to Callables at runtime.
## - A typo in one mapping should not hard-crash registry initialization.

const _EFFECT_METHODS: Dictionary = {
	"draw_cards": "draw_cards",
	"search_deck": "search_deck",
	"search_deck_for_basics": "search_deck_for_basics",
	"search_deck_for_energy": "search_deck_for_energy",
	"heal": "heal",
	"discard_all_energy": "discard_all_energy",
	"shuffle_hand_and_draw": "shuffle_hand_and_draw",
	"apply_condition": "apply_condition",
	"cure_all_conditions": "cure_all_conditions",
	"spread_bench_damage": "spread_bench_damage",
	"recover_from_discard": "recover_from_discard"
}

static var _resolved: Dictionary = {}


static func resolve(effect_id: String) -> Callable:
	if _resolved.has(effect_id):
		return _resolved[effect_id]

	var method_name: String = str(_EFFECT_METHODS.get(effect_id, ""))
	if method_name == "":
		push_warning("CardEffectRegistry: unknown effect id '%s'" % effect_id)
		return Callable()

	if not CardEffects.has_method(method_name):
		push_warning(
			"CardEffectRegistry: effect id '%s' points to missing CardEffects method '%s'" % [
				effect_id,
				method_name
			]
		)
		return Callable()

	var callable := Callable(CardEffects, method_name)
	_resolved[effect_id] = callable
	return callable


static func invoke(effect_id: String, args: Array = []) -> Variant:
	var callable := resolve(effect_id)
	if not callable.is_valid():
		return null
	return callable.callv(args)


static func has_effect(effect_id: String) -> bool:
	return resolve(effect_id).is_valid()
