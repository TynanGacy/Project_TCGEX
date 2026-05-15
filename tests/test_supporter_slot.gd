extends GutTest
## Lifecycle tests for the shared Supporter slot.
##
## A Supporter card stays in the slot from when it is played until the
## end-of-turn cleanup, at which point it is discarded to its owner's pile.
## These tests verify the state, signal, and discard behaviour without
## requiring real Supporter handlers — they use a synthesised TrainerCardData.

const _TRAINER_SCRIPT := preload("res://scripts/cards/trainer_card_data.gd")
const _PLAY_SUPPORTER_SCRIPT := preload("res://scripts/actions/action_play_supporter.gd")


func _make_supporter(slug: String) -> TrainerCardData:
	var card: TrainerCardData = _TRAINER_SCRIPT.new()
	card.card_id      = "TEST_%s" % slug
	card.display_name = slug.capitalize()
	card.card_type    = CardData.CardType.TRAINER
	card.trainer_kind = TrainerCardData.TrainerKind.SUPPORTER
	card.effect_key   = ""     # no real handler — execution is a no-op
	card.effect_params = {}
	return card


func _make_manager() -> ManagerSystem:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	# Stand-in GamePosition (RefCounted — owned by mgr).
	mgr.game_position = GamePosition.new()
	# Position MAIN phase, player 0 active.
	mgr.current_phase  = 1    # Phase.MAIN
	mgr.current_player = 0
	mgr.turn_number    = 3
	mgr.first_player   = 0
	return mgr


## Baseline: an unused slot starts empty.
func test_supporter_slot_starts_empty() -> void:
	var mgr := _make_manager()
	assert_null(mgr.active_supporter, "no supporter at start")
	assert_eq(mgr.active_supporter_owner, -1, "no owner")


## Playing a supporter places it in the slot (not the discard).
func test_play_supporter_puts_card_in_slot() -> void:
	var mgr := _make_manager()
	var card := _make_supporter("birch")
	mgr.game_position.put_in_hand(0, card)
	var emitted: Array = []
	mgr.supporter_changed.connect(func(c: TrainerCardData, owner: int) -> void:
		emitted.append([c, owner])
	)
	var action: ActionPlaySupporter = _PLAY_SUPPORTER_SCRIPT.new(0, card)
	# Skip Manager-level validation pathways; call apply() directly. Stub the
	# trainer_resolver to null so apply() doesn't try to dispatch.
	mgr.trainer_resolver = null
	action.apply(mgr)
	assert_eq(mgr.active_supporter, card, "card now in slot")
	assert_eq(mgr.active_supporter_owner, 0, "owner is player 0")
	# Card left the hand…
	assert_false((mgr.game_position.hands[0] as Array).has(card),
		"card removed from hand")
	# …but is NOT in the discard yet.
	assert_false((mgr.game_position.discards[0] as Array).has(card),
		"card not yet discarded")
	# Signal fired with correct payload.
	assert_eq(emitted.size(), 1, "supporter_changed emitted once")
	assert_eq(emitted[0][0], card)
	assert_eq(emitted[0][1], 0)


## End-of-turn cleanup discards the supporter to its owner's pile and clears
## both slot fields.
func test_end_of_turn_discards_supporter() -> void:
	var mgr := _make_manager()
	var card := _make_supporter("oak")
	mgr.active_supporter = card
	mgr.active_supporter_owner = 0
	var cleared_emit: Array = []
	mgr.supporter_changed.connect(func(c: TrainerCardData, owner: int) -> void:
		cleared_emit.append([c, owner])
	)
	mgr._discard_active_supporter()
	assert_null(mgr.active_supporter, "slot cleared")
	assert_eq(mgr.active_supporter_owner, -1, "owner reset")
	assert_true((mgr.game_position.discards[0] as Array).has(card),
		"card now in owner's discard")
	assert_eq(cleared_emit.size(), 1, "supporter_changed (clear) emitted")
	assert_null(cleared_emit[0][0], "null card")
	assert_eq(cleared_emit[0][1], -1, "owner -1")


## When a second Supporter would somehow land in the slot, the previous one
## is sent to its owner's discard (safety net — the normal turn rules prevent
## two Supporters per turn).
func test_playing_second_supporter_discards_first() -> void:
	var mgr := _make_manager()
	var first := _make_supporter("first")
	var second := _make_supporter("second")
	mgr.active_supporter = first
	mgr.active_supporter_owner = 0
	mgr.game_position.put_in_hand(1, second)
	mgr.trainer_resolver = null
	var action: ActionPlaySupporter = _PLAY_SUPPORTER_SCRIPT.new(1, second)
	action.apply(mgr)
	# First was sent to its owner's (p0) discard.
	assert_true((mgr.game_position.discards[0] as Array).has(first),
		"prior supporter discarded to its owner")
	# Second now occupies the slot under p1.
	assert_eq(mgr.active_supporter, second)
	assert_eq(mgr.active_supporter_owner, 1)


## reset_game_state clears the supporter slot state alongside the stadium.
func test_reset_game_state_clears_supporter() -> void:
	var mgr := _make_manager()
	mgr.active_supporter = _make_supporter("temp")
	mgr.active_supporter_owner = 0
	mgr.reset_game_state()
	assert_null(mgr.active_supporter, "supporter cleared")
	assert_eq(mgr.active_supporter_owner, -1, "owner reset")


## Discarded-supporter side: card goes to the OWNER's pile, not the current
## player's. Confirms owner_id is honoured.
func test_discard_routes_to_owner_pile() -> void:
	var mgr := _make_manager()
	var card := _make_supporter("for_p1")
	mgr.active_supporter = card
	mgr.active_supporter_owner = 1  # p1 owns it
	mgr._discard_active_supporter()
	assert_true((mgr.game_position.discards[1] as Array).has(card),
		"card lands in p1's discard")
	assert_false((mgr.game_position.discards[0] as Array).has(card),
		"NOT in p0's discard")
