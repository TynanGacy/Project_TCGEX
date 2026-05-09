class_name DeckValidator
## Pure-logic validator for deck models built in the in-game deck builder.
##
## Deck model: Dictionary[card_id (String) -> count (int)].
## Returns an Array[String] of human-readable error messages; empty == valid.
##
## Hard rules (all blocking):
##   1. Total card count must be exactly 60.
##   2. No more than 4 copies of any non-basic-Energy card.
##      (Basic Energy = EnergyCardData with provides == 1; unlimited copies.)
##   3. At least 1 Basic Pokémon (PokemonCardData with stage == BASIC).

const DECK_SIZE: int = 60
const COPY_LIMIT: int = 4

## Names of basic Energy cards — these are the only cards exempt from the
## 4-copy limit. Special Energies (Rainbow, Multi, Darkness, Metal in this
## era) and any future special energy still cap at 4. Lookup is by exact
## display_name to match the source JSON; no schema flag exists yet.
const BASIC_ENERGY_NAMES: Array[String] = [
	"Grass Energy",
	"Fire Energy",
	"Water Energy",
	"Lightning Energy",
	"Psychic Energy",
	"Fighting Energy",
]


static func is_basic_energy(card: CardData) -> bool:
	return card != null and card.display_name in BASIC_ENERGY_NAMES


static func validate(model: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	var total: int = _total_count(model)
	if total != DECK_SIZE:
		errors.append("Deck must contain exactly %d cards (currently %d)." % [DECK_SIZE, total])

	var over_limit: Array[String] = []
	var basic_pokemon_count: int = 0

	for card_id in model.keys():
		var count: int = int(model[card_id])
		if count <= 0:
			continue
		var card: CardData = CardDatabase.get_card(card_id)
		if card == null:
			errors.append("Unknown card: %s" % card_id)
			continue

		if not is_basic_energy(card) and count > COPY_LIMIT:
			over_limit.append("%s (%d)" % [card.display_name, count])

		if card is PokemonCardData and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			basic_pokemon_count += count

	if not over_limit.is_empty():
		errors.append("More than %d copies: %s." % [COPY_LIMIT, ", ".join(over_limit)])

	if basic_pokemon_count == 0:
		errors.append("Deck must include at least 1 Basic Pokémon.")

	return errors


static func total_count(model: Dictionary) -> int:
	return _total_count(model)


static func basic_pokemon_count(model: Dictionary) -> int:
	var n := 0
	for card_id in model.keys():
		var card: CardData = CardDatabase.get_card(card_id)
		if card is PokemonCardData and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			n += int(model[card_id])
	return n


static func _total_count(model: Dictionary) -> int:
	var n := 0
	for v in model.values():
		n += int(v)
	return n
