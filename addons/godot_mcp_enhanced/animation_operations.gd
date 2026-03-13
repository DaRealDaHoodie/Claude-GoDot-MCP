@tool
extends Node

## Animation Operations for Claude-GoDot-MCP
## Covers AnimationPlayer, AnimationLibrary, Animation tracks/keyframes, AnimationTree

var editor_interface: EditorInterface


# ── Internal Helpers ──────────────────────────────────────────────────────────

func _get_player(params: Dictionary) -> Dictionary:
	"""Resolve AnimationPlayer node from scene. Returns {success, player, root} or error."""
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


func _get_anim(player: AnimationPlayer, animation_name: String, library_name: String = "") -> Dictionary:
	"""Resolve an Animation resource from player. Returns {success, animation, full_name}."""
	# Build the full qualified name (library/anim or just anim for default library)
	var candidates: Array[String] = []
	if library_name != "":
		candidates.append(library_name + "/" + animation_name)
	candidates.append(animation_name)
	# Also search across all libraries
	for lib_name in player.get_animation_library_list():
		var try_name = (lib_name + "/" if lib_name != "" else "") + animation_name
		if not try_name in candidates:
			candidates.append(try_name)

	for candidate in candidates:
		if player.has_animation(candidate):
			return {"success": true, "animation": player.get_animation(candidate), "full_name": candidate}

	return {"success": false, "error": "Animation '%s' not found in player (library: '%s')" % [animation_name, library_name]}


func _track_type_to_enum(type_name: String) -> int:
	match type_name.to_lower().replace(" ", "_").replace("-", "_"):
		"value":          return Animation.TYPE_VALUE
		"method":         return Animation.TYPE_METHOD
		"bezier":         return Animation.TYPE_BEZIER
		"audio":          return Animation.TYPE_AUDIO
		"animation":      return Animation.TYPE_ANIMATION
		"position_3d", "position3d", "pos3d":  return Animation.TYPE_POSITION_3D
		"rotation_3d", "rotation3d", "rot3d":  return Animation.TYPE_ROTATION_3D
		"scale_3d", "scale3d":                 return Animation.TYPE_SCALE_3D
		"blend_shape", "blendshape":           return Animation.TYPE_BLEND_SHAPE
	return -1


func _enum_to_track_type(t: int) -> String:
	match t:
		Animation.TYPE_VALUE:       return "value"
		Animation.TYPE_METHOD:      return "method"
		Animation.TYPE_BEZIER:      return "bezier"
		Animation.TYPE_AUDIO:       return "audio"
		Animation.TYPE_ANIMATION:   return "animation"
		Animation.TYPE_POSITION_3D: return "position_3d"
		Animation.TYPE_ROTATION_3D: return "rotation_3d"
		Animation.TYPE_SCALE_3D:    return "scale_3d"
		Animation.TYPE_BLEND_SHAPE: return "blend_shape"
	return "unknown"


func _interp_to_enum(name: String) -> int:
	match name.to_lower():
		"nearest":      return Animation.INTERPOLATION_NEAREST
		"linear":       return Animation.INTERPOLATION_LINEAR
		"cubic":        return Animation.INTERPOLATION_CUBIC
		"linear_angle": return Animation.INTERPOLATION_LINEAR_ANGLE
		"cubic_angle":  return Animation.INTERPOLATION_CUBIC_ANGLE
	return -1


func _enum_to_interp(i: int) -> String:
	match i:
		Animation.INTERPOLATION_NEAREST:      return "nearest"
		Animation.INTERPOLATION_LINEAR:       return "linear"
		Animation.INTERPOLATION_CUBIC:        return "cubic"
		Animation.INTERPOLATION_LINEAR_ANGLE: return "linear_angle"
		Animation.INTERPOLATION_CUBIC_ANGLE:  return "cubic_angle"
	return "linear"


