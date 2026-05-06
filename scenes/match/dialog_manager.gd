class_name DialogManager
extends Node

## Owns all in-match modal dialogs: attack, retreat, bench modify,
## prize selection, promotion, energy discard, and the win screen.

var _main: Node = null
var _hud: CanvasLayer = null

## Active attack/retreat/prize/promotion dialog (at most one open at a time).
var _attack_dialog: Control = null

## Queue of {pid, slot_id} dicts for Pokemon that couldn't be auto-relocated
## when the bench slot count was reduced.  Processed one at a time.
var _bench_overflow_queue: Array = []


func init(main_node: Node) -> void:
	_main = main_node
	_hud  = main_node.get_node("HUD")


func clear() -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	_bench_overflow_queue.clear()


## ---------------------------------------------------------------------------
## Attack UI
## ---------------------------------------------------------------------------

func on_attack_pressed() -> void:
	if _main._setup_dialog != null or _main._in_setup_phase:
		return
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
		return
	_show_attack_dialog()


func _show_attack_dialog() -> void:
	var pid: int = (_main._authority as MatchAuthority).current_player_id()

	var opp_id := 1 - pid
	var opp_actives: Array[String] = []
	for i in range(1, _main._active_slots + 1):
		var sid := "p%d_active%d" % [opp_id, i]
		if _main.manager.board_position.get_instance(sid) != null:
			opp_actives.append(sid)

	if opp_actives.is_empty():
		_main._log("[Attack] No opponent active Pokémon to attack.")
		return

	var entries: Array = []
	for i in range(1, _main._active_slots + 1):
		var sid := "p%d_active%d" % [pid, i]
		var inst: PokemonInstance = _main.manager.board_position.get_instance(sid)
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
		_main._log("[Attack] No attacks available this turn.")
		return

	var panel := MatchUIUtils.make_panel()
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

		var cost_str := MatchUIUtils.format_attack_cost(atk)
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

	_hud.add_child(panel)
	_attack_dialog = panel


