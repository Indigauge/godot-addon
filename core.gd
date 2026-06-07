class_name IndigaugeCore

static var _dispatcher: Callable = Callable()

static func set_event_dispatcher(d: Callable) -> void:
	_dispatcher = d

# Event type must be letters with exactly one '.' not at the start or end (e.g. "player.died").
static func validate_event_type(s: String) -> Dictionary:
	if s.length() < 3:
		return {"ok": false, "error": "Invalid event type: too short (expected 'a.b')"}
	var dot := s.find(".")
	if dot == -1:
		return {"ok": false, "error": "Invalid event type: must contain one '.'"}
	if s.rfind(".") != dot:
		return {"ok": false, "error": "Invalid event type: multiple '.' found"}
	if dot == 0 or dot == s.length() - 1:
		return {"ok": false, "error": "Invalid event type: '.' cannot be the first or last character"}
	for ch in s:
		if ch == ".": continue
		var o := ch.unicode_at(0)
		var is_letter := (o >= 65 and o <= 90) or (o >= 97 and o <= 122)
		if not is_letter:
			return {"ok": false, "error": "Invalid event type: only letters and a single '.' are allowed"}
	return {"ok": true}

static func emit(level: String, event_type: String, metadata: Variant = null, ctx: Dictionary = {}) -> bool:
	var v := validate_event_type(event_type)
	if not v.ok:
		return false
	if _dispatcher.is_null():
		return false
	return _dispatcher.call(level, event_type, metadata, ctx)

# Hardware bucketing helpers
static func bucket_cores(n: int) -> String:
	if n <= 2: return "1-2"
	if n <= 4: return "3-4"
	if n <= 8: return "6-8"
	return ">8"

static func bucket_ram_gb(gb: int) -> String:
	if gb <= 4: return "<=4"
	if gb <= 8: return "6-8"
	if gb <= 16: return "12-16"
	return ">16"

static func coarsen_cpu_name(cpu_raw: String) -> String:
	var name := cpu_raw.to_lower()
	if name.find("apple m1") != -1: return "Apple M1"
	if name.find("apple m2") != -1: return "Apple M2"
	if name.find("apple m3") != -1: return "Apple M3"
	if name.find("intel") != -1:
		if name.find("celeron") != -1: return "Intel Celeron"
		if name.find("pentium") != -1: return "Intel Pentium"
		if name.find("xeon") != -1: return "Intel Xeon"
		if name.find("atom") != -1: return "Intel Atom"
		if name.find("i3") != -1: return "Intel i3"
		if name.find("i5") != -1: return "Intel i5"
		if name.find("i7") != -1: return "Intel i7"
		if name.find("i9") != -1: return "Intel i9"
		return "Intel (Other)"
	if name.find("amd") != -1:
		if name.find("threadripper") != -1: return "AMD Ryzen Threadripper"
		if name.find("ryzen") != -1: return "AMD Ryzen"
		if name.find("epyc") != -1: return "AMD EPYC"
		if name.find("athlon") != -1: return "AMD Athlon"
		return "AMD (Other)"
	if name.find("arm") != -1 or name.find("cortex") != -1:
		return "ARM (Generic)"
	return ""
