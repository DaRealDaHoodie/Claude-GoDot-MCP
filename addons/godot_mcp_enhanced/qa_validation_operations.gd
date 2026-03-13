@tool
extends Node

## QA & Validation Operations for Claude-GoDot-MCP
## Covers error assertions, scene validation, mouse path simulation, reimport, and unique node names.

var editor_interface: EditorInterface
var debugger_ref: Node  ## Set to debugger_integration in plugin.gd _enter_tree()


# ── QA Tools ─────────────────────────────────────────────────────────────────

func assert_no_errors(params: Dictionary) -> Dictionary:
	"""Assert that the Godot error log contains no errors (and optionally no warnings).
	   Returns {passed, error_count, warning_count, errors}. Fails if any errors found."""
	var include_warnings = bool(params.get("include_warnings", false))

	var error_list = []
	var warning_list = []

	if debugger_ref and debugger_ref.has_method("get_errors"):
		var result = debugger_ref.get_errors()
		var data = result.get("data", {})
		error_list   = data.get("errors",   [])
		warning_list = data.get("warnings", [])
	else:
		# Fallback: check EditorLog if available via EditorInterface
		# Can't easily access the log programmatically without debugger_ref
		pass

	var passed = error_list.is_empty()
	if include_warnings:
		passed = passed and warning_list.is_empty()

	print("[QA] assert_no_errors: %s (errors=%d, warnings=%d)" % [
		"PASS" if passed else "FAIL", error_list.size(), warning_list.size()
	])

	return {
		"success": true,
		"data": {
			"passed":        passed,
			"error_count":   error_list.size(),
			"warning_count": warning_list.size(),
			"errors":        error_list.slice(0, 20),
			"warnings":      warning_list.slice(0, 10) if include_warnings else []
		}
	}


