class_name HandVisualManager
extends Node

## Manages hand card visuals for both players.

var _main: Node = null
var _hand_cards: Array = [{}, {}]


func init(main_node: Node) -> void:
	_main = main_node


func hand_node(pid: int) -> Hand:
	return _main.player_hand if pid == 0 else _main._opponent_hand


func clear() -> void:
	_main.player_hand.clear_cards()
	for pid in range(2):
		for card in (_hand_cards[pid] as Dictionary).values():
			if is_instance_valid(card):
				(card as Card).queue_free()
	_hand_cards = [{}, {}]


func rebuild(player_id: int) -> void:
	if hand_node(player_id) == null:
		return
	hand_node(player_id).clear_cards()
	for card in (_hand_cards[player_id] as Dictionary).values():
		if is_instance_valid(card):
			(card as Card).queue_free()
	(_hand_cards[player_id] as Dictionary).clear()

	var face_up: bool = (player_id == _main._authority.current_player_id())
	var hand: Array = _main.manager.game_position.hands[player_id]
	for data in hand:
		var card_node := _main.card_scene.instantiate() as Card
		if face_up:
			card_node.set_data(data)
			card_node.drag_started.connect(_main._on_card_drag_started)
			card_node.card_dropped.connect(_main._on_card_dropped)
		else:
			card_node.back_texture = _main.CARD_BACK
			card_node.face_down    = true
		hand_node(player_id).add_card(card_node)
		(_hand_cards[player_id] as Dictionary)[data] = card_node


## Adds cards newly in [player_id]'s hand that aren't yet tracked.
func sync_new_cards(player_id: int) -> void:
	if hand_node(player_id) == null:
		return
	var face_up: bool = (player_id == _main._authority.current_player_id())
	var dict: Dictionary = _hand_cards[player_id]
	for data: CardData in _main.manager.game_position.hands[player_id]:
		if not dict.has(data):
			var card_node := _main.card_scene.instantiate() as Card
			if face_up:
				card_node.set_data(data)
				card_node.drag_started.connect(_main._on_card_drag_started)
				card_node.card_dropped.connect(_main._on_card_dropped)
			else:
				card_node.back_texture = _main.CARD_BACK
				card_node.face_down    = true
			hand_node(player_id).add_card(card_node)
			dict[data] = card_node


func on_card_left_hand(player_id: int, card: CardData) -> void:
	if hand_node(player_id) == null:
		return
	var dict: Dictionary = _hand_cards[player_id]
	if not dict.has(card):
		return
	var card_node: Card = dict[card]
	dict.erase(card)
	hand_node(player_id).remove_card(card_node)
	card_node.queue_free()
