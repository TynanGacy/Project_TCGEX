class_name AttackEffects
## Registers all Pokémon attack effects with CardEffectRegistry.
##
## TWO REGISTRATION PATHS
## ──────────────────────
## 1. Auto-detection (register_all receives the CardLibrary):
##    For every loaded card, each attack's text is inspected for known patterns
##    (coin-flip damage, condition application, bench damage, etc.).  If a
##    pattern matches, the corresponding generic handler is registered.
##
## 2. Specific overrides (at the bottom of register_all):
##    Complex attacks that don't fit a single pattern get a hand-written handler
##    registered by card_id + attack_index.  These always take priority because
##    they're registered AFTER the auto-detection loop.
##
## HANDLER SIGNATURES
## ──────────────────
##   pre-damage  :  func(ctx: CardEffectContext) -> void
##                  May set ctx.damage_bonus or ctx.damage_override.
##   post-damage :  func(ctx: CardEffectContext) -> void
##                  Runs after damage is written to defender; ctx.damage_dealt
##                  holds the final amount.

# ---------------------------------------------------------------------------
# Registration entry-point
# ---------------------------------------------------------------------------

static func register_all(library: CardLibrary = null) -> void:
	# Auto-detect common patterns for every loaded card.
	if library != null:
		for card_data in library.all_cards():
			if not (card_data is PokemonCardData):
				continue
			var pdata := card_data as PokemonCardData
			for i in pdata.attacks.size():
				_auto_register(pdata.card_id, i, pdata.attacks[i])

	# ---- Specific handlers (override auto-detection) ----------------------
	# DR_1 Absol
	CardEffectRegistry.register_attack_pre( "DR_1_absol", 0, _absol_bad_news_pre)
	CardEffectRegistry.register_attack_pre( "DR_1_absol", 1, _absol_prize_count_pre)

	# DR_100 Charizard
	CardEffectRegistry.register_attack_post("DR_100_charizard", 0, _charizard_collect_fire)
	CardEffectRegistry.register_attack_post("DR_100_charizard", 1, _charizard_flame_pillar)

	# RS_11 Sceptile (Lizard Poison — energy-count conditions)
	CardEffectRegistry.register_attack_post("RS_11_sceptile", 0, _sceptile_lizard_poison)

	# DR_27 Flaaffy (Energy Recall)
	CardEffectRegistry.register_attack_post("DR_27_flaaffy", 0, _flaaffy_energy_recall)

	# DR_15 Flygon (Air Slash — coin-or-discard)
	CardEffectRegistry.register_attack_post("DR_15_flygon", 0, _flygon_air_slash)

	# RS_103 Sneasel-ex (Beat Up — flip per Pokémon in play)
	CardEffectRegistry.register_attack_pre( "RS_103_sneasel_ex", 1, _sneasel_beat_up_pre)

	# RS_16 Breloom (Battle Blast — +10 per Fighting Energy)
	CardEffectRegistry.register_attack_pre( "RS_16_breloom", 1, _breloom_battle_blast_pre)

	# DR_7 Minun (Cheer On — heal all own Pokémon)
	CardEffectRegistry.register_attack_post("DR_7_minun", 0, _minun_cheer_on)

	# DR_7 Minun (Special Circuit — 20 / 40 to any Pokémon)
	CardEffectRegistry.register_attack_post("DR_7_minun", 1, _minun_special_circuit)

	# Generic "self-damage equal to damage dealt" (Nincada, Pelipper, etc.)
	_register_self_heal_after_attack("DR_11_shedinja",  0)
	_register_self_heal_after_attack("RS_19_pelipper",  1)


# ---------------------------------------------------------------------------
# Auto-detection helpers
# ---------------------------------------------------------------------------

# Returns the integer value after the first occurrence of a digit sequence
# at the very start of the text, or -1 if not found.
static func _extract_leading_int(t: String) -> int:
	var r := RegEx.new()
	r.compile("^\\D*(\\d+)")
	var m := r.search(t)
	if m == null:
		return -1
	return int(m.get_string(1))


# Parses "Flip N coins" or "Flip a coin" → number of flips (1 if "a coin").
static func _parse_flip_count(text: String) -> int:
	var tl := text.to_lower()
	if "flip a coin" in tl:
		return 1
	var r := RegEx.new()
	r.compile("flip (\\d+) coins?")
	var m := r.search(tl)
	if m != null:
		return int(m.get_string(1))
	return 0


