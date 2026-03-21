class_name TurnPhase

enum Phase {
	START,
	MAIN,
	ATTACK,
	END
}

static func phase_to_string(p: int) -> String:
	match p:
		Phase.START: return "START"
		Phase.MAIN: return "MAIN"
		Phase.ATTACK: return "ATTACK"
		Phase.END: return "END"
	return "UNKNOWN"
