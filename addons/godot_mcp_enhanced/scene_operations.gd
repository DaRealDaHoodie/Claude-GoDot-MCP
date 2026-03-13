@tool
extends Node

var editor_interface: EditorInterface

signal scene_modified(scene_path: String)
signal node_added(node_path: String)
signal node_deleted(node_path: String)


func get_scene_tree() -> Dictionary:
	"""Get recursive tree view of all nodes in current scene"""
	var root = editor_interface.get_edited_scene_root()
	
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var tree_data = _build_node_tree(root)
	return {"success": true, "data": tree_data}


func _build_node_tree(node: Node, depth: int = 0) -> Dictionary:
	"""Recursively build node tree structure"""
	var node_data = {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"visible": node.get("visible") if "visible" in node else null,
		"script": node.get_script().resource_path if node.get_script() else null,
		"children": []
	}
	
	# Add position for 2D/3D nodes
	if node is Node2D:
		node_data["position"] = {"x": node.position.x, "y": node.position.y}
		node_data["rotation"] = node.rotation
		node_data["scale"] = {"x": node.scale.x, "y": node.scale.y}
	elif node is Node3D:
		var pos = node.position
		node_data["position"] = {"x": pos.x, "y": pos.y, "z": pos.z}
		var rot = node.rotation
		node_data["rotation"] = {"x": rot.x, "y": rot.y, "z": rot.z}
		var scl = node.scale
		node_data["scale"] = {"x": scl.x, "y": scl.y, "z": scl.z}
	
	# Add Control-specific properties
	if node is Control:
		node_data["size"] = {"x": node.size.x, "y": node.size.y}
		node_data["anchor_left"] = node.anchor_left
		node_data["anchor_top"] = node.anchor_top
		node_data["anchor_right"] = node.anchor_right
		node_data["anchor_bottom"] = node.anchor_bottom
	
	# Recursively add children
	for child in node.get_children():
		node_data["children"].append(_build_node_tree(child, depth + 1))
	
	return node_data


func get_compact_scene_tree() -> Dictionary:
	"""Get simplified scene tree for Windsurf live preview"""
	var root = editor_interface.get_edited_scene_root()
	
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var tree_data = _build_compact_node_tree(root)
	return {"success": true, "data": tree_data}


func _build_compact_node_tree(node: Node) -> Dictionary:
	"""Build compact tree with only essential info"""
	var data = {
		"name": node.name,
		"type": node.get_class(),
		"children": []
	}
	
	for child in node.get_children():
		data["children"].append(_build_compact_node_tree(child))
	
	return data


func get_scene_file_content() -> String:
	"""Get raw content of current scene file"""
	var current_scene = editor_interface.get_edited_scene_root()
	if not current_scene:
		return ""
	
	var scene_path = current_scene.scene_file_path
	if scene_path == "":
		return ""
	
	var file = FileAccess.open(scene_path, FileAccess.READ)
	if not file:
		return ""
	
	var content = file.get_as_text()
	file.close()
	return content


func create_scene(scene_path: String, root_type: String = "Node2D") -> Dictionary:
	"""Create a new scene with specified root node type"""
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	
	# Check if scene already exists
	if FileAccess.file_exists(scene_path):
		return {"success": false, "error": "Scene already exists: " + scene_path}
	
	# Create root node
	var root_node = _create_node_by_type(root_type)
	if not root_node:
		return {"success": false, "error": "Failed to create node of type: " + root_type}
	
	# Create packed scene
	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(root_node)
	
	if result != OK:
		root_node.queue_free()
		return {"success": false, "error": "Failed to pack scene: " + error_string(result)}
	
	# Save scene
	var error = ResourceSaver.save(packed_scene, scene_path)
	root_node.queue_free()
	
	if error != OK:
		return {"success": false, "error": "Failed to save scene: " + error_string(error)}
	
	# Refresh filesystem
	editor_interface.get_resource_filesystem().scan()
	
	print("[Scene Operations] Created scene: ", scene_path)
	return {"success": true, "data": {"scene_path": scene_path}}


