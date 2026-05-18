extends Node3D
## Main scene.
##
## Startup flow:
##   _ready() -> _show_setup_dialog() -> _on_setup_confirmed() -> _start_game()
##   -> manager.begin_game(0) -> turn_started (per-turn loop).
##
## Setup collects: mode (developer / player), prize count (2-6), active slot
## count (1-2), bench slot count (3-5), and per-player deck selection.
##
## Developer mode swaps the visible hand to whichever player's turn it is
## so the operator can drive both sides.  Player mode keeps the visible hand
## fixed to player 0 (the CPU for player 1 is a future addition).
##
## Wires the four systems (PokemonInstance / BoardPosition / GamePosition /
## ManagerSystem) together for the user flow:
##   - Drag a card from the visible hand onto a board zone.
##   - _build_action_for_drop() picks the right Game_Action by card type.
##   - The Manager validates / applies / emits.
## The turn flow (draw, main, cleanup, pass) is owned by the Manager; the
## End Turn button submits manager.end_turn().

@onready var camera: Camera3D = $Camera3D
@onready var board:  Board    = $Board
@onready var player_hand: Hand = $Board/PlayerHand

@onready var phase_label: Label = $HUD/TopBar/PhaseLabel
@onready var end_turn_button: Button = $HUD/TopBar/EndTurnButton
@onready var game_log: RichTextLabel = $HUD/LogPanel/GameLog
@onready var card_zoom_popup: CardZoomPopup = $HUD/CardZoomPopup

@onready var manager: Node = ManagerSystemSingleton
var _authority: MatchAuthority = null

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")
const CARD_BACK: Texture2D = preload("res://assets/images/card_back.png")
const _HAND_SCENE: PackedScene = preload("res://scenes/hand/hand.tscn")

var _hand_mgr: HandVisualManager = null
var _opponent_hand: Hand = null

var _pile_mgr: PileVisualManager = null
var _setup_mgr: SetupManager = null

## Visual card node currently displayed in the shared supporter slot, or null.
var _supporter_visual: Card = null

var _input_mgr: InputManager = null

## Perspective (developer mode).  When the active turn changes we flip the
## camera, the hand anchor, and every in-play PokemonInstance so the board
## reads correctly from whichever side the controlling player is on.  Piles
## (prizes / deck / discard) and off-table UI stay put.
var _controlling_player: int = 0
var _p0_cam_transform: Transform3D = Transform3D.IDENTITY
var _p1_cam_transform: Transform3D = Transform3D.IDENTITY
var _p0_hand_transform: Transform3D = Transform3D.IDENTITY
var _p1_hand_transform: Transform3D = Transform3D.IDENTITY

## --- Setup state ------------------------------------------------------------
var is_developer_mode: bool = false
## Set true by SetupManager when mode == "player".  Toggles the AIDriver as
## the source of P1 input and tells the dialog/match code to skip showing
## CPU-facing prompts.
var opponent_is_cpu: bool = false
var _prize_count:      int  = 6
var _active_slots:     int  = 1
var _bench_slots:      int  = 5
var _setup_dialog: Control = null

## CPU driver (null in developer mode or before _start_game runs).
var _ai_driver: AIDriver = null


## True when [pid] is being driven by AIDriver (P1 in Player Mode).
func is_cpu_player(pid: int) -> bool:
	return opponent_is_cpu and pid == 1

## Coin flip overlay — created in _ready(), shown for every coin flip.
var _coin_flip_overlay: Control = null

## True while the pre-game setup sequence (mulligans / coin flip) is running.
## Blocks drag input so cards can't be moved before the game starts.
var _in_setup_phase: bool = false

## True while a player is in the "place starting Pokémon" step.  The End Turn
## button is relabelled "Ready" and guarded against calling end_turn().
var _in_placement_phase: bool = false

## Programmatically-added Reset button lives next to the End-Turn button
## in the TopBar.
var _reset_button:      Button = null
var _attack_button:     Button = null
var _retreat_button:    Button = null
var _save_state_button:  Button = null
var _load_state_button:  Button = null
var _back_to_menu_button: Button = null

var _dialog_mgr:    DialogManager   = null
var _save_load_mgr: SaveLoadManager = null

