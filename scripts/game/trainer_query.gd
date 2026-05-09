class_name TrainerQuery
extends RefCounted
## Data object describing a player query that pauses the trainer pipeline
## until the player responds (e.g. choose a card from hand, pick a Pokémon
## to heal, search the deck).  Parallel to AttackQuery.

enum Kind {
	GENERIC_CHOICE,
	CHOOSE_OWN_POKEMON,        ## Potion, Energy Switch source / dest
	CHOOSE_OPPONENT_BENCH,     ## Pokémon Reversal target
	CHOOSE_OPPONENT_POKEMON,   ## Energy Removal 2 (active or bench)
	CHOOSE_OWN_BENCH,          ## Switch
	CHOOSE_ENERGY_ON_POKEMON,  ## Energy Removal 2, Energy Switch
	CHOOSE_FROM_HAND,          ## TV Reporter discard, evolution picks
	CHOOSE_FROM_LIST,          ## Generic card-list picker (deck/discard search)
	REORDER_TOP_OF_DECK,       ## PokéNav
}

var kind: int = Kind.GENERIC_CHOICE
var player_id: int = 0
var prompt: String = ""
var options: Array = []
var min_selections: int = 1
var max_selections: int = 1
## Free-form filter dictionary (e.g. {"stage":"BASIC"} or {"basic_only":true}).
var filter: Dictionary = {}
