class_name CardLibrary
## Loads card definitions from a folder of per-card JSON files and provides
## lookup by card_id.  Each file in the folder should contain one card object.
##
## Usage:
##   var library := CardLibrary.load_from_folder("res://data/cards")
##   var data := library.get_card("pikachu")          # CardData or null
##   var all  := library.all_cards()                  # Array of CardData
##   var deck := library.build_deck(["pikachu", ...]) # Array[CardData] (skips unknown ids)

var _cards: Dictionary = {}  # card_id (String) -> CardData


## Loads every *.json file in folder_path and returns a CardLibrary.
## Non-JSON files are silently ignored.
static func load_from_folder(folder_path: String) -> CardLibrary:
	var lib := CardLibrary.new()
	var dir := DirAccess.open(folder_path)
	if dir == null:
		push_error("CardLibrary: could not open folder '%s'" % folder_path)
		return lib
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			lib._load(folder_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	return lib


## Returns the CardData for card_id, or null if not found.
func get_card(id: String) -> CardData:
	return _cards.get(id, null)


## Returns all loaded CardData objects as an unordered array.
func all_cards() -> Array:
	return _cards.values()


## Builds a deck (Array[CardData]) from a list of card IDs.
## Unknown IDs are skipped with a warning; duplicates are preserved.
func build_deck(ids: Array) -> Array[CardData]:
	var deck: Array[CardData] = []
	for id in ids:
		var card := get_card(str(id))
		if card == null:
			push_warning("CardLibrary: unknown card_id '%s' — skipped" % id)
		else:
			deck.append(card)
	return deck


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _load(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("CardLibrary: could not read '%s'" % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("CardLibrary: expected a JSON object in '%s'" % path)
		return
	var card := _parse_entry(parsed as Dictionary)
	if card != null:
		_cards[card.card_id] = card


func _parse_entry(d: Dictionary) -> CardData:
	var card_type: String = d.get("card_type", "")
	match card_type:
		"POKEMON":
			return _parse_pokemon(d)
		"ENERGY":
			return _parse_energy(d)
		"TRAINER":
			return _parse_trainer(d)
		_:
			push_warning("CardLibrary: unknown card_type '%s' for card_id '%s'" % [
				card_type, d.get("card_id", "?")])
			return null


func _parse_pokemon(d: Dictionary) -> PokemonCardData:
	var card := PokemonCardData.new()
	card.card_id      = d.get("card_id", "")
	card.display_name = d.get("display_name", "")
	card.card_type    = CardData.CardType.POKEMON
	card.rules_text   = d.get("rules_text", "")

	var stage_str: String = d.get("stage", "BASIC")
	match stage_str:
		"STAGE1": card.stage = PokemonCardData.Stage.STAGE1
		"STAGE2": card.stage = PokemonCardData.Stage.STAGE2
		_:        card.stage = PokemonCardData.Stage.BASIC

	card.evolves_from = d.get("evolves_from", "")
	card.hp_max       = int(d.get("hp_max", 50))
	card.retreat_cost = int(d.get("retreat_cost", 1))
	card.pokemon_type = _parse_energy_type(d.get("pokemon_type", "COLORLESS"))
	card.weakness     = _parse_energy_type(d.get("weakness", "NONE"))
	card.resistance   = _parse_energy_type(d.get("resistance", "NONE"))

	if d.has("attacks") and d["attacks"] is Array:
		for atk_dict in d["attacks"] as Array:
			if atk_dict is Dictionary:
				card.attacks.append(_parse_attack(atk_dict as Dictionary))

	return card


func _parse_energy(d: Dictionary) -> EnergyCardData:
	var card := EnergyCardData.new()
	card.card_id      = d.get("card_id", "")
	card.display_name = d.get("display_name", "")
	card.card_type    = CardData.CardType.ENERGY
	card.rules_text   = d.get("rules_text", "")
	card.energy_type  = _parse_energy_type(d.get("energy_type", "COLORLESS"))
	card.provides     = int(d.get("provides", 1))
	return card


func _parse_trainer(d: Dictionary) -> TrainerCardData:
	var card := TrainerCardData.new()
	card.card_id      = d.get("card_id", "")
	card.display_name = d.get("display_name", "")
	card.card_type    = CardData.CardType.TRAINER
	card.rules_text   = d.get("rules_text", "")

	var kind_str: String = d.get("trainer_kind", "ITEM")
	match kind_str:
		"SUPPORTER": card.trainer_kind = TrainerCardData.TrainerKind.SUPPORTER
		"STADIUM":   card.trainer_kind = TrainerCardData.TrainerKind.STADIUM
		"TOOL":      card.trainer_kind = TrainerCardData.TrainerKind.TOOL
		_:           card.trainer_kind = TrainerCardData.TrainerKind.ITEM

	return card


func _parse_attack(d: Dictionary) -> AttackData:
	var atk := AttackData.new()
	atk.name             = d.get("name", "")
	atk.base_damage      = int(d.get("base_damage", 0))
	atk.text             = d.get("text", "")
	atk.cost_colorless   = int(d.get("cost_colorless", 0))
	atk.cost_fire        = int(d.get("cost_fire", 0))
	atk.cost_water       = int(d.get("cost_water", 0))
	atk.cost_grass       = int(d.get("cost_grass", 0))
	atk.cost_lightning   = int(d.get("cost_lightning", 0))
	atk.cost_psychic     = int(d.get("cost_psychic", 0))
	atk.cost_fighting    = int(d.get("cost_fighting", 0))
	atk.cost_darkness    = int(d.get("cost_darkness", 0))
	atk.cost_metal       = int(d.get("cost_metal", 0))
	return atk


func _parse_energy_type(s: String) -> PokemonCardData.EnergyType:
	match s:
		"FIRE":      return PokemonCardData.EnergyType.FIRE
		"WATER":     return PokemonCardData.EnergyType.WATER
		"GRASS":     return PokemonCardData.EnergyType.GRASS
		"LIGHTNING": return PokemonCardData.EnergyType.LIGHTNING
		"PSYCHIC":   return PokemonCardData.EnergyType.PSYCHIC
		"FIGHTING":  return PokemonCardData.EnergyType.FIGHTING
		"DARKNESS":  return PokemonCardData.EnergyType.DARKNESS
		"METAL":     return PokemonCardData.EnergyType.METAL
		"DRAGON":    return PokemonCardData.EnergyType.DRAGON
		"COLORLESS": return PokemonCardData.EnergyType.COLORLESS
		_:           return PokemonCardData.EnergyType.NONE