func _coerce_for_track(anim: Animation, track_idx: int, raw) -> Variant:
	"""Convert JSON array/number to Godot type based on track type."""
	if not raw is Array:
		return raw
	var t = anim.track_get_type(track_idx)
	match t:
		Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D:
			if raw.size() >= 3: return Vector3(raw[0], raw[1], raw[2])
		Animation.TYPE_ROTATION_3D:
			if raw.size() >= 4: return Quaternion(raw[0], raw[1], raw[2], raw[3])
			if raw.size() >= 3: return Quaternion.from_euler(Vector3(raw[0], raw[1], raw[2]))
		Animation.TYPE_VALUE, Animation.TYPE_BEZIER:
			match raw.size():
				2: return Vector2(raw[0], raw[1])
				3: return Vector3(raw[0], raw[1], raw[2])
				4: return Color(raw[0], raw[1], raw[2], raw[3])
	return raw


func _variant_to_json(v: Variant) -> Variant:
	"""Serialize Godot types to JSON-safe values."""
	if v is Vector2:     return [v.x, v.y]
	if v is Vector3:     return [v.x, v.y, v.z]
	if v is Quaternion:  return [v.x, v.y, v.z, v.w]
	if v is Color:       return [v.r, v.g, v.b, v.a]
	if v is Transform3D: return {"origin": [v.origin.x, v.origin.y, v.origin.z]}
	if v is Transform2D: return {"origin": [v.origin.x, v.origin.y]}
	return v


# ── Animation Library / Resource Management ───────────────────────────────────

func get_animation_player_info(params: Dictionary) -> Dictionary:
	"""List all libraries and animations in an AnimationPlayer."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var libraries = {}
	for lib_name in player.get_animation_library_list():
		var lib = player.get_animation_library(lib_name)
		var anims = []
		for anim_name in lib.get_animation_list():
			var a = lib.get_animation(anim_name)
			anims.append({
				"name": anim_name,
				"full_name": (lib_name + "/" if lib_name != "" else "") + anim_name,
				"length": a.length,
				"loop_mode": a.loop_mode,
				"step": a.step,
				"track_count": a.get_track_count()
			})
		libraries[lib_name if lib_name != "" else "(default)"] = anims

	return {
		"success": true,
		"data": {
			"player_path": params.get("player_path", "AnimationPlayer"),
			"current_animation": player.current_animation,
			"is_playing": player.is_playing(),
			"autoplay": player.autoplay,
			"libraries": libraries
		}
	}


func create_animation(params: Dictionary) -> Dictionary:
	"""Create a new Animation resource and register it in an AnimationPlayer library."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var anim_name = params.get("animation_name", "")
	if anim_name == "":
		return {"success": false, "error": "animation_name is required"}

	var lib_name   = params.get("library_name", "")
	var length     = float(params.get("length", 1.0))
	var loop_mode  = params.get("loop_mode", "none")   # none / linear / pingpong
	var step       = float(params.get("step", 0.1))

	# Get or create the target library
	var lib: AnimationLibrary
	if player.has_animation_library(lib_name):
		lib = player.get_animation_library(lib_name)
	else:
		lib = AnimationLibrary.new()
		player.add_animation_library(lib_name, lib)

	if lib.has_animation(anim_name):
		return {"success": false, "error": "Animation '%s' already exists in library '%s'" % [anim_name, lib_name]}

	var anim = Animation.new()
	anim.length = length
	anim.step   = step
	match loop_mode:
		"linear":   anim.loop_mode = Animation.LOOP_LINEAR
		"pingpong": anim.loop_mode = Animation.LOOP_PINGPONG
		_:          anim.loop_mode = Animation.LOOP_NONE

	lib.add_animation(anim_name, anim)

	var full_name = (lib_name + "/" if lib_name != "" else "") + anim_name
	print("[Animation] Created: ", full_name)
	return {
		"success": true,
		"data": {"animation_name": anim_name, "library_name": lib_name,
				 "full_name": full_name, "length": length, "loop_mode": loop_mode}
	}


