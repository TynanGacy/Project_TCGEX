class_name DeckLoader
## Loads a player's deck from an editable JSON configuration file.
##
## Edit  data/decks/player_deck.json   to customise Player 0's deck.
## Edit  data/decks/opponent_deck.json to customise Player 1's deck.
##
## File format:
##   {
##     "cards": [
##       { "card_id": "RS_73_torchic",   "count": 4 },
##       { "card_id": "RS_27_combusken", "count": 3 },
##       ...
##     ]
##   }
##
## Each "card_id" must match the id field in one of the JSON files under
## data/cards/.  If a file is missing, unreadable, or resolves to an empty
## deck, the loader falls back to a random 60-card deck via TestDeckFactory.

const PLAYER_DECK_PATH   := "res://data/decks/player_deck.json"
const OPPONENT_DECK_PATH := "res://data/decks/opponent_deck.json"
const DECKS_DIR          := "res://data/decks/"


## Returns the CardData array for [player_id] (0 = player, 1 = opponent).
## If [override_path] is non-empty it is used instead of the default file.
static func load_deck(player_id: int, override_path: String = "") -> Array[CardData]:
	if not override_path.is_empty():
		return _load_from_file(override_path)
	var path := PLAYER_DECK_PATH if player_id == 0 else OPPONENT_DECK_PATH
	return _load_from_file(path)


## Returns every .json file in DECKS_DIR whose card entries sum to exactly 60.
## Each element is a Dictionary with "path" (res:// path) and "label" (display name).
static func get_valid_decks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var files := DirAccess.get_files_at(DECKS_DIR)
	for fname in files:
		if not fname.ends_with(".json"):
			continue
		var path := DECKS_DIR + fname
		var raw := FileAccess.get_file_as_string(path)
		if raw.is_empty():
			continue
		var parsed = JSON.parse_string(raw)
		if parsed == null or not (parsed is Dictionary):
			continue
		var entries = (parsed as Dictionary).get("cards", null)
		if entries == null or not (entries is Array):
			continue
		var total := 0
		for entry in entries as Array:
			if entry is Dictionary:
				total += int((entry as Dictionary).get("count", 0))
		if total == 60:
			var label := fname.trim_suffix(".json").replace("_", " ")
			result.append({"path": path, "label": label})
	return result


static func _load_from_file(path: String) -> Array[CardData]:
	if not FileAccess.file_exists(path):
		push_warning("DeckLoader: '%s' not found — using random deck." % path)
		return TestDeckFactory.build_deck(60)

	var raw := FileAccess.get_file_as_string(path)
	if raw.is_empty():
		push_warning("DeckLoader: '%s' is empty — using random deck." % path)
		return TestDeckFactory.build_deck(60)

	var parsed = JSON.parse_string(raw)
	if parsed == null or not (parsed is Dictionary):
		push_warning("DeckLoader: failed to parse '%s' — using random deck." % path)
		return TestDeckFactory.build_deck(60)

	var entries = (parsed as Dictionary).get("cards", null)
	if entries == null or not (entries is Array):
		push_warning("DeckLoader: '%s' has no 'cards' array — using random deck." % path)
		return TestDeckFactory.build_deck(60)

	var pool := TestDeckFactory._build_card_pool_by_id()
	var deck: Array[CardData] = []

	for entry in entries as Array:
		if not (entry is Dictionary):
			continue
		var cid: String = str((entry as Dictionary).get("card_id", ""))
		var cnt: int    = int((entry as Dictionary).get("count", 1))
		if cid.is_empty():
			continue
		if not pool.has(cid):
			push_warning("DeckLoader: unknown card_id '%s' — skipping." % cid)
			continue
		for _i in cnt:
			deck.append(pool[cid] as CardData)

	if deck.is_empty():
		push_warning("DeckLoader: deck from '%s' resolved to 0 cards — using random deck." % path)
		return TestDeckFactory.build_deck(60)

	return deck
