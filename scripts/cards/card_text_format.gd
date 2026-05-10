class_name CardTextFormat
## Formatters used by the deck builder's text-mode rows.
##
## Example output for `3× Numel | {R} | DR 69/100 | —`:
##   row(card, count=3) → "3× Numel | {R} | DR 69/100 | —"

const _ENERGY_LETTER: Dictionary = {
	PokemonCardData.EnergyType.FIRE:      "R",
	PokemonCardData.EnergyType.WATER:     "W",
	PokemonCardData.EnergyType.GRASS:     "G",
	PokemonCardData.EnergyType.LIGHTNING: "L",
	PokemonCardData.EnergyType.PSYCHIC:   "P",
	PokemonCardData.EnergyType.FIGHTING:  "F",
	PokemonCardData.EnergyType.DARKNESS:  "D",
	PokemonCardData.EnergyType.METAL:     "M",
	PokemonCardData.EnergyType.COLORLESS: "C",
	PokemonCardData.EnergyType.DRAGON:    "N",
	PokemonCardData.EnergyType.NONE:      "?",
}


## Returns the printable type token (e.g. "{R}", "It", "{C}").
static func type_token(card: CardData) -> String:
	if card == null:
		return "?"
	if card is PokemonCardData:
		return "{%s}" % _ENERGY_LETTER.get((card as PokemonCardData).pokemon_type, "?")
	if card is EnergyCardData:
		return "{%s}" % _ENERGY_LETTER.get((card as EnergyCardData).energy_type, "?")
	if card is TrainerCardData:
		match (card as TrainerCardData).trainer_kind:
			TrainerCardData.TrainerKind.ITEM:      return "It"
			TrainerCardData.TrainerKind.SUPPORTER: return "Su"
			TrainerCardData.TrainerKind.STADIUM:   return "St"
			TrainerCardData.TrainerKind.TOOL:      return "To"
	return "?"


## "DR 69/100" — uses set totals derived from the loaded CardDatabase pool.
static func set_locator(card: CardData) -> String:
	if card == null:
		return "?"
	var prefix := CardDatabase.set_of(card.card_id)
	var num := card_number(card)
	var total := _set_total(prefix)
	return "%s %s/%d" % [prefix, num, total]


static func card_number(card: CardData) -> String:
	if card == null:
		return "?"
	var parts := card.card_id.split("_")
	if parts.size() < 2:
		return "?"
	return parts[1]


## Newest-first set rank used for sorting in the deck builder / card list.
## Lower rank = sorts earlier. Add new sets to the front of this list as
## they're added to data/cards/.
const _SET_RANK: Array[String] = ["DR", "SS", "RS"]


static func set_rank(prefix: String) -> int:
	var idx := _SET_RANK.find(prefix)
	## Unknown sets sort to the end, alphabetically among themselves.
	return idx if idx >= 0 else _SET_RANK.size()


static func card_number_int(card_id: String) -> int:
	var parts := card_id.split("_")
	if parts.size() < 2:
		return 0
	return int(parts[1])


## Comparator: set rank (newest first) then numeric card number ascending.
## Use as: array.sort_custom(CardTextFormat.compare_cards)
static func compare_cards(a: CardData, b: CardData) -> bool:
	if a == null or b == null:
		return a != null
	var ra := set_rank(CardDatabase.set_of(a.card_id))
	var rb := set_rank(CardDatabase.set_of(b.card_id))
	if ra != rb:
		return ra < rb
	return card_number_int(a.card_id) < card_number_int(b.card_id)


## Variant that takes raw ids; used by DeckPane.
static func compare_card_ids(a: String, b: String) -> bool:
	var ra := set_rank(CardDatabase.set_of(a))
	var rb := set_rank(CardDatabase.set_of(b))
	if ra != rb:
		return ra < rb
	return card_number_int(a) < card_number_int(b)


# ---------------------------------------------------------------------------
# Alternate sort comparators
# ---------------------------------------------------------------------------

## Canonical TCG energy ordering (Grass, Fire, Water, Lightning, Psychic,
## Fighting, Darkness, Metal, Colorless). The enum's own integer order is
## different (FIRE=1, WATER=2, GRASS=3, …) so we map enum → rank explicitly.
## Dragon is omitted: no Dragon type exists in the DR/RS/SS era.
const _ENERGY_SORT_RANK: Dictionary = {
	PokemonCardData.EnergyType.GRASS:     0,
	PokemonCardData.EnergyType.FIRE:      1,
	PokemonCardData.EnergyType.WATER:     2,
	PokemonCardData.EnergyType.LIGHTNING: 3,
	PokemonCardData.EnergyType.PSYCHIC:   4,
	PokemonCardData.EnergyType.FIGHTING:  5,
	PokemonCardData.EnergyType.DARKNESS:  6,
	PokemonCardData.EnergyType.METAL:     7,
	PokemonCardData.EnergyType.COLORLESS: 8,
	PokemonCardData.EnergyType.NONE:      99,
}


