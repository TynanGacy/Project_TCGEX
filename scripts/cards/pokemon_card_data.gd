extends CardData
class_name PokemonCardData

enum Stage { BASIC, STAGE1, STAGE2 }
enum EnergyType { NONE, FIRE, WATER, GRASS, LIGHTNING, PSYCHIC, FIGHTING, DARKNESS, METAL, DRAGON, COLORLESS }

@export var stage: Stage = Stage.BASIC
## Name-only slug used for evolution matching (no set suffix).
## e.g. "pikachu" for any print of Pikachu regardless of set.
@export var name_slug: String = ""
@export var evolves_from: String = ""
@export var hp_max: int = 50
@export var pokemon_type: EnergyType = EnergyType.COLORLESS

@export var weakness: EnergyType = EnergyType.NONE
@export var resistance: EnergyType = EnergyType.NONE
@export var retreat_cost: int = 1

@export var attacks: Array[AttackData] = []

## Poké-Powers and Poké-Bodies on this card (usually 0 or 1).
@export var abilities: Array[AbilityData] = []

static func energy_type_to_string(t: EnergyType) -> String:
	## Utility kept for upcoming HUD/log formatting (effect text, battle log,
	## and debug overlays) where enum names need stable string output.
	return String(EnergyType.keys()[t])
