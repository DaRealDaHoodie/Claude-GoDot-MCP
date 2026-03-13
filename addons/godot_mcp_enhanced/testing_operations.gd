@tool
extends Node

## Testing & QA Operations for Claude-GoDot-MCP
## Covers action sequences, frame waits, property assertions, screenshot sequences, and scene stats.

var editor_interface: EditorInterface


# ── Testing Tools ─────────────────────────────────────────────────────────────

func simulate_action_sequence(params: Dictionary) -> Dictionary:
	"""Fire a sequence of input actions/keypresses with configurable delays between steps.
	   Each step: {action: string, pressed: bool, delay_ms: int} OR {keycode: int, pressed: bool, delay_ms: int}.
	   Useful for automated playtesting: walk → jump → interact → verify."""
	var steps = params.get("steps", [])
	if steps.is_empty():
		return {"success": false, "error": "steps array is required. Each step: {action: 'jump', pressed: true, delay_ms: 200} or {keycode: 32, pressed: true, delay_ms: 100}"}

	var results = []

	for step in steps:
		var action   = step.get("action", "")
		var keycode  = int(step.get("keycode", 0))
		var pressed  = bool(step.get("pressed", true))
		var delay_ms = int(step.get("delay_ms", 0))

		if action != "":
			var event = InputEventAction.new()
			event.action  = action
			event.pressed = pressed
			event.strength = float(step.get("strength", 1.0))
			Input.parse_input_event(event)
			results.append({"type": "action", "action": action, "pressed": pressed})
		elif keycode != 0:
			var event = InputEventKey.new()
			event.keycode = keycode
			event.pressed = pressed
			Input.parse_input_event(event)
			results.append({"type": "key", "keycode": keycode, "pressed": pressed})
		else:
			results.append({"type": "noop", "delay_only": true})

		if delay_ms > 0:
			await get_tree().create_timer(delay_ms / 1000.0).timeout

	print("[Test] Action sequence done: %d steps" % results.size())
	return {"success": true, "data": {"steps_executed": results.size(), "results": results}}


func wait_frames(params: Dictionary) -> Dictionary:
	"""Await N process frames. Use after physics operations to let simulation settle before asserting."""
	var frame_count = clampi(int(params.get("frame_count", 10)), 1, 300)
	var use_physics = bool(params.get("physics_frames", false))

	for _i in range(frame_count):
		if use_physics:
			await Engine.get_main_loop().physics_frame
		else:
			await Engine.get_main_loop().process_frame

	return {"success": true, "data": {"frames_waited": frame_count, "physics_frames": use_physics}}


func assert_node_property(params: Dictionary) -> Dictionary:
	"""Assert that a node's property equals an expected value. Returns {passed, actual, expected}.
	   Supports numeric tolerance for float/Vector3 comparisons."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node_path    = params.get("node_path", "")
	var property     = params.get("property", "")
	var expected     = params.get("expected_value")
	var tolerance    = float(params.get("tolerance", 0.001))

	if node_path == "" or property == "":
		return {"success": false, "error": "node_path and property are required"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	var actual = node.get(property)
	var passed = false
	var comparison_note = ""

	if actual is float or actual is int:
		passed = abs(float(actual) - float(str(expected).to_float())) <= tolerance
		comparison_note = "numeric (tolerance=%.4f)" % tolerance
	elif actual is Vector3 and expected is Array and expected.size() >= 3:
		var ev = Vector3(float(expected[0]), float(expected[1]), float(expected[2]))
		passed = actual.distance_to(ev) <= tolerance
		comparison_note = "Vector3 distance (tolerance=%.4f)" % tolerance
	elif actual is Vector2 and expected is Array and expected.size() >= 2:
		var ev = Vector2(float(expected[0]), float(expected[1]))
		passed = actual.distance_to(ev) <= tolerance
		comparison_note = "Vector2 distance"
	elif actual is bool:
		passed = bool(actual) == bool(expected)
		comparison_note = "bool"
	else:
		passed = str(actual) == str(expected)
		comparison_note = "string equality"

	print("[Test] assert '%s.%s': %s (expected=%s, actual=%s) → %s" % [
		node_path, property, comparison_note, str(expected), str(actual), "PASS" if passed else "FAIL"
	])

	return {
		"success": true,
		"data": {
			"passed":   passed,
			"property": property,
			"actual":   str(actual),
			"expected": str(expected),
			"node_path": node_path,
			"comparison": comparison_note
		}
	}


func capture_frame_sequence(params: Dictionary) -> Dictionary:
	"""Capture N editor screenshots with configurable interval. Returns array of base64-encoded PNGs.
	   Use for before/after comparisons, animation verification, particle effect reviews."""
	var frame_count  = clampi(int(params.get("frame_count", 3)), 1, 10)
	var interval_ms  = clampi(int(params.get("interval_ms", 500)), 0, 5000)
	var capture_game = bool(params.get("capture_game", false))

	var screenshots = []

	for i in range(frame_count):
		if i > 0 and interval_ms > 0:
			await get_tree().create_timer(interval_ms / 1000.0).timeout

		var img: Image = null
		if capture_game:
			# Game viewport
			var vp = get_viewport()
			if vp:
				img = vp.get_texture().get_image()
		else:
			# Editor window
			img = DisplayServer.screen_get_image(0)

		if img:
			screenshots.append(Marshalls.raw_to_base64(img.save_png_to_buffer()))
		else:
			screenshots.append("")

	print("[Test] Captured %d frame(s) with %dms interval" % [screenshots.size(), interval_ms])
	return {
		"success": true,
		"data": {
			"frame_count": screenshots.size(),
			"interval_ms": interval_ms,
			"screenshots":  screenshots
		}
	}


func get_scene_statistics(params: Dictionary) -> Dictionary:
	"""Count all nodes in the scene by type. Returns total count, script count, and type breakdown.
	   Use for QA checks and performance baseline."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var type_counts: Dictionary = {}
	var script_count  = 0
	var total_nodes   = 0
	var max_depth     = 0

	var queue: Array = [[root, 0]]
	while not queue.is_empty():
		var entry  = queue.pop_front()
		var node   = entry[0]
		var depth  = entry[1]
		total_nodes += 1
		max_depth = max(max_depth, depth)

		var cls = node.get_class()
		type_counts[cls] = type_counts.get(cls, 0) + 1

		if node.get_script():
			script_count += 1

		for child in node.get_children():
			queue.append([child, depth + 1])

	# Sort type_counts by count descending
	var sorted_types = []
	for cls in type_counts:
		sorted_types.append({"type": cls, "count": type_counts[cls]})
	sorted_types.sort_custom(func(a, b): return a["count"] > b["count"])

	return {
		"success": true,
		"data": {
			"scene_name":    root.name,
			"total_nodes":   total_nodes,
			"script_count":  script_count,
			"max_depth":     max_depth,
			"type_breakdown": sorted_types
		}
	}
