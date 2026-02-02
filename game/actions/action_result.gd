# res://game/actions/ActionResult.gd
class_name ActionResult

var ok: bool
var reason: String

static func success() -> ActionResult:
	var r := ActionResult.new()
	r.ok = true
	r.reason = ""
	return r

static func fail(msg: String) -> ActionResult:
	var r := ActionResult.new()
	r.ok = false
	r.reason = msg
	return r
