class_name Board
extends Node3D
## The 3D game board — a table surface with drop zones.

var all_zones: Array[DropZone] = []

## Bench zone dimensions: 2× the base card size.
const BENCH_CARD_W   := 1.32   ## landscape width  (0.66 × 2)
const BENCH_CARD_H   := 0.88   ## landscape height (0.44 × 2)
const BENCH_SPACING  := 1.35   ## centre-to-centre slot spacing
const BENCH_Z        := 2.4

## Active zone dimensions: 3× the base card size.
const ACTIVE_CARD_W  := 1.98   ## landscape width  (0.66 × 3)
const ACTIVE_CARD_H  := 1.32   ## landscape height (0.44 × 3)
const ACTIVE_SPACING := 2.1    ## spacing between dual-active slots
const ACTIVE_Z       := 1.1

## Prize zone layout constants (squished to fit beside expanded bench).
## Prizes stack into a single face-down pile per column (two columns per side).
## All prizes in one column share the same XZ; cards are offset in Y to form a pile.
const PRIZE_CARD_W     := 0.5    ## portrait width  (reduced)
const PRIZE_CARD_H     := 0.6    ## portrait height (reduced)
const PRIZE_AREA_X     := 2.9    ## abs x of prize-area centre (equidistant from active)
const PRIZE_COL_HALF   := 0.3    ## half-column spacing (x offset from PRIZE_AREA_X)
const PRIZE_STACK_Z    := 1.1    ## z position of prize pile (same as ACTIVE_Z)
const PRIZE_STACK_Y_STEP := 0.01 ## Y offset per layer (one card thickness)


func _ready() -> void:
	_collect_zones()


## Rebuild the active zone list, skipping invisible zones so they are never
## treated as valid drop targets.
func _collect_zones() -> void:
	all_zones.clear()
	for child in get_children():
		if child is DropZone and child.visible:
			all_zones.append(child as DropZone)
		for grandchild in child.get_children():
			if grandchild is DropZone and grandchild.visible:
				all_zones.append(grandchild as DropZone)


## Reposition and show/hide active and bench zones to match the configured
## counts. Call once after creating GameState, before dealing cards.
func configure_slots(num_active: int, num_bench: int) -> void:
	for i in range(2):
		var aname := "Active" if i == 0 else "Active 2"
		var zone := _find_zone_in_tree(aname)
		if zone == null:
			continue
		zone.visible = i < num_active
		zone.set_zone_size(ACTIVE_CARD_W, ACTIVE_CARD_H)
		if i < num_active:
			zone.position = Vector3(_active_x(i, num_active, false), 0.0, ACTIVE_Z)

	for i in range(1, 6):
		var zone := _find_zone_in_tree("Bench %d" % i)
		if zone == null:
			continue
		var si := i - 1
		zone.visible = si < num_bench
		zone.set_zone_size(BENCH_CARD_W, BENCH_CARD_H)
		if si < num_bench:
			zone.position = Vector3(_bench_x(si, num_bench, false), 0.0, BENCH_Z)

	for i in range(2):
		var aname := "Opp Active" if i == 0 else "Opp Active 2"
		var zone := _find_zone_in_tree(aname)
		if zone == null:
			continue
		zone.visible = i < num_active
		zone.set_zone_size(ACTIVE_CARD_W, ACTIVE_CARD_H)
		if i < num_active:
			zone.position = Vector3(_active_x(i, num_active, true), 0.0, -ACTIVE_Z)

	for i in range(1, 6):
		var zone := _find_zone_in_tree("Opp Bench %d" % i)
		if zone == null:
			continue
		var si := i - 1
		zone.visible = si < num_bench
		zone.set_zone_size(BENCH_CARD_W, BENCH_CARD_H)
		if si < num_bench:
			zone.position = Vector3(_bench_x(si, num_bench, true), 0.0, -BENCH_Z)

	_collect_zones()


## Position and show/hide prize zones to match [num_prizes] (2-6).
## Layout: two columns per side; each column is a face-down pile with cards
## offset in Y (Prize 1 at top/highest Y, taken first).
## Odd prize count puts one extra card in the left column.
## Player-0 prizes sit to the left (negative X); player-1 mirror to the right.
func configure_prizes(num_prizes: int) -> void:
	## left_col = ceil(num_prizes/2), right_col = floor(num_prizes/2)
	var left_col: int  = (num_prizes + 1) / 2
	var right_col: int = num_prizes / 2

	for i in range(6):
		var p0 := _find_zone_in_tree("Prize %d"     % (i + 1))
		var p1 := _find_zone_in_tree("Opp Prize %d" % (i + 1))

		var used := (i < num_prizes)
		if p0: p0.visible = used
		if p1: p1.visible = used
		if not used:
			continue

		if p0: p0.set_zone_size(PRIZE_CARD_W, PRIZE_CARD_H)
		if p1: p1.set_zone_size(PRIZE_CARD_W, PRIZE_CARD_H)

		## Determine which column this prize belongs to and its layer within that column.
		## Prizes 0..(left_col-1) go in the left column; the rest in the right.
		## Layer 0 = Prize 1 = top of stack (highest Y), taken first.
		var in_left := (i < left_col)
		var layer := i if in_left else (i - left_col)
		var x_off := -PRIZE_COL_HALF if in_left else PRIZE_COL_HALF
		var y_pos := float(left_col - 1 - layer) * PRIZE_STACK_Y_STEP if in_left \
			else float(right_col - 1 - layer) * PRIZE_STACK_Y_STEP

		## Player 0: left side (negative x), positive z.
		if p0: p0.position = Vector3(-PRIZE_AREA_X + x_off,  y_pos,  PRIZE_STACK_Z)
		## Player 1: right side (positive x), negative z (mirrored).
		if p1: p1.position = Vector3( PRIZE_AREA_X - x_off,  y_pos, -PRIZE_STACK_Z)

	_collect_zones()


## Searches the full scene tree (visible or not) for a zone by name.
func _find_zone_in_tree(zname: String) -> DropZone:
	for child in get_children():
		if child is DropZone and (child as DropZone).zone_name == zname:
			return child as DropZone
		for grandchild in child.get_children():
			if grandchild is DropZone and (grandchild as DropZone).zone_name == zname:
				return grandchild as DropZone
	return null


func _active_x(slot: int, total: int, mirror: bool) -> float:
	var x := 0.0 if total == 1 else (-ACTIVE_SPACING * 0.5 + slot * ACTIVE_SPACING)
	return -x if mirror else x


func _bench_x(slot: int, total: int, mirror: bool) -> float:
	var half_span := (total - 1) * BENCH_SPACING * 0.5
	var x := -half_span + slot * BENCH_SPACING
	return -x if mirror else x


func get_zone_by_name(zone_name: String) -> DropZone:
	for zone in all_zones:
		if zone.zone_name == zone_name:
			return zone
	return null


func get_zone_containing(card: Card) -> DropZone:
	for zone in all_zones:
		if card in zone.held_cards:
			return zone
	return null


func get_zone_at_position(world_pos: Vector3) -> DropZone:
	for zone in all_zones:
		if zone.contains_point(world_pos):
			return zone
	return null


func clear_highlights() -> void:
	for zone in all_zones:
		zone.set_highlighted(false)


