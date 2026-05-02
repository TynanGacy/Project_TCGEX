extends Control
## Full-screen coin flip animation overlay with staggered multi-coin support.
##
## Single coin:  show_flip(result, label)  → centred coin animation (~1.75 s).
## Multi-coin:   show_batch(results, label) → N coins in a row, each starting
##               halfway through the previous coin's flip phase.
##
## Timing constants:
##   FLIP_PHASE  = total animation time for one coin (spin + land + flash).
##   STAGGER     = delay between each successive coin starting = FLIP_PHASE / 2.
##   HOLD_TIME   = pause after all coins land before fade-out.
##   BUFFER_SEC  = extra time added to the delay reported to the game (via
##                 total_anim_duration()) so the turn doesn't end abruptly.
##
## Designed to sit inside a CanvasLayer / HUD node.  Ignores mouse input so
## gameplay is never blocked.

const COIN_DIAMETER: int = 140
const COIN_SPACING: float = 160.0  ## px between coin centres
const HEADS_COLOR := Color(0.95, 0.85, 0.2)   ## Gold
const TAILS_COLOR := Color(0.68, 0.72, 0.78)  ## Silver

## Timing (seconds).
const FADE_IN: float = 0.08
const FLIP_PHASE: float = 0.864   ## 4 half-flips (0.64) + final land (0.224)
const STAGGER: float = 0.432      ## half of FLIP_PHASE
const HOLD_TIME: float = 0.50
const FADE_OUT: float = 0.25
const BUFFER_SEC: float = 1.0     ## extra second before turn ends

var _backdrop: ColorRect
var _result_label: Label
var _coins: Array[Panel] = []
var _coin_letters: Array[Label] = []
var _coin_styles: Array[StyleBoxFlat] = []
var _tweens: Array[Tween] = []
var _master_tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_backdrop()


## Single-coin convenience — wraps show_batch with a 1-element array.
func show_flip(result: bool, label: String = "") -> void:
	show_batch([result], label)


## Play the staggered coin flip animation for [results].
func show_batch(results: Array, label: String = "") -> void:
	_kill_all_tweens()
	_clear_coins()

	var count: int = results.size()
	if count == 0:
		return

	visible = true
	modulate.a = 1.0
	_backdrop.color.a = 0.0

	## Build coin panels.
	for i in range(count):
		_create_coin(i, count)

	## Build result label.
	if _result_label == null:
		_build_result_label()
	_result_label.text = ""
	_result_label.modulate.a = 0.0
	## Move result label to front so it draws on top.
	move_child(_result_label, get_child_count() - 1)

	## Master tween handles backdrop + final fade-out.
	_master_tween = create_tween()
	_master_tween.tween_property(_backdrop, "color:a", 0.35, FADE_IN)

	## Stagger per-coin animations.
	for i in range(count):
		var delay: float = i * STAGGER
		_start_coin_anim(i, results[i], delay)

	## After all coins land: show result text, hold, fade out.
	var all_done_time: float = FADE_IN + FLIP_PHASE + (count - 1) * STAGGER
	_master_tween.tween_interval(all_done_time - FADE_IN)  ## already spent FADE_IN

	## Result text.
	var heads_count: int = 0
	for r in results:
		if r:
			heads_count += 1
	var result_text: String
	if count == 1:
		result_text = "HEADS!" if results[0] else "TAILS!"
	else:
		result_text = "%d Heads!" % heads_count if heads_count != count else "All Heads!"
		if heads_count == 0:
			result_text = "All Tails!"
	_master_tween.tween_callback(func() -> void: _result_label.text = result_text)
	_master_tween.tween_property(_result_label, "modulate:a", 1.0, 0.1)

	## Hold then fade out.
	_master_tween.tween_interval(HOLD_TIME)
	_master_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	_master_tween.tween_callback(func() -> void:
		visible = false
		_clear_coins()
	)


## Returns the total animation duration (seconds) for [count] coins,
## INCLUDING the 1-second buffer.  Used by main.gd to set _anim_end_msec.
static func total_anim_duration(count: int) -> float:
	return FADE_IN + FLIP_PHASE + (count - 1) * STAGGER + HOLD_TIME + FADE_OUT + BUFFER_SEC


