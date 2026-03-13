@tool
extends Node

## Editor Polish Operations for Claude-GoDot-MCP
## Covers node selection, batch duplication, and script pattern search.

var editor_interface: EditorInterface


# ── Editor Polish Tools ───────────────────────────────────────────────────────

func select_nodes(params: Dictionary) -> Dictionary:
	"""Select one or more nodes in the editor viewport by their scene paths.
	   Clears existing selection by default. Use after add_node to immediately inspect the new node."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node_paths    = params.get("node_paths", [])
	var clear_first   = bool(params.get("clear_existing", true))

	if node_paths.is_empty():
		return {"success": false, "error": "node_paths array is required (list of scene paths to select)"}

	var selection = editor_interface.get_selection()
	if clear_first:
		selection.clear()

	var selected  = []
	var not_found = []

	for path in node_paths:
		var node = root.get_node_or_null(str(path))
		if node:
			selection.add_node(node)
			selected.append(str(path))
		else:
			not_found.append(str(path))

	print("[Editor] Selected %d node(s)" % selected.size())
	return {
		"success": true,
		"data": {
			"selected":   selected,
			"not_found":  not_found,
			"count":      selected.size()
		}
	}


func batch_duplicate_with_offset(params: Dictionary) -> Dictionary:
	"""Duplicate a node N times, each copy offset by a cumulative position/rotation delta.
	   Perfect for placing fence posts, pillars, tiles, or enemy spawn points along a line."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node_path       = params.get("node_path", "")
	var count           = clampi(int(params.get("count", 2)), 1, 100)
	var pos_offset      = params.get("position_offset", [1, 0, 0])
	var rot_offset_deg  = params.get("rotation_offset_deg", [0, 0, 0])
	var name_prefix     = params.get("name_prefix", "")

	if node_path == "":
		return {"success": false, "error": "node_path is required"}

	var source = root.get_node_or_null(node_path)
	if not source:
		return {"success": false, "error": "Node not found: " + node_path}

	var parent = source.get_parent()
	if not parent:
		return {"success": false, "error": "Source node has no parent"}

	# Parse offset vectors
	var off3: Vector3 = Vector3.ZERO
	var rot3: Vector3 = Vector3.ZERO
	var off2: Vector2 = Vector2.ZERO

	if pos_offset is Array and pos_offset.size() >= 3:
		off3 = Vector3(float(pos_offset[0]), float(pos_offset[1]), float(pos_offset[2]))
	elif pos_offset is Array and pos_offset.size() >= 2:
		off2 = Vector2(float(pos_offset[0]), float(pos_offset[1]))

	if rot_offset_deg is Array and rot_offset_deg.size() >= 3:
		rot3 = Vector3(
			deg_to_rad(float(rot_offset_deg[0])),
			deg_to_rad(float(rot_offset_deg[1])),
			deg_to_rad(float(rot_offset_deg[2]))
		)

	var created = []
	var prefix  = name_prefix if name_prefix != "" else source.name

	for i in range(count):
		var dup = source.duplicate()
		dup.name = "%s_%d" % [prefix, i + 1]
		parent.add_child(dup)
		dup.owner = root

		if dup is Node3D and source is Node3D:
			dup.position = source.position + off3 * (i + 1)
			dup.rotation = source.rotation + rot3 * (i + 1)
		elif dup is Node2D and source is Node2D:
			var o2 = off2 if off2 != Vector2.ZERO else Vector2(off3.x, off3.y)
			dup.position = source.position + o2 * (i + 1)
			if rot3.z != 0.0:
				dup.rotation = source.rotation + rot3.z * (i + 1)

		created.append(str(dup.get_path()))

	print("[Editor] Duplicated '%s' × %d with offset %s" % [node_path, count, str(off3)])
	return {
		"success": true,
		"data": {
			"source_path":   node_path,
			"created":       created,
			"count":         created.size(),
			"position_offset": [off3.x, off3.y, off3.z]
		}
	}


func find_scripts_with_pattern(params: Dictionary) -> Dictionary:
	"""Grep all .gd script files in the project for a regex pattern.
	   Use to find: all scripts that extend a class, use a specific node type, call a method, etc."""
	var pattern = params.get("pattern", "")
	if pattern == "":
		return {"success": false, "error": "pattern is required (regex string, e.g. 'extends CharacterBody3D' or 'RigidBody3D')"}

	var max_results = clampi(int(params.get("max_results", 50)), 1, 200)
	var project_root = ProjectSettings.globalize_path("res://")

	var results: Array = []
	_grep_scripts(project_root, project_root, pattern, results, max_results)

	return {
		"success": true,
		"data": {
			"pattern":     pattern,
			"match_count": results.size(),
			"results":     results
		}
	}


func _grep_scripts(dir_path: String, project_root: String, pattern: String, results: Array, max_results: int) -> void:
	if results.size() >= max_results:
		return

	var dir = DirAccess.open(dir_path)
	if not dir:
		return

	var regex = RegEx.new()
	if regex.compile(pattern) != OK:
		return  # Invalid pattern — silently skip

	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "" and results.size() < max_results:
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full_path = dir_path + "/" + fname
		if dir.current_is_dir():
			_grep_scripts(full_path, project_root, pattern, results, max_results)
		elif fname.ends_with(".gd"):
			var f = FileAccess.open(full_path, FileAccess.READ)
			if f:
				var content = f.get_as_text()
				f.close()
				var matches = regex.search_all(content)
				if not matches.is_empty():
					var lines = content.split("\n")
					var match_details = []
					for m in matches.slice(0, 5):
						var line_num = content.left(m.get_start()).count("\n") + 1
						if line_num <= lines.size():
							match_details.append({
								"line":   line_num,
								"text":   lines[line_num - 1].strip_edges(),
								"match":  m.get_string()
							})
					# Convert to res:// path
					var res_path = "res://" + full_path.trim_prefix(project_root).trim_prefix("/")
					results.append({
						"file":        res_path,
						"match_count": matches.size(),
						"matches":     match_details
					})
		fname = dir.get_next()
	dir.list_dir_end()
