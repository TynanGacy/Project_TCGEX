class_name AttackResolver
extends Node
## Async attack pipeline orchestrator (steps 2-10 of the attack flowchart).
##
## Created as a child of ManagerSystem in _ready().  Holds zero persistent
## state between attacks.  The pipeline runs as a coroutine using await
## between phases.

enum Phase {
	VALIDATE,
	SELECT_TARGET,
	DECLARE,
	CONDITIONALS,
	PRE_DAMAGE_EFFECTS,
	DAMAGE_CALC,
	POST_DAMAGE_EFFECTS,
	NULLIFICATION,
	EXECUTE_QUEUE,
	ON_DAMAGE_RECEIVED,
	EXIT_ATTACK,
}

signal pipeline_completed
signal player_query_requested(query: AttackQuery)
signal player_query_resolved(response: Variant)

var _is_resolving: bool = false


func is_resolving() -> bool:
	return _is_resolving


func resolve_query(response: Variant) -> void:
	player_query_resolved.emit(response)


func begin_attack(action, manager) -> void:
	assert(not _is_resolving, "AttackResolver: re-entrant call")
	_is_resolving = true

	var attacker: PokemonInstance = manager.board_position.get_instance(action.attacker_slot)
	var target: PokemonInstance   = manager.board_position.get_instance(action.target_slot)
	var attack: AttackData        = attacker.card.attacks[action.attack_index]

	var ctx := AttackContext.new()
	ctx.manager       = manager
	ctx.attacker      = attacker
	ctx.target        = target
	ctx.attack        = attack
	ctx.player_id     = action.player_id
	ctx.attacker_slot = action.attacker_slot
	ctx.target_slot   = action.target_slot
	ctx.base_damage   = attack.base_damage
	ctx.bonus_damage  = 0

	## Step 2: Declare — lock in the attack.
	manager.attack_used_this_turn[action.player_id] = true

	## Step 3: Conditionals — confusion first, then effect-based conditionals.
	ctx.current_phase = Phase.CONDITIONALS
	if attacker.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED):
		var pname: String = attacker.card.display_name if attacker.card != null else "Pokémon"
		if not manager.flip_coin("%s confusion" % pname):
			await _wait_for_animations()
			manager.log_message.emit(
				"[Confused] %s is confused — attack fails! Takes 30 damage." % pname
			)
			attacker.apply_damage(30)
			manager.pokemon_state_changed.emit(action.attacker_slot, attacker)
			if attacker.is_knocked_out():
				manager.resolve_knockout(action.attacker_slot, 1 - action.player_id)
			_is_resolving = false
			pipeline_completed.emit()
			return
		await _wait_for_animations()
	EffectRegistry.dispatch_phase_for_attack(attack, Phase.CONDITIONALS, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Tier-3 multi-turn defender immunity: if the primary target has an active
	## effect_immune_until_turn flag (Agility, Iron Defense, etc.), the attack
	## is wholly blocked — no damage and no post-damage effects.
	var primary_tgt: PokemonInstance = manager.board_position.get_instance(action.target_slot)
	if primary_tgt != null and primary_tgt.effect_immune_until_turn != -1 \
			and manager.turn_number <= primary_tgt.effect_immune_until_turn:
		manager.log_message.emit(
			"%s is immune to all effects this turn — attack does nothing." %
				(primary_tgt.card.display_name if primary_tgt.card != null else "Target")
		)
		ctx.attack_blocked = true

	if ctx.attack_blocked:
		_is_resolving = false
		pipeline_completed.emit()
		return

	## Step 4: Pre-damage effects.
	ctx.current_phase = Phase.PRE_DAMAGE_EFFECTS
	EffectRegistry.dispatch_phase_for_attack(attack, Phase.PRE_DAMAGE_EFFECTS, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Step 5: Damage calculation.
	ctx.current_phase = Phase.DAMAGE_CALC
	EffectRegistry.dispatch_phase_for_attack(attack, Phase.DAMAGE_CALC, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Execute attacker modifiers immediately so bonus_damage is ready for W/R.
	_execute_category(ctx, QueuedEffect.Category.ATTACKER_MODIFIER)

	## Step 5c: Defender modifiers (weakness/resistance built-in, plus handler effects).
	_execute_category(ctx, QueuedEffect.Category.DEFENDER_MODIFIER)

	## Step 5d: Queue damage entries.
	var opp_id: int = 1 - action.player_id
	var hit_slots: Array[String] = []
	if attack.hits_each_defending:
		for s in BoardPosition.ACTIVE_SLOTS:
			var sid := "p%d_%s" % [opp_id, s]
			if not manager.board_position.is_empty(sid):
				hit_slots.append(sid)
	else:
		hit_slots.append(action.target_slot)

	for sid in hit_slots:
		var hit_target: PokemonInstance = manager.board_position.get_instance(sid)
		if hit_target == null:
			continue
		var entry := DamageEntry.new()
		entry.target_slot     = sid
		entry.target_instance = hit_target
		entry.base_amount     = ctx.base_damage + ctx.bonus_damage
		entry.final_amount    = ActionAttack._compute_damage(
			entry.base_amount, attacker, hit_target
		)
		# Tier-3 damage immunity (Scrunch, Dragon Dance): zero damage but allow
		# non-damage effects to still resolve.
		if hit_target.damage_immune_until_turn != -1 \
				and manager.turn_number <= hit_target.damage_immune_until_turn:
			entry.final_amount = 0
		if sid == action.target_slot:
			ctx.final_damage = entry.final_amount
		ctx.damage_queue.append(entry)

	## Step 6: Post-damage effects.
	ctx.current_phase = Phase.POST_DAMAGE_EFFECTS
	EffectRegistry.dispatch_phase_for_attack(attack, Phase.POST_DAMAGE_EFFECTS, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Step 7: Nullification (placeholder — no abilities implemented yet).
	ctx.current_phase = Phase.NULLIFICATION

	## Step 8: Execute all queued effects.
	ctx.current_phase = Phase.EXECUTE_QUEUE
	for entry: DamageEntry in ctx.damage_queue:
		if entry.final_amount > 0:
			entry.target_instance.apply_damage(entry.final_amount)
			ctx.damaged_slots.append(entry.target_slot)

	for effect: QueuedEffect in ctx.effect_queue:
		if effect.category == QueuedEffect.Category.ATTACKER_MODIFIER \
				or effect.category == QueuedEffect.Category.DEFENDER_MODIFIER:
			continue
		ctx._query_response = null
		if effect.needs_query and effect.query_template != null:
			player_query_requested.emit(effect.query_template)
			ctx._query_response = await player_query_resolved
		effect.execute.call(ctx)

	## Step 9: On-damage-received (placeholder — no such effects implemented yet).
	ctx.current_phase = Phase.ON_DAMAGE_RECEIVED

	## Step 10: KOs — check simultaneously.
	ctx.current_phase = Phase.EXIT_ATTACK
	for entry: DamageEntry in ctx.damage_queue:
		if entry.target_instance.is_knocked_out():
			manager.resolve_knockout(entry.target_slot, action.player_id)

	## Run post-actions (status conditions, heal, discard, retreat lock, etc.)
	## after KO resolution so bench-damage KOs don't double-process.
	ctx.run_post_actions()
	manager.flush_deferred_effects()

	_is_resolving = false
	pipeline_completed.emit()


## Waits for all queued animations to finish.  No-op if AnimationManager
## is unavailable (headless tests) or has nothing queued.
func _wait_for_animations() -> void:
	var anim_mgr := _get_animation_manager()
	if anim_mgr == null or anim_mgr.skip_animations:
		return
	await anim_mgr.wait_until_drained()


func _get_animation_manager() -> Node:
	return ManagerSystemSingleton.animation_manager


## Immediately executes and removes all queued effects of [cat] from the queue.
func _execute_category(ctx: AttackContext, cat: int) -> void:
	var remaining: Array[QueuedEffect] = []
	for effect: QueuedEffect in ctx.effect_queue:
		if effect.category == cat:
			effect.execute.call(ctx)
		else:
			remaining.append(effect)
	ctx.effect_queue = remaining
