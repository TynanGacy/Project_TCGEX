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

## Per-player CardData → Card node cache.  Index 0 = player 0, 1 = player 1.
## Both players' hands are tracked symmetrically; face-up vs face-down is a
## rendering decision, not a structural one.
var _hand_cards: Array = [{}, {}]
var _opponent_hand: Hand = null

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

## True while the pre-game setup sequence (mulligans / coin flip) is running.
## Blocks drag input so cards can't be moved before the game starts.
var _in_setup_phase: bool = false

## True while a player is in the "place starting Pokémon" step.  The End Turn
## button is relabelled "Ready" and guarded against calling end_turn().
var _in_placement_phase: bool = false

## Used by choice dialogs during the setup sequence to relay a yes/no answer.
signal _setup_choice_made(chose_yes: bool)


## Programmatically-added Reset button lives next to the End-Turn button
## in the TopBar.
var _reset_button:  Button = null
var _attack_button: Button = null
var _retreat_button: Button = null

## Active attack/retreat/prize/promotion dialog (at most one open at a time).
var _attack_dialog: Control = null

## Deferred end-of-turn: set when an attack commits; cleared after prize
## selection and promotion both resolve so we don't end the turn too early.
var _attack_end_turn_pending: bool = false

## Setup-phase board drag.  During placement, Basic Pokémon can be dragged
## between active, bench, and hand.  Only one instance is dragged at a time.
var _setup_dragged_instance: PokemonInstance = null
var _setup_dragged_from_slot: String = ""


func _ready() -> void:
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
	_authority.turn_started.connect(_on_turn_started)
	_authority.turn_ended.connect(_on_turn_ended)
	_authority.phase_changed.connect(_on_phase_changed)
	_authority.pokemon_knocked_out.connect(_on_pokemon_knocked_out)
	_authority.prize_taken.connect(_on_prize_taken)
	_authority.prize_selection_required.connect(_on_prize_selection_required)
	_authority.promotion_required.connect(_on_promotion_required)
	_authority.promotion_done.connect(_on_promotion_done)
	_authority.game_won.connect(_on_game_won)

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
	_in_setup_phase = true
	board.configure_slots(_active_slots, _bench_slots, _prize_count)

	_opponent_hand = _HAND_SCENE.instantiate() as Hand
	_opponent_hand.name = "OpponentHand"
	board.add_child(_opponent_hand)
	_opponent_hand.transform = _p1_hand_transform

	var p0_deck: Array[CardData] = DeckLoader.load_deck(0, _player_deck_path)
	var p1_deck: Array[CardData] = DeckLoader.load_deck(1, _opponent_deck_path)
	_authority.load_deck(0, p0_deck)
	_authority.load_deck(1, p1_deck)

	## Both players draw 7 before the coin flip (RS-PK setup rule).
	_authority.draw_starting_hand(0, 7)
	_authority.draw_starting_hand(1, 7)

	## Prizes are dealt after the mulligan phase so a deck with few basics
	## cannot softlock by prizing all of them before the hand is drawn.

	## Run mulligan loop, placement, then coin flip; begin_game() is called at the end.
	_run_setup_sequence()


## ---------------------------------------------------------------------------
## Setup sequence (mulligans + coin flip)
## ---------------------------------------------------------------------------

