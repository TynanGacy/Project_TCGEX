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

## ── Debug camera adjuster ────────────────────────────────────────────────────
var _cam_adjust_active: bool  = false
var _cam_adjust_label:  Label = null
const _CAM_STEP:     float = 0.05
const _CAM_ROT_STEP: float = 1.0
const _CAM_FOV_STEP: float = 1.0

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

## ── Card search popup ────────────────────────────────────────────────────────
var _card_search_overlay: CanvasLayer = null
var _see_board_btn: Button = null

## ── Energy discard picker ────────────────────────────────────────────────────
var _energy_discard_picker: Control = null

## ── Prize picker ──────────────────────────────────────────────────────────────
## Set when the human must interactively choose prize card(s) to take.
var _prize_picker_player:    int     = -1
var _prize_picker_remaining: int     = 0
var _prize_picker_panel:     Control = null

## CardInstance → Card node cache.  Populated when cards are spawned and
## cleaned up when they are freed, making _find_card_node() O(1).
var _card_node_cache: Dictionary = {}

## ── Pre-game placement phase ─────────────────────────────────────────────────
## True while players are choosing their starting Active Pokemon.
var _in_placement_phase: bool = false
var _placement_done: Array[bool] = [false, false]
var _placement_picker: Control = null

## ── UI panels (built in code) ────────────────────────────────────────────────
var _setup_dialog:   Control = null
var _setup_selected_mode: String = ""
var _player_deck_path:   String = ""
var _opponent_deck_path: String = ""
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
const STARTUP_SPAWN_BATCH := 12


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

	## Debug camera adjuster label (hidden until backtick is pressed).
	_cam_adjust_label = Label.new()
	_cam_adjust_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_cam_adjust_label.offset_left   =  10.0
	_cam_adjust_label.offset_right  = 900.0
	_cam_adjust_label.offset_top    = -52.0
	_cam_adjust_label.offset_bottom =  -8.0
	_cam_adjust_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	_cam_adjust_label.add_theme_font_size_override("font_size", 13)
	_cam_adjust_label.visible = false
	$HUD.add_child(_cam_adjust_label)

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

	## Deck selection — scanned from data/decks/ at startup.
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

	## Track selected mode so start_btn knows when to enable.
	_setup_selected_mode = ""

	dev_btn.pressed.connect(func() -> void:
		_setup_selected_mode = "developer"
		dev_btn.modulate    = Color(0.4, 0.9, 0.4)
		player_btn.modulate = Color.WHITE
		mode_desc.text = "Developer Mode: No CPU. Perspective switches automatically each turn so you play both sides."
		start_btn.disabled = false
	)
	player_btn.pressed.connect(func() -> void:
		_setup_selected_mode = "player"
		player_btn.modulate = Color(0.4, 0.4, 0.9)
		dev_btn.modulate    = Color.WHITE
		mode_desc.text = "Player Mode: An autonomous CPU plays the opposing deck."
		start_btn.disabled = false
	)
	start_btn.pressed.connect(func() -> void:
		_setup_dialog.queue_free()
		_setup_dialog = null
		var p_sel := p1_deck_opt.selected
		var o_sel := p2_deck_opt.selected
		var p_path: String = deck_options[randi() % deck_options.size()]["path"] \
			if p_sel <= 0 and not deck_options.is_empty() \
			else ("" if p_sel <= 0 else deck_options[p_sel - 1]["path"] as String)
		var o_path: String = deck_options[randi() % deck_options.size()]["path"] \
			if o_sel <= 0 and not deck_options.is_empty() \
			else ("" if o_sel <= 0 else deck_options[o_sel - 1]["path"] as String)
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


# ===========================================================================
# GAME START
# ===========================================================================

func _on_setup_confirmed(
	mode: String,
	prizes: int,
	active_slots: int,
	bench_slots: int,
	player_deck_path: String = "",
	opponent_deck_path: String = ""
) -> void:
	is_developer_mode     = (mode == "developer")
	_prize_count          = prizes
	_active_slots         = active_slots
	_bench_slots          = bench_slots
	_player_deck_path     = player_deck_path
	_opponent_deck_path   = opponent_deck_path
	_start_game()


func _start_game() -> void:
	var startup_t0 := Time.get_ticks_msec()
	## ── Build game state ──────────────────────────────────────────────────
	game_state = GameState.new(2, _active_slots, _bench_slots)
	turn_controller.set_state(game_state)
	board.configure_slots(_active_slots, _bench_slots)
	board.configure_prizes(_prize_count)

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
	turn_controller.effect_choice_required.connect(_on_effect_choice_required)
	turn_controller.coin_flip_batch_ready.connect(_on_coin_flip_batch_ready)
	turn_controller.card_search_requested.connect(_on_card_search_requested)
	turn_controller.energy_discard_choice_requested.connect(_on_energy_discard_choice_requested)
	turn_controller.prizes_needed.connect(_on_prizes_needed)
	game_state.board.card_moved.connect(_on_board_card_moved)

	player_hand.card_played.connect(_on_card_played)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

	## Perspective switching is a Developer Mode-only affordance.
	if is_developer_mode:
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

	## ── Deal decks and starting hands (prizes placed after mulligan draw) ──
	## Decks are loaded from data/decks/*.json; fall back to random if missing.
	var deck_load_t0 := Time.get_ticks_msec()
	game_state.setup_player_deck(0, DeckLoader.load_deck(0, _player_deck_path))
	game_state.setup_player_deck(1, DeckLoader.load_deck(1, _opponent_deck_path))
	var deck_load_ms := Time.get_ticks_msec() - deck_load_t0

	## Draw starting hands with mulligan rule (reshuffle if no Basic found).
	var opening_t0 := Time.get_ticks_msec()
	var reshuffles_p0 := game_state.draw_starting_hand_with_mulligan(0, 7)
	var reshuffles_p1 := game_state.draw_starting_hand_with_mulligan(1, 7)

	## Prizes are placed after the opening hand is established.
	game_state.setup_prizes(0, _prize_count)
	game_state.setup_prizes(1, _prize_count)
	var opening_ms := Time.get_ticks_msec() - opening_t0

	## game_started stays false until placement phase completes.

	## ── Spawn visual cards ────────────────────────────────────────────────
	var visuals_t0 := Time.get_ticks_msec()
	var p0_from := board.get_zone_by_name("Deck").global_position + Vector3(0, 0.1, 0) \
		if board.get_zone_by_name("Deck") else Vector3.ZERO
	for inst in game_state.board.get_hand_cards(0):
		var card: Card = card_scene.instantiate()
		card.set_instance(inst)
		_register_card_node(card)
		card.drag_started.connect(_on_card_drag_started)
		card.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card_animated(card, p0_from)

	await _spawn_hidden_startup_visuals()
	var visuals_ms := Time.get_ticks_msec() - visuals_t0

	## ── CPU player (Player Mode only — never created in Developer Mode) ───
	if not is_developer_mode:
		cpu_player = CpuPlayer.new()
		add_child(cpu_player)
		cpu_player.setup(game_state, turn_controller)

	## ── Log setup info then enter placement phase ─────────────────────────
	_log_line("Game setup — %s | Prizes: %d | Active slots: %d | Bench: %d" % [
		"Developer Mode" if is_developer_mode else "Player Mode",
		_prize_count, _active_slots, _bench_slots
	])
	if reshuffles_p0 > 0:
		_log_line("P0 had no Basic in opening hand — reshuffled %d time(s)." % reshuffles_p0)
	if reshuffles_p1 > 0:
		_log_line("P1 had no Basic in opening hand — reshuffled %d time(s)." % reshuffles_p1)
	_log_line("Startup timings — deck load: %d ms | opening setup: %d ms | visuals: %d ms | total: %d ms" % [
		deck_load_ms,
		opening_ms,
		visuals_ms,
		Time.get_ticks_msec() - startup_t0
	])

	_start_placement_phase()


# ===========================================================================
# DECK / PRIZE VISUAL HELPERS
# ===========================================================================

func _spawn_deck_visual(pid: int) -> void:
	var zone_name := "Deck" if pid == 0 else "Opp Deck"
	var deck_zone := board.get_zone_by_name(zone_name)
	if deck_zone == null:
		return
	for inst in game_state.board.get_zone("p%d_deck" % pid):
		var card := _make_card_node(inst as CardInstance, true)
		board.add_child(card)
		deck_zone.receive_card(card)


## Spawns one face-down card node for each prize in the logical prize zone,
## distributing them across the "Prize N" / "Opp Prize N" visual zones.
func _spawn_prize_visuals(pid: int) -> void:
	var prefix := "Prize " if pid == 0 else "Opp Prize "
	var prize_cards := game_state.board.get_zone("p%d_prizes" % pid)
	for i in range(prize_cards.size()):
		var zone_name := prefix + str(i + 1)
		var prize_zone := board.get_zone_by_name(zone_name)
		if prize_zone == null:
			continue
		var card := _make_card_node(prize_cards[i] as CardInstance, true)
		board.add_child(card)
		prize_zone.receive_card(card)


## Creates and binds a Card node while allowing the caller to set face-down
## state before set_instance(). This avoids unnecessary SubViewport refreshes
## for hidden cards during initial setup (opponent hand, deck, prizes).
func _make_card_node(inst: CardInstance, start_face_down: bool = false) -> Card:
	var card: Card = card_scene.instantiate()
	card.face_down = start_face_down
	card.set_instance(inst)
	_register_card_node(card)
	return card


## Spawns hidden startup visuals in small batches across frames so setup
## does not stall the game loop on one long frame.
func _spawn_hidden_startup_visuals() -> void:
	var spawned_in_batch := 0
	var p1_from := board.get_zone_by_name("Opp Deck").global_position + Vector3(0, 0.1, 0) \
		if board.get_zone_by_name("Opp Deck") else Vector3.ZERO
	for inst in game_state.board.get_hand_cards(1):
		var card := _make_card_node(inst, true)
		opp_hand.add_card_animated(card, p1_from)
		spawned_in_batch += 1
		if spawned_in_batch >= STARTUP_SPAWN_BATCH:
			spawned_in_batch = 0
			await get_tree().process_frame

	for pid in range(2):
		var zone_name := "Deck" if pid == 0 else "Opp Deck"
		var deck_zone := board.get_zone_by_name(zone_name)
		if deck_zone != null:
			for inst in game_state.board.get_zone("p%d_deck" % pid):
				var deck_card := _make_card_node(inst as CardInstance, true)
				board.add_child(deck_card)
				deck_zone.receive_card(deck_card)
				spawned_in_batch += 1
				if spawned_in_batch >= STARTUP_SPAWN_BATCH:
					spawned_in_batch = 0
					await get_tree().process_frame

		var prefix := "Prize " if pid == 0 else "Opp Prize "
		var prize_cards := game_state.board.get_zone("p%d_prizes" % pid)
		for i in range(prize_cards.size()):
			var prize_zone := board.get_zone_by_name(prefix + str(i + 1))
			if prize_zone == null:
				continue
			var prize_card := _make_card_node(prize_cards[i] as CardInstance, true)
			board.add_child(prize_card)
			prize_zone.receive_card(prize_card)
			spawned_in_batch += 1
			if spawned_in_batch >= STARTUP_SPAWN_BATCH:
				spawned_in_batch = 0
				await get_tree().process_frame


## Removes the visual card node for [target_card] from its prize zone for [pid]
## and returns its world position.  When [target_card] is null, falls back to
## removing the first card from the lowest-numbered occupied zone (auto-take path).
func _pop_prize_visual(pid: int, target_card: CardInstance = null) -> Vector3:
	var prefix := "Prize " if pid == 0 else "Opp Prize "
	for i in range(1, 7):
		var prize_zone := board.get_zone_by_name(prefix + str(i))
		if prize_zone == null or prize_zone.held_cards.is_empty():
			continue
		## Find the specific card node when a target is given.
		var card_node: Card = null
		if target_card != null:
			for held in prize_zone.held_cards:
				if (held as Card).card_instance == target_card:
					card_node = held as Card
					break
			if card_node == null:
				continue  ## target not in this zone — keep searching
		else:
			card_node = prize_zone.held_cards[0] as Card
		var pos := prize_zone.global_position + Vector3(0, 0.1, 0)
		prize_zone.remove_card(card_node)
		card_node.queue_free()
		return pos
	return Vector3.ZERO



# ===========================================================================
# PRE-GAME PLACEMENT PHASE
# Both players place any number of Basic Pokémon face-down before the game:
#   • Active slot(s) must be filled before the bench is available.
#   • Bench placement is optional once all active slots are filled.
#   • Players click "Done" to confirm (requires active slot(s) filled).
#
# Dev Mode:  P0 places first (perspective at P0), then P1, then coin flip.
# Player Mode: P0 picks via dialog; P1 (CPU) auto-fills active then bench.
# ===========================================================================

func _start_placement_phase() -> void:
	_in_placement_phase = true
	_placement_done     = [false, false]
	_log_line("Pre-game: each player places Basic Pokémon face-down (active first, bench optional).")
	_prompt_player_placement(0)


func _prompt_player_placement(player_id: int) -> void:
	if is_developer_mode:
		_switch_perspective_to(player_id)

	var basics: Array[CardInstance] = []
	for card in game_state.board.get_hand_cards(player_id):
		if card.data is PokemonCardData \
				and (card.data as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			basics.append(card)

	if basics.is_empty():
		push_error("_prompt_player_placement: P%d has no Basic Pokemon to place!" % player_id)
		_on_placement_done(player_id)
		return

	if not is_developer_mode and player_id == 1:
		_cpu_auto_place(player_id, basics)
		return

	_show_placement_picker(player_id, basics)


func _cpu_auto_place(player_id: int, basics: Array[CardInstance]) -> void:
	for basic in basics:
		if game_state.board.get_first_empty_active_slot(player_id) != -1 \
				or game_state.board.can_play_card_to_bench(player_id):
			_place_setup_card(player_id, basic)
		else:
			break
	_on_placement_done(player_id)


func _show_placement_picker(player_id: int, basics: Array[CardInstance]) -> void:
	if _placement_picker:
		_placement_picker.queue_free()

	var num_active    := game_state.board.num_active_slots
	var filled_active := 0
	for s in range(num_active):
		if game_state.board.get_active_card(player_id, s) != null:
			filled_active += 1
	var active_full := (filled_active == num_active)
	var bench_count := game_state.board.get_bench_cards(player_id).size()
	var bench_full  := not game_state.board.can_play_card_to_bench(player_id)

	_placement_picker = PanelContainer.new()
	_placement_picker.custom_minimum_size = Vector2(340, 0)
	_placement_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var style := StyleBoxFlat.new()
	style.bg_color               = Color(0.10, 0.12, 0.18, 0.97)
	style.corner_radius_top_left    = 8
	style.corner_radius_top_right   = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	_placement_picker.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_placement_picker.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "P%d — Setup: Place Basic Pokémon (face-down)" % player_id
	title_lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	vbox.add_child(title_lbl)

	var status_color := Color(0.5, 0.9, 0.5) if active_full else Color(1.0, 0.85, 0.4)
	var status_lbl := Label.new()
	status_lbl.text = "Active: %d/%d %s  |  Bench: %d" % [
		filled_active, num_active, "(done)" if active_full else "", bench_count
	]
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_color_override("font_color", status_color)
	vbox.add_child(status_lbl)

	vbox.add_child(HSeparator.new())

	var hint_lbl := Label.new()
	if not active_full:
		hint_lbl.text = "Fill your Active slot(s) first."
	elif not bench_full and not basics.is_empty():
		hint_lbl.text = "Active filled! You may also place to the Bench."
	else:
		hint_lbl.text = "Click Done to confirm."
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.82))
	vbox.add_child(hint_lbl)

	for basic in basics:
		var pdata := basic.data as PokemonCardData
		var empty_slot := game_state.board.get_first_empty_active_slot(player_id)
		var can_bench  := game_state.board.can_play_card_to_bench(player_id)
		var can_place  := (empty_slot != -1) or can_bench

		var dest_text: String
		if empty_slot != -1:
			dest_text = ("-> Active Slot %d" % (empty_slot + 1)) if num_active > 1 else "-> Active"
		elif can_bench:
			dest_text = "-> Bench"
		else:
			dest_text = "(no space)"

		var btn := Button.new()
		btn.text     = "%s  [%d HP]  %s" % [pdata.display_name, basic.hp_max(), dest_text]
		btn.disabled = not can_place
		var captured_card := basic
		var captured_pid  := player_id
		btn.pressed.connect(func() -> void:
			_on_placement_card_picked(captured_pid, captured_card)
		)
		vbox.add_child(btn)

	vbox.add_child(HSeparator.new())

	var done_btn := Button.new()
	done_btn.text     = "Done — Confirm Setup"
	done_btn.disabled = (filled_active == 0)
	var captured_pid2 := player_id
	done_btn.pressed.connect(func() -> void:
		if _placement_picker:
			_placement_picker.queue_free()
			_placement_picker = null
		_on_placement_done(captured_pid2)
	)
	vbox.add_child(done_btn)

	$HUD.add_child(_placement_picker)


