extends Node
## Central Manager.  Mediates every Game_Action that mutates the game state:
## playing Basic Pokemon, attaching energy and tools, playing items /
## supporters / stadiums, and evolving.  Attacks and the formal turn system
## will be layered on top of these once they return.
##
## Contract (vision):
##   - Game_Actions are declarative; they do NOT mutate state themselves.
##   - The Manager is the ONLY component that evaluates legality and relays
##     mutations to GamePosition / BoardPosition / PokemonInstances.
##   - The player / CPU may only interact with the game by submitting a
##     Game_Action via request_action().

signal action_committed(action: GameAction)
signal action_rejected(action: GameAction, reason: String)
signal log_message(text: String)

## Scene-layer listeners connect to these to know when in-play Pokemon need
## new visuals, when hand/discard/deck change, etc.  They are re-emits of
## the underlying system signals so the scene only has to listen in one place.
signal board_slot_changed(slot_id: String, instance: PokemonInstance)
signal overflow_escalation(player_id: int, instance: PokemonInstance)
signal hand_changed(player_id: int)
signal deck_changed(player_id: int)
signal discard_changed(player_id: int)
signal prizes_changed(player_id: int)

## Stadium is a global board-state card (only one exists across both players).
signal stadium_changed(stadium: TrainerCardData, owner_id: int)

var board_position: BoardPosition = null
var game_position:  GamePosition = null

## --- Global board state owned by the Manager --------------------------------
##
## These pieces of state are neither per-PokemonInstance nor per-hand/deck;
## they're game-wide flags the turn system will reset each turn.

## The Stadium currently in play (null if none), and which player owns it.
var active_stadium: TrainerCardData = null
var active_stadium_owner: int = -1

## Per-player turn flags.  Reset by reset_turn_flags() when the turn system
## is restored; until then they persist across the session.
var supporter_played_this_turn: Array[bool] = [false, false]
var energy_attached_this_turn:  Array[bool] = [false, false]


func _ready() -> void:
	game_position  = GamePosition.new()
	board_position = BoardPosition.new()
	add_child(board_position)

	board_position.slot_changed.connect(_on_slot_changed)
	board_position.overflow_escalation.connect(_on_overflow_escalation)

	game_position.deck_changed.connect(func(pid): deck_changed.emit(pid))
	game_position.hand_changed.connect(func(pid): hand_changed.emit(pid))
	game_position.discard_changed.connect(func(pid): discard_changed.emit(pid))
	game_position.prizes_changed.connect(func(pid): prizes_changed.emit(pid))


## Scene-layer hook: called once the Board scene is ready so BoardPosition can
## map slot_ids to the Node3D anchors used for visual placement.
func attach_board_anchors(anchors: Dictionary) -> void:
	board_position.set_slot_anchors(anchors)


## --- Public API -------------------------------------------------------------

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
	return ActionResult.success()


## Convenience helpers the scene layer uses for startup — NOT actions, since
## these happen before the player is "playing".

func load_deck(player_id: int, cards: Array[CardData]) -> void:
	game_position.load_deck(player_id, cards)
	game_position.shuffle_deck(player_id)


func draw_starting_hand(player_id: int, count: int = 7) -> void:
	for _i in count:
		game_position.draw(player_id)


func deal_prizes(player_id: int, count: int = 6) -> void:
	game_position.deal_prizes(player_id, count)


## Clears per-turn flags for [player_id].  Called by the (future) turn
## system at the start of a player's turn.  Stadium state is intentionally
## NOT cleared — Stadiums persist across turns until replaced.
func reset_turn_flags(player_id: int) -> void:
	if player_id < 0 or player_id >= supporter_played_this_turn.size():
		return
	supporter_played_this_turn[player_id] = false
	energy_attached_this_turn[player_id]  = false


## --- Internal ---------------------------------------------------------------

func _reject(action: GameAction, reason: String) -> void:
	action_rejected.emit(action, reason)
	log_message.emit("[REJECT] %s" % reason)


func _on_slot_changed(slot_id: String, instance: PokemonInstance) -> void:
	board_slot_changed.emit(slot_id, instance)


func _on_overflow_escalation(player_id: int, instance: PokemonInstance) -> void:
	overflow_escalation.emit(player_id, instance)
	log_message.emit("[ESCALATION] P%d has no empty bench for overflow." % player_id)
