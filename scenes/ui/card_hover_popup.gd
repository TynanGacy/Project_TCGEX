extends PanelContainer
class_name CardHoverPopup

@onready var title_label: Label = $Margin/VBox/TitleLabel
@onready var stats_label: Label = $Margin/VBox/StatsLabel
@onready var art_rect: TextureRect = $Margin/VBox/Art
@onready var rules_label: RichTextLabel = $Margin/VBox/RulesLabel

const OFFSET := Vector2(18, 18)
const PAD := 8.0


func _ready() -> void:
	# Do not block mouse / hover underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Make this ignore parent Control layout/transform so we can freely position it.
	top_level = true

	hide()
	set_process(true)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_position_to_mouse()


func show_for(card: CardView) -> void:
	if card == null or not is_instance_valid(card):
		hide()
		return

	var inst := card.get_instance()
	if inst == null or inst.data == null:
		hide()
		return

	var data := inst.data

	# ---- Base CardData fields ----
	if data is CardData:
		var base := data as CardData
		title_label.text = base.display_name
		rules_label.text = base.rules_text
		if art_rect != null:
			art_rect.texture = base.art
	else:
		title_label.text = ""
		rules_label.text = ""
		if art_rect != null:
			art_rect.texture = null

	# ---- Type-specific stats line ----
	if data is PokemonCardData:
		var p := data as PokemonCardData
		stats_label.text = "HP %d   %s" % [
			p.hp_max,
			PokemonCardData.energy_type_to_string(p.pokemon_type)
		]
	else:
		stats_label.text = ""

	show()

	# Place immediately (and again deferred in case size changes after layout).
	_update_position_to_mouse()
	call_deferred("_update_position_to_mouse")


func hide_popup() -> void:
	hide()


func _update_position_to_mouse() -> void:
	var vp := get_viewport()
	if vp == null:
		return

	var GAP := 16.0

	var vp_rect := vp.get_visible_rect()
	var vp_size := vp_rect.size
	var mouse := vp.get_mouse_position()

	# Ensure we have a usable size
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		s = get_minimum_size()
	if s.x <= 0.0 or s.y <= 0.0:
		return

	# Prefer top-left of the cursor (popup bottom-right near the mouse)
	var x := mouse.x - s.x - GAP
	var y := mouse.y - s.y - GAP

	# If not enough room on the left, put it to the right
	if x < PAD:
		x = mouse.x + GAP

	# If not enough room above, put it below
	if y < PAD:
		y = mouse.y + GAP

	# Final clamp in case we're near the far edges or popup is large
	var max_x := vp_size.x - s.x - PAD
	var max_y := vp_size.y - s.y - PAD

	global_position = Vector2(
		clamp(x, PAD, max_x),
		clamp(y, PAD, max_y)
	)