## Async coroutine that drives the full RS-PK pre-game setup:
##   1. Mulligan loop until both players have at least one Basic in hand.
##   2. Prize cards dealt (after mulligans so basics can't be prized out).
##   3. Each player places their starting Pokémon (active required, bench optional).
##      Opponent's side is hidden while the other player places.
##   4. Coin flip — winner must go first; first-turn restrictions apply to them.
##   5. Call begin_game() with the starting player.
func _run_setup_sequence() -> void:
	var mulligan_counts: Array[int] = [0, 0]

	while true:
		var p0_ok := _authority.has_basic_in_hand(0)
		var p1_ok := _authority.has_basic_in_hand(1)
		if p0_ok and p1_ok:
			break

		## Both have no basics — both mulligan simultaneously, no bonus draws.
		if not p0_ok and not p1_ok:
			mulligan_counts[0] += 1
			mulligan_counts[1] += 1
			_log("[Setup] Both players have no Basic Pokémon — both take a mulligan.")
			_authority.return_hand_to_deck(0)
			_authority.return_hand_to_deck(1)
			_authority.draw_starting_hand(0, 7)
			_authority.draw_starting_hand(1, 7)
			await _show_setup_info(
				"Both players had no Basic Pokémon.\nBoth shuffled and drew 7 new cards."
			)
			continue

		## Exactly one player has no basics — they mulligan; opponent may draw.
		var mulligan_pid: int = 0 if not p0_ok else 1
		var other_pid:    int = 1 - mulligan_pid
		mulligan_counts[mulligan_pid] += 1
		_log("[Setup] P%d has no Basic Pokémon — taking mulligan #%d." \
				% [mulligan_pid, mulligan_counts[mulligan_pid]])
		_authority.return_hand_to_deck(mulligan_pid)
		_authority.draw_starting_hand(mulligan_pid, 7)

		await _show_setup_info(
			"Player %d had no Basic Pokémon\nand took mulligan #%d.\nThey shuffled and drew 7 new cards." \
			% [mulligan_pid, mulligan_counts[mulligan_pid]]
		)

		## Opponent decides whether to draw a bonus card for this mulligan.
		var wants_draw: bool = await _show_mulligan_card_offer(other_pid)
		if wants_draw:
			_authority.draw_one(other_pid)
			_log("[Setup] P%d draws an extra card (mulligan bonus)." % other_pid)

	## Prizes are dealt after the mulligan phase (RS-PK rule).
	_authority.deal_prizes(0, _prize_count)
	_authority.deal_prizes(1, _prize_count)
	_log("[Setup] Prize cards dealt.")

	## Placement phase — each player places their starting Pokémon in turn.
	## The other player's side is hidden while they place.
	for placing_pid: int in [0, 1]:
		_authority.begin_setup_placement(placing_pid)
		_apply_perspective(placing_pid)
		## Rebuild both hands so the placing player's cards are face-up and
		## the waiting player's cards are face-down from this perspective.
		_rebuild_hand_visual(0)
		_rebuild_hand_visual(1)
		_in_setup_phase = false   ## allow drag input during placement
		await _show_placement_phase(placing_pid)
		_in_setup_phase = true    ## block drag again between phases
		_authority.end_setup_placement()
		_log("[Setup] P%d finished placing starting Pokémon." % placing_pid)

	## Both players have set up — flip to decide who goes first.
	var flip_result:    int = randi() % 2  ## 0 = Heads → P0 first, 1 = Tails → P1 first
	var starting_player: int = flip_result
	_log("[Setup] Coin flip: %s — P%d goes first." \
			% ["Heads" if flip_result == 0 else "Tails", starting_player])

	await _show_coin_flip_result(starting_player, flip_result)

	_in_setup_phase = false
	## _on_turn_started handles the hand rebuild and phase label.
	_authority.begin_game(starting_player)


## ---------------------------------------------------------------------------
## Setup-phase dialog helpers
## ---------------------------------------------------------------------------

## Builds a centred modal panel and returns it with an empty VBoxContainer
## child ready for content.  Caller adds to $HUD.
func _make_setup_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 120)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.97)
	style.corner_radius_top_left     = 8
	style.corner_radius_top_right    = 8
	style.corner_radius_bottom_left  = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	return panel


## True if [pid]'s board satisfies both Ready conditions:
##   1. At least one active slot has a Pokémon.
##   2. No empty active slot exists alongside any bench Pokémon
##      (i.e. if the bench is occupied, all active slots must be filled).
func _is_placement_ready(pid: int) -> bool:
	var has_active := false
	for i in range(1, _active_slots + 1):
		if manager.board_position.get_instance("p%d_active%d" % [pid, i]) != null:
			has_active = true
			break
	if not has_active:
		return false
	var has_bench := false
	for i in range(1, _bench_slots + 1):
		if manager.board_position.get_instance("p%d_bench%d" % [pid, i]) != null:
			has_bench = true
			break
	if not has_bench:
		return true  ## No bench Pokémon → condition 2 is trivially satisfied.
	## Bench is occupied — every active slot must also be filled.
	for i in range(1, _active_slots + 1):
		if manager.board_position.get_instance("p%d_active%d" % [pid, i]) == null:
			return false
	return true


