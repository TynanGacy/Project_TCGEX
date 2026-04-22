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

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")
const CARD_BACK: Texture2D = preload("res://assets/images/card_back.png")

## CardData -> Card node cache for the hand.
var _hand_cards: Dictionary = {}

## zone_name -> Card node for deck / discard / prize pile visuals.  Keys are
## the full DropZone.zone_name (e.g. "Deck", "Opp Deck", "Prize 3",
## "Opp Prize 5") so player 0 and player 1 piles coexist without clashing.
var _pile_nodes: Dictionary = {}

## Drag state
var dragged_card: Card = null
const DRAG_PLANE := Plane(Vector3.UP, 0.0)

## Hover state — the Node3D currently lifted by the mouse cursor.  This is
## either a Card (for hand / pile cards) or a PokemonInstance (for board
## cards), so the whole instance — nameplate included — rises together.
var _hovered_node: Node3D = null

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
var _prize_count:      int  = 6
var _active_slots:     int  = 1
var _bench_slots:      int  = 5
var _player_deck_path:   String = ""
var _opponent_deck_path: String = ""

var _setup_dialog: Control = null
var _setup_selected_mode: String = ""


## Programmatically-added Reset button lives next to the End-Turn button
## in the TopBar.
var _reset_button: Button = null


func _ready() -> void:
	phase_label.text = ""
	end_turn_button.text = "End Turn"
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	_reset_button = Button.new()
	_reset_button.text = "Reset"
	_reset_button.pressed.connect(_reset_game)
	end_turn_button.get_parent().add_child(_reset_button)

	manager.action_committed.connect(_on_action_committed)
	manager.action_rejected.connect(_on_action_rejected)
	manager.log_message.connect(_log)
	manager.hand_changed.connect(_on_hand_changed)
	manager.board_slot_changed.connect(_on_board_slot_changed)
	manager.overflow_escalation.connect(_on_overflow_escalation)
	manager.deck_changed.connect(_on_deck_changed)
	manager.discard_changed.connect(_on_discard_changed)
	manager.prizes_changed.connect(_on_prizes_changed)
	manager.stadium_changed.connect(_on_stadium_changed)
	manager.turn_started.connect(_on_turn_started)
	manager.turn_ended.connect(_on_turn_ended)
	manager.phase_changed.connect(_on_phase_changed)

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
	manager.attach_board_anchors(board.collect_slot_anchors())

	_show_setup_dialog()


## ---------------------------------------------------------------------------
## Setup dialog
## ---------------------------------------------------------------------------

