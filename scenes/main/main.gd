extends Node3D
## Main scene — camera, lighting, input raycasting, turn engine, and game wiring.

@onready var camera: Camera3D = $Camera3D
@onready var board: Board = $Board
@onready var player_hand: Hand = $Board/PlayerHand
@onready var opp_hand: Hand = $Board/OppHand

## HUD elements
@onready var phase_label: Label = $HUD/TopBar/PhaseLabel
@onready var end_turn_button: Button = $HUD/TopBar/EndTurnButton
@onready var game_log: RichTextLabel = $HUD/LogPanel/GameLog
@onready var card_zoom_popup: CardZoomPopup = $HUD/CardZoomPopup

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")

## Perspective — 0 = player 0 (near side), 1 = player 1 (far side)
var controlling_player: int = 0
var _p0_cam_transform: Transform3D
var _p1_cam_transform: Transform3D

## Drag state
var dragged_card: Card = null
var hovered_card: Card = null
var _source_zone: DropZone = null

## Card inspector popup
var _card_popup: PanelContainer = null
var _popup_art: TextureRect = null
var _popup_name_label: Label = null
var _popup_type_label: Label = null
var _popup_details_label: Label = null

## Turn engine
@onready var turn_controller: TurnController = TurnControllerSingleton
var game_state: GameState

## The Y height of the table surface for drag plane intersection
const TABLE_Y := 0.0
const DRAG_PLANE := Plane(Vector3.UP, 0.0)

@export var test_hand_size: int = 5

func _ready() -> void:
	player_hand.card_played.connect(_on_card_played)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	## Store camera transforms for both perspectives.
	_p0_cam_transform = camera.transform
	_p1_cam_transform = Transform3D(
		Basis(Vector3.UP, PI) * camera.basis,
		camera.position.rotated(Vector3.UP, PI)
	)

	## Add perspective-switch button to the HUD top bar.
	var switch_btn := Button.new()
	switch_btn.text = "Switch Perspective"
	switch_btn.pressed.connect(_switch_perspective)
	$HUD/TopBar.add_child(switch_btn)

	## Set up game state
	game_state = GameState.new(2, 2, 4)
	turn_controller.set_state(game_state)
	board.configure_slots(game_state.board.num_active_slots, game_state.board.max_bench_size)

	turn_controller.phase_changed.connect(_on_phase_changed)
	turn_controller.action_rejected.connect(_on_action_rejected)
	turn_controller.action_committed.connect(_on_action_committed)
	turn_controller.log_message.connect(_on_turn_log)
	game_state.board.card_moved.connect(_on_board_card_moved)

	_on_phase_changed(game_state.phase)
	_deal_starting_hand(test_hand_size)
	_spawn_deck_visual(0)
	_spawn_deck_visual(1)
	_build_card_popup()


func _deal_starting_hand(count: int) -> void:
	print("Dealing %d cards. Hand position: %s" % [count, str(player_hand.global_position)])

	# Build a randomised test deck for each player.
	game_state.setup_player_deck(0, TestDeckFactory.build_deck(20))
	game_state.setup_player_deck(1, TestDeckFactory.build_deck(20))
	game_state.draw_starting_hand(0, count)
	game_state.draw_starting_hand(1, count)

	var p0_from: Vector3 = board.get_zone_by_name("Deck").global_position + Vector3(0, 0.1, 0)
	for inst in game_state.board.get_hand_cards(0):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst)
		card.drag_started.connect(_on_card_drag_started)
		card.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card_animated(card, p0_from)

	var p1_from: Vector3 = board.get_zone_by_name("Opp Deck").global_position + Vector3(0, 0.1, 0)
	for inst in game_state.board.get_hand_cards(1):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst)
		card.face_down = true
		opp_hand.add_card_animated(card, p1_from)


func _deck_zone_name(pid: int) -> String:
	return "Deck" if pid == 0 else "Opp Deck"


