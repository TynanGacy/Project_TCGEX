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
