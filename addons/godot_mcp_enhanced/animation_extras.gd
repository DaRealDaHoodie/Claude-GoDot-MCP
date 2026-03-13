@tool
extends Node

## Animation Extras for Claude-GoDot-MCP
## Blend space operations, cross-player animation copying, and speed scale control.

var editor_interface: EditorInterface


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_player(params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	var path = params.get("player_path", "AnimationPlayer")
	var node = root.get_node_or_null(path)
	if not node:
		return {"success": false, "error": "AnimationPlayer not found: " + path}
	if not node is AnimationPlayer:
		return {"success": false, "error": "Node '%s' is %s, not AnimationPlayer" % [path, node.get_class()]}
	return {"success": true, "player": node, "root": root}


func _get_tree_node(params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	var tree_path = params.get("tree_path", "AnimationTree")
	var tree = root.get_node_or_null(tree_path)
	if not tree or not tree is AnimationTree:
		return {"success": false, "error": "AnimationTree not found at: " + tree_path}
	return {"success": true, "tree": tree, "root": root}


func _get_blend_space_node(tree: AnimationTree, state_name: String) -> Dictionary:
	"""Resolve a blend space node from within a StateMachine."""
	if not tree.tree_root is AnimationNodeStateMachine:
		return {"success": false, "error": "AnimationTree root is not a StateMachine"}
	var sm: AnimationNodeStateMachine = tree.tree_root
	if not sm.has_node(state_name):
		return {"success": false, "error": "State '%s' not found in StateMachine" % state_name}
	var bs = sm.get_node(state_name)
	if not (bs is AnimationNodeBlendSpace1D or bs is AnimationNodeBlendSpace2D):
		return {"success": false, "error": "State '%s' is %s, not a BlendSpace node" % [state_name, bs.get_class()]}
	return {"success": true, "blend_space": bs, "is_1d": bs is AnimationNodeBlendSpace1D}


# ── Animation Extra Tools ─────────────────────────────────────────────────────

func add_blend_space_point(params: Dictionary) -> Dictionary:
	"""Add an animation blend point to an AnimationNodeBlendSpace1D or BlendSpace2D.
	   The blend space must be a state inside an AnimationNodeStateMachine."""
	var r = _get_tree_node(params)
	if not r.success: return r
	var tree: AnimationTree = r.tree

	var state_name     = params.get("state_name", "")
	var animation_name = params.get("animation_name", "")
	var blend_position = params.get("blend_position")  # float for 1D, [x,y] for 2D

	if state_name == "" or animation_name == "":
		return {"success": false, "error": "state_name and animation_name are required"}

	var br = _get_blend_space_node(tree, state_name)
	if not br.success: return br
	var bs = br.blend_space

	var point_node = AnimationNodeAnimation.new()
	point_node.animation = animation_name

	if br.is_1d:
		var pos = float(blend_position) if not blend_position is Array else float(blend_position[0])
		bs.add_blend_point(point_node, pos)
		var idx = bs.get_blend_point_count() - 1
		print("[Anim] BlendSpace1D: added '%s' at pos %.2f (idx=%d)" % [animation_name, pos, idx])
		return {"success": true, "data": {"state_name": state_name, "animation_name": animation_name, "position": pos, "point_index": idx}}
	else:
		var pos: Vector2
		if blend_position is Array and blend_position.size() >= 2:
			pos = Vector2(float(blend_position[0]), float(blend_position[1]))
		else:
			pos = Vector2.ZERO
		bs.add_blend_point(point_node, pos)
		var idx = bs.get_blend_point_count() - 1
		print("[Anim] BlendSpace2D: added '%s' at [%.2f, %.2f] (idx=%d)" % [animation_name, pos.x, pos.y, idx])
		return {"success": true, "data": {"state_name": state_name, "animation_name": animation_name, "position": [pos.x, pos.y], "point_index": idx}}


func get_blend_space_info(params: Dictionary) -> Dictionary:
	"""Get all blend points, limits, and snap settings from a blend space state."""
	var r = _get_tree_node(params)
	if not r.success: return r
	var tree: AnimationTree = r.tree

	var state_name = params.get("state_name", "")
	if state_name == "":
		return {"success": false, "error": "state_name is required"}

	var br = _get_blend_space_node(tree, state_name)
	if not br.success: return br
	var bs = br.blend_space

	var points = []
	for i in range(bs.get_blend_point_count()):
		var pt_node = bs.get_blend_point_node(i)
		var anim_name = pt_node.animation if pt_node is AnimationNodeAnimation else pt_node.get_class()
		if br.is_1d:
			points.append({"index": i, "animation": anim_name, "position": bs.get_blend_point_position(i)})
		else:
			var pos: Vector2 = bs.get_blend_point_position(i)
			points.append({"index": i, "animation": anim_name, "position": [pos.x, pos.y]})

	var info: Dictionary = {
		"state_name": state_name,
		"blend_space_type": "1D" if br.is_1d else "2D",
		"point_count": points.size(),
		"points": points
	}

	if br.is_1d:
		info["min_space"] = bs.min_space
		info["max_space"] = bs.max_space
		info["snap"] = bs.snap
	else:
		info["min_space"] = [bs.min_space.x, bs.min_space.y]
		info["max_space"] = [bs.max_space.x, bs.max_space.y]
		info["snap"] = [bs.snap.x, bs.snap.y]

	return {"success": true, "data": info}


func copy_animation(params: Dictionary) -> Dictionary:
	"""Copy one or more animations from a source AnimationPlayer to a destination AnimationPlayer.
	   Duplicates the Animation resource so the two players are independent."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var src_path  = params.get("source_player_path", "")
	var dst_path  = params.get("dest_player_path", "")
	var anim_names = params.get("animation_names", [])  # Empty = copy all
	var dest_lib_name = params.get("dest_library_name", "")

	if src_path == "" or dst_path == "":
		return {"success": false, "error": "source_player_path and dest_player_path are required"}

	var src = root.get_node_or_null(src_path)
	var dst = root.get_node_or_null(dst_path)

	if not src or not src is AnimationPlayer:
		return {"success": false, "error": "Source AnimationPlayer not found: " + src_path}
	if not dst or not dst is AnimationPlayer:
		return {"success": false, "error": "Destination AnimationPlayer not found: " + dst_path}

	# Get or create destination library
	var dst_lib: AnimationLibrary
	if dst.has_animation_library(dest_lib_name):
		dst_lib = dst.get_animation_library(dest_lib_name)
	else:
		dst_lib = AnimationLibrary.new()
		dst.add_animation_library(dest_lib_name, dst_lib)

	# Build list of (library_name, anim_name) pairs to copy
	var to_copy: Array = []
	if anim_names.is_empty():
		for lib_name in src.get_animation_library_list():
			var lib = src.get_animation_library(lib_name)
			for anim_name in lib.get_animation_list():
				to_copy.append([lib_name, anim_name])
	else:
		for anim_name in anim_names:
			# Find which library holds this animation
			for lib_name in src.get_animation_library_list():
				var lib = src.get_animation_library(lib_name)
				if lib.has_animation(anim_name):
					to_copy.append([lib_name, anim_name])
					break

	var copied = []
	for entry in to_copy:
		var lib_name  = entry[0]
		var anim_name = entry[1]
		var src_lib   = src.get_animation_library(lib_name)
		var anim      = src_lib.get_animation(anim_name).duplicate()  # deep copy
		if dst_lib.has_animation(anim_name):
			dst_lib.remove_animation(anim_name)
		dst_lib.add_animation(anim_name, anim)
		copied.append(anim_name)

	print("[Anim] Copied %d animation(s) from '%s' → '%s'" % [copied.size(), src_path, dst_path])
	return {
		"success": true,
		"data": {
			"source": src_path, "destination": dst_path,
			"dest_library": dest_lib_name,
			"copied": copied, "count": copied.size()
		}
	}


func set_animation_speed_scale(params: Dictionary) -> Dictionary:
	"""Set the playback speed_scale on an AnimationPlayer (2.0 = double speed, 0.5 = half speed)."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var speed_scale = float(params.get("speed_scale", 1.0))
	player.speed_scale = speed_scale

	return {
		"success": true,
		"data": {
			"player_path": params.get("player_path", "AnimationPlayer"),
			"speed_scale": speed_scale
		}
	}
