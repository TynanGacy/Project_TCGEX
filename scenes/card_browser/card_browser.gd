extends Control
## Standalone browser over every card in CardDatabase.

@onready var _grid: CardGrid = $Layout/CardGrid
@onready var _filter_bar: CardFilterBar = $Layout/FilterBar
@onready var _back_btn: Button = $Layout/Header/BackButton
@onready var _zoom: PanelContainer = $ZoomOverlay
@onready var _zoom_art: TextureRect = $ZoomOverlay/Margin/V/Art
@onready var _zoom_name: Label = $ZoomOverlay/Margin/V/CardName
@onready var _zoom_text: Label = $ZoomOverlay/Margin/V/Rules


func _ready() -> void:
	_grid.set_pool(CardDatabase.all_cards())
	_filter_bar.filters_changed.connect(_grid.set_filters)
	_grid.set_filters(_filter_bar.get_filters())
	_grid.card_zoom.connect(_show_zoom)
	_grid.card_activated.connect(_show_zoom)
	_back_btn.pressed.connect(GameStateManager.return_to_menu)
	_zoom.visible = false
	_zoom.gui_input.connect(_zoom_gui_input)


func _show_zoom(card: CardData) -> void:
	if card == null:
		return
	_zoom_art.texture = card.art if card.art != null else CardDatabase.load_art(card.card_id)
	_zoom_name.text = card.display_name
	_zoom_text.text = card.rules_text
	_zoom.visible = true


func _zoom_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_zoom.visible = false
