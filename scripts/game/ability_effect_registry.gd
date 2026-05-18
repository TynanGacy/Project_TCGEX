class_name AbilityEffectRegistry
## Static registry mapping AbilityData.effect_key strings to Poké-Power /
## Poké-Body handlers.  Parallel to TrainerEffectRegistry and EffectRegistry.

static var _definitions: Dictionary = {}


static func register_def(key: String, definition: AbilityEffectDefinition) -> void:
	if key == "":
		return
	_definitions[key] = definition


static func has_definition(key: String) -> bool:
	return key != "" and _definitions.has(key)


static func get_definition(key: String) -> AbilityEffectDefinition:
	if key == "" or not _definitions.has(key):
		return null
	return _definitions[key]


## Synchronously runs the handler for [phase].  No-op if [key] is unregistered
## or has no handler for [phase].
static func dispatch_phase(key: String, phase: int, ctx: AbilityContext) -> void:
	if key == "" or not _definitions.has(key):
		return
	var def: AbilityEffectDefinition = _definitions[key]
	if def.phase_handlers.has(phase):
		def.phase_handlers[phase].call(ctx)


## Returns the AbilityQuery produced by the PROMPT handler, or null if the
## key has no PROMPT handler.  PROMPT handlers may also return null to
## indicate "no query needed for this activation".
##
## PROMPT handlers can be coroutines (await coin animations, etc.).  Callers
## MUST `await` this function; await on a synchronous handler is a no-op so
## non-coroutine handlers remain compatible.
static func get_query(key: String, ctx: AbilityContext) -> AbilityQuery:
	if key == "" or not _definitions.has(key):
		return null
	var def: AbilityEffectDefinition = _definitions[key]
	if not def.phase_handlers.has(AbilityResolver.Phase.PROMPT):
		return null
	var result = await def.phase_handlers[AbilityResolver.Phase.PROMPT].call(ctx)
	if result is AbilityQuery:
		return result
	return null


## Returns the passive_meta dictionary for [key], or {} if unregistered.
## Static helpers (damage modifiers, energy-cost discounts, etc.) read this
## to scan in-play Pokémon for matching Poké-Bodies.
static func passive_meta(key: String) -> Dictionary:
	if key == "" or not _definitions.has(key):
		return {}
	return (_definitions[key] as AbilityEffectDefinition).passive_meta


static func registered_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _definitions.keys():
		keys.append(str(k))
	return keys


static func clear() -> void:
	_definitions.clear()