func _spawn_deck_visual(pid: int) -> void:
	var deck_zone := board.get_zone_by_name(_deck_zone_name(pid))
	if deck_zone == null:
		return
	for inst in game_state.board.get_zone("p%d_deck" % pid):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst as CardInstance)
		card.face_down = true
		board.add_child(card)
		deck_zone.receive_card(card)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		## Any click dismisses the popup (right-click may also re-open it below).
		if mb.pressed and _card_popup != null and _card_popup.visible:
			_card_popup.visible = false

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				card_zoom_popup.hide_popup()
				_try_pick_card(mb.position)
			else:
				_try_drop_card()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click(mb.position)

	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE and _card_popup != null:
			_card_popup.visible = false

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragged_card:
			_move_dragged_card(mm.position)
		else:
			_update_hover(mm.position)


func _try_pick_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card:
		if card.face_down:
			return
		_source_zone = board.get_zone_containing(card)
		if _source_zone:
			_source_zone.remove_card(card)
		dragged_card = card
		card.start_drag()


func _try_drop_card() -> void:
	if not dragged_card:
		return
	var card := dragged_card
	var from_zone := _source_zone
	dragged_card = null
	_source_zone = null
	card.end_drag()

	var inst := card.card_instance
	if inst == null:
		_snap_back(card, from_zone)
		return

	var target_drop_zone := board.get_zone_at_position(card.global_position)
	var action := _build_play_action(inst, target_drop_zone)

	if action == null:
		_snap_back(card, from_zone)
		return

	var result := action.validate(game_state)
	if not result.ok:
		_log_line(result.reason)
		_snap_back(card, from_zone)
		return

	action.apply(game_state)
	_apply_card_visual(card, from_zone, inst, target_drop_zone)
	_log_line("[P%d][%s] %s" % [
		controlling_player, TurnPhase.phase_to_string(game_state.phase), action.description()
	])


## Builds the appropriate GameAction for dropping inst onto drop_zone.
## Returns null when no valid play exists for this card+zone combination.
func _build_play_action(inst: CardInstance, drop_zone: DropZone) -> GameAction:
	var PID := controlling_player

	if inst.data is PokemonCardData:
		var pdata := inst.data as PokemonCardData
		var slot := _zone_name_to_pokemon_slot(drop_zone)
		if slot == "":
			return null
		if pdata.stage == PokemonCardData.Stage.BASIC:
			if drop_zone != null and not drop_zone.held_cards.is_empty():
				return null
			return ActionPlayBasicPokemon.new(PID, inst, slot)
		else:
			var target := _instance_in_drop_zone(drop_zone)
			if target == null:
				return null
			return ActionEvolvePokemon.new(PID, inst, target)

	elif inst.data is EnergyCardData:
		var target := _instance_in_drop_zone(drop_zone)
		if target == null:
			return null
		return ActionAttachEnergy.new(PID, inst, target)

	elif inst.data is TrainerCardData:
		var tdata := inst.data as TrainerCardData
		match tdata.trainer_kind:
			TrainerCardData.TrainerKind.ITEM:
				return ActionPlayTrainerItem.new(PID, inst)
			TrainerCardData.TrainerKind.SUPPORTER:
				return ActionPlayTrainerSupporter.new(PID, inst)
			TrainerCardData.TrainerKind.STADIUM:
				return ActionPlayTrainerStadium.new(PID, inst)
			TrainerCardData.TrainerKind.TOOL:
				var target := _instance_in_drop_zone(drop_zone)
				if target == null:
					return null
				return ActionPlayTrainerTool.new(PID, inst, target)

	return null


