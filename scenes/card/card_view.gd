extends PanelContainer
class_name CardView

# ============================================================
#	CardView.gd
#	- UI representation of a card
#	- Emits clicked(self) on left-click
#	- Maintains a simple "selected" visual border
#	- Renders from a CardInstance (runtime state) when provided
#	- NOW: Dynamically scales to fit container size
# ============================================================


# ============================================================
#	Signals
# ============================================================
signal clicked(card_view: CardView)
signal hover_started(card_view: CardView)
signal hover_ended(card_view: CardView)


# ============================================================
#	Editor-exposed styling
# ============================================================

@export var selection_thickness: float = 4.0
@export var selection_color: Color = Color(1.0, 0.9, 0.2, 1.0)


# ============================================================
#	Node references (UI)
# ============================================================
@onready var name_label: Label = $Margin/VBox/SummaryBar/NameLabel
@onready var hp_label: Label = $Margin/VBox/SummaryBar/HPLabel
@onready var type_label: Label = $Margin/VBox/SummaryBar/TypeLabel
@onready var art_rect: TextureRect = $Margin/VBox/ArtRect


# ============================================================
#	State
# ============================================================
var card_instance: CardInstance = null
var _is_selected: bool = false


# ============================================================
#	Lifecycle
# ============================================================
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	mouse_entered.connect(func(): hover_started.emit(self))
	mouse_exited.connect(func(): hover_ended.emit(self))
	
	# Configure art scaling to be dynamic
	if art_rect:
		art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Make art responsive to container size
		art_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Listen for size changes to update art
	resized.connect(_on_card_resized)
	

func _on_card_resized() -> void:
	"""Called when the card is resized - ensures art scales properly"""
	if art_rect and size.y > 0:
		# Calculate available space for art (leaving room for labels)
		var margin_total = 16  # top + bottom margins
		var label_height = 24  # approximate height of name/hp labels
		var available_height = size.y - margin_total - label_height
		
		# Set minimum size to encourage proper scaling
		art_rect.custom_minimum_size = Vector2(size.x - margin_total, max(60, available_height))

	
func refresh_ui() -> void:
	if card_instance == null or card_instance.data == null:
		return

	var data := card_instance.data

	# -------- Base CardData --------
	if data is CardData:
		var base := data as CardData
		name_label.text = base.display_name
		if art_rect:
			art_rect.texture = base.art
	else:
		name_label.text = ""

	# -------- Pokémon-specific --------
	if data is PokemonCardData:
		var p := data as PokemonCardData
		
		# Display HP (current/max)
		if hp_label:
			hp_label.text = "%d/%d HP" % [card_instance.hp_remaining(), p.hp_max]
		
		# Display type
		if type_label:
			type_label.text = PokemonCardData.energy_type_to_string(p.pokemon_type)
	else:
		# Non-Pokemon cards
		if hp_label:
			hp_label.text = ""
		if type_label:
			type_label.text = ""
	
# ============================================================
#	Public API: selection
# ============================================================
func set_selected(v: bool) -> void:
	_is_selected = v
	queue_redraw()

func is_selected() -> bool:
	return _is_selected


# ============================================================
#	Public API: data binding
# ============================================================
func set_instance(inst: CardInstance) -> void:
	card_instance = inst
	refresh_ui()

func get_instance() -> CardInstance:
	return card_instance


# ============================================================
#	Public API: raw display (used by _render_from_instance)
# ============================================================
func set_display(cardname: String, cost: int, rules: String) -> void:
	name_label.text = cardname

# ============================================================
#	Input
# ============================================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(self)
		accept_event() # prevents ScrollContainer drag/scroll from stealing it

# ============================================================
#	Drawing: selection border
# ============================================================
func _draw() -> void:
	if not _is_selected:
		return

	var t: float = selection_thickness
	if t <= 0.0:
		return

	var r: Rect2 = Rect2(Vector2.ZERO, size)

	# Clamp thickness so it never exceeds half the smallest dimension
	var max_t: float = float(min(r.size.x, r.size.y)) * 0.5
	t = min(t, max_t)

	# Top
	draw_rect(Rect2(Vector2(r.position.x, r.position.y), Vector2(r.size.x, t)), selection_color)
	# Bottom
	draw_rect(Rect2(Vector2(r.position.x, r.position.y + r.size.y - t), Vector2(r.size.x, t)), selection_color)
	# Left
	draw_rect(Rect2(Vector2(r.position.x, r.position.y), Vector2(t, r.size.y)), selection_color)
	# Right
	draw_rect(Rect2(Vector2(r.position.x + r.size.x - t, r.position.y), Vector2(t, r.size.y)), selection_color)


# ============================================================
#	Rendering: CardInstance -> UI
# ============================================================
func _render_from_instance() -> void:
	if card_instance == null or card_instance.data == null:
		return

	var data := card_instance.data

	# Art
	art_rect.texture = data.art

	# Defaults
	var display_name := data.display_name
	var cost := 0
	var text := data.rules_text

	# Pokémon-specific display (placeholder, expand later)
	if data is PokemonCardData:
		var p := data as PokemonCardData
		display_name = "%s (%d/%d HP)" % [p.display_name, card_instance.hp_remaining(), p.hp_max]

		# Placeholder: show first attack if present
		if p.attacks.size() > 0:
			text = p.attacks[0].name + "\n" + p.attacks[0].text

		# Optional: append conditions for debugging
		if card_instance.special_conditions.size() > 0:
			text += "\n\nStatus: " + str(card_instance.special_conditions)

	set_display(display_name, cost, text)