func _on_placement_card_picked(player_id: int, card: CardInstance) -> void:
	_place_setup_card(player_id, card)
	_log_line("P%d placed %s face-down." % [player_id, card.data.display_name if card.data else "?"])

	var remaining: Array[CardInstance] = []
	for c in game_state.board.get_hand_cards(player_id):
		if c.data is PokemonCardData \
				and (c.data as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			remaining.append(c)

	var no_space := game_state.board.get_first_empty_active_slot(player_id) == -1 \
		and not game_state.board.can_play_card_to_bench(player_id)

	if remaining.is_empty() or no_space:
		if _placement_picker:
			_placement_picker.queue_free()
			_placement_picker = null
		var num_active := game_state.board.num_active_slots
		var filled := 0
		for s in range(num_active):
			if game_state.board.get_active_card(player_id, s) != null:
				filled += 1
		if filled >= 1:
			_on_placement_done(player_id)
		else:
			_show_placement_picker(player_id, remaining)
	else:
		_show_placement_picker(player_id, remaining)


func _place_setup_card(player_id: int, card: CardInstance) -> void:
	var slot := game_state.board.get_first_empty_active_slot(player_id)
	var zone_id: String
	if slot != -1:
		zone_id = "p%d_active_%d" % [player_id, slot]
	else:
		zone_id = "p%d_bench" % player_id

	game_state.board.move_card(card, zone_id)
	card.turn_entered_play = game_state.turn_number

	var card_node := _find_card_node(card)
	if card_node == null:
		return

	var hand := player_hand if player_id == 0 else opp_hand
	if hand.cards.has(card_node):
		hand.remove_card(card_node)

	board.add_child(card_node)
	card_node.face_down = true


func _on_placement_done(player_id: int) -> void:
	_placement_done[player_id] = true

	if not (_placement_done[0] and _placement_done[1]):
		_prompt_player_placement(1 - player_id)
	else:
		_complete_placement_phase()


func _complete_placement_phase() -> void:
	_in_placement_phase = false

	## Reveal all placed cards face-up simultaneously.
	for pid in range(2):
		for slot_idx in range(game_state.board.num_active_slots):
			var inst := game_state.board.get_active_card(pid, slot_idx)
			if inst == null:
				continue
			var card_node := _find_card_node(inst)
			if card_node:
				card_node.face_down = false
		for bench_card in game_state.board.get_bench_cards(pid):
			var card_node := _find_card_node(bench_card)
			if card_node:
				card_node.face_down = false

	_log_line("All setup Pokémon revealed. Flipping coin for first player...")

	var first_player := await _show_coin_flip_overlay()

	game_state.game_started = true
	_log_line("P%d goes first!" % first_player)
	turn_controller.start_game(first_player)


## Animated coin-flip overlay.  Returns winning player id: 0 = heads, 1 = tails.
func _show_coin_flip_overlay() -> int:
	var winner: int = randi() % 2

	## Flip count parity encodes the result:
	## starting from "H", after N flips: H if N even, T if N odd.
	const MIN_FLIPS := 6
	var flip_count := MIN_FLIPS + (randi() % 4) * 2 + winner

	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.78)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color               = Color(0.10, 0.12, 0.20, 0.97)
	panel_style.corner_radius_top_left    = 10
	panel_style.corner_radius_top_right   = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text               = "COIN FLIP"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text               = "Determining who goes first..."
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	vbox.add_child(sub_lbl)

	var coin_center := CenterContainer.new()
	coin_center.custom_minimum_size = Vector2(0, 150)
	vbox.add_child(coin_center)

	var coin := PanelContainer.new()
	coin.custom_minimum_size = Vector2(120, 120)
	coin.pivot_offset = Vector2(60, 60)
	var coin_style := StyleBoxFlat.new()
	coin_style.bg_color                   = Color(1.0, 0.82, 0.10)
	coin_style.corner_radius_top_left     = 60
	coin_style.corner_radius_top_right    = 60
	coin_style.corner_radius_bottom_left  = 60
	coin_style.corner_radius_bottom_right = 60
	coin.add_theme_stylebox_override("panel", coin_style)
	coin_center.add_child(coin)

	var coin_lbl := Label.new()
	coin_lbl.text               = "H"
	coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	coin_lbl.add_theme_font_size_override("font_size", 52)
	coin_lbl.add_theme_color_override("font_color", Color(0.55, 0.38, 0.0))
	coin_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coin.add_child(coin_lbl)

	var result_lbl := Label.new()
	result_lbl.text               = ""
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 18)
	result_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.40))
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(result_lbl)

	var ok_btn := Button.new()
	ok_btn.text    = "Begin Game"
	ok_btn.visible = false
	vbox.add_child(ok_btn)

	await get_tree().process_frame

	## Squeeze X axis back and forth, swapping face at each half-flip.
	const HEADS_COLOR := Color(1.0, 0.82, 0.10)
	const TAILS_COLOR := Color(0.62, 0.44, 0.05)
	const FLIP_SPEED  := 0.10

	var showing_heads := true

	for _i in range(flip_count):
		var t1 := create_tween()
		t1.tween_property(coin, "scale", Vector2(0.06, 1.0), FLIP_SPEED)
		await t1.finished
		showing_heads = not showing_heads
		coin_style.bg_color = HEADS_COLOR if showing_heads else TAILS_COLOR
		coin_lbl.text       = "H" if showing_heads else "T"
		var t2 := create_tween()
		t2.tween_property(coin, "scale", Vector2(1.0, 1.0), FLIP_SPEED)
		await t2.finished

	result_lbl.text = "HEADS — P0 goes first!" if winner == 0 else "TAILS — P1 goes first!"
	ok_btn.visible  = true
	await ok_btn.pressed
	overlay.queue_free()
	return winner


