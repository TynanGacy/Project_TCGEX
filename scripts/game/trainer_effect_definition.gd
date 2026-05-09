class_name TrainerEffectDefinition
extends RefCounted
## Maps TrainerResolver phases to handler Callables.  Mirrors EffectDefinition.
##
## Handler signatures:
##   VALIDATE / APPLY / POST_APPLY:  func(ctx: TrainerContext) -> void
##   PROMPT:                          func(ctx: TrainerContext) -> TrainerQuery

var phase_handlers: Dictionary = {}


static func single(phase: int, handler: Callable) -> TrainerEffectDefinition:
	var def := TrainerEffectDefinition.new()
	def.phase_handlers[phase] = handler
	return def


static func multi(mapping: Dictionary) -> TrainerEffectDefinition:
	var def := TrainerEffectDefinition.new()
	def.phase_handlers = mapping
	return def
