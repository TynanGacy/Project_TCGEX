class_name Card
extends Control
## A draggable card with hover preview. Arena-style click-and-drag.

signal drag_started(card: Card)
signal drag_ended(card: Card)
signal card_dropped(card: Card)

@export var card_name: String = "Card"
@export var card_art: Texture2D

## Visual settings
const BASE_SIZE := Vector2(150, 210)
const HOVER_SCALE := Vector2(1.15, 1.15)
const DRAG_SCALE := Vector2(1.05, 1.05)
const HOVER_RISE := 30.0
const TWEEN_SPEED := 0.15

## State
var is_dragging := false
var is_hovered := false
var drag_offset := Vector2.ZERO
var home_position := Vector2.ZERO
var home_rotation := 0.0
var hand_index := 0

@onready var background: ColorRect = %Background
@onready var art_rect: TextureRect = %ArtRect
@onready var name_label: Label = %NameLabel


func _ready() -> void:
	custom_minimum_size = BASE_SIZE
	size = BASE_SIZE
	pivot_offset = BASE_SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_update_visuals()


func _update_visuals() -> void:
	if name_label:
		name_label.text = card_name
	if art_rect and card_art:
		art_rect.texture = card_art


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_start_drag(mb.global_position)
			else:
				_end_drag()


func _start_drag(mouse_pos: Vector2) -> void:
	is_dragging = true
	drag_offset = global_position - mouse_pos
	z_index = 100
	_tween_scale(DRAG_SCALE)
	drag_started.emit(self)


func _end_drag() -> void:
	if not is_dragging:
		return
	is_dragging = false
	z_index = 0
	card_dropped.emit(self)
	drag_ended.emit(self)


func _process(_delta: float) -> void:
	if is_dragging:
		global_position = get_global_mouse_position() + drag_offset


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_MOUSE_ENTER:
			if not is_dragging:
				is_hovered = true
				_on_hover_start()
		NOTIFICATION_MOUSE_EXIT:
			if not is_dragging:
				is_hovered = false
				_on_hover_end()


func _on_hover_start() -> void:
	z_index = 50
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", HOVER_SCALE, TWEEN_SPEED)
	tween.tween_property(self, "position:y", home_position.y - HOVER_RISE, TWEEN_SPEED)
	tween.tween_property(self, "rotation", 0.0, TWEEN_SPEED)


func _on_hover_end() -> void:
	z_index = hand_index
	return_to_home()


func return_to_home() -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, TWEEN_SPEED)
	tween.tween_property(self, "position", home_position, TWEEN_SPEED)
	tween.tween_property(self, "rotation", home_rotation, TWEEN_SPEED)


func set_home(pos: Vector2, rot: float, index: int) -> void:
	home_position = pos
	home_rotation = rot
	hand_index = index
	z_index = index
