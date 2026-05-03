class_name AnimationRequest
extends RefCounted
## Data object describing a visual animation to enqueue in AnimationManager.

enum Kind {
	COIN_FLIP,
	COIN_BATCH,
	DAMAGE_APPLIED,
	STATUS_APPLIED,
	ATTACK_MAIN,
	ENERGY_DISCARD,
	KNOCKOUT,
	GENERIC_DELAY,
}

var id: int = -1
var kind: int = Kind.GENERIC_DELAY
var duration: float = 0.5
var data: Dictionary = {}