## Placement phase for [placing_pid]: repurposes the End Turn button as
## "Ready", enables it only once both placement conditions are met, and
## awaits the press.
func _show_placement_phase(placing_pid: int) -> void:
	_in_placement_phase      = true
	end_turn_button.text     = "Ready"
	end_turn_button.disabled = not _is_placement_ready(placing_pid)
	_update_phase_label()

	var refresh := func(_sid: String, _inst: PokemonInstance) -> void:
		end_turn_button.disabled = not _is_placement_ready(placing_pid)
	_authority.board_slot_changed.connect(refresh)

	await end_turn_button.pressed
	_authority.board_slot_changed.disconnect(refresh)

	end_turn_button.text     = "End Turn"
	end_turn_button.disabled = false
	_in_placement_phase      = false


## Shows an informational panel with a "Continue" button and awaits it.
func _show_setup_info(message: String) -> void:
	var panel := _make_setup_panel()
	var vbox := panel.get_child(0) as VBoxContainer
	var lbl := Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var btn := Button.new()
	btn.text = "Continue"
	vbox.add_child(btn)
	$HUD.add_child(panel)
	await btn.pressed
	panel.queue_free()


## Asks [offer_pid] whether they want a bonus mulligan draw card.
## Returns true if they click "Yes".
func _show_mulligan_card_offer(offer_pid: int) -> bool:
	var panel := _make_setup_panel()
	var vbox := panel.get_child(0) as VBoxContainer
	var lbl := Label.new()
	lbl.text = "Player %d: Draw a bonus card\nfor your opponent's mulligan?" % offer_pid
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)
	var yes_btn := Button.new()
	yes_btn.text = "Yes"
	var no_btn := Button.new()
	no_btn.text  = "No"
	row.add_child(yes_btn)
	row.add_child(no_btn)
	yes_btn.pressed.connect(func() -> void: _setup_choice_made.emit(true))
	no_btn.pressed.connect(func() -> void:  _setup_choice_made.emit(false))
	$HUD.add_child(panel)
	var result: bool = await _setup_choice_made
	panel.queue_free()
	return result


## Shows the coin-flip outcome and first-turn restriction note, then awaits
## the "Begin Game" button.
func _show_coin_flip_result(starting_player: int, flip_result: int) -> void:
	var panel := _make_setup_panel()
	var vbox := panel.get_child(0) as VBoxContainer

	var flip_lbl := Label.new()
	flip_lbl.text = "%s!" % ("Heads" if flip_result == 0 else "Tails")
	flip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flip_lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(flip_lbl)

	var result_lbl := Label.new()
	result_lbl.text = "Player %d goes first." % starting_player
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(result_lbl)

	var note_lbl := Label.new()
	note_lbl.text = "First-turn restrictions: no draw, no Supporters."
	note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.5))
	vbox.add_child(note_lbl)

	var btn := Button.new()
	btn.text = "Begin Game"
	vbox.add_child(btn)
	$HUD.add_child(panel)
	await btn.pressed
	panel.queue_free()


func _reset_game() -> void:
	_in_setup_phase = false
	_attack_end_turn_pending = false
	if _setup_dragged_instance != null:
		_setup_dragged_instance.queue_free()
		_setup_dragged_instance = null
	_setup_dragged_from_slot = ""
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
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

	## Clear hand visuals for both players.
	player_hand.clear_cards()
	for pid in range(2):
		for card in (_hand_cards[pid] as Dictionary).values():
			if is_instance_valid(card):
				(card as Card).queue_free()
	_hand_cards = [{}, {}]

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

	phase_label.text = ""
	game_log.clear()
	_show_setup_dialog()


## ---------------------------------------------------------------------------
## Hand visuals
## ---------------------------------------------------------------------------

## Returns the Hand scene node that physically represents [pid]'s hand on the
## table.  P0's node is fixed at P0's side; P1's at P1's side.  The camera
## flip in _apply_perspective makes whichever side is "near" depend on who is
## controlling, without moving the hand nodes themselves.
func _hand_node(pid: int) -> Hand:
	return player_hand if pid == 0 else _opponent_hand


## Full rebuild of [player_id]'s hand visual from scratch.
## In developer mode every card is face-up and draggable.
## In player mode P1's cards are rendered face-down (CPU placeholder).
func _rebuild_hand_visual(player_id: int) -> void:
	if _hand_node(player_id) == null:
		return
	_hand_node(player_id).clear_cards()
	for card in (_hand_cards[player_id] as Dictionary).values():
		if is_instance_valid(card):
			(card as Card).queue_free()
	(_hand_cards[player_id] as Dictionary).clear()

	var face_up: bool = (player_id == _authority.current_player_id())
	var hand: Array = manager.game_position.hands[player_id]
	for data in hand:
		var card_node := card_scene.instantiate() as Card
		if face_up:
			card_node.set_data(data)
			card_node.drag_started.connect(_on_card_drag_started)
			card_node.card_dropped.connect(_on_card_dropped)
		else:
			card_node.back_texture = CARD_BACK
			card_node.face_down    = true
		_hand_node(player_id).add_card(card_node)
		(_hand_cards[player_id] as Dictionary)[data] = card_node


