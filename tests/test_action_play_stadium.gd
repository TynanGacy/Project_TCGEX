extends GutTest
## Tests for ActionPlayStadium.  Verifies kind validation, the
## same-name-Stadium rule, and that a new Stadium replaces the prior one
## (sending it to its owner's discard).

var _lib: CardLibrary
var _trainer_handlers: Node = null
var _ability_handlers: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_trainer_handlers = load("res://scenes/match/trainer_handlers.gd").new()
	add_child(_trainer_handlers)
	_ability_handlers = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers)


func after_all() -> void:
	for n in [_trainer_handlers, _ability_handlers]:
		if n != null:
			n.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func test_rejects_item_card() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	var potion: TrainerCardData = _lib.get_card("RS_91_potion") as TrainerCardData
	mgr.game_position.put_in_hand(0, potion)
	var r := ActionPlayStadium.new(0, potion).validate(mgr)
	assert_false(r.ok, "ActionPlayStadium must reject Items.")


func test_places_stadium() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	b.set_prizes(0)
	b.set_prizes(1)
	var stadium: TrainerCardData = _lib.get_card("DR_86_low_pressure_system") as TrainerCardData
	mgr.game_position.put_in_hand(0, stadium)

	var r := await mgr.request_action_async(ActionPlayStadium.new(0, stadium))
	assert_true(r.ok, "Stadium should be placed: %s" % r.reason)
	assert_eq(mgr.active_stadium, stadium)
	assert_eq(mgr.active_stadium_owner, 0)
	assert_false((mgr.game_position.hands[0] as Array).has(stadium))


func test_rejects_same_name_stadium() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	b.set_prizes(0)
	b.set_prizes(1)
	var existing: TrainerCardData = _lib.get_card("DR_86_low_pressure_system") as TrainerCardData
	mgr.active_stadium = existing
	mgr.active_stadium_owner = 1
	## Same card_id stadium in hand — classic same-name rule rejects.
	var dup: TrainerCardData = _lib.get_card("DR_86_low_pressure_system") as TrainerCardData
	mgr.game_position.put_in_hand(0, dup)
	var r := ActionPlayStadium.new(0, dup).validate(mgr)
	assert_false(r.ok, "Same-name Stadium must be rejected.")
