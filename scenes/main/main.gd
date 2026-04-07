extends Node3D
## Main scene — camera, input, HUD, and game orchestration.
##
## Startup flow:
##   _ready()  →  _show_setup_dialog()
##             →  _on_setup_confirmed()  →  _start_game()
##
## Player Mode:  Human plays P0; CpuPlayer automates P1.
## Developer Mode: No CPU.  At turn-end the perspective automatically flips
##                 so the developer can play both sides.

@onready var camera:      Camera3D = $Camera3D
@onready var board:       Board    = $Board
@onready var player_hand: Hand     = $Board/PlayerHand
@onready var opp_hand:    Hand     = $Board/OppHand

## HUD elements created in the scene.
@onready var phase_label:     Label         = $HUD/TopBar/PhaseLabel
@onready var end_turn_button: Button        = $HUD/TopBar/EndTurnButton
@onready var game_log:        RichTextLabel = $HUD/LogPanel/GameLog

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")
const _POPUP_ART_SHADER := preload("res://scenes/card/card_face_rounded_2d.gdshader")

## ── Turn engine (singleton autoload) ────────────────────────────────────────
@onready var turn_controller: TurnController = TurnControllerSingleton
var game_state: GameState

## ── Game mode & settings ────────────────────────────────────────────────────
var is_developer_mode: bool = false
var _prize_count:  int = 6
var _active_slots: int = 1
var _bench_slots:  int = 5

## ── Camera perspectives ──────────────────────────────────────────────────────
var controlling_player: int = 0
var _p0_cam_transform: Transform3D
var _p1_cam_transform: Transform3D

## ── Drag state ───────────────────────────────────────────────────────────────
var dragged_card:  Card     = null
var hovered_card:  Card     = null
var _source_zone:  DropZone = null

## ── CPU player (Player Mode only) ────────────────────────────────────────────
var cpu_player: CpuPlayer = null

## ── Pending promotion tracking ───────────────────────────────────────────────
## Set to the player_id that needs to promote after a KO.  -1 = none pending.
var _pending_promotion_player: int = -1
## After all promotions resolve, advance past ATTACK phase automatically.
var _advance_after_promotion: bool = false

## ── Game-over flag ───────────────────────────────────────────────────────────
var _game_over: bool = false

## ── UI panels (built in code) ────────────────────────────────────────────────
var _setup_dialog:   Control = null
var _attack_panel:   Control = null
var _target_picker:  Control = null
var _bench_picker:   Control = null
var _card_popup:          PanelContainer = null
var _popup_art_container: Control        = null
var _popup_art:           TextureRect    = null
var _prize_label:    Label = null
var _status_label:   Label = null

## Attack selection state while target picker is open.
var _pending_atk_slot:  int = -1
var _pending_atk_index: int = -1

## Table plane for card drag intersections.
const DRAG_PLANE := Plane(Vector3.UP, 0.0)


# ===========================================================================
# _ready — show setup dialog only; no game logic until confirmed
# ===========================================================================

func _ready() -> void:
	## Cache camera perspectives before anything moves.
	_p0_cam_transform = camera.transform
	_p1_cam_transform = Transform3D(
		Basis(Vector3.UP, PI) * camera.basis,
		camera.position.rotated(Vector3.UP, PI)
	)

	## Build all UI panels (hidden until needed).
	_build_attack_panel()
	_build_card_popup()

	## Block everything behind the setup dialog.
	_show_setup_dialog()


# ===========================================================================
# SETUP DIALOG
# Lets the player pick Developer / Player mode and configure board variables
# before the game begins.
# ===========================================================================

func _show_setup_dialog() -> void:
	_setup_dialog = PanelContainer.new()
	_setup_dialog.custom_minimum_size = Vector2(420, 320)

	## Centre on screen using anchors.
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

	## Mode description label.
	var mode_desc := Label.new()
	mode_desc.text = "Choose a mode above."
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(mode_desc)

	vbox.add_child(HSeparator.new())

	## Prize count row.
	var prize_row := HBoxContainer.new()
	var prize_lbl := Label.new()
	prize_lbl.text = "Prize Cards (2-6):"
	prize_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var prize_spin := SpinBox.new()
	prize_spin.min_value = 2
	prize_spin.max_value = 6
	prize_spin.value     = 6
	prize_row.add_child(prize_lbl)
	prize_row.add_child(prize_spin)
	vbox.add_child(prize_row)

	## Active slots row.
	var active_row := HBoxContainer.new()
	var active_lbl := Label.new()
	active_lbl.text = "Active Slots (1-2):"
	active_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var active_spin := SpinBox.new()
	active_spin.min_value = 1
	active_spin.max_value = 2
	active_spin.value     = 1
	active_row.add_child(active_lbl)
	active_row.add_child(active_spin)
	vbox.add_child(active_row)

	## Bench slots row.
	var bench_row := HBoxContainer.new()
	var bench_lbl := Label.new()
	bench_lbl.text = "Bench Slots (3-5):"
	bench_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bench_spin := SpinBox.new()
	bench_spin.min_value = 3
	bench_spin.max_value = 5
	bench_spin.value     = 5
	bench_row.add_child(bench_lbl)
	bench_row.add_child(bench_spin)
	vbox.add_child(bench_row)

	vbox.add_child(HSeparator.new())

	var start_btn := Button.new()
	start_btn.text     = "Start Game"
	start_btn.disabled = true
	vbox.add_child(start_btn)

	## Track selected mode so start_btn knows when to enable.
	var chosen_mode := ""

	dev_btn.pressed.connect(func() -> void:
		chosen_mode = "developer"
		dev_btn.modulate    = Color(0.4, 0.9, 0.4)
		player_btn.modulate = Color.WHITE
		mode_desc.text = "Developer Mode: No CPU. Perspective switches automatically each turn so you play both sides."
		start_btn.disabled = false
	)
	player_btn.pressed.connect(func() -> void:
		chosen_mode = "player"
		player_btn.modulate = Color(0.4, 0.4, 0.9)
		dev_btn.modulate    = Color.WHITE
		mode_desc.text = "Player Mode: An autonomous CPU plays the opposing deck."
		start_btn.disabled = false
	)
	start_btn.pressed.connect(func() -> void:
		_setup_dialog.queue_free()
		_setup_dialog = null
		_on_setup_confirmed(
			chosen_mode,
			int(prize_spin.value),
			int(active_spin.value),
			int(bench_spin.value)
		)
	)

	$HUD.add_child(_setup_dialog)