## Registers a Card node in the cache.  Stale entries (freed nodes) are
## detected by is_instance_valid() in _find_card_node().  We intentionally
## do NOT use tree_exiting for cleanup because cards are routinely
## reparented (hand → board) which fires tree_exiting without the card
## actually being freed.
func _register_card_node(card_node: Card) -> void:
	if card_node.card_instance != null:
		_card_node_cache[card_node.card_instance] = card_node


## Returns the Card node for [inst] via O(1) dictionary lookup.
func _find_card_node(inst: CardInstance) -> Card:
	if inst == null or not is_instance_valid(inst):
		return null

	var raw: Variant = _card_node_cache.get(inst, null)
	if raw == null:
		return null
	if not is_instance_valid(raw):
		_card_node_cache.erase(inst)
		return null
	if not (raw is Card):
		_card_node_cache.erase(inst)
		return null
	return raw


# ===========================================================================
# TURN / PHASE EVENT HANDLERS
# ===========================================================================

func _on_turn_started(_turn_number: int, current_player_id: int) -> void:
	_update_prize_label()
	_update_status_label()
	## End-of-turn conditions (Burn, Poison, Sleep, Paralysis) are applied just
	## before this signal fires, so we need a fresh visual pass to show the
	## updated HP counters and condition badges.
	_refresh_board_card_visuals()

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
	## START phase stays intact for trigger processing, then advances itself.
	if phase == TurnPhase.Phase.START:
		turn_controller.next_phase(game_state.current_player_id)
	## END phase stays intact for trigger processing, then advances itself.
	elif phase == TurnPhase.Phase.END:
		turn_controller.end_turn(game_state.current_player_id)


func _on_action_committed(action: GameAction) -> void:
	## Visual sync for CPU-driven card plays.
	_sync_visual_for_action(action)
	_refresh_attack_panel()
	_update_status_label()
	_refresh_affected_card_visuals(action)


func _on_action_rejected(action: GameAction, reason: String) -> void:
	_log_line("[REJECT] %s — %s" % [action.description(), reason])


func _on_turn_log(text: String) -> void:
	_log_line(text)


## ── Knockout / prize / promotion callbacks ──────────────────────────────────

func _on_pokemon_knocked_out(victim: CardInstance, scoring_player_id: int) -> void:
	## game_state already moved the logical card (and all attachments / prior stages)
	## to discard inside resolve_knockouts().
	## Visually: remove from its board zone and drop it face-up onto the owner's discard pile.
	var card_node := _find_card_node(victim)
	if card_node:
		var zone := board.get_zone_containing(card_node)
		if zone:
			zone.remove_card(card_node)   ## resets board-display mode if needed
		card_node.clear_play_state()      ## remove damage/energy/status overlays
		card_node.face_down = false
		var discard_name := "Discard" if victim.owner_id == 0 else "Opp Discard"
		var discard_zone := board.get_zone_by_name(discard_name)
		if discard_zone != null:
			discard_zone.receive_card(card_node)
		else:
			card_node.queue_free()

	## Spawn visual nodes for any attached energy, tools, or prior-stage Pokemon
	## that game_state moved to the logical discard but have no visual Card node
	## (their nodes were destroyed when they were originally attached/evolved).
	_sync_discard_visuals(victim.owner_id)

	var pname := victim.data.display_name if victim.data else "Pokemon"
	_log_line(">>> %s was knocked out! P%d scores a KO." % [pname, scoring_player_id])


