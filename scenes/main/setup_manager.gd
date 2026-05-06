class_name SetupManager
extends Node

## Manages the pre-game setup dialog and mulligan/placement/coin-flip sequence.

var _main: Node = null
var _setup_selected_mode: String = ""
var _player_deck_path: String = ""
var _opponent_deck_path: String = ""

## Emitted by mulligan-offer buttons so the coroutine can await the choice.
signal _setup_choice_made(chose_yes: bool)


func init(main_node: Node) -> void:
	_main = main_node


func show_setup_dialog() -> void:
	_main._setup_dialog = PanelContainer.new()
	_main._setup_dialog.custom_minimum_size = Vector2(420, 320)
	_main._setup_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18, 0.97)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_main._setup_dialog.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_main._setup_dialog.add_child(vbox)

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
	prize_spin.value     = _main._prize_count
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
	active_spin.value     = _main._active_slots
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
	bench_spin.value     = _main._bench_slots
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
		_main._setup_dialog.queue_free()
		_main._setup_dialog = null
		_on_setup_confirmed(
			_setup_selected_mode,
			int(prize_spin.value),
			int(active_spin.value),
			int(bench_spin.value),
			p_path,
			o_path
		)
	)

	_main.get_node("HUD").add_child(_main._setup_dialog)


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
	_main.is_developer_mode   = (mode == "developer")
	_main._prize_count        = prizes
	_main._active_slots       = active_slots
	_main._bench_slots        = bench_slots
	_player_deck_path   = player_deck_path
	_opponent_deck_path = opponent_deck_path
	_start_game()


## ---------------------------------------------------------------------------
## Game lifecycle
## ---------------------------------------------------------------------------

func _start_game() -> void:
	_main._in_setup_phase = true
	_main.manager.configure_slots(_main._active_slots, _main._bench_slots)
	_main.board.configure_slots(_main._active_slots, _main._bench_slots, _main._prize_count)

	_main._opponent_hand = _main._HAND_SCENE.instantiate() as Hand
	_main._opponent_hand.name = "OpponentHand"
	_main.board.add_child(_main._opponent_hand)
	_main._opponent_hand.transform = _main._p1_hand_transform

	var p0_deck: Array[CardData] = DeckLoader.load_deck(0, _player_deck_path)
	var p1_deck: Array[CardData] = DeckLoader.load_deck(1, _opponent_deck_path)
	TestDeckFactory.load_art_for_deck(p0_deck)
	TestDeckFactory.load_art_for_deck(p1_deck)
	_main._authority.load_deck(0, p0_deck)
	_main._authority.load_deck(1, p1_deck)

	_main._authority.draw_starting_hand(0, 7)
	_main._authority.draw_starting_hand(1, 7)

	_run_setup_sequence()


## ---------------------------------------------------------------------------
## Setup sequence (mulligans + coin flip)
## ---------------------------------------------------------------------------