# ===========================================================================
# GAME START
# ===========================================================================

func _on_setup_confirmed(
	mode: String,
	prizes: int,
	active_slots: int,
	bench_slots: int
) -> void:
	is_developer_mode = (mode == "developer")
	_prize_count      = prizes
	_active_slots     = active_slots
	_bench_slots      = bench_slots
	_start_game()


func _start_game() -> void:
	## ── Build game state ──────────────────────────────────────────────────
	game_state = GameState.new(2, _active_slots, _bench_slots)
	turn_controller.set_state(game_state)
	board.configure_slots(_active_slots, _bench_slots)

	## ── Connect signals ───────────────────────────────────────────────────
	turn_controller.phase_changed.connect(_on_phase_changed)
	turn_controller.action_rejected.connect(_on_action_rejected)
	turn_controller.action_committed.connect(_on_action_committed)
	turn_controller.log_message.connect(_on_turn_log)
	turn_controller.turn_started.connect(_on_turn_started)
	turn_controller.pokemon_knocked_out.connect(_on_pokemon_knocked_out)
	turn_controller.prize_taken.connect(_on_prize_taken)
	turn_controller.active_slot_emptied.connect(_on_active_slot_emptied)
	turn_controller.game_over.connect(_on_game_over)
	game_state.board.card_moved.connect(_on_board_card_moved)

	player_hand.card_played.connect(_on_card_played)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	## Perspective-switch button (Developer Mode label or generic).
	var switch_btn := Button.new()
	switch_btn.text = "Switch Perspective"
	switch_btn.pressed.connect(_switch_perspective)
	$HUD/TopBar.add_child(switch_btn)

	## Prize / status HUD labels.
	_prize_label = Label.new()
	_prize_label.text = "Prizes — P0: %d | P1: %d" % [_prize_count, _prize_count]
	$HUD/TopBar.add_child(_prize_label)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	$HUD/TopBar.add_child(_status_label)

	## ── Deal decks, prizes, and starting hands ────────────────────────────
	game_state.setup_player_deck(0, TestDeckFactory.build_deck(60))
	game_state.setup_player_deck(1, TestDeckFactory.build_deck(60))

	game_state.setup_prizes(0, _prize_count)
	game_state.setup_prizes(1, _prize_count)

	game_state.draw_starting_hand(0, 7)
	game_state.draw_starting_hand(1, 7)

	game_state.game_started = true

	## ── Spawn visual cards ────────────────────────────────────────────────
	var p0_from := board.get_zone_by_name("Deck").global_position + Vector3(0, 0.1, 0) \
		if board.get_zone_by_name("Deck") else Vector3.ZERO
	for inst in game_state.board.get_hand_cards(0):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst)
		card.drag_started.connect(_on_card_drag_started)
		card.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card_animated(card, p0_from)

	var p1_from := board.get_zone_by_name("Opp Deck").global_position + Vector3(0, 0.1, 0) \
		if board.get_zone_by_name("Opp Deck") else Vector3.ZERO
	for inst in game_state.board.get_hand_cards(1):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst)
		card.face_down = true
		opp_hand.add_card_animated(card, p1_from)

	_spawn_deck_visual(0)
	_spawn_deck_visual(1)

	## ── CPU player ────────────────────────────────────────────────────────
	if not is_developer_mode:
		cpu_player = CpuPlayer.new()
		add_child(cpu_player)
		cpu_player.setup(game_state, turn_controller)

	## ── Force first START phase signal (TurnController._ready fired first) ─
	_on_phase_changed(game_state.phase)
	_log_line("Game started — %s | Prizes: %d | Active slots: %d | Bench: %d" % [
		"Developer Mode" if is_developer_mode else "Player Mode",
		_prize_count, _active_slots, _bench_slots
	])


# ===========================================================================
# DECK / PRIZE VISUAL HELPERS
# ===========================================================================

func _spawn_deck_visual(pid: int) -> void:
	var zone_name := "Deck" if pid == 0 else "Opp Deck"
	var deck_zone := board.get_zone_by_name(zone_name)
	if deck_zone == null:
		return
	for inst in game_state.board.get_zone("p%d_deck" % pid):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst as CardInstance)
		card.face_down = true
		board.add_child(card)
		deck_zone.receive_card(card)


## Find the Card node in the scene tree that wraps [inst].
func _find_card_node(inst: CardInstance) -> Card:
	for zone in board.all_zones:
		for card in zone.held_cards:
			if (card as Card).card_instance == inst:
				return card as Card
	for card in player_hand.cards:
		if (card as Card).card_instance == inst:
			return card as Card
	for card in opp_hand.cards:
		if (card as Card).card_instance == inst:
			return card as Card
	for child in board.get_children():
		if child is Card and (child as Card).card_instance == inst:
			return child as Card
	return null


