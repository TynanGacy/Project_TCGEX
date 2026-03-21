extends Control
class_name Table


# ============================================================
#	Table.gd
#	- Spawns test cards into hand (both players)
#	- Handles selection + click interactions
#	- Moves CardViews between Hand/Bench/ActiveSlots
#	- Updates CardInstance.zone when a CardView moves
#
#	Game actions and state bridge live in:
#	  scripts/actions/action_play_selected_to_bench.gd
#	  scripts/actions/action_play_selected_to_empty_active.gd
#	  scripts/actions/action_promote_selected_to_active.gd
#	  scripts/actions/action_swap_active_slot_with_bench_index.gd
#	  scripts/game/table_game_state.gd
#
#	Layout positioning lives in:
#	  scenes/table/table_layout.gd
# ============================================================

# ============================================================
#	Packed scenes
# ============================================================
var card_view_scene: PackedScene = preload("res://scenes/card/card_view.tscn")

# ============================================================
#	Node references (UI + Zones)
# ============================================================
@onready var player_slots: SlotOverlay = %PlayerSlotOverlay
@onready var opponent_slots: SlotOverlay = %OpponentSlotOverlay
@onready var stadium_slot: ColorRect = %StadiumSlot

@onready var end_turn_button: Button = %EndTurnButton
@onready var phase_label: Label = %PhaseLabel
@onready var game_log: RichTextLabel = %GameLog
@onready var turn_controller: TurnController = TurnControllerSingleton

@onready var player_hand_zone: HBoxContainer = %PlayerHandZone
@onready var player_bench_zone: HBoxContainer = %PlayerBenchZone
@onready var active_slots_container: HBoxContainer = %PlayerActiveSlots

@onready var active_click_area: Control = %PlayerActiveClickArea
@onready var bench_click_area: Control = %PlayerBenchClickArea

@onready var opponent_hand_zone: HBoxContainer = %OpponentHandZone
@onready var opponent_bench_zone: HBoxContainer = %OpponentBenchZone
@onready var opponent_active_slots_container: HBoxContainer = %OpponentActiveSlots

@onready var opponent_active_click_area: Control = %OpponentActiveClickArea
@onready var opponent_bench_click_area: Control = %OpponentBenchClickArea

# Per-player zone collections (index 0 = player, index 1 = opponent)
var _hand_zones: Array[HBoxContainer] = []
var _bench_zones: Array[HBoxContainer] = []
var _active_slots_by_player: Array = []
var _hover_popup: CardHoverPopup
var _hover_timer: Timer
var _hover_card: CardView = null
var hovered_card: CardView = null


# ============================================================
#	Match config / Limits
# ============================================================
@export var num_active_slots: int = 2 # set to 2 for doubles
@export var max_bench: int = 4

# ============================================================
#	Test content
# ============================================================
var test_cards: Array[CardData] = [
	preload("res://data/cards/pokemon/pikachu_basic.tres"),
	preload("res://data/cards/pokemon/pikachu_basic.tres"),
]
@export var test_hand_size: int = 7

# ============================================================
#	Runtime state
# ============================================================
var selected_card_view: Node = null

# ============================================================
#	Turn-engine bridge state
# ============================================================
var _table_state: TableGameState


# ============================================================
#	Lifecycle
# ============================================================
func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_log_line("Table loaded.")

	# Build per-player collections FIRST (fixes your init-order bug)
	_hand_zones = [player_hand_zone, opponent_hand_zone]
	_bench_zones = [player_bench_zone, opponent_bench_zone]
	_active_slots_by_player = [[], []]

	_cache_active_slots_for_player(0, active_slots_container)
	_cache_active_slots_for_player(1, opponent_active_slots_container)
	_apply_active_slot_format_for_player(0)
	_apply_active_slot_format_for_player(1)

	# Empty-space click handlers for zones
	_connect_click_area(active_click_area, "active_click_area", func(e): _on_active_zone_input(0, e))
	_connect_click_area(bench_click_area, "bench_click_area", func(e): _on_bench_zone_input(0, e))
	_connect_click_area(opponent_active_click_area, "opponent_active_click_area", func(e): _on_active_zone_input(1, e))
	_connect_click_area(opponent_bench_click_area, "opponent_bench_click_area", func(e): _on_bench_zone_input(1, e))

	# Turn engine bridge
	_table_state = TableGameState.new(self)
	turn_controller.set_state(_table_state)

	turn_controller.phase_changed.connect(_on_phase_changed)
	turn_controller.action_rejected.connect(_on_action_rejected)
	turn_controller.action_committed.connect(_on_action_committed)
	turn_controller.log_message.connect(_on_turn_log)


	_on_phase_changed(_table_state.phase)

	_hover_timer = Timer.new()
	_hover_timer.one_shot = true
	_hover_timer.wait_time = 0.5
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)

