extends Node
class_name ManagerSystem
## Central Manager.  Mediates every Game_Action that mutates the game state
## and owns the turn / phase flow.
##
## Contract (vision):
##   - Game_Actions are declarative; they do NOT mutate state themselves.
##   - The Manager is the ONLY component that evaluates legality and relays
##     mutations to GamePosition / BoardPosition / PokemonInstances.
##   - The player / CPU may only interact with the game by submitting a
##     Game_Action via request_action().
##
## Turn flow (per player):
##     DRAW    — auto-draw one card from the deck.
##     MAIN    — the player submits Game_Actions.  Per-turn limits:
##                 * 1 energy attachment
##                 * 1 supporter played
##                 * 1 stadium played (different name than current)
##                 * retreat at most once
##                 * basics / items / evolutions / abilities are unlimited
##                 * a Pokemon that entered play this turn cannot evolve
##     CLEANUP — resolve between-turn condition effects for the ending
##               player: paralysis ends; sleep/burn flip to end.
##     -> control passes to the other player.

enum Phase { SETUP, MAIN, ENDED }

signal action_committed(action: GameAction)
signal action_rejected(action: GameAction, reason: String)
signal log_message(text: String)

## Scene-layer listeners connect to these to know when in-play Pokemon need
## new visuals, when hand/discard/deck change, etc.  They are re-emits of
## the underlying system signals so the scene only has to listen in one place.
signal board_slot_changed(slot_id: String, instance: PokemonInstance)
## Emitted after any action that mutates an already-placed PokemonInstance
## (attachments, HP, conditions, evolution).  Slot-keyed so listeners can
## target only the relevant instance.
signal pokemon_state_changed(slot_id: String, instance: PokemonInstance)
signal overflow_escalation(player_id: int, instance: PokemonInstance)
signal hand_changed(player_id: int)
## Fired immediately after a card departs a player's hand (before hand_changed).
signal card_left_hand(player_id: int, card: CardData)
signal deck_changed(player_id: int)
signal discard_changed(player_id: int)
signal prizes_changed(player_id: int)

## Stadium is a global board-state card (only one exists across both players).
signal stadium_changed(stadium: TrainerCardData, owner_id: int)

## Combat signals.
signal pokemon_knocked_out(slot_id: String)
signal prize_taken(player_id: int)
signal prize_selection_required(player_id: int)
signal promotion_required(player_id: int)
signal promotion_done(player_id: int, to_slot: String)
signal game_won(player_id: int)

## Turn / phase signals.
signal turn_started(player_id: int, turn_number: int)
signal turn_ended(player_id: int)
signal phase_changed(phase: int)

## Coin flip signal — emitted for every coin flip in the game.
## [result] is true for heads; [label] names the context (attack name, wake-up check, etc.).
signal coin_flipped(result: bool, label: String)
## Emitted when an attack effect requires the player to choose which energy
## card(s) to discard and the attacker has non-identical energy attached.
signal energy_discard_choice_required(player_id: int, eligible: Array[CardData], count: int, attacker_slot: String)

var board_position: BoardPosition = null
var game_position:  GamePosition = null

## --- Slot configuration ------------------------------------------------------
## Set once per game via configure_slots() before begin_game().
## active_slot_count never changes mid-game; bench_slot_count can change via
## set_bench_count() and may return a list of Pokemon that need to be discarded.
var active_slot_count: int = 1
var bench_slot_count:  int = 5

## --- Board-state CSV logging -------------------------------------------------
var _board_log_file: FileAccess = null

## All slot ids in the order they appear as CSV columns.
const _LOG_SLOTS: Array[String] = [
	"p0_active1", "p0_active2",
	"p0_bench1",  "p0_bench2",  "p0_bench3",  "p0_bench4",  "p0_bench5",
	"p0_overflow1", "p0_overflow2",
	"p1_active1", "p1_active2",
	"p1_bench1",  "p1_bench2",  "p1_bench3",  "p1_bench4",  "p1_bench5",
	"p1_overflow1", "p1_overflow2",
]

## --- Global board state owned by the Manager --------------------------------
##
## These pieces of state are neither per-PokemonInstance nor per-hand/deck;
## they're game-wide flags the turn system resets each turn.

