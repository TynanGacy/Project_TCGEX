extends GutTest
## Tests for ActionPlayItem.  Verifies kind validation (rejects non-Items,
## rejects fossils), hand presence, and that the card is moved to the discard
## on apply.

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


func test_rejects_supporter_card() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	var birch: TrainerCardData = _lib.get_card("RS_89_professor_birch") as TrainerCardData
	mgr.game_position.put_in_hand(0, birch)
	var r := ActionPlayItem.new(0, birch).validate(mgr)
	assert_false(r.ok, "ActionPlayItem must reject Supporters.")


func test_rejects_fossil_via_plays_as_pokemon_flag() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	var fossil: TrainerCardData = _lib.get_card("SS_90_claw_fossil") as TrainerCardData
	mgr.game_position.put_in_hand(0, fossil)
	var r := ActionPlayItem.new(0, fossil).validate(mgr)
	assert_false(r.ok, "Fossils route through ActionPlayFossil, not ActionPlayItem.")


func test_rejects_when_card_not_in_hand() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	## Energy Switch is a simple Item we won't actually resolve here.
	var item: TrainerCardData = _lib.get_card("RS_82_energy_switch") as TrainerCardData
	## Note: not put into hand.
	var r := ActionPlayItem.new(0, item).validate(mgr)
	assert_false(r.ok, "Item must be in hand to play.")


func test_apply_moves_card_to_discard() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	## Place a damaged Pokémon so heal_choice has at least one valid target
	## (this satisfies the VALIDATE phase; we won't await the player query).
	b.place_active(0, "RS_52_electrike", {"hp": 30})
	b.set_prizes(0)
	b.set_prizes(1)
	var potion: TrainerCardData = _lib.get_card("RS_91_potion") as TrainerCardData
	mgr.game_position.put_in_hand(0, potion)

	var action := ActionPlayItem.new(0, potion)
	var r := action.validate(mgr)
	assert_true(r.ok, "Potion validate should pass: %s" % r.reason)
	## Apply directly (bypassing resolver query plumbing). We're only
	## asserting the action's own state mutation contract.
	action.apply(mgr)
	assert_false((mgr.game_position.hands[0] as Array).has(potion),
		"Potion should be removed from hand on apply.")
	assert_true((mgr.game_position.discards[0] as Array).has(potion),
		"Potion should be in the discard pile on apply.")
