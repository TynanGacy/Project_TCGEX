class_name StadiumEffects
## Static helpers that read passive effects from the currently-active Stadium.
##
## Stadiums are persistent, board-wide trainers; their effects don't dispatch
## per-action like Items / Supporters.  Instead, code paths that care about
## those effects (e.g. ActionRetreat) call into this helper to ask the
## currently active stadium for a modifier.
##
## The helper inspects manager.active_stadium.effect_key + effect_params,
## so authoring a new stadium is "add JSON params + (maybe) extend this file."

## Returns the Colorless retreat discount that the active stadium grants to
## [pokemon].  Returns 0 if no stadium is in play, the stadium does not
## affect retreat costs, or the Pokémon's type is not on the stadium's list.
##
## Stadium params shape:
##   {"retreat_discount": {"types": ["FIRE","WATER"], "amount": 1}}
static func retreat_discount_for(pokemon: PokemonCardData, manager) -> int:
	if pokemon == null or manager == null or manager.active_stadium == null:
		return 0
	var stadium: TrainerCardData = manager.active_stadium
	if stadium.effect_params == null or not stadium.effect_params.has("retreat_discount"):
		return 0
	var spec: Dictionary = stadium.effect_params["retreat_discount"]
	var types: Array = spec.get("types", [])
	var amount: int = int(spec.get("amount", 0))
	if amount <= 0:
		return 0
	var ptype_name: String = PokemonCardData.EnergyType.keys()[pokemon.pokemon_type]
	for t in types:
		if str(t) == ptype_name:
			return amount
	return 0


## Returns the flat HP bonus the active stadium grants to [pokemon].  Returns 0
## if no stadium is in play, the stadium does not grant an HP aura, or the
## Pokémon's type is not on the stadium's list.
##
## Stadium params shape:
##   {"hp_bonus": {"types": ["GRASS","LIGHTNING"], "amount": 10}}
static func hp_bonus_for(pokemon: PokemonCardData, stadium: TrainerCardData) -> int:
	if pokemon == null or stadium == null:
		return 0
	if stadium.effect_params == null or not stadium.effect_params.has("hp_bonus"):
		return 0
	var spec: Dictionary = stadium.effect_params["hp_bonus"]
	var types: Array = spec.get("types", [])
	var amount: int = int(spec.get("amount", 0))
	if amount <= 0:
		return 0
	var ptype_name: String = PokemonCardData.EnergyType.keys()[pokemon.pokemon_type]
	for t in types:
		if str(t) == ptype_name:
			return amount
	return 0


## Updates [inst]'s aura HP bonus to match the active stadium.  Adjusts
## max_hp and current_hp by the delta and emits pokemon_state_changed.
##
## Called when a Pokémon enters play, when it evolves, and indirectly by
## reconcile_all_auras when a Stadium is played.
static func reconcile_aura_for(slot_id: String, inst: PokemonInstance,
		manager) -> void:
	if inst == null or inst.card == null:
		return
	var desired: int = hp_bonus_for(inst.card, manager.active_stadium)
	var current: int = inst.aura_hp_bonus
	if desired == current:
		return
	var delta: int = desired - current
	inst.aura_hp_bonus = desired
	inst.max_hp += delta
	if delta > 0:
		## Buff: raise current_hp to keep "damage taken" consistent (max bumps up
		## but the Pokémon doesn't suddenly read as more wounded).
		inst.current_hp = mini(inst.max_hp, inst.current_hp + delta)
	else:
		## Buff revoked: never raise current above the new max.
		inst.current_hp = mini(inst.max_hp, inst.current_hp)
	inst.refresh_visual()
	if manager.has_signal("pokemon_state_changed"):
		manager.pokemon_state_changed.emit(slot_id, inst)


## Walks every in-play Pokémon on both sides and reconciles its aura against
## the active stadium.  Called from ActionPlayStadium after the stadium swap.
static func reconcile_all_auras(manager) -> void:
	if manager == null or manager.board_position == null:
		return
	for pid in range(2):
		for sid in BoardPosition.all_slot_ids(pid):
			var inst: PokemonInstance = manager.board_position.get_instance(sid)
			if inst != null:
				reconcile_aura_for(sid, inst, manager)
