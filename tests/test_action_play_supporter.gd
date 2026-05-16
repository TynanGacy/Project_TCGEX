extends GutTest
## Tests for ActionPlaySupporter.  Verifies kind validation and the
## once-per-turn Supporter lock.

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
	var r := ActionPlaySupporter.new(0, potion).validate(mgr)
	assert_false(r.ok, "ActionPlaySupporter must reject Items.")


func test_once_per_turn_lock() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	b.set_prizes(0)
	b.set_prizes(1)
	## Fill the deck so draw_until has cards to pull.
	for i in range(8):
		mgr.game_position.decks[0].append(_lib.get_card("RS_104_grass_energy"))
	var birch_a: TrainerCardData = _lib.get_card("RS_89_professor_birch") as TrainerCardData
	mgr.game_position.put_in_hand(0, birch_a)

	var first := await mgr.request_action_async(ActionPlaySupporter.new(0, birch_a))
	assert_true(first.ok, "First Supporter should resolve: %s" % first.reason)
	assert_true(mgr.supporter_played_this_turn[0],
		"supporter_played_this_turn should flip on apply.")

	## Second Supporter same turn — reject via the manager's gate.
	var birch_b: TrainerCardData = _lib.get_card("RS_89_professor_birch") as TrainerCardData
	mgr.game_position.put_in_hand(0, birch_b)
	var second := ActionPlaySupporter.new(0, birch_b).validate(mgr)
	assert_false(second.ok, "Second Supporter same turn must be rejected.")


func test_rejects_when_card_not_in_hand() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	var birch: TrainerCardData = _lib.get_card("RS_89_professor_birch") as TrainerCardData
	## Note: not put into hand.
	var r := ActionPlaySupporter.new(0, birch).validate(mgr)
	assert_false(r.ok, "Supporter must be in hand to play.")
