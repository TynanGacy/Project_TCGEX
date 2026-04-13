class_name CardEffectRegistry
## Central registry mapping card IDs (and attack indices) to effect Callables.
##
## SETUP
##   Call CardEffectRegistry.setup() once at startup after loading the
##   CardLibrary.  Pass the library so AttackEffects can auto-register
##   pattern-based handlers for all loaded cards:
##
##     CardEffectRegistry.setup(my_library)
##
## REGISTRATION (done inside TrainerEffects / AttackEffects)
##   CardEffectRegistry.register_item("RS_91_potion", _potion_fn)
##   CardEffectRegistry.register_attack_pre("DR_1_absol", 1, _prize_count_pre)
##   CardEffectRegistry.register_attack_post("DR_100_charizard", 0, _collect_fire)
##
## DISPATCH (called by action classes)
##   CardEffectRegistry.dispatch_item(ctx)
##   CardEffectRegistry.dispatch_attack_pre(ctx)
##   CardEffectRegistry.dispatch_attack_post(ctx)
##
## CALLABLE SIGNATURES
##   Trainer item/supporter/stadium :  func(ctx: CardEffectContext) -> void
##   Tool between-turns trigger     :  func(tool: CardInstance,
##                                          holder: CardInstance,
##                                          state: GameState) -> void
##   Attack pre-damage              :  func(ctx: CardEffectContext) -> void
##   Attack post-damage             :  func(ctx: CardEffectContext) -> void


## Trainer effects keyed by card_id.
static var _item_effects: Dictionary = {}
static var _supporter_effects: Dictionary = {}
static var _stadium_effects: Dictionary = {}

## Tool effects triggered between turns: card_id → Callable.
static var _tool_between_turns: Dictionary = {}

## Attack effects keyed by "card_id:attack_index".
static var _attack_pre: Dictionary = {}
static var _attack_post: Dictionary = {}

## Prevents double-initialisation.
static var _initialized: bool = false


## ---------------------------------------------------------------------------
## Setup
## ---------------------------------------------------------------------------

## Registers all built-in effects.  Pass the CardLibrary so AttackEffects can
## iterate all loaded cards for pattern-based auto-registration.
static func setup(library: CardLibrary = null) -> void:
	if _initialized:
		return
	_initialized = true
	TrainerEffects.register_all()
	AttackEffects.register_all(library)


## ---------------------------------------------------------------------------
## Registration helpers
## ---------------------------------------------------------------------------

static func register_item(card_id: String, fn: Callable) -> void:
	_item_effects[card_id] = fn

static func register_supporter(card_id: String, fn: Callable) -> void:
	_supporter_effects[card_id] = fn

static func register_stadium(card_id: String, fn: Callable) -> void:
	_stadium_effects[card_id] = fn

static func register_tool_between_turns(card_id: String, fn: Callable) -> void:
	_tool_between_turns[card_id] = fn

static func register_attack_pre(card_id: String, atk_idx: int, fn: Callable) -> void:
	_attack_pre["%s:%d" % [card_id, atk_idx]] = fn

static func register_attack_post(card_id: String, atk_idx: int, fn: Callable) -> void:
	_attack_post["%s:%d" % [card_id, atk_idx]] = fn


## ---------------------------------------------------------------------------
## Dispatch helpers
## ---------------------------------------------------------------------------

static func dispatch_item(ctx: CardEffectContext) -> void:
	if ctx.card == null:
		return
	var fn: Callable = _item_effects.get(ctx.card.data.card_id, Callable())
	if fn.is_valid():
		fn.call(ctx)

static func dispatch_supporter(ctx: CardEffectContext) -> void:
	if ctx.card == null:
		return
	var fn: Callable = _supporter_effects.get(ctx.card.data.card_id, Callable())
	if fn.is_valid():
		fn.call(ctx)

static func dispatch_stadium(ctx: CardEffectContext) -> void:
	if ctx.card == null:
		return
	var fn: Callable = _stadium_effects.get(ctx.card.data.card_id, Callable())
	if fn.is_valid():
		fn.call(ctx)

## Runs the between-turns trigger for a tool attached to a Pokémon.
static func dispatch_tool_between_turns(
		tool: CardInstance,
		holder: CardInstance,
		state: GameState
) -> void:
	if tool == null or not (tool.data is TrainerCardData):
		return
	var fn: Callable = _tool_between_turns.get(tool.data.card_id, Callable())
	if fn.is_valid():
		fn.call(tool, holder, state)

## Pre-damage hook: may set ctx.damage_bonus or ctx.damage_override.
static func dispatch_attack_pre(ctx: CardEffectContext) -> void:
	if ctx.attacker == null:
		return
	var key := "%s:%d" % [ctx.attacker.data.card_id, ctx.attack_index]
	var fn: Callable = _attack_pre.get(key, Callable())
	if fn.is_valid():
		fn.call(ctx)

## Post-damage hook: runs after damage has been applied to the defender.
static func dispatch_attack_post(ctx: CardEffectContext) -> void:
	if ctx.attacker == null:
		return
	var key := "%s:%d" % [ctx.attacker.data.card_id, ctx.attack_index]
	var fn: Callable = _attack_post.get(key, Callable())
	if fn.is_valid():
		fn.call(ctx)
