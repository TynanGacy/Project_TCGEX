extends Control
## Sellback shop, modeled on the deck builder: collection pool on the left,
## "sell cart" on the right. Each owned card carries a single rolled
## appraisal that's shown as the card's subtitle (image mode) or as an
## extra column (text mode). Clicking a pool card pushes one copy into the
## cart; clicking a cart card pulls one back out. The cart shows the
## running total and a Sell button realizes the transaction.
##
## Rules per design feedback:
##  - No deck-builder limits (no 60-card cap, no 4-per-card cap).
##  - Basic energies are excluded entirely from the pool.
##  - Prices are stable across sales — only the explicit Re-roll button
##    re-randomizes (eventually this will hook into in-game time).
##  - Sorting by price lives in the shared CardFilterBar's Sort dropdown
##    as the "Price" option, injected on _ready via add_sort_option.
##  - A pool tile disappears once every copy is in the cart and reappears
##    if the player pulls a copy back out.

@onready var _back_btn: Button = $Layout/Header/BackButton
@onready var _reroll_btn: Button = $Layout/Header/RerollButton
@onready var _coin_label: Label = $Layout/Header/CoinLabel
@onready var _filter_bar: CardFilterBar = $Layout/FilterBar
@onready var _pool_grid: CardGrid = $Layout/Body/PoolGrid
@onready var _cart_grid: CardGrid = $Layout/Body/Cart/CartGrid
@onready var _total_label: Label = $Layout/Body/Cart/CartFooter/TotalLabel
@onready var _sell_btn: Button = $Layout/Body/Cart/CartFooter/SellButton
@onready var _last_copy_dialog: ConfirmationDialog = $LastCopyDialog

var _rng: RandomNumberGenerator
var _appraisals: Dictionary = {}  ## card_id -> int (price for one copy)
var _cart: Dictionary = {}        ## card_id -> int (copies queued to sell)


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_pool_grid.show_counts = true
	_cart_grid.show_counts = true

	_back_btn.pressed.connect(GameStateManager.open_shop)
	_reroll_btn.pressed.connect(_on_reroll_pressed)
	_sell_btn.pressed.connect(_on_sell_pressed)
	_last_copy_dialog.confirmed.connect(_commit_sale)

	_pool_grid.card_activated.connect(_on_pool_card_clicked)
	_cart_grid.card_activated.connect(_on_cart_card_clicked)

	## Inject Price as a sort option in the filter bar and wire a custom
	## comparator into both grids that reads from _appraisals. The lambda
	## captures _appraisals by reference so Re-roll's mutations are seen by
	## any subsequent sort.
	_filter_bar.add_sort_option("Price", "price")
	var price_cmp := func(a: CardData, b: CardData) -> bool:
		return int(_appraisals.get(a.card_id, 0)) > int(_appraisals.get(b.card_id, 0))
	_pool_grid.set_custom_comparator("price", price_cmp)
	_cart_grid.set_custom_comparator("price", price_cmp)

	_filter_bar.filters_changed.connect(_pool_grid.set_filters)
	_filter_bar.filters_changed.connect(_cart_grid.set_filters)
	_pool_grid.set_filters(_filter_bar.get_filters())
	_cart_grid.set_filters(_filter_bar.get_filters())

	PlayerProfile.coins_changed.connect(_refresh_coins)
	PlayerProfile.collection_changed.connect(_on_collection_changed)
	PlayerProfile.collection_reset.connect(_on_collection_reset)

	_reroll_appraisals()
	_refresh_pool()
	_refresh_cart()
	_refresh_coins(PlayerProfile.coins)


# ---------------------------------------------------------------------------
# Pricing
# ---------------------------------------------------------------------------

func _reroll_appraisals() -> void:
	## One price per card_id (not per copy) so "×N at P ⛁" reads cleanly.
	## Cards added since the last roll (e.g. via opening packs while the
	## sell scene is loaded) get a price too.
	_appraisals.clear()
	for cid in PlayerProfile.collection.keys():
		var card: CardData = CardDatabase.get_card(cid)
		if card == null:
			continue
		_appraisals[cid] = CardAppraiser.appraise(card, _rng)


func _ensure_appraisal(card_id: String) -> void:
	if _appraisals.has(card_id):
		return
	var card: CardData = CardDatabase.get_card(card_id)
	if card == null:
		return
	_appraisals[card_id] = CardAppraiser.appraise(card, _rng)


# ---------------------------------------------------------------------------
# Pool (left side: cards available to sell)
# ---------------------------------------------------------------------------

func _refresh_pool() -> void:
	## Cards whose every copy is already in the cart drop out of the pool
	## entirely — the tile vanishes so the grid reflows. Basic energies
	## never appear in the first place.
	var pool: Array = []
	var counts: Dictionary = {}
	var subtitles: Dictionary = {}
	for cid in PlayerProfile.collection.keys():
		var card: CardData = CardDatabase.get_card(cid)
		if card == null:
			continue
		if DeckValidator.is_basic_energy(card):
			continue
		var available: int = PlayerProfile.owned_count(cid) - int(_cart.get(cid, 0))
		if available <= 0:
			continue
		_ensure_appraisal(cid)
		pool.append(card)
		counts[cid] = available
		subtitles[cid] = "%d ⛁" % int(_appraisals[cid])

	_pool_grid.set_counts(counts, true)
	_pool_grid.set_subtitles(subtitles)
	_pool_grid.set_pool(pool)


