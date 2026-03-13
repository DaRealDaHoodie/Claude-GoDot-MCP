@tool
extends Node

## TileMap / GridMap Operations for Claude-GoDot-MCP
## Covers painting, filling, clearing, and querying TileMap layers and GridMap cells.

var editor_interface: EditorInterface


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_tilemap(params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	var path = params.get("node_path", "")
	if path == "":
		return {"success": false, "error": "node_path is required"}
	var node = root.get_node_or_null(path)
	if not node:
		return {"success": false, "error": "Node not found: " + path}
	if not node is TileMap:
		return {"success": false, "error": "Node '%s' is %s, not TileMap" % [path, node.get_class()]}
	return {"success": true, "node": node}


func _get_gridmap(params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"success": false, "error": "No scene currently open"}
	var path = params.get("node_path", "")
	if path == "":
		return {"success": false, "error": "node_path is required"}
	var node = root.get_node_or_null(path)
	if not node:
		return {"success": false, "error": "Node not found: " + path}
	if not node is GridMap:
		return {"success": false, "error": "Node '%s' is %s, not GridMap" % [path, node.get_class()]}
	return {"success": true, "node": node}


# ── TileMap Tools ─────────────────────────────────────────────────────────────

func paint_tiles(params: Dictionary) -> Dictionary:
	"""Paint multiple cells on a TileMap layer in one call.
	   Each cell: {x, y, source_id, atlas_x, atlas_y, alternative_tile}."""
	var r = _get_tilemap(params)
	if not r.success: return r
	var tm: TileMap = r.node

	var layer     = int(params.get("layer", 0))
	var cells     = params.get("cells", [])
	var source_id = int(params.get("source_id", 0))  # default source_id for all cells
	var atlas_x   = int(params.get("atlas_x", 0))
	var atlas_y   = int(params.get("atlas_y", 0))
	var alt_tile  = int(params.get("alternative_tile", 0))

	if cells.is_empty():
		return {"success": false, "error": "cells array is required. Each entry: {x, y} with optional source_id, atlas_x, atlas_y, alternative_tile"}

	# Ensure layer exists
	while tm.get_layers_count() <= layer:
		tm.add_layer(-1)

	var painted = 0
	for cell in cells:
		var pos      = Vector2i(int(cell.get("x", 0)),       int(cell.get("y", 0)))
		var src      = int(cell.get("source_id", source_id))
		var atlas    = Vector2i(int(cell.get("atlas_x", atlas_x)), int(cell.get("atlas_y", atlas_y)))
		var alt      = int(cell.get("alternative_tile", alt_tile))
		tm.set_cell(layer, pos, src, atlas, alt)
		painted += 1

	print("[TileMap] Painted %d cells on layer %d of '%s'" % [painted, layer, params.get("node_path")])
	return {"success": true, "data": {"painted": painted, "layer": layer}}


func fill_tiles_rect(params: Dictionary) -> Dictionary:
	"""Fill a rectangular region of a TileMap layer with a single tile."""
	var r = _get_tilemap(params)
	if not r.success: return r
	var tm: TileMap = r.node

	var layer    = int(params.get("layer", 0))
	var x        = int(params.get("x", 0))
	var y        = int(params.get("y", 0))
	var width    = int(params.get("width", 1))
	var height   = int(params.get("height", 1))
	var source_id = int(params.get("source_id", 0))
	var atlas    = Vector2i(int(params.get("atlas_x", 0)), int(params.get("atlas_y", 0)))
	var alt_tile = int(params.get("alternative_tile", 0))

	if width <= 0 or height <= 0:
		return {"success": false, "error": "width and height must be positive"}

	while tm.get_layers_count() <= layer:
		tm.add_layer(-1)

	var painted = 0
	for row in range(height):
		for col in range(width):
			tm.set_cell(layer, Vector2i(x + col, y + row), source_id, atlas, alt_tile)
			painted += 1

	print("[TileMap] Filled %d×%d rect at (%d,%d) layer %d in '%s'" % [width, height, x, y, layer, params.get("node_path")])
	return {"success": true, "data": {"filled": painted, "rect": {"x": x, "y": y, "width": width, "height": height}, "layer": layer}}


func clear_tiles(params: Dictionary) -> Dictionary:
	"""Erase specific cells or clear an entire TileMap layer."""
	var r = _get_tilemap(params)
	if not r.success: return r
	var tm: TileMap = r.node

	var layer = int(params.get("layer", 0))
	var cells = params.get("cells", [])

	if layer >= tm.get_layers_count():
		return {"success": false, "error": "Layer %d does not exist (tilemap has %d layers)" % [layer, tm.get_layers_count()]}

	if cells.is_empty():
		# Clear entire layer
		tm.clear_layer(layer)
		print("[TileMap] Cleared entire layer %d in '%s'" % [layer, params.get("node_path")])
		return {"success": true, "data": {"cleared": "entire_layer", "layer": layer}}
	else:
		var erased = 0
		for cell in cells:
			tm.erase_cell(layer, Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0))))
			erased += 1
		return {"success": true, "data": {"erased": erased, "layer": layer}}


