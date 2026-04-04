class_name AttachmentDisplay
## Shared utilities for displaying attachment icons on cards.
## Used by card.gd (3D board icons) and main.gd (popup inspector circles).
## Any change to colours, sort order, or labelling only needs to happen here.

## Energy type colours — index must match PokemonCardData.EnergyType enum.
const ENERGY_TYPE_COLORS: Array[Color] = [
	Color(0.70, 0.70, 0.70),  # NONE
	Color(0.95, 0.40, 0.10),  # FIRE
	Color(0.20, 0.50, 0.95),  # WATER
	Color(0.20, 0.75, 0.20),  # GRASS
	Color(0.95, 0.85, 0.10),  # LIGHTNING
	Color(0.70, 0.20, 0.90),  # PSYCHIC
	Color(0.75, 0.35, 0.10),  # FIGHTING
	Color(0.15, 0.08, 0.28),  # DARKNESS
	Color(0.55, 0.60, 0.65),  # METAL
	Color(0.10, 0.55, 0.50),  # DRAGON
	Color(0.85, 0.82, 0.75),  # COLORLESS
]

const TOOL_ICON_COLOR := Color(0.50, 0.20, 0.70)

## Basic energy display names in canonical order (Grass → Fighting).
## Any energy whose display_name exactly matches one of these is treated as
## a basic energy and sorted before all special energy.
const BASIC_ENERGY_NAMES: Array[String] = [
	"Grass Energy",
	"Fire Energy",
	"Water Energy",
	"Lightning Energy",
	"Psychic Energy",
	"Fighting Energy",
]


## Returns the colour for an energy CardInstance.
static func energy_color(inst: CardInstance) -> Color:
	if inst.data is EnergyCardData:
		var idx := int((inst.data as EnergyCardData).energy_type)
		if idx >= 0 and idx < ENERGY_TYPE_COLORS.size():
			return ENERGY_TYPE_COLORS[idx]
	return Color(0.5, 0.5, 0.5)


## Returns the single-letter label for an energy CardInstance.
static func energy_label(inst: CardInstance) -> String:
	if inst.data is EnergyCardData:
		return PokemonCardData.energy_type_to_string(
			(inst.data as EnergyCardData).energy_type
		).substr(0, 1)
	return "?"


## Returns a lexicographically-sortable key for canonical energy ordering:
##   "0_N"  – basic energy (N = 0-5 matching BASIC_ENERGY_NAMES index)
##   "1_"   – any Darkness energy (special, sorted before other specials)
##   "2_"   – any Metal energy (special, sorted before other specials)
##   "3_X"  – all other special energy, alphabetical by display_name
static func energy_sort_key(inst: CardInstance) -> String:
	if not (inst.data is EnergyCardData):
		return "9_"
	var name := inst.data.display_name
	var basic_idx := BASIC_ENERGY_NAMES.find(name)
	if basic_idx >= 0:
		return "0_%d" % basic_idx
	if "Darkness" in name:
		return "1_"
	if "Metal" in name:
		return "2_"
	return "3_" + name


## Returns a new Array[CardInstance] sorted in canonical energy order.
static func sort_energy(energy: Array[CardInstance]) -> Array[CardInstance]:
	var sorted: Array[CardInstance] = energy.duplicate()
	sorted.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return energy_sort_key(a) < energy_sort_key(b)
	)
	return sorted
