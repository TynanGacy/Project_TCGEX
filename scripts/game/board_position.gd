class_name BoardPosition
extends Node
## Tracks the placement of up to 14 PokemonInstance objects across the 14
## fixed slots on the board, and drives the visual appearance of each slot.
##
## Slots (per player):
##   active1, active2,
##   bench1, bench2, bench3, bench4, bench5,
##   overflow1, overflow2
##
## Responsibilities (and ONLY these):
##   - Know which PokemonInstance occupies which slot.
##   - Reparent / position a PokemonInstance's visual node when it is placed
##     or moved.
##   - After every update, attempt to auto-drain overflow slots into empty
##     bench slots.  If an overflow slot still has an instance after draining,
##     emit overflow_escalation for the Manager to resolve.
##
## It does NOT consult game rules; it does NOT reject moves.  The Manager
## validates legality before calling into BoardPosition.

signal slot_changed(slot_id: String, instance: PokemonInstance)
signal overflow_escalation(player_id: int, instance: PokemonInstance)

const ACTIVE_SLOTS: Array[String] = ["active1", "active2"]
const BENCH_SLOTS: Array[String] = ["bench1", "bench2", "bench3", "bench4", "bench5"]
const OVERFLOW_SLOTS: Array[String] = ["overflow1", "overflow2"]

## slot_id (String) -> PokemonInstance | null
var _slots: Dictionary = {}

## slot_id (String) -> Node3D anchor in the scene tree (where to place the
## PokemonInstance visual).  Populated by set_slot_anchors().
var _anchors: Dictionary = {}


func _init() -> void:
	for pid in range(2):
		for s in ACTIVE_SLOTS + BENCH_SLOTS + OVERFLOW_SLOTS:
			_slots[_sid(pid, s)] = null


## --- Slot id helpers --------------------------------------------------------

static func _sid(player_id: int, slot_name: String) -> String:
	return "p%d_%s" % [player_id, slot_name]


static func all_slot_ids(player_id: int = -1) -> Array[String]:
	var out: Array[String] = []
	var players := [0, 1] if player_id < 0 else [player_id]
	for pid in players:
		for s in ACTIVE_SLOTS + BENCH_SLOTS + OVERFLOW_SLOTS:
			out.append(_sid(pid, s))
	return out


## --- Anchor wiring ----------------------------------------------------------

## Registers the Node3D anchors used to visually position each slot's
## PokemonInstance.  Callers pass { slot_id: Node3D }.
func set_slot_anchors(anchors: Dictionary) -> void:
	_anchors = anchors.duplicate()
	_refresh_all_visuals()


## --- Queries ----------------------------------------------------------------

func get_instance(slot_id: String) -> PokemonInstance:
	return _slots.get(slot_id, null) as PokemonInstance


func has_slot(slot_id: String) -> bool:
	return _slots.has(slot_id)


func is_empty(slot_id: String) -> bool:
	return get_instance(slot_id) == null


func player_of(slot_id: String) -> int:
	if slot_id.begins_with("p0_"): return 0
	if slot_id.begins_with("p1_"): return 1
	return -1


func first_empty_bench(player_id: int) -> String:
	for s in BENCH_SLOTS:
		var sid := _sid(player_id, s)
		if is_empty(sid):
			return sid
	return ""


func first_empty_active(player_id: int) -> String:
	## Placeholder for upcoming "multi-active" rule support and effects that
	## can promote into secondary active slots.  Not called by the current
	## single-active flow, but intentionally kept as part of the board API.
	for s in ACTIVE_SLOTS:
		var sid := _sid(player_id, s)
		if is_empty(sid):
			return sid
	return ""


## --- Mutations (no legality checks) -----------------------------------------

## Places [instance] into [slot_id], overwriting any previous occupant (the
## previous occupant is cleared but not discarded — the caller must have
## already removed it).  Triggers overflow auto-resolution.
func place(slot_id: String, instance: PokemonInstance) -> void:
	if not _slots.has(slot_id):
		push_error("BoardPosition.place: unknown slot '%s'" % slot_id)
		return
	_slots[slot_id] = instance
	_apply_visual(slot_id, instance)
	slot_changed.emit(slot_id, instance)
	_resolve_overflow(player_of(slot_id))


## Removes and returns the PokemonInstance at [slot_id] (or null if empty).
func clear(slot_id: String) -> PokemonInstance:
	var inst: PokemonInstance = _slots.get(slot_id, null)
	_slots[slot_id] = null
	if inst != null and inst.get_parent() != null:
		inst.get_parent().remove_child(inst)
	slot_changed.emit(slot_id, null)
	return inst


## Moves the PokemonInstance from [from_slot] to [to_slot].  Does not swap —
## if [to_slot] is occupied the existing instance is left orphaned (caller's
## responsibility).  Use swap() for a true swap.
func move(from_slot: String, to_slot: String) -> void:
	var inst: PokemonInstance = _slots.get(from_slot, null)
	_slots[from_slot] = null
	_slots[to_slot] = inst
	slot_changed.emit(from_slot, null)
	_apply_visual(to_slot, inst)
	slot_changed.emit(to_slot, inst)
	_resolve_overflow(player_of(to_slot))


func swap(slot_a: String, slot_b: String) -> void:
	var a: PokemonInstance = _slots.get(slot_a, null)
	var b: PokemonInstance = _slots.get(slot_b, null)
	_slots[slot_a] = b
	_slots[slot_b] = a
	_apply_visual(slot_a, b)
	_apply_visual(slot_b, a)
	slot_changed.emit(slot_a, b)
	slot_changed.emit(slot_b, a)


## --- Internal: visuals + overflow -------------------------------------------

func _apply_visual(slot_id: String, instance: PokemonInstance) -> void:
	if instance == null:
		return
	var anchor: Node3D = _anchors.get(slot_id, null)
	if anchor == null:
		return
	if instance.get_parent() != null and instance.get_parent() != anchor:
		instance.get_parent().remove_child(instance)
	if instance.get_parent() == null:
		anchor.add_child(instance)
	instance.position = Vector3.ZERO
	instance.rotation = Vector3.ZERO
	if anchor is DropZone:
		instance.set_display_width((anchor as DropZone).get_effective_width())


func _refresh_all_visuals() -> void:
	for slot_id in _slots.keys():
		var inst := _slots[slot_id] as PokemonInstance
		if inst != null:
			_apply_visual(slot_id, inst)


## If any overflow slot is populated, try to shift it into the first empty
## bench slot for that player.  If no bench slot is available, emit
## overflow_escalation so the Manager can prompt the player.
func _resolve_overflow(player_id: int) -> void:
	if player_id < 0:
		return
	for s in OVERFLOW_SLOTS:
		var over_id := _sid(player_id, s)
		var inst := get_instance(over_id)
		if inst == null:
			continue
		var bench_id := first_empty_bench(player_id)
		if bench_id != "":
			move(over_id, bench_id)
		else:
			overflow_escalation.emit(player_id, inst)
