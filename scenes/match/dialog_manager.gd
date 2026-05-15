class_name DialogManager
extends Node

## Owns all in-match modal dialogs: attack, retreat, bench modify,
## prize selection, promotion, energy discard, and the win screen.

var _main: Node = null
var _hud: CanvasLayer = null

## Active attack/retreat/prize/promotion dialog (at most one open at a time).
var _attack_dialog: Control = null

## Deck-search overlay state (kept separately so it can coexist with attack
## dialogs without interfering with their lifecycle).  When minimised, the
## main panel is hidden and `_deck_search_restore_btn` is shown instead.
var _deck_search_panel: Control = null
var _deck_search_restore_btn: Button = null


func init(main_node: Node) -> void:
	_main = main_node
	_hud  = main_node.get_node("HUD")


func clear() -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	_close_deck_search()


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


## ---------------------------------------------------------------------------
## Trainer-effect query dialog
## ---------------------------------------------------------------------------

## Routed from match.gd when TrainerResolver emits player_query_requested.
## Dispatches by query.kind to the right picker.  All pickers ultimately
## resolve via _main.manager.trainer_resolver.resolve_query(response).
func on_trainer_query_requested(query: TrainerQuery) -> void:
	match query.kind:
		TrainerQuery.Kind.CHOOSE_OWN_POKEMON, \
		TrainerQuery.Kind.CHOOSE_OWN_BENCH, \
		TrainerQuery.Kind.CHOOSE_OPPONENT_BENCH, \
		TrainerQuery.Kind.CHOOSE_OPPONENT_POKEMON:
			_show_pokemon_slot_picker(query)
		TrainerQuery.Kind.CHOOSE_FROM_HAND, \
		TrainerQuery.Kind.CHOOSE_FROM_LIST:
			_show_deck_search_grid(query)
		TrainerQuery.Kind.CHOOSE_ENERGY_ON_POKEMON:
			_show_energy_on_pokemon_picker(query)
		TrainerQuery.Kind.REORDER_TOP_OF_DECK:
			_show_deck_reorder_grid(query)
		TrainerQuery.Kind.GENERIC_CHOICE:
			_show_generic_choice(query)
		_:
			push_warning("DialogManager: unhandled trainer query kind %d" % query.kind)
			_main.manager.trainer_resolver.resolve_query(null)


## Generic Pokémon slot picker: one button per slot ID listed in
## query.options.  Sends the chosen slot id back to the resolver.
func _show_pokemon_slot_picker(query: TrainerQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	var resolver = _main.manager.trainer_resolver

	if query.options.is_empty():
		push_warning("DialogManager: trainer query has no options — auto-cancelling.")
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose a Pokémon"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for sid_variant in query.options:
		var sid: String = str(sid_variant)
		var inst: PokemonInstance = _main.manager.board_position.get_instance(sid)
		var label_text: String
		if inst == null or inst.card == null:
			label_text = sid
		else:
			label_text = "%s — %s (%d/%d)" % [
				_slot_label(sid), inst.card.display_name,
				inst.current_hp, inst.max_hp,
			]
		var btn := Button.new()
		btn.text = label_text
		var captured_sid := sid
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured_sid)
		)
		vbox.add_child(btn)

	## Cancel button — sends null and the handler treats it as a no-op.
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(null)
	)
	vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