func _run_setup_sequence() -> void:
	var mulligan_counts: Array[int] = [0, 0]

	while true:
		var p0_ok: bool = (_main._authority as MatchAuthority).has_basic_in_hand(0)
		var p1_ok: bool = (_main._authority as MatchAuthority).has_basic_in_hand(1)
		if p0_ok and p1_ok:
			break

		if not p0_ok and not p1_ok:
			mulligan_counts[0] += 1
			mulligan_counts[1] += 1
			_main._log("[Setup] Both players have no Basic Pokémon — both take a mulligan.")
			_main._authority.return_hand_to_deck(0)
			_main._authority.return_hand_to_deck(1)
			_main._authority.draw_starting_hand(0, 7)
			_main._authority.draw_starting_hand(1, 7)
			await _show_setup_info(
				"Both players had no Basic Pokémon.\nBoth shuffled and drew 7 new cards."
			)
			continue

		var mulligan_pid: int = 0 if not p0_ok else 1
		var other_pid:    int = 1 - mulligan_pid
		mulligan_counts[mulligan_pid] += 1
		_main._log("[Setup] P%d has no Basic Pokémon — taking mulligan #%d." \
				% [mulligan_pid, mulligan_counts[mulligan_pid]])
		_main._authority.return_hand_to_deck(mulligan_pid)
		_main._authority.draw_starting_hand(mulligan_pid, 7)

		await _show_setup_info(
			"Player %d had no Basic Pokémon\nand took mulligan #%d.\nThey shuffled and drew 7 new cards." \
			% [mulligan_pid, mulligan_counts[mulligan_pid]]
		)

		var wants_draw: bool = await _show_mulligan_card_offer(other_pid)
		if wants_draw:
			_main._authority.draw_one(other_pid)
			_main._log("[Setup] P%d draws an extra card (mulligan bonus)." % other_pid)

	_main._authority.deal_prizes(0, _main._prize_count)
	_main._authority.deal_prizes(1, _main._prize_count)
	_main._log("[Setup] Prize cards dealt.")

	for placing_pid: int in [0, 1]:
		_main._authority.begin_setup_placement(placing_pid)
		_main._apply_perspective(placing_pid)
		_main._hand_mgr.rebuild(0)
		_main._hand_mgr.rebuild(1)
		_main._in_setup_phase = false
		await _show_placement_phase(placing_pid)
		_main._in_setup_phase = true
		_main._authority.end_setup_placement()
		_main._log("[Setup] P%d finished placing starting Pokémon." % placing_pid)

	var _heads: bool         = _main.manager.flip_coin("Opening flip")
	var flip_result: int     = 0 if _heads else 1
	var starting_player: int = flip_result
	_main._log("[Setup] Coin flip: %s — P%d goes first." \
			% ["Heads" if flip_result == 0 else "Tails", starting_player])

	await _show_coin_flip_result(starting_player, flip_result)

	_main._in_setup_phase = false
	_main._authority.begin_game(starting_player)


## ---------------------------------------------------------------------------
## Setup-phase dialog helpers
## ---------------------------------------------------------------------------

func _is_placement_ready(pid: int) -> bool:
	var has_active := false
	for i in range(1, _main._active_slots + 1):
		if _main.manager.board_position.get_instance("p%d_active%d" % [pid, i]) != null:
			has_active = true
			break
	if not has_active:
		return false
	var has_bench := false
	for i in range(1, _main._bench_slots + 1):
		if _main.manager.board_position.get_instance("p%d_bench%d" % [pid, i]) != null:
			has_bench = true
			break
	if not has_bench:
		return true
	for i in range(1, _main._active_slots + 1):
		if _main.manager.board_position.get_instance("p%d_active%d" % [pid, i]) == null:
			return false
	return true


func _show_placement_phase(placing_pid: int) -> void:
	_main._in_placement_phase      = true
	_main.end_turn_button.text     = "Ready"
	_main.end_turn_button.disabled = not _is_placement_ready(placing_pid)
	_main._update_phase_label()

	var refresh := func(_sid: String, _inst: PokemonInstance) -> void:
		_main.end_turn_button.disabled = not _is_placement_ready(placing_pid)
	_main._authority.board_slot_changed.connect(refresh)

	await _main.end_turn_button.pressed
	_main._authority.board_slot_changed.disconnect(refresh)

	_main.end_turn_button.text     = "End Turn"
	_main.end_turn_button.disabled = false
	_main._in_placement_phase      = false


func _show_setup_info(message: String) -> void:
	var panel := _make_panel()
	var vbox := panel.get_child(0) as VBoxContainer
	var lbl := Label.new()
	lbl.text = message
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var btn := Button.new()
	btn.text = "Continue"
	vbox.add_child(btn)
	_main.get_node("HUD").add_child(panel)
	await btn.pressed
	panel.queue_free()


func _show_mulligan_card_offer(offer_pid: int) -> bool:
	var panel := _make_panel()
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
	_main.get_node("HUD").add_child(panel)
	var result: bool = await _setup_choice_made
	panel.queue_free()
	return result


func _show_coin_flip_result(starting_player: int, flip_result: int) -> void:
	var panel := _make_panel()
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
	_main.get_node("HUD").add_child(panel)
	await btn.pressed
	panel.queue_free()


func _make_panel() -> PanelContainer:
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
