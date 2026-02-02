extends CardData
class_name PokemonCardData

enum Stage { BASIC, STAGE1, STAGE2 }
enum EnergyType { NONE, FIRE, WATER, GRASS, LIGHTNING, PSYCHIC, FIGHTING, DARKNESS, METAL, DRAGON, COLORLESS }

@export var stage: Stage = Stage.BASIC
@export var hp_max: int = 50
@export var pokemon_type: EnergyType = EnergyType.COLORLESS

@export var weakness: EnergyType = EnergyType.NONE
@export var resistance: EnergyType = EnergyType.NONE
@export var retreat_cost: int = 1

@export var attacks: Array[AttackData] = []

static func energy_type_to_string(t: EnergyType) -> String:
	return String(EnergyType.keys()[t])
