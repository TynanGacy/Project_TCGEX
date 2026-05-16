extends GutTest
## Tests for ActionRetreat.  Covers happy retreat with energy discard,
## insufficient-energy rejection, Asleep/Paralyzed blocks, the once-per-turn
## flag, and Balloon Berry free retreat.

var _lib: CardLibrary
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func test_retreats_and_discards_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Lairon — retreat_cost 2.
	var active := b.place_active(0, "RS_36_lairon", {
		"energy": [
			"RS_104_grass_energy", "RS_104_grass_energy", "RS_104_grass_energy",
		],
	})
	b.place_bench(0, "RS_63_poochyena")
	b.place_active(1, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var bench_slot := mgr.board_position.first_empty_bench(0)
	## first_empty_bench gives the next empty slot — back up by one to land
	## on the one we just placed Poochyena in.
	var occupied: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) != null:
			occupied = sid
			break
	assert_ne(occupied, "", "Test setup: bench Pokémon missing.")

	## Exactly enough energy to retreat — no choice needed, auto-discards.
	## Detach the third energy so we hit the "exactly equal" branch.
	active.attached_energy.pop_back()
	var r := await mgr.request_action_async(ActionRetreat.new(0, "p0_active1", occupied))
	assert_true(r.ok, "Retreat should succeed: %s" % r.reason)
	assert_eq(active.attached_energy.size(), 0, "Both energies should be discarded.")
	assert_true(mgr.retreat_used_this_turn[0],
		"retreat_used_this_turn flag should flip.")


func test_rejects_when_insufficient_energy() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_36_lairon", {"energy": ["RS_104_grass_energy"]})
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var bench: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) != null:
			bench = sid
			break
	var r := ActionRetreat.new(0, "p0_active1", bench).validate(mgr)
	assert_false(r.ok, "Retreat should fail with insufficient energy.")


func test_rejects_when_asleep() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {
		"energy": ["RS_109_lightning_energy"],
		"conditions": [PokemonInstance.SpecialCondition.ASLEEP],
	})
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var bench: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) != null:
			bench = sid
			break
	var r := ActionRetreat.new(0, "p0_active1", bench).validate(mgr)
	assert_false(r.ok, "Asleep Pokémon cannot retreat.")


func test_rejects_when_paralyzed() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {
		"energy": ["RS_109_lightning_energy"],
		"conditions": [PokemonInstance.SpecialCondition.PARALYZED],
	})
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var bench: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) != null:
			bench = sid
			break
	var r := ActionRetreat.new(0, "p0_active1", bench).validate(mgr)
	assert_false(r.ok, "Paralyzed Pokémon cannot retreat.")


func test_balloon_berry_free_retreat_discards_tool() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var active := b.place_active(0, "RS_36_lairon")  ## zero energy
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var berry: TrainerCardData = _lib.get_card("DR_82_balloon_berry") as TrainerCardData
	active.attach_tool(berry)
	var bench: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) != null:
			bench = sid
			break

	var r := await mgr.request_action_async(ActionRetreat.new(0, "p0_active1", bench))
	assert_true(r.ok, "Balloon Berry should grant free retreat.")
	## After retreat, the berry should be in the discard pile and not on the
	## Pokémon (which is now in the bench slot).
	var moved: PokemonInstance = mgr.board_position.get_instance(bench)
	assert_eq(moved.attached_tools.size(), 0, "Berry should be detached.")
	assert_true((mgr.game_position.discards[0] as Array).has(berry),
		"Berry should be in player 0's discard.")


func test_rejects_when_already_retreated() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike", {"energy": ["RS_109_lightning_energy"]})
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	mgr.retreat_used_this_turn[0] = true
	var bench: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) != null:
			bench = sid
			break
	var r := ActionRetreat.new(0, "p0_active1", bench).validate(mgr)
	assert_false(r.ok, "Cannot retreat twice in a turn.")
