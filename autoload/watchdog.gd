extends Node
## Main-thread stall watchdog. Runs a background Thread that watches a
## heartbeat the main thread bumps every frame. If the main thread fails to
## bump for STALL_THRESHOLD_SECONDS, the watchdog prints to stderr (which
## shows up in the editor's Output panel) and kills the process so the user
## isn't stuck waiting on a frozen game.
##
## When the game is launched from the Godot editor (F5), the running game is
## a child process — OS.get_process_id() returns the game's PID, not the
## editor's, so the kill never touches the editor.
##
## Disabled inside the editor itself (Engine.is_editor_hint()) so it never
## fires while you're authoring scenes.

const POLL_INTERVAL_MS: int = 500
## How long the main thread is allowed to be unresponsive before we kill.
## 15s is generous: large saves, first-run asset imports, and a couple of
## file-dialog round trips all complete well under this, while a genuine
## O(N²) UI cascade still gets killed within seconds rather than minutes.
const STALL_THRESHOLD_SECONDS: float = 15.0

var _enabled: bool = true
var _thread: Thread = null
var _mutex: Mutex = null
var _stop: bool = false
var _last_heartbeat_ms: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		_enabled = false
		return
	_mutex = Mutex.new()
	_last_heartbeat_ms = Time.get_ticks_msec()
	_thread = Thread.new()
	_thread.start(_watch_loop)


func _process(_delta: float) -> void:
	if not _enabled:
		return
	## Cheapest possible heartbeat — single integer write under a mutex.
	_mutex.lock()
	_last_heartbeat_ms = Time.get_ticks_msec()
	_mutex.unlock()


func _watch_loop() -> void:
	while true:
		OS.delay_msec(POLL_INTERVAL_MS)
		if _stop:
			return
		_mutex.lock()
		var last_ms: int = _last_heartbeat_ms
		_mutex.unlock()
		var now_ms: int = Time.get_ticks_msec()
		var stalled_s: float = float(now_ms - last_ms) / 1000.0
		if stalled_s > STALL_THRESHOLD_SECONDS:
			## printerr surfaces immediately in the editor's Output panel and
			## in any stderr stream a packaged build is logging to. No
			## crash-file dance — the message is the breadcrumb.
			printerr("[Watchdog] Main thread stalled %.1fs (limit %.1fs). Terminating process." %
				[stalled_s, STALL_THRESHOLD_SECONDS])
			OS.kill(OS.get_process_id())
			return


func _exit_tree() -> void:
	if _thread == null:
		return
	_stop = true
	_thread.wait_to_finish()
