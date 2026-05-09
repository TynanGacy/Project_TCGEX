class_name GamePosition
extends RefCounted
## Tracks every card that is NOT currently in play.
##
## Four lists per player:
##   - deck    (ordered; back() is the "top" draw position)
##   - hand
##   - discard
##   - prizes  (up to 6 individually addressable slots)
##
## Unlike PokemonInstance-backed in-play cards, these are plain CardData
## references — no HP, no attachments, no conditions.
##
## This system only tracks containment.  It does NOT:
##   - check whether a move is legal
##   - own visuals (the scene layer renders hand/deck/discard itself)
##
## Callers (Manager) move cards between lists, or between a list and a
## PokemonInstance, without asking permission.

const MAX_PRIZES := 6

signal deck_changed(player_id: int)
signal hand_changed(player_id: int)
## Fired immediately after a card is removed from a player's hand so listeners
## can target the exact departing card without diffing the full hand array.
signal card_left_hand(player_id: int, card: CardData)
signal discard_changed(player_id: int)
signal prizes_changed(player_id: int)

## Per-player lists.  Index 0 = player 0, index 1 = player 1.
var decks:    Array = [[] as Array[CardData], [] as Array[CardData]]
var hands:    Array = [[] as Array[CardData], [] as Array[CardData]]
var discards: Array = [[] as Array[CardData], [] as Array[CardData]]

## Prizes are stored as Array[CardData] with exactly MAX_PRIZES entries.
## An empty prize slot holds null.  Each slot is individually addressable.
var prizes:   Array = [
	[null, null, null, null, null, null],
	[null, null, null, null, null, null],
]


## --- Deck setup -------------------------------------------------------------

func load_deck(player_id: int, cards: Array[CardData]) -> void:
	var deck: Array[CardData] = []
	deck.assign(cards)
	decks[player_id] = deck
	deck_changed.emit(player_id)


func shuffle_deck(player_id: int) -> void:
	var deck: Array = decks[player_id]
	for i in range(deck.size() - 1, 0, -1):
		var j := randi() % (i + 1)
		var tmp: Variant = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	deck_changed.emit(player_id)


## --- Queries ----------------------------------------------------------------

func deck_size(player_id: int) -> int:    return (decks[player_id] as Array).size()
func hand_size(player_id: int) -> int:    return (hands[player_id] as Array).size()
func discard_size(player_id: int) -> int: return (discards[player_id] as Array).size()


func prizes_remaining(player_id: int) -> int:
	var count := 0
	for c in prizes[player_id]:
		if c != null:
			count += 1
	return count


## --- Deck / hand moves ------------------------------------------------------

## Pops the top card of the deck (back of the array) and places it into the
## player's hand.  Returns the drawn card, or null if the deck is empty.
func draw(player_id: int) -> CardData:
	var deck: Array = decks[player_id]
	if deck.is_empty():
		return null
	var card: CardData = deck.pop_back()
	(hands[player_id] as Array).append(card)
	deck_changed.emit(player_id)
	hand_changed.emit(player_id)
	return card


## Deals [count] cards from deck top to the player's prize row, filling the
## first [count] empty prize slots in order.
func deal_prizes(player_id: int, count: int) -> void:
	count = clampi(count, 0, MAX_PRIZES)
	for i in range(MAX_PRIZES):
		if count <= 0:
			break
		if prizes[player_id][i] != null:
			continue
		var deck: Array = decks[player_id]
		if deck.is_empty():
			break
		prizes[player_id][i] = deck.pop_back() as CardData
		count -= 1
	deck_changed.emit(player_id)
	prizes_changed.emit(player_id)


## Removes [card] from the player's deck (first occurrence).  Returns true
## on success.  Used by trainer-card searches (Pokéball, Energy Search, etc.).
func take_from_deck(player_id: int, card: CardData) -> bool:
	var deck: Array = decks[player_id]
	var idx := deck.find(card)
	if idx < 0:
		return false
	deck.remove_at(idx)
	deck_changed.emit(player_id)
	return true


## Removes [card] from the player's discard (first occurrence).  Returns
## true on success.  Used by Energy Restore / Energy Recycle System.
func take_from_discard(player_id: int, card: CardData) -> bool:
	var pile: Array = discards[player_id]
	var idx := pile.find(card)
	if idx < 0:
		return false
	pile.remove_at(idx)
	discard_changed.emit(player_id)
	return true


## Appends [card] onto the bottom of the player's deck (front of array;
## the top is the back).  Used by Energy Recycle "shuffle into deck".
func put_in_deck(player_id: int, card: CardData) -> void:
	(decks[player_id] as Array).push_front(card)
	deck_changed.emit(player_id)


## Removes [card] from the player's hand (if present).  Returns true on
## success.  Used by the Manager when a card moves from hand to a
## PokemonInstance or to the discard pile.
func take_from_hand(player_id: int, card: CardData) -> bool:
	var hand: Array = hands[player_id]
	var idx := hand.find(card)
	if idx < 0:
		return false
	hand.remove_at(idx)
	card_left_hand.emit(player_id, card)
	hand_changed.emit(player_id)
	return true


func put_in_hand(player_id: int, card: CardData) -> void:
	(hands[player_id] as Array).append(card)
	hand_changed.emit(player_id)


func put_in_discard(player_id: int, card: CardData) -> void:
	(discards[player_id] as Array).append(card)
	discard_changed.emit(player_id)


## Takes a specific prize card by slot index (0..5).  Returns the card, or
## null if the slot is empty.
func take_prize(player_id: int, slot_index: int) -> CardData:
	if slot_index < 0 or slot_index >= MAX_PRIZES:
		return null
	var card: CardData = prizes[player_id][slot_index]
	prizes[player_id][slot_index] = null
	if card != null:
		prizes_changed.emit(player_id)
	return card


## Discards every card in [cards] for [player_id].  Used when a
## PokemonInstance is released after KO.
func discard_all(player_id: int, cards: Array[CardData]) -> void:
	var discard: Array = discards[player_id]
	for c in cards:
		if c != null:
			discard.append(c)
	discard_changed.emit(player_id)


## --- Setup helpers -----------------------------------------------------------

## Returns true if [player_id]'s hand contains at least one Basic Pokémon.
func has_basic_pokemon(player_id: int) -> bool:
	for card in (hands[player_id] as Array):
		if card is PokemonCardData and (card as PokemonCardData).stage == PokemonCardData.Stage.BASIC:
			return true
	return false


## Returns every card in [player_id]'s hand to the deck, then shuffles.
## Fires card_left_hand for each departing card so the scene layer can remove
## individual card visuals, then fires hand_changed once to signal completion.
func return_hand_to_deck(player_id: int) -> void:
	var hand: Array = hands[player_id]
	var deck: Array = decks[player_id]
	var snapshot: Array = hand.duplicate()
	for card in snapshot:
		hand.erase(card)
		card_left_hand.emit(player_id, card)
		deck.append(card)
	shuffle_deck(player_id)
	hand_changed.emit(player_id)