## The Stadium currently in play (null if none), and which player owns it.
var active_stadium: TrainerCardData = null
var active_stadium_owner: int = -1

## --- Turn state -------------------------------------------------------------

var current_player: int = 0
var current_phase:  int = Phase.SETUP
var turn_number:    int = 0

## The player who won the opening coin flip and goes first.  Set by begin_game().
var first_player: int = 0

## --- Energy discard choice state --------------------------------------------
## Set by an effect handler when the attacker has mixed energy and the player
## must choose which card(s) to discard.  Cleared by resolve_energy_discard_choice().
var energy_discard_pending: bool = false
var energy_discard_player:  int  = -1
var energy_discard_count:   int  = 0
var energy_discard_slot:    String = ""

## The player currently in the pre-game placement phase (-1 = not placing).
## Set by begin_setup_placement(); cleared by end_setup_placement().
var setup_placing_player: int = -1

## Per-player turn flags.  Cleared at the start of each player's turn.
var supporter_played_this_turn: Array[bool] = [false, false]
var energy_attached_this_turn:  Array[bool] = [false, false]
var retreat_used_this_turn:     Array[bool] = [false, false]
var attack_used_this_turn:      Array[bool] = [false, false]

## Prize-selection and promotion phases happen between turns (after a KO).
## These are cleared by ActionTakePrize / ActionPromote respectively.
var prize_selection_phase_for: int = -1
var promotion_phase_for:       int = -1
## Defender whose promotion to check after prize selection resolves.
var _ko_defender: int = -1

## Per-player list of PokemonInstance objects that came into play this turn
## (via play-from-hand or evolution).  Prevents "evolve on the same turn you
## played this Pokemon" and "evolve twice on the same turn".
var pokemon_entered_play_this_turn: Array = [[], []]


func _open_board_log() -> void:
	if _board_log_file != null:
		_board_log_file.close()
		_board_log_file = null
	var dt := Time.get_datetime_dict_from_system()
	var fname := "board_log_%04d%02d%02d_%02d%02d%02d.csv" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second,
	]
	_board_log_file = FileAccess.open("user://" + fname, FileAccess.WRITE)
	if _board_log_file == null:
		push_error("BoardLog: cannot open user://%s" % fname)
		return
	var header: PackedStringArray = PackedStringArray(["action"])
	for s in _LOG_SLOTS:
		header.append(s)
	_board_log_file.store_csv_line(header)
	print("BoardLog: logging to ", ProjectSettings.globalize_path("user://" + fname))


func _log_state(action_label: String) -> void:
	if _board_log_file == null or board_position == null:
		return
	var row: PackedStringArray = PackedStringArray([action_label])
	for slot_id in _LOG_SLOTS:
		if not is_valid_slot(slot_id):
			row.append("[invalid]")
			continue
		var inst: PokemonInstance = board_position.get_instance(slot_id)
		if inst == null:
			row.append("[empty]")
		else:
			var pname := inst.card.display_name if inst.card != null else "???"
			row.append("%s (%d/%d)" % [pname, inst.current_hp, inst.max_hp])
	_board_log_file.store_csv_line(row)


func configure_slots(active: int, bench: int) -> void:
	active_slot_count = clampi(active, 1, 2)
	bench_slot_count  = clampi(bench,  3, 5)


## True when slot_id is within the currently configured active/bench limits.
## Overflow slots are always invalid; prize/deck/discard are always valid.
func is_valid_slot(slot_id: String) -> bool:
	if "overflow" in slot_id:
		return false
	if "active" in slot_id:
		return int(slot_id.right(1)) <= active_slot_count
	if "bench" in slot_id:
		return int(slot_id.right(1)) <= bench_slot_count
	return true