## After a valid action has been applied, moves the card node to its new home.
func _apply_card_visual(
	card: Card,
	from_zone: DropZone,
	inst: CardInstance,
	target_drop_zone: DropZone
) -> void:
	# Detach from hand if it was dragged from there.
	if from_zone == null:
		if player_hand.cards.has(card):
			player_hand.remove_card(card)
		elif opp_hand.cards.has(card):
			opp_hand.remove_card(card)
		board.add_child(card)

	var logic_location := game_state.board.find_card_location(inst)

	if "active" in logic_location or "bench" in logic_location:
		# For evolution: remove the prior stage card node from the zone first.
		if inst.prior_stage != null and target_drop_zone != null:
			_remove_prior_stage_visual(target_drop_zone, inst.prior_stage)
		if target_drop_zone != null:
			target_drop_zone.receive_card(card)
			# Refresh attachment icons — needed when evolving a Pokemon that has energy/tools.
			if inst.prior_stage != null:
				card.update_attachment_icons()

	elif "discard" in logic_location:
		var discard := board.get_zone_by_name("Discard")
		if discard != null:
			discard.receive_card(card)

	elif logic_location == "stadium":
		# No dedicated visual zone for the stadium — snap to centre table.
		card.set_home(Vector3(0.0, 0.05, 0.0), Vector3.ZERO, 0)
		card.return_to_home()

	else:
		# Card removed from all board zones (energy or tool attached to pokemon).
		card.queue_free()
		# Refresh the attachment icons on the target Pokemon's card node.
		if target_drop_zone != null and not target_drop_zone.held_cards.is_empty():
			(target_drop_zone.held_cards[0] as Card).update_attachment_icons()


## Removes and frees the Card node for prior_inst from a visual DropZone.
func _remove_prior_stage_visual(zone: DropZone, prior_inst: CardInstance) -> void:
	for held in zone.held_cards:
		if held.card_instance == prior_inst:
			zone.remove_card(held)
			held.queue_free()
			return


## Returns "active" or "bench" for the controlling player's zones, "" for everything else.
func _zone_name_to_pokemon_slot(drop_zone: DropZone) -> String:
	if drop_zone == null:
		return ""
	var zn := drop_zone.zone_name
	if controlling_player == 0:
		if zn == "Active" or zn.begins_with("Active "):
			return "active"
		if zn.begins_with("Bench"):
			return "bench"
	else:
		if zn == "Opp Active" or zn.begins_with("Opp Active "):
			return "active"
		if zn.begins_with("Opp Bench"):
			return "bench"
	return ""


## Returns the CardInstance of the first card held in a visual DropZone.
func _instance_in_drop_zone(drop_zone: DropZone) -> CardInstance:
	if drop_zone == null or drop_zone.held_cards.is_empty():
		return null
	return drop_zone.held_cards[0].card_instance


func _snap_back(card: Card, from_zone: DropZone) -> void:
	if from_zone != null:
		from_zone.receive_card(card)
	else:
		card.snap_to_home()


func _move_dragged_card(screen_pos: Vector2) -> void:
	var world_pos: Variant = _screen_to_table(screen_pos)
	if world_pos != null:
		dragged_card.move_to_drag_position(world_pos as Vector3)


func _update_hover(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card != hovered_card:
		if hovered_card:
			hovered_card.set_hovered(false)
		hovered_card = card
		if hovered_card:
			hovered_card.set_hovered(true)


func _raycast_card(screen_pos: Vector2) -> Card:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0, 1)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	var body: Object = result.collider
	if body is StaticBody3D and body.get_parent() is Card:
		return body.get_parent() as Card
	return null


