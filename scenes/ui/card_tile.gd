class_name CardTile
extends Panel
## Reusable card cell used by the in-match deck-search overlay, the card
## browser, and the deck builder. Has two view modes:
##   - VIEW_IMAGE: art only (no border, no name) with a count badge in the
##     top-right corner. Compact vertical footprint.
##   - VIEW_TEXT:  one-line "N× Name | {Type} | SET NUM/TOTAL | RARITY".
## Children are built procedurally so the .tscn root only needs to hold the
## script.

signal clicked(card: CardData)
signal right_clicked(card: CardData)
signal hovered(card: CardData)
signal unhovered(card: CardData)

enum ViewMode { IMAGE, TEXT }
enum CountStyle { CORNER, CENTER_RIGHT_LARGE }

## Tile dimensions chosen to roughly match the real card aspect (63:88 ≈ 0.716)
## so the rounded-corner shader can fill the rect without aspect distortion.
const TILE_W: int = 200
const ART_H:  int = 280

## Text-mode column widths (px). All tiles use the same widths so columns
## align across rows like a table.
const TXT_COL_COUNT: int = 60
const TXT_COL_NAME:  int = 240
const TXT_COL_TYPE:  int = 50
const TXT_COL_SET:   int = 120
const TXT_COL_RARITY: int = 60

const _ROUNDED_SHADER_PATH := "res://scenes/card/card_zoom_rounded_2d.gdshader"
## Match-overlay paths still pass selection state through the legacy meta keys
## set in _build_styles(). The pre-existing border styles are preserved when
## use_match_styles=true to keep the in-match selection visuals identical.
var use_match_styles: bool = false

var card: CardData = null
var _count: int = 0
var _show_count: bool = false
var _mode: ViewMode = ViewMode.IMAGE
var _count_style: int = CountStyle.CORNER

var _image_root: Control = null
var _text_root: Control = null
var _art: TextureRect = null
var _count_badge: Label = null
var _text_count: Label = null
var _text_name: Label = null
var _text_type: Label = null
var _text_set: Label = null
var _text_rarity: Label = null

var _unselected_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null


static func create(card_in: CardData, count: int = 0, show_count: bool = false) -> CardTile:
	var t := CardTile.new()
	t.setup(card_in, count, show_count)
	return t


## Factory for the in-match overlay: keeps the bordered-panel look and the
## selected/unselected meta keys that dialog_manager's selection helper uses.
static func create_match(card_in: CardData) -> CardTile:
	var t := CardTile.new()
	t.use_match_styles = true
	t.setup(card_in, 0, false)
	return t


func setup(card_in: CardData, count_in: int = 0, show_count_in: bool = false) -> void:
	card = card_in
	_count = count_in
	_show_count = show_count_in
	mouse_filter = Control.MOUSE_FILTER_STOP
	if use_match_styles:
		_install_match_styles()
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_build_image_view()
	_build_text_view()
	_apply_mode()
	mouse_entered.connect(func(): hovered.emit(card))
	mouse_exited.connect(func(): unhovered.emit(card))
	gui_input.connect(_on_gui_input)


func set_view_mode(mode: ViewMode) -> void:
	_mode = mode
	_apply_mode()


func set_count_style(s: int) -> void:
	_count_style = s
	_apply_count_style()


func set_selected(is_selected: bool) -> void:
	if not use_match_styles:
		return
	add_theme_stylebox_override("panel", _selected_style if is_selected else _unselected_style)


func set_count(n: int) -> void:
	_count = n
	if _count_badge != null:
		_count_badge.text = "×%d" % n
		_count_badge.visible = _show_count and n > 0
	if _text_count != null:
		_text_count.text = "%d×" % n


func _install_match_styles() -> void:
	_unselected_style = StyleBoxFlat.new()
	_unselected_style.bg_color = Color(0.10, 0.10, 0.12, 1.0)
	_unselected_style.set_corner_radius_all(8)
	_unselected_style.set_border_width_all(2)
	_unselected_style.border_color = Color(0.25, 0.25, 0.30, 1.0)
	add_theme_stylebox_override("panel", _unselected_style)

	_selected_style = StyleBoxFlat.new()
	_selected_style.bg_color = Color(0.10, 0.16, 0.10, 1.0)
	_selected_style.set_corner_radius_all(8)
	_selected_style.set_border_width_all(4)
	_selected_style.border_color = Color(0.40, 0.95, 0.40, 1.0)

	## Legacy selection helper in dialog_manager.gd reads these metas and
	## calls add_theme_stylebox_override("panel", ...). With CardTile now
	## extending Panel, that path applies the stylebox correctly.
	set_meta("unselected_style", _unselected_style)
	set_meta("selected_style", _selected_style)


