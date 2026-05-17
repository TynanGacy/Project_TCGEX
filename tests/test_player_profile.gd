extends GutTest
## Tests for the PlayerProfile autoload: coin/card/pack mutations, signals,
## and the save/load JSON round-trip.
##
## The autoload itself persists to user://profile.json. To keep these tests
## independent of any real save on disk we reset the profile before each
## test and after the suite.

func before_each() -> void:
	PlayerProfile.reset_profile()


func after_all() -> void:
	PlayerProfile.reset_profile()


func test_add_coins_emits_signal_and_updates_balance() -> void:
	watch_signals(PlayerProfile)
	PlayerProfile.add_coins(150)
	assert_eq(PlayerProfile.coins, 150)
	assert_signal_emitted_with_parameters(PlayerProfile, "coins_changed", [150])


func test_spend_coins_blocks_when_underfunded() -> void:
	PlayerProfile.add_coins(50)
	assert_false(PlayerProfile.spend_coins(100), "underfunded spend rejected")
	assert_eq(PlayerProfile.coins, 50)
	assert_true(PlayerProfile.spend_coins(40), "affordable spend succeeds")
	assert_eq(PlayerProfile.coins, 10)


func test_collection_tracks_counts_and_signals() -> void:
	watch_signals(PlayerProfile)
	PlayerProfile.add_card("DR_100_charizard", 2)
	PlayerProfile.add_card("DR_100_charizard", 1)
	assert_eq(PlayerProfile.owned_count("DR_100_charizard"), 3)
	assert_signal_emit_count(PlayerProfile, "collection_changed", 2)
	PlayerProfile.add_card("DR_100_charizard", -3)
	assert_eq(PlayerProfile.owned_count("DR_100_charizard"), 0)
	assert_false(PlayerProfile.collection.has("DR_100_charizard"),
		"zero entries are pruned")


func test_grant_and_consume_pack() -> void:
	PlayerProfile.grant_pack("DR_booster", 2)
	assert_eq(PlayerProfile.pack_count("DR_booster"), 2)
	assert_true(PlayerProfile.consume_pack("DR_booster"))
	assert_eq(PlayerProfile.pack_count("DR_booster"), 1)
	assert_true(PlayerProfile.consume_pack("DR_booster"))
	assert_false(PlayerProfile.consume_pack("DR_booster"),
		"consume on empty pack inventory returns false")


func test_clear_collection_wipes_cards_but_keeps_coins_and_packs() -> void:
	PlayerProfile.add_coins(500)
	PlayerProfile.add_card("DR_100_charizard", 3)
	PlayerProfile.add_card("RS_3_blaziken", 2)
	PlayerProfile.grant_pack("DR_booster", 4)
	watch_signals(PlayerProfile)
	PlayerProfile.clear_collection()
	assert_eq(PlayerProfile.collection.size(), 0, "collection emptied")
	assert_eq(PlayerProfile.coins, 500, "coins preserved")
	assert_eq(PlayerProfile.pack_count("DR_booster"), 4, "packs preserved")
	assert_signal_emit_count(PlayerProfile, "collection_reset", 1,
		"one bulk reset signal instead of N collection_changed events")
	assert_signal_emit_count(PlayerProfile, "collection_changed", 0,
		"no per-card events on bulk reset — avoids O(N²) UI rebuild")


func test_save_load_round_trip() -> void:
	PlayerProfile.add_coins(777)
	PlayerProfile.add_card("DR_1_absol", 4)
	PlayerProfile.add_card("RS_3_blaziken", 2)
	PlayerProfile.grant_pack("DR_booster", 5)
	PlayerProfile.save_profile()

	## Mutate in-memory, then reload from disk and confirm values restored.
	PlayerProfile.add_coins(-777)
	PlayerProfile.collection.clear()
	PlayerProfile.pack_inventory.clear()
	PlayerProfile.load_profile()

	assert_eq(PlayerProfile.coins, 777)
	assert_eq(PlayerProfile.owned_count("DR_1_absol"), 4)
	assert_eq(PlayerProfile.owned_count("RS_3_blaziken"), 2)
	assert_eq(PlayerProfile.pack_count("DR_booster"), 5)
