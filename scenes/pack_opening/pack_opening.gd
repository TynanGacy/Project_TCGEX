extends Control
## Pack-opening reveal screen. Reads pending pack id from GameStateManager,
## consumes one pack from PlayerProfile, rolls cards via PackOpener, and
## displays them face-down. Click a card to flip it; rarities highlight on
## reveal. Cards are added to the collection on roll (not on flip) so the
## player still owns them if they exit early.

const REVEAL_TWEEN_TIME: float = 0.25
const BATCH_OPEN_SIZE: int = 6

## Tile dimensions used both for the layout reserve and the rounded-corner
## shader's `card_size` uniform — keeping them in lockstep is what makes
## the rounding consistent for every set, not just DR.
const TILE_W: float = 170.0
const TILE_H: float = 246.0
const TILE_CORNER_RADIUS: float = 10.0
## Extra empty space around the grid so the rarity halo glow on the top
## and bottom rows isn't clipped by the scroll viewport's edges or the
## Done button below.
const TOP_GUTTER_PX: int = 28
const BOTTOM_GUTTER_PX: int = 28
const ROUNDED_SHADER_PATH: String = "res://scenes/card/card_zoom_rounded_2d.gdshader"

## Halo border + glow color for cards added to the player's collection for
## the first time. Per design: white/blue/green/yellow/red/violet up the tier.
const HALO_COLORS: Dictionary = {
	"Common":       Color(1.0, 1.0, 1.0),
	"Uncommon":     Color(0.35, 0.55, 1.0),
	"Rare":         Color(0.3, 0.95, 0.4),
	"Rare Holo":    Color(1.0, 0.9, 0.2),
	"Rare Holo EX": Color(1.0, 0.3, 0.3),
	"Rare Secret":  Color(0.75, 0.35, 1.0),
}

var _pack: PackDefinition = null
var _pack_count: int = 1
var _rolled_ids: Array[String] = []
var _flipped: Array[bool] = []
var _tiles: Array[Control] = []
## Snapshot of which unique card_ids the player already owned *before* this
## opening committed its rolls. Used to decide whether a flipped card earns
## the first-time-pull halo.
var _was_owned: Dictionary = {}
var _grid: HFlowContainer
var _title: Label
var _flip_all_btn: Button
var _open_more_btn: Button
var _open_more_batch_btn: Button
var _next_btn: Button


func _ready() -> void:
	var req := GameStateManager.consume_pending_pack_request()
	var pack_id: String = req.get("pack_id", "")
	_pack_count = max(1, int(req.get("count", 1)))
	_pack = PackCatalog.get_by_id(pack_id) if pack_id != "" else null
	if _pack == null:
		push_warning("PackOpening: no pending pack id")
		GameStateManager.return_to_menu()
		return

	## Cap the batch at whatever the player actually owns — guards against the
	## shop UI being stale or the request being raced past a sale.
	var available: int = PlayerProfile.pack_count(_pack.pack_id)
	_pack_count = min(_pack_count, available)
	if _pack_count <= 0:
		push_warning("PackOpening: player owns no %s" % _pack.pack_id)
		GameStateManager.open_shop()
		return

	## Roll first, snapshot owned counts before mutating the collection so the
	## halo logic can tell "was new pre-pack" apart from "duplicate within
	## this pack". Then commit the cards.
	var pending_ids: Array[String] = []
	for _i in _pack_count:
		PlayerProfile.consume_pack(_pack.pack_id)
		for cid in PackOpener.roll(_pack):
			pending_ids.append(cid)
	for cid in pending_ids:
		if not _was_owned.has(cid):
			_was_owned[cid] = PlayerProfile.owned_count(cid) > 0
	for cid in pending_ids:
		PlayerProfile.add_card(cid, 1)
		_rolled_ids.append(cid)
	_flipped.resize(_rolled_ids.size())

	_build_layout()


