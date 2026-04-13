class_name AttackResolver
## Static utility for attack damage calculation and energy cost checking.

## Pairs of [EnergyType, cost_property_name] for the eight typed energy costs.
## Defined at class level so it's accessible from all static functions.
const _TYPED_COSTS: Array = [
	[PokemonCardData.EnergyType.FIRE,      "cost_fire"],
	[PokemonCardData.EnergyType.WATER,     "cost_water"],
	[PokemonCardData.EnergyType.GRASS,     "cost_grass"],
	[PokemonCardData.EnergyType.LIGHTNING, "cost_lightning"],
	[PokemonCardData.EnergyType.PSYCHIC,   "cost_psychic"],
	[PokemonCardData.EnergyType.FIGHTING,  "cost_fighting"],
	[PokemonCardData.EnergyType.DARKNESS,  "cost_darkness"],
	[PokemonCardData.EnergyType.METAL,     "cost_metal"],
]
##
## Damage rules follow the Generation III (Ruby/Sapphire) format:
##   Weakness  → damage × 2
##   Resistance → damage − 30 (floor 0)
##
## Special energy effects applied here:
##   Darkness Energy  — +10 damage if the attacker is a Darkness-type Pokémon.
##   Metal Energy     — −10 damage per Metal Energy attached to a Metal-type
##                      defender (applied after Weakness/Resistance).
##   Buffer Piece     — −20 damage to the defender after all other modifiers.
##
## Energy affordability:
##   Specific-type costs (Fire, Water, …) must be covered by those exact types.
##   Any remaining Colorless cost is covered by leftover energy of any type.
##   Rainbow Energy and Multi Energy act as wild cards (1 unit of any type).


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns true when [pokemon]'s attached energy fully covers [attack]'s cost.
static func can_afford(pokemon: CardInstance, attack: AttackData) -> bool:
	var counts := _count_energy(pokemon)
	var wilds: int  = counts.get(_WILD, 0)  # Rainbow / valid Multi energy units

	## --- Satisfy each specific-colour requirement first -------------------
	for pair in _TYPED_COSTS:
		var etype: int = pair[0]
		var prop: String = pair[1]
		var cost: int = attack.get(prop) if attack.get(prop) != null else 0
		if cost == 0:
			continue
		var have: int = counts.get(etype, 0)
		if have >= cost:
			continue
		# Deficit — try to fill with wilds.
		var deficit: int = cost - have
		if wilds >= deficit:
			wilds -= deficit
		else:
			return false

	if attack.cost_colorless == 0:
		return true

	## --- Count all remaining energy for the colorless requirement ---------
	var remaining: int = wilds
	for etype: int in counts:
		if etype == _WILD:
			continue
		var surplus: int = counts[etype]
		for pair in _TYPED_COSTS:
			if pair[0] == etype:
				surplus = maxi(0, surplus - (attack.get(pair[1]) if attack.get(pair[1]) != null else 0))
		remaining += surplus

	return remaining >= attack.cost_colorless


## Returns final damage after applying Weakness, Resistance, special energy
## bonuses (Darkness, Metal) and tool reductions (Buffer Piece).
static func calculate_damage(
		attacker: CardInstance,
		defender: CardInstance,
		attack: AttackData
) -> int:
	if not (attacker.data is PokemonCardData) or not (defender.data is PokemonCardData):
		return attack.base_damage

	var atk_pdata := attacker.data as PokemonCardData
	var def_pdata  := defender.data   as PokemonCardData
	var damage     := attack.base_damage

	## Weakness: ×2 (RS-era rule)
	if atk_pdata.pokemon_type != PokemonCardData.EnergyType.NONE \
			and def_pdata.weakness == atk_pdata.pokemon_type:
		damage *= 2

	## Resistance: −30 (floor 0)
	if atk_pdata.pokemon_type != PokemonCardData.EnergyType.NONE \
			and def_pdata.resistance == atk_pdata.pokemon_type:
		damage = maxi(0, damage - 30)

	## Darkness Energy: +10 if attacker is Darkness type and has ≥1 Darkness Energy.
	if atk_pdata.pokemon_type == PokemonCardData.EnergyType.DARKNESS:
		var darkness_units: int = _count_energy(attacker).get(
			PokemonCardData.EnergyType.DARKNESS, 0)
		damage += darkness_units * 10

	## Metal Energy: −10 per Metal Energy attached to a Metal-type defender.
	if def_pdata.pokemon_type == PokemonCardData.EnergyType.METAL:
		var metal_units := _count_energy_by_card_id(defender, "RS_94_metal_energy")
		damage = maxi(0, damage - metal_units * 10)

	## Buffer Piece: −20 to the defender (one-time; discarded by GameState).
	if defender.has_tool_id("DR_83_buffer_piece"):
		damage = maxi(0, damage - 20)

	return maxi(0, damage)


