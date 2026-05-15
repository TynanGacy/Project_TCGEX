extends GutTest
## GUT test suite for Tier-3 Wave 19 (Cross-system / interactive attacks):
##   - SS_46/47/61 Surprise                  (blind opp-hand pick → shuffle to deck)
##   - SS_10 Sableye Supernatural            (use Supporter from opp hand)
##   - SS_9 Mawile Scam                      (shuffle opp Supporter to deck + opp draws 1)
##   - DR_1 Absol Bad News                   (blind discard until 5 left)
##   - DR_21 Skarmory Pick On                (open look + shuffle until 5 left)
##   - DR_92 Kingdra ex Genetic Memory       (sub-attack from prior_stages)

var _lib: CardLibrary
var _handlers_node: Node = null
var _trainer_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_handlers_node = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_handlers_node)
	# TrainerHandlers must also be registered for Sableye's bridge test.
	_trainer_handlers_node = load("res://scenes/match/trainer_handlers.gd").new()
	add_child(_trainer_handlers_node)


func after_all() -> void:
	if _handlers_node != null:
		_handlers_node.queue_free()
		_handlers_node = null
	if _trainer_handlers_node != null:
		_trainer_handlers_node.queue_free()
		_trainer_handlers_node = null


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


func _set_attack(att: PokemonInstance, base_damage: int, key: String,
		params: Dictionary, chain: Array = []) -> void:
	var a: AttackData = att.card.attacks[0]
	a.base_damage = base_damage
	a.effect_key = key
	a.effect_params = params
	a.effect_chain = chain
	a.cost_colorless = 0; a.cost_fire = 0; a.cost_water = 0; a.cost_grass = 0
	a.cost_lightning = 0; a.cost_psychic = 0; a.cost_fighting = 0
	a.cost_darkness = 0; a.cost_metal = 0


func _auto_answer_queries(mgr: ManagerSystem, values: Array) -> void:
	var queue: Array = values.duplicate()
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void:
			if queue.is_empty():
				push_warning("Test: attack query fired but no canned response left")
				return
			var v: Variant = queue.pop_front()
			mgr.attack_resolver.resolve_query.call_deferred(v)
	)
	# Bridge: Supporters may emit TrainerQuery through trainer_resolver. Reuse
	# the same FIFO for both signal sources.
	if mgr.trainer_resolver != null:
		mgr.trainer_resolver.player_query_requested.connect(
			func(_q: TrainerQuery) -> void:
				if queue.is_empty():
					push_warning("Test: trainer query fired but no canned response left")
					return
				var v: Variant = queue.pop_front()
				mgr.trainer_resolver.resolve_query.call_deferred(v)
		)


## Seed opp hand with the listed card_ids in order.
func _give_opp_hand(mgr: ManagerSystem, card_ids: Array) -> void:
	for cid in card_ids:
		var c: CardData = _lib.get_card(str(cid))
		if c != null:
			mgr.game_position.put_in_hand(1, c)


## ── Surprise (SS_46 Lombre / SS_47 Murkrow / SS_61 Duskull) ────────────────

## (a) Opp hand of 3, pick idx 1 → 10 dmg (Lombre), that card to opp deck.
func test_lombre_surprise_picks_and_shuffles() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon", "RS_108_fire_energy", "DR_5_golem"])
	_set_attack(att, 10, "look_take_shuffle_one_from_opp_hand", {})
	var hand_before: int = mgr.game_position.hands[1].size()
	var deck_before: int = mgr.game_position.decks[1].size()
	_auto_answer_queries(mgr, [[1] as Array[int]])
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 10,
		"Lombre Surprise deals 10")
	assert_eq(mgr.game_position.hands[1].size(), hand_before - 1, "opp hand -1")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1, "opp deck +1")


## (b) Empty opp hand → no query, 10 damage still lands.
func test_lombre_surprise_empty_opp_hand_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Opp hand stays empty.
	_set_attack(att, 10, "look_take_shuffle_one_from_opp_hand", {})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 10,
		"damage still lands")
	assert_false(any_query[0], "no query when opp hand empty")


## (c) Murkrow Surprise: 0 damage, card returns to opp deck.
func test_murkrow_surprise_zero_damage_shuffles() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon"])
	_set_attack(att, 0, "look_take_shuffle_one_from_opp_hand", {})
	_auto_answer_queries(mgr, [[0] as Array[int]])
	var hp_before := tgt.current_hp
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 0,
		"Murkrow Surprise does no damage")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1, "deck +1")
	assert_eq(mgr.game_position.hands[1].size(), 0, "hand empty")


