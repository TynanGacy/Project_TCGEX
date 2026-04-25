extends Node
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

## Turn / phase signals.
signal turn_started(player_id: int, turn_number: int)
signal turn_ended(player_id: int)
signal phase_changed(phase: int)

var board_position: BoardPosition = null
var game_position:  GamePosition = null

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

## The player currently in the pre-game placement phase (-1 = not placing).
## Set by begin_setup_placement(); cleared by end_setup_placement().
var setup_placing_player: int = -1

## Per-player turn flags.  Cleared at the start of each player's turn.
var supporter_played_this_turn: Array[bool] = [false, false]
var energy_attached_this_turn:  Array[bool] = [false, false]
var retreat_used_this_turn:     Array[bool] = [false, false]

## Per-player list of PokemonInstance objects that came into play this turn
## (via play-from-hand or evolution).  Prevents "evolve on the same turn you
## played this Pokemon" and "evolve twice on the same turn".
var pokemon_entered_play_this_turn: Array = [[], []]


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
	return ActionResult.success()


## Convenience query for action validators: is it [pid]'s main phase?
func is_main_phase_for(pid: int) -> bool:
	return current_phase == Phase.MAIN and current_player == pid


## Human-readable name for the current phase; used by the scene layer for
## the phase label (avoids cross-script enum lookups).
func phase_name() -> String:
	match current_phase:
		Phase.SETUP: return "Setup"
		Phase.MAIN:  return "Main"
		Phase.ENDED: return "Cleanup"
	return "?"


## --- Public API: setup / turn flow ------------------------------------------

func load_deck(player_id: int, cards: Array[CardData]) -> void:
	game_position.load_deck(player_id, cards)
	game_position.shuffle_deck(player_id)


func draw_starting_hand(player_id: int, count: int = 7) -> void:
	for _i in count:
		game_position.draw(player_id)


func deal_prizes(player_id: int, count: int = 6) -> void:
	game_position.deal_prizes(player_id, count)


## Starts the match.  Called once after the setup sequence (mulligans + coin
## flip) is complete.  [starting_player] is the coin-flip winner, who goes
## first and has first-turn restrictions applied.
func begin_game(starting_player: int = 0) -> void:
	first_player   = starting_player
	turn_number    = 0
	current_phase  = Phase.SETUP
	for pid in range(2):
		_reset_turn_flags(pid)
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
	active_stadium       = null
	active_stadium_owner = -1
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


func _reset_turn_flags(pid: int) -> void:
	if pid < 0 or pid >= supporter_played_this_turn.size():
		return
	supporter_played_this_turn[pid] = false
	energy_attached_this_turn[pid]  = false
	retreat_used_this_turn[pid]     = false
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
		if randi() % 2 == 0:
			inst.remove_condition(PokemonInstance.SpecialCondition.ASLEEP)
			log_message.emit("[Cleanup] %s wakes up." % name)
		else:
			log_message.emit("[Cleanup] %s stays Asleep." % name)
	if inst.special_conditions.has(PokemonInstance.SpecialCondition.BURNED):
		if randi() % 2 == 0:
			inst.remove_condition(PokemonInstance.SpecialCondition.BURNED)
			log_message.emit("[Cleanup] %s's Burn ends." % name)
		else:
			log_message.emit("[Cleanup] %s stays Burned." % name)


## --- Internal: dispatch -----------------------------------------------------

func _reject(action: GameAction, reason: String) -> void:
	action_rejected.emit(action, reason)
	log_message.emit("[REJECT] %s" % reason)


func _on_slot_changed(slot_id: String, instance: PokemonInstance) -> void:
	board_slot_changed.emit(slot_id, instance)


func _on_overflow_escalation(player_id: int, instance: PokemonInstance) -> void:
	overflow_escalation.emit(player_id, instance)
	log_message.emit("[ESCALATION] P%d has no empty bench for overflow." % player_id)
