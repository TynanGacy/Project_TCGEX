class_name CardZoomPopup
extends PanelContainer
## Zoomed card inspector shown on right-click.
## Displays the card art and, for in-play Pokemon, typed energy disc icons
## and any attached tool — mirroring the 3D board display using the same
## AttachmentDisplay constants so colours and ordering are consistent.
##
## Icon placement mirrors the board: disc centres sit on the bottom edge of
## the card art so each icon straddles the edge exactly as ENERGY_NORM_Y=1.0
## does in PokemonInstance.  The CardFrame Control is sized to encompass both
## the card art and the protruding bottom half of the attachment icons.

## Card art dimensions in popup pixels (portrait orientation).
const CARD_ART_W := 322.0
const CARD_ART_H := 449.0

## Side length (px) of each circular attachment icon — proportional to the
## board disc sizing (ENERGY_NORM_STEP_X × card_w × 0.80 ≈ 12 % of card width).
const ICON_SIZE   := 56
## Corner radius = half side length → perfect circle.
const ICON_RADIUS := 28

@onready var card_art:            TextureRect   = $MarginContainer/CardFrame/CardArt
@onready var _card_frame:         Control       = $MarginContainer/CardFrame
@onready var _attachment_section: VBoxContainer = $MarginContainer/CardFrame/AttachmentSection
@onready var _energy_rows:        VBoxContainer = $MarginContainer/CardFrame/AttachmentSection/EnergyRows
@onready var _tool_row:           HBoxContainer = $MarginContainer/CardFrame/AttachmentSection/ToolRow


func _ready() -> void:
	card_art.position = Vector2.ZERO
	card_art.size = Vector2(CARD_ART_W, CARD_ART_H)
	_apply_rounded_shader()
	_layout_card_frame()
	call_deferred("reset_size")


func _apply_rounded_shader() -> void:
	var shader: Shader = load("res://scenes/card/card_zoom_rounded_2d.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("card_size", Vector2(CARD_ART_W, CARD_ART_H))
	card_art.material = mat


## Shows the popup for [card].  Pass the owning [instance] (if any) to render
## attachment icons; pass null for hand / pile / non-Pokemon cards.
func show_card(card: Card, instance: PokemonInstance = null) -> void:
	card_art.texture = card.data.art if card.data != null else null
	_refresh_attachments(instance)
	visible = true
	call_deferred("_layout_card_frame")
	call_deferred("reset_size")


func hide_popup() -> void:
	visible = false


## Positions AttachmentSection so icon centres sit on the card art's bottom
## edge (matching ENERGY_NORM_Y = 1.0 on the board), then resizes CardFrame
## to encompass both the card and the protruding icon halves.
func _layout_card_frame() -> void:
	card_art.position = Vector2.ZERO
	card_art.size = Vector2(CARD_ART_W, CARD_ART_H)

	if not _attachment_section.visible:
		_card_frame.custom_minimum_size = Vector2(CARD_ART_W, CARD_ART_H)
		return

	## Icon centres at y = CARD_ART_H; section top = CARD_ART_H - ICON_SIZE/2.
	var attach_top := CARD_ART_H - ICON_SIZE * 0.5
	_attachment_section.position = Vector2(0.0, attach_top)
	_attachment_section.size.x   = CARD_ART_W

	var attach_h := _attachment_section.get_combined_minimum_size().y
	_card_frame.custom_minimum_size = Vector2(CARD_ART_W, attach_top + attach_h)


## Rebuilds the attachment icon rows from [instance] state.
## Pure read — no mutation.  Safe to call from the MatchAuthority signal path.
func _refresh_attachments(instance: PokemonInstance) -> void:
	for child in _energy_rows.get_children():
		child.queue_free()
	for child in _tool_row.get_children():
		child.queue_free()

	if instance == null:
		_attachment_section.visible = false
		return

	var sorted: Array[CardData] = AttachmentDisplay.sort_energy(instance.attached_energy)

	if not sorted.is_empty():
		var i := 0
		while i < sorted.size():
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 6)
			_energy_rows.add_child(row)
			for j in range(AttachmentDisplay.MAX_VISIBLE_ENERGY):
				if i + j >= sorted.size():
					break
				row.add_child(_make_energy_disc(sorted[i + j]))
			i += AttachmentDisplay.MAX_VISIBLE_ENERGY

	var has_tool := not instance.attached_tools.is_empty()
	if has_tool:
		_tool_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tool_row.add_child(_make_tool_disc(instance.attached_tools[0]))
		var name_label := Label.new()
		name_label.text = instance.attached_tools[0].display_name
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", Color.WHITE)
		_tool_row.add_child(name_label)
	_tool_row.visible = has_tool

	_attachment_section.visible = not sorted.is_empty() or has_tool


func _make_energy_disc(card_data: CardData) -> Panel:
	return _make_disc(
		AttachmentDisplay.energy_color(card_data),
		AttachmentDisplay.energy_label(card_data)
	)


func _make_tool_disc(card_data: CardData) -> Panel:
	return _make_disc(
		AttachmentDisplay.TOOL_ICON_COLOR,
		card_data.display_name.substr(0, 1)
	)


func _make_disc(bg_color: Color, letter: String) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)

	var style := StyleBoxFlat.new()
	style.corner_radius_top_left     = ICON_RADIUS
	style.corner_radius_top_right    = ICON_RADIUS
	style.corner_radius_bottom_left  = ICON_RADIUS
	style.corner_radius_bottom_right = ICON_RADIUS
	style.bg_color = bg_color
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = letter
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	panel.add_child(lbl)
	return panel
