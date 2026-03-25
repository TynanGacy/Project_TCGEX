extends Control
## Main scene — wires up the board, hand, and card interactions.

@onready var board: Board = $Board
@onready var player_hand: Hand = $PlayerHand

var card_scene: PackedScene = preload("res://scenes/card/card.tscn")


func _ready() -> void:
	player_hand.card_played.connect(_on_card_played)
	_deal_starting_hand(5)


func _deal_starting_hand(count: int) -> void:
	for i in count:
		var card: Card = card_scene.instantiate()
		card.card_name = "Card %d" % (i + 1)
		card.drag_started.connect(_on_card_drag_started)
		card.drag_ended.connect(_on_card_drag_ended)
		player_hand.add_card(card)


func _on_card_played(card: Card) -> void:
	var drop_pos := card.global_position + Card.BASE_SIZE / 2.0
	if board.try_place_card(card, drop_pos):
		player_hand.remove_card(card)
		board.add_child(card)
	else:
		card.return_to_home()


func _on_card_drag_started(card: Card) -> void:
	board.highlight_valid_zones(card)


func _on_card_drag_ended(_card: Card) -> void:
	board.clear_highlights()