# ---------------------------------------------------------------------------
# Cart (right side: queued sales)
# ---------------------------------------------------------------------------

func _refresh_cart() -> void:
	var cart_cards: Array = []
	var subtitles: Dictionary = {}
	for cid in _cart.keys():
		if int(_cart[cid]) <= 0:
			continue
		var card: CardData = CardDatabase.get_card(cid)
		if card == null:
			continue
		cart_cards.append(card)
		subtitles[cid] = "%d ⛁" % int(_appraisals.get(cid, 0))

	_cart_grid.set_counts(_cart.duplicate(), true)
	_cart_grid.set_subtitles(subtitles)
	_cart_grid.set_pool(cart_cards)
	_refresh_total()


func _refresh_total() -> void:
	var total: int = 0
	for cid in _cart.keys():
		total += int(_cart[cid]) * int(_appraisals.get(cid, 0))
	_total_label.text = "Total: %d ⛁" % total
	## Allow selling even when the total rolls to 0 (legitimate for unlucky
	## commons) — the only hard gate is "is the cart empty?".
	_sell_btn.disabled = _cart.is_empty()


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_pool_card_clicked(card: CardData) -> void:
	if card == null:
		return
	if DeckValidator.is_basic_energy(card):
		return
	var owned: int = PlayerProfile.owned_count(card.card_id)
	var in_cart: int = int(_cart.get(card.card_id, 0))
	if in_cart >= owned:
		return
	_cart[card.card_id] = in_cart + 1
	_refresh_pool()
	_refresh_cart()


func _on_cart_card_clicked(card: CardData) -> void:
	if card == null:
		return
	var in_cart: int = int(_cart.get(card.card_id, 0))
	if in_cart <= 1:
		_cart.erase(card.card_id)
	else:
		_cart[card.card_id] = in_cart - 1
	_refresh_pool()
	_refresh_cart()


func _on_sell_pressed() -> void:
	if _cart.is_empty():
		return
	## Check whether any card in the cart includes all of the player's
	## remaining copies. If so, surface a confirmation listing each card
	## by name so the player isn't surprised when their last Charizard
	## evaporates. _commit_sale runs on confirmation.
	var last_copy_names: Array[String] = []
	for cid in _cart.keys():
		var n: int = int(_cart[cid])
		if n <= 0:
			continue
		if n >= PlayerProfile.owned_count(cid):
			var card: CardData = CardDatabase.get_card(cid)
			if card != null:
				last_copy_names.append(card.display_name)
	if last_copy_names.is_empty():
		_commit_sale()
		return
	last_copy_names.sort()
	_last_copy_dialog.dialog_text = (
		"You're about to sell your last copy of:\n\n• %s\n\nProceed?"
		% "\n• ".join(last_copy_names))
	_last_copy_dialog.popup_centered()


func _commit_sale() -> void:
	if _cart.is_empty():
		return
	## Snapshot prices and counts before mutating the collection — committing
	## the sale below fires collection_changed, which would otherwise reorder
	## the cart mid-iteration.
	var total: int = 0
	var to_sell: Array = []
	for cid in _cart.keys():
		var n: int = int(_cart[cid])
		if n <= 0:
			continue
		var price: int = int(_appraisals.get(cid, 0))
		total += price * n
		to_sell.append({"id": cid, "n": n})
	_cart.clear()
	for entry in to_sell:
		PlayerProfile.add_card(str(entry["id"]), -int(entry["n"]))
	if total > 0:
		PlayerProfile.add_coins(total)
	_refresh_pool()
	_refresh_cart()


func _on_reroll_pressed() -> void:
	_reroll_appraisals()
	_refresh_pool()
	_refresh_cart()


# ---------------------------------------------------------------------------
# Profile signals
# ---------------------------------------------------------------------------

func _on_collection_changed(card_id: String, new_count: int) -> void:
	## Player sold cards or opened a pack while this scene is up. Keep the
	## cart consistent (can't carry more copies than the player owns) and
	## refresh both grids.
	if new_count <= 0:
		_cart.erase(card_id)
		_appraisals.erase(card_id)
	else:
		_ensure_appraisal(card_id)
		var in_cart: int = int(_cart.get(card_id, 0))
		if in_cart > new_count:
			_cart[card_id] = new_count
	_refresh_pool()
	_refresh_cart()


func _on_collection_reset() -> void:
	_cart.clear()
	_appraisals.clear()
	_refresh_pool()
	_refresh_cart()


func _refresh_coins(value: int) -> void:
	_coin_label.text = "Coins: %d" % value
