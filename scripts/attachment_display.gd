class_name AttachmentDisplay
## Static utilities for rendering energy and tool attachment icons on in-play
## Pokemon.  Referenced by PokemonInstance for 3D board icons and can be used
## by any 2D popup inspector.  Centralising colours and layout means a single
## edit propagates everywhere.
##
## Designed to work with the four-system architecture (PokemonInstance /
## BoardPosition / GamePosition / ManagerSystem) and the MatchAuthority
## transport abstraction: all methods are pure functions of CardData state so
## they compose cleanly with both local and future online authority paths.

## Colours indexed by PokemonCardData.EnergyType enum value.
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

## Basic energy display names — defines canonical sort order (basic before special).
const BASIC_ENERGY_NAMES: Array[String] = [
	"Grass Energy",
	"Fire Energy",
	"Water Energy",
	"Lightning Energy",
	"Psychic Energy",
	"Fighting Energy",
]

## Normalised card-face layout fractions (0.0 = top/left edge, 1.0 = bottom/right edge).
## Both the 3D board card (PokemonInstance) and any 2D popup inspector derive
## positions from these so icons align consistently across rendering contexts.

## Energy: disc centres sit on the bottom card edge (50 % overlap below the card).
const ENERGY_NORM_Y       := 1.0
## X fraction for the first energy disc centre (aligned with weakness column).
const ENERGY_NORM_START_X := 0.18
## X fraction step between consecutive disc centres.
## Sized so MAX_VISIBLE_ENERGY discs plus an overflow label all fit within card width.
const ENERGY_NORM_STEP_X  := 0.15

## Tool: disc centre sits on the left card edge (50 % overlap to the left).
const TOOL_NORM_X       := 0.0
## Y fraction of the tool disc centre (upper portion of card, beside art).
const TOOL_NORM_START_Y := 0.216

## Maximum energy icons rendered individually; any excess collapses to a "+N" label.
const MAX_VISIBLE_ENERGY := 5

## ---------------------------------------------------------------------------
## Energy sphere crop profiles
## ---------------------------------------------------------------------------
## Each profile defines where the energy sphere sits on the card art so the
## attachment disc can be cropped and centred on it.
##
##   center : Vector2  Normalised UV position of the sphere centre on the card
##                     image.  (0,0) = top-left, (1,1) = bottom-right.
##   radius : float    Fraction of card width covered by the sphere's radius.
##                     The rendered disc shows a square crop of side (2*radius)
##                     centred on 'center', so smaller = more zoomed in.
##
## To add a new card: pick or create a profile that matches its art layout,
## then add an entry to ENERGY_CARD_PROFILE keyed by card_id.

const ENERGY_SPHERE_PROFILES: Dictionary = {
	## Basic energies (RS set — Grass/Fire/Water/Lightning/Psychic/Fighting).
	## Large sphere in the lower portion of the art, below the triangular glow.
	## All six cards share the same template.
	"rs_basic": {
		"center": Vector2(0.750, 0.450),
		"radius": 0.500,
	},
	## Special energies based on RS Darkness/Metal Energy.
	"rs_pseudo_special": {
		"center": Vector2(0.700, 0.375),
		"radius": 0.385,
	},
	## Special energies based on Rainbow Energy.
	"rainbow": {
		"center": Vector2(0.605, 0.320),
		"radius": 0.210,
	},
	## Special energies based on Multi Energy.
	"multi": {
		"center": Vector2(0.750, 0.288),
		"radius": 0.500,
	},

}

const ENERGY_CARD_PROFILE: Dictionary = {
	"RS_104_grass_energy":     "rs_basic",
	"RS_105_fighting_energy":  "rs_basic",
	"RS_106_water_energy":     "rs_basic",
	"RS_107_psychic_energy":   "rs_basic",
	"RS_108_fire_energy":      "rs_basic",
	"RS_109_lightning_energy": "rs_basic",
	"RS_93_darkness_energy":   "rs_pseudo_special",
	"RS_94_metal_energy":      "rs_pseudo_special",
	"RS_95_rainbow_energy":    "rainbow",
	"SS_93_multi_energy":      "multi",
}


## Returns the display colour for [card_data] if it is an EnergyCardData.
static func energy_color(card_data: CardData) -> Color:
	if card_data is EnergyCardData:
		var idx := int((card_data as EnergyCardData).energy_type)
		if idx >= 0 and idx < ENERGY_TYPE_COLORS.size():
			return ENERGY_TYPE_COLORS[idx]
	return Color(0.5, 0.5, 0.5)


## Returns the single-letter type abbreviation for [card_data].
static func energy_label(card_data: CardData) -> String:
	if card_data is EnergyCardData:
		return PokemonCardData.energy_type_to_string(
			(card_data as EnergyCardData).energy_type
		).substr(0, 1)
	return "?"


## Returns a lexicographically-sortable key for canonical energy ordering:
##   "0_N" — basic energy (N = index in BASIC_ENERGY_NAMES, Grass…Fighting)
##   "1_"  — Darkness special energy
##   "2_"  — Metal special energy
##   "3_X" — all other special energy, alphabetical by display_name
static func energy_sort_key(card_data: CardData) -> String:
	if not (card_data is EnergyCardData):
		return "9_"
	var n := card_data.display_name
	var basic_idx := BASIC_ENERGY_NAMES.find(n)
	if basic_idx >= 0:
		return "0_%d" % basic_idx
	if "Darkness" in n:
		return "1_"
	if "Metal" in n:
		return "2_"
	return "3_" + n


## Returns a new Array[CardData] sorted in canonical energy order.
static func sort_energy(energy: Array[CardData]) -> Array[CardData]:
	var sorted: Array[CardData] = energy.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData) -> bool:
		return energy_sort_key(a) < energy_sort_key(b)
	)
	return sorted


## Returns the sphere-crop profile for [card_data] as a Dictionary with
## keys "center" (Vector2) and "radius" (float).  Falls back to "basic" if
## the card has no registered profile.
static func sphere_crop(card_data: CardData) -> Dictionary:
	var profile_name: String = ENERGY_CARD_PROFILE.get(card_data.card_id, "rs_basic")
	return ENERGY_SPHERE_PROFILES.get(profile_name, ENERGY_SPHERE_PROFILES["rs_basic"])