# ---------------------------------------------------------------------------
# Per-coin animation
# ---------------------------------------------------------------------------

func _start_coin_anim(idx: int, result: bool, delay: float) -> void:
	var coin: Panel = _coins[idx]
	var style: StyleBoxFlat = _coin_styles[idx]
	var letter: Label = _coin_letters[idx]

	coin.scale = Vector2.ONE
	coin.pivot_offset = coin.size / 2.0
	style.bg_color = HEADS_COLOR
	letter.text = ""

	var tw: Tween = create_tween()
	_tweens.append(tw)

	## Initial delay for stagger.
	if delay > 0.0:
		tw.tween_interval(delay)

	## Spin — 4 half-flips, alternating colour.
	var half_flip: float = 0.08
	for i in range(4):
		var next_color: Color = TAILS_COLOR if i % 2 == 0 else HEADS_COLOR
		tw.tween_property(coin, "scale:y", 0.05, half_flip)
		tw.tween_callback(_swap_face.bind(style, letter, next_color, ""))
		tw.tween_property(coin, "scale:y", 1.0, half_flip)

	## Final half-flip to result face.
	tw.tween_property(coin, "scale:y", 0.05, half_flip)
	var land_color: Color = HEADS_COLOR if result else TAILS_COLOR
	var land_letter: String = "H" if result else "T"
	tw.tween_callback(_swap_face.bind(style, letter, land_color, land_letter))
	tw.tween_property(coin, "scale:y", 1.0, half_flip * 1.8)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_backdrop() -> void:
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0.0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)


func _build_result_label() -> void:
	_result_label = Label.new()
	_result_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.anchor_left   = 0.5
	_result_label.anchor_right  = 0.5
	_result_label.anchor_top    = 0.5
	_result_label.anchor_bottom = 0.5
	_result_label.offset_left   = -200.0
	_result_label.offset_right  =  200.0
	_result_label.offset_top    =  COIN_DIAMETER / 2.0 + 10.0
	_result_label.offset_bottom =  COIN_DIAMETER / 2.0 + 50.0
	_result_label.add_theme_font_size_override("font_size", 36)
	_result_label.add_theme_color_override("font_color", Color.WHITE)
	_result_label.modulate.a = 0.0
	add_child(_result_label)


func _create_coin(idx: int, total: int) -> void:
	var coin := Panel.new()
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.anchor_left   = 0.5
	coin.anchor_right  = 0.5
	coin.anchor_top    = 0.5
	coin.anchor_bottom = 0.5

	## Horizontal offset: centre coin at index (total-1)/2 is at x=0.
	var x_offset: float = (idx - (total - 1) / 2.0) * COIN_SPACING
	var half: float = COIN_DIAMETER / 2.0
	coin.offset_left   = x_offset - half
	coin.offset_right  = x_offset + half
	coin.offset_top    = -half - 20.0
	coin.offset_bottom =  half - 20.0

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(COIN_DIAMETER / 2)
	style.bg_color = HEADS_COLOR
	style.border_color = Color(0.55, 0.45, 0.1)
	style.set_border_width_all(3)
	coin.add_theme_stylebox_override("panel", style)
	add_child(coin)

	## Letter on coin face.
	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", Color(0.2, 0.15, 0.0))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.add_child(lbl)

	_coins.append(coin)
	_coin_styles.append(style)
	_coin_letters.append(lbl)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _swap_face(style: StyleBoxFlat, lbl: Label, color: Color, letter: String) -> void:
	style.bg_color = color
	lbl.text = letter


func _kill_all_tweens() -> void:
	if _master_tween and _master_tween.is_running():
		_master_tween.kill()
	_master_tween = null
	for tw in _tweens:
		if tw and tw.is_running():
			tw.kill()
	_tweens.clear()


func _clear_coins() -> void:
	for coin in _coins:
		if is_instance_valid(coin):
			coin.queue_free()
	_coins.clear()
	_coin_styles.clear()
	_coin_letters.clear()
