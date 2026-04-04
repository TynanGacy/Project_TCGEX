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

## ---------------------------------------------------------------------------
## Normalised card-face layout fractions (0.0 = top/left edge, 1.0 = bottom/right edge).
## Both the 3D board card (card.gd) and the 2D popup (main.gd) derive their
## pixel / unit positions from these values so the icons align consistently.
## ---------------------------------------------------------------------------

## Energy: vertical centre sits on the bottom edge of the card (50 % overlap).
const ENERGY_NORM_Y := 1.0

## X fraction for the first energy icon centre.
## Chosen to align below the weakness symbol in the card's stats row.
const ENERGY_NORM_START_X := 0.18

## X fraction step between consecutive energy icon centres.
## Sized so 5 circles plus a board overflow '+' all fit within the card width.
const ENERGY_NORM_STEP_X := 0.15

## Tool: horizontal centre on the left edge of the card (50 % overlap).
const TOOL_NORM_X := 0.0

## Y fraction of the first tool icon centre. Derived from board constants:
##   (CARD_HEIGHT / 2 + ICON_START_Z) / CARD_HEIGHT = (0.44 - 0.25) / 0.88 ≈ 0.216
const TOOL_NORM_START_Y := 0.216

## Y fraction step between consecutive tool icon centres.
##   ICON_SPACING / CARD_HEIGHT = 0.20 / 0.88 ≈ 0.227
const TOOL_NORM_STEP_Y := 0.227


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
