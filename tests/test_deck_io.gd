extends GutTest
## Covers DeckIO save/load helpers and slugification.

const _TEST_SLUG := "__gut_test_deck_io"


func before_each() -> void:
	_cleanup_test_file()


func after_each() -> void:
	_cleanup_test_file()


func test_save_then_load_round_trip_preserves_counts() -> void:
	var path := DeckIO.user_path_for_slug(_TEST_SLUG)
	var model := {
		"DR_100_charizard": 4,
		"RS_104_grass_energy": 30,
		"RS_1_aggron": 2,
	}
	var err := DeckIO.save_model(model, path)
	assert_eq(err, OK, "save_model should succeed")
	assert_true(FileAccess.file_exists(path), "deck file should exist on disk")

	var loaded := DeckIO.load_model(path)
	assert_eq(loaded.size(), model.size())
	for k in model.keys():
		assert_eq(int(loaded.get(k, 0)), int(model[k]), "count mismatch for %s" % k)


func test_load_missing_file_returns_empty_model() -> void:
	var loaded := DeckIO.load_model("user://this_file_should_not_exist.json")
	assert_eq(loaded.size(), 0)


func test_save_skips_zero_or_negative_counts() -> void:
	var path := DeckIO.user_path_for_slug(_TEST_SLUG)
	var model := {
		"DR_100_charizard": 4,
		"RS_1_aggron": 0,    ## should be omitted
		"RS_2_x":          -3,   ## should be omitted
	}
	DeckIO.save_model(model, path)
	var loaded := DeckIO.load_model(path)
	assert_eq(loaded.size(), 1)
	assert_true(loaded.has("DR_100_charizard"))


func test_list_user_decks_finds_saved_deck() -> void:
	var path := DeckIO.user_path_for_slug(_TEST_SLUG)
	DeckIO.save_model({"DR_100_charizard": 4}, path)
	var entries := DeckIO.list_user_decks()
	var found := false
	for e in entries:
		if (e as Dictionary).get("path", "") == path:
			found = true
			break
	assert_true(found, "saved deck should appear in list_user_decks()")


# ---------------------------------------------------------------------------
# Slugify
# ---------------------------------------------------------------------------

func test_slugify_lowercases_and_underscores() -> void:
	assert_eq(DeckIO.slugify("My Fire Deck"), "my_fire_deck")
	assert_eq(DeckIO.slugify("Charizard-Blaziken"), "charizard_blaziken")


func test_slugify_strips_punctuation_and_collapses_underscores() -> void:
	assert_eq(DeckIO.slugify("!!Hello,, World!!"), "hello_world")
	assert_eq(DeckIO.slugify("a   b"), "a_b")


func test_slugify_falls_back_to_deck_for_empty_input() -> void:
	assert_eq(DeckIO.slugify(""),    "deck")
	assert_eq(DeckIO.slugify("   "), "deck")
	assert_eq(DeckIO.slugify("!!!"), "deck")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _cleanup_test_file() -> void:
	var path := DeckIO.user_path_for_slug(_TEST_SLUG)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