## Spawns visual Card nodes for any CardInstance in [player_id]'s logical
## discard zone that currently has no visual representation.  This covers
## attached energy, attached tools, and prior-stage Pokemon whose Card nodes
## were destroyed when they were originally attached or evolved.
##
## Drag signals are only wired up for player 0's newly spawned discard cards.
## In Developer Mode, player 1's discard cards are therefore not draggable
## from that perspective — they are informational display only.
func _sync_discard_visuals(player_id: int) -> void:
	var discard_name := "Discard" if player_id == 0 else "Opp Discard"
	var discard_zone := board.get_zone_by_name(discard_name)
	if discard_zone == null:
		return

	var logic_discard := game_state.board.get_zone("p%d_discard" % player_id)
	for raw in logic_discard:
		var inst := raw as CardInstance
		if inst == null or not is_instance_valid(inst):
			continue
		if _find_card_node(inst) != null:
			continue  ## already has a visual node
		## No visual node — spawn one for this attachment / prior-stage card.
		var new_node: Card = card_scene.instantiate()
		new_node.set_instance(inst)
		_register_card_node(new_node)
		new_node.face_down = false
		if player_id == 0:
			new_node.drag_started.connect(_on_card_drag_started)
			new_node.drag_ended.connect(_on_card_drag_ended)
		board.add_child(new_node)
		discard_zone.receive_card(new_node)


func _on_prize_taken(player_id: int, card: CardInstance) -> void:
	## The prize card was moved to hand by ActionTakePrize.apply().
	## Remove the visual prize card from its zone and use that position as the
	## fly-in origin for the new hand card.
	var from_pos := _pop_prize_visual(player_id, card)

	var card_node: Card = card_scene.instantiate()
	card_node.set_instance(card)
	_register_card_node(card_node)

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


## ── Prize picker ──────────────────────────────────────────────────────────────

func _on_prizes_needed(player_id: int, count: int) -> void:
	## Auto-pick when this player is not the one we're currently controlling.
	if controlling_player != player_id:
		for _i in range(count):
			var prizes := game_state.board.get_zone("p%d_prizes" % player_id)
			if prizes.is_empty():
				break
			turn_controller.notify_prize_selected(player_id, prizes[0] as CardInstance)
		return
	## Human picks interactively.
	_prize_picker_player    = player_id
	_prize_picker_remaining = count
	_open_prize_picker(count)


func _open_prize_picker(count: int) -> void:
	_close_prize_picker()

	_prize_picker_panel = PanelContainer.new()
	_prize_picker_panel.custom_minimum_size = Vector2(320, 0)
	_prize_picker_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_prize_picker_panel.offset_top    = 50
	_prize_picker_panel.offset_bottom = 130
	_prize_picker_panel.offset_left   = -160
	_prize_picker_panel.offset_right  = 160

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.10, 0.14, 0.22, 0.95)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_prize_picker_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_prize_picker_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Take %d Prize Card%s" % [count, "s" if count > 1 else ""]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "Click a prize card on the board to take it."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	vbox.add_child(sub)

	$HUD.add_child(_prize_picker_panel)

	## Highlight occupied prize zones for the picking player.
	var prefix := "Prize " if _prize_picker_player == 0 else "Opp Prize "
	for i in range(1, 7):
		var pz := board.get_zone_by_name(prefix + str(i))
		if pz != null and not pz.held_cards.is_empty():
			pz.set_highlighted(true)


func _close_prize_picker() -> void:
	if _prize_picker_panel != null and is_instance_valid(_prize_picker_panel):
		_prize_picker_panel.queue_free()
	_prize_picker_panel = null
	## Un-highlight all prize zones.
	for pid2 in range(2):
		var prefix2 := "Prize " if pid2 == 0 else "Opp Prize "
		for i in range(1, 7):
			var pz := board.get_zone_by_name(prefix2 + str(i))
			if pz != null:
				pz.set_highlighted(false)