func _try_zoom_card(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card and not card.face_down:
		card_zoom_popup.show_card(card)
	else:
		card_zoom_popup.hide_popup()


func _screen_to_table(screen_pos: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit: Variant = DRAG_PLANE.intersects_ray(from, dir)
	return hit


func _on_card_played(_card: Card) -> void:
	pass  ## Placement is handled in _try_drop_card.


func _on_card_drag_started(card: Card) -> void:
	if game_state.phase == TurnPhase.Phase.MAIN:
		_highlight_valid_zones_for(card)


func _on_card_drag_ended(_card: Card) -> void:
	board.clear_highlights()


# ---------------------------------------------------------------------------
# Card inspector popup — fixed panel on the left side of the screen.
# ---------------------------------------------------------------------------

func _build_card_popup() -> void:
	_card_popup = PanelContainer.new()
	_card_popup.visible = false
	_card_popup.custom_minimum_size = Vector2(270, 0)
	_card_popup.position = Vector2(10, 50)
	_card_popup.gui_input.connect(_on_popup_gui_input)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_card_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	_popup_art = TextureRect.new()
	_popup_art.custom_minimum_size = Vector2(246, 344)
	_popup_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_popup_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(_popup_art)

	vbox.add_child(HSeparator.new())

	_popup_name_label = Label.new()
	_popup_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_popup_name_label)

	_popup_type_label = Label.new()
	_popup_type_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.6))
	vbox.add_child(_popup_type_label)

	vbox.add_child(HSeparator.new())

	_popup_details_label = Label.new()
	_popup_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_popup_details_label.custom_minimum_size = Vector2(246, 0)
	vbox.add_child(_popup_details_label)

	$HUD.add_child(_card_popup)