## Lowers or raises the bench slot limit mid-game.
## On decrease, auto-relocates Pokemon from now-invalid slots to the lowest
## available valid bench slot.  Returns an Array of {pid, slot_id} Dictionaries
## for any Pokemon that could not be relocated (caller must arrange discards).
func set_bench_count(new_count: int) -> Array:
	new_count = clampi(new_count, 3, 5)
	if new_count == bench_slot_count:
		return []
	bench_slot_count = new_count
	var overflow: Array = []
	## Process highest ordinals first so relocations land in the lowest free slot.
	for n in range(5, new_count, -1):
		for pid in [0, 1]:
			var invalid_slot := "p%d_bench%d" % [pid, n]
			var inst: PokemonInstance = board_position.get_instance(invalid_slot)
			if inst == null:
				continue
			var moved := false
			for m in range(1, new_count + 1):
				var target := "p%d_bench%d" % [pid, m]
				if board_position.get_instance(target) == null:
					board_position.move(invalid_slot, target)
					moved = true
					break
			if not moved:
				overflow.append({"pid": pid, "displaced_slot": invalid_slot})
	return overflow


func _ready() -> void:
	game_position  = GamePosition.new()
	board_position = BoardPosition.new()
	add_child(board_position)

	board_position.slot_changed.connect(_on_slot_changed)
	board_position.overflow_escalation.connect(_on_overflow_escalation)

	game_position.deck_changed.connect(func(pid): deck_changed.emit(pid))
	game_position.hand_changed.connect(func(pid): hand_changed.emit(pid))
	game_position.card_left_hand.connect(func(pid, card): card_left_hand.emit(pid, card))
	game_position.discard_changed.connect(func(pid): discard_changed.emit(pid))
	game_position.prizes_changed.connect(func(pid): prizes_changed.emit(pid))


## Scene-layer hook: called once the Board scene is ready so BoardPosition can
## map slot_ids to the Node3D anchors used for visual placement.
func attach_board_anchors(anchors: Dictionary) -> void:
	board_position.set_slot_anchors(anchors)


## --- Public API: Game_Actions -----------------------------------------------

## The single entry point for Game_Actions.  Validates, applies, emits.
## Returns the ActionResult so callers can react synchronously (e.g. to
## snap a dragged card back on rejection).
func request_action(action: GameAction) -> ActionResult:
	if action == null:
		_reject(null, "Null action.")
		return ActionResult.fail("Null action.")

	## During prize selection or promotion, only the matching action type passes.
	if prize_selection_phase_for >= 0 and not (action is ActionTakePrize):
		_reject(action, "Prize selection is pending — take a prize first.")
		return ActionResult.fail("Prize selection is pending.")
	if promotion_phase_for >= 0 and not (action is ActionPromote):
		_reject(action, "Promotion is pending — promote a Pokémon first.")
		return ActionResult.fail("Promotion is pending.")

	var result: ActionResult = action.validate(self)
	if not result.ok:
		_reject(action, result.reason)
		return result

	action.apply(self)
	log_message.emit(action.description())
	action_committed.emit(action)
	for slot_id in action.affected_slots():
		var inst: PokemonInstance = board_position.get_instance(slot_id)
		if inst != null:
			pokemon_state_changed.emit(slot_id, inst)
	_check_all_promotions_needed()
	_log_state("[Action] " + action.description())
	return ActionResult.success()


## Convenience query for action validators: is it [pid]'s main phase?
func is_main_phase_for(pid: int) -> bool:
	return current_phase == Phase.MAIN and current_player == pid


## Human-readable name for the current phase; used by the scene layer for
## the phase label (avoids cross-script enum lookups).
func phase_name() -> String:
	match current_phase:
		Phase.SETUP:
			if setup_placing_player >= 0:
				return "Place Pokémon"
			return "Setup"
		Phase.MAIN:
			if prize_selection_phase_for >= 0:
				return "Take Prize (P%d)" % prize_selection_phase_for
			if promotion_phase_for >= 0:
				return "Promote (P%d)" % promotion_phase_for
			return "Main"
		Phase.ENDED: return "Cleanup"
	return "?"


## True if [pid] is on their very first turn of the game.
## The first player's first turn is turn 1; the second player's is turn 2.
func is_first_turn_for(pid: int) -> bool:
	return (pid == first_player and turn_number == 1) \
		or (pid != first_player and turn_number == 2)


## --- Public API: setup / turn flow ------------------------------------------

func load_deck(player_id: int, cards: Array[CardData]) -> void:
	game_position.load_deck(player_id, cards)
	game_position.shuffle_deck(player_id)