# Returns (base, per_head, flips) for "Flip N coins. This attack does X damage
# times the number of heads" / "plus Y more for each heads" patterns.
# Returns (-1,-1,0) when not matched.
static func _parse_flip_damage(text: String) -> Array:
	var tl := text.to_lower()
	var flips := _parse_flip_count(tl)
	if flips == 0:
		return [-1, -1, 0]

	# "X damage times the number of heads"
	var r1 := RegEx.new()
	r1.compile("does (\\d+) damage times the number of heads")
	var m1 := r1.search(tl)
	if m1 != null:
		return [0, int(m1.get_string(1)), flips]

	# "X damage plus Y more damage for each heads"
	var r2 := RegEx.new()
	r2.compile("plus (\\d+) more damage for each heads")
	var m2 := r2.search(tl)
	if m2 != null:
		return [-1, int(m2.get_string(1)), flips]  # base left to base_damage

	# "does 40 damage times the number of heads" already covered above; also
	# handle "flip a coin until you get tails"
	if "flip a coin until you get tails" in tl:
		var r3 := RegEx.new()
		r3.compile("(\\d+) damage times the number of heads")
		var m3 := r3.search(tl)
		if m3 != null:
			return [0, int(m3.get_string(1)), -1]  # -1 flips = flip-until-tails

	return [-1, -1, 0]


# Detects the condition name from text such as "now Poisoned", "now Asleep".
static func _parse_condition(text: String) -> CardInstance.SpecialCondition:
	var tl := text.to_lower()
	if "poisoned" in tl: return CardInstance.SpecialCondition.POISONED
	if "asleep"   in tl: return CardInstance.SpecialCondition.ASLEEP
	if "burned"   in tl: return CardInstance.SpecialCondition.BURNED
	if "paralyzed" in tl: return CardInstance.SpecialCondition.PARALYZED
	if "confused"  in tl: return CardInstance.SpecialCondition.CONFUSED
	return CardInstance.SpecialCondition.NONE


# Detects "+Y damage per damage counter on [self|defender]" and returns
# {bonus, target} where target is "self" or "defender".
static func _parse_per_damage_counter(text: String) -> Dictionary:
	var r := RegEx.new()
	r.compile("plus (\\d+) more damage for each damage counter on (\\w+)")
	var m := r.search(text.to_lower())
	if m == null:
		return {}
	var y := int(m.get_string(1))
	var who := m.get_string(2)
	var target := "defender" if who in ["the", "defending"] else "self"
	return {"bonus": y, "target": target}


# Detects "Does X damage to N of your opponent's Benched Pokémon".
# Returns {damage, count} or {} if not matched.
static func _parse_bench_damage(text: String) -> Dictionary:
	var tl := text.to_lower()
	if "benched" not in tl:
		return {}

	# "N of your opponent's Benched Pokémon"
	var r1 := RegEx.new()
	r1.compile("does (\\d+) damage to (\\d+|each) of your opponent.s bench")
	var m1 := r1.search(tl)
	if m1 != null:
		var dmg   := int(m1.get_string(1))
		var count := -1 if m1.get_string(2) == "each" else int(m1.get_string(2))
		return {"damage": dmg, "count": count}

	# "Does X damage to each Benched Pokémon (both)"
	var r2 := RegEx.new()
	r2.compile("does (\\d+) damage to each benched")
	var m2 := r2.search(tl)
	if m2 != null:
		return {"damage": int(m2.get_string(1)), "count": -1, "both": true}

	return {}


# Detects "+Y for each Energy attached to [pokemon] not used to pay"
static func _parse_excess_energy_bonus(text: String) -> Dictionary:
	var tl := text.to_lower()
	var r := RegEx.new()
	r.compile("plus (\\d+) more damage for each \\w+ energy attached.*not used to pay")
	var m := r.search(tl)
	if m != null:
		# Look for cap "You can't add more than X damage"
		var cap_r := RegEx.new()
		cap_r.compile("can.t add more than (\\d+) damage")
		var cap_m := cap_r.search(tl)
		var cap := -1
		if cap_m != null:
			cap = int(cap_m.get_string(1))
		return {"bonus_per": int(m.get_string(1)), "cap": cap}
	return {}


