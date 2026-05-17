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
## Optional secondary counts rendered as a denominator alongside _counts.
## When non-empty each tile shows "primary/sub" (e.g. "2/4"); when empty the
## tile falls back to "×N".
var _subcounts: Dictionary = {}
## Optional per-card subtitle strings (e.g. sell prices like "12 ⛁"). When
## non-empty the tile shows the subtitle below the art in image mode or as
## an extra column in text mode. Empty subtitles render nothing.
var _subtitles: Dictionary = {}
## Caller-supplied comparators registered by sort_key. Used by the sell
## screen to plug a "price" sort that needs per-card prices the default
## CardTextFormat comparator can't see.
var _custom_comparators: Dictionary = {}  ## sort_key -> Callable
var _view_mode: int = CardTile.ViewMode.IMAGE
var _filters: Dictionary = {}
## Set true by apply_filters() to coalesce multiple set_* calls (counts,
## subcounts, subtitles, pool, filters) made in the same frame into a
## single deferred rebuild. Without this, adding one card to the sell cart
## was triggering 3+ full grid rebuilds back-to-back — visible as lag.
var _rebuild_queued: bool = false

## Incremental-build state. Each call to _rebuild_grid bumps the generation
## and starts an async coroutine. Build is two-phase to hide the cost:
## Phase 1 instantiates ALL filtered tiles at once with the card-back as a
## placeholder texture so the scroll fills immediately with no gaps; phase
## 2 then walks the tiles in batches and swaps in the real art. Any
## coroutine still mid-upgrade bails out the moment a new rebuild bumps
## the generation.
var _rebuild_generation: int = 0
## Tiles whose real art is upgraded per frame during phase 2. 40 gives the
## first viewport's worth a chance to fully populate within ~one second on
## a typical 700-card pool while keeping per-frame cost low.
const TILES_PER_FRAME: int = 40

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


func set_subcounts(subcounts: Dictionary) -> void:
	_subcounts = subcounts
	apply_filters()


func set_subtitles(subtitles: Dictionary) -> void:
	_subtitles = subtitles
	apply_filters()


func set_custom_comparator(sort_key: String, comparator: Callable) -> void:
	## Register a comparator that supersedes CardTextFormat.comparator_for()
	## when the active sort key matches. Lets external screens (e.g. the
	## sell screen's "price" sort) plug in state-dependent sort orders
	## without touching the global comparator registry.
	_custom_comparators[sort_key] = comparator
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
	## Queue exactly one deferred rebuild per frame regardless of how many
	## set_* calls fire. Synchronously triggering _rebuild_grid here used
	## to do 3+ full rebuilds for a single sell-cart click because we set
	## counts, subtitles, and pool all in sequence; with deferral the rebuild
	## sees the final state of all three after the call chain unwinds.
	if _grid == null:
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_apply_filters_now")


func _apply_filters_now() -> void:
	_rebuild_queued = false
	if _grid == null:
		return
	_filtered = _pool.filter(_passes_filters)
	var sort_key: String = str(_filters.get("sort", "default"))
	var comparator: Callable
	if _custom_comparators.has(sort_key):
		comparator = _custom_comparators[sort_key]
	else:
		comparator = CardTextFormat.comparator_for(sort_key)
	_filtered.sort_custom(comparator)
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
	## Diff-based rebuild. The previous version queue_freed every existing
	## tile and recreated the whole pool on each call, which made cart
	## clicks visibly stutter — every click reset and rebuilt ~300 tiles.
	## Now we:
	##   1. Index existing tiles by card_id.
	##   2. Walk _filtered in order; reuse existing tiles where possible
	##      (just updating count/subcount/subtitle in place), and create
	##      new ones only for cards that weren't already present.
	##   3. Free any old tiles that aren't in the new _filtered.
	##   4. Reorder kept tiles via move_child to match _filtered's order.
	##   5. Run the art-upgrade coroutine only on newly created tiles —
	##      kept tiles already have real art.
	##
	## Generation is bumped so any still-running upgrade coroutine for the
	## prior rebuild gives up before touching tiles we may have freed.
	_rebuild_generation += 1
	var my_gen: int = _rebuild_generation
	_match_label.text = "%d / %d cards" % [_filtered.size(), _pool.size()]

	var existing: Dictionary = {}  ## card_id -> CardTile
	for c in _grid.get_children():
		if c is CardTile and is_instance_valid(c):
			var ct := c as CardTile
			if ct.card != null:
				existing[ct.card.card_id] = ct

	var stretch_in_text := _view_mode == CardTile.ViewMode.TEXT
	var ordered: Array[CardTile] = []
	var created: Array[CardTile] = []
	for c in _filtered:
		var card: CardData = c as CardData
		if card == null:
			continue
		var count: int = int(_counts.get(card.card_id, 0))
		var subcount: int = int(_subcounts.get(card.card_id, 0))
		var subtitle: String = str(_subtitles.get(card.card_id, ""))
		var tile: CardTile
		if existing.has(card.card_id):
			tile = existing[card.card_id]
			existing.erase(card.card_id)
			## In-place update — no node churn.
			tile.set_count(count)
			tile.set_subcount(subcount)
			tile.set_subtitle(subtitle)
		else:
			tile = CardTile.create(card, count, show_counts, subcount,
				subtitle, true)
			tile.set_view_mode(_view_mode)
			if stretch_in_text:
				tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tile.clicked.connect(func(cd: CardData): card_activated.emit(cd))
			tile.right_clicked.connect(func(cd: CardData): card_zoom.emit(cd))
			tile.hovered.connect(func(cd: CardData): card_hovered.emit(cd))
			tile.unhovered.connect(func(cd: CardData): card_unhovered.emit(cd))
			_grid.add_child(tile)
			created.append(tile)
		ordered.append(tile)

	## Anything left in `existing` was in the prior view but isn't in the
	## new filtered set — drop those tiles.
	for card_id in existing.keys():
		var stale: CardTile = existing[card_id]
		if is_instance_valid(stale):
			stale.queue_free()

	## Reorder kept tiles to match _filtered. move_child is O(N) per call;
	## in the common case (sort unchanged) most calls are no-ops.
	for i in ordered.size():
		_grid.move_child(ordered[i], i)

	if not created.is_empty():
		_upgrade_art_incremental(my_gen, created)


func _upgrade_art_incremental(my_gen: int, tiles: Array[CardTile]) -> void:
	## Phase 2: swap each tile's card-back placeholder for the real art in
	## batches of TILES_PER_FRAME. Bails out if a new rebuild has started.
	## Text mode skips this entirely — text-view tiles never show art.
	##
	## Iterates direct CardTile references captured during phase 1, so a
	## stale child mix (queue_free'd siblings from a prior rebuild) can't
	## shift our cursor or corrupt indices. is_instance_valid still guards
	## against the tile itself being torn down between yields.
	if _view_mode == CardTile.ViewMode.TEXT:
		return
	var i: int = 0
	while i < tiles.size():
		if my_gen != _rebuild_generation:
			return
		var stop: int = min(i + TILES_PER_FRAME, tiles.size())
		for j in range(i, stop):
			var t: CardTile = tiles[j]
			if is_instance_valid(t):
				t.populate_art()
		i = stop
		if i < tiles.size():
			await get_tree().process_frame


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