## Match-local nodes (moved from autoload so they free with this scene).
var _anim_manager:    Node = null
var _effect_handlers: Node = null
var _trainer_handlers: Node = null
var _ability_handlers: Node = null

## Deferred end-of-turn: set when an attack commits; cleared after prize
## selection and promotion both resolve so we don't end the turn too early.
var _attack_end_turn_pending: bool = false


func _ready() -> void:
	## Match-local subsystems — created first so ManagerSystemSingleton can
	## reference animation_manager before any other node tries to use it.
	_anim_manager = load("res://scenes/match/animation_manager.gd").new()
	add_child(_anim_manager)
	_effect_handlers = load("res://scenes/match/effect_handlers.gd").new()
	add_child(_effect_handlers)
	_trainer_handlers = load("res://scenes/match/trainer_handlers.gd").new()
	add_child(_trainer_handlers)
	_ability_handlers = load("res://scenes/match/ability_handlers.gd").new()
	add_child(_ability_handlers)
	ManagerSystemSingleton.animation_manager = _anim_manager

	_pile_mgr = PileVisualManager.new()
	add_child(_pile_mgr)
	_pile_mgr.init(self)

	_hand_mgr = HandVisualManager.new()
	add_child(_hand_mgr)
	_hand_mgr.init(self)

	_dialog_mgr = DialogManager.new()
	add_child(_dialog_mgr)

	_input_mgr = InputManager.new()
	add_child(_input_mgr)

	phase_label.text = ""
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	_reset_button = Button.new()
	_reset_button.text = "Reset"
	_reset_button.pressed.connect(_reset_game)
	end_turn_button.get_parent().add_child(_reset_button)

	_attack_button = Button.new()
	_attack_button.text = "Attack"
	_attack_button.pressed.connect(_on_attack_pressed)
	end_turn_button.get_parent().add_child(_attack_button)

	_retreat_button = Button.new()
	_retreat_button.text = "Retreat"
	_retreat_button.pressed.connect(_on_retreat_pressed)
	end_turn_button.get_parent().add_child(_retreat_button)

	_save_state_button = Button.new()
	_save_state_button.text = "Save State"
	_save_state_button.disabled = true
	_save_state_button.pressed.connect(_on_save_state_pressed)
	end_turn_button.get_parent().add_child(_save_state_button)

	_load_state_button = Button.new()
	_load_state_button.text = "Load State"
	_load_state_button.disabled = true
	_load_state_button.pressed.connect(_on_load_state_pressed)
	end_turn_button.get_parent().add_child(_load_state_button)

	_back_to_menu_button = Button.new()
	_back_to_menu_button.text = "Menu"
	_back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	end_turn_button.get_parent().add_child(_back_to_menu_button)

	_authority = LocalMatchAuthority.new(manager)
	_authority.action_committed.connect(_on_action_committed)
	_authority.action_rejected.connect(_on_action_rejected)
	_authority.log_message.connect(_log)
	_authority.hand_changed.connect(_on_hand_changed)
	_authority.card_left_hand.connect(_on_card_left_hand)
	_authority.board_slot_changed.connect(_on_board_slot_changed)
	_authority.overflow_escalation.connect(_on_overflow_escalation)
	_authority.deck_changed.connect(_on_deck_changed)
	_authority.discard_changed.connect(_on_discard_changed)
	_authority.prizes_changed.connect(_on_prizes_changed)
	_authority.stadium_changed.connect(_on_stadium_changed)
	_authority.supporter_changed.connect(_on_supporter_changed)
	_authority.turn_started.connect(_on_turn_started)
	_authority.turn_ended.connect(_on_turn_ended)
	_authority.phase_changed.connect(_on_phase_changed)
	_authority.pokemon_knocked_out.connect(_on_pokemon_knocked_out)
	_authority.prize_taken.connect(_on_prize_taken)
	_authority.prize_selection_required.connect(_on_prize_selection_required)
	_authority.promotion_required.connect(_on_promotion_required)
	_authority.promotion_done.connect(_on_promotion_done)
	_authority.game_won.connect(_on_game_won)

	## Coin flip overlay — shown briefly whenever any coin is flipped.
	## AnimationManager auto-connects to coin signals and drives the overlay.
	_coin_flip_overlay = preload("res://scenes/ui/coin_flip_overlay.gd").new()
	$HUD.add_child(_coin_flip_overlay)
	_anim_manager.set_coin_overlay(_coin_flip_overlay)
	manager.energy_discard_choice_required.connect(_on_energy_discard_choice_required)
	manager.retreat_energy_choice_required.connect(_on_retreat_energy_choice_required)
	if manager.trainer_resolver != null:
		manager.trainer_resolver.player_query_requested.connect(_on_trainer_query_requested)
	if manager.attack_resolver != null:
		manager.attack_resolver.player_query_requested.connect(_on_attack_query_requested)

	_dialog_mgr.init(self)
	_input_mgr.init(self)
	_setup_mgr = SetupManager.new()
	add_child(_setup_mgr)
	_setup_mgr.init(self)

	_save_load_mgr = SaveLoadManager.new()
	add_child(_save_load_mgr)
	_save_load_mgr.init(self)

	## Capture both perspective transforms up front.  P0 takes the scene's
	## default camera / hand placement; P1 is the same transforms rotated
	## 180° around the world Y axis so the board reads from the opposite
	## side of the table.
	_p0_cam_transform  = camera.transform
	_p0_hand_transform = player_hand.transform
	var y_flip := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	_p1_cam_transform  = y_flip * _p0_cam_transform
	_p1_hand_transform = y_flip * _p0_hand_transform

	## Wait a frame so Board._ready has run and DropZones are positioned.
	await get_tree().process_frame
	_authority.attach_board_anchors(board.collect_slot_anchors())

	_setup_mgr.show_setup_dialog()