# ===========================================================================
# TURN / PHASE EVENT HANDLERS
# ===========================================================================

func _on_turn_started(_turn_number: int, current_player_id: int) -> void:
	_update_prize_label()
	_update_status_label()

	## In Developer Mode the perspective flips automatically on turn change.
	if is_developer_mode and current_player_id != controlling_player:
		_switch_perspective_to(current_player_id)


func _on_phase_changed(phase: int) -> void:
	if phase_label:
		phase_label.text = "Phase: %s  |  P%d's turn" % [
			TurnPhase.phase_to_string(phase), game_state.current_player_id
		]

	_refresh_attack_panel()

	## Auto-draw at START of each turn after turn 1.
	if phase == TurnPhase.Phase.START and game_state.turn_number > 1:
		turn_controller.request_action(
			ActionDrawCard.new(game_state.current_player_id, 1)
		)


func _on_action_committed(action: GameAction) -> void:
	## Visual sync for CPU-driven card plays.
	_sync_visual_for_action(action)
	_refresh_attack_panel()
	_update_status_label()


func _on_action_rejected(action: GameAction, reason: String) -> void:
	_log_line("[REJECT] %s — %s" % [action.description(), reason])


func _on_turn_log(text: String) -> void:
	_log_line(text)


## ── Knockout / prize / promotion callbacks ──────────────────────────────────

func _on_pokemon_knocked_out(victim: CardInstance, scoring_player_id: int) -> void:
	## Remove the KO'd Card node from its visual zone; game_state already moved
	## the logical card to discard inside resolve_knockouts().
	var card_node := _find_card_node(victim)
	if card_node:
		var zone := board.get_zone_containing(card_node)
		if zone:
			zone.remove_card(card_node)
		card_node.queue_free()

	var pname := victim.data.display_name if victim.data else "Pokemon"
	_log_line(">>> %s was knocked out! P%d scores a KO." % [pname, scoring_player_id])


func _on_prize_taken(player_id: int, card: CardInstance) -> void:
	## The prize card was moved to hand by ActionTakePrize.apply().
	## Spawn a Card node in the appropriate hand.
	var from_pos := Vector3.ZERO
	var prize_zone_name := "Prize 1" if player_id == 0 else "Opp Prize 1"
	var pzone := board.get_zone_by_name(prize_zone_name)
	if pzone:
		from_pos = pzone.global_position + Vector3(0, 0.1, 0)

	var card_node: Card = card_scene.instantiate()
	card_node.set_instance(card)

	if player_id == 0:
		card_node.face_down = false
		card_node.drag_started.connect(_on_card_drag_started)
		card_node.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card_animated(card_node, from_pos)
	else:
		card_node.face_down = (controlling_player != 1)
		if controlling_player == 1:
			card_node.drag_started.connect(_on_card_drag_started)
			card_node.drag_ended.connect(_on_card_drag_ended)
		opp_hand.add_card_animated(card_node, from_pos)

	_update_prize_label()
	_log_line("P%d takes a prize card (%s)." % [player_id, card.data.display_name if card.data else "?"])


func _on_active_slot_emptied(player_id: int) -> void:
	## Determine whether this player can promote from bench.
	var bench := game_state.board.get_bench_cards(player_id)
	if bench.is_empty():
		## No bench Pokemon — game_over signal should follow from TurnController.
		return

	if not is_developer_mode and player_id == 1:
		## CPU handles its own promotion.
		cpu_player.handle_promotion_needed()
		## After CPU promotes, auto-advance if an attack was what triggered this.
		_try_advance_after_promotion()
		return

	## Human player must choose.
	_pending_promotion_player = player_id
	_advance_after_promotion  = (game_state.phase == TurnPhase.Phase.ATTACK)

	if bench.size() == 1:
		## Only one option: auto-promote immediately.
		_execute_forced_promotion(player_id, 0)
	else:
		_show_bench_picker(player_id, bench)


func _execute_forced_promotion(player_id: int, bench_index: int) -> void:
	## Bypasses the actor gate — the opponent's board is being fixed mid-turn.
	var action := ActionPromoteFromBench.new(
		game_state.current_player_id,
		player_id, bench_index, true
	)
	turn_controller.request_action(action)
	_pending_promotion_player = -1
	_try_advance_after_promotion()


func _try_advance_after_promotion() -> void:
	if _advance_after_promotion and not _game_over:
		if game_state.phase == TurnPhase.Phase.ATTACK:
			_advance_after_promotion = false
			turn_controller.next_phase(game_state.current_player_id)


func _on_game_over(winner_player_id: int) -> void:
	_game_over = true
	_show_game_over_screen(winner_player_id)


# ===========================================================================
# VISUAL SYNC FOR CPU ACTIONS
# Listens to action_committed and mirrors the logical state onto Card nodes.
# ===========================================================================

func _sync_visual_for_action(action: GameAction) -> void:
	if action is ActionPlayBasicPokemon:
		_sync_play_pokemon(action as ActionPlayBasicPokemon)

	elif action is ActionEvolvePokemon:
		_sync_evolve(action as ActionEvolvePokemon)

	elif action is ActionAttachEnergy:
		_sync_attach_energy(action as ActionAttachEnergy)

	elif action is ActionPromoteFromBench:
		_sync_promotion(action as ActionPromoteFromBench)

	elif action is ActionDrawCard:
		## _on_board_card_moved handles deck→hand already.
		pass


