class_name PokemonInstance
extends Node3D
## An in-play Pokemon. Owns all dynamic per-Pokemon state AND the visual
## representation of that state.
##
## PokemonInstance is responsible for:
##   - Storing Max/Current HP, special conditions, attached energy/tools,
##     previous evolutions, and any dynamic modifiers.
##   - Storing every card currently contained in this instance (the base
##     Pokemon, any prior evolution stages, attached energy, attached tools).
##   - Rendering its own visual (3D card face + HP label + attachment icons
##     + status badges).
##   - Updating that visual whenever its state changes — it does NOT consult
##     game rules or ask permission; the Manager is responsible for legality.
##
## When the Pokemon is knocked out or otherwise removed, call release_cards()
## to collect every card contained and discard the instance.

enum SpecialCondition { ASLEEP, BURNED, CONFUSED, PARALYZED, POISONED }

## --- Static state -----------------------------------------------------------
var card: PokemonCardData = null     ## Top (current) card of the evolution stack.
var prior_stages: Array[PokemonCardData] = []  ## Underneath, oldest first.
var owner_id: int = 0

## --- Dynamic state ----------------------------------------------------------
var max_hp: int = 0
var current_hp: int = 0
var special_conditions: Array[SpecialCondition] = []
var attached_energy: Array[CardData] = []
var attached_tools: Array[CardData] = []

## Dynamic modifiers applied by board effects.  Keyed by modifier id (String),
## value is an arbitrary Dictionary the effect defines.  Cleared on release.
var modifiers: Dictionary = {}

## --- Visual -----------------------------------------------------------------
const _CARD_SCENE := preload("res://scenes/card/card.tscn")

## Width (world units) used by the card face in board mode.  Set by whoever
## places the instance (typically a DropZone via BoardPosition).
var display_width: float = 1.32

var _card_visual: Card = null
var _hp_label: Label3D = null
var _condition_label: Label3D = null
var _energy_label: Label3D = null


static func create(pokemon_card: PokemonCardData, owner: int = 0) -> PokemonInstance:
	var inst := PokemonInstance.new()
	inst.card = pokemon_card
	inst.owner_id = owner
	inst.max_hp = pokemon_card.hp_max if pokemon_card != null else 0
	inst.current_hp = inst.max_hp
	return inst


func _ready() -> void:
	_build_visual()
	refresh_visual()


func _build_visual() -> void:
	_card_visual = _CARD_SCENE.instantiate() as Card
	add_child(_card_visual)  ## add_child first so @onready nodes are live
	_card_visual.set_display_width(display_width)
	_card_visual.set_board_mode(true)
	_card_visual.set_data(card)

	_hp_label = Label3D.new()
	_hp_label.name = "HPLabel"
	_hp_label.pixel_size = 0.0012
	_hp_label.font_size = 40
	_hp_label.modulate = Color.WHITE
	_hp_label.outline_size = 8
	_hp_label.outline_modulate = Color.BLACK
	_hp_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_hp_label.position = Vector3(0.0, 0.03, -display_width * 0.35)
	add_child(_hp_label)

	_energy_label = Label3D.new()
	_energy_label.name = "EnergyLabel"
	_energy_label.pixel_size = 0.0009
	_energy_label.font_size = 28
	_energy_label.modulate = Color(0.8, 0.95, 1.0)
	_energy_label.outline_size = 6
	_energy_label.outline_modulate = Color.BLACK
	_energy_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_energy_label.position = Vector3(-display_width * 0.35, 0.03, display_width * 0.18)
	add_child(_energy_label)

	_condition_label = Label3D.new()
	_condition_label.name = "ConditionLabel"
	_condition_label.pixel_size = 0.0009
	_condition_label.font_size = 28
	_condition_label.modulate = Color(1.0, 0.7, 0.4)
	_condition_label.outline_size = 6
	_condition_label.outline_modulate = Color.BLACK
	_condition_label.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	_condition_label.position = Vector3(display_width * 0.30, 0.03, display_width * 0.18)
	add_child(_condition_label)


## Pushes current state to the visual.  Call after any mutation.
func refresh_visual() -> void:
	if _card_visual != null:
		_card_visual.set_data(card)
		_card_visual.face_down = false
	if _hp_label != null:
		_hp_label.text = "%d/%d HP" % [current_hp, max_hp]
	if _energy_label != null:
		_energy_label.text = "" if attached_energy.is_empty() else "E×%d" % attached_energy.size()
	if _condition_label != null:
		_condition_label.text = _conditions_text()


func _conditions_text() -> String:
	if special_conditions.is_empty():
		return ""
	var parts: Array[String] = []
	for c in special_conditions:
		parts.append(_cond_abbrev(c))
	return " ".join(parts)


static func _cond_abbrev(c: int) -> String:
	match c:
		SpecialCondition.ASLEEP:    return "SLP"
		SpecialCondition.BURNED:    return "BRN"
		SpecialCondition.CONFUSED:  return "CNF"
		SpecialCondition.PARALYZED: return "PAR"
		SpecialCondition.POISONED:  return "PSN"
	return "?"


## --- Mutators (no legality checks — Manager is responsible) -----------------

func apply_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - maxi(0, amount))
	refresh_visual()


func heal(amount: int) -> void:
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	refresh_visual()


func add_condition(c: SpecialCondition) -> void:
	if not special_conditions.has(c):
		special_conditions.append(c)
	refresh_visual()


func remove_condition(c: SpecialCondition) -> void:
	special_conditions.erase(c)
	refresh_visual()


func attach_energy(energy_card: CardData) -> void:
	attached_energy.append(energy_card)
	refresh_visual()


func attach_tool(tool_card: CardData) -> void:
	attached_tools.append(tool_card)
	refresh_visual()


## Pushes [new_card] onto the evolution stack; the previous top becomes a
## prior stage.  Max HP updates; damage carries over.
func evolve_to(new_card: PokemonCardData) -> void:
	if card != null:
		prior_stages.append(card)
	card = new_card
	var carried_damage := max_hp - current_hp
	max_hp = new_card.hp_max if new_card != null else max_hp
	current_hp = maxi(0, max_hp - carried_damage)
	refresh_visual()


func is_knocked_out() -> bool:
	return current_hp <= 0


## Returns every card currently contained in this instance, in the order:
##   [top card, ...prior stages, ...attached energy, ...attached tools]
func all_cards() -> Array[CardData]:
	var out: Array[CardData] = []
	if card != null:
		out.append(card)
	for c in prior_stages:
		out.append(c)
	for e in attached_energy:
		out.append(e)
	for t in attached_tools:
		out.append(t)
	return out


## Detaches and returns every card; zeroes out dynamic state.  The caller is
## expected to route the returned cards into a specified list (discard, lost
## zone, etc.).  After this call the instance is safe to queue_free.
func release_cards() -> Array[CardData]:
	var out := all_cards()
	card = null
	prior_stages.clear()
	attached_energy.clear()
	attached_tools.clear()
	special_conditions.clear()
	modifiers.clear()
	current_hp = 0
	max_hp = 0
	return out


func set_display_width(w: float) -> void:
	display_width = w
	if _card_visual != null:
		_card_visual.set_display_width(w)
		_card_visual.set_board_mode(true)
	if _hp_label != null:
		_hp_label.position = Vector3(0.0, 0.03, -w * 0.35)
	if _energy_label != null:
		_energy_label.position = Vector3(-w * 0.35, 0.03, w * 0.18)
	if _condition_label != null:
		_condition_label.position = Vector3(w * 0.30, 0.03, w * 0.18)
