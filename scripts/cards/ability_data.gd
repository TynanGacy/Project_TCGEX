extends Resource
class_name AbilityData
## Represents a Poké-Power or Poké-Body on a Pokémon card.
##
## Poké-Powers are activated abilities (the player chooses when to use them).
## Poké-Bodies are passive abilities that are always active.

enum AbilityKind { POKE_POWER, POKE_BODY }

@export var ability_name: String = ""
@export var kind: AbilityKind = AbilityKind.POKE_BODY
@export_multiline var text: String = ""

## Effect identifier matching an AbilityEffectRegistry handler.  Empty string =
## no runtime effect (ability shows in card text but doesn't dispatch).
@export var effect_key: String = ""

## Runtime configuration for parameterized ability-effect handlers.  Mirror of
## AttackData.effect_params / TrainerCardData.effect_params.
@export var effect_params: Dictionary = {}

## When true, this Poké-Power can be activated any number of times per turn
## ("As often as you like during your turn…").  Default false matches the
## standard once-per-turn rule.  Repeatable powers never set
## PokemonInstance.power_used_this_turn.
@export var repeatable: bool = false