func _sync_play_pokemon(action: ActionPlayBasicPokemon) -> void:
	## If the card is already shown in a board zone (human drag-and-drop), skip.
	var card_node := _find_card_node(action.card)
	if card_node == null:
		return
	## If the card node is still in a hand, it was a CPU play: move it to board.
	if player_hand.cards.has(card_node) or opp_hand.cards.has(card_node):
		if player_hand.cards.has(card_node):
			player_hand.remove_card(card_node)
		else:
			opp_hand.remove_card(card_node)
		board.add_child(card_node)
		card_node.face_down = false

	var logic_loc := game_state.board.find_card_location(action.card)
	var target_zone := _logic_zone_to_visual_zone(logic_loc)
	if target_zone:
		target_zone.receive_card(card_node)


func _sync_evolve(action: ActionEvolvePokemon) -> void:
	## Remove prior stage's visual node; move the evolution card node to the zone.
	var evo_node    := _find_card_node(action.card)
	var prior_node  := _find_card_node(action.target)
	var target_zone: DropZone = null
	if prior_node:
		target_zone = board.get_zone_containing(prior_node)
		if target_zone:
			target_zone.remove_card(prior_node)
		prior_node.queue_free()

	if evo_node == null:
		return
	if player_hand.cards.has(evo_node) or opp_hand.cards.has(evo_node):
		if player_hand.cards.has(evo_node):
			player_hand.remove_card(evo_node)
		else:
			opp_hand.remove_card(evo_node)
		board.add_child(evo_node)
	if target_zone:
		target_zone.receive_card(evo_node)
		evo_node.update_attachment_icons()


func _sync_attach_energy(action: ActionAttachEnergy) -> void:
	## The energy card node should disappear; the Pokemon's icons update.
	var energy_node := _find_card_node(action.card)
	if energy_node:
		if player_hand.cards.has(energy_node):
			player_hand.remove_card(energy_node)
		elif opp_hand.cards.has(energy_node):
			opp_hand.remove_card(energy_node)
		energy_node.queue_free()

	var pokemon_node := _find_card_node(action.target)
	if pokemon_node:
		pokemon_node.update_attachment_icons()


func _sync_promotion(action: ActionPromoteFromBench) -> void:
	## Find the promoted Pokemon's Card node and move it to the active zone.
	## The logic board already moved it; we just update visuals.
	var pid := action.player_id
	## Find which active slot it ended up in.
	for slot_idx in range(game_state.board.num_active_slots):
		var inst := game_state.board.get_active_card(pid, slot_idx)
		if inst == null:
			continue
		var card_node := _find_card_node(inst)
		if card_node == null:
			continue
		## Remove from the bench zone it used to be in.
		var old_zone := board.get_zone_containing(card_node)
		if old_zone:
			old_zone.remove_card(card_node)
		## Place in the correct active zone.
		var active_zone_name := _active_zone_name_for(pid, slot_idx)
		var active_zone := board.get_zone_by_name(active_zone_name)
		if active_zone:
			active_zone.receive_card(card_node)
		break


# ===========================================================================
# ATTACK PANEL
# Shown during the ATTACK phase when it is the human player's turn.
# Lists every attack on every active Pokemon with energy cost and damage.
# ===========================================================================

func _build_attack_panel() -> void:
	_attack_panel = PanelContainer.new()
	_attack_panel.visible = false
	_attack_panel.custom_minimum_size = Vector2(260, 0)
	_attack_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_attack_panel.offset_left  = -270
	_attack_panel.offset_right = -4

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.92)
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_attack_panel.add_theme_stylebox_override("panel", style)

	$HUD.add_child(_attack_panel)


func _refresh_attack_panel() -> void:
	if _attack_panel == null or game_state == null:
		return

	## Only show during ATTACK phase when it is the human player's turn.
	var human_turn := (controlling_player == game_state.current_player_id)
	var is_attack  := (game_state.phase == TurnPhase.Phase.ATTACK)
	_attack_panel.visible = is_attack and human_turn and not _game_over

	## Rebuild the button list.
	for child in _attack_panel.get_children():
		child.queue_free()

	if not _attack_panel.visible:
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_attack_panel.add_child(vbox)

	var heading := Label.new()
	heading.text = "Attacks"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 14)
	vbox.add_child(heading)

	var pid := game_state.current_player_id
	var any_attack_added := false

	for slot_idx in range(game_state.board.num_active_slots):
		var pokemon := game_state.board.get_active_card(pid, slot_idx)
		if pokemon == null or not (pokemon.data is PokemonCardData):
			continue

		var pdata := pokemon.data as PokemonCardData

		## Pokemon header.
		var pname_lbl := Label.new()
		var hp_str := "%d/%d HP" % [pokemon.hp_remaining(), pokemon.hp_max()]
		pname_lbl.text = "%s  [%s]" % [pdata.display_name, hp_str]
		pname_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
		vbox.add_child(pname_lbl)

		for atk_idx in range(pdata.attacks.size()):
			var atk := pdata.attacks[atk_idx]
			var can_use := AttackResolver.can_afford(pokemon, atk)
			var cost_str := AttackResolver.cost_summary(atk)
			var dmg_str  := ("%d dmg" % atk.base_damage) if atk.base_damage > 0 else "Effect"

			var btn := Button.new()
			btn.text = "%s\n(%s)  %s" % [atk.name, cost_str, dmg_str]
			btn.disabled = not can_use
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.custom_minimum_size = Vector2(0, 44)

			var captured_slot := slot_idx
			var captured_atk  := atk_idx
			btn.pressed.connect(func() -> void:
				_on_attack_button_pressed(captured_slot, captured_atk)
			)
			vbox.add_child(btn)
			any_attack_added = true

	if not any_attack_added:
		var no_atk := Label.new()
		no_atk.text = "No affordable attacks."
		no_atk.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		vbox.add_child(no_atk)


