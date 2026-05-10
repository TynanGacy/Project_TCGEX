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


## Dispatches an attack's primary `effect_key` plus any entries in its
## `effect_chain`. Each chain entry is `{"key": String, "params": Dictionary}`.
## Handlers read `ctx.attack.effect_params`, so we temporarily swap the
## attack reference around each chain entry's dispatch.
static func dispatch_phase_for_attack(attack: AttackData, phase: int,
		ctx: AttackContext, queue: Array[QueuedEffect]) -> void:
	dispatch_phase(attack.effect_key, phase, ctx, queue)
	if attack.effect_chain.is_empty():
		return
	var saved: AttackData = ctx.attack
	for raw in attack.effect_chain:
		if not (raw is Dictionary):
			continue
		var entry: Dictionary = raw
		var sub := AttackData.new()
		# Preserve the parent attack's identity so log lines / costs stay sensible.
		sub.name = saved.name
		sub.base_damage = saved.base_damage
		sub.cost_colorless = saved.cost_colorless
		sub.cost_fire = saved.cost_fire
		sub.cost_water = saved.cost_water
		sub.cost_grass = saved.cost_grass
		sub.cost_lightning = saved.cost_lightning
		sub.cost_psychic = saved.cost_psychic
		sub.cost_fighting = saved.cost_fighting
		sub.cost_darkness = saved.cost_darkness
		sub.cost_metal = saved.cost_metal
		sub.effect_key = str(entry.get("key", ""))
		sub.effect_params = entry.get("params", {}) if entry.get("params", {}) is Dictionary else {}
		ctx.attack = sub
		dispatch_phase(sub.effect_key, phase, ctx, queue)
	ctx.attack = saved


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