# Main auto-register function: inspects attack text and registers generic handlers.
static func _auto_register(card_id: String, atk_idx: int, attack: AttackData) -> void:
	var text := attack.text
	if text == "":
		return

	# --- Flip-based damage override ----------------------------------------
	var flip_info := _parse_flip_damage(text)
	if flip_info[2] != 0:  # matched
		var base:     int = flip_info[0]
		var per_head: int = flip_info[1]
		var flips:    int = flip_info[2]
		if flips == -1:
			# flip-until-tails variant
			CardEffectRegistry.register_attack_pre(card_id, atk_idx,
				func(ctx: CardEffectContext) -> void:
					var heads := 0
					while randi() % 2 == 1:
						heads += 1
					ctx.damage_override = per_head * heads)
		else:
			CardEffectRegistry.register_attack_pre(card_id, atk_idx,
				func(ctx: CardEffectContext) -> void:
					var heads := 0
					for _i in flips:
						if randi() % 2 == 1:
							heads += 1
					if base >= 0:
						ctx.damage_override = per_head * heads
					else:
						ctx.damage_bonus += per_head * heads)
		return  # flip damage replaces other patterns

	# --- Simple condition application --------------------------------------
	var tl := text.to_lower()
	var has_coin := "flip a coin" in tl and "if heads" in tl

	# "The Defending Pokémon is now X" / "Each Defending Pokémon is now X"
	if "defending pokémon is now" in tl or "defending pokemon is now" in tl:
		var cond := _parse_condition(text)
		if cond != CardInstance.SpecialCondition.NONE:
			if has_coin:
				CardEffectRegistry.register_attack_post(card_id, atk_idx,
					func(ctx: CardEffectContext) -> void:
						if randi() % 2 == 1 and ctx.defender != null:
							ctx.defender.add_condition(cond))
			else:
				CardEffectRegistry.register_attack_post(card_id, atk_idx,
					func(ctx: CardEffectContext) -> void:
						if ctx.defender != null:
							ctx.defender.add_condition(cond))

	# --- Per-damage-counter bonus ------------------------------------------
	var pdc := _parse_per_damage_counter(text)
	if not pdc.is_empty():
		var bonus: int   = pdc["bonus"]
		var target: String = pdc.get("target", "defender")
		CardEffectRegistry.register_attack_pre(card_id, atk_idx,
			func(ctx: CardEffectContext) -> void:
				var source := ctx.attacker if target == "self" else ctx.defender
				if source != null:
					ctx.damage_bonus += source.damage / 10 * bonus)

	# --- Excess-energy bonus -----------------------------------------------
	var eeb := _parse_excess_energy_bonus(text)
	if not eeb.is_empty():
		var bp: int  = eeb["bonus_per"]
		var cap: int = eeb["cap"]
		CardEffectRegistry.register_attack_pre(card_id, atk_idx,
			func(ctx: CardEffectContext) -> void:
				if ctx.attacker == null or ctx.attack == null:
					return
				var total   := AttackResolver.total_energy_count(ctx.attacker)
				var cost    := AttackResolver.total_cost(ctx.attack)
				var excess  := maxi(0, total - cost)
				var raw     := excess * bp
				ctx.damage_bonus += cap >= 0 ? mini(raw, cap) : raw)

	# --- Bench damage (post-attack) ----------------------------------------
	var bd := _parse_bench_damage(text)
	if not bd.is_empty():
		var bdmg:  int  = bd["damage"]
		var bcnt:  int  = bd["count"]    # -1 = all
		var bboth: bool = bd.get("both", false)
		CardEffectRegistry.register_attack_post(card_id, atk_idx,
			func(ctx: CardEffectContext) -> void:
				var opp_id := 1 - ctx.actor_id
				var targets := ctx.state.board.get_bench_cards(opp_id)
				if bboth:
					for b in ctx.state.board.get_bench_cards(ctx.actor_id):
						b.apply_damage(bdmg)
				var count := bcnt
				for b in targets:
					if count == 0:
						break
					b.apply_damage(bdmg)
					if count > 0:
						count -= 1)

	# --- Coin-flip: discard 1 energy from defender -----------------------
	if "flip a coin. if heads, discard 1 energy card attached to the defending" in tl:
		CardEffectRegistry.register_attack_post(card_id, atk_idx,
			func(ctx: CardEffectContext) -> void:
				if randi() % 2 == 0:
					return
				if ctx.defender == null or ctx.defender.attached_energy.is_empty():
					return
				var opp_id := 1 - ctx.actor_id
				var e := ctx.defender.attached_energy[0] as CardInstance
				ctx.defender.attached_energy.erase(e)
				ctx.state.board.move_card(e, "p%d_discard" % opp_id))

	# --- "Draw a card" ----------------------------------------------------
	if text.strip_edges().to_lower() == "draw a card.":
		CardEffectRegistry.register_attack_post(card_id, atk_idx,
			func(ctx: CardEffectContext) -> void:
				CardEffects.draw_cards(ctx.state, ctx.actor_id, 1))

	# --- "Attach a [Type] Energy card from your discard pile to [Self]" ---
	if "attach" in tl and "from your discard pile" in tl and "energy" in tl:
		# Only register a simple "1 energy from discard" variant here;
		# complex variants are handled by specific overrides.
		if not ("up to 2" in tl or "up to 3" in tl):
			CardEffectRegistry.register_attack_post(card_id, atk_idx,
				func(ctx: CardEffectContext) -> void:
					_attach_energy_from_discard(ctx.state, ctx.actor_id,
						ctx.attacker, 1, PokemonCardData.EnergyType.NONE))


