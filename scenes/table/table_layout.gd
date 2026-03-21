# res://scenes/table/table_layout.gd
#
# Handles card-container positioning so that CardView nodes line up
# with the visual SlotOverlay rects.  Extracted from Table to keep
# layout math separate from game logic.
class_name TableLayout
extends RefCounted


static func position_card_containers(
	player_id: int,
	layout_info: Dictionary,
	overlay_global_pos: Vector2,
	num_active_slots: int,
	active_slots: Array,
	bench_zone: HBoxContainer,
	slot_overlay: SlotOverlay,
	active_click_area: Control,
	bench_click_area: Control,
) -> void:
	var active_s: float = layout_info.get("active_s", 120.0)
	var bench_s: float = layout_info.get("bench_s", 120.0)
	var gap: float = slot_overlay.gap

	var bench_x0: float = layout_info.get("bench_x0", 0.0)
	var bench_w: float = layout_info.get("bench_w", 0.0)
	var bench_y: float = layout_info.get("bench_y", 0.0)
	var row_gap: float = slot_overlay.row_gap

	# Active slot positions
	var active_x0: float = bench_x0 + (bench_w - (num_active_slots * active_s + (num_active_slots - 1) * gap)) * 0.5
	var active_y: float = bench_y - active_s - row_gap

	for i in range(min(num_active_slots, active_slots.size())):
		var slot := active_slots[i] as Control
		if slot == null:
			continue

		slot.top_level = true
		var slot_x := overlay_global_pos.x + active_x0 + i * (active_s + gap)
		var slot_y := overlay_global_pos.y + active_y

		slot.global_position = Vector2(slot_x, slot_y)
		slot.custom_minimum_size = Vector2(active_s, active_s)
		slot.size = Vector2(active_s, active_s)
		slot.z_index = 0
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

		for child in slot.get_children():
			if child is CardView:
				child.custom_minimum_size = Vector2(active_s, active_s)
				child.size = Vector2(active_s, active_s)
				child.mouse_filter = Control.MOUSE_FILTER_STOP

	# Bench zone
	if bench_zone != null:
		bench_zone.top_level = true
		bench_zone.global_position = Vector2(overlay_global_pos.x + bench_x0, overlay_global_pos.y + bench_y)
		bench_zone.custom_minimum_size = Vector2(bench_w, bench_s)
		bench_zone.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		bench_zone.z_index = 0
		bench_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE

		for child in bench_zone.get_children():
			if child is CardView:
				child.custom_minimum_size = Vector2(bench_s, bench_s)
				child.size = Vector2(bench_s, bench_s)
				child.mouse_filter = Control.MOUSE_FILTER_STOP

	# Click areas
	_position_click_areas(
		layout_info, overlay_global_pos,
		num_active_slots, active_s, bench_s,
		slot_overlay, active_click_area, bench_click_area,
	)


static func _position_click_areas(
	layout_info: Dictionary,
	overlay_global_pos: Vector2,
	num_active_slots: int,
	active_s: float,
	bench_s: float,
	slot_overlay: SlotOverlay,
	active_click: Control,
	bench_click: Control,
) -> void:
	var gap: float = slot_overlay.gap
	var row_gap: float = slot_overlay.row_gap

	var bench_x0: float = layout_info.get("bench_x0", 0.0)
	var bench_w: float = layout_info.get("bench_w", 0.0)
	var bench_y: float = layout_info.get("bench_y", 0.0)

	var active_x0: float = bench_x0 + (bench_w - (num_active_slots * active_s + (num_active_slots - 1) * gap)) * 0.5
	var active_y: float = bench_y - active_s - row_gap
	var active_w: float = num_active_slots * active_s + (num_active_slots - 1) * gap

	if active_click != null:
		active_click.top_level = true
		active_click.global_position = Vector2(overlay_global_pos.x + active_x0, overlay_global_pos.y + active_y)
		active_click.size = Vector2(active_w, active_s)
		active_click.z_index = -10
		active_click.mouse_filter = Control.MOUSE_FILTER_STOP

	if bench_click != null:
		bench_click.top_level = true
		bench_click.global_position = Vector2(overlay_global_pos.x + bench_x0, overlay_global_pos.y + bench_y)
		bench_click.size = Vector2(bench_w, bench_s)
		bench_click.z_index = -10
		bench_click.mouse_filter = Control.MOUSE_FILTER_STOP
