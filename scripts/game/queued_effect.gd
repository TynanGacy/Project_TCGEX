class_name QueuedEffect
extends RefCounted
## A single effect resolved during the attack pipeline and queued for later
## execution.  Populated during phases 4-6, pruned in phase 7 (nullification),
## and executed in phase 8.

enum Category {
	CONDITIONAL,
	PRE_DAMAGE,
	ATTACKER_MODIFIER,
	DEFENDER_MODIFIER,
	DAMAGE,
	POST_DAMAGE,
	ON_DAMAGE_RECEIVED,
}

var category: int = Category.POST_DAMAGE
var source_key: String = ""
var execute: Callable
var is_nullifiable: bool = true
var description: String = ""
var needs_query: bool = false
var query_template  ## AttackQuery or null