func _show_setup_dialog() -> void:
	_setup_dialog = PanelContainer.new()
	_setup_dialog.custom_minimum_size = Vector2(420, 320)
	_setup_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.97)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_setup_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_setup_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "Pokemon TCG Simulator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	var mode_label := Label.new()
	mode_label.text = "Select Mode:"
	vbox.add_child(mode_label)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	vbox.add_child(mode_row)

	var dev_btn    := Button.new()
	var player_btn := Button.new()
	dev_btn.text    = "Developer Mode"
	player_btn.text = "Player Mode"
	dev_btn.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	player_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(dev_btn)
	mode_row.add_child(player_btn)

	var mode_desc := Label.new()
	mode_desc.text = "Choose a mode above."
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(mode_desc)

	vbox.add_child(HSeparator.new())

	var prize_row := HBoxContainer.new()
	var prize_lbl := Label.new()
	prize_lbl.text = "Prize Cards (2-6):"
	prize_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var prize_spin := SpinBox.new()
	prize_spin.min_value = 2
	prize_spin.max_value = 6
	prize_spin.value     = _prize_count
	prize_row.add_child(prize_lbl)
	prize_row.add_child(prize_spin)
	vbox.add_child(prize_row)

	var active_row := HBoxContainer.new()
	var active_lbl := Label.new()
	active_lbl.text = "Active Slots (1-2):"
	active_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active_spin := SpinBox.new()
	active_spin.min_value = 1
	active_spin.max_value = 2
	active_spin.value     = _active_slots
	active_row.add_child(active_lbl)
	active_row.add_child(active_spin)
	vbox.add_child(active_row)

	var bench_row := HBoxContainer.new()
	var bench_lbl := Label.new()
	bench_lbl.text = "Bench Slots (3-5):"
	bench_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bench_spin := SpinBox.new()
	bench_spin.min_value = 3
	bench_spin.max_value = 5
	bench_spin.value     = _bench_slots
	bench_row.add_child(bench_lbl)
	bench_row.add_child(bench_spin)
	vbox.add_child(bench_row)

	vbox.add_child(HSeparator.new())

	var deck_options := DeckLoader.get_valid_decks()

	var p1_deck_row := HBoxContainer.new()
	var p1_deck_lbl := Label.new()
	p1_deck_lbl.text = "Player Deck:"
	p1_deck_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p1_deck_opt := OptionButton.new()
	p1_deck_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_deck_opt.add_item("Random Deck")
	for deck_entry: Dictionary in deck_options:
		p1_deck_opt.add_item(deck_entry["label"] as String)
	p1_deck_row.add_child(p1_deck_lbl)
	p1_deck_row.add_child(p1_deck_opt)
	vbox.add_child(p1_deck_row)

	var p2_deck_row := HBoxContainer.new()
	var p2_deck_lbl := Label.new()
	p2_deck_lbl.text = "Opponent Deck:"
	p2_deck_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p2_deck_opt := OptionButton.new()
	p2_deck_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p2_deck_opt.add_item("Random Deck")
	for deck_entry: Dictionary in deck_options:
		p2_deck_opt.add_item(deck_entry["label"] as String)
	p2_deck_row.add_child(p2_deck_lbl)
	p2_deck_row.add_child(p2_deck_opt)
	vbox.add_child(p2_deck_row)

	vbox.add_child(HSeparator.new())

	var start_btn := Button.new()
	start_btn.text     = "Start Game"
	start_btn.disabled = true
	vbox.add_child(start_btn)

	_setup_selected_mode = ""

	dev_btn.pressed.connect(func() -> void:
		_setup_selected_mode = "developer"
		dev_btn.modulate    = Color(0.4, 0.9, 0.4)
		player_btn.modulate = Color.WHITE
		mode_desc.text = "Developer Mode: No CPU. (Perspective flip / both-sides play will be restored alongside the turn system.)"
		start_btn.disabled = false
	)
	player_btn.pressed.connect(func() -> void:
		_setup_selected_mode = "player"
		player_btn.modulate = Color(0.4, 0.4, 0.9)
		dev_btn.modulate    = Color.WHITE
		mode_desc.text = "Player Mode: CPU opponent will be restored with the turn system."
		start_btn.disabled = false
	)
	start_btn.pressed.connect(func() -> void:
		var p_sel := p1_deck_opt.selected
		var o_sel := p2_deck_opt.selected
		var p_path: String = _resolve_deck_path(p_sel, deck_options)
		var o_path: String = _resolve_deck_path(o_sel, deck_options)
		_setup_dialog.queue_free()
		_setup_dialog = null
		_on_setup_confirmed(
			_setup_selected_mode,
			int(prize_spin.value),
			int(active_spin.value),
			int(bench_spin.value),
			p_path,
			o_path
		)
	)

	$HUD.add_child(_setup_dialog)


func _resolve_deck_path(sel: int, deck_options: Array[Dictionary]) -> String:
	if deck_options.is_empty():
		return ""
	if sel <= 0:
		return deck_options[randi() % deck_options.size()]["path"] as String
	return deck_options[sel - 1]["path"] as String


func _on_setup_confirmed(
	mode: String,
	prizes: int,
	active_slots: int,
	bench_slots: int,
	player_deck_path: String,
	opponent_deck_path: String
) -> void:
	is_developer_mode   = (mode == "developer")
	_prize_count        = prizes
	_active_slots       = active_slots
	_bench_slots        = bench_slots
	_player_deck_path   = player_deck_path
	_opponent_deck_path = opponent_deck_path
	_start_game()


## ---------------------------------------------------------------------------
## Game lifecycle
## ---------------------------------------------------------------------------

func _start_game() -> void:
	board.configure_slots(_active_slots, _bench_slots, _prize_count)

	var p0_deck: Array[CardData] = DeckLoader.load_deck(0, _player_deck_path)
	var p1_deck: Array[CardData] = DeckLoader.load_deck(1, _opponent_deck_path)
	manager.load_deck(0, p0_deck)
	manager.load_deck(1, p1_deck)

	manager.draw_starting_hand(0, 7)
	manager.draw_starting_hand(1, 7)

	manager.deal_prizes(0, _prize_count)
	manager.deal_prizes(1, _prize_count)

	## Start turn 1.  _on_turn_started handles the hand rebuild and phase label.
	manager.begin_game(0)


