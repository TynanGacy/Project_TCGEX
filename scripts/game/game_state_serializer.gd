class_name GameStateSerializer
## Saves and restores the full game state to/from JSON files in user://saves/.
##
## Save format version 1:
##   version, saved_at, name, mode, prize_count, active_slots, bench_slots,
##   controlling_player, turn {}, positions {player_0, player_1}, board {}
##
## Card restoration always uses TestDeckFactory._build_card_pool_by_id() so
## the loaded CardData objects carry art textures, matching the in-game pool.

const SAVE_DIR := "user://saves/"
const VERSION  := 1


## ── Serialization ─────────────────────────────────────────────────────────────

static func serialize(
	manager,
	is_developer_mode: bool,
	prize_count: int,
	active_slots: int,
	bench_slots: int,
	controlling_player: int
) -> Dictionary:
	var gp = manager.game_position
	var bp = manager.board_position

	var state: Dictionary = {
		"version":             VERSION,
		"saved_at":            Time.get_datetime_string_from_system(false, true),
		"name":                "",
		"mode":                "developer" if is_developer_mode else "player",
		"prize_count":         prize_count,
		"active_slots":        active_slots,
		"bench_slots":         bench_slots,
		"controlling_player":  controlling_player,
		"turn":                _serialize_turn(manager),
		"positions":           _serialize_positions(gp),
		"board":               _serialize_board(bp),
	}
	return state


static func _serialize_turn(manager) -> Dictionary:
	return {
		"current_player":      manager.current_player,
		"current_phase":       manager.current_phase,
		"turn_number":         manager.turn_number,
		"first_player":        manager.first_player,
		"supporter_played":    [
			manager.supporter_played_this_turn[0],
			manager.supporter_played_this_turn[1],
		],
		"energy_attached":     [
			manager.energy_attached_this_turn[0],
			manager.energy_attached_this_turn[1],
		],
		"retreat_used":        [
			manager.retreat_used_this_turn[0],
			manager.retreat_used_this_turn[1],
		],
		"attack_used":         [
			manager.attack_used_this_turn[0],
			manager.attack_used_this_turn[1],
		],
		"active_stadium_card":  manager.active_stadium.card_id if manager.active_stadium != null else null,
		"active_stadium_owner": manager.active_stadium_owner,
		"prize_selection_for":  manager.prize_selection_phase_for,
		"promotion_for":        manager.promotion_phase_for,
	}


static func _serialize_positions(gp) -> Dictionary:
	var out: Dictionary = {}
	for pid in range(2):
		out["player_%d" % pid] = {
			"deck":    _card_ids(gp.decks[pid]),
			"hand":    _card_ids(gp.hands[pid]),
			"discard": _card_ids(gp.discards[pid]),
			"prizes":  _prize_ids(gp.prizes[pid]),
		}
	return out


static func _serialize_board(bp) -> Dictionary:
	var out: Dictionary = {}
	for sid: String in BoardPosition.all_slot_ids():
		var inst: PokemonInstance = bp.get_instance(sid)
		out[sid] = _serialize_instance(inst)
	return out


static func _serialize_instance(inst: PokemonInstance) -> Variant:
	if inst == null:
		return null
	return {
		"card":         inst.card.card_id if inst.card != null else "",
		"prior_stages": _card_ids(inst.prior_stages),
		"current_hp":   inst.current_hp,
		"max_hp":       inst.max_hp,
		"conditions":   inst.special_conditions.map(func(c): return int(c)),
		"energy":       _card_ids(inst.attached_energy),
		"tools":        _card_ids(inst.attached_tools),
		"owner_id":     inst.owner_id,
	}


static func _card_ids(arr: Array) -> Array:
	var ids: Array = []
	for c in arr:
		if c != null and c is CardData:
			ids.append((c as CardData).card_id)
	return ids


static func _prize_ids(prize_row: Array) -> Array:
	var ids: Array = []
	for c in prize_row:
		if c != null and c is CardData:
			ids.append((c as CardData).card_id)
		else:
			ids.append(null)
	return ids


## ── File I/O ──────────────────────────────────────────────────────────────────

static func save_to_file(state: Dictionary, save_name: String) -> String:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var safe_name := save_name.strip_edges()
	if safe_name == "":
		safe_name = "save"
	## Replace characters unsafe for filenames.
	var result := ""
	for ch in safe_name:
		if ch in " /:*?\"<>|\\":
			result += "_"
		else:
			result += ch
	var ts := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var filename := "%s_%s.json" % [result, ts]
	var path := SAVE_DIR + filename
	var json_text := JSON.stringify(state, "\t")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("GameStateSerializer: could not write to %s" % path)
		return ""
	f.store_string(json_text)
	f.close()
	return path


## Returns Array of {path, name, saved_at} dicts, newest-first.
static func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return saves
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var path := SAVE_DIR + fname
			var raw := FileAccess.get_file_as_string(path)
			if raw != "":
				var parsed = JSON.parse_string(raw)
				if parsed is Dictionary:
					saves.append({
						"path":     path,
						"name":     (parsed as Dictionary).get("name", fname),
						"saved_at": (parsed as Dictionary).get("saved_at", ""),
					})
		fname = dir.get_next()
	dir.list_dir_end()
	## Sort newest first by saved_at string (ISO format sorts correctly).
	saves.sort_custom(func(a, b): return (a["saved_at"] as String) > (b["saved_at"] as String))
	return saves


