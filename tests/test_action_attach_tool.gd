extends GutTest
## Tests for ActionAttachTool.  Verifies kind validation, the one-tool-per-
## Pokémon rule, hand presence, and that the tool ends up attached on apply.

var _lib: CardLibrary
var _ability_handlers: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_ability_handlers = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers)


func after_all() -> void:
	if _ability_handlers != null:
		_ability_handlers.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func test_attaches_tool_to_active() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var inst := b.place_active(0, "RS_52_electrike")
	b.set_prizes(0)
	b.set_prizes(1)
	var berry: TrainerCardData = _lib.get_card("RS_85_oran_berry") as TrainerCardData
	mgr.game_position.put_in_hand(0, berry)

	var r := await mgr.request_action_async(
		ActionAttachTool.new(0, berry, "p0_active1")
	)
	assert_true(r.ok, "Tool attach should succeed: %s" % r.reason)
	assert_true(inst.attached_tools.has(berry),
		"Berry should be in attached_tools on apply.")


func test_rejects_second_tool() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	var inst := b.place_active(0, "RS_52_electrike")
	## Pre-attach a tool directly so we hit the one-tool rule.
	var first: TrainerCardData = _lib.get_card("RS_84_lum_berry") as TrainerCardData
	inst.attach_tool(first)
	b.set_prizes(0)
	b.set_prizes(1)
	var second: TrainerCardData = _lib.get_card("RS_85_oran_berry") as TrainerCardData
	mgr.game_position.put_in_hand(0, second)

	var r := ActionAttachTool.new(0, second, "p0_active1").validate(mgr)
	assert_false(r.ok, "Cannot attach a second Tool to the same Pokémon.")


func test_rejects_non_tool_card() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	b.place_active(0, "RS_52_electrike")
	var potion: TrainerCardData = _lib.get_card("RS_91_potion") as TrainerCardData
	mgr.game_position.put_in_hand(0, potion)
	var r := ActionAttachTool.new(0, potion, "p0_active1").validate(mgr)
	assert_false(r.ok, "ActionAttachTool must reject non-Tool Trainer cards.")


func test_rejects_when_target_slot_empty() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0, 3)
	## No Pokémon placed.
	var berry: TrainerCardData = _lib.get_card("RS_85_oran_berry") as TrainerCardData
	mgr.game_position.put_in_hand(0, berry)
	var r := ActionAttachTool.new(0, berry, "p0_active1").validate(mgr)
	assert_false(r.ok, "Cannot attach Tool to an empty slot.")
