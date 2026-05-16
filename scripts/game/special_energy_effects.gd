class_name SpecialEnergyEffects
extends RefCounted
## Runtime behaviour for special energy cards (Rainbow / Darkness / Metal /
## Multi). Card-library auto-classification already populates energy_type
## and extra_types for filtering and display; this helper provides the
## *gameplay* hooks the attack pipeline and energy-attach action consume.
##
## Match cards by `card_id` slug rather than by display name so localisation
## or reprint renames don't silently break the rules.

const _RAINBOW := "rainbow_energy"
const _MULTI   := "multi_energy"
const _DARK    := "darkness_energy"
const _METAL   := "metal_energy"


## --- Slug helpers -----------------------------------------------------------

static func _slug(card: CardData) -> String:
	if card == null:
		return ""
	var parts := String(card.card_id).split("_", false, 2)
	if parts.size() < 3:
		return ""
	return parts[2].to_lower()


static func is_rainbow(card: CardData) -> bool:
	return _slug(card) == _RAINBOW


static func is_multi(card: CardData) -> bool:
	return _slug(card) == _MULTI


static func is_darkness(card: CardData) -> bool:
	return _slug(card) == _DARK


static func is_metal(card: CardData) -> bool:
	return _slug(card) == _METAL


## A card is "special" energy if it is not a basic energy.  Used by Multi's
## degradation clause: Multi provides Colorless only when ANY other special
## energy is attached to the same Pokémon.
static func is_special(card: CardData) -> bool:
	if not (card is EnergyCardData):
		return false
	var s := _slug(card)
	return s == _RAINBOW or s == _MULTI or s == _DARK or s == _METAL


## --- Rainbow: damage counter on attach --------------------------------------

## Called from ActionAttachEnergy.apply() after the energy is on the Pokémon
## and after Poké-Body energy-attach triggers have fired.  Fossils ignore
## (they "can't be affected" by attached-card effects in general; the rule
## text doesn't carve out Rainbow, but applying damage to a Trainer card is
## meaningless — guarding keeps the unit tests honest).
static func run_on_attach(inst: PokemonInstance, card: CardData, _manager) -> void:
	if inst == null or card == null:
		return
	if inst.source_trainer_card != null:
		return
	if is_rainbow(card):
		inst.apply_damage(10)


## --- Darkness: +10 outgoing damage pre-W/R ----------------------------------

## Returns the flat damage bonus Darkness Energies on `attacker` contribute
## to its attack pre-W/R.  Gated by: attacker.pokemon_type == DARKNESS OR
## attacker.card.display_name contains "dark" (case-insensitive — covers the
## "Dark <Pokémon>" prints from era reprints).  Stacks one +10 per attached
## Darkness Energy.
static func outgoing_attacker_bonus(attacker: PokemonInstance) -> int:
	if attacker == null or attacker.card == null:
		return 0
	if not _attacker_qualifies_for_darkness(attacker):
		return 0
	var count := 0
	for e in attacker.attached_energy:
		if is_darkness(e):
			count += 1
	return count * 10


static func _attacker_qualifies_for_darkness(attacker: PokemonInstance) -> bool:
	## Use effective_pokemon_type so Kecleon's "Energy Variation" promotes it
	## to Darkness when only Darkness Energy is attached (an edge case but
	## printed rules apply uniformly).
	var atype: int = AbilityEffects.effective_pokemon_type(attacker)
	if atype == int(PokemonCardData.EnergyType.DARKNESS):
		return true
	var name := String(attacker.card.display_name).to_lower()
	# "dark" must appear as a word ("dark tyranitar", "team magma's dark...")
	# rather than inside an unrelated substring. A naive contains() is good
	# enough for the printed roster — every era reprint that triggers this
	# clause literally begins with "Dark ".
	return name.begins_with("dark ") or name.contains(" dark ")


## --- Metal: -10 incoming damage post-W/R ------------------------------------

## Returns the flat damage reduction Metal Energies attached to `defender`
## contribute to incoming attacks post-W/R.  Gated by: defender's effective
## type == METAL (read via AbilityEffects.effective_pokemon_type so Kecleon
## morph counts).  Stacks one -10 per attached Metal Energy.
static func incoming_reduction(defender: PokemonInstance) -> int:
	if defender == null or defender.card == null:
		return 0
	if AbilityEffects.effective_pokemon_type(defender) != int(PokemonCardData.EnergyType.METAL):
		return 0
	var count := 0
	for e in defender.attached_energy:
		if is_metal(e):
			count += 1
	return count * 10


## --- Multi: conditional type provision --------------------------------------

## Returns the list of energy-type ints `card` provides while attached to
## `inst`.
##   - Basic / Darkness / Metal: [energy_type] (passes through).
##   - Rainbow: every standard type ([] sentinel meaning "wildcard").
##   - Multi: wildcard if no other special on `inst`; else [COLORLESS].
##
## Callers that pay attack costs should treat the empty-array return as
## "matches any single type slot" (a wildcard), since Rainbow/Multi explicitly
## provide only one energy at a time.
static func types_for_attached(inst: PokemonInstance, card: CardData) -> Array[int]:
	if not (card is EnergyCardData):
		return []
	if is_rainbow(card):
		return []  # wildcard
	if is_multi(card):
		if _has_other_special_attached(inst, card):
			return [int(PokemonCardData.EnergyType.COLORLESS)]
		return []  # wildcard
	# Basic / Darkness / Metal — pass through.
	return [int((card as EnergyCardData).energy_type)]


static func _has_other_special_attached(inst: PokemonInstance, self_card: CardData) -> bool:
	if inst == null:
		return false
	## Skip ONE occurrence of self_card (the caller's copy).  Card resources
	## are singletons in CardLibrary, so when the player attaches two Multi
	## Energies the same CardData is referenced twice — a plain `e ==
	## self_card` skip would erase both copies and miss the "other special"
	## clause. Consume only the first match.
	var skipped_self := false
	for e in inst.attached_energy:
		if not skipped_self and e == self_card:
			skipped_self = true
			continue
		if is_special(e):
			return true
	return false
