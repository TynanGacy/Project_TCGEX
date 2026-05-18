extends Node
## Singleton wrapping CardLibrary with one shared cache and art-loading.
## Lazy-loaded on first access so it doesn't depend on autoload _ready order.

const _CARDS_FOLDER := "res://data/cards"

var _library: CardLibrary = null
var _art_cache: Dictionary = {}  # card_id -> Texture2D


func _get_library() -> CardLibrary:
	if _library == null:
		_library = CardLibrary.load_from_folder(_CARDS_FOLDER)
	return _library


## Returns every loaded CardData (unordered).
func all_cards() -> Array:
	return _get_library().all_cards()


## Returns the CardData for card_id, or null if unknown.
func get_card(id: String) -> CardData:
	return _get_library().get_card(id)


## Returns the set prefix ("DR" / "RS" / "SS") parsed from a card_id, or "" if unparseable.
func set_of(card_id: String) -> String:
	var idx := card_id.find("_")
	if idx <= 0:
		return ""
	return card_id.substr(0, idx)


## Returns Dictionary[set_prefix -> Array[CardData]].
func cards_by_set() -> Dictionary:
	var out: Dictionary = {}
	for c in all_cards():
		var key := set_of((c as CardData).card_id)
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(c)
	return out


## Returns every distinct rarity string present in the loaded card pool,
## sorted by Pokémon-TCG tier order. Used by the deck-builder filter bar to
## populate its Rarity multi-select.
func all_rarities() -> Array[String]:
	var seen: Dictionary = {}
	for c in all_cards():
		for r in (c as CardData).rarities:
			seen[str(r)] = true
	var out: Array[String] = []
	for k in seen.keys():
		out.append(str(k))
	out.sort_custom(func(a: String, b: String):
		var ra := CardTextFormat._rank_one(a)
		var rb := CardTextFormat._rank_one(b)
		if ra != rb:
			return ra < rb
		return a < b)
	return out


## Loads (and caches) the art Texture2D for a card_id, or null if missing.
func load_art(card_id: String) -> Texture2D:
	if _art_cache.has(card_id):
		return _art_cache[card_id]
	var set_folder := set_of(card_id)
	if set_folder == "":
		return null
	var path := "res://assets/images/%s/%s.png" % [set_folder, card_id]
	if not ResourceLoader.exists(path):
		push_warning("CardDatabase.load_art: no image at %s" % path)
		_art_cache[card_id] = null
		return null
	var tex: Texture2D = load(path)
	_art_cache[card_id] = tex
	return tex


# ---------------------------------------------------------------------------
# Live-match deck API
#
# These wrap CardLibrary so the live match path uses the complete parser
# (abilities, effect_chain, extra_types, plays_as_pokemon, rules_text).
# Replaces the legacy `TestDeckFactory` helpers.
# ---------------------------------------------------------------------------


## Returns Dictionary[card_id -> CardData] for every parsed card.
## Used by DeckLoader and GameStateSerializer to resolve card IDs.
func card_pool_by_id() -> Dictionary:
	var out: Dictionary = {}
	for c in all_cards():
		out[(c as CardData).card_id] = c
	return out


## Builds a deck from an array of card IDs, skipping unknown IDs.
## Cards are NOT duplicated here — callers that need distinct instances
## per copy (e.g. DeckLoader) must duplicate templates themselves.
func build_deck(ids: Array) -> Array[CardData]:
	return _get_library().build_deck(ids)


## Random N-card fallback for when a deck file is missing or invalid.
## Each card in the returned deck is a fresh duplicate so identity
## tracking (e.g. _hand_cards keyed by CardData) stays one-to-one.
func build_random_deck(size: int = 60) -> Array[CardData]:
	var pool: Array = all_cards()
	var deck: Array[CardData] = []
	if pool.is_empty():
		push_error("CardDatabase.build_random_deck: pool is empty")
		return deck
	for _i in size:
		var template := pool[randi() % pool.size()] as CardData
		deck.append(template.duplicate() as CardData)
	return deck


## Loads art textures for every card in a deck and assigns each `card.art`.
## Shared Texture2D references are reused across duplicates of the same
## card_id within the deck. Cards that already have art are skipped.
func load_art_for_deck(deck: Array) -> void:
	var loaded: Dictionary = {}
	for c in deck:
		var card := c as CardData
		if card == null or card.art != null:
			continue
		if loaded.has(card.card_id):
			card.art = loaded[card.card_id]
			continue
		var tex: Texture2D = load_art(card.card_id)
		card.art = tex
		if tex != null:
			loaded[card.card_id] = tex
