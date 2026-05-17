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
## Optional subtitle column (used by the sell screen for per-card prices).
## Hidden via visibility when the subtitle string is empty.
const TXT_COL_SUBTITLE: int = 90

const _ROUNDED_SHADER_PATH := "res://scenes/card/card_zoom_rounded_2d.gdshader"
const _CARD_BACK_PATH      := "res://assets/images/card_back.png"

## Class-level cached resources. Building a fresh ShaderMaterial and loading
## the card-back texture per tile was a significant chunk of the per-tile
## cost when populating a collection grid with hundreds of cards — they're
## immutable and identical across every tile, so we cache them once.
static var _shared_rounded_material: ShaderMaterial = null
static var _shared_card_back: Texture2D = null


static func get_rounded_material() -> ShaderMaterial:
	if _shared_rounded_material != null:
		return _shared_rounded_material
	var shader: Shader = load(_ROUNDED_SHADER_PATH)
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("card_size", Vector2(TILE_W, ART_H))
	## Slightly wider radius than the popup uses (11.7 on 322px ≈ 3.6%); we
	## use ~4% of width so it reads as a clearly rounded card at tile scale.
	mat.set_shader_parameter("corner_radius", 8.0)
	_shared_rounded_material = mat
	return _shared_rounded_material


static func get_card_back() -> Texture2D:
	if _shared_card_back == null:
		_shared_card_back = load(_CARD_BACK_PATH)
	return _shared_card_back
## Match-overlay paths still pass selection state through the legacy meta keys
## set in _build_styles(). The pre-existing border styles are preserved when
## use_match_styles=true to keep the in-match selection visuals identical.
var use_match_styles: bool = false

var card: CardData = null
var _count: int = 0
## Optional secondary count rendered as a denominator. When > 0 the badge
## shows "primary/sub" (e.g. "2/4" = 2 in deck out of 4 owned). When 0 the
## badge falls back to the legacy "×N" format.
var _subcount: int = 0
var _show_count: bool = false
var _mode: ViewMode = ViewMode.IMAGE
var _count_style: int = CountStyle.CORNER
## Optional caption rendered below the art in image mode and as an extra
## column in text mode. Used by the sell screen to show per-card prices;
## leaving it empty (default) hides the widgets entirely so other consumers
## keep their existing layout.
var _subtitle: String = ""
## When true, the tile is created with the card-back placeholder and the
## real art is only loaded when populate_art() is called. Used by CardGrid
## to keep large pools snappy: every tile renders immediately as a card
## back, then real art gets swapped in across subsequent frames.
var _deferred_art: bool = false

var _image_root: Control = null
var _text_root: Control = null
var _art: TextureRect = null
var _count_badge_pill: PanelContainer = null
var _count_badge: Label = null
var _image_subtitle_pill: PanelContainer = null
var _image_subtitle: Label = null
var _text_subtitle: Label = null
var _text_count: Label = null
var _text_name: Label = null
var _text_type: Label = null
var _text_set: Label = null
var _text_rarity: Label = null

var _unselected_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null


static func create(card_in: CardData, count: int = 0, show_count: bool = false,
		subcount: int = 0, subtitle: String = "",
		deferred_art: bool = false) -> CardTile:
	var t := CardTile.new()
	t.setup(card_in, count, show_count, subcount, subtitle, deferred_art)
	return t


## Factory for the in-match overlay: keeps the bordered-panel look and the
## selected/unselected meta keys that dialog_manager's selection helper uses.
static func create_match(card_in: CardData) -> CardTile:
	var t := CardTile.new()
	t.use_match_styles = true
	t.setup(card_in, 0, false)
	return t


func setup(card_in: CardData, count_in: int = 0, show_count_in: bool = false,
		subcount_in: int = 0, subtitle_in: String = "",
		deferred_art_in: bool = false) -> void:
	card = card_in
	_count = count_in
	_subcount = subcount_in
	_show_count = show_count_in
	_subtitle = subtitle_in
	_deferred_art = deferred_art_in
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
	_refresh_count_badge()


func set_subtitle(s: String) -> void:
	_subtitle = s
	if _image_subtitle != null:
		_image_subtitle.text = s
	if _image_subtitle_pill != null:
		_image_subtitle_pill.visible = s != ""
	if _text_subtitle != null:
		_text_subtitle.text = s
		_text_subtitle.visible = s != ""


func populate_art() -> void:
	## Upgrade a tile from the card-back placeholder to its real art. Safe
	## to call on a non-deferred tile (no-op when the real texture is already
	## loaded). Keeps the shared rounded shader material in place.
	if card == null or _art == null:
		return
	_deferred_art = false
	var real: Texture2D = card.art if card.art != null else CardDatabase.load_art(card.card_id)
	if real != null:
		_art.texture = real


func set_subcount(n: int) -> void:
	_subcount = n
	_refresh_count_badge()


func _refresh_count_badge() -> void:
	var should_show: bool = _show_count and (_count > 0 or _subcount > 0)
	if _count_badge != null:
		_count_badge.text = _badge_text()
		_count_badge.visible = should_show
	## Hide the pill background too — otherwise unowned cards in full-pool
	## modes display an empty black pill on the art.
	if _count_badge_pill != null:
		_count_badge_pill.visible = should_show
	if _text_count != null:
		_text_count.text = "%d×" % _count