func _on_attack_button_pressed(slot_idx: int, atk_idx: int) -> void:
	if _game_over:
		return
	var opp_id := 1 - game_state.current_player_id

	## Gather valid opponent active targets.
	var targets: Array[CardInstance] = []
	for s in range(game_state.board.num_active_slots):
		var opp := game_state.board.get_active_card(opp_id, s)
		if opp != null:
			targets.append(opp)

	if targets.is_empty():
		_log_line("No opponent active Pokemon to attack.")
		return

	if targets.size() == 1:
		## Single target: fire immediately.
		_fire_attack(slot_idx, atk_idx, targets[0])
	else:
		## Multiple targets: show picker.
		_pending_atk_slot  = slot_idx
		_pending_atk_index = atk_idx
		_show_target_picker(targets)


func _fire_attack(slot_idx: int, atk_idx: int, target: CardInstance) -> void:
	var pid := game_state.current_player_id
	turn_controller.request_action(
		ActionAttack.new(pid, slot_idx, target, atk_idx)
	)
	_refresh_attack_panel()


# ===========================================================================
# TARGET PICKER
# Modal dialog shown when there are multiple opponent active slots to choose.
# ===========================================================================

func _show_target_picker(targets: Array[CardInstance]) -> void:
	if _target_picker:
		_target_picker.queue_free()

	_target_picker = PanelContainer.new()
	_target_picker.custom_minimum_size = Vector2(280, 0)
	_target_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.14, 0.97)
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_target_picker.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_target_picker.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "Choose a Target:"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	for target in targets:
		var pdata := target.data as PokemonCardData
		var hp_str := "%d/%d HP" % [target.hp_remaining(), target.hp_max()]
		var btn := Button.new()
		btn.text = "%s  [%s]" % [pdata.display_name, hp_str]
		var captured_target := target
		btn.pressed.connect(func() -> void:
			_target_picker.queue_free()
			_target_picker = null
			_fire_attack(_pending_atk_slot, _pending_atk_index, captured_target)
			_pending_atk_slot  = -1
			_pending_atk_index = -1
		)
		vbox.add_child(btn)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func() -> void:
		_target_picker.queue_free()
		_target_picker = null
		_pending_atk_slot  = -1
		_pending_atk_index = -1
	)
	vbox.add_child(cancel)

	$HUD.add_child(_target_picker)


# ===========================================================================
# BENCH PICKER
# Modal dialog prompting the player to choose which bench Pokemon to promote.
# ===========================================================================

func _show_bench_picker(player_id: int, bench: Array[CardInstance]) -> void:
	if _bench_picker:
		_bench_picker.queue_free()

	_bench_picker = PanelContainer.new()
	_bench_picker.custom_minimum_size = Vector2(300, 0)
	_bench_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.08, 0.97)
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_bench_picker.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_bench_picker.add_child(vbox)

	var lbl := Label.new()
	var who := "P%d — " % player_id
	lbl.text = "%sChoose a Pokemon to promote:" % who
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	for i in range(bench.size()):
		var pokemon := bench[i]
		var pdata := pokemon.data as PokemonCardData
		var hp_str := "%d/%d HP" % [pokemon.hp_remaining(), pokemon.hp_max()]
		var btn := Button.new()
		btn.text = "%s  [%s]" % [pdata.display_name, hp_str]
		var captured_idx := i
		btn.pressed.connect(func() -> void:
			_bench_picker.queue_free()
			_bench_picker = null
			_execute_forced_promotion(player_id, captured_idx)
		)
		vbox.add_child(btn)

	$HUD.add_child(_bench_picker)


# ===========================================================================
# GAME OVER SCREEN
# ===========================================================================

func _show_game_over_screen(winner_player_id: int) -> void:
	_attack_panel.visible = false

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(360, 160)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.98)
	style.corner_radius_top_left    = 10
	style.corner_radius_top_right   = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	var winner_name := "Player %d" % (winner_player_id + 1)
	if winner_player_id == 0:
		winner_name = "You" if not is_developer_mode else "Player 1"
	elif not is_developer_mode:
		winner_name = "CPU"
	title.text = "%s WIN%s!" % [winner_name, "S" if not winner_name.ends_with("s") else ""]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "The game has ended."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	vbox.add_child(sub)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit_btn)

	$HUD.add_child(panel)
	_log_line("=== GAME OVER — P%d wins! ===" % winner_player_id)


# ===========================================================================
# INPUT — drag, drop, right-click card inspector
# ===========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _game_over or game_state == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		## Any click dismisses the card popup.
		if mb.pressed and _card_popup != null and _card_popup.visible:
			_card_popup.visible = false

		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
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
	## Only let the controlling player drag their own face-up cards, and only
	## during their own turn (relevant in Player Mode when the CPU is active).
	if game_state == null:
		return
	if controlling_player != game_state.current_player_id:
		return
	var card := _raycast_card(screen_pos)
	if card == null or card.face_down:
		return
	_source_zone = board.get_zone_containing(card)
	if _source_zone:
		_source_zone.remove_card(card)
	dragged_card = card
	card.start_drag()