func get_animation_info(params: Dictionary) -> Dictionary:
	"""Get detailed info about an animation: length, loop, step, and all tracks."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var tracks = []
	for i in range(anim.get_track_count()):
		tracks.append({
			"index": i,
			"type": _enum_to_track_type(anim.track_get_type(i)),
			"path": str(anim.track_get_path(i)),
			"enabled": anim.track_is_enabled(i),
			"interpolation": _enum_to_interp(anim.track_get_interpolation_type(i)),
			"key_count": anim.track_get_key_count(i)
		})

	return {
		"success": true,
		"data": {
			"full_name": ar.full_name,
			"length": anim.length,
			"loop_mode": anim.loop_mode,
			"step": anim.step,
			"track_count": anim.get_track_count(),
			"tracks": tracks
		}
	}


func set_animation_properties(params: Dictionary) -> Dictionary:
	"""Set length, loop_mode, and/or step on an Animation."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	if params.has("length"):
		anim.length = float(params["length"])
	if params.has("loop_mode"):
		match params["loop_mode"]:
			"linear":   anim.loop_mode = Animation.LOOP_LINEAR
			"pingpong": anim.loop_mode = Animation.LOOP_PINGPONG
			_:          anim.loop_mode = Animation.LOOP_NONE
	if params.has("step"):
		anim.step = float(params["step"])

	return {"success": true, "data": {"full_name": ar.full_name, "length": anim.length, "loop_mode": anim.loop_mode}}


func delete_animation(params: Dictionary) -> Dictionary:
	"""Remove an animation from a library."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var anim_name = params.get("animation_name", "")
	var lib_name  = params.get("library_name", "")

	if not player.has_animation_library(lib_name):
		return {"success": false, "error": "Library not found: " + lib_name}

	var lib = player.get_animation_library(lib_name)
	if not lib.has_animation(anim_name):
		return {"success": false, "error": "Animation not found: " + anim_name}

	lib.remove_animation(anim_name)
	print("[Animation] Deleted: ", lib_name + "/" + anim_name)
	return {"success": true}


# ── Track Management ──────────────────────────────────────────────────────────

func add_animation_track(params: Dictionary) -> Dictionary:
	"""Add a new track to an Animation. Returns the new track index."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_type = params.get("track_type", "value")
	var track_path = params.get("track_path", "")   # e.g. "Skeleton3D:position" or "Armature/BoneAttach:transform"
	var interp     = params.get("interpolation", "linear")

	var type_enum = _track_type_to_enum(track_type)
	if type_enum == -1:
		return {"success": false, "error": "Unknown track_type '%s'. Valid: value/method/bezier/position_3d/rotation_3d/scale_3d/blend_shape/audio/animation" % track_type}

	var track_idx = anim.add_track(type_enum)

	if track_path != "":
		anim.track_set_path(track_idx, NodePath(track_path))

	var interp_enum = _interp_to_enum(interp)
	if interp_enum != -1 and type_enum in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER]:
		anim.track_set_interpolation_type(track_idx, interp_enum)

	print("[Animation] Added %s track [%d] path='%s' in '%s'" % [track_type, track_idx, track_path, ar.full_name])
	return {
		"success": true,
		"data": {
			"track_index": track_idx,
			"track_type": track_type,
			"track_path": track_path,
			"animation": ar.full_name
		}
	}


func remove_animation_track(params: Dictionary) -> Dictionary:
	"""Remove a track by index from an Animation."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range (0–%d)" % [track_idx, anim.get_track_count() - 1]}

	anim.remove_track(track_idx)
	print("[Animation] Removed track %d from '%s'" % [track_idx, ar.full_name])
	return {"success": true, "data": {"removed_track_index": track_idx, "remaining_tracks": anim.get_track_count()}}


func set_track_path(params: Dictionary) -> Dictionary:
	"""Set or change the node:property path of a track."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx  = int(params.get("track_index", -1))
	var track_path = params.get("track_path", "")

	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}
	if track_path == "":
		return {"success": false, "error": "track_path is required"}

	anim.track_set_path(track_idx, NodePath(track_path))
	return {"success": true, "data": {"track_index": track_idx, "track_path": track_path}}