func open_scene(scene_path: String) -> Dictionary:
	"""Open a scene in the editor"""
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "Scene not found: " + scene_path}
	
	# open_scene_from_path returns void in Godot 4.x
	editor_interface.open_scene_from_path(scene_path)
	
	# Verify it opened by checking if current scene matches
	await Engine.get_main_loop().process_frame
	var current = editor_interface.get_edited_scene_root()
	if current and current.scene_file_path == scene_path:
		print("[Scene Operations] Opened scene: ", scene_path)
		return {"success": true, "data": {"scene_path": scene_path}}
	else:
		return {"success": false, "error": "Failed to open scene (could not verify)"}


func delete_scene(scene_path: String) -> Dictionary:
	"""Delete a scene file"""
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	
	if not FileAccess.file_exists(scene_path):
		return {"success": false, "error": "Scene not found: " + scene_path}
	
	var dir = DirAccess.open("res://")
	var error = dir.remove(scene_path)
	
	if error != OK:
		return {"success": false, "error": "Failed to delete scene: " + error_string(error)}
	
	editor_interface.get_resource_filesystem().scan()
	
	print("[Scene Operations] Deleted scene: ", scene_path)
	return {"success": true, "data": {"scene_path": scene_path}}


func add_scene_as_child(scene_path: String, parent_node_path: String) -> Dictionary:
	"""Add a scene as a child node to parent"""
	if not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	# Get parent node
	var parent = root.get_node_or_null(parent_node_path) if parent_node_path else root
	if not parent:
		return {"success": false, "error": "Parent node not found: " + parent_node_path}
	
	# Load scene
	var scene = load(scene_path)
	if not scene:
		return {"success": false, "error": "Failed to load scene: " + scene_path}
	
	var instance = scene.instantiate()
	parent.add_child(instance)
	instance.owner = root
	
	emit_signal("node_added", str(instance.get_path()))
	print("[Scene Operations] Added scene as child: ", scene_path)
	
	return {"success": true, "data": {"node_path": str(instance.get_path())}}


func play_scene(scene_path: String = "") -> Dictionary:
	"""Play scene in Godot"""
	if scene_path != "" and not scene_path.begins_with("res://"):
		scene_path = "res://" + scene_path
	
	if scene_path != "":
		editor_interface.play_custom_scene(scene_path)
	else:
		editor_interface.play_current_scene()
	
	print("[Scene Operations] Playing scene: ", scene_path if scene_path else "current")
	return {"success": true}


func stop_running_scene() -> Dictionary:
	"""Stop the currently running scene"""
	editor_interface.stop_playing_scene()
	print("[Scene Operations] Stopped running scene")
	return {"success": true}


func add_node(params: Dictionary) -> Dictionary:
	"""Add a node to the current scene"""
	var node_type = params.get("node_type", "")
	var node_name = params.get("node_name", "")
	var parent_path = params.get("parent_node_path", "")
	var properties = params.get("properties", {})
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	# Get parent node
	var parent = root.get_node_or_null(parent_path) if parent_path else root
	if not parent:
		return {"success": false, "error": "Parent node not found: " + parent_path}
	
	# Create node
	var new_node = _create_node_by_type(node_type)
	if not new_node:
		return {"success": false, "error": "Failed to create node of type: " + node_type}
	
	new_node.name = node_name
	parent.add_child(new_node)
	new_node.owner = root
	
	# Set properties
	for prop_name in properties:
		if prop_name in new_node:
			new_node.set(prop_name, properties[prop_name])
	
	emit_signal("node_added", str(new_node.get_path()))
	print("[Scene Operations] Added node: ", new_node.get_path())
	
	return {"success": true, "data": {"node_path": str(new_node.get_path())}}


