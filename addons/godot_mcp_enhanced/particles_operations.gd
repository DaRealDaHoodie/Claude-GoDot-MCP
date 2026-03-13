@tool
extends Node

## Particles Operations for Claude-GoDot-MCP
## Covers GPUParticles3D / CPUParticles3D creation, material parameters, and control.

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


func _emission_shape_enum(name: String) -> int:
	match name.to_lower():
		"sphere":          return ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		"sphere_surface":  return ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
		"box":             return ParticleProcessMaterial.EMISSION_SHAPE_BOX
		"ring":            return ParticleProcessMaterial.EMISSION_SHAPE_RING
		_:                 return ParticleProcessMaterial.EMISSION_SHAPE_POINT


func _coerce_value(v, key: String) -> Variant:
	"""Coerce JSON arrays to the right Godot type based on context."""
	if not v is Array:
		return v
	match v.size():
		2:
			if "color" in key.to_lower(): return Color(v[0], v[1], 0.0, 1.0)
			return Vector2(v[0], v[1])
		3:
			if "color" in key.to_lower(): return Color(v[0], v[1], v[2], 1.0)
			return Vector3(v[0], v[1], v[2])
		4:
			return Color(v[0], v[1], v[2], v[3])
	return v


# ── Particle Tools ────────────────────────────────────────────────────────────

func create_particles(params: Dictionary) -> Dictionary:
	"""Create a GPUParticles3D node with a configured ParticleProcessMaterial in one call."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var parent_path   = params.get("parent_path", "")
	var particle_name = params.get("particle_name", "GPUParticles3D")
	var amount        = int(params.get("amount", 100))
	var lifetime      = float(params.get("lifetime", 1.0))
	var one_shot      = bool(params.get("one_shot", false))
	var explosiveness = float(params.get("explosiveness", 0.0))
	var emission_shape = params.get("emission_shape", "point")

	var parent = root.get_node_or_null(parent_path) if parent_path != "" else root
	if not parent:
		return {"success": false, "error": "Parent not found: " + parent_path}

	var particles = GPUParticles3D.new()
	particles.name = particle_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.explosiveness = explosiveness
	particles.emitting = true

	if params.has("position"):
		var p = params["position"]
		if p is Array and p.size() >= 3:
			particles.position = Vector3(float(p[0]), float(p[1]), float(p[2]))

	parent.add_child(particles)
	particles.owner = root

	# Build ParticleProcessMaterial from params
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = _emission_shape_enum(emission_shape)

	if params.has("emission_sphere_radius"):
		mat.emission_sphere_radius = float(params["emission_sphere_radius"])
	if params.has("emission_box_extents"):
		var e = params["emission_box_extents"]
		if e is Array and e.size() >= 3:
			mat.emission_box_extents = Vector3(float(e[0]), float(e[1]), float(e[2]))
	if params.has("gravity"):
		var g = params["gravity"]
		if g is Array and g.size() >= 3:
			mat.gravity = Vector3(float(g[0]), float(g[1]), float(g[2]))
	if params.has("initial_velocity_min"):
		mat.initial_velocity_min = float(params["initial_velocity_min"])
	if params.has("initial_velocity_max"):
		mat.initial_velocity_max = float(params["initial_velocity_max"])
	if params.has("scale_min"):
		mat.scale_min = float(params["scale_min"])
	if params.has("scale_max"):
		mat.scale_max = float(params["scale_max"])
	if params.has("color"):
		var c = params["color"]
		if c is Array and c.size() >= 3:
			mat.color = Color(c[0], c[1], c[2], c[3] if c.size() >= 4 else 1.0)
	if params.has("direction"):
		var d = params["direction"]
		if d is Array and d.size() >= 3:
			mat.direction = Vector3(float(d[0]), float(d[1]), float(d[2]))
	if params.has("spread"):
		mat.spread = float(params["spread"])
	if params.has("linear_accel_min"):
		mat.linear_accel_min = float(params["linear_accel_min"])
	if params.has("linear_accel_max"):
		mat.linear_accel_max = float(params["linear_accel_max"])

	particles.process_material = mat

	print("[Particles] Created GPUParticles3D '%s' (amount=%d, lifetime=%.1f, shape=%s)" % [particle_name, amount, lifetime, emission_shape])
	return {
		"success": true,
		"data": {
			"particle_path": str(particles.get_path()),
			"amount": amount,
			"lifetime": lifetime,
			"emission_shape": emission_shape
		}
	}


func set_particle_material_param(params: Dictionary) -> Dictionary:
	"""Set a parameter on an existing GPUParticles3D's ParticleProcessMaterial."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not node is GPUParticles3D:
		return {"success": false, "error": "Node is not a GPUParticles3D (is %s)" % node.get_class()}
	if not node.process_material:
		return {"success": false, "error": "GPUParticles3D has no process_material assigned"}

	var mat = node.process_material
	var param_name = params.get("param_name", "")
	var value = params.get("value")

	if param_name == "":
		return {"success": false, "error": "param_name is required. Common: emission_shape, emission_sphere_radius, emission_box_extents, initial_velocity_min, initial_velocity_max, gravity, direction, spread, color, scale_min, scale_max, linear_accel_min, linear_accel_max, radial_accel_min, radial_accel_max"}

	# emission_shape string → enum
	if param_name == "emission_shape" and value is String:
		value = _emission_shape_enum(value)
	else:
		value = _coerce_value(value, param_name)

	mat.set(param_name, value)
	return {"success": true, "data": {"param_name": param_name, "value": str(value)}}


func restart_particles(params: Dictionary) -> Dictionary:
	"""Restart a GPUParticles3D or CPUParticles3D — triggers a fresh burst."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not (node is GPUParticles3D or node is CPUParticles3D):
		return {"success": false, "error": "Node is not a GPUParticles3D or CPUParticles3D (is %s)" % node.get_class()}

	node.restart()
	node.emitting = true
	print("[Particles] Restarted '%s'" % params.get("node_path"))
	return {"success": true, "data": {"node_path": params.get("node_path")}}


func get_particle_info(params: Dictionary) -> Dictionary:
	"""Get all properties of a GPUParticles3D node including process material settings."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not (node is GPUParticles3D or node is CPUParticles3D):
		return {"success": false, "error": "Node is not a particle node (is %s)" % node.get_class()}

	var info: Dictionary = {
		"class":          node.get_class(),
		"amount":         node.amount,
		"lifetime":       node.lifetime,
		"emitting":       node.emitting,
		"one_shot":       node.one_shot,
		"explosiveness":  node.explosiveness,
		"randomness":     node.randomness,
		"speed_scale":    node.speed_scale,
		"position":       [node.position.x, node.position.y, node.position.z]
	}

	if node is GPUParticles3D and node.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = node.process_material
		info["process_material"] = {
			"emission_shape":       mat.emission_shape,
			"emission_sphere_radius": mat.emission_sphere_radius,
			"initial_velocity_min": mat.initial_velocity_min,
			"initial_velocity_max": mat.initial_velocity_max,
			"gravity":              [mat.gravity.x, mat.gravity.y, mat.gravity.z],
			"direction":            [mat.direction.x, mat.direction.y, mat.direction.z],
			"spread":               mat.spread,
			"scale_min":            mat.scale_min,
			"scale_max":            mat.scale_max,
			"color":                [mat.color.r, mat.color.g, mat.color.b, mat.color.a],
			"linear_accel_min":     mat.linear_accel_min,
			"linear_accel_max":     mat.linear_accel_max,
		}

	return {"success": true, "data": info}