func _badge_text() -> String:
	## "in_deck/owned" when a denominator is meaningful; legacy "×N" otherwise.
	if _subcount > 0:
		return "%d/%d" % [_count, _subcount]
	return "×%d" % _count


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
	if _deferred_art:
		## Render the card-back immediately so the grid layout settles right
		## away; populate_art() will swap in real art on demand.
		_art.texture = get_card_back()
	elif card != null:
		_art.texture = card.art if card.art != null else CardDatabase.load_art(card.card_id)
	_apply_rounded_shader(_art)
	_image_root.add_child(_art)

	## Wrap the badge in a PanelContainer with a dark pill background so the
	## number is legible regardless of card art behind it. Previously the bare
	## white-with-outline label was easy to miss against light artwork.
	var badge_pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0, 0, 0, 0.72)
	pill_style.set_corner_radius_all(6)
	pill_style.content_margin_left = 6
	pill_style.content_margin_right = 6
	pill_style.content_margin_top = 1
	pill_style.content_margin_bottom = 1
	badge_pill.add_theme_stylebox_override("panel", pill_style)
	badge_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_root.add_child(badge_pill)
	_count_badge_pill = badge_pill

	_count_badge = Label.new()
	_count_badge.text = _badge_text()
	_count_badge.add_theme_color_override("font_color", Color(1, 1, 1))
	_count_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_pill.add_child(_count_badge)
	_apply_count_style()
	_refresh_count_badge()

	## Optional subtitle wrapped in a dark pill anchored to the bottom-center
	## of the art. Mirroring the count-badge approach (PanelContainer auto-
	## sized to the label) gives us a robust position regardless of the
	## host scene's layout quirks — the previous bare Label was unreliable.
	_image_subtitle_pill = PanelContainer.new()
	var sub_style := StyleBoxFlat.new()
	sub_style.bg_color = Color(0, 0, 0, 0.78)
	sub_style.set_corner_radius_all(6)
	sub_style.content_margin_left = 8
	sub_style.content_margin_right = 8
	sub_style.content_margin_top = 1
	sub_style.content_margin_bottom = 1
	_image_subtitle_pill.add_theme_stylebox_override("panel", sub_style)
	_image_subtitle_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Anchor BOTTOM_WIDE so the container spans the tile width and the
	## inner PanelContainer pill (sized to its label) sits centered. Using
	## a HBoxContainer wrapper keeps the pill exactly content-wide rather
	## than full-width with text floating inside it.
	var sub_row := HBoxContainer.new()
	sub_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sub_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sub_row.offset_top = -28.0
	sub_row.offset_bottom = -6.0
	sub_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_root.add_child(sub_row)
	sub_row.add_child(_image_subtitle_pill)

	_image_subtitle = Label.new()
	_image_subtitle.text = _subtitle
	_image_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_image_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_image_subtitle.add_theme_font_size_override("font_size", 14)
	_image_subtitle.add_theme_color_override("font_color", Color(1, 0.95, 0.55))
	_image_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_subtitle_pill.add_child(_image_subtitle)
	_image_subtitle_pill.visible = _subtitle != ""


func _apply_count_style() -> void:
	if _count_badge == null or _count_badge_pill == null:
		return
	_count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _count_style == CountStyle.CENTER_RIGHT_LARGE:
		_count_badge_pill.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_count_badge_pill.offset_left  = -110.0
		_count_badge_pill.offset_right = -8.0
		_count_badge_pill.offset_top    = -28.0
		_count_badge_pill.offset_bottom = 28.0
		_count_badge.add_theme_font_size_override("font_size", 32)
		_count_badge.add_theme_constant_override("outline_size", 6)
	else:
		## Small middle-right pill — same anchor as CENTER_RIGHT_LARGE (the
		## deck-pane style the player is used to) but smaller so ownership
		## info doesn't cover attacks/HP on the card. Sized at ~1.5× the
		## original small pill after player feedback.
		_count_badge_pill.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_count_badge_pill.offset_left  = -64.0
		_count_badge_pill.offset_right = -6.0
		_count_badge_pill.offset_top    = -15.0
		_count_badge_pill.offset_bottom = 15.0
		_count_badge.add_theme_font_size_override("font_size", 16)
		_count_badge.add_theme_constant_override("outline_size", 3)


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
	## Optional subtitle column (sell-screen price). Visibility flips off when
	## subtitle is empty so the column collapses to zero width and consumers
	## without a subtitle see no change.
	_text_subtitle = _make_text_cell(TXT_COL_SUBTITLE, HORIZONTAL_ALIGNMENT_RIGHT)
	_text_subtitle.text = _subtitle
	_text_subtitle.visible = _subtitle != ""
	_text_subtitle.add_theme_color_override("font_color", Color(1, 0.95, 0.55))
	_text_root.add_child(_text_count)
	_text_root.add_child(_text_name)
	_text_root.add_child(_text_type)
	_text_root.add_child(_text_set)
	_text_root.add_child(_text_rarity)
	_text_root.add_child(_text_subtitle)

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
		_text_subtitle.text = _subtitle


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
	target.material = get_rounded_material()


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
