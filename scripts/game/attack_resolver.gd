class_name AttackResolver
## Static utility for attack damage calculation and energy cost checking.
##
## Damage rules follow the Generation III (Ruby/Sapphire) format:
##   Weakness  → damage × 2
##   Resistance → damage − 30 (floor 0)
##
## Energy affordability: specific-type costs (fire, water, …) must be paid by
## exactly that energy type.  Any remaining colorless cost may be covered by
## leftover energy of any type.


## Returns true when [pokemon]'s attached energy fully covers [attack]'s cost.
static func can_afford(pokemon: CardInstance, attack: AttackData) -> bool:
	var counts := _count_energy(pokemon)

	## --- Satisfy each specific-colour requirement first ---------------------
	if _type_count(counts, PokemonCardData.EnergyType.FIRE)      < attack.cost_fire:      return false
	if _type_count(counts, PokemonCardData.EnergyType.WATER)     < attack.cost_water:     return false
	if _type_count(counts, PokemonCardData.EnergyType.GRASS)     < attack.cost_grass:     return false
	if _type_count(counts, PokemonCardData.EnergyType.LIGHTNING) < attack.cost_lightning: return false
	if _type_count(counts, PokemonCardData.EnergyType.PSYCHIC)   < attack.cost_psychic:   return false
	if _type_count(counts, PokemonCardData.EnergyType.FIGHTING)  < attack.cost_fighting:  return false
	if _type_count(counts, PokemonCardData.EnergyType.DARKNESS)  < attack.cost_darkness:  return false
	if _type_count(counts, PokemonCardData.EnergyType.METAL)     < attack.cost_metal:     return false

	if attack.cost_colorless == 0:
		return true

	## --- Count leftover energy for the colorless requirement ---------------
	var remaining := 0
	for etype: int in counts:
		var surplus := counts[etype]
		match etype:
			PokemonCardData.EnergyType.FIRE:      surplus = max(0, surplus - attack.cost_fire)
			PokemonCardData.EnergyType.WATER:     surplus = max(0, surplus - attack.cost_water)
			PokemonCardData.EnergyType.GRASS:     surplus = max(0, surplus - attack.cost_grass)
			PokemonCardData.EnergyType.LIGHTNING: surplus = max(0, surplus - attack.cost_lightning)
			PokemonCardData.EnergyType.PSYCHIC:   surplus = max(0, surplus - attack.cost_psychic)
			PokemonCardData.EnergyType.FIGHTING:  surplus = max(0, surplus - attack.cost_fighting)
			PokemonCardData.EnergyType.DARKNESS:  surplus = max(0, surplus - attack.cost_darkness)
			PokemonCardData.EnergyType.METAL:     surplus = max(0, surplus - attack.cost_metal)
		remaining += surplus

	return remaining >= attack.cost_colorless


## Returns final damage after applying weakness and resistance.
static func calculate_damage(
	attacker: CardInstance,
	defender: CardInstance,
	attack: AttackData
) -> int:
	if not (attacker.data is PokemonCardData) or not (defender.data is PokemonCardData):
		return attack.base_damage

	var atk_type := (attacker.data as PokemonCardData).pokemon_type
	var def_data  := defender.data as PokemonCardData
	var damage    := attack.base_damage

	## Weakness: ×2 (RS-era rule)
	if atk_type != PokemonCardData.EnergyType.NONE and def_data.weakness == atk_type:
		damage *= 2

	## Resistance: −30 (floor 0)
	if atk_type != PokemonCardData.EnergyType.NONE and def_data.resistance == atk_type:
		damage = max(0, damage - 30)

	return damage


## Total energy units attached to a Pokemon (respects the 'provides' field on
## multi-energy cards such as Double Colorless Energy).
static func total_energy_count(pokemon: CardInstance) -> int:
	var total := 0
	for e in pokemon.attached_energy:
		if e.data is EnergyCardData:
			total += (e.data as EnergyCardData).provides
	return total


## Human-readable energy cost string, e.g. "F F C" for Fire Fire Colorless.
## Used by the attack panel UI.
static func cost_summary(attack: AttackData) -> String:
	var parts: Array[String] = []

	## Fixed-colour costs use single-letter abbreviations.
	const ABBR: Dictionary = {
		"cost_fire": "F", "cost_water": "W", "cost_grass": "G",
		"cost_lightning": "L", "cost_psychic": "P", "cost_fighting": "FG",
		"cost_darkness": "D", "cost_metal": "M"
	}
	for prop in ABBR:
		var count: int = attack.get(prop) if attack.get(prop) != null else 0
		for _i in count:
			parts.append(ABBR[prop])
	for _i in attack.cost_colorless:
		parts.append("C")

	if parts.is_empty():
		return "(free)"
	return " ".join(parts)


## Returns the total energy cost (colorless + all specific types) as an integer.
static func total_cost(attack: AttackData) -> int:
	return (attack.cost_colorless + attack.cost_fire + attack.cost_water
		+ attack.cost_grass + attack.cost_lightning + attack.cost_psychic
		+ attack.cost_fighting + attack.cost_darkness + attack.cost_metal)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _count_energy(pokemon: CardInstance) -> Dictionary:
	## Returns a Dictionary mapping EnergyType int → total energy units.
	var counts: Dictionary = {}
	for e in pokemon.attached_energy:
		if not (e.data is EnergyCardData):
			continue
		var etype: int = (e.data as EnergyCardData).energy_type
		var prov:  int = (e.data as EnergyCardData).provides
		counts[etype] = counts.get(etype, 0) + prov
	return counts


static func _type_count(counts: Dictionary, energy_type: int) -> int:
	return counts.get(energy_type, 0)