func _try_pick_prize(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null:
		return
	var inst := card.card_instance
	if inst == null:
		return
	## Verify the card is in one of the prize picker player's prize zones.
	var prefix := "Prize " if _prize_picker_player == 0 else "Opp Prize "
	var in_prize := false
	for i in range(1, 7):
		var pz := board.get_zone_by_name(prefix + str(i))
		if pz != null and pz.held_cards.has(card):
			in_prize = true
			break
	if not in_prize:
		return
	_prize_picker_remaining -= 1
	var pid := _prize_picker_player
	if _prize_picker_remaining <= 0:
		_prize_picker_player = -1
		_close_prize_picker()
	turn_controller.notify_prize_selected(pid, inst)


func _on_active_slot_emptied(player_id: int) -> void:
	## Determine whether this player can promote from bench.
	var bench := game_state.board.get_bench_cards(player_id)
	if bench.is_empty():
		## No bench Pokemon — game_over signal should follow from TurnController.
		return

	## CPU handles promotion in Player Mode only; never in Developer Mode.
	## Do NOT auto-advance here — _resolve_post_attack() handles phase
	## advancement after this synchronous signal handler returns.
	if not is_developer_mode and player_id == 1 and cpu_player != null:
		cpu_player.handle_promotion_needed()
		return

	## Human player must choose.
	_pending_promotion_player = player_id
	_advance_after_promotion  = (game_state.phase == TurnPhase.Phase.MAIN)

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


func _try_advance_after_promotion() -> void:
	if _advance_after_promotion and not _game_over:
		_advance_after_promotion = false
		if game_state.phase == TurnPhase.Phase.MAIN:
			turn_controller.next_phase(game_state.current_player_id)   ## MAIN -> END


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

	elif action is ActionRetreat:
		_sync_retreat(action as ActionRetreat)

	elif action is ActionDrawCard:
		## _on_board_card_moved handles deck→hand already.
		pass


func _sync_play_pokemon(action: ActionPlayBasicPokemon) -> void:
	var card_node := _find_card_node(action.card)
	if card_node == null:
		return
	## Human drag-and-drop already placed the card via _apply_card_visual.
	## Only proceed if the card is still in a hand (CPU play).
	if not (player_hand.cards.has(card_node) or opp_hand.cards.has(card_node)):
		return
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
	evo_node.face_down = false
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


func _sync_retreat(action: ActionRetreat) -> void:
	## After swap_cards, the chosen bench card is now active and the old active
	## card is at the end of the bench array.  Move the visual nodes to match.
	var pid      := action.actor_id
	var slot_idx := action.active_slot

	var new_active_inst := game_state.board.get_active_card(pid, slot_idx)
	var bench_cards     := game_state.board.get_bench_cards(pid)
	if new_active_inst == null or bench_cards.is_empty():
		return
	var new_bench_inst := bench_cards.back() as CardInstance

	var promoted_node := _find_card_node(new_active_inst)  ## was on bench
	var retreated_node := _find_card_node(new_bench_inst)  ## was in active

	## The bench visual zone where the promoted card was sitting.
	var vacated_bench_zone := board.get_zone_containing(promoted_node) if promoted_node else null
	var active_zone_name   := _active_zone_name_for(pid, slot_idx)
	var active_zone        := board.get_zone_by_name(active_zone_name)

	## Move promoted card: bench zone → active zone.
	if promoted_node != null:
		if vacated_bench_zone:
			vacated_bench_zone.remove_card(promoted_node)
		if active_zone:
			active_zone.receive_card(promoted_node)
		promoted_node.face_down = false

	## Move retreated card: active zone → the slot the promoted card just left.
	if retreated_node != null:
		if active_zone:
			active_zone.remove_card(retreated_node)
		var target_bench := vacated_bench_zone if vacated_bench_zone \
			else _find_first_empty_bench_zone(pid)
		if target_bench:
			target_bench.receive_card(retreated_node)
		retreated_node.update_attachment_icons()


## Refreshes damage counters and status overlays on every face-up card in a
## board zone.  Called after any action that may change HP or conditions.
##
## NOTE: this visits all cards in all zones on each call.  For the current
## game size this is acceptable.  A targeted approach (only refresh the card
## that was actually affected) would reduce per-action node churn if the
## number of in-play cards grows.
func _refresh_board_card_visuals() -> void:
	if board == null:
		return
	for zone in board.all_zones:
		for card in zone.held_cards:
			var c := card as Card
			c.update_damage_counter()
			c.update_status_overlays()


## Refreshes only the card(s) affected by [action] instead of every card on
## the board.  Falls back to _refresh_board_card_visuals() for action types
## whose side-effects can touch arbitrary cards (e.g. trainer items).
func _refresh_affected_card_visuals(action: GameAction) -> void:
	if board == null:
		return

	var targets: Array[CardInstance] = []

	if action is ActionAttack:
		var atk := action as ActionAttack
		var attacker := game_state.board.get_active_card(atk.actor_id, atk.attacker_slot)
		if attacker != null:
			targets.append(attacker)
		if atk.defender != null:
			targets.append(atk.defender)
		## Attacks may hit multiple active slots — refresh all opponent actives.
		var opp_id := 1 - atk.actor_id
		for s in range(game_state.board.num_active_slots):
			var opp := game_state.board.get_active_card(opp_id, s)
			if opp != null and not targets.has(opp):
				targets.append(opp)
	elif action is ActionAttachEnergy:
		if (action as ActionAttachEnergy).target != null:
			targets.append((action as ActionAttachEnergy).target)
	elif action is ActionEvolvePokemon:
		if (action as ActionEvolvePokemon).card != null:
			targets.append((action as ActionEvolvePokemon).card)
	elif action is ActionPlayBasicPokemon:
		if (action as ActionPlayBasicPokemon).card != null:
			targets.append((action as ActionPlayBasicPokemon).card)
	elif action is ActionPromoteFromBench:
		var promo := action as ActionPromoteFromBench
		for s in range(game_state.board.num_active_slots):
			var c := game_state.board.get_active_card(promo.player_id, s)
			if c != null:
				targets.append(c)
	elif action is ActionPlayTrainerTool:
		if (action as ActionPlayTrainerTool).target != null:
			targets.append((action as ActionPlayTrainerTool).target)
	else:
		## Trainer items/supporters/stadiums can have wide side effects.
		_refresh_board_card_visuals()
		return

	for inst in targets:
		var card_node := _find_card_node(inst)
		if card_node != null:
			card_node.update_damage_counter()
			card_node.update_status_overlays()


# ===========================================================================
# ATTACK PANEL
# Shown during the MAIN phase when it is the human player's turn.
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

	## Attacks happen during MAIN phase (ATTACK phase is no longer in the flow).
	var human_turn := (controlling_player == game_state.current_player_id)
	var attack_window := (game_state.phase == TurnPhase.Phase.MAIN)
	_attack_panel.visible = attack_window and human_turn and not _game_over

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

	var retreat_heading := Label.new()
	retreat_heading.text = "Retreat"
	retreat_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	retreat_heading.add_theme_font_size_override("font_size", 14)
	vbox.add_child(retreat_heading)

	for slot_idx in range(game_state.board.num_active_slots):
		var active := game_state.board.get_active_card(pid, slot_idx)
		if active == null:
			continue
		var bench := game_state.board.get_bench_cards(pid)
		var retreat_btn := Button.new()
		var retreat_cost := active.get_effective_retreat_cost(game_state)
		retreat_btn.text = "Retreat Active %d (cost %d)" % [slot_idx + 1, retreat_cost]
		retreat_btn.disabled = bench.is_empty() \
			or game_state.has_attacked_this_turn \
			or game_state.has_retreated_this_turn \
			or active.attached_energy.size() < retreat_cost
		var captured_slot := slot_idx
		retreat_btn.pressed.connect(func() -> void:
			_on_retreat_button_pressed(captured_slot)
		)
		vbox.add_child(retreat_btn)


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


func _on_retreat_button_pressed(slot_idx: int) -> void:
	if _game_over:
		return
	var pid := game_state.current_player_id
	var bench := game_state.board.get_bench_cards(pid)
	if bench.is_empty():
		return
	var active := game_state.board.get_active_card(pid, slot_idx)
	if active == null:
		return
	var retreat_cost := active.get_effective_retreat_cost(game_state)

	## Inner helper: after the bench target is chosen, ask for energy if needed.
	var _do_retreat := func(bench_index: int) -> void:
		## Balloon Berry handles its own discard; no energy picker needed.
		var balloon := active.get_tool()
		var uses_balloon := balloon != null and balloon.data != null \
			and balloon.data.card_id == "DR_82_balloon_berry"

		if uses_balloon or retreat_cost == 0 \
				or active.attached_energy.size() <= retreat_cost:
			## No choice required — fire immediately.
			turn_controller.request_action(ActionRetreat.new(pid, slot_idx, bench_index))
			_refresh_attack_panel()
		else:
			## Player must choose which energy to discard.
			var energies: Array = active.attached_energy.duplicate()
			var pname := active.data.display_name if active.data else "Pokemon"
			_show_energy_discard_picker(
				energies,
				retreat_cost,
				pname,
				func(chosen_energy: Array) -> void:
					var action := ActionRetreat.new(pid, slot_idx, bench_index)
					for e in chosen_energy:
						action.energy_to_discard.append(e as CardInstance)
					turn_controller.request_action(action)
					_refresh_attack_panel()
			)

	if bench.size() == 1:
		_do_retreat.call(0)
	else:
		_show_bench_picker_for_choice(
			"Choose a Pokemon to switch in for retreat:",
			bench,
			_do_retreat
		)


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
	_show_bench_picker_for_choice(
		"P%d — Choose a Pokemon to promote:" % player_id,
		bench,
		func(chosen_index: int) -> void:
			_execute_forced_promotion(player_id, chosen_index)
			_try_advance_after_promotion()
	)


func _show_bench_picker_for_choice(
	title: String,
	bench: Array[CardInstance],
	on_choose: Callable
) -> void:
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
	lbl.text = title
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
			if on_choose.is_valid():
				on_choose.call(captured_idx)
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

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	_handle_cam_adjust_key(key)


func _handle_cam_adjust_key(key: InputEventKey) -> void:
	## Backtick toggles adjust mode regardless of game state.
	if key.keycode == KEY_QUOTELEFT:
		_cam_adjust_active = not _cam_adjust_active
		_cam_adjust_label.visible = _cam_adjust_active
		if _cam_adjust_active:
			_cam_adjust_refresh_label()
		get_viewport().set_input_as_handled()
		return

	if not _cam_adjust_active:
		return

	## Consume all keys while the overlay is active so they don't move cards.
	get_viewport().set_input_as_handled()

	var shift: bool = key.shift_pressed
	var pos: Vector3 = camera.position
	var rot: Vector3 = camera.rotation_degrees
	var fov: float   = camera.fov
	var dirty: bool  = true

	if key.keycode == KEY_RIGHT:
		if shift:
			rot.y -= _CAM_ROT_STEP
		else:
			pos.x += _CAM_STEP
	elif key.keycode == KEY_LEFT:
		if shift:
			rot.y += _CAM_ROT_STEP
		else:
			pos.x -= _CAM_STEP
	elif key.keycode == KEY_UP:
		if shift:
			pos.y += _CAM_STEP
		else:
			pos.z -= _CAM_STEP
	elif key.keycode == KEY_DOWN:
		if shift:
			pos.y -= _CAM_STEP
		else:
			pos.z += _CAM_STEP
	elif key.keycode == KEY_COMMA:
		rot.x -= _CAM_ROT_STEP
	elif key.keycode == KEY_PERIOD:
		rot.x += _CAM_ROT_STEP
	elif key.keycode == KEY_BRACKETLEFT:
		fov = maxf(10.0, fov - _CAM_FOV_STEP)
	elif key.keycode == KEY_BRACKETRIGHT:
		fov = minf(120.0, fov + _CAM_FOV_STEP)
	elif key.keycode == KEY_P:
		print("=== Camera Debug ===")
		print("  position:         ", camera.position)
		print("  rotation_degrees: ", camera.rotation_degrees)
		print("  fov:              ", camera.fov)
		print("  transform:        ", camera.transform)
		dirty = false
	else:
		dirty = false

	if dirty:
		camera.position         = pos
		camera.rotation_degrees = rot
		camera.fov              = fov
		if controlling_player == 0:
			_p0_cam_transform = camera.transform
			_p1_cam_transform = Transform3D(
				Basis(Vector3.UP, PI) * camera.basis,
				camera.position.rotated(Vector3.UP, PI)
			)
		else:
			_p1_cam_transform = camera.transform
		_cam_adjust_refresh_label()


func _cam_adjust_refresh_label() -> void:
	var pos: Vector3 = camera.position
	var rot: Vector3 = camera.rotation_degrees
	_cam_adjust_label.text = (
		"[CAM ADJUST]  ` exit  |  Arrows=pan X/Z  |  Shift+↑↓=height  |  Shift+←→=yaw  |  ,/.=pitch  |  [/]=FOV  |  P=print\n"
		+ "pos (%.3f, %.3f, %.3f)   rot (%.1f, %.1f, %.1f)   fov %.1f" % [
			pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, camera.fov
		]
	)

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
	## While the prize picker is open, clicks select prizes instead of dragging.
	if _prize_picker_player >= 0:
		_try_pick_prize(screen_pos)
		return
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
	_refresh_affected_card_visuals(action)


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
		## For bench plays, honour the exact zone the player dropped on rather
		## than redirecting to the first-empty slot.  Redirecting causes the
		## card to land in two held_cards arrays simultaneously (the drop zone
		## AND the first-empty zone), creating phantom occupied-slot entries
		## that silently block future drops.
		## Active plays (including bench→active redirects) still use the logical zone.
		var actual_zone: DropZone
		if "bench" in logic_location and target_drop_zone != null \
				and _zone_name_to_pokemon_slot(target_drop_zone) == "bench":
			actual_zone = target_drop_zone
		else:
			actual_zone = _logic_zone_to_visual_zone(logic_location)
			if actual_zone == null:
				actual_zone = target_drop_zone
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


## Converts a logical BoardState zone id to its corresponding visual DropZone.
## Returns null if the zone id is unknown or all bench slots are occupied.
## Handles the p0/p1 active and bench zones; discard zones are also mapped.
## Energy / tool / stadium zones have no visual DropZone and return null.
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


## Returns the visual zone names for the controlling player's active slot(s).
## Slot 0 is just "Active" / "Opp Active"; slot 1+ appends the slot number.
func _player_active_zone_names() -> Array[String]:
	var names: Array[String] = []
	var prefix := "" if controlling_player == 0 else "Opp "
	for i in range(game_state.board.num_active_slots):
		names.append(prefix + ("Active" if i == 0 else "Active %d" % (i + 1)))
	return names


## Returns the visual zone names for all of the controlling player's bench slots.
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
	if not is_developer_mode:
		return
	_switch_perspective_to(1 - controlling_player)


func _switch_perspective_to(pid: int) -> void:
	if pid == controlling_player:
		## Avoid double-applying board rotation when callers request the
		## currently active perspective (e.g. first placement prompt for P0).
		_configure_hand_for_player(player_hand, pid == 0)
		_configure_hand_for_player(opp_hand,    pid == 1)
		_refresh_attack_panel()
		return
	controlling_player = pid
	camera.transform = _p0_cam_transform if pid == 0 else _p1_cam_transform
	_configure_hand_for_player(player_hand, pid == 0)
	_configure_hand_for_player(opp_hand,    pid == 1)
	_apply_board_perspective(pid)
	_refresh_attack_panel()


func _apply_board_perspective(pid: int) -> void:
	var y_rot := 0.0 if pid == 0 else PI
	for zone in board.all_zones:
		if zone.zone_name == "Deck" or zone.zone_name == "Opp Deck":
			continue
		zone.perspective_y_rotation = y_rot
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
	if _game_over or game_state == null or _in_placement_phase:
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

## Reacts to logical card movements emitted by BoardState.card_moved.
##
## Two responsibilities:
##   • deck → hand: triggers the visual draw animation (_sync_deck_draw_visual).
##   • active/bench → anywhere else: clears in-play state (damage, energy, etc.)
##     so cards are logically clean when they leave the battlefield.
##
## NOTE: player_id is parsed from the zone id string ("p0_deck" → pid 0).
## This relies on the two-player "p{0|1}_…" naming convention.
func _on_board_card_moved(inst: CardInstance, from_zone: String, to_zone: String) -> void:
	if from_zone.ends_with("_deck") and to_zone.ends_with("_hand"):
		var pid := int(from_zone.substr(1).split("_")[0])
		_sync_deck_draw_visual(inst, pid)
	## When a card leaves an active or bench zone for any off-board zone,
	## erase its in-play modifiers (damage, energy, tools, status conditions).
	var leaving_play := (from_zone.contains("_active") or from_zone.contains("_bench")) \
		and not (to_zone.contains("_active") or to_zone.contains("_bench"))
	if leaving_play:
		inst.clear_in_play_state()
	if from_zone.contains("_active") or from_zone.contains("_bench") \
			or to_zone.contains("_active") or to_zone.contains("_bench"):
		_sync_in_play_positions_from_logic()


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


func _sync_in_play_positions_from_logic() -> void:
	for pid in range(2):
		for slot_idx in range(game_state.board.num_active_slots):
			var active := game_state.board.get_active_card(pid, slot_idx)
			if active != null:
				_place_instance_in_zone(active, _active_zone_name_for(pid, slot_idx))

		var bench := game_state.board.get_bench_cards(pid)
		for i in range(bench.size()):
			var zone_name := ("Bench %d" % (i + 1)) if pid == 0 else ("Opp Bench %d" % (i + 1))
			_place_instance_in_zone(bench[i], zone_name)


func _place_instance_in_zone(inst: CardInstance, zone_name: String) -> void:
	var card_node := _find_card_node(inst)
	if card_node == null:
		return
	var target_zone := board.get_zone_by_name(zone_name)
	if target_zone == null:
		return
	var old_zone := board.get_zone_containing(card_node)
	if old_zone != null and old_zone != target_zone:
		old_zone.remove_card(card_node)
	if not target_zone.held_cards.has(card_node):
		target_zone.receive_card(card_node)


func _on_effect_choice_required(reason: String, player_id: int, choices: Array) -> void:
	if choices.is_empty():
		turn_controller.resolve_effect_choice(player_id, [])
		return
	if choices.size() == 1:
		turn_controller.resolve_effect_choice(player_id, [choices[0]])
		return
	if controlling_player != player_id:
		turn_controller.resolve_effect_choice(player_id, [choices[0]])
		return
	var bench_choices: Array[CardInstance] = []
	for choice in choices:
		if choice is CardInstance:
			bench_choices.append(choice)
	_show_bench_picker_for_choice(
		reason,
		bench_choices,
		func(chosen_index: int) -> void:
			if chosen_index < 0 or chosen_index >= bench_choices.size():
				turn_controller.resolve_effect_choice(player_id, [])
				return
			turn_controller.resolve_effect_choice(player_id, [bench_choices[chosen_index]])
	)


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

	## HP bar overlay for Pokemon cards.
	if inst.is_pokemon():
		var hp_max := inst.hp_max()
		var hp_rem := inst.hp_remaining()
		var ratio := float(hp_rem) / float(hp_max) if hp_max > 0 else 0.0

		var bar_y := _POPUP_ART_H - 38.0
		var bar_h := 38.0

		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.0, 0.0, 0.0, 0.62)
		bar_bg.position = Vector2(0.0, bar_y)
		bar_bg.size = Vector2(_POPUP_ART_W, bar_h)
		_popup_art_container.add_child(bar_bg)

		var fill_color: Color
		if ratio > 0.5:
			fill_color = Color(0.12, 0.70, 0.12, 0.78)
		elif ratio > 0.25:
			fill_color = Color(0.90, 0.74, 0.0, 0.78)
		else:
			fill_color = Color(0.88, 0.12, 0.12, 0.78)

		var bar_fill := ColorRect.new()
		bar_fill.color = fill_color
		bar_fill.position = Vector2(0.0, bar_y)
		bar_fill.size = Vector2(_POPUP_ART_W * ratio, bar_h)
		_popup_art_container.add_child(bar_fill)

		var hp_lbl := Label.new()
		hp_lbl.text = "%d / %d HP" % [hp_rem, hp_max]
		hp_lbl.add_theme_font_size_override("font_size", 17)
		hp_lbl.add_theme_color_override("font_color", Color.WHITE)
		hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_lbl.position = Vector2(0.0, bar_y + 8.0)
		hp_lbl.size = Vector2(_POPUP_ART_W, 24.0)
		_popup_art_container.add_child(hp_lbl)

		## Status condition chips just above the HP bar.
		const COND_COLORS: Dictionary = {
			CardInstance.SpecialCondition.POISONED:  {"label": "POISONED",  "color": Color(0.62, 0.08, 0.82)},
			CardInstance.SpecialCondition.BURNED:    {"label": "BURNED",    "color": Color(0.95, 0.38, 0.04)},
			CardInstance.SpecialCondition.PARALYZED: {"label": "PARALYZED", "color": Color(0.90, 0.85, 0.08)},
			CardInstance.SpecialCondition.ASLEEP:    {"label": "ASLEEP",    "color": Color(0.28, 0.28, 0.68)},
			CardInstance.SpecialCondition.CONFUSED:  {"label": "CONFUSED",  "color": Color(0.78, 0.38, 0.68)},
		}
		var chip_x := 4.0
		for cond in COND_COLORS.keys():
			if not inst.has_condition(cond as CardInstance.SpecialCondition):
				continue
			var info: Dictionary = COND_COLORS[cond]
			var chip := _make_popup_status_chip(info["label"] as String, info["color"] as Color)
			chip.position = Vector2(chip_x, bar_y - 30.0)
			_popup_art_container.add_child(chip)
			chip_x += chip.custom_minimum_size.x + 4.0

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


