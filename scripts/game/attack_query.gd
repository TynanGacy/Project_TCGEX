class_name AttackQuery
extends RefCounted
## Data object describing a player query that pauses the attack pipeline
## until the player responds (e.g. "may" abilities, energy discard choice).

enum Kind {
	MAY_ABILITY,
	CHOOSE_ENERGY_DISCARD,
	CHOOSE_ORDER,
	GENERIC_CHOICE,
	CHOOSE_BENCH_TARGET,      ## Group N — pick an opponent bench Pokémon
	MAY_DISCARD_FOR_BONUS,    ## Group H — opt in/out of energy discard for bonus damage
	CHOOSE_ENERGY_FROM_HAND,  ## Group M — select energy from hand to attach
	MAY_CONFIRM,              ## Wave 17 — generic yes/no confirm
	CHOOSE_DISCARD_COUNT,     ## Wave 17 — Lava Flow / Dragon Burst / Quick Touch energy multi-pick
	CHOOSE_ENERGY_TYPE,       ## Wave 17 — Dragon Burst (FIRE or LIGHTNING)
	CHOOSE_OPP_HAND_BLIND,    ## Wave 19 — Lombre/Murkrow/Duskull Surprise, Absol Bad News
	CHOOSE_OPP_HAND_OPEN,     ## Wave 19 — Sableye, Mawile, Skarmory (filter via `filter` dict)
	CHOOSE_ATTACK_FROM_CARDS, ## Wave 19 — Genetic Memory
}

var kind: int = Kind.GENERIC_CHOICE
var player_id: int = 0
var prompt: String = ""
var options: Array = []
var min_selections: int = 1
var max_selections: int = 1

## Wave 19 — filter spec for CHOOSE_OPP_HAND_OPEN (e.g. {"supporter_only": true}).
## Empty dict = no filter. UI dimmer disables non-matching cards.
var filter: Dictionary = {}