func draw_starting_hand(player_id: int, count: int = 7) -> void:
	for _i in count:
		game_position.draw(player_id)


func deal_prizes(player_id: int, count: int = 6) -> void:
	game_position.deal_prizes(player_id, count)


## Flips a coin, emits coin_flipped, and returns true for heads.
## All coin flips in the game must route through this method so the visual fires.
func flip_coin(label: String) -> bool:
	var heads: bool = (randi() % 2) == 0
	coin_flipped.emit(heads, label)
	return heads


## Called by the UI after the player selects which energy card(s) to discard
## when energy_discard_choice_required was emitted.
## [indices] are indices into the attacker's attached_energy array.
func resolve_energy_discard_choice(indices: Array[int]) -> void:
	if not energy_discard_pending:
		return
	var attacker: PokemonInstance = board_position.get_instance(energy_discard_slot)
	if attacker == null:
		_clear_energy_discard_state()
		return
	var to_remove: Array[CardData] = []
	var sorted_idx: Array[int] = indices.duplicate()
	sorted_idx.sort()
	sorted_idx.reverse()
	for idx in sorted_idx:
		if idx >= 0 and idx < attacker.attached_energy.size():
			to_remove.append(attacker.attached_energy[idx])
			attacker.attached_energy.remove_at(idx)
	if not to_remove.is_empty():
		game_position.discard_all(energy_discard_player, to_remove)
		attacker.refresh_visual()
		pokemon_state_changed.emit(energy_discard_slot, attacker)
	_clear_energy_discard_state()


func _clear_energy_discard_state() -> void:
	energy_discard_pending = false
	energy_discard_player  = -1
	energy_discard_count   = 0
	energy_discard_slot    = ""


## Starts the match.  Called once after the setup sequence (mulligans + coin
## flip) is complete.  [starting_player] is the coin-flip winner, who goes
## first and has first-turn restrictions applied.
func begin_game(starting_player: int = 0) -> void:
	first_player   = starting_player
	turn_number    = 0
	current_phase  = Phase.SETUP
	for pid in range(2):
		_reset_turn_flags(pid)
	_open_board_log()
	_begin_turn(starting_player)


## --- Public API: setup placement / helpers ----------------------------------

## Enters the placement phase for [pid]: records who is placing so
## ActionSetupPlayBasic can validate correctly, and sets current_player so
## the scene layer's current_player_id() returns the right value.
func begin_setup_placement(pid: int) -> void:
	setup_placing_player = pid
	current_player       = pid


## Exits the placement phase.
func end_setup_placement() -> void:
	setup_placing_player = -1


## True when [pid] is currently in the pre-game placement phase.
func is_setup_placement_for(pid: int) -> bool:
	return current_phase == Phase.SETUP and setup_placing_player == pid


## True if [pid]'s current hand contains at least one Basic Pokémon.
func has_basic_in_hand(pid: int) -> bool:
	return game_position.has_basic_pokemon(pid)


## Returns every card in [pid]'s hand to their deck and shuffles.
func return_hand_to_deck(pid: int) -> void:
	game_position.return_hand_to_deck(pid)


## Draws one card for [pid] (used to grant the opponent a bonus mulligan draw).
func draw_one(pid: int) -> void:
	game_position.draw(pid)


## Returns true if [pid] is allowed to play a Supporter this turn.
## The first player cannot play a Supporter on their very first turn.
func can_play_supporter(pid: int) -> bool:
	if supporter_played_this_turn[pid]:
		return false
	if pid == first_player and turn_number == 1:
		return false
	return true


## Ends the current player's turn: runs cleanup for their board state, emits
## turn_ended, and passes control to the other player.
func end_turn() -> void:
	if current_phase != Phase.MAIN:
		return  ## already between turns / not yet started
	var finishing_player := current_player
	_run_cleanup(finishing_player)
	_log_state("[Cleanup] P%d end of turn %d" % [finishing_player, turn_number])
	log_message.emit("[End Turn] P%d ends turn %d." % [finishing_player, turn_number])
	turn_ended.emit(finishing_player)
	_begin_turn(1 - finishing_player)


