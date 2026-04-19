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

## Optional effect identifier for future ability-effect dispatch.
@export var effect_key: String = ""