## Hand / generic card-list picker: checkbox list bounded by
## query.min_selections / query.max_selections.  Sends back Array[CardData].
##
## When max_selections = 0, only a Cancel button is offered (used by deck
## searches that whiffed — empty list).
func _show_hand_card_picker(query: TrainerQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null

	var resolver = _main.manager.trainer_resolver
	var max_sel: int = mini(query.max_selections, query.options.size())
	var min_sel: int = mini(query.min_selections, max_sel)
	if query.options.is_empty() or max_sel <= 0:
		resolver.resolve_query([])
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose card(s)"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var selected: Array[int] = []
	var confirm_btn := Button.new()

	var update_confirm := func() -> void:
		confirm_btn.text = "Confirm (%d / %d–%d)" % [selected.size(), min_sel, max_sel]
		confirm_btn.disabled = selected.size() < min_sel or selected.size() > max_sel

	for i in query.options.size():
		var card: CardData = query.options[i] as CardData
		if card == null:
			continue
		var cb := CheckBox.new()
		cb.text = card.display_name
		var idx := i
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(idx):
					selected.append(idx)
			else:
				selected.erase(idx)
			update_confirm.call()
		)
		vbox.add_child(cb)

	confirm_btn.pressed.connect(func() -> void:
		var to_send: Array[CardData] = []
		for idx in selected:
			var c: CardData = query.options[idx] as CardData
			if c != null:
				to_send.append(c)
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(to_send)
	)
	update_confirm.call()
	vbox.add_child(confirm_btn)

	if min_sel == 0:
		var cancel := Button.new()
		cancel.text = "Cancel"
		cancel.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query([])
		)
		vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


## Generic text-choice picker: options are arbitrary strings, returns the
## selected string.  Used for mode prompts (e.g. Energy Recycle System).
func _show_generic_choice(query: TrainerQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.trainer_resolver
	if query.options.is_empty():
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(320, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for opt_variant in query.options:
		var label_text: String = str(opt_variant)
		var btn := Button.new()
		btn.text = label_text
		var captured := label_text
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured)
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(null)
	)
	vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


## Slay-the-Spire-style deck/discard search overlay.
##
## Renders the candidate cards as a scrollable grid of card-art tiles.
## Click a tile to toggle selection (bordered when selected); confirm when
## the count is in [min_selections, max_selections].  A Minimise button
## hides the overlay so the player can inspect the board, with a floating
## Restore button to bring it back.  Selection state is preserved across
## minimise / restore.
##
## Sends back Array[CardData] via trainer_resolver.resolve_query().
func _show_deck_search_grid(query: TrainerQuery) -> void:
	if _deck_search_panel != null:
		_deck_search_panel.queue_free()
		_deck_search_panel = null
	if _deck_search_restore_btn != null:
		_deck_search_restore_btn.queue_free()
		_deck_search_restore_btn = null

	var resolver = _main.manager.trainer_resolver
	var max_sel: int = mini(query.max_selections, query.options.size())
	var min_sel: int = mini(query.min_selections, max_sel)
	if query.options.is_empty() or max_sel <= 0:
		resolver.resolve_query([])
		return

	## Backdrop covers the full HUD with a semi-transparent fade.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	## Centred container holding header / grid / footer.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 720)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	## Header bar.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = query.prompt if query.prompt != "" else "Choose card(s)"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 16)
	header.add_child(status)

	var minimise_btn := Button.new()
	minimise_btn.text = "Minimise"
	header.add_child(minimise_btn)
	vbox.add_child(header)

	## Card grid in a scroll container.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(920, 560)
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	## Footer with Confirm and (optional) Cancel.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel" if min_sel == 0 else "Skip"
	cancel_btn.disabled = min_sel > 0
	footer.add_child(cancel_btn)
	var confirm_btn := Button.new()
	footer.add_child(confirm_btn)
	vbox.add_child(footer)

	var selected: Array[int] = []
	var tiles: Array[Control] = []

	var update_status := func() -> void:
		status.text = "%d / %d–%d selected" % [selected.size(), min_sel, max_sel]
		confirm_btn.text = "Confirm (%d)" % selected.size()
		confirm_btn.disabled = selected.size() < min_sel or selected.size() > max_sel

	## Build a tile per candidate.
	for i in query.options.size():
		var card: CardData = query.options[i] as CardData
		if card == null:
			continue
		var idx := i
		var tile := _make_card_tile(card)
		tile.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton):
				return
			var mb := event as InputEventMouseButton
			if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if selected.has(idx):
				selected.erase(idx)
			else:
				if selected.size() >= max_sel:
					return  ## already at cap
				selected.append(idx)
			_set_tile_selected(tile, selected.has(idx))
			update_status.call()
		)
		grid.add_child(tile)
		tiles.append(tile)

	confirm_btn.pressed.connect(func() -> void:
		var to_send: Array[CardData] = []
		for sel_idx in selected:
			var c: CardData = query.options[sel_idx] as CardData
			if c != null:
				to_send.append(c)
		_close_deck_search()
		resolver.resolve_query(to_send)
	)
	cancel_btn.pressed.connect(func() -> void:
		_close_deck_search()
		resolver.resolve_query([])
	)

	minimise_btn.pressed.connect(func() -> void:
		_minimise_deck_search()
	)

	update_status.call()

	_hud.add_child(backdrop)
	_deck_search_panel = backdrop


