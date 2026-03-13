@tool
extends Node

## Skeleton Operations for Claude-GoDot-MCP
## Covers Skeleton3D bone inspection, pose manipulation, and pose reset.

var editor_interface: EditorInterface


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_skeleton(params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	var path = params.get("node_path", "")
	if path == "":
		return {"success": false, "error": "node_path is required"}
	var node = root.get_node_or_null(path)
	if not node:
		return {"success": false, "error": "Node not found: " + path}
	if not node is Skeleton3D:
		return {"success": false, "error": "Node '%s' is %s, not Skeleton3D" % [path, node.get_class()]}
	return {"success": true, "skeleton": node}


func _transform_to_dict(t: Transform3D) -> Dictionary:
	return {
		"position":         [t.origin.x, t.origin.y, t.origin.z],
		"basis_x":          [t.basis.x.x, t.basis.x.y, t.basis.x.z],
		"basis_y":          [t.basis.y.x, t.basis.y.y, t.basis.y.z],
		"basis_z":          [t.basis.z.x, t.basis.z.y, t.basis.z.z],
		"rotation_degrees": [
			rad_to_deg(t.basis.get_euler().x),
			rad_to_deg(t.basis.get_euler().y),
			rad_to_deg(t.basis.get_euler().z)
		],
		"scale": [t.basis.get_scale().x, t.basis.get_scale().y, t.basis.get_scale().z]
	}


# ── Skeleton Tools ────────────────────────────────────────────────────────────

func get_skeleton_bones(params: Dictionary) -> Dictionary:
	"""List all bones in a Skeleton3D with their names, parent indices, rest transforms, and current poses."""
	var r = _get_skeleton(params)
	if not r.success: return r
	var sk: Skeleton3D = r.skeleton

	var bones = []
	for i in range(sk.get_bone_count()):
		var rest  = sk.get_bone_rest(i)
		var pose  = sk.get_bone_pose(i)
		var global_pose = sk.get_bone_global_pose(i)
		bones.append({
			"index":         i,
			"name":          sk.get_bone_name(i),
			"parent_index":  sk.get_bone_parent(i),  # -1 = root bone
			"rest":          _transform_to_dict(rest),
			"pose":          _transform_to_dict(pose),
			"global_pose_position": [global_pose.origin.x, global_pose.origin.y, global_pose.origin.z],
			"enabled":       sk.is_bone_enabled(i)
		})

	return {
		"success": true,
		"data": {
			"node_path":  params.get("node_path"),
			"bone_count": bones.size(),
			"bones":      bones
		}
	}


func set_bone_pose(params: Dictionary) -> Dictionary:
	"""Set pose position, rotation (Euler deg or Quaternion), and/or scale on a bone by name or index."""
	var r = _get_skeleton(params)
	if not r.success: return r
	var sk: Skeleton3D = r.skeleton

	# Resolve bone index
	var bone_idx = -1
	if params.has("bone_name"):
		bone_idx = sk.find_bone(str(params["bone_name"]))
		if bone_idx < 0:
			return {"success": false, "error": "Bone '%s' not found in skeleton" % params["bone_name"]}
	elif params.has("bone_index"):
		bone_idx = int(params["bone_index"])
	else:
		return {"success": false, "error": "bone_name or bone_index is required"}

	if bone_idx < 0 or bone_idx >= sk.get_bone_count():
		return {"success": false, "error": "Bone index %d out of range (0–%d)" % [bone_idx, sk.get_bone_count() - 1]}

	if params.has("position"):
		var p = params["position"]
		if p is Array and p.size() >= 3:
			sk.set_bone_pose_position(bone_idx, Vector3(float(p[0]), float(p[1]), float(p[2])))

	if params.has("rotation"):
		var rot = params["rotation"]
		if rot is Array:
			if rot.size() >= 4:
				sk.set_bone_pose_rotation(bone_idx, Quaternion(float(rot[0]), float(rot[1]), float(rot[2]), float(rot[3])))
			elif rot.size() >= 3:
				# Interpret as Euler degrees
				var euler = Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(float(rot[2])))
				sk.set_bone_pose_rotation(bone_idx, Quaternion.from_euler(euler))

	if params.has("scale"):
		var s = params["scale"]
		if s is Array and s.size() >= 3:
			sk.set_bone_pose_scale(bone_idx, Vector3(float(s[0]), float(s[1]), float(s[2])))

	var bone_name = sk.get_bone_name(bone_idx)
	print("[Skeleton] set_bone_pose: bone='%s' (idx=%d)" % [bone_name, bone_idx])
	return {
		"success": true,
		"data": {
			"bone_index": bone_idx,
			"bone_name":  bone_name,
			"pose":       _transform_to_dict(sk.get_bone_pose(bone_idx))
		}
	}


func reset_skeleton_pose(params: Dictionary) -> Dictionary:
	"""Reset all bone poses to the skeleton's rest pose (clears any procedural or manual posing)."""
	var r = _get_skeleton(params)
	if not r.success: return r
	var sk: Skeleton3D = r.skeleton

	sk.reset_bone_poses()

	print("[Skeleton] reset_bone_poses on '%s' (%d bones)" % [params.get("node_path"), sk.get_bone_count()])
	return {
		"success": true,
		"data": {
			"node_path":  params.get("node_path"),
			"bone_count": sk.get_bone_count()
		}
	}