## Adds any cards in [player_id]'s hand that are not yet tracked.
## Removals are handled exclusively by _on_card_left_hand so the fan slides
## smoothly without a full rebuild whenever the hand shrinks.
func _sync_new_hand_cards(player_id: int) -> void:
	if _hand_node(player_id) == null:
		return
	var face_up: bool = (player_id == _authority.current_player_id())
	var dict: Dictionary = _hand_cards[player_id]
	for data: CardData in manager.game_position.hands[player_id]:
		if not dict.has(data):
			var card_node := card_scene.instantiate() as Card
			if face_up:
				card_node.set_data(data)
				card_node.drag_started.connect(_on_card_drag_started)
				card_node.card_dropped.connect(_on_card_dropped)
			else:
				card_node.back_texture = CARD_BACK
				card_node.face_down    = true
			_hand_node(player_id).add_card(card_node)
			dict[data] = card_node


## Removes the exact card that just left [player_id]'s hand.  O(1) lookup via
## the CardData key; works identically for both players.
func _on_card_left_hand(player_id: int, card: CardData) -> void:
	if _hand_node(player_id) == null:
		return
	var dict: Dictionary = _hand_cards[player_id]
	if not dict.has(card):
		return
	var card_node: Card = dict[card]
	dict.erase(card)
	_hand_node(player_id).remove_card(card_node)
	card_node.queue_free()


func _on_hand_changed(player_id: int) -> void:
	_sync_new_hand_cards(player_id)


## ---------------------------------------------------------------------------
## Drag input
## ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	## Block game input while setup dialog or setup sequence is active.
	if _setup_dialog != null or _in_setup_phase:
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
				if _setup_dragged_instance != null:
					_try_drop_setup_drag()
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
		elif _setup_dragged_instance != null:
			var world := _screen_to_table(mm.position)
			_setup_dragged_instance.global_position = Vector3(world.x, Card.HOVER_LIFT * 2.0, world.z)
		else:
			_update_hover(mm.position)


func _try_pick_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null:
		return
	if not card._is_in_hand:
		## During setup placement, Basic Pokémon already on the board can be
		## freely repositioned — pick them up as a setup drag.
		if manager.setup_placing_player >= 0:
			_try_pick_setup_instance(card)
			return
		## During prize selection the player clicks a prize card on the board.
		if manager.prize_selection_phase_for >= 0:
			_try_pick_prize_card(card)
		return  ## Otherwise board/pile cards are not draggable.
	## Face-down cards belong to the opponent in player mode and are never
	## directly interactive.  In developer mode all cards are face-up.
	if card.face_down or card.data == null:
		return
	## Only the current player's cards can be picked up.
	var card_owner: int = 0 if card.get_parent() == player_hand else 1
	if card_owner != _authority.current_player_id():
		return
	## Clear any hover lift before the card enters drag mode so the two
	## animations don't fight each other.
	if _hovered_node == card:
		_hovered_node = null
	dragged_card = card
	card.start_drag()


## During prize selection, claims the prize card that was clicked on the board.
## Prize zone names are "Prize 1"–"Prize N" (player 0) or "Opp Prize 1"–"Opp Prize N" (player 1).
func _try_pick_prize_card(card: Card) -> void:
	var pid := manager.prize_selection_phase_for
	var prefix := _zone_prefix(pid)
	var parent := card.get_parent()
	if not (parent is DropZone):
		return
	var zone := parent as DropZone
	for i in range(1, _prize_count + 1):
		if zone.zone_name == "%sPrize %d" % [prefix, i]:
			var action := ActionTakePrize.new(pid, i - 1)
			_authority.request_action(action)
			return


