class_name CardZoomPopup
extends PanelContainer
## Zoomed card inspector shown on right-click.
## Displays the card art and, for in-play Pokemon, typed energy disc icons
## and any attached tool — mirroring the 3D board display using the same
## AttachmentDisplay constants so colours and ordering are consistent.
##
## show_card() accepts an optional PokemonInstance; pass it whenever the
## raycasted Card is owned by one.  The MatchAuthority / LocalMatchAuthority
## layer emits pokemon_state_changed when attachments mutate, so callers can
## re-open the popup or react without tight coupling to PokemonInstance directly.

## Side length (px) of each circular attachment icon.
## Derived from the board formula: ENERGY_NORM_STEP_X × card_w × 0.80 ≈ 12 % of
## card width.  Applied to the popup's 322 px card art width: 322 × 0.12 ≈ 39 px;
## bumped to 56 px so the icons read clearly and still fit 5 per row.
const ICON_SIZE   := 56
## Corner radius that makes the square Panel appear circular (half of ICON_SIZE).
const ICON_RADIUS := 28

@onready var card_art:           TextureRect  = $MarginContainer/VBoxContainer/CardArt
@onready var _attachment_section: VBoxContainer = $MarginContainer/VBoxContainer/AttachmentSection
@onready var _energy_rows:        VBoxContainer = $MarginContainer/VBoxContainer/AttachmentSection/EnergyRows
@onready var _tool_row:           HBoxContainer = $MarginContainer/VBoxContainer/AttachmentSection/ToolRow


func _ready() -> void:
	call_deferred("reset_size")


## Shows the popup for [card].  Pass the owning [instance] (if any) to render
## attachment icons; pass null for hand / pile / non-Pokemon cards.
func show_card(card: Card, instance: PokemonInstance = null) -> void:
	card_art.texture = card.data.art if card.data != null else null
	_refresh_attachments(instance)
	visible = true
	call_deferred("reset_size")


func hide_popup() -> void:
	visible = false


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