## Builds one card tile (TextureRect + name label inside a styled Panel).
## Initial state is unselected. Delegates to the reusable CardTile so the
## visual stays in sync with the card browser and deck builder.
func _make_card_tile(card: CardData) -> Control:
	return CardTile.create_match(card)


## Swaps the tile's stylebox between selected and unselected.
func _set_tile_selected(tile: Control, is_selected: bool) -> void:
	var key: String = "selected_style" if is_selected else "unselected_style"
	if tile.has_meta(key):
		tile.add_theme_stylebox_override("panel", tile.get_meta(key))


## Hide the deck-search panel and show a floating Restore button.  Selection
## state is preserved on the panel because we only set visible = false.
func _minimise_deck_search() -> void:
	if _deck_search_panel == null:
		return
	_deck_search_panel.visible = false
	if _deck_search_restore_btn != null:
		_deck_search_restore_btn.queue_free()
	var btn := Button.new()
	btn.text = "Restore Search ▲"
	btn.add_theme_font_size_override("font_size", 14)
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.position = Vector2(-220, 60)
	btn.size = Vector2(200, 36)
	btn.pressed.connect(func() -> void:
		if _deck_search_panel != null:
			_deck_search_panel.visible = true
		if _deck_search_restore_btn != null:
			_deck_search_restore_btn.queue_free()
			_deck_search_restore_btn = null
	)
	_hud.add_child(btn)
	_deck_search_restore_btn = btn


## Tear down both the panel and the restore button.
func _close_deck_search() -> void:
	if _deck_search_panel != null:
		_deck_search_panel.queue_free()
		_deck_search_panel = null
	if _deck_search_restore_btn != null:
		_deck_search_restore_btn.queue_free()
		_deck_search_restore_btn = null


## Grid-based reorder dialog (PokéNav step 2).  Shows each candidate as a
## card-art tile; click to assign sequential positions (1 = drawn first).
## A position badge appears on selected tiles.  Confirm enabled when every
## tile has been ordered.  Same minimise / restore behaviour as the search
## grid.  Sends back Array[CardData] in chosen order.
func _show_deck_reorder_grid(query: TrainerQuery) -> void:
	if _deck_search_panel != null:
		_deck_search_panel.queue_free()
		_deck_search_panel = null
	if _deck_search_restore_btn != null:
		_deck_search_restore_btn.queue_free()
		_deck_search_restore_btn = null

	var resolver = _main.manager.trainer_resolver
	if query.options.is_empty():
		resolver.resolve_query([])
		return

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(960, 720)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	var title := Label.new()
	title.text = query.prompt if query.prompt != "" else "Click cards in draw order"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 16)
	status.text = "0 / %d ordered" % query.options.size()
	header.add_child(status)
	var minimise_btn := Button.new()
	minimise_btn.text = "Minimise"
	header.add_child(minimise_btn)
	vbox.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(920, 520)
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	var reset_btn := Button.new()
	reset_btn.text = "Reset Order"
	footer.add_child(reset_btn)
	var confirm_btn := Button.new()
	footer.add_child(confirm_btn)
	vbox.add_child(footer)

	var ordered_indices: Array[int] = []
	var tiles: Array[Control] = []
	var badges: Array[Label] = []

	var update_status := func() -> void:
		status.text = "%d / %d ordered" % [ordered_indices.size(), query.options.size()]
		confirm_btn.text = "Confirm (%d)" % ordered_indices.size()
		confirm_btn.disabled = ordered_indices.size() != query.options.size()

	for i in query.options.size():
		var card: CardData = query.options[i] as CardData
		if card == null:
			continue
		var idx := i
		var tile := _make_card_tile(card)

		## Position badge: hidden until clicked.
		var badge := Label.new()
		badge.text = ""
		badge.visible = false
		badge.add_theme_font_size_override("font_size", 28)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color.BLACK)
		badge.add_theme_constant_override("outline_size", 4)
		badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
		badge.position = Vector2(8, 8)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge)
		badges.append(badge)

		tile.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton):
				return
			var mb := event as InputEventMouseButton
			if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
				return
			if ordered_indices.has(idx):
				return  ## click Reset Order to redo
			ordered_indices.append(idx)
			_set_tile_selected(tile, true)
			badge.text = str(ordered_indices.size())
			badge.visible = true
			update_status.call()
		)
		grid.add_child(tile)
		tiles.append(tile)

	confirm_btn.pressed.connect(func() -> void:
		var to_send: Array[CardData] = []
		for ord_idx in ordered_indices:
			var c: CardData = query.options[ord_idx] as CardData
			if c != null:
				to_send.append(c)
		_close_deck_search()
		resolver.resolve_query(to_send)
	)

	reset_btn.pressed.connect(func() -> void:
		ordered_indices.clear()
		for j in tiles.size():
			_set_tile_selected(tiles[j], false)
			badges[j].visible = false
		update_status.call()
	)

	minimise_btn.pressed.connect(func() -> void:
		_minimise_deck_search()
	)

	update_status.call()

	_hud.add_child(backdrop)
	_deck_search_panel = backdrop