## During setup, lifts a board Pokémon so it can be repositioned or returned
## to hand.  Only Basic Pokémon are movable (evolved Pokémon stay put).
func _try_pick_setup_instance(card: Card) -> void:
	if card.face_down or card.data == null:
		return
	## Only Basic Pokémon may be freely repositioned.
	if not (card.data is PokemonCardData) \
			or (card.data as PokemonCardData).stage != PokemonCardData.Stage.BASIC:
		return
	var inst := card.get_parent() as PokemonInstance
	if inst == null or inst.owner_id != manager.setup_placing_player:
		return
	## Locate the source slot.
	var pid: int = manager.setup_placing_player
	for sid: String in BoardPosition.all_slot_ids(pid):
		if manager.board_position.get_instance(sid) == inst:
			_setup_dragged_from_slot = sid
			break
	if _setup_dragged_from_slot == "":
		return
	## Release any hover state, then reparent the instance to the board node
	## so it can be moved freely in world space.
	if _hovered_node == inst:
		_release_hover()
	var world_pos := inst.global_position
	if inst.get_parent() != null:
		inst.get_parent().remove_child(inst)
	board.add_child(inst)
	inst.global_position = Vector3(world_pos.x, Card.HOVER_LIFT * 2.0, world_pos.z)
	_setup_dragged_instance = inst


## Resolves a setup-phase board drag on mouse-up.
## – Dropped on same slot or off-board but near original → snap back.
## – Dropped off-board (no zone) → return Pokémon to hand.
## – Dropped on another slot belonging to this player → move or swap.
## – Dropped on opponent's slot or out-of-range → snap back.
func _try_drop_setup_drag() -> void:
	var inst      := _setup_dragged_instance
	var from_slot := _setup_dragged_from_slot
	_setup_dragged_instance = null
	_setup_dragged_from_slot = ""
	var pid: int = manager.setup_placing_player

	var zone     := board.get_slot_zone_at(inst.global_position)
	var to_slot  := board.slot_id_for_zone(zone) if zone != null else ""

	if to_slot == from_slot:
		## Dropped back on the origin → snap back.
		manager.board_position.place(from_slot, inst)
		return

	if to_slot == "":
		## Dropped off all zones → return to hand.
		manager.board_position.clear(from_slot)
		var released: Array[CardData] = inst.release_cards()
		for c: CardData in released:
			manager.game_position.put_in_hand(pid, c)
		inst.queue_free()
		return

	if manager.board_position.player_of(to_slot) != pid:
		## Opponent's slot → snap back.
		manager.board_position.place(from_slot, inst)
		return

	## Same player's slot: move (if empty) or swap (if occupied).
	if manager.board_position.get_instance(to_slot) == null:
		manager.board_position.move(from_slot, to_slot)
	else:
		manager.board_position.swap(from_slot, to_slot)


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
	var instance: PokemonInstance = null
	if card.get_parent() is PokemonInstance:
		instance = card.get_parent() as PokemonInstance
	card_zoom_popup.show_card(card, instance)


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

	var result: ActionResult = _authority.request_action(action)
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
	var PLAYER_ID: int = _authority.current_player_id()

	## During the setup placement phase only Basics may be placed, using the
	## setup-specific action that skips the main-phase requirement.
	if manager.setup_placing_player >= 0:
		if data is PokemonCardData and slot_id != "":
			var p := data as PokemonCardData
			if p.stage == PokemonCardData.Stage.BASIC:
				return ActionSetupPlayBasic.new(PLAYER_ID, p, slot_id)
		return null

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
	if _in_placement_phase:
		return  ## Button is acting as "Ready" — handled by _show_placement_phase.
	_authority.end_turn()


func _on_turn_started(pid: int, _turn_num: int) -> void:
	if is_developer_mode:
		_apply_perspective(pid)
	_rebuild_hand_visual(0)
	_rebuild_hand_visual(1)
	_update_phase_label()


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
		if pid == 1:
			node.rotation.y = PI
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


## ---------------------------------------------------------------------------
## Attack UI
## ---------------------------------------------------------------------------

func _on_attack_pressed() -> void:
	if _setup_dialog != null or _in_setup_phase:
		return
	## Toggle the dialog if it is already open.
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
		return
	_show_attack_dialog()


