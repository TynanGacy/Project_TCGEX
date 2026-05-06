extends Node
## Lightweight localhost HTTP server that lets the Godot-AI MCP inject input
## events into the running game during development.
##
## Only active in debug / editor builds.
##
## Endpoints:
##   GET  http://localhost:9080/ping         — health check
##   POST http://localhost:9080/input        — JSON body, returns JSON
##   GET  http://localhost:9080/scene_tree   — dump visible Button nodes
##
## Actions:
##   press_button  — find a Button by text and emit its pressed signal
##   select_option — find an OptionButton by node name and select an item by text
##   drag          — multi-frame drag from one position to another
##   mouse_click   — instant press+release at a position
##   mouse_move    — warp mouse to position
##   key           — inject a key event
##   action_press / action_release  — named InputMap actions

const PORT := 9080
const READ_CHUNK := 4096

var _server: TCPServer = TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _buffers: Dictionary = {}  # instance_id -> PackedByteArray

## Multi-frame drag state.
## Each entry: {"type": "press"|"move"|"release", "pos": Vector2, "button": int}
var _drag_queue: Array = []
var _drag_frame_counter: int = 0  # frames to wait before processing next entry


func _ready() -> void:
	if not (OS.is_debug_build() or OS.has_feature("editor")):
		queue_free()
		return
	var err := _server.listen(PORT, "127.0.0.1")
	if err != OK:
		push_error("MCPInputServer: failed to listen on port %d — %s" % [PORT, error_string(err)])
		return
	print("[MCPInputServer] ready on 127.0.0.1:%d" % PORT)


func _exit_tree() -> void:
	for peer: StreamPeerTCP in _peers:
		peer.disconnect_from_host()
	_peers.clear()
	_buffers.clear()
	if _server.is_listening():
		_server.stop()


func _process(_delta: float) -> void:
	# Advance drag queue one step per frame.
	if not _drag_queue.is_empty():
		if _drag_frame_counter > 0:
			_drag_frame_counter -= 1
		else:
			var step: Dictionary = _drag_queue.pop_front()
			_execute_drag_step(step)
			_drag_frame_counter = step.get("wait", 1)  # frames to wait before next step

	# Service HTTP connections.
	if not _server.is_listening():
		return
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		_peers.append(peer)
		_buffers[peer.get_instance_id()] = PackedByteArray()
	for peer: StreamPeerTCP in _peers.duplicate():
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			peer.poll()
			var available := peer.get_available_bytes()
			if available > 0:
				var result: Array = peer.get_data(mini(available, READ_CHUNK))
				if result[0] == OK:
					var buf: PackedByteArray = _buffers[peer.get_instance_id()]
					buf.append_array(result[1])
					_buffers[peer.get_instance_id()] = buf
					_try_handle(peer)
		elif status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
			_drop_peer(peer)


func _execute_drag_step(step: Dictionary) -> void:
	var pos: Vector2 = step.get("pos", Vector2.ZERO)
	var button: int  = step.get("button", MOUSE_BUTTON_LEFT)
	var kind: String = step.get("type", "move")
	Input.warp_mouse(pos)
	match kind:
		"press":
			var ev := InputEventMouseButton.new()
			ev.position = pos
			ev.global_position = pos
			ev.button_index = button
			ev.pressed = true
			Input.parse_input_event(ev)
		"move":
			var ev := InputEventMouseMotion.new()
			ev.position = pos
			ev.global_position = pos
			Input.parse_input_event(ev)
		"release":
			var ev := InputEventMouseButton.new()
			ev.position = pos
			ev.global_position = pos
			ev.button_index = button
			ev.pressed = false
			Input.parse_input_event(ev)


# ---------------------------------------------------------------------------
# HTTP framing
# ---------------------------------------------------------------------------

func _try_handle(peer: StreamPeerTCP) -> void:
	var buf: PackedByteArray = _buffers[peer.get_instance_id()]
	var raw := buf.get_string_from_utf8()
	var header_end := raw.find("\r\n\r\n")
	if header_end == -1:
		return
	var header_block := raw.substr(0, header_end)
	var body_raw := raw.substr(header_end + 4)
	var content_length := 0
	for line: String in header_block.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = int(line.split(":", true, 1)[1].strip_edges())
			break
	if body_raw.length() < content_length:
		return
	_buffers[peer.get_instance_id()] = PackedByteArray()
	var first_line := header_block.split("\r\n")[0]
	var parts := first_line.split(" ")
	var method := parts[0] if parts.size() > 0 else ""
	var path   := parts[1] if parts.size() > 1 else "/"
	var body   := body_raw.substr(0, content_length)
	var status := 200
	var resp: Dictionary = {}
	if method == "GET" and path == "/ping":
		resp = {"status": "ok"}
	elif method == "GET" and path == "/scene_tree":
		resp = {"nodes": _dump_buttons(get_tree().root)}
	elif method == "POST" and path == "/input":
		var json := JSON.new()
		if json.parse(body) == OK:
			resp = _dispatch(json.data)
		else:
			status = 400
			resp = {"error": "invalid JSON"}
	else:
		status = 404
		resp = {"error": "not found"}
	_send_response(peer, status, resp)


func _send_response(peer: StreamPeerTCP, status: int, body: Dictionary) -> void:
	var body_str := JSON.stringify(body)
	var response := (
		"HTTP/1.1 %d OK\r\n" % status
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body_str.length()
		+ "Access-Control-Allow-Origin: *\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
		+ body_str
	)
	peer.put_data(response.to_utf8_buffer())
	peer.poll()
	_drop_peer(peer)


func _drop_peer(peer: StreamPeerTCP) -> void:
	_buffers.erase(peer.get_instance_id())
	_peers.erase(peer)
	peer.disconnect_from_host()


