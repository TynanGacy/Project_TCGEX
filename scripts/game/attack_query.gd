class_name AttackQuery
extends RefCounted
## Data object describing a player query that pauses the attack pipeline
## until the player responds (e.g. "may" abilities, energy discard choice).

enum Kind {
	MAY_ABILITY,
	CHOOSE_ENERGY_DISCARD,
	CHOOSE_ORDER,
	GENERIC_CHOICE,
}

var kind: int = Kind.GENERIC_CHOICE
var player_id: int = 0
var prompt: String = ""
var options: Array = []
var min_selections: int = 1
var max_selections: int = 1
