class_name ActionPlayFossil
extends GameAction
## Plays a Fossil Trainer card (Claw / Mysterious / Root Fossil) as if it were
## a Basic Pokémon.  The card goes from hand → target bench slot, where it is
## represented by a synthetic PokemonInstance whose `card` field is a
## runtime-built PokemonCardData (40 HP, Colorless, no attacks, retreat-locked)
## and whose `source_trainer_card` is the original Trainer card.
##
## When the Fossil is knocked out or otherwise leaves play, the original
## Trainer card is what is routed back to the discard pile (see
## PokemonInstance.all_cards / release_cards).

var player_id: int = 0
var card: TrainerCardData = null
var target_slot: String = ""


func _init(pid: int, fossil_card: TrainerCardData, slot_id: String) -> void:
	player_id   = pid
	card        = fossil_card
	target_slot = slot_id


func validate(manager) -> ActionResult:
	if card == null:
		return ActionResult.fail("No fossil card specified.")
	if not card.plays_as_pokemon:
		return ActionResult.fail("Card is not a Fossil (plays_as_pokemon == false).")
	if manager.game_position == null or manager.board_position == null:
		return ActionResult.fail("Manager is not initialised.")
	if not manager.is_main_phase_for(player_id):
		return ActionResult.fail("Not your main phase.")
	if not (manager.game_position.hands[player_id] as Array).has(card):
		return ActionResult.fail("Fossil is not in your hand.")
	if not manager.board_position.has_slot(target_slot):
		return ActionResult.fail("Unknown slot '%s'." % target_slot)
	if not manager.is_valid_slot(target_slot):
		return ActionResult.fail("Slot '%s' is not in use this game." % target_slot)
	if manager.board_position.player_of(target_slot) != player_id:
		return ActionResult.fail("Slot does not belong to you.")
	if not manager.board_position.is_empty(target_slot):
		return ActionResult.fail("Slot '%s' is occupied." % target_slot)
	## Fossils may only be placed on the bench.
	if "active" in target_slot:
		return ActionResult.fail("Fossils may only be played to a bench slot.")
	return ActionResult.success()


func apply(manager) -> void:
	manager.game_position.take_from_hand(player_id, card)
	var synthetic := _build_synthetic_pokemon(card)
	var inst := PokemonInstance.create(synthetic, player_id)
	inst.source_trainer_card = card
	manager.board_position.place(target_slot, inst)
	StadiumEffects.reconcile_aura_for(target_slot, inst, manager)
	manager.pokemon_entered_play_this_turn[player_id].append(inst)
	manager.log_message.emit(
		"[Fossil] %s played to %s." % [card.display_name, target_slot]
	)


func description() -> String:
	var name := card.display_name if card != null else "Fossil"
	return "P%d plays fossil %s to %s" % [player_id, name, target_slot]


func affected_slots() -> Array[String]:
	return [target_slot]


## Builds the runtime PokemonCardData that represents the fossil while it is
## on the board.  Reads display_name and hp from card.effect_params["as_pokemon"];
## type is locked to COLORLESS, stage to BASIC, and retreat_cost to a sentinel
## that ActionRetreat will reject.
static func _build_synthetic_pokemon(fossil: TrainerCardData) -> PokemonCardData:
	var spec: Dictionary = fossil.effect_params.get("as_pokemon", {}) as Dictionary
	var p := PokemonCardData.new()
	p.card_id      = fossil.card_id
	p.display_name = str(spec.get("display_name", fossil.display_name))
	p.card_type    = CardData.CardType.POKEMON
	p.stage        = PokemonCardData.Stage.BASIC
	p.name_slug    = fossil.card_id.to_lower()
	p.evolves_from = ""
	p.pokemon_type = PokemonCardData.EnergyType.COLORLESS
	p.hp_max       = int(spec.get("hp", 40))
	p.weakness     = PokemonCardData.EnergyType.NONE
	p.resistance   = PokemonCardData.EnergyType.NONE
	## Sentinel retreat cost.  ActionRetreat rejects fossils explicitly anyway,
	## but a huge cost also keeps any speculative retreat-cost calculations safe.
	p.retreat_cost = 99
	p.rules_text   = fossil.rules_text
	p.attacks      = []
	return p
