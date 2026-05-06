extends Node
## Animation queue autoload.  Listens to game events and manages a sequential
## FIFO animation queue.  Never overlaps animations.  Does NOT modify game state.

signal animation_completed(anim_id: int)
signal queue_drained
signal animation_started(anim_id: int, kind: int)

var _queue: Array[AnimationRequest] = []
var _current: AnimationRequest = null
var _next_id: int = 0
var _coin_flip_overlay: Control = null
var skip_animations: bool = false


func _ready() -> void:
	var manager := ManagerSystemSingleton
	manager.coin_flipped.connect(_on_coin_flipped)
	manager.coins_batch_flipped.connect(_on_coins_batch_flipped)


func set_coin_overlay(overlay: Control) -> void:
	_coin_flip_overlay = overlay


func enqueue(request: AnimationRequest) -> int:
	var id := _next_id
	_next_id += 1
	request.id = id
	if skip_animations:
		animation_completed.emit(id)
		if _queue.is_empty() and _current == null:
			queue_drained.emit()
		return id
	_queue.append(request)
	if _current == null:
		_play_next()
	return id


func enqueue_and_wait(request: AnimationRequest) -> void:
	var id := enqueue(request)
	if skip_animations:
		return
	while true:
		var completed_id: int = await animation_completed
		if completed_id == id:
			break


func wait_until_drained() -> void:
	if skip_animations:
		return
	if _queue.is_empty() and _current == null:
		return
	await queue_drained


func _on_coin_flipped(result: bool, label: String) -> void:
	if _coin_flip_overlay != null:
		_coin_flip_overlay.show_flip(result, label)
	var req := AnimationRequest.new()
	req.kind = AnimationRequest.Kind.COIN_FLIP
	req.duration = _coin_flip_overlay.total_anim_duration(1) if _coin_flip_overlay != null else 1.0
	req.data = {"result": result, "label": label}
	enqueue(req)


func _on_coins_batch_flipped(results: Array[bool], label: String) -> void:
	if _coin_flip_overlay != null:
		_coin_flip_overlay.show_batch(results, label)
	var req := AnimationRequest.new()
	req.kind = AnimationRequest.Kind.COIN_BATCH
	req.duration = _coin_flip_overlay.total_anim_duration(results.size()) if _coin_flip_overlay != null else 1.0
	req.data = {"results": results, "label": label}
	enqueue(req)


func _play_next() -> void:
	if _queue.is_empty():
		_current = null
		queue_drained.emit()
		return
	_current = _queue.pop_front()
	animation_started.emit(_current.id, _current.kind)
	await get_tree().create_timer(_current.duration).timeout
	var finished_id := _current.id
	_current = null
	animation_completed.emit(finished_id)
	_play_next()
