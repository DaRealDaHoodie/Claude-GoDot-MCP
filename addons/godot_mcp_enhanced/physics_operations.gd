@tool
extends Node

## Physics Operations for Claude-GoDot-MCP
## Covers RigidBody3D/CharacterBody3D impulse/force/torque, velocity, property setup, and joints.

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
	return {"success": true, "node": node, "root": root}


func _vec3(raw, default: Vector3 = Vector3.ZERO) -> Vector3:
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	if raw is Vector3:
		return raw
	return default


func _vec3_to_list(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


# ── Physics Tools ─────────────────────────────────────────────────────────────

func apply_impulse(params: Dictionary) -> Dictionary:
	"""Apply an impulse to a RigidBody3D (immediate velocity change)."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node
	if not node is RigidBody3D:
		return {"success": false, "error": "Node '%s' is %s, not RigidBody3D" % [params.get("node_path"), node.get_class()]}
	var impulse = _vec3(params.get("impulse", [0, 0, 0]))
	var position = _vec3(params.get("position", [0, 0, 0]))
	node.apply_impulse(impulse, position)
	print("[Physics] apply_impulse on '%s': impulse=%s pos=%s" % [params.get("node_path"), impulse, position])
	return {"success": true, "data": {"impulse": _vec3_to_list(impulse), "position": _vec3_to_list(position)}}


func apply_force(params: Dictionary) -> Dictionary:
	"""Apply a continuous force to a RigidBody3D (persists until cleared)."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node
	if not node is RigidBody3D:
		return {"success": false, "error": "Node is not a RigidBody3D (is %s)" % node.get_class()}
	var force = _vec3(params.get("force", [0, 0, 0]))
	var position = _vec3(params.get("position", [0, 0, 0]))
	node.apply_force(force, position)
	print("[Physics] apply_force on '%s': force=%s" % [params.get("node_path"), force])
	return {"success": true, "data": {"force": _vec3_to_list(force), "position": _vec3_to_list(position)}}


func apply_torque(params: Dictionary) -> Dictionary:
	"""Apply a torque (rotational force) to a RigidBody3D."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node
	if not node is RigidBody3D:
		return {"success": false, "error": "Node is not a RigidBody3D (is %s)" % node.get_class()}
	var torque = _vec3(params.get("torque", [0, 0, 0]))
	node.apply_torque(torque)
	print("[Physics] apply_torque on '%s': torque=%s" % [params.get("node_path"), torque])
	return {"success": true, "data": {"torque": _vec3_to_list(torque)}}


func set_linear_velocity(params: Dictionary) -> Dictionary:
	"""Set linear_velocity on a RigidBody3D or CharacterBody3D."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node
	if not (node is RigidBody3D or node is CharacterBody3D):
		return {"success": false, "error": "Node is %s — needs RigidBody3D or CharacterBody3D" % node.get_class()}
	var velocity = _vec3(params.get("velocity", [0, 0, 0]))
	node.linear_velocity = velocity
	return {"success": true, "data": {"linear_velocity": _vec3_to_list(velocity), "node_class": node.get_class()}}


func set_angular_velocity(params: Dictionary) -> Dictionary:
	"""Set angular_velocity on a RigidBody3D."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node
	if not node is RigidBody3D:
		return {"success": false, "error": "Node is not a RigidBody3D (is %s)" % node.get_class()}
	var velocity = _vec3(params.get("velocity", [0, 0, 0]))
	node.angular_velocity = velocity
	return {"success": true, "data": {"angular_velocity": _vec3_to_list(velocity)}}


func set_physics_property(params: Dictionary) -> Dictionary:
	"""Set a physics property on any physics body (mass, gravity_scale, linear_damp, etc.)."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node
	var prop = params.get("property", "")
	var value = params.get("value")

	if prop == "":
		return {"success": false, "error": "property is required. Common: mass, gravity_scale, linear_damp, angular_damp, freeze, freeze_mode, collision_layer, collision_mask, can_sleep, continuous_cd"}

	# Coerce freeze_mode string → enum
	if prop == "freeze_mode" and value is String:
		match value.to_lower():
			"static":    value = RigidBody3D.FREEZE_MODE_STATIC
			"kinematic": value = RigidBody3D.FREEZE_MODE_KINEMATIC

	# Coerce collision_layer/mask array of ints → bitmask
	if prop in ["collision_layer", "collision_mask"] and value is Array:
		var mask = 0
		for layer in value:
			mask |= (1 << (int(layer) - 1))
		value = mask

	node.set(prop, value)
	return {"success": true, "data": {"property": prop, "value": node.get(prop)}}


func create_joint(params: Dictionary) -> Dictionary:
	"""Create a physics joint node (HingeJoint3D, PinJoint3D, etc.) and wire two bodies."""
	var r = _get_node({"node_path": params.get("parent_path", "")}) if params.get("parent_path", "") != "" else {"success": true}
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var parent_path = params.get("parent_path", "")
	var parent = root.get_node_or_null(parent_path) if parent_path != "" else root
	if not parent:
		return {"success": false, "error": "Parent not found: " + parent_path}

	var joint_type = params.get("joint_type", "HingeJoint3D")
	var joint_name = params.get("joint_name", joint_type)
	var node_a_path = params.get("node_a_path", "")
	var node_b_path = params.get("node_b_path", "")

	var joint: Node3D
	match joint_type:
		"HingeJoint3D":       joint = HingeJoint3D.new()
		"PinJoint3D":         joint = PinJoint3D.new()
		"SliderJoint3D":      joint = SliderJoint3D.new()
		"Generic6DOFJoint3D": joint = Generic6DOFJoint3D.new()
		"ConeTwistJoint3D":   joint = ConeTwistJoint3D.new()
		_:
			return {"success": false, "error": "Unknown joint_type '%s'. Valid: HingeJoint3D, PinJoint3D, SliderJoint3D, Generic6DOFJoint3D, ConeTwistJoint3D" % joint_type}

	joint.name = joint_name
	parent.add_child(joint)
	joint.owner = root

	# Set position
	if params.has("position"):
		joint.position = _vec3(params["position"])

	# Wire bodies — use relative NodePaths from the joint's perspective
	if node_a_path != "" and root.has_node(node_a_path):
		joint.node_a = joint.get_path_to(root.get_node(node_a_path))
	if node_b_path != "" and root.has_node(node_b_path):
		joint.node_b = joint.get_path_to(root.get_node(node_b_path))

	print("[Physics] Created %s '%s' (A=%s, B=%s)" % [joint_type, joint_name, node_a_path, node_b_path])
	return {
		"success": true,
		"data": {
			"joint_path": str(joint.get_path()),
			"joint_type": joint_type,
			"node_a": node_a_path,
			"node_b": node_b_path
		}
	}