## Wipes all turn state / global board state.  Used by the scene layer when
## resetting the match back to the setup dialog.  Subsystems (GamePosition
## / BoardPosition) are rebuilt separately by the scene layer.
func reset_game_state() -> void:
	first_player         = 0
	setup_placing_player = -1
	current_player       = 0
	current_phase        = Phase.SETUP
	turn_number          = 0
	active_stadium            = null
	active_stadium_owner      = -1
	prize_selection_phase_for = -1
	promotion_phase_for       = -1
	_ko_defender              = -1
	_clear_energy_discard_state()
	for pid in range(2):
		_reset_turn_flags(pid)


## --- Internal: turn flow ----------------------------------------------------

func _begin_turn(pid: int) -> void:
	current_player = pid
	turn_number   += 1
	_reset_turn_flags(pid)
	current_phase = Phase.MAIN
	phase_changed.emit(current_phase)
	## The first player does not draw on their very first turn (RS-PK rule).
	var skip_draw := (pid == first_player and turn_number == 1)
	if not skip_draw and not (game_position.decks[pid] as Array).is_empty():
		game_position.draw(pid)
	if skip_draw:
		log_message.emit("[Turn %d] P%d begins — no draw (first player's first turn)." % [turn_number, pid])
	else:
		log_message.emit("[Turn %d] P%d begins." % [turn_number, pid])
	turn_started.emit(pid, turn_number)
	_log_state("[Turn Start] P%d turn %d%s" % [pid, turn_number, " (no draw)" if skip_draw else ""])


func _reset_turn_flags(pid: int) -> void:
	if pid < 0 or pid >= supporter_played_this_turn.size():
		return
	supporter_played_this_turn[pid]  = false
	energy_attached_this_turn[pid]   = false
	retreat_used_this_turn[pid]      = false
	attack_used_this_turn[pid]       = false
	pokemon_entered_play_this_turn[pid] = []


## Resolves between-turn condition effects for [pid]'s in-play Pokemon:
##   - PARALYZED ends automatically at the end of its owner's turn.
##   - ASLEEP flips a coin; heads wakes up.
##   - BURNED flips a coin; heads ends the burn.  (Between-turn burn
##     damage is intentionally not yet applied — damage lives in a later
##     action, to be added alongside Attack resolution.)
func _run_cleanup(pid: int) -> void:
	current_phase = Phase.ENDED
	phase_changed.emit(current_phase)
	for sid in BoardPosition.all_slot_ids(pid):
		var inst: PokemonInstance = board_position.get_instance(sid)
		if inst != null:
			_cleanup_instance(inst)


func _cleanup_instance(inst: PokemonInstance) -> void:
	var name: String = inst.card.display_name if inst.card != null else "Pokemon"
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED):
		inst.remove_condition(PokemonInstance.SpecialCondition.PARALYZED)
		log_message.emit("[Cleanup] %s is no longer Paralyzed." % name)
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP):
		if flip_coin("%s wake-up" % name):
			inst.remove_condition(PokemonInstance.SpecialCondition.ASLEEP)
			log_message.emit("[Cleanup] %s wakes up." % name)
		else:
			log_message.emit("[Cleanup] %s stays Asleep." % name)
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.BURNED):
		if flip_coin("%s burn check" % name):
			inst.remove_condition(PokemonInstance.SpecialCondition.BURNED)
			log_message.emit("[Cleanup] %s's Burn ends." % name)
		else:
			log_message.emit("[Cleanup] %s stays Burned." % name)


## --- Combat resolution -------------------------------------------------------

