@tool
extends Node

## Audio Operations for Claude-GoDot-MCP
## Covers AudioStreamPlayer3D creation, playback control, and AudioServer bus management.

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


func _is_audio_player(node: Node) -> bool:
	return node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D


# ── Audio Tools ───────────────────────────────────────────────────────────────

func create_audio_player_3d(params: Dictionary) -> Dictionary:
	"""Create an AudioStreamPlayer3D with optional stream and full 3D audio config."""
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}

	var parent_path  = params.get("parent_path", "")
	var player_name  = params.get("player_name", "AudioStreamPlayer3D")
	var stream_path  = params.get("stream_path", "")

	var parent = root.get_node_or_null(parent_path) if parent_path != "" else root
	if not parent:
		return {"success": false, "error": "Parent not found: " + parent_path}

	var player = AudioStreamPlayer3D.new()
	player.name = player_name

	# Load audio stream
	if stream_path != "":
		if ResourceLoader.exists(stream_path):
			player.stream = load(stream_path)
		else:
			return {"success": false, "error": "Audio stream not found: " + stream_path}

	# 3D audio properties
	if params.has("unit_size"):      player.unit_size = float(params["unit_size"])
	if params.has("max_distance"):   player.max_distance = float(params["max_distance"])
	if params.has("volume_db"):      player.volume_db = float(params["volume_db"])
	if params.has("pitch_scale"):    player.pitch_scale = float(params["pitch_scale"])
	if params.has("bus"):            player.bus = params["bus"]
	if params.has("autoplay"):       player.autoplay = bool(params["autoplay"])
	if params.has("max_polyphony"):  player.max_polyphony = int(params["max_polyphony"])

	# Attenuation model
	if params.has("attenuation_model"):
		match str(params["attenuation_model"]).to_lower():
			"inverse_distance": player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
			"inverse_square":   player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
			"logarithmic":      player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
			"disabled":         player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED

	parent.add_child(player)
	player.owner = root

	# Set 3D position
	if params.has("position"):
		var p = params["position"]
		if p is Array and p.size() >= 3:
			player.position = Vector3(float(p[0]), float(p[1]), float(p[2]))

	if params.get("play_immediately", false) and player.stream:
		player.play()

	print("[Audio] Created AudioStreamPlayer3D '%s' stream='%s'" % [player_name, stream_path])
	return {
		"success": true,
		"data": {
			"player_path": str(player.get_path()),
			"stream": stream_path,
			"volume_db": player.volume_db,
			"bus": player.bus
		}
	}


func play_audio(params: Dictionary) -> Dictionary:
	"""Play or resume an AudioStreamPlayer (2D, 3D, or non-spatial), optionally from a position."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not _is_audio_player(node):
		return {"success": false, "error": "Node '%s' is %s, not an AudioStreamPlayer" % [params.get("node_path"), node.get_class()]}

	var from_pos = float(params.get("from_position", 0.0))
	node.play(from_pos)
	return {"success": true, "data": {"node_path": params.get("node_path"), "from_position": from_pos, "playing": true}}


func stop_audio(params: Dictionary) -> Dictionary:
	"""Stop playback on an AudioStreamPlayer (2D, 3D, or non-spatial)."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not _is_audio_player(node):
		return {"success": false, "error": "Node is not an AudioStreamPlayer"}

	node.stop()
	return {"success": true, "data": {"node_path": params.get("node_path"), "playing": false}}


func set_audio_property(params: Dictionary) -> Dictionary:
	"""Set a property on any AudioStreamPlayer. Common: volume_db, pitch_scale, bus, unit_size, max_distance, autoplay."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not _is_audio_player(node):
		return {"success": false, "error": "Node is not an AudioStreamPlayer"}

	var prop  = params.get("property", "")
	var value = params.get("value")

	if prop == "":
		return {"success": false, "error": "property is required. Common: volume_db, pitch_scale, bus, unit_size, max_distance, autoplay, stream_paused, max_polyphony, panning_strength"}

	node.set(prop, value)
	return {"success": true, "data": {"property": prop, "value": node.get(prop)}}


func get_playback_position(params: Dictionary) -> Dictionary:
	"""Get current playback position in seconds and playing state of an AudioStreamPlayer."""
	var r = _get_node(params)
	if not r.success: return r
	var node = r.node

	if not _is_audio_player(node):
		return {"success": false, "error": "Node is not an AudioStreamPlayer"}

	return {
		"success": true,
		"data": {
			"position":   node.get_playback_position(),
			"is_playing": node.is_playing(),
			"volume_db":  node.volume_db,
			"pitch_scale": node.pitch_scale,
			"bus":        node.bus,
			"stream":     str(node.stream.resource_path) if node.stream else ""
		}
	}


func set_bus_volume(params: Dictionary) -> Dictionary:
	"""Set the volume_db on a named AudioServer bus (Master, Music, SFX, etc.)."""
	var bus_name  = params.get("bus_name", "Master")
	var volume_db = float(params.get("volume_db", 0.0))

	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		# List available buses for a helpful error
		var buses = []
		for i in range(AudioServer.bus_count):
			buses.append(AudioServer.get_bus_name(i))
		return {"success": false, "error": "Bus '%s' not found. Available: %s" % [bus_name, str(buses)]}

	AudioServer.set_bus_volume_db(idx, volume_db)
	return {"success": true, "data": {"bus_name": bus_name, "volume_db": volume_db}}


func add_bus_effect(params: Dictionary) -> Dictionary:
	"""Add an AudioEffect to a named bus. Returns the effect index."""
	var bus_name    = params.get("bus_name", "Master")
	var effect_type = params.get("effect_type", "AudioEffectReverb")

	var idx = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return {"success": false, "error": "Bus '%s' not found" % bus_name}

	var effect: AudioEffect
	match effect_type:
		"AudioEffectReverb":      effect = AudioEffectReverb.new()
		"AudioEffectDelay":       effect = AudioEffectDelay.new()
		"AudioEffectCompressor":  effect = AudioEffectCompressor.new()
		"AudioEffectLimiter":     effect = AudioEffectLimiter.new()
		"AudioEffectDistortion":  effect = AudioEffectDistortion.new()
		"AudioEffectChorus":      effect = AudioEffectChorus.new()
		"AudioEffectPitchShift":  effect = AudioEffectPitchShift.new()
		"AudioEffectAmplify":     effect = AudioEffectAmplify.new()
		"AudioEffectEQ6":         effect = AudioEffectEQ6.new()
		"AudioEffectEQ10":        effect = AudioEffectEQ10.new()
		"AudioEffectEQ21":        effect = AudioEffectEQ21.new()
		_:
			return {"success": false, "error": "Unknown effect_type '%s'. Valid: AudioEffectReverb, AudioEffectDelay, AudioEffectCompressor, AudioEffectLimiter, AudioEffectDistortion, AudioEffectChorus, AudioEffectPitchShift, AudioEffectAmplify, AudioEffectEQ6/10/21" % effect_type}

	# Apply any effect-specific params passed alongside
	var skip_keys = {"bus_name": true, "effect_type": true, "node_path": true}
	for key in params:
		if not key in skip_keys:
			effect.set(key, params[key])

	AudioServer.add_bus_effect(idx, effect)
	var effect_idx = AudioServer.get_bus_effect_count(idx) - 1

	print("[Audio] Added %s to bus '%s' (effect_index=%d)" % [effect_type, bus_name, effect_idx])
	return {
		"success": true,
		"data": {
			"bus_name":    bus_name,
			"effect_type": effect_type,
			"effect_index": effect_idx
		}
	}
