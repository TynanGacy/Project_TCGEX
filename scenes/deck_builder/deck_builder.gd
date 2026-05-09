extends Control
## In-game deck builder.
## Left: filterable card pool (CardGrid, 4-wide).
## Right: deck (DeckPane, 2-wide) above the preview window.
## Preview shows full-size art of whatever card the mouse is over; minimisable.

@onready var _grid: CardGrid = $Layout/Body/CardGrid
@onready var _filter_bar: CardFilterBar = $Layout/FilterBar
@onready var _pane: DeckPane = $Layout/Body/Side/DeckPane
@onready var _preview: PanelContainer = $Layout/Body/Side/Preview
@onready var _preview_art: TextureRect = $Layout/Body/Side/Preview/Margin/Aspect/Art
@onready var _preview_toggle: Button = $Layout/BottomBar/PreviewToggleButton

@onready var _total_label: Label = $Layout/Header/Status/HBox/TotalLabel
@onready var _basics_label: Label = $Layout/Header/Status/HBox/BasicsLabel
@onready var _errors_label: Label = $Layout/Header/Status/ErrorsLabel
@onready var _name_label: Label = $Layout/Header/Status/NameLabel

@onready var _back_btn: Button = $Layout/Header/Buttons/BackButton
@onready var _new_btn: Button = $Layout/Header/Buttons/NewButton
@onready var _load_btn: Button = $Layout/Header/Buttons/LoadButton
@onready var _save_btn: Button = $Layout/Header/Buttons/SaveButton
@onready var _save_as_btn: Button = $Layout/Header/Buttons/SaveAsButton

@onready var _save_dialog: AcceptDialog = $SaveDialog
@onready var _save_name_edit: LineEdit = $SaveDialog/V/NameEdit
@onready var _overwrite_dialog: ConfirmationDialog = $OverwriteDialog
@onready var _picker: AcceptDialog = $PickerDialog
@onready var _picker_list: ItemList = $PickerDialog/V/List

var _current_path: String = ""
var _current_is_preset: bool = false
var _picker_entries: Array = []
var _preview_visible: bool = true


func _ready() -> void:
	_grid.show_counts = true
	_grid.set_pool(CardDatabase.all_cards())
	_filter_bar.filters_changed.connect(_grid.set_filters)
	_grid.set_filters(_filter_bar.get_filters())
	_apply_preview_rounded_shader()
	_grid.card_activated.connect(_on_pool_card_clicked)
	_grid.card_zoom.connect(_on_pool_card_zoomed)
	_grid.card_hovered.connect(_on_card_hovered)
	_grid.card_unhovered.connect(_on_card_unhovered)

	_pane.deck_changed.connect(_on_deck_changed)
	_pane.card_hovered.connect(_on_card_hovered)
	_pane.card_unhovered.connect(_on_card_unhovered)

	_back_btn.pressed.connect(GameStateManager.return_to_menu)
	_new_btn.pressed.connect(_on_new_pressed)
	_load_btn.pressed.connect(_on_load_pressed)
	_save_btn.pressed.connect(_on_save_pressed)
	_save_as_btn.pressed.connect(_on_save_as_pressed)
	_save_dialog.confirmed.connect(_on_save_dialog_confirmed)
	_overwrite_dialog.confirmed.connect(_on_overwrite_confirmed)
	_picker.confirmed.connect(_on_picker_confirmed)
	_preview_toggle.pressed.connect(_on_preview_toggle)

	_refresh_status()


func _on_pool_card_clicked(card: CardData) -> void:
	_pane.add_card(card.card_id, 1)


func _on_pool_card_zoomed(card: CardData) -> void:
	if _pane.count_of(card.card_id) > 0:
		_pane.remove_card(card.card_id, 1)


func _on_card_hovered(card: CardData) -> void:
	if card == null:
		return
	_preview_art.texture = card.art if card.art != null else CardDatabase.load_art(card.card_id)