## Energy-on-Pokémon picker: lists each EnergyCardData in query.options
## (energies attached to whichever Pokémon the handler chose previously).
## Sends back the chosen EnergyCardData (single).
func _show_energy_on_pokemon_picker(query: TrainerQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.trainer_resolver
	if query.options.is_empty():
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose an Energy"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for c_variant in query.options:
		var card: CardData = c_variant as CardData
		if card == null:
			continue
		var info := MatchUIUtils.energy_label_and_color(card)
		var btn := Button.new()
		btn.text = info["label"]
		btn.add_theme_color_override("font_color", info["color"])
		var captured: CardData = card
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured)
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(null)
	)
	vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


## Top-of-deck reorder picker: shows the cards in query.options face-up; the
## player clicks them in their desired DRAW order (first click = next drawn).
## Sends back Array[CardData] in chosen draw order.
func _show_top_of_deck_reorder(query: TrainerQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.trainer_resolver
	if query.options.is_empty():
		resolver.resolve_query([])
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(420, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Click cards in draw order"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.text = "0 / %d picked" % query.options.size()
	vbox.add_child(status)

	var ordered: Array[CardData] = []
	var buttons: Array[Button] = []

	for i in query.options.size():
		var card: CardData = query.options[i] as CardData
		var btn := Button.new()
		btn.text = "%s" % (card.display_name if card != null else "?")
		var captured: CardData = card
		var captured_btn: Button = btn
		btn.pressed.connect(func() -> void:
			if ordered.has(captured) or captured == null:
				return
			ordered.append(captured)
			captured_btn.text = "%d. %s" % [ordered.size(), captured.display_name]
			captured_btn.disabled = true
			status.text = "%d / %d picked" % [ordered.size(), query.options.size()]
			if ordered.size() == query.options.size():
				panel.queue_free()
				_attack_dialog = null
				resolver.resolve_query(ordered.duplicate())
		)
		vbox.add_child(btn)
		buttons.append(btn)

	## Reset button so the player can start over if they misclicked.
	var reset := Button.new()
	reset.text = "Reset Order"
	reset.pressed.connect(func() -> void:
		ordered.clear()
		for j in buttons.size():
			var b := buttons[j]
			var c: CardData = query.options[j] as CardData
			b.text = c.display_name if c != null else "?"
			b.disabled = false
		status.text = "0 / %d picked" % query.options.size()
	)
	vbox.add_child(reset)

	_hud.add_child(panel)
	_attack_dialog = panel


## ─────────────────────────────────────────────────────────────────────────
## Wave 17+: attack-side query routing.
##
## Mirrors on_trainer_query_requested but resolves through
## _main.manager.attack_resolver.resolve_query. Wired from match.gd.
## ─────────────────────────────────────────────────────────────────────────

func on_attack_query_requested(query: AttackQuery) -> void:
	match query.kind:
		AttackQuery.Kind.MAY_ABILITY, \
		AttackQuery.Kind.MAY_CONFIRM, \
		AttackQuery.Kind.MAY_DISCARD_FOR_BONUS:
			_show_attack_yesno(query)
		AttackQuery.Kind.CHOOSE_DISCARD_COUNT, \
		AttackQuery.Kind.CHOOSE_ENERGY_DISCARD, \
		AttackQuery.Kind.CHOOSE_ENERGY_FROM_HAND:
			_show_attack_energy_multi_picker(query)
		AttackQuery.Kind.CHOOSE_ENERGY_TYPE:
			_show_attack_energy_type_picker(query)
		AttackQuery.Kind.CHOOSE_BENCH_TARGET:
			_show_attack_slot_picker(query)
		AttackQuery.Kind.GENERIC_CHOICE:
			_show_attack_generic_choice(query)
		AttackQuery.Kind.CHOOSE_OPP_HAND_BLIND:
			_show_opp_hand_blind_picker(query)
		AttackQuery.Kind.CHOOSE_OPP_HAND_OPEN:
			_show_opp_hand_open_picker(query)
		AttackQuery.Kind.CHOOSE_ATTACK_FROM_CARDS:
			_show_attack_from_cards_picker(query)
		_:
			push_warning("DialogManager: unhandled attack query kind %d" % query.kind)
			_main.manager.attack_resolver.resolve_query(null)


## Yes/No prompt — MAY_CONFIRM / MAY_ABILITY / MAY_DISCARD_FOR_BONUS.
## Sends `true` for Yes, `false` for No.
func _show_attack_yesno(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Confirm?"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var yes := Button.new()
	yes.text = "Yes"
	yes.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(true)
	)
	vbox.add_child(yes)

	var no := Button.new()
	no.text = "No"
	no.pressed.connect(func() -> void:
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(false)
	)
	vbox.add_child(no)

	_hud.add_child(panel)
	_attack_dialog = panel


## Slot picker for attack-side CHOOSE_BENCH_TARGET. Returns the chosen slot id.
## Mirrors _show_pokemon_slot_picker but resolves through attack_resolver.
func _show_attack_slot_picker(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	if query.options.is_empty():
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose a target"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for sid_variant in query.options:
		var sid: String = str(sid_variant)
		var inst: PokemonInstance = _main.manager.board_position.get_instance(sid)
		var label_text: String
		if inst == null or inst.card == null:
			label_text = sid
		else:
			label_text = "%s — %s (%d/%d)" % [
				_slot_label(sid), inst.card.display_name,
				inst.current_hp, inst.max_hp,
			]
		var btn := Button.new()
		btn.text = label_text
		var captured_sid := sid
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured_sid)
		)
		vbox.add_child(btn)

	_hud.add_child(panel)
	_attack_dialog = panel


## Energy-multi-picker — CHOOSE_DISCARD_COUNT / CHOOSE_ENERGY_DISCARD /
## CHOOSE_ENERGY_FROM_HAND. query.options is Array[CardData] (energies on
## attacker or in hand). Confirm enables when count is in [min, max].
## Returns Array[CardData] of chosen energies.
func _show_attack_energy_multi_picker(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	var max_sel: int = mini(query.max_selections, query.options.size())
	var min_sel: int = mini(query.min_selections, max_sel)
	if query.options.is_empty() or max_sel <= 0:
		resolver.resolve_query([] as Array[CardData])
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose energy"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var selected: Array[int] = []
	var confirm_btn := Button.new()

	var update_confirm := func() -> void:
		confirm_btn.text = "Confirm (%d / %d–%d)" % [selected.size(), min_sel, max_sel]
		confirm_btn.disabled = selected.size() < min_sel or selected.size() > max_sel

	for i in query.options.size():
		var card: CardData = query.options[i] as CardData
		if card == null:
			continue
		var cb := CheckBox.new()
		cb.text = card.display_name
		var idx := i
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(idx):
					selected.append(idx)
			else:
				selected.erase(idx)
			update_confirm.call()
		)
		vbox.add_child(cb)

	confirm_btn.pressed.connect(func() -> void:
		var to_send: Array[CardData] = []
		for idx in selected:
			var c: CardData = query.options[idx] as CardData
			if c != null:
				to_send.append(c)
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(to_send)
	)
	update_confirm.call()
	vbox.add_child(confirm_btn)

	if min_sel == 0:
		var cancel := Button.new()
		cancel.text = "Cancel"
		cancel.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query([] as Array[CardData])
		)
		vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