## Setup dialog and sequence — delegated to SetupManager.


func _on_back_to_menu_pressed() -> void:
	ManagerSystemSingleton.full_reset()
	GameStateManager.return_to_menu()


func _reset_game() -> void:
	_in_setup_phase = false
	_attack_end_turn_pending = false

	## Abort any in-flight pipelines BEFORE freeing PokemonInstance / board
	## state so resolver coroutines awaiting on animations or queries bail
	## cleanly instead of resuming with stale references.  AnimationManager's
	## queue is drained synchronously so awaiters wake immediately and hit
	## their _should_bail check.
	if manager.attack_resolver != null:
		manager.attack_resolver.abort()
	if manager.trainer_resolver != null:
		manager.trainer_resolver.abort()
	if manager.ability_resolver != null:
		manager.ability_resolver.abort()
	if manager.animation_manager != null:
		manager.animation_manager.clear_queue()

	_input_mgr.reset()
	_dialog_mgr.clear()
	_pile_mgr.clear()

	_hand_mgr.clear()

	if _opponent_hand != null:
		_opponent_hand.queue_free()
		_opponent_hand = null

	## Clear every PokemonInstance from every slot.
	for sid in BoardPosition.all_slot_ids():
		var inst: PokemonInstance = manager.board_position.clear(sid)
		if inst != null:
			inst.queue_free()

	## Reset state by rebuilding the Manager's subsystems.
	manager.game_position  = GamePosition.new()
	manager.board_position.queue_free()
	manager.board_position = BoardPosition.new()
	manager.add_child(manager.board_position)
	manager.board_position.slot_changed.connect(manager._on_slot_changed)
	manager.board_position.overflow_escalation.connect(manager._on_overflow_escalation)
	manager.game_position.deck_changed.connect(func(pid): manager.deck_changed.emit(pid))
	manager.game_position.hand_changed.connect(func(pid): manager.hand_changed.emit(pid))
	manager.game_position.card_left_hand.connect(func(pid, card): manager.card_left_hand.emit(pid, card))
	manager.game_position.discard_changed.connect(func(pid): manager.discard_changed.emit(pid))
	manager.game_position.prizes_changed.connect(func(pid): manager.prizes_changed.emit(pid))
	manager.attach_board_anchors(board.collect_slot_anchors())

	## Clear turn / global board state owned by the Manager.
	manager.reset_game_state()

	## Snap back to P0 perspective so the setup dialog and the next game
	## start from the default camera side.
	_controlling_player = 0
	camera.transform = _p0_cam_transform

	_save_state_button.disabled = true
	_load_state_button.disabled = true

	phase_label.text = ""
	game_log.clear()
	_setup_mgr.show_setup_dialog()


