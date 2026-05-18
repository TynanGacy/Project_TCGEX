class_name ToolEffects
## Static helpers that read passive effects from Pokémon Tool attachments.
##
## Tools are persistent, per-Pokémon attachments; their effects don't dispatch
## through TrainerResolver when the Tool is attached.  Instead, game-flow code
## paths (ActionRetreat, AttackResolver, ManagerSystem cleanup) call into this
## helper to ask each attached Tool for its modifier.
##
## Mirror of StadiumEffects.  Authoring a new tool effect is "add JSON
## effect_key + extend the matching helper here."

const _LUM_BERRY_KEY: String = "tool_clear_conditions_on_attach"
const _ORAN_BERRY_KEY: String = "tool_heal_on_damage"
const _BALLOON_BERRY_KEY: String = "tool_free_retreat_once"
const _BUFFER_PIECE_KEY: String = "tool_damage_reduction"


## Returns true iff [key] is a tool effect_key handled by this helper.
## Used by the registry coverage smoke test to validate Tool card JSON.
static func is_known_key(key: String) -> bool:
	return key == _LUM_BERRY_KEY \
		or key == _ORAN_BERRY_KEY \
		or key == _BALLOON_BERRY_KEY \
		or key == _BUFFER_PIECE_KEY


## Returns the flat damage reduction (after W/R) applied by any tool attached
## to [target].  Returns 0 if no relevant tool is attached.
##
## Called from AttackResolver during damage computation, alongside the
## Granite-Head check.
static func damage_reduction_for(target: PokemonInstance) -> int:
	if target == null:
		return 0
	for tool in target.attached_tools:
		var tcard: TrainerCardData = tool as TrainerCardData
		if tcard == null:
			continue
		if tcard.effect_key == _BUFFER_PIECE_KEY:
			return int(tcard.effect_params.get("amount", 20))
	return 0


## If [inst] has a free-retreat tool attached (Balloon Berry), returns that
## tool card (to be discarded in place of energy).  Returns null otherwise.
##
## Called from ActionRetreat before energy-cost validation.
static func free_retreat_tool(inst: PokemonInstance) -> TrainerCardData:
	if inst == null:
		return null
	for tool in inst.attached_tools:
		var tcard: TrainerCardData = tool as TrainerCardData
		if tcard == null:
			continue
		if tcard.effect_key == _BALLOON_BERRY_KEY:
			return tcard
	return null


## Runs between-turn Tool effects for [inst] in [slot_id].  Called from
## ManagerSystem._cleanup_instance_async after condition damage has applied.
##
## Currently handles:
##   tool_clear_conditions_on_attach  — Lum Berry: if any special condition is
##                                       on this Pokémon, clear all conditions
##                                       and discard the tool.
##   tool_heal_on_damage              — Oran Berry: if at least 2 damage
##                                       counters (20 HP missing), heal 20 and
##                                       discard the tool.
##
## Buffer Piece auto-discard fires here too: Buffer Piece discards at the end
## of the opponent's turn after the Tool was attached (see
## PokemonInstance.tool_attached_turn).
static func run_between_turn_effects(inst: PokemonInstance, slot_id: String,
		manager) -> void:
	if inst == null or inst.attached_tools.is_empty():
		return
	var pname: String = inst.card.display_name if inst.card != null else "Pokemon"
	## Iterate a copy because we may discard tools mid-loop.
	for tool in inst.attached_tools.duplicate():
		var tcard: TrainerCardData = tool as TrainerCardData
		if tcard == null:
			continue
		match tcard.effect_key:
			_LUM_BERRY_KEY:
				if not inst.special_conditions.is_empty():
					inst.special_conditions.clear()
					_discard_tool_from_instance(inst, tcard, manager)
					inst.refresh_visual()
					manager.pokemon_state_changed.emit(slot_id, inst)
					manager.log_message.emit(
						"[Tool] %s cleared all conditions from %s." % [tcard.display_name, pname]
					)
			_ORAN_BERRY_KEY:
				var missing: int = inst.max_hp - inst.current_hp
				if missing >= 20:
					inst.heal(20)
					_discard_tool_from_instance(inst, tcard, manager)
					manager.pokemon_state_changed.emit(slot_id, inst)
					manager.log_message.emit(
						"[Tool] %s healed 20 HP from %s." % [tcard.display_name, pname]
					)
			_BUFFER_PIECE_KEY:
				## Discard at end of the opponent's first turn after attach.
				## tool_attached_turn[tcard] is the manager.turn_number at attach
				## time. Owner is the controller of [inst].  The first turn after
				## attach that ends with the opponent as the finishing player is
				## when we discard.
				var attached_turn: int = int(inst.tool_attached_turn.get(tcard, -1))
				if attached_turn >= 0 and manager.turn_number > attached_turn \
						and manager.current_player != inst.owner_id:
					_discard_tool_from_instance(inst, tcard, manager)
					manager.pokemon_state_changed.emit(slot_id, inst)
					manager.log_message.emit(
						"[Tool] %s discarded from %s." % [tcard.display_name, pname]
					)


## Detaches [tool] from [inst] and routes it to [inst.owner_id]'s discard.
## Refreshes the visual so the tool-attachment bubble icon disappears
## together with the tool — Oran Berry and Buffer Piece auto-discards
## previously bypassed this and left a stale bubble on the Pokémon.
static func _discard_tool_from_instance(inst: PokemonInstance,
		tool: TrainerCardData, manager) -> void:
	inst.attached_tools.erase(tool)
	inst.tool_attached_turn.erase(tool)
	manager.game_position.put_in_discard(inst.owner_id, tool)
	inst.refresh_visual()