func delete_node(params: Dictionary) -> Dictionary:
	"""Delete a node from the scene"""
	var node_path = params.get("node_path", "")
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	if node == root:
		return {"success": false, "error": "Cannot delete root node"}
	
	emit_signal("node_deleted", node_path)
	node.queue_free()
	
	print("[Scene Operations] Deleted node: ", node_path)
	return {"success": true}


func duplicate_node(params: Dictionary) -> Dictionary:
	"""Duplicate an existing node"""
	var node_path = params.get("node_path", "")
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	var duplicate = node.duplicate(DUPLICATE_USE_INSTANTIATION)
	node.get_parent().add_child(duplicate)
	duplicate.owner = root
	
	emit_signal("node_added", str(duplicate.get_path()))
	print("[Scene Operations] Duplicated node: ", node_path)
	
	return {"success": true, "data": {"node_path": str(duplicate.get_path())}}


func move_node(params: Dictionary) -> Dictionary:
	"""Move a node to a different parent"""
	var node_path = params.get("node_path", "")
	var new_parent_path = params.get("new_parent_path", "")
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	var new_parent = root.get_node_or_null(new_parent_path)
	if not new_parent:
		return {"success": false, "error": "New parent not found: " + new_parent_path}
	
	node.reparent(new_parent)
	
	print("[Scene Operations] Moved node: ", node_path, " to ", new_parent_path)
	return {"success": true, "data": {"node_path": str(node.get_path())}}


func update_property(params: Dictionary) -> Dictionary:
	"""Update a property of a node"""
	var node_path = params.get("node_path", "")
	var property_name = params.get("property", "")
	var property_value = params.get("value")
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	if not property_name in node:
		return {"success": false, "error": "Property not found: " + property_name}
	
	node.set(property_name, property_value)
	
	emit_signal("scene_modified", "")
	print("[Scene Operations] Updated property: ", node_path, ".", property_name)
	
	return {"success": true}


func add_resource(params: Dictionary) -> Dictionary:
	"""Add a resource to a node property"""
	var node_path = params.get("node_path", "")
	var resource_type = params.get("resource_type", "")
	var property_name = params.get("property", "")
	var resource_properties = params.get("resource_properties", {})
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}
	
	# Create resource
	var resource = ClassDB.instantiate(resource_type)
	if not resource:
		return {"success": false, "error": "Failed to create resource of type: " + resource_type}
	
	# Set resource properties
	for prop in resource_properties:
		if prop in resource:
			resource.set(prop, resource_properties[prop])
	
	# Assign to node
	node.set(property_name, resource)
	
	emit_signal("scene_modified", "")
	print("[Scene Operations] Added resource: ", resource_type, " to ", node_path)
	
	return {"success": true}


func set_anchor_preset(params: Dictionary) -> Dictionary:
	"""Set anchor preset for Control node"""
	var node_path = params.get("node_path", "")
	var preset = params.get("preset", "top_left")
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node or not node is Control:
		return {"success": false, "error": "Node is not a Control: " + node_path}
	
	var preset_value = _get_anchor_preset_value(preset)
	node.set_anchors_preset(preset_value)
	
	print("[Scene Operations] Set anchor preset: ", preset, " for ", node_path)
	return {"success": true}


func set_anchor_values(params: Dictionary) -> Dictionary:
	"""Set precise anchor values for Control node"""
	var node_path = params.get("node_path", "")
	
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	
	var node = root.get_node_or_null(node_path)
	if not node or not node is Control:
		return {"success": false, "error": "Node is not a Control: " + node_path}
	
	if params.has("anchor_left"):
		node.anchor_left = params["anchor_left"]
	if params.has("anchor_top"):
		node.anchor_top = params["anchor_top"]
	if params.has("anchor_right"):
		node.anchor_right = params["anchor_right"]
	if params.has("anchor_bottom"):
		node.anchor_bottom = params["anchor_bottom"]
	
	print("[Scene Operations] Set anchor values for ", node_path)
	return {"success": true}