## ---------------------------------------------------------------------------
## Hand visuals
## ---------------------------------------------------------------------------

func _on_card_left_hand(player_id: int, card: CardData) -> void:
	_hand_mgr.on_card_left_hand(player_id, card)


func _on_hand_changed(player_id: int) -> void:
	_hand_mgr.sync_new_cards(player_id)


## Stub callbacks used as drag signal targets by HandVisualManager.
func _on_card_drag_started(_card: Card) -> void:
	pass


func _on_card_dropped(_card: Card) -> void:
	pass


## ---------------------------------------------------------------------------
## Manager signal handlers
## ---------------------------------------------------------------------------

func _on_action_committed(action: GameAction) -> void:
	_log("[OK] %s" % action.description())


func _on_action_rejected(action: GameAction, reason: String) -> void:
	if action != null:
		_log("[X] %s — %s" % [action.description(), reason])
	else:
		_log("[X] %s" % reason)


## BoardPosition places the PokemonInstance visual itself, but every
## placement / move / swap resets the instance's local rotation.  Re-apply
## the current perspective so a freshly-placed Pokemon reads right-side up
## after a mid-game perspective flip.
func _on_board_slot_changed(_slot_id: String, instance: PokemonInstance) -> void:
	if instance == null:
		return
	instance.rotation.y = _board_rotation_y()


func _on_overflow_escalation(player_id: int, _instance) -> void:
	_log("[Overflow] P%d has no empty bench — manual resolution required." % player_id)


func _on_stadium_changed(stadium: TrainerCardData, owner_id: int) -> void:
	if stadium == null:
		_log("[Stadium] cleared.")
	else:
		_log("[Stadium] P%d: %s is now in play." % [owner_id, stadium.display_name])


## Adds / removes the visual card in the shared Supporter zone. Driven by the
## manager's supporter_changed signal — fires on play (card != null) and on
## end-of-turn discard (card == null).
func _on_supporter_changed(supporter: TrainerCardData, owner_id: int) -> void:
	if _supporter_visual != null:
		_supporter_visual.queue_free()
		_supporter_visual = null
	if supporter == null:
		_log("[Supporter] cleared.")
		return
	_log("[Supporter] P%d plays %s." % [owner_id, supporter.display_name])
	var zone: DropZone = (board as Board).get_supporter_zone()
	if zone == null:
		return
	_supporter_visual = card_scene.instantiate() as Card
	zone.add_child(_supporter_visual)
	_supporter_visual.position = Vector3.ZERO
	# Rotate so the card reads right-side-up from the owner's perspective.
	if owner_id == 1:
		_supporter_visual.rotation.y = PI
	_supporter_visual.face_down = false
	_supporter_visual.set_data(supporter)


## ---------------------------------------------------------------------------
## Turn / phase
## ---------------------------------------------------------------------------

func _on_end_turn_pressed() -> void:
	if _in_placement_phase:
		return
	await _authority.end_turn_async()


func _on_turn_started(pid: int, _turn_num: int) -> void:
	if is_developer_mode:
		_apply_perspective(pid)
	_hand_mgr.rebuild(0)
	_hand_mgr.rebuild(1)
	_update_phase_label()
	_save_state_button.disabled = false
	_load_state_button.disabled = false


## --- Developer-mode perspective flip ---------------------------------------

## Y rotation in radians that in-play cards should use from the controlling
## player's perspective.  P0 reads natively; P1 reads upside-down unless we
## flip the cards 180° around Y.
func _board_rotation_y() -> float:
	return 0.0 if _controlling_player == 0 else PI


## Moves the camera to [pid]'s side of the table and re-orients every
## in-play PokemonInstance so cards read right-side-up from that perspective.
## The two Hand nodes are fixed in world space at their respective player's
## side — the camera flip naturally brings each player's hand to the near side
## without needing to move the nodes themselves.
func _apply_perspective(pid: int) -> void:
	if pid == _controlling_player:
		return
	_controlling_player = pid
	camera.transform = _p0_cam_transform if pid == 0 else _p1_cam_transform
	var y_rot := _board_rotation_y()
	for sid in BoardPosition.all_slot_ids():
		var inst: PokemonInstance = manager.board_position.get_instance(sid)
		if inst != null:
			inst.rotation.y = y_rot
	## Mirror Stadium / Supporter so each stays on the controlling player's
	## screen-left and screen-right respectively.
	board.apply_perspective(pid)