func _try_drop_card() -> void:
	if not dragged_card:
		return
	var card      := dragged_card
	var from_zone := _source_zone
	dragged_card  = null
	_source_zone  = null
	card.end_drag()

	var inst := card.card_instance
	if inst == null:
		_snap_back(card, from_zone)
		return

	var target_zone := board.get_zone_at_position(card.global_position)
	var action := _build_play_action(inst, target_zone)

	if action == null:
		_snap_back(card, from_zone)
		return

	var result := action.validate(game_state)
	if not result.ok:
		_log_line(result.reason)
		_snap_back(card, from_zone)
		return

	action.apply(game_state)
	_apply_card_visual(card, from_zone, inst, target_zone)
	_log_line("[P%d][%s] %s" % [
		controlling_player, TurnPhase.phase_to_string(game_state.phase), action.description()
	])
	_refresh_attack_panel()


func _build_play_action(inst: CardInstance, drop_zone: DropZone) -> GameAction:
	var PID := controlling_player

	if inst.data is PokemonCardData:
		var pdata := inst.data as PokemonCardData
		var slot  := _zone_name_to_pokemon_slot(drop_zone)
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


func _apply_card_visual(
	card: Card,
	from_zone: DropZone,
	inst: CardInstance,
	target_drop_zone: DropZone
) -> void:
	if from_zone == null:
		if player_hand.cards.has(card):
			player_hand.remove_card(card)
		elif opp_hand.cards.has(card):
			opp_hand.remove_card(card)
		board.add_child(card)

	var logic_location := game_state.board.find_card_location(inst)

	if "active" in logic_location or "bench" in logic_location:
		## For evolution: remove the prior-stage node from whatever zone it was in.
		if inst.prior_stage != null and target_drop_zone != null:
			_remove_prior_stage_visual(target_drop_zone, inst.prior_stage)
		## Resolve the ACTUAL destination zone — the bench→active redirect may have
		## placed the card somewhere other than where the player dropped it.
		var actual_zone := _logic_zone_to_visual_zone(logic_location)
		if actual_zone == null:
			actual_zone = target_drop_zone  ## Fallback: use the drop zone.
		if actual_zone != null:
			actual_zone.receive_card(card)
			if inst.prior_stage != null:
				card.update_attachment_icons()

	elif "discard" in logic_location:
		var discard := board.get_zone_by_name("Discard")
		if discard != null:
			discard.receive_card(card)

	elif logic_location == "stadium":
		card.set_home(Vector3(0.0, 0.05, 0.0), Vector3.ZERO, 0)
		card.return_to_home()

	else:
		## Energy / tool attached — the card node lives on the Pokemon.
		card.queue_free()
		if target_drop_zone != null and not target_drop_zone.held_cards.is_empty():
			(target_drop_zone.held_cards[0] as Card).update_attachment_icons()


func _remove_prior_stage_visual(zone: DropZone, prior_inst: CardInstance) -> void:
	for held in zone.held_cards:
		if (held as Card).card_instance == prior_inst:
			zone.remove_card(held)
			held.queue_free()
			return


# ===========================================================================
# ZONE NAME HELPERS
# ===========================================================================

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


func _instance_in_drop_zone(drop_zone: DropZone) -> CardInstance:
	if drop_zone == null or drop_zone.held_cards.is_empty():
		return null
	return (drop_zone.held_cards[0] as Card).card_instance


## Converts a logical zone id ("p0_active_0", "p1_bench", …) to its visual DropZone.
func _logic_zone_to_visual_zone(zone_id: String) -> DropZone:
	if zone_id.begins_with("p0_active_"):
		var slot := int(zone_id.get_slice("_", 2))
		return board.get_zone_by_name("Active" if slot == 0 else "Active %d" % (slot + 1))
	if zone_id == "p0_bench":
		return _find_first_empty_bench_zone(0)
	if zone_id.begins_with("p1_active_"):
		var slot := int(zone_id.get_slice("_", 2))
		return board.get_zone_by_name("Opp Active" if slot == 0 else "Opp Active %d" % (slot + 1))
	if zone_id == "p1_bench":
		return _find_first_empty_bench_zone(1)
	if "discard" in zone_id:
		var pid := int(zone_id.substr(1, 1))
		return board.get_zone_by_name("Discard" if pid == 0 else "Opp Discard")
	return null


func _find_first_empty_bench_zone(pid: int) -> DropZone:
	var prefix := "Bench " if pid == 0 else "Opp Bench "
	for i in range(1, 6):
		var zone := board.get_zone_by_name(prefix + str(i))
		if zone != null and zone.held_cards.is_empty():
			return zone
	return null


func _active_zone_name_for(pid: int, slot_idx: int) -> String:
	if pid == 0:
		return "Active" if slot_idx == 0 else "Active %d" % (slot_idx + 1)
	else:
		return "Opp Active" if slot_idx == 0 else "Opp Active %d" % (slot_idx + 1)


## Return zone names used by the controlling player.
func _player_active_zone_names() -> Array[String]:
	var names: Array[String] = []
	var prefix := "" if controlling_player == 0 else "Opp "
	for i in range(game_state.board.num_active_slots):
		names.append(prefix + ("Active" if i == 0 else "Active %d" % (i + 1)))
	return names


func _player_bench_zone_names() -> Array[String]:
	var names: Array[String] = []
	var prefix := "" if controlling_player == 0 else "Opp "
	for i in range(1, game_state.board.max_bench_size + 1):
		names.append(prefix + "Bench %d" % i)
	return names


