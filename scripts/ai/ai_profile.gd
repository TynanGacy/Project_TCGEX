class_name AIProfile
extends RefCounted
## Optional per-deck weight overrides for OpponentAI.
##
## Phase A: stub — every profile is the default (no overrides).  Phase B will
## load `data/ai_profiles/<deck_id>.json` and expose hint weights that the
## scoring function in OpponentAI reads when deciding between candidates.

const PROFILES_DIR := "res://data/ai_profiles/"

var deck_id: String = ""


static func default() -> AIProfile:
	var p := AIProfile.new()
	p.deck_id = "default"
	return p


## Loads a profile for [deck_id] from PROFILES_DIR.  Returns default() if no
## file exists — profiles are optional, never required.
static func for_deck(deck_id_in: String) -> AIProfile:
	var path := PROFILES_DIR + deck_id_in + ".json"
	if not FileAccess.file_exists(path):
		return default()
	var p := AIProfile.new()
	p.deck_id = deck_id_in
	return p
