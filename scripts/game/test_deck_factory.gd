class_name TestDeckFactory

## Builds a randomised test deck for playtesting.
## Each card is drawn at random from a pool of one representative per
## card type / sub-type.  display_name is written so the Label3D on each
## card face makes the type immediately readable in-game.

static func build_deck(size: int = 20) -> Array[CardData]:
	var pool := _build_pool()
	if pool.is_empty():
		push_error("build_deck: pool is empty, cannot build deck")
		return []
	var deck: Array[CardData] = []
	for i in size:
		deck.append(pool[randi() % pool.size()])
	return deck

static func _load_art(card_id: String) -> Texture2D:
	var parts := card_id.split("_")
	if parts.size() < 2:
		return null
	var set_folder := parts[0]
	var path := "res://assets/images/%s/%s.png" % [set_folder, card_id]
	if ResourceLoader.exists(path):
		return load(path)
	push_warning("_load_art: no image found at %s" % path)
	return null
	
static func _card_from_json(data: Dictionary) -> CardData:
	var card: CardData = null
	match data.get("card_type", ""):
		"POKEMON":
			var energy_type = PokemonCardData.EnergyType[data.get("pokemon_type", "COLORLESS")]
			match data.get("stage", "BASIC"):
				"BASIC":
					card = _basic(
						data["card_id"],
						data["display_name"],
						energy_type,
						data.get("hp_max", 0)
					)
				"STAGE1":
					card = _stage1(
						data["card_id"],
						data["display_name"],
						data.get("evolves_from", ""),
						energy_type,
						data.get("hp_max", 0)
					)
				"STAGE2":
					card = _stage2(
						data["card_id"],
						data["display_name"],
						data.get("evolves_from", ""),
						energy_type,
						data.get("hp_max", 0)
					)
		"TRAINER":
			match data.get("trainer_kind", "ITEM"):
				"ITEM":      card = _item(data["card_id"], data["display_name"])
				"SUPPORTER": card = _supporter(data["card_id"], data["display_name"])
				"STADIUM":   card = _stadium(data["card_id"], data["display_name"])
				"TOOL":      card = _tool(data["card_id"], data["display_name"])
		"ENERGY":
			var energy_type = PokemonCardData.EnergyType[data.get("energy_type", "COLORLESS")]
			card = _energy(data["card_id"], data["display_name"], energy_type)

	if card != null:
		card.art = _load_art(data["card_id"])
		if card is PokemonCardData:
			(card as PokemonCardData).name_slug = data.get("name_slug", data.get("card_id", ""))
		return card

	push_warning("_card_from_json: unhandled card_type '%s' for %s" % [data.get("card_type"), data.get("card_id")])
	return null

static func _load_folder(path: String, pool: Array[CardData]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("_load_folder: could not open " + path)
		return

	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if dir.current_is_dir():
			_load_folder(path + filename + "/", pool)
		elif filename.ends_with(".json"):
			var full_path := path + filename
			var raw := FileAccess.get_file_as_string(full_path)
			if raw == "":
				push_warning("_load_folder: empty or unreadable file: " + full_path)
			else:
				var parsed = JSON.parse_string(raw)
				if parsed == null:
					push_warning("_load_folder: failed to parse JSON: " + full_path)
				else:
					var card := _card_from_json(parsed)
					if card != null:
						pool.append(card)
		filename = dir.get_next()
	dir.list_dir_end()


static func _build_pool() -> Array[CardData]:
	var pool: Array[CardData] = []
	_load_folder("res://data/cards/", pool)
	if pool.is_empty():
		push_error("_build_pool: pool is empty — are the JSON files imported in Godot?")
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


static func _stage2(
	id: String,
	name: String,
	evolves_from: String,
	ptype: PokemonCardData.EnergyType,
	hp: int
) -> PokemonCardData:
	var d := PokemonCardData.new()
	d.card_id      = id
	d.display_name = name
	d.stage        = PokemonCardData.Stage.STAGE2
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
