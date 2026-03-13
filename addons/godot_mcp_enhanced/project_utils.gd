@tool
extends Node

## Project Utilities for Claude-GoDot-MCP
## FPS assertion, renderer info, resource validation, global transforms, feature tags, metadata.

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


# ── Project Utility Tools ─────────────────────────────────────────────────────

func assert_fps_above(params: Dictionary) -> Dictionary:
	"""Sample FPS over N frames and assert the average meets a minimum threshold.
	   Requires scene to be playing for meaningful game FPS measurement."""
	var threshold   = float(params.get("threshold", 30.0))
	var frame_count = clampi(int(params.get("frame_count", 60)), 1, 300)

	var fps_samples: Array[float] = []
	for _i in range(frame_count):
		await Engine.get_main_loop().process_frame
		fps_samples.append(float(Engine.get_frames_per_second()))

	var total = 0.0
	for fps in fps_samples:
		total += fps
	var avg_fps = total / fps_samples.size()
	var min_fps = fps_samples.min()
	var max_fps = fps_samples.max()

	var passed = avg_fps >= threshold

	print("[QA] assert_fps_above %.0f: avg=%.1f min=%.1f max=%.1f → %s" % [
		threshold, avg_fps, min_fps, max_fps, "PASS" if passed else "FAIL"
	])
	return {
		"success": true,
		"data": {
			"passed":         passed,
			"threshold":      threshold,
			"avg_fps":        snappedf(avg_fps, 0.1),
			"min_fps":        snappedf(min_fps, 0.1),
			"max_fps":        snappedf(max_fps, 0.1),
			"frames_sampled": fps_samples.size()
		}
	}


func get_renderer_info(_params: Dictionary) -> Dictionary:
	"""Get rendering backend, GPU adapter name/vendor, VRAM usage, viewport size, and Godot version."""
	var vram_used_bytes = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var screen_sz = DisplayServer.screen_get_size()

	return {
		"success": true,
		"data": {
			"adapter_name":         RenderingServer.get_video_adapter_name(),
			"adapter_vendor":       RenderingServer.get_video_adapter_vendor(),
			"adapter_api_version":  RenderingServer.get_video_adapter_api_version(),
			"rendering_method":     ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
			"vram_used_mb":         snappedf(vram_used_bytes / 1048576.0, 0.01),
			"screen_size":          [screen_sz.x, screen_sz.y],
			"godot_version":        Engine.get_version_info(),
			"fps":                  Engine.get_frames_per_second()
		}
	}


func assert_resource_valid(params: Dictionary) -> Dictionary:
	"""Verify that a res:// resource exists and loads without errors. Returns {passed, resource_type}."""
	var resource_path = params.get("resource_path", "")
	if resource_path == "":
		return {"success": false, "error": "resource_path is required"}

	if not ResourceLoader.exists(resource_path):
		return {
			"success": true,
			"data": {"passed": false, "error": "File does not exist", "resource_path": resource_path}
		}

	var res = ResourceLoader.load(resource_path)
	if not res:
		return {
			"success": true,
			"data": {"passed": false, "error": "Resource failed to load", "resource_path": resource_path}
		}

	print("[QA] assert_resource_valid '%s': PASS (%s)" % [resource_path, res.get_class()])
	return {
		"success": true,
		"data": {
			"passed":        true,
			"resource_type": res.get_class(),
			"resource_path": resource_path
		}
	}