func _pick_target_then_attack(pid: int, atk_slot: String, atk_idx: int, opp_actives: Array[String]) -> void:
	if opp_actives.size() == 1:
		_submit_attack(pid, atk_slot, atk_idx, opp_actives[0])
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(380, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Choose a Target"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for tgt_slot: String in opp_actives:
		var inst: PokemonInstance = _main.manager.board_position.get_instance(tgt_slot)
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

	_hud.add_child(panel)
	_attack_dialog = panel


func _submit_attack(pid: int, atk_slot: String, atk_idx: int, tgt_slot: String) -> void:
	var action := ActionAttack.new(pid, atk_slot, atk_idx, tgt_slot)
	var result: ActionResult = await (_main._authority as MatchAuthority).request_action_async(action)
	if result.ok:
		_main._attack_end_turn_pending = true
		_main._try_end_turn_after_attack()


## ---------------------------------------------------------------------------
## Retreat UI
## ---------------------------------------------------------------------------

func on_retreat_pressed() -> void:
	if _main._setup_dialog != null or _main._in_setup_phase:
		return
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
		return
	_show_retreat_dialog()


func _show_retreat_dialog() -> void:
	var pid: int = (_main._authority as MatchAuthority).current_player_id()

	var retreatable: Array = []
	for i in range(1, _main._active_slots + 1):
		var sid := "p%d_active%d" % [pid, i]
		var inst: PokemonInstance = _main.manager.board_position.get_instance(sid)
		if inst == null or inst.card == null:
			continue
		if inst.attached_energy.size() >= inst.card.retreat_cost:
			retreatable.append({"slot": sid, "inst": inst})

	if retreatable.is_empty():
		_main._log("[Retreat] No active Pokémon can afford to retreat.")
		return

	var bench_options: Array[String] = []
	for i in range(1, _main._bench_slots + 1):
		var sid := "p%d_bench%d" % [pid, i]
		if _main.manager.board_position.get_instance(sid) != null:
			bench_options.append(sid)

	if bench_options.is_empty():
		_main._log("[Retreat] No bench Pokémon to retreat to.")
		return

	var panel := MatchUIUtils.make_panel()
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
	_hud.add_child(panel)
	_attack_dialog = panel


func _pick_bench_for_retreat(pid: int, active_slot: String, bench_options: Array[String]) -> void:
	if bench_options.size() == 1:
		_submit_retreat(pid, active_slot, bench_options[0])
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(380, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Choose Bench Replacement"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for bnch: String in bench_options:
		var inst: PokemonInstance = _main.manager.board_position.get_instance(bnch)
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
	_hud.add_child(panel)
	_attack_dialog = panel


func _submit_retreat(pid: int, active_slot: String, bench_slot: String) -> void:
	var action := ActionRetreat.new(pid, active_slot, bench_slot)
	_main._authority.request_action(action)


## ---------------------------------------------------------------------------
## Modify Bench dialog
## ---------------------------------------------------------------------------

func on_modify_bench_pressed() -> void:
	if _main._setup_dialog != null or _main._in_setup_phase:
		return
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
		return
	_show_modify_bench_dialog()


func _show_modify_bench_dialog() -> void:
	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(320, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "Modify Bench Slots"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Bench Slots (3–5):"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := SpinBox.new()
	spin.min_value = 3
	spin.max_value = 5
	spin.value     = _main.manager.bench_slot_count
	row.add_child(lbl)
	row.add_child(spin)
	vbox.add_child(row)

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
		_apply_bench_count_change(int(spin.value))
	)
	vbox.add_child(apply_btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
	)
	vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


func _apply_bench_count_change(new_count: int) -> void:
	_main._bench_slots = new_count
	_bench_overflow_queue = _main.manager.set_bench_count(new_count)
	_main.board.set_bench_count(new_count)
	_process_bench_overflow()


func _process_bench_overflow() -> void:
	if _bench_overflow_queue.is_empty():
		return
	var entry: Dictionary = _bench_overflow_queue.pop_front()
	var pid: int = entry["pid"]
	var displaced_slot: String = entry["displaced_slot"]

	var displaced_inst: PokemonInstance = _main.manager.board_position.get_instance(displaced_slot)
	if displaced_inst == null:
		_process_bench_overflow()
		return

	for m in range(1, _main._bench_slots + 1):
		var target := "p%d_bench%d" % [pid, m]
		if _main.manager.board_position.get_instance(target) == null:
			_main.manager.board_position.move(displaced_slot, target)
			_process_bench_overflow()
			return

	var discard_options: Array[String] = []
	for m in range(1, 6):
		var sid := "p%d_bench%d" % [pid, m]
		if _main.manager.board_position.get_instance(sid) != null:
			discard_options.append(sid)

	var dname := displaced_inst.card.display_name if displaced_inst.card != null else "Pokémon"

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(400, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "P%d: %s needs a bench spot.\nDiscard a Pokémon to make room:" % [pid, dname]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)

	for discard_slot in discard_options:
		var discard_inst: PokemonInstance = _main.manager.board_position.get_instance(discard_slot)
		var pname := discard_inst.card.display_name \
				if discard_inst != null and discard_inst.card != null else discard_slot
		var hp_str := " (%d/%d HP)" % [discard_inst.current_hp, discard_inst.max_hp] \
				if discard_inst != null else ""
		var btn := Button.new()
		btn.text = "%s%s" % [pname, hp_str]
		var _ds := discard_slot
		var _dn := pname
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			var chosen: PokemonInstance = _main.manager.board_position.get_instance(_ds)
			if chosen != null:
				_main.manager.board_position.clear(_ds)
				var released := chosen.release_cards()
				_main.manager.game_position.discard_all(pid, released)
				chosen.queue_free()
				_main._log("[Bench] P%d: %s discarded — bench reduced." % [pid, _dn])
			_bench_overflow_queue.push_front(entry)
			_process_bench_overflow()
		)
		vbox.add_child(btn)

	_hud.add_child(panel)


## ---------------------------------------------------------------------------
## Prize selection dialog
## ---------------------------------------------------------------------------

func on_prize_selection_required(player_id: int) -> void:
	_main._update_phase_label()
	_show_prize_selection_dialog(player_id)


func _show_prize_selection_dialog(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(320, 50)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "P%d: Choose a prize card from the board" % player_id
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	_hud.add_child(panel)
	_attack_dialog = panel

	_highlight_prize_zones(player_id, true)


func _highlight_prize_zones(player_id: int, on: bool) -> void:
	var prefix := MatchUIUtils.zone_prefix(player_id)
	for i in range(1, _main._prize_count + 1):
		var zone: DropZone = _main.board.get_named_zone("%sPrize %d" % [prefix, i])
		if zone != null:
			zone.set_highlighted(on)


## ---------------------------------------------------------------------------
## Promotion dialog
## ---------------------------------------------------------------------------

func on_promotion_required(player_id: int) -> void:
	_main._update_phase_label()
	_show_promotion_dialog(player_id)


func _show_promotion_dialog(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	var empty_actives: Array[String] = []
	for i in range(1, _main._active_slots + 1):
		var sid := "p%d_active%d" % [player_id, i]
		if _main.manager.board_position.get_instance(sid) == null \
				and _main.manager.board_position.has_slot(sid):
			empty_actives.append(sid)

	var bench_occupied: Array[String] = []
	for i in range(1, _main._bench_slots + 1):
		var sid := "p%d_bench%d" % [player_id, i]
		if _main.manager.board_position.get_instance(sid) != null:
			bench_occupied.append(sid)

	if empty_actives.is_empty() or bench_occupied.is_empty():
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(400, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var title := Label.new()
	title.text = "P%d: Promote a Pokémon to Active" % player_id
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var to_slot: String = empty_actives[0] if empty_actives.size() == 1 else ""

	for bnch: String in bench_occupied:
		var inst: PokemonInstance = _main.manager.board_position.get_instance(bnch)
		var pname := inst.card.display_name if inst != null and inst.card != null else bnch
		var hp_str := " (%d/%d HP)" % [inst.current_hp, inst.max_hp] if inst != null else ""

		if to_slot != "":
			var btn := Button.new()
			btn.text = "%s%s" % [pname, hp_str]
			var fn: Callable = func(bs: String, ts: String) -> void:
				panel.queue_free()
				_attack_dialog = null
				_submit_promotion(player_id, bs, ts)
			btn.pressed.connect(fn.bind(bnch, to_slot))
			vbox.add_child(btn)
		else:
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

	_hud.add_child(panel)
	_attack_dialog = panel


func _submit_promotion(player_id: int, from_slot: String, to_slot: String) -> void:
	var action := ActionPromote.new(player_id, from_slot, to_slot)
	_main._authority.request_action(action)


## ---------------------------------------------------------------------------
## KO / prize / promotion / win signal handlers
## ---------------------------------------------------------------------------

func on_prize_taken(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	_highlight_prize_zones(player_id, false)
	_main._update_phase_label()
	_main._try_end_turn_after_attack()


func on_promotion_done() -> void:
	_main._update_phase_label()
	_main._try_end_turn_after_attack()


func on_game_won(player_id: int) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	_highlight_prize_zones(0, false)
	_highlight_prize_zones(1, false)

	var panel := MatchUIUtils.make_panel()
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
		_main.end_turn_button.disabled  = false
		if _main._attack_button  != null: _main._attack_button.disabled  = false
		if _main._retreat_button != null: _main._retreat_button.disabled = false
		if _main._bench_button   != null: _main._bench_button.disabled   = false
		_main._reset_game()
	)
	vbox.add_child(btn)
	_hud.add_child(panel)


## ---------------------------------------------------------------------------
## Energy discard choice dialog
## ---------------------------------------------------------------------------

func on_energy_discard_choice_required(
		_player_id: int, eligible: Array, count: int, _attacker_slot: String) -> void:
	var panel := MatchUIUtils.make_panel()
	var vbox  := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = "Choose %d energy card%s to discard:" % [count, "s" if count > 1 else ""]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var selected: Array[int] = []

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm (%d/%d selected)" % [0, count]
	confirm_btn.disabled = true

	for i in eligible.size():
		var card: CardData = eligible[i]
		var cb := CheckBox.new()
		cb.text = card.display_name if card != null else "Energy"
		var idx := i
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(idx):
					selected.append(idx)
			else:
				selected.erase(idx)
			confirm_btn.text = "Confirm (%d/%d selected)" % [selected.size(), count]
			confirm_btn.disabled = selected.size() != count
		)
		vbox.add_child(cb)

	confirm_btn.pressed.connect(func() -> void:
		_main.manager.resolve_energy_discard_choice(selected)
		panel.queue_free()
	)
	vbox.add_child(confirm_btn)

	_hud.add_child(panel)


func on_retreat_energy_choice_required(
		_player_id: int, eligible: Array, count: int, _active_slot: String) -> void:
	var panel := MatchUIUtils.make_panel()
	var vbox  := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = "Retreat — choose %d energy card%s to discard:" % [count, "s" if count > 1 else ""]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var selected: Array[int] = []

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm (%d/%d selected)" % [0, count]
	confirm_btn.disabled = true

	for i in eligible.size():
		var card: CardData = eligible[i]
		var cb := CheckBox.new()
		cb.text = card.display_name if card != null else "Energy"
		var idx := i
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(idx):
					selected.append(idx)
			else:
				selected.erase(idx)
			confirm_btn.text = "Confirm (%d/%d selected)" % [selected.size(), count]
			confirm_btn.disabled = selected.size() != count
		)
		vbox.add_child(cb)

	confirm_btn.pressed.connect(func() -> void:
		_main.manager.resolve_retreat_energy_choice(selected)
		panel.queue_free()
	)
	vbox.add_child(confirm_btn)

	_hud.add_child(panel)