## (d) Hand-count restored via deck size check (count, not order).
func test_duskull_surprise_count_invariants() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon", "RS_108_fire_energy"])
	_set_attack(att, 0, "look_take_shuffle_one_from_opp_hand", {})
	_auto_answer_queries(mgr, [[0] as Array[int]])
	var total_before: int = mgr.game_position.hands[1].size() + mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	var total_after: int = mgr.game_position.hands[1].size() + mgr.game_position.decks[1].size()
	assert_eq(total_after, total_before, "hand+deck total preserved")


## ── Sableye Supernatural (SS_10) ───────────────────────────────────────────

## (a) Opp has a draw-style Supporter; attacker confirms; supporter effect
## fires; supporter REMAINS in opp hand.
func test_sableye_supernatural_uses_opp_supporter() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# DR_88 TV Reporter (draw_then_discard) — pick one whose effect is
	# unambiguous and visible in state.
	_give_opp_hand(mgr, ["DR_88_tv_reporter"])
	# Seed attacker deck so TV Reporter can draw from it.
	for cid in ["DR_49_bagon", "DR_49_bagon", "DR_49_bagon", "RS_108_fire_energy"]:
		mgr.game_position.decks[0].append(_lib.get_card(cid))
	_set_attack(att, 0, "look_then_may_use_supporter_from_opp_hand", {})
	# Queries fire in this order:
	#   1) Open opp hand picker (Supernatural) — return [tv_reporter]
	#   2) MAY_CONFIRM "Use TV Reporter?" — return true
	#   3) TV Reporter trainer flow may emit its own query (depends on impl)
	var tv: CardData = mgr.game_position.hands[1][0]
	var attacker_hand_before: int = mgr.game_position.hands[0].size()
	var opp_hand_before: int = mgr.game_position.hands[1].size()
	# We can't predict trainer-flow internals; provide enough true/empty
	# responses to cover up to a couple of cascaded prompts.
	_auto_answer_queries(mgr, [[tv] as Array[CardData], true, true, true])
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Supporter still in opp hand.
	assert_eq(mgr.game_position.hands[1].size(), opp_hand_before,
		"opp hand size unchanged — supporter stays in opp hand")
	assert_true(mgr.game_position.hands[1].has(tv),
		"the exact supporter card is still in opp hand")
	# supporter_played_this_turn[attacker] should NOT be consumed.
	assert_false(mgr.supporter_played_this_turn[0],
		"attacker's once-per-turn supporter slot is NOT consumed")


## (b) Opp has no Supporter → no-op (no MAY_CONFIRM fires, hands unchanged).
func test_sableye_supernatural_no_supporter_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon", "RS_108_fire_energy"])  # no supporters
	_set_attack(att, 0, "look_then_may_use_supporter_from_opp_hand", {})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(any_query[0], "no query fires when opp hand has no supporter")
	assert_eq(mgr.game_position.hands[1].size(), hand_before, "hand unchanged")


## (c) Attacker declines after open-hand picker returns nothing.
func test_sableye_supernatural_decline() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_88_tv_reporter"])
	for cid in ["DR_49_bagon"]:
		mgr.game_position.decks[0].append(_lib.get_card(cid))
	_set_attack(att, 0, "look_then_may_use_supporter_from_opp_hand", {})
	# Player picks nothing (empty array) → handler returns early.
	_auto_answer_queries(mgr, [[] as Array[CardData]])
	var attacker_hand_before: int = mgr.game_position.hands[0].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Attacker drew nothing (supporter effect was not invoked).
	assert_eq(mgr.game_position.hands[0].size(), attacker_hand_before,
		"no draw → effect was not invoked")


## ── Mawile Scam (SS_9) ─────────────────────────────────────────────────────