func _build_layout() -> void:
	var v := VBoxContainer.new()
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.offset_left = 16
	v.offset_top = 16
	v.offset_right = -16
	v.offset_bottom = -16
	v.add_theme_constant_override("separation", 16)
	add_child(v)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "← Shop"
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(GameStateManager.open_shop)
	header.add_child(back)
	_title = Label.new()
	_title.text = "%s ×%d" % [_pack.display_name, _pack_count] if _pack_count > 1 else _pack.display_name
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	header.add_child(_title)
	_flip_all_btn = Button.new()
	_flip_all_btn.text = "Reveal All"
	_flip_all_btn.custom_minimum_size = Vector2(120, 40)
	_flip_all_btn.pressed.connect(_reveal_all)
	header.add_child(_flip_all_btn)

	var remaining: int = PlayerProfile.pack_count(_pack.pack_id)
	if remaining >= 1:
		_open_more_btn = Button.new()
		_open_more_btn.text = "Open 1 More"
		_open_more_btn.custom_minimum_size = Vector2(140, 40)
		_open_more_btn.tooltip_text = "Reveal all cards before opening more."
		_open_more_btn.pressed.connect(func(): _open_more(1))
		header.add_child(_open_more_btn)
	if remaining >= BATCH_OPEN_SIZE:
		_open_more_batch_btn = Button.new()
		_open_more_batch_btn.text = "Open ×%d More" % BATCH_OPEN_SIZE
		_open_more_batch_btn.custom_minimum_size = Vector2(160, 40)
		_open_more_batch_btn.tooltip_text = "Reveal all cards before opening more."
		_open_more_batch_btn.pressed.connect(func(): _open_more(BATCH_OPEN_SIZE))
		header.add_child(_open_more_batch_btn)

	v.add_child(header)
	## Locked until every card in the current batch has been flipped — keeps
	## the player from skipping past unrevealed pulls.
	_update_open_more_enabled()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)

	## Wrap the grid in a MarginContainer so the top row has breathing room
	## for the rarity-halo glow. Without this, halos on the first row were
	## clipped by the scroll viewport's top edge.
	var grid_margins := MarginContainer.new()
	grid_margins.add_theme_constant_override("margin_top", TOP_GUTTER_PX)
	grid_margins.add_theme_constant_override("margin_bottom", BOTTOM_GUTTER_PX)
	grid_margins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_margins)

	_grid = HFlowContainer.new()
	## Doubled from 16 → 32 per design feedback: cards read as individual
	## pulls instead of a tightly packed sheet.
	_grid.add_theme_constant_override("h_separation", 32)
	_grid.add_theme_constant_override("v_separation", 32)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_margins.add_child(_grid)

	for i in _rolled_ids.size():
		var tile := _make_tile(i)
		_tiles.append(tile)
		_grid.add_child(tile)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_next_btn = Button.new()
	_next_btn.text = "Done"
	_next_btn.custom_minimum_size = Vector2(160, 44)
	_next_btn.pressed.connect(GameStateManager.open_shop)
	footer.add_child(_next_btn)
	v.add_child(footer)


func _make_tile(index: int) -> Control:
	## Tile structure (back-to-front draw order, which is child order):
	##   tile (Control, layout reserve)
	##   ├── halo (Panel)         — same rect as art; bg is the halo color
	##   │                          covered by the card on top, only the
	##   │                          StyleBoxFlat shadow leaks out as a glow.
	##   ├── art (TextureRect)    — rounded-corner shader clips to card shape;
	##   │                          this is what makes RS / SS / DR render
	##   │                          identically regardless of source PNG.
	##   │   └── badge_pill       — owned-count chip on the middle-right.
	##   No PanelContainer wrapper, no name label per design feedback.
	var card_id := _rolled_ids[index]
	var card: CardData = CardDatabase.get_card(card_id)
	var tile := Control.new()
	tile.custom_minimum_size = Vector2(TILE_W, TILE_H)
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	## Scale tween should pulse from the tile center, not the top-left corner.
	tile.pivot_offset = Vector2(TILE_W * 0.5, TILE_H * 0.5)

	var halo := Panel.new()
	halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## No-op stylebox by default — overridden by _apply_halo on first pulls.
	halo.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	tile.add_child(halo)

	var art := TextureRect.new()
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.texture = SleevesManager.get_sleeve(0) if SleevesManager else null
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rounded_shader(art)
	tile.add_child(art)

	## Count badge — owned-after-this-pack copies, rendered as a small dark
	## pill on the middle-right of the art. Matches the CardTile CORNER style
	## so the badge looks identical between collection / deck builder / pack
	## opening. Hidden until the tile is flipped.
	var badge_pill := PanelContainer.new()
	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = Color(0, 0, 0, 0.78)
	pill_style.set_corner_radius_all(4)
	pill_style.content_margin_left = 4
	pill_style.content_margin_right = 4
	pill_style.content_margin_top = 1
	pill_style.content_margin_bottom = 1
	badge_pill.add_theme_stylebox_override("panel", pill_style)
	badge_pill.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	badge_pill.offset_left = -64
	badge_pill.offset_top = -15
	badge_pill.offset_right = -6
	badge_pill.offset_bottom = 15
	badge_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_pill.visible = false
	art.add_child(badge_pill)

	var count_badge := Label.new()
	count_badge.text = ""
	count_badge.add_theme_color_override("font_color", Color(1, 1, 1))
	count_badge.add_theme_font_size_override("font_size", 16)
	count_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	count_badge.add_theme_constant_override("outline_size", 3)
	count_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_pill.add_child(count_badge)

	tile.set_meta("art", art)
	tile.set_meta("halo", halo)
	tile.set_meta("count_badge", count_badge)
	tile.set_meta("count_badge_pill", badge_pill)
	tile.set_meta("card", card)
	tile.set_meta("index", index)
	tile.gui_input.connect(func(ev: InputEvent): _on_tile_input(ev, tile))
	return tile