## Energy-type picker — CHOOSE_ENERGY_TYPE. query.options is Array[String]
## of type names ("FIRE", "LIGHTNING", ...). Returns the chosen String.
func _show_attack_energy_type_picker(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	if query.options.is_empty():
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose energy type"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for opt in query.options:
		var type_name: String = str(opt)
		var btn := Button.new()
		btn.text = type_name
		var captured := type_name
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured)
		)
		vbox.add_child(btn)

	_hud.add_child(panel)
	_attack_dialog = panel


## Generic string-choice picker — CHOOSE_ORDER / GENERIC_CHOICE on attack side.
## Mirrors _show_generic_choice but for attack queries.
func _show_attack_generic_choice(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver
	if query.options.is_empty():
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(360, 80)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for opt in query.options:
		var label_text: String = str(opt)
		var btn := Button.new()
		btn.text = label_text
		var captured: Variant = opt
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured)
		)
		vbox.add_child(btn)

	_hud.add_child(panel)
	_attack_dialog = panel


## ─────────────────────────────────────────────────────────────────────────
## Wave 19: opp-hand & attack-from-cards pickers.
## ─────────────────────────────────────────────────────────────────────────

## Blind opp-hand picker — N face-down card-back buttons. Selecting one
## reveals it to the attacker. Min/max selections from query bounds.
## query.options is an int (opp hand size) OR Array (the opp hand snapshot).
## Returns Array[int] of selected indices.
func _show_opp_hand_blind_picker(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	var size: int = 0
	if not query.options.is_empty():
		var first: Variant = query.options[0]
		if first is int:
			size = int(first)
		elif first is Array:
			size = (first as Array).size()
		else:
			size = query.options.size()
	if size <= 0:
		resolver.resolve_query([] as Array[int])
		return

	var max_sel: int = mini(query.max_selections, size)
	var min_sel: int = mini(query.min_selections, max_sel)

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(420, 120)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Pick %d card(s) blindly" % min_sel
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var row := HBoxContainer.new()
	vbox.add_child(row)

	var selected: Array[int] = []
	var buttons: Array[Button] = []
	var confirm_btn := Button.new()

	var update_confirm := func() -> void:
		confirm_btn.text = "Confirm (%d / %d–%d)" % [selected.size(), min_sel, max_sel]
		confirm_btn.disabled = selected.size() < min_sel or selected.size() > max_sel

	for i in size:
		var btn := Button.new()
		btn.text = "?"
		btn.custom_minimum_size = Vector2(36, 56)
		var idx := i
		btn.toggle_mode = true
		btn.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(idx):
					selected.append(idx)
			else:
				selected.erase(idx)
			update_confirm.call()
		)
		row.add_child(btn)
		buttons.append(btn)

	confirm_btn.pressed.connect(func() -> void:
		var to_send: Array[int] = selected.duplicate()
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(to_send)
	)
	update_confirm.call()
	vbox.add_child(confirm_btn)

	_hud.add_child(panel)
	_attack_dialog = panel


