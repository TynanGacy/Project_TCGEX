extends Resource
class_name AbilityData
## Represents a Poké-Power or Poké-Body on a Pokémon card.
##
## Poké-Powers are activated abilities (the player chooses when to use them).
## Poké-Bodies are passive abilities that are always active.
##
## effect_key maps to a registered handler in CardEffectRegistry, allowing
## new cards to declare their ability behaviour in JSON without code changes.

enum AbilityKind { POKE_POWER, POKE_BODY }

@export var ability_name: String = ""
@export var kind: AbilityKind = AbilityKind.POKE_BODY
@export_multiline var text: String = ""

## Optional key into CardEffectRegistry for programmatic effect lookup.
## If empty the engine falls back to rules_text / manual dispatch.
@export var effect_key: String = ""
