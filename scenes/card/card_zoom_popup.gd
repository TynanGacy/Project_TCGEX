class_name CardZoomPopup
extends PanelContainer
## Shows a zoomed view of a card on the left side of the screen when right-clicked.

@onready var card_art: TextureRect = $MarginContainer/VBoxContainer/CardArt
@onready var card_name_label: Label = $MarginContainer/VBoxContainer/CardName
@onready var rules_label: Label = $MarginContainer/VBoxContainer/RulesText


func show_card(card: Card) -> void:
	if card.data != null:
		card_art.texture = card.data.art
		card_name_label.text = card.data.display_name
		rules_label.text = card.data.rules_text
	else:
		card_art.texture = null
		card_name_label.text = card.card_name
		rules_label.text = ""
	visible = true


func hide_popup() -> void:
	visible = false