## Open opp-hand picker — show opp hand as a card grid with checkboxes.
## query.options is Array[CardData]; query.filter is Dictionary (e.g.
## {"supporter_only": true}). Returns Array[CardData] of selected cards.
func _show_opp_hand_open_picker(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	if query.options.is_empty():
		resolver.resolve_query([] as Array[CardData])
		return

	var supporter_only: bool = bool(query.filter.get("supporter_only", false))

	var max_sel: int = mini(query.max_selections, query.options.size())
	var min_sel: int = mini(query.min_selections, max_sel)

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(420, 200)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Look at opponent's hand"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	var selected: Array[int] = []
	var confirm_btn := Button.new()

	var update_confirm := func() -> void:
		confirm_btn.text = "Confirm (%d / %d–%d)" % [selected.size(), min_sel, max_sel]
		confirm_btn.disabled = selected.size() < min_sel or selected.size() > max_sel

	for i in query.options.size():
		var card: CardData = query.options[i] as CardData
		if card == null:
			continue
		var cb := CheckBox.new()
		var disabled := false
		if supporter_only:
			disabled = not _is_supporter(card)
		cb.text = card.display_name + ("  (Supporter)" if _is_supporter(card) else "")
		cb.disabled = disabled
		var idx := i
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				if not selected.has(idx):
					selected.append(idx)
			else:
				selected.erase(idx)
			update_confirm.call()
		)
		vbox.add_child(cb)

	confirm_btn.pressed.connect(func() -> void:
		var to_send: Array[CardData] = []
		for idx in selected:
			var c: CardData = query.options[idx] as CardData
			if c != null:
				to_send.append(c)
		panel.queue_free()
		_attack_dialog = null
		resolver.resolve_query(to_send)
	)
	update_confirm.call()
	vbox.add_child(confirm_btn)

	if min_sel == 0:
		var cancel := Button.new()
		cancel.text = "Cancel"
		cancel.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query([] as Array[CardData])
		)
		vbox.add_child(cancel)

	_hud.add_child(panel)
	_attack_dialog = panel


