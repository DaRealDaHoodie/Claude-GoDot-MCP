@tool
extends Node

## Batch Operations for Claude-GoDot-MCP
## Covers bulk property setting by type/group, script-wide find/replace, and multi-node creation.

var editor_interface: EditorInterface


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_root() -> Node:
	return editor_interface.get_edited_scene_root()


func _collect_by_type(root: Node, type_name: String) -> Array:
	var result: Array = []
	var queue: Array = [root]
	while not queue.is_empty():
		var node = queue.pop_front()
		if node.get_class() == type_name or node.is_class(type_name):
			result.append(node)
		queue += node.get_children()
	return result


func _collect_by_group(root: Node, group_name: String) -> Array:
	var result: Array = []
	var queue: Array = [root]
	while not queue.is_empty():
		var node = queue.pop_front()
		if node.is_in_group(group_name):
			result.append(node)
		queue += node.get_children()
	return result


func _coerce_value(v) -> Variant:
	"""Coerce JSON array → Vector2/3/Color for property setting."""
	if not v is Array:
		return v
	match v.size():
		2: return Vector2(float(v[0]), float(v[1]))
		3: return Vector3(float(v[0]), float(v[1]), float(v[2]))
		4: return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return v


# ── Batch Tools ───────────────────────────────────────────────────────────────

func batch_set_property_on_type(params: Dictionary) -> Dictionary:
	"""Set a property on every node of a given Godot class in the scene.
	   Use for: set all Light3D energy to 1.5, enable all CollisionShape3D, etc."""
	var root = _get_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node_type = params.get("node_type", "")
	var property  = params.get("property", "")
	var value     = params.get("value")

	if node_type == "" or property == "":
		return {"success": false, "error": "node_type and property are required"}

	var nodes   = _collect_by_type(root, node_type)
	var updated = []
	var errors  = []
	var coerced = _coerce_value(value)

	for node in nodes:
		if node.get(property) != null or node.has_method("set_" + property):
			node.set(property, coerced)
			updated.append(str(node.get_path()))
		else:
			errors.append({"path": str(node.get_path()), "error": "property '%s' not found" % property})

	print("[Batch] Set %s.%s = %s on %d/%d nodes" % [node_type, property, str(coerced), updated.size(), nodes.size()])
	return {
		"success": true,
		"data": {
			"node_type": node_type, "property": property,
			"updated": updated.size(), "errors": errors.size(),
			"updated_paths": updated, "error_details": errors
		}
	}


func batch_set_property_on_group(params: Dictionary) -> Dictionary:
	"""Set a property on every node that belongs to a named group in the scene."""
	var root = _get_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var group_name = params.get("group_name", "")
	var property   = params.get("property", "")
	var value      = params.get("value")

	if group_name == "" or property == "":
		return {"success": false, "error": "group_name and property are required"}

	var nodes   = _collect_by_group(root, group_name)
	if nodes.is_empty():
		return {"success": false, "error": "No nodes found in group '%s'" % group_name}

	var updated = []
	var errors  = []
	var coerced = _coerce_value(value)

	for node in nodes:
		node.set(property, coerced)
		updated.append(str(node.get_path()))

	print("[Batch] Set .%s = %s on %d nodes in group '%s'" % [property, str(coerced), updated.size(), group_name])
	return {
		"success": true,
		"data": {
			"group_name": group_name, "property": property,
			"updated": updated.size(), "updated_paths": updated
		}
	}


