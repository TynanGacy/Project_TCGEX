extends Node3D
## Minimal bare-bones main scene.
##
## Startup flow:
##   _ready() -> _show_setup_dialog() -> _on_setup_confirmed() -> _start_game()
##
## Setup collects: mode (developer / player), prize count (2-6), active slot
## count (1-2), bench slot count (3-5), and per-player deck selection.  Both
## modes currently behave the same because CPU / turn-flow was removed by the
## four-system refactor; the mode flag is retained so it can drive future
## CPU / perspective-flip features without re-plumbing the dialog.
##
## Wires the four systems (PokemonInstance / BoardPosition / GamePosition /
## ManagerSystem) together for a single user flow: drag a Basic Pokemon
## card out of the hand onto an Active or Bench slot, and the Manager
## validates + dispatches the ActionPlayPokemon.

@onready var camera: Camera3D = $Camera3D
@onready var board:  Board    = $Board
@onready var player_hand: Hand = $Board/PlayerHand

@onready var phase_label: Label = $HUD/TopBar/PhaseLabel
@onready var end_turn_button: Button = $HUD/TopBar/EndTurnButton
@onready var game_log: RichTextLabel = $HUD/LogPanel/GameLog

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

## --- Setup state ------------------------------------------------------------
var is_developer_mode: bool = false
var _prize_count:      int  = 6
var _active_slots:     int  = 1
var _bench_slots:      int  = 5
var _player_deck_path:   String = ""
var _opponent_deck_path: String = ""

var _setup_dialog: Control = null
var _setup_selected_mode: String = ""


func _ready() -> void:
	phase_label.text = ""
	end_turn_button.text = "Reset"
	end_turn_button.pressed.connect(_reset_game)

	manager.action_committed.connect(_on_action_committed)
	manager.action_rejected.connect(_on_action_rejected)
	manager.log_message.connect(_log)
	manager.hand_changed.connect(_on_hand_changed)
	manager.board_slot_changed.connect(_on_board_slot_changed)
	manager.overflow_escalation.connect(_on_overflow_escalation)
	manager.deck_changed.connect(_on_deck_changed)
	manager.discard_changed.connect(_on_discard_changed)
	manager.prizes_changed.connect(_on_prizes_changed)

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

	_rebuild_hand_visual(0)
	phase_label.text = "%s mode  |  %d prize cards" % [
		"Developer" if is_developer_mode else "Player",
		_prize_count,
	]


func _reset_game() -> void:
	## Clear pile visuals.
	for node in _pile_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
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

	game_log.clear()
	_show_setup_dialog()


## ---------------------------------------------------------------------------
## Hand visuals
## ---------------------------------------------------------------------------

func _rebuild_hand_visual(player_id: int) -> void:
	if player_id != 0:
		return  ## Only player 0 hand is rendered in bare-bones mode.

	player_hand.clear_cards()
	for card in _hand_cards.values():
		if is_instance_valid(card):
			card.queue_free()
	_hand_cards.clear()

	var hand: Array = manager.game_position.hands[0]
	for data in hand:
		var card_node := card_scene.instantiate() as Card
		card_node.set_data(data)
		player_hand.add_card(card_node)
		card_node.drag_started.connect(_on_card_drag_started)
		card_node.card_dropped.connect(_on_card_dropped)
		_hand_cards[data] = card_node


func _on_hand_changed(player_id: int) -> void:
	if player_id == 0:
		_rebuild_hand_visual(0)


## ---------------------------------------------------------------------------
## Drag input
## ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	## Block game input while setup dialog is open.
	if _setup_dialog != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_try_pick_card(mb.position)
			else:
				_try_drop_card()
	elif event is InputEventMouseMotion and dragged_card != null:
		var world := _screen_to_table((event as InputEventMouseMotion).position)
		dragged_card.move_to_drag_position(world)


func _try_pick_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null or not card._is_in_hand:
		return  ## Only hand cards are draggable; board/pile cards snap back automatically.
	if card.data == null or not (card.data is PokemonCardData):
		return
	if (card.data as PokemonCardData).stage != PokemonCardData.Stage.BASIC:
		return
	dragged_card = card
	card.start_drag()


func _try_drop_card() -> void:
	if dragged_card == null:
		return
	var card := dragged_card
	dragged_card = null

	var zone := board.get_slot_zone_at(card.global_position)
	var slot_id := board.slot_id_for_zone(zone) if zone != null else ""

	if slot_id == "" or card.data == null or not (card.data is PokemonCardData):
		card.return_to_home()
		card.end_drag()
		return

	var action := ActionPlayPokemon.new(0, card.data as PokemonCardData, slot_id)
	var result: ActionResult = manager.request_action(action)
	## If committed the Card is freed by _rebuild_hand_visual; if rejected we
	## snap it back to its previous position.
	if not result.ok:
		card.return_to_home()
	card.end_drag()


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
	return hit as Vector3 if hit != null else from


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


func _on_board_slot_changed(_slot_id: String, _instance) -> void:
	pass  ## BoardPosition places the PokemonInstance visual itself.


func _on_overflow_escalation(player_id: int, _instance) -> void:
	_log("[Overflow] P%d has no empty bench — manual resolution required." % player_id)


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


func _refresh_deck_visual(pid: int) -> void:
	var zone_name := "%sDeck" % _zone_prefix(pid)
	var zone := board.get_named_zone(zone_name)
	if zone == null:
		return
	var count: int = (manager.game_position.decks[pid] as Array).size()
	var node := _pile_nodes.get(zone_name, null) as Card
	if count == 0:
		if node != null:
			node.queue_free()
			_pile_nodes.erase(zone_name)
		zone.set_label("Deck (0)")
		return
	if node == null:
		node = card_scene.instantiate() as Card
		zone.add_child(node)
		node.position = Vector3.ZERO
		node.back_texture = CARD_BACK
		node.face_down = true
		_pile_nodes[zone_name] = node
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
				node.back_texture = CARD_BACK
				node.face_down = true
				_pile_nodes[zone_name] = node


func _log(text: String) -> void:
	game_log.append_text(text + "\n")
