class_name EffectDefinition
extends RefCounted
## Maps AttackResolver phases to handler Callables.
##
## Handler signature:
##   func(ctx: AttackContext, queue: Array[QueuedEffect]) -> void

var phase_handlers: Dictionary = {}


static func single(phase: int, handler: Callable) -> EffectDefinition:
	var def := EffectDefinition.new()
	def.phase_handlers[phase] = handler
	return def


static func multi(mapping: Dictionary) -> EffectDefinition:
	var def := EffectDefinition.new()
	def.phase_handlers = mapping
	return def
