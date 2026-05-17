extends Control
## Collection browser. Shows every card in CardDatabase, with owned count
## badges sourced from PlayerProfile. An "Owned only" toggle hides unowned
## cards. Reuses the same CardGrid + CardFilterBar widgets the deck builder
## uses, with the count source rewired to the player's collection.

@onready var _grid: CardGrid = $Layout/CardGrid
@onready var _filter_bar: CardFilterBar = $Layout/FilterBar
@onready var _back_btn: Button = $Layout/Header/BackButton
@onready var _owned_toggle: CheckBox = $Layout/Header/OwnedToggle
@onready var _owned_label: Label = $Layout/Header/OwnedLabel
@onready var _reset_btn: Button = $Layout/Header/ResetButton
@onready var _reset_confirm: ConfirmationDialog = $ResetConfirm

var _all_cards: Array = []


func _ready() -> void:
	_all_cards = CardDatabase.all_cards()
	_refresh_counts()
	_apply_pool()
	_filter_bar.filters_changed.connect(_grid.set_filters)
	_grid.set_filters(_filter_bar.get_filters())
	_back_btn.pressed.connect(GameStateManager.return_to_menu)
	_owned_toggle.toggled.connect(_on_owned_toggled)
	_reset_btn.pressed.connect(func(): _reset_confirm.popup_centered())
	_reset_confirm.confirmed.connect(PlayerProfile.clear_collection)
	PlayerProfile.collection_changed.connect(_on_collection_changed)
	PlayerProfile.collection_reset.connect(_on_collection_reset)
	_refresh_owned_label()


func _on_collection_reset() -> void:
	## One full refresh covers the entire wipe — see PlayerProfile docs.
	_refresh_counts()
	_apply_pool()
	_refresh_owned_label()


func _apply_pool() -> void:
	if _owned_toggle != null and _owned_toggle.button_pressed:
		_grid.set_pool(_all_cards.filter(
			func(c: CardData) -> bool: return PlayerProfile.owned_count(c.card_id) > 0))
	else:
		_grid.set_pool(_all_cards)


func _refresh_counts() -> void:
	## In owned-only mode every tile maps to an owned card so the ×N badge is
	## meaningful. In full-pool mode the player explicitly asked to browse
	## the whole set; suppress the count overlay entirely so the artwork
	## reads cleanly and unowned cards don't look like they're missing a
	## badge alongside owned ones.
	if _owned_toggle != null and _owned_toggle.button_pressed:
		_grid.set_counts(PlayerProfile.collection.duplicate(), true)
	else:
		_grid.set_counts({}, false)


func _on_owned_toggled(_pressed: bool) -> void:
	_refresh_counts()
	_apply_pool()


func _on_collection_changed(_card_id: String, _new_count: int) -> void:
	_refresh_counts()
	_apply_pool()
	_refresh_owned_label()


func _refresh_owned_label() -> void:
	var unique_owned: int = PlayerProfile.collection.size()
	var total: int = _all_cards.size()
	_owned_label.text = "%d / %d unique" % [unique_owned, total]
