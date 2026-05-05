class_name SaveLoadManager
extends Node

## Handles save/load dialog UI and game-state restoration.

var _main: Node = null


func init(main_node: Node) -> void:
	_main = main_node


func on_save_pressed() -> void:
	var default_name := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var panel := MatchUIUtils.make_panel()
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Save Game State"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var name_lbl := Label.new()
	name_lbl.text = "Save Name:"
	vbox.add_child(name_lbl)

	var name_edit := LineEdit.new()
	name_edit.text = default_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(name_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(save_btn)

	_main.get_node("HUD").add_child(panel)
	name_edit.grab_focus()
	name_edit.select_all()

	cancel_btn.pressed.connect(func() -> void: panel.queue_free())
	save_btn.pressed.connect(func() -> void:
		var save_name: String = name_edit.text.strip_edges()
		panel.queue_free()
		var state := GameStateSerializer.serialize(
			_main.manager,
			_main.is_developer_mode,
			_main._prize_count,
			_main._active_slots,
			_main._bench_slots,
			_main._controlling_player
		)
		state["name"] = save_name
		var path := GameStateSerializer.save_to_file(state, save_name)
		if path != "":
			_main._log("[Save] State saved: %s" % save_name)
		else:
			_main._log("[Save] ERROR: could not write save file.")
	)


func on_load_pressed() -> void:
	var saves := GameStateSerializer.list_saves()

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(480, 380)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Load Game State"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	if saves.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No saved states found."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 220)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(scroll)

		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)

		for entry: Dictionary in saves:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			list.add_child(row)

			var lbl := Label.new()
			var disp_name: String = entry.get("name", "") as String
			var disp_time: String = entry.get("saved_at", "") as String
			lbl.text = "%s  [%s]" % [disp_name, disp_time]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)

			var load_btn := Button.new()
			load_btn.text = "Load"
			var captured_path: String = entry.get("path", "") as String
			load_btn.pressed.connect(func() -> void:
				panel.queue_free()
				load_game_state(captured_path)
			)
			row.add_child(load_btn)

	vbox.add_child(HSeparator.new())

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func() -> void: panel.queue_free())
	vbox.add_child(cancel_btn)

	_main.get_node("HUD").add_child(panel)


func load_game_state(path: String) -> void:
	var state := GameStateSerializer.load_from_file(path)
	if state.is_empty():
		_main._log("[Load] ERROR: could not read save file.")
		return

	_main.is_developer_mode     = (state.get("mode", "developer") as String) == "developer"
	_main._prize_count          = int(state.get("prize_count",        6))
	_main._active_slots         = int(state.get("active_slots",       1))
	_main._bench_slots          = int(state.get("bench_slots",        5))
	_main._controlling_player   = int(state.get("controlling_player", 0))

	_main._in_setup_phase        = false
	_main._in_placement_phase    = false
	_main._attack_end_turn_pending = false
	_main.end_turn_button.text   = "End Turn"
	_main.end_turn_button.disabled = false
	_main._input_mgr.reset()
	_main._dialog_mgr.clear()
	if _main._setup_dialog != null:
		_main._setup_dialog.queue_free()
		_main._setup_dialog = null

	_main._pile_mgr.clear()
	_main._hand_mgr.clear()

	if _main._opponent_hand != null:
		_main._opponent_hand.queue_free()
		_main._opponent_hand = null

	for sid in BoardPosition.all_slot_ids():
		var inst: PokemonInstance = _main.manager.board_position.clear(sid)
		if inst != null:
			inst.queue_free()

	_main.manager.game_position  = GamePosition.new()
	_main.manager.board_position.queue_free()
	_main.manager.board_position = BoardPosition.new()
	_main.manager.add_child(_main.manager.board_position)
	_main.manager.board_position.slot_changed.connect(_main.manager._on_slot_changed)
	_main.manager.board_position.overflow_escalation.connect(_main.manager._on_overflow_escalation)
	_main.manager.game_position.deck_changed.connect(func(pid): _main.manager.deck_changed.emit(pid))
	_main.manager.game_position.hand_changed.connect(func(pid): _main.manager.hand_changed.emit(pid))
	_main.manager.game_position.card_left_hand.connect(func(pid, card): _main.manager.card_left_hand.emit(pid, card))
	_main.manager.game_position.discard_changed.connect(func(pid): _main.manager.discard_changed.emit(pid))
	_main.manager.game_position.prizes_changed.connect(func(pid): _main.manager.prizes_changed.emit(pid))

	_main.manager.configure_slots(_main._active_slots, _main._bench_slots)
	_main.board.configure_slots(_main._active_slots, _main._bench_slots, _main._prize_count)

	_main._opponent_hand = _main._HAND_SCENE.instantiate() as Hand
	_main._opponent_hand.name = "OpponentHand"
	_main.board.add_child(_main._opponent_hand)
	_main._opponent_hand.transform = _main._p1_hand_transform

	_main.manager.attach_board_anchors(_main.board.collect_slot_anchors())
	_main.manager.reset_game_state()

	var pool_by_id := TestDeckFactory._build_card_pool_by_id()
	GameStateSerializer.restore_turn_state(state, _main.manager)
	GameStateSerializer.restore_positions(state, _main.manager, pool_by_id)
	GameStateSerializer.restore_board(state, _main.manager, pool_by_id)

	_main.player_hand.transform = _main._p0_hand_transform
	_main.camera.transform = _main._p1_cam_transform if _main._controlling_player == 1 else _main._p0_cam_transform

	for pid in range(2):
		_main.manager.game_position.deck_changed.emit(pid)
		_main.manager.game_position.hand_changed.emit(pid)
		_main.manager.game_position.discard_changed.emit(pid)
		_main.manager.game_position.prizes_changed.emit(pid)

	_main._hand_mgr.rebuild(0)
	_main._hand_mgr.rebuild(1)

	_main._update_phase_label()
	_main._log("[Load] State '%s' loaded." % state.get("name", path))