# Hover popup (single shared instance)
	var hover_popup_scene: PackedScene = preload("res://scenes/ui/card_hover_popup.tscn")
	_hover_popup = hover_popup_scene.instantiate() as CardHoverPopup
	add_child(_hover_popup)
	_hover_popup.hide()

	call_deferred("_refresh_playmat_layout")

	# Spawn test hands for BOTH players
	_spawn_test_hand(0, test_hand_size)
	_spawn_test_hand(1, test_hand_size)


# ============================================================
#	turn_controller signal handlers
# ============================================================
func _on_phase_changed(phase: int) -> void:
	phase_label.text = "Phase: %s" % TurnPhase.phase_to_string(phase)

func _on_action_rejected(action: GameAction, reason: String) -> void:
	_log_line("[REJECT] %s (%s)" % [action.description(), reason])

func _on_action_committed(action: GameAction) -> void:
	ensure_required_actives_if_possible(0)
	ensure_required_actives_if_possible(1)
	call_deferred("_refresh_playmat_layout")

func _on_turn_log(text: String) -> void:
	_log_line(text)


# ============================================================
#	Logging
# ============================================================
func _log_line(text: String) -> void:
	game_log.append_text(text + "\n")


# ============================================================
#	UI event handlers
# ============================================================
func _on_end_turn_pressed() -> void:
	_log_line("Turn button pressed.")
	var actor := turn_controller.state.current_player_id
	if _table_state.phase == TurnPhase.Phase.END:
		turn_controller.end_turn(actor)
	else:
		turn_controller.next_phase(actor)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_selected_card(null)

