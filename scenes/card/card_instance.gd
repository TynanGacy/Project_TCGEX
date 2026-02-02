extends RefCounted
class_name CardInstance

enum Zone { DECK, HAND, ACTIVE, BENCH, DISCARD, PRIZES, OTHER }

# Optional: keep status generic for now (Pokemon-specific statuses can live here too)
enum SpecialCondition { NONE, ASLEEP, BURNED, CONFUSED, PARALYZED, POISONED }

var instance_id: int
var data: CardData
var zone: Zone = Zone.OTHER

# Runtime state (mostly meaningful for Pokémon)
var damage: int = 0
var special_conditions: Array[SpecialCondition] = []

# Attachments (Pokémon-like)
var attached_energy: Array[CardInstance] = []
var attached_tools: Array[CardInstance] = []

# For future: owner/controller
var owner_id: int = 0
var controller_id: int = 0

static var _next_id: int = 1

static func create(from_data: CardData) -> CardInstance:
	var inst: CardInstance = CardInstance.new()
	inst.instance_id = _next_id
	_next_id += 1

	inst.data = from_data
	inst.special_conditions.clear()
	inst.damage = 0
	return inst

func is_pokemon() -> bool:
	return data is PokemonCardData

func hp_max() -> int:
	if data is PokemonCardData:
		return (data as PokemonCardData).hp_max
	return 0

func hp_remaining() -> int:
	if not is_pokemon():
		return 0
	return max(0, hp_max() - damage)

func apply_damage(amount: int) -> void:
	if not is_pokemon():
		return
	damage = max(0, damage + max(0, amount))

func heal(amount: int) -> void:
	if not is_pokemon():
		return
	damage = max(0, damage - max(0, amount))

func is_knocked_out() -> bool:
	if not is_pokemon():
		return false
	return damage >= hp_max()

func has_condition(cond: SpecialCondition) -> bool:
	return special_conditions.has(cond)

func add_condition(cond: SpecialCondition) -> void:
	if cond == SpecialCondition.NONE:
		return
	if not special_conditions.has(cond):
		special_conditions.append(cond)

func remove_condition(cond: SpecialCondition) -> void:
	special_conditions.erase(cond)

func clear_conditions() -> void:
	special_conditions.clear()

func attach_energy(card: CardInstance) -> bool:
	if card == null:
		return false
	if not (card.data is EnergyCardData):
		return false
	attached_energy.append(card)
	return true

func attach_tool(card: CardInstance) -> bool:
	if card == null:
		return false
	if not (card.data is TrainerCardData):
		return false
	var t := card.data as TrainerCardData
	if t.trainer_kind != TrainerCardData.TrainerKind.TOOL:
		return false
	attached_tools.append(card)
	return true