func _handle_right_click(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null or card.face_down or card.card_instance == null:
		return
	_populate_card_popup(card.card_instance)
	_card_popup.visible = true


func _populate_card_popup(inst: CardInstance) -> void:
	_popup_art.texture = inst.data.art

	_popup_name_label.text = inst.data.display_name

	var type_str := ""
	var details := ""

	if inst.data is PokemonCardData:
		var pdata := inst.data as PokemonCardData
		var stage_label := ""
		match pdata.stage:
			PokemonCardData.Stage.BASIC:   stage_label = "Basic"
			PokemonCardData.Stage.STAGE1:  stage_label = "Stage 1"
			PokemonCardData.Stage.STAGE2:  stage_label = "Stage 2"
		type_str = "Pokemon — %s" % stage_label

		details = "HP: %d   Type: %s" % [
			pdata.hp_max,
			PokemonCardData.energy_type_to_string(pdata.pokemon_type)
		]
		if pdata.evolves_from != "":
			details += "\nEvolves from: %s" % pdata.evolves_from
		if pdata.weakness != PokemonCardData.EnergyType.NONE:
			details += "\nWeakness: %s ×2" % PokemonCardData.energy_type_to_string(pdata.weakness)
		if pdata.resistance != PokemonCardData.EnergyType.NONE:
			details += "\nResistance: %s -30" % PokemonCardData.energy_type_to_string(pdata.resistance)
		details += "\nRetreat: %d" % pdata.retreat_cost
		if inst.damage > 0:
			details += "\nDamage taken: %d  (%d HP left)" % [inst.damage, inst.hp_remaining()]
		for atk in pdata.attacks:
			details += "\n\n[%s]  %d dmg" % [atk.name, atk.base_damage]
			if atk.text != "":
				details += "\n%s" % atk.text

	elif inst.data is EnergyCardData:
		var edata := inst.data as EnergyCardData
		type_str = "Energy"
		details = "Type: %s\nProvides: %d" % [
			PokemonCardData.energy_type_to_string(edata.energy_type),
			edata.provides
		]

	elif inst.data is TrainerCardData:
		var tdata := inst.data as TrainerCardData
		var kind_label := ""
		match tdata.trainer_kind:
			TrainerCardData.TrainerKind.ITEM:      kind_label = "Item"
			TrainerCardData.TrainerKind.SUPPORTER: kind_label = "Supporter"
			TrainerCardData.TrainerKind.STADIUM:   kind_label = "Stadium"
			TrainerCardData.TrainerKind.TOOL:      kind_label = "Tool"
		type_str = "Trainer — %s" % kind_label

	if inst.data.rules_text != "":
		details += "\n\n%s" % inst.data.rules_text

	## Show attached energy/tools when inspecting a board Pokemon.
	if not inst.attached_energy.is_empty():
		var names := ""
		for e in inst.attached_energy:
			if e.data != null:
				names += (", " if names != "" else "") + e.data.display_name
		details += "\nAttached energy: %s" % names
	if not inst.attached_tools.is_empty():
		var names := ""
		for t in inst.attached_tools:
			if t.data != null:
				names += (", " if names != "" else "") + t.data.display_name
		details += "\nTool: %s" % names

	_popup_type_label.text = type_str
	_popup_details_label.text = details.strip_edges()


func _on_popup_gui_input(event: InputEvent) -> void:
	## Clicking anywhere on the popup dismisses it.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_card_popup.visible = false


## Highlights only the zones that are valid drop targets for this card.
func _highlight_valid_zones_for(card: Card) -> void:
	board.clear_highlights()
	var inst := card.card_instance
	if inst == null:
		return

	if inst.data is PokemonCardData:
		var pdata := inst.data as PokemonCardData
		if pdata.stage == PokemonCardData.Stage.BASIC:
			_highlight_pokemon_play_zones()
		else:
			_highlight_evolution_zones_for(inst)

	elif inst.data is EnergyCardData:
		_highlight_zones_with_pokemon()

	elif inst.data is TrainerCardData:
		var tdata := inst.data as TrainerCardData
		if tdata.trainer_kind == TrainerCardData.TrainerKind.TOOL:
			_highlight_zones_with_pokemon()
		# Item / Supporter / Stadium need no specific drop target.


## Returns visual zone names for the controlling player's active slots.
func _player_active_zone_names() -> Array[String]:
	var names: Array[String] = []
	var prefix := "" if controlling_player == 0 else "Opp "
	for i in range(game_state.board.num_active_slots):
		names.append(prefix + ("Active" if i == 0 else "Active %d" % (i + 1)))
	return names


## Returns visual zone names for the controlling player's bench slots.
func _player_bench_zone_names() -> Array[String]:
	var names: Array[String] = []
	var prefix := "" if controlling_player == 0 else "Opp "
	for i in range(1, game_state.board.max_bench_size + 1):
		names.append(prefix + "Bench %d" % i)
	return names


## Highlights empty Active and non-full Bench zones for the controlling player.
func _highlight_pokemon_play_zones() -> void:
	for zone_name in _player_active_zone_names():
		var active := board.get_zone_by_name(zone_name)
		if active != null and active.held_cards.is_empty():
			active.set_highlighted(true)
	for zone_name in _player_bench_zone_names():
		var bench := board.get_zone_by_name(zone_name)
		if bench != null and bench.held_cards.size() < bench.max_cards:
			bench.set_highlighted(true)


## Highlights Active / Bench zones that hold a valid prior-stage target.
func _highlight_evolution_zones_for(inst: CardInstance) -> void:
	if not (inst.data is PokemonCardData):
		return
	var pdata := inst.data as PokemonCardData
	var candidate_names := _player_active_zone_names() + _player_bench_zone_names()
	for zone_name in candidate_names:
		var zone := board.get_zone_by_name(zone_name)
		if zone == null or zone.held_cards.is_empty():
			continue
		var target_inst := zone.held_cards[0].card_instance
		if target_inst == null or not (target_inst.data is PokemonCardData):
			continue
		if (target_inst.data as PokemonCardData).name_slug == pdata.evolves_from:
			zone.set_highlighted(true)


## Highlights Active / Bench zones that currently hold a Pokemon.
func _highlight_zones_with_pokemon() -> void:
	var candidate_names := _player_active_zone_names() + _player_bench_zone_names()
	for zone_name in candidate_names:
		var zone := board.get_zone_by_name(zone_name)
		if zone == null or zone.held_cards.is_empty():
			continue
		var target_inst := zone.held_cards[0].card_instance
		if target_inst != null and target_inst.data is PokemonCardData:
			zone.set_highlighted(true)


## Toggles control between player 0 (near side) and player 1 (far side).
func _switch_perspective() -> void:
	controlling_player = 1 - controlling_player
	camera.transform = _p0_cam_transform if controlling_player == 0 else _p1_cam_transform
	_configure_hand_for_player(player_hand, controlling_player == 0)
	_configure_hand_for_player(opp_hand, controlling_player == 1)
	_flip_board_card_rotations()


## Toggles the perspective_y_rotation on every board zone (excluding decks) so
## that all currently held cards — and any cards placed in future — face the camera.
func _flip_board_card_rotations() -> void:
	for zone in board.all_zones:
		if zone.zone_name == "Deck" or zone.zone_name == "Opp Deck":
			continue
		zone.perspective_y_rotation = fmod(zone.perspective_y_rotation + PI, TAU)
		zone.relayout()


## Sets face-down state and drag wiring for all cards in a hand.
func _configure_hand_for_player(hand: Hand, is_controlling: bool) -> void:
	for card in hand.cards:
		card.face_down = not is_controlling
		if is_controlling:
			if not card.drag_started.is_connected(_on_card_drag_started):
				card.drag_started.connect(_on_card_drag_started)
			if not card.drag_ended.is_connected(_on_card_drag_ended):
				card.drag_ended.connect(_on_card_drag_ended)
		else:
			if card.drag_started.is_connected(_on_card_drag_started):
				card.drag_started.disconnect(_on_card_drag_started)
			if card.drag_ended.is_connected(_on_card_drag_ended):
				card.drag_ended.disconnect(_on_card_drag_ended)


## Turn engine handlers
func _on_end_turn_pressed() -> void:
	var actor := turn_controller.state.current_player_id
	if game_state.phase == TurnPhase.Phase.END:
		turn_controller.end_turn(actor)
	else:
		turn_controller.next_phase(actor)


func _on_phase_changed(phase: int) -> void:
	if phase_label:
		phase_label.text = "Phase: %s" % TurnPhase.phase_to_string(phase)
	## Turn 1 hand is dealt manually in _deal_starting_hand; skip auto-draw.
	if phase == TurnPhase.Phase.START and game_state.turn_number > 1:
		turn_controller.request_action(
			ActionDrawCard.new(game_state.current_player_id, 1)
		)


func _on_board_card_moved(inst: CardInstance, from_zone: String, to_zone: String) -> void:
	if from_zone.ends_with("_deck") and to_zone.ends_with("_hand"):
		var pid := int(from_zone.substr(1).split("_")[0])
		_sync_deck_draw_visual(inst, pid)


func _sync_deck_draw_visual(inst: CardInstance, pid: int) -> void:
	var deck_zone := board.get_zone_by_name(_deck_zone_name(pid))
	if deck_zone == null:
		return
	var drawn_card: Card = null
	for card in deck_zone.held_cards:
		if card.card_instance == inst:
			drawn_card = card
			break
	if drawn_card == null:
		return
	## Save world position before detaching from the scene tree.
	var from_global := drawn_card.global_position
	deck_zone.remove_card(drawn_card)
	board.remove_child(drawn_card)
	if pid == 0:
		drawn_card.face_down = controlling_player != 0
		if controlling_player == 0:
			drawn_card.drag_started.connect(_on_card_drag_started)
			drawn_card.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card_animated(drawn_card, from_global)
	else:
		drawn_card.face_down = controlling_player != 1
		if controlling_player == 1:
			drawn_card.drag_started.connect(_on_card_drag_started)
			drawn_card.drag_ended.connect(_on_card_drag_ended)
		opp_hand.add_card_animated(drawn_card, from_global)


func _on_action_rejected(action: GameAction, reason: String) -> void:
	_log_line("[REJECT] %s (%s)" % [action.description(), reason])


func _on_action_committed(_action: GameAction) -> void:
	pass


func _on_turn_log(text: String) -> void:
	_log_line(text)


func _log_line(text: String) -> void:
	if game_log:
		game_log.append_text(text + "\n")