static func load_from_file(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	if raw == "":
		push_error("GameStateSerializer: could not read %s" % path)
		return {}
	var parsed = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("GameStateSerializer: invalid JSON in %s" % path)
		return {}
	return parsed as Dictionary


## ── Restoration ───────────────────────────────────────────────────────────────

## Restores turn / phase counters onto manager from a saved state dictionary.
static func restore_turn_state(state: Dictionary, manager) -> void:
	var t: Dictionary = state.get("turn", {}) as Dictionary
	manager.current_player  = int(t.get("current_player", 0))
	manager.current_phase   = int(t.get("current_phase",  1))
	manager.turn_number     = int(t.get("turn_number",    1))
	manager.first_player    = int(t.get("first_player",   0))

	var sup: Array = t.get("supporter_played", [false, false]) as Array
	manager.supporter_played_this_turn = [bool(sup[0]), bool(sup[1])]

	var en: Array = t.get("energy_attached", [false, false]) as Array
	manager.energy_attached_this_turn = [bool(en[0]), bool(en[1])]

	var ret: Array = t.get("retreat_used", [false, false]) as Array
	manager.retreat_used_this_turn = [bool(ret[0]), bool(ret[1])]

	var atk: Array = t.get("attack_used", [false, false]) as Array
	manager.attack_used_this_turn = [bool(atk[0]), bool(atk[1])]

	manager.active_stadium         = null
	manager.active_stadium_owner   = int(t.get("active_stadium_owner", -1))
	manager.prize_selection_phase_for = int(t.get("prize_selection_for", -1))
	manager.promotion_phase_for    = int(t.get("promotion_for",        -1))


## Restores deck/hand/discard/prize card lists into manager.game_position.
## pool_by_id: Dictionary[card_id: String -> CardData] — art-loaded pool from
## TestDeckFactory._build_card_pool_by_id().
static func restore_positions(state: Dictionary, manager, pool_by_id: Dictionary) -> void:
	var gp = manager.game_position
	var positions: Dictionary = state.get("positions", {}) as Dictionary
	for pid in range(2):
		var pdata: Dictionary = positions.get("player_%d" % pid, {}) as Dictionary

		var deck: Array[CardData] = _resolve_card_list(pdata.get("deck", []) as Array, pool_by_id)
		gp.decks[pid] = deck

		var hand: Array[CardData] = _resolve_card_list(pdata.get("hand", []) as Array, pool_by_id)
		gp.hands[pid] = hand

		var discard: Array[CardData] = _resolve_card_list(pdata.get("discard", []) as Array, pool_by_id)
		gp.discards[pid] = discard

		var prize_ids: Array = pdata.get("prizes", []) as Array
		for i in range(mini(prize_ids.size(), 6)):
			if prize_ids[i] == null:
				gp.prizes[pid][i] = null
			else:
				gp.prizes[pid][i] = _resolve_card(str(prize_ids[i]), pool_by_id)


## Restores all PokemonInstances onto the board from a saved state dictionary.
static func restore_board(state: Dictionary, manager, pool_by_id: Dictionary) -> void:
	var board_data: Dictionary = state.get("board", {}) as Dictionary
	for sid: String in board_data.keys():
		var inst_data = board_data[sid]
		if inst_data == null:
			continue
		var inst := _restore_instance(inst_data as Dictionary, pool_by_id)
		if inst != null:
			manager.board_position.place(sid, inst)


static func _restore_instance(data: Dictionary, pool_by_id: Dictionary) -> PokemonInstance:
	var card_id: String = data.get("card", "") as String
	if card_id == "":
		return null
	var pcard := _resolve_card(card_id, pool_by_id) as PokemonCardData
	if pcard == null:
		push_warning("GameStateSerializer: unknown Pokémon card '%s'" % card_id)
		return null

	var owner: int = int(data.get("owner_id", 0))
	var inst := PokemonInstance.create(pcard, owner)
	inst.current_hp = int(data.get("current_hp", inst.current_hp))
	inst.max_hp     = int(data.get("max_hp",     inst.max_hp))

	for cid: String in (data.get("energy", []) as Array):
		var e := _resolve_card(cid, pool_by_id)
		if e != null:
			inst.attached_energy.append(e)

	for cid: String in (data.get("tools", []) as Array):
		var t := _resolve_card(cid, pool_by_id)
		if t != null:
			inst.attached_tools.append(t)

	for cond_int in (data.get("conditions", []) as Array):
		inst.special_conditions.append(int(cond_int) as PokemonInstance.SpecialCondition)

	for ps_id: String in (data.get("prior_stages", []) as Array):
		var ps := _resolve_card(ps_id, pool_by_id) as PokemonCardData
		if ps != null:
			inst.prior_stages.append(ps)

	return inst


static func _resolve_card_list(ids: Array, pool_by_id: Dictionary) -> Array[CardData]:
	var out: Array[CardData] = []
	for cid in ids:
		var c := _resolve_card(str(cid), pool_by_id)
		if c != null:
			out.append(c)
	return out


static func _resolve_card(card_id: String, pool_by_id: Dictionary) -> CardData:
	if not pool_by_id.has(card_id):
		push_warning("GameStateSerializer: card_id '%s' not found in pool" % card_id)
		return null
	## Duplicate so each in-game reference is a distinct object.
	return (pool_by_id[card_id] as CardData).duplicate()