func _reset_game() -> void:
	## Clear pile visuals.  Deck entries are Array[Card] (layered stack);
	## discard / prize entries are single Card nodes.
	for entry in _pile_nodes.values():
		if entry is Array:
			for layer in entry:
				if is_instance_valid(layer):
					(layer as Node).queue_free()
		elif is_instance_valid(entry):
			(entry as Node).queue_free()
	_pile_nodes.clear()

	## Clear hand visuals.
	player_hand.clear_cards()
	for card in _hand_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_hand_cards.clear()

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
	manager.game_position.discard_changed.connect(func(pid): manager.discard_changed.emit(pid))
	manager.game_position.prizes_changed.connect(func(pid): manager.prizes_changed.emit(pid))
	manager.attach_board_anchors(board.collect_slot_anchors())

	## Clear turn / global board state owned by the Manager.
	manager.reset_game_state()

	## Snap back to P0 perspective so the setup dialog and the next game
	## start from the default camera side.
	_controlling_player = 0
	camera.transform = _p0_cam_transform
	player_hand.transform = _p0_hand_transform

	phase_label.text = ""
	game_log.clear()
	_show_setup_dialog()


## ---------------------------------------------------------------------------
## Hand visuals
## ---------------------------------------------------------------------------

## Returns the player_id whose hand should currently be shown in PlayerHand.
## Developer mode follows whoever's turn it is so the operator can drive
## both sides; Player mode stays on player 0 until the CPU/opponent system
## returns.
func _visible_hand_player() -> int:
	if is_developer_mode:
		return manager.current_player
	return 0


func _rebuild_hand_visual(player_id: int) -> void:
	if player_id != _visible_hand_player():
		return

	player_hand.clear_cards()
	for card in _hand_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_hand_cards.clear()

	var hand: Array = manager.game_position.hands[player_id]
	for data in hand:
		var card_node := card_scene.instantiate() as Card
		card_node.set_data(data)
		player_hand.add_card(card_node)
		card_node.drag_started.connect(_on_card_drag_started)
		card_node.card_dropped.connect(_on_card_dropped)
		_hand_cards[data] = card_node


func _on_hand_changed(player_id: int) -> void:
	if player_id == _visible_hand_player():
		_rebuild_hand_visual(player_id)


## ---------------------------------------------------------------------------
## Drag input
## ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	## Block game input while setup dialog is open.
	if _setup_dialog != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		## Any mouse click dismisses an open inspector popup before falling
		## through to drag / right-click handling.
		if mb.pressed and card_zoom_popup != null and card_zoom_popup.visible:
			card_zoom_popup.hide_popup()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_pick_card(mb.position)
			else:
				_try_drop_card()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(mb.position)
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE and card_zoom_popup != null:
			card_zoom_popup.hide_popup()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragged_card != null:
			var world := _screen_to_table(mm.position)
			dragged_card.move_to_drag_position(world)
		else:
			_update_hover(mm.position)


func _try_pick_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null or not card._is_in_hand:
		return  ## Only hand cards are draggable; board/pile cards snap back automatically.
	if card.data == null:
		return
	## Clear any hover lift before the card enters drag mode so the two
	## animations don't fight each other.
	if _hovered_node == card:
		_hovered_node = null
	## All concrete CardData subclasses (PokemonCardData, TrainerCardData,
	## EnergyCardData) are playable from hand — the action-specific validator
	## decides legality when the drop lands.
	dragged_card = card
	card.start_drag()


## Returns the node that should lift when the cursor is over [card].
## Hand cards hover as themselves; board cards (inside a PokemonInstance)
## bubble up to the instance so the nameplate moves too; pile cards
## (deck / discard / prize — parented directly to a DropZone) don't hover
## at all, since there's no meaningful lift for a stacked pile.
func _hover_target_for(card: Card) -> Node3D:
	if card == null:
		return null
	var parent := card.get_parent()
	if parent is PokemonInstance:
		return parent as PokemonInstance
	if parent is DropZone:
		return null
	return card


func _apply_hover(node: Node3D) -> void:
	if node is Card:
		(node as Card).set_hovered(true)
	else:
		var t := node.create_tween()
		t.tween_property(node, "position:y", Card.HOVER_LIFT, Card.TWEEN_SPEED)


func _release_hover() -> void:
	if _hovered_node == null or not is_instance_valid(_hovered_node):
		_hovered_node = null
		return
	if _hovered_node is Card:
		(_hovered_node as Card).set_hovered(false)
	else:
		var t := _hovered_node.create_tween()
		t.tween_property(_hovered_node, "position:y", 0.0, Card.TWEEN_SPEED)
	_hovered_node = null


