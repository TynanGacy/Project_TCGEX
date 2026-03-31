class_name TestDeckFactory

## Builds a randomised test deck for playtesting.
## Each card is drawn at random from a pool of one representative per
## card type / sub-type.  display_name is written so the Label3D on each
## card face makes the type immediately readable in-game.

static func build_deck(size: int = 20) -> Array[CardData]:
	var pool := _build_pool()
	var deck: Array[CardData] = []
	for i in size:
		deck.append(pool[randi() % pool.size()])
	return deck


static func _build_pool() -> Array[CardData]:
	var pool: Array[CardData] = []

	# --- Basic Pokemon ---
	pool.append(_basic("pikachu",    "Pikachu [Basic]",    PokemonCardData.EnergyType.LIGHTNING, 60))
	pool.append(_basic("squirtle",   "Squirtle [Basic]",   PokemonCardData.EnergyType.WATER,     60))
	pool.append(_basic("charmander", "Charmander [Basic]", PokemonCardData.EnergyType.FIRE,      70))

	# --- Stage 1 Pokemon (evolve_from matches card_id of a Basic above) ---
	pool.append(_stage1("raichu",    "Raichu [Stage 1]",    "pikachu",    PokemonCardData.EnergyType.LIGHTNING, 90))
	pool.append(_stage1("wartortle", "Wartortle [Stage 1]", "squirtle",   PokemonCardData.EnergyType.WATER,     80))
	pool.append(_stage1("charmeleon","Charmeleon [Stage 1]","charmander", PokemonCardData.EnergyType.FIRE,      80))

	# --- Energy ---
	pool.append(_energy("fire_energy",      "Fire Energy",      PokemonCardData.EnergyType.FIRE))
	pool.append(_energy("water_energy",     "Water Energy",     PokemonCardData.EnergyType.WATER))
	pool.append(_energy("lightning_energy", "Lightning Energy", PokemonCardData.EnergyType.LIGHTNING))
	pool.append(_energy("colorless_energy", "Colorless Energy", PokemonCardData.EnergyType.COLORLESS))

	# --- Trainer: Item ---
	pool.append(_item("potion",   "Potion [Item]"))
	pool.append(_item("pokeball", "Poké Ball [Item]"))

	# --- Trainer: Supporter ---
	pool.append(_supporter("professors_research", "Prof. Research [Supporter]"))

	# --- Trainer: Stadium ---
	pool.append(_stadium("gym", "Gym [Stadium]"))

	# --- Trainer: Tool ---
	pool.append(_tool("exp_share", "Exp. Share [Tool]"))

	return pool


# ---------------------------------------------------------------------------
# Private builders
# ---------------------------------------------------------------------------

static func _basic(
	id: String,
	name: String,
	ptype: PokemonCardData.EnergyType,
	hp: int
) -> PokemonCardData:
	var d := PokemonCardData.new()
	d.card_id      = id
	d.display_name = name
	d.stage        = PokemonCardData.Stage.BASIC
	d.pokemon_type = ptype
	d.hp_max       = hp
	return d


static func _stage1(
	id: String,
	name: String,
	evolves_from: String,
	ptype: PokemonCardData.EnergyType,
	hp: int
) -> PokemonCardData:
	var d := PokemonCardData.new()
	d.card_id      = id
	d.display_name = name
	d.stage        = PokemonCardData.Stage.STAGE1
	d.evolves_from = evolves_from
	d.pokemon_type = ptype
	d.hp_max       = hp
	return d


static func _energy(id: String, name: String, etype: PokemonCardData.EnergyType) -> EnergyCardData:
	var d := EnergyCardData.new()
	d.card_id      = id
	d.display_name = name
	d.energy_type  = etype
	return d


static func _item(id: String, name: String) -> TrainerCardData:
	var d := TrainerCardData.new()
	d.card_id      = id
	d.display_name = name
	d.trainer_kind = TrainerCardData.TrainerKind.ITEM
	return d


static func _supporter(id: String, name: String) -> TrainerCardData:
	var d := TrainerCardData.new()
	d.card_id      = id
	d.display_name = name
	d.trainer_kind = TrainerCardData.TrainerKind.SUPPORTER
	return d


static func _stadium(id: String, name: String) -> TrainerCardData:
	var d := TrainerCardData.new()
	d.card_id      = id
	d.display_name = name
	d.trainer_kind = TrainerCardData.TrainerKind.STADIUM
	return d


static func _tool(id: String, name: String) -> TrainerCardData:
	var d := TrainerCardData.new()
	d.card_id      = id
	d.display_name = name
	d.trainer_kind = TrainerCardData.TrainerKind.TOOL
	return d
