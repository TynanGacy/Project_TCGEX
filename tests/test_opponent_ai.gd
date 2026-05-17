extends GutTest
## Unit tests for OpponentAI.decide_action — the pure decision function.
##
## Scope: Phase A heuristic priorities only. Driver wiring (turn loop, prize
## selection, mid-attack query responses) is exercised by running the game
## in the editor against the DR Fire opponent deck — those code paths
## involve async signals and the dialog manager and are not unit-testable
## in isolation.

var _lib: CardLibrary
var _ai: OpponentAI
var _handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_handlers_node = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_handlers_node)


func after_all() -> void:
	if _handlers_node != null:
		_handlers_node.queue_free()
		_handlers_node = null


func before_each() -> void:
	_ai = OpponentAI.new()


func _fresh_manager() -> ManagerSystem:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return mgr


func _builder() -> TestBoardBuilder:
	return TestBoardBuilder.new(_fresh_manager(), _lib)


## ── 1. Empty active + basic in hand → play to active ─────────────────────────

func test_decides_to_play_basic_to_empty_active() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.give_hand(0, ["DR_98_charmander"])

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_not_null(action, "AI must place a basic when active is empty")
	assert_true(action is ActionPlayPokemon, "Expected ActionPlayPokemon")
	var ap := action as ActionPlayPokemon
	assert_eq(ap.target_slot, "p0_active1", "Active slot first")
	assert_true(ap.validate(mgr).ok, "Suggested action must validate")


## ── 2. Active exists, bench empty, basic in hand → play to bench ─────────────

func test_decides_to_fill_bench_when_empty() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_77_torchic")
	b.give_hand(0, ["DR_98_charmander"])

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_not_null(action, "AI must bench a basic when bench is empty")
	assert_true(action is ActionPlayPokemon, "Expected ActionPlayPokemon")
	assert_eq((action as ActionPlayPokemon).target_slot, "p0_bench1",
		"First empty bench slot")


## ── 3. Bench at MAX_BENCH_FILL, energy in hand, not yet attached → attach ────

func test_decides_to_attach_energy_after_bench_is_filled() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_98_charmander")
	for i in OpponentAI.MAX_BENCH_FILL:
		b.place("p0_bench%d" % (i + 1), "DR_72_slugma")
	b.give_hand(0, ["RS_108_fire_energy"])

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_not_null(action, "AI must attach energy with bench full")
	assert_true(action is ActionAttachEnergy, "Expected ActionAttachEnergy")
	var ae := action as ActionAttachEnergy
	assert_eq(ae.target_slot, "p0_active1",
		"Prefers attaching to the active so it can attack")
	assert_true(ae.validate(mgr).ok, "Suggested attach must validate")


## ── 4. Energy already attached this turn, attack legal → attack ─────────────

func test_decides_to_attack_when_attack_is_legal() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Numel Firebreathing: cost_fire 1, 10 base dmg. One fire energy = legal.
	b.place_active(0, "DR_69_numel", {"energy": ["RS_108_fire_energy"]})
	b.place_active(1, "DR_98_charmander")
	for i in OpponentAI.MAX_BENCH_FILL:
		b.place("p0_bench%d" % (i + 1), "DR_72_slugma")
	mgr.energy_attached_this_turn[0] = true

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_not_null(action, "Legal attack must be chosen")
	assert_true(action is ActionAttack, "Expected ActionAttack")
	var atk := action as ActionAttack
	assert_eq(atk.attacker_slot, "p0_active1")
	assert_eq(atk.target_slot,   "p1_active1")
	assert_true(atk.validate(mgr).ok, "Suggested attack must validate")


## ── 5. Picks highest-damage legal attack when multiple are payable ──────────

func test_attack_picks_highest_damage_legal_option() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Numel: Firebreathing (10, cost_fire 1) and Tackle (20, cost_colorless 2).
	## 2 fire energy makes both legal — AI must pick Tackle for higher damage.
	b.place_active(0, "DR_69_numel",
		{"energy": ["RS_108_fire_energy", "RS_108_fire_energy"]})
	b.place_active(1, "DR_98_charmander")
	for i in OpponentAI.MAX_BENCH_FILL:
		b.place("p0_bench%d" % (i + 1), "DR_72_slugma")
	mgr.energy_attached_this_turn[0] = true

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_true(action is ActionAttack, "Expected ActionAttack")
	var atk := action as ActionAttack
	var attacker: PokemonInstance = mgr.board_position.get_instance("p0_active1")
	var chosen_dmg: int = int(attacker.card.attacks[atk.attack_index].base_damage)
	assert_eq(chosen_dmg, 20,
		"AI must pick Tackle (20 dmg) over Firebreathing (10 dmg) when both are payable")


## ── 6. Nothing to do → returns null (driver will end turn) ──────────────────

func test_returns_null_when_no_legal_action() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	b.place_active(0, "DR_77_torchic")  ## No energy attached, no opp active.
	for i in OpponentAI.MAX_BENCH_FILL:
		b.place("p0_bench%d" % (i + 1), "DR_72_slugma")
	## Empty hand, energy attach already used, attack already used.
	mgr.energy_attached_this_turn[0] = true
	mgr.attack_used_this_turn[0]     = true

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_null(action, "AI must signal end-turn by returning null")


## ── 7. Not main phase → returns null (defensive guard) ──────────────────────

func test_returns_null_when_not_in_main_phase() -> void:
	var b := _builder()
	var mgr: ManagerSystem = b._manager
	mgr.current_phase = ManagerSystem.Phase.SETUP
	mgr.current_player = 0
	b.give_hand(0, ["DR_98_charmander"])

	var action: GameAction = _ai.decide_action(mgr, 0)
	assert_null(action, "AI must not act outside of main phase")


## ── 8. Null manager → returns null (defensive guard) ────────────────────────

func test_returns_null_when_manager_is_null() -> void:
	var action: GameAction = _ai.decide_action(null, 0)
	assert_null(action, "Null manager must not crash; returns null")