func get_node_global_transform(params: Dictionary) -> Dictionary:
	"""Get the world-space position, rotation (degrees), and scale of a Node3D or Node2D."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if node is Node3D:
		var t = node.global_transform
		var euler_deg = t.basis.get_euler() * (180.0 / PI)
		return {
			"success": true,
			"data": {
				"node_class":        "Node3D",
				"global_position":   [t.origin.x,   t.origin.y,   t.origin.z],
				"global_rotation_degrees": [euler_deg.x, euler_deg.y, euler_deg.z],
				"global_scale":      [t.basis.get_scale().x, t.basis.get_scale().y, t.basis.get_scale().z],
				"basis_x":           [t.basis.x.x, t.basis.x.y, t.basis.x.z],
				"basis_y":           [t.basis.y.x, t.basis.y.y, t.basis.y.z],
				"basis_z":           [t.basis.z.x, t.basis.z.y, t.basis.z.z]
			}
		}
	elif node is Node2D:
		return {
			"success": true,
			"data": {
				"node_class":             "Node2D",
				"global_position":        [node.global_position.x, node.global_position.y],
				"global_rotation_degrees": rad_to_deg(node.global_rotation),
				"global_scale":           [node.global_scale.x, node.global_scale.y]
			}
		}
	else:
		return {"success": false, "error": "Node '%s' is %s — not a Node3D or Node2D" % [params.get("node_path"), node.get_class()]}


func set_node_global_transform(params: Dictionary) -> Dictionary:
	"""Set the world-space position, rotation (degrees), and/or scale of a Node3D or Node2D."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if node is Node3D:
		if params.has("global_position"):
			var p = params["global_position"]
			if p is Array and p.size() >= 3:
				node.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		if params.has("global_rotation_degrees"):
			var rot = params["global_rotation_degrees"]
			if rot is Array and rot.size() >= 3:
				node.global_rotation_degrees = Vector3(float(rot[0]), float(rot[1]), float(rot[2]))
		if params.has("global_scale"):
			var s = params["global_scale"]
			if s is Array and s.size() >= 3:
				node.scale = node.global_transform.basis.get_scale()  # preserve before
				# For global scale we must adjust via transform
				var t = node.global_transform
				t.basis = Basis(t.basis.get_rotation_quaternion()).scaled(Vector3(float(s[0]), float(s[1]), float(s[2])))
				node.global_transform = t
		return {
			"success": true,
			"data": {
				"node_class":      "Node3D",
				"global_position": [node.global_position.x, node.global_position.y, node.global_position.z]
			}
		}
	elif node is Node2D:
		if params.has("global_position"):
			var p = params["global_position"]
			if p is Array and p.size() >= 2:
				node.global_position = Vector2(float(p[0]), float(p[1]))
		if params.has("global_rotation_degrees"):
			node.global_rotation = deg_to_rad(float(params["global_rotation_degrees"]))
		if params.has("global_scale"):
			var s = params["global_scale"]
			if s is Array and s.size() >= 2:
				node.global_scale = Vector2(float(s[0]), float(s[1]))
		return {
			"success": true,
			"data": {
				"node_class":      "Node2D",
				"global_position": [node.global_position.x, node.global_position.y]
			}
		}
	else:
		return {"success": false, "error": "Node is not Node3D or Node2D"}


func toggle_feature_tag(params: Dictionary) -> Dictionary:
	"""Add or remove a custom feature tag in project settings (application/config/features).
	   Feature tags can be queried at runtime with OS.has_feature('tag_name')."""
	var tag     = params.get("tag", "")
	var enabled = bool(params.get("enabled", true))

	if tag == "":
		return {"success": false, "error": "tag is required"}

	var features = Array(PackedStringArray(ProjectSettings.get_setting("application/config/features", PackedStringArray())))

	var changed = false
	if enabled and not tag in features:
		features.append(tag)
		changed = true
	elif not enabled and tag in features:
		features.erase(tag)
		changed = true

	if changed:
		ProjectSettings.set_setting("application/config/features", PackedStringArray(features))
		ProjectSettings.save()

	print("[Project] toggle_feature_tag '%s' → %s (changed=%s)" % [tag, str(enabled), str(changed)])
	return {
		"success": true,
		"data": {
			"tag":      tag,
			"enabled":  enabled,
			"changed":  changed,
			"all_features": features
		}
	}


func set_node_metadata(params: Dictionary) -> Dictionary:
	"""Set or remove metadata on a node via node.set_meta() / node.remove_meta().
	   Metadata persists in .tscn files and is accessible at runtime via node.get_meta('key')."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	var key    = params.get("key", "")
	var value  = params.get("value")
	var remove = bool(params.get("remove", false))

	if key == "":
		return {"success": false, "error": "key is required"}

	if remove:
		if node.has_meta(key):
			node.remove_meta(key)
			return {"success": true, "data": {"key": key, "action": "removed"}}
		else:
			return {"success": false, "error": "Metadata key '%s' not found on node" % key}
	else:
		node.set_meta(key, value)
		return {
			"success": true,
			"data": {
				"key":   key,
				"value": str(node.get_meta(key)),
				"action": "set"
			}
		}