func _apply_rounded_shader(art: TextureRect) -> void:
	## Forces every card art — DR, RS, SS, and anything we add later — to
	## render with the same rounded card silhouette. Previously RS/SS images
	## rendered as squared rectangles because only DR happened to ship with
	## pre-clipped PNGs.
	var shader: Shader = load(ROUNDED_SHADER_PATH)
	if shader == null:
		push_warning("PackOpening: rounded shader missing at %s" % ROUNDED_SHADER_PATH)
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("card_size", Vector2(TILE_W, TILE_H))
	mat.set_shader_parameter("corner_radius", TILE_CORNER_RADIUS)
	art.material = mat


func _on_tile_input(ev: InputEvent, tile: Control) -> void:
	if not (ev is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = ev
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	_flip(int(tile.get_meta("index")))


func _flip(i: int) -> void:
	if i < 0 or i >= _tiles.size() or _flipped[i]:
		return
	_flipped[i] = true
	var tile: Control = _tiles[i]
	var card: CardData = tile.get_meta("card")
	var art: TextureRect = tile.get_meta("art")
	var count_badge: Label = tile.get_meta("count_badge")
	if card != null:
		art.texture = CardDatabase.load_art(card.card_id)
		var rarity := CardAppraiser.highest_rarity(card)
		count_badge.text = "×%d" % PlayerProfile.owned_count(card.card_id)
		var pill: PanelContainer = tile.get_meta("count_badge_pill")
		pill.visible = true
		if not bool(_was_owned.get(card.card_id, false)):
			_apply_halo(tile, rarity)
			## Mark as owned so duplicates later in the same opening don't
			## double-halo.
			_was_owned[card.card_id] = true
	var tween := create_tween()
	tween.tween_property(tile, "scale", Vector2(1.05, 1.05), REVEAL_TWEEN_TIME)
	tween.tween_property(tile, "scale", Vector2(1.0, 1.0), REVEAL_TWEEN_TIME)
	_update_open_more_enabled()


func _reveal_all() -> void:
	for i in _tiles.size():
		_flip(i)


func _update_open_more_enabled() -> void:
	var all_revealed: bool = true
	for f in _flipped:
		if not f:
			all_revealed = false
			break
	var tip := "" if all_revealed else "Reveal all cards before opening more."
	if _open_more_btn != null:
		_open_more_btn.disabled = not all_revealed
		_open_more_btn.tooltip_text = tip
	if _open_more_batch_btn != null:
		_open_more_batch_btn.disabled = not all_revealed
		_open_more_batch_btn.tooltip_text = tip


func _open_more(count: int) -> void:
	## Re-enter this scene with a fresh pending request. Using the same scene
	## tears down and rebuilds, which also resets the scroll position to the
	## top — the right behavior when a new batch lands.
	GameStateManager.open_pack(_pack.pack_id, count)


func _apply_halo(tile: Control, rarity: String) -> void:
	## Paints the halo layer behind the card. The Panel's bg_color matches the
	## halo tint but sits the same size as the art on top, so the card hides
	## it — only the StyleBoxFlat shadow leaks past the card edges, giving a
	## pure glow with no visible solid ring on top of the artwork.
	if not HALO_COLORS.has(rarity):
		return
	var color: Color = HALO_COLORS[rarity]
	var halo: Panel = tile.get_meta("halo")
	if halo == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = int(TILE_CORNER_RADIUS)
	sb.corner_radius_top_right = int(TILE_CORNER_RADIUS)
	sb.corner_radius_bottom_left = int(TILE_CORNER_RADIUS)
	sb.corner_radius_bottom_right = int(TILE_CORNER_RADIUS)
	sb.shadow_color = Color(color.r, color.g, color.b, 0.85)
	sb.shadow_size = 22
	halo.add_theme_stylebox_override("panel", sb)