func _create_node_by_type(type_name: String) -> Node:
	"""Create a node instance by type name"""
	if ClassDB.class_exists(type_name):
		return ClassDB.instantiate(type_name)
	return null


func _get_anchor_preset_value(preset_name: String) -> int:
	"""Convert preset name to Control.LayoutPreset enum"""
	match preset_name:
		"top_left": return Control.PRESET_TOP_LEFT
		"top_right": return Control.PRESET_TOP_RIGHT
		"bottom_left": return Control.PRESET_BOTTOM_LEFT
		"bottom_right": return Control.PRESET_BOTTOM_RIGHT
		"center_left": return Control.PRESET_CENTER_LEFT
		"center_top": return Control.PRESET_CENTER_TOP
		"center_right": return Control.PRESET_CENTER_RIGHT
		"center_bottom": return Control.PRESET_CENTER_BOTTOM
		"center": return Control.PRESET_CENTER
		"left_wide": return Control.PRESET_LEFT_WIDE
		"top_wide": return Control.PRESET_TOP_WIDE
		"right_wide": return Control.PRESET_RIGHT_WIDE
		"bottom_wide": return Control.PRESET_BOTTOM_WIDE
		"vcenter_wide": return Control.PRESET_VCENTER_WIDE
		"hcenter_wide": return Control.PRESET_HCENTER_WIDE
		"full_rect": return Control.PRESET_FULL_RECT
		_: return Control.PRESET_TOP_LEFT


func save_scene() -> Dictionary:
	"""Save the current open scene to disk"""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var scene_path = root.scene_file_path
	if scene_path == "":
		return {"success": false, "error": "Scene has no file path (use save_scene_as)"}

	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err != OK:
		return {"success": false, "error": "Failed to pack scene: " + error_string(err)}

	err = ResourceSaver.save(packed, scene_path)
	if err != OK:
		return {"success": false, "error": "Failed to save scene: " + error_string(err)}

	editor_interface.get_resource_filesystem().scan()
	print("[Scene Operations] Saved scene: ", scene_path)
	return {"success": true, "data": {"scene_path": scene_path}}


func rename_node(params: Dictionary) -> Dictionary:
	"""Rename a node in the current scene"""
	var node_path = params.get("node_path", "")
	var new_name = params.get("new_name", "")

	if new_name == "":
		return {"success": false, "error": "new_name cannot be empty"}

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	if node == root:
		return {"success": false, "error": "Cannot rename root node via this tool"}

	var old_name = node.name
	node.name = new_name

	print("[Scene Operations] Renamed node: ", old_name, " -> ", new_name)
	return {"success": true, "data": {"old_name": old_name, "new_name": node.name, "new_path": str(node.get_path())}}


func reorder_node(params: Dictionary) -> Dictionary:
	"""Move a node to a specific child index within its parent"""
	var node_path = params.get("node_path", "")
	var new_index = params.get("new_index", 0)

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	var parent = node.get_parent()
	if not parent:
		return {"success": false, "error": "Node has no parent"}

	parent.move_child(node, new_index)

	print("[Scene Operations] Reordered node: ", node_path, " to index ", new_index)
	return {"success": true, "data": {"node_path": str(node.get_path()), "new_index": node.get_index()}}


func find_nodes(params: Dictionary) -> Dictionary:
	"""Find all nodes in the scene matching type and/or name pattern"""
	var node_type = params.get("node_type", "")
	var name_pattern = params.get("name_pattern", "")
	var recursive = params.get("recursive", true)

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var found = []
	_find_nodes_recursive(root, node_type, name_pattern, found)

	return {"success": true, "data": {"nodes": found, "count": found.size()}}


func _find_nodes_recursive(node: Node, node_type: String, name_pattern: String, found: Array) -> void:
	var type_match = node_type == "" or node.is_class(node_type)
	var name_match = name_pattern == "" or node.name.match(name_pattern)

	if type_match and name_match:
		found.append({
			"name": node.name,
			"type": node.get_class(),
			"path": str(node.get_path())
		})

	for child in node.get_children():
		_find_nodes_recursive(child, node_type, name_pattern, found)


