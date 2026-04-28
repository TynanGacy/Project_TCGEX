class_name EffectRegistry
## Static registry mapping effect_key strings to attack-effect handler Callables.
##
## Handlers are registered once (typically in an autoload or scene _ready) and
## persist for the lifetime of the application.
##
## Handler signature:  func(ctx: AttackContext) -> void
##
## Two-phase design (see AttackContext):
##   - Handlers can set ctx.bonus_damage before the W/R calculation runs.
##   - Handlers can enqueue post-damage actions via ctx.add_post_action().
##
## Registration example:
##   EffectRegistry.register("coin_asleep", func(ctx):
##       ctx.add_post_action(func():
##           ctx.target.add_condition(PokemonInstance.SpecialCondition.ASLEEP)
##       )
##   )

static var _handlers: Dictionary = {}


## Registers [handler] for [key]. Overwrites any existing handler for the same key.
static func register(key: String, handler: Callable) -> void:
	if key == "":
		return
	_handlers[key] = handler


## Returns true if [key] has a registered handler.
static func has_handler(key: String) -> bool:
	return key != "" and _handlers.has(key)


## Dispatches [key] if a handler is registered; no-op otherwise.
## Called once per attack resolution, before W/R and damage are applied.
static func dispatch(key: String, ctx: AttackContext) -> void:
	if key == "" or not _handlers.has(key):
		return
	_handlers[key].call(ctx)


## Returns all currently registered keys (useful for debugging / testing).
static func registered_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in _handlers.keys():
		keys.append(str(k))
	return keys


## Removes all registered handlers. Primarily for use between unit tests.
static func clear() -> void:
	_handlers.clear()
