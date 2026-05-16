extends GutTest
## Tests for ActionAttachEnergy.  Verifies the once-per-turn energy lock,
## hand/slot validation, and that the apply step flips the
## energy_attached_this_turn flag.

var _lib: CardLibrary
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	## Loaded for the on-attach Poké-Body / SpecialEnergyEffects hooks the
	## action calls into; without it those AbilityEffects calls fall through.
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func test_validates_and_attaches_to_active() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var inst := b.place_active(0, "RS_52_electrike")
	b.set_prizes(0)
	b.set_prizes(1)
	var energy: EnergyCardData = _lib.get_card("RS_109_lightning_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, energy)

	var action := ActionAttachEnergy.new(0, energy, "p0_active1")
	var r := await mgr.request_action_async(action)
	assert_true(r.ok, "Attach should succeed on first try.")
	assert_eq(inst.attached_energy.size(), 1, "Energy should be on the Pokémon.")
	assert_true(mgr.energy_attached_this_turn[0],
		"energy_attached_this_turn flag should flip on apply.")


func test_once_per_turn_lock_rejects_second_attach() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike")
	b.set_prizes(0)
	b.set_prizes(1)
	var e1: EnergyCardData = _lib.get_card("RS_109_lightning_energy") as EnergyCardData
	var e2: EnergyCardData = _lib.get_card("RS_109_lightning_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, e1)
	mgr.game_position.put_in_hand(0, e2)

	var r1 := await mgr.request_action_async(ActionAttachEnergy.new(0, e1, "p0_active1"))
	assert_true(r1.ok)
	var r2 := ActionAttachEnergy.new(0, e2, "p0_active1").validate(mgr)
	assert_false(r2.ok, "Second attach in the same turn must be rejected.")


func test_rejects_when_card_not_in_hand() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike")
	var stray: EnergyCardData = _lib.get_card("RS_109_lightning_energy") as EnergyCardData
	## Note: stray was never put into the hand.
	var r := ActionAttachEnergy.new(0, stray, "p0_active1").validate(mgr)
	assert_false(r.ok, "Attach should fail when the card is not in hand.")


func test_rejects_when_slot_empty() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var energy: EnergyCardData = _lib.get_card("RS_109_lightning_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, energy)
	var r := ActionAttachEnergy.new(0, energy, "p0_active1").validate(mgr)
	assert_false(r.ok, "Attach should fail when target slot has no Pokémon.")


func test_attaches_to_bench_slot() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "RS_52_electrike")
	var bench_inst := b.place_bench(0, "RS_63_poochyena")
	b.set_prizes(0)
	b.set_prizes(1)
	var energy: EnergyCardData = _lib.get_card("RS_104_grass_energy") as EnergyCardData
	mgr.game_position.put_in_hand(0, energy)

	## Reach into the board to find the bench slot bench_inst lives in.
	var bench_slot: String = ""
	for s in BoardPosition.BENCH_SLOTS:
		var sid := "p0_%s" % s
		if mgr.board_position.get_instance(sid) == bench_inst:
			bench_slot = sid
			break
	assert_ne(bench_slot, "", "Test setup: should have found bench slot.")

	var r := await mgr.request_action_async(ActionAttachEnergy.new(0, energy, bench_slot))
	assert_true(r.ok)
	assert_eq(bench_inst.attached_energy.size(), 1)
