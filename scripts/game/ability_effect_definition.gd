class_name AbilityEffectDefinition
extends RefCounted
## Maps AbilityResolver phases to handler Callables.  Mirror of
## TrainerEffectDefinition / EffectDefinition.
##
## Handler signatures:
##   VALIDATE / APPLY / POST_APPLY:  func(ctx: AbilityContext) -> void
##   PROMPT:                          func(ctx: AbilityContext) -> AbilityQuery
##
## Passive Poké-Bodies use the same registry but typically expose only a
## metadata accessor (the helper code reads ability.effect_params directly).
## They may register an empty definition for symmetry — the resolver simply
## won't dispatch any phase against them.

var phase_handlers: Dictionary = {}

## Optional metadata describing how a Poké-Body affects gameplay.  Read by
## static helpers (e.g. AbilityEffects.damage_modifier_for_target) when
## scanning all in-play Pokémon for matching auras.  Schema is per-effect_key.
var passive_meta: Dictionary = {}


static func single(phase: int, handler: Callable) -> AbilityEffectDefinition:
	var def := AbilityEffectDefinition.new()
	def.phase_handlers[phase] = handler
	return def


static func multi(mapping: Dictionary) -> AbilityEffectDefinition:
	var def := AbilityEffectDefinition.new()
	def.phase_handlers = mapping
	return def


## Constructs a definition that only carries passive metadata (no phase
## handlers).  Useful for Poké-Body effect_keys whose behaviour is fully
## described in effect_params + a static helper.
static func passive(meta: Dictionary) -> AbilityEffectDefinition:
	var def := AbilityEffectDefinition.new()
	def.passive_meta = meta
	return def
