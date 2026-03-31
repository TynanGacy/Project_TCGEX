class_name ActionAttachEnergy
extends GameAction

## Attaches one Energy card from hand to a Pokemon in play.
## Only one energy attachment is allowed per turn.

var card: CardInstance
var target: CardInstance


func _init(pid: int, energy_card: CardInstance, target_pokemon: CardInstance) -> void:
	actor_id = pid
	card = energy_card
	target = target_pokemon


func validate(state: GameState) -> ActionResult:
	if state.phase != TurnPhase.Phase.MAIN:
		return ActionResult.fail("Can only attach energy during MAIN phase.")

	if card == null or target == null:
		return ActionResult.fail("Invalid card or target.")

	if not (card.data is EnergyCardData):
		return ActionResult.fail("Card is not an Energy card.")

	var hand_zone := "p%d_hand" % actor_id
	if state.board.find_card_location(card) != hand_zone:
		return ActionResult.fail("Energy card is not in your hand.")

	if not (target.data is PokemonCardData):
		return ActionResult.fail("Target is not a Pokemon.")

	if not _target_is_in_play(state):
		return ActionResult.fail("Target Pokemon is not in play.")

	var player := state.get_player(actor_id)
	if not player.can_attach_energy():
		return ActionResult.fail("Already attached an energy this turn.")

	return ActionResult.success()


func apply(state: GameState) -> void:
	# Remove from hand without placing in any zone (energy lives on the Pokemon).
	state.board.remove_card(card)
	card.zone = CardInstance.Zone.OTHER

	target.attach_energy(card)
	state.get_player(actor_id).mark_energy_attached()


func description() -> String:
	if card != null and target != null and card.data != null and target.data != null:
		return "Attach %s to %s" % [card.data.display_name, target.data.display_name]
	return "Attach Energy"


func _target_is_in_play(state: GameState) -> bool:
	var target_zone := state.board.find_card_location(target)
	for slot_idx in range(state.board.num_active_slots):
		if target_zone == "p%d_active_%d" % [actor_id, slot_idx]:
			return true
	if target_zone == "p%d_bench" % actor_id:
		return true
	return false
