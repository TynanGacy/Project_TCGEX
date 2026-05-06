class_name InputManager
extends Node

## Handles all mouse/keyboard input: drag, hover, raycast, and drop routing.
## Added as a child of Main so Godot propagates _unhandled_input automatically.

var _main: Node = null

var dragged_card: Card = null
var _hovered_node: Node3D = null
var _setup_dragged_instance: PokemonInstance = null
var _setup_dragged_from_slot: String = ""

const DRAG_PLANE := Plane(Vector3.UP, 0.0)


func init(main_node: Node) -> void:
	_main = main_node


func reset() -> void:
	if _setup_dragged_instance != null:
		_setup_dragged_instance.queue_free()
		_setup_dragged_instance = null
	_setup_dragged_from_slot = ""
	dragged_card = null
	_hovered_node = null


func _unhandled_input(event: InputEvent) -> void:
	if _main._setup_dialog != null or _main._in_setup_phase:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and _main.card_zoom_popup != null and _main.card_zoom_popup.visible:
			_main.card_zoom_popup.hide_popup()
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
		if ke.pressed and ke.keycode == KEY_ESCAPE and _main.card_zoom_popup != null:
			_main.card_zoom_popup.hide_popup()
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
		if _main.manager.setup_placing_player >= 0:
			_try_pick_setup_instance(card)
			return
		if _main.manager.prize_selection_phase_for >= 0:
			_try_pick_prize_card(card)
		return
	if card.face_down or card.data == null:
		return
	var card_owner: int = 0 if card.get_parent() == _main.player_hand else 1
	if card_owner != _main._authority.current_player_id():
		return
	if _hovered_node == card:
		_hovered_node = null
	dragged_card = card
	card.start_drag()


func _try_pick_prize_card(card: Card) -> void:
	var pid: int = _main.manager.prize_selection_phase_for
	var prefix := MatchUIUtils.zone_prefix(pid)
	var parent := card.get_parent()
	if not (parent is DropZone):
		return
	var zone := parent as DropZone
	for i in range(1, _main._prize_count + 1):
		if zone.zone_name == "%sPrize %d" % [prefix, i]:
			var action := ActionTakePrize.new(pid, i - 1)
			_main._authority.request_action(action)
			return


func _try_pick_setup_instance(card: Card) -> void:
	if card.face_down or card.data == null:
		return
	if not (card.data is PokemonCardData) \
			or (card.data as PokemonCardData).stage != PokemonCardData.Stage.BASIC:
		return
	var inst := card.get_parent() as PokemonInstance
	if inst == null or inst.owner_id != _main.manager.setup_placing_player:
		return
	var pid: int = _main.manager.setup_placing_player
	for sid: String in BoardPosition.all_slot_ids(pid):
		if _main.manager.board_position.get_instance(sid) == inst:
			_setup_dragged_from_slot = sid
			break
	if _setup_dragged_from_slot == "":
		return
	if _hovered_node == inst:
		_release_hover()
	var world_pos := inst.global_position
	if inst.get_parent() != null:
		inst.get_parent().remove_child(inst)
	_main.board.add_child(inst)
	inst.global_position = Vector3(world_pos.x, Card.HOVER_LIFT * 2.0, world_pos.z)
	_setup_dragged_instance = inst


func _try_drop_setup_drag() -> void:
	var inst      := _setup_dragged_instance
	var from_slot := _setup_dragged_from_slot
	_setup_dragged_instance = null
	_setup_dragged_from_slot = ""
	var pid: int = _main.manager.setup_placing_player

	var zone: DropZone = (_main.board as Board).get_slot_zone_at(inst.global_position)
	var to_slot: String = (_main.board as Board).slot_id_for_zone(zone) if zone != null else ""

	if to_slot == from_slot:
		_main.manager.board_position.place(from_slot, inst)
		return

	if to_slot == "":
		_main.manager.board_position.clear(from_slot)
		var released: Array[CardData] = inst.release_cards()
		for c: CardData in released:
			_main.manager.game_position.put_in_hand(pid, c)
		inst.queue_free()
		return

	if _main.manager.board_position.player_of(to_slot) != pid:
		_main.manager.board_position.place(from_slot, inst)
		return

	if _main.manager.board_position.get_instance(to_slot) == null:
		_main.manager.board_position.move(from_slot, to_slot)
	else:
		_main.manager.board_position.swap(from_slot, to_slot)


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


func _update_hover(screen_pos: Vector2) -> void:
	var target := _hover_target_for(_raycast_card(screen_pos))
	if target == _hovered_node:
		return
	_release_hover()
	_hovered_node = target
	if _hovered_node != null:
		_apply_hover(_hovered_node)


func _handle_right_click(screen_pos: Vector2) -> void:
	var card := _raycast_card(screen_pos)
	if card == null or card.face_down or card.data == null:
		return
	if _main.card_zoom_popup == null:
		return
	var instance: PokemonInstance = null
	if card.get_parent() is PokemonInstance:
		instance = card.get_parent() as PokemonInstance
	_main.card_zoom_popup.show_card(card, instance)


func _try_drop_card() -> void:
	if dragged_card == null:
		return
	var card := dragged_card
	dragged_card = null

	if card.data == null:
		card.return_to_home()
		card.end_drag()
		return

	var zone: DropZone = (_main.board as Board).get_slot_zone_at(card.global_position)
	var slot_id: String = (_main.board as Board).slot_id_for_zone(zone) if zone != null else ""

	var action := _build_action_for_drop(card.data, slot_id)
	if action == null:
		card.return_to_home()
		card.end_drag()
		return

	var result: ActionResult = _main._authority.request_action(action)
	if not result.ok:
		card.return_to_home()
	card.end_drag()


func _build_action_for_drop(data: CardData, slot_id: String) -> GameAction:
	var PLAYER_ID: int = _main._authority.current_player_id()

	if _main.manager.setup_placing_player >= 0:
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


func _raycast_card(screen_pos: Vector2) -> Card:
	var from: Vector3 = (_main.camera as Camera3D).project_ray_origin(screen_pos)
	var dir: Vector3  = (_main.camera as Camera3D).project_ray_normal(screen_pos)
	var params := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var hit: Dictionary = _main.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return null
	var body := hit.collider as Node
	if body == null:
		return null
	var parent := body.get_parent()
	return parent as Card


func _screen_to_table(screen_pos: Vector2) -> Vector3:
	var from: Vector3 = (_main.camera as Camera3D).project_ray_origin(screen_pos)
	var dir: Vector3  = (_main.camera as Camera3D).project_ray_normal(screen_pos)
	var hit: Variant = DRAG_PLANE.intersects_ray(from, dir)
	if hit == null:
		return from
	return hit as Vector3