# ===========================================================================
# DRAG HIGHLIGHTS
# ===========================================================================

func _on_card_drag_started(card: Card) -> void:
	if game_state != null and game_state.phase == TurnPhase.Phase.MAIN:
		_highlight_valid_zones_for(card)


func _on_card_drag_ended(_card: Card) -> void:
	board.clear_highlights()


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


func _highlight_pokemon_play_zones() -> void:
	for zone_name in _player_active_zone_names():
		var zone := board.get_zone_by_name(zone_name)
		if zone != null and zone.held_cards.is_empty():
			zone.set_highlighted(true)
	for zone_name in _player_bench_zone_names():
		var zone := board.get_zone_by_name(zone_name)
		if zone != null and zone.held_cards.size() < zone.max_cards:
			zone.set_highlighted(true)


func _highlight_evolution_zones_for(inst: CardInstance) -> void:
	if not (inst.data is PokemonCardData):
		return
	var pdata := inst.data as PokemonCardData
	var candidates := _player_active_zone_names() + _player_bench_zone_names()
	for zone_name in candidates:
		var zone := board.get_zone_by_name(zone_name)
		if zone == null or zone.held_cards.is_empty():
			continue
		var target_inst := (zone.held_cards[0] as Card).card_instance
		if target_inst == null or not (target_inst.data is PokemonCardData):
			continue
		if (target_inst.data as PokemonCardData).name_slug == pdata.evolves_from:
			zone.set_highlighted(true)


func _highlight_zones_with_pokemon() -> void:
	var candidates := _player_active_zone_names() + _player_bench_zone_names()
	for zone_name in candidates:
		var zone := board.get_zone_by_name(zone_name)
		if zone == null or zone.held_cards.is_empty():
			continue
		var target_inst := (zone.held_cards[0] as Card).card_instance
		if target_inst != null and target_inst.data is PokemonCardData:
			zone.set_highlighted(true)


# ===========================================================================
# RAYCAST / SCREEN → WORLD
# ===========================================================================

func _raycast_card(screen_pos: Vector2) -> Card:
	var from  := camera.project_ray_origin(screen_pos)
	var dir   := camera.project_ray_normal(screen_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0, 1)
	var result := space.intersect_ray(query)
	if result.is_empty():
		return null
	var body: Object = result.collider
	if body is StaticBody3D and body.get_parent() is Card:
		return body.get_parent() as Card
	return null


func _screen_to_table(screen_pos: Vector2) -> Variant:
	var from := camera.project_ray_origin(screen_pos)
	var dir  := camera.project_ray_normal(screen_pos)
	return DRAG_PLANE.intersects_ray(from, dir)


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


func _snap_back(card: Card, from_zone: DropZone) -> void:
	if from_zone != null:
		from_zone.receive_card(card)
	else:
		card.snap_to_home()


# ===========================================================================
# PERSPECTIVE SWITCHING
# ===========================================================================

func _switch_perspective() -> void:
	_switch_perspective_to(1 - controlling_player)


func _switch_perspective_to(pid: int) -> void:
	controlling_player = pid
	camera.transform = _p0_cam_transform if pid == 0 else _p1_cam_transform
	_configure_hand_for_player(player_hand, pid == 0)
	_configure_hand_for_player(opp_hand,    pid == 1)
	_flip_board_card_rotations()
	_refresh_attack_panel()


func _flip_board_card_rotations() -> void:
	for zone in board.all_zones:
		if zone.zone_name == "Deck" or zone.zone_name == "Opp Deck":
			continue
		zone.perspective_y_rotation = fmod(zone.perspective_y_rotation + PI, TAU)
		zone.relayout()


func _configure_hand_for_player(hand: Hand, is_controlling: bool) -> void:
	for card in hand.cards:
		(card as Card).face_down = not is_controlling
		if is_controlling:
			if not (card as Card).drag_started.is_connected(_on_card_drag_started):
				(card as Card).drag_started.connect(_on_card_drag_started)
			if not (card as Card).drag_ended.is_connected(_on_card_drag_ended):
				(card as Card).drag_ended.connect(_on_card_drag_ended)
		else:
			if (card as Card).drag_started.is_connected(_on_card_drag_started):
				(card as Card).drag_started.disconnect(_on_card_drag_started)
			if (card as Card).drag_ended.is_connected(_on_card_drag_ended):
				(card as Card).drag_ended.disconnect(_on_card_drag_ended)


# ===========================================================================
# END TURN BUTTON
# ===========================================================================

func _on_end_turn_pressed() -> void:
	if _game_over or game_state == null:
		return
	## Only the player whose turn it is (and whose perspective we control)
	## should advance phases.
	if controlling_player != game_state.current_player_id:
		return
	var actor := game_state.current_player_id
	match game_state.phase:
		TurnPhase.Phase.END:
			turn_controller.end_turn(actor)
		_:
			turn_controller.next_phase(actor)


# ===========================================================================
# BOARD CARD MOVED — deck→hand draw visual sync
# ===========================================================================

func _on_board_card_moved(inst: CardInstance, from_zone: String, to_zone: String) -> void:
	if from_zone.ends_with("_deck") and to_zone.ends_with("_hand"):
		var pid := int(from_zone.substr(1).split("_")[0])
		_sync_deck_draw_visual(inst, pid)