func get_node_signals(params: Dictionary) -> Dictionary:
	"""List all signals available on a node"""
	var node_path = params.get("node_path", "")
	var include_inherited = params.get("include_inherited", true)

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	var signals = []
	for sig in node.get_signal_list():
		signals.append({
			"name": sig.name,
			"args": sig.args
		})

	# Also get connections
	var connections = []
	for sig in node.get_signal_list():
		for conn in node.get_signal_connection_list(sig.name):
			connections.append({
				"signal": sig.name,
				"target": str(conn.callable.get_object()),
				"method": conn.callable.get_method(),
				"flags": conn.flags
			})

	return {
		"success": true,
		"data": {
			"node_path": node_path,
			"node_type": node.get_class(),
			"signals": signals,
			"connections": connections
		}
	}


func connect_signal(params: Dictionary) -> Dictionary:
	"""Connect a signal from source node to a method on target node"""
	var source_path = params.get("source_node_path", "")
	var signal_name = params.get("signal_name", "")
	var target_path = params.get("target_node_path", "")
	var method_name = params.get("method_name", "")

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var source = root.get_node_or_null(source_path)
	if not source:
		return {"success": false, "error": "Source node not found: " + source_path}

	var target = root.get_node_or_null(target_path)
	if not target:
		return {"success": false, "error": "Target node not found: " + target_path}

	if not source.has_signal(signal_name):
		return {"success": false, "error": "Signal '%s' not found on %s" % [signal_name, source_path]}

	if not target.has_method(method_name):
		return {"success": false, "error": "Method '%s' not found on %s" % [method_name, target_path]}

	if source.is_connected(signal_name, Callable(target, method_name)):
		return {"success": false, "error": "Signal already connected"}

	source.connect(signal_name, Callable(target, method_name))

	print("[Scene Operations] Connected signal: ", source_path, ".", signal_name, " -> ", target_path, ".", method_name)
	return {"success": true, "data": {"source": source_path, "signal": signal_name, "target": target_path, "method": method_name}}


func disconnect_signal(params: Dictionary) -> Dictionary:
	"""Disconnect a signal connection"""
	var source_path = params.get("source_node_path", "")
	var signal_name = params.get("signal_name", "")
	var target_path = params.get("target_node_path", "")
	var method_name = params.get("method_name", "")

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var source = root.get_node_or_null(source_path)
	if not source:
		return {"success": false, "error": "Source node not found: " + source_path}

	var target = root.get_node_or_null(target_path)
	if not target:
		return {"success": false, "error": "Target node not found: " + target_path}

	if not source.is_connected(signal_name, Callable(target, method_name)):
		return {"success": false, "error": "Signal is not connected"}

	source.disconnect(signal_name, Callable(target, method_name))

	print("[Scene Operations] Disconnected signal: ", source_path, ".", signal_name, " -> ", target_path, ".", method_name)
	return {"success": true}


func add_node_to_group(params: Dictionary) -> Dictionary:
	var node_path = params.get("node_path", "")
	var group_name = params.get("group_name", "")

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	node.add_to_group(StringName(group_name), true)  # persistent=true so it's saved in scene

	print("[Scene Operations] Added node to group: ", node_path, " -> ", group_name)
	return {"success": true, "data": {"node_path": node_path, "group": group_name}}


func remove_node_from_group(params: Dictionary) -> Dictionary:
	var node_path = params.get("node_path", "")
	var group_name = params.get("group_name", "")

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	if not node.is_in_group(StringName(group_name)):
		return {"success": false, "error": "Node is not in group: " + group_name}

	node.remove_from_group(StringName(group_name))

	print("[Scene Operations] Removed node from group: ", node_path, " <- ", group_name)
	return {"success": true}


