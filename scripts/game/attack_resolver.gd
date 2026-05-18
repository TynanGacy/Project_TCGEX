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


## Wave 17 — coroutine-friendly helper. Handlers can `await resolver.ask(query)`
## inline, mirroring TrainerResolver.ask. Emits player_query_requested and
## awaits the matching resolved signal. Tests connect to the signal directly
## via _auto_answer_query / _auto_answer_queries; the live UI routes through
## DialogManager.on_attack_query_requested.
func ask(query: AttackQuery) -> Variant:
	player_query_requested.emit(query)
	return await player_query_resolved


## Wave 19 — invoke a Pokémon attack from a card OTHER than attacker.card
## (used by Genetic Memory to call attacks of prior-stage cards). Cost is
## waived; the parent attack already paid. Single-level nesting only —
## guarded by ctx.sub_attack_depth.
func invoke_sub_attack(ctx: AttackContext, sub_card: PokemonCardData,
		sub_attack_index: int) -> void:
	if ctx.sub_attack_depth > 0:
		return
	if sub_card == null or sub_attack_index < 0 \
			or sub_attack_index >= sub_card.attacks.size():
		return
	var sub: AttackData = sub_card.attacks[sub_attack_index]
	if sub == null:
		return
	ctx.sub_attack_depth += 1
	# Build an action that targets the same defender as the parent attack.
	var sub_action := ActionAttack.new(ctx.player_id, ctx.attacker_slot,
		sub_attack_index, ctx.target_slot)
	# Bypass the re-entrancy assert by running with is_sub_attack=true.
	await begin_attack_with_attack(sub_action, ctx.manager, sub, {
		"is_sub_attack": true,
		"skip_conditionals_gate": true,
	})
	ctx.sub_attack_depth -= 1


## Wave 19 — invoke a Trainer (Supporter) effect from within an attack.
## Used by Sableye Supernatural to "use the effect of a Supporter card you
## find in your opponent's hand". Translates AttackContext → TrainerContext,
## sets the `invoked_inline` sentinel, then dispatches APPLY + POST_APPLY
## through the existing TrainerEffectRegistry. Skips VALIDATE entirely —
## the caller has already decided to play this effect; running VALIDATE
## could fail on conditions like supporter_played_this_turn that don't
## apply when invoked inline.
##
## Does NOT remove the supporter from opp's hand (caller's responsibility)
## and does NOT set supporter_played_this_turn (per design: Supernatural
## should not consume the attacker's once-per-turn supporter slot).
func invoke_trainer_effect_inline(effect_key: String, ctx: AttackContext,
		card: TrainerCardData) -> void:
	if effect_key == "":
		return
	if not TrainerEffectRegistry.has_definition(effect_key):
		return
	var tctx := TrainerContext.new()
	tctx.manager = ctx.manager
	tctx.player_id = ctx.player_id
	tctx.card = card
	if card != null and card.effect_params != null:
		tctx.params = card.effect_params.duplicate(true)
	tctx.params["invoked_inline"] = true
	# Run PROMPT if present — supporter may need a query.
	var query: TrainerQuery = await TrainerEffectRegistry.get_query(effect_key, tctx)
	if query != null:
		ctx.manager.trainer_resolver.player_query_requested.emit(query)
		tctx.query_response = await ctx.manager.trainer_resolver.player_query_resolved
	var def = TrainerEffectRegistry._definitions[effect_key]
	if def.phase_handlers.has(TrainerResolver.Phase.APPLY):
		await def.phase_handlers[TrainerResolver.Phase.APPLY].call(tctx)
	if def.phase_handlers.has(TrainerResolver.Phase.POST_APPLY):
		await def.phase_handlers[TrainerResolver.Phase.POST_APPLY].call(tctx)


func begin_attack(action, manager) -> void:
	## Thin wrapper around begin_attack_with_attack. Resolves the AttackData
	## from the attacker's card by attack_index — the standard path used by
	## ActionAttack. Wave 19's invoke_sub_attack uses begin_attack_with_attack
	## directly with an explicit AttackData override and opts.
	var attacker: PokemonInstance = manager.board_position.get_instance(action.attacker_slot)
	var attack: AttackData = attacker.card.attacks[action.attack_index]
	await begin_attack_with_attack(action, manager, attack, {})


