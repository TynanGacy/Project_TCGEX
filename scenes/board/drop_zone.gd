class_name DropZone
extends Control
## A zone on the board where cards can be dropped.

signal card_received(card: Card)

@export var zone_name: String = "Zone"
@export var zone_color: Color = Color(0.2, 0.3, 0.2, 0.4)
@export var highlight_color: Color = Color(0.3, 0.6, 0.3, 0.6)
@export var max_cards: int = 1

var held_cards: Array[Card] = []
var is_highlighted := false

@onready var bg: ColorRect = $Background
@onready var label: Label = $Label


func _ready() -> void:
	bg.color = zone_color
	label.text = zone_name


func can_accept_card(_card: Card) -> bool:
	return held_cards.size() < max_cards


func receive_card(card: Card) -> void:
	held_cards.append(card)
	card_received.emit(card)
	_layout_held_cards()


func remove_card(card: Card) -> void:
	held_cards.erase(card)
	_layout_held_cards()


func set_highlighted(value: bool) -> void:
	is_highlighted = value
	if bg:
		bg.color = highlight_color if value else zone_color


func get_drop_rect() -> Rect2:
	return get_global_rect()


func _layout_held_cards() -> void:
	for i in held_cards.size():
		var card := held_cards[i]
		var center := global_position + size / 2.0 - Card.BASE_SIZE / 2.0
		card.global_position = center
		card.rotation = 0.0