func _make_popup_status_chip(label_text: String, color: Color) -> Label:
	var chip := Label.new()
	chip.text = label_text
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left   = 6.0
	style.content_margin_right  = 6.0
	style.content_margin_top    = 3.0
	style.content_margin_bottom = 3.0
	chip.add_theme_stylebox_override("normal", style)
	## get_minimum_size() returns 0 before the node is in the scene tree, so
	## we estimate width from character count instead.  At 13 px font size each
	## character is roughly 8 px wide; add 16 px for the two content margins.
	## The longest status name is "PARALYZED" (9 chars) → ~88 px.
	chip.custom_minimum_size = Vector2(label_text.length() * 8.0 + 16.0, 24.0)
	return chip


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


# ===========================================================================
# COIN FLIP OVERLAY — game effects
# Uses the same animated coin visual as the "who goes first" flip.
# ===========================================================================

func _on_coin_flip_batch_ready(batch: Array) -> void:
	for entry in batch:
		await _show_coin_flip_visual(entry["results"] as Array, entry["reason"] as String)


## Animated coin-flip result overlay used for all in-game coin-flip effects.
## [results] — Array[bool], true = heads.  Shows one coin per result, sequentially.
func _show_coin_flip_visual(results: Array, subtitle: String, btn_text: String = "OK") -> void:
	const FLIP_SPEED_SINGLE := 0.10
	const FLIP_SPEED_MULTI  := 0.05
	const MIN_FLIPS_SINGLE  := 6
	const MIN_FLIPS_MULTI   := 4
	const HEADS_COLOR := Color(1.0, 0.82, 0.10)
	const TAILS_COLOR := Color(0.62, 0.44, 0.05)

	var flip_speed  := FLIP_SPEED_SINGLE if results.size() == 1 else FLIP_SPEED_MULTI
	var min_flips   := MIN_FLIPS_SINGLE  if results.size() == 1 else MIN_FLIPS_MULTI

	var overlay := CanvasLayer.new()
	overlay.layer = 15
	add_child(overlay)

	## Full-rect input blocker.
	var blocker := ColorRect.new()
	blocker.color = Color(0.0, 0.0, 0.0, 0.78)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(blocker)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color               = Color(0.10, 0.12, 0.20, 0.97)
	panel_style.corner_radius_top_left    = 10
	panel_style.corner_radius_top_right   = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text               = "COIN FLIP"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text               = subtitle
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	vbox.add_child(sub_lbl)

	## Counter label (hidden for single flips).
	var count_lbl := Label.new()
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	count_lbl.visible = results.size() > 1
	vbox.add_child(count_lbl)

	var coin_center := CenterContainer.new()
	coin_center.custom_minimum_size = Vector2(0, 150)
	vbox.add_child(coin_center)

	var coin := PanelContainer.new()
	coin.custom_minimum_size = Vector2(120, 120)
	coin.pivot_offset = Vector2(60, 60)
	var coin_style := StyleBoxFlat.new()
	coin_style.bg_color                   = HEADS_COLOR
	coin_style.corner_radius_top_left     = 60
	coin_style.corner_radius_top_right    = 60
	coin_style.corner_radius_bottom_left  = 60
	coin_style.corner_radius_bottom_right = 60
	coin.add_theme_stylebox_override("panel", coin_style)
	coin_center.add_child(coin)

	var coin_lbl := Label.new()
	coin_lbl.text               = "H"
	coin_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	coin_lbl.add_theme_font_size_override("font_size", 52)
	coin_lbl.add_theme_color_override("font_color", Color(0.55, 0.38, 0.0))
	coin_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coin.add_child(coin_lbl)

	var result_lbl := Label.new()
	result_lbl.text               = ""
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 18)
	result_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.40))
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(result_lbl)

	var ok_btn := Button.new()
	ok_btn.text    = btn_text
	ok_btn.visible = false
	vbox.add_child(ok_btn)

	await get_tree().process_frame

	for i in range(results.size()):
		var is_heads: bool = results[i]

		## Reset coin state for each flip.
		coin.scale      = Vector2(1, 1)
		coin_lbl.text   = "H"
		coin_style.bg_color = HEADS_COLOR
		result_lbl.text = ""
		ok_btn.visible  = false
		if results.size() > 1:
			count_lbl.text = "Flip %d / %d" % [i + 1, results.size()]

		## Compute flip count so the coin ends on the correct side.
		## Starting at "H" (showing_heads = true after 0 flips).
		## After N flips: heads if N even, tails if N odd.
		var flip_count := min_flips + (randi() % 4) * 2
		if is_heads:
			if flip_count % 2 != 0:
				flip_count += 1
		else:
			if flip_count % 2 != 1:
				flip_count += 1

		var showing_heads := true
		for _f in range(flip_count):
			var t1 := create_tween()
			t1.tween_property(coin, "scale", Vector2(0.06, 1.0), flip_speed)
			await t1.finished
			showing_heads = not showing_heads
			coin_style.bg_color = HEADS_COLOR if showing_heads else TAILS_COLOR
			coin_lbl.text       = "H" if showing_heads else "T"
			var t2 := create_tween()
			t2.tween_property(coin, "scale", Vector2(1.0, 1.0), flip_speed)
			await t2.finished

		result_lbl.text = "HEADS" if is_heads else "TAILS"

		if i < results.size() - 1:
			## Brief pause before the next coin.
			await get_tree().create_timer(0.35).timeout
		else:
			ok_btn.visible = true
			await ok_btn.pressed

	overlay.queue_free()