## Wave 18: extracted resolver body. Accepts an explicit AttackData so callers
## (e.g. Wave 19's invoke_sub_attack for Genetic Memory) can supply an attack
## from a card OTHER than attacker.card.
##
## opts keys:
##   "skip_conditionals_gate": bool — when true, bypasses smokescreen +
##       confusion gates at the top of the pipeline. Used for sub-attacks
##       so conditions on the parent attacker are checked once, not nested.
##   "is_sub_attack": bool — when true, signals a nested invocation; the
##       caller is responsible for managing _is_resolving / sub_attack_depth.
##       In this mode the assert(not _is_resolving) is suppressed, the
##       declaration step is suppressed (attack_used_this_turn already set
##       by the parent), and pipeline_completed is NOT emitted at the end
##       (the parent pipeline emits its own).
func begin_attack_with_attack(action, manager, attack: AttackData, opts: Dictionary = {}) -> void:
	var is_sub: bool = bool(opts.get("is_sub_attack", false))
	var skip_cond: bool = bool(opts.get("skip_conditionals_gate", false))
	if not is_sub:
		assert(not _is_resolving, "AttackResolver: re-entrant call")
		_is_resolving = true

	var attacker: PokemonInstance = manager.board_position.get_instance(action.attacker_slot)
	var target: PokemonInstance   = manager.board_position.get_instance(action.target_slot)

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
	if not is_sub:
		manager.attack_used_this_turn[action.player_id] = true

	## Step 3: Conditionals — confusion first, then effect-based conditionals.
	ctx.current_phase = Phase.CONDITIONALS

	## Smokescreen-style coin gate. If the attacker has a pending
	## next-attack-coin-fail flag, flip a coin; tails blocks the attack.
	## Flag is one-shot — cleared on first trigger regardless of outcome.
	## Wave 19: sub-attacks skip this gate (parent already paid for it).
	if not skip_cond and attacker.next_attack_coin_fail_until_turn != -1 \
			and manager.turn_number <= attacker.next_attack_coin_fail_until_turn:
		var sname: String = attacker.card.display_name if attacker.card != null else "Pokémon"
		var passed: bool = manager.flip_coin("%s smokescreen" % sname)
		attacker.next_attack_coin_fail_until_turn = -1
		if not passed:
			await _wait_for_animations()
			manager.log_message.emit(
				"[Smokescreen] %s's attack does nothing (tails)." % sname
			)
			if not is_sub:
				_is_resolving = false
				pipeline_completed.emit()
			return
		await _wait_for_animations()

	if not skip_cond and attacker.special_conditions.has(PokemonInstance.SpecialCondition.CONFUSED):
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
			if not is_sub:
				_is_resolving = false
				pipeline_completed.emit()
			return
		await _wait_for_animations()
	await EffectRegistry.dispatch_phase_for_attack(attack, Phase.CONDITIONALS, ctx, ctx.effect_queue)
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

	## Wave 2 — Wonder Guard (Shedinja) / Safeguard (Wobbuffet): total
	## immunity from attacks by a matching source class. Blocks both damage
	## and post-damage effects, just like effect_immune_until_turn.
	if not ctx.attack_blocked and primary_tgt != null \
			and AbilityEffects.attack_blocked_by_source_immunity(primary_tgt, attacker, manager):
		manager.log_message.emit(
			"[Body] %s — attack has no effect on %s." % [
				_immunity_body_name(primary_tgt),
				primary_tgt.card.display_name if primary_tgt.card != null else "Target",
			]
		)
		ctx.attack_blocked = true

	if ctx.attack_blocked:
		_is_resolving = false
		pipeline_completed.emit()
		return

	## Step 4: Pre-damage effects.
	ctx.current_phase = Phase.PRE_DAMAGE_EFFECTS
	await EffectRegistry.dispatch_phase_for_attack(attack, Phase.PRE_DAMAGE_EFFECTS, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Execute any PRE_DAMAGE-category effects inline so they (and their queries)
	## resolve BEFORE damage calc. Used by attacks that switch the defender,
	## ignore tools, etc. Effects of other categories stay in the queue for
	## later phases.
	var remaining: Array[QueuedEffect] = []
	for pre_eff: QueuedEffect in ctx.effect_queue:
		if pre_eff.category != QueuedEffect.Category.PRE_DAMAGE:
			remaining.append(pre_eff)
			continue
		ctx._query_response = null
		if pre_eff.needs_query and pre_eff.query_template != null:
			player_query_requested.emit(pre_eff.query_template)
			ctx._query_response = await player_query_resolved
		pre_eff.execute.call(ctx)
	ctx.effect_queue = remaining

	## Step 5: Damage calculation.
	ctx.current_phase = Phase.DAMAGE_CALC
	await EffectRegistry.dispatch_phase_for_attack(attack, Phase.DAMAGE_CALC, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Execute attacker modifiers immediately so bonus_damage is ready for W/R.
	_execute_category(ctx, QueuedEffect.Category.ATTACKER_MODIFIER)

	## Wave 12: consume any queued next-turn bonus-damage entries on the attacker.
	## Each entry is one-shot. Expired entries are pruned.
	for i in range(attacker.next_turn_attack_bonuses.size() - 1, -1, -1):
		var entry = attacker.next_turn_attack_bonuses[i]
		if not (entry is Dictionary):
			attacker.next_turn_attack_bonuses.remove_at(i)
			continue
		var until_turn: int = int(entry.get("until_turn", -1))
		if manager.turn_number > until_turn:
			attacker.next_turn_attack_bonuses.remove_at(i)
			continue
		var want_name: String = str(entry.get("attack_name", ""))
		if want_name != "" and want_name != attack.name:
			continue
		ctx.bonus_damage += int(entry.get("amount", 0))
		attacker.next_turn_attack_bonuses.remove_at(i)

	## Step 5c: Defender modifiers (weakness/resistance built-in, plus handler effects).
	_execute_category(ctx, QueuedEffect.Category.DEFENDER_MODIFIER)

	## Step 5d: Queue damage entries.
	## Wave 18: ctx.force_hit_each_defending lets DAMAGE_CALC handlers (e.g.
	## may_split_damage_each / Split Blast) escalate a single-target attack
	## into all-defending after a player confirms.
	var opp_id: int = 1 - action.player_id
	var hit_slots: Array[String] = []
	if attack.hits_each_defending or ctx.force_hit_each_defending:
		for s in BoardPosition.ACTIVE_SLOTS:
			var sid := "p%d_%s" % [opp_id, s]
			if not manager.board_position.is_empty(sid):
				hit_slots.append(sid)
	else:
		hit_slots.append(action.target_slot)

	## Pre-W/R Poké-Body modifiers on the attacker's side (Crawdaunt's Power
	## Pinchers etc.).  Single value applied across all hit slots for this
	## attack — the carrier is the attacker's controller's active.
	var attacker_aura_bonus: int = AbilityEffects.damage_dealt_modifier_before_wr(
		attacker, manager
	)
	## Darkness Energy: +10 per attached copy when the attacker qualifies
	## (Darkness type or has "Dark" in its name). Stacks; pre-W/R.
	attacker_aura_bonus += SpecialEnergyEffects.outgoing_attacker_bonus(attacker)

	for sid in hit_slots:
		var hit_target: PokemonInstance = manager.board_position.get_instance(sid)
		if hit_target == null:
			continue
		var entry := DamageEntry.new()
		entry.target_slot     = sid
		entry.target_instance = hit_target
		entry.base_amount     = ctx.base_damage + ctx.bonus_damage + attacker_aura_bonus
		## Pre-W/R defender-side Poké-Body modifier (Intimidating Fang).
		var defender_pre_wr: int = AbilityEffects.damage_taken_modifier_before_wr(
			hit_target, manager
		)
		entry.base_amount = maxi(0, entry.base_amount + defender_pre_wr)

		## Wave 2 — Beautifly "Withering Dust": while in active position on
		## either side, no Active Pokémon has Resistance. Force-skip the
		## resistance leg of the W/R compute.
		var skip_resistance_eff: bool = ctx.skip_resistance \
				or AbilityEffects.global_resistance_disabled(manager)
		entry.final_amount    = ActionAttack._compute_damage(
			entry.base_amount, attacker, hit_target,
			ctx.skip_weakness, skip_resistance_eff
		)
		## Wave 2 — Whiscash "Submerge": prevent damage while benched.
		if AbilityEffects.bench_damage_blocked(hit_target, sid, manager):
			entry.final_amount = 0
		# Tier-3 damage immunity (Scrunch, Dragon Dance): zero damage but allow
		# non-damage effects to still resolve.
		if hit_target.damage_immune_until_turn != -1 \
				and manager.turn_number <= hit_target.damage_immune_until_turn:
			entry.final_amount = 0
		# Wave-9 damage reduction (Granite Head): subtract a flat amount after W/R.
		if entry.final_amount > 0 \
				and hit_target.damage_reduction_until_turn != -1 \
				and manager.turn_number <= hit_target.damage_reduction_until_turn:
			entry.final_amount = maxi(0,
				entry.final_amount - hit_target.damage_reduction_amount)
		# Tool-based damage reduction (Buffer Piece): subtract a flat amount after W/R.
		if entry.final_amount > 0:
			var tool_reduction: int = ToolEffects.damage_reduction_for(hit_target)
			if tool_reduction > 0:
				entry.final_amount = maxi(0, entry.final_amount - tool_reduction)
		# Metal Energy: -10 per attached copy when defender is Metal type. Post-W/R.
		if entry.final_amount > 0:
			var metal_reduction: int = SpecialEnergyEffects.incoming_reduction(hit_target)
			if metal_reduction > 0:
				entry.final_amount = maxi(0, entry.final_amount - metal_reduction)
		# Poké-Body post-W/R modifiers (Exoskeleton, Energy Guard, Glowing Screen).
		if entry.final_amount > 0:
			var ability_delta: int = AbilityEffects.damage_taken_modifier_after_wr(
				hit_target, attacker, manager
			)
			if ability_delta != 0:
				entry.final_amount = maxi(0, entry.final_amount + ability_delta)
		# Coin-gated Poké-Body reduction (Sand Guard, Hard Cocoon).
		if entry.final_amount > 0:
			var coin_reduction: int = AbilityEffects.coin_gated_reduction_for_target(
				hit_target, manager
			)
			if coin_reduction > 0:
				entry.final_amount = maxi(0, entry.final_amount - coin_reduction)
		if sid == action.target_slot:
			ctx.final_damage = entry.final_amount
		ctx.damage_queue.append(entry)

	## Step 6: Post-damage effects.
	ctx.current_phase = Phase.POST_DAMAGE_EFFECTS
	await EffectRegistry.dispatch_phase_for_attack(attack, Phase.POST_DAMAGE_EFFECTS, ctx, ctx.effect_queue)
	await _wait_for_animations()

	## Step 7: Nullification (placeholder — no abilities implemented yet).
	ctx.current_phase = Phase.NULLIFICATION

	## Step 8: Execute all queued effects.
	ctx.current_phase = Phase.EXECUTE_QUEUE
	for entry: DamageEntry in ctx.damage_queue:
		if entry.final_amount > 0:
			entry.target_instance.apply_damage(entry.final_amount)
			ctx.damaged_slots.append(entry.target_slot)
			## Pattern E — Poké-Body retaliation (Rough Skin, Fire Veil,
			## Poison Payback). Fires "even if [target] is Knocked Out", so
			## we run it after the damage application regardless of KO state.
			AbilityEffects.run_on_damaged_by_attack(
				entry.target_instance, entry.target_slot,
				attacker, action.attacker_slot, manager
			)

	## Wave 2 — Dustox "Protective Dust": prevent all attack effects (status,
	## discard, etc.) on the primary target. Damage already applied above is
	## kept. We skip both the effect_queue iteration and run_post_actions
	## further down. This over-blocks split-target effects (rare in the
	## current roster); see AbilityEffects.defender_blocks_attack_effects.
	var effects_blocked: bool = AbilityEffects.defender_blocks_attack_effects(primary_tgt, manager)
	if not effects_blocked:
		for effect: QueuedEffect in ctx.effect_queue:
			if effect.category == QueuedEffect.Category.ATTACKER_MODIFIER \
					or effect.category == QueuedEffect.Category.DEFENDER_MODIFIER:
				continue
			ctx._query_response = null
			if effect.needs_query and effect.query_template != null:
				player_query_requested.emit(effect.query_template)
				ctx._query_response = await player_query_resolved
			effect.execute.call(ctx)
	elif primary_tgt != null:
		manager.log_message.emit(
			"[Body] Protective Dust — attack effects on %s prevented." % (
				primary_tgt.card.display_name if primary_tgt.card != null else "target"
			)
		)

	## Step 9: On-damage-received (placeholder — no such effects implemented yet).
	ctx.current_phase = Phase.ON_DAMAGE_RECEIVED

	## Step 10: KOs — check simultaneously.
	ctx.current_phase = Phase.EXIT_ATTACK
	for entry: DamageEntry in ctx.damage_queue:
		if entry.target_instance.is_knocked_out():
			manager.resolve_knockout(entry.target_slot, action.player_id)

	## Run post-actions (status conditions, heal, discard, retreat lock, etc.)
	## after KO resolution so bench-damage KOs don't double-process.  Skipped
	## entirely when Protective Dust gates effects on the primary target.
	if not effects_blocked:
		ctx.run_post_actions()
	manager.flush_deferred_effects()

	## Wave 7 — Chain of Events (Plusle / Minun): when a regular attack
	## finishes, a Pokémon in the OTHER active slot carrying Chain of Events
	## may use its own attack[0] (Cheer On) once per turn. Fires before
	## pipeline_completed so request_action_async callers await it too.
	if not is_sub:
		await _maybe_chain_of_events(action, manager)

	if not is_sub:
		_is_resolving = false
		pipeline_completed.emit()


## Wave 7 — Chain of Events trigger. Called once at the tail of a regular
## (non-sub) attack pipeline. Bails on any of: chain already used this turn,
## no carrier in the other active slot, carrier KO'd, carrier condition-
## locked, carrier can't pay Cheer On's energy cost, no opp Active to target.
## Sets manager.chain_of_events_used_this_turn BEFORE invoking the sub-attack
## so the chain itself can't recursively chain.
func _maybe_chain_of_events(parent_action, manager) -> void:
	if manager.chain_of_events_used_this_turn[parent_action.player_id]:
		return
	var carrier_slot: String = AbilityEffects.find_chain_of_events_carrier_slot(
		parent_action.attacker_slot, manager)
	if carrier_slot == "":
		return
	var carrier: PokemonInstance = manager.board_position.get_instance(carrier_slot)
	if carrier == null or carrier.card == null or carrier.is_knocked_out():
		return
	if carrier.card.attacks.is_empty():
		return
	if carrier.special_conditions.has(PokemonInstance.SpecialCondition.ASLEEP) \
			or carrier.special_conditions.has(PokemonInstance.SpecialCondition.PARALYZED):
		manager.log_message.emit(
			"[Body] Chain of Events — %s is condition-locked; no chain." %
				carrier.card.display_name
		)
		return
	var cheer_on: AttackData = carrier.card.attacks[0]
	var pay_check: ActionResult = ActionAttack._check_energy(carrier, cheer_on)
	if not pay_check.ok:
		manager.log_message.emit(
			"[Body] Chain of Events — %s can't pay %s's cost." % [
				carrier.card.display_name, cheer_on.name,
			]
		)
		return
	var opp_id: int = 1 - parent_action.player_id
	var target_slot: String = ""
	for s in BoardPosition.ACTIVE_SLOTS:
		var sid := "p%d_%s" % [opp_id, s]
		if manager.board_position.get_instance(sid) != null:
			target_slot = sid
			break
	if target_slot == "":
		return
	manager.chain_of_events_used_this_turn[parent_action.player_id] = true
	manager.log_message.emit(
		"[Body] Chain of Events — %s uses %s." % [
			carrier.card.display_name, cheer_on.name,
		]
	)
	var chain_action := ActionAttack.new(parent_action.player_id,
		carrier_slot, 0, target_slot)
	await begin_attack_with_attack(chain_action, manager, cheer_on, {
		"is_sub_attack": true,
		"skip_conditionals_gate": true,
	})


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


## Returns the name of the first source-immunity body on [inst] for log
## prefix formatting.  Returns "Wonder Guard" / "Safeguard" / etc. so the
## log line names the specific power instead of a generic "immunity".
func _immunity_body_name(inst: PokemonInstance) -> String:
	if inst == null or inst.card == null:
		return "Immunity"
	for abil in inst.card.abilities:
		if abil != null and abil.effect_key == AbilityEffects.BODY_SOURCE_IMMUNITY:
			return abil.ability_name
	return "Immunity"