func get_track_info(params: Dictionary) -> Dictionary:
	"""Get full info about a track: type, path, interpolation, and all keyframes."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", -1))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}

	var track_type = anim.track_get_type(track_idx)
	var keys = []
	for k in range(anim.track_get_key_count(track_idx)):
		var entry = {
			"index": k,
			"time": anim.track_get_key_time(track_idx, k),
			"transition": anim.track_get_key_transition(track_idx, k)
		}
		# Value tracks carry an explicit value; others have specialized accessors
		if track_type in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER,
						  Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
						  Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]:
			entry["value"] = _variant_to_json(anim.track_get_key_value(track_idx, k))
		keys.append(entry)

	return {
		"success": true,
		"data": {
			"track_index": track_idx,
			"type": _enum_to_track_type(track_type),
			"path": str(anim.track_get_path(track_idx)),
			"enabled": anim.track_is_enabled(track_idx),
			"interpolation": _enum_to_interp(anim.track_get_interpolation_type(track_idx)),
			"key_count": anim.track_get_key_count(track_idx),
			"keys": keys
		}
	}


func set_track_interpolation(params: Dictionary) -> Dictionary:
	"""Set interpolation mode on a VALUE or BEZIER track."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", -1))
	var interp    = params.get("interpolation", "linear")

	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}

	var interp_enum = _interp_to_enum(interp)
	if interp_enum == -1:
		return {"success": false, "error": "Unknown interpolation '%s'. Valid: nearest/linear/cubic/linear_angle/cubic_angle" % interp}

	anim.track_set_interpolation_type(track_idx, interp_enum)
	return {"success": true, "data": {"track_index": track_idx, "interpolation": interp}}


# ── Keyframe Management ───────────────────────────────────────────────────────

func add_keyframe(params: Dictionary) -> Dictionary:
	"""Insert a keyframe at a given time on a track. Value is auto-coerced to the right Godot type."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx  = int(params.get("track_index", 0))
	var time       = float(params.get("time", 0.0))
	var raw_value  = params.get("value")
	var transition = float(params.get("transition", 1.0))

	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range (0–%d)" % [track_idx, anim.get_track_count() - 1]}

	var typed_value = _coerce_for_track(anim, track_idx, raw_value)
	var key_idx = anim.track_insert_key(track_idx, time, typed_value, transition)

	print("[Animation] Keyframe added: track=%d t=%.3f val=%s in '%s'" % [track_idx, time, str(typed_value), ar.full_name])
	return {
		"success": true,
		"data": {
			"key_index": key_idx,
			"time": time,
			"value": _variant_to_json(typed_value),
			"track_index": track_idx,
			"animation": ar.full_name
		}
	}


func remove_keyframe(params: Dictionary) -> Dictionary:
	"""Remove a keyframe by index, or by nearest time if key_index is omitted."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", 0))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}

	var key_idx = -1
	if params.has("key_index"):
		key_idx = int(params["key_index"])
	elif params.has("time"):
		# Find nearest key to specified time
		var t = float(params["time"])
		key_idx = anim.track_find_key(track_idx, t, Animation.FIND_MODE_NEAREST)

	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"success": false, "error": "key_index %d out of range on track %d" % [key_idx, track_idx]}

	var removed_time = anim.track_get_key_time(track_idx, key_idx)
	anim.track_remove_key(track_idx, key_idx)
	return {"success": true, "data": {"removed_key_index": key_idx, "removed_time": removed_time, "track_index": track_idx}}


func set_keyframe_value(params: Dictionary) -> Dictionary:
	"""Update the value of an existing keyframe."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", 0))
	var key_idx   = int(params.get("key_index", 0))
	var raw_value = params.get("value")

	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}
	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"success": false, "error": "key_index %d out of range on track %d" % [key_idx, track_idx]}

	var typed_value = _coerce_for_track(anim, track_idx, raw_value)
	anim.track_set_key_value(track_idx, key_idx, typed_value)

	return {"success": true, "data": {"track_index": track_idx, "key_index": key_idx, "value": _variant_to_json(typed_value)}}


func set_keyframe_time(params: Dictionary) -> Dictionary:
	"""Move a keyframe to a new time position."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", 0))
	var key_idx   = int(params.get("key_index", 0))
	var new_time  = float(params.get("time", 0.0))

	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}
	if key_idx < 0 or key_idx >= anim.track_get_key_count(track_idx):
		return {"success": false, "error": "key_index %d out of range" % key_idx}

	var old_time = anim.track_get_key_time(track_idx, key_idx)
	anim.track_set_key_time(track_idx, key_idx, new_time)
	return {"success": true, "data": {"track_index": track_idx, "key_index": key_idx, "old_time": old_time, "new_time": new_time}}