## Attack-from-cards picker — vertical list of buttons "Card Name — Attack
## Name (N dmg)". query.options is Array[Dictionary] with shape
## {"card": PokemonCardData, "index": int, "label": String}. Returns the
## chosen dict.
func _show_attack_from_cards_picker(query: AttackQuery) -> void:
	if _attack_dialog != null:
		_attack_dialog.queue_free()
		_attack_dialog = null
	var resolver = _main.manager.attack_resolver

	if query.options.is_empty():
		resolver.resolve_query(null)
		return

	var panel := MatchUIUtils.make_panel()
	panel.custom_minimum_size = Vector2(420, 120)
	var vbox := panel.get_child(0) as VBoxContainer

	var header := Label.new()
	header.text = query.prompt if query.prompt != "" else "Choose an attack"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	vbox.add_child(header)

	for opt in query.options:
		if not (opt is Dictionary):
			continue
		var entry: Dictionary = opt
		var btn := Button.new()
		btn.text = str(entry.get("label", "?"))
		var captured := entry
		btn.pressed.connect(func() -> void:
			panel.queue_free()
			_attack_dialog = null
			resolver.resolve_query(captured)
		)
		vbox.add_child(btn)

	_hud.add_child(panel)
	_attack_dialog = panel


static func _is_supporter(card: CardData) -> bool:
	if not (card is TrainerCardData):
		return false
	var tc := card as TrainerCardData
	return tc.trainer_kind == TrainerCardData.TrainerKind.SUPPORTER


## Pretty-prints a slot id like "p0_active1" → "Active 1".
static func _slot_label(slot_id: String) -> String:
	if slot_id.contains("active1"): return "Active 1"
	if slot_id.contains("active2"): return "Active 2"
	if slot_id.contains("bench1"):  return "Bench 1"
	if slot_id.contains("bench2"):  return "Bench 2"
	if slot_id.contains("bench3"):  return "Bench 3"
	if slot_id.contains("bench4"):  return "Bench 4"
	if slot_id.contains("bench5"):  return "Bench 5"
	return slot_id
