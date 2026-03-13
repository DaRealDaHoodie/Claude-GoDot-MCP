@tool
extends Node

## Batch Extras for Claude-GoDot-MCP
## Script attachment, node renaming, file moves, scene packing, and resource file creation.

var editor_interface: EditorInterface


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_root() -> Node:
	return editor_interface.get_edited_scene_root()


func _walk_scene(root: Node, callback: Callable) -> void:
	"""BFS walk of the scene tree, calling callback(node) for each node."""
	var queue: Array = [root]
	while not queue.is_empty():
		var node = queue.pop_front()
		callback.call(node)
		queue += node.get_children()


func _coerce_value(v) -> Variant:
	if not v is Array: return v
	match v.size():
		2: return Vector2(float(v[0]), float(v[1]))
		3: return Vector3(float(v[0]), float(v[1]), float(v[2]))
		4: return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return v


# ── Batch Extra Tools ─────────────────────────────────────────────────────────

func batch_attach_script(params: Dictionary) -> Dictionary:
	"""Attach the same GDScript to every node matching a type and/or group filter.
	   Use for giving a class script to all enemies, all collectibles, all platforms, etc."""
	var root = _get_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var script_path = params.get("script_path", "")
	var node_type   = params.get("node_type", "")
	var group_name  = params.get("group_name", "")
	var overwrite   = bool(params.get("overwrite_existing", false))

	if script_path == "":
		return {"success": false, "error": "script_path is required (res:// path to .gd file)"}
	if not ResourceLoader.exists(script_path):
		return {"success": false, "error": "Script not found: " + script_path}

	var scr = load(script_path)
	if not scr:
		return {"success": false, "error": "Failed to load script: " + script_path}

	var attached = []
	var skipped  = []

	_walk_scene(root, func(node: Node) -> void:
		# Type filter
		if node_type != "" and not node.is_class(node_type):
			return
		# Group filter
		if group_name != "" and not node.is_in_group(group_name):
			return
		# Already has script
		if node.get_script() and not overwrite:
			skipped.append(str(node.get_path()))
			return
		node.set_script(scr)
		attached.append(str(node.get_path()))
	)

	print("[BatchExtras] Attached '%s' to %d node(s) (%d skipped)" % [script_path, attached.size(), skipped.size()])
	return {
		"success": true,
		"data": {
			"script_path": script_path,
			"attached":    attached.size(),
			"skipped":     skipped.size(),
			"attached_paths": attached
		}
	}


func batch_rename_nodes(params: Dictionary) -> Dictionary:
	"""Find & replace in node names within a scene subtree. Supports regex.
	   WARNING: Renaming nodes can break NodePath references in scripts — use with care."""
	var root = _get_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var search      = params.get("search", "")
	var replacement = params.get("replacement", "")
	var root_path   = params.get("root_path", "")
	var node_type   = params.get("node_type", "")
	var use_regex   = bool(params.get("use_regex", false))

	if search == "":
		return {"success": false, "error": "search is required"}

	var search_root = root.get_node_or_null(root_path) if root_path != "" else root
	if not search_root:
		return {"success": false, "error": "root_path not found: " + root_path}

	var regex: RegEx = null
	if use_regex:
		regex = RegEx.new()
		if regex.compile(search) != OK:
			return {"success": false, "error": "Invalid regex pattern: " + search}

	var renamed: Array = []

	_walk_scene(search_root, func(node: Node) -> void:
		if node_type != "" and not node.is_class(node_type):
			return
		var old_name = node.name
		var new_name: String
		if use_regex:
			new_name = regex.sub(old_name, replacement, true)
		else:
			new_name = old_name.replace(search, replacement)
		if new_name != old_name and new_name != "":
			node.name = new_name
			renamed.append({"old": old_name, "new": str(node.name)})
	)

	print("[BatchExtras] Renamed %d node(s): '%s' → '%s'" % [renamed.size(), search, replacement])
	return {
		"success": true,
		"data": {
			"renamed": renamed.size(),
			"changes": renamed,
			"warning": "Renaming nodes may break NodePath references in scripts." if renamed.size() > 0 else ""
		}
	}