func get_keyframes(params: Dictionary) -> Dictionary:
	"""List all keyframes on a track with time, value, and transition."""
	var r = _get_player(params)
	if not r.success: return r
	var player: AnimationPlayer = r.player

	var ar = _get_anim(player, params.get("animation_name", ""), params.get("library_name", ""))
	if not ar.success: return ar
	var anim: Animation = ar.animation

	var track_idx = int(params.get("track_index", 0))
	if track_idx < 0 or track_idx >= anim.get_track_count():
		return {"success": false, "error": "track_index %d out of range" % track_idx}

	var keys = []
	var count = anim.track_get_key_count(track_idx)
	var track_type = anim.track_get_type(track_idx)

	for k in range(count):
		var entry = {
			"index": k,
			"time": anim.track_get_key_time(track_idx, k),
			"transition": anim.track_get_key_transition(track_idx, k),
		}
		if track_type in [Animation.TYPE_VALUE, Animation.TYPE_BEZIER,
						  Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
						  Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE]:
			entry["value"] = _variant_to_json(anim.track_get_key_value(track_idx, k))
		keys.append(entry)

	return {
		"success": true,
		"data": {
			"track_index": track_idx,
			"type": _enum_to_track_type(track_type),
			"path": str(anim.track_get_path(track_idx)),
			"key_count": count,
			"keys": keys
		}
	}


# ── AnimationTree ─────────────────────────────────────────────────────────────

func setup_animation_tree(params: Dictionary) -> Dictionary:
	"""Create an AnimationTree node (with StateMachine or BlendTree root) attached to a parent.
	   Wires its anim_player to the given AnimationPlayer path."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var parent_path  = params.get("parent_path", "")
	var player_path  = params.get("player_path", "AnimationPlayer")
	var tree_type    = params.get("tree_type", "state_machine")  # state_machine / blend_tree
	var tree_name    = params.get("tree_name", "AnimationTree")

	var parent = root.get_node_or_null(parent_path) if parent_path != "" else root
	if not parent:
		return {"success": false, "error": "Parent node not found: " + parent_path}

	# Verify the AnimationPlayer exists
	var ap_node = root.get_node_or_null(player_path)
	if not ap_node or not ap_node is AnimationPlayer:
		return {"success": false, "error": "AnimationPlayer not found at: " + player_path}

	var tree = AnimationTree.new()
	tree.name = tree_name
	parent.add_child(tree)
	tree.owner = root

	# Set anim_player using a relative path from tree to player
	tree.anim_player = tree.get_path_to(ap_node)

	# Set root node type
	var tree_root: AnimationRootNode
	match tree_type:
		"blend_tree":    tree_root = AnimationNodeBlendTree.new()
		_:               tree_root = AnimationNodeStateMachine.new()

	tree.tree_root = tree_root
	tree.active    = true

	print("[Animation] Created AnimationTree '%s' (type=%s) → player=%s" % [tree_name, tree_type, player_path])
	return {
		"success": true,
		"data": {
			"tree_path": str(tree.get_path()),
			"tree_type": tree_type,
			"player_path": player_path,
			"active": true
		}
	}


func add_state_to_machine(params: Dictionary) -> Dictionary:
	"""Add an AnimationNodeAnimation (or sub-machine) to an AnimationNodeStateMachine."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var tree_path  = params.get("tree_path", "AnimationTree")
	var state_name = params.get("state_name", "")
	var anim_name  = params.get("animation_name", "")  # animation to play in this state
	var position_x = float(params.get("position_x", 0.0))
	var position_y = float(params.get("position_y", 0.0))

	if state_name == "":
		return {"success": false, "error": "state_name is required"}

	var tree = root.get_node_or_null(tree_path)
	if not tree or not tree is AnimationTree:
		return {"success": false, "error": "AnimationTree not found at: " + tree_path}

	if not tree.tree_root is AnimationNodeStateMachine:
		return {"success": false, "error": "tree_root is not an AnimationNodeStateMachine (it's %s)" % tree.tree_root.get_class()}

	var sm: AnimationNodeStateMachine = tree.tree_root

	if sm.has_node(state_name):
		return {"success": false, "error": "State '%s' already exists in state machine" % state_name}

	var node: AnimationNode
	var node_type = params.get("node_type", "animation")  # animation / state_machine / blend_space_1d / blend_space_2d
	match node_type:
		"state_machine":   node = AnimationNodeStateMachine.new()
		"blend_space_1d":  node = AnimationNodeBlendSpace1D.new()
		"blend_space_2d":  node = AnimationNodeBlendSpace2D.new()
		_:
			node = AnimationNodeAnimation.new()
			if anim_name != "":
				node.animation = anim_name

	sm.add_node(state_name, node, Vector2(position_x, position_y))

	print("[Animation] Added state '%s' (%s) to StateMachine" % [state_name, node_type])
	return {
		"success": true,
		"data": {
			"state_name": state_name,
			"node_type": node_type,
			"animation_name": anim_name,
			"position": [position_x, position_y]
		}
	}