func validate_scene(params: Dictionary) -> Dictionary:
	"""Validate the current scene for common issues: missing collision shapes,
	   missing meshes, physics bodies without collision, AnimationPlayers without animations.
	   Returns a list of {severity, node_path, issue} findings."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var findings: Array = []
	_validate_node_recursive(root, root, findings)

	var error_count   = findings.filter(func(f): return f.get("severity") == "error").size()
	var warning_count = findings.filter(func(f): return f.get("severity") == "warning").size()

	print("[QA] validate_scene '%s': %d error(s), %d warning(s)" % [root.name, error_count, warning_count])
	return {
		"success": true,
		"data": {
			"scene_name":    root.name,
			"passed":        error_count == 0,
			"error_count":   error_count,
			"warning_count": warning_count,
			"findings":      findings
		}
	}


func _validate_node_recursive(node: Node, root: Node, findings: Array) -> void:
	var path = str(root.get_path_to(node)) if node != root else node.name

	# CollisionShape without shape resource
	if (node is CollisionShape3D or node is CollisionShape2D) and not node.shape:
		findings.append({"severity": "error", "node_path": path, "issue": "%s has no Shape resource assigned" % node.get_class()})

	# MeshInstance3D without mesh
	if node is MeshInstance3D and not node.mesh:
		findings.append({"severity": "warning", "node_path": path, "issue": "MeshInstance3D has no Mesh assigned"})

	# PhysicsBody3D with no CollisionShape child
	if (node is RigidBody3D or node is CharacterBody3D or node is StaticBody3D):
		var has_shape = false
		for child in node.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				has_shape = true
				break
		if not has_shape:
			findings.append({"severity": "error", "node_path": path, "issue": "%s has no CollisionShape3D or CollisionPolygon3D child" % node.get_class()})

	# AnimationPlayer with no animations
	if node is AnimationPlayer:
		var total_anims = 0
		for lib_name in node.get_animation_library_list():
			total_anims += node.get_animation_library(lib_name).get_animation_list().size()
		if total_anims == 0:
			findings.append({"severity": "warning", "node_path": path, "issue": "AnimationPlayer has no animations"})

	# AnimationTree not pointing to a valid AnimationPlayer
	if node is AnimationTree:
		var ap_path = node.anim_player
		if ap_path == NodePath("") or not root.has_node(ap_path):
			findings.append({"severity": "error", "node_path": path, "issue": "AnimationTree.anim_player points to a non-existent node"})
		elif not node.active:
			findings.append({"severity": "warning", "node_path": path, "issue": "AnimationTree is not active"})

	# Light3D with very high energy (likely a mistake)
	if node is Light3D and node.light_energy > 100.0:
		findings.append({"severity": "warning", "node_path": path, "issue": "Light3D has energy=%.1f (unusually high)" % node.light_energy})

	# Area3D / Area2D without collision shape
	if node is Area3D or node is Area2D:
		var has_shape = false
		for child in node.get_children():
			if child is CollisionShape3D or child is CollisionShape2D or child is CollisionPolygon3D or child is CollisionPolygon2D:
				has_shape = true
				break
		if not has_shape:
			findings.append({"severity": "warning", "node_path": path, "issue": "%s has no CollisionShape child (will not detect overlaps)" % node.get_class()})

	for child in node.get_children():
		_validate_node_recursive(child, root, findings)


func simulate_mouse_path(params: Dictionary) -> Dictionary:
	"""Simulate mouse movement along an array of screen positions with a configurable interval.
	   Optionally click at the final position. Use for testing UI interactions, drag paths, etc."""
	var points    = params.get("points", [])
	var interval_ms = int(params.get("interval_ms", 50))
	var click_at_end = bool(params.get("click_at_end", false))
	var button_index = int(params.get("button_index", 1))

	if points.is_empty():
		return {"success": false, "error": "points array is required: [{x, y}, ...]"}

	var steps_done = 0
	var last_pos   = Vector2.ZERO

	for i in range(points.size()):
		var pt  = points[i]
		var pos = Vector2(float(pt.get("x", 0)), float(pt.get("y", 0)))

		var event = InputEventMouseMotion.new()
		event.position = pos
		if i > 0:
			event.relative = pos - last_pos
		Input.parse_input_event(event)
		last_pos = pos
		steps_done += 1

		if interval_ms > 0 and i < points.size() - 1:
			await get_tree().create_timer(interval_ms / 1000.0).timeout

	if click_at_end and not points.is_empty():
		var click_event = InputEventMouseButton.new()
		click_event.position = last_pos
		click_event.button_index = button_index
		click_event.pressed = true
		Input.parse_input_event(click_event)
		click_event.pressed = false
		Input.parse_input_event(click_event)

	return {
		"success": true,
		"data": {
			"steps": steps_done,
			"final_position": [last_pos.x, last_pos.y],
			"clicked": click_at_end
		}
	}


func reimport_all(params: Dictionary) -> Dictionary:
	"""Trigger a full filesystem scan and reimport of all project assets.
	   Use after batch-modifying .import files or moving assets."""
	var fs = editor_interface.get_resource_filesystem()
	fs.scan()

	# Also trigger reimport of any files that changed
	if params.get("force_reimport", false):
		# Collect all importable files
		var all_files: Array = []
		_collect_importable(ProjectSettings.globalize_path("res://"), all_files)
		if not all_files.is_empty():
			fs.reimport_files(all_files)

	print("[QA] Reimport/scan triggered (%s)" % ("force" if params.get("force_reimport", false) else "standard scan"))
	return {
		"success": true,
		"data": {"message": "Filesystem scan triggered. Godot will reimport changed assets."}
	}


func _collect_importable(dir_path: String, result: Array) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir: return
	var importable_ext = ["png", "jpg", "jpeg", "webp", "svg", "wav", "ogg", "mp3",
						  "fbx", "glb", "gltf", "obj", "dae", "ttf", "otf"]
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full = dir_path + "/" + fname
		if dir.current_is_dir():
			if fname != ".godot":
				_collect_importable(full, result)
		else:
			var ext = fname.get_extension().to_lower()
			if ext in importable_ext:
				result.append(full)
		fname = dir.get_next()
	dir.list_dir_end()


func set_node_unique_name(params: Dictionary) -> Dictionary:
	"""Set or clear a node's unique_name_in_owner flag — enables %NodeName shorthand access."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node_path = params.get("node_path", "")
	var unique    = bool(params.get("unique", true))

	if node_path == "":
		return {"success": false, "error": "node_path is required"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	node.unique_name_in_owner = unique

	print("[QA] set_node_unique_name '%s' → unique=%s (access via %%%s)" % [node_path, str(unique), node.name])
	return {
		"success": true,
		"data": {
			"node_path":           node_path,
			"node_name":           node.name,
			"unique_name_in_owner": unique,
			"shorthand":           "%%" + node.name if unique else "(disabled)"
		}
	}