# ===========================================================================
# CARD SEARCH POPUP
# Full-screen overlay for choosing cards from deck or discard pile.
# ===========================================================================

func _on_card_search_requested(
		pile: Array,
		max_count: int,
		reason: String,
		preceding_flips: Array,
		actor_id: int
) -> void:
	## CPU: auto-select up to max_count cards, no UI shown.
	if not is_developer_mode and controlling_player != actor_id:
		var auto_chosen: Array = []
		for card in pile:
			if auto_chosen.size() >= max_count:
				break
			auto_chosen.append(card)
		turn_controller.resolve_card_search(auto_chosen)
		return

	## Show preceding coin flip results first (e.g. Poké Ball heads before search).
	for entry in preceding_flips:
		await _show_coin_flip_visual(entry["results"] as Array, entry["reason"] as String)

	## Then show the search popup.
	await _show_card_search_popup(pile, max_count, reason)


## Full-screen card-search popup.  Resolves via turn_controller.resolve_card_search().
func _show_card_search_popup(pile: Array, max_count: int, reason: String) -> void:
	const CARD_W := 120
	const CARD_H := 168  ## same aspect ratio as the inspect popup art
	const CARD_GAP := 8

	## Close any existing popup.
	if _card_search_overlay != null and is_instance_valid(_card_search_overlay):
		_card_search_overlay.queue_free()

	_card_search_overlay = CanvasLayer.new()
	_card_search_overlay.layer = 12
	add_child(_card_search_overlay)

	## Input-blocking background.
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_search_overlay.add_child(bg)

	## Root container (fills screen, leaving margins).
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left",   24)
	root.add_theme_constant_override("margin_right",  24)
	root.add_theme_constant_override("margin_top",    20)
	root.add_theme_constant_override("margin_bottom", 20)
	_card_search_overlay.add_child(root)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	root.add_child(outer_vbox)

	## ── Top bar ──────────────────────────────────────────────────────────
	var top_bar := HBoxContainer.new()
	outer_vbox.add_child(top_bar)

	var title_lbl := Label.new()
	title_lbl.text = reason
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_lbl)

	var see_board_btn := Button.new()
	see_board_btn.text = "See Board"
	top_bar.add_child(see_board_btn)

	## ── Instruction label ────────────────────────────────────────────────
	var instr_lbl := Label.new()
	instr_lbl.text = "Select up to %d card%s  (right-click to inspect)" % \
		[max_count, "s" if max_count != 1 else ""]
	instr_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	outer_vbox.add_child(instr_lbl)

	## ── Scrollable card grid ─────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", CARD_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GAP)
	scroll.add_child(grid)

	## ── Bottom bar ───────────────────────────────────────────────────────
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 12)
	outer_vbox.add_child(bottom_bar)

	var sel_lbl := Label.new()
	sel_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	sel_lbl.text = "No card selected."
	bottom_bar.add_child(sel_lbl)

	var confirm_btn := Button.new()
	confirm_btn.text     = "Confirm Selection"
	confirm_btn.disabled = true
	bottom_bar.add_child(confirm_btn)

	## ── Build card tiles ─────────────────────────────────────────────────
	var selected: Array[CardInstance] = []

	## Selected-border style (gold highlight).
	var sel_style := StyleBoxFlat.new()
	sel_style.bg_color                   = Color(0.10, 0.12, 0.18, 0.95)
	sel_style.border_color               = Color(1.0, 0.82, 0.10)
	sel_style.border_width_left   = 3
	sel_style.border_width_right  = 3
	sel_style.border_width_top    = 3
	sel_style.border_width_bottom = 3
	sel_style.corner_radius_top_left    = 4
	sel_style.corner_radius_top_right   = 4
	sel_style.corner_radius_bottom_left = 4
	sel_style.corner_radius_bottom_right = 4

	var unsel_style := StyleBoxFlat.new()
	unsel_style.bg_color                   = Color(0.10, 0.12, 0.18, 0.95)
	unsel_style.border_color               = Color(0.3, 0.3, 0.4)
	unsel_style.border_width_left   = 2
	unsel_style.border_width_right  = 2
	unsel_style.border_width_top    = 2
	unsel_style.border_width_bottom = 2
	unsel_style.corner_radius_top_left    = 4
	unsel_style.corner_radius_top_right   = 4
	unsel_style.corner_radius_bottom_left = 4
	unsel_style.corner_radius_bottom_right = 4

	## Refresh confirm button and selection label.
	var update_ui := func() -> void:
		var names := []
		for inst in selected:
			names.append(inst.data.display_name if inst.data else "?")
		if names.is_empty():
			sel_lbl.text = "No card selected."
		else:
			sel_lbl.text = "Selected: " + ", ".join(names)
		confirm_btn.disabled = selected.is_empty()

	for raw in pile:
		var inst := raw as CardInstance
		if inst == null or inst.data == null:
			continue

		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(CARD_W, CARD_H + 24)
		tile.add_theme_stylebox_override("panel", unsel_style.duplicate())
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		grid.add_child(tile)

		var tile_vbox := VBoxContainer.new()
		tile_vbox.add_theme_constant_override("separation", 2)
		tile.add_child(tile_vbox)

		var art := TextureRect.new()
		art.texture        = inst.data.art
		art.custom_minimum_size = Vector2(CARD_W, CARD_H)
		art.expand_mode    = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode   = TextureRect.STRETCH_SCALE
		art.mouse_filter   = Control.MOUSE_FILTER_PASS
		tile_vbox.add_child(art)

		var name_lbl := Label.new()
		name_lbl.text = inst.data.display_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
		name_lbl.clip_text = true
		tile_vbox.add_child(name_lbl)

		var captured_inst := inst
		var captured_tile := tile

		tile.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton):
				return
			var mb := event as InputEventMouseButton
			if not mb.pressed:
				return
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				## Open inspect popup.
				_populate_card_popup(captured_inst)
				_card_popup.visible = true
				get_viewport().set_input_as_handled()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				## Toggle selection.
				if selected.has(captured_inst):
					selected.erase(captured_inst)
					captured_tile.add_theme_stylebox_override(
						"panel", unsel_style.duplicate())
				else:
					if selected.size() < max_count:
						selected.append(captured_inst)
						captured_tile.add_theme_stylebox_override(
							"panel", sel_style.duplicate())
				update_ui.call()
				get_viewport().set_input_as_handled()
		)

	## ── See Board / See Selection toggle ─────────────────────────────────
	see_board_btn.pressed.connect(func() -> void:
		_card_search_overlay.visible = false
		## Floating "See Selection" button added to HUD.
		if _see_board_btn != null and is_instance_valid(_see_board_btn):
			_see_board_btn.queue_free()
		_see_board_btn = Button.new()
		_see_board_btn.text = "See Selection"
		_see_board_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		_see_board_btn.offset_left  = -180.0
		_see_board_btn.offset_right =    0.0
		_see_board_btn.offset_top   =   50.0
		_see_board_btn.offset_bottom =  86.0
		$HUD.add_child(_see_board_btn)
		_see_board_btn.pressed.connect(func() -> void:
			_card_search_overlay.visible = true
			if _see_board_btn != null and is_instance_valid(_see_board_btn):
				_see_board_btn.queue_free()
			_see_board_btn = null
		)
	)

	## ── Await confirmation ────────────────────────────────────────────────
	await confirm_btn.pressed

	## Clean up floating button if still visible.
	if _see_board_btn != null and is_instance_valid(_see_board_btn):
		_see_board_btn.queue_free()
	_see_board_btn = null

	_card_search_overlay.queue_free()
	_card_search_overlay = null

	turn_controller.resolve_card_search(selected)