func get_node_groups(params: Dictionary) -> Dictionary:
	"""Get all groups a node belongs to"""
	var node_path = params.get("node_path", "")

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	return {"success": true, "data": {"node_path": node_path, "groups": node.get_groups()}}


func batch_set_properties(params: Dictionary) -> Dictionary:
	"""Set multiple properties on multiple nodes at once"""
	# params.operations = [{node_path, property, value}, ...]
	var operations = params.get("operations", [])

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var results = []
	var errors = []

	for op in operations:
		var node_path = op.get("node_path", "")
		var property = op.get("property", "")
		var value = op.get("value")

		var node = root.get_node_or_null(node_path)
		if not node:
			errors.append("Node not found: " + node_path)
			continue

		if not property in node:
			errors.append("Property '%s' not found on %s" % [property, node_path])
			continue

		node.set(property, value)
		results.append({"node": node_path, "property": property, "set": true})

	emit_signal("scene_modified", "")
	return {
		"success": errors.size() == 0,
		"data": {"applied": results, "errors": errors}
	}


func get_class_property_list(params: Dictionary) -> Dictionary:
	"""Get all available properties for a Godot class by name"""
	var class_name_str = params.get("class_name", "")

	if class_name_str == "":
		return {"success": false, "error": "class_name is required"}

	if not ClassDB.class_exists(class_name_str):
		return {"success": false, "error": "Class not found: " + class_name_str}

	var props = []
	for p in ClassDB.class_get_property_list(class_name_str, false):
		if p.usage & PROPERTY_USAGE_EDITOR:
			props.append({
				"name": p.name,
				"type": type_string(p.type),
				"hint": p.hint,
				"hint_string": p.hint_string,
				"usage": p.usage
			})

	return {
		"success": true,
		"data": {
			"class_name": class_name_str,
			"parent_class": ClassDB.get_parent_class(class_name_str),
			"properties": props,
			"count": props.size()
		}
	}


func set_shader_parameter(params: Dictionary) -> Dictionary:
	"""Set a parameter on a ShaderMaterial attached to a node"""
	var node_path = params.get("node_path", "")
	var param_name = params.get("param_name", "")
	var value = params.get("value")
	var surface_index = params.get("surface_index", 0)

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var node = root.get_node_or_null(node_path)
	if not node:
		return {"success": false, "error": "Node not found: " + node_path}

	# Resolve the material from the node using multiple strategies
	var material: Material = null

	# MeshInstance3D / CSGShape3D — surface override first, then mesh material
	if node.has_method("get_surface_override_material"):
		material = node.get_surface_override_material(surface_index)
	if not material and node.has_method("get_active_mesh") and node.get_active_mesh():
		material = node.get_active_mesh().surface_get_material(surface_index)

	# Node3D material_override (works on any VisualInstance3D)
	if not material and "material_override" in node and node.material_override:
		material = node.material_override

	# 2D / CanvasItem: material property
	if not material and "material" in node and node.material:
		material = node.material

	if not material:
		return {"success": false, "error": "No material found on node '%s'. Set a ShaderMaterial first." % node_path}

	if not material is ShaderMaterial:
		return {"success": false, "error": "Material is %s, not ShaderMaterial. Convert it first." % material.get_class()}

	# Convert array values to Godot vector/color types automatically
	var typed_value = _coerce_shader_value(value)
	material.set_shader_parameter(param_name, typed_value)

	emit_signal("scene_modified", "")
	print("[Scene Operations] Shader param set: %s.%s = %s" % [node_path, param_name, str(typed_value)])
	return {"success": true, "data": {"node_path": node_path, "param": param_name, "value": str(typed_value)}}


func _coerce_shader_value(value) -> Variant:
	"""Convert JSON array values to Godot vector/color types for shader params"""
	if not value is Array:
		return value
	match value.size():
		2: return Vector2(value[0], value[1])
		3: return Vector3(value[0], value[1], value[2])
		4: return Color(value[0], value[1], value[2], value[3])
		_: return value