func _on_active_zone_input(player_id: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_play_selected_to_active(player_id)

func _on_bench_zone_input(player_id: int, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_try_play_selected_to_bench(player_id)


# ============================================================
#	Selection + Card click dispatch
# ============================================================
func _on_card_clicked(card_view: Node) -> void:
	if selected_card_view == null or not is_instance_valid(selected_card_view):
		_set_selected_card(card_view)
		return

	if selected_card_view == card_view:
		_set_selected_card(null)
		return

	if _try_swap_between_active_and_bench(selected_card_view, card_view):
		_set_selected_card(null)
		return

	_set_selected_card(card_view)

func _set_selected_card(card_view: Node) -> void:
	if selected_card_view != null and is_instance_valid(selected_card_view):
		selected_card_view.set_selected(false)

	selected_card_view = card_view

	if selected_card_view != null and is_instance_valid(selected_card_view):
		selected_card_view.set_selected(true)
		_log_line("Selected: " + selected_card_view.name)
	else:
		_log_line("Selection cleared.")


# ============================================================
#	Zone actions: play/promote (via turn_controller)
# ============================================================
func _try_play_selected_to_active(target_player_id: int) -> void:
	if selected_card_view == null or not is_instance_valid(selected_card_view):
		return

	var actor := _owner_from_card_parent(selected_card_view)
	if actor == -1:
		_log_line("Selected card owner could not be determined.")
		return

	var empty_slot := get_first_empty_active_slot_index(target_player_id)
	if empty_slot == -1:
		_log_line("Active zone is full. Click an active Pokémon to swap instead.")
		return

	var parent := selected_card_view.get_parent()

	if parent == _hand_zones[target_player_id]:
		turn_controller.request_action(ActionPlaySelectedToEmptyActive.new(actor, selected_card_view, target_player_id, empty_slot))
		_set_selected_card(null)
		return

	if parent == _bench_zones[target_player_id]:
		turn_controller.request_action(ActionPromoteSelectedBenchToEmptyActive.new(actor, selected_card_view, target_player_id, empty_slot))
		_set_selected_card(null)
		return

	_log_line("Selected card isn't in the correct zone for this action.")

func _try_play_selected_to_bench(target_player_id: int) -> void:
	if selected_card_view == null or not is_instance_valid(selected_card_view):
		return

	var actor := _owner_from_card_parent(selected_card_view)
	if actor == -1:
		return

	if selected_card_view.get_parent() == _hand_zones[target_player_id]:
		turn_controller.request_action(ActionPlaySelectedToBench.new(actor, selected_card_view, target_player_id))
		_set_selected_card(null)


# ============================================================
#	Swapping: Active <-> Bench (via turn_controller)
# ============================================================
func _try_swap_between_active_and_bench(a: Node, b: Node) -> bool:
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false

	var a_owner := _owner_from_card_parent(a)
	var b_owner := _owner_from_card_parent(b)
	if a_owner == -1 or b_owner == -1:
		return false

	if a_owner != b_owner:
		return false

	var board_player_id := a_owner

	var a_in_active := _is_in_active(board_player_id, a)
	var a_in_bench := _is_in_bench(board_player_id, a)
	var b_in_active := _is_in_active(board_player_id, b)
	var b_in_bench := _is_in_bench(board_player_id, b)

	if (a_in_active and b_in_bench) or (a_in_bench and b_in_active):
		var active_card := a if a_in_active else b
		var bench_card := b if b_in_bench else a

		var active_slot_index := _get_active_slot_index_for_card(board_player_id, active_card)
		var bench_index := _get_bench_index_for_card(board_player_id, bench_card)

		if active_slot_index == -1 or bench_index == -1:
			return false

		turn_controller.request_action(ActionSwapActiveSlotWithBenchIndex.new(board_player_id, board_player_id, active_slot_index, bench_index))
		return true

	return false


# ============================================================
#	Active slots: caching + display format
# ============================================================
func _cache_active_slots_for_player(player_id: int, slots_container: HBoxContainer) -> void:
	if slots_container == null:
		push_error("Active slots container is NULL for player_id=%d. Check your node path / scene tree." % player_id)
		return

	var slots: Array = _active_slots_by_player[player_id]
	slots.clear()

	for child in slots_container.get_children():
		if child is Control:
			slots.append(child)

	if slots.is_empty():
		push_warning("Active slots list is empty for player_id=%d. Container has no Control children." % player_id)


func _apply_active_slot_format_for_player(player_id: int) -> void:
	var slots: Array = _active_slots_by_player[player_id]
	for i in range(slots.size()):
		(slots[i] as Control).visible = (i < num_active_slots)

func get_active_card(player_id: int, slot_index: int) -> Node:
	if slot_index < 0 or slot_index >= num_active_slots:
		return null
	var slots: Array = _active_slots_by_player[player_id]
	var slot := slots[slot_index] as Control
	for child in slot.get_children():
		if _is_card_view(child):
			return child
	return null

func get_first_empty_active_slot_index(player_id: int) -> int:
	for i in range(num_active_slots):
		if get_active_card(player_id, i) == null:
			return i
	return -1

func move_card_to_active_slot(player_id: int, card_view: Node, slot_index: int) -> void:
	var slots: Array = _active_slots_by_player[player_id]
	var slot := slots[slot_index] as Control
	var old_parent := card_view.get_parent()
	if old_parent != null:
		old_parent.remove_child(card_view)
	slot.add_child(card_view)
	_sync_instance_zone(card_view, CardInstance.Zone.ACTIVE)


# ============================================================
#	Movement helpers + instance zone syncing
# ============================================================
func _move_card_to_zone(card_view: Node, zone: Node, owner_player_id: int) -> void:
	var old_parent := card_view.get_parent()
	if old_parent != null:
		old_parent.remove_child(card_view)

	zone.add_child(card_view)
	_log_line("Moved card to " + zone.name)

	if zone == _hand_zones[owner_player_id]:
		_sync_instance_zone(card_view, CardInstance.Zone.HAND)
	elif zone == _bench_zones[owner_player_id]:
		_sync_instance_zone(card_view, CardInstance.Zone.BENCH)
	else:
		_sync_instance_zone(card_view, CardInstance.Zone.OTHER)

func _sync_instance_zone(card_view: Node, z: CardInstance.Zone) -> void:
	var view := card_view as CardView
	if view == null:
		return
	var inst: CardInstance = view.get_instance()
	if inst != null:
		inst.zone = z


# ============================================================
#	Counting / queries
# ============================================================
func _count_cards_in_zone(zone: Node) -> int:
	var count := 0
	for child in zone.get_children():
		if _is_card_view(child):
			count += 1
	return count

func _is_card_view(node: Node) -> bool:
	return node != null and node.has_method("set_selected") and node.has_signal("clicked")

func _is_in_active(player_id: int, node: Node) -> bool:
	var p := node.get_parent()
	var slots: Array = _active_slots_by_player[player_id]
	return p != null and slots.has(p)

func _is_in_bench(player_id: int, node: Node) -> bool:
	return node.get_parent() == _bench_zones[player_id]


# ============================================================
#	Index helpers for swap actions
# ============================================================
func _get_active_slot_index_for_card(player_id: int, card: Node) -> int:
	if card == null or not is_instance_valid(card):
		return -1
	var p := card.get_parent()
	if p == null:
		return -1
	var slots: Array = _active_slots_by_player[player_id]
	for i in range(num_active_slots):
		if slots[i] == p:
			return i
	return -1

func _get_bench_index_for_card(player_id: int, card: Node) -> int:
	if card == null or not is_instance_valid(card):
		return -1
	if card.get_parent() != _bench_zones[player_id]:
		return -1
	return card.get_index()

func _get_bench_card_by_index(player_id: int, bench_index: int) -> Node:
	var bench := _bench_zones[player_id]
	if bench_index < 0 or bench_index >= bench.get_child_count():
		return null
	var node := bench.get_child(bench_index)
	return node if _is_card_view(node) else null

func _swap_active_slot_with_bench_index(player_id: int, active_slot_index: int, bench_index: int) -> void:
	var active_card := get_active_card(player_id, active_slot_index)
	var bench_card := _get_bench_card_by_index(player_id, bench_index)
	if active_card == null or bench_card == null:
		return

	var bench_parent := _bench_zones[player_id]
	var slots: Array = _active_slots_by_player[player_id]
	var active_parent := slots[active_slot_index] as Control

	active_parent.remove_child(active_card)
	bench_parent.remove_child(bench_card)

	active_parent.add_child(bench_card)
	bench_parent.add_child(active_card)
	bench_parent.move_child(active_card, bench_index)

	_sync_instance_zone(bench_card, CardInstance.Zone.ACTIVE)
	_sync_instance_zone(active_card, CardInstance.Zone.BENCH)

	_log_line("Swapped P%d Active[%d] and Bench[%d]." % [player_id, active_slot_index, bench_index])


# ============================================================
#	Rule maintenance: keep required actives filled (if possible)
# ============================================================
func ensure_required_actives_if_possible(player_id: int) -> void:
	while get_active_count(player_id) < num_active_slots and get_bench_count(player_id) > 0:
		var card := take_first_bench_card(player_id)
		if card == null:
			return
		var slot_index := get_first_empty_active_slot_index(player_id)
		if slot_index == -1:
			return
		move_card_to_active_slot(player_id, card, slot_index)

func get_active_count(player_id: int) -> int:
	var count := 0
	for i in range(num_active_slots):
		if get_active_card(player_id, i) != null:
			count += 1
	return count

func get_bench_count(player_id: int) -> int:
	return _count_cards_in_zone(_bench_zones[player_id])

func take_first_bench_card(player_id: int) -> Node:
	for child in _bench_zones[player_id].get_children():
		if _is_card_view(child):
			return child
	return null

# ============================================================
#	Test: spawn hand cards (per player)
# ============================================================
func _spawn_test_hand(player_id: int, count: int) -> void:
	if player_id < 0 or player_id >= _hand_zones.size():
		push_error("_spawn_test_hand: invalid player_id=%d" % player_id)
		return

	var zone: HBoxContainer = _hand_zones[player_id]
	if zone == null:
		push_error("_spawn_test_hand: hand zone is NULL for player_id=%d. Fix node paths / unique names." % player_id)
		return

	for child in zone.get_children():
		child.queue_free()

	if player_id == 0:
		selected_card_view = null

	for i in range(count):
		var card_view: CardView = card_view_scene.instantiate()
		zone.add_child(card_view)
		card_view.clicked.connect(_on_card_clicked)
		card_view.hover_started.connect(_on_card_hover_started)
		card_view.hover_ended.connect(_on_card_hover_ended)

		var data := test_cards[i % test_cards.size()]
		var inst: CardInstance = CardInstance.create(data)
		inst.zone = CardInstance.Zone.HAND
		card_view.set_instance(inst)

# ============================================================
#	Determine card owner by parent zone/slot
# ============================================================
func _owner_from_card_parent(card_view: Node) -> int:
	if card_view == null or not is_instance_valid(card_view):
		return -1
	var p := card_view.get_parent()

	if p == _hand_zones[0] or p == _bench_zones[0] or _active_slots_by_player[0].has(p):
		return 0
	if p == _hand_zones[1] or p == _bench_zones[1] or _active_slots_by_player[1].has(p):
		return 1

	return -1

func _connect_click_area(area: Control, label: String, cb: Callable) -> void:
	if area == null:
		push_error("%s is NULL. Update node path or set Unique Name and use %%NodeName." % label)
		return
	area.gui_input.connect(cb)

func _on_card_hover_started(card: CardView) -> void:
	_hover_timer.stop()
	_hover_card = card
	_hover_timer.start()

func _on_card_hover_ended(card: CardView) -> void:
	_hover_timer.stop()
	if card == _hover_card:
		_hover_card = null
	if _hover_popup != null:
		_hover_popup.hide()

func _on_hover_timer_timeout() -> void:
	if _hover_card == null or not is_instance_valid(_hover_card):
		return
	if _hover_popup != null:
		_hover_popup.show_for(_hover_card)


# ============================================================
#	Playmat layout (delegates to TableLayout)
# ============================================================
func _refresh_playmat_layout() -> void:
	if player_slots == null or opponent_slots == null or stadium_slot == null:
		return

	var player_active := num_active_slots
	var player_bench := max_bench
	var opp_active := num_active_slots
	var opp_bench := max_bench

	var p_rect := Rect2(Vector2.ZERO, player_slots.size)
	var o_rect := Rect2(Vector2.ZERO, opponent_slots.size)

	var p := player_slots.update_layout(p_rect, player_active, player_bench, "player")
	var o := opponent_slots.update_layout(o_rect, opp_active, opp_bench, "opponent")

	# Delegate card container positioning to TableLayout
	TableLayout.position_card_containers(
		0, p, player_slots.global_position,
		num_active_slots, _active_slots_by_player[0], _bench_zones[0],
		player_slots, active_click_area, bench_click_area,
	)
	TableLayout.position_card_containers(
		1, o, opponent_slots.global_position,
		num_active_slots, _active_slots_by_player[1], _bench_zones[1],
		opponent_slots, opponent_active_click_area, opponent_bench_click_area,
	)

	# Stadium sizing: square, same scale as active
	var stadium_s := player_slots.bench_sq * player_slots.stadium_scale
	stadium_slot.size = Vector2(stadium_s, stadium_s)

	var deck_x_global := player_slots.global_position.x + float(p["deck_x"])
	var stadium_x := deck_x_global + (player_slots.card_rect.x - stadium_s) * 0.5

	var opp_bottom := opponent_slots.global_position.y + opponent_slots.size.y
	var player_top := player_slots.global_position.y
	var mid_y := (opp_bottom + player_top) * 0.5
	var stadium_y := mid_y - stadium_s * 0.5

	stadium_slot.global_position = Vector2(stadium_x, stadium_y)

func _enter_tree() -> void:
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	call_deferred("_refresh_playmat_layout")
