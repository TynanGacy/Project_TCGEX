class_name DeckPane
extends VBoxContainer
## Right pane of the deck builder: 2-column tile grid of the cards in the
## current deck. Click a tile to add a copy, right-click to remove. Holds
## the canonical deck model.

signal deck_changed(model: Dictionary)
signal card_hovered(card: CardData)
signal card_unhovered(card: CardData)

## Hard cap on copies of any non-basic-energy card. Mirrors DeckValidator's
## per-id limit so the user can't even build past it via the UI.
const COPY_LIMIT: int = 4

var _model: Dictionary = {}  ## card_id -> count
var _view_mode: int = CardTile.ViewMode.IMAGE

var _scroll: ScrollContainer = null
var _grid: Container = null
var _view_btn: Button = null


func _ready() -> void:
	if _grid == null:
		_build_layout()
	_rebuild()


func get_model() -> Dictionary:
	return _model.duplicate()


func set_model(model: Dictionary) -> void:
	_model = {}
	for k in model.keys():
		var n: int = int(model[k])
		if n > 0:
			_model[k] = n
	_rebuild()
	deck_changed.emit(_model.duplicate())


func clear() -> void:
	_model.clear()
	_rebuild()
	deck_changed.emit({})


func add_card(card_id: String, n: int = 1) -> void:
	var current: int = int(_model.get(card_id, 0))
	if n > 0:
		var card: CardData = CardDatabase.get_card(card_id)
		if not DeckValidator.is_basic_energy(card):
			var allowed: int = COPY_LIMIT - current
			if allowed <= 0:
				return
			n = min(n, allowed)
	_model[card_id] = current + n
	if _model[card_id] <= 0:
		_model.erase(card_id)
	_rebuild()
	deck_changed.emit(_model.duplicate())


func remove_card(card_id: String, n: int = 1) -> void:
	add_card(card_id, -n)


func count_of(card_id: String) -> int:
	return int(_model.get(card_id, 0))


func set_view_mode(mode: int) -> void:
	_view_mode = mode
	if _view_btn != null:
		_view_btn.text = "Text" if mode == CardTile.ViewMode.IMAGE else "Image"
	if _grid != null:
		_replace_grid_for_mode()
	_rebuild()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	## DeckPane extends VBoxContainer so its parent VSplitContainer (Side)
	## sizes us correctly via container layout. Children are added directly
	## to self.
	add_theme_constant_override("separation", 6)
	clip_contents = true

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.alignment = BoxContainer.ALIGNMENT_END
	_view_btn = Button.new()
	_view_btn.text = "Text"
	_view_btn.custom_minimum_size = Vector2(72, 0)
	_view_btn.pressed.connect(_on_view_btn_pressed)
	bar.add_child(_view_btn)
	add_child(bar)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	## Reserve enough room for at least 2 image-mode columns so the HSplit
	## divider can't shrink this pane below that.
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


func _rebuild() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()

	## Order: Pokémon → Trainer → Energy, then by card_id within each group.
	var ordered: Array = _model.keys()
	ordered.sort_custom(_compare_card_ids)
	for cid in ordered:
		var card: CardData = CardDatabase.get_card(cid)
		if card == null:
			continue
		var tile := CardTile.create(card, int(_model[cid]), true)
		tile.set_view_mode(_view_mode)
		## Same small middle-right pill the collection / pack-opening / pool
		## tiles use — kept consistent so a number in the same place always
		## means "copies recorded here", regardless of which view you're in.
		tile.set_count_style(CardTile.CountStyle.CORNER)
		if _view_mode == CardTile.ViewMode.TEXT:
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.clicked.connect(func(cd: CardData): add_card(cd.card_id, 1))
		tile.right_clicked.connect(func(cd: CardData): remove_card(cd.card_id, 1))
		tile.hovered.connect(func(cd: CardData): card_hovered.emit(cd))
		tile.unhovered.connect(func(cd: CardData): card_unhovered.emit(cd))
		_grid.add_child(tile)


func _compare_card_ids(a: String, b: String) -> bool:
	## Group by card type first (Pokémon → Trainer → Energy), then by the
	## shared set/number ordering (newest set first, ascending number).
	var ca: CardData = CardDatabase.get_card(a)
	var cb: CardData = CardDatabase.get_card(b)
	var ta: int = ca.card_type if ca != null else 99
	var tb: int = cb.card_type if cb != null else 99
	if ta != tb:
		return ta < tb
	return CardTextFormat.compare_card_ids(a, b)


func _on_view_btn_pressed() -> void:
	var next := CardTile.ViewMode.TEXT if _view_mode == CardTile.ViewMode.IMAGE else CardTile.ViewMode.IMAGE
	set_view_mode(next)
