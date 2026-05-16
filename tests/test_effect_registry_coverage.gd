extends GutTest
## Smoke test asserting every effect_key referenced in the card data resolves
## via the appropriate registry.  Catches typos and orphaned keys that would
## otherwise fail silently at runtime (registries return early on unknown keys).
##
## Three lookup tables are checked:
##   - AbilityData.effect_key    → AbilityEffectRegistry
##   - TrainerCardData.effect_key → TrainerEffectRegistry
##   - AttackData.effect_key (+ effect_chain[*].key) → EffectRegistry
##
## Empty keys are intentional (cards with no runtime effect) and skipped.

var _attack_handlers: Node = null
var _trainer_handlers: Node = null
var _ability_handlers: Node = null


func before_all() -> void:
	_attack_handlers = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_attack_handlers)
	_trainer_handlers = load("res://scenes/match/trainer_handlers.gd").new()
	add_child(_trainer_handlers)
	_ability_handlers = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers)


func after_all() -> void:
	for n in [_attack_handlers, _trainer_handlers, _ability_handlers]:
		if n != null:
			n.queue_free()


func test_every_ability_effect_key_resolves() -> void:
	var misses: Array[String] = []
	for card in CardDatabase.all_cards():
		if not (card is PokemonCardData):
			continue
		var poke: PokemonCardData = card
		for abil in poke.abilities:
			var key: String = abil.effect_key
			if key == "":
				continue
			if not AbilityEffectRegistry.has_definition(key):
				misses.append("%s ability '%s' → '%s'" %
					[poke.card_id, abil.ability_name, key])
	assert_eq(misses.size(), 0,
		"Unresolved AbilityEffectRegistry keys:\n  " + "\n  ".join(misses))


func test_every_trainer_effect_key_resolves() -> void:
	## Items, Supporters, and Stadiums dispatch through TrainerEffectRegistry.
	## Tools route through ToolEffects static helpers (read directly by
	## ActionRetreat / AttackResolver / ManagerSystem cleanup).
	## Fossils route through ActionPlayFossil via the plays_as_pokemon flag;
	## their effect_key is descriptive metadata, not a dispatch label.
	var misses: Array[String] = []
	for card in CardDatabase.all_cards():
		if not (card is TrainerCardData):
			continue
		var trainer: TrainerCardData = card
		if trainer.plays_as_pokemon:
			continue
		var key: String = trainer.effect_key
		if key == "":
			continue
		if trainer.trainer_kind == TrainerCardData.TrainerKind.TOOL:
			if not ToolEffects.is_known_key(key):
				misses.append("%s tool → '%s'" % [trainer.card_id, key])
			continue
		if not TrainerEffectRegistry.has_definition(key):
			misses.append("%s → '%s'" % [trainer.card_id, key])
	assert_eq(misses.size(), 0,
		"Unresolved trainer effect_keys:\n  " + "\n  ".join(misses))


func test_every_attack_effect_key_resolves() -> void:
	var misses: Array[String] = []
	for card in CardDatabase.all_cards():
		if not (card is PokemonCardData):
			continue
		var poke: PokemonCardData = card
		for atk in poke.attacks:
			if atk.effect_key != "" \
					and not EffectRegistry.has_handler(atk.effect_key):
				misses.append("%s attack '%s' → '%s'" %
					[poke.card_id, atk.name, atk.effect_key])
			for raw in atk.effect_chain:
				if not (raw is Dictionary):
					continue
				var chain_key: String = str((raw as Dictionary).get("key", ""))
				if chain_key == "":
					continue
				if not EffectRegistry.has_handler(chain_key):
					misses.append("%s attack '%s' chain → '%s'" %
						[poke.card_id, atk.name, chain_key])
	assert_eq(misses.size(), 0,
		"Unresolved EffectRegistry keys:\n  " + "\n  ".join(misses))