# ---------------------------------------------------------------------------
# Generic helper invoked by auto-detected handlers
# ---------------------------------------------------------------------------

static func _attach_energy_from_discard(
		state: GameState,
		actor_id: int,
		target: CardInstance,
		count: int,
		etype: PokemonCardData.EnergyType
) -> void:
	var found := 0
	var discard := state.board.get_zone("p%d_discard" % actor_id).duplicate()
	for card in discard:
		if found >= count:
			break
		if not (card is CardInstance) or not (card as CardInstance).data is EnergyCardData:
			continue
		var edata := (card as CardInstance).data as EnergyCardData
		if etype != PokemonCardData.EnergyType.NONE and edata.energy_type != etype:
			continue
		# Move to "attached" state (same pattern as ActionAttachEnergy.apply).
		state.board.remove_card(card)
		(card as CardInstance).zone = CardInstance.Zone.OTHER
		target.attached_energy.append(card)
		found += 1


static func _register_self_heal_after_attack(card_id: String, atk_idx: int) -> void:
	CardEffectRegistry.register_attack_post(card_id, atk_idx,
		func(ctx: CardEffectContext) -> void:
			ctx.attacker.heal(ctx.damage_dealt))


# ---------------------------------------------------------------------------
# Specific attack handlers
# ---------------------------------------------------------------------------

# -- DR_1 Absol: Bad News (atk 0) -----------------------------------------
# "If opponent has ≥ 6 cards, discard until they have 5."
static func _absol_bad_news_pre(ctx: CardEffectContext) -> void:
	ctx.damage_override = 0  # Bad News deals 0 damage.
	var opp_id := 1 - ctx.actor_id
	var hand := ctx.state.board.get_hand_cards(opp_id)
	while hand.size() >= 6:
		ctx.state.board.move_card(hand[0], "p%d_discard" % opp_id)
		hand = ctx.state.board.get_hand_cards(opp_id)


# -- DR_1 Absol: Prize Count (atk 1) --------------------------------------
# "+20 if you have more Prize cards than your opponent."
static func _absol_prize_count_pre(ctx: CardEffectContext) -> void:
	var my_prizes  := ctx.state.board.get_zone("p%d_prizes" % ctx.actor_id).size()
	var opp_prizes := ctx.state.board.get_zone("p%d_prizes" % (1 - ctx.actor_id)).size()
	if my_prizes > opp_prizes:
		ctx.damage_bonus += 20


# -- DR_100 Charizard: Collect Fire (atk 0) --------------------------------
# "Flip a coin. If heads, attach 2 Fire Energy from discard to Charizard."
static func _charizard_collect_fire(ctx: CardEffectContext) -> void:
	if randi() % 2 == 0:  # tails
		return
	_attach_energy_from_discard(ctx.state, ctx.actor_id, ctx.attacker, 2,
		PokemonCardData.EnergyType.FIRE)


# -- DR_100 Charizard: Flame Pillar (atk 1) --------------------------------
# "You may discard 1 Fire Energy; if so, do 30 to a Bench Pokémon."
# Auto-select: always discard (more aggressive play) if Fire Energy available.
static func _charizard_flame_pillar(ctx: CardEffectContext) -> void:
	var fire_e: CardInstance = null
	for e in ctx.attacker.attached_energy:
		if (e.data is EnergyCardData) \
				and (e.data as EnergyCardData).energy_type == PokemonCardData.EnergyType.FIRE:
			fire_e = e
			break
	if fire_e == null:
		return
	# Discard the Fire Energy.
	ctx.attacker.attached_energy.erase(fire_e)
	ctx.state.board.move_card(fire_e, "p%d_discard" % ctx.actor_id)
	# Deal 30 to first opponent bench Pokémon.
	var bench := ctx.state.board.get_bench_cards(1 - ctx.actor_id)
	if not bench.is_empty():
		bench[0].apply_damage(30)