func connect_states(params: Dictionary) -> Dictionary:
	"""Connect two states in an AnimationNodeStateMachine with a transition."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var tree_path    = params.get("tree_path", "AnimationTree")
	var from_state   = params.get("from_state", "")
	var to_state     = params.get("to_state", "")
	var switch_mode  = params.get("switch_mode", "immediate")  # immediate / sync / at_end
	var auto_advance = bool(params.get("auto_advance", false))

	if from_state == "" or to_state == "":
		return {"success": false, "error": "from_state and to_state are required"}

	var tree = root.get_node_or_null(tree_path)
	if not tree or not tree is AnimationTree:
		return {"success": false, "error": "AnimationTree not found at: " + tree_path}

	if not tree.tree_root is AnimationNodeStateMachine:
		return {"success": false, "error": "tree_root is not an AnimationNodeStateMachine"}

	var sm: AnimationNodeStateMachine = tree.tree_root

	if not sm.has_node(from_state):
		return {"success": false, "error": "State '%s' not found in state machine" % from_state}
	if not sm.has_node(to_state):
		return {"success": false, "error": "State '%s' not found in state machine" % to_state}

	var transition = AnimationNodeStateMachineTransition.new()
	match switch_mode:
		"sync":    transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_SYNC
		"at_end":  transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		_:         transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE

	transition.advance_mode = (
		AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		if auto_advance else
		AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
	)

	sm.add_transition(from_state, to_state, transition)

	print("[Animation] Connected states: %s → %s (%s)" % [from_state, to_state, switch_mode])
	return {
		"success": true,
		"data": {
			"from": from_state,
			"to": to_state,
			"switch_mode": switch_mode,
			"auto_advance": auto_advance
		}
	}


func set_blend_parameter(params: Dictionary) -> Dictionary:
	"""Set a parameter on an AnimationTree (e.g. blend position, transition index).
	   Parameter path format: 'parameters/StateMachine/blend_position' """
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var tree_path  = params.get("tree_path", "AnimationTree")
	var param_path = params.get("parameter_path", "")
	var value      = params.get("value")

	if param_path == "":
		return {"success": false, "error": "parameter_path is required (e.g. 'parameters/playback' or 'parameters/BlendSpace2D/blend_position')"}

	var tree = root.get_node_or_null(tree_path)
	if not tree or not tree is AnimationTree:
		return {"success": false, "error": "AnimationTree not found at: " + tree_path}

	# Coerce common parameter values
	var coerced = value
	if value is Array:
		match value.size():
			2: coerced = Vector2(value[0], value[1])
			3: coerced = Vector3(value[0], value[1], value[2])

	tree.set(param_path, coerced)

	return {
		"success": true,
		"data": {"parameter_path": param_path, "value": _variant_to_json(coerced)}
	}


func travel_to_state(params: Dictionary) -> Dictionary:
	"""Trigger a state machine travel() to reach a target state. Requires scene to be playing."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var tree_path   = params.get("tree_path", "AnimationTree")
	var target      = params.get("target_state", "")
	var playback_param = params.get("playback_param", "parameters/playback")

	if target == "":
		return {"success": false, "error": "target_state is required"}

	var tree = root.get_node_or_null(tree_path)
	if not tree or not tree is AnimationTree:
		return {"success": false, "error": "AnimationTree not found at: " + tree_path}

	if not tree.active:
		return {"success": false, "error": "AnimationTree is not active. Set active=true first."}

	var playback = tree.get(playback_param)
	if not playback:
		return {"success": false, "error": "Playback not found at '%s'. Is the tree active and state machine running?" % playback_param}

	playback.travel(target)

	print("[Animation] Travel to state: ", target)
	return {"success": true, "data": {"target_state": target, "playback_param": playback_param}}
