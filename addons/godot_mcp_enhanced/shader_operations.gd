@tool
extends Node

## Shader Operations for Claude-GoDot-MCP
## Covers ShaderMaterial creation, shader code hot-reload, and uniform inspection.
## (Shader parameter *setting* is in scene_operations.gd via set_shader_parameter)

var editor_interface: EditorInterface


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_node(params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	var path = params.get("node_path", "")
	if path == "":
		return {"success": false, "error": "node_path is required"}
	var node = root.get_node_or_null(path)
	if not node:
		return {"success": false, "error": "Node not found: " + path}
	return {"success": true, "node": node}


func _get_material(node: Node, slot: int = 0) -> Material:
	"""Try multiple strategies to get a material from a node."""
	# MeshInstance3D: surface override first, then mesh's own material
	if node is MeshInstance3D:
		var mat = node.get_surface_override_material(slot)
		if mat: return mat
		if node.material_override: return node.material_override
		if node.mesh: return node.mesh.surface_get_material(slot)

	# GeometryInstance3D fallback
	if node is GeometryInstance3D:
		if node.material_override: return node.material_override

	# 2D / billboard / etc.
	if node.get("material") != null:
		return node.material

	return null


func _set_material(node: Node, mat: Material, slot: int = 0) -> void:
	"""Assign a material to the appropriate slot on a node."""
	if node is MeshInstance3D:
		node.set_surface_override_material(slot, mat)
	elif node is GeometryInstance3D:
		node.material_override = mat
	elif node.get("material") != null:
		node.material = mat


func _variant_to_json(v: Variant) -> Variant:
	if v is Vector2:    return [v.x, v.y]
	if v is Vector3:    return [v.x, v.y, v.z]
	if v is Vector4:    return [v.x, v.y, v.z, v.w]
	if v is Color:      return [v.r, v.g, v.b, v.a]
	if v is Transform3D: return {"origin": [v.origin.x, v.origin.y, v.origin.z]}
	return v


# ── Shader Tools ──────────────────────────────────────────────────────────────

func create_shader_material(params: Dictionary) -> Dictionary:
	"""Create a ShaderMaterial with the given GLSL code and assign it to a node's material slot."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	var shader_code = params.get("shader_code", "")
	var slot = int(params.get("surface_slot", 0))

	if shader_code == "":
		return {"success": false, "error": "shader_code is required (valid Godot shader source starting with 'shader_type spatial;' or 'shader_type canvas_item;')"}

	var shader = Shader.new()
	shader.code = shader_code

	var mat = ShaderMaterial.new()
	mat.shader = shader

	_set_material(node, mat, slot)

	print("[Shader] Created ShaderMaterial on '%s' (slot=%d)" % [params.get("node_path"), slot])
	return {
		"success": true,
		"data": {
			"node_path": params.get("node_path"),
			"surface_slot": slot,
			"shader_type": "canvas_item" if "shader_type: canvas_item" in shader_code else "spatial"
		}
	}


func get_shader_code(params: Dictionary) -> Dictionary:
	"""Read the GLSL source code of a ShaderMaterial on a node."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	var slot = int(params.get("surface_slot", 0))
	var mat = _get_material(node, slot)

	if not mat:
		return {"success": false, "error": "No material found on '%s' (slot %d)" % [params.get("node_path"), slot]}
	if not mat is ShaderMaterial:
		return {"success": false, "error": "Material is %s, not ShaderMaterial" % mat.get_class()}
	if not mat.shader:
		return {"success": false, "error": "ShaderMaterial has no Shader assigned"}

	return {
		"success": true,
		"data": {
			"shader_code": mat.shader.code,
			"node_path": params.get("node_path"),
			"surface_slot": slot
		}
	}


func set_shader_code(params: Dictionary) -> Dictionary:
	"""Hot-reload shader code on a node — creates a ShaderMaterial if none exists."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	var slot = int(params.get("surface_slot", 0))
	var new_code = params.get("shader_code", "")

	if new_code == "":
		return {"success": false, "error": "shader_code is required"}

	var mat = _get_material(node, slot)

	if not mat or not mat is ShaderMaterial:
		# Create new ShaderMaterial
		var shader = Shader.new()
		shader.code = new_code
		mat = ShaderMaterial.new()
		mat.shader = shader
		_set_material(node, mat, slot)
	else:
		if not mat.shader:
			mat.shader = Shader.new()
		mat.shader.code = new_code

	print("[Shader] Hot-reloaded shader on '%s' (slot=%d)" % [params.get("node_path"), slot])
	return {
		"success": true,
		"data": {"node_path": params.get("node_path"), "surface_slot": slot}
	}


func get_shader_parameters(params: Dictionary) -> Dictionary:
	"""List all uniforms declared in a ShaderMaterial's shader, with their current values."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	var slot = int(params.get("surface_slot", 0))
	var mat = _get_material(node, slot)

	if not mat:
		return {"success": false, "error": "No material found on '%s'" % params.get("node_path")}
	if not mat is ShaderMaterial:
		return {"success": false, "error": "Material is %s, not ShaderMaterial" % mat.get_class()}
	if not mat.shader:
		return {"success": false, "error": "ShaderMaterial has no Shader assigned"}

	# Use Shader.get_shader_uniform_list() — the Godot 4.x API
	var uniform_list = mat.shader.get_shader_uniform_list()
	var result = []
	for uniform in uniform_list:
		var name = uniform.get("name", "")
		var current_val = mat.get_shader_parameter(name)
		result.append({
			"name":          name,
			"type":          uniform.get("type", -1),
			"hint":          uniform.get("hint", 0),
			"hint_string":   uniform.get("hint_string", ""),
			"current_value": _variant_to_json(current_val)
		})

	return {
		"success": true,
		"data": {
			"parameters": result,
			"count": result.size(),
			"node_path": params.get("node_path"),
			"surface_slot": slot
		}
	}