func _show_attack_dialog() -> void:
	var pid := _authority.current_player_id()

	## Collect opponent active slots that have a Pokémon.
	var opp_id := 1 - pid
	var opp_actives: Array[String] = []
	for i in range(1, _active_slots + 1):
		var sid := "p%d_active%d" % [opp_id, i]
		if manager.board_position.get_instance(sid) != null:
			opp_actives.append(sid)

	if opp_actives.is_empty():
		_log("[Attack] No opponent active Pokémon to attack.")
		return

	## Build list of available (attacker_slot, attack_index) entries.
	var entries: Array = []
	for i in range(1, _active_slots + 1):
		var sid := "p%d_active%d" % [pid, i]
		var inst: PokemonInstance = manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			continue
		if inst.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP) \
				or inst.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED):
			continue
		for j in range(inst.card.attacks.size()):
			entries.append({
				"slot":   sid,
				"idx":    j,
				"attack": inst.card.attacks[j],
				"can":    ActionAttack._check_energy(inst, inst.card.attacks[j]).ok,
				"inst":   inst,
			})

	if entries.is_empty():
		_log("[Attack] No attacks available this turn.")
		return

	var panel := _make_setup_panel()
	panel.custom_minimum_size = Vector2(400, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Choose an Attack"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for entry: Dictionary in entries:
		var atk: AttackData       = entry["attack"]
		var can: bool             = entry["can"]
		var inst: PokemonInstance = entry["inst"]
		var slot: String          = entry["slot"]
		var idx: int              = entry["idx"]

		var cost_str := _format_attack_cost(atk)
		var dmg_str  := ("%d dmg" % atk.base_damage) if atk.base_damage > 0 else "no dmg"
		var btn := Button.new()
		btn.text     = "%s  %s %s  %s" % [inst.card.display_name, atk.name, cost_str, dmg_str]
		btn.disabled = not can
		if not can:
			btn.modulate = Color(0.55, 0.55, 0.55)

		var fn: Callable = func(s: String, i: int) -> void:
			panel.queue_free()
			_attack_dialog = null
			_pick_target_then_attack(pid, s, i, opp_actives)
		btn.pressed.connect(fn.bind(slot, idx))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
	)
	vbox.add_child(cancel)

	$HUD.add_child(panel)
	_attack_dialog = panel


## If there is exactly one opponent active the attack is unambiguous.
## Otherwise show a second dialog for target selection.
func _pick_target_then_attack(pid: int, atk_slot: String, atk_idx: int, opp_actives: Array[String]) -> void:
	if opp_actives.size() == 1:
		_submit_attack(pid, atk_slot, atk_idx, opp_actives[0])
		return

	var panel := _make_setup_panel()
	panel.custom_minimum_size = Vector2(380, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Choose a Target"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for tgt_slot: String in opp_actives:
		var inst: PokemonInstance = manager.board_position.get_instance(tgt_slot)
		var name := inst.card.display_name if (inst != null and inst.card != null) else tgt_slot
		var hp_str := " (%d/%d HP)" % [inst.current_hp, inst.max_hp] if inst != null else ""
		var btn := Button.new()
		btn.text = "%s%s" % [name, hp_str]
		var fn: Callable = func(ts: String) -> void:
			panel.queue_free()
			_attack_dialog = null
			_submit_attack(pid, atk_slot, atk_idx, ts)
		btn.pressed.connect(fn.bind(tgt_slot))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
	)
	vbox.add_child(cancel)

	$HUD.add_child(panel)
	_attack_dialog = panel


func _submit_attack(pid: int, atk_slot: String, atk_idx: int, tgt_slot: String) -> void:
	var action := ActionAttack.new(pid, atk_slot, atk_idx, tgt_slot)
	var result := _authority.request_action(action)
	if result.ok:
		_attack_end_turn_pending = true
		_try_end_turn_after_attack()


## Ends the attacker's turn only once prize selection and promotion are both
## fully resolved so the turn doesn't advance mid-interaction.
func _try_end_turn_after_attack() -> void:
	if not _attack_end_turn_pending:
		return
	if manager.prize_selection_phase_for >= 0:
		return
	if manager.promotion_phase_for >= 0:
		return
	_attack_end_turn_pending = false
	_authority.end_turn()


## Returns a bracketed string of single-letter energy symbols for [atk]'s cost.
func _format_attack_cost(atk: AttackData) -> String:
	var parts: Array[String] = []
	for _i in range(atk.cost_fire):      parts.append("R")
	for _i in range(atk.cost_water):     parts.append("W")
	for _i in range(atk.cost_grass):     parts.append("G")
	for _i in range(atk.cost_lightning): parts.append("L")
	for _i in range(atk.cost_psychic):   parts.append("P")
	for _i in range(atk.cost_fighting):  parts.append("F")
	for _i in range(atk.cost_darkness):  parts.append("D")
	for _i in range(atk.cost_metal):     parts.append("M")
	for _i in range(atk.cost_colorless): parts.append("C")
	if parts.is_empty():
		return "[–]"
	return "[%s]" % "".join(parts)


