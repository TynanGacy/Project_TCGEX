extends Control
## Pack shop. Lists every PackDefinition from data/packs/ with price + buy
## button. Also shows the player's unopened pack inventory with "Open" buttons,
## and a collapsible dev panel for granting coins during testing.
##
## NOTE on pricing: all packs are uniformly 100 coins for now. Real economy
## tuning (DR > RS > SS to reflect chase-card difficulty per the research in
## the plan file) is a TODO once income sources exist.

const COIN_GRANTS: Array[int] = [100, 1000, 10000]
const BATCH_OPEN_SIZE: int = 6
const BATCH_BUY_SIZE: int = 6

var _coin_label: Label
var _shop_list: VBoxContainer
var _inventory_list: VBoxContainer
var _packs: Array[PackDefinition] = []
## Per-pack widgets, kept around so the disabled state can be toggled in
## response to coin/inventory changes without rebuilding rows.
var _buy_buttons: Dictionary = {}         ## pack_id -> Button
var _buy_batch_buttons: Dictionary = {}   ## pack_id -> Button
var _open_buttons: Dictionary = {}        ## pack_id -> Button
var _open_batch_buttons: Dictionary = {}  ## pack_id -> Button
var _inventory_labels: Dictionary = {}    ## pack_id -> Label


func _ready() -> void:
	_packs = PackCatalog.load_all()
	_build_layout()
	_refresh_coins(PlayerProfile.coins)
	_refresh_inventory()
	PlayerProfile.coins_changed.connect(_refresh_coins)
	PlayerProfile.pack_inventory_changed.connect(func(_id, _n): _refresh_inventory())


func _build_layout() -> void:
	var layout := VBoxContainer.new()
	layout.anchor_right = 1.0
	layout.anchor_bottom = 1.0
	layout.offset_left = 16
	layout.offset_top = 16
	layout.offset_right = -16
	layout.offset_bottom = -16
	layout.add_theme_constant_override("separation", 12)
	add_child(layout)

	## Header — back, title, coin counter.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(GameStateManager.return_to_menu)
	header.add_child(back)
	var title := Label.new()
	title.text = "Pack Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var sell_btn := Button.new()
	sell_btn.text = "Sell Cards"
	sell_btn.custom_minimum_size = Vector2(140, 40)
	sell_btn.pressed.connect(GameStateManager.open_sell)
	header.add_child(sell_btn)
	_coin_label = Label.new()
	_coin_label.add_theme_font_size_override("font_size", 18)
	_coin_label.custom_minimum_size = Vector2(220, 40)
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_coin_label)
	layout.add_child(header)

	## Two columns: shop on the left, unopened-pack inventory on the right.
	var body := HSplitContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 600
	layout.add_child(body)

	body.add_child(_build_section("Buy Packs", _build_shop_list()))
	body.add_child(_build_section("Your Packs", _build_inventory_list()))

	## Dev panel.
	var dev := _build_dev_panel()
	layout.add_child(dev)


func _build_section(heading: String, body: Control) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 18)
	v.add_child(h)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(body)
	v.add_child(scroll)
	return v


func _build_shop_list() -> VBoxContainer:
	_shop_list = VBoxContainer.new()
	_shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_list.add_theme_constant_override("separation", 6)
	for pd in _packs:
		_shop_list.add_child(_make_shop_row(pd))
	return _shop_list


func _make_shop_row(pd: PackDefinition) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var name_lbl := Label.new()
	name_lbl.text = pd.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 16)
	h.add_child(name_lbl)
	var price_lbl := Label.new()
	price_lbl.text = "%d ⛁" % pd.price_coins
	price_lbl.custom_minimum_size = Vector2(80, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(price_lbl)
	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(80, 32)
	buy.pressed.connect(func(): _try_buy(pd, 1))
	h.add_child(buy)
	_buy_buttons[pd.pack_id] = buy

	var buy_batch := Button.new()
	buy_batch.text = "Buy ×%d" % BATCH_BUY_SIZE
	buy_batch.custom_minimum_size = Vector2(96, 32)
	buy_batch.tooltip_text = "Costs %d ⛁" % (pd.price_coins * BATCH_BUY_SIZE)
	buy_batch.pressed.connect(func(): _try_buy(pd, BATCH_BUY_SIZE))
	h.add_child(buy_batch)
	_buy_batch_buttons[pd.pack_id] = buy_batch
	return row


func _build_inventory_list() -> VBoxContainer:
	_inventory_list = VBoxContainer.new()
	_inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_list.add_theme_constant_override("separation", 6)
	## One row per pack, built once and kept around forever. Counts and
	## button enable-state are updated in _refresh_inventory; rows never
	## get added or removed, so the layout never shifts.
	for pd in _packs:
		_inventory_list.add_child(_make_inventory_row(pd))
	return _inventory_list


func _refresh_inventory() -> void:
	if _inventory_list == null:
		return
	for pd in _packs:
		var n: int = PlayerProfile.pack_count(pd.pack_id)
		var lbl: Label = _inventory_labels.get(pd.pack_id, null)
		if lbl != null:
			lbl.text = "%s ×%d" % [pd.display_name, n]
		var open: Button = _open_buttons.get(pd.pack_id, null)
		if open != null:
			open.disabled = n < 1
		var open_batch: Button = _open_batch_buttons.get(pd.pack_id, null)
		if open_batch != null:
			open_batch.disabled = n < BATCH_OPEN_SIZE


func _make_inventory_row(pd: PackDefinition) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	row.add_child(h)
	var name_lbl := Label.new()
	name_lbl.text = "%s ×0" % pd.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)
	_inventory_labels[pd.pack_id] = name_lbl
	var open := Button.new()
	open.text = "Open"
	open.custom_minimum_size = Vector2(80, 32)
	open.pressed.connect(func(): GameStateManager.open_pack(pd.pack_id, 1))
	h.add_child(open)
	_open_buttons[pd.pack_id] = open
	var open_batch := Button.new()
	open_batch.text = "Open ×%d" % BATCH_OPEN_SIZE
	open_batch.custom_minimum_size = Vector2(96, 32)
	open_batch.pressed.connect(
		func(): GameStateManager.open_pack(pd.pack_id, BATCH_OPEN_SIZE))
	h.add_child(open_batch)
	_open_batch_buttons[pd.pack_id] = open_batch
	return row


func _build_dev_panel() -> Control:
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var heading := Label.new()
	heading.text = "Dev: grant coins"
	heading.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	v.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for amt in COIN_GRANTS:
		var b := Button.new()
		b.text = "+%d" % amt
		b.custom_minimum_size = Vector2(100, 32)
		b.pressed.connect(func(): PlayerProfile.add_coins(amt))
		row.add_child(b)
	v.add_child(row)
	return panel


func _try_buy(pd: PackDefinition, count: int = 1) -> void:
	var total: int = pd.price_coins * max(1, count)
	if not PlayerProfile.spend_coins(total):
		push_warning("Shop: not enough coins for %d × %s" % [count, pd.pack_id])
		return
	PlayerProfile.grant_pack(pd.pack_id, count)


func _refresh_coins(value: int) -> void:
	if _coin_label != null:
		_coin_label.text = "Coins: %d" % value
	for pd in _packs:
		var single: Button = _buy_buttons.get(pd.pack_id, null)
		if single != null:
			single.disabled = value < pd.price_coins
		var batch: Button = _buy_batch_buttons.get(pd.pack_id, null)
		if batch != null:
			batch.disabled = value < pd.price_coins * BATCH_BUY_SIZE