func replace_in_all_scripts(params: Dictionary) -> Dictionary:
	"""Find & replace text or regex across all .gd script files in the project.
	   Supports dry_run mode to preview changes without writing."""
	var search      = params.get("search", "")
	var replacement = params.get("replacement", "")
	var use_regex   = bool(params.get("use_regex", false))
	var dry_run     = bool(params.get("dry_run", false))
	var include_addons = bool(params.get("include_addons", false))

	if search == "":
		return {"success": false, "error": "search is required"}

	var project_root = ProjectSettings.globalize_path("res://")
	var results: Array = []
	var total_files   = 0
	var total_changes = 0

	_replace_in_dir(project_root, project_root, search, replacement, use_regex, dry_run, include_addons, results, total_files, total_changes)

	print("[Batch] replace_in_scripts: '%s' → '%s' in %d file(s), %d change(s)%s" % [
		search, replacement, results.size(), total_changes, " (DRY RUN)" if dry_run else ""
	])
	return {
		"success": true,
		"data": {
			"search": search, "replacement": replacement,
			"dry_run": dry_run, "use_regex": use_regex,
			"files_modified": results.size(),
			"total_replacements": total_changes,
			"files": results
		}
	}


func _replace_in_dir(dir_path: String, project_root: String, search: String, replacement: String,
					  use_regex: bool, dry_run: bool, include_addons: bool,
					  results: Array, total_files: int, total_changes: int) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir: return

	var regex: RegEx = null
	if use_regex:
		regex = RegEx.new()
		if regex.compile(search) != OK: return

	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full = dir_path + "/" + fname
		if dir.current_is_dir():
			if fname == "addons" and not include_addons:
				fname = dir.get_next()
				continue
			_replace_in_dir(full, project_root, search, replacement, use_regex, dry_run, include_addons, results, total_files, total_changes)
		elif fname.ends_with(".gd"):
			var f = FileAccess.open(full, FileAccess.READ)
			if not f:
				fname = dir.get_next()
				continue
			var original = f.get_as_text()
			f.close()

			var modified: String
			var change_count: int
			if use_regex:
				var matches = regex.search_all(original)
				change_count = matches.size()
				modified = regex.sub(original, replacement, true)
			else:
				change_count = original.count(search)
				modified = original.replace(search, replacement)

			if change_count > 0:
				var res_path = "res://" + full.trim_prefix(project_root).trim_prefix("/")
				results.append({"file": res_path, "replacements": change_count})
				total_changes += change_count
				if not dry_run:
					var wf = FileAccess.open(full, FileAccess.WRITE)
					if wf:
						wf.store_string(modified)
						wf.close()
		fname = dir.get_next()
	dir.list_dir_end()


func batch_create_nodes(params: Dictionary) -> Dictionary:
	"""Create multiple nodes in one call. Each entry specifies type, name, parent_path,
	   properties (with array→Vector coercion), and optional script path."""
	var root = _get_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var nodes_spec = params.get("nodes", [])
	if nodes_spec.is_empty():
		return {"success": false, "error": "nodes array is required. Each entry: {type, name, parent_path, properties: {}, script: ''}"}

	var created = []
	var errors  = []

	for spec in nodes_spec:
		var type_name   = spec.get("type", "Node")
		var node_name   = spec.get("name", type_name)
		var parent_path = spec.get("parent_path", "")
		var props       = spec.get("properties", {})
		var script_path = spec.get("script", "")

		var parent = root.get_node_or_null(parent_path) if parent_path != "" else root
		if not parent:
			errors.append({"name": node_name, "error": "Parent not found: " + parent_path})
			continue

		# ClassDB instantiation
		if not ClassDB.class_exists(type_name):
			errors.append({"name": node_name, "error": "Unknown class: " + type_name})
			continue

		var node = ClassDB.instantiate(type_name)
		node.name = node_name
		parent.add_child(node)
		node.owner = root

		# Apply properties
		for key in props:
			node.set(key, _coerce_value(props[key]))

		# Attach script
		if script_path != "" and ResourceLoader.exists(script_path):
			var scr = load(script_path)
			if scr:
				node.set_script(scr)

		created.append(str(node.get_path()))

	print("[Batch] Created %d node(s), %d error(s)" % [created.size(), errors.size()])
	return {
		"success": true,
		"data": {
			"created": created.size(),
			"errors":  errors.size(),
			"created_paths": created,
			"error_details": errors
		}
	}
