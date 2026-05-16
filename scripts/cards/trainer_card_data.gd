extends CardData
class_name TrainerCardData

enum TrainerKind { ITEM, SUPPORTER, STADIUM, TOOL }

@export var trainer_kind: TrainerKind = TrainerKind.ITEM

## Effect identifier matching a TrainerEffectRegistry handler.
## Empty string = no effect (card moves to discard with no further action).
@export var effect_key: String = ""

## Runtime configuration for parameterized trainer-effect handlers.
@export var effect_params: Dictionary = {}

## True for Trainer cards that are placed onto the board as a synthetic Basic
## Pokémon (Fossils — Claw, Mysterious, Root).  These cards are routed through
## ActionPlayFossil rather than ActionPlayItem.  Pokémon parameters live in
## effect_params.as_pokemon (display_name, hp).
@export var plays_as_pokemon: bool = false