# ---------------------------------------------------------------------------
# Button / OptionButton tree dump
# ---------------------------------------------------------------------------

func _dump_buttons(node: Node, depth: int = 0) -> Array:
	var out: Array = []
	if depth > 10:
		return out
	if node is Button:
		var btn := node as Button
		if btn.visible:
			var rect := btn.get_global_rect()
			out.append({"text": btn.text, "disabled": btn.disabled,
				"rect": {"x": rect.position.x, "y": rect.position.y,
					"w": rect.size.x, "h": rect.size.y}})
	for child in node.get_children():
		out.append_array(_dump_buttons(child, depth + 1))
	return out


# ---------------------------------------------------------------------------
# Command dispatch
# ---------------------------------------------------------------------------

func _dispatch(cmd: Variant) -> Dictionary:
	if not cmd is Dictionary:
		return {"error": "body must be a JSON object"}
	var action: String = cmd.get("action", "")
	match action:
		"press_button":
			var text: String = cmd.get("text", "")
			if text.is_empty():
				return {"error": "missing 'text'"}
			var btn := _find_button(get_tree().root, text)
			if btn == null:
				return {"error": "button not found: '%s'" % text}
			btn.emit_signal("pressed")
			return {"ok": true, "action": action, "text": text}

		"select_option":
			## Find an OptionButton by node name (or partial name) and select
			## an item whose display text matches [text]. Emits item_selected.
			## Params: {"node": "NodeName", "text": "Option Label"}
			var node_name: String = cmd.get("node", "")
			var option_text: String = cmd.get("text", "")
			if node_name.is_empty():
				return {"error": "missing 'node'"}
			if option_text.is_empty():
				return {"error": "missing 'text'"}
			var opt := _find_option_button(get_tree().root, node_name)
			if opt == null:
				return {"error": "OptionButton not found: '%s'" % node_name}
			for i in range(opt.item_count):
				if opt.get_item_text(i) == option_text:
					opt.select(i)
					opt.emit_signal("item_selected", i)
					return {"ok": true, "action": action, "node": node_name,
						"selected": option_text, "index": i}
			# Build list of available options to help debugging.
			var available: Array = []
			for i in range(opt.item_count):
				available.append(opt.get_item_text(i))
			return {"error": "option text not found: '%s'" % option_text,
				"available": available}

		"drag":
			## Multi-frame drag from (from_x,from_y) to (to_x,to_y).
			## steps: number of intermediate move frames (default 10).
			## frame_wait: frames between each move step (default 1).
			var fx: float = float(cmd.get("from_x", 0))
			var fy: float = float(cmd.get("from_y", 0))
			var tx: float = float(cmd.get("to_x", 0))
			var ty: float = float(cmd.get("to_y", 0))
			var steps: int = int(cmd.get("steps", 10))
			var wait: int  = int(cmd.get("frame_wait", 1))
			var button: int = int(cmd.get("button", MOUSE_BUTTON_LEFT))
			_drag_queue.clear()
			# Press at start.
			_drag_queue.append({"type": "press", "pos": Vector2(fx, fy), "button": button, "wait": wait})
			# Move steps.
			for i in range(1, steps + 1):
				var t := float(i) / float(steps)
				var mx := fx + (tx - fx) * t
				var my := fy + (ty - fy) * t
				_drag_queue.append({"type": "move", "pos": Vector2(mx, my), "button": button, "wait": wait})
			# Release at end.
			_drag_queue.append({"type": "release", "pos": Vector2(tx, ty), "button": button, "wait": 0})
			_drag_frame_counter = 0
			return {"ok": true, "action": action, "steps": steps + 2,
				"from": {"x": fx, "y": fy}, "to": {"x": tx, "y": ty}}

		"mouse_click":
			var pos := Vector2(float(cmd.get("x", 0)), float(cmd.get("y", 0)))
			var button: int = cmd.get("button", MOUSE_BUTTON_LEFT)
			_inject_mouse_click(pos, button)
			return {"ok": true, "action": action, "x": pos.x, "y": pos.y}

		"mouse_move":
			var pos := Vector2(float(cmd.get("x", 0)), float(cmd.get("y", 0)))
			Input.warp_mouse(pos)
			return {"ok": true, "action": action, "x": pos.x, "y": pos.y}

		"key":
			var keycode: int = cmd.get("keycode", 0)
			var pressed: bool = cmd.get("pressed", true)
			var ev := InputEventKey.new()
			ev.keycode = keycode
			ev.pressed = pressed
			ev.echo = false
			Input.parse_input_event(ev)
			return {"ok": true, "action": action, "keycode": keycode, "pressed": pressed}

		"action_press":
			var iname: String = cmd.get("name", "")
			if iname.is_empty():
				return {"error": "missing 'name'"}
			Input.action_press(iname)
			return {"ok": true, "action": action, "name": iname}

		"action_release":
			var iname: String = cmd.get("name", "")
			if iname.is_empty():
				return {"error": "missing 'name'"}
			Input.action_release(iname)
			return {"ok": true, "action": action, "name": iname}

		_:
			return {"error": "unknown action '%s'" % action}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_button(node: Node, text: String) -> Button:
	if node is Button and not (node is OptionButton):
		var btn := node as Button
		if btn.text == text and btn.visible and not btn.disabled:
			return btn
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _find_option_button(node: Node, node_name: String) -> OptionButton:
	if node is OptionButton:
		var opt := node as OptionButton
		if opt.name == node_name or (node_name in opt.name):
			return opt
	for child in node.get_children():
		var found := _find_option_button(child, node_name)
		if found != null:
			return found
	return null


func _inject_mouse_click(pos: Vector2, button: int) -> void:
	Input.warp_mouse(pos)
	var press := InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = button
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