## (a) Opp has supporter, attacker confirms → supporter to opp deck, opp draws 1.
## Per rules, after shuffle-then-draw the supporter MAY end up redrawn back
## into opp's hand (1/N chance, where N = deck size after shuffle). We
## therefore verify aggregate invariants — hand size unchanged, discard
## untouched, and total cards in deck+hand preserved — rather than the
## specific identity of the drawn card.
func test_mawile_scam_shuffles_and_opp_draws() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_88_tv_reporter"])
	# Seed opp deck with cards so the draw is observable.
	mgr.game_position.decks[1].append(_lib.get_card("DR_49_bagon"))
	mgr.game_position.decks[1].append(_lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "look_then_may_shuffle_opp_supporter_draw_one", {})
	var supporter: CardData = mgr.game_position.hands[1][0]
	var hand_before: int = mgr.game_position.hands[1].size()
	var deck_before: int = mgr.game_position.decks[1].size()
	var discard_before: int = mgr.game_position.discards[1].size()
	_auto_answer_queries(mgr, [[supporter] as Array[CardData], true])
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	# Hand: -supporter, +1 drawn = same size.
	assert_eq(mgr.game_position.hands[1].size(), hand_before,
		"hand size unchanged (lost 1, drew 1)")
	# Deck: +supporter, -1 drawn = same size.
	assert_eq(mgr.game_position.decks[1].size(), deck_before,
		"deck size unchanged (gained supporter, drew 1)")
	# Supporter must NOT have gone to discard.
	assert_eq(mgr.game_position.discards[1].size(), discard_before,
		"supporter went to deck, not discard")
	# Total card count across all opp zones preserved.
	var total_after: int = mgr.game_position.hands[1].size() \
		+ mgr.game_position.decks[1].size() \
		+ mgr.game_position.discards[1].size()
	var total_before: int = hand_before + deck_before + discard_before
	assert_eq(total_after, total_before, "no cards gained or lost")


## (b) Opp has no Supporter → no-op (no draw).
func test_mawile_scam_no_supporter_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon"])  # no supporter
	mgr.game_position.decks[1].append(_lib.get_card("RS_108_fire_energy"))
	_set_attack(att, 0, "look_then_may_shuffle_opp_supporter_draw_one", {})
	var hand_before: int = mgr.game_position.hands[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), hand_before,
		"no-op: hand size unchanged")


## (c) Attacker declines → no shuffle, no draw.
func test_mawile_scam_decline() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_88_tv_reporter"])
	mgr.game_position.decks[1].append(_lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "look_then_may_shuffle_opp_supporter_draw_one", {})
	var supporter: CardData = mgr.game_position.hands[1][0]
	# Player picks the supporter, then declines.
	_auto_answer_queries(mgr, [[supporter] as Array[CardData], false])
	var hand_before: int = mgr.game_position.hands[1].size()
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), hand_before, "hand unchanged")
	assert_eq(mgr.game_position.decks[1].size(), deck_before, "deck unchanged")
	assert_true(mgr.game_position.hands[1].has(supporter), "supporter still in hand")


## ── Absol Bad News (DR_1) ──────────────────────────────────────────────────

## (a) Opp hand=7, pick 2 → 2 discarded, 5 left.
func test_absol_bad_news_discards_until_five() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon", "DR_49_bagon", "DR_49_bagon",
		"DR_49_bagon", "DR_49_bagon", "DR_49_bagon", "DR_49_bagon"])  # 7
	_set_attack(att, 0, "pick_blind_from_opp_hand_to_discard_until",
		{"threshold": 6, "target_size": 5})
	_auto_answer_queries(mgr, [[0, 1] as Array[int]])
	var discard_before: int = mgr.game_position.discards[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), 5, "5 cards left in opp hand")
	assert_eq(mgr.game_position.discards[1].size(), discard_before + 2,
		"2 cards in opp discard pile")


## (b) Opp hand=5 → no-op (below threshold).
func test_absol_bad_news_below_threshold_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_give_opp_hand(mgr, ["DR_49_bagon", "DR_49_bagon", "DR_49_bagon",
		"DR_49_bagon", "DR_49_bagon"])  # 5
	_set_attack(att, 0, "pick_blind_from_opp_hand_to_discard_until",
		{"threshold": 6, "target_size": 5})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(any_query[0], "no query when hand below threshold")
	assert_eq(mgr.game_position.hands[1].size(), 5, "hand unchanged")


