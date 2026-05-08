class_name DialogManager
extends Node

## Owns all in-match modal dialogs: attack, retreat, bench modify,
## prize selection, promotion, energy discard, and the win screen.

var _main: Node = null
var _hud: CanvasLayer = null

## Active attack/retreat/prize/promotion dialog (at most one open at a time).
var _attack_dialog: Control = null


func init(main_node: Node) -> void:
	_main = main_node
	_hud  = main_node.get_node("HUD")


func clear() -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null


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
	title.text = "Retreat — choose active Pokémon"
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
	title.text = "Retreat — choose bench replacement"
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
		_main._reset_game()
	)
	vbox.add_child(btn)
	_hud.add_child(panel)


## ---------------------------------------------------------------------------
## Energy discard choice dialog
## ---------------------------------------------------------------------------

func on_energy_discard_choice_required(
		_player_id: int, eligible: Array, count: int, _attacker_slot: String) -> void:
	var header := "Choose %d energy card%s to discard:" % [count, "s" if count > 1 else ""]
	_show_energy_choice_dialog(header, eligible, count,
		func(sel: Array[int]) -> void:
			_main.manager.resolve_energy_discard_choice(sel)
	)


func on_retreat_energy_choice_required(
		_player_id: int, eligible: Array, count: int, _active_slot: String) -> void:
	var header := "Retreat — choose %d energy card%s to discard:" % [count, "s" if count > 1 else ""]
	_show_energy_choice_dialog(header, eligible, count,
		func(sel: Array[int]) -> void:
			_main.manager.resolve_retreat_energy_choice(sel)
	)


## Returns true when every entry in [eligible] is an EnergyCardData with the
## same energy_type — meaning the player has no meaningful choice and we can
## just auto-pick the first [count] indices.
func _energy_choice_is_degenerate(eligible: Array) -> bool:
	if eligible.size() < 2:
		return true
	if not (eligible[0] is EnergyCardData):
		return false
	var first_type: int = (eligible[0] as EnergyCardData).energy_type
	for c: CardData in eligible:
		if not (c is EnergyCardData):
			return false
		if (c as EnergyCardData).energy_type != first_type:
			return false
	return true


func _show_energy_choice_dialog(header_text: String, eligible: Array, count: int, on_confirm: Callable) -> void:
	if _energy_choice_is_degenerate(eligible):
		var auto_indices: Array[int] = []
		for i in range(mini(count, eligible.size())):
			auto_indices.append(i)
		on_confirm.call(auto_indices)
		return

	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	var panel := MatchUIUtils.make_panel()
	var vbox  := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var selected: Array[int] = []

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm (%d/%d selected)" % [0, count]
	confirm_btn.disabled = true

	for i in eligible.size():
		var card: CardData = eligible[i]
		var info := MatchUIUtils.energy_label_and_color(card)
		var cb := CheckBox.new()
		cb.text = info["label"]
		cb.add_theme_color_override("font_color", info["color"])
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
		var to_send: Array[int] = selected.duplicate()
		panel.queue_free()
		_attack_dialog = null
		on_confirm.call(to_send)
	)
	vbox.add_child(confirm_btn)

	_hud.add_child(panel)
	_attack_dialog = panel
