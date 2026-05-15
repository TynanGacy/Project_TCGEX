class_name Board
extends Node3D
## The 3D game board — a table surface with DropZone anchors.
##
## In the refactored architecture, DropZones are PURELY visual anchors used
## by BoardPosition to position PokemonInstances.  All logical slot state
## (which Pokemon is in which slot, overflow handling, etc.) lives in
## BoardPosition — the DropZones here just provide world positions.
##
## The named DropZones map 1:1 to BoardPosition slot_ids:
##   "Active"         -> p0_active1        "Opp Active"   -> p1_active1
##   "Active 2"       -> p0_active2        "Opp Active 2" -> p1_active2
##   "Bench N"        -> p0_benchN (1..5)  "Opp Bench N"  -> p1_benchN
##
## Overflow slots (p0_overflow1/2, p1_overflow1/2) are logical only — they
## are not rendered; BoardPosition auto-drains them to empty benches.
## If auto-drain fails it emits overflow_escalation for the Manager.

const PLAYMAT_PATHS: Array[String] = [
	"res://assets/images/playmats/playmat_default.png",
]

var _active_playmat_index: int = 0

const BENCH_CARD_W   := 1.32
const BENCH_CARD_H   := 0.88
const ACTIVE_CARD_W  := 1.98
const ACTIVE_CARD_H  := 1.32

## Stadium and Supporter are shared (not per-player), so they live outside the
## per-player slot map.  Game logic treats each as a single global slot.
## Their visual positions swap on perspective flip so Stadium always reads on
## the controlling player's screen-left and Supporter on the screen-right.
const STADIUM_SLOT_ID := "stadium"
const STADIUM_ZONE_NAME := "Stadium"
const SUPPORTER_SLOT_ID := "supporter"
const SUPPORTER_ZONE_NAME := "Supporter"

## Absolute X offset from board centre that Stadium and Supporter share.
## From P0 perspective Stadium sits at -SHARED_SLOT_X (screen-left),
## Supporter at +SHARED_SLOT_X; P1 perspective mirrors both.
## Doubles mode pushes the prize / deck / discard columns outward (the active
## row is wider), so the shared slots track them outward as well.
const SHARED_SLOT_X_SINGLES := 2.75
const SHARED_SLOT_X_DOUBLES := 3.85

## Maps Board_Position slot_id -> DropZone name in the scene tree.
const SLOT_TO_ZONE_NAME := {
	"p0_active1": "Active",
	"p0_active2": "Active 2",
	"p0_bench1":  "Bench 1",
	"p0_bench2":  "Bench 2",
	"p0_bench3":  "Bench 3",
	"p0_bench4":  "Bench 4",
	"p0_bench5":  "Bench 5",
	"p1_active1": "Opp Active",
	"p1_active2": "Opp Active 2",
	"p1_bench1":  "Opp Bench 1",
	"p1_bench2":  "Opp Bench 2",
	"p1_bench3":  "Opp Bench 3",
	"p1_bench4":  "Opp Bench 4",
	"p1_bench5":  "Opp Bench 5",
}

@onready var _table_surface: MeshInstance3D = $TableSurface


func _ready() -> void:
	_load_playmat()
	_initialise_zones()


func _load_playmat() -> void:
	var mat := _table_surface.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		_table_surface.set_surface_override_material(0, mat)
	var path := PLAYMAT_PATHS[_active_playmat_index]
	if ResourceLoader.exists(path):
		mat.albedo_texture = load(path) as Texture2D
		mat.albedo_color = Color.WHITE
	else:
		mat.albedo_texture = null
		mat.albedo_color = Color(0.22, 0.16, 0.1)


## Size the 2-player × 7-slot visible drop zones appropriately.  Called once
## on _ready.  Prize / deck / discard zones retain their scene transforms.
func _initialise_zones() -> void:
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone == null:
			continue
		if "active" in sid:
			zone.set_zone_size(ACTIVE_CARD_W, ACTIVE_CARD_H)
		else:
			zone.set_zone_size(BENCH_CARD_W, BENCH_CARD_H)
	var stadium_zone := get_stadium_zone()
	if stadium_zone != null:
		stadium_zone.set_zone_size(BENCH_CARD_W, BENCH_CARD_H)
	var supporter_zone := get_supporter_zone()
	if supporter_zone != null:
		supporter_zone.set_zone_size(BENCH_CARD_W, BENCH_CARD_H)


## Returns the shared Stadium DropZone, or null if the scene is mid-load.
func get_stadium_zone() -> DropZone:
	return _find_zone_in_tree(STADIUM_ZONE_NAME)


## Returns the shared Supporter DropZone, or null if the scene is mid-load.
func get_supporter_zone() -> DropZone:
	return _find_zone_in_tree(SUPPORTER_ZONE_NAME)


## Mirrors Stadium and Supporter X positions so that, from [pid]'s screen,
## Stadium reads on the left and Supporter on the right.  The camera flip in
## match.gd rotates 180° around Y, which turns world-+x into screen-left for
## P1 — so for P1 we put Stadium at +SHARED_SLOT_X and Supporter at -.
func apply_perspective(pid: int) -> void:
	_current_perspective = pid
	_refresh_shared_slot_positions()


