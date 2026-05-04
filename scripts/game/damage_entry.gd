class_name DamageEntry
extends RefCounted
## Stores the resolved damage for a single target, queued at step 5d and
## applied during step 8 (execute queue).

var target_slot: String = ""
var target_instance: PokemonInstance
var base_amount: int = 0
var attacker_bonus: int = 0
var weakness_multiplied: bool = false
var resistance_applied: bool = false
var final_amount: int = 0
