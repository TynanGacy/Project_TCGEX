extends GutTest
## Tests for Wave 5 — Baby Evolution power (Pichu / Azurill / Elekid / Wynaut).
##
## Each baby card has a Poké-Power that promotes itself into a specific
## Basic Pokémon from hand, clearing all damage counters in the process.
## Once per turn, blocked on the turn the baby entered play, blocked on the
## game's first turn.

var _lib: CardLibrary
var _attack_handlers: Node = null
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_attack_handlers = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_attack_handlers)
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _attack_handlers != null:
		_attack_handlers.queue_free()
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func _find_slot(mgr: ManagerSystem, inst: PokemonInstance) -> String:
	for pid in [0, 1]:
		for s in (BoardPosition.ACTIVE_SLOTS + BoardPosition.BENCH_SLOTS):
			var sid := "p%d_%s" % [pid, s]
			if mgr.board_position.get_instance(sid) == inst:
				return sid
	return ""


func test_pichu_baby_evolves_into_pikachu_and_clears_damage() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	## Pichu in active, damaged.
	var pichu_inst := b.place_active(0, "SS_20_pichu", {"hp": 10})
	## Pikachu in hand.
	var pikachu := _lib.get_card("SS_72_pikachu") as PokemonCardData
	mgr.game_position.put_in_hand(0, pikachu)

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0)
	)
	assert_true(r.ok, "Baby Evolution should activate: %s" % r.reason)
	assert_eq(pichu_inst.card.name_slug, "pikachu",
		"Slot occupant should now be Pikachu.")
	assert_eq(pichu_inst.current_hp, pichu_inst.max_hp,
		"All damage counters should be removed (HP = max).")
	assert_eq(pichu_inst.max_hp, pikachu.hp_max,
		"max_hp should update to Pikachu's hp_max.")
	assert_true(pichu_inst.power_used_this_turn,
		"Once-per-turn flag should be set.")


func test_baby_evolution_rejects_without_target_in_hand() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "SS_20_pichu")
	## Hand has the wrong basic.
	mgr.game_position.put_in_hand(0, _lib.get_card("SS_68_marill"))

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0)
	)
	assert_false(r.ok, "Baby Evolution should reject without Pikachu in hand.")


func test_baby_evolution_blocked_on_entered_play_turn() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var pichu_inst := b.place_active(0, "SS_20_pichu")
	mgr.game_position.put_in_hand(0, _lib.get_card("SS_72_pikachu"))
	## Mark Pichu as having entered play this turn.
	mgr.pokemon_entered_play_this_turn[0].append(pichu_inst)

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0)
	)
	assert_false(r.ok,
		"Baby Evolution should be blocked the turn the baby came into play.")


func test_azurill_baby_evolves_into_marill() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var azu := b.place_active(0, "SS_31_azurill", {"hp": 10})
	mgr.game_position.put_in_hand(0, _lib.get_card("SS_68_marill"))

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0)
	)
	assert_true(r.ok, "Azurill Baby Evolution: %s" % r.reason)
	assert_eq(azu.card.name_slug, "marill")
	assert_eq(azu.current_hp, azu.max_hp,
		"Damage counters cleared after Baby Evolution.")


func test_elekid_baby_evolves_into_electabuzz() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var elekid := b.place_active(0, "SS_36_elekid")
	mgr.game_position.put_in_hand(0, _lib.get_card("SS_35_electabuzz"))

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0)
	)
	assert_true(r.ok, "Elekid Baby Evolution: %s" % r.reason)
	assert_eq(elekid.card.name_slug, "electabuzz")


func test_wynaut_baby_evolves_into_wobbuffet() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var wyn := b.place_active(0, "SS_54_wynaut")
	mgr.game_position.put_in_hand(0, _lib.get_card("SS_26_wobbuffet"))

	var r: ActionResult = await mgr.request_action_async(
		ActionUseAbility.new(0, "p0_active1", 0)
	)
	assert_true(r.ok, "Wynaut Baby Evolution: %s" % r.reason)
	assert_eq(wyn.card.name_slug, "wobbuffet")