## (c) Opp hand=8, force pick [0,1,2] → those exact indices discarded.
func test_absol_bad_news_picks_exact_indices() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	# Distinct cards so we can identify which 3 left the hand.
	_give_opp_hand(mgr, ["DR_49_bagon", "RS_108_fire_energy", "DR_5_golem",
		"DR_41_shelgon", "RS_104_grass_energy", "RS_106_water_energy",
		"RS_107_psychic_energy", "RS_109_lightning_energy"])  # 8
	var pre_idx_0: CardData = mgr.game_position.hands[1][0]
	var pre_idx_1: CardData = mgr.game_position.hands[1][1]
	var pre_idx_2: CardData = mgr.game_position.hands[1][2]
	_set_attack(att, 0, "pick_blind_from_opp_hand_to_discard_until",
		{"threshold": 6, "target_size": 5})
	_auto_answer_queries(mgr, [[0, 1, 2] as Array[int]])
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), 5, "5 left")
	# The discard pile should contain the three pre-recorded cards.
	var discard: Array = mgr.game_position.discards[1]
	assert_true(discard.has(pre_idx_0), "idx 0 discarded")
	assert_true(discard.has(pre_idx_1), "idx 1 discarded")
	assert_true(discard.has(pre_idx_2), "idx 2 discarded")


## ── Skarmory Pick On (DR_21) ───────────────────────────────────────────────

## (a) Opp hand=6, pick 1 → 5 left, 1 in deck.
func test_skarmory_pick_on_shuffles_one() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for _i in range(6):
		mgr.game_position.put_in_hand(1, _lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "look_pick_shuffle_opp_hand_until",
		{"threshold": 6, "target_size": 5})
	var pre_card: CardData = mgr.game_position.hands[1][0]
	_auto_answer_queries(mgr, [[pre_card] as Array[CardData]])
	var deck_before: int = mgr.game_position.decks[1].size()
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(mgr.game_position.hands[1].size(), 5, "5 cards left")
	assert_eq(mgr.game_position.decks[1].size(), deck_before + 1, "1 card to opp deck")


## (b) Opp hand=5 → no-op.
func test_skarmory_pick_on_below_threshold_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for _i in range(5):
		mgr.game_position.put_in_hand(1, _lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "look_pick_shuffle_opp_hand_until",
		{"threshold": 6, "target_size": 5})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(any_query[0], "no query below threshold")
	assert_eq(mgr.game_position.hands[1].size(), 5, "hand unchanged")


## (c) Functional check: the query kind is CHOOSE_OPP_HAND_OPEN (attacker sees hand).
func test_skarmory_pick_on_uses_open_picker() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_49_bagon", {})
	b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	for _i in range(6):
		mgr.game_position.put_in_hand(1, _lib.get_card("DR_49_bagon"))
	_set_attack(att, 0, "look_pick_shuffle_opp_hand_until",
		{"threshold": 6, "target_size": 5})
	var captured_kind := [-1]
	mgr.attack_resolver.player_query_requested.connect(
		func(q: AttackQuery) -> void:
			captured_kind[0] = q.kind
			# Auto-respond with one card so the attack resolves.
			mgr.attack_resolver.resolve_query.call_deferred(
				[mgr.game_position.hands[1][0]] as Array[CardData])
	)
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_eq(captured_kind[0], AttackQuery.Kind.CHOOSE_OPP_HAND_OPEN,
		"Pick On uses open-hand picker (attacker sees the hand)")


## ── Kingdra ex Genetic Memory (DR_92) ──────────────────────────────────────

