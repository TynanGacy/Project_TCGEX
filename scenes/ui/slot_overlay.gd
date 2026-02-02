extends Control
class_name SlotOverlay

# --- Tunables ---
@export var bench_sq := 120.0
@export var active_scale := 1.5
@export var stadium_scale := 1.5

@export var card_rect := Vector2(120, 168) # deck/discard/prizes (full card)
@export var gap := 16.0
@export var pile_gap := 14.0
@export var row_gap := 24.0
@export var pad := 16.0

@export var slot_color := Color(1, 1, 1, 0.10)
@export var pile_color := Color(1, 1, 1, 0.08)
@export var stadium_color := Color(1, 1, 1, 0.12)

var _bench: Array[ColorRect] = []
var _active: Array[ColorRect] = []

var _prizes: ColorRect
var _deck: ColorRect
var _discard: ColorRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prizes = _make_rect(pile_color)
	_deck = _make_rect(pile_color)
	_discard = _make_rect(pile_color)

func update_layout(board_rect: Rect2, active_count: int, bench_count: int, piles_mode: String) -> Dictionary:
	# piles_mode: "player" (prizes left, deck right) or "opponent" (deck left, prizes right)

	var bench_s := bench_sq
	var active_s := bench_sq * active_scale

	_resize_rects(_bench, bench_count, slot_color)
	_resize_rects(_active, active_count, slot_color)

	# Bench row near bottom of this board rect
	var bench_w := bench_count * bench_s + (bench_count - 1) * gap
	var bench_x0 := board_rect.position.x + (board_rect.size.x - bench_w) * 0.5
	var bench_y := board_rect.position.y + board_rect.size.y - bench_s - pad

	for i in range(bench_count):
		_bench[i].position = Vector2(bench_x0 + i * (bench_s + gap), bench_y)
		_bench[i].size = Vector2(bench_s, bench_s)

	# Active row centered above bench (toward middle)
	var active_w := active_count * active_s + (active_count - 1) * gap
	var active_x0 := board_rect.position.x + (board_rect.size.x - active_w) * 0.5
	var active_y := bench_y - active_s - row_gap

	for i in range(active_count):
		_active[i].position = Vector2(active_x0 + i * (active_s + gap), active_y)
		_active[i].size = Vector2(active_s, active_s)

	# Piles aligned to bench row center
	var pile_y := bench_y + (bench_s - card_rect.y) * 0.5

	var prizes_x: float
	var deck_x: float

	if piles_mode == "player":
		# prizes left, deck/discard right
		prizes_x = bench_x0 - pile_gap - card_rect.x
		deck_x = bench_x0 + bench_w + pile_gap
	else:
		# opponent: deck/discard left, prizes right
		deck_x = bench_x0 - pile_gap - card_rect.x
		prizes_x = bench_x0 + bench_w + pile_gap

	_prizes.position = Vector2(prizes_x, pile_y)
	_prizes.size = card_rect

	_deck.position = Vector2(deck_x, pile_y)
	_deck.size = card_rect

	_discard.position = Vector2(deck_x, pile_y + card_rect.y + pile_gap)
	_discard.size = card_rect

	# Return key geometry so Table can place Stadium relative to deck column
	return {
		"bench_x0": bench_x0,
		"bench_w": bench_w,
		"bench_y": bench_y,
		"deck_x": deck_x,
		"pile_y": pile_y,
		"bench_s": bench_s,
		"active_s": active_s
	}

func _make_rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r

func _resize_rects(arr: Array[ColorRect], want: int, c: Color) -> void:
	while arr.size() < want:
		var r: ColorRect = _make_rect(c)
		arr.append(r)

	while arr.size() > want:
		var last_index := arr.size() - 1
		var r: ColorRect = arr[last_index]
		arr.remove_at(last_index)
		r.queue_free()
