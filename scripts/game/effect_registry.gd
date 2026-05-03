class_name EffectRegistry
## Static registry mapping effect_key strings to attack-effect handlers.
##
## New API (phase-aware):
##   register_def(key, EffectDefinition) — maps phases to handler Callables.
##   dispatch_phase(key, phase, ctx, queue) — fires the handler for one phase.
##
## Legacy API (compatibility shim, remove after all handlers migrated):
##   register(key, handler) — routes to DAMAGE_CALC phase.
##   dispatch(key, ctx) — calls old-style handler directly.

static var _handlers: Dictionary = {}
static var _definitions: Dictionary = {}


## --- New phase-aware API -----------------------------------------------------

static func register_def(key: String, definition: EffectDefinition) -> void:
	if key == "":
		return
	_definitions[key] = definition


static func register_simple(key: String, phase: int, handler: Callable) -> void:
	_definitions[key] = EffectDefinition.single(phase, handler)


static func dispatch_phase(key: String, phase: int, ctx: AttackContext,
		queue: Array[QueuedEffect]) -> void:
	if key == "" or not _definitions.has(key):
		return
	var def: EffectDefinition = _definitions[key]
	if def.phase_handlers.has(phase):
		def.phase_handlers[phase].call(ctx, queue)


static func has_definition(key: String) -> bool:
	return key != "" and _definitions.has(key)


## --- Legacy API (compatibility shim) -----------------------------------------

static func register(key: String, handler: Callable) -> void:
	if key == "":
		return
	_handlers[key] = handler


static func has_handler(key: String) -> bool:
	return key != "" and (_handlers.has(key) or _definitions.has(key))


static func dispatch(key: String, ctx: AttackContext) -> void:
	if key == "" or not _handlers.has(key):
		return
	_handlers[key].call(ctx)


static func registered_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _handlers.keys():
		keys.append(str(k))
	for k in _definitions.keys():
		if not keys.has(str(k)):
			keys.append(str(k))
	return keys


static func clear() -> void:
	_handlers.clear()
	_definitions.clear()