func move_and_rename_file(params: Dictionary) -> Dictionary:
	"""Move and/or rename a file in the project. Triggers a filesystem scan so references update.
	   Both paths should be res:// paths."""
	var source_path = params.get("source_path", "")
	var dest_path   = params.get("dest_path", "")

	if source_path == "" or dest_path == "":
		return {"success": false, "error": "source_path and dest_path are required (res:// paths)"}

	var source_abs = ProjectSettings.globalize_path(source_path)
	var dest_abs   = ProjectSettings.globalize_path(dest_path)

	if not FileAccess.file_exists(source_abs):
		return {"success": false, "error": "Source file not found: " + source_path}

	# Create destination directory if needed
	var dest_dir = dest_abs.get_base_dir()
	if not DirAccess.dir_exists_absolute(dest_dir):
		var err = DirAccess.make_dir_recursive_absolute(dest_dir)
		if err != OK:
			return {"success": false, "error": "Failed to create destination directory: " + dest_dir}

	var err = DirAccess.rename_absolute(source_abs, dest_abs)
	if err != OK:
		return {"success": false, "error": "Failed to rename file: error %d" % err}

	# Trigger filesystem rescan so .uid and references update
	editor_interface.get_resource_filesystem().scan()

	print("[BatchExtras] Moved '%s' → '%s'" % [source_path, dest_path])
	return {
		"success": true,
		"data": {
			"source": source_path,
			"destination": dest_path,
			"note": "Filesystem scan triggered. NodePath/preload references in scripts may need manual update."
		}
	}


func pack_scene(params: Dictionary) -> Dictionary:
	"""Save a node (and its children) as a new .tscn PackedScene file.
	   The node remains in the original scene — this creates an independent copy."""
	var root = _get_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node_path   = params.get("node_path", "")
	var output_path = params.get("output_path", "")

	if node_path == "" or output_path == "":
		return {"success": false, "error": "node_path and output_path (res:// .tscn path) are required"}

	if not output_path.ends_with(".tscn"):
		return {"success": false, "error": "output_path must end with .tscn"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	var packed = PackedScene.new()
	var result = packed.pack(node)
	if result != OK:
		return {"success": false, "error": "Failed to pack node '%s': error %d" % [node_path, result]}

	# Ensure output directory exists
	var out_abs = ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())

	var save_err = ResourceSaver.save(packed, output_path)
	if save_err != OK:
		return {"success": false, "error": "Failed to save packed scene: error %d" % save_err}

	editor_interface.get_resource_filesystem().scan()

	print("[BatchExtras] Packed '%s' → '%s'" % [node_path, output_path])
	return {
		"success": true,
		"data": {
			"node_path":   node_path,
			"output_path": output_path,
			"node_class":  node.get_class()
		}
	}


func create_resource_file(params: Dictionary) -> Dictionary:
	"""Create a .tres resource file of any Godot class (PhysicsMaterial, Environment, Sky, etc.)
	   and optionally set initial properties."""
	var resource_type = params.get("resource_type", "Resource")
	var output_path   = params.get("output_path", "")
	var properties    = params.get("properties", {})

	if output_path == "":
		return {"success": false, "error": "output_path is required (res:// path ending in .tres or .res)"}

	if not ClassDB.class_exists(resource_type):
		return {"success": false, "error": "Unknown resource type: '%s'. Examples: PhysicsMaterial, Environment, StandardMaterial3D, AudioStreamWAV" % resource_type}

	if not ClassDB.is_parent_class(resource_type, "Resource"):
		return {"success": false, "error": "'%s' is not a Resource subclass" % resource_type}

	var res: Resource = ClassDB.instantiate(resource_type)
	if not res:
		return {"success": false, "error": "Failed to instantiate: " + resource_type}

	# Apply initial properties
	var prop_errors = []
	for key in properties:
		var coerced = _coerce_value(properties[key])
		res.set(key, coerced)
		if res.get(key) == null and coerced != null:
			prop_errors.append("property '%s' may not exist on %s" % [key, resource_type])

	var out_abs = ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(out_abs.get_base_dir())

	var save_err = ResourceSaver.save(res, output_path)
	if save_err != OK:
		return {"success": false, "error": "Failed to save resource: error %d" % save_err}

	editor_interface.get_resource_filesystem().scan()

	print("[BatchExtras] Created %s → '%s'" % [resource_type, output_path])
	return {
		"success": true,
		"data": {
			"resource_type": resource_type,
			"output_path":   output_path,
			"property_warnings": prop_errors
		}
	}
