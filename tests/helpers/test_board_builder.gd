class_name TestBoardBuilder
## Configures a ManagerSystem into a deterministic board state for GUT tests.
##
## The manager must already be in the scene tree before building:
##   var mgr = load("res://autoload/manager_system.gd").new()
##   add_child_autoqfree(mgr)
##   var b = TestBoardBuilder.new(mgr, lib)
##
## After setup, call mgr.request_action() directly to exercise game logic.
##
## Phase constants (ManagerSystem.Phase enum values):
##   SETUP = 0  |  MAIN = 1  |  ENDED = 2

var _manager   ## ManagerSystem node
var _lib: CardLibrary


func _init(manager, lib: CardLibrary) -> void:
	_manager = manager
	_lib     = lib


## Sets the board to [player_id]'s MAIN phase at turn [turn_num].
## Use turn_num >= 3 to avoid first-turn restrictions on draw/supporters.
func set_turn(player_id: int, turn_num: int = 3) -> void:
	_manager.current_player = player_id
	_manager.current_phase  = 1      ## Phase.MAIN
	_manager.turn_number    = turn_num
	_manager.first_player   = 0


## Places a Pokémon in [slot_id] (e.g. "p0_active1", "p1_bench2").
## opts keys:
##   "hp"         : int   — override current_hp (max_hp stays at card value)
##   "energy"     : Array[String]  — card_ids of energy to attach
##   "conditions" : Array[PokemonInstance.SpecialCondition]
## Returns the created PokemonInstance (useful for direct state assertions).
func place(slot_id: String, card_id: String, opts: Dictionary = {}) -> PokemonInstance:
	var owner := _manager.board_position.player_of(slot_id)
	var card  := _lib.get_card(card_id) as PokemonCardData
	assert(card != null, "TestBoardBuilder.place: unknown card_id '%s'" % card_id)

	var inst := PokemonInstance.create(card, owner)

	if opts.has("hp"):
		inst.current_hp = int(opts["hp"])

	if opts.has("energy"):
		for eid: String in (opts["energy"] as Array):
			var ecard := _lib.get_card(eid)
			assert(ecard != null, "TestBoardBuilder: unknown energy card '%s'" % eid)
			inst.attached_energy.append(ecard)

	if opts.has("conditions"):
		for c in (opts["conditions"] as Array):
			inst.special_conditions.append(c as PokemonInstance.SpecialCondition)

	_manager.board_position.place(slot_id, inst)
	return inst


## Shorthand: places in p[pid]_active1.
func place_active(pid: int, card_id: String, opts: Dictionary = {}) -> PokemonInstance:
	return place("p%d_active1" % pid, card_id, opts)


## Shorthand: places in the first empty bench slot for [pid].
func place_bench(pid: int, card_id: String, opts: Dictionary = {}) -> PokemonInstance:
	var slot := _manager.board_position.first_empty_bench(pid)
	assert(slot != "", "TestBoardBuilder.place_bench: bench is full for p%d" % pid)
	return place(slot, card_id, opts)


## Fills [count] prize slots for [pid] with a dummy card so prize-taking logic works.
func set_prizes(pid: int, count: int = 6) -> void:
	var dummy := _lib.get_card("RS_104_grass_energy")
	assert(dummy != null, "TestBoardBuilder.set_prizes: grass energy card not found")
	for i in range(mini(count, 6)):
		_manager.game_position.prizes[pid][i] = dummy


## Puts [card_ids] into [pid]'s hand.
func give_hand(pid: int, card_ids: Array) -> void:
	for cid: String in card_ids:
		var card := _lib.get_card(str(cid))
		assert(card != null, "TestBoardBuilder.give_hand: unknown card '%s'" % cid)
		_manager.game_position.put_in_hand(pid, card)


## Returns the PokemonInstance currently in [slot_id], or null.
func inst(slot_id: String) -> PokemonInstance:
	return _manager.board_position.get_instance(slot_id)