## ---------------------------------------------------------------------------
## Retreat UI
## ---------------------------------------------------------------------------

func _on_retreat_pressed() -> void:
	if _setup_dialog != null or _in_setup_phase:
		return
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
		return
	_show_retreat_dialog()


func _show_retreat_dialog() -> void:
	var pid := _authority.current_player_id()

	## Collect active Pokémon that can afford to retreat.
	var retreatable: Array = []
	for i in range(1, _active_slots + 1):
		var sid := "p%d_active%d" % [pid, i]
		var inst: PokemonInstance = manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			continue
		if inst.attached_energy.size() >= inst.card.retreat_cost:
			retreatable.append({"slot": sid, "inst": inst})

	if retreatable.is_empty():
		_log("[Retreat] No active Pokémon can afford to retreat.")
		return

	## Collect bench Pokémon available as replacements.
	var bench_options: Array[String] = []
	for i in range(1, _bench_slots + 1):
		var sid := "p%d_bench%d" % [pid, i]
		if manager.board_position.get_instance(sid) != null:
			bench_options.append(sid)

	if bench_options.is_empty():
		_log("[Retreat] No bench Pokémon to retreat to.")
		return

	var panel := _make_setup_panel()
	panel.custom_minimum_size = Vector2(400, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Choose Pokémon to Retreat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for entry: Dictionary in retreatable:
		var inst: PokemonInstance = entry["inst"]
		var slot: String = entry["slot"]
		var cost: int = inst.card.retreat_cost
		var have: int = inst.attached_energy.size()
		var btn := Button.new()
		btn.text = "%s  (cost %d, have %d energy)" % [inst.card.display_name, cost, have]
		var fn: Callable = func(s: String) -> void:
			panel.queue_free()
			_attack_dialog = null
			_pick_bench_for_retreat(pid, s, bench_options)
		btn.pressed.connect(fn.bind(slot))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
	)
	vbox.add_child(cancel)
	$HUD.add_child(panel)
	_attack_dialog = panel


func _pick_bench_for_retreat(pid: int, active_slot: String, bench_options: Array[String]) -> void:
	if bench_options.size() == 1:
		_submit_retreat(pid, active_slot, bench_options[0])
		return

	var panel := _make_setup_panel()
	panel.custom_minimum_size = Vector2(380, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Choose Bench Replacement"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for bnch: String in bench_options:
		var inst: PokemonInstance = manager.board_position.get_instance(bnch)
		var pname := inst.card.display_name if inst != null and inst.card != null else bnch
		var hp_str := " (%d/%d HP)" % [inst.current_hp, inst.max_hp] if inst != null else ""
		var btn := Button.new()
		btn.text = "%s%s" % [pname, hp_str]
		var fn: Callable = func(bs: String) -> void:
			panel.queue_free()
			_attack_dialog = null
			_submit_retreat(pid, active_slot, bs)
		btn.pressed.connect(fn.bind(bnch))
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
	)
	vbox.add_child(cancel)
	$HUD.add_child(panel)
	_attack_dialog = panel


func _submit_retreat(pid: int, active_slot: String, bench_slot: String) -> void:
	var action := ActionRetreat.new(pid, active_slot, bench_slot)
	_authority.request_action(action)


## ---------------------------------------------------------------------------
## Prize selection dialog
## ---------------------------------------------------------------------------

func _on_prize_selection_required(player_id: int) -> void:
	_update_phase_label()
	_show_prize_selection_dialog(player_id)