## Lifts whichever node the cursor is over and returns the previous one.
func _update_hover(screen_pos: Vector2) -> void:
	var target := _hover_target_for(_raycast_card(screen_pos))
	if target == _hovered_node:
		return
	_release_hover()
	_hovered_node = target
	if _hovered_node != null:
		_apply_hover(_hovered_node)


## Shows the zoomed inspector popup for the card under the cursor.  Face-down
## cards and empty pile anchors have no data worth inspecting, so they're
## skipped.
func _handle_right_click(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null or card.face_down or card.data == null:
		return
	if card_zoom_popup == null:
		return
	card_zoom_popup.show_card(card)


func _try_drop_card() -> void:
	if dragged_card == null:
		return
	var card := dragged_card
	dragged_card = null

	if card.data == null:
		card.return_to_home()
		card.end_drag()
		return

	var zone := board.get_slot_zone_at(card.global_position)
	var slot_id := board.slot_id_for_zone(zone) if zone != null else ""

	var action := _build_action_for_drop(card.data, slot_id)
	if action == null:
		card.return_to_home()
		card.end_drag()
		return

	var result: ActionResult = manager.request_action(action)
	## If committed the Card is freed by _rebuild_hand_visual; if rejected we
	## snap it back to its previous position.
	if not result.ok:
		card.return_to_home()
	card.end_drag()


## Builds the Game_Action appropriate to the dragged card's type.  Returns
## null if the drop is meaningless (e.g. a Pokemon / Energy / Tool with no
## target slot).  Items, Supporters and Stadiums do not need a slot — they
## can be dropped anywhere on the table.
func _build_action_for_drop(data: CardData, slot_id: String) -> GameAction:
	var PLAYER_ID: int = manager.current_player
	if data is EnergyCardData:
		if slot_id == "":
			return null
		return ActionAttachEnergy.new(PLAYER_ID, data as EnergyCardData, slot_id)
	if data is TrainerCardData:
		var trainer := data as TrainerCardData
		match trainer.trainer_kind:
			TrainerCardData.TrainerKind.TOOL:
				if slot_id == "":
					return null
				return ActionAttachTool.new(PLAYER_ID, trainer, slot_id)
			TrainerCardData.TrainerKind.ITEM:
				return ActionPlayItem.new(PLAYER_ID, trainer)
			TrainerCardData.TrainerKind.SUPPORTER:
				return ActionPlaySupporter.new(PLAYER_ID, trainer)
			TrainerCardData.TrainerKind.STADIUM:
				return ActionPlayStadium.new(PLAYER_ID, trainer)
		return null
	if data is PokemonCardData:
		if slot_id == "":
			return null
		var pokemon := data as PokemonCardData
		if pokemon.stage == PokemonCardData.Stage.BASIC:
			return ActionPlayPokemon.new(PLAYER_ID, pokemon, slot_id)
		return ActionEvolve.new(PLAYER_ID, pokemon, slot_id)
	return null


func _on_card_drag_started(_card: Card) -> void:
	pass


func _on_card_dropped(_card: Card) -> void:
	pass


func _raycast_card(screen_pos: Vector2) -> Card:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var body := hit.collider as Node
	if body == null:
		return null
	var parent := body.get_parent()
	return parent as Card


func _screen_to_table(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	var hit: Variant = DRAG_PLANE.intersects_ray(from, dir)
	if hit == null:
		return from
	return hit as Vector3


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


## ---------------------------------------------------------------------------
## Turn / phase
## ---------------------------------------------------------------------------

func _on_end_turn_pressed() -> void:
	manager.end_turn()


func _on_turn_started(pid: int, _turn_num: int) -> void:
	if is_developer_mode:
		_apply_perspective(pid)
	_rebuild_hand_visual(pid)
	_update_phase_label()


## --- Developer-mode perspective flip ---------------------------------------

## Y rotation in radians that in-play cards should use from the controlling
## player's perspective.  P0 reads natively; P1 reads upside-down unless we
## flip the cards 180° around Y.
func _board_rotation_y() -> float:
	return 0.0 if _controlling_player == 0 else PI


## Flips the camera, player hand anchor, and every in-play PokemonInstance
## to the [pid] side of the table.  Prizes, deck, and discard piles are left
## alone — they're face-down stacks whose orientation doesn't matter.
func _apply_perspective(pid: int) -> void:
	if pid == _controlling_player:
		return
	_controlling_player = pid
	camera.transform = _p0_cam_transform if pid == 0 else _p1_cam_transform
	player_hand.transform = _p0_hand_transform if pid == 0 else _p1_hand_transform

	var y_rot := _board_rotation_y()
	for sid in BoardPosition.all_slot_ids():
		var inst := manager.board_position.get_instance(sid)
		if inst != null:
			inst.rotation.y = y_rot


func _on_turn_ended(_pid: int) -> void:
	_update_phase_label()


func _on_phase_changed(_phase: int) -> void:
	_update_phase_label()


func _update_phase_label() -> void:
	var mode := "Developer" if is_developer_mode else "Player"
	phase_label.text = "%s  |  P%d  |  Turn %d  |  %s" % [
		mode, manager.current_player, manager.turn_number, manager.phase_name(),
	]


func _on_deck_changed(pid: int) -> void:
	_refresh_deck_visual(pid)


func _on_discard_changed(pid: int) -> void:
	_refresh_discard_visual(pid)


func _on_prizes_changed(pid: int) -> void:
	_refresh_prizes_visual(pid)


## ---------------------------------------------------------------------------
## Pile visuals (deck / discard / prizes)
## ---------------------------------------------------------------------------

func _zone_prefix(pid: int) -> String:
	return "" if pid == 0 else "Opp "


## Deck stack visualisation — cap how many face-down layers we draw and how
## thick each layer is so the shrinking pile stays legible without spawning
## a Card node per real card.
const DECK_MAX_LAYERS: int = 12
const DECK_LAYER_THICKNESS: float = 0.018
const DECK_FULL_SIZE: int = 60


func _refresh_deck_visual(pid: int) -> void:
	var zone_name := "%sDeck" % _zone_prefix(pid)
	var zone := board.get_named_zone(zone_name)
	if zone == null:
		return
	var count: int = (manager.game_position.decks[pid] as Array).size()

	## Drop any previously built stack so we rebuild from scratch.
	var layers: Array = _pile_nodes.get(zone_name, []) as Array
	for old_layer in layers:
		if is_instance_valid(old_layer):
			(old_layer as Node).queue_free()
	layers.clear()

	if count == 0:
		_pile_nodes.erase(zone_name)
		zone.set_label("Deck (0)")
		return

	var layer_count: int = clampi(
		ceili(float(count) / float(DECK_FULL_SIZE) * DECK_MAX_LAYERS),
		1, DECK_MAX_LAYERS
	)
	for i in range(layer_count):
		var layer_node := card_scene.instantiate() as Card
		zone.add_child(layer_node)
		layer_node.position = Vector3(0, i * DECK_LAYER_THICKNESS, 0)
		layer_node.back_texture = CARD_BACK
		layer_node.face_down = true
		layers.append(layer_node)
	_pile_nodes[zone_name] = layers
	zone.set_label("Deck (%d)" % count)


func _refresh_discard_visual(pid: int) -> void:
	var zone_name := "%sDiscard" % _zone_prefix(pid)
	var zone := board.get_named_zone(zone_name)
	if zone == null:
		return
	var discard: Array = manager.game_position.discards[pid]
	var node := _pile_nodes.get(zone_name, null) as Card
	if discard.is_empty():
		if node != null:
			node.queue_free()
			_pile_nodes.erase(zone_name)
		zone.set_label("Discard (0)")
		return
	if node == null:
		node = card_scene.instantiate() as Card
		zone.add_child(node)
		node.position = Vector3.ZERO
		_pile_nodes[zone_name] = node
	node.face_down = false
	node.set_data(discard.back() as CardData)
	zone.set_label("Discard (%d)" % discard.size())


func _refresh_prizes_visual(pid: int) -> void:
	var prefix := _zone_prefix(pid)
	var prize_row: Array = manager.game_position.prizes[pid]
	for i in range(6):
		var zone_name := "%sPrize %d" % [prefix, i + 1]
		var zone := board.get_named_zone(zone_name)
		if zone == null or not zone.visible:
			continue
		var node := _pile_nodes.get(zone_name, null) as Card
		var occupied: bool = (prize_row[i] != null)
		if not occupied:
			if node != null:
				node.queue_free()
				_pile_nodes.erase(zone_name)
		else:
			if node == null:
				node = card_scene.instantiate() as Card
				zone.add_child(node)
				node.position = Vector3.ZERO
				## Opponent prizes face the opposite side of the table.
				if pid == 1:
					node.rotation.y = PI
				node.back_texture = CARD_BACK
				node.face_down = true
				_pile_nodes[zone_name] = node


func _log(text: String) -> void:
	game_log.append_text(text + "\n")
