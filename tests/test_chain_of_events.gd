extends GutTest
## GUT tests for Wave 7 — Plusle / Minun "Chain of Events".
##
## After a regular attack, if there is a Pokémon in the attacker's OTHER
## active slot that carries Chain of Events, that Pokémon uses its own
## attack[0] (Cheer On) as a sub-attack. Once per turn even with multiple
## chain bodies.

var _lib: CardLibrary
var _attack_handlers: Node = null
var _ability_handlers_node: Node = null


func before_all() -> void:
	_lib = CardLibrary.load_from_folder("res://data/cards")
	_attack_handlers = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_attack_handlers)
	_ability_handlers_node = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers_node)


func after_all() -> void:
	if _attack_handlers != null:
		_attack_handlers.queue_free()
	if _ability_handlers_node != null:
		_ability_handlers_node.queue_free()


func _make_builder() -> TestBoardBuilder:
	var mgr: ManagerSystem = load("res://autoload/manager_system.gd").new()
	add_child_autoqfree(mgr)
	return TestBoardBuilder.new(mgr, _lib)


## --- Chain fires after partner attack -------------------------------------

func test_chain_of_events_fires_cheer_on_after_partner_attack() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Active1 = Bagon (attacker) with damage to verify the chain heals it.
	## Active2 = Plusle (carrier with Chain of Events) holding 1 energy to
	## pay Cheer On's Colorless cost.
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"], "hp": 20})
	b.place_active2(0, "DR_8_plusle",
		{"energy": ["RS_104_grass_energy"]})
	b.place_active(1, "DR_49_bagon")
	b.set_prizes(0); b.set_prizes(1)

	var pre_hp: int = attacker.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_true(r.ok, "Bagon's attack should succeed: %s" % r.reason)
	## Bagon takes no self-damage, so any HP gain comes from Cheer On.
	## heal_team scope=all + counters=1 → +10 HP to every P0 Pokémon.
	assert_eq(attacker.current_hp, pre_hp + 10,
		"Plusle's Chain of Events should have triggered Cheer On (+10 HP).")
	assert_true(mgr.chain_of_events_used_this_turn[0],
		"Once-per-turn chain flag should be set after firing.")


## --- Chain blocked: no carrier in other active slot -----------------------

func test_chain_of_events_does_not_fire_without_carrier() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Just Bagon — no Plusle/Minun anywhere.
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"], "hp": 20})
	b.place_active(1, "DR_49_bagon")
	b.set_prizes(0); b.set_prizes(1)

	var pre_hp: int = attacker.current_hp
	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(attacker.current_hp, pre_hp,
		"No carrier → no Cheer On heal.")
	assert_false(mgr.chain_of_events_used_this_turn[0])


## --- Chain blocked: carrier can't pay Cheer On's energy cost --------------

func test_chain_of_events_blocked_when_carrier_has_no_energy() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"], "hp": 20})
	## Plusle without energy can't pay Cheer On's 1 Colorless cost.
	b.place_active2(0, "DR_8_plusle")
	b.place_active(1, "DR_49_bagon")
	b.set_prizes(0); b.set_prizes(1)

	var pre_hp: int = attacker.current_hp
	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(attacker.current_hp, pre_hp,
		"Cheer On should not fire when the carrier can't pay its cost.")
	assert_false(mgr.chain_of_events_used_this_turn[0])


## --- Chain blocked: carrier is condition-locked --------------------------

func test_chain_of_events_blocked_when_carrier_paralyzed() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	var attacker := b.place_active(0, "DR_49_bagon",
		{"energy": ["RS_104_grass_energy"], "hp": 20})
	b.place_active2(0, "DR_8_plusle",
		{"energy": ["RS_104_grass_energy"],
		 "conditions": [PokemonInstance.SpecialCondition.PARALYZED]})
	b.place_active(1, "DR_49_bagon")
	b.set_prizes(0); b.set_prizes(1)

	var pre_hp: int = attacker.current_hp
	await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 0, "p1_active1")
	)
	assert_eq(attacker.current_hp, pre_hp,
		"Paralyzed carrier should not chain.")
	assert_false(mgr.chain_of_events_used_this_turn[0])


## --- Chain does not re-trigger itself (once per turn) --------------------
##
## Plusle in active1 (carrier), Minun in active2 (also carrier). When the
## attack-from-active2 case runs, only one chain should fire — the other
## carrier's body sees the per-turn flag and stays quiet. We verify this by
## checking the heal happened exactly once (not twice).

func test_chain_of_events_fires_at_most_once_per_turn() -> void:
	var b   := _make_builder()
	var mgr: ManagerSystem = b._manager
	b.set_turn(0)
	## Plusle attacks (uses its own attack[1] = Extra Circuit at 20 damage,
	## simpler for tracking). Minun is in active2 with energy + chain body.
	## Extra Circuit costs 1 Lightning + 1 Colorless — attach two Lightning.
	var attacker := b.place_active(0, "DR_8_plusle",
		{"energy": ["RS_109_lightning_energy", "RS_109_lightning_energy"],
		 "hp": 20})
	## Force Plusle's attack[1] to be a vanilla 20-damage hit on the opponent
	## active (Extra Circuit picks a target via prompt; skip by patching).
	attacker.card.attacks[1].effect_key = ""
	attacker.card.attacks[1].base_damage = 20
	## Minun is the chain carrier with 1 energy to pay Cheer On.
	var minun := b.place_active2(0, "DR_7_minun",
		{"energy": ["RS_104_grass_energy"], "hp": 30})
	b.place_active(1, "DR_49_bagon")
	b.set_prizes(0); b.set_prizes(1)

	var pre_attacker_hp: int = attacker.current_hp
	var pre_minun_hp: int = minun.current_hp
	var r: ActionResult = await mgr.request_action_async(
		ActionAttack.new(0, "p0_active1", 1, "p1_active1")
	)
	assert_true(r.ok, "Plusle's attack should resolve: %s" % r.reason)
	## Cheer On runs once: +10 HP per Pokémon.  If it ran twice we'd see +20.
	assert_eq(attacker.current_hp - pre_attacker_hp, 10,
		"Plusle should be healed exactly once even with two chain bodies.")
	assert_eq(minun.current_hp - pre_minun_hp, 10,
		"Minun should be healed exactly once even with two chain bodies.")
	assert_true(mgr.chain_of_events_used_this_turn[0])