## Active-count is the second axis (singles vs doubles) that affects shared
## slot X.  Called by configure_slots once it knows the mode.
func _refresh_shared_slot_positions() -> void:
	var shared_x: float = SHARED_SLOT_X_DOUBLES if _current_active_count == 2 else SHARED_SLOT_X_SINGLES
	var sign_for_stadium: float = -1.0 if _current_perspective == 0 else 1.0
	var stadium_zone := get_stadium_zone()
	if stadium_zone != null:
		stadium_zone.position.x = sign_for_stadium * shared_x
	var supporter_zone := get_supporter_zone()
	if supporter_zone != null:
		supporter_zone.position.x = -sign_for_stadium * shared_x


## Active/bench spacing constants (world units between slot centres).
## ACTIVE_SPACING must exceed ACTIVE_CARD_W (1.98) to avoid overlap.
const ACTIVE_SPACING := 2.2
const BENCH_SPACING  := 1.35

## Z positions of each row per player (index 0 = p0, index 1 = p1).
## Active row pushed outward from centre to make room for the shared Stadium /
## Supporter slots at z = 0.  Bench row shifted in the same direction to keep
## clear of the active row's footprint.
const ACTIVE_Z: Array[float] = [1.4, -1.4]
const BENCH_Z:  Array[float] = [2.65, -2.65]

## Outer X positions for peripheral zones (prize columns, deck, discard).
## Player 0 keeps prizes on the left (negative x) and deck/discard on the
## right; player 1 mirrors that arrangement.  Prize and deck/discard columns
## share the same |x| pair so the gap from the active row to prizes equals
## the gap from the active row to deck/discard.  Singles mode uses a tighter
## column pair so that gap matches the doubles-mode gap (the active row in
## doubles is wider, pushing its outer edge close to the columns naturally).
const DECK_X_SINGLES        : Array[float] = [ 2.4, -2.4]
const DISCARD_X_SINGLES     : Array[float] = [ 3.1, -3.1]
const PRIZE_INNER_X_SINGLES : Array[float] = [-2.4,  2.4]
const PRIZE_OUTER_X_SINGLES : Array[float] = [-3.1,  3.1]

const DECK_X_DOUBLES        : Array[float] = [ 3.5, -3.5]
const DISCARD_X_DOUBLES     : Array[float] = [ 4.2, -4.2]
const PRIZE_INNER_X_DOUBLES : Array[float] = [-3.5,  3.5]
const PRIZE_OUTER_X_DOUBLES : Array[float] = [-4.2,  4.2]

## Tracks the current active-row mode and perspective so reconfiguration calls
## (configure_slots / apply_perspective) can independently update Stadium /
## Supporter without losing the other axis of state.
var _current_active_count: int = 1
var _current_perspective:  int = 0

## Updates bench zone visibility and positions only.  Called mid-game when the
## bench slot count changes (see manager.set_bench_count).
func set_bench_count(bench_count: int) -> void:
	bench_count = clampi(bench_count, 3, 5)
	for pid in range(2):
		for i in range(1, 6):
			var zone := get_zone_for_slot("p%d_bench%d" % [pid, i])
			if zone == null:
				continue
			zone.visible = (i <= bench_count)
			if zone.visible:
				var half := (bench_count - 1) / 2.0
				zone.position = Vector3((i - 1 - half) * BENCH_SPACING, 0.0, BENCH_Z[pid])


