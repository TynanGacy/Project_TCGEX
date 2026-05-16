extends GutTest
## Tests for ActionPromote.  Promotion is only valid while
## manager.promotion_phase_for == player_id, and only from bench to an empty
## active slot.

var _lib: CardLibrary


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func _first_occupied_bench(mgr: ManagerSystem, pid: int) -> String:
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [pid, s]
		if mgr.board_position.get_instance(sid) != null:
			return sid
	return ""


func test_promotes_bench_to_empty_active() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	## Place a bench Pokémon; leave active1 empty.
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	mgr.promotion_phase_for = 0
	var bench := _first_occupied_bench(mgr, 0)
	var bench_inst := mgr.board_position.get_instance(bench)

	var r := mgr.request_action(ActionPromote.new(0, bench, "p0_active1"))
	assert_true(r.ok, "Promote should succeed: %s" % r.reason)
	assert_eq(mgr.board_position.get_instance("p0_active1"), bench_inst,
		"Bench Pokémon should now occupy active1.")
	assert_eq(mgr.board_position.get_instance(bench), null,
		"Bench slot should now be empty.")
	assert_eq(mgr.promotion_phase_for, -1,
		"promotion_phase_for should clear after promote.")


func test_rejects_outside_promotion_phase() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	## promotion_phase_for is -1 by default — not the player's promotion phase.
	var bench := _first_occupied_bench(mgr, 0)
	var r := ActionPromote.new(0, bench, "p0_active1").validate(mgr)
	assert_false(r.ok, "Promote must require promotion_phase_for == player_id.")


func test_rejects_when_target_active_occupied() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	mgr.promotion_phase_for = 0
	var bench := _first_occupied_bench(mgr, 0)
	var r := ActionPromote.new(0, bench, "p0_active1").validate(mgr)
	assert_false(r.ok, "Cannot promote into an occupied active slot.")


func test_rejects_when_source_not_bench() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	mgr.promotion_phase_for = 0
	## Attempt to promote from a non-existent slot label.
	var r := ActionPromote.new(0, "p0_active1", "p0_active1").validate(mgr)
	assert_false(r.ok, "Source must be a bench slot.")
