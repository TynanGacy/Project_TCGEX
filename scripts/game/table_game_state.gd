# res://scripts/game/table_game_state.gd
#
# Bridges the turn-engine's GameState interface to the Table scene tree.
# The Table node owns the actual card zones (HBoxContainers, active slots, etc.),
# and this class delegates queries/mutations to Table's methods.
class_name TableGameState
extends GameState

var table: Table

func _init(t: Table = null) -> void:
	table = t

# ---------- Play / Promote ----------
func can_play_hand_to_bench(target_player_id: int) -> bool:
	return table._count_cards_in_zone(table._bench_zones[target_player_id]) < table.max_bench

func can_play_hand_to_active(target_player_id: int) -> bool:
	return table.get_first_empty_active_slot_index(target_player_id) != -1

func can_promote_bench_to_active(target_player_id: int) -> bool:
	return table.get_first_empty_active_slot_index(target_player_id) != -1

func play_hand_to_bench(target_player_id: int, card_view: Node) -> void:
	table._move_card_to_zone(card_view, table._bench_zones[target_player_id], target_player_id)

func play_hand_to_active(target_player_id: int, card_view: Node, slot_index: int) -> void:
	table.move_card_to_active_slot(target_player_id, card_view, slot_index)

func promote_bench_to_active(target_player_id: int, card_view: Node, slot_index: int) -> void:
	table.move_card_to_active_slot(target_player_id, card_view, slot_index)

# ---------- Swap ----------
func can_swap_active_with_bench_3(board_player_id: int, active_slot_index: int, bench_index: int) -> bool:
	var a := table.get_active_card(board_player_id, active_slot_index)
	var b := table._get_bench_card_by_index(board_player_id, bench_index)
	return a != null and b != null

func swap_active_with_bench_3(board_player_id: int, active_slot_index: int, bench_index: int) -> void:
	table._swap_active_slot_with_bench_index(board_player_id, active_slot_index, bench_index)