# -- RS_11 Sceptile: Lizard Poison (atk 0) ---------------------------------
# Conditions depend on total energy attached to Sceptile.
static func _sceptile_lizard_poison(ctx: CardEffectContext) -> void:
	if ctx.defender == null:
		return
	var total := AttackResolver.total_energy_count(ctx.attacker)
	match total:
		1:
			ctx.defender.add_condition(CardInstance.SpecialCondition.ASLEEP)
		2:
			ctx.defender.add_condition(CardInstance.SpecialCondition.POISONED)
		3:
			ctx.defender.add_condition(CardInstance.SpecialCondition.ASLEEP)
			ctx.defender.add_condition(CardInstance.SpecialCondition.POISONED)
		_:
			if total >= 4:
				ctx.defender.add_condition(CardInstance.SpecialCondition.ASLEEP)
				ctx.defender.add_condition(CardInstance.SpecialCondition.BURNED)
				ctx.defender.add_condition(CardInstance.SpecialCondition.POISONED)


# -- DR_27 Flaaffy: Energy Recall (atk 0) ----------------------------------
# "Attach up to 2 basic Energy cards from discard to Flaaffy."
static func _flaaffy_energy_recall(ctx: CardEffectContext) -> void:
	_attach_energy_from_discard(ctx.state, ctx.actor_id, ctx.attacker, 2,
		PokemonCardData.EnergyType.NONE)


# -- DR_15 Flygon: Air Slash (atk 0) ---------------------------------------
# "Flip a coin. If tails, discard 1 Energy from Flygon."
static func _flygon_air_slash(ctx: CardEffectContext) -> void:
	if randi() % 2 == 1:  # heads — keep energy
		return
	if ctx.attacker.attached_energy.is_empty():
		return
	var e := ctx.attacker.attached_energy[0] as CardInstance
	ctx.attacker.attached_energy.erase(e)
	ctx.state.board.move_card(e, "p%d_discard" % ctx.actor_id)


# -- RS_103 Sneasel-ex: Beat Up (atk 1) -----------------------------------
# "Flip a coin for each of your Pokémon in play. 20 damage × heads."
static func _sneasel_beat_up_pre(ctx: CardEffectContext) -> void:
	var all_mine := ctx.state.get_all_in_play(ctx.actor_id)
	var heads := 0
	for _p in all_mine:
		if randi() % 2 == 1:
			heads += 1
	ctx.damage_override = 20 * heads


# -- RS_16 Breloom: Battle Blast (atk 1) ----------------------------------
# "Does 40 damage plus 10 more for each Fighting Energy attached to Breloom."
static func _breloom_battle_blast_pre(ctx: CardEffectContext) -> void:
	var fighting_count := 0
	for e in ctx.attacker.attached_energy:
		if (e.data is EnergyCardData) \
				and (e.data as EnergyCardData).energy_type == PokemonCardData.EnergyType.FIGHTING:
			fighting_count += (e.data as EnergyCardData).provides
	ctx.damage_bonus += fighting_count * 10


# -- DR_7 Minun: Cheer On (atk 0) -----------------------------------------
# "Remove 1 damage counter from each of your Pokémon."
static func _minun_cheer_on(ctx: CardEffectContext) -> void:
	for pokemon in ctx.state.get_all_in_play(ctx.actor_id):
		pokemon.heal(10)


# -- DR_7 Minun: Special Circuit (atk 1) ----------------------------------
# "20 damage to any Pokémon; 40 if that Pokémon has a Poké-Power or Poké-Body."
static func _minun_special_circuit(ctx: CardEffectContext) -> void:
	var opp_id := 1 - ctx.actor_id
	# Auto-target: opponent's active Pokémon.
	var target := ctx.state.board.get_active_card(opp_id, 0)
	if target == null:
		return
	var dmg := 20
	if target.data is PokemonCardData:
		var pdata := target.data as PokemonCardData
		if not pdata.abilities.is_empty():
			dmg = 40
	target.apply_damage(dmg)