## Energy type used as a sort key; cards with no energy type sort last.
## For multi-typed cards (Multi/Rainbow Energy, dual-type Pokémon) we sort
## by the lowest-ranked of their types so the card lands as early as possible
## in the canonical TCG ordering — which means the Energy filter still puts
## it next to the type the player most likely cares about.
static func _energy_sort_key(card: CardData) -> int:
	var types := card_energy_types(card)
	if types.is_empty():
		return 99
	var best := 99
	for t in types:
		var rank := int(_ENERGY_SORT_RANK.get(t, 99))
		if rank < best:
			best = rank
	return best


## Returns every energy type a card carries — primary plus extras.
## Multi/Rainbow-style energy cards include each standard type so the
## deck-builder energy filter matches them under any selection.
static func card_energy_types(card: CardData) -> Array[int]:
	var out: Array[int] = []
	if card is PokemonCardData:
		var p := card as PokemonCardData
		out.append(int(p.pokemon_type))
		for t in p.extra_types:
			if not out.has(int(t)):
				out.append(int(t))
	elif card is EnergyCardData:
		var e := card as EnergyCardData
		out.append(int(e.energy_type))
		for t in e.extra_types:
			if not out.has(int(t)):
				out.append(int(t))
	return out


static func compare_by_type(a: CardData, b: CardData) -> bool:
	if a == null or b == null:
		return a != null
	if a.card_type != b.card_type:
		return a.card_type < b.card_type
	return compare_cards(a, b)


static func compare_by_energy(a: CardData, b: CardData) -> bool:
	if a == null or b == null:
		return a != null
	var ea := _energy_sort_key(a)
	var eb := _energy_sort_key(b)
	if ea != eb:
		return ea < eb
	return compare_cards(a, b)


## Pokémon-TCG tier order: common < uncommon < rare < rare holo < rare holo ex
## < rare secret < promo. Unknown / empty rarity sorts last. Tiebreak by set/number.
const _RARITY_RANK := {
	"common": 0,
	"uncommon": 1,
	"rare": 2,
	"rare holo": 3,
	"rare holo ex": 4,
	"rare secret": 5,
}

## Rank for a single rarity string. Unknown / empty → INF (sorts last).
static func _rank_one(s: String) -> int:
	var key := s.strip_edges().to_lower()
	if key == "":
		return 1 << 30
	if _RARITY_RANK.has(key):
		return _RARITY_RANK[key]
	if key.find("promo") != -1:
		return 6
	if key.begins_with("rare holo ex"):
		return 4
	if key.begins_with("rare holo"):
		return 3
	if key.begins_with("rare"):
		return 2
	return 1 << 30


## A multi-rarity card sorts at its best (lowest) tier — that's the rarity
## tier most players think of it as belonging to.
static func _rarity_rank(card: CardData) -> int:
	if card == null or card.rarities.is_empty():
		return 1 << 30
	var best := 1 << 30
	for r in card.rarities:
		var rank := _rank_one(str(r))
		if rank < best:
			best = rank
	return best


## Default rarity sort goes "best first": Rare Secret → Promo → Rare Holo EX
## → Rare Holo → Rare → Uncommon → Common, with unknown / empty rarity always
## last. Reverse-direction (handled in CardGrid) flips the whole list.
static func compare_by_rarity(a: CardData, b: CardData) -> bool:
	if b == null:
		return a != null
	if a == null:
		return false
	var ra := _rarity_rank(a)
	var rb := _rarity_rank(b)
	var unranked := 1 << 30
	var unk_a := ra == unranked
	var unk_b := rb == unranked
	if unk_a != unk_b:
		return not unk_a  ## known rarities before unknown
	if ra != rb:
		return ra > rb    ## higher tier first within the ranked group
	return compare_cards(a, b)


## Placeholder — collection / ownership isn't implemented yet. Returns the
## default ordering until a player-collection store exists.
static func compare_by_collection(a: CardData, b: CardData) -> bool:
	return compare_cards(a, b)


## Returns the comparator function for a sort key string.
##   "default"    — set rank (newest first) then number
##   "type"       — card type then default
##   "energy"     — energy/pokemon type then default
##   "rarity"     — Pokémon-TCG tier order then default
##   "collection" — placeholder (default order)
static func comparator_for(sort_key: String) -> Callable:
	match sort_key:
		"type":       return Callable(CardTextFormat, "compare_by_type")
		"energy":     return Callable(CardTextFormat, "compare_by_energy")
		"rarity":     return Callable(CardTextFormat, "compare_by_rarity")
		"collection": return Callable(CardTextFormat, "compare_by_collection")
		_:            return Callable(CardTextFormat, "compare_cards")


static func rarity(card: CardData) -> String:
	if card == null or card.rarities.is_empty():
		return "—"
	return " / ".join(card.rarities)


## Full one-line text-mode row.
static func row(card: CardData, count: int) -> String:
	if card == null:
		return ""
	return "%d× %s | %s | %s | %s" % [
		count,
		card.display_name,
		type_token(card),
		set_locator(card),
		rarity(card),
	]


# ---------------------------------------------------------------------------
# Set-total cache (derived from CardDatabase pool on first access)
# ---------------------------------------------------------------------------

static var _set_totals: Dictionary = {}


static func _set_total(prefix: String) -> int:
	if _set_totals.is_empty():
		var by_set: Dictionary = CardDatabase.cards_by_set()
		for k in by_set.keys():
			_set_totals[k] = (by_set[k] as Array).size()
	return int(_set_totals.get(prefix, 0))