func _apply_preview_rounded_shader() -> void:
	## Source PNGs are inconsistent — some have transparent rounded corners,
	## some are square. Apply the same shader the in-match popup uses so the
	## preview always renders rounded regardless of the source image.
	var shader: Shader = load("res://scenes/card/card_zoom_rounded_2d.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	## card_size matches the preview rect's natural aspect; the shader uses
	## UVs scaled by this so the corner radius reads as a fraction of size.
	## Aspect is locked by the AspectRatioContainer wrapping this TextureRect,
	## so STRETCH_SCALE fills the rect cleanly without distortion. The shader
	## reads UV (0-1) so the actual pixel size doesn't matter — only the
	## width:height ratio passed in card_size matters for the corner curve.
	mat.set_shader_parameter("card_size", Vector2(63, 88))
	mat.set_shader_parameter("corner_radius", 3.0)
	_preview_art.material = mat
	_preview_art.stretch_mode = TextureRect.STRETCH_SCALE


func _on_card_unhovered(_card: CardData) -> void:
	pass  ## leave last-hovered card visible until a new one is hovered


func _on_deck_changed(_model: Dictionary) -> void:
	_grid.set_counts(_pane.get_model(), true)
	_refresh_status()


func _on_preview_toggle() -> void:
	_preview_visible = not _preview_visible
	_preview.visible = _preview_visible
	_preview_toggle.text = "Hide Preview ▼" if _preview_visible else "Show Preview ▲"


func _refresh_status() -> void:
	var model := _pane.get_model()
	var total := DeckValidator.total_count(model)
	var basics := DeckValidator.basic_pokemon_count(model)
	var errors := DeckValidator.validate(model)

	_total_label.text = "%d / 60" % total
	_total_label.add_theme_color_override("font_color",
		Color(1, 0.4, 0.4) if total != 60 else Color(0.7, 1, 0.7))

	_basics_label.text = "%d basic Pokémon" % basics
	_basics_label.add_theme_color_override("font_color",
		Color(1, 0.4, 0.4) if basics == 0 else Color(0.7, 1, 0.7))

	if errors.is_empty():
		_errors_label.text = "Deck valid."
		_errors_label.add_theme_color_override("font_color", Color(0.7, 1, 0.7))
	else:
		_errors_label.text = "  •  ".join(errors)
		_errors_label.add_theme_color_override("font_color", Color(1, 0.5, 0.5))

	if _current_path == "":
		_name_label.text = "(unsaved)"
	else:
		var fname := _current_path.get_file().trim_suffix(".json")
		_name_label.text = "%s%s" % [fname, " [preset, read-only]" if _current_is_preset else ""]

	_save_btn.disabled = errors.size() > 0 or _current_path == "" or _current_is_preset
	_save_as_btn.disabled = errors.size() > 0


# ---------------------------------------------------------------------------
# New / Load / Save
# ---------------------------------------------------------------------------

func _on_new_pressed() -> void:
	_pane.clear()
	_current_path = ""
	_current_is_preset = false
	_refresh_status()


func _on_load_pressed() -> void:
	_picker_entries.clear()
	_picker_list.clear()
	for entry in DeckLoader.get_valid_decks():
		_picker_entries.append({"path": entry.path, "label": entry.label, "preset": true})
		_picker_list.add_item("[preset] %s" % entry.label)
	for entry in DeckIO.list_user_decks():
		_picker_entries.append({"path": entry.path, "label": entry.label, "preset": false})
		_picker_list.add_item(entry.label)
	if _picker_entries.is_empty():
		_picker_list.add_item("(no decks found)")
	_picker.popup_centered()


func _on_picker_confirmed() -> void:
	var sel := _picker_list.get_selected_items()
	if sel.is_empty():
		return
	var idx: int = sel[0]
	if idx >= _picker_entries.size():
		return
	var entry: Dictionary = _picker_entries[idx]
	var model := DeckIO.load_model(entry.path)
	_pane.set_model(model)
	_current_path = entry.path
	_current_is_preset = bool(entry.preset)
	_refresh_status()


func _on_save_pressed() -> void:
	if _current_path == "" or _current_is_preset:
		_on_save_as_pressed()
		return
	_write_to(_current_path)


func _on_save_as_pressed() -> void:
	var default_name := ""
	if _current_path != "":
		default_name = _current_path.get_file().trim_suffix(".json").replace("_", " ")
	_save_name_edit.text = default_name
	_save_dialog.popup_centered()


func _on_save_dialog_confirmed() -> void:
	var slug := DeckIO.slugify(_save_name_edit.text)
	var path := DeckIO.user_path_for_slug(slug)
	if FileAccess.file_exists(path):
		_overwrite_dialog.dialog_text = "Overwrite existing deck '%s'?" % slug
		_overwrite_dialog.set_meta("pending_path", path)
		_overwrite_dialog.popup_centered()
		return
	_write_to(path)


func _on_overwrite_confirmed() -> void:
	if _overwrite_dialog.has_meta("pending_path"):
		_write_to(_overwrite_dialog.get_meta("pending_path"))


func _write_to(path: String) -> void:
	var errors := DeckValidator.validate(_pane.get_model())
	if not errors.is_empty():
		push_warning("DeckBuilder.save blocked by validator: %s" % str(errors))
		return
	var err := DeckIO.save_model(_pane.get_model(), path)
	if err != OK:
		push_error("DeckBuilder: save failed (%d)" % err)
		return
	_current_path = path
	_current_is_preset = false
	_refresh_status()
