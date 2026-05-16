class_name AbilityQuery
extends RefCounted
## Data object describing a player query that pauses an ability pipeline until
## the player responds (e.g. pick a Pokémon to receive a Poké-Power's effect).
##
## Mirror of TrainerQuery — Poké-Powers reuse the same UI affordances as
## Trainer cards, so kind values are kept compatible.

enum Kind {
	GENERIC_CHOICE,
	CHOOSE_OWN_POKEMON,
	CHOOSE_OPPONENT_BENCH,
	CHOOSE_OPPONENT_POKEMON,
	CHOOSE_OWN_BENCH,
	CHOOSE_ENERGY_ON_POKEMON,
	CHOOSE_FROM_HAND,
	CHOOSE_FROM_LIST,
	REORDER_TOP_OF_DECK,
}

var kind: int = Kind.GENERIC_CHOICE
var player_id: int = 0
var prompt: String = ""
var options: Array = []
var min_selections: int = 1
var max_selections: int = 1
var filter: Dictionary = {}