# ===========================================================================
# ENERGY DISCARD PICKER
# Small modal for choosing which attached energy to pay for retreat.
# ===========================================================================

func _on_energy_discard_choice_requested(
		energies: Array,
		count: int,
		pokemon_name: String
) -> void:
	## This signal is only emitted by the UI layer itself (_on_retreat_button_pressed),
	## so it always targets the controlling player.  No CPU check needed.
	pass  ## Handled directly via _show_energy_discard_picker().


## Shows a picker where the player selects [count] energy cards to discard.
func _show_energy_discard_picker(
		energies: Array,
		count: int,
		pokemon_name: String,
		on_confirm: Callable
) -> void:
	if _energy_discard_picker != null and is_instance_valid(_energy_discard_picker):
		_energy_discard_picker.queue_free()

	_energy_discard_picker = PanelContainer.new()
	_energy_discard_picker.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_energy_discard_picker.custom_minimum_size = Vector2(360, 0)

	var pick_style := StyleBoxFlat.new()
	pick_style.bg_color = Color(0.08, 0.10, 0.16, 0.97)
	pick_style.corner_radius_top_left    = 8
	pick_style.corner_radius_top_right   = 8
	pick_style.corner_radius_bottom_left = 8
	pick_style.corner_radius_bottom_right = 8
	_energy_discard_picker.add_theme_stylebox_override("panel", pick_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_energy_discard_picker.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Choose %d Energy to discard (%s)" % [count, pokemon_name]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	vbox.add_child(title_lbl)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	vbox.add_child(flow)

	var sel_lbl := Label.new()
	sel_lbl.text = "Selected: 0 / %d" % count
	sel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	vbox.add_child(sel_lbl)

	var confirm_btn := Button.new()
	confirm_btn.text     = "Confirm"
	confirm_btn.disabled = true
	vbox.add_child(confirm_btn)

	var selected_energy: Array[CardInstance] = []

	for raw in energies:
		var inst := raw as CardInstance
		if inst == null or inst.data == null:
			continue

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 64)
		btn.focus_mode = Control.FOCUS_NONE

		var etype: PokemonCardData.EnergyType = PokemonCardData.EnergyType.NONE
		if inst.data is EnergyCardData:
			etype = (inst.data as EnergyCardData).energy_type
		var btn_color := AttachmentDisplay.energy_color(inst)

		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = btn_color
		normal_style.corner_radius_top_left    = 32
		normal_style.corner_radius_top_right   = 32
		normal_style.corner_radius_bottom_left = 32
		normal_style.corner_radius_bottom_right = 32
		var sel_energy_style := normal_style.duplicate() as StyleBoxFlat
		sel_energy_style.border_color = Color.WHITE
		sel_energy_style.border_width_left   = 3
		sel_energy_style.border_width_right  = 3
		sel_energy_style.border_width_top    = 3
		sel_energy_style.border_width_bottom = 3
		btn.add_theme_stylebox_override("normal",  normal_style)
		btn.add_theme_stylebox_override("hover",   normal_style)
		btn.add_theme_stylebox_override("pressed", sel_energy_style)

		var lbl := Label.new()
		lbl.text = AttachmentDisplay.energy_label(inst)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.add_child(lbl)

		if inst.data != null:
			btn.tooltip_text = inst.data.display_name

		flow.add_child(btn)

		var captured_inst := inst
		var captured_btn  := btn
		btn.pressed.connect(func() -> void:
			if selected_energy.has(captured_inst):
				selected_energy.erase(captured_inst)
				captured_btn.add_theme_stylebox_override("normal", normal_style)
				captured_btn.add_theme_stylebox_override("hover",  normal_style)
			else:
				if selected_energy.size() < count:
					selected_energy.append(captured_inst)
					captured_btn.add_theme_stylebox_override("normal", sel_energy_style)
					captured_btn.add_theme_stylebox_override("hover",  sel_energy_style)
			sel_lbl.text = "Selected: %d / %d" % [selected_energy.size(), count]
			confirm_btn.disabled = selected_energy.size() != count
		)

	$HUD.add_child(_energy_discard_picker)

	await confirm_btn.pressed

	_energy_discard_picker.queue_free()
	_energy_discard_picker = null
	on_confirm.call(selected_energy)
