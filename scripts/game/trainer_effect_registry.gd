class_name TrainerEffectRegistry
## Static registry mapping effect_key strings to Trainer-card handlers.
## Parallel to EffectRegistry, but for Items / Supporters / Stadiums /
## Tools rather than attacks.

static var _definitions: Dictionary = {}


static func register_def(key: String, definition: TrainerEffectDefinition) -> void:
	if key == "":
		return
	_definitions[key] = definition


static func has_definition(key: String) -> bool:
	return key != "" and _definitions.has(key)


## Synchronously runs the handler for [phase].  No-op if [key] is unregistered
## or has no handler for [phase].
static func dispatch_phase(key: String, phase: int, ctx: TrainerContext) -> void:
	if key == "" or not _definitions.has(key):
		return
	var def: TrainerEffectDefinition = _definitions[key]
	if def.phase_handlers.has(phase):
		def.phase_handlers[phase].call(ctx)


## Returns the TrainerQuery produced by the PROMPT handler, or null if the
## key has no PROMPT handler.  PROMPT handlers may also return null to
## indicate "no query needed for this play" (e.g. only one valid target).
##
## PROMPT handlers can be coroutines (e.g. Pokemon Reversal awaits the coin
## animation before deciding whether to prompt for a bench target).  Callers
## MUST `await` this function; await on a synchronously-returning handler is
## a no-op, so non-coroutine handlers remain compatible.
static func get_query(key: String, ctx: TrainerContext) -> TrainerQuery:
	if key == "" or not _definitions.has(key):
		return null
	var def: TrainerEffectDefinition = _definitions[key]
	if not def.phase_handlers.has(TrainerResolver.Phase.PROMPT):
		return null
	var result = await def.phase_handlers[TrainerResolver.Phase.PROMPT].call(ctx)
	if result is TrainerQuery:
		return result
	return null


static func registered_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _definitions.keys():
		keys.append(str(k))
	return keys


static func clear() -> void:
	_definitions.clear()