## Hides excess zones, centres the visible ones around x = 0, and hides
## unused prize slots.  BoardPosition's logical slots are untouched.
func configure_slots(active_count: int, bench_count: int, prize_count: int = 6) -> void:
	active_count = clampi(active_count, 1, 2)
	bench_count  = clampi(bench_count,  3, 5)
	prize_count  = clampi(prize_count,  2, 6)
	_current_active_count = active_count

	## Column X depends on active-row width: doubles needs wider columns to
	## clear the wider active row; singles squeezes them in so the prize /
	## deck gap matches the doubles gap from the active edge.
	var deck_x_arr        : Array[float] = DECK_X_DOUBLES        if active_count == 2 else DECK_X_SINGLES
	var discard_x_arr     : Array[float] = DISCARD_X_DOUBLES     if active_count == 2 else DISCARD_X_SINGLES
	var prize_inner_x_arr : Array[float] = PRIZE_INNER_X_DOUBLES if active_count == 2 else PRIZE_INNER_X_SINGLES
	var prize_outer_x_arr : Array[float] = PRIZE_OUTER_X_DOUBLES if active_count == 2 else PRIZE_OUTER_X_SINGLES

	for pid in range(2):
		## Active slots — centre the visible pair around x = 0.
		for i in range(1, 3):
			var zone := get_zone_for_slot("p%d_active%d" % [pid, i])
			if zone == null:
				continue
			zone.visible = (i <= active_count)
			if zone.visible:
				var half := (active_count - 1) / 2.0
				zone.position = Vector3((i - 1 - half) * ACTIVE_SPACING, 0.0, ACTIVE_Z[pid])

		## Bench slots — centre the visible group around x = 0.
		for i in range(1, 6):
			var zone := get_zone_for_slot("p%d_bench%d" % [pid, i])
			if zone == null:
				continue
			zone.visible = (i <= bench_count)
			if zone.visible:
				var half := (bench_count - 1) / 2.0
				zone.position = Vector3((i - 1 - half) * BENCH_SPACING, 0.0, BENCH_Z[pid])

		## Prize slots — hide the unused tail slots and shift to the outer x
		## columns so they clear the new wider active row.  Odd indices
		## (1/3/5) use the outer column; even indices (2/4/6) the inner.
		## When prize_count is odd, the final prize sits on its own row and
		## is centred between the two columns.
		var prize_prefix := "" if pid == 0 else "Opp "
		var prize_z_sign := 1.0 if pid == 0 else -1.0
		var prize_rows: Array[float] = [1.1, 1.3, 1.5]
		var prize_center_x: float = (prize_inner_x_arr[pid] + prize_outer_x_arr[pid]) / 2.0
		for i in range(1, 7):
			var zone := _find_zone_in_tree("%sPrize %d" % [prize_prefix, i])
			if zone == null:
				continue
			zone.visible = (i <= prize_count)
			var col_x: float
			if i == prize_count and prize_count % 2 == 1:
				col_x = prize_center_x
			else:
				col_x = prize_outer_x_arr[pid] if (i % 2 == 1) else prize_inner_x_arr[pid]
			var row_z: float = prize_rows[(i - 1) / 2] * prize_z_sign
			zone.position = Vector3(col_x, zone.position.y, row_z)

		## Deck / discard — share the column |x| with the prize pair so the
		## active-row-to-column gap is identical on both sides.
		var deck_zone := _find_zone_in_tree("%sDeck" % prize_prefix)
		if deck_zone != null:
			deck_zone.position = Vector3(deck_x_arr[pid], deck_zone.position.y, ACTIVE_Z[pid])
		var discard_zone := _find_zone_in_tree("%sDiscard" % prize_prefix)
		if discard_zone != null:
			discard_zone.position = Vector3(discard_x_arr[pid], discard_zone.position.y, ACTIVE_Z[pid])

	## Once both players' columns are repositioned, the shared slots track them.
	_refresh_shared_slot_positions()


## Returns any DropZone in the scene by its zone_name property.
func get_named_zone(name: String) -> DropZone:
	return _find_zone_in_tree(name)


## Returns the DropZone for a given BoardPosition slot_id, or null.
func get_zone_for_slot(slot_id: String) -> DropZone:
	var zone_name: String = SLOT_TO_ZONE_NAME.get(slot_id, "")
	if zone_name == "":
		return null
	return _find_zone_in_tree(zone_name)


## Builds the { slot_id: DropZone } dictionary BoardPosition uses as its
## anchors for visually placing PokemonInstance nodes.
func collect_slot_anchors() -> Dictionary:
	var anchors: Dictionary = {}
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone != null:
			anchors[sid] = zone
	return anchors


## Returns the DropZone at the given world position (used for drag-to-drop).
## Iterates Pokemon-slot zones, plus the shared Stadium slot.
func get_slot_zone_at(world_pos: Vector3) -> DropZone:
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone != null and zone.visible and zone.contains_point(world_pos):
			return zone
	var stadium_zone := get_stadium_zone()
	if stadium_zone != null and stadium_zone.visible and stadium_zone.contains_point(world_pos):
		return stadium_zone
	var supporter_zone := get_supporter_zone()
	if supporter_zone != null and supporter_zone.visible and supporter_zone.contains_point(world_pos):
		return supporter_zone
	return null


## Returns the slot_id for a given DropZone (reverse lookup), or "".
func slot_id_for_zone(zone: DropZone) -> String:
	if zone == null:
		return ""
	for sid in SLOT_TO_ZONE_NAME.keys():
		if get_zone_for_slot(sid) == zone:
			return sid
	if zone == get_stadium_zone():
		return STADIUM_SLOT_ID
	if zone == get_supporter_zone():
		return SUPPORTER_SLOT_ID
	return ""


func _find_zone_in_tree(zname: String) -> DropZone:
	for child in get_children():
		if child is DropZone and (child as DropZone).zone_name == zname:
			return child as DropZone
		for grandchild in child.get_children():
			if grandchild is DropZone and (grandchild as DropZone).zone_name == zname:
				return grandchild as DropZone
	return null


func clear_highlights() -> void:
	for sid in SLOT_TO_ZONE_NAME.keys():
		var zone := get_zone_for_slot(sid)
		if zone != null:
			zone.set_highlighted(false)
	var stadium_zone := get_stadium_zone()
	if stadium_zone != null:
		stadium_zone.set_highlighted(false)
	var supporter_zone := get_supporter_zone()
	if supporter_zone != null:
		supporter_zone.set_highlighted(false)