func _show_prize_selection_dialog(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	var panel := _make_setup_panel()
	panel.custom_minimum_size = Vector2(320, 50)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "P%d: Choose a prize card from the board" % player_id
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	$HUD.add_child(panel)
	_attack_dialog = panel

	_highlight_prize_zones(player_id, true)


func _highlight_prize_zones(player_id: int, on: bool) -> void:
	var prefix := _zone_prefix(player_id)
	for i in range(1, _prize_count + 1):
		var zone: DropZone = board.get_named_zone("%sPrize %d" % [prefix, i])
		if zone != null:
			zone.set_highlighted(on)


## ---------------------------------------------------------------------------
## Promotion dialog
## ---------------------------------------------------------------------------

func _on_promotion_required(player_id: int) -> void:
	_update_phase_label()
	_show_promotion_dialog(player_id)


func _show_promotion_dialog(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	## Gather the empty active slots and bench options.
	var empty_actives: Array[String] = []
	for i in range(1, _active_slots + 1):
		var sid := "p%d_active%d" % [player_id, i]
		if manager.board_position.get_instance(sid) == null \
				and manager.board_position.has_slot(sid):
			empty_actives.append(sid)

	var bench_occupied: Array[String] = []
	for i in range(1, _bench_slots + 1):
		var sid := "p%d_bench%d" % [player_id, i]
		if manager.board_position.get_instance(sid) != null:
			bench_occupied.append(sid)

	if empty_actives.is_empty() or bench_occupied.is_empty():
		return

	var panel := _make_setup_panel()
	panel.custom_minimum_size = Vector2(400, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "P%d: Promote a Pokémon to Active" % player_id
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	## If there is only one active slot to fill, skip the active-slot choice.
	var to_slot: String = empty_actives[0] if empty_actives.size() == 1 else ""

	for bnch: String in bench_occupied:
		var inst: PokemonInstance = manager.board_position.get_instance(bnch)
		var pname := inst.card.display_name if inst != null and inst.card != null else bnch
		var hp_str := " (%d/%d HP)" % [inst.current_hp, inst.max_hp] if inst != null else ""

		if to_slot != "":
			## Only one active destination — promote directly.
			var btn := Button.new()
			btn.text = "%s%s" % [pname, hp_str]
			var fn: Callable = func(bs: String, ts: String) -> void:
				panel.queue_free()
				_attack_dialog = null
				_submit_promotion(player_id, bs, ts)
			btn.pressed.connect(fn.bind(bnch, to_slot))
			vbox.add_child(btn)
		else:
			## Multiple empty actives — show a sub-label then one button per active.
			var lbl := Label.new()
			lbl.text = "%s%s → ?" % [pname, hp_str]
			vbox.add_child(lbl)
			for act: String in empty_actives:
				var btn := Button.new()
				btn.text = "  → %s" % act
				var fn: Callable = func(bs: String, ts: String) -> void:
					panel.queue_free()
					_attack_dialog = null
					_submit_promotion(player_id, bs, ts)
				btn.pressed.connect(fn.bind(bnch, act))
				vbox.add_child(btn)

	$HUD.add_child(panel)
	_attack_dialog = panel


func _submit_promotion(player_id: int, from_slot: String, to_slot: String) -> void:
	var action := ActionPromote.new(player_id, from_slot, to_slot)
	_authority.request_action(action)


## ---------------------------------------------------------------------------
## KO / prize / promotion / win signal handlers
## ---------------------------------------------------------------------------

func _on_pokemon_knocked_out(_slot_id: String) -> void:
	_update_phase_label()


func _on_prize_taken(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	_highlight_prize_zones(player_id, false)
	_update_phase_label()
	## If no promotion is pending after this prize, the attacking turn can end.
	_try_end_turn_after_attack()


func _on_promotion_done(_player_id: int, _to_slot: String) -> void:
	_update_phase_label()
	_try_end_turn_after_attack()


func _on_game_won(player_id: int) -> void:
	_attack_end_turn_pending = false
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	_highlight_prize_zones(0, false)
	_highlight_prize_zones(1, false)
	_log("[GAME OVER] Player %d wins!" % player_id)
	end_turn_button.disabled  = true
	if _attack_button  != null: _attack_button.disabled  = true
	if _retreat_button != null: _retreat_button.disabled = true

	var panel := _make_setup_panel()
	var vbox := panel.get_child(0) as VBoxContainer
	var lbl := Label.new()
	lbl.text = "Player %d Wins!" % player_id
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	vbox.add_child(lbl)
	var btn := Button.new()
	btn.text = "Play Again"
	btn.pressed.connect(func() -> void:
		panel.queue_free()
		end_turn_button.disabled  = false
		if _attack_button  != null: _attack_button.disabled  = false
		if _retreat_button != null: _retreat_button.disabled = false
		_reset_game()
	)
	vbox.add_child(btn)
	$HUD.add_child(panel)


func _log(text: String) -> void:
	game_log.append_text(text + "\n")