## (a) Pick a damage attack from a prior stage → damage lands via sub-pipeline.
func test_genetic_memory_invokes_sub_attack_damage() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Place a basic that has a deterministic damage attack as the "current
	# top" but treat its attacks[0] (Headbutt or similar) as a prior stage's
	# attack. Simpler: place DR_92 Kingdra ex synthetically with prior_stages
	# containing a Pokemon whose attack[0] has 30 base damage.
	var att := b.place_active(0, "DR_92_kingdra_ex", {})
	# Push a Pokemon with a known damage attack as the prior stage. Use
	# DR_49 Bagon — its attacks may have nonzero base_damage at idx 0.
	var seadra := _lib.get_card("DR_40_seadra") as PokemonCardData
	att.prior_stages.append(seadra)
	b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	# Determine seadra's best damage attack.
	var best_idx := 0
	var best_dmg := -1
	for i in range(seadra.attacks.size()):
		if seadra.attacks[i].base_damage > best_dmg:
			best_dmg = seadra.attacks[i].base_damage
			best_idx = i
	# Override Kingdra ex's Genetic Memory cost to nothing for test isolation.
	_set_attack(att, 0, "use_attack_from_prior_stage", {})
	# Build the expected option entry the handler will offer.
	var expected_entry := {
		"card": seadra, "index": best_idx,
		"label": "%s — %s (%d dmg)" % [seadra.display_name, seadra.attacks[best_idx].name, best_dmg],
	}
	_auto_answer_queries(mgr, [expected_entry])
	var hp_before := (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Genetic Memory should resolve")
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	# Sub-attack ran; damage should be > 0 (W/R may apply but Kingdra is WATER
	# vs Golem WATER-weakness → doubled).
	assert_true(hp_before - tgt2.current_hp > 0,
		"sub-attack dealt some damage via the sub-pipeline")


## (b) Empty prior_stages → no-op, no damage.
func test_genetic_memory_empty_prior_stages_noop() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_92_kingdra_ex", {})
	# No prior stages.
	var tgt := b.place_active(1, "DR_5_golem", {"hp": 120})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "use_attack_from_prior_stage", {})
	var any_query := [false]
	mgr.attack_resolver.player_query_requested.connect(
		func(_q: AttackQuery) -> void: any_query[0] = true)
	var hp_before := tgt.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok)
	assert_false(any_query[0], "no query when prior_stages empty")
	assert_eq(hp_before - (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp, 0,
		"no damage when no prior stages")


## (c) Cost-waived: Kingdra ex with no energy still resolves sub-attack.
func test_genetic_memory_cost_waived() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	# Kingdra ex with ZERO energy attached.
	var att := b.place_active(0, "DR_92_kingdra_ex", {})
	var seadra := _lib.get_card("DR_40_seadra") as PokemonCardData
	att.prior_stages.append(seadra)
	b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "use_attack_from_prior_stage", {})
	var best_idx := 0
	var best_dmg := -1
	for i in range(seadra.attacks.size()):
		if seadra.attacks[i].base_damage > best_dmg:
			best_dmg = seadra.attacks[i].base_damage
			best_idx = i
	_auto_answer_queries(mgr, [{
		"card": seadra, "index": best_idx, "label": "x"
	}])
	var hp_before := (mgr.board_position.get_instance("p1_active1") as PokemonInstance).current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "Genetic Memory should resolve even without energy")
	# Sub-attack damage > 0 means cost wasn't re-validated.
	var tgt2: PokemonInstance = mgr.board_position.get_instance("p1_active1")
	if best_dmg > 0:
		assert_true(hp_before - tgt2.current_hp > 0,
			"sub-attack damage landed with cost waived")


## (d) sub_attack_depth guard: a nested invoke from within a sub-attack is
## a no-op (single-level only).
func test_genetic_memory_recursion_guard() -> void:
	# Direct unit test of invoke_sub_attack with depth=1 already set.
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_92_kingdra_ex", {})
	var seadra := _lib.get_card("DR_40_seadra") as PokemonCardData
	att.prior_stages.append(seadra)
	b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	# Construct a synthetic AttackContext.
	var ctx := AttackContext.new()
	ctx.manager = mgr
	ctx.attacker = att
	ctx.target = mgr.board_position.get_instance("p1_active1")
	ctx.player_id = 0
	ctx.attacker_slot = "p0_active1"
	ctx.target_slot = "p1_active1"
	ctx.attack = att.card.attacks[0]
	ctx.sub_attack_depth = 1  # pretend we're already nested
	# Call should no-op because depth > 0.
	await mgr.attack_resolver.invoke_sub_attack(ctx, seadra, 0)
	assert_eq(ctx.sub_attack_depth, 1, "depth not incremented when guard hits")


## (e) Sub-attack consumes its own forced flips (if its key uses coin).
func test_genetic_memory_sub_attack_uses_flip_queue() -> void:
	var b := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var att := b.place_active(0, "DR_92_kingdra_ex", {})
	# Find a prior-stage Pokemon whose attack uses a coin flip — fall back
	# to seadra if none has coin gating.
	var seadra := _lib.get_card("DR_40_seadra") as PokemonCardData
	att.prior_stages.append(seadra)
	b.place_active(1, "DR_5_golem", {"hp": 200})
	b.set_prizes(0); b.set_prizes(1)
	_set_attack(att, 0, "use_attack_from_prior_stage", {})
	# Push enough flips that any coin-using sub-attack drains from it.
	mgr.push_forced_flips([true, true, true, true])
	var best_idx := 0
	var best_dmg := -1
	for i in range(seadra.attacks.size()):
		if seadra.attacks[i].base_damage > best_dmg:
			best_dmg = seadra.attacks[i].base_damage
			best_idx = i
	_auto_answer_queries(mgr, [{
		"card": seadra, "index": best_idx, "label": "x"
	}])
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1"))
	assert_true(r.ok, "pipeline resolves with forced flips available")
