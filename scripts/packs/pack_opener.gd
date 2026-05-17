class_name PackOpener
extends RefCounted
## Rolls the contents of a pack: for each slot, choose a rarity tier by weight,
## then pick a uniformly-random card of that rarity inside the pack's set.
## RNG is injectable so tests can pin the seed.
##
## Pack constraints enforced during rolling:
##   1. Basic energies are never included — they're the only candidates
##      filtered out wholesale, since they're handed out by other means
##      (deckbuilder copy-limit exemption, etc.). Special energies like
##      Darkness/Metal are kept in the pool.
##   2. No duplicate card_ids within a single pack.
##   3. At most one trainer AND at most one energy per pack — caps are
##      independent, so a single pack can contain both a trainer and an
##      energy alongside Pokémon. Once a trainer lands, later slots can't
##      roll another trainer (but an energy is still allowed); same for
##      energy. The remaining slots are Pokémon.

static func roll(pack: PackDefinition, rng: RandomNumberGenerator = null) -> Array[String]:
	var out: Array[String] = []
	if pack == null:
		return out
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	## Index the set's cards by rarity once per roll. Basic energies are
	## excluded up front so no fallback path can accidentally select them.
	var set_cards: Array = (CardDatabase.cards_by_set() as Dictionary).get(pack.set_code, [])
	if set_cards.is_empty():
		push_warning("PackOpener: no cards loaded for set %s" % pack.set_code)
		return out
	var by_rarity: Dictionary = {}  ## rarity -> Array[CardData]
	for c in set_cards:
		var card: CardData = c
		if DeckValidator.is_basic_energy(card):
			continue
		for r in card.rarities:
			var key: String = str(r)
			if not by_rarity.has(key):
				by_rarity[key] = []
			(by_rarity[key] as Array).append(card)

	var seen_ids: Dictionary = {}  ## card_id -> true, for dup protection
	var trainer_used: bool = false
	var energy_used: bool = false

	for slot in pack.slots:
		var sd: Dictionary = slot
		var count: int = int(sd.get("count", 1))
		var pool: Array = sd.get("rarity_pool", [])
		var weights: Array = sd.get("weights", [])
		for _i in count:
			var rarity := _pick_rarity(pool, weights, rng)
			var candidates: Array = _filter(by_rarity.get(rarity, []),
				seen_ids, trainer_used, energy_used)
			if candidates.is_empty():
				## Rarity tier had nothing eligible — walk the rest of the pool
				## (still honoring dup / type-cap filters) before giving up.
				candidates = _fallback_candidates(pool, by_rarity,
					seen_ids, trainer_used, energy_used)
			if candidates.is_empty():
				push_warning("PackOpener: no candidates for slot in %s" % pack.pack_id)
				continue
			var pick: CardData = candidates[rng.randi_range(0, candidates.size() - 1)]
			out.append(pick.card_id)
			seen_ids[pick.card_id] = true
			if pick.card_type == CardData.CardType.TRAINER:
				trainer_used = true
			elif pick.card_type == CardData.CardType.ENERGY:
				energy_used = true
	return out


static func _filter(candidates: Array, seen_ids: Dictionary,
		trainer_used: bool, energy_used: bool) -> Array:
	var out: Array = []
	for c in candidates:
		var card: CardData = c
		if seen_ids.has(card.card_id):
			continue
		if trainer_used and card.card_type == CardData.CardType.TRAINER:
			continue
		if energy_used and card.card_type == CardData.CardType.ENERGY:
			continue
		out.append(card)
	return out


static func _pick_rarity(pool: Array, weights: Array, rng: RandomNumberGenerator) -> String:
	if pool.is_empty():
		return ""
	if weights.size() != pool.size() or weights.is_empty():
		return str(pool[rng.randi_range(0, pool.size() - 1)])
	var total: int = 0
	for w in weights:
		total += max(0, int(w))
	if total <= 0:
		return str(pool[rng.randi_range(0, pool.size() - 1)])
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for i in pool.size():
		acc += max(0, int(weights[i]))
		if roll <= acc:
			return str(pool[i])
	return str(pool[pool.size() - 1])


static func _fallback_candidates(pool: Array, by_rarity: Dictionary,
		seen_ids: Dictionary, trainer_used: bool, energy_used: bool) -> Array:
	for r in pool:
		var filtered := _filter(by_rarity.get(str(r), []), seen_ids,
			trainer_used, energy_used)
		if not filtered.is_empty():
			return filtered
	return []