func _sync_deck_draw_visual(inst: CardInstance, pid: int) -> void:
	var deck_zone := board.get_zone_by_name("Deck" if pid == 0 else "Opp Deck")
	if deck_zone == null:
		return
	var drawn_card: Card = null
	for card in deck_zone.held_cards:
		if (card as Card).card_instance == inst:
			drawn_card = card as Card
			break
	if drawn_card == null:
		return
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


# ===========================================================================
# CARD INSPECTOR POPUP (right-click)
# ===========================================================================

func _build_card_popup() -> void:
	_card_popup = PanelContainer.new()
	_card_popup.visible = false
	_card_popup.custom_minimum_size = Vector2(448, 0)
	_card_popup.position = Vector2(10, 50)
	_card_popup.gui_input.connect(_on_popup_gui_input)
	_card_popup.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   58)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_card_popup.add_child(margin)

	_popup_art_container = Control.new()
	_popup_art_container.custom_minimum_size = Vector2(380, 533)
	_popup_art_container.clip_contents = false
	margin.add_child(_popup_art_container)

	_popup_art = TextureRect.new()
	_popup_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup_art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_popup_art.stretch_mode = TextureRect.STRETCH_SCALE
	## Apply the same rounded-corner shader used by the 3D card face mesh so
	## the popup shows the card with matching curved edges and corner fill.
	var popup_mat := ShaderMaterial.new()
	popup_mat.shader = _POPUP_ART_SHADER
	popup_mat.set_shader_parameter("mirror_radius", 0.032)
	_popup_art.material = popup_mat
	_popup_art_container.add_child(_popup_art)

	$HUD.add_child(_card_popup)


func _handle_right_click(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null or card.face_down or card.card_instance == null:
		return
	_populate_card_popup(card.card_instance)
	_card_popup.visible = true


const _POPUP_ART_W := 380.0
const _POPUP_ART_H := 533.0
const _POPUP_ENERGY_SIZE := 64
const _POPUP_TOOL_SIZE   := 96

func _populate_card_popup(inst: CardInstance) -> void:
	_popup_art.texture = inst.data.art

	## Remove previous attachment buttons; keep only the art TextureRect.
	for child in _popup_art_container.get_children():
		if child != _popup_art:
			child.queue_free()

	var tool_r := _POPUP_TOOL_SIZE / 2.0
	for i in range(inst.attached_tools.size()):
		var frac_y := AttachmentDisplay.TOOL_NORM_START_Y + i * AttachmentDisplay.TOOL_NORM_STEP_Y
		var cy := _POPUP_ART_H * frac_y
		var btn := _make_popup_circle_button(
			inst.attached_tools[i], AttachmentDisplay.TOOL_ICON_COLOR, _POPUP_TOOL_SIZE)
		btn.position = Vector2(-tool_r, cy - tool_r)
		_popup_art_container.add_child(btn)

	var energy_r     := _POPUP_ENERGY_SIZE / 2.0
	var sorted_energy := AttachmentDisplay.sort_energy(inst.attached_energy)
	for i in range(sorted_energy.size()):
		var col := i % 5
		var row := i / 5
		var frac_x := AttachmentDisplay.ENERGY_NORM_START_X + col * AttachmentDisplay.ENERGY_NORM_STEP_X
		var cx := _POPUP_ART_W * frac_x
		var cy := _POPUP_ART_H + row * (_POPUP_ENERGY_SIZE + 8.0)
		var btn := _make_popup_circle_button(
			sorted_energy[i], AttachmentDisplay.energy_color(sorted_energy[i]), _POPUP_ENERGY_SIZE)
		btn.position = Vector2(cx - energy_r, cy - energy_r)
		_popup_art_container.add_child(btn)


func _make_popup_circle_button(inst: CardInstance, color: Color, size: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(size, size)
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ""
	if inst.data != null:
		btn.tooltip_text = inst.data.display_name
	var radius := size / 2
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = color
	normal_style.corner_radius_top_left     = radius
	normal_style.corner_radius_top_right    = radius
	normal_style.corner_radius_bottom_left  = radius
	normal_style.corner_radius_bottom_right = radius
	var hover_style := normal_style.duplicate() as StyleBoxFlat
	hover_style.bg_color = color.lightened(0.25)
	btn.add_theme_stylebox_override("normal",  normal_style)
	btn.add_theme_stylebox_override("hover",   hover_style)
	btn.add_theme_stylebox_override("pressed", normal_style)
	btn.gui_input.connect(_on_attachment_icon_input.bind(inst))
	return btn


func _on_attachment_icon_input(event: InputEvent, inst: CardInstance) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_populate_card_popup(inst)
			get_viewport().set_input_as_handled()


func _on_popup_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_card_popup.visible = false


func _on_card_played(_card: Card) -> void:
	pass  ## Placement handled in _try_drop_card.


# ===========================================================================
# HUD HELPERS
# ===========================================================================

func _update_prize_label() -> void:
	if _prize_label == null or game_state == null:
		return
	var p0 := game_state.get_player(0)
	var p1 := game_state.get_player(1)
	var p0_prizes := p0.prizes_remaining if p0 else 0
	var p1_prizes := p1.prizes_remaining if p1 else 0
	_prize_label.text = "Prizes — P0: %d | P1: %d" % [p0_prizes, p1_prizes]


func _update_status_label() -> void:
	if _status_label == null or game_state == null:
		return
	var mode_tag := "[DEV]" if is_developer_mode else "[P%d]" % (controlling_player + 1)
	_status_label.text = mode_tag


func _log_line(text: String) -> void:
	if game_log:
		game_log.append_text(text + "\n")
