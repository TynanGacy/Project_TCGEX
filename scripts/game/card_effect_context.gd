class_name CardEffectContext
extends RefCounted
## Immutable-ish bag of data passed to every card effect function.
##
## Attack effects may also mutate the damage modifier fields before damage
## is calculated and applied:
##   damage_bonus    — added to base_damage; set by pre-damage hooks.
##   damage_override — when >= 0 replaces (base_damage + damage_bonus)
##                     entirely, BEFORE weakness / resistance are applied.
##
## After damage is applied, action_attack.gd writes damage_dealt so that
## post-damage hooks know how much was actually done.

var state: GameState
var actor_id: int

## The card being played (Trainer) or the attacking Pokémon (for attacks).
var card: CardInstance

## Attack-specific fields — null/zero for Trainer contexts.
var attacker: CardInstance
var defender: CardInstance
var attack: AttackData
var attack_index: int = 0

## Pre-damage modifiers (set inside dispatch_attack_pre handlers).
var damage_bonus: int = 0
var damage_override: int = -1   # -1 means "use base_damage + damage_bonus"

## Populated after damage is written to the defender.
var damage_dealt: int = 0


## Factory: create a context for a Trainer card effect.
static func for_trainer(
		s: GameState, pid: int, c: CardInstance
) -> CardEffectContext:
	var ctx := CardEffectContext.new()
	ctx.state    = s
	ctx.actor_id = pid
	ctx.card     = c
	return ctx


## Factory: create a context for an attack effect.
static func for_attack(
		s: GameState, pid: int,
		atk: CardInstance, def: CardInstance,
		attack_data: AttackData, atk_idx: int
) -> CardEffectContext:
	var ctx := CardEffectContext.new()
	ctx.state        = s
	ctx.actor_id     = pid
	ctx.card         = atk
	ctx.attacker     = atk
	ctx.defender     = def
	ctx.attack       = attack_data
	ctx.attack_index = atk_idx
	return ctx
