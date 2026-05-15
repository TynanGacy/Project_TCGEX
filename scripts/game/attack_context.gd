class_name AttackContext
## Data context passed to EffectRegistry handlers during attack resolution.
##
## Resolution order in ActionAttack.apply():
##   1. base_damage is set from the AttackData.
##   2. EffectRegistry.dispatch() is called — handlers may set bonus_damage,
##      or enqueue post-damage actions via add_post_action().
##   3. final_damage is computed: _compute_damage(base_damage + bonus_damage)
##      applying weakness and resistance.
##   4. final_damage is applied to the target.
##   5. KO is checked and resolved.
##   6. run_post_actions() is called — handlers apply status conditions,
##      bench damage, self-heal, discard effects, etc.

var manager            ## ManagerSystem node
var attacker: PokemonInstance
var target: PokemonInstance
var attack: AttackData
var player_id: int = 0
var attacker_slot: String = ""
var target_slot: String = ""

## Set from AttackData before dispatch. Read-only in handlers.
var base_damage: int = 0

## Handlers increment this before W/R is applied (e.g. "+20 damage on heads").
## Do NOT touch final_damage directly from a handler.
var bonus_damage: int = 0

## Set by ActionAttack after W/R. Available to post-actions for reference.
var final_damage: int = 0

var effect_queue: Array[QueuedEffect] = []
var damage_queue: Array[DamageEntry] = []
var damaged_slots: Array[String] = []
var attack_blocked: bool = false
var current_phase: int = -1

## Damage-modifier flags set by CONDITIONALS-phase handlers. Honored by
## AttackResolver's damage-queue construction.
var skip_weakness: bool = false
var skip_resistance: bool = false

var _post_actions: Array[Callable] = []

## Populated by AttackResolver when a needs_query QueuedEffect is about to execute.
var _query_response: Variant = null

## Wave 17 — track energy cards discarded during this attack's resolution.
## Appended by discard_energy / discard_energy_self / Lava Flow / Dragon Burst.
## Chained bonus-damage steps read .size() to scale damage by discard count.
var discarded_this_attack: Array[CardData] = []

## Wave 17 — opaque string flags handlers can set/check across chain entries.
## E.g. Flame Pillar's may_discard_for_bonus sets a flag the chained
## damage_chosen_target reads to gate the bench damage on whether discard happened.
var attack_flags: Dictionary = {}

## Wave 18 — when true, the resolver's hit-slot loop iterates all defender
## ACTIVE_SLOTS even if attack.hits_each_defending is false. Used by
## may_split_damage_each (Split Blast) to convert a single-target attack into
## an all-defending split at DAMAGE_CALC time.
var force_hit_each_defending: bool = false

## Wave 19 — single-level guard for sub-attack invocation (Genetic Memory).
## invoke_sub_attack increments before nesting and decrements after.
var sub_attack_depth: int = 0


## Queue [fn] to run after damage is applied and KO is resolved.
## Use this for status conditions, bench damage, energy discards, etc.
func add_post_action(fn: Callable) -> void:
	_post_actions.append(fn)


## Called by ActionAttack after the KO check.
## Queues post-actions on the manager for deferred execution after animations complete.
func run_post_actions() -> void:
	for fn in _post_actions:
		manager.queue_deferred_effect(fn)


## Flips a coin, emits the game-wide coin_flipped signal, logs the result,
## and returns true for heads.
func flip_coin() -> bool:
	var heads: bool = manager.flip_coin(attack.name)
	manager.log_message.emit(
		"[Coin] %s — %s" % [attack.name, "Heads" if heads else "Tails"]
	)
	return heads


## Flips [count] coins as a batch, emits the batch signal for staggered
## animation, logs each result individually, and returns the array.
func flip_coins(count: int) -> Array[bool]:
	var results: Array[bool] = manager.flip_coins_batch(count, attack.name)
	for i in range(results.size()):
		manager.log_message.emit(
			"[Coin] %s (#%d) — %s" % [attack.name, i + 1, "Heads" if results[i] else "Tails"]
		)
	return results


## Applies [amount] damage to [inst] through the normal apply_damage path.
## Use this in post-actions for bench/self damage so HP is tracked correctly.
func deal_damage_to(inst: PokemonInstance, amount: int) -> void:
	if inst == null or amount <= 0:
		return
	inst.apply_damage(amount)
	manager.log_message.emit(
		"[Effect] %d damage to %s." % [amount, inst.card.display_name if inst.card else "?"]
	)
