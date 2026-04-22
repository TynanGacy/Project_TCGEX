class_name CardZoomPopup
extends PanelContainer
## Shows a zoomed view of a card's art on the left side of the screen when right-clicked.
## Text overlays (HP, conditions, attachments) will be added here in future.

@onready var card_art: TextureRect = $MarginContainer/CardArt


func show_card(card: Card) -> void:
	card_art.texture = card.data.art if card.data != null else null
	visible = true


func hide_popup() -> void:
	visible = false
