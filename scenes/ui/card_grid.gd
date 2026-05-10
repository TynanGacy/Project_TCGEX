class_name CardGrid
extends VBoxContainer
## Filterable grid of CardTile instances, used by the card browser and the
## deck builder. Filters are owned externally — see CardFilterBar — and fed
## in via set_filters(). Consumers feed the source pool via set_pool() and
## react via card_activated / card_zoom / hover signals.

signal card_activated(card: CardData)  ## left-click
signal card_zoom(card: CardData)        ## right-click
signal card_hovered(card: CardData)
signal card_unhovered(card: CardData)

## When true, image-mode tiles render with a count badge in the corner.
@export var show_counts: bool = false

var _pool: Array = []
var _filtered: Array = []
var _counts: Dictionary = {}  ## card_id -> int
var _view_mode: int = CardTile.ViewMode.IMAGE
var _filters: Dictionary = {}

## Container that holds the tiles. Swapped between HFlowContainer (image
## mode, wraps based on width) and VBoxContainer (text mode, single column).
var _grid: Container = null
var _scroll: ScrollContainer = null
var _match_label: Label = null
var _view_btn: Button = null


func _ready() -> void:
	if get_child_count() == 0:
		_build_layout()


func set_pool(cards: Array) -> void:
	_pool = cards.duplicate()
	apply_filters()


func set_counts(counts: Dictionary, show: bool = true) -> void:
	_counts = counts
	show_counts = show
	apply_filters()


func set_filters(f: Dictionary) -> void:
	_filters = f
	apply_filters()


func set_view_mode(mode: int) -> void:
	_view_mode = mode
	if _view_btn != null:
		_view_btn.text = "Text" if mode == CardTile.ViewMode.IMAGE else "Image"
	if _grid != null:
		_replace_grid_for_mode()
		_rebuild_grid()


func get_view_mode() -> int:
	return _view_mode


func apply_filters() -> void:
	if _grid == null:
		return
	_filtered = _pool.filter(_passes_filters)
	var sort_key: String = str(_filters.get("sort", "default"))
	_filtered.sort_custom(CardTextFormat.comparator_for(sort_key))
	if bool(_filters.get("reverse", false)):
		_filtered.reverse()
	_rebuild_grid()


func _passes_filters(item: Variant) -> bool:
	var card: CardData = item as CardData
	if card == null:
		return false

	var sets: Dictionary = _filters.get("sets", {})
	if not sets.is_empty():
		var prefix := CardDatabase.set_of(card.card_id)
		if not sets.get(prefix, false):
			return false

	var types: Dictionary = _filters.get("types", {})
	if not types.is_empty():
		if not types.get(card.card_type, false):
			return false

	var energies: Dictionary = _filters.get("energies", {})
	if not energies.is_empty():
		## A Pokémon or energy card matches if any of its types (primary plus
		## extras) is selected. Multi/Rainbow Energy carries every type so it
		## passes regardless of which energies are checked. Trainers/cards
		## with no types are filtered out when energies is non-empty.
		var card_types := CardTextFormat.card_energy_types(card)
		if card_types.is_empty():
			return false
		var any := false
		for t in card_types:
			if energies.get(t, false):
				any = true
				break
		if not any:
			return false

	var rarities: Dictionary = _filters.get("rarities", {})
	if not rarities.is_empty():
		## Match if any of the card's rarities is selected. A promo+rare card
		## thus passes both the "Promo" and "Rare" filters.
		var any_rarity := false
		for r in card.rarities:
			if rarities.get(str(r), false):
				any_rarity = true
				break
		if not any_rarity:
			return false

	var needle := str(_filters.get("name", "")).strip_edges().to_lower()
	if needle != "" and not card.display_name.to_lower().contains(needle):
		return false

	return true


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var stretch_in_text := _view_mode == CardTile.ViewMode.TEXT
	for c in _filtered:
		var card: CardData = c as CardData
		var count: int = int(_counts.get(card.card_id, 0))
		var tile := CardTile.create(card, count, show_counts)
		tile.set_view_mode(_view_mode)
		if stretch_in_text:
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.clicked.connect(func(cd: CardData): card_activated.emit(cd))
		tile.right_clicked.connect(func(cd: CardData): card_zoom.emit(cd))
		tile.hovered.connect(func(cd: CardData): card_hovered.emit(cd))
		tile.unhovered.connect(func(cd: CardData): card_unhovered.emit(cd))
		_grid.add_child(tile)
	_match_label.text = "%d / %d cards" % [_filtered.size(), _pool.size()]


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	## CardGrid extends VBoxContainer so its parent HSplitContainer can size
	## us correctly via container layout. Children are added directly to self.
	add_theme_constant_override("separation", 6)
	clip_contents = true

	## Compact header: match count + per-pane view-mode toggle. Filters live
	## above the splitter (see CardFilterBar) so the deck pane can be widened
	## without compressing them.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_match_label = Label.new()
	_match_label.text = "0 / 0 cards"
	_match_label.add_theme_font_size_override("font_size", 13)
	_match_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_match_label)
	_view_btn = Button.new()
	_view_btn.text = "Text"  ## label shows mode-to-toggle-into
	_view_btn.custom_minimum_size = Vector2(72, 0)
	_view_btn.pressed.connect(_on_view_btn_pressed)
	header.add_child(_view_btn)
	add_child(header)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	## Reserve enough horizontal room that the surrounding HSplitContainer
	## can't drag this pane below 2 image-mode columns.
	custom_minimum_size.x = 2 * CardTile.TILE_W + 8 + 20

	_replace_grid_for_mode()


func _replace_grid_for_mode() -> void:
	if _grid != null:
		_grid.queue_free()
		_grid = null
	if _view_mode == CardTile.ViewMode.IMAGE:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		_grid = flow
	else:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 4)
		_grid = vb
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)


func _on_view_btn_pressed() -> void:
	var next := CardTile.ViewMode.TEXT if _view_mode == CardTile.ViewMode.IMAGE else CardTile.ViewMode.IMAGE
	set_view_mode(next)
