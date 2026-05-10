extends CardData
class_name EnergyCardData

@export var energy_type: PokemonCardData.EnergyType = PokemonCardData.EnergyType.COLORLESS
## Extra types this card provides for sorting/filter purposes. Multi and
## Rainbow Energy populate this with every standard energy type so they
## match any energy filter.
@export var extra_types: Array[int] = []
@export var provides: int = 1
