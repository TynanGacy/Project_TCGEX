class_name CardFilterBar
extends HFlowContainer
## Reusable card-filter strip used above the card browser and the deck
## builder. Owns the filter UI; emits a Dictionary describing the current
## selection. Consumers feed the dict to CardGrid.set_filters().
##
## Filter dictionary shape:
##   {
##     "sets":      Dictionary[String     -> true]   (set prefix selected)
##     "types":     Dictionary[CardType   -> true]
##     "energies":  Dictionary[EnergyType -> true]
##     "rarities":  Dictionary[String     -> true]   (rarity label selected)
##     "name":      String  (substring match, case-insensitive)
##     "sort":      String  (key passed to CardTextFormat.comparator_for)
##     "reverse":   bool    (true → flip the sorted result)
##   }

signal filters_changed(filters: Dictionary)

var _selected_sets: Dictionary = {}
var _selected_types: Dictionary = {}
var _selected_energies: Dictionary = {}
var _selected_rarities: Dictionary = {}

var _set_menu: MenuButton = null
var _type_menu: MenuButton = null
var _energy_menu: MenuButton = null
var _rarity_menu: MenuButton = null
var _sort_opt: OptionButton = null
var _dir_opt: OptionButton = null
var _name_edit: LineEdit = null


func _ready() -> void:
	add_theme_constant_override("h_separation", 12)
	add_theme_constant_override("v_separation", 4)
	if get_child_count() == 0:
		_build()


func get_filters() -> Dictionary:
	return {
		"sets":      _selected_sets.duplicate(),
		"types":     _selected_types.duplicate(),
		"energies":  _selected_energies.duplicate(),
		"rarities":  _selected_rarities.duplicate(),
		"name":      _name_edit.text if _name_edit != null else "",
		"sort":      _sort_value(),
		"reverse":   _direction_value(),
	}


func _direction_value() -> bool:
	if _dir_opt == null:
		return false
	var idx := _dir_opt.selected
	if idx < 0:
		return false
	return bool(_dir_opt.get_item_metadata(idx))


func _sort_value() -> String:
	if _sort_opt == null:
		return "default"
	var idx := _sort_opt.selected
	if idx < 0:
		return "default"
	return str(_sort_opt.get_item_metadata(idx))


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build() -> void:
	_set_menu    = _add_multi_menu("Set",    "All sets",     _selected_sets,     _set_options())
	_type_menu   = _add_multi_menu("Type",   "Any type",     _selected_types,    _type_options())
	_energy_menu = _add_multi_menu("Energy", "Any energy",   _selected_energies, _energy_options())
	_rarity_menu = _add_multi_menu("Rarity", "Any rarity",   _selected_rarities, _rarity_options())
	_sort_opt    = _add_sort_option("Sort", _sort_options())
	_dir_opt     = _add_sort_option("Order", _direction_options())

	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 4)
	var name_lbl := Label.new()
	name_lbl.text = "Name:"
	name_box.add_child(name_lbl)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name…"
	_name_edit.custom_minimum_size = Vector2(160, 0)
	_name_edit.text_changed.connect(func(_t): _emit())
	name_box.add_child(_name_edit)
	add_child(name_box)


func _set_options() -> Array:
	var sets: Array = CardDatabase.cards_by_set().keys()
	sets.sort()
	var out: Array = []
	for s in sets:
		out.append([s, s])
	return out


func _type_options() -> Array:
	return [
		["Pokémon", CardData.CardType.POKEMON],
		["Trainer", CardData.CardType.TRAINER],
		["Energy",  CardData.CardType.ENERGY],
	]


func _energy_options() -> Array:
	## Dragon omitted: there is no Dragon energy in the DR/RS/SS era.
	return [
		["Fire",      PokemonCardData.EnergyType.FIRE],
		["Water",     PokemonCardData.EnergyType.WATER],
		["Grass",     PokemonCardData.EnergyType.GRASS],
		["Lightning", PokemonCardData.EnergyType.LIGHTNING],
		["Psychic",   PokemonCardData.EnergyType.PSYCHIC],
		["Fighting",  PokemonCardData.EnergyType.FIGHTING],
		["Darkness",  PokemonCardData.EnergyType.DARKNESS],
		["Metal",     PokemonCardData.EnergyType.METAL],
		["Colorless", PokemonCardData.EnergyType.COLORLESS],
	]