func get_cell_tile(params: Dictionary) -> Dictionary:
	"""Get the tile data at a specific TileMap cell position."""
	var r = _get_tilemap(params)
	if not r.success: return r
	var tm: TileMap = r.node

	var layer = int(params.get("layer", 0))
	var x     = int(params.get("x", 0))
	var y     = int(params.get("y", 0))
	var pos   = Vector2i(x, y)

	if layer >= tm.get_layers_count():
		return {"success": false, "error": "Layer %d does not exist" % layer}

	var source_id = tm.get_cell_source_id(layer, pos)
	if source_id == -1:
		return {"success": true, "data": {"empty": true, "x": x, "y": y, "layer": layer}}

	var atlas = tm.get_cell_atlas_coords(layer, pos)
	var alt   = tm.get_cell_alternative_tile(layer, pos)

	return {
		"success": true,
		"data": {
			"x": x, "y": y, "layer": layer,
			"source_id": source_id,
			"atlas_x": atlas.x, "atlas_y": atlas.y,
			"alternative_tile": alt,
			"empty": false
		}
	}


# ── GridMap Tools ─────────────────────────────────────────────────────────────

func set_grid_cell(params: Dictionary) -> Dictionary:
	"""Set a single GridMap cell. item_id comes from the GridMap's MeshLibrary."""
	var r = _get_gridmap(params)
	if not r.success: return r
	var gm: GridMap = r.node

	var x           = int(params.get("x", 0))
	var y           = int(params.get("y", 0))
	var z           = int(params.get("z", 0))
	var item_id     = int(params.get("item_id", 0))
	var orientation = int(params.get("orientation", 0))  # 0–23 for 24 rotations

	if item_id == -1:
		gm.set_cell_item(Vector3i(x, y, z), GridMap.INVALID_CELL_ITEM)
	else:
		gm.set_cell_item(Vector3i(x, y, z), item_id, orientation)

	return {"success": true, "data": {"x": x, "y": y, "z": z, "item_id": item_id, "orientation": orientation}}


func fill_grid_box(params: Dictionary) -> Dictionary:
	"""Fill a 3D box region of a GridMap with a single item."""
	var r = _get_gridmap(params)
	if not r.success: return r
	var gm: GridMap = r.node

	var x           = int(params.get("x", 0))
	var y           = int(params.get("y", 0))
	var z           = int(params.get("z", 0))
	var width       = int(params.get("width", 1))
	var height      = int(params.get("height", 1))
	var depth       = int(params.get("depth", 1))
	var item_id     = int(params.get("item_id", 0))
	var orientation = int(params.get("orientation", 0))

	if width <= 0 or height <= 0 or depth <= 0:
		return {"success": false, "error": "width, height, depth must be positive"}

	var filled = 0
	for dx in range(width):
		for dy in range(height):
			for dz in range(depth):
				gm.set_cell_item(Vector3i(x + dx, y + dy, z + dz), item_id, orientation)
				filled += 1

	print("[GridMap] Filled %d cells (%d×%d×%d) at (%d,%d,%d) in '%s'" % [filled, width, height, depth, x, y, z, params.get("node_path")])
	return {"success": true, "data": {"filled": filled, "box": {"x": x, "y": y, "z": z, "width": width, "height": height, "depth": depth}}}


func get_grid_used_cells(params: Dictionary) -> Dictionary:
	"""List all occupied cells in a GridMap with their item IDs and orientations."""
	var r = _get_gridmap(params)
	if not r.success: return r
	var gm: GridMap = r.node

	var used = gm.get_used_cells()
	var cells = []
	for pos in used:
		var item = gm.get_cell_item(pos)
		var orient = gm.get_cell_item_orientation(pos)
		cells.append({
			"x": pos.x, "y": pos.y, "z": pos.z,
			"item_id": item,
			"orientation": orient
		})

	# Get MeshLibrary item names if available
	var item_names = {}
	if gm.mesh_library:
		for item_id in gm.mesh_library.get_item_list():
			item_names[item_id] = gm.mesh_library.get_item_name(item_id)

	return {
		"success": true,
		"data": {
			"cell_count": cells.size(),
			"cells": cells,
			"item_names": item_names
		}
	}