## Total energy units attached to a Pokémon (respects the 'provides' field on
## multi-energy cards such as Double Colorless Energy).
static func total_energy_count(pokemon: CardInstance) -> int:
	var total := 0
	for e in pokemon.attached_energy:
		if e.data is EnergyCardData:
			total += (e.data as EnergyCardData).provides
	return total


## Human-readable energy cost string, e.g. "F F C" for Fire Fire Colorless.
static func cost_summary(attack: AttackData) -> String:
	var parts: Array[String] = []
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


## Returns the total energy cost as an integer.
static func total_cost(attack: AttackData) -> int:
	return (attack.cost_colorless + attack.cost_fire + attack.cost_water
		+ attack.cost_grass + attack.cost_lightning + attack.cost_psychic
		+ attack.cost_fighting + attack.cost_darkness + attack.cost_metal)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Sentinel key used inside _count_energy to represent "wild" energy units
## contributed by Rainbow Energy and valid Multi Energy.
const _WILD := -1


## Returns a Dictionary mapping EnergyType int → total energy units available.
## Wild-card energy (Rainbow, valid Multi) is stored under the _WILD key.
static func _count_energy(pokemon: CardInstance) -> Dictionary:
	var counts: Dictionary = {}

	# Count how many special energy cards are attached (for Multi Energy rule).
	var special_count := 0
	for e in pokemon.attached_energy:
		if not (e.data is EnergyCardData):
			continue
		var edata := e.data as EnergyCardData
		if not _is_basic_energy_type(edata.energy_type):
			special_count += 1

	for e in pokemon.attached_energy:
		if not (e.data is EnergyCardData):
			continue
		var edata  := e.data as EnergyCardData
		var etype  := edata.energy_type
		var prov   := edata.provides
		var cid    := e.data.card_id

		# Rainbow Energy: always wild (provides 1 of any type).
		if cid == "RS_95_rainbow_energy":
			counts[_WILD] = counts.get(_WILD, 0) + 1
			continue

		# Multi Energy: wild UNLESS another special energy is already attached.
		if cid == "SS_93_multi_energy":
			if special_count <= 1:  # only this multi energy attached
				counts[_WILD] = counts.get(_WILD, 0) + 1
			else:
				# Reverts to Colorless when other specials are present.
				counts[PokemonCardData.EnergyType.COLORLESS] = \
					counts.get(PokemonCardData.EnergyType.COLORLESS, 0) + 1
			continue

		counts[etype] = counts.get(etype, 0) + prov

	return counts


## Count the number of energy units provided by a specific special energy card
## (identified by card_id) attached to [pokemon].
static func _count_energy_by_card_id(pokemon: CardInstance, card_id: String) -> int:
	var total := 0
	for e in pokemon.attached_energy:
		if (e.data is EnergyCardData) and e.data.card_id == card_id:
			total += (e.data as EnergyCardData).provides
	return total


static func _is_basic_energy_type(etype: PokemonCardData.EnergyType) -> bool:
	return etype in [
		PokemonCardData.EnergyType.FIRE,
		PokemonCardData.EnergyType.WATER,
		PokemonCardData.EnergyType.GRASS,
		PokemonCardData.EnergyType.LIGHTNING,
		PokemonCardData.EnergyType.PSYCHIC,
		PokemonCardData.EnergyType.FIGHTING,
		PokemonCardData.EnergyType.DARKNESS,
		PokemonCardData.EnergyType.METAL,
	]