func _rarity_options() -> Array:
	## Sourced from the loaded card pool so the menu only ever lists rarities
	## that actually exist. CardDatabase.all_rarities() returns them in
	## Pokémon-TCG tier order.
	var out: Array = []
	for r in CardDatabase.all_rarities():
		out.append([r, r])
	return out


func _direction_options() -> Array:
	## (label, metadata) — false keeps the comparator's natural order, true
	## reverses the sorted result. Applies to whichever Sort key is active.
	return [
		["Default", false],
		["Reverse", true],
	]


func _sort_options() -> Array:
	## (label, metadata-key) pairs. The key is what CardGrid passes to
	## CardTextFormat.comparator_for(). Collection is still a placeholder
	## that falls back to the default order (see card_text_format.gd).
	return [
		["Set & number",  "default"],
		["Type",          "type"],
		["Energy",        "energy"],
		["Rarity",        "rarity"],
		["Collection",    "collection"],
	]


func add_sort_option(label: String, metadata_key: String) -> void:
	## Append a screen-specific sort option after the bar is built. The
	## sell screen uses this to inject "Price" without polluting the global
	## sort list — pricing is per-session state, not a property of the card.
	if _sort_opt == null:
		return
	_sort_opt.add_item(label)
	_sort_opt.set_item_metadata(_sort_opt.item_count - 1, metadata_key)


# ---------------------------------------------------------------------------
# Multi-select menu
# ---------------------------------------------------------------------------

## Adds a "Label: [MenuButton]" pair backed by a checkable popup. Returns the
## MenuButton so the caller can read state if needed. Clicking an item
## toggles its checked state and updates `sel_dict` + the button label.
func _add_multi_menu(label_text: String, all_label: String,
		sel_dict: Dictionary, options: Array) -> MenuButton:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = "%s:" % label_text
	box.add_child(lbl)

	var mb := MenuButton.new()
	mb.text = all_label
	mb.custom_minimum_size = Vector2(112, 0)
	mb.set_meta("all_label", all_label)

	var popup := mb.get_popup()
	popup.hide_on_checkable_item_selection = false
	var labels: Array = []
	var keys: Array = []
	for i in options.size():
		var entry: Array = options[i]
		labels.append(entry[0])
		keys.append(entry[1])
		popup.add_check_item(entry[0], i)
		popup.set_item_metadata(i, entry[1])
	mb.set_meta("labels", labels)
	mb.set_meta("keys", keys)

	popup.id_pressed.connect(func(id: int): _on_multi_id(id, mb, sel_dict))

	box.add_child(mb)
	add_child(box)
	return mb


func _on_multi_id(id: int, mb: MenuButton, sel_dict: Dictionary) -> void:
	var popup := mb.get_popup()
	var idx := popup.get_item_index(id)
	if idx < 0:
		return
	var key: Variant = popup.get_item_metadata(idx)
	var was: bool = popup.is_item_checked(idx)
	popup.set_item_checked(idx, not was)
	if not was:
		sel_dict[key] = true
	else:
		sel_dict.erase(key)
	mb.text = _multi_label(sel_dict, mb)
	_emit()


func _multi_label(sel_dict: Dictionary, mb: MenuButton) -> String:
	if sel_dict.is_empty():
		return mb.get_meta("all_label")
	if sel_dict.size() >= 2:
		return "Multiple"
	## Exactly one selected — show its label.
	var only_key: Variant = sel_dict.keys()[0]
	var labels: Array = mb.get_meta("labels")
	var keys:   Array = mb.get_meta("keys")
	var idx := keys.find(only_key)
	return str(labels[idx]) if idx >= 0 else str(only_key)


# ---------------------------------------------------------------------------
# Sort option
# ---------------------------------------------------------------------------

## Stores a String metadata key per item so the selected entry round-trips
## through to CardTextFormat.comparator_for().
func _add_sort_option(label_text: String, entries: Array) -> OptionButton:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lbl := Label.new()
	lbl.text = "%s:" % label_text
	box.add_child(lbl)
	var opt := OptionButton.new()
	for i in entries.size():
		var entry: Array = entries[i]
		opt.add_item(entry[0])
		opt.set_item_metadata(i, entry[1])
	opt.item_selected.connect(func(_i): _emit())
	box.add_child(opt)
	add_child(box)
	return opt


func _emit() -> void:
	filters_changed.emit(get_filters())