func scan_broken_resources() -> Dictionary:
	"""Scan all .tscn/.tres/.res files for broken res:// references"""
	var broken = []
	_scan_for_broken_refs("res://", broken)

	# Deduplicate by (file, missing_ref) pair
	var seen = {}
	var unique_broken = []
	for entry in broken:
		var key = entry["file"] + "|" + entry["missing_ref"]
		if not seen.has(key):
			seen[key] = true
			unique_broken.append(entry)

	return {
		"success": true,
		"data": {
			"broken_count": unique_broken.size(),
			"broken_refs": unique_broken,
			"message": "Run after moving/renaming assets. Fix by updating references or re-importing."
		}
	}


func _scan_for_broken_refs(path: String, broken: Array) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var item = dir.get_next()
	while item != "":
		if not item.begins_with("."):
			var full = path.path_join(item)
			if dir.current_is_dir():
				_scan_for_broken_refs(full, broken)
			else:
				var ext = item.get_extension().to_lower()
				if ext in ["tscn", "tres", "res"]:
					_check_file_for_broken_refs(full, broken)
		item = dir.get_next()
	dir.list_dir_end()


func _check_file_for_broken_refs(file_path: String, broken: Array) -> void:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return
	var content = file.get_as_text()
	file.close()

	var regex = RegEx.new()
	# Match res:// paths (stop at quote, whitespace, comma, closing paren/bracket)
	regex.compile('res://[^"\\s,)\\]]+')
	var matches = regex.search_all(content)

	for m in matches:
		var ref_path = m.get_string()
		# Skip metadata files — they're generated and may not exist as standalone files
		if ref_path.ends_with(".import") or ref_path.ends_with(".uid"):
			continue
		# Check if the referenced file exists
		if not FileAccess.file_exists(ref_path):
			broken.append({"file": file_path, "missing_ref": ref_path})


# ── Navigation Mesh Baking ────────────────────────────────────────────────────

func bake_navigation_mesh(params: Dictionary) -> Dictionary:
	"""Bake NavigationRegion2D/3D navigation meshes. Bakes all found if no node_path given."""
	var node_path = params.get("node_path", "")

	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	if node_path != "":
		# Bake a specific navigation region
		var node = root.get_node_or_null(node_path)
		if not node:
			# Also try absolute path from tree root
			node = root.get_tree().root.get_node_or_null(node_path)
		if not node:
			return {"success": false, "error": "Node not found: " + node_path}

		if node is NavigationRegion3D:
			node.bake_navigation_mesh()
			await node.bake_finished
			return {"success": true, "data": {
				"baked": [{"path": node_path, "type": "NavigationRegion3D"}], "count": 1
			}}
		elif node is NavigationRegion2D:
			node.bake_navigation_polygon()
			return {"success": true, "data": {
				"baked": [{"path": node_path, "type": "NavigationRegion2D"}], "count": 1
			}}
		else:
			return {"success": false, "error": "Node '%s' is %s, not NavigationRegion2D/3D" % [node_path, node.get_class()]}

	# Auto-discover and bake all navigation regions in scene
	var baked = []
	_bake_nav_recursive(root, baked)

	if baked.is_empty():
		return {"success": false, "error": "No NavigationRegion2D or NavigationRegion3D nodes found in scene"}

	print("[Scene Operations] Baked %d navigation region(s)" % baked.size())
	return {"success": true, "data": {"baked": baked, "count": baked.size()}}


func _bake_nav_recursive(node: Node, baked: Array) -> void:
	if node is NavigationRegion3D:
		node.bake_navigation_mesh()
		baked.append({"path": str(node.get_path()), "type": "NavigationRegion3D"})
	elif node is NavigationRegion2D:
		node.bake_navigation_polygon()
		baked.append({"path": str(node.get_path()), "type": "NavigationRegion2D"})
	for child in node.get_children():
		_bake_nav_recursive(child, baked)