func _on_turn_ended(_pid: int) -> void:
	_update_phase_label()


func _on_phase_changed(_phase: int) -> void:
	_update_phase_label()


func _update_phase_label() -> void:
	var mode := "Developer" if is_developer_mode else "Player"
	phase_label.text = "%s  |  P%d  |  Turn %d  |  %s" % [
		mode, _authority.current_player_id(), _authority.current_turn_number(), _authority.phase_name(),
	]


func _on_deck_changed(pid: int) -> void:
	_pile_mgr.refresh_deck(pid)


func _on_discard_changed(pid: int) -> void:
	_pile_mgr.refresh_discard(pid)


func _on_prizes_changed(pid: int) -> void:
	_pile_mgr.refresh_prizes(pid)


## ---------------------------------------------------------------------------
## Attack / Retreat / Bench / Dialog UI — delegated to DialogManager
## ---------------------------------------------------------------------------

func _on_attack_pressed() -> void:
	_dialog_mgr.on_attack_pressed()


func _on_retreat_pressed() -> void:
	_dialog_mgr.on_retreat_pressed()


func _on_prize_selection_required(player_id: int) -> void:
	if is_cpu_player(player_id):
		return  ## AIDriver answers on the CPU side.
	_dialog_mgr.on_prize_selection_required(player_id)


func _on_promotion_required(player_id: int) -> void:
	if is_cpu_player(player_id):
		return  ## AIDriver answers on the CPU side.
	_dialog_mgr.on_promotion_required(player_id)


func _on_pokemon_knocked_out(_slot_id: String) -> void:
	_update_phase_label()


func _on_prize_taken(player_id: int) -> void:
	_dialog_mgr.on_prize_taken(player_id)


func _on_promotion_done(_player_id: int, _to_slot: String) -> void:
	_dialog_mgr.on_promotion_done()


func _on_game_won(player_id: int) -> void:
	_attack_end_turn_pending = false
	_log("[GAME OVER] Player %d wins!" % player_id)
	end_turn_button.disabled  = true
	if _attack_button  != null: _attack_button.disabled  = true
	if _retreat_button != null: _retreat_button.disabled = true
	_dialog_mgr.on_game_won(player_id)


func _on_energy_discard_choice_required(
		player_id: int, eligible: Array, count: int, attacker_slot: String) -> void:
	if is_cpu_player(player_id):
		return
	_dialog_mgr.on_energy_discard_choice_required(player_id, eligible, count, attacker_slot)


func _on_retreat_energy_choice_required(
		player_id: int, eligible: Array, count: int, active_slot: String) -> void:
	if is_cpu_player(player_id):
		return
	_dialog_mgr.on_retreat_energy_choice_required(player_id, eligible, count, active_slot)


func _on_trainer_query_requested(query: TrainerQuery) -> void:
	if query != null and is_cpu_player(query.player_id):
		return
	_dialog_mgr.on_trainer_query_requested(query)


func _on_attack_query_requested(query: AttackQuery) -> void:
	if query != null and is_cpu_player(query.player_id):
		return
	_dialog_mgr.on_attack_query_requested(query)


## ---------------------------------------------------------------------------
## End-of-turn after attack (cross-manager orchestration)
## ---------------------------------------------------------------------------

func _try_end_turn_after_attack() -> void:
	if not _attack_end_turn_pending:
		return
	if manager.prize_selection_phase_for >= 0:
		return
	if manager.promotion_phase_for >= 0:
		return
	_attack_end_turn_pending = false
	await _authority.end_turn_async()


func _log(text: String) -> void:
	game_log.append_text(text + "\n")


## ---------------------------------------------------------------------------
## Save / Load state — delegated to SaveLoadManager
## ---------------------------------------------------------------------------

func _on_save_state_pressed() -> void:
	_save_load_mgr.on_save_pressed()


func _on_load_state_pressed() -> void:
	_save_load_mgr.on_load_pressed()