## Called by ActionAttack after a KO is detected.
func resolve_knockout(defending_slot: String, attacking_player: int) -> void:
	var inst: PokemonInstance = board_position.get_instance(defending_slot)
	if inst == null or not inst.is_knocked_out():
		return
	var defender_player := board_position.player_of(defending_slot)
	var ko_name := inst.card.display_name if inst.card != null else "Pokémon"
	log_message.emit("[KO] %s was Knocked Out!" % ko_name)

	board_position.clear(defending_slot)
	var released: Array[CardData] = inst.release_cards()
	game_position.discard_all(defender_player, released)
	inst.queue_free()

	pokemon_knocked_out.emit(defending_slot)

	## If the defender now has zero Pokémon remaining, the attacker wins
	## immediately (before prizes are taken).
	var defender_has_pokemon := false
	for sid: String in BoardPosition.all_slot_ids(defender_player):
		if board_position.get_instance(sid) != null:
			defender_has_pokemon = true
			break
	if not defender_has_pokemon:
		log_message.emit("[WIN] P%d has no Pokémon remaining — P%d wins!" % [defender_player, attacking_player])
		current_phase = Phase.ENDED
		phase_changed.emit(current_phase)
		game_won.emit(attacking_player)
		_log_state("[KO] %s KO'd — P%d wins" % [ko_name, attacking_player])
		return

	## Begin prize selection for the attacking player.
	if game_position.prizes_remaining(attacking_player) > 0:
		_ko_defender = defender_player
		prize_selection_phase_for = attacking_player
		phase_changed.emit(current_phase)
		prize_selection_required.emit(attacking_player)
		_log_state("[KO] %s KO'd — prize selection for P%d" % [ko_name, attacking_player])
	else:
		_log_state("[KO] %s KO'd — no prizes left, checking promotion" % ko_name)
		_check_promotion_needed(defender_player)


## Checks whether [defender] has an empty active slot that needs filling and
## either fills it automatically (exactly one bench option) or emits
## promotion_required (two or more bench options).
func _check_promotion_needed(defender: int) -> void:
	var empty_actives: Array[String] = []
	for s: String in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [defender, s]
		if is_valid_slot(sid) and board_position.has_slot(sid) \
				and board_position.get_instance(sid) == null:
			empty_actives.append(sid)
	if empty_actives.is_empty():
		_log_state("[Promo Check P%d] active slots full — no promotion" % defender)
		return

	var bench_occupied: Array[String] = []
	for s: String in BoardPosition.BENCH_SLOTS:
		var sid := "p%d_%s" % [defender, s]
		if board_position.has_slot(sid) and board_position.get_instance(sid) != null:
			bench_occupied.append(sid)
	if bench_occupied.is_empty():
		_log_state("[Promo Check P%d] bench empty — no promotion" % defender)
		return

	## Exactly one bench Pokémon — auto-promote to the first empty active slot.
	if bench_occupied.size() == 1:
		var from_slot := bench_occupied[0]
		var to_slot   := empty_actives[0]
		_log_state("[Promo Check P%d] auto-promoting %s → %s" % [defender, from_slot, to_slot])
		board_position.move(from_slot, to_slot)
		var promoted: PokemonInstance = board_position.get_instance(to_slot)
		var pname := promoted.card.display_name if promoted != null and promoted.card != null else "Pokémon"
		log_message.emit("[Promote] %s auto-promoted to active." % pname)
		promotion_done.emit(defender, to_slot)
		_log_state("[Auto-Promote P%d] %s now in %s" % [defender, pname, to_slot])
		return

	_log_state("[Promo Check P%d] multiple bench options — player must choose" % defender)
	promotion_phase_for = defender
	phase_changed.emit(current_phase)
	promotion_required.emit(defender)


## Enforces the invariant that no empty active slot exists while a bench
## Pokémon is available to fill it.  Called after every successful action
## during the MAIN phase so the check covers play-to-bench as well as KOs.
func _check_all_promotions_needed() -> void:
	if current_phase != Phase.MAIN:
		return
	if promotion_phase_for >= 0 or prize_selection_phase_for >= 0:
		return
	for pid: int in [0, 1]:
		if promotion_phase_for >= 0:
			return  ## One pending promotion at a time.
		_check_promotion_needed(pid)


## --- Internal: dispatch -----------------------------------------------------

func _reject(action: GameAction, reason: String) -> void:
	action_rejected.emit(action, reason)
	log_message.emit("[REJECT] %s" % reason)


func _on_slot_changed(slot_id: String, instance: PokemonInstance) -> void:
	board_slot_changed.emit(slot_id, instance)


func _on_overflow_escalation(player_id: int, instance: PokemonInstance) -> void:
	overflow_escalation.emit(player_id, instance)
	log_message.emit("[ESCALATION] P%d has no empty bench for overflow." % player_id)