func _build_image_view() -> void:
	_image_root = Control.new()
	_image_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image_root)

	_art = TextureRect.new()
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	## STRETCH_SCALE so the texture fills the rect exactly and the rounded
	## shader can clip to the tile bounds without leaving square corners.
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card != null:
		_art.texture = card.art if card.art != null else CardDatabase.load_art(card.card_id)
	_apply_rounded_shader(_art)
	_image_root.add_child(_art)

	_count_badge = Label.new()
	_count_badge.text = "×%d" % _count
	_count_badge.visible = _show_count and _count > 0
	_count_badge.add_theme_color_override("font_color", Color(1, 1, 1))
	_count_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_root.add_child(_count_badge)
	_apply_count_style()


func _apply_count_style() -> void:
	if _count_badge == null:
		return
	_count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _count_style == CountStyle.CENTER_RIGHT_LARGE:
		_count_badge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_count_badge.offset_left  = -96.0
		_count_badge.offset_right = -8.0
		_count_badge.offset_top    = -28.0
		_count_badge.offset_bottom = 28.0
		_count_badge.add_theme_font_size_override("font_size", 32)
		_count_badge.add_theme_constant_override("outline_size", 6)
	else:
		_count_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_count_badge.offset_left  = -42.0
		_count_badge.offset_top   = 2.0
		_count_badge.offset_right = -4.0
		_count_badge.offset_bottom = 24.0
		_count_badge.add_theme_font_size_override("font_size", 16)
		_count_badge.add_theme_constant_override("outline_size", 4)


func _build_text_view() -> void:
	## Text mode lays each trait out in a fixed-width Label so columns align
	## across rows like a table.
	_text_root = HBoxContainer.new()
	_text_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_root.add_theme_constant_override("separation", 8)
	_text_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text_root)

	_text_count  = _make_text_cell(TXT_COL_COUNT, HORIZONTAL_ALIGNMENT_RIGHT)
	_text_name   = _make_text_cell(TXT_COL_NAME, HORIZONTAL_ALIGNMENT_LEFT)
	_text_type   = _make_text_cell(TXT_COL_TYPE, HORIZONTAL_ALIGNMENT_CENTER)
	_text_set    = _make_text_cell(TXT_COL_SET, HORIZONTAL_ALIGNMENT_LEFT)
	_text_rarity = _make_text_cell(TXT_COL_RARITY, HORIZONTAL_ALIGNMENT_CENTER)
	_text_root.add_child(_text_count)
	_text_root.add_child(_text_name)
	_text_root.add_child(_text_type)
	_text_root.add_child(_text_set)
	_text_root.add_child(_text_rarity)

	## Trailing spacer absorbs any extra horizontal space so the named columns
	## stay at their fixed widths and align across rows.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_root.add_child(spacer)

	if card != null:
		_text_count.text  = "%d×" % _count
		_text_name.text   = card.display_name
		_text_type.text   = CardTextFormat.type_token(card)
		_text_set.text    = CardTextFormat.set_locator(card)
		_text_rarity.text = CardTextFormat.rarity(card)


func _make_text_cell(width: int, align: int) -> Label:
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.size_flags_horizontal = 0  ## fixed width — do not expand
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.horizontal_alignment = align
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _apply_rounded_shader(target: CanvasItem) -> void:
	var shader: Shader = load(_ROUNDED_SHADER_PATH)
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("card_size", Vector2(TILE_W, ART_H))
	## Slightly wider radius than the popup uses (11.7 on 322px ≈ 3.6%); we
	## use ~4% of width so it reads as a clearly rounded card at tile scale.
	mat.set_shader_parameter("corner_radius", 8.0)
	target.material = mat


func _apply_mode() -> void:
	if _mode == ViewMode.IMAGE:
		custom_minimum_size = Vector2(TILE_W, ART_H)
		_image_root.visible = true
		_text_root.visible = false
	else:
		custom_minimum_size = Vector2(TILE_W, 28)
		_image_root.visible = false
		_text_root.visible = true
		if card != null and _text_count != null:
			_text_count.text  = "%d×" % _count
			_text_name.text   = card.display_name
			_text_type.text   = CardTextFormat.type_token(card)
			_text_set.text    = CardTextFormat.set_locator(card)
			_text_rarity.text = CardTextFormat.rarity(card)


func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(card)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(card)
